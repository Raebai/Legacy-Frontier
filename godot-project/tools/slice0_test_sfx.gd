# Run: godot --headless --path godot-project --script tools/slice0_test_sfx.gd
extends SceneTree

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
	var failed: int = 0
	failed += _test_streams_load()
	failed += _test_sfx_autoload_keys()
	if failed > 0:
		printerr("Slice0 sfx tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice0 sfx tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_streams_load() -> int:
	var failed: int = 0
	for key: String in SFX_VARIANTS:
		for path: String in SFX_VARIANTS[key]:
			var stream: Resource = load(path)
			failed += _expect(stream != null, "%s loads (%s)" % [key, path])
			failed += _expect(stream is AudioStreamWAV, "%s is AudioStreamWAV (%s)" % [key, path])
	return failed


func _test_sfx_autoload_keys() -> int:
	var failed: int = 0
	var sfx_script: GDScript = load("res://scripts/combat/Sfx.gd")
	failed += _expect(sfx_script != null, "Sfx.gd loads")
	if sfx_script == null:
		return failed
	var streams: Dictionary = sfx_script.get_script_constant_map().get("STREAMS", {})
	for key: String in SFX_VARIANTS:
		failed += _expect(streams.has(key), "STREAMS has key '%s'" % key)
		var variants: Variant = streams.get(key)
		failed += _expect(variants is Array, "STREAMS['%s'] is an Array of variants" % key)
		failed += _expect(variants is Array and not (variants as Array).is_empty(), "STREAMS['%s'] non-empty" % key)
	return failed
