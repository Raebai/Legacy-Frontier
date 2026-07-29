# godot-project/tools/m11_test_patience.gd
# Run with: godot --headless --path godot-project --script tools/m11_test_patience.gd
# Headless tests for Patience.compute_delta + Levenshtein. Uses lightweight
# RefCounted-extending inner-class stubs so tests don't need Node lifetime
# management. The Patience.compute_delta signature accepts Object precisely
# to enable this.
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
	"levenshtein_basics",
	"levenshtein_edge_cases",
	"levenshtein_distance_window",
	"compute_delta_neutral",
	"compute_delta_insult",
	"compute_delta_compliment",
	"compute_delta_interest",
	"compute_delta_repeat",
	"compute_delta_stacks",
]

var _fails: int = 0
var _completed: Dictionary = {}


# Stand-in for NPCData. Only the fields Patience touches.
class StubData:
	var patience_decay_rate: float = 0.05
	var interest_keywords: Array[String] = []
	var npc_id: String = "test"


# Stand-in for NPC instance. Holds data + short_term.
class StubNpc:
	var data: StubData
	var short_term: Array[Dictionary] = []


func _init() -> void:
	_test_levenshtein_basics()
	_test_levenshtein_edge_cases()
	_test_levenshtein_distance_window()
	_test_compute_delta_neutral()
	_test_compute_delta_insult()
	_test_compute_delta_compliment()
	_test_compute_delta_interest()
	_test_compute_delta_repeat()
	_test_compute_delta_stacks()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("M11 tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("M11 tests: all PASS")
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


func _expect_close(actual: float, expected: float, tol: float, msg: String) -> void:
	if abs(actual - expected) > tol:
		printerr("FAIL: %s — expected %.4f, got %.4f" % [msg, expected, actual])
		_fails += 1


func _make_npc(decay: float = 0.05, interests: Array[String] = [], short_term: Array[Dictionary] = []) -> StubNpc:
	var d: StubData = StubData.new()
	d.patience_decay_rate = decay
	d.interest_keywords = interests
	d.npc_id = "test"
	var n: StubNpc = StubNpc.new()
	n.data = d
	n.short_term = short_term
	return n


func _test_levenshtein_basics() -> void:
	_expect(Patience.levenshtein("kitten", "sitting") == 3, "levenshtein: kitten -> sitting = 3")
	_expect(Patience.levenshtein("flaw", "lawn") == 2, "levenshtein: flaw -> lawn = 2")
	_expect(Patience.levenshtein("abc", "abc") == 0, "levenshtein: identical = 0")
	_expect(Patience.levenshtein("abc", "abd") == 1, "levenshtein: single sub = 1")
	_completes("levenshtein_basics")


func _test_levenshtein_edge_cases() -> void:
	_expect(Patience.levenshtein("", "") == 0, "levenshtein: empty/empty = 0")
	_expect(Patience.levenshtein("", "abc") == 3, "levenshtein: empty/abc = 3")
	_expect(Patience.levenshtein("abc", "") == 3, "levenshtein: abc/empty = 3")
	_expect(Patience.levenshtein("a", "b") == 1, "levenshtein: single-char different = 1")
	_completes("levenshtein_edge_cases")


func _test_levenshtein_distance_window() -> void:
	_expect(Patience.levenshtein("whats your name", "what's your name") == 1, "levenshtein: punctuation-only differs by 1")
	_expect(Patience.levenshtein("how are you", "how are u") == 2, "levenshtein: 'you'/'u' = 2")
	_expect(Patience.levenshtein("hi", "hello there friend") > 5, "levenshtein: very different exceeds window")
	_completes("levenshtein_distance_window")


func _test_compute_delta_neutral() -> void:
	var npc: StubNpc = _make_npc(0.05)
	var delta: float = Patience.compute_delta("just walking by", npc)
	_expect_close(delta, -0.05, 0.001, "delta: neutral text -> -decay_rate")
	_completes("compute_delta_neutral")


func _test_compute_delta_insult() -> void:
	var npc: StubNpc = _make_npc(0.05)
	var delta: float = Patience.compute_delta("you're stupid", npc)
	_expect_close(delta, -0.05 + Patience.INSULT_DELTA, 0.001, "delta: insult -> -decay -0.25")
	_completes("compute_delta_insult")


func _test_compute_delta_compliment() -> void:
	var npc: StubNpc = _make_npc(0.05)
	var delta: float = Patience.compute_delta("thanks for the help", npc)
	_expect_close(delta, -0.05 + Patience.COMPLIMENT_DELTA, 0.001, "delta: compliment -> -decay +0.10")
	_completes("compute_delta_compliment")


func _test_compute_delta_interest() -> void:
	var interests: Array[String] = ["book", "story"]
	var npc: StubNpc = _make_npc(0.05, interests)
	var delta: float = Patience.compute_delta("tell me about books", npc)
	_expect_close(delta, -0.05 + Patience.INTEREST_DELTA, 0.001, "delta: interest match -> -decay +0.05")
	_completes("compute_delta_interest")


func _test_compute_delta_repeat() -> void:
	var interests: Array[String] = []
	var st: Array[Dictionary] = [
		{"role": "user", "content": "what's your name"},
		{"role": "assistant", "content": "Raebai."},
	]
	var npc: StubNpc = _make_npc(0.05, interests, st)
	var delta: float = Patience.compute_delta("whats your name", npc)
	_expect_close(delta, -0.05 + Patience.REPEAT_DELTA, 0.001, "delta: repeat question -> -decay -0.10")
	_completes("compute_delta_repeat")


func _test_compute_delta_stacks() -> void:
	# All four trigger types simultaneously: insult + compliment + interest + repeat.
	# Prior turn identical to current so Levenshtein is 0 (well under window),
	# and the message contains keywords that match all four trigger regexes.
	var interests: Array[String] = ["book"]
	var st: Array[Dictionary] = [
		{"role": "user", "content": "thanks for the lovely book idiot"},
	]
	var npc: StubNpc = _make_npc(0.05, interests, st)
	var delta: float = Patience.compute_delta("thanks for the lovely book idiot", npc)
	var expected: float = -0.05 + Patience.INSULT_DELTA + Patience.COMPLIMENT_DELTA + Patience.INTEREST_DELTA + Patience.REPEAT_DELTA
	_expect_close(delta, expected, 0.001, "delta: all-stack")
	_completes("compute_delta_stacks")
