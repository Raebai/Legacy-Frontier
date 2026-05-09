# godot-project/tools/m9_test_memory.gd
# Run with: godot --headless --path godot-project --script tools/m9_test_memory.gd
# Exits with code 0 on success, prints failures to stderr and exits non-zero on failure.
extends SceneTree


func _init() -> void:
	var failed: int = 0
	failed += _test_migrate_v1_to_v2()
	failed += _test_empty_v2()
	failed += _test_valence_word_bands()
	failed += _test_mood_word_bands()
	failed += _test_patience_word_bands()
	failed += _test_estimate_tokens()
	failed += _test_compact_relationship_minimal()
	failed += _test_compact_relationship_full()
	if failed > 0:
		printerr("M9 tests: %d FAILED" % failed)
		quit(1)
	else:
		print("M9 tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_migrate_v1_to_v2() -> int:
	var v1: Dictionary = {
		"version": 1,
		"npc_id": "raebai",
		"messages": [{"role": "user", "content": "hi"}],
	}
	var v2: Dictionary = MemoryUtils.migrate_v1_to_v2(v1)
	var fails: int = 0
	fails += _expect(v2["version"] == 2, "migrate: version is 2")
	fails += _expect(v2["npc_id"] == "raebai", "migrate: npc_id preserved")
	fails += _expect(v2["short_term"] == v1["messages"], "migrate: messages -> short_term")
	fails += _expect(v2["long_term_summary"] == "", "migrate: long_term_summary empty")
	fails += _expect(v2["relationships"] is Dictionary and v2["relationships"].is_empty(), "migrate: relationships empty dict")
	fails += _expect(v2["stats"].get("mood", -99.0) == 0.0, "migrate: stats.mood default 0")
	return fails


func _test_empty_v2() -> int:
	var v2: Dictionary = MemoryUtils.empty_v2("mirelle")
	var fails: int = 0
	fails += _expect(v2["version"] == 2, "empty_v2: version is 2")
	fails += _expect(v2["npc_id"] == "mirelle", "empty_v2: npc_id set")
	fails += _expect((v2["short_term"] as Array).is_empty(), "empty_v2: short_term empty")
	return fails


func _test_valence_word_bands() -> int:
	var fails: int = 0
	fails += _expect(MemoryUtils.valence_word(0.7) == "deeply trusting", "valence: 0.7 -> deeply trusting")
	fails += _expect(MemoryUtils.valence_word(0.4) == "warm", "valence: 0.4 -> warm")
	fails += _expect(MemoryUtils.valence_word(0.0) == "neutral", "valence: 0.0 -> neutral")
	fails += _expect(MemoryUtils.valence_word(-0.4) == "cold", "valence: -0.4 -> cold")
	fails += _expect(MemoryUtils.valence_word(-0.8) == "hostile", "valence: -0.8 -> hostile")
	return fails


func _test_mood_word_bands() -> int:
	var fails: int = 0
	fails += _expect(MemoryUtils.mood_word(0.6) == "bright and open", "mood: 0.6 -> bright and open")
	fails += _expect(MemoryUtils.mood_word(0.3) == "settled", "mood: 0.3 -> settled")
	fails += _expect(MemoryUtils.mood_word(0.0) == "even", "mood: 0.0 -> even")
	fails += _expect(MemoryUtils.mood_word(-0.3) == "gloomy", "mood: -0.3 -> gloomy")
	fails += _expect(MemoryUtils.mood_word(-0.7) == "dark", "mood: -0.7 -> dark")
	return fails


func _test_patience_word_bands() -> int:
	var fails: int = 0
	fails += _expect(MemoryUtils.patience_word(0.95) == "fresh and curious", "patience: 0.95 -> fresh and curious")
	fails += _expect(MemoryUtils.patience_word(0.7) == "engaged", "patience: 0.7 -> engaged")
	fails += _expect(MemoryUtils.patience_word(0.3) == "fading", "patience: 0.3 -> fading")
	fails += _expect(MemoryUtils.patience_word(0.1) == "worn out, ready to leave", "patience: 0.1 -> worn out")
	return fails


func _test_estimate_tokens() -> int:
	var fails: int = 0
	fails += _expect(MemoryUtils.estimate_tokens("") == 0, "tokens: empty -> 0")
	fails += _expect(MemoryUtils.estimate_tokens("abcd") == 1, "tokens: 4 chars -> 1")
	fails += _expect(MemoryUtils.estimate_tokens("a".repeat(100)) == 25, "tokens: 100 chars -> 25")
	return fails


func _test_compact_relationship_minimal() -> int:
	var rel: Dictionary = {"valence": 0.4}
	var line: String = MemoryUtils.compact_relationship("the player", rel)
	return _expect(line == "the player [warm].", "compact (minimal): " + line)


func _test_compact_relationship_full() -> int:
	var rel: Dictionary = {
		"valence": 0.7,
		"key_facts": ["old friend", "news node"],
		"gossip_inbox": [{"from": "raebai", "fact": "asked about Coldrose"}],
	}
	var line: String = MemoryUtils.compact_relationship("Mirelle", rel)
	var expected: String = "Mirelle [deeply trusting] — old friend, news node. Recent rumours: raebai said: asked about Coldrose."
	return _expect(line == expected, "compact (full):\n  got:      " + line + "\n  expected: " + expected)
