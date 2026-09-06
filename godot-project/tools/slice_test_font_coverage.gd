# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_font_coverage.gd
#
# EVERY CHARACTER THE GAME PUTS ON SCREEN CAN ACTUALLY BE DRAWN BY THE FONT THAT WILL
# DRAW IT.
#
# THE FAULT THIS EXISTS FOR, and it had been shipping for a long time.
# `assets/ui/stickspire_theme.tres` carries 21 font_size and font_color entries and NOT
# ONE Font resource, and there is no font file anywhere in the repo. So every Label and
# Button falls back to Godot's built-in Open Sans subset, whose coverage stops at
# Latin-1. Ten glyphs shipped inside button labels were therefore drawing NOTHING:
#
#   U+2588 █  the class roster's leading colour block — the source calls it "the leading
#             block on a rail row, drawn in the class colour", and it had never once been
#             drawn. The screen kept being judged with its main piece of colour missing.
#   U+2588 █  again, three of them, as the Outfitter colour picker's swatch. A colour
#             picker was shipping rows with no colour on them.
#   U+25C9 ◉  / U+25CB ○   the picker's "this one is mine" mark
#   U+21A9 ↩  / U+2726 ✦   the Grimoire toggle
#   U+21BA ↺  the Reset button          U+2617 ☗  the class button
#   U+25D0 ◐  the Colours button        U+25B8 ▸  the in-label separator
#   U+25C6 ◆  the armoury pad's default glyph
#   U+26A0 ⚠  the credits warning
#
# ⚠ THERE IS NO ERROR WHEN THIS HAPPENS. Godot draws a zero-width nothing and carries on,
# so the only symptom is a UI that quietly looks worse than the source says it does —
# which is the hardest class of bug to report, because the person seeing it can only say
# "it needs to look better".
#
# ⚠ WHY THIS SCANS SOURCE RATHER THAN PIXELS. The drawn channel cannot be intercepted
# here: Godot 4 refuses a GDScript override of a native CanvasItem draw method, and
# --headless has no framebuffer. But this fault is decidable WITHOUT drawing — `has_char`
# is the same question the renderer asks — so scanning what the source will hand to a
# control is not a weaker proxy for the real check, it IS the real check.
#
# ⚠ AND IT ASKS THE FONT THE GAME WILL ACTUALLY USE, not a hardcoded list. If the theme
# ever gains a real font with full coverage, this suite goes green on its own and the
# glyphs may come back — the substitutions below are a consequence of having no font, not
# a house style. That is the fix worth making one day; this is the guard until then.
extends SceneTree

const THEME_PATH: String = "res://assets/ui/stickspire_theme.tres"

## Directories whose string literals reach a control.
const SCAN_DIRS: Array[String] = ["res://scripts"]

## ⚠ THE FIRST VERSION OF THIS SUITE MATCHED `.text =` AND A HANDFUL OF SIBLINGS, AND IT
## MISSED THE TWO MOST IMPORTANT STRINGS IN THE GAME. `Lobby` builds its title screen with
## a helper — `_button("SINGLE PLAYER  ▸", _play_solo, 19)` — so the label is a
## CONSTRUCTOR ARGUMENT and never appears next to `.text`. Both primary verbs on the front
## door were drawing their marker as a zero-width nothing, and a gate written to catch
## exactly that bug walked straight past them.
##
## So the rule is inverted: every non-comment line is suspect, and only lines that
## demonstrably go to the CONSOLE are exempt. A allowlist of the ways a string can reach a
## control cannot be complete — there is always one more helper — whereas the set of sinks
## that are NOT the screen is small, closed and obvious.
##
## Comments are excluded wholesale: this file's own header is full of the very glyphs it
## bans, as is most of the codebase, deliberately. A comment is read in an editor.
const CONSOLE_SINKS: Array[String] = [
	"print(", "print_rich(", "printerr(", "printt(", "prints(",
	"push_error(", "push_warning(", "assert(",
]

## Codepoints allowed through even if the current font lacks them. Empty on purpose:
## anything that needs to be here is a glyph someone wants and cannot have, and the
## honest fix is a font rather than a waiver. Kept as the seam so a deliberate exception
## is one line with a reason next to it, not a rewrite of the walk.
const WAIVED: Array[int] = []

var _failures: int = 0
var _font: Font = null
var _checked_files: int = 0
var _checked_lines: int = 0


func _fail(msg: String) -> void:
	_failures += 1
	push_error("FAIL: " + msg)
	print("  FAIL: ", msg)


func _init() -> void:
	_font = _resolve_font()
	_test_the_probe_can_fail()
	_test_no_undrawable_glyph_reaches_a_control()
	print("  scanned %d files, %d ui lines, font '%s'"
		% [_checked_files, _checked_lines, _font.get_font_name() if _font != null else "<null>"])
	if _failures == 0:
		print("Font coverage tests: all PASS")
	else:
		print("Font coverage tests: ", _failures, " FAILED")
	quit(1 if _failures > 0 else 0)


## The font the game will really draw with: the theme's default if it has one, else the
## engine fallback every control silently lands on when it does not.
func _resolve_font() -> Font:
	var theme: Theme = load(THEME_PATH) as Theme
	if theme != null and theme.default_font != null:
		return theme.default_font
	return ThemeDB.fallback_font


## ⚠ A COVERAGE TEST THAT CANNOT FAIL IS A TEST OF THE FIXTURE. If `has_char` answered
## true for everything — a different engine build, a font swap, a typo in the walk — the
## scan below would pass on a screen full of blanks and say so confidently. So first
## prove the instrument still reports a known-absent glyph as absent.
func _test_the_probe_can_fail() -> void:
	if _font == null:
		_fail("no font resolved at all — the scan below would be vacuous")
		return
	if not _font.has_char(0x0041):
		_fail("the font cannot draw 'A', so the probe is broken rather than the strings")
	# U+1F600, outside every desktop UI font's normal coverage. If this is ever drawable
	# the font has full Unicode coverage, and the ban below can simply be lifted.
	if _font.has_char(0x1F600):
		_fail("the font reports coverage of U+1F600 — either it now has full Unicode "
			+ "coverage (in which case delete this suite and restore the glyphs) or "
			+ "`has_char` is not answering, and the scan below proves nothing")


func _test_no_undrawable_glyph_reaches_a_control() -> void:
	if _font == null:
		return
	for dir: String in SCAN_DIRS:
		_scan_dir(dir)


func _scan_dir(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		_fail("cannot open %s — the scan would silently cover nothing" % path)
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		var full: String = path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(full)
		elif name.ends_with(".gd"):
			_scan_file(full)
		name = d.get_next()
	d.list_dir_end()


func _scan_file(path: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	_checked_files += 1
	var n: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		n += 1
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		# Trailing comments are cut too: a `# ⚠ ...` note after real code is prose.
		var hash_at: int = line.find("#")
		var code: String = line.substr(0, hash_at) if hash_at >= 0 else line
		# Console output is the ONE exempt sink: a terminal renders what a UI font cannot,
		# and the debug prints in this codebase lean on arrows and rules heavily.
		var to_console: bool = false
		for sink: String in CONSOLE_SINKS:
			if code.contains(sink):
				to_console = true
				break
		if to_console or not code.contains("\""):
			continue
		_checked_lines += 1
		for i: int in code.length():
			var cp: int = code.unicode_at(i)
			if cp < 0x0100 or WAIVED.has(cp):
				continue
			if not _font.has_char(cp):
				_fail("%s:%d puts U+%04X on screen and the font cannot draw it — it "
					% [path, n, cp]
					+ "renders as nothing at all, with no error. Use a character the "
					+ "font has, or draw the shape (a StyleBoxFlat border is what the "
					+ "class roster and the colour picker both use for their swatch).")
	f.close()
