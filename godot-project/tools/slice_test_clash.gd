# Run: godot --headless --path godot-project --script tools/slice_test_clash.gd
# THE CLASH (scripts/combat/MeleeClash.gd) — two fighters commit a blow at each
# other inside the same short window and the blows MEET instead of trading damage.
#
# WHAT THIS SUITE IS ACTUALLY FOR. The clash window is the whole feature and it is
# a pure guess, so the assertions that matter most are the boundary ones — and of
# those, THE NEGATIVE IS THE IMPORTANT ONE. A window that is too generous turns
# every melee trade into a clash, which does not look like a bug, it looks like
# melee stopped working. `blow_outside_window_does_not_clash` is the guard against
# shipping that, and it is deliberately asserted twice: once through the pure
# timing predicate and once through the real `declare()` path with real bodies.
#
# ⚠ TEST HYGIENE — the idiom this file refuses to use. `failed += _test_x()` is a
# trap in GDScript: reading a member that no longer exists is NOT a failure, it
# logs a runtime error, ABORTS the enclosing function on the spot and hands the
# caller back the return type's zero — which that idiom reads as "no failures".
# 64 suites in this repo were silently passing that way. So:
#   1. failures accumulate on the MEMBER `_fails`, never on a return value;
#   2. every test records a COMPLETION SENTINEL as its last line, so a test that
#      dies half-way fails the suite BY ABSENCE whatever the cause.
# Reference: tools/slice_test_loadout.gd.
extends SceneTree

const TESTS: Array[String] = [
	"weight_matches_spell_vocabulary",
	"simultaneous_blows_clash",
	"blow_outside_window_does_not_clash",
	"equal_weight_is_symmetric",
	"heavier_blow_overpowers",
	"clash_spends_both_attacks",
	"aim_and_reach_are_mutual",
	"refractory_prevents_clash_lock",
	"deferred_contact_consumes_once",
	"body_origin_beats_a_stale_transform",
]

## A fighter that is nothing but a position, a swing and a recorder. Node2D so
## SpellTargets can measure it; `apply_knockback` so MeleeClash._recoil finds a
## real path rather than silently doing nothing (a stub with no recoil method
## would let a broken _recoil pass unnoticed).
class Fighter:
	extends Node2D
	var shoves: int = 0
	var last_impulse: Vector2 = Vector2.ZERO

	func apply_knockback(impulse: Vector2, _do_flop: bool = true) -> void:
		shoves += 1
		last_impulse = impulse


## A fighter shaped like the playground's SpikeFigure: the NODE never moves, the
## real body is somewhere else entirely, and it publishes where via `body_origin`.
## Exists to pin the regression that made the clash silently never fire.
class DetachedFighter:
	extends Fighter
	var origin: Vector2 = Vector2.ZERO

	func body_origin() -> Vector2:
		return origin

	## Silhouette measured from the REAL body, exactly as SpikeFigure's does — so
	## the reach half of the gate cannot pass by accident off the stale transform.
	func body_distance(p: Vector2) -> float:
		return origin.distance_to(p)

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	# No juice: the beat awaits a hit-stop and spawns an impact-frame node, neither
	# of which belongs in a headless suite. The RULE is what is under test.
	MeleeClash.effects_enabled = false
	_test_weight_matches_spell_vocabulary()
	_test_simultaneous_blows_clash()
	_test_blow_outside_window_does_not_clash()
	_test_equal_weight_is_symmetric()
	_test_heavier_blow_overpowers()
	_test_clash_spends_both_attacks()
	_test_aim_and_reach_are_mutual()
	_test_refractory_prevents_clash_lock()
	_test_deferred_contact_consumes_once()
	_test_body_origin_beats_a_stale_transform()
	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			print("  FAIL [sentinel] test '%s' never reached its end — it aborted part-way" % name)
	if _fails == 0:
		print("clash tests: all PASS (%d tests)" % TESTS.size())
	else:
		print("clash tests: %d FAILURES" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


# --------------------------------------------------------------------- helpers

func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		print("  FAIL: %s" % what)


## Two fighters facing each other, `gap` px apart, freshly registered. Returns
## [left, right]. Clears clash state so each test starts from nothing.
func _pair(gap: float = 60.0) -> Array:
	MeleeClash.reset()
	var a := Fighter.new()
	var b := Fighter.new()
	root.add_child(a)
	root.add_child(b)
	a.global_position = Vector2.ZERO
	b.global_position = Vector2(gap, 0.0)
	return [a, b]


func _drop(pair: Array) -> void:
	for f: Node in pair:
		f.queue_free()


# ----------------------------------------------------------------------- tests

## Weight is SpellTier's, not a second scheme. If this drifts, a melee clash and a
## spell clash have started teaching two different rules.
func _test_weight_matches_spell_vocabulary() -> void:
	_expect(MeleeClash.weight_for(14) == SpellTier.Tier.QUICK, "a 14-damage jab is QUICK")
	_expect(MeleeClash.weight_for(30) == SpellTier.Tier.HEAVY, "a 30-damage greatsword swing is HEAVY")
	_expect(MeleeClash.weight_for(60) == SpellTier.Tier.ULT, "a 60-damage blow is ULT")
	# The comparison itself must come from SpellTier, so retuning the spell shelves
	# moves melee with them.
	_expect(MeleeClash.resolve_outcome(SpellTier.Tier.QUICK, SpellTier.Tier.QUICK)
		== MeleeClash.OUTCOME_EVEN, "equal shelves cancel, exactly as two spells do")
	_expect(MeleeClash.resolve_outcome(SpellTier.Tier.ULT, SpellTier.Tier.QUICK)
		== MeleeClash.OUTCOME_OVERPOWERED, "the heavier shelf overpowers")
	_expect(MeleeClash.resolve_outcome(SpellTier.Tier.QUICK, SpellTier.Tier.HEAVY)
		== MeleeClash.OUTCOME_OUTWEIGHED, "the lighter shelf is outweighed")
	_completed["weight_matches_spell_vocabulary"] = true


## The positive case: two blows a few frames apart, aimed at each other, clash.
func _test_simultaneous_blows_clash() -> void:
	var p: Array = _pair()
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 1000)
	# 50 ms apart — three frames at 60 Hz, well inside the 90 ms window.
	var r: Dictionary = MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 1050)
	_expect(bool(r["clashed"]), "blows 50 ms apart clash")
	_expect(r["opponent"] == p[0], "the clash names the other fighter")
	# The beat is staged at the MEETING POINT, not on either body — that midpoint is
	# what every effect in _beat is positioned by.
	_expect(Vector2(r["at"]).is_equal_approx(Vector2(30.0, 0.0)),
		"the clash is staged midway between the fighters, got %s" % [r["at"]])
	_drop(p)
	_completed["simultaneous_blows_clash"] = true


## ⭐ THE IMPORTANT NEGATIVE. A window too generous turns every trade into a clash
## and destroys melee, so this asserts the boundary from both sides — through the
## pure predicate and through the real declare() path.
func _test_blow_outside_window_does_not_clash() -> void:
	var window_ms: int = int(round(MeleeClash.CLASH_WINDOW * 1000.0))
	_expect(MeleeClash.timing_matches(1000, 1000 + window_ms),
		"exactly on the window edge still counts as simultaneous")
	_expect(not MeleeClash.timing_matches(1000, 1000 + window_ms + 1),
		"one millisecond past the edge does NOT")
	# THE HARD CEILING, asserted against a literal rather than against the constant
	# itself — otherwise this test moves whenever the window does and guards nothing.
	# 0.20 s is the SHORTEST melee cooldown in the game (Hero's Brawler). A window at
	# or above it means two fighters mashing at that cadence clash on every single
	# swing, forever: melee would look broken rather than exciting. If a future tune
	# trips this, the window has gone past the point where the feature is a feature.
	_expect(MeleeClash.CLASH_WINDOW < 0.20,
		"the clash window must stay under the shortest melee cooldown (0.20 s), got %.3f"
			% MeleeClash.CLASH_WINDOW)
	_expect(not MeleeClash.timing_matches(1000, 1200),
		"blows a full Brawler cooldown apart are a trade, never a clash")
	# ...and the floor: a window that only spans a couple of frames fires never.
	_expect(MeleeClash.CLASH_WINDOW >= 0.05,
		"a window under ~3 frames would make the feature invisible, got %.3f"
			% MeleeClash.CLASH_WINDOW)
	# ...and through the whole machine, with real bodies in range and aimed.
	var p: Array = _pair()
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 2000)
	var r: Dictionary = MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 2000 + window_ms + 20)
	_expect(not bool(r["clashed"]),
		"a blow past the window is an ordinary trade, not a clash")
	_expect(not bool(r["spent"]), "...and therefore still deals its damage")
	_expect(p[0].shoves == 0 and p[1].shoves == 0, "...and nobody was thrown")
	# The first fighter's blow must ALSO still be live — a near-miss must not have
	# quietly consumed it.
	_expect(not MeleeClash.consume_spent(p[0]), "the earlier blow was not spent either")
	_drop(p)
	_completed["blow_outside_window_does_not_clash"] = true


## Equal weight is symmetric: both spent, both thrown, and thrown APART rather than
## both the same way.
func _test_equal_weight_is_symmetric() -> void:
	var p: Array = _pair()
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 3000)
	var r: Dictionary = MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 3020)
	_expect(String(r["outcome"]) == MeleeClash.OUTCOME_EVEN, "equal weight = an even clash")
	_expect(p[0].shoves == 1 and p[1].shoves == 1, "both fighters were thrown exactly once")
	# Left fighter thrown left, right fighter thrown right.
	_expect(p[0].last_impulse.x < 0.0 and p[1].last_impulse.x > 0.0,
		"they were thrown APART, got %s / %s" % [p[0].last_impulse, p[1].last_impulse])
	_expect(is_equal_approx(p[0].last_impulse.length(), p[1].last_impulse.length()),
		"an even clash throws both sides equally hard")
	_drop(p)
	_completed["equal_weight_is_symmetric"] = true


## Unequal weight resolves the way the spell system would: the heavier blow is NOT
## cancelled, it eats the lighter one and keeps going.
func _test_heavier_blow_overpowers() -> void:
	var p: Array = _pair()
	# Left throws a 30-damage greatsword swing (HEAVY); right throws a jab (QUICK).
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 30, MeleeClash.WEIGHT_AUTO, 4000)
	var r: Dictionary = MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 4030)
	_expect(String(r["outcome"]) == MeleeClash.OUTCOME_OUTWEIGHED,
		"the jab reports itself outweighed")
	_expect(bool(r["spent"]), "the lighter blow is cancelled")
	_expect(p[1].shoves == 1, "the loser is swatted")
	_expect(p[0].shoves == 0, "the winner is NOT thrown — their blow keeps going")
	_expect(not MeleeClash.consume_spent(p[0]),
		"...and the winner's blow is still live, so it will still land")
	_expect(p[1].last_impulse.length() > MeleeClash.THROW_APART,
		"being outweighed throws you harder than an even clash does")
	_drop(p)
	_completed["heavier_blow_overpowers"] = true


## The load-bearing consequence: a clash SPENDS both attacks, so neither one also
## deals damage. Without this the clash would be a free extra effect on top of a
## normal trade rather than a replacement for it.
func _test_clash_spends_both_attacks() -> void:
	var p: Array = _pair()
	var first: Dictionary = MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 5000)
	_expect(not bool(first["spent"]), "an unmatched commit is not spent yet")
	var second: Dictionary = MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 5040)
	_expect(bool(second["spent"]), "the second blow is spent by the clash")
	# The FIRST fighter committed before the clash existed, so it learns its blow
	# was cancelled by asking at contact — that is the deferred-contact path Hero
	# uses, and it is the half that would silently double-hit if it broke.
	_expect(MeleeClash.consume_spent(p[0]), "the first blow is spent too")
	_drop(p)
	_completed["clash_spends_both_attacks"] = true


## A clash needs MUTUAL engagement. Simultaneity alone is not enough, or someone
## swinging at a crate would cancel a blow aimed at them from across the room.
func _test_aim_and_reach_are_mutual() -> void:
	# Aimed away: right fighter swings off to the right, not back at the left one.
	var p: Array = _pair()
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 6000)
	var away: Dictionary = MeleeClash.declare(p[1], Vector2.RIGHT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 6020)
	_expect(not bool(away["clashed"]), "a blow thrown AWAY does not clash")
	_drop(p)
	# Out of reach: simultaneous, mutually aimed, but far too far apart.
	var far: Array = _pair(600.0)
	MeleeClash.declare(far[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 7000)
	var oor: Dictionary = MeleeClash.declare(far[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 7020)
	_expect(not bool(oor["clashed"]), "blows that could never have met do not clash")
	_drop(far)
	# The pure aim predicate, both directions.
	_expect(MeleeClash.aims_at(Vector2.ZERO, Vector2.RIGHT, Vector2(50.0, 0.0)),
		"a swing straight at someone aims at them")
	_expect(not MeleeClash.aims_at(Vector2.ZERO, Vector2.LEFT, Vector2(50.0, 0.0)),
		"a swing in the opposite direction does not")
	_expect(not MeleeClash.aims_at(Vector2.ZERO, Vector2.ZERO, Vector2(50.0, 0.0)),
		"a zero swing direction aims at nothing")
	_completed["aim_and_reach_are_mutual"] = true


## The anti-lock guard: two fighters thrown apart who both swing again immediately
## must TRADE, not clash forever. Without the refractory, a generous window can
## produce a stalemate in which neither fighter can ever take damage.
func _test_refractory_prevents_clash_lock() -> void:
	var p: Array = _pair()
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 8000)
	var first: Dictionary = MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 8020)
	_expect(bool(first["clashed"]), "the first clash fires")
	# Both swing again, still simultaneous, still engaged — but inside the refractory.
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 8300)
	var again: Dictionary = MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 8320)
	_expect(not bool(again["clashed"]),
		"a second simultaneous swing inside the refractory is a real trade")
	# ...and once the refractory has lapsed, clashing is available again.
	var refractory_ms: int = int(round(MeleeClash.CLASH_REFRACTORY * 1000.0))
	var t: int = 8020 + refractory_ms + 50
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, t)
	var later: Dictionary = MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, t + 20)
	_expect(bool(later["clashed"]), "clashing is available again after the refractory")
	_drop(p)
	_completed["refractory_prevents_clash_lock"] = true


## consume_spent() is a CONSUME. A swing may only be cancelled once, or a fighter
## whose blow was clashed would keep skipping damage on every later swing.
func _test_deferred_contact_consumes_once() -> void:
	var p: Array = _pair()
	MeleeClash.declare(p[0], Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 9000)
	MeleeClash.declare(p[1], Vector2.LEFT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 9020)
	_expect(MeleeClash.consume_spent(p[0]), "the cancelled swing reports spent once")
	_expect(not MeleeClash.consume_spent(p[0]), "...and not a second time")
	# A fighter who never committed anything has nothing to consume.
	var lone := Fighter.new()
	root.add_child(lone)
	_expect(not MeleeClash.consume_spent(lone), "a fighter who never swung is never spent")
	lone.queue_free()
	_drop(p)
	_completed["deferred_contact_consumes_once"] = true


## REGRESSION — found by tools/clash_capture.gd, invisible in code review.
##
## The playground's SpikeFigure hangs its whole body off a `_torso` child; the node
## itself never leaves its spawn point. Reading `global_position` therefore reported
## BOTH brawling figures at the same stale spot, the separation between them was
## zero, the mutual-aim gate refused every pair, and the clash never fired once —
## silently, with no error anywhere. This pins the fix: the position is ASKED FOR.
func _test_body_origin_beats_a_stale_transform() -> void:
	MeleeClash.reset()
	var a := DetachedFighter.new()
	var b := DetachedFighter.new()
	root.add_child(a)
	root.add_child(b)
	# Both NODES parked on top of each other at the spawn point — the trap exactly.
	a.global_position = Vector2.ZERO
	b.global_position = Vector2.ZERO
	# ...while the real bodies stand 70 px apart, facing off.
	a.origin = Vector2(200.0, 40.0)
	b.origin = Vector2(270.0, 40.0)
	MeleeClash.declare(a, Vector2.RIGHT, 58.0, 14, MeleeClash.WEIGHT_AUTO, 11000)
	var r: Dictionary = MeleeClash.declare(b, Vector2.LEFT, 58.0, 14,
		MeleeClash.WEIGHT_AUTO, 11030)
	_expect(bool(r["clashed"]),
		"a fighter whose body is not its node still clashes (the capture-found bug)")
	_expect(Vector2(r["at"]).is_equal_approx(Vector2(235.0, 40.0)),
		"...and the beat is staged between the REAL bodies, got %s" % [r["at"]])
	a.queue_free()
	b.queue_free()
	_completed["body_origin_beats_a_stale_transform"] = true
