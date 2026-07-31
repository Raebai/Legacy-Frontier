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
## THE FLOOR'S SHAPE: 3-5 escalating waves, then the boss. Leave EMPTY and
## Encounter synthesizes a wave list from `enemy_budget` / `concurrent_cap`
## (Encounter.synthesize_waves), so a FloorDef authored before waves existed —
## or a synthesized fallback floor — still plays as a wave fight.
@export var waves: Array[WaveDef] = []
## The quiet beat between a cleared wave and the next one, in seconds.
@export var wave_break: float = 1.5
## Boss HP as a fraction of the guardian's full strength. <= 0 derives it from
## floor_type (Encounter.boss_scale_for_type): a COMBAT floor gets a lean
## mini-guardian, ELITE a bigger one, BOSS the colossus at full size.
@export var boss_scale: float = 0.0
## Environment + layout (null = inherit the tower default, resolved at build).
@export var theme: EnvTheme = null
@export var layout: LayoutDef = null
## Loose escape hatch for per-floor rules (e.g. "no_crates", "boss_gate").
@export var special_tags: Array[String] = []
