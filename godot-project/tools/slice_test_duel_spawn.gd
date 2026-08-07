# Run: godot --headless --path godot-project --script tools/slice_test_duel_spawn.gd
#
# NOBODY MAY START THE FIGHT STANDING INSIDE A BLOCK.
#
# Maker, during a live playtest: *"when bot fight happen they start within the boxes
# which is a wierd bug as wel"*. It was real and the arithmetic was exact:
#
#     VersusArena.COVER_POINTS[0].x = 470, a DestructibleTerrain is 64 wide
#         -> the left cover block spans 438 .. 502
#     BotMatch mirrors its fighters about FLOOR_CENTRE_X (720) +/- SPAWN_SPREAD (280)
#         -> the LEFT fighter stands at 440
#
# Two pixels inside the cover. The right pair (spawn 1000, block 1148..1212) happened
# to miss by 148, which is the only reason one fighter looked fine.
#
# THE TWO FACTS LIVED IN DIFFERENT FILES AND NEVER MET. The stage authors its cover
# in `_ready`; `BotMatch` re-seats the fighters afterwards. Nothing reconciled them,
# so the overlap was not a mistake anybody made — it was a sum nobody computed.
#
# This suite computes it. It checks the pure displacement helper, and then checks the
# REAL numbers the two files actually ship, so the next person who nudges either a
# cover point or the spawn spread gets a red build instead of a fighter in a box.
#
# ⚠ AND IT ASSERTS THE BUG WAS REAL. `_test_the_bug_was_real` re-derives the raw
# authored overlap. Without it, a future refactor that quietly moved a cover point
# would make every other test here pass while testing nothing at all.
#
# ⚠ LOADED BY PATH, NEVER BY `class_name`. `VersusArena` / `BotMatch` /
# `DestructibleTerrain` all name the Sfx / Juice / CombatVfx autoloads, and naming
# the class here would compile that whole chain at THIS script's parse time — before
# the main loop has registered a single autoload. Same reason every capture tool in
# this project documents.
#
# ⚠ NEVER `failed += _test_x()`. A dead property read aborts the enclosing function
# and hands back the return type's zero, which reads as "no failures". Failures
# accumulate on `_fails` and every test records a COMPLETION SENTINEL, so a test that
# aborts half-way fails the suite by absence.
extends SceneTree

const ARENA_PATH: String = "res://scripts/combat/VersusArena.gd"
const MATCH_PATH: String = "res://scripts/combat/BotMatch.gd"
const TERRAIN_PATH: String = "res://scripts/combat/DestructibleTerrain.gd"

## `DestructibleTerrain.block_size` is an `@export`, so its default is not in the
## script constant map and instantiating one would drag three autoloads in. The value
## is asserted against the source text in `_test_block_width_is_still_64` instead —
## if somebody re-sizes the cover, this suite says so rather than quietly measuring
## the wrong box.
const BLOCK_W: float = 64.0

const TESTS: Array[String] = [
	"block_width_is_still_64",
	"the_bug_was_real",
	"helper_leaves_distant_blocks_alone",
	"helper_pushes_the_short_way",
	"helper_clamps_onto_the_fight_floor",
	"helper_survives_a_block_exactly_on_a_spawn",
	"duel_footing_is_clear_of_every_block",
	"stage_own_spawns_are_clear_of_every_block",
	"the_duel_keeps_its_mirrored_footing",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}

var _arena: GDScript = null
var _match: GDScript = null
var _arena_k: Dictionary = {}
var _match_k: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_arena = load(ARENA_PATH) as GDScript
	_match = load(MATCH_PATH) as GDScript
	if _arena == null or _match == null:
		printerr("duel_spawn: FAIL — could not load VersusArena.gd / BotMatch.gd")
		printerr("duel spawn tests: 1 FAILED")
		quit(1)
		return true
	_arena_k = _arena.get_script_constant_map()
	_match_k = _match.get_script_constant_map()

	_test_block_width_is_still_64()
	_test_the_bug_was_real()
	_test_helper_leaves_distant_blocks_alone()
	_test_helper_pushes_the_short_way()
	_test_helper_clamps_onto_the_fight_floor()
	_test_helper_on_exact_spawn()
	_test_duel_footing_is_clear()
	_test_stage_own_spawns_are_clear()
	_test_mirrored_footing()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("duel_spawn: TEST DID NOT COMPLETE — %s (it aborted part-way)" % name)
	if _fails == 0:
		print("duel spawn tests: all PASS")
	else:
		printerr("duel spawn tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("duel_spawn: FAIL — %s" % what)


## Every fighter x this project ever stands somebody at on this stage.
func _duel_spawns() -> Array[float]:
	var centre: float = float(_match_k.get("FLOOR_CENTRE_X", 0.0))
	var spread: float = float(_match_k.get("SPAWN_SPREAD", 0.0))
	return [centre - spread, centre + spread]


## The resolved x of every cover block, given who is standing where.
func _resolved_cover(keepout: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for pt: Vector2 in (_arena_k.get("COVER_POINTS", []) as Array):
		out.append(float(_arena.call("cover_x_clear_of", pt.x, BLOCK_W, keepout)))
	return out


## Does a body standing at `spawn_x` intersect a block centred at `block_x`?
## Deliberately the NAIVE geometry — half a block plus half a body — rather than
## anything the production code shares, so this suite can disagree with it.
func _overlaps(block_x: float, spawn_x: float, body_half: float) -> bool:
	return absf(block_x - spawn_x) < BLOCK_W * 0.5 + body_half


# --------------------------------------------------------------------------- 1
## If the cover stops being 64 px wide, every number in this file is measuring the
## wrong box and must be re-derived rather than silently believed.
func _test_block_width_is_still_64() -> void:
	var text: String = FileAccess.get_file_as_string(TERRAIN_PATH)
	_expect(not text.is_empty(), "could not read DestructibleTerrain.gd")
	_expect(text.contains("block_size: Vector2 = Vector2(64, 64)"),
		"DestructibleTerrain.block_size is no longer 64x64 — re-derive BLOCK_W and "
		+ "the overlap numbers in this suite's header")
	_completed["block_width_is_still_64"] = true


# --------------------------------------------------------------------------- 2
## THE BUG, RESTATED AS ARITHMETIC. The authored cover point and the authored spawn
## really did overlap; this suite is not testing a hypothetical.
func _test_the_bug_was_real() -> void:
	var cover: Array = _arena_k.get("COVER_POINTS", []) as Array
	_expect(cover.size() >= 2, "the stage no longer authors two cover blocks")
	if cover.size() < 2:
		_completed["the_bug_was_real"] = true
		return
	var spawns: Array[float] = _duel_spawns()
	var raw_hit: bool = false
	for pt: Vector2 in cover:
		for sx: float in spawns:
			if _overlaps(pt.x, sx, 9.0):
				raw_hit = true
	_expect(raw_hit,
		"the RAW authored cover no longer overlaps a duel spawn, so this suite is "
		+ "guarding nothing. Either the authoring changed (fine — delete this test "
		+ "and say why) or the geometry moved and the rest of the file is stale.")
	_completed["the_bug_was_real"] = true


# --------------------------------------------------------------------------- 3
func _test_helper_leaves_distant_blocks_alone() -> void:
	# A block a long way from everybody must not move AT ALL. A displacement helper
	# that quietly re-centres the whole stage would pass every overlap test here.
	_expect(is_equal_approx(
		float(_arena.call("cover_x_clear_of", 800.0, BLOCK_W, [200.0, 1300.0] as Array[float])),
		800.0), "a block 500 px from the nearest spawn was moved")
	_expect(is_equal_approx(
		float(_arena.call("cover_x_clear_of", 800.0, BLOCK_W, [] as Array[float])),
		800.0), "an empty keep-out moved a block")
	_completed["helper_leaves_distant_blocks_alone"] = true


# --------------------------------------------------------------------------- 4
func _test_helper_pushes_the_short_way() -> void:
	var half: float = float(_arena_k.get("SPAWN_FOOTPRINT_HALF", 0.0))
	_expect(half > 0.0, "SPAWN_FOOTPRINT_HALF is missing or zero")
	var need: float = BLOCK_W * 0.5 + half
	# Block slightly RIGHT of the spawn -> pushed further right, never across.
	var right: float = float(_arena.call("cover_x_clear_of", 470.0, BLOCK_W, [440.0] as Array[float]))
	_expect(right > 440.0, "a block right of the spawn was pushed across it")
	_expect(is_equal_approx(right, 440.0 + need),
		"a displaced block should land exactly on the clearance, got %.1f" % right)
	# ...and mirrored.
	var left: float = float(_arena.call("cover_x_clear_of", 420.0, BLOCK_W, [440.0] as Array[float]))
	_expect(left < 440.0, "a block left of the spawn was pushed across it")
	_expect(is_equal_approx(left, 440.0 - need),
		"a displaced block should land exactly on the clearance, got %.1f" % left)
	_completed["helper_pushes_the_short_way"] = true


# --------------------------------------------------------------------------- 5
func _test_helper_clamps_onto_the_fight_floor() -> void:
	var lo: float = float(_arena_k.get("COVER_X_MIN", 0.0))
	var hi: float = float(_arena_k.get("COVER_X_MAX", 0.0))
	_expect(lo > 0.0 and hi > lo, "COVER_X_MIN / COVER_X_MAX are missing or crossed")
	# A spawn parked at the very edge would otherwise shove a block off the terrain,
	# and cover floating over a blast zone is worse than cover in the wrong place.
	_expect(float(_arena.call("cover_x_clear_of", 80.0, BLOCK_W, [90.0] as Array[float])) >= lo,
		"a block was pushed off the LEFT edge of the fight floor")
	_expect(float(_arena.call("cover_x_clear_of", 1360.0, BLOCK_W, [1350.0] as Array[float])) <= hi,
		"a block was pushed off the RIGHT edge of the fight floor")
	_completed["helper_clamps_onto_the_fight_floor"] = true


# --------------------------------------------------------------------------- 6
## A block centred EXACTLY on a spawn has no short way out. It must still move, and
## it must move the same way every time — both co-op peers build this stage
## independently and a coin-flip here would desync the cover.
func _test_helper_on_exact_spawn() -> void:
	var a: float = float(_arena.call("cover_x_clear_of", 500.0, BLOCK_W, [500.0] as Array[float]))
	var b: float = float(_arena.call("cover_x_clear_of", 500.0, BLOCK_W, [500.0] as Array[float]))
	_expect(not _overlaps(a, 500.0, 9.0), "a block centred on a spawn did not move")
	_expect(is_equal_approx(a, b), "the displacement is not deterministic")
	_completed["helper_survives_a_block_exactly_on_a_spawn"] = true


# --------------------------------------------------------------------------- 7
## THE ONE THAT ANSWERS THE MAKER. Real cover points, real duel footing, resolved
## through the real helper: nobody is in a box.
func _test_duel_footing_is_clear() -> void:
	var spawns: Array[float] = _duel_spawns()
	var blocks: Array[float] = _resolved_cover(spawns)
	_expect(not blocks.is_empty(), "the stage resolved no cover at all")
	for bx: float in blocks:
		for sx: float in spawns:
			_expect(not _overlaps(bx, sx, 9.0),
				"a duel fighter at x %.0f starts inside the cover block at x %.0f"
					% [sx, bx])
	_completed["duel_footing_is_clear_of_every_block"] = true


# --------------------------------------------------------------------------- 8
## The stage's OWN showcase spawns (a capture tool driving the showcase without
## BotMatch) get the same protection — `_spawn_keepout` falls back to them.
func _test_stage_own_spawns_are_clear() -> void:
	var a: Vector2 = _arena_k.get("SHOWCASE_SPAWN_A", Vector2.ZERO)
	var b: Vector2 = _arena_k.get("SHOWCASE_SPAWN_B", Vector2.ZERO)
	var p1: Vector2 = _arena_k.get("P1_SPAWN", Vector2.ZERO)
	for pair: Array in [[a.x, b.x] as Array[float], [p1.x] as Array[float]]:
		var keepout: Array[float] = []
		for v: float in pair:
			keepout.append(v)
		for bx: float in _resolved_cover(keepout):
			for sx: float in keepout:
				_expect(not _overlaps(bx, sx, 9.0),
					"a body at x %.0f starts inside the cover block at x %.0f"
						% [sx, bx])
	_completed["stage_own_spawns_are_clear_of_every_block"] = true


# --------------------------------------------------------------------------- 9
## AND THE FIX MUST NOT HAVE COST THE THING IT WAS PROTECTING. The duel's mirrored
## footing is the property the whole fix was shaped around — if a later hand "fixes"
## the overlap by nudging a fighter instead of a block, this goes red.
func _test_mirrored_footing() -> void:
	var centre: float = float(_match_k.get("FLOOR_CENTRE_X", 0.0))
	var spread: float = float(_match_k.get("SPAWN_SPREAD", 0.0))
	var spawns: Array[float] = _duel_spawns()
	_expect(spawns.size() == 2, "the duel no longer has exactly two spawns")
	if spawns.size() != 2:
		_completed["the_duel_keeps_its_mirrored_footing"] = true
		return
	_expect(is_equal_approx((spawns[0] + spawns[1]) * 0.5, centre),
		"the two fighters are no longer mirrored about the floor centre")
	_expect(is_equal_approx(spawns[1] - spawns[0], spread * 2.0),
		"the opening gap is no longer SPAWN_SPREAD * 2")
	_completed["the_duel_keeps_its_mirrored_footing"] = true
