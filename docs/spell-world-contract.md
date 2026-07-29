# SpellWorld contract — how a spectacle stops passing through the world

`godot-project/scripts/combat/SpellWorld.gd`

This is the adoption checklist for the ~15 spell spectacle scripts. It exists to
close the maker's #1 outstanding gameplay bug:

> "No spell may pass through geometry. Meteors currently fall THROUGH the floor;
> nothing may end up below or inside the environment. A spell that meets a wall,
> the ground, or cover should IMPACT there — and destroy what it can. Every
> single spell should be interactive."

and its companion rule:

> "the spells shouldn't be able to get out the radius"

**Status: headless-verified, UNPLAYTESTED.** Every constant in `SpellWorld.gd` is
reasoning, not feel. See `tools/slice_test_spell_world.gd`.

---

## The two files, and which one you want

| | answers | touches physics |
|---|---|---|
| `SpellGeometry` | "do these two shapes touch, and where?" | no — pure maths |
| `SpellWorld` | "what does the world put in the way?" | yes |

If you need "is this target inside my blast", that is `SpellGeometry`. If you need
"…and is there a wall between us", that is `SpellWorld`.

---

## The three rules you must not get wrong

**1. World space only. Never a spectacle's transform.**
Spell spectacle nodes park at the arena origin and draw in world coordinates, so
`global_position` is `(0,0)` and is **not** where the effect is. Every `SpellWorld`
function takes explicit `Vector2` world points. A node is only ever passed as
`ctx`, purely to reach the right `World2D`. Pass the points your effect computed
for itself — the same ones you draw with.

**2. Destructibles are SMASHED THROUGH, not treated as walls.**

```gdscript
SMASHED = is_in_group("destructible") OR is_queued_for_deletion()
```

The `is_queued_for_deletion()` half is load-bearing and has already cost a session
once: a cover block that just collapsed leaves the `"destructible"` group
*immediately*, while its collider survives until the deferred free. A group-only
test stops the spell dead on the very crate it just broke. This is the **default**
(`smash_destructibles = true`); pass `false` only if a specific spell should be
stopped by cover. Whatever you smashed comes back in the result's `smashed` array
— **damage it**, that is the "destroy what it can" half of the ask.

**3. Always exclude the caster.**

```gdscript
var skip: Array[RID] = SpellWorld.rids([caster_node])
```

A spell spawns overlapping whoever cast it. Without this, the cast instantly
collides with the caster.

---

## The result dictionary

Every query returns the same shape, always populated, never `{}`:

| key | type | meaning |
|---|---|---|
| `hit` | `bool` | did something solid stop it |
| `position` | `Vector2` | impact point; the clear endpoint when nothing was hit |
| `normal` | `Vector2` | surface normal; `ZERO` on a miss |
| `collider` | `Object` | what was hit — decide damage / smash / react from this |
| `rid` | `RID` | for chaining excludes |
| `distance` | `float` | travel along `from -> to` before the impact — **use this to clip a drawn length** |
| `smashed` | `Array[Node]` | destructibles torn through on the way, in order |

---

## The checklist — call these three places

### At SPAWN — is this position legal?

Before you place a wall, a pillar, a summon, or a teleport destination:

```gdscript
if SpellWorld.is_blocked(dest, body_radius, skip, self):
    return  # or nudge; nothing may end up INSIDE the environment
```

### At TRAVEL — did I cross anything this frame?

Per-frame, cast the segment you *just travelled* (not a forward guess) — that is
deterministic and cannot tunnel past a fast frame:

```gdscript
var r := SpellWorld.first_solid(prev_pos, pos, skip, self)
for n: Node in (r["smashed"] as Array[Node]):
    if n.has_method("damage_at"):
        n.damage_at(damage, r["position"], _dir)
if r["hit"]:
    _impact_at(r["position"], r["normal"], r["collider"])
    return
```

For anything with real **width** — beams, walls, ground waves, charging bodies —
use `first_solid_thick(from, to, thickness)` instead. A hairline centre ray
straddles pillars the effect visibly covers. (This is
`RockWall._hit_world`'s three-height sample, generalised.)

For a **drawn length** the one-liner is:

```gdscript
var end := SpellWorld.clip(muzzle, aim_end, BEAM_WIDTH, skip, self)
```

The beam can no longer be drawn through a wall.

### At IMPACT — keep damage inside the drawn shape

Two halves. Shape is `SpellGeometry`'s job; **cover is `SpellWorld`'s**:

```gdscript
var in_range := MeteorSigil.targets_in_radius(at, RADIUS, get_tree().get_nodes_in_group(target_group))
for e: Node in SpellWorld.filter_reachable(at, in_range, skip, self):
    ...
```

`filter_reachable` drops anything behind a wall. It is the single line that stops
blasts leaking through geometry.

Also: **use the same radius constant for the draw and the damage.** Most "the
spell got out of its radius" reports are a visual radius and a damage radius that
drifted apart, not a physics problem. `MeteorSigil.SIGIL_VISUAL_RADIUS_FACTOR`
already documents one deliberate divergence — deliberate is fine, accidental is
the bug.

---

## Falling spells do one extra thing

**A falling spell must resolve its impact Y against the FLOOR BENEATH the target,
never against the target's own Y.** This is exactly why meteors fall through the
floor today: the impact point is a scatter roll, and a scatter roll lands in
mid-air or below the world about as often as it lands on the ground.

```gdscript
var g := SpellWorld.floor_below(desired)
if not g["hit"]:
    return          # over a pit — skip the strike; do NOT drop it into the void
var at: Vector2 = g["position"]
```

⚠ **On a miss, `position` is your own point unchanged, not the bottom of the
probe.** Check `hit`. Over a pit the right answer is caller-specific — skip the
strike, let it fall out of the world, or free the residue node —
`GroundCrater` already makes this call ("over a pit — no floating crater") and is
the model to copy.

Ground-hugging effects (crawls, spreading sheets, ground waves) want
`ground_path(from, to, steps)`: the floor polyline to draw along. It **stops at
the lip of a pit** rather than drawing across thin air.

---

## Worked example — `MeteorSigil`, the canonical offender

`MeteorSigil` picks scatter points on a squashed ellipse, then lands each meteor
at that raw point. Nothing ever asks where the ground is, so a strike rolled over
a pit or under a ledge detonates **inside or below the floor**, and its radius
damage passes straight through walls.

### Before

```gdscript
func _land(m: Dictionary) -> void:
    m["landed"] = true
    var at: Vector2 = m["to"]     # <- a raw scatter roll. Could be mid-air, or below the world.
    _apply_damage(at)
    match _effect:
        "fire": _land_fire(at)
        ...


func _apply_damage(at: Vector2) -> void:
    for enemy: Node in targets_in_radius(at, METEOR_IMPACT_RADIUS,
            get_tree().get_nodes_in_group(target_group)):
        # <- no LOS test: damages through walls, "out of the radius"
        if enemy.has_method("take_damage"):
            enemy.take_damage(_damage)
        ...
```

### After

```gdscript
func _land(m: Dictionary) -> void:
    m["landed"] = true
    # THE FIX: the strike lands on the FLOOR under the scatter point, not at the
    # scatter point's own y. No floor there = a pit = no strike at all, rather
    # than a detonation under the world.
    var ground: Dictionary = SpellWorld.floor_below(m["to"] as Vector2, SKY_HEIGHT * 1.5)
    if not bool(ground["hit"]):
        return
    var at: Vector2 = ground["position"]
    m["to"] = at                  # so the in-flight draw ends where the impact is
    _apply_damage(at)
    match _effect:
        "fire": _land_fire(at)
        ...


func _apply_damage(at: Vector2) -> void:
    var in_range: Array = targets_in_radius(at, METEOR_IMPACT_RADIUS,
        get_tree().get_nodes_in_group(target_group))
    # Cover blocks the blast — a meteor on the far side of a wall does not reach you.
    for enemy: Node in SpellWorld.filter_reachable(at, in_range, [], self):
        if enemy.has_method("take_damage"):
            enemy.take_damage(_damage)
        ...
```

The descent itself gets the same treatment for free: because `m["to"]` is now the
resolved floor point, `_draw_fire_meteor` / `_draw_earth_boulder` / `_draw_ice_spike`
all interpolate `from -> to` to the ground and stop there instead of continuing
into it.

---

## Quick reference

```gdscript
SpellWorld.first_solid(from, to, exclude, ctx, smash, mask) -> Dictionary
SpellWorld.first_solid_thick(from, to, thickness, samples, exclude, ctx, smash, mask) -> Dictionary
SpellWorld.clip(from, to, thickness, exclude, ctx, smash, mask) -> Vector2
SpellWorld.floor_below(pos, max_dist, exclude, ctx, smash, mask) -> Dictionary
SpellWorld.floor_point(pos, max_dist, exclude, ctx) -> Vector2
SpellWorld.ground_path(from, to, steps, max_dist, exclude, ctx) -> PackedVector2Array
SpellWorld.is_blocked(pos, radius, exclude, ctx, smash, mask) -> bool
SpellWorld.can_reach(from, to, exclude, ctx, smash, mask) -> bool
SpellWorld.filter_reachable(from, nodes, exclude, ctx, smash, mask) -> Array
SpellWorld.rids(nodes) -> Array[RID]
SpellWorld.is_smashable(collider) -> bool
SpellWorld.space(ctx) / has_world(ctx)
```

All arguments after the first two have defaults. `ctx` is any node in the same
world (pass `self`); omit it and the main loop's root viewport world is used. With
no physics world at all — headless helper suites, teardown — **every function
degrades to "no hit"**, so nothing crashes and nothing silently blocks.

`filter_reachable` is the **one deliberate transform read** in `SpellWorld`: it
reads `global_position` on the target bodies you give it, because an enemy's
transform genuinely is where the enemy is. Pass bodies there, never spell effects.

---

# SpellTargets contract — how a spell stops missing heads and hitting through walls

`godot-project/scripts/combat/SpellTargets.gd`

The third sibling, and the adoption checklist for the ~15 spectacles that currently
select their own victims. It closes two maker-reported bugs that turned out to have
one structural cause:

> "spells pass through heads without registering"

and, again:

> "the spells shouldn't be able to get out the radius"

**Status: headless-verified, UNPLAYTESTED.** Every constant in `SpellTargets.gd` is
reasoning, not feel. See `tools/slice_test_spell_targets.gd`
(`SpellTargets tests: all PASS`).

---

## The three files, and which one you want

| | answers | touches physics |
|---|---|---|
| `SpellGeometry` | "do these two shapes touch, and where?" | no — pure maths |
| `SpellWorld` | "what does the world put in the way?" | yes |
| `SpellTargets` | **"who is actually hit?"** | via `SpellWorld` |

`SpellTargets` is the layer that combines the other two against a list of bodies. If
you are writing a `for e in get_tree().get_nodes_in_group(...)` loop inside a spell,
you want this file — and you almost certainly do not want to write the loop.

---

## Why the head was never a target

`Enemy` draws a `CharacterRig` whose **head centre sits 9.9 px above the node
origin** — 18.9 px on the 1.9x SpellPlayground sparring dummies, 30.4 px on the
Guardian. Every area and line spell in the game tested `enemy.global_position`: a
zero-size point about ten pixels *below* the head being aimed at. You could aim
deliberately into that band and hit nothing. It was never a physics problem; it was
arithmetic, copy-pasted into eight files.

The fix is a duck-typed silhouette test, in the same style as `wall_distance` /
`blink_to` / `reflect` / the `reaction_*` contract:

```gdscript
has_method("body_distance")  ->  distance to the DRAWN body (spine segment + head
                                 circle, scale-aware; negative inside the head)
has_method("hit_margin")     ->  that target's own forgiveness ring, in world px
has_method("head_point")     ->  where the drawn head actually is
...otherwise                 ->  the old point test on `global_position`, margin 0
```

`Enemy` (and `Boss`) publishes all three. `SpikeFigure` publishes `body_distance`
only — which is why each method is picked up **independently**. A crate, a bolt or a
test stub publishes none, and **keeps working byte-identically to the old code**.

---

## The API

```gdscript
SpellTargets.in_radius(center, radius, nodes, skip, ctx, require_los) -> Array
SpellTargets.on_line(origin, dir, length, half_width, nodes, skip, ctx, require_los) -> Array
SpellTargets.in_cone(apex, facing, reach, min_dot, nodes, skip, ctx, require_los) -> Array
SpellTargets.nearest(point, max_reach, nodes, skip, ctx, require_los) -> Node2D
SpellTargets.sorted_by_distance(point, nodes) -> Array
SpellTargets.alive(nodes) -> Array

SpellTargets.hits(target, p, reach) -> bool          # the single-target predicate
SpellTargets.body_distance(target, p) -> float       # INF when there is no body
SpellTargets.hit_margin(target) -> float             # 0.0 when the target has none
SpellTargets.aim_point(target) -> Vector2            # the head, or the origin
```

Everything after `nodes` has a default. `skip` is a list of **nodes** — they are
dropped from the results *and* excluded from the line-of-sight rays; pass the caster.
`ctx` is any node in the same world (pass `self`). `require_los` is **`true` by
default** — see below.

⚠ **World space only, exactly as in `SpellWorld`.** `center` / `origin` / `apex` are
the points your effect computed for itself, never the spell node's transform. A
spectacle parks at the arena origin, so its `global_position` is `(0, 0)`. The one
deliberate transform read is on the **target bodies** you pass in — an enemy's
transform genuinely is where the enemy is.

---

## Replacement 1 — `targets_in_radius`

**Seven** files carry a byte-identical private copy of this helper. (The brief for
this work listed six; `BlinkStrike` was the seventh, found only by grepping — which
is exactly the drift this consolidation exists to end.)

| file | member to delete |
|---|---|
| `BlinkStrike.gd` | `static func targets_in_radius` |
| `BoulderHurl.gd` | `static func targets_in_radius` |
| `DivineRay.gd` | `static func targets_in_radius` |
| `MeteorSigil.gd` | `static func targets_in_radius` |
| `RiftDagger.gd` | `static func targets_in_radius` |
| `RockPillar.gd` | `static func targets_in_radius` |
| `StarConvergence.gd` | `static func targets_in_radius` |

### Before

```gdscript
static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
    var out: Array = []
    for n: Node in nodes:
        if n is Node2D and center.distance_to((n as Node2D).global_position) <= radius:
            out.append(n)
    return out


func _apply_impact_damage(at: Vector2) -> void:
    for enemy: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group("enemy")):
        ...
```

### After

Delete the local helper outright, then:

```gdscript
func _apply_impact_damage(at: Vector2) -> void:
    for enemy: Node in SpellTargets.in_radius(at, _radius,
            get_tree().get_nodes_in_group("enemy"), [caster], self):
        ...
```

That one line fixes **both** bugs at that call site: `in_radius` tests the drawn
silhouette instead of the origin, and routes the survivors through
`SpellWorld.filter_reachable` so nothing behind a wall is damaged.

⚠ The worked `MeteorSigil` example earlier in this document still shows
`targets_in_radius(at, METEOR_IMPACT_RADIUS, ...)` wrapped in an explicit
`SpellWorld.filter_reachable(...)`. That was right when it was written; it is now a
single call — `SpellTargets.in_radius(at, METEOR_IMPACT_RADIUS, ..., [caster], self)`
— and the explicit `filter_reachable` becomes redundant, because LOS is on by default.

---

## Replacement 2 — `targets_on_line` / `targets_on_beam`

Two files, same shape, two names:

| file | member to delete |
|---|---|
| `LightningRush.gd` | `static func targets_on_line` |
| `BeamSpell.gd` | `static func targets_on_beam` |

### Before

```gdscript
static func targets_on_line(origin: Vector2, dir: Vector2, length: float,
        half_width: float, nodes: Array) -> Array:
    var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
    var perp: Vector2 = d.orthogonal()
    var out: Array = []
    for n: Node in nodes:
        if not n is Node2D:
            continue
        var rel: Vector2 = (n as Node2D).global_position - origin
        var proj: float = rel.dot(d)
        if proj < 0.0 or proj > length:
            continue
        if absf(rel.dot(perp)) <= half_width:
            out.append(n)
    return out
```

### After

```gdscript
for enemy: Node in SpellTargets.on_line(_origin, _dir, _length, half,
        get_tree().get_nodes_in_group(target_group), [caster], self):
    ...
```

The argument order is deliberately identical, so the swap is positional.

⚠ **One behaviour change: the corridor is now a CAPSULE, not a box.** The old test
projected onto the axis and rejected anything outside `[0, length]`, giving square
ends; `on_line` clamps to the nearest point on the segment, giving rounded ones. So a
target just past the tip, within `half_width` of it, now registers. That is a reach
increase **of up to `half_width`, at the tip only**. It is chosen deliberately:
`SpellGeometry` already defines a "line" as a capsule and beam-vs-beam / beam-vs-wall
reactions already resolve against capsules, so a beam whose *damage* shape disagreed
with its *reaction* shape would be a fresh two-schemes bug of exactly the kind this
work exists to end.

---

## The inline loops

These have no helper to delete — they hand-roll the loop at the call site. Each row
is the same edit: drop the loop, keep the body.

| file | what it selects today | becomes |
|---|---|---|
| `Hero.gd` `_on_melee_hit_frame` | range + `facing.dot()` arc, over three groups | `SpellTargets.in_cone(global_position, facing, _melee_range, _melee_arc_dot, ...)` |
| `Hero.gd` `_nearest_enemy_in_melee_range` | nearest enemy within range | `SpellTargets.nearest(global_position, _melee_range, ...)` |
| `Spell.gd` `_do_chain` | nearest unvisited enemy per hop | `SpellTargets.nearest(here, CHAIN_RANGE, ..., already)` |
| `ChainBolt.gd` `build_chain` | corridor for hop 1, nearest per hop after | `SpellTargets.on_line(...)` then `SpellTargets.nearest(...)` |
| `BlastSpell.gd` | radius, over enemies + props + projectiles | `SpellTargets.in_radius(...)` |
| `EnergyNova.gd` | radius, over enemies + props + projectiles | `SpellTargets.in_radius(...)` |
| `HollowPurple.gd` | radius around `_p` | `SpellTargets.in_radius(_p, _radius, ...)` |
| `RuneOrbs.gd` | radius around each orb | `SpellTargets.in_radius(...)` |
| `SigilGuard.gd` | radius `HIT_RADIUS` | `SpellTargets.hits(t, at, HIT_RADIUS)` |
| `RiftDagger.gd` | radius `HIT_RADIUS + pad`, three groups | `SpellTargets.hits(n, _pos, HIT_RADIUS + pad)` |
| `BoulderHurl.gd` | in-flight `BOULDER_R + HIT_PAD` | `SpellTargets.hits(e, _pos, BOULDER_R + HIT_PAD)` |
| `BladeFlurry.gd` | radius `RANGE` from `_origin` | `SpellTargets.in_radius(_origin, RANGE, ...)` |
| `EnemyProjectile.gd` | radius `HIT_RADIUS` | `SpellTargets.hits(target, global_position, HIT_RADIUS)` |
| `DrainTether.gd` `_resolve_caster` | nearest hero within `CASTER_ADOPT_R` | `SpellTargets.nearest(origin, CASTER_ADOPT_R, ...)` |
| `ZoneSpell.gd` | group loop over the zone | `SpellTargets.in_radius(...)` |

**The wall / ground band tests are a special case.** `IceWall`, `RockWall`,
`ShadowRoot` and `ShadowCrawler` do not use a radius at all — they test an
axis-aligned band (`absf(p.x - _floor_base.x) > half_width`). The closest honest
mapping is `on_line` along the band's centre line: a vertical segment for the walls, a
ground-following one for the crawlers. That gains them the silhouette test and rounds
the band's ends by `half_width`. Do these one at a time and look at them — they are
the rows most likely to want a feel check rather than a mechanical swap.

At minimum, every one of these should run its group array through
`SpellTargets.alive(...)`. That alone drops nodes already `is_queued_for_deletion()`,
which is how a crate that collapsed earlier in the same frame currently eats a second
hit and a second death spectacle.

---

## Line of sight is the default

`require_los = true` on every selector, so the safe behaviour is what you get by not
thinking about it. Internally it is one call to `SpellWorld.filter_reachable`, which
already owns the pull-back pad, the smash rule (destructible cover does not shield —
it breaks) and the degrade-to-clear behaviour when there is no physics world.

**Opt out only when the fiction says the effect is not line-of-sight.** The known case
is `ShadowCrawler`, documented as passing **under** walls; a ground-borne effect that
follows the floor is the archetype, and `ShadowRoot` is worth a look for the same
reason. "It was easier" is not a reason — killing someone through solid rock is the
worst version of a spell getting out of its radius.

```gdscript
SpellTargets.in_radius(at, r, nodes, [caster], self, false)  # <- the documented opt-out
```

---

## ⚠ What this changes about how big things feel

Read this before tuning any radius, because several of these compound.

* **Targets with no silhouette are unchanged.** Crates, bolts, props, plain
  `Node2D`s, test stubs: `DEFAULT_HIT_MARGIN` is `0.0` and `body_distance` falls back
  to `global_position`, so `in_radius` resolves *identically* to the old formula at
  every radius, boundary included. The suite sweeps 40 radii to prove it. That is what
  makes adopting this in bulk safe.
* **Targets with a silhouette get bigger, deliberately.** For a drawn enemy the test
  is now `radius + hit_margin()` (~3.7 px at rig height 31, ~7 px on a 1.9x dummy)
  measured from the **nearest point of a ~31 px tall body** rather than from a point
  at its middle. Along the vertical axis that is up to half a rig height of extra
  effective reach, on top of the margin. **That growth is the bug fix.** But a radius
  that felt right against origin-point testing will feel noticeably bigger now.
* **So do not stack forgiveness.** Tune the spell's radius, *or* tune
  `Enemy.HIT_MARGIN_FACTOR`. Never both, and never add "a few px of padding" at a call
  site on top of either — a second margin scheme somewhere else is precisely how the
  two-schemes bug started.
* **The cone boundary is strict.** `in_cone` tests `facing.dot(toward) > min_dot`,
  matching Hero's shipped melee exactly. `min_dot = -1.0` therefore admits everything
  *except* a target standing exactly opposite; pass something below `-1.0` for a true
  full circle. Flipping this to `>=` would widen every swing in the game by a hair.

---

## Quick reference

```gdscript
# the blast
for e: Node in SpellTargets.in_radius(at, RADIUS, group, [caster], self):

# the beam / lane
for e: Node in SpellTargets.on_line(origin, dir, length, half_width, group, [caster], self):

# the swing
for e: Node in SpellTargets.in_cone(pos, facing, reach, arc_dot, group, [caster], self):

# the auto-target / chain hop
var target: Node2D = SpellTargets.nearest(pos, reach, group, already_hit, self)

# the one-target check
if SpellTargets.hits(victim, _pos, HIT_RADIUS):

# aim AT someone (a marker, a head-height beam, an impact burst)
var at: Vector2 = SpellTargets.aim_point(victim)   # the head, not their stomach
```
