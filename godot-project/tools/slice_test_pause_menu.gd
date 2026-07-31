# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_pause_menu.gd
#
# THE SETTINGS MENU HAS TO BE REACHABLE ON A PHONE.
#
# Every host opens the pause menu on `ui_cancel` and nothing else. A phone has no Esc
# key. So volume, music, camera zoom, screen shake, hit-stop, aim assist and the
# graphics toggle were ALL keyboard-only on the one platform this game is being built
# for — a settings panel that cannot be opened is not a settings panel.
#
# WHAT THIS PINS, and each assertion exists because the obvious implementation of it
# is silently broken:
#   1. The pause button SURVIVES ITS PARENT BEING HIDDEN. `PauseMenu` is a Control
#      that is `visible = false` almost always, so a Control child would be invisible
#      exactly when it is needed. It lives on a CanvasLayer, which is not a CanvasItem
#      and therefore does not inherit that. This is the whole trick and it is the one
#      thing a screenshot would have caught and a unit test nearly cannot.
#   2. It does NOT block the game. A full-rect holder with the wrong mouse filter
#      would eat every tap on the arena underneath it, which reads as "the game froze".
#   3. It hides while the menu is open (the menu has its own Resume row — two ways to
#      close it in the same corner is a mis-tap waiting to happen).
#   4. The settings panel actually contains the new rows, and they write through to
#      the live config rather than to a local copy.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion sentinel
# as its last line, so a test that aborts part-way fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"pause_button_is_visible_while_the_menu_is_closed",
	"pause_button_does_not_eat_the_game",
	"pause_button_hides_while_the_menu_is_open",
	"settings_has_the_new_rows",
	"aim_assist_row_writes_through",
	"quality_row_cycles_and_labels_itself",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


## Stands in for the /root/Tuning autoload, which is NOT registered under `--script`.
## Holds a real `TuningConfig`, so the rows below are writing to the same resource
## type the game does rather than to a bespoke bag of properties.
class FakeTuning extends Node:
	var cfg: TuningConfig = TuningConfig.new()


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_button_visible_when_closed()
	_test_button_does_not_block()
	_test_button_hides_when_open()
	_test_settings_rows()
	_test_aim_assist_row()
	_test_quality_row()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Pause-menu tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("Pause-menu tests: all PASS")
	quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _make_menu() -> PauseMenu:
	var m := PauseMenu.new()
	root.add_child(m)
	m.build("Exit")
	return m


## Swap in a FakeTuning for /root/Tuning. Synchronous single-threaded GDScript with no
## awaits in between, so nothing else ever observes the substitution.
func _with_tuning() -> Node:
	var real: Node = root.get_node_or_null("/root/Tuning")
	if real != null:
		root.remove_child(real)
	var fake := FakeTuning.new()
	fake.name = "Tuning"
	root.add_child(fake)
	return real


func _restore_tuning(real: Node) -> void:
	var fake: Node = root.get_node_or_null("/root/Tuning")
	if fake != null:
		root.remove_child(fake)
		fake.free()
	if real != null:
		root.add_child(real)


## Every descendant of `n` that is a CanvasItem and is actually being drawn. Walks the
## real tree rather than trusting a stored reference, because "is it on screen" is a
## question about ancestry, and ancestry is exactly what the CanvasLayer trick changes.
func _find_visible_button(n: Node, text: String) -> Button:
	var b: Button = n as Button
	if b != null and b.text == text and b.is_visible_in_tree():
		return b
	for c: Node in n.get_children():
		var found: Button = _find_visible_button(c, text)
		if found != null:
			return found
	return null


# ------------------------------------------------------------------- 1+2+3
## ⚠ THE ASSERTION THE WHOLE FEATURE HANGS ON. The menu is closed — `visible = false`
## on the PauseMenu Control itself — and the pause button must still be drawn. A
## Control child would fail this; the CanvasLayer child passes it.
func _test_button_visible_when_closed() -> void:
	var m: PauseMenu = _make_menu()
	_expect(not m.visible, "a freshly built pause menu is closed")
	_expect(_find_visible_button(m, "II") != null,
		("the pause BUTTON is visible while the menu is CLOSED — without this the "
		+ "settings panel is unreachable on a phone, which is the entire point"))
	m.queue_free()
	_completes("pause_button_is_visible_while_the_menu_is_closed")


## The button's full-rect holder must not swallow taps meant for the game. A holder
## with the default mouse filter would make the arena unresponsive everywhere, which
## reads to a player as a freeze rather than as a UI bug.
func _test_button_does_not_block() -> void:
	var m: PauseMenu = _make_menu()
	var btn: Button = _find_visible_button(m, "II")
	_expect(btn != null, "the pause button exists")
	if btn == null:
		m.queue_free()
		return  # deliberately NOT completed: the missing sentinel fails the suite
	var holder: Control = btn.get_parent() as Control
	_expect(holder != null and holder.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the full-rect holder IGNORES input — only the button itself takes taps")
	_expect(btn.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"...and the button itself does take them")
	# It also has to be big enough to hit with a thumb. 44 px is the smallest tap
	# target that survives contact with a real hand; anything under it is a miss.
	_expect(btn.custom_minimum_size.x >= 44.0 and btn.custom_minimum_size.y >= 44.0,
		"the tap target is at least 44x44 (got %s)" % btn.custom_minimum_size)
	m.queue_free()
	_completes("pause_button_does_not_eat_the_game")


func _test_button_hides_when_open() -> void:
	var m: PauseMenu = _make_menu()
	m.open()
	_expect(_find_visible_button(m, "II") == null,
		"the pause button hides while the menu is open (the menu has its own Resume)")
	m.close()
	_expect(_find_visible_button(m, "II") != null, "...and comes back when it closes")
	# And a host that has no business showing one can turn it off outright.
	m.set_pause_button_visible(false)
	_expect(_find_visible_button(m, "II") == null,
		"set_pause_button_visible(false) hides it for hosts that do not want one")
	m.queue_free()
	_completes("pause_button_hides_while_the_menu_is_open")


# ------------------------------------------------------------------ 4+5+6
## The rows exist AND are reachable — the settings column is inside a ScrollContainer
## precisely because it already ran past the bottom of a 720p window, and these are two
## more rows on top of that.
func _test_settings_rows() -> void:
	var real: Node = _with_tuning()
	var m: PauseMenu = _make_menu()
	var labels: Array[String] = []
	_collect_labels(m, labels)
	for wanted: String in ["Master Volume", "Music Volume", "Camera Zoom", "Screen Shake"]:
		_expect(labels.has(wanted), "settings still has the `%s` row" % wanted)
	_expect(labels.has("Aim Assist  (0 = off)"),
		"settings has the AIM ASSIST row (phase 2.5)")
	_expect(_find_button_prefixed(m, "Graphics: ") != null,
		"settings has the GRAPHICS QUALITY row — forcing LOW on desktop is currently "
		+ "the only way to see the phone's picture, since no APK has ever been built")
	m.queue_free()
	_restore_tuning(real)
	_completes("settings_has_the_new_rows")


## The slider must write to the LIVE config, because `SpellTargets.assist_strength`
## re-reads it on the frame the aim is resolved. A row that updated a local copy would
## look correct and do nothing.
func _test_aim_assist_row() -> void:
	var real: Node = _with_tuning()
	var m: PauseMenu = _make_menu()
	var cfg: TuningConfig = (root.get_node_or_null("/root/Tuning") as FakeTuning).cfg
	_expect(is_equal_approx(cfg.aim_assist, 0.0),
		"the SHIPPED default is 0 — assist off, no-auto-aim rule intact")
	m.call("_on_aim_assist_changed", 0.6)
	_expect(is_equal_approx(cfg.aim_assist, 0.6),
		"the slider writes through to the live Tuning config (got %.2f)" % cfg.aim_assist)
	m.call("_on_aim_assist_changed", 0.0)
	_expect(is_equal_approx(cfg.aim_assist, 0.0), "...and back down to inert")
	m.queue_free()
	_restore_tuning(real)
	_completes("aim_assist_row_writes_through")


## AUTO -> HIGH -> LOW -> AUTO, with the label following. The label matters more than
## it looks: "Auto" alone leaves the one question the maker actually has ("am I looking
## at the phone's picture right now?") unanswered on the screen meant to answer it.
func _test_quality_row() -> void:
	var real: Node = _with_tuning()
	var m: PauseMenu = _make_menu()
	var cfg: TuningConfig = (root.get_node_or_null("/root/Tuning") as FakeTuning).cfg
	_expect(int(cfg.graphics_quality) == int(TuningConfig.Quality.AUTO),
		"it starts on AUTO (LOW on a mobile export, HIGH elsewhere)")
	var btn: Button = _find_button_prefixed(m, "Graphics: ")
	_expect(btn != null, "the quality row is a button")
	if btn == null:
		m.queue_free()
		_restore_tuning(real)
		return  # deliberately NOT completed
	_expect(btn.text.contains("AUTO"), "...labelled with the current state")
	m.call("_on_quality_pressed")
	_expect(int(cfg.graphics_quality) == int(TuningConfig.Quality.HIGH), "AUTO -> HIGH")
	_expect(btn.text.contains("HIGH"), "...and the label followed")
	m.call("_on_quality_pressed")
	_expect(int(cfg.graphics_quality) == int(TuningConfig.Quality.LOW), "HIGH -> LOW")
	_expect(TuningConfig.quality_is_low(),
		"forcing LOW really does report the cheap picture on a desktop run")
	m.call("_on_quality_pressed")
	_expect(int(cfg.graphics_quality) == int(TuningConfig.Quality.AUTO), "LOW -> AUTO (wraps)")
	m.queue_free()
	_restore_tuning(real)
	_completes("quality_row_cycles_and_labels_itself")


# ------------------------------------------------------------------- helpers
func _collect_labels(n: Node, out: Array[String]) -> void:
	var l: Label = n as Label
	if l != null:
		out.append(l.text)
	for c: Node in n.get_children():
		_collect_labels(c, out)


func _find_button_prefixed(n: Node, prefix: String) -> Button:
	var b: Button = n as Button
	if b != null and b.text.begins_with(prefix):
		return b
	for c: Node in n.get_children():
		var found: Button = _find_button_prefixed(c, prefix)
		if found != null:
			return found
	return null
