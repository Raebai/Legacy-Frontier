# READ-ONLY PROBE (safe to delete). LOOK at the proposed per-kind SOCKET GLYPH.
#
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_glyph_socket.gd
#
# ⚠ NO --headless. Headless writes blank PNGs while reporting success.
#
# Everything drawn here is a FAITHFUL TRANSCRIPTION of the code being proposed:
# `AbilityBar._draw_socket` as it ships today, plus the extracted-static motif body
# copied verbatim out of `MagicCircle._draw_motif`. Nothing in the game is edited.
#
# Frames (in %APPDATA%/Godot/app_userdata/Legacy Frontier/):
#   _probe_glyph_true.png   the 640x360 phone framebuffer 1:1
#   _probe_glyph_6x.png     the same pixels, NEAREST x6, for judging
extends SceneTree

const VIEW: Vector2i = Vector2i(640, 360)


func _initialize() -> void:
	_run()


func _run() -> void:
	var sub := SubViewport.new()
	sub.size = VIEW
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.disable_3d = true
	var page := Page.new()
	page.kit = SpellLibrary.build_for_class(0)   # ARCANIST
	sub.add_child(page)
	root.add_child(sub)
	for i: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	img.save_png("user://_probe_glyph_true.png")
	var big: Image = img.duplicate()
	big.resize(VIEW.x * 6, VIEW.y * 6, Image.INTERPOLATE_NEAREST)
	big.save_png("user://_probe_glyph_6x.png")
	print("wrote _probe_glyph_true.png (%dx%d) and _probe_glyph_6x.png" % [VIEW.x, VIEW.y])
	quit(0)


class Page extends Control:
	var kit: Array = []

	## THE PROPOSED MAP. Kind -> MagicCircle.Motif, all 22, nothing NONE.
	const MOTIF_BY_KIND: Dictionary = {
		SpellDef.Kind.BEAM: MagicCircle.Motif.LANCE,
		SpellDef.Kind.DIVINE_RAY: MagicCircle.Motif.DESCENT,
		SpellDef.Kind.NOVA: MagicCircle.Motif.PULSE,
		SpellDef.Kind.METEOR: MagicCircle.Motif.DESCENT,
		SpellDef.Kind.CONVERGENCE: MagicCircle.Motif.DESCENT,
		SpellDef.Kind.RUSH: MagicCircle.Motif.LANCE,
		SpellDef.Kind.BOULDER: MagicCircle.Motif.ERUPTION,
		SpellDef.Kind.PILLAR: MagicCircle.Motif.ERUPTION,
		SpellDef.Kind.WALL: MagicCircle.Motif.BARRIER,
		SpellDef.Kind.ICE_WALL: MagicCircle.Motif.BARRIER,
		SpellDef.Kind.CHAIN: MagicCircle.Motif.SNARE,
		SpellDef.Kind.ZONE: MagicCircle.Motif.WARD,
		SpellDef.Kind.MISSILES: MagicCircle.Motif.ORBIT,
		SpellDef.Kind.BLINK_STRIKE: MagicCircle.Motif.BLADE,
		SpellDef.Kind.TETHER: MagicCircle.Motif.SNARE,
		SpellDef.Kind.FLURRY: MagicCircle.Motif.BLADE,
		SpellDef.Kind.CRAWLER: MagicCircle.Motif.SNARE,
		SpellDef.Kind.THROWN_ANCHOR: MagicCircle.Motif.BLADE,
		SpellDef.Kind.WARD: MagicCircle.Motif.WARD,
		SpellDef.Kind.ARC: MagicCircle.Motif.PULSE,
		SpellDef.Kind.HEX: MagicCircle.Motif.SPIRAL,
		SpellDef.Kind.CATACLYSM: MagicCircle.Motif.VOID,
	}

	## Glyph geometry, expressed against the socket the bar already draws.
	const GLYPH_R: float = AbilityBar.SOCKET_RADIUS * 1.16
	const GLYPH_W: float = 1.8

	static func motif_for(sig: SpellDef) -> int:
		if sig == null:
			return MagicCircle.Motif.NONE
		# Per-spell refinement FIRST for the two kinds that hide many spells behind one
		# ordinal, so the socket agrees with the cast circle spell-for-spell.
		if sig.kind == SpellDef.Kind.HEX or sig.kind == SpellDef.Kind.CATACLYSM:
			var path: String = SpellCaster.spectacle_path(sig)
			if not path.is_empty():
				var m: int = int(SpellSigil.MOTIF_BY_SCRIPT.get(path.get_file(),
					MagicCircle.Motif.NONE))
				if m != MagicCircle.Motif.NONE:
					return m
		return int(MOTIF_BY_KIND.get(sig.kind, MagicCircle.Motif.NONE))

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, Vector2(640, 360)), Color(0.06, 0.06, 0.09))
		draw_string(font, Vector2(8, 14), "ARCANIST kit — socket + glyph (true 640x360 px)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.9))
		# ── Row A: the real Arcanist hand, as the bar would draw it ──────────────
		var x: float = 12.0
		for i: int in kit.size():
			var sig: SpellDef = kit[i] as SpellDef
			var rect := Rect2(Vector2(x, 26.0), Vector2(AbilityBar.SLOT_SIZE, AbilityBar.SLOT_SIZE))
			var accent: Color = sig.resolve_color(Elements.color(SpellCaster.resolve_element(sig)))
			_socket(rect, accent, SpellTier.of(sig), motif_for(sig), GLYPH_R, GLYPH_W)
			draw_string(font, Vector2(x - 4.0, 88.0), sig.id.substr(0, 12),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.6, 0.6, 0.7))
			x += AbilityBar.SLOT_SIZE + 12.0
		# ── Row A': same four, thinner + smaller glyph, for the size A/B ─────────
		draw_string(font, Vector2(8, 108), "same four, GLYPH_R x1.00 / w 1.3",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.8))
		x = 12.0
		for i: int in kit.size():
			var sig2: SpellDef = kit[i] as SpellDef
			var rect2 := Rect2(Vector2(x, 114.0), Vector2(AbilityBar.SLOT_SIZE, AbilityBar.SLOT_SIZE))
			var accent2: Color = sig2.resolve_color(Elements.color(SpellCaster.resolve_element(sig2)))
			_socket(rect2, accent2, SpellTier.of(sig2), motif_for(sig2),
				AbilityBar.SOCKET_RADIUS, 1.3)
			x += AbilityBar.SLOT_SIZE + 12.0
		# ── Rows B: every motif in the vocabulary, one accent, so shape is all ───
		draw_string(font, Vector2(8, 186), "the whole motif vocabulary (same colour on purpose)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.8))
		var names: Array[String] = ["DESCENT", "LANCE", "BARRIER", "ERUPTION", "ORBIT", "PULSE",
			"SNARE", "BLADE", "WARD", "VOID", "SPIRAL", "SUMMON"]
		var flat := Color(0.78, 0.45, 1.0)
		for i: int in names.size():
			var col_i: int = i % 6
			var row_i: int = i / 6
			var rx: float = 12.0 + float(col_i) * (AbilityBar.SLOT_SIZE + 12.0)
			var ry: float = 194.0 + float(row_i) * 78.0
			_socket(Rect2(Vector2(rx, ry), Vector2(AbilityBar.SLOT_SIZE, AbilityBar.SLOT_SIZE)),
				flat, SpellTier.Tier.HEAVY, i + 1, GLYPH_R, GLYPH_W)
			draw_string(font, Vector2(rx - 3.0, ry + 56.0), names[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.62, 0.62, 0.72))

	## `AbilityBar._draw_slot` + `_draw_socket`, transcribed, plus the glyph.
	func _socket(rect: Rect2, accent: Color, tier: int, motif: int, gr: float, gw: float) -> void:
		draw_rect(rect, AbilityBar.PANEL_COLOR)
		var c: Vector2 = rect.get_center()
		var t: int = clampi(tier, 0, AbilityBar.TIER_DASHES.size() - 1)
		var phase: float = 0.0
		draw_circle(c, AbilityBar.SOCKET_RADIUS,
			Color(accent.r, accent.g, accent.b, AbilityBar.SOCKET_WASH_ALPHA), true, -1.0, true)
		var r: float = AbilityBar.SOCKET_RADIUS
		_ring(c, r, AbilityBar.TIER_DASHES[t], AbilityBar.TIER_DUTY[t], phase, TAU,
			accent, AbilityBar.TIER_RING_WIDTH[t], true)
		if tier == SpellTier.Tier.ULT:
			_ring(c, r * AbilityBar.ULT_OUTER_R, 3, 0.5, -phase * 0.5, TAU,
				Color(SpellTier.color(SpellTier.Tier.ULT), 0.75), 2.0, true)
		# THE GLYPH — the extracted static, called at the socket's centre.
		var gcol := Color(accent.r * 1.25, accent.g * 1.25, accent.b * 1.25, 0.95)
		draw_set_transform(c, 0.0, Vector2.ONE)
		_motif(self, motif, gr, gcol, gw, 0.0, false, 0.95)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(rect, AbilityBar.BORDER_COLOR, false, AbilityBar.BORDER_WIDTH)
		draw_rect(rect, AbilityBar.READY_GLOW_COLOR, false, AbilityBar.READY_GLOW_WIDTH)

	func _ring(c: Vector2, r: float, n: int, duty: float, rot: float, sweep: float,
			col: Color, w: float, aa: bool) -> void:
		if sweep <= 0.0 or n <= 0 or r <= 0.0:
			return
		var pts := PackedVector2Array()
		var step: float = TAU / float(n)
		var a: float = 0.0
		while a < sweep:
			var a0: float = -PI * 0.5 + rot + a
			pts.append(c + Vector2.from_angle(a0) * r)
			pts.append(c + Vector2.from_angle(a0 + minf(step * duty, sweep - a)) * r)
			a += step
		if pts.size() >= 2:
			draw_multiline(pts, col, w, aa)

	# ══ THE PROPOSED STATIC, verbatim from MagicCircle._draw_motif's match block ══
	static func _seg_of(full: int, r: float, low: bool) -> int:
		var n: int = full
		if r > 0.0:
			n = clampi(MagicCircle.segments_for_radius(absf(r)), MagicCircle.MIN_SEGMENTS, full)
		return maxi(n / 2, 12) if low else n

	static func _star(ci: CanvasItem, r: float, points: int, offset: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i: int in points:
			pts.append(Vector2.from_angle(offset - PI / 2.0 + TAU * float(i) / float(points)) * r)
		pts.append(pts[0])
		ci.draw_polyline(pts, col, 2.0, true)

	static func _motif(ci: CanvasItem, motif: int, R: float, col: Color, w: float,
			phase: float, low: bool, shade_a: float) -> void:
		if motif == MagicCircle.Motif.NONE or R <= 4.0:
			return
		var lo: float = R * MagicCircle.MOTIF_INNER
		var hi: float = R * MagicCircle.MOTIF_OUTER
		match motif:
			MagicCircle.Motif.DESCENT:
				for i: int in 3:
					var d: Vector2 = Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 3.0)
					var t: Vector2 = d.orthogonal()
					ci.draw_polyline(PackedVector2Array([
						d * hi + t * R * 0.14, d * lo, d * hi - t * R * 0.14,
					]), col, w, true)
				var x: float = R * 0.12
				ci.draw_line(Vector2(-x, 0.0), Vector2(x, 0.0), col, w * 0.7, true)
				ci.draw_line(Vector2(0.0, -x), Vector2(0.0, x), col, w * 0.7, true)
			MagicCircle.Motif.LANCE:
				ci.draw_line(Vector2(-hi, 0.0), Vector2(hi, 0.0), col, w + 0.4, true)
				ci.draw_polyline(PackedVector2Array([
					Vector2(hi * 0.55, -R * 0.13), Vector2(hi, 0.0), Vector2(hi * 0.55, R * 0.13),
				]), col, w, true)
				if not low:
					var g: float = R * 0.20
					ci.draw_line(Vector2(-hi * 0.7, -g), Vector2(hi * 0.2, -g), col, 1.0, true)
					ci.draw_line(Vector2(-hi * 0.7, g), Vector2(hi * 0.2, g), col, 1.0, true)
			MagicCircle.Motif.BARRIER:
				ci.draw_line(Vector2(-hi, 0.0), Vector2(hi, 0.0), col, w + 1.4, true)
				if not low:
					var e: float = R * 0.16
					ci.draw_line(Vector2(-hi, -e), Vector2(-hi, e), col, w, true)
					ci.draw_line(Vector2(hi, -e), Vector2(hi, e), col, w, true)
			MagicCircle.Motif.ERUPTION:
				for i: int in 5:
					var d2: Vector2 = Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 5.0)
					var t2: Vector2 = d2.orthogonal()
					ci.draw_polyline(PackedVector2Array([
						d2 * lo + t2 * R * 0.10, d2 * hi, d2 * lo - t2 * R * 0.10,
					]), col, w, true)
			MagicCircle.Motif.ORBIT:
				var mid: float = (lo + hi) * 0.5
				ci.draw_arc(Vector2.ZERO, mid, 0.0, TAU, _seg_of(40, mid, low),
					Color(col.r, col.g, col.b, col.a * 0.45), 1.0, true)
				for i: int in 3:
					var p: Vector2 = Vector2.from_angle(phase * 1.9 + TAU * float(i) / 3.0) * mid
					ci.draw_circle(p, maxf(1.8, R * 0.05), col, true, -1.0, true)
			MagicCircle.Motif.PULSE:
				for i: int in 3:
					var rr2: float = lerpf(lo, hi, float(i) / 2.0)
					var off: float = float(i) * 0.7
					ci.draw_arc(Vector2.ZERO, rr2, off, off + TAU * 0.78, _seg_of(30, rr2, low),
						Color(col.r, col.g, col.b, col.a * (1.0 - 0.22 * float(i))), w, true)
			MagicCircle.Motif.SNARE:
				for i: int in 3:
					var base: float = TAU * float(i) / 3.0
					var pts := PackedVector2Array()
					for k: int in 7:
						var tt: float = float(k) / 6.0
						var rr3: float = lerpf(lo, hi, tt)
						pts.append(Vector2.from_angle(base + tt * 1.5) * rr3)
					ci.draw_polyline(pts, col, w, true)
			MagicCircle.Motif.BLADE:
				var d3: Vector2 = Vector2.from_angle(-0.55)
				var d4: Vector2 = Vector2.from_angle(0.75)
				ci.draw_line(-d3 * hi, d3 * hi, col, w + 0.8, true)
				ci.draw_line(-d4 * hi * 0.72, d4 * hi * 0.72,
					Color(col.r, col.g, col.b, col.a * 0.7), w, true)
			MagicCircle.Motif.WARD:
				var hex := PackedVector2Array()
				for i: int in 7:
					hex.append(Vector2.from_angle(TAU * float(i % 6) / 6.0) * hi * 0.88)
				ci.draw_polyline(hex, col, w, true)
			MagicCircle.Motif.VOID:
				ci.draw_circle(Vector2.ZERO, hi * 0.8, Color(0.0, 0.0, 0.0, 0.55 * shade_a),
					true, -1.0, true)
				ci.draw_arc(Vector2.ZERO, hi * 0.8, 0.0, TAU, _seg_of(40, hi * 0.8, low),
					col, w + 0.6, true)
			MagicCircle.Motif.SPIRAL:
				var sp := PackedVector2Array()
				var steps: int = 10 if low else 16
				for k2: int in steps + 1:
					var tt2: float = float(k2) / float(steps)
					sp.append(Vector2.from_angle(phase * 0.5 + tt2 * TAU * 0.9)
						* lerpf(lo * 0.6, hi, tt2))
				ci.draw_polyline(sp, col, w, true)
			MagicCircle.Motif.SUMMON:
				_star(ci, hi * 0.9, 3, 0.0, col)
				ci.draw_arc(Vector2.ZERO, lo * 0.8, 0.0, TAU, _seg_of(24, lo * 0.8, low),
					Color(col.r, col.g, col.b, col.a * 0.5), 1.0, true)
