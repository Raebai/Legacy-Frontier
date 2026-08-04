# Run: godot --headless --path godot-project --script tools/slice_test_progression.gd
# The levelling economy. Progression.gd is entirely static + pure, so this needs no
# scene, no disk and no network. It also PRINTS the economy at the end, because a
# curve nobody can see is a curve nobody can argue with.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read ABORTS the enclosing function and hands back the return type's
# zero, which the `failed += _test_x()` idiom reads as "no failures". So failures
# accumulate on the MEMBER `_fails`, and every test records a completion sentinel —
# a test that aborts part-way is missing from `_completed` and fails BY ABSENCE.

const TESTS: Array[String] = [
	"the_curve_gets_harder_forever",
	"depth_gain_is_derived_not_authored",
	"the_pace_is_flat_at_every_depth",
	"a_full_climb_is_about_twelve_levels",
	"farming_dies_on_its_own",
	"deep_villains_drop_more_per_body",
	"the_three_shares_are_the_whole_floor",
	"xp_and_level_round_trip",
	"the_cap_actually_caps",
	"every_class_row_sums_to_ten",
	"level_one_is_exactly_the_authored_class",
	"ward_is_capped_and_is_not_a_multiplier",
	"stormcaller_is_denied_focus_four",
	"solo_is_untouched_by_the_coop_rule",
	"the_party_climbs_at_the_trailing_member",
	"class_unlocking_shape",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

## The real authored tower, so the economy is asserted against the floors that ship
## rather than against numbers typed into this file. `_floor_budgets` is filled in
## _process before any test runs.
var _floor_budgets: Array[int] = []


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_load_real_floor_budgets()
	_test_the_curve_gets_harder_forever()
	_test_depth_gain_is_derived_not_authored()
	_test_the_pace_is_flat_at_every_depth()
	_test_a_full_climb_is_about_twelve_levels()
	_test_farming_dies_on_its_own()
	_test_deep_villains_drop_more_per_body()
	_test_the_three_shares_are_the_whole_floor()
	_test_xp_and_level_round_trip()
	_test_the_cap_actually_caps()
	_test_every_class_row_sums_to_ten()
	_test_level_one_is_exactly_the_authored_class()
	_test_ward_is_capped_and_is_not_a_multiplier()
	_test_stormcaller_is_denied_focus_four()
	_test_solo_is_untouched_by_the_coop_rule()
	_test_the_party_climbs_at_the_trailing_member()
	_test_class_unlocking_shape()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	_print_the_economy()
	if _fails > 0:
		printerr("Progression tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Progression tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Sum each floor's authored wave budgets — the denominator the per-enemy XP is
## derived against. Read off the SHIPPING tower so a maker retune of a wave row
## flows into this suite instead of quietly invalidating it.
func _load_real_floor_budgets() -> void:
	var GS: GDScript = load("res://scripts/GameState.gd") as GDScript
	var tower: TowerDef = GS.build_default_tower()
	for f: FloorDef in tower.floors:
		var total: int = 0
		for w: WaveDef in f.waves:
			total += maxi(w.enemy_budget, 0)
		_floor_budgets.append(maxi(total, 1))


func _budget(floor: int) -> int:
	if floor >= 1 and floor <= _floor_budgets.size():
		return _floor_budgets[floor - 1]
	return 22


# ══════════════════════════════════════════════════════════════════════════════
# THE CURVE
# ══════════════════════════════════════════════════════════════════════════════

## "harder to level up as you play" — asserted as a PROPERTY, not as a number, so
## retuning GROWTH cannot make the promise false without failing here.
func _test_the_curve_gets_harder_forever() -> void:
	_expect(Progression.GROWTH > 1.0, "GROWTH > 1 or levelling gets EASIER as you play")
	var prev: int = 0
	for l: int in range(1, Progression.MAX_LEVEL):
		var cost: int = Progression.xp_to_next(l)
		_expect(cost > prev, "level %d costs strictly more than level %d" % [l, l - 1])
		prev = cost
	# The ratio is CONSTANT — the property a geometric curve has and a power curve
	# does not. A power curve's ratio decays toward 1, i.e. levels come faster and
	# faster at the top, which is the opposite of the brief.
	var r_low: float = Progression.xp_to_next_exact(3.0) / Progression.xp_to_next_exact(2.0)
	var r_high: float = Progression.xp_to_next_exact(25.0) / Progression.xp_to_next_exact(24.0)
	_expect(is_equal_approx(r_low, r_high),
		"the cost ratio is the SAME at level 24 as at level 2 (it is geometric, not a power curve)")
	_expect(is_equal_approx(r_low, Progression.GROWTH), "…and that ratio is GROWTH itself")
	# The compounded slope over a first climb is the thing a player actually feels.
	var slope: float = Progression.xp_to_next_exact(12.0) / Progression.xp_to_next_exact(1.0)
	_expect(slope > 5.0, "level 12 costs at least 5x what level 1 did (the slope is legible)")
	_completes("the_curve_gets_harder_forever")


## ⚠ THE LOAD-BEARING ONE. "villains in the high levels drop more PROPORTIONALLY"
## is only true if the depth curve is COMPUTED from the level curve. If someone
## ever replaces depth_gain() with a typed constant, this fails.
func _test_depth_gain_is_derived_not_authored() -> void:
	var expected: float = pow(Progression.GROWTH, Progression.LEVELS_PER_FLOOR)
	_expect(is_equal_approx(Progression.depth_gain(), expected),
		"depth_gain() == GROWTH ^ LEVELS_PER_FLOOR — derived, never authored")
	_expect(Progression.depth_gain() > 1.0, "deeper floors are worth more, not less")
	# Every adjacent pair of floors sits at exactly that ratio.
	for f: int in range(1, 20):
		var ratio: float = Progression.floor_xp_value(f + 1) / Progression.floor_xp_value(f)
		_expect(is_equal_approx(ratio, Progression.depth_gain()),
			"floor %d is worth exactly depth_gain() x floor %d" % [f + 1, f])
	_completes("depth_gain_is_derived_not_authored")


## THE IDENTITY THE WHOLE SYSTEM RESTS ON. A floor is worth LEVELS_PER_FLOOR levels
## at the level you are expected to be when you fight it — at EVERY depth. That is
## what "the pace is flat while the numbers grow" means, and it is exact rather
## than approximate because both sides are the same exponential.
## ⚠ IT HOLDS ONLY BELOW THE LEVEL CAP, and that is not a caveat to bury. Past
## MAX_LEVEL the level curve STOPS while the floor curve keeps climbing, so the
## identity necessarily breaks — a floor above the cap pays XP nobody can spend.
## The loop therefore runs to the deepest floor whose expected level is still under
## the cap, and then asserts the boundary explicitly rather than skipping past it.
func _test_the_pace_is_flat_at_every_depth() -> void:
	var deepest_meaningful: int = 0
	for f: int in range(1, 200):
		if Progression.expected_level_on_floor(f) >= float(Progression.MAX_LEVEL):
			break
		deepest_meaningful = f
	_expect(deepest_meaningful > 10,
		"the identity is meaningful well past the current 10-floor tower (got %d floors)"
		% deepest_meaningful)
	for f: int in range(1, deepest_meaningful + 1):
		var cost_of_a_level: float = Progression.xp_to_next_exact(Progression.expected_level_on_floor(f))
		_expect(cost_of_a_level > 0.0, "a level has a price on floor %d" % f)
		if cost_of_a_level <= 0.0:
			continue
		var levels: float = Progression.floor_xp_value(f) / cost_of_a_level
		_expect(is_equal_approx(levels, Progression.LEVELS_PER_FLOOR),
			"floor %d is worth exactly LEVELS_PER_FLOOR levels (got %.4f)" % [f, levels])
	# THE BOUNDARY, stated out loud: past the cap a floor still pays, and the XP is
	# simply unspendable. That is the honest behaviour of a capped curve, and it is
	# asserted so that raising MAX_LEVEL later is a visible change and not a silent one.
	var past: int = deepest_meaningful + 1
	_expect(Progression.floor_xp_value(past) > 0.0, "a floor past the cap still has a value")
	_expect(Progression.xp_to_next_exact(Progression.expected_level_on_floor(past)) == 0.0,
		"…but the level it would buy costs nothing, because there is no level left to buy")
	_completes("the_pace_is_flat_at_every_depth")


## The spec sized the Growth table against "~12 levels for the current 10-floor
## tower" (§5.3). This asserts the economy actually delivers that, against the real
## floor count — so growing the tower and forgetting the curve fails here.
func _test_a_full_climb_is_about_twelve_levels() -> void:
	var floors: int = _floor_budgets.size()
	_expect(floors > 0, "the authored tower has floors")
	if floors <= 0:
		return  # deliberately NOT completed
	var banked: float = 0.0
	for f: int in range(1, floors + 1):
		banked += Progression.floor_xp_value(f)
	var reached: int = Progression.level_for_xp(int(round(banked)))
	_expect(reached >= 10 and reached <= 15,
		"one full climb of the %d-floor tower lands between level 10 and 15 (got %d)" % [floors, reached])
	# And a SECOND climb must still be worth doing — diminishing, never zero.
	var after_two: int = Progression.level_for_xp(int(round(banked * 2.0)))
	_expect(after_two > reached, "a second full climb still gains levels")
	_expect(after_two - reached < reached - 1,
		"…but fewer of them than the first climb gave (the returns diminish)")
	_completes("a_full_climb_is_about_twelve_levels")


## ⚠ THE ANTI-FARM THEOREM, EXECUTABLE. The spec BANNED kill-XP to avoid this; the
## maker put XP on villains, so the ban is replaced by arithmetic. Farming is never
## forbidden — it is out-grown, and this proves it rather than claiming it.
func _test_farming_dies_on_its_own() -> void:
	var b1: int = _budget(1)
	var prev: int = 0
	for l: int in range(1, Progression.MAX_LEVEL):
		var kills: int = Progression.kills_to_level(1, l, b1)
		_expect(kills > 0, "a floor-1 farm at level %d needs a positive number of bodies" % l)
		_expect(kills >= prev, "the floor-1 farm never gets CHEAPER as you level (level %d)" % l)
		prev = kills
	# Unbounded in practice: the farm must become absurd, not merely slower.
	var at_20: int = Progression.kills_to_level(1, 20, b1)
	_expect(at_20 > 10 * _budget(1),
		"by level 20 a floor-1 farm costs more than ten full clears of floor 1 (got %d bodies)" % at_20)
	# THE COMPARISON THAT MATTERS: climbing beats farming at the SAME level, and by
	# a margin that widens. Bodies-per-level on the deepest floor vs on floor 1.
	var deepest: int = _floor_budgets.size()
	for l: int in [5, 10, 15, 20]:
		var farm: int = Progression.kills_to_level(1, l, b1)
		var climb: int = Progression.kills_to_level(deepest, l, _budget(deepest))
		_expect(climb < farm,
			"at level %d, bodies-per-level is lower on floor %d than on floor 1 (%d vs %d)"
			% [l, deepest, climb, farm])
	_completes("farming_dies_on_its_own")


## The maker's line, asserted directly: a villain deeper in the tower is worth more
## than one near the top of the stairs. Non-trivial because wave budgets ALSO grow
## with depth, so the per-body number is a ratio of two growing things.
func _test_deep_villains_drop_more_per_body() -> void:
	var floors: int = _floor_budgets.size()
	if floors < 2:
		return  # deliberately NOT completed
	# ⚠ PER-BODY VALUE IS NOT MONOTONIC FLOOR-TO-FLOOR, AND MUST NOT BE ASSERTED AS IF
	# IT WERE. It is a RATIO of two independently-authored curves: the floor's worth
	# (geometric, `depth_gain`) over the floor's body count (hand-authored per wave).
	# So a floor that deliberately sends MORE bodies than its neighbour pays less per
	# head — which is correct, and is exactly what happened when floor 1 was thinned
	# for being too hard while floor 2 was left alone.
	#
	# This asserted a strict step-by-step chain and went red on a difficulty retune
	# that had not broken anything. What actually matters — and what the maker's line
	# "villains in the high levels drop more" actually claims — is the SPAN: deep
	# villains beat shallow ones, and no floor pays LESS per head than the first.
	# ⚠ AND NOT EVEN "NO FLOOR PAYS LESS THAN FLOOR 1" SURVIVES, because the maker had
	# floor 1 thinned from 22 bodies to 14 for being too hard. Dividing the same floor
	# value by fewer heads pays MORE per head — so the teaching floor now out-pays its
	# neighbours per body, entirely correctly. The claim that is actually load-bearing
	# is the SPAN, and it is the only one asserted.
	var first: int = Progression.enemy_xp(1, _budget(1))
	_expect(Progression.enemy_xp(floors, _budget(floors)) > first,
		"a villain on the top floor is strictly worth more than one on floor 1")
	# …and the FLOOR's total worth IS strictly monotonic — that curve is pure
	# arithmetic with no authored denominator, so it may be pinned exactly.
	for f: int in range(1, floors):
		_expect(Progression.floor_xp_value(f + 1) > Progression.floor_xp_value(f),
			"floor %d is worth strictly more than floor %d" % [f + 1, f])
	# The guardian is the biggest single XP event on its floor — it is the fight the
	# floor is built toward, so it should pay like it.
	for f: int in range(1, floors + 1):
		_expect(Progression.guardian_xp(f) > Progression.enemy_xp(f, _budget(f)),
			"floor %d's guardian pays more than one of its trash" % f)
	_completes("deep_villains_drop_more_per_body")


## A floor is worth its full value however you took it. If the shares stop summing
## to 1 the floor quietly pays more (or less) than the pace identity promises, and
## `_test_the_pace_is_flat_at_every_depth` would keep passing while the game lied.
func _test_the_three_shares_are_the_whole_floor() -> void:
	var total: float = Progression.KILL_SHARE + Progression.CLEAR_SHARE + Progression.GUARDIAN_SHARE
	_expect(is_equal_approx(total, 1.0),
		"KILL + CLEAR + GUARDIAN shares == 1.0 (got %.4f)" % total)
	_expect(Progression.KILL_SHARE > 0.0, "villains drop XP — the maker's ask, pinned")
	_expect(Progression.KILL_SHARE > Progression.CLEAR_SHARE,
		"kills are the biggest channel (a reward you watch land beats one that arrives at a door)")
	_completes("the_three_shares_are_the_whole_floor")


func _test_xp_and_level_round_trip() -> void:
	_expect(Progression.total_xp_for_level(1) == 0, "level 1 costs nothing")
	_expect(Progression.level_for_xp(0) == 1, "zero XP is level 1")
	_expect(Progression.level_for_xp(-500) == 1, "junk XP still answers level 1")
	for l: int in range(1, Progression.MAX_LEVEL + 1):
		var at: int = Progression.total_xp_for_level(l)
		_expect(Progression.level_for_xp(at) == l,
			"exactly the XP for level %d IS level %d" % [l, l])
		_expect(Progression.xp_into_level(at) == 0, "…with 0 banked into it")
		if l < Progression.MAX_LEVEL:
			_expect(Progression.level_for_xp(at - 1) == l - 1 or l == 1,
				"one XP short of level %d is still level %d" % [l, l - 1])
			var mid: int = at + Progression.xp_to_next(l) / 2
			_expect(Progression.level_for_xp(mid) == l, "half way is still level %d" % l)
			_expect(Progression.xp_into_level(mid) > 0, "…with progress banked into it")
	_completes("xp_and_level_round_trip")


func _test_the_cap_actually_caps() -> void:
	_expect(Progression.xp_to_next(Progression.MAX_LEVEL) == 0, "the cap costs nothing more")
	_expect(Progression.xp_to_next(Progression.MAX_LEVEL + 7) == 0, "…and past it too")
	_expect(Progression.level_for_xp(999_999_999) == Progression.MAX_LEVEL,
		"no amount of XP exceeds the cap")
	_expect(Progression.kills_to_level(1, Progression.MAX_LEVEL, 22) == 0,
		"at the cap, no number of bodies buys anything")
	# Growth is clamped by the cap too, or a corrupt save could hand out any stat.
	_expect(Progression.growth_points(9999, 3, Progression.Axis.VITALITY)
			== Progression.growth_points(Progression.MAX_LEVEL, 3, Progression.Axis.VITALITY),
		"Growth clamps at MAX_LEVEL — a corrupt level cannot buy stats")
	_completes("the_cap_actually_caps")


## ⚠ THE INVARIANT THE SPEC ASKED FOR BY NAME. Every class gains exactly the same
## Growth budget per level; only the SHAPE differs. It is what keeps nine classes
## on one power curve while feeling nothing alike, and a row that sums to 11 is a
## class that quietly out-levels the other eight.
func _test_every_class_row_sums_to_ten() -> void:
	_expect(Progression.CLASS_GROWTH.size() == 9, "nine classes have a Growth row")
	for c: int in Progression.CLASS_GROWTH.size():
		var row: Array = Progression.CLASS_GROWTH[c]
		_expect(row.size() == Progression.AXIS_COUNT,
			"class %d has one value per axis" % c)
		var sum: int = 0
		for v in row:
			_expect(int(v) >= 0, "class %d has no negative axis" % c)
			sum += int(v)
		_expect(sum == Progression.GROWTH_PER_LEVEL,
			"class %d's Growth row sums to %d, not %d — it would out-level the others"
			% [c, sum, Progression.GROWTH_PER_LEVEL])
	# Every class must actually have a PRIMARY — a perfectly flat row is a class
	# with no character, which is the thing the whole table exists to prevent.
	for c: int in Progression.CLASS_GROWTH.size():
		var top: int = 0
		for v in Progression.CLASS_GROWTH[c]:
			top = maxi(top, int(v))
		_expect(top >= 3, "class %d has a primary axis (its highest is %d)" % [c, top])
	_completes("every_class_row_sums_to_ten")


## A level-1 climber is EXACTLY the class's authored base. This is what keeps every
## existing balance number (CLASS_CONFIG hp/speed, BotMatch's CLASS_VITALITY, the
## 288-bout sweep) meaningful instead of silently obsolete the day levels shipped.
func _test_level_one_is_exactly_the_authored_class() -> void:
	for c: int in Progression.CLASS_GROWTH.size():
		for a: int in Progression.AXIS_COUNT:
			_expect(Progression.growth_points(1, c, a) == 0,
				"class %d has banked no Growth at level 1" % c)
			_expect(is_equal_approx(Progression.stat_mult(1, c, a), 1.0),
				"class %d axis %d multiplies by exactly 1.0 at level 1" % [c, a])
		_expect(is_equal_approx(Progression.ward_reduction(1, c), 0.0),
			"class %d has no damage reduction at level 1" % c)
	# …and it goes up from there, on the axes the class actually invests in.
	for c: int in Progression.CLASS_GROWTH.size():
		var row: Array = Progression.CLASS_GROWTH[c]
		for a: int in Progression.AXIS_COUNT:
			if int(row[a]) > 0 and a != Progression.Axis.WARD:
				_expect(Progression.stat_mult(10, c, a) > 1.0,
					"class %d grows on axis %d by level 10" % [c, a])
			elif int(row[a]) == 0 and a != Progression.Axis.WARD:
				_expect(is_equal_approx(Progression.stat_mult(30, c, a), 1.0),
					"class %d NEVER grows on axis %d — a 0 in the table means 0" % [c, a])
	# Junk inputs return the identity rather than erroring or indexing off the end.
	_expect(is_equal_approx(Progression.stat_mult(10, -1, 0), 1.0), "an unknown class grows nothing")
	_expect(is_equal_approx(Progression.stat_mult(10, 99, 0), 1.0), "…and an off-the-end one too")
	_expect(Progression.growth_points(10, 0, 99) == 0, "an unknown axis banks nothing")
	_completes("level_one_is_exactly_the_authored_class")


## WARD is a REDUCTION, not a multiplier. Routing it through `stat_mult` would give
## a number that reads fine and is wrong the day someone multiplies damage by it.
func _test_ward_is_capped_and_is_not_a_multiplier() -> void:
	_expect(is_equal_approx(Progression.stat_mult(30, 3, Progression.Axis.WARD), 1.0),
		"stat_mult refuses to answer for WARD — use ward_reduction()")
	var jugg: float = Progression.ward_reduction(Progression.MAX_LEVEL, 3)
	_expect(jugg > 0.0, "the Juggernaut actually gets damage reduction")
	_expect(jugg <= Progression.WARD_CAP, "…and it never exceeds the cap")
	_expect(is_equal_approx(Progression.ward_reduction(Progression.MAX_LEVEL, 0), 0.0),
		"a class with WARD 0 gets none, ever")
	# The cap must BIND if MAX_LEVEL is ever raised — assert against an absurd level
	# so a future tower cannot quietly produce an immortal.
	_expect(Progression.ward_reduction(100000, 3) <= Progression.WARD_CAP,
		"the WARD cap holds at any level, however MAX_LEVEL moves")
	_completes("ward_is_capped_and_is_not_a_multiplier")


## Measured, not felt. Stormcaller wins 16-0 on the honest harness because it is
## the only class built end-to-end around ICE-field -> LIGHTNING; cooldown recovery
## is exactly the axis that would compound that. If someone later "fixes" the table
## by giving the combo class more FOCUS, this is the tripwire.
func _test_stormcaller_is_denied_focus_four() -> void:
	var storm: Array = Progression.CLASS_GROWTH[6]
	_expect(int(storm[Progression.Axis.FOCUS]) < 4,
		"Stormcaller does NOT get FOCUS 4 — cooldown growth compounds its measured 16-0")
	_expect(int(storm[Progression.Axis.SWIFTNESS]) >= 3,
		"…it gets mobility instead, so the class still has a growth fantasy")
	_completes("stormcaller_is_denied_focus_four")


## THE GUARD THAT KEEPS CO-OP OUT OF SOLO. A party of one must be identical to no
## party at all, or the co-op rule has silently changed the single-player game.
func _test_solo_is_untouched_by_the_coop_rule() -> void:
	for l: int in range(1, Progression.MAX_LEVEL + 1):
		_expect(Progression.party_growth_level([l]) == l,
			"a party of one at level %d plays at level %d" % [l, l])
	_completes("solo_is_untouched_by_the_coop_rule")


## Maker: "in co-op I would want them to experience the climbing of the tower
## without being overlevelled at the first fight". Growth caps at the TRAILING
## member. Mirrors GameState.party_start_floor, which takes the lowest checkpoint.
func _test_the_party_climbs_at_the_trailing_member() -> void:
	_expect(Progression.party_growth_level([3, 25]) == 3,
		"a level-25 friend plays at the level-3's power")
	_expect(Progression.party_growth_level([25, 3]) == 3,
		"who joined first cannot change the answer — it is a min, not a first-wins")
	_expect(Progression.party_growth_level([12, 12]) == 12,
		"two equals are not penalised at all")
	_expect(Progression.party_growth_level([]) == 1,
		"an empty party still names a level rather than erroring")
	_expect(Progression.party_growth_level([0, -9]) == 1, "junk levels clamp to 1")
	_expect(Progression.party_growth_level([999, 999]) == Progression.MAX_LEVEL,
		"…and are clamped to the cap at the top end")
	# THE POINT OF THE WHOLE RULE, stated as a consequence: the capped friend brings
	# their level-1 stat block, i.e. exactly the authored class, to the new player's
	# first fight. Their SPELLS are untouched — that is deliberately not asserted
	# here because it is an absence, and it is pinned where the tree is spent.
	var capped: int = Progression.party_growth_level([1, Progression.MAX_LEVEL])
	_expect(is_equal_approx(Progression.stat_mult(capped, 3, Progression.Axis.VITALITY), 1.0),
		"a max-level friend joining a fresh climber fights floor 1 at authored stats")
	_completes("the_party_climbs_at_the_trailing_member")


func _test_class_unlocking_shape() -> void:
	_expect(Progression.STARTING_CLASSES.size() == 6, "six classes to start")
	_expect(Progression.LOCKED_CLASSES.size() == 3, "three are withheld")
	# No overlap, and together they are exactly the nine.
	for c: int in Progression.LOCKED_CLASSES:
		_expect(not Progression.STARTING_CLASSES.has(c), "class %d is not both" % c)
	_expect(Progression.STARTING_CLASSES.size() + Progression.LOCKED_CLASSES.size()
			== Progression.CLASS_GROWTH.size(),
		"starting + locked covers every class exactly once")
	# The three withheld are the combo/thrall/parry trio — and Stormcaller being one
	# of them is the balance fix, so it is named rather than left to the list order.
	_expect(Progression.LOCKED_CLASSES.has(6),
		"Stormcaller is a LATE unlock — that is what defuses its 16-0 as a beginner trap")
	_expect(Progression.is_class_unlocked(0, []), "a starter is unlocked with nothing earned")
	# ⚠ THE ROSTER GATE IS A SURFACED DECISION, so this asserts the SHIPPED POLICY by
	# name rather than whichever behaviour the constant happens to select. Flipping
	# `ALL_CLASSES_UNLOCKED` fails HERE, loudly and on purpose: it is a design change
	# and it should have to be made twice. Same idiom as `slice_test_climb`'s pins on
	# `RESET_CLIMB_ON_GAME_OVER` and `SOLO_SELF_REVIVE_CHARGES`.
	_expect(Progression.ALL_CLASSES_UNLOCKED == true,
		"SHIPPED POLICY: the whole roster is open (ALL_CLASSES_UNLOCKED == true), "
		+ "because the maker asked to playtest nine classes without grinding floor 5 "
		+ "four times. Set it false to restore the guardian unlocks — and update this test.")
	if Progression.ALL_CLASSES_UNLOCKED:
		# Open roster: every class answers unlocked, and there is nothing left to pick.
		for c: int in Progression.CLASS_GROWTH.size():
			_expect(Progression.is_class_unlocked(c, []), "class %d is pickable with nothing earned" % c)
		_expect(Progression.choosable_classes([]).is_empty(),
			"a guardian has nothing left to grant while the roster is open")
		# …and an off-the-end id is still refused, or a corrupt save picks class 47.
		_expect(not Progression.is_class_unlocked(99, []), "an off-the-end class is still refused")
		_expect(not Progression.is_class_unlocked(-1, []), "…and a negative one")
	else:
		# The DESIGNED behaviour, still asserted so it cannot rot while it is switched off.
		_expect(not Progression.is_class_unlocked(6, []), "a locked class is locked with nothing earned")
		_expect(Progression.is_class_unlocked(6, [6]), "…and unlocked once earned")
		_expect(Progression.is_class_unlocked(6, [6.0]),
			"…including through a JSON float (the M9 trap: parse gives 6.0, not 6)")
		var left: Array[int] = Progression.choosable_classes([6])
		_expect(left.size() == 2, "two remain to pick after the first unlock")
		_expect(not left.has(6), "…and the one already earned is not offered again")
		_expect(Progression.choosable_classes([6, 7, 8]).is_empty(), "nothing left once all three are had")
	_completes("class_unlocking_shape")


## The economy, printed. Not an assertion — a thing a person can read and disagree
## with, which is the only way a curve nobody has played gets corrected.
func _print_the_economy() -> void:
	print("")
	print("── THE LEVELLING ECONOMY ──────────────────────────────────────────────")
	print("  GROWTH %.3f/level · LEVELS_PER_FLOOR %.2f · depth_gain %.4f/floor (derived)"
		% [Progression.GROWTH, Progression.LEVELS_PER_FLOOR, Progression.depth_gain()])
	print("  floor | bodies | floor xp | per body | guardian | clear | expected lvl")
	for f: int in range(1, _floor_budgets.size() + 1):
		print("  %5d | %6d | %8d | %8d | %8d | %5d | %.1f"
			% [f, _budget(f), int(round(Progression.floor_xp_value(f))),
				Progression.enemy_xp(f, _budget(f)), Progression.guardian_xp(f),
				Progression.clear_xp(f), Progression.expected_level_on_floor(f)])
	print("  level | xp to next | career total | floor-1 bodies to level (THE FARM METER)")
	for l: int in [1, 5, 10, 12, 15, 20, 25, 29]:
		print("  %5d | %10d | %12d | %d"
			% [l, Progression.xp_to_next(l), Progression.total_xp_for_level(l),
				Progression.kills_to_level(1, l, _budget(1))])
	var banked: float = 0.0
	for f: int in range(1, _floor_budgets.size() + 1):
		banked += Progression.floor_xp_value(f)
	print("  one full climb banks %d xp -> level %d"
		% [int(round(banked)), Progression.level_for_xp(int(round(banked)))])
	print("───────────────────────────────────────────────────────────────────────")
