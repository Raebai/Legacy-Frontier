# Run: godot --headless --path godot-project --script tools/slice_test_floor.gd
# DestructibleFloor tiles independent FloorSegments; breaking one opens a REAL hole
# (that segment leaves the "destructible" group + frees) while neighbours survive.
# Runtime-load (not preload): FloorSegment references DebrisChunk/Juice/Sfx.
extends SceneTree

var _ran: bool = false


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	var parent := Node2D.new()
	root.add_child(parent)
	var floor_script: GDScript = load("res://scripts/combat/DestructibleFloor.gd")
	var df: Node2D = floor_script.new()
	df.set("run_start", Vector2(0.0, 100.0))
	df.set("run_end_x", 320.0)  # 5 segments at 64px
	parent.add_child(df)

	var segs: Array = []
	for c: Node in df.get_children():
		if c is StaticBody2D:
			segs.append(c)
	failed += _expect(segs.size() == 5, "tiled 5 floor segments (got %d)" % segs.size())

	var ok_group: bool = true
	var ok_layer: bool = true
	for s: Node in segs:
		if not s.is_in_group("destructible"):
			ok_group = false
		if (s as StaticBody2D).collision_layer != 5:
			ok_layer = false
	failed += _expect(ok_group, "segments joined group 'destructible'")
	failed += _expect(ok_layer, "segments use collision_layer 5 (blocks fighters + spell-hittable)")

	# Break the middle segment -> real hole: leaves the group + frees; neighbours stay.
	var target: Node = segs[2]
	target.call("take_damage", 999)
	failed += _expect(not target.is_in_group("destructible"), "broken segment left the group (no same-frame re-hit)")
	failed += _expect(target.is_queued_for_deletion(), "broken segment queued for free (collider gone -> hole)")
	failed += _expect(segs[1].is_in_group("destructible") and not segs[1].is_queued_for_deletion(),
		"a neighbour survives (partial passable hole, not a full wipe)")

	# Post-death damage is a safe no-op (no crash).
	target.call("take_damage", 10)

	if failed > 0:
		printerr("Floor tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Floor tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0
