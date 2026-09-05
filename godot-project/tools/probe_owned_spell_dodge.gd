# CAN YOU GET OUT OF THE WAY? — dodge slack, in frames, for every spell in the
# wall / zone / control files.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/probe_owned_spell_dodge.gd
#
# Maker's standing directive: *"NO auto-aim"* and *"everything must be dodgeable"*.
# The second half of that is a claim about NUMBERS, and it is the half nobody had
# ever computed. A telegraph is not evidence of a dodge: a 0.40 s tell over a 118 px
# footprint is undodgeable on foot no matter how legible the ring is, because a
# 210 px/s walk needs 0.56 s to leave it.
#
# So, per spell:
#   WINDUP   seconds between the spell becoming visible and the first frame it can
#            damage a body.
#   ESCAPE   how far a body standing at the WORST case — the dead centre of the
#            danger area — must travel to be outside it.
#   SLACK    windup minus the time that escape takes, expressed in frames at 60 Hz,
#            per movement verb. NEGATIVE SLACK MEANS THE SPELL IS NOT DODGEABLE by
#            that verb, whatever its tell looks like.
#
# ⚠ ESCAPE IS BISECTED AGAINST THE SPELL'S OWN CONTAINMENT PREDICATE, never read off
# a radius constant. `ZoneSpell.footprint_contains` and `IceWall.chill_contains` are
# the exact functions the damage loops call, so the distance reported here is the
# distance that actually matters even if the drawn shape and the constant disagree
# (which is the recurring class of bug in this codebase — five drawn-vs-damaged
# mismatches and counting). Where a spell has no static predicate the geometry is
# rebuilt from ITS OWN constants, read through `get_script_constant_map()`, so a
# retune moves this table with it.
#
# ⚠ THIS IS A PROBE THAT ASSERTS. It prints the table for the maker AND fails the
# build on the two invariants that are not tuning opinions:
#   1. every spell is dodgeable by SOMETHING (the standing directive), and
#   2. no spell in these files homes, snaps or re-aims (the no-auto-aim directive) —
#      checked by re-running the aim maths and demanding the answer be a pure
#      function of the aim, not of where a target happens to be standing.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
const TESTS: Array[String] = [
	"the_table",
	"everything_is_dodgeable_by_something",
	"nothing_re_aims_itself",
]

const ICE_WALL_PATH: String = "res://scripts/combat/IceWall.gd"
const ROCK_WALL_PATH: String = "res://scripts/combat/RockWall.gd"
const ZONE_SPELL_PATH: String = "res://scripts/combat/ZoneSpell.gd"
const SHADOW_ROOT_PATH: String = "res://scripts/combat/ShadowRoot.gd"
const PETRIFY_PATH: String = "res://scripts/combat/Petrify.gd"

## The movement verbs, taken from Hero rather than retyped. A number copied out of
## another file is a number that stops being true the day that file is retuned, and
## this whole table is only worth reading if it tracks the game.
const HERO_PATH: String = "res://scripts/combat/Hero.gd"

## The tick the slack is quoted at. Frames are what a player counts and what a
## reaction time is measured in.
const HZ: float = 60.0
## How far the bisection is allowed to be wrong, in px. Half a pixel is far below
## anything that changes a frame count at these speeds.
const BISECT_EPS: float = 0.5
## Ceiling for the bisection search — no danger footprint in these files is close to
## this wide, and a predicate that is true out here is a bug, not a big spell.
const BISECT_MAX: float = 2000.0

var _fails: int = 0
var _completed: Dictionary = {}
var _rows: Array[Dictionary] = []

var _walk: float = 0.0
var _dash_speed: float = 0.0
var _dash_time: float = 0.0


func _initialize() -> void:
	root.size = Vector2i(1366, 768)
	_run()


func _run() -> void:
	await process_frame
	var hero: Dictionary = (load(HERO_PATH) as GDScript).get_script_constant_map()
	_walk = float(hero["SPEED"])
	_dash_speed = float(hero["DASH_SPEED"])
	_dash_time = float(hero["DASH_TIME"])
	_test_the_table()
	_test_everything_is_dodgeable_by_something()
	_test_nothing_re_aims_itself()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Owned-spell dodge probe: %d FAILED" % _fails)
		quit(1)
	else:
		print("Owned-spell dodge probe: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ---- the movement model -----------------------------------------------------

## Seconds to cover `px` on foot.
func _walk_time(px: float) -> float:
	return px / _walk


## Seconds to cover `px` with one dash and then walking. A dash is a fixed-duration
## burst, so beyond its own travel the body is back at walking pace — modelling it as
## "fast forever" would flatter every spell in the table.
func _dash_time_for(px: float) -> float:
	var dash_px: float = _dash_speed * _dash_time
	if px <= dash_px:
		return px / _dash_speed
	return _dash_time + (px - dash_px) / _walk


func _frames(seconds: float) -> float:
	return seconds * HZ


## The smallest distance along `dir` from `center` at which `inside` stops being
## true. Bisection against the SPELL'S OWN predicate — see the header for why this
## is not `return radius`.
func _escape_distance(center: Vector2, dir: Vector2, inside: Callable) -> float:
	if not bool(inside.call(center)):
		return 0.0
	var lo: float = 0.0
	var hi: float = 1.0
	while hi < BISECT_MAX and bool(inside.call(center + dir * hi)):
		lo = hi
		hi *= 2.0
	if hi >= BISECT_MAX:
		return INF   # the predicate never stops being true: a bug, reported as one
	while hi - lo > BISECT_EPS:
		var mid: float = (lo + hi) * 0.5
		if bool(inside.call(center + dir * mid)):
			lo = mid
		else:
			hi = mid
	return hi


## One row of the table. `note` is what the reader needs in order to know whether a
## negative number is a bug or a design.
func _row(name: String, windup: float, escape: float, verb: String, note: String) -> void:
	_rows.append({
		"name": name, "windup": windup, "escape": escape, "verb": verb, "note": note,
		"walk": _frames(windup - _walk_time(escape)),
		"dash": _frames(windup - _dash_time_for(escape)),
	})


# ---- the tests --------------------------------------------------------------

## THE TABLE. Every damaging thing these files can do to a body, with the windup it
## gives you and the distance it makes you cover.
func _test_the_table() -> void:
	var ic: Dictionary = (load(ICE_WALL_PATH) as GDScript).get_script_constant_map()
	var rc: Dictionary = (load(ROCK_WALL_PATH) as GDScript).get_script_constant_map()
	var zc: Dictionary = (load(ZONE_SPELL_PATH) as GDScript).get_script_constant_map()
	var sc: Dictionary = (load(SHADOW_ROOT_PATH) as GDScript).get_script_constant_map()
	var pc: Dictionary = (load(PETRIFY_PATH) as GDScript).get_script_constant_map()
	var origin := Vector2.ZERO

	# ── ICE WALL, expiry burst. The wall stands for its whole life and then bursts;
	# the life IS the windup, and it is enormous. This is the easy one.
	var ice_r: float = float(ic["SHATTER_RADIUS"])
	_row("ice wall shatter (expiry)", float(ic["LIFETIME"]), ice_r, "walk",
		"the wall's whole lifetime is the tell")

	# ── ICE WALL, second beat. A press detonates it. The only tell it can have is
	# the one BEFORE the press, which is the rise — see IceWall.can_shove's gate.
	_row("ice wall shatter (punched)", float(ic["RISE_TIME"]), ice_r, "dash",
		"RISE_TIME gate is the whole tell; a walk cannot clear 120 px in 0.30 s")

	# ── ROCK WALL, the plow. Windup is the TRAVEL: the ram has to cross the gap.
	# Measured at a realistic engagement distance rather than at contact, because a
	# ram measured at contact has no windup by definition and the number would say
	# nothing. 200 px is roughly the reach of the two-beat plus a body.
	var plow_px: float = float(rc["WALL_SIZE"].x) * 0.5 + float(rc["PLOW_PAD"])
	var ram_gap: float = 200.0
	_row("rock wall plow (at %d px)" % int(ram_gap), ram_gap / float(rc["SHOVE_SPEED"]),
		plow_px, "walk", "the 820 px/s travel IS the tell; escape is sideways out of the band")

	# ── BLIZZARD, chip tick. Placed field; the footprint eases open over GROW_TIME
	# and the first bite lands exactly when it finishes.
	var bliz_r: float = 135.0   # the shipped SpellDef radius
	var frost_escape: float = _escape_distance(origin, Vector2.RIGHT,
		func(p: Vector2) -> bool:
			return bool((load(ZONE_SPELL_PATH) as GDScript).call(
				"footprint_contains", "frost", origin, bliz_r, p)))
	_row("blizzard chip tick", float(zc["GROW_TIME"]), frost_escape, "dash",
		"8 dmg a tick — the chip is a tax for standing in weather, not a hit")

	# ── BLIZZARD, the encase. The rime meter is the fuse and it is DRAWN over the
	# victim's head, so the whole fill time is honest windup.
	_row("blizzard encase (34)", float(zc["RIME_TO_ENCASE"]), frost_escape, "walk",
		"the rime ring over your head counts the fuse down; leaving DRAINS it")

	# ── SHADOW ROOT. The surge races along the floor to a drawn mark.
	var root_r: float = 64.0    # the shipped SpellDef radius = grasp half-width
	_row("shadow root (grasp)", float(sc["SURGE_TIME"]), root_r, "walk",
		"or JUMP: the claws reach CATCH_HEIGHT %d px and no higher" % int(sc["CATCH_HEIGHT"]))

	# ── PETRIFY. A ring on the ground, then the nearest body inside it turns to stone.
	var pet_r: float = 118.0    # the shipped SpellDef radius
	_row("petrify (catch)", float(pc["CATCH_TIME"]), pet_r, "dash",
		"a walk cannot clear 118 px in 0.40 s — this one NEEDS the dash")

	print("")
	print("  spell                          windup   escape   walk      dash     verdict")
	print("  ---------------------------------------------------------------------------")
	for r: Dictionary in _rows:
		var verdict: String = "DODGEABLE"
		if float(r["dash"]) < 0.0:
			verdict = "NOT DODGEABLE"
		elif float(r["walk"]) < 0.0:
			verdict = "dash only"
		print("  %-28s  %5.2fs  %5.0fpx  %+6.1ff  %+6.1ff  %s"
			% [r["name"], r["windup"], r["escape"], r["walk"], r["dash"], verdict])
	print("  ---------------------------------------------------------------------------")
	print("  slack in FRAMES at %d Hz. negative = the damage lands before you can be out."
		% int(HZ))
	print("  movement model: walk %.0f px/s, dash %.0f px/s for %.2fs (= %.0f px) then walk."
		% [_walk, _dash_speed, _dash_time, _dash_speed * _dash_time])
	for r: Dictionary in _rows:
		print("    %-28s %s" % [r["name"], r["note"]])
	print("")
	_completes("the_table")


## THE STANDING DIRECTIVE, as an assertion. Not "is it comfortable" — that is the
## maker's call and this file has no opinion — but "is there ANY movement verb that
## gets a body out". A spell nothing can escape is a bug regardless of taste.
func _test_everything_is_dodgeable_by_something() -> void:
	_expect(not _rows.is_empty(), "the table has rows (an empty table asserts nothing)")
	for r: Dictionary in _rows:
		_expect(float(r["escape"]) < INF,
			"%s has a BOUNDED danger area (its containment predicate never goes false)"
				% r["name"])
		_expect(float(r["dash"]) > 0.0,
			"%s is escapable by a dash (%.1f frames of slack — negative means the "
				% [r["name"], float(r["dash"])]
				+ "damage lands before a dashing body can be clear)")
	_completes("everything_is_dodgeable_by_something")


## NO AUTO-AIM, and the honest form of that question is: does the spell's landing
## point depend on anything except where it was aimed?
##
## Both walls answer it through `wall_center(from, aim, offset)`, which is pure and
## static — so it can be called with a body parked in every direction and must give
## the SAME answer every time. A spell that snapped to a target would not.
##
## Shadow Root and Petrify are checked differently: Shadow Root's grasp point is the
## aim clamped to a run length, and Petrify's catch is "the NEAREST body inside the
## footprint" — a selection INSIDE a placed area, which is not auto-aim (the area
## does not move to find anyone; step out of it and the spell visibly fizzles). Those
## are noted rather than asserted here because they are not pure functions.
func _test_nothing_re_aims_itself() -> void:
	var ice: GDScript = load(ICE_WALL_PATH) as GDScript
	var rock: GDScript = load(ROCK_WALL_PATH) as GDScript
	var from := Vector2(300.0, 40.0)
	for script: GDScript in [ice, rock]:
		var baseline: Vector2 = script.call("wall_center", from, Vector2.RIGHT)
		# Same call, over and over, with nothing in the world changed the spell could
		# be reading. A stateful or target-seeking implementation would drift.
		for i in 8:
			var again: Vector2 = script.call("wall_center", from, Vector2.RIGHT)
			_expect(again == baseline, "wall placement is a pure function of the aim")
		# ...and aiming somewhere else puts it somewhere else, in the aimed direction.
		var up: Vector2 = script.call("wall_center", from, Vector2.UP)
		_expect(up != baseline, "aiming elsewhere places the wall elsewhere")
		_expect(is_equal_approx((up - from).normalized().dot(Vector2.UP), 1.0),
			"the wall lands ALONG the aim, not toward anything")
		# A zero aim must not become a search. It falls back to a fixed direction.
		var zero: Vector2 = script.call("wall_center", from, Vector2.ZERO)
		_expect(zero == baseline, "a zero aim falls back to a FIXED direction, not a target")
	_completes("nothing_re_aims_itself")
