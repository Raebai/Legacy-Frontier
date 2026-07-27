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
	failed += _test_buttons_drive_real_actions()
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


## Every action a touch button drives must EXIST in the input map AND be an action
## something actually polls. The JUMP button shipped pressing "move_up" while
## Hero polls "jump", so touch jump was dead on a device — and the old test still
## passed, because counting buttons never checks what they are wired to.
func _test_buttons_drive_real_actions() -> int:
	var pad := TouchControls.new()
	pad.force_visible = true
	root.add_child(pad)
	var ok: int = 0
	var seen: Array[String] = []
	for c: Node in pad.get_children():
		if not (c is Button):
			continue
		var action: String = String(c.get_meta("action", ""))
		if action == "":
			continue
		seen.append(action)
		ok += _expect(InputMap.has_action(action),
			"touch button '%s' drives a real action '%s'" % [(c as Button).text, action])
	# The verbs a phone player cannot play without.
	for required: String in ["jump", "cast", "dash", "melee", "parry"]:
		ok += _expect(seen.has(required), "touch pad exposes '%s'" % required)
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
