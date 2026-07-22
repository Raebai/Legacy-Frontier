# Run: godot --headless --path godot-project --script tools/slice_test_loadout.gd
# Gear-ABILITY integration: a real Hero, real configure_class + set_loadout, asserting
# the wired effects actually land — weapon sets/reverts the element, hat scales max HP,
# robe wards, hammer scales melee — and that class DEFAULTS are untouched (override-only)
# and re-applying is idempotent. Hero.tscn is load()ed at runtime (autoload test-trap);
# tests run on the first _process frame.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var f: int = 0
	f += _test_defaults_untouched()
	f += _test_weapon_sets_and_reverts_element()
	f += _test_head_body_and_melee_effects()
	f += _test_idempotent_recompute()
	if f > 0:
		printerr("Loadout tests: %d FAILED" % f)
		quit(1)
	else:
		print("Loadout tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	return hero


## A class with NO loadout override plays exactly at its tuned base (override-only).
func _test_defaults_untouched() -> int:
	var f: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.CRYOMANCER)  # default weapon staff_ice, element ICE
	f += _expect(int(hero._element) == int(Elements.Element.ICE), "cryomancer default element ICE")
	f += _expect(int(hero.max_hp) == 100, "no gear -> max_hp stays 100")
	f += _expect(is_equal_approx(float(hero._gear_ward_frac), 0.0), "no gear -> no ward")
	f += _expect(is_equal_approx(float(hero._gear_speed_mult), 1.0), "no gear -> speed x1")
	f += _expect(is_equal_approx(float(hero._melee_knockback), float(hero._base_melee_knockback)), "no gear -> base melee kb")
	hero.queue_free()
	return f


## The flagship: an elemental weapon sets the element; a non-elemental one reverts to
## the class innate; clearing the slot also reverts.
func _test_weapon_sets_and_reverts_element() -> int:
	var f: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.MAGE)  # innate ARCANE
	f += _expect(int(hero._element) == int(Elements.Element.ARCANE), "mage base ARCANE")
	hero.set_loadout("weapon", "staff_ice")
	f += _expect(int(hero._element) == int(Elements.Element.ICE), "staff_ice -> ICE")
	hero.set_loadout("weapon", "staff_storm")
	f += _expect(int(hero._element) == int(Elements.Element.LIGHTNING), "staff_storm -> LIGHTNING")
	hero.set_loadout("weapon", "hammer")  # non-elemental
	f += _expect(int(hero._element) == int(Elements.Element.ARCANE), "hammer reverts to innate ARCANE")
	hero.set_loadout("weapon", "")  # cleared
	f += _expect(int(hero._element) == int(Elements.Element.ARCANE), "cleared weapon reverts to innate")
	hero.queue_free()
	return f


## hat -> +12% HP, robe -> ward, hammer -> melee mults (from the class base).
func _test_head_body_and_melee_effects() -> int:
	var f: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.MAGE)
	var base_kb: float = float(hero._base_melee_knockback)
	var base_dmg: int = int(hero._base_melee_damage)
	hero.set_loadout("head", "hat")
	f += _expect(int(hero.max_hp) == 112, "hat -> max_hp 112")
	f += _expect(int(hero.hp) <= int(hero.max_hp), "hp within new max")
	hero.set_loadout("body", "robe")
	f += _expect(is_equal_approx(float(hero._gear_ward_frac), 0.4), "robe -> ward 0.4")
	hero.set_loadout("head", "hood")
	f += _expect(is_equal_approx(float(hero._gear_speed_mult), 1.12), "hood -> speed x1.12")
	f += _expect(int(hero.max_hp) == 100, "hood replaced hat -> max_hp back to 100")
	hero.set_loadout("weapon", "hammer")
	f += _expect(is_equal_approx(float(hero._melee_knockback), base_kb * 1.4), "hammer -> +40% knockback from base")
	f += _expect(int(hero._melee_damage) == int(round(float(base_dmg) * 1.2)), "hammer -> +20% damage from base")
	hero.queue_free()
	return f


## Re-applying the same loadout must not compound (idempotent from the class base).
func _test_idempotent_recompute() -> int:
	var f: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.JUGGERNAUT)  # explicit melee tuning + hammer default
	hero.set_loadout("weapon", "hammer")
	var kb1: float = float(hero._melee_knockback)
	hero.set_loadout("weapon", "hammer")  # same again
	hero.set_loadout("weapon", "hammer")
	f += _expect(is_equal_approx(float(hero._melee_knockback), kb1), "re-equip hammer doesn't compound knockback")
	hero.queue_free()
	return f
