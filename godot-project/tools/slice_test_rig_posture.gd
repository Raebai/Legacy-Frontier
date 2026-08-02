# Run: godot --headless --path godot-project --script tools/slice_test_rig_posture.gd
#
# ⚠ THE REGRESSION THIS FILE EXISTS TO STOP: THE PERMANENT CROUCH.
#
# The rig drew a leg 0.48 of its height while its hip rode only 0.41 above the foot,
# so ~14% of every leg had to be folded away in the knee ON EVERY FRAME. Measured off
# the DRAWN pose by tools/rig_posture_measure.gd, the resting knee sat at 119 degrees
# against the signed-off SpikeFigure's 155, and the knee jutted 12.1% of the figure's
# height off the hip->foot line against the spike's 5.4%. Every fighter in the game —
# hero, minion, elite, boss, hub NPC — stood and walked in a groucho squat.
#
# Nothing caught it, because nothing asserted about the STANCE. The gait suite pins
# cadence, slide and lift; none of those move when the hips are 20% too low.
#
# THE RULES THIS FILE FOLLOWS, and why:
#   * ASSERT THE DRAWN CHANNEL. Every number here comes off `_sim_pose()` — what
#     `_draw()` actually renders — and the knee comes out of the SAME 2-bone IK
#     `draw_figure` solves. The walk bug survived three fixes because the tests read
#     what the gait INTENDED (`_gait_foot_world`) while the spring sim smeared what
#     was rendered. A posture test that read `_compute_pose` would repeat that.
#   * MINIMUM OCCURRENCE ON EVERYTHING. "no frame was crouched" is trivially true of
#     a rig that never produced a frame, so every bound is paired with a count.
#   * NO `failed += _test_x()`. A dead property read aborts the enclosing function and
#     evaluates to 0, which that idiom reads as "no failures" — it silently disabled
#     64 suites once. Failures accumulate on the `_failed` MEMBER and each test sets
#     its own completion sentinel, so an aborted test fails BY ABSENCE.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"
## Every rig height in the game: minion, hero, elite, boss/Guardian. Posture is a
## RATIO, so all four must produce identical numbers — a stance that only reads at
## one size is a hardcoded pixel count wearing a fraction's clothes.
const HEIGHTS: Array[float] = [18.0, 31.0, 47.0, 60.0]

## SpikeFigure's own measured stance (tools/rig_posture_measure.gd, real physics):
##   hip ride 0.5075 h | leg drawn 0.5222 h | extension 0.972 | knee 155.5 deg
## The bands below sit around those, wide enough that a deliberate re-tune toward the
## spike still passes and narrow enough that the 0.856 / 119-degree squat cannot.
const MIN_EXTENSION: float = 0.93
const MAX_EXTENSION: float = 1.00
const MIN_KNEE_DEG: float = 145.0
const MIN_HIP_RIDE: float = 0.47
## Knee jut off the hip->foot line, as a fraction of height. The spike is at 0.054,
## the pre-fix rig at 0.121.
const MAX_KNEE_OUT: float = 0.085
## The idle breath is `sin(_phase * 2) * height * 0.03`, so the head top legitimately
## wanders +/-3% of height around -0.5. Anything beyond that is the silhouette moving.
const HEAD_TOP_TOL: float = 0.045
const FOOT_TOL: float = 0.02
## The joints the sim drives, i.e. everything that is DRAWN off a simulated position.
## Mirrors CharacterRig.SIM_JOINTS; read straight from the pose dictionary.
const SIM_KEYS: Array[String] = [
	"head_center", "shoulder", "hip", "hand_lead", "hand_off", "foot_lead", "foot_off",
]

var _ran: bool = false
var _failed: int = 0
var _done: Dictionary = {}


## `_initialize` + a coroutine rather than `_process`, because the floor test below
## needs REAL physics frames (its whole point is that the rig's downward ground probe
## found a real collider). It quits itself when done.
func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_run()


func _run() -> void:
	if _ran:
		return
	_ran = true

	_test_standing_is_upright()
	_test_silhouette_extents_unchanged()
	_test_no_grounded_state_hovers()
	_test_enemy_mirrors_the_rig_skeleton()
	_test_weapon_tip_still_sits_on_the_arm()
	await _test_ragdoll_never_sinks_through_the_floor()

	const EXPECTED: Array[String] = [
		"upright", "extents", "no_hover", "enemy_mirror", "weapon_tip", "ragdoll_floor",
	]
	for key: String in EXPECTED:
		if not bool(_done.get(key, false)):
			_failed += 1
			printerr("  FAIL: test '%s' did not run to completion" % key)

	if _failed == 0:
		print("rig posture tests: all PASS")
	else:
		printerr("rig posture tests: %d FAILED" % _failed)
	quit(1 if _failed > 0 else 0)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failed += 1
		printerr("  FAIL: ", label)


## A rig detached from any scene: the ground probe finds nothing (INF), so the gait
## falls back to the figure's own standing foot line. Same fixture the gait suite
## uses, and it is what makes this measurable headlessly.
func _make_rig(h: float) -> Node2D:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", h)
	rig.call("set_grounded", true)
	rig.call("play", 0)   # State.IDLE
	return rig


func _settle(rig: Node2D, frames: int = 120) -> void:
	for _i: int in frames:
		rig.call("advance", 1.0 / 60.0)


## Posture read off ONE drawn frame. `knee` is solved with the rig's own static IK, so
## it is the joint that gets painted rather than a second implementation of it.
func _posture(rig: Node2D, h: float) -> Dictionary:
	var script: GDScript = load(RIG_PATH) as GDScript
	var consts: Dictionary = script.get_script_constant_map()
	var thigh: float = h * float(consts["THIGH_FACTOR"])
	var shin: float = h * float(consts["SHIN_FACTOR"])
	var pose: Dictionary = rig.call("_sim_pose")
	var hip: Vector2 = pose["hip"]
	var feet: Array[Vector2] = [pose["foot_lead"], pose["foot_off"]]
	var foot_y: float = maxf(feet[0].y, feet[1].y)
	var worst_deg: float = 999.0
	var worst_out: float = 0.0
	for f: Vector2 in feet:
		var knee: Vector2 = script.call("_ik_joint", hip, f, thigh, shin, Vector2.RIGHT)
		var deg: float = rad_to_deg(acos(clampf(
			(hip - knee).normalized().dot((f - knee).normalized()), -1.0, 1.0)))
		var span: Vector2 = f - hip
		var out: float = 0.0
		if span.length() > 0.0001:
			out = absf((knee - hip).dot(span.orthogonal().normalized()))
		if deg < worst_deg:
			worst_deg = deg
			worst_out = out
	return {
		"hip_ride": (foot_y - hip.y) / h,
		"extension": (foot_y - hip.y) / maxf(thigh + shin, 0.0001),
		"knee_deg": worst_deg,
		"knee_out": worst_out / h,
		"head_top": ((pose["head_center"] as Vector2).y - float(pose["r"])) / h,
		"foot": foot_y / h,
	}


## THE PIN. A standing figure reads UPRIGHT — a hair of knee for life, not a squat —
## and it does so at every rig height in the game, because posture is a ratio.
func _test_standing_is_upright() -> void:
	var samples: int = 0
	var worst_ext: float = 9.0
	var worst_knee: float = 999.0
	var worst_hip: float = 9.0
	var worst_out: float = 0.0
	for h: float in HEIGHTS:
		var rig: Node2D = _make_rig(h)
		_settle(rig)
		# A whole idle breath cycle, not one frame: the bob moves the hip by
		# height * 0.03 * 0.5 and a single sample could land anywhere in it.
		for _i: int in 90:
			rig.call("advance", 1.0 / 60.0)
			var p: Dictionary = _posture(rig, h)
			samples += 1
			worst_ext = minf(worst_ext, float(p["extension"]))
			worst_knee = minf(worst_knee, float(p["knee_deg"]))
			worst_hip = minf(worst_hip, float(p["hip_ride"]))
			worst_out = maxf(worst_out, float(p["knee_out"]))
		rig.free()
	# MINIMUM OCCURRENCE. Without this every bound below is vacuous.
	_expect(samples >= HEIGHTS.size() * 60,
		"posture was actually sampled (%d frames across %d heights)" % [samples, HEIGHTS.size()])
	_expect(worst_hip >= MIN_HIP_RIDE,
		"the hip rides high enough to stand on: %.4f h (min %.2f; pre-fix 0.411, spike 0.508)"
				% [worst_hip, MIN_HIP_RIDE])
	_expect(worst_ext >= MIN_EXTENSION and worst_ext <= MAX_EXTENSION,
		"the leg is near-straight, not folded: extension %.3f (band %.2f-%.2f; pre-fix 0.856, spike 0.972)"
				% [worst_ext, MIN_EXTENSION, MAX_EXTENSION])
	_expect(worst_knee >= MIN_KNEE_DEG,
		"the standing knee reads as a slight bend: %.1f deg (min %.0f; pre-fix 119.2, spike 155.5)"
				% [worst_knee, MIN_KNEE_DEG])
	_expect(worst_out <= MAX_KNEE_OUT,
		"the knee does not jut: %.4f h off the hip->foot line (max %.3f; pre-fix 0.121, spike 0.054)"
				% [worst_out, MAX_KNEE_OUT])
	_done["upright"] = true


## Standing the figure up must not make it TALLER. The head top stays at -height/2 and
## the feet at +height/2 — the extents Enemy's analytic hit model, the camera framing
## and every platform clearance are all built on.
func _test_silhouette_extents_unchanged() -> void:
	var samples: int = 0
	var worst_head: float = 0.0
	var worst_foot: float = 0.0
	for h: float in HEIGHTS:
		var rig: Node2D = _make_rig(h)
		_settle(rig)
		for _i: int in 90:
			rig.call("advance", 1.0 / 60.0)
			var p: Dictionary = _posture(rig, h)
			samples += 1
			worst_head = maxf(worst_head, absf(float(p["head_top"]) + 0.5))
			worst_foot = maxf(worst_foot, absf(float(p["foot"]) - 0.5))
		rig.free()
	_expect(samples >= HEIGHTS.size() * 60,
		"extents were actually sampled (%d frames)" % samples)
	_expect(worst_head <= HEAD_TOP_TOL,
		"the drawn head top stays at -height/2: worst |offset| %.4f h (max %.3f)"
				% [worst_head, HEAD_TOP_TOL])
	_expect(worst_foot <= FOOT_TOL,
		"the drawn feet stay on the foot line: worst |offset| %.4f h (max %.3f)"
				% [worst_foot, FOOT_TOL])
	_done["extents"] = true


## Raising the hip without lengthening the leg would leave the feet dangling in every
## state that does NOT go through the world-locked gait (CAST, PUNCH, HURT and the
## rest read their feet off the pose's own leg angles). That is the figure hovering
## above its own collider, and it is invisible in an idle screenshot.
func _test_no_grounded_state_hovers() -> void:
	# State: IDLE 0, RUN 1, CAST 3, PUNCH 4, HURT 6. DASH/KICK/WALL_SLIDE/AIR all
	# legitimately lift a foot or leave the ground and are excluded on purpose.
	const GROUNDED_STATES: Array[int] = [0, 1, 3, 4, 6]
	var checked: int = 0
	var worst: float = 0.0
	var worst_label: String = ""
	for h: float in HEIGHTS:
		for st: int in GROUNDED_STATES:
			var rig: Node2D = _make_rig(h)
			_settle(rig, 60)
			rig.call("play", st)
			# One-shots (CAST/PUNCH/HURT) return to IDLE, so sample INSIDE the window.
			for _i: int in 4:
				rig.call("advance", 1.0 / 60.0)
			var pose: Dictionary = rig.call("_sim_pose")
			var low: float = maxf(
				(pose["foot_lead"] as Vector2).y, (pose["foot_off"] as Vector2).y) / h
			checked += 1
			# Only HOVERING is a failure: a foot BELOW the line is clamped by the
			# ground probe in a real scene, and a lifted foot is the pose doing its job.
			var gap: float = 0.5 - low
			if gap > worst:
				worst = gap
				worst_label = "h=%.0f state=%d" % [h, st]
			rig.free()
	_expect(checked == HEIGHTS.size() * GROUNDED_STATES.size(),
		"every grounded state was checked at every height (%d)" % checked)
	_expect(worst <= 0.04,
		"no grounded state leaves the lowest foot hovering: worst %.4f h (%s, max 0.04)"
				% [worst, worst_label])
	_done["no_hover"] = true


## Enemy re-derives the hit silhouette from its OWN copy of the rig's skeleton. Those
## copies were hand-typed literals and they are exactly the pair this pass moved; a
## stale mirror is the "spells pass through the body" bug arriving by the back door.
func _test_enemy_mirrors_the_rig_skeleton() -> void:
	var rig_c: Dictionary = (load(RIG_PATH) as GDScript).get_script_constant_map()
	var enemy_c: Dictionary = (load(ENEMY_PATH) as GDScript).get_script_constant_map()
	for pair: Array in [
		["RIG_HEAD_R_FACTOR", "HEAD_R_FACTOR"],
		["RIG_HIP_Y_FACTOR", "HIP_Y_FACTOR"],
		["RIG_LEG_LEN_FACTOR", "LEG_LEN_FACTOR"],
	]:
		_expect(enemy_c.has(pair[0]) and rig_c.has(pair[1]),
			"both %s and %s exist" % [pair[0], pair[1]])
		if enemy_c.has(pair[0]) and rig_c.has(pair[1]):
			_expect(is_equal_approx(float(enemy_c[pair[0]]), float(rig_c[pair[1]])),
				"Enemy.%s (%.5f) mirrors CharacterRig.%s (%.5f)"
						% [pair[0], float(enemy_c[pair[0]]), pair[1], float(rig_c[pair[1]])])
	# The skeleton has to close: hip + resting leg must put the feet on +height/2, or
	# the hurtbox's own `feet_y` stops agreeing with the drawing.
	var closes: float = float(rig_c["HIP_Y_FACTOR"]) + float(rig_c["LEG_LEN_FACTOR"])
	_expect(absf(closes - 0.5) < 0.0001,
		"hip + resting leg puts the feet at +height/2 (%.5f)" % closes)
	# ...and the resting leg must be SHORTER than the drawn one, or there is no knee.
	_expect(float(rig_c["LEG_LEN_FACTOR"]) < float(rig_c["LEG_REACH_FACTOR"]),
		"the resting leg is shorter than the drawn leg, so a knee exists (%.4f < %.4f)"
				% [float(rig_c["LEG_LEN_FACTOR"]), float(rig_c["LEG_REACH_FACTOR"])])
	_done["enemy_mirror"] = true


## The known trap in this codebase: a mismatched skeleton means "the blade vanishes and
## every spell spawns out of the hero's navel". The muzzle is derived from the shoulder
## and the lead hand, and BOTH moved when the hip did — so pin that the tip is still
## out on the arm rather than somewhere inside the torso.
func _test_weapon_tip_still_sits_on_the_arm() -> void:
	var checked: int = 0
	for h: float in HEIGHTS:
		var rig: Node2D = _make_rig(h)
		rig.call("set_equipment", "weapon", "staff")
		_settle(rig, 60)
		var pose: Dictionary = rig.call("_sim_pose")
		var hand: Vector2 = rig.to_local(rig.call("get_lead_hand_global"))
		var tip: Vector2 = rig.to_local(rig.call("get_weapon_tip"))
		var shoulder: Vector2 = pose["shoulder"]
		var hip: Vector2 = pose["hip"]
		checked += 1
		# The hand hangs off the shoulder at arm's length (arm_len = height * 0.32),
		# solved through the same spring the drawing uses, so allow the spring's slack.
		_expect(shoulder.distance_to(hand) <= h * 0.40,
			"h=%.0f: the lead hand is within arm's reach of the shoulder (%.2f px, max %.2f)"
					% [h, shoulder.distance_to(hand), h * 0.40])
		# The staff tip is height * 0.38 past the hand, along the arm. It must be well
		# clear of the body: the navel bug is the tip landing back on the spine.
		_expect(tip.distance_to(hand) > h * 0.20,
			"h=%.0f: the staff tip stands off the hand (%.2f px, min %.2f)"
					% [h, tip.distance_to(hand), h * 0.20])
		var spine_mid: Vector2 = (Vector2(0.0, -h * 0.5 + float(pose["r"]) * 2.0) + hip) * 0.5
		_expect(tip.distance_to(spine_mid) > h * 0.25,
			"h=%.0f: the staff tip is not inside the torso (%.2f px from the spine, min %.2f)"
					% [h, tip.distance_to(spine_mid), h * 0.25])
		rig.free()
	_expect(checked == HEIGHTS.size(),
		"the weapon tip was checked at every height (%d)" % checked)
	_done["weapon_tip"] = true


## ⚠ THE RAGDOLL MUST NOT BE DRAWN THROUGH THE GROUND, AND FOR A LONG TIME IT WAS.
##
## The joint floor-clamp in `_step_sim` used to work off `_local_floor_y(pos.x)` — a
## per-joint "floor line" in the rig's OWN rotated frame. That is only exact while the
## body is near-upright, and the sprawl branch of the body spring drives the pitch to
## PRONE_LEAN (1.42 rad = 81 degrees), where the local x axis is nearly vertical in world
## terms and the whole construction stops meaning anything.
##
## MEASURED on an 84 px figure taking a knockback flop over a real floor (see
## tools/rig_ragdoll_floor_probe.gd): the lowest DRAWN joint finished 25 px UNDER the
## ground before this pass and 46 px after the springs were loosened toward the spike.
## No suite noticed, because every other rig test drives a DETACHED rig whose ground
## probe finds nothing and which therefore takes the fallback branch.
##
## So this one builds a real collider and a real physics tick, and asserts on the DRAWN
## joints. The occurrence guards matter more than usual here: "nothing sank" is trivially
## true of a rig that never went limp, never leaned, and never found the floor at all —
## which is exactly the state every other suite in this repo leaves it in.
func _test_ragdoll_never_sinks_through_the_floor() -> void:
	const FLOOR_Y: float = 400.0
	const H: float = 84.0
	var body := StaticBody2D.new()
	body.position = Vector2(300.0, FLOOR_Y + 20.0)
	body.collision_layer = 1     # CharacterRig.GROUND_MASK
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000.0, 40.0)
	cs.shape = rect
	body.add_child(cs)
	root.add_child(body)

	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", H)
	rig.position = Vector2(300.0, FLOOR_Y - H * 0.5)
	root.add_child(rig)
	rig.call("set_grounded", true)
	rig.call("play", 0)   # State.IDLE
	for _i: int in 40:
		await physics_frame

	# OCCURRENCE GUARD 1: the probe actually found the floor. Without this the rig takes
	# the detached fallback and the whole test measures nothing.
	_expect(is_finite(float(rig.get("_ground_world_y"))),
		"the rig's ground probe found the real floor (got %s)" % rig.get("_ground_world_y"))

	rig.call("play", 6)   # State.HURT
	rig.call("apply_impulse", Vector2(1.0, -0.25).normalized(), 900.0)
	rig.call("flop", 0.85, 0.45)

	var samples: int = 0
	var limp_frames: int = 0
	var max_pitch: float = 0.0
	var deepest: float = -1.0e9
	var deepest_key: String = ""
	for _i: int in 90:
		await physics_frame
		var pose: Dictionary = rig.call("_sim_pose")
		samples += 1
		if float(rig.get("_limp")) > 0.3:
			limp_frames += 1
		max_pitch = maxf(max_pitch, absf(float(rig.call("body_pitch"))))
		for k: String in SIM_KEYS:
			var wy: float = rig.to_global(pose[k] as Vector2).y
			if wy - FLOOR_Y > deepest:
				deepest = wy - FLOOR_Y
				deepest_key = k
	rig.free()
	body.free()

	_expect(samples >= 80, "the flop was actually sampled (%d frames)" % samples)
	# OCCURRENCE GUARD 2: the body genuinely went limp AND genuinely toppled. A clamp
	# that is never tested by a real sprawl is not a clamp that has been tested.
	_expect(limp_frames >= 30,
		"the body actually went limp for a real stretch (%d frames over 0.3)" % limp_frames)
	_expect(max_pitch >= 0.8,
		"the body actually toppled toward the sprawl (peak pitch %.2f rad, min 0.80)" % max_pitch)
	# THE PIN. Pre-fix this read +25 px on this exact fixture (30% of the figure).
	_expect(deepest <= H * 0.02,
		"no drawn joint is rendered through the floor: deepest '%s' %+.2f px (max %.2f)"
				% [deepest_key, deepest, H * 0.02])
	_done["ragdoll_floor"] = true
