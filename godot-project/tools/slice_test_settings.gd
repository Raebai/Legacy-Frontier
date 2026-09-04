# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_settings.gd
#
# THE SETTINGS PANEL FITS THE SCREEN, THE SETTINGS SURVIVE THE GAME CLOSING, AND THE
# KEYS CAN BE REBOUND.
#
# Three faults, all of them measured before anything was written (see
# `tools/probe_settings_panel.gd`), and each assertion here exists because the obvious
# implementation of the fix is silently broken:
#
#   1. THE PANEL RESOLVED OFF-SCREEN. `custom_minimum_size = Vector2(320, 520)` inside a
#      `CenterContainer` on a 360-tall viewport is a 520-px panel, because a
#      CenterContainer hands its child the child's MINIMUM size. 160 px hung below the
#      screen edge — and since scrolling only moves content INSIDE that box, the bottom
#      160 px of the settings column could not be reached at any scroll position.
#      ⚠ A test that only checked `custom_minimum_size` would have passed the whole
#      time. This measures the RESOLVED GLOBAL RECT against the viewport.
#   2. ONLY ONE SETTING PERSISTED. Fullscreen. The other ten were written straight into
#      whatever owned them at runtime and forgotten on exit.
#      ⚠ A test that set a value and read the same value back proves nothing — the
#      in-memory copy answers correctly whether or not anything reached the disk. So
#      this WRITES, then SCRAMBLES the live value, then `Settings.forget_cache()` (the
#      in-memory ConfigFile is dropped and the file re-read), then `apply_all`, and only
#      then asks the live game what it thinks. That is a restart, inside one process.
#   3. THERE WAS NO KEY REBINDING. The rows here check the LIVE `InputMap`, not the
#      stored string: an override that is saved and never applied is the same feature
#      as no override at all.
#      ⚠ AND THE PAD MUST STAY OUT. `Input.is_action_pressed` aggregates every device,
#      so a joypad button bound to an action drives player ONE whenever player TWO
#      presses it. `is_rebindable_event` refuses it and this proves the refusal.
#
# ⚠ THIS SUITE NEVER TOUCHES `user://settings.cfg`. It points `Settings` at
# `user://settings_test.cfg` for its duration and deletes it at the end — otherwise
# running the tests would overwrite the maker's own volume, brightness and keybinds.
#
# ⚠ HEADLESS HAS NO WINDOW AND THEREFORE NO ASPECT RATIO: `get_visible_rect()` falls
# back to a SQUARE 640x640 and every vertical assertion below would be checked against
# 280 px of height the player does not have. `root.size` is set to a real 16:9 window
# and a frame waited on; `_test_the_harness_is_honest` fails the suite if that did not
# take, because every other measurement here depends on it.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead property read ABORTS the enclosing function and returns the type's zero, which
# `failed += _test_x()` reads as "no failures". So failures accumulate on the MEMBER
# `_fails` and every test records a completion sentinel as its last line: a test that
# aborts part-way is then missing from `_completed` and fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"the_harness_is_honest",
	"the_panel_fits_the_screen",
	"the_panel_scrolls_when_it_must",
	"nothing_is_wider_than_its_card",
	"no_control_is_left_on_the_stock_theme",
	"every_setting_survives_a_restart",
	"the_controls_page_has_a_row_per_action",
	"rebinding_moves_the_live_map",
	"a_rebind_survives_a_restart",
	"reset_restores_the_project_map",
	"the_pad_cannot_be_bound",
	"the_wielded_row_fits_its_column",
]

const Settings := preload("res://scripts/Settings.gd")
const HudStyle := preload("res://scripts/ui/HudStyle.gd")

## Somewhere that is not the maker's real settings file. See the header.
const TEST_CFG: String = "user://settings_test.cfg"

## The base viewport (`project.godot` window/size/viewport_{width,height}).
const BASE_W: float = 640.0
const BASE_H: float = 360.0

## `RunSummary.STAT_W` is 250 and the key label eats the left of the row, so the value
## half has about this much. Restated rather than derived: the point is to pin the
## number the row has to clear, and deriving it from the layout would make the test
## agree with whatever the layout happens to do.
const WIELDED_BUDGET: float = 185.0

var _fails: int = 0
var _completed: Dictionary = {}


## Stands in for the /root/Tuning autoload, holding a REAL `TuningConfig` so the rows
## write to the same resource type the game does. Same shape as the stand-in in
## `tools/slice_test_pause_menu.gd`.
class FakeTuning extends Node:
	var cfg: TuningConfig = TuningConfig.new()


## Stands in for /root/GameState. Only the two fields the settings rows touch — a real
## `GameState` drags the whole run spine into a suite about a menu.
class FakeGameState extends Node:
	var camera_zoom: float = 1.6
	var pvp_rules: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# A real 16:9 window, or `stretch/aspect="expand"` never resolves — see the header.
	root.size = Vector2i(1366, 768)
	await process_frame
	await process_frame

	# ⚠ REDIRECT THE SETTINGS FILE BEFORE ANYTHING READS OR WRITES ONE — and then CHECK
	# THAT THE REDIRECT TOOK. It did not, for a while, and the suite passed anyway while
	# quietly overwriting the maker's real `user://settings.cfg`: `Settings.reload()`
	# resolved to the engine's `Script.reload()`, which recompiled the script and reset
	# every static, `_path` included. See the note on `Settings.forget_cache`.
	#
	# A harness that can silently point at the wrong file is a harness that lies, so the
	# assertion below is not ceremony — it is the reason this suite can be trusted at all.
	Settings.use_path(TEST_CFG)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Settings.forget_cache()
	if Settings.path() != TEST_CFG:
		printerr(("FAIL: the settings file was NOT redirected (still %s) — refusing to "
			+ "run, because these tests write settings and would clobber the real file")
			% Settings.path())
		printerr("Settings tests: 1 FAILED")
		quit(1)
		return

	_test_the_harness_is_honest()
	await _test_the_panel_fits_the_screen()
	await _test_the_panel_scrolls_when_it_must()
	await _test_nothing_is_wider_than_its_card()
	await _test_no_stock_theme()
	await _test_every_setting_survives_a_restart()
	_test_controls_rows()
	_test_rebinding_moves_the_live_map()
	_test_a_rebind_survives_a_restart()
	_test_reset_restores_the_project_map()
	_test_the_pad_cannot_be_bound()
	await _test_the_wielded_row_fits()

	# Leave nothing behind: the file, the path override and the shipped key map.
	Settings.reset_all_bindings()
	Settings.forget_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Settings.use_path(Settings.PATH)

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Settings tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Settings tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ═══════════════════════════════════════════════════════════════ 0. the harness
## ⚠ EVERY VERTICAL ASSERTION BELOW IS WORTHLESS IF THIS ONE FAILS. Headless falls back
## to a square 640x640 viewport, which is 280 px of height that does not exist on the
## screen the game is played on — a panel that "fits" 640 tall is the exact bug this
## suite is about. Checked first and named for what it is.
func _test_the_harness_is_honest() -> void:
	var vp: Vector2 = root.get_visible_rect().size
	_expect(is_equal_approx(vp.x, BASE_W) and is_equal_approx(vp.y, BASE_H),
		("the viewport resolved to the real 640x360 base and not headless's square "
		+ "fallback (got %.0fx%.0f — set root.size and wait a frame)") % [vp.x, vp.y])
	_completes("the_harness_is_honest")


# ═══════════════════════════════════════════════════════════════ 1. the layout
## ⚠ THE ASSERTION THE WHOLE FIX HANGS ON, and it is about the RESOLVED RECT rather
## than the property that caused it. `custom_minimum_size` could be anything; what
## matters is whether the panel the player is looking at is on the screen.
func _test_the_panel_fits_the_screen() -> void:
	var menu: PauseMenu = await _open_settings_menu()
	var vp: Vector2 = root.get_visible_rect().size
	for named: Array in _pages(menu):
		var scroll: ScrollContainer = named[1] as ScrollContainer
		if scroll == null:
			continue
		menu.call("_show_page", named[2])
		await process_frame
		await process_frame
		var r: Rect2 = scroll.get_global_rect()
		_expect(r.position.y >= -0.5,
			"the %s card starts on screen (top at y %.1f)" % [named[0], r.position.y])
		_expect(r.end.y <= vp.y + 0.5,
			("the %s card ends on screen (bottom at y %.1f on a %.0f-tall viewport — "
			+ "the old hardcoded 520 put this 160 px past the edge)")
			% [named[0], r.end.y, vp.y])
		_expect(r.position.x >= -0.5 and r.end.x <= vp.x + 0.5,
			"the %s card fits the width (x %.1f..%.1f)" % [named[0], r.position.x, r.end.x])
	menu.queue_free()
	_completes("the_panel_fits_the_screen")


## Fitting is only half of it. A column taller than the screen has to SCROLL, and the
## bug being fixed was a panel that did both wrongly at once: too tall for the screen
## AND (for content between 360 and 520) too short to scroll.
func _test_the_panel_scrolls_when_it_must() -> void:
	var menu: PauseMenu = await _open_settings_menu()
	var scroll: ScrollContainer = menu.get("_settings_scroll") as ScrollContainer
	var col: VBoxContainer = menu.get("_settings_col") as VBoxContainer
	_expect(scroll != null and col != null, "the settings page exposes its scroll + column")
	if scroll == null or col == null:
		menu.queue_free()
		return   # deliberately NOT completed: the missing sentinel fails the suite
	var content: float = col.get_combined_minimum_size().y
	var box: float = scroll.get_global_rect().size.y
	_expect(content > box,
		("the built-in settings column is genuinely taller than one screen (%.0f vs "
		+ "%.0f) — if this ever stops being true the scroll assertions below are vacuous")
		% [content, box])
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	_expect(bar != null and bar.max_value - bar.page > 0.5,
		"…and the scrollbar has somewhere to go, so the last row is reachable")
	# The reachable band and the card are now the same thing — that is the fix.
	var vp: Vector2 = root.get_visible_rect().size
	var r: Rect2 = scroll.get_global_rect()
	var lost: float = maxf(-r.position.y, 0.0) + maxf(r.end.y - vp.y, 0.0)
	_expect(lost <= 0.5,
		("0 px of the card is off-screen at any scroll position (got %.1f — this was "
		+ "160.0 before the fix)") % lost)
	menu.queue_free()
	_completes("the_panel_scrolls_when_it_must")


## ⚠ THE OTHER HALF OF THE OVERFLOW FAULT, AND IT DID NOT LOOK LIKE ONE. The generated
## controls card measured 337 px in a panel authored at 320 with horizontal scrolling
## DISABLED — so it did not clip, it pushed the whole settings card out to 343 px wide.
## A `Label` with no autowrap and no `clip_text` does not shrink; it resizes its parent.
func _test_nothing_is_wider_than_its_card() -> void:
	var menu: PauseMenu = await _open_settings_menu()
	for named: Array in _pages(menu):
		var scroll: ScrollContainer = named[1] as ScrollContainer
		if scroll == null:
			continue
		menu.call("_show_page", named[2])
		await process_frame
		await process_frame
		var inner: float = scroll.get_global_rect().size.x
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		if bar != null and bar.visible:
			inner -= bar.size.x
		for l: Label in _all(scroll, "Label"):
			# An autowrapping or clipping label is allowed to be "too wide": it has been
			# told what to do about it. An unmanaged one has not.
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.clip_text:
				continue
			_expect(l.get_combined_minimum_size().x <= inner + 0.5,
				("the %s page's label \"%s\" fits its card (%.0f px into %.0f) — an "
				+ "unwrapped, unclipped Label widens the panel instead of clipping")
				% [named[0], l.text.substr(0, 28), l.get_combined_minimum_size().x, inner])
	menu.queue_free()
	_completes("nothing_is_wider_than_its_card")


## ⚠ THE COMPLAINT WAS "UGLY", AND THIS IS THE MEASURABLE HALF OF IT. Every button,
## slider and checkbox in this menu was on the STOCK GODOT THEME — grey rectangles —
## next to a pause button in the same file that had been hand-styled with a radius and
## a border, on top of a game drawn in chalk on near-black paper.
##
## ⚠ SCOPED TO THE THREE PLAYER-FACING PAGES, NOT THE WHOLE MENU. The F1 DIRECTOR hangs
## 130-odd buttons off this node and it is a debug rig that `export_presets.cfg`
## excludes from the pack outright — styling it would be work nobody can ever see, and
## sweeping the whole subtree here would have made this assertion about a file this
## workstream does not own.
func _test_no_stock_theme() -> void:
	var menu: PauseMenu = await _open_settings_menu()
	var plain: int = 0
	var sliders: int = 0
	var plain_sliders: int = 0
	var buttons: int = 0
	for named: Array in _pages(menu):
		var page: Node = named[2] as Node
		if page == null:
			continue
		for b: Button in _all(page, "Button"):
			buttons += 1
			if not b.has_theme_stylebox_override("normal"):
				plain += 1
				printerr("        unstyled button on %s: \"%s\"" % [named[0], b.text])
		for s: HSlider in _all(page, "HSlider"):
			sliders += 1
			if not s.has_theme_stylebox_override("slider"):
				plain_sliders += 1
	_expect(buttons >= 10, "there are buttons here to check (%d)" % buttons)
	_expect(plain == 0, "%d button(s) are still on the stock grey theme" % plain)
	_expect(sliders >= 5, "the sliders are still here to style (%d)" % sliders)
	_expect(plain_sliders == 0, "%d slider(s) still have the stock track" % plain_sliders)
	menu.queue_free()
	_completes("no_control_is_left_on_the_stock_theme")


# ═══════════════════════════════════════════════════════════ 2. persistence
## ⚠ THE ONE TEST THAT COULD MOST EASILY BE VACUOUS. Setting a value and reading it
## back proves only that a variable holds what it was assigned. So: set it, FLUSH,
## scramble every live value to something else, `Settings.forget_cache()` (the in-memory
## ConfigFile is dropped, the file is re-read from disk), `apply_all` — and only then
## ask the live game. If the write never reached the file, the scrambled value stands
## and the assertion fails.
func _test_every_setting_survives_a_restart() -> void:
	var saved: Dictionary = _stash_globals()
	var real_t: Node = _swap_in(FakeTuning.new(), "Tuning")
	var real_g: Node = _swap_in(FakeGameState.new(), "GameState")
	var menu: PauseMenu = await _open_settings_menu()
	var tcfg: TuningConfig = (root.get_node_or_null("/root/Tuning") as FakeTuning).cfg
	var gs: FakeGameState = root.get_node_or_null("/root/GameState") as FakeGameState

	# 1. Drive every row the way a player would.
	menu.call("_on_volume_changed", 0.37)
	menu.call("_on_music_volume_changed", 0.21)
	menu.call("_on_zoom_changed", 2.15)
	menu.call("_on_shake_changed", 0.35)
	menu.call("_on_hit_stop_toggled", false)
	menu.call("_on_aim_assist_changed", 0.45)
	menu.call("_on_quality_pressed")                       # AUTO -> HIGH
	menu.call("_on_pvp_pressed")                           # HEALTH -> STOCKS
	menu.call("_on_friendly_fire_toggled", not FriendlyFire.enabled())
	menu.call("_on_brightness_pressed")                    # Normal -> Bright
	var want_ff: bool = FriendlyFire.enabled()
	var want_bright: int = int(root.get_meta(Settings.BRIGHTNESS_META, 1))
	var want_colour: int = Outfitter.chosen_colourway
	if Outfitter.colourways().size() > 1:
		menu.call("_cycle_colour")
		want_colour = Outfitter.chosen_colourway
	Settings.flush()

	# 2. Scramble. Everything the file is supposed to remember is now WRONG in memory.
	Settings.set_bus_linear("Master", 1.0)
	Settings.set_bus_linear("Music", 1.0)
	gs.camera_zoom = 1.6
	gs.pvp_rules = 0
	tcfg.shake_scale = 0.7
	tcfg.hit_stop_enabled = true
	tcfg.aim_assist = 0.0
	tcfg.graphics_quality = TuningConfig.Quality.AUTO
	FriendlyFire.set_enabled(not want_ff)
	root.set_meta(Settings.BRIGHTNESS_META, Settings.BRIGHTNESS_DEFAULT)
	Outfitter.chosen_colourway = 0

	# 3. Relaunch, from the file and nothing else.
	Settings.forget_cache()
	Settings.apply_all(self)

	_expect(is_equal_approx(snappedf(Settings.bus_linear("Master"), 0.01), 0.37),
		"master volume came back (%.3f)" % Settings.bus_linear("Master"))
	_expect(is_equal_approx(snappedf(Settings.bus_linear("Music"), 0.01), 0.21),
		"music volume came back (%.3f)" % Settings.bus_linear("Music"))
	_expect(is_equal_approx(gs.camera_zoom, 2.15), "camera zoom came back (%.2f)" % gs.camera_zoom)
	_expect(gs.pvp_rules == 1, "the PvP rule came back (%d)" % gs.pvp_rules)
	_expect(is_equal_approx(tcfg.shake_scale, 0.35), "screenshake came back (%.2f)" % tcfg.shake_scale)
	_expect(not tcfg.hit_stop_enabled, "hit-stop came back off")
	_expect(is_equal_approx(tcfg.aim_assist, 0.45), "aim assist came back (%.2f)" % tcfg.aim_assist)
	_expect(int(tcfg.graphics_quality) == int(TuningConfig.Quality.HIGH),
		"graphics quality came back (%d)" % int(tcfg.graphics_quality))
	_expect(FriendlyFire.enabled() == want_ff, "friendly fire came back")
	_expect(int(root.get_meta(Settings.BRIGHTNESS_META, -1)) == want_bright,
		"brightness came back (%d)" % int(root.get_meta(Settings.BRIGHTNESS_META, -1)))
	_expect(Outfitter.chosen_colourway == want_colour,
		"the colourway came back (%d)" % Outfitter.chosen_colourway)

	menu.queue_free()
	_swap_out(real_g, "GameState")
	_swap_out(real_t, "Tuning")
	_restore_globals(saved)
	_completes("every_setting_survives_a_restart")


# ═══════════════════════════════════════════════════════════ 3. key rebinding
## The rows are DERIVED from `CONTROL_ROWS`, the same table the printed controls card
## has always used, so the two cannot disagree about which verbs the game has.
func _test_controls_rows() -> void:
	var rows: Array = PauseMenu.rebindable_rows()
	_expect(rows.size() >= 15, "there is a row for every verb (%d)" % rows.size())
	var seen: Dictionary = {}
	for row: Array in rows:
		var action: StringName = row[0] as StringName
		_expect(InputMap.has_action(action), "row `%s` names a real action" % action)
		_expect(not seen.has(action), "action `%s` gets exactly one row" % action)
		seen[action] = true
		_expect(String(row[1]).strip_edges() != "", "row `%s` has a label" % action)
	for wanted: StringName in [&"move_left", &"move_right", &"cast", &"ui_cancel"]:
		_expect(seen.has(wanted), "`%s` is rebindable" % wanted)
	# The two halves of "Move" must not both be called "Move".
	var labels: Dictionary = {}
	for row: Array in rows:
		labels[String(row[1])] = true
	_expect(labels.size() == rows.size(),
		"every row has a DISTINCT label (%d labels for %d rows — a shared entry name "
		% [labels.size(), rows.size()] + "must be suffixed by its action)")
	_completes("the_controls_page_has_a_row_per_action")


## ⚠ THE LIVE MAP, NOT THE STORED STRING. An override that is written to disk and never
## applied to `InputMap` is exactly as useful as no override at all, and it is the
## failure mode that looks most like success from the settings screen.
func _test_rebinding_moves_the_live_map() -> void:
	var before: String = Settings.binding_label(&"melee")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_K
	_expect(Settings.rebind(&"melee", ev), "the rebind was accepted")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	_expect(InputMap.event_is_action(k, &"melee"),
		"pressing K now IS the melee action, according to the live InputMap")
	_expect(Settings.binding_label(&"melee") == "K",
		"…and the cap says so (%s)" % Settings.binding_label(&"melee"))
	_expect(before != "K", "the test is not vacuous — melee was `%s` before" % before)
	# The old key must be gone, or the player has two melee keys and only asked for one.
	var old := InputEventKey.new()
	old.physical_keycode = KEY_F
	_expect(not InputMap.event_is_action(old, &"melee"),
		"the key it used to be on no longer fires it")
	_completes("rebinding_moves_the_live_map")


## Same restart shape as the settings round-trip: reset the LIVE map back to the
## project's own bindings without writing that reset to disk, drop the in-memory config,
## re-read the file, re-apply. If the override never reached the file, melee is F again.
func _test_a_rebind_survives_a_restart() -> void:
	Settings.flush()
	Settings.reset_all_bindings()      # live map back to project.godot's answer
	_expect(Settings.binding_label(&"melee") != "K", "the map really was put back")
	Settings.forget_cache()                  # forget the in-memory erase; re-read the file
	Settings.apply_input_overlay()
	_expect(Settings.binding_label(&"melee") == "K",
		"the rebind came back off disk (got %s)" % Settings.binding_label(&"melee"))
	_completes("a_rebind_survives_a_restart")


## ⚠ "RESET TO DEFAULTS" NEEDS DEFAULTS TO EXIST. A rebind overwrites `InputMap` in
## place, so unless the shipped map was snapshotted BEFORE the first override there is
## nothing to return to — and `project.godot` is not this workstream's file to read back
## from. `Settings.capture_input_defaults()` runs at boot and again in `PauseMenu.build`.
func _test_reset_restores_the_project_map() -> void:
	Settings.reset_all_bindings()
	Settings.flush()
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	_expect(InputMap.event_is_action(f, &"melee"),
		"melee is back on the key project.godot binds it to")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	_expect(not InputMap.event_is_action(k, &"melee"), "…and off the one it was moved to")
	Settings.forget_cache()
	_expect(not Settings.cfg().has_section(Settings.S_INPUT),
		"the override is gone from the file too, not just from the map")
	_completes("reset_restores_the_project_map")


## ⚠ THE PAD MUST NEVER REACH THE ACTION MAP. `Input.is_action_pressed` aggregates every
## connected device, so a joypad button bound to `move_left` walks player ONE whenever
## player TWO pushes their stick. This repo keeps the pad out of the map deliberately
## and reads raw per-device state in `PadController`; a rebind screen is the easiest
## possible way to undo that by accident.
func _test_the_pad_cannot_be_bound() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	_expect(not Settings.is_rebindable_event(pad), "a joypad BUTTON is not rebindable")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	_expect(not Settings.is_rebindable_event(stick), "a joypad AXIS is not rebindable")
	_expect(not Settings.rebind(&"melee", pad), "…and `rebind` refuses it outright")
	_expect(not InputMap.event_is_action(pad, &"melee"),
		"the refused pad button really is not on the action")
	# A mouse button IS allowed — `cast` and `parry` ship on LMB/RMB.
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	_expect(Settings.is_rebindable_event(lmb), "a mouse button IS rebindable (cast is LMB)")
	_completes("the_pad_cannot_be_bound")


# ═══════════════════════════════════════════════════════ 4. the run card's row
## ⚠ MEASURED, AT THE FONT IT IS DRAWN AT. The `wielded` row joined every element the
## run used into one unwrapped, unclipped `Label`: eight names measured 272 px into a
## column with about 185 px for the value, so from six elements on it ran out over the
## drawn tower beside it.
func _test_the_wielded_row_fits() -> void:
	var every: Array = ["Fire", "Ice", "Shadow", "Storm", "Arcane", "Poison", "Holy",
		"Blood"]
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", HudStyle.SMALL)
	root.add_child(lab)
	var worst: float = 0.0
	for n: int in range(1, every.size() + 1):
		lab.text = RunSummary.wielded_text(every.slice(0, n))
		await process_frame
		worst = maxf(worst, lab.get_combined_minimum_size().x)
	_expect(worst <= WIELDED_BUDGET,
		("the widest `wielded` value fits its column (%.0f px of %.0f — 8 elements "
		+ "measured 272 px before the cap)") % [worst, WIELDED_BUDGET])
	# And the cap must not have quietly dropped the information.
	var text: String = RunSummary.wielded_text(every)
	_expect(text.contains("+%d" % (every.size() - RunSummary.WIELDED_SHOWN)),
		"…and it still says how many it did not name (`%s`)" % text)
	lab.queue_free()
	_completes("the_wielded_row_fits_its_column")


# ═══════════════════════════════════════════════════════════════════ helpers
func _open_settings_menu() -> PauseMenu:
	var m := PauseMenu.new()
	root.add_child(m)
	m.build("Exit")
	m.open()
	m.call("_open_settings")
	await process_frame
	await process_frame
	return m


## `[name, scroll, center]` for each of the three pages.
func _pages(m: PauseMenu) -> Array:
	return [
		["main", m.get("_main_scroll"), m.get("_main_center")],
		["settings", m.get("_settings_scroll"), m.get("_settings_center")],
		["controls", m.get("_controls_scroll"), m.get("_controls_center")],
	]


## Every descendant of a given class. Walks the real tree rather than trusting a stored
## reference — "is it styled" is a question about what is actually on screen.
func _all(from: Node, cls: String) -> Array:
	var out: Array = []
	if from.is_class(cls):
		out.append(from)
	for c: Node in from.get_children():
		out.append_array(_all(c, cls))
	return out


## Swap a stand-in onto /root under an autoload's name, returning the real one (or null)
## so it can be put back. Synchronous, with no awaits in between, so nothing else in the
## tree ever observes the substitution.
func _swap_in(fake: Node, autoload_name: String) -> Node:
	var real: Node = root.get_node_or_null("/root/%s" % autoload_name)
	if real != null:
		root.remove_child(real)
	fake.name = autoload_name
	root.add_child(fake)
	return real


func _swap_out(real: Node, autoload_name: String) -> void:
	var fake: Node = root.get_node_or_null("/root/%s" % autoload_name)
	if fake != null:
		root.remove_child(fake)
		fake.free()
	if real != null:
		root.add_child(real)


## ⚠ FOUR OF THE SETTINGS LIVE IN PROCESS-WIDE STATE (two audio buses, a static on
## `SpellCaster` via `FriendlyFire`, a static on `Outfitter`, metadata on the tree root)
## and this suite deliberately changes all of them. Anything left behind would leak into
## whatever suite the runner starts next.
func _stash_globals() -> Dictionary:
	return {
		"master": Settings.bus_linear("Master"),
		"music": Settings.bus_linear("Music"),
		"ff": FriendlyFire.enabled(),
		"colour": Outfitter.chosen_colourway,
		"bright": root.get_meta(Settings.BRIGHTNESS_META, Settings.BRIGHTNESS_DEFAULT),
	}


func _restore_globals(saved: Dictionary) -> void:
	Settings.set_bus_linear("Master", float(saved["master"]))
	Settings.set_bus_linear("Music", float(saved["music"]))
	FriendlyFire.set_enabled(bool(saved["ff"]))
	Outfitter.chosen_colourway = int(saved["colour"])
	root.set_meta(Settings.BRIGHTNESS_META, int(saved["bright"]))
