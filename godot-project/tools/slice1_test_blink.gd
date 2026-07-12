# Run: godot --headless --path godot-project --script tools/slice1_test_blink.gd
# Note: tests run on the first _process frame (not _init) because Hero.gd
# references autoloads (Sfx, Targeting via _cast), and autoload globals are
# only registered with GDScript after the main loop is set up — so the hero
# scene is load()ed at runtime, never preload()ed.
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_blink_moves_along_facing()
	failed += _test_blink_respects_cooldown()
	failed += _test_blink_iframes_block_damage_then_expire()
	failed += _test_blink_zero_facing_guard()
	if failed > 0:
		printerr("Slice1 blink tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 blink tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_hero() -> CharacterBody2D:
	# Runtime load: compiles after autoload globals (Sfx) are registered.
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)  # freed with root at exit
	return hero


func _test_blink_moves_along_facing() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(5000.0, 5000.0)  # open space, far from anything
	hero._move_dir = Vector2.DOWN  # blink follows the MOVEMENT direction now
	var origin: Vector2 = hero.global_position

	hero._blink()
	var expected: Vector2 = origin + Vector2.DOWN * hero.BLINK_DISTANCE
	failed += _expect(
		hero.global_position.distance_to(expected) < 1.0,
		"blink teleports BLINK_DISTANCE along movement (got %s, want %s)"
		% [hero.global_position, expected]
	)
	failed += _expect(
		hero._blink_cooldown_timer == hero.BLINK_COOLDOWN,
		"blink starts its cooldown"
	)
	failed += _expect(
		hero._blink_iframe_timer == hero.BLINK_IFRAME,
		"blink starts its i-frame window"
	)
	return failed


func _test_blink_respects_cooldown() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(5000.0, 8000.0)
	hero._move_dir = Vector2.RIGHT

	hero._blink()
	var after_first: Vector2 = hero.global_position
	hero._blink()  # still on cooldown — must be a no-op
	failed += _expect(
		hero.global_position == after_first,
		"second immediate blink does nothing (cooldown gate)"
	)

	hero._blink_cooldown_timer = 0.0  # simulate cooldown expiry
	hero._blink()
	failed += _expect(
		hero.global_position.distance_to(after_first + Vector2.RIGHT * hero.BLINK_DISTANCE) < 1.0,
		"blink fires again once cooldown expires"
	)
	return failed


func _test_blink_iframes_block_damage_then_expire() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(8000.0, 5000.0)
	var full_hp: int = hero.hp

	hero._blink()
	failed += _expect(hero._blink_iframe_timer > 0.0, "i-frame timer > 0 right after blink")
	hero.take_damage(25)
	failed += _expect(hero.hp == full_hp, "damage during blink i-frames is a no-op")

	hero._blink_iframe_timer = 0.0  # simulate i-frame window expiring
	hero.take_damage(25)
	failed += _expect(hero.hp == full_hp - 25, "damage lands again once i-frames expire")
	return failed


func _test_blink_zero_facing_guard() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(8000.0, 8000.0)
	hero._move_dir = Vector2.ZERO  # unreachable in play, but the guard must hold
	var origin: Vector2 = hero.global_position

	hero._blink()
	failed += _expect(
		hero.global_position.distance_to(origin + Vector2.RIGHT * hero.BLINK_DISTANCE) < 1.0,
		"zero movement dir falls back to RIGHT"
	)
	return failed
