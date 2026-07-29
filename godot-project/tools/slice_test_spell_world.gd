# Run: godot --headless --path godot-project --script tools/slice_test_spell_world.gd
#
# SpellWorld — the shared "stop at the first solid" helper every spectacle threads
# its spawn / travel / impact through. This suite exists for the maker's #1
# outstanding bug ("no spell may pass through geometry; meteors fall THROUGH the
# floor") so the regression can never come back one spell at a time.
#
# Uses a REAL physics space (extends SceneTree + await physics_frame, the
# slice3_test_spell_collision idiom) because every function under test is a
# world query — a synchronous helper harness would prove nothing but the
# degrade-to-no-hit path.
#
# THE TEST THAT MATTERS MOST is _test_queued_for_deletion_is_smashed(): a cover
# block that has just collapsed leaves the "destructible" group IMMEDIATELY while
# its collider survives until the deferred free, so a group-only smash test stops
# the spell dead on the very crate it just broke. That bug has already cost one
# session (see RockWall._is_smashable). Do not delete this test.
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
	"is_smashable_pure",
	"rids_helper",
	"clear_path_returns_endpoint",
	"wall_stops_and_reports",
	"degenerate_segment",
	"exclude_skips_a_wall",
	"destructible_is_smashed_through",
	"queued_for_deletion_is_smashed",
	"opt_out_makes_destructible_solid",
	"clip",
	"thick_catches_offset_wall",
	"floor_below_finds_floor",
	"floor_below_over_a_pit",
	"ground_path_stops_at_the_lip",
	"is_blocked",
	"reachability_through_cover",
]

var _fails: int = 0
var _completed: Dictionary = {}

## Everything is placed far from the origin-per-band so one test's leftovers can
## never satisfy another's ray. Each test tears its own bodies down.
const TOL: float = 2.0  # px — ray hit points land on the surface, not exactly on it


func _initialize() -> void:
	_run()  # fire-and-forget: awaits inside, quits when done


func _run() -> void:
	_test_is_smashable_pure()
	_test_rids_helper()
	await _test_clear_path_returns_endpoint()
	await _test_wall_stops_and_reports()
	await _test_degenerate_segment()
	await _test_exclude_skips_a_wall()
	await _test_destructible_is_smashed_through()
	await _test_queued_for_deletion_is_smashed()
	await _test_opt_out_makes_destructible_solid()
	await _test_clip()
	await _test_thick_catches_offset_wall()
	await _test_floor_below_finds_floor()
	await _test_floor_below_over_a_pit()
	await _test_ground_path_stops_at_the_lip()
	await _test_is_blocked()
	await _test_reachability_through_cover()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("SpellWorld tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("SpellWorld tests: all PASS")
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


# ------------------------------------------------------------------ fixtures

## A plain solid wall: StaticBody2D on the default collision_layer 1, no group —
## the "real world geometry" a spell must always stop against.
func _wall(at: Vector2, size: Vector2 = Vector2(40.0, 40.0)) -> StaticBody2D:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	body.global_position = at
	return body


## Destructible cover, matching DestructibleTerrain: collision_layer 5 (bits 1+4,
## so a mask-1 ray sees it) AND group "destructible", so it is smashed through.
func _crate(at: Vector2, size: Vector2 = Vector2(40.0, 40.0)) -> StaticBody2D:
	var body: StaticBody2D = _wall(at, size)
	body.collision_layer = 5
	body.add_to_group("destructible")
	return body


func _free_all(bodies: Array) -> void:
	for b: Node in bodies:
		if is_instance_valid(b):
			b.queue_free()
	await physics_frame
	await physics_frame


# ------------------------------------------------------------- pure behaviour

## The smash rule itself, with no world involved.
func _test_is_smashable_pure() -> void:
	var plain := Node2D.new()
	var crate := Node2D.new()
	crate.add_to_group("destructible")
	root.add_child(plain)
	root.add_child(crate)
	_expect(not SpellWorld.is_smashable(plain), "a plain node is NOT smashable")
	_expect(SpellWorld.is_smashable(crate), "a 'destructible' node IS smashable")
	_expect(SpellWorld.is_smashable(null), "a null collider counts as smashed (not there)")
	plain.queue_free()
	# Queued but not yet freed, and NOT in the group — the collapsed-cover case.
	_expect(SpellWorld.is_smashable(plain),
		"a queued-for-deletion node IS smashable even without the group")
	crate.queue_free()
	_completes("is_smashable_pure")


func _test_rids_helper() -> void:
	var body: StaticBody2D = _wall(Vector2(-9000.0, -9000.0))
	var not_a_collider := Node2D.new()
	root.add_child(not_a_collider)
	var got: Array[RID] = SpellWorld.rids([body, not_a_collider, null])
	_expect(got.size() == 1, "rids() keeps only live CollisionObject2Ds (got %s)" % got.size())
	_expect(got.size() == 1 and got[0] == body.get_rid(), "rids() returns the body's own RID")
	body.queue_free()
	not_a_collider.queue_free()
	_completes("rids_helper")


# ------------------------------------------------------------- core primitive

## Control: nothing in the way -> the endpoint comes back untouched, hit is false.
## Guards against the raycast false-positiving and eating spells that hit nothing.
func _test_clear_path_returns_endpoint() -> void:
	await physics_frame
	var from := Vector2(-4000.0, -4000.0)
	var to := Vector2(-3800.0, -4000.0)
	var r: Dictionary = SpellWorld.first_solid(from, to)
	_expect(not bool(r["hit"]), "clear path: hit == false")
	_expect((r["position"] as Vector2).distance_to(to) < TOL,
		"clear path: position is the original endpoint (%s)" % r["position"])
	_expect(r["collider"] == null, "clear path: no collider")
	_expect(absf(float(r["distance"]) - from.distance_to(to)) < TOL,
		"clear path: distance is the full span")
	_expect((r["smashed"] as Array).is_empty(), "clear path: nothing smashed")
	_completes("clear_path_returns_endpoint")


## The core case: a wall in the path stops the segment AT the wall, and reports
## what was hit + the surface normal so the caller can stage an impact there.
func _test_wall_stops_and_reports() -> void:
	var w: StaticBody2D = _wall(Vector2(100.0, 0.0))  # spans x 80..120
	await physics_frame
	var r: Dictionary = SpellWorld.first_solid(Vector2(0.0, 0.0), Vector2(300.0, 0.0))
	_expect(bool(r["hit"]), "wall: hit == true")
	var p: Vector2 = r["position"]
	_expect(absf(p.x - 80.0) < TOL, "wall: impact at the near face x≈80 (got %s)" % p.x)
	_expect(r["collider"] == w, "wall: collider is the wall")
	_expect((r["normal"] as Vector2).x < -0.5, "wall: normal faces back down the ray (%s)" % r["normal"])
	_expect(absf(float(r["distance"]) - 80.0) < TOL,
		"wall: distance is travel-along-the-segment (got %s)" % r["distance"])
	await _free_all([w])
	_completes("wall_stops_and_reports")


## A zero-length probe is not a segment question; it must not report a phantom
## impact. (Callers asking "is this SPOT solid" want is_blocked.)
func _test_degenerate_segment() -> void:
	var w: StaticBody2D = _wall(Vector2(100.0, 600.0))
	await physics_frame
	var at := Vector2(100.0, 600.0)
	var r: Dictionary = SpellWorld.first_solid(at, at)
	_expect(not bool(r["hit"]), "degenerate segment: no phantom hit even inside a body")
	await _free_all([w])
	_completes("degenerate_segment")


## The self-collision guard: a spell spawned overlapping its caster must be able
## to exclude it, or every cast instantly stops on the person casting it.
func _test_exclude_skips_a_wall() -> void:
	var w: StaticBody2D = _wall(Vector2(100.0, 900.0))
	await physics_frame
	var from := Vector2(0.0, 900.0)
	var to := Vector2(300.0, 900.0)
	_expect(bool(SpellWorld.first_solid(from, to)["hit"]),
		"exclude control: the wall does stop an unexcluded ray")
	var r: Dictionary = SpellWorld.first_solid(from, to, SpellWorld.rids([w]))
	_expect(not bool(r["hit"]), "exclude: an excluded body does not stop the ray")
	await _free_all([w])
	_completes("exclude_skips_a_wall")


# --------------------------------------------------------- the smash-through

## Cover is SMASHED, not respected: the spell keeps going past a crate and lands
## on the wall behind it, and the crate comes back in `smashed` so the caller can
## damage it ("destroy what it can").
func _test_destructible_is_smashed_through() -> void:
	var crate: StaticBody2D = _crate(Vector2(100.0, 1200.0))   # x 80..120
	var w: StaticBody2D = _wall(Vector2(200.0, 1200.0))        # x 180..220
	await physics_frame
	var r: Dictionary = SpellWorld.first_solid(Vector2(0.0, 1200.0), Vector2(300.0, 1200.0))
	_expect(bool(r["hit"]), "smash: still stops on the wall behind the crate")
	_expect(r["collider"] == w, "smash: the collider is the WALL, not the crate")
	_expect(absf((r["position"] as Vector2).x - 180.0) < TOL,
		"smash: impact at the wall face x≈180 (got %s)" % (r["position"] as Vector2).x)
	var smashed: Array = r["smashed"]
	_expect(smashed.size() == 1 and smashed[0] == crate,
		"smash: the crate is reported in `smashed` so it can be damaged")
	await _free_all([crate, w])
	_completes("destructible_is_smashed_through")


## ⚠ THE REGRESSION GUARD. A cover block that just collapsed leaves the
## "destructible" group IMMEDIATELY while its collider survives until the deferred
## free. A group-only smash test would see a group-less solid body and stop the
## spell dead on the very crate it just broke.
##
## Note the deliberate absence of an `await` after queue_free(): that reproduces
## the real timing — the smash pass and the ray happen in the SAME frame, before
## the deferred free lands. The first assertion proves the collider really is
## still live in the space, so the second assertion cannot pass vacuously.
func _test_queued_for_deletion_is_smashed() -> void:
	var collapsing: StaticBody2D = _wall(Vector2(100.0, 1500.0))  # NOT in the group
	await physics_frame
	var from := Vector2(0.0, 1500.0)
	var to := Vector2(300.0, 1500.0)
	collapsing.queue_free()
	_expect(collapsing.is_queued_for_deletion(), "regression: the body IS queued for deletion")
	# Proof the collider is still in the space this frame — otherwise the real
	# assertion below would pass for the wrong reason.
	_expect(
		bool(SpellWorld.first_solid(from, to, [], null, false)["hit"]),
		"regression: the collapsing body's collider is still live in the space"
	)
	var r: Dictionary = SpellWorld.first_solid(from, to)
	_expect(not bool(r["hit"]),
		"regression: a queued-for-deletion collider is SMASHED THROUGH, not treated as a wall")
	await physics_frame
	await physics_frame
	_completes("queued_for_deletion_is_smashed")


## The opt-out still works: a spell that should be stopped by cover can ask for it.
func _test_opt_out_makes_destructible_solid() -> void:
	var crate: StaticBody2D = _crate(Vector2(100.0, 1800.0))
	await physics_frame
	var r: Dictionary = SpellWorld.first_solid(
		Vector2(0.0, 1800.0), Vector2(300.0, 1800.0), [], null, false)
	_expect(bool(r["hit"]), "opt-out: smash_destructibles=false stops on the crate")
	_expect(r["collider"] == crate, "opt-out: the collider is the crate")
	await _free_all([crate])
	_completes("opt_out_makes_destructible_solid")


# ----------------------------------------------------------------- clip/thick

func _test_clip() -> void:
	var w: StaticBody2D = _wall(Vector2(100.0, 2100.0))
	await physics_frame
	var from := Vector2(0.0, 2100.0)
	var blocked: Vector2 = SpellWorld.clip(from, Vector2(300.0, 2100.0))
	_expect(absf(blocked.x - 80.0) < TOL,
		"clip: a blocked beam ends at the wall (got %s)" % blocked.x)
	var open_to := Vector2(0.0, 2400.0)
	var clear: Vector2 = SpellWorld.clip(Vector2(-500.0, 2400.0), open_to)
	_expect(clear.distance_to(open_to) < TOL, "clip: a clear beam keeps its full length")
	await _free_all([w])
	_completes("clip")


## A hairline centre ray misses a wall the beam's own WIDTH straddles. This is
## RockWall._hit_world's three-height sample generalised: the thick query must see
## what the centre line slips past.
func _test_thick_catches_offset_wall() -> void:
	# The wall spans y 2710..2750, entirely BELOW the centre line at y=2700, so a
	# hairline ray misses it while an 80 px-wide path straddles it.
	var w: StaticBody2D = _wall(Vector2(100.0, 2730.0))
	await physics_frame
	var from := Vector2(0.0, 2700.0)
	var to := Vector2(300.0, 2700.0)
	_expect(not bool(SpellWorld.first_solid(from, to)["hit"]),
		"thick control: the hairline centre ray misses the offset wall")
	var r: Dictionary = SpellWorld.first_solid_thick(from, to, 80.0)
	_expect(bool(r["hit"]), "thick: a wide path DOES catch the offset wall")
	_expect(absf(float(r["distance"]) - 80.0) < TOL,
		"thick: distance is measured along the centre line (got %s)" % r["distance"])
	await _free_all([w])
	_completes("thick_catches_offset_wall")


# ------------------------------------------------------------ the vertical case

## The meteor bug, directly: the impact Y must come from the FLOOR under the
## target, not from the target's own y.
func _test_floor_below_finds_floor() -> void:
	var ground: StaticBody2D = _wall(Vector2(0.0, 3100.0), Vector2(400.0, 40.0))  # top at y=3080
	await physics_frame
	var above := Vector2(0.0, 2900.0)
	var r: Dictionary = SpellWorld.floor_below(above)
	_expect(bool(r["hit"]), "floor_below: found the floor")
	_expect(absf((r["position"] as Vector2).y - 3080.0) < TOL,
		"floor_below: impact y is the floor surface, not the caller's y (got %s)"
			% (r["position"] as Vector2).y)
	_expect(absf((r["position"] as Vector2).x - above.x) < TOL,
		"floor_below: x is unchanged")
	_expect(r["collider"] == ground, "floor_below: reports the floor it found")
	_expect(SpellWorld.floor_point(above).distance_to(r["position"] as Vector2) < TOL,
		"floor_point: agrees with floor_below")
	await _free_all([ground])
	_completes("floor_below_finds_floor")


## A pit: hit is false and `position` is the caller's own point UNCHANGED — never
## the bottom of the probe, which would drop the effect into the void (the very
## thing this file exists to stop).
func _test_floor_below_over_a_pit() -> void:
	await physics_frame
	var over_nothing := Vector2(20000.0, 20000.0)
	var r: Dictionary = SpellWorld.floor_below(over_nothing)
	_expect(not bool(r["hit"]), "pit: hit == false when there is no floor")
	_expect((r["position"] as Vector2).distance_to(over_nothing) < TOL,
		"pit: position is the caller's point unchanged, NOT the probe's far end (%s)" % r["position"])
	_expect(float(r["distance"]) == 0.0, "pit: distance is 0")
	_completes("floor_below_over_a_pit")


## A ground-hugging effect follows the terrain, and STOPS at the lip of a pit
## rather than drawing itself across thin air.
func _test_ground_path_stops_at_the_lip() -> void:
	# Floor from x -100..100 only; everything past x=100 is a pit.
	var ground: StaticBody2D = _wall(Vector2(0.0, 3600.0), Vector2(200.0, 40.0))  # top y=3580
	await physics_frame
	var full: PackedVector2Array = SpellWorld.ground_path(
		Vector2(-80.0, 3400.0), Vector2(80.0, 3400.0), 9)
	_expect(full.size() == 9, "ground_path: samples the whole span over solid floor (got %s)" % full.size())
	_expect(full.size() > 0 and absf(full[0].y - 3580.0) < TOL,
		"ground_path: points sit on the floor surface")
	var over_edge: PackedVector2Array = SpellWorld.ground_path(
		Vector2(-80.0, 3400.0), Vector2(400.0, 3400.0), 9)
	_expect(over_edge.size() > 0 and over_edge.size() < 9,
		"ground_path: stops at the lip of the pit (got %s of 9)" % over_edge.size())
	await _free_all([ground])
	_completes("ground_path_stops_at_the_lip")


# ------------------------------------------------------- occupancy / legality

func _test_is_blocked() -> void:
	var w: StaticBody2D = _wall(Vector2(0.0, 4000.0), Vector2(100.0, 100.0))  # y 3950..4050
	var crate: StaticBody2D = _crate(Vector2(400.0, 4000.0), Vector2(100.0, 100.0))
	await physics_frame
	_expect(SpellWorld.is_blocked(Vector2(0.0, 4000.0)),
		"is_blocked: a point inside solid rock is blocked")
	_expect(not SpellWorld.is_blocked(Vector2(0.0, 3500.0)),
		"is_blocked: a point in open air is not blocked")
	# Radius test: the circle at y=3900 r=80 reaches down to 3980, inside the wall.
	_expect(SpellWorld.is_blocked(Vector2(0.0, 3900.0), 80.0),
		"is_blocked: a body-sized destination overlapping the wall is blocked")
	_expect(not SpellWorld.is_blocked(Vector2(0.0, 3900.0), 10.0),
		"is_blocked: the same point with a small radius is clear")
	_expect(not SpellWorld.is_blocked(Vector2(400.0, 4000.0)),
		"is_blocked: you may land inside a destructible (it breaks)")
	_expect(SpellWorld.is_blocked(Vector2(400.0, 4000.0), 0.0, [], null, false),
		"is_blocked: ...unless the caller opts out of smashing")
	_expect(not SpellWorld.is_blocked(Vector2(0.0, 4000.0), 0.0, SpellWorld.rids([w])),
		"is_blocked: an excluded body does not block")
	await _free_all([w, crate])
	_completes("is_blocked")


## "The spells shouldn't be able to get out the radius", in its through-walls
## form: a target inside the radius but BEHIND a wall must be dropped.
func _test_reachability_through_cover() -> void:
	var w: StaticBody2D = _wall(Vector2(100.0, 4500.0))
	var behind := Node2D.new()
	var open := Node2D.new()
	root.add_child(behind)
	root.add_child(open)
	behind.global_position = Vector2(200.0, 4500.0)   # wall between it and the centre
	open.global_position = Vector2(0.0, 4700.0)       # clear line
	await physics_frame
	var centre := Vector2(0.0, 4500.0)
	_expect(not SpellWorld.can_reach(centre, behind.global_position),
		"can_reach: false through a wall")
	_expect(SpellWorld.can_reach(centre, open.global_position),
		"can_reach: true over open ground")
	var kept: Array = SpellWorld.filter_reachable(centre, [behind, open])
	_expect(kept.size() == 1 and kept[0] == open,
		"filter_reachable: drops the target behind cover, keeps the one in the open")
	behind.queue_free()
	open.queue_free()
	await _free_all([w])
	_completes("reachability_through_cover")
