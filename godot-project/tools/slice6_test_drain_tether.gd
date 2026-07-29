# DrainTether — the rework that made the whip DODGEABLE. Everything asserted here
# is a pure static over plain values (the catch sweep, the escape strain, the
# dodge budget), so the counterplay rules are provable without a scene, the same
# way ChainBolt.build_chain is.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_drain_tether.gd
#
# ⚠ WHY THE SCRIPT IS load()ED AND NEVER NAMED `DrainTether`. A `--script` tool
# is COMPILED BEFORE THE AUTOLOADS EXIST. Naming the class here makes the parser
# compile it at that moment, it calls `Sfx`, and the suite dies with "Identifier
# not found: Sfx" — while STILL PRINTING "all PASS", because every failed static
# call returns null and the assertions never run. That false pass is the trap
# this comment exists to stop the next person walking into; `_guard` below turns
# it into a loud failure if the statics ever go missing again.
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
	"catch_matches_the_drawn_silhouette",
	"the_whip_catches_the_head_not_the_origin",
	"no_autoaim",
	"sweep_does_not_tunnel",
	"first_caught_picks_the_nearest",
	"escape_is_readable",
	"dodge_budget",
	"nothing_happens_during_the_windup",
	"a_whiff_cleans_itself_up",
]

var _fails: int = 0
var _completed: Dictionary = {}

const TETHER_PATH: String = "res://scripts/combat/DrainTether.gd"

var _ran: bool = false
var _dt: GDScript = null
var _k: Dictionary = {}   # the spell's constant map, so numbers stay in sync


## A victim that records what the whip did to it and when. Two-argument
## take_damage, matching Enemy (heroes take one) — see DrainTether._hurt.
class Dummy extends Node2D:
	var hits: int = 0
	var total: int = 0

	func take_damage(amount: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		hits += 1
		total += amount


## A body with a DRAWN SILHOUETTE above its origin, stubbing the duck-typed
## contract `Enemy` implements (body_distance / hit_margin / head_point). The
## head sits further above the origin than the hook is wide, which is the whole
## point — see `_test_the_whip_catches_the_head_not_the_origin`.
class Tall extends Node2D:
	const HEAD_UP: float = 34.0   # head centre above the node origin
	const HEAD_R: float = 9.0

	func head_point() -> Vector2:
		return global_position + Vector2(0.0, -HEAD_UP)

	## Zero, so these assertions stay exact. A real Enemy returns a forgiveness
	## ring; inflating it here would hide a boundary regression.
	func hit_margin() -> float:
		return 0.0

	## Spine segment (origin up to the head) plus the head circle on top —
	## the same shape SpikeFigure.body_distance describes.
	func body_distance(p: Vector2) -> float:
		var neck: Vector2 = global_position + Vector2(0.0, -HEAD_UP + HEAD_R)
		var spine: float = SpellGeometry.point_segment_distance(p, global_position, neck)
		return minf(spine, p.distance_to(head_point()) - HEAD_R)


## A body the whip can catch. Plain Node2D — the selectors only ever read
## global_position, which is the point of keeping them pure.
func _body(at: Vector2) -> Node2D:
	var n := Node2D.new()
	root.add_child(n)
	n.global_position = at
	return n


## Kicked off from `_process` rather than run inside it, because the lifecycle
## test has to `await process_frame` — the whole regression being guarded against
## is about WHEN the spell does things, which cannot be observed in one frame.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	_dt = load(TETHER_PATH) as GDScript
	_k = _dt.get_script_constant_map() if _dt != null else {}
	# The surface check runs FIRST: if the statics moved, every assertion below
	# would trivially pass against nulls, so the tests are skipped and their
	# missing sentinels fail the suite alongside the named guard failures.
	_guard()
	if _fails == 0:
		_test_catch_matches_the_drawn_silhouette()
		_test_the_whip_catches_the_head_not_the_origin()
		_test_no_autoaim()
		_test_sweep_does_not_tunnel()
		_test_first_caught_picks_the_nearest()
		_test_escape_is_readable()
		_test_dodge_budget()
		await _test_nothing_happens_during_the_windup()
		await _test_a_whiff_cleans_itself_up()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Drain tether tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Drain tether tests: all PASS")
		quit(0)


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


## Everything below calls into the loaded script dynamically, so a renamed or
## deleted static would silently return null and every assertion would trivially
## pass. Prove the surface exists FIRST, and bail loudly if it does not.
func _guard() -> void:
	_expect(_dt != null, "the DrainTether script loads at runtime")
	if _dt == null:
		return
	for fn: String in ["caught_by", "first_caught", "break_strain", "dodge_window"]:
		_expect(_dt.has_method(fn), "the pure selector `%s` still exists" % fn)
	for c: String in ["CATCH_R", "BREAK_PULL", "WINDUP", "LASH_SPEED", "RANGE",
			"DRAIN_TIME", "REEL_SPEED"]:
		_expect(_k.has(c), "the tuning constant `%s` still exists" % c)


## The maker's rule: "the spells shouldn't be able to get out the radius". The
## catch radius IS the radius the hook disc is drawn at, so this pins both the
## positive and — the one that matters — the NEGATIVE case just outside it.
##
## The stubs are plain Node2D with no silhouette methods, which is deliberate:
## that is the zero-margin fallback path, so these boundaries are exact and a
## future change that quietly inflated the hitbox would show up here.
func _test_catch_matches_the_drawn_silhouette() -> void:
	var r: float = float(_k["CATCH_R"])
	var from := Vector2(0.0, 0.0)
	var to := Vector2(200.0, 0.0)
	var on_line: Node2D = _body(Vector2(100.0, 0.0))
	var inside: Node2D = _body(Vector2(100.0, r - 1.0))
	var outside: Node2D = _body(Vector2(100.0, r + 1.0))
	var miles: Node2D = _body(Vector2(100.0, r * 3.0))
	var behind: Node2D = _body(Vector2(-r - 1.0, 0.0))
	var beyond: Node2D = _body(Vector2(200.0 + r + 1.0, 0.0))
	_expect(_dt.caught_by(from, to, r, on_line), "a body on the whip's line is caught")
	_expect(_dt.caught_by(from, to, r, inside),
		"a body just inside the hook radius is caught")
	_expect(not _dt.caught_by(from, to, r, outside),
		"a body just OUTSIDE the hook radius takes nothing")
	_expect(not _dt.caught_by(from, to, r, miles),
		"...and one well outside it certainly takes nothing")
	# The endpoints are capsule caps, not an infinite ray: nothing behind the
	# caster and nothing past the head.
	_expect(not _dt.caught_by(from, to, r, behind),
		"a body behind the caster is never caught")
	_expect(not _dt.caught_by(from, to, r, beyond),
		"a body past the hook head is not caught until the hook gets there")
	# A freed or null target must never crash a per-frame flight loop.
	_expect(not _dt.caught_by(from, to, r, null),
		"a null target is simply not caught, rather than an error")
	for n: Node2D in [on_line, inside, outside, miles, behind, beyond]:
		n.free()
	_completes("catch_matches_the_drawn_silhouette")


## Bug 1 from SpellTargets' header, applied to this spell: `Enemy` draws its head
## ABOVE its node origin, so a whip aimed at somebody's head against an
## origin-only test passes straight through it. The whip must test the drawn
## silhouette. Stubbed with the same duck-typed contract Enemy implements.
func _test_the_whip_catches_the_head_not_the_origin() -> void:
	var r: float = float(_k["CATCH_R"])
	var tall := Tall.new()
	root.add_child(tall)
	tall.global_position = Vector2(100.0, 0.0)
	# A lash at HEAD height: far above the origin, but right through the skull.
	var from := Vector2(0.0, -Tall.HEAD_UP)
	var to := Vector2(200.0, -Tall.HEAD_UP)
	_expect(tall.global_position.distance_to(from.lerp(to, 0.5)) > r,
		"the premise holds: an origin-only test would MISS this lash")
	_expect(_dt.caught_by(from, to, r, tall),
		"a whip through the drawn head connects")
	# ...and the silhouette is not a licence to hit from anywhere.
	var high := Vector2(0.0, -Tall.HEAD_UP - Tall.HEAD_R - r - 8.0)
	_expect(not _dt.caught_by(high, high + Vector2(200.0, 0.0), r, tall),
		"a whip clean over the head still misses")
	tall.free()
	_completes("the_whip_catches_the_head_not_the_origin")


## Locked rule 1: no auto-aim, no homing. A body a hair outside the swept capsule
## must be missed no matter how obviously it was "the target".
func _test_no_autoaim() -> void:
	var r: float = float(_k["CATCH_R"])
	var from := Vector2.ZERO
	var to := Vector2(400.0, 0.0)
	var off: Node2D = _body(Vector2(200.0, r + 2.0))
	_expect(_dt.first_caught(from, to, r, [off]) == null,
		"the hook does not bend to find a target just off the line")
	# ...and it is genuinely just off, not off by miles — this is a near-miss.
	_expect(_dt.caught_by(from, to, r + 4.0, off),
		"the near-miss is a NEAR miss (it lands with a slightly fatter hook)")
	off.free()
	_completes("no_autoaim")


## Anti-tunnelling: the catch is a swept capsule over the segment the head
## travelled this frame, not a point test at the head. A point test only needs
## ONE long frame to fail — a step wider than 2 x CATCH_R drops any body sitting
## in the middle of it, and the whip visibly passes straight through someone.
## This is not hypothetical on a mobile-first game: at LASH_SPEED the step below
## is a ~73 ms frame, which is one GC hitch or a cheap device.
func _test_sweep_does_not_tunnel() -> void:
	var r: float = float(_k["CATCH_R"])
	var step: float = r * 3.0
	_expect(step / float(_k["LASH_SPEED"]) < 0.12,
		"the premise is a plausible hitch, not an absurd one (%.0f ms frame)"
			% [step / float(_k["LASH_SPEED"]) * 1000.0])
	var prev := Vector2(0.0, 0.0)
	var head := Vector2(step, 0.0)
	var skipped: Node2D = _body(Vector2(step * 0.5, 0.0))  # dead centre of the step
	_expect(_dt.first_caught(prev, head, r, [skipped]) == skipped,
		"a body the frame stepped OVER is still caught by the sweep")
	_expect(head.distance_to(skipped.global_position) > r,
		"...and a head-only point test would indeed have missed it")
	skipped.free()
	_completes("sweep_does_not_tunnel")


## Two bodies on the line: the whip bites the near one. A whip that reached past
## the first thing it crossed would be a beam with extra steps.
func _test_first_caught_picks_the_nearest() -> void:
	var r: float = float(_k["CATCH_R"])
	var from := Vector2.ZERO
	var to := Vector2(400.0, 0.0)
	var near: Node2D = _body(Vector2(120.0, 4.0))
	var far: Node2D = _body(Vector2(300.0, -6.0))
	_expect(_dt.first_caught(from, to, r, [far, near]) == near,
		"the nearest body along the sweep is bitten, whatever order it was listed in")
	_expect(_dt.first_caught(from, to, r, []) == null,
		"an empty arena catches nobody")
	near.free()
	far.free()
	_completes("first_caught_picks_the_nearest")


## Counterplay 3: once bitten you can tear free, and the demand is the SAME
## wherever you were caught (measured from the bite point, not from the caster).
## `break_strain` also drives the drawn break ring, so what strains is what frees.
func _test_escape_is_readable() -> void:
	var pull: float = float(_k["BREAK_PULL"])
	var bite := Vector2(300.0, 100.0)
	_expect(is_equal_approx(float(_dt.break_strain(bite, bite, pull)), 0.0),
		"standing still is zero strain")
	var half: float = float(_dt.break_strain(bite, bite + Vector2(pull * 0.5, 0.0), pull))
	_expect(absf(half - 0.5) < 0.001, "halfway out is half strained (got %.3f)" % half)
	_expect(float(_dt.break_strain(bite, bite + Vector2(pull, 0.0), pull)) >= 1.0,
		"reaching the break distance frees you")
	_expect(float(_dt.break_strain(bite, bite + Vector2(0.0, -pull - 50.0), pull)) >= 1.0,
		"...in ANY direction, including straight up (a jump is an escape)")
	_expect(float(_dt.break_strain(bite, bite + Vector2(pull - 1.0, 0.0), pull)) < 1.0,
		"one pixel short is still caught — the boundary is where the constant says")
	# The escape must be beatable inside the channel by an ordinary body. The
	# cable reels at REEL_SPEED, so the NET budget is what actually matters.
	var hero_speed: float = 210.0        # Hero.SPEED
	var net: float = (hero_speed - float(_k["REEL_SPEED"])) * float(_k["DRAIN_TIME"])
	_expect(net > pull,
		"a running hero clears the break (%.0f px available vs %.0f needed)" % [net, pull])
	_expect(float(_k["REEL_SPEED"]) < 55.0,
		"the reel stays under the slowest enemy walk (55 px/s) — weight, not a lock")
	_completes("escape_is_readable")


## Counterplay 1+2, as numbers. The whole reason this file exists: the old spell
## bit on the frame it was cast, so the dodge budget was ZERO at every range.
func _test_dodge_budget() -> void:
	var windup: float = float(_k["WINDUP"])
	var reach: float = float(_k["RANGE"])
	_expect(windup > 0.0, "there is a windup at all (the old version had none)")
	var point_blank: float = float(_dt.dodge_window(0.0))
	_expect(absf(point_blank - windup) < 0.001,
		"point-blank still pays the full windup — the guaranteed floor")
	_expect(point_blank >= 0.2,
		"...and that floor is long enough to react to (%.2f s)" % point_blank)
	var far: float = float(_dt.dodge_window(reach))
	_expect(far > point_blank,
		"distance BUYS time — the hook travels, it does not teleport")
	_expect(far >= 0.5,
		"a max-range cast gives at least half a second (%.2f s)" % far)
	# 22 px of catch radius against 210 px/s of hero: the floor alone is more than
	# enough room to simply walk out of the line.
	var walk: float = 210.0 * windup
	_expect(walk > float(_k["CATCH_R"]) * 2.0,
		"the windup alone moves a hero clear of the hook (%.0f px vs %.0f px wide)"
			% [walk, float(_k["CATCH_R"]) * 2.0])
	_expect(float(_dt.dodge_window(reach * 2.0)) <= far + 0.001,
		"the budget is clamped at the whip's reach — nothing past RANGE is ever hit")
	_completes("dodge_budget")


## THE REGRESSION THAT STARTED ALL THIS. The old spell resolved its target query
## and applied its first drain tick inside the same `tether()` call it was cast
## from, so a victim standing on the aim line had already been hit before the
## first frame drew. Assert the opposite directly: while the whip is still
## coiling, the body on the line takes NOTHING, and it is not yet parryable
## either (there is no whip in the air to catch).
func _test_nothing_happens_during_the_windup() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var victim := Dummy.new()
	victim.add_to_group("enemy")
	arena.add_child(victim)
	victim.global_position = Vector2(300.0, 0.0)
	var whip: Node2D = _dt.new()
	arena.add_child(whip)
	whip.call("tether", Vector2.ZERO, Vector2.RIGHT, Color(0.6, 0.3, 0.9), 11, "shadow")
	_expect(int(whip.get("_state")) == 0, "the whip starts in COIL, not in contact")
	_expect(victim.hits == 0, "the cast frame itself deals NO damage")
	var frames: int = 0
	var coil_frames: int = 0
	# Watch every frame of the coil: nothing may land, and nothing may be parryable.
	while frames < 600 and is_instance_valid(whip) and int(whip.get("_state")) == 0:
		_expect(victim.hits == 0, "no damage lands during the windup")
		_expect(not whip.is_in_group("deflectable_spell"),
			"a coiling whip is not yet in the air to be parried")
		coil_frames += 1
		frames += 1
		await process_frame
	_expect(coil_frames > 0, "the windup actually lasted at least one frame")
	# ...and once launched it must be catchable, because a travelling spell owes
	# the defender the reflect() verb (see SpellDeflect's class docs).
	if is_instance_valid(whip):
		_expect(whip.is_in_group("deflectable_spell"),
			"a lashing whip IS deflectable")
	# Let it fly the rest of the way and confirm it does eventually connect —
	# "dodgeable" must not have quietly become "harmless".
	while frames < 600 and is_instance_valid(whip) and int(whip.get("_state")) < 2:
		frames += 1
		await process_frame
	_expect(victim.hits >= 1, "the whip still bites what it actually reaches")
	if is_instance_valid(whip):
		whip.queue_free()
	victim.queue_free()
	arena.queue_free()
	await process_frame
	_completes("nothing_happens_during_the_windup")


## A whip thrown at empty air must crack, recoil and retire itself. A spectacle
## that leaks a node every time you miss is a frame-rate bug waiting for a
## playtest where somebody misses a lot.
func _test_a_whiff_cleans_itself_up() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var whip: Node2D = _dt.new()
	arena.add_child(whip)
	whip.call("tether", Vector2.ZERO, Vector2.RIGHT, Color(0.6, 0.3, 0.9), 11, "shadow")
	# Generous budget: windup + full travel + recoil, plus slack for frame jitter.
	var budget: int = 600
	var frames: int = 0
	while frames < budget and is_instance_valid(whip):
		frames += 1
		await process_frame
	_expect(not is_instance_valid(whip),
		"a whiffed whip frees itself instead of lingering forever")
	arena.queue_free()
	await process_frame
	_completes("a_whiff_cleans_itself_up")
