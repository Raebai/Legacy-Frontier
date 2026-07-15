# Run: godot --headless --path godot-project --script tools/slice3_test_destructible_terrain.gd
# Note: tests run on the first _process frame (not _init) because
# DestructibleTerrain.gd references the Sfx and Juice autoloads, and autoload
# globals are only registered with GDScript after the main loop is set up —
# so the terrain script is load()ed at runtime, never preload()ed.
# (Same harness shape as tools/slice1_test_destructible.gd.)
extends SceneTree

const TERRAIN_SCRIPT_PATH: String = "res://scripts/combat/DestructibleTerrain.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_terrain_starts_at_max_hp()
	failed += _test_partial_damage_does_not_break()
	failed += _test_cumulative_damage_breaks_at_zero()
	failed += _test_post_death_damage_is_a_noop()
	if failed > 0:
		printerr("Slice3 destructible-terrain tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice3 destructible-terrain tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_terrain() -> StaticBody2D:
	# Runtime load: compiles after autoload globals (Sfx, Juice) are registered.
	var terrain_script: GDScript = load(TERRAIN_SCRIPT_PATH)
	var terrain: StaticBody2D = terrain_script.new()
	root.add_child(terrain)  # freed with root at exit; _ready builds the collider
	return terrain


func _test_terrain_starts_at_max_hp() -> int:
	var failed: int = 0
	var terrain: StaticBody2D = _make_terrain()
	failed += _expect(terrain.max_hp == 120, "default max_hp is 120 (cover chips + lasts)")
	failed += _expect(terrain.hp == terrain.max_hp, "terrain starts at max_hp")
	failed += _expect(
		terrain.is_in_group("destructible"), "terrain joins the destructible group"
	)
	failed += _expect(
		terrain.block_size == Vector2(64, 64), "default block_size is 64x64"
	)
	# The collider is built in code in _ready — verify it exists and matches.
	var collider: CollisionShape2D = null
	for child: Node in terrain.get_children():
		if child is CollisionShape2D:
			collider = child
			break
	failed += _expect(collider != null, "terrain builds a CollisionShape2D in _ready")
	if collider != null:
		var rect_shape: RectangleShape2D = collider.shape as RectangleShape2D
		failed += _expect(rect_shape != null, "collider shape is a RectangleShape2D")
		if rect_shape != null:
			# The collider grows DOWN by GROUND_OVERLAP_MARGIN (8px; the visual face
			# stays block_size) so there's no flush T-junction seam you can walk under.
			var margin: float = float((terrain.get_script() as GDScript).get_script_constant_map().get("GROUND_OVERLAP_MARGIN", 8.0))
			var block: Vector2 = terrain.get("block_size")
			var expected: Vector2 = block + Vector2(0.0, margin)
			failed += _expect(
				rect_shape.size == expected, "collider size = block_size grown down by the overlap margin"
			)
	return failed


func _test_partial_damage_does_not_break() -> int:
	var failed: int = 0
	var terrain: StaticBody2D = _make_terrain()
	terrain.take_damage(20)
	failed += _expect(terrain.hp == terrain.max_hp - 20, "partial hit subtracts hp")
	failed += _expect(
		not terrain.is_queued_for_deletion(), "partial hit does not break the block"
	)
	failed += _expect(
		terrain.is_in_group("destructible"), "damaged terrain stays targetable"
	)
	return failed


func _test_cumulative_damage_breaks_at_zero() -> int:
	var failed: int = 0
	var terrain: StaticBody2D = _make_terrain()
	terrain.take_damage(terrain.max_hp - 20)
	failed += _expect(
		not terrain.is_queued_for_deletion(), "heavy sub-lethal damage leaves the block standing"
	)
	terrain.take_damage(20)  # cumulative == max_hp
	failed += _expect(terrain.hp == 0, "cumulative lethal damage zeroes hp")
	failed += _expect(
		terrain.is_queued_for_deletion(), "broken terrain queues for deletion"
	)
	failed += _expect(
		not terrain.is_in_group("destructible"),
		"broken terrain leaves the destructible group immediately"
	)
	return failed


func _test_post_death_damage_is_a_noop() -> int:
	var failed: int = 0
	var terrain: StaticBody2D = _make_terrain()
	var decals_before: int = _alive_decals().size()
	terrain.take_damage(terrain.max_hp)
	failed += _expect(terrain.is_queued_for_deletion(), "lethal hit frees the block")
	# Shatter now bursts into physics DebrisChunks (group "debris_chunk") and
	# drops NO floor decal — the block stood in the air, so a crack mark there
	# just floated. Verify physics rubble spawned and no decal was dropped.
	failed += _expect(
		_alive_decals().size() == decals_before,
		"terrain shatter drops no floor decal (was a floating spider)"
	)
	failed += _expect(
		get_nodes_in_group("debris_chunk").size() > 0,
		"terrain shatter bursts into physics debris chunks"
	)
	# Overkill after death must be a safe no-op: no crash, no second shatter.
	terrain.take_damage(999)
	failed += _expect(terrain.hp == 0, "post-death damage leaves hp at 0")
	failed += _expect(
		_alive_decals().size() == decals_before, "post-death damage spawns nothing"
	)
	return failed


## Live decals only: queue_free()d nodes linger in the group until end of frame.
func _alive_decals() -> Array[Node]:
	var alive: Array[Node] = []
	for decal: Node in get_nodes_in_group("floor_decal"):
		if is_instance_valid(decal) and not decal.is_queued_for_deletion():
			alive.append(decal)
	return alive
