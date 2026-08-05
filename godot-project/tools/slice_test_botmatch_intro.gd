# Run: godot --headless --path godot-project --script tools/slice_test_botmatch_intro.gd
#
# THE PRE-FIGHT CARD, THE TWO CORNERS, AND THE TAUNT BOOK — the three things that turn
# a bot match from a physics demo into something worth recording, asserted without
# standing up the scene they live in.
#
# What it covers:
#   * the intro is BOUNDED and SKIPPABLE — a ceremony that a sim cannot turn off is a
#     tax on every headless bout, and one that runs under `--headless` is ~2 s of
#     staring at a card the dummy renderer never drew;
#   * the two side colours are DISTINCT and are the SAME SOURCE the plates read — the
#     whole point of `SIDE_COLORS` is that the card cannot promise a yellow fighter
#     while the stage draws a blue one;
#   * `TauntBook` has lines for every DECLARED beat, `line_for` is deterministic under
#     a pinned roll, and no row is unreachable;
#   * the Lobby can actually route to the duel, and clears the statics that would
#     otherwise hand it a showcase or a free-play stage.
#
# ⚠ THE `failed += _test_x()` IDIOM IS BANNED IN THIS FILE, and the reason is written
# up at length in `tools/slice_test_loadout.gd`: reading a member that has moved is not
# a test failure in GDScript, it ABORTS the enclosing function and hands the caller the
# return type's zero — which that idiom reads as "no failures". It silently disabled 64
# suites once. So, exactly as that file does it:
#
#   1. failures accumulate on the MEMBER `_fails`, never on a return value;
#   2. every test's last line records a COMPLETION SENTINEL, so a test that aborts
#      half-way fails the suite BY ABSENCE, whatever the cause;
#   3. `quit(1)` and `quit(0)` are mutually exclusive branches — never both.
extends SceneTree

const MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"
const LOBBY_SCRIPT: String = "res://scripts/ui/Lobby.gd"
const LOBBY_SCENE: String = "res://scenes/ui/Lobby.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"

## Every test that must run to completion. A name missing from `_completed` at the end
## means that test aborted part-way and the suite fails.
const TESTS: Array[String] = [
	"intro_is_bounded", "intro_skips_headless", "corner_colours",
	"plates_read_the_corner", "taunt_beats_are_complete", "taunt_line_is_deterministic",
	"taunt_rows_are_plural", "no_unreachable_beat", "taunt_voice_is_shaped",
	"taunts_have_no_drawing_references", "taunts_answer_the_opponent",
	"lobby_routes_to_the_duel", "lobby_clears_the_statics", "lobby_opponent_is_never_a_mirror",
	"live_match_is_not_slowed", "live_bodies_wear_the_corner",
]

const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"

## BotMatch members this suite reaches DYNAMICALLY (it is loaded by PATH, never as the
## `BotMatch` identifier — naming it here would compile its whole autoload-touching
## dependency chain at this script's parse time). Listed once so a relocation is named
## rather than merely detected.
const MATCH_MEMBERS: Array[String] = ["intro_seconds", "taunts"]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _match: GDScript = null
var _lobby_src: String = ""


## The two live tests share ONE instantiated match — standing the versus stage up twice
## would double the slowest part of this suite for no extra coverage.
var _live: Node = null


## ⚠ THE BODY IS A COROUTINE AND `_process` ONLY KICKS IT OFF. The two live tests have
## to let a real match TICK, and `_process` must keep returning `false` for the main
## loop to deliver those frames — so it cannot be the thing that awaits. `_run_all`
## owns the quit instead, exactly the shape `tools/botmatch_sim.gd` uses.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_all()
	return false


func _run_all() -> void:
	_match = load(MATCH_SCRIPT) as GDScript
	_expect(_match != null, "BotMatch.gd loads")
	var f: FileAccess = FileAccess.open(LOBBY_SCRIPT, FileAccess.READ)
	if f != null:
		_lobby_src = _code_only(f.get_as_text())
		f.close()
	_expect(_lobby_src != "", "Lobby.gd is readable as source")

	_test_intro_is_bounded()
	_test_intro_skips_headless()
	_test_corner_colours()
	_test_plates_read_the_corner()
	_test_taunt_beats_are_complete()
	_test_taunt_line_is_deterministic()
	_test_taunt_rows_are_plural()
	_test_no_unreachable_beat()
	_test_taunt_voice_is_shaped()
	_test_taunts_have_no_drawing_references()
	_test_taunts_answer_the_opponent()
	_test_lobby_routes_to_the_duel()
	_test_lobby_clears_the_statics()
	_test_lobby_opponent_is_never_a_mirror()
	await _test_live_match()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("BotMatch intro tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("BotMatch intro tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## ⚠ SOURCE ASSERTIONS MUST READ CODE, NOT PROSE. Both of the files this suite
## inspects DOCUMENT the thing they no longer do ("it used to read
## `ClassInfo.color_for`...", "never as a bare `VersusArena` identifier"), because that
## is how this project explains itself — so a naive `src.contains(...)` matches the
## warning against the mistake and fails on a correct file. This strips comments,
## quote-aware, so what is left is what the engine actually executes.
func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in src.split("\n"):
		var quote: String = ""
		var cut: int = -1
		for i: int in line.length():
			var c: String = line[i]
			if quote != "":
				if c == quote:
					quote = ""
			elif c == "\"" or c == "'":
				quote = c
			elif c == "#":
				cut = i
				break
		out.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(out)


## ...and for the ONE assertion that hunts a bare identifier, string literals have to go
## too: `const VERSUS_SCRIPT := "res://scripts/combat/VersusArena.gd"` is the CORRECT
## by-path form and contains the very identifier the check is trying to forbid.
## Contents are blanked rather than the quotes removed, so nothing on either side of a
## string accidentally joins into a new token.
func _strip_quoted(code: String) -> String:
	var out: String = ""
	var quote: String = ""
	for i: int in code.length():
		var c: String = code[i]
		if quote != "":
			if c == quote:
				quote = ""
				out += c
			continue
		if c == "\"" or c == "'":
			quote = c
		out += c
	return out


## The statics really are declared, by name. The completion sentinel catches a
## relocation; this says WHICH one relocated.
func _require_statics(script: GDScript, names: Array[String]) -> void:
	if script == null:
		_expect(false, "BotMatch.gd exists (cannot check its statics)")
		return
	var present: Dictionary = {}
	for p: Dictionary in script.get_property_list():
		present[String(p["name"])] = true
	for n: String in names:
		_expect(present.has(n),
			"BotMatch still declares `%s` (moved or renamed — the tool knob is dead)" % n)


# ==========================================================================
# THE CARD
# ==========================================================================

## A ceremony has to be SHORT and it has to be a KNOB. `tools/botmatch_sim.gd` runs
## this scene over many pairings and `tools/directed_clip_capture.gd` films it; a card
## that could not be turned off would be charged to every bout of both.
func _test_intro_is_bounded() -> void:
	_require_statics(_match, MATCH_MEMBERS)
	if _match == null:
		return   # deliberately NOT completed: the missing sentinel fails the suite
	var secs: float = float(_match.get("intro_seconds"))
	# A lower bound too: an "intro" of 0.2 s is a flicker nobody can read, and it would
	# pass a naive "is it small" check while failing the feature.
	_expect(secs >= 0.8, "the card holds long enough to read (got %.2fs)" % secs)
	# ⚠ 3.0 -> 4.0 ON THE MAKER'S ASK: *"before the fight starts I need some time to
	# show x vs z on the screen as the stick figures stand there like a couple
	# seconds"*. The ceiling is still here and still means what it meant — the card
	# must not become a cutscene the sweep tools pay for on every bout — it is just no
	# longer tighter than the couple of seconds that were asked for. At 3.2 s, minus a
	# 0.28 s fade each end and the 0.45 s FIGHT beat, the readable hold is ~2.2 s.
	_expect(secs <= 4.0, "...and is not a cutscene (got %.2fs)" % secs)
	# SKIPPABLE. A tool sets this to 0 and the card is gone whole.
	_match.set("intro_seconds", 0.0)
	_expect(is_zero_approx(float(_match.get("intro_seconds"))),
		"intro_seconds is settable to 0 — a capture tool can skip the card")
	_match.set("intro_seconds", secs)
	_expect(is_equal_approx(float(_match.get("intro_seconds")), secs),
		"...and restorable (statics on a GDScript round-trip through get/set)")
	# The taunt switch is the same shape, for the same reason.
	var was: bool = bool(_match.get("taunts"))
	_match.set("taunts", false)
	_expect(not bool(_match.get("taunts")), "taunts can be turned off by a tool")
	_match.set("taunts", was)
	# The FIGHT beat has to fit inside a clip's tail (`directed_clip_capture --tail`
	# defaults to 1.8 s) or the word is still fading when the recording stops.
	var beat: float = float(_match.get("INTRO_FIGHT_BEAT"))
	_expect(beat > 0.0 and beat <= 1.0,
		"the FIGHT beat is a beat, not a scene (got %.2fs)" % beat)
	_completes("intro_is_bounded")


## NO DISPLAY, NO CEREMONY. This suite and every other one runs under `--headless`,
## where the dummy renderer draws nothing and reports success — so a card that did not
## check would cost every headless bout its full hold for a picture nobody can see.
##
## Asserted through the real predicate rather than by re-deriving it here, so the test
## fails if the check is deleted rather than if a copy of it drifts.
func _test_intro_skips_headless() -> void:
	if _match == null:
		return
	_expect(DisplayServer.get_name() == "headless",
		"this suite really is running headless (otherwise the next line proves nothing)")
	_expect(not bool(_match.call("_ceremony")),
		"_ceremony() is FALSE with no display — the card and the taunts are skipped")
	_completes("intro_skips_headless")


# ==========================================================================
# YELLOW vs BLUE
# ==========================================================================

## The two corners must be TELLABLE APART on a phone screen at a distance, which is
## the whole ask ("an intro screen like yellow vs blue"). Distinctness is asserted as a
## real perceptual gap, not as `a != b` — two nearly-identical colours would satisfy
## inequality and fail the feature.
func _test_corner_colours() -> void:
	if _match == null:
		return
	var left: Color = _match.call("side_color", 0)
	var right: Color = _match.call("side_color", 1)
	var gap: float = absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b)
	_expect(gap >= 0.9, "the two corners are far apart in colour (channel gap %.2f)" % gap)
	# Yellow on the left: red and green high, blue low.
	_expect(left.r > 0.7 and left.g > 0.6 and left.b < 0.45,
		"the LEFT corner is yellow (got %s)" % left)
	# Blue on the right: blue dominant over red.
	_expect(right.b > 0.7 and right.b - right.r > 0.4,
		"the RIGHT corner is blue (got %s)" % right)
	# Both are opaque — a translucent tint on a rig reads as a ghost, and `Hero` already
	# uses alpha for exactly that (GHOST_COLOR).
	_expect(is_equal_approx(left.a, 1.0) and is_equal_approx(right.a, 1.0),
		"both corners are fully opaque")
	# Anything that is not a corner falls back rather than erroring — a draw has no side.
	var none: Color = _match.call("side_color", -1)
	_expect(none != left and none != right, "a non-side falls back to neither corner")
	_completes("corner_colours")


## ONE SOURCE, OR THE CARD LIES. The plates used to be painted from
## `ClassInfo.color_for()` while the bodies are now forced to the side colour — that is
## exactly the disagreement `SIDE_COLORS` exists to make impossible, so this asserts
## the plate path reads `side_color` and no longer reads the class palette.
func _test_plates_read_the_corner() -> void:
	var f: FileAccess = FileAccess.open(MATCH_SCRIPT, FileAccess.READ)
	if f == null:
		_expect(false, "BotMatch.gd is readable as source")
		return
	var src: String = _code_only(f.get_as_text())
	f.close()
	var paint_at: int = src.find("func _paint_hud")
	_expect(paint_at >= 0, "BotMatch still has a _paint_hud")
	if paint_at < 0:
		return
	var paint: String = src.substr(paint_at, 1400)
	_expect(paint.contains("side_color(side)"),
		"the name plate is painted from side_color(side) — the same source as the card")
	_expect(not paint.contains("ClassInfo.color_for"),
		"...and NOT from the class palette, which would disagree with the body")
	# The rig really is retinted, and from the same function.
	_expect(src.contains("set_tint") and src.contains("side_color(side)"),
		"the fighters' rigs are tinted from side_color too")
	_expect(src.contains("func _paint_corners"),
		"the retint lives in its own named step (_paint_corners)")
	_completes("plates_read_the_corner")


# ==========================================================================
# THE TAUNT BOOK
# ==========================================================================

## Every DECLARED beat can be spoken. A beat with no row would produce silence at a
## moment the fight was written around, and `line_for` returns "" for it — a failure
## that is invisible in a recording and impossible to notice in a sim.
func _test_taunt_beats_are_complete() -> void:
	var beats: Array = TauntBook.beats()
	_expect(beats.size() >= 5, "there are at least the five declared beats (got %d)" % beats.size())
	# The five the match actually fires. Named literally, so removing a beat from the
	# book without removing its call site fails HERE rather than in a recording.
	const REQUIRED: Array[StringName] = [
		&"fight_start", &"first_blood", &"big_hit", &"low_health", &"finisher",
	]
	for b: StringName in REQUIRED:
		_expect(beats.has(b), "the book declares the `%s` beat" % b)
		_expect(TauntBook.line_for(b, 0) != "", "`%s` has at least one line" % b)
	_completes("taunt_beats_are_complete")


## ⚠ THE MAKER'S RULING, AS A SWEEP RATHER THAN A COMMENT. *"no drawing references
## please as they make no sense"* — every line in this book used to be about paper
## ("pencils up", "you're a doodle", "mostly eraser now"). That register belongs to
## `Bark`, which speaks for a hero inside a page; a duel is two fighters in a ring and
## neither of them is a drawing.
##
## A ruling like this decays the moment somebody adds "one more good line", so the
## banned vocabulary lives in the book as DATA and this walks every row of both tables
## against it. `all_lines()` is derived, never hand-listed — a hand-listed copy is
## exactly how a new row escapes the check that exists to police it.
func _test_taunts_have_no_drawing_references() -> void:
	var lines: Array[String] = TauntBook.all_lines()
	_expect(lines.size() >= 25, "the book still has a real number of lines (got %d)" % lines.size())
	for line: String in lines:
		var low: String = line.to_lower()
		for banned: String in TauntBook.BANNED_WORDS:
			# Word-ish containment: the banned list is deliberately whole words a taunt
			# would use, and substring matching would fail "decline" on "line".
			var padded: String = " %s " % low.replace(".", " ").replace(",", " ")
			_expect(not padded.contains(" %s " % banned),
				"taunt `%s` does not reach for the drawing metaphor (`%s`)" % [line, banned])
	_completes("taunts_have_no_drawing_references")


## ⚠ AND THEY ANSWER WHO IS OPPOSITE. Maker: *"make the bots text chats interact with
## each other based on who they are fighting"*. Two claims, and the second is the one
## that would rot silently:
##   1. a beat WITH a per-class row returns that row for every one of the nine classes;
##   2. a beat WITHOUT one still speaks, out of the generic table.
## (2) is not padding — `VS_LINES` covers two of five beats on purpose, so a picker
## that returned "" for the other three would mute `low_health` and `finisher`, the two
## beats a recording most needs, and nothing else in the suite would notice.
func _test_taunts_answer_the_opponent() -> void:
	const CLASS_COUNT: int = 9
	for beat: StringName in TauntBook.beats():
		var personal: bool = TauntBook.has_vs_line(beat, 0)
		for cid: int in CLASS_COUNT:
			var line: String = TauntBook.line_for(beat, 0, cid)
			_expect(line != "", "`%s` speaks when facing class %d" % [beat, cid])
			if personal:
				_expect(TauntBook.has_vs_line(beat, cid),
					"`%s` has a line about class %d, not just about some of them" % [beat, cid])
	# The two loud beats are the personal ones, and a fighter facing class 3 must not
	# be handed class 4's line — pinned by roll so this is an identity, not a sample.
	_expect(TauntBook.line_for(&"big_hit", 0, 3) != TauntBook.line_for(&"big_hit", 0, 4),
		"two different opponents draw two different lines")
	_expect(TauntBook.line_for(&"low_health", 0, 3) == TauntBook.line_for(&"low_health", 0, 4),
		"...and a beat with no per-class row falls back to the shared one")
	_completes("taunts_answer_the_opponent")


## Deterministic under a pinned roll, random under -1 — the same contract
## `Bark.line_for` offers, so the two pickers cannot drift into behaving differently.
func _test_taunt_line_is_deterministic() -> void:
	for b: StringName in TauntBook.beats():
		var n: int = TauntBook.count_for(b)
		_expect(n > 0, "`%s` has a non-empty row" % b)
		if n <= 0:
			continue
		for roll: int in n:
			var a: String = TauntBook.line_for(b, roll)
			var again: String = TauntBook.line_for(b, roll)
			_expect(a == again, "`%s` roll %d is stable ('%s' vs '%s')" % [b, roll, a, again])
			_expect(a != "", "`%s` roll %d is not empty" % [b, roll])
		# The roll wraps rather than erroring, which is what lets a caller pass a raw
		# counter without knowing how many lines a beat has.
		_expect(TauntBook.line_for(b, n) == TauntBook.line_for(b, 0),
			"`%s` wraps its roll modulo the row size" % b)
	# An unknown beat is SILENT, never a placeholder string over a fighter's head.
	_expect(TauntBook.line_for(&"no_such_beat", 0) == "",
		"an unknown beat says nothing at all")
	_completes("taunt_line_is_deterministic")


## A beat with ONE line stops being a taunt the second time you watch a match — and
## this mode's whole product is somebody watching a lot of matches in a row.
##
## Also pins the house voice rules `Bark` sets out: five words or fewer.
func _test_taunt_rows_are_plural() -> void:
	for b: StringName in TauntBook.beats():
		var n: int = TauntBook.count_for(b)
		_expect(n >= 3, "`%s` has at least three lines to choose from (got %d)" % [b, n])
		for roll: int in n:
			var line: String = TauntBook.line_for(b, roll)
			var words: int = line.split(" ", false).size()
			_expect(words <= 5, "`%s`/%d is five words or fewer ('%s')" % [b, roll, line])
			_expect(line.length() <= 40, "`%s`/%d is short enough to read mid-fight" % [b, roll])
	_completes("taunt_rows_are_plural")


## NO ROW NOBODY CAN REACH. `BEATS` is the contract and `LINES` is the content; a key
## in one and not the other is either a silent beat or a set of lines that will never
## be spoken, and both are the kind of thing that survives review forever.
func _test_no_unreachable_beat() -> void:
	var declared: Dictionary = {}
	for b: StringName in TauntBook.beats():
		declared[b] = true
	for key: Variant in TauntBook.LINES.keys():
		_expect(declared.has(key),
			"`%s` has lines but is not in BEATS — nothing can ever say it" % key)
	for b: StringName in TauntBook.beats():
		_expect(TauntBook.LINES.has(b),
			"`%s` is declared in BEATS but has no lines — the beat is silent" % b)
	_completes("no_unreachable_beat")


## The mouth agrees with the words. A dying line delivered in a cheerful chirp reads as
## broken rather than as a bug — `Bark` makes the same promise with its own MOODS table.
func _test_taunt_voice_is_shaped() -> void:
	for b: StringName in TauntBook.beats():
		var mood: int = TauntBook.mood_for(b)
		_expect(mood >= 0 and mood < Gibberish.Mood.size(),
			"`%s` maps to a real Gibberish mood (got %d)" % [b, mood])
	# The one beat that is not swagger is the one that must not sound like it.
	_expect(TauntBook.mood_for(&"low_health") == Gibberish.Mood.HURT,
		"the low-health line is spoken HURT, not shouted")
	_expect(TauntBook.mood_for(&"finisher") == Gibberish.Mood.SHOUT,
		"the winning line is the loudest thing in the clip")
	# An unmapped beat falls back rather than erroring.
	_expect(TauntBook.mood_for(&"no_such_beat") == Gibberish.Mood.TALK,
		"an unknown beat falls back to TALK")
	_completes("taunt_voice_is_shaped")


# ==========================================================================
# THE LOBBY ROUTE
# ==========================================================================

## THE BUTTON EXISTS, IN THE ROW THAT ALREADY EXISTED. A complete human-vs-bot duel
## shipped inside `VersusArena` with no route from the title screen at all; this is the
## assertion that it is reachable, and that reaching it did not cost a ROW (the column
## measures ~306 of 360 px — `slice_test_shell` pins that, and a fourth row breaks it).
func _test_lobby_routes_to_the_duel() -> void:
	if _lobby_src == "":
		return
	# ⚠ MOVED INTO THE ANTECHAMBER on 2026-08-04. Maker, twice: "the tower intro
	# still has too many buttons". The room owns these now — the RING is free play,
	# the RACK is the armoury, the STATUE is class. `slice_test_town` asserts the
	# stations exist there; asserting them HERE would re-pin the duplication that
	# was the complaint.
	_expect(not _lobby_src.contains("Fight a Bot"),
		"the duel button is NOT on the title any more (it belongs to the room)")
	_expect(_lobby_src.contains("func _fight_bot"), "...wired to _fight_bot")
	_expect(_lobby_src.contains("func versus_available"),
		"...guarded by versus_available(), mirroring free_play_available/bot_match_available")
	# BY PATH, never as a bare identifier — the trap the other two buttons document.
	_expect(_lobby_src.contains("res://scripts/combat/VersusArena.gd"),
		"the duel is reached by PATH")
	_expect(not _strip_quoted(_lobby_src).contains("VersusArena"),
		"...and never as a bare `VersusArena` identifier (that drags its chain into boot)")
	# Same rule for the other two by-path buttons, so this stays true of the whole file.
	_expect(not _strip_quoted(_lobby_src).contains("BotMatch"),
		"nor a bare `BotMatch` identifier")
	_expect(not _strip_quoted(_lobby_src).contains("FreePlay"),
		"nor a bare `FreePlay` identifier")
	# ⚠ THE PREP ROW IS GONE. It held Free Play / Fight a Bot / Loadout, and all
	# three moved into the Antechamber (ring / ring / rack) when the maker asked twice
	# for fewer buttons on the title. What is asserted instead is that the row did not
	# quietly come back — a re-added button here is the regression, not a missing one.
	_expect(_lobby_src.find("var prep := HBoxContainer.new()") < 0,
		"the title has no prep row — those verbs live in the room now")
	_expect(_lobby_src.find("var coop := HBoxContainer.new()") >= 0,
		"...and the multiplayer row is still there, because that IS a title question")
	# The scene really is there to route to.
	_expect(ResourceLoader.exists(ARENA_SCRIPT), "the versus arena script is in this build")
	_completes("lobby_routes_to_the_duel")


## ⚠ THE STATICS ARE THE WHOLE BUG. `VersusArena._is_duel()` is "not a showcase", so a
## duel entered after a bot match (`showcase_a/b` set) or after free play (`free_play`
## true) is silently NOT A DUEL — you get two bots and no player, or an empty sandbox.
## Both failures land two scenes away from their cause.
func _test_lobby_clears_the_statics() -> void:
	if _lobby_src == "":
		return
	var at: int = _lobby_src.find("func _fight_bot")
	_expect(at >= 0, "the lobby has a _fight_bot")
	if at < 0:
		return
	var body: String = _lobby_src.substr(at, 1600)
	_expect(body.contains("\"showcase_a\", -1"), "_fight_bot clears showcase_a")
	_expect(body.contains("\"showcase_b\", -1"), "_fight_bot clears showcase_b")
	_expect(body.contains("\"free_play\", false"), "_fight_bot clears free_play")
	_expect(body.contains("\"duel_bot_class\""), "_fight_bot sets the bot's class")
	_expect(body.contains("\"duel_difficulty\""), "_fight_bot sets the tier")
	_expect(body.contains("selected_class"), "_fight_bot records the player's class")
	_expect(body.contains("get_node_or_null(\"/root/GameState\")"),
		"...through the guarded tree lookup, never the bare GameState identifier")
	_completes("lobby_clears_the_statics")


## THE DEFAULT MATCHUP IS NEVER A MIRROR. Walking into your own class by accident is
## the one pairing nobody wants, and `BotMatch._cycle_a` already refuses it for the same
## reason. Asserted against the LIVE lobby, over every class, not against the source.
func _test_lobby_opponent_is_never_a_mirror() -> void:
	var scene: PackedScene = load(LOBBY_SCENE) as PackedScene
	if scene == null:
		_expect(false, "the Lobby scene loads")
		return
	var lobby: Node = scene.instantiate()
	root.add_child(lobby)
	var n: int = ClassInfo.count()
	_expect(n > 1, "there is more than one class to pick from")
	var seen: Dictionary = {}
	for cls: int in n:
		lobby.set("_selected_class", cls)
		var bot: int = int(lobby.call("duel_opponent"))
		_expect(bot >= 0 and bot < n, "class %d gets a real opponent (got %d)" % [cls, bot])
		_expect(bot != cls, "class %d is not handed a mirror of itself" % cls)
		seen[bot] = true
	# An invariant that is trivially true of an empty result is not an invariant: this
	# only means anything because the loop above ran n times and recorded n answers.
	_expect(seen.size() >= 1, "the sweep actually produced opponents (%d distinct)" % seen.size())
	var tier: int = int(lobby.call("duel_tier"))
	_expect(tier >= 0 and tier <= 3, "the duel tier is sanitised into 0..3 (got %d)" % tier)
	# ...AND THE MAKER'S OWN CHOICE SURVIVES A TRIP BACK TO THE TITLE. The arena's pause
	# menu cycles the bot's class mid-fight; if this screen simply overwrote the static
	# every time, that cycler would be silently pointless. Proven by writing a value the
	# default cannot be confused with and reading it back through the real accessor.
	var arena: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena != null and n > 3:
		var was: Variant = arena.get("duel_bot_class")
		arena.set("duel_bot_class", 3)
		lobby.set("_selected_class", 0)      # not 3, so the mirror guard cannot fire
		_expect(int(lobby.call("duel_opponent")) == 3,
			"the arena's own bot-class knob is PRESERVED, not overwritten by the lobby")
		lobby.set("_selected_class", 3)      # now it IS a mirror, and must be refused
		_expect(int(lobby.call("duel_opponent")) != 3,
			"...except when it would be a mirror of your own pick")
		if was != null:
			arena.set("duel_bot_class", int(was))
	lobby.queue_free()
	_completes("lobby_opponent_is_never_a_mirror")


# ==========================================================================
# THE LIVE MATCH
#
# The two assertions that source-reading cannot make: that a headless bout really does
# start FIGHTING on frame one (the sim's throughput depends on it), and that the two
# bodies really are wearing the corner colours rather than one shared `GameState`
# colourway. Both need a real `BotMatch` on a real stage.
# ==========================================================================

func _test_live_match() -> void:
	var scene: PackedScene = load(MATCH_SCENE) as PackedScene
	if scene == null:
		_expect(false, "the BotMatch scene loads")
		return
	# Ask for the LONGEST sane ceremony. If the headless skip is broken, the assertions
	# below fail loudly instead of the suite merely getting slower by an amount nobody
	# would notice.
	_match.set("intro_seconds", 3.0)
	_match.set("auto_rematch", false)
	_live = scene.instantiate()
	root.add_child(_live)
	# Two frames: one for `_ready` to build the arena, one for `_process` to have run at
	# least once — an intro that paused would have done it by now.
	await process_frame
	await process_frame
	_test_live_match_is_not_slowed()
	_test_live_bodies_wear_the_corner()
	if is_instance_valid(_live):
		_live.free()      # immediate, so `_exit_tree` unpauses before the suite reports
	paused = false
	_match.set("intro_seconds", 1.8)


## NO CEREMONY WITHOUT A DISPLAY. If this ever regresses, `tools/botmatch_sim.gd` pays
## `intro_seconds` per bout across every pairing and `tools/directed_clip_capture.gd`
## films a paused stage until its patience runs out.
func _test_live_match_is_not_slowed() -> void:
	if not is_instance_valid(_live):
		_expect(false, "the match instantiated")
		return
	_expect(int(_live.get("_intro_phase")) == 2,
		"a headless bout opens straight in Intro.DONE — no card, no pause")
	_expect(not paused, "...and the tree is LIVE on the first frames, not held")
	_expect(not bool(_live.call("match_over")), "the bout has not already resolved")
	_completes("live_match_is_not_slowed")


## YELLOW ON THE LEFT, BLUE ON THE RIGHT, ON THE ACTUAL BODIES.
##
## ⚠ THE ORDERING THIS PROVES IS THE WHOLE POINT. `Hero._ready` applies
## `GameState.colourway` — ONE global shared by both fighters — as the last thing it
## does, so a tint written any earlier is silently overwritten and both stickmen come
## out the same colour. Reading `rig.limb_color` back off the live bodies is the only
## honest way to know `_paint_corners` ran late enough.
func _test_live_bodies_wear_the_corner() -> void:
	if not is_instance_valid(_live):
		_expect(false, "the match instantiated")
		return
	var fighters: Variant = _live.get("_fighters")
	if not (fighters is Array):
		_expect(false, "the match exposes its fighters (the member moved)")
		return
	var list: Array = fighters as Array
	_expect(list.size() == 2, "the stage stood up exactly two fighters (got %d)" % list.size())
	if list.size() != 2:
		return   # deliberately NOT completed
	var worn: Array[Color] = []
	for side: int in 2:
		var body: Node = list[side]
		_expect(is_instance_valid(body), "fighter %d is alive" % side)
		if not is_instance_valid(body):
			return
		var rig: Variant = body.get("rig")
		_expect(rig != null, "fighter %d has a rig to tint" % side)
		if rig == null:
			return
		var worn_col: Color = (rig as Object).get("limb_color")
		var want: Color = _match.call("side_color", side)
		_expect(worn_col.is_equal_approx(want),
			"fighter %d wears its corner colour (want %s, got %s)" % [side, want, worn_col])
		worn.append(worn_col)
	# The bug this replaced: BOTH fighters painted from one shared value. Asserting they
	# differ is what makes the two lines above more than a tautology.
	_expect(not worn[0].is_equal_approx(worn[1]),
		"the two fighters are NOT the same colour (the old GameState.colourway bug)")
	_completes("live_bodies_wear_the_corner")
