# Run: godot --headless --path godot-project --script tools/slice4_test_spells.gd
# Pure-geometry tests for the spectacle signature spells: the beam line test and
# the divine-ray radius test. No physics world needed (the damage selectors are
# static functions over node global_positions).
#
# The scripts are load()ed at RUNTIME (never referenced by class_name) because
# BeamSpell/DivineRay reference the Sfx AUTOLOAD, which only registers once the
# main loop is live — a compile-time class_name reference would fail to resolve
# Sfx and (per the ledger's test trap) print a false PASS. Runs on the first
# _process frame, by which point Sfx exists.
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
	"beam_line",
	"divine_radius",
	"meteor_radius",
	"convergence_radius",
	"crawler_catch",
	"dagger_burst_radius",
]

var _fails: int = 0
var _completed: Dictionary = {}

const BEAM_PATH: String = "res://scripts/combat/BeamSpell.gd"
const RAY_PATH: String = "res://scripts/combat/DivineRay.gd"
const METEOR_PATH: String = "res://scripts/combat/MeteorSigil.gd"
const CONVERGENCE_PATH: String = "res://scripts/combat/StarConvergence.gd"
const CRAWLER_PATH: String = "res://scripts/combat/ShadowCrawler.gd"
const DAGGER_PATH: String = "res://scripts/combat/RiftDagger.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_beam_line()
	_test_divine_radius()
	_test_meteor_radius()
	_test_convergence_radius()
	_test_crawler_catch()
	_test_dagger_burst_radius()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice4 spell tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice4 spell tests: all PASS")
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


func _node_at(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	root.add_child(n)
	n.global_position = pos
	return n


func _test_beam_line() -> void:
	var origin := Vector2(0.0, 0.0)
	var dir := Vector2.RIGHT
	var length := 500.0
	var half := 20.0
	var on_line: Node2D = _node_at(Vector2(300.0, 5.0))     # on the beam
	var too_wide: Node2D = _node_at(Vector2(300.0, 40.0))   # perpendicular miss
	var behind: Node2D = _node_at(Vector2(-50.0, 0.0))      # behind the muzzle
	var beyond: Node2D = _node_at(Vector2(700.0, 0.0))      # past the tip
	var beam: GDScript = load(BEAM_PATH)
	var hit: Array = beam.targets_on_beam(origin, dir, length, half, [on_line, too_wide, behind, beyond])
	_expect(on_line in hit, "enemy on the beam line is hit")
	_expect(not (too_wide in hit), "enemy outside the beam width is missed")
	_expect(not (behind in hit), "enemy behind the muzzle is missed")
	_expect(not (beyond in hit), "enemy past the beam tip is missed")
	_expect(hit.size() == 1, "exactly one target on the beam (got %d)" % hit.size())
	_completes("beam_line")


func _test_divine_radius() -> void:
	var center := Vector2(100.0, 100.0)
	var inside: Node2D = _node_at(Vector2(140.0, 100.0))    # 40px < 90
	var edge: Node2D = _node_at(Vector2(100.0, 189.0))      # 89px < 90
	var outside: Node2D = _node_at(Vector2(100.0, 250.0))   # 150px > 90
	var ray: GDScript = load(RAY_PATH)
	var hit: Array = ray.targets_in_radius(center, 90.0, [inside, edge, outside])
	_expect(inside in hit, "enemy inside the divine footprint is hit")
	_expect(edge in hit, "enemy at the footprint edge is hit")
	_expect(not (outside in hit), "enemy outside the footprint is missed")
	_completes("divine_radius")


func _test_meteor_radius() -> void:
	var impact := Vector2(0.0, 0.0)
	var close: Node2D = _node_at(Vector2(30.0, 0.0))    # inside a 48px meteor blast
	var far: Node2D = _node_at(Vector2(120.0, 0.0))     # outside it
	var meteor: GDScript = load(METEOR_PATH)
	var hit: Array = meteor.targets_in_radius(impact, 48.0, [close, far])
	_expect(close in hit, "enemy in a meteor blast is hit")
	_expect(not (far in hit), "enemy outside a meteor blast is missed")
	_completes("meteor_radius")


func _test_convergence_radius() -> void:
	var center := Vector2(0.0, 0.0)
	var inside: Node2D = _node_at(Vector2(100.0, 0.0))    # inside a 160px nova
	var far: Node2D = _node_at(Vector2(220.0, 0.0))       # outside it
	var conv: GDScript = load(CONVERGENCE_PATH)
	var hit: Array = conv.targets_in_radius(center, 160.0, [inside, far])
	_expect(inside in hit, "enemy inside the convergence nova is hit")
	_expect(not (far in hit), "enemy outside the nova is missed")
	_completes("convergence_radius")


## The Creeping Shade's catch window. Asymmetric on purpose: generous UPWARD (a
## grounded body's centre rides above the floor the head runs along) and tight
## downward, so a body one platform below is not speared through the floor. The
## upward limit is also the whole dodge: jump and the shade passes under you.
func _test_crawler_catch() -> void:
	var head := Vector2(200.0, 400.0)
	var crawler: GDScript = load(CRAWLER_PATH)
	_expect(crawler.caught_by(head, Vector2(206.0, 382.0), 26.0),
		"a body standing in the head's column is caught")
	_expect(not crawler.caught_by(head, Vector2(240.0, 382.0), 26.0),
		"a body outside the catch half-width is passed by")
	_expect(crawler.caught_by(head, Vector2(200.0, 348.0), 26.0),
		"a body 52px up (still grounded-tall) is caught")
	_expect(not crawler.caught_by(head, Vector2(200.0, 330.0), 26.0),
		"an AIRBORNE body above the catch height is missed — jumping dodges it")
	_expect(not crawler.caught_by(head, Vector2(200.0, 460.0), 26.0),
		"a body well below the head (another floor) is missed")
	_completes("crawler_catch")


## The Rift Dagger's arrival burst — the radius query that resolves the second
## beat at the teleport destination.
func _test_dagger_burst_radius() -> void:
	var dest := Vector2(-300.0, 90.0)
	var inside: Node2D = _node_at(Vector2(-350.0, 90.0))    # 50px < 70
	var outside: Node2D = _node_at(Vector2(-300.0, 200.0))  # 110px > 70
	var dagger: GDScript = load(DAGGER_PATH)
	var hit: Array = dagger.targets_in_radius(dest, 70.0, [inside, outside])
	_expect(inside in hit, "enemy inside the rift arrival burst is hit")
	_expect(not (outside in hit), "enemy outside the arrival burst is missed")
	_completes("dagger_burst_radius")
