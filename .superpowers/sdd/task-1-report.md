# Task 1 report: Strip to the sandbox

## Summary

Repointed boot straight into `VersusArena`, hid the hub Armory station (loft platform
stays), and added 2 stationary grey PRACTICE DUMMIES near `P1_SPAWN` that take hits
from every existing hero attack/spell with zero spell-file edits, never block the
round's win condition, and respawn in place a beat after being knocked out.

## Files changed

- `godot-project/project.godot` — `run/main_scene` repointed from
  `res://scenes/ui/Lobby.tscn` to `res://scenes/combat/VersusArena.tscn`.
  `Lobby.tscn` untouched on disk.
- `godot-project/scripts/World.gd` — `_build_loft()`: the Armory station
  instantiation is now wrapped in `if false:` with a
  `# hidden 2026-07-23 (sandbox focus)` comment. The loft platform + step
  still build (still climbable); only the station itself doesn't spawn.
- `godot-project/scripts/combat/Enemy.gd`:
  - New `@export var passive: bool = false`.
  - New `const PASSIVE_RESPAWN_DELAY: float = 1.0` and
    `var _passive_home: Vector2`.
  - `_ready()`: if `passive`, snapshots `global_position` into `_passive_home`
    (the spawner sets `position` before `add_child`, so this is the intended
    fixed spot).
  - `_physics_process()`: a passive enemy now branches into a new
    `_process_passive(delta)` immediately after the co-op-puppet early return
    — no retarget, no chase, no attack windup. It still takes knockback,
    gravity, wall-slam craters, and normal `take_damage`/`_die` — it just
    never chases or swings.
  - `_die()`: passive branch skips kill-power/run-kill credit and the
    permanent corpse-launch + `queue_free`, instead playing a smaller death
    burst/shake and calling a new `_respawn_passive()`.
  - `_respawn_passive()`: hides the node, disables its `CollisionShape2D`
    (deferred), awaits `PASSIVE_RESPAWN_DELAY`, then (guarded by
    `is_instance_valid(self)`) repositions to `_passive_home`, refills hp,
    re-enables collision/visibility/physics, and plays the same respawn poof
    VFX colors VersusArena uses for ring-out respawns.
- `godot-project/scripts/combat/VersusArena.gd`:
  - New constants: `DUMMY_COUNT = 2`, `DUMMY_X_OFFSETS = [-120.0, 120.0]`,
    `DUMMY_TINT` (neutral grey `0.55/0.55/0.58`), `DUMMY_HP = 9999`,
    `DUMMY_STOCKS = 999999`.
  - `_ready()` now calls `_spawn_dummies()` right after `_spawn_fighters()`.
  - New `_spawn_dummies()`: instantiates `Enemy.tscn` `DUMMY_COUNT` times,
    sets `passive = true`, `max_hp = DUMMY_HP`, `tint = DUMMY_TINT`,
    positions at `P1_SPAWN + offset`, adds to the tree, adds to group
    `"dummy"` (group `"enemy"` comes for free from `Enemy._ready()`), and
    registers each with `_register_fighter(..., DUMMY_STOCKS)` so a stray
    ring-out (unlikely — they sit on solid ground far from any pit) still
    respawns them through the existing fighter-registry path instead of ever
    reaching `_eliminate()`'s permanent `queue_free`.
  - `_register_fighter(body, spawn, stocks: int = STOCKS)` — added an optional
    `stocks` override (default preserves all existing call sites' behavior
    byte-for-byte).
  - `_bots_alive()` — added `and not node.is_in_group("dummy")` to the count
    filter, with a comment explaining why (so dummies can never block "Bots
    left" hitting 0 / the win condition).
- `godot-project/tools/slice3_test_versus.gd` (**not in the brief's file list —
  see "Deviation" below**) — `_test_match_setup` updated to: filter
  `get_nodes_in_group("enemy")` to exclude `"dummy"` before checking
  `BOT_COUNT`; assert `DUMMY_COUNT` dummies exist in group `"dummy"`; assert
  registry size is `BOT_COUNT + DUMMY_COUNT + 1`; skip the "every fighter
  starts with STOCKS stocks" check for dummy registry entries (they
  legitimately carry `DUMMY_STOCKS`).
- `godot-project/tools/slice_test_sandbox.gd` (new) + its `.uid` — headless
  `SceneTree` runner. Loads the packed `VersusArena.tscn` (not just the bare
  script, per the brief — this is now literally what F5 boots), settles 70
  frames (the `arena_wide_capture.gd` idiom), then asserts: >=2 nodes in group
  `"dummy"`, each also in group `"enemy"`, each has `passive == true`, and each
  sits within 250px of `P1_SPAWN`. Prints `sandbox tests: all PASS`.

## Deviation from the brief's file list (and why)

The brief's file list didn't include `tools/slice3_test_versus.gd`, but
"Critical resolution 1" requires dummies to join group `"enemy"` (mandatory —
that's how every existing hero spell/attack finds its targets, and the brief
explicitly forbids touching spell files to special-case this). Group
membership makes `get_nodes_in_group("enemy")` include the 2 dummies
unconditionally, which broke `slice3_test_versus.gd`'s pre-existing hard
assertions (`bots.size() == BOT_COUNT`, `registry.size() == BOT_COUNT + 1`,
"every fighter starts with STOCKS stocks" looped over ALL registry entries).
This was unavoidable given the group-membership requirement, so I updated
that test's assumptions to reflect the new, intentional reality (documented
above) rather than leave the full sweep red. This is exactly the case the
brief's Step 6 anticipated ("If a suite references the win/alive count, make
sure your dummy exclusion doesn't break it").

## Test commands + output

Headless import (script/scene changes, no new `class_name` but ran it anyway
per discipline):
```
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --import
```
-> clean, `[ DONE ]` on `first_scan_filesystem`, `update_scripts_classes`,
`loading_editor_layout`.

New sandbox test:
```
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_sandbox.gd
```
-> `sandbox tests: all PASS`

Full sweep — every `godot-project/tools/slice*_test_*.gd` (38 files, run
individually):
```
for f in godot-project/tools/slice*_test_*.gd; do
  godot-engine/...console.exe --headless --path godot-project --script "tools/$(basename "$f")"
done
```
-> all 38 green, including the fixed `slice3_test_versus.gd`
(`Slice3 versus tests: all PASS`) and the new `slice_test_sandbox.gd`
(`sandbox tests: all PASS`). Full list confirmed: slice0_test_sfx,
slice0_test_targeting, slice1_test_blink, slice1_test_destructible,
slice1_test_elements, slice1_test_enemy_attack, slice1_test_music,
slice1_test_nova, slice1_test_rank, slice1_test_rig, slice1_test_telegraph,
slice1_test_weapon, slice2_test_enemy_archetypes, slice2_test_rogue,
slice2_test_runloop, slice3_test_aiming, slice3_test_destructible_terrain,
slice3_test_enemy_abilities, slice3_test_enemy_sideon, slice3_test_parry,
slice3_test_spell_collision, slice3_test_stage_hazard, slice3_test_versus,
slice4_test_spells, slice5_test_classes, slice_test_boss, slice_test_class_q,
slice_test_climb, slice_test_coop, slice_test_coop_effects, slice_test_debris,
slice_test_floor, slice_test_gear, slice_test_ground_crater,
slice_test_loadout, slice_test_sandbox, slice_test_status, slice_test_summon,
slice_test_touch.

(A benign, pre-existing `ObjectDB instances leaked at exit` / `1 resources
still in use at exit` warning appears on every `SceneTree`-runner test in this
suite — including a baseline run of `slice3_test_versus.gd` before my fix
landed — since none of them free the arena/root nodes before `quit()`. Not
introduced by this task.)

## Self-review

- **Group/counting correctness verified**: dummies join `"enemy"` (via
  `Enemy._ready()`, unconditional) + `"dummy"` (explicit); `_bots_alive()`
  excludes `"dummy"`; confirmed by both the new sandbox test and the fixed
  `slice3_test_versus.gd` passing.
- **No spell files touched** — confirmed via the diff; only `Enemy.gd`,
  `VersusArena.gd`, `World.gd`, `project.godot`, and the two test files
  changed.
- **Figure size/scale untouched** — no changes to `CharacterRig`, no scale/size
  fields touched anywhere in this diff (Task 2's territory, left alone).
- **SP byte-identical for existing bots/hero**: `_register_fighter`'s new
  `stocks` parameter defaults to `STOCKS`, so every pre-existing call site
  (`_p1`, the 5 bots, minion spawns via `_spawn_runtime_enemy` — which
  doesn't call `_register_fighter` at all) is unaffected. `passive` defaults
  to `false`, so no existing `Enemy` instance changes behavior.
- **Ordering fragility noted**: `slice3_test_versus.gd`'s
  `_test_ring_out_respawns_bot` takes `get_nodes_in_group("enemy")[0]` and
  assumes it's a real bot (asserting exactly `STOCKS - 1` after one ring-out,
  which would fail if index 0 were a `DUMMY_STOCKS`-carrying dummy). Verified
  empirically that real bots (added in `_spawn_fighters`, before
  `_spawn_dummies` runs) occupy the earlier group-array slots and the test
  passes, but this is an implicit ordering assumption rather than a
  structural guarantee. Not fixed further since untouched-by-brief and
  currently green; flagging for awareness if `_spawn_dummies()`'s call order
  in `_ready()` ever moves before `_spawn_fighters()`.
- **Respawn-in-place is not covered by an automated headless assertion** — the
  brief permits this ("if that's complex, at minimum ensure dummies exist at
  start; note any limitation"). The mechanism itself (hide, disable collider,
  timer, reposition, refill hp, re-enable) was implemented in full rather than
  stubbed, but exercising it would require either driving `take_damage()` to
  zero HP and asserting post-delay state in a headless runner with a real
  `await`/timer tick, or an in-editor playtest swinging at a dummy until it
  drops and watching it pop back up. Recommend the maker do a quick in-editor
  sanity check (F5 -> hit a grey dummy until its HP bar empties -> confirm it
  reappears ~1s later at the same spot) during the F5 GO/NO-GO pass.
- **Dummy tankiness (`DUMMY_HP = 9999`) is a judgment call**, not specified by
  the brief. Chosen so the dummy reads as a durable combo-practice target
  rather than dying every few hits; the respawn path still exists and works
  if the maker wants something squishier — that's a one-constant tweak.

## Concerns

- None blocking. The `slice3_test_versus.gd` edit is the one deviation beyond
  the brief's stated file list; rationale is above and I believe it's exactly
  what the brief's Step 6 anticipated, but flagging clearly since it wasn't
  explicitly pre-approved.

## Fix pass

Test-only follow-up closing 3 coverage findings on `godot-project/tools/slice3_test_versus.gd`.
No production `.gd`/`.tscn`/`.godot` files changed (verified: `git status --porcelain`
shows only the test file modified after this pass).

### 1. (Important) New regression test — `_test_dummy_never_blocks_victory()`

Added a new test asserting a dummy can never block (or falsely gate) the
victory check. It runs against a **freshly-instantiated second `VersusArena`**
rather than the shared `arena` the other tests mutate, because `_match_over`
latches permanently once `_test_p1_elimination_ends_match` ends the shared
match in DEFEAT, and `VersusArena._on_fighter_fell` early-returns once
`_match_over` is true (VersusArena.gd:175) — the "kill every real bot, leave
dummies alive, expect VICTORY" scenario cannot be exercised on an
already-finished shared arena. A second instance gives a clean, isolated
match; real bots are looked up via that instance's own `_registry` (filtered
`node.is_in_group("enemy") and not node.is_in_group("dummy")`), never a raw
`get_nodes_in_group()` query, since the shared arena's fighters are still live
in the same `SceneTree` and would otherwise leak into the count.

The test:
- Collects the fresh arena's `BOT_COUNT` real bot ids from its own registry.
- Kills each real bot through the same `_on_fighter_fell` ring-out path the
  existing tests use (`STOCKS` falls per bot, `invuln` zeroed before each call
  so every fall actually lands) — mirrors the pattern already used in
  `_test_p1_elimination_ends_match`.
- Asserts `_bots_alive() == 0`, `_match_over == true`, and the banner text
  begins with `"VICTORY"` (not `"DEFEAT"`).
- Asserts all `DUMMY_COUNT` dummies are still `is_instance_valid`, in group
  `"dummy"`, and not `is_queued_for_deletion()`.

**RED-then-GREEN evidence** (a purely additive assertion on a fresh instance
can't be exercised against the current, correct code without breaking
something first, so I reverted the production fix under test, confirmed RED,
then restored it):
- Temporarily reverted `VersusArena._bots_alive()` (VersusArena.gd:225-233) to
  drop the `and not node.is_in_group("dummy")` clause.
- Ran `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice3_test_versus.gd`
  → **RED**:
  ```
  FAIL: _bots_alive() excludes the still-alive dummies, got 2
  FAIL: eliminating every real bot ends the match even though dummies remain
  FAIL: the victory finish fires (banner reads VICTORY), got
  Slice3 versus tests: 3 FAILED
  ```
  Exactly the failure mode described in `VersusArena.gd`'s own comment on
  `_bots_alive()`: without the dummy exclusion, the two permanently-alive,
  never-freed dummies keep `_bots_alive()` stuck at 2 forever, so the round
  can never reach VICTORY no matter how many real bots die.
- Restored `_bots_alive()` to its original, correct form (verified
  `git diff --stat godot-project/scripts/combat/VersusArena.gd` shows no
  diff), re-ran the same command → **GREEN**: `Slice3 versus tests: all PASS`.

### 2. (Minor) Dummy-stocks assertion in `_test_match_setup`

The loop that previously `continue`d past dummy registry entries (skipping
the "every fighter starts with STOCKS stocks" check for them) now asserts, in
the dummy branch, `int(entry.get("stocks", -1)) == arena.DUMMY_STOCKS` before
continuing.

### 3. (Minor) Ordering-fragility hardening in `_test_ring_out_respawns_bot`

`get_nodes_in_group("enemy")[0]` previously assumed the first enemy in the
group array is a real bot (an implicit ordering dependency on
`_spawn_fighters()` running before `_spawn_dummies()`, flagged as a known risk
in the original report's self-review). Now filters `not n.is_in_group("dummy")`
first, matching the same filter idiom already used in `_test_match_setup`, so
the test no longer silently depends on spawn-call order.

### Test commands + output

Amended-suite run:
```
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice3_test_versus.gd
```
```
Slice3 versus tests: all PASS
```
(A benign pre-existing `ObjectDB instances leaked at exit` / `1 resources
still in use at exit` warning still appears — confirmed present on an
unmodified baseline run via `git stash` before this pass too; not introduced
by this fix pass, and expected given the test harness never frees the
arena/root nodes before `quit()`.)

Full sweep — every `godot-project/tools/slice*_test_*.gd` (38 files, run
individually, same loop as the original report):
```
for f in godot-project/tools/slice*_test_*.gd; do
  godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script "tools/$(basename "$f")"
done
```
All 38 green, including `slice3_test_versus.gd` (`Slice3 versus tests: all
PASS`). No regressions in any other suite.

### Fix-pass concerns

- None blocking. Production code was never left in the reverted state —
  confirmed via `git status --porcelain` (only the test file shows modified)
  and `git diff --stat` on `VersusArena.gd` (empty) before committing.
