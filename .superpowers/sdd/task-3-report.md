# Task 3 Report — Dash

## Status
DONE

## Files changed
- `godot-project/scripts/combat/Hero.gd` (only file modified)
  - Added constants: `DASH_SPEED = 620.0`, `DASH_TIME = 0.14`, `DASH_COOLDOWN = 0.55`
  - Added member vars: `is_dashing: bool = false` (interface for later i-frames task — name preserved), `_dash_timer`, `_dash_cooldown_timer`, `_dash_dir`
  - Replaced `_physics_process` body with the plan's exact dash-aware version (cooldown ticks every frame; dash overrides movement for DASH_TIME; existing `Input.get_vector` movement + `facing` update preserved verbatim; dash triggers on `dash` action via `Input.is_action_just_pressed` — named actions only, per Global Constraints / D-011)
  - Added `_start_dash()` method (sets state, snapshots `facing` into `_dash_dir`)

## Validation
Branch confirmed: `v2.0-tower`

Command:
```
"godot-engine/Godot_v4.6.2-stable_win64_console.exe" --headless --path godot-project --quit-after 120
```
Output:
```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org

[MCP Runtime] Server listening on port 7777
[MCP Runtime] Autoload ready, server starting on port 7777
```
No GDScript PARSE/SCRIPT errors. MCP banner lines are expected noise, not failures.

## Commit
- `e39e3ed` — `slice0: hero dash (burst + cooldown)` (plan's Step 5 message)

## Deviations
- Step 4 (PLAYTEST CHECKPOINT) skipped per continuous-mode instruction. Dash numbers (620 / 0.14 / 0.55) are the plan's untuned starting points; tuning deferred to a later human playtest.
- No other deviations. Code matches the plan's Task 3 snippets exactly (only signature change: `_delta` -> `delta`, as required by the replacement code).
