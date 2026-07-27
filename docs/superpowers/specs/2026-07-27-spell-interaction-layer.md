# Spell Interaction Layer — Phase 3 design spec

> **Scope.** Phase 3 of `docs/references/magic-overhaul-plan.md` (line 44-53): a **curated
> reactions layer** over the equip-one-spell model. ~28 hand-authored reactions emergent from
> element × physical form, authored as DATA so a new spell inherits reactions without touching
> reaction code. Plus the parry/deflect wiring for the 24 signatures.
>
> **LOCKED (maker).** This is NOT Magicka-style live composition. You equip ONE spell. Reactions
> happen when two *already-cast* effects meet in the world. Nothing in this spec proposes
> composing spells at cast time.
>
> **Status.** Design only — no game code was modified producing this document. Phases 0, 1 and
> 2a-2h are committed (`158c319` .. `532f7c1`).

---

## 0. What already exists (verified, with citations)

Every hook the plan promised is real. Confirmed by reading:

| Hook | Where | Notes |
|---|---|---|
| `RockWall` group `"shoveable"` | `scripts/combat/RockWall.gd:79` | added in `raise_wall()`, removed in `_begin_crumble()` (`:261`) |
| `RockWall.shove(dir, speed) -> bool` | `RockWall.gd:152` | returns false if crumbling/sliding; snaps a mid-rise wall solid (`:161`) |
| `RockWall.find_shoveable_near(tree, pos, max_dist)` | `RockWall.gd:113` | duck-typed on `has_method("wall_distance")` (`:119`) |
| `RockWall.footprint_center()` | `RockWall.gd:133` | **its docstring is the trap warning** — see §2.1 |
| `RockWall.wall_distance(pos)` | `RockWall.gd:138` | clamped-rect distance, 0 when touching |
| `IceWall` group `"ice_wall"` | `scripts/combat/IceWall.gd:70` | removed on shatter (`:148`) |
| `IceWall.shatter()` idempotent | `IceWall.gd:142` | guarded by `_shattered` (`:143`); natural expiry calls the same method (`:222`) |
| `Elements.color/emissive/effect_name` | `scripts/combat/Elements.gd:16 / :48 / :82` | 8 elements; `EMISSIVE_PEAK = 1.7` (`:39`) |
| `ZoneSpell.open(...)` | `scripts/combat/ZoneSpell.gd:44` | blizzard (`_effect=="frost"`), consecrate (`"holy"`), legacy void |
| `MeteorSigil.rain(...)` / `_land()` | `scripts/combat/MeteorSigil.gd:89 / :183` | per-element `_land_fire/_land_frost/_land_earth/_land_shadow` (`:229-299`) |
| `BeamSpell.fire(...)` | `scripts/combat/BeamSpell.gd:60` | `_discharge()` (`:150`) is the one-frame damage moment |
| `BeamSpell.targets_on_beam(...)` | `BeamSpell.gd:249` | **pure static** segment test — reuse it for Hollow Purple |
| `ChainBolt.build_chain(...)` | `scripts/combat/ChainBolt.gd:86` | pure static; `FIRST_CORRIDOR` = 46 px aim gate |
| `BoulderHurl.hurl(...)` | `scripts/combat/BoulderHurl.gd:56` | `_check_flight_collision` (`:133`) is where a mid-flight reaction goes |
| `StarConvergence.converge(...)` | `scripts/combat/StarConvergence.gd:40` | |
| Dispatch seam | `scripts/combat/SpellCaster.gd:38` | one match arm per `SpellDef.Kind` |
| Spell data shape | `scripts/combat/SpellDef.gd:16` | `Kind` enum, 16 values, **append-only** |
| 24 signatures | `scripts/combat/SpellLibrary.gd:51` `build_all()` | |
| Duck-typed contract precedent | `RockWall.gd:119`, `SpellCaster.gd:194` (`blink_to`), `IceWall.gd:175` (`consume`) | the project's idiom for cross-system hooks |

Existing groups in use: `enemy`, `hero`, `player`, `destructible`, `enemy_projectile`,
`player_spell`, `shoveable`, `ice_wall`, `breakable_platform`, `stage_hazard`, `dummy`.

Autoloads today (`project.godot`): `MCPRuntime, Conversation, Sfx, Music, Rank, GameState,
Tuning, ClassSelect, Loadout, Net`.

---

## 1. THE DATA SHAPE

### 1.1 Why the key is (form, form) + element predicate — not (kind, kind)

`SpellDef.Kind` has 16 values and is append-only by contract (`SpellDef.gd:14-16`). Keying the
matrix on Kind gives a 16×16×8×8 space that is (a) mostly empty, (b) hostile to the "new spell
inherits reactions" requirement — a new `Kind` would inherit **nothing**, which is exactly the
failure mode the plan's last bullet forbids.

So the reaction axis is a coarse **physical FORM**, derived from Kind but deliberately lossy:

```gdscript
# ReactionDef.gd
enum Form {
	BEAM,        # a live damaging LINE SEGMENT   — BeamSpell, LightningRush, ChainBolt link, DivineRay column
	BARRIER,     # a standing SOLID                — RockWall, IceWall
	FIELD,       # a persistent GROUND AREA        — ZoneSpell (blizzard/consecrate/void), ShadowRoot grasp, ember pool
	PROJECTILE,  # a MOVING body                   — BoulderHurl in flight, RuneOrbs, Spell bolt, a SHOVED RockWall, a falling meteor
	IMPACT,      # an INSTANT point detonation     — meteor land, boulder impact, nova, convergence, blink cut, pillar erupt
	AURA,        # a body-attached state volume    — reserved: burning/chilled enemies, hero element aura
}
```

Six forms → a 6×6 upper-triangular key space of 21 buckets. A new spell picks `form` +
`element` and instantly inherits every row whose predicates it satisfies. **That is the whole
point of this shape.** `_FORM_FOR_KIND` maps the 16 kinds onto the 6 forms in one place, and a
spell may override with an explicit `reaction_form` field on `SpellDef` when the default is
wrong (e.g. `ZONE` forks to `ShadowRoot` at `SpellCaster.gd:147`, which is FIELD, not a placed
puddle).

### 1.2 `ReactionDef` — the authored row

A `Resource` so it is `.tres`-authorable later, exactly like `SpellDef` (`SpellDef.gd:1-9`),
while the *shipped* table lives in a static code library, exactly like `SpellLibrary`.

```gdscript
class_name ReactionDef
extends Resource
## ONE curated reaction: "when a thing of form A and element A meets a thing of form B and
## element B, this happens." Keyed on FORM + element PREDICATE (never on spell id), so a
## newly-authored spell inherits every row it matches without editing reaction code.

enum Form { BEAM, BARRIER, FIELD, PROJECTILE, IMPACT, AURA }

@export var id: String = ""                  # stable key, e.g. "fire_beam_shatters_ice_wall"
@export var display_name: String = ""        # for the playground HUD readout

# --- the key -------------------------------------------------------------
@export var form_a: int = Form.BEAM
@export var form_b: int = Form.BARRIER
## Element predicates. EMPTY = "any element" (this is how generic fallback rows are written).
@export var elements_a: PackedInt32Array = PackedInt32Array()
@export var elements_b: PackedInt32Array = PackedInt32Array()
## Element-RELATIONSHIP predicates, checked after the sets. Lets one row cover all four
## opposed pairs (Hollow Purple) instead of authoring 4 near-duplicate rows.
@export var require_opposed: bool = false    # Elements.opposed(a) == b
@export var require_same: bool = false       # a == b

# --- what happens --------------------------------------------------------
@export var outcome: String = ""             # dispatch key into ReactionOutcomes (§3)
@export var priority: int = 0                # highest priority wins when several rows match
@export var consumes_a: bool = false         # reaction destroys reactant A (calls reaction_consume)
@export var consumes_b: bool = false
@export var suppress: bool = false           # NULL ROW: match, do nothing, block lower-priority rows

# --- tunables the outcome reads -----------------------------------------
@export var damage: int = 0
@export var radius: float = 0.0
@export var knockback: float = 0.0
@export var status: int = -1                 # Elements.Element applied in the AoE, -1 = none
@export var duration: float = 0.0            # for outcomes that spawn a lingering thing
@export var scale: float = 1.0               # generic multiplier (bigger detonation, extra hops)

# --- pacing --------------------------------------------------------------
## ONE_SHOT: this exact (instance A, instance B) pair reacts at most once, ever.
## SUSTAINED: re-fires on `cooldown` while the pair keeps overlapping (field × field).
@export var repeat: int = Repeat.ONE_SHOT
@export var cooldown: float = 0.0
enum Repeat { ONE_SHOT, SUSTAINED }
```

### 1.3 The table + lookup

```gdscript
class_name SpellReactions
extends RefCounted
## The curated reaction MATRIX. Static tables only — mirrors Elements.gd / MemoryUtils.gd.

## bucket key -> Array[ReactionDef], built once, cached.
static var _table: Dictionary = {}

## Canonical bucket key. (BEAM, BARRIER) and (BARRIER, BEAM) MUST land in the same bucket,
## so the smaller form index is always first and the caller is told whether it was swapped.
static func bucket_key(fa: int, fb: int) -> int:
	return (mini(fa, fb) << 4) | maxi(fa, fb)

## Best matching row for a candidate pair, or null. `a`/`b` are Reactant descriptors (§2.2).
## Returns {"def": ReactionDef, "swapped": bool} so the outcome knows which reactant is A.
static func match_pair(a: Dictionary, b: Dictionary) -> Dictionary:
	var rows: Array = _table.get(bucket_key(a["form"], b["form"]), [])
	var best: ReactionDef = null
	var best_swapped: bool = false
	for r: ReactionDef in rows:
		if _fits(r, a, b):
			if best == null or r.priority > best.priority:
				best = r; best_swapped = false
		elif _fits(r, b, a):
			if best == null or r.priority > best.priority:
				best = r; best_swapped = true
	if best == null or best.suppress:
		return {}
	return {"def": best, "swapped": best_swapped}
```

`_fits()` is the only predicate logic: form equality, element-set membership (empty = wildcard),
then `require_opposed` / `require_same`. It is a pure static function — first test suite target.

### 1.4 The opposed-element table (new, lives on `Elements.gd`)

Hollow Purple is "red + blue → purple, made literal". That needs an authored opposition:

```gdscript
# Elements.gd — appended, no existing behaviour touched
const OPPOSED: Dictionary = {
	Element.FIRE: Element.ICE,      Element.ICE: Element.FIRE,
	Element.LIGHTNING: Element.EARTH, Element.EARTH: Element.LIGHTNING,
	Element.SHADOW: Element.HOLY,   Element.HOLY: Element.SHADOW,
	Element.ARCANE: Element.WIND,   Element.WIND: Element.ARCANE,
}
static func opposed(e: int) -> int:
	return int(OPPOSED.get(e, -1))
```

Four opposed pairs → four Hollow Purples with four different final colours, from ONE row.

### 1.5 Worked example — the exact authored entries

**(a) The headliner. One row covers all four opposed beam pairs.**

```gdscript
static func _hollow_purple() -> ReactionDef:
	var r := ReactionDef.new()
	r.id = "hollow_purple"
	r.display_name = "HOLLOW PURPLE"
	r.form_a = ReactionDef.Form.BEAM
	r.form_b = ReactionDef.Form.BEAM
	r.require_opposed = true          # FIRE×ICE, LIGHTNING×EARTH, SHADOW×HOLY, ARCANE×WIND
	r.outcome = "hollow_purple"
	r.priority = 100                  # beats every generic BEAM×BEAM row
	r.consumes_a = true
	r.consumes_b = true
	r.damage = 0                      # computed from the two beams at fire time (§4.5)
	r.radius = 220.0
	r.knockback = 900.0
	r.repeat = ReactionDef.Repeat.ONE_SHOT
	return r
```

**(b) The bread-and-butter row, and the one that proves inheritance.**

```gdscript
static func _fire_shatters_ice_barrier() -> ReactionDef:
	var r := ReactionDef.new()
	r.id = "fire_shatters_ice_barrier"
	r.display_name = "Ice wall shatters"
	r.form_a = ReactionDef.Form.BEAM
	r.form_b = ReactionDef.Form.BARRIER
	r.elements_a = PackedInt32Array([Elements.Element.FIRE, Elements.Element.HOLY])
	r.elements_b = PackedInt32Array([Elements.Element.ICE])
	r.outcome = "shatter_barrier"     # calls IceWall.shatter() — the hook at IceWall.gd:142
	r.priority = 10
	r.consumes_b = true
	r.scale = 1.6                     # shard-burst AoE scaled up vs a natural expiry
	return r
```

There is a **sibling row with `form_a = IMPACT`** and the same predicate/outcome. Between the
two, *every* fire-flavoured thing in the game — Infernal Lance, a fire meteor landing, a
Judgment column, a nova, a burning boulder — shatters an ice wall, and a spell added next month
that is `effect = "fire"` and lands as an `IMPACT` inherits it with **zero code edits**. That is
the acceptance test for the whole data shape (§8, T1).

---

## 2. DETECTION — how two live effects notice each other

### 2.1 ⚠ THE TRAP: `global_position` is (0,0) for almost every spectacle

Verified across the codebase. These scripts explicitly park the node at the arena origin and
draw in **world coordinates** from a private field:

```
BeamSpell.gd:76      global_position = Vector2.ZERO   # draws from _origin
ZoneSpell.gd:54                                        # draws from _at
ChainBolt.gd:56, :74                                   # draws from _points
BladeFlurry.gd:47 · BlinkStrike.gd:28 · DrainTether.gd:39
LightningRush.gd:62 · RuneOrbs.gd:48 · ShadowRoot.gd:63
```

`RockWall` / `IceWall` never assign it at all — the node inherits the parent's origin and the
real wall lives in `_floor_base`. `RockWall.gd:128-134` documents this in so many words:

> *"the wall node sits at the arena origin and everything is drawn in world coordinates, so
> `global_position` is not the wall — callers deciding 'is it to my left or my right' must ask
> for this."*

`SpellPlaygroundController.gd:145-148` already had to work around it for the shove.

**Consequence for a naive detector:** `a.global_position.distance_to(b.global_position)` returns
`0.0` for *every* pair of live spectacles. The symptom is not "nothing works" — it is *"every
reaction fires instantly, all of them, at the top-left of the arena."* That is a half-day of
confused debugging if it is not designed out. `MeteorSigil` and `BoulderHurl` are the exceptions
(`_center`, `_pos`) and would work, which makes the bug *intermittent* and therefore worse.

**Design rule: the detector never reads `global_position`.** Geometry is supplied explicitly.

### 2.2 The Reactant contract (duck-typed, opt-in, additive)

Three methods on a spell node, following the project's existing duck-typed idiom
(`wall_distance` / `shove` / `consume` / `blink_to`):

```gdscript
## World-space geometry of this effect RIGHT NOW. Never derived from global_position.
##   {"shape": Shape.SEGMENT, "a": Vector2, "b": Vector2, "r": float}   # BEAM, thickness r
##   {"shape": Shape.CIRCLE,  "a": Vector2, "r": float}                 # FIELD / IMPACT / PROJECTILE
##   {"shape": Shape.RECT,    "a": Vector2, "b": Vector2}               # BARRIER (min, max corners)
func reaction_shape() -> Dictionary

## True only while this effect can actually react — a CHARGING beam must not.
func reaction_active() -> bool

## The reaction destroyed this effect: tear down WITHOUT firing the normal end-of-life beat.
func reaction_consume() -> void
```

Reference implementations (each ~5 lines, no behaviour change):

```gdscript
# BeamSpell.gd
func reaction_shape() -> Dictionary:
	return {"shape": 0, "a": _origin, "b": _beam_tip(), "r": _width * 0.5 + 8.0}  # matches _apply_beam_damage's half-width
func reaction_active() -> bool:
	return _fired and _elapsed < CHARGE_TIME + FIRE_TIME          # firing, not charging, not fading
func reaction_consume() -> void:
	if _circle != null and is_instance_valid(_circle): _circle.vanish(0.12)
	queue_free()

# IceWall.gd
func reaction_shape() -> Dictionary:
	var hw := WALL_SIZE.x * 0.5
	return {"shape": 2, "a": _floor_base - Vector2(hw, WALL_SIZE.y), "b": _floor_base + Vector2(hw, 0.0)}
func reaction_active() -> bool:
	return _elapsed >= 0.0 and not _shattered
func reaction_consume() -> void:
	shatter()                                                     # already idempotent (IceWall.gd:143)
```

`reaction_active()` gating is load-bearing: without it, two beams crossing **during their 0.34 s
charge telegraph** (`BeamSpell.CHARGE_TIME`, `:33`) would trigger Hollow Purple before either
beam existed on screen.

### 2.3 The four candidate mechanisms, judged

| Mechanism | Cost | Fit with this codebase | Verdict |
|---|---|---|---|
| **Groups + overlap polling** | `get_nodes_in_group()` allocates a fresh `Array` per call; needs one group per form → 6 allocations per tick, plus the geometry re-derived every tick | Idiomatic (the codebase polls groups constantly). But there is nowhere to hang the one-shot pair memo, the SUSTAINED cooldown, or a global budget — each would have to be duplicated into every spell script | Workable, but leaks bookkeeping into 24 files |
| **Area2D + collision layers** | Free broad-phase (the physics server does it) | **Reject.** Spectacles have no colliders — they are pure `Node2D` `_draw` in world coords. Retrofitting 24 shapes is enormous, and the origin-parked node means every `CollisionShape2D` transform would have to be manually world-offset anyway, i.e. all the work of the explicit-geometry approach *plus* physics-server overhead and a per-frame `body_entered` cadence we do not control. Two walls already own real `StaticBody2D`s on layer 1 for *blocking*; reusing those for reactions would make beams collide with walls as terrain | Reject |
| **Signals** | Cheapest at fire time | No natural emitter. Every spell would have to know about every other spell to connect — the exact coupling the data table exists to prevent | Reject |
| **Central registry autoload** | One typed array, no per-tick allocation; cached geometry; single place for memo/cooldown/budget | Matches the existing autoload roster (`Sfx`, `Rank`, `Tuning`, `Loadout`); registration is 1 line per spell; unregistered spells simply never react, so it can land dark and be lit up spell-by-spell | **RECOMMENDED** |

### 2.4 RECOMMENDED: `SpellReactor` — a central registry autoload

```gdscript
# scripts/combat/SpellReactor.gd  — autoload "SpellReactor"
class_name SpellReactorNode
extends Node

const TICK_HZ: float = 30.0            # reactions resolve at 30 Hz, not 120 — a 33 ms latency
const MAX_LIVE: int = 12               # hard cap on tracked reactants
const MAX_REACTIONS_PER_TICK: int = 2  # a meteor barrage inside a void zone must not fire 11x

var _live: Array[Dictionary] = []       # {node, form, element, shape, active}
var _memo: Dictionary = {}              # "idA:idB:rowid" -> true (ONE_SHOT) / next_time (SUSTAINED)

func register(node: Node, form: int, element: int) -> void
func unregister(node: Node) -> void
```

**The loop, and why it is not O(24²) per frame:**

1. **`24` is the size of the spell LIBRARY, not the live count.** Realistic concurrency is 1-4
   effects; `MAX_LIVE` caps it at 12. Worst case is 12·11/2 = **66 pairs** per tick, at 30 Hz.
2. **Stage 1 — validity sweep.** Drop entries where `not is_instance_valid(node)` or
   `not node.reaction_active()`. Typically leaves 0-3 entries, and with fewer than 2 the whole
   tick returns immediately. **This is the common case: zero work.**
3. **Stage 2 — table gate, before any geometry.** For each pair, one `Dictionary` lookup on
   `bucket_key(form_a, form_b)`. The matrix is sparse (21 possible buckets, ~14 populated), so
   most pairs die on a dict miss having cost one integer shift and one hash. **No `Vector2` maths
   is done for a pair that has no authored reaction.**
4. **Stage 3 — element predicate.** `_fits()` on the ≤4 rows in the bucket. Integer set tests.
5. **Stage 4 — geometry.** Only now call `reaction_shape()` on both and run the overlap test.
   Cache the shape per node per tick so a node in three pairs computes it once.
6. **Stage 5 — memo + budget.** Skip if this `(instance_a, instance_b, row)` already fired
   (`ONE_SHOT`) or is still on `cooldown` (`SUSTAINED`). Stop after `MAX_REACTIONS_PER_TICK`.

Net: the steady-state cost with nothing cast is a single `is_empty()` check 30×/second. With a
beam and a wall live it is one dict lookup, one predicate, one segment-vs-rect test.

**Instance-id memo, not node references** — `_memo` keys off `get_instance_id()` so a freed node
cannot keep the dictionary alive; the validity sweep also prunes memo keys for dead ids.

**Registration is one line** inside each spell's existing entry function, e.g. at the end of
`BeamSpell.fire()`: `SpellReactor.register(self, ReactionDef.Form.BEAM, element_id)`. No existing
call path changes. A spell that is not registered is not in the system — which is what makes the
rollout incremental and each task independently shippable.

### 2.5 `ReactionGeometry` — pure static overlap tests

All in one `RefCounted`, all pure, all headless-testable with no physics world (mirrors
`BeamSpell.targets_on_beam`, `ChainBolt.build_chain`, `BoulderHurl.targets_in_radius`):

```gdscript
static func segment_x_segment(a0, a1, b0, b1) -> Dictionary   # {"hit": bool, "point": Vector2, "ta": float, "tb": float}
static func segment_x_rect(a0, a1, rmin, rmax) -> Dictionary  # {"hit": bool, "point": Vector2}  (slab test)
static func segment_x_circle(a0, a1, c, r) -> Dictionary
static func circle_x_circle(c0, r0, c1, r1) -> Dictionary
static func rect_x_circle(rmin, rmax, c, r) -> Dictionary
```

`segment_x_segment` must return the **intersection point and both parameters** — Hollow Purple
needs the exact cross point *and* how far along each beam it sits (to bend the correct portion of
each beam into the collapse, §4).

---

## 3. THE REACTION TABLE — ~28 rows

`◆` = headliner, must land first. Outcome names are dispatch keys in `ReactionOutcomes.gd`.
"Fires from" = which existing script's registration puts the reactant in play.

### Tier 1 — the headliners (T3-T5)

| # | Trigger pair | Outcome | Fires from | New VFX |
|---|---|---|---|---|
| ◆1 | **BEAM × BEAM**, elements OPPOSED, segments cross | `hollow_purple` — freeze → collapse → silence → purple annihilation lance + ring. Both beams consumed. §4 | `BeamSpell` ×2 (also `LightningRush`; also a Boss beam vs the hero's — `BeamSpell.target_group`, `:6`) | **`HollowPurple.gd`** — bespoke node, 4-beat timeline, own `_draw` |
| ◆2 | **BEAM(fire\|holy) × BARRIER(ice)** — and its `IMPACT × BARRIER(ice)` sibling row | `shatter_barrier` — `IceWall.shatter()` with `scale` 1.6 on the shard AoE | `BeamSpell`/`MeteorSigil`/`DivineRay` × `IceWall` | reuse `IceWall._draw_shatter` (`:290`), + a steam wisp at the contact face |
| ◆3 | **BEAM\|IMPACT(fire) × FIELD(ice)** (blizzard) | `steam_cloud` — the blizzard's remaining lifetime converts to a rising steam volume: obscures line-of-sight, applies a slow (soft-CC), no damage | `BeamSpell`/`MeteorSigil` × `ZoneSpell` (`_effect=="frost"`) | **`SteamCloud.gd`** — a drifting translucent volume; the one reaction whose payoff is *vision*, not damage |
| ◆4 | **BEAM(lightning) × FIELD(ice)**, and **IMPACT(lightning) × AURA(chilled enemy)** | `supercharge_chain` — `+scale` hops and `+40%` damage on the next chain; the arcs render fatter and branch | `ChainBolt`/`LightningRush` × `ZoneSpell`/`StatusComponent` | branched arc draw + a conducting shimmer on the frost field |
| ◆5 | **BARRIER(rock, SLIDING) × enemy body** | `plow_pin` — the existing `_plow_enemies` (`RockWall.gd:344`) upgraded: on a plow that ends against world geometry, the caught enemy is **pinned** (rooted for 0.8 s) instead of merely knocked | `RockWall` while `_sliding` | pin-crush impact frame + a crumple decal at the pin point |
| ◆6 | **PROJECTILE(earth, boulder) × BARRIER(ice)** | `shatter_shrapnel` — *not* the radial shatter: a **directional shard cone** along the boulder's travel vector, and the boulder keeps flying with reduced radius | `BoulderHurl` (from `_check_flight_collision`, `:133`) × `IceWall` | **`ShardCone.gd`** — directional variant of the shatter burst |
| ◆7 | **IMPACT(any) × FIELD(shadow)** (void zone) | `void_charged` — the detonation is void-charged: 1.8× radius, 1.5× damage, knockback **inverted to a pull** (matching `_land_shadow`'s implosion, `MeteorSigil.gd:289`) | `MeteorSigil`/`BoulderHurl`/`StarConvergence` × `ZoneSpell` | dark-rimmed detonation + inward mote pull |

*(The plan lists 7 headliners; 1-6 are the must-land-first set, 7 lands in the same batch if T5 has room.)*

### Tier 2 — destructive / dramatic (T5)

| # | Trigger pair | Outcome | Fires from | New VFX |
|---|---|---|---|---|
| 8 | BEAM(fire) × BARRIER(rock) | `superheat_barrier` — wall becomes MOLTEN: glowing seams, and a subsequent `shove()` applies burn + doubles plow damage | `BeamSpell` × `RockWall` | molten overlay tint (a `_molten` flag in `RockWall._draw`) |
| 9 | BEAM(lightning) × BARRIER(rock) | `ground_out` — the beam is EARTHED: absorbed at the wall, a discharge ring bursts at the wall base, no through-damage | `BeamSpell`/`LightningRush` × `RockWall` | arc-to-ground burst |
| 10 | BEAM(holy) × BARRIER(rock) | `carve_through` — a clean hole is punched; the wall survives with a gap (collider split into two) | `DivineRay`/`BeamSpell` × `RockWall` | bored-hole silhouette edit |
| 11 | IMPACT(fire) × BARRIER(rock) | `spall` — the struck face flakes off toward the impact; wall thins, `LIFETIME` cut | any IMPACT × `RockWall` | `DebrisChunk` cone (exists) + face-notch redraw |
| 12 | PROJECTILE(any) × BARRIER(any) — **generic fallback** | `block_and_stress` — projectile consumed, barrier takes structural damage. Priority 0, so any specific row above wins | all | none (reuses existing bursts) |
| 13 | PROJECTILE × PROJECTILE, OPPOSED | `mutual_annihilation` — mid-air pop, small purple flash. The cheap, accessible Hollow Purple | `RuneOrbs`/`Spell`/`BoulderHurl` | shared `ReactionSpark` |
| 14 | BEAM(ice) × FIELD(fire) (ember pool, `MeteorSigil.gd:707`) | `quench` — the pool is snuffed, a steam puff | `BeamSpell` × ember pool | reuse `SteamCloud` at small scale |
| 15 | PROJECTILE(fire) × FIELD(ice) | `quench_projectile` — the projectile is ice-clad: damage halved, no burn | `BoulderHurl`/`RuneOrbs` × `ZoneSpell` | frost crust on the projectile draw |
| 16 | IMPACT(earth) × FIELD(any) | `displace_field` — the ground erupts through the field: radius cut 40 %, the field is visibly torn | `RockPillar`/`BoulderHurl` × `ZoneSpell` | field-tear ring |
| 17 | BEAM\|IMPACT(holy) × FIELD(shadow) | `burn_out_void` — the void field collapses, a radiant purge ring expands | `DivineRay` × `ZoneSpell`/`ShadowRoot` | purge ring |
| 18 | IMPACT(shadow) × FIELD(holy) (consecrate) | `desecrate` — mutual cancel: both die, a grey null-ring | `MeteorSigil` × `ZoneSpell` | null-ring (desaturated) |
| 19 | BEAM(shadow) × BARRIER(ice) | `embrittle` — the wall does NOT shatter; it goes dark and brittle, and its next shatter deals 2× | `BeamSpell` × `IceWall` | dark crack veins in `IceWall._draw` |
| 20 | FIELD(ice) × FIELD(shadow), SUSTAINED | `black_blizzard` — both lifetimes extended, tick damage merged, palette goes violet-white | `ZoneSpell` ×2 | palette blend (data-driven, no new node) |

### Tier 3 — constructive / utility (T6)

| # | Trigger pair | Outcome | Fires from | New VFX |
|---|---|---|---|---|
| 21 | BEAM(ice) × BARRIER(ice), SAME element | `reinforce_barrier` — spires regrow, `LIFETIME` +2.5 s, wall widens. **Friendly reactions matter**: a matrix where every meeting is destruction teaches players to never stack their own elements | `BeamSpell` × `IceWall` | regrow tween on existing spire draw |
| 22 | IMPACT(earth) × BARRIER(rock), SAME | `reinforce_barrier` — a fifth slab is added, wall gets taller | `RockPillar` × `RockWall` | reuse `_build_slabs` |
| 23 | BEAM(wind) × FIELD(fire) | `fan_flames` — fire field radius +50 %, damage +30 %, drifts downwind | `BeamSpell` × ember pool | drift offset on the existing field draw |
| 24 | BEAM(wind) × FIELD(any) | `blow_field` — the field is TRANSLATED downwind over 0.4 s (priority below 23) | `BeamSpell` × `ZoneSpell` | none (animate `_at`) |
| 25 | BEAM(wind) × steam cloud | `disperse` — the cloud is blown apart, vision restored instantly | `BeamSpell` × `SteamCloud` | fade-and-streak |
| 26 | BEAM × BEAM, SAME element | `resonance` — no annihilation: both beams widen 40 % for their remaining `FIRE_TIME` and a bright bloom sits at the cross. Deliberately *nice*, so same-element crossing is not a dud | `BeamSpell` ×2 | cross-point bloom |
| 27 | BEAM × BEAM, neither opposed nor same | `splinter` — both refract at the cross: a small scatter burst, tiny damage, no consumption. Every crossing gets *some* beat | `BeamSpell` ×2 | shared `ReactionSpark` |
| 28 | IMPACT(lightning) × BARRIER(rock) — **NULL ROW** | `suppress = true` — matches, does nothing, blocks the generic row 11 from making stone spall to a lightning hit | — | none |

**Shared VFX to build once:** `ReactionSpark` (a small element-blended contact burst used by every
low-tier row, so nothing is silent) and `ReactionLabel` (a playground-only floating readout of the
row's `display_name` — the maker needs to *see* which row fired when tuning).

---

## 4. HOLLOW PURPLE — full implementation detail

The showcase. It must not be a recoloured `CombatVfx.spawn_burst`. Its budget is a bespoke node
with its own timeline and `_draw`, on the order of `MeteorSigil`'s complexity, and it should be
the only thing in the game that *stops the screen*.

### 4.1 Trigger conditions (all must hold)

- Two registered reactants, both `form == BEAM`, both `reaction_active()` (i.e. `_fired` and
  inside `FIRE_TIME` — **not** during the 0.34 s charge).
- `Elements.opposed(elem_a) == elem_b`.
- `ReactionGeometry.segment_x_segment` reports a hit with `0.08 < ta < 0.97` and
  `0.08 < tb < 0.97` — the cross must be in the *body* of both beams, not a muzzle graze.
- Both beams at least 300 px long (no two stubs faking it).
- `SpellReactor` holds no live `HollowPurple` (a global one-shot; the node registers a
  `"hollow_purple_live"` flag and clears it on free).

### 4.2 The four beats

Total ~1.9 s. `P` = the cross point.

**Beat 1 — SEIZE (t 0 → 0.10).** The frame it triggers:
- Both beams are **frozen, not deleted** — a new contract method `reaction_freeze()` pins each
  beam's `_elapsed` and suspends further damage while leaving it drawn at current intensity.
  Freezing rather than deleting is the whole read: the player sees their own beam get *caught*.
- `Juice.hit_stop(0.12)` (`Juice.gd:10`), `Juice.shake_camera(18.0)`.
- `PostProcess.shock(1.0, uv)` (`PostProcess.gd:132`) — **note the seam:** `shock` takes a
  *screen-space UV* centre, so `P` must be projected through the active `Camera2D`. Every other
  caller passes the default `(0.5, 0.5)`; a `Juice.world_to_uv(P)` helper is the clean addition
  and it also serves the localized `impact_frame` work from Phase 0.
- A single white flash frame at `P`.

**Beat 2 — COLLAPSE (t 0.10 → 0.45).** The two beams are *drunk in*:
- Each frozen beam is redrawn as a **curve** whose far portion bends toward `P` and whose tip is
  swallowed — sampled along a quadratic with the control point pulled toward `P`, so the beams
  visibly *hook* inward rather than fade.
- Two counter-rotating lobes at `P`, one in `Elements.emissive(elem_a)`, one in
  `Elements.emissive(elem_b)`, spiralling into a shrinking gap between them. The gap never
  closes during this beat — that unresolved tension is the anticipation.
- `Juice.zoom_pull_camera(0.28, 0.9, 0.18, 0.6)` — wider than `StarConvergence`'s 0.22
  (`SpellCaster.gd:88`), which is currently the widest pull in the game. Hollow Purple should
  out-scale the existing finisher.
- `PostProcess.set_theme` (`:139`) eased toward a desaturated cold grade.
- Loose debris/particles in a 400 px radius are drawn drifting *inward*.

**Beat 3 — SILENCE (t 0.45 → 0.63).** The beat that makes it JJK and not a purple explosion:
- Everything stops. A **pure black disc** at `P` (drawn at a high `z_index`, over the arena) with
  a razor-thin white event-horizon ring — negative space, not light.
- No sfx at all for 180 ms. The game is loud constantly; 180 ms of nothing is the loudest thing
  available and costs zero assets.
- Screen grade at its most desaturated. Camera fully pulled, dead still (no shake).

**Beat 4 — DETONATION (t 0.63 → ~1.6).** The disc inverts:
- A **purple annihilation LANCE** fires along the **angle bisector** of the two beams'
  directions — so it reads as the two beams' *combined output*, and it is aimable-by-play (the
  second caster chooses the bisector by choosing their angle). Length = `max(len_a, len_b)`,
  width = `(w_a + w_b) * 2.2`.
- Plus a radial annihilation ring at `P`, radius `r.radius` (220), expanding hard.
- **The colour is computed, not authored** — this is what "red + blue → purple, made literal"
  means in the code:
  ```gdscript
  var ca: Color = Elements.color(elem_a)
  var cb: Color = Elements.color(elem_b)
  var summed := Color(ca.r + cb.r, ca.g + cb.g, ca.b + cb.b, 1.0)   # additive light mixing
  var peak: float = maxf(summed.r, maxf(summed.g, summed.b))
  var core := Color(summed.r, summed.g, summed.b) * (Elements.EMISSIVE_PEAK * 1.35 / maxf(peak, 0.001))
  ```
  FIRE `(1.0,0.45,0.15)` + ICE `(0.5,0.85,1.0)` → `(1.5,1.3,1.15)` → a searing near-white violet
  core with the two parent hues bleeding at the rim. Each of the four opposed pairs therefore
  gives a *different* Hollow Purple, from one row of data.
- **Damage, in two parts:**
  - Radial: `(dmg_a + dmg_b) * 1.6` to everything within `radius` of `P`, knockback
    `r.knockback` (900) directly away from `P` — far above `BoulderHurl.KNOCKBACK` (460).
  - Corridor: the same damage along the lance, reusing **`BeamSpell.targets_on_beam`**
    (`BeamSpell.gd:249`) — a pure static already covered by the beam tests, so the lance's hit
    test needs no new geometry code and is deterministically testable.
  - Destructibles in radius/corridor take `damage_at`; `enemy_projectile` nodes in range are
    `consume()`d (the pattern at `IceWall.gd:173` / `BoulderHurl.gd:193`).
- Ground residue: a **near-black "erased" scar** along the lance (`ScorchDecal.spawn` with a
  near-zero tint, long lifetime) — the ground is *gone*, not burned — plus a
  `DestructibleTerrain` carve where one exists.
- `Juice.epic_moment()` (`Juice.gd:79`) + `Juice.impact_frame(1.0, P)` + a layered
  `Sfx.play("blast")` and `Sfx.play("beam", -6.0, -0.35)` pitched down.

### 4.3 Consumption

`consumes_a` and `consumes_b` are both true. `reaction_consume()` on a `BeamSpell` dismisses its
muzzle sigil and frees it **without** running `_impact_burst`/`_impact_mark` — the beams did not
land, they were eaten. This is exactly why `reaction_consume()` exists as a separate verb from
`queue_free()`.

### 4.4 Who can trigger it

- **Co-op, two players, opposed elements** — the intended showcase. Friendly fire is already ON.
- **Solo vs a boss** — `BeamSpell.target_group` (`:6`) exists precisely so the Boss fires the
  same beam at the hero. A boss beam crossing the player's inherits Hollow Purple for free. Worth
  saying out loud in the spec: **a boss with an opposed-element beam becomes a Hollow Purple
  puzzle at zero extra cost**, which is a genuine encounter-design lever.
- **Solo, one caster** — not possible today (one beam at a time). Deliberately left alone; a
  "leave a beam suspended" mechanic would be a new spell, not a reaction.

### 4.5 Guards against the obvious ways this gets annoying

Global one-shot while live; minimum beam length; body-of-beam cross parameters; the whole thing
respects `Tuning` so the maker can dial the freeze and silence durations live; and the hitstop
is routed through `Juice.hit_stop`, which already honours the hit-stop toggle (`Juice.gd:22`).

---

## 5. PARRY / DEFLECT WIRING

### 5.1 Why only the basic bolt is deflectable today — the precise reason

`Hero.try_parry` (`Hero.gd:1721`) is a **passive receiver**. It never scans for anything; it only
runs when something calls it. There is exactly one caller in the game:
`EnemyProjectile._check_hit` (`EnemyProjectile.gd:153`).

That caller works because `EnemyProjectile` satisfies two assumptions baked into the mechanism:

1. **It is a moving point body that re-queries a target group every physics frame**
   (`_check_hit`, `:144-161`), so there is a frame at which it can ask "am I being parried?"
2. **Its allegiance is a single boolean.** `reflect(new_dir, color)` (`:62`) flips `_reflected`,
   and `_check_hit` swaps the queried group from `"hero"` to `"enemy"` on that one flag (`:145`).

The parry contract is literally `proj.has_method("reflect")` (`Hero.gd:1724`).

**None of the 24 signatures satisfy either assumption.** They are one-shot `Node2D`s that draw in
world coordinates and apply damage **once**, via a static geometry query against a group fixed at
spawn — `BeamSpell._apply_beam_damage` (`:234`) over `target_group` (`:6`); `MeteorSigil._apply_damage`
(`:203`); `BoulderHurl._apply_impact_damage` (`:179`). There is no per-frame proximity query on the
hero, so **nothing ever calls `try_parry`**, and none of them has a `reflect()` method, so even if
something did, the guard at `Hero.gd:1724` would refuse.

There is one partial exception worth stating so it is not mistaken for coverage: `Hero.take_damage`
has a parry branch (`Hero.gd:2018`) that negates *any* incoming damage while the window is open.
A hostile beam does call `take_damage`, so an open window does blank it — but as a silent
damage-negate only. No reflect, no directional shield flourish toward the source, no spectacle,
and no reason for the player to understand what happened.

The playground rig is the mirror image and has the same two assumptions: `SpikeFigure._process_projectiles`
(`:924-948`) polls group `"enemy_projectile"`, requires `has_method("reflect")` (`:935`), and reads
`_reflected` (`:931`).

### 5.2 What it takes — data first

The asymmetry the plan calls for ("most things deflectable, a giant ult may BREAK THROUGH")
**must be data on the spell**, per the brief. Add to `SpellDef`:

```gdscript
# SpellDef.gd — appended fields, existing defaults unchanged
enum Deflect { FULL, PARTIAL, BREAKS_THROUGH }
## FULL           — a parry turns the spell around: reversed / mirrored back at its caster.
## PARTIAL        — a parry NEGATES the hit and staggers the caster, but nothing is reversed
##                  (right for fields and barriers, where "reversing" is meaningless).
## BREAKS_THROUGH — the giant ults. The window does NOT save you; it costs you the parry and
##                  buys chip reduction. Learnable, not a gotcha, because the shell VISIBLY
##                  SHATTERS — the player is told, in the moment, that this one cannot be caught.
@export var deflect: int = Deflect.FULL
@export var deflect_damage_mult: float = 1.0   # damage taken on a BREAKS_THROUGH parry (e.g. 0.5)
@export var reaction_form: int = -1            # -1 = derive from kind (§1.1)
```

**Defaults by form, so a new spell inherits sanely** (`SpellReactions.default_deflect(form, def)`):

| Form | Default | Reversal semantics |
|---|---|---|
| PROJECTILE | `FULL` | reverse in place — the existing `reflect()` path |
| BEAM | `FULL` | **mirror**: spawn a fresh `BeamSpell` from the parry point along the shield normal, with `target_group` swapped. `BeamSpell.fire()` already takes an origin + dir, so this is ~6 lines and it is the most spectacular possible parry in the game |
| IMPACT / FIELD / BARRIER | `PARTIAL` | negate + stagger the caster |
| any spell with `cast_time >= 1.1` | `BREAKS_THROUGH` | the levitating-windup ults: `_meteor` (`SpellLibrary.gd:409`), `_convergence` (`:489`) |

The default is a *starting point written into the library*, never a hardcoded rule in the parry
code — a Juggernaut boulder can be authored `BREAKS_THROUGH` ("you do not parry a mountain") and
Heaven's Verdict can be authored `FULL` if playtest says otherwise, by editing one field.

### 5.3 The mechanism — one insertion point per spectacle

The problem is that a spectacle's damage lands in **one frame**, so there is no window for the
victim to notice. The fix is to invert it: the *spell* asks the victim, inside the damage loop it
already runs.

```gdscript
# on Hero (and mirrored on SpikeFigure) — the new receiver
## A SIGNATURE spell is about to damage me. Returns true if I deflected it.
## `spell_node` duck-types `deflect_mode() -> int` and `deflect_origin() -> Vector2`.
func try_deflect_spell(spell_node: Node, at: Vector2, dir: Vector2) -> bool
```

Each spectacle's damage loop gains one guard, e.g. in `BeamSpell._apply_beam_damage` (`:234`):

```gdscript
for enemy in targets_on_beam(...):
	if enemy.has_method("try_deflect_spell") and enemy.try_deflect_spell(self, _nearest_on_beam(enemy), _dir):
		continue                      # deflected — this target takes nothing
	if enemy.has_method("take_damage"): ...
```

`try_deflect_spell` then branches on the spell's `deflect_mode()`:

- **FULL** — consume the window, `Sfx.play("ding")`, `rig.set_parry(dir, PARRY_SHIELD_TIME)`,
  `Juice.impact_frame(1.0, at)`, then perform the form-appropriate reversal (mirror-beam /
  `reflect()` / mirrored impact at the caster). Return `true`.
- **PARTIAL** — consume the window, ding + shell, negate this instance's damage, stagger the
  caster if reachable. Return `true`.
- **BREAKS_THROUGH** — **do not** consume the hit. Play a distinct *shatter* sfx (not the ding),
  crack the shield shell visually, burn `_parry_cooldown_timer` to full, scale damage by
  `deflect_damage_mult`, return `false` so the damage proceeds. The player gets a loud, specific
  "that cannot be parried" lesson.

Why this shape:
- It reuses each spell's existing damage loop, so there is **no new per-frame proximity query**
  and no new physics.
- It is `has_method`-guarded, so any spectacle not yet wired behaves exactly as it does today —
  the 43 existing suites cannot regress from the guard alone.
- `EnemyProjectile`'s existing `try_parry` path is untouched; the two coexist. (A later cleanup
  could route `try_parry` through `try_deflect_spell`, but that is not Phase 3 scope.)

### 5.4 Fairness

Every spell already has a telegraph after Phase 2 (`BeamSpell.CHARGE_TIME` 0.34 s;
`MeteorSigil.CHARGE_TIME` 0.5 s plus per-impact ground markers, `MeteorSigil.gd:29-32`). A 0.16 s
`PARRY_WINDOW` against a 0.34 s tell is a real reaction test, not a coin flip. `BREAKS_THROUGH`
should be reserved for spells whose telegraph is ≥0.9 s, so the counterplay is *movement* — which
is precisely the plan's rule 2.

---

## 6. FILES

**New:**
```
scripts/combat/ReactionDef.gd          # Resource: Form enum + one authored row
scripts/combat/SpellReactions.gd       # static table + bucket_key + match_pair + _fits + default_deflect
scripts/combat/ReactionGeometry.gd     # pure static overlap tests
scripts/combat/SpellReactor.gd         # autoload registry + tick loop + memo + budget
scripts/combat/ReactionOutcomes.gd     # outcome dispatch: one static func per outcome key
scripts/combat/HollowPurple.gd         # the showcase node
scripts/combat/SteamCloud.gd           # obscuring soft-CC volume
scripts/combat/ShardCone.gd            # directional shatter
scripts/combat/ReactionSpark.gd        # shared small contact beat
tools/slice6_test_reaction_geometry.gd
tools/slice6_test_reaction_table.gd
tools/slice6_test_reactor.gd
tools/slice6_test_hollow_purple.gd
tools/slice6_test_spell_deflect.gd
tools/reaction_agent_capture.gd        # screenshot verifier (pattern: tools/wall_agent_capture.gd)
```

**Touched (all additive / guarded):** `Elements.gd` (+`OPPOSED`/`opposed()`), `SpellDef.gd`
(+`Deflect` enum, +3 exports), `Hero.gd` (+`try_deflect_spell`), `SpikeFigure.gd` (mirror),
`project.godot` (+`SpellReactor` autoload), and the ~10 spectacle scripts each gaining
`reaction_shape` / `reaction_active` / `reaction_consume` + one `SpellReactor.register` line +
one `try_deflect_spell` guard in the damage loop.

---

## 7. RISK REGISTER

1. **The origin-parked-node trap (§2.1).** Highest-probability bug in the whole phase, and it
   *fails silently in the wrong direction* (everything reacts, at (0,0)). Mitigation: the
   registry never reads `global_position`, and `slice6_test_reactor.gd` has a dedicated
   regression asserting two origin-parked nodes with distant `reaction_shape()`s do **not** match.
2. **Reaction spam.** A meteor barrage (11 impacts, `SpellLibrary.gd:112`) inside a void zone
   would fire row 7 eleven times. Mitigation: `MAX_REACTIONS_PER_TICK`, `ONE_SHOT` memo keyed on
   the *barrage node* rather than each meteor, and per-outcome cooldowns.
3. **Reactions as a stealth balance change.** Row 7 makes a meteor 1.5× damage. Phase 4's balance
   pass must include reaction damage; keep every multiplier on the `ReactionDef` so it is one file.
4. **`PostProcess.shock` takes screen UV, not world** (`PostProcess.gd:132`). Hollow Purple needs
   the projection helper; get it in T4 or the shock centres on the screen middle and the beat
   lands in the wrong place.
5. **Freezing a beam mid-life** (`reaction_freeze`) touches `BeamSpell._process` timing. Keep it
   to a single `_frozen` early-return so a bug can only make the beam *linger*, never damage twice.
6. **`SpikeFigure` and `Hero` are separate rigs** with duplicated parry code (`Hero.gd:1721` vs
   `SpikeFigure.gd:935`). The deflect work must land in both or the playground and the game will
   disagree — and the playground is the maker's verification surface.

---

## 8. TASK BREAKDOWN

Each task is independently verifiable, leaves the game playable, and has headless verification.
**All 43 existing suites in `tools/slice*_test_*.gd` must stay green after every task.** T0-T2 add
only new files, so they cannot regress anything; T3+ adds `has_method`-guarded call sites.

| T | Deliverable | Headless verification | Game state after |
|---|---|---|---|
| **T0** | `ReactionGeometry.gd` — the five pure overlap statics | **NEW `tools/slice6_test_reaction_geometry.gd`**: segment×segment crossing / parallel / collinear / endpoint-graze, and that it returns correct `ta`/`tb`; segment×rect slab test incl. a segment starting inside; circle/rect cases | Unchanged — new file, zero call sites |
| **T1** | `ReactionDef.gd` + `SpellReactions.gd` table (all ~28 rows authored, outcomes not yet implemented) + `Elements.OPPOSED` | **NEW `tools/slice6_test_reaction_table.gd`**: canonical `bucket_key` symmetry; wildcard element sets; `require_opposed` matches all four pairs and rejects non-pairs; priority resolution; `suppress` blocks lower rows; **the inheritance test — a synthetic Reactant `{form: IMPACT, element: FIRE}` that corresponds to no existing spell still matches `fire_shatters_ice_barrier`** | Unchanged |
| **T2** | `SpellReactor.gd` autoload + the `reaction_shape/active/consume` contract doc. Registered by nobody | **NEW `tools/slice6_test_reactor.gd`** using stub `Node2D`s (pattern: `slice3_test_parry.gd`'s `EnemyStub`): pairs fire once under `ONE_SHOT`; `SUSTAINED` respects cooldown; freed nodes are swept + memo pruned; budget caps at `MAX_REACTIONS_PER_TICK`; **origin-parked regression (risk 1)**; `reaction_active() == false` blocks matching | Autoload present, no reactants → provably zero behaviour change |
| **T3** | **First reaction end-to-end**: `BeamSpell` + `IceWall` implement the contract and register; `ReactionOutcomes.shatter_barrier` calls the existing `IceWall.shatter()` (`:142`) | Extend `slice6_test_reactor.gd` with the real pair driven headlessly (`IceWall` needs no physics world — `_floor_below` returns `{}` cleanly, `:100`). Plus **`tools/reaction_agent_capture.gd`** screenshot: fire beam vs standing ice wall, before/at/after shatter — *look at the PNG* | Rows 2 works in play. Everything else unchanged |
| **T4** | **HOLLOW PURPLE** — `HollowPurple.gd`, `reaction_freeze`/`reaction_consume` on `BeamSpell`, the world→UV projection helper, the computed purple | **NEW `tools/slice6_test_hollow_purple.gd`**: trigger gates (opposed only; both beams active; cross inside both bodies; min length; global one-shot); computed core colour for all four opposed pairs; radial + corridor damage against enemy stubs (corridor via `BeamSpell.targets_on_beam`, already tested); both beams consumed exactly once. Plus a 4-frame screenshot sequence (seize / collapse / silence / detonation) — the beat that *must* be judged by eye is SILENCE | Rows 1-2. The showcase is playable |
| **T5** | Tier-1 remainder (rows 3-7) + Tier-2 destructive (8-20): `SteamCloud.gd`, `ShardCone.gd`, `ReactionSpark.gd`, molten/embrittle flags, and registration on `ZoneSpell`, `MeteorSigil`, `BoulderHurl`, `RockWall`, `ChainBolt`, `StatusComponent` | Extend the reactor suite with one deterministic assertion per row (outcome fired, correct node consumed, damage/radius scaled). Screenshot per new VFX node | Rows 1-20 |
| **T6** | Tier-3 constructive/utility (21-28) — mostly parameter edits on existing draws, no new nodes | Extend the reactor suite; screenshot the reinforce + steam-disperse beats | Full ~28-row matrix live |
| **T7** | **Parry/deflect**: `SpellDef.Deflect` + `deflect_damage_mult` + per-form defaults in `SpellLibrary`; `Hero.try_deflect_spell`; `SpikeFigure` mirror; the guard inserted into each spectacle's damage loop | **NEW `tools/slice6_test_spell_deflect.gd`** (extends the `slice3_test_parry.gd` pattern): `FULL` on a beam spawns a mirrored beam with swapped `target_group` and zeroes the hit; `PARTIAL` negates without reversing; `BREAKS_THROUGH` still damages, applies `deflect_damage_mult`, and burns the parry cooldown; a class that cannot parry (`can_parry` false, `Hero.gd:1703`) is unaffected. **Re-run `slice3_test_parry.gd` — the `EnemyProjectile` path must be byte-identical** | Signatures are parryable per their data |
| **T8** | Balance + audit: reaction damage into the Phase-4 balance pass; playground HUD readout of the last row fired (`ReactionLabel`); a debug overlay drawing live reactant shapes (the fastest way to catch a §2.1 regression by eye); montage capture of all headliners | All 48 suites green; montage reviewed against the Hollow-Purple bar | Phase 3 complete → maker F5 |

**Test count: 43 → 48.** Five new suites, all in the existing `extends SceneTree` +
`_process` + `_expect` idiom (`tools/slice3_test_parry.gd:26-46`), all runnable as
`godot --headless --path godot-project --script tools/slice6_test_<x>.gd`.

**Suites most at risk of regression, to re-run explicitly at T3, T5 and T7:**
`slice4_test_spells.gd`, `slice3_test_spell_collision.gd`, `slice3_test_parry.gd`,
`slice1_test_elements.gd`, `slice_test_status.gd`, `slice_test_selfdamage.gd`,
`slice_test_coop_effects.gd` (co-op replicates spell effects — a consumed/frozen beam must not
desync a client twin).
