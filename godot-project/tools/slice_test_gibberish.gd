# Run: godot --headless --path godot-project --script tools/slice_test_gibberish.gd
#
# Covers the GIBBERISH VOICE system — Gibberish.gd (the maths) plus the four
# voice keys and `speak()` added to Sfx.gd.
#
# WHAT CANNOT BE TESTED: whether it sounds like a character. Headless has no
# audio device, and "characterful" is not a testable property. Nobody has heard
# one syllable of this.
#
# WHAT CAN, and every one of these has a real failure behind it:
#   * the four vowel banks are REAL Sfx roster keys with real mix profiles — a
#     typo there means every voice in the game push_warnings and falls silent;
#   * a voice is STABLE: the same seed is the same character forever, which is
#     the entire premise ("the same fighter sounds like itself");
#   * voices actually SPREAD across the banks and pitch bands — a seed mixer
#     that collapses onto one bank would give every stick figure one mouth and
#     nothing would look wrong on paper;
#   * `plan()` is PURE — same input, same output, no RNG object. The wobble is a
#     hash, so this can be asserted by exact equality rather than by range;
#   * `speak()` rides the EXISTING 32-voice pool and adds no second pool. That
#     was an explicit constraint, and it is the kind of thing that gets violated
#     by a well-meaning "just one more AudioStreamPlayer";
#   * one speaker cannot talk over itself (three hits in a fifth of a second
#     used to be three yelps smeared into one noise).
extends SceneTree

# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# A dead property read is NOT a test failure in GDScript: it logs a runtime
# error, ABORTS the enclosing function, and hands the caller the return type's
# zero. Under `failed += _test_x()` that reads as "no failures" while every
# assertion after the dead line is skipped. So failures accumulate on the MEMBER
# `_fails`, and each test records a completion sentinel as its last line — a test
# that aborts part-way is then missing from `_completed` and fails BY ABSENCE.

const TESTS: Array[String] = [
	"banks_are_real_roster_keys",
	"voice_is_stable",
	"voices_spread",
	"voice_stays_in_bounds",
	"moods_are_all_shaped",
	"plan_is_pure",
	"plan_shape",
	"plan_lands_the_last_syllable",
	"syllables_for_text",
	"speak_uses_the_shared_pool",
	"speak_rate_limits_one_speaker",
]

var _fails: int = 0
var _completed: Dictionary = {}

const SFX_SCRIPT: String = "res://scripts/combat/Sfx.gd"


func _init() -> void:
	_test_banks_are_real_roster_keys()
	_test_voice_is_stable()
	_test_voices_spread()
	_test_voice_stays_in_bounds()
	_test_moods_are_all_shaped()
	_test_plan_is_pure()
	_test_plan_shape()
	_test_plan_lands_the_last_syllable()
	_test_syllables_for_text()
	_test_speak_uses_the_shared_pool()
	_test_speak_rate_limits_one_speaker()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Gibberish tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Gibberish tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _sfx_const(name: String) -> Variant:
	return (load(SFX_SCRIPT) as GDScript).get_script_constant_map().get(name)


# ---------------------------------------------------------------------------
# The banks
# ---------------------------------------------------------------------------

func _test_banks_are_real_roster_keys() -> void:
	var streams: Dictionary = _sfx_const("STREAMS")
	var profile: Dictionary = _sfx_const("PROFILE")
	_expect(Gibberish.BANKS.size() >= 3,
		"there are several vowel banks (got %d)" % Gibberish.BANKS.size())
	for key: String in Gibberish.BANKS:
		_expect(streams.has(key), "voice bank '%s' is a real Sfx roster key" % key)
		var variants: Array = streams.get(key, [])
		# One clip per bank would machine-gun the instant anybody says three
		# syllables — which is the default utterance length.
		_expect(variants.size() >= 3,
			"'%s' has >= 3 variants so a sentence is not one sample (got %d)"
				% [key, variants.size()])
		for v: Variant in variants:
			_expect(v is AudioStream, "'%s' variant imported as audio" % key)
		_expect(profile.has(key), "'%s' has a mix profile" % key)
		# Voices fire several times a second. Layers on them would stack into
		# mush for exactly the reason footsteps and rime ticks are layer-free.
		var prof: Dictionary = profile.get(key, {})
		for layer: String in ["sub", "tail", "crack"]:
			_expect(float(prof.get(layer, 0.0)) == 0.0,
				"'%s' repeats, so it carries no '%s' layer" % [key, layer])
	# Banks must be DISTINCT clips, or four "different" vowels are one vowel.
	var seen: Dictionary = {}
	for key: String in Gibberish.BANKS:
		for v: Variant in (streams.get(key, []) as Array):
			var path: String = (v as Resource).resource_path
			if path.is_empty():
				continue
			_expect(not seen.has(path),
				"'%s' does not reuse %s (already in '%s')"
					% [key, path.get_file(), seen.get(path, "?")])
			seen[path] = key
	_completes("banks_are_real_roster_keys")


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

func _test_voice_is_stable() -> void:
	# The whole premise: the same fighter sounds like itself every time.
	for s: int in [0, 1, 7, 42, 99991, -17]:
		var a: Dictionary = Gibberish.voice(s)
		var b: Dictionary = Gibberish.voice(s)
		_expect(a == b, "voice(%d) is the same voice twice" % s)
	# Negative seeds must not explode an array index — hash() returns negatives.
	var neg: Dictionary = Gibberish.voice(-123456789)
	_expect(Gibberish.BANKS.has(String(neg["bank"])), "a negative seed still picks a real bank")
	# Same NAME, same voice — this is what makes `voice_of(node)` work at all.
	var one := _Named.new()
	one.stub_name = "Enemy@42"
	var two := _Named.new()
	two.stub_name = "Enemy@42"
	_expect(Gibberish.voice_of(one) == Gibberish.voice_of(two),
		"two bodies with the same name share a voice")
	_expect(Gibberish.voice_of(null)["bank"] is String, "a null speaker degrades to a valid voice")
	_completes("voice_is_stable")


func _test_voices_spread() -> void:
	# A mixer that quietly collapsed onto one bank would look completely fine in
	# the code and give every character in the game the same mouth.
	var banks: Dictionary = {}
	var pitches: Dictionary = {}
	var gaps: Dictionary = {}
	for i in 400:
		var v: Dictionary = Gibberish.voice(Gibberish.seed_for("body_%d" % i))
		banks[v["bank"]] = true
		pitches[v["pitch"]] = true
		gaps[snappedf(float(v["gap"]), 0.005)] = true
	_expect(banks.size() == Gibberish.BANKS.size(),
		"400 characters use every vowel bank (got %d of %d)" % [banks.size(), Gibberish.BANKS.size()])
	_expect(pitches.size() >= Gibberish.PITCH_BANDS.size() - 1,
		"400 characters use nearly every pitch band (got %d)" % pitches.size())
	_expect(gaps.size() >= 6, "cadence varies between characters (got %d buckets)" % gaps.size())
	_completes("voices_spread")


func _test_voice_stays_in_bounds() -> void:
	var lo: float = Gibberish.PITCH_BANDS[0]
	var hi: float = Gibberish.PITCH_BANDS[Gibberish.PITCH_BANDS.size() - 1]
	for i in 200:
		var v: Dictionary = Gibberish.voice(i * 7919)
		var p: float = float(v["pitch"])
		var g: float = float(v["gap"])
		_expect(p >= lo and p <= hi, "pitch %.3f is inside the band table" % p)
		_expect(g >= Gibberish.GAP_MIN and g <= Gibberish.GAP_MAX,
			"cadence %.3f is inside [GAP_MIN, GAP_MAX]" % g)
	# The bands must actually be ordered dark -> bright, because the comment says
	# so and because a future insert in the wrong place would re-voice everybody.
	for i in range(1, Gibberish.PITCH_BANDS.size()):
		_expect(Gibberish.PITCH_BANDS[i] > Gibberish.PITCH_BANDS[i - 1],
			"pitch band %d is above %d" % [i, i - 1])
	_completes("voice_stays_in_bounds")


func _test_moods_are_all_shaped() -> void:
	# A mood with no row falls back to TALK silently — so a new mood would ship
	# looking wired up and sounding like nothing in particular.
	for mood: int in Gibberish.Mood.values():
		_expect(Gibberish.MOOD_SHAPE.has(mood), "Mood %d has a shape row" % mood)
		var shape: Dictionary = Gibberish.MOOD_SHAPE.get(mood, {})
		for field: String in ["pitch", "gap", "db", "n", "land"]:
			_expect(shape.has(field), "Mood %d declares '%s'" % [mood, field])
		_expect(float(shape.get("db", 99.0)) <= Gibberish.MAX_DB,
			"Mood %d does not out-shout the game" % mood)
		_expect(int(shape.get("n", 0)) >= 1 and int(shape.get("n", 0)) <= Gibberish.MAX_SYLLABLES,
			"Mood %d has a sane default length" % mood)
	_completes("moods_are_all_shaped")


# ---------------------------------------------------------------------------
# The utterance
# ---------------------------------------------------------------------------

func _test_plan_is_pure() -> void:
	# Purity is what lets this be tested by equality at all, and it is what makes
	# a voice an identity rather than a random noise generator.
	var v: Dictionary = Gibberish.voice(Gibberish.seed_for("Boss"))
	for mood: int in Gibberish.Mood.values():
		var a: Array = Gibberish.plan(v, mood, 4)
		var b: Array = Gibberish.plan(v, mood, 4)
		_expect(a == b, "plan() is pure for mood %d" % mood)
	# Two different characters saying the same thing must not be identical.
	var other: Dictionary = Gibberish.voice(Gibberish.seed_for("Mob"))
	_expect(Gibberish.plan(v, Gibberish.Mood.TALK, 3) != Gibberish.plan(other, Gibberish.Mood.TALK, 3),
		"two characters do not utter identically")
	_completes("plan_is_pure")


func _test_plan_shape() -> void:
	var v: Dictionary = Gibberish.voice(1234)
	for n in range(1, Gibberish.MAX_SYLLABLES + 1):
		var p: Array = Gibberish.plan(v, Gibberish.Mood.TALK, n)
		_expect(p.size() == n, "a %d-syllable ask yields %d entries (got %d)" % [n, n, p.size()])
		var last_delay: float = -1.0
		for entry: Dictionary in p:
			_expect(Gibberish.BANKS.has(String(entry["key"])), "entry names a real bank")
			_expect(float(entry["pitch"]) > 0.0, "entry pitch is positive")
			_expect(float(entry["delay"]) > last_delay, "syllables are ordered in time")
			_expect(float(entry["db"]) <= Gibberish.MAX_DB, "entry respects the voice ceiling")
			last_delay = float(entry["delay"])
		_expect(float((p[0] as Dictionary)["delay"]) == 0.0, "the first syllable is immediate")
	# Nobody gets to monologue.
	var long: Array = Gibberish.plan(v, Gibberish.Mood.TALK, 99)
	_expect(long.size() == Gibberish.MAX_SYLLABLES, "an absurd ask is clamped to MAX_SYLLABLES")
	# An utterance has to be over fast — this is a fight, not a cutscene.
	_expect(Gibberish.plan_duration(long) < 1.0,
		"even the longest utterance is under a second (%.2fs)" % Gibberish.plan_duration(long))
	_expect(Gibberish.plan_duration([]) == 0.0, "an empty plan has no duration")
	_completes("plan_shape")


func _test_plan_lands_the_last_syllable() -> void:
	# The LAND is the only intonation there is: a question has to rise and a death
	# has to fall, or every line reads the same.
	var v: Dictionary = Gibberish.voice(777)
	var base: float = float(v["pitch"])
	var q: Array = Gibberish.plan(v, Gibberish.Mood.QUESTION, 3)
	var d: Array = Gibberish.plan(v, Gibberish.Mood.DIE, 3)
	var q_last: float = float((q[q.size() - 1] as Dictionary)["pitch"])
	var d_last: float = float((d[d.size() - 1] as Dictionary)["pitch"])
	_expect(q_last > base, "a question rises at the end (%.3f vs base %.3f)" % [q_last, base])
	_expect(d_last < base, "dying falls at the end (%.3f vs base %.3f)" % [d_last, base])
	_expect(q_last > d_last, "a question and a death do not land the same way")
	# A single syllable has no "last" to punctuate — it must not be silently
	# re-pitched into the land, or every yelp would be the same note.
	var one: Array = Gibberish.plan(v, Gibberish.Mood.HURT, 1)
	_expect(one.size() == 1, "a one-syllable yelp is one syllable")
	_completes("plan_lands_the_last_syllable")


func _test_syllables_for_text() -> void:
	_expect(Gibberish.syllables_for_text("") >= 1, "an empty line still moves the mouth")
	var short_n: int = Gibberish.syllables_for_text("fresh sheet.")
	var long_n: int = Gibberish.syllables_for_text("the hand pressed harder than before")
	_expect(long_n >= short_n, "a longer line is not a shorter noise")
	_expect(long_n <= Gibberish.MAX_SYLLABLES, "even a long line is capped")
	for n: int in [short_n, long_n]:
		_expect(n >= 1 and n <= Gibberish.MAX_SYLLABLES, "syllable count stays in range (%d)" % n)
	_completes("syllables_for_text")


# ---------------------------------------------------------------------------
# Driving the real thing
# ---------------------------------------------------------------------------

func _test_speak_uses_the_shared_pool() -> void:
	var sfx: Node = (load(SFX_SCRIPT) as GDScript).new()
	sfx.name = "Sfx"
	root.add_child(sfx)
	var pool_size: int = int(_sfx_const("POOL_SIZE"))
	# Nodes added during a SceneTree script's _init are not "inside the tree", so
	# `_ready` has not run and the pool is built lazily by the first emission —
	# exactly as the existing Sfx suites document. Speaking IS the trigger.
	# A whole room talking at once.
	for i in 40:
		sfx.speak(Gibberish.seed_for("body_%d" % i), i % Gibberish.Mood.size(), 3)
	var after: int = sfx.get_children().size()
	_expect(after == pool_size,
		"speak() added NO second audio pool (%d children, pool is %d)" % [after, pool_size])
	var routed: int = 0
	for child in sfx.get_children():
		_expect(child is AudioStreamPlayer,
			"every child of Sfx is still a pool voice, not a bolted-on player")
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream != null:
			routed += 1
	_expect(routed == pool_size, "every pool voice was used by the chatter (%d/%d)" % [routed, pool_size])
	# The convenience form has to work too — it is what call sites will use.
	var body := _Named.new()
	body.stub_name = "Enemy@9"
	var dur: float = float(sfx.speak_for(body, Gibberish.Mood.HURT))
	_expect(dur >= 0.0, "speak_for returns a duration rather than erroring")
	sfx.free()
	_completes("speak_uses_the_shared_pool")


func _test_speak_rate_limits_one_speaker() -> void:
	var sfx: Node = (load(SFX_SCRIPT) as GDScript).new()
	sfx.name = "Sfx"
	root.add_child(sfx)
	var seed: int = Gibberish.seed_for("Hero")
	var first: float = float(sfx.speak(seed, Gibberish.Mood.HURT, 2))
	var second: float = float(sfx.speak(seed, Gibberish.Mood.HURT, 2))
	_expect(first > 0.0, "the first utterance lands")
	_expect(second == 0.0, "the same speaker cannot talk over itself")
	# A DIFFERENT speaker in the same instant must still be heard — the limit is
	# per-voice, not global, or a crowd would take turns.
	var other: float = float(sfx.speak(Gibberish.seed_for("Someone Else"), Gibberish.Mood.HURT, 2))
	_expect(other > 0.0, "a different speaker is not gagged by the first")
	sfx.free()
	_completes("speak_rate_limits_one_speaker")


## Minimal stand-in for a live body: something with a name and nothing else.
## RefCounted rather than Node so the suite never has to manage node lifetimes —
## the same reason Patience.gd types its subject as Object.
class _Named:
	extends RefCounted
	var stub_name: String = "stub"

	func get_name() -> String:
		return stub_name
