class_name MirrorImage
extends Node2D
## MIRROR IMAGE — Tier 2 floor pickup. A second you, one beat behind, casting what
## you cast from wherever it happens to be standing. It is on nobody's side.
##
## ⚠ IT MIMICS CASTS, NOT INPUTS, and that distinction is the whole implementation.
## Recording the player's buttons would need a hook inside `Hero`, which this agent
## does not own. Instead the clone listens at `SpellCaster.cast()` — the one seam
## every spell in the game already passes through — via `echo()`. Consequences,
## all of them good:
##   * it works for BOTS and for a future co-op peer with no extra code, because
##     they cast through the same function;
##   * it repeats what the player actually DID rather than a re-simulation of what
##     they pressed, so there is no divergence to keep in sync;
##   * a spell added tomorrow is mirrored on the day it is added.
##
## THE FRIENDLY FIRE IS REAL AND IS THE POINT. The clone casts with ITSELF as the
## caster, not with the hero. `SpellTargets` excludes a spectacle's own caster from
## its scans, so a spell cast by the clone excludes the CLONE — a node that is not
## in the `mortal` group and was never a target anyway — and therefore happily
## catches the player who summoned it. Casting as the hero instead would have made
## the clone's spells politely refuse to touch their owner, which is the one thing
## this spell must not do.
##
## WHAT IT WILL NOT REPEAT, and why (`_MUTE`):
##   * `mirror_image` itself — a clone that summons clones is an allocation bug
##     wearing a spell's hat.
##   * every Tier 3 `CATACLYSM` — those are charge-limited boss drops, and echoing
##     one would hand the player a second cast of a one-charge spell for free.
##     Charges are spent by the HERO at the dispatcher; the echo never spends any.

## Positional samples per second. The clone replays a delayed transform, so this is
## the resolution of its path — low enough to be cheap, high enough that a dash
## does not teleport it. UNTESTED FEEL GUESS.
const SAMPLE_HZ: float = 30.0
## How often a rig afterimage is stamped at the clone's position. The clone has no
## rig of its own: it borrows the HERO's current pose and draws it where the clone
## is, which is both cheaper than a second rig and exactly right — a mirror image
## should be posed like you.
const GHOST_INTERVAL: float = 0.085
const GHOST_FADE: float = 0.20
## Clone tint. Arcane violet at low alpha so it never gets mistaken for a second
## player at a glance, which would be the worst possible misread in co-op.
const CLONE_TINT: Color = Color(0.72, 0.55, 1.0, 0.55)

## Spell ids and kinds the clone refuses to repeat. See the header.
const MUTE_IDS: Array[String] = ["mirror_image"]

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.ARCANE
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

var _life: float = 9.0
var _delay: float = 1.0
var _elapsed: float = 0.0
var _color: Color = CLONE_TINT
## Ring buffer of {t, pos} samples of the hero's position.
var _trail: Array[Dictionary] = []
var _sample_accum: float = 0.0
var _ghost_accum: float = 0.0
## Pending echoes: {at (seconds on _elapsed), spell, target, color, fx}.
var _pending: Array[Dictionary] = []
## Where the clone is drawn/casts from this frame.
var _clone_pos: Vector2 = Vector2.ZERO


func hex(caster: Node, origin: Vector2, _target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_life = maxf(spell.length, 1.0)
	_delay = clampf(spell.reach, 0.15, 4.0)
	_color = Color(color.r, color.g, color.b, CLONE_TINT.a)
	_clone_pos = origin
	global_position = Vector2.ZERO
	# The clone must be BEHIND the hero in the frame so the position it samples is
	# the hero's settled one, not a half-integrated mid-frame value.
	process_priority = 150
	process_physics_priority = 150
	SpellSigil.open(self, origin, color, 1.0, false, Vector2.RIGHT, true, 0.12, 0.4)
	SpellDrops.sfx("cast_arcane", -4.0, 0.08, 1.3)
	queue_redraw()


## THE LISTENER. Called from `SpellCaster.cast()` for every spell any caster
## throws; each live clone owned by that caster queues its own delayed repeat.
##
## Static + tree-scanned rather than signal-based on purpose: a signal would need
## the hero to know clones exist, which is the coupling this whole design avoids.
static func echo(caster: Node, spell: SpellDef, target: Vector2, color: Color,
		fx: String, ctx: Node) -> void:
	if caster == null or spell == null or ctx == null or not ctx.is_inside_tree():
		return
	if MUTE_IDS.has(spell.id) or spell.kind == SpellDef.Kind.CATACLYSM:
		return
	var tree: SceneTree = ctx.get_tree()
	if tree == null:
		return
	var want: int = caster.get_instance_id()
	for m: Node in tree.get_nodes_in_group(&"mirror_image"):
		if not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		var owner_node: Variant = m.get(&"caster_node")
		if owner_node == null or not is_instance_valid(owner_node as Object):
			continue
		if (owner_node as Object).get_instance_id() != want:
			continue
		m.call(&"queue_echo", spell, target, color, fx)


func _ready() -> void:
	add_to_group(&"mirror_image")


func queue_echo(spell: SpellDef, target: Vector2, color: Color, fx: String) -> void:
	_pending.append({"at": _elapsed + _delay, "spell": spell, "target": target,
		"color": color, "fx": fx})


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _life or not _owner_ok():
		_dissolve()
		return
	_sample(delta)
	_clone_pos = _delayed_position()
	_fire_due(delta)
	_stamp_ghost(delta)
	queue_redraw()


func _owner_ok() -> bool:
	return caster_node != null and is_instance_valid(caster_node) \
		and not caster_node.is_queued_for_deletion() and caster_node is Node2D


func _sample(delta: float) -> void:
	_sample_accum += delta
	if _sample_accum < 1.0 / SAMPLE_HZ:
		return
	_sample_accum = 0.0
	_trail.append({"t": _elapsed, "pos": (caster_node as Node2D).global_position})
	# Trim anything older than the delay window — the buffer is a delay line, not
	# a recording, and an untrimmed one grows for the whole nine seconds.
	while _trail.size() > 2 and float(_trail[0]["t"]) < _elapsed - _delay - 0.5:
		_trail.pop_front()


## Where the hero was `_delay` seconds ago, interpolated between the two samples
## that straddle it. Falls back to the oldest sample early in the clone's life,
## when there is not yet a full delay's worth of history — so the clone starts
## standing where you were when you cast it rather than snapping in from nowhere.
func _delayed_position() -> Vector2:
	if _trail.is_empty():
		return _clone_pos
	var want: float = _elapsed - _delay
	if want <= float(_trail[0]["t"]):
		return _trail[0]["pos"]
	for i: int in range(_trail.size() - 1, 0, -1):
		var a: Dictionary = _trail[i - 1]
		var b: Dictionary = _trail[i]
		if float(a["t"]) <= want and want <= float(b["t"]):
			var span: float = maxf(float(b["t"]) - float(a["t"]), 0.0001)
			return (a["pos"] as Vector2).lerp(b["pos"], (want - float(a["t"])) / span)
	return _trail[_trail.size() - 1]["pos"]


## Cast anything whose delay has elapsed, FROM THE CLONE and AS the clone.
func _fire_due(_delta: float) -> void:
	var still: Array[Dictionary] = []
	for e: Dictionary in _pending:
		if _elapsed < float(e["at"]):
			still.append(e)
			continue
		var spell: SpellDef = e["spell"] as SpellDef
		if spell == null:
			continue
		# The clone aims along the SAME VECTOR the player did, re-based to where the
		# clone is standing. Copying the absolute target point instead would make two
		# spells land on the same spot, which looks like a double-cast bug rather than
		# like a second caster.
		var offset: Vector2 = (e["target"] as Vector2) - _origin_at_cast(e)
		SpellCaster.cast(spell, get_parent(), _clone_pos, _clone_pos + offset,
			e["color"], String(e["fx"]), self, StringName(target_group))
		CombatVfx.spawn_burst(get_parent(), _clone_pos, Color(_color.r, _color.g, _color.b, 0.8),
			Color(_color.r, _color.g, _color.b, 0.0), 8, 0.3, 40.0, 120.0, 0.9, 2.2)
	_pending = still


## Where the hero stood when the mirrored cast was made — i.e. the clone's own
## current position minus nothing, because the clone IS the hero delayed. Using the
## clone's position at fire time is exactly right: the aim vector was measured from
## the hero's position at cast time, and the clone is that position, `_delay` later.
func _origin_at_cast(_e: Dictionary) -> Vector2:
	return _delayed_position()


## Borrow the hero's CURRENT rig pose and stamp it at the clone's position. The rig
## is duck-typed: a caster without one (a bot stub, a capture-tool Node2D) simply
## gets the fallback silhouette in `_draw`.
func _stamp_ghost(delta: float) -> void:
	_ghost_accum += delta
	if _ghost_accum < GHOST_INTERVAL:
		return
	_ghost_accum = 0.0
	var rig: Variant = caster_node.get(&"rig")
	if rig == null or not (rig is Node2D) or not is_instance_valid(rig as Object):
		return
	var rig2: Node2D = rig as Node2D
	if not rig2.has_method(&"_compute_pose"):
		return
	var ghost: Node2D = (load("res://scripts/combat/RigGhost.gd") as GDScript).new()
	ghost.set(&"pose", rig2.call(&"_compute_pose"))
	var equip: Variant = rig2.get(&"equipment")
	ghost.set(&"equipment_slots", (equip as Dictionary).duplicate() if equip is Dictionary else {})
	ghost.set(&"fig_height", rig2.get(&"height"))
	ghost.set(&"base_color", _color)
	ghost.set(&"fade_time", GHOST_FADE)
	get_parent().add_child(ghost)
	ghost.global_transform = rig2.global_transform
	ghost.global_position = _clone_pos + (rig2.global_position - (caster_node as Node2D).global_position)
	ghost.z_index = 0


func _dissolve() -> void:
	CombatVfx.spawn_burst(get_parent(), _clone_pos, Color(_color.r, _color.g, _color.b, 0.8),
		Color(_color.r, _color.g, _color.b, 0.0), 16, 0.45, 60.0, 180.0, 1.0, 2.8)
	queue_free()


## The clone's own mark — a shimmer ring at its feet plus a floating sigil dot.
## The rig ghosts above carry the FIGURE; this carries the "that one is not real"
## read, and it is what keeps the clone legible when the ghost pool is saturated.
func _draw() -> void:
	var beat: float = 0.5 + 0.5 * sin(_elapsed * 5.0)
	var left: float = clampf(1.0 - _elapsed / _life, 0.0, 1.0)
	draw_arc(_clone_pos + Vector2(0.0, 3.0), 16.0 + 3.0 * beat, 0.0, TAU, 26,
		Color(_color.r, _color.g, _color.b, 0.5), 2.0, true)
	draw_arc(_clone_pos + Vector2(0.0, 3.0), 21.0, -PI * 0.5, -PI * 0.5 + TAU * left,
		30, Color(_color.r, _color.g, _color.b, 0.75), 2.4, true)
	# Fallback silhouette for a caster with no rig (capture tools, stubs): a plain
	# translucent figure, so this file is never invisible in a harness.
	if caster_node == null or caster_node.get(&"rig") == null:
		draw_line(_clone_pos, _clone_pos + Vector2.UP * 24.0,
			Color(_color.r, _color.g, _color.b, 0.6), 3.0, true)
		draw_circle(_clone_pos + Vector2.UP * 30.0, 6.0,
			Color(_color.r, _color.g, _color.b, 0.6), true, -1.0, true)
