# Task 6 Report — Enemies (two archetypes) + the fight

**Status:** COMPLETE
**Branch:** `v2.0-tower`
**Commit:** `e4926e1` — `slice0: two enemy archetypes, chase + damage + death, arena spawner`
**Date:** 2026-07-08

## Files

| File | Action |
|---|---|
| `godot-project/scripts/combat/Enemy.gd` | Created — exact code from plan Step 1 (CharacterBody2D, `add_to_group("enemy")` in `_ready`, `@export` max_hp / move_speed / touch_damage / tint, chase via `move_and_slide`, contact damage <22px on 0.8s cooldown, `take_damage(amount: int)`, white hit-flash, `_die()` → `Juice.shake_camera(8.0)` + `Juice.hit_stop()` + `queue_free()`) |
| `godot-project/scenes/combat/Enemy.tscn` | Created — hand-authored, root `Enemy` (CharacterBody2D) + `Visual` ColorRect offsets (-10,-10,10,10) color (0.9,0.35,0.3,1) + `CollisionShape2D` RectangleShape2D size (20,20). Syntax modeled on `scenes/Player.tscn` / `scenes/combat/Spell.tscn` |
| `godot-project/scripts/combat/Arena.gd` | REPLACED entirely — plan Step 3 verbatim: preload Enemy scene, keep TARGET_ENEMY_COUNT=5 alive, spawn every 1.2s when below target, 50/50 archetype roll (chaser: 24hp/140spd/8dmg orange vs brute: 70hp/62spd/18dmg magenta), random position in ARENA_MIN(80,80)–ARENA_MAX(1120,600) |
| `godot-project/scripts/combat/Enemy.gd.uid` | Godot-generated sidecar, committed per repo convention |

## Validation

1. **Headless import:** `--headless --path godot-project --import` → exit 0, no PARSE/SCRIPT errors (only progress banners).
2. **Boot check:** `--headless --path godot-project --quit-after 180` → exit 0, zero GDScript errors. MCP/Vulkan-style banners only.
3. **Spawn/chase evidence:** confirmed `run/main_scene="res://scenes/combat/Arena.tscn"` and Arena instances Hero, then ran two boots with a temporary `print` in `_spawn_enemy`:
   - Run 1: `spawned enemy hp=24 speed=140 at (701.5, 301.8)` + a second chaser — chaser archetype spawns and chases 3s with no runtime errors.
   - Run 2 (300 frames): `spawned enemy hp=70 speed=62 at (726.8, 446.9)` + a second brute — brute archetype confirmed.
   - Debug print removed; final clean boot produced zero non-banner output.
4. Committed state boots clean.

## Deviations

- **PLAYTEST CHECKPOINT (Step 5) skipped** per continuous-mode instruction. Numbers are the plan's untuned starting values.
- Temporary debug `print` added/removed during validation only (not in committed code).
- `Enemy.gd.uid` included in the commit beyond the plan's 3-file `git add` list — matches this repo's established sidecar-committing convention.
- No other deviations; Enemy.gd and Arena.gd are the plan's code verbatim.

## Notes / Concerns

- Only ~2 spawns occur per 180-frame headless window (spawner ticks every 1.2s) — expected, not a defect.
- `Juice.hit_stop()` / `shake_camera()` are still no-op stubs until Task 7; `_die()` calls them safely.
- Enemies can spawn on top of the hero (random position, no min-distance check) — plan-as-specified; a tune-pass candidate for the maker's playtest.
