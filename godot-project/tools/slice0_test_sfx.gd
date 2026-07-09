# Run: godot --headless --path godot-project --script tools/slice0_test_sfx.gd
extends SceneTree

const SFX_PATHS: Dictionary = {
	"cast": "res://assets/audio/sfx/cast.ogg",
	"spell_impact": "res://assets/audio/sfx/spell_impact.ogg",
	"enemy_death": "res://assets/audio/sfx/enemy_death.ogg",
	"hero_hurt": "res://assets/audio/sfx/hero_hurt.ogg",
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
	for key: String in SFX_PATHS:
		var path: String = SFX_PATHS[key]
		var stream: Resource = load(path)
		failed += _expect(stream != null, "%s loads (%s)" % [key, path])
		failed += _expect(
			stream is AudioStreamOggVorbis,
			"%s is AudioStreamOggVorbis" % key
		)
	return failed


func _test_sfx_autoload_keys() -> int:
	var failed: int = 0
	var sfx_script: GDScript = load("res://scripts/combat/Sfx.gd")
	failed += _expect(sfx_script != null, "Sfx.gd loads")
	if sfx_script == null:
		return failed
	var streams: Dictionary = sfx_script.get_script_constant_map().get("STREAMS", {})
	for key: String in SFX_PATHS:
		failed += _expect(streams.has(key), "STREAMS has key '%s'" % key)
		failed += _expect(
			streams.get(key) != null,
			"STREAMS['%s'] stream is non-null" % key
		)
	return failed
