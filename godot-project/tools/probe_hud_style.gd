# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_hud_style.gd
#
# THE MEASUREMENT BEHIND THE HUD CONSOLIDATION PASS. Not a test — it asserts
# nothing and never fails. It prints the numbers the pass was judged on, so the
# "before" and the "after" in the report are read off a run rather than argued.
#
# What it prints, and why each number is the one that matters:
#
#   1. ON-SCREEN SIZE ACROSS THE ZOOM RANGE. The combat camera runs 0.46 .. 2.6,
#      a 5.6x swing, and every body-attached HUD node is a Node2D whose drawn size
#      is world_size * zoom. This walks the range and prints what the PLAYER sees.
#      A widget that obeys HudStyle's one zoom rule prints the same number in every
#      column; one that does not prints the bug.
#
#   2. THE BANDS. Every band's extent, and every PAIR checked for intersection.
#      The layout test asserts this against live nodes; this prints it so a human
#      can see the stack.
#
#   3. TYPE. The widths the fallback font actually produces for the strings the
#      HUD draws, at the sizes it draws them — which is how "104px is enough for
#      the chain counter at BODY but not at LEAD" was decided rather than guessed.
extends SceneTree

const HudStyle := preload("res://scripts/ui/HudStyle.gd")

## The camera positions worth looking at: both ends of the real range, the
## reference (where everything was tuned), and 1.0 (where the old clamp sat).
const ZOOMS: Array[float] = [0.46, 1.0, 1.6, 2.2, 2.6]


func _process(_delta: float) -> bool:
	_zoom_table()
	_band_table()
	_type_table()
	quit(0)
	return true


## on-screen px = world px * zoom * ui_scale(zoom).
func _screen_px(world_px: float, zoom: float) -> float:
	var ui: float = clampf(HudStyle.ZOOM_REF / zoom,
		HudStyle.ZOOM_REF / HudStyle.ZOOM_TIGHT, HudStyle.ZOOM_REF / HudStyle.ZOOM_WIDE)
	return world_px * zoom * ui


func _raw_px(world_px: float, zoom: float) -> float:
	return world_px * zoom


func _zoom_table() -> void:
	print("── body-attached HUD, ON-SCREEN pixels across the camera range ──")
	var head: String = "  %-26s" % "widget (world px)"
	for z: float in ZOOMS:
		head += "%8.2f" % z
	print(head)
	var rows: Array = [
		["enemy HP bar h (4)", 4.0],
		["hero HP bar h (7)", 7.0],
		["hero HP bar w (52)", 52.0],
		["ringout %% font (11)", 11.0],
		["damage number (15x1.2)", 18.0],
		["damage crit (26x1.5)", 39.0],
		["bark font (9)", 9.0],
	]
	for r: Array in rows:
		var raw: String = "  %-26s" % ("RAW  " + String(r[0]))
		var fix: String = "  %-26s" % ("HELD " + String(r[0]))
		for z: float in ZOOMS:
			raw += "%8.1f" % _raw_px(float(r[1]), z)
			fix += "%8.1f" % _screen_px(float(r[1]), z)
		print(raw)
		print(fix)
	print("")


func _band_table() -> void:
	print("── the vertical bands (base viewport 640x360) ──")
	var bands: Array = [
		["rank title", HudStyle.BAND_RANK],
		["floor banner", HudStyle.BAND_FLOOR_BANNER],
		["boss bar", HudStyle.BAND_BOSS_BAR],
		["boss modifiers", HudStyle.BAND_BOSS_MODS],
		["floor affix", HudStyle.BAND_AFFIX],
		["hype shout", HudStyle.BAND_SHOUT],
	]
	for b: Array in bands:
		var span: Array = b[1]
		print("  %-16s y %6.1f .. %6.1f   (%.0f px)"
			% [b[0], span[0], span[1], float(span[1]) - float(span[0])])
	var overlaps: int = 0
	for i: int in bands.size():
		for j: int in range(i + 1, bands.size()):
			var a: Array = bands[i][1]
			var c: Array = bands[j][1]
			if float(a[0]) < float(c[1]) and float(c[0]) < float(a[1]):
				overlaps += 1
				print("  ⚠ OVERLAP: %s and %s" % [bands[i][0], bands[j][0]])
	print("  overlapping band pairs: %d" % overlaps)
	print("")


func _type_table() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		print("(no fallback font — skipping the type table)")
		return
	print("── drawn width of the strings the HUD actually renders ──")
	var rows: Array = [
		["24  CHAIN", HudStyle.BODY, Hype.COMBO_WIDTH],
		["24  CHAIN", HudStyle.LEAD, Hype.COMBO_WIDTH],
		["100  CHAIN", HudStyle.BODY, Hype.COMBO_WIDTH],
		["100  CHAIN", HudStyle.LEAD, Hype.COMBO_WIDTH],
		["THE ASHEN GUARDIAN", HudStyle.BODY, 640.0 - 2.0 * BossBar.NAME_INSET],
		["THIS FLOOR: INKED — PRESSED TOO HARD INTO THE PAGE", HudStyle.SMALL, 600.0],
		["UNSTOPPABLE", HudStyle.TITLE, 640.0],
		["Ascendant · Tier 5", HudStyle.SMALL, 640.0],
	]
	for r: Array in rows:
		var w: float = font.get_string_size(String(r[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(r[1])).x
		var box: float = float(r[2])
		print("  %-52s @%2d -> %6.1f px in a %.0f px box  %s"
			% [r[0], int(r[1]), w, box, "FITS" if w <= box else "ELLIPSISED"])
	print("")
