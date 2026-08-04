class_name SpellTreeScreen
extends Control
## THE ARCHIVIST'S SCREEN — the spell tree, at the lectern.
##
## Spec §7 gives the lectern's townsperson a job: "opens the SPELL TREE; explains
## what a spell actually does". This is that screen, and it follows the town's one
## structural rule — **the station IS the screen**. There is no menu step: you walk
## up to the Archivist, press E, and you are in the tree.
##
## ⚠ IT SPENDS POINTS AND NOTHING ELSE. Which three roles you CARRY is the
## Outfitter's job and stays there. This screen only decides which spells are
## available to be carried at all, which is exactly the split the design asks for:
## the tree grows your OPTIONS, the lectern picks your HAND.
##
## ⚠ EVERY RULE IS IN `SpellTree`, NOT HERE. This file lays out buttons and calls
## `can_buy`. That separation is what let the whole economy — including the five
## mis-pointed links in the design doc — be tested before a single pixel existed.

signal closed

const PANEL_W: float = 380.0
## Every tappable target clears this, matching the Outfitter, the Lobby and the town.
const MIN_TAP: float = 30.0

const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)
const AFFORD: Color = Color(0.66, 0.92, 0.72)     # you can buy this
const TOO_DEAR: Color = Color(0.80, 0.55, 0.50)   # you cannot, yet
const OWNED: Color = Color(0.70, 0.78, 0.95)

var _class_id: int = 0
var _col: VBoxContainer = null
var _title: Label = null
var _points: Label = null
var _rows: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	refresh()


func set_class(class_id: int) -> void:
	_class_id = clampi(class_id, 0, SpellTree.TREES.size() - 1)
	refresh()


func _build() -> void:
	# Nearly opaque, for the same reason the Outfitter is: the town behind this is a
	# drawn skyline plus labels, and at 0.78 they read straight through the spell
	# names, which on a phone is a legibility bug rather than a mood.
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	_col = col

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", CHALK)
	col.add_child(_title)

	_points = Label.new()
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points.add_theme_font_size_override("font_size", 10)
	_points.add_theme_color_override("font_color", GRAPHITE)
	col.add_child(_points)

	# ⚠ SCROLLED. Nine rows plus headers overflows a phone in portrait, and a panel
	# that simply grows taller than the screen puts the CLOSE button off the bottom
	# edge — i.e. a screen with no exit on the target platform.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W, 260.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.custom_minimum_size = Vector2(PANEL_W, 0)
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)

	col.add_child(_button("Close", close, 13))


func _button(text: String, cb: Callable, font_size: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(PANEL_W, MIN_TAP)
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE   # a stray focus ring on a phone reads as a bug
	b.clip_text = true
	b.pressed.connect(cb)
	return b


## Full rebuild rather than a diff. Ten rows is nothing, and a diff of a tree whose
## affordability changes on every purchase is more code than it saves.
func refresh() -> void:
	if _rows == null:
		return
	for c: Node in _rows.get_children():
		c.queue_free()

	var gs: Node = get_node_or_null(^"/root/GameState")
	var level: int = 1 if gs == null else int(gs.call("level"))
	var owned: Array = [] if gs == null else (gs.get("unlocked_nodes") as Array)
	var avail: int = SpellTree.points_available(level, owned)

	_title.text = "%s — the Archivist" % ClassInfo.name_for(_class_id)
	_points.text = "level %d   ·   %d skill point%s to spend   ·   %d of %d spent" % [
		level, avail, "" if avail == 1 else "s",
		SpellTree.points_spent(owned), SpellTree.total_cost(_class_id),
	]

	for role: String in SpellTree.ROLES:
		var head := Label.new()
		head.text = role.to_upper()
		head.add_theme_font_size_override("font_size", 9)
		head.add_theme_color_override("font_color", GRAPHITE)
		_rows.add_child(head)
		for linked: bool in [false, true]:
			var node: String = SpellTree.node_id(_class_id, role, linked)
			if SpellTree.spell_of(node) == "":
				continue        # the ult has no link — draw nothing rather than a stub
			_rows.add_child(_node_row(node, linked, level, owned))


## One node. The row's TEXT carries its whole state, because a phone has no hover
## and no tooltip — if the button does not say why it is unpressable, nothing does.
func _node_row(node: String, linked: bool, level: int, owned: Array) -> Button:
	var spell_id: String = SpellTree.spell_of(node)
	var def: SpellDef = SpellLibrary.by_id(spell_id)
	var name: String = spell_id if def == null else String(def.display_name)
	var cost: int = SpellTree.cost_of(node)
	var have: bool = SpellTree.is_unlocked(node, owned)
	var free: bool = SpellTree.is_free(node)
	var buyable: bool = SpellTree.can_buy(node, _class_id, level, owned)

	var label: String = "%s  %s" % ["«" + name + "»" if linked else name, ""]
	var col: Color = CHALK
	if free:
		label = "%s   — yours" % name
		col = OWNED
	elif have:
		label = "%s   — learned" % ("«" + name + "»" if linked else name)
		col = OWNED
	elif buyable:
		label = "%s   — %d pt%s" % ["«" + name + "»" if linked else name, cost, "" if cost == 1 else "s"]
		col = AFFORD
	else:
		label = "%s   — %d pt%s (need %d more)" % [
			"«" + name + "»" if linked else name, cost, "" if cost == 1 else "s",
			cost - SpellTree.points_available(level, owned),
		]
		col = TOO_DEAR

	var b: Button = _button(label, _buy.bind(node), 12)
	b.add_theme_color_override("font_color", col)
	b.disabled = not buyable
	# A disabled Button in Godot dims to near-invisible against this backdrop, so the
	# state is carried by the COLOUR above and the dimming is turned back down.
	b.modulate.a = 1.0 if buyable or have else 0.78
	return b


func _buy(node: String) -> void:
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs == null:
		return
	var level: int = int(gs.call("level"))
	var owned: Array = gs.get("unlocked_nodes") as Array
	# ⚠ RE-CHECKED HERE, not trusted from the button's disabled state. A Button that
	# was affordable when the row was drawn can be stale by the time it is pressed —
	# two rapid taps on a 1-point balance would otherwise buy two nodes.
	if not SpellTree.can_buy(node, _class_id, level, owned):
		_sfx("ground_out", -4.0)
		return
	owned.append(node)
	gs.set("unlocked_nodes", owned)
	if gs.has_method("save_progress"):
		gs.call("save_progress")
	_sfx("ding")
	refresh()


func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _sfx(key: String, db: float = 0.0) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s != null and s.has_method("play"):
		s.call("play", key, db)
