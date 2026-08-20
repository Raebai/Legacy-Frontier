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
## ⚠ AND THERE WAS NO PERSISTENCE LAYER TO HOOK INTO, WHICH IS WHY THIS FILE OWNS ONE.
## Four incompatible mechanisms are in use today and ALL FOUR forget on exit: the feel
## knobs live in a `res://` Resource that is only ever LOADED (`Tuning.gd` has no
## `ResourceSaver` call), camera zoom lives on `GameState` but is not in the save
## payload, brightness is stashed as metadata on the SceneTree root, and the volume
## sliders are written straight into `AudioServer` and never stored. A player who sets
## fullscreen and quits must not have to set it again, so this writes a real file —
## `user://settings.cfg`, which `docs/references/stick-fight-feel-study.md` already
## asked for. Other settings can move in here later; the shape is deliberately generic.
##
## ⚠ EXCLUSIVE vs WINDOWED-FULLSCREEN. This uses `WINDOW_MODE_FULLSCREEN`, which is
## Godot's borderless "windowed fullscreen", NOT `WINDOW_MODE_EXCLUSIVE_FULLSCREEN`.
## Exclusive takes the display mode over, which makes alt-tab slow and — the reason
## that matters here — makes screen capture unreliable. This project's whole content
## pipeline is screen capture.

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "display"
const KEY_FULLSCREEN: String = "fullscreen"


func _ready() -> void:
	# Runs while paused: the toggle has to work from the pause menu, which is the one
	# place a player is most likely to look for it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()


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


# ---------------------------------------------------------------- persistence

func _load() -> void:
	# ⚠ NEVER FORCE A WINDOW MODE IN A HEADLESS RUN. The suites and the whole capture
	# pipeline boot this autoload, and asking for fullscreen on a dummy display is at
	# best wasted and at worst a resize the frame-grabber then films.
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return                      # no file yet: keep the project default (windowed)
	if bool(cfg.get_value(SECTION, KEY_FULLSCREEN, false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _save(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)         # keep anything else already in the file
	cfg.set_value(SECTION, KEY_FULLSCREEN, on)
	cfg.save(SETTINGS_PATH)
