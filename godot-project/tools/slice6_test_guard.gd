# GuardComponent — the single mitigation path (gear armour, one-shot robe, ward
# spells). Pure arithmetic + timers, so it is provable without a scene.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_guard.gd
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
	"gear_parity",
	"absorb",
	"order",
	"replace_not_stack",
	"attachment",
	"reduction_floor",
]

var _fails: int = 0
var _completed: Dictionary = {}

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_gear_parity()
	_test_absorb()
	_test_order()
	_test_replace_not_stack()
	_test_attachment()
	_test_reduction_floor()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Guard tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Guard tests: all PASS")
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


func _guard() -> GuardComponent:
	var host := Node.new()
	root.add_child(host)
	return GuardComponent.of(host)


## The gear maths must match what Hero.take_damage did inline before this
## existed, or every existing loadout silently rebalances.
func _test_gear_parity() -> void:
	var g := _guard()
	g.set_gear(0.15, 0.5)                       # armour 15%, robe soaks 50% once
	# 100 -> 85 (armour) -> 42.5 -> 43 (robe, rounded), robe then spent.
	_expect(g.mitigate(100) == 43, "first hit takes armour AND the robe")
	_expect(g.mitigate(100) == 85, "second hit takes armour only — robe is spent")
	# Re-applying gear re-arms the robe (a fresh loadout = a fresh ward).
	g.set_gear(0.15, 0.5)
	_expect(g.mitigate(100) == 43, "re-applying gear re-arms the one-shot robe")
	# No gear at all is an identity transform, so an un-geared hero is unchanged.
	var plain := _guard()
	_expect(plain.mitigate(100) == 100, "an empty guard changes nothing")
	_expect(plain.is_idle(), "an empty guard reports itself idle")
	_completes("gear_parity")


func _test_absorb() -> void:
	var g := _guard()
	g.grant_absorb(45.0, 6.0)
	_expect(g.mitigate(30) == 0, "an absorb pool eats a hit whole")
	_expect(g.mitigate(30) == 15, "...and the overflow lands once it is drained")
	_expect(g.mitigate(30) == 30, "a drained pool stops mitigating")
	# Expiry.
	var t := _guard()
	t.grant_absorb(50.0, 0.5)
	t._process(0.6)
	_expect(t.mitigate(30) == 30, "an expired absorb pool does nothing")
	# Immunity beats everything, including damage larger than any pool.
	var i := _guard()
	i.grant_immunity(0.3)
	_expect(i.mitigate(999) == 0, "immunity zeroes any hit")
	i._process(0.4)
	_expect(i.mitigate(999) == 999, "immunity expires")
	_completes("absorb")


## Percentages before the pool, so an absorb soaks REDUCED damage and lasts
## longer — that is what makes armour + ward feel worth stacking.
func _test_order() -> void:
	var g := _guard()
	# 20% armour, deliberately inside MIN_DAMAGE_MULT so this test measures ORDER
	# and not the floor — real gear reduction is ~15%, so this is representative.
	g.set_gear(0.2, 0.0)
	g.grant_absorb(20.0, 5.0)
	# 100 -> 80 by armour, then 20 eaten by the pool -> 60 lands, pool empty.
	_expect(g.mitigate(100) == 60, "reductions apply before the absorb pool")
	_expect(g.absorb <= 0.01, "the pool drained by the REDUCED amount")
	# Zero and negative damage must pass through untouched and consume nothing.
	var z := _guard()
	z.grant_absorb(50.0, 5.0)
	_expect(z.mitigate(0) == 0, "a zero hit passes through")
	_expect(z.absorb == 50.0, "...and does not drain the pool")
	_completes("order")


## Wards REPLACE rather than stack: dash i-frames + a free parry + stacking
## absorbs is the fastest route to an un-hittable player.
func _test_replace_not_stack() -> void:
	var g := _guard()
	g.grant_absorb(30.0, 5.0)
	g.grant_absorb(30.0, 5.0)
	_expect(g.absorb == 30.0, "absorb refreshes rather than doubling (got %f)" % g.absorb)
	g.grant_reduction(0.3, 4.0)
	g.grant_reduction(0.3, 4.0)
	_expect(is_equal_approx(g.timed_reduction, 0.3), "reduction refreshes rather than summing")
	# A stronger ward still upgrades a weaker one.
	g.grant_absorb(80.0, 5.0)
	_expect(g.absorb == 80.0, "a stronger ward replaces a weaker one")
	# Reduction is capped so nothing reaches full immunity by stacking percentages.
	g.grant_reduction(5.0, 1.0)
	_expect(g.timed_reduction <= 0.95, "reduction is capped below total immunity")
	_completes("replace_not_stack")


func _test_attachment() -> void:
	var host := Node.new()
	root.add_child(host)
	_expect(GuardComponent.peek(host) == null, "peek does not create a guard")
	var a := GuardComponent.of(host)
	var b := GuardComponent.of(host)
	_expect(a == b, "of() returns the SAME guard rather than stacking children")
	_expect(GuardComponent.peek(host) == a, "peek finds an attached guard")
	# Duck-typed on ANY node, so Enemy/Boss/bots work with no extra code.
	_expect(GuardComponent.of(null) == null, "a null body yields no guard")
	_expect(GuardComponent.peek(null) == null, "peeking a null body is safe")
	_completes("attachment")


## Percentages compose multiplicatively toward invulnerability without any single
## number looking wrong, so the STANDING stack is floored.
func _test_reduction_floor() -> void:
	var g := _guard()
	g.set_gear(0.5, 0.0)
	g.grant_reduction(0.5, 5.0)      # 0.5 * 0.5 = 0.25x, below the floor
	_expect(g.mitigate(100) == int(round(100.0 * GuardComponent.MIN_DAMAGE_MULT)),
		"stacked standing reduction is floored (got %d)" % g.mitigate(100))
	# A one-shot soak is spent immediately, so it cannot compound and applies on
	# top of the floor — which is also what keeps existing gear behaviour intact.
	var h := _guard()
	h.set_gear(0.15, 0.5)
	_expect(h.mitigate(100) == 43, "the one-shot robe still stacks past the floor")
	_completes("reduction_floor")
