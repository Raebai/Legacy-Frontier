# Run: godot --headless --path godot-project --script tools/slice1_test_telegraph.gd
# Note: tests run on the first _process frame (not _init) because
# BlastSpell.gd references the Sfx autoload, and autoload globals are only
# registered with GDScript after the main loop is set up.
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
	"telegraph_fires_once_after_windup",
	"telegraph_fades_then_frees",
	"blast_damage_radius_and_knockback",
]

var _fails: int = 0
var _completed: Dictionary = {}

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
	_test_telegraph_fires_once_after_windup()
	_test_telegraph_fades_then_frees()
	_test_blast_damage_radius_and_knockback()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 telegraph tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 telegraph tests: all PASS")
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


func _test_telegraph_fires_once_after_windup() -> void:
	var tg: Telegraph = TelegraphScript.new()
	root.add_child(tg)
	var fires: Array = [0]
	tg.fired.connect(func() -> void: fires[0] += 1)

	tg.start(80.0, 0.5)
	tg.advance(0.4)
	_expect(fires[0] == 0, "not fired at 0.4s of a 0.5s windup")
	tg.advance(0.15)  # 0.55s total — past the windup
	_expect(fires[0] == 1, "fired once past windup")
	tg.advance(0.05)  # 0.60s total — still inside the fade window
	_expect(fires[0] == 1, "fired exactly once (no re-fire)")
	_expect(not tg.is_queued_for_deletion(), "alive during post-fire fade")

	root.remove_child(tg)
	tg.free()
	_completes("telegraph_fires_once_after_windup")


func _test_telegraph_fades_then_frees() -> void:
	var tg: Telegraph = TelegraphScript.new()
	root.add_child(tg)

	tg.start(80.0, 0.5)
	tg.advance(0.5)  # fire
	tg.advance(0.2)  # past the 0.15s fade window
	_expect(
		tg.is_queued_for_deletion(), "queue_free after fire + fade elapse"
	)
	_completes("telegraph_fades_then_frees")


func _test_blast_damage_radius_and_knockback() -> void:
	# Runtime load: compiles after autoload globals (Sfx) are registered.
	var blast_script: GDScript = load(BLAST_SCRIPT_PATH)
	_expect(blast_script != null, "BlastSpell.gd loads")
	if blast_script == null:
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
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

	_expect(
		near.damage_calls.size() == 1 and near.damage_calls[0] == damage,
		"enemy inside radius takes DAMAGE exactly once"
	)
	_expect(far.damage_calls.is_empty(), "enemy outside radius untouched")
	_expect(near.knockback.x > 0.0, "inside enemy knocked outward (+x)")
	_expect(far.knockback == Vector2.ZERO, "outside enemy gets no knockback")

	root.remove_child(near)
	root.remove_child(far)
	root.remove_child(blast)
	near.free()
	far.free()
	blast.free()
	_completes("blast_damage_radius_and_knockback")
