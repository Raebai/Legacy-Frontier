# Clip readability, and the destructible Smash-style stage

**Date:** 2026-09-02 · **Branch:** `bot-fight-quality` · **Status:** phase 1 shipped and
measured, phases 2-3 specified.

Maker's ask, verbatim: *"maybe have the narration and the text over but like let the
fight start earlier ... fully work on the destructible map ... make it entirely
destructible similar to a super smash bros map and maybe the way we show the fight
should be clearer like a single map also the graphics in the video are horrible and not
good quality like the gameplay ... if the camera shows more of the map or follows the
character better or zooms out where it needs to"*.

This spec exists because those are five asks with one root cause between them, and the
evidence for it arrived the same day.

---

## 0. What the numbers said, before anything was changed

TikTok's first retention curves (1 Sep 2026, the first TikTok posts ever made):

```
arcanist_vs_cryomancer   s0 100%  s1 58%  s2 23%  s3 17%  s12 1%   avg 2.0s of 37s
brawler_vs_stormcaller   s0 100%  s1 68%  s2 33%  s3 25%  s12 3%   avg 4.0s of 34s
```

Two independent structural causes, both confirmed in code rather than inferred:

1. **The clip opened on a frozen stage.** `BotMatch._open_intro` called
   `get_tree().paused = true`. Frames pulled from a delivered clip at 0.3 s, 2.0 s and
   3.0 s measured **PSNR 47.6 dB** against each other — a still image. ~80% of viewers
   left before the fight began.
2. **TikTok and Instagram were sent the 1920x1080 landscape file.** Only the YouTube
   entry carried `clip_suffix: ".portrait"`; the guard refusing landscape was written
   for YouTube alone, because only there is the consequence loud.

And a third, which is about the picture rather than the funnel:

3. **The subject is tiny.** `probe_directed_framing ... portrait` measures
   **SUBJECT 4.4% of frame height** — an 84 px figure on a 1080x1920 phone. This is
   what "the graphics are horrible" means. It is *not* fidelity: pulled at 1:1 the
   render is clean, anti-aliased linework.

⚠ **THE PIPELINE BELIEVED IT ALREADY HANDLED (1).** `directed_clip_capture` keeps
`_intro_clip_seconds = 1.2`, `intro_active()` promised *"a hot-gated capture therefore
always starts after the intro, every time"*, and `make_post.VO_AT` was justified by
*"the VS card holds for 1.2 s of clip time"*. All three describe the PNG-sequence path.
The shipped pipeline uses `--write-movie` plus one contiguous `-ss/-t` cut, so the whole
freeze shipped. Three comments, one implementation, and they disagreed.

---

## 1. Phase 1 — SHIPPED (`a894e92`, `d5e0259`)

| change | measured effect |
|---|---|
| 9:16 file to TikTok + Instagram, not just YouTube | letterboxing gone; `VERTICAL_ONLY` now covers all three |
| card no longer pauses the tree; names ride over a live fight | opening frames **47.6 dB → 16.7 dB** (still image → live fight) |
| card dim `0.62 → 0.16` | it was heavy *because* the stage behind it was frozen |
| `PORTRAIT_ZOOM_MIN 1.25 → 2.10`, `MAX 2.40 → 3.40` | subject **4.4% → 6.1%**, but offscreen **10.7% → 40.2%** |
| `_recentre_if_the_pair_fits` (new) | offscreen **40.2% → 4.1%**, off-centre **138.6 → 42.7**, subject holds at 5.9-6.0% |
| encode: last-mile `crf 21 → 17`, colour range pinned at gen 1, lanczos on two filters | the delivered 9:16 file was a FOURTH lossy generation and the cheapest pass of the four |

**The framing lesson worth keeping:** raising the zoom floor alone made the clip *worse*
— it threw a fighter out of frame on 40-65% of samples. Mean separation was only ~135
world px against a ~287 px visible width, so the **leans** were doing that, not the zoom.
Portrait skipped `_relieve_the_lean` on every frame; that rule is correct only when the
pair is too far apart to contain, where the midpoint is empty air between them.
`_recentre_if_the_pair_fits` applies the test that was actually meant — containment, not
legibility — and the shot came out bigger, better centred, and losing a fighter *less*
often than before the change.

---

## 2. Phase 2 — clarity. Decisions, with the reason each is cheap

### 2.1 ONE stage, always the same — `stage_layout = 0`

`VersusArena.STAGE_TERRACES` holds **three** terrain layouts and `_layout_index()` rolls
one per bout (`stage_layout = -1` rolls; `>= 0` pins). Ten biomes repaint on top. So no
two clips share a stage and a viewer never learns the map.

Pinning to variant 0 — the broad fight floor, a left mound, a staircase to a right bluff
— plus the three `BREAKABLE_PLATFORMS` (`600,627` / `840,711` / `1050,627`) *is* already
a Smash-shaped stage: one main platform with floating platforms over it.

**It also divides the destructible work by three**, because destruction only has to be
correct, reachable and good-looking on one silhouette.

⚠ This is a one-line default change and a one-line revert. Variety returns by setting
`stage_layout = -1`.

### 2.2 Length — 12-18 s

At second 12 the two measured clips retain 1% and 3%; completion is 0% and 1.5%. Two
thirds of every clip is rendered and watched by almost nobody.

Two routes, and the cheap one first:

- **Lower `--hp`** so the bout genuinely ENDS in ~15 s. A complete arc that finishes on a
  KO loops, and loops are the strongest distribution signal there is. Risk: a shorter
  fight has fewer lead changes, so more takes fail the FightScore gate.
  **Pick the number with `tools/botmatch_sim.gd`, not by shooting** — it reports duration
  and score per bout for free.
- **Highlight-window selection** on the existing 32 s capture. More faithful, but needs a
  new selection step.

### 2.3 Still open, in priority order

- **Vertical HUD.** Health bars span the full width and the `0:34` match clock is pure
  noise to a viewer; it reads as a screen recording.
- **VFX density.** A frame pulled mid-ult had the two actual fighters nearly impossible
  to find under overlapping purple swirls, cyan lines, orange shards and a screen-filling
  void circle. The maker's own earlier ruling — *"too much going on"* — is the same note.
- **Character contrast.** The fighters share a colour family with the background shards.
  A rim/outline would separate them from any backdrop.
- **Dead frame area.** With the ground anchored at `PORTRAIT_GROUND_AT = 0.72`, the bottom
  ~27% of a vertical frame is solid rock and the top ~25% is empty sky.

---

## 3. Phase 3 — the destructible stage

Design spec: `docs/superpowers/specs/2026-08-19-destructible-map-design.md`. Slice 0
(measure reach) is done; Slices 1-5 unbuilt. **The maker has now overridden the pause**
("fully work on the destructible map ... make it entirely destructible").

### 3.1 What already exists and should be reused

| file | what it gives |
|---|---|
| `DestructibleTerrain.gd` (545 ln) | cell-grid knockout, per-hit cluster scoring, `BreakawayPart` falling bodies |
| `DestructibleFloor.gd` (142 ln) | per-segment bodies that open a REAL hole; the 2 px seam-overlap trick |
| `BreakablePlatform.gd` (202 ln) | break → debris → regen, host-authoritative |
| `ArenaTerrain.gd` (143 ln) | the strata look to preserve |
| the damage contract | group `"destructible"` + `take_damage`/`damage_at`, already called from **33 files** |

The damage arm needs **no new code**. What is genuinely new is the greedy-merge of a
chunk grid into few rectangles, the dirty-row incremental rebuild, and the co-op diff.

### 3.2 The binding numbers

```
chunk 16 px · 2,584 chunks over the shipped stage · jump apex 105.3 px
flat-gap reach:  Juggernaut 97.1 px = 6.1 chunks   <- the binding constraint
                 Arcanist 127.0 · Brawler 132.5 · Swordsaint 139.7 · Stormcaller 147.6
```

A hole ≤6 chunks (96 px) is crossable by everyone; 7 strands the Juggernaut; 10 (160 px)
strands the roster.

### 3.3 Slice order, and why this one first

1. **Slice 1 — grid + greedy merge, ZERO damage.** The risk gate. `DestructibleTerrain`'s
   cell logic scaling from a 64 px block to ~1360 px of fight floor is unproven, and the
   merge algorithm has no prior art in this repo. Acceptance: a fighter walks the stage
   *identically* to today, and no seam snags.
   ⚠ Merged rectangles MUST keep `DestructibleFloor`'s seam-overlap discipline — a
   `CharacterBody2D` running across abutting colliders snags on the joins.
2. **Slice 2 — damage opens holes**, fight floor only.
3. **Slice 3 — the floor is tougher than the furniture.**
4. **Slice 4 — bots cross gaps.** ⚠ `BotBrain._safest()` returns "nowhere good" and the
   caller **holds rather than reverses**, so a melee bot stranded by a severed stage
   stands at the lip doing nothing. Settle this before Slice 4, not inside it.
5. **Slice 5 — co-op diff replication.** Last, and only once solo is boring.

### 3.4 Traps to carry in

- **Two caps, never one.** Chunks-removed-per-hit is forbidden to cap (maker ruling);
  cosmetic debris COUNT must be capped separately, or one wide AoE spawns hundreds of
  `RigidBody2D`s in a frame and "too much going on" gets worse.
- **A fresh hole is a third ring-out vector.** Today ring-out is only the two
  `BLAST_ZONES` off the far L/R edges, and everything under the terrain is solid by
  design. Nothing detects "fell through a hole that did not exist a second ago".
- **Do not copy `FloorGen`'s reachability budget.** It runs on dead constants
  (`JUMP_VELOCITY 580` / `GRAVITY 1500`) against live tuning (740 / 2600), so it already
  certifies unreachable surfaces as reachable. Derive from `TuningConfig`.
- **A body that falls through a real hole must be distinguishable from a body that fell
  off the harness's bounds**, or the sim reports holes as floor bugs — the
  `body_off_test_slab` lesson.

---

## 4. How to check any of this

```
python python-tools/run_all_tests.py --jobs 3                     # 176 suites
godot --headless --path godot-project --script tools/probe_directed_framing.gd -- 3 6
godot --headless --path godot-project --script tools/probe_directed_framing.gd -- 3 6 portrait
```

The portrait argument is new, and it matters: measuring only 1366x768 measured a frame
no viewer sees — the same mistake that made `probe_showcase_framing` describe a camera
path the bot fight does not use.
