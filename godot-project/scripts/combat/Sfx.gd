extends Node
## Global one-shot sound player (autoload `Sfx`).
## Plays combat SFX on a round-robin pool of AudioStreamPlayers so overlapping
## casts/hits/deaths never cut each other off.
##
## ============================================================================
## WHERE THESE SOUNDS COME FROM
## ============================================================================
## Almost every clip in the roster is a REAL RECORDING mined out of the local
## `Effects/` library (the Sonniss #GameAudioGDC bundle + the TomMusic and Pepper
## free packs — 773 files across 45 packs, ~2 GB, gitignored). A handful are CC0
## downloads filling gaps that library genuinely does not cover.
##
## `python-tools/build_combat_sfx.py` IS the source-of-truth mapping: every game
## sound names the library file it was cut from, the window it was cut at, and a
## HIGH/MED/LOW confidence rating. When something sounds wrong, start there —
## re-pointing a key is a one-line manifest edit and a re-run, not an archaeology
## exercise. Licence + attribution for every downloaded file is in
## `assets/audio/CREDITS.md`.
##
## NOBODY HAS HEARD ANY OF THIS. Every clip was chosen by filename, folder,
## duration and file size, and every number in the mix block below is a
## considered guess. This is a starting mix laid out to be tuned in one pass with
## ears on it, not a finished one.
##
## ============================================================================
## WHY THE ROSTER IS THIS BIG
## ============================================================================
## It used to be 23 keys, which was far coarser than the game had become: ONE
## `beam` key served five different beams; ONE `ice` key served an ice wall, a
## spike line, a rime freeze and a shatter; the spell-vs-spell REACTIONS — the
## most cinematic thing in the game — had no sounds at all. The maker's note was
## "more accurate to what each spell does", so the roster now follows the spell
## list instead of the other way round:
##
##   * five beams, five voices (arcane / frost / fire / shadow / storm)
##   * Blizzard's three beats are three sounds: rime_tick -> ice_encase -> ice_shatter
##   * Glacial Spine gets a TRAVELLING sound (a fissure running through an ice
##     field), not a one-shot impact
##   * Drain Tether lashes, bites, drains, tears and misses — five keys
##   * Aegis Ward absorbs, cracks a plate, and breaks — three events, because
##     absorb is emphatically NOT break
##   * each ult is its own event: siege / verdict / eruption / bombardment /
##     avalanche / shove / unmaking
##   * every ReactionTable outcome has a voice, routed through REACTION_SOUND
##
## NEW KEYS ARE ADDITIVE. Every key the game called before still exists and still
## works; several now point at better recordings (see LEGACY ALIASES). Nothing
## outside this file had to change for the game to sound different today.
##
## ============================================================================
## THE MIX — why `play()` does more than play one sample
## ============================================================================
##  1. NO LOW END. Library one-shots carry a crack and a body but almost nothing
##     under ~80 Hz. A screen-crossing beam with no sub reads as a firework.
##     Heavy keys automatically ride a `sub_boom` stem underneath.
##  2. NO TAIL. A detonation that stops dead sounds like it happened in a vacuum.
##     Ult-weight keys get a `rumble` stem ~60 ms behind the hit — the room
##     answering. Still the single biggest "it got bigger" lever in here.
##  3. FLAT DYNAMICS. Every asset is peak-normalised, so without grading an
##     annihilation ult and a footstep arrive at the same loudness. Keys are
##     graded on the SpellTier vocabulary (QUICK/HEAVY/ULT, plus TICK).
##  4. TOO LONG. The library files are LIBRARY files — a "beam" recording is a
##     20-second electric-spell loop, an "ult" hit is a 2-second trailer boom —
##     while the spells they voice are over in well under a second. Every cue is
##     now CUT to fit the picture at playback — see THE LENGTH PROBLEM, below,
##     which carries the measurements and the derivation of the cap.
##
## HEADROOM CHANGED. The SFX bus compressor was loosened (threshold -14 -> -8,
## ratio 4.0 -> 2.5) because it was the hard ceiling on how big anything could
## sound. The class trims are opened up into that new headroom: the top of the
## range is genuinely louder now, rather than only the bottom being quieter.
##
## Everything routes to the "SFX" bus; ULT-weight keys briefly duck the Music.

# ---------------------------------------------------------------------------
# THE ROSTER
# ---------------------------------------------------------------------------
const STREAMS: Dictionary = {

	# ============================================================= CASTING
	# Casting is a visible PROCESS here (windup -> sigil along the aim ->
	# levitation -> discharge), so it gets a per-ELEMENT voice plus keys for the
	# beats of the process itself.
	"cast": [
		preload("res://assets/audio/sfx/cast_1.wav"),
		preload("res://assets/audio/sfx/cast_2.wav"),
	],
	"cast_fire": [
		preload("res://assets/audio/sfx/cast_fire_1.ogg"),
		preload("res://assets/audio/sfx/cast_fire_2.ogg"),
		preload("res://assets/audio/sfx/cast_fire_3.ogg"),
	],
	"cast_ice": [
		preload("res://assets/audio/sfx/cast_ice_1.ogg"),
		preload("res://assets/audio/sfx/cast_ice_2.ogg"),
	],
	"cast_earth": [
		preload("res://assets/audio/sfx/cast_earth_1.ogg"),
		preload("res://assets/audio/sfx/cast_earth_2.ogg"),
	],
	"cast_shadow": [
		preload("res://assets/audio/sfx/cast_shadow_1.wav"),
		preload("res://assets/audio/sfx/cast_shadow_2.wav"),
	],
	"cast_holy": [
		preload("res://assets/audio/sfx/cast_holy_1.wav"),
		preload("res://assets/audio/sfx/cast_holy_2.wav"),
	],
	"cast_storm": [
		preload("res://assets/audio/sfx/cast_storm_1.ogg"),
		preload("res://assets/audio/sfx/cast_storm_2.wav"),
	],
	"cast_arcane": [
		preload("res://assets/audio/sfx/cast_arcane_1.wav"),
		preload("res://assets/audio/sfx/cast_arcane_2.ogg"),
		preload("res://assets/audio/sfx/cast_arcane_3.ogg"),
	],
	# The windup. `charge_up` is the everyday one; `charge_ult` is the trailer
	# riser that belongs only in front of a finisher.
	"charge_up": [
		preload("res://assets/audio/sfx/charge_up_1.wav"),
		preload("res://assets/audio/sfx/charge_up_2.wav"),
	],
	"charge_ult": [
		preload("res://assets/audio/sfx/charge_ult_1.wav"),
		preload("res://assets/audio/sfx/charge_ult_2.wav"),
	],
	# The sigil drawing itself along the aim, and the caster leaving the floor.
	"sigil_form": [
		preload("res://assets/audio/sfx/sigil_form_1.wav"),
		preload("res://assets/audio/sfx/sigil_form_2.ogg"),
	],
	"levitate": [preload("res://assets/audio/sfx/levitate_1.wav")],

	# =============================================================== BEAMS
	# Five beams that were all one key. `beam_start` / `beam_end` are the frames
	# the line appears and cuts out — layer them under the body of any of them.
	"beam_arcane": [
		preload("res://assets/audio/sfx/beam_arcane_1.ogg"),
		preload("res://assets/audio/sfx/beam_arcane_2.ogg"),
	],
	"beam_frost": [
		preload("res://assets/audio/sfx/beam_frost_1.wav"),
		preload("res://assets/audio/sfx/beam_frost_2.wav"),
	],
	"beam_fire": [
		preload("res://assets/audio/sfx/beam_fire_1.wav"),
		preload("res://assets/audio/sfx/beam_fire_2.ogg"),
	],
	"beam_shadow": [
		preload("res://assets/audio/sfx/beam_shadow_1.wav"),
		preload("res://assets/audio/sfx/beam_shadow_2.wav"),
	],
	"beam_storm": [
		preload("res://assets/audio/sfx/beam_storm_1.ogg"),
		preload("res://assets/audio/sfx/beam_storm_2.wav"),
	],
	"beam_start": [preload("res://assets/audio/sfx/beam_start_1.wav")],
	"beam_end": [preload("res://assets/audio/sfx/beam_end_1.wav")],

	# ================================================================= ICE
	"ice_wall": [
		preload("res://assets/audio/sfx/ice_wall_1.ogg"),
		preload("res://assets/audio/sfx/ice_wall_2.ogg"),
	],
	# Glacial Spine — a crest erupting from the floor and RACING outward, so the
	# source is a fissure running through an ice field, not an impact.
	"ice_spine": [
		preload("res://assets/audio/sfx/ice_spine_1.wav"),
		preload("res://assets/audio/sfx/ice_spine_2.wav"),
	],
	"ice_throw": [
		preload("res://assets/audio/sfx/ice_throw_1.ogg"),
		preload("res://assets/audio/sfx/ice_throw_2.ogg"),
	],
	"frost_field": [
		preload("res://assets/audio/sfx/frost_field_1.ogg"),
		preload("res://assets/audio/sfx/frost_field_2.ogg"),
	],
	# --- Blizzard's three beats. The freeze TRAP is a rising meter, then a
	# closing, then a break, and each is a different sound on purpose.
	# `rime_tick` is short, dry and quiet: it fires repeatedly as the meter fills,
	# so anything with a tail would smear into mush.
	"rime_tick": [
		preload("res://assets/audio/sfx/rime_tick_1.wav"),
		preload("res://assets/audio/sfx/rime_tick_2.wav"),
		preload("res://assets/audio/sfx/rime_tick_3.wav"),
	],
	"ice_encase": [
		preload("res://assets/audio/sfx/ice_encase_1.ogg"),
		preload("res://assets/audio/sfx/ice_encase_2.ogg"),
		preload("res://assets/audio/sfx/ice_encase_3.wav"),
	],
	"ice_shatter": [
		preload("res://assets/audio/sfx/ice_shatter_1.wav"),
		preload("res://assets/audio/sfx/ice_shatter_2.wav"),
	],

	# =============================================================== EARTH
	"earth_wall": [
		preload("res://assets/audio/sfx/earth_wall_1.ogg"),
		preload("res://assets/audio/sfx/earth_wall_2.ogg"),
	],
	"earth_pillar": [
		preload("res://assets/audio/sfx/earth_pillar_1.wav"),
		preload("res://assets/audio/sfx/earth_pillar_2.wav"),
	],
	"earth_hurl": [
		preload("res://assets/audio/sfx/earth_hurl_1.ogg"),
		preload("res://assets/audio/sfx/earth_hurl_2.ogg"),
	],
	"earth_impact": [
		preload("res://assets/audio/sfx/earth_impact_1.ogg"),
		preload("res://assets/audio/sfx/earth_impact_2.ogg"),
	],
	"avalanche": [
		preload("res://assets/audio/sfx/avalanche_1.ogg"),
		preload("res://assets/audio/sfx/avalanche_2.wav"),
	],
	"rubble": [
		preload("res://assets/audio/sfx/rubble_1.wav"),
		preload("res://assets/audio/sfx/rubble_2.wav"),
	],

	# =========================================================== LIGHTNING
	# THE ONE GAP THE LOCAL LIBRARY COULD NOT FILL — 45 packs and no designed
	# electric arc anywhere in them. These are CC0 downloads (see CREDITS.md);
	# everything else in the roster comes from the local library.
	"zap": [
		preload("res://assets/audio/sfx/zap_1.wav"),
		preload("res://assets/audio/sfx/zap_2.wav"),
		preload("res://assets/audio/sfx/zap_3.wav"),
	],
	"zap_arc": [
		preload("res://assets/audio/sfx/zap_arc_1.wav"),
		preload("res://assets/audio/sfx/zap_arc_2.wav"),
	],
	# One link of a chain leap: the same arc, shorter and drier.
	"zap_chain": [
		preload("res://assets/audio/sfx/zap_chain_1.wav"),
		preload("res://assets/audio/sfx/zap_chain_2.wav"),
	],
	"thunder": [
		preload("res://assets/audio/sfx/thunder_1.ogg"),
		preload("res://assets/audio/sfx/thunder_2.wav"),
		preload("res://assets/audio/sfx/thunder_3.wav"),
	],

	# ============================================================== SHADOW
	"shadow_cast": [preload("res://assets/audio/sfx/shadow_cast_1.wav")],
	"shadow_crawl": [
		preload("res://assets/audio/sfx/shadow_crawl_1.wav"),
		preload("res://assets/audio/sfx/shadow_crawl_2.wav"),
	],
	"shadow_root": [
		preload("res://assets/audio/sfx/shadow_root_1.wav"),
		preload("res://assets/audio/sfx/shadow_root_2.wav"),
	],
	"void_pull": [
		preload("res://assets/audio/sfx/void_pull_1.wav"),
		preload("res://assets/audio/sfx/void_pull_2.wav"),
	],
	"rift_open": [
		preload("res://assets/audio/sfx/rift_open_1.wav"),
		preload("res://assets/audio/sfx/rift_open_2.wav"),
	],

	# ================================================================ HOLY
	"holy": [preload("res://assets/audio/sfx/holy.wav")],
	"holy_swell": [
		preload("res://assets/audio/sfx/holy_swell_1.wav"),
		preload("res://assets/audio/sfx/holy_swell_2.wav"),
	],
	"holy_pillar": [
		preload("res://assets/audio/sfx/holy_pillar_1.wav"),
		preload("res://assets/audio/sfx/holy_pillar_2.wav"),
	],
	# Heaven's Verdict: a hairline thread appears, THEN it burns down.
	"verdict_thread": [preload("res://assets/audio/sfx/verdict_thread_1.wav")],
	"verdict_burn": [preload("res://assets/audio/sfx/verdict_burn_1.wav")],
	# --- Aegis Ward. Three events, and the distinction is the whole spell:
	# ABSORB means the ward ate a spell and SURVIVED (a swallowed, muted deny);
	# CRACK is one rune plate going; BREAK is the gate failing.
	"ward_raise": [
		preload("res://assets/audio/sfx/ward_raise_1.wav"),
		preload("res://assets/audio/sfx/ward_raise_2.wav"),
	],
	"ward_absorb": [
		preload("res://assets/audio/sfx/ward_absorb_1.wav"),
		preload("res://assets/audio/sfx/ward_absorb_2.wav"),
	],
	"ward_crack": [
		preload("res://assets/audio/sfx/ward_crack_1.ogg"),
		preload("res://assets/audio/sfx/ward_crack_2.wav"),
	],
	"ward_break": [
		preload("res://assets/audio/sfx/ward_break_1.ogg"),
		preload("res://assets/audio/sfx/ward_break_2.wav"),
		preload("res://assets/audio/sfx/ward_break_3.wav"),
	],

	# ================================================================ ULTS
	"blast": [
		preload("res://assets/audio/sfx/blast_1.wav"),
		preload("res://assets/audio/sfx/blast_2.wav"),
	],
	"nova": [
		preload("res://assets/audio/sfx/nova_1.wav"),
		preload("res://assets/audio/sfx/nova_2.wav"),
	],
	"ult_siege": [
		preload("res://assets/audio/sfx/ult_siege_1.wav"),
		preload("res://assets/audio/sfx/ult_siege_2.wav"),
	],
	"ult_bombardment": [
		preload("res://assets/audio/sfx/ult_bombardment_1.wav"),
		preload("res://assets/audio/sfx/ult_bombardment_2.ogg"),
	],
	"ult_eruption": [
		preload("res://assets/audio/sfx/ult_eruption_1.wav"),
		preload("res://assets/audio/sfx/ult_eruption_2.wav"),
	],
	"ult_avalanche": [
		preload("res://assets/audio/sfx/ult_avalanche_1.ogg"),
		preload("res://assets/audio/sfx/ult_avalanche_2.wav"),
	],
	"ult_shove": [
		preload("res://assets/audio/sfx/ult_shove_1.wav"),
		preload("res://assets/audio/sfx/ult_shove_2.wav"),
	],
	# UNMAKING. Its audio identity is ABSENCE — the screen tears and the world
	# goes QUIET. The clip is the thinnest in the roster, the profile trims it
	# hard, and it still carries ULT weight purely so it ducks the music: the
	# ducking IS the sound. Do not "fix" this by making it louder.
	"ult_unmaking": [preload("res://assets/audio/sfx/ult_unmaking_1.wav")],
	# Hollow Purple: the intake, the held beat, then the erasure lance.
	"hollow_intake": [
		preload("res://assets/audio/sfx/hollow_intake_1.wav"),
		preload("res://assets/audio/sfx/hollow_intake_2.wav"),
	],
	"hollow_erase": [
		preload("res://assets/audio/sfx/hollow_erase_1.wav"),
		preload("res://assets/audio/sfx/hollow_erase_2.wav"),
	],

	# ======================================================== DRAIN TETHER
	# A hooked whip: it LASHES out, bites, drains, and can be TORN free.
	"whip_lash": [
		preload("res://assets/audio/sfx/whip_lash_1.wav"),
		preload("res://assets/audio/sfx/whip_lash_2.wav"),
		preload("res://assets/audio/sfx/whip_lash_3.wav"),
	],
	"whip_bite": [
		preload("res://assets/audio/sfx/whip_bite_1.wav"),
		preload("res://assets/audio/sfx/whip_bite_2.wav"),
	],
	"drain_pull": [
		preload("res://assets/audio/sfx/drain_pull_1.wav"),
		preload("res://assets/audio/sfx/drain_pull_2.wav"),
	],
	"tether_tear": [
		preload("res://assets/audio/sfx/tether_tear_1.wav"),
		preload("res://assets/audio/sfx/tether_tear_2.wav"),
	],
	"whip_miss": [
		preload("res://assets/audio/sfx/whip_miss_1.wav"),
		preload("res://assets/audio/sfx/whip_miss_2.wav"),
	],

	# ======================================================= MELEE / CLASH
	# REMAPPED. These used TomMusic's fantasy-RPG sword clips; the game is stick
	# figures throwing hands, and Pepper ships a 142-file dedicated brawl library.
	"melee_swing": [
		preload("res://assets/audio/sfx/melee_swing_1.wav"),
		preload("res://assets/audio/sfx/melee_swing_2.wav"),
		preload("res://assets/audio/sfx/melee_swing_3.wav"),
		preload("res://assets/audio/sfx/melee_swing_4.wav"),
	],
	"melee_swing_heavy": [
		preload("res://assets/audio/sfx/melee_swing_heavy_1.wav"),
		preload("res://assets/audio/sfx/melee_swing_heavy_2.wav"),
		preload("res://assets/audio/sfx/melee_swing_heavy_3.wav"),
	],
	"melee_hit": [
		preload("res://assets/audio/sfx/melee_hit_1.wav"),
		preload("res://assets/audio/sfx/melee_hit_2.wav"),
		preload("res://assets/audio/sfx/melee_hit_3.wav"),
		preload("res://assets/audio/sfx/melee_hit_4.wav"),
	],
	"melee_hit_heavy": [
		preload("res://assets/audio/sfx/melee_hit_heavy_1.wav"),
		preload("res://assets/audio/sfx/melee_hit_heavy_2.wav"),
		preload("res://assets/audio/sfx/melee_hit_heavy_3.wav"),
	],
	"melee_crit": [
		preload("res://assets/audio/sfx/melee_crit_1.wav"),
		preload("res://assets/audio/sfx/melee_crit_2.wav"),
	],
	# THE CLASH — two fighters' blows MEETING. Deliberately not either fighter's
	# hit sound: a block transient plus a metallic ring, so the ear hears an
	# exchange rather than a connect.
	"clash": [
		preload("res://assets/audio/sfx/clash_1.wav"),
		preload("res://assets/audio/sfx/clash_2.wav"),
		preload("res://assets/audio/sfx/clash_3.ogg"),
	],
	"clash_heavy": [
		preload("res://assets/audio/sfx/clash_heavy_1.wav"),
		preload("res://assets/audio/sfx/clash_heavy_2.wav"),
	],
	"parry": [
		preload("res://assets/audio/sfx/parry_1.ogg"),
		preload("res://assets/audio/sfx/parry_2.ogg"),
		preload("res://assets/audio/sfx/parry_3.ogg"),
	],
	"block": [
		preload("res://assets/audio/sfx/block_1.wav"),
		preload("res://assets/audio/sfx/block_2.wav"),
	],
	"guard_break": [
		preload("res://assets/audio/sfx/guard_break_1.wav"),
		preload("res://assets/audio/sfx/guard_break_2.wav"),
	],
	"punch": [
		preload("res://assets/audio/sfx/punch_1.wav"),
		preload("res://assets/audio/sfx/punch_2.wav"),
		preload("res://assets/audio/sfx/punch_3.wav"),
	],
	"kick": [
		preload("res://assets/audio/sfx/kick_1.wav"),
		preload("res://assets/audio/sfx/kick_2.wav"),
	],
	# The bright Stick-Fight "clean hit" payoff. Kept separate from `parry` on
	# purpose: `ding` is a REWARD cue, `parry` is a physical event.
	"ding": [preload("res://assets/audio/sfx/ding.wav")],

	# =========================================================== REACTIONS
	# Spell-vs-spell outcomes. These had NO sounds at all and are exactly the
	# moments the maker means by "cinematic". The outcome string -> key mapping is
	# REACTION_SOUND, below — use `Sfx.reaction_sound(outcome)`, do not guess a
	# name from the outcome, because several outcomes deliberately share a sound
	# and a few land on non-`rx_` keys (`shatter_ward` is a ward break).
	"rx_steam": [
		preload("res://assets/audio/sfx/rx_steam_1.wav"),
		preload("res://assets/audio/sfx/rx_steam_2.ogg"),
	],
	"rx_supercharge": [
		preload("res://assets/audio/sfx/rx_supercharge_1.wav"),
		preload("res://assets/audio/sfx/rx_supercharge_2.wav"),
	],
	"rx_shatter": [
		preload("res://assets/audio/sfx/rx_shatter_1.wav"),
		preload("res://assets/audio/sfx/rx_shatter_2.wav"),
	],
	"rx_shrapnel": [
		preload("res://assets/audio/sfx/rx_shrapnel_1.wav"),
		preload("res://assets/audio/sfx/rx_shrapnel_2.wav"),
	],
	"rx_void_pull": [preload("res://assets/audio/sfx/rx_void_pull_1.wav")],
	"rx_resonance": [preload("res://assets/audio/sfx/rx_resonance_1.wav")],
	"rx_carve": [
		preload("res://assets/audio/sfx/rx_carve_1.wav"),
		preload("res://assets/audio/sfx/rx_carve_2.wav"),
	],
	# The headline outcome — two beams cancelling.
	"rx_annihilate": [
		preload("res://assets/audio/sfx/rx_annihilate_1.wav"),
		preload("res://assets/audio/sfx/rx_annihilate_2.wav"),
	],
	"rx_breach": [
		preload("res://assets/audio/sfx/rx_breach_1.wav"),
		preload("res://assets/audio/sfx/rx_breach_2.ogg"),
	],
	"rx_ward_absorb": [
		preload("res://assets/audio/sfx/rx_ward_absorb_1.wav"),
		preload("res://assets/audio/sfx/rx_ward_absorb_2.wav"),
	],
	"rx_overpower": [preload("res://assets/audio/sfx/rx_overpower_1.wav")],
	"rx_ground_out": [
		preload("res://assets/audio/sfx/rx_ground_out_1.wav"),
		preload("res://assets/audio/sfx/rx_ground_out_2.wav"),
	],
	"rx_field_merge": [preload("res://assets/audio/sfx/rx_field_merge_1.wav")],
	# Holy light burning a shadow field out of existence — something is ERASED,
	# so it is a bright swell plus a dispersal rather than an impact.
	"rx_banish": [
		preload("res://assets/audio/sfx/rx_banish_1.wav"),
		preload("res://assets/audio/sfx/rx_banish_2.wav"),
	],
	"rx_blocked": [
		preload("res://assets/audio/sfx/rx_blocked_1.wav"),
		preload("res://assets/audio/sfx/rx_blocked_2.ogg"),
	],

	# =============================================================== VOICE
	# GIBBERISH. Four vowel banks, four variants each — the whole spoken
	# vocabulary of the game. Synthesised from scratch by
	# `python-tools/generate_gibberish_voices.py` (no pack, no licence, no
	# localisation), and re-pitched per character at playback by
	# `Gibberish.gd` + `speak()` below. Sixteen assets, unlimited voices.
	#
	# These are fired ONLY through `speak()`, never by a gameplay call site
	# guessing a key — the bank a character uses is part of its identity, and
	# picking one by hand would give two different fighters the same mouth.
	"voice_a": [
		preload("res://assets/audio/voice/gib_a_1.wav"),
		preload("res://assets/audio/voice/gib_a_2.wav"),
		preload("res://assets/audio/voice/gib_a_3.wav"),
		preload("res://assets/audio/voice/gib_a_4.wav"),
	],
	"voice_e": [
		preload("res://assets/audio/voice/gib_e_1.wav"),
		preload("res://assets/audio/voice/gib_e_2.wav"),
		preload("res://assets/audio/voice/gib_e_3.wav"),
		preload("res://assets/audio/voice/gib_e_4.wav"),
	],
	"voice_i": [
		preload("res://assets/audio/voice/gib_i_1.wav"),
		preload("res://assets/audio/voice/gib_i_2.wav"),
		preload("res://assets/audio/voice/gib_i_3.wav"),
		preload("res://assets/audio/voice/gib_i_4.wav"),
	],
	"voice_u": [
		preload("res://assets/audio/voice/gib_u_1.wav"),
		preload("res://assets/audio/voice/gib_u_2.wav"),
		preload("res://assets/audio/voice/gib_u_3.wav"),
		preload("res://assets/audio/voice/gib_u_4.wav"),
	],

	# ============================================================== BODIES
	# ⚠ `enemy_death` is NOT only a mob cue — DestructibleProp (crates),
	# BreakablePlatform, DestructibleTerrain, DestructibleFloor, RockWall and
	# Thrall all play it. Anything vocal here fires when a crate breaks, which is
	# how the maker met it. Keep it wordless.
	"enemy_death": [
		preload("res://assets/audio/sfx/enemy_death_1.wav"),
		preload("res://assets/audio/sfx/enemy_death_2.wav"),
		preload("res://assets/audio/sfx/enemy_death_3.wav"),
	],
	"enemy_death_big": [
		preload("res://assets/audio/sfx/enemy_death_big_1.wav"),
		preload("res://assets/audio/sfx/enemy_death_big_2.wav"),
	],
	"enemy_hurt": [
		preload("res://assets/audio/sfx/enemy_hurt_1.wav"),
		preload("res://assets/audio/sfx/enemy_hurt_2.wav"),
		preload("res://assets/audio/sfx/enemy_hurt_3.wav"),
	],
	"hero_hurt": [
		preload("res://assets/audio/sfx/hero_hurt_1.wav"),
		preload("res://assets/audio/sfx/hero_hurt_2.wav"),
		preload("res://assets/audio/sfx/hero_hurt_3.wav"),
	],
	# A ragdoll hitting the floor. The rig flops constantly and had no sound.
	"body_fall": [
		preload("res://assets/audio/sfx/body_fall_1.wav"),
		preload("res://assets/audio/sfx/body_fall_2.wav"),
		preload("res://assets/audio/sfx/body_fall_3.wav"),
	],
	# One variant, not two: the second was a body-burst from the family the maker
	# banned on 2026-08-04, and nothing calls this key, so replacing it would only
	# have added a second unheard guess.
	"gib": [
		preload("res://assets/audio/sfx/gib_1.wav"),
	],
	"spell_impact": [
		preload("res://assets/audio/sfx/spell_impact_1.wav"),
		preload("res://assets/audio/sfx/spell_impact_2.wav"),
		preload("res://assets/audio/sfx/spell_impact_3.wav"),
	],

	# =================================================== MOVEMENT / WORLD
	# REMAPPED from synth blips to real recorded footfalls on rock. Four variants
	# so a run is four different footfalls rather than one sample stuttering.
	"step": [
		preload("res://assets/audio/sfx/step_1.wav"),
		preload("res://assets/audio/sfx/step_2.wav"),
		preload("res://assets/audio/sfx/step_3.wav"),
		preload("res://assets/audio/sfx/step_4.wav"),
	],
	"land": [
		preload("res://assets/audio/sfx/land_1.wav"),
		preload("res://assets/audio/sfx/land_2.wav"),
	],
	"dash": [
		preload("res://assets/audio/sfx/dash_1.wav"),
		preload("res://assets/audio/sfx/dash_2.wav"),
	],
	"blink": [preload("res://assets/audio/sfx/blink.wav")],
	"crate_break": [
		preload("res://assets/audio/sfx/crate_break_1.ogg"),
		preload("res://assets/audio/sfx/crate_break_2.ogg"),
	],
	"platform_break": [
		preload("res://assets/audio/sfx/platform_break_1.ogg"),
		preload("res://assets/audio/sfx/platform_break_2.wav"),
	],
	# The "something is coming" tell in front of a telegraphed enemy attack —
	# dodge-the-tell only works if the tell is audible as well as visible.
	"telegraph": [
		preload("res://assets/audio/sfx/telegraph_1.wav"),
		preload("res://assets/audio/sfx/telegraph_2.wav"),
	],

	# ======================================================= LEGACY ALIASES
	# Keys the game already calls, re-pointed at better recordings so ~20 call
	# sites got an upgrade without being edited. Same key, same behaviour, new
	# source. The forward-looking name is given for each — see the handoff list.
	# `beam`   -> beam_arcane   (one key was serving five different beams)
	"beam": [
		preload("res://assets/audio/sfx/beam_arcane_1.ogg"),
		preload("res://assets/audio/sfx/beam_arcane_2.ogg"),
	],
	# `ice`    -> ice_wall      (its only gameplay caller is IceWall.gd)
	"ice": [
		preload("res://assets/audio/sfx/ice_wall_1.ogg"),
		preload("res://assets/audio/sfx/ice_wall_2.ogg"),
	],
	# `earth`  -> earth_wall
	"earth": [
		preload("res://assets/audio/sfx/earth_wall_1.ogg"),
		preload("res://assets/audio/sfx/earth_wall_2.ogg"),
	],
	# `cannon` -> holy_pillar. All three callers (DivineRay x2, StarConvergence)
	# are pillar slams, and the old clip was a synth placeholder.
	"cannon": [
		preload("res://assets/audio/sfx/holy_pillar_1.wav"),
		preload("res://assets/audio/sfx/holy_pillar_2.wav"),
	],
	# `footstep` -> step. Kept because Hero.gd and SpikeFigure.gd call this name.
	"footstep": [
		preload("res://assets/audio/sfx/step_1.wav"),
		preload("res://assets/audio/sfx/step_2.wav"),
		preload("res://assets/audio/sfx/step_3.wav"),
		preload("res://assets/audio/sfx/step_4.wav"),
	],

	# =============================================================== STEMS
	# Not fired directly by gameplay: `play()` rides these UNDER the keys above
	# per the PROFILE table. `sub_boom` is now a real trailer boom rather than a
	# synthesised sine — it is the layer that decides whether anything feels heavy.
	"sub_boom": [
		preload("res://assets/audio/sfx/sub_boom_1.wav"),
		preload("res://assets/audio/sfx/sub_boom_2.wav"),
	],
	"rumble": [
		preload("res://assets/audio/sfx/rumble_1.wav"),
		preload("res://assets/audio/sfx/rumble_2.wav"),
	],
	"crack": [
		preload("res://assets/audio/sfx/crack_1.wav"),
		preload("res://assets/audio/sfx/crack_2.wav"),
	],
}

# ===========================================================================
# THE MIX. Every tunable in this file lives between here and DEFAULT_PROFILE, so
# a tuning pass with ears on it is one contiguous block of edits.
# ===========================================================================

## How much a sound COSTS — the same vocabulary SpellTier.gd uses to grade
## spells, extended down one shelf for footsteps and UI blips. Grading by class
## rather than per-key means a new sound only has to answer "how big is this?".
enum Weight { TICK, QUICK, HEAVY, ULT }

## Class trim in dB, added on top of whatever the call site asked for.
## The spread widened from 10 dB to 14 dB when the SFX bus compressor was
## loosened (-14/4.0 -> -8/2.5): under the old hard ceiling the only way to buy
## contrast was to push the floor down, and everything ended up small. There is
## real headroom above now, so the top of the range uses it.
const WEIGHT_TRIM_DB: Array[float] = [
	-11.0,  # TICK  — footsteps, rime ticks, whiffs. Present, never noticed.
	-6.0,   # QUICK — bolts, casts, small impacts. The bed of the fight.
	-1.5,   # HEAVY — real hits and mid-tier spells.
	3.0,    # ULT   — the ones that shake the screen.
]

## Music ducking per class, so an ult carves its own hole in the bed. Only ULT
## ducks — pumping the music on every melee hit would read as a broken mix.
const WEIGHT_DUCK_DB: Array[float] = [0.0, 0.0, 0.0, 9.0]
const WEIGHT_DUCK_HOLD: float = 0.4

## Base pitch of the `sub_boom` stem per class — the heavier the event, the lower
## the weight layer sits, so an ult's low end is genuinely below a melee thud's.
const WEIGHT_SUB_PITCH: Array[float] = [1.35, 1.30, 1.15, 0.92]

## Layer levels, relative to the (already trimmed) level of the sound they ride
## under. All three sit well below the main hit — the point is to be FELT, not
## heard as a second sound effect.
const SUB_DB: float = -3.0     # weight layer
const TAIL_DB: float = -8.0    # room tail
const CRACK_DB: float = -6.0   # borrowed attack for sounds that have none

## When each layer lands, in seconds after the main hit. The sub is nearly
## simultaneous (it IS the hit's body); the tail is late enough to read as an
## answer rather than as part of the impact.
const SUB_DELAY: float = 0.012
const TAIL_DELAY: float = 0.06

## Per-play level jitter (± dB). The cheapest cure for one-shot sameness: the
## same sample at the same level twice in a row is what reads as "cheap".
const LEVEL_JITTER_DB: float = 1.6

## ══ THE KEYS THAT ACTUALLY REPEAT ═══════════════════════════════════════════════
## Only these five go through the repeat governor in `play()`. They are the ones a
## duel fires several times a second: the melee connect, the bolt connect, the hurt
## grunt, the reward ring and the swing itself.
##
## ⚠ `enemy_death` IS DELIBERATELY NOT HERE. It is also fired by `DestructibleProp`,
## `BreakablePlatform`, `DestructibleTerrain`, `DestructibleFloor`, `RockWall` and
## `Thrall` — so governing it would swallow "that crate broke" the moment one spell
## clears several props, which is feedback the player acts on rather than noise.
## Same reasoning excludes `telegraph`: it is the tower's dodge-the-tell cue and it
## has to cut through a busy fight by design.
const REPEAT_GOVERNED: Array[String] = [
	"melee_hit", "spell_impact", "hero_hurt", "ding", "melee_swing",
]
## Two hits closer together than this are one hit as far as an ear is concerned.
const REPEAT_FLOOR_MS: int = 60
## Inside this window a repeat is ducked and stripped of its layers.
const REPEAT_WINDOW_MS: int = 190
const REPEAT_TRIM_DB: float = -4.5

## Last play time per governed key. Not per-emitter: the complaint is about the
## SCREEN's total noise, and two fighters landing alternate blows produce the same
## smear as one fighter landing two.
var _last_play_ms: Dictionary = {}

# ---------------------------------------------------------------------------
# THE LENGTH PROBLEM — "the sound fx are too long compared to the cast itself"
# ---------------------------------------------------------------------------
# The maker's report, 2026-08-04, about the big spells. It is not a mixing
# complaint and no amount of trim fixes it: the CLIPS ARE SIMPLY LONGER THAN THE
# SPELLS. Measured (source length / the picture it is voicing):
#
#   beam_storm_1.ogg   20.70 s   Tempest        0.48 s of beam after discharge
#   thunder_1.ogg       5.27 s   Heaven's Wrath  played at pitch 0.72 => 7.3 s
#   nova_1/2.wav        3.82 s   Energy Nova    0.26 s shockwave, node dead at 0.7 s
#   ice_wall_1/2.ogg    2.53 s   Ice Wall       RISE_TIME 0.30 s
#   ult_siege_1/2.wav   2.00 s   Star Convergence 0.12 hold + 0.55 fade = 0.67 s
#   earth_pillar, ult_eruption, verdict_burn, holy_pillar, rx_annihilate,
#   hollow_erase, ult_avalanche, ult_bombardment, avalanche, rx_overpower
#                       2.00 s   ...every one of them, against a sub-second picture
#   rumble_1/2.wav      2.00 s   the ROOM TAIL rides under EVERY ult (see TAIL_DB)
#   sub_boom_1/2.wav    1.80 s   the weight layer rides under nearly everything
#
# ⚠ The last two are why this reads as a mix-wide problem rather than a handful
# of bad files: even a cue whose own clip is short drags a 1.8 s sub and a 2.0 s
# rumble behind it, so EVERY heavy event had a two-second hangover.
#
# THE FIX IS A CAP, NOT PER-FILE SURGERY. Trimming the assets means re-running
# `python-tools/build_combat_sfx.py` with a new window per entry, guessing again
# with no ears, and it would still leave the next imported clip free to be four
# seconds long. Capping at PLAYBACK makes "no cue outlives its picture" a
# property of the mix that new content inherits for free.

## The longest AFTERMATH any big spell actually draws. DERIVED — it is the
## largest picture-length in the ult set, read off the spells themselves:
##
##   BeamSpell     FIRE_TIME 0.26 + FADE_TIME 0.22          = 0.48 s
##   StarConverge  IMPACT_HOLD 0.12 + FADE_TIME 0.55        = 0.67 s
##   EnergyNova / BlastSpell   CLEANUP_DELAY                = 0.70 s
##   DivineRay     PILLAR_HOLD 0.06 + FADE_TIME 0.85        = 0.91 s  <- the longest
##
## So by ~0.9 s after a discharge there is nothing left on screen, and anything
## still sounding is audio with no picture. That is exactly the desync reported.
## ⚠ If a spell is ever given a longer aftermath than DivineRay's, this number is
## the one that has to move — it is a measurement, not a taste.
const SPECTACLE_TAIL: float = 0.9

## The cap for a DISCHARGE cue — a payoff that has to land with its picture and
## leave with it. Also the cap for the sub/tail/crack stems, so the room's answer
## dies just as the picture clears rather than a second later.
const CUE_MAX_LEN: float = SPECTACLE_TAIL

## The cap for a PROCESS cue — a windup / channel / gather, marked `"hold": true`
## in PROFILE. These are the one family that is SUPPOSED to sustain: cutting a
## charge riser at 0.9 s would leave the back half of a 1.6 s levitating channel
## in silence, which is a worse bug than the one being fixed.
##
## DERIVED from SpellLibrary: the longest `cast_time` in the game is Equinox's
## 1.6 s, and `Hero._begin_channel` runs the levitating windup for exactly that
## long. So the windup cue fades out precisely as the discharge lands on top of
## it — which is what a windup is for.
## ⚠ Read it off `SpellLibrary` again if a longer channel is ever authored; a
## windup that goes quiet mid-channel is a worse bug than the overhang this file
## exists to cut.
const HOLD_MAX_LEN: float = 1.6

## The cut is a FADE, not a stop. A 20-second loop silenced mid-sample clicks,
## and a click is more noticeable than the overhang was. 120 ms is long enough to
## kill the click and short enough that the ear still hears a cue that ENDED
## rather than one that faded away.
## ⚠ The fade runs INSIDE the cap, not after it — total audible length is the cap.
const CUE_FADE: float = 0.12

## How far the fade drops before the voice is stopped. RELATIVE to whatever level
## the cue was playing at, so a quiet cue and a loud one fade over the same curve
## instead of the quiet one snapping off early. -36 dB is inaudible under a fight.
const CUT_DROP_DB: float = -36.0

## Per-key mix profile.
##   w     — Weight class (drives trim, ducking, sub pitch).
##   trim  — extra per-key dB on top of the class trim.
##   sub   — strength 0..1 of the low-end weight layer (0 = none).
##   tail  — strength 0..1 of the room rumble.
##   crack — strength 0..1 of a borrowed transient, for sounds with no attack.
##   hold  — true for a PROCESS cue (windup / channel / gather / warning) that is
##           meant to SUSTAIN under something else. Raises its length cap from
##           CUE_MAX_LEN to HOLD_MAX_LEN — see THE LENGTH PROBLEM above.
##           ⚠ This is NOT the same axis as weight. `charge_ult` is HEAVY and
##           holds; `beam_frost` is HEAVY and must not. The question is "is this
##           a process or a payoff?", and no weight class answers it.
## Unlisted keys fall back to DEFAULT_PROFILE — but the test suite requires every
## roster key to appear here, because "it fell back to the default" is
## indistinguishable from "nobody decided" six months later.
const PROFILE: Dictionary = {
	# --- CASTING. A cast is a promise, not a payoff: subs give the big ones
	# dread, but the TAIL belongs to the discharge that follows, and putting one
	# here would step on it.
	# EVERY key in this block HOLDS. A cast is the one thing in the roster that is
	# supposed to still be sounding a second later — it is covering a channel the
	# player can see (`Hero._begin_channel`), and cutting it to the discharge cap
	# would put the back half of every big windup in silence.
	"cast": {"w": Weight.QUICK, "hold": true},
	"cast_fire": {"w": Weight.QUICK, "sub": 0.2, "hold": true},
	"cast_ice": {"w": Weight.QUICK, "hold": true},
	"cast_earth": {"w": Weight.QUICK, "sub": 0.3, "hold": true},
	"cast_shadow": {"w": Weight.QUICK, "sub": 0.35, "hold": true},
	"cast_holy": {"w": Weight.QUICK, "crack": 0.2, "hold": true},
	# ⚠ cast_storm_1.ogg is TWENTY-ONE SECONDS — `electricspell2.ogg` shipped
	# `copy=True` (byte-for-byte, no window) out of build_combat_sfx.py, and it is
	# an ambient spell LOOP, not a one-shot. The cap makes it usable; it does not
	# make it right. See the handoff note in THE LENGTH PROBLEM.
	"cast_storm": {"w": Weight.QUICK, "trim": -1.0, "hold": true},
	"cast_arcane": {"w": Weight.QUICK, "hold": true},
	"charge_up": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.45, "hold": true},
	"charge_ult": {"w": Weight.HEAVY, "trim": 1.0, "sub": 0.7, "hold": true},
	# Quiet process cues. They run UNDER the cast, not next to it.
	"sigil_form": {"w": Weight.TICK, "trim": 2.0, "hold": true},
	"levitate": {"w": Weight.QUICK, "trim": -3.0, "sub": 0.3, "hold": true},

	# --- BEAMS. Screen-crossing lines that are bright and mid-heavy: they need
	# the borrowed crack to land on an exact frame and the sub to have any size.
	"beam": {"w": Weight.ULT, "sub": 0.6, "tail": 0.55, "crack": 0.45},
	"beam_arcane": {"w": Weight.ULT, "sub": 0.6, "tail": 0.55, "crack": 0.45},
	# Frostpiercer is the THINNEST beam — a precision poke thrown all fight, not
	# a finisher — so it is graded down a shelf and carries almost no low end.
	"beam_frost": {"w": Weight.HEAVY, "sub": 0.3, "tail": 0.3, "crack": 0.5},
	# Infernal Lance is the FATTEST. Everything on, wide open.
	"beam_fire": {"w": Weight.ULT, "trim": 1.0, "sub": 0.9, "tail": 0.7, "crack": 0.45},
	"beam_shadow": {"w": Weight.ULT, "sub": 0.75, "tail": 0.6, "crack": 0.3},
	# ⚠ NOT a hold, despite being the worst offender in the roster. Tempest is a
	# DISCHARGE — 0.48 s of beam after the cue fires — and beam_storm_1.ogg is
	# 20.70 s, the same `copy=True` accident as cast_storm. The cap cuts it to
	# 0.9 s; what it plays is the HEAD of a spell loop, which is a content
	# question the cap cannot answer. Flagged for a re-window, not a re-grade.
	"beam_storm": {"w": Weight.ULT, "sub": 0.6, "tail": 0.5, "crack": 0.6},
	# Layered under a beam by its call site, so no layers of their own.
	"beam_start": {"w": Weight.HEAVY, "trim": -2.0},
	"beam_end": {"w": Weight.QUICK, "trim": -2.0},

	# --- ICE. Bright and glassy; small subs, short tails.
	"ice": {"w": Weight.HEAVY, "sub": 0.38, "tail": 0.22},
	"ice_wall": {"w": Weight.HEAVY, "sub": 0.38, "tail": 0.22},
	"ice_spine": {"w": Weight.HEAVY, "trim": 1.0, "sub": 0.45, "tail": 0.3},
	"ice_throw": {"w": Weight.QUICK, "sub": 0.15},
	# A FIELD, not a hit: ZoneSpell keeps one on the floor for `length` seconds
	# (4.2 s for the frost zone), so its voice is allowed the process cap.
	"frost_field": {"w": Weight.HEAVY, "sub": 0.3, "tail": 0.35, "hold": true},
	# The rime meter filling. Fires repeatedly, so it must be the quietest thing
	# in the roster and carry NO layers at all — a sub under every tick would
	# turn a rising meter into a drum loop.
	"rime_tick": {"w": Weight.TICK, "trim": -2.0},
	"ice_encase": {"w": Weight.HEAVY, "sub": 0.4, "tail": 0.25},
	# The payoff of the whole trap. It is allowed to be an event.
	"ice_shatter": {"w": Weight.ULT, "trim": -1.0, "sub": 0.7, "tail": 0.6, "crack": 0.4},

	# --- EARTH. Heavy and repeatable: small subs, short or no tails, because
	# these fire in bunches and a long tail on each would be mud.
	"earth": {"w": Weight.HEAVY, "sub": 0.8, "tail": 0.55},
	"earth_wall": {"w": Weight.HEAVY, "sub": 0.8, "tail": 0.55},
	"earth_pillar": {"w": Weight.ULT, "trim": 1.0, "sub": 1.0, "tail": 0.9, "crack": 0.5},
	"earth_hurl": {"w": Weight.QUICK, "sub": 0.35},
	"earth_impact": {"w": Weight.HEAVY, "sub": 0.7, "tail": 0.3},
	"avalanche": {"w": Weight.ULT, "sub": 0.9, "tail": 0.8},
	"rubble": {"w": Weight.QUICK, "trim": -2.0, "sub": 0.25},

	# --- LIGHTNING. Electricity is all high-frequency crack; the sub is what
	# stops it sounding like static.
	"zap": {"w": Weight.HEAVY, "sub": 0.3, "tail": 0.18},
	"zap_arc": {"w": Weight.HEAVY, "sub": 0.35, "tail": 0.2},
	"zap_chain": {"w": Weight.QUICK, "trim": -1.0, "sub": 0.15},
	"thunder": {"w": Weight.ULT, "sub": 1.0, "tail": 1.0},

	# --- SHADOW. Low, tonal, wrong. Shadow spells take their weight from the sub
	# rather than from level — present without being loud.
	"shadow_cast": {"w": Weight.QUICK, "sub": 0.4},
	"shadow_crawl": {"w": Weight.QUICK, "trim": -2.0, "sub": 0.5},
	"shadow_root": {"w": Weight.HEAVY, "sub": 0.45, "tail": 0.25},
	# A PULL is a process — Grave Tide holds one open for HOLD_TIME 1.7 s — so the
	# suck has to keep sucking rather than stop while the bodies are still moving.
	"void_pull": {"w": Weight.HEAVY, "sub": 0.8, "tail": 0.4, "hold": true},
	"rift_open": {"w": Weight.QUICK, "trim": -1.0, "crack": 0.35},

	# --- HOLY. Pure swells with NO transient — without a borrowed crack the ear
	# never registers the frame the seal opened.
	"holy": {"w": Weight.HEAVY, "sub": 0.35, "tail": 0.5, "crack": 0.3},
	"holy_swell": {"w": Weight.HEAVY, "sub": 0.35, "tail": 0.5, "crack": 0.3},
	"holy_pillar": {"w": Weight.ULT, "trim": 1.0, "sub": 1.0, "tail": 1.0, "crack": 0.55},
	# The thread is TENSION, not impact: quiet, no low end, and its whole job is
	# to make the burn-down that follows land. It therefore HOLDS by definition —
	# a thread that stops sounding before it burns is just a click.
	"verdict_thread": {"w": Weight.QUICK, "trim": -2.0, "crack": 0.2, "hold": true},
	"verdict_burn": {"w": Weight.ULT, "sub": 0.95, "tail": 1.0},
	"ward_raise": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.3, "crack": 0.3},
	# ABSORB is a SWALLOW. No tail, no crack: the ward has to sound like it took
	# the hit AWAY, which is the opposite of an impact.
	"ward_absorb": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.45},
	"ward_crack": {"w": Weight.QUICK, "trim": 1.0, "crack": 0.3},
	"ward_break": {"w": Weight.ULT, "trim": -1.0, "sub": 0.7, "tail": 0.7, "crack": 0.5},

	# --- ULTS. The screen-shakers. These are what the maker is watching when the
	# audio reads small, so they get all three layers.
	"blast": {"w": Weight.ULT, "sub": 0.9, "tail": 0.8},
	"nova": {"w": Weight.ULT, "sub": 0.85, "tail": 0.7},
	"cannon": {"w": Weight.ULT, "trim": 1.0, "sub": 1.0, "tail": 1.0, "crack": 0.55},
	"ult_siege": {"w": Weight.ULT, "sub": 0.85, "tail": 0.9, "crack": 0.4},
	"ult_bombardment": {"w": Weight.ULT, "sub": 0.9, "tail": 0.85},
	"ult_eruption": {"w": Weight.ULT, "trim": 1.0, "sub": 1.0, "tail": 0.9, "crack": 0.5},
	"ult_avalanche": {"w": Weight.ULT, "sub": 0.95, "tail": 0.85},
	# Floor-hugging: heavy underneath, nothing bright on top.
	"ult_shove": {"w": Weight.ULT, "trim": -1.0, "sub": 1.0, "tail": 0.5},
	# ABSENCE. Trimmed 12 dB below its own class and stripped of every layer, but
	# left at ULT weight so the music ducks. The ducking is the sound.
	"ult_unmaking": {"w": Weight.ULT, "trim": -12.0},
	# The INTAKE is Hollow Purple's held beat — the gather before the erasure — so
	# it holds; `hollow_erase` on the next line is the payoff and does not.
	"hollow_intake": {"w": Weight.HEAVY, "sub": 0.7, "hold": true},
	"hollow_erase": {"w": Weight.ULT, "trim": 1.0, "sub": 1.0, "tail": 1.0, "crack": 0.4},

	# --- DRAIN TETHER. The lash is a whip crack: it already has the sharpest
	# transient in the roster, so it borrows nothing and only wants weight.
	"whip_lash": {"w": Weight.HEAVY, "sub": 0.4},
	"whip_bite": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.3},
	"drain_pull": {"w": Weight.QUICK, "trim": -2.0, "sub": 0.35},
	"tether_tear": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.25, "crack": 0.3},
	# It bit AIR. Thin and empty by design.
	"whip_miss": {"w": Weight.TICK, "trim": 2.0},

	# --- MELEE / CLASH.
	"melee_swing": {"w": Weight.TICK, "trim": 2.0},
	"melee_swing_heavy": {"w": Weight.QUICK, "trim": -1.0, "sub": 0.2},
	"melee_hit": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.22},
	"melee_hit_heavy": {"w": Weight.HEAVY, "trim": 1.0, "sub": 0.55, "tail": 0.25},
	"melee_crit": {"w": Weight.HEAVY, "trim": 2.0, "sub": 0.6, "tail": 0.35, "crack": 0.3},
	# A clash is two people's force cancelling. It should read BIGGER than either
	# hit — that is the whole reason it is its own sound.
	"clash": {"w": Weight.HEAVY, "trim": 1.0, "sub": 0.5, "tail": 0.3, "crack": 0.35},
	"clash_heavy": {"w": Weight.ULT, "trim": -2.0, "sub": 0.8, "tail": 0.6, "crack": 0.4},
	"parry": {"w": Weight.QUICK, "trim": 2.0, "crack": 0.25},
	"block": {"w": Weight.QUICK, "trim": 1.0, "sub": 0.2},
	"guard_break": {"w": Weight.HEAVY, "trim": 1.0, "sub": 0.5, "tail": 0.3},
	"punch": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.25},
	"kick": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.35},
	# The one QUICK sound allowed to sit forward in the mix — it is the payoff.
	"ding": {"w": Weight.QUICK, "trim": 2.0},

	# --- REACTIONS. Graded by how RARE and how consequential the outcome is: a
	# blocked projectile happens constantly, a mutual annihilation is a moment.
	"rx_steam": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.3, "tail": 0.4},
	"rx_supercharge": {"w": Weight.ULT, "trim": -1.0, "sub": 0.7, "tail": 0.6, "crack": 0.5},
	"rx_shatter": {"w": Weight.ULT, "trim": -1.0, "sub": 0.7, "tail": 0.6, "crack": 0.4},
	"rx_shrapnel": {"w": Weight.HEAVY, "trim": 1.0, "sub": 0.5, "tail": 0.3, "crack": 0.35},
	"rx_void_pull": {"w": Weight.HEAVY, "sub": 0.8, "tail": 0.4},
	"rx_resonance": {"w": Weight.ULT, "trim": -1.0, "sub": 0.6, "tail": 0.9, "crack": 0.3},
	"rx_carve": {"w": Weight.HEAVY, "sub": 0.4, "tail": 0.3},
	"rx_annihilate": {"w": Weight.ULT, "trim": 1.0, "sub": 1.0, "tail": 1.0, "crack": 0.55},
	"rx_breach": {"w": Weight.ULT, "trim": -1.0, "sub": 0.85, "tail": 0.7, "crack": 0.4},
	"rx_ward_absorb": {"w": Weight.HEAVY, "trim": -1.0, "sub": 0.45},
	"rx_overpower": {"w": Weight.ULT, "trim": -1.0, "sub": 0.9, "tail": 0.8},
	"rx_ground_out": {"w": Weight.HEAVY, "trim": -2.0, "sub": 0.5, "tail": 0.25},
	"rx_field_merge": {"w": Weight.HEAVY, "trim": -2.0, "sub": 0.5, "tail": 0.4},
	# Consequential and rare (holy is the only element that counters a void
	# field), so it is graded up — but no crack: nothing is being STRUCK.
	"rx_banish": {"w": Weight.HEAVY, "trim": 1.0, "sub": 0.5, "tail": 0.6},
	"rx_blocked": {"w": Weight.QUICK, "trim": 1.0, "sub": 0.2},

	# --- VOICE. A voice is CHARACTER, not an impact: it must never fight the
	# spell that just went off, and a three-syllable line fires three of these
	# inside a fifth of a second, so they are layer-free for exactly the reason
	# footsteps are. Graded one notch above the TICK floor because dialogue that
	# cannot be heard over a fight is not dialogue.
	"voice_a": {"w": Weight.TICK, "trim": 4.0},
	"voice_e": {"w": Weight.TICK, "trim": 4.0},
	"voice_i": {"w": Weight.TICK, "trim": 3.0},
	"voice_u": {"w": Weight.TICK, "trim": 4.5},

	# --- BODIES.
	# ⚠ Graded DOWN from HEAVY/-1.0 on 2026-08-04. This is the highest-cadence
	# cue in the game — a wave death every couple of seconds, plus every crate and
	# wall — and the maker asked for it "more subtle". HEAVY is the shelf for a
	# real hit; a thing ceasing to exist is a full stop, not a hit. Net ~4.5 dB
	# down here, ~3 dB more at the source clip.
	"enemy_death": {"w": Weight.QUICK, "trim": 0.0, "sub": 0.25},
	"enemy_death_big": {"w": Weight.ULT, "trim": -2.0, "sub": 0.8, "tail": 0.7},
	"enemy_hurt": {"w": Weight.QUICK, "trim": -1.0, "sub": 0.15},
	"hero_hurt": {"w": Weight.QUICK, "sub": 0.2},
	"body_fall": {"w": Weight.QUICK, "trim": -1.0, "sub": 0.4},
	"gib": {"w": Weight.HEAVY, "sub": 0.5, "tail": 0.3},
	"spell_impact": {"w": Weight.QUICK, "sub": 0.18},

	# --- MOVEMENT / WORLD. Feet stay layer-free: a sub under every step would be
	# absurd, and at running cadence the tails would stack into mush.
	"step": {"w": Weight.TICK},
	"footstep": {"w": Weight.TICK},
	"land": {"w": Weight.QUICK, "sub": 0.35},
	"dash": {"w": Weight.TICK, "trim": 2.0},
	"blink": {"w": Weight.QUICK, "sub": 0.18},
	"crate_break": {"w": Weight.HEAVY, "trim": -2.0, "sub": 0.3},
	"platform_break": {"w": Weight.HEAVY, "sub": 0.6, "tail": 0.4},
	# A warning has to cut through the fight or it is not a warning — and it has to
	# last as long as the window it is warning about, so it holds. Dodge-the-tell
	# breaks if the tell goes quiet while the tell is still on screen.
	"telegraph": {"w": Weight.HEAVY, "trim": 1.0, "crack": 0.3, "hold": true},

	# --- STEMS, when played directly (they normally arrive via the layer path,
	# which bypasses this table). No layers => no recursion even if something
	# does call them by name.
	"sub_boom": {"w": Weight.QUICK},
	"rumble": {"w": Weight.QUICK},
	"crack": {"w": Weight.QUICK},
}

const DEFAULT_PROFILE: Dictionary = {"w": Weight.QUICK}

## ReactionTable outcome string -> roster key. THIS is the contract for the
## spell-vs-spell reaction work; `reaction_sound()` is the accessor.
##
## It is not a 1:1 name mapping and deliberately so:
##   * `shatter_ward` is a WARD BREAK, not a generic shatter — the ward has its
##     own three-beat vocabulary (raise / absorb / crack / break) and borrowing
##     the ice shatter here would erase the distinction the spell is built on.
##   * `hollow_purple` gets the erasure lance; its INTAKE (`hollow_intake`) is a
##     separate beat the outcome should fire first, on a delay.
##   * `void_charged` and the void pull are the same event under two names.
##   * `none` maps to "" — a suppressed rule must stay silent, and returning ""
##     is how a caller tells "no sound by design" from "key missing".
##
## Anything not listed returns "". If a new outcome needs a voice, ask for one
## rather than pointing it at the nearest existing key — the whole reason the
## roster grew was that near-misses read as wrong.
const REACTION_SOUND: Dictionary = {
	"steam_cloud": "rx_steam",
	"supercharge": "rx_supercharge",
	"shatter_ice_barrier": "rx_shatter",
	"shrapnel_cone": "rx_shrapnel",
	"void_charged": "rx_void_pull",
	"beam_resonance": "rx_resonance",
	"carve": "rx_carve",
	"mutual_annihilation": "rx_annihilate",
	# Two bolts popping each other. Shares `rx_overpower` rather than the annihilate
	# pair on purpose: this fires several times a duel, and the annihilate cue is the
	# beam clash's voice — spending it here would flatten the loud one.
	"bolt_fizzle": "rx_overpower",
	"breach": "rx_breach",
	"ward_absorb": "rx_ward_absorb",
	"overpower": "rx_overpower",
	"ground_out": "rx_ground_out",
	"field_merge": "rx_field_merge",
	"barrier_blocks": "rx_blocked",
	"banish": "rx_banish",
	"shatter_ward": "ward_break",
	"hollow_purple": "hollow_erase",
	"none": "",
}


## The roster key for a ReactionTable outcome, or "" when the outcome is silent
## by design or has no voice yet. Callers should treat "" as "play nothing" —
## never as a reason to substitute another key.
func reaction_sound(outcome: String) -> String:
	return String(REACTION_SOUND.get(outcome, ""))

const SFX_BUS: StringName = &"SFX"
## One ULT occupies four voices at once (main + crack + sub + tail), a flurry
## overlaps several events, and a spell-vs-spell reaction can fire on top of both
## while two beams are still sounding. AudioStreamPlayers are cheap; running out
## of them mid-clash is not.
const POOL_SIZE: int = 32

## One speaker may not start a new utterance inside this window — see `speak()`.
## Roughly the length of the longest single syllable, so a yelp always finishes.
const VOICE_MIN_INTERVAL_MS: int = 140
## Extra per-syllable pitch wobble on top of the deterministic one `Gibberish`
## already bakes in. Small: the identity is in the plan, this is just breath.
const VOICE_PITCH_JITTER: float = 0.02

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last_variant: Dictionary = {}  # key -> last index played, to avoid immediate repeats
var _last_spoke: Dictionary = {}    # voice seed -> Time.get_ticks_msec() of last utterance
## pool slot -> the in-flight length-cap fade on it, so the slot's next occupant
## can kill it before it fades THEM out. See _kill_cut.
var _cuts: Dictionary = {}


## Frames to keep looking for a real scene before giving up on installing the
## VoiceDirector. Autoloads are ready BEFORE the main scene exists, so this
## cannot happen in `_ready`. Under `--script` there is never a current scene, so
## this simply expires and the headless suites never see a director at all.
const DIRECTOR_SPAWN_FRAMES: int = 180

var _director_frames: int = 0


func _ready() -> void:
	# Keep SFX audible while hit-stop slows the game clock.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_pool()
	set_process(true)


## The ONLY thing this _process does is install the voice/bark observer once the
## game has a scene, then switch itself off. Note it adds the director to the
## tree ROOT, never as a child of this node: `Sfx`'s children are its voice pool
## and exactly its voice pool (tools/slice_test_sfx_roster.gd asserts the count),
## and a stray non-AudioStreamPlayer child there would be a real bug, not just a
## red test.
func _process(_delta: float) -> void:
	_director_frames += 1
	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		VoiceDirector.ensure(tree)
		set_process(false)
	elif _director_frames >= DIRECTOR_SPAWN_FRAMES:
		set_process(false)


## Build the voice pool. Idempotent, and called from _emit_now as well as _ready:
## autoload order and scene _ready order both mean something can ask for a sound
## before this node's own _ready has run, and an unbuilt pool would spam
## out-of-bounds on every call instead of just playing.
func _ensure_pool() -> void:
	if not _players.is_empty():
		return
	var has_sfx_bus: bool = AudioServer.get_bus_index(SFX_BUS) != -1
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		if has_sfx_bus:
			p.bus = SFX_BUS
		add_child(p)
		_players.append(p)


## Play a named SFX, with its weight-class trim, level jitter and any automatic
## sub/tail/crack layers from PROFILE.
##
## `volume_db` is what the CALL SITE asks for — the class trim is added on top,
## so existing relative mixing at call sites (a quieter secondary whiff, a louder
## payoff ding) is preserved exactly.
## `pitch_variation` is a ± fraction (0.08 = ±8%).
## `pitch_base` re-pitches the sample before the jitter (0.7 = a deeper thud from
## the same clip — lets one asset serve as several events).
## `delay` postpones the whole event (layers included) — for a call site that
## wants a beat between, say, a cast and its discharge.
func play(
	key: String,
	volume_db: float = 0.0,
	pitch_variation: float = 0.06,
	pitch_base: float = 1.0,
	delay: float = 0.0
) -> void:
	var prof: Dictionary = PROFILE.get(key, DEFAULT_PROFILE)
	var weight: int = int(prof.get("w", Weight.QUICK))
	var db: float = volume_db \
		+ WEIGHT_TRIM_DB[weight] \
		+ float(prof.get("trim", 0.0)) \
		+ randf_range(-LEVEL_JITTER_DB, LEVEL_JITTER_DB)
	# How long this cue is allowed to sound before it is faded out — the fix for
	# "the sound fx are too long compared to the cast itself". See THE LENGTH
	# PROBLEM. A payoff gets the discharge cap; a windup gets the channel cap.
	var max_len: float = HOLD_MAX_LEN if bool(prof.get("hold", false)) else CUE_MAX_LEN
	# ══ THE REPEAT GOVERNOR ═════════════════════════════════════════════════════
	# Maker, watching a duel: *"it becomes noise slop right now because they are
	# repeatedly getting hit"*. Measured: this file had NO throttle of any kind — no
	# per-key cooldown, no same-sound-within-N-ms suppression, no concurrency cap. A
	# busy exchange makes ~20-25 `play()` calls a second and starts ~35-40 VOICES,
	# against a 32-slot round-robin pool, so the pool wraps about once a second and
	# overwrites cues mid-tail with no crossfade. That is the mush.
	#
	# It thins rather than mutes, and only for the handful of keys that actually
	# repeat (see `REPEAT_GOVERNED`). The first hit of a flurry lands at full weight;
	# the ones behind it duck under it and drop their sub/tail layers, so three
	# connects read as ONE impact with texture instead of three equal bangs — which is
	# also what they look like on screen.
	#
	# ⚠ PER-KEY, NEVER A GLOBAL RATE BUDGET. `slice_test_sfx_mix` and
	# `slice_test_sfx_roster` play the WHOLE roster inside a single frame and assert
	# every pool slot received a stream; a global "N sounds per 100 ms" cap would
	# suppress most of that sweep and fail both suites for the wrong reason. Each key
	# is played once per sweep, so a per-key window never triggers there.
	var layered: bool = true
	if REPEAT_GOVERNED.has(key):
		var now_ms: int = Time.get_ticks_msec()
		var since: int = now_ms - int(_last_play_ms.get(key, -100000))
		if since < REPEAT_FLOOR_MS:
			# Physically indistinguishable from the one before it — two sources landing
			# on the same frame. Mirrors `CharacterRig.STEP_SFX_MIN_GAP`, which is the
			# same guard already written for footsteps.
			return
		if since < REPEAT_WINDOW_MS:
			# Inside the flurry: duck it and strip the layers. Skipping the layers is
			# the bigger win of the two — it takes a three-connect trade from about
			# eighteen voices to eight.
			db += REPEAT_TRIM_DB
			layered = false
		_last_play_ms[key] = now_ms
	# Unknown key: warn and bail BEFORE the layers, so a typo doesn't leave a
	# disembodied sub-boom firing with nothing on top of it.
	if not _emit(key, db, pitch_variation, pitch_base, delay, max_len):
		return
	if not layered:
		return

	# --- automatic layers. These go through _emit, never play(), so a stem can
	# never recurse into its own profile.
	#
	# ⚠ THE STEMS TAKE THE DISCHARGE CAP EVEN UNDER A HOLD CUE, deliberately.
	# sub_boom is 1.8 s and rumble is 2.0 s, and they ride under nearly every
	# heavy key in the roster — so before the cap they, not the main clips, were
	# the reason a two-second hangover followed EVERY big hit. The sub is the
	# hit's body and the tail is the room answering it; neither is a process, and
	# a room that is still answering a second after the picture cleared is the
	# exact desync being fixed. Capped here they land at CUE_MAX_LEN + their own
	# small delay, i.e. just past the picture, which is what "a tail" means.
	var sub: float = float(prof.get("sub", 0.0))
	if sub > 0.0:
		_emit(
			"sub_boom",
			db + SUB_DB + linear_to_db(sub),
			0.05,
			WEIGHT_SUB_PITCH[weight],
			delay + SUB_DELAY,
			CUE_MAX_LEN
		)
	var tail: float = float(prof.get("tail", 0.0))
	if tail > 0.0:
		_emit(
			"rumble",
			db + TAIL_DB + linear_to_db(tail),
			0.08,
			1.0,
			delay + TAIL_DELAY,
			CUE_MAX_LEN
		)
	var crack: float = float(prof.get("crack", 0.0))
	if crack > 0.0:
		_emit("crack", db + CRACK_DB + linear_to_db(crack), 0.1, 1.0, delay, CUE_MAX_LEN)

	var duck_db: float = WEIGHT_DUCK_DB[weight]
	if duck_db > 0.0:
		# Resolve the Music autoload via the tree (not the global identifier) so
		# this compiles in isolated --script test contexts where autoloads aren't
		# registered. Relative-from-root, not the absolute "/root/Music": a
		# --script context has no active scene and an absolute get_node errors
		# there on every call.
		if not is_inside_tree():
			return
		var music: Node = get_tree().root.get_node_or_null(^"Music")
		if music != null and music.has_method(&"duck"):
			music.call(&"duck", duck_db, WEIGHT_DUCK_HOLD)


# ===========================================================================
# THE VOICE — gibberish, Animal Crossing style
# ===========================================================================
## Speak a short run of gibberish syllables in ONE character's voice.
##
## `voice_seed` is any stable integer for the speaker — `Gibberish.seed_for(name)`
## or `Gibberish.voice_of(node)["seed"]`. The same seed always produces the same
## bank, pitch band and cadence, so a fighter sounds like itself for the whole
## climb with nothing stored and nothing replicated.
##
## THIS ADDS NO SECOND AUDIO POOL. Every syllable goes through `_emit`, i.e. the
## same 32-voice round-robin everything else uses. A voice is by far the cheapest
## thing in the roster (TICK weight, no sub/tail/crack layers), so a room of
## chattering mobs costs a handful of pool slots, not a mixer.
##
## Deliberately fire-and-forget: it never awaits, never blocks, and returns the
## utterance's duration in seconds so a caller can hold a speech bubble up for
## exactly as long as the mouth is moving.
func speak(
	voice_seed: int,
	mood: int = 0,
	syllables: int = 0,
	volume_db: float = 0.0,
	delay: float = 0.0
) -> float:
	return speak_voice(Gibberish.voice(voice_seed), mood, syllables, volume_db, delay)


## Same, from an ALREADY-BUILT voice dict.
##
## This is the real body of `speak()`, split out for the one case the seed-only
## form cannot express: a speaker whose pitch band is pinned rather than rolled.
## `Gibberish.voice_in_bands` exists because a guardian that rolled the top band
## sounds like the thing it just ate, and a caller holding that dict has nowhere to
## put it if the only entry point takes an integer. Everything else — the
## per-speaker interval floor, the pool, the fire-and-forget contract — is
## identical, and `speak()` is now literally one line of this.
func speak_voice(
	v: Dictionary,
	mood: int = 0,
	syllables: int = 0,
	volume_db: float = 0.0,
	delay: float = 0.0
) -> float:
	var voice_seed: int = int(v.get("seed", 0))
	var plan: Array = Gibberish.plan(v, mood, syllables)
	if plan.is_empty():
		return 0.0
	# One speaker cannot talk over itself. Without this, a fighter taking three
	# hits in a fifth of a second stacks three yelps into a single smeared noise
	# — the classic "why does the hurt sound break when it matters most".
	var now: int = Time.get_ticks_msec()
	var last: int = int(_last_spoke.get(voice_seed, -100000))
	if now - last < VOICE_MIN_INTERVAL_MS:
		return 0.0
	_last_spoke[voice_seed] = now
	for entry: Dictionary in plan:
		# ⚠ UNCAPPED (max_len 0.0), and the only caller that is. A syllable is
		# 0.09–1.0 s of recorded mouth and its CADENCE is already the plan's job —
		# `Gibberish` decides when the next one starts and `plan_duration` is what
		# a speech bubble is held open for. Cutting a syllable short here would
		# desync the mouth from the bubble to fix a length problem voices do not
		# have (nothing in the voice bank is longer than the discharge cap anyway).
		_emit(
			String(entry["key"]),
			volume_db + float(entry["db"]),
			VOICE_PITCH_JITTER,
			float(entry["pitch"]),
			delay + float(entry["delay"]),
			0.0
		)
	return Gibberish.plan_duration(plan)


## Same, for anything with a name: the usual call site (`Sfx.speak_for(enemy,
## Gibberish.Mood.HURT)`) does not have to know what a seed is.
func speak_for(who: Object, mood: int = 0, syllables: int = 0, volume_db: float = 0.0) -> float:
	return speak_voice(Gibberish.voice_of(who), mood, syllables, volume_db)


## Fire ONE stream. Returns false (and warns) for an unknown key so `play` can
## skip the layers. This is the only place that touches the pool.
##
## `max_len` is the wall-clock ceiling on how long this voice may sound before it
## is faded out (0 = no ceiling). See THE LENGTH PROBLEM.
func _emit(
	key: String,
	volume_db: float,
	pitch_variation: float,
	pitch_base: float,
	delay: float,
	max_len: float = 0.0
) -> bool:
	var variants: Array = STREAMS.get(key, [])
	if variants.is_empty():
		push_warning("Sfx: unknown key '%s'" % key)
		return false
	var stream: AudioStream = _pick_variant(key, variants)
	var pitch: float = pitch_base * (1.0 + randf_range(-pitch_variation, pitch_variation))
	if delay > 0.0:
		_emit_after(stream, volume_db, pitch, delay, max_len)
	else:
		_emit_now(stream, volume_db, pitch, max_len)
	return true


func _emit_now(stream: AudioStream, volume_db: float, pitch: float, max_len: float = 0.0) -> void:
	_ensure_pool()
	var slot: int = _next
	var p: AudioStreamPlayer = _players[slot]
	_next = (_next + 1) % POOL_SIZE
	# ⚠ KILL THE PREVIOUS OCCUPANT'S FADE FIRST. The pool is a 32-slot round-robin
	# and it wraps; without this, a cut tween still running on the slot would keep
	# driving `volume_db` DOWN through the sound that just took the slot over, and
	# the symptom — one sound in thirty-two arriving inaudible, at random — is
	# about as unpleasant a bug as this file could grow.
	_kill_cut(slot)
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	# The voice is fully configured before this check so a headless --script
	# harness (where nothing is really "inside the tree") can still verify the
	# routing, while Godot's "playback can only happen inside the scene tree"
	# error never fires. At runtime this is an autoload and always true.
	if is_inside_tree():
		p.play()
		_cut_to_fit(slot, p, stream, volume_db, pitch, max_len)


## Fade this voice out and stop it once it has sounded for `max_len` seconds — the
## mechanism behind THE LENGTH PROBLEM. No-ops when the clip already fits, which
## is the common case: most of the roster is shorter than the cap and never sees a
## tween at all.
func _cut_to_fit(
	slot: int,
	p: AudioStreamPlayer,
	stream: AudioStream,
	level_db: float,
	pitch: float,
	max_len: float
) -> void:
	if max_len <= 0.0:
		return
	# ⚠ AGAINST THE AUDIBLE LENGTH, NOT THE FILE LENGTH. `pitch_scale` stretches
	# playback, and the call sites lean on it hard for weight: Heaven's Wrath asks
	# for `thunder` at 0.72, which turns a 5.27 s clip into 7.3 s of sound, and
	# Hollow Purple's 0.62 turns a 2.0 s erase into 3.2 s. Comparing raw
	# `get_length()` to the cap would let exactly the biggest, most pitched-down
	# spells — the ones the maker reported — slip through the check.
	var audible: float = stream.get_length() / maxf(pitch, 0.01)
	if audible <= max_len:
		return
	var tw: Tween = p.create_tween()
	# ⚠ Same reasoning as _emit_after's timer flags, and load-bearing for the same
	# reason: hit-stop drives Engine.time_scale toward zero, and a scaled tween
	# would stretch a 0.9 s cap into several seconds on precisely the ULT hits
	# that TRIGGER hit-stop — i.e. it would fail on the only cues this exists for.
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ignore_time_scale(true)
	var hold: float = maxf(max_len - CUE_FADE, 0.0)
	if hold > 0.0:
		tw.tween_interval(hold)
	tw.tween_property(p, "volume_db", level_db + CUT_DROP_DB, CUE_FADE)
	tw.tween_callback(p.stop)
	_cuts[slot] = tw


## Drop any in-flight cut on a pool slot. Safe to call on a slot that never had
## one; `is_valid()` covers the tween having already finished or been freed.
func _kill_cut(slot: int) -> void:
	var existing: Variant = _cuts.get(slot)
	if existing is Tween and (existing as Tween).is_valid():
		(existing as Tween).kill()
	_cuts.erase(slot)


## Deferred variant. The timer is created with process_always AND
## ignore_time_scale: hit-stop drives Engine.time_scale toward zero, and a scaled
## timer would stretch the 60 ms gap between an impact and its tail into a
## quarter of a second — the layering would fall apart exactly on the biggest
## hits, which are the ones that trigger hit-stop.
func _emit_after(
	stream: AudioStream,
	volume_db: float,
	pitch: float,
	delay: float,
	max_len: float = 0.0
) -> void:
	if not is_inside_tree():
		# detached (tests): no timer available
		_emit_now(stream, volume_db, pitch, max_len)
		return
	await get_tree().create_timer(delay, true, false, true).timeout
	_emit_now(stream, volume_db, pitch, max_len)


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
