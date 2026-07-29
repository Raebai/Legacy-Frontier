# Run: godot --headless --path godot-project --script tools/slice0_test_sfx.gd
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"streams_load",
	"sfx_autoload_keys",
]

var _fails: int = 0
var _completed: Dictionary = {}

# Layered SFX are now multi-variant .wav files (transient+body+tail synth).
# Each key maps to an ARRAY of variant streams in Sfx.STREAMS.
const SFX_VARIANTS: Dictionary = {
	"cast": ["res://assets/audio/sfx/cast_1.wav", "res://assets/audio/sfx/cast_2.wav"],
	"spell_impact": [
		"res://assets/audio/sfx/spell_impact_1.wav",
		"res://assets/audio/sfx/spell_impact_2.wav",
		"res://assets/audio/sfx/spell_impact_3.wav",
	],
	"enemy_death": ["res://assets/audio/sfx/enemy_death_1.wav", "res://assets/audio/sfx/enemy_death_2.wav"],
	"hero_hurt": ["res://assets/audio/sfx/hero_hurt_1.wav", "res://assets/audio/sfx/hero_hurt_2.wav"],
	"blast": ["res://assets/audio/sfx/blast_1.wav", "res://assets/audio/sfx/blast_2.wav"],
}


func _init() -> void:
	_test_streams_load()
	_test_sfx_autoload_keys()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice0 sfx tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice0 sfx tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _test_streams_load() -> void:
	for key: String in SFX_VARIANTS:
		for path: String in SFX_VARIANTS[key]:
			var stream: Resource = load(path)
			_expect(stream != null, "%s loads (%s)" % [key, path])
			_expect(stream is AudioStreamWAV, "%s is AudioStreamWAV (%s)" % [key, path])
	_completes("streams_load")


func _test_sfx_autoload_keys() -> void:
	var sfx_script: GDScript = load("res://scripts/combat/Sfx.gd")
	_expect(sfx_script != null, "Sfx.gd loads")
	if sfx_script == null:
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var streams: Dictionary = sfx_script.get_script_constant_map().get("STREAMS", {})
	for key: String in SFX_VARIANTS:
		_expect(streams.has(key), "STREAMS has key '%s'" % key)
		var variants: Variant = streams.get(key)
		_expect(variants is Array, "STREAMS['%s'] is an Array of variants" % key)
		_expect(variants is Array and not (variants as Array).is_empty(), "STREAMS['%s'] non-empty" % key)
	_completes("sfx_autoload_keys")
