# Run: godot --headless --path godot-project --script tools/slice_test_stage_variants.gd
#
# THE DUEL STAGE HAS MORE THAN ONE SHAPE NOW, AND EVERY SHAPE IS WALKABLE.
#
# Maker: *"I think the maps need some more variety as well"*.
#
# What varied per bout before: the SKY. `_stage_theme` rolls a `GameState.BIOMES` row,
# and every consumer of it is sky/silhouette/accent colour plus a PostProcess wash.
# That table carries `{name, wash, accent, light}` and is physically incapable of
# holding a coordinate, so ten "different" stages were ten repaints of one shape.
#
# ⚠ AND THE ONE SHAPE WAS ILLEGAL. `FloorGen` documents the hero's real movement
# budget — a 580 jump against 1500 gravity apexes at 112 px, so a COMFORTABLE (not
# frame-perfect) step is `STEP_MAX = 86` — and the shipped `TERRACES` had THREE 90 px
# risers on its right staircase. Nothing ever checked, because `FloorGen` validates
# the TOWER's generated floors and this stage is hand-authored in another file.
#
# That is also half of *"these guys get stuck in the corner of a wall then destroyed"*:
# a bot pressed into a face it cannot climb has nowhere to go.
#
# THIS SUITE IS THE CHECK THAT WAS MISSING, applied to every variant including the
# original — which is why the original's risers moved 90 -> 84.
#
# ⚠ AND IT PINS WHAT MAY NOT VARY. Two facts are load-bearing far outside VersusArena:
# the MAIN FLOOR ROW (780, x 40..1400) which `BotMatch.FLOOR_CENTRE_X`, `SPAWN_Y`,
# `COVER_X_MIN/MAX`, the camera clamps and ~25 capture tools are all derived from; and
# the OUTER EXTENT (40..1965) which `PROBE_TERRAIN_X0/X1` are hand-copied from. A
# variant that broke either would not fail loudly — it would file live anomalies and
# reframe every clip.
#
# ⚠ LOADED BY PATH, NEVER BY `class_name`: `VersusArena` and `FloorGen` reach the
# autoloads, which do not exist during a `--script` run.
#
# ⚠ NEVER `failed += _test_x()`. Failures accumulate on `_fails`; every test records a
# COMPLETION SENTINEL so one that aborts half-way fails the suite by absence.
extends SceneTree

const ARENA_PATH: String = "res://scripts/combat/VersusArena.gd"
const FLOORGEN_PATH: String = "res://scripts/tower/FloorGen.gd"

const TESTS: Array[String] = [
	"there_is_more_than_one_stage",
	"every_variant_keeps_the_fight_floor",
	"every_variant_stays_inside_the_rim",
	"every_riser_is_climbable",
	"no_terrace_floats_unreachable",
	"cover_matches_the_variant_count",
	"cover_sits_on_the_fight_floor",
	"the_roll_is_stable_within_a_bout",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _arena: GDScript = null
var _k: Dictionary = {}
var _step_max: float = 86.0


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_arena = load(ARENA_PATH) as GDScript
	if _arena == null:
		printerr("stage_variants: FAIL — could not load VersusArena.gd")
		printerr("stage variant tests: 1 FAILED")
		quit(1)
		return true
	_k = _arena.get_script_constant_map()
	var fg: GDScript = load(FLOORGEN_PATH) as GDScript
	if fg != null:
		_step_max = float(fg.get_script_constant_map().get("STEP_MAX", 86.0))

	_test_count()
	_test_floor_row()
	_test_rim()
	_test_risers()
	_test_reachable()
	_test_cover_count()
	_test_cover_on_floor()
	_test_roll_stable()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("stage_variants: TEST DID NOT COMPLETE — %s (aborted part-way)" % name)
	if _fails == 0:
		print("stage variant tests: all PASS")
	else:
		printerr("stage variant tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("stage_variants: FAIL — %s" % what)


func _variants() -> Array:
	return _k.get("STAGE_TERRACES", []) as Array


# --------------------------------------------------------------------------- 1
func _test_count() -> void:
	_expect(_variants().size() >= 3,
		"only %d stage variant(s) — the duel is back to one shape in ten colours"
			% _variants().size())
	_completed["there_is_more_than_one_stage"] = true


# --------------------------------------------------------------------------- 2
## THE ROW EVERY OTHER FILE IS DERIVED FROM. `BotMatch.FLOOR_CENTRE_X` is literally
## commented `(40 + 1400) / 2`.
func _test_floor_row() -> void:
	var ground: float = float(_k.get("GROUND_TOP", 780.0))
	for i: int in _variants().size():
		var rows: Array = _variants()[i]
		_expect(not rows.is_empty(), "variant %d has no terraces at all" % i)
		if rows.is_empty():
			continue
		var first: Dictionary = rows[0]
		_expect(is_equal_approx(float(first["surface_y"]), ground),
			"variant %d's first row is at y %.0f, not GROUND_TOP (%.0f) — spawn Y, "
				% [i, float(first["surface_y"]), ground]
				+ "the camera clamps and every capture tool are derived from it")
		_expect(is_equal_approx(float(first["x0"]), 40.0)
				and is_equal_approx(float(first["x1"]), 1400.0),
			"variant %d's fight floor spans %.0f..%.0f, not 40..1400 — BotMatch's "
				% [i, float(first["x0"]), float(first["x1"])]
				+ "FLOOR_CENTRE_X and the cover clamps are derived from those numbers")
	_completed["every_variant_keeps_the_fight_floor"] = true


# --------------------------------------------------------------------------- 3
func _test_rim() -> void:
	var lo: float = float(_k.get("PROBE_TERRAIN_X0", 40.0))
	var hi: float = float(_k.get("PROBE_TERRAIN_X1", 1965.0))
	for i: int in _variants().size():
		for t: Dictionary in _variants()[i]:
			_expect(float(t["x0"]) >= lo - 0.01 and float(t["x1"]) <= hi + 0.01,
				"variant %d has a terrace at %.0f..%.0f, outside the probe's own "
					% [i, float(t["x0"]), float(t["x1"])]
					+ "terrain bounds (%.0f..%.0f) — the live probe would file an "
					% [lo, hi] + "anomaly for anyone standing on it")
	_completed["every_variant_stays_inside_the_rim"] = true


# --------------------------------------------------------------------------- 4
## ⚠ THE ONE THE SHIPPED STAGE FAILED. Three 90 px risers against a documented
## comfortable step of 86.
func _test_risers() -> void:
	for i: int in _variants().size():
		var rows: Array = _variants()[i]
		for a: int in rows.size():
			for b: int in rows.size():
				if a == b:
					continue
				var lo: Dictionary = rows[a]
				var hi: Dictionary = rows[b]
				# Only pairs that actually TOUCH form a riser; disjoint terraces are
				# a gap, not a step, and are covered by the reachability test below.
				if float(hi["x0"]) > float(lo["x1"]) or float(lo["x0"]) > float(hi["x1"]):
					continue
				var rise: float = float(lo["surface_y"]) - float(hi["surface_y"])
				if rise <= 0.0:
					continue
				_expect(rise <= _step_max + 0.01,
					"variant %d has a %.0f px riser (%.0f -> %.0f); FloorGen's own "
						% [i, rise, float(lo["surface_y"]), float(hi["surface_y"])]
						+ "COMFORTABLE step is %.0f, and a bot pressed into a face "
						% _step_max + "it cannot climb is the corner it dies in")
	_completed["every_riser_is_climbable"] = true


# --------------------------------------------------------------------------- 5
## Every terrace has to be reachable from the fight floor by SOME chain of legal
## steps, or a variant can hide a shelf nobody can ever stand on — which looks
## identical to a shelf that is simply unused.
func _test_reachable() -> void:
	for i: int in _variants().size():
		var rows: Array = _variants()[i]
		var reached: Array[int] = [0]
		var grew: bool = true
		while grew:
			grew = false
			for b: int in rows.size():
				if reached.has(b):
					continue
				for a: int in reached:
					if _steps(rows[a], rows[b]):
						reached.append(b)
						grew = true
						break
		_expect(reached.size() == rows.size(),
			"variant %d has %d of %d terraces reachable from the fight floor"
				% [i, reached.size(), rows.size()])
	_completed["no_terrace_floats_unreachable"] = true


## Can a body get from terrace `a` to terrace `b`? Same shape as
## `FloorGen.can_step`, restated here rather than called: that function takes the
## generator's own surface record and this file must not depend on its exact keys.
func _steps(a: Dictionary, b: Dictionary) -> bool:
	var rise: float = float(a["surface_y"]) - float(b["surface_y"])
	if rise > _step_max:
		return false
	var gap: float = 0.0
	if float(b["x0"]) > float(a["x1"]):
		gap = float(b["x0"]) - float(a["x1"])
	elif float(a["x0"]) > float(b["x1"]):
		gap = float(a["x0"]) - float(b["x1"])
	return gap <= (110.0 if rise > 0.0 else 170.0)


# --------------------------------------------------------------------------- 6
func _test_cover_count() -> void:
	var cover: Array = _k.get("STAGE_COVER", []) as Array
	_expect(cover.size() == _variants().size(),
		"%d cover sets for %d terrain variants — a bout would build the terrain for "
			% [cover.size(), _variants().size()] + "one stage and the cover for another")
	_completed["cover_matches_the_variant_count"] = true


# --------------------------------------------------------------------------- 7
## Cover has to stand ON the fight floor. A block authored over a terrace it does not
## touch hangs in the air; one outside 40..1400 hangs over the blast zone.
func _test_cover_on_floor() -> void:
	var ground: float = float(_k.get("GROUND_TOP", 780.0))
	var cover: Array = _k.get("STAGE_COVER", []) as Array
	for i: int in cover.size():
		for pt: Vector2 in (cover[i] as Array):
			_expect(is_equal_approx(pt.y, ground - 32.0),
				"variant %d has cover at y %.0f — a 64 px block resting on %.0f must "
					% [i, pt.y, ground] + "be centred at %.0f" % (ground - 32.0))
			_expect(pt.x >= 72.0 and pt.x <= 1368.0,
				"variant %d has cover at x %.0f, off the fight floor" % [i, pt.x])
	_completed["cover_sits_on_the_fight_floor"] = true


# --------------------------------------------------------------------------- 8
## ⚠ EVERY BUILDER ASKS SEPARATELY. `_build_terrain` and `_build_cover` each call the
## accessor, so a roll that re-rolled per call would build the terrain for one stage
## and place the cover for another — and it would do it rarely enough to look like a
## drawing bug rather than a logic one.
func _test_roll_stable() -> void:
	_arena.set("stage_layout", -1)
	_arena.set("_layout_rolled", false)
	var first: Array = _arena.call("active_terraces")
	for i: int in 8:
		_expect(_arena.call("active_terraces") == first,
			"the stage roll changed between calls within one bout")
	_expect(_arena.call("active_cover")
		== (_k.get("STAGE_COVER", []) as Array)[int(_arena.get("stage_layout_rolled"))],
		"the cover does not belong to the terrain that was rolled")
	# ...and an explicit pin wins, which is what the capture tools rely on.
	for want: int in _variants().size():
		_arena.set("stage_layout", want)
		_expect(_arena.call("active_terraces") == _variants()[want],
			"pinning stage_layout = %d did not select variant %d" % [want, want])
	_arena.set("stage_layout", -1)
	_completed["the_roll_is_stable_within_a_bout"] = true
