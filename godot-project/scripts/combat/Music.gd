extends Node
## Global music bed (autoload `Music`).
## Loops a single combat track under the SFX layer and exposes a duck() so
## big moments (the blast) can push the music down for a beat and let the
## sound effect own the mix. One AudioStreamPlayer, PROCESS_MODE_ALWAYS so
## the bed keeps driving through hit-stop's Engine.time_scale slow.

## Swap the track by ear later: this const is the only place the path lives.
const COMBAT_THEME_PATH: String = "res://assets/audio/music/combat_theme.mp3"
## Mystic-forest hub ambience (synth pad, seamless loop) — a different bed for the
## lobby so the hub feels calm + artsy, not like a fight.
const HUB_THEME_PATH: String = "res://assets/audio/music/hub_ambience.wav"
const HUB_VOLUME_DB: float = -20.0  # a touch more present than combat (no SFX competing)

## Music sits UNDER the SFX (which play at 0 db) — dropped to -20 (was -12) so
## the bed stays background and the combat SFX own the mix.
const BASE_VOLUME_DB: float = -28.0
const SILENT_DB: float = -60.0
const FADE_IN_TIME: float = 1.5
const DUCK_RECOVER_TIME: float = 0.45

var _player: AudioStreamPlayer
var _combat_stream: AudioStreamMP3
var _hub_stream: AudioStream
var _base_db: float = BASE_VOLUME_DB
var _volume_tween: Tween


func _ready() -> void:
	# Keep the bed playing while hit-stop slows the game clock.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	# Route to the dedicated Music bus so big SFX can duck it independently of
	# Master (falls back to Master if the bus layout isn't present).
	_player.bus = &"Music" if AudioServer.get_bus_index(&"Music") != -1 else &"Master"
	add_child(_player)
	var stream: Resource = load(COMBAT_THEME_PATH)
	if stream is AudioStreamMP3:
		_combat_stream = stream
		_combat_stream.loop = true
	else:
		push_warning("Music: combat theme failed to load (%s)" % COMBAT_THEME_PATH)
	# Hub ambience (WAV pad) — force a seamless full-length forward loop.
	var hub: Resource = load(HUB_THEME_PATH)
	if hub is AudioStream:
		_hub_stream = hub
		if hub is AudioStreamWAV:
			var w := hub as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			# 16-bit mono -> 2 bytes/frame; loop the whole clip.
			w.loop_end = w.data.size() / 2
	if _combat_stream == null and _hub_stream == null:
		return
	play_combat()


## Set the resting volume the bed returns to after fades/ducks.
func set_volume_db(db: float) -> void:
	_base_db = db
	if _player == null:
		return
	_kill_volume_tween()
	_player.volume_db = db


## Briefly drop the bed by `amount_db`, hold, then ramp back to base.
## The blast "whump": music gets out of the way so the SFX hits harder.
func duck(amount_db: float = 8.0, hold: float = 0.35) -> void:
	if _player == null or _combat_stream == null or not _player.playing:
		return
	_kill_volume_tween()
	_player.volume_db = _base_db - amount_db
	_volume_tween = get_tree().create_tween()
	_volume_tween.tween_interval(hold)
	_volume_tween.tween_property(_player, "volume_db", _base_db, DUCK_RECOVER_TIME)


## Start the combat loop with a short fade-in. Idempotent.
func play_combat() -> void:
	if _combat_stream == null:
		push_warning("Music: no combat stream loaded, cannot play")
		return
	if _player.playing and _player.stream == _combat_stream:
		return
	_base_db = BASE_VOLUME_DB  # reset from the hub bed's level if we came from the lobby
	_kill_volume_tween()
	_player.stream = _combat_stream
	_player.volume_db = SILENT_DB
	_player.play()
	_volume_tween = get_tree().create_tween()
	_volume_tween.tween_property(_player, "volume_db", _base_db, FADE_IN_TIME)


## Switch to the mystic-forest HUB ambience with a fade-in. Idempotent — called by
## the hub (World._ready); the arenas call play_combat() to switch back.
func play_hub() -> void:
	if _hub_stream == null:
		play_combat()  # no hub bed available — keep whatever's playing
		return
	if _player.playing and _player.stream == _hub_stream:
		return
	_base_db = HUB_VOLUME_DB
	_kill_volume_tween()
	_player.stream = _hub_stream
	_player.volume_db = SILENT_DB
	_player.play()
	_volume_tween = get_tree().create_tween()
	_volume_tween.tween_property(_player, "volume_db", _base_db, FADE_IN_TIME)


## Stop the bed. Idempotent.
func stop() -> void:
	_kill_volume_tween()
	if _player != null and _player.playing:
		_player.stop()


func _kill_volume_tween() -> void:
	if _volume_tween != null and _volume_tween.is_valid():
		_volume_tween.kill()
	_volume_tween = null
