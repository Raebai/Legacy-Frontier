# READ-ONLY PROBE (safe to delete). Every class's REAL hand, with the proposed socket
# glyph, at true phone pixels — plus a stdout table of the motif each slot resolves to.
#
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_glyph_kits.gd
#
# ⚠ NO --headless (headless writes blank PNGs while reporting success).
#
# Frames (in %APPDATA%/Godot/app_userdata/Ashpire/):
#   _probe_glyph_kits_true.png   640x360, 1:1 — the honest phone read
#   _probe_glyph_kits_6x.png     same pixels, NEAREST x6
extends SceneTree

const VIEW: Vector2i = Vector2i(640, 360)

const MOTIF_NAMES: Array[String] = ["NONE", "DESCENT", "LANCE", "BARRIER", "ERUPTION",
	"ORBIT", "PULSE", "SNARE", "BLADE", "WARD", "VOID", "SPIRAL", "SUMMON"]


func _initialize() -> void:
	_run()


func _run() -> void:
	# --- the table, before anything is drawn -------------------------------------
	var classes: int = SpellLibrary.CLASS_KITS.size()
	var worst: int = 0
	# EVERY REACHABLE HAND, not just the default one: the player leaves one non-ult role
	# behind at class-select, so a class has C(4,3)=4 hands and the default is only one.
	var by_id: Dictionary = SpellLibrary._spell_by_id()
	print("id pool: ", by_id.size(), " spells")   # guard: an empty pool would pass vacuously
	for c: int in classes:
		var kit: Dictionary = SpellLibrary.kit_for_class(c)
		var non_ult: Array = []
		for role: String in SpellLibrary.ROLE_ORDER:
			if role != "ult" and kit.has(role):
				non_ult.append(role)
		for drop: int in non_ult.size():
			var roles: Array = []
			for i: int in non_ult.size():
				if i != drop:
					roles.append(non_ult[i])
			roles.append("ult")
			var seen: Dictionary = {}
			var line: String = "class %d (no %s): " % [c, non_ult[drop]]
			for role: String in roles:
				var sig: SpellDef = by_id.get(String(kit.get(role, ""))) as SpellDef
				if sig == null:
					continue
				var m: int = Page.motif_for(sig)
				line += "%s=%s  " % [sig.id, MOTIF_NAMES[m]]
				seen[m] = int(seen.get(m, 0)) + 1
			var dup: int = 0
			for k: Variant in seen:
				if int(seen[k]) > 1:
					dup += int(seen[k]) - 1
				if int(k) == MagicCircle.Motif.NONE:
					line += " <<< NONE"
			worst = maxi(worst, dup)
			print(line, ("   <<< %d DUPLICATE(S)" % dup) if dup > 0 else "")
	print("worst duplicate count in any reachable hand: ", worst)
	# --- every Kind must resolve --------------------------------------------------
	for k: int in Page.MOTIF_BY_KIND.keys().size():
		pass
	var missing: Array[int] = []
	for kind: int in range(22):
		if int(Page.MOTIF_BY_KIND.get(kind, MagicCircle.Motif.NONE)) == MagicCircle.Motif.NONE:
			missing.append(kind)
	print("Kinds with no motif: ", missing)

	# --- the picture ---------------------------------------------------------------
	var sub := SubViewport.new()
	sub.size = VIEW
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.disable_3d = true
	var page := Page.new()
	for c: int in classes:
		page.hands.append(SpellLibrary.build_for_class(c))
	sub.add_child(page)
	root.add_child(sub)
	for i: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	img.save_png("user://_probe_glyph_kits_true.png")
	var big: Image = img.duplicate()
	big.resize(VIEW.x * 6, VIEW.y * 6, Image.INTERPOLATE_NEAREST)
	big.save_png("user://_probe_glyph_kits_6x.png")
	print("wrote _probe_glyph_kits_true.png / _6x.png")
	quit(0)


class Page extends Control:
	var hands: Array = []

	## FALLBACK ONLY. The first key is the spectacle SCRIPT (so the socket and the cast
	## circle are literally the same lookup); this answers when that table has no row —
	## which today is NOVA (its spectacle is a .tscn, not a .gd) and the eleven HEX
	## class signatures.
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
		SpellDef.Kind.CHAIN: MagicCircle.Motif.LANCE,
		SpellDef.Kind.ZONE: MagicCircle.Motif.WARD,
		SpellDef.Kind.MISSILES: MagicCircle.Motif.ORBIT,
		SpellDef.Kind.BLINK_STRIKE: MagicCircle.Motif.BLADE,
		SpellDef.Kind.TETHER: MagicCircle.Motif.SNARE,
		SpellDef.Kind.FLURRY: MagicCircle.Motif.BLADE,
		SpellDef.Kind.CRAWLER: MagicCircle.Motif.SNARE,
		SpellDef.Kind.THROWN_ANCHOR: MagicCircle.Motif.BLADE,
		SpellDef.Kind.WARD: MagicCircle.Motif.WARD,
		SpellDef.Kind.ARC: MagicCircle.Motif.LANCE,
		SpellDef.Kind.HEX: MagicCircle.Motif.SPIRAL,
		SpellDef.Kind.CATACLYSM: MagicCircle.Motif.VOID,
	}

	## THE PROPOSED ADDITIONS to SpellSigil.MOTIF_BY_SCRIPT. Every one of these spells
	## currently opens a MOTIF-LESS cast circle in world space too, so this is one fix
	## in two places rather than a HUD-only table.
	const PROPOSED_SCRIPT_ROWS: Dictionary = {
		# --- ELEVEN ADDITIONS. These spells have NO row today, so they open a
		#     motif-less circle in world space too — one fix, two places.
		"ThousandCuts.gd": MagicCircle.Motif.PULSE,
		"IaiSlash.gd": MagicCircle.Motif.BLADE,
		"CrescentStep.gd": MagicCircle.Motif.LANCE,
		"ShockwaveStomp.gd": MagicCircle.Motif.PULSE,
		"MeteorFist.gd": MagicCircle.Motif.DESCENT,
		"RadiantVolley.gd": MagicCircle.Motif.LANCE,
		"Shatter.gd": MagicCircle.Motif.PULSE,
		"HeavensWrath.gd": MagicCircle.Motif.DESCENT,
		"FaultLine.gd": MagicCircle.Motif.LANCE,
		"RaiseThrall.gd": MagicCircle.Motif.SUMMON,
		"GraveTide.gd": MagicCircle.Motif.PULSE,
		"IceSpikeLine.gd": MagicCircle.Motif.ERUPTION,
		# --- SIX RE-POINTS, each chosen so no HAND carries the same figure twice.
		"RiftDagger.gd": MagicCircle.Motif.LANCE,        # was BLADE
		"RockPillar.gd": MagicCircle.Motif.BARRIER,      # was ERUPTION
		"ChainBolt.gd": MagicCircle.Motif.SNARE,         # was LANCE
		"ShadowRoot.gd": MagicCircle.Motif.WARD,         # was SNARE
		"HorizonArc.gd": MagicCircle.Motif.PULSE,        # was LANCE
		"StarConvergence.gd": MagicCircle.Motif.ORBIT,   # was DESCENT
		"DrainTether.gd": MagicCircle.Motif.VOID,        # was SNARE
		"BlinkStrike.gd": MagicCircle.Motif.SPIRAL,      # was BLADE
	}

	const GLYPH_R: float = AbilityBar.SOCKET_RADIUS * 1.16
	const GLYPH_W: float = 1.8

	static func motif_for(sig: SpellDef) -> int:
		if sig == null:
			return MagicCircle.Motif.NONE
		var file: String = SpellCaster.spectacle_path(sig).get_file()
		if not file.is_empty():
			# PROPOSED first: it IS the post-patch MOTIF_BY_SCRIPT (11 additions + 6
			# re-points). Falling through to the live table gives the untouched rows.
			var m: int = int(PROPOSED_SCRIPT_ROWS.get(file, MagicCircle.Motif.NONE))
			if m == MagicCircle.Motif.NONE:
				m = int(SpellSigil.MOTIF_BY_SCRIPT.get(file, MagicCircle.Motif.NONE))
			if m != MagicCircle.Motif.NONE:
				return m
		return int(MOTIF_BY_KIND.get(sig.kind, MagicCircle.Motif.NONE))

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, Vector2(640, 360)), Color(0.06, 0.06, 0.09))
		for c: int in hands.size():
			var col_i: int = c / 5
			var row_i: int = c % 5
			var ox: float = 14.0 + float(col_i) * 312.0
			var oy: float = 12.0 + float(row_i) * 68.0
			draw_string(font, Vector2(ox, oy + 8.0), "c%d" % c,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.6, 0.7))
			var x: float = ox + 18.0
			for sig: Variant in (hands[c] as Array):
				var s: SpellDef = sig as SpellDef
				var rect := Rect2(Vector2(x, oy), Vector2(AbilityBar.SLOT_SIZE, AbilityBar.SLOT_SIZE))
				var accent: Color = s.resolve_color(Elements.color(SpellCaster.resolve_element(s)))
				_socket(rect, accent, SpellTier.of(s), motif_for(s), GLYPH_R, GLYPH_W)
				x += AbilityBar.SLOT_SIZE + 8.0

	func _socket(rect: Rect2, accent: Color, tier: int, motif: int, gr: float, gw: float) -> void:
		draw_rect(rect, AbilityBar.PANEL_COLOR)
		var c: Vector2 = rect.get_center()
		var t: int = clampi(tier, 0, AbilityBar.TIER_DASHES.size() - 1)
		draw_circle(c, AbilityBar.SOCKET_RADIUS,
			Color(accent.r, accent.g, accent.b, AbilityBar.SOCKET_WASH_ALPHA), true, -1.0, true)
		var r: float = AbilityBar.SOCKET_RADIUS
		_ring(c, r, AbilityBar.TIER_DASHES[t], AbilityBar.TIER_DUTY[t], 0.0, TAU,
			accent, AbilityBar.TIER_RING_WIDTH[t], true)
		if tier == SpellTier.Tier.ULT:
			_ring(c, r * AbilityBar.ULT_OUTER_R, 3, 0.5, 0.0, TAU,
				Color(SpellTier.color(SpellTier.Tier.ULT), 0.75), 2.0, true)
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
