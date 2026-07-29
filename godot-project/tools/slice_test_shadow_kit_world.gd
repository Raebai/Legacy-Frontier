# Run: godot --headless --path godot-project --script tools/slice_test_shadow_kit_world.gd
#
# THE SHADOW KIT vs THE WORLD — RiftDagger, BlinkStrike, ShadowRoot, ShadowCrawler
# against the maker's #1 outstanding gameplay bug:
#
#   "No spell may pass through geometry. Meteors currently fall THROUGH the floor;
#    nothing may end up below or inside the environment. A spell that meets a wall,
#    the ground, or cover should IMPACT there — and destroy what it can."
#   "the spells shouldn't be able to get out the radius"
#
# THE TESTS THAT MATTER MOST ARE THE NEGATIVE ONES. Proving a spell hits is easy and
# nearly worthless; the whole point of this suite is that a body just outside the
# drawn extent, or behind a wall, takes EXACTLY ZERO. Every positive assertion below
# is paired with the negative that gives it meaning — delete a negative and the test
# beside it starts passing for the wrong reason.
#
# It also pins the two DELIBERATE EXEMPTIONS so a future consolidation pass cannot
# quietly "fix" them into blandness:
#   * ShadowCrawler still passes UNDER a wall  (_test_crawler_still_goes_under_walls)
#   * ShadowCrawler still dies in a pit        (_test_crawler_still_dies_in_a_pit)
#
# Uses a REAL physics space (extends SceneTree + `await physics_frame`, the
# slice_test_spell_world idiom) because every behaviour under test is a world query.
# The suite starts from _process rather than _initialize for the OTHER reason the
# blink suite documents: the spectacles reference the Sfx / Juice / CombatVfx
# autoloads, which are not registered until the main loop is up — so every script is
# `load()`ed by path at runtime and never named as a class here.
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
	"dagger_stops_at_a_wall",
	"dagger_plants_in_cover_and_damages_it",
	"dagger_burst_respects_cover_and_its_own_radius",
	"dagger_burst_registers_a_head_height_body",
	"dagger_arrival_is_never_inside_a_wall",
	"dagger_over_a_pit_is_lost_not_left_floating",
	"dagger_is_deflectable",
	"blink_blast_does_not_leak_through_a_wall",
	"blink_blast_is_deflectable",
	"root_surge_stops_at_a_wall",
	"root_lock_stops_at_the_lip_of_a_pit",
	"root_catch_window_is_what_is_drawn",
	"root_is_deflectable",
	"crawler_still_goes_under_walls",
	"crawler_still_dies_in_a_pit",
	"crawler_chews_cover_on_the_way_past",
	"crawler_catch_uses_the_targets_own_margin",
	"crawler_is_deflectable",
	"reaction_contract_is_complete_and_in_world_space",
]

var _fails: int = 0
var _completed: Dictionary = {}

const DAGGER_PATH: String = "res://scripts/combat/RiftDagger.gd"
const BLINK_PATH: String = "res://scripts/combat/BlinkStrike.gd"
const ROOT_PATH: String = "res://scripts/combat/ShadowRoot.gd"
const CRAWLER_PATH: String = "res://scripts/combat/ShadowCrawler.gd"

## px. Ray hit points land ON a surface, not exactly on the nominal coordinate.
const TOL: float = 3.0
## Fixed timestep used to drive every spectacle by hand. Small enough that a
## 780 px/s dagger moves ~16 px a step (comfortably under its 15 px hit radius plus
## the segment test), and deterministic, which real frames are not.
const STEP: float = 0.02
## Hard cap on manual steps, so a spell that never resolves fails the assertion
## instead of hanging the suite.
const MAX_STEPS: int = 400

var _started: bool = false


# ---------------------------------------------------------------------- fixtures

## Everything the spells duck-type against, INCLUDING the silhouette seam
## (`body_distance` / `hit_margin` / `head_point`) that SpellTargets uses — because
## "a head-height hit registers" is only testable against something that HAS a head.
## The body is a 20 px spine running UP from the origin, matching CharacterRig's
## real shape closely enough for the arithmetic to mean something.
class FakeEnemy:
	extends Node2D

	const SPINE: float = 20.0
	const MARGIN: float = 7.0     # ≈ what a 1.9x sparring dummy publishes

	var taken: int = 0
	var statuses: int = 0
	var shoves: Vector2 = Vector2.ZERO
	var guarding: bool = false

	func _ready() -> void:
		add_to_group("enemy")

	func take_damage(amount: int, _tint: Color = Color.WHITE) -> void:
		taken += amount

	func apply_status(_element_id: int) -> void:
		statuses += 1

	func apply_knockback(impulse: Vector2) -> void:
		shoves += impulse

	func head_point() -> Vector2:
		return global_position + Vector2(0.0, -SPINE)

	func hit_margin() -> float:
		return MARGIN

	func body_distance(p: Vector2) -> float:
		return SpellGeometry.closest_point_on_segment(
			p, global_position, head_point()).distance_to(p)

	# --- the SpellDeflect victim contract ---
	func is_parrying() -> bool:
		return guarding

	func parry_freshness() -> float:
		return 1.0


## A hero-flavoured FakeEnemy: same duck-typed surface, different group. Used for the
## reflected-dagger case, where the target group flips to "hero".
class FakeHero:
	extends FakeEnemy

	func _ready() -> void:
		add_to_group("hero")


## Breakable cover. A REAL StaticBody2D so the world queries see it, on collision
## layer 5 (bits 1+4, exactly like DestructibleTerrain) so a mask-1 ray finds it,
## and in the "destructible" group so SpellWorld's smash rule applies.
class FakeCrate:
	extends StaticBody2D

	var taken: int = 0
	var last_contact: Vector2 = Vector2.ZERO

	func take_damage(amount: int, _tint: Color = Color.WHITE) -> void:
		taken += amount

	func damage_at(amount: int, at: Vector2, _normal: Vector2) -> void:
		taken += amount
		last_contact = at


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()  # fire-and-forget: awaits inside, quits when done
	return false


func _run() -> void:
	# --- RiftDagger ---
	await _test_dagger_stops_at_a_wall()
	await _test_dagger_plants_in_cover_and_damages_it()
	await _test_dagger_burst_respects_cover_and_its_own_radius()
	await _test_dagger_burst_registers_a_head_height_body()
	await _test_dagger_arrival_is_never_inside_a_wall()
	await _test_dagger_over_a_pit_is_lost_not_left_floating()
	await _test_dagger_is_deflectable()
	# --- BlinkStrike ---
	await _test_blink_blast_does_not_leak_through_a_wall()
	await _test_blink_blast_is_deflectable()
	# --- ShadowRoot ---
	await _test_root_surge_stops_at_a_wall()
	await _test_root_lock_stops_at_the_lip_of_a_pit()
	await _test_root_catch_window_is_what_is_drawn()
	await _test_root_is_deflectable()
	# --- ShadowCrawler (the documented exceptions) ---
	await _test_crawler_still_goes_under_walls()
	await _test_crawler_still_dies_in_a_pit()
	await _test_crawler_chews_cover_on_the_way_past()
	await _test_crawler_catch_uses_the_targets_own_margin()
	await _test_crawler_is_deflectable()
	# --- the shared contracts ---
	await _test_reaction_contract_is_complete_and_in_world_space()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Shadow kit world tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Shadow kit world tests: all PASS")
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


# ------------------------------------------------------------ world scaffolding
# Every test builds its own terrain in its own y band, far from every other, so one
# test's leftovers can never satisfy another's ray.

func _solid(at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	body.global_position = at
	return body


## A floor slab whose TOP surface is at `top_y`, spanning x `from_x`..`to_x`.
func _floor(from_x: float, to_x: float, top_y: float) -> StaticBody2D:
	var w: float = to_x - from_x
	return _solid(Vector2(from_x + w * 0.5, top_y + 20.0), Vector2(w, 40.0))


## A wall STANDING ON a floor whose surface is `top_y`: spans `top_y - height`..`top_y`.
func _standing_wall(x: float, top_y: float, height: float, thickness: float = 40.0) -> StaticBody2D:
	return _solid(Vector2(x, top_y - height * 0.5), Vector2(thickness, height))


func _crate_at(at: Vector2, size: Vector2 = Vector2(40.0, 40.0)) -> FakeCrate:
	var c := FakeCrate.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	c.add_child(cs)
	c.collision_layer = 5           # bits 1+4 — blocks movement AND takes spell hits
	c.add_to_group("destructible")
	root.add_child(c)
	c.global_position = at
	return c


func _arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a


func _enemy(parent: Node, at: Vector2) -> FakeEnemy:
	var e := FakeEnemy.new()
	parent.add_child(e)
	e.global_position = at
	return e


func _hero(parent: Node, at: Vector2) -> FakeHero:
	var h := FakeHero.new()
	parent.add_child(h)
	h.global_position = at
	return h


func _cleanup(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await physics_frame
	await physics_frame


## Drive a spectacle by hand. Engine processing is switched OFF first so the only
## clock is this loop — a spell stepped by both would advance at an unknown rate and
## every timing assertion below would be a coin toss.
func _step(node: Node, steps: int, dt: float = STEP) -> void:
	node.set_process(false)
	for _i: int in steps:
		if not is_instance_valid(node):
			return
		node.call("_process", dt)


## Step until `state_var` leaves `while_state`, or MAX_STEPS runs out.
func _step_until_state_changes(node: Node, while_state: int) -> void:
	node.set_process(false)
	for _i: int in MAX_STEPS:
		if not is_instance_valid(node) or int(node.get("_state")) != while_state:
			return
		node.call("_process", STEP)


# --------------------------------------------------------------------- RiftDagger

func _throw(arena: Node, owner_node: Node, from: Vector2, aim: Vector2,
		range_px: float = 700.0, burst_r: float = 70.0, damage: int = 30) -> Node2D:
	var d: Node2D = (load(DAGGER_PATH) as GDScript).new()
	arena.add_child(d)
	d.call("throw_dagger", owner_node, from, aim, Color(0.6, 0.35, 0.95),
		range_px, burst_r, damage, 4.0, 4.5, "shadow")
	return d


## A wall between the blade and its target stops it AT the wall — and the body on
## the far side, well inside the dagger's flight path, takes NOTHING.
func _test_dagger_stops_at_a_wall() -> void:
	var y: float = 1000.0
	var arena: Node2D = _arena()
	var wall: StaticBody2D = _solid(Vector2(100.0, y), Vector2(40.0, 200.0))  # x 80..120
	var behind: FakeEnemy = _enemy(arena, Vector2(300.0, y))
	var thrower: Node2D = Node2D.new()
	arena.add_child(thrower)
	thrower.global_position = Vector2(0.0, y)
	await physics_frame
	var d: Node2D = _throw(arena, thrower, Vector2(0.0, y), Vector2.RIGHT)
	_step_until_state_changes(d, 0)  # State.FLYING == 0
	_expect(int(d.get("_state")) == 1, "the blade STOPS (state STUCK) at the wall")
	var pos: Vector2 = d.get("_pos")
	_expect(absf(pos.x - 80.0) < TOL,
		"...at the wall's near face x≈80, not past it (got %s)" % pos.x)
	_expect(behind.taken == 0,
		"THE NEGATIVE CASE: a body behind the wall takes ZERO (got %d)" % behind.taken)
	await _cleanup([arena, wall])
	_completes("dagger_stops_at_a_wall")


## Cover STOPS this spell rather than being torn through — the one documented
## smash-rule exemption in the kit, because a thrown dagger is an object that plants
## itself. But "destroy what it can" still applies: the crate takes the hit. Before
## this work it took precisely nothing, because the wall raycast returned on the
## crate's layer-1 collider before the destructible loop below could ever run.
func _test_dagger_plants_in_cover_and_damages_it() -> void:
	var y: float = 1400.0
	var arena: Node2D = _arena()
	var crate: FakeCrate = _crate_at(Vector2(100.0, y))  # x 80..120
	var thrower: Node2D = Node2D.new()
	arena.add_child(thrower)
	thrower.global_position = Vector2(0.0, y)
	await physics_frame
	var d: Node2D = _throw(arena, thrower, Vector2(0.0, y), Vector2.RIGHT, 700.0, 70.0, 30)
	_step_until_state_changes(d, 0)
	_expect(int(d.get("_state")) == 1, "the blade plants itself IN the crate")
	_expect(crate.taken == 30,
		"...and the crate takes the blade's damage (got %d, was 0 before this fix)" % crate.taken)
	_expect(absf(crate.last_contact.x - 80.0) < TOL,
		"...chipped at the face it was actually struck (got %s)" % crate.last_contact.x)
	await _cleanup([arena, crate])
	_completes("dagger_plants_in_cover_and_damages_it")


## The arrival burst: inside the drawn radius is hit, JUST OUTSIDE takes zero, and
## behind cover takes zero even though it is well inside the radius. That last one
## is the maker's "spells shouldn't be able to get out the radius", in its
## through-walls form.
func _test_dagger_burst_respects_cover_and_its_own_radius() -> void:
	var y: float = 1800.0
	var burst_r: float = 70.0
	var arena: Node2D = _arena()
	var wall: StaticBody2D = _solid(Vector2(300.0, y), Vector2(40.0, 200.0))  # x 280..320
	var thrower: Node2D = Node2D.new()
	arena.add_child(thrower)
	thrower.global_position = Vector2(0.0, y)
	await physics_frame
	var d: Node2D = _throw(arena, thrower, Vector2(0.0, y), Vector2.RIGHT, 700.0, burst_r)
	_step_until_state_changes(d, 0)
	var stuck: Vector2 = d.get("_pos")
	_expect(absf(stuck.x - 280.0) < TOL, "the blade planted in the wall face")
	# Placed relative to the ARRIVAL point, which sits a little back from the blade
	# (see _safe_arrival) — so measure against the dagger's own resolved position.
	var near: FakeEnemy = _enemy(arena, Vector2(stuck.x - 30.0, y))
	var just_out: FakeEnemy = _enemy(arena, Vector2(stuck.x - 170.0, y))
	var behind: FakeEnemy = _enemy(arena, Vector2(stuck.x + 50.0, y))
	await physics_frame
	d.call("recall")
	_step(d, 40)
	_expect(near.taken > 0, "a body inside the arrival burst is hit")
	_expect(just_out.taken == 0,
		"THE NEGATIVE CASE: a body outside the drawn burst takes ZERO (got %d)" % just_out.taken)
	_expect(just_out.shoves == Vector2.ZERO, "...and is not shoved either")
	_expect(behind.taken == 0,
		"THE NEGATIVE CASE: a body inside the radius but BEHIND the wall takes ZERO (got %d)"
			% behind.taken)
	await _cleanup([arena, wall])
	_completes("dagger_burst_respects_cover_and_its_own_radius")


## The head bug, directly. A body whose ORIGIN is outside the burst radius but whose
## drawn spine reaches inside it must register — that is the maker's "spells pass
## through heads without registering". Its partner assertion is the body placed far
## enough that even its head is clear, which must still take zero: the fix widens the
## test to the silhouette, it does not simply inflate the radius.
func _test_dagger_burst_registers_a_head_height_body() -> void:
	var y: float = 2200.0
	var burst_r: float = 70.0
	var arena: Node2D = _arena()
	var thrower: Node2D = Node2D.new()
	arena.add_child(thrower)
	thrower.global_position = Vector2(0.0, y)
	await physics_frame
	# Range 120 with nothing in the way: it whiffs, drops, finds no floor and is lost
	# — so instead we let it hit a wall and recall from there, which is deterministic.
	var wall: StaticBody2D = _solid(Vector2(400.0, y), Vector2(40.0, 40.0))
	await physics_frame
	var d: Node2D = _throw(arena, thrower, Vector2(0.0, y), Vector2.RIGHT, 700.0, burst_r)
	_step_until_state_changes(d, 0)
	var at: Vector2 = d.get("_pos")
	# Origin 75 px BELOW the blade: outside a 70 px radius by the old origin test,
	# but its 20 px spine reaches to 55 px, comfortably inside.
	var head_high: FakeEnemy = _enemy(arena, at + Vector2(0.0, 75.0))
	# Origin 110 px below: even the top of the spine is 90 px away, outside 70 + 7.
	var clear: FakeEnemy = _enemy(arena, at + Vector2(0.0, 110.0))
	await physics_frame
	d.call("recall")
	_step(d, 40)
	_expect(head_high.taken > 0,
		"a body whose ORIGIN is outside the radius but whose BODY reaches in is hit")
	_expect(clear.taken == 0,
		"THE NEGATIVE CASE: a body whose whole silhouette is clear takes ZERO (got %d)"
			% clear.taken)
	await _cleanup([arena, wall])
	_completes("dagger_burst_registers_a_head_height_body")


## The blade plants itself IN walls by design, so the naive "arrive on the blade"
## would put a body inside solid rock — the same rule that forbids a meteor under
## the floor. The arrival must be pushed back out onto open ground.
func _test_dagger_arrival_is_never_inside_a_wall() -> void:
	var y: float = 2600.0
	var arena: Node2D = _arena()
	var wall: StaticBody2D = _solid(Vector2(300.0, y), Vector2(80.0, 200.0))  # x 260..340
	var thrower: Node2D = Node2D.new()
	arena.add_child(thrower)
	thrower.global_position = Vector2(0.0, y)
	await physics_frame
	var d: Node2D = _throw(arena, thrower, Vector2(0.0, y), Vector2.RIGHT)
	_step_until_state_changes(d, 0)
	d.call("recall")
	_step(d, 40)
	var landed: Vector2 = thrower.global_position
	_expect(landed.x < 260.0,
		"the caster arrives OUTSIDE the wall the blade is buried in (got x=%s)" % landed.x)
	_expect(not SpellWorld.is_blocked(landed, 4.0),
		"...and the point it arrived at is not inside solid geometry")
	await _cleanup([arena, wall])
	_completes("dagger_arrival_is_never_inside_a_wall")


## A dagger that runs out of range over open air has nothing to plant itself in.
## "Nothing may end up below or inside the environment" cuts both ways — it must be
## LOST, not left hanging in the void as a recallable anchor. The paired positive is
## the same throw over solid floor, which must still plant normally.
func _test_dagger_over_a_pit_is_lost_not_left_floating() -> void:
	var y: float = 3000.0
	var arena: Node2D = _arena()
	var thrower: Node2D = Node2D.new()
	arena.add_child(thrower)
	thrower.global_position = Vector2(0.0, y)
	await physics_frame
	# Over a pit: no floor anywhere in this band.
	var lost: Node2D = _throw(arena, thrower, Vector2(0.0, y), Vector2.RIGHT, 120.0)
	_step_until_state_changes(lost, 0)
	_expect(int(lost.get("_state")) == 3,
		"a dagger that whiffs over a pit is SPENT, not stuck in mid-air (state %s)"
			% lost.get("_state"))
	_expect(not lost.is_in_group("rift_anchor"),
		"...and leaves no recall anchor floating in the void")
	# Control: the identical throw over solid ground plants and stays recallable.
	var ground: StaticBody2D = _floor(-200.0, 600.0, y + 60.0)
	await physics_frame
	var planted: Node2D = _throw(arena, thrower, Vector2(0.0, y), Vector2.RIGHT, 120.0)
	_step_until_state_changes(planted, 0)
	_expect(int(planted.get("_state")) == 1,
		"CONTROL: the same throw over solid floor plants normally (state %s)"
			% planted.get("_state"))
	await _cleanup([arena, ground])
	_completes("dagger_over_a_pit_is_lost_not_left_floating")


## reflect() is a ONE-SHOT, so a blade already turned once has no second reversal
## left — without SpellDeflect a guard press against the returning wave would be
## worth nothing at all. A clean guard eats it whole.
func _test_dagger_is_deflectable() -> void:
	var y: float = 3400.0
	var arena: Node2D = _arena()
	var thrower: Node2D = Node2D.new()
	arena.add_child(thrower)
	thrower.global_position = Vector2(600.0, y)
	await physics_frame
	var d: Node2D = _throw(arena, thrower, Vector2(600.0, y), Vector2.LEFT)
	d.call("reflect", Vector2.RIGHT, Color.WHITE)   # as a parry would
	var guard: FakeHero = _hero(arena, Vector2(750.0, y))
	guard.guarding = true
	await physics_frame
	_step_until_state_changes(d, 0)
	_expect(guard.taken == 0,
		"a guarding victim takes the DEFLECTED amount — zero (got %d)" % guard.taken)
	_expect(guard.statuses == 0, "...and no ailment is applied through the guard")
	# Control: the same reflected blade against an unguarded body does land. It runs
	# in its own y band with the guarding hero torn down first — "hero" is a GLOBAL
	# group, so a guard left standing anywhere would eat this blade too and the
	# control would pass for the wrong reason.
	await _cleanup([arena])
	var y2: float = y + 400.0
	var arena2: Node2D = _arena()
	var thrower2 := Node2D.new()
	arena2.add_child(thrower2)
	thrower2.global_position = Vector2(600.0, y2)
	await physics_frame
	var d2: Node2D = _throw(arena2, thrower2, Vector2(600.0, y2), Vector2.LEFT)
	d2.call("reflect", Vector2.RIGHT, Color.WHITE)
	var open: FakeHero = _hero(arena2, Vector2(760.0, y2))
	await physics_frame
	_step_until_state_changes(d2, 0)
	_expect(open.taken > 0, "CONTROL: an unguarded body does take the returned blade")
	await _cleanup([arena2])
	_completes("dagger_is_deflectable")


# -------------------------------------------------------------------- BlinkStrike

## The blast ring must not reach through a wall. The shipped suite
## (tools/slice_test_blink_blast.gd) already owns the radius boundary and the dodge
## window; this covers only the world half it could not.
func _test_blink_blast_does_not_leak_through_a_wall() -> void:
	var y: float = 3800.0
	var arena: Node2D = _arena()
	var dest := Vector2(0.0, y)
	var wall: StaticBody2D = _solid(Vector2(30.0, y), Vector2(10.0, 200.0))  # x 25..35
	var behind: FakeEnemy = _enemy(arena, Vector2(55.0, y))     # 55 px away, inside 64
	var open: FakeEnemy = _enemy(arena, Vector2(-55.0, y))      # same distance, clear line
	await physics_frame
	var b: Node2D = (load(BLINK_PATH) as GDScript).new()
	arena.add_child(b)
	b.call("strike", Vector2(-400.0, y), dest, Color(0.6, 0.35, 0.95), 40, "shadow")
	b.call("advance", 0.4)
	_expect(open.taken > 0, "a body inside the ring with a clear line is hit")
	_expect(behind.taken == 0,
		"THE NEGATIVE CASE: the same distance BEHIND a wall takes ZERO (got %d)" % behind.taken)
	await _cleanup([arena, wall])
	_completes("blink_blast_does_not_leak_through_a_wall")


func _test_blink_blast_is_deflectable() -> void:
	var y: float = 4200.0
	var arena: Node2D = _arena()
	var dest := Vector2(0.0, y)
	var guard: FakeEnemy = _enemy(arena, dest)
	guard.guarding = true
	var open: FakeEnemy = _enemy(arena, dest + Vector2(20.0, 0.0))
	await physics_frame
	var b: Node2D = (load(BLINK_PATH) as GDScript).new()
	arena.add_child(b)
	b.call("strike", Vector2(-400.0, y), dest, Color(0.6, 0.35, 0.95), 40, "shadow")
	b.call("advance", 0.4)
	_expect(guard.taken == 0,
		"a guarding victim takes the DEFLECTED amount — zero (got %d)" % guard.taken)
	_expect(guard.shoves == Vector2.ZERO, "...and is not shoved by a blast it ate")
	_expect(open.taken > 0, "CONTROL: the body beside it, not guarding, is hit")
	await _cleanup([arena])
	_completes("blink_blast_is_deflectable")


# --------------------------------------------------------------------- ShadowRoot

func _erupt(arena: Node, origin: Vector2, aim: Vector2, radius: float = 64.0,
		damage: int = 26) -> Node2D:
	var r: Node2D = (load(ROOT_PATH) as GDScript).new()
	arena.add_child(r)
	r.call("erupt", origin, aim, Color(0.6, 0.35, 0.9), radius, damage, "shadow")
	return r


## Shadow Root is NOT the kit's wall-passer (that is ShadowCrawler, whose identity
## it would steal), so a wall standing in the surge's way stops the grasp AT it —
## and a body on the far side is not rooted through solid rock.
func _test_root_surge_stops_at_a_wall() -> void:
	var y: float = 4600.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-200.0, 900.0, y)
	var wall: StaticBody2D = _standing_wall(300.0, y, 120.0)   # x 280..320
	var beyond: FakeEnemy = _enemy(arena, Vector2(420.0, y - 10.0))
	await physics_frame
	var r: Node2D = _erupt(arena, Vector2(0.0, y - 10.0), Vector2(420.0, 0.0))
	var lock: Vector2 = r.get("_lock")
	_expect(lock.x < 300.0,
		"the grasp lands on THIS side of the wall (got x=%s, wall face 280)" % lock.x)
	_step(r, 40)   # past SURGE_TIME 0.5
	_expect(bool(r.get("_snapped")), "the grasp resolved")
	_expect(beyond.taken == 0,
		"THE NEGATIVE CASE: a body past the wall is not rooted through it (got %d)"
			% beyond.taken)
	await _cleanup([arena, ground, wall])
	_completes("root_surge_stops_at_a_wall")


## A grasp mark rolled onto thin air is the meteor bug wearing a different hat. The
## walk stops at the last solid ground instead.
func _test_root_lock_stops_at_the_lip_of_a_pit() -> void:
	var y: float = 5000.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-100.0, 200.0, y)   # everything past x=200 is a pit
	await physics_frame
	var r: Node2D = _erupt(arena, Vector2(0.0, y - 10.0), Vector2(460.0, 0.0))
	var lock: Vector2 = r.get("_lock")
	_expect(lock.x <= 200.0 + TOL,
		"the grasp stops at the lip of the pit, not out over it (got x=%s)" % lock.x)
	_expect(absf(lock.y - y) < TOL,
		"...and sits ON the floor surface, not in mid-air (got y=%s, floor %s)" % [lock.y, y])
	await _cleanup([arena, ground])
	_completes("root_lock_stops_at_the_lip_of_a_pit")


## CATCH_HEIGHT used to be 100 while the claws were drawn 46 tall — the grasp
## reached more than twice as high as any picture of it. One constant now feeds
## both, and this pins it: a grounded body is caught, a body above the claws is not,
## and a body off the mark is not.
func _test_root_catch_window_is_what_is_drawn() -> void:
	var y: float = 5400.0
	var radius: float = 64.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-200.0, 900.0, y)
	await physics_frame
	var r: Node2D = _erupt(arena, Vector2(0.0, y - 10.0), Vector2(300.0, 0.0), radius)
	var lock: Vector2 = r.get("_lock")
	var script: GDScript = load(ROOT_PATH) as GDScript
	var claw: float = float(script.CATCH_HEIGHT)
	var on_mark: FakeEnemy = _enemy(arena, lock + Vector2(0.0, -10.0))
	var jumped: FakeEnemy = _enemy(arena, lock + Vector2(0.0, -(claw + 20.0)))
	var off_mark: FakeEnemy = _enemy(arena, lock + Vector2(radius + 40.0, -10.0))
	await physics_frame
	_step(r, 40)
	_expect(on_mark.taken > 0, "a grounded body on the mark is rooted")
	_expect(jumped.taken == 0,
		"THE NEGATIVE CASE: a body above the DRAWN claw height escaped (got %d)"
			% jumped.taken)
	_expect(off_mark.taken == 0,
		"THE NEGATIVE CASE: a body off the mark takes ZERO (got %d)" % off_mark.taken)
	_expect(float(script.CATCH_HEIGHT) == claw,
		"CATCH_HEIGHT is the single number the claws are drawn at")
	await _cleanup([arena, ground])
	_completes("root_catch_window_is_what_is_drawn")


func _test_root_is_deflectable() -> void:
	var y: float = 5800.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-200.0, 900.0, y)
	await physics_frame
	var r: Node2D = _erupt(arena, Vector2(0.0, y - 10.0), Vector2(300.0, 0.0))
	var lock: Vector2 = r.get("_lock")
	var guard: FakeEnemy = _enemy(arena, lock + Vector2(0.0, -10.0))
	guard.guarding = true
	await physics_frame
	_step(r, 40)
	_expect(guard.taken == 0,
		"a guarding victim takes the DEFLECTED amount — zero (got %d)" % guard.taken)
	_expect((r.get("_victims") as Array).is_empty(),
		"...and is not ROOTED either: a guard that ate the grasp is not held by it")
	await _cleanup([arena, ground])
	_completes("root_is_deflectable")


# ------------------------------------------------------------------ ShadowCrawler

func _crawl(arena: Node, origin: Vector2, aim: Vector2, range_px: float = 620.0,
		catch_r: float = 26.0, damage: int = 60) -> Node2D:
	var c: Node2D = (load(CRAWLER_PATH) as GDScript).new()
	arena.add_child(c)
	c.call("crawl", origin, aim, Color(0.6, 0.35, 0.9), range_px, catch_r, damage, "shadow")
	return c


## ⚠ THE EXEMPTION GUARD. Passing UNDER barriers is this spell's identity — "the
## kit's only answer to a wall". If a future consolidation pass swaps `_floor_y` for
## SpellWorld.floor_below (which casts with hit_from_inside ON) the head will pin
## itself to the underside of the wall and this test goes red. Do not delete it.
func _test_crawler_still_goes_under_walls() -> void:
	var y: float = 6200.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-200.0, 900.0, y)
	var wall: StaticBody2D = _standing_wall(200.0, y, 80.0)
	var target: FakeEnemy = _enemy(arena, Vector2(400.0, y - 10.0))
	await physics_frame
	var c: Node2D = _crawl(arena, Vector2(0.0, y - 10.0), Vector2.RIGHT)
	_step(c, MAX_STEPS)
	_expect(target.taken > 0,
		"the shade passed UNDER the wall and struck the body beyond it (got %d)"
			% target.taken)
	await _cleanup([arena, ground, wall])
	_completes("crawler_still_goes_under_walls")


## ...and the price of a spell terrain steers: run out of floor and it is gone,
## which also means the body waiting on the far side of the chasm is safe.
func _test_crawler_still_dies_in_a_pit() -> void:
	var y: float = 6600.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-100.0, 200.0, y)   # pit past x=200
	var far_side: FakeEnemy = _enemy(arena, Vector2(600.0, y - 10.0))
	await physics_frame
	var c: Node2D = _crawl(arena, Vector2(0.0, y - 10.0), Vector2.RIGHT)
	var died: bool = false
	c.set_process(false)
	for _i: int in MAX_STEPS:
		if not is_instance_valid(c) or int(c.get("_state")) == 4:   # State.DEAD
			died = true
			break
		c.call("_process", STEP)
	_expect(died, "the shade dies when it runs out of floor")
	_expect(far_side.taken == 0,
		"THE NEGATIVE CASE: the body across the chasm takes ZERO (got %d)" % far_side.taken)
	await _cleanup([arena, ground])
	_completes("crawler_still_dies_in_a_pit")


## A crate is not a safe place to stand: cover is smashed THROUGH, damaged, and does
## not stop the wave. The old test only saw cover whose ORIGIN happened to sit near
## the head, so a wide span the shade crossed the middle of was never touched.
func _test_crawler_chews_cover_on_the_way_past() -> void:
	var y: float = 7000.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-200.0, 900.0, y)
	var crate: FakeCrate = _crate_at(Vector2(200.0, y - 20.0))
	var beyond: FakeEnemy = _enemy(arena, Vector2(500.0, y - 10.0))
	await physics_frame
	var c: Node2D = _crawl(arena, Vector2(0.0, y - 10.0), Vector2.RIGHT)
	_step(c, MAX_STEPS)
	_expect(crate.taken > 0, "cover on the path is chewed (got %d)" % crate.taken)
	_expect(crate.taken == 60,
		"...exactly ONCE, not once per frame of the crossing (got %d)" % crate.taken)
	_expect(beyond.taken > 0, "...and the wave is NOT stopped by it")
	await _cleanup([arena, ground, crate])
	_completes("crawler_chews_cover_on_the_way_past")


## The only forgiveness added to the catch column is the target's OWN margin — never
## a pad invented at the call site.
##
## HONEST NOTE ON WHAT THAT MARGIN BUYS. `caught_by`'s x term is a COLUMN and the
## head sweeps through every x, so widening it changes WHERE the shade rears up, not
## WHETHER it catches — the boundary is only observable on the pure static, which is
## what the first block below tests. The y term is the real dodge and is unchanged;
## the second block is its negative case.
func _test_crawler_catch_uses_the_targets_own_margin() -> void:
	var catch_r: float = 26.0
	var margin: float = FakeEnemy.MARGIN
	var script: GDScript = load(CRAWLER_PATH) as GDScript
	var head := Vector2(0.0, 0.0)
	_expect(script.caught_by(head, Vector2(catch_r - 1.0, 0.0), catch_r),
		"boundary: just inside the bare column is caught")
	_expect(not script.caught_by(head, Vector2(catch_r + 4.0, 0.0), catch_r),
		"THE NEGATIVE CASE: just outside the bare column takes nothing")
	_expect(script.caught_by(head, Vector2(catch_r + 4.0, 0.0), catch_r + margin),
		"...and the SAME body IS caught once its own margin is added — the one and")
	_expect(not script.caught_by(head, Vector2(catch_r + margin + 4.0, 0.0),
			catch_r + margin),
		"...only forgiveness, with its own hard negative just past it")
	var arena: Node2D = _arena()
	# Inside catch_r + margin.
	var y1: float = 7400.0
	var g1: StaticBody2D = _floor(-200.0, 900.0, y1)
	var near: FakeEnemy = _enemy(arena, Vector2(300.0, y1 - 10.0))
	await physics_frame
	var c1: Node2D = _crawl(arena, Vector2(0.0, y1 - 10.0), Vector2.RIGHT, 620.0, catch_r)
	_step(c1, MAX_STEPS)
	_expect(near.taken > 0, "CONTROL: a body squarely in the column is struck")
	# Outside it: the shade must run straight past and whiff at the end of its budget.
	var y2: float = 7800.0
	var g2: StaticBody2D = _floor(-200.0, 900.0, y2)
	# Well above the catch window (CATCH_Y is 54) — airborne, so it is passed under.
	var airborne: FakeEnemy = _enemy(arena, Vector2(300.0, y2 - 140.0))
	await physics_frame
	var c2: Node2D = _crawl(arena, Vector2(0.0, y2 - 10.0), Vector2.RIGHT, 620.0, catch_r)
	_step(c2, MAX_STEPS)
	_expect(airborne.taken == 0,
		"THE NEGATIVE CASE: an airborne body above the catch window takes ZERO (got %d)"
			% airborne.taken)
	await _cleanup([arena, g1, g2])
	_completes("crawler_catch_uses_the_targets_own_margin")


func _test_crawler_is_deflectable() -> void:
	var y: float = 8200.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-200.0, 900.0, y)
	var guard: FakeEnemy = _enemy(arena, Vector2(300.0, y - 10.0))
	guard.guarding = true
	await physics_frame
	var c: Node2D = _crawl(arena, Vector2(0.0, y - 10.0), Vector2.RIGHT)
	_step(c, MAX_STEPS)
	_expect(guard.taken == 0,
		"a guarding victim takes the DEFLECTED amount — zero (got %d)" % guard.taken)
	_expect(guard.shoves == Vector2.ZERO, "...and is not launched by a strike it ate")
	await _cleanup([arena, ground])
	_completes("crawler_is_deflectable")


# ------------------------------------------------------------- shared contracts

## Every one of the four now participates in the reaction layer, and none of them
## reports its own transform as its geometry.
##
## THE TRAP THIS PINS: all four PARK AT THE ARENA ORIGIN and draw in world
## coordinates, so `global_position` is (0,0) and is NOT where the effect is. A
## reaction_shape() built from the transform would report every live spectacle as
## touching, at the top-left of the arena — a bug that fails loud in the wrong
## direction. Each shape below must sit near the point the spell was actually cast.
func _test_reaction_contract_is_complete_and_in_world_space() -> void:
	var y: float = 8600.0
	var arena: Node2D = _arena()
	var ground: StaticBody2D = _floor(-200.0, 1400.0, y)
	var thrower: Node2D = Node2D.new()
	arena.add_child(thrower)
	thrower.global_position = Vector2(600.0, y - 10.0)
	await physics_frame
	var live: Array[Node] = []
	var d: Node2D = _throw(arena, thrower, Vector2(600.0, y - 10.0), Vector2.RIGHT)
	live.append(d)
	var b: Node2D = (load(BLINK_PATH) as GDScript).new()
	arena.add_child(b)
	b.call("strike", Vector2(600.0, y - 10.0), Vector2(700.0, y - 10.0),
		Color(0.6, 0.35, 0.95), 40, "shadow")
	live.append(b)
	live.append(_erupt(arena, Vector2(600.0, y - 10.0), Vector2(300.0, 0.0)))
	live.append(_crawl(arena, Vector2(600.0, y - 10.0), Vector2.RIGHT))
	var wanted: Array[String] = [
		"reaction_shape", "reaction_active", "reaction_element", "reaction_form",
		"reaction_owner", "reaction_weight", "reaction_consume",
	]
	for n: Node in live:
		var who: String = n.get_script().resource_path.get_file()
		for m: String in wanted:
			_expect(n.has_method(m), "%s implements %s()" % [who, m])
		var shape: Dictionary = n.call("reaction_shape")
		_expect(not shape.is_empty(), "%s publishes a shape" % who)
		var centre: Vector2 = shape.get("center", Vector2.ZERO)
		_expect(centre.distance_to(Vector2.ZERO) > 100.0,
			"%s's shape is in WORLD space, not at the origin-parked transform (got %s)"
				% [who, centre])
		# The weight axis: whatever SpellCaster sets is what the reactor reads back.
		n.set("spell_tier", SpellTier.Tier.ULT)
		_expect(int(n.call("reaction_weight")) == SpellTier.Tier.ULT,
			"%s's reaction_weight() echoes spell_tier" % who)
	await _cleanup([arena, ground])
	_completes("reaction_contract_is_complete_and_in_world_space")
