# Run: godot --headless --path godot-project --script tools/slice7_test_clipdirector.gd
# THE CONTENT ENGINE'S JUDGEMENT, asserted rather than eyeballed. `ClipDirector`
# decides when a bot fight is worth filming and where to point, and both of those
# are opinions a test can pin: an exchange must outscore an approach, a knockdown
# and a ring-out must both end the shot, and a tall spectacle must never be able to
# lift the camera off the stage.
#
# The last one is not hypothetical. The first directed capture came back as a frame
# of almost pure sky with the fighters' heads at the very bottom edge, because the
# framing leaned toward the centroid of the live spells and a Stormcaller's
# lightning column is a node hundreds of pixels above the floor. `_lean` is
# asymmetric now, and `vertical_lean_is_damped` is the assertion that keeps it so.
#
# ⚠ THE HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the
# enclosing function and returns the type's zero, which that idiom reads as "no
# failures". Failures accumulate on the MEMBER `_fails`; every test records a
# COMPLETION SENTINEL as its last line, so an aborted test fails BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"heat_is_zero_on_an_empty_board", "damage_makes_it_hot",
	"heat_decays", "knockdown_latches", "ringout_counts_as_decisive",
	"vertical_lean_is_damped", "camera_stays_over_the_stage",
]

## The fighter stand-in. A bare `Node2D` in group `hero` with the two members the
## director reads — deliberately NOT a real `Hero`, because this suite is about the
## DIRECTOR's judgement and a real hero would drag in the whole autoload chain.
##
## ⚠ A stub is only honest if it is not more generous than reality. Both members
## below exist on the shipped `Hero` (`hp` at Hero.gd, `damage_pct` for the ring-out
## model); `_test_against_a_real_hero` is deliberately NOT attempted here because
## `slice3_test_versus` already asserts the arena builds real ones.
const STAGE: Rect2 = Rect2(Vector2.ZERO, Vector2(2000.0, 1000.0))
const GROUND: float = 780.0

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_empty_board()
	_test_damage_makes_it_hot()
	_test_heat_decays()
	_test_knockdown_latches()
	_test_ringout_counts()
	_test_vertical_lean()
	_test_camera_stays_over_stage()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("ClipDirector tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("ClipDirector tests: all PASS")
		quit(0)
	return true


# ==========================================================================

## Two fighters standing still with nothing in flight is not worth filming.
func _test_empty_board() -> void:
	var d: ClipDirector = _director()
	_fighter(d, Vector2(400.0, GROUND), 100)
	_fighter(d, Vector2(1400.0, GROUND), 100)
	d.advance(0.1)
	_expect(d.heat() < ClipDirector.HOT_THRESHOLD,
		"an approach is not hot (heat %.2f)" % d.heat())
	_expect(not d.is_hot(), "...so the camera is not rolling")
	_teardown(d)
	_completes("heat_is_zero_on_an_empty_board")


## ...and an exchange is. The SHAPE of the judgement, not a magic number: the same
## board with damage on it must score strictly higher, and clear the threshold.
func _test_damage_makes_it_hot() -> void:
	var d: ClipDirector = _director()
	var a: Node2D = _fighter(d, Vector2(700.0, GROUND), 100)
	var b: Node2D = _fighter(d, Vector2(900.0, GROUND), 100)
	d.advance(0.1)
	var cold: float = d.heat()
	a.set("hp", 70)      # a real exchange, both ways
	b.set("hp", 65)
	d.advance(0.1)
	_expect(d.heat() > cold,
		"damage raises heat (%.2f -> %.2f)" % [cold, d.heat()])
	_expect(d.is_hot(), "an exchange clears the roll threshold (heat %.2f)" % d.heat())
	_teardown(d)
	_completes("damage_makes_it_hot")


## Heat is a window, not a latch: once the exchange is over it falls again, or every
## clip would run to its full frame budget after one hit.
func _test_heat_decays() -> void:
	var d: ClipDirector = _director()
	var a: Node2D = _fighter(d, Vector2(300.0, GROUND), 100)
	_fighter(d, Vector2(1500.0, GROUND), 100)
	d.advance(0.1)
	a.set("hp", 40)
	d.advance(0.1)
	var hot: float = d.heat()
	# Well past DAMAGE_MEMORY, in steps so the event queue is actually swept.
	for _i: int in 20:
		d.advance(0.1)
	_expect(d.heat() < hot, "heat falls once the exchange is over (%.2f -> %.2f)"
		% [hot, d.heat()])
	_teardown(d)
	_completes("heat_decays")


## A fighter at zero HP ends the shot, and the latch never clears — a tool reads it
## once per frame and must not miss the beat because the body was freed.
func _test_knockdown_latches() -> void:
	var d: ClipDirector = _director()
	var a: Node2D = _fighter(d, Vector2(700.0, GROUND), 100)
	_fighter(d, Vector2(900.0, GROUND), 100)
	d.advance(0.1)
	_expect(not d.saw_knockdown(), "no knockdown while both are up")
	a.set("hp", 0)
	d.advance(0.1)
	_expect(d.saw_knockdown(), "hp <= 0 is a knockdown")
	_expect(d.seconds_since_knockdown() >= 0.0, "...and the tail clock starts")
	for _i: int in 5:
		d.advance(0.1)
	_expect(d.saw_knockdown(), "the latch holds")
	_expect(d.seconds_since_knockdown() > 0.4, "...and the tail clock advances")
	_teardown(d)
	_completes("knockdown_latches")


## ⚠ THE RING-OUT IS THE OTHER WAY THIS STAGE ENDS A FIGHT, and reading only HP is
## what made a directed capture run its whole frame budget through two fighters
## repeatedly launching each other off the rim. Under `ringout_mode` a hit
## accumulates `damage_pct` instead of draining HP; a reset to zero after real
## accumulation IS the respawn, i.e. somebody just went off the stage.
func _test_ringout_counts() -> void:
	var d: ClipDirector = _director()
	var a: Node2D = _fighter(d, Vector2(700.0, GROUND), 100)
	_fighter(d, Vector2(900.0, GROUND), 100)
	d.advance(0.1)
	a.set("damage_pct", 180.0)     # a long exchange under the Smash model
	d.advance(0.1)
	_expect(not d.saw_knockdown(), "accumulating damage is not yet decisive")
	_expect(d.heat() > 0.0, "...but it does count as heat, unlike before the fix")
	a.set("damage_pct", 0.0)       # respawned: knocked off the stage
	d.advance(0.1)
	_expect(d.saw_knockdown(), "a ring-out ends the shot too")
	_teardown(d)
	_completes("ringout_counts_as_decisive")


## The asymmetric lean. Horizontally the camera follows the action fully; vertically
## it barely follows it at all, because fighters stand on a floor and spells go up.
func _test_vertical_lean() -> void:
	var from: Vector2 = Vector2(1000.0, 700.0)
	var toward: Vector2 = Vector2(1400.0, 100.0)     # a lightning column, high up
	var out: Vector2 = ClipDirector._lean(from, toward, 0.5)
	_expect(is_equal_approx(out.x, 1200.0),
		"x leans at full weight (got %.1f, wanted 1200)" % out.x)
	var moved_y: float = from.y - out.y
	var full_y: float = (from.y - toward.y) * 0.5
	_expect(moved_y < full_y * 0.5,
		"y leans far less than x (moved %.1f of a possible %.1f)" % [moved_y, full_y])
	_expect(moved_y > 0.0, "...but it does still lean — a damped lean, not none")
	_completes("vertical_lean_is_damped")


## However far a spectacle reaches, the eye stays in a band above the floor. This is
## the assertion behind the "340 of 400 frames came back as empty sky" note.
func _test_camera_stays_over_the_stage_body(spell_y: float) -> Vector2:
	var d: ClipDirector = _director()
	var cam := Camera2D.new()
	root.add_child(cam)
	d.bind(cam, STAGE, GROUND)
	_fighter(d, Vector2(700.0, GROUND), 100)
	_fighter(d, Vector2(900.0, spell_y), 100)
	for _i: int in 40:
		d.advance(0.1)
	var at: Vector2 = cam.global_position
	cam.free()
	_teardown(d)
	return at


func _test_camera_stays_over_stage() -> void:
	var low: Vector2 = _test_camera_stays_over_the_stage_body(GROUND)
	var high: Vector2 = _test_camera_stays_over_the_stage_body(-400.0)
	for at: Vector2 in [low, high]:
		_expect(at.y >= GROUND - ClipDirector.VERTICAL_BAND - 1.0,
			"the eye never rises above the band (y=%.1f, floor=%.1f)" % [at.y, GROUND])
		_expect(at.y <= GROUND - 39.0,
			"...nor sinks into the rock (y=%.1f)" % at.y)
		_expect(at.x >= STAGE.position.x + 339.0 and at.x <= STAGE.end.x - 339.0,
			"...nor drifts off the ends of the stage (x=%.1f)" % at.x)
	_completes("camera_stays_over_the_stage")


# ==========================================================================

func _director() -> ClipDirector:
	var d := ClipDirector.new()
	root.add_child(d)
	# The director drives its own clock through `advance`; `_process` would double it.
	d.set_process(false)
	d.stage = STAGE
	d.ground_y = GROUND
	return d


## A fighter stand-in: group `hero`, an `hp` and a `damage_pct`. Parented to the
## director's own parent (the root) so `get_tree().get_nodes_in_group` finds it.
func _fighter(_d: ClipDirector, at: Vector2, hp: int) -> Node2D:
	var n := Node2D.new()
	# ⚠ THE SCRIPT IS REQUIRED. `Object.set` on a property the object does not declare
	# is silently dropped, so a bare `Node2D` would read `hp` back as null and every
	# assertion in this file would pass or fail for the wrong reason.
	n.set_script(_STUB)
	n.global_position = at
	n.add_to_group(&"hero")
	n.set("hp", hp)
	n.set("max_hp", hp)
	n.set("damage_pct", 0.0)
	root.add_child(n)
	return n


## The two members `ClipDirector` reads off a fighter, and nothing else. Written
## inline as a GDScript source string because a stub file in `tools/` would be
## discovered by the capture-tool index and by the run-all harness.
const _STUB_SRC: String = """
extends Node2D
var hp: int = 100
var max_hp: int = 100
var damage_pct: float = 0.0
"""
static var _STUB: GDScript = _make_stub()


static func _make_stub() -> GDScript:
	var s := GDScript.new()
	s.source_code = _STUB_SRC
	s.reload()
	return s


func _teardown(d: ClipDirector) -> void:
	for n: Node in get_nodes_in_group(&"hero"):
		n.free()
	d.free()


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true
