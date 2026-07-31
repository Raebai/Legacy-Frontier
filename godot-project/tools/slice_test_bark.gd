# Run: godot --headless --path godot-project --script tools/slice_test_bark.gd
#
# Covers BARKS — Bark.gd (the line table + the picker) riding SpeechBubble.gd
# unchanged, and VoiceDirector.gd (the observer that decides when to speak).
#
# WHAT CANNOT BE TESTED: whether the lines are any good, and whether they read in
# half a second while dodging. Those need a phone and a person.
#
# WHAT CAN, and every one is a real failure mode:
#   * a bark NEVER blocks. The spec's hard rule. `say()` must return a plain bool
#     synchronously — the moment somebody awaits the bubble's shrink-to-fit
#     inside it, every call site becomes a coroutine and a bark can eat a frame
#     of input in a fight;
#   * the lines obey the house voice — short enough to read mid-dodge, and no
#     empty rows (an empty row makes `line_for` return "" and the bark silently
#     never appears);
#   * every event has a MOOD, or its gibberish falls back to neutral chatter and
#     a death line gets delivered as small talk;
#   * exactly ONE bubble per speaker, reused — a second would render two lines on
#     top of each other;
#   * the per-speaker cooldown holds, or a kill chain papers the screen;
#   * unknown events are SILENT, never a placeholder string on screen;
#   * with no Sfx autoload present (every headless context) the whole thing is a
#     no-op rather than a crash — the `--script` autoload trap this repo has been
#     bitten by repeatedly.
extends SceneTree

# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion
# sentinel as its last line, so a test aborted by a dead property read fails BY
# ABSENCE instead of reading as "zero failures".

const TESTS: Array[String] = [
	"lines_obey_the_house_voice",
	"every_event_has_a_mood",
	"picker_is_deterministic",
	"unknown_event_is_silent",
	"say_never_blocks",
	"one_bubble_per_speaker",
	"cooldown_holds",
	"say_refuses_bad_speakers",
	"voice_only_is_safe_without_sfx",
	"director_installs_once",
	"director_survives_an_empty_world",
]

var _fails: int = 0
var _completed: Dictionary = {}

## The house rule for a bark, from Bark.gd's header: five words or fewer, ideally
## three. Enforced because it is the difference between a line you absorb
## peripherally and a line you have to stop and read.
const MAX_WORDS: int = 5
const MAX_CHARS: int = 40


func _init() -> void:
	# Table-only checks first: they need nothing but the scripts.
	_test_lines_obey_the_house_voice()
	_test_every_event_has_a_mood()
	_test_picker_is_deterministic()
	_test_director_installs_once()
	# Everything below needs a LIVE speaker. Nodes added during a SceneTree
	# script's _init are not yet "inside the tree" — and `Bark.say` refuses a
	# detached speaker on purpose (its bubble would have no viewport). One idle
	# frame and the tree is real, which is also the only way to exercise the code
	# path that actually ships.
	await process_frame
	await _test_unknown_event_is_silent()
	await _test_say_never_blocks()
	await _test_one_bubble_per_speaker()
	await _test_cooldown_holds()
	await _test_say_refuses_bad_speakers()
	await _test_voice_only_is_safe_without_sfx()
	_test_director_survives_an_empty_world()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Bark tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Bark tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## SpeechBubble.say() is a coroutine that yields several frames while it
## shrink-to-fits. Freeing the speaker before those frames elapse leaves the
## coroutine holding a freed label. Two idle frames settle it — which is also a
## fair check that nothing in the bubble path errors when it resumes.
func _settle() -> void:
	await process_frame
	await process_frame


func _speaker() -> Node2D:
	var n := Node2D.new()
	n.name = "Speaker%d" % randi()
	root.add_child(n)
	return n


# ---------------------------------------------------------------------------
# The lines
# ---------------------------------------------------------------------------

func _test_lines_obey_the_house_voice() -> void:
	_expect(not Bark.LINES.is_empty(), "there are barks at all")
	for event: StringName in Bark.LINES:
		var row: Array = Bark.LINES[event]
		# An empty row makes line_for return "" and the bark silently never fires
		# — indistinguishable in play from "the hook is not wired up".
		_expect(not row.is_empty(), "'%s' has at least one line" % event)
		_expect(row.size() >= 2 or event in [&"run_start"],
			"'%s' has enough lines not to repeat instantly (%d)" % [event, row.size()])
		for line: String in row:
			_expect(not line.strip_edges().is_empty(), "'%s' has no blank line" % event)
			var words: int = line.strip_edges().split(" ", false).size()
			_expect(words <= MAX_WORDS,
				"'%s': \"%s\" is %d words (max %d — nobody reads mid-dodge)"
					% [event, line, words, MAX_WORDS])
			_expect(line.length() <= MAX_CHARS,
				"'%s': \"%s\" is %d chars (max %d)" % [event, line, line.length(), MAX_CHARS])
			# No instructions: telling the player what to do is the HUD's job, and
			# a bark that does it reads as a tutorial popup. Matched on the
			# opening word plus UI nouns rather than on "press" anywhere in the
			# string — "the hand pressed harder" is flavour, not a prompt.
			var low: String = line.to_lower()
			for verb: String in ["press ", "tap ", "hold ", "swipe ", "use the "]:
				_expect(not low.begins_with(verb),
					"'%s': \"%s\" does not open with an instruction" % [event, line])
			for noun: String in ["button", "joystick", "the screen"]:
				_expect(not low.contains(noun),
					"'%s': \"%s\" names no UI furniture" % [event, line])
	_expect(Bark.events().size() == Bark.LINES.size(), "events() reports the whole table")
	# A bark is punctuation. If it lingers longer than its own cooldown, two
	# speakers' bubbles start overlapping in time.
	_expect(Bark.HOLD < Bark.COOLDOWN, "a line is gone before the same mouth may reopen")
	_completes("lines_obey_the_house_voice")


func _test_every_event_has_a_mood() -> void:
	for event: StringName in Bark.LINES:
		_expect(Bark.MOODS.has(event),
			"'%s' declares a gibberish mood (else a death line is small talk)" % event)
		var mood: int = Bark.mood_for(event)
		_expect(Gibberish.MOOD_SHAPE.has(mood), "'%s' names a real Gibberish mood" % event)
	for event: StringName in Bark.MOODS:
		_expect(Bark.LINES.has(event), "mood table has no orphan event '%s'" % event)
	_completes("every_event_has_a_mood")


func _test_picker_is_deterministic() -> void:
	for event: StringName in Bark.LINES:
		var row: Array = Bark.LINES[event]
		for i in row.size():
			_expect(Bark.line_for(event, i) == String(row[i]),
				"line_for('%s', %d) is that row" % [event, i])
		# The roll wraps rather than going out of bounds — a caller passing a
		# kill count or a floor number must not crash the bark system.
		_expect(Bark.line_for(event, row.size() + 3) == String(row[3 % row.size()]),
			"'%s' wraps an out-of-range roll" % event)
	_completes("picker_is_deterministic")


func _test_unknown_event_is_silent() -> void:
	_expect(Bark.line_for(&"no_such_event_ever", 0) == "",
		"an unknown event resolves to silence, not to a placeholder on screen")
	var who: Node2D = _speaker()
	_expect(Bark.say(who, &"no_such_event_ever", true) == false, "and nothing is said")
	_expect(who.get_node_or_null(NodePath(String(Bark.BUBBLE_NAME))) == null,
		"and no bubble is built for it")
	await _settle()
	who.free()
	_completes("unknown_event_is_silent")


# ---------------------------------------------------------------------------
# Speaking
# ---------------------------------------------------------------------------

func _test_say_never_blocks() -> void:
	# THE SPEC'S HARD RULE. `SpeechBubble.say` yields several frames while it
	# shrink-to-fits; if Bark ever awaits it, every call site silently becomes a
	# coroutine and a bark can delay a cast. A coroutine call returns a
	# GDScriptFunctionState-ish object, not a bool — so this asserts the type.
	var who: Node2D = _speaker()
	var result: Variant = Bark.say(who, &"floor_enter", true, 0)
	_expect(typeof(result) == TYPE_BOOL,
		"say() returns a plain bool synchronously (got %s)" % type_string(typeof(result)))
	_expect(bool(result), "an `always` bark actually fires")
	await _settle()
	who.free()
	_completes("say_never_blocks")


func _test_one_bubble_per_speaker() -> void:
	var who: Node2D = _speaker()
	_expect(Bark.say(who, &"floor_enter", true, 0), "first line lands")
	var bubble: Node = who.get_node_or_null(NodePath(String(Bark.BUBBLE_NAME)))
	_expect(bubble != null, "a bubble was parented to the speaker")
	_expect(bubble is Node2D, "the bubble is the world-space SpeechBubble")
	_expect(bubble.has_method(&"say"), "it is really SpeechBubble (it answers say())")
	# Reuse, not re-create: a second bubble would render two lines on top of each
	# other and neither would be readable.
	who.set_meta(&"bark_last", -999.0)      # step past the cooldown deliberately
	_expect(Bark.say(who, &"floor_clear", true, 0), "second line lands")
	var bubbles: int = 0
	for c: Node in who.get_children():
		if String(c.name) == String(Bark.BUBBLE_NAME):
			bubbles += 1
	_expect(bubbles == 1, "still exactly one bubble on the speaker (got %d)" % bubbles)
	await _settle()
	who.free()
	_completes("one_bubble_per_speaker")


func _test_cooldown_holds() -> void:
	var who: Node2D = _speaker()
	_expect(Bark.say(who, &"streak", true, 0), "the first bark of a chain lands")
	# Everything after it inside the window is refused — without this a kill
	# chain papers the screen with chalk.
	var extra: int = 0
	for i in 8:
		if Bark.say(who, &"streak", true, i):
			extra += 1
	_expect(extra == 0, "a chain of kills does not stack bubbles (got %d extra)" % extra)
	_expect(Bark.COOLDOWN > 0.0, "there is a cooldown at all")
	await _settle()
	who.free()
	_completes("cooldown_holds")


func _test_say_refuses_bad_speakers() -> void:
	_expect(Bark.say(null, &"floor_enter", true) == false, "a null speaker says nothing")
	# A Control speaker would put a world-space bubble into a UI layer, where its
	# position maths is meaningless — refuse rather than render it somewhere odd.
	var ui := Control.new()
	root.add_child(ui)
	_expect(Bark.say(ui, &"floor_enter", true) == false, "a Control speaker is refused")
	ui.free()
	# Not in the tree: the bubble would have no viewport and no camera to clamp to.
	var loose := Node2D.new()
	_expect(Bark.say(loose, &"floor_enter", true) == false, "a detached speaker is refused")
	loose.free()
	await _settle()
	_completes("say_refuses_bad_speakers")


func _test_voice_only_is_safe_without_sfx() -> void:
	# Bark reaches Sfx through a TREE lookup, never the bare `Sfx` identifier:
	# naming an autoload inside a STATIC function is a compile error that
	# surfaces as an unrelated missing method — the trap this repo keeps
	# rediscovering. This must hold in BOTH worlds, and a --script run visits
	# both: root is empty during `_init`, and the autoloads have landed by the
	# time the first idle frame elapses. So the assertions below are written to
	# pass either way, and the call is exercised twice.
	var who: Node2D = _speaker()
	var sfx_present: bool = root.get_node_or_null(^"Sfx") != null
	print("NOTE: Sfx autoload %s in this --script context" %
		("IS present" if sfx_present else "is absent"))
	Bark.voice_only(who, Gibberish.Mood.HURT, 2)
	Bark.voice_only(null, Gibberish.Mood.HURT)
	_expect(true, "voice_only with no Sfx present is a no-op, not a crash")
	# And a full bark, which also reaches for Sfx, must survive the same absence.
	_expect(Bark.say(who, &"low_health", true, 0), "a bark still shows its line with no audio")
	await _settle()
	who.free()
	_completes("voice_only_is_safe_without_sfx")


# ---------------------------------------------------------------------------
# The observer
# ---------------------------------------------------------------------------

func _test_director_installs_once() -> void:
	# It behaves like an autoload without being registered in project.godot (that
	# file belongs to another agent this session). Idempotence is therefore the
	# whole contract: two entry points call ensure(), and a second director would
	# double every bark and every death cry.
	var a: Node = VoiceDirector.ensure(self)
	_expect(a != null, "ensure() builds a director")
	var b: Node = VoiceDirector.ensure(self)
	_expect(a == b, "ensure() is idempotent even before the deferred add lands")
	_expect(String(a.name) == String(VoiceDirector.NODE_NAME), "it takes the agreed name")
	_expect(VoiceDirector.ensure(null) == null, "no tree, no director, no crash")
	_completes("director_installs_once")


func _test_director_survives_an_empty_world() -> void:
	# Its whole job is reading a world that may not be there: no arena, no hero,
	# no Hype, no GameState. Every one of those is duck-typed on purpose so a
	# concurrent rename in another agent's file costs silence, never a crash.
	var d: Node = VoiceDirector.ensure(self)
	_expect(d != null, "director available")
	for i in 4:
		d.call(&"_rescan")
		d.call(&"_poll_streak")
		d.call(&"_watch_health")
	_expect(true, "scanning an empty world is a no-op")
	# And the floor-transition reset, which clears every cached node.
	d.call(&"_reset_for_new_floor")
	_expect(true, "a floor transition with nothing built is a no-op")
	_completes("director_survives_an_empty_world")
