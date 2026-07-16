extends Node
## Global music bed (autoload `Music`).
## MOOD-driven: the hub plays a folklore TOWN bed, floors play ADVENTURE, and a
## BOSS floor swaps to a hotter BOSS bed. Each mood is a PLAYLIST you can cycle
## through live with the `cycle_music` action (M) — the "cool option" to vary the
## score. One AudioStreamPlayer routed to the Music bus, PROCESS_MODE_ALWAYS so
## the bed keeps driving through hit-stop's Engine.time_scale slow, and a duck()
## so big moments (the blast) push the music down for a beat.

enum Mood { TOWN, ADVENTURE, BOSS }

## Each mood is a PLAYLIST of resource paths. The first entry is the default;
## `cycle_track()` steps through them (skipping any missing file). Drop new tracks
## in and add their path here — that's the only wiring needed.
const PLAYLISTS: Dictionary = {
	Mood.TOWN: [
		"res://assets/audio/music/hub_ambience.wav",
		"res://assets/audio/music/arcadia.mp3",
		"res://assets/audio/music/lord_of_the_land.mp3",
	],
	Mood.ADVENTURE: [
		"res://assets/audio/music/for_tomorrow.mp3",
		"res://assets/audio/music/unexplored_moon.mp3",
		"res://assets/audio/music/combat_theme.mp3",
	],
	Mood.BOSS: [
		"res://assets/audio/music/boss_theme.mp3",
	],
}

## Per-mood resting volume (boss a touch hotter for impact; town more present
## since no SFX compete in the lobby).
const MOOD_VOLUME_DB: Dictionary = {
	Mood.TOWN: -20.0,
	Mood.ADVENTURE: -28.0,
	Mood.BOSS: -24.0,
}

const BASE_VOLUME_DB: float = -28.0
const SILENT_DB: float = -60.0
const FADE_IN_TIME: float = 1.5
const CYCLE_FADE_TIME: float = 0.8
const DUCK_RECOVER_TIME: float = 0.45

var _player: AudioStreamPlayer
var _mood: int = Mood.ADVENTURE
var _track_index: Dictionary = {Mood.TOWN: 0, Mood.ADVENTURE: 0, Mood.BOSS: 0}
var _streams: Dictionary = {}          # path -> loaded (looping) AudioStream, or null if missing
var _base_db: float = BASE_VOLUME_DB
var _volume_tween: Tween
var _toast_layer: CanvasLayer
var _toast_label: Label
var _toast_tween: Tween


func _ready() -> void:
	# Keep the bed playing while hit-stop slows the game clock.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	# Route to the dedicated Music bus so big SFX can duck it independently of
	# Master (falls back to Master if the bus layout isn't present).
	_player.bus = &"Music" if AudioServer.get_bus_index(&"Music") != -1 else &"Master"
	add_child(_player)
	play_mood(Mood.ADVENTURE)   # boot default (matches the old play_combat() boot)


# ------------------------------------------------------------------ mood core
## Switch to a mood, playing its current track with a fade-in. Idempotent per
## (mood, track). BOSS with no track falls back to ADVENTURE so nothing breaks.
func play_mood(mood: int) -> void:
	if not PLAYLISTS.has(mood):
		return
	if _resolve_stream(mood, int(_track_index.get(mood, 0))) == null and mood == Mood.BOSS:
		mood = Mood.ADVENTURE   # no boss bed supplied yet — keep the adventure score
	var stream: AudioStream = _resolve_stream(mood, int(_track_index.get(mood, 0)))
	if stream == null:
		return
	_mood = mood
	_base_db = float(MOOD_VOLUME_DB.get(mood, BASE_VOLUME_DB))
	if _player.playing and _player.stream == stream:
		return   # already on this exact track
	_swap_to(stream, FADE_IN_TIME)


## Advance to the next track in the CURRENT mood's playlist and crossfade to it.
## Skips missing files so cycling never lands on silence. Returns a short display
## name for a toast ("" if there's nothing to cycle). Bound to the M key.
func cycle_track() -> String:
	var playlist: Array = PLAYLISTS[_mood]
	if playlist.size() <= 1:
		return ""
	var next: int = (int(_track_index[_mood]) + 1) % playlist.size()
	for _i in playlist.size():
		if _resolve_stream(_mood, next) != null:
			break
		next = (next + 1) % playlist.size()
	var stream: AudioStream = _resolve_stream(_mood, next)
	if stream == null:
		return ""
	_track_index[_mood] = next
	_swap_to(stream, CYCLE_FADE_TIME)
	return _track_display_name(playlist[next])


## Load + loop-configure a stream by (mood, index), cached. Returns null if the
## file is missing (e.g. boss_theme.mp3 not supplied) — callers handle the fallback.
func _resolve_stream(mood: int, idx: int) -> AudioStream:
	var playlist: Array = PLAYLISTS[mood]
	if idx < 0 or idx >= playlist.size():
		return null
	var path: String = playlist[idx]
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		_streams[path] = null
		return null
	var s: Resource = load(path)
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2   # 16-bit mono -> 2 bytes/frame; loop the whole clip
	_streams[path] = s
	return s


## Fade the player onto a new stream (kills any in-flight volume tween first).
func _swap_to(stream: AudioStream, fade: float) -> void:
	_kill_volume_tween()
	_player.stream = stream
	_player.volume_db = SILENT_DB
	_player.play()
	_volume_tween = get_tree().create_tween()
	_volume_tween.tween_property(_player, "volume_db", _base_db, fade)


func _track_display_name(path: String) -> String:
	return path.get_file().get_basename().capitalize()


# ----------------------------------------------------- convenience + aliases
func play_town() -> void: play_mood(Mood.TOWN)
func play_adventure() -> void: play_mood(Mood.ADVENTURE)
func play_boss() -> void: play_mood(Mood.BOSS)

# Back-compat: the existing call sites (World.gd, Arena.gd, VersusArena.gd) keep working.
func play_hub() -> void: play_town()
func play_combat() -> void: play_adventure()


# ------------------------------------------------------------- volume / duck
## Set the resting volume the bed returns to after fades/ducks.
func set_volume_db(db: float) -> void:
	_base_db = db
	if _player == null:
		return
	_kill_volume_tween()
	_player.volume_db = db


## Briefly drop the bed by `amount_db`, hold, then ramp back to base. The blast
## "whump": music gets out of the way so the SFX hits harder.
func duck(amount_db: float = 8.0, hold: float = 0.35) -> void:
	if _player == null or not _player.playing:
		return
	_kill_volume_tween()
	_player.volume_db = _base_db - amount_db
	_volume_tween = get_tree().create_tween()
	_volume_tween.tween_interval(hold)
	_volume_tween.tween_property(_player, "volume_db", _base_db, DUCK_RECOVER_TIME)


## Stop the bed. Idempotent.
func stop() -> void:
	_kill_volume_tween()
	if _player != null and _player.playing:
		_player.stop()


func _kill_volume_tween() -> void:
	if _volume_tween != null and _volume_tween.is_valid():
		_volume_tween.kill()
	_volume_tween = null


# --------------------------------------------------------- the cool option: M
## The Music autoload lives in EVERY scene, so handling the cycle key here makes
## it work in the hub and in combat with no per-scene wiring. Guarded so it never
## steals M while the player is typing to an NPC.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cycle_music"):
		return
	var vp: Viewport = get_viewport()
	if vp != null and vp.gui_get_focus_owner() is LineEdit:
		return
	var name_str: String = cycle_track()
	if name_str != "":
		_toast("♪  " + name_str)


## Tiny top-corner "now playing" label, ~1.4s fade. Built lazily.
func _toast(text: String) -> void:
	if _toast_layer == null:
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = 80
		add_child(_toast_layer)
		_toast_label = Label.new()
		_toast_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.offset_top = 40.0
		_toast_label.add_theme_font_size_override("font_size", 13)
		_toast_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.75, 1.0))
		_toast_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.09, 0.95))
		_toast_label.add_theme_constant_override("outline_size", 5)
		_toast_layer.add_child(_toast_label)
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = get_tree().create_tween()
	_toast_tween.tween_interval(1.0)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
