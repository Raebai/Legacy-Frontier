# ParryRing — deflect as a visible shrinking ring you time, with a weaker
# sustained guard if you overshoot and hold.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_parry_ring.gd
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
	"shrink_and_reset",
	"timing_bands",
	"sustain_is_weaker",
	"ult_interaction",
	"guard_blocks_attack",
	"rearm",
]

var _fails: int = 0
var _completed: Dictionary = {}

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_shrink_and_reset()
	_test_timing_bands()
	_test_sustain_is_weaker()
	_test_ult_interaction()
	_test_guard_blocks_attack()
	_test_rearm()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Parry ring tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Parry ring tests: all PASS")
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


func _held(seconds: float) -> ParryRing:
	var r := ParryRing.new()
	var _p: bool = r.press()
	r.tick(seconds)
	return r


func _test_shrink_and_reset() -> void:
	var r := ParryRing.new()
	_expect(is_equal_approx(r.radius01(), ParryRing.RADIUS_MAX),
		"an idle ring sits at full radius")
	var _p: bool = r.press()
	_expect(is_equal_approx(r.radius01(), ParryRing.RADIUS_MAX),
		"the ring blooms at full radius on press")
	r.tick(ParryRing.SHRINK_TIME * 0.5)
	var mid: float = r.radius01()
	_expect(mid < ParryRing.RADIUS_MAX and mid > ParryRing.RADIUS_MIN,
		"the ring shrinks while held (got %f)" % mid)
	r.tick(ParryRing.SHRINK_TIME)
	_expect(is_equal_approx(r.radius01(), ParryRing.RADIUS_MIN),
		"the ring bottoms out rather than vanishing")
	# Release resets, so every attempt is a fresh committed read.
	r.release()
	_expect(is_equal_approx(r.radius01(), ParryRing.RADIUS_MAX),
		"releasing resets the ring to full")
	_expect(r.quality() == ParryRing.Quality.NONE, "a released ring guards nothing")
	_completes("shrink_and_reset")


## The whole mechanic: too early blocks nothing, the tight band is perfect.
func _test_timing_bands() -> void:
	var early := _held(ParryRing.SHRINK_TIME * 0.3)
	_expect(early.quality() == ParryRing.Quality.NONE,
		"a still-closing ring does not block — pressing early is not a shield")
	_expect(is_equal_approx(early.damage_mult(), 1.0), "...and takes full damage")
	var perfect := _held(ParryRing.SHRINK_TIME * 0.9)
	_expect(perfect.quality() == ParryRing.Quality.PERFECT,
		"the tight band is the perfect window")
	_expect(is_equal_approx(perfect.damage_mult(), 0.0), "a perfect read negates entirely")
	_expect(perfect.can_reflect(), "a perfect read reflects")
	# The window must be genuinely reactable, not a single frame.
	var window: float = (ParryRing.PERFECT_END - ParryRing.PERFECT_START) * ParryRing.SHRINK_TIME
	_expect(window >= 0.05, "the perfect window is reactable (%.3f s)" % window)
	_expect(window <= 0.20, "...but still demanding (%.3f s)" % window)
	_completes("timing_bands")


## Holding is allowed and useful, but must never beat timing it.
func _test_sustain_is_weaker() -> void:
	var sustained := _held(ParryRing.SHRINK_TIME * 2.5)
	_expect(sustained.quality() == ParryRing.Quality.SUSTAIN,
		"overshooting drops into a sustained guard rather than failing outright")
	_expect(sustained.damage_mult() > 0.0, "a sustained guard still takes damage")
	_expect(sustained.damage_mult() < 1.0, "...but chips it, so holding is not pointless")
	_expect(not sustained.can_reflect(),
		"a sustained guard never reflects — the safe option must not also be the strong one")
	# Holding longer must not creep back toward perfect.
	var forever := _held(ParryRing.SHRINK_TIME * 20.0)
	_expect(forever.quality() == ParryRing.Quality.SUSTAIN,
		"holding indefinitely stays sustained")
	_expect(is_equal_approx(forever.damage_mult(), sustained.damage_mult()),
		"holding longer grants no further benefit")
	_completes("sustain_is_weaker")


## The ring feeds SpellDeflect's victim contract: only a perfect read clears the
## tight ult window, so an ult can never be turned by simply holding guard.
func _test_ult_interaction() -> void:
	var perfect := _held(ParryRing.SHRINK_TIME * 0.9)
	_expect(is_equal_approx(perfect.freshness(), 1.0),
		"a perfect read reports full freshness")
	_expect(perfect.freshness() >= 1.0 - SpellDeflect.WINDOW_ULT,
		"...which clears the ult window")
	var sustained := _held(ParryRing.SHRINK_TIME * 3.0)
	_expect(is_equal_approx(sustained.freshness(), 0.0),
		"a sustained guard reports no freshness")
	_expect(sustained.freshness() < 1.0 - SpellDeflect.WINDOW_ULT,
		"...so holding guard can never turn an ult")
	_completes("ult_interaction")


## Holding guard must cost your offence, or the safe option is free.
func _test_guard_blocks_attack() -> void:
	var r := ParryRing.new()
	_expect(not r.blocks_attack(), "not guarding leaves attacking free")
	var _p: bool = r.press()
	_expect(r.blocks_attack(), "guarding locks out attacking from the first frame")
	r.tick(ParryRing.SHRINK_TIME * 3.0)
	_expect(r.blocks_attack(), "a sustained guard still costs your offence")
	r.release()
	_expect(not r.blocks_attack(), "releasing frees attacking again")
	_completes("guard_blocks_attack")


## Mashing guard must not carpet the fight in perfect reads.
func _test_rearm() -> void:
	var r := ParryRing.new()
	_expect(r.press(), "a fresh guard comes up")
	r.tick(ParryRing.SHRINK_TIME * 0.9)
	_expect(r.quality() == ParryRing.Quality.PERFECT, "and can be timed perfectly")
	r.release()
	_expect(not r.is_ready(), "releasing starts a re-arm")
	_expect(not r.press(), "a mashed re-press is refused while re-arming")
	_expect(r.quality() == ParryRing.Quality.NONE, "a refused press guards nothing")
	r.tick(ParryRing.REARM_TIME + 0.01)
	_expect(r.is_ready(), "the guard re-arms after the gap")
	_expect(r.press(), "and can be pressed again")
	_completes("rearm")
