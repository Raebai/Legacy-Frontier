# RESUME HERE — 2026-08-12, FIXED FROM A LIVE PLAYTEST, NOT RE-PLAYED

**ASHPIRE.** Branch `bot-fight-quality`, **601d135**, **169/169 green**, pushed, clean.

Yesterday's handoff opened by recommending the one mode that was crashing. This one
opens by saying plainly: **everything below is fixed and pushed, and none of it has
been played since it was fixed.**

## ▶ WHAT THE MAKER HIT, IN THE ORDER THEY HIT IT

| symptom | cause | confidence |
|---|---|---|
| Watch Bots crashed instantly | `ArenaTerrain.terraces` typed `Array[Dictionary]`, handed an untyped `Array` | fixed, negative-controlled |
| "they both lag in the box" | **variant 2's shelf spanned x 980–1560 and the right fighter spawns at 1000** — a terrace is 320 px of solid rock BELOW its surface, not a line. ~1 bout in 3 | fixed + pinned by a test |
| crates eaten at the opening | cover authored 54 px from a spawn; the keep-out only ever promised "not overlapping" | `STAGE_COVER` emptied |
| crashed after ONE fight | `_paint_hud` called `get_visible_rect()` on a null viewport — `_process` fires for a frame after the node leaves the tree | fixed, negative-controlled |
| Zanshin "trying to cast a free object" | `for n: Node2D in live` — the TYPED loop variable casts every iteration, and `hurt` inside the loop frees other entries of the same array | fixed |
| boulder "hits the ground and goes nowhere" | `_rise_height()` fired its ceiling probe from a point lying ON the floor, so it reported the floor as the ceiling and the rock never rose | fixed, confident |
| corpse embedded in a wall | corpse keeps driving into a face through the win freeze (`process_mode = ALWAYS`) | ⚠ **reasoned, NOT reproduced** |
| random subtext under "X WINS" | telemetry on the thumbnail frame | removed |
| Cleric too strong | `radiant_volley` 18 → 15/lance, backed by 75/78/81% across three sweeps | done |

**If the corpse embeds again** it is the launch tunnelling a thin platform in a single
step, not pressure against a face — that needs a swept move, not a velocity clamp.

## ⚠ THE LESSON THAT COST THE MOST TODAY

**166/166 was green over a duel stage that had been throwing on every bout for a week.**
Three things hid it and they are the same mistake: the variant suite tested the
AUTHORED table via `get_script_constant_map()`; `slice_test_sandbox` booted the real
scene, hit the error and still printed `all PASS` (a GDScript runtime error is NOT
fatal); and `run_all_tests.py` only ever read each suite's own summary line.

`run_all_tests.py` now **fails any suite that emits a runtime `SCRIPT ERROR`**, scoped
to that and not the broader `ERROR:`. Opt out with an `ALLOWS_SCRIPT_ERRORS` marker.
That single gate immediately caught **four more suites passing vacuously**, one of which
(`slice_test_spell_warm`) had failed to COMPILE and was still reporting all PASS.

**Negative-control every new test.** Twice today a test passed while the thing it
guarded was broken — including one I had just written to catch that very bug.

## ▶ STILL OPEN

* **9:16 is a flag, not a feature.** `bot_clip_capture --vertical=1` renders exact 9:16
  and never letterboxes, but the crop slices the class names, cuts both HP bars off and
  often contains NEITHER fighter — the plates anchor to full width and the bodies stand
  560 px apart. The maker wants landscape AND vertical to post both. Needs a tighter
  `CombatCamera` two-shot plus safe-area-aware plates.
* **The content programme** (researched, not built): a stated question burned over live
  action in frame 1, ONE always-visible meter, event-driven audio, series numbering with
  win/loss records, a bracket. Highest leverage: **sim many bouts, score the ENDING
  SHAPE, publish only the good ones** — `tools/botmatch_sim.gd` already does the sim.
* **~36 cosmetic `is`-before-`is_instance_valid` sites** remain where the operand is a
  fresh group scan. Harmless; every STORED one is fixed.
* **`thousand_cuts` sits above its own stated ceiling** (21.0 dmg/s vs the 19.4 its
  comment cites). Left alone deliberately — retuning off a documentation error is not a
  measurement. Re-price it in the next real sweep.

## ⚠ NEVER DO THIS

**Do not rewrite source files with PowerShell `Get-Content | Set-Content`.** On PS 5.1
it reads UTF-8 as ANSI and writes the damage back with a BOM. It corrupted three files
across three commits, was not losslessly reversible, and needed restoring from git plus
re-applying every edit by hand. It also tripped the maker's antivirus. Use git, an
editor tool, or Python.

Also: **launching the game rewrites tracked files** — `project.godot` loses three keys,
`Main.tscn` loses its comment block. Check `git status` after any launch.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 6      # 169 suites, ~135s
```
