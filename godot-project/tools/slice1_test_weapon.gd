# Run: godot --headless --path godot-project --script tools/slice1_test_weapon.gd
# Note: tests run on the first _process frame (not _init) because Hero.gd and
# WeaponPickup.gd reference the Sfx autoload, and autoload globals are only
# registered with GDScript after the main loop is set up — so both are
# load()ed at runtime, never preload()ed.
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
	"default_weapon_is_fists",
	"equip_sword_swaps_rig_and_stats",
	"unknown_kind_falls_back_to_fists",
	"pickup_equips_hero_once_and_frees",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const PICKUP_SCRIPT_PATH: String = "res://scripts/combat/WeaponPickup.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_default_weapon_is_fists()
	_test_equip_sword_swaps_rig_and_stats()
	_test_unknown_kind_falls_back_to_fists()
	_test_pickup_equips_hero_once_and_frees()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 weapon tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 weapon tests: all PASS")
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


func _test_default_weapon_is_fists() -> void:
	var hero: CharacterBody2D = _make_hero()
	_expect(hero._weapon == "fists", "default weapon is fists")
	_expect(hero._melee_damage == 14, "fists damage 14")
	_expect(hero._melee_range == 58.0, "fists range 58")
	_expect(hero._melee_knockback == 300.0, "fists knockback 300 (Slice 3 shove bump)")
	_expect(
		hero.rig.equipment.get("weapon", "") == "staff",
		"mage preset staff visual until a pickup swaps it"
	)
	_completes("default_weapon_is_fists")


func _test_equip_sword_swaps_rig_and_stats() -> void:
	var hero: CharacterBody2D = _make_hero()

	hero.equip_weapon("sword")
	_expect(hero._weapon == "sword", "equip_weapon(sword) sets _weapon")
	_expect(
		hero.rig.equipment.get("weapon", "") == "sword", "rig weapon slot swapped to sword"
	)
	_expect(hero._melee_damage == 26, "sword damage 26")
	_expect(hero._melee_range == 60.0, "sword range 60")
	_expect(hero._melee_knockback == 400.0, "sword knockback 400 (Slice 3 shove bump)")

	hero.equip_weapon("fists")
	_expect(hero._weapon == "fists", "equip_weapon(fists) reverts _weapon")
	_expect(hero._melee_damage == 14, "fists damage restored")
	_expect(hero._melee_range == 58.0, "fists range restored")
	_expect(hero._melee_knockback == 300.0, "fists knockback restored")
	_completes("equip_sword_swaps_rig_and_stats")


func _test_unknown_kind_falls_back_to_fists() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.equip_weapon("sword")
	hero.equip_weapon("banhammer")
	_expect(hero._weapon == "fists", "unknown kind falls back to fists")
	_expect(hero._melee_damage == 14, "fallback uses fists damage")
	_completes("unknown_kind_falls_back_to_fists")


func _test_pickup_equips_hero_once_and_frees() -> void:
	var pickup_script: GDScript = load(PICKUP_SCRIPT_PATH)
	_expect(pickup_script != null, "WeaponPickup.gd loads")
	if pickup_script == null:
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice

	var hero: CharacterBody2D = _make_hero()
	var pickup: Area2D = pickup_script.new()
	pickup.weapon_kind = "sword"
	root.add_child(pickup)

	pickup._on_body_entered(hero)
	_expect(hero._weapon == "sword", "walk-over equips the sword")
	_expect(
		pickup.is_queued_for_deletion(), "pickup frees itself after equip"
	)

	# Double-trigger guard: a consumed pickup must not re-equip.
	hero.equip_weapon("fists")
	pickup._on_body_entered(hero)
	_expect(hero._weapon == "fists", "consumed pickup does not re-equip")
	_completes("pickup_equips_hero_once_and_frees")
