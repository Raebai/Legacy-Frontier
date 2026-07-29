# Run: godot --headless --path godot-project --script tools/slice_test_impact_spells.gd
#
# The four spectacles that resolve damage as an IMPACT rather than a persistent
# shape — RockPillar, BoulderHurl, BlastSpell and the basic bolt (Spell.gd) —
# against the world contract in docs/spell-world-contract.md.
#
# THIS SUITE EXISTS FOR THE MAKER'S #1 OUTSTANDING BUG:
#   "No spell may pass through geometry. Meteors currently fall THROUGH the
#    floor; nothing may end up below or inside the environment. A spell that
#    meets a wall, the ground, or cover should IMPACT there — and destroy what
#    it can."
# and its companion, which is what most of the assertions below are really about:
#   "the spells shouldn't be able to get out the radius"
#
# ⚠ THE NEGATIVE CASES ARE THE POINT. A change that made everything hit would
# pass every "the head registers" assertion in this file. The only thing between
# these fixes and a stealth hitbox inflation across four spells is the block of
# tests that assert what must NOT be hit: outside the drawn extent, behind cover,
# below the floor, and — the headline — beside the pillar's fang. Do not weaken
# those to make a feel tweak land.
#
# ⚠ THE ONE THAT MATTERS MOST is _test_pillar_does_not_reach_through_the_floor().
# RockPillar used to damage a 66 px CIRCLE around its ground mark while drawing a
# 46 px-wide fang, so 66 px of that circle pointed straight DOWN THROUGH THE
# FLOOR and uppercut anything standing in the room below. Do not delete it.
#
# Uses a REAL physics space (extends SceneTree + await physics_frame, the
# slice_test_spell_world / slice_test_spell_targets idiom) because every fix under
# test is a world query — a synchronous harness would only ever prove the
# degrade-to-no-hit path.
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
## ⚠ EVERY NEGATIVE TEST IS LISTED HERE, and that is the whole reason this array
## is worth the maintenance. A negative test aborting part-way is invisible
## otherwise: nothing was hit, so nothing failed, so a suite that skipped it
## reports the same "all PASS" as a suite that ran it. Absence from `_completed`
## is what turns "I never checked" into a failure.
const TESTS: Array[String] = [
	"pillar_stands_on_the_floor",
	"pillar_over_a_pit_does_not_erupt",
	"pillar_is_clipped_by_a_ceiling",
	"pillar_damages_its_own_fang",
	"pillar_misses_beside_the_fang",                 # NEGATIVE
	"pillar_does_not_reach_through_the_floor",       # NEGATIVE (the headline)
	"pillar_registers_a_head",
	"pillar_does_not_reach_above_a_slab",            # NEGATIVE
	"pillar_smashes_cover_in_its_column",
	"pillar_is_deflectable",
	"boulder_rips_from_the_floor",
	"boulder_stops_at_a_wall",
	"boulder_smashes_through_a_crate",
	"boulder_flight_reach_is_the_drawn_radius",      # NEGATIVE
	"boulder_blast_respects_cover",                  # NEGATIVE
	"boulder_blast_boundary",                        # NEGATIVE
	"boulder_registers_a_head",
	"boulder_is_deflectable",
	"boulder_reflect_turns_it_around",
	"blast_damages_in_radius",
	"blast_boundary",                                # NEGATIVE
	"blast_respects_cover",                          # NEGATIVE
	"blast_registers_a_head",
	"blast_drawn_extent_tracks_the_damage_radius",
	"blast_is_deflectable",
	"blast_visual_twin_does_no_damage",
	"bolt_ghost_rule",
	"bolt_stops_at_a_wall",
	"bolt_steps_past_a_ghost",                       # regression guard
	"bolt_chain_respects_cover",                     # NEGATIVE
	"bolt_chain_hops_to_a_head",
	"bolt_reflect_grace_and_turn",
]

var _fails: int = 0
var _completed: Dictionary = {}

## Each band of tests lives thousands of px from every other so one band's
## leftover bodies can never satisfy another's ray or radius.
const TOL: float = 2.0

const PILLAR_SCRIPT: String = "res://scripts/combat/RockPillar.gd"
const BOULDER_SCRIPT: String = "res://scripts/combat/BoulderHurl.gd"
const BLAST_SCRIPT: String = "res://scripts/combat/BlastSpell.gd"
const BOLT_SCENE: String = "res://scenes/combat/Spell.tscn"


## A plain point target: no silhouette, no forgiveness ring. Per SpellTargets'
## contract this resolves BYTE-IDENTICALLY to the old
## `center.distance_to(global_position) <= radius`, which is what makes the
## boundary assertions below exact rather than approximate.
class Victim extends Node2D:
	var damage_calls: Array[int] = []
	var knockback: Vector2 = Vector2.ZERO
	var statuses: Array[int] = []

	func take_damage(amount: int) -> void:
		damage_calls.append(amount)

	func apply_knockback(v: Vector2) -> void:
		knockback += v

	func apply_status(id: int, _fresh: bool = true) -> void:
		statuses.append(id)


## A victim holding a parry. SpellDeflect is duck-typed, so this is the whole
## contract: `is_parrying` plus the optional recorder.
class GuardVictim extends Victim:
	var deflected: int = 0

	func is_parrying() -> bool:
		return true

	func on_spell_deflected(_dir: Vector2) -> void:
		deflected += 1


## A target that DRAWS a body — spine segment + head circle — publishing the same
## three duck-typed methods `Enemy` does, by the same formulas. Mirrors the stub
## in slice_test_spell_targets.gd (constants live INSIDE the inner class because
## inner classes do not reliably see the outer script's constant scope).
class Silhouette extends Victim:
	const RIG_H: float = 31.0
	const HEAD_R_FACTOR: float = 0.18
	const HIP_Y_FACTOR: float = 0.1
	const MARGIN_FACTOR: float = 0.12

	func _sil() -> Dictionary:
		var head_r: float = RIG_H * HEAD_R_FACTOR
		var head_local := Vector2(0.0, -RIG_H * 0.5 + head_r)
		var xf: Transform2D = global_transform
		var s: float = absf(xf.get_scale().y)
		return {
			"neck": xf * (head_local + Vector2(0.0, head_r)),
			"hip": xf * Vector2(0.0, RIG_H * HIP_Y_FACTOR),
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
		return RIG_H * MARGIN_FACTOR * float(_sil()["scale"])

	func head_point() -> Vector2:
		return _sil()["head"] as Vector2


## Destructible cover that records the localized hit, so "smashed THROUGH, not
## stopped" can be asserted rather than assumed.
class Crate extends StaticBody2D:
	var damage_calls: Array[int] = []

	func damage_at(amount: int, _at: Vector2, _dir: Vector2) -> void:
		damage_calls.append(amount)

	func take_damage(amount: int) -> void:
		damage_calls.append(amount)


func _initialize() -> void:
	_run()  # fire-and-forget: awaits inside, quits when done


func _run() -> void:
	# --- RockPillar: the file with the known lie
	await _test_pillar_stands_on_the_floor()
	await _test_pillar_over_a_pit_does_not_erupt()
	await _test_pillar_is_clipped_by_a_ceiling()
	await _test_pillar_damages_its_own_fang()
	await _test_pillar_misses_beside_the_fang()                     # NEGATIVE
	await _test_pillar_does_not_reach_through_the_floor()           # NEGATIVE (the headline)
	await _test_pillar_registers_a_head()
	await _test_pillar_does_not_reach_above_a_slab()                # NEGATIVE
	await _test_pillar_smashes_cover_in_its_column()
	await _test_pillar_is_deflectable()
	# --- BoulderHurl
	await _test_boulder_rips_from_the_floor()
	await _test_boulder_stops_at_a_wall()
	await _test_boulder_smashes_through_a_crate()
	await _test_boulder_flight_reach_is_the_drawn_radius()          # NEGATIVE
	await _test_boulder_blast_respects_cover()                      # NEGATIVE
	await _test_boulder_blast_boundary()                            # NEGATIVE
	await _test_boulder_registers_a_head()
	await _test_boulder_is_deflectable()
	await _test_boulder_reflect_turns_it_around()
	# --- BlastSpell
	await _test_blast_damages_in_radius()
	await _test_blast_boundary()                                    # NEGATIVE
	await _test_blast_respects_cover()                              # NEGATIVE
	await _test_blast_registers_a_head()
	await _test_blast_drawn_extent_tracks_the_damage_radius()
	await _test_blast_is_deflectable()
	await _test_blast_visual_twin_does_no_damage()
	# --- Spell (the bolt)
	_test_bolt_ghost_rule()
	await _test_bolt_stops_at_a_wall()
	await _test_bolt_steps_past_a_ghost()                           # regression guard
	await _test_bolt_chain_respects_cover()                         # NEGATIVE
	await _test_bolt_chain_hops_to_a_head()
	await _test_bolt_reflect_grace_and_turn()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Impact spell tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Impact spell tests: all PASS")
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

## Plain solid world geometry: StaticBody2D on collision_layer 1, no group.
func _wall(at: Vector2, size: Vector2 = Vector2(40.0, 40.0)) -> StaticBody2D:
	var body := StaticBody2D.new()
	_shape_onto(body, size)
	root.add_child(body)
	body.global_position = at
	return body


## Destructible cover, matching DestructibleTerrain: collision_layer 5 (bits 1+4,
## so a mask-1 ray sees it) AND group "destructible", so it is smashed through.
func _crate(at: Vector2, size: Vector2 = Vector2(40.0, 40.0)) -> Crate:
	var body := Crate.new()
	_shape_onto(body, size)
	body.collision_layer = 5
	body.add_to_group("destructible")
	root.add_child(body)
	body.global_position = at
	return body


func _shape_onto(body: CollisionObject2D, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)


func _victim(at: Vector2, group: String = "enemy") -> Victim:
	var v := Victim.new()
	v.add_to_group(group)
	root.add_child(v)
	v.global_position = at
	return v


func _guard(at: Vector2, group: String = "enemy") -> GuardVictim:
	var v := GuardVictim.new()
	v.add_to_group(group)
	root.add_child(v)
	v.global_position = at
	return v


func _silhouette(at: Vector2, group: String = "enemy") -> Silhouette:
	var v := Silhouette.new()
	v.add_to_group(group)
	root.add_child(v)
	v.global_position = at
	return v


## Erupt a pillar and stop its timeline immediately, so `_process` cannot apply
## the launch a second time behind the test's back.
func _pillar(mark: Vector2) -> Node2D:
	var p: Node2D = (load(PILLAR_SCRIPT) as GDScript).new()
	root.add_child(p)
	p.call("erupt", mark)
	p.set_process(false)
	return p


func _boulder(from: Vector2, aim: Vector2) -> Node2D:
	var b: Node2D = (load(BOULDER_SCRIPT) as GDScript).new()
	root.add_child(b)
	b.call("hurl", from, aim)
	b.set_process(false)
	return b


func _blast(at: Vector2, opts: Dictionary = {}) -> Node2D:
	var b: Node2D = (load(BLAST_SCRIPT) as GDScript).new()
	root.add_child(b)
	if not opts.is_empty():
		b.call("configure", opts)
	b.global_position = at
	return b


func _cleanup(nodes: Array) -> void:
	for n: Variant in nodes:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	# SpellDeflect's payoff drives Juice.hit_stop, which parks Engine.time_scale
	# at 0.05 until its own real-time timer restores it. A suite that left it
	# there would hand every later test a 20x-slowed delta.
	Engine.time_scale = 1.0
	await physics_frame
	await physics_frame


# ================================================================== RockPillar
# Band y ~ 0 .. 3000

## The fang stands on the FLOOR under the mark, not at the mark's own y. An aim
## point is a cursor position and lands in mid-air as often as not.
func _test_pillar_stands_on_the_floor() -> void:
	var ground: StaticBody2D = _wall(Vector2(0.0, 200.0), Vector2(400.0, 40.0))  # top y=180
	await physics_frame
	var p: Node2D = _pillar(Vector2(0.0, 60.0))  # marked 120 px ABOVE the floor
	_expect(absf(float((p.get("_ground") as Vector2).y) - 180.0) < TOL,
		"pillar: base snaps to the floor surface y=180 (got %s)" % (p.get("_ground") as Vector2).y)
	_expect(absf(float((p.get("_ground") as Vector2).x)) < TOL,
		"pillar: x is unchanged by the floor probe")
	await _cleanup([p, ground])
	_completes("pillar_stands_on_the_floor")


## Over a pit there is nothing to erupt from, and dropping the fang to the end of
## the probe would plant it in the void — the exact bug the contract exists for.
func _test_pillar_over_a_pit_does_not_erupt() -> void:
	await physics_frame
	var p: Node2D = _pillar(Vector2(24000.0, 24000.0))
	_expect(p.is_queued_for_deletion(), "pillar over a pit frees itself")
	_expect(float(p.get("_elapsed")) < 0.0, "pillar over a pit never starts its timeline")
	await _cleanup([p])
	_completes("pillar_over_a_pit_does_not_erupt")


## The fang GROWS upward, so it is a travelling thing: a ledge above it stops it
## there instead of letting stone grow through solid rock.
func _test_pillar_is_clipped_by_a_ceiling() -> void:
	var ground: StaticBody2D = _wall(Vector2(0.0, 1200.0), Vector2(400.0, 40.0))   # top y=1180
	var ceiling: StaticBody2D = _wall(Vector2(0.0, 1100.0), Vector2(400.0, 20.0))  # bottom y=1110
	await physics_frame
	var p: Node2D = _pillar(Vector2(0.0, 1150.0))
	# 1180 -> 1110 is 70 px of clearance; the fang's natural height is 150.
	_expect(absf(float(p.get("_height")) - 70.0) < TOL,
		"pillar: fang height clipped to the ceiling (expected ~70, got %s)" % p.get("_height"))
	await _cleanup([p, ground, ceiling])
	_completes("pillar_is_clipped_by_a_ceiling")


func _test_pillar_damages_its_own_fang() -> void:
	var ground: StaticBody2D = _wall(Vector2(0.0, 2000.0), Vector2(400.0, 40.0))  # top y=1980
	await physics_frame
	var at_base: Victim = _victim(Vector2(0.0, 1975.0))       # standing on the mark
	var up_column: Victim = _victim(Vector2(10.0, 1900.0))    # 80 px up, inside the fang
	var p: Node2D = _pillar(Vector2(0.0, 1970.0))
	p.call("_apply_launch")
	_expect(at_base.damage_calls.size() == 1,
		"pillar: a body standing in the footprint is hit (got %s)" % at_base.damage_calls.size())
	_expect(up_column.damage_calls.size() == 1,
		"pillar: a body ALREADY AIRBORNE over the mark is hit — the 150 px column is the shape")
	_expect(at_base.knockback.y < 0.0, "pillar: the launch is UPWARD")
	await _cleanup([p, at_base, up_column, ground])
	_completes("pillar_damages_its_own_fang")


## ⚠ NEGATIVE. The pillar used to damage a 66 px circle while drawing a 23 px
## half-width fang. A body a clear 40 px to the side is OUTSIDE the picture and
## must now take nothing — that reduction is the balance change, stated plainly.
func _test_pillar_misses_beside_the_fang() -> void:
	var ground: StaticBody2D = _wall(Vector2(0.0, 2300.0), Vector2(600.0, 40.0))  # top y=2280
	await physics_frame
	var inside: Victim = _victim(Vector2(20.0, 2275.0))    # within the 23 px half-width
	var outside: Victim = _victim(Vector2(40.0, 2275.0))   # beyond it, inside the OLD 66 px
	var p: Node2D = _pillar(Vector2(0.0, 2270.0))
	p.call("_apply_launch")
	_expect(inside.damage_calls.size() == 1, "pillar: 20 px off-centre is inside the fang")
	_expect(outside.damage_calls.is_empty(),
		"pillar NEGATIVE: 40 px off-centre takes ZERO — the drawn fang is 23 px half-width, " +
		"and the old 66 px circle was 2.9x the picture")
	await _cleanup([p, inside, outside, ground])
	_completes("pillar_misses_beside_the_fang")


## ⚠ NEGATIVE, AND THE HEADLINE. The old 66 px circle pointed DOWN as well as
## sideways, so anything standing in the room below the floor was uppercut
## through solid ground. The fang capsule has no downward extent at all.
func _test_pillar_does_not_reach_through_the_floor() -> void:
	var ground: StaticBody2D = _wall(Vector2(0.0, 2600.0), Vector2(600.0, 40.0))  # spans y 2580..2620
	await physics_frame
	# 30 px BELOW the floor surface: comfortably inside the old 66 px circle.
	var below: Victim = _victim(Vector2(0.0, 2650.0))
	var p: Node2D = _pillar(Vector2(0.0, 2570.0))
	p.call("_apply_launch")
	_expect(absf(float((p.get("_ground") as Vector2).y) - 2580.0) < TOL,
		"pillar: base is on the floor surface, so the test is measuring what it thinks")
	_expect(below.damage_calls.is_empty(),
		"pillar NEGATIVE: a body 30 px UNDER the floor takes ZERO — no uppercut through solid rock")
	await _cleanup([p, below, ground])
	_completes("pillar_does_not_reach_through_the_floor")


## Bug 1 (heads): the drawn head sits ~10 px ABOVE the node origin, and the old
## point test could not see it. A silhouette standing beside the fang at head
## height now registers via its body, not its origin.
func _test_pillar_registers_a_head() -> void:
	var ground: StaticBody2D = _wall(Vector2(0.0, 2900.0), Vector2(600.0, 40.0))  # top y=2880
	await physics_frame
	# Origin 29 px off-centre. An ORIGIN test needs <= 23 (half-width) + 3.72 (the
	# body's own margin) = 26.72, so 29 misses; the drawn HEAD circle reaches
	# 5.58 px closer than the origin does, which brings it inside. That gap is the
	# whole of Bug 1, measured.
	var s: Silhouette = _silhouette(Vector2(29.0, 2875.0))
	var p: Node2D = _pillar(Vector2(0.0, 2870.0))
	p.call("_apply_launch")
	_expect(s.damage_calls.size() == 1,
		"pillar: a drawn body whose ORIGIN is outside the fang still registers via its silhouette")
	await _cleanup([p, s, ground])
	_completes("pillar_registers_a_head")


## ⚠ NEGATIVE. Nothing standing above solid rock is uppercut through it.
##
## For a NARROW VERTICAL effect the ceiling clip and the line-of-sight cull are
## the same guarantee seen twice — anything that would block the fang's view of a
## victim directly above it is also something the fang stops growing at. So this
## asserts the guarantee rather than one mechanism: a body on the far side of a
## slab takes nothing, and the fang is short.
func _test_pillar_does_not_reach_above_a_slab() -> void:
	var ground: StaticBody2D = _wall(Vector2(5000.0, 200.0), Vector2(600.0, 40.0))  # top y=180
	# A slab across the column at y=120 (spans y 112..128), between the fang's base
	# and the body above it.
	var cover: StaticBody2D = _wall(Vector2(5000.0, 120.0), Vector2(200.0, 16.0))
	await physics_frame
	var above: Victim = _victim(Vector2(5000.0, 100.0))  # just past the slab
	var p: Node2D = _pillar(Vector2(5000.0, 170.0))
	p.call("_apply_launch")
	_expect(float(p.get("_height")) < 60.0,
		"pillar: the fang stops at the slab rather than growing through it (height %s)"
			% p.get("_height"))
	_expect(above.damage_calls.is_empty(),
		"pillar NEGATIVE: a body on the far side of a solid slab takes ZERO")
	await _cleanup([p, above, cover, ground])
	_completes("pillar_does_not_reach_above_a_slab")


## "Destroy what it can": destructible cover in the fang's column is smashed
## THROUGH — the eruption damages it rather than being stopped dead by it.
func _test_pillar_smashes_cover_in_its_column() -> void:
	var ground: StaticBody2D = _wall(Vector2(6000.0, 200.0), Vector2(600.0, 40.0))  # top y=180
	var crate: Crate = _crate(Vector2(6000.0, 120.0), Vector2(40.0, 20.0))          # in the column
	await physics_frame
	var p: Node2D = _pillar(Vector2(6000.0, 170.0))
	_expect(not crate.damage_calls.is_empty(),
		"pillar: destructible cover overhead is smashed as the fang grows through it")
	_expect(float(p.get("_height")) > 40.0,
		"pillar: ...and the fang is NOT stopped by it (height %s)" % p.get("_height"))
	await _cleanup([p, crate, ground])
	_completes("pillar_smashes_cover_in_its_column")


## Every attack spell is deflectable. The fang does not travel, so it is the
## SpellDeflect.resolve flavour: a held guard EATS the uppercut entirely.
func _test_pillar_is_deflectable() -> void:
	var ground: StaticBody2D = _wall(Vector2(7000.0, 200.0), Vector2(600.0, 40.0))  # top y=180
	await physics_frame
	var g: GuardVictim = _guard(Vector2(7000.0, 175.0))
	var p: Node2D = _pillar(Vector2(7000.0, 170.0))
	p.call("_apply_launch")
	_expect(g.deflected == 1, "pillar: the guard is told it deflected")
	_expect(g.damage_calls.is_empty(),
		"pillar: a deflected uppercut deals the DEFLECTED amount, which is zero")
	_expect(g.knockback == Vector2.ZERO,
		"pillar: ...and a parried victim is not launched either")
	await _cleanup([p, g, ground])
	_completes("pillar_is_deflectable")


# ================================================================= BoulderHurl
# Band y ~ 8000 .. 11000

func _test_boulder_rips_from_the_floor() -> void:
	var ground: StaticBody2D = _wall(Vector2(8000.0, 200.0), Vector2(600.0, 40.0))  # top y=180
	await physics_frame
	var b: Node2D = _boulder(Vector2(8000.0, 60.0), Vector2.RIGHT)
	_expect(absf(float(b.get("_ground_y")) - 180.0) < TOL,
		"boulder: rips from the FLOOR under the caster (got %s)" % b.get("_ground_y"))
	await _cleanup([b, ground])
	_completes("boulder_rips_from_the_floor")


## The segment JUST TRAVELLED is raycast, so a 900 px/s rock cannot tunnel a
## 40 px wall, and the blast is staged at the wall rather than beyond it.
func _test_boulder_stops_at_a_wall() -> void:
	var w: StaticBody2D = _wall(Vector2(8400.0, 500.0))  # spans x 8380..8420
	await physics_frame
	var b: Node2D = _boulder(Vector2(8200.0, 500.0), Vector2.RIGHT)
	b.set("_prev_pos", Vector2(8300.0, 500.0))
	b.set("_pos", Vector2(8500.0, 500.0))  # a whole frame's travel straight through it
	var stopped: bool = b.call("_check_flight_collision")
	_expect(stopped, "boulder: the wall stops the flight")
	var hit: Vector2 = b.get("_hit_point")
	_expect(absf(hit.x - 8380.0) < TOL + 5.0,
		"boulder: impact at the wall's near face x~8380 (got %s)" % hit.x)
	await _cleanup([b, w])
	_completes("boulder_stops_at_a_wall")


## Cover is torn THROUGH by something this heavy, and comes back damaged rather
## than stopping the rock.
func _test_boulder_smashes_through_a_crate() -> void:
	var crate: Crate = _crate(Vector2(9000.0, 500.0))
	await physics_frame
	var b: Node2D = _boulder(Vector2(8800.0, 500.0), Vector2.RIGHT)
	b.set("_prev_pos", Vector2(8900.0, 500.0))
	b.set("_pos", Vector2(9100.0, 500.0))
	var stopped: bool = b.call("_check_flight_collision")
	_expect(not stopped, "boulder: a crate does NOT stop the rock")
	_expect(not crate.damage_calls.is_empty(),
		"boulder: ...and the crate it tore through takes the hit")
	await _cleanup([b, crate])
	_completes("boulder_smashes_through_a_crate")


## ⚠ NEGATIVE. The in-flight test was `BOULDER_R + HIT_PAD` = 40 px against a
## rock drawn at 26 — a call-site pad stacked on top of the target's own margin,
## which SpellTargets' stacking caveat forbids. The reach is now the drawn radius.
## Driven through the spell's OWN collision function, not through SpellTargets, so
## it is the shipping code path that is pinned.
func _test_boulder_flight_reach_is_the_drawn_radius() -> void:
	await physics_frame
	var pad: Victim = _victim(Vector2(9500.0, 535.0))  # 35 px — inside the DELETED 40 px pad
	var b: Node2D = _boulder(Vector2(9300.0, 500.0), Vector2.RIGHT)
	b.set("_prev_pos", Vector2(9500.0, 500.0))
	b.set("_pos", Vector2(9500.0, 500.0))
	_expect(not bool(b.call("_check_flight_collision")),
		"boulder NEGATIVE: a body 35 px from the rock does NOT stop it — inside the deleted " +
		"HIT_PAD, outside the 26 px rock that is actually drawn")
	# ...and the control, so the negative above cannot be passing because the
	# collision function is simply broken.
	var near: Victim = _victim(Vector2(9500.0, 480.0))  # 20 px — inside the drawn rock
	await physics_frame
	_expect(bool(b.call("_check_flight_collision")),
		"boulder: a body 20 px from the rock DOES stop it")
	_expect((b.get("_hit_point") as Vector2).distance_to(Vector2(9500.0, 500.0)) < TOL,
		"boulder: the blast is staged where the ROCK is, not where the victim is")
	await _cleanup([b, near, pad])
	_completes("boulder_flight_reach_is_the_drawn_radius")


## ⚠ NEGATIVE. The detonation must not reach round a wall.
func _test_boulder_blast_respects_cover() -> void:
	var w: StaticBody2D = _wall(Vector2(10000.0, 500.0))
	await physics_frame
	var behind: Victim = _victim(Vector2(10060.0, 500.0))  # wall between it and the blast
	var open: Victim = _victim(Vector2(9940.0, 500.0))     # clear line, same distance
	var b: Node2D = _boulder(Vector2(9700.0, 500.0), Vector2.RIGHT)
	b.call("_apply_impact_damage", Vector2(9940.0, 440.0))
	_expect(open.damage_calls.size() == 1, "boulder: the body in the open is hit")
	_expect(behind.damage_calls.is_empty(),
		"boulder NEGATIVE: a body behind a wall takes ZERO even though it is inside the radius")
	await _cleanup([b, behind, open, w])
	_completes("boulder_blast_respects_cover")


## ⚠ NEGATIVE. A point target has no forgiveness ring, so the blast boundary is
## exactly `_radius` — the same number the shockwave and boundary arc are drawn at.
func _test_boulder_blast_boundary() -> void:
	await physics_frame
	var inside: Victim = _victim(Vector2(10600.0 + 80.0, 500.0))
	var outside: Victim = _victim(Vector2(10600.0 + 90.0, 500.0))
	var b: Node2D = _boulder(Vector2(10400.0, 500.0), Vector2.RIGHT)
	b.call("_apply_impact_damage", Vector2(10600.0, 500.0))  # default radius 84
	_expect(inside.damage_calls.size() == 1, "boulder: 80 px from centre is inside 84")
	_expect(outside.damage_calls.is_empty(),
		"boulder NEGATIVE: 90 px from centre takes ZERO — nothing gets out of the radius")
	await _cleanup([b, inside, outside])
	_completes("boulder_blast_boundary")


func _test_boulder_registers_a_head() -> void:
	await physics_frame
	# Origin 92 px BELOW the blast. An origin test needs <= 84 + 3.72 = 87.72, so
	# it misses; the drawn head sits 9.92 px higher and reaches 76.5 px, well in.
	var s: Silhouette = _silhouette(Vector2(11000.0, 592.0))
	var b: Node2D = _boulder(Vector2(10900.0, 500.0), Vector2.RIGHT)
	b.call("_apply_impact_damage", Vector2(11000.0, 500.0))
	_expect(s.damage_calls.size() == 1,
		"boulder: a drawn body whose ORIGIN is outside the radius registers via its silhouette")
	await _cleanup([b, s])
	_completes("boulder_registers_a_head")


func _test_boulder_is_deflectable() -> void:
	await physics_frame
	var g: GuardVictim = _guard(Vector2(11500.0, 500.0))
	var b: Node2D = _boulder(Vector2(11300.0, 500.0), Vector2.RIGHT)
	b.call("_apply_impact_damage", Vector2(11500.0, 500.0))
	_expect(g.deflected == 1, "boulder: the guard is told it deflected the blast")
	_expect(g.damage_calls.is_empty(), "boulder: a deflected blast deals zero")
	await _cleanup([b, g])
	_completes("boulder_is_deflectable")


## The rock physically TRAVELS, so it takes the reflect() path: caught and sent
## back at whoever threw it. Clearing the caster and flipping the group is what
## turns a block into a counter-attack.
func _test_boulder_reflect_turns_it_around() -> void:
	await physics_frame
	var thrower: Victim = _victim(Vector2(11900.0, 500.0), "hero")
	var b: Node2D = _boulder(Vector2(11900.0, 500.0), Vector2.RIGHT)
	b.set("caster_node", thrower)
	_expect(b.is_in_group("deflectable_spell"),
		"boulder: advertises itself to the parry scans while in flight")
	_expect((b.call("deflect_point") as Vector2).distance_to(Vector2.ZERO) > 1.0,
		"boulder: deflect_point is the ROCK's world position, not the node's (0,0) origin")
	b.set("_flying", true)
	b.call("reflect", Vector2.LEFT, Color.WHITE)
	_expect(bool(b.get("_reflected")), "boulder: records that it was reflected")
	_expect((b.get("_dir") as Vector2).x < 0.0, "boulder: flies back the other way")
	_expect(String(b.get("target_group")) == "hero",
		"boulder: a caught rock now hunts the side that threw it")
	_expect(b.get("caster_node") == null,
		"boulder: ownership is severed, so the thrower is no longer immune to their own rock")
	await _cleanup([b, thrower])
	_completes("boulder_reflect_turns_it_around")


# ================================================================== BlastSpell
# Band y ~ 14000 .. 16000

func _test_blast_damages_in_radius() -> void:
	await physics_frame
	var v: Victim = _victim(Vector2(14060.0, 500.0))
	var b: Node2D = _blast(Vector2(14000.0, 500.0))
	b.call("_apply_blast_damage")
	_expect(v.damage_calls.size() == 1, "blast: a body inside the radius is hit once")
	_expect(v.knockback.x > 0.0, "blast: knocked outward (+x)")
	await _cleanup([b, v])
	_completes("blast_damages_in_radius")


## ⚠ NEGATIVE, and the CONFIGURED radius rather than the const: the Brawler's
## fire punch reconfigures this to 66 and must damage 66, not 92.
func _test_blast_boundary() -> void:
	await physics_frame
	var inside: Victim = _victim(Vector2(14560.0, 500.0))    # 60 px
	var outside: Victim = _victim(Vector2(14572.0, 500.0))   # 72 px
	var b: Node2D = _blast(Vector2(14500.0, 500.0), {"radius": 66.0})
	b.call("_apply_blast_damage")
	_expect(inside.damage_calls.size() == 1, "blast: 60 px is inside a 66 px blast")
	_expect(outside.damage_calls.is_empty(),
		"blast NEGATIVE: 72 px takes ZERO from a 66 px blast — the const 92 is not the reach")
	await _cleanup([b, inside, outside])
	_completes("blast_boundary")


## ⚠ NEGATIVE.
func _test_blast_respects_cover() -> void:
	var w: StaticBody2D = _wall(Vector2(15000.0, 500.0))
	await physics_frame
	var behind: Victim = _victim(Vector2(15060.0, 500.0))
	var open: Victim = _victim(Vector2(14940.0, 500.0))
	var b: Node2D = _blast(Vector2(14940.0, 440.0))
	b.call("_apply_blast_damage")
	_expect(open.damage_calls.size() == 1, "blast: the body in the open is hit")
	_expect(behind.damage_calls.is_empty(),
		"blast NEGATIVE: a body behind a wall takes ZERO")
	await _cleanup([b, behind, open, w])
	_completes("blast_respects_cover")


func _test_blast_registers_a_head() -> void:
	await physics_frame
	# Origin 103 px below the blast. An origin test needs <= 92 + 3.72 = 95.72, so
	# it misses; the drawn head reaches 87.5 px, inside.
	var s: Silhouette = _silhouette(Vector2(15500.0, 603.0))
	var b: Node2D = _blast(Vector2(15500.0, 500.0))           # default radius 92
	b.call("_apply_blast_damage")
	_expect(s.damage_calls.size() == 1,
		"blast: a drawn body whose ORIGIN is outside the radius registers via its silhouette")
	await _cleanup([b, s])
	_completes("blast_registers_a_head")


## The drawn extent and the damage extent are now ONE number. `reaction_shape()`
## is the honest proxy for the drawing: it is built from the same `radius` the
## shockwave, the boundary arc, the flash core and the crater all read.
func _test_blast_drawn_extent_tracks_the_damage_radius() -> void:
	await physics_frame
	var b: Node2D = _blast(Vector2(16000.0, 500.0), {"radius": 66.0})
	var shape: Dictionary = b.call("reaction_shape")
	_expect(absf(float(shape["radius"]) - 66.0) < 0.001,
		"blast: the drawn/reacted extent follows the CONFIGURED radius, not BLAST_RADIUS")
	_expect((shape["center"] as Vector2).distance_to(Vector2(16000.0, 500.0)) < TOL,
		"blast: ...centred where the blast actually is")
	await _cleanup([b])
	_completes("blast_drawn_extent_tracks_the_damage_radius")


func _test_blast_is_deflectable() -> void:
	await physics_frame
	var g: GuardVictim = _guard(Vector2(16500.0, 540.0))
	var b: Node2D = _blast(Vector2(16500.0, 500.0))
	b.call("_apply_blast_damage")
	_expect(g.deflected == 1, "blast: the guard is told it deflected")
	_expect(g.damage_calls.is_empty(), "blast: a deflected blast deals zero")
	_expect(g.knockback == Vector2.ZERO, "blast: ...and does not shove either")
	await _cleanup([b, g])
	_completes("blast_is_deflectable")


## Co-op: the client-side twin plays the spectacle and applies NO damage. Also
## the reason it stays out of the reaction registry.
func _test_blast_visual_twin_does_no_damage() -> void:
	await physics_frame
	var v: Victim = _victim(Vector2(17000.0, 520.0))
	var b: Node2D = _blast(Vector2(17000.0, 500.0), {"visual_only": true})
	b.call("_detonate")
	_expect(v.damage_calls.is_empty(), "blast: a visual-only twin applies no damage")
	await _cleanup([b, v])
	_completes("blast_visual_twin_does_no_damage")


# ======================================================================== bolt
# Band y ~ 20000 .. 22000

## The ghost rule, with no world involved. A bolt is not a boulder: LIVE cover is
## solid to it. Only a body that is already on its way out is stepped past.
func _test_bolt_ghost_rule() -> void:
	var script: GDScript = load("res://scripts/combat/Spell.gd") as GDScript
	var plain := Node2D.new()
	var crate := Node2D.new()
	crate.add_to_group("destructible")
	root.add_child(plain)
	root.add_child(crate)
	_expect(not bool(script.call("_is_ghost", plain)),
		"bolt: plain world geometry is NOT a ghost — it stops the bolt")
	_expect(not bool(script.call("_is_ghost", crate)),
		"bolt: LIVE destructible cover is NOT a ghost — a bolt stops on it and breaks it")
	plain.queue_free()
	_expect(bool(script.call("_is_ghost", plain)),
		"bolt: a queued-for-deletion collider IS a ghost — the bolt must not die on it")
	_expect(bool(script.call("_is_ghost", null)),
		"bolt: a freed collider is a ghost")
	crate.queue_free()
	_completes("bolt_ghost_rule")


func _test_bolt_stops_at_a_wall() -> void:
	var w: StaticBody2D = _wall(Vector2(20100.0, 500.0))  # spans x 20080..20120
	await physics_frame
	var bolt: Area2D = (load(BOLT_SCENE) as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.global_position = Vector2(20200.0, 500.0)
	var consumed: bool = bolt.call("_resolve_segment", Vector2(20000.0, 500.0))
	_expect(consumed, "bolt: a wall across the travelled segment consumes it")
	_expect(absf(bolt.global_position.x - 20080.0) < TOL,
		"bolt: snapped back to the wall's near face x~20080 (got %s)" % bolt.global_position.x)
	await _cleanup([bolt, w])
	_completes("bolt_stops_at_a_wall")


## ⚠ REGRESSION GUARD. A cover block that collapsed THIS frame leaves the
## "destructible" group immediately while its collider survives to the deferred
## free. A bolt that stops on it dies on nothing, one frame after breaking it.
##
## Note the deliberate absence of an `await` after queue_free(): that reproduces
## the real timing. The first assertion proves the collider is genuinely still in
## the space, so the second cannot pass vacuously.
func _test_bolt_steps_past_a_ghost() -> void:
	var collapsing: StaticBody2D = _wall(Vector2(21100.0, 500.0))  # NOT in the group
	await physics_frame
	var bolt: Area2D = (load(BOLT_SCENE) as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.global_position = Vector2(21200.0, 500.0)
	_expect(bool(SpellWorld.first_solid(
			Vector2(21000.0, 500.0), Vector2(21200.0, 500.0), [], null, false)["hit"]),
		"bolt regression: the collapsing body's collider is still live in the space")
	collapsing.queue_free()
	_expect(collapsing.is_queued_for_deletion(),
		"bolt regression: the body IS queued for deletion")
	var consumed: bool = bolt.call("_resolve_segment", Vector2(21000.0, 500.0))
	_expect(not consumed,
		"bolt regression: a queued-for-deletion collider is STEPPED PAST, not treated as a wall")
	_expect(absf(bolt.global_position.x - 21200.0) < TOL,
		"bolt regression: ...and the bolt keeps its position (got %s)" % bolt.global_position.x)
	await _cleanup([bolt])
	_completes("bolt_steps_past_a_ghost")


## ⚠ NEGATIVE. Lightning that jumps through solid rock is the "spells get out of
## the radius" bug wearing a nicer hat.
func _test_bolt_chain_respects_cover() -> void:
	var w: StaticBody2D = _wall(Vector2(22050.0, 500.0))
	await physics_frame
	var first: Victim = _victim(Vector2(22000.0, 500.0))
	var behind: Victim = _victim(Vector2(22110.0, 500.0))  # wall between it and `first`
	var open: Victim = _victim(Vector2(21900.0, 500.0))    # clear line, further away
	var bolt: Area2D = (load(BOLT_SCENE) as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.global_position = Vector2(22000.0, 500.0)
	bolt.set("chain_count", 1)
	bolt.set("damage", 20)
	bolt.call("_do_chain", first)
	_expect(behind.damage_calls.is_empty(),
		"bolt NEGATIVE: the chain does NOT arc through a wall to the nearer target")
	_expect(open.damage_calls.size() == 1,
		"bolt: ...it hops to the further target it can actually see")
	_expect(first.damage_calls.is_empty(),
		"bolt: the already-hit target is never chained to twice")
	await _cleanup([bolt, first, behind, open, w])
	_completes("bolt_chain_respects_cover")


func _test_bolt_chain_hops_to_a_head() -> void:
	await physics_frame
	var first: Victim = _victim(Vector2(23000.0, 500.0))
	# Origin 210 px away. An origin test needs <= CHAIN_RANGE 200 + 3.72 = 203.72,
	# so it misses; the drawn head reaches 194.5 px, inside.
	var s: Silhouette = _silhouette(Vector2(23000.0, 710.0))
	var bolt: Area2D = (load(BOLT_SCENE) as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.global_position = Vector2(23000.0, 500.0)
	bolt.set("chain_count", 1)
	bolt.set("damage", 20)
	bolt.call("_do_chain", first)
	_expect(s.damage_calls.size() == 1,
		"bolt: the chain measures to the DRAWN silhouette, so a body just past range by its " +
		"origin still registers")
	await _cleanup([bolt, first, s])
	_completes("bolt_chain_hops_to_a_head")


## The bolt travels, so it is caught and sent back rather than merely eaten — and
## it cannot be caught in the first instants, while it is still overlapping the
## body that fired it.
func _test_bolt_reflect_grace_and_turn() -> void:
	await physics_frame
	var thrower: Victim = _victim(Vector2(24000.0, 500.0), "hero")
	var bolt: Area2D = (load(BOLT_SCENE) as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.global_position = Vector2(24000.0, 500.0)
	bolt.call("launch", Vector2.RIGHT)
	bolt.set("caster", thrower)
	_expect(bolt.is_in_group("deflectable_spell"),
		"bolt: advertises itself to the parry scans")
	bolt.call("reflect", Vector2.LEFT, Color.WHITE)
	_expect(not bool(bolt.get("_reflected")),
		"bolt: cannot be caught inside REFLECT_GRACE — you may not parry your own muzzle")
	bolt.set("_age", 1.0)
	bolt.call("reflect", Vector2.LEFT, Color.WHITE)
	_expect(bool(bolt.get("_reflected")), "bolt: is caught once it is clear of the muzzle")
	_expect((bolt.get("_dir") as Vector2).x < 0.0, "bolt: flies back the other way")
	_expect(bolt.get("caster") == null,
		"bolt: ownership is severed, so a caught bolt can hit the person who threw it")
	await _cleanup([bolt, thrower])
	_completes("bolt_reflect_grace_and_turn")
