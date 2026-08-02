# Run: godot --headless --path godot-project --script tools/slice7_test_clipframing.gd
# THE ONE CAMERA RULE THE MAKER ASKED FOR, asserted instead of eyeballed.
#
#   "the camera needs to follow it cinematically please so the audience can see it
#    all all the time"
#
# So the failure mode to pin is LOSING A FIGHTER OFF-FRAME, and it had a specific
# cause: the old `ClipDirector._frame` solved a zoom that fit the pair around their
# MIDPOINT and then multiplied it by `1 + HEAT_PUNCH * heat`. Two independent bugs in
# one line — the shot is centred on a LEANED, CLAMPED eye rather than the midpoint it
# was solved for, and the punch pushes past containment exactly when the fight is
# most worth watching. Both are asserted against here.
#
# What is NOT asserted, because it is not true: that both fighters are always in
# frame. `ZOOM_MIN` is a real floor and two bots 1900 px apart on a 2000 px stage
# genuinely cannot both fit. The honest rule is the one below — contained whenever it
# is geometrically possible, and pulled ALL THE WAY BACK when it is not, never
# punched in.
#
# ⚠ THE HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the
# enclosing function and hands back the type's zero, which that idiom reads as "no
# failures". Failures accumulate on the MEMBER `_fails`; every test records a
# COMPLETION SENTINEL as its last line, so an aborted test fails BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"a_separated_pair_stays_in_frame",
	"a_hot_exchange_stays_in_frame",
	"a_launched_fighter_stays_in_frame",
	"heat_tightens_but_never_loses_anybody",
	"an_impossible_spread_pulls_all_the_way_back",
]

const STAGE: Rect2 = Rect2(Vector2.ZERO, Vector2(2000.0, 1000.0))
const GROUND: float = 780.0
## Enough steps for both the position and the (slower) zoom lerp to settle.
const SETTLE_STEPS: int = 60
const STEP: float = 0.05

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_separated_pair()
	_test_hot_exchange()
	_test_launched_fighter()
	_test_heat_tightens()
	_test_impossible_spread()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("ClipFraming tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("ClipFraming tests: all PASS")
		quit(0)
	return true


# ==========================================================================

## A pair well apart on the floor, nothing happening. The everyday shot.
func _test_separated_pair() -> void:
	var rig: Dictionary = _settle([Vector2(560.0, GROUND), Vector2(1220.0, GROUND)], false)
	_expect_contains(rig, "a separated pair")
	_teardown(rig)
	_completes("a_separated_pair_stays_in_frame")


## ...and the same pair mid-exchange, WIDE APART, with only ONE of them taking the
## damage. That combination is the exact shape of the bug: the victim lean pulls the
## eye a long way off the midpoint the old code solved its zoom around, and then the
## heat punch tightens on top of that, so the fighter doing the hitting leaves the
## frame at the most watchable moment of the fight. Both fighters, still in shot.
func _test_hot_exchange() -> void:
	var rig: Dictionary = _settle([Vector2(400.0, GROUND), Vector2(1300.0, GROUND)],
		true, 1)
	var d: ClipDirector = rig["director"]
	_expect(d.heat() > ClipDirector.HOT_THRESHOLD,
		"the exchange is actually hot (heat %.2f) — otherwise this asserts nothing"
		% d.heat())
	_expect_contains(rig, "a hot exchange")
	_teardown(rig)
	_completes("a_hot_exchange_stays_in_frame")


## Vertical containment. A knockback that launches a fighter must widen the shot, not
## leave them above the top edge — the eye is clamped into a band above the floor, so
## the ONLY thing that can keep them in is the zoom.
func _test_launched_fighter() -> void:
	var rig: Dictionary = _settle([Vector2(760.0, GROUND), Vector2(940.0, GROUND - 300.0)], true)
	_expect_contains(rig, "a launched fighter")
	_teardown(rig)
	_completes("a_launched_fighter_stays_in_frame")


## Heat is allowed to tighten the shot. It is NOT allowed to buy that tightness by
## throwing a fighter out of it. Both halves are asserted, because dropping the first
## would let a camera that never moves pass.
func _test_heat_tightens() -> void:
	var pair: Array[Vector2] = [Vector2(600.0, GROUND), Vector2(1000.0, GROUND)]
	var cold: Dictionary = _settle(pair, false)
	var cold_zoom: float = (cold["camera"] as Camera2D).zoom.x
	_teardown(cold)
	var hot: Dictionary = _settle(pair, true)
	var hot_zoom: float = (hot["camera"] as Camera2D).zoom.x
	_expect(hot_zoom > cold_zoom,
		"a hot moment is a TIGHTER shot (%.3f cold -> %.3f hot)" % [cold_zoom, hot_zoom])
	_expect_contains(hot, "the tightened hot shot")
	_teardown(hot)
	_completes("heat_tightens_but_never_loses_anybody")


## The honest edge. Two fighters further apart than ZOOM_MIN can ever cover: the
## shot must be at the floor — pulled ALL THE WAY BACK — and not punched in by heat.
func _test_impossible_spread() -> void:
	var rig: Dictionary = _settle([Vector2(60.0, GROUND), Vector2(1940.0, GROUND)], true)
	var z: float = (rig["camera"] as Camera2D).zoom.x
	_expect(is_equal_approx(z, ClipDirector.ZOOM_MIN) or z < ClipDirector.ZOOM_MIN + 0.01,
		"an uncoverable spread sits at the zoom floor (got %.3f, floor %.3f)"
		% [z, ClipDirector.ZOOM_MIN])
	_teardown(rig)
	_completes("an_impossible_spread_pulls_all_the_way_back")


# ==========================================================================

## Stand up a director + camera + fighters, optionally keep an exchange running so
## heat stays up, and step until the camera has settled.
## `victim` is which fighter takes the damage: -1 for both (a trade), or an index for
## a one-sided beating, which is what pulls the framing lean off the midpoint.
func _settle(at: Array[Vector2], hot: bool, victim: int = -1) -> Dictionary:
	var d := ClipDirector.new()
	root.add_child(d)
	d.set_process(false)   # `advance` drives the clock; `_process` would double it
	var cam := Camera2D.new()
	root.add_child(cam)
	d.bind(cam, STAGE, GROUND)
	var fighters: Array[Node2D] = []
	for p: Vector2 in at:
		fighters.append(_fighter(p))
	# Seed the camera somewhere plausible so the lerp is settling, not travelling
	# from the world origin.
	cam.global_position = Vector2(1000.0, GROUND - 50.0)
	var hp: int = 400
	for i: int in SETTLE_STEPS:
		if hot and i % 3 == 0:
			# Refreshed every few steps so the damage window never empties and heat
			# stays up for the whole settle.
			hp -= 6
			if victim < 0:
				fighters[0].set("hp", hp)
				fighters[1].set("hp", hp)
			else:
				fighters[victim].set("hp", hp)
		d.advance(STEP)
		# Positions are FIXED across the settle: this suite is about the camera, and
		# a moving target would make "did it converge" unanswerable.
		for k: int in fighters.size():
			fighters[k].global_position = at[k]
	return {"director": d, "camera": cam, "fighters": fighters, "at": at}


## Every fighter inside the camera's visible world rect, computed the same way the
## renderer does: the eye, plus half the viewport divided by the zoom.
func _expect_contains(rig: Dictionary, what: String) -> void:
	var cam: Camera2D = rig["camera"]
	var view: Vector2 = Vector2(root.get_visible_rect().size)
	var half: Vector2 = (view * 0.5) / maxf(cam.zoom.x, 0.001)
	var shot := Rect2(cam.global_position - half, half * 2.0)
	for p: Vector2 in (rig["at"] as Array[Vector2]):
		_expect(shot.has_point(p),
			"%s: fighter at %s is inside the shot %s (zoom %.3f)"
			% [what, p, shot, cam.zoom.x])


func _fighter(at: Vector2) -> Node2D:
	var n := Node2D.new()
	# ⚠ THE SCRIPT IS REQUIRED. `Object.set` on a property the object does not declare
	# is silently dropped, so a bare `Node2D` would read `hp` back as null and every
	# assertion here would pass or fail for the wrong reason.
	n.set_script(_STUB)
	n.global_position = at
	n.add_to_group(&"hero")
	n.set("hp", 400)
	n.set("max_hp", 400)
	n.set("damage_pct", 0.0)
	root.add_child(n)
	return n


const _STUB_SRC: String = """
extends Node2D
var hp: int = 400
var max_hp: int = 400
var damage_pct: float = 0.0
"""
static var _STUB: GDScript = _make_stub()


static func _make_stub() -> GDScript:
	var s := GDScript.new()
	s.source_code = _STUB_SRC
	s.reload()
	return s


func _teardown(rig: Dictionary) -> void:
	for n: Node in get_nodes_in_group(&"hero"):
		n.free()
	(rig["camera"] as Camera2D).free()
	(rig["director"] as ClipDirector).free()


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true
