# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_reachability.gd
#
# ══ WHAT IS BUILT BUT CANNOT BE REACHED BY A PLAYER? ═══════════════════════════
#
# This exists because of a real bug, and the bug's shape is the point.
#
# The wall two-beat — punch a standing wall and it answers — was built, tested,
# documented, and callable from exactly ONE place: `scripts/spike/SpellPlaygroundController.gd`.
# In the Arena, on every tower floor and in every bot fight, no press could reach it. The
# maker reviewed those spells IN the playground, watched it work, and asked for more of it,
# while the build they would actually ship did not have the feature at all.
#
# **It was not broken.** Every unit test of it passed, because every unit test drove it
# directly. "Does this work" and "can a player reach this" are different questions, and a
# suite that only ever asks the first cannot report the second no matter how green it is.
#
# So this walks the shipping source and reports every public entry point whose only callers
# live in trees the export STRIPS — `scripts/spike/`, `scenes/spike/` and `tools/`. A
# function used only by a probe proves the function exists. It does not prove the game uses
# it.
#
# ⚠ THIS IS A REPORT, NOT A GUARD, AND DELIBERATELY SO. Plenty of entries below are
# correct and intentional: capture tooling reaches into systems on purpose, and some
# functions are honest public API with no caller yet. A test that failed on all of them
# would be turned off within a week. The one thing worth pinning as a test is a SPECIFIC
# feature somebody has decided must be reachable — see `slice_test_wall_reachable.gd`,
# which does exactly that for the shove entry point. Read this list, then promote what
# matters.
#
# ⚠ IT IS ALSO TEXTUAL, and therefore blind in both directions: a call assembled through
# `call("name")` or a signal is invisible to it, and a name that happens to be a substring
# of another is over-counted. Names shorter than MIN_NAME are skipped for that reason.
extends SceneTree

## Trees the export strips. A caller here is, from a shipped build's view, no caller.
const UNSHIPPED: Array[String] = ["res://scripts/spike/", "res://scenes/spike/", "res://tools/"]
## Where the game itself lives.
const SHIPPING_ROOT: String = "res://scripts/"
## Short names collide with ordinary words and with each other; a report full of false
## positives is a report nobody reads.
const MIN_NAME: int = 8
## Godot lifecycle and common overrides — a caller for these is the ENGINE, not a script.
const ENGINE_HOOKS: Array[String] = [
	"_process", "_physics_process", "_ready", "_init", "_enter_tree", "_exit_tree",
	"_draw", "_input", "_unhandled_input", "_gui_input", "_notification", "_get",
	"_set", "_to_string", "_integrate_forces", "_shortcut_input",
]


func _process(_delta: float) -> bool:
	var files: Array[String] = []
	_gd_files(SHIPPING_ROOT, files)
	for root: String in UNSHIPPED:
		_gd_files(root, files)
	# name -> {"decl": path, "shipping": int, "unshipped": Array[String]}
	var decls: Dictionary = {}
	var sources: Dictionary = {}
	for path: String in files:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var src: String = f.get_as_text()
		sources[path] = src
		if _is_unshipped(path):
			continue                      # only SHIPPING code declares things we care about
		for line: String in src.split("\n"):
			var t: String = line.strip_edges()
			if not (t.begins_with("func ") or t.begins_with("static func ")):
				continue
			var after: String = t.substr(t.find("func ") + 5)
			var name: String = after.substr(0, maxi(after.find("("), 0))
			if name.length() < MIN_NAME or ENGINE_HOOKS.has(name):
				continue
			if name.begins_with("_"):
				continue                  # private by convention; not an entry point
			decls[name] = path

	var findings: Array = []
	for name: String in decls:
		var home: String = String(decls[name])
		var shipping: int = 0
		var unshipped: Array[String] = []
		for path: String in sources:
			if path == home:
				continue                  # its own file is not evidence of reach
			if not _calls(String(sources[path]), name):
				continue
			if _is_unshipped(path):
				unshipped.append(path.replace("res://", ""))
			else:
				shipping += 1
		if shipping == 0 and not unshipped.is_empty():
			findings.append({"name": name, "home": home, "by": unshipped})

	findings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["home"]) < String(b["home"]))
	print("")
	print("== ENTRY POINTS WITH NO SHIPPING CALLER ==")
	print("   (declared in scripts/, called only from spike/ or tools/)")
	print("")
	for f: Dictionary in findings:
		print("  %-34s  %s" % [String(f["name"]), String(f["home"]).replace("res://scripts/", "")])
		print("        reached only by: %s" % ", ".join(f["by"]))
	print("")
	print("SUMMARY: %d of %d public entry points have no shipping caller."
		% [findings.size(), decls.size()])
	print("A name here is a QUESTION, not a defect — read the list, promote what matters.")
	quit(0)
	return true


func _is_unshipped(path: String) -> bool:
	for prefix: String in UNSHIPPED:
		if path.begins_with(prefix):
			return true
	return false


## A real call, not a mention: comment lines dropped, a trailing `(` required, and `func `
## excluded so a declaration cannot count as a use of itself. The first version of the
## sibling guard counted prose and passed its own revert-test on the strength of a comment.
func _calls(src: String, name: String) -> bool:
	for line: String in src.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("#"):
			continue
		var at: int = t.find(name + "(")
		if at < 0:
			continue
		if t.substr(0, at).ends_with("func "):
			continue
		return true
	return false


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
