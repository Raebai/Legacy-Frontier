# Run: godot --headless --path godot-project --script tools/slice_test_spell_targets.gd
#
# SpellTargets — the ONE canonical "who is actually hit?" helper, replacing the
# eight copy-pasted `targets_in_radius` / `targets_on_line` loops. This suite exists
# for two maker-reported bugs:
#
#   Bug 1: "spells pass through heads without registering." Enemy's drawn head
#          centre sits 9.9 px ABOVE its node origin (18.9 px on the 1.9x sparring
#          dummies) while every spell tested `global_position` — a zero-size point
#          about ten pixels below the head being aimed at.
#   Bug 2: blasts damaged THROUGH walls, because a group loop plus a distance test
#          never asks what is between the spell and the victim.
#
# ⚠ THE NEGATIVE CASES MATTER FAR MORE THAN THE POSITIVE ONES. A helper that made
# everything hit would pass every "the head registers" test in this file. The only
# thing standing between this fix and a stealth hitbox inflation across the whole
# game is the block of tests that assert what must NOT be hit: just outside the
# radius, behind a wall, past the end of a beam, behind you in a cone, already
# queued for deletion, and — the big one — that a target with NO silhouette
# resolves BYTE-IDENTICALLY to the old `center.distance_to(n.global_position) <=
# radius`. Do not weaken those to make a feel tweak land.
#
# Uses a REAL physics space (extends SceneTree + await physics_frame, the
# slice3_test_spell_collision / slice_test_spell_world idiom) because line of sight
# is a world query — a synchronous harness would only ever prove the
# degrade-to-no-cull path.
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
	"stub_matches_real_enemy",
	"silhouette_seam_duck_types",
	"fallback_for_a_plain_node",
	"default_margin_is_zero",
	"head_height_registers",
	"body_height_registers",
	"just_outside_the_radius_misses",
	"plain_node_is_byte_identical_to_the_old_test",
	"scale_awareness",
	"behind_a_wall_is_not_hit",
	"los_opt_out_hits_through_the_wall",
	"caster_is_excluded",
	"queued_for_deletion_never_appears",
	"non_node2d_is_dropped",
	"on_line_catches_a_head_height_beam",
	"on_line_misses_over_the_head_and_past_the_tip",
	"on_line_respects_cover",
	"in_cone",
	"nearest",
	"sorted_by_distance_is_stable",
]

var _fails: int = 0
var _completed: Dictionary = {}

## Each band of tests lives thousands of px from every other so one test's leftover
## bodies can never satisfy another's ray or radius.
const TOL: float = 0.001

const DUMMY_SCALE: float = 1.9  # SpellPlaygroundController's sparring dummies

const ENEMY_SCRIPT_PATH: String = "res://scripts/combat/Enemy.gd"
const RigScript: GDScript = preload("res://scripts/combat/CharacterRig.gd")


## A target that DRAWS a body: spine segment + head circle, scale-aware. Publishes
## the same three duck-typed methods `Enemy` does, and by the same formulas, so the
## suite can exercise the silhouette path without dragging the whole Enemy brain
## (and its autoload-dependent _physics_process) into a --script harness.
##
## The rig factors live INSIDE this inner class, referenced from the outer suite as
## `Silhouette.RIG_H`. Inner classes do not reliably see the outer script's constant
## scope in GDScript, and a stub that quietly failed to compile would take the whole
## suite down with a misleading error. They mirror Enemy.RIG_HEAD_R_FACTOR /
## RIG_HIP_Y_FACTOR / HIT_MARGIN_FACTOR and CharacterRig's default height, and
## `_test_stub_matches_real_enemy()` asserts that mirroring still holds.
class Silhouette extends Node2D:
	const RIG_H: float = 31.0
	## Moved 0.18 -> 0.105 / 0.12 -> 0.155 with the stickman proportion pass (the drawn
	## figure got spindly, so the tested silhouette did too). Still hand-copied rather
	## than read from Enemy — see the class note — and still guarded by
	## `_test_stub_matches_real_enemy()`, which is exactly the assertion that caught
	## this drift the moment the real constants moved.
	const HEAD_R_FACTOR: float = 0.105
	const HIP_Y_FACTOR: float = 0.1
	const MARGIN_FACTOR: float = 0.155

	var height: float = RIG_H

	func _sil() -> Dictionary:
		var head_r: float = height * HEAD_R_FACTOR
		var head_local := Vector2(0.0, -height * 0.5 + head_r)
		var xf: Transform2D = global_transform
		var s: float = absf(xf.get_scale().y)
		return {
			"neck": xf * (head_local + Vector2(0.0, head_r)),
			"hip": xf * Vector2(0.0, height * HIP_Y_FACTOR),
			"head": xf * head_local,
			"head_r": head_r * s,
			"scale": s,
		}

	func body_distance(p: Vector2) -> float:
		var s: Dictionary = _sil()
		var spine_d: float = SpellGeometry.point_segment_distance(
			p, s["neck"] as Vector2, s["hip"] as Vector2)
		return minf(spine_d, p.distance_to(s["head"] as Vector2) - float(s["head_r"]))

	func hit_margin() -> float:
		return height * MARGIN_FACTOR * float(_sil()["scale"])

	func head_point() -> Vector2:
		return _sil()["head"] as Vector2


func _initialize() -> void:
	_run()  # fire-and-forget: awaits inside, quits when done


func _run() -> void:
	# --- the duck-typed seam, and its fallback
	await _test_stub_matches_real_enemy()
	await _test_silhouette_seam_duck_types()
	await _test_fallback_for_a_plain_node()
	await _test_default_margin_is_zero()
	# --- in_radius: the headline fix, then the guards
	await _test_head_height_registers()
	await _test_body_height_registers()
	await _test_just_outside_the_radius_misses()
	await _test_plain_node_is_byte_identical_to_the_old_test()
	await _test_scale_awareness()
	# --- line of sight
	await _test_behind_a_wall_is_not_hit()
	await _test_los_opt_out_hits_through_the_wall()
	# --- the pool guards
	await _test_caster_is_excluded()
	await _test_queued_for_deletion_never_appears()
	await _test_non_node2d_is_dropped()
	# --- the other selectors
	await _test_on_line_catches_a_head_height_beam()
	await _test_on_line_misses_over_the_head_and_past_the_tip()
	await _test_on_line_respects_cover()
	await _test_in_cone()
	await _test_nearest()
	await _test_sorted_by_distance_is_stable()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("SpellTargets tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("SpellTargets tests: all PASS")
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


# ------------------------------------------------------------------- fixtures

## A drawn body at `at`. `node_scale` reproduces the 1.9x sparring dummies.
func _figure(at: Vector2, node_scale: float = 1.0) -> Silhouette:
	var f := Silhouette.new()
	root.add_child(f)
	f.global_position = at
	f.scale = Vector2(node_scale, node_scale)
	return f


## A target with NO silhouette methods at all — a crate, a bolt, a stub. This is the
## fallback path, and it must behave exactly as the pre-SpellTargets code did.
func _plain(at: Vector2) -> Node2D:
	var n := Node2D.new()
	root.add_child(n)
	n.global_position = at
	return n


## Solid world geometry: StaticBody2D on collision layer 1, no group — what the
## LOS ray (SpellWorld.SOLID_MASK) sees.
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


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await physics_frame
	await physics_frame


# ------------------------------------------------------------ the duck-typed seam

## The stub is only worth testing against if it agrees with the REAL Enemy. Built
## the way Enemy.tscn does (Rig child + the shipped 20x20 movement collider), the
## way slice_test_enemy_silhouette._setup does it.
##
## This is also the test that proves the duck-typing binds to the SHIPPED contract
## rather than to a convenient stub: `SpellTargets.body_distance` / `hit_margin` /
## `aim_point` are called against a live Enemy here, not a Silhouette.
func _test_stub_matches_real_enemy() -> void:
	await physics_frame
	var enemy: CharacterBody2D = (load(ENEMY_SCRIPT_PATH) as GDScript).new()
	enemy.collision_layer = 4
	var rig: CharacterRig = RigScript.new()
	rig.name = "Rig"
	enemy.add_child(rig)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20.0, 20.0)
	shape.shape = rect
	enemy.add_child(shape)
	root.add_child(enemy)
	# No brain, no autoloads: this suite steps physics frames, and Enemy's
	# _physics_process reaches for a hero / tuning that a --script harness has not
	# registered. We only want its GEOMETRY.
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.global_position = Vector2(0.0, -9000.0)

	var stub: Silhouette = _figure(Vector2(0.0, -9000.0))
	# The three seams, real vs stub, at a spread of probe points.
	for p: Vector2 in [
		Vector2(0.0, -9000.0), Vector2(0.0, -9012.0), Vector2(14.0, -9004.0),
		Vector2(-40.0, -8990.0),
	]:
		var real_d: float = SpellTargets.body_distance(enemy, p)
		var stub_d: float = SpellTargets.body_distance(stub, p)
		_expect(absf(real_d - stub_d) < 0.01,
			"stub silhouette matches the real Enemy at %s (real %.3f vs stub %.3f)"
				% [p, real_d, stub_d])
	_expect(
		absf(SpellTargets.hit_margin(enemy) - SpellTargets.hit_margin(stub)) < 0.01,
		"stub margin matches the real Enemy's (%.3f vs %.3f)"
			% [SpellTargets.hit_margin(enemy), SpellTargets.hit_margin(stub)])
	_expect(
		SpellTargets.aim_point(enemy).distance_to(SpellTargets.aim_point(stub)) < 0.01,
		"stub head_point matches the real Enemy's")
	# THE ROOT CAUSE, restated numerically against the shipped class: the head the
	# player aims at is ~10 px above the point every spell used to test.
	var head_rise: float = enemy.global_position.y - SpellTargets.aim_point(enemy).y
	_expect(head_rise > 9.0,
		"the real Enemy's head sits %.1f px ABOVE its origin — the band spells flew through"
			% head_rise)
	await _free_all([enemy, stub])
	_completes("stub_matches_real_enemy")


## Each of the three methods is picked up INDEPENDENTLY. This matters because
## `SpikeFigure` publishes `body_distance` but NOT `hit_margin`: a helper that
## demanded the whole trio would silently fall back to a point test on the player.
func _test_silhouette_seam_duck_types() -> void:
	var f: Silhouette = _figure(Vector2(0.0, 1000.0))
	_expect(f.has_method(&"body_distance") and f.has_method(&"hit_margin"),
		"fixture sanity: the stub publishes the seam")
	var head: Vector2 = SpellTargets.aim_point(f)
	_expect(head.y < 1000.0 - 9.0,
		"aim_point returns the drawn HEAD, well above the origin (y=%.2f)" % head.y)
	_expect(SpellTargets.body_distance(f, head) <= 0.0,
		"a point dead-centre on the head is INSIDE the silhouette")
	_expect(SpellTargets.hit_margin(f) > 3.0,
		"hit_margin comes from the target, not from this file (%.2f)"
			% SpellTargets.hit_margin(f))
	# Freed / null targets fail CLOSED: INF distance, never a hit.
	_expect(SpellTargets.body_distance(null, Vector2.ZERO) == INF,
		"a null target is INF away, so it can never satisfy a <= test")
	_expect(not SpellTargets.hits(null, Vector2.ZERO, 99999.0),
		"...and hits() says no even for an absurd reach")
	await _free_all([f])
	_completes("silhouette_seam_duck_types")


## The fallback. A target with none of the three methods must resolve on
## `global_position` with ZERO margin — i.e. exactly the old behaviour.
func _test_fallback_for_a_plain_node() -> void:
	var p: Node2D = _plain(Vector2(0.0, 2000.0))
	_expect(not p.has_method(&"body_distance"),
		"fixture sanity: the plain node has no silhouette")
	var probe := Vector2(30.0, 2000.0)
	_expect(absf(SpellTargets.body_distance(p, probe) - 30.0) < TOL,
		"fallback measures to global_position (%.4f, want 30)"
			% SpellTargets.body_distance(p, probe))
	_expect(SpellTargets.hit_margin(p) == 0.0,
		"a marginless target gets NO forgiveness (%.4f)" % SpellTargets.hit_margin(p))
	_expect(SpellTargets.aim_point(p).is_equal_approx(p.global_position),
		"aim_point falls back to the origin")
	await _free_all([p])
	_completes("fallback_for_a_plain_node")


## The anti-inflation constant, asserted directly. If someone "helpfully" raises
## DEFAULT_HIT_MARGIN, every crate, bolt and prop in the game silently grows.
func _test_default_margin_is_zero() -> void:
	_expect(SpellTargets.DEFAULT_HIT_MARGIN == 0.0,
		"DEFAULT_HIT_MARGIN is 0 — the fallback path must not inflate anything")
	_completes("default_margin_is_zero")


# ------------------------------------------------------------------- in_radius

## THE HEADLINE FIX. A blast centred on the drawn head registers, and the same
## blast would have MISSED under the old origin-point rule — asserted side by side
## so the test cannot pass vacuously.
func _test_head_height_registers() -> void:
	var f: Silhouette = _figure(Vector2(0.0, 3000.0))
	await physics_frame
	var head: Vector2 = SpellTargets.aim_point(f)
	var tiny: float = 1.0  # a pinprick blast, dead on the head
	var got: Array = SpellTargets.in_radius(head, tiny, [f])
	_expect(got.size() == 1 and got[0] == f,
		"a blast on the head hits (%d results)" % got.size())
	# The control: the OLD test, verbatim. It misses, which is the reported bug.
	var old_hit: bool = head.distance_to(f.global_position) <= tiny
	_expect(not old_hit,
		"control: the old origin-point test MISSES the same blast (head is %.1f px up)"
			% (f.global_position.y - head.y))
	# And the exact band the old 20x20 collider had nothing behind: 1 px above its
	# top edge, at head height.
	var dead_zone := Vector2(0.0, 3000.0 - 11.0)
	_expect(SpellTargets.in_radius(dead_zone, 1.0, [f]).size() == 1,
		"the old dead zone just above the movement collider now registers")
	await _free_all([f])
	_completes("head_height_registers")


## The spine, not just the head — the fix must not trade one dead band for another.
func _test_body_height_registers() -> void:
	var f: Silhouette = _figure(Vector2(0.0, 4000.0))
	await physics_frame
	for dy: float in [-4.0, 0.0, 3.0]:
		var at := Vector2(0.0, 4000.0 + dy)
		_expect(SpellTargets.in_radius(at, 1.0, [f]).size() == 1,
			"a blast on the spine at dy=%.1f registers" % dy)
	await _free_all([f])
	_completes("body_height_registers")


## ⚠ THE MOST IMPORTANT TEST IN THE FILE. Bounds are computed from the target's own
## reported distance and margin, so this asserts the exact boundary rather than a
## number someone can quietly widen: 2 px inside the boundary hits, 2 px outside
## does not. Without this, "test the silhouette" degrades into "hit everything".
func _test_just_outside_the_radius_misses() -> void:
	var f: Silhouette = _figure(Vector2(0.0, 5000.0))
	await physics_frame
	var centre := Vector2(120.0, 5000.0)
	var d: float = SpellTargets.body_distance(f, centre)
	var m: float = SpellTargets.hit_margin(f)
	# The boundary is d <= radius + m, i.e. radius = d - m.
	var inside: float = d - m + 2.0
	var outside: float = d - m - 2.0
	_expect(SpellTargets.in_radius(centre, inside, [f]).size() == 1,
		"just INSIDE the boundary hits (radius %.2f, body %.2f, margin %.2f)"
			% [inside, d, m])
	_expect(SpellTargets.in_radius(centre, outside, [f]).is_empty(),
		"just OUTSIDE the boundary does NOT hit (radius %.2f, body %.2f, margin %.2f)"
			% [outside, d, m])
	# Grossly out of range, in every direction, is obviously a miss.
	for far: Vector2 in [
		Vector2(0.0, 5000.0 - 200.0), Vector2(0.0, 5000.0 + 200.0),
		Vector2(200.0, 5000.0), Vector2(-200.0, 5000.0),
	]:
		_expect(SpellTargets.in_radius(far, 40.0, [f]).is_empty(),
			"a blast 200 px away at %s does not reach" % far)
	await _free_all([f])
	_completes("just_outside_the_radius_misses")


## THE NO-OP GUARANTEE. For a target with no silhouette, this helper must agree with
## the old copy-pasted formula at EVERY distance, including exactly on the boundary.
## Swept rather than spot-checked, because a one-sided `<` vs `<=` slip would only
## show at the boundary and would quietly change every crate in the game.
func _test_plain_node_is_byte_identical_to_the_old_test() -> void:
	var p: Node2D = _plain(Vector2(0.0, 6000.0))
	await physics_frame
	var centre := Vector2(0.0, 6000.0 - 50.0)
	var mismatches: int = 0
	for step: int in 40:
		var radius: float = float(step) * 2.5  # 0 .. 97.5, crossing the true 50
		var old_says: bool = centre.distance_to(p.global_position) <= radius
		var new_says: bool = not SpellTargets.in_radius(centre, radius, [p]).is_empty()
		if old_says != new_says:
			mismatches += 1
	_expect(mismatches == 0,
		"a marginless target resolves identically to the old test at every radius (%d mismatches)"
			% mismatches)
	# Exactly ON the boundary is inclusive, as it always was.
	_expect(not SpellTargets.in_radius(centre, 50.0, [p]).is_empty(),
		"the boundary itself is inclusive (<=, not <)")
	await _free_all([p])
	_completes("plain_node_is_byte_identical_to_the_old_test")


## The 1.9x sparring dummies are where the maker actually noticed the bug. Nothing
## may be hardcoded to rig height 31 — every number must come from the target.
func _test_scale_awareness() -> void:
	var plain: Silhouette = _figure(Vector2(0.0, 7000.0))
	var big: Silhouette = _figure(Vector2(0.0, 7400.0), DUMMY_SCALE)
	await physics_frame
	var head: Vector2 = SpellTargets.aim_point(big)
	var rise: float = big.global_position.y - head.y
	_expect(rise > 18.0,
		"a %.1fx dummy's head is %.1f px above its origin" % [DUMMY_SCALE, rise])
	_expect(SpellTargets.in_radius(head, 1.0, [big]).size() == 1,
		"a pinprick blast on the big dummy's head registers")
	_expect(
		is_equal_approx(SpellTargets.hit_margin(big),
			SpellTargets.hit_margin(plain) * DUMMY_SCALE),
		"the forgiveness ring scales with the figure (%.3f vs %.3f x %.1f)"
			% [SpellTargets.hit_margin(big), SpellTargets.hit_margin(plain), DUMMY_SCALE])
	# ...and it is still not a free hit from anywhere: well clear is still a miss.
	_expect(SpellTargets.in_radius(Vector2(0.0, 7400.0 - 140.0), 40.0, [big]).is_empty(),
		"a shot sailing well over the big dummy still misses")
	await _free_all([plain, big])
	_completes("scale_awareness")


# --------------------------------------------------------------- line of sight

## BUG 2. A target inside the radius but BEHIND a wall must be dropped — "the spells
## shouldn't be able to get out the radius", in its through-walls form.
func _test_behind_a_wall_is_not_hit() -> void:
	var w: StaticBody2D = _wall(Vector2(100.0, 8000.0))     # spans x 80..120
	var behind: Silhouette = _figure(Vector2(200.0, 8000.0))
	var open: Silhouette = _figure(Vector2(0.0, 8150.0))
	await physics_frame
	var centre := Vector2(0.0, 8000.0)
	# Control: with a big enough radius, BOTH are geometrically in range.
	var no_los: Array = SpellTargets.in_radius(centre, 400.0, [behind, open], [], null, false)
	_expect(no_los.size() == 2,
		"control: both targets are inside the radius (%d)" % no_los.size())
	var got: Array = SpellTargets.in_radius(centre, 400.0, [behind, open])
	_expect(got.size() == 1 and got[0] == open,
		"the target behind the wall is dropped, the one in the open is kept (%d results)"
			% got.size())
	await _free_all([w, behind, open])
	_completes("behind_a_wall_is_not_hit")


## The opt-out still works, for the spells whose fiction ignores geometry
## (ShadowCrawler passes UNDER walls). If this ever stops working, those spells
## silently lose half their targets.
func _test_los_opt_out_hits_through_the_wall() -> void:
	var w: StaticBody2D = _wall(Vector2(100.0, 9000.0))
	var behind: Silhouette = _figure(Vector2(200.0, 9000.0))
	await physics_frame
	var centre := Vector2(0.0, 9000.0)
	_expect(SpellTargets.in_radius(centre, 400.0, [behind]).is_empty(),
		"control: LOS on, the wall blocks")
	_expect(
		SpellTargets.in_radius(centre, 400.0, [behind], [], null, false).size() == 1,
		"require_los = false reaches through the wall (the documented opt-out)")
	await _free_all([w, behind])
	_completes("los_opt_out_hits_through_the_wall")


# ----------------------------------------------------------------- pool guards

## A spell must not damage whoever cast it. `skip` removes the node from the results
## AND from the LOS rays.
func _test_caster_is_excluded() -> void:
	var caster: Silhouette = _figure(Vector2(0.0, 10000.0))
	var victim: Silhouette = _figure(Vector2(30.0, 10000.0))
	await physics_frame
	var centre := Vector2(0.0, 10000.0)
	var both: Array = SpellTargets.in_radius(centre, 200.0, [caster, victim])
	_expect(both.size() == 2, "control: both are in range (%d)" % both.size())
	var got: Array = SpellTargets.in_radius(centre, 200.0, [caster, victim], [caster])
	_expect(got.size() == 1 and got[0] == victim,
		"the caster is excluded, everyone else still resolves (%d results)" % got.size())
	# A skip entry that is not even in the candidate list is harmless.
	var stray := Node2D.new()
	root.add_child(stray)
	_expect(
		SpellTargets.in_radius(centre, 200.0, [caster, victim], [stray]).size() == 2,
		"a skip entry that is not a candidate changes nothing")
	await _free_all([caster, victim, stray])
	_completes("caster_is_excluded")


## A crate that collapsed earlier THIS frame is still in its group until the
## deferred free lands. Damaging it again is a wasted hit at best and a second death
## spectacle at worst. Note the deliberate absence of an await after queue_free():
## that reproduces the real same-frame timing.
func _test_queued_for_deletion_never_appears() -> void:
	var doomed: Silhouette = _figure(Vector2(0.0, 11000.0))
	var live: Silhouette = _figure(Vector2(20.0, 11000.0))
	await physics_frame
	var centre := Vector2(0.0, 11000.0)
	_expect(SpellTargets.in_radius(centre, 200.0, [doomed, live]).size() == 2,
		"control: both are hittable before the free")
	doomed.queue_free()
	_expect(doomed.is_queued_for_deletion(),
		"regression: the node IS queued for deletion")
	var got: Array = SpellTargets.in_radius(centre, 200.0, [doomed, live])
	_expect(got.size() == 1 and got[0] == live,
		"a queued-for-deletion target is never in the results (%d)" % got.size())
	# Nulls in the list must not throw either — group arrays get stale.
	_expect(SpellTargets.in_radius(centre, 200.0, [null, live]).size() == 1,
		"a null entry is skipped rather than throwing")
	await _free_all([live])
	_completes("queued_for_deletion_never_appears")


## Every selector needs a world position; a non-Node2D has none. Silently dropping
## it matches what every hand-rolled loop already did (`if not n is Node2D: continue`).
func _test_non_node2d_is_dropped() -> void:
	var plain_node := Node.new()  # no transform at all
	root.add_child(plain_node)
	var live: Silhouette = _figure(Vector2(0.0, 12000.0))
	await physics_frame
	var got: Array = SpellTargets.in_radius(Vector2(0.0, 12000.0), 200.0, [plain_node, live])
	_expect(got.size() == 1 and got[0] == live,
		"a positionless node is dropped, not crashed on (%d results)" % got.size())
	await _free_all([plain_node, live])
	_completes("non_node2d_is_dropped")


# --------------------------------------------------------------------- on_line

## BUG 1 IN ITS BEAM FORM. A corridor fired at HEAD height passes ~10 px above the
## origin every old `targets_on_line` tested, so a narrow beam aimed squarely at a
## head registered nothing. The control asserts the old maths really did miss.
func _test_on_line_catches_a_head_height_beam() -> void:
	var f: Silhouette = _figure(Vector2(200.0, 13000.0))
	await physics_frame
	var head: Vector2 = SpellTargets.aim_point(f)
	var origin := Vector2(0.0, head.y)      # a beam fired along head height
	var dir := Vector2.RIGHT
	var half: float = 2.0                   # deliberately narrower than the head rise
	_expect(
		SpellTargets.on_line(origin, dir, 400.0, half, [f]).size() == 1,
		"a head-height beam hits the head")
	# The control: the old corridor test, verbatim, against the ORIGIN only.
	var rel: Vector2 = f.global_position - origin
	var old_hit: bool = rel.dot(dir) >= 0.0 and rel.dot(dir) <= 400.0 \
		and absf(rel.dot(dir.orthogonal())) <= half
	_expect(not old_hit,
		"control: the old origin-only corridor test MISSES the same beam")
	# A beam at body height still works — the head probe did not replace the spine.
	_expect(
		SpellTargets.on_line(Vector2(0.0, 13000.0), dir, 400.0, half, [f]).size() == 1,
		"a body-height beam still hits the spine")
	await _free_all([f])
	_completes("on_line_catches_a_head_height_beam")


## The negative half: a beam clearly OVER the head misses, a beam that stops SHORT
## misses, and a beam pointing the other way misses.
func _test_on_line_misses_over_the_head_and_past_the_tip() -> void:
	var f: Silhouette = _figure(Vector2(200.0, 14000.0))
	await physics_frame
	var half: float = 2.0
	_expect(
		SpellTargets.on_line(Vector2(0.0, 14000.0 - 60.0), Vector2.RIGHT, 400.0, half, [f]).is_empty(),
		"a beam sailing well over the head misses")
	_expect(
		SpellTargets.on_line(Vector2(0.0, 14000.0 + 60.0), Vector2.RIGHT, 400.0, half, [f]).is_empty(),
		"a beam passing under the feet misses")
	_expect(
		SpellTargets.on_line(Vector2(0.0, 14000.0), Vector2.RIGHT, 100.0, half, [f]).is_empty(),
		"a beam that stops short of the target misses")
	_expect(
		SpellTargets.on_line(Vector2(0.0, 14000.0), Vector2.LEFT, 400.0, half, [f]).is_empty(),
		"a beam fired the other way misses (the corridor is not a full line)")
	# A zero direction must not silently become a hit-everything wildcard.
	_expect(
		SpellTargets.on_line(Vector2(0.0, 14000.0), Vector2.ZERO, 0.0, half, [f]).is_empty(),
		"a degenerate zero-length beam hits nothing")
	await _free_all([f])
	_completes("on_line_misses_over_the_head_and_past_the_tip")


## A beam is stopped by cover too — the same LOS default as in_radius, cast from the
## MUZZLE (which is what SpellWorld.clip already shortens the drawn beam against).
func _test_on_line_respects_cover() -> void:
	var w: StaticBody2D = _wall(Vector2(100.0, 15000.0))
	var behind: Silhouette = _figure(Vector2(200.0, 15000.0))
	await physics_frame
	var origin := Vector2(0.0, 15000.0)
	_expect(
		SpellTargets.on_line(origin, Vector2.RIGHT, 400.0, 8.0, [behind], [], null, false).size() == 1,
		"control: geometrically the corridor covers the target")
	_expect(
		SpellTargets.on_line(origin, Vector2.RIGHT, 400.0, 8.0, [behind]).is_empty(),
		"the wall stops the beam's damage as well as its drawing")
	await _free_all([w, behind])
	_completes("on_line_respects_cover")


# ---------------------------------------------------------------------- cone

## Hero's melee wedge: in front + within reach hits; behind misses; in front but out
## of reach misses. The negatives are the point — a cone that catches what is behind
## you is a punch that lands backwards.
func _test_in_cone() -> void:
	var front: Silhouette = _figure(Vector2(30.0, 16000.0))
	var back: Silhouette = _figure(Vector2(-30.0, 16000.0))
	var far: Silhouette = _figure(Vector2(300.0, 16000.0))
	await physics_frame
	var apex := Vector2(0.0, 16000.0)
	var got: Array = SpellTargets.in_cone(apex, Vector2.RIGHT, 60.0, 0.3,
		[front, back, far])
	_expect(got.size() == 1 and got[0] == front,
		"only the target in front and in reach is hit (%d results)" % got.size())
	# Widening the arc past a half-plane lets the one behind you in too — the sanity
	# anchor that the wedge is an arc and not a hardcoded hemisphere.
	_expect(
		SpellTargets.in_cone(apex, Vector2.RIGHT, 60.0, -1.1, [front, back, far]).size() == 2,
		"a full-circle arc degenerates to a radius test (both near targets)")
	# ⚠ THE BOUNDARY IS STRICT (`dot > min_dot`), matching Hero's shipped melee test.
	# min_dot = -1.0 therefore admits everything EXCEPT the exactly-opposite target,
	# and min_dot = 0.0 excludes a target at exactly 90 degrees. Asserted rather than
	# assumed because flipping either to `>=` would widen every swing in the game.
	_expect(
		SpellTargets.in_cone(apex, Vector2.RIGHT, 60.0, -1.0, [back]).is_empty(),
		"min_dot = -1.0 still excludes a target standing exactly opposite (strict >)")
	var side: Silhouette = _figure(Vector2(0.0, 16000.0 - 30.0))
	await physics_frame
	_expect(
		SpellTargets.in_cone(apex, Vector2.RIGHT, 60.0, 0.0, [side]).is_empty(),
		"min_dot = 0.0 excludes a target at exactly 90 degrees (strict >)")
	# A target standing exactly on the apex has no direction and always counts.
	var onto: Silhouette = _figure(apex)
	await physics_frame
	_expect(
		SpellTargets.in_cone(apex, Vector2.RIGHT, 60.0, 0.99, [onto]).size() == 1,
		"a target standing on top of you is always in the arc")
	await _free_all([front, back, far, side, onto])
	_completes("in_cone")


# ------------------------------------------------------------ nearest / ordering

func _test_nearest() -> void:
	var near: Silhouette = _figure(Vector2(20.0, 17000.0))
	var mid: Silhouette = _figure(Vector2(80.0, 17000.0))
	await physics_frame
	var at := Vector2(0.0, 17000.0)
	_expect(SpellTargets.nearest(at, 300.0, [mid, near]) == near,
		"nearest picks the closest silhouette regardless of input order")
	_expect(SpellTargets.nearest(at, 5.0, [mid, near]) == null,
		"nearest returns null when nothing is in reach")
	_expect(SpellTargets.nearest(at, 300.0, [mid, near], [near]) == mid,
		"nearest honours the skip list")
	await _free_all([near, mid])
	_completes("nearest")


## Deterministic hop order is what keeps ChainBolt.build_chain a testable pure
## selector. Equal distances must keep INPUT order — Array.sort_custom is not stable
## on its own, so this asserts the index tiebreak actually works.
## Note the fixtures are PLAIN nodes, not silhouettes. A drawn body is vertically
## ASYMMETRIC (the head sits above the origin, the hip below), so two figures placed
## equally far above and below a probe point are NOT equidistant — the tie this test
## needs would never actually occur. That asymmetry is correct behaviour, and
## discovering it here is exactly why the tie fixture has to be a point target.
func _test_sorted_by_distance_is_stable() -> void:
	var a: Node2D = _plain(Vector2(0.0, 18100.0))   # equidistant with b
	var b: Node2D = _plain(Vector2(0.0, 17900.0))   # equidistant with a
	var close: Node2D = _plain(Vector2(10.0, 18000.0))
	await physics_frame
	var at := Vector2(0.0, 18000.0)
	var order: Array = SpellTargets.sorted_by_distance(at, [a, b, close])
	_expect(order.size() == 3 and order[0] == close,
		"nearest first")
	var again: Array = SpellTargets.sorted_by_distance(at, [a, b, close])
	_expect(order == again, "the same input always yields the same order")
	# Ties keep input order both ways round, which is the actual stability claim.
	var ab: Array = SpellTargets.sorted_by_distance(at, [a, b])
	var ba: Array = SpellTargets.sorted_by_distance(at, [b, a])
	_expect(ab.size() == 2 and ba.size() == 2 and ab[0] == a and ba[0] == b,
		"equal distances keep their input order (stable sort)")
	await _free_all([a, b, close])
	_completes("sorted_by_distance_is_stable")
