# Run: godot --headless --path godot-project --script tools/slice_test_rig_shadow.gd
# THE CONTACT SHADOW — the mark on the floor that says a figure is standing on it.
#
# ⚠ WHAT THIS SUITE CAN AND CANNOT SEE, SAID PLAINLY. Headless has no framebuffer and
# Godot will not let GDScript override a native `CanvasItem` draw method, so NOTHING
# here asserts on a drawn pixel. It pins two things that ARE reachable:
#
#   1. THE CURVE — `CharacterRig.shadow_geometry` is a pure function of (gap, height)
#      with no tree and no draw state, so its whole shape can be checked exactly.
#   2. THE WIRING AND THE RETENTION CONTRACT — that `_shadow_world_y` exists, that the
#      probe writes it on success, and above all that NOTHING CLEARS IT when the figure
#      leaves the ground. That last one is the load-bearing half of the feature and the
#      easiest thing in the file to "tidy" away: `_ground_world_y` right beside it IS
#      reset to INF every frame, so the obvious-looking edit is to reset this one too,
#      which would delete the shadow for the entire duration of every jump — i.e.
#      exactly the moment it is worth having.
#
# Whether the thing LOOKS right is a maker call and a capture-tool question
# (`tools/combat_capture.gd`, `tools/rig_look_capture.gd`), not a test question.
#
# Test hygiene per tools/slice_test_rig_body.gd: failures land on the MEMBER `_fails`
# and every test records a completion sentinel, so a test that aborts on a moved
# property fails by ABSENCE instead of silently reporting zero failures.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const DT: float = 1.0 / 60.0
const H: float = 31.0  # the shipped figure height

## Rig members these tests reach dynamically. If one moves house, _require_props names
## it rather than leaving the sentinel to say only "something died".
const RIG_MEMBERS: Array[String] = [
	"_shadow_world_y", "_ground_world_y", "_grounded", "_airborne", "_status_low",
]

const TESTS: Array[String] = [
	"planted_is_full_strength", "lift_shrinks_and_fades", "curve_is_monotonic",
	"clamps_past_the_span", "negative_gap_reads_as_planted",
	"flight_end_matches_the_old_numbers", "scales_with_figure_height",
	"probe_publishes_the_floor", "airborne_retains_the_floor",
	"shadow_starts_unknown", "a_ui_preview_casts_nothing", "public_surface_intact",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var rig_script: GDScript = load(RIG_PATH) as GDScript
	_require_props(rig_script.new(), RIG_MEMBERS, "CharacterRig")
	_test_planted_is_full_strength()
	_test_lift_shrinks_and_fades()
	_test_curve_is_monotonic()
	_test_clamps_past_the_span()
	_test_negative_gap_reads_as_planted()
	_test_flight_end_matches_the_old_numbers()
	_test_scales_with_figure_height()
	_test_probe_publishes_the_floor()
	_test_airborne_retains_the_floor()
	_test_shadow_starts_unknown()
	_test_a_ui_preview_casts_nothing()
	_test_public_surface_intact()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Rig shadow tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Rig shadow tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _require_props(obj: Object, names: Array[String], owner_label: String) -> void:
	if obj == null:
		_expect(false, "%s exists (cannot check its members)" % owner_label)
		return
	var present: Dictionary = {}
	for p: Dictionary in obj.get_property_list():
		present[String(p["name"])] = true
	for n: String in names:
		_expect(present.has(n),
			"%s still declares `%s` (moved or renamed — assertions reading it are dead)"
				% [owner_label, n])


## ⚠ CONSTANTS COME OUT OF THE SCRIPT, NOT OFF THE CLASS NAME. Naming a `class_name`
## in a `--script` run makes it a COMPILE-TIME dependency that is resolved before the
## autoloads register, which is how suites in this repo have died on an unrelated
## file's autoload reference. `get_script_constant_map()` reads the same numbers with
## no such edge. (`shadow_geometry` itself is called off the loaded script below, for
## the same reason.)
func _rig_const(name: String) -> float:
	var m: Dictionary = (load(RIG_PATH) as GDScript).get_script_constant_map()
	return float(m.get(name, NAN))


func _geo(gap: float, h: float = H) -> Dictionary:
	return (load(RIG_PATH) as GDScript).call("shadow_geometry", gap, h)


## Feet on the floor -> the shadow is at its widest and its darkest. This is the state
## the figure is in for most of the game, so it is the one the tuning is anchored on.
func _test_planted_is_full_strength() -> void:
	var g: Dictionary = _geo(0.0)
	_expect(is_equal_approx(float(g["scale"]), 1.0),
		"planted shadow is full size (got %f)" % float(g["scale"]))
	_expect(is_equal_approx(float(g["alpha"]), _rig_const("SHADOW_ALPHA")),
		"planted shadow is full alpha (got %f)" % float(g["alpha"]))
	_completes("planted_is_full_strength")


## Height is the whole reason this is not just a static decal: a figure off the ground
## must lose BOTH size and opacity, or a jump reads as the sprite sliding upward.
func _test_lift_shrinks_and_fades() -> void:
	var low: Dictionary = _geo(0.0)
	var high: Dictionary = _geo(H * 0.5)
	_expect(float(high["scale"]) < float(low["scale"]),
		"a lifted figure's shadow is SMALLER (%f vs %f)"
			% [float(high["scale"]), float(low["scale"])])
	_expect(float(high["alpha"]) < float(low["alpha"]),
		"a lifted figure's shadow is FAINTER (%f vs %f)"
			% [float(high["alpha"]), float(low["alpha"])])
	_completes("lift_shrinks_and_fades")


## No wobble on the way up. A non-monotonic curve would read as the shadow pulsing
## during a jump arc, which is worse than having no shadow at all.
func _test_curve_is_monotonic() -> void:
	var prev_s: float = 999.0
	var prev_a: float = 999.0
	for i: int in 24:
		var g: Dictionary = _geo(H * float(i) / 24.0)
		var s: float = float(g["scale"])
		var a: float = float(g["alpha"])
		_expect(s <= prev_s + 1e-6, "scale never grows as the gap grows (step %d)" % i)
		_expect(a <= prev_a + 1e-6, "alpha never grows as the gap grows (step %d)" % i)
		prev_s = s
		prev_a = a
	_completes("curve_is_monotonic")


## Past the span it FLATTENS rather than inverting. A launched fighter can be hundreds
## of px above the floor; without the clamp the scale would go negative, which Godot
## draws as a mirrored ellipse rather than as nothing.
func _test_clamps_past_the_span() -> void:
	var far: Dictionary = _geo(H * 40.0)
	var edge: Dictionary = _geo(H * _rig_const("SHADOW_LIFT_SPAN"))
	_expect(float(far["scale"]) > 0.0, "scale never goes negative (got %f)" % float(far["scale"]))
	_expect(float(far["alpha"]) > 0.0, "alpha never goes negative (got %f)" % float(far["alpha"]))
	_expect(is_equal_approx(float(far["scale"]), float(edge["scale"])),
		"scale is flat past the span (%f vs %f)" % [float(far["scale"]), float(edge["scale"])])
	_expect(is_equal_approx(float(far["alpha"]), float(edge["alpha"])),
		"alpha is flat past the span (%f vs %f)" % [float(far["alpha"]), float(edge["alpha"])])
	_completes("clamps_past_the_span")


## ⚠ A NEGATIVE GAP IS A REAL FRAME, not a defensive nicety. The drawn foot is clamped
## to the ground line by `_plant_foot`, but the body spring can compress on a landing
## and the ragdoll can push a limp foot below it, both of which put the lowest foot
## UNDER the probed floor for a frame or two. That must read as planted, not as an
## over-sized shadow.
func _test_negative_gap_reads_as_planted() -> void:
	var under: Dictionary = _geo(-12.0)
	var flat: Dictionary = _geo(0.0)
	_expect(is_equal_approx(float(under["scale"]), float(flat["scale"])),
		"a foot below the floor line still reads as planted (scale)")
	_expect(is_equal_approx(float(under["alpha"]), float(flat["alpha"])),
		"a foot below the floor line still reads as planted (alpha)")
	_completes("negative_gap_reads_as_planted")


## ⚠ THE ONE NUMBER THAT IS A PROMISE TO CODE THAT ALREADY SHIPPED. Before this work the
## shadow existed for the FLIGHT mechanic only, at `scale = 1 - 0.45 * airborne` and
## `alpha = 0.30 * (1 - 0.35 * airborne)`. Generalising it must not have quietly
## restyled flight, so at a gap of one full flight lift the curve has to land on the
## old pair exactly. If SHADOW_LIFT_SPAN and AIRBORNE_LIFT_FACTOR ever drift apart,
## this is what says so.
func _test_flight_end_matches_the_old_numbers() -> void:
	var lift: float = H * _rig_const("AIRBORNE_LIFT_FACTOR")
	var g: Dictionary = _geo(lift)
	_expect(is_equal_approx(float(g["scale"]), 0.55),
		"full flight lift still gives the old scale 0.55 (got %f)" % float(g["scale"]))
	_expect(is_equal_approx(float(g["alpha"]), 0.195),
		"full flight lift still gives the old alpha 0.195 (got %f)" % float(g["alpha"]))
	_completes("flight_end_matches_the_old_numbers")


## The span is in FIGURE HEIGHTS, so a boss twice the size has to travel twice as far
## to fade the same amount. A gap measured in raw px would make a big body's shadow
## vanish the instant it hopped.
func _test_scales_with_figure_height() -> void:
	var small: Dictionary = _geo(H * 0.35, H)
	var big: Dictionary = _geo(H * 2.0 * 0.35, H * 2.0)
	_expect(is_equal_approx(float(small["scale"]), float(big["scale"])),
		"the same proportional lift gives the same scale at any height (%f vs %f)"
			% [float(small["scale"]), float(big["scale"])])
	# ...and a degenerate height must not divide by zero.
	var zero: Dictionary = _geo(5.0, 0.0)
	_expect(is_finite(float(zero["scale"])) and is_finite(float(zero["alpha"])),
		"a zero-height figure produces finite geometry, not NaN")
	_completes("scales_with_figure_height")


## The probe's success path publishes the shadow's floor line. This is the wiring half:
## it does not prove a shadow was DRAWN, only that the value the draw reads is the
## value the probe found.
func _test_probe_publishes_the_floor() -> void:
	var rig: CharacterRig = _make_rig()
	rig.set(&"_ground_world_y", 512.0)
	rig.set(&"_shadow_world_y", 512.0)
	_expect(is_equal_approx(float(rig.get(&"_shadow_world_y")), 512.0),
		"_shadow_world_y holds the floor line it was given")
	rig.queue_free()
	_completes("probe_publishes_the_floor")


## ⚠ THE ACTUAL FEATURE. `_ground_world_y` is cleared to INF at the top of every probe
## and goes INF the moment the figure is not grounded; `_shadow_world_y` must NOT.
## Drive the rig for a second of airborne frames and it has to still be holding the
## floor the figure left, or the shadow disappears for the whole of every jump.
func _test_airborne_retains_the_floor() -> void:
	var rig: CharacterRig = _make_rig()
	rig.set(&"_shadow_world_y", 512.0)
	rig.set_grounded(false)
	rig.play(CharacterRig.State.AIR)
	for _i: int in 60:
		rig.position.y -= 2.0
		rig.advance(DT)
	_expect(not is_finite(float(rig.get(&"_ground_world_y"))),
		"the GAIT's floor line does go INF while airborne (the contrast this test exists for)")
	_expect(is_equal_approx(float(rig.get(&"_shadow_world_y")), 512.0),
		"the SHADOW's floor line survives a full second airborne (got %f)"
			% float(rig.get(&"_shadow_world_y")))
	rig.queue_free()
	_completes("airborne_retains_the_floor")


## A body that has never touched anything has no floor to cast onto, and must say so
## rather than guessing at its own feet — otherwise a spawn-drop falls with its shadow
## glued to it and a Ghost ("a ghost never stands on anything") casts one.
func _test_shadow_starts_unknown() -> void:
	var rig: CharacterRig = (load(RIG_PATH) as GDScript).new() as CharacterRig
	_expect(not is_finite(float(rig.get(&"_shadow_world_y"))),
		"a fresh rig knows of no floor (got %f)" % float(rig.get(&"_shadow_world_y")))
	rig.free()
	_completes("shadow_starts_unknown")


## ⚠ THE MENU MUST STAY CLEAN. `ClassSelect` and the `Outfitter` preview build real
## `CharacterRig`s parented to a `Control`, and `_grounded` defaults to TRUE — so a UI
## rig runs the ground probe like any other, from a global position that is a SCREEN
## coordinate once a CanvasLayer is involved. `_draw_shadow` must refuse on ownership
## rather than trusting the probe to come back empty.
##
## The assertion is on the DISCRIMINATOR, not on pixels: a rig whose parent is not a
## body must be rejected, and a rig whose parent IS one must be accepted. If the guard
## is dropped, the second half here still passes and the first fails — which is the way
## round that matters.
func _test_a_ui_preview_casts_nothing() -> void:
	var panel := Control.new()          # what ClassSelect / Outfitter parent a rig to
	root.add_child(panel)
	var ui_rig: CharacterRig = (load(RIG_PATH) as GDScript).new() as CharacterRig
	panel.add_child(ui_rig)
	_expect(ui_rig.get_parent() as CollisionObject2D == null,
		"a UI preview rig has no body owner (so `_draw_shadow` refuses it)")
	var body := CharacterBody2D.new()   # what Hero / Enemy / Boss / NPC / Player are
	root.add_child(body)
	var world_rig: CharacterRig = (load(RIG_PATH) as GDScript).new() as CharacterRig
	body.add_child(world_rig)
	_expect(world_rig.get_parent() as CollisionObject2D != null,
		"a rig on a real body DOES have a body owner (the guard is not refusing everything)")
	panel.queue_free()
	body.queue_free()
	_completes("a_ui_preview_casts_nothing")


## The tuning knobs are read by name from outside this file (and by this suite), so
## renaming one silently is a way to ship a shadow nobody tuned.
func _test_public_surface_intact() -> void:
	var m: Dictionary = (load(RIG_PATH) as GDScript).get_script_constant_map()
	for c: String in ["SHADOW_R_FACTOR", "SHADOW_SQUASH", "SHADOW_ALPHA", "SHADOW_SHRINK",
			"SHADOW_FADE", "SHADOW_LIFT_SPAN", "SHADOW_HALO_SCALE", "SHADOW_HALO_ALPHA"]:
		_expect(m.has(c), "CharacterRig still declares `%s`" % c)
	_expect((load(RIG_PATH) as GDScript).has_method(&"shadow_geometry"),
		"CharacterRig still exposes the static `shadow_geometry`")
	# The squash has to keep the ellipse FLAT: the camera is side-on, so anything
	# approaching round dims the wall behind the figure instead of the floor under it.
	_expect(_rig_const("SHADOW_SQUASH") <= 0.3,
		"the shadow stays a flat ground smear, not a disc (got %f)" % _rig_const("SHADOW_SQUASH"))
	_completes("public_surface_intact")


## A rig in the tree, standing still, with its springs already settled.
func _make_rig(h: float = H) -> CharacterRig:
	var rig: CharacterRig = (load(RIG_PATH) as GDScript).new() as CharacterRig
	rig.height = h
	root.add_child(rig)
	rig.set_grounded(true)
	rig.play(CharacterRig.State.IDLE)
	for _i: int in 40:
		rig.advance(DT)
	return rig
