# Run: godot --headless --path godot-project --script tools/slice1_test_telegraph.gd
# Note: tests run on the first _process frame (not _init) because
# BlastSpell.gd references the Sfx autoload, and autoload globals are only
# registered with GDScript after the main loop is set up.
extends SceneTree

const TelegraphScript: GDScript = preload("res://scripts/combat/Telegraph.gd")
const BLAST_SCRIPT_PATH: String = "res://scripts/combat/BlastSpell.gd"

var _ran: bool = false


class StubEnemy:
	extends CharacterBody2D

	var damage_calls: Array[int] = []
	var knockback: Vector2 = Vector2.ZERO

	func take_damage(amount: int) -> void:
		damage_calls.append(amount)

	# Mirrors Enemy.apply_knockback — the real knockback path (a decaying
	# impulse added to chase velocity, not a direct velocity write).
	func apply_knockback(impulse: Vector2) -> void:
		knockback = impulse


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_telegraph_fires_once_after_windup()
	failed += _test_telegraph_fades_then_frees()
	failed += _test_blast_damage_radius_and_knockback()
	if failed > 0:
		printerr("Slice1 telegraph tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 telegraph tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_telegraph_fires_once_after_windup() -> int:
	var failed: int = 0
	var tg: Telegraph = TelegraphScript.new()
	root.add_child(tg)
	var fires: Array = [0]
	tg.fired.connect(func() -> void: fires[0] += 1)

	tg.start(80.0, 0.5)
	tg.advance(0.4)
	failed += _expect(fires[0] == 0, "not fired at 0.4s of a 0.5s windup")
	tg.advance(0.15)  # 0.55s total — past the windup
	failed += _expect(fires[0] == 1, "fired once past windup")
	tg.advance(0.05)  # 0.60s total — still inside the fade window
	failed += _expect(fires[0] == 1, "fired exactly once (no re-fire)")
	failed += _expect(not tg.is_queued_for_deletion(), "alive during post-fire fade")

	root.remove_child(tg)
	tg.free()
	return failed


func _test_telegraph_fades_then_frees() -> int:
	var failed: int = 0
	var tg: Telegraph = TelegraphScript.new()
	root.add_child(tg)

	tg.start(80.0, 0.5)
	tg.advance(0.5)  # fire
	tg.advance(0.2)  # past the 0.15s fade window
	failed += _expect(
		tg.is_queued_for_deletion(), "queue_free after fire + fade elapse"
	)
	return failed


func _test_blast_damage_radius_and_knockback() -> int:
	var failed: int = 0
	# Runtime load: compiles after autoload globals (Sfx) are registered.
	var blast_script: GDScript = load(BLAST_SCRIPT_PATH)
	failed += _expect(blast_script != null, "BlastSpell.gd loads")
	if blast_script == null:
		return failed
	var damage: int = blast_script.get_script_constant_map().get("DAMAGE", 0)

	var blast: Node2D = blast_script.new()
	root.add_child(blast)
	blast.global_position = Vector2.ZERO

	var near := StubEnemy.new()
	near.add_to_group("enemy")
	root.add_child(near)
	near.global_position = Vector2(60, 0)  # inside BLAST_RADIUS (92)

	var far := StubEnemy.new()
	far.add_to_group("enemy")
	root.add_child(far)
	far.global_position = Vector2(300, 0)  # outside BLAST_RADIUS

	blast._apply_blast_damage()

	failed += _expect(
		near.damage_calls.size() == 1 and near.damage_calls[0] == damage,
		"enemy inside radius takes DAMAGE exactly once"
	)
	failed += _expect(far.damage_calls.is_empty(), "enemy outside radius untouched")
	failed += _expect(near.knockback.x > 0.0, "inside enemy knocked outward (+x)")
	failed += _expect(far.knockback == Vector2.ZERO, "outside enemy gets no knockback")

	root.remove_child(near)
	root.remove_child(far)
	root.remove_child(blast)
	near.free()
	far.free()
	blast.free()
	return failed
