# SigilGuard — the CASTER's guard: a magic circle summoned on time, which
# absorbs the spell and sends it back. Proves the two things that must be true:
# the mage runs on the SAME ParryRing clock as the swordsman (one timing model,
# two costumes), and the stronger outcome is paid for with a strictly harder read.
#
# ⚠⚠ WHAT THIS SUITE DOES NOT PROVE, AND ITS GREEN LINE IMPLIES: that anything in
# the game ever BUILDS a SigilGuard. Nothing does. Every fixture here is a 5-line
# stub victim; no Hero, Enemy or Boss is touched, so "all PASS" is a true statement
# about the class in isolation and says nothing about whether the feature exists.
# `SigilGuard.of()` has zero production call sites and the mage never gets a SIGIL
# ring. See the header of scripts/combat/SigilGuard.gd for the evidence and for
# what wiring it would take — including the `guard_style` hazard that must be fixed
# in the same change.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_sigil_guard.gd
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
	"one_clock_two_styles",
	"the_mage_pays_for_it",
	"sigil_has_no_safe_fallback",
	"sigil_can_still_turn_an_ult",
	"attachment",
	"absorb_returns_an_echo",
	"echo_is_capped_and_rate_limited",
	"echo_never_auto_aims",
	"spell_deflect_routes_through_the_sigil",
]

var _fails: int = 0
var _completed: Dictionary = {}

var _ran: bool = false


## A victim that parries perfectly — the shape SpellDeflect's contract expects.
class Caster extends Node:
	func is_parrying() -> bool:
		return true

	func parry_freshness() -> float:
		return 1.0


## Something the echo may legitimately fly into, so a hit can be observed. In the
## "enemy" group because that is the echo's default return_group — the group is a
## FILTER on what the echo runs into, never a list it searches.
class Dummy extends Node2D:
	var taken: int = 0

	func _ready() -> void:
		add_to_group("enemy")
		# ...and `mortal`, the shared damageable-fighter group every hero attack scans
		# now that friendly fire is on. A real `Enemy` joins both; a stub that joined only
		# `enemy` would be invisible to every hero spell and swing in the game.
		add_to_group(SpellCaster.MORTAL_GROUP)

	func take_damage(amount: int) -> void:
		taken += amount


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_one_clock_two_styles()
	_test_the_mage_pays_for_it()
	_test_sigil_has_no_safe_fallback()
	_test_sigil_can_still_turn_an_ult()
	_test_attachment()
	_test_absorb_returns_an_echo()
	_test_echo_is_capped_and_rate_limited()
	_test_echo_never_auto_aims()
	_test_spell_deflect_routes_through_the_sigil()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Sigil guard tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Sigil guard tests: all PASS")
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


func _ring(style: int, seconds: float) -> ParryRing:
	var r := ParryRing.for_style(style)
	var _p: bool = r.press()
	r.tick(seconds)
	return r


## An armed sigil on a host that is really in the tree, which is what summon()
## and the echo spawn both need.
func _armed(dir: Vector2 = Vector2.RIGHT) -> SigilGuard:
	var host := Node2D.new()
	root.add_child(host)
	var s := SigilGuard.of(host)
	s.summon(dir, Color(0.7, 0.5, 1.0))
	return s


func _echoes() -> Array:
	var out: Array = []
	for n: Node in root.get_children():
		if n is SigilGuard.Echo:
			out.append(n)
	return out


func _clear_echoes() -> void:
	for e: Node in _echoes():
		root.remove_child(e)
		e.free()


## The whole point of putting style on ParryRing instead of writing a second
## timer: press/release/shrink/re-arm are ONE implementation, and a class only
## moves the numbers. If these ever diverge, the two guards will drift apart.
func _test_one_clock_two_styles() -> void:
	var blade := _ring(ParryRing.Style.BLADE, ParryRing.SHRINK_TIME * 0.5)
	var sigil := _ring(ParryRing.Style.SIGIL, ParryRing.SHRINK_TIME * 0.5)
	_expect(is_equal_approx(blade.progress(), sigil.progress()),
		"both styles run the same clock")
	_expect(is_equal_approx(blade.radius01(), sigil.radius01()),
		"both styles shrink identically — the circle IS the ring, drawn differently")
	_expect(blade.blocks_attack() and sigil.blocks_attack(),
		"both styles cost your offence while the guard is genuinely up")
	# A fresh sigil is refused while re-arming exactly like a blade.
	var s := ParryRing.for_style(ParryRing.Style.SIGIL)
	_expect(s.press(), "a fresh sigil comes up")
	s.release()
	_expect(not s.press(), "a mashed sigil is refused while re-arming")
	_completes("one_clock_two_styles")


## Absorb-and-return beats eat-the-hit, so it must be harder to land. The trade
## is paid in three places; all three must actually be true, not just documented.
func _test_the_mage_pays_for_it() -> void:
	var blade := ParryRing.for_style(ParryRing.Style.BLADE)
	var sigil := ParryRing.for_style(ParryRing.Style.SIGIL)
	# 1. A tighter window.
	_expect(sigil.perfect_window() < blade.perfect_window(),
		"the sigil's window is tighter (%.3f s vs %.3f s)"
			% [sigil.perfect_window(), blade.perfect_window()])
	_expect(sigil.perfect_window() >= 0.04,
		"...but still reactable rather than a coin flip (%.3f s)" % sigil.perfect_window())
	# 2. A longer re-arm.
	_expect(sigil.rearm_time() > blade.rearm_time(),
		"a whiffed summoning costs more than a whiffed parry")
	# 3. And the tighter window is REAL: a moment that parries with steel does
	#    nothing at all with a circle.
	var t: float = ParryRing.SHRINK_TIME * 0.80
	_expect(_ring(ParryRing.Style.BLADE, t).quality() == ParryRing.Quality.PERFECT,
		"0.80 through the shrink is a clean blade parry")
	_expect(_ring(ParryRing.Style.SIGIL, t).quality() == ParryRing.Quality.NONE,
		"...and the same moment catches nothing in a circle")
	_completes("the_mage_pays_for_it")


## The largest price, and the one that carries the fantasy: steel degrades into a
## weaker guard, a summoning collapses into nothing.
func _test_sigil_has_no_safe_fallback() -> void:
	var over := _ring(ParryRing.Style.SIGIL, ParryRing.SHRINK_TIME * 2.0)
	_expect(over.is_collapsed(), "an unmet sigil collapses")
	_expect(over.quality() == ParryRing.Quality.NONE,
		"a collapsed sigil guards nothing — there is no sustained circle")
	_expect(is_equal_approx(over.damage_mult(), 1.0),
		"...so an overshot caster takes the hit in full")
	_expect(not over.can_reflect(), "...and returns nothing")
	_expect(not over.blocks_attack(),
		"a collapsed sigil frees your hands — it must not charge the guard's price for no guard")
	# The blade's behaviour is untouched by any of this.
	var blade := _ring(ParryRing.Style.BLADE, ParryRing.SHRINK_TIME * 2.0)
	_expect(blade.quality() == ParryRing.Quality.SUSTAIN,
		"a blade still bottoms out into a sustained guard")
	_expect(blade.blocks_attack(), "...and still costs the swordsman his offence")
	_expect(not blade.is_collapsed(), "a blade never collapses")
	_completes("sigil_has_no_safe_fallback")


## The mage must not be quietly barred from the hardest read in the game.
func _test_sigil_can_still_turn_an_ult() -> void:
	var perfect := _ring(ParryRing.Style.SIGIL, ParryRing.SHRINK_TIME * 0.93)
	_expect(perfect.quality() == ParryRing.Quality.PERFECT,
		"deep in the band is a clean catch")
	_expect(perfect.freshness() >= 1.0 - SpellDeflect.WINDOW_ULT,
		"a caught spell clears the ult window")
	var collapsed := _ring(ParryRing.Style.SIGIL, ParryRing.SHRINK_TIME * 2.0)
	_expect(collapsed.freshness() < 1.0 - SpellDeflect.WINDOW_ULT,
		"a collapsed sigil can never turn an ult")
	_completes("sigil_can_still_turn_an_ult")


## Same duck-typed idiom as GuardComponent, so SpellDeflect can find it on any
## body without the victim contract growing a method.
func _test_attachment() -> void:
	var host := Node2D.new()
	root.add_child(host)
	_expect(SigilGuard.peek(host) == null, "peek does not create a sigil")
	var a := SigilGuard.of(host)
	var b := SigilGuard.of(host)
	_expect(a == b, "of() returns the SAME sigil rather than stacking children")
	_expect(SigilGuard.peek(host) == a, "peek finds an attached sigil")
	_expect(SigilGuard.of(null) == null, "a null body yields no sigil")
	_expect(SigilGuard.peek(null) == null, "peeking a null body is safe")
	# Not armed until summoned, so a caster who never pressed guard absorbs nothing.
	_expect(not a.is_armed(), "an unsummoned sigil is not armed")
	a.summon(Vector2.RIGHT, Color.WHITE)
	_expect(a.is_armed(), "summoning arms it")
	a.dismiss()
	_expect(not a.is_armed(), "dismissing disarms it")
	_completes("attachment")


## "Absorbed and sent back" — for a spell that cannot physically be reversed, the
## circle condenses it into an echo rather than silently eating it, so the player
## reads ONE defensive verb whatever they just blocked.
func _test_absorb_returns_an_echo() -> void:
	_clear_echoes()
	var s := _armed(Vector2.RIGHT)
	s.absorb(40, Vector2.LEFT, Vector2(100.0, 0.0))
	var es: Array = _echoes()
	_expect(es.size() == 1, "an absorbed spell sends something back (got %d)" % es.size())
	if es.size() == 1:
		var e: SigilGuard.Echo = es[0]
		_expect(e.damage == int(round(40.0 * SigilGuard.ECHO_DAMAGE_MULT)),
			"the echo carries a FRACTION of what was swallowed, not the whole spell (got %d)" % e.damage)
		_expect(e.global_position.is_equal_approx(Vector2(100.0, 0.0)),
			"the echo leaves from where the catch happened")
		# It damages what it physically reaches — no seeking, no steering.
		var d := Dummy.new()
		root.add_child(d)
		d.global_position = e.global_position
		_expect(e.check_hit(), "the echo hits a valid target it reaches")
		_expect(d.taken == e.damage, "...for its payload (got %d)" % d.taken)
		root.remove_child(d)
		d.free()
	_clear_echoes()
	_completes("absorb_returns_an_echo")


## A non-travelling spell's damage is per-tick and an ult tick is enormous. The
## defensive verb must never become the highest-damage action in the game.
func _test_echo_is_capped_and_rate_limited() -> void:
	_clear_echoes()
	var s := _armed(Vector2.RIGHT)
	s.absorb(100000, Vector2.LEFT, Vector2.ZERO)
	var es: Array = _echoes()
	_expect(es.size() == 1, "one absorb, one echo")
	if es.size() == 1:
		_expect((es[0] as SigilGuard.Echo).damage == SigilGuard.ECHO_DAMAGE_CAP,
			"an absorbed ult tick is capped (got %d)" % (es[0] as SigilGuard.Echo).damage)
	_clear_echoes()
	# A ZONE ticks repeatedly: every tick is still absorbed, but the return is not
	# a firehose. Nothing defensive is lost — only the extra echoes are dropped.
	s._process(SigilGuard.ECHO_MIN_INTERVAL + 0.01)   # clear the interval from above
	s.absorb(40, Vector2.LEFT, Vector2.ZERO)
	s.absorb(40, Vector2.LEFT, Vector2.ZERO)
	s.absorb(40, Vector2.LEFT, Vector2.ZERO)
	_expect(_echoes().size() == 1, "repeated ticks return ONE echo, not one each")
	_clear_echoes()
	s._process(SigilGuard.ECHO_MIN_INTERVAL + 0.01)
	s.absorb(40, Vector2.LEFT, Vector2.ZERO)
	_expect(_echoes().size() == 1, "the echo re-arms after its interval")
	_clear_echoes()
	_completes("echo_is_capped_and_rate_limited")


## The locked project rule. The echo goes where the PLAYER pointed the circle,
## and never hunts for a body to fly at.
func _test_echo_never_auto_aims() -> void:
	_clear_echoes()
	# A juicy target sitting far off to the LEFT, which the echo must ignore.
	var bait := Dummy.new()
	root.add_child(bait)
	bait.global_position = Vector2(-900.0, 0.0)
	var s := _armed(Vector2.RIGHT)
	s.absorb(40, Vector2(-1.0, 0.0), Vector2.ZERO)
	var es: Array = _echoes()
	_expect(es.size() == 1, "the catch returned an echo")
	if es.size() == 1:
		var e: SigilGuard.Echo = es[0]
		_expect(e.dir.is_equal_approx(Vector2.RIGHT),
			"the echo flies where the CIRCLE pointed, not at the nearest body (got %s)" % e.dir)
	_clear_echoes()
	# With no meaningful facing, it falls back to the exact reverse of the
	# incoming direction — still a direction the fight handed it, never a search.
	# (Reaching into _dir deliberately: this is the documented fallback branch,
	# which a summoned sigil normalises away.)
	var s2 := _armed(Vector2.RIGHT)
	s2._dir = Vector2.ZERO
	s2.absorb(40, Vector2.RIGHT, Vector2.ZERO)
	var es2: Array = _echoes()
	_expect(es2.size() == 1, "the fallback still returns an echo")
	if es2.size() == 1:
		_expect((es2[0] as SigilGuard.Echo).dir.is_equal_approx(Vector2.LEFT),
			"...back the way the spell came")
	_clear_echoes()
	bait.free()
	_completes("echo_never_auto_aims")


## The integration that makes any of this reachable: resolve()'s signature is
## UNCHANGED (fifteen spell scripts are being written against it), and the
## class-specific outcome is discovered on the victim instead of passed in.
func _test_spell_deflect_routes_through_the_sigil() -> void:
	_clear_echoes()
	# A swordsman: blocks fully, returns nothing.
	var blade := Caster.new()
	root.add_child(blade)
	_expect(SpellDeflect.resolve(blade, 90, Vector2.LEFT, Vector2.ZERO) == 0,
		"a swordsman's parry still negates the hit")
	_expect(_echoes().is_empty(), "...and sends nothing back")
	blade.free()
	# A caster with a summoned circle: blocks exactly as fully, AND returns.
	var mage := Caster.new()
	root.add_child(mage)
	var s := SigilGuard.of(mage)
	s.summon(Vector2.RIGHT, Color(0.7, 0.5, 1.0))
	_expect(SpellDeflect.resolve(mage, 90, Vector2.LEFT, Vector2.ZERO) == 0,
		"a caught spell deals no damage either — the READ is identical")
	_expect(_echoes().size() == 1, "...but the circle sends something back")
	_clear_echoes()
	# An unarmed caster (never pressed guard, or the circle already collapsed)
	# must not return anything off someone else's parry state.
	s.dismiss()
	_expect(SpellDeflect.resolve(mage, 90, Vector2.LEFT, Vector2.ZERO) == 0,
		"a dismissed circle still blocks via the shared path")
	_expect(_echoes().is_empty(), "...but returns nothing without a circle up")
	_clear_echoes()
	mage.free()
	_completes("spell_deflect_routes_through_the_sigil")
