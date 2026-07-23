# Task 2 report — Stickman feel (CharacterRig)

**Branch:** v2.0-tower · **File:** `godot-project/scripts/combat/CharacterRig.gd` (+ new `godot-project/tools/slice_test_rig.gd`)

## What changed (final numeric values)

### 1. AIR state + phase (interface contract for Task 6)
- `enum State { … WALL_SLIDE, AIR }` — added **at the end** (index 8) so existing indices/saves/tests stay valid.
- Fields `_air_rising: bool`, `_air_grounded: bool`; method `set_air_phase(rising: bool, grounded: bool)`.
- New `State.AIR` pose branch in `_compute_pose` (placed right after IDLE):
  - **rising** (`_air_rising`): knees tuck up (`leg_len*0.58/0.68`), arms thrown up.
  - **falling** (default): legs reach down (`leg_len*1.06`), arms out to balance.
  - **landing** (`_air_grounded`): brief crouch/squash (`bob = height*0.10`, legs `*0.70`).
- Task-6-callable exactly as specified: `CharacterRig.State.AIR`, `play(State.AIR)`, `set_air_phase(rising, grounded)`.

### 2. Foot-plant IK
- `const GROUND_MASK: int = 1` — **verified** against the code, not guessed: VersusArena `_make_terrace` terraces (StaticBody2D default layer 1), `RuinPlatform` (default layer 1), `BreakablePlatform` (`collision_layer=5` = bits 1+3), `RockWall`/`IceWall` (layer 1), matching `Hero.BLINK_WALL_MASK=1`. Fighter bodies are on layers 2 (hero) / 4 (enemy, boss), so a mask-1 downward ray never self-hits.
- `_update_ground_probe()` (called once/frame in `advance()`): raycasts straight down from ~head height to `height*1.5` below via `get_world_2d().direct_space_state.intersect_ray`, caches the contact point as LOCAL y in `_ground_local_y` (INF when airborne / off-tree / no ground within reach). A downward ray is vertical regardless of `scale.x`, so the facing flip is irrelevant.
- `_plant_foot(local_foot, ground_local_y) -> Vector2` (pure, headless-testable): a **support** foot at/below the ground line is clamped exactly onto it (x preserved); a **lifted/swing** foot above the line is left untouched so the stride still reads.
- Wired in `_sim_pose()` for both feet when `_grounded and state != AIR and _limp < 0.5 and is_finite(_ground_local_y)`. This is what fixes the "float" for the now-larger figure (hero natural feet ≈ +15.2 local vs the 18px collider bottom at +9 → planted up onto the floor instead of sinking).

### 3. Tamed spring
- `STIFFNESS: 60 → 180`, `MAX_OFFSET_FACTOR: 0.85 → 0.35` (limbs settle tight to the pose).
- Leg softness is now **gated by limp**: `leg_stiffness = stiffness * lerpf(1.0, LOOSE_LEG_STIFFNESS, _limp)`. At rest `_limp = 0` → full-stiffness, planted legs (no drift); the loose/flowy legs only appear when the body goes limp — i.e. the post-hit `flop()` HURT flail and the hold-DOWN ragdoll. `LOOSE_LEG_STIFFNESS` const unchanged (still 0.5, now applied only under limp).

### 4. Aim arm snaps
- Extended the aim gate from `IDLE/RUN` to `_is_aim_state()` = **IDLE, RUN, AIR, DASH, CAST** (new helper).
- In `_sim_pose()`, when `aim_arm and _is_aim_state()`, the drawn `hand_lead` is set to the **target** angle from `_compute_pose` (snapshotted before the sim overwrite) — the lead hand **bypasses the spring** and points exactly at the cursor instead of lagging. Shoulder still eases, so the arm reads responsive, not rigid. Strikes/wall-slide keep their scripted arm.

### 5. Bolder silhouette
- Limb width `height*0.12 → height*0.16`; head radius `height*0.15 → height*0.18`.
- `OUTLINE_COLOR: Color(0.10,0.11,0.16,0.85) → Color(0.04,0.04,0.07,1.0)` (true dark, opaque keyline); `OUTLINE_EXTRA: 1.0 → 2.0`.
- Default `height: 26.0 → 31.0` (moderate size bump). Boss.tscn (`height=95`) and the capture rigs override per-instance, so only the default hero + regular enemies grow — camera/VersusArena framing untouched, as required.

## Tests
- New `tools/slice_test_rig.gd` (SceneTree runner): asserts `State.AIR` exists + `play(AIR)` enters it; `set_air_phase` flips the flags and the AIR rising/falling poses differ (rising tucks higher); aim-arm lead-hand angle matches `set_aim` within 0.02 rad in **IDLE** and in **AIR**; `_plant_foot` clamps a sinking foot to the line (x preserved) and leaves a lifted foot; spring consts are within the settled targets.
- Command: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_rig.gd` → **`rig tests: all PASS`**, exit 0. (The `ObjectDB instances leaked` warning is benign and identical in the pre-existing `slice1_test_rig.gd`.)
- Full sweep of all 40 `tools/slice*_test_*.gd`: **PASS=40 FAIL=0** (includes the existing `slice1_test_rig.gd` and every enemy/rig/coop suite — no regressions).

## GPU capture (feel judged by eye)
- Command: `godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/verify_feel_capture.gd`
- Output: `C:\Users\Raaed\AppData\Roaming\Godot\app_userdata\Legacy Frontier\verify_sheet.png` (also `user://verify_sheet.png`).
- What it shows (confirmed by a 3× zoom-crop): **bold dark-outlined blue stick puppet** with a clear keyline; in cell [0] (idle, aim right) the **feet are planted on the terrain floor — no float**; in cell [3] (cast, aim up-right) the **lead hand VFX points up-right at the aim**; cell [2] shows the parry shield arc. No physics/query errors during the live raycast run.
- Note: cell [1] ("jump") still shows the run-leg pose because **Hero's state SELECTION (choosing AIR on `!is_on_floor()`) is Task 6** and out of scope here — the rig now *provides* the AIR pose + `set_air_phase`, but nothing calls `play(State.AIR)` yet. This is the intended interface hand-off.

## Self-review / limitations
- **Foot-plant is one-directional** (clamps sinking feet up, never pulls a floating foot down) — correct for the run cycle (swing foot must stay lifted) and for the bumped-height fighters (which sink). The **boss** rig (height 95, deep 44×92 collider at +6) has natural feet ~4.5px *above* its floor line, so its feet are not planted down — but that float is pre-existing (unchanged from before this task) and negligible at that scale. Regular hero/enemies are fully grounded.
- The live raycast is **runtime-only** (guarded by `is_inside_tree()` + null `World2D`/space checks); it can't be exercised headlessly, so the headless test covers the pure `_plant_foot` math and the capture covers the live grounding. Query runs from `_process` (via `advance()`); the capture run produced no "flushing queries" or space-state errors.
- Applied to **all fighters** (rig is visual) — intended; does not touch co-op gameplay-logic paths, so the SP-byte-identical rule is unaffected.
- No new `class_name` introduced; headless `--import` run clean before capture regardless.
