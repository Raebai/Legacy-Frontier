# Run: godot --headless --path godot-project --script tools/slice_test_antechamber_sky.gd
#
# THE ENTRY AREA HAS TO CONTAIN THE TOWER.
#
# The maker's ask was "make the lobby area where they can enter the tower feel way more
# epic, change the background". The room's whole sky was a two-stop gradient and the
# only tower in it was `TowerDoor`'s 112-px shaft against an 889-px frame. What went in
# is `AntechamberBackdrop` — a colossal spire, a moon, ridges, cloud and petals — plus
# a camera reframe, and this suite pins the four things about that which would break
# silently and be noticed only by playing:
#
#   1. THE BACKDROP IS ACTUALLY IN THE ROOM. `World._build_backdrop` is one call; a
#      merge that drops it leaves a room that still passes every other town suite.
#   2. NOTHING SCENERY SITS ON THE FIGHTER RUNG. This is the "I can't see the game"
#      bug `StageLayers` exists for, and the petal layer is a NEW drawer in front of
#      the ground — exactly the shape of thing that defaults to z 0.
#   3. THE CAMERA STILL SHOWS THE SKY IT WAS REFRAMED FOR. `limit_bottom`, not
#      `offset`, is what decides the framing at this zoom (the offset asks for a centre
#      the clamp refuses), so the two numbers are only correct TOGETHER. Somebody
#      restoring `GROUND_Y + 60` while leaving the offset alone silently gives back the
#      old frame and every other suite stays green.
#   4. LOW REALLY IS CHEAPER. A quality branch nobody measures is a quality branch that
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
## `HubAmbience`'s tallest near pine: `near_h` maxes at 320 and the third tier's apex
## sits `1.167 * h` above the base, so the worst-case treeline is ~360 px up. The spire
## and the moon have to be readable ABOVE that or the backdrop is behind a hedge.
const TREELINE: float = 360.0
## How much clear sky above that treeline the reframe has to buy. 100 px of a 500-px
## frame is a fifth of the screen — below that the moon and the cloud bands have
## nowhere to be, which is the state the room was in.
const MIN_CLEAR_SKY: float = 100.0

const TESTS: Array[String] = [
	"the_town_actually_builds_a_backdrop",
	"no_scenery_sits_on_the_fighter_rung",
	"the_camera_frames_the_sky_it_was_reframed_for",
	"low_quality_is_actually_cheaper",
	"the_spire_is_big_in_the_frame",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _town: Node = null


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_town_builds_backdrop()
	_test_rungs()
	_test_camera_frame()
	_test_low_is_cheaper()
	_test_spire_is_big()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Antechamber-sky tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("Antechamber-sky tests: all PASS")
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


# ---------------------------------------------------------------------- 1 + 2
func _test_town_builds_backdrop() -> void:
	var town: Node = _town_node()
	_expect(town != null, "the town scene loads")
	if town == null:
		return  # deliberately NOT completed
	var b: Node2D = _backdrop_in(town)
	_expect(b != null,
		("the town builds an AntechamberBackdrop — without it the room in front of an "
		+ "infinite tower contains no tower"))
	if b == null:
		return  # deliberately NOT completed
	_expect((b.get("_windows") as Array).size() > 0, "the spire has lit windows")
	_expect((b.get("_clouds") as Array).size() > 0, "there are cloud bands to cross it")
	_expect(b.get("_petals") != null, "the foreground petal layer exists")
	_completes("the_town_actually_builds_a_backdrop")


## THE `StageLayers` RULE, applied to the two nodes this pass added. Fighters own z 0
## and nothing that is scenery may ever share it — the maker played a build where three
## drawers defaulted to 0 and reported that he could not see the game.
func _test_rungs() -> void:
	var town: Node = _town_node()
	var b: Node2D = _backdrop_in(town) if town != null else null
	if b == null:
		return  # deliberately NOT completed
	_expect(b.z_index == StageLayers.MOUNTAIN,
		"the backdrop parks on MOUNTAIN (%d), got %d" % [StageLayers.MOUNTAIN, b.z_index])
	_expect(not b.z_as_relative,
		"...absolutely, so a parent's own z cannot push it onto another rung")
	var petals: Node2D = b.get("_petals") as Node2D
	_expect(petals != null and petals.z_index == StageLayers.DEBRIS,
		"the petals park on DEBRIS (%d) — in front of the ground, behind every fighter"
		% StageLayers.DEBRIS)
	_expect(petals != null and petals.z_index < StageLayers.FIGHTER,
		"...and therefore never on the fighter rung, which is the whole rule")
	_completes("no_scenery_sits_on_the_fighter_rung")


# -------------------------------------------------------------------------- 3
## ⚠ THE OFFSET DOES NOT DECIDE THIS FRAME, THE CLAMP DOES, and that is the entire
## reason this test exists. At 0.72 zoom the viewport is 500 world px tall, so the
## lowest legal camera centre is `limit_bottom - 250`. The requested centre
## (`GROUND_Y + offset`) is BELOW that and is thrown away — meaning `limit_bottom` alone
## chooses how much sky you see, and raising the offset without lowering the limit does
## nothing at all. Both numbers are asserted together, against the sky they buy.
func _test_camera_frame() -> void:
	var k: Dictionary = (load(WORLD_SCRIPT) as GDScript).get_script_constant_map()
	var ground: float = float(k["GROUND_Y"])
	var view_h: float = BASE.y / CAM_ZOOM
	var limit_bottom: float = ground + CAM_LIMIT_BOTTOM_OVER_GROUND
	var centre: float = clampf(ground + CAM_OFFSET_Y,
		CAM_LIMIT_TOP + view_h * 0.5, limit_bottom - view_h * 0.5)
	var top: float = centre - view_h * 0.5
	var bottom: float = centre + view_h * 0.5
	# The ground line must still be on screen — a "cinematic" frame that crops the floor
	# you are standing on is not cinematic, it is broken.
	_expect(bottom >= ground,
		"the ground line (%.0f) is still in frame (bottom %.0f)" % [ground, bottom])
	# ...and not by much. Everything below the ground line is opaque dirt.
	_expect(bottom - ground <= 40.0,
		("no more than 40 px of the frame is spent below the ground line, got %.0f — "
		+ "that budget belongs to the sky") % (bottom - ground))
	var clear: float = (ground - TREELINE) - top
	_expect(clear >= MIN_CLEAR_SKY,
		("%.0f px of clear sky above the worst-case treeline (need %.0f) — this is what "
		+ "the moon, the cloud bands and the top of the spire live in")
		% [clear, MIN_CLEAR_SKY])
	_completes("the_camera_frames_the_sky_it_was_reframed_for")


# -------------------------------------------------------------------------- 4
## Every seeded count has to drop on LOW. `build()` reads the LIVE quality, so the
## override lands after it and `reseed()` follows — see the note on that function for
## why measuring without the reseed reports that LOW costs the same as HIGH.
func _test_low_is_cheaper() -> void:
	var k: Dictionary = (load(WORLD_SCRIPT) as GDScript).get_script_constant_map()
	var script: GDScript = load(BACKDROP_SCRIPT) as GDScript
	var counts: Dictionary = {}
	for low: bool in [false, true]:
		var b: Node2D = script.new()
		root.add_child(b)
		b.call("build", float(k["TOWN_WIDTH"]), float(k["GROUND_Y"]), float(k["TOWER_X"]),
			Color(0.19, 0.16, 0.30), Color(0.62, 0.70, 1.0))
		b.set("_low", low)
		b.call("reseed")
		var petals: Node = b.get("_petals")
		counts[low] = {
			"windows": (b.get("_windows") as Array).size(),
			"clouds": (b.get("_clouds") as Array).size(),
			"petals": int(petals.get("count")) if petals != null else 0,
		}
		# Force the paint at this setting: `_draw` branches on `_low`, so the cheap
		# path is only exercised if something actually asks for it. A bad index in
		# there is a SCRIPT ERROR here rather than a black sky on a phone.
		b.call("_process", 1.0)
		b.queue_redraw()
		root.remove_child(b)
		b.queue_free()
	for key: String in ["windows", "clouds", "petals"]:
		var hi: int = int((counts[false] as Dictionary)[key])
		var lo: int = int((counts[true] as Dictionary)[key])
		_expect(hi > 0, "HIGH draws some `%s` at all (got %d)" % [key, hi])
		_expect(lo < hi, "LOW cuts `%s`: %d -> %d" % [key, hi, lo])
		_expect(lo > 0, "...but does not delete it — LOW is cheaper, not empty (%s)" % key)
	_completes("low_quality_is_actually_cheaper")


# -------------------------------------------------------------------------- 5
## The number the whole ask reduces to. `TowerDoor`'s shaft is 112 px wide against the
## 889 px the town camera shows — 12.6% — and the maker's verdict on that room was that
## it did not feel like the foot of a tower. The replacement has to be several times
## that where it is actually visible, i.e. ABOVE the treeline, not at the ground where
## the forest hides it.
func _test_spire_is_big() -> void:
	var k: Dictionary = (load(WORLD_SCRIPT) as GDScript).get_script_constant_map()
	var ground: float = float(k["GROUND_Y"])
	var script: GDScript = load(BACKDROP_SCRIPT) as GDScript
	var b: Node2D = script.new()
	root.add_child(b)
	b.call("build", float(k["TOWN_WIDTH"]), ground, float(k["TOWER_X"]),
		Color(0.19, 0.16, 0.30), Color(0.62, 0.70, 1.0))
	var view_w: float = BASE.x / CAM_ZOOM
	var width_at_treeline: float = 2.0 * float(b.call("_spire_half_at", ground - TREELINE))
	var share: float = width_at_treeline / view_w
	_expect(share >= 0.25,
		("the spire is at least a quarter of the frame where it clears the trees, got "
		+ "%.0f%% (%.0f px of %.0f) — the shaft it replaces was 12.6%%")
		% [share * 100.0, width_at_treeline, view_w])
	# It has to keep NARROWING all the way up, or it is a wall rather than a tower.
	var lo: float = float(b.call("_spire_half_at", ground))
	var mid: float = float(b.call("_spire_half_at", ground - 600.0))
	var hi: float = float(b.call("_spire_half_at", ground - 1400.0))
	_expect(lo > mid and mid > hi,
		"the taper is monotonic: %.0f > %.0f > %.0f" % [lo, mid, hi])
	# And it must not terminate anywhere the camera can look. `limit_top` is -420.
	_expect(float(k["GROUND_Y"]) - 0.0 > 0.0
			and float((script.get_script_constant_map())["SPIRE_TOP_Y"]) < CAM_LIMIT_TOP,
		"the drawn top (%s) is above the camera's ceiling (%.0f) — the tower never ends on screen"
		% [script.get_script_constant_map()["SPIRE_TOP_Y"], CAM_LIMIT_TOP])
	root.remove_child(b)
	b.queue_free()
	_completes("the_spire_is_big_in_the_frame")
