extends Node2D
## STAND-IN FOR ANOTHER AGENT'S MINION, for tools/slice_test_class_movement.gd.
##
## The Warlock's Thrall Swap is written against a published contract and nothing else:
## group `&"thrall"`, node meta `&"thrall_owner"` -> the Hero that raised it, optional
## `hp` / `downed` for liveness. The minions themselves are another agent's file, so the
## suite must be able to exercise the contract WITHOUT importing them — otherwise the
## test would be pinned to an implementation this task does not own and would break the
## moment that agent lands.
##
## ⚠ WHY THIS IS A SCRIPT AND NOT A BARE `Node2D`. `set()` on an UNDECLARED property is
## a SILENT NO-OP in GDScript: `node.set("hp", 0)` on a plain Node2D succeeds, changes
## nothing, and the "a dead thrall is not a destination" assertion would then be testing
## a thrall that is still at full health — passing for the wrong reason. Declaring the
## fields here is what makes that assertion mean what it says.
##
## Named with a leading underscore so `python-tools/run_all_tests.py` does not mistake
## it for a suite (its EXCLUDE_RES drops `^_`).

var hp: int = 10
var downed: bool = false
## Written by `Hero._thrall_swap` so a swapped minion does not inherit a fall.
var velocity: Vector2 = Vector2.ZERO
