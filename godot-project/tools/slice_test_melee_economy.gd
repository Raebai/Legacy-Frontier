# Run: godot --headless --path godot-project --script tools/slice_test_melee_economy.gd
#
# THE SWORD MUST NOT BE THE STRATEGY. The fun audit measured a free, unlimited,
# permanent ground sword at ~76 single-target DPS against ~32 for an Arcanist's
# entire three-spell kit, and predicted the dominant play on floors 1-4 for a
# CASTER to be "grab the sword, hold melee, cast as garnish". In a game about
# absurd magic that is the wrong dominant strategy.
#
# This suite pins the two halves of the answer:
#   1. every class's spell kit out-damages BARE FISTS on a single target, so the
#      permanent melee floor is never higher than the kit's ceiling;
#   2. the retune moved DAMAGE ONLY. `SpellTier` is derived from cast_time /
#      cooldown / mp_cost and doubles as CLASH WEIGHT in the reaction system, so a
#      damage pass that quietly moved a spell between shelves would have silently
#      re-decided every spell-vs-spell interaction it is in. Every shipped spell's
#      shelf is asserted here by name.
#
# The DPS model is the same rotation `tools/dps_sim.gd` runs (cast anything off
# cooldown, punch in the gaps) with the same per-Kind single-target hit estimates —
# see that file's header for what the model can and cannot tell you.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion
# sentinel so a test that aborts part-way fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"every_kit_beats_bare_fists",
	"hex_hits_are_per_spell_not_a_flat_fudge",
	"tiers_are_unchanged_by_the_damage_pass",
	"tier_inputs_untouched",
	"melee_constants_still_match_hero",
]

## Hero.gd's melee baseline, re-read from the file so this cannot drift.
const HERO_PATH: String = "res://scripts/combat/Hero.gd"
const MELEE_COOLDOWN: float = 0.34
const FISTS_DAMAGE: int = 14
const CAST_COOLDOWN: float = 0.35

## Same table, same reasoning, as tools/dps_sim.gd.
const SINGLE_TARGET_HITS: Dictionary = {
	"FLURRY": 3.0, "MISSILES": 2.5, "METEOR": 3.0, "TETHER": 5.0, "ZONE": 4.0,
}

## ⚠ `HEX` IS NOT IN THE TABLE ABOVE AND MUST NOT BE, AND THIS IS THE WHOLE REASON
## THIS BLOCK EXISTS.
##
## Every other row up there is keyed by KIND because a kind IS one spectacle: every
## FLURRY is `BladeFlurry`, every ZONE is `ZoneSpell`. `SpellDef.Kind.HEX` is the one
## kind that is not — it is the arm that forks on ID (`SpellCaster.HEX_SCRIPTS`), and
## after the anti-recolour pass it carries FOURTEEN different spells: eleven class
## signatures plus three floor pickups. A single `"HEX": n` row would be a hidden
## fudge applied to fourteen unrelated spectacles at once — the exact thing this
## file's own header calls out as the reason `SINGLE_TARGET_HITS` is written per-Kind
## and reviewable rather than baked into the sim.
##
## It is not a hypothetical. A flat `"HEX": 3.0` — the value that happens to make
## every class clear the floor — reports the Brawler at 88.5 dps and the Swordsaint
## at 113.6, because it multiplies a 165-damage single-body crater and a 96-damage
## single-body draw-cut by three. That is not a passing test, it is a broken model
## that passes.
##
## So: per ID, each derived from the spectacle's own constants, exactly like the
## per-Kind rows.
##   thousand_cuts  — `count` (7) cuts on ONE anchored body, then a finisher worth
##                    `ThousandCuts.FINAL_MULT` (2.4) of a cut. 7 + 2.4 = 9.4.
##   radiant_volley — `RadiantVolley.WAVES` is [5, 7, 9] = 21 parallel lances across
##                    a band ~68 px wide. A body squarely IN the band eats most of a
##                    lane-width's worth; 6 is a deliberately conservative "stood in
##                    the middle", and the edge case is genuinely 1 (that is the
##                    spell's entire design — position is the damage dial).
##   heavens_wrath  — `HeavensWrath.STRIKES` is 5, but each picks its own mark and a
##                    marked body has `MARK_TELL` (0.45 s) to leave. 3 of 5 against
##                    a target that is also trying to fight.
##   grave_tide     — the catch hit, plus the hold's drain: `HOLD_TIME` 1.7 /
##                    `DRAIN_EVERY` 0.35 ≈ 5 ticks of `DRAIN_PER_TICK` 6 = 30, which
##                    against a 118 catch is a further 0.25 of a hit. 1.25.
## Everything absent is 1.0, which is the honest answer for the single-body melee
## hexes (Iai Slash, Crescent Step, Shockwave Stomp, Meteor Fist, Shatter, Fault
## Line) and for the ones that deal no direct damage at all (Raise Thrall, Mirror
## Image, Petrify, Gravity Flip, Blood Pact — see the model's stated limitation in
## `SpellLibrary`'s DPS-floor block).
const HEX_SINGLE_TARGET_HITS: Dictionary = {
	"thousand_cuts": 9.4,
	"radiant_volley": 6.0,
	"heavens_wrath": 3.0,
	"grave_tide": 1.25,
}

## THE SHELF OF EVERY SHIPPED SPELL, by id. A damage pass must not move any of
## these — `SpellTier.of()` reads cast_time / cooldown / mp_cost and NOT damage, so
## if this table ever fails, someone changed a timing or a cost while believing they
## were changing a number, and the clash table moved with it.
const EXPECTED_TIER: Dictionary = {
	"ordinary_spell": "HEAVY", "frostpiercer": "HEAVY", "infernal_lance": "ULT",
	# ⚠ `judgment` MOVED SHELF DELIBERATELY when the fourth spell slot claimed it for
	# the Cleric: an ult may not sit in a non-ult slot, so it paid one timing to clear
	# the shelf (a 1.0 -> 0.8 s windup, written up at `_judgment()`). `blood_pact` made
	# the same move for the Swordsaint (12 -> 6.6 s cooldown) and is not listed here
	# because this table only carries spells that were shipped before it existed.
	# Every other row is still "do not touch".
	"judgment": "HEAVY", "heavens_verdict": "ULT", "meteor_sigil": "ULT",
	"thunderclap": "HEAVY", "umbral_lance": "ULT", "tempest": "ULT",
	"chain_lightning": "QUICK", "rune_orbs": "HEAVY", "blade_flurry": "QUICK",
	"blizzard": "HEAVY", "drain_tether": "HEAVY", "void_zone": "HEAVY",
	"blink_strike": "HEAVY", "rock_wall": "HEAVY", "frozen_comet": "ULT",
	# THE ANTI-RECOLOUR SIGNATURES. Every one of them declares `cast_time = 0.0` — a
	# positive cast time routes the cast through Hero's LEVITATING channel, which is
	# wrong for a stomp, a draw-cut, a dash or a tide out of the floor, and each of
	# them owns its own telegraph instead. So the five that must be ULT-shelf reach
	# it through COOLDOWN and MP only, which is exactly the "any ONE of these is
	# enough" clause in `SpellTier.of`. If one of them ever drops off the ULT shelf
	# its class's ULT SLOT becomes illegal and `slice8_test_spell_kits` goes red — so
	# these five rows are load-bearing twice over.
	"thousand_cuts": "ULT", "meteor_fist": "ULT", "fault_line": "ULT",
	"heavens_wrath": "ULT", "grave_tide": "ULT",
	"iai_slash": "HEAVY", "crescent_step": "HEAVY", "shockwave_stomp": "HEAVY",
	"radiant_volley": "HEAVY", "shatter": "HEAVY", "raise_thrall": "HEAVY",
	# ...and the two spells the pass MOVED between shelves / tables, pinned so the
	# move cannot silently undo itself:
	#   mirror_image was a Tier 2 drop and is the Arcanist's control slot now;
	#   aegis_ward was costed as an ULT (11 s cooldown) and equipped by nobody, and
	#   came down to 6.8 s so the Cleric could actually hold it in a non-ult slot.
	"mirror_image": "HEAVY", "aegis_ward": "HEAVY",
}

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_every_kit_beats_bare_fists()
	_test_hex_hits_are_per_spell_not_a_flat_fudge()
	_test_tiers_are_unchanged_by_the_damage_pass()
	_test_tier_inputs_untouched()
	_test_melee_constants_still_match_hero()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Melee economy tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Melee economy tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## THE FINDING. Bare fists are the permanent, free, unlimited melee floor; a class's
## three spell buttons must clear it on a single target, which is the BOSS case and
## the one where AoE cannot rescue a caster.
func _test_every_kit_beats_bare_fists() -> void:
	var fists_dps: float = float(FISTS_DAMAGE) / MELEE_COOLDOWN
	for cid: int in range(SpellLibrary.CLASS_KITS.size()):
		var kit: Array = SpellLibrary.build_for_class(cid)
		_expect(kit.size() == SpellTier.SLOT_COUNT,
			"class %d carries %d spells" % [cid, SpellTier.SLOT_COUNT])
		var dps: float = _sim(kit)
		_expect(dps >= fists_dps,
			"class %d's kit does %.1f single-target dps, at or above bare fists (%.1f)"
				% [cid, dps, fists_dps])
	_completes("every_kit_beats_bare_fists")


## THE POSITIVE HALF OF THE HEX ROW, and the reason it exists: the assertion above
## is satisfiable by CHEATING. Hand every HEX spell a flat multiplier and all nine
## classes clear the floor without a single damage number being right — a flat 3.0
## reports the Brawler at 88.5 dps for a spell that hits one body once. A test that
## a fake fix can pass is not a test, so this pins the SHAPE of the estimate as well
## as its effect.
##
## Three claims, all of which a flat row would break:
##   1. The hex estimates are per-ID and the model really reads them (a table
##      nothing consults is the invariant-on-an-empty-set problem).
##   2. The single-body melee hexes score exactly ONE hit. Iai Slash, Crescent Step,
##      Shockwave Stomp, Meteor Fist, Shatter and Fault Line each resolve one damage
##      query against a given body per cast — read off their spectacles — so any
##      value above 1.0 is inventing damage that does not exist.
##   3. A hex that deals no direct damage at all contributes nothing, however many
##      "hits" it is credited with. `raise_thrall` and `mirror_image` are the two,
##      and their real contribution (a summon, a clone) is deliberately unmodelled —
##      which makes the floor conservative rather than generous.
func _test_hex_hits_are_per_spell_not_a_flat_fudge() -> void:
	var by_id: Dictionary = {}
	for s: SpellDef in SpellLibrary.build_all():
		by_id[s.id] = s
	# 1. The table is consulted at all, on a spell a class really carries.
	var cuts: Variant = by_id.get("thousand_cuts")
	_expect(cuts != null, "thousand_cuts exists in the library")
	if cuts != null:
		_expect(int(cuts.kind) == int(SpellDef.Kind.HEX), "thousand_cuts is a HEX")
		_expect(_hits(cuts) > 1.5,
			"the per-ID hex table is REACHED (thousand_cuts scores %.1f hits, not the 1.0 default)"
				% _hits(cuts))
	# 2. One body, one hit — the six that resolve a single damage query per cast.
	for id: String in ["iai_slash", "crescent_step", "shockwave_stomp", "meteor_fist",
			"shatter", "fault_line"]:
		var s2: Variant = by_id.get(id)
		_expect(s2 != null, "%s exists in the library" % id)
		if s2 == null:
			continue
		_expect(is_equal_approx(_hits(s2), 1.0),
			"%s lands ONCE on a single body (%.2f) — a flat HEX multiplier would inflate it"
				% [id, _hits(s2)])
	# 3. The unmodelled pair really do contribute zero, so the floor stays conservative.
	for id2: String in ["raise_thrall", "mirror_image"]:
		var s3: Variant = by_id.get(id2)
		_expect(s3 != null, "%s exists in the library" % id2)
		if s3 == null:
			continue
		_expect(int(s3.damage) == 0,
			"%s deals no DIRECT damage, so the rotation scores it zero and the floor "
				% id2 + "it clears is the conservative one")
	_completes("hex_hits_are_per_spell_not_a_flat_fudge")


## The shelf of every spell, by name. See EXPECTED_TIER.
func _test_tiers_are_unchanged_by_the_damage_pass() -> void:
	var by_id: Dictionary = {}
	for s: SpellDef in SpellLibrary.build_all():
		by_id[s.id] = s
	for id: String in EXPECTED_TIER:
		var s: Variant = by_id.get(id)
		if s == null:
			_expect(false, "spell `%s` still exists in the library" % id)
			continue
		var got: String = SpellTier.display_name(SpellTier.of(s))
		_expect(got == String(EXPECTED_TIER[id]),
			"`%s` is %s (got %s) — a timing or a cost moved, and the clash weight with it"
				% [id, String(EXPECTED_TIER[id]), got])
	_completes("tiers_are_unchanged_by_the_damage_pass")


## `SpellTier.of` must keep reading exactly the three commitment inputs. If `damage`
## ever became one of them, every future damage tune would silently be a clash tune.
func _test_tier_inputs_untouched() -> void:
	var probe := SpellDef.new()
	probe.cast_time = 0.0
	probe.cooldown = 3.0
	probe.mp_cost = 40
	var before: int = SpellTier.of(probe)
	probe.damage = 9999
	_expect(SpellTier.of(probe) == before,
		"damage is not an input to SpellTier.of (a 9999-damage spell kept its shelf)")
	probe.cooldown = SpellTier.ULT_COOLDOWN
	_expect(SpellTier.of(probe) == SpellTier.Tier.ULT, "cooldown still promotes to ULT")
	_completes("tier_inputs_untouched")


## The melee baseline this suite reasons against is Hero's, not a copy that drifted.
func _test_melee_constants_still_match_hero() -> void:
	var hero: GDScript = load(HERO_PATH) as GDScript
	_expect(hero != null, "Hero.gd loads")
	if hero != null:
		_expect(float(hero.get(&"MELEE_COOLDOWN")) == MELEE_COOLDOWN,
			"Hero.MELEE_COOLDOWN is still %.2f" % MELEE_COOLDOWN)
		_expect(int(hero.get(&"MELEE_DAMAGE")) == FISTS_DAMAGE,
			"Hero.MELEE_DAMAGE is still %d" % FISTS_DAMAGE)
		_expect(float(hero.get(&"CAST_COOLDOWN")) == CAST_COOLDOWN,
			"Hero.CAST_COOLDOWN is still %.2f" % CAST_COOLDOWN)
	_completes("melee_constants_still_match_hero")


## Spell-only rotation over 60 s: cast the biggest ready hit, never punch.
func _sim(kit: Array) -> float:
	var dt: float = 0.01
	var window: float = 60.0
	var cds: Array[float] = []
	for _s in kit:
		cds.append(0.0)
	var gcd: float = 0.0
	var busy: float = 0.0
	var total: float = 0.0
	var t: float = 0.0
	while t < window:
		if busy > 0.0:
			busy = maxf(busy - dt, 0.0)
		else:
			var best: int = -1
			var best_dmg: float = 0.0
			for i: int in range(kit.size()):
				if cds[i] > 0.0 or gcd > 0.0:
					continue
				var d: float = float(kit[i].damage) * _hits(kit[i])
				if d > best_dmg:
					best_dmg = d
					best = i
			if best >= 0:
				total += best_dmg
				cds[best] = kit[best].cooldown
				gcd = CAST_COOLDOWN
				busy = kit[best].cast_time
		for i: int in range(cds.size()):
			cds[i] = maxf(cds[i] - dt, 0.0)
		gcd = maxf(gcd - dt, 0.0)
		t += dt
	return total / window


func _hits(spell: SpellDef) -> float:
	var names: Array[String] = [
		"BEAM", "DIVINE_RAY", "NOVA", "METEOR", "CONVERGENCE", "RUSH", "BOULDER",
		"PILLAR", "WALL", "ICE_WALL", "CHAIN", "ZONE", "MISSILES", "BLINK_STRIKE",
		"TETHER", "FLURRY", "CRAWLER", "THROWN_ANCHOR", "WARD", "ARC", "HEX",
		"CATACLYSM",
	]
	if spell.kind < 0 or spell.kind >= names.size():
		return 1.0
	# HEX is the id-forked kind — fourteen spectacles behind one enum value — so it
	# is answered per ID. See HEX_SINGLE_TARGET_HITS for why a flat row would be a
	# fudge rather than an estimate.
	if names[spell.kind] == "HEX":
		return float(HEX_SINGLE_TARGET_HITS.get(spell.id, 1.0))
	return float(SINGLE_TARGET_HITS.get(names[spell.kind], 1.0))
