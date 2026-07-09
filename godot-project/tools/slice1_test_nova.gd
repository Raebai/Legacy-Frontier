# Run: godot --headless --path godot-project --script tools/slice1_test_nova.gd
# Note: tests run on the first _process frame (not _init) because
# EnergyNova.gd and Hero.gd reference autoloads (Sfx), and autoload globals
# are only registered with GDScript after the main loop is set up — so both
# scenes are load()ed at runtime, never preload()ed.
extends SceneTree

const NOVA_SCENE_PATH: String = "res://scenes/combat/EnergyNova.tscn"
const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


## Recorder stub: joins group "enemy" and records damage + knockback calls.
class StubEnemy:
	extends CharacterBody2D
	var damage_taken: int = 0
	var last_knockback: Vector2 = Vector2.ZERO

	func take_damage(amount: int) -> void:
		damage_taken += amount

	func apply_knockback(vec: Vector2) -> void:
		last_knockback = vec


## Recorder stub: joins group "destructible" and records damage only.
class StubProp:
	extends StaticBody2D
	var damage_taken: int = 0

	func take_damage(amount: int) -> void:
		damage_taken += amount


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_nova_damages_and_pushes_inside_only()
	failed += _test_nova_hits_destructibles_in_radius()
	failed += _test_nova_center_overlap_knockback_fallback()
	failed += _test_hero_nova_cooldown_gate()
	if failed > 0:
		printerr("Slice1 nova tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 nova tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_nova() -> Node2D:
	# Runtime load: compiles after autoload globals (Sfx) are registered.
	var nova_scene: PackedScene = load(NOVA_SCENE_PATH)
	var nova: Node2D = nova_scene.instantiate()
	root.add_child(nova)  # freed with root at exit
	return nova


func _make_hero() -> CharacterBody2D:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)
	return hero


func _make_enemy(pos: Vector2) -> StubEnemy:
	var enemy: StubEnemy = StubEnemy.new()
	root.add_child(enemy)
	enemy.global_position = pos
	enemy.add_to_group("enemy")
	return enemy


func _make_prop(pos: Vector2) -> StubProp:
	var prop: StubProp = StubProp.new()
	root.add_child(prop)
	prop.global_position = pos
	prop.add_to_group("destructible")
	return prop


## Full activate_at drive: inside enemy takes damage + OUTWARD knockback,
## outside enemy is completely untouched. Clusters sit far apart so tests
## never cross-hit each other's radius-135 queries.
func _test_nova_damages_and_pushes_inside_only() -> int:
	var failed: int = 0
	var center: Vector2 = Vector2(5000.0, 5000.0)
	var inside: StubEnemy = _make_enemy(center + Vector2(80.0, 0.0))
	var outside: StubEnemy = _make_enemy(center + Vector2(300.0, 0.0))
	var nova: Node2D = _make_nova()

	nova.call("activate_at", center)
	failed += _expect(
		nova.global_position == center, "activate_at places the nova at the given position"
	)
	failed += _expect(
		inside.damage_taken == nova.NOVA_DAMAGE,
		"enemy inside NOVA_RADIUS takes NOVA_DAMAGE (got %d)" % inside.damage_taken
	)
	failed += _expect(
		inside.last_knockback.normalized().dot(Vector2.RIGHT) > 0.99,
		"inside enemy is pushed OUTWARD, away from the center (got %s)"
		% inside.last_knockback
	)
	failed += _expect(
		absf(inside.last_knockback.length() - nova.NOVA_KNOCKBACK) < 0.01,
		"knockback magnitude is NOVA_KNOCKBACK"
	)
	failed += _expect(outside.damage_taken == 0, "enemy outside NOVA_RADIUS takes no damage")
	failed += _expect(
		outside.last_knockback == Vector2.ZERO, "enemy outside NOVA_RADIUS gets no knockback"
	)
	return failed


## _apply_nova_damage() drives the geometry directly: crates in range shatter,
## crates out of range are untouched.
func _test_nova_hits_destructibles_in_radius() -> int:
	var failed: int = 0
	var center: Vector2 = Vector2(8000.0, 5000.0)
	var inside: StubProp = _make_prop(center + Vector2(0.0, 60.0))
	var outside: StubProp = _make_prop(center + Vector2(0.0, 400.0))
	var nova: Node2D = _make_nova()
	nova.global_position = center

	nova.call("_apply_nova_damage")
	failed += _expect(
		inside.damage_taken == nova.NOVA_DAMAGE, "destructible inside takes NOVA_DAMAGE"
	)
	failed += _expect(outside.damage_taken == 0, "destructible outside is untouched")
	return failed


## Enemy standing EXACTLY on the caster: zero-length away vector must fall
## back to RIGHT instead of a zero knockback.
func _test_nova_center_overlap_knockback_fallback() -> int:
	var failed: int = 0
	var center: Vector2 = Vector2(5000.0, 8000.0)
	var overlapped: StubEnemy = _make_enemy(center)
	var nova: Node2D = _make_nova()
	nova.global_position = center

	nova.call("_apply_nova_damage")
	failed += _expect(
		overlapped.last_knockback.normalized().dot(Vector2.RIGHT) > 0.99,
		"enemy overlapping the center still gets pushed (RIGHT fallback)"
	)
	failed += _expect(
		absf(overlapped.last_knockback.length() - nova.NOVA_KNOCKBACK) < 0.01,
		"fallback knockback keeps full NOVA_KNOCKBACK magnitude"
	)
	return failed


## Hero wiring: _nova() spawns the nova at the hero, starts the cooldown, and
## re-firing during cooldown is a no-op.
func _test_hero_nova_cooldown_gate() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(8000.0, 8000.0)
	var nearby: StubEnemy = _make_enemy(hero.global_position + Vector2(70.0, 0.0))

	hero._nova()
	failed += _expect(
		hero._nova_cooldown_timer == hero.NOVA_COOLDOWN, "nova starts its cooldown"
	)
	failed += _expect(
		nearby.damage_taken == 30,
		"hero nova damages an enemy standing next to the hero (got %d)" % nearby.damage_taken
	)

	hero._nova()  # still on cooldown — must be a no-op
	failed += _expect(
		nearby.damage_taken == 30, "second immediate nova does nothing (cooldown gate)"
	)

	hero._nova_cooldown_timer = 0.0  # simulate cooldown expiry
	hero._nova()
	failed += _expect(
		nearby.damage_taken == 60, "nova fires again once cooldown expires"
	)
	return failed
