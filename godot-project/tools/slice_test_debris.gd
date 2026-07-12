# Run: godot --headless --path godot-project --script tools/slice_test_debris.gd
# Drives the DebrisChunk physics rubble: spawn count, gravity/motion, and the
# global live-chunk cap. DebrisChunk has no autoload deps, so the class_name is
# safe to reference directly (like Targeting/Elements in the other suites).
extends SceneTree

var _failed: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var container := Node2D.new()
	root.add_child(container)
	# A wide floor on collision layer 1 so chunks (mask 1) can land on it.
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2000.0, 40.0)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	floor_body.add_child(cs)
	floor_body.position = Vector2(0.0, 220.0)
	container.add_child(floor_body)
	await physics_frame  # let the tree settle so is_inside_tree() holds

	# 1) spawn_burst creates exactly `count` chunks.
	_expect(container.is_inside_tree(), "container is in the tree before spawning")
	DebrisChunk.spawn_burst(container, Vector2(0.0, -60.0), Color(0.4, 0.4, 0.45), 12, Vector2.RIGHT, 240.0)
	await physics_frame
	var n0: int = get_nodes_in_group("debris_chunk").size()
	_expect(n0 == 12, "spawn_burst creates 12 chunks (got %d)" % n0)

	# 2) chunks move under physics (launch + gravity) over several steps.
	for _i: int in 45:
		await physics_frame
	var moved: bool = false
	for c: Node in get_nodes_in_group("debris_chunk"):
		if is_instance_valid(c) and absf((c as Node2D).global_position.y + 60.0) > 2.0:
			moved = true
			break
	_expect(moved, "chunks move (launch + gravity) away from the spawn point")

	# 3) global cap: flooding with 200 more never exceeds MAX_LIVE_CHUNKS (90).
	DebrisChunk.spawn_burst(container, Vector2(0.0, -60.0), Color(0.4, 0.4, 0.45), 200, Vector2.ZERO, 200.0)
	await physics_frame
	var total: int = 0
	for c: Node in get_nodes_in_group("debris_chunk"):
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			total += 1
	_expect(total <= 90, "global live-chunk cap respected (got %d)" % total)

	if _failed > 0:
		printerr("DEBRIS tests: %d FAILED" % _failed)
		quit(1)
	else:
		print("DEBRIS tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_failed += 1
