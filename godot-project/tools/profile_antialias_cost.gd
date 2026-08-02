# Run WITH THE GUI BINARY:
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/profile_antialias_cost.gd
#
# WHAT `antialiased = true` COSTS, IN PRIMITIVES.
#
# `tools/profile_draw_cost.gd` measured a single `CharacterRig` at ~820-920
# rasterised primitives per frame, and the static read of the file says its `_draw`
# issues only about 40 `draw_*` CALLS. A 20x gap between calls issued and primitives
# produced is not a rounding error, and the candidate explanation is the trailing
# `true` on 19 of those calls: Godot's software antialiasing does not ask the
# hardware for anything, it TESSELLATES — building extra fringe geometry around
# every stroke so the edge can be feathered in the fragment shader.
#
# That matters because the project also runs MSAA on the 2D viewport, which smooths
# exactly the same edges in hardware. If the tessellation multiplier is large, the
# game is paying for edge antialiasing twice on every line it draws, and the cheaper
# of the two payments is the one it can stop making.
#
# This measures the multiplier directly and synthetically: identical geometry, one
# node with `antialiased = true` and one with `false`, primitives-in-frame differenced.
# Synthetic ON PURPOSE — a measurement taken inside CharacterRig would be confounded
# by its aura layers, its IK and its conditional garnish, and the question here is
# about one boolean, not about one script.
#
# ⚠ THE RESULT IS A RATIO, AND ONLY A RATIO. It says how much more geometry an
# antialiased stroke builds. It does NOT say the game will get faster by that
# proportion — primitives are one input to the frame and the two systems that
# dominated the fill measurement (MSAA resolve, the screen-space grade) are per-pixel
# and appear nowhere in this number.
#
# Test-idiom note: a HARNESS, not an assertion suite — no pass/fail sentinels.
extends SceneTree

## Strokes drawn per node. Large enough that the fixed per-node overhead is a
## rounding error on the total and the ratio is the geometry's, not the node's.
const STROKES: int = 400
const WIDTH: float = 2.0
## Points per polyline. CharacterRig's limbs are short multi-segment runs and
## SpawnTell's scribbles are 5-point polylines, so this is the shape in use — a
## 2-point line would understate the fringe, which is built per SEGMENT and per JOIN.
const POINTS: int = 5

var _phase: int = 0


## ⚠ The knobs are duplicated into the inner class rather than read off the outer
## one. A script run with `--script` has no `class_name`, so an inner class cannot
## name its enclosing script — `OuterName.CONST` is a compile error that reports as
## an unrelated missing identifier, which is the same shape as the autoload trap
## recorded in docs/NEXT-SESSION.md. `_run` asserts the two copies agree.
class Strokes:
	extends Node2D
	const STROKES: int = 400
	const POINTS: int = 5
	const WIDTH: float = 2.0

	var aa: bool = false
	var mode: String = "polyline"

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99   # identical geometry in both nodes; only `aa` differs
		for i: int in STROKES:
			var pts := PackedVector2Array()
			var o := Vector2(rng.randf_range(0.0, 900.0), rng.randf_range(0.0, 500.0))
			for p: int in POINTS:
				pts.append(o + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0)))
			match mode:
				"polyline":
					draw_polyline(pts, Color(1, 1, 1, 0.9), WIDTH, aa)
				"line":
					draw_line(pts[0], pts[1], Color(1, 1, 1, 0.9), WIDTH, aa)
				"arc":
					draw_arc(o, 12.0, 0.0, TAU, 14, Color(1, 1, 1, 0.9), WIDTH, aa)


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("profile_antialias_cost: HEADLESS reports zero primitives. Use the GUI binary.")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run()


func _run() -> void:
	if Strokes.STROKES != STROKES or Strokes.POINTS != POINTS or Strokes.WIDTH != WIDTH:
		printerr("[aa] the header constants and the drawer's copies have drifted apart —")
		printerr("     the printed configuration would not be the one measured.")
		quit(1)
		return
	print("[aa] %d strokes/node, %d points each, width %.1f" % [STROKES, POINTS, WIDTH])
	print("  %-12s %12s %12s %10s" % ["primitive", "aa=false", "aa=true", "x more"])
	for mode: String in ["line", "polyline", "arc"]:
		var off: int = await _measure(mode, false)
		var on: int = await _measure(mode, true)
		print("  %-12s %12d %12d %9.1fx"
			% [mode, off, on, float(on) / maxf(float(off), 1.0)])
	print("")
	print("  CharacterRig issues 19 antialiased draw_* calls per figure and measures")
	print("  ~820-920 rasterised primitives per visible rig at 60 Hz — the dominant")
	print("  continuous cost in the frame. The viewport already runs MSAA over the")
	print("  same edges. See tools/slice_test_render_budget.gd for the fill numbers.")
	quit(0)


## Primitives attributable to one `Strokes` node: measured with it present, then
## with it hidden, and differenced — so the stage's own baseline (there is none here,
## but a future caller may add one) cancels instead of being counted as stroke cost.
func _measure(mode: String, aa: bool) -> int:
	var n := Strokes.new()
	n.aa = aa
	n.mode = mode
	root.add_child(n)
	var with: int = await _prims()
	n.visible = false
	var without: int = await _prims()
	n.queue_free()
	await process_frame
	return with - without


func _prims() -> int:
	var acc: int = 0
	for i: int in 5:
		await process_frame
		await RenderingServer.frame_post_draw
		acc += int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	@warning_ignore("integer_division")
	var out: int = acc / 5
	return out
