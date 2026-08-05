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
## ⚠ THE DRAWING METAPHOR IS GONE, ON THE MAKER'S RULING: *"no drawing references
## please as they make no sense"*. Every line in this table used to be about paper —
## "pencils up", "you're a doodle", "mostly eraser now", "someone redraw them". That
## register belongs to `Bark`, which is the CLIMB's voice and speaks for a hero
## muttering at a page they are inside. **A duel is two fighters in a ring.** Neither
## of them is a drawing, nobody in the scene is holding a pencil, and a taunt that
## reaches for a metaphor the fight never established reads as a different game's
## dialogue pasted in.
##
## Two people who do not like each other, mid-fight, out of breath. Hard rules:
##
##   * five words or fewer, ideally three;
##   * no proper nouns, no lore terms nobody has been taught;
##   * never anime-earnest ("I won't lose!"), never generic-fantasy ("face my blade");
##   * never an instruction to the PLAYER — nobody in this mode is playing;
##   * and now: nothing about paper, ink, pencils, lines, sketches or erasers.
##
## ── AND THEY ANSWER WHO IS IN FRONT OF THEM ─────────────────────────────────────
## Maker: *"make the bots text chats interact with each other based on who they are
## fighting"*. A generic table cannot do that — every fighter said the same five
## things regardless of whether it was facing a wall of armour or a man on fire.
##
## `VS_LINES` is one row per opposing CLASS, and it is about what that class IS: the
## Juggernaut's armour, the Cryomancer's ice, the Cleric's healing, the Shadowblade
## never standing still. The picker prefers a VS line when one exists for the beat
## (see `line_for`) and falls back to the generic row, so a class with a thin row
## still speaks rather than going silent — the fallback is the whole reason both
## tables exist instead of nine copies of five beats.
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
		"go on then.",
		"you first.",
		"this won't take long.",
		"i've fought worse.",
		"try and land one.",
	],
	# ── the first hit of the bout. The one who LANDED it says this.
	&"first_blood": [
		"that's one.",
		"felt that, did you.",
		"too slow.",
		"stand still next time.",
	],
	# ── a genuinely big hit. Still the attacker; still gloating.
	&"big_hit": [
		"sit down.",
		"stay down.",
		"that one counted.",
		"get up. i'll wait.",
		"still standing? bold.",
	],
	# ── said by whoever is nearly gone. Not brave. Not begging.
	&"low_health": [
		"not done yet.",
		"hold together. hold.",
		"i can still swing.",
		"that one hurt.",
		"i've had worse.",
	],
	# ── the win. The loudest thing in the clip, and the last words in it.
	&"finisher": [
		"done.",
		"stay there.",
		"next.",
		"told you.",
		"that's that, then.",
	],
}

## ── WHAT THEY SAY ABOUT THE CLASS OPPOSITE ──────────────────────────────────────
## Indexed by the OPPONENT's class, ordered exactly like `BotMatch.CLASS_LABELS`:
## ARCANIST, SHADOWBLADE, BRAWLER, JUGGERNAUT, CLERIC, CRYOMANCER, STORMCALLER,
## WARLOCK, SWORDSAINT.
##
## ⚠ EACH ROW IS ABOUT THE THING THAT CLASS DOES, not about its name — the fighters
## have never been told what they are called, and a line naming a class reads as a UI
## label being spoken aloud. The Juggernaut is "all that armour", the Cleric is "stop
## healing", the Shadowblade is "stand still". That is also what makes them land: the
## viewer has just WATCHED the thing the line is complaining about.
##
## Deliberately only the two loud beats, `fight_start` and `big_hit`. A per-class
## low-health line would be a fighter commenting on its opponent's kit while dying,
## which is the one beat this file's own note says is not swagger.
const VS_LINES: Dictionary = {
	&"fight_start": [
		["all that theory. right."],           # 0 ARCANIST
		["stand still, coward."],              # 1 SHADOWBLADE
		["no reach at all."],                  # 2 BRAWLER
		["all that armour. slow."],            # 3 JUGGERNAUT
		["pray after, not during."],           # 4 CLERIC
		["put the ice down."],                 # 5 CRYOMANCER
		["big sparks. small man."],            # 6 STORMCALLER
		["fight me, not your pets."],          # 7 WARLOCK
		["one sword. one chance."],            # 8 SWORDSAINT
	],
	&"big_hit": [
		["think your way out of that."],       # 0 ARCANIST
		["caught you. finally."],              # 1 SHADOWBLADE
		["reach. that's what that was."],      # 2 BRAWLER
		["armour did nothing."],               # 3 JUGGERNAUT
		["heal that one."],                    # 4 CLERIC
		["thawed you out."],                   # 5 CRYOMANCER
		["grounded."],                         # 6 STORMCALLER
		["where are your pets now."],          # 7 WARLOCK
		["should have parried."],              # 8 SWORDSAINT
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
## `vs_class` is the OPPONENT's class index (`BotMatch.CLASS_LABELS` order), or -1 for
## "no opinion about who that is". When a VS row exists for this beat and that class,
## the picker prefers it — the whole point of the maker's ask is that the fighters
## answer each other, and a line that only shows up one time in five does not read as
## interaction, it reads as a coincidence.
##
## ⚠ THE FALLBACK IS NOT DEFENSIVE PADDING. `VS_LINES` deliberately covers only two of
## the five beats, so three beats have no per-class row at all and MUST come out of
## the generic table. A picker that returned "" for those would silently mute
## `low_health` and `finisher` — the two beats the recording most needs.
static func line_for(beat: StringName, roll: int = -1, vs_class: int = -1) -> String:
	var row: Array = _row_for(beat, vs_class)
	if row.is_empty():
		return ""
	var i: int = (randi() if roll < 0 else roll) % row.size()
	return String(row[i])


## The row a pick will come from: the per-opponent one when there is one, else the
## generic one. Split out so the suite can assert the choice without picking a line.
static func _row_for(beat: StringName, vs_class: int) -> Array:
	if vs_class >= 0:
		var table: Array = VS_LINES.get(beat, [])
		if vs_class < table.size():
			var vs_row: Array = table[vs_class]
			if not vs_row.is_empty():
				return vs_row
	return LINES.get(beat, [])


## Does this beat carry a line specifically about `vs_class`? Exposed for the suite
## and for anything that wants to know whether a bubble will be personal.
static func has_vs_line(beat: StringName, vs_class: int) -> bool:
	if vs_class < 0:
		return false
	var table: Array = VS_LINES.get(beat, [])
	return vs_class < table.size() and not (table[vs_class] as Array).is_empty()


## The gibberish mood a beat is spoken in. Unlisted beats fall back to TALK, which is
## the same contract `Bark.mood_for` offers.
static func mood_for(beat: StringName) -> int:
	return int(MOODS.get(beat, Gibberish.Mood.TALK))


## How many lines a beat can choose from. Used by the suite to assert no beat is a
## one-liner (a taunt you hear every single match stops being a taunt).
static func count_for(beat: StringName) -> int:
	var row: Array = LINES.get(beat, [])
	return row.size()


## ⚠ THE WORDS THIS TABLE MAY NOT CONTAIN, as data rather than as a comment. The
## maker's ruling ("no drawing references please as they make no sense") is the kind
## that decays the moment somebody adds "one more good line", so the suite sweeps
## every row against this list instead of trusting the next author to remember.
const BANNED_WORDS: Array[String] = [
	"pencil", "draw", "drawn", "drawing", "doodle", "sketch", "eraser", "erase",
	"rubbed", "paper", "page", "ink", "smudge", "smudged", "line", "lines", "redraw",
	"crossed out", "scribble",
]


## Every line in both tables, for the sweep. Derived, never hand-listed — a hand-listed
## copy is exactly how a new row escapes the check that exists to police it.
static func all_lines() -> Array[String]:
	var out: Array[String] = []
	for beat: Variant in LINES.keys():
		for s: Variant in (LINES[beat] as Array):
			out.append(String(s))
	for beat: Variant in VS_LINES.keys():
		for row: Variant in (VS_LINES[beat] as Array):
			for s: Variant in (row as Array):
				out.append(String(s))
	return out
