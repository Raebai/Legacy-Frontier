# Run: godot --headless --path godot-project --script tools/slice_test_status.gd
# Elemental ailments (StatusComponent): burn DoT, chill->freeze slow escalation,
# weaken damage amp, shock slow. Drives _process(delta) by hand (deterministic).
# Runs on the first _process frame (repo idiom) though StatusComponent has no
# autoload dependency — Elements/CombatVfx are plain class_name helpers.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"burn_ticks_damage",
	"chill_then_freeze_slows",
	"weaken_amplifies",
	"shock_slows",
]

var _fails: int = 0
var _completed: Dictionary = {}

const StatusScript: GDScript = preload("res://scripts/combat/StatusComponent.gd")

var _ran: bool = false


class StubEnemy:
	extends Node2D
	var dmg: Array[int] = []
	# Matches Enemy.take_damage's optional element tint (DoT ticks pass a hue).
	func take_damage(amount: int, _tint: Color = Color(1.0, 1.0, 1.0, 0.0)) -> void:
		dmg.append(amount)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_burn_ticks_damage()
	_test_chill_then_freeze_slows()
	_test_weaken_amplifies()
	_test_shock_slows()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Status tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Status tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _make() -> Dictionary:
	var enemy := StubEnemy.new()
	enemy.add_to_group("enemy")
	root.add_child(enemy)
	var status: Node2D = StatusScript.new()
	enemy.add_child(status)
	return {"enemy": enemy, "status": status}


func _drive(status: Node2D, seconds: float, step: float = 0.1) -> void:
	var t: float = 0.0
	while t < seconds:
		status._process(step)
		t += step


func _test_burn_ticks_damage() -> void:
	var ctx: Dictionary = _make()
	var status: Node2D = ctx["status"]
	var enemy: StubEnemy = ctx["enemy"]
	status.apply(StatusScript.FIRE)
	_expect(is_equal_approx(status.slow_factor(), 1.0), "burn does not slow")
	_drive(status, 1.0)
	_expect(not enemy.dmg.is_empty(), "burn ticks damage over time")
	root.remove_child(enemy)
	enemy.free()
	_completes("burn_ticks_damage")


func _test_chill_then_freeze_slows() -> void:
	var ctx: Dictionary = _make()
	var status: Node2D = ctx["status"]
	status.apply(StatusScript.ICE)
	var chilled: float = status.slow_factor()
	_expect(chilled < 1.0 and chilled > 0.2, "chill slows but does not freeze")
	status.apply(StatusScript.ICE)  # second ice on a chilled target -> freeze
	var frozen: float = status.slow_factor()
	_expect(frozen < chilled, "second ice freezes (stronger slow)")
	root.remove_child(ctx["enemy"])
	ctx["enemy"].free()
	_completes("chill_then_freeze_slows")


func _test_weaken_amplifies() -> void:
	var ctx: Dictionary = _make()
	var status: Node2D = ctx["status"]
	status.apply(StatusScript.SHADOW)
	_expect(status.damage_mult() > 1.0, "weaken amplifies incoming damage")
	_drive(status, StatusScript.WEAKEN_DURATION + 0.3)
	_expect(is_equal_approx(status.damage_mult(), 1.0), "weaken expires back to 1.0")
	root.remove_child(ctx["enemy"])
	ctx["enemy"].free()
	_completes("weaken_amplifies")


func _test_shock_slows() -> void:
	var ctx: Dictionary = _make()
	var status: Node2D = ctx["status"]
	# No other enemies in range -> chain finds none, just the local stun.
	status.apply(StatusScript.LIGHTNING, false)
	_expect(status.slow_factor() <= StatusScript.SHOCK_SLOW + 0.001, "shock stuns (heavy slow)")
	root.remove_child(ctx["enemy"])
	ctx["enemy"].free()
	_completes("shock_slows")
