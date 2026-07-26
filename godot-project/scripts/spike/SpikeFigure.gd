class_name SpikeFigure
extends Node2D
## THROWAWAY SPIKE — physics stick fighter (Stick Fight feel).
## ONLY the torso is a physics body (a floating capsule that rides on its legs, so
## the weight is on the FEET). Arms + legs are KINEMATIC (drawn):
##  - grounded: WORLD-LOCKED feet (planted foot stays nailed down, then steps) and
##    arms that hang / pump with the stride — settled and planted.
##  - AIRBORNE: limbs go SLACK — every limb segment is a low-stiffness spring that
##    dangles under gravity, trails the body's momentum and flails with noise, and
##    the torso itself is barely uprighted so it tips with the jump (loose ragdoll,
##    no canned pose).
##  - duck HELD: the whole body flops all the way down and lies flat (prone).
##  - death: capsule torso topples free + a settle-flat bias → corpse ends prone.
## Touches no game code; delete scripts/spike/ to remove.

const WORLD_LAYER := 1
const TORSO_LAYER := 2

# segment sizes (px) — ratios measured off Stick Fight frames (in head-diameters):
# head 1.0 · torso ~1.6 · arm total ~1.65 · leg total ~2.75 · stroke width ~0.35
const HEAD_R := 8.0             # BIG round head — the dominant landmark
const UARM_LEN := 15.5          # slightly longer arms
const FARM_LEN := 14.5
const THIGH_LEN := 22.0
const SHIN_LEN := 22.0
const LIMB_W := 5.5             # one marker-stroke width for EVERY line (torso too)

# floating-capsule support
const RIDE_HEIGHT := 58.5       # hip(12) + legs(44)*0.97 + spring sag ~4 → near-straight stand
const RIDE_HEIGHT_DUCK := 30.0  # first beat of the duck (squat) before the flop
const RIDE_PRONE := 11.0        # duck HELD → all the way down, body lying on the floor
const RIDE_SPRING := 4200.0
const RIDE_DAMP := 260.0
const RIDE_FORCE_MAX := 120000.0
const GROUND_PROBE := 34.0

# gait (world-locked feet)
const STANCE := 4.5            # half stance width at rest (near-straight column legs)
const STANCE_DUCK := 14.0      # wide frog squat while ducking
const STEP_LENGTH := 30.0      # how far ahead a foot plants when it steps
const STEP_TRIGGER := 15.0     # back foot this far behind the hip → step it forward
const STEP_LIFT := 13.0        # swing-foot lift height
const IDLE_SPEED := 14.0       # below this speed = idle (feet settle, no stepping)

# feel
const MAX_LEAN := 0.5
const RUN_LEAN := 0.16
const JUMP_CROUCH := 0.0        # Stick Fight jumps fire immediately (no wind-up crouch)
const JUMP_LOCK := 0.22
const JUMP_COOLDOWN := 0.30     # floor between jumps — can't machine-gun-mash the key
const WALL_JUMP_PUSH := 380.0   # horizontal launch when you kick off a wall
const WALL_JUMP_UP := 660.0     # vertical launch when you kick off a wall
const WALL_PROBE := 26.0        # reach far enough that a tilted torso still finds the wall (was 15 — grip dropped out)
const WALL_SLIDE_SPEED := 130.0 # max fall speed while clinging a wall (time to wall-jump)
const WALL_SLIDE_MIN := 55.0    # min slide speed while clinging — never fully glue/hover on a wall
const WALL_JUMP_LOCK := 0.15    # input lockout after a wall-jump so holding-into-wall can't eat the launch
const PUNCH_COOLDOWN := 0.26    # min time between punches — no momentum-fly from spamming
const STAGGER_TIME := 0.4
# AIR-DASH (ported from Hero.gd): burst toward aim/move, air-capable, i-frames for
# the whole dash (is_dashing gates hit()), ghost afterimages on a fixed cadence.
const DASH_SPEED := 620.0
const DASH_TIME := 0.14
const DASH_COOLDOWN := 0.6
const GHOST_INTERVAL := 0.03
const GHOST_COLOR := Color(0.6, 0.85, 1.0, 0.55)
# PARRY/DEFLECT (ported from Hero.gd): short active window; a bolt arriving inside
# it is reflected toward the aim with a ding + a directional shield-arc shell tell.
const PARRY_WINDOW := 0.16
const PARRY_COOLDOWN := 0.9
const PARRY_SHIELD_TIME := 0.26
const PARRY_REACH := 40.0       # shield-arc radius = the deflect catch radius
const PARRY_COLOR := Color(0.85, 1.0, 1.0)
const CAST_TIME := 0.3          # brief two-handed channel pose (Phase 2 windups stack on top)
const BOLT_HIT_RADIUS := 17.0   # unparried incoming bolt connects at this range
const CRAWL_FACTOR := 0.34      # prone crawl speed as a fraction of walk speed
const PUNCH_TIME := 0.22
const NECK_Y := -14.0           # torso top (head blob sits just above)
const SHOULDER_OFF := Vector2(0, -10)   # arms emerge a bit below the neck (clean round head)
const SHOULDER_DX := 0.5                # arms leave from the torso CENTER line (single-stroke shoulder)
const HIP_OFF := Vector2(0, 12)
# arm spring — grounded arms follow their target with a little physics (lag + slight
# overshoot); the forearm lags the upper arm for a double-jointed, alive feel
const ARM_STIFF := 150.0
const ARM_DAMP := 11.0
const FARM_STIFF := 100.0
const FARM_DAMP := 9.0
# AIRBORNE limbs = slack ragdoll: barely any stiffness, low damping, noise flail
const ARM_AIR_STIFF := 26.0
const ARM_AIR_DAMP := 2.0
const FARM_AIR_STIFF := 45.0
const FARM_AIR_DAMP := 2.5
const LEG_AIR_STIFF := 26.0
const LEG_AIR_DAMP := 2.2
const SHIN_AIR_STIFF := 60.0
const SHIN_AIR_DAMP := 3.0
const FLAIL_NOISE := 7.0        # rad/s^2 of pseudo-random airborne limb churn

# live-tunable knobs (kept for the controller; arms/legs are kinematic now)
var stiffness := 3000.0
var damping := 90.0
var max_torque := 14000.0
var air_factor := 0.2
var grav_scale := 2.0
var jump_speed := 700.0         # jump HEIGHT — tunable (knob 6)
var move_speed := 300.0
var move_force := 3400.0
var upright_k := 55000.0
var upright_d := 6000.0
var punch_lunge := 3400.0       # punch DRAGS the whole body that way (momentum lunge, was 2400) — tunable

# config
var spawn_pos := Vector2.ZERO
var body_color := Color(0.93, 0.51, 0.51)

# control inputs
var ctrl_move_x := 0.0
var ctrl_jump := false
var ctrl_duck := false
var ctrl_aim := Vector2.ZERO
var ctrl_aim_hold := false      # LMB held → arms track the cursor
var dead := false

var _parts := {}               # {"torso": RigidBody2D} — controller compat
var _torso: RigidBody2D
var _ground_ray: RayCast2D
var _wall_ray_l: RayCast2D
var _wall_ray_r: RayCast2D
var _wall_dir := 0              # -1 = wall on the LEFT, +1 = wall on the RIGHT, 0 = none
var _wall_x := 0.0             # x of the touching wall face (valid when _wall_dir != 0)
var _wj_lock := 0.0           # input-lockout timer after a wall-jump
var _clinging := false        # gripping a wall this frame (airborne + pressing into it)
var _wall_dust_t := 0.0       # wall-slide dust cadence
var _arm_line: Array = []       # two Line2D (drawn in front of the torso)
var _facing := 1.0
var _arm_ang := [0.0, 0.0]       # sprung upper-arm world angles
var _arm_vel := [0.0, 0.0]
var _farm_ang := [0.0, 0.0]      # sprung (lagging) forearm world angles
var _farm_vel := [0.0, 0.0]
# sprung LEG state — only drives the legs while AIRBORNE (dangling ragdoll);
# grounded frames re-sync it from the gait IK so takeoff starts from the real pose
var _leg_ang := [PI * 0.5, PI * 0.5]
var _leg_vel := [0.0, 0.0]
var _shin_ang := [PI * 0.5, PI * 0.5]
var _shin_vel := [0.0, 0.0]
var _flail_seed := [0.0, 0.0]

# gait state
var _gait_ready := false
var _plant := [Vector2.ZERO, Vector2.ZERO]   # world plant positions
var _swing_foot := 0
var _swing_t := 1.0                          # 1.0 = both planted
var _swing_from := Vector2.ZERO
var _swing_to := Vector2.ZERO
var _foot := [Vector2.ZERO, Vector2.ZERO]     # rendered foot positions
var _knee := [Vector2.ZERO, Vector2.ZERO]

var _cur_ride := RIDE_HEIGHT
var _lean_cap := MAX_LEAN
var _duck_t := 0.0              # 0 = standing … 1 = fully prone (duck held)
var _coyote := 0.0
var _jump_crouch := 0.0
var _jump_lock := 0.0
var _pending_jump := false
var _jump_held_prev := false   # last frame's jump input — for rising-edge detection
var _jump_cd := 0.0            # cooldown timer between jumps
var _punch_timer := 0.0
var _punch_cd := 0.0            # punch cooldown (anti-spam)
var _grounded := false          # cached this frame — punch shove only when planted
var _punch_ang := 0.0
var _stagger := 0.0
var _clock := 0.0
var _was_air := false
var _last_floor_y := 0.0
var _peak_fall := 0.0           # fastest downward speed this airtime — scales the land thud

# dash state
var is_dashing := false
var _dash_timer := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector2.RIGHT
var _ghost_t := 0.0

# parry state
var _parry_window := 0.0
var _parry_cd := 0.0
var _parry_shell_t := 0.0
var _parry_dir := Vector2.RIGHT

# cast state
var _cast_timer := 0.0
var _cast_ang := 0.0
var _cast_pose := CastStyle.Pose.POINT   # body language for the windup in progress

# shared speed-line resources (built once)
static var _streak_mat: CanvasItemMaterial = null
static var _streak_curve: Curve = null


signal punched(dir: Vector2)
signal casting(dir: Vector2)
signal parried(world_pos: Vector2)   # a bolt was deflected — controller adds the camera juice


func _ready() -> void:
	_flail_seed = [randf() * TAU, randf() * TAU]
	_build()


func _build() -> void:
	var o := spawn_pos
	_torso = RigidBody2D.new()
	_torso.name = "torso"
	_torso.mass = 8.0
	_torso.can_sleep = false
	add_child(_torso)
	# CAPSULE collider — rounded ends can't prop the corpse up on a rect corner,
	# so a dead body always rolls flat instead of settling semi-seated
	_torso.add_child(_capsule_col(6.5, 40.0, Vector2(0, -2)))
	_torso.position = o
	_torso.gravity_scale = grav_scale
	_torso.collision_layer = TORSO_LAYER
	_torso.collision_mask = WORLD_LAYER
	_torso.angular_damp = 8.0
	_torso.linear_damp = 0.3
	_torso.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	# FRICTIONLESS surface — pressing into a wall must never GLUE the capsule there; with zero
	# friction it slides down under gravity (capped by WALL_SLIDE_SPEED) instead of sticking
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0
	pm.bounce = 0.0
	_torso.physics_material_override = pm
	_torso.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	_torso.center_of_mass = Vector2(0, 14)
	_add_line(_torso, Vector2(0, NECK_Y), Vector2(0, HIP_OFF.y), LIMB_W)
	# head blob barely overlaps the neck — reads as a clean CIRCLE on a thin neck
	_add_circle(_torso, Vector2(0, NECK_Y - HEAD_R + 0.5), HEAD_R)
	_parts["torso"] = _torso

	_ground_ray = RayCast2D.new()
	_ground_ray.target_position = Vector2(0, RIDE_HEIGHT + GROUND_PROBE)
	_ground_ray.collision_mask = WORLD_LAYER
	add_child(_ground_ray)

	# side feelers for wall-cling / wall-jump
	_wall_ray_l = RayCast2D.new()
	_wall_ray_l.target_position = Vector2(-WALL_PROBE, 0)
	_wall_ray_l.collision_mask = WORLD_LAYER
	add_child(_wall_ray_l)
	_wall_ray_r = RayCast2D.new()
	_wall_ray_r.target_position = Vector2(WALL_PROBE, 0)
	_wall_ray_r.collision_mask = WORLD_LAYER
	add_child(_wall_ray_r)

	# arm lines are children added AFTER the torso, so they draw in front of the body
	for i in 2:
		var ln := Line2D.new()
		ln.width = LIMB_W
		ln.default_color = body_color
		ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ln.end_cap_mode = Line2D.LINE_CAP_ROUND
		ln.joint_mode = Line2D.LINE_JOINT_ROUND
		add_child(ln)
		_arm_line.append(ln)


func _capsule_col(radius: float, height: float, off: Vector2) -> CollisionShape2D:
	var c := CollisionShape2D.new()
	var s := CapsuleShape2D.new()
	s.radius = radius
	s.height = height
	c.shape = s
	c.position = off
	return c


func _add_line(body: Node2D, a: Vector2, b: Vector2, w: float) -> void:
	var ln := Line2D.new()
	ln.points = PackedVector2Array([a, b])
	ln.width = w
	ln.default_color = body_color
	ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ln.end_cap_mode = Line2D.LINE_CAP_ROUND
	body.add_child(ln)


func _add_circle(body: Node2D, center: Vector2, radius: float) -> void:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 22:
		pts.append(center + Vector2.from_angle(TAU * i / 22.0) * radius)
	poly.polygon = pts
	poly.color = body_color
	body.add_child(poly)


func configure(k: Dictionary) -> void:
	stiffness = k.get("stiffness", stiffness)
	damping = k.get("damping", damping)
	max_torque = k.get("max_torque", max_torque)
	air_factor = k.get("air_factor", air_factor)
	grav_scale = k.get("grav_scale", grav_scale)
	jump_speed = k.get("jump_speed", jump_speed)
	move_speed = k.get("move_speed", move_speed)
	move_force = k.get("move_force", move_force)
	upright_k = k.get("upright_k", upright_k)
	upright_d = k.get("upright_d", upright_d)
	punch_lunge = k.get("punch_lunge", punch_lunge)
	if _torso != null:
		_torso.gravity_scale = grav_scale


# ---- actions ----

func punch() -> void:
	if _punch_cd > 0.0:
		return                     # still cooling down — ignore the spam-click
	_punch_cd = PUNCH_COOLDOWN
	_punch_timer = PUNCH_TIME
	var sh: Vector2 = _torso.to_global(SHOULDER_OFF)
	var dir := (ctrl_aim - sh).normalized() if ctrl_aim != Vector2.ZERO else Vector2(_facing, 0)
	_punch_ang = dir.angle()
	_facing = 1.0 if dir.x >= 0.0 else -1.0        # turn toward the punch (click)
	# ONE arm punches (the aim-side arm) — snap it out toward the punch
	var lead := 0 if _facing >= 0.0 else 1
	var err := wrapf(_punch_ang - _arm_ang[lead], -PI, PI)
	_arm_vel[lead] += err * 20.0
	_farm_vel[lead] += err * 20.0
	# body MOMENTUM — the punch shoves you: a solid shove PLANTED, still a real half-shove in
	# the air (but the punch cooldown + gravity keep you from spamming into flight)
	var lunge := punch_lunge if _grounded else punch_lunge * 0.5
	_torso.apply_central_impulse(dir * lunge)
	var lsh: Vector2 = _torso.to_global(Vector2(SHOULDER_DX if lead == 0 else -SHOULDER_DX, SHOULDER_OFF.y))
	var fist: Vector2 = lsh + dir * (UARM_LEN + FARM_LEN)
	_spawn_wind_streaks(fist + dir * 9.0, 9, dir, "punch")   # wind marks burst IN FRONT of the fist
	_sfx("melee_swing", -3.0, 0.1)
	punched.emit(dir)


## AIR-DASH: burst toward `dir` (8-way, vertical included — NO floor gate). Full-duration
## i-frames via the is_dashing guard in hit(); blue ghost afterimages on a fixed cadence.
func dash(dir: Vector2) -> bool:
	if dead or is_dashing or _dash_cd > 0.0:
		return false
	is_dashing = true
	_dash_timer = DASH_TIME
	_dash_cd = DASH_COOLDOWN
	_ghost_t = 0.0
	_dash_dir = dir.normalized() if dir != Vector2.ZERO else Vector2(_facing, 0)
	if absf(_dash_dir.x) > 0.15:
		_facing = signf(_dash_dir.x)
	_sfx("melee_swing", -5.0, 0.08, 0.78)            # whoosh: swing clip pitched down
	_spawn_wind_streaks(_torso.global_position, 8, _dash_dir, "dash")
	# limbs get flung by the burst — reads as a real jerk, not a glide
	for i in 2:
		_arm_vel[i] += randf_range(-5.0, 5.0)
		_leg_vel[i] += randf_range(-4.0, 4.0)
	return true


## SpellCaster's BLINK_STRIKE callback (duck-typed `blink_to`, same contract Hero
## implements): teleport to `dest` and report where we actually ended up so the cut
## is drawn to the real destination.
##
## The rig is one RigidBody2D torso with procedural limbs hanging off it, so moving
## the torso moves the whole figure — but the limbs' sprung angles are kept and
## given a jolt, so arriving reads as being YANKED through the shadow rather than
## snapping to a new spot fully composed. Velocity is cleared so you don't keep the
## momentum you had before vanishing.
func blink_to(dest: Vector2) -> Vector2:
	if dead or _torso == null:
		return _torso.global_position if _torso != null else dest
	_spawn_wind_streaks(_torso.global_position, 8, (dest - _torso.global_position).normalized(), "dash")
	_torso.global_position = dest
	_torso.linear_velocity = Vector2.ZERO
	_torso.angular_velocity = 0.0
	for i in 2:
		_arm_vel[i] += randf_range(-7.0, 7.0)
		_leg_vel[i] += randf_range(-6.0, 6.0)
	return dest


## PARRY: open the deflect window + throw up the directional shield-arc tell toward
## the aim. The reward (ding + reflect) only fires if a bolt arrives in the window —
## see _process_projectiles().
func parry() -> bool:
	if dead or _parry_cd > 0.0:
		return false
	_parry_cd = PARRY_COOLDOWN
	_parry_window = PARRY_WINDOW
	_parry_shell_t = PARRY_SHIELD_TIME
	var sh: Vector2 = _torso.to_global(SHOULDER_OFF)
	_parry_dir = (ctrl_aim - sh).normalized() if ctrl_aim != Vector2.ZERO else Vector2(_facing, 0)
	if absf(_parry_dir.x) > 0.15:
		_facing = signf(_parry_dir.x)
	# lead arm sweeps up into the guard
	var lead := 0 if _facing >= 0.0 else 1
	var err := wrapf(_parry_dir.angle() - _arm_ang[lead], -PI, PI)
	_arm_vel[lead] += err * 16.0
	_farm_vel[lead] += err * 16.0
	_sfx("melee_swing", -6.0, 0.1, 1.15)             # quick guard "swish" tell
	return true


## CAST windup toward `dir`, in one of the CastStyle.Pose body languages, plus the
## `casting` signal. Rule 4: no spell is a plain instant spawn — the pose IS the
## tell, and its length is the opponent's dodge window, so `pose` drives both how
## the body moves and how long it commits. Mirrors Hero._begin_summon's intent.
##
## The pose only seeds the impulse here; `_solve_arms` holds the shape for the
## rest of the window (see the `_cast_timer > 0.0` branch). Everything stays in
## the existing spring solver so a hit mid-cast still ragdolls out of it — a
## canned keyframe would fight the active-ragdoll direction.
func cast(dir: Vector2, pose: int = CastStyle.Pose.POINT) -> void:
	if dead:
		return
	var d := dir.normalized() if dir != Vector2.ZERO else Vector2(_facing, 0)
	_cast_pose = pose
	_cast_timer = CastStyle.duration(pose)
	_cast_ang = d.angle()
	if absf(d.x) > 0.15:
		_facing = signf(d.x)
	var throw_ang := _cast_arm_target(d)
	# Kick the arms toward the pose's line. SLAM and COIL wind the opposite way
	# first so the release has somewhere to travel from — anticipation is what
	# makes a gesture read as force rather than teleporting into position.
	var kick := 14.0
	match pose:
		CastStyle.Pose.SLAM:
			throw_ang = -PI * 0.5          # arms go OVERHEAD; the drive-down is below
			kick = 18.0
		CastStyle.Pose.COIL:
			throw_ang = d.angle() + PI     # coil back away from the aim
			kick = 20.0
		CastStyle.Pose.LASH:
			kick = 26.0                    # one sharp flick, no anticipation
	for i in 2:
		# LASH is asymmetric: only the lead arm whips, the other stays loose.
		if pose == CastStyle.Pose.LASH and i != 0:
			continue
		var err := wrapf(throw_ang - _arm_ang[i], -PI, PI)
		_arm_vel[i] += err * kick
		_farm_vel[i] += err * kick
	casting.emit(d)


## Where the arms want to END UP for a pose. SLAM resolves at the end of the
## window (the drive-down), so it is handled by _solve_arms rather than here.
func _cast_arm_target(d: Vector2) -> float:
	return d.angle()


## Defensive Sfx dispatch (via /root so spike headless tests without autoloads survive).
func _sfx(key: String, db := 0.0, pvar := 0.06, pitch := 1.0) -> void:
	var s: Node = get_node_or_null(^"/root/Sfx")
	if s != null and s.has_method(&"play"):
		s.call(&"play", key, db, pvar, pitch)


func _spawn_puffs(pos: Vector2, count: int, size: float) -> void:
	# soft lumpy dust poofs that WAFT up + out and ease-fade, plus a few dark dirt flecks kicked
	# up — the Stick-Fight "scuffed ground" look instead of flat white circles
	for i in count:
		var p := Polygon2D.new()
		var r := size * (0.55 + randf() * 0.7)
		var pts := PackedVector2Array()
		for a in 9:
			pts.append(Vector2.from_angle(TAU * a / 9.0 + randf() * 0.3) * r * randf_range(0.78, 1.2))  # lumpy, not a circle
		p.polygon = pts
		var g := randf_range(0.80, 0.94)
		p.color = Color(g, g * 0.97, g * 0.9, randf_range(0.45, 0.72))   # soft warm grey-white
		p.position = pos + Vector2(randf_range(-9.0, 9.0), randf_range(-5.0, 3.0))
		add_child(p)
		var life := randf_range(0.34, 0.54)
		var drift := Vector2(randf_range(-16.0, 16.0), randf_range(-24.0, -7.0))   # waft up + out
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", p.position + drift, life).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "scale", Vector2(2.2, 2.2), life).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 0.0, life)
		tw.chain().tween_callback(p.queue_free)
	# a few dark dirt flecks kicked out, arcing back down
	for i in 1 + count / 4:
		var f := Polygon2D.new()
		var fr := randf_range(1.4, 2.9)
		f.polygon = PackedVector2Array([Vector2(-fr, -fr), Vector2(fr, -fr), Vector2(fr, fr), Vector2(-fr, fr)])
		f.color = Color(0.24, 0.2, 0.16, 0.92)
		f.position = pos + Vector2(randf_range(-5.0, 5.0), -2.0)
		add_child(f)
		var fdr := Vector2(randf_range(-60.0, 60.0), randf_range(-40.0, -12.0))   # out + up, then the +y settles it down
		var flife := randf_range(0.3, 0.5)
		var twf := create_tween()
		twf.set_parallel(true)
		twf.tween_property(f, "position", f.position + fdr + Vector2(0, 34.0), flife).set_ease(Tween.EASE_OUT)
		twf.tween_property(f, "modulate:a", 0.0, flife)
		twf.chain().tween_callback(f.queue_free)


## Stick-Fight-crisp SPEED-LINES: tapered (thick root -> needle tip via width_curve),
## gently bowed along the travel arc, additive-blended, subtly tinted per action,
## darting along the motion and gone in a blink. Flavors:
##   "punch" — warm, tight fast cone ahead of the fist
##   "jump"  — cool + airy upward fan from the feet
##   "wall"  — cool kick-off spray along the wall-jump launch
##   "hit"   — warm scattered shock ticks around the impact
##   "dash"  — cool long streaks trailing the dash line
func _spawn_wind_streaks(pos: Vector2, count: int, bias := Vector2.ZERO, flavor := "") -> void:
	var directional := bias != Vector2.ZERO
	var base_ang := bias.angle() if directional else 0.0
	var tint := Color(0.92, 0.95, 1.0)          # faint cool default (never flat white)
	var spread := 0.7
	var len_min := 20.0
	var len_max := 44.0
	var dart_min := 34.0
	var dart_max := 66.0
	var life := 0.17
	match flavor:
		"punch":
			tint = Color(1.0, 0.87, 0.7)
			spread = 0.34
			len_min = 26.0; len_max = 56.0
			dart_min = 60.0; dart_max = 110.0
			life = 0.13
		"jump":
			tint = Color(0.8, 0.9, 1.0)
			spread = 0.5
			len_min = 24.0; len_max = 48.0
			dart_min = 40.0; dart_max = 76.0
			life = 0.22
		"wall":
			tint = Color(0.8, 0.9, 1.0)
			spread = 0.42
			len_min = 20.0; len_max = 44.0
			dart_min = 46.0; dart_max = 86.0
			life = 0.16
		"hit":
			tint = Color(1.0, 0.82, 0.66)
			spread = 1.35                       # scattered — a shock splash, not a cone
			len_min = 13.0; len_max = 30.0
			dart_min = 44.0; dart_max = 84.0
			life = 0.13
		"dash":
			tint = Color(0.7, 0.86, 1.0)
			spread = 0.26
			len_min = 30.0; len_max = 62.0
			dart_min = 44.0; dart_max = 92.0
			life = 0.16
	for i in count:
		var ang := (base_ang + randf_range(-spread, spread)) if directional else (randf() * TAU)
		var d := Vector2.from_angle(ang)
		var n := d.orthogonal()
		var seg := randf_range(len_min, len_max)
		var bow := randf_range(0.05, 0.16) * seg * (1.0 if randf() < 0.5 else -1.0)
		var ln := Line2D.new()
		# 6 points root->tip, bowed sideways (peak mid-line) → a motion ARC, not a spike
		var pts := PackedVector2Array()
		for s_i in 6:
			var t := s_i / 5.0
			pts.append(d * (t - 0.35) * seg + n * bow * sin(t * PI))
		ln.points = pts
		ln.width = randf_range(3.2, 5.6)
		ln.width_curve = _streak_width_curve()   # thick root -> needle tip (the taper)
		ln.material = _streak_material()         # additive — glows over the scene
		ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ln.end_cap_mode = Line2D.LINE_CAP_ROUND
		ln.joint_mode = Line2D.LINE_JOINT_ROUND
		ln.default_color = Color(tint.r, tint.g, tint.b, randf_range(0.55, 0.9))
		# scatter along + across the action direction (mostly ahead of it)
		var off := (d * randf_range(-4.0, 15.0) + n * randf_range(-11.0, 11.0)) if directional else Vector2(randf_range(-17.0, 17.0), randf_range(-15.0, 15.0))
		ln.position = pos + off
		add_child(ln)
		var this_life := life * randf_range(0.8, 1.2)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(ln, "position", ln.position + d * randf_range(dart_min, dart_max), this_life * 1.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(ln, "modulate:a", 0.0, this_life)
		tw.chain().tween_callback(ln.queue_free)


static func _streak_material() -> CanvasItemMaterial:
	if _streak_mat == null:
		_streak_mat = CanvasItemMaterial.new()
		_streak_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _streak_mat


static func _streak_width_curve() -> Curve:
	if _streak_curve == null:
		_streak_curve = Curve.new()
		_streak_curve.add_point(Vector2(0.0, 1.0))
		_streak_curve.add_point(Vector2(0.55, 0.5))
		_streak_curve.add_point(Vector2(1.0, 0.05))
	return _streak_curve


## A HIT: knocked back + flinch, stays standing, recovers. (Only kill() floors it.)
## Dashing = i-frames: the whole DASH_TIME window shrugs hits off.
func hit(dir: Vector2, strength: float) -> void:
	if is_dashing:
		return
	_stagger = STAGGER_TIME
	_torso.apply_central_impulse(dir * strength)
	_spawn_wind_streaks(_torso.to_global(SHOULDER_OFF) - dir * 6.0, 6, dir, "hit")
	# hits rattle the limbs loose too
	for i in 2:
		_arm_vel[i] += randf_range(-6.0, 6.0)
		_farm_vel[i] += randf_range(-5.0, 5.0)


func kill() -> void:
	dead = true
	_torso.collision_mask = WORLD_LAYER
	# real limp flop: let the torso spin + topple freely (no more uprighting)
	_torso.angular_damp = 0.6
	_torso.linear_damp = 0.1
	_torso.apply_central_impulse(Vector2(-_facing * 200.0, -320.0))
	_torso.apply_torque_impulse(8000.0 * (1.0 if randf() < 0.5 else -1.0))
	# drop the bottom-heavy balance: a live fighter is weighted to stand back up,
	# a corpse isn't — centered mass lets the capsule roll flat instead of
	# self-righting into a seated prop
	_torso.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_AUTO
	for i in 2:
		_arm_vel[i] += randf_range(-8.0, 8.0)
		_farm_vel[i] += randf_range(-6.0, 6.0)
	_spawn_puffs(_torso.global_position, 3, 8.0)    # knock-out poof (kept sparse)


# ---- per-frame ----

func _physics_process(delta: float) -> void:
	_punch_timer = maxf(0.0, _punch_timer - delta)
	_punch_cd = maxf(0.0, _punch_cd - delta)
	_jump_lock = maxf(0.0, _jump_lock - delta)
	_wj_lock = maxf(0.0, _wj_lock - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_parry_window = maxf(0.0, _parry_window - delta)
	_parry_cd = maxf(0.0, _parry_cd - delta)
	_parry_shell_t = maxf(0.0, _parry_shell_t - delta)
	_cast_timer = maxf(0.0, _cast_timer - delta)
	_clock += delta
	# FACE the way you actually MOVE (real velocity), not the raw key: no snap-turn on a
	# tap, you feel resistance (pinned on a wall = no motion = no turn), and a prone body
	# (duck held) never auto-swaps facing when you press left/right.
	if _duck_t < 0.35 and absf(_torso.linear_velocity.x) > 24.0:
		_facing = signf(_torso.linear_velocity.x)
	if _stagger > 0.0:
		_stagger -= delta

	var torso := _torso
	_ground_ray.global_position = torso.global_position
	_ground_ray.force_raycast_update()
	var hitg := _ground_ray.is_colliding()
	# side feelers → which side (if any) a wall is on, for wall-jump
	_wall_ray_l.global_position = torso.global_position
	_wall_ray_r.global_position = torso.global_position
	_wall_ray_l.force_raycast_update()
	_wall_ray_r.force_raycast_update()
	_wall_dir = -1 if _wall_ray_l.is_colliding() else (1 if _wall_ray_r.is_colliding() else 0)
	if _wall_dir > 0:
		_wall_x = _wall_ray_r.get_collision_point().x
	elif _wall_dir < 0:
		_wall_x = _wall_ray_l.get_collision_point().x
	var floor_y: float = _ground_ray.get_collision_point().y if hitg else torso.global_position.y + _cur_ride
	var dist := floor_y - torso.global_position.y
	var grounded := hitg and dist <= _cur_ride + 12.0 and _jump_lock <= 0.0
	_grounded = grounded
	# WALL CLING — press into a wall while airborne and you grip it (slow fall) with scuff dust,
	# so there's time to wall-jump off/up it instead of dropping past it instantly
	_clinging = not grounded and _wall_dir != 0 and signf(ctrl_move_x) == float(_wall_dir)
	if _clinging:
		# ALWAYS slide while clinging (never glue): hold descent between a gentle min and the cap
		if torso.linear_velocity.y >= 0.0:
			torso.linear_velocity.y = clampf(torso.linear_velocity.y, WALL_SLIDE_MIN, WALL_SLIDE_SPEED)
		if torso.linear_velocity.y > 25.0:                 # sliding down → scuff dust off the wall face
			_wall_dust_t -= delta
			if _wall_dust_t <= 0.0:
				_wall_dust_t = 0.09
				_spawn_puffs(Vector2(_wall_x, torso.global_position.y + 8.0), 2, 4.0)
	if hitg:
		_last_floor_y = floor_y
	# HARD backstop — never sink through the floor. ONLY clamp when there is ACTUALLY ground
	# right below this frame (hitg); otherwise a stale floor height would pin you floating in
	# mid-air after you step off a ledge.
	if hitg and _last_floor_y > 0.0 and torso.global_position.y > _last_floor_y - 2.0:
		var p := torso.global_position
		p.y = _last_floor_y - 2.0
		torso.global_position = p
		if torso.linear_velocity.y > 0.0:
			torso.linear_velocity.y = 0.0
	if not grounded:
		_peak_fall = maxf(_peak_fall, torso.linear_velocity.y)   # fastest drop → land thud weight
	if grounded and _was_air and not dead:
		_spawn_puffs(Vector2((_foot[0].x + _foot[1].x) * 0.5, _last_floor_y), 7, 6.0)   # LANDING dust AT the floor
		if _peak_fall > 140.0:                                   # real fall, not a step off a curb
			var impact := clampf(_peak_fall / 900.0, 0.0, 1.0)
			_sfx("footstep", lerpf(-10.0, -1.0, impact), 0.1, lerpf(0.8, 0.6, impact))   # deeper+louder with speed
		_peak_fall = 0.0
	_was_air = not grounded
	if grounded:
		_coyote = 0.12
	else:
		_coyote = maxf(0.0, _coyote - delta)

	# duck HELD ramps the flop: squat first, then all the way down to prone.
	# NOTE: gate on "near the ground" (standing sense), NOT the tight grounded flag —
	# while the body drops toward prone height the tight flag flickers false and
	# would stall the flop halfway.
	var near_ground := hitg and dist <= RIDE_HEIGHT + 14.0
	var duck_active := ctrl_duck and not dead and _jump_lock <= 0.0 and near_ground
	_duck_t = move_toward(_duck_t, 1.0 if duck_active else 0.0, delta / 0.3)
	var ride_target := lerpf(RIDE_HEIGHT, RIDE_PRONE, _duck_t)
	if _jump_crouch > 0.0:
		ride_target = RIDE_HEIGHT_DUCK
	_cur_ride = move_toward(_cur_ride, ride_target, 520.0 * delta)

	if not dead:
		# a LIVE fighter is bottom-weighted (stands back up); flopped prone it goes
		# slack — centered mass so gravity rolls the body flat instead of balancing
		# it on the capsule end (roly-poly prop)
		var want_auto := _duck_t > 0.5
		var is_auto := _torso.center_of_mass_mode == RigidBody2D.CENTER_OF_MASS_MODE_AUTO
		if want_auto != is_auto:
			if want_auto:
				_torso.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_AUTO
			else:
				_torso.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
				_torso.center_of_mass = Vector2(0, 14)
		# loose in the air: less rotational drag so the body tips + tumbles with momentum
		_torso.angular_damp = 8.0 if grounded else 2.0

	if not dead:
		if is_dashing:
			_process_dash(torso, delta)          # dash OWNS the velocity — no spring/move/jump
		else:
			var controlled := _stagger <= 0.0
			_support(torso, grounded, dist, delta)
			if controlled:
				_move(torso)
				_do_jump(torso, grounded, delta)
		_process_projectiles()
	else:
		_corpse_settle(torso)
	_update_arms(torso, delta)
	_update_legs(torso, floor_y, grounded, delta)
	_jump_held_prev = ctrl_jump   # track input edge for next frame's jump gate
	queue_redraw()


func _support(torso: RigidBody2D, grounded: bool, dist: float, delta: float) -> void:
	# keep supporting the body even when prone — the ride height drops to RIDE_PRONE so
	# it lies LOW/flat but is still held just above the floor (never falls through)
	if grounded and _jump_lock <= 0.0:
		var comp := _cur_ride - dist
		var f := comp * RIDE_SPRING + torso.linear_velocity.y * RIDE_DAMP
		f = clampf(f, 0.0, RIDE_FORCE_MAX)
		if f > 0.0:
			torso.apply_central_force(Vector2(0, -f))
	var lean := clampf(torso.linear_velocity.x / move_speed, -1.0, 1.0) * RUN_LEAN
	var cap := MAX_LEAN
	var gain := 1.0
	if not grounded and _clinging:
		# clinging a wall: keep the body UPRIGHT (firm uprighting, tight cap) so it doesn't
		# tip over and pull the hip out of wall-probe range — that's what dropped the grip
		gain = 0.55
		cap = 0.4
		lean = float(_wall_dir) * 0.12
	elif not grounded:
		# AIRBORNE: barely uprighted — the whole body tips with its momentum and only
		# slowly rights itself, like a loose ragdoll that happens to land feet-first
		gain = 0.09
		cap = 1.15
		lean = clampf(torso.linear_velocity.x / move_speed, -1.0, 1.0) * 0.68
	elif _duck_t > 0.02:
		# duck-flop: the lean target itself rotates the whole body down flat (prone)
		lean = _facing * 1.42 * _duck_t
		cap = MAX_LEAN + 1.35 * _duck_t
	elif absf(ctrl_move_x) > 0.1:
		# (grounded, not ducking) lean scales with how much you're HELD BACK: a free run is
		# a light lean; pushing into a wall/obstacle (input but little motion) is a strong
		# lean INTO it → you visibly strain against whatever is in the way
		var resist := clampf((ctrl_move_x * move_speed - torso.linear_velocity.x) / move_speed, -1.0, 1.0)
		lean = clampf(torso.linear_velocity.x / move_speed, -1.0, 1.0) * RUN_LEAN + resist * RUN_LEAN * 1.6
	_lean_cap = move_toward(_lean_cap, cap, 5.0 * delta)    # cap eases → no landing snap
	var err := wrapf(lean - torso.rotation, -PI, PI)
	torso.apply_torque((upright_k * err - upright_d * torso.angular_velocity) * gain)
	if absf(torso.rotation) > _lean_cap:
		torso.rotation = clampf(torso.rotation, -_lean_cap, _lean_cap)
		torso.angular_velocity = 0.0


func _corpse_settle(torso: RigidBody2D) -> void:
	# once the corpse has mostly stopped, bias it toward lying FLAT (nearest ±90°)
	# so it never balances propped on a collider end — always ends prone
	if torso.linear_velocity.length() > 60.0 or absf(torso.angular_velocity) > 6.0:
		return
	if not _ground_ray.is_colliding():
		return
	var r := wrapf(torso.rotation, -PI, PI)
	var tgt := PI * 0.5 if r >= 0.0 else -PI * 0.5
	torso.apply_torque(60000.0 * (tgt - r) - 9000.0 * torso.angular_velocity)


func _move(torso: RigidBody2D) -> void:
	if _wj_lock > 0.0:
		return                     # brief lockout after a wall-jump so the launch isn't cancelled by holding into the wall
	var spd := move_speed
	if _duck_t > 0.4:
		spd = move_speed * CRAWL_FACTOR   # DOWN + left/right while prone = slow CRAWL along the ground
	var target := ctrl_move_x * spd
	var vx := torso.linear_velocity.x
	torso.apply_central_force(Vector2((target - vx) * move_force * 0.02, 0))


func _do_jump(torso: RigidBody2D, grounded: bool, delta: float) -> void:
	_jump_cd = maxf(0.0, _jump_cd - delta)
	# RISING EDGE only: you must release + re-press for each jump (no hold-to-auto-bounce),
	# and the cooldown stops rapid mashing → no jump spam.
	var edge := ctrl_jump and not _jump_held_prev
	if edge and grounded and _jump_cd <= 0.0 and not _pending_jump:
		_pending_jump = true
		_jump_crouch = JUMP_CROUCH
		_coyote = 0.0
	elif edge and not grounded and _wall_dir != 0:
		# WALL JUMP — no long cooldown (you leave the wall, so no spam-in-place). ADAPTIVE:
		# holding INTO the wall = a CLIMB kick (mostly UP, small push) so you scale the same
		# wall; otherwise a full KICK-OFF (UP + strong AWAY). The input lockout below keeps the
		# launch from being eaten by a held direction.
		var into := absf(ctrl_move_x) > 0.1 and signf(ctrl_move_x) == float(_wall_dir)
		var away := float(-_wall_dir)
		var lv := torso.linear_velocity
		lv.x = away * WALL_JUMP_PUSH * (0.4 if into else 1.0)
		lv.y = -WALL_JUMP_UP
		torso.linear_velocity = lv
		_jump_lock = JUMP_LOCK
		_wj_lock = WALL_JUMP_LOCK
		_facing = away                                   # launch = new facing
		torso.apply_torque_impulse(away * 1600.0)        # a little kick-off spin
		for i in 2:
			_arm_vel[i] += randf_range(-6.0, 6.0)
			_leg_vel[i] += randf_range(-6.0, 6.0)
		_spawn_wind_streaks(torso.to_global(Vector2(-away * 9.0, 0)), 5, Vector2(away, -0.6), "wall")
		_sfx("melee_swing", -9.0, 0.1, 0.72)          # kick-off whoomph
	if _pending_jump:
		_jump_crouch -= delta
		if _jump_crouch <= 0.0:
			var lv := torso.linear_velocity
			lv.y = -jump_speed
			torso.linear_velocity = lv
			_jump_lock = JUMP_LOCK
			_jump_cd = JUMP_COOLDOWN
			_pending_jump = false
			# random body tip + fling every limb a RANDOM way — each jump reads
			# different, never posed
			torso.apply_torque_impulse(randf_range(-3200.0, 3200.0))
			for i in 2:
				_leg_vel[i] += randf_range(-7.0, 7.0)
				_shin_vel[i] += randf_range(-5.0, 5.0)
				_arm_vel[i] += randf_range(-6.0, 6.0)
				_farm_vel[i] += randf_range(-5.0, 5.0)
			_spawn_wind_streaks((_foot[0] + _foot[1]) * 0.5 + Vector2(0, -8.0), 9, Vector2(0, -1), "jump")
			_spawn_puffs((_foot[0] + _foot[1]) * 0.5, 6, 6.0)   # JUMP-off dust from the floor
			_sfx("melee_swing", -10.0, 0.1, 0.68)               # soft liftoff whoomph


## Dash frame: hold the burst velocity (beats gravity/spring), drop ghosts on cadence,
## then skid off the burst at the end instead of rocketing on.
func _process_dash(torso: RigidBody2D, delta: float) -> void:
	_dash_timer -= delta
	torso.linear_velocity = _dash_dir * DASH_SPEED
	torso.angular_velocity = 0.0
	_ghost_t -= delta
	if _ghost_t <= 0.0:
		_ghost_t = GHOST_INTERVAL
		_spawn_ghost()
	if _dash_timer <= 0.0:
		is_dashing = false
		torso.linear_velocity *= 0.35
		_spawn_puffs(torso.global_position + Vector2(0, RIDE_HEIGHT * 0.5), 4, 5.0)


## Blue afterimage: snapshot the CURRENT drawn pose (torso, head, arms, legs) as a
## fading world-locked ghost — the dash reads as a smear of where you were.
func _spawn_ghost() -> void:
	if _torso == null:
		return
	var g := Node2D.new()
	g.z_index = -1                                   # behind the live figure
	add_child(g)
	var neck: Vector2 = _torso.to_global(Vector2(0, NECK_Y))
	var hip: Vector2 = _torso.to_global(HIP_OFF)
	_ghost_line(g, PackedVector2Array([neck, hip]))
	var head := Polygon2D.new()
	var hc: Vector2 = _torso.to_global(Vector2(0, NECK_Y - HEAD_R + 0.5))
	var pts := PackedVector2Array()
	for i in 14:
		pts.append(hc + Vector2.from_angle(TAU * i / 14.0) * HEAD_R)
	head.polygon = pts
	head.color = GHOST_COLOR
	g.add_child(head)
	for i in 2:
		_ghost_line(g, _arm_line[i].points)
		_ghost_line(g, PackedVector2Array([hip, _knee[i], _foot[i]]))
	var tw := create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.22)
	tw.tween_callback(g.queue_free)


func _ghost_line(parent: Node2D, pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var ln := Line2D.new()
	ln.points = pts
	ln.width = LIMB_W
	ln.default_color = GHOST_COLOR
	ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ln.end_cap_mode = Line2D.LINE_CAP_ROUND
	ln.joint_mode = Line2D.LINE_JOINT_ROUND
	parent.add_child(ln)


## Incoming-bolt hookup: while the parry window is open, a hostile bolt inside the
## shield reach is REFLECTED toward the aim (ding + shell flourish + `parried`);
## otherwise a bolt that reaches the body connects (shove + burst). Dash i-frames
## let it pass clean through.
func _process_projectiles() -> void:
	if _torso == null:
		return
	var tp: Vector2 = _torso.global_position
	for p in get_tree().get_nodes_in_group("enemy_projectile"):
		if not (p is Node2D) or not is_instance_valid(p):
			continue
		if p.get("_reflected") == true:
			continue                                 # already ours — flying back out
		var pp: Vector2 = (p as Node2D).global_position
		var d := tp.distance_to(pp)
		if _parry_window > 0.0 and d <= PARRY_REACH + 10.0 and p.has_method("reflect"):
			p.call("reflect", _parry_dir, PARRY_COLOR)
			_parry_window = 0.0                      # one reflect per window
			_parry_shell_t = PARRY_SHIELD_TIME       # shell flares fresh on the connect
			_sfx("ding", 2.0, 0.02)                  # the whole payoff — crisp + loud
			_spawn_wind_streaks(pp, 7, _parry_dir, "hit")
			parried.emit(pp)
			return
		if d <= BOLT_HIT_RADIUS and not is_dashing:
			var dirv := (tp - pp).normalized()
			if dirv == Vector2.ZERO:
				dirv = Vector2(-_facing, 0.0)
			if p.has_method("consume"):
				p.call("consume")                    # its own burst + free
			hit((dirv + Vector2(0, -0.3)).normalized(), 420.0)
			return


func _update_arms(torso: RigidBody2D, delta: float) -> void:
	# arms HANG DOWN and follow physics (flail with the body); they only thrust toward
	# the cursor while punching. Facing still tracks the cursor for the punch direction.
	var vx := torso.linear_velocity.x
	var vy := torso.linear_velocity.y
	var punching := _punch_timer > 0.0
	var lead := 0 if _facing >= 0.0 else 1                    # aim-side arm does the punch
	var airborne := _jump_lock > 0.0 or absf(vy) > 60.0
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var sh: Vector2 = torso.to_global(Vector2(SHOULDER_DX * side, SHOULDER_OFF.y))
		var target: float
		var f_off := 0.0                                     # forearm rest bend (elbow)
		var stiff := ARM_STIFF
		var damp := ARM_DAMP
		var fstiff := FARM_STIFF
		var fdamp := FARM_DAMP
		if punching and i == lead:
			target = _punch_ang                              # only the lead arm thrusts
			stiff = ARM_STIFF * 4.0
			damp = ARM_DAMP * 2.0
		elif dead:
			# slack corpse arms: near-zero stiffness toward world-down → they drape
			# over whatever the torso settles into
			target = PI * 0.5
			stiff = 20.0
			damp = 2.5
			fstiff = FARM_AIR_STIFF
			fdamp = FARM_AIR_DAMP
		elif _cast_timer > 0.0:
			# CAST windup — the SHAPE depends on the pose (rule 4: no two spells are
			# thrown the same way). `prog` runs 0->1 across the window so a pose can
			# wind up and then RELEASE inside a single gesture.
			var prog: float = 1.0 - clampf(
				_cast_timer / maxf(CastStyle.duration(_cast_pose), 0.001), 0.0, 1.0)
			stiff = ARM_STIFF * 3.2
			damp = ARM_DAMP * 1.6
			match _cast_pose:
				CastStyle.Pose.SLAM:
					# Overhead, then DRIVE into the ground past halfway. The snap from
					# up to down IS the gesture — that's what sells "the earth answers".
					target = lerpf(-PI * 0.5, PI * 0.42, smoothstep(0.35, 0.85, prog))
					stiff = ARM_STIFF * (2.4 + 3.0 * prog)  # accelerates into the slam
					damp = ARM_DAMP * 1.3
				CastStyle.Pose.CIRCLE:
					# Ritual sweep: arms open OUT to frame the circle, then present it
					# forward. Capped at a half-turn spread — past that the arms swing
					# BEHIND the head and read as "hands up" instead of "drawing a ring".
					target = _cast_ang + side * lerpf(PI * 0.5, 0.24, smoothstep(0.3, 1.0, prog))
					stiff = ARM_STIFF * 2.6
					damp = ARM_DAMP * 1.8                   # slower, deliberate
				CastStyle.Pose.CHANNEL:
					# Arms UP and HELD while power gathers — the long readable tell.
					target = lerpf(_cast_ang, -PI * 0.5, 0.75) + side * 0.3
					stiff = ARM_STIFF * 2.2
					damp = ARM_DAMP * 2.2                   # very steady, no wobble
				CastStyle.Pose.COIL:
					# Pull tight to the chest, then FIRE down the aim on release.
					target = _cast_ang + (PI if prog < 0.55 else 0.0) + side * 0.1
					stiff = ARM_STIFF * 4.0                 # snappy in both directions
					damp = ARM_DAMP * 1.4
				CastStyle.Pose.LASH:
					# Asymmetric flick: the lead arm snaps out, the off arm trails loose.
					if side > 0.0:
						target = _cast_ang
						stiff = ARM_STIFF * 4.5
						damp = ARM_DAMP * 1.2
					else:
						target = _cast_ang + PI * 0.55
						stiff = ARM_STIFF * 0.8
						damp = ARM_DAMP * 0.9
				_:
					target = _cast_ang + side * 0.13        # POINT: two-handed thrust
		elif _parry_shell_t > 0.0:
			# guard: both arms hold the shield line while the shell shows
			target = _parry_dir.angle() + side * 0.2
			stiff = ARM_STIFF * 2.6
			damp = ARM_DAMP * 1.4
		elif _stagger > 0.0:
			target = atan2(-0.6, -_facing)                   # recoil back/up
		elif ctrl_aim_hold:
			target = (ctrl_aim - sh).angle()                 # HOLD click: arms track the cursor
			stiff = ARM_STIFF * 1.6
			damp = ARM_DAMP * 1.2
		elif _clinging:
			# gripping the wall — arms angle gently toward it, firm (not limp flail, not splayed)
			target = PI * 0.5 + float(_wall_dir) * 0.42 + side * 0.12
			stiff = 95.0
			damp = 6.0
			fstiff = 95.0
			fdamp = 6.0
		elif airborne:
			# AIR = SLACK: arms dangle toward world-down, trail the momentum, and
			# churn with noise — no symmetric fling, just loose ragdoll flail
			var trail := clampf(vx / 420.0, -1.0, 1.0)
			target = PI * 0.5 - trail * 0.9 + side * 0.6
			stiff = ARM_AIR_STIFF
			damp = ARM_AIR_DAMP
			fstiff = FARM_AIR_STIFF
			fdamp = FARM_AIR_DAMP
			_arm_vel[i] += (sin(_clock * (5.2 + i * 2.1) + _flail_seed[i]) \
				+ sin(_clock * (9.7 + i * 1.4) + _flail_seed[i] * 2.0)) * 7.5 * delta
		elif _duck_t > 0.05:
			# prone: arms slack toward the ground; while CRAWLING they pull toward the crawl
			# direction in alternation (dragging yourself along) instead of hanging dead
			var crawl := (clampf(absf(vx) / (move_speed * CRAWL_FACTOR), 0.0, 1.0)) if _duck_t > 0.4 else 0.0
			var dirx := signf(vx) if absf(vx) > 8.0 else _facing
			var alt := sin(_clock * 8.0 + i * PI) * 0.5 + 0.5      # 0..1, opposite per arm
			target = PI * 0.5 + side * 0.3 * (1.0 - _duck_t) + dirx * crawl * alt * 0.8
			stiff = lerpf(45.0, 120.0, crawl)
			damp = lerpf(3.5, 8.0, crawl)
			fstiff = FARM_AIR_STIFF
			fdamp = FARM_AIR_DAMP
		else:
			# grounded: hang down beside the torso; while striding the arms pump in
			# GUARANTEED anti-phase, driven by the stride openness (foot0 vs foot1)
			var spd := clampf(absf(vx) / move_speed, 0.0, 1.0)
			var stride := clampf((_foot[0].x - _foot[1].x) / (STEP_LENGTH * 1.4), -1.0, 1.0)
			var swing := stride * side * 1.05 * spd          # foot0 ahead → arm0 back, arm1 fwd
			# at rest arms hang almost straight DOWN (narrow Stick Fight silhouette,
			# just the hand caps peeking past the hips); striding opens the pump
			target = PI * 0.5 + (0.12 + 0.25 * spd) * side + swing
			f_off = -0.05 * side + swing * 0.5               # relaxed elbow; pumps with the swing
		var err := wrapf(target - _arm_ang[i], -PI, PI)
		_arm_vel[i] += err * stiff * delta
		_arm_vel[i] *= exp(-damp * delta)
		_arm_ang[i] += _arm_vel[i] * delta
		# forearm lags the upper arm (double-jointed noodle life)
		var ferr := wrapf(_arm_ang[i] + f_off - _farm_ang[i], -PI, PI)
		_farm_vel[i] += ferr * fstiff * delta
		_farm_vel[i] *= exp(-fdamp * delta)
		_farm_ang[i] += _farm_vel[i] * delta
		var elbow := sh + Vector2.from_angle(_arm_ang[i]) * UARM_LEN
		var hand := elbow + Vector2.from_angle(_farm_ang[i]) * FARM_LEN
		if _last_floor_y > 0.0:                              # never draw a hand through the floor
			elbow.y = minf(elbow.y, _last_floor_y)
			hand.y = minf(hand.y, _last_floor_y)
		elbow.x = _wall_clamp_x(elbow.x)                     # never draw an arm through a wall
		hand.x = _wall_clamp_x(hand.x)
		_arm_line[i].points = PackedVector2Array([sh, elbow, hand])


func _update_legs(torso: RigidBody2D, floor_y: float, grounded: bool, delta: float) -> void:
	var hip: Vector2 = torso.to_global(HIP_OFF)

	if dead:
		# corpse legs: feet stay world-locked where they died; as the torso topples
		# the IK folds/stretches the legs toward the old plants → dragged limp flop
		for i in 2:
			_plant[i].y = maxf(_plant[i].y, floor_y - 1.0)
			_foot[i] = _plant[i]
			_solve_knee(i, hip)
			_sync_leg_springs(i, hip)
		return

	if not grounded and _clinging:
		# WALL-CLING legs — braced against the wall (bent knees, shins toward the wall),
		# firm springs so they hold a pose instead of flailing limp
		for i in 2:
			var cside := 1.0 if i == 0 else -1.0
			var thigh_t := PI * 0.5 + float(_wall_dir) * 0.10 + cside * 0.04   # nearly straight down
			var shin_t := thigh_t + float(_wall_dir) * 0.22                    # a soft knee bend toward the wall
			_leg_vel[i] += wrapf(thigh_t - _leg_ang[i], -PI, PI) * 150.0 * delta
			_leg_vel[i] *= exp(-11.0 * delta)
			_leg_ang[i] += _leg_vel[i] * delta
			_shin_vel[i] += wrapf(shin_t - _shin_ang[i], -PI, PI) * 150.0 * delta
			_shin_vel[i] *= exp(-11.0 * delta)
			_shin_ang[i] += _shin_vel[i] * delta
			_knee[i] = hip + Vector2.from_angle(_leg_ang[i]) * THIGH_LEN
			_foot[i] = _knee[i] + Vector2.from_angle(_shin_ang[i]) * SHIN_LEN
		_plant[0] = Vector2(hip.x + STANCE, floor_y)
		_plant[1] = Vector2(hip.x - STANCE, floor_y)
		_swing_t = 1.0
		_gait_ready = true
		return

	if not grounded:
		# AIRBORNE = SLACK RAGDOLL: each leg is a barely-stiff double pendulum that
		# dangles toward world-down, trails the body's momentum, whips as the thigh
		# moves (shin lags) and churns with per-leg noise. No choreographed split.
		var trail := clampf(torso.linear_velocity.x / 420.0, -1.0, 1.0)
		var updraft := clampf(torso.linear_velocity.y / 620.0, -1.0, 1.0)
		for i in 2:
			var side := 1.0 if i == 0 else -1.0
			var target := PI * 0.5 - trail * 0.95 + side * 0.2 - updraft * 0.22 * side
			var noise := sin(_clock * (6.0 + i * 2.7) + _flail_seed[i]) \
				+ sin(_clock * (11.3 + i * 1.6) + _flail_seed[i] * 3.0)
			_leg_vel[i] += (wrapf(target - _leg_ang[i], -PI, PI) * LEG_AIR_STIFF \
				+ noise * FLAIL_NOISE) * delta
			_leg_vel[i] *= exp(-LEG_AIR_DAMP * delta)
			_leg_ang[i] += _leg_vel[i] * delta
			# shin chases the thigh with lag → knees bend from MOTION, not design
			var starget: float = _leg_ang[i] + clampf(_leg_vel[i] * 0.3, -0.9, 0.9)
			_shin_vel[i] += wrapf(starget - _shin_ang[i], -PI, PI) * SHIN_AIR_STIFF * delta
			_shin_vel[i] *= exp(-SHIN_AIR_DAMP * delta)
			_shin_ang[i] += _shin_vel[i] * delta
			_knee[i] = hip + Vector2.from_angle(_leg_ang[i]) * THIGH_LEN
			_foot[i] = _knee[i] + Vector2.from_angle(_shin_ang[i]) * SHIN_LEN
		_plant[0] = Vector2(hip.x + STANCE, floor_y)
		_plant[1] = Vector2(hip.x - STANCE, floor_y)
		_swing_t = 1.0
		_gait_ready = true
		return

	if not _gait_ready:
		_plant[0] = Vector2(hip.x + STANCE, floor_y)
		_plant[1] = Vector2(hip.x - STANCE, floor_y)
		_gait_ready = true

	var vx := torso.linear_velocity.x
	var moving := absf(vx) > IDLE_SPEED
	var walk_dir := signf(vx)

	if moving and _duck_t <= 0.25:
		if _swing_t >= 1.0:
			# step the foot that's furthest behind in the walk direction
			var behind_i := 0 if (_plant[0].x - _plant[1].x) * walk_dir <= 0.0 else 1
			if (hip.x - _plant[behind_i].x) * walk_dir > STEP_TRIGGER:
				_swing_foot = behind_i
				_swing_from = _plant[behind_i]
				_swing_to = Vector2(hip.x + walk_dir * STEP_LENGTH, floor_y)
				_swing_t = 0.0
		else:
			_swing_t += delta * lerpf(5.0, 10.0, clampf(absf(vx) / move_speed, 0.0, 1.0))
			if _swing_t >= 1.0:
				_plant[_swing_foot] = _swing_to
				_spawn_puffs(_swing_to, 2, 4.0)          # footstep dust
				_sfx("footstep", -6.0, 0.14)             # quiet tick on each plant (grounded+moving only)
	elif _duck_t > 0.25:
		# DUCK-FLOP: the feet slide out along the floor AWAY from the head, so the
		# body ends fully stretched out prone with loosely-bent legs
		_swing_t = 1.0
		var reach := lerpf(STANCE_DUCK, THIGH_LEN + SHIN_LEN - 8.0, _duck_t)
		_plant[0] = _plant[0].lerp(Vector2(hip.x - _facing * reach, floor_y), 0.2)
		_plant[1] = _plant[1].lerp(Vector2(hip.x - _facing * maxf(reach - 13.0, 6.0), floor_y), 0.2)
	else:
		# idle: no stepping; feet ease under the hips so it settles to a clean stand
		_swing_t = 1.0
		var stance := STANCE_DUCK if ctrl_duck else STANCE
		_plant[0] = _plant[0].lerp(Vector2(hip.x + stance, floor_y), 0.25)
		_plant[1] = _plant[1].lerp(Vector2(hip.x - stance, floor_y), 0.25)

	for i in 2:
		if i == _swing_foot and _swing_t < 1.0:
			var fx := lerpf(_swing_from.x, _swing_to.x, _swing_t)
			var fy := floor_y - sin(_swing_t * PI) * STEP_LIFT
			_foot[i] = Vector2(fx, fy)
		else:
			_foot[i] = _plant[i]          # WORLD-LOCKED — the anti-slide
		_solve_knee(i, hip)
		_sync_leg_springs(i, hip)


func _sync_leg_springs(i: int, hip: Vector2) -> void:
	# keep the sprung leg state glued to the gait pose while grounded, so the moment
	# the body leaves the floor the ragdoll dangle starts from the REAL leg pose
	_leg_ang[i] = (_knee[i] - hip).angle()
	_shin_ang[i] = (_foot[i] - _knee[i]).angle()
	_leg_vel[i] = 0.0
	_shin_vel[i] = 0.0


func _solve_knee(i: int, hip: Vector2) -> void:
	# knees bend FORWARD relative to travel (knee leads the way you're facing) so a run
	# reads as going forward, not moonwalking. Tied to _facing (which tracks movement),
	# so it only re-orients on a genuine turnaround, not per-frame jitter.
	var angs := _ik_leg(hip, _foot[i], THIGH_LEN, SHIN_LEN, -_facing)
	_knee[i] = hip + Vector2.from_angle(angs.x) * THIGH_LEN
	_foot[i] = _knee[i] + Vector2.from_angle(angs.y) * SHIN_LEN   # exact leg length (no stretch)
	if _last_floor_y > 0.0:                                        # never draw a leg through the floor
		_knee[i].y = minf(_knee[i].y, _last_floor_y)
		_foot[i].y = minf(_foot[i].y, _last_floor_y)


func _ik_leg(hip: Vector2, foot: Vector2, l1: float, l2: float, knee_sign: float) -> Vector2:
	var to_foot := foot - hip
	var d := clampf(to_foot.length(), absf(l1 - l2) + 1.0, l1 + l2 - 1.0)
	var base := to_foot.angle()
	var cos_k := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var theta := acos(cos_k)
	var thigh_ang := base + knee_sign * theta
	var knee := hip + Vector2.from_angle(thigh_ang) * l1
	var shin_ang := (foot - knee).angle()
	return Vector2(thigh_ang, shin_ang)


func _wall_clamp_x(x: float) -> float:
	# keep a drawn limb from stabbing through the wall it's up against (only the torso has a
	# real collider, so the kinematic limbs must be held at the wall face by hand)
	if _wall_dir > 0:
		return minf(x, _wall_x - LIMB_W * 0.5)
	elif _wall_dir < 0:
		return maxf(x, _wall_x + LIMB_W * 0.5)
	return x


func _draw() -> void:
	if _torso == null:
		return
	var hip: Vector2 = _torso.to_global(HIP_OFF)
	for i in 2:
		var knee := Vector2(_wall_clamp_x(_knee[i].x), _knee[i].y)
		var foot := Vector2(_wall_clamp_x(_foot[i].x), _foot[i].y)
		draw_line(hip, knee, body_color, LIMB_W, true)
		draw_line(knee, foot, body_color, LIMB_W, true)
		draw_circle(knee, LIMB_W * 0.5, body_color)
		draw_circle(foot, LIMB_W * 0.5, body_color)
	draw_circle(hip, LIMB_W * 0.5, body_color)
	# PARRY SHELL — the directional shield-arc tell thrown up toward the aim. Bright
	# while the ACTIVE window is open, then the lingering shell fades with the timer.
	if _parry_shell_t > 0.0:
		var c: Vector2 = _torso.to_global(SHOULDER_OFF)
		var pa := _parry_dir.angle()
		var fade := clampf(_parry_shell_t / PARRY_SHIELD_TIME, 0.0, 1.0)
		var hot := 1.0 if _parry_window > 0.0 else 0.55          # active window = hot
		draw_arc(c, PARRY_REACH, pa - 0.95, pa + 0.95, 22,
			Color(PARRY_COLOR.r, PARRY_COLOR.g, PARRY_COLOR.b, 0.95 * fade * hot), 4.5, true)
		draw_arc(c, PARRY_REACH - 7.0, pa - 0.72, pa + 0.72, 16,
			Color(PARRY_COLOR.r, PARRY_COLOR.g, PARRY_COLOR.b, 0.38 * fade * hot), 2.5, true)
