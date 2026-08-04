# Run: godot --headless --path godot-project --script tools/slice_test_xp_flow.gd
#
# XP END TO END, through the real run spine and the real authored tower.
#
# ⚠ WHY THIS EXISTS ON TOP OF `slice_test_progression`. That suite proves the CURVE
# — pure functions, exact identities, the farm meter. It cannot prove that a single
# XP ever reaches a player, because it never touches `GameState`. This project's own
# standing lesson is that integration is where the surviving bugs live: `TOTAL_FLOORS`
# was raised to 10 while `total_floors()` kept answering 5, every climb test passed,
# and a wipe silently became a total reset.
#
# So this one PLAYS a floor: kills the bodies, fells the guardian, takes the exit,
# and asserts a level actually arrived.
extends SceneTree

const TESTS: Array[String] = [
	"a_cleared_floor_is_worth_its_authored_value",
	"the_purse_holds_against_a_summoner",
	"a_client_banks_relayed_xp_without_re_broadcasting",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const GS_PATH: String = "res://scripts/GameState.gd"


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var GS: GDScript = load(GS_PATH) as GDScript
	_test_a_cleared_floor_is_worth_its_authored_value(GS)
	_test_the_purse_holds_against_a_summoner(GS)
	_test_a_client_banks_relayed_xp_without_re_broadcasting(GS)
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("XP flow tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("XP flow tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Build a live-run GameState sitting on `floor`, with its purse open.
func _running(GS: GDScript, floor: int) -> Node:
	var gs: Node = GS.new()
	gs.active_tower = GS.build_default_tower()
	gs._xp = 0
	gs._run_active = true
	gs._floor = floor
	gs._open_floor_purse()
	return gs


## How many bodies a floor authors — the same sum the economy divides by.
func _bodies(gs: Node, floor: int) -> int:
	var fd: FloorDef = gs.floor_def_for(floor)
	var total: int = 0
	for w: WaveDef in fd.waves:
		total += maxi(w.enemy_budget, 0)
	return maxi(total, 1)


## Clearing a floor properly must pay ROUGHLY what the curve says the floor is
## worth — the three channels summing back to the whole. Rounding makes it
## approximate rather than exact (per-enemy XP is an int), so this asserts a band.
func _test_a_cleared_floor_is_worth_its_authored_value(GS: GDScript) -> void:
	var gs: Node = _running(GS, 1)
	var levels: Array = []
	gs.leveled_up.connect(func(l: int) -> void: levels.append(l))
	for i: int in _bodies(gs, 1):
		gs.notify_kill()
	gs.notify_guardian_killed()
	gs.advance_floor()
	var worth: float = Progression.floor_xp_value(1)
	_expect(float(gs._xp) >= worth * 0.85 and float(gs._xp) <= worth * 1.15,
		"a fully cleared floor 1 pays about what it is worth (%d vs %.0f)" % [gs._xp, worth])
	_expect(gs.level() >= 2, "…which is enough for at least one level (got %d)" % gs.level())
	_expect(levels.size() >= 1, "…and `leveled_up` actually fired")
	_expect(gs._floor == 2, "…and the climb advanced")
	# A DEEPER floor pays more for the same act. The maker's line, end to end.
	var deep: Node = _running(GS, gs.total_floors())
	for i: int in _bodies(deep, deep.total_floors()):
		deep.notify_kill()
	deep.notify_guardian_killed()
	deep.advance_floor()
	_expect(deep._xp > gs._xp,
		"clearing the TOP floor pays more than clearing floor 1 (%d vs %d)" % [deep._xp, gs._xp])
	gs.free()
	deep.free()
	_completes("a_cleared_floor_is_worth_its_authored_value")


## ⚠ THE FARM VECTOR THE PURSE EXISTS FOR. A SUMMONER's minions, a boss's adds and
## the Warlock's own thralls are all bodies the floor never authored. Without the
## purse, standing next to a summoner on floor 1 would mint XP forever and be the
## best farm in the game — and it would look completely normal while doing it.
func _test_the_purse_holds_against_a_summoner(GS: GDScript) -> void:
	var gs: Node = _running(GS, 1)
	var authored: int = _bodies(gs, 1)
	# Kill FIVE TIMES the floor's authored population.
	for i: int in authored * 5:
		gs.notify_kill()
	var cap: int = int(round(Progression.floor_xp_value(1) * Progression.KILL_SHARE))
	_expect(gs._xp <= cap,
		"%d kills on a %d-body floor cannot out-earn the floor's kill share (%d vs cap %d)"
			% [authored * 5, authored, gs._xp, cap])
	# ⚠ NON-VACUOUS: a purse that pays NOTHING would also satisfy the line above.
	_expect(gs._xp > 0, "…while still actually paying for the kills it should")
	_expect(gs._xp >= cap / 2, "…and paying most of the share, not a token")
	gs.free()
	_completes("the_purse_holds_against_a_summoner")


## The co-op relay. `receive_net_xp` must bank exactly what it is handed — a client
## that silently dropped it would level only from floor transitions, which fails in
## the direction that still looks correct.
func _test_a_client_banks_relayed_xp_without_re_broadcasting(GS: GDScript) -> void:
	var gs: Node = GS.new()
	gs._xp = 0
	var seen: Array = []
	gs.xp_gained.connect(func(a: int, k: String, _w: Vector2) -> void: seen.append([a, k]))
	gs.receive_net_xp(250, "kill", Vector2.ZERO)
	_expect(gs._xp == 250, "a relayed grant is banked verbatim (got %d)" % gs._xp)
	_expect(seen.size() == 1 and String(seen[0][1]) == "kill", "…and reported once, with its kind")
	_expect(gs.level() == Progression.level_for_xp(250), "…and the level follows from it")
	# A zero or negative grant is a no-op rather than a signal storm.
	gs.receive_net_xp(0, "kill", Vector2.ZERO)
	gs.receive_net_xp(-99, "kill", Vector2.ZERO)
	_expect(gs._xp == 250 and seen.size() == 1, "junk grants change nothing and say nothing")
	gs.free()
	_completes("a_client_banks_relayed_xp_without_re_broadcasting")
