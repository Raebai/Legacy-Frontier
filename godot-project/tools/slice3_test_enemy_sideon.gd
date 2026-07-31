# Run: godot --headless --path godot-project --script tools/slice3_test_enemy_sideon.gd
# Enemy.gd references the Sfx autoload, so it is load()ed at runtime on the first
# _process frame (repo test-trap idiom). No platform exists in this harness, so
# is_on_floor() is always false — each test drives the directly-callable side-on
# seams (_apply_gravity / _physics_process / _wants_chase_jump) by hand instead
# of relying on real floor collision (unstepped physics never lands a body).
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
	"gravity_helper",
	"vertical_knockback_pop",
	"horizontal_chase_intent",
	"charger_lane_is_horizontal",
	"jump_decision",
	"leap_decision",
	"leap_velocity_reaches_ledge",
	"mage_windup_and_aoe",
	"pounce_closes_a_flat_gap",
	"recover_walks_back_in",
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
	_test_gravity_helper()
	_test_vertical_knockback_pop()
	_test_horizontal_chase_intent()
	_test_charger_lane_is_horizontal()
	_test_jump_decision()
	_test_leap_decision()
	_test_leap_velocity_reaches_ledge()
	_test_mage_windup_and_aoe()
	_test_pounce_closes_a_flat_gap()
	_test_recover_walks_back_in()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice3 enemy side-on tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice3 enemy side-on tests: all PASS")
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


## Airborne (no platform in the harness): one gravity step pulls the enemy
## down by GRAVITY * delta; repeated steps saturate at MAX_FALL.
func _test_gravity_helper() -> void:
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(500, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	enemy.velocity = Vector2.ZERO
	enemy._apply_gravity(0.1)
	_expect(enemy.velocity.y > 0.0, "gravity pulls an airborne enemy down")
	_expect(
		is_equal_approx(enemy.velocity.y, float(c["GRAVITY"]) * 0.1),
		"one gravity step adds GRAVITY * delta"
	)
	for _i in 60:
		enemy._apply_gravity(0.1)
	_expect(
		is_equal_approx(enemy.velocity.y, float(c["MAX_FALL"])),
		"repeated gravity steps cap at MAX_FALL"
	)
	_teardown(ctx)
	_completes("gravity_helper")


## A hard hit with an upward component pops the enemy: apply_knockback folds
## the vertical part into velocity.y once, and the pop survives a gravity step.
func _test_vertical_knockback_pop() -> void:
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(500, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	enemy.velocity = Vector2.ZERO
	# apply_knockback scales the impulse by the global knockback_mult (Tuning);
	# assert against the same source so the invariant tracks the tuning knob.
	var kb_mult: float = enemy._knockback_mult()
	enemy.apply_knockback(Vector2(180.0, -400.0))
	_expect(
		is_equal_approx(enemy.velocity.y, -400.0 * kb_mult),
		"vertical knockback lands as a one-shot upward impulse into velocity.y (x knockback_mult)"
	)
	enemy._apply_gravity(TICK)
	_expect(enemy.velocity.y < 0.0, "the pop is still rising after one gravity tick")
	_teardown(ctx)
	_completes("vertical_knockback_pop")


## The default chase drives velocity.x toward the hero's side (and gravity
## still applies inside the chase path). 200px away: no touch, no telegraph.
func _test_horizontal_chase_intent() -> void:
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(200, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	_expect(enemy.velocity.x > 0.0, "chaser moves right toward a hero on its right")
	_expect(enemy.velocity.y > 0.0, "airborne chaser falls during the chase (gravity applied)")

	hero.global_position = Vector2(enemy.global_position.x - 200.0, enemy.global_position.y)
	enemy._physics_process(TICK)
	_expect(enemy.velocity.x < 0.0, "chaser moves left toward a hero on its left")

	_teardown(ctx)
	_completes("horizontal_chase_intent")


## The charge is a horizontal rocket: even against an off-axis hero, the lane
## locked at windup is a flat unit vector toward the hero's side.
func _test_charger_lane_is_horizontal() -> void:
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero 200 right + 40 up: dist ~204 is inside CHARGE_RANGE (260).
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHARGER"]), Vector2(200, -40), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]

	enemy._physics_process(TICK)
	_expect(enemy.get("_attack_state") == states["WINDUP"], "charger in range enters WINDUP")
	var lane: Vector2 = enemy.get("_charge_dir")
	_expect(
		lane.y == 0.0 and lane.x == 1.0,
		"charge lane is a horizontal unit vector toward the hero (no diagonal)"
	)

	_teardown(ctx)
	_completes("charger_lane_is_horizontal")


## Pure jump decision (_wants_chase_jump excludes is_on_floor by design so it
## is testable without stepped physics; _try_chase_jump adds the floor gate).
func _test_jump_decision() -> void:
	var c: Dictionary = _consts()
	# Hero 120 above (> JUMP_TRIGGER_HEIGHT 60) and 100 near on x (< 260).
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(100, -120), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy.set("_jump_cd", 0.0)
	_expect(enemy._wants_chase_jump(), "hero well above + near on x -> wants to chase-jump")

	hero.global_position = Vector2(100, -20)
	_expect(not enemy._wants_chase_jump(), "hero barely above (< JUMP_TRIGGER_HEIGHT) -> no jump")

	hero.global_position = Vector2(400, -120)
	_expect(not enemy._wants_chase_jump(), "hero above but too far horizontally -> no jump")

	hero.global_position = Vector2(100, 120)
	_expect(not enemy._wants_chase_jump(), "hero below -> no jump")

	hero.global_position = Vector2(100, -120)
	enemy.set("_jump_cd", 0.5)
	_expect(not enemy._wants_chase_jump(), "jump cooldown still running -> no jump")

	_teardown(ctx)
	_completes("jump_decision")


## LEAP decision: a hero on a HIGH ledge (past the fixed hop's ~90px reach) and
## roughly under/near on x triggers a leap; too-low / too-far / on-cooldown don't.
func _test_leap_decision() -> void:
	var c: Dictionary = _consts()
	# Hero 180 up (> LEAP_MIN_HEIGHT 105) and 120 near on x (< 400).
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(120, -180), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy.set("_leap_cd", 0.0)
	_expect(enemy._wants_leap(), "hero on a high ledge, near on x -> wants to leap")

	hero.global_position = Vector2(120, -70)
	_expect(not enemy._wants_leap(), "hero only a hop above (< LEAP_MIN_HEIGHT) -> no leap")

	hero.global_position = Vector2(600, -180)
	_expect(not enemy._wants_leap(), "hero high but too far on x -> no leap")

	hero.global_position = Vector2(120, -180)
	enemy.set("_leap_cd", 1.0)
	_expect(not enemy._wants_leap(), "leap cooldown running -> no leap")

	_teardown(ctx)
	_completes("leap_decision")


## The ballistic solve actually CLEARS the target height: the launch apex above
## the start (v.y^2 / 2g) must reach the ledge, the launch is upward, carries
## toward the target, and the horizontal is capped.
func _test_leap_velocity_reaches_ledge() -> void:
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["CHASER"]), Vector2(300, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var g: float = float(c["GRAVITY"])
	var ledge_h: float = 173.0
	var v: Vector2 = enemy.compute_leap_velocity(Vector2.ZERO, Vector2(140.0, -ledge_h))
	_expect(v.y < 0.0, "leap launches upward")
	var apex: float = (v.y * v.y) / (2.0 * g)
	_expect(apex >= ledge_h, "leap apex clears the target ledge height (%.0f >= %.0f)" % [apex, ledge_h])
	_expect(v.x > 0.0, "leap carries toward a target on the right")
	_expect(absf(v.x) <= float(c["LEAP_MAX_SPEED"]) + 0.01, "horizontal launch is capped")
	_teardown(ctx)
	_completes("leap_velocity_reaches_ledge")


## MAGE: in-band it telegraphs a ground ZONE at the hero's snapshot spot, then the
## tell fires a BlastSpell configured to hurt group "hero" — the hero takes the AoE.
func _test_mage_windup_and_aoe() -> void:
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero 300px right — inside the MAGE band [210, 380].
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["MAGE"]), Vector2(300, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]

	enemy._physics_process(TICK)
	_expect(enemy.get("_attack_state") == states["WINDUP"], "mage in-band enters WINDUP")
	var tg: Telegraph = null
	for child in (ctx["arena"] as Node2D).get_children():
		if child is Telegraph:
			tg = child
			break
	_expect(tg != null, "mage WINDUP spawns a ground-zone telegraph")
	if tg != null:
		_expect(
			tg.global_position == hero.global_position,
			"mage AoE zone is snapshot at the hero's position (dodge OUT of it)"
		)
		tg.advance(float(c["MAGE_WINDUP"]) + 0.05)
	_expect(enemy.get("_attack_state") == states["RECOVER"], "mage enters RECOVER after casting")
	_expect(
		hero.damage_calls.has(int(c["MAGE_AOE_DAMAGE"])),
		"the hero standing in the marked zone takes the MAGE AoE damage"
	)
	_teardown(ctx)
	_completes("mage_windup_and_aoe")


# ══════════════════════════════════════════════════════════════ AGGRESSION
## THE POUNCE. The leap system solves a VERTICAL problem — reaching a hero on a
## ~170px ledge — and the tower arena is a flat 960x480 room with no ledges, so
## on every floor of the actual game that solver was unreachable code. The same
## ballistic launch closes a horizontal gap, which is what turns a chaser that has
## fallen behind from a jogging silhouette into a threat that commits.
func _test_pounce_closes_a_flat_gap() -> void:
	var c: Dictionary = _consts()
	var arch: Dictionary = c["Archetype"] as Dictionary
	# Hero 300px away on a FLAT floor (same y) — no height for _wants_leap to use.
	var ctx: Dictionary = _setup(int(arch["CHASER"]), Vector2(300, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var hero: StubHero = ctx["hero"]
	enemy.set("_leap_cd", 0.0)
	_expect(not enemy._wants_leap(), "a FLAT room never triggers the ledge leap (that was the bug)")
	_expect(enemy._wants_pounce(), "...but a chaser left behind on the flat DOES pounce")

	hero.global_position = Vector2(80, 0)
	_expect(not enemy._wants_pounce(), "close enough to just run at you -> no pounce")
	hero.global_position = Vector2(900, 0)
	_expect(not enemy._wants_pounce(), "absurdly far -> no pounce (the arc stops reading)")
	hero.global_position = Vector2(300, 0)
	enemy.set("_leap_cd", 1.0)
	_expect(not enemy._wants_pounce(), "pounce cooldown running -> no pounce")
	_teardown(ctx)

	# ...and it is archetype-gated: a BRUTE springing across the room would throw
	# away the readable slow-heavy silhouette its whole telegraph depends on.
	var ctx2: Dictionary = _setup(int(arch["BRUTE"]), Vector2(300, 0), Vector2.ZERO)
	var brute: CharacterBody2D = ctx2["enemy"]
	brute.set("_leap_cd", 0.0)
	_expect(not brute._wants_pounce(), "a BRUTE does not pounce")
	_teardown(ctx2)

	# The launch itself carries toward the target rather than straight up.
	var ctx3: Dictionary = _setup(int(arch["ASSASSIN"]), Vector2(300, 0), Vector2.ZERO)
	var assassin: CharacterBody2D = ctx3["enemy"]
	assassin.set("_leap_cd", 0.0)
	_expect(assassin._wants_pounce(), "an ASSASSIN pounces too")
	var v: Vector2 = assassin.compute_leap_velocity(Vector2.ZERO, Vector2(300.0, 0.0))
	_expect(v.x > 0.0, "the pounce carries toward a hero on the right")
	_expect(v.y < 0.0, "...on an arc, not a slide")
	_teardown(ctx3)
	_completes("pounce_closes_a_flat_gap")


## RECOVER used to ROOT an enemy in place. With a cooldown on top, a brute spent
## most of a fight standing still looking at you — dead air with legs, and a room
## full of them is a room where nothing is happening. Recovery now closes ground
## (slower than a chase, so the stagger still reads), while a KITER recovers
## BACKWARDS because retreating out of reach is its entire grammar.
func _test_recover_walks_back_in() -> void:
	var c: Dictionary = _consts()
	var arch: Dictionary = c["Archetype"] as Dictionary
	var states: Dictionary = c["AttackState"] as Dictionary
	_expect(float(c["RECOVER_DRIVE"]) > 0.0, "recovery has a drive at all")
	_expect(float(c["RECOVER_DRIVE"]) < 1.0, "...but slower than a chase, so it still reads as a stagger")

	# Melee: hero to the RIGHT, so recovery drives right (toward it).
	var ctx: Dictionary = _setup(int(arch["BRUTE"]), Vector2(300, 0), Vector2.ZERO)
	var brute: CharacterBody2D = ctx["enemy"]
	brute.set("_attack_state", int(states["RECOVER"]))
	brute.set("_recover_timer", 1.0)
	brute._process_recover(TICK)
	_expect(brute.velocity.x > 0.0,
		"a recovering brute walks BACK IN toward the hero (got %.1f)" % brute.velocity.x)
	_teardown(ctx)

	# Kiter: hero to the RIGHT, so recovery drives LEFT (away).
	var ctx2: Dictionary = _setup(int(arch["CASTER"]), Vector2(300, 0), Vector2.ZERO)
	var caster: CharacterBody2D = ctx2["enemy"]
	caster.set("_attack_state", int(states["RECOVER"]))
	caster.set("_recover_timer", 1.0)
	caster._process_recover(TICK)
	_expect(caster.velocity.x < 0.0,
		"a recovering CASTER backs off instead (got %.1f)" % caster.velocity.x)
	_teardown(ctx2)

	# The kite strafe: in-band with nothing to do, a kiter drifts rather than
	# standing at parade rest — and the drift reverses, so it circles.
	var ctx3: Dictionary = _setup(int(arch["MAGE"]), Vector2(240, 0), Vector2.ZERO)
	var mage: CharacterBody2D = ctx3["enemy"]
	var first: float = mage._kite_strafe(0.01)
	_expect(absf(first) > 0.0, "an in-band kiter drifts instead of freezing")
	var flipped: float = mage._kite_strafe(float(c["KITE_STRAFE_PERIOD"]) + 0.01)
	_expect(signf(flipped) != signf(first), "...and the drift reverses, so it circles for an angle")
	_teardown(ctx3)
	_completes("recover_walks_back_in")
