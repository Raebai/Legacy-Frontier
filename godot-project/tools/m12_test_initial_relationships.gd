# godot-project/tools/m12_test_initial_relationships.gd
# Run with: godot --headless --path godot-project --script tools/m12_test_initial_relationships.gd
# Mirrors NPC._seed_initial_relationships logic for isolated testing.
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
	"seed_populates_empty_registry",
	"seed_does_not_overwrite_existing",
	"malformed_seed_is_skipped",
	"missing_fields_get_defaults",
	"multiple_seeds_all_applied",
]

var _fails: int = 0
var _completed: Dictionary = {}


func _init() -> void:
	_test_seed_populates_empty_registry()
	_test_seed_does_not_overwrite_existing()
	_test_malformed_seed_is_skipped()
	_test_missing_fields_get_defaults()
	_test_multiple_seeds_all_applied()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("M12 tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("M12 tests: all PASS")
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


# Pure-function mirror of NPC._seed_initial_relationships. Mutates `existing`
# in place and returns it for caller convenience.
func _merge(seed: Array, existing: Dictionary) -> Dictionary:
	var rel: Dictionary = existing.duplicate(true)
	for s in seed:
		if not (s is Dictionary):
			continue
		var entity_id: String = str(s.get("entity_id", ""))
		if entity_id == "":
			continue
		if rel.has(entity_id):
			continue
		var key_facts_seed: Variant = s.get("key_facts", [])
		var key_facts: Array = []
		if key_facts_seed is Array:
			for f in key_facts_seed:
				key_facts.append(str(f))
		rel[entity_id] = {
			"valence": float(s.get("valence", 0.0)),
			"key_facts": key_facts,
			"gossip_inbox": [],
		}
	return rel


func _test_seed_populates_empty_registry() -> void:
	var seed: Array = [{"entity_id": "raebai", "valence": 0.7, "key_facts": ["old friend"]}]
	var rel: Dictionary = _merge(seed, {})
	_expect(rel.has("raebai"), "seed: raebai key present")
	_expect(rel["raebai"]["valence"] == 0.7, "seed: valence preserved")
	_expect((rel["raebai"]["key_facts"] as Array)[0] == "old friend", "seed: key_facts preserved")
	_expect((rel["raebai"]["gossip_inbox"] as Array).is_empty(), "seed: gossip_inbox empty")
	_completes("seed_populates_empty_registry")


func _test_seed_does_not_overwrite_existing() -> void:
	var seed: Array = [{"entity_id": "raebai", "valence": 0.7, "key_facts": ["fresh seed"]}]
	var existing: Dictionary = {
		"raebai": {"valence": 0.4, "key_facts": ["evolved fact"], "gossip_inbox": []},
	}
	var rel: Dictionary = _merge(seed, existing)
	_expect(rel["raebai"]["valence"] == 0.4, "no-overwrite: valence preserved")
	_expect((rel["raebai"]["key_facts"] as Array)[0] == "evolved fact", "no-overwrite: key_facts preserved")
	_completes("seed_does_not_overwrite_existing")


func _test_malformed_seed_is_skipped() -> void:
	var seed: Array = [
		"not a dict",
		{"entity_id": "", "valence": 0.5},        # empty id
		null,
		42,
		{"entity_id": "valid", "valence": 0.3},
	]
	var rel: Dictionary = _merge(seed, {})
	_expect(rel.size() == 1, "malformed: only valid entry kept (size=%d)" % rel.size())
	_expect(rel.has("valid"), "malformed: 'valid' present")
	_completes("malformed_seed_is_skipped")


func _test_missing_fields_get_defaults() -> void:
	var seed: Array = [{"entity_id": "barebones"}]
	var rel: Dictionary = _merge(seed, {})
	_expect(rel["barebones"]["valence"] == 0.0, "defaults: valence -> 0.0")
	_expect((rel["barebones"]["key_facts"] as Array).is_empty(), "defaults: key_facts -> []")
	_expect((rel["barebones"]["gossip_inbox"] as Array).is_empty(), "defaults: gossip_inbox -> []")
	_completes("missing_fields_get_defaults")


func _test_multiple_seeds_all_applied() -> void:
	var seed: Array = [
		{"entity_id": "a", "valence": 0.5},
		{"entity_id": "b", "valence": -0.2, "key_facts": ["wary"]},
		{"entity_id": "c", "valence": 0.9, "key_facts": ["beloved"]},
	]
	var rel: Dictionary = _merge(seed, {})
	_expect(rel.size() == 3, "multi: all three seeds applied (size=%d)" % rel.size())
	_expect(rel["b"]["valence"] == -0.2, "multi: b valence preserved")
	_expect((rel["c"]["key_facts"] as Array)[0] == "beloved", "multi: c key_facts preserved")
	_completes("multiple_seeds_all_applied")
