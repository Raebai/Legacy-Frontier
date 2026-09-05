# Run: godot --headless --path godot-project --script tools/slice_test_antechamber_sky.gd
#
# THE ENTRY AREA IS A ROOM, AND THE TOWER IS OUTSIDE THE WINDOW.
#
# ⚠ THIS SUITE USED TO PIN AN OUTDOOR FRAMING and the ruling it pinned is superseded,
# not deleted. What it asserted was: a colossal spire at least a quarter of the frame
# wide where it clears the TREELINE, and at least 100 px of clear SKY above that
# treeline for the moon and the cloud bands to live in. Both were correct for the room
# that existed — an outdoor night at the foot of a tower.
#
# Maker, 2026-09: *"make the lobby very different like a tavern vibe … not outside at a
# campfire but instead inside of a tavern"*. A tavern has no treeline and no sky, so the
# old numbers could only have been kept by lying about what they measured. The NEW
# ruling, which this file now pins, is the same four risks re-aimed at an interior:
#
#   1. THE ROOM IS ACTUALLY IN THE SCENE. `World._build_backdrop` is one call; a merge
#      that drops it leaves a town that still passes every other town suite.
#   2. NOTHING SCENERY SITS ON THE FIGHTER RUNG. This is the "I can't see the game" bug
#      `StageLayers` exists for, and the dust layer is a drawer in FRONT of the floor —
#      exactly the shape of thing that defaults to z 0.
#   3. THE CAMERA STILL FRAMES A ROOM. An interior only reads as one if the CEILING is
#      in shot and the WINDOW BAND is in shot. `limit_bottom` and `offset` are only
#      correct together (the offset asks for a centre the clamp refuses), so both are
#      asserted against the picture they buy — the same trap as before, new picture.
#   4. THE TOWER IS STILL IN THE ROOM, THROUGH THE GLASS. It is no longer allowed to be
#      a quarter of the frame — a silhouette that touches both jambs is a wall of stone,
#      not a view — so what is pinned now is that the great window is big enough to read
#      and that the spire is FRAMED BY it rather than filling or missing it.
#   5. THE WINDOW LIST IS ORDERED AND DISJOINT. `AntechamberBackdrop._draw_wall` paints
#      the wall as the GAPS BETWEEN consecutive openings. Out of order or overlapping,
#      a gap runs backwards, the band it should have painted is simply missing, and the
#      room has a hole in it that no other test can see.
#   6. LOW REALLY IS CHEAPER. A quality branch nobody measures is a quality branch that
#      quietly stops branching.
#
# ⚠ NO `get_visible_rect()` ANYWHERE IN HERE. Headless has no window and therefore no
# aspect: the root viewport reports a SQUARE 640x640, so any framing computed from it
# is a framing that does not exist on any device. The base viewport is a constant in
# `project.godot` (640x360, `aspect=expand`, so HEIGHT is the fixed edge) and that
# constant is what the arithmetic below uses.
#
# ⚠ TEST IDIOM (see tools/slice_test_loadout.gd). Failures accumulate on the MEMBER
# `_fails` and every test's last line records a COMPLETION SENTINEL, because a dead
# property read ABORTS the enclosing function and hands back a zero — which reads as
# "no failures" while verifying nothing. A test that dies half-way fails by ABSENCE.
extends SceneTree

const TOWN_SCENE: String = "res://scenes/Main.tscn"
const WORLD_SCRIPT: String = "res://scripts/World.gd"
const BACKDROP_SCRIPT: String = "res://scripts/ui/AntechamberBackdrop.gd"
## `project.godot`: 640x360 with `aspect=expand`. See the ⚠ above.
const BASE: Vector2 = Vector2(640.0, 360.0)
## The town camera, mirrored from `World._place_player`. Kept as literals rather than
## read off a live camera because the point is to catch the two numbers DRIFTING APART,
## and reading whatever the file currently says can never do that.
const CAM_ZOOM: float = 0.72
const CAM_OFFSET_Y: float = -96.0
const CAM_LIMIT_TOP: float = -420.0
const CAM_LIMIT_BOTTOM_OVER_GROUND: float = 18.0
## How much of the ceiling has to be in shot before the room reads as enclosed rather
## than as a wall with a dark strip over it. 40 px of a 500-px frame is 8% — modest, and
## the difference between "indoors" and "outdoors at night in front of a shed".
const MIN_CEILING_ON_SCREEN: float = 40.0
## The great window's minimum share of the frame width. It replaces the old "the spire
## is a quarter of the frame" rule, one level out: the OPENING now has to be big enough
## to be a view, and the spire has to be framed by it (see below).
const MIN_GREAT_WINDOW_SHARE: float = 0.15
## What fraction of the great window the spire may occupy. The floor is "you can see it
## is a tower"; the ceiling is the fault the tavern pass actually fixed — at the old
## base half-width the shaft measured 291 px across a 224 px opening and read as solid
## stone behind the glass.
const SPIRE_IN_WINDOW_MIN: float = 0.35
const SPIRE_IN_WINDOW_MAX: float = 0.90

const TESTS: Array[String] = [
	"the_town_actually_builds_the_room",
	"no_scenery_sits_on_the_fighter_rung",
	"the_camera_frames_a_room",
	"the_window_openings_are_ordered_and_disjoint",
	"low_quality_is_actually_cheaper",
	"the_tower_is_framed_by_the_great_window",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _town: Node = null


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_town_builds_room()
	_test_rungs()
	_test_camera_frame()
	_test_window_order()
	_test_low_is_cheaper()
	_test_tower_is_framed()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Antechamber-tavern tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("Antechamber-tavern tests: all PASS")
	quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(name: String) -> void:
	_completed[name] = true


## Built ONCE and cached. `World._ready` spawns townspeople, dummies and hero bodies;
## instantiating the town per test would spawn three of everything.
func _town_node() -> Node:
	if _town != null and is_instance_valid(_town):
		return _town
	var packed: PackedScene = load(TOWN_SCENE)
	if packed == null:
		return null
	_town = packed.instantiate()
	root.add_child(_town)
	return _town


func _backdrop_in(from: Node) -> Node2D:
	var s: Script = from.get_script() as Script
	if s != null and s.resource_path == BACKDROP_SCRIPT:
		return from as Node2D
	for c: Node in from.get_children():
		var found: Node2D = _backdrop_in(c)
		if found != null:
			return found
	return null


## A freshly built backdrop, off the town, so a test can force `_low` without touching
## the one the room is using.
func _fresh_backdrop(low: bool) -> Node2D:
	var k: Dictionary = (load(WORLD_SCRIPT) as GDScript).get_script_constant_map()
	var script: GDScript = load(BACKDROP_SCRIPT) as GDScript
	var b: Node2D = script.new()
	root.add_child(b)
	b.call("build", float(k["TOWN_WIDTH"]), float(k["GROUND_Y"]), float(k["TOWER_X"]),
		Color(0.105, 0.118, 0.235), Color(0.62, 0.70, 1.0))
	if low:
		b.set("_low", true)
		b.call("reseed")
	return b


# ---------------------------------------------------------------------- 1 + 2
func _test_town_builds_room() -> void:
	var town: Node = _town_node()
	_expect(town != null, "the town scene loads")
	if town == null:
		return  # deliberately NOT completed
	var b: Node2D = _backdrop_in(town)
	_expect(b != null,
		("the town builds an AntechamberBackdrop — without it the room in front of an "
		+ "infinite tower is an empty gradient"))
	if b == null:
		return  # deliberately NOT completed
	_expect((b.get("_windows") as Array).size() > 0,
		"the wall has window openings — they are the only thing outside is seen through")
	_expect((b.get("_bottles") as Array).size() > 0, "the bar's shelf has bottles on it")
	_expect((b.get("_haze") as Array).size() > 0, "there is haze drifting in the lamp band")
	_expect(b.get("_dust") != null, "the foreground dust layer exists")
	_completes("the_town_actually_builds_the_room")


## THE `StageLayers` RULE, applied to the two nodes this pass owns. Fighters own z 0
## and nothing that is scenery may ever share it — the maker played a build where three
## drawers defaulted to 0 and reported that he could not see the game.
func _test_rungs() -> void:
	var town: Node = _town_node()
	var b: Node2D = _backdrop_in(town) if town != null else null
	if b == null:
		return  # deliberately NOT completed
	_expect(b.z_index == StageLayers.MOUNTAIN,
		"the room shell parks on MOUNTAIN (%d), got %d" % [StageLayers.MOUNTAIN, b.z_index])
	_expect(not b.z_as_relative,
		"...absolutely, so a parent's own z cannot push it onto another rung")
	var dust: Node2D = b.get("_dust") as Node2D
	_expect(dust != null and dust.z_index == StageLayers.DEBRIS,
		"the dust parks on DEBRIS (%d) — in front of the floor, behind every fighter"
		% StageLayers.DEBRIS)
	_expect(dust != null and dust.z_index < StageLayers.FIGHTER,
		"...and therefore never on the fighter rung, which is the whole rule")
	_completes("no_scenery_sits_on_the_fighter_rung")


# -------------------------------------------------------------------------- 3
## ⚠ THE OFFSET DOES NOT DECIDE THIS FRAME, THE CLAMP DOES, and that is the entire
## reason this test exists. At 0.72 zoom the viewport is 500 world px tall, so the
## lowest legal camera centre is `limit_bottom - 250`. The requested centre
## (`GROUND_Y + offset`) is BELOW that and is thrown away — meaning `limit_bottom` alone
## chooses what you see, and raising the offset without lowering the limit does nothing
## at all. Both numbers are asserted together, against the room they buy.
func _test_camera_frame() -> void:
	var k: Dictionary = (load(WORLD_SCRIPT) as GDScript).get_script_constant_map()
	var bk: Dictionary = (load(BACKDROP_SCRIPT) as GDScript).get_script_constant_map()
	var ground: float = float(k["GROUND_Y"])
	var view_h: float = BASE.y / CAM_ZOOM
	var limit_bottom: float = ground + CAM_LIMIT_BOTTOM_OVER_GROUND
	var centre: float = clampf(ground + CAM_OFFSET_Y,
		CAM_LIMIT_TOP + view_h * 0.5, limit_bottom - view_h * 0.5)
	var top: float = centre - view_h * 0.5
	var bottom: float = centre + view_h * 0.5
	# The floor line must still be on screen — a "cinematic" frame that crops the boards
	# you are standing on is not cinematic, it is broken.
	_expect(bottom >= ground,
		"the floor line (%.0f) is still in frame (bottom %.0f)" % [ground, bottom])
	# ...and not by much. Everything below the floor line is opaque slab.
	_expect(bottom - ground <= 40.0,
		("no more than 40 px of the frame is spent below the floor line, got %.0f — "
		+ "that budget belongs to the room") % (bottom - ground))
	# THE CEILING. This is the assertion that replaced "clear sky above the treeline",
	# and it is the same question asked of an interior: is the thing that defines the
	# space actually in shot?
	var ceil_y: float = float(bk["CEIL_Y"])
	_expect(ceil_y - top >= MIN_CEILING_ON_SCREEN,
		("%.0f px of ceiling and rafters are in frame (need %.0f) — below that the room "
		+ "stops reading as an interior and becomes a wall with a dark strip on it")
		% [ceil_y - top, MIN_CEILING_ON_SCREEN])
	# THE WINDOW BAND. The whole point of the wall is what is cut out of it, so the
	# openings have to be inside the frame with room to spare at both ends.
	var w_top: float = float(bk["WINDOW_TOP"])
	var w_bottom: float = float(bk["WINDOW_BOTTOM"])
	_expect(w_top > top + 20.0,
		"the window heads (%.0f) sit clear of the frame's top edge (%.0f)" % [w_top, top])
	_expect(w_bottom < ground - 40.0,
		("the window sills (%.0f) sit clear of the floor (%.0f) — a window that meets "
		+ "the boards is a door") % [w_bottom, ground])
	# The tie-beam must sit BELOW the frame top, or the lamps hang from off-screen.
	_expect(ceil_y + float(bk["BEAM_H"]) < w_top,
		"the tie-beam clears the window heads (%.0f vs %.0f)"
		% [ceil_y + float(bk["BEAM_H"]), w_top])
	_completes("the_camera_frames_a_room")


# -------------------------------------------------------------------------- 4
## `_draw_wall` paints the wall as the GAPS between consecutive openings. That is only
## a list of gaps if the openings are sorted and do not overlap — otherwise a gap runs
## backwards, its band is silently skipped, and the room has an unpainted hole in it
## that every other suite in the project is blind to.
func _test_window_order() -> void:
	var b: Node2D = _fresh_backdrop(false)
	var wins: Array = b.get("_windows")
	_expect(wins.size() >= 2,
		"there is more than one window — one hole in a long wall is a porthole, not a hall")
	var prev_end: float = -INF
	var same_band: bool = true
	var band_y: float = -INF
	for i: int in wins.size():
		var w: Rect2 = wins[i]
		_expect(w.position.x >= prev_end,
			("window %d starts at %.0f, before the previous one ended at %.0f — the wall "
			+ "bands are painted between them and this makes one of them run backwards")
			% [i, w.position.x, prev_end])
		prev_end = w.end.x
		if i == 0:
			band_y = w.position.y
		elif not is_equal_approx(w.position.y, band_y) or not is_equal_approx(
				w.size.y, (wins[0] as Rect2).size.y):
			same_band = false
	_expect(same_band,
		("every window shares one y band — the wall subtraction in `_draw_wall` is three "
		+ "rectangles only because they do, and is a clipping problem if they stop"))
	root.remove_child(b)
	b.queue_free()
	_completes("the_window_openings_are_ordered_and_disjoint")


# -------------------------------------------------------------------------- 5
## Every seeded count has to drop on LOW. `build()` reads the LIVE quality, so the
## override lands after it and `reseed()` follows — see the note on that function for
## why measuring without the reseed reports that LOW costs the same as HIGH.
func _test_low_is_cheaper() -> void:
	var counts: Dictionary = {}
	for low: bool in [false, true]:
		var b: Node2D = _fresh_backdrop(low)
		var dust: Node = b.get("_dust")
		counts[low] = {
			"bottles": (b.get("_bottles") as Array).size(),
			"haze": (b.get("_haze") as Array).size(),
			"dust": int(dust.get("count")) if dust != null else 0,
		}
		# Force the paint at this setting: `_draw` branches on `_low`, so the cheap path
		# is only exercised if something actually asks for it. A bad index in there is a
		# SCRIPT ERROR here rather than a black room on a phone.
		b.call("_process", 1.0)
		b.queue_redraw()
		root.remove_child(b)
		b.queue_free()
	for key: String in ["bottles", "haze", "dust"]:
		var hi: int = int((counts[false] as Dictionary)[key])
		var lo: int = int((counts[true] as Dictionary)[key])
		_expect(hi > 0, "HIGH draws some `%s` at all (got %d)" % [key, hi])
		_expect(lo < hi, "LOW cuts `%s`: %d -> %d" % [key, hi, lo])
		_expect(lo > 0, "...but does not delete it — LOW is cheaper, not empty (%s)" % key)
	_completes("low_quality_is_actually_cheaper")


# -------------------------------------------------------------------------- 6
## THE NUMBER THE WHOLE ASK REDUCES TO, ONE LEVEL OUT FROM WHERE IT USED TO BE.
##
## The old rule was "the spire is at least a quarter of the frame". Inside a tavern that
## rule would demand a shaft wider than any window in the room, which is how the outdoor
## version of this backdrop ended up drawing 291 px of stone across a 224 px opening —
## a silhouette that touches both jambs has no distance and reads as masonry, not as the
## tower you are about to climb. So what is pinned now is the FRAMING: an opening big
## enough to be a view, and a spire that sits inside it with air on both sides.
func _test_tower_is_framed() -> void:
	var k: Dictionary = (load(WORLD_SCRIPT) as GDScript).get_script_constant_map()
	var ground: float = float(k["GROUND_Y"])
	var tower_x: float = float(k["TOWER_X"])
	var b: Node2D = _fresh_backdrop(false)
	var bk: Dictionary = (load(BACKDROP_SCRIPT) as GDScript).get_script_constant_map()
	var view_w: float = BASE.x / CAM_ZOOM
	# The great window is the widest of them, and it is the one the spire stands in.
	var great: Rect2 = Rect2()
	for w: Variant in b.get("_windows"):
		var r: Rect2 = w
		if r.size.x > great.size.x:
			great = r
	_expect(great.size.x / view_w >= MIN_GREAT_WINDOW_SHARE,
		("the great window is at least %.0f%% of the frame, got %.0f%% (%.0f px of %.0f) "
		+ "— below that it is a porthole and the tower is a detail")
		% [MIN_GREAT_WINDOW_SHARE * 100.0, great.size.x / view_w * 100.0,
			great.size.x, view_w])
	_expect(absf((great.position.x + great.size.x * 0.5) - tower_x) <= 80.0,
		("the great window is on the tower door's own axis (window centre %.0f, door "
		+ "%.0f) — the way out and the view of what you are climbing are one place")
		% [great.position.x + great.size.x * 0.5, tower_x])
	# The spire, measured across the window's mid-height.
	var mid_y: float = great.position.y + great.size.y * 0.5
	var spire_half: float = float(b.call("_spire_half_at", mid_y))
	var spire_x: float = tower_x + float(bk["SPIRE_DX"])
	var share: float = (spire_half * 2.0) / great.size.x
	_expect(share >= SPIRE_IN_WINDOW_MIN and share <= SPIRE_IN_WINDOW_MAX,
		("the spire fills %.0f%% of the great window (want %.0f..%.0f%%) — under it and "
		+ "there is no tower out there, over it and the glass is a wall of stone")
		% [share * 100.0, SPIRE_IN_WINDOW_MIN * 100.0, SPIRE_IN_WINDOW_MAX * 100.0])
	# ...and it has to be BEHIND the opening, not next to it.
	var overlap: float = minf(spire_x + spire_half, great.end.x) \
		- maxf(spire_x - spire_half, great.position.x)
	_expect(overlap >= spire_half * 2.0 * 0.8,
		("%.0f px of the spire's %.0f px width lands inside the opening — a tower drawn "
		+ "beside the window is painted straight over by the wall")
		% [overlap, spire_half * 2.0])
	# It has to keep NARROWING all the way up, or it is a wall rather than a tower.
	var lo: float = float(b.call("_spire_half_at", ground))
	var mid: float = float(b.call("_spire_half_at", ground - 600.0))
	var hi: float = float(b.call("_spire_half_at", ground - 1400.0))
	_expect(lo > mid and mid > hi,
		"the taper is monotonic: %.0f > %.0f > %.0f" % [lo, mid, hi])
	# And it must not terminate anywhere the camera can look. `limit_top` is -420.
	_expect(float(bk["SPIRE_TOP_Y"]) < CAM_LIMIT_TOP,
		"the drawn top (%s) is above the camera's ceiling (%.0f) — the tower never ends on screen"
		% [bk["SPIRE_TOP_Y"], CAM_LIMIT_TOP])
	root.remove_child(b)
	b.queue_free()
	_completes("the_tower_is_framed_by_the_great_window")
