# Run: godot --headless --path godot-project --script tools/slice_test_render_budget.gd
#
# THE RENDER-CONFIG GUARD RAIL. Pins the settings a profiling pass measured and a
# later session can silently undo — because every one of them is a single character
# in a file nobody reads, and every one of them is invisible until somebody
# re-measures.
#
# WHAT WAS MEASURED (tools/profile_fill_cost.gd and tools/profile_post_variants.gd,
# shipping Arena, RTX 4070 Laptop, vsync off, static stage, medians of 7-9 laps):
#
#   1920x1080   baseline 1.73 ms/frame of pure fill
#               msaa 8x -> 4x   -30%      msaa 8x -> 2x   -47%     msaa off  -63%
#               post-process off          -51%
#   2560x1440   baseline 2.96 ms/frame
#               msaa off  -69%            post-process off  -53%
#
#   Inside the post-process grade, at 1920x1080:
#               the screen-texture MIPMAP CHAIN   10% of the frame, for an image
#                 that is bit-identical (every fetch samples LOD 0)
#               the grain                         12%
#               the chromatic aberration           1-2%   <- effectively free
#               the vignette                       0-2%   <- effectively free
#
# ── WHAT THIS SUITE THEREFORE ASSERTS, AND WHY EACH ONE ──────────────────────
#
#   msaa_2d is 4x (value 2) AND NOT 8x (value 3). The project shipped on 3 — the
#   SLOWEST option Godot offers — while its own notes described it as 4x, so nobody
#   was choosing it. 8x costs a third of the fill budget on top of 4x on a desktop
#   and is bandwidth, which is exactly the axis a mid-range Android is worst on.
#   This is a FLOOR-AND-CEILING assertion, not an equality: dropping to 2x is a
#   further real saving somebody may legitimately take, but going back to 8x has to
#   be a decision with a number attached rather than a default.
#
#   The post-process shader does NOT sample the screen texture with a mipmap
#   filter. The chain is rebuilt every frame from the whole framebuffer and is never
#   read above LOD 0. Free to remove, and free to accidentally reinstate — the hint
#   is one word on one line.
#
#   The mobile MSAA override stays STRICTLY CHEAPER than the desktop one. The phone
#   is the constrained device; a change that quietly raised it to match desktop
#   would be invisible on the machine it was made on.
#
# ⚠ WHY NOTHING HERE IS A MILLISECOND. Wall-clock in this repo is non-monotonic by
# ~20x for sub-millisecond work and cannot be asserted on. Every value below is a
# project setting or a substring of a shader — deterministic, identical on every
# machine, and the thing the measurement was actually about. The milliseconds live
# in the two profiling harnesses, which are for a human to read.
#
# Idiom: failures accumulate on the MEMBER `_fails` and every test records a
# COMPLETION SENTINEL, so a test that aborts part-way fails BY ABSENCE rather than
# being read as a pass. Never `_fails += _test_x()`. See tools/slice_test_loadout.gd.
extends SceneTree

## Every test that must run to completion. Missing at the end = it aborted.
const TESTS: Array[String] = [
	"msaa_is_not_the_slowest_option",
	"mobile_msaa_is_cheaper_than_desktop",
	"post_shader_has_no_mipmap_chain",
	"post_shader_still_has_its_look",
	"post_process_is_gated_by_the_quality_dial",
]

const POST_SHADER: String = "res://scenes/combat/post_process.gdshader"

## Godot's msaa_2d enum: 0 off, 1 = 2x, 2 = 4x, 3 = 8x ("Slowest" in the editor).
const MSAA_OFF: int = 0
const MSAA_8X: int = 3
const MSAA_4X: int = 2

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true

	_test_msaa_is_not_the_slowest_option()
	_test_mobile_msaa_is_cheaper_than_desktop()
	_test_post_shader_has_no_mipmap_chain()
	_test_post_shader_still_has_its_look()
	_test_post_process_is_gated_by_the_quality_dial()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Render budget tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Render budget tests: all PASS")
		quit(0)
	return true


# ------------------------------------------------------------------- the tests

## 8x MSAA is the most expensive anti-aliasing Godot will sell you, and this game is
## flat vector art whose primitives already ask for per-primitive antialiasing of
## their own. Measured cost of the last doubling: 30% of the fill budget at 1080p.
func _test_msaa_is_not_the_slowest_option() -> void:
	var msaa: int = int(ProjectSettings.get_setting(
		"rendering/anti_aliasing/quality/msaa_2d", MSAA_8X))
	_expect(msaa < MSAA_8X,
		"msaa_2d is not 8x, Godot's slowest option (got %d; 30%% of the 1080p fill"
			% msaa + " budget sits between 4x and 8x)")
	# The other half of the fence. AA off is a legitimate perf choice on some
	# targets, but this project's look study committed to native-res + MSAA, so
	# silently landing on 0 would be a look regression wearing a perf win's clothes.
	_expect(msaa > MSAA_OFF,
		"msaa_2d is still ON (got %d) — the look study committed to native-res + MSAA"
			% msaa)
	_completes("msaa_is_not_the_slowest_option")


## The phone is the constrained device. A desktop-side change that raised the mobile
## override to match would be invisible on the machine it was made on, which is the
## whole failure mode a `.mobile` override exists to prevent.
func _test_mobile_msaa_is_cheaper_than_desktop() -> void:
	var desktop: int = int(ProjectSettings.get_setting(
		"rendering/anti_aliasing/quality/msaa_2d", MSAA_4X))
	var mobile: int = int(ProjectSettings.get_setting(
		"rendering/anti_aliasing/quality/msaa_2d.mobile", desktop))
	_expect(mobile <= desktop,
		"the mobile msaa override (%d) is no more expensive than desktop (%d)"
			% [mobile, desktop])
	_completes("mobile_msaa_is_cheaper_than_desktop")


## `filter_linear_mipmap` on a `hint_screen_texture` makes the renderer build a full
## mipmap pyramid of the framebuffer every frame. Every fetch in this shader uses
## screen-space UVs at 1:1, so the derivatives are ~1 texel and all of them land on
## LOD 0 — the pyramid is built and never read. 10% of the frame at 1080p for an
## image that does not change by one bit.
func _test_post_shader_has_no_mipmap_chain() -> void:
	var code: String = _shader_code()
	if code == "":
		_expect(false, "the post-process shader could not be read at " + POST_SHADER)
		return
	_expect(not code.contains("filter_linear_mipmap"),
		"post_process.gdshader does not request a per-frame framebuffer mipmap chain"
		+ " (`filter_linear_mipmap` is back; use `filter_linear`, or `textureLod` if"
		+ " an effect genuinely needs a blurred read)")
	# An invariant that would be trivially true of an empty file is not an invariant.
	_expect(code.contains("hint_screen_texture"),
		"...and it still reads the screen at all (the grade is a screen-space pass)")
	_completes("post_shader_has_no_mipmap_chain")


## THE LOOK IS NOT A PERFORMANCE BUDGET. The aberration and the vignette were both
## measured at 0-2% of the frame — i.e. free — so any future "optimisation" that
## deletes them is paying nothing and costing the maker their picture. Pinned here
## precisely so that trade cannot be made by accident.
func _test_post_shader_still_has_its_look() -> void:
	var code: String = _shader_code()
	if code == "":
		_expect(false, "the post-process shader could not be read at " + POST_SHADER)
		return
	_expect(code.contains("aberration_base"),
		"the chromatic aberration is still in the grade (measured at 1-2% of the"
		+ " frame — removing it is a look decision, never a performance one)")
	_expect(code.contains("vignette_strength"),
		"the vignette is still in the grade (measured at 0-2% of the frame)")
	_expect(code.contains("shock_amp"),
		"the shockwave ripple is still in the grade")
	_completes("post_shader_still_has_its_look")


## The whole grade is ~50% of the fill budget, and the single biggest renderer
## saving available on a phone is not drawing it. That saving only exists if the
## quality dial can actually reach it.
func _test_post_process_is_gated_by_the_quality_dial() -> void:
	var src: String = _read("res://scripts/combat/PostProcess.gd")
	if src == "":
		_expect(false, "PostProcess.gd could not be read")
		return
	_expect(src.contains("screen_shaders_allowed"),
		"PostProcess still gates itself on TuningConfig.screen_shaders_allowed()"
		+ " (the LOW-quality path is how a phone stops paying for the grade)")
	_expect(src.contains("_rect.visible"),
		"...and it does so by hiding the rect, which is what makes the gate free")
	_completes("post_process_is_gated_by_the_quality_dial")


# ---------------------------------------------------------------------- helpers
func _shader_code() -> String:
	# Read the FILE, not `load(...).code`. A loaded Shader would report whatever the
	# importer produced, and the thing being guarded is the source a human edits.
	#
	# ⚠ COMMENTS STRIPPED, and that is not tidiness. The line above the sampler
	# EXPLAINS why the mipmap hint was removed, and therefore contains the word
	# `filter_linear_mipmap` — so a raw substring scan fails on the very file it is
	# guarding, and the obvious "fix" is to delete the explanation. Strip `//` first
	# and the assertion is about the CODE, which is what it was always about.
	var out: PackedStringArray = PackedStringArray()
	for line: String in _read(POST_SHADER).split("\n"):
		var cut: int = line.find("//")
		out.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(out)


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true
