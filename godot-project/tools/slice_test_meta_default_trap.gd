# Run: godot --headless --path godot-project --script tools/slice_test_meta_default_trap.gd
#
# `get_meta(name, null)` IS NOT A DEFAULT — IT IS AN ERROR WAITING FOR AN ABSENT KEY.
#
# ⚠ THE TRAP. Godot decides whether a default was supplied by comparing it against
# `Variant()`. `null` IS `Variant()`. So `get_meta(KEY, null)` is indistinguishable from
# `get_meta(KEY)`, and on a missing key it does not return null — it pushes
#
#     The object does not have any 'meta' values with the key '<KEY>'.
#
# It reads exactly like defensive code and behaves like the undefended call.
#
# ⚠ NOT HYPOTHETICAL. Four sites had it, and two were firing constantly before anyone
# noticed, because a pushed error is not fatal and nothing was reading stderr:
#   * `CastName._heavy_label`  — every fighter's FIRST heavy cast, every bout.
#   * `Lobby._btn_scale`       — three errors before the title screen finished loading.
#   * `Hero._nearest_thrall`   — once per unstamped thrall per scan, per frame.
#   * `slice_test_thrall`      — in the suite that is supposed to be checking this.
#
# The fix is always `has_meta(KEY)` first, or a non-null sentinel default.
#
# ⚠ THIS IS A SOURCE LINT, and it is deliberately narrow: it matches only the literal
# `null` default, which is never correct and never a false positive. It does NOT try to
# police the wider family (`is` before `is_instance_valid`), because that ordering is
# harmless on a fresh group scan and a lint that cries wolf on ~36 harmless sites is a
# lint people learn to skip — see the anomaly-spam lesson in the bot-probe work.
extends SceneTree

const ROOTS: Array[String] = ["res://scripts", "res://tools", "res://addons"]

## The offending shape. `[^)]*` keeps it on one argument list so a later `, null` in a
## different call on the same line cannot produce a phantom hit.
const PATTERN: String = "get_meta\\([^)]*,\\s*null\\s*\\)"

var _fails: int = 0
var _scanned: int = 0
var _hits: Array[String] = []


func _initialize() -> void:
	var re := RegEx.new()
	if re.compile(PATTERN) != OK:
		printerr("meta_default: FAIL — the lint's own regex did not compile")
		printerr("meta default tests: 1 FAILED")
		quit(1)
		return
	for root: String in ROOTS:
		_scan(root, re)

	# ⚠ A LINT THAT SCANNED NOTHING PASSES. Pin the reach, or a broken walk reads as a
	# clean codebase — the exact vacuous-pass shape this repo keeps getting caught by.
	if _scanned < 200:
		_fails += 1
		printerr("meta_default: FAIL — only %d .gd files scanned; the walk is broken, "
			% _scanned + "and a lint that reads nothing always passes")

	for h: String in _hits:
		_fails += 1
		printerr("meta_default: FAIL — %s" % h)

	if _fails > 0:
		printerr("meta default tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("meta default tests: all PASS (%d files scanned)" % _scanned)
		quit(0)


func _scan(dir_path: String, re: RegEx) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full: String = dir_path.path_join(name)
		if d.current_is_dir():
			_scan(full, re)
		elif name.ends_with(".gd"):
			_check(full, re)
		name = d.get_next()
	d.list_dir_end()


func _check(path: String, re: RegEx) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	_scanned += 1
	var line_no: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		line_no += 1
		# Skip comment-only lines so this file's own documentation of the trap, and any
		# other write-up of it, cannot fail the build.
		if line.strip_edges().begins_with("#"):
			continue
		if re.search(line) != null:
			# ⚠ THE MESSAGE MUST NOT CONTAIN THE PATTERN IT DESCRIBES. Spelling the call
			# out literally here made this lint fail on its own error string — and the
			# tempting fix, exempting this file from the walk, would have given the lint
			# a permanent blind spot in the one file most likely to discuss the trap.
			_hits.append("%s:%d — a null meta default is NOT a default (Godot cannot "
				% [path, line_no] + "tell it from no default and errors instead); call "
				+ "has_meta() first. Line: %s" % line.strip_edges())
	f.close()
