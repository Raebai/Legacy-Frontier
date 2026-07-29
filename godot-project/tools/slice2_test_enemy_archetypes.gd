# Run: godot --headless --path godot-project --script tools/slice2_test_enemy_archetypes.gd
# Enemy.gd references the Sfx autoload, so it is load()ed at runtime on the first
# _process frame (repo test-trap idiom). Engine physics is disabled per-node;
# each test drives _physics_process / Telegraph.advance by hand.
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
	"caster_windup_fires_dodgeable_bolt",
	"charger_line_telegraph_then_hit",
	"line_telegraph_fires_once",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ENEMY_SCRIPT_PATH: String = "res://scripts/combat/Enemy.gd"
const RigScript: GDScript = preload("res://scripts/combat/CharacterRig.gd")
const TICK: float = 1.0 / 60.0

var _ran: bool = false


class StubHero:
	extends Node2D
	var damage_calls: Array[int] = []
	func take_damage(amount: int) -> void:
		damage_calls.append(amount)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_caster_windup_fires_dodgeable_bolt()
	_test_charger_line_telegraph_then_hit()
	_test_line_telegraph_fires_once()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice2 enemy-archetype tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice2 enemy-archetype tests: all PASS")
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


func _consts() -> Dictionary:
	return (load(ENEMY_SCRIPT_PATH) as GDScript).get_script_constant_map()


func _setup(kind: int, hero_pos: Vector2, enemy_pos: Vector2) -> Dictionary:
	var enemy_script: GDScript = load(ENEMY_SCRIPT_PATH)
	var arena := Node2D.new()
	root.add_child(arena)
	var hero := StubHero.new()
	hero.add_to_group("hero")
	arena.add_child(hero)
	hero.global_position = hero_pos
	var enemy: CharacterBody2D = enemy_script.new()
	enemy.set("archetype", kind)
	var rig: CharacterRig = RigScript.new()
	rig.name = "Rig"
	enemy.add_child(rig)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 20)
	shape.shape = rect
	enemy.add_child(shape)
	arena.add_child(enemy)
	enemy.global_position = enemy_pos
	enemy.set_physics_process(false)
	return {"arena": arena, "hero": hero, "enemy": enemy}


func _teardown(ctx: Dictionary) -> void:
	var arena: Node2D = ctx["arena"]
	root.remove_child(arena)
	arena.free()


func _find_telegraph(arena: Node2D) -> Telegraph:
	for child in arena.get_children():
		if child is Telegraph:
			return child
	return null


# Duck-typed (NOT `is EnemyProjectile`): a static type ref would force
# EnemyProjectile.gd to compile at this test's own compile time — before the
# main loop registers the Sfx autoload it uses — and fail (the repo test-trap).
func _find_projectile(arena: Node2D) -> Node:
	for child in arena.get_children():
		if child.has_method("launch") and child.has_method("_check_hit"):
			return child
	return null


func _test_caster_windup_fires_dodgeable_bolt() -> void:
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero at 250px — inside the caster band [180, 320].
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CASTER"]), Vector2(250, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	_expect(enemy.get("_attack_state") == states["WINDUP"], "caster in-band enters WINDUP")
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	_expect(tg != null, "caster WINDUP spawns a telegraph tell")
	_expect(_find_projectile(ctx["arena"]) == null, "no bolt before the telegraph fires")

	if tg != null:
		tg.advance(float(c["CASTER_WINDUP"]) + 0.05)
	_expect(enemy.get("_attack_state") == states["RECOVER"], "caster enters RECOVER after firing")
	var proj: Node = _find_projectile(ctx["arena"])
	_expect(proj != null, "telegraph firing spawns an EnemyProjectile")
	if proj != null:
		proj.set_physics_process(false)
		# The bolt hits a hero standing on it (dodging it — moving away — would miss).
		hero.global_position = (proj as Node2D).global_position
		var hit: bool = proj._check_hit()
		_expect(hit, "bolt hits a hero within HIT_RADIUS")
		_expect(hero.damage_calls == [int(proj.get("DAMAGE"))], "bolt deals its DAMAGE once")

	_teardown(ctx)
	_completes("caster_windup_fires_dodgeable_bolt")


func _test_charger_line_telegraph_then_hit() -> void:
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero at 200px — inside CHARGE_RANGE (260).
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHARGER"]), Vector2(200, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	_expect(enemy.get("_attack_state") == states["WINDUP"], "charger in range enters WINDUP")
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	_expect(tg != null, "charger spawns a telegraph")
	if tg != null:
		_expect(tg.get("_shape") == Telegraph.Shape.LINE, "charger telegraph is a LINE")
		tg.advance(float(c["CHARGE_WINDUP"]) + 0.05)
	_expect(enemy.get("_attack_state") == states["CHARGING"], "charger begins CHARGING after the tell")

	# Put the hero right on the lane so the charge connects within a tick or two.
	hero.global_position = enemy.global_position + Vector2(20, 0)
	enemy._physics_process(TICK)
	_expect(hero.damage_calls == [int(c["CHARGE_DAMAGE"])], "charge hits the hero once for CHARGE_DAMAGE")

	# Charge times out -> RECOVER.
	enemy._physics_process(float(c["CHARGE_TIME"]) + 0.05)
	_expect(enemy.get("_attack_state") == states["RECOVER"], "charge ends in RECOVER")
	# Even multiple ticks on the hero deal no second hit (single-hit guard).
	enemy.set("_attack_state", states["CHARGING"])
	enemy.set("_charge_timer", float(c["CHARGE_TIME"]))
	enemy._physics_process(TICK)
	_expect(hero.damage_calls.size() == 1, "charge never double-hits the same hero")

	_teardown(ctx)
	_completes("charger_line_telegraph_then_hit")


func _test_line_telegraph_fires_once() -> void:
	var tg := Telegraph.new()
	root.add_child(tg)
	var fires: Array = []
	tg.fired.connect(func() -> void: fires.append(1))
	tg.start_line(300.0, 34.0, 0.0, 0.5)
	_expect(tg.get("_shape") == Telegraph.Shape.LINE, "start_line sets LINE shape")
	tg.advance(0.4)
	_expect(fires.is_empty(), "line telegraph has not fired mid-windup")
	tg.advance(0.15)
	_expect(fires.size() == 1, "line telegraph fires exactly once at windup end")
	_completes("line_telegraph_fires_once")
