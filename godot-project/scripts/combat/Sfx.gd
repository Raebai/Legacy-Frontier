extends Node
## Global one-shot sound player (autoload `Sfx`).
## Plays combat SFX on a small round-robin pool of AudioStreamPlayers so
## overlapping casts/hits/deaths never cut each other off.
##
## Each key maps to an ARRAY of variant streams. Most combat keys now use REAL
## game-ready clips from the royalty-free "Free Fantasy SFX Pack by TomMusic" (dropped
## over the old filenames — de-cornies the beam + gives spells/melee real weight):
## beam=Firespray, cast=Fireball, charge_up=Firebuff, ice=Ice Throw/Freeze, earth=Rock
## Meteor/Wall, nova=Wave Attack, blast=Rock Meteor Swarm, spell_impact=Spell Impact,
## melee_hit=Sword Impact, melee_swing=Sword Attack, footstep=Dirt Walk. The rest
## (zap/holy/cannon/blink/ding/hero_hurt/enemy_death) stay on the synth placeholders
## from python-tools/generate_placeholder_sfx.py (no fitting royalty-free source, or
## they double as generic thuds). `play()` picks a random variant + a small pitch
## jitter so repeats never machine-gun the same sample (Stick-Fight feel study §5).
## Everything routes to the "SFX" bus; "big" keys (blast/cannon/beam) duck the Music.

const STREAMS: Dictionary = {
	"cast": [
		preload("res://assets/audio/sfx/cast_1.wav"),
		preload("res://assets/audio/sfx/cast_2.wav"),
	],
	"spell_impact": [
		preload("res://assets/audio/sfx/spell_impact_1.wav"),
		preload("res://assets/audio/sfx/spell_impact_2.wav"),
		preload("res://assets/audio/sfx/spell_impact_3.wav"),
	],
	"enemy_death": [
		preload("res://assets/audio/sfx/enemy_death_1.wav"),
		preload("res://assets/audio/sfx/enemy_death_2.wav"),
	],
	"hero_hurt": [
		preload("res://assets/audio/sfx/hero_hurt_1.wav"),
		preload("res://assets/audio/sfx/hero_hurt_2.wav"),
	],
	"melee_swing": [
		preload("res://assets/audio/sfx/melee_swing_1.wav"),
		preload("res://assets/audio/sfx/melee_swing_2.wav"),
	],
	"melee_hit": [
		preload("res://assets/audio/sfx/melee_hit_1.wav"),
		preload("res://assets/audio/sfx/melee_hit_2.wav"),
		preload("res://assets/audio/sfx/melee_hit_3.wav"),
	],
	"blast": [
		preload("res://assets/audio/sfx/blast_1.wav"),
		preload("res://assets/audio/sfx/blast_2.wav"),
	],
	# Bright "ding" on a clean melee/parry connect + running footsteps.
	"ding": [preload("res://assets/audio/sfx/ding.wav")],
	"footstep": [preload("res://assets/audio/sfx/footstep.wav")],
	# Shadow-blink teleport: short "vwip" (down-then-up pitch sweep + sparkle).
	"blink": [preload("res://assets/audio/sfx/blink.wav")],
	# Anime ability sounds — one per ability family (see generate_placeholder_sfx.py).
	"charge_up": [
		preload("res://assets/audio/sfx/charge_up_1.wav"),
		preload("res://assets/audio/sfx/charge_up_2.wav"),
	],
	"beam": [
		preload("res://assets/audio/sfx/beam_1.wav"),
		preload("res://assets/audio/sfx/beam_2.wav"),
	],
	"cannon": [
		preload("res://assets/audio/sfx/cannon_1.wav"),
		preload("res://assets/audio/sfx/cannon_2.wav"),
	],
	"zap": [
		preload("res://assets/audio/sfx/zap_1.wav"),
		preload("res://assets/audio/sfx/zap_2.wav"),
	],
	"ice": [
		preload("res://assets/audio/sfx/ice_1.wav"),
		preload("res://assets/audio/sfx/ice_2.wav"),
	],
	"earth": [
		preload("res://assets/audio/sfx/earth_1.wav"),
		preload("res://assets/audio/sfx/earth_2.wav"),
	],
	"holy": [preload("res://assets/audio/sfx/holy.wav")],
	"nova": [
		preload("res://assets/audio/sfx/nova_1.wav"),
		preload("res://assets/audio/sfx/nova_2.wav"),
	],
}

## Keys big enough to briefly duck the music under them (SFX cuts through).
const DUCK_KEYS: Dictionary = {"blast": true, "cannon": true, "beam": true}

const SFX_BUS: StringName = &"SFX"
const POOL_SIZE: int = 8

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last_variant: Dictionary = {}  # key -> last index played, to avoid immediate repeats


func _ready() -> void:
	# Keep SFX audible while hit-stop slows the game clock.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var has_sfx_bus: bool = AudioServer.get_bus_index(SFX_BUS) != -1
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		if has_sfx_bus:
			p.bus = SFX_BUS
		add_child(p)
		_players.append(p)


## Play a named SFX. `pitch_variation` is a ± fraction (0.08 = ±8%).
## `pitch_base` re-pitches the sample before the jitter (0.7 = a deeper thud from
## the same clip — lets one asset serve as footstep tick AND land thud).
func play(key: String, volume_db: float = 0.0, pitch_variation: float = 0.06, pitch_base: float = 1.0) -> void:
	var variants: Array = STREAMS.get(key, [])
	if variants.is_empty():
		push_warning("Sfx: unknown key '%s'" % key)
		return
	var stream: AudioStream = _pick_variant(key, variants)
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch_base * (1.0 + randf_range(-pitch_variation, pitch_variation))
	p.play()
	if DUCK_KEYS.has(key):
		# Resolve the Music autoload via the tree (not the global identifier) so
		# this compiles in isolated --script test contexts where autoloads aren't
		# registered; at runtime /root/Music is the autoload.
		var music: Node = get_node_or_null(^"/root/Music")
		if music != null and music.has_method(&"duck"):
			music.call(&"duck")


## Pick a random variant, but avoid replaying the exact same one back-to-back
## (only matters when a key has 2+ variants).
func _pick_variant(key: String, variants: Array) -> AudioStream:
	if variants.size() == 1:
		return variants[0]
	var idx: int = randi() % variants.size()
	if idx == _last_variant.get(key, -1):
		idx = (idx + 1) % variants.size()
	_last_variant[key] = idx
	return variants[idx]
