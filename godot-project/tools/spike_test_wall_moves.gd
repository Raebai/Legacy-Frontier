# Run: godot --headless --path godot-project --script tools/spike_test_wall_moves.gd
extends SceneTree
## Headless BEHAVIOURAL test for the stickman spike rig (scripts/spike/SpikeFigure.gd).
##
## The spike design spec (§9) asked for a headless stability/behaviour harness and it
## was never written — every check so far has been "render a PNG and look at it", which
## cannot tell you whether wall-slide actually descends or whether a wall-jump actually
## launches. This drives the figure through its MOVEMENT contract and asserts on
## OBSERVABLE state (world position, linear velocity, rotation, emitted signals) rather
## than on internal constants, so it survives feel-tuning of the knobs.
##
## Hard failures = the mechanic is broken. WARNs = the mechanic is wired but a
## documented-intent feature is not reachable (reported, does not fail the suite).

const FIG := preload("res://scripts/spike/SpikeFigure.gd")
const TICK: int = 120                  # spike runs its physics at 120 Hz
const REST_RIDE: float = 58.5          # SpikeFigure.RIDE_HEIGHT — resting hip height over the floor

var _fails: int = 0
var _warns: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	Engine.physics_ticks_per_second = TICK
	# A GDScript error inside a coroutine kills that coroutine silently, so quit() would
	# never fire and the harness would spin forever instead of reporting. Fail loudly.
	create_timer(240.0).timeout.connect(func() -> void:
		printerr("FAIL: harness watchdog fired — a test coroutine died before reaching the end")
		quit(1))
	_run()


func _run() -> void:
	await _t_idle_stability()
	await _t_ground_jump()
	await _t_jump_is_not_autobounce()
	await _t_wall_slide_never_sticks()
	await _t_wall_grip_persists()
	await _t_wall_jump_kicks_off()
	await _t_wall_climb_gains_height()
	await _t_coyote_ledge_jump()
	await _t_punch_cooldown()
	await _t_prone_crawl_is_slower()
	await _t_kill_settles_flat()

	for w: String in _warns:
		print("WARN: ", w)
	if _fails > 0:
		printerr("Spike wall/move tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Spike wall/move tests: all PASS (%d warnings)" % _warns.size())
		quit(0)


# ---- harness ----

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _warn(cond: bool, msg: String) -> void:
	if not cond:
		_warns.append(msg)


## floor_y = top surface of the ground (INF for none).
## wall_x  = x of a tall wall's LEFT face (INF for none).
func _world(floor_y: float, wall_x: float, floor_span_right: float = 2000.0) -> Node2D:
	var holder := Node2D.new()
	root.add_child(holder)
	if is_finite(floor_y):
		# floor centred so its right edge lands on floor_span_right (ledge tests walk off it)
		var w := 4000.0
		_rect(holder, Vector2(floor_span_right - w * 0.5, floor_y + 40.0), Vector2(w, 80.0))
	if is_finite(wall_x):
		_rect(holder, Vector2(wall_x + 200.0, -200.0), Vector2(400.0, 2400.0))
	return holder


func _rect(parent: Node2D, pos: Vector2, size: Vector2) -> void:
	var b := StaticBody2D.new()
	b.position = pos
	b.collision_layer = FIG.WORLD_LAYER
	b.collision_mask = 0
	var c := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	parent.add_child(b)


func _figure(parent: Node2D, pos: Vector2) -> Node2D:
	var f: Node2D = FIG.new()
	f.spawn_pos = pos
	parent.add_child(f)
	await physics_frame        # _ready()->_build() can be deferred to the first frame
	return f


func _torso(f: Node2D) -> RigidBody2D:
	return f._parts["torso"] as RigidBody2D


func _step(f: Node2D, frames: int, mx: float = 0.0, jump: bool = false, duck: bool = false) -> void:
	for i in frames:
		f.ctrl_move_x = mx
		f.ctrl_jump = jump
		f.ctrl_duck = duck
		await physics_frame


## release + re-press: the rig gates jumps on a RISING EDGE, so a held key is not a jump
func _jump_edge(f: Node2D, mx: float = 0.0) -> void:
	await _step(f, 3, mx, false)
	await _step(f, 1, mx, true)


func _teardown(holder: Node2D) -> void:
	holder.queue_free()
	await physics_frame
	await physics_frame


func _finite(t: RigidBody2D) -> bool:
	var p := t.global_position
	var v := t.linear_velocity
	return is_finite(p.x) and is_finite(p.y) and is_finite(v.x) and is_finite(v.y) and is_finite(t.rotation)


# ---- tests ----

func _t_idle_stability() -> void:
	var w := _world(300.0, INF)
	var f: Node2D = await _figure(w, Vector2(0, 100))
	await _step(f, 300)
	var t := _torso(f)
	_expect(_finite(t), "idle: physics went non-finite (NaN/inf) after 300 frames")
	_expect(absf(t.global_position.x) < 60.0,
		"idle: figure drifted sideways with no input (x=%.1f)" % t.global_position.x)
	var rest_y := 300.0 - REST_RIDE
	_expect(absf(t.global_position.y - rest_y) < 30.0,
		"idle: not resting at ride height (y=%.1f, expected ~%.1f)" % [t.global_position.y, rest_y])
	await _teardown(w)


func _t_ground_jump() -> void:
	var w := _world(300.0, INF)
	var f: Node2D = await _figure(w, Vector2(0, 100))
	await _step(f, 150)
	var t := _torso(f)
	var y0 := t.global_position.y
	await _jump_edge(f)
	var peak := y0
	for i in 70:
		f.ctrl_jump = false
		await physics_frame
		peak = minf(peak, t.global_position.y)
	_expect(y0 - peak > 60.0,
		"ground jump: barely left the floor (rose %.1f px, expected > 60)" % (y0 - peak))
	await _teardown(w)


func _t_jump_is_not_autobounce() -> void:
	var w := _world(300.0, INF)
	var f: Node2D = await _figure(w, Vector2(0, 100))
	await _step(f, 150)
	var t := _torso(f)
	# hold the key down for ~1.7 s — a rising-edge gate means exactly ONE launch
	var launches := 0
	var prev_vy := 0.0
	for i in 200:
		f.ctrl_move_x = 0.0
		f.ctrl_jump = true
		f.ctrl_duck = false
		await physics_frame
		var vy := t.linear_velocity.y
		if vy < -500.0 and prev_vy > -100.0:
			launches += 1
		prev_vy = vy
	_expect(launches == 1,
		"jump spam: holding the key produced %d launches (expected exactly 1)" % launches)
	await _teardown(w)


## THE regression test for the reported bug: "jump into a wall and you get stuck glued
## to the wall at the hip and don't slide down". The torso capsule is the only collider,
## so wall friction could carry the whole body's weight. Gripping must SLOW the fall,
## never stop it.
func _t_wall_slide_never_sticks() -> void:
	var w := _world(900.0, 100.0)
	var f: Node2D = await _figure(w, Vector2(86, 0))
	var t := _torso(f)
	await _step(f, 15, 1.0)                       # press into the wall, reach the slide cap
	_expect(100.0 - t.global_position.x < 20.0,
		"wall slide: never reached the wall (x=%.1f, wall face at 100)" % t.global_position.x)
	_expect(f._clinging, "wall slide: pressing into the wall did not engage the grip")
	var y1 := t.global_position.y
	await _step(f, 30, 1.0)                       # 0.25 s pinned against it
	var drop := t.global_position.y - y1
	_expect(_finite(t), "wall slide: physics went non-finite while clinging")
	_expect(drop > 12.0,
		"WALL STICK BUG: pressed into the wall and only fell %.1f px in 0.25 s — the body is glued to it" % drop)
	_expect(drop < 70.0,
		"wall slide: fell %.1f px in 0.25 s — that is free-fall, the slide cap is not applied" % drop)
	await _teardown(w)


## The grip must SURVIVE contact. The torso is barely uprighted in the air (weak gain,
## ~1.15 rad cap), so pressed against a wall it slowly tips; a capsule tilted that far
## holds the torso ORIGIN further from the wall than the side probe reaches, so wall
## detection silently drops to 0 mid-slide — after which the figure free-falls and
## wall-jump is unreachable, because the wall-jump branch is gated on `_wall_dir != 0`.
func _t_wall_grip_persists() -> void:
	var w := _world(900.0, 100.0)
	var f: Node2D = await _figure(w, Vector2(86, 0))
	var t := _torso(f)
	var lost_at := -1
	var lost_rot := 0.0
	var lost_gap := 0.0
	for i in 150:                                  # 1.25 s pressed into the wall
		f.ctrl_move_x = 1.0
		f.ctrl_jump = false
		f.ctrl_duck = false
		await physics_frame
		if i > 5 and f._wall_dir == 0 and lost_at < 0:
			lost_at = i
			lost_rot = t.rotation
			lost_gap = 100.0 - t.global_position.x
	_expect(lost_at < 0,
		("wall grip DROPS OUT after %.2f s pressed against the wall: the torso tipped to "
		+ "%.2f rad, putting its origin %.1f px from the wall face while WALL_PROBE reaches "
		+ "only %.1f px — the figure then free-falls and can no longer wall-jump")
		% [float(lost_at) / float(TICK), lost_rot, lost_gap, FIG.WALL_PROBE])
	await _teardown(w)


func _t_wall_jump_kicks_off() -> void:
	var w := _world(900.0, 100.0)
	var f: Node2D = await _figure(w, Vector2(86, 0))
	var t := _torso(f)
	await _step(f, 15, 1.0)                       # grip the wall (wall is on the RIGHT)
	var x0 := t.global_position.x
	await _jump_edge(f, 0.0)                      # not holding into it → full kick-off
	var vy := t.linear_velocity.y
	var vx := t.linear_velocity.x
	_expect(vy < -300.0,
		"wall jump: no upward launch off the wall (vy=%.1f, expected < -300)" % vy)
	_expect(vx < -120.0,
		"wall jump: no push AWAY from the wall (vx=%.1f, expected < -120)" % vx)
	await _step(f, 40, 0.0)
	var moved := x0 - t.global_position.x
	_expect(moved > 35.0,
		"wall jump: launch did not carry the body off the wall (moved %.1f px, expected > 35)" % moved)
	await _teardown(w)


## holding INTO the wall is the CLIMB kick (mostly up) — repeated kicks must gain height
func _t_wall_climb_gains_height() -> void:
	var w := _world(900.0, 100.0)
	var f: Node2D = await _figure(w, Vector2(86, 0))
	var t := _torso(f)
	await _step(f, 12, 1.0)
	var y0 := t.global_position.y
	for cycle in 4:
		await _jump_edge(f, 1.0)                  # keep pressing into the wall
		await _step(f, 26, 1.0)
	var rise := y0 - t.global_position.y
	_expect(_finite(t), "wall climb: physics went non-finite")
	_expect(rise > 40.0,
		"wall climb: 4 kicks up the wall gained only %.1f px of height (expected > 40)" % rise)
	await _teardown(w)


## Coyote time is TRACKED by the rig (_coyote is set on the ground and decays in the air).
## If it is never consumed by the jump gate, a jump pressed a frame after walking off a
## ledge is silently dropped — reported as a warning, not a hard failure.
func _t_coyote_ledge_jump() -> void:
	var w := _world(300.0, INF, 200.0)            # floor ends at x = 200
	var f: Node2D = await _figure(w, Vector2(0, 100))
	var t := _torso(f)
	await _step(f, 150)
	# run off the right-hand edge, then jump on the very next frame
	var off := false
	for i in 240:
		f.ctrl_move_x = 1.0
		f.ctrl_jump = false
		f.ctrl_duck = false
		await physics_frame
		if t.global_position.x > 206.0:
			off = true
			break
	_expect(off, "coyote: never walked off the ledge (setup failed)")
	if off:
		await _step(f, 1, 1.0, true)              # rising edge, just past the lip
		_warn(t.linear_velocity.y < -400.0,
			"coyote time is tracked (_coyote) but never consumed by the jump gate — a jump pressed just after walking off a ledge is dropped (vy=%.1f)" % t.linear_velocity.y)
	await _teardown(w)


func _t_punch_cooldown() -> void:
	var w := _world(300.0, INF)
	var f: Node2D = await _figure(w, Vector2(0, 100))
	var hits := [0]
	f.punched.connect(func(_d: Vector2) -> void: hits[0] += 1)
	await _step(f, 150)
	for i in 5:
		f.punch()                                  # mash it in a single frame
	_expect(hits[0] == 1, "punch spam: 5 clicks in one frame fired %d punches (expected 1)" % hits[0])
	await _step(f, 45)                             # > PUNCH_COOLDOWN
	f.punch()
	_expect(hits[0] == 2, "punch: a punch after the cooldown did not fire (total %d, expected 2)" % hits[0])
	await _teardown(w)


func _t_prone_crawl_is_slower() -> void:
	var w := _world(300.0, INF)
	var f: Node2D = await _figure(w, Vector2(-400, 100))
	var t := _torso(f)
	await _step(f, 150)
	var stand := await _avg_speed(f, 90, 1.0, false)
	await _step(f, 20, 0.0, false, false)
	await _step(f, 80, 0.0, false, true)           # hold duck → flop all the way to prone
	var prone_y := t.global_position.y
	_expect(prone_y > 300.0 - REST_RIDE + 22.0,
		"prone: duck-held did not flatten the body (y=%.1f, standing rest is %.1f)" % [prone_y, 300.0 - REST_RIDE])
	var crawl := await _avg_speed(f, 90, 1.0, true)
	_expect(crawl < stand * 0.85,
		"prone: crawling is not slower than running (crawl %.1f vs run %.1f px/s)" % [crawl, stand])
	_expect(crawl > 4.0, "prone: crawling does not move the body at all (%.1f px/s)" % crawl)
	await _teardown(w)


func _t_kill_settles_flat() -> void:
	var w := _world(300.0, INF)
	var f: Node2D = await _figure(w, Vector2(0, 100))
	var t := _torso(f)
	await _step(f, 150)
	f.kill()
	await _step(f, 420)
	_expect(_finite(t), "death: corpse physics went non-finite")
	_expect(absf(cos(t.rotation)) < 0.5,
		"death: corpse settled propped up instead of lying flat (|cos(rot)|=%.2f)" % absf(cos(t.rotation)))
	_expect(t.global_position.y > 300.0 - REST_RIDE + 10.0,
		"death: corpse never came down to the floor (y=%.1f)" % t.global_position.y)
	await _teardown(w)


func _avg_speed(f: Node2D, frames: int, mx: float, duck: bool) -> float:
	var t := _torso(f)
	var total := 0.0
	for i in frames:
		f.ctrl_move_x = mx
		f.ctrl_jump = false
		f.ctrl_duck = duck
		await physics_frame
		total += absf(t.linear_velocity.x)
	return total / float(frames)
