# The release gate's CHECKS, as pure functions over TEXT.
# ============================================================================
#
# Split out of `release_gate_dev_bridge.gd` for one reason: a gate that can only
# ever be observed RED is a gate nobody trusts. The live gate is red by design
# during development (the MCP dev bridge is in `[autoload]` and the maker uses it
# every session), so "it printed FAILED" proves nothing about whether it would
# ever print PASS — or whether the PASS branch even works.
#
# Every check below takes the FILE TEXT and returns a list of blocker strings.
# That makes both answers testable from a suite that never touches the real
# project files: `tools/slice_test_release_gate.gd` feeds each check a clean text
# and asserts zero blockers, then a dirty text and asserts the exact blocker.
#
# TEXT, not `ProjectSettings`, throughout. Two reasons, both learned here:
#   * autoload singletons are NOT registered under `--script`, so asking the tree
#     is not an option;
#   * `ProjectSettings.get_setting()` answers from built-in engine defaults even
#     when our line has been deleted, so it cannot see the deletion that matters.
# The file is the artefact that ships, so the file is the thing worth asserting.
extends RefCounted

## Autoloads that must not exist in a shipping build, and why.
const DEV_AUTOLOADS: Dictionary = {
	"MCPRuntime": "WebSocket dev bridge — opens a listening socket + live scene introspection at boot",
}

## Paths the export preset must exclude from the pack.
##
## `res://tools/*` is the one that keeps THE DIRECTOR out of a shipping build.
## The director is a full debug rig — jump floors, summon any boss, grant any
## spell, god mode — and it is not gated by a runtime flag it could be talked out
## of. It simply is not in the pack. That is only true while this line is.
const DEV_PATHS: Array[String] = [
	"res://tools/*",
	"res://addons/godot_mcp_runtime/*",
	"res://addons/godot_mcp_editor/*",
	"res://addons/auto_reload/*",
]

## The director's second, independent gate lives in this shipped file.
const DIRECTOR_HOST: String = "res://scripts/combat/PauseMenu.gd"
## The guard that must survive in it.
const DIRECTOR_GUARD: String = "OS.is_debug_build()"
## What must never appear in a shipped script. A `preload` is resolved at COMPILE
## time, so preloading an excluded path does not merely leak the file — it makes
## the export fail to build, or worse, silently pulls `res://tools/` back into
## the pack. `load()` of the same path is fine: at runtime, on a device, it
## simply returns null and the feature does not exist.
const BANNED_PRELOAD: String = "preload(\"res://tools/"


## Everything, in one call. `pause_menu_text` may be empty when the caller could
## not read it — that is itself reported, rather than passing by omission.
static func check_all(project_text: String, preset_text: String, host_text: String) -> Array[String]:
	var out: Array[String] = []
	out.append_array(check_autoloads(project_text))
	out.append_array(check_export_excludes(preset_text))
	out.append_array(check_director(host_text))
	return out


## No dev autoload may be in `[autoload]`. Parsed rather than substring-matched
## so a mention in a comment elsewhere in project.godot cannot trip it, and so
## the blocker can print the exact line to delete.
static func check_autoloads(text: String) -> Array[String]:
	var out: Array[String] = []
	if text.is_empty():
		out.append("project.godot could not be read — cannot verify the autoload list")
		return out
	var in_autoload: bool = false
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("["):
			in_autoload = line == "[autoload]"
			continue
		if not in_autoload or line.is_empty() or line.begins_with(";"):
			continue
		var key: String = line.get_slice("=", 0).strip_edges()
		if DEV_AUTOLOADS.has(key):
			out.append(
				"`%s` is still in project.godot [autoload] — %s.\n" % [key, DEV_AUTOLOADS[key]]
				+ "      REMOVE the line `%s` from the [autoload] section, export, then put it back." % line)
	return out


## The preset must exclude every dev path. Checked against the `exclude_filter`
## line specifically: the paths also appear in this file's own comments, and a
## whole-file substring match would pass on a preset that mentions them in a
## comment and excludes nothing.
static func check_export_excludes(text: String) -> Array[String]:
	var out: Array[String] = []
	if text.is_empty():
		out.append("export_presets.cfg is missing — there is no Android preset to ship")
		return out
	var filter_line: String = ""
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("exclude_filter"):
			filter_line = line
			break
	if filter_line.is_empty():
		out.append("export_presets.cfg has no `exclude_filter` line — every dev path would ship")
		return out
	for path: String in DEV_PATHS:
		if not filter_line.contains(path):
			out.append(
				"the export preset no longer excludes `%s` — dev code would ship.\n" % path
				+ "      Add it back to `exclude_filter` in export_presets.cfg.")
	return out


## THE DIRECTOR'S SECOND GATE, in the shipped file that hosts it.
##
## The first gate (the script is not in the pack) is enforced by
## `check_export_excludes` above. This one catches the case that gate cannot: a
## DEBUG APK, sideloaded to a phone, built from a preset somebody edited.
static func check_director(host_text: String) -> Array[String]:
	var out: Array[String] = []
	if host_text.is_empty():
		out.append("%s could not be read — cannot verify the director's debug gate" % DIRECTOR_HOST)
		return out
	if not host_text.contains(DIRECTOR_GUARD):
		out.append(
			"`%s` has lost its `%s` guard — the DIRECTOR would be reachable in a\n" % [DIRECTOR_HOST, DIRECTOR_GUARD]
			+ "      release build. Restore the guard in `director_available()`.")
	if host_text.contains(BANNED_PRELOAD):
		out.append(
			"`%s` PRELOADS a `res://tools/` path. preload() resolves at compile time,\n" % DIRECTOR_HOST
			+ "      so it defeats the export exclude that keeps the director out of the pack.\n"
			+ "      Use `load()` behind `director_available()` instead.")
	return out
