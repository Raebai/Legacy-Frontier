# Run: godot --headless --path godot-project --script tools/slice1_test_destructible.gd
# Note: tests run on the first _process frame (not _init) because
# DestructibleProp.gd references the Sfx autoload, and autoload globals are
# only registered with GDScript after the main loop is set up — so the prop
# scene and the decal script are load()ed at runtime, never preload()ed.
extends SceneTree

const PROP_SCENE_PATH: String = "res://scenes/combat/DestructibleProp.tscn"
const DECAL_SCRIPT_PATH: String = "res://scripts/combat/ScorchDecal.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_prop_starts_at_max_hp()
	failed += _test_partial_damage_does_not_shatter()
	failed += _test_lethal_damage_shatters_and_drops_decal()
	failed += _test_decal_spawn_group_position_z()
	failed += _test_decal_cap_frees_oldest()
	if failed > 0:
		printerr("Slice1 destructible tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 destructible tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


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


func _test_prop_starts_at_max_hp() -> int:
	var failed: int = 0
	var prop: StaticBody2D = _make_prop()
	failed += _expect(prop.max_hp == 30, "default max_hp is 30")
	failed += _expect(prop.hp == prop.max_hp, "prop starts at max_hp")
	failed += _expect(prop.is_in_group("destructible"), "prop joins the destructible group")
	return failed


func _test_partial_damage_does_not_shatter() -> int:
	var failed: int = 0
	var prop: StaticBody2D = _make_prop()
	prop.take_damage(10)
	failed += _expect(prop.hp == prop.max_hp - 10, "partial hit subtracts hp")
	failed += _expect(not prop.is_queued_for_deletion(), "partial hit does not shatter")
	failed += _expect(prop.is_in_group("destructible"), "damaged prop stays targetable")
	return failed


func _test_lethal_damage_shatters_and_drops_decal() -> int:
	var failed: int = 0
	var prop: StaticBody2D = _make_prop()
	var decals_before: int = _alive_decals().size()
	prop.take_damage(prop.max_hp)
	failed += _expect(prop.hp == 0, "lethal hit zeroes hp")
	failed += _expect(prop.is_queued_for_deletion(), "shattered prop queues for deletion")
	failed += _expect(
		not prop.is_in_group("destructible"),
		"shattered prop leaves the destructible group immediately"
	)
	failed += _expect(
		_alive_decals().size() == decals_before + 1,
		"shatter drops exactly one floor decal"
	)
	# Overkill after death must be a no-op, not a second shatter.
	prop.take_damage(999)
	failed += _expect(
		_alive_decals().size() == decals_before + 1, "post-death damage spawns nothing"
	)
	return failed


func _test_decal_spawn_group_position_z() -> int:
	var failed: int = 0
	var decal_script: GDScript = load(DECAL_SCRIPT_PATH)
	var before: int = _alive_decals().size()
	decal_script.spawn(root, Vector2(123, 45), 30.0, "scorch", Color(0.1, 0.05, 0.02, 0.6))
	var alive: Array[Node] = _alive_decals()
	failed += _expect(alive.size() == before + 1, "spawn adds one node to floor_decal group")
	if alive.size() != before + 1:
		return failed
	var decal: Node2D = alive[alive.size() - 1] as Node2D
	failed += _expect(decal != null, "spawned decal is a Node2D")
	if decal == null:
		return failed
	failed += _expect(decal.global_position == Vector2(123, 45), "decal sits at the given position")
	failed += _expect(decal.z_index == -1, "decal z_index is -1 (above floor, below actors)")
	failed += _expect(decal.radius == 30.0, "decal keeps the requested radius")
	failed += _expect(decal.kind == "scorch", "decal keeps the requested kind")
	# Null-parent guard: must not crash, must not add a decal.
	decal_script.spawn(null, Vector2.ZERO, 10.0, "crack", Color.BLACK)
	failed += _expect(_alive_decals().size() == before + 1, "null parent spawns nothing")
	return failed


func _test_decal_cap_frees_oldest() -> int:
	var failed: int = 0
	var decal_script: GDScript = load(DECAL_SCRIPT_PATH)
	# Clear decals from earlier tests so the cap math is exact.
	for old: Node in _alive_decals():
		old.queue_free()
	var cap: int = decal_script.MAX_DECALS
	for i: int in cap:
		decal_script.spawn(root, Vector2(float(i), 0.0), 8.0, "crack", Color(0, 0, 0, 0.5))
	var alive: Array[Node] = _alive_decals()
	failed += _expect(alive.size() == cap, "exactly MAX_DECALS decals stay alive")
	var oldest: Node = alive[0]
	failed += _expect(not oldest.is_queued_for_deletion(), "at the cap nothing is freed yet")
	decal_script.spawn(root, Vector2(999, 0), 8.0, "scorch", Color(0, 0, 0, 0.5))
	failed += _expect(
		oldest.is_queued_for_deletion(), "one past the cap frees the oldest decal"
	)
	failed += _expect(
		_alive_decals().size() == cap, "live decal count holds at MAX_DECALS"
	)
	return failed
