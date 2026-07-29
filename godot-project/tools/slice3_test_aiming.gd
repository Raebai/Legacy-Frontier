# Run: godot --headless --path godot-project --script tools/slice3_test_aiming.gd
#
# This suite used to prove the soft-aim forgiveness cone (Targeting.assisted_aim)
# bent a shot toward a nearby enemy. That cone is gone: the locked rule is no
# auto-aim and no homing, because a cone that quietly corrects a near-miss steals
# from BOTH sides — the shooter's aim and the target's dodge.
#
# The file is kept (and inverted) rather than deleted because the structural guard
# in slice0_test_targeting.gd can only catch aim assist coming back under the OLD
# names. This one is behavioural: it fires real abilities past a real off-axis
# enemy and insists the projectile goes exactly where the player pointed. That
# catches assistance reintroduced inline, or under any new name.
#
# Runs on the first _process frame (not _init) because Hero references autoloads
# that only register once the main loop is up.
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
	"bolt_goes_exactly_where_you_point",
	"bolt_ignores_enemy_behind_you",
	"parry_returns_along_your_aim",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const PROJ_SCRIPT_PATH: String = "res://scripts/combat/EnemyProjectile.gd"
const MAGE: int = 0  # Hero.HeroClass.MAGE — single-shot bolt, no burst spread
## How far off the aim line the bait enemy sits. Comfortably inside the range and
## cone the deleted assist used (420 px / dot 0.95), so any surviving assist would
## visibly bend the shot toward it.
const BAIT_OFFSET: Vector2 = Vector2(150.0, 60.0)
## Direction tolerance. A bent shot would be degrees off; this only absorbs float
## noise from normalising.
const DIR_EPSILON: float = 0.001

var _ran: bool = false


## Minimal enemy stand-in: in the "enemy" group, which is all the aim path ever
## queried. No full Enemy scene needed to prove a shot ignores it.
class EnemyStub extends Node2D:
	func take_damage(_amount: int) -> void:
		pass
	func apply_knockback(_impulse: Vector2) -> void:
		pass


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_bolt_goes_exactly_where_you_point()
	_test_bolt_ignores_enemy_behind_you()
	_test_parry_returns_along_your_aim()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice3 manual-aim tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice3 manual-aim tests: all PASS")
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


func _make_hero(pos: Vector2) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.configure_class(MAGE)
	hero.global_position = pos
	return hero


func _make_bait(pos: Vector2) -> Node2D:
	var e := EnemyStub.new()
	e.add_to_group("enemy")
	root.add_child(e)
	e.global_position = pos
	return e


## Fire the primary and return the direction the spawned bolt actually flew, found
## by diffing the arena's children. Read `_dir`, never the transform: spell nodes
## park at the arena origin and draw in world coordinates, so their position says
## nothing about where they are going.
func _fire_and_read_dir(hero: CharacterBody2D, aim: Vector2) -> Vector2:
	var before: Array[Node] = root.get_children()
	hero._aim_dir = aim.normalized()
	hero._cast_cooldown_timer = 0.0
	hero._primary_bolt()
	for child: Node in root.get_children():
		if before.has(child):
			continue
		var d: Variant = child.get("_dir")
		if d is Vector2:
			return d
	return Vector2.ZERO


func _test_bolt_goes_exactly_where_you_point() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(1000, 1000))
	_make_bait(hero.global_position + BAIT_OFFSET)
	var aim: Vector2 = Vector2.RIGHT
	var got: Vector2 = _fire_and_read_dir(hero, aim)
	_expect(got != Vector2.ZERO, "the primary actually spawned a bolt")
	# The bait sits down-and-right of the aim line. Assist would have tilted the
	# shot toward it; a manual shot is dead flat along the aim.
	_expect(
		got.distance_to(aim) < DIR_EPSILON,
		"bolt flies exactly along the aim, un-bent by a nearby enemy (got %s)" % got)
	_completes("bolt_goes_exactly_where_you_point")


## The mirror case: an enemy the player is pointing AWAY from must not turn the
## shot around. Catches an assist that ignores the forgiveness cone entirely.
func _test_bolt_ignores_enemy_behind_you() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(2000, 2000))
	_make_bait(hero.global_position + Vector2(-40.0, 0.0))
	var aim: Vector2 = Vector2.RIGHT
	var got: Vector2 = _fire_and_read_dir(hero, aim)
	_expect(got.x > 0.0, "bolt still flies forward with an enemy at your back")
	_expect(
		got.distance_to(aim) < DIR_EPSILON,
		"bolt is unaffected by an enemy behind the aim (got %s)" % got)
	_completes("bolt_ignores_enemy_behind_you")


## A parried bolt leaves along the SHIELD'S facing — i.e. the player's aim — not at
## whichever enemy happens to be closest. Timing the window is one skill; pointing
## the return is the second. Redirecting at the nearest enemy made the parry a
## homing missile that only asked for the timing.
func _test_parry_returns_along_your_aim() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(3000, 3000))
	# A tempting target dead to the right; the player is aiming straight UP.
	_make_bait(hero.global_position + Vector2(120.0, 0.0))
	hero._aim_dir = Vector2.UP
	hero._try_parry_start()
	_expect(hero.is_parrying(), "the parry window opened")
	var proj: Node2D = (load(PROJ_SCRIPT_PATH) as GDScript).new()
	root.add_child(proj)
	proj.global_position = hero.global_position
	proj.launch(Vector2.RIGHT)
	proj._check_hit()
	_expect(proj.get("_reflected") == true, "the bolt was parried")
	var dir: Vector2 = proj.get("_dir")
	_expect(
		dir.distance_to(Vector2.UP) < DIR_EPSILON,
		"parried bolt leaves along the player's aim, not at the nearest enemy (got %s)" % dir)
	_completes("parry_returns_along_your_aim")
