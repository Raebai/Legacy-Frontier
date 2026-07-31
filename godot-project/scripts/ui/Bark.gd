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
	&"boss_down": [
		"even ink runs.",
		"crossed out.",
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
	&"boss_down": Gibberish.Mood.DIE,
}


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


## Speak with no bubble — just the mouth. For the moments where a line would be
## noise but silence is worse: taking a hit, dying, swinging at nothing.
static func voice_only(who: Node, mood: int, syllables: int = 0) -> void:
	if who == null or not is_instance_valid(who) or not who.is_inside_tree():
		return
	var sfx: Node = _sfx(who)
	if sfx != null and sfx.has_method(&"speak_for"):
		sfx.call(&"speak_for", who, mood, syllables)


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
	if sfx == null or not sfx.has_method(&"speak_for"):
		return
	var mood: int = mood_for(event)
	sfx.call(&"speak_for", who, mood, Gibberish.syllables_for_text(text, mood))


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
