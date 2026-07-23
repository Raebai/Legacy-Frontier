# Run: godot --headless --path godot-project --script tools/slice_test_rig.gd
# CharacterRig "Stick Fight feel" additions (Task 2): the AIR jump/fall state, the
# aim-arm snapping the lead hand to the cursor angle, the foot-plant clamp, and the
# tamed spring. Everything asserted here is PURE (no tree, no physics), so it runs
# headlessly. The live foot-plant RAYCAST + the look/feel are eyeballed via the GPU
# capture (tools/verify_feel_capture.gd); this covers the math + the interface.
extends SceneTree

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_air_state_exists()
	failed += _test_air_phase_toggle_and_pose()
	failed += _test_aim_arm_snaps_to_angle_idle()
	failed += _test_aim_arm_tracks_in_air()
	failed += _test_aim_arm_sim_bypass_snaps_idle()
	failed += _test_aim_arm_sim_bypass_snaps_air()
	failed += _test_foot_plant_clamps()
	failed += _test_spring_tamed()
	if failed > 0:
		printerr("rig tests: %d FAILED" % failed)
		quit(1)
	else:
		print("rig tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## The AIR state must exist on the enum (Task 6 calls play(State.AIR)); play() must
## be able to enter it from the default IDLE.
func _test_air_state_exists() -> int:
	var f: int = 0
	f += _expect(CharacterRig.State.keys().has("AIR"), "State.AIR must exist on the enum")
	var rig := CharacterRig.new()
	rig.play(CharacterRig.State.AIR)
	f += _expect(rig.state == CharacterRig.State.AIR, "play(State.AIR) enters AIR")
	rig.free()
	return f


## set_air_phase flips the rising/grounded flags, and the AIR pose branch actually
## differs between the rising (knees tucked) and falling (legs reaching down) phases.
func _test_air_phase_toggle_and_pose() -> int:
	var f: int = 0
	var rig := CharacterRig.new()
	rig.set_air_phase(true, false)
	f += _expect(rig._air_rising and not rig._air_grounded, "set_air_phase(true,false)")
	rig.set_air_phase(false, true)
	f += _expect(not rig._air_rising and rig._air_grounded, "set_air_phase(false,true)")
	rig.play(CharacterRig.State.AIR)
	# Rising vs falling must produce visibly different leg poses (tuck vs reach).
	rig.set_air_phase(true, false)
	var rising: Dictionary = rig._compute_pose()
	rig.set_air_phase(false, false)
	var falling: Dictionary = rig._compute_pose()
	f += _expect(
		(rising["foot_lead"] as Vector2).distance_to(falling["foot_lead"]) > 1.0,
		"AIR rising and falling foot poses must differ"
	)
	# The rising tuck lifts the lead foot HIGHER (smaller y) than the falling reach.
	f += _expect(
		(rising["foot_lead"] as Vector2).y < (falling["foot_lead"] as Vector2).y,
		"AIR rising foot tucks up above the falling reach"
	)
	rig.free()
	return f


## With aim_arm on, in IDLE, the drawn lead hand's angle from the shoulder equals the
## set_aim() angle (the twin-stick snap). Fresh rig -> scale.x = 1, so local == world.
func _test_aim_arm_snaps_to_angle_idle() -> int:
	var f: int = 0
	var rig := CharacterRig.new()
	rig.set_aim_arm(true)  # state defaults to IDLE
	var aim: Vector2 = Vector2(0.6, -0.4).normalized()
	rig.set_aim(aim)
	var pose: Dictionary = rig._compute_pose()
	var hand_angle: float = ((pose["hand_lead"] as Vector2) - (pose["shoulder"] as Vector2)).angle()
	var diff: float = absf(angle_difference(hand_angle, aim.angle()))
	f += _expect(diff < 0.02, "IDLE lead hand points at aim (angle diff %.4f rad)" % diff)
	rig.free()
	return f


## The aim gate also covers AIR (extended from IDLE/RUN) — the hand tracks the cursor
## while jumping. Off-arm keeps its AIR swing (only the lead arm is aim-driven).
func _test_aim_arm_tracks_in_air() -> int:
	var f: int = 0
	var rig := CharacterRig.new()
	rig.set_aim_arm(true)
	rig.play(CharacterRig.State.AIR)
	rig.set_air_phase(false, false)
	var aim: Vector2 = Vector2(-0.3, -0.7).normalized()  # up-left
	rig.set_aim(aim)
	var pose: Dictionary = rig._compute_pose()
	var hand_angle: float = ((pose["hand_lead"] as Vector2) - (pose["shoulder"] as Vector2)).angle()
	var diff: float = absf(angle_difference(hand_angle, aim.angle()))
	f += _expect(diff < 0.02, "AIR lead hand tracks aim (angle diff %.4f rad)" % diff)
	rig.free()
	return f


## The _compute_pose tests above only exercise the un-simmed animation TARGET. The
## actual "hand always points at the cursor" mechanism Hero relies on is the SPRING
## BYPASS inside _sim_pose() (hand_lead is overwritten with the un-lagged target
## AFTER the spring sim runs), so a fast aim swing can't smear the visible hand behind
## the cursor. Seed the sim, then deliberately displace the simulated hand_lead far
## from the aim target (as a real spring lag would), and assert _sim_pose() still
## snaps it back. This FAILS if the bypass line in _sim_pose() is removed/commented.
func _test_aim_arm_sim_bypass_snaps_idle() -> int:
	var f: int = 0
	var rig := CharacterRig.new()
	rig.set_aim_arm(true)  # state defaults to IDLE
	var aim: Vector2 = Vector2(0.6, -0.4).normalized()
	rig.set_aim(aim)
	rig.advance(0.016)  # seeds _sim (lazily, at the already aim-aligned target pose)
	# Deliberately lag the simulated hand far from the aim target (angle ~157 deg
	# away from `aim`), mimicking a spring that hasn't caught up to a fast aim swing.
	rig._sim["hand_lead"] = (rig._sim["shoulder"] as Vector2) + Vector2(-40.0, 60.0)
	var pose: Dictionary = rig._sim_pose()
	var hand_angle: float = ((pose["hand_lead"] as Vector2) - (pose["shoulder"] as Vector2)).angle()
	var diff: float = absf(angle_difference(hand_angle, aim.angle()))
	f += _expect(diff < 0.02, "IDLE sim-bypass snaps a lagged hand back to aim (angle diff %.4f rad)" % diff)
	rig.free()
	return f


## Same bypass, in AIR — the aim-snap gate covers AIR too (Task 6), so a jumping
## Hero's hand must also ignore the spring lag and track the cursor exactly.
func _test_aim_arm_sim_bypass_snaps_air() -> int:
	var f: int = 0
	var rig := CharacterRig.new()
	rig.set_aim_arm(true)
	rig.play(CharacterRig.State.AIR)
	rig.set_air_phase(false, false)
	var aim: Vector2 = Vector2(-0.3, -0.7).normalized()  # up-left
	rig.set_aim(aim)
	rig.advance(0.016)
	# Lag angle ~82 deg away from `aim` here.
	rig._sim["hand_lead"] = (rig._sim["shoulder"] as Vector2) + Vector2(50.0, -30.0)
	var pose: Dictionary = rig._sim_pose()
	var hand_angle: float = ((pose["hand_lead"] as Vector2) - (pose["shoulder"] as Vector2)).angle()
	var diff: float = absf(angle_difference(hand_angle, aim.angle()))
	f += _expect(diff < 0.02, "AIR sim-bypass snaps a lagged hand back to aim (angle diff %.4f rad)" % diff)
	rig.free()
	return f


## _plant_foot clamps a sinking support foot exactly onto the ground line (preserving
## x) and leaves a lifted (swing) foot untouched so the stride still reads.
func _test_foot_plant_clamps() -> int:
	var f: int = 0
	var rig := CharacterRig.new()
	var planted: Vector2 = rig._plant_foot(Vector2(3.0, 15.0), 9.0)  # below the line -> plant up
	f += _expect(is_equal_approx(planted.y, 9.0), "sinking foot clamps to the ground line")
	f += _expect(is_equal_approx(planted.x, 3.0), "plant preserves the foot's x")
	var lifted: Vector2 = rig._plant_foot(Vector2(3.0, 5.0), 9.0)  # above the line -> untouched
	f += _expect(is_equal_approx(lifted.y, 5.0), "lifted (swing) foot keeps its natural y")
	rig.free()
	return f


## The spring is tamed enough that the resting/running pose settles (no float smear):
## stiff spring + a low max drift. Guards the Task-4 numbers against regressions.
func _test_spring_tamed() -> int:
	var f: int = 0
	f += _expect(CharacterRig.STIFFNESS >= 150.0, "STIFFNESS raised so the pose settles")
	f += _expect(CharacterRig.MAX_OFFSET_FACTOR <= 0.45, "MAX_OFFSET_FACTOR lowered so limbs don't drift")
	return f
