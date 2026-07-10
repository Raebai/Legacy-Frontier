# Run: godot --headless --path godot-project --script tools/slice2_test_runloop.gd
# GameState.gd is an autoload script; its outcome/fact builders and floor math
# are static + pure, so they are called directly off the loaded GDScript with no
# scene, no Ollama, no change_scene. Runs on the first _process frame per the
# repo idiom.
extends SceneTree

const GS_PATH: String = "res://scripts/GameState.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var GS: GDScript = load(GS_PATH) as GDScript
	var failed: int = 0
	failed += _test_build_outcome(GS)
	failed += _test_build_run_fact(GS)
	failed += _test_run_hint_text(GS)
	failed += _test_merge_run_fact(GS)
	failed += _test_ingest_run_fact(GS)
	failed += _test_floor_math(GS)
	if failed > 0:
		printerr("Slice2 runloop tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice2 runloop tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_build_outcome(GS: GDScript) -> int:
	var failed: int = 0
	var o: Dictionary = GS.build_outcome(3, 11, false, true, ["Fire", "Shadow"], 2, "Ranked")
	failed += _expect(int(o["floor_reached"]) == 3, "floor_reached carried")
	failed += _expect(int(o["enemies_killed"]) == 11, "enemies_killed carried")
	failed += _expect(bool(o["died"]) == true, "died carried")
	failed += _expect(bool(o["cleared"]) == false, "cleared == not died")
	failed += _expect(String(o["rank_title"]) == "Ranked", "rank_title carried")
	failed += _expect((o["elements_used"] as Array).size() == 2, "elements coerced to array")
	failed += _expect(String((o["elements_used"] as Array)[0]) == "Fire", "element stringified")
	var o2: Dictionary = GS.build_outcome(5, 40, true, false, [], 5, "Ascendant")
	failed += _expect(bool(o2["cleared"]) == true, "cleared true when not died")
	failed += _expect(bool(o2["boss_killed"]) == true, "boss_killed carried")
	return failed


func _test_build_run_fact(GS: GDScript) -> int:
	var failed: int = 0
	var died: String = GS.build_run_fact(GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber"))
	failed += _expect(died.begins_with(GS.RUN_FACT_PREFIX), "died fact carries prefix")
	failed += _expect(died.contains("floor 3"), "died fact names the floor")
	failed += _expect(died.contains("fire"), "died fact lowercases element")
	var won: String = GS.build_run_fact(GS.build_outcome(5, 40, true, false, ["Ice"], 5, "Ascendant"))
	failed += _expect(won.contains("guardian"), "boss fact mentions the guardian")
	var alive: String = GS.build_run_fact(GS.build_outcome(2, 5, false, false, [], 1, "Climber"))
	failed += _expect(alive.contains("alive"), "cleared-but-not-boss fact reads 'alive'")
	failed += _expect(alive.begins_with(GS.RUN_FACT_PREFIX), "alive fact carries prefix")
	return failed


func _test_run_hint_text(GS: GDScript) -> int:
	var failed: int = 0
	var died: String = GS.run_hint_text(GS.build_outcome(4, 9, false, true, [], 2, "Ranked"))
	failed += _expect(died.contains("died") and died.contains("floor 4"), "death hint is specific")
	var won: String = GS.run_hint_text(GS.build_outcome(5, 40, true, false, [], 5, "Ascendant"))
	failed += _expect(won.contains("guardian"), "victory hint mentions the guardian")
	return failed


func _test_merge_run_fact(GS: GDScript) -> int:
	var failed: int = 0
	var f1: String = GS.RUN_FACT_PREFIX + "walked out of floor 2 alive"
	var merged: Array = GS.merge_run_fact([], f1, 5)
	failed += _expect(merged.size() == 1 and String(merged[0]) == f1, "append into empty")
	# A second run fact REPLACES the first (only one run-marked entry survives).
	var f2: String = GS.RUN_FACT_PREFIX + "fell on floor 3"
	var merged2: Array = GS.merge_run_fact(merged, f2, 5)
	var run_marked: int = 0
	for f in merged2:
		if String(f).begins_with(GS.RUN_FACT_PREFIX):
			run_marked += 1
	failed += _expect(run_marked == 1, "exactly one run-marked fact survives")
	failed += _expect(String(merged2[merged2.size() - 1]) == f2, "newest run fact is last")
	# Non-run facts are preserved.
	var with_durable: Array = GS.merge_run_fact(["name is Raaed", f1], f2, 5)
	failed += _expect(with_durable.has("name is Raaed"), "durable fact preserved through merge")
	# Cap is enforced by oldest-drop.
	var capped: Array = GS.merge_run_fact(["a", "b", "c", "d", "e"], f2, 5)
	failed += _expect(capped.size() == 5, "cap enforced")
	failed += _expect(not capped.has("a"), "oldest dropped under cap")
	failed += _expect(String(capped[capped.size() - 1]) == f2, "run fact kept as newest")
	return failed


func _test_ingest_run_fact(GS: GDScript) -> int:
	var failed: int = 0
	var stub := _NpcStub.new()
	GS.ingest_run_fact(stub, GS.RUN_FACT_PREFIX + "fell on floor 2")
	failed += _expect(stub.relationships.has("player"), "player relationship auto-created")
	failed += _expect(stub.saved, "save_memory called after ingest")
	var kf: Array = stub.relationships["player"]["key_facts"]
	failed += _expect(kf.size() == 1, "one key fact after first ingest")
	# A second run replaces, not appends.
	GS.ingest_run_fact(stub, GS.RUN_FACT_PREFIX + "cleared floor 5")
	var kf2: Array = stub.relationships["player"]["key_facts"]
	failed += _expect(kf2.size() == 1, "second run replaces the first (still one)")
	failed += _expect(String(kf2[0]).contains("floor 5"), "latest run fact wins")
	return failed


func _test_floor_math(GS: GDScript) -> int:
	var failed: int = 0
	failed += _expect(int(GS.floor_enemy_budget(1)) == 4, "floor 1 budget 4")
	failed += _expect(int(GS.floor_enemy_budget(5)) == 12, "floor 5 budget 12")
	failed += _expect(int(GS.floor_enemy_budget(1)) < int(GS.floor_enemy_budget(3)), "budget ramps")
	failed += _expect(int(GS.floor_concurrent_cap(1)) >= 3, "cap floor >= 3")
	failed += _expect(int(GS.floor_concurrent_cap(9)) <= 7, "cap ceilinged at 7")
	failed += _expect(float(GS.floor_brute_chance(1)) < float(GS.floor_brute_chance(5)), "brute mix ramps")
	failed += _expect(String(GS.floor_theme(1)) == "surface", "floor 1 is surface")
	failed += _expect(String(GS.floor_theme(3)) == "underground", "floor 3 is underground")
	failed += _expect(String(GS.floor_theme(5)) == "sky", "floor 5 is sky")
	return failed


## Minimal NPC stand-in for ingest_run_fact — mirrors NPC.gd's relationship
## surface (relationships dict + _ensure_player_relationship + save_memory).
class _NpcStub extends RefCounted:
	var relationships: Dictionary = {}
	var saved: bool = false

	func _ensure_player_relationship() -> void:
		if not relationships.has("player"):
			relationships["player"] = {"valence": 0.0, "key_facts": []}

	func save_memory() -> void:
		saved = true
