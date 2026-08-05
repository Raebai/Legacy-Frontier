# READ-ONLY PROBE (safe to delete). WHICH primitive is the ability bar's 258 us?
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_bar_prims.gd
#
# The bar draws ~15 draw_string and ~120 geometry primitives per frame. Before pitching
# "trade the name labels for rotating glyph rings", the relative cost of a string vs an
# arc vs a line has to be a MEASURED number, not an assumption about font shaping.
# Synthetic: one Control per primitive kind, 100 copies, timed against an empty one.
extends SceneTree

const COPIES: int = 100
const PER_NODE: int = 14        # what one bar draws of each kind, roughly
const SAMPLES: int = 240
const WARMUP: int = 60


class Bench extends Control:
	var kind: String = "none"

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		for i: int in 14:
			var p := Vector2(20.0 + float(i) * 9.0, 40.0 + float(i))
			match kind:
				"string":
					draw_string(font, p, "Meteor", HORIZONTAL_ALIGNMENT_CENTER, 46, 8,
						Color(0.62, 0.62, 0.7))
				"rect":
					draw_rect(Rect2(p, Vector2(46, 46)), Color(0.1, 0.1, 0.15, 0.9), false, 2.0)
				"line":
					draw_line(p, p + Vector2(8, 8), Color(0.7, 0.6, 1.0), 2.0)
				"arc":
					draw_arc(p, 18.0, 0.0, TAU, 24, Color(0.9, 0.4, 0.85), 2.0, true)
				"arc_no_aa":
					draw_arc(p, 18.0, 0.0, TAU, 24, Color(0.9, 0.4, 0.85), 2.0, false)
				"polyline_aa":
					var pts := PackedVector2Array()
					for k: int in 25:
						pts.append(p + Vector2.from_angle(TAU * float(k) / 24.0) * 18.0)
					draw_polyline(pts, Color(0.9, 0.4, 0.85), 2.0, true)
				"circle_filled":
					draw_circle(p, 6.0, Color(0.9, 0.4, 0.85), true, -1.0, true)
				"circle_no_aa":
					draw_circle(p, 6.0, Color(0.9, 0.4, 0.85), true, -1.0, false)
				"multiline_ring":
					# A whole 16-dash ring as ONE call.
					var seg := PackedVector2Array()
					for k: int in 16:
						var a0: float = TAU * float(k) / 16.0
						seg.append(p + Vector2.from_angle(a0) * 18.0)
						seg.append(p + Vector2.from_angle(a0 + 0.26) * 18.0)
					draw_multiline(seg, Color(0.9, 0.4, 0.85), 2.0)
				"colored_polygon":
					# A whole ring as ONE textured triangle fan.
					var pts := PackedVector2Array()
					var cols := PackedColorArray()
					for k: int in 20:
						pts.append(p + Vector2.from_angle(TAU * float(k) / 20.0) * 18.0)
						cols.append(Color(0.9, 0.4, 0.85, 0.5))
					draw_polygon(pts, cols)


func _initialize() -> void:
	Engine.max_fps = 0
	_run()


func _run() -> void:
	# Baseline measured TWICE, first and last, so a cold-cache first run cannot be
	# mistaken for a cheap primitive (the first pass of this probe did exactly that).
	var base_a: float = await _measure("none")
	var results: Array = []
	for kind: String in ["string", "rect", "line", "arc", "arc_no_aa", "polyline_aa",
			"circle_filled", "circle_no_aa", "multiline_ring", "colored_polygon"]:
		results.append([kind, await _measure(kind)])
	var base_b: float = await _measure("none")
	var base: float = minf(base_a, base_b)
	print("baseline first=%.3f last=%.3f ms  (using %.3f)" % [base_a, base_b, base])
	for r: Array in results:
		var per: float = (float(r[1]) - base) * 1000.0 / float(COPIES)
		print("%-14s %7.3f ms/frame  ->  %6.1f us per node (%d prims)  = %5.2f us/prim" % [
			r[0], float(r[1]), per, PER_NODE, per / float(PER_NODE)])
	quit(0)


func _measure(kind: String) -> float:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	for i: int in COPIES:
		var b := Bench.new()
		b.kind = kind
		layer.add_child(b)
	for i: int in WARMUP:
		await process_frame
	var t0: int = Time.get_ticks_usec()
	for i: int in SAMPLES:
		await process_frame
	var ms: float = float(Time.get_ticks_usec() - t0) / float(SAMPLES) / 1000.0
	layer.queue_free()
	for i: int in 20:
		await process_frame
	return ms
