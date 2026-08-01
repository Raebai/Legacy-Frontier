# Run: godot --headless --path godot-project --script tools/release_gate_dev_bridge.gd
#
# ⚠ THIS IS A RELEASE GATE, NOT A REGRESSION SUITE. It is EXPECTED TO FAIL during
# development and MUST pass before any build that leaves this machine. Do not
# "fix" a red run by deleting the check; fix it by doing what it prints.
#
# The checks themselves live in `tools/release_gate_lib.gd` as pure functions
# over file TEXT, and `tools/slice_test_release_gate.gd` exercises every one of
# them in BOTH directions against synthetic inputs. That split exists because
# this gate is red by design most of the time, so a live run can only ever
# demonstrate the failure path — the PASS branch needs its own proof.
#
# ---------------------------------------------------------------------------
# WHAT IT GUARDS — TWO THINGS NOW
#
# 1. `MCPRuntime` (project.godot [autoload]) -> addons/godot_mcp_runtime/.
#    A WebSocket DEV BRIDGE: it opens a listening socket on port 7777 at boot and
#    exposes live scene-tree introspection and performance monitors to anything
#    that connects. On a desktop, behind a home router, while the maker is
#    building the game, that is the single most useful tool in the project. In a
#    shipping mobile app it is a listening socket and a remote introspection
#    surface on a stranger's phone.
#
#    Autoloads ARE exported. There is no "debug only" flag on them.
#
# 2. THE DIRECTOR (`tools/director/Director.gd`) — the debug review rig: jump to
#    any floor, summon any boss with any modifiers, switch class live, grant any
#    spell, spawn any archetype, god mode, slow motion, frame step.
#
#    Its primary gate is that it is NOT IN THE PACK: `res://tools/*` is in the
#    preset's `exclude_filter`, so on a device the script does not exist and
#    `PauseMenu.director_available()` finds nothing. Its second gate is
#    `OS.is_debug_build()` in `PauseMenu.gd`, which is what keeps it off a
#    sideloaded DEBUG apk if the exclude list is ever edited. This gate asserts
#    both, plus that no shipped script `preload`s a `res://tools/` path (a
#    preload resolves at compile time and would defeat the exclude outright).
#
# ---------------------------------------------------------------------------
# WHY THE AUTOLOAD IS A CHECKLIST GATE AND NOT AN AUTOMATIC FIX
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
# unlikely. Note the contrast with the director, which needed no such compromise:
# nothing in the shipped game imports it, so excluding it from the pack costs
# nothing and requires no pre-release ritual at all.
#
# See docs/mobile-export.md for the exact edits.
extends SceneTree

const Lib := preload("res://tools/release_gate_lib.gd")

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var blockers: Array[String] = Lib.check_all(
		FileAccess.get_file_as_string("res://project.godot"),
		_read_or_empty("res://export_presets.cfg"),
		_read_or_empty(Lib.DIRECTOR_HOST))
	if blockers.is_empty():
		print("Release gate: PASS — no dev bridge and no director in the shipping surface.")
		quit(0)
		return true
	printerr("")
	printerr("=====================================================================")
	printerr(" RELEASE GATE FAILED — %d SHIP BLOCKER(S)" % blockers.size())
	printerr("=====================================================================")
	for b: String in blockers:
		printerr("  * " + b)
	printerr("")
	printerr(" This gate is EXPECTED to be red during development.")
	printerr(" It must be green before an APK/AAB leaves this machine.")
	printerr(" Fix + full context: docs/mobile-export.md")
	printerr("=====================================================================")
	quit(1)
	return true


## `FileAccess.get_file_as_string` on a missing path returns "" but also logs an
## engine error, which reads like a crash in the gate's own output. Existence is
## a legitimate answer here (a missing preset IS a blocker), so ask first.
func _read_or_empty(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
