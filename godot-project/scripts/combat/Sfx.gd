extends Node
## Global one-shot sound player (autoload `Sfx`).
## Plays combat SFX on a small round-robin pool of AudioStreamPlayers so
## overlapping casts/hits/deaths never cut each other off. Slight per-play
## pitch variation keeps repeated sounds from feeling robotic.

const STREAMS: Dictionary = {
	"cast": preload("res://assets/audio/sfx/cast.ogg"),
	"spell_impact": preload("res://assets/audio/sfx/spell_impact.ogg"),
	"enemy_death": preload("res://assets/audio/sfx/enemy_death.ogg"),
	"hero_hurt": preload("res://assets/audio/sfx/hero_hurt.ogg"),
}

const POOL_SIZE: int = 8

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	# Keep SFX audible while hit-stop slows the game clock.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## Play a named SFX. `pitch_variation` is a ± fraction (0.08 = ±8%).
func play(key: String, volume_db: float = 0.0, pitch_variation: float = 0.06) -> void:
	var stream: AudioStream = STREAMS.get(key)
	if stream == null:
		push_warning("Sfx: unknown key '%s'" % key)
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
