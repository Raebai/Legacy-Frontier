class_name BoulderHurl
extends Node2D
## Earthbending BOULDER HURL. The caster rips a boulder up out of the ground
## (rise + rubble), it hangs a beat, then HURLS along the aim as a heavy tumbling
## rock. On impact: radius damage + HEAVY knockback, shatters into physics debris
## + dust, gouges the ground (crack + hole). Grounded earth move — no float.
## Instantiate .new(), add to the arena, call hurl(). Node sits at arena origin;
## everything is drawn in world coordinates (mirrors DivineRay/MeteorSigil).
##
## World contract (docs/spell-world-contract.md), all four parts:
##   SPAWN  — the rip point is the FLOOR under the caster (SpellWorld.floor_below)
##            and is refused if it would put the rock inside solid geometry.
##   TRAVEL — the segment JUST TRAVELLED is raycast every frame, so a fast rock
##            cannot tunnel through a wall; destructible cover in the path is
##            smashed and damaged rather than stopping it.
##   TARGETS— SpellTargets: silhouette-tested (a head at rock height registers)
##            and line-of-sight-gated (the blast does not reach round a wall).
##   DEFLECT— the boulder physically TRAVELS, so it takes the `reflect()` path,
##            not SpellDeflect.resolve: you catch it and send it back at whoever
##            threw it. That is strictly the better fantasy and it is what
##            SpellDeflect's class docs name this spell for.
##
## ⚠ WHAT THE RADIUS AUDIT FOUND HERE (two mismatches, both fixed):
##   1. The in-flight hit test was `BOULDER_R + HIT_PAD` = 40 px against a rock
##      drawn at ~26 px — a 54 % over-reach, and a second forgiveness scheme
##      stacked on top of the target's own `hit_margin()`, which is exactly what
##      SpellTargets' stacking caveat forbids. HIT_PAD is gone; the test is the
##      drawn radius, plus whatever forgiveness the TARGET publishes for itself.
##   2. Every drawn element (shockwave, crater, scorch, floor probe) used the
##      CONST `IMPACT_RADIUS` while the damage used `_radius`, the caller's
##      value. They agree today only because the one shipping caster happens to
##      pass 84.0. Everything drawn now reads `_radius`.
##   3. The shockwave ring raced out to `IMPACT_RADIUS * 1.35` — 113 px of
##      drawn danger around an 84 px blast. It is now capped at `_radius` with a
##      boundary arc held at exactly `_radius`, which is the idiom BlinkStrike
##      already ships ("the boundary arc is held at exactly BLAST_RADIUS").

## THE DODGE BUDGET. RISE_TIME + HANG_TIME is how long the rock is visibly torn
## out of the ground and held at the apex before it moves at all — the window to
## get out of the lane. UNTESTED GUESS: 0.42 s total, deliberately longer than
## BlinkStrike's 0.30 tell because this one crosses the screen afterwards.
const RISE_TIME: float = 0.30      # rips up out of the ground
const HANG_TIME: float = 0.12      # hangs a beat at apex (anticipation)
const FLIGHT_SPEED: float = 900.0
## ⚠ THE SAFETY BOUND, AND ONLY THAT. A hurled rock should end on the thing it
## hits — a wall, cover, a body, the far side of the room — never by running out
## of an invisible allowance in open air. It used to be 900 px, which is roughly
## one screen: throw across an open floor and the boulder detonated on nothing,
## mid-flight, which is the maker's *"despawn in the air"* in its other form.
##
## Raised so that on the one-screen floors that ship the ARENA stops the rock and
## this number is never reached. It is kept rather than deleted because "travel
## until you hit something" has to terminate: `_check_flight_collision` sweeps the
## world every frame, but a rock thrown into a gap in the geometry would otherwise
## fly forever, and this project has an entity budget. Rejected: dropping the cap
## and relying on an arena-bounds test — there is no shared "am I still on the
## stage" query for spectacles, and inventing a second one here is exactly the
## divergence `SpellWorld` exists to prevent. UNTESTED GUESS.
const MAX_FLIGHT: float = 2200.0
const RISE_HEIGHT: float = 46.0
const BOULDER_R: float = 26.0
const IMPACT_RADIUS: float = 84.0
const DEFAULT_DAMAGE: int = 52
## ⚠ RETIRED — the shove is now derived from the spell's own damage and shelf via
## `SpellTier.push_for_spectacle`. Kept only as the record of what it used to be:
## every one of these sat BELOW `SlamPhysics.MIN_SLAM_SPEED` (250), so no spell in
## the game could throw a body hard enough to crack what it hit. Do not tune this
## number — nothing reads it. The band is in `SpellTier`.
const RETIRED_KNOCKBACK: float = 300.0
const CLEANUP_DELAY: float = 0.8
const DEBRIS_COUNT: int = 16
const SHOCKWAVE_TIME: float = 0.28

## How far down we look for the ground the rock is torn out of. Generous enough
## to reach the floor from a mid-jump cast, short enough that a caster standing
## over a pit reports "no floor" instead of ripping a boulder from a slab three
## screens below. UNTESTED GUESS.
const FLOOR_PROBE: float = 260.0
## Where the rock is torn out, relative to the caster, along the aim. Far enough
## that it is not drawn inside the caster's own body; near enough that it still
## reads as THEIR boulder. UNTESTED GUESS (unchanged from the original).
const RIP_OFFSET: float = 26.0
## How far OFF a struck surface the blast is resolved from. A wall impact point
## sits exactly on the wall's face, and a line-of-sight ray fired from a point
## lying on a collider can report an instant block against that very surface —
## which would cull everything the detonation should have hit. Pushing the blast
## centre out along the surface normal is also just physically right: the rock
## shatters against the wall, not inside it. UNTESTED GUESS.
const IMPACT_LIFT: float = 4.0
## The same idea as `IMPACT_LIFT`, for the CEILING probe in `_rise_height`: how far off
## the floor the upward ray starts, so it cannot instantly report the floor it is
## standing on. Small enough not to matter under a real ceiling.
const PROBE_LIFT: float = 6.0
## A reflected boulder gets its travel budget back so it can actually reach the
## thrower. 1.0 = the full MAX_FLIGHT again. UNTESTED GUESS.
const REFLECT_TRAVEL_FACTOR: float = 1.0

const BODY_COLOR: Color = Color(0.34, 0.24, 0.15)
const LIT_COLOR: Color = Color(0.62, 0.46, 0.26)
const RIM_COLOR: Color = Color(1.15, 0.92, 0.55)  # HDR highlight (blooms)
const DUST_TINT: Color = Color(0.55, 0.42, 0.28, 0.5)
const SHADOW_COLOR: Color = Color(0.18, 0.12, 0.07)  # the away-facing facets
const CRACK_COLOR: Color = Color(0.14, 0.09, 0.05, 0.85)
## Sun is up-and-left, matching the arena's lit-crust terrain shading.
const LIGHT_DIR: Vector2 = Vector2(-0.55, -0.835)
const CORE_SCALE: float = 0.52   # inner cap; the ring between it and the rim = facets
const TRAIL_LENGTH: int = 7      # dust puffs kept behind a rock in flight

## Who this boulder hurts. "enemy" while the caster owns it; a REFLECTED boulder
## flips to "hero", which is what makes catching one a counter-attack rather than
## a mere cancel (the same flip RiftDagger.reflect performs).
var target_group: String = "enemy"

var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(0.78, 0.55, 0.28)
var _radius: float = IMPACT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var element_id: int = -1
## Who cast this. Drives the reaction layer's same-owner rules, and keeps the
## thrower's own body from stopping the rock the instant it spawns. Cleared on a
## reflect, so a caught boulder can come back and hit the person who threw it.
var caster_node: Node = null
## Reaction weight — see SpellTier. Set by SpellCaster at cast time; the default
## middle shelf keeps an unset boulder evenly matched with every other
## un-adopted spectacle, exactly as it behaves today.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

var _elapsed: float = -1.0
var _ground_y: float = 0.0
var _pos: Vector2 = Vector2.ZERO
var _prev_pos: Vector2 = Vector2.ZERO
var _traveled: float = 0.0
var _spin: float = 0.0
var _flying: bool = false
var _reflected: bool = false
var _shockwave_elapsed: float = -1.0
var _shape: PackedVector2Array = PackedVector2Array()
var _cracks: Array[PackedVector2Array] = []   # local-space fissures, tumble with the body
var _trail: Array[Vector2] = []               # recent positions, oldest first
## Where the flight stopped, and what stopped it. Set by `_check_flight_collision`
## so `_process` does not have to re-derive the impact point.
var _hit_point: Vector2 = Vector2.ZERO
## The un-lifted world contact from `_check_flight_collision`, and the body it was on.
## A null collider means the rock detonated on a BODY, or ran out of flight, and never
## touched terrain at all — the one case the floor snap in `_shatter` is right for.
var _world_contact: Vector2 = Vector2.ZERO
var _world_collider: Object = null
## Measurement only, read by `tools/probe_destructible_hitpoint.gd`: how far the old
## floor-snapped carve point sat from the real contact. -1 until an impact resolves.
var contact_vs_floor_px: float = -1.0


func hurl(
	from: Vector2, aim: Vector2, color: Color = Color(0.78, 0.55, 0.28),
	radius: float = IMPACT_RADIUS, damage: int = DEFAULT_DAMAGE, _effect: String = "earth"
) -> void:
	_origin = from
	_dir = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	_color = color
	_radius = radius
	_damage = damage
	_elapsed = 0.0
	var skip: Array[RID] = SpellWorld.rids([caster_node])
	# Find the ground the boulder rips out of. Over a pit there IS no ground, and
	# the honest answer is caller-specific (see SpellWorld.floor_below's ⚠): this
	# spell is grounded earth, so it rips from just under the caster's own feet
	# rather than refusing to cast — the rock still exists, it just came from the
	# ledge you are standing on.
	var ground: Dictionary = SpellWorld.floor_below(from, FLOOR_PROBE, skip, self)
	_ground_y = (ground["position"] as Vector2).y if bool(ground["hit"]) else from.y + 30.0
	_pos = Vector2(from.x + _dir.x * RIP_OFFSET, _ground_y)
	# NOTHING MAY START INSIDE THE ENVIRONMENT. Ripping the rock out flush against
	# a wall would spawn it inside the wall and it would then "impact" on its first
	# frame from within solid rock. Fall back to directly under the caster, which
	# is where they are standing and therefore known to be free.
	if SpellWorld.is_blocked(_pos, BOULDER_R, skip, self):
		_pos = Vector2(from.x, _ground_y)
	_prev_pos = _pos
	_shape = _make_boulder(BOULDER_R)
	_cracks = _make_cracks(BOULDER_R)
	# Ground cracks open as the rock tears out.
	DebrisChunk.spawn_burst(get_parent(), Vector2(_pos.x, _ground_y), Color(0.5, 0.38, 0.22), 5, Vector2.UP, 200.0)
	CombatVfx.spawn_burst(get_parent(), Vector2(_pos.x, _ground_y), Color(0.85, 0.62, 0.35, 0.8),
		Color(0.4, 0.28, 0.15, 0.0), 14, 0.4, 60.0, 180.0, 1.4, 3.5)
	ScorchDecal.spawn(get_parent(), Vector2(_pos.x, _ground_y), BOULDER_R * 1.3, "crack",
		Color(0.5, 0.36, 0.22, 0.6), 7.0)  # the HOLE left in the ground
	# THE RIP MARK. Flat on the ground the rock is torn out of, not a gate in the
	# air: earth's whole tell in this game is that it comes from the floor and has no
	# light of its own, so a standing sigil would fight the family's identity. Short
	# hold — the mark is the hole opening, and the rock is gone a moment later.
	SpellSigil.open(self, Vector2(_pos.x, _ground_y), color, 0.9,
		false, Vector2.RIGHT, true, 0.14, 0.42)
	Juice.shake_camera(3.0)
	Sfx.play("earth", -4.0, 0.08)
	# Deflect path #1 (the reflect() half): a thing that physically travels can be
	# CAUGHT and sent back, so it advertises itself to the parry scans.
	add_to_group("deflectable_spell")
	# Join the reaction system. `reaction_active()` keeps it inert until it is
	# actually flying, so a rock still being torn free cannot annihilate anything.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.PROJECTILE, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- deflect contract (the reflect() half — see SpellDeflect's class docs) ----

## Where this spell physically IS, for the parry scans. The NODE parks at the
## arena origin and draws in world coordinates, so `global_position` is (0, 0)
## and would put every parry check at the top-left of the level.
func deflect_point() -> Vector2:
	return _pos


## Caught and sent back. Reversing the rock is only half of it: flipping
## `target_group` and clearing `caster_node` is what turns a block into a
## counter-attack — the boulder now hunts the side that threw it, and the
## thrower's own body no longer excludes itself from the travel ray.
##
## Deliberately silent: the parrier (Hero._try_parry / SpikeFigure._try_reflect)
## already plays the "ding", and a second one here would double it.
func reflect(new_dir: Vector2, color: Color) -> void:
	if _reflected or not _flying or _shockwave_elapsed >= 0.0:
		return
	_reflected = true
	_dir = new_dir.normalized() if new_dir != Vector2.ZERO else -_dir
	_color = color
	_traveled = MAX_FLIGHT * (1.0 - REFLECT_TRAVEL_FACTOR)
	caster_node = null
	target_group = "hero"
	_trail.clear()
	queue_redraw()


## AoE sweeps clear pending hazards through this (mirrors EnemyProjectile.consume
## and RiftDagger.consume): detonate where it stands.
func consume() -> void:
	if _shockwave_elapsed < 0.0:
		_impact(_pos)


# --- reaction contract (see SpellReactor) ------------------------------------

## World-space geometry built from `_pos` and the DRAWN radius — never from
## `global_position`, which is (0, 0) for this node.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(_pos, BOULDER_R)


## LOAD-BEARING: false while the rock is still being torn out of the ground and
## false once it has shattered, so a boulder can only react during the part of
## its life where it is a rock crossing the arena.
func reaction_active() -> bool:
	return _flying and _shockwave_elapsed < 0.0


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.PROJECTILE


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: the rock was eaten mid-flight. It goes WITHOUT its
## detonation — no damage, no crater, no shockwave.
func reaction_consume() -> void:
	queue_free()


# --- flight ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	_spin += delta * 9.0
	if _shockwave_elapsed >= 0.0:
		_shockwave_elapsed += delta
		queue_redraw()
		return
	if _elapsed < RISE_TIME:
		var u: float = _elapsed / RISE_TIME
		_pos.y = _ground_y - _rise_height() * (1.0 - pow(1.0 - u, 2.0))  # ease-out lift
	elif _elapsed < RISE_TIME + HANG_TIME:
		_pos.y = _ground_y - _rise_height()
	else:
		# FLIGHT
		if not _flying:
			_flying = true
			Sfx.play("melee_swing", -2.0, 0.1)
		_prev_pos = _pos
		_pos += _dir * FLIGHT_SPEED * delta
		_traveled += FLIGHT_SPEED * delta
		# Wake: keep the last few positions so _draw can taper dust behind it.
		_trail.append(_prev_pos)
		if _trail.size() > TRAIL_LENGTH:
			_trail.remove_at(0)
		if _check_flight_collision():
			_impact(_hit_point)
			return
		if _traveled >= MAX_FLIGHT:
			# The bound, not the design. Detonating here is still the right answer —
			# a rock that vanishes is worse than a rock that breaks — but reaching
			# this line at all means the throw crossed MAX_FLIGHT of open air, which
			# no shipping floor is wide enough to allow.
			_impact(_pos)
			return
	queue_redraw()


## How high the rock is torn before it is thrown, CLIPPED against whatever is
## above the rip point. Ripping a boulder up through a low ceiling would draw it
## inside the ceiling for the whole anticipation beat.
func _rise_height() -> float:
	# ⚠ THE PROBE STARTED ON THE FLOOR AND HIT THE FLOOR. Maker: *"boulder throw keeps
	# hitting the ground and not going anywhere"*.
	#
	# The rip point is `_ground_y` — a point lying EXACTLY on the floor collider — and
	# this file already documents the consequence twenty lines up, for `IMPACT_LIFT`:
	# "a line-of-sight ray fired from a point lying on a collider can report an instant
	# block against that very surface". This ceiling probe was doing precisely that. It
	# returned ~0, so the rock never rose, and a boulder at ground level flies along the
	# ground until `_check_flight_collision` raycasts its own travel segment straight
	# into the floor — which is the whole reported symptom, from one ray origin.
	#
	# Lifting the origin clear of the surface is the same fix `IMPACT_LIFT` already is;
	# the distance is measured back from the lifted origin so a REAL low ceiling still
	# clips the rise honestly.
	var base: Vector2 = Vector2(_pos.x, _ground_y - PROBE_LIFT)
	var up: Vector2 = base + Vector2.UP * RISE_HEIGHT
	var r: Dictionary = SpellWorld.first_solid(base, up,
		SpellWorld.rids([caster_node]), self)
	var head: float = float(r["distance"]) + PROBE_LIFT if bool(r["hit"]) else RISE_HEIGHT
	# ⚠ AND NEVER BELOW THE ROCK'S OWN RADIUS. A rise shorter than the boulder draws it
	# half inside the ground it was torn from and puts its flight line back into the
	# floor. Under a genuinely low ceiling this prefers "clips the ceiling slightly" to
	# "the spell does not work", which is the right way round.
	return maxf(head, BOULDER_R + 2.0)


## Did the rock meet anything on the segment it JUST travelled?
##
## ORDER MATTERS AND IT USED TO BE WRONG. The world is asked FIRST: previously
## the enemy scan ran first, so a rock could "hit" someone standing on the far
## side of a wall it had not reached yet. Now the wall stops it at the wall, and
## only a clear segment goes on to look for a victim.
##
## Raycasting the segment JUST TRAVELLED (rather than probing forward from the
## new position) is what makes this un-tunnellable: at 900 px/s the rock moves
## 15 px a frame and a 40 px-thin wall is trivially skipped by a point test.
func _check_flight_collision() -> bool:
	var skip: Array[RID] = SpellWorld.rids([caster_node])
	var world: Dictionary = SpellWorld.first_solid(_prev_pos, _pos, skip, self)
	# "Destroy what it can": destructible cover is torn THROUGH by a rock this
	# heavy, and everything it tore through comes back to be damaged.
	for prop: Node in (world["smashed"] as Array[Node]):
		_smash(prop, world["position"] as Vector2)
	if bool(world["hit"]):
		# Pushed IMPACT_LIFT out along the surface normal — see the constant.
		var n: Vector2 = world["normal"]
		_hit_point = (world["position"] as Vector2) + n.normalized() * IMPACT_LIFT \
			if n != Vector2.ZERO else world["position"]
		# ...and the RAW contact, kept separately and un-lifted. `_hit_point` is where the
		# SPECTACLE is staged (lifted clear of the surface so the burst is not half
		# buried); the carve needs the point the rock actually touched, and the two are
		# IMPACT_LIFT apart by construction. See `_shatter`.
		_world_contact = world["position"] as Vector2
		_world_collider = world["collider"]
		return true
	# Clear segment — now look for a body. `BOULDER_R` and nothing else: the drawn
	# rock's own radius, with the target's published `hit_margin()` added by
	# SpellTargets. No call-site pad (see the ⚠ in the class docs).
	var found: Array = SpellTargets.in_radius(_pos, BOULDER_R,
		get_tree().get_nodes_in_group(target_group), [caster_node], self)
	if found.is_empty():
		return false
	# Detonate where the ROCK is, not where the victim is: the blast radius covers
	# them either way, and the crater belongs under the rock.
	_hit_point = _pos
	return true


func _impact(at: Vector2) -> void:
	_pos = at
	if is_in_group("deflectable_spell"):
		remove_from_group("deflectable_spell")  # no longer catchable — it has landed
	_apply_impact_damage(at)
	_shatter(at)
	_shockwave_elapsed = 0.0
	Juice.on_hit({"dir": _dir, "shake": 13.0, "kick": 10.0, "zoom": 0.11,
		"sfx": "blast", "sfx_pitch": 0.1, "hitstop": 0.1})
	Juice.zoom_pull_camera(0.12, 0.3, 0.12, 0.45)
	# A rock arriving is mass, not magic: the white blow-out, on this hurl's own
	# shelf. Camera + freeze suppressed — the two lines above already fired both,
	# and a second freeze here is precisely the stacking that turns a volley of
	# these into slow motion.
	Juice.tier_frame(spell_tier, at, element_id,
		{"style": ImpactFrame.Style.BLOWOUT,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


func _shatter(at: Vector2) -> void:
	# Ground residue is snapped to the FLOOR, and SKIPPED entirely over a pit —
	# a crater hanging in mid-air is the same bug as a meteor under the floor,
	# seen from the other side (GroundCrater already makes this call).
	var ground: Dictionary = SpellWorld.floor_below(at, _radius * 2.2,
		SpellWorld.rids([caster_node]), self)
	CombatVfx.spawn_burst(get_parent(), at, Color(0.85, 0.62, 0.35, 0.9), Color(0.4, 0.28, 0.15, 0.0),
		30, 0.5, 80.0, 260.0, 1.8, 5.0)
	if not bool(ground["hit"]):
		return
	var floor_pos: Vector2 = ground["position"]
	DebrisChunk.spawn_burst(get_parent(), floor_pos, Color(0.5, 0.38, 0.22), DEBRIS_COUNT, _dir, 340.0)
	ScorchDecal.spawn(get_parent(), floor_pos, _radius * 0.6, "crack",
		Color(0.6, 0.45, 0.28, 0.6), 8.0)
	# ...and the rock the boulder landed on actually goes. This is the one carve site
	# in the roster with a story reason to exist: the spell RIPPED this stone out of the
	# ground a second ago, so a version where it lands and the floor is pristine is the
	# spell arguing with itself.
	#
	# `floor_pos`, NOT `at` — the impact point can be a body's chest in mid-air, and the
	# two lines above already snapped the residue down to the ground for exactly that
	# reason. Carving at `at` would open holes in the sky over a pit; the `ground["hit"]`
	# early-return above is what makes `floor_pos` safe to use here at all.
	# ⚠ THE CARVE POINT MOVED, AND THE COMMENT ABOVE IT ARGUED FOR THE WRONG ONE.
	# `floor_pos` is a downward snap from the impact, defended above by the mid-air
	# case: "the impact point can be a body's chest". True — but only WHEN THE ROCK HIT
	# A BODY. When it hit TERRAIN, `_check_flight_collision` already held the exact
	# contact from its own raycast and this threw it away, then re-derived a point
	# straight down from a position that had been pushed IMPACT_LIFT out along the
	# surface normal. On a flat deck the two agree within a few px; on a terrace FACE or
	# the arena rim — any vertical surface — the snap walks the hole down the wall to
	# the floor at its foot, which is *"kept accurate to where it hit"* failing in the
	# most visible way available.
	#
	# `contact_vs_floor_px` records the disagreement in px so the probe can report it
	# rather than anyone arguing about it from the geometry.
	var carve_at: Vector2 = floor_pos
	var carve_on: Object = ground.get("collider")
	if _world_collider != null and is_instance_valid(_world_collider):
		contact_vs_floor_px = _world_contact.distance_to(floor_pos)
		carve_at = _world_contact
		carve_on = _world_collider
	#
	# ⚠ THE FOOTPRINT IS `BOULDER_R`, THE ROCK, NOT `_radius`, THE BLAST. The maker's
	# worked example is physical — *"a boulder of course should take a piece out of the
	# floor"* — and what takes the piece is the stone, not the pressure wave around it.
	# `_radius` is the damage/knockback reach and is several times wider; sizing the
	# crater off it would have the rock excavate ground it never touched, which is the
	# same error as a beam digging wider than the beam. A 26 px rock leaves a ~35 px
	# hole: visibly a bite the rock's own size, and visibly smaller than a meteor's.
	DestructibleStage.carve_from_body(carve_on, _damage, carve_at, -_dir,
		BOULDER_R, self)


## Blast damage. `_radius` — the same number the shockwave and the boundary arc
## are drawn at — with line of sight on, so the blast cannot reach round a wall.
func _apply_impact_damage(at: Vector2) -> void:
	var skip: Array = [caster_node]
	for enemy: Node in SpellTargets.in_radius(at, _radius,
			get_tree().get_nodes_in_group(target_group), skip, self):
		var away: Vector2 = ((enemy as Node2D).global_position - at).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		# The DETONATION does not travel — there is nothing to send back once the
		# rock has already shattered — so the blast half routes through
		# SpellDeflect.resolve and a well-timed guard eats it. (Catching the rock
		# IN FLIGHT is the other, better answer: see `reflect`.)
		var dealt: int = SpellDeflect.resolve(enemy, _damage, _dir,
			SpellTargets.aim_point(enemy))
		if dealt > 0 and enemy.has_method("take_damage"):
			enemy.take_damage(dealt)
		if dealt <= 0:
			continue  # parried: the guard ate the ailment and the shove too
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(away * SpellTier.push_for_spectacle(
				float(dealt), SpellTier.PUSH_TIER[SpellTier.Tier.HEAVY]))
	for prop: Node in SpellTargets.in_radius(at, _radius,
			get_tree().get_nodes_in_group("destructible"), skip, self):
		_smash(prop, at)
	for proj: Node in SpellTargets.in_radius(at, _radius,
			get_tree().get_nodes_in_group("enemy_projectile"), skip, self):
		if proj.has_method("consume"):
			proj.call("consume")


## Damage one destructible, preferring the localized `damage_at` so cover breaks
## where the rock struck it. Shared by the travel smash and the blast.
func _smash(prop: Node, at: Vector2) -> void:
	if prop == null or not is_instance_valid(prop) or prop.is_queued_for_deletion():
		return
	if prop.has_method("damage_at"):
		prop.call("damage_at", _damage, at, _dir)
	elif prop.has_method("take_damage"):
		prop.call("take_damage", _damage)


## An irregular chunk, not a polygon. The old version spaced 7 verts evenly and
## only jittered the radius, which reads as a slightly-dented heptagon — the
## "flat brown hexagon" look. Jittering the ANGLES too gives uneven edge lengths,
## which is what makes a silhouette read as broken rock.
func _make_boulder(rad: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = 9
	for i in n:
		var a: float = TAU * (float(i) + randf_range(-0.32, 0.32)) / float(n)
		pts.append(Vector2.from_angle(a) * rad * randf_range(0.68, 1.15))
	return pts


## Two or three fissures across the chunk, in LOCAL space so they rotate with it.
func _make_cracks(rad: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for c in randi_range(2, 3):
		var a: float = randf() * TAU
		var start: Vector2 = Vector2.from_angle(a) * rad * randf_range(0.55, 0.95)
		var line := PackedVector2Array([start])
		var heading: float = a + PI + randf_range(-0.6, 0.6)
		for seg in 3:
			heading += randf_range(-0.5, 0.5)
			line.append(line[line.size() - 1] + Vector2.from_angle(heading) * rad * randf_range(0.2, 0.4))
		out.append(line)
	return out


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _shockwave_elapsed >= 0.0:
		_draw_shockwave()
		return
	var rot: Transform2D = Transform2D(_spin, _pos)
	var n: int = _shape.size()
	# 1) Dust TRAIL behind the rock — a tapering line of puffs along the recent
	# path, so a thrown boulder leaves a wake instead of one smear circle.
	for i in _trail.size():
		var age: float = float(i + 1) / float(_trail.size())   # 1.0 = newest
		draw_circle(_trail[i], BOULDER_R * (0.26 + 0.52 * age),
			Color(DUST_TINT.r, DUST_TINT.g, DUST_TINT.b, DUST_TINT.a * age * 0.75),
			true, -1.0, true)
	# 2) Faceted body. Each rim edge gets its own quad running back to an inner
	# cap, shaded by which way that facet points relative to the sun. Because the
	# facets are built from the ROTATED verts, the shading tumbles with the rock —
	# that turning light is what sells mass. A single flat fill with a painted-on
	# highlight (the old draw) stays visually still no matter how fast it spins.
	for i in n:
		var a: Vector2 = rot * _shape[i]
		var b: Vector2 = rot * _shape[(i + 1) % n]
		var ca: Vector2 = rot * (_shape[i] * CORE_SCALE)
		var cb: Vector2 = rot * (_shape[(i + 1) % n] * CORE_SCALE)
		var facing: Vector2 = ((a + b) * 0.5 - _pos).normalized()
		var lam: float = clampf(facing.dot(LIGHT_DIR) * 0.5 + 0.5, 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([ca, a, b, cb]),
			SHADOW_COLOR.lerp(LIT_COLOR, lam * lam))
	# 3) Inner cap — the flat top plane of the chunk.
	var cap := PackedVector2Array()
	for i in n:
		cap.append(rot * (_shape[i] * CORE_SCALE))
	draw_colored_polygon(cap, BODY_COLOR.lerp(LIT_COLOR, 0.28))
	# 4) Fissures across the face.
	for crack: PackedVector2Array in _cracks:
		var world := PackedVector2Array()
		for p: Vector2 in crack:
			world.append(rot * p)
		draw_polyline(world, CRACK_COLOR, 1.4, true)
	# 5) HDR rim on the sun-facing silhouette edges — the only part that blooms,
	# so the rock catches light without the whole mass glowing.
	for i in n:
		var a: Vector2 = rot * _shape[i]
		var b: Vector2 = rot * _shape[(i + 1) % n]
		if ((a + b) * 0.5 - _pos).normalized().dot(LIGHT_DIR) > 0.35:
			draw_line(a, b, RIM_COLOR, 1.6, true)


## The detonation, drawn at EXACTLY the radius that damaged. The expanding ring
## stops at `_radius` instead of racing 35 % past it, and a boundary arc is held
## at `_radius` for the whole fade so the extent stays legible after the wave has
## passed — the treatment BlinkStrike already ships for the same reason.
func _draw_shockwave() -> void:
	var t: float = clampf(_shockwave_elapsed / SHOCKWAVE_TIME, 0.0, 1.0)
	if t >= 1.0:
		return
	var alpha: float = 1.0 - t
	draw_arc(_pos, _radius, 0.0, TAU, 48, Color(0.85, 0.6, 0.3, 0.35 * alpha), 2.0, true)
	var r: float = lerpf(8.0, _radius, t)
	draw_arc(_pos, r, 0.0, TAU, 48, Color(0.85, 0.6, 0.3, 0.9 * alpha), lerpf(9.0, 2.0, t), true)
	if t < 0.4:
		var flash: float = 1.0 - t / 0.4
		# Capped like `BlastSpell`'s — see the block there. A full-radius HDR fill is a
		# flat disc over everything standing in the blast, not a flash.
		draw_circle(_pos, _radius * flash * 0.52,
			Color(1.2, 0.95, 0.6, 0.26 * flash), true, -1.0, true)
