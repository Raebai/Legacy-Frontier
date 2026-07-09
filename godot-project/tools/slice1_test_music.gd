# Run: godot --headless --path godot-project --script tools/slice1_test_music.gd
# Note: tests run on the first _process frame (not _init) because Music.gd is
# an autoload-shaped script — load()ed at runtime, never preload()ed, so it
# compiles after autoload globals are registered.
extends SceneTree

const THEME_PATH: String = "res://assets/audio/music/combat_theme.mp3"
const MUSIC_SCRIPT_PATH: String = "res://scripts/combat/Music.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_combat_theme_loads()
	failed += _test_music_autoload_api()
	if failed > 0:
		printerr("Slice1 music tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 music tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_combat_theme_loads() -> int:
	var failed: int = 0
	var stream: Resource = load(THEME_PATH)
	failed += _expect(stream != null, "combat_theme.mp3 loads (%s)" % THEME_PATH)
	failed += _expect(stream is AudioStreamMP3, "combat_theme.mp3 is AudioStreamMP3")
	return failed


func _test_music_autoload_api() -> int:
	var failed: int = 0
	var music_script: GDScript = load(MUSIC_SCRIPT_PATH)
	failed += _expect(music_script != null, "Music.gd loads")
	if music_script == null:
		return failed
	var music: Node = music_script.new()
	for method: String in ["duck", "play_combat", "set_volume_db", "stop"]:
		failed += _expect(music.has_method(method), "Music has method '%s'" % method)
	failed += _expect(
		music_script.get_script_constant_map().get("BASE_VOLUME_DB", 0.0) < 0.0,
		"BASE_VOLUME_DB sits under the SFX (negative db)"
	)
	# stop() before _ready (no player yet) must be a safe no-op.
	music.call("stop")
	music.free()
	return failed
