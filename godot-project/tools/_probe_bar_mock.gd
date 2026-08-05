# READ-ONLY PROBE (safe to delete). SIDE BY SIDE: the shipped socket vs the proposed one.
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_bar_mock.gd
#
#   _probe_mock_big.png    both rows at 46 px slots, 6x NEAREST — is the figure legible?
#   _probe_mock_phone.png  the same rows squashed to a true 640x360 framebuffer first,
#                          then 6x NEAREST — does ANY of it survive a phone?
#
# Row 1 = today (panel + element ring + tier corner brackets + name text + veil wipe).
# Row 2 = proposed (dashed rune ring whose DASH COUNT is the tier, a still motif from
#         SpellDef.kind in the middle, cooldown as a CLOSING arc, no name text, no
#         float timer, ULT gets a counter-rotating outer ring).
# Both rows are drawn with the primitives the shipped bar would use, so the perf model
# in the report is the model these pixels cost.
extends SceneTree

const SLOT: float = 46.0
const GAP: float = 6.0
const PHONE: Vector2i = Vector2i(640, 360)

## The Arcanist's real hand, from the probe run: three ARCANE spells and a FIRE ult.
## The point of using it is that three of the four are the SAME COLOUR — the case the
## shipped bar cannot tell apart.
const CASES: Array[Dictionary] = [
	{"n": "First", "c": Color(0.95, 0.4, 0.85), "tier": 0, "motif": "LANCE", "cd": 0.0},
	{"n": "Mirror", "c": Color(0.95, 0.4, 0.85), "tier": 1, "motif": "SUMMON", "cd": 0.6},
	{"n": "Arcane", "c": Color(0.95, 0.4, 0.85), "tier": 1, "motif": "ORBIT", "cd": 0.0},
	{"n": "Meteor", "c": Color(1.0, 0.45, 0.15), "tier": 2, "motif": "DESCENT", "cd": 0.3},
]


class Mock extends Control:
	const SLOT: float = 46.0
	const GAP: float = 6.0
	var cases: Array = []
	var phase: float = 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(d: float) -> void:
		phase += d
		queue_redraw()

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.10, 0.11, 0.15))
		var x0: float = 30.0
		draw_string(font, Vector2(x0, 22.0), "SHIPPED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.7, 0.7, 0.8))
		for i: int in cases.size():
			var r := Rect2(Vector2(x0 + float(i) * (SLOT + GAP), 30.0), Vector2(SLOT, SLOT))
			_shipped(r, cases[i], font)
		draw_string(font, Vector2(x0, 118.0), "PROPOSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.7, 0.7, 0.8))
		for i: int in cases.size():
			var r := Rect2(Vector2(x0 + float(i) * (SLOT + GAP), 126.0), Vector2(SLOT, SLOT))
			_proposed(r, cases[i], font)

	# ------------------------------------------------------------------ today
	func _shipped(rect: Rect2, cs: Dictionary, font: Font) -> void:
		var accent: Color = cs["c"]
		var tier: int = int(cs["tier"])
		var tc: Color = SpellTier.color(tier)
		draw_rect(rect, Color(0.08, 0.08, 0.12, 0.88))
		var inner: Rect2 = rect.grow(-3.0)
		draw_rect(inner, Color(accent.r, accent.g, accent.b, 0.13))
		draw_rect(inner, accent, false, 2.0)
		var corners: Array = [
			[inner.position, Vector2.RIGHT, Vector2.DOWN],
			[Vector2(inner.end.x, inner.position.y), Vector2.LEFT, Vector2.DOWN],
			[Vector2(inner.position.x, inner.end.y), Vector2.RIGHT, Vector2.UP],
			[inner.end, Vector2.LEFT, Vector2.UP],
		]
		for c: Array in corners:
			draw_line(c[0], c[0] + (c[1] as Vector2) * 8.0, tc, 2.0)
			draw_line(c[0], c[0] + (c[2] as Vector2) * 8.0, tc, 2.0)
		draw_rect(rect, Color(0.36, 0.36, 0.44, 0.9), false, 1.0)
		if tier == 2:
			draw_rect(rect.grow(2.0), tc, false, 2.0)
			draw_rect(rect.grow(4.5), tc, false, 1.0)
		draw_string(font, rect.position + Vector2(4, 13), String(cs.get("key", "1")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.96, 1.0))
		draw_string(font, Vector2(rect.position.x, rect.end.y - 3.0), String(cs["n"]),
			HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), 8, Color(0.62, 0.62, 0.7))
		var frac: float = float(cs["cd"])
		if frac > 0.0:
			var h: float = rect.size.y * frac
			draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - h),
				Vector2(rect.size.x, h)), Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(rect.position.x, rect.get_center().y + 5.0),
				"%.1f" % (frac * 6.0), HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), 15,
				Color(1, 1, 1, 0.95))
		else:
			draw_rect(rect, Color(0.55, 0.9, 1.0, 0.9), false, 2.0)

	# --------------------------------------------------------------- proposed
	## Dash count IS the tier (6 / 10 / 14 — MagicCircle.GLYPHS_*), so density says
	## "heavy" without a second hue. One draw_multiline for the whole ring.
	func _proposed(rect: Rect2, cs: Dictionary, font: Font) -> void:
		var accent: Color = cs["c"]
		var tier: int = int(cs["tier"])
		var frac: float = float(cs["cd"])
		var c: Vector2 = rect.get_center()
		var R: float = 16.0
		# 1. the plinth — quieter than today's: no second inner border to fight the ring
		draw_rect(rect, Color(0.07, 0.07, 0.11, 0.85))
		draw_rect(rect, Color(0.30, 0.30, 0.38, 0.55), false, 1.0)
		# 2. dim wash inside the ring so the socket reads as a vessel, not a hole
		draw_circle(c, R * 0.95, Color(accent.r, accent.g, accent.b, 0.10), true, -1.0, false)
		# 3. the cooldown IS the ring: it CLOSES as the spell returns
		var dashes: int = [6, 10, 14][tier]
		var sweep: float = TAU * (1.0 - frac)
		var spin: float = phase * (0.35 if tier < 2 else 0.22)
		_dashed_ring(c, R, dashes, spin, sweep,
			Color(accent.r, accent.g, accent.b, 1.0 if frac <= 0.0 else 0.85), 2.0)
		# 4. the ULT is HUNGRIER: a second ring outside, turning the other way
		if tier == 2:
			_dashed_ring(c, R * 1.30, 4, -phase * 0.5, TAU,
				Color(1.0, 0.80, 0.35, 0.75), 2.0)
		# 5. the motif — the still figure that says WHICH spell. Batched: one call.
		_motif(c, R, String(cs["motif"]), Color(accent.r * 1.25, accent.g * 1.25,
			accent.b * 1.25, 0.95))
		# 6. core mote, breathing
		var b: float = 0.8 + 0.2 * sin(phase * 4.0)
		draw_circle(c, 2.2 * b, Color(1, 1, 1, 0.85), true, -1.0, false)
		# 7. still-cooling: a dim veil, NOT a black wipe, and no float timer at all
		if frac > 0.0:
			draw_rect(rect.grow(-1.0), Color(0.02, 0.02, 0.05, 0.34))
		# 8. the key stays — it is the one text a thumb needs
		draw_string(font, rect.position + Vector2(4, 13), String(cs.get("key", "1")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.96, 1.0, 0.9))

	## A ring of `n` dashes over `sweep` radians from 12 o'clock, as ONE draw_multiline.
	func _dashed_ring(c: Vector2, r: float, n: int, rot: float, sweep: float,
			col: Color, w: float) -> void:
		if sweep <= 0.0:
			return
		var pts := PackedVector2Array()
		var step: float = TAU / float(n)
		var dash: float = step * 0.55
		var a: float = 0.0
		while a < sweep:
			var a0: float = -PI * 0.5 + rot + a
			var a1: float = a0 + minf(dash, sweep - a)
			pts.append(c + Vector2.from_angle(a0) * r)
			pts.append(c + Vector2.from_angle(a1) * r)
			a += step
		if pts.size() >= 2:
			draw_multiline(pts, col, w)

	## The inner-court figure. Same vocabulary as MagicCircle.Motif; batched into one
	## draw_multiline so a whole figure costs about what one arc used to.
	func _motif(c: Vector2, R: float, motif: String, col: Color) -> void:
		var lo: float = R * 0.30
		var hi: float = R * 0.62
		var p := PackedVector2Array()
		match motif:
			"DESCENT":
				for i: int in 3:
					var d: Vector2 = Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 3.0)
					var t: Vector2 = d.orthogonal()
					p.append(c + d * hi + t * R * 0.20); p.append(c + d * lo)
					p.append(c + d * lo); p.append(c + d * hi - t * R * 0.20)
			"LANCE":
				p.append(c + Vector2(-hi, 0)); p.append(c + Vector2(hi, 0))
				p.append(c + Vector2(hi, 0)); p.append(c + Vector2(hi - 4, -3))
				p.append(c + Vector2(hi, 0)); p.append(c + Vector2(hi - 4, 3))
			"BARRIER":
				p.append(c + Vector2(-hi, -2)); p.append(c + Vector2(hi, -2))
				p.append(c + Vector2(-hi * 0.6, -2)); p.append(c + Vector2(-hi * 0.6, 4))
				p.append(c + Vector2(0, -2)); p.append(c + Vector2(0, 4))
				p.append(c + Vector2(hi * 0.6, -2)); p.append(c + Vector2(hi * 0.6, 4))
			"ORBIT":
				for i: int in 3:
					var a: float = TAU * float(i) / 3.0
					var s: Vector2 = c + Vector2.from_angle(a) * hi
					p.append(s + Vector2(-2, -2)); p.append(s + Vector2(2, 2))
					p.append(s + Vector2(2, -2)); p.append(s + Vector2(-2, 2))
				p.append(c + Vector2(-lo, 0)); p.append(c + Vector2(lo, 0))
			"SUMMON":
				# two overlapping figures — "another body arrives"
				for dx: float in [-3.0, 3.0]:
					p.append(c + Vector2(dx, -hi)); p.append(c + Vector2(dx, hi))
					p.append(c + Vector2(dx - 4, -hi * 0.5)); p.append(c + Vector2(dx + 4, -hi * 0.5))
			"PULSE":
				for k: int in 3:
					var rr: float = lo + (hi - lo) * float(k) / 2.0
					for s: int in 8:
						var a0: float = TAU * float(s) / 8.0
						p.append(c + Vector2.from_angle(a0) * rr)
						p.append(c + Vector2.from_angle(a0 + 0.5) * rr)
		if p.size() >= 2:
			draw_multiline(p, col, 1.6)


var _mock: Mock = null


func _initialize() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_mock = Mock.new()
	var cs: Array = []
	for i: int in CASES.size():
		var d: Dictionary = (CASES[i] as Dictionary).duplicate()
		d["key"] = str(i + 1)
		cs.append(d)
	_mock.cases = cs
	layer.add_child(_mock)
	_run()


func _run() -> void:
	for i: int in 60:
		await process_frame
	await _shot("_probe_mock_big", 6, false)
	await _shot("_probe_mock_phone", 6, true)
	quit(0)


func _shot(name: String, zoom: int, phone: bool) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var s: float = float(img.get_width()) / 640.0
	var band := Rect2i(20, 10, 280, 180)
	if phone:
		img.resize(PHONE.x, PHONE.y, Image.INTERPOLATE_LANCZOS)
	else:
		band = Rect2i(int(20 * s), int(10 * s), int(280 * s), int(180 * s))
	var out: Image = img.get_region(band.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	out.resize(out.get_width() * zoom, out.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	out.save_png("user://%s.png" % name)
	print("%s -> %dx%d" % [name, out.get_width(), out.get_height()])
