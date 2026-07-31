class_name WaveDef
extends Resource
## ONE WAVE of a floor's fight. A floor is an ordered list of these: the wave
## spawns its whole budget, the room goes quiet, a beat passes, the next (harder)
## wave starts. When the last wave is cleared the floor's boss arrives.
##
## The per-wave knobs mirror FloorDef's encounter fields. A NEGATIVE value means
## "inherit the floor's value" — so a wave list can escalate only what it cares
## about (usually budget + cap) and leave difficulty to the floor.

## Total enemies this wave spawns.
@export var enemy_budget: int = 4
## Max alive at once during this wave (the pressure knob).
@export var concurrent_cap: int = 3
## Archetype-roll bias. < 0 inherits FloorDef.brute_chance.
@export var brute_chance: float = -1.0
## HP scaling for this wave's enemies. < 0 inherits FloorDef.hp_multiplier.
@export var hp_multiplier: float = -1.0
## Seconds between spawns inside this wave. < 0 uses Encounter.SPAWN_INTERVAL.
@export var spawn_interval: float = -1.0


## Resolve `brute_chance` against the floor's value (the < 0 = inherit rule).
func resolved_brute(floor_brute: float) -> float:
	return floor_brute if brute_chance < 0.0 else brute_chance


## Resolve `hp_multiplier` against the floor's value.
func resolved_hp(floor_hp: float) -> float:
	return floor_hp if hp_multiplier < 0.0 else hp_multiplier


## Resolve `spawn_interval` against the encounter default.
func resolved_interval(default_interval: float) -> float:
	return default_interval if spawn_interval < 0.0 else spawn_interval
