# Task 2 Report — The Hero: top-down movement + screenshake camera

**Status:** DONE
**Commit:** `d13b5c8` — `slice0: hero top-down movement + screenshake camera`
**Branch:** `v2.0-tower` (confirmed via `git branch --show-current`)

## Files changed

| File | Change |
|---|---|
| `godot-project/scripts/combat/Hero.gd` | NEW — CharacterBody2D script, exact plan code: `SPEED=210`, `Input.get_vector` over `move_*` actions, `facing` tracking, `hp`/`max_hp`, `take_damage()`, `health_changed(current: int, maximum: int)` signal, `_die()` resets to full HP. Joins group `"hero"` in `_ready()`. |
| `godot-project/scripts/combat/CombatCamera.gd` | NEW — extends Camera2D, exact plan code: `add_shake(amount)` capped at 24.0, `SHAKE_DECAY=12.0`, random offset in `_process`, joins group `"combat_camera"` in `_ready()`. |
| `godot-project/scenes/combat/Hero.tscn` | NEW — root `Hero` (CharacterBody2D, `groups=["hero"]`) with Hero.gd; children: `Visual` ColorRect offsets (-9,-9,9,9) hero-blue (0.4,0.7,1,1); `CollisionShape2D` RectangleShape2D 18×18; `Camera2D` with CombatCamera.gd, smoothing on at speed 8.0, limits 0/0/1200/680. |
| `godot-project/scenes/combat/Arena.tscn` | MODIFIED — added `Hero.tscn` PackedScene ext_resource, instanced `Hero` at (600, 340) room center; `load_steps` bumped 6→7. |
| `godot-project/scripts/combat/Hero.gd.uid`, `CombatCamera.gd.uid` | NEW — Godot-generated sidecars from the headless import, committed per repo convention (Task 1 did the same in `d61fc9f`). |

## Validation

1. `git branch --show-current` → `v2.0-tower` ✅
2. `"godot-engine/Godot_v4.6.2-stable_win64_console.exe" --headless --path godot-project --import` → exit 0; `first_scan_filesystem`, `update_scripts_classes`, `loading_editor_layout` all `[ DONE ]`, no errors. ✅
3. `"godot-engine/Godot_v4.6.2-stable_win64_console.exe" --headless --path godot-project --quit-after 120` → exit 0; output only the Godot banner + MCP Runtime port-7777 lines (known non-failures). Zero GDScript PARSE/SCRIPT errors. Arena (run scene) booted with Hero instanced. ✅

## Interface contract (for later tasks)

- `Hero`: CharacterBody2D in group `"hero"`, `var facing: Vector2`, `func take_damage(amount: int) -> void`, `signal health_changed(current: int, maximum: int)` — all exactly as specified.
- `CombatCamera`: extends Camera2D, group `"combat_camera"`, `func add_shake(amount: float) -> void` — exactly as specified.

## Deviations

- **Step 6 (PLAYTEST CHECKPOINT) skipped** per continuous-mode instruction; human playtests the whole slice at the end. `SPEED=210` left at the plan's starting value, untuned.
- **`.uid` sidecars added to the commit** — not in the plan's `git add` list, but the repo tracks them (Task 1 needed a follow-up commit `d61fc9f` for exactly this); bundling them avoids a stray-file follow-up.
- **Boot check used `--quit-after 120`** (per environment instructions) instead of the plan's `--quit-after 3`.
- No new `class_name` introduced, so no extra class-cache import cycle was needed (import was run anyway before boot).
