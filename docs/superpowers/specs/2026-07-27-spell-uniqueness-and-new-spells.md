# Spell Uniqueness Audit + Two New Spells — design spec

**Date:** 2026-07-27 · **Branch:** `stickman-integrate` · **Status:** design, not implemented
**Governing plan:** `docs/references/magic-overhaul-plan.md` (Phases 0, 1, 2a–2h DONE)
**Trigger:** maker verdict after playing — *"there are still spells that do the same thing. I wanted unique stuff — like shadow travelling across the floor, or a teleporting dagger one."*

> **Read this first.** Phase 2 fixed the **art** families (5 beams stopped being tint-swaps, 4 meteors got bespoke falling objects, colossus stopped being a brown Judgment). It did **not** fix the **shape** families. The maker is not complaining about colour any more — he is complaining that 24 spells resolve through **six delivery shapes, and 18 of the 24 sit in just two of them.** Different art on the same verb still plays the same. This spec (A) proves that at the code level, (B) designs the two spells he asked for as genuinely new shapes, (C) proposes the next shapes to build.

---

## PART A — THE AUDIT

### A.0 How this was measured

Not by eyeballing the art. By reading, for each spell: which **damage selector** resolves the hit, and what the player has to **do with the cursor and the timer** to land it. Two spells with different particles but the same selector and the same input are the same spell.

Source of truth: `godot-project/scripts/combat/SpellLibrary.gd` → `build_all()` (lines 51–71), `SpellCaster.gd` → `cast()` (line 38, `match spell.kind` at line 50), `CastStyle.gd` → `for_spell()` (line 32).

### A.1 Full table — all 24 spells

Playground index = positional index into `SpellLibrary.build_all()` (the capture tool addresses spells by raw index — see §D.5).

| # | id | Kind | Spectacle script | Cast pose (playground) | In-game windup | **Delivery shape** |
|---|---|---|---|---|---|---|
| 0 | `zoltraak` | BEAM | `BeamSpell.gd` (arcane skin) | POINT | CHANNEL (levitate 1.0 s) | **L** line-from-caster |
| 1 | `frostpiercer` | BEAM | `BeamSpell.gd` (frost skin) | POINT | CHANNEL 1.0 s | **L** |
| 2 | `infernal_lance` | BEAM | `BeamSpell.gd` (fire skin) | POINT | CHANNEL 1.0 s | **L** |
| 3 | `umbral_lance` | BEAM | `BeamSpell.gd` (shadow skin) | POINT | CHANNEL 1.0 s | **L** |
| 4 | `tempest` | BEAM | `BeamSpell.gd` (lightning skin) | POINT | CHANNEL 1.0 s | **L** |
| 5 | `chidori` | RUSH | `LightningRush.gd` | COIL | SUMMON+GATHER | **L** |
| 6 | `chain_lightning` | CHAIN | `ChainBolt.gd` | LASH | SUMMON+GATHER | **L** (then auto-hops) |
| 7 | `judgment` | DIVINE_RAY | `DivineRay.gd` (light mode) | CHANNEL | CHANNEL 1.0 s | **G** marked ground point |
| 8 | `colossus_pillar` | DIVINE_RAY | `DivineRay.gd` (stone mode) | CHANNEL | CHANNEL 1.0 s | **G** |
| 9 | `rock_pillar` | PILLAR | `RockPillar.gd` | SLAM | SUMMON+GATHER | **G** |
| 10 | `heavens_verdict` | CONVERGENCE | `StarConvergence.gd` | CIRCLE | CHANNEL 1.3 s | **G** |
| 11 | `meteor_sigil` | METEOR | `MeteorSigil.gd` (fire) | CIRCLE | CHANNEL 1.1 s | **G** (bombardment) |
| 12 | `void_barrage` | METEOR | `MeteorSigil.gd` (shadow) | CIRCLE | CHANNEL 1.1 s | **G** |
| 13 | `avalanche` | METEOR | `MeteorSigil.gd` (earth) | CIRCLE | CHANNEL 1.1 s | **G** |
| 14 | `frozen_comet` | METEOR | `MeteorSigil.gd` (frost) | CIRCLE | CHANNEL 1.1 s | **G** |
| 15 | `rune_orbs` | MISSILES | `RuneOrbs.gd` | LASH | SUMMON+GATHER | **P** travelling projectile |
| 16 | `boulder_hurl` | BOULDER | `BoulderHurl.gd` | SLAM | SUMMON+GATHER | **P** |
| 17 | `blink_strike` | BLINK_STRIKE | `BlinkStrike.gd` | COIL | SUMMON+GATHER | **L** |
| 18 | `blade_flurry` | FLURRY | `BladeFlurry.gd` | COIL | SUMMON+GATHER | **M** melee arc |
| 19 | `void_zone` ("Shadow Root") | ZONE (forked) | `ShadowRoot.gd` | CIRCLE | SUMMON+GATHER | **C** ground traveller |
| 20 | `blizzard` | ZONE | `ZoneSpell.gd` (frost) | CIRCLE | SUMMON+GATHER | **G** (persistent field) |
| 21 | `drain_tether` | TETHER | `DrainTether.gd` | LASH | SUMMON+GATHER | **L** |
| 22 | `rock_wall` | WALL | `RockWall.gd` | SLAM | SUMMON+GATHER | **B** barrier |
| 23 | `ice_wall` | ICE_WALL | `IceWall.gd` | SLAM | SUMMON+GATHER | **B** |

### A.2 The shape census

| Shape | Spells | Count | The player's actual verb |
|---|---|---|---|
| **L** — line from the caster, resolved instantly along the aim | 0,1,2,3,4,5,6,17,21 | **9** | point at a thing → thing on the line is hit |
| **G** — mark a ground point in reach, telegraph, detonate in a circle | 7,8,9,10,11,12,13,14,20 | **9** | put a circle on the floor → get out of it |
| **P** — travelling projectile from the caster | 15,16 | 2 | lead the target |
| **B** — barrier in front of the caster | 22,23 | 2 | block a lane |
| **M** — melee arc at the caster | 18 | 1 | be close, press |
| **C** — ground traveller from the caster | 19 | 1 | outrun / jump the wave |

**18 of 24 spells live in two shapes.** The three most interesting shapes have one spell each.

### A.3 The proof: five copies of one selector, five copies of another

The sameness is not subjective — it is literally duplicated code.

**Shape L is one geometric test, copy-pasted five times:**

| File · line | Function |
|---|---|
| `BeamSpell.gd:250` | `static func targets_on_beam(origin, dir, length, half_width, nodes)` |
| `LightningRush.gd:141` | `static func targets_on_line(origin, dir, length, half_width, nodes)` |
| `BlinkStrike.gd:57` | `static func targets_on_line(origin, dir, length, half_width, nodes)` |
| `ChainBolt.gd:86` | `static func build_chain(...)` — first target is the same corridor test (`FIRST_CORRIDOR = 46.0`) |
| `DrainTether.gd:52` | `static func latch_target(origin, dir, reach, corridor, nodes)` — same corridor test |

All five: project onto the aim ray, reject if `proj < 0 or proj > length`, accept if `absf(rel.dot(perp)) <= half_width`.

**Shape G is one geometric test, copy-pasted five times:**

`DivineRay.gd:306`, `StarConvergence.gd:114`, `RockPillar.gd:108`, `MeteorSigil.gd:345`, `BoulderHurl.gd:171` — all `static func targets_in_radius(center, radius, nodes) -> Array`, byte-identical bodies.

### A.4 The clusters that still feel same-y, and WHY

Ranked by how loudly they read as duplicates in play.

**Cluster 1 — THE FOUR BOMBARDMENTS (`meteor_sigil` / `void_barrage` / `avalanche` / `frozen_comet`). Worst offender.**
Not just the same shape — the same *numbers*:

| | mp | cd | dmg | radius | count | reach | cast_time |
|---|---|---|---|---|---|---|---|
| meteor_sigil | 72 | 6.0 | 22 | 140 | 11 | 300 | 1.1 |
| void_barrage | 70 | 6.2 | 22 | 135 | 11 | 300 | 1.1 |
| avalanche | 72 | 6.4 | 22 | 145 | 11 | 300 | 1.1 |
| frozen_comet | 70 | 6.0 | 22 | 138 | 11 | 300 | 1.1 |

Four of 24 slots, one script (`MeteorSigil.gd`), one dispatch arm (`SpellCaster.gd:68`), one pose (CIRCLE), one 1.1 s levitate. Phase 2's per-element falling objects are excellent work — and completely invisible to the decision the player makes, which is identical in all four cases. **These are one spell with a skin picker.**

**Cluster 2 — THE FIVE BEAMS (`zoltraak` / `frostpiercer` / `infernal_lance` / `umbral_lance` / `tempest`).**
Phase 2 gave each a real silhouette (dragons / hex lens / razor lance / void core / braided storm) — the art job is done. But the *play* is one spell: `BeamSpell.CHARGE_TIME = 0.34` is a **shared constant**, so all five telegraph for exactly the same time; the damage corridor is the same line test; the pose is the same POINT; the windup is the same 1.0 s levitate. The only per-spell knobs are `length` (900–1250) and `width` (22–42). A beam that charges 0.34 s and a beam that charges 0.34 s are the same beam.

**Cluster 3 — THE LIGHTNING TRIO (`chidori` / `tempest` / `chain_lightning`).**
Three of 24 slots, one element, all Shape L, three separate scripts doing the same thing to the player: point at a guy, lightning happens on that line. `chain_lightning`'s hops are real differentiation *after* the first hit — but the first hit is `FIRST_CORRIDOR = 46.0` around the aim ray, i.e. a beam. `chidori`'s fork is a *fixed geometric branch* (`LightningRush._resolve_chain`, line 121), so it too is "line + a bit more line".

**Cluster 4 — THE THREE SPIRES (`rock_pillar` / `colossus_pillar` / `judgment`).**
`rock_pillar` and `colossus_pillar` are explicitly designed as the fast-small and slow-big version of *the same event* (see `DivineRay.gd:35-40` comments: "deliberately the OPPOSITE of RockPillar's fast uppercut fang" — opposite *tuning*, identical *shape*). `judgment` shares the script and the arm with `colossus_pillar`; only the palette differs. Three slots for "a vertical thing appears at the ground point you marked."

**Cluster 5 — SHADOW'S SHORT-RANGE BURSTS (`blink_strike` / `blade_flurry`).**
Both SHADOW, both COIL pose, both SUMMON+GATHER, both "be near things in front of you and press". One is a line cut, one is a forward cone. In practice the player uses them interchangeably.

### A.5 The cast-animation finding (rule 4 is not actually satisfied)

The plan's rule 4 says **each spell** needs a distinct characterful cast. Two structural gaps:

1. **`CastStyle` is not wired into the game at all.** `CastStyle.for_spell()` has exactly **one** caller in the whole project: `scripts/spike/SpellPlaygroundController.gd:225-227`. `Hero.gd` never references `CastStyle`. In the shipped game there are effectively **two cast animations for 24 spells**:
   - `cast_time > 0` (12 spells: 5 beams, judgment, colossus_pillar, 4 meteors, heavens_verdict) → `Hero._begin_channel()` (line 1052): `State.CAST` + `set_airborne(true)` levitate. No gesture.
   - `cast_time == 0` (the other 12) → `Hero._begin_summon()` (line 943): `rig.cast_gesture(CharacterRig.GestureKind.GATHER, 0.9, _element)` at line 955 — **the same GATHER for every one of them.**
2. **Even in the playground, poses key off `Kind`, not off the spell.** `CastStyle.for_spell(kind: int)` means 5 beams share POINT and 7 spells (4 meteors + convergence + 2 zones) share CIRCLE.

**Recommended fix (small, unblocks everything else):**
- Change the signature to `static func for_spell(spell: SpellDef) -> int` so it can fork on `spell.id` / `spell.element` as well as `spell.kind`. Only one call site to update (`SpellPlaygroundController.gd:225`).
- Build the missing `Pose → CharacterRig.GestureKind` bridge and call it from `Hero._begin_summon()` (replace the hardcoded `GestureKind.GATHER` at line 955) and `Hero._begin_channel()`. `CharacterRig` has `cast_gesture(kind, intensity, element)` at line 532 and `GestureKind { NONE, FLICK, IGNITE_DROP, RAISE, GATHER, STOMP }` at line 27 — the vocabulary exists, it is just unmapped.

This is prerequisite work for both new spells below: without it, a "distinct cast animation" only exists in the playground.

### A.6 The parry finding (rule 3 is not satisfied by any of the 24)

Confirmed by exhaustive grep of `scripts/combat/`: **no hero spell spectacle participates in the parry layer.** None of `BeamSpell` / `RuneOrbs` / `BoulderHurl` / `MeteorSigil` / `DivineRay` / `StarConvergence` / `ChainBolt` / `BlinkStrike` / `BladeFlurry` / `DrainTether` / `ZoneSpell` / `ShadowRoot` / `LightningRush` / `RockPillar` / `RockWall` / `IceWall` has a `reflect()` method, a `_reflected` property, or membership in a deflect-scanned group. Only `Spell.gd` (the basic bolt) is wired in, and only for `fizzle()`.

**The contract a new spell must satisfy to be deflectable** (two different rigs, two different polarities — a new spell should satisfy both):

| Rig | Who scans | What it needs |
|---|---|---|
| **Hero** (`Hero.try_parry(proj) -> bool`, `Hero.gd:1721`) | the **projectile** scans the `"hero"` group and calls `target.try_parry(self)` — see `EnemyProjectile._check_hit()` (`EnemyProjectile.gd:144-161`) | the projectile must call `try_parry(self)` **and** expose `func reflect(new_dir: Vector2, color: Color) -> void` |
| **SpikeFigure** (playground, `SpikeFigure._process_projectiles()`, ~lines 920–940) | the **figure** scans, within `PARRY_REACH = 40.0` | the node must expose `reflect(Vector2, Color)` **and** a `_reflected: bool` property, and be in a group the scan iterates (today only `"enemy_projectile"`) |

**Both new spells below implement this contract.** They are the first two bricks of the plan's Phase 3 "wire signatures into the parry layer".

---

## PART B — THE TWO NEW SPELLS

Both introduce a delivery shape that nothing else in the kit has, and both add a *verb* the player does not currently have.

---

## B.1 — CREEPING SHADE (`creeping_shade`) — the ground-hugging traveller

> A shadow peels off the caster's feet and **races along the floor**, following every slope and step, until it reaches something — then it rears up and spikes it into the air.

### B.1.1 Why this is a new shape

Nothing in the kit is a **hazard with a real position that travels over time and whose strike point is emergent**. Everything either resolves instantly (Shape L), resolves at a point the player pre-marked (Shape G), or is a projectile that ignores terrain (Shape P). The new axis: *terrain determines the spell's path, and the victim's own position at the moment of arrival determines where it hits.*

### B.1.2 Distinctness from `ShadowRoot.gd` — mandatory reading before implementing

`ShadowRoot.gd` already draws a dark line racing along the ground. **It is not the same spell, and the implementer must not "just extend it."** The difference is that ShadowRoot's race is *cosmetic*: `_lock` is computed once in `erupt()` (line 69) as `origin + Vector2(dir_sign * run, -24)`, the vein is a `lerp(_origin, _lock, p)` (line 195), and the strike fires on a fixed `SURGE_TIME = 0.5` timer regardless of distance.

| | `ShadowRoot` (`void_zone`) | **Creeping Shade** (new) |
|---|---|---|
| Strike point | precomputed at cast time (`_lock`, line 69) | **emergent** — wherever the head physically reaches a body |
| The dark line | polyline lerped origin→lock, never touches physics | a **real moving head** with a per-frame downward raycast; the drawn trail *is* the path it took |
| Travel time | fixed 0.5 s at any distance | distance ÷ 520 px/s (0.1 s at point blank, 1.2 s at max) |
| Terrain | one raycast at cast (`_floor_snap`, line 85) | hugs the floor every frame; climbs slopes, follows steps down, **falls into pits and dies** |
| Payload | ROOT (hard CC via `apply_status(EARTH)`), 26 dmg | 60 dmg + **upward launch**, no CC |
| How you dodge | be off the mark, or above `CATCH_HEIGHT = 100` when the timer fires — **positional** | be airborne when it passes under you — **timing** |
| Blocked by walls | n/a | **no — it passes under `RockWall` / `IceWall`.** This is its identity: the anti-barrier tool |
| Parry | none | yes — reflected back at the caster |

If in doubt: ShadowRoot is *"stand still, you're caught"*. Creeping Shade is *"jump, or you're launched"*.

### B.1.3 Data (`SpellLibrary.gd`)

```gdscript
## CREEPING SHADE — Shadowblade third signature. A shadow peels off the caster's
## feet and RACES ALONG THE FLOOR, hugging terrain, until it reaches a body — then
## it rears into a spike and launches them. Passes UNDER walls; dies in pits.
static func _creeping_shade() -> SpellDef:
	var s := SpellDef.new()
	s.id = "creeping_shade"
	s.display_name = "Creeping Shade"
	s.description = "Peel your own shadow off the ground and send it racing along "\
		+ "the floor — it follows every slope, slips under walls, and SPIKES the "\
		+ "first thing it reaches into the air. Jump it or wear it."
	s.kind = SpellDef.Kind.CRAWLER
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 52
	s.cooldown = 5.5
	s.damage = 60
	s.reach = 620.0   # max travel distance
	s.radius = 26.0   # catch half-width in x
	s.cast_time = 0.0 # summon path, NOT the levitate channel — it comes off the floor
	return s
```

Append `_creeping_shade()` to `build_all()` (playground index **24**) and add to `build_for_class(1)` (SHADOWBLADE) as a third entry — that class is currently all-melee (`blink_strike`, `blade_flurry`) and this gives it its only ranged pressure tool.

### B.1.4 Kind + dispatch

`SpellDef.gd:16` — **APPEND ONLY** (the file's own comment warns that inserting renumbers BOULDER/PILLAR/WALL and breaks their arms):

```gdscript
enum Kind { BEAM, DIVINE_RAY, NOVA, METEOR, CONVERGENCE, RUSH, BOULDER, PILLAR, WALL, ICE_WALL, CHAIN, ZONE, MISSILES, BLINK_STRIKE, TETHER, FLURRY, CRAWLER, THROWN_ANCHOR }
```

`SpellCaster.gd` — new const beside the others (lines 11–27) and a new arm in the `match` at line 50, modelled on the ZONE arm (line 142):

```gdscript
const CRAWLER_PATH: String = "res://scripts/combat/ShadowCrawler.gd"
...
		SpellDef.Kind.CRAWLER:
			# A ground-hugging traveller launched from the caster's feet along the
			# aim. Unlike ShadowRoot the strike point is EMERGENT, so nothing is
			# clamped to reach here — `reach` is the crawler's own travel budget.
			var cr: Node2D = (load(CRAWLER_PATH) as GDScript).new()
			arena.add_child(cr)
			cr.set("element_id", elem)
			cr.call("crawl", caster_pos, aim.normalized(), col, spell.reach, spell.radius, spell.damage, fx)
			Juice.zoom_pull_camera(0.10, 0.5, 0.12, 0.5)
			return true
```

### B.1.5 New script — `godot-project/scripts/combat/ShadowCrawler.gd`

**Model file:** `ShadowRoot.gd` for the *look* (near-black core + violet fray + sprouting spikes + HDR sparks) and `BoulderHurl.gd` for the *motion* (`_process` advance + `_floor_below` raycast + `_check_flight_collision` + `_impact`).

```gdscript
class_name ShadowCrawler
extends Node2D
```

**Constants:**

| Const | Value | Meaning |
|---|---|---|
| `SPEED` | `520.0` | px/s along the floor |
| `MAX_RANGE` | `620.0` | travel budget (overridden by `spell.reach`) |
| `CATCH_X` | `26.0` | half-width in x for a body to be caught (from `spell.radius`) |
| `CATCH_Y` | `54.0` | how far above the head a body's centre may be and still be caught |
| `SNAP_TIME` | `0.12` | the rear-up beat between contact and damage — the second dodge window |
| `SHRED_TIME` | `0.25` | spike dissolve after the strike |
| `WHIFF_HOLD` | `0.30` | claw-at-air beat when it runs out of range (mirrors `ShadowRoot.WHIFF_HOLD`) |
| `WALL_CLIMB` | `110.0` | px it will run *up* a vertical face before dissipating |
| `PIT_DROP` | `260.0` | fall this far with no floor and it dies (fell into a pit) |
| `TRAIL_MAX` | `44` | trail points retained for the draw (≈0.6 s of path) |
| `KNOCK_UP` | `-430.0` | y component of the launch |
| `KNOCK_FWD` | `140.0` | x component (along travel) |

**Public API (mirrors every other spectacle: one driver method):**

```gdscript
func crawl(origin: Vector2, aim: Vector2, color: Color, range_px: float,
		catch_r: float, damage: int, effect: String = "shadow") -> void
```

**Timeline (seconds from cast key press):**

| t | Event |
|---|---|
| 0.00 | `Hero._cast_signature()` → `_begin_summon` (SUMMON path, `cast_time == 0`). Pose = **SWEEP** (new, §B.3). Body drops into a low crouch, trailing hand drags the floor. |
| 0.00–0.28 | Windup. The caster's own drawn ground shadow **elongates toward the aim** — the pre-telegraph. `Sfx.play("cast", -6.0, -0.2)` (pitched *down*, unlike ShadowRoot's `-4.0, +0.1`). |
| 0.28 | `SpellCaster.cast()` fires; `ShadowCrawler.crawl()` runs. Head spawns floor-snapped at the caster's feet. `Juice.shake_camera(3.0)`. |
| 0.28 → ≤1.47 | **TRAVEL.** Per `_process(delta)` — see loop below. Max 620 px ÷ 520 px/s = 1.19 s. |
| on contact | **REAR-UP, 0.12 s.** The head stops at the victim's x and rises into a coiled dark spike. No damage yet. A late jump still escapes — this is the on-target telegraph rule 2 demands, on top of the visible approach. |
| +0.12 | **STRIKE.** Damage + launch + juice. Node enters SHRED. |
| +0.37 | `queue_free()`. |
| (whiff) | at `MAX_RANGE`, rear into a grasping claw for 0.30 s, then free. |

**The travel loop** — model on `BoulderHurl._process` (lines 93–126) and `_check_flight_collision` (lines 133–146):

```
_prev = _head
_head.x += _dir_sign * SPEED * delta

# 1. FLOOR-SNAP. Ray from (_head.x, _head.y - 40) down 120 px, collision layer 1.
#    hit  -> _head.y = hit.position.y            (climbs slopes, follows steps)
#    miss -> _head.y += FALL_SPEED * delta       (walks off a ledge)
#            if total drop > PIT_DROP: _dissipate()   # fell in a pit — spell dies
#    Reuse the exact idiom of ShadowRoot._floor_snap (line 85) /
#    BoulderHurl._floor_below (line 85): PhysicsRayQueryParameters2D.create(a, b, 1).

# 2. WALL CHECK. Ray _prev -> _head, layer 1, hit_from_inside = true.
#    If hit and absf(normal.x) > 0.7 -> the shade RUNS UP the face:
#      _climb += rise; if _climb > WALL_CLIMB: _dissipate()
#    NOTE: RockWall/IceWall bodies sit ON the floor, so the crawler's floor ray
#    still finds ground beneath them and it passes UNDER. That is intended and is
#    this spell's identity — verify it in the playground with a raised RockWall.

# 3. VICTIM CHECK. For each node in group "enemy" (or _target_group when reflected):
#      absf(n.global_position.x - _head.x) <= CATCH_X
#      and (_head.y - n.global_position.y) <= CATCH_Y  and >= -20.0
#    -> _begin_snap(n).  Airborne bodies above CATCH_Y are simply missed.
#    STOPS ON THE FIRST BODY — it does not pierce. (Piercing would make it a
#    better beam, which is exactly the sameness we are trying to kill.)

# 4. TRAIL. _trail.append(_head); if _trail.size() > TRAIL_MAX: _trail.remove_at(0)

# 5. RANGE. _travelled += SPEED * delta; if >= _range: _whiff()
```

**Strike (`_strike(n)`), model `ShadowRoot._snap()` (line 109) and `BlinkStrike.strike()` (line 24):**

```gdscript
n.take_damage(_damage, Color(_color.r, _color.g, _color.b, 1.0))
n.apply_status(element_id)                       # SHADOW -> Weaken. NO EARTH root.
n.apply_knockback(Vector2(_dir_sign * KNOCK_FWD, KNOCK_UP))
Juice.impact_frame(0.7, _head)                   # localized, per Phase 0
Juice.hit_stop(0.07)
Juice.shake_camera(9.0)
Sfx.play("spell_impact", -2.0, -0.15)
# Two bursts, copied in shape from ShadowRoot._snap lines 130-138:
#   1) dark implosion  (0.12,0.02,0.20,0.95) -> transparent, 18 particles, additive OFF
#   2) HDR violet sparks Elements.emissive(element_id), 8 particles, additive ON
```

Also sweep `"destructible"` (crates) at the head each frame with `take_damage` — a floor wave should chew cover, and it matches `RuneOrbs._target_within` (line 100) which already checks both groups.

**Draw approach (`_draw`)** — the trail *is* the geometry, so terrain-hugging is free:

```
alpha_i = i / _trail.size()                # tail fades: reads as a wave, not a painted line
draw_polyline(_trail, Color(0.40,0.18,0.70, 0.22),  12.0, true)   # wide violet halo
draw_polyline(_trail, Color(0.03,0.00,0.07, 0.95),   7.0, true)   # light-eating core
draw_polyline(_trail, Color(0.62,0.34,1.00, 0.60),   2.0, true)   # bright rim
```
(Godot's `draw_polyline` takes one colour; to get the per-point fade, emit the trail as N short `draw_line` segments with per-segment alpha — the same pattern `BoulderHurl._draw` uses for its dust trail, lines 236–241.)

Then, copied in shape from `ShadowRoot._draw_vein` (lines 207–218): sprouting spikes off every 3rd trail point, taller near the head, swaying on `sin(_elapsed * 8.0 + seed)`. Head: dark bulge + violet arc + 5 HDR sparks — `ShadowRoot.gd:222-229` verbatim in structure.

Rear-up spike (`_draw_snap`): a single tapered dark fang growing `0 → 74 px` over `SNAP_TIME` with an HDR violet tip glint. Reuse the fang polygon idea from `RockPillar._draw_column` (line 160) but shadow-palette and half the width.

**Deflect (rule 3):**

```gdscript
var _reflected: bool = false        # property the SpikeFigure scan reads
var _target_group: String = "enemy"

func reflect(new_dir: Vector2, color: Color) -> void:
	if _reflected:
		return
	_reflected = true
	_dir_sign = signf(new_dir.x) if new_dir.x != 0.0 else -_dir_sign
	_target_group = "hero"
	_color = color
	_travelled = 0.0                # full budget again, running the other way
	_trail.clear()
	Sfx.play("ding", 0.0, 0.05)

func consume() -> void:             # so AoE sweeps can clear it, per EnemyProjectile.consume
	queue_free()
```

Join group `"deflectable_spell"` in `_ready()`. **One 2-line change is required elsewhere:** `SpikeFigure._process_projectiles()` currently iterates only `"enemy_projectile"` — widen it to also iterate `"deflectable_spell"`. That is the first brick of Phase 3.

**Rule compliance:** (1) no homing — a fixed `_dir_sign` and floor geometry, nothing tracks a target; (2) dodgeable twice — the visible 0.1–1.2 s approach, then the 0.12 s rear-up; (3) deflectable — above; (4) new SWEEP pose; (5) not a recolor — the only ground traveller with real physics, and the palette-shared `ShadowRoot` is distinguished by silhouette (racing wave + fang vs. static claw cage) and by verb.

---

## B.2 — RIFT DAGGER (`rift_dagger`) — the thrown anchor

> Throw a dagger. It flies where you aimed it and sticks in whatever it hits — a wall, a crate, or a body that then walks away with it. Press again and you tear yourself through space to it.

### B.2.1 Activation model — decided, with justification

**DECISION: second press of the same key = recall + teleport. Not auto-on-impact.**

Options weighed against the **mobile-first / fewer-buttons** constraint (`CLAUDE.md`: "Every action must work via virtual joystick + tap"):

| Model | Buttons | Verdict |
|---|---|---|
| **(a) Second press of the same slot** | **1** | **CHOSEN** |
| (b) Auto-teleport on impact | 1 | Rejected — removes all decision-making, and collapses the spell into a slower `blink_strike` |
| (c) Hold-vs-tap | 1 | Rejected — hold gestures fight the existing joystick/tap idiom and add input latency to a combat spell |
| (d) Separate recall button | 2 | Rejected — violates the constraint outright |

Why (a) is right, not just acceptable:

1. **It is still one button.** The slot's own state changes meaning. `AbilityBar._draw_slot()` (`AbilityBar.gd:102`) already renders from a plain `Dictionary` contract supplied by `Hero.gd:1800-1803` — swapping the slot's name string to `"RECALL"` and forcing `"enabled": true` while an anchor is live is a data change, no new UI code.
2. **It preserves the fantasy the maker described.** He said the caster *can* blink to it. "Can" is a choice. Model (b) deletes the choice.
3. **It is a genuinely new verb.** All 24 existing spells are single-press fire-and-forget. This is the kit's first **two-beat** spell: throw → read the fight → commit or don't. That verb novelty is worth more than any amount of new particle art, and it is the direct answer to *"spells that do the same thing"*.
4. **No stranded state.** If the player never presses again, the dagger dissolves at `LIVE_TIME = 4.0 s` and the cooldown starts then. There is no mode the player can get stuck in.
5. **Safety is free.** The teleport destination goes through the existing duck-typed `caster.blink_to(dest) -> Vector2` contract that `SpellCaster.gd:194-195` already uses for `blink_strike` (Hero refuses to blink into a pit and returns where it actually ended up). No new safety code.

### B.2.2 Distinctness from `blink_strike` and `LightningRush`

| | `blink_strike` (`BlinkStrike.gd`) | `chidori` (`LightningRush.gd`) | **Rift Dagger** |
|---|---|---|---|
| Destination | your cursor, clamped to `reach = 300` | caster doesn't move | **a physical object that had to survive a flight** |
| Travel | none — instant | none — instant line | a 780 px/s projectile you can watch, block, or lose |
| Range | 300 px, guaranteed | 620 px line | 700 px, **uncertain** (an `IceWall` eats it) |
| Damage | 85 along the crossed line | 62 along the line + fork | 34 on stick + 34 in a 70 px arrival burst |
| Decision points | 1 (where) | 1 (where) | **2 (where, then whether/when)** |
| World state | none persists | none persists | a live object visible to the enemy for up to 4 s |
| Counterplay | none | none | parry the dagger → the anchor is severed and the recall fizzles |

The enemy *seeing your dagger stuck in the wall and knowing you might come* is a read the kit currently cannot produce.

### B.2.3 Data (`SpellLibrary.gd`)

```gdscript
## RIFT DAGGER — Shadowblade / Arcanist. Throw a dagger that sticks where it lands
## (wall, crate, or a body that walks away with it); press again to TEAR yourself
## through to it. Two beats, one button.
static func _rift_dagger() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rift_dagger"
	s.display_name = "Rift Dagger"
	s.description = "Hurl a dagger down the aim — it sticks in whatever it reaches. "\
		+ "Press again and the rift tears you through to it, bursting on arrival."
	s.kind = SpellDef.Kind.THROWN_ANCHOR
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 46
	s.cooldown = 4.5    # starts when the anchor RESOLVES, not at throw
	s.damage = 34       # deliberately low both halves — a positioning tool
	s.reach = 700.0     # throw range
	s.radius = 70.0     # arrival burst radius
	s.length = 4.0      # anchor lifetime, s (precedent: SpellCaster.gd:161-163
	                    # already uses `length` as a lifetime for ZONE)
	s.cast_time = 0.0
	return s
```

Append to `build_all()` (playground index **25**); add to `build_for_class(1)` SHADOWBLADE.

### B.2.4 Dispatch + the one-button seam

`SpellCaster.gd` — new const + arm:

```gdscript
const DAGGER_PATH: String = "res://scripts/combat/RiftDagger.gd"
...
		SpellDef.Kind.THROWN_ANCHOR:
			# One button, two beats: if this caster already has a live anchor, the
			# press means RECALL. try_recall() is the shared static helper so every
			# caster (Hero, playground figure, bots) gets the second beat for free.
			if (load(DAGGER_PATH) as GDScript).try_recall(arena.get_tree(), caster):
				return true
			var dg: Node2D = (load(DAGGER_PATH) as GDScript).new()
			arena.add_child(dg)
			dg.set("element_id", elem)
			dg.call("throw_dagger", caster, caster_pos, aim.normalized(), col,
				spell.reach, spell.radius, spell.damage, spell.length, spell.cooldown, fx)
			return true
```

`Hero.gd` — **the MP problem.** `_cast_signature()` spends MP at line 918 *before* `SpellCaster.cast()` runs, so a recall press would cost mana and burn a cooldown. Fix: one early branch at the very top of `_cast_signature()` (currently lines 909–912), **before** the cooldown check and **before** the MP check:

```gdscript
func _cast_signature() -> void:
	if _signatures.is_empty():
		return
	var spell: SpellDef = _signatures[_signature_index]
	# Second beat of a THROWN_ANCHOR: the key means RECALL. Free — no MP, no
	# cooldown; the cooldown starts when the anchor resolves (see RiftDagger).
	if spell.kind == SpellDef.Kind.THROWN_ANCHOR \
			and (load("res://scripts/combat/RiftDagger.gd") as GDScript).try_recall(get_tree(), self):
		return
	if _signature_cd_timer > 0.0:
		return
	if mp < float(spell.mp_cost):
		...
```

Because Hero returns early, `SpellCaster`'s own `try_recall` never double-fires for the hero — it exists so the playground (`SpellPlaygroundController._cast()`, line 213, which has no MP/cooldown) gets the same behaviour with zero extra code.

`Hero.gd` — one new tiny public method (the dagger owns the cooldown timing now):

```gdscript
## Start the signature cooldown from OUTSIDE. A deferred-resolution spell (the
## Rift Dagger) only "completes" when its anchor resolves or expires, so it — not
## _cast_signature — decides when the timer starts.
func start_signature_cooldown(seconds: float) -> void:
	_signature_cd_timer = maxf(_signature_cd_timer, seconds)
```
Called duck-typed (`if _owner.has_method("start_signature_cooldown")`), so the playground figure is unaffected.

`Hero.gd:1800-1803` (the AbilityBar slot dict) — while an anchor is live, override the slot name to `"RECALL"` and `"remaining": 0.0`.

### B.2.5 New script — `godot-project/scripts/combat/RiftDagger.gd`

**Model files:** `BoulderHurl.gd` for the flight + collision loop, `BlinkStrike.gd` for the teleport beat, `DrainTether.gd` for the thread draw.

```gdscript
class_name RiftDagger
extends Node2D
```

**Constants:** `SPEED = 780.0`, `SPIN = 22.0` (rad/s), `HIT_RADIUS = 15.0`, `LIVE_TIME = 4.0`, `RECALL_TELL = 0.18`, `ARRIVE_FADE = 0.30`, `ARRIVE_KNOCK = 260.0`, `DROP_ARC = 0.25`, `BLADE_LEN = 17.0`.

**States:** `FLYING → STUCK → RECALLING → SPENT`.

**Public API:**

```gdscript
func throw_dagger(owner_node: Node, from: Vector2, aim: Vector2, color: Color,
		range_px: float, burst_r: float, damage: int, live_time: float,
		cooldown: float, effect: String = "shadow") -> void

func recall() -> void          # begins the RECALL_TELL, then teleports

## Nearest live anchor owned by `caster`, told to recall. True if one existed.
static func try_recall(tree: SceneTree, caster: Node) -> bool
```

`try_recall` is modelled on `RockWall.find_shoveable_near()` (`RockWall.gd:113`): iterate `tree.get_nodes_in_group("rift_anchor")`, keep the one whose `_owner == caster` and whose state is `FLYING` or `STUCK`, call `recall()` on it, return true. Filtering by `_owner` is what makes this co-op-safe — each player only recalls their own dagger.

**Timeline:**

| t | Event |
|---|---|
| 0.00 | Cast. Pose = **THROW** (new, §B.3): over-the-shoulder overhand with a step forward and full follow-through. `_summon_total = SUMMON_WINDUP_FAST` (set `special` accordingly, or leave NORMAL — 0.20 s is right). |
| 0.20 | Dagger spawns at `rig.get_weapon_tip()`, flies straight along `aim.normalized()`. `Sfx.play("melee_swing", -3.0, 0.15)`. |
| 0.20 → ≤1.10 | **FLIGHT** at 780 px/s, max 700 px. Per frame: `_prev = _pos; _pos += _dir * SPEED * delta`, then the collision check below. |
| on hit | **STUCK.** See below. |
| no hit at max range | 0.25 s drop arc to the floor (raycast down, `BoulderHurl._floor_below` idiom), then STUCK. |
| STUCK → +4.00 s from throw | Pulsing rift halo + a faint wavy thread back toward `_owner`. |
| second press | **RECALLING, 0.18 s** — the thread snaps taut and both ends flash white. **This is the arrival telegraph** (an enemy standing on the dagger can step off). |
| +0.18 | Teleport + arrival burst. |
| +0.48 | `queue_free()`, cooldown already started. |
| 4.00 s, no press | Dissolve. `_owner.start_signature_cooldown(_cooldown)`. `queue_free()`. |

**Flight collision** — copy the structure of `BoulderHurl._check_flight_collision` (lines 133–146), enemies first then a world raycast:

```
for e in group "enemy" (or _target_group):
    if _pos.distance_to(e.global_position) <= HIT_RADIUS + 12:
        e.take_damage(_damage, tint); e.apply_status(element_id)
        _anchor_node = e                                   # STICKS IN THE BODY
        _stick_offset = _pos - e.global_position
        -> STUCK
ray _prev -> _pos on layer 1, hit_from_inside = true:
    hit -> _pos = hit.position; _anchor_node = null; -> STUCK
```

While STUCK with `_anchor_node != null` and still valid: `_pos = _anchor_node.global_position + _stick_offset` every frame. **A dagger riding a moving enemy is this spell's best moment** — make sure the thread and halo follow it. If the anchor node dies or is freed, the dagger drops to the floor at its last position and stays recallable.

**Recall resolve:**

```gdscript
var dest: Vector2 = _pos + Vector2(0.0, -4.0)
if _owner != null and _owner.has_method("blink_to"):
	dest = _owner.call("blink_to", dest)      # SAME contract as SpellCaster.gd:194-195
elif _owner is Node2D:
	(_owner as Node2D).global_position = dest
# Arrival burst — radius query modelled on BoulderHurl._apply_impact_damage (line 179)
for e in RiftDagger.targets_in_radius(dest, _burst_r, tree.get_nodes_in_group(_target_group)):
	e.take_damage(_damage, tint)
	e.apply_status(element_id)
	e.apply_knockback((e.global_position - dest).normalized() * ARRIVE_KNOCK)
for prop in ... group "destructible" ...: prop.take_damage(_damage)
for proj in ... group "enemy_projectile" ...: proj.consume()   # arrival clears bolts
# Two bursts, structurally BlinkStrike.strike() lines 44-47:
#   inky puff at the caster's OLD position, HDR flash at `dest`
Juice.hit_stop(0.06); Juice.shake_camera(8.0); Juice.impact_frame(0.6, dest)
Sfx.play("blink", 0.0, -0.05)
if _owner.has_method("start_signature_cooldown"): _owner.start_signature_cooldown(_cooldown)
```

Add `static func targets_in_radius(center, radius, nodes) -> Array` — copy `BoulderHurl.gd:171` verbatim (yes, a sixth copy; extracting a shared `SpellGeometry` helper is a worthwhile but separate cleanup, see §C.5).

**Draw:**
- *Flying:* the blade as a 4-vertex `draw_colored_polygon` (needle) rotated by `_spin`, near-black body + one HDR violet edge line (`Elements.emissive(element_id)`), plus a short 5-point violet after-trail. Facet/rim technique: `BoulderHurl._draw` steps 2 and 5 (lines 246–273).
- *Stuck:* the blade held at its landing angle, a slowly pulsing squashed rift ellipse behind it (`draw_set_transform(_pos, ang, Vector2(1.0, 0.4))` then `draw_circle` + `draw_arc`, the idiom used all over `ShadowRoot._draw_telegraph`, line 235), and a low-alpha wavy thread back to `_owner` — `DrainTether._draw` lines 131–141 verbatim in structure, at ~0.25 alpha.
- *Recalling:* the thread straightens over `RECALL_TELL` (lerp the wobble amplitude to 0) and both endpoints grow HDR flare discs. This is the tell; it must be unmissable.

**Deflect:** same contract as the crawler — `_reflected: bool`, `reflect(new_dir, color)`, `consume()`, group `"deflectable_spell"` **and** `"rift_anchor"`. On reflect: flip `_dir`, set `_target_group = "hero"`, **and set `_owner = null` so the thrower cannot recall to it.** Severing the anchor is the counterplay — a parried dagger is not just deflected, the whole two-beat play is cancelled. Also call `try_parry(self)` against the `"hero"` group during flight (the `EnemyProjectile._check_hit()` pattern, lines 144–161) so an *enemy-thrown* dagger is parryable by the player if this spell is ever given to a boss.

**Rule compliance:** (1) no homing — fixed `_dir`, and the teleport goes to a physical object, not a tracked enemy; (2) dodgeable — a 780 px/s visible projectile (slower than every beam, blockable by `RockWall`/`IceWall`), then a 0.18 s arrival tell; (3) deflectable — above, with the strongest counterplay in the kit; (4) new THROW pose; (5) not a recolor — nothing else leaves a persistent world anchor, and the only reused visual is the arrival flash beat.

---

## B.3 — Shared prerequisite: two new cast poses

`CastStyle.gd` — add to `enum Pose` (line 19, **append**) and to `duration()` (line 51):

```gdscript
enum Pose { POINT, SLAM, CIRCLE, CHANNEL, COIL, LASH, SWEEP, THROW }
```

| Pose | Direction | Duration | For |
|---|---|---|---|
| `SWEEP` | Drop to a low crouch; the trailing hand **drags across the ground** and flicks forward. The spell peels off the floor, not out of the hands. Distinct from SLAM (overhead, driven *down*) and LASH (standing, arm whips *out*). | `0.28` | CRAWLER |
| `THROW` | Over-the-shoulder overhand with a **step forward** and a full cross-body follow-through. The one pose in the kit where the caster's mass moves. Distinct from LASH (wrist flick, no weight transfer). | `0.20` | THROWN_ANCHOR |

Add arms to `for_spell()` for `Kind.CRAWLER → SWEEP` and `Kind.THROWN_ANCHOR → THROW`. **Note the `_:` default at line 44 returns POINT** — a new Kind silently gets POINT if you forget.

**Two files must be touched to make a Pose real** (per the rig's structure):
1. `scripts/spike/SpikeFigure.gd:427` — the `match pose:` inside `func cast(dir, pose)` (line 413), which seeds the arm impulse. `SWEEP`: `throw_ang = 0.0` (hand toward the floor) + a torso crouch impulse. `THROW`: `throw_ang = d.angle() + PI` on the wind, one-armed like LASH (`if pose == LASH and i != 0: continue` at line 438 — extend that guard to THROW).
2. `scripts/spike/SpikeFigure.gd:991` — the `match _cast_pose` inside `_solve_arms()` (gated on `_cast_timer > 0.0`), which holds the pose. **Both matches must be updated or the pose half-works.**

Then extend `godot-project/tools/cast_pose_capture.gd` (lines 41–55 iterate the Pose values; line 55 sizes the frame count from `CastStyle.duration(pose)`) to include the two new poses, and look at the images.

---

## PART C — FOUR MORE DELIVERY SHAPES TO BUILD NEXT

Prioritised by how much of the §A.2 census each one breaks.

### C.1 — DELAYED / TRIGGERED (a trap that arms now and fires on a condition). **Highest value.**

Every one of the 24 spells resolves *because you pressed the button*. Not one fires because the **world** did something. A glyph you plant that detonates when a body crosses it (or after N seconds, whichever first) breaks the single most universal property of the kit — it is the only proposal here that touches all 24 spells' sameness at once rather than one cluster's. It also fits the tower-climb/co-op design better than anything else on this list: plant the trap, bait the enemy onto it, and in co-op one player sets while the other herds. **Model:** `ZoneSpell.gd` `_process`/`_tick` (lines 95–135) for the persistence loop, plus `BlinkStrike.targets_on_line` (line 57) or `BoulderHurl.targets_in_radius` (line 171) for the trip test, plus `RockPillar`'s charge-then-erupt timeline (lines 74–105) for the detonation. Cheapest of the four to build; largest identity return.

### C.2 — PERSISTENT MOVING HAZARD (a wall of force / rolling mass that keeps going on its own). **Second.**

This converts Shape G's 9 spells from *"a circle appears here"* into *"a threat is coming and it does not stop"* — spatial pressure instead of a placed AoE. The clearest instance: a sweeping wall of flame that walks the arena floor, forcing repositioning for its whole life. **The code already exists and no spell uses it as its primary delivery:** `RockWall.shove()` (line 152) + `_process_slide()` (line 274) + `_plow_enemies()` (line 344) + `_slam_stop()` (line 393) is a complete moving-solid-that-plows-bodies implementation, currently reachable only as a secondary interaction on a defensive wall. Promote that motion model to a first-class spell and Shape G stops being nine variations of a circle.

### C.3 — HEIGHT-BAND SWEEP FROM AN ARENA EDGE. **Third.**

Every spell today originates at the caster, at a ground point, or directly overhead — and **aim is only ever used for direction or ground placement. Nothing in the kit asks the player to choose a height.** A wave that enters from the left or right arena edge and sweeps across at the vertical band you aimed at — duck under it or jump over it depending on where you put it — adds a whole new input axis rather than a new visual. It is also the first spell that would meaningfully use the side-view arena's vertical space, which `MeteorSigil`'s `GROUND_SCATTER = Vector2(1.0, 0.35)` comment (line 68) shows the kit currently squashes flat. **Model:** `ZoneSpell._draw_squall`'s wind-driven streak system (lines 231–254) for the look; `BeamSpell.targets_on_beam` (line 250) with the aim locked to horizontal and the origin off-screen for the hit test.

### C.4 — OUT-AND-BACK (boomerang). **Fourth.**

Every projectile in the kit is one-way. A thrown thing that damages on the way out *and* on the way back doubles the aim decision — you position yourself for the return, which is a timing skill nothing else exercises. Lowest priority only because Shape P holds just 2 of 24 spells, so it kills the least existing sameness; but it is the cheapest to prototype. **Model:** `RuneOrbs._orb_position()` (lines 80–84) — replace the linear `origin + dir * SPEED * age` with a ping-pong ease and let the existing `_target_within` (line 100) hit test run both directions, with a per-target already-hit set so the outbound pass doesn't double-dip.

### C.5 — Cleanup that makes all of the above cheaper (not a shape, but do it)

Extract the two duplicated selectors (§A.3) into one `scripts/combat/SpellGeometry.gd` with `static func targets_on_line(...)` and `static func targets_in_radius(...)`, and have the ten existing copies delegate. Two benefits: new spells stop adding an eleventh copy, and the *shape* of a spell becomes legible at a glance from which helper it calls — which is exactly the property that would have made this audit unnecessary.

---

## PART D — IMPLEMENTATION CHECKLIST

Ordered. Each numbered item is commit-sized.

1. **`CastStyle.gd`** — append `SWEEP`, `THROW` to `Pose`; add `duration()` arms (0.28 / 0.20); add `for_spell()` arms for the two new Kinds. *(Optional but recommended: change `for_spell(kind: int)` → `for_spell(spell: SpellDef)`; one call site, `SpellPlaygroundController.gd:225`.)*
2. **`scripts/spike/SpikeFigure.gd`** — add SWEEP/THROW arms to **both** matches: `cast()` line 427 and `_solve_arms()` line 991. Extend the one-armed guard at line 438 to cover THROW.
3. **`SpellDef.gd:16`** — append `CRAWLER, THROWN_ANCHOR` to `enum Kind`. **Append only** — the file's own comment explains why inserting breaks BOULDER/PILLAR/WALL.
4. **`scripts/combat/ShadowCrawler.gd`** — new, per §B.1.5.
5. **`scripts/combat/RiftDagger.gd`** — new, per §B.2.5.
6. **`SpellCaster.gd`** — two path consts beside lines 11–27; two arms in the `match` at line 50.
7. **`Hero.gd`** — the recall early-branch at the top of `_cast_signature()` (line 909); new `start_signature_cooldown()`; AbilityBar slot name override at lines 1800–1803.
8. **`scripts/spike/SpikeFigure.gd`** — widen `_process_projectiles()` (~line 920) to iterate `"deflectable_spell"` as well as `"enemy_projectile"`, so the new spells are parryable in the playground.
9. **`SpellLibrary.gd`** — `_creeping_shade()`, `_rift_dagger()`; **append** both to `build_all()` (→ indices 24, 25); add both to `build_for_class(1)` SHADOWBLADE.
10. **`scripts/spike/SpellPlaygroundController.gd`** — add arms to `_kind_name()` (~line 374) for the two new Kinds, or the HUD prints nothing for them.
11. **Tests** — `tools/slice4_test_spells.gd`: add `_test_crawler_catch()` (x-window + y-window + airborne-miss) and `_test_dagger_burst_radius()`; wire both into the `failed +=` chain. `tools/slice3_test_parry.gd`: add a case that `reflect()` flips `_dir`/`_target_group` and that a reflected dagger has `_owner == null`. **Follow the house idiom exactly:** `extends SceneTree`, `_ran` guard, work in `_process()` (never `_init`), scripts `load()`ed by path const (never `class_name` — a compile-time reference to an autoload-touching script prints a **false PASS**), `_expect(cond, msg) -> int`, `print("Slice4 spell tests: all PASS"); quit(0)`.
12. **Screenshots** — `tools/spell_playground_capture.gd` addresses spells by **raw index** into `build_all()` (`_scene.get("_spells")[0]` = beam, `[11]` = meteor). Appending is safe; **inserting into a themed group silently re-points the existing captures.** Add blocks for `[24]` and `[25]` (crawler ≈ 60 frames for the travel; dagger ≈ 45 frames for flight, then a second block that calls `recall()` and waits ~25 more). Note the tool calls `SpellCaster.cast()` directly and therefore **does not exercise the pose** — to see the SWEEP/THROW windup in a shot, set `_scene._sidx` and call `_scene._cast()` instead. Also extend `tools/cast_pose_capture.gd` for the two new poses.
13. **Verify by looking.** Per the plan's screenshot protocol: `godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/spell_playground_capture.gd`, PNGs land in `%APPDATA%\Godot\app_userdata\Legacy Frontier\`. Read the images and iterate until they're thrilling. Then run the headless suites with the console binary: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice4_test_spells.gd`.
14. **Playground checks that are not covered by tests** — raise a `RockWall`, send the crawler at it, confirm it passes **under**; send the crawler off a ledge into a pit, confirm it dies; stick the dagger in a walking enemy and confirm the halo/thread ride the body; parry both with `C` in the playground and confirm reflection + anchor severing.
