# Run with: godot --headless --path godot-project --script tools/m10_test_consolidator.gd
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
	"parse_valid_json",
	"parse_malformed_json",
	"parse_empty_response",
	"parse_type_coercion_float_for_int",
	"parse_word_cap_enforcement",
	"parse_new_facts_cap",
	"apply_clears_short_term",
	"apply_updates_valence",
	"apply_appends_key_facts",
	"apply_consumes_inbox_indices",
	"apply_stashes_pending_facts_to_share",
	"apply_mood_decay_snaps_to_zero_within_floor",
	"truncate_concat_fallback",
	"apply_error_path_uses_fallback",
]

var _fails: int = 0
var _completed: Dictionary = {}


class StubData:
	var npc_name: String = "Test"
	var personality_prompt: String = "First line\nSecond line"


class StubNpc:
	var data: StubData
	var short_term: Array[Dictionary] = []
	var long_term_summary: String = ""
	var relationships: Dictionary = {}
	var mood: float = 0.0
	var pending_facts_to_share: Array = []


func _init() -> void:
	_test_parse_valid_json()
	_test_parse_malformed_json()
	_test_parse_empty_response()
	_test_parse_type_coercion_float_for_int()
	_test_parse_word_cap_enforcement()
	_test_parse_new_facts_cap()
	_test_apply_clears_short_term()
	_test_apply_updates_valence()
	_test_apply_appends_key_facts()
	_test_apply_consumes_inbox_indices()
	_test_apply_stashes_pending_facts_to_share()
	_test_apply_mood_decay_snaps_to_zero_within_floor()
	_test_truncate_concat_fallback()
	_test_apply_error_path_uses_fallback()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("M10 tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("M10 tests: all PASS")
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


func _test_parse_valid_json() -> void:
	var json: String = '{"updated_long_term_summary":"All went well.","relationship_updates":{"player":{"valence_delta":0.2,"new_facts":["fact1"],"consumed_inbox_indices":[]}},"mood_delta":0.1,"strong_facts_to_share":[]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	_expect(not parsed.has("error"), "valid: no error key")
	_expect(parsed["updated_long_term_summary"] == "All went well.", "valid: long_term preserved")
	_expect_close(parsed["mood_delta"], 0.1, 0.001, "valid: mood_delta float")
	_expect(parsed["relationship_updates"].has("player"), "valid: player update present")
	_completes("parse_valid_json")


func _test_parse_malformed_json() -> void:
	var parsed: Dictionary = MemoryConsolidator.parse_response("this is not json at all")
	_expect(parsed.has("error"), "malformed: returns error key")
	_completes("parse_malformed_json")


func _test_parse_empty_response() -> void:
	var parsed: Dictionary = MemoryConsolidator.parse_response("")
	_expect(parsed.has("error"), "empty: returns error key")
	_completes("parse_empty_response")


func _test_parse_type_coercion_float_for_int() -> void:
	# JSON.parse_string returns numbers as TYPE_FLOAT; consumed_inbox_indices
	# might therefore arrive as [0.0, 1.0]. parse_response must coerce to int.
	var json: String = '{"updated_long_term_summary":"x","relationship_updates":{"a":{"consumed_inbox_indices":[0,1,2]}},"mood_delta":0,"strong_facts_to_share":[]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	var consumed: Array = parsed["relationship_updates"]["a"]["consumed_inbox_indices"]
	_expect(consumed.size() == 3, "coerce: 3 indices")
	_expect(typeof(consumed[0]) == TYPE_INT, "coerce: index[0] is int")
	_completes("parse_type_coercion_float_for_int")


func _test_parse_word_cap_enforcement() -> void:
	# 100-word summary should get clipped to 80.
	var long_text: String = "word ".repeat(100).strip_edges()
	var json: String = '{"updated_long_term_summary":"' + long_text + '","mood_delta":0,"relationship_updates":{},"strong_facts_to_share":[]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	var word_count: int = parsed["updated_long_term_summary"].split(" ", false).size()
	_expect(word_count <= 81, "word_cap: %d words (limit 80 + ellipsis)" % word_count)
	_completes("parse_word_cap_enforcement")


func _test_parse_new_facts_cap() -> void:
	var json: String = '{"updated_long_term_summary":"x","relationship_updates":{"player":{"new_facts":["f1","f2","f3","f4","f5"]}},"mood_delta":0,"strong_facts_to_share":[]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	var facts: Array = parsed["relationship_updates"]["player"]["new_facts"]
	_expect(facts.size() == 3, "new_facts_cap: 3 max (got %d)" % facts.size())
	_completes("parse_new_facts_cap")


func _test_apply_clears_short_term() -> void:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.short_term = [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "hello"}]
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"a chat","mood_delta":0,"relationship_updates":{},"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	_expect(npc.short_term.is_empty(), "apply: short_term cleared after consolidation")
	_completes("apply_clears_short_term")


func _test_apply_updates_valence() -> void:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.relationships = {"player": {"valence": 0.3, "key_facts": [], "gossip_inbox": []}}
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"x","relationship_updates":{"player":{"valence_delta":0.2}},"mood_delta":0,"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	_expect_close(npc.relationships["player"]["valence"], 0.5, 0.001, "apply: valence 0.3+0.2 = 0.5")
	_completes("apply_updates_valence")


func _test_apply_appends_key_facts() -> void:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.relationships = {"player": {"valence": 0.0, "key_facts": ["existing"], "gossip_inbox": []}}
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"x","relationship_updates":{"player":{"new_facts":["new fact 1","new fact 2"]}},"mood_delta":0,"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	var facts: Array = npc.relationships["player"]["key_facts"]
	_expect(facts.size() == 3 and facts[2] == "new fact 2", "apply: key_facts appended (got %s)" % str(facts))
	_completes("apply_appends_key_facts")


func _test_apply_consumes_inbox_indices() -> void:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.relationships = {"player": {"valence": 0.0, "key_facts": [], "gossip_inbox": [
		{"from": "a", "fact": "old"},
		{"from": "b", "fact": "stale"},
		{"from": "c", "fact": "keep"},
	]}}
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"x","relationship_updates":{"player":{"consumed_inbox_indices":[0,1]}},"mood_delta":0,"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	var inbox: Array = npc.relationships["player"]["gossip_inbox"]
	_expect(inbox.size() == 1 and inbox[0]["fact"] == "keep", "apply: indices 0,1 consumed; only 'keep' remains")
	_completes("apply_consumes_inbox_indices")


func _test_apply_stashes_pending_facts_to_share() -> void:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.pending_facts_to_share = []
	var json: String = '{"updated_long_term_summary":"x","relationship_updates":{},"mood_delta":0,"strong_facts_to_share":[{"about":"player","fact":"heading to Coldrose","share_with":["mirelle"]}]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	MemoryConsolidator.apply_to_npc(npc, parsed)
	_expect(npc.pending_facts_to_share.size() == 1, "share: queue has 1 entry")
	if npc.pending_facts_to_share.size() > 0:
		_expect(npc.pending_facts_to_share[0]["share_with"][0] == "mirelle", "share: share_with preserved")
	_completes("apply_stashes_pending_facts_to_share")


func _test_apply_mood_decay_snaps_to_zero_within_floor() -> void:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.mood = 0.03  # within ±0.05 floor; should snap to 0
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"x","relationship_updates":{},"mood_delta":0,"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	_expect_close(npc.mood, 0.0, 0.001, "decay: snaps to 0 within ±0.05 floor")
	_completes("apply_mood_decay_snaps_to_zero_within_floor")


func _test_truncate_concat_fallback() -> void:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.short_term = [{"role": "user", "content": "hello"}, {"role": "assistant", "content": "hi"}]
	var summary: String = MemoryConsolidator.build_truncate_concat_summary(npc)
	_expect("hello" in summary and "hi" in summary, "fallback: both turns appear in concat")
	_completes("truncate_concat_fallback")


func _test_apply_error_path_uses_fallback() -> void:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.short_term = [{"role": "user", "content": "raw content"}, {"role": "assistant", "content": "raw reply"}]
	var parsed: Dictionary = MemoryConsolidator.parse_response("not json")  # returns {"error": ...}
	MemoryConsolidator.apply_to_npc(npc, parsed)
	_expect("raw content" in npc.long_term_summary, "error_path: fallback wrote raw content to long_term")
	_expect(npc.short_term.is_empty(), "error_path: short_term cleared even on fallback")
	_completes("apply_error_path_uses_fallback")
