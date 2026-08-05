# Scratch probe: reproduce the DUEL DEATH exactly and measure how far the drawn
# corpse ends up below the floor line.
#
#   godot --headless --path godot-project --script tools/rig_death_floor_probe.gd
#
# ⚠ NOT `tools/rig_ragdoll_floor_probe.gd`. That one flops a DETACHED height-84 rig
# with `flop()` + a 900 impulse. The bug the maker reported ("most the time the
# characters die and glitch into the floor") is a different path in four ways that all
# bear on the answer, so measuring the old one would have measured the wrong thing:
#
#   1. the rig is a CHILD of an 18x18-collider body, so `_align_feet_to_body` offsets
#      it by `box_bottom - height*0.5` = -6.5 and the drawn feet start ON the floor;
#   2. `height` is 31, not 84 — and the prone ride drop is a FRACTION of height;
#   3. the death path is `collapse(dir, 1050)`, which snaps `_limp` to 0.85+ and so
#      engages the prone ride target that `flop(0.85)` only partly reaches;
#   4. the body is PAUSED at the KO while the rig is set PROCESS_MODE_ALWAYS, so
#      nothing re-runs `move_and_slide` or re-feeds `set_grounded` underneath it.
#
# Reports the ride, the pitch, the lowest SIM joint, and — separately — the lowest
# DRAWN extent, because a joint clamped exactly to the floor still buries half a head
# circle or half a limb width, and on a stick figure the head is the biggest mass.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const FLOOR_Y: float = 400.0
const FIG_H: float = 31.0          # Hero.tscn's rig height
const BOX: float = 18.0            # Hero.tscn's RectangleShape2D
const JOINTS: Array[String] = [
	"head_center", "shoulder", "hip", "hand_lead", "hand_off", "foot_lead", "foot_off",
]

var _rig: Node2D
var _body: CharacterBody2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_build_floor()
	_build_fighter()
	_run()


func _build_floor() -> void:
	var b := StaticBody2D.new()
	b.position = Vector2(300.0, FLOOR_Y + 200.0)
	b.collision_layer = 1
	b.collision_mask = 0
	var c := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(4000.0, 400.0)
	c.shape = s
	b.add_child(c)
	root.add_child(b)


## A stand-in for `Hero.tscn`: an 18x18 body with the rig as a child, so
## `_align_feet_to_body` runs against a real box exactly as it does in a duel.
func _build_fighter() -> void:
	_body = CharacterBody2D.new()
	_body.collision_layer = 2
	_body.collision_mask = 1
	var c := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(BOX, BOX)
	c.shape = s
	_body.add_child(c)
	_rig = (load(RIG_PATH) as GDScript).new() as Node2D
	_rig.set("height", FIG_H)
	_body.add_child(_rig)
	root.add_child(_body)
	# Feet exactly on the floor: box bottom (+9) sits at FLOOR_Y.
	_body.global_position = Vector2(300.0, FLOOR_Y - BOX * 0.5)


## Head radius and limb half-width, from the rig's own factors. A joint sitting ON
## the floor line is not the same as the figure sitting on it.
func _drawn_margin(joint: String) -> float:
	if joint == "head_center":
		return maxf(2.0, FIG_H * 0.105)          # HEAD_R_FACTOR
	return maxf(1.6, FIG_H * 0.075) * 0.5        # LIMB_W_FACTOR, half


func _report(tag: String) -> void:
	var pose: Dictionary = _rig.call("_sim_pose")
	var low: float = -1e9
	var low_key: String = ""
	var drawn_low: float = -1e9
	var drawn_key: String = ""
	for k: String in JOINTS:
		var wy: float = _rig.to_global(pose[k] as Vector2).y
		if wy > low:
			low = wy
			low_key = k
		var edge: float = wy + _drawn_margin(k)
		if edge > drawn_low:
			drawn_low = edge
			drawn_key = k
	print("  %-10s ride %6.2f  pitch %5.2f  limp %.2f | joint '%s' %+6.2f | DRAWN '%s' %+6.2f"
		% [tag, _rig.call("body_ride"), _rig.call("body_pitch"), _rig.get("_limp"),
			low_key, low - FLOOR_Y, drawn_key, drawn_low - FLOOR_Y])


func _run() -> void:
	for _i: int in 40:
		await physics_frame
	print("=== RIG DEATH FLOOR PROBE (positive = BELOW the floor) ===")
	print("  rig offset in body: %.2f (expect -6.50)" % float(_rig.position.y))
	print("  ground probe: %s (INF means the raycast missed)" % _rig.get("_ground_world_y"))
	_report("standing")

	# THE DUEL DEATH, in the order `BotMatch._put_the_loser_down` does it.
	_rig.process_mode = Node.PROCESS_MODE_ALWAYS
	_rig.call("set_grounded", true)
	_rig.call("collapse", Vector2(-1.0, -0.5), 1050.0)
	# ...and the body stops, exactly as `get_tree().paused = true` stops it.
	_body.set_physics_process(false)

	for step: int in 120:
		await physics_frame
		if step == 5 or step == 20 or step == 45 or step == 80 or step == 119:
			_report("t+%d" % step)
	print("  ground probe after: %s" % _rig.get("_ground_world_y"))
	quit(0)
