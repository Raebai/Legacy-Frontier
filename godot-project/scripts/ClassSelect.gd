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

## ══ PLAYER TWO PICKS THEIR OWN CLASS, WITH A PAD AND NOTHING ELSE ═══════════════
## The standing known gap in same-screen co-op: a joining pad inherited player one's
## class and the only way out was `switch_class` (BACK), which CYCLES — nine presses
## to reach the ninth class, rebuilding the body on each, with nothing naming what you
## were about to become. This screen already IS the class pick; it simply could not be
## reached or driven without a mouse and a keyboard.
##
## ⚠ THREE THINGS ARE DIFFERENT IN PAD MODE, AND EACH IS A BUG IF IT IS NOT.
##   1. IT WRITES `GameState.set_local_class(device, i)`, NEVER `selected_class`.
##      That global is player ONE's class and is written by six other paths; parking
##      player two's pick there is the leak `slice_test_local_coop` exists to catch.
##   2. `_apply_feedback` IS NOT CALLED. It re-configures the whole "player" group and
##      retints the hub body — i.e. it would turn player one into player two's class.
##      The caller (`LocalCoop._on_class_picked`) re-configures exactly one body.
##   3. THE FULL-SCREEN DIMMER IS OFF. Player one is still fighting: dimming their
##      half of the screen because their friend opened a menu is not a modal, it is a
##      penalty. The panel is a panel; the fight keeps running behind it, unpaused,
##      and only the chooser's own pad is taken out of the hero's hands
##      (`PadController.suspended`).
##
## Solo is byte-identical: `_physics_process` is OFF unless a pad opened this, and every hub
## path below is untouched.
##
## Navigation is the LEFT STICK + A/B, which are the buttons a joining pad already
## used to get here. Deliberately NOT the d-pad: that is four spell slots.
const PAD_REPEAT_FIRST: float = 0.34    ## hold delay before the cursor auto-repeats
const PAD_REPEAT_RATE: float = 0.13     ## and how fast it walks after that
## What the cursor sits on. Brighter than `HIGHLIGHT` (which marks the CURRENT class)
## so "where I am" and "what I am" never read as the same thing.
const PAD_CURSOR: Color = Color(1.0, 0.95, 0.6)

var _cards: Array[Button] = []
var _panel: PanelContainer = null
var _dim: ColorRect = null

## --- pad mode state. `_pad_device < 0` means every line of it is dead. ---
var _pad_device: int = -1
var _pad: PadController = null
var _pad_pick: Callable = Callable()
var _cursor: int = 0
var _repeat_left: float = 0.0
var _held_dir: Vector2i = Vector2i.ZERO
var _title: Label = null
## ⚠ THE PHYSICS FRAME THIS OPENED ON, AND IT IS NOT BOOKKEEPING — IT IS THE FIX FOR A
## SCREEN THAT OPENED AND SHUT IN THE SAME BREATH.
##
## BACK opens the chooser and BACK also backs out of it, and `PadController` holds a
## press EDGE for the whole physics frame it lands on. So `LocalCoop` saw the edge and
## opened this, and then this file's own tick — running later in that same frame,
## against that same live edge — read it as "back out" and closed again. Measured in the
## real arena: `BACK -> chooser open = false`, with no error anywhere, because both
## halves did exactly what they were told.
##
## An edge that opened a screen must not also act INSIDE it. Nothing is read until the
## frame turns over.
var _opened_frame: int = -1


func _ready() -> void:
	layer = 90
	visible = false
	set_physics_process(false)   # pad mode is the only thing that needs a tick
	var dim := ColorRect.new()
	_dim = dim
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
	_title = title
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
	# The hub altar. Clears any pad mode first so the two can never be half-open at
	# once — a chooser showing "PLAYER 2" and writing `selected_class` is the worst of
	# both, and it is exactly what a stale field would produce.
	_end_pad_mode()
	_title.text = "CHOOSE YOUR CLASS"
	if _dim != null:
		_dim.visible = true
	_refresh_locks()
	_refresh_highlight()
	visible = true
	var idx: int = _selected_class()
	if idx >= 0 and idx < _cards.size():
		_cards[idx].grab_focus()


func close() -> void:
	_end_pad_mode()
	visible = false


# ═════════════════════════════════════════════════════ PAD MODE (player two)
## Open the chooser for ONE local player, driven entirely by their pad.
##
## `on_pick` is called as `on_pick(device, index)` and is the ONLY thing that applies
## the choice — this screen deliberately does not know how to dress a body or which
## body is theirs. `LocalCoop._on_class_picked` does both.
## `seat` is which player they are on the couch (2, 3, 4) — NOT the device id. The first
## version put `device + 2` in the title, which reads "PLAYER 5" for anybody whose pad
## happens to enumerate as joypad 3. A device id is a hardware detail and must never
## reach a player's eyes.
func open_for_pad(device: int, pad: PadController, on_pick: Callable, seat: int = 2) -> void:
	if pad == null:
		return
	if visible and _pad_device != device:
		# Two people opening their choosers at once would share one panel and one
		# cursor. First one keeps it; the second press is simply ignored, which is
		# better than the alternative of stealing the panel out from under them.
		return
	_pad_device = device
	# ⚠ THE HERO'S OWN PAD, HANDED OVER, NOT A SECOND ONE BUILT HERE. There is one pad
	# in the player's hands; building a second `PadController` for the same device was
	# the first shape of this and it is untestable by construction — a probe's fake pad
	# cannot be behind an object this file constructs for itself. `LocalCoop` suspends
	# the HERO's side of this same object while the chooser is up, and the chooser reads
	# through the suspend with `menu_*`. See `PadController.suspended`.
	_pad = pad
	_pad_pick = on_pick
	_held_dir = Vector2i.ZERO
	_repeat_left = 0.0
	if _dim != null:
		_dim.visible = false     # player one is still fighting behind this
	if _title != null:
		_title.text = "PLAYER %d — CHOOSE YOUR CLASS" % maxi(seat, 2)
	_refresh_locks()
	var start: int = _local_class_of(device)
	_cursor = start if start >= 0 and start < _cards.size() else 0
	_paint_cursor()
	visible = true
	_opened_frame = Engine.get_physics_frames()
	set_physics_process(true)


## Is the chooser currently up for THIS device? `LocalCoop` polls it to know when the
## pad belongs to the hero again — one owner of that answer rather than two.
func is_open_for(device: int) -> bool:
	return visible and _pad_device == device


func close_for(device: int) -> void:
	if _pad_device == device:
		close()


func _end_pad_mode() -> void:
	if _pad_device < 0:
		return
	_pad_device = -1
	_pad = null
	_pad_pick = Callable()
	set_physics_process(false)
	if _dim != null:
		_dim.visible = true
	if _title != null:
		_title.text = "CHOOSE YOUR CLASS"
	_refresh_highlight()   # drop the cursor tint, leave the hub's own highlight


func _local_class_of(device: int) -> int:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("local_class_of"):
		return -1
	var v: int = int(gs.call("local_class_of", device))
	# -1 is "inherit player one", which as a STARTING CURSOR means "start on the class
	# you are actually standing in" rather than on card zero.
	return _selected_class() if v < 0 else v


## ⚠ PHYSICS, NOT IDLE, FOR THE SAME REASON `LocalCoop._physics_process` is. Confirm
## and back-out are EDGES, and a `PadController` edge lives for exactly one physics
## frame — while Godot may run up to eight physics steps inside one slow idle frame, in
## which case an idle-frame read of an edge finds it already rolled past. That failure
## is silent and frame-rate dependent: it works on an empty floor and stops working in
## the fight where somebody actually wants to change class.
func _physics_process(delta: float) -> void:
	if _pad == null or not visible:
		return
	# See `_opened_frame`: the press that opened this is still live, and reading it here
	# closes the screen on the frame it appeared.
	if Engine.get_physics_frames() == _opened_frame:
		return
	var dir := Vector2i(
		1 if _pad.menu_pressed(&"move_right") else (-1 if _pad.menu_pressed(&"move_left") else 0),
		1 if _pad.menu_pressed(&"move_down") else (-1 if _pad.menu_pressed(&"move_up") else 0))
	# ⚠ EDGE, THEN A REPEAT ON A CLOCK. A raw per-frame read walks the cursor across
	# nine cards in a sixth of a second — the grid is unusable and it looks broken
	# rather than fast. A pure edge is the other failure: holding the stick does
	# nothing and you press nine times. Both, then: the first push moves immediately,
	# and holding walks at `PAD_REPEAT_RATE`.
	if dir != _held_dir:
		_held_dir = dir
		_repeat_left = PAD_REPEAT_FIRST
		if dir != Vector2i.ZERO:
			_move_cursor(dir)
	elif dir != Vector2i.ZERO:
		_repeat_left -= delta
		if _repeat_left <= 0.0:
			_repeat_left = PAD_REPEAT_RATE
			_move_cursor(dir)
	# A confirms, B backs out. The same two buttons that got them into the game.
	# ⚠ `menu_just_pressed`, NOT `just_pressed` — the hero side of this pad is suspended
	# while the chooser is up, and the suspended side answers neutral to everything.
	if _pad.menu_just_pressed(&"jump"):
		_confirm_cursor()
	elif _pad.menu_just_pressed(&"dash") or _pad.menu_just_pressed(&"class_menu"):
		close()


## Walk the grid, clamped rather than wrapped. A wrapping cursor on a 3x3 grid means
## pushing right off the end of a row lands you on the far left of the SAME row, which
## reads as the stick having missed the input.
func _move_cursor(dir: Vector2i) -> void:
	var n: int = _cards.size()
	if n == 0:
		return
	var rows: int = int(ceil(float(n) / float(GRID_COLUMNS)))
	var col: int = _cursor % GRID_COLUMNS
	var row: int = _cursor / GRID_COLUMNS
	col = clampi(col + dir.x, 0, GRID_COLUMNS - 1)
	row = clampi(row + dir.y, 0, rows - 1)
	# The last row can be short (9 cards in 3 columns is square, but the roster moves).
	_cursor = clampi(row * GRID_COLUMNS + col, 0, n - 1)
	_paint_cursor()


## The cursor tint, drawn over the hub's "this is your class" highlight so both read.
func _paint_cursor() -> void:
	var sel: int = _local_class_of(_pad_device)
	for i: int in _cards.size():
		if i == _cursor:
			_cards[i].modulate = PAD_CURSOR
		elif i == sel:
			_cards[i].modulate = HIGHLIGHT
		else:
			_cards[i].modulate = Color.WHITE
	if _cursor >= 0 and _cursor < _cards.size():
		_cards[_cursor].grab_focus()


## ⚠ NOT `_on_card_pressed`. That one writes `selected_class` and calls
## `_apply_feedback` — player ONE's class and player ONE's body. This is the whole
## reason pad mode is a separate confirm rather than a fake button press.
func _confirm_cursor() -> void:
	if _cursor < 0 or _cursor >= _cards.size():
		return
	var gs: Node = get_node_or_null("/root/GameState")
	# Locks are re-checked here for the same reason `_on_card_pressed` re-checks them:
	# `disabled` is a display state, and a cursor can be parked on a disabled card.
	# Player two does NOT get to spend player one's banked guardian pick — that is a
	# one-shot reward on a shared save, and spending it from a pad nobody chose to give
	# it to is not a decision anybody made.
	if gs != null and not Progression.is_class_unlocked(_cursor, gs.get("unlocked_classes") as Array):
		return
	var picked: int = _cursor
	if _pad_pick.is_valid():
		_pad_pick.call(_pad_device, picked)
	close()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _on_card_pressed(index: int) -> void:
	# ⚠ THE HUB PATH ONLY. In pad mode the cards are still real Buttons with real
	# focus, so player one hitting Enter (or clicking) while player two's chooser is up
	# would fire this and write PLAYER TWO's card into `selected_class` — the exact
	# leak the separate store exists to prevent. `_confirm_cursor` is pad mode's
	# confirm, and it is the only one.
	if _pad_device >= 0:
		return
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
