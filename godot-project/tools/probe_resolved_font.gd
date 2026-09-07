# What font does a real Control actually RESOLVE to, and can that font draw the glyphs
# the game had to stop using?
#
#   Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#       --script tools/probe_resolved_font.gd
#   Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/probe_resolved_font.gd          # GUI, same question
#
# WHY THIS EXISTS. `slice_test_font_coverage` asks the THEME for its font, finds none,
# and falls back to asking Godot's built-in default — and on that basis 237 files carry
# glyph substitutions. But a specimen rendered through the GUI binary drew every one of
# the banned glyphs, and drew ⚠ in COLOUR, which is a system emoji font and not anything
# this project ships. So one of two things is true and they lead to opposite decisions:
#
#   * the resolved font really does cover them, and the substitutions are protecting
#     against a fault that only exists on some platforms; or
#   * it does not, and something below `has_char` is quietly filling the gap on this
#     desktop while the APK gets the zero-width nothing the maker actually reported.
#
# ⚠ SO IT ASKS THE CONTROL, NOT THE THEME. `Control.get_theme_font()` is what the
# renderer resolves, including the default-theme font the suite has to reach for by
# hand. The difference between those two lookups is the whole question.
extends SceneTree

const THEME_PATH: String = "res://assets/ui/stickspire_theme.tres"
const WANTED: Array = [
	[0x2588, "block"], [0x25C9, "fisheye"], [0x25CB, "circle"],
	[0x21A9, "hook arrow"], [0x2726, "four-point star"], [0x21BA, "reset arrow"],
	[0x2617, "shogi piece"], [0x25D0, "half circle"], [0x25B8, "right triangle"],
	[0x25C6, "diamond"], [0x26A0, "warning"], [0x2190, "left arrow"],
	[0x2192, "right arrow"], [0x203A, "angle quote"],
]


func _init() -> void:
	var headless: bool = DisplayServer.get_name() == "headless"
	print("")
	print("display server: %s" % DisplayServer.get_name())

	var theme: Theme = load(THEME_PATH) as Theme
	print("theme default_font: %s" % ("<none>" if theme.default_font == null
		else str(theme.default_font)))

	# A real Button, in a real tree, with the real theme — resolved the way the renderer
	# resolves it.
	var b := Button.new()
	b.theme = theme
	root.add_child(b)
	var f: Font = b.get_theme_font(&"font")
	print("Button.get_theme_font(font) -> %s" % ("<null>" if f == null else str(f)))
	if f != null:
		print("  font_name: %s" % f.get_font_name())
		print("  fallbacks: %d" % f.get_fallbacks().size())
		for sub in f.get_fallbacks():
			print("      %s" % (sub as Font).get_font_name())

	print("")
	print("has_char on the RESOLVED font:")
	var missing: int = 0
	for e in WANTED:
		var ok: bool = f != null and f.has_char(int(e[0]))
		if not ok:
			missing += 1
		print("  U+%04X %-16s %s" % [int(e[0]), e[1], "yes" if ok else "NO"])

	# `has_char` is one question; "would a glyph actually come out" is another, because
	# the text server consults OS fallbacks that `has_char` on a single Font does not
	# report. Measure the DRAWN width: a zero-width nothing is exactly that.
	print("")
	print("drawn width of each glyph through the resolved font (0.0 = nothing drawn):")
	if f != null:
		for e in WANTED:
			var s: String = String.chr(int(e[0]))
			var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			print("  U+%04X %-16s width %.1f%s"
				% [int(e[0]), e[1], w, "   <-- ZERO" if w <= 0.01 else ""])

	print("")
	print("SUMMARY: %d of %d wanted glyphs are missing from the resolved font (%s)"
		% [missing, WANTED.size(), "headless" if headless else "GUI"])
	quit(0)
