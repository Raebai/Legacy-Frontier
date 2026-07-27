# Run: godot --headless --path godot-project --script tools/slice3_test_parry.gd
# Wave 2 (MMO layer): perfect-timing parry reverses an enemy bolt; class-gated.
# Runs on the first _process frame (not _init) because Hero/EnemyProjectile
# reference autoloads (Sfx, Targeting, CombatVfx) that only register after the
# main loop is up — so both are load()ed at runtime, never preload()ed.
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const PROJ_SCRIPT_PATH: String = "res://scripts/combat/EnemyProjectile.gd"
const DAGGER_PATH: String = "res://scripts/combat/RiftDagger.gd"
const ROGUE: int = 1  # Hero.HeroClass.ROGUE
const MAGE: int = 0   # Hero.HeroClass.MAGE

var _ran: bool = false


## Minimal enemy stand-in: in the "enemy" group with a take_damage sink, so a
## reflected bolt has something to hit without instancing the full Enemy scene.
class EnemyStub extends Node2D:
	var damage_taken: int = 0
	func take_damage(amount: int) -> void:
		damage_taken += amount
	func apply_knockback(_impulse: Vector2) -> void:
		pass


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_rogue_parry_reflects()
	failed += _test_mage_can_parry_too()
	failed += _test_no_window_takes_hit()
	failed += _test_reflected_bolt_hits_enemy()
	failed += _test_parried_dagger_severs_anchor()
	if failed > 0:
		printerr("Slice3 parry tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice3 parry tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_hero(cls: int, pos: Vector2) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.configure_class(cls)
	hero.global_position = pos
	return hero


func _make_proj(pos: Vector2) -> Node2D:
	var proj: Node2D = (load(PROJ_SCRIPT_PATH) as GDScript).new()
	root.add_child(proj)
	proj.global_position = pos
	proj.launch(Vector2.RIGHT)
	return proj


func _test_rogue_parry_reflects() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero(ROGUE, Vector2(1000, 1000))
	var full_hp: int = hero.hp
	hero._try_parry_start()
	failed += _expect(hero.is_parrying(), "rogue parry window opens")
	var proj: Node2D = _make_proj(hero.global_position)
	var hit: bool = proj._check_hit()
	failed += _expect(not hit, "parried bolt is not a hit on the hero")
	failed += _expect(hero.hp == full_hp, "parry -> hero takes no damage")
	failed += _expect(proj._reflected, "parried bolt becomes reflected")
	failed += _expect(not hero.is_parrying(), "window consumed after one reflect")
	return failed


func _test_mage_can_parry_too() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero(MAGE, Vector2(2000, 2000))
	hero._try_parry_start()
	failed += _expect(hero.is_parrying(), "parry is universal now — mage can parry too")
	return failed


func _test_no_window_takes_hit() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero(ROGUE, Vector2(3000, 3000))
	var full_hp: int = hero.hp
	# Rogue, but the window was never opened.
	var proj: Node2D = _make_proj(hero.global_position)
	var hit: bool = proj._check_hit()
	failed += _expect(hit, "no parry window -> the bolt connects")
	failed += _expect(hero.hp < full_hp, "no parry window -> hero takes damage")
	return failed


func _test_reflected_bolt_hits_enemy() -> int:
	var failed: int = 0
	var enemy := EnemyStub.new()
	enemy.add_to_group("enemy")
	root.add_child(enemy)
	enemy.global_position = Vector2(4000, 4000)
	var proj: Node2D = _make_proj(enemy.global_position)
	proj.reflect(Vector2.RIGHT, Color.WHITE)  # now hunts the "enemy" group
	var hit: bool = proj._check_hit()
	failed += _expect(hit, "reflected bolt strikes an enemy")
	failed += _expect(enemy.damage_taken > 0, "reflected bolt deals damage to the enemy")
	return failed


## The Rift Dagger is the first SIGNATURE spell in the parry layer, and its
## deflect does more than turn the blade around: clearing the owner SEVERS the
## anchor, so the thrower's recall press finds nothing. That cancellation is the
## counterplay the spell is balanced around, so it is worth pinning down.
func _test_parried_dagger_severs_anchor() -> int:
	var failed: int = 0
	var thrower := Node2D.new()
	root.add_child(thrower)
	thrower.global_position = Vector2(5000, 5000)
	var dagger: Node2D = (load(DAGGER_PATH) as GDScript).new()
	root.add_child(dagger)
	dagger.call("throw_dagger", thrower, Vector2(5000, 5000), Vector2.RIGHT,
		Color.WHITE, 700.0, 70.0, 34, 4.0, 4.5, "shadow")
	failed += _expect(dagger.get("_target_group") == "enemy", "a thrown dagger hunts enemies")
	failed += _expect(
		(load(DAGGER_PATH) as GDScript).find_anchor(get_root().get_tree(), thrower) == dagger,
		"a live dagger is findable as its thrower's anchor")
	dagger.call("reflect", Vector2.LEFT, Color.WHITE)
	failed += _expect(dagger.get("_reflected") == true, "a parried dagger is marked reflected")
	failed += _expect(dagger.get("_dir").x < 0.0, "a parried dagger flies back the other way")
	failed += _expect(dagger.get("_target_group") == "hero", "a parried dagger now hunts heroes")
	failed += _expect(dagger.get("_owner") == null, "a parried dagger's anchor is SEVERED")
	failed += _expect(
		(load(DAGGER_PATH) as GDScript).find_anchor(get_root().get_tree(), thrower) == null,
		"the thrower can no longer recall to a parried dagger")
	return failed
