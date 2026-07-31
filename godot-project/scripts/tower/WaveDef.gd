class_name WaveDef
extends Resource
## ONE WAVE of a floor's fight. A floor is an ordered list of these.
##
## PACING (the thing this resource exists to author): a wave does NOT wait for an
## empty room. It opens with a VANGUARD that lands all at once — the unseen hand
## DRAWS the mob in, so a group appearing from nothing is diegetic and can be
## loud — trickles the rest under `concurrent_cap`, and hands off to the next wave
## while its last few bodies are still standing (see `handoff_alive`). Pressure
## therefore never drops to zero, which is the whole point: dead air is the
## opposite of what a floor is for.
##
## ESCALATION (the difficulty dial): vary the MIX, not the HP. `archetypes` names
## exactly who shows up, so wave 3 can be "two chargers and a mage at once" while
## wave 1 is "chasers". Per the spec — "higher floors add modifiers, not HP. HP
## scaling makes fights longer, not harder, and long is the enemy of chaos on a
## phone" — `hp_multiplier` is left at its inherit default in every authored wave.
##
## The per-wave knobs mirror FloorDef's encounter fields. A NEGATIVE value means
## "inherit the floor's value" — so a wave list can escalate only what it cares
## about and leave the rest to the floor.

## Total enemies this wave spawns.
@export var enemy_budget: int = 4
## Max alive at once during this wave (the pressure knob).
@export var concurrent_cap: int = 3
## Archetype-roll bias. < 0 inherits FloorDef.brute_chance.
@export var brute_chance: float = -1.0
## HP scaling for this wave's enemies. < 0 inherits FloorDef.hp_multiplier.
## LEAVE THIS ALONE in authored waves — escalate `archetypes` instead.
@export var hp_multiplier: float = -1.0
## Seconds between spawns inside this wave. < 0 uses Encounter.SPAWN_INTERVAL.
@export var spawn_interval: float = -1.0
## THE MIX. Enemy.Archetype ids this wave may roll (empty = the floor's weighted
## roll over all eight). This is the difficulty axis: more bodies, then tankier
## bodies, then a nastier mix, then two threats at once.
@export var archetypes: Array[int] = []
## How many bodies land AT ONCE the moment the wave opens. < 0 derives it from
## `concurrent_cap` (Encounter.vanguard_for_cap) so most waves need not say.
@export var vanguard: int = -1
## Hand off to the next wave once this many (or fewer) bodies are left alive —
## the overlap that kills the dead air. < 0 derives it from `concurrent_cap`
## (Encounter.handoff_for_cap). 0 means "wait for a genuinely empty room".
@export var handoff_alive: int = -1


## Resolve `brute_chance` against the floor's value (the < 0 = inherit rule).
func resolved_brute(floor_brute: float) -> float:
	return floor_brute if brute_chance < 0.0 else brute_chance


## Resolve `hp_multiplier` against the floor's value.
func resolved_hp(floor_hp: float) -> float:
	return floor_hp if hp_multiplier < 0.0 else hp_multiplier


## Resolve `spawn_interval` against the encounter default.
func resolved_interval(default_interval: float) -> float:
	return default_interval if spawn_interval < 0.0 else spawn_interval


## Resolve the opening burst against the cap-derived default.
func resolved_vanguard(derived: int) -> int:
	return derived if vanguard < 0 else vanguard


## Resolve the overlap threshold against the cap-derived default. 0 is a
## MEANINGFUL authored value ("clear the room first"), so only < 0 inherits.
func resolved_handoff(derived: int) -> int:
	return derived if handoff_alive < 0 else handoff_alive
