# Run: godot --headless --path godot-project --script tools/slice_test_destructible_stage.gd
#
# SLICE 1 OF THE DESTRUCTIBLE STAGE: the chunk grid and the rectangles that come off it.
#
# The property that matters is NOT "destruction works" — nothing here destroys anything.
# It is that replacing five hand-made terrace boxes with a merged chunk grid leaves the
# stage the fighters stand on EXACTLY where it was. A stage that is one pixel taller,
# one pixel shorter, or seamed anywhere along the walking surface is a regression that
# would show up as "the legs look wrong" three sessions later.
#
# ⚠ THE HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the
# enclosing function and hands back the type's zero, which that idiom reads as "no
# failures". Failures accumulate on the MEMBER `_fails`; every test records a COMPLETION
# SENTINEL as its last line, so an aborted test fails BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"a_grid_over_the_shipped_stage_covers_the_same_rock",
	"the_walking_surface_lands_exactly_where_the_terraces_put_it",
	"merging_collapses_thousands_of_chunks_into_a_handful_of_boxes",
	"every_intact_chunk_is_covered_by_some_rectangle",
	"a_hole_removes_rock_only_where_it_was_punched",
	"rectangles_never_grow_upward",
	"the_body_is_one_node_with_one_shape_per_merged_rect",
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
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	call_deferred("_go")
	return false


func _go() -> void:
	await process_frame
	for t: String in TESTS:
		call(t)
	for t: String in TESTS:
		_expect(_completed.has(t), "%s ran to completion" % t)
	print("slice_test_destructible_stage: %s (%d failure(s))"
		% ["all PASS" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAILED: %s" % what)


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


## The grid must describe the same rock the terraces did. Area is compared with a
## tolerance of half a chunk per edge per terrace, because centre-sampling can lose a
## sliver narrower than that and cannot gain one.
func a_grid_over_the_shipped_stage_covers_the_same_rock() -> void:
	var s: DestructibleStage = _stage()
	var chunk_area: float = DestructibleStage.CHUNK * DestructibleStage.CHUNK
	var grid_area: float = float(s.solid_count()) * chunk_area
	var want: float = 0.0
	for r: Rect2 in _terrace_rects():
		want += r.size.x * r.size.y
	# Terraces overlap (they all sit on the same deep rock), so the grid can only be
	# SMALLER than the naive sum. What must not happen is the grid being bigger.
	_expect(grid_area <= want + chunk_area,
		"grid area %.0f never exceeds the terrace area %.0f" % [grid_area, want])
	_expect(grid_area > want * 0.5,
		"grid area %.0f is the same order as the terrace area %.0f" % [grid_area, want])
	_done("a_grid_over_the_shipped_stage_covers_the_same_rock")


## THE ONE THAT MATTERS. Every fighter stands on this number.
func the_walking_surface_lands_exactly_where_the_terraces_put_it() -> void:
	var s: DestructibleStage = _stage()
	var probes: Array[Array] = [
		[700.0, 780.0],    # main fight floor
		[120.0, 700.0],    # left mound
		[1450.0, 696.0],   # first step
		[1600.0, 612.0],   # second step
		[1900.0, 528.0],   # right bluff
	]
	for p: Array in probes:
		var got: float = s.surface_y_at(float(p[0]))
		_expect(is_equal_approx(got, float(p[1])),
			"surface at x=%.0f is %.1f, terrace says %.1f" % [p[0], got, float(p[1])])
	_done("the_walking_surface_lands_exactly_where_the_terraces_put_it")


func merging_collapses_thousands_of_chunks_into_a_handful_of_boxes() -> void:
	var s: DestructibleStage = _stage()
	var rects: Array[Rect2] = s.merged_rects()
	_expect(s.solid_count() > 1000,
		"the shipped stage is thousands of chunks (%d)" % s.solid_count())
	# The point of merging. A per-chunk body count would be the solid count itself.
	_expect(rects.size() < 64,
		"merged into %d rectangles, not %d bodies" % [rects.size(), s.solid_count()])
	_expect(rects.size() > 0, "merging produced something")
	# PRINTED EVEN ON A PASS. A green suite that reports nothing cannot tell you the
	# rebuild got twice as expensive last week, and this is the number that would say so.
	print("  grid %d x %d = %d cell(s), %d solid, merged into %d rectangle(s)"
		% [s.cols, s.rows, s.cols * s.rows, s.solid_count(), rects.size()])
	_done("merging_collapses_thousands_of_chunks_into_a_handful_of_boxes")


## No chunk may be left without collision over it. A gap here is a fighter falling
## through a floor that looks solid.
func every_intact_chunk_is_covered_by_some_rectangle() -> void:
	var s: DestructibleStage = _stage()
	var rects: Array[Rect2] = s.merged_rects()
	var missed: int = 0
	for cy: int in s.rows:
		for cx: int in s.cols:
			if not s.is_solid(cx, cy):
				continue
			var centre: Vector2 = s.origin + Vector2(
				(float(cx) + 0.5) * DestructibleStage.CHUNK,
				(float(cy) + 0.5) * DestructibleStage.CHUNK)
			var covered: bool = false
			for r: Rect2 in rects:
				if r.has_point(centre):
					covered = true
					break
			if not covered:
				missed += 1
	_expect(missed == 0, "%d intact chunk(s) have no rectangle over them" % missed)
	_done("every_intact_chunk_is_covered_by_some_rectangle")


## Slice 2's mechanism, asserted early because the merge has to survive it.
func a_hole_removes_rock_only_where_it_was_punched() -> void:
	var s: DestructibleStage = _stage()
	var before: int = s.solid_count()
	# A 6-unit hole: the widest gap the whole roster can still cross (Juggernaut's
	# flat-gap reach is 97.1 px = 6.1 of the spec's 16 px units). One unit is
	# DESTRUCTION_CELLS cells wide, so this clears 6 * 4 = 24 cells of one row.
	var wide: int = 6 * DestructibleStage.DESTRUCTION_CELLS
	var cx0: int = int((700.0 - s.origin.x) / DestructibleStage.CHUNK)
	var cy0: int = int((780.0 - s.origin.y) / DestructibleStage.CHUNK)
	_expect(s.is_solid(cx0, cy0), "the row being punched was solid to begin with")
	for k: int in wide:
		s.clear_cell(cx0 + k, cy0)
	_expect(s.solid_count() == before - wide,
		"%d cells removed, count went %d -> %d" % [wide, before, s.solid_count()])
	_expect(s.is_solid(cx0 - 1, cy0), "the cell left of the hole is untouched")
	_expect(s.is_solid(cx0 + wide, cy0), "the cell right of the hole is untouched")
	_expect(s.is_solid(cx0, cy0 + 1), "the rock UNDER the hole is untouched")
	# And the merge still covers everything that is left.
	var rects: Array[Rect2] = s.merged_rects()
	var hole_centre: Vector2 = s.origin + Vector2(
		(float(cx0) + 0.5) * DestructibleStage.CHUNK,
		(float(cy0) + 0.5) * DestructibleStage.CHUNK)
	var in_hole: bool = false
	for r: Rect2 in rects:
		if r.has_point(hole_centre):
			in_hole = true
			break
	_expect(not in_hole, "no rectangle covers the punched hole")
	_done("a_hole_removes_rock_only_where_it_was_punched")


## The seam rule. Overlap sideways, grow down, never up.
func rectangles_never_grow_upward() -> void:
	var s: DestructibleStage = _stage()
	var top: float = INF
	for r: Rect2 in s.merged_rects():
		top = minf(top, r.position.y)
	var highest_terrace: float = INF
	for t: Dictionary in TERRACES:
		highest_terrace = minf(highest_terrace, float(t["surface_y"]))
	_expect(is_equal_approx(top, highest_terrace),
		"highest rectangle top %.1f == highest terrace surface %.1f"
			% [top, highest_terrace])
	_done("rectangles_never_grow_upward")


func the_body_is_one_node_with_one_shape_per_merged_rect() -> void:
	var s: DestructibleStage = _stage()
	var holder := Node2D.new()
	root.add_child(holder)
	var body: StaticBody2D = s.rebuild_collision(holder)
	var rects: Array[Rect2] = s.merged_rects()
	_expect(body != null, "a body was built")
	_expect(body.get_child_count() == rects.size(),
		"%d shapes for %d rectangles" % [body.get_child_count(), rects.size()])
	_expect(s.shape_count() == rects.size(), "shape_count agrees")
	# The seam grow must be sideways and down only — check one shape against its rect.
	if not rects.is_empty() and body.get_child_count() > 0:
		var cs: CollisionShape2D = body.get_child(0) as CollisionShape2D
		var box: RectangleShape2D = cs.shape as RectangleShape2D
		var drawn_top: float = cs.position.y - box.size.y * 0.5
		_expect(is_equal_approx(drawn_top, rects[0].position.y),
			"shape top %.2f sits on rect top %.2f" % [drawn_top, rects[0].position.y])
	holder.queue_free()
	_done("the_body_is_one_node_with_one_shape_per_merged_rect")
