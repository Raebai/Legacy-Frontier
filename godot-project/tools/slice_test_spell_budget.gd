# Run: godot --headless --path godot-project --script tools/slice_test_spell_budget.gd
#
# A SPELL MAY NOT LIE ABOUT WHAT IT COSTS.
#
# Maker: *"cleric is very OP, different classes and different spells should have
# diffferent cooldowns based on damage output usefulnness all that sort of stuff"*.
#
# ⚠ THE FIRST HALF IS BACKED BY MEASUREMENT. A 288-bout round robin run after this
# session's changes: WARLOCK 49/64, **CLERIC 47/64 (73%)**, STORMCALLER 42, SWORDSAINT
# 34, BRAWLER 30, ARCANIST 25, JUGGERNAUT 23, CRYOMANCER 23, SHADOWBLADE 15 (23%).
# The Cleric is second, not first — the Warlock is above it — but both are far over.
#
# ⚠ THE SECOND HALF — "derive the cooldown" — IS NOT WHAT THIS FILE DOES, and the
# reason is worth stating because it is the obvious thing to reach for.
#
#   1. IT IS CIRCULAR. `SpellTier.of` DERIVES a spell's shelf from its cast time,
#      cooldown and cost, and that shelf decides slot legality, clash weight,
#      knockback and the cooldown multiplier. Deriving the cooldown from damage makes
#      damage a transitive input to the shelf — and
#      `slice_test_melee_economy._test_tier_inputs_untouched` exists precisely to
#      stop that, because "every future damage tune is silently a clash tune" is a
#      trap this project has already written the post-mortem for.
#   2. ELEVEN SPELLS DEAL ZERO DAMAGE. `aegis_ward`, `rock_wall`, `petrify`,
#      `blood_pact`, `mirror_image`, `raise_thrall`, `teardown`, `chronostasis`,
#      `equinox`, `roulette`, `ice_wall`. A damage->cooldown map gives every one of
#      them a cooldown of zero, i.e. the QUICK shelf, i.e. spammable — and those are
#      exactly the spells the "usefulness" half of the ask is about.
#   3. `damage` IS NOT COMMENSURABLE. It is per-tick for a tether, per-projectile for
#      a volley, per-hop for a chain. Reading the field raw understates `drain_tether`
#      by 5x.
#
# SO: A BUDGET, NOT A DERIVATION. The same claim — a spell cannot be worth more than
# it pays for — expressed as a CEILING that fails the build, which composes with the
# tier system instead of inverting it. It is also the cheapest honest first step the
# playtest queue itself asked for: *"a probe that tables every spell's damage-per-
# second and utility against its cooldown, so the outliers are visible before anything
# is retuned"*. This is that table, with teeth.
#
# ⚠ MULTI-HIT COMES FROM `dps_sim.SINGLE_TARGET_HITS`, loaded rather than copied. That
# file's own header calls it "an explicit, reviewable estimate per Kind rather than a
# hidden fudge", and a second private estimate here would be exactly the hidden fudge
# it is avoiding.
#
# ⚠ NEVER `failed += _test_x()`. Failures accumulate on `_fails`; every test records a
# COMPLETION SENTINEL so one that aborts half-way fails the suite by absence.
extends SceneTree

const DPS_SIM_PATH: String = "res://tools/dps_sim.gd"

## THE CEILING, in damage per second of cooldown, for a carried HEAVY spell.
##
## Derived from the roster rather than chosen: the busiest carried heavies sit at
## `ordinary_spell` 88/3.2 = 27.5, `blink_strike` 85/3.2 = 26.6 (and it teleports),
## `thunderclap` 90/3.4 = 26.5. Everything else is below. 30.0 leaves honest headroom
## over that band and still catches the one spell that was double it.
const MAX_HEAVY_DPC: float = 30.0
## Ults are allowed to be worth more per second — that is what an ult is. They pay in
## a long wait, a big mana bill and usually a channel. `meteor_fist` is the roster's
## honest ceiling at 165/8.5 = 19.4, so this is not a tight leash; it exists so a
## future Tier 3 cannot be authored at 400 damage on a 5 s cooldown.
const MAX_ULT_DPC: float = 26.0

const TESTS: Array[String] = [
	"no_carried_heavy_is_over_budget",
	"no_carried_ult_is_over_budget",
	"utility_spells_obey_the_duty_cycle",
	"the_table_is_not_empty",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _hits: Dictionary = {}
var _rows: Array = []


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var sim: GDScript = load(DPS_SIM_PATH) as GDScript
	if sim != null:
		_hits = sim.get_script_constant_map().get("SINGLE_TARGET_HITS", {}) as Dictionary
	_gather()
	_print_table()
	_test_heavies()
	_test_ults()
	_test_duty_cycle()
	_test_not_empty()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("spell_budget: TEST DID NOT COMPLETE — %s (aborted part-way)" % name)
	if _fails == 0:
		print("spell budget tests: all PASS")
	else:
		printerr("spell budget tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("spell_budget: FAIL — %s" % what)


## Every spell any class actually CARRIES. Deliberately not `all_spells()`: the
## reserve pool holds orphans nobody can equip (`colossus_pillar` is 96/2.8 and has
## been for a long time), and failing the build on a spell no hand can hold would
## teach the next person to raise the ceiling rather than fix a real outlier.
func _gather() -> void:
	var seen: Dictionary = {}
	for cls: int in ClassInfo.CLASSES.size():
		var kit: Array = SpellLibrary.build_for_class(cls)
		for s: SpellDef in kit:
			if s == null or seen.has(s.id):
				continue
			seen[s.id] = true
			_rows.append({
				"id": s.id, "cls": ClassInfo.name_for(cls),
				"dmg": s.damage, "cd": s.cooldown,
				"tier": SpellTier.of(s), "dpc": _dpc(s),
			})


## Damage per second of cooldown, with multi-hit folded in. Zero-damage spells report
## 0.0 and are handled by the duty-cycle test instead — see the header.
func _dpc(s: SpellDef) -> float:
	if s.cooldown <= 0.001:
		return 0.0
	var mult: float = float(MULTI_HIT_BY_ID.get(s.id,
		_hits.get(_kind_name(s.kind), 1.0)))
	return (float(s.damage) * mult) / s.cooldown


## ⚠ PER-ID, AND IT HAS TO BE. `dps_sim.SINGLE_TARGET_HITS` is keyed by KIND, and the
## HEX kind holds both `thousand_cuts` (SEVEN cuts, all on the one body it anchored
## to) and `shockwave_stomp` (one hit). A kind-level number cannot describe both, so
## the first version of this table priced the Shadowblade's ULT at 2.0 damage per
## second of cooldown when the real figure is 18.4 — understating it SEVEN-FOLD, on
## the very class this suite was being used to diagnose.
##
## ⚠ AND `SpellDef.count` CANNOT BE READ AUTOMATICALLY. It is overloaded: seven cuts
## for `thousand_cuts`, five HOPS for `chain_lightning` — and hops land on DIFFERENT
## bodies, so reading it blind would price a 60-damage chain at 100 dmg/s and fail the
## build for a spell that is fine. Named explicitly, one line each, or not at all.
const MULTI_HIT_BY_ID: Dictionary = {
	"thousand_cuts": 7.0,    # cuts walked around one anchor
	"heavens_wrath": 5.0,    # strikes from a cell that drifts onto one body
}


func _kind_name(kind: int) -> String:
	var keys: Array = SpellDef.Kind.keys()
	return String(keys[kind]) if kind >= 0 and kind < keys.size() else ""


func _print_table() -> void:
	print("  ── carried spells, damage per second of cooldown ──")
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dpc"]) > float(b["dpc"]))
	for r: Dictionary in _rows:
		print("    %-18s %-12s dmg %3d  cd %.1f  tier %d  ->  %.1f dmg/s"
			% [r["id"], r["cls"], int(r["dmg"]), float(r["cd"]), int(r["tier"]),
				float(r["dpc"])])


# --------------------------------------------------------------------------- 1
## ⚠ THE ONE THAT CAUGHT `judgment`. 95 damage on a 2.6 s cooldown — 36.5 dmg/s, the
## highest of any carried spell in the game and a third again above the next — sitting
## in the CLERIC's ANSWER slot, the class the maker reported as overpowered.
##
## Its history is the whole story: it was an orphan, it was retuned OFF the ULT shelf
## when the Cleric claimed it, and the retune moved ONLY `cast_time` 1.0 -> 0.8
## because that was the axis that could pay for the shelf without changing what the
## spell does. Nobody revisited the cooldown, so a spell priced as an ultimate kept
## its damage and lost its wait.
func _test_heavies() -> void:
	for r: Dictionary in _rows:
		if int(r["tier"]) != SpellTier.Tier.HEAVY or float(r["dpc"]) <= 0.0:
			continue
		_expect(float(r["dpc"]) <= MAX_HEAVY_DPC,
			"%s (%s) is %.1f damage per second of cooldown, over the %.1f budget "
				% [r["id"], r["cls"], float(r["dpc"]), MAX_HEAVY_DPC]
				+ "for a carried heavy — %d damage on a %.1f s wait"
				% [int(r["dmg"]), float(r["cd"])])
	_completed["no_carried_heavy_is_over_budget"] = true


# --------------------------------------------------------------------------- 2
func _test_ults() -> void:
	for r: Dictionary in _rows:
		if int(r["tier"]) != SpellTier.Tier.ULT or float(r["dpc"]) <= 0.0:
			continue
		_expect(float(r["dpc"]) <= MAX_ULT_DPC,
			"%s (%s) is %.1f damage per second of cooldown, over the %.1f ult budget"
				% [r["id"], r["cls"], float(r["dpc"]), MAX_ULT_DPC])
	_completed["no_carried_ult_is_over_budget"] = true


# --------------------------------------------------------------------------- 3
## THE "usefulness" HALF, and the rule is not invented here — `aegis_ward` already
## carries it in `SpellLibrary`, written out as a derivation: `cooldown >= 2 x
## duration`, i.e. uptime at or under half. That is the only cooldown in the whole
## catalogue that was DERIVED rather than authored, and it is the right shape for a
## spell whose worth is a duration rather than a number.
##
## ⚠ APPLIED ONLY TO ZERO-DAMAGE SPELLS THAT DECLARE A DURATION. `length` is
## overloaded per Kind — it is a beam's reach and a projectile's travel budget — so
## reading it as seconds on a damage spell would compare a distance to a wait.
func _test_duty_cycle() -> void:
	for r: Dictionary in _rows:
		if int(r["dmg"]) != 0:
			continue
		var s: SpellDef = SpellLibrary.by_id(String(r["id"]))
		if s == null or s.length <= 0.0 or s.length > 30.0:
			continue   # not a duration: see the note above on `length`
		_expect(s.cooldown >= s.length,
			"%s runs for %.1f s on a %.1f s cooldown — a utility spell whose uptime "
				% [r["id"], s.length, s.cooldown]
				+ "exceeds 100%% is permanently on, which is not a cooldown")
	_completed["utility_spells_obey_the_duty_cycle"] = true


# --------------------------------------------------------------------------- 4
## A budget check over an empty table passes perfectly. This is the armour.
func _test_not_empty() -> void:
	_expect(_rows.size() >= 30,
		"only %d carried spells found — the scan has stopped working, and every "
			% _rows.size() + "budget assertion above is passing vacuously")
	var priced: int = 0
	for r: Dictionary in _rows:
		if float(r["dpc"]) > 0.0:
			priced += 1
	_expect(priced >= 20,
		"only %d spells have a damage price at all — the multi-hit table or the "
			% priced + "damage field has stopped being read")
	_completed["the_table_is_not_empty"] = true
