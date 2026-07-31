class_name RiftDagger
extends Node2D
## RIFT DAGGER — throw a dagger that STICKS where it lands, then press the same
## key again to tear yourself through space to it.
##
## The kit's first two-beat spell. Every other signature is fire-and-forget: you
## press, it resolves, the world forgets. This one leaves a physical object in the
## world for up to LIVE_TIME, visible to everyone, and then asks a second question
## — commit or don't. The dagger can stick in a wall, in a crate, or in a BODY
## that then walks off with it, so the destination is something that had to
## survive a flight rather than a point the cursor guaranteed.
##
## The recall press is routed through `try_recall()` rather than a second input
## binding: one slot, two meanings, which is what the mobile-first constraint
## costs us and also what makes the spell a decision instead of a combo.
##
## Counterplay is the strongest in the kit: parrying the dagger in flight severs
## the anchor (`_owner` is cleared), so the whole two-beat play is cancelled, not
## merely redirected. A dagger that has ALREADY been turned once cannot be turned
## again (`_reflected` is a one-shot, and the parry scan skips a reflected blade so
## it does not eat a guard press for nothing) — instead its hit is threaded through
## `SpellDeflect.resolve`, so a correctly-timed guard EATS the returned blade.
##
## Draws in world coordinates; the node itself parks at the arena origin.
##
## ── WORLD CONTRACT (docs/spell-world-contract.md) ────────────────────────────
## SPAWN.   The recall destination is vetted with `SpellWorld.is_blocked` before
##          the caster is moved: the blade plants itself IN walls by design, so
##          "arrive on the blade" would drop a body inside solid rock — the mirror
##          image of a meteor under the floor, and the same rule forbids both.
## TRAVEL.  Both the body test and the world test run against the segment JUST
##          TRAVELLED (`_prev` -> `_pos`), never a forward guess, so a 780 px/s
##          blade cannot tunnel through a thin wall or a thin enemy on a bad frame.
## IMPACT.  Every radius query goes through `SpellTargets`, which tests the DRAWN
##          silhouette (fixing the maker's "spells pass through heads") and drops
##          anything behind cover (fixing "spells get out of the radius").
##
## ⚠ ONE DELIBERATE EXEMPTION FROM THE SMASH RULE. Everywhere else a spell tears
## THROUGH destructible cover; this one does not. `first_solid` is called with
## `smash_destructibles = false`, because a thrown dagger is an OBJECT and the
## class docs already promise it "can stick in a wall, in a crate, or in a BODY".
## Planting in the crate is the fiction. What was MISSING is the other half of the
## maker's ask — "destroy what it can" — so the crate now takes the blade's damage
## at the exact face it was struck. Before this, a dagger that stuck in a crate
## dealt it precisely nothing: the old code stopped on the crate's layer-1 collider
## in the wall raycast and never reached the destructible loop below it.

const SPEED: float = 780.0          # slower than every beam — you can watch it come
const SPIN: float = 22.0            # rad/s tumble in flight
const HIT_RADIUS: float = 15.0
const LIVE_TIME: float = 4.0
const RECALL_TELL: float = 0.18     # the arrival telegraph — step off the dagger
const ARRIVE_FADE: float = 0.30
const ARRIVE_KNOCK: float = 260.0
const DROP_ARC: float = 0.25        # falls to the floor when it reaches max range
const DROP_GRAVITY: float = 2200.0
const DROP_DRIFT: float = 140.0
const BLADE_LEN: float = 20.0
const BLADE_HALF_W: float = 4.2
const GRIP_LEN: float = 9.0
const TRAIL_LENGTH: int = 5

# --- world-contract constants. ALL UNTESTED GUESSES: reasoning, not feel. -----

## How far outside a surface a rescued recall destination is pushed. Just enough
## that the arriving body is clear of the collider rather than kissing it, and it
## doubles as the probe radius for the legality test — a hero-sized destination is
## only legal if a hero-sized volume fits. Sibling reference: BlinkStrike's
## SURFACE_PAD is 8.0 for a blast CENTRE, which has no body; this is a little more
## generous because it is a body that has to stand there. UNTESTED GUESS.
const ARRIVE_CLEARANCE: float = 10.0

## How far down the whiffed dagger looks for a floor to plant itself in. Was a bare
## `400.0` inline; named because it is the number that decides whether a dagger
## thrown over a chasm finds the far ledge or is declared lost. UNTESTED GUESS.
const DROP_PROBE: float = 400.0

enum State { FLYING, STUCK, RECALLING, SPENT }

var element_id: int = Elements.Element.SHADOW

## The clash shelf this spell fights at (SpellTier.Tier), set by SpellCaster at
## cast time; also the dial deciding how hard the blade is to guard against — an
## ult only connects with the opening sliver of a parry window. Middle shelf when
## nobody sets it, which is how every un-adopted spectacle already behaves.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## WHO CAST THIS, under the name `SpellCaster._stamp` writes. Deliberately a second
## handle on the same node `_owner` already holds: `_owner` arrives as a positional
## ARGUMENT to `throw_dagger` (behaviour — whose recall this answers), while this is
## the uniform IDENTITY property every spectacle in the codebase publishes. The two
## mechanisms are documented on the TETHER arm of `SpellCaster.cast`, and until this
## line existed the stamp's write went nowhere (`set()` on an undeclared property is
## a silent no-op), which left the summoning sigil unable to find the caster's live
## wind-up circle to adopt.
var caster_node: Node = null

var _owner: Node = null
var _color: Color = Color(0.6, 0.35, 0.95)
var _range: float = 700.0
var _burst_r: float = 70.0
var _damage: int = 34
var _live_time: float = LIVE_TIME
var _cooldown: float = 4.5
var _effect: String = "shadow"

var _state: int = State.SPENT
var _pos: Vector2 = Vector2.ZERO
var _prev: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _travelled: float = 0.0
var _spin: float = 0.0
var _angle: float = 0.0             # the frozen blade angle once it lands
var _age: float = 0.0               # since the throw — drives LIVE_TIME
var _recall_t: float = 0.0
var _spent_t: float = 0.0
var _drop_t: float = -1.0           # >=0 while the whiffed dagger is falling
var _drop_v: float = 0.0
var _anchor_node: Node2D = null     # the body it rode away with, if any
var _stick_offset: Vector2 = Vector2.ZERO
var _trail: Array[Vector2] = []
var _cd_started: bool = false

## Read by the parry scans to skip a dagger that is already flying back out.
var _reflected: bool = false
var _target_group: String = "enemy"


## Entry point, mirroring every other spectacle's single driver method.
func throw_dagger(
	owner_node: Node, from: Vector2, aim: Vector2, color: Color, range_px: float,
	burst_r: float, damage: int, live_time: float, cooldown: float,
	effect: String = "shadow"
) -> void:
	_owner = owner_node
	_color = color
	_range = maxf(range_px, 120.0)
	_burst_r = maxf(burst_r, 20.0)
	_damage = damage
	_live_time = live_time if live_time > 0.5 and live_time < 30.0 else LIVE_TIME
	_cooldown = cooldown
	_effect = effect
	_dir = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	_pos = from
	_prev = from
	_angle = _dir.angle()
	global_position = Vector2.ZERO
	_state = State.FLYING
	add_to_group("rift_anchor")
	add_to_group("deflectable_spell")
	# The rift the blade leaves through — an edge-on gate at the throwing hand,
	# pointed down the flight line. Brief: a dagger is out of the hand fast (see
	# CastStyle.THROW, 0.20 s), and a gate that outlasted the throw would look like
	# a portal the blade forgot to come back through.
	SpellSigil.open(self, from, color, 1.0, true, _dir, false, 0.15, 0.32)
	Sfx.play("melee_swing", -3.0, 0.15)
	# Join the reaction system. A thrown blade is the archetypal PROJECTILE form;
	# reaction_active() keeps it inert once it has planted itself, so a stuck anchor
	# sitting in a wall for four seconds is scenery, not a live reagent.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.PROJECTILE, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) -----------------------------------

## World space, built from `_pos` — NOT from global_position, which is (0,0)
## because this node draws in world coordinates. HIT_RADIUS is the same number the
## flight collision uses, so what reacts and what damages are one shape.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(_pos, HIT_RADIUS)


## Only while it is actually a moving blade. A STUCK anchor is an object someone
## left in the wall; a RECALLING one is a tell; a SPENT one is a fading ring. None
## of those should annihilate a beam that happens to sweep past.
func reaction_active() -> bool:
	return _state == State.FLYING


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.PROJECTILE


func reaction_owner() -> Node:
	return _owner


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: end the spell through the shared exit so the thrower still
## gets their cooldown back. A blade eaten by a reaction is not a wasted slot.
func reaction_consume() -> void:
	_finish()


## How much of a victim's parry window counts against this hit. SpellDeflect's
## policy is that nothing is unparryable but an ult is brutal to time, so the tier
## the spell already declares picks the dial rather than this file inventing one.
func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


## Nearest live anchor owned by `caster`, told to recall. True if one existed —
## which is what turns a second press of the slot into the second beat.
##
## Filtering on the owner is what makes this co-op-safe: two players each pressing
## their own slot recall their own daggers, never each other's.
static func try_recall(tree: SceneTree, caster: Node) -> bool:
	var anchor: Node2D = find_anchor(tree, caster)
	if anchor == null:
		return false
	anchor.call("recall")
	return true


## The live anchor `caster` could recall to right now, or null. Also drives the
## hotbar's RECALL label, so the slot reads the same state the press will act on.
static func find_anchor(tree: SceneTree, caster: Node) -> Node2D:
	if tree == null or caster == null:
		return null
	for a: Node in tree.get_nodes_in_group("rift_anchor"):
		if not (a is Node2D) or not is_instance_valid(a):
			continue
		if a.get("_owner") != caster:
			continue
		var st: int = int(a.get("_state"))
		if st == State.FLYING or st == State.STUCK:
			return a as Node2D
	return null


## Pure geometry (testable): nodes within `radius` of `center`.
##
## RETAINED, NOT DELETED, and that is a deliberate exception to
## `docs/spell-world-contract.md`'s "delete the local helper outright": the shipped
## suite tools/slice4_test_spells.gd asserts on this exact static and is owned
## elsewhere. The BODY is gone though — it forwards to the shared selector, so
## there is one implementation in the game rather than seven.
##
## Line of sight is OFF here on purpose: this is the PURE-GEOMETRY entry point,
## taking a bare node list with no caster and no world context, which is how the
## suite calls it. The real damage path (`_resolve_recall`) calls
## `SpellTargets.in_radius` directly WITH line of sight.
static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
	return SpellTargets.in_radius(center, radius, nodes, [], null, false)


## Begin the second beat. The tell runs even from mid-flight, so a snap double-tap
## is a short forward hop rather than an instant blink to nowhere.
func recall() -> void:
	if _state != State.FLYING and _state != State.STUCK:
		return
	_state = State.RECALLING
	_recall_t = 0.0
	Sfx.play("charge_up", -8.0, 0.05, 1.4)


## Where this spell physically IS, for the parry scans (the node parks at origin).
func deflect_point() -> Vector2:
	return _pos


## Deflect contract (magic-overhaul rule 3). Reversing the blade is only half of
## it: clearing `_owner` SEVERS the anchor, so the thrower's recall finds nothing
## and the whole two-beat play is cancelled. That is the counterplay this spell
## is balanced around.
func reflect(new_dir: Vector2, color: Color) -> void:
	if _reflected or _state != State.FLYING:
		return
	_reflected = true
	_dir = new_dir.normalized() if new_dir != Vector2.ZERO else -_dir
	_angle = _dir.angle()
	_color = color
	_owner = null
	_target_group = "hero"
	_travelled = 0.0
	_trail.clear()
	if is_in_group("rift_anchor"):
		remove_from_group("rift_anchor")
	Sfx.play("ding", 0.0, 0.05)
	queue_redraw()


## AoE sweeps clear pending hazards through this (mirrors EnemyProjectile.consume).
func consume() -> void:
	_finish()


func _process(delta: float) -> void:
	_age += delta
	_spin += delta * SPIN
	match _state:
		State.FLYING:
			_fly(delta)
		State.STUCK:
			# _ride() can END the spell (the carrier died over a pit), so its answer
			# is checked rather than ignored — otherwise the dissolve beat plays
			# twice in one frame.
			if not _ride():
				return
			if _age >= _live_time:
				_dissolve()
				return
		State.RECALLING:
			if not _ride():
				return
			_recall_t += delta
			if _recall_t >= RECALL_TELL:
				_resolve_recall()
		State.SPENT:
			_spent_t += delta
			if _spent_t >= ARRIVE_FADE:
				queue_free()
				return
	queue_redraw()


func _fly(delta: float) -> void:
	_prev = _pos
	if _drop_t >= 0.0:
		# Out of throw range: it arcs down and plants itself wherever it lands, so
		# a missed throw still leaves a usable (if badly placed) anchor.
		_drop_t += delta
		_drop_v += DROP_GRAVITY * delta
		_pos += Vector2(_dir.x * DROP_DRIFT, _drop_v) * delta
		if _drop_t >= DROP_ARC:
			# THE PIT RULE. `floor_below` reports its miss rather than dropping the
			# point to the far end of the probe, so a dagger thrown over a chasm is
			# LOST instead of hanging in mid-air. "Nothing may end up below or inside
			# the environment" cuts both ways: not under the floor, and not in the void.
			var ground: Dictionary = _floor_below(_pos)
			if not bool(ground["hit"]):
				_dissolve()
				return
			_stick_world(ground["position"] as Vector2)
			return
	else:
		_pos += _dir * SPEED * delta
		_travelled += SPEED * delta
	_trail.append(_prev)
	if _trail.size() > TRAIL_LENGTH:
		_trail.remove_at(0)
	if _check_flight_collision():
		return
	if _drop_t < 0.0 and _travelled >= _range:
		_drop_t = 0.0
		_drop_v = 0.0


## Bodies first, then a world raycast along the segment travelled — the same
## order BoulderHurl uses, so a dagger never tunnels through a thin wall.
##
## THREE THINGS CHANGED HERE, all of them audit findings rather than balance calls.
##
## 1. THE BODY TEST WAS A LIE ABOUT ITS OWN SIZE. It measured `_pos` to the
##    victim's ORIGIN with `HIT_RADIUS + 12.0` — a 27 px point test, where the
##    blade is drawn 20 px long and HIT_RADIUS is 15. Two separate faults: the
##    `+ 12.0` was a second forgiveness scheme bolted on at the call site (exactly
##    what the contract forbids stacking), and testing the origin is the maker's
##    "spells pass through heads without registering" bug — a head sits ~10 px
##    ABOVE the origin (19 px on the 1.9x dummies). It is now one
##    `SpellTargets.on_line` capsule at HIT_RADIUS against the DRAWN silhouette,
##    with the target's own `hit_margin()` as the only forgiveness.
##    BALANCE: against a plain prop the reach SHRINKS by 12 px; against a drawn
##    body it grows, because the measurement starts at the body's edge instead of
##    its middle. Both moves are toward what is drawn.
##
## 2. IT ONLY TESTED WHERE THE BLADE ENDED UP. At 780 px/s a 30 fps frame moves the
##    blade 26 px — further than HIT_RADIUS — so a thin enemy could be stepped over
##    entirely. The capsule now spans `_prev` -> `_pos`, the segment JUST TRAVELLED.
##
## 3. STICKING IN A CRATE DEALT IT NOTHING. Cover is on collision layer 1, so the
##    old wall raycast stopped on it and returned before the destructible loop
##    below could ever run — that loop was dead code. The world query now reports
##    what it stopped against and the blade damages it at the exact face it bit.
func _check_flight_collision() -> bool:
	var skip: Array = [_owner]
	var travel: Vector2 = _pos - _prev
	# Nearest-first: the blade meets what is closest to where it STARTED the step,
	# not whichever body the group array happened to list first.
	var struck: Array = SpellTargets.sorted_by_distance(_prev,
		SpellTargets.on_line(_prev, travel, travel.length(), HIT_RADIUS,
			get_tree().get_nodes_in_group(_target_group), skip, self))
	if not struck.is_empty():
		var n: Node2D = struck[0] as Node2D
		var at: Vector2 = SpellTargets.aim_point(n)
		# Deflect contract: a blade that has already been turned once cannot be
		# turned again, so a guard EATS it instead — and eats the blade with it,
		# since a dagger absorbed by a sigil has no business staying stuck in the
		# body that absorbed it.
		var dealt: int = SpellDeflect.resolve(n, _damage, _dir, at, _deflect_window())
		if dealt <= 0:
			_finish()
			return true
		if n.has_method("take_damage"):
			SpellTargets.hurt(n, dealt, Color(_color.r, _color.g, _color.b, 1.0))
		if n.has_method("apply_status"):
			n.call("apply_status", element_id)
		_stick_body(n)
		return true
	# A hostile dagger (an enemy's, or one that was parried back) can itself be
	# parried. The owner is excluded so a thrower never parries their own throw, and
	# an ALREADY-reflected blade is skipped: reflect() is a one-shot, so scanning
	# would consume a hero's parry press and change nothing. That blade is stopped
	# through SpellDeflect above instead.
	if not _reflected:
		for h: Node in get_tree().get_nodes_in_group("hero"):
			if h == _owner or not (h is Node2D) or not is_instance_valid(h):
				continue
			if not SpellTargets.hits(h, _pos, HIT_RADIUS):
				continue
			if h.has_method("try_parry") and h.call("try_parry", self):
				return false
	# The world, along the segment just travelled. `smash_destructibles = false` is
	# THE deliberate exemption documented in the class header: a thrown dagger is an
	# object that plants itself in cover rather than tearing through it.
	var world: Dictionary = SpellWorld.first_solid(_prev, _pos,
		SpellWorld.rids([_owner]), self, false)
	if bool(world["hit"]):
		_bite_cover(world)
		_stick_world(world["position"] as Vector2)
		return true
	return false


## "Destroy what it can": if the thing that stopped the blade was breakable, chip
## it at the face that was actually struck, using the impact normal so the damage
## lands on the side the dagger came from. `is_smashable` also answers true for a
## body already queued for deletion, hence the validity guard — that one is a
## corpse, not cover.
func _bite_cover(world: Dictionary) -> void:
	var col: Object = world.get("collider")
	if col == null or not is_instance_valid(col) or not SpellWorld.is_smashable(col):
		return
	var at: Vector2 = world["position"] as Vector2
	var normal: Vector2 = world["normal"] as Vector2
	if col.has_method("damage_at"):
		col.call("damage_at", _damage, at,
			normal if normal != Vector2.ZERO else -_dir)
	elif col.has_method("take_damage"):
		col.call("take_damage", _damage)


## Buried in a body: the dagger keeps a fixed offset and RIDES it. A dagger stuck
## in a walking enemy is this spell's best moment — the anchor is now wherever
## that enemy decided to go.
func _stick_body(n: Node2D) -> void:
	_anchor_node = n
	_stick_offset = _pos - n.global_position
	_land()


func _stick_world(at: Vector2) -> void:
	_pos = at
	_anchor_node = null
	_land()


func _land() -> void:
	_state = State.STUCK
	_angle = _dir.angle()
	_drop_t = -1.0
	CombatVfx.spawn_burst(get_parent(), _pos,
		Color(0.35, 0.15, 0.5, 0.85), Color(0.1, 0.03, 0.2, 0.0),
		10, 0.3, 40.0, 130.0, 0.8, 2.0)
	Sfx.play("melee_hit", -6.0, 0.08, 1.25)
	Juice.shake_camera(2.0)


## Keep station on whatever we are buried in. If it dies the dagger does not go
## with it — it drops to the floor at its last position and stays recallable, so
## killing the carrier is not a free cancel.
##
## Returns FALSE when the spell ended inside this call (the carrier died over a
## pit), so the caller stops rather than running a second end-of-life beat.
func _ride() -> bool:
	if _anchor_node == null:
		return true
	if not is_instance_valid(_anchor_node):
		_anchor_node = null
		var ground: Dictionary = _floor_below(_pos)
		if not bool(ground["hit"]):
			# The carrier died over a chasm. A dagger cannot hang in thin air, and
			# leaving a recall anchor floating in the void would teleport the caster
			# into it — the same rule that stops meteors landing under the floor.
			_dissolve()
			return false
		_pos = ground["position"] as Vector2
		return true
	_pos = _anchor_node.global_position + _stick_offset
	return true


## The floor beneath `from`, as SpellWorld's standard result. CHECK `hit` — on a
## miss `position` is `from` unchanged (there genuinely is no floor there), and
## every caller here treats that as "the dagger is lost" rather than planting it in
## mid-air.
func _floor_below(from: Vector2) -> Dictionary:
	return SpellWorld.floor_below(from, DROP_PROBE, SpellWorld.rids([_owner]), self)


## The second beat resolves: the caster is torn through to the blade and the rift
## bursts on arrival. Displacement is delegated to the caster's `blink_to` — the
## SAME duck-typed contract blink_strike uses — so the hero's "never land in a
## pit" rule is not duplicated here.
func _resolve_recall() -> void:
	var from: Vector2 = _owner_point()
	# Vet the landing spot BEFORE handing it on. The blade plants itself in walls by
	# design, so the naive "arrive on the blade" puts a body inside solid rock; the
	# caster's own blink_to then gets a point that is already legal instead of one it
	# has to rescue (and SpikeFigure's blink_to does not rescue at all).
	var dest: Vector2 = _safe_arrival(_pos + Vector2(0.0, -4.0), from)
	if _owner != null and is_instance_valid(_owner) and _owner.has_method("blink_to"):
		dest = _owner.call("blink_to", dest)
	elif _owner is Node2D and is_instance_valid(_owner):
		(_owner as Node2D).global_position = dest
	var tint := Color(_color.r, _color.g, _color.b, 1.0)
	var skip: Array = [_owner]
	for e: Node in SpellTargets.in_radius(dest, _burst_r,
			get_tree().get_nodes_in_group(_target_group), skip, self):
		# The arrival burst does not travel, so per SpellDeflect's split there is
		# nothing to send back: a correctly-timed guard eats it, shove included.
		var dealt: int = SpellDeflect.resolve(e, _damage,
			(e as Node2D).global_position - dest, SpellTargets.aim_point(e),
			_deflect_window())
		if dealt <= 0:
			continue
		if e.has_method("take_damage"):
			SpellTargets.hurt(e, dealt, tint)
		if e.has_method("apply_status"):
			e.call("apply_status", element_id)
		if e.has_method("apply_knockback"):
			var away: Vector2 = ((e as Node2D).global_position - dest).normalized()
			e.call("apply_knockback", (away if away != Vector2.ZERO else Vector2.UP) * ARRIVE_KNOCK)
	for prop: Node in SpellTargets.in_radius(dest, _burst_r,
			get_tree().get_nodes_in_group("destructible"), skip, self):
		if prop.has_method("take_damage"):
			prop.call("take_damage", _damage)
	for proj: Node in SpellTargets.in_radius(dest, _burst_r,
			get_tree().get_nodes_in_group("enemy_projectile"), skip, self):
		if proj.has_method("consume"):
			proj.call("consume")
	# Inky puff where the caster WAS, hot flash where they arrive — the same
	# read as blink_strike's departure/arrival pair, so a teleport always looks
	# like a teleport no matter which spell caused it.
	CombatVfx.spawn_burst(get_parent(), from, Color(0.35, 0.15, 0.5, 0.9),
		Color(0.1, 0.03, 0.2, 0.0), 16, 0.4, 50.0, 150.0, 1.2, 3.0)
	CombatVfx.spawn_burst(get_parent(), dest, Elements.emissive(element_id),
		Color(_color.r, _color.g, _color.b, 0.0), 20, 0.35, 70.0, 210.0,
		0.7, 2.0, 0.0, 0.0, true)
	Juice.hit_stop(0.06)
	Juice.shake_camera(8.0)
	# The shadow family's shared mark — the negative (see ShadowRoot._erupt).
	# A teleport is the single best fit for it in the whole kit: the picture is
	# identical either side of the blink except that YOU moved, which is exactly
	# what an inverted frame says.
	Juice.frame({
		"style": ImpactFrame.Style.INVERT, "strength": 0.9, "at": dest,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})
	Sfx.play("blink", 0.0, 0.05)
	_pos = dest
	_finish()


## The nearest point to `dest` a BODY may legally rest at, walking back toward
## `home` (the caster, who is standing somewhere legal by construction).
##
## A POINT test, not a segment test, and that distinction is load-bearing: a rift
## tear is ALLOWED to cross a thin wall — only the RESTING SPOT matters. This is
## the same rule Hero._safe_blink_destination and BlinkStrike.safe_blast_point
## document, and a segment raycast here would drag every legal recall back to the
## first wall between the caster and their own blade.
##
## Destructible cover does NOT block: you may appear inside a crate, and it breaks.
## The back-ray, however, runs with smashing OFF — we are looking for the surface we
## came through, and a crate is a perfectly good surface to stand just outside of.
func _safe_arrival(dest: Vector2, home: Vector2) -> Vector2:
	var skip: Array[RID] = SpellWorld.rids([_owner])
	if not SpellWorld.is_blocked(dest, ARRIVE_CLEARANCE, skip, self):
		return dest
	var away: Vector2 = home - dest
	if away.length() < 1.0:
		return home
	var back: Dictionary = SpellWorld.first_solid(dest, home, skip, self, false)
	if not bool(back["hit"]):
		return home  # buried, but no surface between here and home — fall all the way
	return (back["position"] as Vector2) + away.normalized() * ARRIVE_CLEARANCE


## The anchor was never used: it crumbles and hands the cooldown back.
func _dissolve() -> void:
	CombatVfx.spawn_burst(get_parent(), _pos, Color(0.2, 0.06, 0.32, 0.7),
		Color(0.05, 0.0, 0.1, 0.0), 10, 0.35, 30.0, 90.0, 0.7, 1.8)
	_finish()


## Shared end: start the owner's cooldown ONCE (a deferred-resolution spell only
## "completes" here, not at the throw) and fade out.
func _finish() -> void:
	if not _cd_started and _owner != null and is_instance_valid(_owner) \
			and _owner.has_method("start_signature_cooldown"):
		_owner.call("start_signature_cooldown", _cooldown)
	_cd_started = true
	_state = State.SPENT
	_spent_t = 0.0
	if is_in_group("rift_anchor"):
		remove_from_group("rift_anchor")
	if is_in_group("deflectable_spell"):
		remove_from_group("deflectable_spell")


## The caster's world point for the thread. The spike rig's node sits at its spawn
## position while the body it actually drives is a RigidBody2D torso hanging off
## it, so ask for the torso when there is one (the playground controller resolves
## the rig's position the same way).
func _owner_point() -> Vector2:
	if _owner == null or not is_instance_valid(_owner):
		return _pos
	var torso: Variant = _owner.get("_torso")
	if torso is Node2D and is_instance_valid(torso):
		return (torso as Node2D).global_position
	if _owner is Node2D:
		return (_owner as Node2D).global_position
	return _pos


func _draw() -> void:
	match _state:
		State.FLYING:
			_draw_thread(0.16)
			_draw_blade(_spin, 1.0)
		State.STUCK:
			_draw_rift()
			_draw_thread(0.25)
			_draw_blade(_angle, 1.0)
		State.RECALLING:
			_draw_rift()
			_draw_thread(0.9)
			_draw_blade(_angle, 1.0)
		State.SPENT:
			var k: float = clampf(1.0 - _spent_t / ARRIVE_FADE, 0.0, 1.0)
			draw_circle(_pos, _burst_r * (0.4 + 0.9 * (1.0 - k)),
				Color(0.35, 0.15, 0.6, 0.22 * k), true, -1.0, true)
			draw_arc(_pos, _burst_r * (0.5 + 1.0 * (1.0 - k)), 0.0, TAU, 40,
				Color(0.78, 0.5, 1.15, 0.85 * k), 3.0, true)


## The blade. Built as a real dagger silhouette — tip, edge, guard, grip, pommel
## — rather than a glowing shard, because this thing has to read as an OBJECT
## someone left in the wall for four seconds, not as a projectile still in play.
## The body is dark violet rather than near-black for exactly that reason: a
## light-eating fill vanishes on this arena and all that survived was the guard
## and the spine, which read as a plus sign.
func _draw_blade(ang: float, k: float) -> void:
	for i in _trail.size():
		var age: float = float(i + 1) / float(_trail.size())
		draw_circle(_trail[i], 3.0 * age, Color(0.5, 0.24, 0.85, 0.28 * age * k), true, -1.0, true)
	var t := Transform2D(ang, _pos)
	var tip: Vector2 = t * Vector2(BLADE_LEN, 0.0)
	var needle := PackedVector2Array([
		tip,
		t * Vector2(3.0, -BLADE_HALF_W),
		t * Vector2(0.0, 0.0),
		t * Vector2(3.0, BLADE_HALF_W),
	])
	draw_colored_polygon(needle, Color(0.14, 0.05, 0.24, 0.98 * k))
	var outline := PackedVector2Array(needle)
	outline.append(tip)                                   # close the silhouette
	draw_polyline(outline, Color(0.62, 0.34, 1.0, 0.9 * k), 1.6, true)
	var em: Color = Elements.emissive(element_id)
	draw_line(t * Vector2(1.0, 0.0), tip, Color(em.r, em.g, em.b, 0.8 * k), 1.2, true)
	# Guard, grip and pommel. Without them the blade is just a spike, and every
	# other shadow spell in the kit is already made of spikes.
	draw_line(t * Vector2(0.0, -6.5), t * Vector2(0.0, 6.5),
		Color(0.16, 0.05, 0.28, 0.98 * k), 3.2, true)
	draw_line(t * Vector2(0.0, -6.5), t * Vector2(0.0, 6.5),
		Color(0.6, 0.34, 0.98, 0.8 * k), 1.2, true)
	draw_line(t * Vector2(0.0, 0.0), t * Vector2(-GRIP_LEN, 0.0),
		Color(0.1, 0.03, 0.18, 0.98 * k), 3.4, true)
	draw_circle(t * Vector2(-GRIP_LEN - 1.5, 0.0), 2.6, Color(0.5, 0.26, 0.86, 0.9 * k), true, -1.0, true)


## The tear in space the blade is pinning open: a squashed ellipse behind it,
## breathing. Squashed (not a disc) so it reads as a slit, not another nova ring.
func _draw_rift() -> void:
	var pulse: float = 0.85 + 0.15 * sin(_age * 7.0)
	var flare: float = 1.0
	if _state == State.RECALLING:
		flare = 1.0 + 1.6 * clampf(_recall_t / RECALL_TELL, 0.0, 1.0)
	# Perpendicular to the blade: the dagger is PINNING the tear, so a slit across
	# it reads as a wound in space, where an ellipse aligned with the blade just
	# reads as a saucer the dagger is sitting in.
	draw_set_transform(_pos, _angle + PI * 0.5, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 15.0 * pulse * flare, Color(0.03, 0.0, 0.07, 0.75), true, -1.0, true)
	draw_arc(Vector2.ZERO, 17.0 * pulse * flare, 0.0, TAU, 28,
		Color(0.68, 0.38, 1.05, 0.7), 1.8, true)
	draw_arc(Vector2.ZERO, 23.0 * pulse * flare, 0.0, TAU, 32,
		Color(0.5, 0.24, 0.85, 0.3), 1.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _state == State.RECALLING:
		var em: Color = Elements.emissive(element_id)
		draw_circle(_pos, 6.0 * flare, Color(em.r, em.g, em.b, 0.8), true, -1.0, true)


## The line home. Wavy and faint while the anchor waits — it is a reminder, not a
## laser — then STRAIGHTENING as the recall commits. That straightening is the
## arrival tell: an enemy standing on the dagger has RECALL_TELL to step off.
func _draw_thread(strength: float) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var a: Vector2 = _owner_point()
	var b: Vector2 = _pos
	if a.distance_to(b) < 8.0:
		return
	var taut: float = 0.0
	if _state == State.RECALLING:
		taut = clampf(_recall_t / RECALL_TELL, 0.0, 1.0)
	var perp: Vector2 = (b - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in 13:
		var u: float = float(i) / 12.0
		var wob: float = sin(u * 9.0 + _age * 5.0) * 10.0 * sin(u * PI) * (1.0 - taut)
		pts.append(a.lerp(b, u) + perp * wob)
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, strength * (0.5 + 0.5 * taut)),
		1.6 + 2.4 * taut, true)
	if taut > 0.0:
		var em: Color = Elements.emissive(element_id)
		draw_polyline(pts, Color(em.r, em.g, em.b, 0.55 * taut), 1.0, true)
		draw_circle(a, 5.0 + 9.0 * taut, Color(em.r, em.g, em.b, 0.6 * taut), true, -1.0, true)
		draw_circle(b, 5.0 + 9.0 * taut, Color(em.r, em.g, em.b, 0.6 * taut), true, -1.0, true)
