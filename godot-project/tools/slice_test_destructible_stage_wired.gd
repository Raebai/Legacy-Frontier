# Run: godot --headless --path godot-project --script tools/slice_test_destructible_stage_wired.gd
#
# THE FLAGGED DESTRUCTIBLE STAGE, MEASURED ON THE SURFACE A FIGHTER ACTUALLY LANDS ON.
#
# `slice_test_destructible_stage` proves the GRID is right: `surface_y_at` returns the
# authored terrace surfaces, the merge covers every intact chunk, nothing grows upward.
# All of that is the model's own opinion of itself. This suite asks the physics server
# instead — it boots the real `VersusArena` twice, once with the flag off and once with
# it on, and casts a ray down onto the ground at ~100 x positions across the whole stage.
#
# ⚠ WHY A/B AND NOT ONLY AN ABSOLUTE ASSERT. The claim being tested is not "the floor is
# at 780"; it is "swapping five boxes for a merged chunk grid moves nothing". An A/B
# holds that line everywhere, not just at five hand-picked probes, and it fails on the
# exact x where the two disagree — which is the number a fix needs.
# [[feedback_verify_the_drawn_channel]]: read the channel the CharacterBody gets, not
# the one the model computed. The five authored surfaces are asserted absolutely too,
# because a shared wrong answer is still a wrong answer.
#
# ⚠ THE RAY EXCLUDES EVERYTHING THAT IS NOT GROUND. Cover blocks, ruin platforms,
# breakable platforms and the two fighters are all CollisionObject2Ds standing in the
# same column. They are identical in both configurations, so leaving them in would not
# break the A/B — it would just mean half the sweep measured a crate. The exclusion list
# is built from the live tree, so the ray reports rock or nothing.
#
# ⚠ HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the enclosing
# function and hands back the type's zero, which that idiom reads as "no failures".
# Failures accumulate on `_fails`; each test records a COMPLETION SENTINEL as its last
# line, so an aborted test fails BY ABSENCE.
#
# ⚠ LOADED BY SCRIPT PATH, NOT BY `class_name` — naming the class in a `--script` run
# drags its compile-time dependencies in. Same reason as `slice_test_arena_builds`.
extends SceneTree

const ARENA_SCENE_PATH: String = "res://scenes/combat/VersusArena.tscn"
const ARENA_SCRIPT_PATH: String = "res://scripts/combat/VersusArena.gd"

## `_ready` builds the terrain synchronously; these are settle margin, and they are also
## what lets the physics server register the fresh bodies before the first ray.
const SETTLE_FRAMES: int = 8

## The stage spans x 40..1965. Sweep past both ends on purpose: gaining rock outside the
## authored stage is exactly the failure a grid that grew rather than shrank would make.
const SWEEP_X0: float = 0.0
const SWEEP_X1: float = 2000.0
const SWEEP_STEP: float = 20.0

## Above the highest terrace (528) and below the deepest rock (780 + 320 = 1100).
const RAY_TOP: float = 300.0
const RAY_BOTTOM: float = 1300.0

## The five authored surfaces of variant 0, for the absolute reading.
const PROBES: Array[Array] = [
	[700.0, 780.0],    # main fight floor
	[120.0, 700.0],    # left mound
	[1450.0, 696.0],   # first step
	[1600.0, 612.0],   # second step
	[1900.0, 528.0],   # right bluff
]

const TESTS: Array[String] = [
	"the_flag_off_path_is_the_five_terrace_boxes",
	"the_flag_on_path_is_one_body_and_no_loose_terraces",
	"the_ground_a_ray_lands_on_is_identical_either_way",
	"the_flagged_stage_puts_the_five_surfaces_where_they_were_authored",
	"the_flag_adds_a_floor_ring_out_and_the_shipped_stage_keeps_two",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _script: GDScript = null

## Filled by the two boots.
var _off: Dictionary = {}          # x -> surface y, or INF for no ground
var _on: Dictionary = {}
var _off_terraces: int = -1
var _on_terraces: int = -1
var _off_stage_bodies: int = -1
var _on_stage_bodies: int = -1
var _on_shapes: int = -1
var _off_pits: int = -1
var _on_pits: int = -1


func _initialize() -> void:
	_script = load(ARENA_SCRIPT_PATH) as GDScript
	if _script == null:
		printerr("destructible_stage_wired: FAIL — could not load VersusArena.gd")
		print("destructible stage wired tests: FAILED (1 failure(s))")
		quit(1)
		return
	_run()


func _run() -> void:
	# Pin the layout: the flag has to be compared against a FIXED silhouette, or the two
	# boots could roll different stages and the A/B would compare two different maps.
	var prior_layout: Variant = _script.get("stage_layout")
	_script.set("stage_layout", 0)

	_script.set("destructible_stage", false)
	await _boot_and_measure(false)
	_script.set("destructible_stage", true)
	await _boot_and_measure(true)
	_script.set("destructible_stage", false)
	_script.set("stage_layout", prior_layout)

	the_flag_off_path_is_the_five_terrace_boxes()
	the_flag_on_path_is_one_body_and_no_loose_terraces()
	the_ground_a_ray_lands_on_is_identical_either_way()
	the_flagged_stage_puts_the_five_surfaces_where_they_were_authored()
	the_flag_adds_a_floor_ring_out_and_the_shipped_stage_keeps_two()

	for t: String in TESTS:
		_expect(_completed.has(t), "%s ran to completion" % t)
	print("destructible stage wired tests: %s (%d failure(s))"
		% ["all PASS" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("destructible_stage_wired: FAIL — %s" % what)


func _done(t: String) -> void:
	_completed[t] = true


## Boot the real arena, count what got built, and read the ground under the sweep.
func _boot_and_measure(flagged: bool) -> void:
	var scene: PackedScene = load(ARENA_SCENE_PATH) as PackedScene
	var arena: Node = scene.instantiate()
	root.add_child(arena)
	for _f: int in SETTLE_FRAMES:
		await process_frame

	var terraces: int = 0
	var stage_bodies: int = 0
	var shapes: int = 0
	var ground: Array[RID] = []
	for child: Node in arena.get_children():
		# `_make_terrace` builds a bare, script-less StaticBody2D straight onto the
		# arena. Cover, ruins and breakable platforms all carry a script, which is what
		# separates them here.
		if child is StaticBody2D and child.get_script() == null:
			terraces += 1
			ground.append((child as StaticBody2D).get_rid())
	for node: Node in arena.find_children("DestructibleStageBody", "", true, false):
		var body: StaticBody2D = node as StaticBody2D
		if body == null:
			continue
		stage_bodies += 1
		shapes += body.get_child_count()
		ground.append(body.get_rid())

	# Ring-out pits, counted per configuration. See the test at the foot of this file.
	var pits: int = 0
	for h: Node in arena.find_children("", "StageHazard", true, false):
		if int(h.get(&"mode")) == 0:  # StageHazard.Mode.PIT
			pits += 1

	var exclude: Array[RID] = []
	_collect_non_ground(arena, ground, exclude)

	var reading: Dictionary = {}
	var x: float = SWEEP_X0
	while x <= SWEEP_X1:
		reading[x] = _ground_y_at(x, exclude)
		x += SWEEP_STEP
	for p: Array in PROBES:
		reading[float(p[0])] = _ground_y_at(float(p[0]), exclude)

	if flagged:
		_on = reading
		_on_terraces = terraces
		_on_stage_bodies = stage_bodies
		_on_shapes = shapes
		_on_pits = pits
	else:
		_off = reading
		_off_terraces = terraces
		_off_stage_bodies = stage_bodies
		_off_pits = pits

	arena.queue_free()
	await process_frame


## Every collider in the arena that is NOT ground, so the ray cannot report a crate.
func _collect_non_ground(node: Node, ground: Array[RID], out: Array[RID]) -> void:
	if node is CollisionObject2D:
		var rid: RID = (node as CollisionObject2D).get_rid()
		if not ground.has(rid):
			out.append(rid)
	for child: Node in node.get_children():
		_collect_non_ground(child, ground, out)


## The y a downward ray lands on at `world_x`, or INF where there is no rock.
func _ground_y_at(world_x: float, exclude: Array[RID]) -> float:
	var space: PhysicsDirectSpaceState2D = root.world_2d.direct_space_state
	var q := PhysicsRayQueryParameters2D.create(
		Vector2(world_x, RAY_TOP), Vector2(world_x, RAY_BOTTOM))
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = exclude
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return float((hit["position"] as Vector2).y)


func the_flag_off_path_is_the_five_terrace_boxes() -> void:
	_expect(_off_terraces == 5,
		"flag off built %d bare terrace bodies, the authored table has 5" % _off_terraces)
	_expect(_off_stage_bodies == 0,
		"flag off built %d DestructibleStageBody — it must build none" % _off_stage_bodies)
	_done("the_flag_off_path_is_the_five_terrace_boxes")


func the_flag_on_path_is_one_body_and_no_loose_terraces() -> void:
	_expect(_on_stage_bodies == 1,
		"flag on built %d DestructibleStageBody, expected exactly 1" % _on_stage_bodies)
	_expect(_on_terraces == 0,
		"flag on ALSO built %d bare terrace bodies — the stage is doubled" % _on_terraces)
	# The whole reason for merging: a handful of shapes, not one per chunk.
	_expect(_on_shapes > 0 and _on_shapes < 64,
		"the one body carries %d shapes, expected a handful" % _on_shapes)
	print("  flag off: %d terrace bodies | flag on: 1 body, %d merged shape(s)"
		% [_off_terraces, _on_shapes])
	_done("the_flag_on_path_is_one_body_and_no_loose_terraces")


## THE ONE THAT MATTERS. Every fighter stands on these numbers.
func the_ground_a_ray_lands_on_is_identical_either_way() -> void:
	var mismatched: int = 0
	var first: String = ""
	var solid: int = 0
	for x: Variant in _off.keys():
		var a: float = float(_off[x])
		var b: float = float(_on.get(x, INF))
		if a < INF:
			solid += 1
		var same: bool = (a == INF and b == INF) or is_equal_approx(a, b)
		if not same:
			mismatched += 1
			if first == "":
				first = "x=%.0f lands at %.2f with the boxes and %.2f with the grid" \
					% [float(x), a, b]
	_expect(_off.size() > 0 and _on.size() > 0, "both boots produced a reading")
	_expect(solid > 0, "the flag-off sweep found ground at all (%d of %d x positions)"
		% [solid, _off.size()])
	_expect(mismatched == 0,
		"%d of %d x positions moved. First: %s" % [mismatched, _off.size(), first])
	print("  swept %d x positions (%d over rock): %d disagreement(s)"
		% [_off.size(), solid, mismatched])
	_done("the_ground_a_ray_lands_on_is_identical_either_way")


## The absolute reading, so the suite says where the floor IS and not only that it did
## not move. Both configurations are checked — a shared wrong answer is still wrong.
func the_flagged_stage_puts_the_five_surfaces_where_they_were_authored() -> void:
	for p: Array in PROBES:
		var x: float = float(p[0])
		var want: float = float(p[1])
		var got_off: float = float(_off.get(x, INF))
		var got_on: float = float(_on.get(x, INF))
		_expect(is_equal_approx(got_off, want),
			"boxes: surface at x=%.0f is %.2f, authored %.1f" % [x, got_off, want])
		_expect(is_equal_approx(got_on, want),
			"grid: surface at x=%.0f is %.2f, authored %.1f" % [x, got_on, want])
		print("  x=%-6.0f authored %-7.1f boxes %-9.2f grid %.2f"
			% [x, want, got_off, got_on])
	_done("the_flagged_stage_puts_the_five_surfaces_where_they_were_authored")


## THE THIRD RING-OUT VECTOR, AND THAT IT COSTS THE SHIPPED STAGE NOTHING.
##
## The class docs of `VersusArena` say out loud that everything is solid and *"the bots
## can't fall through and hand an early win"*. Slice 2 makes that false once the rock can
## be opened: 320 px of fight floor is a lot, but it is finite. `BotMatch.is_off_stage`
## already tests `p.y > RIM_BOTTOM`, so the mode the clips are shot in is covered — the
## duel, free-play and sandbox paths reach this arena WITHOUT `BotMatch` and had nothing
## below them at all, so a body through a fresh hole would fall forever.
##
## Both halves matter and both are asserted: the flag ADDS the floor pit, and the flag
## being OFF leaves exactly the two authored `BLAST_ZONES` and not one thing more.
func the_flag_adds_a_floor_ring_out_and_the_shipped_stage_keeps_two() -> void:
	_expect(_off_pits == 2,
		"flag off built %d PIT hazard(s); the authored BLAST_ZONES table has 2" % _off_pits)
	_expect(_on_pits == 3,
		"flag on built %d PIT hazard(s), expected the 2 authored plus the floor pit"
			% _on_pits)
	print("  ring-out pits: %d with the boxes, %d with the destructible grid"
		% [_off_pits, _on_pits])
	_done("the_flag_adds_a_floor_ring_out_and_the_shipped_stage_keeps_two")
