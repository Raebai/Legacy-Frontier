# Run: godot --headless --path godot-project --script tools/slice_test_deflect_angle.gd
#
# A DEFLECTED SPELL COMES OFF THE GUARD, AT THE ANGLE THE GUARD WAS HELD.
#
# Maker, live playtest: *"remember deflect should send the spell back out from the
# deflect angle as well"*.
#
# Before this, `Hero.try_parry` and `Hero._guard_deflect_sweep` sent every caught
# thing straight down `_aim_dir`. That was a deliberate choice over return-to-sender
# and it is written up at length in `Hero.try_parry`'s header — but it is not an
# ANGLE: the exit ignored where the shot came from entirely, so in a duel (where both
# bots aim at each other) every parry looked exactly like return-to-sender and the
# orientation of the guard meant nothing at all.
#
# The guard is a PLANE now, `SpellDeflect.return_dir` is the only place that fact is
# expressed, and this suite is what stops it drifting back.
#
# THE FOUR PROPERTIES, in the order they matter:
#
#   1. SQUARE STILL RETURNS TO SENDER. The most satisfying outcome must stay the most
#      obvious input, or the change is a nerf wearing a feature's clothes.
#   2. AN ANGLED GUARD DOUBLES THE ANGLE. This is the actual ask, and it is the only
#      property that distinguishes the new behaviour from the old one.
#   3. IT CAN NEVER COME BACK AT YOU. Falls out of the mirror's algebra
#      (`out.dot(n) == -incoming.dot(n)`) given the MIN_FACE_DOT gate — but "falls
#      out of the algebra" is exactly the kind of claim that stops being true after
#      one refactor, so it is asserted directly over a swept range.
#   4. IT IS NEVER ZERO. A deflect that returns a zero vector stops the spell dead in
#      the air, which is indistinguishable from the feature being broken.
#
# ⚠ LOADED BY PATH, NEVER BY `class_name`. `SpellDeflect` names Juice / CombatVfx /
# ImpactFrame, and naming the class here would compile that chain at THIS script's
# parse time — before the main loop registers a single autoload.
#
# ⚠ NEVER `failed += _test_x()`. A dead property read aborts the enclosing function
# and hands back the return type's zero, which reads as "no failures". Failures
# accumulate on `_fails`, and every test records a COMPLETION SENTINEL so a test that
# aborts half-way fails the suite by absence.
extends SceneTree

const DEFLECT_PATH: String = "res://scripts/combat/SpellDeflect.gd"
const HERO_PATH: String = "res://scripts/combat/Hero.gd"
const ARC_PATH: String = "res://scripts/combat/HorizonArc.gd"

const TESTS: Array[String] = [
	"square_still_returns_to_sender",
	"an_angled_guard_doubles_the_angle",
	"it_never_comes_back_at_the_defender",
	"it_is_never_zero",
	"a_glancing_guard_shoves_along_the_guard",
	"degenerate_inputs_are_survivable",
	"incoming_is_asked_of_the_spell_first",
	"every_deflect_path_uses_the_shared_angle",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _sd: GDScript = null
var _k: Dictionary = {}


## A projectile that answers the house contract, so `incoming_dir_of` has something
## real to interrogate. Counters record WHICH source was believed.
class ProjStub extends Node2D:
	var _dir: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var use_velocity: bool = false
	var velocity_asks: int = 0

	func travel_velocity() -> Vector2:
		velocity_asks += 1
		return vel if use_velocity else Vector2.ZERO


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_sd = load(DEFLECT_PATH) as GDScript
	if _sd == null:
		printerr("deflect_angle: FAIL — could not load SpellDeflect.gd")
		printerr("deflect angle tests: 1 FAILED")
		quit(1)
		return true
	_k = _sd.get_script_constant_map()

	_test_square()
	_test_doubles()
	_test_never_backwards()
	_test_never_zero()
	_test_glancing()
	_test_degenerate()
	_test_incoming_source()
	_test_every_path_shares_it()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("deflect_angle: TEST DID NOT COMPLETE — %s (it aborted part-way)" % name)
	if _fails == 0:
		print("deflect angle tests: all PASS")
	else:
		printerr("deflect angle tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("deflect_angle: FAIL — %s" % what)


func _out(guard: Vector2, incoming: Vector2) -> Vector2:
	return _sd.call("return_dir", guard, incoming)


func _min_dot() -> float:
	return float(_k.get("MIN_FACE_DOT", 0.25))


# --------------------------------------------------------------------------- 1
## Meet the shot SQUARE and it goes straight back down the line it arrived on. This
## is the property that lets the change ship: everything that felt good before still
## behaves the way it did.
func _test_square() -> void:
	for a: float in [0.0, PI * 0.5, PI, -PI * 0.37, 2.1]:
		var n: Vector2 = Vector2.from_angle(a)          # the guard faces the shot
		var incoming: Vector2 = -n                       # ...and the shot comes at it
		var out: Vector2 = _out(n, incoming)
		_expect(out.distance_to(n) < 0.001,
			"a square guard at %.2f rad did not return the shot to sender (got %s)"
				% [a, out])
	_completed["square_still_returns_to_sender"] = true


# --------------------------------------------------------------------------- 2
## THE ASK ITSELF. Hold the guard `theta` off square and the shot leaves `2*theta`
## off return-to-sender. If this ever stops being true the feature is gone, whatever
## the other tests say.
func _test_doubles() -> void:
	# 30 degrees off square. Guard faces RIGHT; the shot arrives 30 deg off head-on.
	var n: Vector2 = Vector2.RIGHT
	for theta: float in [deg_to_rad(15.0), deg_to_rad(30.0), deg_to_rad(50.0)]:
		# Incoming is (-n) rotated by theta — i.e. theta away from meeting it square.
		var incoming: Vector2 = (-n).rotated(theta)
		var out: Vector2 = _out(n, incoming)
		# The mirror sends it out at theta on the OTHER side of the guard normal.
		var expected: Vector2 = n.rotated(-theta)
		_expect(out.distance_to(expected) < 0.002,
			"a guard %.0f deg off square did not double the angle (got %s, wanted %s)"
				% [rad_to_deg(theta), out, expected])
		# ...and stated the other way round, because the above could pass on a sign
		# convention that is consistently wrong: the exit must NOT be the guard line.
		_expect(out.distance_to(n) > 0.01,
			"a guard %.0f deg off square still sent the shot down the guard line — "
				% rad_to_deg(theta)
				+ "that is the OLD aim-direct behaviour, not a deflect angle")
	_completed["an_angled_guard_doubles_the_angle"] = true


# --------------------------------------------------------------------------- 3
## A deflected spell may never travel back into the body that deflected it. Swept
## over the whole legal fan rather than spot-checked, because the guarantee is an
## algebraic consequence and those are exactly what refactors quietly break.
func _test_never_backwards() -> void:
	var floor_dot: float = _min_dot()
	var worst: float = 99.0
	for gi: int in 24:
		var n: Vector2 = Vector2.from_angle(TAU * float(gi) / 24.0)
		for si: int in 48:
			var incoming: Vector2 = Vector2.from_angle(TAU * float(si) / 48.0)
			var out: Vector2 = _out(n, incoming)
			worst = minf(worst, out.dot(n))
	_expect(worst >= floor_dot - 0.001,
		"a deflected spell left with only %.3f along the guard — the floor is "
			% worst + "MIN_FACE_DOT (%.3f), below which it is heading back at you"
			% floor_dot)
	_completed["it_never_comes_back_at_the_defender"] = true


# --------------------------------------------------------------------------- 4
## Zero would stop the spell dead in the air, which reads as the deflect being broken
## rather than as anything having been deflected.
func _test_never_zero() -> void:
	for gi: int in 16:
		var n: Vector2 = Vector2.from_angle(TAU * float(gi) / 16.0)
		for si: int in 16:
			var incoming: Vector2 = Vector2.from_angle(TAU * float(si) / 16.0)
			var out: Vector2 = _out(n, incoming)
			_expect(out.length() > 0.9,
				"return_dir handed back a %.3f-length vector (guard %s, incoming %s)"
					% [out.length(), n, incoming])
	_completed["it_is_never_zero"] = true


# --------------------------------------------------------------------------- 5
## A guard barely in the shot's way must SHOVE rather than mirror. The mirror would
## let a grazing shot slide past almost unchanged, and "I deflected that and nothing
## happened" reads as a bug.
func _test_glancing() -> void:
	var n: Vector2 = Vector2.RIGHT
	# Perpendicular: the guard is edge-on to the shot, dot == 0, well above the gate.
	var out: Vector2 = _out(n, Vector2.UP)
	_expect(out.distance_to(n) < 0.001,
		"an edge-on guard mirrored instead of shoving along the guard (got %s)" % out)
	# ...and a shot arriving FROM BEHIND the guard is shoved on, never dragged back.
	var behind: Vector2 = _out(n, Vector2.RIGHT)
	_expect(behind.distance_to(n) < 0.001,
		"a shot from behind the guard was not sent along the guard (got %s)" % behind)
	_completed["a_glancing_guard_shoves_along_the_guard"] = true


# --------------------------------------------------------------------------- 6
## The three degenerate inputs the live paths can genuinely hand this: no guard, no
## incoming, and neither. None may return zero and none may throw.
func _test_degenerate() -> void:
	_expect(_out(Vector2.ZERO, Vector2.LEFT).length() > 0.9,
		"a zero guard produced no direction at all")
	_expect(_out(Vector2.ZERO, Vector2.LEFT).distance_to(Vector2.LEFT) < 0.001,
		"a zero guard should let the shot carry on, not invent an angle")
	_expect(_out(Vector2.UP, Vector2.ZERO).distance_to(Vector2.UP) < 0.001,
		"an unknown incoming line should fall back to the guard line")
	_expect(_out(Vector2.ZERO, Vector2.ZERO).length() > 0.9,
		"both inputs zero produced no direction at all")
	_completed["degenerate_inputs_are_survivable"] = true


# --------------------------------------------------------------------------- 7
## `incoming_dir_of` must ASK the spell before it guesses. A guessed line (spell ->
## body) is right often enough to hide a broken interrogation, so the stub records
## whether it was asked at all.
func _test_incoming_source() -> void:
	var p := ProjStub.new()
	p.use_velocity = true
	p.vel = Vector2(0.0, 300.0)
	root.add_child(p)
	p.global_position = Vector2(100.0, 0.0)
	var got: Vector2 = _sd.call("incoming_dir_of", p, p.global_position, Vector2.ZERO)
	_expect(p.velocity_asks > 0, "incoming_dir_of never asked for travel_velocity")
	_expect(got.distance_to(Vector2.DOWN) < 0.001,
		"the live travel velocity was not believed (got %s)" % got)
	# With no velocity, the house `_dir` member is next.
	p.use_velocity = false
	p._dir = Vector2.LEFT
	got = _sd.call("incoming_dir_of", p, p.global_position, Vector2.ZERO)
	_expect(got.distance_to(Vector2.LEFT) < 0.001,
		"the spell's own _dir was not believed (got %s)" % got)
	# With neither, the geometric line from the spell to the body it reached.
	p._dir = Vector2.ZERO
	got = _sd.call("incoming_dir_of", p, Vector2(100.0, 0.0), Vector2.ZERO)
	_expect(got.distance_to(Vector2.LEFT) < 0.001,
		"the spell -> body fallback line was wrong (got %s)" % got)
	# A dead projectile must not crash the parry.
	_expect(_sd.call("incoming_dir_of", null, Vector2.ZERO, Vector2.RIGHT) != null,
		"a null projectile broke incoming_dir_of")
	p.queue_free()
	_completed["incoming_is_asked_of_the_spell_first"] = true


# --------------------------------------------------------------------------- 8
## ⚠ THE ASSERTION THAT MATTERS MOST. Every property above is about one pure
## function; none of them notice if a call site stops calling it. There are four
## deflect paths in this game and they have drifted apart before — the whole reason
## `SpellDeflect.note_deflect` exists is that one of them was invisible to the
## harness for months.
##
## Checked by source text rather than by behaviour because the live paths need a
## Hero, a rig, an arena and four autoloads to reach, and a suite that heavy would be
## skipped rather than fixed the first time it went red.
func _test_every_path_shares_it() -> void:
	var hero: String = FileAccess.get_file_as_string(HERO_PATH)
	var arc: String = FileAccess.get_file_as_string(ARC_PATH)
	_expect(not hero.is_empty() and not arc.is_empty(),
		"could not read Hero.gd / HorizonArc.gd")
	# Hero has exactly two reflect() call sites: try_parry and _guard_deflect_sweep.
	_expect(hero.count("SpellDeflect.return_dir") >= 2,
		"a Hero deflect path stopped going through SpellDeflect.return_dir "
		+ "(found %d of 2)" % hero.count("SpellDeflect.return_dir"))
	# Four beats in Hero: try_parry, the blade sweep, the press-window contact parry
	# and the PERFECT ring contact parry. All four are "a guard turned something
	# away" and all four must sound like it.
	_expect(hero.count("SpellDeflect.beat") >= 4,
		"a Hero deflect path stopped playing the shared beat (found %d of 4)"
			% hero.count("SpellDeflect.beat"))
	_expect(arc.contains("SpellDeflect.return_dir"),
		"Horizon Cut's sweep is not using the shared deflect angle")
	_expect(arc.contains("_sweep_deflect"),
		"Horizon Cut no longer sweeps anything aside")
	# And the old ad-hoc beats must not creep back in beside the shared one.
	_expect(not hero.contains("Sfx.play(\"ding\", 2.0, 0.02)"),
		"a Hero deflect path is playing its own ding again instead of the shared "
		+ "beat — the four paths drifted apart once already")
	_completed["every_deflect_path_uses_the_shared_angle"] = true
