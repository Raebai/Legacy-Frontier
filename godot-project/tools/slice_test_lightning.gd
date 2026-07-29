# Run: godot --headless --path godot-project --script tools/slice_test_lightning.gd
# The two LIGHTNING spectacles after the "that single line of lighting is corny"
# rework: LightningRush (Chidori, RUSH) and ChainBolt (Chain Lightning, CHAIN).
#
# The visual rework itself can only be judged by looking at a rendered PNG — what
# IS testable, and what this suite pins down, is the pair of contracts the rework
# had to not break:
#   1. THE PICTURE NEVER PROMISES REACH THE HITBOX DOES NOT HAVE. Every drawn
#      point of the lance now derives from the same half-corridor the damage test
#      uses (maker: "the spells shouldn't be able to get out the radius"). Before
#      the rework damage stopped at 23 px off-axis while the bolt swung out past
#      40 and its glow past 60.
#   2. NO AUTO-AIM. ChainBolt's opening strike must still miss when you aim wide;
#      only the arcs AFTER a landed hit are automatic.
# Plus the mechanical properties the "corny" fix depends on: the shape actually
# re-randomises over time, the braided strands are actually different from each
# other, and the filaments stay pinned to the points they claim to connect.
#
# Both scripts touch autoloads (Sfx / Juice / PostProcess / CombatVfx) at RUNTIME,
# so they are load()ed by path rather than preloaded — the repo's headless trap.
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
	"bolt_stays_inside_damage_corridor",
	"bolt_endpoints_are_pinned",
	"bolt_rejitters_over_time",
	"strands_are_actually_braided",
	"corridor_clamp",
	"rush_damage_respects_the_corridor",
	"chain_link_stays_between_strike_points",
	"chain_opening_strike_has_no_seek",
	"chain_arcs_after_a_hit_are_automatic",
]

var _fails: int = 0
var _completed: Dictionary = {}

const RUSH_PATH: String = "res://scripts/combat/LightningRush.gd"
const CHAIN_PATH: String = "res://scripts/combat/ChainBolt.gd"

var _ran: bool = false


class Dummy:
	extends Node2D
	var dmg: Array[int] = []
	func take_damage(a: int, _tint: Variant = null) -> void:
		dmg.append(a)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_bolt_stays_inside_damage_corridor()
	_test_bolt_endpoints_are_pinned()
	_test_bolt_rejitters_over_time()
	_test_strands_are_actually_braided()
	_test_corridor_clamp()
	_test_rush_damage_respects_the_corridor()
	_test_chain_link_stays_between_strike_points()
	_test_chain_opening_strike_has_no_seek()
	_test_chain_arcs_after_a_hit_are_automatic()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Lightning tests: %d FAILED" % _fails)
	else:
		print("Lightning tests: all PASS")
	quit(1 if _fails > 0 else 0)
	return false


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, what: String) -> void:
	if not cond:
		printerr("  FAIL: ", what)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## THE contract of the rework. Whatever shape the bolt takes on any tick, for any
## strand, every vertex must lie inside the same corridor `targets_on_line` uses —
## the lance must never be drawn sweeping through an enemy that takes nothing.
func _test_bolt_stays_inside_damage_corridor() -> void:
	var rush: GDScript = load(RUSH_PATH)
	var origin := Vector2(120.0, -40.0)
	var length: float = 620.0
	var half: float = 26.0 * 0.5 + 10.0  # _damage_half() for the authored width
	var worst: float = 0.0
	var escaped_sideways: int = 0
	var overshot_the_ends: int = 0
	# Sweep angles, strands and ticks: the shape is time- and salt-dependent, so a
	# single sample would prove nothing.
	for a: int in 8:
		var d := Vector2.from_angle(TAU * float(a) / 8.0)
		var perp: Vector2 = d.orthogonal()
		for salt: int in 4:
			for tq: int in 24:
				var pts: PackedVector2Array = rush.strand_points(
					origin, d, length, half, 26, salt, tq)
				for p: Vector2 in pts:
					var rel: Vector2 = p - origin
					worst = maxf(worst, absf(rel.dot(perp)))
					if absf(rel.dot(perp)) > half + 0.001:
						escaped_sideways += 1
					if rel.dot(d) < -0.001 or rel.dot(d) > length + 0.001:
						overshot_the_ends += 1
	# Tallied over the whole sweep, then asserted ONCE each: this loop visits
	# ~20k points, and one break reported per point buries the rest of the suite.
	# (The longitudinal check used to be a bare `failed += 1` with no message at
	# all, so a bolt overshooting its own length failed silently-looking.)
	_expect(escaped_sideways == 0,
		"no drawn point escapes the corridor sideways (%d points did)" % escaped_sideways)
	_expect(overshot_the_ends == 0,
		"no drawn point runs past either end of the bolt (%d did)" % overshot_the_ends)
	_expect(worst <= half + 0.001,
		"no drawn point escapes the damage corridor (worst %.2f of %.2f)" % [worst, half])
	# ...and it should actually USE the corridor — a bolt clamped so hard it draws
	# a straight line would pass the test above while being exactly the bug.
	_expect(worst > half * 0.3,
		"the bolt still wanders (uses %.0f%% of the corridor)" % [worst / half * 100.0])
	_completes("bolt_stays_inside_damage_corridor")


## The lance must CONNECT: it starts at the fist and ends at the impact point.
## A bolt whose ends float free reads as a decal lying on top of the scene.
func _test_bolt_endpoints_are_pinned() -> void:
	var rush: GDScript = load(RUSH_PATH)
	var origin := Vector2(-300.0, 88.0)
	var d := Vector2.RIGHT
	# Tallied over the whole sweep, then asserted ONCE per endpoint: 12 quadrants
	# reporting the same break 12 times buries every other failure in the suite.
	var loose_start: int = 0
	var loose_end: int = 0
	for tq: int in 12:
		var pts: PackedVector2Array = rush.strand_points(origin, d, 500.0, 23.0, 26, 0, tq)
		if not pts[0].is_equal_approx(origin):
			loose_start += 1
		if not pts[pts.size() - 1].is_equal_approx(origin + d * 500.0):
			loose_end += 1
	_expect(loose_start == 0, "bolt starts at the fist (%d/12 quadrants float free)" % loose_start)
	_expect(loose_end == 0, "bolt ends at the impact point (%d/12 quadrants float free)" % loose_end)
	_completes("bolt_endpoints_are_pinned")


## A bolt drawn once and faded is a DECAL — the corniest lightning there is. The
## shape has to genuinely re-randomise between quantized ticks.
func _test_bolt_rejitters_over_time() -> void:
	var rush: GDScript = load(RUSH_PATH)
	var origin := Vector2.ZERO
	var a: PackedVector2Array = rush.strand_points(origin, Vector2.RIGHT, 600.0, 23.0, 26, 0, 3)
	var b: PackedVector2Array = rush.strand_points(origin, Vector2.RIGHT, 600.0, 23.0, 26, 0, 4)
	var moved: float = 0.0
	for i: int in a.size():
		moved = maxf(moved, a[i].distance_to(b[i]))
	_expect(moved > 4.0, "the bolt re-jitters between ticks (moved %.1f px)" % moved)
	# ...and deterministically: the SAME tick must redraw identically, or the bolt
	# would strobe every frame instead of snapping at JITTER_HZ.
	var again: PackedVector2Array = rush.strand_points(origin, Vector2.RIGHT, 600.0, 23.0, 26, 0, 3)
	var same: bool = true
	for i: int in a.size():
		if not a[i].is_equal_approx(again[i]):
			same = false
	_expect(same, "the same tick redraws identically (no per-frame strobe)")
	_completes("bolt_rejitters_over_time")


## The braid is only a braid if the strands differ. Three identical filaments
## stacked on each other are still one line.
func _test_strands_are_actually_braided() -> void:
	var rush: GDScript = load(RUSH_PATH)
	var main: PackedVector2Array = rush.strand_points(Vector2.ZERO, Vector2.RIGHT, 600.0, 23.0, 26, 0, 9)
	var ghost: PackedVector2Array = rush.strand_points(Vector2.ZERO, Vector2.RIGHT, 600.0, 23.0, 26, 1, 9)
	var spread: float = 0.0
	for i: int in main.size():
		spread = maxf(spread, main[i].distance_to(ghost[i]))
	_expect(spread > 4.0, "ghost strands differ from the main arc (%.1f px apart)" % spread)
	_completes("strands_are_actually_braided")


## The single choke point every drawn point passes through. Tested directly so a
## future draw site that forgets to call it fails loudly somewhere.
func _test_corridor_clamp() -> void:
	var rush: GDScript = load(RUSH_PATH)
	var o := Vector2(50.0, 50.0)
	var inside: Vector2 = rush.clamp_in_corridor(Vector2(200.0, 60.0), o, Vector2.RIGHT, 400.0, 23.0)
	_expect(inside.is_equal_approx(Vector2(200.0, 60.0)), "a point already inside is untouched")
	var far: Vector2 = rush.clamp_in_corridor(Vector2(200.0, 300.0), o, Vector2.RIGHT, 400.0, 23.0)
	_expect(is_equal_approx(far.y, 73.0), "a point outside is pulled back to the corridor edge")
	var past: Vector2 = rush.clamp_in_corridor(Vector2(9999.0, 50.0), o, Vector2.RIGHT, 400.0, 23.0)
	_expect(is_equal_approx(past.x, 450.0), "a point past the tip is pulled back to the tip")
	_completes("corridor_clamp")


## The negative case the maker's rule is really about: something JUST outside the
## corridor takes zero. Paired with a just-inside case so a corridor that silently
## collapsed to nothing couldn't pass.
func _test_rush_damage_respects_the_corridor() -> void:
	var rush: GDScript = load(RUSH_PATH)
	var half: float = 26.0 * 0.5 + 10.0  # 23.0
	var origin := Vector2.ZERO
	var holder := Node2D.new()
	root.add_child(holder)

	var just_in := Dummy.new()
	just_in.position = Vector2(300.0, half - 1.0)
	var just_out := Dummy.new()
	just_out.position = Vector2(300.0, half + 1.0)
	var behind := Dummy.new()
	behind.position = Vector2(-40.0, 0.0)
	var past := Dummy.new()
	past.position = Vector2(700.0, 0.0)
	for n: Node in [just_in, just_out, behind, past]:
		holder.add_child(n)

	var hit: Array = rush.targets_on_line(origin, Vector2.RIGHT, 620.0, half,
		[just_in, just_out, behind, past])
	_expect(hit.has(just_in), "a target just INSIDE the corridor is struck")
	_expect(not hit.has(just_out), "a target just OUTSIDE the corridor takes ZERO")
	_expect(not hit.has(behind), "a target behind the fist takes zero")
	_expect(not hit.has(past), "a target past the lance tip takes zero")
	holder.queue_free()
	_completes("rush_damage_respects_the_corridor")


## Chain damage lands on BODIES, not along a path — so the drawn link's only job
## is to stay honest about which two bodies it connects.
func _test_chain_link_stays_between_strike_points() -> void:
	var chain: GDScript = load(CHAIN_PATH)
	var a := Vector2(-100.0, 20.0)
	var b := Vector2(180.0, -60.0)
	var span: Vector2 = b - a
	var dir: Vector2 = span.normalized()
	var perp: Vector2 = dir.orthogonal()
	var bad: int = 0
	for salt: int in 3:
		for tq: int in 20:
			var pts: PackedVector2Array = chain.link_points(a, b, salt, tq)
			if not pts[0].is_equal_approx(a) or not pts[pts.size() - 1].is_equal_approx(b):
				bad += 1
			for p: Vector2 in pts:
				var rel: Vector2 = p - a
				# JAG is the authored peak wander; allow it plus a hair of slack.
				if absf(rel.dot(perp)) > chain.JAG + 0.001:
					bad += 1
				if rel.dot(dir) < -0.001 or rel.dot(dir) > span.length() + 0.001:
					bad += 1
	_expect(bad == 0, "every link vertex stays pinned between the two struck bodies")
	_completes("chain_link_stays_between_strike_points")


## Overhaul rule 1, still locked after the visual rework: the OPENING strike does
## not seek. Target 1 must lie inside the aim corridor; aim wide and it fizzles.
func _test_chain_opening_strike_has_no_seek() -> void:
	var chain: GDScript = load(CHAIN_PATH)
	var holder := Node2D.new()
	root.add_child(holder)

	var on_aim := Dummy.new()
	on_aim.position = Vector2(300.0, chain.FIRST_CORRIDOR - 2.0)
	var off_aim := Dummy.new()
	off_aim.position = Vector2(300.0, chain.FIRST_CORRIDOR + 2.0)
	holder.add_child(on_aim)
	holder.add_child(off_aim)

	var hit: Array = chain.build_chain(Vector2.ZERO, Vector2.RIGHT,
		chain.FIRST_REACH, chain.HOP_RANGE, 5, [on_aim])
	_expect(hit.has(on_aim), "a target inside the aim corridor is struck")
	# off_aim ALONE — it must not be picked up as target 1. (Offering both at once
	# would prove nothing: off_aim sits 4 px from on_aim, so it would be legitimately
	# picked up by the first HOP, which is the automatic half of the design.)
	var missed: Array = chain.build_chain(Vector2.ZERO, Vector2.RIGHT,
		chain.FIRST_REACH, chain.HOP_RANGE, 5, [off_aim])
	_expect(missed.is_empty(), "a target just outside the corridor is NOT sought out")

	# Aim into empty air with a victim standing right there off-axis: the bolt
	# must fizzle rather than bend onto it.
	var whiff: Array = chain.build_chain(Vector2.ZERO, Vector2.UP,
		chain.FIRST_REACH, chain.HOP_RANGE, 5, [on_aim, off_aim])
	_expect(whiff.is_empty(), "aiming wide fizzles — no free retarget")
	holder.queue_free()
	_completes("chain_opening_strike_has_no_seek")


## The other half of the deliberate split: once the opening strike LANDS, the arcs
## after it are automatic, because that is what "chain" means. This is not aim
## assist — it is a consequence of connecting.
func _test_chain_arcs_after_a_hit_are_automatic() -> void:
	var chain: GDScript = load(CHAIN_PATH)
	var holder := Node2D.new()
	root.add_child(holder)

	var first := Dummy.new()
	first.position = Vector2(300.0, 0.0)
	# Well off the aim ray, but within one hop of the first victim — it must be
	# picked up even though the player never aimed anywhere near it.
	var hop := Dummy.new()
	hop.position = Vector2(340.0, 160.0)
	holder.add_child(first)
	holder.add_child(hop)

	var hit: Array = chain.build_chain(Vector2.ZERO, Vector2.RIGHT,
		chain.FIRST_REACH, chain.HOP_RANGE, 5, [first, hop])
	_expect(hit.size() == 2 and hit[0] == first and hit[1] == hop,
		"the arc after a landed hit leaps off-axis automatically")

	# ...but out of hop range it stops, rather than chaining across the arena.
	hop.position = Vector2(340.0, chain.HOP_RANGE + 120.0)
	var short_chain: Array = chain.build_chain(Vector2.ZERO, Vector2.RIGHT,
		chain.FIRST_REACH, chain.HOP_RANGE, 5, [first, hop])
	_expect(short_chain.size() == 1, "the chain stops when the next body is out of hop range")
	holder.queue_free()
	_completes("chain_arcs_after_a_hit_are_automatic")
