# Task 1.3 (PC half) — the baseline measurement, and it redirects the task

**Date:** 2026-10-18 · **Lane:** QA + Feel · **Where:** PC (measurement) · **Board:** Phase 1, row 1.3

Board row 1.3 is *"profiler pass: count spell spectacle cost at the ceiling, object-pool
every spectacle scene, entity cap on the floor"*, split Cloud (pooling) / PC (measurement).
This is the PC half: the **before** numbers, so the cloud's pooling work has something to
beat. Check column wants *under 8 ms at ceiling*.

**Headline: the ceiling costs ~70 ms of CPU against a 33.3 ms budget, and the thing
costing it is not what the row says it is.**

---

## The numbers

Two independent run-sets, 20 s each, `stress_mobile_entities.gd`. Both sets agree within
6%, so these are replicated, not single reads.

| Condition | CPU total | physics | process | per entity |
|---|---|---|---|---|
| 25 entities, **no casting** | 22.4 / 22.6 ms | 10.0 / 10.5 | 12.3 / 12.3 | 0.89 ms |
| 25 entities, **casting** | 68.6 / 72.7 ms | 56.5 / 60.2 | 12.1 / 12.4 | 2.75 ms |
| **8** entities, **casting** | 69.5 / 71.7 ms | 58.0 / 59.5 | 11.5 / 11.6 | 8.68 ms |

Budget: 33.3 ms at 30 fps, 16.7 at 60. Raw files: `stress_*.txt`, `profile_spectacles.txt`.

## What the numbers say

**1. The crowd is not the cost, so an entity cap buys nothing.** 8 entities and 25
entities with casting on cost the *same* (~70 ms). Tripling the crowd changed nothing
measurable. The row's *"entity cap on the floor"* is aimed at a term that is already flat.
Crowd-only at the full 25 is 22 ms, which fits the 30 fps budget.

**2. Casting adds ~48 ms, and essentially all of it is PHYSICS.** Physics goes 10 ms →
58 ms (5.8x) the moment spells are cast. `process` is flat at ~12 ms in every condition.
So the overage is not the spectacles' own `_process`/`_draw` — it is the physics those
spells put into the world (shapes, areas, overlap queries).

**3. The spectacles' own per-frame cost is already under the Check.**
`profile_spectacles.gd` measures the callbacks directly: *roster mean 625.88 µs/instance,
8 concurrent = 5.01 ms/frame*. That is under the row's 8 ms target **today, before any
pooling.** Pooling the scenes will not move the 48 ms, because the 48 ms is not there.

**4. Where pooling WILL pay is construction.** The `cast µs` column is one-off cost per
cast, and the worst are large:

| Spell | cast µs |
|---|---|
| boulder_hurl | 7,040 |
| rift_dagger | 7,010 |
| shatter | 6,556 |
| fault_line | 5,715 |
| blink_strike | 5,550 |
| thousand_cuts | 5,399 |
| chain_lightning | 5,024 |
| frozen_comet | 4,763 |
| horizon_cut | 4,724 |
| chronostasis | 4,728 |

At the harness's 4 Hz cast rate a 7 ms construction is ~28 ms/s of pure node-building.
**That** is the object-pooling target, and the row is right to call for it — just for the
`cast` column, not the frame column.

**5. `MagicCircle` is 48–55% of all draw cost**, across 44–46 of the 54 spells. It is the
single biggest draw lever in the game, and it is also the signature look, so it wants to be
made *cheap*, never removed. Worst instance 1,383 µs (avalanche).

**6. The spectacle budget is declared but not enforced.** Every casting run reports
`PEAK LIVE SPECTACLES 12 (budget 8)` — 50% over, every time. Particle demand is already
being cut 15% and debris 27% under load, so the work-budget system is engaging while the
spectacle count is not capped.

**7. One outlier worth a look:** `blizzard` (ZoneSpell) `proc` is 71.12 µs — roughly 3x the
next worst (`meteor_storm`, 24.65) and ~40x the roster median. Per-frame, so it multiplies.

## What this means for the row

The measurement does not say 1.3 is wrong; it says **two of its three clauses are aimed
off-target**:

- *object-pool every spectacle scene* — **keep**, retargeted at the `cast` column (the
  4–7 ms constructors above), not at per-frame cost.
- *entity cap on the floor* — **drop or deprioritise**; the crowd term is flat and already
  in budget.
- *count spell spectacle cost at the ceiling* — **done, here.**
- **add:** the real overage is spell PHYSICS (+48 ms). Nothing on the board targets it.
  That is where the 30 fps budget is actually being lost.

## ⚠ What these numbers are not

**Headless = CPU only.** The dummy renderer means the GPU cost — the thing that actually
decides the frame rate on a tile-based mobile GPU — is not in any number here, and cannot
be. Both harnesses say so in their own headers. The draw figures are the cost of *building*
draw commands, not of rasterising them; a cheap spectacle here can still be the most
expensive thing on a phone if it covers the screen. The device answers that, through
`PerfOverlay` (F3, or a three-finger tap), and nothing else substitutes for it.

**No sabotage pass on the pool yet.** The row's Check is *"under 8 ms at ceiling; sabotage:
remove the pool, see it blow"*. There is no pool to remove — that is the Cloud half. When it
lands, the sabotage is: disable it and watch the `cast` column return to the numbers in the
table above.

**Reproduce:**

    godot --headless --path godot-project --script tools/stress_mobile_entities.gd -- ++entities=25 ++casting=1 ++seconds=20
    godot --headless --path godot-project --script tools/profile_spectacles.gd -- ++copies=16 ++iters=300
