# Run: godot --headless --path godot-project --script tools/slice_test_status.gd
# Elemental ailments (StatusComponent): burn DoT, chill->freeze slow escalation,
# weaken damage amp, shock slow. Drives _process(delta) by hand (deterministic).
# Runs on the first _process frame (repo idiom) though StatusComponent has no
# autoload dependency — Elements/CombatVfx are plain class_name helpers.
extends SceneTree

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
	var failed: int = 0
	failed += _test_burn_ticks_damage()
	failed += _test_chill_then_freeze_slows()
	failed += _test_weaken_amplifies()
	failed += _test_shock_slows()
	if failed > 0:
		printerr("Status tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Status tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


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


func _test_burn_ticks_damage() -> int:
	var failed: int = 0
	var ctx: Dictionary = _make()
	var status: Node2D = ctx["status"]
	var enemy: StubEnemy = ctx["enemy"]
	status.apply(StatusScript.FIRE)
	failed += _expect(is_equal_approx(status.slow_factor(), 1.0), "burn does not slow")
	_drive(status, 1.0)
	failed += _expect(not enemy.dmg.is_empty(), "burn ticks damage over time")
	root.remove_child(enemy)
	enemy.free()
	return failed


func _test_chill_then_freeze_slows() -> int:
	var failed: int = 0
	var ctx: Dictionary = _make()
	var status: Node2D = ctx["status"]
	status.apply(StatusScript.ICE)
	var chilled: float = status.slow_factor()
	failed += _expect(chilled < 1.0 and chilled > 0.2, "chill slows but does not freeze")
	status.apply(StatusScript.ICE)  # second ice on a chilled target -> freeze
	var frozen: float = status.slow_factor()
	failed += _expect(frozen < chilled, "second ice freezes (stronger slow)")
	root.remove_child(ctx["enemy"])
	ctx["enemy"].free()
	return failed


func _test_weaken_amplifies() -> int:
	var failed: int = 0
	var ctx: Dictionary = _make()
	var status: Node2D = ctx["status"]
	status.apply(StatusScript.SHADOW)
	failed += _expect(status.damage_mult() > 1.0, "weaken amplifies incoming damage")
	_drive(status, StatusScript.WEAKEN_DURATION + 0.3)
	failed += _expect(is_equal_approx(status.damage_mult(), 1.0), "weaken expires back to 1.0")
	root.remove_child(ctx["enemy"])
	ctx["enemy"].free()
	return failed


func _test_shock_slows() -> int:
	var failed: int = 0
	var ctx: Dictionary = _make()
	var status: Node2D = ctx["status"]
	# No other enemies in range -> chain finds none, just the local stun.
	status.apply(StatusScript.LIGHTNING, false)
	failed += _expect(status.slow_factor() <= StatusScript.SHOCK_SLOW + 0.001, "shock stuns (heavy slow)")
	root.remove_child(ctx["enemy"])
	ctx["enemy"].free()
	return failed
