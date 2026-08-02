# Scratch probe: after a knockback flop on a REAL floor, how far below the floor line
# does the lowest DRAWN joint end up? Prints per-frame; not a suite.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const FLOOR_Y: float = 400.0
const FIG_H: float = 84.0

var _rig: Node2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	var b := StaticBody2D.new()
	b.position = Vector2(300.0, FLOOR_Y + 20.0)
	b.collision_layer = 1
	b.collision_mask = 0
	var c := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(4000.0, 40.0)
	c.shape = s
	b.add_child(c)
	root.add_child(b)

	_rig = (load(RIG_PATH) as GDScript).new() as Node2D
	_rig.set("height", FIG_H)
	_rig.position = Vector2(300.0, FLOOR_Y - FIG_H * 0.5)
	root.add_child(_rig)
	_rig.call("set_grounded", true)
	_rig.call("play", 0)
	_run()


func _run() -> void:
	for _i: int in 60:
		await physics_frame
	print("probe: ground_world_y=%s (INF means the raycast missed)" % _rig.get("_ground_world_y"))
	_rig.call("play", 6)
	_rig.call("apply_impulse", Vector2(1.0, -0.25).normalized(), 900.0)
	_rig.call("flop", 0.85, 0.45)
	for step: int in 90:
		await physics_frame
		if step % 10 == 0 or step == 89:
			var pose: Dictionary = _rig.call("_sim_pose")
			var low: float = -1e9
			var low_key: String = ""
			for k: String in ["head_center", "shoulder", "hip", "hand_lead", "hand_off",
					"foot_lead", "foot_off"]:
				var wy: float = _rig.to_global(pose[k] as Vector2).y
				if wy > low:
					low = wy
					low_key = k
			print("  step %2d  limp %.2f  ride %6.2f  pitch %5.2f  lowest '%s' %+7.2f px below floor"
				% [step, _rig.get("_limp"), _rig.call("body_ride"), _rig.call("body_pitch"),
					low_key, low - FLOOR_Y])
	quit(0)
