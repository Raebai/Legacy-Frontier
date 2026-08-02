# Run: godot --headless --path godot-project --script tools/slice_test_waves.gd
# THE TOWER's floor shape (Phase 1.1 / 1.2 / 1.4): a floor is 3-5 escalating
# WAVES with a beat between them, then a boss, and the floor is cleared only when
# the boss is dead. Plus the live-entity cap that Encounter now owns.
#
# The wave MATH (synthesize_waves / split_budget / boss_scale_for_type) is static
# + pure, so it tests with no tree at all. The wave SEQUENCE is driven by hand
# through Encounter._process against a real (tiny) arena, so the assertions are
# about behaviour rather than about fields having values.
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
	"split_budget_is_exact",
	"synthesized_waves_escalate",
	"authored_waves_win",
	"wave_inheritance",
	"boss_scale_by_type",
	"waves_run_in_order",
	"break_between_waves",
	"boss_only_after_last_wave",
	"cleared_waits_for_the_boss",
	"rest_floor_has_no_boss",
	"entity_cap_math",
	"cap_gates_wave_spawning",
	"pacing_math",
	"vanguard_lands_together",
	"waves_overlap_so_the_room_is_never_empty",
	"wave_cleared_fires_once_per_wave",
	"roster_forces_the_archetype_mix",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const GS_PATH: String = "res://scripts/GameState.gd"

## Encounter.Phase, restated here so a rename over there fails loudly rather than
## silently comparing against a stale literal.
const PHASE_IDLE: int = 0
const PHASE_WAVES: int = 1
## Was PHASE_BREAK — a silent 1.5s pause between waves. It is now the SURGE: a
## short LOUD beat that the previous wave's stragglers usually fight you through.
## Same ordinal; renamed here so the assertions read as what they now mean.
const PHASE_SURGE: int = 2
const PHASE_BOSS: int = 3
const PHASE_DONE: int = 4


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_split_budget_is_exact()
	_test_synthesized_waves_escalate()
	_test_authored_waves_win()
	_test_wave_inheritance()
	_test_boss_scale_by_type()
	_test_waves_run_in_order()
	_test_break_between_waves()
	_test_boss_only_after_last_wave()
	_test_cleared_waits_for_the_boss()
	_test_rest_floor_has_no_boss()
	_test_entity_cap_math()
	_test_cap_gates_wave_spawning()
	_test_pacing_math()
	_test_vanguard_lands_together()
	_test_waves_overlap_so_the_room_is_never_empty()
	_test_wave_cleared_fires_once_per_wave()
	_test_roster_forces_the_archetype_mix()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Wave tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Wave tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ fixtures
## A bare arena + encounter. The encounter's own _process is DISABLED so every
## test drives the sequence by hand and nothing advances behind an assertion.
func _make_encounter() -> Array:
	var arena := Node2D.new()
	root.add_child(arena)
	var enc: Node = load(ENCOUNTER_PATH).new()
	arena.add_child(enc)
	enc.set_process(false)
	return [arena, enc]


func _floor_with(waves: Array, type: int = FloorDef.FloorType.COMBAT) -> FloorDef:
	var fd := FloorDef.new()
	fd.floor_type = type
	fd.layout = LayoutDef.new()
	fd.wave_break = 1.5
	fd.hp_multiplier = 1.0
	fd.brute_chance = 0.3
	var list: Array[WaveDef] = []
	var total: int = 0
	for row: Array in waves:
		var w := WaveDef.new()
		w.enemy_budget = int(row[0])
		w.concurrent_cap = int(row[1])
		w.spawn_interval = 0.0   # tests care about ORDER, not pacing
		list.append(w)
		total += int(row[0])
	fd.waves = list
	fd.enemy_budget = total
	return fd


## Advance the encounter by `steps` ticks of `dt`, wiping the room BEFORE each
## tick so waves complete. Killing before the tick (not after) is load-bearing: a
## tick can spawn the guardian, and killing after would delete it in the same
## breath it arrived. Wiping also stops at the boss phase, so the guardian is left
## standing for the assertions that are about it.
func _tick(enc: Node, steps: int, dt: float = 0.5, kill: bool = true) -> int:
	for i: int in steps:
		if kill and int(enc.call("phase")) != PHASE_BOSS:
			for e: Node in get_nodes_in_group("enemy"):
				e.free()   # free(), not queue_free(): the gate re-reads the group NOW
		enc.call("_process", dt)
	return int(enc.call("phase"))


func _clear_arena(arena: Node) -> void:
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	arena.free()


# --------------------------------------------------------------- pure wave math
## The split must be EXACT. If it were not, a floor authored as "12 enemies"
## would quietly become an 11- or 13-enemy floor the day someone leaned on the
## synthesized path, and nobody would ever catch it by eye.
func _test_split_budget_is_exact() -> void:
	var enc_script: GDScript = load(ENCOUNTER_PATH) as GDScript
	for total: int in range(1, 40):
		var shares: Array = enc_script.split_budget(total, 3)
		var sum: int = 0
		var min_share: int = 1 << 30
		for s: int in shares:
			sum += int(s)
			min_share = mini(min_share, int(s))
		_expect(sum == total, "split of %d sums back to %d (got %d)" % [total, total, sum])
		_expect(min_share >= 1, "split of %d gives every wave at least one enemy" % total)
		_expect(shares.size() == mini(3, total),
			"split of %d across 3 yields %d shares" % [total, mini(3, total)])
	# Degenerate inputs are empty lists, not crashes.
	_expect((enc_script.split_budget(0, 3) as Array).is_empty(), "a 0 budget splits into nothing")
	_expect((enc_script.split_budget(5, 0) as Array).is_empty(), "0 waves splits into nothing")
	_completes("split_budget_is_exact")


## The fallback for a FloorDef that predates waves: a 3-wave escalating shape
## whose totals match the old flat budget exactly.
func _test_synthesized_waves_escalate() -> void:
	var enc_script: GDScript = load(ENCOUNTER_PATH) as GDScript
	var waves: Array = enc_script.synthesize_waves(12, 4, 0.3)
	_expect(waves.size() == 3, "a 12-enemy floor synthesizes 3 waves (got %d)" % waves.size())
	var total: int = 0
	var prev_budget: int = 0
	var prev_cap: int = 0
	var budgets_grow: bool = true
	var caps_grow: bool = true
	for w in waves:
		total += int(w.enemy_budget)
		if int(w.enemy_budget) < prev_budget:
			budgets_grow = false
		if int(w.concurrent_cap) < prev_cap:
			caps_grow = false
		prev_budget = int(w.enemy_budget)
		prev_cap = int(w.concurrent_cap)
	_expect(total == 12, "synthesized waves still add up to the floor's budget (got %d)" % total)
	_expect(budgets_grow, "synthesized waves get BIGGER, not smaller")
	_expect(caps_grow, "synthesized concurrent caps ramp with the waves")
	_expect(float(waves[2].brute_chance) > float(waves[0].brute_chance),
		"the last synthesized wave leans nastier than the first")
	# A REST floor (budget 0) has no waves at all.
	_expect((enc_script.synthesize_waves(0, 3, 0.3) as Array).is_empty(),
		"a 0-budget floor synthesizes no waves")
	_completes("synthesized_waves_escalate")


## An authored wave list is used VERBATIM — synthesis is only the fallback.
func _test_authored_waves_win() -> void:
	var enc_script: GDScript = load(ENCOUNTER_PATH) as GDScript
	var fd: FloorDef = _floor_with([[7, 2], [1, 9]])
	var resolved: Array = enc_script.resolved_waves(fd)
	_expect(resolved.size() == 2, "the authored list is used as-is (got %d waves)" % resolved.size())
	_expect(int(resolved[0].enemy_budget) == 7 and int(resolved[1].concurrent_cap) == 9,
		"authored budgets/caps are not rewritten by the synthesizer")
	# ...and an EMPTY list falls back rather than producing a floor with no fight.
	var bare := FloorDef.new()
	bare.enemy_budget = 6
	bare.concurrent_cap = 3
	_expect((enc_script.resolved_waves(bare) as Array).size() == 3,
		"a floor with no authored waves still gets a wave list")
	_expect(enc_script.resolved_waves(null).is_empty(), "a null floor resolves to no waves")
	_completes("authored_waves_win")


## A wave's difficulty fields are "< 0 = inherit the floor", so a wave table can
## be about pacing alone.
func _test_wave_inheritance() -> void:
	var w := WaveDef.new()
	_expect(is_equal_approx(w.resolved_brute(0.42), 0.42), "default brute_chance inherits the floor")
	_expect(is_equal_approx(w.resolved_hp(1.3), 1.3), "default hp_multiplier inherits the floor")
	_expect(is_equal_approx(w.resolved_interval(0.55), 0.55), "default interval inherits the encounter")
	w.brute_chance = 0.9
	w.hp_multiplier = 2.0
	w.spawn_interval = 0.1
	_expect(is_equal_approx(w.resolved_brute(0.42), 0.9), "an explicit brute_chance overrides")
	_expect(is_equal_approx(w.resolved_hp(1.3), 2.0), "an explicit hp_multiplier overrides")
	_expect(is_equal_approx(w.resolved_interval(0.55), 0.1), "an explicit interval overrides")
	_completes("wave_inheritance")


## Every floor ends on a guardian, but only a BOSS floor gets the full colossus.
func _test_boss_scale_by_type() -> void:
	var enc_script: GDScript = load(ENCOUNTER_PATH) as GDScript
	var full: float = enc_script.boss_scale_for_type(FloorDef.FloorType.BOSS)
	var elite: float = enc_script.boss_scale_for_type(FloorDef.FloorType.ELITE)
	var combat: float = enc_script.boss_scale_for_type(FloorDef.FloorType.COMBAT)
	_expect(is_equal_approx(full, 1.0), "a BOSS floor gets the guardian at full strength")
	_expect(combat < elite and elite < full, "COMBAT < ELITE < BOSS guardian scale")
	_expect(combat > 0.0, "even a COMBAT floor's guardian is a real fight, not a zero")
	# An authored boss_scale beats the floor-type default.
	var fd: FloorDef = _floor_with([[2, 2]])
	fd.boss_scale = 0.8
	_expect(is_equal_approx(enc_script.resolved_boss_scale(fd), 0.8), "authored boss_scale wins")
	fd.boss_scale = 0.0
	_expect(is_equal_approx(enc_script.resolved_boss_scale(fd), combat),
		"boss_scale 0 falls back to the floor type")
	_completes("boss_scale_by_type")


# --------------------------------------------------------------- wave sequence
## Waves run in the authored order, and each one only spawns its OWN budget.
func _test_waves_run_in_order() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var seen: Array = []
	enc.connect("wave_started", func(idx: int, total: int) -> void: seen.append([idx, total]))
	enc.call("run_floor", _floor_with([[2, 3], [3, 3], [4, 4]]))
	_expect(int(enc.call("wave_count")) == 3, "the floor knows it has 3 waves")
	_expect(int(enc.call("current_wave")) == 0, "the first wave starts immediately")
	_expect(seen.size() == 1 and int(seen[0][0]) == 0 and int(seen[0][1]) == 3,
		"wave_started(0, 3) fired for the opener")
	# Drive the whole floor; each _tick kills what spawned, so waves complete.
	_tick(enc, 60)
	var indices: Array = []
	for row: Array in seen:
		indices.append(int(row[0]))
	_expect(indices == [0, 1, 2], "waves ran in order 0,1,2 (got %s)" % str(indices))
	_clear_arena(arena)
	_completes("waves_run_in_order")


## THE BEAT. A cleared wave does not roll straight into the next one — the room
## goes quiet for wave_break seconds first, which is the thing that makes a wave
## read as a wave instead of as a trickle.
func _test_break_between_waves() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var fd: FloorDef = _floor_with([[1, 3], [1, 3]])
	fd.wave_break = 1.5
	enc.call("run_floor", fd)
	# Spend + clear wave 0 with small ticks so we land INSIDE the break.
	var guard: int = 0
	while int(enc.call("phase")) == PHASE_WAVES and guard < 200:
		for e: Node in get_nodes_in_group("enemy"):
			e.free()
		enc.call("_process", 0.05)
		guard += 1
	_expect(int(enc.call("phase")) == PHASE_SURGE,
		"a cleared wave hands off to the BREAK, not straight to the next wave")
	_expect(int(enc.call("current_wave")) == 0, "the break still belongs to the wave that just ended")
	# Not long enough — still waiting.
	enc.call("_process", 0.5)
	_expect(int(enc.call("phase")) == PHASE_SURGE, "the break is a real wait, not one frame")
	# Long enough — wave 1 opens.
	enc.call("_process", 1.2)
	_expect(int(enc.call("phase")) == PHASE_WAVES, "the break ends and the next wave starts")
	_expect(int(enc.call("current_wave")) == 1, "...and it is the NEXT wave")
	_clear_arena(arena)
	_completes("break_between_waves")


## 1.2: no guardian while there is still a wave to fight, on any floor type.
func _test_boss_only_after_last_wave() -> void:
	for type: int in [FloorDef.FloorType.COMBAT, FloorDef.FloorType.ELITE, FloorDef.FloorType.BOSS]:
		var fx: Array = _make_encounter()
		var arena: Node = fx[0]
		var enc: Node = fx[1]
		var boss_calls: Array = []
		enc.connect("boss_spawned", func() -> void: boss_calls.append(int(enc.call("current_wave"))))
		enc.call("run_floor", _floor_with([[2, 3], [2, 3], [2, 3]], type))
		_expect(boss_calls.is_empty(), "type %d: no guardian at the door" % type)
		# Halfway through: still no boss.
		_tick(enc, 8, 0.4)
		if int(enc.call("phase")) != PHASE_BOSS:
			_expect(boss_calls.is_empty(), "type %d: no guardian mid-floor" % type)
		_tick(enc, 60)
		_expect(boss_calls.size() == 1, "type %d: exactly one guardian, after the waves" % type)
		_expect(int(enc.call("phase")) == PHASE_BOSS or int(enc.call("phase")) == PHASE_DONE,
			"type %d: the floor reached its boss phase" % type)
		_clear_arena(arena)
	_completes("boss_only_after_last_wave")


## The floor is cleared when the BOSS dies — not when the last wave dies.
func _test_cleared_waits_for_the_boss() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var cleared: Array = []
	enc.connect("cleared", func() -> void: cleared.append(true))
	enc.call("run_floor", _floor_with([[1, 3], [1, 3]]))
	# Run the waves down. The boss spawns; do NOT kill it yet.
	var guard: int = 0
	while int(enc.call("phase")) != PHASE_BOSS and guard < 400:
		for e: Node in get_nodes_in_group("enemy"):
			e.free()
		enc.call("_process", 0.5)
		guard += 1
	_expect(int(enc.call("phase")) == PHASE_BOSS, "the floor reached its boss phase")
	_expect(cleared.is_empty(), "clearing the last wave does NOT clear the floor")
	var boss_alive: int = get_nodes_in_group("enemy").size()
	_expect(boss_alive >= 1, "a guardian is actually standing there (got %d bodies)" % boss_alive)
	# Let it live a while: the floor must stay open.
	enc.call("_process", 1.0)
	enc.call("_process", 1.0)
	_expect(cleared.is_empty(), "the floor stays open while the guardian lives")
	# Kill it -> cleared.
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	enc.call("_process", 0.1)
	_expect(cleared.size() == 1, "the floor clears once the guardian is dead")
	_expect(int(enc.call("phase")) == PHASE_DONE, "...and the encounter is DONE")
	# ...and it only clears ONCE.
	enc.call("_process", 0.5)
	_expect(cleared.size() == 1, "a cleared floor does not re-clear")
	_clear_arena(arena)
	_completes("cleared_waits_for_the_boss")


## A REST floor is the deliberate exception: nothing to fight, and no guardian
## either. It clears the instant it starts.
func _test_rest_floor_has_no_boss() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var cleared: Array = []
	var bosses: Array = []
	enc.connect("cleared", func() -> void: cleared.append(true))
	enc.connect("boss_spawned", func() -> void: bosses.append(true))
	var fd := FloorDef.new()
	fd.floor_type = FloorDef.FloorType.REST
	fd.enemy_budget = 0
	fd.layout = LayoutDef.new()
	enc.call("run_floor", fd)
	_expect(cleared.size() == 1, "a REST floor clears immediately")
	_expect(bosses.is_empty(), "a REST floor summons no guardian")
	_expect(get_nodes_in_group("enemy").is_empty(), "a REST floor spawns nothing")
	_clear_arena(arena)
	# ...and the `no_boss` escape hatch does the same for a floor that DOES fight.
	var fx2: Array = _make_encounter()
	var enc2: Node = fx2[1]
	var bosses2: Array = []
	enc2.connect("boss_spawned", func() -> void: bosses2.append(true))
	var fd2: FloorDef = _floor_with([[1, 3]])
	fd2.special_tags = ["no_boss"]
	enc2.call("run_floor", fd2)
	_tick(enc2, 30)
	_expect(bosses2.is_empty(), "the `no_boss` tag opts a floor out of its guardian")
	_expect(int(enc2.call("phase")) == PHASE_DONE, "...and it still clears")
	_clear_arena(fx2[0])
	_completes("rest_floor_has_no_boss")


# ------------------------------------------------------------------ entity cap
## Encounter is the ONE authority on the live population, counting players and
## every enemy body (minions and boss adds are in "enemy" too).
func _test_entity_cap_math() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	_expect(int(enc.get("MAX_LIVE_ENTITIES")) == 25, "the cap is the spec's 25")
	_expect(int(enc.call("live_entity_count")) == 0, "an empty arena has nobody in it")
	_expect(int(enc.call("spawn_headroom")) == 25, "...so the whole budget is free")
	_expect(bool(enc.call("can_spawn", 25)), "25 fits exactly")
	_expect(not bool(enc.call("can_spawn", 26)), "26 does not")
	# Heroes count too — the players are part of the 25.
	var bodies: Array[Node] = []
	for i: int in 3:
		var h := Node2D.new()
		h.add_to_group("hero")
		arena.add_child(h)
		bodies.append(h)
	_expect(int(enc.call("live_entity_count")) == 3, "heroes count against the cap")
	for i: int in 20:
		var e := Node2D.new()
		e.add_to_group("enemy")
		arena.add_child(e)
		bodies.append(e)
	_expect(int(enc.call("live_entity_count")) == 23, "enemies count too (3 + 20)")
	_expect(int(enc.call("spawn_headroom")) == 2, "two slots left")
	_expect(bool(enc.call("can_spawn", 2)), "a 2-body summon still fits")
	_expect(not bool(enc.call("can_spawn", 3)), "a 3-body summon does not")
	for i: int in 2:
		var e2 := Node2D.new()
		e2.add_to_group("enemy")
		arena.add_child(e2)
		bodies.append(e2)
	_expect(int(enc.call("spawn_headroom")) == 0, "a full arena has no headroom")
	_expect(not bool(enc.call("can_spawn", 1)), "...and refuses even one more body")
	_expect(int(enc.call("spawn_headroom")) >= 0, "headroom never goes negative")
	for b: Node in bodies:
		b.free()
	_clear_arena(arena)
	_completes("entity_cap_math")


## The wave spawner asks the cap too: a floor packed to the ceiling stops
## spawning even when its wave budget and concurrent cap both say "go".
func _test_cap_gates_wave_spawning() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	# One wave with a huge budget + cap, so ONLY the entity cap can stop it.
	enc.call("run_floor", _floor_with([[60, 60]]))
	_tick(enc, 120, 0.5, false)   # never kill anything
	var live: int = get_nodes_in_group("enemy").size()
	_expect(live <= 25, "the wave spawner never exceeds the 25-entity cap (got %d)" % live)
	_expect(live >= 20, "...and it did fill the arena rather than stalling early (got %d)" % live)
	_expect(int(enc.call("phase")) == PHASE_WAVES, "the wave is still running, just capped")
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	_clear_arena(arena)
	_completes("cap_gates_wave_spawning")


# ═══════════════════════════════════════════════════════════════════ PACING
# The first cut of waves ran "spawn -> wait for an EMPTY room -> pause 1.5s".
# Both halves of that are dead air, which is the opposite of what a floor is for.
# The four tests below are the contract for the fix: waves LAND (vanguard), waves
# OVERLAP (handoff while stragglers live), the win is ANNOUNCED (wave_cleared),
# and difficulty is COMPOSITION (roster), never a quiet HP multiplier.

## The two derived pacing numbers, pure. A wave that opens with one body
## trickling in is a lull, and a handoff that waits for zero is dead air — so
## vanguard has a floor of 2 and handoff a floor of 1.
func _test_pacing_math() -> void:
	var enc_script: GDScript = load(ENCOUNTER_PATH) as GDScript
	for cap: int in range(1, 9):
		var v: int = int(enc_script.vanguard_for_cap(cap))
		var h: int = int(enc_script.handoff_for_cap(cap))
		_expect(v >= 2, "cap %d opens with at least 2 bodies at once (got %d)" % [cap, v])
		_expect(v <= maxi(cap, 2), "cap %d's vanguard does not exceed the cap (got %d)" % [cap, v])
		_expect(h >= 1, "cap %d hands off with at least one straggler up (got %d)" % [cap, h])
		_expect(h <= 3, "cap %d's handoff stays a TAIL, not half the wave (got %d)" % [cap, h])
	_expect(int(enc_script.vanguard_for_cap(6)) > int(enc_script.vanguard_for_cap(2)),
		"a bigger wave lands with a bigger opening group")
	# WaveDef's inherit rule: < 0 derives, and 0 is a MEANINGFUL authored value
	# ("clear the room properly first"), so it must survive.
	var w := WaveDef.new()
	_expect(w.resolved_vanguard(3) == 3, "an unset vanguard derives from the cap")
	_expect(w.resolved_handoff(2) == 2, "an unset handoff derives from the cap")
	w.vanguard = 5
	w.handoff_alive = 0
	_expect(w.resolved_vanguard(3) == 5, "an authored vanguard wins")
	_expect(w.resolved_handoff(2) == 0, "an authored handoff of ZERO is honoured, not treated as unset")
	_completes("pacing_math")


## THE DRAW-IN. A wave opens with a GROUP arriving in one tick — not one body
## every SPAWN_INTERVAL. The spawn interval here is deliberately huge, so
## anything that arrives in the first tick can only have come from the vanguard.
##
## SINCE THE SPAWN TELL, "arriving" happens in two beats: the whole vanguard is
## MARKED in one tick (a scribble where each body will stand), and the whole
## vanguard LANDS in one tick SPAWN_TELL_LEAD later. Both halves are asserted —
## the group-ness is the contract, and it now has to survive the lead.
func _test_vanguard_lands_together() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var enc_script: GDScript = load(ENCOUNTER_PATH) as GDScript
	var fd: FloorDef = _floor_with([[8, 5]])
	fd.waves[0].spawn_interval = 30.0    # the trickle cannot possibly contribute
	enc.call("run_floor", fd)
	enc.call("_process", 0.05)
	var marked: int = int(enc.call("pending_spawn_count"))
	var want: int = int(enc_script.vanguard_for_cap(5))
	_expect(marked == want,
		"the wave OPENS by MARKING %d bodies at once (got %d)" % [want, marked])
	_expect(get_nodes_in_group("enemy").size() == 0,
		"...and nothing has landed yet: the ink comes first")
	# ...and it does not keep bursting: the rest is the trickle it was authored as.
	enc.call("_process", 0.05)
	_expect(int(enc.call("pending_spawn_count")) == marked,
		"the vanguard fires ONCE, then the wave trickles")
	# THE GROUP LANDS AS A GROUP. If the lead were applied per body the wave would
	# dribble in over the lead instead of hitting, and the draw-in would be gone.
	enc.call("_process", float(enc.get("SPAWN_TELL_LEAD")))
	_expect(get_nodes_in_group("enemy").size() == want,
		"the whole vanguard LANDS together when the lead elapses (got %d)"
			% get_nodes_in_group("enemy").size())
	_expect(int(enc.call("pending_spawn_count")) == 0, "...and nothing is left waiting")
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	_clear_arena(arena)
	_completes("vanguard_lands_together")


## THE OVERLAP — the whole point of the pacing pass. A wave hands off while its
## last bodies are still alive, so the next wave's vanguard arrives on top of a
## fight in progress. If this ever regresses to "wait for an empty room", the
## floor gets its dead air back and this fails.
func _test_waves_overlap_so_the_room_is_never_empty() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var fd: FloorDef = _floor_with([[6, 4], [6, 4]])
	fd.wave_break = 0.2
	enc.call("run_floor", fd)
	# Spawn wave 0 out without killing anything: it fills to its cap and stalls.
	var guard: int = 0
	while get_nodes_in_group("enemy").size() < 4 and guard < 200:
		enc.call("_process", 0.1)
		guard += 1
	# Kill down towards the tail, checking the handoff fires BEFORE the room empties.
	#
	# PRESSURE, not bodies. Since the spawn tell, a body that has been MARKED but
	# has not landed yet is still the wave leaning on you — you can see where it is
	# about to stand, and Encounter counts it against the cap for exactly that
	# reason. Measuring only `enemy` here would call a room with two marks in it
	# empty, which is the opposite of what a player sees.
	var handed_off_with_alive: int = -1
	guard = 0
	while int(enc.call("phase")) == PHASE_WAVES and guard < 400:
		enc.call("_process", 0.1)
		var live: Array = get_nodes_in_group("enemy")
		if int(enc.call("phase")) != PHASE_WAVES:
			handed_off_with_alive = live.size() + int(enc.call("pending_spawn_count"))
			break
		if live.size() > 0:
			live[0].free()
		guard += 1
	_expect(int(enc.call("phase")) == PHASE_SURGE, "the beaten wave handed off to the SURGE")
	_expect(handed_off_with_alive > 0,
		"the handoff happened with the wave's last bodies STILL ALIVE (got %d)" % handed_off_with_alive)
	# ...and the next wave opens on top of them.
	enc.call("_process", 0.5)
	_expect(int(enc.call("current_wave")) == 1, "the next wave opened")
	_expect(get_nodes_in_group("enemy").size() + int(enc.call("pending_spawn_count"))
			>= handed_off_with_alive,
		"the stragglers are still in the room when wave 2 lands on you")
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	_clear_arena(arena)
	_completes("waves_overlap_so_the_room_is_never_empty")


## THE REWARD BEAT. Every wave — including the last one, just before the
## guardian — announces itself as beaten exactly once. Hype hangs the shout, the
## camera punch, the music swell and the banked rank power off this signal, so a
## missing or doubled emit is a visibly broken floor.
func _test_wave_cleared_fires_once_per_wave() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var beaten: Array = []
	enc.connect("wave_cleared", func(idx: int, total: int) -> void: beaten.append([idx, total]))
	enc.call("run_floor", _floor_with([[2, 3], [3, 3], [4, 4]]))
	_tick(enc, 80)
	var indices: Array = []
	for row: Array in beaten:
		indices.append(int(row[0]))
	_expect(indices == [0, 1, 2],
		"every wave announced itself beaten, in order, once (got %s)" % str(indices))
	_expect(beaten.size() > 0 and int(beaten[0][1]) == 3, "the signal carries the floor's wave count")
	_clear_arena(arena)
	_completes("wave_cleared_fires_once_per_wave")


## DIFFICULTY IS COMPOSITION. A wave that names its roster gets EXACTLY those
## archetypes — this is the lever that replaces HP scaling, so if the roster were
## quietly ignored the floors would silently flatten back into the same soup.
func _test_roster_forces_the_archetype_mix() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var fd: FloorDef = _floor_with([[12, 12]])
	fd.brute_chance = 1.0    # the weighted roll would happily hand back other kinds
	var roster: Array[int] = [3, 7]   # CHARGER, MAGE
	fd.waves[0].archetypes = roster
	enc.call("run_floor", fd)
	_tick(enc, 30, 0.5, false)
	var seen: Dictionary = {}
	for e: Node in get_nodes_in_group("enemy"):
		seen[int(e.get("archetype"))] = true
	_expect(seen.size() > 0, "the roster wave actually spawned something")
	for kind: int in seen:
		_expect(roster.has(kind),
			"a rostered wave spawned only its own archetypes (saw %d)" % kind)
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	_clear_arena(arena)
	_completes("roster_forces_the_archetype_mix")
