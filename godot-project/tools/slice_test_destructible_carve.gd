# Run: godot --headless --path godot-project --script tools/slice_test_destructible_carve.gd
#
# SLICE 2 OF THE DESTRUCTIBLE STAGE: DAMAGE OPENS HOLES.
#
# Slice 1 proved the merged grid describes the same rock the terrace boxes did. This
# suite proves the four things Slice 2 adds, and each one is a property that would fail
# SILENTLY in play if it broke:
#
#   1. the THRESHOLD holds — a jab leaves the ground alone, a committed hit does not
#   2. a carve removes rock WHERE IT LANDED and nowhere else, and the merge survives it
#   3. the rebuild is INCREMENTAL — a hit dirties the blocks it touched, not the stage
#   4. the routing refuses everything that is not the stage's own body, so a bolt
#      stopping on a ruin platform cannot punch the rock underneath it
#
# ⚠ THE HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the
# enclosing function and hands back the type's zero, which that idiom reads as "no
# failures". Failures accumulate on the MEMBER `_fails`; every test records a COMPLETION
# SENTINEL as its last line, so an aborted test fails BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"a_jab_leaves_the_ground_alone_and_a_committed_hit_does_not",
	"the_crater_curve_is_monotonic_and_bounded",
	"a_carve_removes_rock_only_where_it_landed",
	"a_carve_dirties_only_the_blocks_it_touched",
	"the_rebuild_is_incremental_and_reports_what_it_deferred",
	"routing_refuses_every_body_that_is_not_the_stage",
	"a_carved_hole_is_really_gone_from_the_collision",
	"the_cavity_is_drawn_where_the_rock_was_removed",
]

## The shipped stage, variant 0, from `VersusArena.STAGE_TERRACES[0]` + TERRACE_DEPTH.
const TERRACE_DEPTH: float = 320.0
const TERRACES: Array[Dictionary] = [
	{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},
	{"surface_y": 700.0, "x0": 40.0,   "x1": 250.0},
	{"surface_y": 696.0, "x0": 1330.0, "x1": 1580.0},
	{"surface_y": 612.0, "x0": 1540.0, "x1": 1760.0},
	{"surface_y": 528.0, "x0": 1700.0, "x1": 1965.0},
]

var _fails: int = 0
var _completed: Dictionary = {}


## ⚠ `_initialize`, NOT `_process`. A `SceneTree` script's `_process` QUITS THE TREE the
## moment it returns true, and the guard idiom the Slice 1 suite uses (`if _ran: return
## true`) therefore kills the loop on frame two. That is fine for a suite whose tests are
## synchronous; every test here needs frames to elapse so the deferred rebuild can run,
## and the first version of this file died silently after test four — no verdict line, no
## `quit`, exit code 0. A suite that can end without printing either sentinel is worse
## than no suite. `slice_test_destructible_stage_wired` drives from `_initialize` for the
## same reason.
func _initialize() -> void:
	_go()


## Every test is a coroutine (each opens with `await process_frame`) so the dispatch loop
## can await them uniformly. Awaiting a call that is NOT a coroutine is a runtime error
## in Godot 4, and a mixed list would fail on whichever entry someone edited last.
func _go() -> void:
	await process_frame
	for t: String in TESTS:
		await call(t)
	for t: String in TESTS:
		_expect(_completed.has(t), "%s ran to completion" % t)
	print("slice_test_destructible_carve: %s (%d failure(s))"
		% ["all PASS" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: %s" % what)


func _done(t: String) -> void:
	_completed[t] = true


func _terrace_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t: Dictionary in TERRACES:
		out.append(Rect2(Vector2(float(t["x0"]), float(t["surface_y"])),
			Vector2(float(t["x1"]) - float(t["x0"]), TERRACE_DEPTH)))
	return out


func _stage() -> DestructibleStage:
	var s := DestructibleStage.new()
	s.build_from_rects(_terrace_rects())
	return s


## A stage that is IN THE TREE with a live body — needed by anything that exercises the
## deferred rebuild, because that runs in `_process`.
func _live_stage() -> DestructibleStage:
	var s: DestructibleStage = _stage()
	root.add_child(s)
	s.rebuild_collision(s)
	return s


# ── 1. the threshold ───────────────────────────────────────────────────────

## The whole design decision, asserted at both ends. A `ZoneSpell` tick (8) and a Blade
## Flurry cut (24) must leave the floor exactly as they found it; a heavy (62) must not.
func a_jab_leaves_the_ground_alone_and_a_committed_hit_does_not() -> void:
	await process_frame
	var s: DestructibleStage = _stage()
	var before: int = s.solid_count()
	var at := Vector2(700.0, 782.0)
	_expect(s.is_solid(int((at.x - s.origin.x) / DestructibleStage.CHUNK),
		int((at.y - s.origin.y) / DestructibleStage.CHUNK)),
		"the cell under the test point is rock to begin with")
	for jab: int in [1, 8, 24, DestructibleStage.CARVE_MIN_DAMAGE - 1]:
		_expect(s.damage_at(jab, at, Vector2.DOWN) == 0,
			"a %d-damage hit removed rock — the threshold is not holding" % jab)
	_expect(s.solid_count() == before,
		"%d cell(s) went missing to hits that should all have been refused"
			% (before - s.solid_count()))
	_expect(s.refused_hits == 4, "4 refusals were counted, got %d" % s.refused_hits)
	# ...and the committed hit does bite.
	var removed: int = s.damage_at(62, at, Vector2.DOWN)
	_expect(removed > 0, "a 62-damage hit removed nothing")
	_expect(s.carve_events == 1, "one carve event was recorded, got %d" % s.carve_events)
	_expect(s.solid_count() == before - removed,
		"solid count fell by exactly the cells the carve reported")
	_done("a_jab_leaves_the_ground_alone_and_a_committed_hit_does_not")


func the_crater_curve_is_monotonic_and_bounded() -> void:
	await process_frame
	var lo: float = DestructibleStage.carve_radius_for(DestructibleStage.CARVE_MIN_DAMAGE)
	var mid: float = DestructibleStage.carve_radius_for(120)
	var hi: float = DestructibleStage.carve_radius_for(9999)
	_expect(is_equal_approx(lo, DestructibleStage.CARVE_RADIUS_MIN),
		"the lightest carving hit opens CARVE_RADIUS_MIN (%.2f vs %.2f)"
			% [lo, DestructibleStage.CARVE_RADIUS_MIN])
	_expect(lo < mid and mid < hi, "the curve rises: %.2f < %.2f < %.2f" % [lo, mid, hi])
	_expect(is_equal_approx(hi, DestructibleStage.CARVE_RADIUS_MAX),
		"an absurd damage number still clamps at CARVE_RADIUS_MAX (%.2f)" % hi)
	# SUB-LINEAR: five times the damage must not be five times the radius, or an ult
	# takes a bite the size of the fight floor. The same reasoning `SpellTier` records.
	var five_x: float = DestructibleStage.carve_radius_for(200)
	_expect(five_x < lo * 5.0,
		"5x the damage opened %.2f px against a linear %.2f px" % [five_x, lo * 5.0])
	# The hint may only ever widen. A call site cannot switch destruction off by
	# passing a small footprint.
	var s: DestructibleStage = _stage()
	var narrow: int = s.damage_at(200, Vector2(700.0, 782.0), Vector2.DOWN, 1.0)
	var s2: DestructibleStage = _stage()
	var plain: int = s2.damage_at(200, Vector2(700.0, 782.0), Vector2.DOWN)
	_expect(narrow == plain,
		"a tiny radius hint narrowed the crater (%d cells vs %d)" % [narrow, plain])
	_done("the_crater_curve_is_monotonic_and_bounded")


# ── 2. the carve ───────────────────────────────────────────────────────────

func a_carve_removes_rock_only_where_it_landed() -> void:
	await process_frame
	var s: DestructibleStage = _stage()
	var at := Vector2(700.0, 782.0)
	var r: float = 20.0
	var removed: int = s.carve_disc(at, r)
	_expect(removed > 0, "the carve removed nothing")
	var strays: int = 0
	var missed: int = 0
	for cy: int in s.rows:
		for cx: int in s.cols:
			if not s.was_rock(cx, cy):
				continue
			var c: Vector2 = s.origin + Vector2(
				(float(cx) + 0.5) * DestructibleStage.CHUNK,
				(float(cy) + 0.5) * DestructibleStage.CHUNK)
			var inside: bool = c.distance_to(at) <= r
			if inside and s.is_solid(cx, cy):
				missed += 1
			elif not inside and not s.is_solid(cx, cy):
				strays += 1
	_expect(strays == 0, "%d cell(s) OUTSIDE the disc were removed" % strays)
	_expect(missed == 0, "%d cell(s) INSIDE the disc survived" % missed)
	# The merge still covers every cell that is left, and nothing covers the hole.
	var rects: Array[Rect2] = s.merged_rects()
	var uncovered: int = 0
	for cy2: int in s.rows:
		for cx2: int in s.cols:
			if not s.is_solid(cx2, cy2):
				continue
			var c2: Vector2 = s.origin + Vector2(
				(float(cx2) + 0.5) * DestructibleStage.CHUNK,
				(float(cy2) + 0.5) * DestructibleStage.CHUNK)
			var covered: bool = false
			for rr: Rect2 in rects:
				if rr.has_point(c2):
					covered = true
					break
			if not covered:
				uncovered += 1
	_expect(uncovered == 0, "%d surviving cell(s) lost their collision" % uncovered)
	var hole_covered: bool = false
	for rr2: Rect2 in rects:
		if rr2.has_point(at):
			hole_covered = true
			break
	_expect(not hole_covered, "a rectangle still covers the middle of the crater")
	_done("a_carve_removes_rock_only_where_it_landed")


# ── 3. the rebuild ─────────────────────────────────────────────────────────

func a_carve_dirties_only_the_blocks_it_touched() -> void:
	await process_frame
	var s: DestructibleStage = _stage()
	_expect(s.block_count() > 4, "the grid is partitioned at all (%d block(s))"
		% s.block_count())
	_expect(s.dirty_block_count() == 0, "a fresh stage has no dirty blocks")
	s.carve_disc(Vector2(700.0, 782.0), 20.0)
	var dirty: int = s.dirty_block_count()
	_expect(dirty >= 1, "the carve dirtied nothing")
	# THE POINT OF THE WHOLE PARTITION. A 20 px crater is 10 cells across against a
	# 48-cell block, so it can straddle at most two blocks in each axis.
	_expect(dirty <= 4, "one crater dirtied %d of %d block(s) — the partition is not "
		% [dirty, s.block_count()] + "localising the damage and every hit will pay for "
		+ "the whole stage")
	print("  one 20 px crater dirtied %d of %d block(s)" % [dirty, s.block_count()])
	_done("a_carve_dirties_only_the_blocks_it_touched")


func the_rebuild_is_incremental_and_reports_what_it_deferred() -> void:
	await process_frame
	var s: DestructibleStage = _live_stage()
	await process_frame
	_expect(s.dirty_block_count() == 0, "the initial build left no dirty blocks")
	var shapes_before: int = s.shape_count()
	# A wide sweep of carve points in ONE frame — the `FaultLine` case §6.1 warns about.
	for i: int in 30:
		var wx: float = 200.0 + float(i) * 34.0
		s.damage_at(120, Vector2(wx, s.surface_y_at(wx) + 6.0), Vector2.DOWN)
	var dirty: int = s.dirty_block_count()
	_expect(dirty > 1, "30 carve points across the stage dirtied %d block(s)" % dirty)
	# ⚠ THE COALESCING CLAIM. 30 carves must cost ONE rebuild pass of their union, not
	# 30 passes. Nothing has rebuilt yet — that is the claim.
	_expect(s.shape_count() == shapes_before,
		"the shape count moved before a frame elapsed — a carve rebuilt inline")
	var passes: int = 0
	for _f: int in 12:
		await process_frame
		if s.dirty_block_count() == 0:
			break
		passes += 1
	_expect(s.dirty_block_count() == 0,
		"%d block(s) were still dirty after 12 frames" % s.dirty_block_count())
	_expect(s.shape_count() != shapes_before, "the rebuild produced no new shapes")
	_expect(s.rebuild_usec_worst > 0, "no rebuild time was recorded at all")
	print("  30 carves in one frame: %d dirty block(s), settled over %d extra frame(s),"
		% [dirty, passes]
		+ " %d deferral(s), worst pass %.0f us"
			% [s.deferred_rebuilds, float(s.rebuild_usec_worst)])
	s.queue_free()
	_done("the_rebuild_is_incremental_and_reports_what_it_deferred")


# ── 4. the routing ─────────────────────────────────────────────────────────

## `carve_from_body` is how a bolt reaches the ground. It must answer 0 for every body
## that is not the stage's own collider, or a bolt that stopped on a ruin platform would
## punch a hole in the rock underneath it.
func routing_refuses_every_body_that_is_not_the_stage() -> void:
	await process_frame
	var s: DestructibleStage = _live_stage()
	await process_frame
	var body: StaticBody2D = s.get_node_or_null(^"DestructibleStageBody") as StaticBody2D
	_expect(body != null, "the stage built a body named DestructibleStageBody")
	var imposter := StaticBody2D.new()
	root.add_child(imposter)
	var at := Vector2(700.0, 782.0)
	_expect(DestructibleStage.carve_from_body(imposter, 200, at, Vector2.DOWN) == 0,
		"a plain StaticBody2D routed damage into the stage")
	_expect(DestructibleStage.carve_from_body(null, 200, at, Vector2.DOWN) == 0,
		"a null collider routed damage into the stage")
	if body != null:
		_expect(DestructibleStage.carve_from_body(body, 200, at, Vector2.DOWN) > 0,
			"the stage's OWN body did not route damage — the wiring is dead")
	# ...and the area route finds the stage by group.
	_expect(DestructibleStage.carve_area(s, 200, Vector2(760.0, 782.0), Vector2.UP) > 0,
		"carve_area could not find the stage through its group")
	imposter.queue_free()
	s.queue_free()
	_done("routing_refuses_every_body_that_is_not_the_stage")


## THE ONE THAT MATTERS FOR PLAY. The grid saying "no rock" is the model's own opinion;
## this asks the physics server whether a body would fall through.
## [[feedback_verify_the_drawn_channel]] — read the channel the CharacterBody gets.
func a_carved_hole_is_really_gone_from_the_collision() -> void:
	await process_frame
	var s: DestructibleStage = _live_stage()
	await process_frame
	var centre_x: float = 700.0
	var before: float = _ground_y_at(centre_x, s)
	_expect(is_equal_approx(before, 780.0),
		"the ray found the fight floor at %.2f before any damage" % before)
	# A hole the whole roster can cross: 6 of the spec's 16 px units = 96 px. Carved as
	# overlapping discs, which is how a real bombardment would do it.
	var x: float = centre_x - 48.0
	while x <= centre_x + 48.0:
		s.carve_disc(Vector2(x, 790.0), 26.0)
		x += 12.0
	for _f: int in 6:
		await process_frame
	# Sweep the hole and count how much of it the physics server agrees is gone. The
	# GRID width and the COLLISION width are not the same number: `SEAM_OVERLAP_X` grows
	# every rectangle 2 px sideways, so a hole is 4 px narrower in collision than in the
	# grid. That is the seam trick working as designed and erring toward solid, but it
	# is a real 4 px against the Juggernaut's 97.1 px reach and it gets printed.
	var grid_open: int = 0
	var phys_open: int = 0
	var px: float = centre_x - 90.0
	while px <= centre_x + 90.0:
		if s.surface_y_at(px) > 800.0:
			grid_open += 1
		if _ground_y_at(px, s) > 800.0:
			phys_open += 1
		px += 2.0
	_expect(grid_open > 0, "the grid says nothing was removed")
	_expect(phys_open > 0,
		"the GRID has a hole but the physics server still finds floor across all of it")
	_expect(grid_open - phys_open <= 3,
		"the collision hole is %d sample(s) narrower than the grid hole — more than the "
			% (grid_open - phys_open)
		+ "seam overlap explains")
	print("  a %.0f px carved gap reads as %.0f px of grid and %.0f px of collision"
		% [96.0, float(grid_open) * 2.0, float(phys_open) * 2.0])
	s.queue_free()
	_done("a_carved_hole_is_really_gone_from_the_collision")


## A hole in the collision that is not a hole in the PICTURE is the worst possible
## outcome: solid-looking ground you fall through. The stage draws its own cavity.
func the_cavity_is_drawn_where_the_rock_was_removed() -> void:
	await process_frame
	var s: DestructibleStage = _live_stage()
	await process_frame
	s.damage_at(200, Vector2(700.0, 790.0), Vector2.DOWN)
	for _f: int in 4:
		await process_frame
	var cavity: Array[Rect2] = s.debug_cavity_rects()
	_expect(not cavity.is_empty(), "nothing was drawn over a crater that exists")
	var area: float = 0.0
	var covers_centre: bool = false
	for r: Rect2 in cavity:
		area += r.size.x * r.size.y
		if r.has_point(Vector2(700.0, 790.0)):
			covers_centre = true
	_expect(covers_centre, "the cavity drawing misses the middle of its own crater")
	# The drawn area must match the removed area, or the picture and the collision
	# disagree about where the ground is.
	var cell_area: float = DestructibleStage.CHUNK * DestructibleStage.CHUNK
	var removed_area: float = float(s.carved_cells) * cell_area
	_expect(is_equal_approx(area, removed_area),
		"drew %.0f px2 of cavity for %.0f px2 of removed rock" % [area, removed_area])
	s.queue_free()
	_done("the_cavity_is_drawn_where_the_rock_was_removed")


## The y a downward ray lands on at `world_x`, or INF where there is no rock.
##
## ⚠ EVERY OTHER COLLIDER IS EXCLUDED BY RID, and the first version of this that did not
## do that reported a 96 px grid hole as 48 px of collision — a "finding" that was
## entirely the harness. Earlier tests build their own live stage and `queue_free` it,
## and a queued node still answers rays until the frame it is actually deleted, so the
## ray was landing on a DIFFERENT stage's intact floor. Two stages, one ray.
## [[feedback_harnesses_lie_verify_them]] — the instrument was the thing that was wrong.
func _ground_y_at(world_x: float, stage: DestructibleStage) -> float:
	var space: PhysicsDirectSpaceState2D = \
		stage.get_viewport().world_2d.direct_space_state
	var q := PhysicsRayQueryParameters2D.create(
		Vector2(world_x, 300.0), Vector2(world_x, 1300.0))
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var mine: StaticBody2D = \
		stage.get_node_or_null(^"DestructibleStageBody") as StaticBody2D
	var exclude: Array[RID] = []
	_collect_other_rids(root, mine, exclude)
	q.exclude = exclude
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return float((hit["position"] as Vector2).y)


func _collect_other_rids(node: Node, keep: CollisionObject2D, out: Array[RID]) -> void:
	if node is CollisionObject2D and node != keep:
		out.append((node as CollisionObject2D).get_rid())
	for child: Node in node.get_children():
		_collect_other_rids(child, keep, out)
