class_name SpellTreeScreen
extends Control
## THE ARCHIVIST'S SCREEN — and it is a TREE now, not a list.
##
## ══ WHY IT WAS REWRITTEN ════════════════════════════════════════════════════
## Maker, on the old screen: "the Archivist must be an ACTUAL TREE — click a node to
## spend a point, and the branches visibly grow as you invest. Not a list of rows."
##
## The old screen was nine scrolling buttons, each carrying a sentence of its own
## state ("Rock Wall — 2 pts (need 1 more)"). Every fact was there and none of it was
## a SHAPE: you could not see that a role had two nodes, that the far one costs
## double, or that you had put everything into one branch and nothing into the rest.
## A tree says all of that without a word, in the one place a phone player is
## actually looking — the picture.
##
## ⚠ THE GROWTH IS THE FEEDBACK, and it is why this is not merely a prettier list. A
## bought node does not just change colour: its bough THICKENS and REACHES over about
## a third of a second, and buds open at the tip. That is the "I spent something and
## something happened" beat the old screen answered with a label changing tense.
##
## ⚠ EVERY RULE IS STILL IN `SpellTree`, NOT HERE. This file draws boughs and calls
## `can_buy`. That separation is what let the whole economy — including the five
## mis-pointed links in the design doc — be tested before a single pixel existed, and
## it is why this rewrite touched no test in `tools/slice_test_spell_tree.gd`.
##
## ⚠ IT SPENDS POINTS AND NOTHING ELSE. Which roles you CARRY is the Outfitter's job
## and stays there. The tree grows your OPTIONS, the Outfitter picks your HAND.

signal closed

const PANEL_W: float = 400.0
## Every tappable target clears this, matching the Outfitter, the Lobby and the town.
const MIN_TAP: float = 30.0
## The node hit-target. Bigger than `MIN_TAP` because these are not a row with
## generous margins — they are scattered on a drawing, and a near-miss on a phone
## should still land on the thing you were obviously aiming at.
const NODE_TAP: float = 38.0

const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)
const AFFORD: Color = Color(0.66, 0.92, 0.72)     # you can buy this
const TOO_DEAR: Color = Color(0.52, 0.44, 0.44)   # you cannot, yet
const OWNED: Color = Color(0.70, 0.78, 0.95)
const BARK: Color = Color(0.34, 0.27, 0.21)
const BARK_LIVE: Color = Color(0.52, 0.42, 0.28)

## ── THE DRAWING ──────────────────────────────────────────────────────────────
## The canvas is a fixed size and every position below is inside it, so the tree is
## laid out once in tree-space and the panel simply holds it. Resizing the panel must
## never move a node out from under a finger already on its way down.
## ⚠ 324 OVERFLOWED THE SCREEN. Measured, not reasoned: the game's base viewport is
## 640x360 and this panel is title + points + canvas + Close, so a 324-tall canvas
## made a screen ~400 units tall inside a 360-unit window — the Close button off the
## bottom edge, which is the exact failure the old list's ScrollContainer existed to
## avoid. The whole budget is 360 minus ~66 of header and button.
const CANVAS: Vector2 = Vector2(PANEL_W, 272.0)
## Where the trunk forks. Low and central: the boughs fan UP from here, which is the
## way a tree grows and the way "more expensive" runs on this screen.
const FORK: Vector2 = Vector2(PANEL_W * 0.5, 214.0)
const TRUNK_BOTTOM: float = 268.0
## How far out along a bough each shelf sits. The NATIVE (your own class's spell) is
## close to the trunk; the LINK (somebody else's, at double the price) is out at the
## tip. DISTANCE IS COST, which is the one thing a list could never show.
const R_NATIVE: float = 76.0
const R_LINKED: float = 136.0
## The five boughs, in `SpellTree.ROLES` order, fanned across the top. Degrees,
## screen-space, 0 = right, negative = up. Spread so no two nodes can collide with a
## `NODE_TAP` box: at R_NATIVE the neighbour gap is 2 * 76 * sin(17) = 44 px.
##
## ⚠ THE FIFTH IS THE ULT AND IT POINTS STRAIGHT UP, alone above the fan, because it
## is the one branch with no link, no price and no way to lose it. It is the class
## itself, and a shelf you cannot spend on should not sit in the row of shelves you
## can.
const BOUGH_ANGLES: Array[float] = [-152.0, -118.0, -62.0, -28.0, -90.0]

const GROW_RATE: float = 3.4        # units per second: a bough fills in ~0.3 s
const BUD_RADIUS: float = 3.2

var _class_id: int = 0
var _title: Label = null
var _points: Label = null
var _canvas: Control = null
## role -> 0..1, how grown that bough is DRAWN as. Lerped toward the owned count, so a
## purchase is a movement rather than a repaint.
var _grown: Dictionary = {}
## The invisible tap targets, one per node, keyed by node id.
var _taps: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	refresh()
	_snap_growth()


func set_class(class_id: int) -> void:
	_class_id = clampi(class_id, 0, SpellTree.TREES.size() - 1)
	_rebuild_taps()
	refresh()
	_snap_growth()


## Open at full growth for whatever is already owned, so entering the screen is not
## an animation of your entire history replaying at you.
func _snap_growth() -> void:
	for role: String in SpellTree.ROLES:
		_grown[role] = _target_growth(role)
	if _canvas != null:
		_canvas.queue_redraw()


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
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

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

	# ⚠ NO SCROLL CONTAINER ANY MORE. The list needed one — nine rows plus headers
	# overflowed a phone in portrait and pushed Close off the bottom edge, i.e. a
	# screen with no exit on the target platform. A tree does not grow downward: it
	# fans, so the whole thing fits one fixed canvas at any node count.
	_canvas = Control.new()
	_canvas.custom_minimum_size = CANVAS
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_draw_tree)
	col.add_child(_canvas)
	_rebuild_taps()

	col.add_child(_button("Close", close, 13))


## One invisible Button per node, parked on the node's position. Real Buttons rather
## than hit-testing in `_gui_input`, for two reasons that are both about the phone:
## press feedback comes for free, and `slice_test_town`'s tap-target sweep measures
## Buttons — a hand-rolled hit box would pass that test by being invisible to it,
## which is the worst way to pass a test.
func _rebuild_taps() -> void:
	if _canvas == null:
		return
	for b: Variant in _taps.values():
		if is_instance_valid(b):
			(b as Node).queue_free()
	_taps.clear()
	for role: String in SpellTree.ROLES:
		for linked: bool in [false, true]:
			var node: String = SpellTree.node_id(_class_id, role, linked)
			if SpellTree.spell_of(node) == "":
				continue     # the ult has no link — no node, no tap target
			var b := Button.new()
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(NODE_TAP, NODE_TAP)
			b.size = Vector2(NODE_TAP, NODE_TAP)
			b.position = _node_pos(role, linked) - Vector2(NODE_TAP, NODE_TAP) * 0.5
			b.tooltip_text = _node_label(node)
			b.pressed.connect(_buy.bind(node))
			_canvas.add_child(b)
			_taps[node] = b


## Where a node sits on the canvas. The single source of truth for both the drawing
## and the tap target — they cannot drift apart because there is only one of them.
func _node_pos(role: String, linked: bool) -> Vector2:
	var idx: int = SpellTree.ROLES.find(role)
	if idx < 0:
		idx = 0
	var a: float = deg_to_rad(BOUGH_ANGLES[idx % BOUGH_ANGLES.size()])
	var r: float = R_LINKED if linked else R_NATIVE
	# ⚠ A LINKLESS BOUGH PUTS ITS ONE NODE AT THE TIP. That is the ult, straight up,
	# and it is not a flourish: at R_NATIVE it sat 37 px from its two neighbours, which
	# is inside the 38 px tap box — a press aimed at the ult could land on the control
	# slot. Sending it to the tip clears that to 66 px AND reads better, because the
	# branch you cannot spend on is the one crowning the tree.
	if not linked and SpellTree.spell_of(SpellTree.node_id(_class_id, role, true)) == "":
		r = R_LINKED
	return FORK + Vector2(cos(a), sin(a)) * r


func _button(text: String, cb: Callable, font_size: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(PANEL_W, MIN_TAP)
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE   # a stray focus ring on a phone reads as a bug
	b.clip_text = true
	b.pressed.connect(cb)
	return b


## How grown a bough SHOULD be: 0 with nothing on it, 0.5 with the native, 1 with
## both. Free nodes count — a class's opening hand is already a living branch.
func _target_growth(role: String) -> float:
	var owned: Array = _owned()
	var have: float = 0.0
	var total: float = 0.0
	for linked: bool in [false, true]:
		var node: String = SpellTree.node_id(_class_id, role, linked)
		if SpellTree.spell_of(node) == "":
			continue
		total += 1.0
		if SpellTree.is_free(node) or SpellTree.is_unlocked(node, owned):
			have += 1.0
	return 0.0 if total <= 0.0 else have / total


func _process(delta: float) -> void:
	if _canvas == null:
		return
	var moving: bool = false
	for role: String in SpellTree.ROLES:
		var now: float = float(_grown.get(role, 0.0))
		var want: float = _target_growth(role)
		if absf(now - want) > 0.001:
			_grown[role] = move_toward(now, want, GROW_RATE * delta)
			moving = true
	if moving:
		_canvas.queue_redraw()


# ═══════════════════════════════════════════════════════════════ the drawing
func _draw_tree() -> void:
	var owned: Array = _owned()
	var level: int = _level()
	# The trunk. Always alive — it is the class itself, and it is not for sale.
	_canvas.draw_line(Vector2(FORK.x, TRUNK_BOTTOM), Vector2(FORK.x, FORK.y + 14.0),
		BARK, 13.0)
	_canvas.draw_line(Vector2(FORK.x, TRUNK_BOTTOM), FORK, BARK_LIVE, 8.0)

	for role: String in SpellTree.ROLES:
		var grown: float = float(_grown.get(role, 0.0))
		var inner: Vector2 = _node_pos(role, false)
		var outer: Vector2 = _node_pos(role, true)
		var has_link: bool = SpellTree.spell_of(SpellTree.node_id(_class_id, role, true)) != ""
		# THE BOUGH GROWS IN TWO LEGS: fork -> native, native -> link. So the branch
		# physically REACHES further as you buy outward, which is the "visibly grow"
		# the maker asked for. A dead leg is still drawn, thin and dark — you have to
		# be able to see what you have not bought.
		_bough(FORK, inner, clampf(grown * 2.0, 0.0, 1.0))
		if has_link:
			_bough(inner, outer, clampf(grown * 2.0 - 1.0, 0.0, 1.0))

	# ⚠ NODES AFTER EVERY BOUGH, NOT INTERLEAVED. Boughs overlap near the fork, and a
	# later branch drawn over an earlier node would cut a bark-coloured line across a
	# disc the player is trying to press.
	for role2: String in SpellTree.ROLES:
		_node(role2, false, level, owned)
		if SpellTree.spell_of(SpellTree.node_id(_class_id, role2, true)) != "":
			_node(role2, true, level, owned)


## One leg of a bough. `live` 0..1 is how much of it has grown: the dead remainder is
## a thin dark twig, the grown part is thicker, lighter, and buds at its tip.
func _bough(from: Vector2, to: Vector2, live: float) -> void:
	_canvas.draw_line(from, to, BARK, 2.0)
	if live <= 0.0:
		return
	var tip: Vector2 = from.lerp(to, live)
	_canvas.draw_line(from, tip, BARK_LIVE, 2.0 + 4.0 * live)
	# Buds, at the tip, only once the leg is essentially full — so a half-grown branch
	# reads as reaching rather than as finished.
	if live < 0.92:
		return
	var along: Vector2 = (to - from).normalized()
	var side := Vector2(-along.y, along.x)
	for s: float in [-1.0, 1.0]:
		_canvas.draw_circle(tip + side * s * 6.0 - along * 6.0, BUD_RADIUS,
			Color(0.56, 0.80, 0.52, 0.9))


## One node: a disc, its ring, its cost pips and its name.
##
## ⚠ THE STATE IS THE PICTURE, NOT A SENTENCE. The old list wrote "— 2 pts (need 1
## more)" on every row it could not sell you. Here: filled = yours, bright ring =
## affordable, dim = not yet, and the PIPS are the price. Nothing has to be read.
func _node(role: String, linked: bool, level: int, owned: Array) -> void:
	var node: String = SpellTree.node_id(_class_id, role, linked)
	var at: Vector2 = _node_pos(role, linked)
	var have: bool = SpellTree.is_free(node) or SpellTree.is_unlocked(node, owned)
	var buyable: bool = SpellTree.can_buy(node, _class_id, level, owned)
	var col: Color = OWNED if have else (AFFORD if buyable else TOO_DEAR)
	var r: float = 12.0 if linked else 15.0

	if have:
		_canvas.draw_circle(at, r + 3.0, Color(col.r, col.g, col.b, 0.16))
		_canvas.draw_circle(at, r, Color(col.r, col.g, col.b, 0.55))
	elif buyable:
		# The one thing on screen asking to be pressed gets a wash of its own.
		_canvas.draw_circle(at, r + 2.0, Color(col.r, col.g, col.b, 0.12))
	_canvas.draw_arc(at, r, 0.0, TAU, 26, col, 2.0 if have or buyable else 1.0, true)

	# COST PIPS, under the ring, and only while it is still for sale. One dot a point.
	if not have:
		var cost: int = SpellTree.cost_of(node)
		for i: int in cost:
			_canvas.draw_circle(
				at + Vector2((float(i) - float(cost - 1) * 0.5) * 6.0, r + 7.0), 2.0, col)

	# ⚠ THE LABEL SITS ON THE OUTWARD SIDE, so a bough never writes its name across the
	# branch it grew from. Above the node when it points upward, below otherwise.
	var dir: Vector2 = (at - FORK).normalized()
	var lift: float = -r - 7.0 if dir.y < -0.55 else r + 19.0
	var w: float = 100.0
	_canvas.draw_string(ThemeDB.fallback_font, at + Vector2(-w * 0.5, lift),
		_short_name(node), HORIZONTAL_ALIGNMENT_CENTER, w, 10, col)


## The spell's display name, short enough for the label. `AbilityBar` already owns
## "the most identifying word" rule, so this borrows it rather than inventing a
## second answer that could disagree with the hotbar.
func _short_name(node: String) -> String:
	var spell_id: String = SpellTree.spell_of(node)
	var def: SpellDef = SpellLibrary.by_id(spell_id)
	if def == null:
		return spell_id
	return AbilityBar.short_spell_name(String(def.display_name))


func _node_label(node: String) -> String:
	var spell_id: String = SpellTree.spell_of(node)
	var def: SpellDef = SpellLibrary.by_id(spell_id)
	var name: String = spell_id if def == null else String(def.display_name)
	if SpellTree.is_free(node):
		return "%s — yours" % name
	return "%s — %d pt" % [name, SpellTree.cost_of(node)]


# ═══════════════════════════════════════════════════════════════════ the state
func _owned() -> Array:
	var gs: Node = get_node_or_null(^"/root/GameState")
	return [] if gs == null else (gs.get("unlocked_nodes") as Array)


func _level() -> int:
	var gs: Node = get_node_or_null(^"/root/GameState")
	return 1 if gs == null else int(gs.call("level"))


## Repaint the header and the tree. Cheap: the tree is one `_draw` and the tap
## targets never move, so there is nothing to rebuild.
func refresh() -> void:
	if _title == null:
		return
	var avail: int = SpellTree.points_available(_level(), _owned())
	_title.text = "%s — the Archivist" % ClassInfo.name_for(_class_id)
	# ⚠ ONE LINE, AND IT IS THE ONLY PROSE ON THE SCREEN. The old header carried level,
	# points, spent and total — four numbers, three of which the tree now shows as
	# shape. What a picture cannot say is how much you have left to spend.
	_points.text = "%d point%s to spend" % [avail, "" if avail == 1 else "s"]
	for node: Variant in _taps.keys():
		var b: Button = _taps[node] as Button
		if is_instance_valid(b):
			b.tooltip_text = _node_label(String(node))
	if _canvas != null:
		_canvas.queue_redraw()


func _buy(node: String) -> void:
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs == null:
		return
	var level: int = int(gs.call("level"))
	var owned: Array = gs.get("unlocked_nodes") as Array
	# ⚠ RE-CHECKED HERE, not trusted from the button's state. A node that was
	# affordable when the tree was drawn can be stale by the time it is pressed — two
	# rapid taps on a 1-point balance would otherwise buy two nodes.
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
