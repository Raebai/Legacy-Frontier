# A fighter-shaped STUB for the drop-economy spell suites: the four things a
# spectacle actually touches on a body — `hp`, `max_hp`, `velocity` and a
# one-argument `take_damage` (the `Hero` signature, so `SpellTargets.hurt`'s arity
# adaptation is exercised rather than bypassed).
#
# DECLARED properties, not metadata: `set()` on an undeclared property is a silent
# no-op in Godot 4, so a stub that merely pretended to have `hp` would make every
# assertion about health movement pass while measuring nothing.
#
# Leading underscore keeps `run_all_tests.py` from treating it as a suite.
extends Node2D

var hp: int = 100
var max_hp: int = 100
var velocity: Vector2 = Vector2.ZERO
## Every `take_damage` this stub received, for suites that need to prove a hit was
## SWALLOWED rather than merely undone.
var damage_log: Array[int] = []


func take_damage(amount: int) -> void:
	damage_log.append(amount)
	hp = maxi(hp - amount, 0)
