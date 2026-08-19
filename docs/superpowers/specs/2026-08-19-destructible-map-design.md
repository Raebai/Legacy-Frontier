# Destructible map — design spec

**Date:** 2026-08-19 · **Branch:** `bot-fight-quality` · **Status:** SPEC ONLY, no code written.

Queue item 9. The house rule is that a change this size gets a written spec before any
code (see `project_v2_tower_redesign`), and this is that document. It is written to be
executable: every number below either carries its provenance or is explicitly marked as
"must be measured first".

---

## 1. What the maker has already locked

Four decisions, taken before this spec and not reopened here:

1. **Chunks break off and FALL.** Stick Fight's ice, not Worms' carving. A hit does not
   erase pixels — it detaches a cluster and gravity takes it.
2. **Everything is breakable, INCLUDING the floor** — but the floor is much tougher.
3. **Host-authoritative co-op FROM THE START.** Not retrofitted.
4. **Bots are TAUGHT to cross gaps.** Not walled off from them.

And one ruling, 2026-08-19, on being told a hole 8 chunks wide cannot be crossed by the
human either:

> **"if that happens then it happens it will be a projectile based ending"**

**So an uncrossable gap is an ACCEPTED OUTCOME, not a bug.** Concretely this forbids two
tempting safety rails: do **not** cap chunks-removed-per-hit to preserve crossability, and
do **not** add a structural "the stage may never be severed" invariant. A severed stage is
a ranged duel and that is a legitimate way for a fight to end.

---

## 2. The numbers, and how much to trust each one

| Quantity | Value | Provenance | Trust |
|---|---|---|---|
| Chunk size | 16 px | chosen | design input |
| Chunks over the shipped stage | **2,584** | re-derived 2026-08-19 from live `STAGE_TERRACES[0]` + `BREAKABLE_PLATFORMS` | recomputed, see note |
| Jump apex | **105.3 px** | `740² / (2·2600)` from `TuningConfig` | derived from live constants |
| Run speed | **210 px/s** | `Hero.SPEED` | read from code |
| Airtime, full arc | **0.569 s** | `2·740/2600` | derived |
| **Flat-gap reach — Juggernaut** | **97.1 px = 6.1 chunks** | MEASURED 2026-08-19 | **binding constraint** |
| Flat-gap reach — Arcanist | 127.0 px = 7.9 chunks | MEASURED | |
| Flat-gap reach — Brawler | 132.5 px = 8.3 chunks | MEASURED | |
| Flat-gap reach — Swordsaint | 139.7 px = 8.7 chunks | MEASURED | |
| Flat-gap reach — Stormcaller | 147.6 px = 9.2 chunks | MEASURED | |
| Measured apex / airtime | 111.5 px / 0.567 s | MEASURED | vs 105.3 / 0.569 derived |
| Rising-jump forward reach | **~83.6 px** | `VersusArena.gd:194`, already relied on by shipped geometry | in-repo, load-bearing |
| Ground dash | ~112 px | earlier research | **unverified here** |

**⚠ Two corrections to the earlier research note, recorded so nobody re-derives the wrong
thing.** The note said "2,155 chunks, the stage is only 27.6% solid". Recomputing against
the actual shipped terrace and platform tables gives **2,584 chunks at 59.3% solid**. The
difference is a denominator disagreement — 27.6% is solid-over-full-playfield-including-sky,
59.3% is solid-over-the-terrain-bounding-box (highest surface down to collider bottom).
Both can be true; the chunk COUNT is the one that sizes the data structure, so use 2,584.

**✅ SLICE 0 IS DONE. THE REACH IS MEASURED, AND IT CORRECTS THIS SPEC.**
`tools/probe_gap_reach.gd` drives a real `Hero` through the real `controller` seam
across a purpose-built flat bench and reports the widest flat gap each class clears.
Two independent controls run first (a plain run must move the body; a held jump must
leave the ground) so a zero can never be mistaken for a finding.

**The planning number was 119.5 px and the truth is a RANGE of 97–148 px**, because the
reach is a function of run speed and the classes do not share one. The number that
governs the design is therefore **the Juggernaut's 97.1 px — 6 chunks, not 7.5.**

⚠ **This changes the rule.** The old text below said "seven chunks (112 px) is the last
crossable width". That is true for four classes and FALSE for the Juggernaut, which
cannot cross seven. The honest statement is: **a hole 6 chunks wide (96 px) is crossable
by everyone; 7 strands the Juggernaut; 9+ (144 px) strands everyone but the Stormcaller;
10 (160 px) strands the whole roster.**

⚠ **SEVEN FAULTS WERE FIXED TO GET THIS NUMBER**, all recorded in the probe's own header
so nobody pays for them twice. The two that would bite anyone writing a similar harness:
the jump must be HELD (`Hero` has variable jump height and halves upward velocity on
release — a one-frame press measures a third of the arc), and the takeoff height must be
sampled AT THE LIP (a run-up that starts on the left mound measures a surface 80 px above
where the jump actually happens). The last two faults were measurement-side: the stage's
own platforms make a "flat gap" unmeasurable, hence the bench; and landing must be
detected by `is_on_floor()`, because depenetration leaves the body a fraction of a pixel
higher than it took off from and a height comparison never fires.

**⚠ And `FloorGen`'s reachability budget is calibrated to DEAD CONSTANTS.** It derives its
gaps from "JUMP_VELOCITY 580 against GRAVITY 1500" while `TuningConfig` overrides both at
runtime (740 / 2600). `GAP_UP_MAX` is 110 against an actual ~83.6 px rising reach and
`GAP_FLAT_MAX` is 170 against ~119.5. So `can_step` certifies surfaces as connected that
nobody can reach, and `_prune_stranded` trusts the same wrong numbers. **This already
affects human players and is a separate blast radius from this feature** — but any code here
that asks "is this still crossable" must not reuse those constants. (This session's new
`slice_test_stage_variants.breakable_platforms_are_climbable` deliberately derives its own
budget from live tuning for exactly this reason; copy that approach.)

---

## 3. Architecture

### 3.1 One body, greedy-merged rectangles, dirty-row rebuild

The terrain is **ONE `StaticBody2D`** whose collision is a set of rectangle shapes produced
by greedy-merging the intact chunk grid — not one body per chunk, and not a `TileMapLayer`.

- **Not one body per chunk.** 2,584 bodies is both a physics cost and, worse, a *seam*
  problem: a `CharacterBody2D` running across abutting colliders snags on the joins. The
  shipped `DestructibleFloor` already documents this ("segments overlap horizontally + grow
  down so a running CharacterBody2D never snags on the seam between them").
- **Not `TileMapLayer`.** Known `set_cell` cost cliff when rewriting many cells per frame.
- **Greedy merge**: per row, run-length the intact spans into rectangles, then extend each
  rectangle downward while the rows below have an identical span. Typical output is tens of
  rectangles, not thousands.
- **Dirty rows only.** A hit marks the rows it touched; only those are re-merged and only the
  affected shapes replaced. A full rebuild is the fallback, not the path.

### 3.2 What already exists and should be reused, not rewritten

The codebase already has most of the vocabulary:

| Existing | Lines | What it gives this feature |
|---|---|---|
| `DestructibleTerrain.gd` | 545 | **The closest prior art** — already models a block face as a GRID OF CELLS, knocks clusters out per hit, launches each as a real falling `RigidBody2D` chunk, and redraws from the intact cells. Decision #1, already built at block scale. |
| `DebrisChunk.gd` | — | the falling-chunk body itself |
| `DestructibleFloor.gd` | 142 | independent segments that open a REAL passable hole; the seam-overlap trick |
| `BreakablePlatform.gd` | 202 | break → debris → regenerate state machine, amber rim affordance |
| `ArenaTerrain.gd` | 143 | the layered strata look the rebuilt terrain must keep |

**The honest framing: this is mostly a SCALE-UP of `DestructibleTerrain` from one block to
the whole stage, plus a collision-rebuild strategy it does not need at block size.** Read it
first. If its cell-grid generalises, this is a much smaller feature than it looks.

### 3.3 Damage routing

Keep the shipped contract: group `destructible`, `take_damage` / `damage_at`. Every existing
consumer already speaks it, so spells need no new arm.

### 3.4 Co-op (decision #3)

**The host owns the grid.** Clients never author destruction locally.

- Host applies damage, computes removed chunks, and replicates a compact **diff** —
  run-length spans per dirty row, not a bitmap of 2,584 cells.
- Clients rebuild their own collision from the diff and spawn their own cosmetic debris.
  Debris is never replicated; it is decoration and a client can roll its own.
- Late join / desync: a full grid snapshot as RLE. At 2,584 cells that is small.
- ⚠ This mirrors the enemy model already shipped (host-authoritative spawner + synchronizer,
  see `project_v2_coop_milestone`), so reuse that seam rather than invent one.

---

## 4. The unresolved question — melee across a severed stage

**This is the one thing the maker has not ruled on, and it should be settled before slice 4.**

Three classes are melee-primary: the **Brawler** (its card explicitly reads "pure-melee
knockout — no magic"), the **Juggernaut** and the **Swordsaint**. Across an uncrossable gap
they have no answer at all. Worse for the showcase the maker actually watches,
`BotBrain._safest`'s hazard veto **HOLDS rather than reverses** — so a melee bot will stand
at the lip doing nothing until the clock runs out. A stalled bot fight is the failure mode
most visible to the maker, because Watch Bots is what they look at.

Options, and what each costs:

1. **Give the melee classes a gap-closer that reaches.** The Brawler already has an air jump;
   the Swordsaint has Crescent Rush; the Juggernaut has nothing. Cheapest for feel, but it
   partly un-rules the ruling — the gap stops being decisive.
2. **Let the clock settle it on health bars.** Zero new mechanics, and it makes "sever the
   stage while ahead" a legitimate winning strategy. Risks reading as a stalemate.
3. **Accept the stall.** Honest to the ruling, worst to watch.
4. *(new, from this session)* **Teach the veto to reverse.** Decision #4 says bots get taught
   to cross gaps; the same rung could teach a melee bot with no crossing available to commit
   to a *ranged* option rather than hold. Most work, best showcase.

**Recommendation: 2 + 4.** The clock decides, and the bot stops looking broken while it
waits. Neither weakens the ruling. But this is a design call and it is the maker's.

---

## 5. Build order — six slices

Each slice is independently verifiable and independently revertable.

> **⚠ STATUS 2026-08-19 (evening): PAUSED BEFORE SLICE 1, DELIBERATELY.** The maker,
> mid-playtest: *"there is like too much going on all the time so we need to fix that"*.
> A destructible map ADDS events to a fight that is already too busy, so building it now
> would push hardest in the wrong direction. It resumes after the density pass.
>
> **Slice 0 was attempted twice and still has no number.** Three real faults were found
> and fixed along the way, recorded here so the next attempt does not repeat them:
> 1. `Input.action_press` does not drive a `Hero` — it reads `Input` only when its
>    `controller` is null. Install a scripted controller on the `controller` seam.
> 2. That controller MUST implement `tick(body, clock)`; `Hero._physics_process` calls
>    it at the top of the step and a missing method aborts the whole physics tick.
> 3. `tick` must NOT age the just-pressed edge — it runs before the hero polls
>    anything, so copying held-into-prev there makes `just_pressed` compare a set with
>    itself and `_just(&"jump")` is never true.
>
> With all three fixed the CONTROL passes (holding `move_right` moves the body 122.7 px
> in 40 ticks, i.e. ~205 px/s against `Hero.SPEED` 210) and the jump measurement still
> reports 0.0 px for all five classes. Untested suspicion for next time: the settle loop
> is 10 ticks while a 80 px drop takes ~15, so the body may not be `is_on_floor()` when
> the jump is pressed. **Do not trust the derived 119.5 px until this reads a number.**

- **Slice 0 — MEASURE THE REACH. ✅ DONE** (`tools/probe_gap_reach.gd`). Build a probe that genuinely drives a `Hero` across a
  parameterised gap and binary-searches the widest crossable width, per class, for a flat
  jump, a rising jump and a ground dash. ⚠ The 2026-08-19 attempt failed by driving input the
  body does not read; drive the same seam `BotController` uses instead. **Nothing after this
  slice should use a derived number.** Output: three constants, pinned by a test.
- **Slice 1 — The grid, offline.** Chunk grid over the existing terrain, greedy-merge to
  rectangles, rebuild one `StaticBody2D`. No damage yet. Verify: merged collision is
  equivalent to the current terraces (a fighter walks the stage identically), and a dirty-row
  rebuild is inside budget.
- **Slice 2 — Damage → holes.** Wire `take_damage`/`damage_at`, remove chunk clusters, spawn
  falling `DebrisChunk`s. Reuse `DestructibleTerrain`'s cluster logic. Verify: a hole is
  really passable, and the stage still renders as `ArenaTerrain` strata rather than a
  checkerboard.
- **Slice 3 — The floor, tougher.** Decision #2. One hp multiplier on floor rows; confirm chip
  damage never opens the ground and a real blow does.
- **Slice 4 — Bots cross gaps.** Decision #4. Publish gap geometry into the blackboard and add
  the crossing rung. ⚠ Settle §4 first. ⚠ `BotBrain`'s own warning applies: a wrong readiness
  gate "would show up in play as a bot dashing four times a second". The `_reach_upward` rung
  added 2026-08-19 is the shape to copy — guarded on all four sides and spaced.
- **Slice 5 — Co-op.** Host-authoritative diff replication + RLE snapshot on join. Verify on
  loopback first, then two machines.

---

## 6. Risks

1. **Collision rebuild cost per frame.** Mitigation is dirty-rows-only; the risk is a spell
   that damages many rows at once (a Fault Line along the ground). Budget max rows per frame
   and spread the rest — but ⚠ **log what was deferred.** Silent truncation reads as "it all
   rebuilt" when it did not.
2. **`DestructibleTerrain` may not generalise**, and slice 1 discovers it. Acceptable: slice 1
   is exactly where that is cheap to learn.
3. **Debris count.** 2,584 potential chunks; a big hit must cap *spawned debris* (cosmetic)
   without capping *removed chunks* (the ruling forbids that). Two different caps — do not
   conflate them.
4. **The dead-constants trap** (§2) reappearing in any new reachability code.
5. **The stage look.** `ArenaTerrain` draws cohesive strata from terrace rects. Driving it from
   an arbitrary chunk silhouette is a real art problem, not a mechanical one.

---

## 7. Not in scope

Tower floors (this is the versus stage first), destructible ceilings/overhangs, terrain that
regenerates (`BreakablePlatform` owns that and stays as it is), and any change to `FloorGen`'s
dead-constant budget — a real bug with its own blast radius that wants its own fix, not a
rider on this one.
