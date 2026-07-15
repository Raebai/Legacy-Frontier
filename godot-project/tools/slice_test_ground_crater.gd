# Run: godot --headless --path godot-project --script tools/slice_test_ground_crater.gd
# GroundCrater: the session cap holds, and a snap spawn with no floor below frees
# itself (no floating crater over a pit). GroundCrater uses no autoloads, so it
# loads + runs cleanly headless.
extends SceneTree

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	var parent := Node2D.new()
	root.add_child(parent)
	var crater_script: GDScript = load("res://scripts/combat/GroundCrater.gd")

	# Spawn well over the cap (snap=false so no raycast) — only MAX_CRATERS stay alive.
	for i in crater_script.MAX_CRATERS + 12:
		crater_script.spawn(parent, Vector2(float(i) * 10.0, 0.0), 30.0, false)
	failed += _expect(_alive_craters() == crater_script.MAX_CRATERS,
		"crater count capped at MAX_CRATERS (got %d)" % _alive_craters())

	# A snap spawn over nothing (headless world has no floor collider) frees itself.
	crater_script.spawn(parent, Vector2(500.0, 0.0), 30.0, true)
	failed += _expect(_alive_craters() == crater_script.MAX_CRATERS,
		"a snap crater with no floor below does not add a floating crater")

	if failed > 0:
		printerr("Ground-crater tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Ground-crater tests: all PASS")
		quit(0)
	return true


func _alive_craters() -> int:
	var n: int = 0
	for c: Node in get_nodes_in_group("ground_crater"):  # SceneTree-wide (self is the tree)
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			n += 1
	return n


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0
