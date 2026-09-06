# Run: godot --headless --path godot-project --script tools/slice_test_carve_capsule.gd
#
# THE CAPSULE: A WALL TAKES THE MATERIAL IT IS MADE OF.
#
# `DestructibleStage` could only ever remove a DISC, and its own header said what that
# cost: *"a rock wall that leaves a trench where it tore itself free would make cover and
# hazard the same act... a wall's footprint is a long thin SPAN, not a disc — `carve_disc`
# would need a capsule sibling... and a row of bites is exactly the shape most likely to
# move the severed-run number off 0."* `HorizonArc` was left unwired for the same reason.
#
# This suite is that measurement. It proves five things, and the FOURTH is the one the
# whole slice exists for:
#
#   1. the capsule is a STADIUM — round caps, flat sides, and nothing outside it goes
#   2. a zero-length span is EXACTLY a disc, so the primitive is a superset and not a
#      second, drifting description of the same shape
#   3. the scan is bounded to the SPAN and beats a naive row of `carve_disc` calls,
#      which is the implementation it must be cheaper than to be worth existing
#   4. ⚠ THE SEVERED RUN MOVES. A wall's trench cuts a six-cell ledge clean in two;
#      a single disc of the same radius in the same place does not. That number has
#      been 0 for the whole of the destruction work.
#   5. ...and the world's FLOOR is still a floor. A 320 px terrace takes a pockmark,
#      not a hole through it. The trench is a hazard on a plank and a scar on the ground,
#      which is the difference the maker's "do not make the ground destroyable" ruling
#      is actually about.
#
# Plus the wiring, because a comment is not an implementation
# ([[feedback_a_comment_is_not_an_implementation]]): `RockWall.raise_wall` and
# `IceWall.raise_wall` are driven FOR REAL against a real ledge through real physics, and
# `HorizonArc` is flown into one, so "the walls are wired" is a measurement rather than a
# claim about a call site somebody read.
#
# ⚠ THE HOUSE RULE, inherited from `slice_test_destructible_carve`. Never
# `failed += _test_x()` — a dead property read aborts the enclosing function and hands
# back the type's zero, which that idiom reads as "no failures". Failures accumulate on
# the MEMBER `_fails`; every test records a COMPLETION SENTINEL as its last line, so an
# aborted test fails BY ABSENCE.
#
# ⚠ AND NO PRECONDITION IS EVER `OR`ed AGAINST THE THING IT PRECEDES. `flag or removed >
# 0` is true on a green tree however dead `flag` reads, which is a test of the fixture
# and not of the code. Preconditions here are separate `_expect`s with their own message.
extends SceneTree

const TESTS: Array[String] = [
	"the_capsule_is_a_stadium_with_round_caps_and_nothing_outside_it",
	"a_zero_length_span_is_exactly_a_disc",
	"the_scan_is_bounded_to_the_span_and_beats_a_row_of_discs",
	"a_rock_wall_trenches_the_ledge_it_tore_itself_out_of",
	"the_trench_severs_the_ledge_and_a_disc_of_the_same_radius_does_not",
	"an_ice_wall_leaves_a_narrower_trench_than_a_rock_wall",
	"a_wall_scars_the_worlds_floor_and_never_cuts_through_it",
	"the_ledger_refuses_a_source_re_digging_its_own_trench",
	"the_span_spends_the_discs_debris_budget_and_never_a_multiple_of_it",
	"a_horizon_cut_slots_the_plank_it_stopped_against",
]

## The shipped ground stage, variant 0, from `VersusArena.STAGE_TERRACES[0]` +
## TERRACE_DEPTH — the same table `slice_test_destructible_carve` builds from, so the
## "the floor is still a floor" test is measured against the real thing.
const TERRACE_DEPTH: float = 320.0
const TERRACES: Array[Dictionary] = [
	{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},
	{"surface_y": 700.0, "x0": 40.0,   "x1": 250.0},
	{"surface_y": 696.0, "x0": 1330.0, "x1": 1580.0},
	{"surface_y": 612.0, "x0": 1540.0, "x1": 1760.0},
	{"surface_y": 528.0, "x0": 1700.0, "x1": 1965.0},
]

const ROCK_WALL: String = "res://scripts/combat/RockWall.gd"
const ICE_WALL: String = "res://scripts/combat/IceWall.gd"
const HORIZON_ARC: String = "res://scripts/combat/HorizonArc.gd"
const RUIN_PLATFORM: String = "res://scripts/combat/RuinPlatform.gd"

## A ledge wide enough that a 44 px trench is a real cut through it and not simply the
## whole plank, which would prove nothing about the SHAPE.
const LEDGE_SIZE: Vector2 = Vector2(190.0, 24.0)

var _fails: int = 0
var _completed: Dictionary = {}
var _room: Node2D = null


## ⚠ `_initialize`, NOT `_process`. A `SceneTree` script's `_process` QUITS THE TREE the
## moment it returns true. Every test here needs frames to elapse — the physics server
## must see a freshly added ledge before a wall's floor probe can find it, and the grid's
## re-merge runs in `_process` — so the dispatch loop awaits.
func _initialize() -> void:
	_go()


func _go() -> void:
	await process_frame
	_room = Node2D.new()
	root.add_child(_room)
	for t: String in TESTS:
		await call(t)
	for t: String in TESTS:
		_expect(_completed.has(t), "%s ran to completion" % t)
	print("slice_test_carve_capsule: %s (%d failure(s))"
		% ["all PASS" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: %s" % what)


func _done(t: String) -> void:
	_completed[t] = true


## ⚠ `physics_frame` AND `process_frame`, NEVER ONLY THE SECOND. Every wall in here finds
## its floor with a raycast, and a body added this frame is not in the physics space
## until the space has actually stepped — so a suite that only awaits idle frames gets a
## clear ray through a ledge that is visibly right there, and the wall seats in mid-air.
## `slice_test_destructible_sources._pump` is the same helper for the same reason.
func _pump(n: int = 2) -> void:
	for _i: int in n:
		await process_frame
		await physics_frame


# ── fixtures ───────────────────────────────────────────────────────────────

## ══ READ A WALL'S CONSTANT WITHOUT NAMING ITS CLASS ════════════════════════
## ⚠ WRITING `RockWall.WALL_SIZE` HERE BREAKS THIS ENTIRE SUITE, AND IT DID. A
## `class_name` mentioned in a script body is a COMPILE-TIME dependency
## ([[feedback_gdscript_resolution_traps]]), so naming `RockWall` forces RockWall.gd to
## compile as THIS file loads — which in a `--script` run happens BEFORE the project's
## autoloads are registered. RockWall.gd calls `Sfx.play` and `Juice.shake_camera` by
## name, so it fails with "Identifier not found: Sfx", and every later
## `load(ROCK_WALL).new()` then hands back an uncompiled script whose `new` does not
## exist. Three tests aborted exactly that way, and the console blamed an unrelated file
## a different agent happened to be mid-edit on — which is how a whole afternoon goes.
##
## `load()` inside a function runs after the autoloads are up, so the same script
## compiles cleanly. The numbers still come from the wall's own file rather than being
## copied here, which is the property that mattered about naming the class in the first
## place.
func _konst(path: String, key: String) -> Variant:
	var gd: GDScript = load(path) as GDScript
	if gd == null:
		return null
	return gd.get_script_constant_map().get(key)


func _konst_f(path: String, key: String) -> float:
	return float(_konst(path, key))


func _konst_i(path: String, key: String) -> int:
	return int(_konst(path, key))


## A bare grid over one rectangle, out of the tree. For the pure-geometry tests, which
## want a known cell layout and no spectacle, no body and no group membership.
func _slab(rect: Rect2) -> DestructibleStage:
	var s := DestructibleStage.new()
	s.spectacle = false
	s.build_from_rects([rect] as Array[Rect2])
	return s


func _terrace_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t: Dictionary in TERRACES:
		out.append(Rect2(Vector2(float(t["x0"]), float(t["surface_y"])),
			Vector2(float(t["x1"]) - float(t["x0"]), TERRACE_DEPTH)))
	return out


## The world's floor, IN THE TREE with a live body — so a wall's floor probe finds it and
## `carve_span_from_body` can route to it by `BODY_META`, exactly as in play.
##
## ⚠ THE CALLER MUST HAND IT BACK TO `_drop_stage`. The ground stage joins `GROUP_NAME`
## in `_ready`, and `stage_in` returns THE FIRST MEMBER of that group — a stale one left
## behind catches every carve for the rest of the run. That is the fault
## `slice_test_destructible_sources` records costing it five false failures.
func _ground_stage() -> DestructibleStage:
	var s := DestructibleStage.new()
	s.build_from_rects(_terrace_rects())
	_room.add_child(s)
	s.rebuild_collision(s)
	return s


func _drop_stage(s: DestructibleStage) -> void:
	if s == null or not is_instance_valid(s):
		return
	# ⚠ OUT OF THE GROUP BEFORE THE FREE, not after and not instead. `queue_free` lands at
	# the end of the frame, so a stage merely queued is still the first member of the
	# group for the rest of this one.
	s.remove_from_group(DestructibleStage.GROUP_NAME)
	s.queue_free()


## A real `RuinPlatform` ledge, in the tree, one frame old so `_ready` has built its grid
## and the physics server has seen its shapes.
func _ledge(at: Vector2, size: Vector2 = LEDGE_SIZE) -> StaticBody2D:
	var n: StaticBody2D = (load(RUIN_PLATFORM) as GDScript).new() as StaticBody2D
	n.set(&"platform_size", size)
	_room.add_child(n)
	n.global_position = at
	return n


func _grid_of(body: StaticBody2D) -> DestructibleStage:
	return body.get_node_or_null(^"CarveGrid") as DestructibleStage


## ══ THE SEVERED RUN ════════════════════════════════════════════════════════
## The width of the widest run of columns with NO rock left where rock used to be — a
## stage cut in two. THE number this slice exists to move: it has been 0.
##
## ⚠ ASKS THE STAGE, NEVER RECONSTRUCTS THE SILHOUETTE. Copied verbatim from
## `tools/probe_destructible_bot_fight.gd` and `tools/slice_test_destructible_sources.gd`
## so the three agree by construction; the first version of the probe's copy rebuilt the
## original from the terrace table with a 2 px sample offset and reported an 80 px hole on
## a bout where nothing had been carved at all ([[feedback_harnesses_lie_verify_them]]).
func _severed_run(s: DestructibleStage) -> float:
	var run: int = 0
	var best: int = 0
	for cx: int in s.cols:
		var had: bool = false
		var has: bool = false
		for cy: int in s.rows:
			if s.was_rock(cx, cy):
				had = true
			if s.is_solid(cx, cy):
				has = true
				break
		if had and not has:
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return float(best) * DestructibleStage.CHUNK


# ── 1. the shape ───────────────────────────────────────────────────────────

## A stadium and not a strip, a box or a lozenge. Four probes, and each one is a
## different way the maths could be wrong:
##   * ON the segment, past both ends and inside the cap radius — the ROUND CAPS exist
##     (an unclamped projection would make this an infinite strip and take the whole row)
##   * past an end by MORE than the radius — the caps are round and not square
##   * beside the middle inside the radius — the flat sides are there
##   * beside the middle outside it — and they stop where they say they do
func the_capsule_is_a_stadium_with_round_caps_and_nothing_outside_it() -> void:
	await process_frame
	var s: DestructibleStage = _slab(Rect2(0.0, 0.0, 400.0, 200.0))
	var a := Vector2(120.0, 100.0)
	var b := Vector2(280.0, 100.0)
	var r: float = 20.0
	var before: int = s.solid_count()
	_expect(before > 0, "the test slab was born empty (%d cells)" % before)
	var removed: int = s.carve_capsule(a, b, r)
	_expect(removed > 0, "a 160 px span with a 20 px radius removed nothing")
	_expect(s.solid_count() == before - removed,
		"the grid lost %d cells but the capsule reported %d"
			% [before - s.solid_count(), removed])

	# Helper reads, so each probe below is one readable line.
	var solid_at := func(p: Vector2) -> bool:
		return s.is_solid(int((p.x - s.origin.x) / DestructibleStage.CHUNK),
			int((p.y - s.origin.y) / DestructibleStage.CHUNK))

	_expect(not solid_at.call(Vector2(200.0, 100.0)),
		"the middle of the span survived — this is not a capsule at all")
	# The caps: 12 px past the far end is inside a 20 px cap, 30 px past it is not.
	_expect(not solid_at.call(Vector2(292.0, 100.0)),
		"12 px past the end of a 20 px-radius span is still rock — the cap is missing,"
		+ " so this is a rectangle and the trench has square ends")
	_expect(solid_at.call(Vector2(310.0, 100.0)),
		"30 px past the end of a 20 px-radius span is gone — the projection is NOT"
		+ " clamped, so this is an infinite strip and the carve runs off the map")
	# The sides.
	_expect(not solid_at.call(Vector2(200.0, 114.0)),
		"14 px to the side of the span's middle survived a 20 px radius")
	_expect(solid_at.call(Vector2(200.0, 128.0)),
		"28 px to the side of a 20 px-radius span is gone — the capsule is wider than"
		+ " it claims and the drawn wall would disagree with the hole")
	# ...and a diagonal span works, which the axis-aligned probes above cannot show.
	var d: DestructibleStage = _slab(Rect2(0.0, 0.0, 400.0, 400.0))
	var got: int = d.carve_capsule(Vector2(100.0, 100.0), Vector2(300.0, 300.0), 16.0)
	_expect(got > 0, "a diagonal span removed nothing")
	var mid_on: bool = d.is_solid(int((200.0 - d.origin.x) / DestructibleStage.CHUNK),
		int((200.0 - d.origin.y) / DestructibleStage.CHUNK))
	var mid_off: bool = d.is_solid(int((260.0 - d.origin.x) / DestructibleStage.CHUNK),
		int((140.0 - d.origin.y) / DestructibleStage.CHUNK))
	_expect(not mid_on, "the diagonal span's own centre survived")
	_expect(mid_off,
		"a point 85 px off the diagonal's centre-line was removed by a 16 px radius —"
		+ " the scan rectangle is being cleared instead of the stadium inside it")
	_done("the_capsule_is_a_stadium_with_round_caps_and_nothing_outside_it")


# ── 2. the superset property ───────────────────────────────────────────────

## A span of zero length is a disc, cell for cell. This is what makes the capsule a
## SUPERSET of `carve_disc` rather than a second description of round holes that can
## drift from the first — and it is why `RockPillar` was left on the disc: a column's
## contact is round, and routing it through the span would buy an identical hole.
func a_zero_length_span_is_exactly_a_disc() -> void:
	await process_frame
	var at := Vector2(200.0, 100.0)
	var r: float = 23.0
	var by_disc: DestructibleStage = _slab(Rect2(0.0, 0.0, 400.0, 200.0))
	var by_span: DestructibleStage = _slab(Rect2(0.0, 0.0, 400.0, 200.0))
	var n_disc: int = by_disc.carve_disc(at, r)
	var n_span: int = by_span.carve_capsule(at, at, r)
	_expect(n_disc > 0, "the disc control removed nothing")
	_expect(n_disc == n_span,
		"a zero-length capsule removed %d cells where the disc removed %d" % [n_span, n_disc])
	var same: bool = true
	for cy: int in by_disc.rows:
		for cx: int in by_disc.cols:
			if by_disc.is_solid(cx, cy) != by_span.is_solid(cx, cy):
				same = false
				break
	_expect(same,
		"a zero-length capsule and a disc of the same radius left DIFFERENT cells"
		+ " standing — the two shapes have already drifted")
	_done("a_zero_length_span_is_exactly_a_disc")


# ── 3. the cost ────────────────────────────────────────────────────────────

## ⚠ THIS IS THE TEST THAT JUSTIFIES THE PRIMITIVE EXISTING AT ALL. A span could always
## have been faked as a row of overlapping `carve_disc` calls, and if that were no more
## expensive there would be no reason to write anything. It IS more expensive, twice
## over: every overlap re-walks cells a neighbour already visited, and every disc pays
## the bounds arithmetic again.
##
## ⚠ THE BUILD IS OUTSIDE THE TIMER. `build_from_rects` walks every cell in the slab,
## which is the same order of work as the carve — timing it would drown the thing being
## measured. Both sides are given a freshly built grid, untimed, every rep.
func the_scan_is_bounded_to_the_span_and_beats_a_row_of_discs() -> void:
	await process_frame
	var rect := Rect2(0.0, 0.0, 600.0, 200.0)
	var a := Vector2(60.0, 100.0)
	var b := Vector2(540.0, 100.0)
	var r: float = 14.0
	# A row spaced by the radius: heavy overlap, which is what it takes for a row of
	# discs to leave a trench with no scallops in its sides. This is the honest
	# implementation the capsule replaces, not a strawman with three discs in it.
	var steps: int = int(a.distance_to(b) / r) + 1
	var reps: int = 40
	var t_span: int = 0
	var t_discs: int = 0
	var cells_span: int = 0
	var cells_discs: int = 0
	for _i: int in reps:
		var s1: DestructibleStage = _slab(rect)
		var m1: int = Time.get_ticks_usec()
		cells_span = s1.carve_capsule(a, b, r)
		t_span += Time.get_ticks_usec() - m1
		var s2: DestructibleStage = _slab(rect)
		var m2: int = Time.get_ticks_usec()
		var n: int = 0
		for k: int in steps + 1:
			n += s2.carve_disc(a.lerp(b, float(k) / float(steps)), r)
		t_discs += Time.get_ticks_usec() - m2
		cells_discs = n
	var mean_span: float = float(t_span) / float(reps)
	var mean_discs: float = float(t_discs) / float(reps)
	print("[capsule-cost] span %.1f us  vs  %d discs %.1f us  (%.2fx)  |  cells %d vs %d"
		% [mean_span, steps + 1, mean_discs, mean_discs / maxf(mean_span, 0.001),
			cells_span, cells_discs])
	_expect(mean_span > 0.0, "the capsule timed at zero — the clock is not moving")
	_expect(mean_span < mean_discs,
		"one capsule (%.1f us) is not cheaper than the %d discs it replaces (%.1f us)"
			% [mean_span, steps + 1, mean_discs]
		+ " — the primitive is buying nothing")
	# ⚠ AND IT IS THE BETTER TRENCH AS WELL AS THE CHEAPER ONE, which is the half a
	# stopwatch cannot see. A row of discs spaced by the radius leaves SCALLOPS along the
	# sides of the slot — the rock between two neighbouring caps that neither one reached
	# — so it does more work and removes LESS. The capsule taking strictly more cells over
	# the same span is that difference, measured.
	_expect(cells_span > cells_discs,
		"the capsule removed %d cells and the row of %d discs removed %d over the same"
			% [cells_span, steps + 1, cells_discs]
		+ " span — the row is not leaving the scalloped edges it must, so these two are"
		+ " not being compared on the same trench")
	# ...and it is bounded to the SPAN, not to the grid. A tiny capsule in the corner of
	# a big slab must not cost what a slab-wide one does.
	var big: DestructibleStage = _slab(Rect2(0.0, 0.0, 2000.0, 1000.0))
	var t0: int = Time.get_ticks_usec()
	big.carve_capsule(Vector2(100.0, 100.0), Vector2(140.0, 100.0), 10.0)
	var tiny_us: int = Time.get_ticks_usec() - t0
	var wide: DestructibleStage = _slab(Rect2(0.0, 0.0, 2000.0, 1000.0))
	var t1: int = Time.get_ticks_usec()
	wide.carve_capsule(Vector2(100.0, 500.0), Vector2(1900.0, 500.0), 10.0)
	var wide_us: int = Time.get_ticks_usec() - t1
	print("[capsule-cost] 40 px span %d us  vs  1800 px span %d us on the same grid"
		% [tiny_us, wide_us])
	_expect(tiny_us * 4 < maxi(wide_us, 1),
		"a 40 px capsule (%d us) costs within 4x a 1800 px one (%d us) on the same"
			% [tiny_us, wide_us]
		+ " grid — the scan is not bounded to the span")
	_done("the_scan_is_bounded_to_the_span_and_beats_a_row_of_discs")


# ── 4. the wall, wired, for real ───────────────────────────────────────────

## ⚠ THE WALL IS RAISED, NOT POKED. `raise_wall` is called through real physics against a
## real ledge, so this asserts THE WIRE and not just the arithmetic behind it — a
## `_carve_trench` nobody calls would pass every geometry test above and do nothing in
## play ([[feedback_a_comment_is_not_an_implementation]]).
##
## The wall is raised from `WALL_OFFSET` to the LEFT of the ledge's centre so its own
## `wall_center` lands on top of the plank, which is where its floor probe must find it.
func a_rock_wall_trenches_the_ledge_it_tore_itself_out_of() -> void:
	await process_frame
	var ledge: StaticBody2D = _ledge(Vector2(600.0, 400.0))
	await _pump()
	var g: DestructibleStage = _grid_of(ledge)
	_expect(g != null, "the ledge built no carve grid — nothing to trench")
	if g == null:
		_done("a_rock_wall_trenches_the_ledge_it_tore_itself_out_of")
		return
	var before: int = g.solid_count()
	_expect(before > 0, "the ledge's grid was born empty (%d cells)" % before)
	var offset: float = _konst_f(ROCK_WALL, "WALL_OFFSET")
	var wide: float = (_konst(ROCK_WALL, "WALL_SIZE") as Vector2).x
	var wall: Node2D = (load(ROCK_WALL) as GDScript).new() as Node2D
	_room.add_child(wall)
	# Cast from a point WALL_OFFSET to the left of the ledge centre and 90 px up, aiming
	# right: `wall_center` therefore lands at (600, 310) and the probe drops onto the
	# plank's top face at y = 388.
	wall.call("raise_wall", Vector2(600.0 - offset, 310.0), Vector2.RIGHT,
		Color(0.78, 0.55, 0.28), "earth")
	await _pump()
	var base: Vector2 = wall.get("_floor_base") as Vector2
	_expect(absf(base.y - 388.0) < 2.0,
		"the wall seated at y=%.1f rather than on the ledge's top face (388) — the"
			% base.y + " floor probe missed the plank, so this proves nothing")
	var after: int = g.solid_count()
	_expect(after < before,
		"a rock wall rose off a ledge and the ledge lost NOTHING (%d -> %d cells)."
			% [before, after]
		+ " The trench is unwired.")
	_expect(g.carve_events == 1,
		"the raise produced %d carve event(s); one wall tears loose once" % g.carve_events)
	# ...and it came out ALONG the wall's footprint. The trench must be at least as long
	# as the wall is wide, and it must not have taken the far end of the plank with it.
	var cell: float = DestructibleStage.CHUNK
	var col := func(world_x: float) -> int:
		return int((ledge.to_local(Vector2(world_x, 400.0)).x - g.origin.x) / cell)
	var top_row: int = 0
	_expect(not g.is_solid(col.call(600.0), top_row),
		"the surface directly under the wall is untouched")
	_expect(not g.is_solid(col.call(600.0 - wide * 0.4), top_row),
		"the LEFT end of the wall's footprint kept its rock — the carve is a point, not"
		+ " a span")
	_expect(not g.is_solid(col.call(600.0 + wide * 0.4), top_row),
		"the RIGHT end of the wall's footprint kept its rock — the carve is a point, not"
		+ " a span")
	_expect(g.is_solid(col.call(600.0 + 80.0), top_row),
		"rock 80 px from a 44 px wall was removed — the trench is far longer than the"
		+ " wall is wide")
	wall.queue_free()
	ledge.queue_free()
	_done("a_rock_wall_trenches_the_ledge_it_tore_itself_out_of")


# ── 5. THE NUMBER ──────────────────────────────────────────────────────────

## ⚠ THIS IS THE POINT OF THE WHOLE SLICE. The severed run — the widest run of columns
## with no rock left where rock used to be — has been 0 across the destruction work, and
## `DestructibleStage`'s header named a row of bites along a span as the shape most
## likely to move it.
##
## Two measurements, on two identical ledges, from the SAME wall arithmetic:
##   * the wall's trench, a capsule along its footprint
##   * a single `carve_disc` of the same radius at the same sunk centre — which is the
##     most generous thing the old primitive could have done for a wall
##
## The disc reaches full depth only in the one column under its centre, so what it severs
## is a nick. The capsule reaches full depth along the whole span, so what it severs is
## the wall's width. Asserting the capsule's run against `WALL_SIZE.x` rather than against
## "greater than zero" is deliberate: the CLAIM is that the trench is as long as the wall
## is wide, and "some cells went" is not that claim.
func the_trench_severs_the_ledge_and_a_disc_of_the_same_radius_does_not() -> void:
	await process_frame
	var wide: float = (_konst(ROCK_WALL, "WALL_SIZE") as Vector2).x
	var bite: int = _konst_i(ROCK_WALL, "TRENCH_BITE")
	var half: float = wide * 0.5
	var r: float = DestructibleStage.carve_radius_for_strike(bite, half)
	var base := Vector2(600.0, 388.0)          # a ledge's top face, as above
	var sink := Vector2(0.0, r)

	var by_span: StaticBody2D = _ledge(Vector2(600.0, 400.0))
	var by_disc: StaticBody2D = _ledge(Vector2(1200.0, 400.0))
	await _pump()
	var gs: DestructibleStage = _grid_of(by_span)
	var gd: DestructibleStage = _grid_of(by_disc)
	_expect(gs != null and gd != null, "both control ledges built grids")
	if gs == null or gd == null:
		_done("the_trench_severs_the_ledge_and_a_disc_of_the_same_radius_does_not")
		return
	_expect(_severed_run(gs) == 0.0,
		"the ledge was already severed before anything hit it (%.0f px)" % _severed_run(gs))

	gs.damage_span(bite, base + Vector2(-half, 0.0) + sink,
		base + Vector2(half, 0.0) + sink, Vector2.UP, half, null)
	# The disc gets the identical radius at the identical sunk centre — every advantage
	# except the length.
	gd.damage_at(bite, Vector2(1200.0, 388.0) + sink, Vector2.UP, half, null)

	var span_run: float = _severed_run(gs)
	var disc_run: float = _severed_run(gd)
	print("[severed-run] ledge %.0f x %.0f px  |  wall trench %.0f px  vs  one disc"
			% [LEDGE_SIZE.x, LEDGE_SIZE.y, span_run]
		+ " of the same radius %.0f px  (carve radius %.1f px)" % [disc_run, r])
	_expect(span_run >= wide,
		"the trench severed %.0f px of a %.0f px ledge — less than the wall's own"
			% [span_run, LEDGE_SIZE.x]
		+ " %.0f px width, so it is not the trench the design promises"
			% wide)
	_expect(disc_run < wide,
		"a single disc already severed %.0f px, as much as the span does — the capsule"
			% disc_run + " is buying nothing this test can see")
	_expect(span_run > disc_run,
		"the span severed %.0f px and the disc %.0f px" % [span_run, disc_run])
	# ...and the plank is still a plank at its ends: severing it in the middle must leave
	# two pieces, not zero.
	_expect(gs.solid_count() > 0, "the trench took the whole ledge, not a slot out of it")
	by_span.queue_free()
	by_disc.queue_free()
	_done("the_trench_severs_the_ledge_and_a_disc_of_the_same_radius_does_not")


# ── 6. the two walls stay two spells ───────────────────────────────────────

## The walls' whole distinction is that they are one idea in two materials — rock is
## CHUNKY (44 px), ice is SLIM (30). That difference has to survive into the floor, or
## the trench is a third thing bolted onto both rather than a property of each wall.
##
## ⚠ BOTH ARE RAISED FOR REAL, and the ice wall's route is the interesting one: its seat
## comes from `SpellWorld.floor_point`, which PIERCES destructibles and hands back no
## collider at all, so it needs its own short non-piercing probe to find what it is
## standing on. If that probe is wrong the ice wall trenches nothing and this fails.
func an_ice_wall_leaves_a_narrower_trench_than_a_rock_wall() -> void:
	await process_frame
	var rock_ledge: StaticBody2D = _ledge(Vector2(600.0, 400.0))
	var ice_ledge: StaticBody2D = _ledge(Vector2(1200.0, 400.0))
	await _pump()
	var gr: DestructibleStage = _grid_of(rock_ledge)
	var gi: DestructibleStage = _grid_of(ice_ledge)
	_expect(gr != null and gi != null, "both ledges built grids")
	if gr == null or gi == null:
		_done("an_ice_wall_leaves_a_narrower_trench_than_a_rock_wall")
		return
	var rock_offset: float = _konst_f(ROCK_WALL, "WALL_OFFSET")
	var ice_offset: float = _konst_f(ICE_WALL, "WALL_OFFSET")
	var rock_wide: float = (_konst(ROCK_WALL, "WALL_SIZE") as Vector2).x
	var ice_wide: float = (_konst(ICE_WALL, "WALL_SIZE") as Vector2).x
	var rock: Node2D = (load(ROCK_WALL) as GDScript).new() as Node2D
	_room.add_child(rock)
	rock.call("raise_wall", Vector2(600.0 - rock_offset, 310.0), Vector2.RIGHT,
		Color(0.78, 0.55, 0.28), "earth")
	var ice: Node2D = (load(ICE_WALL) as GDScript).new() as Node2D
	_room.add_child(ice)
	ice.call("raise_wall", Vector2(1200.0 - ice_offset, 310.0), Vector2.RIGHT,
		Color(0.55, 0.8, 1.0), "frost")
	await _pump()
	var rock_cells: int = gr.carved_cells
	var ice_cells: int = gi.carved_cells
	print("[wall-trench] rock (%0.f px wide) took %d cells; ice (%.0f px) took %d"
		% [rock_wide, rock_cells, ice_wide, ice_cells])
	_expect(ice_cells > 0,
		"an ice wall rose off a ledge and took NOTHING with it — its surface probe found"
		+ " no body, so the trench is unwired for ice")
	_expect(rock_cells > 0, "the rock control took nothing either")
	_expect(ice_cells < rock_cells,
		"the ice wall's trench (%d cells) is not narrower than the rock wall's (%d)."
			% [ice_cells, rock_cells]
		+ " The two walls are one spell in two colours in the floor as well.")
	rock.queue_free()
	ice.queue_free()
	rock_ledge.queue_free()
	ice_ledge.queue_free()
	_done("an_ice_wall_leaves_a_narrower_trench_than_a_rock_wall")


# ── 7. and the world's floor is still a floor ──────────────────────────────

## THE OTHER HALF OF THE RULING. The maker tried a destructible ground and ruled it back
## out; the versus stage keeps its carvable terraces, but a wall going up must SCAR them
## and never open them. Same trench, same wall, same arithmetic — a 320 px terrace simply
## has more rock than a 24 px plank, and the depth rule (`2 * radius`, sunk by `radius`)
## is what makes one outcome fall out of the other rather than being two special cases.
func a_wall_scars_the_worlds_floor_and_never_cuts_through_it() -> void:
	await process_frame
	var stage: DestructibleStage = _ground_stage()
	await _pump()
	_expect(_severed_run(stage) == 0.0, "the ground stage started intact")
	var wall: Node2D = (load(ROCK_WALL) as GDScript).new() as Node2D
	_room.add_child(wall)
	wall.set("_floor_base", Vector2(700.0, 780.0))   # the main terrace's surface
	var before: int = stage.solid_count()
	wall.call("_carve_trench", stage.rebuild_collision(stage))
	var after: int = stage.solid_count()
	_expect(after < before,
		"the wall's trench took nothing out of the world's floor (%d -> %d)"
			% [before, after])
	var run: float = _severed_run(stage)
	print("[severed-run] versus terrace (%.0f px deep): wall trench severed %.0f px"
		% [TERRACE_DEPTH, run])
	_expect(run == 0.0,
		"a rock wall cut clean through a %.0f px terrace: %.0f px of the world's floor"
			% [TERRACE_DEPTH, run]
		+ " has no rock left in the column. A wall is cover, not a pit.")
	wall.queue_free()
	_drop_stage(stage)
	await process_frame
	_expect(DestructibleStage.stage_in(_room) == null,
		"the test ground stage is still the first member of %s — every later carve in"
			% DestructibleStage.GROUP_NAME + " this run would be steered onto it")
	_done("a_wall_scars_the_worlds_floor_and_never_cuts_through_it")


# ── 8. nothing tunnels ─────────────────────────────────────────────────────

## The anti-cascade ledger, for spans. This is not decoration: `HorizonArc` calls
## `_carve_through` on every frame it is over a body, so without a ledger entry covering
## the WHOLE trench a travelling cut would re-cut the same plank sixty times a second and
## the depth of the slot would be a function of frame rate.
##
## The case that actually happens is the SECOND FRAME: a cut whose span has crept
## forward by one frame's flight and is still lying in the slot it opened last frame.
## That is what `HorizonArc` offers sixty times a second and it is what must be refused.
##
## ⚠ AND THE COMPLEMENT IS ASSERTED TOO, because an over-broad ledger is a bug in the
## other direction: it would silently stop a fault line or a marching cut from ever
## biting again. A span clear of the first trench must still be admitted.
func the_ledger_refuses_a_source_re_digging_its_own_trench() -> void:
	await process_frame
	var s: DestructibleStage = _slab(Rect2(0.0, 0.0, 900.0, 400.0))
	var src := RefCounted.new()
	var a := Vector2(120.0, 200.0)
	var b := Vector2(420.0, 200.0)
	var first: int = s.damage_span(60, a, b, Vector2.DOWN, 20.0, src)
	_expect(first > 0, "the first span bite removed nothing")
	var again: int = s.damage_span(60, a, b, Vector2.DOWN, 20.0, src)
	_expect(again == 0,
		"the same source re-dug its own trench for another %d cells" % again)
	# One frame of a travelling cut: ~19 px at `HorizonArc.SPEED` and 30 fps, which is
	# the most generous stride the spell can produce.
	var crept: int = s.damage_span(60, a + Vector2(19.0, 0.0), b + Vector2(19.0, 0.0),
		Vector2.DOWN, 20.0, src)
	_expect(crept == 0,
		"a span that had crept forward by one frame's flight took %d more cells — a"
			% crept
		+ " travelling cut walks its own slot into a tunnel and the depth of it becomes"
		+ " a function of frame rate")
	_expect(s.repeat_refused_hits == 2,
		"the ledger refused %d bite(s); two were offered and both should have been"
			% s.repeat_refused_hits)
	# ...and NOT over-broad: a span clear of the first trench still bites. The recorded
	# crater is the trench's bounding circle (half-length + radius = 170 px) and
	# `CARVE_REPEAT_BITE` is 0.75 of it, so a midpoint 200 px out is honestly new ground.
	var clear_bite: int = s.damage_span(60, b + Vector2(80.0, 0.0),
		b + Vector2(380.0, 0.0), Vector2.DOWN, 20.0, src)
	_expect(clear_bite > 0,
		"a span well clear of the first trench was refused — the ledger is over-broad,"
		+ " and a marching effect would bite once and then never again")
	# ...and the rule is per-SOURCE: two different strikes on one spot are two strikes.
	#
	# ⚠ COUNTED THROUGH `repeat_refused_hits`, NOT THROUGH CELLS REMOVED. The rock along
	# that span is already gone, so a second strike there legitimately removes 0 whether
	# it was admitted or refused — reading the return value cannot tell the two apart and
	# would pass no matter which way the ledger went.
	var refused_before: int = s.repeat_refused_hits
	var other := RefCounted.new()
	s.damage_span(60, a, b, Vector2.DOWN, 20.0, other)
	_expect(s.repeat_refused_hits == refused_before,
		"a DIFFERENT source was turned away by this source's ledger — the anti-cascade"
		+ " rule has gone global, and two spells hitting one spot now count as one")
	_done("the_ledger_refuses_a_source_re_digging_its_own_trench")


# ── 9. the spectacle's budget ──────────────────────────────────────────────

## ⚠ THE COSMETIC CAP IS THE ONE CAP THIS FILE IS ALLOWED. The maker's ruling forbids
## capping the CELLS a carve removes (*"if that happens then it happens it will be a
## projectile based ending"*), and nothing here does. What IS capped is the debris, and a
## span is exactly where that could have gone wrong: fire the disc's spectacle at every
## step of a 600 px cut and you get six times the disc's chunks and six times its decals
## for one hit.
##
## So the assertion is the tight one — a long span requests EXACTLY what a disc of the
## same radius requests, never a multiple of it. Read off `DebrisChunk._requested`, which
## counts what was ASKED for before the austerity thinning, so the number does not move
## with the frame budget.
func the_span_spends_the_discs_debris_budget_and_never_a_multiple_of_it() -> void:
	await process_frame
	var disc_stage: DestructibleStage = _slab(Rect2(0.0, 0.0, 900.0, 400.0))
	var span_stage: DestructibleStage = _slab(Rect2(0.0, 0.0, 900.0, 400.0))
	# In the tree, because `_spawn_carve_spectacle` parents debris to `get_parent()` and
	# does nothing at all when there isn't one.
	_room.add_child(disc_stage)
	_room.add_child(span_stage)
	disc_stage.spectacle = true
	span_stage.spectacle = true
	await process_frame

	var d0: int = DebrisChunk._requested
	disc_stage.damage_at(80, Vector2(400.0, 200.0), Vector2.DOWN, 24.0, null)
	var disc_chunks: int = DebrisChunk._requested - d0
	var s0: int = DebrisChunk._requested
	# 700 px of span — the longest thing in the roster, a full-width Horizon Cut chord.
	span_stage.damage_span(80, Vector2(100.0, 200.0), Vector2(800.0, 200.0),
		Vector2.DOWN, 24.0, null)
	var span_chunks: int = DebrisChunk._requested - s0
	print("[span-debris] one disc requested %d chunks; a 700 px trench requested %d"
		% [disc_chunks, span_chunks])
	_expect(disc_chunks > 0, "the disc control requested no debris at all")
	_expect(span_chunks == disc_chunks,
		"a 700 px trench requested %d chunks against the disc's %d — the span is"
			% [span_chunks, disc_chunks]
		+ " spending the disc's budget PER SAMPLE instead of across the span")
	_expect(span_chunks <= DestructibleStage.MAX_DEBRIS_PER_CARVE,
		"a span requested %d chunks against a cap of %d"
			% [span_chunks, DestructibleStage.MAX_DEBRIS_PER_CARVE])
	# ...and a SHORT span collapses to one sample, i.e. to the disc's own burst.
	var short_stage: DestructibleStage = _slab(Rect2(0.0, 0.0, 900.0, 400.0))
	_room.add_child(short_stage)
	short_stage.spectacle = true
	await process_frame
	var t0: int = DebrisChunk._requested
	short_stage.damage_span(80, Vector2(400.0, 200.0), Vector2(410.0, 200.0),
		Vector2.DOWN, 24.0, null)
	_expect(DebrisChunk._requested - t0 == disc_chunks,
		"a 10 px span requested %d chunks where the disc requested %d — a trench shorter"
			% [DebrisChunk._requested - t0, disc_chunks]
		+ " than one stride should be byte-identical to a disc's burst")
	disc_stage.queue_free()
	span_stage.queue_free()
	short_stage.queue_free()
	_done("the_span_spends_the_discs_debris_budget_and_never_a_multiple_of_it")


# ── 10. Horizon Cut, finally wired ─────────────────────────────────────────

## `HorizonArc` was left unwired because a disc is the wrong description of a wall of
## edge: sized to its 600 px height it would gouge a crater as wide as the cut is tall,
## and sized to its 30 px thickness it would nick. Its span is the tip-to-tip chord it
## already publishes through `arc_point`, which is the same function `_draw()` asks — so
## the slot in the rock is generated from the picture rather than from a second
## description of it.
##
## ⚠ THE ARC IS FLOWN, NOT POKED. It is swept at a real ledge and left to run its own
## `_process` until it bites, so this asserts the WIRE inside that function.
func a_horizon_cut_slots_the_plank_it_stopped_against() -> void:
	await process_frame
	# ⚠ ITS OWN LANE, WELL CLEAR OF EVERY OTHER TEST'S FIXTURE. A travelling cut stops on
	# the FIRST solid thing in front of it, so a ledge another test left standing in this
	# one's flight path silently becomes the thing that gets slotted — and this test then
	# reads 0 carve events off a plank the blade never reached and reports the spell
	# unwired. Measured: it did exactly that. y = 1600 is below the versus terraces
	# (528-1100) and far from the 400-line the wall tests use.
	var ledge: StaticBody2D = _ledge(Vector2(900.0, 1600.0), Vector2(260.0, 24.0))
	await _pump()
	var g: DestructibleStage = _grid_of(ledge)
	_expect(g != null, "the ledge built no grid for the cut to bite")
	if g == null:
		_done("a_horizon_cut_slots_the_plank_it_stopped_against")
		return
	var before: int = g.solid_count()
	var arc: Node2D = (load(HORIZON_ARC) as GDScript).new() as Node2D
	_room.add_child(arc)
	# Launched level with the plank and well short of it, so the flight is real and the
	# blade meets the plank's near face rather than starting inside it.
	arc.call("sweep", Vector2(500.0, 1596.0), Vector2.RIGHT, Color.WHITE,
		900.0, 30.0, 90.0, 300.0, 110)
	# Fly it. The cut travels at SPEED px/s, so a handful of generous steps covers the
	# ~270 px to the plank several times over; it stops itself on the bite.
	# ⚠ `is_instance_valid` FIRST, every step. A spent cut calls `queue_free()` on itself
	# from inside `_process`, so a loop that only checks `_live` reads a property off a
	# freed instance the moment the flight over-runs — which is a hard error, not a false
	# assertion, and it aborts the test before its completion sentinel.
	for _i: int in 30:
		if not is_instance_valid(arc) or not bool(arc.get("_live")):
			break
		arc.call("_process", 0.03)
		await _pump(1)
		if g.carve_events > 0:
			break
	var after: int = g.solid_count()
	print("[horizon-cut] plank %d -> %d cells over %d carve event(s); severed run %.0f px"
		% [before, after, g.carve_events, _severed_run(g)])
	_expect(g.carve_events > 0,
		"a Horizon Cut met a plank and took nothing out of it — `_carve_through` is not"
		+ " reached from `_process`, so the spell is still unwired")
	_expect(after < before,
		"the cut fired a carve event but removed no cells (%d -> %d)" % [before, after])
	# ⚠ AND IT CANNOT TUNNEL. A second `_carve_through` at the same place is the frame
	# after the first, which is precisely what the ledger exists to refuse.
	var events: int = g.carve_events
	if is_instance_valid(arc):
		arc.call("_carve_through", ledge)
		_expect(g.carve_events == events,
			"the cut bit the same plank twice — the slot deepens with the frame rate")
		arc.queue_free()
	ledge.queue_free()
	_done("a_horizon_cut_slots_the_plank_it_stopped_against")
