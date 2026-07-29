# Run: godot --headless --path godot-project --script tools/slice1_test_rig.gd
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"default_state_idle",
	"punch_one_shot_hit_frame_and_return",
	"looping_ignored_during_one_shot",
	"equipment_slot_recorded",
	"facing_flip",
]

var _fails: int = 0
var _completed: Dictionary = {}

const RigScript: GDScript = preload("res://scripts/combat/CharacterRig.gd")


func _init() -> void:
	_test_default_state_idle()
	_test_punch_one_shot_hit_frame_and_return()
	_test_looping_ignored_during_one_shot()
	_test_equipment_slot_recorded()
	_test_facing_flip()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 rig tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 rig tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _make_rig() -> CharacterRig:
	return RigScript.new()


func _test_default_state_idle() -> void:
	var rig: CharacterRig = _make_rig()
	_expect(
		rig.state == CharacterRig.State.IDLE, "default state is IDLE"
	)
	rig.free()
	_completes("default_state_idle")


func _test_punch_one_shot_hit_frame_and_return() -> void:
	var rig: CharacterRig = _make_rig()
	var hits: Array = [0]
	rig.hit_frame.connect(func() -> void: hits[0] += 1)

	rig.play(CharacterRig.State.PUNCH)
	_expect(rig.state == CharacterRig.State.PUNCH, "play(PUNCH) sets state")

	# PUNCH lasts 0.22s; hit_frame fires at ~55% (0.121s).
	rig.advance(0.05)
	_expect(hits[0] == 0, "hit_frame not yet fired at 0.05s")
	rig.advance(0.08)  # 0.13s total — past the strike moment
	_expect(hits[0] == 1, "hit_frame fired once past 55%")
	_expect(rig.state == CharacterRig.State.PUNCH, "still PUNCH mid one-shot")
	rig.advance(0.05)
	_expect(hits[0] == 1, "hit_frame does not re-fire")
	rig.advance(0.1)  # 0.28s total — past the 0.22s duration
	_expect(rig.state == CharacterRig.State.IDLE, "auto-returns to IDLE when done")

	rig.free()
	_completes("punch_one_shot_hit_frame_and_return")


func _test_looping_ignored_during_one_shot() -> void:
	var rig: CharacterRig = _make_rig()

	rig.play(CharacterRig.State.PUNCH)
	rig.play(CharacterRig.State.IDLE)
	_expect(rig.state == CharacterRig.State.PUNCH, "play(IDLE) ignored during one-shot")
	rig.play(CharacterRig.State.RUN)
	_expect(rig.state == CharacterRig.State.PUNCH, "play(RUN) ignored during one-shot")

	rig.advance(0.3)  # finish the one-shot
	rig.play(CharacterRig.State.RUN)
	_expect(rig.state == CharacterRig.State.RUN, "play(RUN) works after one-shot ends")

	rig.free()
	_completes("looping_ignored_during_one_shot")


func _test_equipment_slot_recorded() -> void:
	var rig: CharacterRig = _make_rig()

	rig.set_equipment("weapon", "sword")
	_expect(
		rig.equipment.get("weapon", "") == "sword", "set_equipment records weapon=sword"
	)
	rig.set_equipment("weapon", "")
	_expect(
		not rig.equipment.has("weapon"), "set_equipment with \"\" clears the slot"
	)

	rig.free()
	_completes("equipment_slot_recorded")


func _test_facing_flip() -> void:
	var rig: CharacterRig = _make_rig()

	rig.set_facing(Vector2.LEFT)
	_expect(rig.scale.x < 0.0, "facing LEFT flips scale.x negative")
	rig.set_facing(Vector2.RIGHT)
	_expect(rig.scale.x > 0.0, "facing RIGHT restores scale.x positive")
	rig.set_facing(Vector2.LEFT)
	rig.set_facing(Vector2.UP)
	_expect(rig.scale.x < 0.0, "facing UP (x == 0) leaves flip unchanged")

	rig.free()
	_completes("facing_flip")
