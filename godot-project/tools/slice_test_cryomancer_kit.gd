# THE CRYOMANCER'S TWO 2026-09-05 RULINGS, PINNED.
#
# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#          --script tools/slice_test_cryomancer_kit.gd
#
# 1. THE PRIMARY IS A SHARD VOLLEY, NOT A CONE. Maker: *"cryomancers left click
#    attack the cone is weird and too big just change it all shoot out some crystal
#    ice shards or something instead"*. The old wedge measured reach 118 px /
#    half-angle 60 deg — 120 deg of arc, the widest and longest basic attack in the
#    roster. This suite pins that the press now publishes a LANE tell whose corridor
#    is the corridor the shards actually fly down, that the total damage landed on
#    one body is 18 (against the cone's 19, i.e. a re-shape not a stealth buff), and
#    that a shard PIERCES rather than expiring on the first torso.
#
# 2. THE ICE SLIDE CAN CLIMB. Maker: *"also make sure I can dash upwards with
#    cryomancer as well"* — the SECOND report of this. The first fix taught
#    `_dash_dir` to keep its vertical, and `slice_test_class_movement` went green on
#    exactly that: it asserts `absf(dir.y) > 0.5`. But `_begin_verb_extras` then set
#    only `velocity.x`, and `_travel_velocity` overwrote `v.y` with gravity on every
#    frame of the 0.55 s travel — so the DIRECTION was right and the DISPLACEMENT was
#    zero, and the suite could not tell.
#
# ⚠ THAT GAP IS WHY THIS FILE EXISTS, AND IT IS THE HOUSE LESSON: assert the channel
# the PLAYER gets. Every movement assertion below measures `global_position` before
# and after, never `_dash_dir` and never a constant.
#
# ⚠ NON-VACUOUSNESS. Each test counts what it actually performed and fails at zero —
# "no shard ever hit illegally" is trivially true of a volley that never spawned.
#
# ⚠ TEST IDIOM (full write-up in tools/slice_test_loadout.gd). A dead member read
# ABORTS the enclosing function and hands the caller the type's zero, which the
# `failed += _test_x()` idiom reads as "no failures". So failures accumulate on the
# MEMBER `_fails`, and every test's last line records a COMPLETION SENTINEL.
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const CRYOMANCER: int = 5

const TESTS: Array[String] = [
	"the_primary_is_a_shard_volley_not_a_cone",
	"the_drawn_lane_is_the_flown_corridor",
	"a_volley_lands_the_cones_damage",
	"a_shard_pierces_and_never_double_dips",
	"the_ice_slide_actually_climbs",
	"the_ice_slide_still_bleeds_and_still_travels_flat",
]

## Hero members/methods reached DYNAMICALLY (Hero.gd has no class_name). Listed once
## so a relocation is NAMED rather than merely caught by the sentinel.
const HERO_MEMBERS: Array[String] = [
	"_cfg", "_aim_dir", "_move_dir", "facing", "velocity", "is_dashing",
	"_cast_cooldown_timer", "_dash_cooldown_timer", "_dash_verb",
]
const HERO_METHODS: Array[String] = [
	"configure_class", "_cast", "_primary_frost_shards", "_start_dash",
	"movement_verb_name", "movement_verb_distance",
]

const FLOOR_Y: float = 400.0
const START_X: float = 900.0
const START_Y: float = FLOOR_Y - 10.0
const FLOOR_W: float = 4000.0
const TRAVEL_FRAME_CAP: int = 240

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _floor: StaticBody2D = null


## A body that counts what the volley did to it. Declares BOTH `take_damage` arities'
## worth of surface via the two-arg default, which is what `SpellTargets.hurt` probes.
##
## ⚠ AND IT PUBLISHES A `body_distance`, WHICH IS NOT DECORATION. A bare `Node2D` is a
## POINT, and the game's real fighters are not: `SpellTargets.body_distance` asks the
## target for its silhouette and only falls back to the origin for stubs. A stub that
## stayed a point would have made this suite measure a stricter game than the one that
## ships — the volley leaves the weapon tip 14.2 px above the body origin, so a
## point-dummy is missed by shots that visibly go through a real torso. 12 px is the
## rough half-height of the drawn rig.
class ShardDummy:
	extends Node2D
	const BODY_RADIUS: float = 12.0
	var hp: int = 500
	var hits: int = 0
	var damage_taken: int = 0
	var chilled: int = 0
	func body_distance(p: Vector2) -> float:
		return maxf(global_position.distance_to(p) - BODY_RADIUS, 0.0)
	func take_damage(a: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		hp -= a
		hits += 1
		damage_taken += a
	func apply_knockback(_v: Vector2) -> void:
		pass
	func apply_status(_e: int, _c: bool = true) -> void:
		chilled += 1


## ⚠ ALWAYS returns false — a `true` return QUITS the main loop, and `_run()` is async.
## `_run()` ends the process itself.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	_pin_level_one()
	_build_floor()
	await physics_frame
	await physics_frame

	await _test_the_primary_is_a_shard_volley_not_a_cone()
	await _test_the_drawn_lane_is_the_flown_corridor()
	await _test_a_volley_lands_the_cones_damage()
	await _test_a_shard_pierces_and_never_double_dips()
	await _test_the_ice_slide_actually_climbs()
	await _test_the_ice_slide_still_bleeds_and_still_travels_flat()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Cryomancer kit tests: %d FAILED" % _fails)
		quit(1)
		return
	print("Cryomancer kit tests: all PASS")
	quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Same reason `slice_test_class_movement` pins it: `GameState._ready` loads the real
## `user://climber.json`, so on a machine whose owner has played, every stat below
## silently drifts by their level.
func _pin_level_one() -> void:
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs == null:
		return
	gs.set("_xp", 0)
	if gs.has_method("clear_party_level"):
		gs.call("clear_party_level")


func _build_floor() -> void:
	_floor = StaticBody2D.new()
	_floor.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(FLOOR_W, 40.0)
	cs.shape = rect
	_floor.add_child(cs)
	_floor.global_position = Vector2(START_X, FLOOR_Y + 20.0)
	root.add_child(_floor)


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.call("configure_class", CRYOMANCER)
	hero.global_position = Vector2(START_X, START_Y)
	hero.set("facing", Vector2.RIGHT)
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.set("_move_dir", Vector2.RIGHT)
	return hero


func _require_surface(hero: Object) -> void:
	var present: Dictionary = {}
	for p: Dictionary in hero.get_property_list():
		present[String(p["name"])] = true
	for n: String in HERO_MEMBERS:
		_expect(present.has(n),
			"Hero still declares `%s` (moved or renamed — assertions reading it are dead)" % n)
	for m: String in HERO_METHODS:
		_expect(hero.has_method(m),
			"Hero still has method `%s()` (renamed — assertions calling it are dead)" % m)


## Instance ids of every live telegraph, so one press's tell can be told apart from
## whatever a previous test left standing. (`probe_basic_attack_visuals` records why:
## nothing `queue_free`d is actually freed inside a synchronous loop, and reading
## `get_nodes_in_group("telegraph")[0]` made every class report the Brawler's tell.)
func _tell_ids() -> Dictionary:
	var out: Dictionary = {}
	for n: Node in get_nodes_in_group(&"telegraph"):
		if is_instance_valid(n):
			out[n.get_instance_id()] = true
	return out


func _new_tell(before: Dictionary) -> Node:
	for n: Node in get_nodes_in_group(&"telegraph"):
		if is_instance_valid(n) and not before.has(n.get_instance_id()):
			return n
	return null


func _volley_ids() -> Dictionary:
	var out: Dictionary = {}
	for n: Node in root.get_children():
		if n is FrostShards:
			out[n.get_instance_id()] = true
	return out


func _new_volley(before: Dictionary) -> Node:
	for n: Node in root.get_children():
		if n is FrostShards and not before.has(n.get_instance_id()):
			return n
	return null


## Press LMB and fire the tell's lead out by hand, so the volley actually launches
## inside a synchronous test. `Telegraph.advance` is the documented seam for this —
## `Hero._telegraphed_ability`'s own header says the tell IS the clock precisely so
## headless suites can step it without frames passing.
func _press_and_resolve(hero: CharacterBody2D) -> Node:
	var tells_before: Dictionary = _tell_ids()
	var volleys_before: Dictionary = _volley_ids()
	hero.set("_cast_cooldown_timer", 0.0)
	hero.call("_cast")
	var tell: Node = _new_tell(tells_before)
	if tell != null:
		tell.call("advance", 0.2)   # past ABILITY_TELL_LEAD (0.10)
	return _new_volley(volleys_before)


# ─────────────────────────────────────────────────────── 1. the shape changed
## ⚠ DESIGNED TO FAIL ON THE PRE-CHANGE CODE. Restore `"primary": "frost_cone"` in
## `Hero.CLASS_CONFIG` and the first assertion goes red; restore `Style.CONE` in
## `_primary_frost_shards` and the second does. Verified by doing exactly that.
func _test_the_primary_is_a_shard_volley_not_a_cone() -> void:
	var hero: CharacterBody2D = _make_hero()
	_require_surface(hero)
	await physics_frame
	_expect(String((hero.get("_cfg") as Dictionary).get("primary", "bolt")) == "frost_shards",
		"the Cryomancer's LMB is `frost_shards` (got `%s`) — the cone the maker called "
		% String((hero.get("_cfg") as Dictionary).get("primary", "bolt"))
		+ "\"weird and too big\" is gone")
	var tells_before: Dictionary = _tell_ids()
	hero.set("_cast_cooldown_timer", 0.0)
	hero.call("_cast")
	var tell: Node = _new_tell(tells_before)
	if tell == null:
		_expect(false, "the press still publishes a telegraph at all — a basic attack "
			+ "with nothing to perceive is what the cone's tell was added to fix")
	else:
		_expect(int(tell.get("style")) == Telegraph.Style.LANE,
			"the tell is a LANE (got style %d) — the drawn shape must be the damaging "
			% int(tell.get("style"))
			+ "shape, and a wedge describing a straight volley is exactly the drift "
			+ "the cone's tell was fixed to stop")
		var shape: Dictionary = tell.call("danger_shape")
		_expect(String(shape.get("shape", "")) == "line",
			"...and it PUBLISHES itself as a line (got `%s`), which is the only shape "
			% String(shape.get("shape", ""))
			+ "besides `circle` that BotDodge branches on")
		_expect(not shape.has("cone"),
			"...and no longer carries a `cone` block — nothing downstream should still "
			+ "be told this attack is a wedge")
	# ⚠ ONE SHAPE PER PRESS. Two classes shipped basic attacks that drew TWO
	# attack-shaped things and the maker reported it as "two attacks".
	var extra: int = 0
	for n: Node in get_nodes_in_group(&"telegraph"):
		if is_instance_valid(n) and not tells_before.has(n.get_instance_id()):
			extra += 1
	_expect(extra == 1,
		"exactly ONE telegraph per press (saw %d) — no garnish shape alongside the tell"
		% extra)
	hero.queue_free()
	await physics_frame
	_completes("the_primary_is_a_shard_volley_not_a_cone")


# ───────────────────────────────────────── 2. the lane IS the flown corridor
## The tell may not describe a corridor the shards do not fly down, in either
## direction: too narrow under-warns (health somebody was promised), too wide
## over-warns (a dodge nobody needed). This asserts the lane is derived from
## `FrostShards`' own constants, not restated next to them.
func _test_the_drawn_lane_is_the_flown_corridor() -> void:
	var hero: CharacterBody2D = _make_hero()
	await physics_frame
	var tells_before: Dictionary = _tell_ids()
	hero.set("_cast_cooldown_timer", 0.0)
	hero.call("_cast")
	var tell: Node = _new_tell(tells_before)
	if tell == null:
		_expect(false, "the press publishes a tell to measure")
	else:
		var shape: Dictionary = tell.call("danger_shape")
		var from: Vector2 = shape.get("from", Vector2.ZERO)
		var to: Vector2 = shape.get("to", Vector2.ZERO)
		var want_len: float = FrostShards.MAX_RANGE
		var want_w: float = 2.0 * (FrostShards.MAX_RANGE * sin(FrostShards.FAN_SPREAD)
			+ FrostShards.HIT_RADIUS)
		_expect(absf(from.distance_to(to) - want_len) < 0.5,
			"the lane reaches exactly MAX_RANGE (%.1f vs %.1f px)"
			% [from.distance_to(to), want_len])
		_expect(absf(float(shape.get("width", -1.0)) - want_w) < 0.5,
			"the lane is as wide as the fan spreads plus a shard's hit radius "
			+ "(%.1f vs %.1f px)" % [float(shape.get("width", -1.0)), want_w])
		# Vacuity armour: a zero-length or zero-width lane would satisfy an equality
		# against constants that had also gone to zero.
		_expect(want_len > 100.0 and want_w > 10.0,
			"the corridor is a real corridor (%.0f x %.0f px)" % [want_len, want_w])
		# ⚠ AND IT IS SHORTER THAN A BOLT'S. Going from the cone's 118 px to the five
		# bolt classes' 560 would not be a re-shape, it would delete the "forces
		# mid-range" identity the cone existed to enforce.
		_expect(want_len < 560.0,
			"the volley stops short of a bolt's 560 px (%.0f) — the Cryomancer is still "
			% want_len + "a mid-range class, not a sixth bolt class")
	hero.queue_free()
	await physics_frame
	_completes("the_drawn_lane_is_the_flown_corridor")


# ────────────────────────────────────────────── 3. the shelf did not move
## THE BEFORE/AFTER NUMBER. The cone dealt 19 to every body in its arc; the volley
## deals 6 x 3 = 18 through one. This measures the DAMAGE THE DUMMY RECEIVED, not the
## constant, so a shard that spawns and never connects fails here.
func _test_a_volley_lands_the_cones_damage() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(START_X, START_Y - 60.0)   # clear of the floor
	await physics_frame
	var dummy := ShardDummy.new()
	dummy.add_to_group("enemy")
	dummy.add_to_group(SpellCaster.MORTAL_GROUP)
	root.add_child(dummy)
	# Straight down the aim, well inside MAX_RANGE and far enough out that all three
	# shards have converged onto the body's hit radius.
	dummy.global_position = hero.global_position + Vector2(90.0, 0.0)
	hero.set("_aim_dir", Vector2.RIGHT)
	var volley: Node = _press_and_resolve(hero)
	_expect(volley != null, "the press spawned a FrostShards volley")
	var guard: int = 0
	while is_instance_valid(volley) and guard < TRAVEL_FRAME_CAP:
		await physics_frame
		guard += 1
	_expect(dummy.hits > 0,
		"the volley actually connected (%d hits) — a spell that spawns and misses "
		% dummy.hits + "would satisfy every other assertion in this file")
	_expect(dummy.damage_taken == 18,
		"three shards through one body deal 18 (got %d) against the cone's 19 — a "
		% dummy.damage_taken + "RE-SHAPE, not a stealth buff or nerf")
	_expect(dummy.chilled > 0,
		"the shards still CHILL (%d applications) — the 2nd stack freezing is the "
		% dummy.chilled + "whole reason this class's basic attack is not a bolt")
	dummy.queue_free()
	hero.queue_free()
	await physics_frame
	_completes("a_volley_lands_the_cones_damage")


# ──────────────────────────────────────────────────── 4. pierce, exactly once
## PIERCE IS A DECISION. The cone hit every body in its 120-deg arc; a shard that
## died on the first torso would delete the ice class's crowd identity along with the
## cone's shape. The maker also complained that Crescent Rush stops dead on first
## contact. But pierce must NOT mean a shard can bill the same body twice.
func _test_a_shard_pierces_and_never_double_dips() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(START_X, START_Y - 60.0)
	await physics_frame
	var near := ShardDummy.new()
	var far := ShardDummy.new()
	for d: ShardDummy in [near, far]:
		d.add_to_group("enemy")
		d.add_to_group(SpellCaster.MORTAL_GROUP)
		root.add_child(d)
	near.global_position = hero.global_position + Vector2(70.0, 0.0)
	far.global_position = hero.global_position + Vector2(150.0, 0.0)
	hero.set("_aim_dir", Vector2.RIGHT)
	var volley: Node = _press_and_resolve(hero)
	_expect(volley != null, "the press spawned a volley to pierce with")
	var guard: int = 0
	while is_instance_valid(volley) and guard < TRAVEL_FRAME_CAP:
		await physics_frame
		guard += 1
	_expect(near.hits > 0, "the near body was hit (%d)" % near.hits)
	_expect(far.hits > 0,
		"the FAR body was hit too (%d) — the shards pierced the first torso rather "
		% far.hits + "than stopping dead on it")
	# ⚠ THE OTHER HALF. Pierce widens the attack across a crowd; it must never
	# multiply it into a single target. Three shards, three hits, 18 damage — the same
	# total the volley deals to one body standing alone.
	_expect(near.damage_taken <= 18,
		"the near body was billed at most once per shard (%d damage, %d hits) — "
		% [near.damage_taken, near.hits] + "a shard may not re-hit a body it is "
		+ "already inside on the next frame")
	_expect(far.damage_taken <= 18,
		"...and so was the far body (%d damage, %d hits)"
		% [far.damage_taken, far.hits])
	near.queue_free()
	far.queue_free()
	hero.queue_free()
	await physics_frame
	_completes("a_shard_pierces_and_never_double_dips")


# ───────────────────────────────────────────────────── 5. the slide climbs
## ⚠ THIS IS THE ASSERTION `slice_test_class_movement` COULD NOT MAKE. That suite
## checks `absf(_dash_dir.y) > 0.5` — the COMPUTED direction — and it was green
## throughout the whole period the maker was reporting "cryomancer can't dash
## upwards", because `_begin_verb_extras` set only `velocity.x` and `_travel_velocity`
## replaced `v.y` with gravity every frame. This measures `global_position`.
##
## ⚠ DESIGNED TO FAIL ON THE PRE-CHANGE CODE. Restore
## `velocity.x = slide_x * _dash_speed` and the gravity line in `_travel_velocity` and
## the rise below measures ~0 px against a floor of 60. Verified by doing exactly that.
func _test_the_ice_slide_actually_climbs() -> void:
	var hero: CharacterBody2D = _make_hero()
	await physics_frame
	_expect(String(hero.call("movement_verb_name")) == "ice_slide",
		"the class under test still carries the ice slide (got `%s`)"
		% String(hero.call("movement_verb_name")))
	hero.global_position = Vector2(START_X, START_Y)
	hero.set("velocity", Vector2.ZERO)
	hero.set("_dash_cooldown_timer", 0.0)
	hero.set("_move_dir", Vector2.UP)      # straight up — the maker's literal case
	hero.set("_aim_dir", Vector2.UP)
	var y0: float = hero.global_position.y
	hero.call("_start_dash")
	var dir: Vector2 = hero.get("_dash_dir")
	_expect(dir.y < -0.5,
		"the slide still resolves an upward direction (got %s) — this half was already "
		% str(dir) + "green before the fix, which is why it was not enough")
	var guard: int = 0
	var peak: float = y0
	while bool(hero.get("is_dashing")) and guard < TRAVEL_FRAME_CAP:
		await physics_frame
		peak = minf(peak, hero.global_position.y)
		guard += 1
	_expect(guard < TRAVEL_FRAME_CAP, "the slide terminated (%d frames)" % guard)
	var rise: float = y0 - peak
	_expect(rise > 60.0,
		"the body actually CLIMBED (%.1f px) — this is the channel the player sees, "
		% rise + "and it read ~0 for as long as _travel_velocity overwrote v.y with gravity")
	# It is a SLIDE, not a rocket: the published distance is 222 px, so a rise wildly
	# past it would mean the friction stopped being applied at all.
	var claimed: float = float(hero.call("movement_verb_distance"))
	_expect(rise <= claimed * 1.25,
		"...and it climbed no further than the verb claims (%.1f vs %.1f px) — the "
		% [rise, claimed] + "slide still BLEEDS, it did not become a flat burst")
	hero.queue_free()
	await physics_frame
	_completes("the_ice_slide_actually_climbs")


# ──────────────────────────────────────── 6. and the horizontal one is unchanged
## The regression half. Letting the slide climb must not move its distance band —
## `slice_test_class_movement` pins nine verbs against a 25% window with about 2% of
## slack in it, so a horizontal slide that got longer or shorter would take that
## suite red for a change that was only ever meant to add a plane.
func _test_the_ice_slide_still_bleeds_and_still_travels_flat() -> void:
	var hero: CharacterBody2D = _make_hero()
	await physics_frame
	hero.global_position = Vector2(START_X, START_Y)
	hero.set("velocity", Vector2.ZERO)
	hero.set("_dash_cooldown_timer", 0.0)
	hero.set("_move_dir", Vector2.RIGHT)
	hero.set("_aim_dir", Vector2.RIGHT)
	var x0: float = hero.global_position.x
	hero.call("_start_dash")
	var guard: int = 0
	while bool(hero.get("is_dashing")) and guard < TRAVEL_FRAME_CAP:
		await physics_frame
		guard += 1
	var travelled: float = absf(hero.global_position.x - x0)
	var claimed: float = float(hero.call("movement_verb_distance"))
	_expect(travelled > 100.0,
		"a flat slide still goes somewhere (%.1f px) — non-vacuousness" % travelled)
	_expect(absf(travelled - claimed) < claimed * 0.25,
		"a flat slide still lands in the published band (%.1f measured vs %.1f "
		% [travelled, claimed] + "claimed) — the 2D friction decays the MAGNITUDE at "
		+ "the old horizontal rate, so the integral is unchanged")
	hero.queue_free()
	await physics_frame
	_completes("the_ice_slide_still_bleeds_and_still_travels_flat")
