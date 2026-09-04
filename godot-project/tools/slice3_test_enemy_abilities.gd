# Run: godot --headless --path godot-project --script tools/slice3_test_enemy_abilities.gd
# Slice 3: enemy ABILITIES — the SUMMONER telegraphs on itself, then calls in
# SUMMON_COUNT weak chaser minions as arena siblings.
# Enemy.gd references the Sfx autoload, so it is load()ed at runtime on the first
# _process frame (repo test-trap idiom). Engine physics is disabled per-node;
# each test drives _physics_process / Telegraph.advance by hand.
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
	"summoner_windup_then_spawns_minions",
	"summoner_abort_mid_windup_spawns_nothing",
	"summon_cap_holds_when_a_minion_has_been_freed",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ENEMY_SCRIPT_PATH: String = "res://scripts/combat/Enemy.gd"
const RigScript: GDScript = preload("res://scripts/combat/CharacterRig.gd")
const TICK: float = 1.0 / 60.0

var _ran: bool = false


class StubHero:
	extends Node2D
	var damage_calls: Array[int] = []
	func take_damage(amount: int) -> void:
		damage_calls.append(amount)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_summoner_windup_then_spawns_minions()
	_test_summoner_abort_mid_windup_spawns_nothing()
	_test_summon_cap_holds_when_a_minion_has_been_freed()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice3 enemy-abilities tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice3 enemy-abilities tests: all PASS")
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


func _consts() -> Dictionary:
	return (load(ENEMY_SCRIPT_PATH) as GDScript).get_script_constant_map()


func _setup(kind: int, hero_pos: Vector2, enemy_pos: Vector2) -> Dictionary:
	var enemy_script: GDScript = load(ENEMY_SCRIPT_PATH)
	var arena := Node2D.new()
	root.add_child(arena)
	var hero := StubHero.new()
	hero.add_to_group("hero")
	arena.add_child(hero)
	hero.global_position = hero_pos
	var enemy: CharacterBody2D = enemy_script.new()
	enemy.set("archetype", kind)
	var rig: CharacterRig = RigScript.new()
	rig.name = "Rig"
	enemy.add_child(rig)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 20)
	shape.shape = rect
	enemy.add_child(shape)
	arena.add_child(enemy)
	enemy.global_position = enemy_pos
	enemy.set_physics_process(false)
	return {"arena": arena, "hero": hero, "enemy": enemy}


func _teardown(ctx: Dictionary) -> void:
	var arena: Node2D = ctx["arena"]
	root.remove_child(arena)
	arena.free()


func _find_telegraph(arena: Node2D) -> Telegraph:
	for child in arena.get_children():
		if child is Telegraph:
			return child
	return null


## Every live enemy (summoner + minions) self-registers in group "enemy" via
## Enemy._ready, so the group count is the spawn assertion surface.
func _enemy_group_count() -> int:
	return get_nodes_in_group("enemy").size()


## Duck-typed minion lookup: group members other than the summoner itself.
func _find_minions(exclude: Node) -> Array:
	var minions: Array = []
	for node in get_nodes_in_group("enemy"):
		if node != exclude:
			minions.append(node)
	return minions


func _test_summoner_windup_then_spawns_minions() -> void:
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	# Hero at 250px — inside the summoner band [180, 320].
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["SUMMONER"]), Vector2(250, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]
	var baseline: int = _enemy_group_count()
	_expect(baseline == 1, "only the summoner is in group 'enemy' before the tell")

	enemy._physics_process(TICK)
	_expect(enemy.get("_attack_state") == states["WINDUP"], "summoner in-band enters WINDUP")
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	_expect(tg != null, "summoner WINDUP spawns a telegraph tell")
	if tg != null:
		_expect(
			tg.global_position == enemy.global_position,
			"summon tell sits ON the summoner (self-tell like the caster)"
		)
	_expect(_enemy_group_count() == baseline, "no minions before the telegraph fires")

	if tg != null:
		tg.advance(float(c["SUMMON_WINDUP"]) + 0.05)
	var summon_count: int = int(c["SUMMON_COUNT"])
	_expect(
		_enemy_group_count() == baseline + summon_count,
		"telegraph firing grows group 'enemy' by SUMMON_COUNT"
	)
	var minions: Array = _find_minions(enemy)
	_expect(minions.size() == summon_count, "exactly SUMMON_COUNT minions spawned")
	var chaser_kind: int = int((c["Archetype"] as Dictionary)["CHASER"])
	for minion in minions:
		minion.set_physics_process(false)
		_expect(int(minion.get("archetype")) == chaser_kind, "minion archetype is CHASER")
		_expect(int(minion.get("max_hp")) == int(c["SUMMON_MINION_HP"]), "minion max_hp is SUMMON_MINION_HP")
		_expect(
			(minion as Node2D).global_position.distance_to(enemy.global_position) <= float(c["SUMMON_SCATTER"]) + 0.01,
			"minion spawns adjacent to the summoner (within SUMMON_SCATTER)"
		)
	_expect(enemy.get("_attack_state") == states["RECOVER"], "summoner enters RECOVER after summoning")
	_expect(
		is_equal_approx(float(enemy.get("_attack_cooldown")), float(c["SUMMON_COOLDOWN"])),
		"summon cooldown starts at SUMMON_COOLDOWN"
	)

	_teardown(ctx)
	_completes("summoner_windup_then_spawns_minions")


func _test_summoner_abort_mid_windup_spawns_nothing() -> void:
	var c: Dictionary = _consts()
	var states: Dictionary = c["AttackState"]
	var ctx: Dictionary = _setup(int((c["Archetype"] as Dictionary)["SUMMONER"]), Vector2(250, 0), Vector2.ZERO)
	var enemy: CharacterBody2D = ctx["enemy"]

	enemy._physics_process(TICK)
	_expect(enemy.get("_attack_state") == states["WINDUP"], "summoner enters WINDUP")
	var tg: Telegraph = _find_telegraph(ctx["arena"])
	_expect(tg != null, "abort test has a live telegraph to cancel")
	var baseline: int = _enemy_group_count()

	# Interrupt mid-windup (the fair-play counter: burst the summoner during the
	# tell). _abort_attack disconnects + frees the telegraph; even if the freed
	# telegraph's timer were to elapse this frame, no minions may arrive.
	enemy._abort_attack()
	_expect(enemy.get("_attack_state") == states["CHASE"], "abort returns the summoner to CHASE")
	_expect(enemy.get("_telegraph") == null, "abort clears the telegraph reference")
	if tg != null and is_instance_valid(tg):
		tg.advance(float(c["SUMMON_WINDUP"]) + 0.05)  # disconnected — must be a no-op
	_expect(_enemy_group_count() == baseline, "aborted windup spawns zero minions")

	_teardown(ctx)
	_completes("summoner_abort_mid_windup_spawns_nothing")

## THE SWARM BUG. `_live_minion_count` is the ONLY thing enforcing SUMMON_MAX_ALIVE —
## it gates the summon at `Enemy.gd:1646` and sizes the batch at `Enemy.gd:1673` — and
## its whole job is to prune refs to minions that have died. It was written
## `for m: Node in _minions`, and a TYPED loop variable is a typed ASSIGNMENT: GDScript
## validates the instance as it binds it, so a freed element throws
##
##     SCRIPT ERROR: Trying to assign invalid previously freed instance.
##
## BEFORE `is_instance_valid(m)` on the next line ever runs. The pruner died on exactly
## the input it exists for, every physics frame, and — per this suite's own header — an
## aborted function hands its caller the return type's zero. So the cap read 0 live
## minions forever: `0 < SUMMON_MAX_ALIVE` always passed, `SUMMON_MAX_ALIVE - 0` always
## sized a full batch, and one summoner spawned minions without end until the process
## was eating gigabytes. Observed live 2026-09-04.
##
## ⚠ THE ASSERTION IS THE COUNT, NOT THE ABSENCE OF AN ERROR. A GDScript runtime error
## cannot be caught, so "did it print an error" is not something a test can read. What
## it CAN read is the consequence: the count comes back 0 instead of the real number.
func _test_summon_cap_holds_when_a_minion_has_been_freed() -> void:
	var c: Dictionary = _consts()
	var cap: int = int(c["SUMMON_MAX_ALIVE"])
	var ctx: Dictionary = _setup(
		int((c["Archetype"] as Dictionary)["SUMMONER"]), Vector2(250, 0), Vector2.ZERO)
	var arena: Node2D = ctx["arena"]
	var enemy: CharacterBody2D = ctx["enemy"]

	# A full house of live minions, plus one that has already died — which is the
	# ordinary state of this array a second after any minion is killed.
	var roster: Array = []
	for i: int in cap:
		var live := Node2D.new()
		arena.add_child(live)
		roster.append(live)
	var doomed := Node2D.new()
	arena.add_child(doomed)
	roster.append(doomed)
	enemy.set("_minions", roster)
	arena.remove_child(doomed)
	doomed.free()

	var n: int = int(enemy.call("_live_minion_count"))
	_expect(n == cap,
		"a freed minion in the list must prune to %d live, got %d. 0 means the typed "
			% [cap, n] + "loop variable threw on the freed element and the function "
			+ "aborted — which is the infinite-swarm bug, not a counting slip")
	# The consequence the cap exists for: a full house summons nobody else.
	_expect(maxi(cap - n, 0) == 0,
		"with the cap full, the next batch must be 0, sized %d" % maxi(cap - n, 0))
	# And the prune must actually have happened in place, not just been counted.
	var kept: Array = enemy.get("_minions") as Array
	_expect(kept.size() == cap,
		"_minions must be rewritten to the %d live refs, holds %d" % [cap, kept.size()])

	_teardown(ctx)
	_completes("summon_cap_holds_when_a_minion_has_been_freed")
