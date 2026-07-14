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

const CONTROLS_TEXT: String = "A / D   Move          W / Up   Jump\nSpace   Dash          LMB   Cast\nF   Melee          RMB   Parry / Block\nR   Blink          Q   AoE          T   Nova\nG   Ultimate          V   Cycle spell\nTab   Class          X   Element          C   Colour\nEsc   Pause"

var _main_col: VBoxContainer = null
var _settings_col: VBoxContainer = null
var _main_center: CenterContainer = null
var _settings_center: CenterContainer = null
var _exit_label: String = "Exit to Hub"


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


func open() -> void:
	visible = true
	_main_center.visible = true
	_settings_center.visible = false


func close() -> void:
	visible = false


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
	_main_col.add_child(_menu_button(_exit_label, func() -> void: exit_requested.emit()))


func _build_settings() -> void:
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	add_child(_settings_center)
	_settings_col = VBoxContainer.new()
	_settings_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_col.add_theme_constant_override("separation", 12)
	_settings_center.add_child(_settings_col)

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

	_settings_col.add_child(_menu_button("Back", _close_settings))


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


# ------------------------------------------------------------------ audio (master bus)
func _master_bus() -> int:
	return AudioServer.get_bus_index("Master")


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
