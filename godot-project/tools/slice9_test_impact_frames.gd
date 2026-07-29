# Run: godot --headless --path godot-project --script tools/slice9_test_impact_frames.gd
#
# THE IMPACT-FRAME ARBITER. The frames themselves are a look and a feel and a
# headless test cannot judge either — that is what tools/impact_frame_capture.gd
# and the maker's eyes are for. What IS testable, and what actually needs
# testing, is the referee: the rules that decide which requests become frames.
# Those rules are the difference between "the game punctuates its big hits" and
# "the screen strobes during a meteor barrage", and between shipping and failing
# a storefront photosensitivity check.
#
# Every assertion below drives `ImpactFrame.decide` with an INJECTED clock, so a
# whole second of gameplay is a handful of integers and none of it depends on
# frame pacing, a camera, a viewport or a rendered pixel.
#
# ⚠ TEST HYGIENE (the trap this codebase has already been bitten by, see
# tools/slice_test_loadout.gd): failures accumulate on the MEMBER `_fails`, never
# via `_fails += _test_x()`. Reading a property that has moved or been renamed is
# not a test failure in GDScript — it logs an error, ABORTS the enclosing
# function, and hands the caller the return type's zero value, which under a
# `+=` idiom reads as "found no failures". So every test records a COMPLETION
# SENTINEL as its last line and a missing sentinel fails the suite by absence.
extends SceneTree

const TESTS: Array[String] = [
	"min_interval", "supersede", "burst_cannot_strobe", "ascending_burst",
	"sliding_window", "frame_time_budget", "reduce_flashing_downgrades",
	"local_is_not_a_flash", "tier_ladder", "durations_are_real_time",
]

var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	_test_min_interval()
	_test_supersede()
	_test_burst_cannot_strobe()
	_test_ascending_burst()
	_test_sliding_window()
	_test_frame_time_budget()
	_test_reduce_flashing_downgrades()
	_test_local_is_not_a_flash()
	_test_tier_ladder()
	_test_durations_are_real_time()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("ImpactFrame tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("ImpactFrame tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Every request goes through here with `reduce` pinned, so a machine whose
## data/tuning.tres happens to have reduce_flashing on cannot silently turn the
## whole suite into a test of the downgrade path.
func _ask(now_ms: int, style: int, strength: float, reduce: bool = false) -> Dictionary:
	return ImpactFrame.decide(
		{"style": style, "strength": strength, "reduce": reduce}, now_ms)


# ---------------------------------------------------------------------- tests
## Two equally-weighted beats close together: the second is DROPPED, not queued.
## Queueing is the failure mode that matters — a deferred frame still plays, so a
## chain of them still strobes, just later.
func _test_min_interval() -> void:
	ImpactFrame.reset_arbiter()
	var a: Dictionary = _ask(0, ImpactFrame.Style.BLOWOUT, 0.8)
	_expect(bool(a["granted"]), "the first request is granted")
	# Still inside the first frame's own duration.
	var b: Dictionary = _ask(100, ImpactFrame.Style.BLOWOUT, 0.8)
	_expect(not bool(b["granted"]), "a same-weight request DURING a frame is dropped")
	_expect(String(b["reason"]) == "weaker_than_active", "...and says why")
	# After it ends, but inside the feel interval.
	var c: Dictionary = _ask(200, ImpactFrame.Style.BLOWOUT, 0.8)
	_expect(not bool(c["granted"]), "a request inside MIN_INTERVAL is dropped")
	_expect(String(c["reason"]) == "min_interval", "...and says why")
	var d: Dictionary = _ask(400, ImpactFrame.Style.BLOWOUT, 0.8)
	_expect(bool(d["granted"]), "a request past MIN_INTERVAL is granted")
	_completes("min_interval")


## A stronger beat REPLACES a weaker one that is already playing, rather than
## waiting behind it — an ult landing mid-jab must not be the one that gets
## dropped. A marginally stronger one does not, or a cluster of near-identical
## requests would churn the screen replacing each other.
func _test_supersede() -> void:
	ImpactFrame.reset_arbiter()
	_expect(bool(_ask(0, ImpactFrame.Style.BLOWOUT, 0.7)["granted"]), "weak frame starts")
	var marginal: Dictionary = _ask(40, ImpactFrame.Style.SILHOUETTE, 0.75)
	_expect(not bool(marginal["granted"]),
		"a marginally stronger request does NOT churn the active frame")
	var strong: Dictionary = _ask(40, ImpactFrame.Style.CUT_IN, 1.4)
	_expect(bool(strong["granted"]), "a decisively stronger request is granted mid-frame")
	_expect(bool(strong["supersede"]), "...and is flagged as a supersede, not a second frame")
	_completes("supersede")


## THE BARRAGE. Twenty equal requests inside half a second — the meteor
## avalanche / chain-reaction shape. At most MAX_FULLSCREEN_FLASHES_PER_SECOND
## may become frames.
func _test_burst_cannot_strobe() -> void:
	ImpactFrame.reset_arbiter()
	var granted: int = 0
	for i in 20:
		if bool(_ask(i * 25, ImpactFrame.Style.BLOWOUT, 1.0)["granted"]):
			granted += 1
	_expect(granted <= ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND,
		"20 requests in 500ms produced %d frames (ceiling %d)"
			% [granted, ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND])
	_expect(granted >= 1, "...but the barrage still gets ONE frame (it is not silenced)")
	_completes("burst_cannot_strobe")


## The adversarial barrage: every request is stronger than the last, so every one
## of them is entitled to supersede. This is the case that would slip past a
## naive "one at a time" rule and strobe anyway, which is exactly why the safety
## ceiling is checked on supersedes too.
func _test_ascending_burst() -> void:
	ImpactFrame.reset_arbiter()
	var starts: Array[int] = []
	for i in 20:
		var t: int = i * 25
		if bool(_ask(t, ImpactFrame.Style.BLOWOUT, 0.3 + 0.065 * float(i))["granted"]):
			starts.append(t)
	# Assert the property directly rather than the count: in EVERY one-second
	# window anywhere on the timeline, no more than the ceiling started.
	var worst: int = 0
	for w in 30:
		var lo: int = w * 25
		var n: int = 0
		for s: int in starts:
			if s >= lo and s < lo + 1000:
				n += 1
		worst = maxi(worst, n)
	_expect(worst <= ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND,
		"ascending barrage put %d flashes in some 1s window (ceiling %d)"
			% [worst, ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND])
	_completes("ascending_burst")


## The window SLIDES, it does not reset on the second. A bucket that resets lets
## two frames just before the boundary and two just after add up to four inside
## one real second while every individual check passed.
func _test_sliding_window() -> void:
	ImpactFrame.reset_arbiter()
	_expect(bool(_ask(0, ImpactFrame.Style.BLOWOUT, 0.8)["granted"]), "flash 1 of the second")
	_expect(bool(_ask(300, ImpactFrame.Style.BLOWOUT, 0.8)["granted"]), "flash 2 of the second")
	var third: Dictionary = _ask(900, ImpactFrame.Style.BLOWOUT, 0.8)
	_expect(not bool(third["granted"]), "a third flash inside the same second is refused")
	_expect(String(third["reason"]) == "flash_rate_ceiling", "...by the SAFETY rule, named")
	# t=1050 is >1000ms after the first, so the first has slid out of the window.
	_expect(bool(_ask(1050, ImpactFrame.Style.BLOWOUT, 0.8)["granted"]),
		"once the oldest flash slides out of the window, the budget frees up")
	_completes("sliding_window")


## The other half of the safety rule: two flashes a second is still unacceptable
## if between them they cover most of that second. Two CUT_INs (0.30s each) would
## be 0.60s of flash inside one second, over the 0.45s cap, so the second is
## refused even though the COUNT would have allowed it.
func _test_frame_time_budget() -> void:
	ImpactFrame.reset_arbiter()
	_expect(bool(_ask(0, ImpactFrame.Style.CUT_IN, 1.4)["granted"]), "the first cut-in plays")
	var second: Dictionary = _ask(400, ImpactFrame.Style.CUT_IN, 1.4)
	_expect(not bool(second["granted"]), "a second long frame inside the same second is refused")
	_expect(String(second["reason"]) == "frame_time_budget", "...by the time budget, named")
	_completes("frame_time_budget")


## reduce-flashing DOWNGRADES; it must never DENY. The beat still happens — the
## player who needs this option still gets punctuation, just not a large-area
## high-contrast flash. (Whether the surrounding hit-stop / shake still fire is
## asserted in Juice, not here; `decide` only owns the mark.)
func _test_reduce_flashing_downgrades() -> void:
	ImpactFrame.reset_arbiter()
	var d: Dictionary = _ask(0, ImpactFrame.Style.CUT_IN, 1.4, true)
	_expect(bool(d["granted"]), "reduce-flashing still grants the beat")
	_expect(int(d["style"]) == ImpactFrame.Style.LOCAL,
		"...as the localized ring, not the full-screen cut-in")
	_expect(float(d["strength"]) <= ImpactFrame.LOCAL_MAX_STRENGTH,
		"...with the contrast clamped, not merely the area shrunk")
	_expect(float(d["duration"]) <= ImpactFrame.DURATION_LOCAL, "...and shortened to match")
	# And every style downgrades, not just the loudest one.
	for style: int in [ImpactFrame.Style.BLOWOUT, ImpactFrame.Style.SILHOUETTE,
			ImpactFrame.Style.COLOR_FIELD, ImpactFrame.Style.INVERT]:
		ImpactFrame.reset_arbiter()
		var r: Dictionary = _ask(0, style, 1.2, true)
		_expect(bool(r["granted"]) and int(r["style"]) == ImpactFrame.Style.LOCAL,
			"style %d downgrades to LOCAL under reduce-flashing" % style)
	_completes("reduce_flashing_downgrades")


## A small low-contrast ring is not a flash, and must not spend the flash budget
## — otherwise a crowd of dying enemies would silently eat the ult's frame.
func _test_local_is_not_a_flash() -> void:
	ImpactFrame.reset_arbiter()
	var locals: int = 0
	for i in 12:
		if bool(_ask(i * 100, ImpactFrame.Style.LOCAL, 0.55)["granted"]):
			locals += 1
	_expect(locals >= 2, "localized rings may repeat (%d in 1.2s)" % locals)
	_expect(locals <= ImpactFrame.MAX_LOCAL_PER_SECOND + 2,
		"...but not without limit (%d)" % locals)
	# The full-screen budget is untouched by all that: a big beat still lands.
	var big: Dictionary = _ask(1400, ImpactFrame.Style.COLOR_FIELD, 1.15)
	_expect(bool(big["granted"]),
		"a crowd of local rings does not spend the full-screen flash budget")
	_completes("local_is_not_a_flash")


## The ladder is a RULE — the same SpellTier shelf the clash layer and the audio
## roster read — so pin it. A jab, a heavy, an ult and a climax must land on four
## different marks, and two ults of different elements must not be identical.
func _test_tier_ladder() -> void:
	var quick: Dictionary = ImpactFrame.ladder(SpellTier.Tier.QUICK)
	var heavy: Dictionary = ImpactFrame.ladder(SpellTier.Tier.HEAVY)
	var ult: Dictionary = ImpactFrame.ladder(SpellTier.Tier.ULT, Elements.Element.FIRE)
	var climax: Dictionary = ImpactFrame.ladder(SpellTier.Tier.ULT, Elements.Element.FIRE, true)
	_expect(int(quick["style"]) == ImpactFrame.Style.LOCAL, "QUICK -> localized ring")
	_expect(int(heavy["style"]) == ImpactFrame.Style.BLOWOUT, "HEAVY -> white blow-out")
	_expect(int(ult["style"]) == ImpactFrame.Style.COLOR_FIELD, "ULT with an element -> colour field")
	_expect(int(climax["style"]) == ImpactFrame.Style.CUT_IN, "ULT + climax -> cut-in")
	# An ult with nothing to colour the field with falls back to the black cut.
	_expect(int(ImpactFrame.ladder(SpellTier.Tier.ULT)["style"]) == ImpactFrame.Style.SILHOUETTE,
		"ULT with no element -> silhouette (a colourless colour field is a grey wash)")
	# ...and the ladder is strictly ascending, so the arbiter's supersede rule
	# makes the heavier beat win when two land together.
	_expect(float(quick["strength"]) < float(heavy["strength"]), "QUICK is lighter than HEAVY")
	_expect(float(heavy["strength"]) < float(ult["strength"]), "HEAVY is lighter than ULT")
	_expect(float(ult["strength"]) < float(climax["strength"]), "ULT is lighter than a climax")
	# The gaps must clear SUPERSEDE_EPSILON or a rung could not interrupt the one
	# below it — the ladder would be decorative.
	_expect(float(heavy["strength"]) - float(quick["strength"]) > ImpactFrame.SUPERSEDE_EPSILON,
		"a HEAVY beat can supersede a QUICK one already playing")
	_expect(float(ult["strength"]) - float(heavy["strength"]) > ImpactFrame.SUPERSEDE_EPSILON,
		"an ULT beat can supersede a HEAVY one already playing")
	_completes("tier_ladder")


## Every mark must be over fast. A frame that outstays the beat stops being
## punctuation and starts being an interruption — and a duration over the safety
## budget could never be granted twice, which would quietly break the ladder.
func _test_durations_are_real_time() -> void:
	for style in [ImpactFrame.Style.BLOWOUT, ImpactFrame.Style.SILHOUETTE,
			ImpactFrame.Style.COLOR_FIELD, ImpactFrame.Style.INVERT,
			ImpactFrame.Style.CUT_IN, ImpactFrame.Style.LOCAL]:
		var d: float = ImpactFrame.default_duration(style)
		_expect(d > 0.0 and d <= 0.35, "style %d duration %.3fs is a beat, not a pause" % [style, d])
		_expect(d <= ImpactFrame.MAX_FRAME_SECONDS_PER_SECOND,
			"style %d fits inside the per-second frame-time budget at all" % style)
	_completes("durations_are_real_time")
