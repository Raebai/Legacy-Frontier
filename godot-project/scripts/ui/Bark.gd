class_name Bark
extends RefCounted
## ALL THE NARRATIVE THERE IS. One line over a character's head, then gone.
##
## Spec: "Narrative is barks only. One line over a character's head at scripted
## moments. No dialogue system, no branching, no NPC memory, no LLM." So this
## file is a LINE TABLE and a picker, and nothing else. There is no state
## machine, no queue, no conversation. If a future feature wants a second line to
## follow the first, that is a cutscene and the spec says no.
##
## ── IT REUSES SpeechBubble VERBATIM ────────────────────────────────────────
## `scenes/SpeechBubble.tscn` + `scripts/SpeechBubble.gd` already do exactly
## "one line above a character, shrink-to-fit, fades on a timer". They were built
## for the parked AI-NPC stack and they outlive it unchanged — this file does not
## reimplement any of it, it just parents one to whoever is speaking and calls
## `say()`. That is the single largest piece of reuse available in this feature.
##
## ── IT CAN NEVER BLOCK ─────────────────────────────────────────────────────
## `SpeechBubble` is a Node2D with no Control focus, no pause, no input handling,
## and `say()` is fire-and-forget (we deliberately do NOT await it). A bark
## therefore cannot eat a tap, cannot stop a dash, and cannot delay a cast. On a
## phone, in a fight, that is not a nice-to-have.
##
## ── THE VOICE ──────────────────────────────────────────────────────────────
## Chalk and graphite. Dry, short, present-tense, lower-case-feeling even in
## caps. The tower is DRAWN — an unseen hand sketches each floor, its mobs and
## its boss, and you are a drawing climbing toward whoever holds the pencil. So
## the barks talk about PAPER, INK, LINES and the HAND, and they never explain
## any of it. Nobody reads exposition on a phone; they read four words in half a
## second while dodging.
##
## Hard rules for anything added here:
##   * five words or fewer, ideally three;
##   * no proper nouns, no lore terms nobody has been taught;
##   * never a question the player is expected to answer;
##   * never an instruction (that is the HUD's job, and the HUD is another
##     agent's file).

const BUBBLE_SCENE: PackedScene = preload("res://scenes/SpeechBubble.tscn")

## Name of the bubble node we parent to a speaker. Reused, never re-created — a
## second bubble on the same body would render two lines on top of each other.
const BUBBLE_NAME: StringName = &"BarkBubble"

## How long a line stays up. Short: a bark is punctuation, not reading material.
const HOLD: float = 1.9
## A single speaker cannot bark again inside this window. Without it, a kill
## chain would stack a bubble per body and the screen would be a wall of chalk.
const COOLDOWN: float = 3.0

## Chance a "flavour" bark actually fires. The moments that MUST land (a floor
## opening, the guardian arriving) pass `always = true`; everything else is
## sampled, because a character who comments on literally every event stops
## being a character and becomes a tickertape.
const FLAVOUR_CHANCE: float = 0.35


# ══════════════════════════════════════════════════════════════════ the lines
## event → the things that can be said. Order is not significance; the picker
## rolls across the whole row.
##
## Events are grouped by WHO speaks them, because that is what decides tone: the
## hero is terse and unimpressed, mobs are scribbles that barely form a thought,
## the guardian is confident ink that knows it was drawn well.
const LINES: Dictionary = {
	# ── the climb (the hero) ────────────────────────────────────────────────
	&"run_start": [
		"first line drawn.",
		"up, then.",
		"paper's blank. good.",
	],
	&"floor_enter": [
		"fresh sheet.",
		"still wet.",
		"new page.",
		"drawn in a hurry.",
		"someone rushed this one.",
	],
	&"floor_clear": [
		"page turned.",
		"erased.",
		"next.",
	],
	&"fall": [
		"redrawn. lower.",
		"back down the page.",
		"the hand pressed harder.",
	],
	&"low_health": [
		"lines are smudging.",
		"running out of chalk.",
		"i'm coming apart.",
	],
	&"streak": [
		"the pencil's shaking.",
		"can't draw them fast enough.",
		"more. keep drawing.",
	],
	&"close_call": [
		"nearly rubbed out.",
		"still on the page.",
	],

	# ── the floor answering (mobs) ──────────────────────────────────────────
	&"wave_start": [
		"more ink.",
		"here they come.",
		"the hand's busy.",
	],
	&"wave_clear": [
		"blank again.",
		"that's the page.",
	],
	&"enemy_spawn": [
		"scribbled.",
		"barely a shape.",
		"drawn wrong.",
		"hhh.",
	],
	&"enemy_die": [
		"undrawn.",
		"smudge.",
		"gone.",
	],

	# ── the guardian ────────────────────────────────────────────────────────
	&"boss_arrive": [
		"THIS one was finished.",
		"drawn with care.",
		"inked. not sketched.",
	],
	&"boss_phase": [
		"the hand adds a line.",
		"not done with me.",
		"redrawn, and worse.",
	],
	## PHASE THREE. Split off `boss_phase` because a third break is not a fourth
	## quarter — it is the guardian deciding the page is expendable.
	&"boss_final": [
		"the page is mine now.",
		"then we both burn.",
		"nothing below this line.",
	],
	&"boss_down": [
		"even ink runs.",
		"crossed out.",
	],

	# ── THE FOUR ARTISTS ────────────────────────────────────────────────────
	# Per-guardian variants of the four beats above, reached through
	# `say_variant(who, base, boss.bark_suffix())` — an unauthored suffix simply
	# falls back to the generic row, so a fifth boss speaks the moment it exists
	# and gets its own voice whenever somebody writes one.
	#
	# The register is DEITY, not monster. Each of these is a hand that has drawn
	# whole floors; none of them explains itself, and none of them says more than
	# one line, because a god that monologues is a codex with extra steps.

	# THE ASHSPIRE GUARDIAN — charcoal colossus, the first idea, never corrected.
	&"boss_arrive_guardian": [
		"i was the first shape.",
		"stone. before anything else.",
		"the page begins with me.",
	],
	&"boss_phase_guardian": [
		"the hand presses harder.",
		"deeper into the stone.",
	],
	&"boss_final_guardian": [
		"i am the last line.",
		"burn the page, then.",
	],
	&"boss_down_guardian": [
		"back to charcoal.",
		"smudge me, then.",
	],

	# THE SCRIBBLE — a child's hand, pressed to tearing. It is a tantrum with a body.
	&"boss_arrive_scribble": [
		"SCRIBBLE SCRIBBLE SCRIBBLE.",
		"i got made ANGRY.",
		"the hand was little.",
	],
	&"boss_phase_scribble": [
		"HARDER. press HARDER.",
		"over and over and over.",
	],
	&"boss_final_scribble": [
		"TEAR THE PAPER.",
		"scribble it ALL out.",
	],
	&"boss_down_scribble": [
		"rubbed out.",
		"aww.",
	],

	# THE CARTOGRAPHER — a draughtsman. It does not draw a monster; it draws the floor.
	&"boss_arrive_cartographer": [
		"you stand where i drew.",
		"the floor is my line.",
		"measured. plotted. mine.",
	],
	&"boss_phase_cartographer": [
		"redrawing the floor.",
		"new lines. same page.",
	],
	&"boss_final_cartographer": [
		"every line at once.",
		"the last measure.",
	],
	&"boss_down_cartographer": [
		"off the plan.",
		"my scale was wrong.",
	],

	# THE ILLUMINATOR — gold leaf on vellum, and it has done this before.
	&"boss_arrive_illuminator": [
		"i have done this before.",
		"gold, on the last page.",
		"the light was always mine.",
	],
	&"boss_phase_illuminator": [
		"gilding what is left.",
		"the page begins to shine.",
	],
	&"boss_final_illuminator": [
		"the final page opens.",
		"everything, illuminated.",
	],
	&"boss_down_illuminator": [
		"the gold runs.",
		"unfinished, after all.",
	],

	# THE ERASER — it does not draw, so it does not boast. Flat, incurious, and
	# stated as WORK rather than as threat, which is what makes it unpleasant: the
	# other four want something from you, and this one is just clearing up.
	&"boss_arrive_eraser": [
		"this page was a mistake.",
		"cleaner, nearer to me.",
		"i take it back.",
	],
	&"boss_phase_eraser": [
		"less of it now.",
		"there. and there.",
	],
	&"boss_final_eraser": [
		"nothing left to stand on.",
		"blank. as it began.",
	],
	&"boss_down_eraser": [
		"...it stays, then.",
		"i was not finished.",
	],

	# THE ETCHER — a craftsman mid-process, talking about the WORK and not about
	# you. Every line is a step in etching, which is also the tell: when it says the
	# plate is going in, that is the wind-up it is telling you to come and break.
	&"boss_arrive_etcher": [
		"the ground is laid.",
		"i cut. the acid decides.",
		"the acid bites deeper.",
	],
	&"boss_phase_etcher": [
		"deeper into the plate.",
		"another bath.",
	],
	&"boss_final_etcher": [
		"the plate goes in whole.",
		"let it eat everything.",
	],
	&"boss_down_etcher": [
		"over-bitten.",
		"the plate is ruined.",
	],

	# ── THE ELITES ──────────────────────────────────────────────────────────
	# A named body in a wave of eleven. It gets ONE line when it arrives and one
	# more on the beat that defines it — everything else it does it does with its
	# mouth alone (`voice_only`), because two elites narrating a floor is a
	# tickertape and the hero's own lines are what the player is listening for.
	#
	# Each announce row is written so an experienced player hears WHICH affix is on
	# the floor: the quickened one gabbles, the inked one barely moves its mouth,
	# the keen one asks, the herald addresses the room rather than you.
	&"elite_quickened": [
		"drawn in a hurry.",
		"no time. no time.",
		"faster than the hand.",
	],
	&"elite_inked": [
		"pressed in deep.",
		"i don't move.",
		"part of the page now.",
	],
	&"elite_smudged": [
		"here. no — here.",
		"smeared sideways.",
		"the hand slipped.",
	],
	&"elite_volatile": [
		"still wet.",
		"not dry yet.",
		"careful with me.",
	],
	&"elite_keen": [
		"drawn watching.",
		"i know that shape.",
		"i see the line coming.",
	],
	&"elite_herald": [
		"the page is listening.",
		"the hand is coming.",
		"all of you. up.",
	],
	## THE HOWL. The one elite line that is a MECHANIC — it is the callout that
	## says "burn the glowing one first", and in co-op it is the cheapest possible
	## shout-at-your-friend moment. Always fires; never sampled.
	&"elite_herald_call": [
		"UP. ALL OF YOU.",
		"the hand presses harder.",
		"faster. now.",
	],
	## The fizz warning, once, as it crosses into the burst band. It is a real read
	## — "finish it somewhere else" — so it gets the bubble the pulsing alone lacks.
	&"elite_volatile_fizz": [
		"it's running.",
		"too wet. too wet.",
		"i'm coming open.",
	],
}

## Mood the SPEAKER's gibberish takes for each event — see `Gibberish.Mood`.
## Unlisted events fall back to TALK. A bark and its voice must agree: a dying
## line delivered in a cheerful chirp is the sort of thing that reads as broken
## rather than as a bug.
const MOODS: Dictionary = {
	&"run_start": Gibberish.Mood.MUTTER,
	&"floor_enter": Gibberish.Mood.MUTTER,
	&"floor_clear": Gibberish.Mood.TALK,
	&"fall": Gibberish.Mood.HURT,
	&"low_health": Gibberish.Mood.HURT,
	&"streak": Gibberish.Mood.SHOUT,
	&"close_call": Gibberish.Mood.HURT,
	&"wave_start": Gibberish.Mood.TALK,
	&"wave_clear": Gibberish.Mood.LAUGH,
	&"enemy_spawn": Gibberish.Mood.MUTTER,
	&"enemy_die": Gibberish.Mood.DIE,
	&"boss_arrive": Gibberish.Mood.SHOUT,
	&"boss_phase": Gibberish.Mood.SHOUT,
	&"boss_final": Gibberish.Mood.SHOUT,
	&"boss_down": Gibberish.Mood.DIE,

	# The four artists. Same beats, different temperaments — the Scribble screams
	# its whole fight, the Cartographer states things, the Illuminator is unhurried
	# until the last page, and the Guardian is stone that has decided to speak.
	&"boss_arrive_guardian": Gibberish.Mood.MUTTER,
	&"boss_phase_guardian": Gibberish.Mood.SHOUT,
	&"boss_final_guardian": Gibberish.Mood.SHOUT,
	&"boss_down_guardian": Gibberish.Mood.DIE,
	&"boss_arrive_scribble": Gibberish.Mood.SHOUT,
	&"boss_phase_scribble": Gibberish.Mood.SHOUT,
	&"boss_final_scribble": Gibberish.Mood.SHOUT,
	&"boss_down_scribble": Gibberish.Mood.DIE,
	&"boss_arrive_cartographer": Gibberish.Mood.TALK,
	&"boss_phase_cartographer": Gibberish.Mood.TALK,
	&"boss_final_cartographer": Gibberish.Mood.SHOUT,
	&"boss_down_cartographer": Gibberish.Mood.DIE,
	&"boss_arrive_illuminator": Gibberish.Mood.MUTTER,
	&"boss_phase_illuminator": Gibberish.Mood.TALK,
	&"boss_final_illuminator": Gibberish.Mood.SHOUT,
	&"boss_down_illuminator": Gibberish.Mood.DIE,
	# The Eraser never raises its voice — not even at the end. It is the only artist
	# on the roster that MUTTERs through its own final page, and that is the whole
	# character: it is not fighting you, it is tidying.
	&"boss_arrive_eraser": Gibberish.Mood.MUTTER,
	&"boss_phase_eraser": Gibberish.Mood.MUTTER,
	&"boss_final_eraser": Gibberish.Mood.TALK,
	&"boss_down_eraser": Gibberish.Mood.DIE,
	# The Etcher states its process, and only shouts when the plate goes in whole.
	&"boss_arrive_etcher": Gibberish.Mood.TALK,
	&"boss_phase_etcher": Gibberish.Mood.TALK,
	&"boss_final_etcher": Gibberish.Mood.SHOUT,
	&"boss_down_etcher": Gibberish.Mood.DIE,

	# The elites. The mood IS the tell: a rising QUESTION is the keen one reading
	# you, a SHOUT is the herald addressing the room, a MUTTER is the inked one
	# refusing to be impressed.
	&"elite_quickened": Gibberish.Mood.SHOUT,
	&"elite_inked": Gibberish.Mood.MUTTER,
	&"elite_smudged": Gibberish.Mood.TALK,
	&"elite_volatile": Gibberish.Mood.SHOUT,
	&"elite_keen": Gibberish.Mood.QUESTION,
	&"elite_herald": Gibberish.Mood.SHOUT,
	&"elite_herald_call": Gibberish.Mood.SHOUT,
	&"elite_volatile_fizz": Gibberish.Mood.HURT,
}

# ═════════════════════════════════════════════════════════════ voice identity
## Metadata a speaker may carry to override how its mouth is derived. All three
## are OPTIONAL — a body with none of them speaks exactly as before, from its node
## name, which is what every mob in the game does.
##
## ⚠ WHY A META AND NOT THE NODE NAME. `Gibberish.voice_of` reads `name`, and a
## node's name is assigned by whichever parent adopts it — in co-op the two peers'
## arenas do not necessarily hand the same body the same name, so a name-derived
## voice can differ across a party. Anything with BILLING (an elite, a guardian)
## therefore stamps a seed derived from REPLICATED data instead: the spawn
## dictionary for an elite, the class's own title for a boss. Both are identical on
## every peer by construction, so the same body sounds the same on both phones.
const SEED_META: StringName = &"voice_seed"     ## int — a stable identity
const BAND_META: StringName = &"voice_band"     ## Vector2i — a pitch slice (lo, hi)
const DB_META: StringName = &"voice_db"         ## float — billing, in dB


## The full voice dict for a speaker, honouring any of the three metas above.
static func voice_of_node(who: Object) -> Dictionary:
	if who == null:
		return Gibberish.voice(0)
	var seed: int = -1
	if who is Node and (who as Node).has_meta(SEED_META):
		seed = int((who as Node).get_meta(SEED_META))
	if seed < 0:
		return _banded(Gibberish.voice_of(who), who)
	return _banded(Gibberish.voice(seed), who)


static func _banded(v: Dictionary, who: Object) -> Dictionary:
	if not (who is Node) or not (who as Node).has_meta(BAND_META):
		return v
	var band: Vector2i = (who as Node).get_meta(BAND_META) as Vector2i
	return Gibberish.voice_in_bands(int(v.get("seed", 0)), band.x, band.y)


static func voice_db_of(who: Object) -> float:
	if who is Node and (who as Node).has_meta(DB_META):
		return float((who as Node).get_meta(DB_META))
	return 0.0


# ══════════════════════════════════════════════════════════════════ the picker
## Every authored event. Exposed so a test can sweep the table rather than
## hard-coding a list that drifts out of date the first time a line is added.
static func events() -> Array:
	return LINES.keys()


## The line for an event. `roll` selects deterministically (a test can pin it);
## pass -1 for a random pick. Returns "" for an unknown event — a missing event
## must be SILENT, never a placeholder string on screen.
static func line_for(event: StringName, roll: int = -1) -> String:
	var row: Array = LINES.get(event, [])
	if row.is_empty():
		return ""
	var i: int = (randi() if roll < 0 else roll) % row.size()
	return String(row[i])


## The gibberish mood an event is spoken in.
static func mood_for(event: StringName) -> int:
	return int(MOODS.get(event, Gibberish.Mood.TALK))


# ══════════════════════════════════════════════════════════════════ speaking
## Put a line over `who`'s head and speak it in `who`'s voice.
##
## Returns true if a line actually landed. False means: unknown event, dead node,
## still inside the per-speaker cooldown, or the flavour roll declined — all four
## are normal, none is an error, and none is worth logging in a fight.
##
## `always` bypasses the flavour roll for beats that MUST read (a floor opening,
## the guardian arriving). Everything else stays sampled on purpose.
static func say(who: Node, event: StringName, always: bool = false, roll: int = -1) -> bool:
	if who == null or not is_instance_valid(who) or not who.is_inside_tree():
		return false
	if not (who is Node2D):
		return false          # the bubble is world-space; a Control speaker is a bug
	var text: String = line_for(event, roll)
	if text.is_empty():
		return false
	if not always and randf() > FLAVOUR_CHANCE:
		return false
	if not _off_cooldown(who):
		return false
	var bubble: Node = _bubble_for(who as Node2D)
	if bubble == null:
		return false
	# NOT awaited. `SpeechBubble.say` yields a few frames while it shrink-to-fits;
	# awaiting it here would make every bark call site a coroutine, and a bark
	# must never be something the caller has to wait for.
	bubble.call(&"say", text, HOLD, 0.0)
	_voice(who, event, text)
	return true


## THE SAME BARK, IN A NAMED SPEAKER'S OWN WORDS.
##
## Tries `<event>_<suffix>` and falls back to `<event>` when nobody has written the
## variant. That fallback is the whole design: `VoiceDirector` asks every guardian
## for a suffix and never has to know which of them have lines, so a boss added
## tomorrow speaks immediately in the generic voice and gets its own the moment
## somebody writes a row for it. An empty suffix is just `say()`.
static func say_variant(who: Node, event: StringName, suffix: String,
		always: bool = false, roll: int = -1) -> bool:
	if suffix != "":
		var special := StringName("%s_%s" % [event, suffix])
		if LINES.has(special):
			return say(who, special, always, roll)
	return say(who, event, always, roll)


## Speak with no bubble — just the mouth. For the moments where a line would be
## noise but silence is worse: taking a hit, dying, swinging at nothing.
static func voice_only(who: Node, mood: int, syllables: int = 0) -> void:
	if who == null or not is_instance_valid(who) or not who.is_inside_tree():
		return
	var sfx: Node = _sfx(who)
	if sfx == null or not sfx.has_method(&"speak_voice"):
		return
	sfx.call(&"speak_voice", voice_of_node(who), mood, syllables, voice_db_of(who))


# ══════════════════════════════════════════════════════════════════ internals
## Find or build this speaker's bubble. One per body, reused for its whole life.
static func _bubble_for(who: Node2D) -> Node:
	var existing: Node = who.get_node_or_null(NodePath(String(BUBBLE_NAME)))
	if existing != null:
		return existing
	var bubble: Node = BUBBLE_SCENE.instantiate()
	bubble.name = String(BUBBLE_NAME)
	who.add_child(bubble)
	return bubble


## Per-speaker rate limit, stored on the node itself rather than in a static
## dictionary. A static dict keyed by instance id would leak an entry for every
## body that ever spawned — in a game whose whole premise is "waves of drawn
## mobs, forever", that is an unbounded map.
static func _off_cooldown(who: Node) -> bool:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var last: float = float(who.get_meta(&"bark_last", -999.0))
	if now - last < COOLDOWN:
		return false
	who.set_meta(&"bark_last", now)
	return true


static func _voice(who: Node, event: StringName, text: String) -> void:
	var sfx: Node = _sfx(who)
	if sfx == null or not sfx.has_method(&"speak_voice"):
		return
	var mood: int = mood_for(event)
	sfx.call(&"speak_voice", voice_of_node(who), mood,
		Gibberish.syllables_for_text(text, mood), voice_db_of(who))


## Reach the Sfx autoload through the TREE, never as a bare global identifier.
## Autoloads are not registered under `--script`, so naming `Sfx` in a static
## function here would be a COMPILE error that surfaces as an unrelated missing
## method on whatever loads this file. Relative-from-root rather than
## "/root/Sfx" for the same reason Hype.gd and Sfx.gd do it: a --script context
## has no active scene and an absolute get_node logs an error on every call.
static func _sfx(from: Node) -> Node:
	var tree: SceneTree = from.get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(^"Sfx")
