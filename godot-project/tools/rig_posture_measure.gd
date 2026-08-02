# Run: godot --headless --path godot-project --script tools/rig_posture_measure.gd
#   optional: ++skipspike=1
#
# THE INSTRUMENT FOR "WHY IS HE CROUCHING". The companion to rig_gait_measure.gd:
# that one measures the WALK, this one measures the STANCE. Nothing renders; it
# prints the numbers a still frame cannot give you, for BOTH rigs:
#
#   hip ride    hip height above the foot line, as a fraction of body height. This
#               is how tall the figure actually stands.
#   leg drawn   thigh + shin as DRAWN, same fraction. Fixed by the constants.
#   extension   hip ride / leg drawn. 1.00 = a dead-straight stilt leg; the spike
#               sits at ~0.97 (a hair of knee for life). Anything near 0.8 means
#               ~20% of the leg has to be folded away in the knee EVERY FRAME, and
#               that is a permanent groucho crouch, not a stance.
#   knee angle  interior angle at the knee, degrees. 180 = straight.
#   knee out    how far the knee juts from the hip->foot line, px and % of height.
#               This is the thing that is actually visible.
#   head/foot   drawn head TOP and foot bottom relative to the foot line, as
#               fractions of height — the silhouette Enemy's hit model mirrors.
#               Head top must stay at -height/2 whatever the hip does.
#
# The CharacterRig is measured DETACHED (no ground probe -> it falls back to its own
# standing foot line), exactly as tools/slice_test_rig_gait.gd does, so the number is
# free of floor layout. The SpikeFigure is driven through REAL PHYSICS on a real
# floor, because its stance is the output of a ride spring and an algebraic model of
# it would be a guess about the thing being measured.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const SPIKE_PATH: String = "res://scripts/spike/SpikeFigure.gd"
## Every rig height in the game: minion, hero, elite, boss/Guardian.
const RIG_HEIGHTS: Array[float] = [18.0, 31.0, 47.0, 60.0]
## head 16 + torso 26 + legs 44 — SpikeFigure.gd's own header arithmetic.
const SPIKE_H: float = 86.0

var _ran: bool = false
var _skip_spike: bool = false


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("++skipspike="):
			_skip_spike = a.split("=")[1] != "0"
	Engine.physics_ticks_per_second = 60


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	print("[posture] --- CharacterRig, IDLE, settled")
	for h: float in RIG_HEIGHTS:
		_report("  rig h=%4.0f" % h, _measure_rig(h), h)
	if not _skip_spike:
		var m: Dictionary = await _measure_spike()
		print("[posture] --- SpikeFigure, idle, real physics")
		_report("  spike     ", m, SPIKE_H)
	quit(0)


func _report(tag: String, m: Dictionary, h: float) -> void:
	print(("%s hip ride %.4f h | leg drawn %.4f h | extension %.3f | knee %6.1f deg"
			+ " | knee out %5.2f px (%.1f%% h) | head top %+.4f h | foot %+.4f h")
			% [tag, m["hip_ride"], m["leg"], m["extension"], m["knee_deg"],
				m["knee_out"], 100.0 * float(m["knee_out"]) / h,
				m["head_top"], m["foot"]])


## Interior angle at the knee in degrees (180 = straight) plus how far the knee juts
## sideways off the hip->foot line. Both are read off the SAME 2-bone IK draw_figure
## uses, called on the rig's own script, so this cannot drift from what is painted.
func _knee_metrics(rig_script: GDScript, hip: Vector2, foot: Vector2,
		thigh: float, shin: float) -> Dictionary:
	var knee: Vector2 = rig_script.call("_ik_joint", hip, foot, thigh, shin, Vector2.RIGHT)
	var a: Vector2 = (hip - knee).normalized()
	var b: Vector2 = (foot - knee).normalized()
	var ang: float = rad_to_deg(acos(clampf(a.dot(b), -1.0, 1.0)))
	# Perpendicular distance from the knee to the hip->foot line.
	var span: Vector2 = foot - hip
	var out: float = 0.0
	if span.length() > 0.0001:
		var n: Vector2 = span.orthogonal().normalized()
		out = absf((knee - hip).dot(n))
	return {"deg": ang, "out": out}


## --- CharacterRig -----------------------------------------------------------
func _measure_rig(h: float) -> Dictionary:
	var script: GDScript = load(RIG_PATH) as GDScript
	var rig: Node2D = script.new() as Node2D
	rig.set("height", h)
	rig.call("set_grounded", true)
	rig.call("play", 0)   # State.IDLE
	root.add_child(rig)
	rig.position = Vector2.ZERO
	# Settle: the ride spring and the limb springs both have a start-up transient, and
	# a stance measured inside it is a measurement of the transient.
	for _i: int in 120:
		rig.call("advance", 1.0 / 60.0)

	var consts: Dictionary = script.get_script_constant_map()
	var thigh: float = h * float(consts["THIGH_FACTOR"])
	var shin: float = h * float(consts["SHIN_FACTOR"])
	# THE DRAWN pose. _sim_pose is what _draw() renders; _compute_pose is only its target.
	var pose: Dictionary = rig.call("_sim_pose")
	var hip: Vector2 = pose["hip"]
	var feet: Array[Vector2] = [pose["foot_lead"], pose["foot_off"]]
	var foot_y: float = maxf(feet[0].y, feet[1].y)
	# Worst (most bent) knee of the two — a stance is judged by the leg that looks wrong.
	var worst: Dictionary = {"deg": 999.0, "out": 0.0}
	for f: Vector2 in feet:
		var k: Dictionary = _knee_metrics(script, hip, f, thigh, shin)
		if float(k["deg"]) < float(worst["deg"]):
			worst = k
	var head_top: float = (pose["head_center"] as Vector2).y - float(pose["r"])
	rig.free()
	return {
		"hip_ride": (foot_y - hip.y) / h,
		"leg": (thigh + shin) / h,
		"extension": (foot_y - hip.y) / maxf(thigh + shin, 0.0001),
		"knee_deg": worst["deg"],
		"knee_out": worst["out"],
		"head_top": head_top / h,
		"foot": foot_y / h,
	}


## --- SpikeFigure ------------------------------------------------------------
## Real physics on a real floor: its stance is the steady state of the ride spring.
func _measure_spike() -> Dictionary:
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

	var script: GDScript = load(SPIKE_PATH) as GDScript
	var fig: Node2D = script.new() as Node2D
	fig.set("spawn_pos", Vector2(0.0, 330.0))
	world.add_child(fig)
	for _i: int in 180:
		await physics_frame

	var consts: Dictionary = script.get_script_constant_map()
	var thigh: float = float(consts["THIGH_LEN"])
	var shin: float = float(consts["SHIN_LEN"])
	var head_r: float = float(consts["HEAD_R"])
	var neck_y: float = float(consts["NECK_Y"])
	var hip_off: Vector2 = consts["HIP_OFF"]
	var torso: RigidBody2D = (fig.get("_parts") as Dictionary)["torso"]
	var hip: Vector2 = torso.to_global(hip_off)
	var feet: Array = fig.get("_foot")
	var knees: Array = fig.get("_knee")
	var foot_y: float = maxf((feet[0] as Vector2).y, (feet[1] as Vector2).y)
	# Head TOP: the head blob's centre is NECK_Y - HEAD_R + 0.5 in torso space.
	var head_top: float = torso.to_global(Vector2(0.0, neck_y - head_r * 2.0 + 0.5)).y
	# The spike solves its own knee; read the SOLVED one rather than re-deriving it.
	var worst: Dictionary = {"deg": 999.0, "out": 0.0}
	for i: int in 2:
		var knee: Vector2 = knees[i]
		var foot: Vector2 = feet[i]
		var a: Vector2 = (hip - knee).normalized()
		var b: Vector2 = (foot - knee).normalized()
		var deg: float = rad_to_deg(acos(clampf(a.dot(b), -1.0, 1.0)))
		var span: Vector2 = foot - hip
		var out: float = 0.0
		if span.length() > 0.0001:
			out = absf((knee - hip).dot(span.orthogonal().normalized()))
		if deg < float(worst["deg"]):
			worst = {"deg": deg, "out": out}
	# Everything is reported relative to the FOOT LINE and normalised by the figure's
	# real drawn height, so it is directly comparable with the rig above.
	var h: float = foot_y - head_top
	world.queue_free()
	await process_frame
	print("[posture]   (spike drawn height %.2f px, ref %.0f)" % [h, SPIKE_H])
	return {
		"hip_ride": (foot_y - hip.y) / h,
		"leg": (thigh + shin) / h,
		"extension": (foot_y - hip.y) / (thigh + shin),
		"knee_deg": worst["deg"],
		"knee_out": worst["out"],
		"head_top": (head_top - (foot_y + head_top) * 0.5) / h,
		"foot": (foot_y - (foot_y + head_top) * 0.5) / h,
	}
