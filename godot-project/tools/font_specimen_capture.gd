# Render every display-face candidate drawing the REAL title-screen strings through the
# REAL theme, so the choice is made on pixels. GUI binary only — a --headless run uses
# the dummy renderer and saves a blank PNG that looks exactly like a pass:
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/font_specimen_capture.gd -- <dir-of-ttfs>
#
# -> user://font_specimen.png
#
# WHY A SPECIMEN AND NOT A FONT NAME. `assets/ui/stickspire_theme.tres` carries 21
# font_size entries and no Font resource, so everything falls back to Godot's built-in
# Open Sans subset and every glyph past Latin-1 draws as a ZERO-WIDTH NOTHING with no
# error. `slice_test_font_coverage` currently guards 237 files with substitutions and
# says in its own header that they are "a consequence of having no font, not a house
# style" — ship a font with coverage and it goes green on its own.
#
# `probe_font_candidates.gd` already answered the decidable half: DejaVu Sans is the
# only candidate that draws all 24 wanted glyphs, so it carries the fallback here and
# every row gets the symbols. What is left is the half no assertion can settle — which
# display face the game should speak in — so this draws them and stops.
#
# ⚠ A SubViewport, NOT THE ROOT. The project stretches a 640x360 viewport, so
# `root.get_texture()` would hand back a 640x360 image and this specimen would be judged
# at a size no menu is ever read at. The maker's own rule, paid for on the rig: look at
# it BIG, and measure the channel the viewer gets.
extends SceneTree

const THEME_PATH: String = "res://assets/ui/stickspire_theme.tres"
## The face that answers `has_char` for all 24. Every row falls back to it, so a display
## face missing a symbol still SHOWS that symbol — which is exactly how it would behave
## in the shipped theme.
const FALLBACK: String = "DejaVuSans.ttf"

## The strings that were actually drawing nothing. Both title-screen primaries are
## constructor arguments to `Lobby._button`, which is how a gate written to catch this
## class of bug walked straight past them.
const SAMPLES: Array[String] = [
	"SINGLE PLAYER  ▸",
	"MULTIPLAYER",
	"Start Run  ›",
]
const GLYPH_ROW: String = \
	"█ ◉ ○ ↩ ✦ ↺ ☗ ◐ ▸ ◆ " + \
	"⚠ ← ↑ → ↓"
const BODY_LINE: String = \
	"Climb the tower. It takes floors back. — nine classes, one element each."

const W: int = 1180
const ROW_H: int = 188
const INK := Color(0.055, 0.06, 0.075)
const CHALK := Color(0.88, 0.9, 0.95)
const GRAPHITE := Color(0.62, 0.64, 0.72)
const ACCENT := Color(0.55, 0.9, 1.0)

var _dir: String = ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("give me the directory holding the candidate .ttf files")
		quit(2)
		return
	_dir = args[0]
	_run()


func _run() -> void:
	var fallback: FontFile = _load_abs(_dir.path_join(FALLBACK))
	if fallback == null:
		push_error("%s is the coverage font and it is not in %s" % [FALLBACK, _dir])
		quit(2)
		return

	var faces: Array = []                      # [label, FontFile or null for built-in]
	faces.append(["(built-in Open Sans — what ships today)", null])
	for n in _display_ttfs():
		var f: FontFile = _load_abs(_dir.path_join(n))
		if f != null:
			# ⚠ THE FALLBACK IS THE WHOLE POINT OF THE PAIRING. Godot resolves a missing
			# glyph per-CHARACTER down this chain, so a marker face with no arrows still
			# renders arrows — from DejaVu — without the heading losing its character.
			f.fallbacks = [fallback]
			faces.append([n.get_basename(), f])

	var sub := SubViewport.new()
	sub.size = Vector2i(W, ROW_H * faces.size() + 24)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	root.add_child(sub)

	var bg := ColorRect.new()
	bg.color = INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override(&"separation", 0)
	col.offset_left = 22
	col.offset_top = 12
	col.offset_right = -22
	sub.add_child(col)

	var theme: Theme = load(THEME_PATH) as Theme
	for face in faces:
		col.add_child(_row(String(face[0]), face[1] as FontFile, theme))

	for i: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = sub.get_texture().get_image()
	if img == null:
		push_error("no frame — was this run with the GUI binary?")
		quit(1)
		return
	var path: String = "user://font_specimen.png"
	img.save_png(path)
	print("")
	print("font_specimen_capture: %d face(s) -> %s"
		% [faces.size(), ProjectSettings.globalize_path(path)])
	print("  every row falls back to %s, so the glyph strip is what the SHIPPED"
		% FALLBACK)
	print("  theme would draw with that face on top.")
	quit(0)


## One face: its name, the two title-screen primaries, a body line and the glyph strip
## that has never once been drawn.
func _row(label: String, font: FontFile, theme: Theme) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, ROW_H)
	box.add_theme_constant_override(&"separation", 7)
	box.theme = theme

	box.add_child(_text(label, 13, ACCENT, font, true))

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override(&"separation", 16)
	for s in SAMPLES:
		var b := Button.new()
		b.text = s
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override(&"font_size", 19)
		b.add_theme_color_override(&"font_color", CHALK)
		if font != null:
			b.add_theme_font_override(&"font", font)
		strip.add_child(b)
	box.add_child(strip)

	box.add_child(_text(BODY_LINE, 15, GRAPHITE, font, false))
	box.add_child(_text(GLYPH_ROW, 26, CHALK, font, false))

	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.07)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	return box


func _text(s: String, size: int, colour: Color, font: FontFile,
		   is_name: bool) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	# The NAME of the face is set in the built-in font on purpose — a label naming a
	# candidate, drawn in that candidate, is unreadable exactly when the candidate is
	# the problem.
	if font != null and not is_name:
		l.add_theme_font_override(&"font", font)
	return l


func _display_ttfs() -> PackedStringArray:
	var out: PackedStringArray = []
	var d: DirAccess = DirAccess.open(_dir)
	if d == null:
		return out
	for n in d.get_files():
		if not n.to_lower().ends_with(".ttf"):
			continue
		# The coverage and symbol fonts are not candidates for the DISPLAY slot; they
		# are what sits behind whichever one wins.
		if n.begins_with("DejaVu") or n.begins_with("NotoSansSymbols") \
				or n.begins_with("NotoSansMath"):
			continue
		out.append(n)
	out.sort()
	return out


func _load_abs(path: String) -> FontFile:
	var fa: FileAccess = FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var bytes: PackedByteArray = fa.get_buffer(fa.get_length())
	fa.close()
	var f: FontFile = FontFile.new()
	f.data = bytes
	return f
