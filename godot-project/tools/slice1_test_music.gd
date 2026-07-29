# Run: godot --headless --path godot-project --script tools/slice1_test_music.gd
# Note: tests run on the first _process frame (not _init) because Music.gd is
# an autoload-shaped script — load()ed at runtime, never preload()ed, so it
# compiles after autoload globals are registered.
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
	"combat_theme_loads",
	"music_autoload_api",
]

var _fails: int = 0
var _completed: Dictionary = {}

const THEME_PATH: String = "res://assets/audio/music/combat_theme.mp3"
const MUSIC_SCRIPT_PATH: String = "res://scripts/combat/Music.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_combat_theme_loads()
	_test_music_autoload_api()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 music tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 music tests: all PASS")
		quit(0)
	return true


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


func _test_combat_theme_loads() -> void:
	var stream: Resource = load(THEME_PATH)
	_expect(stream != null, "combat_theme.mp3 loads (%s)" % THEME_PATH)
	_expect(stream is AudioStreamMP3, "combat_theme.mp3 is AudioStreamMP3")
	_completes("combat_theme_loads")


func _test_music_autoload_api() -> void:
	var music_script: GDScript = load(MUSIC_SCRIPT_PATH)
	_expect(music_script != null, "Music.gd loads")
	if music_script == null:
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var music: Node = music_script.new()
	for method: String in ["duck", "play_combat", "set_volume_db", "stop"]:
		_expect(music.has_method(method), "Music has method '%s'" % method)
	_expect(
		music_script.get_script_constant_map().get("BASE_VOLUME_DB", 0.0) < 0.0,
		"BASE_VOLUME_DB sits under the SFX (negative db)"
	)
	# stop() before _ready (no player yet) must be a safe no-op.
	music.call("stop")
	music.free()
	_completes("music_autoload_api")
