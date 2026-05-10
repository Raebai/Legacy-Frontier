# godot-project/tools/m12_test_initial_relationships.gd
# Run with: godot --headless --path godot-project --script tools/m12_test_initial_relationships.gd
# Mirrors NPC._seed_initial_relationships logic for isolated testing.
extends SceneTree


func _init() -> void:
	var failed: int = 0
	failed += _test_seed_populates_empty_registry()
	failed += _test_seed_does_not_overwrite_existing()
	failed += _test_malformed_seed_is_skipped()
	failed += _test_missing_fields_get_defaults()
	failed += _test_multiple_seeds_all_applied()
	if failed > 0:
		printerr("M12 tests: %d FAILED" % failed)
		quit(1)
	else:
		print("M12 tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


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


func _test_seed_populates_empty_registry() -> int:
	var seed: Array = [{"entity_id": "raebai", "valence": 0.7, "key_facts": ["old friend"]}]
	var rel: Dictionary = _merge(seed, {})
	var fails: int = 0
	fails += _expect(rel.has("raebai"), "seed: raebai key present")
	fails += _expect(rel["raebai"]["valence"] == 0.7, "seed: valence preserved")
	fails += _expect((rel["raebai"]["key_facts"] as Array)[0] == "old friend", "seed: key_facts preserved")
	fails += _expect((rel["raebai"]["gossip_inbox"] as Array).is_empty(), "seed: gossip_inbox empty")
	return fails


func _test_seed_does_not_overwrite_existing() -> int:
	var seed: Array = [{"entity_id": "raebai", "valence": 0.7, "key_facts": ["fresh seed"]}]
	var existing: Dictionary = {
		"raebai": {"valence": 0.4, "key_facts": ["evolved fact"], "gossip_inbox": []},
	}
	var rel: Dictionary = _merge(seed, existing)
	var fails: int = 0
	fails += _expect(rel["raebai"]["valence"] == 0.4, "no-overwrite: valence preserved")
	fails += _expect((rel["raebai"]["key_facts"] as Array)[0] == "evolved fact", "no-overwrite: key_facts preserved")
	return fails


func _test_malformed_seed_is_skipped() -> int:
	var seed: Array = [
		"not a dict",
		{"entity_id": "", "valence": 0.5},        # empty id
		null,
		42,
		{"entity_id": "valid", "valence": 0.3},
	]
	var rel: Dictionary = _merge(seed, {})
	var fails: int = 0
	fails += _expect(rel.size() == 1, "malformed: only valid entry kept (size=%d)" % rel.size())
	fails += _expect(rel.has("valid"), "malformed: 'valid' present")
	return fails


func _test_missing_fields_get_defaults() -> int:
	var seed: Array = [{"entity_id": "barebones"}]
	var rel: Dictionary = _merge(seed, {})
	var fails: int = 0
	fails += _expect(rel["barebones"]["valence"] == 0.0, "defaults: valence -> 0.0")
	fails += _expect((rel["barebones"]["key_facts"] as Array).is_empty(), "defaults: key_facts -> []")
	fails += _expect((rel["barebones"]["gossip_inbox"] as Array).is_empty(), "defaults: gossip_inbox -> []")
	return fails


func _test_multiple_seeds_all_applied() -> int:
	var seed: Array = [
		{"entity_id": "a", "valence": 0.5},
		{"entity_id": "b", "valence": -0.2, "key_facts": ["wary"]},
		{"entity_id": "c", "valence": 0.9, "key_facts": ["beloved"]},
	]
	var rel: Dictionary = _merge(seed, {})
	var fails: int = 0
	fails += _expect(rel.size() == 3, "multi: all three seeds applied (size=%d)" % rel.size())
	fails += _expect(rel["b"]["valence"] == -0.2, "multi: b valence preserved")
	fails += _expect((rel["c"]["key_facts"] as Array)[0] == "beloved", "multi: c key_facts preserved")
	return fails
