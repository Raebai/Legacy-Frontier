# Run: godot --headless --path godot-project --script tools/slice_test_rig.gd
# CharacterRig "Stick Fight feel" additions (Task 2): the AIR jump/fall state, the
# aim-arm snapping the lead hand to the cursor angle, the foot-plant clamp, and the
# tamed spring. Everything asserted here is PURE (no tree, no physics), so it runs
# headlessly. The live foot-plant RAYCAST + the look/feel are eyeballed via the GPU
# capture (tools/verify_feel_capture.gd); this covers the math + the interface.
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
	"air_state_exists",
	"air_phase_and_looseness",
	"aim_arm_snaps_to_angle_idle",
	"aim_arm_tracks_in_air",
	"aim_arm_sim_bypass_snaps_idle",
	"aim_arm_sim_bypass_snaps_air",
	"foot_plant_clamps",
	"spring_tamed",
]

var _fails: int = 0
var _completed: Dictionary = {}

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_air_state_exists()
	_test_air_phase_and_looseness()
	_test_aim_arm_snaps_to_angle_idle()
	_test_aim_arm_tracks_in_air()
	_test_aim_arm_sim_bypass_snaps_idle()
	_test_aim_arm_sim_bypass_snaps_air()
	_test_foot_plant_clamps()
	_test_spring_tamed()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("rig tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("rig tests: all PASS")
		quit(0)
	return true


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


## The AIR state must exist on the enum (Task 6 calls play(State.AIR)); play() must
## be able to enter it from the default IDLE.
func _test_air_state_exists() -> void:
	_expect(CharacterRig.State.keys().has("AIR"), "State.AIR must exist on the enum")
	var rig := CharacterRig.new()
	rig.play(CharacterRig.State.AIR)
	_expect(rig.state == CharacterRig.State.AIR, "play(State.AIR) enters AIR")
	rig.free()
	_completes("air_state_exists")


## set_air_phase flips the rising/grounded flags, and (Task 6 reframe) AIR is a LOOSENESS
## REGIME — no canned pose. Airborne must lerp the effective spring stiffness/offset
## PARTWAY toward full limp (looser than the settled grounded value, but NOT as loose as
## a full-limp hit flop). rising is biased a touch tighter than falling; landing settles
## the looseness back to 0 promptly. Guards against a canned jump pose returning.
func _test_air_phase_and_looseness() -> void:
	var rig := CharacterRig.new()
	# Flags still toggle (Hero drives them; they only BIAS the looseness now).
	rig.set_air_phase(true, false)
	_expect(rig._air_rising and not rig._air_grounded, "set_air_phase(true,false)")
	rig.set_air_phase(false, true)
	_expect(not rig._air_rising and rig._air_grounded, "set_air_phase(false,true)")

	# Grounded/IDLE: no air looseness — the spring stays at the full settled stiffness.
	rig.play(CharacterRig.State.IDLE)
	for _i in range(20):
		rig.advance(0.016)
	_expect(is_equal_approx(rig._air_loose, 0.0), "grounded IDLE keeps air looseness at 0")

	# Airborne (falling): the spring loosens PARTWAY toward full limp.
	rig.play(CharacterRig.State.AIR)
	rig.set_air_phase(false, false)  # falling
	for _i in range(30):
		rig.advance(0.016)
	var air_loose: float = rig._air_loose
	_expect(air_loose > 0.0, "AIR loosens the spring above the grounded/settled value")
	_expect(air_loose < 1.0, "AIR is PARTIAL looseness, never full limp")
	# Effective stiffness/offset must sit STRICTLY between the settled grounded values
	# and the full-limp floor: looser than grounded, tighter than a hit-flop ragdoll.
	var air_stiff: float = lerpf(CharacterRig.STIFFNESS, CharacterRig.FULL_LIMP_STIFFNESS, air_loose)
	_expect(air_stiff < CharacterRig.STIFFNESS, "AIR effective stiffness looser than grounded")
	_expect(air_stiff > CharacterRig.FULL_LIMP_STIFFNESS, "AIR effective stiffness stiffer than full limp")
	var air_off: float = lerpf(CharacterRig.MAX_OFFSET_FACTOR, CharacterRig.FULL_LIMP_OFFSET_FACTOR, air_loose)
	_expect(air_off > CharacterRig.MAX_OFFSET_FACTOR, "AIR effective offset wider than grounded")
	_expect(air_off < CharacterRig.FULL_LIMP_OFFSET_FACTOR, "AIR effective offset tighter than full limp")

	# Rising is biased a touch tighter than falling (a coiled leap vs a loose drop).
	rig.set_air_phase(true, false)  # rising
	for _i in range(30):
		rig.advance(0.016)
	_expect(rig._air_loose < air_loose, "rising is biased tighter than falling")

	# Landing (back to a grounded state) settles the looseness to 0 promptly.
	rig.play(CharacterRig.State.IDLE)
	for _i in range(30):
		rig.advance(0.016)
	_expect(is_equal_approx(rig._air_loose, 0.0), "returning to grounded settles air looseness to 0")
	rig.free()
	_completes("air_phase_and_looseness")


## With aim_arm on, in IDLE, the drawn lead hand's angle from the shoulder equals the
## set_aim() angle (the twin-stick snap). Fresh rig -> scale.x = 1, so local == world.
func _test_aim_arm_snaps_to_angle_idle() -> void:
	var rig := CharacterRig.new()
	rig.set_aim_arm(true)  # state defaults to IDLE
	var aim: Vector2 = Vector2(0.6, -0.4).normalized()
	rig.set_aim(aim)
	var pose: Dictionary = rig._compute_pose()
	var hand_angle: float = ((pose["hand_lead"] as Vector2) - (pose["shoulder"] as Vector2)).angle()
	var diff: float = absf(angle_difference(hand_angle, aim.angle()))
	_expect(diff < 0.02, "IDLE lead hand points at aim (angle diff %.4f rad)" % diff)
	rig.free()
	_completes("aim_arm_snaps_to_angle_idle")


## The aim gate also covers AIR (extended from IDLE/RUN) — the hand tracks the cursor
## while jumping. Off-arm keeps its AIR swing (only the lead arm is aim-driven).
func _test_aim_arm_tracks_in_air() -> void:
	var rig := CharacterRig.new()
	rig.set_aim_arm(true)
	rig.play(CharacterRig.State.AIR)
	rig.set_air_phase(false, false)
	var aim: Vector2 = Vector2(-0.3, -0.7).normalized()  # up-left
	rig.set_aim(aim)
	var pose: Dictionary = rig._compute_pose()
	var hand_angle: float = ((pose["hand_lead"] as Vector2) - (pose["shoulder"] as Vector2)).angle()
	var diff: float = absf(angle_difference(hand_angle, aim.angle()))
	_expect(diff < 0.02, "AIR lead hand tracks aim (angle diff %.4f rad)" % diff)
	rig.free()
	_completes("aim_arm_tracks_in_air")


## The _compute_pose tests above only exercise the un-simmed animation TARGET. The
## actual "hand always points at the cursor" mechanism Hero relies on is the SPRING
## BYPASS inside _sim_pose() (hand_lead is overwritten with the un-lagged target
## AFTER the spring sim runs), so a fast aim swing can't smear the visible hand behind
## the cursor. Seed the sim, then deliberately displace the simulated hand_lead far
## from the aim target (as a real spring lag would), and assert _sim_pose() still
## snaps it back. This FAILS if the bypass line in _sim_pose() is removed/commented.
func _test_aim_arm_sim_bypass_snaps_idle() -> void:
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
	_expect(diff < 0.02, "IDLE sim-bypass snaps a lagged hand back to aim (angle diff %.4f rad)" % diff)
	rig.free()
	_completes("aim_arm_sim_bypass_snaps_idle")


## Same bypass, in AIR — the aim-snap gate covers AIR too (Task 6), so a jumping
## Hero's hand must also ignore the spring lag and track the cursor exactly.
func _test_aim_arm_sim_bypass_snaps_air() -> void:
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
	_expect(diff < 0.02, "AIR sim-bypass snaps a lagged hand back to aim (angle diff %.4f rad)" % diff)
	rig.free()
	_completes("aim_arm_sim_bypass_snaps_air")


## _plant_foot clamps a sinking support foot exactly onto the ground line (preserving
## x) and leaves a lifted (swing) foot untouched so the stride still reads.
func _test_foot_plant_clamps() -> void:
	var rig := CharacterRig.new()
	var planted: Vector2 = rig._plant_foot(Vector2(3.0, 15.0), 9.0)  # below the line -> plant up
	_expect(is_equal_approx(planted.y, 9.0), "sinking foot clamps to the ground line")
	_expect(is_equal_approx(planted.x, 3.0), "plant preserves the foot's x")
	var lifted: Vector2 = rig._plant_foot(Vector2(3.0, 5.0), 9.0)  # above the line -> untouched
	_expect(is_equal_approx(lifted.y, 5.0), "lifted (swing) foot keeps its natural y")
	rig.free()
	_completes("foot_plant_clamps")


## The spring is tamed enough that the resting/running pose settles (no float smear):
## stiff spring + a low max drift. Guards the Task-4 numbers against regressions.
func _test_spring_tamed() -> void:
	_expect(CharacterRig.STIFFNESS >= 150.0, "STIFFNESS raised so the pose settles")
	_expect(CharacterRig.MAX_OFFSET_FACTOR <= 0.45, "MAX_OFFSET_FACTOR lowered so limbs don't drift")
	_completes("spring_tamed")
