# Smart Bots — build plan (design recon, 2026-07-27)

Branch: `stickman-integrate`. Status: **RECON ONLY — nothing built.** This document validates
the prior 3-layer bot proposal against the actual code and turns it into an ordered, verifiable
build plan.

Locked constraints honoured throughout:

- **Classical AI only.** No LLM anywhere near combat. Every module below is pure math over a
  blackboard dictionary.
- **SP must stay byte-identical** unless a change is deliberate. Every seam below defaults to the
  existing code path.
- **43 headless suites stay green.** Per-task regression lists are given.

---

## 0. Verdict on the proposal

The three-layer architecture (utility scorer → context steering → micro-FSM) is **right and
survives contact with the code**. GOAP rejection is correct and the code proves it: enemy attack
windups are 0.35–0.9 s (`Enemy.gd:53,63,69,82,94,110`) and every telegraph re-snapshots the target
at windup start, so any plan older than ~1 s is already stale.

Six things in the proposal the real code contradicts or under-specifies. These are the load-bearing
corrections.

### C1 — A Hero-shaped bot currently cannot fight anyone. The input seam is necessary but NOT sufficient.

The proposal's marquee claim is "any class is bot-playable the moment a human can play it."
That is true for *driving* a hero and false for *fighting* with one. Damage routing in this
codebase is **group-hardwired, not faction-based**:

- `Hero._dash_strike_sweep` (`Hero.gd:1186`), `Hero._uppercut` (`Hero.gd:1286`),
  `Hero._nearest_enemy_in_melee_range` (`Hero.gd:1867`) all iterate
  `get_tree().get_nodes_in_group("enemy")` — a bot hero would ignore the player entirely.
- `Hero._fire_punch` / `_ground_slam` hard-code `"target_group": "enemy"`
  (`Hero.gd:1587`, `Hero.gd:1603`).
- `SpellCaster.cast()` (`SpellCaster.gd:38-41`) has **no target-group parameter**, so every
  spectacle it builds keeps its `target_group = "enemy"` default.
- `Spell.gd` only damages a hero when a net session is live: the mask bit is added under
  `netmgr.is_active()` (`Spell.gd:67-69`) and the hero branch itself is inside an
  `if netmgr != null and netmgr.is_active()` (`Spell.gd:157-167`).

So in singleplayer, hero-vs-hero does literally nothing in either direction.

**Good news:** the faction seam is small, because 13 spectacle scripts *already* carry a
`target_group` var that the Boss flips to `"hero"` (`BeamSpell.gd:6`, `DivineRay.gd:5`,
`MeteorSigil.gd:5`, `StarConvergence.gd:5`, `RockPillar.gd:5`, `EnergyNova.gd:5`,
`BlastSpell.gd:26`, and Boss's setters at `Boss.gd:236,254,266,283,318,328,335`). The work is one
extra parameter on `SpellCaster.cast`, one `hostile_group` field on Hero threaded through ~12 call
sites, and one branch in `Spell.gd`. It is a **prerequisite task**, not an afterthought — see T6.

### C2 — Global `Input.action_press` is not a usable seam, despite `TouchControls` using it.

`TouchControls` drives real input actions (`TouchControls.gd:132`, `TouchControls.gd:191-192`) and
that works because there is exactly one local player. Input state is **process-global**: two bots
would fight over the same virtual buttons, and any bot press would also drive the human's hero.
The controller must be **per-instance**.

Corollary: the seam must keep `Input` as the fallback rather than replace it —
`tools/slice_test_touch.gd` asserts the touch layer presses real actions, and
`tools/slice_test_movement.gd` drives the hero with `Input.action_press("move_right")`.
A `controller == null` default preserves both.

### C3 — Telegraphs are invisible to any bot. This is the single biggest blocker to the dodge brain.

`Telegraph` nodes are added as bare arena siblings (`Enemy.gd:677`) and join **no group**. All
geometry is private: `_radius`, `_windup`, `_elapsed`, `_shape`, `_length`, `_width`, `_angle`
(`Telegraph.gd:30-38`). A dodge brain cannot see the thing it exists to dodge.

Fix is one group + four read-only accessors (T2). It pays for itself twice, because
`BlastSpell.detonate_at` spawns a **real `Telegraph`** (`BlastSpell.gd:51-54`) — so the boss's
`slam` and the hero's meteor-Q become perceivable for free.

### C4 — Projectile perception is already zero-touch. Don't over-build it.

Both `Spell.launch` (`Spell.gd:32-35`) and `EnemyProjectile.launch`
(`EnemyProjectile.gd:53-57`) set `rotation = dir.angle()`, and both have a constant `SPEED`
(`Spell.gd:4` = 460, `EnemyProjectile.gd:7` = 260). Groups already exist: `player_spell`
(`Spell.gd:63`) and `enemy_projectile` (`EnemyProjectile.gd:42`). A bot reads velocity today as
`Vector2.from_angle(n.rotation) * SPEED`. Add a `travel_velocity()` accessor for clarity, but
perception is not blocked on it.

### C5 — A proto-dodge already exists. Replace it, don't run a second one alongside.

`Enemy._try_evade` (`Enemy.gd:457-485`) is a crude first draft of exactly this feature: scan
`player_spell` within `EVADE_DANGER_R` 155 px, hop away on the leap arc, or deflect point-blank on
Impossible. It ignores telegraphs, AoEs, meteors and melee entirely, and its arc is hard-coded.

It also means the **difficulty-as-reaction-time model is already half-built**: the `DIFFICULTY`
table (`Enemy.gd:224-229`) has a per-tier `evade_cd` reflex cooldown. Add a `react` column to the
same rows so there is one difficulty source of truth, and swap `_try_evade`'s body for the new
module.

### C6 — Ordering correction: build the DODGE BRAIN before the input seam.

The proposal orders it seam → dodge. But the maker's #1 felt win — *a bot reads your telegraph and
dashes out at human speed* — lands on the **existing `Enemy` bodies** in the **existing
`VersusArena`**, which already has a live Difficulty cycle button
(`VersusArena.gd:462-473`). No seam, no faction work, nothing to regress.

Write the dodge brain as a **body-agnostic pure module over a blackboard dictionary** and wiring it
to `Enemy` first costs only a thin adapter; reusing it on hero-bots later is free. This puts the
felt win in front of an F5 two tasks earlier. Order is corrected in §5.

### Smaller findings

- **Hitstop distorts every timer.** `Juice.hit_stop` sets `Engine.time_scale = 0.05`
  (`Juice.gd:14`). Reaction delays must tick on **scaled `delta`** — the same clock the player
  perceives — or bots get a free ~20× reflex boost on every connect.
- **`Hero.tscn` carries a `Camera2D` child.** A bot hero must disable it, mirroring
  `Hero._setup_net_role` (`Hero.gd:2146-2151`), or it steals the viewport.
- **Cooldown introspection already exists.** `Hero.ability_hud_state()` (`Hero.gd:1759-1770`)
  returns `{name, key, remaining, total, enabled}` per slot — exactly the blackboard the utility
  scorer needs. Reuse it; do not add a parallel API.
- **`spell.reach` is overloaded.** It is a cast-range clamp for PLACED kinds, a *hop range* for
  `CHAIN`, and unused for `WALL`/`ICE_WALL`. The scorer must not treat it as range uniformly.
- **The playground rig is the wrong target.** `scripts/spike/SpikeFigure.gd` is explicitly a
  throwaway spike ("Touches no game code; delete `scripts/spike/` to remove", `SpikeFigure.gd:13`)
  with its own physics model, its own punch/dash/parry, and no class system, no `_cfg`, no
  signature loadout, no `take_damage` contract shared with `Hero`. **Bots target
  `scripts/combat/Hero.gd` and `scripts/combat/Enemy.gd`.** The only thing the spike shares is a
  duck-typed `blink_to` (`SpikeFigure.gd:369`) consumed by `SpellCaster.gd:194-195`.
- **The Boss is a perception blind spot.** `Boss.gd` extends `Enemy` but never calls
  `_emit_telegraph`; its tells are each spectacle's internal windup. Only `slam` is visible
  (BlastSpell → real Telegraph). `pillars` / `rays` / `meteor` / `convergence` draw their own
  markers and stay invisible to a bot. Out of scope for v1; noted so nobody is surprised.

---

## 1. Architecture (as corrected)

```
                   ┌───────────────────────────────────────────┐
                   │  BotPerception  (pure, static)            │
   world  ────────▶│  scan groups → threats → reaction queue   │──▶ Blackboard (Dictionary)
                   └───────────────────────────────────────────┘
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        ▼                               ▼                               ▼
┌───────────────┐             ┌───────────────────┐           ┌──────────────────┐
│ BotDodge      │  ~30 Hz     │ BotSteering       │ 20–30 Hz  │ BotUtility       │  ~5 Hz
│ reflex layer  │  (preempts) │ interest / danger │           │ IAUS scorer      │  + events
└───────┬───────┘             └─────────┬─────────┘           └────────┬─────────┘
        └───────────────┬───────────────┴────────────────────────────  ┘
                        ▼
                 ┌─────────────┐
                 │  BotIntent  │  move_x, aim_pos, jump, dash, parry, cast, ult, …
                 └──────┬──────┘
                        ▼
        ┌───────────────────────────────┐        ┌──────────────────────────────┐
        │ BotController : HeroController│   or   │ Enemy adapter (direct calls) │
        │ (virtual buttons → Hero)      │        │ (velocity / state machine)   │
        └───────────────────────────────┘        └──────────────────────────────┘
```

Every box left of `BotIntent` is **pure static functions over dictionaries** — no nodes, no tree,
no signals. That is what makes the whole thing headless-testable and what lets the same brain drive
both body types.

---

## 2. The input seam — exact shape

### 2.1 Two objects, not one

The proposal's `BotIntent` conflates *what the brain wants* with *how Hero polls*. Split them:

**`scripts/combat/BotIntent.gd`** — plain data the brain writes each tick.

```gdscript
class_name BotIntent
extends RefCounted

var move_x: float = 0.0                     # [-1, 1], analog like Input.get_axis
var move_y: float = 0.0                     # [-1, 1] — feeds Input.get_vector for dash angle only
var aim_pos: Vector2 = Vector2.INF          # world point; INF = hold last aim
## Held buttons. Edge events (just_pressed / just_released) are DERIVED by the
## controller from the previous tick, so the brain never has to think in edges.
var held: Dictionary = {}                   # StringName -> bool

func press(action: StringName) -> void:  held[action] = true
func clear() -> void:  held.clear(); move_x = 0.0; move_y = 0.0; aim_pos = Vector2.INF
```

**`scripts/combat/HeroController.gd`** — the polling interface Hero talks to. Mirrors Godot's
`Input` API 1:1 so every call site is a mechanical rename.

```gdscript
class_name HeroController
extends RefCounted

func is_pressed(action: StringName) -> bool:            return false
func just_pressed(action: StringName) -> bool:          return false
func just_released(action: StringName) -> bool:         return false
func axis(neg: StringName, pos: StringName) -> float:   return 0.0
func vector(nx: StringName, px: StringName, ny: StringName, py: StringName) -> Vector2: return Vector2.ZERO
## Replaces get_global_mouse_position(). `from` is the hero's global_position so an
## implementation can return a point at a fixed offset along an aim direction.
func aim_point(from: Vector2) -> Vector2:               return from + Vector2.RIGHT
```

**`scripts/combat/BotController.gd extends HeroController`** — holds a `BotIntent` plus a snapshot
of last tick's `held` dictionary, and computes edges by diffing. It also **hard-returns `false`**
for `cycle_element`, `cycle_colourway`, `switch_class`, `cycle_signature` regardless of intent —
a bot must never re-roll its own class or loadout mid-fight (`Hero._cycle_class` at `Hero.gd:890`
writes through to `GameState.selected_class`, which would corrupt the player's choice).

### 2.2 Hero-side plumbing

```gdscript
var controller: HeroController = null   # null => keyboard/touch (byte-identical SP)

func _pressed(a: StringName) -> bool:
    return controller.is_pressed(a) if controller != null else Input.is_action_pressed(a)
func _just(a: StringName) -> bool:
    return controller.just_pressed(a) if controller != null else Input.is_action_just_pressed(a)
func _released(a: StringName) -> bool:
    return controller.just_released(a) if controller != null else Input.is_action_just_released(a)
func _axis(n: StringName, p: StringName) -> float:
    return controller.axis(n, p) if controller != null else Input.get_axis(n, p)
func _vector(nx: StringName, px: StringName, ny: StringName, py: StringName) -> Vector2:
    return controller.vector(nx, px, ny, py) if controller != null else Input.get_vector(nx, px, ny, py)
func _aim_point() -> Vector2:
    return controller.aim_point(global_position) if controller != null else get_global_mouse_position()
```

### 2.3 Every Input call site in `Hero.gd` that must change

18 sites. All mechanical.

| Line | Current | Becomes |
|---|---|---|
| 480 | `get_global_mouse_position() - global_position` | `_aim_point() - global_position` |
| 490 | `Input.is_action_pressed("move_down")` | `_pressed(&"move_down")` |
| 505 | `Input.is_action_just_pressed("cycle_element")` | `_just(&"cycle_element")` |
| 507 | `Input.is_action_just_pressed("cycle_colourway")` | `_just(&"cycle_colourway")` |
| 509 | `Input.is_action_just_pressed("switch_class")` | `_just(&"switch_class")` |
| 511 | `Input.is_action_just_pressed("cycle_signature")` | `_just(&"cycle_signature")` |
| 513 | `Input.is_action_just_pressed("ultimate")` | `_just(&"ultimate")` |
| 515 | `Input.is_action_just_pressed("parry")` | `_just(&"parry")` |
| 517 | `Input.is_action_pressed("cast")` | `_pressed(&"cast")` |
| 543 | `Input.get_axis("move_left", "move_right")` | `_axis(&"move_left", &"move_right")` |
| 546 | `Input.is_action_just_pressed("jump")` | `_just(&"jump")` |
| 576 | `Input.is_action_just_released("jump")` | `_released(&"jump")` |
| 677 | `Input.is_action_just_pressed(action)` (buffer loop over melee/dash/blast/blink/nova) | `_just(StringName(action))` |
| 951 | `_summon_target = get_global_mouse_position()` | `_summon_target = _aim_point()` |
| 1058 | `_channel_target = get_global_mouse_position()` | `_channel_target = _aim_point()` |
| 1220 | `Input.get_vector("move_left","move_right","move_up","move_down")` (in `_start_dash`) | `_vector(...)` |
| 1561 | `get_global_mouse_position() - global_position` (in `_meteor_blast`) | `_aim_point() - global_position` |
| 1632 | `get_global_mouse_position() - global_position` (in `_aoe_target`) | `_aim_point() - global_position` |

Plus one branch reorder at **`Hero.gd:475-483`**, the aim resolution block. A controller must win
over the mobile auto-aim path:

```gdscript
if controller != null:
    var to_aim: Vector2 = _aim_point() - global_position
    if to_aim.length() > 1.0:
        _aim_dir = to_aim.normalized()
elif _touch_aim():
    ...unchanged...
else:
    ...unchanged...
```

Optional tidy (behaviour-identical, not required): lines 1561-1564 duplicate `_aoe_target()`
(`Hero.gd:1631-1635`) exactly — same `BLAST_MAX_RANGE` clamp. Collapsing `_meteor_blast` to call
`_aoe_target()` removes a call site. Do it only if the diff stays trivially reviewable.

### 2.4 Why this is safe

With `controller == null` every helper resolves to the identical `Input` call it replaced. There is
no behaviour change, no ordering change, and no allocation. `TouchControls` keeps working unchanged
because it drives the same named actions through global `Input`, which is still the null-controller
path.

---

## 3. Perception model

### 3.1 What a bot can see (all from the real code)

| Source | How | Cost |
|---|---|---|
| Foes / allies | `get_nodes_in_group("hero" / "enemy")` | zero-touch |
| Hero projectiles | group `player_spell` (`Spell.gd:63`); pos, `Vector2.from_angle(rotation) * 460`, `damage` | zero-touch |
| Enemy projectiles | group `enemy_projectile` (`EnemyProjectile.gd:42`); `* 260`; parryable (`has_method("reflect")`) | zero-touch |
| **Attack telegraphs** | **NEW** group `telegraph` + accessors (T2). Covers all 7 enemy archetypes *and* `BlastSpell.detonate_at` | 1 group + 4 getters |
| Ring-out pits | group `stage_hazard` (`StageHazard.gd:39`); read `mode == 0` and `zone_size` — the exact idiom `Hero._dest_in_pit` already uses (`Hero.gd:1371-1382`) | zero-touch |
| Cover / interactables | groups `destructible`, `shoveable` (`RockWall.gd:79`), `ice_wall` (`IceWall.gd:70`), `breakable_platform` | zero-touch |
| Own cooldowns / MP | `Hero.ability_hud_state()` (`Hero.gd:1759`), `Hero.current_signature()`, `hp`/`max_hp`/`damage_pct`/`mp` | zero-touch |
| Ground & ledges | `PhysicsDirectSpaceState2D` down-rays ahead of the feet. No navmesh, no pathfinding — single-screen arenas, exactly as proposed. For "can I reach that ledge", **reuse `Enemy.compute_leap_velocity`** (`Enemy.gd:369-380`) verbatim — it is already a pure ballistic solver. | zero-touch |

Known gaps, accepted for v1: hero melee has no pre-swing tell a bot can read (it resolves on the
rig's `hit_frame`); `MeteorSigil` / `RockPillar` / `DivineRay` / `StarConvergence` draw their own
impact markers rather than `Telegraph` nodes, so boss spectacles beyond `slam` stay invisible.

### 3.2 Threat record

```gdscript
# One entry per perceived threat, keyed by the source node's instance_id.
{
  "id": int,                 # get_instance_id() of the source node
  "kind": int,               # PROJECTILE | ZONE | LANE
  "pos": Vector2,            # circle centre, or lane origin
  "vel": Vector2,            # PROJECTILE only
  "radius": float,           # ZONE only
  "length": float, "width": float, "angle": float,   # LANE only
  "tti": float,              # seconds until it hurts (see §3.4)
  "damage": int,
  "parryable": bool,         # has_method("reflect")
  "source": int,             # instance_id of the caster, or 0
}
```

### 3.3 The reaction-delay queue — with the correction that makes it feel human

```gdscript
class_name BotPerception
extends RefCounted

var _seen: Dictionary = {}      # id -> reveal_time (float, seconds on the bot clock)
var _clock: float = 0.0

## Advance on SCALED delta — the same clock the player perceives through hitstop.
func tick(delta: float) -> void:
    _clock += delta

## Returns only the threats this bot is allowed to have noticed yet.
func filter(raw: Array, base_delay: float, jitter: float) -> Array:
    var out: Array = []
    var live: Dictionary = {}
    for t: Dictionary in raw:
        var id: int = int(t["id"])
        live[id] = true
        if not _seen.has(id):
            _seen[id] = _clock + base_delay + randf_range(-jitter, jitter)
        if _clock >= float(_seen[id]):
            out.append(t)                      # full-fidelity, live data
    for id: int in _seen.keys():               # forget threats that expired
        if not live.has(id):
            _seen.erase(id)
    return out
```

**The correction:** the delay is applied **at first sighting per threat id**, and *only* there.
Once a threat is visible the bot tracks it at full fidelity. The naive "always read a 250 ms-stale
world" model reads as drunk, not human — a person who has already registered the fireball tracks it
in real time. This distinction is what makes the difference between "smart" and "laggy".

**Reaction profiles** — fold into the existing `Enemy.DIFFICULTY` table (`Enemy.gd:224-229`) as a
new `react` column so difficulty has exactly one source of truth:

| Tier | `react` (ms) | jitter (ms) | `evade_cd` (existing) | whiff rate `p_miss` |
|---|---|---|---|---|
| Easy | 380 | ±120 | 1.2 | 0.45 |
| Normal | 300 | ±90 | 1.0 | 0.28 |
| Hard | 220 | ±70 | 0.85 | 0.12 |
| Impossible | 150 | ±45 | 0.5 | 0.03 |

`p_miss` is the second half of "beatable": with that probability the brain deliberately skips a
dodge or takes the second-best exit. Reaction time alone produces a bot that never whiffs, and
losing to a bot that never whiffs is not fun. This is an addition to the proposal, not a
contradiction of it.

---

## 4. The dodge brain — the top priority, in detail

### 4.1 The design grammar it exploits

`Enemy._start_windup` (`Enemy.gd:699-708`) **snapshots the hero's position** and plants a circle
there that never moves. Same for `_start_mage_windup` (`Enemy.gd:813-821`) and
`_start_assassin_windup` (`Enemy.gd:1032-1043`). The charger locks a flat lane
(`Enemy.gd:862-875`). The bomber marks its own feet (`Enemy.gd:1082-1090`).

That grammar means the dodge is *analytically solvable*: "will my predicted position at fire time
be inside the marked region, and if so what is the shortest exit vector?" No search, no sampling.
It also means **moving at all beats a snapshot tell** — so the brain must dodge *out of* the region
along the shortest exit, not merely "move away from the caster".

### 4.2 Threat evaluation

**PROJECTILE — closest-approach solve.** Treat the bot as static over the horizon (correct enough
at 260–460 px/s):

```
rel  = threat.pos - me
t*   = clamp(-rel.dot(vel) / vel.length_squared(), 0.0, HORIZON)     # HORIZON ≈ 0.9 s
miss = (rel + vel * t*).length()
threatening  ⟺  miss < BODY_R + MARGIN  and  t* < HORIZON            # BODY_R ≈ 10, MARGIN ≈ 14
tti = t*
```

**ZONE (circle) — `tti = telegraph.time_to_fire()`.** Predict my position at `tti` from current
velocity; threatening iff `predicted.distance_to(centre) < radius + MARGIN`. Exit vector is
`(predicted - centre).normalized() * (radius + MARGIN - dist)`; when `predicted == centre` pick the
axis with the most open ground (see §4.4 safety scoring).

**LANE (OBB)** — transform my predicted point into the lane's local frame
(`-angle` rotation about the origin) and test `0 <= local.x <= length` and
`abs(local.y) <= width * 0.5 + MARGIN`. Exit is perpendicular: `±(width * 0.5 + MARGIN - |local.y|)`
along the lane normal, whichever side is safer.

### 4.3 Response selection (first affordable wins)

1. **Dash — clearance mode.** Off cooldown, and the dash displacement clears the region.
   Displacement is `DASH_SPEED * DASH_TIME` ≈ `620 * 0.14` = **87 px** (`Hero.gd:13-14`).
2. **Dash — i-frame mode.** `Hero.take_damage` returns early for the whole dash
   (`Hero.gd:2011-2012`), so a dash *timed to overlap impact* beats any threat even without
   clearing it. This is the strongest read in the game and looks like cheating if unrestricted:
   gate it to **Hard+**, put it behind the full reaction delay, and rate-limit it to one per
   `evade_cd`.
3. **Blink.** 175 px, phases walls, `BLINK_IFRAME` 0.22 s (`Hero.gd:72-79`). Better clearance,
   longer cooldown. Note `_blink` fires along `_move_dir`, not aim (`Hero.gd:1252`) — the brain
   must set `move_x` *before* pressing blink.
4. **Parry.** Only if `_cfg["can_parry"]`, off cooldown, and `tti` lands inside the window —
   `PARRY_WINDOW` 0.16 s, or 0.40 s for the Juggernaut block (`Hero.gd:97`, `Hero.gd:783`).
   Parry blocks **melee, contact and charge hits too**, not just projectiles
   (`Hero.gd:2016-2026`) — so parry is a legitimate answer to a CHARGER lane and a BRUTE zone,
   which is a much richer reflex than the proposal assumed.
5. **Jump** when the exit is vertical and `is_on_floor()`.
6. **Walk out** — hand the exit vector to the steering layer as a hard interest override.

### 4.4 Safety gates and commitment

- **Never dodge into a pit.** Score every candidate exit against the `stage_hazard` rects using
  the `Hero._dest_in_pit` idiom (`Hero.gd:1371-1382`) plus a margin. Reject, then re-pick.
- **Never dodge into another live telegraph.** Sum the danger of all visible regions at the
  candidate landing point; take the minimum-danger exit.
- **Latch the decision.** Once chosen, hold for the action's duration plus a short lockout
  (dash 0.14 s + ~0.15 s). Re-evaluating every frame is what makes bots twitch.
- **Roll `p_miss` once per threat**, at the moment the threat first becomes visible — not every
  frame, or the bot flickers between committed and passive.

### 4.5 Headless verification (this is the whole point of keeping it pure)

New suite `tools/slice6_test_bot_dodge.gd`:

- projectile aimed dead-on → threatening; same projectile offset 60 px → not threatening.
- `t*` clamps to 0 for a projectile already past the bot (receding) → not threatening.
- circle centred on me, `tti` 0.4 s → exit magnitude > `radius - my_offset`; direction is the
  shortest way out.
- lane OBB containment: 4 corners inside, 4 just-outside, plus a point past `length`.
- reaction queue: threat observed at `t=0` with delay 0.25 → invisible at `t=0.24`, visible at
  `t=0.26`; after reveal, the returned position equals the live position (no staleness).
- a threat that disappears is forgotten (`_seen` shrinks) so a recycled instance id can't
  inherit an old reveal time.
- response ladder: prefers dash when off cooldown; falls to jump when dash is cooling; falls to
  walk-out when grounded and both are cooling.
- exit vector never lands inside a registered pit rect.

---

## 5. Task breakdown (ordered; each step independently verifiable, game playable throughout)

Run command for every suite:

```
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/<suite>.gd
```

Green is a literal `"<suite> tests: all PASS"` + exit 0. New suites **must** be named
`slice*_test_*.gd` to be picked up by the sweep glob (`test_class_attacks.gd` and the `m9..m12`
suites are already missed by it). Run `--headless --path godot-project --import` once after any
task that introduces a new `class_name` (the class-cache trap).

---

### T1 — `BotPerception` + blackboard (pure). No wiring.

Add `scripts/combat/BotPerception.gd` (threat records, the reveal queue from §3.3) and a
`BotBlackboard` builder that scans the groups in §3.1 into a plain Dictionary.

- **Game change:** none. Nothing calls it.
- **New suite:** `tools/slice6_test_bot_perception.gd` — group scans return the right shapes;
  reveal-queue timing; forgetting; scaled-clock accumulation.
- **Regression:** none.

### T2 — Make telegraphs and projectiles observable.

`Telegraph.gd`: add `_ready()` with `add_to_group("telegraph")`, plus pure getters
`time_to_fire() -> float` (`_windup - _elapsed`), `danger_radius() -> float`, `is_lane() -> bool`,
`lane_geometry() -> Dictionary` (`{length, width, angle}`). `Spell.gd` / `EnemyProjectile.gd`: add
`travel_velocity() -> Vector2`.

- **Game change:** none — a group membership and read-only accessors. No draw path, no timing path
  touched.
- **Verify:** extend the existing `tools/slice1_test_telegraph.gd` (it already drives
  `advance()` deterministically) rather than adding a file — assert `time_to_fire()` counts down,
  `danger_radius()` matches the `start()` argument, `is_lane()` flips under `start_line()`.
- **Regression:** `slice1_test_telegraph.gd`, `slice2_test_enemy_archetypes.gd`,
  `slice3_test_enemy_abilities.gd`, `slice_test_coop_effects.gd` (telegraph twins).

### T3 — `BotDodge` decision module (pure). No wiring.

`scripts/combat/BotDodge.gd`: threat evaluation (§4.2), response ladder (§4.3), safety scoring and
latching (§4.4). Static functions over the blackboard.

- **Game change:** none.
- **New suite:** `tools/slice6_test_bot_dodge.gd` (full list in §4.5).
- **Regression:** none.

### T4 — Wire the dodge brain into `Enemy`. ⭐ FIRST FELT WIN — playable at F5.

Replace `Enemy._try_evade` (`Enemy.gd:457-485`) with a perception+dodge call. Add `react` and
`p_miss` columns to `Enemy.DIFFICULTY` (`Enemy.gd:224-229`) and read them in `_apply_difficulty`
(`Enemy.gd:441-451`). Keep `_deflect` (`Enemy.gd:489-500`) as the Impossible-tier response inside
the new ladder.

- **Game change:** deliberate and only at Hard/Impossible (Easy/Normal keep `dodge: false`, so
  those tiers are byte-identical). Enemies now dodge **telegraphed AoEs and lanes**, not just
  bolts, and their reflex is reaction-delayed instead of instant.
- **Maker verification:** F5 → `VersusArena` → the existing **Difficulty** button
  (`VersusArena.gd:462-473`) cycles Easy→Impossible and reloads. Cast a meteor-Q at a bot on Hard;
  it should read the tell and leave the circle ~220 ms after it blooms.
- **Regression:** `slice2_test_enemy_archetypes.gd`, `slice3_test_enemy_sideon.gd`,
  `slice3_test_enemy_abilities.gd`, `slice1_test_enemy_attack.gd`, `slice_test_coop.gd`,
  `slice3_test_versus.gd`, `slice_test_boss.gd`.

### T5 — The input seam.

`BotIntent.gd`, `HeroController.gd`, `BotController.gd`, plus the 18 `Hero.gd` call sites and the
aim-branch reorder from §2.

- **Game change:** none with `controller == null`.
- **New suite:** `tools/slice6_test_input_seam.gd` — drive a real `Hero.tscn` with a scripted
  `HeroController` through move / jump / dash / cast / ult, and assert the resulting hero state
  matches what the same sequence of `Input.action_press` produces on a null-controller hero.
  Also assert `BotController` suppresses the four cosmetic/class actions.
- **Regression (the big one — 14 Tier-1 suites plus 3):** `slice_test_movement.gd` (pokes
  `_jump_buffer`/`_coyote` and uses `Input.action_press` — the null-controller path must stay
  intact), `slice3_test_parry.gd`, `slice2_test_rogue.gd`, `slice_test_summon.gd`,
  `slice5_test_classes.gd`, `slice_test_class_q.gd`, `slice_test_loadout.gd`,
  `slice_test_selfdamage.gd`, `slice1_test_blink.gd`, `slice1_test_weapon.gd`,
  `slice1_test_elements.gd`, `slice1_test_nova.gd`, `slice_test_ringout.gd`,
  `test_class_attacks.gd` *(outside the sweep glob — run it explicitly)*, plus
  `slice3_test_versus.gd`, `slice_test_sandbox.gd`, and `slice_test_touch.gd`.

### T6 — The faction seam (correction C1). Prerequisite for hero-shaped bots.

Add `Hero.hostile_group: StringName = &"enemy"` and thread it through: the melee/dash/uppercut
group scans (`Hero.gd:1186`, `1286`, `1867`), the two `target_group` literals (`Hero.gd:1587`,
`1603`), the per-class Q spectacles (`Hero.gd:1645-1696`), and a new optional
`target_group: StringName = &"enemy"` parameter on `SpellCaster.cast` (`SpellCaster.gd:38-41`)
that it forwards to each spectacle's existing `target_group` var. In `Spell.gd`, replace the
`Net.is_active()` gate (`Spell.gd:67-69`, `157-167`) with a `hostile_group` field the caster sets —
defaulting so the co-op behaviour is unchanged.

- **Game change:** none at defaults. Every existing caster keeps `&"enemy"`.
- **New suite:** `tools/slice6_test_faction.gd` — a hero with `hostile_group = &"hero"` damages a
  second hero and not itself; a default hero damages enemies and not heroes; `SpellCaster.cast`
  forwards the group to a `BeamSpell` / `BlastSpell` / `MeteorSigil`.
- **Regression:** `slice_test_selfdamage.gd`, `slice5_test_classes.gd`, `slice_test_class_q.gd`,
  `slice2_test_rogue.gd`, `slice_test_summon.gd`, `slice3_test_spell_collision.gd`,
  `slice4_test_spells.gd`, `slice_test_coop.gd`, `slice_test_coop_effects.gd`.

### T7 — `BotBrain` v1 on hero bodies. First class-vs-class fight.

A `BotBrain` node that owns a `BotPerception` + `BotIntent` + `BotController`, attaches to a
`Hero.tscn` instance, disables its `Camera2D` (mirroring `Hero._setup_net_role`,
`Hero.gd:2146-2151`), sets `hostile_group`, and runs dodge + naive spacing. Spawn behind a
`VersusArena` toggle so the default arena roster is untouched.

- **Maker verification:** F5 → toggle → watch an Arcanist bot fight a Shadowblade bot.
- **New suite:** `tools/slice6_test_bot_hero.gd` — a bot hero produces non-zero intent, presses
  dash under threat, and never presses `switch_class`.
- **Regression:** `slice3_test_versus.gd`, `slice_test_ringout.gd`, `slice_test_sandbox.gd`.

### T8 — Context steering (Andrew Fray).

16-slot interest/danger rings. Interest: the class's preferred spacing band (Arcanist wants the
caster band ~180–320 px; Brawler wants contact), plus pickups and high ground. Danger: telegraph
regions, projectile lanes, pit edges (`stage_hazard`), the `p_miss`-adjusted crowd. Blend, pick the
best slot, flatten to `move_x` (this is a side-on platformer — vertical intent becomes `jump` /
`blink` / a leap solved by `Enemy.compute_leap_velocity`).

- **New suite:** `tools/slice6_test_bot_steering.gd` — pit slots are always suppressed; the band
  target reverses sign correctly on both sides; two opposing dangers cancel to a lateral escape.

### T9 — Utility (IAUS) ability scorer.

Score every ready slot from `Hero.ability_hud_state()` (`Hero.gd:1759`) plus the signature
(`current_signature()`, `mp`) against considerations: distance-in-band, target count, own HP,
threat pressure, MP fraction, cooldown fraction. Weights live in a `const Dictionary` keyed by
`Hero.HeroClass` — mirroring the existing `Hero.CLASS_CONFIG` idiom (`Hero.gd:155-221`) rather than
inventing a `.tres` Resource, so a new class is a new row and there is no resource churn.

The scorer must respect the targeting taxonomy (from `SpellCaster.gd` + `SpellLibrary.gd`):

- **SELF-CENTERED** (aim irrelevant): `NOVA` — `activate_at(caster_pos)`, aim ignored entirely.
  `void_zone`/Shadow Root — origin is the caster, aim only steers the eruption.
- **AIMED-DIRECTIONAL** (only `aim.normalized()` is used; distance discarded): `BEAM`, `RUSH`,
  `BOULDER`, `WALL`, `ICE_WALL`, `CHAIN`, `MISSILES`, `TETHER`, `FLURRY`.
- **PLACED-AT-A-POINT** (bot must choose real ground coords, clamped to `spell.reach`):
  `DIVINE_RAY`, `METEOR`, `CONVERGENCE`, `PILLAR`, non-shadow `ZONE`, `BLINK_STRIKE`.

Also: `cast_time > 0` routes to the levitating channel (`Hero.gd:927-928`) which is
**interruptible by any landed hit** (`Hero.gd:2029-2032`) — the scorer must add a hard "am I safe
for `cast_time` seconds" consideration before ever picking `zoltraak`, `infernal_lance`,
`judgment`, `colossus_pillar`, `avalanche` or `heavens_verdict`.

- **New suite:** `tools/slice6_test_bot_utility.gd` — scores are deterministic given a blackboard;
  a channelled ult scores ~0 under active threat; a placed spell's chosen point is inside `reach`;
  MP-starved slots score 0.

### T10 — Parry / deflect scorer.

Fold parry into the utility layer as a first-class option rather than a dodge fallback: score it
against incoming parryable projectiles *and* incoming melee/charge (`Hero.gd:2016-2026`), weighted
by the reflect payoff (`REFLECT_DAMAGE_MULT` 1.5, `EnemyProjectile.gd:14`). Add a per-profile
parry-attempt rate so a low tier bot mistimes it.

- **New suite:** `tools/slice6_test_bot_parry.gd`; **regression:** `slice3_test_parry.gd`.

### T11 — `BotProfile` data pass + tuning.

Extract every magic number above (reaction, jitter, `p_miss`, band widths, consideration weights,
i-frame-dash gating) into one `const` table per profile, and expose the active profile through the
`Tuning` autoload (`scripts/combat/TuningConfig.gd`) so the maker can retune live without a
rebuild — matching the existing feel-knob idiom (`Hero._tune`, `Hero.gd:339-344`).

---

## 6. Risk register

| Risk | Mitigation |
|---|---|
| T5 touches the hottest function in the game (`Hero._physics_process`) and 17 suites | Null-controller default is a literal identity transform; land T5 as one mechanical commit with no logic changes mixed in |
| Hitstop (`Engine.time_scale = 0.05`) silently super-charges bot reflexes | Tick the perception clock on scaled `delta`; assert it in `slice6_test_bot_perception.gd` |
| A bot pressing `switch_class` writes through to `GameState.selected_class` (`Hero.gd:890-894`) and corrupts the player's pick | `BotController` hard-returns `false` for the four cosmetic/class actions; asserted in `slice6_test_bot_hero.gd` |
| Bots that never whiff are not fun | `p_miss` per profile, rolled once per threat at reveal |
| Boss spectacles stay invisible to perception | Documented scope cut; only `slam` (real `Telegraph` via `BlastSpell`) is perceivable in v1 |
| Suites named outside the `slice*` glob get silently skipped | Name every new suite `slice6_test_*.gd`; run `test_class_attacks.gd` explicitly during T5/T6 regression |
| Co-op regression from the faction seam | Every existing caster keeps the `&"enemy"` default; `slice_test_coop.gd` + `slice_test_coop_effects.gd` in T6's regression list |

---

## 7. Summary of changes to the original proposal

| # | Proposal said | Correction |
|---|---|---|
| 1 | Input seam makes any class bot-playable | It makes any class bot-*drivable*. A **faction seam** (T6) is a hard prerequisite before a hero-bot can damage or be damaged in SP |
| 2 | Build order: seam → dodge → steering → utility | **Dodge first, on the existing `Enemy` bodies** (T1–T4). Zero seam, zero faction work, felt win two tasks earlier. Write it body-agnostic so reuse is free |
| 3 | (implicit) bots press virtual buttons | Must be **per-instance**; global `Input.action_press` (the `TouchControls` mechanism) cannot support more than one agent |
| 4 | Bots read telegraphs | Telegraphs are **in no group and have no public geometry** — one-task fix (T2), which also unlocks `BlastSpell` windups for free |
| 5 | Reaction delay applied at perception | Apply it at **first sighting per threat**, then track live. Always-stale perception reads as drunk, not human |
| 6 | Difficulty = reaction time, not damage buffs | Correct, and half-built already (`Enemy.DIFFICULTY.evade_cd`). Add a **whiff rate** too — reaction time alone yields a bot that never misses a dodge |
| 7 | Weights are data, not code | Agreed; use a `const Dictionary` keyed by `HeroClass` (the `Hero.CLASS_CONFIG` idiom), not a new `.tres` Resource |
| 8 | (unstated) which rig bots target | **`scripts/combat/Hero.gd` + `Enemy.gd`.** `scripts/spike/SpikeFigure.gd` is an explicitly throwaway spike with its own physics and no class system |
| 9 | GOAP rejected; no BT addon | Confirmed by the code — 0.35–0.9 s windups with per-windup re-targeting invalidate any longer plan |
