# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_wall_reachable.gd
#
# ══ THE FEATURE THAT ONLY EXISTED IN THE PLAYGROUND ════════════════════════════
#
# The wall two-beat — punch a standing wall and it answers, rock by sliding, ice by
# bursting — was built, tested, documented and reachable from exactly ONE place:
# `scripts/spike/SpellPlaygroundController.gd`. `RockWall.find_shoveable_near` had a
# single caller in the entire repo and it was a spike.
#
# So in the Arena, on every tower floor and in every bot fight, no press could shove or
# detonate a wall. The claim tell never lit, the grinding ram never ran, and the ice
# wall's detonate was unreachable.
#
# That is the worst shape a feature can take, and it is worth naming precisely: it is not
# broken. Every unit test of it passes, because every unit test drives it directly. The
# maker reviewed these spells IN the playground, watched the two-beat work, and asked for
# more of it — while the build they would actually ship did not have it at all. Nothing in
# the suite could tell them, because "does this work" and "can a player reach this" are
# different questions and only the first was being asked.
#
# WHAT IS PINNED: the shove entry point has a caller that a PLAYER can reach. Spike
# scripts under `scripts/spike/` and `scenes/spike/` are excluded from the export
# (`slice_test_release_gate` enforces that), so a caller that lives only there is, from a
# shipped build's point of view, no caller at all.
#
# ⚠ THIS IS A SOURCE-LEVEL GUARD AND IT IS WEAKER THAN A BEHAVIOURAL ONE. It cannot tell
# you the shove FEELS right, or that the facing gate is tuned, or that the wall was in
# reach — `slice_test_wall_two_beat` and `slice_test_wall_identity` own those questions
# and drive the real objects. What this one catches is the failure those cannot see by
# construction: the day somebody refactors the melee path and the last shipping caller
# quietly goes away again, leaving the behavioural suites green because they never needed
# a caller in the first place.
extends SceneTree

## The one function a player's press has to reach for any of it to exist.
const ENTRY: String = "find_shoveable_near"
## Where a caller does NOT count. These trees are stripped from every export preset.
const UNSHIPPED_PREFIXES: Array[String] = ["res://scripts/spike/", "res://scenes/spike/"]
## Where to look. `tools/` is excluded for the same reason as `spike/` — a probe calling
## it proves the function exists, not that the game uses it.
const SEARCH_ROOTS: Array[String] = ["res://scripts/"]

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
const TESTS: Array[String] = [
	"the_shove_entry_point_still_exists",
	"a_shipping_script_calls_it",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_entry_exists()
	_test_shipping_caller()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Wall-reachable tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Wall-reachable tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Every `.gd` under `root`, recursively.
func _gd_files(root: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = root.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_gd_files(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


# ------------------------------------------------------------------------- 1
## If the entry point is renamed, everything below becomes vacuously true — it would
## find zero callers of a name nothing has, and "zero shipping callers" is exactly the
## failure this suite reports. So the name is checked to still mean something first.
func _test_entry_exists() -> void:
	var f: FileAccess = FileAccess.open("res://scripts/combat/RockWall.gd", FileAccess.READ)
	_expect(f != null, "RockWall.gd is readable")
	if f == null:
		return
	_expect(f.get_as_text().contains("func " + ENTRY),
		("`RockWall.%s` no longer exists. If it was renamed, rename it in ENTRY too — "
		+ "otherwise this whole suite passes by finding nothing.") % ENTRY)
	_completes("the_shove_entry_point_still_exists")


# ------------------------------------------------------------------------- 2
func _test_shipping_caller() -> void:
	var files: Array[String] = []
	for root: String in SEARCH_ROOTS:
		_gd_files(root, files)
	_expect(files.size() > 20, "the source tree was actually walked (%d files)" % files.size())
	var shipping: Array[String] = []
	var unshipped: Array[String] = []
	for path: String in files:
		if path.ends_with("RockWall.gd"):
			continue    # the definition, not a caller
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		# ⚠ CODE, NOT PROSE. The first version of this counted any file whose text
		# contained the name — and `IceWall.gd` mentions it twice in comments explaining
		# the duck-typed contract it implements. So the guard reported two shipping
		# callers when there was one, and PASSED its own revert-test: stripping the real
		# caller out of `Hero.gd` left a comment still holding the fort. Comment lines are
		# dropped, and the match requires an actual call — a trailing `(` — with `func `
		# excluded so a definition cannot count as a use of itself.
		if not _calls_entry(f.get_as_text()):
			continue
		var is_spike: bool = false
		for prefix: String in UNSHIPPED_PREFIXES:
			if path.begins_with(prefix):
				is_spike = true
				break
		if is_spike:
			unshipped.append(path)
		else:
			shipping.append(path)
	_expect(not shipping.is_empty(),
		("`%s` has no caller a player can reach — %d caller(s), all in trees the export "
		+ "strips (%s). The wall two-beat is built, tested and unreachable: every unit "
		+ "test of it passes because they drive it directly.")
		% [ENTRY, unshipped.size(), ", ".join(unshipped)])
	print("  %s: %d shipping caller(s) %s, %d spike-only"
		% [ENTRY, shipping.size(), str(shipping), unshipped.size()])
	_completes("a_shipping_script_calls_it")


## Does this source actually CALL the entry point, as opposed to mentioning it?
func _calls_entry(src: String) -> bool:
	for line: String in src.split("
"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var at: int = trimmed.find(ENTRY + "(")
		if at < 0:
			continue
		if trimmed.substr(0, at).ends_with("func "):
			continue    # the definition, not a call
		return true
	return false
