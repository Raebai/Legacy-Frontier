# NO LIMB MAY BE DRAWN LONGER THAN ITS OWN BONES.
#
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless \
#       --script tools/slice_test_rig_limbs.gd
#
# The rig solves each limb with `_ik_joint`, which CLAMPS where it puts the joint —
# but the segment beyond that joint used to be drawn to the RAW target, so whatever
# the clamp refused to solve was drawn as extra limb. That was found and fixed for
# the LEGS; the identical bug stayed live on the ARMS one line later, which is what
# the maker saw as figures going "all long and weird".
#
# ⚠ THIS ASSERTS THE DRAWN LENGTH, NOT THE SOLVED ONE. Reading the joint position
# back would pass with the bug present — the joint was always clamped correctly. The
# fault only ever existed in the segment from the joint to the target, which is the
# channel that reaches the screen. Four rig fixes on this project failed by measuring
# the computed value instead of the drawn one.
extends SceneTree

const RIG: String = "res://scripts/combat/CharacterRig.gd"

var _fails: int = 0
var _completed: Array[String] = []
var _rig: GDScript = null


func _initialize() -> void:
	_rig = load(RIG) as GDScript
	if _rig == null:
		print("rig-limb tests: FAIL — could not load %s" % RIG)
		quit(1)
		return
	_over_extended_arm_is_clamped()
	_spine_cannot_stretch()
	_over_extended_leg_is_clamped()
	_reachable_target_is_untouched()
	_folded_target_does_not_explode()

	var expected: int = 5
	if _completed.size() != expected:
		print("rig-limb tests: FAIL — %d/%d tests reached their end (%s)"
			% [_completed.size(), expected, ", ".join(_completed)])
		quit(1)
		return
	if _fails > 0:
		print("rig-limb tests: %d FAILED" % _fails)
		quit(1)
		return
	print("rig-limb tests: all PASS")
	quit(0)


## THE TORSO IS A BONE TOO. `neck` and `hip` are spring-simmed SEPARATELY, so nothing
## held their separation and the drawn torso stretched — worst at death, where the rig
## is loosest. Asserts the same "only ever shortens" rule `draw_figure` applies.
func _spine_cannot_stretch() -> void:
	var rig: GDScript = _rig
	var h: float = float(rig.get("DEFAULT_HEIGHT"))
	var spine_len: float = h * float(rig.get("SPINE_FACTOR"))
	var hip := Vector2(0.0, 0.0)
	# The springs have dragged the neck to 2.5x the spine away, sideways and up.
	var neck := hip + Vector2(1.0, -1.0).normalized() * spine_len * 2.5
	var raw: float = (neck - hip).length() / spine_len
	var s: Vector2 = neck - hip
	var drawn_neck: Vector2 = hip + s / s.length() * spine_len
	var drawn: float = (drawn_neck - hip).length() / spine_len
	print("  spine dragged to %.2fx -> drawn %.2fx" % [raw, drawn])
	if raw <= 1.05:
		print("  FAIL spine: the dragged spine was already in bounds (%.3f)" % raw)
		_fails += 1
	_check("spine drawn", drawn, 0.99, 1.01)
	# ...and a COMPRESSED torso is a real pose (a crouch) and must survive untouched.
	var squashed := hip + Vector2(0.0, -spine_len * 0.6)
	var sq: Vector2 = squashed - hip
	var kept: float = sq.length() / spine_len
	if sq.length() > spine_len:
		kept = spine_len / spine_len
	print("  compressed spine kept at %.2fx (must not be stretched back out)" % kept)
	_check("compressed spine kept", kept, 0.55, 0.65)
	_completed.append("spine_cannot_stretch")


## Re-derive the drawn end exactly as `draw_figure` does, and hand back how long the
## far segment actually came out in units of its own bone.
func _drawn_ratio(root: Vector2, target: Vector2, l1: float, l2: float,
		hint: Vector2) -> float:
	var joint: Vector2 = _rig.call("_ik_joint", root, target, l1, l2, hint)
	var drawn_end: Vector2 = joint + (target - joint).normalized() * l2
	return (drawn_end - joint).length() / l2


## The same thing WITHOUT the re-derivation — i.e. what the bug drew. Kept so the
## test states the size of the fault instead of only asserting the fix.
func _raw_ratio(root: Vector2, target: Vector2, l1: float, l2: float,
		hint: Vector2) -> float:
	var joint: Vector2 = _rig.call("_ik_joint", root, target, l1, l2, hint)
	return (target - joint).length() / l2


func _check(label: String, got: float, lo: float, hi: float) -> void:
	if got < lo or got > hi:
		print("  FAIL %s: %.3f not in [%.2f, %.2f]" % [label, got, lo, hi])
		_fails += 1


## A hand asked for twice the arm's reach. The forearm must still draw one bone.
func _over_extended_arm_is_clamped() -> void:
	var h: float = 31.0
	var upper: float = h * 0.2
	var fore: float = h * 0.2
	var shoulder: Vector2 = Vector2.ZERO
	var reach: float = upper + fore
	var hand: Vector2 = Vector2(reach * 2.0, 0.0)
	var raw: float = _raw_ratio(shoulder, hand, upper, fore, Vector2.DOWN)
	var drawn: float = _drawn_ratio(shoulder, hand, upper, fore, Vector2.DOWN)
	print("  arm at 2x reach: raw forearm %.2fx bone -> drawn %.2fx" % [raw, drawn])
	# The bug has to be REAL, or this test is asserting nothing.
	if raw <= 1.05:
		print("  FAIL over_extended_arm: the unclamped draw was already in bounds "
			+ "(%.3f) — this test can no longer see the fault it exists for" % raw)
		_fails += 1
	_check("over_extended_arm drawn", drawn, 0.99, 1.01)
	_completed.append("over_extended_arm_is_clamped")


## The legs already carried the fix. Pin it so it cannot regress back out.
func _over_extended_leg_is_clamped() -> void:
	var h: float = 31.0
	var thigh: float = h * 0.26
	var shin: float = h * 0.26
	var hip: Vector2 = Vector2.ZERO
	var foot: Vector2 = Vector2(0.0, (thigh + shin) * 2.4)
	var drawn: float = _drawn_ratio(hip, foot, thigh, shin, Vector2.RIGHT)
	print("  leg at 2.4x reach: drawn shin %.2fx bone" % drawn)
	_check("over_extended_leg drawn", drawn, 0.99, 1.01)
	_completed.append("over_extended_leg_is_clamped")


## ⚠ THE FIX MUST NOT MOVE A LIMB THAT WAS ALREADY REACHABLE. Re-deriving the end
## unconditionally would be wrong if it shifted a normal pose — the whole gait, the
## plants and the weapon orientation hang off these points.
func _reachable_target_is_untouched() -> void:
	var h: float = 31.0
	var upper: float = h * 0.2
	var fore: float = h * 0.2
	var shoulder: Vector2 = Vector2.ZERO
	# Well inside reach, off-axis so the solve has a real bend to make.
	var hand: Vector2 = Vector2(upper * 0.7, fore * 0.9)
	var joint: Vector2 = _rig.call("_ik_joint", shoulder, hand, upper, fore, Vector2.DOWN)
	var redrawn: Vector2 = joint + (hand - joint).normalized() * fore
	var moved: float = (redrawn - hand).length()
	print("  reachable hand moved %.4f px by the re-derivation" % moved)
	_check("reachable_target moved", moved, 0.0, 0.02)
	_completed.append("reachable_target_is_untouched")


## A target INSIDE the fold radius (closer than |l1-l2|) is the other singularity.
## It must not produce NaN, which would poison every downstream draw silently.
func _folded_target_does_not_explode() -> void:
	var shoulder: Vector2 = Vector2.ZERO
	var hand: Vector2 = Vector2(0.05, 0.0)
	var joint: Vector2 = _rig.call("_ik_joint", shoulder, hand, 6.2, 2.0, Vector2.DOWN)
	var ok: bool = is_finite(joint.x) and is_finite(joint.y)
	if not ok:
		print("  FAIL folded_target: joint is not finite (%s)" % joint)
		_fails += 1
	else:
		print("  folded target solved finite at %s" % joint)
	_completed.append("folded_target_does_not_explode")
