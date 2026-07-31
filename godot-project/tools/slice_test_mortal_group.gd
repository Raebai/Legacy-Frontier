# Run: godot --headless --path godot-project --script tools/slice_test_mortal_group.gd
# FRIENDLY FIRE, THIS SIDE OF THE CONTRACT (Phase 1.5).
#
# Friendly fire is implemented by stamping ONE target group: SpellCaster._stamp()
# writes `mortal` instead of a faction name, and every spectacle's existing
# `get_nodes_in_group(target_group)` scan then hits everything alive with zero
# spectacle edits. That only works if every damageable body is IN that group.
#
# So this suite asserts the half owned here: Enemy and Boss join `mortal` — and,
# just as important, that they did NOT stop being in the groups everything else
# scans. `enemy` drives the floor clear gate, the camera framing and every bot
# scan. Swapping instead of adding would be a silent, wide break, so both halves
# are pinned.
#
# CRATES ARE THE EXCEPTION, and it is the interesting one. `mortal` exists to
# make FACTIONS blind to each other. Cover was never factioned: every spectacle
# scans its stamped target_group for fighters AND the "destructible" literal for
# crates, as two separate passes (BlastSpell.gd:232 + :251, BeamSpell.gd:365 +
# :372, and ~20 more). Put a crate in both groups and both passes find it, so it
# eats every hit TWICE. It cost nothing to add and would have quietly halved the
# life of all cover, which is why it is pinned here as a NEGATIVE assertion.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# Failures accumulate on the MEMBER `_fails`, and every test's last line records
# that it reached the end, so a test that aborts part-way fails BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"enemy_is_mortal_and_still_enemy",
	"boss_is_mortal_and_still_enemy",
	"crate_is_destructible_but_NOT_mortal",
	"shattered_crate_leaves_destructible",
	"a_mortal_scan_finds_the_fighters_only",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ENEMY_SCENE: String = "res://scenes/combat/Enemy.tscn"
const BOSS_SCENE: String = "res://scenes/combat/Boss.tscn"
const CRATE_SCENE: String = "res://scenes/combat/DestructibleProp.tscn"
## The faction-blind group. A StringName here because that is what add_to_group
## was handed — get_nodes_in_group accepts either, but naming it once is the point.
const MORTAL: StringName = &"mortal"

var _arena: Node2D = null


func _initialize() -> void:
	_arena = Node2D.new()
	root.add_child(_arena)
	_run()


func _run() -> void:
	await process_frame
	_test_enemy_is_mortal_and_still_enemy()
	_test_boss_is_mortal_and_still_enemy()
	_test_crate_is_destructible_but_NOT_mortal()
	_test_shattered_crate_leaves_destructible()
	_test_a_mortal_scan_finds_the_fighters_only()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Mortal-group tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Mortal-group tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _spawn(path: String) -> Node:
	var n: Node = (load(path) as PackedScene).instantiate()
	_arena.add_child(n)
	return n


func _test_enemy_is_mortal_and_still_enemy() -> void:
	var e: Node = _spawn(ENEMY_SCENE)
	_expect(e.is_in_group(MORTAL), "a spawned enemy joins `mortal`")
	_expect(e.is_in_group("enemy"), "...and is STILL in `enemy` (the clear gate reads it)")
	e.free()
	_completes("enemy_is_mortal_and_still_enemy")


## The Boss inherits the group join through super._ready() rather than repeating
## it — which is exactly the kind of thing that silently stops happening.
func _test_boss_is_mortal_and_still_enemy() -> void:
	var b: Node = _spawn(BOSS_SCENE)
	_expect(b.is_in_group(MORTAL), "the guardian joins `mortal` (via Enemy._ready)")
	_expect(b.is_in_group("enemy"), "...and is STILL in `enemy`")
	b.free()
	_completes("boss_is_mortal_and_still_enemy")


## Cover is already faction-blind and is found by its OWN scan. Adding it to
## `mortal` puts it in the path of both scans, so it takes double damage from
## every spell in the game. This assertion is the guard against re-adding it.
func _test_crate_is_destructible_but_NOT_mortal() -> void:
	var c: Node = _spawn(CRATE_SCENE)
	_expect(c.is_in_group("destructible"), "a crate is in `destructible` (its own scan finds it)")
	_expect(not c.is_in_group(MORTAL),
		"a crate is NOT in `mortal` — both scans would find it and halve all cover")
	c.free()
	_completes("crate_is_destructible_but_NOT_mortal")


## A dead crate must leave its group in the same breath it shatters, or the
## second scan of the same blast hits a corpse.
func _test_shattered_crate_leaves_destructible() -> void:
	var c: Node = _spawn(CRATE_SCENE)
	c.call("take_damage", 5)
	_expect(c.is_in_group("destructible"), "a damaged-but-alive crate stays destructible")
	_expect(not c.is_in_group(MORTAL), "...and never gains `mortal` by being hit")
	c.call("take_damage", 9999)
	_expect(not c.is_in_group("destructible"), "a shattered crate leaves `destructible`")
	_completes("shattered_crate_leaves_destructible")


## THE WHOLE POINT, as a spectacle would see it: one group scan, every FIGHTER
## in the room, whichever faction it belongs to — and no cover, because cover
## has its own pass.
func _test_a_mortal_scan_finds_the_fighters_only() -> void:
	var fighters: Array[Node] = [_spawn(ENEMY_SCENE), _spawn(BOSS_SCENE)]
	var crate: Node = _spawn(CRATE_SCENE)
	var found: Array = get_nodes_in_group(MORTAL)
	for b: Node in fighters:
		_expect(found.has(b), "a `mortal` scan finds %s" % b.get_class())
	_expect(not found.has(crate), "a `mortal` scan does NOT also find the crate")
	# Membership is meaningful rather than decorative only if they answer to damage.
	for b: Node in fighters:
		_expect(b.has_method("take_damage"), "%s in `mortal` can actually take damage" % b.get_class())
	for b: Node in fighters:
		b.free()
	crate.free()
	_completes("a_mortal_scan_finds_the_fighters_only")
