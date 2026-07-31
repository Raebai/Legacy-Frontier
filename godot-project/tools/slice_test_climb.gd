# Run: godot --headless --path godot-project --script tools/slice_test_climb.gd
# Persistent-climb spine (floors step 5). GameState's climber save/parse + fall
# math are static + pure, so they test with no scene, no Ollama, no change_scene.
# One isolated disk round-trip uses a throwaway user:// path so the maker's real
# climber.json is never touched. Runs on the first _process frame per repo idiom.
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
	"fall_floor",
	"climber_save_shape",
	"parse_json_float_trap",
	"outcome_carries_falls",
	"fact_mentions_falls",
	"climber_disk_roundtrip",
	"fall_transition",
	"advance_and_bank",
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
	_test_fall_floor(GS)
	_test_climber_save_shape(GS)
	_test_parse_json_float_trap(GS)
	_test_outcome_carries_falls(GS)
	_test_fact_mentions_falls(GS)
	_test_climber_disk_roundtrip(GS)
	_test_fall_transition(GS)
	_test_advance_and_bank(GS)
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Climb spine tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Climb spine tests: all PASS")
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


func _test_fall_floor(GS: GDScript) -> void:
	# THE TOWER spec: a fall costs ONE floor, never more.
	_expect(int(GS.fall_floor(5)) == 4, "fall from 5 -> 4")
	_expect(int(GS.fall_floor(3)) == 2, "fall from 3 -> 2")
	_expect(int(GS.fall_floor(2)) == 1, "fall from 2 -> 1")
	_expect(int(GS.fall_floor(1)) == 1, "fall from 1 clamps to 1")
	_completes("fall_floor")


func _test_climber_save_shape(GS: GDScript) -> void:
	var s: Dictionary = GS.build_climber_save(4, 6, 2, true, 40)
	_expect(int(s["version"]) == int(GS.CLIMBER_SAVE_VERSION), "version stamped")
	_expect(int(s["current_floor"]) == 4, "current floor carried")
	_expect(int(s["highest_floor"]) == 6, "highest floor carried")
	_expect(int(s["falls"]) == 2, "falls carried")
	_expect(bool(s["tower_conquered"]) == true, "conquered carried")
	_expect(int(s["rank_power"]) == 40, "rank power carried")
	# highest is clamped to be >= current even if a caller passes a stale value.
	var s2: Dictionary = GS.build_climber_save(5, 3, 0, false, 0)
	_expect(int(s2["highest_floor"]) == 5, "highest clamps up to current")
	# floors/falls/power never go below their floors.
	var s3: Dictionary = GS.build_climber_save(0, 0, -3, false, -9)
	_expect(int(s3["current_floor"]) == 1, "current floor floored at 1")
	_expect(int(s3["falls"]) == 0, "falls floored at 0")
	_expect(int(s3["rank_power"]) == 0, "rank power floored at 0")
	_completes("climber_save_shape")


func _test_parse_json_float_trap(GS: GDScript) -> void:
	# The real trap: JSON.parse_string returns numbers as TYPE_FLOAT. parse_climber_save
	# MUST coerce every int field or reloads corrupt (M9 lesson). Round-trip through
	# actual JSON text to reproduce the float typing authentically.
	var payload: Dictionary = GS.build_climber_save(4, 6, 2, true, 40)
	var text: String = JSON.stringify(payload)
	var back: Variant = JSON.parse_string(text)
	_expect(typeof(back) == TYPE_DICTIONARY, "JSON parses back to a dict")
	var state: Dictionary = GS.parse_climber_save(back)
	_expect(typeof(state["current_floor"]) == TYPE_INT, "current floor coerced to int")
	_expect(typeof(state["highest_floor"]) == TYPE_INT, "highest floor coerced to int")
	_expect(typeof(state["falls"]) == TYPE_INT, "falls coerced to int")
	_expect(typeof(state["rank_power"]) == TYPE_INT, "rank power coerced to int")
	_expect(int(state["current_floor"]) == 4, "current value survives")
	_expect(int(state["highest_floor"]) == 6, "highest value survives")
	_expect(bool(state["tower_conquered"]) == true, "conquered value survives")
	# A malformed/empty dict yields safe defaults (fresh climber).
	var empty: Dictionary = GS.parse_climber_save({})
	_expect(int(empty["current_floor"]) == 1, "empty parse -> floor 1")
	_expect(int(empty["falls"]) == 0, "empty parse -> 0 falls")
	_completes("parse_json_float_trap")


func _test_outcome_carries_falls(GS: GDScript) -> void:
	# 8-arg call carries falls.
	var o: Dictionary = GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber", 4)
	_expect(int(o["falls"]) == 4, "outcome carries falls when passed")
	# 7-arg legacy call still works (default 0) — proves backward compat.
	var o2: Dictionary = GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber")
	_expect(int(o2["falls"]) == 0, "outcome falls defaults to 0")
	_completes("outcome_carries_falls")


func _test_fact_mentions_falls(GS: GDScript) -> void:
	var many: String = GS.build_run_fact(GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber", 3))
	_expect(many.contains("3 falls"), "death fact names the fall count")
	# With 0 falls the fact is unchanged (still contains the base death text).
	var zero: String = GS.build_run_fact(GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber", 0))
	_expect(zero.contains("floor 3") and not zero.contains("falls so far"), "0 falls omits the clause")
	_completes("fact_mentions_falls")


func _test_climber_disk_roundtrip(GS: GDScript) -> void:
	# Isolated disk round-trip through a THROWAWAY path so the real climber.json is
	# untouched. Proves the atomic tmp-rename write + the load path together.
	var test_path: String = "user://climber_test.json"
	var gs: Node = GS.new()
	gs._floor = 4
	gs._highest_floor = 6
	gs._falls = 2
	gs.tower_conquered = true
	gs._saved_rank_power = 40
	gs._save_climber(test_path)
	var gs2: Node = GS.new()
	gs2._load_climber(test_path)
	_expect(gs2._floor == 4, "current floor round-trips")
	_expect(gs2._highest_floor == 6, "highest floor round-trips")
	_expect(gs2._falls == 2, "falls round-trips")
	_expect(gs2.tower_conquered == true, "conquered round-trips")
	_expect(gs2._saved_rank_power == 40, "rank power round-trips")
	_expect(typeof(gs2._floor) == TYPE_INT, "loaded floor is int not float")
	var d: DirAccess = DirAccess.open("user://")
	if d != null:
		d.remove("climber_test.json")
	gs.free()
	gs2.free()
	_completes("climber_disk_roundtrip")


## fall() on a live run drops ONE floor, ticks the fall counter, and emits `fell`
## with the dropped floor. Driven on a bare instance (no scene) — _change_scene
## is guarded on get_tree()==null so it no-ops off-tree.
func _test_fall_transition(GS: GDScript) -> void:
	var gs: Node = GS.new()
	gs.active_tower = GS.build_default_tower()
	gs._run_active = true
	gs._floor = 5
	gs._falls = 1
	var seen: Array = []
	gs.fell.connect(func(nf: int) -> void: seen.append(nf))
	gs.fall()
	_expect(gs._floor == 4, "fall drops one floor (5 -> 4)")
	_expect(gs._falls == 2, "fall increments the fall counter")
	_expect(seen.size() == 1 and int(seen[0]) == 4, "fell emitted with the dropped floor")
	# A fall in the SANDBOX (no active run) is a no-op.
	var gs2: Node = GS.new()
	gs2._run_active = false
	gs2._floor = 4
	gs2.fall()
	_expect(gs2._floor == 4, "sandbox fall is a no-op")
	gs.free()
	gs2.free()
	_completes("fall_transition")


## advance_floor on a non-final floor banks the next floor + lifts highest.
func _test_advance_and_bank(GS: GDScript) -> void:
	var gs: Node = GS.new()
	gs.active_tower = GS.build_default_tower()   # 5 floors
	gs._run_active = true
	gs._floor = 2
	gs._highest_floor = 2
	var advanced: Array = []
	gs.floor_advanced.connect(func(nf: int) -> void: advanced.append(nf))
	gs.advance_floor()
	_expect(gs._floor == 3, "advance climbs to the next floor")
	_expect(gs._highest_floor == 3, "highest floor tracks the climb")
	_expect(advanced.size() == 1 and int(advanced[0]) == 3, "floor_advanced emitted")
	# Advancing past the last floor conquers (no floor_advanced; conquered flag set).
	var gs2: Node = GS.new()
	gs2.active_tower = GS.build_default_tower()
	gs2._run_active = true
	gs2._floor = 5
	gs2._highest_floor = 5
	var advanced2: Array = []
	gs2.floor_advanced.connect(func(nf: int) -> void: advanced2.append(nf))
	gs2.advance_floor()
	_expect(gs2.tower_conquered == true, "clearing the last floor conquers the tower")
	_expect(advanced2.is_empty(), "conquer does not emit floor_advanced")
	gs.free()
	gs2.free()
	_completes("advance_and_bank")
