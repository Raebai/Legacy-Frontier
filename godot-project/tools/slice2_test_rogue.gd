# Run: godot --headless --path godot-project --script tools/slice2_test_rogue.gd
# Hero.gd references autoloads (Sfx) so the hero scene is load()ed at runtime on
# the first _process frame, never preload()ed (repo test-trap idiom).
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
	"rogue_config",
	"mage_config_unchanged",
	"throw_blade_damage",
	"dash_strike_dedupe",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_rogue_config()
	_test_mage_config_unchanged()
	_test_throw_blade_damage()
	_test_dash_strike_dedupe()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice2 rogue tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice2 rogue tests: all PASS")
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
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)
	hero.set_physics_process(false)  # isolate — drive abilities by hand
	hero.global_position = Vector2(5000, 5000)
	return hero


func _test_rogue_config() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.ROGUE)
	_expect(String(hero.rig.equipment.get("weapon", "")) == "sword", "rogue equips sword")
	# ⚠ READ THE CLASS NUMBER, NOT THE COMPOSED ONE. `_melee_damage` is
	# `_base_melee_damage * gear["melee_damage"]` (Hero.gd:2518), and gear is the
	# PLAYER'S — `Loadout` is an autoload whose node is on the tree under `--script`,
	# so this assertion was quietly reading whatever the person running the suite had
	# equipped. It went red the first time the maker equipped a weapon while
	# playtesting, on a tree with no code change in it at all. Same trap as the two
	# suites that started testing the tester's `climber.json`; the fix is the same,
	# pin the class fact and let a separate test own the gear multiplier.
	_expect(hero._base_melee_damage == 26, "rogue melee retuned to sword damage 26")
	_expect(is_equal_approx(float(hero._cfg["cast_cd"]), 0.30), "rogue cast_cd 0.30 (burst-flurry recover)")
	_expect(is_equal_approx(float(hero._cfg["dash_cd"]), 0.70), "rogue dash_cd 0.70 (no dash-fly)")
	_expect(is_equal_approx(float(hero._cfg["blink_cd"]), 1.0), "rogue blink_cd 1.0")
	_expect(bool(hero._cfg["dash_strike"]) == true, "rogue has dash_strike")
	_expect(bool(hero._cfg["has_nova"]) == false, "rogue has no nova")
	_expect(String(hero._cfg["aoe"]) == "nova", "rogue Q is whirlwind (nova)")
	# Nova (T) is a no-op for the rogue.
	hero._nova_cooldown_timer = 0.0
	hero._nova()
	_expect(hero._nova_cooldown_timer == 0.0, "rogue _nova() is a no-op (no cooldown spent)")
	_completes("rogue_config")


func _test_mage_config_unchanged() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.MAGE)
	_expect(String(hero.rig.equipment.get("weapon", "")) == "staff", "mage keeps staff")
	# ⚠ NO LONGER "the fists baseline". The Arcanist carries its own staff-poke profile
	# now (five classes used to share one melee row — see
	# tools/slice_test_class_movement.gd). What this line is really guarding is that
	# switching AWAY from the rogue restores the mage's OWN numbers rather than leaving
	# the sword's on it, so it compares against the class row and against the rogue.
	# ⚠ THE CLASS NUMBER, NOT THE COMPOSED ONE. `_melee_damage` is
	# `_base_melee_damage * gear["melee_damage"]`, and `Loadout` is an autoload whose
	# node is on the tree under `--script` — so this was reading whatever the person
	# running the suite had equipped, and went red the moment the maker changed gear
	# mid-playtest on a tree with no code change in it. Third instance of this trap.
	_expect(hero._base_melee_damage == int(hero.CLASS_CONFIG[hero.HeroClass.MAGE]["melee_damage"]),
		"mage melee is the mage's own class profile")
	_expect(hero._melee_damage != 26,
		"switching off the rogue drops the sword's damage (26) rather than keeping it")
	_expect(is_equal_approx(float(hero._cfg["cast_cd"]), hero.CAST_COOLDOWN), "mage cast_cd == const")
	_expect(is_equal_approx(float(hero._cfg["dash_cd"]), hero.DASH_COOLDOWN), "mage dash_cd == const")
	_expect(bool(hero._cfg["dash_strike"]) == false, "mage has no dash_strike")
	_expect(bool(hero._cfg["has_nova"]) == true, "mage has nova")
	_expect(String(hero._cfg["aoe"]) == "arcane_meteor", "mage Q is the arcane meteor storm")
	_completes("mage_config_unchanged")


func _test_throw_blade_damage() -> void:
	# Rogue blade is lighter (9, burst-flurry); mage bolt is the Spell default (18).
	var rogue: CharacterBody2D = _make_hero()
	rogue.configure_class(rogue.HeroClass.ROGUE)
	_expect(_cast_and_read_damage(rogue) == 9, "rogue thrown blade deals 9 (burst)")
	var mage: CharacterBody2D = _make_hero()
	mage.configure_class(mage.HeroClass.MAGE)
	_expect(_cast_and_read_damage(mage) == 18, "mage bolt deals the default 18")
	_completes("throw_blade_damage")


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


func _test_dash_strike_dedupe() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.ROGUE)
	hero.global_position = Vector2(1000, 1000)
	hero._dash_dir = Vector2.RIGHT
	var target := _StubEnemy.new()
	root.add_child(target)
	target.add_to_group("enemy")
	# ...and `mortal`, the shared damageable-fighter group every hero attack scans
	# now that friendly fire is on. A real `Enemy` joins both; a stub that joined only
	# `enemy` would be invisible to every hero spell and swing in the game.
	target.add_to_group(SpellCaster.MORTAL_GROUP)
	target.global_position = Vector2(1030, 1000)  # ~30px, inside dash_strike_range 42
	hero._dash_hit.clear()
	hero._dash_strike_sweep()
	hero._dash_strike_sweep()  # second sweep same dash — must NOT hit again
	_expect(target.hits == 1, "dash-strike hits each enemy once per dash (got %d)" % target.hits)
	_expect(target.last_damage == 16, "dash-strike deals 16 (got %d)" % target.last_damage)
	# A fresh dash clears the dedupe set and can hit again.
	hero._dash_hit.clear()
	hero._dash_strike_sweep()
	_expect(target.hits == 2, "next dash can strike the same enemy again")
	target.queue_free()
	_completes("dash_strike_dedupe")


class _StubEnemy extends Node2D:
	var hits: int = 0
	var last_damage: int = 0

	func take_damage(amount: int) -> void:
		hits += 1
		last_damage = amount

	func apply_knockback(_impulse: Vector2) -> void:
		pass
