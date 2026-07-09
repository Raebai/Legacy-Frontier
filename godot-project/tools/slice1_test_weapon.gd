# Run: godot --headless --path godot-project --script tools/slice1_test_weapon.gd
# Note: tests run on the first _process frame (not _init) because Hero.gd and
# WeaponPickup.gd reference the Sfx autoload, and autoload globals are only
# registered with GDScript after the main loop is set up — so both are
# load()ed at runtime, never preload()ed.
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const PICKUP_SCRIPT_PATH: String = "res://scripts/combat/WeaponPickup.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_default_weapon_is_fists()
	failed += _test_equip_sword_swaps_rig_and_stats()
	failed += _test_unknown_kind_falls_back_to_fists()
	failed += _test_pickup_equips_hero_once_and_frees()
	if failed > 0:
		printerr("Slice1 weapon tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 weapon tests: all PASS")
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


func _test_default_weapon_is_fists() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	failed += _expect(hero._weapon == "fists", "default weapon is fists")
	failed += _expect(hero._melee_damage == 14, "fists damage 14")
	failed += _expect(hero._melee_range == 46.0, "fists range 46")
	failed += _expect(hero._melee_knockback == 220.0, "fists knockback 220")
	failed += _expect(
		hero.rig.equipment.get("weapon", "") == "staff",
		"mage preset staff visual until a pickup swaps it"
	)
	return failed


func _test_equip_sword_swaps_rig_and_stats() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()

	hero.equip_weapon("sword")
	failed += _expect(hero._weapon == "sword", "equip_weapon(sword) sets _weapon")
	failed += _expect(
		hero.rig.equipment.get("weapon", "") == "sword", "rig weapon slot swapped to sword"
	)
	failed += _expect(hero._melee_damage == 26, "sword damage 26")
	failed += _expect(hero._melee_range == 60.0, "sword range 60")
	failed += _expect(hero._melee_knockback == 320.0, "sword knockback 320")

	hero.equip_weapon("fists")
	failed += _expect(hero._weapon == "fists", "equip_weapon(fists) reverts _weapon")
	failed += _expect(hero._melee_damage == 14, "fists damage restored")
	failed += _expect(hero._melee_range == 46.0, "fists range restored")
	failed += _expect(hero._melee_knockback == 220.0, "fists knockback restored")
	return failed


func _test_unknown_kind_falls_back_to_fists() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.equip_weapon("sword")
	hero.equip_weapon("banhammer")
	failed += _expect(hero._weapon == "fists", "unknown kind falls back to fists")
	failed += _expect(hero._melee_damage == 14, "fallback uses fists damage")
	return failed


func _test_pickup_equips_hero_once_and_frees() -> int:
	var failed: int = 0
	var pickup_script: GDScript = load(PICKUP_SCRIPT_PATH)
	failed += _expect(pickup_script != null, "WeaponPickup.gd loads")
	if pickup_script == null:
		return failed

	var hero: CharacterBody2D = _make_hero()
	var pickup: Area2D = pickup_script.new()
	pickup.weapon_kind = "sword"
	root.add_child(pickup)

	pickup._on_body_entered(hero)
	failed += _expect(hero._weapon == "sword", "walk-over equips the sword")
	failed += _expect(
		pickup.is_queued_for_deletion(), "pickup frees itself after equip"
	)

	# Double-trigger guard: a consumed pickup must not re-equip.
	hero.equip_weapon("fists")
	pickup._on_body_entered(hero)
	failed += _expect(hero._weapon == "fists", "consumed pickup does not re-equip")
	return failed
