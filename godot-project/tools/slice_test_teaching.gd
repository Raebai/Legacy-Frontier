# Run: godot --headless --path godot-project --script tools/slice_test_teaching.gd
#
# THE TEACHING FLOORS. The maker's playtest note was two things at once —
# "the bots are also good and fast but they chase like hell WHICH I LIKE but
# dont make the first levels too difficult" — so the praise is a constraint. The
# aggression is wanted; what was wrong is the RAMP into it.
#
# This suite locks the ramp so a later tuning pass cannot quietly undo it, and
# locks the constraint so a later "make floor 1 easier" pass cannot quietly
# flatten the game. Specifically it asserts:
#
#   * floor 1 opens at a LOWER pressure cap than it ends at, and lower than
#     floor 2 opens at;
#   * floor 1 introduces at most TWO archetypes, and each wave adds at most one
#     new one — one new tell at a time;
#   * floor 1's guardian arrives to a CLEAN ROOM (the last wave hands off at 0);
#   * the generator cannot redraw the teaching floor into something harder than
#     it was authored: no classmate swap on depth 1, no cap above the authored
#     one, no `vanguard = cap` slam;
#   * ...and the generator is UNCHANGED from depth 3 up — the "chase like hell"
#     floors keep every knob they had;
#   * escalation is still composition, never HP, on every floor;
#   * the pounce is depth-gated, and a body that was never told its depth (the
#     F6 sandbox, VersusArena, every harness) is unrestricted.
#
# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function and hands the caller the return type's zero
# value. Under `failed += _test_x()` that reads as "zero failures". So: failures
# accumulate on the MEMBER `_fails`, and every test records that it reached its
# own last line. A test that aborts part-way is then missing from `_completed`
# and fails the suite BY ABSENCE.
extends SceneTree

const GS_PATH: String = "res://scripts/GameState.gd"
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"

## Every test that must run to completion.
const TESTS: Array[String] = [
	"floor_one_ramps_into_its_own_pressure",
	"floor_one_teaches_one_tell_at_a_time",
	"the_first_guardian_arrives_to_a_clean_room",
	"the_generator_cannot_make_the_teaching_floor_harder",
	"the_deep_floors_keep_every_knob",
	"escalation_is_still_composition_not_hp",
	"the_pounce_is_a_floor_two_verb",
]

## Enough seeds that a 45%-chance roll firing zero times is not the explanation
## for a green run.
const SEEDS: int = 60

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _tower: Resource = null
var _gs: GDScript = null


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_gs = load(GS_PATH) as GDScript
	_tower = _gs.build_default_tower()
	_test_floor_one_ramps_into_its_own_pressure()
	_test_floor_one_teaches_one_tell_at_a_time()
	_test_the_first_guardian_arrives_to_a_clean_room()
	_test_the_generator_cannot_make_the_teaching_floor_harder()
	_test_the_deep_floors_keep_every_knob()
	_test_escalation_is_still_composition_not_hp()
	_test_the_pounce_is_a_floor_two_verb()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Teaching-floor tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Teaching-floor tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(name: String) -> void:
	_completed[name] = true


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _waves_of(floor_index: int) -> Array:
	return (_tower.floors[floor_index] as Resource).waves as Array


# ---------------------------------------------------------------- 1 · the ramp
## A first-time player has not found the dash yet. Floor 1 must therefore OPEN
## below its own peak and below floor 2's opener — otherwise the "curve" is a
## flat line that happens to start where the game gets hard.
func _test_floor_one_ramps_into_its_own_pressure() -> void:
	var f1: Array = _waves_of(0)
	var f2: Array = _waves_of(1)
	_expect(f1.size() >= 2, "floor 1 has waves to ramp across (got %d)" % f1.size())
	if f1.size() >= 2:
		var first: int = int(f1[0].concurrent_cap)
		var last: int = int(f1[f1.size() - 1].concurrent_cap)
		_expect(first < last,
			"floor 1 opens below its own peak pressure (%d -> %d)" % [first, last])
		_expect(first <= int(f2[0].concurrent_cap),
			"floor 1 opens no harder than floor 2 does (%d vs %d)"
				% [first, int(f2[0].concurrent_cap)])
		# ...and the opener is a handful of bodies, not a room.
		_expect(first <= 3, "floor 1's opening pressure cap is <= 3 (got %d)" % first)
	_completes("floor_one_ramps_into_its_own_pressure")


## ONE NEW TELL AT A TIME. The whole complaint compressed into one assertion: a
## novice can learn to dodge one thing, then another. Two new tells arriving in
## the same wave is the thing that reads as "too difficult".
func _test_floor_one_teaches_one_tell_at_a_time() -> void:
	var seen: Dictionary = {}
	var f1: Array = _waves_of(0)
	for w in f1:
		var added: int = 0
		for a in (w.archetypes as Array):
			if not seen.has(int(a)):
				seen[int(a)] = true
				added += 1
		_expect(added <= 1,
			"each floor-1 wave introduces at most ONE new archetype (a wave added %d)" % added)
	_expect(seen.size() <= 2,
		"floor 1 asks the player to read at most TWO archetypes (got %d)" % seen.size())
	_expect(seen.size() >= 2, "...but it is still a fight, not a single note (got %d)" % seen.size())
	# Floor 2 is allowed to be bigger, but it is still an early floor: it must not
	# dump the whole roster on someone two floors in.
	var seen2: Dictionary = {}
	for w2 in _waves_of(1):
		for a2 in (w2.archetypes as Array):
			seen2[int(a2)] = true
	_expect(seen2.size() <= 4,
		"floor 2 stays inside four archetypes (got %d)" % seen2.size())
	_expect(seen2.size() > seen.size(),
		"...and it still teaches something floor 1 did not (%d vs %d)" % [seen2.size(), seen.size()])
	_completes("floor_one_teaches_one_tell_at_a_time")


## The overlap handoff is the pacing pass's signature and must stay everywhere
## else — but the FIRST guardian anyone ever meets is a lesson, and a lesson
## fought through a crowd teaches nothing. Exactly one wave in the tower opts
## out, and it is floor 1's last.
func _test_the_first_guardian_arrives_to_a_clean_room() -> void:
	var f1: Array = _waves_of(0)
	_expect(int(f1[f1.size() - 1].handoff_alive) == 0,
		"floor 1's last wave hands off at 0 — the guardian arrives alone (got %d)"
			% int(f1[f1.size() - 1].handoff_alive))
	var opted_out: int = 0
	for i: int in (_tower.floors as Array).size():
		for w in _waves_of(i):
			if int(w.handoff_alive) == 0:
				opted_out += 1
	_expect(opted_out == 1,
		"...and it is the ONLY wave in the tower that does (got %d — the overlap is the pacing)"
			% opted_out)
	_completes("the_first_guardian_arrives_to_a_clean_room")


# ----------------------------------------------------- 2 · the generator gates
## FloorGen redraws every floor per climb. On the teaching floor it may redraw
## the ROOM all it likes, but it may not redraw the LESSON: floor 1's authored
## `[CHASER]` opener could otherwise come back as an all-assassin rush, and its
## caps could be re-cut upward. This is the assertion that a re-roll of floor 1
## is a different room and the same lesson.
func _test_the_generator_cannot_make_the_teaching_floor_harder() -> void:
	var fg: GDScript = load("res://scripts/tower/FloorGen.gd") as GDScript
	var src: Array = _waves_of(0)
	var authored_caps: Array[int] = []
	var authored_max: int = 0
	for w in src:
		authored_caps.append(int(w.concurrent_cap))
		authored_max = maxi(authored_max, int(w.concurrent_cap))
	var mix_changed: int = 0
	var cap_raised: int = 0
	var slam: int = 0
	var rooms: Dictionary = {}
	for s: int in SEEDS:
		var t: Resource = fg.vary_tower(_tower, s * 7717 + 29)
		var got: Array = (t.floors[0] as Resource).waves as Array
		for k: int in mini(src.size(), got.size()):
			if str(src[k].archetypes as Array) != str(got[k].archetypes as Array):
				mix_changed += 1
			if int(got[k].concurrent_cap) > authored_caps[k]:
				cap_raised += 1
			if int(got[k].vanguard) >= int(got[k].concurrent_cap):
				slam += 1
		rooms[str((t.floors[0] as Resource).layout.platforms)] = true
	_expect(mix_changed == 0,
		"floor 1's authored mix is never redrawn (%d waves came back different)" % mix_changed)
	_expect(cap_raised == 0,
		"floor 1's pressure caps are never re-cut upward (%d violations)" % cap_raised)
	_expect(slam == 0,
		"floor 1 never gets the `vanguard = cap` slam (%d violations)" % slam)
	# ...and the floor is STILL redrawn, or the gate has turned the teaching floor
	# into the same room every climb, which is a different bug.
	_expect(rooms.size() > 1,
		"floor 1 is still a different ROOM each climb (%d distinct skylines in %d seeds)"
			% [rooms.size(), SEEDS])
	_completes("the_generator_cannot_make_the_teaching_floor_harder")


## THE CONSTRAINT HALF OF THE FEEDBACK. "They chase like hell WHICH I LIKE."
## Nothing above may leak past the early floors: from depth 3 the generator must
## still swap the mix, still re-cut the caps, and still land the slam vanguard.
func _test_the_deep_floors_keep_every_knob() -> void:
	var fg: GDScript = load("res://scripts/tower/FloorGen.gd") as GDScript
	var mix_changed: int = 0
	var cap_raised: int = 0
	var slam: int = 0
	var leaned: int = 0
	for s: int in SEEDS:
		var t: Resource = fg.vary_tower(_tower, s * 4013 + 7)
		for i: int in range(2, (t.floors as Array).size()):
			var src: Array = _waves_of(i)
			var got: Array = (t.floors[i] as Resource).waves as Array
			for k: int in mini(src.size(), got.size()):
				var authored: Array = src[k].archetypes as Array
				var rolled: Array = got[k].archetypes as Array
				if str(authored) != str(rolled):
					mix_changed += 1
				if rolled.size() > authored.size() + 1:
					leaned += 1          # widen + the character pass, still firing
				if int(got[k].concurrent_cap) > int(src[k].concurrent_cap):
					cap_raised += 1
				if int(got[k].vanguard) >= int(got[k].concurrent_cap):
					slam += 1
	_expect(mix_changed > 0, "depth 3+ still redraws the mix (it never varied)")
	_expect(leaned > 0, "depth 3+ still leans a wave on one class (the character pass never fired)")
	_expect(cap_raised > 0, "depth 3+ still re-cuts the pressure caps upward (never happened)")
	_expect(slam > 0, "depth 3+ still lands the slam vanguard (never happened)")
	_completes("the_deep_floors_keep_every_knob")


## The standing policy, re-asserted from this side because "make floor 1 easier"
## is exactly the prompt that tempts someone to reach for the HP dial on the way
## back up. Trash HP is 1.0 everywhere; the depth curve is the guardian's alone.
func _test_escalation_is_still_composition_not_hp() -> void:
	var floors: Array = _tower.floors as Array
	for i: int in floors.size():
		_expect(is_equal_approx(float(floors[i].hp_multiplier), 1.0),
			"floor %d trash hp_multiplier is 1.0 (escalate the MIX, not the HP)" % (i + 1))
		for w in _waves_of(i):
			_expect(float(w.hp_multiplier) < 0.0,
				"floor %d has no per-wave hp override (it must inherit)" % (i + 1))
	_expect(float(floors[floors.size() - 1].boss_hp_multiplier) > float(floors[0].boss_hp_multiplier),
		"the guardian curve still ramps with depth")
	# The teaching floor did not get easier by shedding the guardian's HP either.
	_expect(float(floors[0].boss_hp_multiplier) >= 1.0,
		"floor 1's guardian was not nerfed to buy the ramp (got %.2f)"
			% float(floors[0].boss_hp_multiplier))
	_completes("escalation_is_still_composition_not_hp")


# ------------------------------------------------------------- 3 · the pounce
## The chase is untouched at every depth. What waits one floor is the SPRING —
## and a body that was never told its depth (the F6 sandbox, VersusArena, every
## headless harness) must be exactly as it was, or "measure the feel in the
## sandbox" stops measuring the shipped thing.
func _test_the_pounce_is_a_floor_two_verb() -> void:
	var es: GDScript = load(ENEMY_PATH) as GDScript
	_expect(int(es.get("POUNCE_MIN_DEPTH")) == 2, "the pounce unlocks on floor 2")
	var arcs: Array = es.get("POUNCE_ARCHETYPES") as Array
	_expect(arcs.size() == 2, "still only the two 'it gets to you' archetypes (got %d)" % arcs.size())
	var e: CharacterBody2D = es.new()
	e.archetype = int(arcs[0])
	_expect(int(e.get("floor_depth")) == 0, "an untold body defaults to depth 0 (unrestricted)")
	# The decision is guarded by `_hero`, which is null on a bare instance, so the
	# depth branch is asserted through the field rather than by calling into the
	# physics path. Setting it must not disturb anything else about the body.
	e.set("floor_depth", 1)
	_expect(int(e.get("floor_depth")) == 1, "floor_depth is settable pre-tree (the spawn path)")
	e.free()
	# ...and the spawn dict actually carries it, which is the co-op-safe half:
	# host-computed, replicated, read in build_enemy_from_data. A dict WITHOUT the
	# key must still build (every legacy caller).
	var enc: Node = load("res://scripts/combat/Encounter.gd").new()
	var legacy: Dictionary = {
		"boss": false, "arch": 0, "hp": 24, "spd": 140.0, "touch": 8,
		"tint": Color(1, 1, 1, 1), "tele": false, "x": 10.0, "y": 20.0,
	}
	var built: CharacterBody2D = enc.build_enemy_from_data(legacy)
	_expect(built != null, "a legacy spawn dict (no depth key) still builds")
	if built != null:
		_expect(int(built.get("floor_depth")) == 0, "...and lands unrestricted")
		built.free()
	var deep: Dictionary = legacy.duplicate()
	deep["depth"] = 4
	var built2: CharacterBody2D = enc.build_enemy_from_data(deep)
	_expect(built2 != null and int(built2.get("floor_depth")) == 4,
		"a spawn dict carrying a depth builds a body that knows it")
	if built2 != null:
		built2.free()
	enc.free()
	_completes("the_pounce_is_a_floor_two_verb")
