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
	"cover_never_gates_the_opening",
	"no_terrain_swallows_a_spawn",
	"the_roll_is_stable_within_a_bout",
	"breakable_platforms_are_climbable",
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
	_test_breakable_platforms_are_climbable()
	_test_cover_count()
	_test_cover_on_floor()
	_test_cover_not_in_the_corridor()
	_test_terrain_clear_of_spawns()
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
## COVER MAY NOT STAND BETWEEN THE FIGHTERS AT THE BELL.
##
## Maker, 2026-08-11, watching a bot fight: *"they start behind the crate then break
## the crate and walk into them"*. The blocks were authored at 470 / 1180 against
## spawns at 440 / 1000, and `cover_x_clear_of` guarantees only 54 px of clearance —
## enough to not OVERLAP, nowhere near enough to be out of the way. So every bout
## opened with both fighters demolishing a crate instead of fighting.
##
## ⚠ THIS IS CURRENTLY A GUARD, NOT A MEASUREMENT, AND THAT IS WORTH SAYING PLAINLY:
## `STAGE_COVER` is empty by the same ruling, so every loop below runs zero times and
## the assertion is trivially true today. It exists so that re-authoring a crate back
## into the corridor fails the build instead of quietly restoring the dead opening —
## the emptiness is a DECISION, and a decision no test mentions is one the next
## session silently reverses.
func _test_cover_not_in_the_corridor() -> void:
	# The mirrored bot-match spawns, by path — `BotMatch.gd` names autoloads, so a
	# `class_name` reference here would poison this file's compile. Same rule as the
	# header. Falls back to the documented 720 +/- 280 if the file ever moves.
	var centre: float = 720.0
	var spread: float = 280.0
	var bm: GDScript = load("res://scripts/combat/BotMatch.gd") as GDScript
	if bm != null:
		var k: Dictionary = bm.get_script_constant_map()
		centre = float(k.get("FLOOR_CENTRE_X", centre))
		spread = float(k.get("SPAWN_SPREAD", spread))
	# A crate the fighters can reach before each other is a crate they will hit first.
	# Half a 64 px block plus a body's own footprint is the bare minimum; the margin
	# below is what "out of the way" actually means at this spawn distance.
	var margin: float = 140.0
	var lo: float = centre - spread
	var hi: float = centre + spread
	var cover: Array = _k.get("STAGE_COVER", []) as Array
	for i: int in cover.size():
		for pt: Vector2 in (cover[i] as Array):
			_expect(pt.x <= lo - margin or pt.x >= hi + margin
					or (pt.x > lo + margin and pt.x < hi - margin),
				"variant %d puts cover at x %.0f, within %.0f px of a spawn (%.0f / "
					% [i, pt.x, margin, lo] + "%.0f) — that is the crate both fighters "
					% hi + "break before they ever reach each other")
	_completed["cover_never_gates_the_opening"] = true


# --------------------------------------------------------------------------- 9
## NO TERRACE MAY CONTAIN A SPAWN POINT. This is the check whose absence let variant 2
## ship with the right-hand fighter buried in solid rock on ~1 bout in 3.
##
## ⚠ THE MISTAKE THAT MADE IT INVISIBLE: a terrace row LOOKS like a surface — it is
## authored as `{surface_y, x0, x1}`, and every test above reasons about it as a line
## you stand on. `_make_terrace` grows it DOWNWARD by `TERRACE_DEPTH` into a solid body.
## So the authored table can be entirely legal as a set of surfaces (correct risers, all
## reachable, inside the rim — variant 2 passed all four) while one of those surfaces is
## a 320 px-deep block sitting exactly where a fighter is about to be placed.
##
## The cover test next door pins the same corridor. Cover got a rule and terrain did
## not, which is the more dangerous half: a crate you can break, and rock you cannot.
func _test_terrain_clear_of_spawns() -> void:
	var depth: float = float(_k.get("TERRACE_DEPTH", 320.0))
	# Every point any mode places a body at, gathered from the constants themselves so a
	# spawn that MOVES is re-checked rather than silently escaping this test.
	var spawns: Array[Vector2] = []
	for key: String in ["DUEL_SPAWN_HUMAN", "DUEL_SPAWN_BOT", "SHOWCASE_SPAWN_A",
			"SHOWCASE_SPAWN_B", "FREE_SPAWN"]:
		var v: Variant = _k.get(key)
		if v is Vector2:
			spawns.append(v as Vector2)
	# ...plus BotMatch's, which are NOT in this file: it re-seats the fighters after the
	# arena is built, so the stage's own spawn constants are not where anybody ends up.
	var bm: GDScript = load("res://scripts/combat/BotMatch.gd") as GDScript
	if bm != null:
		var bk: Dictionary = bm.get_script_constant_map()
		var cx: float = float(bk.get("FLOOR_CENTRE_X", 720.0))
		var spread: float = float(bk.get("SPAWN_SPREAD", 280.0))
		var sy: float = float(bk.get("SPAWN_Y", 760.0))
		spawns.append(Vector2(cx - spread, sy))
		spawns.append(Vector2(cx + spread, sy))
	_expect(not spawns.is_empty(),
		"found at least one spawn constant to check — an empty list would make every "
			+ "assertion below vacuously true, which is how the bug got in")

	# Half a body plus the air it wants, matching SPAWN_FOOTPRINT_HALF's reasoning.
	var pad: float = float(_k.get("SPAWN_FOOTPRINT_HALF", 22.0))
	for i: int in _variants().size():
		for t: Dictionary in _variants()[i]:
			var top: float = float(t["surface_y"])
			var x0: float = float(t["x0"]) - pad
			var x1: float = float(t["x1"]) + pad
			for s: Vector2 in spawns:
				var inside: bool = s.x >= x0 and s.x <= x1 \
					and s.y > top and s.y < top + depth
				_expect(not inside,
					"variant %d buries a spawn at (%.0f, %.0f) inside the terrace whose "
						% [i, s.x, s.y] + "surface is y %.0f spanning x %.0f..%.0f — a "
						% [top, float(t["x0"]), float(t["x1"])]
						+ "terrace is %.0f px of SOLID ROCK below its surface, not a line"
						% depth)
	_completed["no_terrain_swallows_a_spawn"] = true


# -------------------------------------------------------------------------- 10
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


# --------------------------------------------------------------------------- 11
## THE THREE BREAKABLE LEDGES MUST BE REACHABLE, AND NOTHING HAS EVER CHECKED.
##
## `BREAKABLE_PLATFORMS` is the one platform table that does not vary per stage, and
## it sat outside every test in this file — which is exactly how `RUINS[0]` came to be
## authored 119 px above a 105 px jump and shipped, "touchable only by a Brawler
## spending its air jump". The maker then asked for the LEFT ledge to match the
## far-right one at 616, a 164 px rise from the ground, so this table now carries a
## surface that is deliberately NOT ground-reachable and is only legal because the mid
## platform is a rung under it. That is precisely the arrangement that needs a guard
## rather than a comment.
##
## ⚠ THIS DELIBERATELY DOES NOT USE `_steps`. That helper's 110 / 170 px gap budget is
## `FloorGen.GAP_UP_MAX` / `GAP_FLAT_MAX`, and those are calibrated to DEAD CONSTANTS —
## they derive from "JUMP_VELOCITY 580 against GRAVITY 1500" while `TuningConfig`
## overrides both at runtime (740 / 2600). Against the live numbers the true rising
## reach is ~83.6 px, not 110. So this test derives its own budget from the tuning the
## game actually runs, and will therefore fail on a ledge `_steps` would wave through.
func _test_breakable_platforms_are_climbable() -> void:
	var plats: Array = _k.get("BREAKABLE_PLATFORMS", []) as Array
	_expect(plats.size() >= 3, "the three breakable ledges are still declared")
	if plats.size() < 3:
		return
	var ground: float = float(_k.get("GROUND_TOP", 780.0))

	# The LIVE ceiling, from the tuning the game runs — not Hero's dead consts.
	var tune: Node = Engine.get_main_loop().root.get_node_or_null("Tuning")
	var jump_v: float = 740.0
	var grav: float = 2600.0
	# `Tuning` is a plain autoload holding a `TuningConfig` resource; the read is a
	# property get off `cfg`, the same shape `Hero._tune` uses. There is no getter
	# method, and calling one aborts the test rather than failing it — which is what
	# the vacuous-pass armour at the top of this file exists to catch, and did.
	var cfg: Object = tune.get("cfg") if tune != null else null
	if cfg != null:
		var jv: Variant = cfg.get("move_jump_velocity")
		var gr: Variant = cfg.get("move_gravity_rise")
		if jv != null:
			jump_v = absf(float(jv))
		if gr != null:
			grav = float(gr)
	var ceiling: float = (jump_v * jump_v) / (2.0 * grav)
	# Horizontal travel while still RISING, which is what a step-up actually gets.
	var rise_reach: float = 83.6

	# Surfaces + spans. A platform's `center` is its middle, so the walkable top is
	# half its height above that — the convention the terraces do NOT use.
	var surf: Array[float] = []
	var x0: Array[float] = []
	var x1: Array[float] = []
	for p: Dictionary in plats:
		var c: Vector2 = p["center"]
		var sz: Vector2 = p["size"]
		surf.append(c.y - sz.y * 0.5)
		x0.append(c.x - sz.x * 0.5)
		x1.append(c.x + sz.x * 0.5)

	# Flood out from the ground: a platform is reachable if the ground reaches it, or
	# if some already-reachable platform is a legal step to it.
	var reached: Array[int] = []
	for i: int in plats.size():
		if ground - surf[i] <= ceiling:
			reached.append(i)
	var grew: bool = true
	while grew:
		grew = false
		for b: int in plats.size():
			if reached.has(b):
				continue
			for a: int in reached:
				var rise: float = surf[a] - surf[b]
				if rise <= 0.0 or rise > _step_max or rise > ceiling:
					continue
				var gap: float = maxf(maxf(x0[b] - x1[a], x0[a] - x1[b]), 0.0)
				if gap <= rise_reach:
					reached.append(b)
					grew = true
					break

	for i: int in plats.size():
		_expect(reached.has(i),
			"breakable platform %d (surface %.0f, rise %.0f from ground) is reachable — "
				% [i, surf[i], ground - surf[i]]
			+ "either from the floor under a %.1f px ceiling or by a legal step" % ceiling)

	# ...and at least one of them must be a GROUND rung, or the whole set floats away
	# together the moment somebody retunes the jump.
	var from_ground: int = 0
	for i: int in plats.size():
		if ground - surf[i] <= ceiling:
			from_ground += 1
	_expect(from_ground >= 1,
		"at least one breakable ledge is reachable straight from the fight floor "
		+ "(otherwise the climb has no first rung)")
	_completed["breakable_platforms_are_climbable"] = true
