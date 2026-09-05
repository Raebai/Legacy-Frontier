# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_audio_buses.gd
#
# THE AUDIO BUS LAYOUT ACTUALLY LOADS, SO THE MUSIC AND SFX SLIDERS ARE NOT NO-OPS.
#
# THE FAULT THIS EXISTS FOR. Every headless run printed
#     ERROR: Unrecognized UID: "uid://dh7jpov3r60sy"
# and then carried on. That UID is `default_bus_layout.tres`, referenced from
# `project.godot` as `buses/default_bus_layout="uid://..."`. When the UID fails to
# resolve, Godot does not fall over — it silently boots the DEFAULT layout, which is a
# single "Master" bus. So `AudioServer.get_bus_index("Music")` returned -1, and every
# `set_bus_volume_db`/`set_bus_linear` against "Music" or "SFX" was a **silent no-op**:
# the settings screen moved a slider that changed nothing at all. It surfaced only as
# `slice_test_settings` intermittently failing "music volume came back", which reads
# like a persistence bug and is not one.
#
# WHY THE UID FORM IS THE BUG AND NOT THE SYMPTOM. A `uid://` reference is resolved
# through `.godot/uid_cache.bin`, which is BUILD OUTPUT — it is not tracked, it is
# rebuilt by an import, and it is rewritten by the editor while the editor is open. So
# the reference worked on a machine that had just imported and failed on a pristine
# checkout, which is exactly the pattern that was observed: reproduced on clean HEAD,
# then "fixed itself" after the editor was opened, then came back. A `res://` path is
# resolved by the filesystem and consults no cache, so it cannot drift.
#
# ⚠ THE OBVIOUS TEST WOULD PASS THE WHOLE TIME. Reading `project.godot` and asserting
# the key is present proves nothing — the key WAS present, pointing at a UID nothing
# could resolve. And setting a bus volume and reading it straight back proves nothing
# either, because with no Music bus the write and the read both go nowhere and agree.
# This asks the RUNNING AudioServer which buses it actually built, which is the only
# channel the player is on.
extends SceneTree

## Every bus the game addresses by name. `Settings` writes to Music and SFX; Master is
## the one Godot creates unprompted, so its presence proves nothing on its own and it is
## listed only so a layout that loaded but was authored wrong is still caught.
const REQUIRED_BUSES: Array[String] = ["Master", "Music", "SFX"]

var _failures: int = 0


func _fail(msg: String) -> void:
	_failures += 1
	push_error("FAIL: " + msg)
	print("  FAIL: ", msg)


func _init() -> void:
	_test_buses_exist()
	_test_bus_volume_is_not_a_no_op()
	_test_project_setting_is_path_not_uid()
	if _failures == 0:
		print("Audio bus tests: all PASS")
	else:
		print("Audio bus tests: ", _failures, " FAILED")
	quit(1 if _failures > 0 else 0)


## The layout loaded at all. With a broken reference the bus count is 1 and every name
## below Master is missing.
func _test_buses_exist() -> void:
	var names: PackedStringArray = []
	for i: int in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(i))
	print("  buses: ", ", ".join(names))
	for want: String in REQUIRED_BUSES:
		if AudioServer.get_bus_index(want) == -1:
			_fail("bus '%s' does not exist — the layout did not load, so every volume write to it is a silent no-op" % want)


## A write to the Music bus REACHES the mixer. This is the assertion that would have
## caught the fault: with no Music bus the index is -1, and `set_bus_volume_db(-1, ...)`
## is discarded without an error.
func _test_bus_volume_is_not_a_no_op() -> void:
	var idx: int = AudioServer.get_bus_index("Music")
	if idx == -1:
		return  # already reported above; do not double-count one fault
	var original: float = AudioServer.get_bus_volume_db(idx)
	AudioServer.set_bus_volume_db(idx, -17.0)
	var readback: float = AudioServer.get_bus_volume_db(idx)
	AudioServer.set_bus_volume_db(idx, original)
	if absf(readback - (-17.0)) > 0.01:
		_fail("wrote -17.0 dB to the Music bus and read back %.2f — the mixer did not take it" % readback)


## THE CAUSE, GUARDED AT THE SOURCE. A `uid://` here resolves through build output that
## is neither tracked nor stable; a `res://` path does not. This is the one assertion
## that fails on a pristine checkout BEFORE anything has been imported, which is where
## the fault actually lived.
func _test_project_setting_is_path_not_uid() -> void:
	var ref: String = str(ProjectSettings.get_setting("audio/buses/default_bus_layout", ""))
	if ref == "":
		_fail("project.godot has no audio/buses/default_bus_layout at all")
		return
	if ref.begins_with("uid://"):
		_fail("audio/buses/default_bus_layout is a UID (%s). Use res://default_bus_layout.tres — a UID resolves through .godot/uid_cache.bin, which is untracked build output the editor rewrites, so it fails on a fresh checkout and the Music bus silently vanishes." % ref)
		return
	if not FileAccess.file_exists(ref):
		_fail("audio/buses/default_bus_layout points at '%s', which does not exist" % ref)
