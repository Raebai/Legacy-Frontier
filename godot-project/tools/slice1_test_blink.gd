# Run: godot --headless --path godot-project --script tools/slice1_test_blink.gd
# Note: tests run on the first _process frame (not _init) because Hero.gd
# references autoloads (Sfx, Targeting via _cast), and autoload globals are
# only registered with GDScript after the main loop is set up — so the hero
# scene is load()ed at runtime, never preload()ed.
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
	"blink_moves_along_facing",
	"blink_respects_cooldown",
	"blink_iframes_block_damage_then_expire",
	"blink_zero_facing_guard",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_blink_moves_along_facing()
	_test_blink_respects_cooldown()
	_test_blink_iframes_block_damage_then_expire()
	_test_blink_zero_facing_guard()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 blink tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 blink tests: all PASS")
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


func _make_hero() -> CharacterBody2D:
	# Runtime load: compiles after autoload globals (Sfx) are registered.
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)  # freed with root at exit
	return hero


func _test_blink_moves_along_facing() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(5000.0, 5000.0)  # open space, far from anything
	hero._move_dir = Vector2.DOWN  # blink follows the MOVEMENT direction now
	var origin: Vector2 = hero.global_position

	hero._blink()
	var expected: Vector2 = origin + Vector2.DOWN * hero.BLINK_DISTANCE
	_expect(
		hero.global_position.distance_to(expected) < 1.0,
		"blink teleports BLINK_DISTANCE along movement (got %s, want %s)"
		% [hero.global_position, expected]
	)
	_expect(
		hero._blink_cooldown_timer == hero.BLINK_COOLDOWN,
		"blink starts its cooldown"
	)
	_expect(
		hero._blink_iframe_timer == hero.BLINK_IFRAME,
		"blink starts its i-frame window"
	)
	_completes("blink_moves_along_facing")


func _test_blink_respects_cooldown() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(5000.0, 8000.0)
	hero._move_dir = Vector2.RIGHT

	hero._blink()
	var after_first: Vector2 = hero.global_position
	hero._blink()  # still on cooldown — must be a no-op
	_expect(
		hero.global_position == after_first,
		"second immediate blink does nothing (cooldown gate)"
	)

	hero._blink_cooldown_timer = 0.0  # simulate cooldown expiry
	hero._blink()
	_expect(
		hero.global_position.distance_to(after_first + Vector2.RIGHT * hero.BLINK_DISTANCE) < 1.0,
		"blink fires again once cooldown expires"
	)
	_completes("blink_respects_cooldown")


func _test_blink_iframes_block_damage_then_expire() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(8000.0, 5000.0)
	var full_hp: int = hero.hp

	hero._blink()
	_expect(hero._blink_iframe_timer > 0.0, "i-frame timer > 0 right after blink")
	hero.take_damage(25)
	_expect(hero.hp == full_hp, "damage during blink i-frames is a no-op")

	hero._blink_iframe_timer = 0.0  # simulate i-frame window expiring
	hero.take_damage(25)
	_expect(hero.hp == full_hp - 25, "damage lands again once i-frames expire")
	_completes("blink_iframes_block_damage_then_expire")


func _test_blink_zero_facing_guard() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(8000.0, 8000.0)
	hero._move_dir = Vector2.ZERO  # unreachable in play, but the guard must hold
	var origin: Vector2 = hero.global_position

	hero._blink()
	_expect(
		hero.global_position.distance_to(origin + Vector2.RIGHT * hero.BLINK_DISTANCE) < 1.0,
		"zero movement dir falls back to RIGHT"
	)
	_completes("blink_zero_facing_guard")
