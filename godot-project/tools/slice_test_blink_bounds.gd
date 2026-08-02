# BLINK: 360° AIM, PHASE-THROUGH, AND LANDING LEGALITY.
#
# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#          --script tools/slice_test_blink_bounds.gd
#
# The maker's ask, verbatim: "blink should just be in the direction it is facing and
# can go through stuff not just side to side, just make sure you cant blink into a
# wall or something". That is three claims, and this suite is one section per claim:
#
#   1. DIRECTION  — blink goes where you AIM, all 360°, not left/right. The
#      regression this guards is specific and was live: `_blink()` used to read
#      `_move_dir`, which is assigned `Vector2(signf(move_x), 0.0)` — structurally
#      incapable of a non-zero Y. So `blink_moves_vertically` is not a nice-to-have,
#      it is THE test that would have caught the bug.
#   2. PASS-THROUGH — a blink aimed INTO a solid slab comes out the FAR side. Also
#      asserted negatively: it must not stop short at the near face like a dash.
#   3. LEGALITY   — after any blink from anywhere, aimed anywhere, the body is never
#      inside a collider, never outside the room, and never over a ring-out pit.
#
# ⚠ NON-VACUOUSNESS. "The hero was never in a wall" is trivially satisfied by a blink
# that never moves, so every legality assertion is paired with a MOVEMENT assertion,
# and the sweep counts how many blinks it actually performed and fails if that count
# is zero. Same standing lesson as everywhere else: an invariant that holds over an
# empty result set is not an invariant.
#
# ⚠ TEST IDIOM (see tools/slice_test_loadout.gd for the full write-up). A dead member
# read ABORTS the enclosing function and hands the caller a zero — which under
# `failed += _test_x()` reads as "no failures". So failures accumulate on the MEMBER
# `_fails`, and every test's last line records that it reached the end. A test missing
# from `_completed` fails the suite BY ABSENCE.
extends SceneTree

## Every test that must run to completion.
const TESTS: Array[String] = [
	"blink_follows_aim_in_all_directions",
	"blink_moves_vertically",
	"blink_passes_through_a_slab",
	"blink_stops_inside_the_outer_wall",
	"blink_against_a_wall_is_refused_and_refunded",
	"blink_never_lands_over_a_pit",
	"blink_sweep_never_lands_illegally",
	"blink_to_spell_callback_vets_the_landing_spot",
]

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

# The room, built exactly the way Arena._apply_room_size builds one: a floor rect
# from (0,0) to (W,H) with four full-span wall colliders CENTRED on the edges, so
# each wall straddles the boundary by half its thickness.
const ROOM_W: float = 960.0
const ROOM_H: float = 480.0
const WALL_T: float = 16.0          # Arena.WALL_THICKNESS
const HERO_HALF: float = 9.0        # Hero.tscn's collider is an 18x18 rect

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
## Bodies that make up the test room, kept so the legality checker can re-query them.
var _room: Node2D = null
var _blinks_performed: int = 0


## ⚠ ALWAYS returns false. In a SceneTree script a true return QUITS the main loop,
## and `_run()` is async (it has to await physics frames before any shape query sees
## the room). Returning true here would tear the tree down before the first await
## resumed, and the suite would exit 0 having printed neither PASS nor FAIL — a
## green run that tested nothing. `_run()` ends the process itself via quit().
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	# Physics has to have ticked at least once before intersect_shape / intersect_ray
	# see anything we just added, so every test in here is downstream of an await.
	_build_room()
	await physics_frame
	await physics_frame

	await _test_blink_follows_aim_in_all_directions()
	await _test_blink_moves_vertically()
	await _test_blink_passes_through_a_slab()
	await _test_blink_stops_inside_the_outer_wall()
	await _test_blink_against_a_wall_is_refused_and_refunded()
	await _test_blink_never_lands_over_a_pit()
	await _test_blink_sweep_never_lands_illegally()
	await _test_blink_to_spell_callback_vets_the_landing_spot()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Blink bounds tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Blink bounds tests: all PASS (%d blinks performed)" % _blinks_performed)
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ----------------------------------------------------------------- the test room
## A REAL room: Arena's four walls, plus the kind of interior geometry FloorGen and
## the versus stage actually put in one — a rooted ruin platform, a breakable
## platform, a plain solid slab, and a ring-out pit. Built with the shipping classes
## rather than stand-ins so the geometry under test is the geometry that ships.
func _build_room() -> void:
	_room = Node2D.new()
	root.add_child(_room)
	# Four walls, Arena._apply_room_size geometry verbatim.
	var walls := StaticBody2D.new()
	_room.add_child(walls)
	_add_wall(walls, Vector2(ROOM_W * 0.5, 0.0), Vector2(ROOM_W, WALL_T))          # top
	_add_wall(walls, Vector2(ROOM_W * 0.5, ROOM_H), Vector2(ROOM_W, WALL_T))       # bottom
	_add_wall(walls, Vector2(0.0, ROOM_H * 0.5), Vector2(WALL_T, ROOM_H))          # left
	_add_wall(walls, Vector2(ROOM_W, ROOM_H * 0.5), Vector2(WALL_T, ROOM_H))       # right
	# A thick solid slab in open floor — the pass-through subject. Deliberately
	# THICKER than a wall (48 px) so "went through it" cannot be confused with
	# "stopped just short".
	var slab := StaticBody2D.new()
	_room.add_child(slab)
	_add_wall(slab, Vector2(SLAB_X, SLAB_Y), Vector2(SLAB_W, SLAB_H))
	# The shipping platform classes, for the sweep.
	#
	# ⚠ load()ed AT RUNTIME, never named as `class_name` identifiers. Naming one
	# here would make it a COMPILE-TIME dependency of this tool script, and these
	# classes reach the `Sfx` autoload — which is not registered yet when a
	# `--script` tool is compiled, so the whole suite fails to load with
	# "Identifier not found: Sfx". Same reason slice1_test_blink.gd load()s the hero
	# scene instead of preloading it.
	var ruin: Node2D = (load("res://scripts/combat/RuinPlatform.gd") as GDScript).new()
	ruin.platform_size = Vector2(190.0, 24.0)
	_room.add_child(ruin)
	ruin.position = Vector2(300.0, 300.0)
	var breakable: Node2D = (load("res://scripts/combat/BreakablePlatform.gd") as GDScript).new()
	breakable.platform_size = Vector2(150.0, 20.0)
	_room.add_child(breakable)
	breakable.position = Vector2(700.0, 180.0)
	# A ring-out pit. Hero._dest_in_pit finds these by group + duck-typed properties.
	# Mode.PIT == 0 (StageHazard's `enum Mode { PIT, SLOPE }`), written as the literal
	# for the same runtime-load reason as above.
	var pit: Node2D = (load("res://scripts/combat/StageHazard.gd") as GDScript).new()
	pit.mode = 0
	pit.zone_size = PIT_SIZE
	_room.add_child(pit)
	pit.position = PIT_CENTER


const SLAB_X: float = 520.0
const SLAB_Y: float = 400.0
const SLAB_W: float = 48.0
const SLAB_H: float = 160.0
const PIT_CENTER: Vector2 = Vector2(160.0, 120.0)
const PIT_SIZE: Vector2 = Vector2(120.0, 100.0)


func _add_wall(body: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func _make_hero(at: Vector2) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	# The body must EXIST to physics (so the room's colliders and its own shape are
	# real) but must not DRIVE itself — an un-suppressed _physics_process would apply
	# gravity between the await and the assertion and every position here would drift.
	hero.set_physics_process(false)
	hero.global_position = at
	return hero


## Teleport + re-arm, so one hero can be reused across many samples in a sweep
## without paying a scene instantiation per sample.
func _place(hero: CharacterBody2D, at: Vector2, aim: Vector2) -> void:
	hero.global_position = at
	hero._aim_dir = aim.normalized()
	hero._blink_cooldown_timer = 0.0


# ------------------------------------------------------------- legality checking
## The three rules, re-derived HERE from the room's real colliders rather than by
## calling Hero's own helper — a test that asks the implementation whether the
## implementation is right proves nothing.
func _illegal_reason(hero: CharacterBody2D) -> String:
	var at: Vector2 = hero.global_position
	# 1. inside solid geometry?
	var space: PhysicsDirectSpaceState2D = hero.get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(HERO_HALF * 2.0, HERO_HALF * 2.0)
	q.shape = box
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [hero.get_rid()]
	q.transform = Transform2D(0.0, at)
	if not space.intersect_shape(q, 1).is_empty():
		return "inside a collider at %s" % at
	# 2. outside the room? The playable box is the wall's INNER face, inset by the
	# hero's half-extent (a body centred any closer would be overlapping the wall).
	var lo: float = WALL_T * 0.5 + HERO_HALF
	if at.x < lo or at.x > ROOM_W - lo or at.y < lo or at.y > ROOM_H - lo:
		return "outside the room at %s" % at
	# 3. over the pit? (Hero.BLINK_PIT_MARGIN is not applied here on purpose: this
	# checks the HARD rule — never over the hole — not Hero's safety margin.)
	var rel: Vector2 = at - PIT_CENTER
	if absf(rel.x) <= PIT_SIZE.x * 0.5 and absf(rel.y) <= PIT_SIZE.y * 0.5:
		return "over the ring-out pit at %s" % at
	return ""


# ------------------------------------------------------------------- 1. DIRECTION
## Sixteen compass directions, run in EMPTY SPACE far from the furnished room.
##
## The empty-space choice is deliberate and was learned the hard way: run from the
## middle of the real room, three of these sixteen rays end inside the ruin, the
## breakable or the slab, and the blink correctly phases PAST them — so the honest
## "travelled exactly BLINK_DISTANCE" assertion goes red for a reason that has
## nothing to do with direction. Direction and clamping are separate claims and get
## separate tests: this one isolates "goes where you aim, at full length", and the
## legality tests below own "and gets clamped when the map says so".
const OPEN: Vector2 = Vector2(5000.0, 5000.0)


func _test_blink_follows_aim_in_all_directions() -> void:
	var hero: CharacterBody2D = _make_hero(OPEN)
	await physics_frame
	var moved: int = 0
	for i: int in 16:
		var aim: Vector2 = Vector2.from_angle(TAU * float(i) / 16.0)
		_place(hero, OPEN, aim)
		var origin: Vector2 = hero.global_position
		hero._blink()
		_blinks_performed += 1
		var delta: Vector2 = hero.global_position - origin
		# It MOVED, the full distance, and along the aim — the three things that
		# together mean "blink follows aim" rather than "blink did something".
		_expect(delta.length() > 1.0, "blink at %.0f° moved at all" % rad_to_deg(aim.angle()))
		_expect(absf(delta.length() - hero.BLINK_DISTANCE) < 2.0,
			"blink at %.0f° travelled BLINK_DISTANCE (got %.1f)"
			% [rad_to_deg(aim.angle()), delta.length()])
		_expect(delta.normalized().dot(aim) > 0.999,
			"blink at %.0f° went along the AIM (got %.0f°)"
			% [rad_to_deg(aim.angle()), rad_to_deg(delta.angle())])
		if delta.length() > 1.0:
			moved += 1
	_expect(moved == 16, "all 16 sampled directions produced a blink (got %d)" % moved)
	hero.queue_free()
	_completes("blink_follows_aim_in_all_directions")


## THE REGRESSION GUARD FOR THE MAKER'S ACTUAL COMPLAINT. Straight up and straight
## down must displace on Y and NOT on X. Under the old `_move_dir` implementation
## this was impossible: that vector's Y is hard-zero by construction, so an upward
## aim produced a horizontal blink. If this test ever goes red, blink has been
## re-wired to a movement vector again.
func _test_blink_moves_vertically() -> void:
	var hero: CharacterBody2D = _make_hero(OPEN)
	await physics_frame
	for aim: Vector2 in [Vector2.UP, Vector2.DOWN]:
		_place(hero, OPEN, aim)
		var origin: Vector2 = hero.global_position
		hero._blink()
		_blinks_performed += 1
		var delta: Vector2 = hero.global_position - origin
		_expect(absf(delta.y) > hero.BLINK_DISTANCE * 0.9,
			"a %s blink displaces on Y (got dy=%.1f)" % [aim, delta.y])
		_expect(absf(delta.x) < 1.0,
			"a %s blink does NOT drift sideways (got dx=%.1f)" % [aim, delta.x])
		_expect(signf(delta.y) == signf(aim.y), "a %s blink goes the right way on Y" % aim)
	hero.queue_free()
	_completes("blink_moves_vertically")


# ---------------------------------------------------------------- 2. PASS-THROUGH
## Aimed straight INTO a 48-px-thick slab, with the endpoint landing INSIDE it.
## The blink must come out the FAR side. The negative half of the assertion is the
## important one: landing at the near face is what a dash does, and this is not one.
func _test_blink_passes_through_a_slab() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(480.0, 240.0))
	await physics_frame
	var slab_left: float = SLAB_X - SLAB_W * 0.5
	var slab_right: float = SLAB_X + SLAB_W * 0.5
	# Stand so that origin + BLINK_DISTANCE lands in the middle of the slab.
	var origin := Vector2(SLAB_X - hero.BLINK_DISTANCE, SLAB_Y)
	_place(hero, origin, Vector2.RIGHT)
	hero._blink()
	_blinks_performed += 1
	var x: float = hero.global_position.x
	_expect(x > slab_right + HERO_HALF - 0.5,
		"blink aimed into the slab came out the FAR side (x=%.1f, slab ends %.1f)"
		% [x, slab_right])
	_expect(x > origin.x, "blink aimed into the slab still went FORWARD")
	_expect(_illegal_reason(hero) == "",
		"blink through the slab landed legally (%s)" % _illegal_reason(hero))
	# ...and it must not have overshot into next week: the phase budget is bounded.
	_expect(x - origin.x <= hero.BLINK_DISTANCE + hero.BLINK_PROBE_EXTRA + 1.0,
		"blink through the slab stayed inside the phase budget")
	hero.queue_free()
	_completes("blink_passes_through_a_slab")


# ------------------------------------------------------------------- 3. LEGALITY
## Aimed at the outer wall with room to travel: the blink must be CLAMPED to just
## inside the room rather than either (a) phasing out into the void — which is what
## the forward-probe used to do, since the 16-px wall fitted inside its budget — or
## (b) refusing outright when there was clearly ground to cover.
func _test_blink_stops_inside_the_outer_wall() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(480.0, 240.0))
	await physics_frame
	# 100 px from the right wall, aiming right: the raw endpoint is ~75 px OUTSIDE.
	var origin := Vector2(ROOM_W - 100.0, 240.0)
	_place(hero, origin, Vector2.RIGHT)
	hero._blink()
	_blinks_performed += 1
	var travelled: float = hero.global_position.x - origin.x
	_expect(_illegal_reason(hero) == "",
		"blink at the wall landed legally (%s)" % _illegal_reason(hero))
	_expect(travelled > hero.BLINK_MIN_TRAVEL,
		"blink at the wall still MOVED you toward it (travelled %.1f)" % travelled)
	_expect(travelled < hero.BLINK_DISTANCE,
		"blink at the wall was clamped short of the full distance (travelled %.1f)" % travelled)
	# The same story with the CEILING, which the old horizontal-only blink could
	# never even reach — this is the case the direction fix newly exposes.
	_place(hero, Vector2(480.0, 100.0), Vector2.UP)
	hero._blink()
	_blinks_performed += 1
	_expect(_illegal_reason(hero) == "",
		"blink at the ceiling landed legally (%s)" % _illegal_reason(hero))
	_expect(hero.global_position.y < 100.0, "blink at the ceiling still went UP")
	hero.queue_free()
	_completes("blink_stops_inside_the_outer_wall")


## Pressed with your nose against the wall: there is nowhere legal to go that is
## worth going, so the press must cost NOTHING. The two halves matter equally —
## the body must not move, and the cooldown must not have been spent, because a
## button that silently eats its own cooldown reads as broken rather than blocked.
func _test_blink_against_a_wall_is_refused_and_refunded() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(480.0, 240.0))
	await physics_frame
	var origin := Vector2(ROOM_W - WALL_T * 0.5 - HERO_HALF - 1.0, 240.0)
	_place(hero, origin, Vector2.RIGHT)
	hero._blink()
	_blinks_performed += 1
	_expect(hero.global_position.distance_to(origin) < 0.001,
		"a blink with nowhere to go does not move the body (moved %.2f)"
		% hero.global_position.distance_to(origin))
	_expect(hero._blink_cooldown_timer == 0.0,
		"a refused blink REFUNDS the cooldown (got %.2f)" % hero._blink_cooldown_timer)
	# ...and the refusal is not a permanent lockout: turn around and it fires.
	_place(hero, origin, Vector2.LEFT)
	hero._blink()
	_blinks_performed += 1
	_expect(hero.global_position.x < origin.x - hero.BLINK_MIN_TRAVEL,
		"re-aiming after a refused blink fires normally")
	_expect(hero._blink_cooldown_timer > 0.0, "the successful blink DOES spend the cooldown")
	hero.queue_free()
	_completes("blink_against_a_wall_is_refused_and_refunded")


## The pit rule, which is the one place "never lands somewhere illegal" is about a
## hole rather than a solid. Aimed so the raw endpoint is dead centre over it.
func _test_blink_never_lands_over_a_pit() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(480.0, 240.0))
	await physics_frame
	var origin := Vector2(PIT_CENTER.x + hero.BLINK_DISTANCE, PIT_CENTER.y)
	_place(hero, origin, Vector2.LEFT)
	hero._blink()
	_blinks_performed += 1
	var rel: Vector2 = hero.global_position - PIT_CENTER
	_expect(absf(rel.x) > PIT_SIZE.x * 0.5 or absf(rel.y) > PIT_SIZE.y * 0.5,
		"blink aimed at the pit did not land in it (ended at %s)" % hero.global_position)
	_expect(_illegal_reason(hero) == "",
		"blink aimed at the pit landed legally (%s)" % _illegal_reason(hero))
	hero.queue_free()
	_completes("blink_never_lands_over_a_pit")


## THE SWEEP the whole exercise is for: many origins x many directions against the
## real room, asserting the invariant after every single one. Counts its own samples
## so a future edit that makes the loop body unreachable fails loudly instead of
## reporting a clean run over nothing.
func _test_blink_sweep_never_lands_illegally() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(480.0, 240.0))
	await physics_frame
	var origins: Array[Vector2] = []
	# A grid over the playable interior, plus deliberate awkward spots: hard against
	# each wall, in the corners, on top of the slab, and beside the pit.
	for gx: int in 7:
		for gy: int in 4:
			origins.append(Vector2(80.0 + 130.0 * float(gx), 70.0 + 110.0 * float(gy)))
	var inset: float = WALL_T * 0.5 + HERO_HALF + 1.0
	origins.append(Vector2(inset, inset))
	origins.append(Vector2(ROOM_W - inset, inset))
	origins.append(Vector2(inset, ROOM_H - inset))
	origins.append(Vector2(ROOM_W - inset, ROOM_H - inset))
	origins.append(Vector2(480.0, inset))
	origins.append(Vector2(SLAB_X, SLAB_Y - SLAB_H * 0.5 - HERO_HALF - 1.0))
	origins.append(PIT_CENTER + Vector2(PIT_SIZE.x, 0.0))

	var samples: int = 0
	var displaced: int = 0
	var vertical_displacements: int = 0
	for origin: Vector2 in origins:
		# Skip an origin that is itself illegal (a grid point may land inside the
		# slab); blinking OUT of geometry is not what this test is about.
		hero.global_position = origin
		if _illegal_reason(hero) != "":
			continue
		for i: int in 12:
			var aim: Vector2 = Vector2.from_angle(TAU * float(i) / 12.0)
			_place(hero, origin, aim)
			hero._blink()
			samples += 1
			_blinks_performed += 1
			var reason: String = _illegal_reason(hero)
			_expect(reason == "",
				"blink from %s at %.0f° landed legally — %s"
				% [origin, rad_to_deg(aim.angle()), reason])
			var delta: Vector2 = hero.global_position - origin
			if delta.length() > 1.0:
				displaced += 1
				if absf(delta.y) > 20.0:
					vertical_displacements += 1
	# NON-VACUOUS: the invariant above is worthless if nothing ran, and equally
	# worthless if every blink refused. Most of this room is open floor, so the
	# overwhelming majority of samples must have actually teleported.
	_expect(samples >= 200, "the sweep ran a meaningful number of samples (got %d)" % samples)
	_expect(float(displaced) > float(samples) * 0.8,
		"the sweep mostly MOVED the hero rather than refusing (%d/%d)" % [displaced, samples])
	_expect(vertical_displacements > samples / 4,
		"the sweep produced plenty of VERTICAL travel (%d/%d) — not a side-to-side dash"
		% [vertical_displacements, samples])
	hero.queue_free()
	_completes("blink_sweep_never_lands_illegally")


## The SPELL path (SpellDef.Kind.BLINK_STRIKE -> SpellCaster -> `blink_to`) must go
## through the same vetting, because that arm hands a raw aim-derived point straight
## in. Also pins the deliberate asymmetry with the ability: the spell is NOT refunded
## when it cannot travel — it just doesn't move, and the caller detonates at the feet.
func _test_blink_to_spell_callback_vets_the_landing_spot() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(480.0, 240.0))
	await physics_frame
	# Ask for a point well outside the room.
	var landed: Vector2 = hero.blink_to(Vector2(ROOM_W + 400.0, 240.0))
	_expect(_illegal_reason(hero) == "",
		"blink_to() never leaves the body illegal (%s)" % _illegal_reason(hero))
	_expect(landed == hero.global_position,
		"blink_to() reports the spot it actually moved to (said %s, at %s)"
		% [landed, hero.global_position])
	_expect(hero.global_position.x > 480.0, "blink_to() still travelled toward the ask")
	# Nose against the wall: no travel, but the call is still well-behaved and the
	# returned point is where the blast should draw — our own feet.
	var pinned := Vector2(ROOM_W - WALL_T * 0.5 - HERO_HALF - 1.0, 240.0)
	hero.global_position = pinned
	var pinned_landed: Vector2 = hero.blink_to(Vector2(ROOM_W + 400.0, 240.0))
	_expect(pinned_landed == pinned,
		"blink_to() with nowhere to go reports the caster's own position")
	_expect(hero.global_position == pinned, "blink_to() with nowhere to go does not move")
	hero.queue_free()
	_completes("blink_to_spell_callback_vets_the_landing_spot")
