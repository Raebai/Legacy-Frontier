# godot-project/tools/m11_test_patience.gd
# Run with: godot --headless --path godot-project --script tools/m11_test_patience.gd
# Headless tests for Patience.compute_delta + Levenshtein. Uses lightweight
# RefCounted-extending inner-class stubs so tests don't need Node lifetime
# management. The Patience.compute_delta signature accepts Object precisely
# to enable this.
extends SceneTree


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
	var failed: int = 0
	failed += _test_levenshtein_basics()
	failed += _test_levenshtein_edge_cases()
	failed += _test_levenshtein_distance_window()
	failed += _test_compute_delta_neutral()
	failed += _test_compute_delta_insult()
	failed += _test_compute_delta_compliment()
	failed += _test_compute_delta_interest()
	failed += _test_compute_delta_repeat()
	failed += _test_compute_delta_stacks()
	if failed > 0:
		printerr("M11 tests: %d FAILED" % failed)
		quit(1)
	else:
		print("M11 tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _expect_close(actual: float, expected: float, tol: float, msg: String) -> int:
	if abs(actual - expected) > tol:
		printerr("FAIL: %s — expected %.4f, got %.4f" % [msg, expected, actual])
		return 1
	return 0


func _make_npc(decay: float = 0.05, interests: Array[String] = [], short_term: Array[Dictionary] = []) -> StubNpc:
	var d: StubData = StubData.new()
	d.patience_decay_rate = decay
	d.interest_keywords = interests
	d.npc_id = "test"
	var n: StubNpc = StubNpc.new()
	n.data = d
	n.short_term = short_term
	return n


func _test_levenshtein_basics() -> int:
	var fails: int = 0
	fails += _expect(Patience.levenshtein("kitten", "sitting") == 3, "levenshtein: kitten -> sitting = 3")
	fails += _expect(Patience.levenshtein("flaw", "lawn") == 2, "levenshtein: flaw -> lawn = 2")
	fails += _expect(Patience.levenshtein("abc", "abc") == 0, "levenshtein: identical = 0")
	fails += _expect(Patience.levenshtein("abc", "abd") == 1, "levenshtein: single sub = 1")
	return fails


func _test_levenshtein_edge_cases() -> int:
	var fails: int = 0
	fails += _expect(Patience.levenshtein("", "") == 0, "levenshtein: empty/empty = 0")
	fails += _expect(Patience.levenshtein("", "abc") == 3, "levenshtein: empty/abc = 3")
	fails += _expect(Patience.levenshtein("abc", "") == 3, "levenshtein: abc/empty = 3")
	fails += _expect(Patience.levenshtein("a", "b") == 1, "levenshtein: single-char different = 1")
	return fails


func _test_levenshtein_distance_window() -> int:
	var fails: int = 0
	fails += _expect(Patience.levenshtein("whats your name", "what's your name") == 1, "levenshtein: punctuation-only differs by 1")
	fails += _expect(Patience.levenshtein("how are you", "how are u") == 2, "levenshtein: 'you'/'u' = 2")
	fails += _expect(Patience.levenshtein("hi", "hello there friend") > 5, "levenshtein: very different exceeds window")
	return fails


func _test_compute_delta_neutral() -> int:
	var npc: StubNpc = _make_npc(0.05)
	var delta: float = Patience.compute_delta("just walking by", npc)
	return _expect_close(delta, -0.05, 0.001, "delta: neutral text -> -decay_rate")


func _test_compute_delta_insult() -> int:
	var npc: StubNpc = _make_npc(0.05)
	var delta: float = Patience.compute_delta("you're stupid", npc)
	return _expect_close(delta, -0.05 + Patience.INSULT_DELTA, 0.001, "delta: insult -> -decay -0.25")


func _test_compute_delta_compliment() -> int:
	var npc: StubNpc = _make_npc(0.05)
	var delta: float = Patience.compute_delta("thanks for the help", npc)
	return _expect_close(delta, -0.05 + Patience.COMPLIMENT_DELTA, 0.001, "delta: compliment -> -decay +0.10")


func _test_compute_delta_interest() -> int:
	var interests: Array[String] = ["book", "story"]
	var npc: StubNpc = _make_npc(0.05, interests)
	var delta: float = Patience.compute_delta("tell me about books", npc)
	return _expect_close(delta, -0.05 + Patience.INTEREST_DELTA, 0.001, "delta: interest match -> -decay +0.05")


func _test_compute_delta_repeat() -> int:
	var interests: Array[String] = []
	var st: Array[Dictionary] = [
		{"role": "user", "content": "what's your name"},
		{"role": "assistant", "content": "Raebai."},
	]
	var npc: StubNpc = _make_npc(0.05, interests, st)
	var delta: float = Patience.compute_delta("whats your name", npc)
	return _expect_close(delta, -0.05 + Patience.REPEAT_DELTA, 0.001, "delta: repeat question -> -decay -0.10")


func _test_compute_delta_stacks() -> int:
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
	return _expect_close(delta, expected, 0.001, "delta: all-stack")
