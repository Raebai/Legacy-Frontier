class_name SpellWorld
extends RefCounted
## Shared WORLD queries for spell effects — "what does the world put in the way?"
##
## SpellGeometry's counterpart, and the split between them is deliberate:
##   * SpellGeometry is PURE MATHS. It answers "do these two shapes touch, and
##     where". It never sees the physics world.
##   * SpellWorld TOUCHES THE PHYSICS WORLD. It answers "is there a wall between
##     these two points", "where is the floor under this spot", "is this
##     teleport destination inside solid rock".
## Keep that line clean: a function here that stops needing a World2D belongs in
## SpellGeometry, and a function there that starts needing one belongs here.
##
## WHY THIS FILE EXISTS — the #1 outstanding gameplay bug, in the maker's words:
##   "No spell may pass through geometry. Meteors currently fall THROUGH the
##    floor; nothing may end up below or inside the environment. A spell that
##    meets a wall, the ground, or cover should IMPACT there — and destroy what
##    it can. Every single spell should be interactive."
## and the rule they added while playtesting:
##   "the spells shouldn't be able to get out the radius"
##
## Today ~15 spectacles resolve damage with a radius/group query and never ask
## what is BETWEEN them and the target, and a dozen of them hand-roll their own
## private `_floor_below` (BlastSpell, EnergyNova, ZoneSpell, IceWall, RockWall,
## RockPillar, BoulderHurl, ShadowRoot, ShadowCrawler, RiftDagger, GroundCrater…
## all the same eight lines, all subtly divergent). Fixing that spell by spell
## would produce fifteen slightly-different raycasts and fifteen
## slightly-different bugs. So it is fixed ONCE, here, and every spectacle
## threads its spawn / travel / impact through it.
## `docs/spell-world-contract.md` is the adoption checklist for implementers.
##
## ⚠ THE TRAP THIS FILE IS BUILT AROUND — the same one SpellGeometry and
## SpellReactor shout about, and it is worth shouting a third time: spell
## spectacle nodes PARK AT THE ARENA ORIGIN and draw in world coordinates, so
## their `global_position` is (0,0) and is NOT where the effect is. So:
##
##     EVERY FUNCTION HERE TAKES EXPLICIT WORLD-SPACE Vector2 VALUES.
##     NOTHING HERE EVER READS A SPELL NODE'S TRANSFORM.
##
## A node is only ever accepted as `ctx` — a handle used to reach the right
## World2D, never as a position. Get this wrong and every ray in the game starts
## at the top-left of the arena: spells stop dead in mid-air for no visible
## reason, or (worse) report "clear" for a path that is solid rock. That is a bug
## which fails LOUD in the wrong direction, which is exactly the kind that eats a
## session. The one deliberate exception is `filter_reachable()`, which reads the
## `global_position` of TARGET BODIES — an enemy's transform genuinely is where
## the enemy is; a spectacle's transform is a lie. See the note on that function.
##
## ⚠ THE SECOND TRAP — DESTRUCTIBLES ARE SMASHED THROUGH, NOT TREATED AS WALLS.
## This one has already cost a session once (see RockWall._is_smashable). Group
## membership alone is NOT a sufficient test: a cover block that has just
## collapsed leaves the "destructible" group IMMEDIATELY, while its collider
## survives until the deferred free. A naive `is_in_group("destructible")` check
## therefore sees a group-less solid body and stops the spell dead on the very
## crate it just broke. The rule, baked in here so no future caller has to
## rediscover it:
##
##     SMASHED = is_in_group("destructible") OR is_queued_for_deletion()
##               (and a freed/invalid collider is smashed too — it isn't there)
##
## It is the DEFAULT everywhere, with `smash_destructibles = false` as the
## opt-out, rather than the other way round, so the safe behaviour is the one you
## get by not thinking about it.
##
## SOLID WORLD GEOMETRY IS COLLISION LAYER 1. That is the project's existing
## convention, not a new one: RuinPlatform/walls sit on layer 1,
## DestructibleTerrain and DestructibleFloor on layer 5 (bits 1+4 — they block
## movement AND take spell hits), BreakablePlatform on 5, DebrisChunk on its own
## layer 6 so falling rubble never blocks anything. A mask-1 ray therefore sees
## walls and destructible cover alike, which is precisely why the smash rule
## above is load-bearing rather than a nicety.
##
## THE RESULT DICTIONARY. Every query returns the SAME shape, always populated,
## never `{}`:
##     {
##       "hit":      bool,        did something solid stop the segment
##       "position": Vector2,     world point of impact; the clear endpoint when
##                                nothing was hit (see floor_below for its one
##                                documented deviation)
##       "normal":   Vector2,     surface normal; ZERO when nothing was hit
##       "collider": Object,      what was hit (null when nothing was) — callers
##                                need this to decide damage vs smash vs react
##       "rid":      RID,         the collider's RID, for chaining excludes
##       "distance": float,       travel along from->to before the impact. USE
##                                THIS to clip a beam's drawn length: for a thick
##                                query `position` is laterally offset and
##                                `from + dir * distance` is the honest endpoint
##       "smashed":  Array[Node], destructibles the segment tore through on the
##                                way, in the order it met them — damage them
##       }
## Returning a full dict rather than the engine's `{}`-on-miss forces no caller
## to re-derive the clear-path endpoint, which is exactly the duplication this
## file exists to delete.
##
## HOW IT REACHES THE PHYSICS SPACE FROM A STATIC CONTEXT. These are static
## functions with no node to call `get_world_2d()` on, so `space()` resolves the
## World2D the way SpellDeflect._arena() reaches the scene: `Engine.get_main_loop()
## as SceneTree`, then the root viewport's world. A `ctx` node, when given, wins —
## that is the only correct answer if an effect ever lives inside a SubViewport
## with its own world. If neither resolves (headless helper suites, a call during
## teardown, a spell built before it entered the tree) every function DEGRADES TO
## "NO HIT" and returns the clear-path result, so nothing crashes and nothing
## silently blocks. Degrading to "clear" rather than "blocked" is the deliberate
## choice: a headless test that gets a phantom wall is a mystery, whereas a
## headless test that gets no walls is just a world with no walls in it.

## Solid world geometry. See the layer note in the class docs.
const SOLID_MASK: int = 1
## How many destructibles ONE segment may tear through before we give up and call
## it stopped. A line of eight crates is already absurd; the cap exists so a
## pathological pile-up cannot turn one query into an unbounded loop.
## UNTESTED GUESS.
const MAX_PIERCE_STEPS: int = 8
## Default downward probe for `floor_below`. Long enough to find the floor from
## meteor-release height (MeteorSigil.SKY_HEIGHT is 360) with room to spare, short
## enough that a spell over a genuine pit reports "no floor" instead of finding
## some distant slab three screens down. UNTESTED GUESS.
const FLOOR_PROBE: float = 400.0
## Parallel rays used by a thick query when the caller does not say. Three is what
## RockWall._hit_world settled on for its wall front edge (bottom / middle / top)
## and it is the smallest count that catches a gap in the middle of a span.
## UNTESTED GUESS.
const THICK_SAMPLES: int = 3
## `filter_reachable` pulls its endpoint this far back toward the source before
## casting. A target standing flush against a wall (or with its origin at its feet,
## on the floor collider) would otherwise be culled by the very surface it is
## standing on. UNTESTED GUESS — if enemies behind cover start taking hits, this
## is the first number to shrink.
const REACH_PAD: float = 6.0
## Cap on colliders reported by a point/shape occupancy test. We only need to know
## whether ANY non-smashable thing is there, so a handful is plenty.
## UNTESTED GUESS.
const OCCUPANCY_MAX_RESULTS: int = 8
## Cap on samples in a ground-hugging path walk. 64 points across an arena-width
## crawl is roughly one sample every 25 px — finer than any drawn ground effect
## needs. UNTESTED GUESS.
const MAX_GROUND_SAMPLES: int = 64

const EPS: float = 0.00001

## One reusable circle for radius occupancy tests. Queries are synchronous and
## single-threaded, so a shared shape costs nothing and saves an allocation on a
## call that can happen every frame of a blink probe.
static var _probe_circle: CircleShape2D = null


# ---------------------------------------------------------------- world access

## The physics space to query, or null when there is none.
##
## `ctx` — ANY node that lives in the same world as the effect (pass `self`; it is
## free and it is the only correct answer inside a SubViewport). It is used ONLY
## to reach a World2D: this function does not read its position, and neither does
## anything else in this file. Duck-typed via `has_method` to match the codebase's
## `wall_distance` / `blink_to` / `consume` idiom, so a Viewport works as well as
## a CanvasItem.
##
## Falls back to the main loop's root viewport world — the same route
## SpellDeflect._arena() takes to find the scene from a static context. Returns
## null in a bare helper suite, which every caller below turns into "no hit".
static func space(ctx: Node = null) -> PhysicsDirectSpaceState2D:
	if ctx != null and is_instance_valid(ctx) and ctx.is_inside_tree() \
			and ctx.has_method(&"get_world_2d"):
		var w: World2D = ctx.call(&"get_world_2d") as World2D
		if w != null:
			return w.direct_space_state
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var rw: World2D = tree.root.world_2d
	return rw.direct_space_state if rw != null else null


## Is there a physics world to ask at all? Callers that want to skip a whole
## block of work headlessly can gate on this instead of inspecting a result.
static func has_world(ctx: Node = null) -> bool:
	return space(ctx) != null


## Collect collision RIDs for an exclude list. The one-liner every call site
## needs: `SpellWorld.rids([caster, my_own_body])`. Silently skips anything that
## is not a live CollisionObject2D, so passing a null caster is harmless.
static func rids(nodes: Array) -> Array[RID]:
	var out: Array[RID] = []
	for n: Variant in nodes:
		if n == null or not is_instance_valid(n):
			continue
		var co: CollisionObject2D = n as CollisionObject2D
		if co != null:
			out.append(co.get_rid())
	return out


# ------------------------------------------------------------ the smash rule

## True for anything a spell tears THROUGH rather than stops against.
##
## THE RULE, and the trap it exists for — copied in spirit from
## RockWall._is_smashable, which is where this was learned the hard way: group
## membership alone is NOT enough. A cover block that just collapsed leaves the
## "destructible" group immediately while its collider lives until the deferred
## free, so a group-only test sees a group-less solid body and stops the spell on
## the very crate it just broke. Anything already queued for deletion — or
## already gone — is smashed, not solid.
static func is_smashable(collider: Object) -> bool:
	# Untyped Variant handling on purpose: assigning an already-freed instance to
	# a typed `Node` variable is itself an error in GDScript, which would make this
	# throw on exactly the case it exists to answer.
	if collider == null or not is_instance_valid(collider):
		return true  # not there any more — nothing to stop against
	var n: Node = collider as Node
	if n == null:
		return false  # a collider that isn't a Node is not ours to smash
	return n.is_in_group(&"destructible") or n.is_queued_for_deletion()


# ------------------------------------------------------------ core primitive

## THE core primitive: walk the segment `from` -> `to` and report the first SOLID
## impact. Every "a spell that meets a wall should impact there" case is this
## function — spawn legality, per-frame travel, beam length, blast reach.
##
## Both points are WORLD SPACE. Never pass `global_position` of a spectacle node
## (see the class docs); pass the points the effect computed for itself.
##
## `exclude` — RIDs the ray ignores. ALWAYS pass the caster (and the effect's own
## body, if it has one): a spell spawns overlapping whoever cast it, and a spell
## that instantly collides with its own caster is a classic and infuriating bug.
## Build it with `rids([caster])`.
##
## `smash_destructibles` — default TRUE, and see the class docs for why the safe
## behaviour is the default. When true the ray keeps going past crates and cover,
## collecting them into the result's `smashed` array so the caller can damage
## them, and only stops on real world geometry.
##
## Returns the standard result dictionary (see class docs); never `{}`. Degrades
## to a clear path when there is no physics world.
static func first_solid(from: Vector2, to: Vector2, exclude: Array[RID] = [],
		ctx: Node = null, smash_destructibles: bool = true,
		mask: int = SOLID_MASK) -> Dictionary:
	var st: PhysicsDirectSpaceState2D = space(ctx)
	if st == null:
		return _clear(from, to)
	# A zero-length probe is not a segment question — intersect_ray's answer for
	# one is not meaningful. Callers asking "is this SPOT solid" want is_blocked().
	if from.distance_squared_to(to) <= EPS:
		return _clear(from, to)
	# Local copy. The pierce loop appends smashed colliders to the exclude set, and
	# mutating the caller's array — or worse, the shared `[]` default argument,
	# which in GDScript persists across calls — would leak state between queries.
	var skip: Array[RID] = []
	skip.assign(exclude)
	var smashed: Array[Node] = []
	var last: Dictionary = {}
	for _step: int in MAX_PIERCE_STEPS:
		var q := PhysicsRayQueryParameters2D.create(from, to, mask)
		q.exclude = skip
		q.collide_with_bodies = true
		q.collide_with_areas = false
		# Point-blank casts legitimately START inside the thing they must hit: a
		# wall raised on top of the caster, a bolt spawned against cover, a meteor
		# released below a ledge. Without this the ray reports "clear" from inside
		# solid rock and the spell phases straight through it — the exact bug.
		q.hit_from_inside = true
		var hit: Dictionary = st.intersect_ray(q)
		if hit.is_empty():
			return _clear(from, to, smashed)
		last = hit
		if smash_destructibles and is_smashable(hit.get("collider")):
			var c: Object = hit.get("collider")
			if c != null and is_instance_valid(c) and c is Node:
				smashed.append(c as Node)
			skip.append(hit.get("rid", RID()) as RID)
			continue
		return _impact(from, to, hit, smashed)
	# Out of pierce steps. Stopping on the last thing we saw is the conservative
	# answer: "spells must not pass through geometry" outranks "spells smash
	# through cover", so a pathological stack of crates ends the spell rather than
	# letting it tunnel out the far side of the level.
	if last.is_empty():
		return _clear(from, to, smashed)
	return _impact(from, to, last, smashed)


## `first_solid` for a path with real WIDTH. A single hairline ray misses a lot: a
## beam is 20 px thick, a shoved wall is 44 px, and either can straddle a pillar
## the centre line slips past. This casts `samples` parallel rays spread across
## `thickness`, perpendicular to the path, and returns the EARLIEST impact among
## them — which is what RockWall._hit_world does by hand with three heights across
## its front edge.
##
## Use it when the effect's own drawn width is more than a few pixels: beams,
## walls, ground waves, charging bodies. A bolt does not need it.
##
## NOTE the returned `position` is on the winning SAMPLE ray, so it is offset
## laterally from the centre line by up to thickness/2 — which is right for
## staging an impact spectacle at the surface that was actually struck. To clip a
## drawn length, use `distance` (or just call `clip`).
static func first_solid_thick(from: Vector2, to: Vector2, thickness: float,
		samples: int = THICK_SAMPLES, exclude: Array[RID] = [], ctx: Node = null,
		smash_destructibles: bool = true, mask: int = SOLID_MASK) -> Dictionary:
	if thickness <= EPS or samples <= 1:
		return first_solid(from, to, exclude, ctx, smash_destructibles, mask)
	var span: Vector2 = to - from
	if span.length_squared() <= EPS:
		return _clear(from, to)
	var perp: Vector2 = span.normalized().orthogonal()
	var best: Dictionary = _clear(from, to)
	var smashed: Array[Node] = []
	var seen: Dictionary = {}  # instance_id -> true, so one crate is listed once
	for i: int in samples:
		var t: float = float(i) / float(samples - 1)  # 0..1 across the width
		var off: Vector2 = perp * lerpf(-thickness * 0.5, thickness * 0.5, t)
		var r: Dictionary = first_solid(from + off, to + off, exclude, ctx,
			smash_destructibles, mask)
		for n: Node in (r["smashed"] as Array[Node]):
			var id: int = n.get_instance_id()
			if not seen.has(id):
				seen[id] = true
				smashed.append(n)
		if not bool(r["hit"]):
			continue
		# Earliest along the CENTRE line wins, not shortest ray: the sample rays
		# are parallel so their `distance` values are directly comparable.
		if not bool(best["hit"]) or float(r["distance"]) < float(best["distance"]):
			best = r
	best["smashed"] = smashed
	return best


## The usable endpoint of a segment: the original `to` when the path is clear,
## otherwise the point where the world stopped it. This is the one-liner that
## makes a beam's drawn length HONEST — `var end := SpellWorld.clip(muzzle, aim_end,
## BEAM_WIDTH, SpellWorld.rids([caster]), self)` and the beam can no longer be
## drawn through a wall.
##
## Pass `thickness > 0` to route through `first_solid_thick`. The returned point
## is always ON the centre line (`from + dir * distance`), which is what a drawn
## segment needs — see the note on `first_solid_thick` about lateral offset.
static func clip(from: Vector2, to: Vector2, thickness: float = 0.0,
		exclude: Array[RID] = [], ctx: Node = null,
		smash_destructibles: bool = true, mask: int = SOLID_MASK) -> Vector2:
	var span: Vector2 = to - from
	if span.length_squared() <= EPS:
		return to
	var res: Dictionary = first_solid_thick(from, to, thickness, THICK_SAMPLES,
		exclude, ctx, smash_destructibles, mask) if thickness > EPS \
		else first_solid(from, to, exclude, ctx, smash_destructibles, mask)
	if not bool(res["hit"]):
		return to
	return from + span.normalized() * float(res["distance"])


# ---------------------------------------------------------- the vertical case

## The floor beneath `pos`, within `max_dist`.
##
## THIS IS WHY METEORS FALL THROUGH THE FLOOR. A falling spell must resolve its
## impact Y against the GROUND UNDER THE TARGET, not against the target's own y —
## an enemy standing on a ledge, or a scatter point rolled into empty air, gives
## an impact point in the middle of nothing or below the world. Every falling and
## ground-planted spell should place its impact at `floor_below(desired).position`
## and nowhere else.
##
## ⚠ ON A MISS `position` IS `pos` UNCHANGED, not the bottom of the probe. There
## is genuinely no floor there (a pit, or off the map) and dropping the effect to
## the end of the ray would put it in the void — the thing we are trying to stop.
## CHECK `hit` BEFORE COMMITTING A SPECTACLE: over a pit the correct behaviours
## are to skip the strike, to let it fall out of the world, or to free the residue
## node, and only the caller knows which. GroundCrater already makes this call
## ("over a pit — no floating crater") and is the model to copy.
static func floor_below(pos: Vector2, max_dist: float = FLOOR_PROBE,
		exclude: Array[RID] = [], ctx: Node = null,
		smash_destructibles: bool = true, mask: int = SOLID_MASK) -> Dictionary:
	var res: Dictionary = first_solid(pos, pos + Vector2(0.0, maxf(max_dist, EPS)),
		exclude, ctx, smash_destructibles, mask)
	if not bool(res["hit"]):
		# See the ⚠ above: fall back to where the caller already was, which is the
		# same fallback RiftDagger._floor_under has been using.
		res["position"] = pos
		res["distance"] = 0.0
	return res


## `floor_below().position` for callers that only want the point and have already
## decided a pit is harmless (residue decals, dust puffs, a shadow's anchor).
## When there is no floor this returns `pos` unchanged — if that matters to you,
## use `floor_below` and read `hit`.
static func floor_point(pos: Vector2, max_dist: float = FLOOR_PROBE,
		exclude: Array[RID] = [], ctx: Node = null) -> Vector2:
	return floor_below(pos, max_dist, exclude, ctx)["position"] as Vector2


## The floor polyline a ground-hugging effect should be drawn along, sampled from
## `from` to `to`. A ground wave, a creeping shadow or a spreading frost sheet
## must follow the terrain rather than sit on one flat y, and doing that means
## `floor_below` per x — this is that loop, written once.
##
## THE PIT RULE: sampling STOPS at the first x with no floor under it, and the
## points found so far are returned. A ground crawl that reaches the lip of a pit
## should end at the lip; continuing past it (at the last known y, or at the
## probe's y) would draw the effect across thin air, which is the same class of
## bug as a meteor under the floor. An empty/1-point return means "there is
## nothing to crawl along here" and the caller should not spawn.
static func ground_path(from: Vector2, to: Vector2, steps: int = 16,
		max_dist: float = FLOOR_PROBE, exclude: Array[RID] = [],
		ctx: Node = null) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = clampi(steps, 2, MAX_GROUND_SAMPLES)
	for i: int in n:
		var t: float = float(i) / float(n - 1)
		var probe: Vector2 = from.lerp(to, t)
		var res: Dictionary = floor_below(probe, max_dist, exclude, ctx)
		if not bool(res["hit"]):
			return out  # the lip of a pit — see THE PIT RULE above
		out.append(res["position"] as Vector2)
	return out


# ------------------------------------------------------- occupancy / legality

## Is this world point INSIDE solid geometry? The teleport-destination legality
## test: a blink that lands you inside a wall is the same bug as a meteor under
## the floor, seen from the other side.
##
## `radius` > 0 tests a CIRCLE instead of a point, which is what you want when the
## thing being placed has a body — a hero-sized destination is only legal if a
## hero-sized volume fits. Hero._safe_blink_destination already does this with its
## own shape query and its own probe walk; this is the cheap shared version for
## everything else (spawn points for walls and pillars, dagger recall targets,
## summon placement).
##
## Destructibles do NOT count as blocking by default, for the same reason they do
## not stop a ray: you can appear inside a crate, and it should break.
static func is_blocked(pos: Vector2, radius: float = 0.0,
		exclude: Array[RID] = [], ctx: Node = null,
		smash_destructibles: bool = true, mask: int = SOLID_MASK) -> bool:
	var st: PhysicsDirectSpaceState2D = space(ctx)
	if st == null:
		return false  # no world -> nothing blocks; see the degradation note
	var results: Array[Dictionary] = []
	if radius <= EPS:
		var pq := PhysicsPointQueryParameters2D.new()
		pq.position = pos
		pq.collision_mask = mask
		pq.collide_with_bodies = true
		pq.collide_with_areas = false
		pq.exclude = exclude
		results = st.intersect_point(pq, OCCUPANCY_MAX_RESULTS)
	else:
		if _probe_circle == null:
			_probe_circle = CircleShape2D.new()
		_probe_circle.radius = radius
		var sq := PhysicsShapeQueryParameters2D.new()
		sq.shape = _probe_circle
		sq.transform = Transform2D(0.0, pos)
		sq.collision_mask = mask
		sq.collide_with_bodies = true
		sq.collide_with_areas = false
		sq.exclude = exclude
		results = st.intersect_shape(sq, OCCUPANCY_MAX_RESULTS)
	for r: Dictionary in results:
		if smash_destructibles and is_smashable(r.get("collider")):
			continue
		return true
	return false


## Is there a clear line from `from` to `to` — i.e. may damage travel there?
##
## THE "SPELLS SHOULDN'T GET OUT OF THE RADIUS" RULE, in its through-walls form: a
## blast whose radius overlaps the far side of a wall must not damage what is
## standing there. Pair it with SpellGeometry (`contains_point` / `overlaps`) for
## the shape half of the test — shape says "in range", this says "and not behind
## cover".
##
## Cover that is DESTRUCTIBLE does not shield by default, matching every other
## function here: a crate is smashed, not respected. `smash_destructibles = false`
## if a particular spell should be stopped by cover.
static func can_reach(from: Vector2, to: Vector2, exclude: Array[RID] = [],
		ctx: Node = null, smash_destructibles: bool = true,
		mask: int = SOLID_MASK) -> bool:
	return not bool(first_solid(from, to, exclude, ctx, smash_destructibles, mask)["hit"])


## Drop everything behind cover out of a target list. THE one-line adoption for
## the ~15 spectacles that currently do `for e in get_nodes_in_group("enemy")` and
## damage anything within a radius, wall or no wall:
##
##     for e in SpellWorld.filter_reachable(centre, in_radius, rids([caster]), self):
##
## ⚠ NOTE THE ONE DELIBERATE TRANSFORM READ IN THIS FILE. This function reads
## `global_position` on the nodes it is given, which everything else here refuses
## to do — because the distinction is what matters, not the rule: an ENEMY's
## transform genuinely is where the enemy is, while a SPECTACLE's transform is a
## lie about where its drawing is. Pass bodies here, never spell effects.
##
## The endpoint is pulled `REACH_PAD` px back toward `from` so a target standing
## flush against a wall (or with its origin down at its feet, on the floor
## collider) is not culled by the very surface it is standing on.
static func filter_reachable(from: Vector2, nodes: Array,
		exclude: Array[RID] = [], ctx: Node = null,
		smash_destructibles: bool = true, mask: int = SOLID_MASK) -> Array:
	var out: Array = []
	for n: Variant in nodes:
		if n == null or not is_instance_valid(n):
			continue
		var n2: Node2D = n as Node2D
		if n2 == null:
			continue
		var target: Vector2 = n2.global_position
		var span: Vector2 = target - from
		var d: float = span.length()
		if d > REACH_PAD:
			target = from + span / d * (d - REACH_PAD)
		if can_reach(from, target, exclude, ctx, smash_destructibles, mask):
			out.append(n)
	return out


# ------------------------------------------------------------------ internals

## The "nothing stopped it" result. `to` is the usable endpoint, which is what
## makes every caller's happy path a single read instead of an is_empty() branch.
static func _clear(from: Vector2, to: Vector2,
		smashed: Array[Node] = []) -> Dictionary:
	return {
		"hit": false,
		"position": to,
		"normal": Vector2.ZERO,
		"collider": null,
		"rid": RID(),
		"distance": from.distance_to(to),
		"smashed": smashed,
	}


## Normalise one `intersect_ray` dict into the shared result shape.
## `distance` is the PROJECTION onto from->to, not `from.distance_to(position)`:
## for a thick query the impact point sits off the centre line, and a beam clipped
## to the off-centre distance would be visibly the wrong length.
static func _impact(from: Vector2, to: Vector2, hit: Dictionary,
		smashed: Array[Node]) -> Dictionary:
	var pos: Vector2 = hit.get("position", to) as Vector2
	var span: Vector2 = to - from
	var dist: float = from.distance_to(pos)
	if span.length_squared() > EPS:
		dist = clampf((pos - from).dot(span.normalized()), 0.0, span.length())
	return {
		"hit": true,
		"position": pos,
		"normal": hit.get("normal", Vector2.ZERO) as Vector2,
		"collider": hit.get("collider"),
		"rid": hit.get("rid", RID()) as RID,
		"distance": dist,
		"smashed": smashed,
	}
