# Run: godot --headless --path godot-project --script tools/slice1_test_nova.gd
# Note: tests run on the first _process frame (not _init) because
# EnergyNova.gd and Hero.gd reference autoloads (Sfx), and autoload globals
# are only registered with GDScript after the main loop is set up — so both
# scenes are load()ed at runtime, never preload()ed.
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
	"nova_damages_and_pushes_inside_only",
	"nova_hits_destructibles_in_radius",
	"nova_center_overlap_knockback_fallback",
	"hero_nova_cooldown_gate",
	"nova_hit_radius_unaffected_by_visual_shrink",
]

var _fails: int = 0
var _completed: Dictionary = {}

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
	_test_nova_damages_and_pushes_inside_only()
	_test_nova_hits_destructibles_in_radius()
	_test_nova_center_overlap_knockback_fallback()
	_test_hero_nova_cooldown_gate()
	_test_nova_hit_radius_unaffected_by_visual_shrink()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 nova tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 nova tests: all PASS")
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
	# ...and `mortal`, the shared damageable-fighter group every hero attack scans
	# now that friendly fire is on. A real `Enemy` joins both; a stub that joined only
	# `enemy` would be invisible to every hero spell and swing in the game.
	enemy.add_to_group(SpellCaster.MORTAL_GROUP)
	return enemy


## Detonate every nova currently GATHERING anywhere under `root`.
##
## EnergyNova now winds up for `WINDUP_TIME` before it goes off (the maker asked for
## a telegraph — see the block at the top of EnergyNova.gd). These tests assert
## GEOMETRY, not timing, so they force the release rather than simulating 0.3 s of
## frames: what is being pinned here is who is inside 135 px, and that answer must
## not depend on how many frames the harness happened to run.
##
## The wind-up's own timing is covered where it belongs — `slice_test_friendly_fire`
## advances real frames through it, so a nova that never detonated would fail there.
func _fire_pending_novas() -> void:
	for n: Node in root.get_children():
		if n.has_method("detonate_now"):
			n.call("detonate_now")


func _make_prop(pos: Vector2) -> StubProp:
	var prop: StubProp = StubProp.new()
	root.add_child(prop)
	prop.global_position = pos
	prop.add_to_group("destructible")
	return prop


## Full activate_at drive: inside enemy takes damage + OUTWARD knockback,
## outside enemy is completely untouched. Clusters sit far apart so tests
## never cross-hit each other's radius-135 queries.
func _test_nova_damages_and_pushes_inside_only() -> void:
	var center: Vector2 = Vector2(5000.0, 5000.0)
	var inside: StubEnemy = _make_enemy(center + Vector2(80.0, 0.0))
	var outside: StubEnemy = _make_enemy(center + Vector2(300.0, 0.0))
	var nova: Node2D = _make_nova()

	nova.call("activate_at", center)
	nova.call("detonate_now")   # skip the 0.30 s gather; see _fire_pending_novas
	_expect(
		nova.global_position == center, "activate_at places the nova at the given position"
	)
	_expect(
		inside.damage_taken == nova.NOVA_DAMAGE,
		"enemy inside NOVA_RADIUS takes NOVA_DAMAGE (got %d)" % inside.damage_taken
	)
	_expect(
		inside.last_knockback.normalized().dot(Vector2.RIGHT) > 0.99,
		"inside enemy is pushed OUTWARD, away from the center (got %s)"
		% inside.last_knockback
	)
	_expect(
		absf(inside.last_knockback.length() - nova.NOVA_KNOCKBACK) < 0.01,
		"knockback magnitude is NOVA_KNOCKBACK"
	)
	_expect(outside.damage_taken == 0, "enemy outside NOVA_RADIUS takes no damage")
	_expect(
		outside.last_knockback == Vector2.ZERO, "enemy outside NOVA_RADIUS gets no knockback"
	)
	_completes("nova_damages_and_pushes_inside_only")


## _apply_nova_damage() drives the geometry directly: crates in range shatter,
## crates out of range are untouched.
func _test_nova_hits_destructibles_in_radius() -> void:
	var center: Vector2 = Vector2(8000.0, 5000.0)
	var inside: StubProp = _make_prop(center + Vector2(0.0, 60.0))
	var outside: StubProp = _make_prop(center + Vector2(0.0, 400.0))
	var nova: Node2D = _make_nova()
	nova.global_position = center

	nova.call("_apply_nova_damage")
	_expect(
		inside.damage_taken == nova.NOVA_DAMAGE, "destructible inside takes NOVA_DAMAGE"
	)
	_expect(outside.damage_taken == 0, "destructible outside is untouched")
	_completes("nova_hits_destructibles_in_radius")


## Enemy standing EXACTLY on the caster: zero-length away vector must fall
## back to RIGHT instead of a zero knockback.
func _test_nova_center_overlap_knockback_fallback() -> void:
	var center: Vector2 = Vector2(5000.0, 8000.0)
	var overlapped: StubEnemy = _make_enemy(center)
	var nova: Node2D = _make_nova()
	nova.global_position = center

	nova.call("_apply_nova_damage")
	_expect(
		overlapped.last_knockback.normalized().dot(Vector2.RIGHT) > 0.99,
		"enemy overlapping the center still gets pushed (RIGHT fallback)"
	)
	_expect(
		absf(overlapped.last_knockback.length() - nova.NOVA_KNOCKBACK) < 0.01,
		"fallback knockback keeps full NOVA_KNOCKBACK magnitude"
	)
	_completes("nova_center_overlap_knockback_fallback")


## Task 7 (right-size spell VFX): EnergyNova's shockwave RING was shrunk
## visually via VISUAL_RADIUS_FACTOR, but _apply_nova_damage() must keep using
## the raw NOVA_RADIUS untouched. Pins the exact hit boundary at NOVA_RADIUS
## (135.0): 1px inside hits, 1px outside misses. If VISUAL_RADIUS_FACTOR (0.62)
## ever leaked into the damage query, the boundary would shrink to ~83.7 and
## the "1px inside" case below would start failing.
func _test_nova_hit_radius_unaffected_by_visual_shrink() -> void:
	var center: Vector2 = Vector2(11000.0, 5000.0)
	var nova: Node2D = _make_nova()
	nova.global_position = center
	var just_inside: StubEnemy = _make_enemy(center + Vector2(float(nova.NOVA_RADIUS) - 1.0, 0.0))
	var just_outside: StubEnemy = _make_enemy(center + Vector2(float(nova.NOVA_RADIUS) + 1.0, 0.0))

	nova.call("_apply_nova_damage")
	_expect(
		just_inside.damage_taken == nova.NOVA_DAMAGE,
		"enemy 1px inside the true NOVA_RADIUS (135) still takes damage (got %d)" % just_inside.damage_taken
	)
	_expect(
		just_outside.damage_taken == 0,
		"enemy 1px outside the true NOVA_RADIUS (135) is untouched — visual shrink did not leak into the hit query (got %d)"
		% just_outside.damage_taken
	)
	_completes("nova_hit_radius_unaffected_by_visual_shrink")


## Hero wiring: _nova() spawns the nova at the hero, starts the cooldown, and
## re-firing during cooldown is a no-op.
func _test_hero_nova_cooldown_gate() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(8000.0, 8000.0)
	var nearby: StubEnemy = _make_enemy(hero.global_position + Vector2(70.0, 0.0))

	hero._nova()
	_fire_pending_novas()
	_expect(
		hero._nova_cooldown_timer == hero.NOVA_COOLDOWN, "nova starts its cooldown"
	)
	_expect(
		nearby.damage_taken == 30,
		"hero nova damages an enemy standing next to the hero (got %d)" % nearby.damage_taken
	)

	hero._nova()  # still on cooldown — must be a no-op
	_fire_pending_novas()
	_expect(
		nearby.damage_taken == 30, "second immediate nova does nothing (cooldown gate)"
	)

	hero._nova_cooldown_timer = 0.0  # simulate cooldown expiry
	hero._nova()
	_fire_pending_novas()
	_expect(
		nearby.damage_taken == 60, "nova fires again once cooldown expires"
	)
	_completes("hero_nova_cooldown_gate")
