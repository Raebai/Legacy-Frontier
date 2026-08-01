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

## THE SHELF OF EVERY SHIPPED SPELL, by id. A damage pass must not move any of
## these — `SpellTier.of()` reads cast_time / cooldown / mp_cost and NOT damage, so
## if this table ever fails, someone changed a timing or a cost while believing they
## were changing a number, and the clash table moved with it.
const EXPECTED_TIER: Dictionary = {
	"ordinary_spell": "HEAVY", "frostpiercer": "HEAVY", "infernal_lance": "ULT",
	"judgment": "ULT", "heavens_verdict": "ULT", "meteor_sigil": "ULT",
	"thunderclap": "HEAVY", "umbral_lance": "ULT", "tempest": "ULT",
	"chain_lightning": "QUICK", "rune_orbs": "HEAVY", "blade_flurry": "QUICK",
	"blizzard": "HEAVY", "drain_tether": "HEAVY", "void_zone": "HEAVY",
	"blink_strike": "HEAVY", "rock_wall": "HEAVY", "frozen_comet": "ULT",
}

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_every_kit_beats_bare_fists()
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
	return float(SINGLE_TARGET_HITS.get(names[spell.kind], 1.0))
