# Run headless:
#   godot --headless --path godot-project --script tools/probe_town_feet.gd
#
# WHERE IS THE FLOOR, AND WHERE DOES EACH FIGURE THINK ITS FEET ARE?
#
# The maker has reported "everyone's legs are weird" across several sessions and
# every previous fix tuned the RIG — knee jut, breath symmetry, trail factor. This
# probe asks the question those fixes never asked: does the body's COLLISION BOX and
# the rig's own HEIGHT agree about where the ground is?
#
# For each figure it prints, in world y:
#   body      the node's origin
#   box_foot  where the collision box's bottom edge is — where PHYSICS rests it
#   rig_foot  where the rig would draw its feet unclamped (origin + height/2)
#   ground    what the rig's own downward raycast found
#   sink      rig_foot - ground. POSITIVE means the drawn feet are BELOW the floor,
#             so `_plant_foot` clamps them up and the legs lose that much length.
#
# A non-zero `sink` on a body that is standing still on flat ground is the bug: it is
# a permanent leg compression that no amount of rig tuning can remove, because it is
# not a rig problem at all — it is two numbers in two different files disagreeing.
extends SceneTree

const TOWN: String = "res://scenes/Main.tscn"


func _initialize() -> void:
	var packed: PackedScene = load(TOWN)
	var town: Node = packed.instantiate()
	root.add_child(town)
	_run.call_deferred(town)


func _run(town: Node) -> void:
	# Let physics actually settle the bodies onto the floor. Without this every number
	# below is the spawn position, which is the trap that made an earlier leg harness
	# lie about exactly this.
	for i: int in 40:
		await physics_frame
	print("figure               body    box_foot  rig_foot   ground    SINK")
	print("-------------------------------------------------------------------")
	for n: Node in _all(town):
		var rig: Node = n.get_node_or_null(^"Rig")
		if rig == null or not (n is Node2D):
			continue
		var body := n as Node2D
		var h: float = float(rig.get("height"))
		var box_half: float = _box_half(n)
		var body_y: float = body.global_position.y
		var rig_y: float = body_y + float((rig as Node2D).position.y) + h * 0.5
		var ground: float = _probe(body, h)
		var sink: float = rig_y - ground if is_finite(ground) else NAN
		print("%-18s %8.2f %8.2f %8.2f %8.2f %7.2f" % [
			_label(n), body_y,
			body_y + box_half if box_half > 0.0 else NAN,
			rig_y, ground, sink])
	quit(0)


func _label(n: Node) -> String:
	var groups: Array = n.get_groups()
	for g: Variant in [&"player", &"town_dummy", &"npc"]:
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
		body.global_position + Vector2(0.0, h * 1.5),
		int(CharacterRig.GROUND_MASK))
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	return INF if hit.is_empty() else (hit["position"] as Vector2).y


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out
