# Task 5 Report — Spell projectile + casting

**Status:** DONE
**Branch:** `v2.0-tower`
**Commit:** `6fa6f36` — `slice0: auto-aimed spell projectile + hero casting`

## Files

### Created
- `godot-project/scripts/combat/Spell.gd` — exact code from plan Step 1. Area2D projectile: `SPEED=460`, `LIFETIME=1.4`, `@export var damage: int = 18`, `launch(direction: Vector2)` normalizes dir + sets rotation, straight-flies in `_physics_process`, damages first group-`"enemy"` node via `body_entered`/`area_entered` (`_try_damage` calls `take_damage(damage)`, `Juice.hit_stop()`, `Juice.shake_camera(6.0)`, `queue_free()`).
- `godot-project/scenes/combat/Spell.tscn` — hand-authored (format 3, Player.tscn/Hero.tscn syntax). Root `Area2D` named `Spell` with `monitoring = true`, `monitorable = false`, script attached. Children: `Visual` ColorRect offsets (-6,-3,6,3) color (1, 0.85, 0.3, 1); `CollisionShape2D` with `RectangleShape2D` size (12, 6).
- `godot-project/scripts/combat/Juice.gd` — Step 2b STUB, exact code from plan: `class_name Juice extends RefCounted`, static `hit_stop(_duration: float = 0.06)` and `shake_camera(_amount: float = 6.0)`, both no-op `pass` bodies. Fleshed out in Task 7 — signatures locked.
- `.uid` sidecars for both new scripts (Godot-generated on import; committed per project convention).

### Modified
- `godot-project/scripts/combat/Hero.gd`:
  - Constants: `CAST_COOLDOWN: float = 0.35`, `SPELL_SCENE: PackedScene = preload("res://scenes/combat/Spell.tscn")`.
  - Member var: `_cast_cooldown_timer: float = 0.0`.
  - `_physics_process` top (immediately after the dash-cooldown decrement line): cast-cooldown decrement + `if Input.is_action_pressed("cast") and _cast_cooldown_timer <= 0.0 and not is_dashing: _cast()`.
  - New `_cast()`: sets cooldown, `Targeting.aim_direction(global_position, get_tree().get_nodes_in_group("enemy"), facing)`, instantiates spell into `get_parent()`, positions at hero, `spell.launch(dir)`, `Juice.shake_camera(2.0)`. Exact code from plan Step 3.

## Validation

1. `--headless --path godot-project --import` — clean; `update_scripts_classes` log shows **`Juice` registered** in the global class cache (class-name-cache trap handled per plan Step 2b).
2. `--headless --path godot-project --quit-after 120` — boot clean. Output was only the Godot banner + MCP Runtime port-7777 lines (expected non-failures per instructions). **Zero GDScript parse/script errors.**

## Deviations

- **Step 5 PLAYTEST CHECKPOINT skipped** — per continuous-mode instruction (no human input awaited).
- `.uid` sidecar files added to the commit beyond the plan's `git add` list — Godot 4.6 generates them on import and the repo's existing convention (Sessions 4+) commits them; omitting them would leave the tree dirty.
- `monitoring = true` written explicitly in `Spell.tscn` even though it is the Area2D default — spec said to set it; harmless and explicit.
- Commit message trailer `Co-Authored-By: Claude` appended per harness commit rules; plan message used verbatim as the subject line.
- No other deviations. Only `scripts/combat/` + `scenes/combat/` touched; hub/memory files untouched. Casting currently hits nothing (no enemies until Task 6) — expected.
