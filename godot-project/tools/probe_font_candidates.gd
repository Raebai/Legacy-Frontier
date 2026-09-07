# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#          --script tools/probe_font_candidates.gd -- <dir-of-ttfs>
#
# WHICH CANDIDATE FONTS CAN ACTUALLY DRAW THE GLYPHS THIS GAME WANTS BACK.
#
# `slice_test_font_coverage` bans a glyph when the font that will draw it lacks it, and
# says so in its own header: the substitutions are "a consequence of having no font, not
# a house style", and the suite "goes green on its own" once the theme gains one. This
# is the instrument for choosing that font.
#
# ⚠ IT ASKS `has_char`, WHICH IS THE QUESTION THE RENDERER ASKS. Not a cmap parsed by
# hand, not a table read from a foundry's website — the same call the suite uses and the
# same one the text server makes when it decides whether to draw a glyph or a
# zero-width nothing. A font that answers true here is a font that will draw it.
#
# Fonts are read as BYTES from an absolute path and handed to `FontFile.data`, so
# candidates can be auditioned from a scratch directory without importing anything into
# the project. Nothing is written.
extends SceneTree

## The glyphs the game asked for and could not have. Taken from
## `slice_test_font_coverage.gd`'s header, which lists every one it had to substitute,
## plus the arrows and marks the touch D-pad and the padlock rows wanted.
const WANTED: Array = [
	[0x2588, "block, class-roster rail + colour swatch"],
	[0x25C9, "fisheye, 'this one is mine'"],
	[0x25CB, "circle, the unpicked mark"],
	[0x21A9, "hook arrow, Grimoire toggle"],
	[0x2726, "four-point star, Grimoire toggle"],
	[0x21BA, "anticlockwise open circle, Reset"],
	[0x2617, "black shogi piece, class button"],
	[0x25D0, "half circle, Colours button"],
	[0x25B8, "small right triangle, in-label separator"],
	[0x25C6, "black diamond, armoury pad default"],
	[0x26A0, "warning sign, credits"],
	[0x203A, "single right angle quote, Start Run"],
	[0x2039, "single left angle quote"],
	[0x2190, "left arrow, D-pad"],
	[0x2191, "up arrow, D-pad"],
	[0x2192, "right arrow, D-pad"],
	[0x2193, "down arrow, D-pad"],
	[0x25B4, "small up triangle"],
	[0x25BE, "small down triangle"],
	[0x25AA, "small black square"],
	[0x2022, "bullet"],
	[0x2026, "ellipsis"],
	[0x00D7, "multiplication sign"],
	[0x2014, "em dash"],
]

## A face with no lowercase is a DISPLAY face, not a body face, and the difference
## decides which slot it can fill. Checked rather than assumed.
const BODY_SAMPLE: String = "abcdefghijklmnopqrstuvwxyz0123456789"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("give me a directory of .ttf files")
		quit(2)
		return
	var dir_path: String = args[0]
	var names: PackedStringArray = _ttfs_in(dir_path)
	if names.is_empty():
		push_error("no .ttf under %s" % dir_path)
		quit(2)
		return

	print("")
	print("%d candidate(s) in %s" % [names.size(), dir_path])
	print("")
	var rows: Array = []
	for n in names:
		var f: FontFile = _load_abs(dir_path.path_join(n))
		if f == null:
			print("  %-34s COULD NOT LOAD" % n)
			continue
		var missing: Array = []
		for entry in WANTED:
			if not f.has_char(int(entry[0])):
				missing.append(entry)
		var lower_ok: bool = true
		for c in BODY_SAMPLE:
			if not f.has_char(c.unicode_at(0)):
				lower_ok = false
				break
		rows.append([n, missing, lower_ok, f])
		print("  %-34s %2d/%2d wanted glyphs   %s" % [
			n, WANTED.size() - missing.size(), WANTED.size(),
			"body-capable" if lower_ok else "DISPLAY ONLY (no full lowercase/digits)"])

	print("")
	print("what each one is missing:")
	for r in rows:
		if (r[1] as Array).is_empty():
			print("  %-34s nothing" % r[0])
			continue
		var bits: PackedStringArray = []
		for entry in r[1]:
			bits.append("U+%04X %s" % [int(entry[0]), entry[1]])
		print("  %-34s" % r[0])
		for b in bits:
			print("      %s" % b)

	# THE PAIRING THAT MATTERS: a display face is allowed to miss symbols as long as
	# something behind it has them, because Godot falls back per-glyph. So the only
	# candidate that must be complete is whichever one carries the FALLBACK.
	print("")
	print("full-coverage candidates (could carry the symbol fallback):")
	var any: bool = false
	for r in rows:
		if (r[1] as Array).is_empty():
			print("  %s" % r[0])
			any = true
	if not any:
		print("  none alone — pair a display face with a symbol font as its fallback")
	quit(0)


func _ttfs_in(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return out
	for n in d.get_files():
		if n.to_lower().ends_with(".ttf") or n.to_lower().ends_with(".otf"):
			out.append(n)
	out.sort()
	return out


## ⚠ BYTES, NOT `load()`. `load()` only reaches inside res://, and auditioning a font
## means reading one that is deliberately NOT in the project yet.
func _load_abs(path: String) -> FontFile:
	var fa: FileAccess = FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var bytes: PackedByteArray = fa.get_buffer(fa.get_length())
	fa.close()
	var f: FontFile = FontFile.new()
	f.data = bytes
	return f
