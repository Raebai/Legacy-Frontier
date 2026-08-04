# Run headless:
#   godot --headless --path godot-project --script tools/probe_holy_hitboxes.gd
#
# DO JUDGMENT AND HEAVEN'S VERDICT ACTUALLY REACH A BODY?
#
# Maker: "judgment / heaven's verdict aren't hitting the hitboxes of the bots properly,
# so make sure they are working with their equivalents with other classes as well."
#
# Both resolve damage through `SpellTargets.in_radius` anchored at `_ground` — the point
# the spell lands ON THE FLOOR — while the body they are aimed at is drawn ABOVE that
# floor. So the question this answers is not "is the query silhouette-aware" (it is) but
# "how far above the impact point can a body be and still be caught".
#
# ⚠ AND THE RIG MOVED. `CharacterRig._align_feet_to_body` raised every figure so its
# feet land on its collider's bottom edge, which lifted every drawn spine by up to
# 6.5 px. A radius tuned against the old, lower silhouette is a radius that now falls
# short — that is the specific suspicion being tested.
#
# Prints, for a body standing on the floor, the largest vertical offset of the impact
# point that still connects, against each spell's authored radius.
extends SceneTree

const ENEMY_SCENE: String = "res://scenes/combat/Enemy.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	var fcs := CollisionShape2D.new()
	var frect := RectangleShape2D.new()
	frect.size = Vector2(2000.0, 40.0)
	fcs.shape = frect
	floor_body.add_child(fcs)
	floor_body.position = Vector2(0.0, 520.0)
	world.add_child(floor_body)
	var ground_top: float = 500.0

	var enemy: Node = load(ENEMY_SCENE).instantiate()
	world.add_child(enemy)
	enemy.set_physics_process(false)
	# Rest it exactly as physics would: origin one box-half above the floor's top face.
	var half: float = 10.0
	for c: Node in enemy.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			half = ((c as CollisionShape2D).shape as RectangleShape2D).size.y * 0.5
	(enemy as Node2D).global_position = Vector2(0.0, ground_top - half)
	for i: int in 6:
		await physics_frame

	var rig: Node2D = enemy.get_node_or_null(^"Rig") as Node2D
	var body_y: float = (enemy as Node2D).global_position.y
	print("floor top      %.2f" % ground_top)
	print("enemy origin   %.2f   (collider half %.1f)" % [body_y, half])
	print("rig offset     %.2f   (feet aligned to the collider bottom)"
		% (0.0 if rig == null else rig.position.y))
	print("head point     %.2f" % (enemy.call("head_point") as Vector2).y)
	print("hit margin     %.2f" % float(enemy.call("hit_margin")))
	print("")
	# How far can the IMPACT POINT sit from the body and still be inside `radius`?
	# `in_radius` is silhouette-aware, so this is the real reach, not centre-to-centre.
	var nodes: Array = [enemy]
	# ⚠ LOS ON — the real call passes a ctx and lets `require_los` default to true, and
	# the impact point of a ground-anchored spell sits ON the floor collider. A trace
	# that starts inside geometry reports BLOCKED, which would make these spells miss
	# everything while the radius maths says they should connect.
	print("radius  losOFF_up  losON_at_floor  losON_up")
	for radius: float in [40.0, 55.0, 70.0, 90.0, 110.0]:
		var up_off: float = -1.0
		for dy: int in range(0, 140, 2):
			if SpellTargets.in_radius(Vector2(0.0, ground_top - float(dy)), radius,
					nodes, [], null, false).size() > 0:
				up_off = float(dy)
		var los_floor: bool = SpellTargets.in_radius(
			Vector2(0.0, ground_top), radius, nodes, [], world).size() > 0
		var up_on: float = -1.0
		for dy2: int in range(0, 140, 2):
			if SpellTargets.in_radius(Vector2(0.0, ground_top - float(dy2)), radius,
					nodes, [], world).size() > 0:
				up_on = float(dy2)
		print("%6.0f  %10.0f  %14s  %9.0f" % [radius, up_off, str(los_floor), up_on])
	quit(0)
