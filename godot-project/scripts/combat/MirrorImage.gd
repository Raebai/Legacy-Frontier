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
##
## ── THE MAKER'S REPORT: "mirror should at least cast what I cast" ─────────────
## They were right, and there were TWO reasons it read as a clone that just stood
## there. Both are fixed here; both were invisible from the unit test, which only
## ever asserted that `echo()` puts an entry in `_pending`.
##
## ⚠ REASON 1 — THE RE-BASED AIM CANCELLED ITSELF OUT. The intent above ("aims
## along the same vector, re-based to where the clone stands") was never what the
## code did. `_origin_at_cast()` answered `_delayed_position()`, which is BY
## DEFINITION the point the clone is standing on this frame — so `target - origin`
## added back to the clone's position resolved to the ORIGINAL absolute target,
## every time, exactly. The copy therefore landed pixel-for-pixel on top of the
## player's own cast, from the spot the player cast it, one second late: the
## "double-cast bug" read this file's own comment claims to avoid. It is fixed by
## recording where the OWNER actually stood when the cast happened (`from`, stamped
## at queue time) instead of recomputing it from the clone, which cannot answer a
## question about a moment it is a delayed copy of.
##
## ⚠ REASON 2 — A CLONE STANDING INSIDE YOU IS NOT A SECOND CASTER. It samples
## where you WERE, so a player who is not moving is a player standing on their own
## clone, and every copy erupts out of the player's own body. `MIN_SEPARATION`
## pushes the clone clear HORIZONTALLY ONLY — the delayed Y is a place the hero
## genuinely stood, so it is on a floor, and a radial push would hang the clone in
## mid-air over a pit for the sake of a few pixels.
##
## ── IT FIGHTS WHILE IT IS OUT ────────────────────────────────────────────────
## With a 1 s echo delay, a 9 s life and every other spell in the kit on its own
## cooldown, the clone spent most of its life doing nothing at all. So between
## echoes it throws the basic bolt at the nearest mob (`_lash`).
##
## The bolt is `Spell.tscn` rather than a bespoke effect on purpose: it already
## travels, clashes, is deflectable, is dodged by smart enemies and carries the
## QUICK reaction weight. A hand-rolled hitscan would be a second scheme for all
## five of those, and a worse one.
##
## ⚠ WHO IT SHOOTS AT vs WHO THE SHOT CAN HURT — these are DIFFERENT QUESTIONS and
## answering them with one group is the bug. It AIMS at the owner's faction
## (`hostile_group`) and never at a hero, which is the identical asymmetry
## `Hero._nearest_enemy_in_melee_range` and `_apply_aim_assist` are documented on:
## friendly fire means you CAN be hit, never that the game steers something into
## you. The bolt's DAMAGE scan is this clone's `target_group` — `mortal` under
## friendly fire — so walking into a bolt the clone threw at a mob still hurts,
## which keeps "it is on nobody's side" true where it should be true (position)
## and false where it would just be griefing (target selection).
##
## Rejected: making the clone hunt the player like a duel opponent. That is a
## different spell, and it makes the one you cast on purpose the thing that kills
## you — unreadable, not funny.
##
## ── BALANCE ──────────────────────────────────────────────────────────────────
## ⚠ ECHOED COPIES ARE HALVED (`ECHO_DAMAGE_SCALE`). A clone that free-casts the
## whole kit at full power is flatly a x2 damage button for 9 s, which no control
## slot should be. Halving makes the window ~1.5x and keeps the spell's value where
## its name is — a second body in a second place, drawing fire and covering an
## angle you are not on — rather than in the damage number.
##
## ⚠ THE SCALE IS APPLIED TO A DUPLICATE, NEVER IN PLACE. A `SpellDef` is a SHARED
## resource out of the catalog: the same object the hero, every bot and the drop
## table read. Scaling it where it lies would permanently halve that spell for
## everyone, compounding once per echo. This is the same trap
## `SpellCaster._blood_pacted` exists to document, and it is solved the same way.

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

## What an echoed copy hits for, as a fraction of the real cast. See the BALANCE
## note in the header for why this is not 1.0. UNTESTED FEEL GUESS — this is the
## dial to turn if the clone reads as either a damage button or a light show.
const ECHO_DAMAGE_SCALE: float = 0.5

## ⚠ HORIZONTAL ONLY — see REASON 2 in the header. How far clear of the owner the
## clone is held when the delayed path would otherwise put it inside them. Roughly
## one body width, so the two silhouettes read as two people rather than one
## smeared one. UNTESTED FEEL GUESS.
const MIN_SEPARATION: float = 34.0

# ------------------------------------------------------------- THE IDLE ATTACK
## The clone's own basic cast. Reused rather than re-created — see the header.
const BOLT_SCENE_PATH: String = "res://scenes/combat/Spell.tscn"
## Seconds between unprompted bolts. Deliberately SLOWER than a hero's own cast
## cadence: the mirror's headline act is the copy, and filler that out-rates the
## thing it is filling for would bury it. UNTESTED FEEL GUESS.
const LASH_INTERVAL: float = 0.9
## How far the clone will pick a mark. Short of a hero's own reach, so it covers
## the ground near where you WERE rather than sniping across the whole floor.
const LASH_RANGE: float = 460.0
## Half a hero's base bolt (18). At `LASH_INTERVAL` that is ~10 dps — present
## enough to finish a chip-damaged mob, far too little to be the reason you cast
## this. UNTESTED FEEL GUESS.
const LASH_DAMAGE: int = 9
## Where on the clone the bolt leaves from. The clone has no rig of its own and
## `_clone_pos` is its FEET, so a bolt spawned there skims the floor and eats the
## first crate in its path instead of the mob it was aimed at.
const LASH_MUZZLE_RISE: float = 18.0

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
## Pending echoes: {at (seconds on _elapsed), spell, from, target, color, fx}.
## `from` is where the OWNER stood at cast time, and it is the whole of the aim
## fix — see REASON 1 in the header for why it cannot be recomputed later.
var _pending: Array[Dictionary] = []
## Where the clone is drawn/casts from this frame.
var _clone_pos: Vector2 = Vector2.ZERO
var _lash_accum: float = 0.0


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


## Take a copy of a cast that just happened. Two things are decided HERE rather
## than at fire time, and both have to be:
##   `from`  — where the owner was standing. A second from now the owner has moved
##             and the clone IS that old position, so nothing at fire time can
##             still answer the question.
##   the scaled duplicate — asked once per queued copy instead of once per frame it
##             sits in the queue, and never against the shared catalog resource.
func queue_echo(spell: SpellDef, target: Vector2, color: Color, fx: String) -> void:
	var from: Vector2 = _clone_pos
	if is_instance_valid(caster_node) and caster_node is Node2D:
		from = (caster_node as Node2D).global_position
	_pending.append({"at": _elapsed + _delay, "spell": _halved(spell), "from": from,
		"target": target, "color": color, "fx": fx})


## `spell` at `ECHO_DAMAGE_SCALE`, as a THROWAWAY DUPLICATE.
##
## ⚠ NEVER MUTATE THE ARGUMENT. See the BALANCE note in the header: a `SpellDef` is
## the shared catalog object, so an in-place scale halves that spell permanently for
## every caster in the game.
##
## Returns the original untouched when there is nothing to scale — a control or
## utility spell with `damage == 0` allocates nothing, which is most of what an
## Arcanist throws.
func _halved(spell: SpellDef) -> SpellDef:
	if spell == null or spell.damage <= 0 or ECHO_DAMAGE_SCALE >= 1.0:
		return spell
	var copy: SpellDef = spell.duplicate() as SpellDef
	# Floor of 1: a scaled-to-zero copy would look like a spell that missed rather
	# than one that landed weakly, which is the worse of the two lies.
	copy.damage = maxi(1, int(round(float(spell.damage) * ECHO_DAMAGE_SCALE)))
	return copy


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _life or not _owner_ok():
		_dissolve()
		return
	_sample(delta)
	_clone_pos = _separated(_delayed_position())
	_fire_due(delta)
	_lash(delta)
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
	var fired: bool = false
	for e: Dictionary in _pending:
		if _elapsed < float(e["at"]):
			still.append(e)
			continue
		var spell: SpellDef = e["spell"] as SpellDef
		if spell == null:
			continue
		# THE AIM VECTOR THE OWNER ACTUALLY CHOSE, thrown from wherever the clone is
		# standing — so the copy is a genuinely different shot rather than a second
		# print of the same one. Measured against the owner's recorded position, never
		# recomputed from the clone: see REASON 1 in the header for why recomputing it
		# resolves back to the original target every single time.
		var offset: Vector2 = (e["target"] as Vector2) - (e["from"] as Vector2)
		SpellCaster.cast(spell, get_parent(), _clone_pos, _clone_pos + offset,
			e["color"], String(e["fx"]), self, StringName(target_group))
		CombatVfx.spawn_burst(get_parent(), _clone_pos, Color(_color.r, _color.g, _color.b, 0.8),
			Color(_color.r, _color.g, _color.b, 0.0), 8, 0.3, 40.0, 120.0, 0.9, 2.2)
		fired = true
	_pending = still
	if fired:
		# The copy just landed, so the filler waits a full beat before speaking over
		# it. Without this the bolt can leave on the same frame as an echoed ult.
		_lash_accum = 0.0


## `p` (the delayed path point) held clear of the owner's body — see REASON 2 in the
## header for why this exists and why the push is horizontal.
##
## The fallback matters more than it looks: a player who has not moved AT ALL leaves
## a zero-length separation vector with no side to it, and picking a side at random
## per frame would make the clone strobe from shoulder to shoulder. Behind the
## owner's facing is a stable answer and reads as "over your shoulder".
func _separated(p: Vector2) -> Vector2:
	if not is_instance_valid(caster_node) or not (caster_node is Node2D):
		return p
	var here: Vector2 = (caster_node as Node2D).global_position
	var dx: float = p.x - here.x
	if absf(dx) >= MIN_SEPARATION:
		return p
	var side: float = signf(dx)
	if absf(dx) < 0.5:
		side = -1.0  # the stable default, used when the owner publishes no facing
		var f: Variant = caster_node.get(&"facing")
		if f is Vector2:
			var face: Vector2 = f
			if absf(face.x) > 0.01:
				side = -signf(face.x)
	# ⚠ AND THE PUSHED POINT IS THE ONE PLACE THIS FUNCTION INVENTS, SO IT IS THE ONE
	# PLACE THAT CAN BE INSIDE A WALL.
	#
	# Maker: "make sure the arcanists mirror doesnt get stuck in a wall or something".
	#
	# The header above argues, correctly, that the DELAYED position is always safe:
	# it is somewhere the hero genuinely stood, so it is on a floor and it is not in
	# geometry. But the separation push is not that point — it is `here.x ± 96`, a
	# coordinate nobody has ever occupied. Cast with your back to a riser, or in the
	# corridor between two terraces, and the clone is placed straight into the rock.
	#
	# Probed rather than assumed: try the chosen side, and if the segment from the
	# owner to it is blocked, take the other one. If BOTH are blocked — a body wedged
	# in a gap narrower than two separations — fall back to the delayed position
	# untouched, which is the safe point the header describes. A clone briefly
	# overlapping its owner is a cosmetic problem; a clone inside a wall is a body
	# that cannot be hit and cannot leave.
	var wanted: Vector2 = Vector2(here.x + side * MIN_SEPARATION, p.y)
	if _clear_of_world(here, wanted):
		return wanted
	var flipped: Vector2 = Vector2(here.x - side * MIN_SEPARATION, p.y)
	if _clear_of_world(here, flipped):
		return flipped
	return p


## Is the straight line from the owner to `to` free of solid world?
##
## Uses the same `SpellWorld.first_solid` seam every spectacle probes terrain with,
## and excludes the caster so its own body is never the thing that blocks the test.
func _clear_of_world(from: Vector2, to: Vector2) -> bool:
	var r: Dictionary = SpellWorld.first_solid(from, to,
		SpellWorld.rids([caster_node]), self)
	return not bool(r.get("hit", false))


# ------------------------------------------------------------- THE IDLE ATTACK
## What the clone does with the rest of its nine seconds. See the header.
##
## ⚠ SUPPRESSED WHILE A COPY IS INBOUND, and the accumulator is held at zero rather
## than merely not-fired: a queued echo is the thing the player cast this spell FOR,
## and a bolt that leaves during the wind-up steals the read from it.
func _lash(delta: float) -> void:
	if not _pending.is_empty():
		_lash_accum = 0.0
		return
	_lash_accum += delta
	if _lash_accum < LASH_INTERVAL:
		return
	var mark: Node2D = _nearest_mob()
	if mark == null:
		return  # nothing to shoot: stay armed, so the first mob to walk up is met
	_lash_accum = 0.0
	_fire_bolt(mark)


## The nearest thing the OWNER counts as an enemy. Never `mortal` — the header's
## aim-vs-damage split is the whole point, and this is the half that must not see a
## hero.
##
## `hostile_group` is duck-typed off the owner rather than assumed, so a bot-driven
## hero (whose faction is the other TEAM, not "enemy") gets a clone that fights the
## same people it does. A caster that publishes no faction — a capture-tool stub, a
## playground figure — falls back to the plain monster group.
func _nearest_mob() -> Node2D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var faction: StringName = &"enemy"
	var f: Variant = caster_node.get(&"hostile_group")
	if f is StringName or f is String:
		faction = StringName(f)
	# `self` as ctx is what excludes the OWNER from the scan (SpellTargets reads
	# `caster_node` off it), and line of sight is left at its default: a clone that
	# shoots the wall it is standing behind is worse than one that waits.
	return SpellTargets.nearest(_clone_pos, LASH_RANGE,
		tree.get_nodes_in_group(faction), [], self)


## Throw the basic bolt at `mark`.
##
## ⚠ `set_hostile_group` MUST COME AFTER `add_child`. It is a method and not a field
## write precisely because it also opens a collision-mask bit that `_ready()` (which
## runs on add) would otherwise stamp over — a bolt that misses that bit passes clean
## through its target with damage code that looks perfectly correct.
##
## ⚠ THE BOLT INHERITS THIS CLONE'S `target_group`, WHICH IS WHAT MAKES CO-OP SAFE.
## A clone rebuilt on a remote peer is a picture of someone else's spell and is
## pointed at `Net.GHOST_GROUP` — the group nobody is in — so its bolts are disarmed
## by the same one substitution that disarms every other twin spectacle, with no
## flag for this file to declare or remember.
func _fire_bolt(mark: Node2D) -> void:
	var muzzle: Vector2 = _clone_pos + Vector2(0.0, -LASH_MUZZLE_RISE)
	# Aimed at the DRAWN head, not the node origin — the origin sits ~10 px below the
	# body you can see, which is the off-by-a-body-part `SpellTargets` exists to fix.
	var dir: Vector2 = SpellTargets.aim_point(mark) - muzzle
	if dir.length_squared() <= 1.0:
		return
	var scene: PackedScene = load(BOLT_SCENE_PATH) as PackedScene
	if scene == null:
		return
	var bolt: Node = scene.instantiate()
	get_parent().add_child(bolt)
	(bolt as Node2D).global_position = muzzle
	bolt.call(&"launch", dir.normalized())
	if bolt.has_method(&"set_element_color"):
		bolt.call(&"set_element_color", Color(_color.r, _color.g, _color.b, 1.0))
	bolt.set(&"element_id", element_id)
	bolt.set(&"damage", LASH_DAMAGE)
	# ⚠ THE CLONE IS THE CASTER, NOT THE HERO, and that is the same deliberate choice
	# the echoed copies make (see the header). Naming the hero here would arm the
	# bolt's "never damage your own caster" backstop on the one body this spell is
	# supposed to be indifferent to. Every reader of `caster` guards for validity, so
	# the clone expiring under a bolt still in flight is safe.
	bolt.set(&"caster", self)
	# Without this the filler bolt reports the default HEAVY weight and would trade
	# evenly in a clash against a committed spell.
	bolt.set(&"spell_tier", SpellTier.Tier.QUICK)
	bolt.call(&"set_hostile_group", StringName(target_group))
	CombatVfx.spawn_burst(get_parent(), muzzle, Color(_color.r, _color.g, _color.b, 0.7),
		Color(_color.r, _color.g, _color.b, 0.0), 5, 0.18, 50.0, 130.0, 0.6, 1.6)
	SpellDrops.sfx("cast_arcane", -12.0, 0.1, 1.55)  # quiet + high: filler, not a cast


## Borrow the hero's CURRENT rig pose and stamp it at the clone's position. The rig
## is duck-typed: a caster without one (a bot stub, a capture-tool Node2D) simply
## gets the fallback silhouette in `_draw`.
func _stamp_ghost(delta: float) -> void:
	_ghost_accum += delta
	if _ghost_accum < GHOST_INTERVAL:
		return
	_ghost_accum = 0.0
	# ⚠ THE CLONE OUTLIVES ITS CASTER BY DESIGN, so `caster_node` must be checked before
	# it is dereferenced at all — `.get()` on a freed object is its own fault, separate
	# from the ordering one below.
	if not is_instance_valid(caster_node):
		return
	var rig: Variant = caster_node.get(&"rig")
	if rig == null or not is_instance_valid(rig) or not (rig is Node2D):
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
