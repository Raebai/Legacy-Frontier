# ParryRing — deflect as a visible shrinking ring you time, with a weaker
# sustained guard if you overshoot and hold.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_parry_ring.gd
extends SceneTree

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_shrink_and_reset()
	failed += _test_timing_bands()
	failed += _test_sustain_is_weaker()
	failed += _test_ult_interaction()
	failed += _test_guard_blocks_attack()
	if failed > 0:
		printerr("Parry ring tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Parry ring tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _held(seconds: float) -> ParryRing:
	var r := ParryRing.new()
	r.press()
	r.tick(seconds)
	return r


func _test_shrink_and_reset() -> int:
	var ok: int = 0
	var r := ParryRing.new()
	ok += _expect(is_equal_approx(r.radius01(), ParryRing.RADIUS_MAX),
		"an idle ring sits at full radius")
	r.press()
	ok += _expect(is_equal_approx(r.radius01(), ParryRing.RADIUS_MAX),
		"the ring blooms at full radius on press")
	r.tick(ParryRing.SHRINK_TIME * 0.5)
	var mid: float = r.radius01()
	ok += _expect(mid < ParryRing.RADIUS_MAX and mid > ParryRing.RADIUS_MIN,
		"the ring shrinks while held (got %f)" % mid)
	r.tick(ParryRing.SHRINK_TIME)
	ok += _expect(is_equal_approx(r.radius01(), ParryRing.RADIUS_MIN),
		"the ring bottoms out rather than vanishing")
	# Release resets, so every attempt is a fresh committed read.
	r.release()
	ok += _expect(is_equal_approx(r.radius01(), ParryRing.RADIUS_MAX),
		"releasing resets the ring to full")
	ok += _expect(r.quality() == ParryRing.Quality.NONE, "a released ring guards nothing")
	return ok


## The whole mechanic: too early blocks nothing, the tight band is perfect.
func _test_timing_bands() -> int:
	var ok: int = 0
	var early := _held(ParryRing.SHRINK_TIME * 0.3)
	ok += _expect(early.quality() == ParryRing.Quality.NONE,
		"a still-closing ring does not block — pressing early is not a shield")
	ok += _expect(is_equal_approx(early.damage_mult(), 1.0), "...and takes full damage")
	var perfect := _held(ParryRing.SHRINK_TIME * 0.9)
	ok += _expect(perfect.quality() == ParryRing.Quality.PERFECT,
		"the tight band is the perfect window")
	ok += _expect(is_equal_approx(perfect.damage_mult(), 0.0), "a perfect read negates entirely")
	ok += _expect(perfect.can_reflect(), "a perfect read reflects")
	# The window must be genuinely reactable, not a single frame.
	var window: float = (ParryRing.PERFECT_END - ParryRing.PERFECT_START) * ParryRing.SHRINK_TIME
	ok += _expect(window >= 0.05, "the perfect window is reactable (%.3f s)" % window)
	ok += _expect(window <= 0.20, "...but still demanding (%.3f s)" % window)
	return ok


## Holding is allowed and useful, but must never beat timing it.
func _test_sustain_is_weaker() -> int:
	var ok: int = 0
	var sustained := _held(ParryRing.SHRINK_TIME * 2.5)
	ok += _expect(sustained.quality() == ParryRing.Quality.SUSTAIN,
		"overshooting drops into a sustained guard rather than failing outright")
	ok += _expect(sustained.damage_mult() > 0.0, "a sustained guard still takes damage")
	ok += _expect(sustained.damage_mult() < 1.0, "...but chips it, so holding is not pointless")
	ok += _expect(not sustained.can_reflect(),
		"a sustained guard never reflects — the safe option must not also be the strong one")
	# Holding longer must not creep back toward perfect.
	var forever := _held(ParryRing.SHRINK_TIME * 20.0)
	ok += _expect(forever.quality() == ParryRing.Quality.SUSTAIN,
		"holding indefinitely stays sustained")
	ok += _expect(is_equal_approx(forever.damage_mult(), sustained.damage_mult()),
		"holding longer grants no further benefit")
	return ok


## The ring feeds SpellDeflect's victim contract: only a perfect read clears the
## tight ult window, so an ult can never be turned by simply holding guard.
func _test_ult_interaction() -> int:
	var ok: int = 0
	var perfect := _held(ParryRing.SHRINK_TIME * 0.9)
	ok += _expect(is_equal_approx(perfect.freshness(), 1.0),
		"a perfect read reports full freshness")
	ok += _expect(perfect.freshness() >= 1.0 - SpellDeflect.WINDOW_ULT,
		"...which clears the ult window")
	var sustained := _held(ParryRing.SHRINK_TIME * 3.0)
	ok += _expect(is_equal_approx(sustained.freshness(), 0.0),
		"a sustained guard reports no freshness")
	ok += _expect(sustained.freshness() < 1.0 - SpellDeflect.WINDOW_ULT,
		"...so holding guard can never turn an ult")
	return ok


## Holding guard must cost your offence, or the safe option is free.
func _test_guard_blocks_attack() -> int:
	var ok: int = 0
	var r := ParryRing.new()
	ok += _expect(not r.blocks_attack(), "not guarding leaves attacking free")
	r.press()
	ok += _expect(r.blocks_attack(), "guarding locks out attacking from the first frame")
	r.tick(ParryRing.SHRINK_TIME * 3.0)
	ok += _expect(r.blocks_attack(), "a sustained guard still costs your offence")
	r.release()
	ok += _expect(not r.blocks_attack(), "releasing frees attacking again")
	return ok
