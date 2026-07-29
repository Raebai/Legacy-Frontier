# Run: godot --headless --path godot-project --script tools/slice_test_sfx_mix.gd
#
# Covers the layered/graded mix added to Sfx.gd and the gait-driven footsteps in
# CharacterRig.gd. Audio itself cannot be verified headless (no device, and
# "epic" is not a testable property) — what IS testable is the plumbing that has
# to hold for the mix to work at all:
#   * every new asset imports as an AudioStreamWAV;
#   * every roster key has a mix profile, and no profile names a key that does
#     not exist (a typo there would push_warning on every cast in the game);
#   * the layer stems carry no layers of their own, so play() cannot recurse;
#   * the weight grading is monotonic — a TICK really is quieter than an ULT,
#     which is the entire "flat dynamics" fix;
#   * footfalls come off the run cycle at the stride rate, fire once per plant,
#     and stay silent when idle / frozen / ragdolling / airborne.
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
	"new_assets_load",
	"roster_covers_call_sites",
	"profiles_match_roster",
	"stems_do_not_recurse",
	"weight_grading_is_monotonic",
	"layer_levels_sit_under_the_hit",
	"footstep_fires_on_the_gait",
	"footstep_silent_when_not_running",
	"footstep_silent_when_loose_or_frozen",
	"footstep_opt_in",
	"play_runs_without_warnings",
	"play_in_tree",
]

var _fails: int = 0
var _completed: Dictionary = {}

const RIG_SCRIPT: String = "res://scripts/combat/CharacterRig.gd"
const SFX_SCRIPT: String = "res://scripts/combat/Sfx.gd"

## The assets generate_epic_sfx.py adds. Paths, not preloads, so a missing file
## fails as a readable test rather than a parse error.
const NEW_ASSETS: Array[String] = [
	"res://assets/audio/sfx/sub_boom_1.wav",
	"res://assets/audio/sfx/sub_boom_2.wav",
	"res://assets/audio/sfx/rumble_1.wav",
	"res://assets/audio/sfx/rumble_2.wav",
	"res://assets/audio/sfx/crack_1.wav",
	"res://assets/audio/sfx/crack_2.wav",
	"res://assets/audio/sfx/step_1.wav",
	"res://assets/audio/sfx/step_2.wav",
	"res://assets/audio/sfx/step_3.wav",
	"res://assets/audio/sfx/step_4.wav",
	"res://assets/audio/sfx/land_1.wav",
	"res://assets/audio/sfx/land_2.wav",
]

## Keys every call site in scripts/ uses today (grep 'Sfx.play('). If a refactor
## ever drops one of these from STREAMS the game would push_warning instead of
## making a sound, which is exactly the class of bug that hides in a playtest.
const CALLED_KEYS: Array[String] = [
	"cast", "spell_impact", "enemy_death", "hero_hurt", "melee_swing", "melee_hit",
	"blast", "ding", "footstep", "step", "land", "blink", "charge_up", "beam",
	"cannon", "zap", "ice", "earth", "holy", "nova",
]

## Stems ridden underneath other sounds by play(). Must exist, must be layer-free.
const STEM_KEYS: Array[String] = ["sub_boom", "rumble", "crack"]


func _init() -> void:
	_test_new_assets_load()
	_test_roster_covers_call_sites()
	_test_profiles_match_roster()
	_test_stems_do_not_recurse()
	_test_weight_grading_is_monotonic()
	_test_layer_levels_sit_under_the_hit()
	_test_footstep_fires_on_the_gait()
	_test_footstep_silent_when_not_running()
	_test_footstep_silent_when_loose_or_frozen()
	_test_footstep_opt_in()
	_test_play_runs_without_warnings()
	# Nodes added during a SceneTree script's _init are not yet "inside the tree",
	# so the checks above exercise the detached fallbacks. Wait one idle frame and
	# the tree is live — that is the only way to cover what actually ships: real
	# AudioStreamPlayer playback and the create_timer branch that schedules the
	# sub/tail layers.
	await process_frame
	await _test_play_in_tree()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Sfx mix tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Sfx mix tests: all PASS")
		quit(0)


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


func _sfx_const(name: String) -> Variant:
	var script: GDScript = load(SFX_SCRIPT)
	return script.get_script_constant_map().get(name)


# ---------------------------------------------------------------------------
# Assets + roster
# ---------------------------------------------------------------------------

func _test_new_assets_load() -> void:
	for path: String in NEW_ASSETS:
		var stream: Resource = load(path)
		_expect(stream != null, "%s loads" % path)
		_expect(stream is AudioStreamWAV, "%s is AudioStreamWAV" % path)
	_completes("new_assets_load")


func _test_roster_covers_call_sites() -> void:
	var streams: Dictionary = _sfx_const("STREAMS")
	_expect(streams != null and not streams.is_empty(), "STREAMS resolves")
	for key: String in CALLED_KEYS:
		_expect(streams.has(key), "STREAMS has called key '%s'" % key)
		var variants: Variant = streams.get(key, [])
		_expect(
			variants is Array and not (variants as Array).is_empty(),
			"STREAMS['%s'] is a non-empty variant array" % key
		)
	# The steps must have several variants or a run machine-guns one sample —
	# the exact complaint the old single 0.5 s walk clip produced.
	var steps: Array = streams.get("step", [])
	_expect(steps.size() >= 3, "step has >= 3 variants (got %d)" % steps.size())
	_expect(
		(streams.get("footstep", []) as Array).size() == steps.size(),
		"legacy 'footstep' alias points at the same step set"
	)
	_completes("roster_covers_call_sites")


func _test_profiles_match_roster() -> void:
	var streams: Dictionary = _sfx_const("STREAMS")
	var profile: Dictionary = _sfx_const("PROFILE")
	for key: String in streams:
		_expect(profile.has(key), "PROFILE grades roster key '%s'" % key)
	# The reverse direction is the dangerous one: a profile for a key that does
	# not exist means play() warns and falls silent at that call site.
	for key: String in profile:
		_expect(streams.has(key), "PROFILE key '%s' exists in STREAMS" % key)
	_completes("profiles_match_roster")


func _test_stems_do_not_recurse() -> void:
	var profile: Dictionary = _sfx_const("PROFILE")
	var streams: Dictionary = _sfx_const("STREAMS")
	for key: String in STEM_KEYS:
		_expect(streams.has(key), "stem '%s' is in STREAMS" % key)
		var prof: Dictionary = profile.get(key, {})
		for layer: String in ["sub", "tail", "crack"]:
			_expect(
				float(prof.get(layer, 0.0)) == 0.0,
				"stem '%s' declares no '%s' layer (would recurse)" % [key, layer]
			)
	_completes("stems_do_not_recurse")


# ---------------------------------------------------------------------------
# The grading — the "flat dynamics" fix
# ---------------------------------------------------------------------------

func _test_weight_grading_is_monotonic() -> void:
	var trims: Array = _sfx_const("WEIGHT_TRIM_DB")
	_expect(trims.size() == 4, "WEIGHT_TRIM_DB has one entry per class")
	for i in range(1, trims.size()):
		_expect(
			float(trims[i]) > float(trims[i - 1]),
			"weight class %d is louder than %d" % [i, i - 1]
		)
	# The whole point is CONTRAST: an ult has to be clearly above a footstep.
	_expect(
		float(trims[3]) - float(trims[0]) >= 6.0,
		"ULT sits >= 6 dB above TICK (got %.1f)" % (float(trims[3]) - float(trims[0]))
	)
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
		_expect(
			float(sub_pitch[i]) < float(sub_pitch[i - 1]),
			"weight class %d's sub is deeper than %d" % [i, i - 1]
		)
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
	# The heaviest key should carry every layer — this is the sound the maker
	# points at when they say it is not epic enough.
	var profile: Dictionary = _sfx_const("PROFILE")
	var cannon: Dictionary = profile.get("cannon", {})
	for layer: String in ["sub", "tail", "crack"]:
		_expect(float(cannon.get(layer, 0.0)) > 0.0, "cannon carries a '%s' layer" % layer)
	# A pure swell with no attack must borrow one, or the ear never registers the
	# frame it happened on.
	_expect(
		float((profile.get("holy", {}) as Dictionary).get("crack", 0.0)) > 0.0,
		"holy borrows a transient"
	)
	# Footsteps must stay layer-free — a sub under every step would be absurd.
	for key: String in ["step", "footstep"]:
		var prof: Dictionary = profile.get(key, {})
		_expect(float(prof.get("sub", 0.0)) == 0.0, "'%s' has no sub layer" % key)
		_expect(float(prof.get("tail", 0.0)) == 0.0, "'%s' has no tail layer" % key)
	_completes("layer_levels_sit_under_the_hit")


# ---------------------------------------------------------------------------
# Gait-driven footsteps (CharacterRig)
# ---------------------------------------------------------------------------

## Drive a rig for `seconds` at a fixed step, TRANSLATING it at `vx` px/s, and count
## `foot_planted` emissions. advance() is the rig's headless-driveable per-frame entry.
##
## The translation is load-bearing now. Footsteps used to be derived from an animation
## phase, so a rig standing still on the spot still ticked; the gait is WORLD-LOCKED
## since the SpikeFigure port, so a foot only plants when the body has actually
## travelled far enough to need a new one. A stationary rig correctly makes no sound.
func _count_plants(rig: Node2D, seconds: float, dt: float = 1.0 / 60.0, vx: float = 180.0) -> int:
	var counter := _PlantCounter.new()
	rig.foot_planted.connect(counter.on_plant)
	rig.set_grounded(true)
	var steps: int = int(seconds / dt)
	for i in steps:
		rig.position.x += vx * dt
		rig.advance(dt)
	rig.foot_planted.disconnect(counter.on_plant)
	return counter.count


class _PlantCounter:
	extends RefCounted
	var count: int = 0

	func on_plant() -> void:
		count += 1


func _make_rig() -> Node2D:
	var rig: Node2D = (load(RIG_SCRIPT) as GDScript).new()
	root.add_child(rig)
	return rig


func _test_footstep_fires_on_the_gait() -> void:
	var rig: Node2D = _make_rig()
	rig.play(rig.State.RUN)
	# Steps are now DISTANCE-driven, not cadence-driven: one plant per STEP_LENGTH of
	# travel (leg reach * STEP_LENGTH_FACTOR), alternating feet. Asserting the count
	# against the distance covered is the honest test of a world-locked gait, and it
	# is what stops the sound drifting away from the visible footfall.
	var seconds: float = 2.0
	var vx: float = 180.0
	var consts: Dictionary = load(RIG_SCRIPT).get_script_constant_map()
	var leg: float = float(rig.height) * 0.4
	var step_len: float = leg * float(consts.get("STEP_LENGTH_FACTOR"))
	var expected: int = int((vx * seconds) / step_len)
	var got: int = _count_plants(rig, seconds, 1.0 / 60.0, vx)
	# Generous band: the swing takes real time, so the stride lags the ideal spacing.
	_expect(
		got > expected / 3 and got <= expected + 2,
		"running %.1fs at %.0f px/s plants feet in proportion to distance (got %d, ideal %d)"
				% [seconds, vx, got, expected]
	)
	_expect(got > 0, "a run plants feet at all")
	# And the flip side of the same contract: standing still makes no footsteps.
	var idle_rig: Node2D = _make_rig()
	idle_rig.play(idle_rig.State.IDLE)
	_expect(_count_plants(idle_rig, 2.0, 1.0 / 60.0, 0.0) == 0, "a standing figure is silent")
	idle_rig.free()
	rig.free()
	_completes("footstep_fires_on_the_gait")


func _test_footstep_silent_when_not_running() -> void:
	var idle: Node2D = _make_rig()
	idle.play(idle.State.IDLE)
	# vx=0 explicitly: the gait is world-locked, so "not running" now means "not
	# TRAVELLING". A figure sliding across the floor at speed plants feet whatever
	# animation state it is nominally in, which is the correct read.
	_expect(_count_plants(idle, 2.0, 1.0 / 60.0, 0.0) == 0, "standing still plants no feet")
	idle.free()
	# Airborne: AIR is a looseness regime with no run cycle — no steps mid-jump.
	var air: Node2D = _make_rig()
	air.play(air.State.AIR)
	air.set_air_phase(false, false)
	_expect(_count_plants(air, 2.0) == 0, "airborne plants no feet")
	air.free()
	_completes("footstep_silent_when_not_running")


func _test_footstep_silent_when_loose_or_frozen() -> void:
	# Ragdolling: flop() drives _limp up; once loose there are no feet under you.
	var limp: Node2D = _make_rig()
	limp.play(limp.State.RUN)
	limp.set_limp(1.0)
	limp.advance(1.0)  # let _limp ease all the way to the target
	_expect(_count_plants(limp, 2.0) == 0, "a ragdolling figure plants no feet")
	limp.free()
	# Hard-CC freeze holds the locomotion phase, so the stride stops dead.
	var frozen: Node2D = _make_rig()
	frozen.play(frozen.State.RUN)
	frozen.set_frozen(true)
	_expect(_count_plants(frozen, 2.0) == 0, "a frozen figure plants no feet")
	frozen.free()
	_completes("footstep_silent_when_loose_or_frozen")


## Drive the real thing. The table tests above check the mix on paper; this one
## instantiates Sfx and pushes every key in the roster through play(), including
## all the automatic layers. It catches what a static table cannot: a broken
## stream reference, an unbuilt voice pool, a typo in the layer dispatch, or a
## key that warns instead of sounding.
##
## A --script harness has no active scene, so actual playback is skipped (see
## _emit_now) — but the voice is fully ROUTED first, so asserting that every pool
## slot ended up holding a stream still proves the whole path ran.
func _test_play_runs_without_warnings() -> void:
	var sfx: Node = (load(SFX_SCRIPT) as GDScript).new()
	sfx.name = "Sfx"
	root.add_child(sfx)
	# The pool has to be big enough that one ULT's four voices (main + crack +
	# sub + tail) plus the surrounding fight don't cut each other off.
	var pool_size: int = int(_sfx_const("POOL_SIZE"))
	_expect(pool_size >= 4 * 3, "pool holds several layered events at once")
	var streams: Dictionary = _sfx_const("STREAMS")
	# Enough events to wrap the pool at least once, so every slot is exercised.
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
	_expect(
		routed == pool_size,
		"every voice got a stream routed to it (%d/%d)" % [routed, pool_size]
	)
	sfx.free()
	_completes("play_runs_without_warnings")


## The real path, one idle frame in: the tree is live, so voices genuinely start
## and the delayed sub/tail layers go through create_timer instead of the
## detached fallback. Headless has no audio DEVICE (Godot loads the dummy driver)
## — this asserts that is a silent no-op rather than an error, which is the
## contract every suite and boot check in the project depends on.
func _test_play_in_tree() -> void:
	var sfx: Node = (load(SFX_SCRIPT) as GDScript).new()
	sfx.name = "Sfx"
	root.add_child(sfx)
	_expect(sfx.is_inside_tree(), "Sfx is live in the tree for this check")
	# The heaviest key in the game: main + crack + sub + tail, three of the four
	# scheduled through the delay path.
	sfx.play("cannon")
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
	_completes("play_in_tree")


func _test_footstep_opt_in() -> void:
	var rig: Node2D = _make_rig()
	# Enemies share this rig; a room of them all ticking would be a cacophony, so
	# the SOUND is opt-in even though the signal always fires.
	_expect(rig.step_sfx == false, "step_sfx is off by default")
	rig.play(rig.State.RUN)
	# With no Sfx autoload registered (--script context) the sound path must be a
	# no-op rather than a crash — the same /root guard the spike rig uses.
	rig.step_sfx = true
	_expect(_count_plants(rig, 1.0) > 0, "opted-in rig still plants feet")
	rig.free()
	_completes("footstep_opt_in")
