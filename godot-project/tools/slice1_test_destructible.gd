# Run: godot --headless --path godot-project --script tools/slice1_test_destructible.gd
# Note: tests run on the first _process frame (not _init) because
# DestructibleProp.gd references the Sfx autoload, and autoload globals are
# only registered with GDScript after the main loop is set up — so the prop
# scene and the decal script are load()ed at runtime, never preload()ed.
extends SceneTree

## ⚠ FLOOR MARKS ARE OFF BY DEFAULT NOW — maker: *"these things that stay afterwards,
## remove all of them"*. The decal machinery this suite guards is still real; it just
## no longer runs in play. The suite turns it on for itself rather than being deleted
## with the feature.


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
	"prop_starts_at_max_hp",
	"partial_damage_does_not_shatter",
	"lethal_damage_shatters_and_drops_decal",
	"decal_spawn_group_position_z",
	"decal_cap_frees_oldest",
]

var _fails: int = 0
var _completed: Dictionary = {}

const PROP_SCENE_PATH: String = "res://scenes/combat/DestructibleProp.tscn"
const DECAL_SCRIPT_PATH: String = "res://scripts/combat/ScorchDecal.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	ScorchDecal.leave_marks = true
	GroundCrater.leave_marks = true
	if _ran:
		return false
	_ran = true
	_test_prop_starts_at_max_hp()
	_test_partial_damage_does_not_shatter()
	_test_lethal_damage_shatters_and_drops_decal()
	_test_decal_spawn_group_position_z()
	_test_decal_cap_frees_oldest()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 destructible tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 destructible tests: all PASS")
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


func _make_prop() -> StaticBody2D:
	# Runtime load: compiles after autoload globals (Sfx) are registered.
	var prop_scene: PackedScene = load(PROP_SCENE_PATH)
	var prop: StaticBody2D = prop_scene.instantiate()
	root.add_child(prop)  # freed with root at exit
	return prop


## Live decals only: queue_free()d nodes linger in the group until end of frame.
func _alive_decals() -> Array[Node]:
	var alive: Array[Node] = []
	for decal: Node in get_nodes_in_group("floor_decal"):
		if is_instance_valid(decal) and not decal.is_queued_for_deletion():
			alive.append(decal)
	return alive


func _test_prop_starts_at_max_hp() -> void:
	var prop: StaticBody2D = _make_prop()
	_expect(prop.max_hp == 30, "default max_hp is 30")
	_expect(prop.hp == prop.max_hp, "prop starts at max_hp")
	_expect(prop.is_in_group("destructible"), "prop joins the destructible group")
	_completes("prop_starts_at_max_hp")


func _test_partial_damage_does_not_shatter() -> void:
	var prop: StaticBody2D = _make_prop()
	prop.take_damage(10)
	_expect(prop.hp == prop.max_hp - 10, "partial hit subtracts hp")
	_expect(not prop.is_queued_for_deletion(), "partial hit does not shatter")
	_expect(prop.is_in_group("destructible"), "damaged prop stays targetable")
	_completes("partial_damage_does_not_shatter")


func _test_lethal_damage_shatters_and_drops_decal() -> void:
	var prop: StaticBody2D = _make_prop()
	var decals_before: int = _alive_decals().size()
	prop.take_damage(prop.max_hp)
	_expect(prop.hp == 0, "lethal hit zeroes hp")
	_expect(prop.is_queued_for_deletion(), "shattered prop queues for deletion")
	_expect(
		not prop.is_in_group("destructible"),
		"shattered prop leaves the destructible group immediately"
	)
	_expect(
		_alive_decals().size() == decals_before + 1,
		"shatter drops exactly one floor decal"
	)
	# Overkill after death must be a no-op, not a second shatter.
	prop.take_damage(999)
	_expect(
		_alive_decals().size() == decals_before + 1, "post-death damage spawns nothing"
	)
	_completes("lethal_damage_shatters_and_drops_decal")


func _test_decal_spawn_group_position_z() -> void:
	var decal_script: GDScript = load(DECAL_SCRIPT_PATH)
	var before: int = _alive_decals().size()
	decal_script.spawn(root, Vector2(123, 45), 30.0, "scorch", Color(0.1, 0.05, 0.02, 0.6))
	var alive: Array[Node] = _alive_decals()
	_expect(alive.size() == before + 1, "spawn adds one node to floor_decal group")
	if alive.size() != before + 1:
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var decal: Node2D = alive[alive.size() - 1] as Node2D
	_expect(decal != null, "spawned decal is a Node2D")
	if decal == null:
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	_expect(decal.global_position == Vector2(123, 45), "decal sits at the given position")
	_expect(decal.z_index == -1, "decal z_index is -1 (above floor, below actors)")
	_expect(decal.radius == 30.0, "decal keeps the requested radius")
	_expect(decal.kind == "scorch", "decal keeps the requested kind")
	# Null-parent guard: must not crash, must not add a decal.
	decal_script.spawn(null, Vector2.ZERO, 10.0, "crack", Color.BLACK)
	_expect(_alive_decals().size() == before + 1, "null parent spawns nothing")
	_completes("decal_spawn_group_position_z")


func _test_decal_cap_frees_oldest() -> void:
	var decal_script: GDScript = load(DECAL_SCRIPT_PATH)
	# Clear decals from earlier tests so the cap math is exact.
	for old: Node in _alive_decals():
		old.queue_free()
	var cap: int = decal_script.MAX_DECALS
	for i: int in cap:
		decal_script.spawn(root, Vector2(float(i), 0.0), 8.0, "crack", Color(0, 0, 0, 0.5))
	var alive: Array[Node] = _alive_decals()
	_expect(alive.size() == cap, "exactly MAX_DECALS decals stay alive")
	var oldest: Node = alive[0]
	_expect(not oldest.is_queued_for_deletion(), "at the cap nothing is freed yet")
	decal_script.spawn(root, Vector2(999, 0), 8.0, "scorch", Color(0, 0, 0, 0.5))
	_expect(
		oldest.is_queued_for_deletion(), "one past the cap frees the oldest decal"
	)
	_expect(
		_alive_decals().size() == cap, "live decal count holds at MAX_DECALS"
	)
	_completes("decal_cap_frees_oldest")
