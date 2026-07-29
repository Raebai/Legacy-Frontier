extends RefCounted
## A PER-INSTANCE virtual gamepad for the bot simulation.
##
## Godot's `Input` is process-global: two bots driving it would fight over the
## same virtual buttons and would also drive the human's hero. So a simulated
## fighter cannot be driven through `Input.action_press` — it needs its own
## button state, which is exactly what `Hero.controller` (the input seam) exists
## to accept. This is the harness's implementation of that interface.
##
## It mirrors Godot's `Input` API 1:1 (is_pressed / just_pressed / just_released
## / axis / vector) plus `aim_point`, which replaces `get_global_mouse_position`
## for a body that has no mouse. Edges are DERIVED by diffing this tick's held
## set against last tick's, so the brain above never has to think in edges — it
## just says what it is holding down right now.
##
## ⚠ NOT declared with `class_name`, and it extends RefCounted rather than the
## game's `HeroController`. Two reasons, both practical:
##   1. The seam is being landed by another agent; this file must compile whether
##      or not `scripts/combat/HeroController.gd` exists yet.
##   2. When it DOES exist and `Hero.controller` is strictly typed, the harness
##      materialises `tools/sim_controller_typed.gd.tmpl` — a four-line subclass
##      of the real base that delegates straight back into this object. So there
##      is exactly one implementation of the button logic, in this file.
##
## FAIRNESS: this object holds buttons, nothing else. It has no access to the
## world and cannot read anything a player could not see. Every decision about
## WHAT to press is made upstream, from perception the same as a human's.

## Held this tick: StringName -> true. Absent means released.
var held: Dictionary = {}
## Held LAST tick, snapshotted by `commit()`. The diff of the two is every edge.
var _prev: Dictionary = {}
## Analog aim, as a unit direction from the body. The hero converts it to a world
## point via `aim_point`, mirroring how a mouse cursor supplies one.
var aim_dir: Vector2 = Vector2.RIGHT
## How far along `aim_dir` the notional cursor sits. Only spells that PLACE at a
## point (meteor, divine ray, convergence) care about the distance; aimed and
## self-centred spells discard it. Kept explicit so a bot can deliberately place
## a meteor short of its target rather than always at maximum reach.
var aim_range: float = 220.0

## Actions this controller refuses to press no matter what the brain asks, because
## pressing them corrupts state that belongs to the player rather than the fight:
## `switch_class` writes through to GameState.selected_class, and the two cosmetic
## cycles would make a capture unwatchable and a sim unreproducible.
##
## ⚠ `cycle_signature` is DELIBERATELY NOT IN THIS LIST, and that is a considered
## disagreement with the build plan, which suppresses it alongside the other
## three. It is not a loadout re-roll — it is how a hero SELECTS which of its five
## kit spells the ultimate key will cast. Suppressing it strands every bot on
## signature index 0 forever, which would make four of every class's five spells
## unreachable and would silently defeat this harness's "a spell never fires"
## detector. See the report: this needs resolving in BotController too.
const SUPPRESSED: Array[StringName] = [
	&"switch_class", &"cycle_element", &"cycle_colourway",
]


func press(action: StringName) -> void:
	if action in SUPPRESSED:
		return
	held[action] = true


func release(action: StringName) -> void:
	held.erase(action)


## Drop every button. Called between matches so no press leaks across a pairing.
func clear() -> void:
	held.clear()


## End of tick: this tick's held set becomes next tick's "previous", which is what
## makes just_pressed / just_released mean anything. Must be called exactly once
## per driven frame, AFTER the hero has polled.
func commit() -> void:
	_prev = held.duplicate()


# ---- the Input-shaped interface Hero polls ---------------------------------

func is_pressed(action: StringName) -> bool:
	return bool(held.get(action, false))


func just_pressed(action: StringName) -> bool:
	return bool(held.get(action, false)) and not bool(_prev.get(action, false))


func just_released(action: StringName) -> bool:
	return not bool(held.get(action, false)) and bool(_prev.get(action, false))


func axis(neg: StringName, pos: StringName) -> float:
	return (1.0 if is_pressed(pos) else 0.0) - (1.0 if is_pressed(neg) else 0.0)


func vector(nx: StringName, px: StringName, ny: StringName, py: StringName) -> Vector2:
	return Vector2(axis(nx, px), axis(ny, py))


## The stand-in for `get_global_mouse_position()`. `from` is the hero's own
## position, so the cursor is always a fixed offset along the aim — which is the
## honest analogue of a player pointing in a direction.
func aim_point(from: Vector2) -> Vector2:
	return from + aim_dir.normalized() * aim_range
