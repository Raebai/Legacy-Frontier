# Run: godot --headless --path godot-project --script tools/slice3_test_flight.gd
# Flight fuel/state machine, driven through the _tick_flight seam (no input
# simulation). First-_process-frame harness: Hero references autoloads + a Rig
# that only wire up once the tree is live (slice1_test_weapon idiom).
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_liftoff_and_drain()
	failed += _test_grounded_regen_and_cap()
	failed += _test_forced_land_on_empty()
	failed += _test_cannot_start_on_low_fuel()
	if failed > 0:
		printerr("Slice3 flight tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice3 flight tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)  # freed with root at exit
	return hero


func _test_liftoff_and_drain() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()  # starts with a full tank
	hero._tick_flight(true, 0.1)
	failed += _expect(hero.is_flying(), "holding fly on a full tank lifts off")
	failed += _expect(hero._fly_fuel < hero.FLY_FUEL_MAX, "flying drains fuel")
	return failed


func _test_grounded_regen_and_cap() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero._fly_fuel = 0.5
	hero._tick_flight(false, 0.2)  # not holding -> grounded, regen
	failed += _expect(not hero.is_flying(), "releasing fly returns to the ground")
	failed += _expect(hero._fly_fuel > 0.5, "grounded regenerates fuel")
	hero._fly_fuel = hero.FLY_FUEL_MAX
	hero._tick_flight(false, 1.0)
	failed += _expect(is_equal_approx(hero._fly_fuel, hero.FLY_FUEL_MAX), "fuel caps at max")
	return failed


func _test_forced_land_on_empty() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero._tick_flight(true, 0.05)  # lift off
	failed += _expect(hero.is_flying(), "airborne before the tank runs dry")
	# A long held tick empties the tank (drain is computed while fuel is still >0,
	# so this frame stays flagged flying with fuel clamped to 0)...
	hero._tick_flight(true, 5.0)
	failed += _expect(hero._fly_fuel == 0.0, "held flight drains the tank to empty")
	# ...and the NEXT tick sees an empty tank -> forced landing even while held.
	hero._tick_flight(true, 0.1)
	failed += _expect(not hero.is_flying(), "an empty tank forces a landing even while held")
	return failed


func _test_cannot_start_on_low_fuel() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero._fly_fuel = hero.FLY_MIN_TO_START - 0.05  # just under the liftoff threshold
	hero._tick_flight(true, 0.05)
	failed += _expect(not hero.is_flying(), "cannot lift off below the min-fuel threshold")
	return failed
