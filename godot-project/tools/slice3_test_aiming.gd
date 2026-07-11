# Run: godot --headless --path godot-project --script tools/slice3_test_aiming.gd
# Wave 1 (twin-stick): Targeting.assisted_aim soft-aim forgiveness cone.
extends SceneTree


func _init() -> void:
	var failed: int = 0
	failed += _test_no_enemy_passthrough()
	failed += _test_zero_aim_safe()
	failed += _test_aligned_enemy_stays()
	failed += _test_in_cone_bends()
	failed += _test_out_of_cone_unchanged()
	failed += _test_out_of_range_unchanged()
	if failed > 0:
		printerr("Slice3 aiming tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice3 aiming tests: all PASS")
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


func _test_no_enemy_passthrough() -> int:
	var got: Vector2 = Targeting.assisted_aim(Vector2.ZERO, Vector2.RIGHT, [])
	return _expect(got.is_equal_approx(Vector2.RIGHT), "no enemy -> raw aim unchanged")


func _test_zero_aim_safe() -> int:
	var got: Vector2 = Targeting.assisted_aim(Vector2.ZERO, Vector2.ZERO, [])
	return _expect(got.is_equal_approx(Vector2.RIGHT), "zero aim -> safe RIGHT fallback")


func _test_aligned_enemy_stays() -> int:
	var e := _make_node(Vector2(100, 0))
	var got: Vector2 = Targeting.assisted_aim(Vector2.ZERO, Vector2.RIGHT, [e])
	var ok := _expect(got.is_equal_approx(Vector2.RIGHT), "enemy on the aim line -> aim holds")
	e.free()
	return ok


func _test_in_cone_bends() -> int:
	# Enemy ~5.7 deg below the aim (inside the ~18 deg cone): aim bends toward it
	# but not all the way (bend 0.6).
	var e := _make_node(Vector2(100, 10))
	var got: Vector2 = Targeting.assisted_aim(Vector2.ZERO, Vector2.RIGHT, [e])
	var to_enemy_angle: float = Vector2(100, 10).angle()
	var ok := _expect(
		got.angle() > 0.001 and got.angle() < to_enemy_angle and got.x > 0.9,
		"in-cone enemy bends aim partway toward it"
	)
	e.free()
	return ok


func _test_out_of_cone_unchanged() -> int:
	# Enemy straight down (90 deg off the RIGHT aim) is well outside the cone.
	var e := _make_node(Vector2(0, 100))
	var got: Vector2 = Targeting.assisted_aim(Vector2.ZERO, Vector2.RIGHT, [e])
	var ok := _expect(got.is_equal_approx(Vector2.RIGHT), "out-of-cone enemy -> aim unchanged")
	e.free()
	return ok


func _test_out_of_range_unchanged() -> int:
	# On the aim line but past the default 420px range.
	var e := _make_node(Vector2(500, 0))
	var got: Vector2 = Targeting.assisted_aim(Vector2.ZERO, Vector2.RIGHT, [e])
	var ok := _expect(got.is_equal_approx(Vector2.RIGHT), "out-of-range enemy -> aim unchanged")
	e.free()
	return ok
