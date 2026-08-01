# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_release_gate.gd
#
# THE GATE MUST BE ABLE TO SAY YES.
#
# `tools/release_gate_dev_bridge.gd` is red by design during development — the
# MCP dev bridge is in `[autoload]` and the maker uses it every session. So a
# live run of the gate can only ever demonstrate the FAILURE path. Nothing about
# it proves the PASS branch is reachable, or that a check would notice the thing
# it exists to notice.
#
# A gate that can only be red gets ignored. So every check is exercised here in
# BOTH directions against synthetic text: clean input -> zero blockers, dirty
# input -> exactly the blocker that names the problem.
#
# What is being guarded, restated: the MCP WebSocket dev bridge must not ship,
# and neither must THE DIRECTOR — the debug review rig that can jump floors,
# summon any boss with any modifiers, grant any spell and turn on god mode. The
# director's primary gate is that `res://tools/*` is excluded from the export
# pack; its second is the `OS.is_debug_build()` guard in the shipped
# `PauseMenu.gd`. Both are asserted below, in both directions.
extends SceneTree

const Lib := preload("res://tools/release_gate_lib.gd")

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion
# sentinel as its last line, so a test that aborts part-way fails BY ABSENCE.

const TESTS: Array[String] = [
	"clean_input_produces_no_blockers",
	"dev_autoload_is_caught",
	"autoload_check_is_section_scoped",
	"missing_tools_exclude_is_caught",
	"missing_addon_exclude_is_caught",
	"commented_out_exclude_does_not_count",
	"director_guard_removal_is_caught",
	"director_preload_is_caught",
	"unreadable_inputs_are_blockers_not_silence",
	"the_real_shipped_files_still_satisfy_the_director_checks",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

# ── Synthetic inputs ────────────────────────────────────────────────────────
## A project.godot with the dev bridge REMOVED — i.e. what the file looks like
## on the one commit an APK is built from.
const CLEAN_PROJECT: String = """
config_version=5

[application]
config/name="Legacy Frontier"

[autoload]

Conversation="*res://scenes/Conversation.tscn"
Sfx="*res://scripts/combat/Sfx.gd"
GameState="*res://scripts/GameState.gd"

[display]
window/size/viewport_width=640
"""

const DIRTY_PROJECT: String = """
[autoload]

MCPRuntime="*uid://qc4i28l1mvja"
Sfx="*res://scripts/combat/Sfx.gd"
"""

## The dev-bridge name appearing OUTSIDE [autoload] must not trip the check —
## project.godot carries `[editor_plugins] enabled=` lines naming the same addon,
## and a substring match would make the gate permanently, uselessly red.
const PROJECT_MENTIONING_BRIDGE_ELSEWHERE: String = """
[autoload]

Sfx="*res://scripts/combat/Sfx.gd"

[editor_plugins]

enabled=PackedStringArray("res://addons/godot_mcp_runtime/plugin.cfg")

[some_other_section]

MCPRuntime="not an autoload, just a string"
"""

const CLEAN_PRESET: String = """
[preset.0]
name="Android"
[preset.0.options]
export_filter="all_resources"
exclude_filter="res://tools/*, res://addons/godot_mcp_runtime/*, res://addons/godot_mcp_editor/*, res://addons/auto_reload/*, res://scripts/spike/*"
"""

## `res://tools/*` dropped — the director would land in the pack.
const PRESET_WITHOUT_TOOLS: String = """
[preset.0.options]
exclude_filter="res://addons/godot_mcp_runtime/*, res://addons/godot_mcp_editor/*, res://addons/auto_reload/*"
"""

## The paths are all present as TEXT, but only in a comment; the real filter is
## empty. A whole-file substring match passes this and ships everything.
const PRESET_WITH_ONLY_A_COMMENT: String = """
[preset.0.options]
; exclude_filter should list res://tools/*, res://addons/godot_mcp_runtime/*,
; res://addons/godot_mcp_editor/*, res://addons/auto_reload/*
exclude_filter=""
"""

const CLEAN_HOST: String = """
static func director_available() -> bool:
	if not OS.is_debug_build():
		return false
	return ResourceLoader.exists(DIRECTOR_SCRIPT)
"""

const HOST_WITHOUT_GUARD: String = """
static func director_available() -> bool:
	return ResourceLoader.exists(DIRECTOR_SCRIPT)
"""

const HOST_WITH_PRELOAD: String = """
const D := preload("res://tools/director/Director.gd")
static func director_available() -> bool:
	if not OS.is_debug_build():
		return false
	return true
"""


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_clean()
	_test_dirty_autoload()
	_test_autoload_scoping()
	_test_missing_tools_exclude()
	_test_missing_addon_exclude()
	_test_commented_exclude()
	_test_guard_removed()
	_test_preload_banned()
	_test_unreadable()
	_test_real_files()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Release-gate tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("Release-gate tests: all PASS")
	quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## True when SOME blocker mentions `needle`. Matching on content rather than
## count so a check that fires for the right reason still passes when another
## check is added beside it.
func _mentions(blockers: Array[String], needle: String) -> bool:
	for b: String in blockers:
		if b.contains(needle):
			return true
	return false


# ---------------------------------------------------------------- THE GREEN
## ⚠ THE ASSERTION THE WHOLE FILE EXISTS FOR. Clean project + clean preset +
## clean host = zero blockers, i.e. the gate's PASS branch is reachable and the
## `Release gate: PASS` line is not dead code.
func _test_clean() -> void:
	var b: Array[String] = Lib.check_all(CLEAN_PROJECT, CLEAN_PRESET, CLEAN_HOST)
	_expect(b.is_empty(),
		"a clean project + preset + host produces ZERO blockers — the gate CAN go green (got %s)"
		% [b])
	_completes("clean_input_produces_no_blockers")


# ------------------------------------------------------------------ THE RED
func _test_dirty_autoload() -> void:
	var b: Array[String] = Lib.check_autoloads(DIRTY_PROJECT)
	_expect(_mentions(b, "MCPRuntime"), "the dev bridge in [autoload] is caught")
	_expect(_mentions(b, "REMOVE the line"),
		"...and the blocker prints the exact line to delete, not just a complaint")
	_completes("dev_autoload_is_caught")


## The addon is named in `[editor_plugins]` in the real project.godot. If the
## check were a substring match the gate would be red forever with the autoload
## already gone — which is the failure mode that trains people to ignore gates.
func _test_autoload_scoping() -> void:
	var b: Array[String] = Lib.check_autoloads(PROJECT_MENTIONING_BRIDGE_ELSEWHERE)
	_expect(b.is_empty(),
		"the bridge named OUTSIDE [autoload] is not a blocker — got %s" % [b])
	_completes("autoload_check_is_section_scoped")


## THE DIRECTOR'S PRIMARY GATE. Without `res://tools/*` excluded, the whole debug
## rig is in the APK regardless of any runtime flag.
func _test_missing_tools_exclude() -> void:
	var b: Array[String] = Lib.check_export_excludes(PRESET_WITHOUT_TOOLS)
	_expect(_mentions(b, "res://tools/*"),
		"dropping `res://tools/*` from the exclude filter is caught — that is the "
		+ "one line keeping the DIRECTOR out of the pack")
	_completes("missing_tools_exclude_is_caught")


func _test_missing_addon_exclude() -> void:
	var b: Array[String] = Lib.check_export_excludes(PRESET_WITHOUT_TOOLS)
	_expect(not _mentions(b, "godot_mcp_runtime"),
		"a preset that DOES exclude the mcp addon is not blamed for it")
	var b2: Array[String] = Lib.check_export_excludes(
		"[preset.0.options]\nexclude_filter=\"res://tools/*\"\n")
	_expect(_mentions(b2, "godot_mcp_runtime"), "a missing addon exclude is caught")
	_completes("missing_addon_exclude_is_caught")


## Every dev path appears in this preset as TEXT — inside a comment — while the
## real filter is empty. The naive whole-file `contains()` passes it.
func _test_commented_exclude() -> void:
	var b: Array[String] = Lib.check_export_excludes(PRESET_WITH_ONLY_A_COMMENT)
	_expect(_mentions(b, "res://tools/*"),
		"paths mentioned only in a COMMENT do not count as excluded")
	_completes("commented_out_exclude_does_not_count")


## THE DIRECTOR'S SECOND GATE. Catches the case the exclude cannot: a debug APK
## built from an edited preset and sideloaded onto a phone.
func _test_guard_removed() -> void:
	var b: Array[String] = Lib.check_director(HOST_WITHOUT_GUARD)
	_expect(_mentions(b, "OS.is_debug_build()"),
		"losing the debug-build guard in PauseMenu is caught")
	_expect(Lib.check_director(CLEAN_HOST).is_empty(),
		"...and a host that still has it is clean")
	_completes("director_guard_removal_is_caught")


## `preload` resolves at COMPILE time, so preloading an excluded path defeats the
## exclude. `load()` behind the guard is the correct shape and must stay legal.
func _test_preload_banned() -> void:
	var b: Array[String] = Lib.check_director(HOST_WITH_PRELOAD)
	_expect(_mentions(b, "PRELOADS"), "a preload of a res://tools/ path is caught")
	_expect(Lib.check_director(
			"if not OS.is_debug_build(): return false\nvar s = load(\"res://tools/director/Director.gd\")"
		).is_empty(),
		"...while a runtime load() of the same path stays legal — it returns null on a device")
	_completes("director_preload_is_caught")


## Silence must not read as success. A file the gate could not open is a file it
## could not verify, and that is a blocker, not a pass.
func _test_unreadable() -> void:
	_expect(not Lib.check_autoloads("").is_empty(), "an unreadable project.godot is a blocker")
	_expect(not Lib.check_export_excludes("").is_empty(), "a missing export preset is a blocker")
	_expect(not Lib.check_director("").is_empty(), "an unreadable PauseMenu.gd is a blocker")
	_completes("unreadable_inputs_are_blockers_not_silence")


## And finally against reality: the REAL shipped files must already satisfy the
## two director checks today. (The autoload check is deliberately NOT asserted
## here — it is expected red until the pre-release edit, and asserting it would
## make this suite fail for the one reason that is by design.)
func _test_real_files() -> void:
	var host: String = FileAccess.get_file_as_string(Lib.DIRECTOR_HOST)
	_expect(not host.is_empty(), "the real %s is readable" % Lib.DIRECTOR_HOST)
	_expect(Lib.check_director(host).is_empty(),
		"the REAL PauseMenu.gd passes the director checks right now: %s"
		% [Lib.check_director(host)])
	var preset: String = ""
	if FileAccess.file_exists("res://export_presets.cfg"):
		preset = FileAccess.get_file_as_string("res://export_presets.cfg")
	_expect(Lib.check_export_excludes(preset).is_empty(),
		"the REAL export preset already excludes every dev path: %s"
		% [Lib.check_export_excludes(preset)])
	_completes("the_real_shipped_files_still_satisfy_the_director_checks")
