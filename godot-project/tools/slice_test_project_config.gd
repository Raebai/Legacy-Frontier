# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_project_config.gd
#
# ══ THE FILE THAT LOOKS RIGHT AND IS NOT ══════════════════════════════════════
#
# `project.godot` is NOT an ini file and it is NOT a shell script. It is parsed by
# Godot's own VariantParser, whose ONLY comment character is ';'. A line beginning
# with '#' is not skipped — it is a PARSE ERROR, and the parser's recovery swallows
# THE ASSIGNMENT THAT FOLLOWS IT.
#
# That cost this project a week of Android. The commit `84caf09` — "Android refused
# the export outright for want of ETC2/ASTC textures" — added exactly this:
#
#     # ANDROID REQUIRES ETC2/ASTC. Without this the export dialog refuses ...
#     # ...four more lines of correct, careful explanation...
#     textures/vram_compression/import_etc2_astc=true
#
# The setting the block was written to document was the setting the block switched
# off. `grep` found the line. Every human who opened the file read it as set. And
# `ProjectSettings.get_setting(...)` returned **false**, so every Android export
# kept failing — with a BLANK error body, because the Android exporter's ETC2 check
# sets `valid = false` without writing a message into the string headless prints.
# Four separate signals all read "fixed" while the build stayed broken.
#
# So this suite pins the two halves that have to be true together:
#   1. THE TEXT — no '#'-led line anywhere in project.godot. This is the cheap,
#      general guard: it catches the NEXT person documenting the NEXT setting,
#      whatever that setting turns out to be.
#   2. THE VALUE — the settings that gate a platform are read back through
#      `ProjectSettings` and asserted on their VALUE, not on their presence in the
#      file. Presence is what lied. Only the parsed value is evidence.
#
# ⚠ WHY BOTH, when (2) alone would have caught this one. (2) only covers settings
# somebody thought to list here, and the failure mode is silent for every setting
# nobody listed. (1) covers the whole file forever and costs one string scan.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead property read ABORTS the enclosing function and returns the type's zero,
# which `failed += _test_x()` would read as "no failures". So failures accumulate on
# the MEMBER `_fails`, and every test records a completion sentinel as its last line:
# a test that aborts part-way is then missing from `_completed` and fails BY ABSENCE.
const TESTS: Array[String] = [
	"no_hash_comments_in_project_godot",
	"platform_gating_settings_read_back_true",
	"semicolon_comments_do_not_eat_the_next_line",
]

## Settings whose VALUE gates a platform export, and the value each must hold.
##
## ⚠ ASSERTED ON THE PARSED VALUE, NEVER ON THE FILE TEXT. The text is the thing
## that lied. `import_etc2_astc` is the one that cost the week: without it true at
## runtime, `EditorExportPlatformAndroid::has_valid_project_configuration` refuses
## the export and — in headless — refuses it with an EMPTY reason.
const GATING_SETTINGS: Dictionary = {
	"rendering/textures/vram_compression/import_etc2_astc": true,
}

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_no_hash_comments()
	_test_gating_settings()
	_test_semicolon_is_the_comment_char()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Project-config tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Project-config tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _project_godot_lines() -> PackedStringArray:
	var f: FileAccess = FileAccess.open("res://project.godot", FileAccess.READ)
	if f == null:
		return PackedStringArray()
	return f.get_as_text().split("\n")


# ------------------------------------------------------------------------- 1
## No '#'-led line, anywhere. See the header: '#' is a parse error whose recovery
## eats the following assignment, so a '#' comment is a loaded gun pointed at
## whichever setting the author put underneath it — which is, by construction,
## always the setting they cared about enough to explain.
func _test_no_hash_comments() -> void:
	var lines: PackedStringArray = _project_godot_lines()
	_expect(lines.size() > 0, "project.godot is readable (it could not be opened)")
	var offenders: Array[String] = []
	for i: int in range(lines.size()):
		if lines[i].strip_edges().begins_with("#"):
			offenders.append("line %d: %s" % [i + 1, lines[i].strip_edges().substr(0, 60)])
	_expect(offenders.is_empty(),
		("project.godot has %d '#' comment line(s) — '#' is NOT a comment in Godot's "
		+ "VariantParser, it is a parse error that SWALLOWS THE NEXT ASSIGNMENT. Use ';'. "
		+ "Offenders:\n    %s") % [offenders.size(), "\n    ".join(offenders)])
	_completes("no_hash_comments_in_project_godot")


# ------------------------------------------------------------------------- 2
## The platform gates, read back through the parser. Presence in the file proves
## nothing — presence is exactly what was true while the value was false.
func _test_gating_settings() -> void:
	for key: String in GATING_SETTINGS:
		var want: Variant = GATING_SETTINGS[key]
		_expect(ProjectSettings.has_setting(key),
			"project setting '%s' is declared" % key)
		var got: Variant = ProjectSettings.get_setting(key, null)
		_expect(got == want,
			("project setting '%s' PARSES to %s, not %s. The line can be present and "
			+ "still not take: check for a '#' comment immediately above it.")
			% [key, str(got), str(want)])
	_completes("platform_gating_settings_read_back_true")


# ------------------------------------------------------------------------- 3
## The positive control: prove ';' really is the comment character, so that test 1
## is enforcing a rule that HAS a working alternative rather than banning comments.
##
## Written as a live parse of a throwaway file rather than as a claim about the
## engine, because "I believe ';' works" is the same class of statement as "I believe
## the setting is on", and that statement is what this whole suite exists about.
func _test_semicolon_is_the_comment_char() -> void:
	var path: String = "user://_project_config_probe.cfg"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(f != null, "probe file is writable")
	if f == null:
		return
	f.store_string("[probe]\n; a semicolon comment\nafter_semicolon=41\n")
	f.close()
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(path)
	_expect(err == OK, "a ';'-commented config parses cleanly (got error %d)" % err)
	_expect(int(cfg.get_value("probe", "after_semicolon", -1)) == 41,
		"the assignment AFTER a ';' comment survives — ';' is the comment character")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_completes("semicolon_comments_do_not_eat_the_next_line")
