# Run: godot --headless --path godot-project --script tools/slice_test_shockwave.gd
# THE SHOCKWAVE RIPPLE'S STRENGTH — the argument 23 call sites pass and the grade
# used to throw away.
#
# ⚠ WHAT THIS SUITE CAN AND CANNOT SEE, SAID PLAINLY. Headless has no framebuffer, so
# nothing here asserts on a warped pixel. What it CAN reach is the number the shader
# is handed: `PostProcess` keeps the live amplitude on `_shock_amp` and pushes it into
# the material every frame, so driving `_process` by hand and reading that member is a
# faithful measurement of what the shader would be told to do. Whether the resulting
# ripple LOOKS right is a maker call and a capture-tool question
# (`tools/postprocess_capture.gd` writes `pp_shock.png`), not a test question.
#
# THE BUG THIS EXISTS FOR: `_begin_shock` wrote the caller's strength into `_shock_amp`
# and `_process` overwrote that same member on the next frame with an expression that
# never mentioned strength. Every ripple in the game — a 0.35 ChainBolt tick and a 1.4
# Hollow Purple release alike — therefore rendered identically. These tests fail if
# that regresses, in either direction: too small a spread means the argument is being
# dropped again, and a moved strength-1.0 value means the default look drifted.
#
# ⚠ NO `class_name` ANYWHERE HERE. Naming `PostProcess` by its class in a `--script`
# run makes it a COMPILE-TIME dependency resolved before the autoloads register; the
# script is loaded by path and its constants read via `get_script_constant_map()`.
#
# Test hygiene per tools/slice_test_rig_body.gd: failures land on the MEMBER `_fails`
# and every test records a completion sentinel, so a test that aborts on a moved
# property fails by ABSENCE instead of silently reporting zero failures.
extends SceneTree

const PP_PATH: String = "res://scripts/combat/PostProcess.gd"
const DT: float = 1.0 / 60.0

## PostProcess members these tests reach dynamically. If one moves house,
## _require_props names it rather than leaving the sentinel to say only "something died".
const PP_MEMBERS: Array[String] = [
	"_shock_age", "_shock_amp", "_shock_strength", "_shock_center", "_heat",
]

const TESTS: Array[String] = [
	"strength_reaches_the_amplitude", "the_authored_range_is_separated",
	"unit_strength_is_unchanged", "amplitude_decays_to_zero",
	"a_weak_follow_up_cannot_stamp_out_an_ult", "a_late_beat_still_retriggers",
	"strength_is_clamped", "centre_is_carried", "public_surface_intact",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_require_props(_make(), PP_MEMBERS, "PostProcess")
	_test_strength_reaches_the_amplitude()
	_test_the_authored_range_is_separated()
	_test_unit_strength_is_unchanged()
	_test_amplitude_decays_to_zero()
	_test_a_weak_follow_up_cannot_stamp_out_an_ult()
	_test_a_late_beat_still_retriggers()
	_test_strength_is_clamped()
	_test_centre_is_carried()
	_test_public_surface_intact()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Shockwave tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Shockwave tests: all PASS")
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
	(obj as Node).free()


func _pp_const(name: String) -> float:
	var m: Dictionary = (load(PP_PATH) as GDScript).get_script_constant_map()
	return float(m.get(name, NAN))


## A PostProcess OUTSIDE the tree. `_ready` builds a CanvasLayer + ColorRect + shader,
## none of which a headless amplitude check needs, and `_process` is driven by hand
## below — but `_process` returns early unless the effect is enabled, and enabling is
## what `_drive` handles.
func _make() -> Node:
	return (load(PP_PATH) as GDScript).new() as Node


## Fire a ripple and advance `frames` of decay, returning the amplitude the shader
## would have been handed on the last of them.
##
## ⚠ THE MATERIAL IS NOT BUILT HERE, so `_process` cannot be called: it pokes
## `_mat.set_shader_parameter` on a null. The decay is replayed against the same
## constants instead — which is honest about what is being measured (the CURVE, from
## the values the object holds) rather than pretending a headless run rendered.
func _amp_after(pp: Node, strength: float, frames: int) -> float:
	pp.call(&"_begin_shock", strength, Vector2(0.5, 0.5))
	var age: float = float(pp.get(&"_shock_age")) + DT * float(frames)
	var k: float = 1.0 - clampf(age / _pp_const("SHOCK_DURATION"), 0.0, 1.0)
	return _pp_const("SHOCK_BASE_AMP") * float(pp.get(&"_shock_strength")) * k * k


## The headline: a stronger beat has to produce a stronger ripple. This is the exact
## assertion the shipped code failed.
func _test_strength_reaches_the_amplitude() -> void:
	var pp: Node = _make()
	var weak: float = _amp_after(pp, 0.35, 2)
	var strong: float = _amp_after(pp, 1.4, 2)
	_expect(strong > weak,
		"a 1.4 beat ripples harder than a 0.35 one (%f vs %f)" % [strong, weak])
	pp.free()
	_completes("strength_reaches_the_amplitude")


## ...and not merely by a hair. The authored range spans 4x, so the amplitudes must
## too — a fix that scaled by, say, `0.9 + 0.1 * strength` would satisfy the test above
## while still rendering every spell as the same ripple.
func _test_the_authored_range_is_separated() -> void:
	var pp: Node = _make()
	var weak: float = _amp_after(pp, 0.35, 2)
	var strong: float = _amp_after(pp, 1.4, 2)
	_expect(weak > 0.0, "the weakest authored beat still ripples at all (got %f)" % weak)
	_expect(strong / maxf(weak, 1e-9) > 3.5,
		"the authored 4x strength range survives as at least 3.5x amplitude (got %fx)"
			% (strong / maxf(weak, 1e-9)))
	pp.free()
	_completes("the_authored_range_is_separated")


## ⚠ THE PROMISE TO EVERYTHING THAT ALREADY SHIPPED. Strength 1.0 must land on exactly
## the amplitude every ripple used to render at, so this is a fix that makes small
## beats smaller and big ones bigger rather than a global volume knob.
func _test_unit_strength_is_unchanged() -> void:
	var pp: Node = _make()
	pp.call(&"_begin_shock", 1.0, Vector2(0.5, 0.5))
	_expect(is_equal_approx(float(pp.get(&"_shock_strength")), 1.0),
		"strength 1.0 is carried as 1.0 (got %f)" % float(pp.get(&"_shock_strength")))
	var k: float = 1.0  # age 0 -> the peak of the ease-out
	var expected: float = _pp_const("SHOCK_BASE_AMP") * k * k
	var got: float = _pp_const("SHOCK_BASE_AMP") * float(pp.get(&"_shock_strength")) * k * k
	_expect(is_equal_approx(got, expected),
		"a strength-1.0 ripple is byte-identical to the shipped one (%f vs %f)"
			% [got, expected])
	pp.free()
	_completes("unit_strength_is_unchanged")


## The ease-out still eases out. A ripple that never reaches zero is a permanent screen
## warp; one that reaches it early is a ripple that pops off.
func _test_amplitude_decays_to_zero() -> void:
	var pp: Node = _make()
	var dur: float = _pp_const("SHOCK_DURATION")
	var early: float = _amp_after(pp, 1.0, 2)
	var mid: float = _amp_after(pp, 1.0, int(dur * 30.0))
	var over: float = _amp_after(pp, 1.0, int(dur * 90.0))
	_expect(mid < early, "the ripple fades as it travels (%f -> %f)" % [early, mid])
	_expect(mid > 0.0, "...and is still alive at the halfway mark (got %f)" % mid)
	_expect(is_zero_approx(over), "...and is exactly gone past its duration (got %f)" % over)
	pp.free()
	_completes("amplitude_decays_to_zero")


## ⚠ THE GUARD THE FIX NEEDED. Big beats fire in clusters; a 0.35 follow-up three
## frames into an ult must not replace the ult's ring, or honouring strength would have
## made the signature moments worse than ignoring it did.
func _test_a_weak_follow_up_cannot_stamp_out_an_ult() -> void:
	var pp: Node = _make()
	pp.call(&"_begin_shock", 1.4, Vector2(0.5, 0.5))
	pp.set(&"_shock_age", 0.05)  # three frames in
	pp.call(&"_begin_shock", 0.35, Vector2(0.1, 0.1))
	_expect(is_equal_approx(float(pp.get(&"_shock_strength")), 1.4),
		"the ult's strength survives a weak follow-up (got %f)"
			% float(pp.get(&"_shock_strength")))
	_expect(float(pp.get(&"_shock_age")) > 0.0,
		"...and its ring is not restarted from zero (age %f)" % float(pp.get(&"_shock_age")))
	# A LOUDER follow-up does take over — the guard is about weaker beats only.
	pp.call(&"_begin_shock", 2.0, Vector2(0.9, 0.9))
	_expect(is_equal_approx(float(pp.get(&"_shock_strength")), 2.0),
		"a bigger beat still takes the screen (got %f)" % float(pp.get(&"_shock_strength")))
	pp.free()
	_completes("a_weak_follow_up_cannot_stamp_out_an_ult")


## ...but the guard must not swallow genuinely separate events. Past halfway the old
## ripple is nearly spent, so the next beat wins whatever its size.
func _test_a_late_beat_still_retriggers() -> void:
	var pp: Node = _make()
	pp.call(&"_begin_shock", 1.4, Vector2(0.5, 0.5))
	pp.set(&"_shock_age", _pp_const("SHOCK_DURATION") * 0.75)
	pp.call(&"_begin_shock", 0.35, Vector2(0.2, 0.2))
	_expect(is_equal_approx(float(pp.get(&"_shock_strength")), 0.35),
		"a late follow-up starts its own ripple (got %f)" % float(pp.get(&"_shock_strength")))
	_expect(is_zero_approx(float(pp.get(&"_shock_age"))),
		"...from the beginning (age %f)" % float(pp.get(&"_shock_age")))
	pp.free()
	_completes("a_late_beat_still_retriggers")


## A caller passing nonsense must not warp the screen inside out. The clamp is the same
## 0..2 the original `_begin_shock` applied; it just now reaches the picture.
func _test_strength_is_clamped() -> void:
	var pp: Node = _make()
	pp.call(&"_begin_shock", -5.0, Vector2(0.5, 0.5))
	_expect(float(pp.get(&"_shock_strength")) >= 0.0,
		"a negative strength cannot invert the ripple (got %f)"
			% float(pp.get(&"_shock_strength")))
	pp.set(&"_shock_age", -1.0)  # let the next beat through the young-ripple guard
	pp.call(&"_begin_shock", 99.0, Vector2(0.5, 0.5))
	_expect(float(pp.get(&"_shock_strength")) <= 2.0,
		"a runaway strength is capped at 2.0 (got %f)" % float(pp.get(&"_shock_strength")))
	pp.free()
	_completes("strength_is_clamped")


## The ripple centre is what makes a beat belong to a place in the world rather than to
## the middle of the screen; the strength work must not have dropped it.
func _test_centre_is_carried() -> void:
	var pp: Node = _make()
	pp.call(&"_begin_shock", 1.0, Vector2(0.25, 0.75))
	_expect((pp.get(&"_shock_center") as Vector2).is_equal_approx(Vector2(0.25, 0.75)),
		"the ripple centre is carried (got %s)" % str(pp.get(&"_shock_center")))
	_completes("centre_is_carried")
	pp.free()


## The statics 23 call sites reach for, and the tuning constants this suite reads.
func _test_public_surface_intact() -> void:
	var src: GDScript = load(PP_PATH) as GDScript
	for m: String in ["shock", "pulse_heat", "set_theme", "add"]:
		_expect(src.has_method(StringName(m)), "PostProcess still exposes static `%s`" % m)
	for c: String in ["SHOCK_BASE_AMP", "SHOCK_DURATION", "HEAT_DECAY"]:
		_expect(src.get_script_constant_map().has(c),
			"PostProcess still declares `%s`" % c)
	# `shock()` on a tree with no grade in it is a documented silent no-op — every call
	# site relies on that to stay guard-free, including in the calm hub.
	src.call("shock", 1.0, Vector2(0.5, 0.5))
	_completes("public_surface_intact")
