class_name FloorDef
extends Resource
## One floor of the climb — a typed test. The floor TYPE drives the rules; the
## encounter/theme/layout fields drive the content. Authored per-tower as .tres,
## or synthesized from depth math when no tower is set (sandbox / fallback).

enum FloorType { COMBAT, ELITE, BOSS, REST, PVP }

@export var floor_type: FloorType = FloorType.COMBAT
## Encounter (replaces the old f(floor) depth math).
@export var enemy_budget: int = 4       # total enemies this floor; 0 = REST (no combat)
@export var concurrent_cap: int = 3     # max alive at once
@export var brute_chance: float = 0.35  # biases the archetype roll toward brutes
@export var hp_multiplier: float = 1.0  # depth HP scaling
## Environment + layout (null = inherit the tower default, resolved at build).
@export var theme: EnvTheme = null
@export var layout: LayoutDef = null
## Loose escape hatch for per-floor rules (e.g. "no_crates", "boss_gate").
@export var special_tags: Array[String] = []
