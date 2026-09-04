# Run: godot --headless --path godot-project --script tools/probe_destructible_carve_cost.gd
#
# WHAT A CARVE COSTS, IN MICROSECONDS, MEASURED RATHER THAN ASSERTED.
#
# The destructible stage's one real engineering risk is written into the design spec
# (`2026-08-19-destructible-map-design.md` §6.1): "Collision rebuild cost per frame."
# The grid is 482 x 143 = 68,926 cells and a hit changes a few dozen of them. Re-merging
# all 68,926 on every hit would be a stutter you can feel, and a Fault Line that damages
# thirty points along the ground would be a stall.
#
# So this measures four things, and prints all four whether they are good or bad:
#   1. the cost of ONE full merge of the intact stage
#   2. the cost of ONE full collision rebuild (merge + node churn)
#   3. the cost of one CARVE (grid writes only, no rebuild)
#   4. the cost of the incremental rebuild that actually runs per frame
#
# ⚠ THE CLOCK. `Time.get_ticks_usec()` is the wall clock. It is honest here because this
# runs OUTSIDE `--write-movie` (where [[feedback_measure_the_channel_the_viewer_gets]]
# records the wall clock reading 22x wrong) and outside hit-stop (which scales
# `Engine.time_scale`, not the wall clock). Each figure is a mean over N repeats, and
# the WORST single sample is printed beside it — a mean of 0.4 ms with a 40 ms worst
# case is a stutter, and a mean alone would hide it.
extends SceneTree

const TERRACE_DEPTH: float = 320.0
const TERRACES: Array[Dictionary] = [
	{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},
	{"surface_y": 700.0, "x0": 40.0,   "x1": 250.0},
	{"surface_y": 696.0, "x0": 1330.0, "x1": 1580.0},
	{"surface_y": 612.0, "x0": 1540.0, "x1": 1760.0},
	{"surface_y": 528.0, "x0": 1700.0, "x1": 1965.0},
]

const MERGE_REPEATS: int = 20
const CARVE_REPEATS: int = 60


func _initialize() -> void:
	call_deferred("_go")


func _rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t: Dictionary in TERRACES:
		out.append(Rect2(Vector2(float(t["x0"]), float(t["surface_y"])),
			Vector2(float(t["x1"]) - float(t["x0"]), TERRACE_DEPTH)))
	return out


func _stage() -> DestructibleStage:
	var s := DestructibleStage.new()
	s.build_from_rects(_rects())
	return s


func _go() -> void:
	await process_frame
	var s: DestructibleStage = _stage()
	print("[carve-cost] grid %d x %d = %d cell(s), %d solid"
		% [s.cols, s.rows, s.cols * s.rows, s.solid_count()])

	# 1 — a full merge of the INTACT stage (the best case: 8 big rectangles).
	var worst: int = 0
	var total: int = 0
	for _i: int in MERGE_REPEATS:
		var t0: int = Time.get_ticks_usec()
		var r: Array[Rect2] = s.merged_rects()
		var dt: int = Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
		if r.is_empty():
			printerr("[carve-cost] merge produced nothing — the measurement is void")
	print("[carve-cost] FULL merge, intact stage:   mean %7.1f us  worst %7.1f us"
		% [float(total) / float(MERGE_REPEATS), float(worst)])

	# 2 — a full collision rebuild (merge + free + N CollisionShape2D nodes).
	var holder := Node2D.new()
	root.add_child(holder)
	worst = 0
	total = 0
	for _i: int in MERGE_REPEATS:
		var t0: int = Time.get_ticks_usec()
		s.rebuild_collision(holder)
		var dt: int = Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
	print("[carve-cost] FULL rebuild_collision:     mean %7.1f us  worst %7.1f us  (%d shapes)"
		% [float(total) / float(MERGE_REPEATS), float(worst), s.shape_count()])

	# 3 — the same full merge AFTER the stage has been chewed up, because a hole-ridden
	# grid fragments every row and the merge gets strictly worse. Measuring only the
	# intact case would report the cheapest merge the stage will ever do.
	var chewed: DestructibleStage = _stage()
	var cx: int = 0
	for k: int in 40:
		var wx: float = 200.0 + float(k) * 28.0
		_punch(chewed, wx, 780.0, 22.0)
		cx += 1
	worst = 0
	total = 0
	for _i: int in MERGE_REPEATS:
		var t0: int = Time.get_ticks_usec()
		var r2: Array[Rect2] = chewed.merged_rects()
		var dt: int = Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
		if _i == 0:
			print("[carve-cost] after %d punches: %d solid, %d rect(s)"
				% [cx, chewed.solid_count(), r2.size()])
	print("[carve-cost] FULL merge, chewed stage:   mean %7.1f us  worst %7.1f us"
		% [float(total) / float(MERGE_REPEATS), float(worst)])

	# 4 — one carve's GRID WRITES alone, with no rebuild at all.
	var carver: DestructibleStage = _stage()
	worst = 0
	total = 0
	for i: int in CARVE_REPEATS:
		var wx: float = 300.0 + float(i) * 15.0
		var t0: int = Time.get_ticks_usec()
		_punch(carver, wx, 780.0, 22.0)
		var dt: int = Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
	print("[carve-cost] one carve, grid writes:     mean %7.1f us  worst %7.1f us"
		% [float(total) / float(CARVE_REPEATS), float(worst)])

	# 5 — THE PATH THAT ACTUALLY RUNS. A carve marks blocks dirty; `_process` re-merges
	# only those. This is the number the frame budget has to survive, and it is the one
	# the whole block partition exists to bring down.
	var live: DestructibleStage = _stage()
	root.add_child(live)
	live.rebuild_collision(live)
	await process_frame
	worst = 0
	total = 0
	var frames: int = 0
	for i: int in CARVE_REPEATS:
		var wx: float = 300.0 + float(i) * 15.0
		live.damage_at(120, Vector2(wx, live.surface_y_at(wx) + 6.0), Vector2.DOWN)
		var before_total: int = live.rebuild_usec_total
		await process_frame
		var dt: int = live.rebuild_usec_total - before_total
		if dt > 0:
			total += dt
			worst = maxi(worst, dt)
			frames += 1
	print("[carve-cost] DIRTY-BLOCK rebuild/frame:  mean %7.1f us  worst %7.1f us  (%d frames)"
		% [float(total) / maxf(float(frames), 1.0), float(worst), frames])
	print("[carve-cost] after %d carves: %d shape(s), %.2f%% of the rock gone, %d deferral(s)"
		% [live.carve_events, live.shape_count(), live.carved_fraction() * 100.0,
			live.deferred_rebuilds])

	# 6 — THE COALESCING CLAIM, checked rather than asserted: thirty carve points in ONE
	# frame must cost one rebuild of their union, not thirty full ones.
	var burst: DestructibleStage = _stage()
	root.add_child(burst)
	burst.rebuild_collision(burst)
	await process_frame
	for i: int in 30:
		var wx2: float = 300.0 + float(i) * 30.0
		burst.damage_at(120, Vector2(wx2, burst.surface_y_at(wx2) + 6.0), Vector2.DOWN)
	print("[carve-cost] 30 carves in one frame -> %d dirty block(s) of %d"
		% [burst.dirty_block_count(), burst.block_count()])
	var t1: int = Time.get_ticks_usec()
	await process_frame
	print("[carve-cost] ...one frame settles them in %.1f us (worst block pass %.1f us), %d deferred"
		% [float(Time.get_ticks_usec() - t1), float(burst.rebuild_usec_worst),
			burst.deferred_rebuilds])
	# Drain any deferrals so the deferral counter above is not read mid-flight.
	for _f: int in 8:
		await process_frame
	print("[carve-cost] after draining: %d dirty block(s) left" % burst.dirty_block_count())

	holder.queue_free()
	quit(0)


## A disc of cells cleared around a world point — the shape Slice 2's damage makes.
func _punch(s: DestructibleStage, wx: float, wy: float, r: float) -> void:
	var c: float = DestructibleStage.CHUNK
	var cx0: int = int(floorf((wx - r - s.origin.x) / c))
	var cx1: int = int(ceilf((wx + r - s.origin.x) / c))
	var cy0: int = int(floorf((wy - r - s.origin.y) / c))
	var cy1: int = int(ceilf((wy + r - s.origin.y) / c))
	for cy: int in range(cy0, cy1 + 1):
		for cx: int in range(cx0, cx1 + 1):
			var p: Vector2 = s.origin + Vector2((float(cx) + 0.5) * c, (float(cy) + 0.5) * c)
			if p.distance_to(Vector2(wx, wy)) <= r:
				s.clear_cell(cx, cy)
