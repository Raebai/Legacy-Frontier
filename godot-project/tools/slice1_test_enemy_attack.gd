# Run: godot --headless --path godot-project --script tools/slice1_test_enemy_attack.gd
# Note: tests run on the first _process frame (not _init) because
# Enemy.gd references the Sfx autoload, and autoload globals are only
# registered with GDScript after the main loop is set up.
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
	failed += _test_brute_enters_windup_and_spawns_telegraph()
	failed += _test_strike_hits_stationary_hero_then_cooldown_gates()
	failed += _test_dashed_out_hero_dodges_the_strike()
	failed += _test_chaser_never_telegraphs_contact_preserved()
	if failed > 0:
		printerr("Slice1 enemy-attack tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 enemy-attack tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## Arena container + stub hero (in group "hero", added BEFORE the enemy so
## Enemy._ready finds it) + an Enemy with a real CharacterRig child.
## Engine physics ticks are disabled; each test drives _physics_process by hand.
func _setup(telegraphed: bool, hero_pos: Vector2, enemy_pos: Vector2) -> Dictionary:
	# Runtime load: compiles after autoload globals (Sfx) are registered.
	var enemy_script: GDScript = load(ENEMY_SCRIPT_PATH)
	var arena := Node2D.new()
	root.add_child(arena)
	var hero := StubHero.new()
	hero.add_to_group("hero")
	arena.add_child(hero)
	hero.global_position = hero_pos
	var enemy: CharacterBody2D = enemy_script.new()
	enemy.set("uses_telegraphed_attack", telegraphed)
	var rig: CharacterRig = RigScript.new()
	rig.name = "Rig"
	enemy.add_child(rig)
	# Real collision shape so move_and_slide has a body to sweep (mirrors
	# Enemy.tscn's 20x20 rect; a shapeless body would spam physics errors).
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
	arena.free()  # frees hero/enemy/telegraph children with it


func _find_telegraph(arena: Node2D) -> Telegraph:
	for child in arena.get_children():
		if child is Telegraph:
			return child
	return null


func _consts() -> Dictionary:
	return (load(ENEMY_SCRIPT_PATH) as GDScript).get_script_constant_map()


func _test_brute_enters_windup_and_spawns_telegraph() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero at 60 px: inside ATTACK_RANGE (78), outside contact range (22).
	var ctx: Dictionary = _setup(true, Vector2(60, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	failed += _expect(
		enemy.get("_attack_state") == states["WINDUP"],
		"brute in ATTACK_RANGE enters WINDUP"
	)
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	failed += _expect(tg != null, "WINDUP spawns a Telegraph in the arena")
	if tg != null:
		failed += _expect(
			tg.global_position == Vector2(60, 0),
			"telegraph snapshots the hero's position at windup start"
		)
	failed += _expect(
		hero.damage_calls.is_empty(),
		"no contact damage while winding up"
	)

	# Held windup ticks stay in WINDUP and still deal no contact damage.
	enemy._physics_process(TICK)
	enemy._physics_process(TICK)
	failed += _expect(
		enemy.get("_attack_state") == states["WINDUP"] and hero.damage_calls.is_empty(),
		"WINDUP holds (no chase, no contact) until the telegraph fires"
	)

	_teardown(ctx)
	return failed


func _test_strike_hits_stationary_hero_then_cooldown_gates() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	var ctx: Dictionary = _setup(true, Vector2(60, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)  # enter WINDUP, spawn the telegraph
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	failed += _expect(tg != null, "telegraph exists before the strike")
	if tg == null:
		_teardown(ctx)
		return failed

	# Hero stands still inside the circle -> eats the heavy hit.
	tg.advance(c["ATTACK_WINDUP"] + 0.05)
	failed += _expect(
		hero.damage_calls == [c["ATTACK_DAMAGE"]],
		"stationary hero takes ATTACK_DAMAGE exactly once"
	)
	failed += _expect(
		enemy.get("_attack_state") == states["RECOVER"],
		"enemy enters RECOVER after the strike"
	)

	# Recover elapses -> back to CHASE, but the cooldown gates a re-windup
	# even though the hero is still in ATTACK_RANGE.
	enemy._physics_process(c["ATTACK_RECOVER_TIME"] + 0.05)
	enemy._physics_process(TICK)
	failed += _expect(
		enemy.get("_attack_state") == states["CHASE"],
		"RECOVER returns to CHASE (cooldown blocks instant re-windup)"
	)

	_teardown(ctx)
	return failed


func _test_dashed_out_hero_dodges_the_strike() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	var ctx: Dictionary = _setup(true, Vector2(60, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)  # enter WINDUP; circle snapshotted at (60, 0)
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	failed += _expect(tg != null, "telegraph exists before the dodge")
	if tg == null:
		_teardown(ctx)
		return failed

	# Hero dashes out: 200 px from the snapshot, well past ATTACK_RADIUS (40).
	hero.global_position = Vector2(260, 0)
	tg.advance(c["ATTACK_WINDUP"] + 0.05)
	failed += _expect(
		hero.damage_calls.is_empty(),
		"hero outside ATTACK_RADIUS of the snapshot takes NO damage (dodged)"
	)
	failed += _expect(
		enemy.get("_attack_state") == states["RECOVER"],
		"missed strike still enters RECOVER"
	)

	_teardown(ctx)
	return failed


func _test_chaser_never_telegraphs_contact_preserved() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Chaser with the hero inside ATTACK_RANGE — must NOT wind up.
	var ctx: Dictionary = _setup(false, Vector2(60, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	for i in 5:
		enemy._physics_process(TICK)
	failed += _expect(
		enemy.get("_attack_state") == states["CHASE"],
		"chaser never enters WINDUP"
	)
	failed += _expect(
		_find_telegraph(ctx["arena"]) == null,
		"chaser never spawns a Telegraph"
	)

	# Pure contact behavior preserved: step into contact range -> touch damage.
	hero.global_position = enemy.global_position + Vector2(10, 0)
	enemy._physics_process(TICK)
	failed += _expect(
		hero.damage_calls == [enemy.get("touch_damage")],
		"chaser contact damage fires as before"
	)

	_teardown(ctx)
	return failed
