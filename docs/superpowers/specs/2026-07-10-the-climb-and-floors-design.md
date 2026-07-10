# The Climb + Data-Driven Floors — Design Spec

**Date:** 2026-07-10 · **Branch:** `v2.0-tower` · **Status:** approved, building

High-level spec for two intertwined changes agreed in brainstorm: (1) reframe the loop from roguelite to a **persistent Tower-of-God climb**, and (2) replace the hardcoded single-room "floor" with a **data-driven floor system**. Keep it simple; this is a *data-shape* change, not new systems.

## 1. Core model — persistent climb (not a roguelite)

- You are a **persistent Climber**. Rank / identity / highest-floor **never reset** — they persist to disk.
- Floors are **tests**. **Failing a floor = drop 2 floors, stay in the tower, keep everything** (rank/power/loot). No run-reset. You re-climb the lost ground; a `falls` counter ticks up.
- The **town clocks you**: on returning to the hub, Raebai/Mirelle reference your climb via the existing memory plumbing (floor reached + falls) — no new memory system.
- You return to the hub **deliberately** (a hub-return portal on any cleared floor) or on **conquering** the tower. Entering the tower **resumes** from your saved floor.

## 2. Floor architecture — a linear spine of typed floors

The climb is a **linear spine**, not a room-maze — so no dungeon-stitching. Three decoupled layers:

1. **Tower (spine)** = data: an ordered list of **typed** floors. One `.tres` per tower.
2. **Room** = one reusable arena shell, **parameterized by data** (size, obstacles, spawn-points, hazards). Bosses get a bespoke room. (Chosen over a hand-authored room pool / procedural — both can slot in later behind the same seam.)
3. **Fight** = enemies spawned into the room's marker points from the floor's data.

New floor = new data row. New tower = new `.tres` + a theme (tileset/tint). **No new code per floor.** Mirrors our shipped `NPCData`/`.tres` + `TuningConfig` pattern; matches how Hades / Soul Knight / Isaac actually work.

### Data shapes (Godot Resources, `.tres`-authorable)
- **`FloorType`** enum: `COMBAT, ELITE, BOSS, REST, PVP` (PVP reserved, built much later).
- **`FloorDef`**: `floor_type`, `enemy_budget`, `concurrent_cap`, `archetype_weights`, `hp_multiplier`, `theme`, `layout`, `special_tags`.
- **`LayoutDef`**: `room_size`, `spawn_rect_min/max`, `min_spawn_dist_from_hero`, `hero_start`, `exit_point`, `crate_positions`, `weapon_pickups`. (Seam: an optional `layout_scene: PackedScene` can be added later for bespoke rooms — no caller changes.)
- **`EnvTheme`**: `name`, `wash_tint` (grows to backdrop/music/props later).
- **`TowerDef`**: `id`, `display_name`, `theme`, `floors: Array[FloorDef]`.

### Runtime split (decompose the `Arena.gd` god-script)
- **`GameState`** — floor *sequencing* + owns the active `TowerDef` + climber persistence.
- **`FloorBuilder`** — given a `FloorDef`, populate the room (layout, crates, pickups, theme wash). Pure "data → children."
- **`Encounter`** — budget/cap/pacing + archetype roll + spawn-point selection; emits `cleared`.
- **`Arena`** — thin coordinator: build floor, run encounter, place exit portal, keep the existing `advance_floor`/`ExitPortal`/`Hero._die` wiring.

## 3. Build order (incremental, each verified, nothing breaks the loop)

1. **Floor Resources + synthesize-from-math** — add the Resource scripts; `GameState` synthesizes a `FloorDef` from today's `f(floor)` math when no tower is set; `Arena` reads the `FloorDef`. Behavior identical; sandbox (F6) untouched.
2. **Extract `Encounter`** from `Arena.gd` (headless-tested via the hand-built-arena idiom).
3. **Extract `FloorBuilder` + `LayoutDef`** (geometry/crates/pickups out of `Arena.gd`).
4. **Author `data/towers/ashspire.tres`** — 5 typed floors (`COMBAT×3, ELITE, BOSS`); set `active_tower` in `enter_run`; delete the dead `f(floor)` math.
5. **Persistent climb spine** — climber state to disk (highest/current floor, falls, rank); resume on enter; `Hero._die` → drop-2-stay; hub-return portal; town clocks the climb via memory fact.

## 4. Out of scope (do NOT build yet)
Procedural generation · hand-authored room pool · room/branch graph (Slay-the-Spire map) · per-enemy archetype Resource · REST-floor economy / shop UI · PvP logic · EnvTheme backdrops/music. Reserve the enum values and seams; ship the spine.

## 5. Invariant to preserve
`enter_run → Arena._ready → build floor → clear → ExitPortal.taken → advance_floor → floor_changed → build floor`, plus `Hero._die` and the standalone-F6 sandbox. Refactor consumes *data* where it used *math*; the wiring is untouched.
