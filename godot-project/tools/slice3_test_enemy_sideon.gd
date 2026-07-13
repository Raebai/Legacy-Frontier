# Run: godot --headless --path godot-project --script tools/slice3_test_enemy_sideon.gd
# Enemy.gd references the Sfx autoload, so it is load()ed at runtime on the first
# _process frame (repo test-trap idiom). No platform exists in this harness, so
# is_on_floor() is always false — each test drives the directly-callable side-on
# seams (_apply_gravity / _physics_process / _wants_chase_jump) by hand instead
# of relying on real floor collision (unstepped physics never lands a body).
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
	failed += _test_gravity_helper()
	failed += _test_vertical_knockback_pop()
	failed += _test_horizontal_chase_intent()
	failed += _test_charger_lane_is_horizontal()
	failed += _test_jump_decision()
	failed += _test_leap_decision()
	failed += _test_leap_velocity_reaches_ledge()
	failed += _test_mage_windup_and_aoe()
	if failed > 0:
		printerr("Slice3 enemy side-on tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice3 enemy side-on tests: all PASS")
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


## Airborne (no platform in the harness): one gravity step pulls the enemy
## down by GRAVITY * delta; repeated steps saturate at MAX_FALL.
func _test_gravity_helper() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(500, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	enemy.velocity = Vector2.ZERO
	enemy._apply_gravity(0.1)
	failed += _expect(enemy.velocity.y > 0.0, "gravity pulls an airborne enemy down")
	failed += _expect(
		is_equal_approx(enemy.velocity.y, float(c["GRAVITY"]) * 0.1),
		"one gravity step adds GRAVITY * delta"
	)
	for _i in 60:
		enemy._apply_gravity(0.1)
	failed += _expect(
		is_equal_approx(enemy.velocity.y, float(c["MAX_FALL"])),
		"repeated gravity steps cap at MAX_FALL"
	)
	_teardown(ctx)
	return failed


## A hard hit with an upward component pops the enemy: apply_knockback folds
## the vertical part into velocity.y once, and the pop survives a gravity step.
func _test_vertical_knockback_pop() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(500, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	enemy.velocity = Vector2.ZERO
	enemy.apply_knockback(Vector2(180.0, -400.0))
	failed += _expect(
		is_equal_approx(enemy.velocity.y, -400.0),
		"vertical knockback lands as a one-shot upward impulse into velocity.y"
	)
	enemy._apply_gravity(TICK)
	failed += _expect(enemy.velocity.y < 0.0, "the pop is still rising after one gravity tick")
	_teardown(ctx)
	return failed


## The default chase drives velocity.x toward the hero's side (and gravity
## still applies inside the chase path). 200px away: no touch, no telegraph.
func _test_horizontal_chase_intent() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(200, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	failed += _expect(enemy.velocity.x > 0.0, "chaser moves right toward a hero on its right")
	failed += _expect(enemy.velocity.y > 0.0, "airborne chaser falls during the chase (gravity applied)")

	hero.global_position = Vector2(enemy.global_position.x - 200.0, enemy.global_position.y)
	enemy._physics_process(TICK)
	failed += _expect(enemy.velocity.x < 0.0, "chaser moves left toward a hero on its left")

	_teardown(ctx)
	return failed


## The charge is a horizontal rocket: even against an off-axis hero, the lane
## locked at windup is a flat unit vector toward the hero's side.
func _test_charger_lane_is_horizontal() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero 200 right + 40 up: dist ~204 is inside CHARGE_RANGE (260).
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHARGER"]), Vector2(200, -40), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]

	enemy._physics_process(TICK)
	failed += _expect(enemy.get("_attack_state") == states["WINDUP"], "charger in range enters WINDUP")
	var lane: Vector2 = enemy.get("_charge_dir")
	failed += _expect(
		lane.y == 0.0 and lane.x == 1.0,
		"charge lane is a horizontal unit vector toward the hero (no diagonal)"
	)

	_teardown(ctx)
	return failed


## Pure jump decision (_wants_chase_jump excludes is_on_floor by design so it
## is testable without stepped physics; _try_chase_jump adds the floor gate).
func _test_jump_decision() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	# Hero 120 above (> JUMP_TRIGGER_HEIGHT 60) and 100 near on x (< 260).
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(100, -120), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy.set("_jump_cd", 0.0)
	failed += _expect(enemy._wants_chase_jump(), "hero well above + near on x -> wants to chase-jump")

	hero.global_position = Vector2(100, -20)
	failed += _expect(not enemy._wants_chase_jump(), "hero barely above (< JUMP_TRIGGER_HEIGHT) -> no jump")

	hero.global_position = Vector2(400, -120)
	failed += _expect(not enemy._wants_chase_jump(), "hero above but too far horizontally -> no jump")

	hero.global_position = Vector2(100, 120)
	failed += _expect(not enemy._wants_chase_jump(), "hero below -> no jump")

	hero.global_position = Vector2(100, -120)
	enemy.set("_jump_cd", 0.5)
	failed += _expect(not enemy._wants_chase_jump(), "jump cooldown still running -> no jump")

	_teardown(ctx)
	return failed


## LEAP decision: a hero on a HIGH ledge (past the fixed hop's ~90px reach) and
## roughly under/near on x triggers a leap; too-low / too-far / on-cooldown don't.
func _test_leap_decision() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	# Hero 180 up (> LEAP_MIN_HEIGHT 105) and 120 near on x (< 400).
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(120, -180), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy.set("_leap_cd", 0.0)
	failed += _expect(enemy._wants_leap(), "hero on a high ledge, near on x -> wants to leap")

	hero.global_position = Vector2(120, -70)
	failed += _expect(not enemy._wants_leap(), "hero only a hop above (< LEAP_MIN_HEIGHT) -> no leap")

	hero.global_position = Vector2(600, -180)
	failed += _expect(not enemy._wants_leap(), "hero high but too far on x -> no leap")

	hero.global_position = Vector2(120, -180)
	enemy.set("_leap_cd", 1.0)
	failed += _expect(not enemy._wants_leap(), "leap cooldown running -> no leap")

	_teardown(ctx)
	return failed


## The ballistic solve actually CLEARS the target height: the launch apex above
## the start (v.y^2 / 2g) must reach the ledge, the launch is upward, carries
## toward the target, and the horizontal is capped.
func _test_leap_velocity_reaches_ledge() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(300, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var g: float = float(c["GRAVITY"])
	var ledge_h: float = 173.0
	var v: Vector2 = enemy.compute_leap_velocity(Vector2.ZERO, Vector2(140.0, -ledge_h))
	failed += _expect(v.y < 0.0, "leap launches upward")
	var apex: float = (v.y * v.y) / (2.0 * g)
	failed += _expect(apex >= ledge_h, "leap apex clears the target ledge height (%.0f >= %.0f)" % [apex, ledge_h])
	failed += _expect(v.x > 0.0, "leap carries toward a target on the right")
	failed += _expect(absf(v.x) <= float(c["LEAP_MAX_SPEED"]) + 0.01, "horizontal launch is capped")
	_teardown(ctx)
	return failed


## MAGE: in-band it telegraphs a ground ZONE at the hero's snapshot spot, then the
## tell fires a BlastSpell configured to hurt group "hero" — the hero takes the AoE.
func _test_mage_windup_and_aoe() -> int:
	var failed: int = 0
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero 300px right — inside the MAGE band [210, 380].
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["MAGE"]), Vector2(300, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	failed += _expect(enemy.get("_attack_state") == states["WINDUP"], "mage in-band enters WINDUP")
	var tg: Telegraph = null
	for child in (ctx["arena"] as Node2D).get_children():
		if child is Telegraph:
			tg = child
			break
	failed += _expect(tg != null, "mage WINDUP spawns a ground-zone telegraph")
	if tg != null:
		failed += _expect(
			tg.global_position == hero.global_position,
			"mage AoE zone is snapshot at the hero's position (dodge OUT of it)"
		)
		tg.advance(float(c["MAGE_WINDUP"]) + 0.05)
	failed += _expect(enemy.get("_attack_state") == states["RECOVER"], "mage enters RECOVER after casting")
	failed += _expect(
		hero.damage_calls.has(int(c["MAGE_AOE_DAMAGE"])),
		"the hero standing in the marked zone takes the MAGE AoE damage"
	)
	_teardown(ctx)
	return failed
