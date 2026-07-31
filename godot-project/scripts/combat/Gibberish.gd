class_name Gibberish
extends RefCounted
## THE VOICE OF EVERY DRAWN THING — Animal-Crossing-style gibberish.
##
## Spec: "Gibberish voices, Animal Crossing style, procedurally pitched. No
## recording, no localisation, more characterful on a stick figure than real VO."
##
## ── WHAT THIS FILE IS, AND WHAT IT IS NOT ───────────────────────────────────
## This is PURE MATH. It owns the two things that make gibberish read as a
## PERSON rather than as a beep sequence:
##
##   1. IDENTITY — a given fighter must sound like ITSELF every time it opens
##      its mouth. `voice(seed)` is a total function from any stable integer to
##      a (vowel bank, base pitch, cadence, jitter) tuple, so the same stick
##      figure has the same voice for the whole climb without anything being
##      stored anywhere.
##   2. INTONATION — a flat run of identical blips is a fax machine. `plan()`
##      walks the pitch across the utterance and lands the final syllable, so a
##      line falls like a statement and a question rises.
##
## It plays NOTHING. `Sfx.speak()` is the only thing that touches audio, and it
## rides the EXISTING 32-voice round-robin pool — there is deliberately no second
## pool anywhere in this feature.
##
## Everything here is `static` and pure: same arguments, same output, no engine
## state, no autoload reach-outs, no RNG object. That is what makes the whole
## voice system headlessly testable (tools/slice_test_gibberish.gd) in a project
## where audio itself cannot be verified without ears.
##
## ── THE LORE, WHICH IS WHY THE BANKS ARE WHAT THEY ARE ──────────────────────
## The tower is DRAWN, and so are you. A drawing does not have a larynx. So the
## voice is deliberately CHALKY — four vowels, no consonants, no words. What a
## character IS shows up as pitch band and cadence: the guardian talks slow and
## low, a scribbled early-floor mob chatters fast and high. Nobody says anything
## and everybody has a personality.

# ═══════════════════════════════════════════════════════════════════ banks
## Roster keys in `Sfx.STREAMS`, one per vowel. Ordered dark → bright; the order
## is load-bearing, because `voice()` maps a seed onto it and a reorder would
## silently change every existing character's voice.
const BANKS: Array[String] = ["voice_u", "voice_a", "voice_e", "voice_i"]

## Pitch bands. A voice picks one and lives in it forever. The spread is wide on
## purpose — a boss and a scribble should not be neighbours — but the extremes
## are bounded so a re-pitched 22 kHz syllable never turns to mush (low) or to a
## mosquito (high).
const PITCH_BANDS: Array[float] = [0.72, 0.84, 0.95, 1.08, 1.22, 1.40]

## How far a single voice's pitch wanders inside its band, per syllable. Enough
## that a sentence is not a monotone; small enough that identity survives.
const PITCH_JITTER: float = 0.055

## Seconds between syllables at neutral cadence. Cadence is per-voice: some
## characters gabble, some take their time.
const GAP_MIN: float = 0.062
const GAP_MAX: float = 0.105

## Nobody gets to hold the floor. Barks are one line; utterances are a mouthful,
## not a monologue.
const MAX_SYLLABLES: int = 6

# ═════════════════════════════════════════════════════════════════════ moods
## What the mouth is DOING. Mood is not a different voice — it is the same voice
## under pressure, which is why every entry modifies the identity rather than
## replacing it.
enum Mood {
	TALK,      ## neutral chatter — the default
	QUESTION,  ## rises at the end
	SHOUT,     ## louder, higher, faster: a taunt or a war cry
	HURT,      ## short, sharp, up a little (a yelp is involuntary)
	DIE,       ## long fall, quiet at the end
	LAUGH,     ## short repeated syllables, bouncing pitch
	MUTTER,    ## quiet, low, slow — the tower's own commentary
}

## Per-mood shaping: pitch multiplier, gap multiplier, dB offset, default
## syllable count, and the final-syllable pitch LAND (>1 rises, <1 falls).
const MOOD_SHAPE: Dictionary = {
	Mood.TALK: {"pitch": 1.00, "gap": 1.00, "db": 0.0, "n": 3, "land": 0.90},
	Mood.QUESTION: {"pitch": 1.03, "gap": 1.05, "db": 0.0, "n": 3, "land": 1.22},
	Mood.SHOUT: {"pitch": 1.12, "gap": 0.78, "db": 3.0, "n": 2, "land": 1.10},
	Mood.HURT: {"pitch": 1.16, "gap": 0.70, "db": 1.0, "n": 1, "land": 0.86},
	Mood.DIE: {"pitch": 0.90, "gap": 1.35, "db": 0.0, "n": 3, "land": 0.62},
	Mood.LAUGH: {"pitch": 1.08, "gap": 0.62, "db": -1.0, "n": 4, "land": 1.06},
	Mood.MUTTER: {"pitch": 0.92, "gap": 1.30, "db": -6.0, "n": 3, "land": 0.88},
}

## Ceiling on how loud a voice may ever be relative to the call site's ask. A
## voice is CHARACTER, not an impact — it must never fight the spell that just
## went off. `Sfx`'s TICK/QUICK class trims do most of this work; this is the
## backstop for a call site that asks for something silly.
const MAX_DB: float = 4.0


# ═══════════════════════════════════════════════════════════════ identity
## A stable integer for anything with a name. Node names in Godot are unique per
## parent and stable for a node's life ("Enemy@3", "Hero", "Boss"), so this gives
## every body in the arena its own voice for free, with nothing to store and
## nothing to replicate.
static func seed_for(text: String) -> int:
	# hash() can return negative; the voice tables index off this, so fold it
	# positive HERE rather than at three call sites that will each forget.
	return absi(text.hash())


## Derive a voice identity from a seed. Total function — every integer produces a
## valid voice, so a caller can hand this a node id, a peer id or a class index
## without a lookup table.
##
## Returns { bank: String (an Sfx roster key), pitch: float, gap: float,
##           jitter: float, seed: int }.
static func voice(seed: int) -> Dictionary:
	var s: int = absi(seed)
	# Three decorrelated draws off one seed, each through a full avalanche mix.
	#
	# NOT plain divisions of the raw seed — that was the first implementation and
	# the suite caught it. Godot's `String.hash` is DJB2-flavoured, so names that
	# differ in one character hash to numbers that differ by ~1, and node names in
	# an arena are exactly that ("Enemy@2", "Enemy@3", "Enemy@4"...). Dividing
	# such a seed leaves the draws correlated: a whole wave of mobs came out with
	# three cadences between them. An avalanche mix decorrelates neighbours, which
	# is the entire point of using one.
	var bank_i: int = _mix(s, 0x9E3779B1) % BANKS.size()
	var band_i: int = _mix(s, 0x85EBCA77) % PITCH_BANDS.size()
	var gap_t: float = float(_mix(s, 0xC2B2AE3D) % 1000) / 999.0
	return {
		"bank": BANKS[bank_i],
		"pitch": PITCH_BANDS[band_i],
		"gap": lerpf(GAP_MIN, GAP_MAX, gap_t),
		"jitter": PITCH_JITTER,
		"seed": s,
	}


## Convenience: the voice of a live node, from its name. Takes an Object rather
## than Node so a test stub (a RefCounted with a `name`) works without dragging
## the scene tree in — the same reason Patience.gd types its npc as Object.
static func voice_of(who: Object) -> Dictionary:
	if who == null:
		return voice(0)
	var n: String = ""
	if who.has_method(&"get_name"):
		n = String(who.call(&"get_name"))
	if n.is_empty():
		n = str(who.get_instance_id())
	return voice(seed_for(n))


# ═══════════════════════════════════════════════════════════════ utterance
## How many syllables a written line is worth. Used when a BARK has text and we
## want the mouth to move for roughly as long as the words are on screen.
## Deliberately sub-linear: a six-word bark is not six times as long a noise as a
## one-word bark, it is about twice.
static func syllables_for_text(text: String, mood: int = Mood.TALK) -> int:
	var words: int = text.strip_edges().split(" ", false).size()
	if words <= 0:
		return int(MOOD_SHAPE[mood]["n"])
	var n: int = 1 + int(round(sqrt(float(words)) * 1.15))
	return clampi(n, 1, MAX_SYLLABLES)


## THE OUTPUT. An ordered list of syllables to fire, each
##   { key: String, pitch: float, delay: float, db: float }
## ready to be handed straight to `Sfx._emit`-shaped playback. Pure: no RNG
## object, no engine state — the per-syllable wobble is a deterministic mix of
## the voice seed and the syllable index, so the same character saying the same
## thing sounds the same twice, which is what makes it read as a VOICE.
static func plan(v: Dictionary, mood: int = Mood.TALK, syllables: int = 0) -> Array:
	var shape: Dictionary = MOOD_SHAPE.get(mood, MOOD_SHAPE[Mood.TALK])
	var n: int = syllables if syllables > 0 else int(shape["n"])
	n = clampi(n, 1, MAX_SYLLABLES)
	var base_pitch: float = float(v.get("pitch", 1.0)) * float(shape["pitch"])
	var gap: float = float(v.get("gap", GAP_MIN)) * float(shape["gap"])
	var jitter: float = float(v.get("jitter", PITCH_JITTER))
	var seed: int = int(v.get("seed", 0))
	var key: String = String(v.get("bank", BANKS[0]))
	var out: Array = []
	for i in n:
		# Deterministic wobble in [-1, 1] from (seed, i). A hash rather than an
		# RNG so `plan` stays pure and the suite can assert exact equality.
		var w: float = _wobble(seed, i)
		var pitch: float = base_pitch * (1.0 + jitter * w)
		if i == n - 1 and n > 1:
			# The LAND: the last syllable is the punctuation. Everything before
			# it is filler, so this is the only one that carries meaning.
			pitch = base_pitch * float(shape["land"])
		out.append({
			"key": key,
			"pitch": maxf(0.35, pitch),
			"delay": gap * float(i),
			"db": minf(float(shape["db"]), MAX_DB),
		})
	return out


## Total duration of a planned utterance, in seconds. Callers use this to keep a
## bark's bubble on screen for at least as long as the mouth is moving.
static func plan_duration(plan_out: Array) -> float:
	if plan_out.is_empty():
		return 0.0
	return float((plan_out[plan_out.size() - 1] as Dictionary).get("delay", 0.0))


## 31-bit avalanche mix (murmur3's finaliser). Every input bit changes about
## half the output bits, which is what makes two adjacent seeds produce unrelated
## voices. Masked positive at each step so the result is always a legal array
## index and never depends on how the platform signs a shift.
static func _mix(x: int, salt: int) -> int:
	var h: int = (x ^ salt) & 0x7FFFFFFF
	h = ((h ^ (h >> 15)) * 2246822519) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 3266489917) & 0x7FFFFFFF
	return (h ^ (h >> 16)) & 0x7FFFFFFF


## Deterministic pseudo-random in [-1, 1] from two ints. Integer hash mixing
## (a cheap xorshift-flavoured mixer), NOT randf() — `plan()` must be pure or
## the tests can only ever assert ranges, and a voice that wobbles differently
## every utterance is not an identity.
static func _wobble(seed: int, i: int) -> float:
	var x: int = (seed * 2654435761 + i * 40503) & 0x7FFFFFFF
	x = (x ^ (x >> 13)) * 1274126177 & 0x7FFFFFFF
	x = x ^ (x >> 16)
	return (float(x % 2001) / 1000.0) - 1.0
