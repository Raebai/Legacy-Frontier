class_name RockWall
extends Node2D
## Earthbending ROCK WALL. A temporary SOLID stone barrier SLAMS up out of the
## ground in the aim direction — heavy irregular slabs erupt one after another
## (bottom-first, with overshoot) so the raise reads as an upheaval, not a grow.
## A StaticBody2D on collision layer 1 blocks enemy BODIES + enemy PROJECTILES
## for a few seconds, then crumbles into rubble. Defensive at rest — but SHOVE
## it (see shove()) and it becomes a grinding projectile-wall that plows enemies,
## smashes crates, and slams to a stop against real world geometry.
## Instantiate .new(), add to arena, call raise_wall(). Draws in world coords.
##
## ══ WHAT THIS WALL IS, AGAINST THE OTHER ONE ═══════════════════════════════
## Maker: *"a rock wall and an ice wall must not be the same spell in two colours"*.
## Both walls answer the SAME second press and answer it OPPOSITELY, which is the
## whole of the distinction and is written out at length in IceWall's header:
##
##   ROCK (here) — the press DISPLACES it. The wall survives the press, LEAVES, and
##                 becomes a grinding ram travelling away from you: offence at RANGE,
##                 along a LINE, and you keep nothing where you were standing.
##   ICE         — the press DETONATES it. It does not move; it bursts where it
##                 stands: offence UP CLOSE, in a RING, and it costs you the barrier.
##
## Stone is the one that MOVES because stone is MASS. That is not decoration: the
## slide is the only reason `_plow_enemies`, `_smash_props`, `_hit_world` and
## `_slam_stop` exist, and none of them have an equivalent on the ice.
##
## THE TWO-BEAT (the maker's ask): rock wall is ONE button pressed twice — the
## first press summons the wall, the second press is the punch that sends it. The
## arbitration that decides which of those a press means lives in the caster (it
## is made of feel numbers — reach, facing, how long the combo stays open); this
## file owns the three things the caster needs to make that call honestly:
## `caster_node` (whose wall is it), `can_shove()` (would a press do anything) and
## `set_primed()` (the tell, so the player can SEE the second beat is armed).
##
## SHOVE CONTRACT (for the punch / RMB hook in SpikeFigure):
##   * every standing wall is in the "shoveable" group
##   * `shove(dir, speed)` starts the slide (returns false if crumbling/sliding)
##   * `can_shove()` = would a shove do anything RIGHT NOW — ask BEFORE committing
##     a button press to a wall, or the press gets eaten by one already sliding
##   * `wall_distance(pos)` = px from pos to the wall's footprint (for range checks)
##   * `time_since_raise()` = seconds since it erupted (for combo-window checks)
##   * `RockWall.find_shoveable_near(tree, pos, max_dist, by)` = nearest shoveable
##   * `RockWall.snapshot_shoveable()` / `adopt_new_shoveable()` = stamp ownership
##     around a cast, since SpellCaster does not forward the caster to raise_wall
##
## REACTION CONTRACT (see SpellReactor): this wall is a BARRIER of EARTH — the
## only barrier in the game that stone counters a school with. `ground_out` (a
## lightning beam is eaten by the earth it hits), `carve` (an evenly matched beam
## BORES THROUGH stone instead of stopping — the one authored exception where a
## barrier is porous), `breach` and `barrier_blocks` all reach it the moment
## `raise_wall()` registers. See reaction_form() for the ruling on what a SHOVED
## wall is, which is the one genuinely arguable call in here.

const WALL_OFFSET: float = 90.0     # how far in front of the caster it rises
const WALL_SIZE: Vector2 = Vector2(44.0, 124.0)  # thickness x height — CHUNKY (ice is slim)
## Clearance left between a shoved body and the wall face. Big enough that the next
## physics step does not immediately re-overlap and re-trigger the depenetration this
## is avoiding. See `_eject_bodies_from_wall`.
const EJECT_PAD: float = 13.0
## How far BELOW the base a body still counts as caught. A fighter stands with its
## origin above its feet, so a body on the ground at the wall's base reads a few px
## under `_floor_base` and would otherwise be missed.
const EJECT_FOOT_PAD: float = 20.0
const RISE_TIME: float = 0.34       # full upheaval: last slab locks just before this
const SLAB_RISE: float = 0.16       # one slab's pop-up time
const SLAB_STAGGER: float = 0.055   # delay between slab launches (bottom-first)
const LIFETIME: float = 4.5         # solid + blocking
const CRUMBLE_TIME: float = 0.5
const DEBRIS_COUNT: int = 22
const SLABS: int = 4                # few BIG slabs (ice is many thin spires)

## Shove tuning — the wall as a projectile. Speed sits below BoulderHurl's 900
## so the slide reads heavier than the throw; damage/knockback match a mid hit.
const SHOVE_SPEED: float = 820.0
const SHOVE_DAMAGE: int = 40
const SHOVE_KNOCKBACK: float = 560.0
const MAX_SLIDE: float = 2200.0     # off-map cap: despawn if nothing stopped it
const GRIND_DUST_INTERVAL: float = 0.06
const PLOW_PAD: float = 22.0        # extra reach on the enemy plow check

const BODY_COLOR: Color = Color(0.38, 0.27, 0.17)
const FACE_COLOR: Color = Color(0.5, 0.37, 0.23)
const LIT_COLOR: Color = Color(0.62, 0.46, 0.26)
const RIM_COLOR: Color = Color(1.15, 0.92, 0.55)  # HDR highlight (blooms)
const SEAM_COLOR: Color = Color(0.16, 0.11, 0.07)
const AMBER_RIM: Color = Color(0.85, 0.55, 0.15)
## Primed-crown tell. Fast enough to read as "armed, act now" rather than as the
## wall's idle breathing, and the glow is multiplied into already-HDR colours so
## the bloom does the work instead of a bigger shape.
## UNTESTED GUESS: both numbers are reasoning, not feel — tune them here.
const PRIME_PULSE_HZ: float = 2.6
const PRIME_GLOW: float = 0.9
const DUST_TINT: Color = Color(0.55, 0.42, 0.28, 0.5)

## ── the reaction contract's one number ───────────────────────────────────────
## Half-width of the volume `reaction_shape()` publishes. Deliberately the SAME
## reach `_smash_props()` already uses to decide that an enemy bolt has been eaten
## by the mass (`wall_distance(p) <= PLOW_PAD`): the wall has ONE contact volume,
## and a second number saying "how close a spell has to be to count as hitting the
## stone" is exactly how drawn-vs-damaged drift starts.
##
## It lands where the wall is DRAWN rather than where its collider is. The blocking
## box is only ±22 px, but the widest slab is drawn out to roughly ±43 with its
## bulges — so a beam that visibly strikes the stone must ground out on it instead
## of passing through a gap the player cannot see. 22 + 22 = 44 covers that.
const REACTION_HALF_WIDTH: float = WALL_SIZE.x * 0.5 + PLOW_PAD

## EARTH, not -1. Two reasons, and the first one is fatal on its own:
##   1. `SpellReactor.register()` REFUSES any effect with `element < 0` outright
##      (an elementless effect would match wildcard rows as a phantom element), so
##      a wall reporting -1 is turned away at the door and every earth row authored
##      for it — `ground_out`, `carve` — is unreachable.
##   2. It is what SpellCaster already stamps. The shipped rock_wall SpellDef
##      declares `element = Elements.Element.EARTH`, so every cast wall has been
##      EARTH since the stamp landed; -1 was only ever the value a wall built
##      directly with .new() (capture tools, spikes) was left holding. Defaulting
##      to the same thing makes the two agree instead of depending on who built it.
## Knock-on, stated rather than discovered later: `_plow_enemies()` gates its
## `apply_status` on `element_id >= 0`, so a directly-built wall now also applies
## the EARTH ailment when it plows — which is what a cast one already did.
## WHO THIS SPELL MAY HURT. Stamped by SpellCaster._stamp() at cast time, so it
## follows the CASTER's faction rather than being fixed at "enemy" forever.
##
## Every spectacle used to scan the literal group "enemy", which is why a
## hero-shaped bot's spells passed harmlessly through another hero: the aim was
## right, the spectacle spawned and drew, and then it queried a group its target
## was not in. Nothing errored — the spell simply never hit anything, which reads
## as a physics bug rather than a targeting one.
##
## Defaults to "enemy", so every existing caster, capture tool and test is
## byte-identical and single player does not change by one branch.
var target_group: String = "enemy"
var element_id: int = Elements.Element.EARTH
## Reaction WEIGHT — a SpellTier.Tier, stamped by SpellCaster at cast time from the
## spell's own cast time / cooldown / cost. The shipped rock_wall is HEAVY, which
## is what puts it on the barrier ladder's middle rungs: an ULT beam BREACHES it,
## an evenly matched one CARVES through it, and a lighter one is simply stopped.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## WHO RAISED THIS. Same name and shape as BeamSpell's `caster_node`, so the one
## question the reaction layer keeps asking — "is this mine?" — is asked the same
## way everywhere. Null means nobody has claimed it: an unowned wall can still be
## punched by anyone, it just cannot steal anybody's use button.
var caster_node: Node = null
var _floor_base: Vector2 = Vector2.ZERO
var _color: Color = Color(0.78, 0.55, 0.28)
var _elapsed: float = -1.0
var _crumbling: bool = false
var _body: StaticBody2D = null
var _collider: CollisionShape2D = null

# Slab geometry, built once at raise: local-space polys with y=0 at the floor.
var _slab_polys: Array[PackedVector2Array] = []
var _slab_base_y: PackedFloat32Array = PackedFloat32Array()  # local y of each slab's bottom
var _slab_delay: PackedFloat32Array = PackedFloat32Array()
var _slab_locked: Array[bool] = []
var _stack_h: float = 0.0

# Shove state.
var _sliding: bool = false
var _slide_dir: Vector2 = Vector2.RIGHT
var _slide_speed: float = SHOVE_SPEED
var _slide_traveled: float = 0.0
var _grind_t: float = 0.0
var _plowed: Dictionary = {}        # instance_id -> true (each enemy hit once per slide)
var _primed: bool = false           # the next use-press punches me — see set_primed()


func raise_wall(
	from: Vector2, aim: Vector2, color: Color = Color(0.78, 0.55, 0.28), _effect: String = "earth"
) -> void:
	_color = color
	_floor_base = wall_center(from, aim, WALL_OFFSET)
	var hit: Dictionary = _floor_below(_floor_base, 220.0)
	if not hit.is_empty():
		_floor_base = hit["position"]
	_elapsed = 0.0
	_build_slabs()
	add_to_group("shoveable")  # the punch/RMB hook finds walls through this group
	# Real blocking body — layer 1 stops enemy bodies + enemy projectiles.
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_body.global_position = _floor_base
	var shape := RectangleShape2D.new()
	shape.size = WALL_SIZE
	_collider = CollisionShape2D.new()
	_collider.shape = shape
	_collider.position = Vector2(0.0, -WALL_SIZE.y * 0.5)  # extend UP from the base
	_body.add_child(_collider)
	# ⚠ AND ANYONE STANDING WHERE IT ERUPTED GETS PUSHED OUT. Maker: *"rockwall keeps
	# freezing the opponents in the wall"*.
	#
	# The body above is created at FULL SIZE on this very frame (the header says so,
	# and the reaction contract depends on it), on collision layer 1, with no regard
	# for who was standing there. A `CharacterBody2D` that finds itself inside a
	# `StaticBody2D` has no good way out: depenetration picks the shortest separation,
	# which for a body near the middle of a 44 x 124 slab is sideways into the other
	# half of the wall, and it jitters there for the wall's whole life. The victim
	# reads as frozen INSIDE the stone, which is exactly the report.
	#
	# The wall is the whole point of the spell, so the wall wins and the BODY moves.
	_eject_bodies_from_wall()
	# The ground BREAKS as the first slab tears out — a slam, not a fade-in.
	DebrisChunk.spawn_burst(get_parent(), _floor_base, Color(0.5, 0.38, 0.22), 8, Vector2.UP, 260.0)
	CombatVfx.spawn_burst(get_parent(), _floor_base, Color(0.85, 0.62, 0.35, 0.8),
		Color(0.4, 0.28, 0.15, 0.0), 20, 0.5, 80.0, 220.0, 1.5, 4.0)
	ScorchDecal.spawn(get_parent(), _floor_base, WALL_SIZE.x * 0.7, "crack",
		Color(0.5, 0.36, 0.22, 0.5), 6.0)
	# THE SUMMONING MARK IN THE FLOOR. A wall is a placed spell, so the sigil lies
	# DOWN at its base rather than standing as a gate — the read is "the ground here
	# is about to answer", and it is on screen before the slabs finish rising. Scaled
	# off the wall's own footprint, not off the spell's cost: the mark has to be as
	# wide as the thing coming out of it or the two look unrelated.
	SpellSigil.open(self, _floor_base, color, WALL_SIZE.x / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.14, 0.62)
	Juice.shake_camera(7.0)
	Sfx.play("earth", -4.0, 0.08)
	# Join the reaction system. Unlike BeamSpell (which registers during a charge it
	# is not yet allowed to react from) there is no telegraph to sit through here:
	# the blocking collider above is live on this very frame, so the wall is a
	# reactant from the moment it erupts. See reaction_active().
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.BARRIER, element_id)
	queue_redraw()


## Shove anything caught inside the freshly-raised slab out to the nearer face.
##
## Deliberately a POSITION write and not an impulse: a shove that has to be integrated
## can be swallowed by the victim's own `move_and_slide` in the same frame it is
## applied — and the failure mode being fixed is precisely a body that cannot resolve
## its own overlap. Moving it clear first and then letting it keep its velocity is the
## only version that cannot fight itself.
##
## Horizontal only. Lifting a victim over a 124 px wall would be a free escape from the
## thing that just blocked them, and dropping them through the floor is worse.
func _eject_bodies_from_wall() -> void:
	var half_w: float = WALL_SIZE.x * 0.5
	var top: float = _floor_base.y - WALL_SIZE.y
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for group: StringName in [&"hero", &"enemy"]:
		for n: Node in tree.get_nodes_in_group(group):
			var b := n as Node2D
			if b == null or not is_instance_valid(b):
				continue
			# The caster is standing WALL_OFFSET away by construction; skip it anyway
			# so a wall raised against a wall never shoves its own summoner.
			if b == caster_node:
				continue
			var p: Vector2 = b.global_position
			if p.y < top or p.y > _floor_base.y + EJECT_FOOT_PAD:
				continue
			var dx: float = p.x - _floor_base.x
			if absf(dx) > half_w + EJECT_PAD:
				continue
			# Out of the nearer face. `dx == 0` is a real case (a wall raised exactly
			# on top of someone), so it needs a side rather than a zero push.
			var side: float = signf(dx)
			if side == 0.0:
				side = 1.0 if _floor_base.x >= global_position.x else -1.0
			b.global_position = Vector2(
				_floor_base.x + side * (half_w + EJECT_PAD), p.y)


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) -----------------------------------

## World-space geometry, built from `_floor_base` — NOT from `global_position`,
## which is (0, 0) because this node draws in world coordinates. It also TRACKS: a
## shoved wall moves `_floor_base` every frame, so the shape follows the slide with
## nothing extra to keep in sync.
##
## THE INSET. A capsule is a segment inflated by half its width, so its end caps
## stick out REACTION_HALF_WIDTH px past each endpoint. Handing it the raw base and
## crown would promise 44 px of reach above the wall (and 44 px underground) that
## the wall does not have. Pulling both endpoints IN by the half-width makes the
## stadium span exactly base..base-WALL_SIZE.y — the wall you can see. The clamp
## matters here rather than being defensive boilerplate: this wall is 124 tall and
## 88 wide through the reaction volume, so the inset is a real fraction of it.
func reaction_shape() -> Dictionary:
	var hw: float = REACTION_HALF_WIDTH
	var inset: float = minf(hw, WALL_SIZE.y * 0.5)
	return SpellGeometry.capsule(
		_floor_base + Vector2.UP * inset,
		_floor_base + Vector2.UP * (WALL_SIZE.y - inset),
		hw * 2.0)


## LOAD-BEARING, and a DELIBERATE departure from BeamSpell / RockPillar, which are
## both inert for their whole telegraph. Those two have nothing there yet during the
## tell. This wall's StaticBody2D is created at full size in `raise_wall()` and is
## already stopping bodies and enemy bolts throughout the 0.34 s upheaval — so
## treating the rise as a telegraph would let a beam sail through a wall that is
## visibly, physically in its way.
##
## TRUE WHILE SLIDING, which is the interesting half. A shoved wall is still a slab
## of stone standing between two people: a beam fired at it should still ground out
## / carve / be stopped, and a moving shield you punched into the line of fire is a
## play rather than a hole in the system. What it is NOT any more is a barrier the
## reaction layer can treat as furniture — see reaction_form().
##
## False once `_crumbling` (the collider is disabled and what is left is dust) and
## false before the raise. `_process_slide` sets `_elapsed = -1.0` on the off-map
## despawn, which lands on the same guard.
func reaction_active() -> bool:
	return _elapsed >= 0.0 and not _crumbling


func reaction_element() -> int:
	return element_id


## THE RULING: a shoved wall is still a BARRIER, not a PROJECTILE.
##
## The fiction pulls the other way and it is worth saying why it loses. A wall
## grinding across the arena at 820 px/s IS a battering ram, and as a PROJECTILE it
## would reach rows a barrier cannot: `shrapnel_cone` against an ice wall,
## `breach` against a lighter barrier. That is the more exciting answer. It is also
## the wrong one, for two reasons that are about this system rather than about
## taste:
##
##  1. THE SHAPE CANNOT TELL BOTH STORIES. `ReactionOutcomes._travel_dir()` reads a
##     projectile's heading straight off its capsule (from -> to). This wall's
##     capsule stands VERTICALLY whether it is parked or grinding, because that is
##     the shape of a slab of stone. Registering the ram as a projectile would make
##     `shrapnel_cone` throw its shards straight UP out of the wall instead of along
##     the slide — a cone drawn one way and damaging another, i.e. exactly the
##     drawn-vs-damaged class of bug this layer keeps finding. Re-shaping the
##     capsule along the slide is not an escape either: a 124 px tall wall laid out
##     as a horizontal capsule would claim ±66 px of phantom reach off both ends.
##  2. FORM IS CAPTURED AT REGISTRATION, not polled. SpellReactor stores `form` in
##     its live dict and only re-reads `active` and `weight` each tick, so changing
##     form mid-life means unregister + re-register — which also drops the pair memo
##     and lets an already-resolved pair fire a second time. The contract does not
##     offer a form change, and inventing one for a single spell is how a detector
##     acquires a special case.
##
## Nothing is lost from the ram itself: its damage story is `_plow_enemies()`,
## `_smash_props()` and `_hit_world()`, none of which are reactions. What IS
## genuinely missing is "ram the ice wall and burst it", because BARRIER vs BARRIER
## is the authored `none` row. That is a TABLE decision (a row in ReactionTable), not
## a lie told by this file about what it is.
func reaction_form() -> int:
	return ReactionTable.Form.BARRIER


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction — and spent through the wall's OWN death, reached exactly the
## way `_slam_stop()` reaches it: fast-forward onto the crumble timeline, then run
## the single teardown that leaves the "shoveable" group, disables the collider,
## sprays the rubble and lets `_process` free it on schedule. A private teardown
## here is how a wall ends up freed while still in the group the two-beat searches,
## or still blocking, or silently gone.
##
## Guarded rather than assumed idempotent: `_begin_crumble()` re-fires debris and a
## camera shake, and a wall consumed twice in one tick would double both.
func reaction_consume() -> void:
	if _elapsed < 0.0 or _crumbling:
		return
	_elapsed = RISE_TIME + LIFETIME
	_begin_crumble()


## Pure geometry (testable): where the wall lands relative to the caster + aim.
static func wall_center(from: Vector2, aim: Vector2, offset: float = WALL_OFFSET) -> Vector2:
	var d: Vector2 = aim.normalized()
	if d == Vector2.ZERO:
		d = Vector2.RIGHT
	return from + d * offset


## Nearest standing shoveable wall within `max_dist` px of `pos`, or null.
## Cheap helper for the punch hook: one group scan, footprint-distance check.
##
## Walls that could not answer a shove right now (mid-slide, crumbling) are
## skipped rather than returned-and-refused: the two-beat spends a BUTTON PRESS
## on whatever comes back, and a press swallowed by a wall already grinding away
## from you is a dead press. `by` narrows the search to walls that node raised,
## which is what keeps the use-button claim from hijacking someone else's wall
## in co-op. Both filters stay duck-typed via has_method so anything else that
## joins the group and answers wall_distance() is still findable.
static func find_shoveable_near(
	tree: SceneTree, pos: Vector2, max_dist: float = 140.0, by: Node = null
) -> Node2D:
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = max_dist
	for w: Node in tree.get_nodes_in_group("shoveable"):
		if not is_instance_valid(w) or not w.has_method("wall_distance"):
			continue
		if w.has_method("can_shove") and not bool(w.call("can_shove")):
			continue
		if by != null and not (w.has_method("is_raised_by") and bool(w.call("is_raised_by", by))):
			continue
		var d: float = w.call("wall_distance", pos)
		if d <= best_d:
			best_d = d
			best = w as Node2D
	return best


## Would a shove actually do something to this wall right now? `shove()` already
## refuses when the wall is still underground, sliding or crumbling — this asks
## the same question BEFORE a caller commits an input to it.
func can_shove() -> bool:
	return _elapsed >= 0.0 and not _crumbling and not _sliding


## Seconds since this wall erupted, for combo-window checks. INF before the raise
## so an un-raised wall can never look "fresh". Only meaningful while the wall is
## standing: _slam_stop() fast-forwards _elapsed onto the crumble timeline, which
## is fine because can_shove() has already excluded that wall by then.
func time_since_raise() -> float:
	return _elapsed if _elapsed >= 0.0 else INF


func is_raised_by(who: Node) -> bool:
	return who != null and caster_node == who


## THE TELL. Before the player presses the button for the second beat they have
## to be able to SEE that it will punch rather than cast. This deliberately does
## not add a new highlight: the wall already draws an amber crown rim as its
## "you can interact with this" cue, and priming just makes that same line
## brighter, fatter and pulsing — the wall waking up, not a new UI element.
func set_primed(on: bool) -> void:
	if _primed == on:
		return
	_primed = on
	queue_redraw()


## --- ownership handoff -------------------------------------------------------
## SpellCaster does not forward the caster to raise_wall(), and it has no reason
## to: a wall does not move whoever cast it, which is the only thing that seam
## passes a caster for. The two-beat DOES need it, so the caster brackets its own
## cast with these two calls and adopts whatever wall appeared. Bracketing rather
## than "nearest wall" or "newest wall" guessing keeps it exact — it cannot pick
## up somebody else's wall standing next to you, and it stays correct if a single
## cast ever raises more than one.
static func snapshot_shoveable(tree: SceneTree) -> Array:
	return tree.get_nodes_in_group("shoveable") if tree != null else []


## Stamp `by` onto every shoveable wall that was not in `before`. Returns how many
## were adopted. Already-owned walls are left alone, so a second bracket around a
## nested cast can never steal the first caster's wall.
##
## ⚠ DUCK-TYPED, NOT `as RockWall`. It used to cast, which silently skipped every
## wall that was not literally this class — so the moment the ICE wall joined the
## "shoveable" registry (it answers the same press by DETONATING; see IceWall's
## header) an ice wall could never be claimed, and the claimable half of the
## two-beat — the primed tell, which requires `is_raised_by(you)` — would never
## light for it. Nothing would have errored: the wall would simply have been
## punchable by anyone and advertised to no one, which reads as the tell being
## broken rather than as ownership never being stamped.
##
## The marker for "this is a wall that can be owned" is `is_raised_by` plus a
## DECLARED `caster_node`. `get()` on an undeclared property returns null, which is
## indistinguishable from a declared-and-unowned one, so the method is what carries
## the contract and the property is only read once the method has vouched for it.
static func adopt_new_shoveable(tree: SceneTree, before: Array, by: Node) -> int:
	if tree == null:
		return 0
	var claimed: int = 0
	for w: Node in tree.get_nodes_in_group("shoveable"):
		if not is_instance_valid(w) or not w.has_method("is_raised_by"):
			continue
		if w.get("caster_node") != null or before.has(w):
			continue
		w.set("caster_node", by)
		claimed += 1
	return claimed


## Where this wall actually STANDS right now. The node itself sits at the arena
## origin and everything is drawn in world coordinates, so `global_position` is
## not the wall — callers deciding "is it to my left or my right" must ask for
## this. Distinct from the static wall_center() above, which PREDICTS where a
## wall would land for a given caster + aim before one exists.
func footprint_center() -> Vector2:
	return _floor_base - Vector2(0.0, WALL_SIZE.y * 0.5)


## Distance from `pos` to this wall's blocking footprint (0 when touching it).
func wall_distance(pos: Vector2) -> float:
	var hw: float = WALL_SIZE.x * 0.5
	var nearest := Vector2(
		clampf(pos.x, _floor_base.x - hw, _floor_base.x + hw),
		clampf(pos.y, _floor_base.y - WALL_SIZE.y, _floor_base.y),
	)
	return pos.distance_to(nearest)


## THE MAKER'S PUSH MECHANIC: punch the wall and it SLIDES across the arena as a
## grinding mass — plows enemies (damage + heavy knockback), smashes destructible
## crates, stops with a slam on real world geometry, despawns off-map. Horizontal
## only (walls grind along the ground; the punch's y is ignored so a downward
## swing still shoves sideways). Returns false when there is nothing to shove.
func shove(dir: Vector2, speed: float = SHOVE_SPEED) -> bool:
	if _elapsed < 0.0 or _crumbling or _sliding:
		return false
	var sx: float = signf(dir.x)
	if sx == 0.0:
		sx = 1.0
	_slide_dir = Vector2(sx, 0.0)
	_slide_speed = maxf(speed, 100.0)
	_sliding = true
	_primed = false  # the second beat has been spent — stop advertising it
	_elapsed = maxf(_elapsed, RISE_TIME)  # a mid-rise shove snaps the wall solid first
	for i in SLABS:
		_slab_locked[i] = true
	# The send-off: dust kicks out BEHIND the wall + a real screen hit, so the
	# first frame of the slide already reads heavy.
	CombatVfx.spawn_burst(get_parent(), _floor_base - _slide_dir * WALL_SIZE.x * 0.6,
		Color(0.8, 0.62, 0.4, 0.85), Color(0.4, 0.28, 0.15, 0.0),
		18, 0.45, 90.0, 240.0, 1.6, 4.0, 0.0, 0.0, false, -_slide_dir, 55.0)
	DebrisChunk.spawn_burst(get_parent(), _floor_base, Color(0.5, 0.38, 0.22), 4, Vector2.UP, 180.0)
	Juice.on_hit({"dir": _slide_dir, "shake": 9.0, "kick": 7.0,
		"sfx": "earth", "sfx_pitch": 0.06, "hitstop": 0.04})
	queue_redraw()
	return true


func _floor_below(from: Vector2, max_dist: float) -> Dictionary:
	var world: World2D = get_world_2d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, max_dist), 1)
	return world.direct_space_state.intersect_ray(query)


## Build the slab silhouette ONCE at raise: a few BIG irregular slabs, widest at
## the bottom, chipped edges, slight overlap — reads as stacked dumb mass where
## the ice wall reads as a grown crystal cluster.
func _build_slabs() -> void:
	var height_fracs: Array = [0.30, 0.27, 0.24, 0.19]
	var width_mults: Array = [1.3, 1.12, 0.98, 0.82]
	var cum: float = 0.0
	for i in SLABS:
		var h: float = WALL_SIZE.y * float(height_fracs[i]) * randf_range(0.92, 1.08)
		var w: float = WALL_SIZE.x * float(width_mults[i]) * 0.5 * randf_range(0.9, 1.08)
		var ox: float = randf_range(-5.0, 5.0)
		var y_bot: float = -cum
		var y_top: float = y_bot - h
		# Irregular chipped heptagon: side bulges + a bumpy top ridge.
		var poly := PackedVector2Array([
			Vector2(ox - w, y_bot),
			Vector2(ox - w - randf_range(2.0, 7.0), lerpf(y_bot, y_top, randf_range(0.3, 0.5))),
			Vector2(ox - w * 0.88 + randf_range(-3.0, 3.0), y_top + randf_range(0.0, 4.0)),
			Vector2(ox + randf_range(-7.0, 7.0), y_top - randf_range(1.0, 6.0)),
			Vector2(ox + w * 0.9 + randf_range(-3.0, 3.0), y_top + randf_range(0.0, 4.0)),
			Vector2(ox + w + randf_range(2.0, 7.0), lerpf(y_bot, y_top, randf_range(0.45, 0.65))),
			Vector2(ox + w * 0.95, y_bot),
		])
		_slab_polys.append(poly)
		_slab_base_y.append(y_bot)
		_slab_delay.append(float(i) * SLAB_STAGGER)
		_slab_locked.append(false)
		cum += h * 0.94  # slight overlap: slabs sit pressed into each other
	_stack_h = cum


## Ease-out-back: overshoots ~10% then settles — the "slab pops past its seat
## and slams down into place" read that makes the rise feel slam-driven.
func _rise_ease(u: float) -> float:
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	var t: float = u - 1.0
	return 1.0 + c3 * t * t * t + c1 * t * t


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _sliding and not _crumbling:
		_process_slide(delta)
		if _elapsed < 0.0:  # despawned mid-slide (off-map)
			return
	elif not _crumbling:
		_process_rise_locks()
		if _elapsed >= RISE_TIME + LIFETIME:
			_begin_crumble()
	if _crumbling and _elapsed >= RISE_TIME + LIFETIME + CRUMBLE_TIME:
		queue_free()
		return
	queue_redraw()


## Per-slab "lock" beat: when a slab finishes its pop it lands with a puff + a
## small shake, so the whole raise reads as four quick impacts, not one tween.
func _process_rise_locks() -> void:
	if _elapsed > RISE_TIME + SLAB_RISE:
		return
	for i in SLABS:
		if _slab_locked[i]:
			continue
		if _elapsed >= _slab_delay[i] + SLAB_RISE:
			_slab_locked[i] = true
			var base_world := _floor_base + Vector2(0.0, _slab_base_y[i])
			CombatVfx.spawn_burst(get_parent(), base_world, Color(0.8, 0.6, 0.38, 0.7),
				Color(0.4, 0.28, 0.15, 0.0), 6, 0.3, 50.0, 140.0, 1.2, 2.8)
			Juice.shake_camera(2.5)


func _begin_crumble() -> void:
	_crumbling = true
	_sliding = false
	_primed = false
	remove_from_group("shoveable")
	if _collider != null:
		_collider.set_deferred("disabled", true)  # stops blocking once it crumbles
	DebrisChunk.spawn_burst(get_parent(), _floor_base - Vector2(0.0, WALL_SIZE.y * 0.5),
		Color(0.5, 0.38, 0.22), DEBRIS_COUNT, Vector2.DOWN, 200.0)
	ScorchDecal.spawn(get_parent(), _floor_base, WALL_SIZE.x * 0.9, "crack",
		Color(0.6, 0.45, 0.28, 0.55), 6.0)
	Juice.shake_camera(5.0)
	Sfx.play("enemy_death", -2.0, 0.1)


# ---- the slide (shoved wall as a projectile) ----

func _process_slide(delta: float) -> void:
	var prev_front_x: float = _front_edge_x()
	var step: Vector2 = _slide_dir * _slide_speed * delta
	_floor_base += step
	_slide_traveled += step.length()
	if _body != null:
		_body.global_position = _floor_base
	_plow_enemies()
	_smash_props()
	_grind_t -= delta
	if _grind_t <= 0.0:
		_grind_t = GRIND_DUST_INTERVAL
		# Grinding dust boils up off the trailing base edge the whole slide.
		CombatVfx.spawn_burst(get_parent(),
			_floor_base - _slide_dir * WALL_SIZE.x * 0.55 + Vector2(0.0, randf_range(-8.0, 0.0)),
			Color(0.75, 0.58, 0.38, 0.7), Color(0.4, 0.28, 0.15, 0.0),
			5, 0.35, 40.0, 120.0, 1.4, 3.2, 0.0, 0.0, false, -_slide_dir + Vector2.UP * 0.6, 40.0)
	if _hit_world(prev_front_x):
		_slam_stop()
	elif _slide_traveled >= MAX_SLIDE:
		# Nothing stopped it — the wall grinds off the map and is gone.
		CombatVfx.spawn_burst(get_parent(), _floor_base, DUST_TINT,
			Color(0.4, 0.28, 0.15, 0.0), 10, 0.4, 50.0, 140.0, 1.5, 3.5)
		_elapsed = -1.0
		queue_free()


func _front_edge_x() -> float:
	return _floor_base.x + _slide_dir.x * WALL_SIZE.x * 0.5


## Solid world geometry across the travelled front edge (3 heights, layer 1).
## Destructible crates are NOT solid to a shoved wall — _smash_props plows them —
## so the ray skips anything in the "destructible" group.
func _hit_world(prev_front_x: float) -> bool:
	var world: World2D = get_world_2d()
	if world == null:
		return false
	var front_x: float = _front_edge_x() + _slide_dir.x * 6.0
	var excludes: Array[RID] = []
	if _body != null:
		excludes.append(_body.get_rid())
	for hy: float in [14.0, WALL_SIZE.y * 0.5, WALL_SIZE.y - 16.0]:
		var y: float = _floor_base.y - hy
		var q := PhysicsRayQueryParameters2D.create(
			Vector2(prev_front_x, y), Vector2(front_x, y), 1)
		q.exclude = excludes
		q.hit_from_inside = true
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Node = hit.get("collider") as Node
		if n != null and _is_smashable(n):
			continue  # smashed through, not stopped
		return true
	return false


## True for anything a shoved wall grinds THROUGH rather than stops against.
## Group membership alone is not enough: `_smash_props()` runs earlier in the
## same frame, and a cover block that just collapsed leaves the "destructible"
## group immediately while its collider lives until the deferred free — so the
## ray would see a group-less solid body and slam the wall to a halt on the very
## crate it just broke. Anything already queued for deletion is smashed, gone.
func _is_smashable(n: Node) -> bool:
	return n.is_in_group("destructible") or n.is_queued_for_deletion()


## How much of a victim's parry window counts against the plow. Same two-line
## expression as every other spectacle, so the ult policy cannot drift per spell.
func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT 		else SpellDeflect.WINDOW_NORMAL


## Anything caught in the wall's path gets plowed ONCE: real damage + a heavy
## up-and-out launch. One hit per enemy per slide (no per-frame damage ticks).
func _plow_enemies() -> void:
	var hw: float = WALL_SIZE.x * 0.5 + PLOW_PAD
	# hostiles(): the shover stands directly behind the wall they just punched, i.e.
	# inside the plow band from the first frame of the slide.
	for e: Node in SpellTargets.hostiles(self, target_group):
		if not e is Node2D or not is_instance_valid(e):
			continue
		var p: Vector2 = (e as Node2D).global_position
		if absf(p.x - _floor_base.x) > hw:
			continue
		if p.y > _floor_base.y + 14.0 or p.y < _floor_base.y - WALL_SIZE.y - 14.0:
			continue
		var id: int = e.get_instance_id()
		if _plowed.has(id):
			continue
		# ⚠ MARKED PLOWED EVEN WHEN THE GUARD EATS IT, and that is a design decision
		# rather than an ordering accident. The wall keeps grinding after the parry,
		# so without the mark the very next frame would re-test the same body and
		# collect the hit the moment the 0.16 s window lapsed — a correct read would
		# buy three frames instead of the exchange. One press turns one ram, once.
		_plowed[id] = true
		# ⚠ DEFLECTABLE — and COUNTED before it was written, because it was not.
		# `tools/slice_test_owned_spell_deflect.gd` measured a raised guard eating 0
		# of this plow's 40 damage. A wall grinding at 820 px/s is the heaviest thing
		# the two-beat can do to somebody and it went through a raised guard as if the
		# guard were not there.
		#
		# It is the `resolve()` path and NOT `reflect()`, despite the wall genuinely
		# travelling — SpellDeflect's split is about whether the thing can be SENT
		# BACK, and a 44 x 124 slab of stone bouncing off a parry into reverse is the
		# ram's whole physics story (plow marks, slam-stop, grind dust) running
		# backwards. The guard turns the hit aside; the wall keeps going.
		var dealt: int = SpellDeflect.resolve(e, SHOVE_DAMAGE, _slide_dir,
			SpellTargets.aim_point(e), _deflect_window())
		if dealt <= 0:
			continue   # the guard turned the mass aside: no damage, no ailment, no launch
		if e.has_method("take_damage"):
			e.take_damage(dealt)
		if element_id >= 0 and e.has_method("apply_status"):
			e.apply_status(element_id)
		if e.has_method("apply_knockback"):
			e.apply_knockback((_slide_dir + Vector2.UP * 0.4).normalized() * SHOVE_KNOCKBACK)
		CombatVfx.spawn_burst(get_parent(), p, Color(0.9, 0.7, 0.45, 0.9),
			Color(0.45, 0.3, 0.16, 0.0), 12, 0.35, 80.0, 220.0, 1.3, 3.0,
			0.0, 0.0, false, _slide_dir, 60.0)
		Juice.on_hit({"dir": _slide_dir, "shake": 8.0, "kick": 5.0,
			"sfx": "melee_hit", "sfx_pitch": 0.08, "hitstop": 0.05})


## Crates and props in the path get smashed; enemy bolts get eaten by the mass.
func _smash_props() -> void:
	var hw: float = WALL_SIZE.x * 0.5 + PLOW_PAD
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if not prop is Node2D or not is_instance_valid(prop):
			continue
		var p: Vector2 = (prop as Node2D).global_position
		if absf(p.x - _floor_base.x) > hw + 20.0 or absf(p.y - _floor_base.y) > WALL_SIZE.y:
			continue
		if prop.has_method("damage_at"):
			prop.damage_at(SHOVE_DAMAGE * 2, p, _slide_dir)
		elif prop.has_method("take_damage"):
			prop.take_damage(SHOVE_DAMAGE * 2)
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if proj is Node2D and wall_distance((proj as Node2D).global_position) <= PLOW_PAD \
				and proj.has_method("consume"):
			proj.call("consume")


## The slide ends against real geometry: one HEAVY beat (shake + kick + hitstop
## + blast), a debris spray up the obstacle, and the wall immediately crumbles —
## a thrown wall is spent, it doesn't go back to being a barrier.
func _slam_stop() -> void:
	_sliding = false
	var front := Vector2(_front_edge_x(), _floor_base.y - WALL_SIZE.y * 0.4)
	DebrisChunk.spawn_burst(get_parent(), front, Color(0.5, 0.38, 0.22), 12,
		-_slide_dir + Vector2.UP * 0.8, 300.0)
	CombatVfx.spawn_burst(get_parent(), front, Color(0.95, 0.75, 0.5, 0.9),
		Color(0.45, 0.3, 0.16, 0.0), 24, 0.5, 90.0, 260.0, 1.6, 4.2)
	ScorchDecal.spawn(get_parent(), Vector2(front.x, _floor_base.y), WALL_SIZE.x * 0.8,
		"crack", Color(0.55, 0.4, 0.25, 0.6), 7.0)
	Juice.on_hit({"dir": _slide_dir, "shake": 13.0, "kick": 10.0, "zoom": 0.1,
		"sfx": "blast", "sfx_pitch": 0.1, "hitstop": 0.09})
	_elapsed = RISE_TIME + LIFETIME  # jump straight onto the crumble timeline
	_begin_crumble()


# ---- drawing ----

func _draw() -> void:
	if _elapsed < 0.0:
		return
	var alpha: float = 1.0
	if _crumbling:
		alpha = clampf(1.0 - (_elapsed - RISE_TIME - LIFETIME) / CRUMBLE_TIME, 0.0, 1.0)
	# Slam vibration while erupting: the whole stack judders, decaying to zero.
	var rise_u: float = clampf(_elapsed / RISE_TIME, 0.0, 1.0)
	var judder: float = (1.0 - rise_u) * 2.4
	var shake_off := Vector2(sin(_elapsed * 80.0) * judder, 0.0)
	# Sliding lean: the top of the stack trails the motion — mass reads in the tilt.
	var lean_px: float = -_slide_dir.x * 9.0 if _sliding else 0.0
	var top_slab: int = -1
	for i in SLABS:
		var u: float = clampf((_elapsed - _slab_delay[i]) / SLAB_RISE, 0.0, 1.0)
		if u <= 0.02:
			break
		top_slab = i
		var s: float = _rise_ease(u)
		var base_y: float = _slab_base_y[i]
		var poly: PackedVector2Array = _slab_polys[i]
		var pts := PackedVector2Array()
		for v in poly:
			var y: float = base_y + (v.y - base_y) * s
			var lean: float = lean_px * clampf(-y / maxf(_stack_h, 1.0), 0.0, 1.0)
			pts.append(_floor_base + shake_off + Vector2(v.x + lean, y))
		draw_colored_polygon(pts, Color(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b, alpha))
		# Lit face wedge (upper-left half catches the light) — gives each slab volume.
		var face := PackedVector2Array([pts[0], pts[1], pts[2], pts[3]])
		draw_colored_polygon(face, Color(FACE_COLOR.r, FACE_COLOR.g, FACE_COLOR.b, 0.85 * alpha))
		# Dark seams around the whole slab: chunky stacked-block read.
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(SEAM_COLOR.r, SEAM_COLOR.g, SEAM_COLOR.b, alpha), 2.2, true)
		# Top ridge catches light hard.
		draw_line(pts[2], pts[3], Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, alpha), 3.2, true)
		draw_line(pts[3], pts[4], Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, alpha), 3.2, true)
	# HDR amber rim on the crown — the "you can interact with this" cue
	# (echoes BreakablePlatform; here it marks the wall as shoveable). PRIMED, the
	# SAME line pulses hot and thick rather than a second highlight appearing: the
	# wall wakes up. It rides the per-frame queue_redraw() _process already does,
	# so the tell costs nothing beyond two multiplies.
	if top_slab >= 0:
		var pulse: float = (0.5 + 0.5 * sin(_elapsed * PRIME_PULSE_HZ * TAU)) if _primed else 0.0
		var crown: PackedVector2Array = _slab_polys[top_slab]
		var cb: float = _slab_base_y[top_slab]
		var cu: float = clampf((_elapsed - _slab_delay[top_slab]) / SLAB_RISE, 0.0, 1.0)
		var cs: float = _rise_ease(cu)
		var a := _floor_base + shake_off + Vector2(crown[2].x + lean_px, cb + (crown[2].y - cb) * cs)
		var b := _floor_base + shake_off + Vector2(crown[4].x + lean_px, cb + (crown[4].y - cb) * cs)
		var rim: Color = RIM_COLOR * (1.0 + PRIME_GLOW * pulse)
		var amber: Color = AMBER_RIM * (1.0 + PRIME_GLOW * pulse)
		draw_line(a, b, Color(rim.r, rim.g, rim.b, alpha * 0.9), 2.0 + 2.4 * pulse, true)
		draw_line(a, (a + b) * 0.5, Color(amber.r, amber.g, amber.b, alpha * 0.8),
			3.4 + 3.0 * pulse, true)
	# Dust skirt at the base; while sliding it smears out behind the wall.
	draw_circle(_floor_base + shake_off, WALL_SIZE.x * 0.8,
		Color(0.55, 0.42, 0.28, 0.35 * alpha), true, -1.0, true)
	if _sliding:
		for k in 3:
			var trail := _floor_base - _slide_dir * WALL_SIZE.x * (0.7 + 0.55 * float(k))
			draw_circle(trail + Vector2(0.0, -4.0 - 3.0 * float(k)),
				WALL_SIZE.x * (0.5 - 0.1 * float(k)),
				Color(0.6, 0.46, 0.3, (0.3 - 0.08 * float(k)) * alpha), true, -1.0, true)
