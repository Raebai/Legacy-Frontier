# Tune 1 Report — Slice 0 feel-tune (collision layers + spell VFX)

Date: 2026-07-09 · Branch: `v2.0-tower`

## Files changed

| File | Change |
|---|---|
| `godot-project/scenes/combat/Arena.tscn` | `Walls` StaticBody2D: `collision_layer = 1`, `collision_mask = 0` |
| `godot-project/scenes/combat/Hero.tscn` | `Hero` CharacterBody2D root: `collision_layer = 2`, `collision_mask = 1` |
| `godot-project/scenes/combat/Enemy.tscn` | `Enemy` CharacterBody2D root: `collision_layer = 4`, `collision_mask = 1` |
| `godot-project/scenes/combat/Spell.tscn` | `Spell` Area2D: `collision_mask = 4` (kept `monitoring = true`, `monitorable = false`); added `Glow` ColorRect + `Trail` GPUParticles2D (see VFX below) |
| `godot-project/scripts/combat/Spell.gd` | `_try_damage` now calls new `_spawn_impact_burst()` before `queue_free()`; `Juice.hit_stop()` + `Juice.shake_camera(6.0)` kept |

## Part 1 — Exact collision values set

- Walls: layer `1` / mask `0`
- Hero: layer `2` / mask `1` → collides with walls only, dashes THROUGH enemies
- Enemy: layer `4` / mask `1` → collides with walls only, passes through hero + other enemies
- Spell (Area2D): mask `4` → detects enemy layer only; ignores walls (layer 1) and hero (layer 2)

Contact damage unaffected (Enemy uses `distance_to`, not physics). Spell→enemy hits confirmed working via headless test (below).

## Part 2 — Spell VFX

- **Glow**: `Glow` ColorRect, offsets (-14, -8, 14, 8), `Color(1, 0.8, 0.3, 0.35)`, declared BEFORE `Visual` in the .tscn so it renders under the bolt.
- **Trail**: `GPUParticles2D` child — `emitting = true`, `amount = 16`, `lifetime = 0.35`, `local_coords = false`, `ParticleProcessMaterial` sub_resource (spread 30, initial_velocity 14–26, scale 1–3, gravity zero, `particle_flag_disable_z = true`, color_ramp = Gradient warm gold `(1, 0.8, 0.3, 0.85)` → transparent `(1, 0.6, 0.2, 0)` via GradientTexture1D). Default square particle texture. Scene `load_steps` bumped 3 → 6 for the three new sub_resources.
- **Impact burst** (`Spell.gd::_spawn_impact_burst`): one-shot `GPUParticles2D` built in code — `emitting = false` first, `one_shot = true`, `explosiveness = 1.0`, `amount = 20`, `lifetime = 0.4`, radial ParticleProcessMaterial (spread 180, velocity 60–130, scale 1–3, gravity zero, warm-gold→transparent Gradient color_ramp). Added to `get_parent()` (so it survives the spell's `queue_free`), positioned via 2D `global_position`, then `restart()` + `emitting = true`; freed after 0.6 s via `get_tree().create_timer(0.6).timeout.connect(burst.queue_free)`. Guards against `get_parent() == null`.

## Validation

1. **Import**: `Godot_v4.6.2 --headless --path godot-project --import` → exit 0, zero parse/script errors (only progress banner).
2. **Boot**: `--headless --quit-after 180` → exit 0. Output was only the Godot banner + MCP Runtime port lines (expected, not failures). Zero PARSE/SCRIPT/RUNTIME errors. Arena is the main scene, so enemies spawn during the window.
3. **Impact-burst code path**: headless boot cannot cast (casting is input-driven), so the burst path was exercised directly with a throwaway SceneTree script (scratchpad, not committed): instantiated `Spell.tscn` + `Enemy.tscn`, called `launch()` then `_try_damage(enemy)`. Output:
   `BURST_TEST spell_mask=4 enemy_layer=4 enemy_hp=22 burst_spawned=true` / `BURST_TEST_OK` — damage landed (40→22), one-shot burst node spawned, zero errors, exit 0.

## Deviations / concerns

- **Burst validation method**: the boot window alone can't exercise `_spawn_impact_burst` (no input headlessly), so a dedicated headless script test was used instead — arguably stronger evidence than the boot run.
- **Pre-existing dirty files NOT committed**: `project.godot`, `scenes/Main.tscn`, `data/npcs/first_npc.tres`, `data/npcs/mirelle.tres`, `assets/tilesets/placeholder_atlas.tres` were already modified in the working tree by Godot editor/import resaves (uid + `unique_id` annotations, property reordering). Notably `first_npc.tres`'s resave DROPS fields (`traits`, `max_hp`, `mood`, `trust`, `patience`, `display_color`) — that looks lossy and unrelated to this task, so it was deliberately left out of the commit for a human decision.
- Trail particle emission direction is world +X (default, `local_coords = false`); at 14–26 px/s vs the bolt's 460 px/s the drift is imperceptible — flagged as a future tuning knob only.
