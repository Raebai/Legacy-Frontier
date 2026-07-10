# Run: godot --headless --path godot-project --script tools/slice2_test_enemy_archetypes.gd
# Enemy.gd references the Sfx autoload, so it is load()ed at runtime on the first
# _process frame (repo test-trap idiom). Engine physics is disabled per-node;
# each test drives _physics_process / Telegraph.advance by hand.
extends SceneTree

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
	var failed: int = 0
	failed += _test_caster_windup_fires_dodgeable_bolt()
	failed += _test_charger_line_telegraph_then_hit()
	failed += _test_line_telegraph_fires_once()
	if failed > 0:
		printerr("Slice2 enemy-archetype tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice2 enemy-archetype tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


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


func _test_caster_windup_fires_dodgeable_bolt() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero at 250px — inside the caster band [180, 320].
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CASTER"]), Vector2(250, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	failed += _expect(enemy.get("_attack_state") == states["WINDUP"], "caster in-band enters WINDUP")
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	failed += _expect(tg != null, "caster WINDUP spawns a telegraph tell")
	failed += _expect(_find_projectile(ctx["arena"]) == null, "no bolt before the telegraph fires")

	if tg != null:
		tg.advance(float(c["CASTER_WINDUP"]) + 0.05)
	failed += _expect(enemy.get("_attack_state") == states["RECOVER"], "caster enters RECOVER after firing")
	var proj: Node = _find_projectile(ctx["arena"])
	failed += _expect(proj != null, "telegraph firing spawns an EnemyProjectile")
	if proj != null:
		proj.set_physics_process(false)
		# The bolt hits a hero standing on it (dodging it — moving away — would miss).
		hero.global_position = (proj as Node2D).global_position
		var hit: bool = proj._check_hit()
		failed += _expect(hit, "bolt hits a hero within HIT_RADIUS")
		failed += _expect(hero.damage_calls == [int(proj.get("DAMAGE"))], "bolt deals its DAMAGE once")

	_teardown(ctx)
	return failed


func _test_charger_line_telegraph_then_hit() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero at 200px — inside CHARGE_RANGE (260).
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHARGER"]), Vector2(200, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	failed += _expect(enemy.get("_attack_state") == states["WINDUP"], "charger in range enters WINDUP")
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	failed += _expect(tg != null, "charger spawns a telegraph")
	if tg != null:
		failed += _expect(tg.get("_shape") == Telegraph.Shape.LINE, "charger telegraph is a LINE")
		tg.advance(float(c["CHARGE_WINDUP"]) + 0.05)
	failed += _expect(enemy.get("_attack_state") == states["CHARGING"], "charger begins CHARGING after the tell")

	# Put the hero right on the lane so the charge connects within a tick or two.
	hero.global_position = enemy.global_position + Vector2(20, 0)
	enemy._physics_process(TICK)
	failed += _expect(hero.damage_calls == [int(c["CHARGE_DAMAGE"])], "charge hits the hero once for CHARGE_DAMAGE")

	# Charge times out -> RECOVER.
	enemy._physics_process(float(c["CHARGE_TIME"]) + 0.05)
	failed += _expect(enemy.get("_attack_state") == states["RECOVER"], "charge ends in RECOVER")
	# Even multiple ticks on the hero deal no second hit (single-hit guard).
	enemy.set("_attack_state", states["CHARGING"])
	enemy.set("_charge_timer", float(c["CHARGE_TIME"]))
	enemy._physics_process(TICK)
	failed += _expect(hero.damage_calls.size() == 1, "charge never double-hits the same hero")

	_teardown(ctx)
	return failed


func _test_line_telegraph_fires_once() -> int:
	var failed: int = 0
	var tg := Telegraph.new()
	root.add_child(tg)
	var fires: Array = []
	tg.fired.connect(func() -> void: fires.append(1))
	tg.start_line(300.0, 34.0, 0.0, 0.5)
	failed += _expect(tg.get("_shape") == Telegraph.Shape.LINE, "start_line sets LINE shape")
	tg.advance(0.4)
	failed += _expect(fires.is_empty(), "line telegraph has not fired mid-windup")
	tg.advance(0.15)
	failed += _expect(fires.size() == 1, "line telegraph fires exactly once at windup end")
	return failed
