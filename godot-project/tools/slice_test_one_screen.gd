# Run: godot --headless --path godot-project --script tools/slice_test_one_screen.gd
# ONE SCREEN (Phase 1.3). Two claims, both of which used to be false:
#   1. LayoutDef.room_size ACTUALLY drives the arena geometry. It used to be read
#      in exactly one place, to position a portal, while the room itself was a
#      1200x680 box hard-coded in Arena.tscn.
#   2. The room, at its authored size, FITS inside the fit-all camera — which is
#      now on for every floor, not just boss floors.
#
# The scene is reached BY PATH and everything on it by NAME (.call/.get), the
# capture-tool idiom: a --script harness has no autoloads registered, so naming a
# class whose dependency chain touches one is a compile error before frame one.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures". So: failures accumulate on the MEMBER
# `_fails`, and every test's last line records that it reached the end — a test
# that aborts part-way is missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"default_room_fits_one_screen",
	"walls_are_built_from_room_size",
	"resizing_does_not_share_shapes",
	"every_authored_layout_fits",
	"frame_all_on_for_every_floor_type",
	"a_spell_can_carve_the_tower_floor",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ARENA_PATH: String = "res://scenes/combat/Arena.tscn"
const CAMERA_PATH: String = "res://scripts/combat/CombatCamera.gd"
const GS_PATH: String = "res://scripts/GameState.gd"

var _arena: Node2D = null


func _initialize() -> void:
	_arena = (load(ARENA_PATH) as PackedScene).instantiate()
	root.add_child(_arena)
	_run()


func _run() -> void:
	await process_frame
	_test_default_room_fits_one_screen()
	_test_walls_are_built_from_room_size()
	_test_resizing_does_not_share_shapes()
	_test_every_authored_layout_fits()
	_test_frame_all_on_for_every_floor_type()
	await _test_a_spell_can_carve_the_tower_floor()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("One-screen tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("One-screen tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## THE ACTUAL "one screen" ARITHMETIC, read off CombatCamera rather than
## re-typed here: the widest the fit-all camera can ever go is the base viewport
## divided by FRAME_ZOOM_MIN, and FRAME_PAD is breathing room the framing always
## adds around the group. Whatever is left is how big a room may be.
func _max_room_size() -> Vector2:
	var cam: GDScript = load(CAMERA_PATH) as GDScript
	var viewport: Vector2 = cam.FRAME_VIEWPORT
	var pad: Vector2 = cam.FRAME_PAD
	var zoom_min: float = cam.FRAME_ZOOM_MIN
	return viewport / zoom_min - pad


func _fits(size: Vector2) -> bool:
	var mx: Vector2 = _max_room_size()
	return size.x <= mx.x and size.y <= mx.y


func _test_default_room_fits_one_screen() -> void:
	var layout: Resource = load("res://scripts/tower/LayoutDef.gd").new()
	var size: Vector2 = layout.room_size
	var mx: Vector2 = _max_room_size()
	_expect(_fits(size),
		"the default room %s fits the framing camera's %s" % [str(size), str(mx)])
	# ...and it is not absurdly small either — a one-screen arena is still an arena.
	_expect(size.x >= mx.x * 0.6 and size.y >= mx.y * 0.6,
		"the default room uses most of the screen it is allowed (%s of %s)" % [str(size), str(mx)])
	# The spawn rect and the hero start have to live INSIDE the room they describe.
	_expect(layout.spawn_rect_max.x < size.x and layout.spawn_rect_max.y < size.y,
		"the spawn rect fits inside the room")
	_expect(layout.hero_start.x < size.x and layout.hero_start.y < size.y,
		"the hero starts inside the room")
	_expect(layout.exit_point.x < size.x and layout.exit_point.y < size.y,
		"the exit portal sits inside the room")
	_completes("default_room_fits_one_screen")


## ══ A SPELL CAN ACTUALLY BITE A TOWER FLOOR ═══════════════════════
## Maker, watching the bot fights: *"please ensure the main game has all of these ...
## and like its similar in how the maps get destroyed"*.
##
## ⚠ IT COULD NOT, AND THE FAILURE WAS COMPLETELY SILENT. `VersusArena` held the only
## line in the project that ever constructed a `DestructibleStage`, so the showcase,
## the duel and FreePlay had destructible ground and the tower — the actual game — had
## none. Both carve routes die quietly on a floor with no stage: `carve_area` scans
## `GROUP_NAME`, finds no members, returns 0; `carve_from_body` looks for `BODY_META`
## on the collider it hit, which the tower's plain `Walls/WallBottom` has never
## carried. Twenty-one call sites across the spell files, all dead, and NOTHING logged
## it, because the refusal counters that would have said so live on the stage that
## does not exist.
##
## So the assertion is deliberately made THROUGH `carve_area` rather than by poking
## the stage directly: the thing that was broken is the lookup, and a test that calls
## `carve_disc` on a stage it already holds would have passed on the broken build.
func _test_a_spell_can_carve_the_tower_floor() -> void:
	var size := Vector2(700.0, 400.0)
	_arena.call("_apply_room_size", size)
	await process_frame
	var ground: DestructibleStage = _arena.get_node_or_null(
		"DestructibleGround") as DestructibleStage
	_expect(ground != null, "the tower floor has a stage to carve")
	if ground == null:
		_completes("a_spell_can_carve_the_tower_floor")
		return
	var at := Vector2(size.x * 0.5, size.y - 16.0 * 0.5 + 2.0)
	var before: int = ground.carved_cells
	# A blast's numbers: the footprint band the size rule is anchored on.
	var removed: int = DestructibleStage.carve_area(_arena, 90, at, Vector2.UP, 90.0)
	_expect(removed > 0,
		"a blast at the middle of a tower floor removed %d cells. Either the room has no"
			% removed
		+ " stage in `GROUP_NAME`, or the carve landed where there is no rock — both of"
		+ " which look identical from a spell's side, which is why this was invisible.")
	_expect(ground.carved_cells > before,
		"the stage counted the carve (%d -> %d cells)" % [before, ground.carved_cells])
	# ══ ...AND THE FLOOR IS STILL A FLOOR ═══════════════════════════
	# The versus stage can absorb craters because its terraces are 320 px deep against a
	# 46 px maximum crater; a tower room's rock is `GROUND_SLAB_DEPTH`, which is much
	# thinner. The answer is not more depth, it is BEDROCK: `WallBottom` sits under the
	# slab, so however much rock is removed there is always a floor beneath it. Asserted
	# because the alternative — a wave fight where the ground can be deleted and the
	# party falls out of the world — is the way this feature would go wrong.
	var walls: Node = _arena.get_node_or_null("Walls")
	var bed: CollisionShape2D = null
	if walls != null:
		bed = walls.get_node_or_null("WallBottom") as CollisionShape2D
	_expect(bed != null and bed.shape is RectangleShape2D,
		"the bedrock collider is still there after a carve")
	if bed != null:
		# BELOW THE KILL LINE, not merely below the rock. A wall anywhere a falling body
		# could land on turns "you fell out of the world" into "you are standing in a pit
		# you cannot leave", which is the worse of the two failures.
		var kill_line: float = size.y + float(_arena.get("FALL_OUT_MARGIN"))
		_expect(bed.position.y > kill_line,
			"the bottom wall is at y=%.1f and the fall-out kill line is y=%.1f. Anything"
				% [bed.position.y, kill_line]
			+ " a body can land on above that line catches it instead of letting it fall"
			+ " out, and a carved hole becomes a pit rather than a hole.")
	_completes("a_spell_can_carve_the_tower_floor")


## The floor rect and all four wall colliders are REBUILT from room_size. Before
## 1.3 these were four fixed sub-resources sized for a 1200x680 box.
func _test_walls_are_built_from_room_size() -> void:
	var size := Vector2(700.0, 400.0)
	_arena.call("_apply_room_size", size)
	var floor_rect: ColorRect = _arena.get_node_or_null("Floor") as ColorRect
	_expect(floor_rect != null, "the arena still has its Floor rect")
	if floor_rect != null:
		_expect(is_equal_approx(floor_rect.offset_right, size.x)
				and is_equal_approx(floor_rect.offset_bottom, size.y),
			"the floor rect matches room_size (got %s)"
				% str(Vector2(floor_rect.offset_right, floor_rect.offset_bottom)))
	var walls: Node = _arena.get_node_or_null("Walls")
	_expect(walls != null, "the arena still has its Walls body")
	if walls == null:
		return   # deliberately NOT completed: the missing sentinel fails the suite
	var thickness: float = float(_arena.get("WALL_THICKNESS"))
	var fall: float = float(_arena.get("FALL_OUT_MARGIN"))
	# ⚠ THIS ROW HAS NOW RECORDED TWO SUPERSEDED RULINGS IN ONE DAY, WHICH IS THE POINT
	# OF WRITING THEM DOWN. It first pinned the wall centred on `size.y`, its top face
	# exactly on the standable line. When the tower's ground became a `DestructibleStage`
	# slab the wall moved to the slab's UNDERSIDE as bedrock, so a crater was a hole you
	# could drop INTO but never THROUGH — my call, to stop a wave fight losing its floor.
	#
	# The maker reversed it: *"there should be a under the floor that you can fall out
	# of"*. So the rock is the only floor, and the wall sits below the kill line where it
	# catches nothing — kept so the physics world still has a bottom.
	#
	# The invariant worth pinning was never the wall's y under any of the three. It is
	# that THE SURFACE A FIGHTER STANDS ON DID NOT MOVE, which is asserted below and has
	# survived all three unchanged.
	var expected: Dictionary = {
		"WallTop": [Vector2(size.x * 0.5, 0.0), Vector2(size.x, thickness)],
		"WallBottom": [Vector2(size.x * 0.5, size.y + fall + thickness),
			Vector2(size.x, thickness)],
		"WallLeft": [Vector2(0.0, size.y * 0.5), Vector2(thickness, size.y)],
		"WallRight": [Vector2(size.x, size.y * 0.5), Vector2(thickness, size.y)],
	}
	for wall_name: String in expected:
		var cs: CollisionShape2D = walls.get_node_or_null(wall_name) as CollisionShape2D
		_expect(cs != null, "%s exists" % wall_name)
		if cs == null:
			continue
		var want_pos: Vector2 = expected[wall_name][0]
		var want_size: Vector2 = expected[wall_name][1]
		_expect(cs.position.is_equal_approx(want_pos),
			"%s sits at %s (got %s)" % [wall_name, str(want_pos), str(cs.position)])
		var shape: RectangleShape2D = cs.shape as RectangleShape2D
		_expect(shape != null, "%s still has a rectangle shape" % wall_name)
		if shape != null:
			_expect(shape.size.is_equal_approx(want_size),
				"%s is %s (got %s)" % [wall_name, str(want_size), str(shape.size)])
	# ══ THE STANDABLE LINE, WHICH IS THE THING THAT MUST NOT MOVE ═══════════
	# Everything on a floor is placed against it: spawn points, ledge heights, the
	# ground cap `RoomShell` paints, the y `FloorGen` hands out. The rock slab was added
	# BELOW it rather than on top of it precisely so none of that had to move, and this
	# is the assertion that says so out loud.
	var ground: DestructibleStage = _arena.get_node_or_null(
		"DestructibleGround") as DestructibleStage
	_expect(ground != null,
		"the tower floor has a DestructibleStage. Without one every carve in the game is"
		+ " a no-op here: `carve_area` scans a group with no members and returns 0, and"
		+ " nothing logs it, because the refusal counters live on the stage.")
	if ground != null:
		var surface: float = ground.surface_y_at(size.x * 0.5)
		_expect(absf(surface - (size.y - thickness * 0.5)) <= DestructibleStage.CHUNK,
			"the rock's top face is at y=%.1f, and the line fighters have always stood on"
				% surface
			+ " is y=%.1f. Adding the slab moved the floor out from under every spawn"
				% (size.y - thickness * 0.5)
			+ " point and ledge height on the floor.")
	# A second, different size re-drives it — the room is not a one-shot.
	_arena.call("_apply_room_size", Vector2(960.0, 480.0))
	var top: CollisionShape2D = walls.get_node_or_null("WallTop") as CollisionShape2D
	if top != null and top.shape is RectangleShape2D:
		_expect(is_equal_approx((top.shape as RectangleShape2D).size.x, 960.0),
			"resizing again re-drives the walls")
	_completes("walls_are_built_from_room_size")


## The wall shapes arrive as .tscn sub-resources. If they were mutated in place
## while still shared, this floor's size would leak into every other scene that
## loads the same resource — so each is duplicated on first resize, and the four
## must not end up aliasing each other either.
func _test_resizing_does_not_share_shapes() -> void:
	var walls: Node = _arena.get_node_or_null("Walls")
	if walls == null:
		_expect(false, "the arena has a Walls body")
		return   # deliberately NOT completed
	_arena.call("_apply_room_size", Vector2(800.0, 500.0))
	var seen: Array = []
	for wall_name: String in ["WallTop", "WallBottom", "WallLeft", "WallRight"]:
		var cs: CollisionShape2D = walls.get_node_or_null(wall_name) as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		_expect(not seen.has(cs.shape.get_instance_id()),
			"%s has its own shape resource (not shared with another wall)" % wall_name)
		seen.append(cs.shape.get_instance_id())
	# A pristine copy of the scene must still carry the AUTHORED size, proving the
	# resize above did not write through to the shared .tscn sub-resource.
	var fresh: Node2D = (load(ARENA_PATH) as PackedScene).instantiate()
	var fresh_top: CollisionShape2D = fresh.get_node_or_null("Walls/WallTop") as CollisionShape2D
	if fresh_top != null and fresh_top.shape is RectangleShape2D:
		_expect(not is_equal_approx((fresh_top.shape as RectangleShape2D).size.x, 800.0),
			"resizing one arena did not write through to the packed scene's shape")
	fresh.free()
	_completes("resizing_does_not_share_shapes")


## Every floor the default tower ships — and every synthesized fallback floor —
## has to fit on one screen, not just the default LayoutDef.
func _test_every_authored_layout_fits() -> void:
	var gs: GDScript = load(GS_PATH) as GDScript
	var tower: Resource = gs.build_default_tower()
	for i: int in (tower.floors as Array).size():
		var layout: Resource = tower.floors[i].layout
		_expect(layout != null, "floor %d has a layout" % (i + 1))
		if layout == null:
			continue
		_expect(_fits(layout.room_size),
			"floor %d's room %s fits one screen" % [i + 1, str(layout.room_size)])
		# Crates and pickups must be inside the walls, or a floor ships cover you
		# can never reach.
		for pos: Vector2 in layout.crate_positions:
			_expect(pos.x > 0.0 and pos.y > 0.0
					and pos.x < layout.room_size.x and pos.y < layout.room_size.y,
				"floor %d crate %s is inside the room" % [i + 1, str(pos)])
		for pos: Vector2 in layout.weapon_pickups:
			_expect(pos.x > 0.0 and pos.y > 0.0
					and pos.x < layout.room_size.x and pos.y < layout.room_size.y,
				"floor %d pickup %s is inside the room" % [i + 1, str(pos)])
	for f: int in [1, 3, 5, 9]:
		var synth: Resource = gs.synthesize_floor_def(f)
		_expect(_fits(synth.layout.room_size),
			"the synthesized floor-%d room fits one screen" % f)
	_completes("every_authored_layout_fits")


## 1.3's policy flip: fit-all framing used to be a BOSS-floor special case. It is
## the default now, so this asserts the arena asks for it on EVERY floor type.
func _test_frame_all_on_for_every_floor_type() -> void:
	var cam := _CamStub.new()
	cam.add_to_group("combat_camera")
	_arena.add_child(cam)
	var gs: GDScript = load(GS_PATH) as GDScript
	var tower: Resource = gs.build_default_tower()
	for i: int in (tower.floors as Array).size():
		cam.last = false
		cam.calls = 0
		_arena.set("_current_floor_def", tower.floors[i])
		_arena.call("_apply_floor_camera")
		_expect(cam.calls == 1, "floor %d asked the camera exactly once" % (i + 1))
		_expect(cam.last, "floor %d (type %d) frames the whole arena"
			% [i + 1, int(tower.floors[i].floor_type)])
	# ...including with no floor def at all (the sandbox / boss-rush path).
	cam.last = false
	_arena.set("_current_floor_def", null)
	_arena.call("_apply_floor_camera")
	_expect(cam.last, "fit-all framing is on even without a floor def")
	cam.free()
	_completes("frame_all_on_for_every_floor_type")


## Stand-in camera: joins "combat_camera" and records what set_frame_all was told.
class _CamStub extends Node2D:
	var last: bool = false
	var calls: int = 0

	func set_frame_all(enabled: bool) -> void:
		last = enabled
		calls += 1
