class_name GhostForm
extends Node2D
## GHOST FORM — you are dead, you are still here, and you are still playing.
##
## The maker's rule: "dying cost is a life in ghost form until your teammate revives
## you". So a downed hero is not a corpse on the floor and not a spectator camera —
## it is a body you still steer, that cannot hit and cannot be hit, drifting through
## a fight it can no longer damage.
##
## ══ WHAT A GHOST CAN DO, AND WHY ═══════════════════════════════════════════════
## The brief is blunt about the failure mode: "a player with nothing to do for 40
## seconds is the worst outcome in a game whose brief is action packed". A ghost
## therefore keeps THREE verbs, chosen so the downed player is busy doing the exact
## thing that gets them back up rather than being given a consolation toy:
##
##   1. DRIFT FREELY — full twin-stick movement at `Hero.GHOST_SPEED`, no gravity,
##      passing through everything except the arena walls. Free drift and not
##      "drift near your body" is a deliberate call: the revive needs the two of you
##      in the same place, and making the GHOST responsible for closing that gap
##      turns being dead into a navigation problem instead of a wait. Your friend is
##      busy not dying; you are the one who can move without consequence.
##   2. SEE THE WHOLE FIGHT — free, because THE TOWER frames the whole arena on one
##      screen. A ghost is never looking at a corner of a room it cannot reach.
##   3. HAUNT — a chalk gust that deals NO damage and shoves nearby enemies off.
##      This is the load-bearing one. A revive costs your teammate ~2 seconds of
##      standing still under pressure; HAUNT is how the ghost BUYS those 2 seconds.
##      The loop becomes: go down -> fly to your friend -> blow the pack off them ->
##      they channel -> you are up. Both players are working the whole time, and the
##      dead one's contribution is legible to the living one.
##
## Zero damage on HAUNT is not timidity. A ghost that can kill is a ghost you would
## rather be, and the moment dying becomes a build the rule stops meaning anything.
##
## ══ THE LOOK — CHALK AND GRAPHITE, A DRAWING BEING RUBBED OUT ══════════════════
## It has to read INSTANTLY at 640x360 on a phone, from across the arena, while
## twelve other things are happening. So the read is carried by SHAPE AND MOTION,
## never by colour alone:
##   * the body itself goes pale + translucent (the pencil lifted off the page)
##   * a BROKEN CHALK RING orbits it — a dashed circle, rotating, that nothing else
##     in the game draws, so the silhouette is unique even at a glance
##   * an ERASER SMUDGE breathes underneath it, jittering like a rubbed pencil mark
##   * GRAPHITE MOTES lift off and fade upward — the drawing coming apart
## The ring is the primary read; the smudge and motes are the flavour that makes it
## chalk-and-graphite rather than a generic blue ghost.
##
## ══ AUTOLOAD-FREE ON PURPOSE ═══════════════════════════════════════════════════
## `enter()` / `exit()` are static and are named from `Hero`, `Net` and the test
## suite. Autoloads are NOT registered under `--script`, and naming one inside a
## static function is a COMPILE error that fails the whole dependency chain and
## reports as an unrelated missing method. So nothing in this file touches `Sfx`,
## `Juice`, `Tuning` or `Net` — sound and hit-stop stay at the call sites in `Hero`.

## Joined by the HERO BODY (not by this node) while it is a ghost, so `Revive` can
## ask `get_nodes_in_group("ghost")` for something to pick up without walking the
## tree or importing `Hero`.
const GHOST_GROUP: StringName = &"ghost"
## Child node name, so `enter` is idempotent and `exit` can find its own work.
const NODE_NAME: StringName = &"GhostForm"

## ⚠ THE MORTAL GROUP IS A LITERAL, NOT `SpellCaster.MORTAL_GROUP`, and for the same
## reason `TouchControls` duplicates the handoff group name: naming that class here
## would drag its compile graph — and the autoloads inside it — into a file that has
## to survive `--script`. `tools/slice_test_ghost_revive.gd` asserts the two agree.
const MORTAL_GROUP: StringName = &"mortal"

## What the body's rig fades to. Pale graphite, well under half opacity: present
## enough to steer, transparent enough that nobody mistakes it for a live fighter.
const RIG_TINT: Color = Color(0.72, 0.76, 0.88, 0.34)

## --- the broken chalk ring (the primary read) ---
const RING_RADIUS: float = 21.0
const RING_DASHES: int = 9
const RING_DASH_ARC: float = 0.24        # radians of ring drawn per dash
const RING_WIDTH: float = 2.2
const RING_SPIN: float = 1.15            # rad/s
const RING_COLOR: Color = Color(0.93, 0.95, 1.0, 0.85)

## --- the eraser smudge ---
const SMUDGE_BLOBS: int = 5
const SMUDGE_RADIUS: float = 15.0
const SMUDGE_COLOR: Color = Color(0.55, 0.58, 0.66, 0.20)

## --- graphite motes lifting off ---
const MOTE_COUNT: int = 7
const MOTE_RISE: float = 34.0            # px travelled over a full life
const MOTE_LIFE: float = 1.5
const MOTE_COLOR: Color = Color(0.28, 0.30, 0.38, 0.85)

## --- the HAUNT gust (drawn here, ruled by Hero) ---
const HAUNT_TIME: float = 0.36
const HAUNT_COLOR: Color = Color(0.95, 0.97, 1.0, 1.0)

## Where the body's centre of mass reads, in the hero's local space. The collision
## box is centred on the origin; the drawn figure sits a little above it.
const BODY_CENTRE: Vector2 = Vector2(0.0, -6.0)

var _phase: float = 0.0
## Per-mote {offset, phase, speed} — seeded once so the drift is steady rather than
## reshuffling every frame.
var _motes: Array[Dictionary] = []
## Countdown of the HAUNT gust ring; 0 = not gusting.
var _haunt: float = 0.0
var _haunt_radius: float = 0.0

# --- what `exit` puts back ---
var _saved_layer: int = -1
var _saved_groups: Array[StringName] = []
var _saved_rig_modulate: Color = Color(1, 1, 1, 1)
var _had_rig: bool = false


# ══════════════════════════════════════════════════════════════════ lifecycle
## Put `hero` into ghost form and return the node that draws it. Idempotent: a hero
## that is already a ghost gets its existing node back rather than a second one.
##
## What this actually changes, and why each one is load-bearing:
##   * LEAVES `mortal` + the faction team group. `Hero.take_damage` already returns
##     early while downed, so this is belt-and-braces — but immunity and being
##     UNTARGETABLE are different things. A ghost still in `mortal` soaks a friendly
##     Meteor's radius scan, eats its hit-stop and its damage number, and reads on
##     screen as a body that is being hit. `DestructibleProp._shatter` is the
##     precedent: leave the groups in the same breath as dying.
##   * KEEPS `hero`. That group is identity, and ~40 places read it — the camera's
##     fit-all framing, the party-wipe verdict, `Net.hero_for_peer`. Dropping it to
##     "clean up" is the exact group-drift trap this codebase has been bitten by
##     twice, and it would make a ghost invisible to the thing that ends the run.
##   * ZEROES `collision_layer`, keeping the mask. Nothing can detect the body, so
##     projectiles and pickup areas pass through — but the mask still holds it
##     inside the arena walls, so a ghost cannot drift off into the void.
static func enter(hero: Node) -> GhostForm:
	if hero == null or not is_instance_valid(hero):
		return null
	var existing: Node = hero.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing is GhostForm:
		return existing as GhostForm
	var g := GhostForm.new()
	g.name = String(NODE_NAME)
	g.z_index = -1        # behind the (now faded) figure: the smudge is UNDER the pencil
	g._saved_layer = int(hero.get(&"collision_layer"))
	# Leave every group that makes this body a legal target, remembering exactly
	# which ones were actually left so `exit` restores this hero's arrangement and
	# not a guess about it (a co-op hero has a faction group; a solo one does not).
	for grp: StringName in [MORTAL_GROUP, _faction_of(hero)]:
		if grp != &"" and hero.is_in_group(grp):
			hero.remove_from_group(grp)
			g._saved_groups.append(grp)
	hero.set(&"collision_layer", 0)
	hero.add_to_group(GHOST_GROUP)
	var rig: Node = hero.get_node_or_null(^"Rig")
	if rig is CanvasItem:
		g._had_rig = true
		g._saved_rig_modulate = (rig as CanvasItem).modulate
		(rig as CanvasItem).modulate = RIG_TINT
	hero.add_child(g)
	return g


## Undo `enter`. Safe to call on a hero that is not a ghost (that is the normal
## answer on a peer that never saw the down).
static func exit(hero: Node) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	hero.remove_from_group(GHOST_GROUP)
	var node: Node = hero.get_node_or_null(NodePath(String(NODE_NAME)))
	if not (node is GhostForm):
		return
	var g := node as GhostForm
	for grp: StringName in g._saved_groups:
		if not hero.is_in_group(grp):
			hero.add_to_group(grp)
	if g._saved_layer >= 0:
		hero.set(&"collision_layer", g._saved_layer)
	if g._had_rig:
		var rig: Node = hero.get_node_or_null(^"Rig")
		if rig is CanvasItem:
			(rig as CanvasItem).modulate = g._saved_rig_modulate
	hero.remove_child(g)
	g.queue_free()


## True when this body is currently wearing ghost form. Asked by `Revive` and by the
## party-wipe verdict, so it is derived from the node rather than from a flag that
## could disagree with what is on screen.
static func is_ghosted(hero: Node) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	return hero.get_node_or_null(NodePath(String(NODE_NAME))) is GhostForm


## The hero's team group, or `&""`. Read through `get()` and type-checked, because
## `get()` on an absent property returns a null Variant and casting that ABORTS the
## enclosing function — the bug that silently killed the spell handoff.
static func _faction_of(hero: Node) -> StringName:
	var f: Variant = hero.get(&"faction_group")
	if f is StringName:
		return f as StringName
	if f is String:
		return StringName(f as String)
	return &""


# ══════════════════════════════════════════════════════════════════════ visuals
func _ready() -> void:
	_seed_motes()
	set_process(true)


func _seed_motes() -> void:
	_motes.clear()
	for i: int in MOTE_COUNT:
		_motes.append({
			"x": randf_range(-11.0, 11.0),
			"t": randf(),                        # 0..1 through its life, staggered
			"speed": randf_range(0.7, 1.3),
			"size": randf_range(0.9, 1.9),
		})


func _process(delta: float) -> void:
	_phase += delta
	for m: Dictionary in _motes:
		m["t"] = fposmod(float(m["t"]) + delta * float(m["speed"]) / MOTE_LIFE, 1.0)
	if _haunt > 0.0:
		_haunt = maxf(_haunt - delta, 0.0)
	queue_redraw()


## Fire the HAUNT gust ring. Called by `Hero._ghost_haunt` on the owner AND by the
## replayed copy on every other peer, so the shove is never invisible magic.
func gust(radius: float) -> void:
	_haunt = HAUNT_TIME
	_haunt_radius = maxf(radius, 8.0)


## Convenience for call sites that hold the HERO rather than this node. Returns
## false when the hero is not a ghost, which is a normal answer.
static func gust_on(hero: Node, radius: float) -> bool:
	var node: Node = null if hero == null else hero.get_node_or_null(NodePath(String(NODE_NAME)))
	if not (node is GhostForm):
		return false
	(node as GhostForm).gust(radius)
	return true


func _draw() -> void:
	_draw_smudge()
	_draw_motes()
	_draw_broken_ring()
	if _haunt > 0.0:
		_draw_gust()


## The rubbed-pencil mark: overlapping soft discs that jitter and breathe. Drawn
## first (furthest back) so the faded figure sits inside it.
func _draw_smudge() -> void:
	var breathe: float = 0.86 + 0.14 * sin(_phase * 2.1)
	for i: int in SMUDGE_BLOBS:
		var a: float = TAU * float(i) / float(SMUDGE_BLOBS) + _phase * 0.35
		var wobble: float = 4.5 + 2.0 * sin(_phase * 3.3 + float(i))
		var at: Vector2 = BODY_CENTRE + Vector2.from_angle(a) * wobble
		draw_circle(at, SMUDGE_RADIUS * breathe * (0.7 + 0.3 * float(i % 2)),
			SMUDGE_COLOR, true, -1.0, true)


## Graphite lifting off the page.
func _draw_motes() -> void:
	for m: Dictionary in _motes:
		var t: float = float(m["t"])
		var at: Vector2 = BODY_CENTRE + Vector2(
			float(m["x"]) + 3.0 * sin(_phase * 1.7 + float(m["x"])),
			-MOTE_RISE * t)
		# Fades in fast, out slow — a speck that pops into existence reads as noise.
		var alpha: float = clampf(minf(t * 6.0, (1.0 - t) * 1.8), 0.0, 1.0)
		draw_circle(at, float(m["size"]),
			Color(MOTE_COLOR.r, MOTE_COLOR.g, MOTE_COLOR.b, MOTE_COLOR.a * alpha),
			true, -1.0, true)


## THE PRIMARY READ. A dashed circle, spinning, that nothing else in the game draws.
## Bright and thin so it survives the post-process grade and a small screen.
func _draw_broken_ring() -> void:
	var pulse: float = 0.72 + 0.28 * sin(_phase * 3.4)
	var col := Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, RING_COLOR.a * pulse)
	var step: float = TAU / float(RING_DASHES)
	for i: int in RING_DASHES:
		var from: float = step * float(i) + _phase * RING_SPIN
		# Alternate dashes ride slightly wider, so the ring reads as coming apart
		# rather than as a tidy dotted circle.
		var r: float = RING_RADIUS + (1.8 if (i % 2) == 0 else -1.4)
		draw_arc(BODY_CENTRE, r, from, from + RING_DASH_ARC, 4, col, RING_WIDTH, true)


## The HAUNT gust: a hard white chalk shockwave snapping outward to its real radius,
## so the shove and the drawing of the shove are the same size.
func _draw_gust() -> void:
	var t: float = 1.0 - (_haunt / HAUNT_TIME)          # 0 -> 1
	var r: float = _haunt_radius * (0.25 + 0.75 * sqrt(t))
	var a: float = (1.0 - t) * 0.9
	draw_arc(BODY_CENTRE, r, 0.0, TAU, 40,
		Color(HAUNT_COLOR.r, HAUNT_COLOR.g, HAUNT_COLOR.b, a), 2.6, true)
	draw_arc(BODY_CENTRE, r * 0.72, 0.0, TAU, 32,
		Color(HAUNT_COLOR.r, HAUNT_COLOR.g, HAUNT_COLOR.b, a * 0.45), 1.4, true)
