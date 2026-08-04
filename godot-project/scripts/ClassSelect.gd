extends CanvasLayer
## Hub Class-Select panel (autoload "ClassSelect"). A modal 8-card grid opened by
## the Class Altar in the hub; tap a card to pick your class (writes
## GameState.selected_class), which retints the hub player + updates the class HUD
## label, then closes. Built in code (house style, no .tscn) like PauseMenu.
##
## Scene-safe: only the hub Altar ever open()s it; the selection feedback no-ops
## when the player / label groups are absent (i.e. in the arena). Referenced
## elsewhere via /root/ClassSelect so headless tests never need the autoload.

## ══ SIMPLER, BECAUSE IT WAS ASKED FOR ═══════════════════════════════════════
## Maker: "class select must be far simpler", under the standing rule "this game has
## too much text and too many random UI pieces — every screen should be cut, not
## added to."
##
## What each card used to carry: the name, a bracketed FANTASY line, and a KIT
## sentence — three lines, nine times, in a two-column grid 232 px wide. That is
## roughly sixty words on a screen whose entire question is "which one". The kit line
## in particular was answering a question the ARCHIVIST and the Outfitter both answer
## properly, with the actual spells, at the two pads either side of this one.
##
## What it carries now: the NAME, in the class's own colour, on a card you can hit
## with a thumb. Three columns so nine cards are a square rather than a column you
## scroll. The colour is not decoration — it is the same `ClassInfo.color_for` the
## hero is tinted with, so the card and the body you walk away in match.
const CARD_SIZE: Vector2 = Vector2(124, 58)
const GRID_COLUMNS: int = 3
## Appended to a locked card. Says WHERE the class is, not merely that it is gone —
## the difference between a goal and a smaller game. Two words instead of five.
const LOCK_SUFFIX: String = "\nguarded"
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
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	vbox.add_child(title)
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	_build_cards(grid)
	# ⚠ THE HINT LINE IS GONE. It read "tap a class · Esc / tap-away to cancel" — an
	# instruction for tapping a grid of nine buttons, which is the one interaction on
	# earth nobody needs told. Both routes it described still work.


func _build_cards(grid: GridContainer) -> void:
	for i: int in ClassInfo.count():
		var info: Dictionary = ClassInfo.CLASSES[i]
		var b := Button.new()
		b.custom_minimum_size = CARD_SIZE
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 15)
		# ⚠ THE NAME AND NOTHING ELSE. `info["fantasy"]` and `info["kit"]` are still
		# authored and still read — `ClassInfo` feeds the class cards elsewhere — they
		# are simply not what this screen is for. What the class actually casts is two
		# pads away, on the Archivist and the Outfitter, in the form of the spells.
		b.text = String(info["name"])
		b.add_theme_color_override("font_color", (info["color"] as Color).lightened(0.25))
		b.pressed.connect(_on_card_pressed.bind(i))
		grid.add_child(b)
		_cards.append(b)
	_refresh_locks()


## ⚠ LOCKED CLASSES ARE SHOWN, NOT HIDDEN. Three of the nine are withheld until a
## guardian is felled (`Progression.LOCKED_CLASSES`), and the difference between a
## card that says "a guardian holds this" and a card that is simply absent is the
## difference between a goal and a smaller game. A player has to be able to WANT the
## thing before they can be rewarded with it.
##
## Re-read on every `open()` rather than only at build time, because a class can be
## earned between two visits to the altar — and a stale card would go on refusing a
## class the save already says is unlocked.
func _refresh_locks() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var owned: Array = [] if gs == null else (gs.get("unlocked_classes") as Array)
	for i: int in _cards.size():
		var unlocked: bool = Progression.is_class_unlocked(i, owned)
		var b: Button = _cards[i]
		b.disabled = not unlocked
		b.modulate.a = 1.0 if unlocked else 0.45
		# Idempotent: `open()` re-runs this, and appending unconditionally would grow
		# the label a little more every single time the altar is used.
		var has_suffix: bool = b.text.ends_with(LOCK_SUFFIX)
		if not unlocked and not has_suffix:
			b.text += LOCK_SUFFIX
		elif unlocked and has_suffix:
			b.text = b.text.substr(0, b.text.length() - LOCK_SUFFIX.length())


func is_open() -> bool:
	return visible


func open() -> void:
	_refresh_locks()
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
	# ⚠ RE-CHECKED, not trusted from `disabled`. A card built before a save loaded, or
	# a keyboard/gamepad focus walk that lands on a disabled button, would otherwise
	# hand out a class the climber has not earned — and `selected_class` persists, so
	# it would stick.
	if gs != null and not Progression.is_class_unlocked(index, gs.get("unlocked_classes") as Array):
		# ...UNLESS A GUARDIAN BANKED A PICK. This is where the floor-5 reward is
		# actually spent: pressing a locked card with a pick in hand CLAIMS that class.
		# The altar is the right place for it — the choosing is the part you remember,
		# and it happens somewhere you chose to walk to rather than in a pop-up over a
		# corpse.
		if not (gs.has_method("spend_class_choice") and bool(gs.call("spend_class_choice", index))):
			return
		_refresh_locks()
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
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_1 \
			and event.keycode < KEY_1 + _cards.size():
		# ⚠ WAS `<= KEY_8`, WITH NINE CLASSES. The ninth was unreachable by key for as
		# long as there have been nine — a hard-coded bound outliving the roster it was
		# written for. Derived now.
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


## Re-dress the hub body + update the class HUD label. No-ops in scenes without
## those nodes (the arena), so the autoload is scene-safe.
##
## ⚠ IT RE-CONFIGURES THE BODY NOW, NOT JUST ITS COLOUR. The town used to be driven by
## `Player`, which has no kit — a tint was the whole of "you are a Cryomancer now". The
## town body is a `Hero` since casting moved into the lobby, so a class change that
## only recoloured it would leave you standing there in ice-blue throwing the
## Arcanist's spells. `configure_class` is the one call that rebuilds the hand.
func _apply_feedback(index: int) -> void:
	var col: Color = ClassInfo.color_for(index)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		if player.has_method("configure_class"):
			player.call("configure_class", index)
		if player.has_method("set_class_tint"):
			player.call("set_class_tint", col)  # retint the stick figure
	for label: Node in get_tree().get_nodes_in_group("class_hud_label"):
		if label is Label:
			# Just the name — `World._reflect_selected_class` writes the same string, and
			# two writers disagreeing about a "Class: " prefix is how a label starts
			# flickering between two forms depending on which one ran last.
			(label as Label).text = ClassInfo.name_for(index)
	_refresh_highlight()
