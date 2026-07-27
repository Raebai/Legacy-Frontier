# SpellDeflect — every attack spell is parryable, and an ult is brutal but not
# exempt. Pure resolve() logic, driven against stub victims so the timing rules
# are provable without a scene.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_spell_deflect.gd
extends SceneTree

var _ran: bool = false


## A victim that reports a parry window and records being deflected against.
class Guard extends Node:
	var parrying: bool = true
	var freshness: float = 1.0
	var deflected: int = 0
	var last_dir: Vector2 = Vector2.ZERO

	func is_parrying() -> bool:
		return parrying

	func parry_freshness() -> float:
		return freshness

	func on_spell_deflected(dir: Vector2) -> void:
		deflected += 1
		last_dir = dir


## An older victim that can block but cannot report freshness — must keep working.
class LegacyGuard extends Node:
	var parrying: bool = true

	func is_parrying() -> bool:
		return parrying


## Something with no defensive vocabulary at all, e.g. a crate.
class Bystander extends Node:
	pass


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_ordinary_spells()
	failed += _test_ults_are_hard_but_possible()
	failed += _test_contract_tolerance()
	if failed > 0:
		printerr("Spell deflect tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Spell deflect tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_ordinary_spells() -> int:
	var ok: int = 0
	var g := Guard.new()
	root.add_child(g)
	# Anywhere inside the window blocks an ordinary spell — even the last sliver.
	g.freshness = 0.05
	var dealt: int = SpellDeflect.resolve(g, 90, Vector2.RIGHT, Vector2.ZERO)
	ok += _expect(dealt == 0, "a parried ordinary spell deals no damage (got %d)" % dealt)
	ok += _expect(g.deflected == 1, "the victim is told it deflected")
	ok += _expect(g.last_dir == Vector2.RIGHT, "the deflect carries the spell's direction")
	# Not parrying -> full damage passes through untouched.
	g.parrying = false
	ok += _expect(SpellDeflect.resolve(g, 90, Vector2.RIGHT, Vector2.ZERO) == 90,
		"an unparried spell deals its full damage")
	ok += _expect(g.deflected == 1, "no deflect is recorded when not parrying")
	g.free()
	return ok


func _test_ults_are_hard_but_possible() -> int:
	var ok: int = 0
	var g := Guard.new()
	root.add_child(g)
	# Late in the window: an ordinary spell is blocked, the ult is NOT. This is
	# the whole point — same press, different outcome by timing.
	g.freshness = 0.5
	ok += _expect(SpellDeflect.resolve(g, 200, Vector2.RIGHT, Vector2.ZERO) == 0,
		"a late parry still stops an ordinary spell")
	var late_ult: int = SpellDeflect.resolve(g, 200, Vector2.RIGHT, Vector2.ZERO,
		SpellDeflect.WINDOW_ULT)
	ok += _expect(late_ult == 200, "a late parry does NOT stop an ult (got %d)" % late_ult)
	# Pressed on the exact frame: the ult IS turned. It must be possible, not a lie.
	g.freshness = 1.0
	var perfect: int = SpellDeflect.resolve(g, 200, Vector2.RIGHT, Vector2.ZERO,
		SpellDeflect.WINDOW_ULT)
	ok += _expect(perfect == 0, "a frame-perfect parry DOES turn an ult (got %d)" % perfect)
	# The boundary is where the constant says it is, not somewhere accidental.
	g.freshness = 1.0 - SpellDeflect.WINDOW_ULT + 0.01
	ok += _expect(SpellDeflect.would_deflect(g, SpellDeflect.WINDOW_ULT),
		"just inside the ult window connects")
	g.freshness = 1.0 - SpellDeflect.WINDOW_ULT - 0.01
	ok += _expect(not SpellDeflect.would_deflect(g, SpellDeflect.WINDOW_ULT),
		"just outside the ult window does not")
	ok += _expect(SpellDeflect.WINDOW_ULT < SpellDeflect.WINDOW_NORMAL,
		"an ult window is strictly tighter than an ordinary one")
	g.free()
	return ok


func _test_contract_tolerance() -> int:
	var ok: int = 0
	# A victim with no freshness reporting keeps the lenient behaviour rather
	# than silently losing the ability to block anything.
	var legacy := LegacyGuard.new()
	root.add_child(legacy)
	ok += _expect(SpellDeflect.resolve(legacy, 70, Vector2.RIGHT, Vector2.ZERO) == 0,
		"a victim without freshness reporting can still parry")
	ok += _expect(SpellDeflect.would_deflect(legacy, SpellDeflect.WINDOW_ULT),
		"...and is not quietly barred from parrying ults")
	legacy.free()
	# Anything with no defensive vocabulary simply takes the hit.
	var crate := Bystander.new()
	root.add_child(crate)
	ok += _expect(SpellDeflect.resolve(crate, 55, Vector2.RIGHT, Vector2.ZERO) == 55,
		"a target that cannot parry takes full damage")
	ok += _expect(not SpellDeflect.would_deflect(crate), "...and never reads as parrying")
	crate.free()
	# A freed/null victim must not crash a damage loop mid-iteration.
	ok += _expect(SpellDeflect.resolve(null, 40, Vector2.RIGHT, Vector2.ZERO) == 40,
		"a null victim passes damage through instead of erroring")
	return ok
