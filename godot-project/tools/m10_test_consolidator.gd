# Run with: godot --headless --path godot-project --script tools/m10_test_consolidator.gd
extends SceneTree


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
	var failed: int = 0
	failed += _test_parse_valid_json()
	failed += _test_parse_malformed_json()
	failed += _test_parse_empty_response()
	failed += _test_parse_type_coercion_float_for_int()
	failed += _test_parse_word_cap_enforcement()
	failed += _test_parse_new_facts_cap()
	failed += _test_apply_clears_short_term()
	failed += _test_apply_updates_valence()
	failed += _test_apply_appends_key_facts()
	failed += _test_apply_consumes_inbox_indices()
	failed += _test_apply_stashes_pending_facts_to_share()
	failed += _test_apply_mood_decay_snaps_to_zero_within_floor()
	failed += _test_truncate_concat_fallback()
	failed += _test_apply_error_path_uses_fallback()
	if failed > 0:
		printerr("M10 tests: %d FAILED" % failed)
		quit(1)
	else:
		print("M10 tests: all PASS")
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


func _test_parse_valid_json() -> int:
	var json: String = '{"updated_long_term_summary":"All went well.","relationship_updates":{"player":{"valence_delta":0.2,"new_facts":["fact1"],"consumed_inbox_indices":[]}},"mood_delta":0.1,"strong_facts_to_share":[]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	var fails: int = 0
	fails += _expect(not parsed.has("error"), "valid: no error key")
	fails += _expect(parsed["updated_long_term_summary"] == "All went well.", "valid: long_term preserved")
	fails += _expect_close(parsed["mood_delta"], 0.1, 0.001, "valid: mood_delta float")
	fails += _expect(parsed["relationship_updates"].has("player"), "valid: player update present")
	return fails


func _test_parse_malformed_json() -> int:
	var parsed: Dictionary = MemoryConsolidator.parse_response("this is not json at all")
	return _expect(parsed.has("error"), "malformed: returns error key")


func _test_parse_empty_response() -> int:
	var parsed: Dictionary = MemoryConsolidator.parse_response("")
	return _expect(parsed.has("error"), "empty: returns error key")


func _test_parse_type_coercion_float_for_int() -> int:
	# JSON.parse_string returns numbers as TYPE_FLOAT; consumed_inbox_indices
	# might therefore arrive as [0.0, 1.0]. parse_response must coerce to int.
	var json: String = '{"updated_long_term_summary":"x","relationship_updates":{"a":{"consumed_inbox_indices":[0,1,2]}},"mood_delta":0,"strong_facts_to_share":[]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	var consumed: Array = parsed["relationship_updates"]["a"]["consumed_inbox_indices"]
	var fails: int = 0
	fails += _expect(consumed.size() == 3, "coerce: 3 indices")
	fails += _expect(typeof(consumed[0]) == TYPE_INT, "coerce: index[0] is int")
	return fails


func _test_parse_word_cap_enforcement() -> int:
	# 100-word summary should get clipped to 80.
	var long_text: String = "word ".repeat(100).strip_edges()
	var json: String = '{"updated_long_term_summary":"' + long_text + '","mood_delta":0,"relationship_updates":{},"strong_facts_to_share":[]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	var word_count: int = parsed["updated_long_term_summary"].split(" ", false).size()
	return _expect(word_count <= 81, "word_cap: %d words (limit 80 + ellipsis)" % word_count)


func _test_parse_new_facts_cap() -> int:
	var json: String = '{"updated_long_term_summary":"x","relationship_updates":{"player":{"new_facts":["f1","f2","f3","f4","f5"]}},"mood_delta":0,"strong_facts_to_share":[]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	var facts: Array = parsed["relationship_updates"]["player"]["new_facts"]
	return _expect(facts.size() == 3, "new_facts_cap: 3 max (got %d)" % facts.size())


func _test_apply_clears_short_term() -> int:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.short_term = [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "hello"}]
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"a chat","mood_delta":0,"relationship_updates":{},"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	return _expect(npc.short_term.is_empty(), "apply: short_term cleared after consolidation")


func _test_apply_updates_valence() -> int:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.relationships = {"player": {"valence": 0.3, "key_facts": [], "gossip_inbox": []}}
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"x","relationship_updates":{"player":{"valence_delta":0.2}},"mood_delta":0,"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	return _expect_close(npc.relationships["player"]["valence"], 0.5, 0.001, "apply: valence 0.3+0.2 = 0.5")


func _test_apply_appends_key_facts() -> int:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.relationships = {"player": {"valence": 0.0, "key_facts": ["existing"], "gossip_inbox": []}}
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"x","relationship_updates":{"player":{"new_facts":["new fact 1","new fact 2"]}},"mood_delta":0,"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	var facts: Array = npc.relationships["player"]["key_facts"]
	return _expect(facts.size() == 3 and facts[2] == "new fact 2", "apply: key_facts appended (got %s)" % str(facts))


func _test_apply_consumes_inbox_indices() -> int:
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
	return _expect(inbox.size() == 1 and inbox[0]["fact"] == "keep", "apply: indices 0,1 consumed; only 'keep' remains")


func _test_apply_stashes_pending_facts_to_share() -> int:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.pending_facts_to_share = []
	var json: String = '{"updated_long_term_summary":"x","relationship_updates":{},"mood_delta":0,"strong_facts_to_share":[{"about":"player","fact":"heading to Coldrose","share_with":["mirelle"]}]}'
	var parsed: Dictionary = MemoryConsolidator.parse_response(json)
	MemoryConsolidator.apply_to_npc(npc, parsed)
	var fails: int = 0
	fails += _expect(npc.pending_facts_to_share.size() == 1, "share: queue has 1 entry")
	if npc.pending_facts_to_share.size() > 0:
		fails += _expect(npc.pending_facts_to_share[0]["share_with"][0] == "mirelle", "share: share_with preserved")
	return fails


func _test_apply_mood_decay_snaps_to_zero_within_floor() -> int:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.mood = 0.03  # within ±0.05 floor; should snap to 0
	var parsed: Dictionary = MemoryConsolidator.parse_response('{"updated_long_term_summary":"x","relationship_updates":{},"mood_delta":0,"strong_facts_to_share":[]}')
	MemoryConsolidator.apply_to_npc(npc, parsed)
	return _expect_close(npc.mood, 0.0, 0.001, "decay: snaps to 0 within ±0.05 floor")


func _test_truncate_concat_fallback() -> int:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.short_term = [{"role": "user", "content": "hello"}, {"role": "assistant", "content": "hi"}]
	var summary: String = MemoryConsolidator.build_truncate_concat_summary(npc)
	return _expect("hello" in summary and "hi" in summary, "fallback: both turns appear in concat")


func _test_apply_error_path_uses_fallback() -> int:
	var npc: StubNpc = StubNpc.new()
	npc.data = StubData.new()
	npc.short_term = [{"role": "user", "content": "raw content"}, {"role": "assistant", "content": "raw reply"}]
	var parsed: Dictionary = MemoryConsolidator.parse_response("not json")  # returns {"error": ...}
	MemoryConsolidator.apply_to_npc(npc, parsed)
	var fails: int = 0
	fails += _expect("raw content" in npc.long_term_summary, "error_path: fallback wrote raw content to long_term")
	fails += _expect(npc.short_term.is_empty(), "error_path: short_term cleared even on fallback")
	return fails
