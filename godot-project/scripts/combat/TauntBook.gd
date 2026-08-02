class_name TauntBook
extends RefCounted
## WHAT THE FIGHTERS SAY TO EACH OTHER. A line table and a picker — nothing else.
##
## A bot match was SILENT of dialogue. `VoiceDirector` is the game's bark observer and
## it binds to Encounter / Boss / enemy-group / GameState signals, none of which exist
## on the versus stage, so two heroes could beat each other to death without either of
## them having an opinion about it. For a mode whose whole purpose is to be RECORDED,
## that is the difference between a physics demo and a fight.
##
## ── WHY A SECOND TABLE AND NOT MORE ROWS IN `Bark.LINES` ────────────────────────
## `Bark.say()` can only speak events that exist in its own fixed table, and `Bark` is
## the CLIMB's voice: the hero muttering at the page, mobs barely forming a thought,
## the guardian being inked. A duel is a different register — these two are talking AT
## each other, not at the paper. Mixing "fresh sheet." into a taunt row would blur the
## one voice this game has already established.
##
## What IS reused: the bubble (`scenes/SpeechBubble.tscn`, driven exactly the way
## `Bark.say` drives it), the gibberish mouth (`Gibberish.Mood`), and the per-speaker
## meta cooldown. This file is only the WORDS.
##
## ── THE VOICE ───────────────────────────────────────────────────────────────────
## Same chalk-and-graphite world as `Bark`, one notch ruder. These are two drawings
## trying to erase each other and neither is impressed. Hard rules, inherited:
##
##   * five words or fewer, ideally three;
##   * no proper nouns, no lore terms nobody has been taught;
##   * never anime-earnest ("I won't lose!"), never generic-fantasy ("face my blade");
##   * never an instruction to the PLAYER — nobody in this mode is playing.
##
## ── PURE, SO IT IS TESTABLE ─────────────────────────────────────────────────────
## Every function here is static and touches no node, no autoload and no tree. That is
## deliberate: `tools/slice_test_botmatch_intro.gd` sweeps the whole table without
## standing up a scene, so a beat that loses its lines fails a suite rather than
## silently producing an empty bubble in a recording.

## THE BEATS, DECLARED. This is the contract, and it is separate from `LINES` on
## purpose: the suite asserts the two agree in BOTH directions, so a beat with no lines
## fails, and so does a row nothing can ever reach because no caller knows its key.
const BEATS: Array[StringName] = [
	&"fight_start",
	&"first_blood",
	&"big_hit",
	&"low_health",
	&"finisher",
]

## How long a taunt stays up. Matched to `Bark.HOLD` — a taunt is punctuation, and a
## bubble that outlives the exchange it commented on reads as a stuck UI.
const HOLD: float = 1.9

## beat → the things that can be said. Order is not significance; the picker rolls
## across the whole row.
const LINES: Dictionary = {
	# ── the bell. Said by ONE of them, not both: two openers is a script reading.
	&"fight_start": [
		"pencils up.",
		"draw first.",
		"you're a doodle.",
		"this won't take long.",
		"nice lines. shame.",
	],
	# ── the first mark on the page. The one who LANDED it says this.
	&"first_blood": [
		"first mark's mine.",
		"smudged you.",
		"that's one line off.",
		"oh, you felt that.",
	],
	# ── a genuinely big hit. Still the attacker; still gloating.
	&"big_hit": [
		"sit down.",
		"back to the sketch.",
		"press harder, i said.",
		"that'll leave a mark.",
		"how's the paper now.",
	],
	# ── said by whoever is nearly gone. Not brave. Not begging.
	&"low_health": [
		"mostly eraser now.",
		"hold together. hold.",
		"my lines are going.",
		"still on the page.",
		"i've had worse drawn.",
	],
	# ── the win. The loudest thing in the clip, and the last words in it.
	&"finisher": [
		"rubbed out.",
		"crossed out.",
		"next page.",
		"that's the drawing, then.",
		"someone redraw them.",
	],
}

## Mood the speaker's gibberish takes for each beat — see `Gibberish.Mood`. A taunt
## delivered in the wrong mouth reads as broken rather than as a bug: the low-health
## line is the only one that is not swagger, and it is the only HURT here.
const MOODS: Dictionary = {
	&"fight_start": Gibberish.Mood.TALK,
	&"first_blood": Gibberish.Mood.LAUGH,
	&"big_hit": Gibberish.Mood.SHOUT,
	&"low_health": Gibberish.Mood.HURT,
	&"finisher": Gibberish.Mood.SHOUT,
}


## Every declared beat. Exposed so a test sweeps the contract rather than hard-coding
## a list that drifts the first time a beat is added.
static func beats() -> Array[StringName]:
	return BEATS


## The line for a beat. `roll` selects DETERMINISTICALLY (a test pins it); pass -1 for
## a random pick. Returns "" for an unknown beat — a missing beat must be SILENT,
## never a placeholder string over a fighter's head in a recording.
##
## Mirrors `Bark.line_for` exactly, including the negative-roll convention, so the two
## pickers cannot drift into behaving differently.
static func line_for(beat: StringName, roll: int = -1) -> String:
	var row: Array = LINES.get(beat, [])
	if row.is_empty():
		return ""
	var i: int = (randi() if roll < 0 else roll) % row.size()
	return String(row[i])


## The gibberish mood a beat is spoken in. Unlisted beats fall back to TALK, which is
## the same contract `Bark.mood_for` offers.
static func mood_for(beat: StringName) -> int:
	return int(MOODS.get(beat, Gibberish.Mood.TALK))


## How many lines a beat can choose from. Used by the suite to assert no beat is a
## one-liner (a taunt you hear every single match stops being a taunt).
static func count_for(beat: StringName) -> int:
	var row: Array = LINES.get(beat, [])
	return row.size()
