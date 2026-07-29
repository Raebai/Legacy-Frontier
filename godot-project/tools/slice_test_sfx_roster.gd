# Run: godot --headless --path godot-project --script tools/slice_test_sfx_roster.gd
#
# Covers the SAMPLED ROSTER in Sfx.gd — the ~100-key set mined out of the local
# `Effects/` library (plus a few CC0 downloads) to replace the 23-key set that
# was serving five beams from one `beam` key.
#
# WHAT CANNOT BE TESTED: whether any of it sounds good. Nobody has heard a single
# clip; every one was chosen by filename, folder and duration. "Epic" is not a
# testable property and headless has no audio device.
#
# WHAT CAN: everything that has to hold for the roster to work at all, and every
# one of these has a real failure mode behind it —
#   * every key's streams actually LOAD (a mis-typed filename in a 100-key table
#     is a parse error at boot, and the autoload not compiling takes the game
#     down, not just the sound);
#   * roster and PROFILE cover each other exactly (a profile naming a key that
#     does not exist means play() warns and falls SILENT at that call site);
#   * the layer stems declare no layers of their own (play() would recurse);
#   * the weight grading stays monotonic — the "flat dynamics" fix;
#   * every key the ~20 existing call sites use still exists (the roster grew by
#     re-pointing several of them, and a dropped alias is a silent regression);
#   * REACTION_SOUND only names real keys (it is the API two other agents are
#     wiring against);
#   * pushing every key in the roster through play() is a silent no-op with no
#     audio device, layers and all.
extends SceneTree

# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function, and hands the caller the return type's zero
# value. Under `failed += _test_x()` that reads as "zero failures" while every
# assertion after the dead line is silently skipped. So failures accumulate on
# the MEMBER `_fails` (an abort cannot discard them) and every test records a
# completion sentinel as its last line. A test that aborts part-way is then
# missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion.
const TESTS: Array[String] = [
	"every_stream_loads",
	"roster_covers_call_sites",
	"profile_and_roster_agree",
	"stems_do_not_recurse",
	"weight_grading_is_monotonic",
	"layer_levels_sit_under_the_hit",
	"spell_families_are_distinct",
	"reaction_map_is_wired",
	"unmaking_is_absence",
	"play_every_key_detached",
	"play_every_key_in_tree",
]

var _fails: int = 0
var _completed: Dictionary = {}

const SFX_SCRIPT: String = "res://scripts/combat/Sfx.gd"
const REACTION_TABLE: String = "res://scripts/combat/ReactionTable.gd"

## Keys the ~20 existing `Sfx.play(` call sites in scripts/ use today. The roster
## rewrite re-pointed several of these at better recordings rather than renaming
## them, precisely so no call site had to change; dropping one would make that
## call site push_warning instead of making a sound, which is the class of bug
## that hides in a playtest.
const CALLED_KEYS: Array[String] = [
	"cast", "spell_impact", "enemy_death", "hero_hurt", "melee_swing", "melee_hit",
	"blast", "ding", "footstep", "step", "land", "blink", "charge_up", "beam",
	"cannon", "zap", "ice", "earth", "holy", "nova", "crack",
]

## Stems ridden underneath other sounds by play(). Must exist, must be layer-free.
const STEM_KEYS: Array[String] = ["sub_boom", "rumble", "crack"]

## The point of the whole exercise: things that used to share one key and now do
## not. Each row is a family that must be several DISTINCT keys with DISTINCT
## streams — if a future edit collapses two of them back onto the same clip, the
## roster has quietly regressed to the state the maker complained about.
const DISTINCT_FAMILIES: Dictionary = {
	"beams": ["beam_arcane", "beam_frost", "beam_fire", "beam_shadow", "beam_storm"],
	"blizzard_beats": ["rime_tick", "ice_encase", "ice_shatter"],
	"ice": ["ice_wall", "ice_spine", "ice_shatter", "frost_field"],
	"ward": ["ward_raise", "ward_absorb", "ward_crack", "ward_break"],
	"tether": ["whip_lash", "whip_bite", "drain_pull", "tether_tear", "whip_miss"],
	"ults": [
		"ult_siege", "ult_bombardment", "ult_eruption", "ult_avalanche",
		"ult_shove", "ult_unmaking",
	],
	"clash": ["clash", "clash_heavy", "melee_hit", "block", "parry"],
}


func _init() -> void:
	_test_every_stream_loads()
	_test_roster_covers_call_sites()
	_test_profile_and_roster_agree()
	_test_stems_do_not_recurse()
	_test_weight_grading_is_monotonic()
	_test_layer_levels_sit_under_the_hit()
	_test_spell_families_are_distinct()
	_test_reaction_map_is_wired()
	_test_unmaking_is_absence()
	_test_play_every_key_detached()
	# Nodes added during a SceneTree script's _init are not yet "inside the tree",
	# so the check above exercises the detached fallbacks. Wait one idle frame and
	# the tree is live — the only way to cover what actually ships: real
	# AudioStreamPlayer playback and the create_timer branch behind the layers.
	await process_frame
	await _test_play_every_key_in_tree()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Sfx roster tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Sfx roster tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _sfx_const(name: String) -> Variant:
	var script: GDScript = load(SFX_SCRIPT)
	return script.get_script_constant_map().get(name)


# ---------------------------------------------------------------------------
# The roster
# ---------------------------------------------------------------------------

func _test_every_stream_loads() -> void:
	var streams: Dictionary = _sfx_const("STREAMS")
	_expect(streams != null and not streams.is_empty(), "STREAMS resolves")
	# The roster is the deliverable. If it ever shrinks back toward the old 23
	# keys, one key is serving several spells again.
	_expect(streams.size() >= 90,
		"roster is per-spell, not per-family (%d keys)" % streams.size())
	var total: int = 0
	for key: String in streams:
		var variants: Variant = streams.get(key, [])
		_expect(variants is Array and not (variants as Array).is_empty(),
			"'%s' is a non-empty variant array" % key)
		for v: Variant in (variants as Array):
			# preload() has already resolved these at parse time, so a null here
			# means an asset that imported as something that is not audio.
			_expect(v is AudioStream, "'%s' variant is an AudioStream" % key)
			total += 1
	_expect(total >= 180, "roster carries real variety (%d clips)" % total)
	_completes("every_stream_loads")


func _test_roster_covers_call_sites() -> void:
	var streams: Dictionary = _sfx_const("STREAMS")
	for key: String in CALLED_KEYS:
		_expect(streams.has(key), "STREAMS still has live call-site key '%s'" % key)
	# Footsteps need several variants or a run machine-guns one sample.
	var steps: Array = streams.get("step", [])
	_expect(steps.size() >= 3, "step has >= 3 variants (got %d)" % steps.size())
	_expect((streams.get("footstep", []) as Array).size() == steps.size(),
		"legacy 'footstep' alias points at the same step set")
	_completes("roster_covers_call_sites")


func _test_profile_and_roster_agree() -> void:
	var streams: Dictionary = _sfx_const("STREAMS")
	var profile: Dictionary = _sfx_const("PROFILE")
	for key: String in streams:
		_expect(profile.has(key), "PROFILE grades roster key '%s'" % key)
	# The reverse direction is the dangerous one: a profile for a key that does
	# not exist means play() warns and falls silent at that call site.
	for key: String in profile:
		_expect(streams.has(key), "PROFILE key '%s' exists in STREAMS" % key)
	# Every profile must name a real weight class, or the WEIGHT_* array lookups
	# in play() index out of bounds on the first call.
	var trims: Array = _sfx_const("WEIGHT_TRIM_DB")
	for key: String in profile:
		var w: int = int((profile[key] as Dictionary).get("w", -1))
		_expect(w >= 0 and w < trims.size(), "'%s' has a valid weight class" % key)
	_completes("profile_and_roster_agree")


func _test_stems_do_not_recurse() -> void:
	var profile: Dictionary = _sfx_const("PROFILE")
	var streams: Dictionary = _sfx_const("STREAMS")
	for key: String in STEM_KEYS:
		_expect(streams.has(key), "stem '%s' is in STREAMS" % key)
		var prof: Dictionary = profile.get(key, {})
		for layer: String in ["sub", "tail", "crack"]:
			_expect(float(prof.get(layer, 0.0)) == 0.0,
				"stem '%s' declares no '%s' layer (would recurse)" % [key, layer])
	_completes("stems_do_not_recurse")


# ---------------------------------------------------------------------------
# The grading
# ---------------------------------------------------------------------------

func _test_weight_grading_is_monotonic() -> void:
	var trims: Array = _sfx_const("WEIGHT_TRIM_DB")
	_expect(trims.size() == 4, "WEIGHT_TRIM_DB has one entry per class")
	for i in range(1, trims.size()):
		_expect(float(trims[i]) > float(trims[i - 1]),
			"weight class %d is louder than %d" % [i, i - 1])
	# The whole point is CONTRAST. The spread was widened when the bus compressor
	# was loosened; anything under 10 dB means that headroom went unused.
	var spread: float = float(trims[3]) - float(trims[0])
	_expect(spread >= 10.0, "ULT sits >= 10 dB above TICK (got %.1f)" % spread)
	# Only the top class ducks the music; ducking on every melee hit would pump.
	var ducks: Array = _sfx_const("WEIGHT_DUCK_DB")
	_expect(ducks.size() == 4, "WEIGHT_DUCK_DB has one entry per class")
	_expect(float(ducks[3]) > 0.0, "ULT ducks the music")
	for i in 3:
		_expect(float(ducks[i]) == 0.0, "weight class %d does not duck" % i)
	# Heavier events put their weight layer LOWER.
	var sub_pitch: Array = _sfx_const("WEIGHT_SUB_PITCH")
	_expect(sub_pitch.size() == 4, "WEIGHT_SUB_PITCH has one entry per class")
	for i in range(1, sub_pitch.size()):
		_expect(float(sub_pitch[i]) < float(sub_pitch[i - 1]),
			"weight class %d's sub is deeper than %d" % [i, i - 1])
	_completes("weight_grading_is_monotonic")


func _test_layer_levels_sit_under_the_hit() -> void:
	# Layers are felt, not heard: each must be below the sound it rides under, or
	# it stops being a layer and becomes a second sound effect.
	for name: String in ["SUB_DB", "TAIL_DB", "CRACK_DB"]:
		_expect(float(_sfx_const(name)) < 0.0, "%s is negative" % name)
	# The tail is an ANSWER to the hit — it must land after the sub, which is part
	# of the hit's own body.
	var sub_delay: float = float(_sfx_const("SUB_DELAY"))
	var tail_delay: float = float(_sfx_const("TAIL_DELAY"))
	_expect(sub_delay >= 0.0, "SUB_DELAY is non-negative")
	_expect(tail_delay > sub_delay, "the tail lands after the sub")
	_expect(tail_delay < 0.2, "the tail still reads as part of the same event")
	var profile: Dictionary = _sfx_const("PROFILE")
	# The heaviest keys must carry every layer — these are the sounds the maker
	# points at when they say it is not epic enough.
	for key: String in ["cannon", "earth_pillar", "holy_pillar", "rx_annihilate"]:
		var prof: Dictionary = profile.get(key, {})
		for layer: String in ["sub", "tail", "crack"]:
			_expect(float(prof.get(layer, 0.0)) > 0.0,
				"'%s' carries a '%s' layer" % [key, layer])
	# Pure swells with no attack must borrow a transient or the ear never
	# registers the frame they happened on.
	for key: String in ["holy", "holy_swell"]:
		_expect(float((profile.get(key, {}) as Dictionary).get("crack", 0.0)) > 0.0,
			"'%s' borrows a transient" % key)
	# Anything that fires REPEATEDLY must stay layer-free: feet at running cadence
	# and rime ticks as the freeze meter fills would otherwise stack into mush.
	for key: String in ["step", "footstep", "rime_tick"]:
		var prof: Dictionary = profile.get(key, {})
		for layer: String in ["sub", "tail", "crack"]:
			_expect(float(prof.get(layer, 0.0)) == 0.0,
				"'%s' repeats, so it has no '%s' layer" % [key, layer])
	_completes("layer_levels_sit_under_the_hit")


# ---------------------------------------------------------------------------
# The reason the roster grew
# ---------------------------------------------------------------------------

func _test_spell_families_are_distinct() -> void:
	var streams: Dictionary = _sfx_const("STREAMS")
	for family: String in DISTINCT_FAMILIES:
		var keys: Array = DISTINCT_FAMILIES[family]
		var seen: Dictionary = {}
		for key: String in keys:
			_expect(streams.has(key), "%s: '%s' exists" % [family, key])
			var variants: Array = streams.get(key, [])
			# Compare by resource PATH: two keys holding the same clip is exactly
			# the "one sound serving four spells" state this replaced.
			for v: Variant in variants:
				if v == null:
					continue
				var path: String = (v as Resource).resource_path
				if path.is_empty():
					continue
				_expect(not seen.has(path),
					"%s: '%s' does not reuse %s (already used by '%s')"
						% [family, key, path.get_file(), seen.get(path, "?")])
				seen[path] = key
	_completes("spell_families_are_distinct")


func _test_reaction_map_is_wired() -> void:
	var streams: Dictionary = _sfx_const("STREAMS")
	var map: Dictionary = _sfx_const("REACTION_SOUND")
	_expect(map != null and not map.is_empty(), "REACTION_SOUND resolves")
	for outcome: String in map:
		var key: String = String(map[outcome])
		# "" is the deliberate silence for a suppressed rule.
		if key.is_empty():
			continue
		_expect(streams.has(key),
			"REACTION_SOUND['%s'] names a real roster key ('%s')" % [outcome, key])
	# Coverage against the live reaction table, read from SOURCE rather than by
	# calling into it: ReactionTable is owned by another agent and mid-edit, and a
	# newly-added outcome is THEIR work in flight, not a fault in this roster. So
	# a gap PRINTS rather than fails — it is a request for a key, not a red build.
	var src: String = FileAccess.get_file_as_string(REACTION_TABLE)
	if not src.is_empty():
		var re := RegEx.create_from_string("_rule\\(\"([a-z_]+)\"")
		var missing: Array[String] = []
		for m: RegExMatch in re.search_all(src):
			var outcome: String = m.get_string(1)
			if not map.has(outcome) and not missing.has(outcome):
				missing.append(outcome)
		if not missing.is_empty():
			print("NOTE: ReactionTable outcomes with no sound yet: ", missing,
				" — ask the audio owner for keys rather than reusing a near-miss.")
	_completes("reaction_map_is_wired")


func _test_unmaking_is_absence() -> void:
	# The unmaking ult's audio identity is ABSENCE: the screen tears and the world
	# goes quiet. It is trimmed far below its own class and carries no layers, but
	# stays at ULT weight so it still DUCKS THE MUSIC — the ducking is the sound.
	# Spelled out as a test because every instinct on a future tuning pass will be
	# to "fix" it by making it louder.
	var profile: Dictionary = _sfx_const("PROFILE")
	var prof: Dictionary = profile.get("ult_unmaking", {})
	var trims: Array = _sfx_const("WEIGHT_TRIM_DB")
	var ducks: Array = _sfx_const("WEIGHT_DUCK_DB")
	var w: int = int(prof.get("w", -1))
	_expect(w == trims.size() - 1, "unmaking is ULT weight (so it ducks the music)")
	_expect(float(ducks[w]) > 0.0, "its weight class actually ducks")
	_expect(float(prof.get("trim", 0.0)) <= -8.0,
		"unmaking is trimmed well below its class (got %.1f)" % float(prof.get("trim", 0.0)))
	for layer: String in ["sub", "tail", "crack"]:
		_expect(float(prof.get(layer, 0.0)) == 0.0, "unmaking carries no '%s'" % layer)
	_completes("unmaking_is_absence")


# ---------------------------------------------------------------------------
# Driving the real thing
# ---------------------------------------------------------------------------

## The table tests above check the roster on paper; this one instantiates Sfx and
## pushes EVERY key through play(), layers included. It catches what a static
## table cannot: a broken stream reference, an unbuilt voice pool, a typo in the
## layer dispatch, or a key that warns instead of sounding.
##
## A --script harness has no active scene, so actual playback is skipped (see
## _emit_now) — but the voice is fully ROUTED first, so asserting that every pool
## slot ended up holding a stream still proves the whole path ran.
func _test_play_every_key_detached() -> void:
	var sfx: Node = (load(SFX_SCRIPT) as GDScript).new()
	sfx.name = "Sfx"
	root.add_child(sfx)
	# The pool has to hold several fully-layered events at once: one ULT is four
	# voices, and a reaction can fire while two beams are still sounding.
	var pool_size: int = int(_sfx_const("POOL_SIZE"))
	_expect(pool_size >= 4 * 4, "pool holds several layered events at once")
	var streams: Dictionary = _sfx_const("STREAMS")
	var rounds: int = 1 + pool_size / maxi(1, streams.size())
	for r in rounds:
		for key: String in streams:
			sfx.play(key)
	var voices: Array = sfx.get_children()
	_expect(voices.size() == pool_size, "pool built %d voices" % pool_size)
	var routed: int = 0
	for child in voices:
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream != null:
			routed += 1
	_expect(routed == pool_size,
		"every voice got a stream routed to it (%d/%d)" % [routed, pool_size])
	# reaction_sound() is the API the reaction work calls; exercise it here rather
	# than only reading its table, so a signature change surfaces.
	var map: Dictionary = _sfx_const("REACTION_SOUND")
	for outcome: String in map:
		var key: String = String(sfx.reaction_sound(outcome))
		_expect(key == String(map[outcome]), "reaction_sound('%s') agrees with the table" % outcome)
		if not key.is_empty():
			sfx.play(key)
	_expect(sfx.reaction_sound("no_such_outcome_ever") == "",
		"an unknown outcome resolves to silence, not to a near-miss key")
	sfx.free()
	_completes("play_every_key_detached")


## The real path, one idle frame in: the tree is live, so voices genuinely start
## and the delayed sub/tail layers go through create_timer instead of the
## detached fallback. Headless has no audio DEVICE (Godot loads the dummy driver)
## — this asserts that is a silent no-op rather than an error, which is the
## contract every suite and boot check in the project depends on.
func _test_play_every_key_in_tree() -> void:
	var sfx: Node = (load(SFX_SCRIPT) as GDScript).new()
	sfx.name = "Sfx"
	root.add_child(sfx)
	_expect(sfx.is_inside_tree(), "Sfx is live in the tree for this check")
	# The heaviest keys in the game: main + crack + sub + tail, three of the four
	# scheduled through the delay path.
	for key: String in ["cannon", "earth_pillar", "rx_annihilate", "ice_shatter"]:
		sfx.play(key)
	sfx.play("step", -6.0, 0.16)
	var playing: int = 0
	for child in sfx.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			playing += 1
	_expect(playing >= 2, "voices actually started (got %d)" % playing)
	# Let the deferred layers land. Two frames plus the longest layer delay.
	await create_timer(0.15, true, false, true).timeout
	var after: int = 0
	for child in sfx.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream != null:
			after += 1
	_expect(after > playing, "the delayed sub/tail layers landed too")
	sfx.free()
	_completes("play_every_key_in_tree")
