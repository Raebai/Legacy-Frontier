# Run: godot --headless --path godot-project --script tools/slice_test_music.gd
#
# Covers the MUSIC BED's wiring, and in particular the one lever that has not
# been pulled yet: SIZE.
#
# Six MP3s are 36.4 MB of a ~45 MB shipping audio payload — about 81% of it — at
# 320/256/192 kbps, for a bed that is mixed 20-28 dB DOWN under the SFX. (The 187
# sound effects cost 4.0 MB combined, because Godot 4.6 imports WAV as QOA. The
# SFX are not the problem.) Re-encoding to ~96-112 kbps Ogg Vorbis saves roughly
# 17-20 MB, around 40% of the whole build.
#
# That conversion has NOT been done: ffmpeg is not installed on this machine and
# `python-tools/compress_music.py` refuses to run without it. What HAS been done
# is make the swap free: `Music._preferred_path()` prefers a same-named `.ogg`
# beside each listed `.mp3`, so dropping the six files in needs no code edit and
# deleting them rolls it back. This suite pins that rule, because a lossy-on-lossy
# conversion nobody has heard needs a rollback that cannot rot.
#
# WHAT CANNOT BE TESTED: whether 112 kbps still sounds good. Headless has no
# audio device and nobody has listened.
extends SceneTree

# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion
# sentinel, so a test aborted by a dead property read fails BY ABSENCE.

const TESTS: Array[String] = [
	"every_mood_has_a_playlist",
	"every_track_resolves",
	"ogg_is_preferred_over_mp3",
	"the_swap_is_reversible",
	"the_compressor_names_the_same_tracks",
]

var _fails: int = 0
var _completed: Dictionary = {}

const MUSIC_SCRIPT: String = "res://scripts/combat/Music.gd"
## Lives outside res://, so it is read through the OS path rather than FileAccess
## on a resource path.
const COMPRESSOR: String = "../python-tools/compress_music.py"


func _init() -> void:
	_test_every_mood_has_a_playlist()
	_test_every_track_resolves()
	_test_ogg_is_preferred_over_mp3()
	_test_the_swap_is_reversible()
	_test_the_compressor_names_the_same_tracks()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Music tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Music tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _music_const(name: String) -> Variant:
	return (load(MUSIC_SCRIPT) as GDScript).get_script_constant_map().get(name)


## A detached instance, purely to reach the methods. Never added to the tree, so
## `_ready` (which starts playing a bed) does not run.
func _music() -> Node:
	return (load(MUSIC_SCRIPT) as GDScript).new()


# ---------------------------------------------------------------------------

func _test_every_mood_has_a_playlist() -> void:
	var playlists: Dictionary = _music_const("PLAYLISTS")
	var volumes: Dictionary = _music_const("MOOD_VOLUME_DB")
	_expect(playlists.size() >= 3, "there is a bed for every place (got %d)" % playlists.size())
	for mood: int in playlists:
		var list: Array = playlists[mood]
		_expect(not list.is_empty(), "mood %d has at least one track" % mood)
		# A mood with no resting level falls back to the global default and
		# quietly loses its intended balance against the SFX.
		_expect(volumes.has(mood), "mood %d has a resting volume" % mood)
	for mood: int in volumes:
		_expect(playlists.has(mood), "no orphan volume for mood %d" % mood)
	_completes("every_mood_has_a_playlist")


func _test_every_track_resolves() -> void:
	# A missing file is survivable at runtime (cycle_track skips it) but it means
	# a mood silently plays the wrong bed — or nothing.
	var playlists: Dictionary = _music_const("PLAYLISTS")
	var seen: Dictionary = {}
	for mood: int in playlists:
		for path: String in playlists[mood]:
			_expect(ResourceLoader.exists(path), "track exists: %s" % path)
			_expect(not seen.has(path), "%s is not listed under two moods" % path.get_file())
			seen[path] = mood
	_completes("every_track_resolves")


func _test_ogg_is_preferred_over_mp3() -> void:
	var m: Node = _music()
	# The re-encode has not happened, so the six music `.ogg` files do not exist
	# yet and every music path must still resolve to its `.mp3`. That IS the
	# fallback branch, and it is the state the game ships in today.
	var playlists: Dictionary = _music_const("PLAYLISTS")
	for mood: int in playlists:
		for path: String in playlists[mood]:
			var got: String = String(m.call(&"_preferred_path", path))
			_expect(ResourceLoader.exists(got), "'%s' resolves to a real file" % path)
			if path.get_extension().to_lower() != "mp3":
				_expect(got == path, "non-mp3 '%s' is left alone" % path.get_file())
	# And the preference branch itself, exercised against a pair that DOES exist:
	# `cast_fire_1.ogg` is in the SFX folder, so asking for a hypothetical
	# `cast_fire_1.mp3` must be answered with the ogg.
	var probe_mp3: String = "res://assets/audio/sfx/cast_fire_1.mp3"
	var probe_ogg: String = "res://assets/audio/sfx/cast_fire_1.ogg"
	_expect(ResourceLoader.exists(probe_ogg), "the probe ogg exists (fixture check)")
	_expect(String(m.call(&"_preferred_path", probe_mp3)) == probe_ogg,
		"an mp3 with an ogg beside it resolves to the ogg")
	m.free()
	_completes("ogg_is_preferred_over_mp3")


func _test_the_swap_is_reversible() -> void:
	var m: Node = _music()
	# Rollback is the whole reason the paths stayed as `.mp3`: with no ogg
	# present the mp3 comes back, so deleting six files undoes a conversion
	# nobody has listened to.
	var missing: String = "res://assets/audio/music/definitely_not_here.mp3"
	_expect(String(m.call(&"_preferred_path", missing)) == missing,
		"with no ogg beside it, the mp3 path is returned unchanged")
	# Extensions other than mp3 are untouched — wav is already imported as QOA
	# and costs almost nothing, so rewriting it would be a footgun with no win.
	for path: String in [
		"res://assets/audio/music/hub_ambience.wav",
		"res://assets/audio/sfx/cast_fire_1.ogg",
	]:
		_expect(String(m.call(&"_preferred_path", path)) == path,
			"'%s' is not rewritten" % path.get_file())
	m.free()
	_completes("the_swap_is_reversible")


func _test_the_compressor_names_the_same_tracks() -> void:
	# The tool and the playlist have to agree, or a track gets added to the game
	# and silently never shrinks — which is exactly how the payload got to 81%
	# music in the first place.
	var src: String = FileAccess.get_file_as_string(COMPRESSOR)
	if src.is_empty():
		# Reading outside res:// is allowed in a --script run but not worth
		# failing the suite over if a future layout moves python-tools/.
		print("NOTE: could not read %s — skipping the tool/playlist cross-check" % COMPRESSOR)
		_completes("the_compressor_names_the_same_tracks")
		return
	var playlists: Dictionary = _music_const("PLAYLISTS")
	for mood: int in playlists:
		for path: String in playlists[mood]:
			if path.get_extension().to_lower() != "mp3":
				continue
			var stem: String = path.get_file().get_basename()
			_expect(src.contains("\"%s\"" % stem),
				"compress_music.py knows about '%s' (else it never shrinks)" % stem)
	_completes("the_compressor_names_the_same_tracks")
