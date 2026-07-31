# Run: godot --headless --path godot-project --script tools/release_gate_dev_bridge.gd
#
# ⚠ THIS IS A RELEASE GATE, NOT A REGRESSION SUITE. It is EXPECTED TO FAIL during
# development and MUST pass before any build that leaves this machine. Do not
# "fix" a red run by deleting the check; fix it by doing what it prints.
#
# ---------------------------------------------------------------------------
# WHAT IT GUARDS
#
# `MCPRuntime` is an autoload (project.godot [autoload]) pointing at
# addons/godot_mcp_runtime/. It is a WebSocket DEV BRIDGE: it opens a listening
# socket on port 7777 at boot and exposes live scene-tree introspection and
# performance monitors to anything that connects. On a desktop, behind a home
# router, while the maker is building the game, that is the single most useful
# tool in the project. In a shipping mobile app it is a listening socket and a
# remote introspection surface on a stranger's phone.
#
# Autoloads ARE exported. There is no "debug only" flag on them.
#
# ---------------------------------------------------------------------------
# WHY THIS IS A CHECKLIST GATE AND NOT AN AUTOMATIC FIX
#
# The obvious answer is a Godot feature-tag override — the same mechanism that
# lets `renderer/rendering_method.mobile` swap the renderer per platform. It does
# not work for autoloads. MEASURED, not assumed: with
#
#     [autoload]
#     MCPRuntime="*uid://qc4i28l1mvja"
#     MCPRuntime.windows=""
#
# on a Windows run, a boot probe printed
#
#     PROBE root children:      [MCPRuntime, Conversation, Sfx, ...]
#     PROBE autoload settings:  [autoload/MCPRuntime, autoload/MCPRuntime.windows, ...]
#     ERROR: Failed to create an autoload, can't load from UID or path: .
#
# — the bridge still loaded, the dotted name registered as a SECOND, SEPARATE
# autoload rather than an override, and the empty path spammed a boot error. It
# is worse than doing nothing. The cause is in the engine: ProjectSettings::_set
# intercepts any key beginning `autoload/` before the override machinery is
# consulted, and takes the node name as everything after the first slash — so
# `MCPRuntime.mobile` is simply a different autoload called "MCPRuntime.mobile".
# Only `get_setting_with_override()` reads the override map, and autoload
# registration never calls it.
#
# So the autoload stays (the maker uses the bridge every session, and deleting it
# would take the whole MCP workflow with it) and REMOVAL IS A MANUAL PRE-RELEASE
# STEP. This gate is what makes forgetting it impossible rather than merely
# unlikely. Belt and braces: the Android export preset also excludes
# addons/godot_mcp_runtime/*, so even a forgotten autoload cannot find its
# script in the pack — but that leaves a boot error in a shipping build, which
# is why it is a backstop and not the plan.
#
# See docs/mobile-export.md for the exact edit.
extends SceneTree

## Autoloads that must not exist in a shipping build, and why.
const DEV_AUTOLOADS: Dictionary = {
	"MCPRuntime": "WebSocket dev bridge — opens a listening socket + live scene introspection at boot",
}
## Addon directories that must be excluded by the export preset.
const DEV_ADDONS: Array[String] = [
	"res://addons/godot_mcp_runtime/*",
	"res://addons/godot_mcp_editor/*",
	"res://addons/auto_reload/*",
]

var _ran: bool = false
var _blockers: Array[String] = []


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_check_autoloads()
	_check_export_excludes()
	if _blockers.is_empty():
		print("Release gate: PASS — no dev bridge in the shipping surface.")
		quit(0)
		return true
	printerr("")
	printerr("=====================================================================")
	printerr(" RELEASE GATE FAILED — %d SHIP BLOCKER(S)" % _blockers.size())
	printerr("=====================================================================")
	for b: String in _blockers:
		printerr("  * " + b)
	printerr("")
	printerr(" This gate is EXPECTED to be red during development.")
	printerr(" It must be green before an APK/AAB leaves this machine.")
	printerr(" Fix + full context: docs/mobile-export.md")
	printerr("=====================================================================")
	quit(1)
	return true


## Read project.godot as TEXT rather than asking ProjectSettings. Two reasons:
## autoload singletons are not registered under `--script`, so asking the tree is
## not an option; and the file is the artefact that actually ships, so the file is
## the thing worth asserting about.
func _check_autoloads() -> void:
	var text: String = FileAccess.get_file_as_string("res://project.godot")
	if text.is_empty():
		_blockers.append("project.godot could not be read — cannot verify the autoload list")
		return
	var in_autoload: bool = false
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("["):
			in_autoload = line == "[autoload]"
			continue
		if not in_autoload or line.is_empty() or line.begins_with(";"):
			continue
		var name: String = line.get_slice("=", 0).strip_edges()
		if DEV_AUTOLOADS.has(name):
			_blockers.append(
				"`%s` is still in project.godot [autoload] — %s.\n" % [name, DEV_AUTOLOADS[name]]
				+ "      REMOVE the line `%s` from the [autoload] section, export, then put it back." % line)


func _check_export_excludes() -> void:
	if not FileAccess.file_exists("res://export_presets.cfg"):
		_blockers.append("export_presets.cfg is missing — there is no Android preset to ship")
		return
	var text: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	for addon: String in DEV_ADDONS:
		if not text.contains(addon):
			_blockers.append(
				"the export preset no longer excludes `%s` — dev addon code would ship" % addon)
