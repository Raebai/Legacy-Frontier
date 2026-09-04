extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════════
## USER PREFERENCES THAT SURVIVE CLOSING THE GAME — one file, one owner.
## ═══════════════════════════════════════════════════════════════════════════════
##
## ⚠ BEFORE THIS, EXACTLY ONE SETTING PERSISTED. `Screen.gd` says so in its own
## header and it was right: fullscreen wrote `user://settings.cfg` and everything
## else forgot on exit. Four incompatible mechanisms, all of them volatile —
##
##   * master + music volume  -> straight into `AudioServer`, never stored
##   * camera zoom            -> `GameState.camera_zoom`, NOT in the save payload
##   * shake / hit-stop / aim assist / graphics quality -> `Tuning.cfg`, a `res://`
##     Resource that `Tuning.gd` only ever LOADS (there is no `ResourceSaver` call
##     anywhere in the project)
##   * brightness             -> metadata on the SceneTree root, which dies with the
##     process
##   * friendly fire          -> a static bool on `SpellCaster`
##   * colourway              -> a static on `Outfitter`
##
## — so a player set nine things, quit, and set all nine again. This routes every one
## of them through the same ConfigFile `Screen` already writes, keyed by section so
## the fullscreen key it wrote before this existed is read back untouched.
##
## ⚠ NO `class_name`, DELIBERATELY. Registering a global class rewrites Godot's
## `global_script_class_cache.cfg`, and several agents are editing this checkout at
## once — a concurrent import corrupts that cache and takes the whole dependency
## chain down with a misleading "missing method" error somewhere else entirely
## (Sessions 6/8/9 lost time to exactly that). Consumers do:
##
##     const Settings := preload("res://scripts/Settings.gd")
##
## which resolves at compile time, needs no import, and — because `preload` returns
## the one GDScript resource — shares the static state below across every consumer.
##
## ⚠ EVERYTHING HERE IS STATIC AND MUST STAY THAT WAY ABOUT AUTOLOADS: naming an
## autoload (`Tuning`, `GameState`, `Music`) as a bare identifier inside a static
## function is a COMPILE error in GDScript, and it surfaces as an unrelated missing
## method. The trap is documented on `TuningConfig.quality_is_low()` and
## `ImpactFrame.reduce_flashing()`. Every autoload here is reached through the tree
## the caller hands in. Global CLASSES (`FriendlyFire`, `Outfitter`, `TuningConfig`)
## are fine — they are not autoloads.

## The same file `Screen.gd` has always written. Sections keep the two apart.
const PATH: String = "user://settings.cfg"

const S_DISPLAY: String = "display"    # owned by Screen.gd (fullscreen)
const S_AUDIO: String = "audio"
const S_CAMERA: String = "camera"
const S_FEEL: String = "feel"
const S_GAME: String = "game"
const S_VIDEO: String = "video"
const S_LOOK: String = "look"
const S_INPUT: String = "input"        # the key-rebinding overlay

const K_MASTER: String = "master_volume"
const K_MUSIC: String = "music_volume"
const K_ZOOM: String = "camera_zoom"
const K_SHAKE: String = "screen_shake"
const K_HIT_STOP: String = "hit_stop"
const K_AIM_ASSIST: String = "aim_assist"
const K_FRIENDLY_FIRE: String = "friendly_fire"
const K_PVP_RULES: String = "pvp_rules"
const K_QUALITY: String = "graphics_quality"
const K_BRIGHTNESS: String = "brightness"
const K_COLOURWAY: String = "colourway"

## ⚠ THE BRIGHTNESS STEP LIVES ON THE TREE ROOT AS METADATA AND THE KEY IS DECLARED
## HERE so there is one string, not two. `PauseMenu.BRIGHTNESS_META` aliases this.
## The root `Window` is the one node that outlives `change_scene_to_file`, and
## `set_meta` needs no declaration to stick — see the long note in PauseMenu for why
## it is not a `Tuning.cfg` field like every other picture knob.
const BRIGHTNESS_META: StringName = &"pause_menu_brightness"
const BRIGHTNESS_STEPS: int = 3
const BRIGHTNESS_DEFAULT: int = 1

## How long a value has to sit still before it is written to disk.
##
## ⚠ THIS IS WHY THERE IS A FLUSH AT ALL RATHER THAN A SAVE PER `set_v`. `HSlider`
## emits `value_changed` on every pixel of a drag: a save-per-change is ~60 file
## writes a second on the volume slider, on a phone, on flash storage. Every writer
## marks dirty and `Screen` (an autoload with `PROCESS_MODE_ALWAYS`, so it keeps
## running while the pause menu has the tree frozen) flushes once the dust settles —
## plus immediately on quit and on the app being backgrounded, which is how a phone
## actually stops.
const FLUSH_DELAY_MSEC: int = 400

## ⚠ THE PATH IS A VARIABLE SO A SUITE CAN POINT IT SOMEWHERE ELSE, and that is not
## test-scaffolding for its own sake: the only honest way to prove a setting SURVIVES A
## RESTART is to write it, throw the in-memory copy away, read the file back and check
## the live value returned — and a suite that did that against `user://settings.cfg`
## would overwrite the maker's own volume, brightness and keybinds every time it ran.
## Ships at `PATH` and nothing but `tools/slice_test_settings.gd` ever moves it.
static var _path: String = PATH

static var _cfg: ConfigFile = null
static var _dirty: bool = false
static var _dirty_at_msec: int = 0
## action -> Array[InputEvent], as `project.godot` shipped it. Captured ONCE at boot
## BEFORE any stored overlay is applied — see `capture_input_defaults`.
static var _defaults: Dictionary = {}
static var _defaults_captured: bool = false


# ═════════════════════════════════════════════════════════════════════ the file
## The one ConfigFile, loaded lazily. A missing file is not an error: every getter
## below takes a default, so a first launch is simply "everything at its default".
static func cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(_path)  # OK or ERR_FILE_CANT_OPEN; either way we have an object
	return _cfg


## Where the file lives right now.
static func path() -> String:
	return _path


## ⚠ TESTS ONLY — see the note on `_path`. Drops the in-memory copy, so the next read
## comes off the new file.
static func use_path(p: String) -> void:
	_path = p
	forget_cache()


## Forget everything held in memory and re-read on next access. This is what "the
## player closed the game and opened it again" looks like from inside one process, and
## it is the only way a suite can prove persistence rather than assert it.
##
## ⚠ DO NOT CALL THIS `reload()`. IT WAS, AND IT COST AN HOUR — a fourth GDScript
## resolution trap to file next to the three already in this project's memory.
##
## A `const X := preload("....gd")` is the SCRIPT RESOURCE, and `Script` already has a
## built-in `reload()` that RECOMPILES the script. `Settings.reload()` from another file
## therefore called the engine's method, not this one — and recompiling re-runs every
## static initialiser, so `_path`, `_cfg`, `_dirty`, `_defaults` and `_defaults_captured`
## all silently snapped back to their declared values.
##
## The symptom was not an error. The suite's `use_path` redirect was undone two lines
## after it was made, so the tests quietly ran against — and OVERWROTE — the maker's real
## `user://settings.cfg` while reporting all PASS. Measured:
##
##     A user://settings.cfg          (start)
##     B user://settings_test.cfg     (after use_path)
##     D user://settings.cfg          (after one more `reload()`)
##
## The lesson generalises: a static "API" on a preloaded script shares a namespace with
## every method of `Script`, `Resource` and `Object`. `get_v`/`set_v` are named that way
## for the same reason — `get()` and `set()` are `Object`'s.
static func forget_cache() -> void:
	_cfg = null
	_dirty = false


static func get_v(section: String, key: String, fallback: Variant) -> Variant:
	return cfg().get_value(section, key, fallback)


## Store a value and mark the file dirty. Does NOT touch the disk — see FLUSH_DELAY_MSEC.
static func set_v(section: String, key: String, value: Variant) -> void:
	cfg().set_value(section, key, value)
	_dirty = true
	_dirty_at_msec = Time.get_ticks_msec()


## Write now, if there is anything to write. Cheap and safe to call when clean.
static func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var err: int = cfg().save(_path)
	if err != OK:
		# Loud, because a settings file that silently fails to write looks exactly
		# like a settings file that is never read.
		printerr("[settings] could not write %s (error %d)" % [_path, err])


## Called every frame by `Screen`. One bool test in the common case.
static func flush_if_due() -> void:
	if not _dirty:
		return
	if Time.get_ticks_msec() - _dirty_at_msec < FLUSH_DELAY_MSEC:
		return
	flush()


## Every persisted setting, as [key, "where it lands"]. Exists so a probe can print
## the list rather than a human maintaining a second copy of it in a doc.
static func known_keys() -> Array:
	return [
		[K_MASTER, "AudioServer 'Master' bus"],
		[K_MUSIC, "AudioServer 'Music' bus"],
		[K_ZOOM, "GameState.camera_zoom"],
		[K_SHAKE, "Tuning.cfg.shake_scale"],
		[K_HIT_STOP, "Tuning.cfg.hit_stop_enabled"],
		[K_AIM_ASSIST, "Tuning.cfg.aim_assist"],
		[K_QUALITY, "Tuning.cfg.graphics_quality"],
		[K_FRIENDLY_FIRE, "FriendlyFire.set_enabled -> SpellCaster.friendly_fire"],
		[K_PVP_RULES, "GameState.pvp_rules"],
		[K_BRIGHTNESS, "SceneTree root meta '%s'" % BRIGHTNESS_META],
		[K_COLOURWAY, "Outfitter.chosen_colourway"],
		["<per action>", "InputMap overlay (keyboard/mouse only)"],
	]


# ══════════════════════════════════════════════════════════════════ apply at boot
## Push every stored preference back onto the live game. Called once, from the LAST
## autoload (`Screen`), so `Tuning`, `GameState` and the audio buses all exist by the
## time this runs — autoload order in `project.godot` is load-bearing here.
##
## Every step is individually null-guarded rather than gated on one big check: a
## stripped build, a headless suite or a scene opened with F6 can be missing any one
## of these, and one absent autoload must not stop the other ten settings restoring.
static func apply_all(tree: SceneTree) -> void:
	apply_audio()
	apply_input_overlay()
	if tree == null:
		return
	var cf: ConfigFile = cfg()

	var gs: Node = tree.root.get_node_or_null(^"/root/GameState")
	if gs != null:
		gs.set("camera_zoom", float(cf.get_value(S_CAMERA, K_ZOOM, gs.get("camera_zoom"))))
		gs.set("pvp_rules", int(cf.get_value(S_GAME, K_PVP_RULES, gs.get("pvp_rules"))))

	var tcfg: Object = tuning_cfg(tree)
	if tcfg != null:
		tcfg.set("shake_scale", float(cf.get_value(S_FEEL, K_SHAKE, tcfg.get("shake_scale"))))
		tcfg.set("hit_stop_enabled",
			bool(cf.get_value(S_FEEL, K_HIT_STOP, tcfg.get("hit_stop_enabled"))))
		tcfg.set("aim_assist", float(cf.get_value(S_FEEL, K_AIM_ASSIST, tcfg.get("aim_assist"))))
		tcfg.set("graphics_quality",
			int(cf.get_value(S_VIDEO, K_QUALITY, tcfg.get("graphics_quality"))))

	# ⚠ ONLY WRITTEN WHEN THE FILE ACTUALLY CARRIES ONE. `FriendlyFire.set_enabled`
	# re-points every spectacle at a faction group; calling it with the value it
	# already has is harmless, but calling it on a fresh install would make this the
	# thing that decides the default instead of `SpellCaster`.
	if cf.has_section_key(S_GAME, K_FRIENDLY_FIRE):
		FriendlyFire.set_enabled(bool(cf.get_value(S_GAME, K_FRIENDLY_FIRE, true)))

	tree.root.set_meta(BRIGHTNESS_META, clampi(
		int(cf.get_value(S_VIDEO, K_BRIGHTNESS, BRIGHTNESS_DEFAULT)), 0, BRIGHTNESS_STEPS - 1))

	var ways: int = Outfitter.colourways().size()
	if ways > 0:
		Outfitter.chosen_colourway = clampi(
			int(cf.get_value(S_LOOK, K_COLOURWAY, Outfitter.chosen_colourway)), 0, ways - 1)


## The audio half, split out because it needs no tree at all — the AudioServer is a
## singleton and is up before the first autoload.
static func apply_audio() -> void:
	var cf: ConfigFile = cfg()
	set_bus_linear("Master", float(cf.get_value(S_AUDIO, K_MASTER, bus_linear("Master"))))
	set_bus_linear("Music", float(cf.get_value(S_AUDIO, K_MUSIC, bus_linear("Music"))))


# ══════════════════════════════════════════════════════════════════════ the knobs
## Volume as a 0..1 linear value. A bus that does not exist reads as full, so a build
## with no dedicated Music bus shows a slider at the top rather than at silence.
static func bus_linear(bus: String) -> float:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return 1.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


static func set_bus_linear(bus: String, v: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	# A linear 0 slider means SILENCE, and `linear_to_db(0)` is -inf, which some
	# drivers turn into a NaN gain. -80 dB is the floor the mixer uses for "off".
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0)


## The `Tuning` autoload's live config resource, or null under `--script` where no
## autoload is registered. Reached through the tree — see the header on why a static
## function may not say `Tuning`.
static func tuning_cfg(tree: SceneTree) -> Object:
	if tree == null:
		return null
	var t: Node = tree.root.get_node_or_null(^"/root/Tuning")
	return null if t == null else t.get("cfg")


# ═══════════════════════════════════════════════════════════ input rebinding
## ⚠ KEYBOARD AND MOUSE ONLY, AND THIS IS A CORRECTNESS RULE RATHER THAN A SCOPE CUT.
## `Input.is_action_pressed` AGGREGATES EVERY DEVICE: bind a joypad button to
## `move_left` and player one walks whenever player TWO pushes their stick. The repo
## keeps the pad out of the action map on purpose and reads raw per-device joypad
## state in `PadController`. Anything that is not a key or a mouse button is refused.
static func is_rebindable_event(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return k.physical_keycode != 0 or k.keycode != 0
	return ev is InputEventMouseButton


## What goes on a key cap.
##
## ⚠ PHYSICAL KEYCODE FIRST. Every binding in `project.godot` is stored physically so
## QWERTY and AZERTY players get the same LAYOUT, which means `keycode` is 0 on all of
## them and reading it would print nothing at all.
##
## `as_text()` is deliberately unused although it is shorter: it DECORATES — a
## physical key comes back as "A (Physical)" and a mouse button as "Left Mouse
## Button", neither of which fits a cap whose whole job is to be scanned.
static func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return OS.get_keycode_string(code) if code != 0 else ""
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel Down"
	return ""


## Serialised form, chosen to be legible when a maker opens `settings.cfg` in a text
## editor: `k:65`, `m:1`. A Dictionary would round-trip just as well and read like a
## memory dump.
static func event_to_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return "k:%d" % code
	if ev is InputEventMouseButton:
		return "m:%d" % (ev as InputEventMouseButton).button_index
	return ""


static func text_to_event(s: String) -> InputEvent:
	var parts: PackedStringArray = s.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var n: int = int(parts[1])
	if parts[0] == "k":
		var k := InputEventKey.new()
		k.physical_keycode = n
		return k
	if parts[0] == "m":
		var m := InputEventMouseButton.new()
		m.button_index = n
		return m
	return null


## Snapshot the map AS `project.godot` SHIPPED IT, before any stored overlay lands.
##
## ⚠ THIS IS THE ONLY MOMENT THE DEFAULTS EXIST. A rebind overwrites the map in
## place, so "reset to defaults" has nothing to return to unless it was copied first.
## Idempotent, and it copies the events (`duplicate()`) because
## `action_erase_events` frees what it holds — a snapshot of live references would be
## a snapshot of dangling ones the first time anything was rebound.
static func capture_input_defaults() -> void:
	if _defaults_captured:
		return
	_defaults_captured = true
	for action: StringName in InputMap.get_actions():
		var evs: Array[InputEvent] = []
		for ev: InputEvent in InputMap.action_get_events(action):
			evs.append(ev.duplicate())
		_defaults[action] = evs


## The project's own binding for an action, ignoring anything the player has done.
static func default_events(action: StringName) -> Array:
	capture_input_defaults()
	return _defaults.get(action, [])


## Replace the KEY/MOUSE binding of one action, keeping every other event type.
##
## ⚠ `action_erase_events` WOULD BE WRONG HERE. Godot ships joypad events on its
## built-in `ui_*` actions, and `ui_cancel` is one of the rebindable rows (it is
## Pause). Wiping the action wholesale would silently delete a pad binding this
## project never chose to add and cannot see — so only the events this screen is
## allowed to author are removed.
static func rebind(action: StringName, ev: InputEvent) -> bool:
	if not InputMap.has_action(action) or not is_rebindable_event(ev):
		return false
	var text: String = event_to_text(ev)
	if text == "":
		return false
	capture_input_defaults()
	_replace_binding(action, text_to_event(text))
	set_v(S_INPUT, String(action), text)
	return true


## Put one action back on the project's binding and forget the override.
static func reset_binding(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	capture_input_defaults()
	for ev: InputEvent in InputMap.action_get_events(action):
		if is_rebindable_event(ev):
			InputMap.action_erase_event(action, ev)
	for ev: InputEvent in default_events(action):
		if is_rebindable_event(ev):
			InputMap.action_add_event(action, ev.duplicate())
	if cfg().has_section_key(S_INPUT, String(action)):
		cfg().erase_section_key(S_INPUT, String(action))
		_dirty = true
		_dirty_at_msec = Time.get_ticks_msec()


## Every override, gone. The whole `[input]` section is erased rather than reset key
## by key so a stale action name left behind by a rename cannot come back tomorrow.
static func reset_all_bindings() -> void:
	capture_input_defaults()
	for action: StringName in _defaults.keys():
		reset_binding(action)
	if cfg().has_section(S_INPUT):
		cfg().erase_section(S_INPUT)
	_dirty = true
	_dirty_at_msec = Time.get_ticks_msec()


## Lay the stored overrides over the shipped map. Safe to call twice.
static func apply_input_overlay() -> void:
	capture_input_defaults()
	var cf: ConfigFile = cfg()
	if not cf.has_section(S_INPUT):
		return
	for key: String in cf.get_section_keys(S_INPUT):
		var action := StringName(key)
		if not InputMap.has_action(action):
			continue      # an action renamed since the file was written: drop it
		var ev: InputEvent = text_to_event(String(cf.get_value(S_INPUT, key, "")))
		if ev != null:
			_replace_binding(action, ev)


static func _replace_binding(action: StringName, ev: InputEvent) -> void:
	for old: InputEvent in InputMap.action_get_events(action):
		if is_rebindable_event(old):
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, ev)


## The cap text for an action right now — the first key/mouse binding it carries, or
## a dash. An action with no printable binding shows the dash rather than an empty
## button, because a blank cap reads as a layout bug rather than as "unbound".
static func binding_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "—"
	for ev: InputEvent in InputMap.action_get_events(action):
		var label: String = event_label(ev)
		if label != "":
			return label
	return "—"


## Which other actions answer to the same key. Used to warn rather than to refuse:
## `jump` and `move_up` legitimately share W in the shipped map, so a rule that
## forbade collisions would forbid the defaults.
static func actions_bound_to(ev: InputEvent, except: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var want: String = event_to_text(ev)
	if want == "":
		return out
	for action: StringName in InputMap.get_actions():
		if action == except:
			continue
		for other: InputEvent in InputMap.action_get_events(action):
			if event_to_text(other) == want:
				out.append(action)
				break
	return out
