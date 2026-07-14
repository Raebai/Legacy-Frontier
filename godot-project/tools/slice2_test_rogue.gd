# Run: godot --headless --path godot-project --script tools/slice2_test_rogue.gd
# Hero.gd references autoloads (Sfx) so the hero scene is load()ed at runtime on
# the first _process frame, never preload()ed (repo test-trap idiom).
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_rogue_config()
	failed += _test_mage_config_unchanged()
	failed += _test_throw_blade_damage()
	failed += _test_dash_strike_dedupe()
	if failed > 0:
		printerr("Slice2 rogue tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice2 rogue tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_hero() -> CharacterBody2D:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)
	hero.set_physics_process(false)  # isolate — drive abilities by hand
	hero.global_position = Vector2(5000, 5000)
	return hero


func _test_rogue_config() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.ROGUE)
	failed += _expect(String(hero.rig.equipment.get("weapon", "")) == "sword", "rogue equips sword")
	failed += _expect(hero._melee_damage == 26, "rogue melee retuned to sword damage 26")
	failed += _expect(is_equal_approx(float(hero._cfg["cast_cd"]), 0.30), "rogue cast_cd 0.30 (burst-flurry recover)")
	failed += _expect(is_equal_approx(float(hero._cfg["dash_cd"]), 0.70), "rogue dash_cd 0.70 (no dash-fly)")
	failed += _expect(is_equal_approx(float(hero._cfg["blink_cd"]), 1.0), "rogue blink_cd 1.0")
	failed += _expect(bool(hero._cfg["dash_strike"]) == true, "rogue has dash_strike")
	failed += _expect(bool(hero._cfg["has_nova"]) == false, "rogue has no nova")
	failed += _expect(String(hero._cfg["aoe"]) == "nova", "rogue Q is whirlwind (nova)")
	# Nova (T) is a no-op for the rogue.
	hero._nova_cooldown_timer = 0.0
	hero._nova()
	failed += _expect(hero._nova_cooldown_timer == 0.0, "rogue _nova() is a no-op (no cooldown spent)")
	return failed


func _test_mage_config_unchanged() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.MAGE)
	failed += _expect(String(hero.rig.equipment.get("weapon", "")) == "staff", "mage keeps staff")
	failed += _expect(hero._melee_damage == hero.MELEE_DAMAGE, "mage melee is fists baseline")
	failed += _expect(is_equal_approx(float(hero._cfg["cast_cd"]), hero.CAST_COOLDOWN), "mage cast_cd == const")
	failed += _expect(is_equal_approx(float(hero._cfg["dash_cd"]), hero.DASH_COOLDOWN), "mage dash_cd == const")
	failed += _expect(bool(hero._cfg["dash_strike"]) == false, "mage has no dash_strike")
	failed += _expect(bool(hero._cfg["has_nova"]) == true, "mage has nova")
	failed += _expect(String(hero._cfg["aoe"]) == "arcane_meteor", "mage Q is the arcane meteor storm")
	return failed


func _test_throw_blade_damage() -> int:
	var failed: int = 0
	# Rogue blade is lighter (9, burst-flurry); mage bolt is the Spell default (18).
	var rogue: CharacterBody2D = _make_hero()
	rogue.configure_class(rogue.HeroClass.ROGUE)
	failed += _expect(_cast_and_read_damage(rogue) == 9, "rogue thrown blade deals 9 (burst)")
	var mage: CharacterBody2D = _make_hero()
	mage.configure_class(mage.HeroClass.MAGE)
	failed += _expect(_cast_and_read_damage(mage) == 18, "mage bolt deals the default 18")
	return failed


## Cast once with no enemies present and read the damage on the spell it spawned.
func _cast_and_read_damage(hero: CharacterBody2D) -> int:
	var parent: Node = hero.get_parent()
	var before: int = parent.get_child_count()
	hero._cast()
	for i in range(before, parent.get_child_count()):
		var c: Node = parent.get_child(i)
		if c.has_method("launch") and c.has_method("set_element_color"):
			return int(c.get("damage"))
	return -999


func _test_dash_strike_dedupe() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.ROGUE)
	hero.global_position = Vector2(1000, 1000)
	hero._dash_dir = Vector2.RIGHT
	var target := _StubEnemy.new()
	root.add_child(target)
	target.add_to_group("enemy")
	target.global_position = Vector2(1030, 1000)  # ~30px, inside dash_strike_range 42
	hero._dash_hit.clear()
	hero._dash_strike_sweep()
	hero._dash_strike_sweep()  # second sweep same dash — must NOT hit again
	failed += _expect(target.hits == 1, "dash-strike hits each enemy once per dash (got %d)" % target.hits)
	failed += _expect(target.last_damage == 16, "dash-strike deals 16 (got %d)" % target.last_damage)
	# A fresh dash clears the dedupe set and can hit again.
	hero._dash_hit.clear()
	hero._dash_strike_sweep()
	failed += _expect(target.hits == 2, "next dash can strike the same enemy again")
	target.queue_free()
	return failed


class _StubEnemy extends Node2D:
	var hits: int = 0
	var last_damage: int = 0

	func take_damage(amount: int) -> void:
		hits += 1
		last_damage = amount

	func apply_knockback(_impulse: Vector2) -> void:
		pass
