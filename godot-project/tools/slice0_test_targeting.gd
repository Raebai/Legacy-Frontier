# Run: godot --headless --path godot-project --script tools/slice0_test_targeting.gd
extends SceneTree


func _init() -> void:
	var failed: int = 0
	failed += _test_nearest_empty()
	failed += _test_nearest_picks_closest()
	failed += _test_aim_direction_normalized()
	failed += _test_aim_direction_fallback()
	if failed > 0:
		printerr("Slice0 targeting tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice0 targeting tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_node(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.global_position = pos
	return n


func _test_nearest_empty() -> int:
	return _expect(Targeting.nearest(Vector2.ZERO, []) == null, "empty -> null")


func _test_nearest_picks_closest() -> int:
	var a := _make_node(Vector2(100, 0))
	var b := _make_node(Vector2(30, 0))
	var c := _make_node(Vector2(300, 0))
	var got: Node2D = Targeting.nearest(Vector2.ZERO, [a, b, c])
	var ok := _expect(got == b, "picks closest (b at 30)")
	a.free(); b.free(); c.free()
	return ok


func _test_aim_direction_normalized() -> int:
	var t := _make_node(Vector2(0, 50))
	var dir: Vector2 = Targeting.aim_direction(Vector2.ZERO, [t], Vector2.RIGHT)
	var ok := _expect(dir.is_equal_approx(Vector2.DOWN), "aim points down at target")
	t.free()
	return ok


func _test_aim_direction_fallback() -> int:
	var dir: Vector2 = Targeting.aim_direction(Vector2.ZERO, [], Vector2.LEFT)
	return _expect(dir.is_equal_approx(Vector2.LEFT), "no target -> fallback dir")
