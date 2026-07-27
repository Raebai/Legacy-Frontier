# GuardComponent — the single mitigation path (gear armour, one-shot robe, ward
# spells). Pure arithmetic + timers, so it is provable without a scene.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_guard.gd
extends SceneTree

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_gear_parity()
	failed += _test_absorb()
	failed += _test_order()
	failed += _test_replace_not_stack()
	failed += _test_attachment()
	if failed > 0:
		printerr("Guard tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Guard tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _guard() -> GuardComponent:
	var host := Node.new()
	root.add_child(host)
	return GuardComponent.of(host)


## The gear maths must match what Hero.take_damage did inline before this
## existed, or every existing loadout silently rebalances.
func _test_gear_parity() -> int:
	var ok: int = 0
	var g := _guard()
	g.set_gear(0.15, 0.5)                       # armour 15%, robe soaks 50% once
	# 100 -> 85 (armour) -> 42.5 -> 43 (robe, rounded), robe then spent.
	ok += _expect(g.mitigate(100) == 43, "first hit takes armour AND the robe")
	ok += _expect(g.mitigate(100) == 85, "second hit takes armour only — robe is spent")
	# Re-applying gear re-arms the robe (a fresh loadout = a fresh ward).
	g.set_gear(0.15, 0.5)
	ok += _expect(g.mitigate(100) == 43, "re-applying gear re-arms the one-shot robe")
	# No gear at all is an identity transform, so an un-geared hero is unchanged.
	var plain := _guard()
	ok += _expect(plain.mitigate(100) == 100, "an empty guard changes nothing")
	ok += _expect(plain.is_idle(), "an empty guard reports itself idle")
	return ok


func _test_absorb() -> int:
	var ok: int = 0
	var g := _guard()
	g.grant_absorb(45.0, 6.0)
	ok += _expect(g.mitigate(30) == 0, "an absorb pool eats a hit whole")
	ok += _expect(g.mitigate(30) == 15, "...and the overflow lands once it is drained")
	ok += _expect(g.mitigate(30) == 30, "a drained pool stops mitigating")
	# Expiry.
	var t := _guard()
	t.grant_absorb(50.0, 0.5)
	t._process(0.6)
	ok += _expect(t.mitigate(30) == 30, "an expired absorb pool does nothing")
	# Immunity beats everything, including damage larger than any pool.
	var i := _guard()
	i.grant_immunity(0.3)
	ok += _expect(i.mitigate(999) == 0, "immunity zeroes any hit")
	i._process(0.4)
	ok += _expect(i.mitigate(999) == 999, "immunity expires")
	return ok


## Percentages before the pool, so an absorb soaks REDUCED damage and lasts
## longer — that is what makes armour + ward feel worth stacking.
func _test_order() -> int:
	var ok: int = 0
	var g := _guard()
	g.set_gear(0.5, 0.0)          # halve everything
	g.grant_absorb(20.0, 5.0)
	# 100 -> 50 by armour, then 20 eaten by the pool -> 30 lands, pool empty.
	ok += _expect(g.mitigate(100) == 30, "reductions apply before the absorb pool")
	ok += _expect(g.absorb <= 0.01, "the pool drained by the REDUCED amount")
	# Zero and negative damage must pass through untouched and consume nothing.
	var z := _guard()
	z.grant_absorb(50.0, 5.0)
	ok += _expect(z.mitigate(0) == 0, "a zero hit passes through")
	ok += _expect(z.absorb == 50.0, "...and does not drain the pool")
	return ok


## Wards REPLACE rather than stack: dash i-frames + a free parry + stacking
## absorbs is the fastest route to an un-hittable player.
func _test_replace_not_stack() -> int:
	var ok: int = 0
	var g := _guard()
	g.grant_absorb(30.0, 5.0)
	g.grant_absorb(30.0, 5.0)
	ok += _expect(g.absorb == 30.0, "absorb refreshes rather than doubling (got %f)" % g.absorb)
	g.grant_reduction(0.3, 4.0)
	g.grant_reduction(0.3, 4.0)
	ok += _expect(is_equal_approx(g.timed_reduction, 0.3), "reduction refreshes rather than summing")
	# A stronger ward still upgrades a weaker one.
	g.grant_absorb(80.0, 5.0)
	ok += _expect(g.absorb == 80.0, "a stronger ward replaces a weaker one")
	# Reduction is capped so nothing reaches full immunity by stacking percentages.
	g.grant_reduction(5.0, 1.0)
	ok += _expect(g.timed_reduction <= 0.95, "reduction is capped below total immunity")
	return ok


func _test_attachment() -> int:
	var ok: int = 0
	var host := Node.new()
	root.add_child(host)
	ok += _expect(GuardComponent.peek(host) == null, "peek does not create a guard")
	var a := GuardComponent.of(host)
	var b := GuardComponent.of(host)
	ok += _expect(a == b, "of() returns the SAME guard rather than stacking children")
	ok += _expect(GuardComponent.peek(host) == a, "peek finds an attached guard")
	# Duck-typed on ANY node, so Enemy/Boss/bots work with no extra code.
	ok += _expect(GuardComponent.of(null) == null, "a null body yields no guard")
	ok += _expect(GuardComponent.peek(null) == null, "peeking a null body is safe")
	return ok
