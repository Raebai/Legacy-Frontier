extends CanvasLayer
## Hub Class-Select panel (autoload "ClassSelect"). A modal 8-card grid opened by
## the Class Altar in the hub; tap a card to pick your class (writes
## GameState.selected_class), which retints the hub player + updates the class HUD
## label, then closes. Built in code (house style, no .tscn) like PauseMenu.
##
## Scene-safe: only the hub Altar ever open()s it; the selection feedback no-ops
## when the player / label groups are absent (i.e. in the arena). Referenced
## elsewhere via /root/ClassSelect so headless tests never need the autoload.

const CARD_SIZE: Vector2 = Vector2(232, 92)
const HIGHLIGHT: Color = Color(0.55, 0.9, 1.0)

var _cards: Array[Button] = []
var _panel: PanelContainer = null


func _ready() -> void:
	layer = 90
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # eat taps behind the panel
	dim.gui_input.connect(_on_dim_input)          # tap-outside dismisses
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)
	var title := Label.new()
	title.text = "CHOOSE YOUR CLASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	vbox.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	_build_cards(grid)
	var hint := Label.new()
	hint.text = "tap a class  ·  Esc / tap-away to cancel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vbox.add_child(hint)


func _build_cards(grid: GridContainer) -> void:
	for i: int in ClassInfo.count():
		var info: Dictionary = ClassInfo.CLASSES[i]
		var b := Button.new()
		b.custom_minimum_size = CARD_SIZE
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 13)
		b.text = "%s\n[%s]\n%s" % [info["name"], info["fantasy"], info["kit"]]
		b.add_theme_color_override("font_color", (info["color"] as Color).lightened(0.25))
		b.pressed.connect(_on_card_pressed.bind(i))
		grid.add_child(b)
		_cards.append(b)


func is_open() -> bool:
	return visible


func open() -> void:
	_refresh_highlight()
	visible = true
	var idx: int = _selected_class()
	if idx >= 0 and idx < _cards.size():
		_cards[idx].grab_focus()


func close() -> void:
	visible = false


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _on_card_pressed(index: int) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("selected_class", index)
	_apply_feedback(index)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_8:
		_on_card_pressed(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()


func _selected_class() -> int:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var v: Variant = gs.get("selected_class")
		if v != null:
			return int(v)
	return 0


## Brighten the currently-selected card so the choice reads.
func _refresh_highlight() -> void:
	var sel: int = _selected_class()
	for i: int in _cards.size():
		_cards[i].modulate = HIGHLIGHT if i == sel else Color.WHITE


## Retint the hub player + update the class HUD label to the chosen class. No-ops
## in scenes without those nodes (the arena), so the autoload is scene-safe.
func _apply_feedback(index: int) -> void:
	var col: Color = ClassInfo.color_for(index)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_class_tint"):
		player.call("set_class_tint", col)  # retint the stick figure
	for label: Node in get_tree().get_nodes_in_group("class_hud_label"):
		if label is Label:
			(label as Label).text = "Class: %s" % ClassInfo.name_for(index)
	_refresh_highlight()
