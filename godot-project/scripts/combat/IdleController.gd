class_name IdleController
extends RefCounted
## A CONTROLLER THAT NEVER PRESSES ANYTHING.
##
## ⚠ IT EXISTS TO LET A BODY RUN ITS PHYSICS WITHOUT DRIVING ITSELF, and that is a
## real trap rather than a nicety. `Hero._pressed` and its five siblings fall through
## to the GLOBAL `Input` singleton when `controller` is null:
##
##     return controller.pressed(a) if controller != null else Input.is_action_pressed(a)
##
## So a `Hero` with no controller does not stand still — it MIRRORS THE PLAYER. Every
## practice dummy walks when you walk, jumps when you jump and casts when you cast,
## because all of them are reading the same keyboard you are.
##
## The workaround up to now was `set_physics_process(false)`, which does stop the
## mirroring — and stops everything else with it: no gravity, no knockback, no ragdoll,
## no flinch, no landing. A dummy became a photograph. Maker, on the town: "make all
## the other stickmen in the hub the same as mine in terms of ragdoll physics."
##
## Answering `false` / `0` / `ZERO` to the six polling methods is the whole class. The
## body then runs its normal `_physics_process` — falls, is shoved, goes limp when hit,
## settles — and simply never chooses to do anything.
##
## Duck-typed on purpose: `Hero.controller` is deliberately untyped so a stub only has
## to implement these six. See the note on that property.


func pressed(_action: StringName) -> bool:
	return false


func just_pressed(_action: StringName) -> bool:
	return false


func just_released(_action: StringName) -> bool:
	return false


func axis(_neg: StringName, _pos: StringName) -> float:
	return 0.0


func vector(_nx: StringName, _px: StringName, _ny: StringName, _py: StringName) -> Vector2:
	return Vector2.ZERO


## `BotController` publishes a cursor for aim; a body that never aims reports its own
## position, which every consumer already treats as "no opinion".
func aim_point(from: Vector2) -> Vector2:
	return from


## ⚠ SEVEN METHODS, NOT SIX, AND THE SEVENTH IS NOT OPTIONAL. `Hero._physics_process`
## calls `controller.tick(self, clock)` unconditionally on every physics frame the
## moment `controller != null` — it is the hook a `BotController` thinks on. A stub
## without it is not "a controller that does nothing", it is a runtime error per body
## per frame.
##
## The test suite did NOT catch this: the assertions that matter here check that a
## dummy HAS a controller and IS processing physics, both of which were true while the
## engine logged four errors a frame. It was caught by a CAPTURE — running the real
## scene and reading the output — which is the same lesson as the rig's feet. A green
## suite is not a running game.
func tick(_body: Node, _clock: float) -> void:
	pass
