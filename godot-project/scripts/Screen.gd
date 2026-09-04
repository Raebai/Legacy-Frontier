extends Node
## Autoload "Screen" — the window mode, and the first setting in this project that
## SURVIVES CLOSING THE GAME.
##
## Maker: *"this game needs full screen capabilities"*.
##
## ⚠ THERE WAS NO WINDOW-MODE CODE AT ALL. Not a toggle, not a menu row, not a
## keybind — `DisplayServer.window_set_mode` appears nowhere in the project. The only
## `fullscreen` identifier in the codebase is
## `ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND`, which is a photosensitivity budget
## for screen flashes and has nothing to do with the window.
##
## ⚠ AND THERE WAS NO PERSISTENCE LAYER TO HOOK INTO, WHICH IS WHY THIS FILE OWNED ONE.
## Four incompatible mechanisms were in use and ALL FOUR forgot on exit: the feel knobs
## live in a `res://` Resource that is only ever LOADED (`Tuning.gd` has no
## `ResourceSaver` call), camera zoom lives on `GameState` but is not in the save
## payload, brightness is stashed as metadata on the SceneTree root, and the volume
## sliders are written straight into `AudioServer` and never stored. A player who sets
## fullscreen and quits must not have to set it again, so this wrote a real file —
## `user://settings.cfg`, which `docs/references/stick-fight-feel-study.md` already
## asked for.
##
## ⚠ "OTHER SETTINGS CAN MOVE IN HERE LATER" — THEY HAVE. `scripts/Settings.gd` now
## owns that file and the other ten preferences (volume x2, camera zoom, screenshake,
## hit-stop, aim assist, friendly fire, PvP rules, graphics quality, brightness,
## colourway, plus the key-rebinding overlay). The fullscreen key below is UNCHANGED —
## same path, same `[display]` section, same key — so a settings.cfg written before
## that split is read back exactly as it was.
##
## THIS FILE STAYS THE ONE THAT DRIVES IT, for two reasons that are both about
## ordering: it is the LAST autoload in `project.godot`, so `Tuning`, `GameState` and
## the audio buses are all up by the time `_ready` runs here; and it is
## `PROCESS_MODE_ALWAYS`, so the debounced flush keeps ticking while the pause menu
## has the rest of the tree frozen — which is the exact moment settings are changed.
##
## ⚠ EXCLUSIVE vs WINDOWED-FULLSCREEN. This uses `WINDOW_MODE_FULLSCREEN`, which is
## Godot's borderless "windowed fullscreen", NOT `WINDOW_MODE_EXCLUSIVE_FULLSCREEN`.
## Exclusive takes the display mode over, which makes alt-tab slow and — the reason
## that matters here — makes screen capture unreliable. This project's whole content
## pipeline is screen capture.

const Settings := preload("res://scripts/Settings.gd")

const SETTINGS_PATH: String = Settings.PATH
const SECTION: String = Settings.S_DISPLAY
const KEY_FULLSCREEN: String = "fullscreen"


func _ready() -> void:
	# Runs while paused: the toggle has to work from the pause menu, which is the one
	# place a player is most likely to look for it — and it is what keeps the debounced
	# settings flush in `_process` ticking while the game itself is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ⚠ CAPTURE THE SHIPPED KEY MAP BEFORE ANYTHING TOUCHES IT, unconditionally —
	# including in the runs that skip the restore below. A rebind overwrites the map in
	# place, so "reset to defaults" has nothing to return to unless the snapshot was
	# taken first, and a headless suite that rebinds must still be able to reset.
	Settings.capture_input_defaults()
	if _skip_restore():
		return
	Settings.apply_all(get_tree())
	_load()


## Should this run put the player's saved preferences back on?
##
## ⚠ TWO RUNS SAY NO, AND BOTH OF THEM ARE OTHER PEOPLE'S TOOLING.
##
##   * HEADLESS — every test suite and the whole botmatch/telemetry side. A suite that
##     inherited whatever the maker last dragged a slider to is a suite that passes on
##     one machine. (`_load` already refused fullscreen here for its own reason: asking
##     a dummy display to go fullscreen is at best wasted.)
##   * `--write-movie` — the clip shoot. It renders with a real window, so it would
##     otherwise pick up the maker's personal screenshake, brightness and graphics
##     quality and bake them into footage that gets posted. The pipeline is entitled to
##     the SHIPPED look; a clip is not a play session.
##
## Deliberately NOT gated on `OS.is_debug_build()`: the maker plays a debug build.
func _skip_restore() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--write-movie"):
			return true
	return false


## The debounced write. One bool test on a clean frame — see Settings.FLUSH_DELAY_MSEC
## for why a save-per-`value_changed` was not an option.
##
## ⚠ `Settings` IS THE SCRIPT RESOURCE, NOT AN INSTANCE. `const X := preload("....gd")`
## yields the `GDScript` object, so `Settings.flush_if_due()` only resolves because that
## function is declared `static func`. A plain `func` would compile cleanly here and then
## fail at RUNTIME with "Nonexistent function ... in base 'GDScript'" the first frame this
## line is reached — one of the resolution traps this project has already paid for.
## Option 1 of the two ways out was taken: every entry point on `Settings` is static and
## all of its state lives in `static var`s, which is also the honest shape for a
## preferences store that is a singleton by nature.
##
## ⚠ AND STATIC NAMES SHARE A NAMESPACE WITH `Script`/`Resource`/`Object`. `Settings`
## briefly had a static `reload()`; every external call to it hit the ENGINE's
## `Script.reload()`, recompiled the script and reset every static in it, silently. It is
## `forget_cache()` now — see the long note there.
func _process(_delta: float) -> void:
	Settings.flush_if_due()


## ⚠ THE TWO WAYS A GAME ACTUALLY STOPS, and neither of them is a frame going by.
## A desktop quit and an Android task-switch both end the process without giving the
## debounce time to fire, so a slider nudged in the last third of a second would be
## lost — which reads exactly like "settings still do not save".
##
## Nothing here BLOCKS the quit (no `set_auto_accept_quit(false)`): the write is a few
## hundred bytes of ConfigFile and a hang on exit would be a worse bug than the one
## being fixed.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			Settings.flush()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			Settings.flush()
		NOTIFICATION_APPLICATION_PAUSED:
			Settings.flush()
		NOTIFICATION_EXIT_TREE:
			Settings.flush()


## ⚠ `_input`, NOT `_unhandled_input`. A fullscreen key that stops working because a
## menu has focus is a fullscreen key that looks broken — and every screen in this game
## that could swallow it (the pause menu, the loadout, the lobby) is exactly where a
## player goes looking for display options.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"fullscreen"):
		toggle()
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var m: int = DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func toggle() -> void:
	set_fullscreen(not is_fullscreen())


func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on
		else DisplayServer.WINDOW_MODE_WINDOWED)
	_save(on)
	_report("toggle")


## ⚠ THE TOGGLE SAYS WHAT IT DID, OUT LOUD. "Fullscreen does not work" was reported
## twice while every measurement available here said it does: a standalone run, a run
## with the real main scene booted, and a boot straight into a saved fullscreen all
## filled a 2560x1600 screen at exactly 4.00x. That gap between the report and the
## instrument is the thing to close, and it cannot be closed from this side - so the
## game now writes the four numbers that settle it into `user://logs/`, where they
## can be read after the fact rather than guessed at.
##
## `canvas scale` is the one that matters. The logical viewport reads 640x360 whether
## scaling works or not, so it is NOT the tell; the final transform is what the renderer
## actually applied. Scale 1.0 on a 2560-wide window means the picture is being drawn at
## 640x360 in the corner of a black screen. Scale ~4.0 means it fills it.
func _report(why: String) -> void:
	await get_tree().process_frame
	var vp: Viewport = get_viewport()
	var scale: Vector2 = vp.get_final_transform().get_scale() if vp != null else Vector2.ZERO
	print("[screen] %s -> mode %d | window %s | screen %s | canvas scale %s"
		% [why, DisplayServer.window_get_mode(), DisplayServer.window_get_size(),
			DisplayServer.screen_get_size(), scale])


# ---------------------------------------------------------------- persistence

func _load() -> void:
	# ⚠ NEVER FORCE A WINDOW MODE IN A HEADLESS RUN. The suites and the whole capture
	# pipeline boot this autoload, and asking for fullscreen on a dummy display is at
	# best wasted and at worst a resize the frame-grabber then films.
	if DisplayServer.get_name() == "headless":
		return
	if bool(Settings.get_v(SECTION, KEY_FULLSCREEN, false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# A player who turned fullscreen on once takes THIS path on every later launch
		# and never touches the toggle, so it has to report too or the common case is
		# the one with no evidence.
		_report("startup")


## ⚠ WRITTEN THROUGH `Settings`, NOT WITH A SECOND `ConfigFile`. The old version
## loaded the file, set one key and saved — correct on its own, and a data-loss bug the
## moment a second writer existed: the pause menu's in-memory copy holds ten other keys
## the player has just changed, and a fresh load-set-save from here would write a file
## built from what was on DISK and clobber all of them on the next flush.
##
## Flushed IMMEDIATELY rather than debounced. Fullscreen is one discrete press, not a
## drag, and it is the setting whose forgetting was reported.
func _save(on: bool) -> void:
	Settings.set_v(SECTION, KEY_FULLSCREEN, on)
	Settings.flush()
