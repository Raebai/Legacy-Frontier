class_name IceWall
extends Node2D
## Cryomancer ICE WALL — a cluster of TRANSLUCENT crystal spires grows up out of
## the ground in the aim direction. You can see the arena through the crystal
## (low-alpha faceted fills), the edges and internal cracks catch light as HDR
## lines that bloom — it reads FRAGILE where the rock wall reads SOLID MASS.
## A StaticBody2D on collision layer 1 blocks enemy BODIES + enemy PROJECTILES
## for a few seconds; enemies pressed against it get CHILLED. It dies by
## SHATTERING: a shard-burst with a small AoE (damage + chill + knockback) —
## public shatter() is the Phase 3 interaction hook (fire beam / boulder /
## impact destroys it early), and natural expiry calls the same method.
## Instantiate .new(), add to arena, call raise_wall(). Draws in world coords.
##
## SHATTER CONTRACT (for the Phase 3 interaction layer):
##   * every standing ice wall is in the "ice_wall" group
##   * `shatter()` bursts it NOW (idempotent — safe to call twice)
##
## REACTION CONTRACT (see SpellReactor): this wall is a BARRIER of ICE, so the
## rows already authored for it — `shatter_ice_barrier` (a fire/holy beam or any
## physical impact pops it), `shrapnel_cone` (a thrown thing bursts it ALONG its
## flight), `breach` / `barrier_blocks` — all reach it the moment `raise_wall()`
## registers. They were authored, implemented and tested while this file did not
## implement the contract at all, which made every one of them unreachable.

const WALL_OFFSET: float = 90.0
const WALL_SIZE: Vector2 = Vector2(30.0, 130.0)  # collider thickness x height (slim vs rock)
const RISE_TIME: float = 0.30       # last spire finishes crystallising by here
const SHARD_GROW: float = 0.20      # one spire's grow time
const LIFETIME: float = 4.5
const SHATTER_TIME: float = 0.3     # ring flash after the burst, then gone
const SHARDS: int = 5               # many slim spires (rock is few fat slabs)
const CHILL_INTERVAL: float = 0.4   # re-chill cadence for anything touching it

## Shard-burst AoE — deliberately light (a defensive wall, not a bomb), but real
## enough that shattering it ON enemies is a play the interaction layer can use.
## SHATTER_RADIUS is BOTH the damaged radius and the radius the death ring is
## drawn out to (see _draw_shatter): the ring you see is exactly the ring that
## hurt. It used to be drawn to 1.2x, i.e. 24 px of ring promising reach the
## burst did not have.
const SHATTER_RADIUS: float = 120.0
const SHATTER_DAMAGE: int = 18
const SHATTER_KNOCKBACK: float = 300.0

## ── the reach contract ───────────────────────────────────────────────────────
## "the spells shouldn't be able to get out the radius". The widest thing this
## wall DRAWS while it stands is the frost pool on the ground, so nothing the
## standing wall does may reach past it. chill_contains() is the one test the
## chill uses, and tools/slice7_test_frost_field.gd asserts it stays inside.
const GROUND_POOL_RADIUS: float = WALL_SIZE.x * 1.3
## Contact slop on the chill box, x and y. Enemies are pushed up against the
## collider rather than overlapping it, so a touch of pad is what makes "pressed
## against the ice" chill at all — it is bounded by the pool radius above.
const CHILL_PAD: float = 14.0
const CHILL_Y_PAD: float = 12.0
## How far down to look for the ground under the wall's landing spot.
const FLOOR_PROBE: float = 220.0

## ── the reaction contract's one number ───────────────────────────────────────
## Half-width of the volume `reaction_shape()` publishes, and DELIBERATELY the
## same box `chill_contains()` already tests: the wall has ONE contact volume, and
## a second number saying "how close a spell has to be to count as hitting the
## ice" is exactly how the five drawn-vs-damaged mismatches in this codebase
## started. Reusing the chill box also inherits its guard for free —
## tools/slice7_test_frost_field.gd already asserts it never reaches past the
## drawn frost pool, so the shape a reaction resolves against cannot silently grow
## past the wall you can see.
##
## It is WIDER than the collider (15) on purpose: the crystal cluster is drawn out
## to roughly ±29 px, so a fire beam that visibly touches the outermost spire must
## shatter the wall rather than pass through a gap the player cannot see. UNTESTED
## GUESS only in the sense that every number here is — it is not a new one.
const REACTION_HALF_WIDTH: float = WALL_SIZE.x * 0.5 + CHILL_PAD

const FILL_COLOR: Color = Color(0.45, 0.75, 1.0)    # drawn at ~0.3 alpha: see-through
const CORE_COLOR: Color = Color(0.6, 0.88, 1.1)     # inner facet, slightly hot
const EDGE_COLOR: Color = Color(0.95, 1.45, 1.85)   # HDR cyan edge lines (bloom)
const CRACK_COLOR: Color = Color(1.4, 1.7, 2.0)     # HDR internal cracks
const GLINT_COLOR: Color = Color(1.6, 1.85, 2.1)    # HDR tip sparkle

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
var element_id: int = Elements.Element.ICE
## WHO RAISED THIS. Same name and shape as BeamSpell's and RockWall's
## `caster_node`, so the one question the reaction layer keeps asking — "is this
## mine?" — is asked the same way everywhere. Stamped by SpellCaster._stamp();
## null is a legal unowned wall (nothing in the barrier rows requires an owner,
## but a ward or an anti-friendly-fire row later might).
##
## ⚠ It has to be DECLARED to be stamped: `set()` on an undeclared property is a
## silent no-op, so before this line SpellCaster was stamping an owner onto this
## wall that went nowhere.
var caster_node: Node = null
## Reaction WEIGHT — a SpellTier.Tier, stamped by SpellCaster at cast time from
## the spell's own cast time / cooldown / cost. The shipped ice_wall is HEAVY,
## which is what puts it on the barrier ladder's middle rungs: an ULT beam
## BREACHES it, an evenly matched one is merely STOPPED, and fire pops it at any
## weight because the element story outranks the weight story.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
var _floor_base: Vector2 = Vector2.ZERO
var _color: Color = Color(0.55, 0.8, 1.0)
var _elapsed: float = -1.0
var _body: StaticBody2D = null
var _collider: CollisionShape2D = null
var _chill_tick: float = 0.0

# Crystal geometry, built once at raise: local-space polys with y=0 at the floor.
var _shard_polys: Array[PackedVector2Array] = []
var _shard_base_x: PackedFloat32Array = PackedFloat32Array()  # grow-scale pivot per spire
var _shard_delay: PackedFloat32Array = PackedFloat32Array()
var _cracks: Array[PackedVector2Array] = []  # internal fracture polylines
var _sparkle_t: float = 0.0

# Shatter state.
var _shattered: bool = false
var _shatter_elapsed: float = -1.0
var _shatter_center: Vector2 = Vector2.ZERO


func raise_wall(
	from: Vector2, aim: Vector2, color: Color = Color(0.55, 0.8, 1.0), _effect: String = "frost"
) -> void:
	_color = color
	# Plant the cluster on the actual ground (SpellWorld, not a private raycast —
	# see docs/spell-world-contract.md). Over a pit floor_point hands the point
	# back unchanged, which is the old behaviour.
	_floor_base = SpellWorld.floor_point(wall_center(from, aim, WALL_OFFSET), FLOOR_PROBE, [], self)
	_elapsed = 0.0
	_build_shards()
	add_to_group("ice_wall")  # Phase 3 finds shatter targets through this group
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
	# Frost mist as the crystals grow + an immediate chill on anything in the space.
	CombatVfx.spawn_burst(get_parent(), _floor_base, Color(0.75, 0.92, 1.0, 0.9),
		Color(0.4, 0.65, 1.0, 0.0), 18, 0.5, 50.0, 160.0, 0.8, 2.4, 0.0, 0.0, true)
	_chill_touching()
	# The frost sigil the shards grow out of — laid flat, like the rock wall's, so
	# the two walls read as the same KIND of answer in two different materials.
	SpellSigil.open(self, _floor_base, color, WALL_SIZE.x / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.14, 0.62)
	Juice.shake_camera(3.5)  # a chime of a cast, not the rock wall's ground-slam
	Sfx.play("ice", -3.0, 0.08)
	# Join the reaction system. Unlike BeamSpell (which registers during a charge
	# it is not yet allowed to react from) there is no telegraph to sit through
	# here: the blocking collider above is live on this very frame, so the wall is
	# a reactant from the moment it is raised. See reaction_active().
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.BARRIER, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) -----------------------------------

## World-space geometry, built from `_floor_base` — NOT from `global_position`,
## which is (0, 0) because this node draws in world coordinates. A wall is a
## standing box, so the honest primitive is a vertical CAPSULE up its extent.
##
## THE INSET. A capsule is a segment inflated by half its width, so its end caps
## stick out REACTION_HALF_WIDTH px past each endpoint. Handing it the raw base
## and tip would promise 29 px of reach above the spire tips (and 29 px
## underground) that the wall does not have — the same "24 px of ring promising
## reach the burst did not have" bug SHATTER_RADIUS was fixed for. Pulling both
## endpoints IN by the half-width makes the stadium span exactly base..base-height:
## the wall you can see. Clamped at half the height so a wall shorter than it is
## wide degenerates to a point rather than inverting.
func reaction_shape() -> Dictionary:
	var hw: float = REACTION_HALF_WIDTH
	var inset: float = minf(hw, WALL_SIZE.y * 0.5)
	return SpellGeometry.capsule(
		_floor_base + Vector2.UP * inset,
		_floor_base + Vector2.UP * (WALL_SIZE.y - inset),
		hw * 2.0)


## LOAD-BEARING, and a DELIBERATE departure from BeamSpell / RockPillar, which are
## both inert for their whole telegraph. Those two have nothing there yet during
## the tell. This wall's StaticBody2D is created at full size in `raise_wall()` and
## is already stopping bodies and enemy bolts throughout the 0.30 s crystallisation
## — so treating the rise as a telegraph would let a fire beam sail through a wall
## that is visibly, physically in its way. Active exactly while the collider
## blocks: from the raise until the wall shatters.
##
## False once `_shattered` because what is left then is a ring flash and a cloud of
## shards, not a barrier — and because it is what stops a wall popped by one
## reaction being found again by the next.
func reaction_active() -> bool:
	return _elapsed >= 0.0 and not _shattered


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.BARRIER


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction — and spent through the wall's OWN authored death, not a
## private teardown. `shatter()` is the one way this wall dies (natural expiry
## calls it too), it leaves the "ice_wall" group, disables the collider, fires the
## shard burst and frees on its own timeline; a second path would be how a wall
## ends up freed while still grouped, or still blocking, or silent.
##
## Note ReactionOutcomes._break() would have found `shatter()` on its own via its
## legacy fallback — but only while `reaction_consume` was absent, because
## `reaction_consume` always wins when both exist. Delegating here is what keeps
## the fallback and the contract saying the same thing.
func reaction_consume() -> void:
	shatter()


## Pure geometry (testable): where the wall lands relative to the caster + aim.
static func wall_center(from: Vector2, aim: Vector2, offset: float = WALL_OFFSET) -> Vector2:
	var d: Vector2 = aim.normalized()
	if d == Vector2.ZERO:
		d = Vector2.RIGHT
	return from + d * offset


## Is `p` touching the standing wall? Pure + static so the reach contract is
## provable headlessly (both the positive case and, more importantly, the
## just-outside NEGATIVE case). `floor_base` is the wall's base on the ground;
## the box runs UP from there, matching the collider and the drawn spires.
static func chill_contains(floor_base: Vector2, p: Vector2) -> bool:
	if absf(p.x - floor_base.x) > WALL_SIZE.x * 0.5 + CHILL_PAD:
		return false
	return p.y <= floor_base.y + CHILL_Y_PAD \
		and p.y >= floor_base.y - WALL_SIZE.y - CHILL_Y_PAD


## Is `p` caught in the shard burst? Same reason as above — and this is the exact
## radius the death ring is drawn to, so drawn and damaged cannot drift apart.
static func shatter_contains(center: Vector2, p: Vector2) -> bool:
	return center.distance_to(p) <= SHATTER_RADIUS


## Build the crystal cluster ONCE at raise: 5 slim pointed spires, tallest in
## the middle, leaning outward — a grown formation, nothing like rock's slabs.
func _build_shards() -> void:
	var xs: Array = [-0.8, -0.38, 0.0, 0.42, 0.85]
	var height_fracs: Array = [0.55, 0.82, 1.05, 0.78, 0.5]
	var base_ws: Array = [9.0, 12.0, 15.0, 12.0, 9.0]  # wide enough to have a glassy BODY
	for i in SHARDS:
		var bx: float = float(xs[i]) * 22.0 + randf_range(-2.0, 2.0)
		var h: float = WALL_SIZE.y * float(height_fracs[i]) * randf_range(0.92, 1.08)
		var w: float = float(base_ws[i]) * randf_range(0.9, 1.1)
		var lean: float = signf(float(xs[i])) * randf_range(0.04, 0.13) * h
		var tip := Vector2(bx + lean, -h)
		# Kite/spire: base -> left shoulder -> tip -> right shoulder -> base.
		_shard_polys.append(PackedVector2Array([
			Vector2(bx - w, 0.0),
			Vector2(bx - w * 0.8 + lean * 0.45, -h * randf_range(0.48, 0.58)),
			tip,
			Vector2(bx + w * 0.85 + lean * 0.5, -h * randf_range(0.42, 0.52)),
			Vector2(bx + w, 0.0),
		]))
		_shard_base_x.append(bx)
		_shard_delay.append(absf(float(xs[i])) * 0.12)  # centre crystallises first
		# One internal fracture polyline per spire: short kinked line catching light.
		var cy: float = -h * randf_range(0.3, 0.6)
		var crack_start := Vector2(bx - w * 0.4, cy)
		var kink := crack_start + Vector2(randf_range(2.0, 6.0), randf_range(-14.0, -8.0))
		var crack_end := kink + Vector2(randf_range(-5.0, 3.0), randf_range(-14.0, -7.0))
		_cracks.append(PackedVector2Array([crack_start, kink, crack_end]))


## PUBLIC SHATTER — the wall's one way to die. Fires the shard-burst (physics
## debris + additive motes + ring flash), a light AoE (damage + chill + knock
## away), eats enemy bolts caught in the burst, then fades the ring and frees.
## Idempotent so the interaction layer and natural expiry can race safely.
func shatter() -> void:
	if _shattered or _elapsed < 0.0:
		return
	_shattered = true
	_shatter_elapsed = 0.0
	_shatter_center = _floor_base - Vector2(0.0, WALL_SIZE.y * 0.45)
	remove_from_group("ice_wall")
	if _collider != null:
		_collider.set_deferred("disabled", true)  # shards don't block
	# The burst: glassy chunks arc out + a white-hot mote flash that blooms.
	DebrisChunk.spawn_burst(get_parent(), _shatter_center, Color(0.78, 0.92, 1.0), 22,
		Vector2.ZERO, 320.0)
	CombatVfx.spawn_burst(get_parent(), _shatter_center, Color(1.1, 1.4, 1.7, 0.95),
		Color(0.5, 0.75, 1.0, 0.0), 32, 0.5, 90.0, 300.0, 0.7, 2.2, 0.0, 0.0, true)
	CombatVfx.spawn_burst(get_parent(), _floor_base, Color(0.8, 0.93, 1.0, 0.7),
		Color(0.55, 0.75, 1.0, 0.0), 12, 0.6, 30.0, 90.0, 1.6, 3.4)  # lingering frost mist
	ScorchDecal.spawn(get_parent(), _floor_base, WALL_SIZE.x * 1.1, "crack",
		Color(0.7, 0.9, 1.0, 0.4), 5.0)
	# Shape says "in range", SpellWorld says "and not behind a wall" — the burst
	# must not leak through geometry its ring is drawn on the near side of. Our own
	# collider is excluded: it sits between the burst centre and everything, and
	# without the exclude the wall would shield the arena from its own shards.
	var skip: Array[RID] = SpellWorld.rids([_body])
	var in_range: Array = []
	# hostiles(): the wall stands at arm's length, so its shatter ring covers the
	# caster the moment friendly fire puts them in the scanned group.
	for e: Node in SpellTargets.hostiles(self, target_group):
		if e is Node2D and is_instance_valid(e) \
				and shatter_contains(_shatter_center, (e as Node2D).global_position):
			in_range.append(e)
	for e: Node in SpellWorld.filter_reachable(_shatter_center, in_range, skip, self):
		var p: Vector2 = (e as Node2D).global_position
		if e.has_method("take_damage"):
			e.take_damage(SHATTER_DAMAGE)
		if e.has_method("apply_status"):
			e.apply_status(element_id)
		if e.has_method("apply_knockback"):
			var away: Vector2 = (p - _shatter_center).normalized()
			e.apply_knockback((away if away != Vector2.ZERO else Vector2.UP) * SHATTER_KNOCKBACK)
	var bolts: Array = []
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if proj is Node2D and shatter_contains(_shatter_center, (proj as Node2D).global_position):
			bolts.append(proj)
	for proj: Node in SpellWorld.filter_reachable(_shatter_center, bolts, skip, self):
		if proj.has_method("consume"):
			proj.call("consume")
	Juice.on_hit({"dir": Vector2.UP, "shake": 9.0, "zoom": 0.06,
		"sfx": "ice", "sfx_pitch": 0.12, "hitstop": 0.05})
	# The wall coming apart gets a mark on its own shelf, tinted ICE — so a
	# shattering wall reads as a cold event on the screen and not as a generic
	# white pop. Camera + freeze suppressed (fired one line above).
	Juice.tier_frame(spell_tier, _shatter_center, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	queue_redraw()


## Chill any enemy overlapping the wall footprint (touching the ice). Runs on
## raise + on a cadence while the wall stands so lingering enemies keep freezing.
## No cover test here, unlike shatter(): this is CONTACT, inside a box a few
## pixels wider than the collider, and the only thing that could sit between the
## wall and something touching it is the wall itself.
func _chill_touching() -> void:
	for e: Node in SpellTargets.hostiles(self, target_group):
		if not e is Node2D or not is_instance_valid(e):
			continue
		if not chill_contains(_floor_base, (e as Node2D).global_position):
			continue
		if e.has_method("apply_status"):
			e.apply_status(element_id)


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	_sparkle_t += delta
	if _shattered:
		_shatter_elapsed += delta
		if _shatter_elapsed >= SHATTER_TIME:
			queue_free()
			return
		queue_redraw()
		return
	# Keep chilling anything pressed against the wall while it stands.
	_chill_tick -= delta
	if _chill_tick <= 0.0:
		_chill_tick = CHILL_INTERVAL
		_chill_touching()
	# Idle glitter: an occasional tiny mote flash off a random spire tip — the
	# "light lives inside this thing" read that sells crystal over painted blue.
	if fmod(_elapsed, 0.6) < delta and not _shard_polys.is_empty():
		var s: PackedVector2Array = _shard_polys[randi() % _shard_polys.size()]
		CombatVfx.spawn_burst(get_parent(), _floor_base + s[2], Color(1.3, 1.6, 1.9, 0.8),
			Color(0.6, 0.85, 1.0, 0.0), 3, 0.3, 10.0, 40.0, 0.5, 1.2, 0.0, 0.0, true)
	if _elapsed >= RISE_TIME + LIFETIME:
		shatter()  # the wall's own death IS the shatter
	queue_redraw()


## Ease-out-back (mild): the spire grows past its height a touch and settles —
## crystallisation, not construction.
func _grow_ease(u: float) -> float:
	var c1: float = 0.9
	var c3: float = c1 + 1.0
	var t: float = u - 1.0
	return 1.0 + c3 * t * t * t + c1 * t * t


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _shattered:
		_draw_shatter()
		return
	# Frost pool on the ground under the cluster (translucent, not a dust skirt).
	draw_circle(_floor_base, WALL_SIZE.x * 1.3, Color(0.7, 0.92, 1.0, 0.12), true, -1.0, true)
	draw_arc(_floor_base, WALL_SIZE.x * 1.3, PI, TAU, 24, Color(0.85, 0.97, 1.05, 0.25), 1.2, true)
	for i in _shard_polys.size():
		var u: float = clampf((_elapsed - _shard_delay[i]) / SHARD_GROW, 0.0, 1.0)
		if u <= 0.02:
			continue
		var s: float = _grow_ease(u)
		var widen: float = 0.55 + 0.45 * u  # base fills out as it grows
		var bx: float = _shard_base_x[i]
		var poly: PackedVector2Array = _shard_polys[i]
		var pts := PackedVector2Array()
		for v in poly:
			pts.append(_floor_base + Vector2(bx + (v.x - bx) * widen, v.y * s))
		# TRANSLUCENT body — the arena reads through it. This is the ice identity.
		draw_colored_polygon(pts, Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, 0.32))
		# Inner facet core: a smaller, slightly hotter wedge = refraction read.
		var core := PackedVector2Array()
		var centroid := (pts[0] + pts[2] + pts[4]) / 3.0
		for p in pts:
			core.append(centroid + (p - centroid) * 0.55)
		draw_colored_polygon(core, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.38))
		# HDR edges: full outline thin, light-side edge (base->shoulder->tip) hot.
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, 0.75), 1.2, true)
		draw_line(pts[0], pts[1], Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, 0.95), 2.0, true)
		draw_line(pts[1], pts[2], Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, 0.95), 2.0, true)
		# Internal crack (only once the spire is mostly grown) with a slow shimmer.
		if u > 0.8:
			var shimmer: float = 0.32 + 0.16 * sin(_sparkle_t * 5.0 + float(i) * 1.7)
			var crack: PackedVector2Array = _cracks[i]
			var cpts := PackedVector2Array()
			for c in crack:
				cpts.append(_floor_base + Vector2(bx + (c.x - bx) * widen, c.y * s))
			draw_polyline(cpts, Color(CRACK_COLOR.r, CRACK_COLOR.g, CRACK_COLOR.b, shimmer), 1.0, true)
		# Tip glint: a tiny pulsing HDR star.
		if u >= 1.0:
			var tip: Vector2 = pts[2]
			var g: float = 0.5 + 0.5 * sin(_sparkle_t * 4.0 + float(i) * 2.3)
			var gl: float = 2.5 + 2.5 * g
			var ga: float = 0.35 + 0.45 * g
			draw_line(tip + Vector2(-gl, 0), tip + Vector2(gl, 0),
				Color(GLINT_COLOR.r, GLINT_COLOR.g, GLINT_COLOR.b, ga), 1.0, true)
			draw_line(tip + Vector2(0, -gl), tip + Vector2(0, gl),
				Color(GLINT_COLOR.r, GLINT_COLOR.g, GLINT_COLOR.b, ga), 1.0, true)


## The death flash: an expanding HDR ring + radial shard streaks, gone in 0.3 s.
func _draw_shatter() -> void:
	var t: float = clampf(_shatter_elapsed / SHATTER_TIME, 0.0, 1.0)
	if t >= 1.0:
		return
	var alpha: float = 1.0 - t
	# Peaks at SHATTER_RADIUS exactly — the ring IS the radius that dealt damage.
	var r: float = lerpf(12.0, SHATTER_RADIUS, 1.0 - (1.0 - t) * (1.0 - t))
	draw_arc(_shatter_center, r, 0.0, TAU, 40,
		Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, 0.9 * alpha), lerpf(7.0, 1.0, t), true)
	for k in 6:
		var ang: float = TAU * float(k) / 6.0 + 0.4
		var d := Vector2.from_angle(ang)
		draw_line(_shatter_center + d * r * 0.55, _shatter_center + d * r * 0.95,
			Color(CRACK_COLOR.r, CRACK_COLOR.g, CRACK_COLOR.b, 0.6 * alpha), 1.4, true)
	if t < 0.35:
		var flash: float = 1.0 - t / 0.35
		draw_circle(_shatter_center, 40.0 * flash,
			Color(1.4, 1.7, 2.0, 0.4 * flash), true, -1.0, true)
