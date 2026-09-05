# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_elite_teardown.gd
#
# THE REPRODUCTION for the floor-10 crash:
#
#   E  _restore: Trying to assign invalid previously freed instance.
#      <GDScript Source>EliteHerald.gd:119 @ _restore()
#      <Stack Trace>   EliteHerald.gd:119 @ _restore()
#                      EliteHerald.gd:129 @ _exit_tree()
#
# This is a PROBE, not a suite -- it prints observations and asserts nothing. The
# regression guard that must stay green forever is tools/slice_test_rider_teardown.gd.
#
# THE SHAPE, measured rather than assumed (see probe_freed_semantics.gd):
#   * `freed == null`            -> TRUE   (so the repo's own "a freed Object is not
#                                           null" note in BossModRider is WRONG)
#   * `is_instance_valid(freed)` -> false
#   * `var e: Node = <freed>`    -> FAULTS with the exact error above
#
# So EliteHerald's guard on line 120 (`if e == null or not is_instance_valid(e)`) is
# UNREACHABLE: the STATICALLY TYPED assignment on line 119 faults first. And because a
# GDScript runtime error ABORTS the enclosing function, `_lifted.clear()` on line 124
# never runs either -- which means the crash is not only log spam, it also defeats the
# entire purpose of the `_exit_tree` hook ("the herald dying mid-surge must not leave
# the room permanently quickened"). Every surviving body stays buffed.
extends SceneTree

const HERALD: String = "res://scripts/combat/elitemods/EliteHerald.gd"

## A body just enemy-shaped enough for EliteHerald to lift: a Node2D in group "enemy"
## carrying the two fields the affix borrows, and deliberately WITHOUT `current_phase`
## (that method is how the herald spots a boss and skips it).
const STUB_SRC: String = """
extends Node2D
var hp: int = 40
var move_speed: float = 100.0
var _cd_speed: float = 1.0
"""

var _ran: bool = false


func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	_repro_real_path()
	_repro_typed_parameter()
	return true


func _stub(at: Vector2) -> Node2D:
	var gs := GDScript.new()
	gs.source_code = STUB_SRC
	gs.reload()
	var n := Node2D.new()
	n.set_script(gs)
	n.global_position = at
	n.add_to_group("enemy")
	return n


# ─────────────────────────────────────────────────────────── the reported crash
## Drives the REAL `_call_out` so `_lifted` is populated the way the game populates
## it, then frees a lifted body out from under the herald and tears the rider down --
## which is exactly what a floor transition does: the wave's bodies go first, the
## elite's rider leaves the tree after them.
func _repro_real_path() -> void:
	print("== REPRO 1: real _call_out, freed target, then teardown ==")
	var arena := Node2D.new()
	root.add_child(arena)

	var host_body: Node2D = _stub(Vector2(0.0, 0.0))
	arena.add_child(host_body)
	var victim: Node2D = _stub(Vector2(60.0, 0.0))
	arena.add_child(victim)

	var gs: GDScript = load(HERALD) as GDScript
	var rider: Node = gs.new()
	rider.name = "Elite_herald"
	rider.set("affix_id", "herald")
	host_body.add_child(rider)

	rider.call("_call_out")
	var lifted: Array = rider.get("_lifted")
	print("  _lifted after _call_out      -> ", lifted.size(), " (expect 1)")
	print("  victim move_speed lifted to  -> ", victim.get("move_speed"), " (base 100)")

	# THE TEARDOWN ORDER THAT BREAKS IT. The lifted body is gone before the rider is.
	victim.free()
	print("  victim freed. lifted[0]['n'] == null      -> ", lifted[0]["n"] == null)
	print("  lifted[0]['n'] is_instance_valid         -> ", is_instance_valid(lifted[0]["n"]))
	print("  --> removing rider; watch for the error:")
	host_body.remove_child(rider)          # fires _exit_tree -> _restore -> line 119
	print("  _lifted AFTER _restore       -> ", (rider.get("_lifted") as Array).size(),
		"  (0 = restore completed; 1 = it aborted and the room stays buffed)")

	rider.free()
	arena.free()


# ────────────────────────────────────────── the same opcode, one call frame over
## The identical fault reachable through a TYPED PARAMETER rather than a typed local.
## This is why `MagicCircle.offer(circle: MagicCircle, ...)` cannot defend itself: its
## `is_instance_valid(circle)` guard is on the first line of the body, and the
## parameter binding that faults happens before the body runs at all. Any rider that
## hands a stale node to a typed parameter owns the fix, not the callee.
func _repro_typed_parameter() -> void:
	print("== REPRO 2: typed PARAMETER binding (the MagicCircle.offer shape) ==")
	var n := Node2D.new()
	var box: Array = [n]
	n.free()
	print("  --> calling a func(x: Node2D) with a freed instance:")
	_takes_typed(box[0])
	print("  (if nothing printed from inside, the guard never ran)")


func _takes_typed(x: Node2D) -> void:
	if not is_instance_valid(x):
		print("  inside: guard ran, x invalid")
		return
	print("  inside: x valid")
