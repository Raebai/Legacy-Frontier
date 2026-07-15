# Run: godot --headless --path godot-project --script tools/slice_test_touch.gd
# Verifies the mobile TouchControls layer: self-hides on a non-touch desktop (so
# keyboard/mouse play is unaffected), builds its buttons when forced, and its
# move-injection presses/releases the real input actions with analog strength.
extends SceneTree

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_hidden_on_desktop()
	failed += _test_forced_builds_buttons()
	failed += _test_move_injection()
	if failed > 0:
		printerr("Touch tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Touch tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## Headless (no touchscreen) + not forced -> the pad hides, so desktop is untouched.
func _test_hidden_on_desktop() -> int:
	var pad := TouchControls.new()
	root.add_child(pad)
	var ok: int = _expect(not pad.visible, "pad hides on non-touch desktop")
	pad.queue_free()
	return ok


## Forced visible -> the pad renders + builds its thumb buttons.
func _test_forced_builds_buttons() -> int:
	var pad := TouchControls.new()
	pad.force_visible = true
	root.add_child(pad)
	var buttons: int = 0
	for c: Node in pad.get_children():
		if c is Button:
			buttons += 1
	var ok: int = _expect(pad.visible, "forced pad is visible")
	ok += _expect(buttons >= 6, "pad built the thumb buttons (got %d)" % buttons)
	pad.queue_free()
	return ok


## The move-joystick drives the SAME named actions the keyboard uses, with strength.
func _test_move_injection() -> int:
	var pad := TouchControls.new()
	pad.force_visible = true
	root.add_child(pad)
	var ok: int = 0
	pad._set_move("move_right", 0.8, true)
	ok += _expect(Input.is_action_pressed("move_right"), "move_right pressed via joystick")
	ok += _expect(Input.get_action_strength("move_right") > 0.5, "analog strength applied")
	pad._set_move("move_right", 0.0, false)
	ok += _expect(not Input.is_action_pressed("move_right"), "move_right released on recenter")
	pad.queue_free()
	return ok
