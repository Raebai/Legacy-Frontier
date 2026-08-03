# Run: godot --headless --path godot-project --script tools/slice2_test_runloop.gd
# GameState.gd is an autoload script; its outcome/fact builders and floor math
# are static + pure, so they are called directly off the loaded GDScript with no
# scene, no Ollama, no change_scene. Runs on the first _process frame per the
# repo idiom.
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
	"build_outcome",
	"build_run_fact",
	"run_hint_text",
	"merge_run_fact",
	"ingest_run_fact",
	"floor_math",
	"floor_def_synthesis",
	"tower_authoring",
]

var _fails: int = 0
var _completed: Dictionary = {}

const GS_PATH: String = "res://scripts/GameState.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var GS: GDScript = load(GS_PATH) as GDScript
	_test_build_outcome(GS)
	_test_build_run_fact(GS)
	_test_run_hint_text(GS)
	_test_merge_run_fact(GS)
	_test_ingest_run_fact(GS)
	_test_floor_math(GS)
	_test_floor_def_synthesis(GS)
	_test_tower_authoring(GS)
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice2 runloop tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice2 runloop tests: all PASS")
		quit(0)
	return true


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


func _test_build_outcome(GS: GDScript) -> void:
	var o: Dictionary = GS.build_outcome(3, 11, false, true, ["Fire", "Shadow"], 2, "Ranked")
	_expect(int(o["floor_reached"]) == 3, "floor_reached carried")
	_expect(int(o["enemies_killed"]) == 11, "enemies_killed carried")
	_expect(bool(o["died"]) == true, "died carried")
	_expect(bool(o["cleared"]) == false, "cleared == not died")
	_expect(String(o["rank_title"]) == "Ranked", "rank_title carried")
	_expect((o["elements_used"] as Array).size() == 2, "elements coerced to array")
	_expect(String((o["elements_used"] as Array)[0]) == "Fire", "element stringified")
	var o2: Dictionary = GS.build_outcome(5, 40, true, false, [], 5, "Ascendant")
	_expect(bool(o2["cleared"]) == true, "cleared true when not died")
	_expect(bool(o2["boss_killed"]) == true, "boss_killed carried")
	_completes("build_outcome")


func _test_build_run_fact(GS: GDScript) -> void:
	var died: String = GS.build_run_fact(GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber"))
	_expect(died.begins_with(GS.RUN_FACT_PREFIX), "died fact carries prefix")
	_expect(died.contains("floor 3"), "died fact names the floor")
	_expect(died.contains("fire"), "died fact lowercases element")
	var won: String = GS.build_run_fact(GS.build_outcome(5, 40, true, false, ["Ice"], 5, "Ascendant"))
	_expect(won.contains("guardian"), "boss fact mentions the guardian")
	var alive: String = GS.build_run_fact(GS.build_outcome(2, 5, false, false, [], 1, "Climber"))
	_expect(alive.contains("alive"), "cleared-but-not-boss fact reads 'alive'")
	_expect(alive.begins_with(GS.RUN_FACT_PREFIX), "alive fact carries prefix")
	_completes("build_run_fact")


func _test_run_hint_text(GS: GDScript) -> void:
	var died: String = GS.run_hint_text(GS.build_outcome(4, 9, false, true, [], 2, "Ranked"))
	_expect(died.contains("died") and died.contains("floor 4"), "death hint is specific")
	var won: String = GS.run_hint_text(GS.build_outcome(5, 40, true, false, [], 5, "Ascendant"))
	_expect(won.contains("guardian"), "victory hint mentions the guardian")
	_completes("run_hint_text")


func _test_merge_run_fact(GS: GDScript) -> void:
	var f1: String = GS.RUN_FACT_PREFIX + "walked out of floor 2 alive"
	var merged: Array = GS.merge_run_fact([], f1, 5)
	_expect(merged.size() == 1 and String(merged[0]) == f1, "append into empty")
	# A second run fact REPLACES the first (only one run-marked entry survives).
	var f2: String = GS.RUN_FACT_PREFIX + "fell on floor 3"
	var merged2: Array = GS.merge_run_fact(merged, f2, 5)
	var run_marked: int = 0
	for f in merged2:
		if String(f).begins_with(GS.RUN_FACT_PREFIX):
			run_marked += 1
	_expect(run_marked == 1, "exactly one run-marked fact survives")
	_expect(String(merged2[merged2.size() - 1]) == f2, "newest run fact is last")
	# Non-run facts are preserved.
	var with_durable: Array = GS.merge_run_fact(["name is Ari", f1], f2, 5)
	_expect(with_durable.has("name is Ari"), "durable fact preserved through merge")
	# Cap is enforced by oldest-drop.
	var capped: Array = GS.merge_run_fact(["a", "b", "c", "d", "e"], f2, 5)
	_expect(capped.size() == 5, "cap enforced")
	_expect(not capped.has("a"), "oldest dropped under cap")
	_expect(String(capped[capped.size() - 1]) == f2, "run fact kept as newest")
	_completes("merge_run_fact")


func _test_ingest_run_fact(GS: GDScript) -> void:
	var stub := _NpcStub.new()
	GS.ingest_run_fact(stub, GS.RUN_FACT_PREFIX + "fell on floor 2")
	_expect(stub.relationships.has("player"), "player relationship auto-created")
	_expect(stub.saved, "save_memory called after ingest")
	var kf: Array = stub.relationships["player"]["key_facts"]
	_expect(kf.size() == 1, "one key fact after first ingest")
	# A second run replaces, not appends.
	GS.ingest_run_fact(stub, GS.RUN_FACT_PREFIX + "cleared floor 5")
	var kf2: Array = stub.relationships["player"]["key_facts"]
	_expect(kf2.size() == 1, "second run replaces the first (still one)")
	_expect(String(kf2[0]).contains("floor 5"), "latest run fact wins")
	_completes("ingest_run_fact")


func _test_floor_math(GS: GDScript) -> void:
	_expect(int(GS.floor_enemy_budget(1)) == 4, "floor 1 budget 4")
	_expect(int(GS.floor_enemy_budget(5)) == 12, "floor 5 budget 12")
	_expect(int(GS.floor_enemy_budget(1)) < int(GS.floor_enemy_budget(3)), "budget ramps")
	_expect(int(GS.floor_concurrent_cap(1)) >= 3, "cap floor >= 3")
	_expect(int(GS.floor_concurrent_cap(9)) <= 7, "cap ceilinged at 7")
	_expect(float(GS.floor_brute_chance(1)) < float(GS.floor_brute_chance(5)), "brute mix ramps")
	_expect(String(GS.floor_theme(1)) == "surface", "floor 1 is surface")
	_expect(String(GS.floor_theme(3)) == "underground", "floor 3 is underground")
	_expect(String(GS.floor_theme(5)) == "sky", "floor 5 is sky")
	_completes("floor_math")


## Synthesized FloorDef (null-tower fallback) must match the depth math exactly,
## so routing Arena through FloorDef is a byte-identical behaviour change.
func _test_floor_def_synthesis(GS: GDScript) -> void:
	for floor in [1, 3, 5]:
		var fd: Resource = GS.synthesize_floor_def(floor)
		_expect(int(fd.enemy_budget) == int(GS.floor_enemy_budget(floor)),
			"floor %d budget matches math" % floor)
		_expect(int(fd.concurrent_cap) == int(GS.floor_concurrent_cap(floor)),
			"floor %d cap matches math" % floor)
		_expect(is_equal_approx(float(fd.brute_chance), float(GS.floor_brute_chance(floor))),
			"floor %d brute_chance matches math" % floor)
		_expect(String(fd.theme.name) == String(GS.floor_theme(floor)),
			"floor %d theme name matches math" % floor)
		_expect(fd.theme.wash_tint == GS.floor_theme_tint(floor),
			"floor %d theme tint matches math" % floor)
	# TRASH HP IS FLAT AT EVERY DEPTH. This assertion was inverted deliberately:
	# it used to demand `synthesize_floor_def(5).hp_multiplier > 1.0`, which is the
	# exact thing the spec forbids — "higher floors add modifiers, not HP. HP
	# scaling makes fights longer, not harder, and long is the enemy of chaos on a
	# phone." Depth now rides on brute_chance (asserted above) and on the
	# GUARDIAN's own curve (asserted below), where a longer committed duel is the
	# point rather than an accident.
	for floor in [1, 3, 5]:
		_expect(is_equal_approx(float(GS.synthesize_floor_def(floor).hp_multiplier), 1.0),
			"floor %d trash hp_multiplier stays 1.0 (depth is the MIX, not HP)" % floor)
	_expect(is_equal_approx(float(GS.synthesize_floor_def(1).boss_hp_multiplier), 1.0),
		"floor 1 guardian is unscaled")
	_expect(float(GS.synthesize_floor_def(5).boss_hp_multiplier) > 1.0,
		"the GUARDIAN's hp curve is where depth scaling survives")
	_completes("floor_def_synthesis")


## The default Ashspire tower is a 5-floor typed spine ending in a BOSS.
func _test_tower_authoring(GS: GDScript) -> void:
	var t: Resource = GS.build_default_tower()
	_expect(t.floors.size() == 5, "Ashspire has 5 floors")
	# FloorType: COMBAT=0, ELITE=1, BOSS=2.
	_expect(int(t.floors[0].floor_type) == 0, "floor 1 is COMBAT")
	_expect(int(t.floors[2].floor_type) == 1, "floor 3 is ELITE")
	_expect(int(t.floors[4].floor_type) == 2, "floor 5 is BOSS")
	# THE TOWER shape (1.1): every floor is 3-5 escalating waves, and the flat
	# enemy_budget field is kept as the SUM of those waves so anything still
	# reading it — including Encounter's synthesized-wave fallback — agrees.
	for i in range(t.floors.size()):
		var waves: Array = t.floors[i].waves
		_expect(waves.size() >= 3 and waves.size() <= 5,
			"floor %d has 3-5 waves (got %d)" % [i + 1, waves.size()])
		var total: int = 0
		var prev: int = 0
		var monotonic: bool = true
		for w in waves:
			total += int(w.enemy_budget)
			if int(w.enemy_budget) < prev:
				monotonic = false
			prev = int(w.enemy_budget)
		_expect(monotonic, "floor %d waves never shrink (they escalate)" % (i + 1))
		_expect(int(t.floors[i].enemy_budget) == total,
			"floor %d enemy_budget (%d) is the sum of its waves (%d)"
				% [i + 1, int(t.floors[i].enemy_budget), total])
	# Deeper floors are longer fights.
	_expect((t.floors[4].waves as Array).size() > (t.floors[0].waves as Array).size(),
		"the summit floor runs more waves than floor 1")
	for i in range(t.floors.size()):
		_expect(t.floors[i].theme != null, "floor %d has a theme" % (i + 1))
		_expect(t.floors[i].layout != null, "floor %d has a layout" % (i + 1))
	# Boss arena is clean (no crates); floor 1 has the full crate set.
	_expect((t.floors[4].layout.crate_positions as Array).size() == 0, "boss floor has no crates")
	_expect((t.floors[0].layout.crate_positions as Array).size() == 6, "floor 1 has 6 crates")
	# Deeper floors lean brutier.
	_expect(float(t.floors[4].brute_chance) > float(t.floors[0].brute_chance), "brute mix ramps with depth")
	# ESCALATION IS THE MIX, NOT THE HP. Every authored floor runs trash at 1.0 and
	# names WHO shows up per wave; the depth curve lives on the guardian alone. If
	# someone reaches for an hp_multiplier to make a floor harder, this fails.
	var rosters: int = 0
	for i in range(t.floors.size()):
		_expect(is_equal_approx(float(t.floors[i].hp_multiplier), 1.0),
			"floor %d trash hp_multiplier is 1.0 (escalate the MIX, not the HP)" % (i + 1))
		for w in (t.floors[i].waves as Array):
			if not (w.archetypes as Array).is_empty():
				rosters += 1
	_expect(rosters == int(t.floors[0].waves.size() + t.floors[1].waves.size()
			+ t.floors[2].waves.size() + t.floors[3].waves.size() + t.floors[4].waves.size()),
		"every authored wave names its own archetype roster (got %d)" % rosters)
	_expect(float(t.floors[4].boss_hp_multiplier) > float(t.floors[0].boss_hp_multiplier),
		"the guardian's hp curve ramps with depth")
	_completes("tower_authoring")


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
