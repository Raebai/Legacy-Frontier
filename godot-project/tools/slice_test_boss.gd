# Run: godot --headless --path godot-project --script tools/slice_test_boss.gd
# The Ashspire Guardian: Encounter spawns a real multi-phase Boss on BOSS floors.
# Verifies spawn/scale/clear-gate, HP-gated phase transitions + signals, per-phase
# attack sets, spectacle retargeting onto "hero", and death -> defeated + drops
# out of "enemy". Uses the _initialize/await idiom.
#
# NOTE: everything boss-specific is accessed by NAME (.get/.call/.connect) — never
# `is Boss` or `boss.method()` directly — so this test script does NOT compile-time
# depend on Boss.gd. That matters: referencing Boss at this script's compile time
# would pull its whole spell chain into early boot, before the Sfx autoload exists.
#
# ── VACUOUS-PASS ARMOUR (retrofitted; this suite was the worst one lacking it) ──
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function, and hands the caller the return type's zero value.
# This file used to be ONE long `_run()`, which made that failure mode maximally
# bad — an abort half way through skipped `_finish()` itself, so the suite never
# reached a verdict at all. And it is the only suite that walks the REAL
# Encounter -> boss spawn path, so it is the one most able to pass without testing.
#
# The fix is the house idiom: one named function per test, each recording that it
# reached its own last line, and a sweep at the end that fails BY ABSENCE. An
# aborted sub-test now returns to `_run()`, which carries on and still reports.
extends SceneTree

## Every test that must run to completion.
const TESTS: Array[String] = [
	"a_boss_floor_holds_its_guardian_behind_the_waves",
	"the_guardian_is_boss_scale",
	"phases_are_hp_gated",
	"every_phase_has_a_real_attack_set",
	"a_hero_spectacle_does_not_hurt_the_boss",
	"death_opens_the_clear_gate",
	"a_combat_floor_gets_a_scaled_down_guardian",
]

var _failed: int = 0
var _completed: Dictionary = {}

var _arena: Node2D = null
var _enc_script: GDScript = null
var _tower: Resource = null
## The guardian spawned by the first test and consumed by the next five. Every test
## that reads it guards on null and RETURNS rather than limping on — a test with no
## subject must fail by absence, not pass by having nothing to check.
var _guardian: Node = null
## The BOSS-floor colossus's HP, captured before it is killed, so the COMBAT-floor
## comparison at the end has something real to be smaller THAN. See that test.
var _colossus_hp: int = 0


func _initialize() -> void:
	_run()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_failed += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _find_boss() -> Node:
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if e.has_method("current_phase"):   # only the Boss exposes this
			return e
	return null


func _run() -> void:
	_enc_script = load("res://scripts/combat/Encounter.gd") as GDScript
	_tower = (load("res://scripts/GameState.gd") as GDScript).build_default_tower()
	_arena = Node2D.new()
	root.add_child(_arena)

	await _test_a_boss_floor_holds_its_guardian_behind_the_waves()
	await _test_the_guardian_is_boss_scale()
	await _test_phases_are_hp_gated()
	await _test_every_phase_has_a_real_attack_set()
	await _test_a_hero_spectacle_does_not_hurt_the_boss()
	await _test_death_opens_the_clear_gate()
	await _test_a_combat_floor_gets_a_scaled_down_guardian()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _failed > 0:
		printerr("Boss tests: %d FAILED" % _failed)
		quit(1)
	else:
		print("Boss tests: all PASS")
		quit(0)


# --------------------------------------------------------------------- the tests
## 1.2: the guardian arrives AFTER the last wave, not at the door.
func _test_a_boss_floor_holds_its_guardian_behind_the_waves() -> void:
	var boss_def: Resource = _tower.floors[4]
	_expect(int(boss_def.floor_type) == 2, "Ashspire floor 5 is BOSS (type 2)")
	var enc: Node = _enc_script.new()
	_arena.add_child(enc)
	enc.run_floor(boss_def)
	await process_frame
	_expect(_find_boss() == null, "no guardian while waves are still running")
	await _drain_waves(enc)
	_guardian = _find_boss()
	_expect(_guardian != null, "boss floor spawned a Boss")
	_completes("a_boss_floor_holds_its_guardian_behind_the_waves")


func _test_the_guardian_is_boss_scale() -> void:
	if _guardian == null:
		return
	_colossus_hp = int(_guardian.get("max_hp"))
	_expect(_colossus_hp >= 400, "guardian has boss-scale HP (>= 400)")
	_expect(int(_guardian.get("touch_damage")) >= 20, "guardian hits hard (touch >= 20)")
	_expect(_guardian.is_in_group("enemy"), "guardian is in 'enemy' (clear gate waits for it)")
	var rig: Node = _guardian.get_node_or_null("Rig")
	_expect(rig != null and float(rig.get("height")) > 60.0,
		"guardian rig is a colossus (height > 60)")
	_completes("the_guardian_is_boss_scale")


## Start in INTRO, then HP-gated P1 -> P2 -> P3, with the signal on each crossing.
func _test_phases_are_hp_gated() -> void:
	if _guardian == null:
		return
	_expect(int(_guardian.call("current_phase")) == 0, "guardian starts in INTRO (phase 0)")
	var seen_phases: Array = []
	_guardian.connect("phase_changed", func(p: int) -> void: seen_phases.append(p))
	_guardian.call("_enter_phase", 1)   # skip the 2.6s intro timer for the test
	_expect(int(_guardian.call("current_phase")) == 1, "entered P1")
	var mx: int = int(_guardian.get("max_hp"))
	_guardian.call("take_damage", int(mx * 0.4))
	_expect(int(_guardian.call("current_phase")) == 2, "crossing 66% HP -> P2")
	_guardian.call("take_damage", int(mx * 0.4))
	_expect(int(_guardian.call("current_phase")) == 3, "crossing 33% HP -> P3")
	_expect(seen_phases.has(2) and seen_phases.has(3), "phase_changed fired for P2 + P3")
	_completes("phases_are_hp_gated")


func _test_every_phase_has_a_real_attack_set() -> void:
	if _guardian == null:
		return
	for ph: int in [1, 2, 3]:
		_expect((_guardian.call("_phase_attack_ids", ph) as Array).size() >= 2,
			"phase %d has >= 2 attacks" % ph)
	_completes("every_phase_has_a_real_attack_set")


## A hero-targeted blast hurts a "hero", not the boss that is standing in it.
func _test_a_hero_spectacle_does_not_hurt_the_boss() -> void:
	if _guardian == null:
		return
	var stub := _HeroStub.new()
	stub.add_to_group("hero")
	_arena.add_child(stub)
	stub.global_position = Vector2(400, 300)
	var boss_hp_before: int = int(_guardian.get("hp"))
	var blast: Node = load("res://scenes/combat/BlastSpell.tscn").instantiate()
	_arena.add_child(blast)
	blast.configure({"target_group": "hero", "damage": 25, "radius": 90, "knockback": 0, "windup": 0.01})
	blast.detonate_now(Vector2(400, 300))
	await process_frame
	_expect(stub.hp < 100, "hero-targeted blast damaged the hero stub")
	_expect(int(_guardian.get("hp")) == boss_hp_before, "hero-targeted blast did NOT damage the boss")
	_completes("a_hero_spectacle_does_not_hurt_the_boss")


func _test_death_opens_the_clear_gate() -> void:
	if _guardian == null:
		return
	var was_defeated: Array = [false]
	_guardian.connect("defeated", func() -> void: was_defeated[0] = true)
	_guardian.call("take_damage", int(_guardian.get("hp")) + 10)
	await process_frame
	await process_frame
	_expect(was_defeated[0], "boss emitted 'defeated' on death")
	_expect(_find_boss() == null, "dead boss left the 'enemy' group (clear gate satisfied)")
	_completes("death_opens_the_clear_gate")


## 1.2: a COMBAT floor also ends on a guardian, scaled DOWN.
func _test_a_combat_floor_gets_a_scaled_down_guardian() -> void:
	var enc2: Node = _enc_script.new()
	_arena.add_child(enc2)
	enc2.run_floor(_tower.floors[0])
	await process_frame
	_expect(_find_boss() == null, "a COMBAT floor holds its guardian back behind the waves")
	await _drain_waves(enc2)
	var mini: Node = _find_boss()
	_expect(mini != null, "a COMBAT floor DOES get a boss once its waves are down")
	if mini != null:
		# ⚠ MEASURED AGAINST THE REAL COLOSSUS, NOT A LITERAL. This used to read
		# `< 400`, and that number was never true of the thing it was checking: a
		# floor-1 COMBAT guardian is BOSS_BASE_HP(640) * 0.80 = 512. The assertion
		# only passed when the floor-1 roll happened to land on the Scribble
		# (0.66 hp_scale -> 338), so it was a coin flip that had been green for as
		# long as nobody rolled the other side. Adding a third artist to the shallow
		# pool is what finally flipped it.
		#
		# The question worth asking is a RATIO, and it is worth asking of whatever
		# pair rolled: the shallow pool's heaviest mini is 512 and the boss-floor
		# pool's lightest colossus is 901, so this holds for every combination.
		_expect(_colossus_hp > 0, "the boss-floor colossus was measured before it died")
		_expect(int(mini.get("max_hp")) < _colossus_hp,
			"the COMBAT-floor guardian is scaled down (%d hp vs the colossus's %d)"
				% [int(mini.get("max_hp")), _colossus_hp])
		_expect(float(mini.get("body_scale")) < 1.0,
			"...and is physically smaller than the Ashspire colossus")
	_completes("a_combat_floor_gets_a_scaled_down_guardian")


# ------------------------------------------------------------------- utilities
## Kill everything the encounter spawns until it opens the boss gate. Faster than
## real time (waves spawn on a timer), so it drives _process directly rather than
## waiting the floor out; bails after a generous frame budget so a regression
## fails the suite instead of hanging it.
func _drain_waves(enc: Node) -> void:
	enc.set_process(false)   # hand-drive it, so the boss is never spawned behind our back
	for i: int in 4000:
		if int(enc.call("phase")) >= 3:   # Encounter.Phase.BOSS
			await process_frame
			return
		for e: Node in root.get_tree().get_nodes_in_group("enemy"):
			e.free()   # free(), not queue_free(): the gate re-reads the group NOW
		enc.call("_process", 0.5)
		if int(enc.call("phase")) >= 3:
			await process_frame
			return
		await process_frame
	_expect(false, "the encounter reached its boss phase within the frame budget")


## Minimal hero stand-in: a Node2D in group "hero" with hp + take_damage.
class _HeroStub extends Node2D:
	var hp: int = 100
	var max_hp: int = 100
	func take_damage(amount: int) -> void:
		hp = maxi(hp - amount, 0)
