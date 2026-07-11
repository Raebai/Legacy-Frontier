# Slice 3 — Combat Feel + MMO Layer + World Unification (design)

**Date:** 2026-07-11 · **Branch:** `v2.0-tower` · **Driver:** maker playtest feedback on the Slice 2 loop.

This spec turns a batch of playtest feedback into a sequenced build. Approved direction (maker, 2026-07-11): aim-to-cursor with soft assist; ground the floaty look; combat-feel first; "get this ALL done" (full scope, all three waves, parry included).

## North star

Make the moment-to-moment fighting feel like **Stick Fight** — twin-stick aiming, punches that shove, a clean "ding" on a good hit, a perfectly-timed parry that *reverses* a spell — while keeping the mobile-first pillar intact (every aim maps to a touch aim-stick later; soft assist keeps it forgiving, never pixel-perfect).

## The three waves

| Wave | Theme | Ships |
|---|---|---|
| **1 — Combat feel** | how it plays every second | twin-stick aim-to-cursor + soft assist · cast pose thrusts at cursor · camera calm · portal fix · Stick-Fight juice+audio |
| **2 — MMO combat layer** | depth + readability | ability/cooldown hotbar HUD · perfect-timing parry-reflect (+ding) · enemy abilities |
| **3 — World & visuals** | it looks the part | hub squares → stickmen + real rooms · environment/floors (grounded read) · flight-as-ability · better portals |

Each wave is headless-verified + atomic-committed. Feel-tuning needs the maker's F5 (Gopeak can't render feel); a GO/NO-GO checklist ships per wave.

---

## Wave 1 — Combat feel

### 1A. Twin-stick aiming (the core change)

Today `Hero.facing` is set from movement input and every attack auto-locks the nearest enemy (`Targeting.aim_direction` / `Targeting.nearest`). Replace that with **two independent vectors**:

- **`_aim_dir`** — from the cursor. `(_aim_source() - global_position).normalized()`. `_aim_source()` returns `get_global_mouse_position()` on desktop; isolated in one method so a mobile aim-stick swaps in later without touching call sites. Drives: cast bolt, blast target, melee arc, and the cast **pose**.
- **`_move_dir`** — last non-zero `Input.get_vector(move_*)`. Drives: **dash** and **blink** direction. Movement is free of aim (strafe): run one way while casting another.

**Soft assist** — new `Targeting.assisted_aim(origin, raw_aim, enemies, cone_dot, range, bend) -> Vector2`. If an enemy lies within the cone (dot(raw_aim, toward) >= `cone_dot`, default cos(18°)≈0.95) and within `range` (default 420), bend `raw_aim` toward the nearest such enemy by `bend` (default 0.6, i.e. 60% of the way; effectively a snap when already near-aligned). No enemy in cone → return `raw_aim` unchanged. Pure function, headless-testable.

**Cast pose** — `CharacterRig` gains `set_aim(dir)`. The body still mirrors left/right via `set_facing` (upright — never rotate the figure upside-down). During `CAST`, the lead arm/staff angle is driven toward `dir` (in the mirrored local frame) so the staff visibly points at the cursor. Locomotion states ignore aim.

Files: `Hero.gd` (vector split, all attack call sites, rig aim), `Targeting.gd` (`assisted_aim`), `CharacterRig.gd` (`set_aim`). No new input actions (mouse position is read directly).

Decision (approved): **dash/blink follow movement, attacks follow the cursor.** Reversible/tunable if playtest dislikes it.

### 1B. Camera calm

The "shake when I move" is camera **lookahead**: 22px drift toward facing at 2.2× zoom. Reduce `LOOKAHEAD_DIST` to ~8 and ease it; base lookahead on `_aim_dir` (a gentle peek toward the cursor) rather than movement so changing direction doesn't lurch. Drop per-cast shake (`Juice.shake_camera(2.0)` in `_cast`) to ~1.0 or remove. **Expose `lookahead_dist` + a `shake_scale` multiplier as live `Tuning` knobs** (`TuningConfig` + `data/tuning.tres`) so the maker dials to taste in-game.

Files: `CombatCamera.gd`, `TuningConfig.gd`, `data/tuning.tres`, `Hero.gd` (cast shake).

### 1C. Portal fix

`ExitPortal` only connects `body_entered` and arms 0.35s late — if the body already overlaps when it arms, or brushes the edge, it never fires. Fix: once `_armed`, **poll `get_overlapping_bodies()` each `_process` frame** for a body in `trigger_group`; emit `taken` once, guarded by a `_taken` flag so it can't double-fire. Keep the arm delay (prevents spawn-on-hero instant trigger). Fixes hub tower-entrance and arena floor-exit together.

Files: `ExitPortal.gd`.

### 1D. Stick-Fight juice + audio

- **Punch shove** — melee already applies decaying knockback (`Enemy.apply_knockback`); make it *read*: slightly higher melee knockback, a target flash on connect, keep the directional camera kick. Tunable.
- **"Ding"** — bright one-shot on a clean melee connect (and reused for the Wave-2 parry). New `Sfx` key `ding`.
- **Footsteps** — a footstep tick while in `RUN` (cadence synced to the run cycle; snappier for rogue). New `Sfx` key `footstep`, pitch-varied.
- **Flow** — add light movement acceleration/friction (currently velocity snaps to `dir*speed`) for weight. Small, tunable (`move_accel` knob).
- **Audio assets** — synthesize `ding.wav` + `footstep.wav` with a Python stdlib generator (`python-tools/generate_placeholder_sfx.py`, mirroring `generate_placeholder_atlas.py`): ding = decaying bright sine/partial stack; footstep = short filtered-noise thump. Godot imports `.wav` natively.

Files: `python-tools/generate_placeholder_sfx.py` (new), `assets/audio/sfx/{ding,footstep}.wav` (generated), `Sfx.gd`, `Hero.gd` (footstep tick + ding on connect + accel/friction).

### Wave 1 tests

`tools/slice3_test_aiming.gd` — `assisted_aim`: no-enemy passthrough, in-cone bend, out-of-cone/out-of-range no bend, zero-vector safety. Plus a portal-overlap unit check where feasible. Existing 15 suites must stay green.

---

## Wave 2 — MMO combat layer (outline; detailed spec later)

- **Ability/cooldown hotbar** — bottom-center HUD row, MMO-style: one slot per class ability (cast/dash/blast/blink/nova or the rogue set), each showing key, icon-ish glyph, and a radial/fill cooldown sweep reading the timers Hero already tracks. New `AbilityBar` Control + a small read-only cooldown query on Hero. Anchor-based (mobile-first).
- **Perfect-timing parry-reflect** — class-gated defensive ability on a key. Opens a short parry window (~0.15s). An enemy projectile (`EnemyProjectile`) or a reflectable spell entering the hero during the window is **reversed**: velocity flips toward the sender, ownership flips to "hero-reflected" so it damages enemies, and the "ding" + a flash fire. Outside the window → normal damage. Which class parries (rogue duelist vs a new/blade mechanic) is a Wave-2 design question.
- **Enemy abilities** — expand archetypes with real abilities (e.g. summoner adds spawns, caster gains a second shot pattern, a shielder, a healer), reusing `Telegraph`/`EnemyProjectile`. Keep tells fair (dodge-the-tell pillar).

## Wave 3 — World & visuals (outline; detailed spec later)

- **Hub → stickmen** — hub `Player` + NPC visuals move from `ColorRect` to `CharacterRig` (the combat rig), unifying the aesthetic. NPC speech/chat unchanged.
- **Environment + grounded read** — real floor/wall/prop art (or richer procedural tiles) in hub and arena; a soft drop shadow under each figure so they read as standing on the floor, not hovering.
- **Flight-as-ability** — a levitate ability (default grounded) that lifts the figure (shadow shrinks/offsets, cross ground-hazards); no free-fly default.
- **Better portals** — upgrade the primitive-ring portals (layered shader-ish draw, particles, inward pull) for both hub and arena.

---

## Constraints / conventions (carried from prior slices)

- **Sequential Godot only** — parallel agents corrupt the `.godot` cache + git index. Fable subagents author isolated, non-overlapping pieces (read-only, no Godot/git); the main thread integrates sequentially, headless-verifies, commits atomically.
- **Class-cache trap** — run `--headless --import` before any run that consumes a new `class_name`.
- **Atomic commits** — one logical change per commit, message describes the why.
- **Headless verify each task** — tests green + clean boot before commit; feel is the maker's F5.
- **Mobile-first pillar preserved** — aim is directional (maps to aim-stick), soft assist keeps it forgiving; the hotbar is anchor-scaled.

## Non-goals (this slice)

- Real animated sprites (procedural rigs stay; asset-gen pipeline is later).
- Networked co-op.
- HP carrying hub↔run.
- Persistent-climb spine (that's the parked floors step 5 — separate track).

## Wave 3 REFRAMED (2026-07-11) — Versus Arena (the near-term focus)

Maker redirected the near-term focus mid-Slice-3 to a **Smash / Brawlhalla / Stick-Fight-style versus arena** as the testbed for all the new combat. Explicitly NOT a pivot — a continuation: the game already renders side-on (upright stick figures) with top-down-style free movement, and that view/movement does NOT change. All versus features are ADDITIVE on the existing engine. NO literal gravity/jumping/side-view-blast-zone rebuild (deferred unless maker asks) — "knocked off the edge" is delivered via pit/edge ring-out + slope-slide instead, which reuses everything and stays mobile-first.

Versus additions (build order):
1. **Destructible map** — spells + blasts + hard hits crater/break the stage. Requires Spell/BlastSpell/Nova to damage the "destructible" group (currently only melee/dash do). New `DestructibleTerrain` (StaticBody2D cover/terrain, multi-hit, shatters to open the space).
2. **Ring-out** — pit/edge zones: a fighter knocked into / walking off = lose a stock; slope zones slide fighters toward the drop. Stocks/respawn manager. New `StageHazard` (pit + slope).
3. **Impact juice** — dust puff on landing (flight/dash-stop), floor crater + dust + extra hitstop when a hard knockback slams a fighter into a wall/floor ("damage where they're sent").
4. **Flight ability** — grounded default; a levitate ability lifts the figure (shadow shrinks), dust on land.
5. **Versus stage + mode** — a Smash/Brawlhalla-like layout (central platform, edges/pits, slopes, destructible cover) with P1 (maker) vs AI bots + stocks; architected so a local gamepad P2 (twin-stick maps perfectly) slots in later.
6. **Mobile** — keep touch/mobile in mind throughout (down the line): anchored HUD, directional aim, no pixel-perfect requirements.
North-star content (LATER, not now): "insane" anime ultimates — divine smite, a long-cast magic-circle bear summon, etc. — built on the existing telegraph→long-cast→screen-filling-payoff pattern once the arena feels good.

## Decisions (to log in v2.0-design.md)

- **D-S3-1** Twin-stick: attacks aim at cursor (soft-assisted), dash/blink follow movement. Reverses the auto-aim pillar but preserves mobile-first via directional aim + assist.
- **D-S3-2** Parry is a *perfect-timing reflect* (reverse the projectile), not a block.
- **D-S3-3** Placeholder SFX (ding/footstep) synthesized via Python stdlib, consistent with the placeholder-atlas approach.
