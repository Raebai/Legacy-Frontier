# Telegraph PERCEPTION contract — the seam a dodging bot reads danger through.
# Locks the three things a brain depends on: every live tell is findable in one
# group scan, its footprint is reported in WORLD space, and the countdown is
# honest about when the hit lands. Without this the AI cannot see the very thing
# it is meant to dodge.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_telegraph_perception.gd
extends SceneTree

var failed: int = 0
var _ran: bool = false


# Driven from _process, not _init: during _init the tree is not up yet, so a node
# added to root never runs _ready and never joins its group.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_joins_group()
	_test_circle_shape_is_world_space()
	_test_line_shape_is_world_space()
	_test_countdown_and_armed()
	if failed == 0:
		print("Telegraph perception tests: all PASS")
		quit(0)
	else:
		printerr("Telegraph perception tests: %d FAILED" % failed)
		quit(1)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failed += 1
		printerr("FAIL: ", msg)


func _make(at: Vector2) -> Telegraph:
	var t := Telegraph.new()
	t.position = at
	root.add_child(t)
	return t


func _test_joins_group() -> void:
	var t := _make(Vector2(120.0, -40.0))
	_expect(t.is_in_group(Telegraph.GROUP), "a live telegraph is findable by group")
	_expect(get_nodes_in_group(Telegraph.GROUP).has(t), "group scan returns it")
	t.free()


## The footprint must be reported where the danger ACTUALLY is. A brain that
## dodges toward (0,0) because the shape came back in local space is worse than
## no brain at all.
func _test_circle_shape_is_world_space() -> void:
	var at := Vector2(320.0, -75.0)
	var t := _make(at)
	t.start(64.0, 0.5)
	var s: Dictionary = t.danger_shape()
	_expect(s.get("shape") == "circle", "circle tell reports a circle")
	_expect(s.get("center") == at, "circle centre is world space (got %s)" % [s.get("center")])
	_expect(is_equal_approx(float(s.get("radius")), 64.0), "circle radius survives")
	t.free()


func _test_line_shape_is_world_space() -> void:
	var at := Vector2(-200.0, 30.0)
	var t := _make(at)
	t.start_line(180.0, 22.0, 0.0, 0.4)      # angle 0 = straight right
	var s: Dictionary = t.danger_shape()
	_expect(s.get("shape") == "line", "lane tell reports a line")
	_expect(s.get("from") == at, "lane starts at the node, world space")
	_expect((s.get("to") as Vector2).is_equal_approx(at + Vector2(180.0, 0.0)),
		"lane end follows length + angle (got %s)" % [s.get("to")])
	_expect(is_equal_approx(float(s.get("width")), 22.0), "lane width survives")
	t.free()


## time_to_impact drives WHEN a bot commits its dodge, so it has to count down in
## real seconds and cross zero exactly when the tell fires.
func _test_countdown_and_armed() -> void:
	var t := _make(Vector2.ZERO)
	t.start(50.0, 0.50)
	_expect(t.is_armed(), "a fresh tell is armed")
	_expect(is_equal_approx(t.time_to_impact(), 0.50), "countdown starts at the windup")
	t.advance(0.30)
	_expect(is_equal_approx(t.time_to_impact(), 0.20), "countdown tracks elapsed time")
	_expect(t.is_armed(), "still armed before it fires")
	t.advance(0.25)                           # past the windup
	_expect(t.time_to_impact() <= 0.0, "countdown is <= 0 once fired")
	_expect(not t.is_armed(), "a fired tell is no longer worth dodging")
	if is_instance_valid(t):
		t.free()
