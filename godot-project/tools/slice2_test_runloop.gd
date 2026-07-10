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
	failed += _test_floor_def_synthesis(GS)
	failed += _test_tower_authoring(GS)
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


## Synthesized FloorDef (null-tower fallback) must match the depth math exactly,
## so routing Arena through FloorDef is a byte-identical behaviour change.
func _test_floor_def_synthesis(GS: GDScript) -> int:
	var failed: int = 0
	for floor in [1, 3, 5]:
		var fd: Resource = GS.synthesize_floor_def(floor)
		failed += _expect(int(fd.enemy_budget) == int(GS.floor_enemy_budget(floor)),
			"floor %d budget matches math" % floor)
		failed += _expect(int(fd.concurrent_cap) == int(GS.floor_concurrent_cap(floor)),
			"floor %d cap matches math" % floor)
		failed += _expect(is_equal_approx(float(fd.brute_chance), float(GS.floor_brute_chance(floor))),
			"floor %d brute_chance matches math" % floor)
		failed += _expect(String(fd.theme.name) == String(GS.floor_theme(floor)),
			"floor %d theme name matches math" % floor)
		failed += _expect(fd.theme.wash_tint == GS.floor_theme_tint(floor),
			"floor %d theme tint matches math" % floor)
	# hp_multiplier: 1.0 at floor 1, ramps with depth.
	failed += _expect(is_equal_approx(float(GS.synthesize_floor_def(1).hp_multiplier), 1.0),
		"floor 1 hp_multiplier is 1.0")
	failed += _expect(float(GS.synthesize_floor_def(5).hp_multiplier) > 1.0,
		"deeper floor hp_multiplier ramps")
	return failed


## The default Ashspire tower is a 5-floor typed spine ending in a BOSS.
func _test_tower_authoring(GS: GDScript) -> int:
	var failed: int = 0
	var t: Resource = GS.build_default_tower()
	failed += _expect(t.floors.size() == 5, "Ashspire has 5 floors")
	# FloorType: COMBAT=0, ELITE=1, BOSS=2.
	failed += _expect(int(t.floors[0].floor_type) == 0, "floor 1 is COMBAT")
	failed += _expect(int(t.floors[2].floor_type) == 1, "floor 3 is ELITE")
	failed += _expect(int(t.floors[4].floor_type) == 2, "floor 5 is BOSS")
	failed += _expect(int(t.floors[0].enemy_budget) == 5, "floor 1 budget 5")
	failed += _expect(int(t.floors[4].enemy_budget) == 6, "boss floor budget 6")
	for i in range(t.floors.size()):
		failed += _expect(t.floors[i].theme != null, "floor %d has a theme" % (i + 1))
		failed += _expect(t.floors[i].layout != null, "floor %d has a layout" % (i + 1))
	# Boss arena is clean (no crates); floor 1 has the full crate set.
	failed += _expect((t.floors[4].layout.crate_positions as Array).size() == 0, "boss floor has no crates")
	failed += _expect((t.floors[0].layout.crate_positions as Array).size() == 6, "floor 1 has 6 crates")
	# Deeper floors lean brutier.
	failed += _expect(float(t.floors[4].brute_chance) > float(t.floors[0].brute_chance), "brute mix ramps with depth")
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
