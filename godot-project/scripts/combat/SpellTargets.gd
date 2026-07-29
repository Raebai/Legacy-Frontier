class_name SpellTargets
extends RefCounted
## Shared TARGET selection for spell effects — "who is actually hit?"
##
## The third of three siblings, and the split between them is the whole point:
##   * `SpellGeometry` is PURE SHAPE MATHS. "Do these two shapes touch, and where?"
##     It never sees the physics world and never sees a target.
##   * `SpellWorld` TOUCHES THE PHYSICS WORLD. "Is there a wall in the way, where is
##     the floor, is this spot inside solid rock?"
##   * `SpellTargets` (this file) COMBINES BOTH AGAINST A LIST OF BODIES. "Given a
##     blast at this point with this radius, who takes the damage?"
## Keep that line clean. A function here that stops needing a target list belongs in
## one of the other two.
##
## WHY THIS FILE EXISTS — TWO REPORTED BUGS WITH ONE STRUCTURAL CAUSE.
##
## Bug 1, in the maker's words: "spells pass through heads without registering."
## They were right, and the reason is arithmetic rather than physics. `Enemy` draws
## a `CharacterRig` whose HEAD CENTRE sits 9.9 px ABOVE the node origin (18.9 px on
## the 1.9x SpellPlayground sparring dummies, 30.4 px on the Guardian) and whose
## skull top is higher still. Every area and line spell in the game tested
## `enemy.global_position` — a ZERO-SIZE POINT at the origin, about ten pixels below
## the head being aimed at. The head was never a target at all. You could aim
## deliberately into that band and hit nothing.
##
## Bug 2: blasts damaged through walls, because a group loop plus a distance test
## never asks what is BETWEEN the spell and the victim.
##
## The structural cause of both is that the targeting helpers were COPY-PASTED into
## eight files. `targets_in_radius` existed verbatim in BoulderHurl, DivineRay,
## MeteorSigil, RiftDagger, RockPillar, StarConvergence and BlinkStrike;
## `targets_on_line` / `targets_on_beam` in LightningRush and BeamSpell; and another
## dozen scripts hand-rolled the same loop inline. Eight copies means a fix lands in
## one and drifts in seven. So it is fixed ONCE, here.
## `docs/spell-world-contract.md` carries the mechanical before/after for each.
##
## ⚠ TRAP 1 — NEVER READ A SPECTACLE'S TRANSFORM. Shouted by both sibling files and
## worth shouting a third time: spell spectacle nodes PARK AT THE ARENA ORIGIN and
## draw in WORLD coordinates, so their `global_position` is `(0, 0)` and is NOT
## where the effect is. Therefore:
##
##     EVERY FUNCTION HERE TAKES EXPLICIT WORLD-SPACE Vector2 VALUES.
##     NOTHING HERE EVER READS A SPELL NODE'S TRANSFORM.
##
## A spell node is only ever accepted as `ctx` — a handle used to reach the right
## `World2D`, never as a position. Pass the points your effect computed for ITSELF,
## the same ones it draws with. Get this wrong and every blast in the game resolves
## at the top-left of the arena: it fails LOUD in the wrong direction, killing
## everything standing near the origin and nothing standing near the spell.
##
## The one deliberate exception — the same one `SpellWorld.filter_reachable` makes,
## and for the same reason — is that this file DOES read `global_position` on the
## TARGET BODIES it is given. An enemy's transform genuinely is where the enemy is;
## a spectacle's transform is a lie. Pass bodies to the `nodes` argument, never
## spell effects.
##
## ⚠ TRAP 2 — TEST THE SILHOUETTE, NOT THE ORIGIN. That is Bug 1's fix, and it is
## DUCK-TYPED, exactly as this codebase already duck-types `wall_distance`,
## `blink_to`, `reflect`, `consume` and the whole `reaction_*` contract:
##
##     has_method("body_distance")  ->  distance to the DRAWN silhouette
##                                      (spine segment + head circle, scale-aware)
##     has_method("hit_margin")     ->  that target's own forgiveness ring, world px
##     has_method("head_point")     ->  where the drawn head actually is
##     ...otherwise                 ->  the old point test on `global_position`
##
## `Enemy` (and `Boss`, which extends it) implements all three; `SpikeFigure`
## implements `body_distance` only. A plain `Node2D`, a destructible crate, an enemy
## projectile or a headless test stub implements none, and MUST keep working
## unchanged — which is why the fallback is a point test on `global_position` and
## the fallback margin is ZERO. That combination makes this file's behaviour
## BYTE-IDENTICAL to the old `targets_in_radius` for every target that has no
## silhouette. Anything more generous would be a stealth hitbox inflation across the
## whole game, dressed up as a bug fix.
##
## ⚠ TRAP 3 — LINE OF SIGHT IS THE DEFAULT, NOT AN OPTION YOU REMEMBER. Bug 2's fix
## is a single call to `SpellWorld.filter_reachable`, and it is wired in as
## `require_los = true` on every selector so the SAFE behaviour is the one a caller
## gets by NOT THINKING ABOUT IT. The maker's rule is "the spells shouldn't be able
## to get out the radius", and killing someone through solid rock is the worst
## version of that. Opt out (`require_los = false`) only when the FICTION says the
## effect is not line-of-sight — `ShadowCrawler` is documented as passing UNDER
## walls, and a ground-borne effect that follows the floor is the archetype. "It was
## easier" is not a reason.
##
## HEADLESS BEHAVIOUR. LOS is delegated wholesale to `SpellWorld`, which degrades to
## "no hit" when there is no physics world (a `--script` helper suite, teardown, a
## spell built before it entered the tree). So in a bare harness NOTHING is culled
## for cover, which is the right way round: a headless test that gets a phantom wall
## is a mystery, a headless test that gets no walls is just a world with no walls.

## Forgiveness ring used for a target that does NOT implement `hit_margin()`.
##
## ZERO ON PURPOSE, and it is the single most important constant in this file. With
## a zero margin AND the `global_position` fallback in `body_distance()`, every
## marginless target — crates, projectiles, plain `Node2D`s, test stubs — resolves
## EXACTLY as the old copy-pasted `center.distance_to(n.global_position) <= radius`
## did. That is what makes adopting this file a no-op for everything except the
## bodies that actually have a drawn silhouette.
##
## Note that `SpikeFigure` (the player rig) has `body_distance` but NOT `hit_margin`,
## so it lands here at 0.0. That is deliberate: if the player figure wants
## forgiveness, the fix is to give SpikeFigure its own `hit_margin()` next to its
## `body_distance()`, NOT to raise this default and quietly widen every crate and
## bolt in the game at the same time. UNTESTED — but the untested direction is the
## conservative one.
const DEFAULT_HIT_MARGIN: float = 0.0

## Probe points used to measure a BODY against a SEGMENT (see `_touches_segment`).
## The silhouette seam is a point->body distance function, so a segment->body
## distance has to be sampled. Two probes — the segment point nearest the body's
## origin, and the segment point nearest its head — is the smallest sample that
## catches the head case, which IS Bug 1. UNTESTED GUESS: if a beam at knee height
## starts clipping heads (or vice versa) this is the knob, but prefer fixing the
## probe CHOICE over adding more of them.
const SEGMENT_PROBES: int = 2

const EPS: float = 0.00001

## ⚠ THE STACKING CAVEAT — READ THIS BEFORE TUNING ANY RADIUS.
## `reach` and `hit_margin` COMPOUND, and so does the silhouette itself. For a
## marginless point target the effective hit test is exactly `radius`. For a drawn
## enemy it is `radius` + `hit_margin()` (~3.7 px at rig height 31, ~7 px on a 1.9x
## dummy) measured not from the origin but from the NEAREST POINT OF A ~31 PX TALL
## BODY — so along the vertical axis the effective reach grows by up to half the rig
## height on top of everything else. That growth IS the bug fix and it is intended.
## But it means a radius that felt right against origin-point testing will feel
## noticeably bigger now, and that "just add a few px of forgiveness" at a call site
## on top of a generous `HIT_MARGIN_FACTOR` produces a hitbox far larger than either
## number suggests. Tune the radius, or tune `Enemy.HIT_MARGIN_FACTOR`. Never both,
## and never a third margin at a call site — a second margin scheme somewhere else
## is precisely how the two-schemes bug started.


# ------------------------------------------------------------ the silhouette seam

## Distance from world point `p` to `target`'s REAL body, or `INF` if there is no
## body to measure. Negative inside the head. This is the whole of Bug 1's fix.
##
## Duck-typed with a fallback (see TRAP 2 in the class docs): a target that draws a
## rig answers with its spine-segment + head-circle silhouette, scale-aware, so a
## 1.9x sparring dummy needs no special case anywhere. Anything else falls back to
## the point test on `global_position` that every call site was already doing, which
## keeps this a no-op for crates, bolts and stubs.
##
## `INF` (not 0, not the caller's point) for a freed / null / non-positional target,
## so it can never satisfy a `<=` test by accident. Failing closed matters here: the
## alternative fails by damaging things that are not there.
static func body_distance(target: Object, p: Vector2) -> float:
	# Untyped Object on purpose. Assigning an already-freed instance to a typed
	# `Node` variable is itself an error in GDScript, which would make this throw on
	# exactly the case it exists to answer.
	if target == null or not is_instance_valid(target):
		return INF
	if target.has_method(&"body_distance"):
		return float(target.call(&"body_distance", p))
	var n2: Node2D = target as Node2D
	if n2 == null:
		return INF  # nothing with a world position — it cannot be hit
	return n2.global_position.distance_to(p)


## `target`'s own forgiveness ring in WORLD px (already scaled by its node scale),
## or `DEFAULT_HIT_MARGIN` when it does not publish one.
##
## Clamped to >= 0: a negative margin would silently SHRINK a body below its drawn
## size, which is the "spells pass through it" bug wearing a different hat.
static func hit_margin(target: Object) -> float:
	if target == null or not is_instance_valid(target):
		return DEFAULT_HIT_MARGIN
	if target.has_method(&"hit_margin"):
		return maxf(float(target.call(&"hit_margin")), 0.0)
	return DEFAULT_HIT_MARGIN


## Where to AIM at / centre an effect on / stage a reaction against `target`: the
## drawn head when it has one, its origin otherwise.
##
## Use this — never `global_position` — for anything the player perceives as
## pointing AT a character: a lock-on marker, a head-height beam, an impact burst, a
## status icon. `global_position` is mid-body and reads as "aimed at their stomach".
static func aim_point(target: Object) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	if target.has_method(&"head_point"):
		return target.call(&"head_point") as Vector2
	var n2: Node2D = target as Node2D
	return n2.global_position if n2 != null else Vector2.ZERO


## THE single-target predicate every inline `if pos.distance_to(n.global_position) >
## HIT_RADIUS: continue` should become. `reach` is the effect's own radius; the
## target's forgiveness is added on top by the target itself.
static func hits(target: Object, p: Vector2, reach: float = 0.0) -> bool:
	# INF <= anything is false, so an invalid target can never pass this.
	return body_distance(target, p) <= reach + hit_margin(target)


# ------------------------------------------------------------------- the selectors

## Everyone in `nodes` within `radius` of world point `center`.
##
## THE replacement for the six copy-pasted `targets_in_radius` helpers. Adoption is
## mechanical — see `docs/spell-world-contract.md`:
##
##     for e: Node in SpellTargets.in_radius(at, RADIUS,
##             get_tree().get_nodes_in_group(target_group), [caster], self):
##
## `center` is WORLD SPACE and must be the point the effect DREW itself at, never
## the spell node's transform (TRAP 1).
##
## `skip` — nodes excluded from the results AND from the line-of-sight rays. Pass
## the caster. It is the caster's own body that is most likely to be sitting on the
## blast centre, and a ray that starts inside a body it can see reports an instant
## block, which would cull the entire result set. Today's layers make that
## impossible (heroes are on collision layer 2, enemies on 4, and the LOS ray masks
## layer 1 only) — this is cheap insurance against the day something hittable also
## becomes solid world geometry, and it is free.
##
## `require_los` — TRUE BY DEFAULT. See TRAP 3.
##
## Result order is the INPUT order, filtered. That makes it deterministic for a
## deterministic input (`get_nodes_in_group` order) and therefore headless-testable;
## use `sorted_by_distance` when a caller needs nearest-first instead.
static func in_radius(center: Vector2, radius: float, nodes: Array,
		skip: Array = [], ctx: Node = null, require_los: bool = true) -> Array:
	var out: Array = []
	for n: Node in _pool(nodes, skip):
		if hits(n, center, radius):
			out.append(n)
	return _reachable(center, out, skip, ctx, require_los)


## Everyone in `nodes` inside the CORRIDOR that runs `length` px from `origin` along
## `dir`, within `half_width` of its centre line.
##
## THE replacement for `LightningRush.targets_on_line` and
## `BeamSpell.targets_on_beam`, whose signatures this deliberately mirrors so the
## swap is positional.
##
## ⚠ ONE DELIBERATE DIVERGENCE FROM THE OLD HELPERS: this is a CAPSULE, not a box.
## The old test projected onto the axis and rejected anything outside `[0, length]`,
## giving square ends; this clamps to the nearest point ON the segment, giving
## rounded ends. So a target just past the tip, within `half_width` of it, now
## registers where before it did not. That is a reach increase of up to `half_width`
## at the tip only. It is chosen for consistency — `SpellGeometry` already defines a
## "line" as a capsule, and beam-vs-beam / beam-vs-wall reactions already resolve
## against capsules, so a beam whose DAMAGE shape disagreed with its REACTION shape
## would be a fresh two-schemes bug of exactly the kind this file exists to end.
static func on_line(origin: Vector2, dir: Vector2, length: float, half_width: float,
		nodes: Array, skip: Array = [], ctx: Node = null,
		require_los: bool = true) -> Array:
	var d: Vector2 = dir.normalized() if dir.length_squared() > EPS else Vector2.RIGHT
	var tip: Vector2 = origin + d * maxf(length, 0.0)
	var out: Array = []
	for n: Node in _pool(nodes, skip):
		if _touches_segment(n, origin, tip, half_width):
			out.append(n)
	# LOS from the MUZZLE, not from the tip: a beam is blocked by what stands between
	# the caster and the victim, and `SpellWorld.clip` is what should already have
	# shortened the drawn beam at that same wall.
	return _reachable(origin, out, skip, ctx, require_los)


## Everyone in `nodes` inside the wedge at `apex`: within `reach`, and within the arc
## whose half-angle is encoded as `min_dot`.
##
## The test is `facing.dot(toward) > min_dot` — STRICTLY greater, because that is the
## form Hero's melee already ships (`facing.dot(toward) > _melee_arc_dot`) and a
## silent flip to `>=` would widen every swing in the game by a hair. So: 1.0 admits
## nothing, 0.0 is the half-plane in front of you, and -1.0 admits everything EXCEPT
## a target standing exactly opposite. For a genuine full circle pass something below
## -1.0 (or just use `in_radius`, which is what a full circle is).
##
## For Hero's punch / kick / uppercut / dash-strike, which today hand-roll this loop
## four times over three different groups.
##
## THE ANGLE IS MEASURED TO THE TARGET'S ORIGIN, the reach to its SILHOUETTE. That
## asymmetry is deliberate: reach-to-silhouette is Bug 1's fix and must land, while
## angle-to-head would make a tall enemy standing beside you register as "above and
## therefore outside the arc" (or worse, inside it when they are behind you). Melee
## arcs are wide; the origin is the honest anchor for "which side of me are they on".
## A target standing exactly ON the apex has no direction at all and always counts.
static func in_cone(apex: Vector2, facing: Vector2, reach: float, min_dot: float,
		nodes: Array, skip: Array = [], ctx: Node = null,
		require_los: bool = true) -> Array:
	var f: Vector2 = facing.normalized() if facing.length_squared() > EPS else Vector2.RIGHT
	var out: Array = []
	for n: Node in _pool(nodes, skip):
		if not hits(n, apex, reach):
			continue
		var toward: Vector2 = (n as Node2D).global_position - apex
		if toward.length_squared() <= EPS:
			out.append(n)  # standing on top of you — no direction, always in the arc
			continue
		if f.dot(toward.normalized()) <= min_dot:
			continue
		out.append(n)
	return _reachable(apex, out, skip, ctx, require_los)


## The single nearest live target within `max_reach` of `point`, or `null`.
##
## For the auto-target seams: `Hero._nearest_enemy_in_melee_range`,
## `Spell._do_chain`'s hop search, `DrainTether._resolve_caster`,
## `ChainBolt.build_chain`'s hop step. Nearest is measured to the SILHOUETTE, so a
## tall enemy whose head is closer than a short enemy's origin wins — which is what
## the eye expects.
##
## Ties break toward the EARLIER node in `nodes` (strict `<`), so the answer is
## reproducible for a reproducible input list. `ChainBolt.build_chain` is
## deliberately a pure static selector precisely so its hop order stays
## headless-testable; keeping this deterministic is what lets it stay that way.
static func nearest(point: Vector2, max_reach: float, nodes: Array,
		skip: Array = [], ctx: Node = null, require_los: bool = true) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for n: Node in in_radius(point, max_reach, nodes, skip, ctx, require_los):
		var d: float = body_distance(n, point)
		if d < best_d:
			best_d = d
			best = n as Node2D
	return best


# -------------------------------------------------------------------- orderings

## `nodes` ordered nearest-silhouette-first from `point`. Does NOT filter by range or
## by line of sight — compose it with `in_radius` when you want both.
##
## STABLE, which `Array.sort_custom` on its own is not: equal distances keep their
## input order via an index tiebreak. A chain that reorders its hops between two runs
## with identical inputs is not testable, and untestable hop order is how a chain
## silently starts double-hitting one target.
static func sorted_by_distance(point: Vector2, nodes: Array) -> Array:
	var keyed: Array = []
	var i: int = 0
	for n: Node in _pool(nodes, []):
		keyed.append({"n": n, "d": body_distance(n, point), "i": i})
		i += 1
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["d"] == b["d"]:
			return int(a["i"]) < int(b["i"])
		return float(a["d"]) < float(b["d"])
	)
	var out: Array = []
	for k: Dictionary in keyed:
		out.append(k["n"])
	return out


## The live, positionable subset of `nodes`: drops nulls, freed instances, anything
## already `is_queued_for_deletion()`, and anything that is not a `Node2D`.
##
## The `is_queued_for_deletion` half is the one that matters. A destructible that
## collapsed earlier THIS frame is still reachable from `get_nodes_in_group` until
## the deferred free lands, and damaging it again is at best a wasted hit and at
## worst a second death spectacle on one crate. `SpellWorld.is_smashable` treats the
## same state as "not there any more" for rays; this is that rule for targets.
static func alive(nodes: Array) -> Array:
	var out: Array = []
	for n: Variant in nodes:
		if n == null or not is_instance_valid(n):
			continue
		var node: Node = n as Node
		if node == null or node.is_queued_for_deletion():
			continue
		if not (n is Node2D):
			continue  # every selector here needs a world position to test against
		out.append(n)
	return out


# ------------------------------------------------------------------- internals

## `alive(nodes)` minus everything in `skip`. Identity is by instance id rather than
## by `in`, so a `skip` entry that was freed between the caller building it and this
## running cannot throw.
static func _pool(nodes: Array, skip: Array) -> Array:
	var blocked: Dictionary = {}
	for s: Variant in skip:
		if s != null and is_instance_valid(s) and s is Object:
			blocked[(s as Object).get_instance_id()] = true
	if blocked.is_empty():
		return alive(nodes)
	var out: Array = []
	for n: Node in alive(nodes):
		if not blocked.has(n.get_instance_id()):
			out.append(n)
	return out


## Bug 2's fix, in one place: drop everything behind cover.
##
## Delegated wholesale to `SpellWorld.filter_reachable` — do NOT reimplement it here.
## It already owns the `REACH_PAD` pull-back (so a target standing flush against a
## wall is not culled by the very surface it stands on), the smash rule (destructible
## cover does not shield, because it breaks), and the degrade-to-clear behaviour when
## there is no physics world.
##
## Called AFTER the shape test, never before: the shape test is pure maths over a
## handful of nodes, the LOS test is a raycast each. Filtering first keeps the
## expensive half proportional to the number of things actually in range.
static func _reachable(from: Vector2, found: Array, skip: Array, ctx: Node,
		require_los: bool) -> Array:
	if not require_los or found.is_empty():
		return found
	return SpellWorld.filter_reachable(from, found, SpellWorld.rids(skip), ctx)


## Does `target`'s body come within `half_width` (+ its own margin) of segment a->b?
##
## The silhouette seam answers POINT->body distance, so SEGMENT->body distance has to
## be sampled: take the point on the segment closest to the body's origin, and the
## point on the segment closest to its head, and measure the body from each. Two
## probes is the smallest sample that catches a corridor passing at head height over
## a body whose origin sits below it — which is Bug 1 in its beam form, and the exact
## case a single origin probe misses.
##
## It IS an approximation. A pathological pose could put the true closest approach
## between the two probes; for a spine-plus-head silhouette against a straight
## corridor that gap is sub-pixel, and erring toward "miss" is the safe direction.
static func _touches_segment(target: Object, a: Vector2, b: Vector2,
		half_width: float) -> bool:
	var reach: float = half_width + hit_margin(target)
	var n2: Node2D = target as Node2D
	if n2 == null:
		return false
	var origin_probe: Vector2 = SpellGeometry.closest_point_on_segment(
		n2.global_position, a, b)
	if body_distance(target, origin_probe) <= reach:
		return true
	var head: Vector2 = aim_point(target)
	if head.is_equal_approx(n2.global_position):
		return false  # no separate head to probe — the origin probe was the whole test
	var head_probe: Vector2 = SpellGeometry.closest_point_on_segment(head, a, b)
	return body_distance(target, head_probe) <= reach


# ---- damage application ------------------------------------------------------

## Arity cache, keyed on the target's script/class. `get_method_list()` allocates a
## dictionary per method, so asking it per hit would be a real cost inside a
## barrage; the answer is a property of the TYPE, so it is asked once per type.
static var _tint_arity: Dictionary = {}


## Deal `amount` to `target`, adapting to WHICHEVER `take_damage` it declares.
##
## THE BUG THIS EXISTS TO DELETE. This codebase has two incompatible signatures:
##     take_damage(amount: int)                       Hero, DestructibleTerrain,
##                                                    DestructibleProp, BreakablePlatform
##     take_damage(amount: int, tint: Color = ...)    Enemy, Boss
## and ~6 spell scripts check `has_method("take_damage")` — which is true for both
## — and then call the TWO-argument form. Against a one-argument receiver that is a
## runtime error, and in GDScript a runtime error **aborts the enclosing function**.
## So the hit is lost AND every line after it is skipped: `RuneOrbs` was dropping
## its ailment and its impact burst and the orb simply vanished, which reads as a
## rendering bug rather than a crash.
##
## It stayed hidden because every spell only ever hit `Enemy`. The faction seam is
## what exposed it: the moment a spell could target a HERO, `ShadowCrawler` and
## `HorizonArc` started crashing on contact. A bot-vs-bot sim found it in minutes.
##
## Returns true if damage was actually applied, so a caller can tell "I hit it"
## from "there was nothing there" instead of assuming.
static func hurt(target: Object, amount: int,
		tint: Color = Color(1.0, 1.0, 1.0, 0.0)) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method(&"take_damage"):
		return false
	if _accepts_tint(target):
		target.call(&"take_damage", amount, tint)
	else:
		target.call(&"take_damage", amount)
	return true


## Does this target's `take_damage` take the tint? Cached per type.
static func _accepts_tint(target: Object) -> bool:
	var key: Variant = target.get_script()
	if key == null:
		key = target.get_class()
	if _tint_arity.has(key):
		return bool(_tint_arity[key])
	var takes: bool = false
	for m: Dictionary in target.get_method_list():
		if String(m.get("name", "")) == "take_damage":
			takes = (m.get("args", []) as Array).size() >= 2
			break
	_tint_arity[key] = takes
	return takes
