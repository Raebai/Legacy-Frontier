# Run headless:
#   godot --headless --path godot-project --script tools/probe_dojo_feet.gd
#
# WHY ARE THE DOJO'S BODIES IN THE AIR?
#
# Maker, playing the tutorial 2026-10-18: *"during the tutorial the bots are flying"*.
# `tools/dojo_capture.gd` shows it — three figures hanging at a constant height with
# clear air under them and their health bars floating alongside.
#
# This is `tools/probe_town_feet.gd` asked of the DOJO instead of the town. Same
# columns, same raycast, same settle: for each figure, in world y,
#
#   body      the node's origin
#   box_foot  the collision box's bottom edge - where PHYSICS rests it
#   rig_foot  where the rig draws its feet (origin + height/2)
#   ground    what a downward ray from the body actually hits
#   GAP       ground - rig_foot. POSITIVE means the figure is ABOVE the floor by
#             that much, i.e. it is flying. (probe_town_feet prints the opposite
#             sign as SINK, because the bug it was built for was feet UNDER the
#             floor. Same number, named for the symptom being chased.)
#
# ⚠ IT SETTLES PHYSICS FIRST, 40 FRAMES, for the reason probe_town_feet gives: without
# it every number is the SPAWN position, and the whole question here is whether these
# bodies FALL from their spawn or hang at it. A figure still airborne after 40 physics
# frames is not mid-fall, it is not falling at all.
extends SceneTree

const SETTLE_FRAMES: int = 40


func _initialize() -> void:
	_run()


func _run() -> void:
	var fp: GDScript = load("res://scripts/combat/FreePlay.gd") as GDScript
	if fp == null:
		printerr("probe_dojo_feet: FreePlay.gd did not load")
		quit(1)
		return
	fp.set("dojo", true)
	fp.call("enter", self, 0)

	for i: int in SETTLE_FRAMES:
		await physics_frame

	print("")
	print("DOJO FEET, after %d physics frames" % SETTLE_FRAMES)
	print("figure                    body   box_foot   rig_foot     ground       GAP  falling")
	print("------------------------------------------------------------------------------------")
	var airborne: int = 0
	var total: int = 0
	for n: Node in _all(root):
		var rig: Node = n.get_node_or_null(^"Rig")
		if rig == null or not (n is Node2D):
			continue
		var body := n as Node2D
		var h: float = float(rig.get("height"))
		var box_half: float = _box_half(n)
		var body_y: float = body.global_position.y
		var rig_y: float = body_y + float((rig as Node2D).position.y) + h * 0.5
		var ground: float = _probe(body, h)
		var gap: float = (ground - rig_y) if is_finite(ground) else NAN
		# A body that is falling has downward velocity; one that is hanging does not.
		var vel: String = "-"
		if body.has_method("get") and body.get("velocity") != null:
			vel = "%.1f" % float((body.get("velocity") as Vector2).y)
		total += 1
		if is_finite(gap) and gap > 2.0:
			airborne += 1
		print("%-22s %8.2f %10.2f %10.2f %10.2f %9.2f %8s" % [
			_label(n), body_y,
			body_y + box_half if box_half > 0.0 else NAN,
			rig_y, ground, gap, vel])
	print("------------------------------------------------------------------------------------")
	print("%d of %d figures are MORE THAN 2 px above the floor they are standing over." % [
		airborne, total])
	print("GAP > 0 means flying. `falling` is the body's y velocity: ~0 on an airborne")
	print("body means gravity is not moving it, so it will hang there forever.")
	quit(0)


func _label(n: Node) -> String:
	var groups: Array = n.get_groups()
	for g: Variant in [&"player", &"hero", &"free_dummy", &"town_dummy", &"npc", &"enemy"]:
		if groups.has(g):
			return "%s (%s)" % [n.name, String(g)]
	return String(n.name)


## Half-height of the node's own rectangle collider, or -1 if it has none.
func _box_half(n: Node) -> float:
	for c: Node in n.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			return ((c as CollisionShape2D).shape as RectangleShape2D).size.y * 0.5
	return -1.0


## The same downward ray the rig casts, so the number printed is the number the rig
## acts on rather than an independent guess at where the floor is.
func _probe(body: Node2D, h: float) -> float:
	var space: PhysicsDirectSpaceState2D = body.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(
		body.global_position + Vector2(0.0, -h * 0.5),
		body.global_position + Vector2(0.0, h * 4.0),
		int(CharacterRig.GROUND_MASK))
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	return INF if hit.is_empty() else (hit["position"] as Vector2).y


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out
