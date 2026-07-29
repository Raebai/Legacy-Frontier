# godot-project/tools/m9_test_memory.gd
# Run with: godot --headless --path godot-project --script tools/m9_test_memory.gd
# Exits with code 0 on success, prints failures to stderr and exits non-zero on failure.
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
	"migrate_v1_to_v2",
	"empty_v2",
	"valence_word_bands",
	"mood_word_bands",
	"patience_word_bands",
	"estimate_tokens",
	"compact_relationship_minimal",
	"compact_relationship_empty_arrays",
	"compact_relationship_full",
]

var _fails: int = 0
var _completed: Dictionary = {}


func _init() -> void:
	_test_migrate_v1_to_v2()
	_test_empty_v2()
	_test_valence_word_bands()
	_test_mood_word_bands()
	_test_patience_word_bands()
	_test_estimate_tokens()
	_test_compact_relationship_minimal()
	_test_compact_relationship_empty_arrays()
	_test_compact_relationship_full()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("M9 tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("M9 tests: all PASS")
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


func _test_migrate_v1_to_v2() -> void:
	var v1: Dictionary = {
		"version": 1,
		"npc_id": "raebai",
		"messages": [{"role": "user", "content": "hi"}],
	}
	var v2: Dictionary = MemoryUtils.migrate_v1_to_v2(v1)
	_expect(v2["version"] == 2, "migrate: version is 2")
	_expect(v2["npc_id"] == "raebai", "migrate: npc_id preserved")
	_expect(v2["short_term"] == v1["messages"], "migrate: messages -> short_term")
	_expect(v2["long_term_summary"] == "", "migrate: long_term_summary empty")
	_expect(v2["relationships"] is Dictionary and v2["relationships"].is_empty(), "migrate: relationships empty dict")
	_expect(v2["stats"].get("mood", -99.0) == 0.0, "migrate: stats.mood default 0")
	_completes("migrate_v1_to_v2")


func _test_empty_v2() -> void:
	var v2: Dictionary = MemoryUtils.empty_v2("mirelle")
	_expect(v2["version"] == 2, "empty_v2: version is 2")
	_expect(v2["npc_id"] == "mirelle", "empty_v2: npc_id set")
	_expect((v2["short_term"] as Array).is_empty(), "empty_v2: short_term empty")
	_completes("empty_v2")


func _test_valence_word_bands() -> void:
	_expect(MemoryUtils.valence_word(0.7) == "deeply trusting", "valence: 0.7 -> deeply trusting")
	_expect(MemoryUtils.valence_word(0.4) == "warm", "valence: 0.4 -> warm")
	_expect(MemoryUtils.valence_word(0.0) == "neutral", "valence: 0.0 -> neutral")
	_expect(MemoryUtils.valence_word(-0.4) == "cold", "valence: -0.4 -> cold")
	_expect(MemoryUtils.valence_word(-0.8) == "hostile", "valence: -0.8 -> hostile")
	# Boundary checks (catches off-by-one threshold drift)
	_expect(MemoryUtils.valence_word(0.6) == "warm", "valence: 0.6 -> warm (boundary)")
	_expect(MemoryUtils.valence_word(0.2) == "neutral", "valence: 0.2 -> neutral (boundary)")
	_expect(MemoryUtils.valence_word(-0.2) == "cold", "valence: -0.2 -> cold (boundary)")
	_expect(MemoryUtils.valence_word(-0.6) == "hostile", "valence: -0.6 -> hostile (boundary)")
	_completes("valence_word_bands")


func _test_mood_word_bands() -> void:
	_expect(MemoryUtils.mood_word(0.6) == "bright and open", "mood: 0.6 -> bright and open")
	_expect(MemoryUtils.mood_word(0.3) == "settled", "mood: 0.3 -> settled")
	_expect(MemoryUtils.mood_word(0.0) == "even", "mood: 0.0 -> even")
	_expect(MemoryUtils.mood_word(-0.3) == "gloomy", "mood: -0.3 -> gloomy")
	_expect(MemoryUtils.mood_word(-0.7) == "dark", "mood: -0.7 -> dark")
	_expect(MemoryUtils.mood_word(0.5) == "settled", "mood: 0.5 -> settled (boundary)")
	_expect(MemoryUtils.mood_word(0.2) == "even", "mood: 0.2 -> even (boundary)")
	_expect(MemoryUtils.mood_word(-0.2) == "gloomy", "mood: -0.2 -> gloomy (boundary)")
	_expect(MemoryUtils.mood_word(-0.5) == "dark", "mood: -0.5 -> dark (boundary)")
	_completes("mood_word_bands")


func _test_patience_word_bands() -> void:
	_expect(MemoryUtils.patience_word(0.95) == "fresh and curious", "patience: 0.95 -> fresh and curious")
	_expect(MemoryUtils.patience_word(0.7) == "engaged", "patience: 0.7 -> engaged")
	_expect(MemoryUtils.patience_word(0.3) == "fading", "patience: 0.3 -> fading")
	_expect(MemoryUtils.patience_word(0.1) == "worn out, ready to leave", "patience: 0.1 -> worn out")
	_expect(MemoryUtils.patience_word(0.8) == "engaged", "patience: 0.8 -> engaged (boundary)")
	_expect(MemoryUtils.patience_word(0.5) == "fading", "patience: 0.5 -> fading (boundary)")
	_expect(MemoryUtils.patience_word(0.2) == "worn out, ready to leave", "patience: 0.2 -> worn out (boundary)")
	_completes("patience_word_bands")


func _test_estimate_tokens() -> void:
	_expect(MemoryUtils.estimate_tokens("") == 0, "tokens: empty -> 0")
	_expect(MemoryUtils.estimate_tokens("abcd") == 1, "tokens: 4 chars -> 1")
	_expect(MemoryUtils.estimate_tokens("a".repeat(100)) == 25, "tokens: 100 chars -> 25")
	_completes("estimate_tokens")


func _test_compact_relationship_minimal() -> void:
	var rel: Dictionary = {"valence": 0.4}
	var line: String = MemoryUtils.compact_relationship("the player", rel)
	_expect(line == "the player [warm].", "compact (minimal): " + line)
	_completes("compact_relationship_minimal")


func _test_compact_relationship_empty_arrays() -> void:
	# key_facts present-but-empty + gossip_inbox present-but-empty.
	# Both branches should be taken (size() > 0 is false), output identical to minimal case.
	var rel: Dictionary = {"valence": 0.4, "key_facts": [], "gossip_inbox": []}
	var line: String = MemoryUtils.compact_relationship("the player", rel)
	_expect(line == "the player [warm].", "compact (empty arrays): " + line)
	_completes("compact_relationship_empty_arrays")


func _test_compact_relationship_full() -> void:
	var rel: Dictionary = {
		"valence": 0.7,
		"key_facts": ["old friend", "news node"],
		"gossip_inbox": [{"from": "raebai", "fact": "asked about Coldrose"}],
	}
	var line: String = MemoryUtils.compact_relationship("Mirelle", rel)
	var expected: String = "Mirelle [deeply trusting] — old friend, news node. Recent rumours: raebai said: asked about Coldrose."
	_expect(line == expected, "compact (full):\n  got:      " + line + "\n  expected: " + expected)
	_completes("compact_relationship_full")
