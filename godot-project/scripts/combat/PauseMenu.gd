class_name PauseMenu
extends Control
## Reusable pause overlay: a dim backdrop + PAUSED + Resume / Settings / Exit.
## Settings expands a sub-panel with a master-VOLUME slider and a CONTROLS
## reference (the maker's ask: "esc needs an exit button as well and settings
## like volume and other stuff like controls"). Built in code (house style, no
## .tscn); process_mode ALWAYS so its buttons work while the tree is paused. The
## host toggles open()/close() and wires the exit action via `exit_requested`.

signal resume_requested
signal exit_requested
## The on-screen PAUSE affordance was tapped. Hosts already wire `ui_cancel` to
## `open()`; they wire this to the same call and the menu stops being keyboard-only.
signal pause_requested

## ⚠ THE ONE PLACE THE SCHEME IS WRITTEN IN PROSE, so it drifts silently the moment a
## binding moves. `1 / 2 / 3` are the three SPELL BUTTONS (`spell_1..3`) — the scheme
## the whole right thumb is built around; `G` throws whichever of them is selected and
## is what a bot pulls; `V` only moves that selection.
const CONTROLS_TEXT: String = "A / D   Move          W / Up   Jump\nSpace   Dash          LMB   Cast\n1 / 2 / 3   Spells          RMB   Parry / Block\nF   Melee          R   Blink          Q   AoE          T   Nova\nG   Cast selected spell          V   Change selection\nTab   Class          X   Element          C   Colour\nEsc / the II button   Pause"

## -- the on-screen pause button (mobile) -------------------------------------
## ⚠ WITHOUT THIS THE SETTINGS MENU IS UNREACHABLE ON A PHONE. Every host opens the
## pause menu on `ui_cancel` and nothing else, and a phone has no Esc key — so volume,
## screen shake, hit-stop, aim assist and the graphics toggle were all keyboard-only
## on the one platform this game is being built for.
##
## Top-RIGHT, deliberately: the left thumb owns the move stick and the right thumb the
## three spell buttons, both near the bottom of the screen, so the top corners are the
## only real estate a thumb is never resting on. Right rather than left because a
## right-handed grip reaches it without crossing the aim stick.
const PAUSE_BTN_SIZE: Vector2 = Vector2(44.0, 44.0)
## Margin from the screen corner. Generous enough to clear a rounded corner and a
## notch cutout, which is the failure mode you only find on hardware.
const PAUSE_BTN_MARGIN: float = 10.0
## Resting transparency. Visible enough to find, faint enough not to sit in the middle
## of the fight. UNTESTED ON A DEVICE — every number in this block is reasoning.
const PAUSE_BTN_ALPHA: float = 0.55

## The layer the button draws on. Above the game, comfortably below the pause
## overlay's own contents, which are drawn by this Control at whatever layer the host
## put it on.
const PAUSE_BTN_LAYER: int = 50

## -- the director (debug review rig) -----------------------------------------
## ⚠ TWO INDEPENDENT SHIP GATES, AND THE FIRST ONE IS THE REAL ONE.
##
##   1. THE SCRIPT IS NOT IN AN EXPORTED BUILD. It lives under `res://tools/`,
##      which `export_presets.cfg` excludes from the pack, so `ResourceLoader.
##      exists()` answers false on a phone and no row is ever built. This is the
##      gate that cannot be forgotten, because it is not a decision made at
##      runtime — the bytes are absent.
##   2. `OS.is_debug_build()` — false in a release export. Belt to the braces,
##      and the thing that keeps the director out of a *debug* APK sideloaded
##      onto someone else's phone even if the exclude list is ever edited.
##
## `tools/release_gate_dev_bridge.gd` asserts BOTH: that the preset still
## excludes `res://tools/*`, and that this file still carries the
## `OS.is_debug_build()` guard and does not `preload` the director (a preload
## would drag an excluded script into the pack and break the export outright).
##
## Reached by `load()` + duck typing rather than a typed reference, exactly like
## `VersusArena._probe_begin` reaches its probe: a hard reference to a file that
## is deliberately absent half the time is a compile error waiting for an export.
const DIRECTOR_SCRIPT: String = "res://tools/director/Director.gd"
## One director per scene, however many PauseMenus a host builds — two would
## double every hotkey (F1 open + F1 close on the same press).
const DIRECTOR_GROUP: StringName = &"director"

var _pause_layer: CanvasLayer = null
var _pause_btn: Button = null
var _quality_btn: Button = null
var _director: Node = null

var _main_col: VBoxContainer = null
var _settings_col: VBoxContainer = null
var _main_center: CenterContainer = null
var _settings_center: CenterContainer = null
var _exit_label: String = "Exit to Hub"
## Kept so injected items can be slotted ABOVE them — the exit stays the last
## thing on the main menu and Back stays the last thing in Settings, however many
## host-specific rows get added in between.
var _exit_btn: Button = null
var _back_btn: Button = null
## Settings rows are scrollable: the duel knobs pushed the column past the bottom
## of a 720p window, and a control you cannot reach is a control you do not have.
var _settings_scroll: ScrollContainer = null


## Build the overlay. `exit_label` names the exit button (e.g. "Exit to Hub" /
## "Quit"). Starts hidden — the host calls open() on Esc.
func build(exit_label: String = "Exit to Hub") -> void:
	_exit_label = exit_label
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so they don't fall through
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_build_main()
	_build_settings()
	_build_pause_button()
	_build_director()


# ------------------------------------------------------------------ director
## Is the debug review rig available in THIS build? See the DIRECTOR_SCRIPT
## block above for why there are two conditions and why the first one is the one
## that matters.
##
## ⚠ DO NOT "SIMPLIFY" THIS BY DROPPING `OS.is_debug_build()`. A debug APK is a
## real thing this project intends to sideload (docs/mobile-export.md §1.5), and
## the file-presence check alone would let the director onto that phone the day
## somebody edits the exclude list for an unrelated reason.
static func director_available() -> bool:
	if not OS.is_debug_build():
		return false
	return ResourceLoader.exists(DIRECTOR_SCRIPT)


## Build the director and give it a row on the MAIN menu (not Settings): it is
## the reason the maker opened the menu, not a preference they are adjusting.
##
## It goes on the main menu rather than behind F1 alone because F1 does not exist
## on a phone — the same reason the pause BUTTON exists at all. Two routes in,
## one of which survives having no keyboard.
func _build_director() -> void:
	if not director_available():
		return
	# ⚠ A DYING DIRECTOR MUST NOT BLOCK A NEW ONE. `queue_free()` lands at the end
	# of the frame and the node stays in its groups until then, so a host that
	# tears down one pause menu and builds another in the same frame would get NO
	# director at all — the same shape as the departed-peer puppet that used to
	# soft-lock Arena's party-wipe check.
	var tree: SceneTree = get_tree()
	if tree != null:
		for d: Node in tree.get_nodes_in_group(DIRECTOR_GROUP):
			if _is_live(d):
				return   # a live sibling PauseMenu already built one
	var script: Resource = load(DIRECTOR_SCRIPT)
	if script == null:
		return
	# The director is a CanvasLayer for the same reason the pause button is: this
	# node is `visible = false` whenever the menu is closed, and the director has
	# to be usable with the menu CLOSED and the game RUNNING. A CanvasLayer is not
	# a CanvasItem, so it does not inherit that hidden state.
	_director = (script as GDScript).new()
	add_child(_director)
	_director.add_to_group(DIRECTOR_GROUP)
	add_action("◆  DIRECTOR  (F1)", func() -> void:
		if _director != null and _director.has_method("set_open"):
			_director.call("set_open", true)
		resume_requested.emit())


## Is this node really still alive — or is it, or anything it hangs off, on its
## way out?
##
## ⚠ `queue_free()` DOES NOT MARK CHILDREN. Calling it on a PauseMenu marks the
## menu and leaves `is_queued_for_deletion()` FALSE on the director underneath
## it, while the whole subtree is nonetheless about to vanish and the director is
## still in its group. Checking only the node itself therefore sees a "live"
## director that will not exist next frame, and the next PauseMenu built in that
## window silently gets none. So the walk goes all the way up.
static func _is_live(n: Node) -> bool:
	if not is_instance_valid(n):
		return false
	var cur: Node = n
	while cur != null:
		if cur.is_queued_for_deletion():
			return false
		cur = cur.get_parent()
	return true


## The live director node, or null in a build that has none. Exposed so a host or
## a test can reach it without knowing where it was parented.
func director() -> Node:
	return _director


## The on-screen PAUSE affordance.
##
## ⚠ IT LIVES ON A `CanvasLayer`, AND THAT IS THE WHOLE TRICK RATHER THAN A STYLE
## CHOICE. This node is a Control that spends almost all of its life `visible = false`
## (that is what "the pause menu is closed" means) with `MOUSE_FILTER_STOP`, so it can
## host neither a visible child nor a clickable one: a Control child of a hidden
## Control is hidden, and making the parent visible instead would put a full-rect
## click-eater over the game. `CanvasLayer` is NOT a CanvasItem, so a parent Control's
## `visible` does not propagate into it — the button draws and takes taps while the
## menu around it is closed, and nothing else on screen is blocked.
##
## `PROCESS_MODE_ALWAYS` is inherited from this node, which is what lets it keep
## receiving input while the tree is paused.
func _build_pause_button() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = PAUSE_BTN_LAYER
	add_child(_pause_layer)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the button itself eats taps
	_pause_layer.add_child(holder)
	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.tooltip_text = "Pause"
	_pause_btn.custom_minimum_size = PAUSE_BTN_SIZE
	_pause_btn.add_theme_font_size_override("font_size", 18)
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.modulate = Color(1.0, 1.0, 1.0, PAUSE_BTN_ALPHA)
	# Styled to match the touch pad's buttons rather than left on the default theme:
	# on a phone this is the ONLY chrome outside the two thumb clusters, and a stock
	# grey rectangle in the corner reads as debug UI rather than as an affordance.
	# It also gets a real PRESS state, because a tap you cannot see land feels broken.
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		var down: bool = state == "pressed"
		sb.bg_color = Color(0.2, 0.24, 0.34, 0.55 + (0.3 if down else 0.0))
		sb.set_corner_radius_all(int(PAUSE_BTN_SIZE.x * 0.35))
		sb.border_color = Color(0.9, 0.96, 1.0, 0.85) if down else Color(0.8, 0.88, 1.0, 0.5)
		sb.set_border_width_all(3 if down else 2)
		_pause_btn.add_theme_stylebox_override(state, sb)
	# Pinned to the top-right corner by anchors, so it lands in the same place on a
	# phone, a tablet and a resized desktop window without anyone computing a position.
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.offset_left = -(PAUSE_BTN_SIZE.x + PAUSE_BTN_MARGIN)
	_pause_btn.offset_top = PAUSE_BTN_MARGIN
	_pause_btn.offset_right = -PAUSE_BTN_MARGIN
	_pause_btn.offset_bottom = PAUSE_BTN_MARGIN + PAUSE_BTN_SIZE.y
	_pause_btn.pressed.connect(_on_pause_pressed)
	holder.add_child(_pause_btn)


## Tapped. TWO ROUTES, and the fallback is now a real one rather than a stopgap.
##
## If a host has connected `pause_requested`, that wins — an explicit wire is always
## better than a guess, and a host that wants to save the run or duck the music before
## opening needs somewhere to do it.
##
## OTHERWISE THIS BUTTON PAUSES THE GAME ITSELF: `get_tree().paused = true` + `open()`,
## which is verbatim what `Arena._set_paused(true)` and `VersusArena._set_paused(true)`
## do. RESUMING still goes out through `resume_requested`, so the host stays the owner
## of un-pausing and nothing about the Esc path moves.
##
## ⚠ IT USED TO SYNTHESIZE `ui_cancel` through `Input.parse_input_event`, and that was
## a stopgap with three real problems, not merely an inelegant one:
##   1. Input is PROCESS-GLOBAL. A synthesized action reaches every listener in the
##      tree — the class picker, the loadout screen, the conversation bar all treat
##      `ui_cancel` as "close me". Tapping PAUSE fired all of them.
##   2. It needed `_synth_cancel`, a one-frame flag racing an asynchronously dispatched
##      event, to stop this node reading its OWN synthetic press as "resume" and
##      closing the menu on the frame it opened. A timing flag guarding a timing bug.
##   3. It only worked at all because two hosts happened to listen for that exact
##      action. A third host, or a host that later moved to a dedicated `pause`
##      action, would have had a pause button that silently did nothing.
## Calling the pause directly has none of those failure modes and is the same two
## lines the hosts run.
func _on_pause_pressed() -> void:
	if pause_requested.get_connections().size() > 0:
		pause_requested.emit()
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.paused = true
	open()


## Show or hide the on-screen pause button. Hosts that have no business showing one —
## a menu scene, a cutscene, a run that has already ended — turn it off; nothing else
## needs to care, because it defaults to on.
func set_pause_button_visible(v: bool) -> void:
	if _pause_layer != null:
		_pause_layer.visible = v


func open() -> void:
	visible = true
	_main_center.visible = true
	_settings_center.visible = false
	# Refreshed on every open rather than only when tapped: `graphics_quality` is also
	# reachable from the inspector and from Remote, so a label written once at build
	# time would start lying the moment anyone touched it there.
	if _quality_btn != null:
		_quality_btn.text = _quality_label()
	if _pause_layer != null:
		_pause_layer.visible = false  # the menu has its own Resume row


func close() -> void:
	visible = false
	if _pause_layer != null:
		_pause_layer.visible = true


func _build_main() -> void:
	_main_center = CenterContainer.new()
	_main_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_main_center)
	_main_col = VBoxContainer.new()
	_main_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_col.add_theme_constant_override("separation", 14)
	_main_center.add_child(_main_col)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_main_col.add_child(title)
	_main_col.add_child(_menu_button("Resume  (Esc)", func() -> void: resume_requested.emit()))
	_main_col.add_child(_menu_button("Settings", _open_settings))
	_exit_btn = _menu_button(_exit_label, func() -> void: exit_requested.emit())
	_main_col.add_child(_exit_btn)


# ------------------------------------------------------- host-injected items
## Add a button to the MAIN pause menu (e.g. "Fight the Boss"). Slotted above the
## exit button so leaving is always the last row no matter what a host injects.
func add_action(text: String, cb: Callable) -> Button:
	var b: Button = _menu_button(text, cb)
	_main_col.add_child(b)
	if _exit_btn != null:
		_main_col.move_child(_exit_btn, _main_col.get_child_count() - 1)
	return b


## Add a button to the SETTINGS sub-panel — this is where a host puts its own
## knobs (the duel's difficulty / bot class / learning toggles). Slotted above
## "Back", which stays the last row.
func add_setting_button(text: String, cb: Callable) -> Button:
	var b: Button = _menu_button(text, cb)
	b.custom_minimum_size = Vector2(240, 30)
	b.add_theme_font_size_override("font_size", 14)
	_settings_col.add_child(b)
	if _back_btn != null:
		_settings_col.move_child(_back_btn, _settings_col.get_child_count() - 1)
	return b


## A section heading in the SETTINGS sub-panel, so an injected block of knobs
## reads as its own group rather than as more audio sliders.
func add_setting_section(title: String) -> Label:
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.62))
	_settings_col.add_child(l)
	if _back_btn != null:
		_settings_col.move_child(_back_btn, _settings_col.get_child_count() - 1)
	return l


func _build_settings() -> void:
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	add_child(_settings_center)
	# SCROLLED. Hosts inject their own rows here (the duel's five knobs), and the
	# column already ran to the bottom of a 720p window with just the built-ins —
	# an unreachable control is not a control.
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.custom_minimum_size = Vector2(320, 520)
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_center.add_child(_settings_scroll)
	_settings_col = VBoxContainer.new()
	_settings_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_col.add_theme_constant_override("separation", 12)
	_settings_scroll.add_child(_settings_col)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	_settings_col.add_child(title)

	# Master volume.
	var vol_label := Label.new()
	vol_label.text = "Master Volume"
	vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(240, 20)
	slider.value = _current_master_linear()
	slider.value_changed.connect(_on_volume_changed)
	_settings_col.add_child(slider)

	# Music volume — drives the dedicated Music bus (independent of Master/SFX).
	var music_label := Label.new()
	music_label.text = "Music Volume"
	music_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(music_label)
	var music_slider := HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01
	music_slider.custom_minimum_size = Vector2(240, 20)
	music_slider.value = _current_music_linear()
	music_slider.value_changed.connect(_on_music_volume_changed)
	_settings_col.add_child(music_slider)
	# The "cool option": cycle the current mood's playlist (same as the M key).
	_settings_col.add_child(_menu_button("Next Track  (M)", func() -> void:
		var m: Node = get_node_or_null("/root/Music")
		if m != null and m.has_method("cycle_track"):
			m.call("cycle_track")))

	# Camera zoom (maker: "we should be able to alter the zoom in the setting").
	# Slider LEFT = wider view, RIGHT = tighter. Applies live + persists.
	var zoom_label := Label.new()
	zoom_label.text = "Camera Zoom"
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(zoom_label)
	var zoom_slider := HSlider.new()
	zoom_slider.min_value = 1.0
	zoom_slider.max_value = 2.6
	zoom_slider.step = 0.05
	zoom_slider.custom_minimum_size = Vector2(240, 20)
	zoom_slider.value = _current_zoom()
	zoom_slider.value_changed.connect(_on_zoom_changed)
	_settings_col.add_child(zoom_slider)

	# Screen shake intensity (0 = off) — motion-sensitivity accessibility; drives
	# Tuning.cfg.shake_scale, which CombatCamera already reads live.
	var shake_label := Label.new()
	shake_label.text = "Screen Shake"
	shake_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(shake_label)
	var shake_slider := HSlider.new()
	shake_slider.min_value = 0.0
	shake_slider.max_value = 1.0
	shake_slider.step = 0.05
	shake_slider.custom_minimum_size = Vector2(240, 20)
	shake_slider.value = _current_shake()
	shake_slider.value_changed.connect(_on_shake_changed)
	_settings_col.add_child(shake_slider)

	# Hit-stop toggle — some players dislike the micro-freeze on impacts.
	var hs_btn := CheckButton.new()
	hs_btn.text = "Hit-Stop"
	hs_btn.button_pressed = _current_hit_stop()
	hs_btn.toggled.connect(_on_hit_stop_toggled)
	_settings_col.add_child(hs_btn)

	# AIM ASSIST. Ships at 0 and 0 is inert — see SpellTargets.assist_aim, which
	# returns the aim it was given before it scans anything at that strength. The
	# slider exists so the spectrum the mobile spec asks for HAS a home without
	# reversing the maker's locked no-auto-aim decision, and so the question can be
	# answered by hand instead of by argument. It bends an aim you already chose by at
	# most SpellTargets.ASSIST_MAX_DEGREES; it never picks a target.
	var aim_label := Label.new()
	aim_label.text = "Aim Assist  (0 = off)"
	aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(aim_label)
	var aim_slider := HSlider.new()
	aim_slider.min_value = 0.0
	aim_slider.max_value = 1.0
	aim_slider.step = 0.05
	aim_slider.custom_minimum_size = Vector2(240, 20)
	aim_slider.value = _current_aim_assist()
	aim_slider.value_changed.connect(_on_aim_assist_changed)
	_settings_col.add_child(aim_slider)

	# GRAPHICS QUALITY. Three states rather than a checkbox because AUTO (the shipping
	# default: LOW on a mobile export, HIGH everywhere else) is a real answer and not
	# the absence of one. The reason it belongs in the player-facing menu rather than
	# staying an inspector field: forcing LOW on a desktop renders the PHONE'S PICTURE
	# without a phone, and no APK has ever been built — so this is currently the only
	# way to look at what the mobile build will look like.
	_quality_btn = _menu_button(_quality_label(), _on_quality_pressed)
	_quality_btn.custom_minimum_size = Vector2(240, 30)
	_quality_btn.add_theme_font_size_override("font_size", 14)
	_settings_col.add_child(_quality_btn)

	# PERFORMANCE OVERLAY. Lives next to the quality toggle because the two are one
	# workflow: flip to LOW, watch the frame time. Silently absent when the Perf
	# autoload is not registered (a headless run, or a build that excluded it).
	if _perf_overlay() != null:
		_settings_col.add_child(_menu_button("Performance Overlay", func() -> void:
			var p: Node = _perf_overlay()
			if p != null and p.has_method("toggle"):
				p.call("toggle")))

	# Controls reference.
	var ctrl_title := Label.new()
	ctrl_title.text = "Controls"
	ctrl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl_title.add_theme_font_size_override("font_size", 18)
	_settings_col.add_child(ctrl_title)
	var ctrl := Label.new()
	ctrl.text = CONTROLS_TEXT
	ctrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl.add_theme_font_size_override("font_size", 13)
	ctrl.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95))
	_settings_col.add_child(ctrl)

	_back_btn = _menu_button("Back", _close_settings)
	_settings_col.add_child(_back_btn)


func _open_settings() -> void:
	_main_center.visible = false
	_settings_center.visible = true


func _close_settings() -> void:
	_settings_center.visible = false
	_main_center.visible = true


## Standard sized menu button wired to a Callable.
func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 38)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b


# --------------------------------------------------------------- resume on Esc
## PauseMenu is PROCESS_MODE_ALWAYS, so it keeps getting input while the tree is
## paused — that's how Esc closes the menu even though the (pausable) host can't
## process input while paused. Only acts while the menu is open.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ audio (master bus)
func _master_bus() -> int:
	return AudioServer.get_bus_index("Master")


func _music_bus() -> int:
	return AudioServer.get_bus_index("Music")


func _current_music_linear() -> float:
	var idx: int = _music_bus()
	if idx < 0:
		return 1.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


func _on_music_volume_changed(v: float) -> void:
	var idx: int = _music_bus()
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0)


func _current_master_linear() -> float:
	var idx: int = _master_bus()
	if idx < 0:
		return 1.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


func _on_volume_changed(v: float) -> void:
	var idx: int = _master_bus()
	if idx < 0:
		return
	# A linear 0 slider = silence; otherwise map to dB.
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0)


# ------------------------------------------------------------------ camera zoom
## Current resting zoom from GameState (falls back to a sensible middle).
func _current_zoom() -> float:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var v: Variant = gs.get("camera_zoom")
		if v != null:
			return float(v)
	return 1.6


## Live-apply the zoom to every combat camera (they persist it to GameState).
func _on_zoom_changed(v: float) -> void:
	for cam: Node in get_tree().get_nodes_in_group("combat_camera"):
		if cam.has_method("set_base_zoom"):
			cam.call("set_base_zoom", v)


## The Tuning autoload's live config resource (holds shake_scale, hit_stop_enabled).
func _tuning_cfg() -> Object:
	var t: Node = get_node_or_null("/root/Tuning")
	if t != null:
		return t.get("cfg")
	return null


func _current_shake() -> float:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		var v: Variant = cfg.get("shake_scale")
		if v != null:
			return float(v)
	return 1.0


## Screenshake slider → Tuning.cfg.shake_scale (CombatCamera reads it live via
## trauma * trauma * shake_scale). Persists across scenes (Tuning is an autoload).
func _on_shake_changed(v: float) -> void:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		cfg.set("shake_scale", v)


# ------------------------------------------------------------------ aim assist
func _current_aim_assist() -> float:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		var v: Variant = cfg.get("aim_assist")
		if v != null:
			return clampf(float(v), 0.0, 1.0)
	return 0.0


## Slider → Tuning.cfg.aim_assist, which `SpellTargets.assist_strength` reads live on
## the frame the aim is resolved, so dragging it changes the feel without a restart.
func _on_aim_assist_changed(v: float) -> void:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		cfg.set("aim_assist", v)


# ------------------------------------------------------------ graphics quality
## AUTO -> HIGH -> LOW -> AUTO. A cycling button rather than three radio rows: the
## panel is already scrolled to reach its bottom on a 720p window, and a setting with
## three states and one label costs one row instead of four.
func _on_quality_pressed() -> void:
	var cfg: Object = _tuning_cfg()
	if cfg == null:
		return
	var v: Variant = cfg.get("graphics_quality")
	var cur: int = TuningConfig.Quality.AUTO if v == null else int(v)
	cfg.set("graphics_quality", (cur + 1) % 3)
	if _quality_btn != null:
		_quality_btn.text = _quality_label()


## The label says what the setting IS *and*, for AUTO, what it currently RESOLVES to —
## because "Auto" alone leaves the one question the maker actually has ("am I looking
## at the phone's picture right now?") unanswered on the screen that is supposed to
## answer it.
func _quality_label() -> String:
	var cfg: Object = _tuning_cfg()
	var v: Variant = cfg.get("graphics_quality") if cfg != null else null
	var cur: int = TuningConfig.Quality.AUTO if v == null else int(v)
	match cur:
		TuningConfig.Quality.HIGH:
			return "Graphics: HIGH"
		TuningConfig.Quality.LOW:
			return "Graphics: LOW  (phone preview)"
	return "Graphics: AUTO  (%s)" % ("low" if TuningConfig.quality_is_low() else "high")


func _perf_overlay() -> Node:
	return get_node_or_null(^"/root/Perf")


func _current_hit_stop() -> bool:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		var v: Variant = cfg.get("hit_stop_enabled")
		if v != null:
			return bool(v)
	return true


func _on_hit_stop_toggled(on: bool) -> void:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		cfg.set("hit_stop_enabled", on)
