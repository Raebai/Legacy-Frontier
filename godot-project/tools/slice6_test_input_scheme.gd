# The CONTROL SCHEME, asserted against the input map itself.
# Bindings are the kind of thing that drifts silently — a stray editor re-save or
# a half-finished rebind leaves a verb on the wrong button and nobody notices
# until it is felt in a playtest. These pin the maker-chosen scheme:
#   RIGHT MOUSE = deflect/parry   ·   SPACE = dash   ·   W/UP = jump (never space)
# and, just as importantly, that no two verbs fight over the same button.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_input_scheme.gd
extends SceneTree

const KEY_SPACE_PHYS: int = 32
const KEY_W_PHYS: int = 87
const MOUSE_LEFT: int = 1
const MOUSE_RIGHT: int = 2

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_scheme()
	failed += _test_no_double_bound_buttons()
	if failed > 0:
		printerr("Input scheme tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Input scheme tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## True when `action` is bound to the given mouse button index.
func _has_mouse(action: String, button: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for e: InputEvent in InputMap.action_get_events(action):
		var mb := e as InputEventMouseButton
		if mb != null and mb.button_index == button:
			return true
	return false


## True when `action` is bound to the given PHYSICAL keycode. Physical, so the
## scheme holds on AZERTY/QWERTZ as well as QWERTY.
func _has_key(action: String, phys: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for e: InputEvent in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k != null and k.physical_keycode == phys:
			return true
	return false


func _test_scheme() -> int:
	var ok: int = 0
	ok += _expect(_has_mouse("parry", MOUSE_RIGHT), "right mouse button deflects")
	ok += _expect(_has_key("dash", KEY_SPACE_PHYS), "space dashes")
	ok += _expect(_has_key("jump", KEY_W_PHYS), "W jumps")
	# The two that would quietly undo the scheme.
	ok += _expect(not _has_key("jump", KEY_SPACE_PHYS),
		"space is NOT also jump — it belongs to dash")
	ok += _expect(not _has_mouse("cast", MOUSE_RIGHT),
		"right mouse is NOT also cast — it belongs to deflect")
	return ok


## No button may drive two combat verbs at once: pressing it would fire both, and
## which one "wins" is then down to polling order rather than design.
func _test_no_double_bound_buttons() -> int:
	var verbs: Array[String] = [
		"cast", "melee", "parry", "dash", "jump", "blast", "blink", "nova", "ultimate",
	]
	var seen: Dictionary = {}          # binding signature -> the verb that claimed it
	var ok: int = 0
	for action: String in verbs:
		if not InputMap.has_action(action):
			continue
		for e: InputEvent in InputMap.action_get_events(action):
			var sig: String = ""
			var mb := e as InputEventMouseButton
			var k := e as InputEventKey
			if mb != null:
				sig = "mouse:%d" % mb.button_index
			elif k != null:
				sig = "key:%d" % k.physical_keycode
			if sig == "":
				continue
			ok += _expect(not seen.has(sig),
				"%s is bound to '%s' and also '%s'" % [sig, seen.get(sig, ""), action])
			seen[sig] = action
	return ok
