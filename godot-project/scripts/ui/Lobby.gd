extends Control
## Co-op lobby + title screen. Play Solo (the classic singleplayer flow, untouched)
## / Host Co-op / Join by IP, a class picker, a live peer list, and Start Run
## (host). Built in code (house style). Set as run/main_scene; "Play Solo" loads
## the hub exactly as before so singleplayer is one click and unchanged.

var _net: Node = null
var _selected_class: int = 0
var _status: Label = null
var _peers_label: Label = null
var _class_btn: Button = null
var _ip_edit: LineEdit = null
var _start_btn: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_net = get_node_or_null("/root/Net")
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.04, 0.07, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	var title := Label.new()
	title.text = "LEGACY FRONTIER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	col.add_child(title)
	var sub := Label.new()
	sub.text = "climb the tower — solo or co-op"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	col.add_child(sub)

	col.add_child(_spacer(10))
	_class_btn = _button("Class: %d" % _selected_class, _cycle_class)
	col.add_child(_class_btn)

	col.add_child(_button("Play Solo", _play_solo))
	col.add_child(_button("Host Co-op", _host))

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(160, 34)
	join_row.add_child(_ip_edit)
	join_row.add_child(_button("Join", _join))
	col.add_child(join_row)

	_start_btn = _button("Start Run", _start_run)
	_start_btn.visible = false
	col.add_child(_start_btn)

	col.add_child(_spacer(8))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	col.add_child(_status)
	_peers_label = Label.new()
	_peers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_peers_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	col.add_child(_peers_label)

	if _net != null:
		_net.lobby_changed.connect(_refresh)
		_net.server_started.connect(_refresh)
		_net.join_ok.connect(func() -> void: _status.text = "Connected — waiting for host to Start Run")
		_net.join_failed.connect(func() -> void: _status.text = "Join failed — check the IP + that a host is up")
	_refresh()


func _cycle_class() -> void:
	# Derived from the real roster, NEVER a hardcoded count. A literal `% 8` made the
	# 9th class (the Swordsaint) unselectable in co-op the moment it was added — and
	# it failed SILENTLY: the button simply never reached it, so the class looked
	# missing rather than unreachable. Any future class is now selectable for free.
	_selected_class = (_selected_class + 1) % maxi(ClassInfo.count(), 1)
	_class_btn.text = "Class: %d" % _selected_class


func _play_solo() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _host() -> void:
	if _net == null:
		return
	var err: int = _net.host(_selected_class)
	if err == OK:
		_status.text = "Hosting on port %d — friends Join your IP, then Start Run" % _net.DEFAULT_PORT
	else:
		_status.text = "Host failed (err %d) — port in use?" % err


func _join() -> void:
	if _net == null:
		return
	var err: int = _net.join(_ip_edit.text.strip_edges(), _selected_class)
	_status.text = ("Connecting to %s..." % _ip_edit.text) if err == OK else "Join error %d" % err


func _start_run() -> void:
	if _net != null and _net.has_method("start_coop_run"):
		_net.start_coop_run()   # Net broadcasts the scene change + run state to all peers


func _refresh(_a = null) -> void:
	if _net == null:
		return
	var hosting: bool = _net.is_host()
	_start_btn.visible = hosting
	if _net.is_active():
		var ids: Array = _net.peers()
		_peers_label.text = "Players: %d  %s" % [ids.size(), str(ids)]
	else:
		_peers_label.text = ""


# --------------------------------------------------------------------- helpers
func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 38)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
