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
## which screen they open:
##
##   * `"armory"` — opens `Loadout` (3 slots x 19 pieces with real effect bags that
##     `Hero._aggregate_gear` already consumes). This had been built, finished, and
##     unreachable behind a literal `if false:` in the parked hub since the day it
##     was written.
##   * `"spells"` — opens the `Outfitter`: which of your class's five authored roles
##     you carry, plus your colourway. The only customisation in the game that
##     changes how you fight.
##   * `"tree"` — opens the Archivist: which spells you may carry AT ALL.
##   * `"class"` — opens ClassSelect: which of the nine you are. The ONE pad that
##     still carries a prop, and it earns it: a gold stick-figure statue STANDS ON
##     the pad, which is the "choose your fighter" mannequin the altar always was.
##     Everything else about it — the disc, the beam, the trip — is the shared pad,
##     so it reads as one of the row rather than as the odd landmark it used to be.
##     This absorbed `ClassAltar.gd`, which was a fourth way of writing
##     walk-up-and-press-E.
##   * `"sparring"` — opens FREE PLAY: no enemies, no stakes, just your spells. The
##     game's only onboarding surface, and it used to be a title-screen button, which
##     is the one place a player is not yet curious.
##   * `"party"` — the ONLY co-op-only station: `World` does not spawn it in a solo
##     session. Press it to begin the climb together (host) or to read who is here.
##
## ⚠ THE STATION IS THE SCREEN. It does not open a menu that then offers the armory;
## pressing interact on the armoury pad IS opening the armory. That is the whole
## defence against the town being "another layer" — see the rules at the top of
## `World.gd`.

## Set by `World._spawn_stations` before the node enters the tree.
@export var kind: String = "armory"

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
## gear, arcane violet for your hand, gold for the Archivist's ledger, blood for the
## sparring ring, and the party stone's cyan, which it already wore.
const PAD_COLORS: Dictionary = {
	"armory": Color(0.62, 0.68, 0.78),
	"spells": Color(0.72, 0.52, 0.95),
	"tree": Color(1.0, 0.82, 0.42),
	"sparring": Color(0.92, 0.42, 0.38),
	"party": Color(0.45, 0.85, 1.0),
	"class": Color(0.95, 0.82, 0.35),
}
## The statue that stands on the class pad. Only this kind builds one.
const STATUE_COLOR: Color = Color(0.95, 0.82, 0.35)
## The glyph over each pad. ⚠ A PICTURE, NOT A WORD, deliberately — the maker's
## standing rule for every screen in this game is "remove the words, keep the
## picture", and the hint already carries the name for anyone who walks up.
const PAD_GLYPHS: Dictionary = {
	"armory": "⚔", "spells": "✦", "tree": "❖", "sparring": "◎", "party": "◈",
	"class": "",
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
	_art = Node2D.new()
	_art.z_index = -1     # under the player: you stand ON the pad
	_art.draw.connect(_draw_pad)
	add_child(_art)

	if kind == "class":
		_build_statue()

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


## The class pad's occupant: a gold stick figure standing on the disc, in the same
## rig every body in the game uses rather than a drawn silhouette — so the statue is
## literally a fighter, standing still, which is what the pad is asking you to pick.
##
## ⚠ IT IS TOLD IT IS GROUNDED. `CharacterRig.set_grounded` defaults to true and this
## one never moves, so it would be right by accident; it is said out loud because the
## town has already shipped one bug that was exactly an un-fed rig (see `NPC._land`).
func _build_statue() -> void:
	var statue := CharacterRig.new()
	statue.set_tint(STATUE_COLOR)
	statue.position.y = -statue.height * 0.5   # feet on the pad
	statue.set_grounded(true)
	statue.set_body_velocity(Vector2.ZERO)
	statue.set_air_phase(false, true)
	statue.play(CharacterRig.State.IDLE)
	add_child(statue)


## The beam clock, and the trip.
##
## ⚠ THE DOWN-LEG IS DRIVEN BY THE SCREEN CLOSING, NOT BY A TIMER. `_overlay_open()`
## is the same question the player's own freeze asks, so the player comes back down
## on exactly the frame they get control again — a timer would either drop them early
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
	# ⚠ THE BODY MUST BE FROZEN, AND THIS IS NEW. The town used to be driven by
	# `Player`, which asked `_overlay_open()` itself and stood still while a screen was
	# up. It is a `Hero` now — so you can cast in the lobby — and a Hero knows nothing
	# about town overlays: left running it would keep gravity, keep reading input, and
	# fall straight back out of the beam while the Outfitter was open, then be standing
	# somewhere else when it closed. Freezing physics stops the fall, the walk and the
	# casting in one line, and `_release_player` is the only place it comes back.
	_lifted.set_physics_process(false)


func _release_player() -> void:
	if _lifted != null and is_instance_valid(_lifted):
		_lifted.global_position = _lift_from
		_lifted.modulate.a = 1.0
		_lifted.set_physics_process(true)
	_lifted = null


## The hint IS the state for the party stone — it is the only station whose label
## changes with the world rather than with the player.
func _hint_text() -> String:
	match kind:
		"spells": return "[E] Spells"
		"tree": return _tree_hint()
		"sparring": return "[E] Sparring ring"
		"class": return "[E] Choose class"
		"party":
			var net: Node = get_node_or_null(^"/root/Net")
			if net == null or not bool(net.call(&"is_active")):
				return "nobody here yet"
			if not bool(net.call(&"is_host")):
				return "waiting for the host"
			return "[E] Begin the climb together"
		_: return "[E] Armory"


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("talk") or not _in_range:
		return
	if _overlay_open():
		return
	# ⚠ FIRED BEFORE THE BRANCH, NOT INSIDE EACH ONE. Every kind below either opens a
	# screen or leaves the room, and both are "the pad took you somewhere" — a beam
	# per branch is four places for one of them to be forgotten. The two that leave
	# the scene entirely (sparring, party) never come back down, which is correct:
	# the room they teleported you out of no longer exists.
	_lift_player()
	if kind == "sparring":
		# Free play is reached BY PATH and by static call, exactly as the title screen
		# reaches it: a bare identifier would drag the versus arena's whole dependency
		# chain into a script that loads with the town.
		var fp: GDScript = load("res://scripts/combat/FreePlay.gd") as GDScript
		if fp != null:
			var gs: Node = get_node_or_null(^"/root/GameState")
			var cls: int = 0 if gs == null else int(gs.get("selected_class"))
			get_viewport().set_input_as_handled()
			fp.call("enter", get_tree(), cls)
		return
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
		# ⚠ ClassSelect IS AN AUTOLOAD, not a `town_overlay` Control, so `_overlay_open`
		# above cannot see it and it has to be asked directly. That asymmetry is why
		# this used to be its own script; it is four lines, not a file.
		var sel: Node = get_node_or_null("/root/ClassSelect")
		if sel != null and sel.has_method("is_open") and not sel.is_open():
			sel.call("open")
			get_viewport().set_input_as_handled()
		return
	if kind == "tree":
		# Same ownership rule as the Outfitter below: a full-screen Control cannot be
		# parented to a StaticBody2D sitting in world space, so the town owns it.
		var town_t: Node = get_tree().current_scene
		if town_t != null and town_t.has_method("open_spell_tree"):
			town_t.call("open_spell_tree")
			get_viewport().set_input_as_handled()
		return
	if kind == "spells":
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


## ⚠ THE HINT CARRIES THE UNSPENT-POINT COUNT, and that is the only prompting the
## tree gets. A level-up already fires a spectacle in the fight; a second nag in the
## town would be the "you have unspent points!" badge that every RPG menu wears and
## that this town's whole design brief exists to avoid. But a player who has never
## opened this screen has no way to learn a point is waiting, so the station says so
## and then says nothing else.
func _tree_hint() -> String:
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs == null:
		return "[E] The Archivist"
	var owned: Array = gs.get("unlocked_nodes") as Array
	var spare: int = SpellTree.points_available(int(gs.call("level")), owned)
	if spare <= 0:
		return "[E] The Archivist"
	return "[E] The Archivist  ·  %d point%s" % [spare, "" if spare == 1 else "s"]
