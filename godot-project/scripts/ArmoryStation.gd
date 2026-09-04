extends StaticBody2D
## A TOWN STATION — a TELEPORT PAD you stand on and press interact on, which opens
## one of the screens the game already had and no player could reach.
##
## == WHY IT IS A PAD AND NOT A PROP =========================================
## Maker, walking the room: "stations should be DOORS or TELEPORT PADS, not
## scattered props — a teleportation pad, when you stand on it and press teleport a
## beam of light comes up and you teleport, and then you teleport down."
##
## The props were a weapon rack, a lectern, a chalk ring and a standing stone: four
## silhouettes, none of which told you it was pressable and two of which (the rack
## and the sparring dummy) were the same brown post at the same height. A PAD says
## one thing and says it the same way every time — **you may stand here, and
## standing here does something** — and the beam is the answer to "did that work",
## which a menu appearing somewhere else on the screen never was.
##
## ⚠ THE PAD IS STILL THE SCREEN. Nothing about the trip is a step you have to take:
## the beam plays WHILE the screen opens, not before it, so the teleport costs zero
## extra presses and zero waiting. If it ever gates the screen behind an animation it
## has become the "another layer" this whole room was rewritten to stop being.
##
## KINDS, one script, because they differ only in their colour, their glyph and
## which screen they open. There are THREE, and only TWO of them are ever in a solo
## room:
##
##   * `"armory"` — opens `Loadout` (3 slots x 19 pieces with real effect bags that
##     `Hero._aggregate_gear` already consumes). This had been built, finished, and
##     unreachable behind a literal `if false:` in the parked hub since the day it
##     was written. Equipment, and nothing but equipment.
##   * `"class"` — opens the `Outfitter`, which is now BOTH halves of "who am I":
##     which of the nine you are AND which of your class's five authored roles you
##     carry. See `World.open_outfitter` for the merge and for why it is shaped as a
##     header button rather than as two chained screens.
##   * `"party"` — the ONLY co-op-only station: `World` does not spawn it in a solo
##     session. Press it to begin the climb together (host) or to read who is here.
##
## ⚠ THREE KINDS HAVE BEEN DELETED FROM THIS FILE, and every one of them went for the
## same reason: a `kind` nothing builds is a colour, a glyph and a code branch that the
## next reader has to work out is dead.
##
##   * `"sparring"` teleported you out to `FreePlay` — a whole second scene with its own
##     stage, camera and control card — to answer "what does this spell look like". The
##     maker: "you should be able to cast spells and stuff within the lobby instead of a
##     training ground; just have standing immortal test dummies on one side."
##     `World._spawn_dummy_yard` is that. `FreePlay` itself is untouched, and still F6.
##   * `"spells"` was the lectern, and its screen is what `"class"` now opens. The maker,
##     asked which pads to keep: *"I only want one for class within which I can edit
##     spells, and one for armoury where I can look at my equipment"*.
##   * `"tree"` was the Archivist, and it is the one worth remembering. It opened
##     `SpellTreeScreen`, which SPENDS REAL POINTS — and `SpellTree.bindable_spells()`,
##     the function that whole economy exists to feed, has no caller anywhere outside
##     its own test suite. So the pad took something from the player and gave back
##     nothing that could reach a fight. Deleting it removed a screen that lied, which
##     is a better argument for the ruling than tidiness was. `SpellTreeScreen.gd` is
##     KEPT and its header says what has to become true before a pad points at it again.
##
## ⚠ THE STATION IS THE SCREEN. It does not open a menu that then offers the armory;
## pressing interact on the armoury pad IS opening the armory. That is the whole
## defence against the town being "another layer" — see the rules at the top of
## `World.gd`.

## Set by `World._spawn_stations` before the node enters the tree.
@export var kind: String = "armory"

## Nearest-wins arbitration for the `talk` key -- see the file for the two bugs
## it exists for, both of which are two of these rings overlapping.
const Interactables := preload("res://scripts/Interactables.gd")

const PROXIMITY_RADIUS: float = 46.0

## -- THE PAD ------------------------------------------------------------------
## Wide and flat, because it has to read as FLOOR you step onto rather than an
## object you bump into — the whole point of the shape is that the invitation is
## "stand here", which no vertical prop can say.
const PAD_RADIUS: float = 30.0
const PAD_SQUASH: float = 0.30       # it LIES DOWN: an ellipse, not a circle
const PAD_RIM_WIDTH: float = 2.0
## The column of light. Present at rest and low, so the pad announces itself from
## across the room; the ACTIVATION is the same column at full brightness, which is
## why the two are one drawing and not two effects that could disagree.
const COLUMN_WIDTH: float = 24.0
const COLUMN_HEIGHT: float = 104.0
const COLUMN_REST_ALPHA: float = 0.09
## How long the beam takes to fire, and to fade once you are back. Shorter than any
## screen takes to appear, on purpose — see "the pad is still the screen" above.
const BEAM_RISE: float = 3.4         # units of `_beam` per second, so ~0.3 s
const BEAM_FALL: float = 2.2
## How far the player rises while the beam holds them. Enough to read as "gone",
## small enough that the camera never has to move.
const LIFT_HEIGHT: float = 40.0

## ONE COLOUR PER STATION, and it is the only thing that tells them apart at a
## glance. Chosen for what each screen is ABOUT rather than to be pretty: steel for
## gear, gold for who you are, and the party stone's cyan, which it already wore.
##
## ⚠ THE VIOLET (`"spells"`) AND THE AMBER (`"tree"`) ARE GONE WITH THEIR KINDS. A
## colour left in this table for a kind nothing spawns is a pad somebody will try to
## build back by writing one line, without the branch below that makes it do anything.
const PAD_COLORS: Dictionary = {
	"armory": Color(0.62, 0.68, 0.78),
	"party": Color(0.45, 0.85, 1.0),
	"class": Color(0.95, 0.82, 0.35),
}
## The glyph over each pad. ⚠ A PICTURE, NOT A WORD, deliberately — the maker's
## standing rule for every screen in this game is "remove the words, keep the
## picture", and the hint already carries the name for anyone who walks up.
## These two are also what `World._build_signboard`'s left arm points with, so a glyph
## added here without a glyph added there is a sign that under-reports the room.
const PAD_GLYPHS: Dictionary = {
	"armory": "⚔", "party": "◈", "class": "☗",
}
const GLYPH_FONT_SIZE: int = 22
const GLYPH_LIFT: float = 58.0

var _hint: Label = null
var _in_range: bool = false
## The pad's drawing surface. A child `Node2D` rather than `_draw` on the body, so the
## art sits at its own z and the player stands ON the pad rather than behind it.
var _art: Node2D = null
## 0 at rest, 1 at full beam. Drives the column, the rim glow and the lift together so
## they can never be out of step with each other.
var _beam: float = 0.0
var _beam_up: bool = false
## The player we lifted and where it stood before we did — so the trip back down is
## against the truth rather than against an assumed ground line.
var _lifted: Node2D = null
var _lift_from: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Compete for the `talk` press by DISTANCE rather than by tree order.
	# See `Interactables` for the two bugs that ordering shipped.
	add_to_group(Interactables.GROUP)
	_art = Node2D.new()
	_art.z_index = -1     # under the player: you stand ON the pad
	_art.draw.connect(_draw_pad)
	add_child(_art)

	# ⚠ THE CLASS PAD NO LONGER CARRIES A STATUE. Maker, in the room: "the yellow dummy
	# should be on the far left of it all with the other 3 dummies" — they read the gold
	# mannequin as a fourth practice dummy, which is a fair reading of "a stick figure
	# standing still that you can walk up to". A pad that is the odd one out teaches the
	# wrong thing about the row; every pad is now the same object with a different
	# colour and glyph, which was the point of making them pads.
	var glyph := Label.new()
	glyph.text = String(PAD_GLYPHS.get(kind, "◆"))
	glyph.position = Vector2(-14.0, -GLYPH_LIFT)
	glyph.add_theme_font_size_override("font_size", GLYPH_FONT_SIZE)
	glyph.add_theme_color_override("font_color", _tint())
	glyph.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.09, 0.9))
	glyph.add_theme_constant_override("outline_size", 4)
	add_child(glyph)

	# ⚠ NO COLLISION SHAPE ANY MORE, AND THAT IS THE POINT OF A PAD. The props were
	# solid, so "walk up to it" meant "walk INTO it and stop"; a pad is floor, and you
	# have to be able to stand in the middle of one for the beam to mean anything. The
	# body stays a StaticBody2D because the proximity Area2D and every `_spawn_stations`
	# call site already address it as one.

	var area := Area2D.new()
	add_child(area)
	# ⚠ MASK 1 AND 2. The town body used to be `Player.tscn` (collision layer 1) and is
	# a `Hero` now (layer 2) so you can cast in the lobby. An Area2D's default mask is
	# 1 alone, so this ring silently stopped seeing the player the day that changed —
	# no "[E] ..." prompt, on any pad, with nothing in the log. Watching both layers is
	# the honest fix: this ring's job is "is the person here", not "which scene are
	# they". Putting the hero on layer 1 instead would make it count as GROUND to every
	# rig's floor probe.
	area.collision_mask = 1 | 2
	var area_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PROXIMITY_RADIUS
	area_shape.shape = circle
	area_shape.position = Vector2(0.0, -15.0)
	area.add_child(area_shape)
	area.body_entered.connect(func(b: Node) -> void:
		if b.is_in_group("player"):
			_in_range = true
			_hint.visible = true)
	area.body_exited.connect(func(b: Node) -> void:
		if b.is_in_group("player"):
			_in_range = false
			_hint.visible = false)

	_hint = Label.new()
	_hint.text = _hint_text()
	_hint.position = Vector2(-38.0, -84.0)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.visible = false
	add_child(_hint)


## -- the pad, the column, the trip ---------------------------------------------
## The whole station in one drawing: a flat disc, a rim, a column of light standing
## on it, and a soft floor-glow underneath. `_beam` (0..1) is the only variable —
## every element below reads it, so the pad can never be half-lit in one part and
## dark in another.
##
## ⚠ DRAWN, NOT NODES. The props this replaced were seven ColorRects and two
## Polygon2Ds per station; a pad that pulses would have needed all of them animated
## in step. One `_draw` that reads one float cannot drift out of sync with itself,
## and it is also what makes the whole thing degrade for free at LOW quality: fewer
## draw calls than the rack it replaced.
func _draw_pad() -> void:
	var col: Color = _tint()
	var lit: float = clampf(_beam, 0.0, 1.0)
	# The floor glow, widest and faintest, so the pad has a footprint before it has
	# an edge. It swells with the beam.
	_ellipse(_art, Vector2.ZERO, PAD_RADIUS * (1.35 + 0.25 * lit),
		Color(col.r, col.g, col.b, 0.06 + 0.14 * lit))
	# The disc itself, then its rim. The rim is the part that reads at distance.
	_ellipse(_art, Vector2.ZERO, PAD_RADIUS, Color(col.r, col.g, col.b, 0.14 + 0.30 * lit))
	_ellipse_line(_art, Vector2.ZERO, PAD_RADIUS,
		Color(col.r, col.g, col.b, 0.55 + 0.45 * lit), PAD_RIM_WIDTH + lit * 1.5)
	# THE COLUMN. Two stacked quads with alpha falling off upward, so the light
	# reads as leaving rather than as a painted bar. Its width narrows as it
	# brightens — a beam gathering, not a slab appearing.
	var a: float = COLUMN_REST_ALPHA + (0.62 - COLUMN_REST_ALPHA) * lit
	var half: float = COLUMN_WIDTH * 0.5 * (1.0 - 0.25 * lit)
	var top: float = -COLUMN_HEIGHT * (0.55 + 0.45 * lit)
	_art.draw_polygon(
		PackedVector2Array([
			Vector2(-half, 0.0), Vector2(half, 0.0),
			Vector2(half * 0.55, top), Vector2(-half * 0.55, top),
		]),
		PackedColorArray([
			Color(col.r, col.g, col.b, a), Color(col.r, col.g, col.b, a),
			Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0),
		]))
	# A white-hot core, only while it is actually firing. This is the frame the eye
	# catches; without it the beam reads as the pad simply getting brighter.
	if lit > 0.02:
		var core: float = half * 0.32
		_art.draw_polygon(
			PackedVector2Array([
				Vector2(-core, 0.0), Vector2(core, 0.0),
				Vector2(core * 0.4, top * 1.05), Vector2(-core * 0.4, top * 1.05),
			]),
			PackedColorArray([
				Color(1.0, 1.0, 1.0, 0.55 * lit), Color(1.0, 1.0, 1.0, 0.55 * lit),
				Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.0),
			]))


## A filled ellipse, flattened by `PAD_SQUASH` so it lies on the floor. `draw_circle`
## with a scaled transform would also scale the rim WIDTH, which is what made the
## first pass look like a smudge at distance.
static func _ellipse(on: Node2D, at: Vector2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in 22:
		var t: float = TAU * float(i) / 22.0
		pts.append(at + Vector2(cos(t) * radius, sin(t) * radius * PAD_SQUASH))
	on.draw_colored_polygon(pts, col)


static func _ellipse_line(on: Node2D, at: Vector2, radius: float, col: Color,
		width: float) -> void:
	var pts := PackedVector2Array()
	for i: int in 23:
		var t: float = TAU * float(i % 22) / 22.0
		pts.append(at + Vector2(cos(t) * radius, sin(t) * radius * PAD_SQUASH))
	on.draw_polyline(pts, col, width)


func _tint() -> Color:
	return PAD_COLORS.get(kind, Color(0.7, 0.75, 0.85))


## The beam clock, and the trip.
##
## ⚠ THE DOWN-LEG IS DRIVEN BY THE SCREEN CLOSING, NOT BY A TIMER. `_overlay_open()`
## is the same question the player's own freeze asks, so the player comes back down on
## exactly the frame they get control again — a timer would either drop them early
## (standing frozen on the floor) or late (walking while still transparent).
func _process(delta: float) -> void:
	# ⚠ THE BEAM HOLDS FOR THE FIRST FRAMES BEFORE THE SCREEN IS UP. `_lift_player`
	# runs in the same frame as the press and the overlay is only in the tree on the
	# NEXT one, so a bare `_beam_up and _overlay_open()` would fire the beam and
	# immediately cancel it. `_beam < 1.0` carries it through the rise; after that the
	# open screen is what keeps it lit.
	var want: bool = _beam_up and (_beam < 1.0 or _overlay_open())
	if _beam_up and not want:
		_beam_up = false
	_beam = clampf(_beam + (BEAM_RISE if want else -BEAM_FALL) * delta, 0.0, 1.0)
	if _lifted != null and is_instance_valid(_lifted):
		_lifted.global_position = _lift_from + Vector2(0.0, -LIFT_HEIGHT * _beam)
		_lifted.modulate.a = 1.0 - 0.85 * _beam
		if _beam <= 0.0:
			_release_player()
	if _art != null:
		_art.queue_redraw()


## Take hold of the player standing on this pad. Position and alpha are RESTORED from
## what was read here, never from a constant — a player who was mid-jump, or whom some
## other system had tinted, must land back exactly as they were.
func _lift_player() -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D):
		return
	_lifted = p as Node2D
	_lift_from = _lifted.global_position
	_beam_up = true
	# ⚠ THE BODY MUST BE FROZEN. The town used to be driven by `Player`, which asked
	# `_overlay_open()` itself and stood still while a screen was up. It is a `Hero`
	# now — so you can cast in the lobby — and a Hero knows nothing about town
	# overlays: left running it would keep gravity, keep reading input, and fall
	# straight back out of the beam while the Outfitter was open, then be standing
	# somewhere else when it closed.
	_lifted.set_physics_process(false)


func _release_player() -> void:
	if _lifted != null and is_instance_valid(_lifted):
		_lifted.global_position = _lift_from
		_lifted.modulate.a = 1.0
		_lifted.set_physics_process(true)
		_redress(_lifted)
	_lifted = null


## Rebuild the body's class kit as it lands.
##
## ⚠ ONE PLACE, FOR EVERY PAD. The Outfitter changes which ROLES you carry AND (since
## the merge) which CLASS you are, and the armory changes your gear — all of which used
## to be read only at `configure_class` time, i.e. at spawn. Since the town body is a
## `Hero` you can cast with, a change made on a pad has to reach the hand you walk away
## with, and the moment it lands is the moment the trip ends. Doing it per-screen would
## be several chances to forget, and the merge just removed one of them.
func _redress(body: Node2D) -> void:
	if not body.has_method("configure_class"):
		return
	var gs: Node = get_node_or_null(^"/root/GameState")
	body.call("configure_class", 0 if gs == null else int(gs.get("selected_class")))


## The hint IS the state for the party stone — it is the only station whose label
## changes with the world rather than with the player.
##
## ⚠ THE CLASS PAD SAYS BOTH THINGS IT DOES. "[E] Choose class" was true when the
## lectern next door carried the spells; it is now the only route to either, and a hint
## that names half a screen is how a player decides they have already seen it.
func _hint_text() -> String:
	match kind:
		"class": return "[E] Class & spells"
		"party":
			var net: Node = get_node_or_null(^"/root/Net")
			if net == null or not bool(net.call(&"is_active")):
				return "nobody here yet"
			if not bool(net.call(&"is_host")):
				return "waiting for the host"
			return "[E] Begin the climb together"
		_: return "[E] Armory"


## Answers the arbitration in `Interactables`.
func interact_ready() -> bool:
	return _in_range


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("talk") or not _in_range:
		return
	if _overlay_open():
		return
	# The warden's 40 px ring reaches x=384 and the armoury pad sits at x=380, so for
	# part of every lap he walks, standing ON the pad showed two hints and the press
	# went to him. Nearest wins. See `Interactables`.
	if not Interactables.wins(self):
		return
	# ⚠ FIRED BEFORE THE BRANCH, NOT INSIDE EACH ONE. Every kind below either opens a
	# screen or leaves the room, and both are "the pad took you somewhere" — a beam per
	# branch is four places for one of them to be forgotten. The one that leaves the
	# scene entirely (party, which starts the co-op climb) never comes back down, which
	# is correct: the room it teleported you out of no longer exists.
	_lift_player()
	if kind == "party":
		# Only the HOST can start; a client pressing this is answered by the hint,
		# which already says what it is waiting for.
		var net: Node = get_node_or_null(^"/root/Net")
		if net != null and bool(net.call(&"is_active")) and bool(net.call(&"is_host")):
			get_viewport().set_input_as_handled()
			net.call(&"start_coop_run")
		elif _hint != null:
			_hint.text = _hint_text()   # re-read: a friend may have joined since
		return
	if kind == "class":
		# ⚠ IT OPENS THE OUTFITTER, NOT `ClassSelect`, AND THAT IS THE MERGE. The maker
		# wants ONE pad that answers both "which of the nine am I" and "which three do I
		# carry"; the Outfitter is the screen that already held the second half and it now
		# carries a header button for the first (`Outfitter.show_class_picker`, which
		# `World.open_outfitter` sets). Pressing E here therefore lands on the SPELLS —
		# the thing you come back for — with the class one tap away, rather than on a
		# class grid you have to get past to reach a spell.
		#
		# The Outfitter is a Control and needs a CanvasLayer, so the town owns its
		# lifetime rather than this station parenting a full-screen panel to a
		# StaticBody2D sitting in world space.
		var town: Node = get_tree().current_scene
		if town != null and town.has_method("open_outfitter"):
			town.call("open_outfitter")
			get_viewport().set_input_as_handled()
		return
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("open"):
		lo.call("open")
		get_viewport().set_input_as_handled()


## True while any other town screen is up. See the same helper on `NPC.gd`.
func _overlay_open() -> bool:
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		return true
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("is_open") and lo.is_open():
		return true
	for o: Node in get_tree().get_nodes_in_group("town_overlay"):
		if o is CanvasItem and (o as CanvasItem).visible:
			return true
	return false


## ⚠ `_tree_hint()` IS DELETED WITH THE `"tree"` KIND, AND IT TOOK ONE REAL THING WITH
## IT: the unspent-skill-point count. It read `SpellTree.points_available(...)` into the
## Archivist's hint, and it was the ONLY place in the town that ever told a player a
## point was waiting. Nothing surfaces that now, which is honest rather than a
## regression — the points bought nodes that reached no fight (see the header) — but it
## is the line to restore alongside the pad if the tree is ever wired up. `NPC.gd`'s
## `{points}` token still exists and would put the same fact in a townsperson's mouth
## for one word of a `.tres`, if a nag is wanted sooner than a pad.
