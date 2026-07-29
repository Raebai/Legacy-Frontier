# Run: godot --headless --path godot-project --script tools/slice3_test_parry.gd
# Wave 2 (MMO layer): perfect-timing parry reverses an enemy bolt; class-gated.
# Runs on the first _process frame (not _init) because Hero/EnemyProjectile
# reference autoloads (Sfx, Targeting, CombatVfx) that only register after the
# main loop is up — so both are load()ed at runtime, never preload()ed.
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
	"rogue_parry_reflects",
	"mage_can_parry_too",
	"no_window_takes_hit",
	"reflected_bolt_hits_enemy",
	"parried_dagger_severs_anchor",
]

var _fails: int = 0
var _completed: Dictionary = {}

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
	_test_rogue_parry_reflects()
	_test_mage_can_parry_too()
	_test_no_window_takes_hit()
	_test_reflected_bolt_hits_enemy()
	_test_parried_dagger_severs_anchor()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice3 parry tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice3 parry tests: all PASS")
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


func _test_rogue_parry_reflects() -> void:
	var hero: CharacterBody2D = _make_hero(ROGUE, Vector2(1000, 1000))
	var full_hp: int = hero.hp
	hero._try_parry_start()
	_expect(hero.is_parrying(), "rogue parry window opens")
	var proj: Node2D = _make_proj(hero.global_position)
	var hit: bool = proj._check_hit()
	_expect(not hit, "parried bolt is not a hit on the hero")
	_expect(hero.hp == full_hp, "parry -> hero takes no damage")
	_expect(proj._reflected, "parried bolt becomes reflected")
	_expect(not hero.is_parrying(), "window consumed after one reflect")
	_completes("rogue_parry_reflects")


func _test_mage_can_parry_too() -> void:
	var hero: CharacterBody2D = _make_hero(MAGE, Vector2(2000, 2000))
	hero._try_parry_start()
	_expect(hero.is_parrying(), "parry is universal now — mage can parry too")
	_completes("mage_can_parry_too")


func _test_no_window_takes_hit() -> void:
	var hero: CharacterBody2D = _make_hero(ROGUE, Vector2(3000, 3000))
	var full_hp: int = hero.hp
	# Rogue, but the window was never opened.
	var proj: Node2D = _make_proj(hero.global_position)
	var hit: bool = proj._check_hit()
	_expect(hit, "no parry window -> the bolt connects")
	_expect(hero.hp < full_hp, "no parry window -> hero takes damage")
	_completes("no_window_takes_hit")


func _test_reflected_bolt_hits_enemy() -> void:
	var enemy := EnemyStub.new()
	enemy.add_to_group("enemy")
	root.add_child(enemy)
	enemy.global_position = Vector2(4000, 4000)
	var proj: Node2D = _make_proj(enemy.global_position)
	proj.reflect(Vector2.RIGHT, Color.WHITE)  # now hunts the "enemy" group
	var hit: bool = proj._check_hit()
	_expect(hit, "reflected bolt strikes an enemy")
	_expect(enemy.damage_taken > 0, "reflected bolt deals damage to the enemy")
	_completes("reflected_bolt_hits_enemy")


## The Rift Dagger is the first SIGNATURE spell in the parry layer, and its
## deflect does more than turn the blade around: clearing the owner SEVERS the
## anchor, so the thrower's recall press finds nothing. That cancellation is the
## counterplay the spell is balanced around, so it is worth pinning down.
func _test_parried_dagger_severs_anchor() -> void:
	var thrower := Node2D.new()
	root.add_child(thrower)
	thrower.global_position = Vector2(5000, 5000)
	var dagger: Node2D = (load(DAGGER_PATH) as GDScript).new()
	root.add_child(dagger)
	dagger.call("throw_dagger", thrower, Vector2(5000, 5000), Vector2.RIGHT,
		Color.WHITE, 700.0, 70.0, 34, 4.0, 4.5, "shadow")
	_expect(dagger.get("_target_group") == "enemy", "a thrown dagger hunts enemies")
	_expect(
		(load(DAGGER_PATH) as GDScript).find_anchor(get_root().get_tree(), thrower) == dagger,
		"a live dagger is findable as its thrower's anchor")
	dagger.call("reflect", Vector2.LEFT, Color.WHITE)
	_expect(dagger.get("_reflected") == true, "a parried dagger is marked reflected")
	_expect(dagger.get("_dir").x < 0.0, "a parried dagger flies back the other way")
	_expect(dagger.get("_target_group") == "hero", "a parried dagger now hunts heroes")
	_expect(dagger.get("_owner") == null, "a parried dagger's anchor is SEVERED")
	_expect(
		(load(DAGGER_PATH) as GDScript).find_anchor(get_root().get_tree(), thrower) == null,
		"the thrower can no longer recall to a parried dagger")
	_completes("parried_dagger_severs_anchor")
