# Run: godot --headless --path godot-project --script tools/slice1_test_rig.gd
extends SceneTree

const RigScript: GDScript = preload("res://scripts/combat/CharacterRig.gd")


func _init() -> void:
	var failed: int = 0
	failed += _test_default_state_idle()
	failed += _test_punch_one_shot_hit_frame_and_return()
	failed += _test_looping_ignored_during_one_shot()
	failed += _test_equipment_slot_recorded()
	failed += _test_facing_flip()
	if failed > 0:
		printerr("Slice1 rig tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 rig tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_rig() -> CharacterRig:
	return RigScript.new()


func _test_default_state_idle() -> int:
	var rig: CharacterRig = _make_rig()
	var failed: int = _expect(
		rig.state == CharacterRig.State.IDLE, "default state is IDLE"
	)
	rig.free()
	return failed


func _test_punch_one_shot_hit_frame_and_return() -> int:
	var failed: int = 0
	var rig: CharacterRig = _make_rig()
	var hits: Array = [0]
	rig.hit_frame.connect(func() -> void: hits[0] += 1)

	rig.play(CharacterRig.State.PUNCH)
	failed += _expect(rig.state == CharacterRig.State.PUNCH, "play(PUNCH) sets state")

	# PUNCH lasts 0.22s; hit_frame fires at ~55% (0.121s).
	rig.advance(0.05)
	failed += _expect(hits[0] == 0, "hit_frame not yet fired at 0.05s")
	rig.advance(0.08)  # 0.13s total — past the strike moment
	failed += _expect(hits[0] == 1, "hit_frame fired once past 55%")
	failed += _expect(rig.state == CharacterRig.State.PUNCH, "still PUNCH mid one-shot")
	rig.advance(0.05)
	failed += _expect(hits[0] == 1, "hit_frame does not re-fire")
	rig.advance(0.1)  # 0.28s total — past the 0.22s duration
	failed += _expect(rig.state == CharacterRig.State.IDLE, "auto-returns to IDLE when done")

	rig.free()
	return failed


func _test_looping_ignored_during_one_shot() -> int:
	var failed: int = 0
	var rig: CharacterRig = _make_rig()

	rig.play(CharacterRig.State.PUNCH)
	rig.play(CharacterRig.State.IDLE)
	failed += _expect(rig.state == CharacterRig.State.PUNCH, "play(IDLE) ignored during one-shot")
	rig.play(CharacterRig.State.RUN)
	failed += _expect(rig.state == CharacterRig.State.PUNCH, "play(RUN) ignored during one-shot")

	rig.advance(0.3)  # finish the one-shot
	rig.play(CharacterRig.State.RUN)
	failed += _expect(rig.state == CharacterRig.State.RUN, "play(RUN) works after one-shot ends")

	rig.free()
	return failed


func _test_equipment_slot_recorded() -> int:
	var failed: int = 0
	var rig: CharacterRig = _make_rig()

	rig.set_equipment("weapon", "sword")
	failed += _expect(
		rig.equipment.get("weapon", "") == "sword", "set_equipment records weapon=sword"
	)
	rig.set_equipment("weapon", "")
	failed += _expect(
		not rig.equipment.has("weapon"), "set_equipment with \"\" clears the slot"
	)

	rig.free()
	return failed


func _test_facing_flip() -> int:
	var failed: int = 0
	var rig: CharacterRig = _make_rig()

	rig.set_facing(Vector2.LEFT)
	failed += _expect(rig.scale.x < 0.0, "facing LEFT flips scale.x negative")
	rig.set_facing(Vector2.RIGHT)
	failed += _expect(rig.scale.x > 0.0, "facing RIGHT restores scale.x positive")
	rig.set_facing(Vector2.LEFT)
	rig.set_facing(Vector2.UP)
	failed += _expect(rig.scale.x < 0.0, "facing UP (x == 0) leaves flip unchanged")

	rig.free()
	return failed
