# Run: godot --headless --path godot-project --script tools/rig_gait_measure.gd
#   optional: ++speed=210 ++hz=60 ++skipspike=1
#
# THE INSTRUMENT FOR "WHY DOES THE WALK LOOK WRONG". Nothing here renders; it prints
# the four numbers a still frame cannot give you, for BOTH rigs at matched speeds:
#
#   cadence   steps/second. A human walks at ~2 and sprints at ~4.5. Anything past
#             ~8 is not a stride, it is a buzz — the "walking on their legs" read.
#   stride    px the body travels between consecutive plants, and the same figure
#             expressed in body-heights, which is the only cross-scale comparison
#             that means anything between an 86 px spike and a 31 px hero.
#   slide     how far the DRAWN support foot moves in world x while it bears weight.
#             The gait's `_plant_w` is world-locked by construction — that is NOT
#             what this measures. This measures the foot that is actually PAINTED,
#             after the IK has clamped it to a leg that may not reach and after the
#             spring sim has lagged it. A world-locked plant that draws 4 px away
#             from itself is still a skate on screen.
#   lift      peak height of the swing foot above the floor line, in px and as a
#             fraction of body height. Below ~4% of height a foot never visibly
#             clears the ground and the legs read as shuffling stilts.
#
# The spike figure is driven through REAL PHYSICS (its torso is a RigidBody2D), so
# its numbers are what the maker actually signed off, not an algebraic model of it.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const SPIKE_PATH: String = "res://scripts/spike/SpikeFigure.gd"
var RIG_H: float = 31.0
## head 16 + torso 26 + legs 44 — SpikeFigure.gd's own header arithmetic.
const SPIKE_H: float = 86.0
## Long enough that even a slow gait lands a double-digit number of steps.
const SECONDS: float = 3.0

var _ran: bool = false
var _speed: float = 210.0
var _hz: float = 60.0
var _skip_spike: bool = false


func _initialize() -> void:
	_parse_args()
	Engine.physics_ticks_per_second = int(_hz)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()      # coroutine; it calls quit() itself when done
	return false


func _run() -> void:
	print("[gait] --- CharacterRig h=%.0f @ %.0f px/s (%.2f body-heights/s) tick=%.0f Hz"
			% [RIG_H, _speed, _speed / RIG_H, _hz])
	_report("  rig  ", _measure_rig(_speed, 1.0 / _hz), RIG_H)
	if not _skip_spike:
		# The spike's own top speed AND the hero's, so "different rig" can be told
		# apart from "different speed".
		for sp: float in [300.0, _speed]:
			var m: Dictionary = await _measure_spike(sp)
			print("[gait] --- SpikeFigure h=%.0f @ %.0f px/s (%.2f body-heights/s) tick=%.0f Hz"
					% [SPIKE_H, sp, sp / SPIKE_H, _hz])
			_report("  spike", m, SPIKE_H)
	quit(0)


func _report(tag: String, m: Dictionary, h: float) -> void:
	if int(m["plants"]) < 2:
		printerr("%s NO STEPS — %d plants in %.1f s. Nothing to measure."
				% [tag, int(m["plants"]), SECONDS])
		return
	var extra: String = ""
	if m.has("tgt_slide"):
		extra = " | plant-only slide %.2f lift %.2f | stretch drawn %.2fx posed %.2fx (max dx local %.1f world %.1f px) | bounce %.2f px (%.1f%% h) | hip mean %.2f px | head top min %.2f px" % [
			m["tgt_slide"], m["tgt_lift"], m["stretch"], m["stretch_c"], m["max_dx"], m["max_dxw"],
			m["bounce"], 100.0 * float(m["bounce"]) / h, m["hip_mean"], m["head_top"]]
	print("%s cadence %6.2f /s | stride %6.2f px (%.3f h) | slide %5.2f px (%.1f%% h) | lift %5.2f px (%.1f%% h) | speed %6.1f px/s | plants %d%s"
			% [tag, m["cadence"], m["stride"], float(m["stride"]) / h,
				m["slide"], 100.0 * float(m["slide"]) / h,
				m["lift"], 100.0 * float(m["lift"]) / h, m["real_speed"], int(m["plants"]), extra])


## --- CharacterRig -----------------------------------------------------------
## Detached from arena geometry on purpose: the ground probe finds nothing, the gait
## falls back to the figure's own standing foot line, and the measurement is free of
## floor layout. `advance` is the rig's own manual step — the entry point every
## capture tool already uses.
func _measure_rig(speed: float, dt: float) -> Dictionary:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", RIG_H)
	rig.call("set_grounded", true)
	rig.call("play", 0)
	root.add_child(rig)
	rig.position = Vector2.ZERO
	# Settle so the ride spring's start-up transient is not read as stride bob.
	for _i: int in 30:
		rig.call("advance", dt)
	rig.call("play", 1)   # State.RUN
	# Walk a full second before the tape starts. Every metric here is a MAXIMUM, so a
	# start-from-standstill transient (the seeded stance is 1.6 px wide and the first
	# stride has to grow out of it) would otherwise be the number reported for the
	# whole run. Transients are real and worth bounding, but they are not the walk.
	for _w: int in int(1.0 / dt):
		rig.position.x += speed * dt
		rig.call("set_body_velocity", Vector2(speed, 0.0))
		rig.call("advance", dt)

	var floor_w: float = rig.global_position.y + RIG_H * 0.5
	var acc := _Accum.new()
	var tgt := _Accum.new()
	var x0: float = rig.position.x
	var stretch: float = 0.0
	var stretch_c: float = 0.0
	var max_dx: float = 0.0
	var max_dxw: float = 0.0
	var hip_sum: float = 0.0
	var hip_n: float = 0.0
	var head_top: float = INF
	var hip_lo: float = INF
	var hip_hi: float = -INF
	for _i: int in int(SECONDS / dt):
		rig.position.x += speed * dt
		rig.call("set_body_velocity", Vector2(speed, 0.0))
		rig.call("advance", dt)
		var pose: Dictionary = rig.call("_sim_pose")
		# foot 0 is `foot_lead`, foot 1 is `foot_off` — the same indexing
		# _compute_pose uses when the gait overwrites them.
		var swing: int = int(rig.get("_swing_foot"))
		var swinging: bool = float(rig.get("_swing_t")) < 1.0
		# How far the drawn foot is from the hip, against what thigh+shin can span. Over
		# 1.0 the shin is being drawn longer than it is — the rubber-leg read that a long
		# stride buys if the body does not ride down onto its legs.
		var hipl: Vector2 = pose["hip"]
		var reach: float = RIG_H * 0.48
		# Both hips: the DRAWN one (spring-simulated, what the leg is actually drawn
		# from) and the POSE one (what _compute_pose's ride dip put there). If the two
		# disagree the spring is eating the dip, which is a different bug from the
		# stride simply being longer than the leg.
		var hip_c: Vector2 = (rig.call("_compute_pose") as Dictionary)["hip"]
		for k: String in ["foot_lead", "foot_off"]:
			var f: Vector2 = pose[k]
			stretch = maxf(stretch, hipl.distance_to(f) / reach)
			stretch_c = maxf(stretch_c, hip_c.distance_to(f) / reach)
			max_dx = maxf(max_dx, absf(f.x - hip_c.x))
			# Same span measured in the WORLD frame, i.e. with the body's run-lean
			# rotation taken back out. If world dx is small and local dx is large, the
			# stretch is the PITCH tipping the figure over its own feet, not the stride.
			max_dxw = maxf(max_dxw, absf(rig.to_global(f).x - rig.global_position.x))
		# MEAN hip height and the head TOP. A ride dip that oscillates is a stride bob;
		# one that just sits low is a permanent crouch, which would shrink the silhouette
		# Enemy's hit model mirrors (head top must stay at -height/2).
		hip_sum += floor_w - rig.to_global(hip_c).y
		hip_n += 1.0
		head_top = minf(head_top, floor_w - (rig.to_global(
			(pose["head_center"] as Vector2) - Vector2(0.0, pose["r"])).y))
		# Hip height above the floor line, for the stride bounce.
		var hy: float = floor_w - rig.to_global(hipl).y
		hip_lo = minf(hip_lo, hy)
		hip_hi = maxf(hip_hi, hy)
		acc.sample(
			[rig.to_global(pose["foot_lead"] as Vector2), rig.to_global(pose["foot_off"] as Vector2)],
			swing, swinging, floor_w
		)
		# The same metrics on the gait's OWN world plants, before the spring sim and
		# the IK ever see them. Splitting the two is what says whether a slide is the
		# gait failing to lock or the DRAWING failing to follow a lock that is real.
		tgt.sample(
			[rig.call("_gait_foot_world", 0) as Vector2, rig.call("_gait_foot_world", 1) as Vector2],
			swing, swinging, floor_w
		)
	var travelled: float = rig.position.x - x0
	rig.free()
	var out: Dictionary = acc.finish(travelled, SECONDS)
	var t: Dictionary = tgt.finish(travelled, SECONDS)
	out["tgt_slide"] = t["slide"]
	out["tgt_lift"] = t["lift"]
	out["stretch"] = stretch
	out["stretch_c"] = stretch_c
	out["max_dx"] = max_dx
	out["max_dxw"] = max_dxw
	out["hip_mean"] = hip_sum / maxf(hip_n, 1.0)
	out["head_top"] = head_top
	out["bounce"] = hip_hi - hip_lo
	return out


## --- SpikeFigure ------------------------------------------------------------
## Real physics: the torso is a RigidBody2D riding a spring over a real floor, so
## this has to run in a live tree at a real tick rate.
func _measure_spike(speed: float) -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40000.0, 60.0)
	cs.shape = rect
	cs.position = Vector2(0.0, 30.0)
	body.add_child(cs)
	body.position = Vector2(0.0, 400.0)
	world.add_child(body)

	var fig: Node2D = (load(SPIKE_PATH) as GDScript).new() as Node2D
	fig.set("spawn_pos", Vector2(-6000.0, 330.0))
	fig.set("move_speed", speed)
	world.add_child(fig)
	# Settle standing, then hold right until the torso reaches terminal speed.
	for _i: int in 60:
		await physics_frame
	for _i: int in int(1.5 * _hz):
		fig.set("ctrl_move_x", 1.0)
		await physics_frame

	var acc := _Accum.new()
	var x0: float = float((fig.call("body_origin") as Vector2).x)
	for _i: int in int(SECONDS * _hz):
		fig.set("ctrl_move_x", 1.0)
		await physics_frame
		var feet: Array = fig.get("_foot")
		acc.sample(
			[feet[0] as Vector2, feet[1] as Vector2],
			int(fig.get("_swing_foot")), float(fig.get("_swing_t")) < 1.0, 400.0
		)
	var travelled: float = float((fig.call("body_origin") as Vector2).x) - x0
	world.queue_free()
	await process_frame
	return acc.finish(travelled, SECONDS)


## Shared metric accumulator so both rigs are judged by identical arithmetic.
##
## Slide is measured PER FOOT across a whole stance: the world x the foot held the
## frame it touched down, versus the furthest it drifted from that before it lifted
## again. Resetting on every swing-index change instead would reset mid-stance and
## report a fraction of the real drift.
class _Accum:
	extends RefCounted

	var plants: int = 0
	var lift: float = 0.0
	var slide: float = 0.0
	var _was_swinging: Array[bool] = [false, false]
	var _ref: Array[float] = [INF, INF]

	func sample(fw: Array, swing: int, swinging: bool, floor_w: float) -> void:
		for i: int in 2:
			var is_swinging: bool = swinging and i == swing
			var fx: float = (fw[i] as Vector2).x
			if is_swinging:
				lift = maxf(lift, floor_w - (fw[i] as Vector2).y)
				_ref[i] = INF          # airborne foot: no plant to drift from
			else:
				if _was_swinging[i] or not is_finite(_ref[i]):
					# Touch-down frame (or the very first sample): this is the plant.
					if _was_swinging[i]:
						plants += 1
					_ref[i] = fx
				else:
					slide = maxf(slide, absf(fx - _ref[i]))
			_was_swinging[i] = is_swinging

	func finish(travelled: float, seconds: float) -> Dictionary:
		return {
			"plants": plants,
			"cadence": float(plants) / seconds,
			"stride": travelled / maxf(float(plants), 1.0),
			"slide": slide,
			"lift": lift,
			"real_speed": travelled / seconds,
		}


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_user_args())
	argv.append_array(OS.get_cmdline_args())
	for raw: String in argv:
		var arg: String = raw.lstrip("+-")
		if not arg.contains("="):
			continue
		var k: String = arg.get_slice("=", 0)
		var v: String = arg.get_slice("=", 1)
		match k:
			"speed":
				_speed = float(v)
			"hz":
				_hz = float(v)
			"height":
				RIG_H = float(v)
			"skipspike":
				_skip_spike = v != "0"
