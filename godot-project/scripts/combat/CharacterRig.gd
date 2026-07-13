class_name CharacterRig
extends Node2D
## Procedural stick-figure visual rig. Placeholder for real animated stick
## sprites later — the public API (play/set_facing/set_tint/flash/
## set_equipment/class_preset + hit_frame) is the swap contract.

signal hit_frame

enum State { IDLE, RUN, DASH, CAST, PUNCH, KICK, HURT, WALL_SLIDE }

## One-shot states auto-return to IDLE after their fixed duration.
const ONE_SHOT_DURATIONS: Dictionary = {
	State.PUNCH: 0.22,
	State.KICK: 0.26,
	State.CAST: 0.28,
	State.HURT: 0.18,
}
## Fraction of a PUNCH/KICK duration at which hit_frame fires.
const HIT_FRAME_FRACTION: float = 0.55

## Melee feel tuning. The strike curve is: wind BACK for the first
## STRIKE_ANTICIPATION_FRACTION of the one-shot (down to -STRIKE_PULLBACK
## extension), then snap forward (cubic ease-out) to full extension exactly
## at HIT_FRAME_FRACTION, then follow through back to rest.
const STRIKE_ANTICIPATION_FRACTION: float = 0.30
const STRIKE_PULLBACK: float = 0.35
## Squash-stretch impact pop: draw-time size multiplier applied when
## hit_frame fires, easing back to 1.0 over POP_TIME seconds.
const POP_SCALE: float = 1.12
const POP_TIME: float = 0.1
## Flight: fraction of the figure's height it rises at full airborne (set_airborne).
const AIRBORNE_LIFT_FACTOR: float = 0.7
## Slash-arc swoosh: visible over [start, end] of the one-shot's normalized
## time, sweeping SLASH_ARC_SPAN radians at radius height * factor.
const SLASH_ARC_START: float = 0.38
const SLASH_ARC_END: float = 0.9
const SLASH_ARC_SPAN: float = 1.5
const SLASH_ARC_RADIUS_FACTOR: float = 0.52

## Dash afterimages: script loaded lazily to keep the dependency one-way
## (RigGhost references CharacterRig for the shared figure draw).
const GHOST_SCRIPT_PATH: String = "res://scripts/combat/RigGhost.gd"
const MAX_GHOSTS: int = 24
## Aura tuning: layer count + pulse speed/amount.
const AURA_LAYERS: int = 3
const AURA_PULSE_SPEED: float = 3.2
const AURA_PULSE_AMOUNT: float = 0.15
## Rank-driven aura escalation. Tier 0 = aura off; tier 1 = the baseline aura
## (exactly the pre-rank look); tiers 2..5 stack intensity, extra silhouette
## layers, orbiting motes, and (tier >= 3) a rotating ground ring. Everything
## is element-coloured via `aura_color`.
const AURA_TIER_MOTES: Array[int] = [0, 0, 4, 6, 9, 12]
const AURA_TIER_STRENGTH_STEP: float = 0.14  # +strength per tier above 1
const AURA_TIER_PULSE_STEP: float = 0.25     # +pulse fraction per tier above 1
const MOTE_ORBIT_RADIUS_FACTOR: float = 0.7  # orbit radius = height * this
const MOTE_ORBIT_SPEED: float = 1.6          # rad/s around the figure
const MOTE_PULSE_SPEED: float = 4.2          # alpha shimmer speed
const GROUND_RING_MIN_TIER: int = 3
const GROUND_RING_SPIN_SPEED: float = 1.1    # rad/s arc rotation
## Crisp Stick-Fight read: a dark outline drawn under the bold limb colour, and
## how much wider than the limb the outline extends (px). The main _draw passes
## OUTLINE_COLOR; the aura silhouette + dash ghosts draw outline-less (soft).
const OUTLINE_COLOR: Color = Color(0.07, 0.08, 0.13, 1.0)
const OUTLINE_EXTRA: float = 1.8
## --- Active-ragdoll spring sim: the DRAWN limbs physically lag/swing/flail
## toward the procedural pose (_compute_pose is the animation TARGET) instead
## of snapping to it, and go limp on death. Stable point-mass springs in LOCAL
## space — deliberately NOT RigidBody2D/PinJoint2D, which explode and fight the
## kinematic controller. ---
## Joints driven by the sim; neck is re-derived from head_center in _sim_pose().
const SIM_JOINTS: Array[String] = [
	"head_center", "shoulder", "hip",
	"hand_lead", "hand_off", "foot_lead", "foot_off",
]
## Extremities flail harder on impulses + receive the inertial trail nudge.
const SIM_EXTREMITIES: Array[String] = [
	"head_center", "hand_lead", "hand_off", "foot_lead", "foot_off",
]
const STIFFNESS: float = 60.0          # LOOSER still — floppier, more ragdoll swing
const DAMPING: float = 8.0             # less = more overshoot/swing (still stable)
const GRAVITY: float = 800.0           # applied only when limp (ragdoll droop)
const MAX_OFFSET_FACTOR: float = 0.85  # allow more drift so limbs really swing
const LIMP_EASE_SPEED: float = 5.0     # _limp eases toward _limp_target at this /s
const IMPULSE_EXTREMITY_MULT: float = 2.6  # hands/feet/head whip harder on hits
const BODY_TRAIL_FACTOR: float = 0.26  # more inertial limb-trail on launch/stop

@export var limb_color: Color = Color(0.55, 0.75, 1.0, 1.0)
@export var height: float = 26.0
## Soft radial glow under the figure ("charged" hero read). Strength 0
## disables it entirely — enemies stay bare sticks.
@export var aura_color: Color = Color(0.4, 0.7, 1.0, 1.0)
@export var aura_strength: float = 0.0
## Rank tier (0..5) driving aura elaborateness. Enemies stay at strength 0 so
## their tier never matters; the hero's tier is fed by Rank via set_aura_tier.
var aura_tier: int = 1

var state: State = State.IDLE
## slot ("head"/"body"/"feet"/"weapon") -> kind id ("" clears).
var equipment: Dictionary = {}

var _phase: float = 0.0
var _one_shot_active: bool = false
var _one_shot_time: float = 0.0
var _one_shot_duration: float = 0.0
var _hit_frame_emitted: bool = false
var _pop_timer: float = 0.0
var _flash_timer: float = 0.0
var _flash_color: Color = Color.WHITE
## World-space cursor direction for the CAST lead arm, from set_aim(). The arm
## points at the TRUE cursor even when the body faces the other way (twin-stick):
## _compute_pose mirrors it into the (possibly flipped) local frame.
var _aim_world: Vector2 = Vector2.RIGHT
## Directional parry SHIELD (Stick-Fight block): a white curved shell drawn in
## the aim direction while active. set_parry() arms it; it fades over its window.
## Faceless otherwise — Stick-Fight fighters convey aim by the body + the shield,
## never a face.
var _parry_dir: Vector2 = Vector2.RIGHT
var _parry_timer: float = 0.0
var _parry_duration: float = 0.0
## Airborne lift for the flight ability (0 = grounded, 1 = fully lifted).
var _airborne: float = 0.0
## Active-ragdoll sim state: joint key -> simulated LOCAL position / velocity.
## Lazily seeded to the current target pose on first use so limbs never spring
## in from the origin. Pure Dictionary/Vector2 math — headless-safe.
var _sim: Dictionary = {}
var _sim_vel: Dictionary = {}
var _sim_ready: bool = false
## Limpness 0 (fully animated) .. 1 (ragdoll: weak springs + gravity droop).
var _limp: float = 0.0
var _limp_target: float = 0.0
## Body velocity fed by set_body_velocity(); its frame-to-frame CHANGE nudges
## the extremities so limbs trail when the body launches/stops.
var _body_vel: Vector2 = Vector2.ZERO
var _prev_body_vel: Vector2 = Vector2.ZERO
## Hard-CC freeze: while true the locomotion cycle (_phase) HOLDS so a frozen /
## shocked enemy reads as genuinely rooted under the ice instead of jogging in
## place. The spring sim + timers still tick (a hit still flails, flashes clear),
## only the animation clock stops. Set by the owner from StatusComponent.is_hard_cc.
var _frozen: bool = false


func _process(delta: float) -> void:
	advance(delta)


## Per-frame update, split out from _process so headless tests can drive
## the rig deterministically without a real frame loop.
func advance(delta: float) -> void:
	# Frozen: hold the locomotion phase so the run/idle cycle stops dead. Timers +
	# sim below still advance so the ice-shatter flash and a knock still read.
	if not _frozen:
		_phase += delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
	if _pop_timer > 0.0:
		_pop_timer -= delta
	if _parry_timer > 0.0:
		_parry_timer -= delta
	if _one_shot_active:
		_one_shot_time += delta
		var is_strike: bool = state == State.PUNCH or state == State.KICK
		if is_strike and not _hit_frame_emitted \
				and _one_shot_time >= _one_shot_duration * HIT_FRAME_FRACTION:
			_hit_frame_emitted = true
			_pop_timer = POP_TIME
			hit_frame.emit()
		if _one_shot_time >= _one_shot_duration:
			_one_shot_active = false
			state = State.IDLE
	_step_sim(delta)
	queue_redraw()


## Step the active-ragdoll spring sim toward the current animation target pose.
## Stable by construction: springs weaken as _limp rises, damping is clamped,
## and every joint is hard-clamped to height * MAX_OFFSET_FACTOR from its
## target so the sim can never explode. _compute_pose() is called ONCE here
## and reused for every joint.
func _step_sim(delta: float) -> void:
	var target_pose: Dictionary = _compute_pose()
	_ensure_sim(target_pose)
	if delta <= 0.0:
		return
	_limp = move_toward(_limp, _limp_target, LIMP_EASE_SPEED * delta)
	var stiffness: float = lerpf(STIFFNESS, STIFFNESS * 0.05, _limp)
	var damp: float = clampf(1.0 - DAMPING * delta, 0.0, 1.0)
	var max_off: float = height * MAX_OFFSET_FACTOR
	# Inertial trail: extremities get a nudge OPPOSITE the body's velocity
	# change (mirrored into the local flip) so limbs lag on launch/stop.
	var dv: Vector2 = _body_vel - _prev_body_vel
	_prev_body_vel = _body_vel
	if not (is_finite(dv.x) and is_finite(dv.y)):
		dv = Vector2.ZERO
	var flip_s: float = 1.0 if scale.x >= 0.0 else -1.0
	var trail: Vector2 = Vector2(-dv.x * flip_s, -dv.y) * BODY_TRAIL_FACTOR
	for key: String in SIM_JOINTS:
		var target: Vector2 = target_pose[key]
		var vel: Vector2 = _sim_vel[key]
		vel += (target - _sim[key]) * stiffness * delta
		vel += Vector2(0.0, GRAVITY * _limp) * delta
		if SIM_EXTREMITIES.has(key):
			vel += trail
		vel *= damp
		var pos: Vector2 = _sim[key] + vel * delta
		var off: Vector2 = pos - target
		var off_len: float = off.length()
		if off_len > max_off:
			pos = target + off / off_len * max_off
		_sim[key] = pos
		_sim_vel[key] = vel


## Lazily seed the sim at the target pose (first advance, or an apply_impulse
## arriving before the first frame) so joints never spring in from the origin.
func _ensure_sim(target_pose: Dictionary = {}) -> void:
	if _sim_ready:
		return
	var pose: Dictionary = target_pose if not target_pose.is_empty() else _compute_pose()
	for key: String in SIM_JOINTS:
		_sim[key] = pose[key]
		_sim_vel[key] = Vector2.ZERO
	_sim_ready = true


## The pose actually DRAWN: _compute_pose() with the driven joints replaced by
## their simulated positions, neck re-derived from the simmed head so head and
## torso stay connected. r + w pass through. draw_figure's 2-bone IK then bends
## knees/elbows from the simmed hip/shoulder/hand/foot for free. Falls back to
## the raw animation pose until the sim is seeded.
func _sim_pose() -> Dictionary:
	var pose: Dictionary = _compute_pose()
	if not _sim_ready:
		return pose
	for key: String in SIM_JOINTS:
		pose[key] = _sim[key]
	pose["neck"] = _sim["head_center"] + Vector2(0.0, pose["r"])
	return pose


## Jolt the limbs: mirror `world_dir` into the (possibly flipped) local frame
## and kick every simmed joint's velocity — extremities harder — so a hit
## sends hands/feet/head flailing before the springs reel them back in.
func apply_impulse(world_dir: Vector2, strength: float) -> void:
	if world_dir == Vector2.ZERO \
			or not (is_finite(world_dir.x) and is_finite(world_dir.y)) \
			or not is_finite(strength) or strength == 0.0:
		return
	_ensure_sim()
	var flip_s: float = 1.0 if scale.x >= 0.0 else -1.0
	var local: Vector2 = Vector2(world_dir.x * flip_s, world_dir.y).normalized()
	for key: String in SIM_JOINTS:
		var mult: float = IMPULSE_EXTREMITY_MULT if SIM_EXTREMITIES.has(key) else 1.0
		_sim_vel[key] += local * strength * mult
	queue_redraw()


## Set the limpness target: 0 = fully animated, 1 = full ragdoll (weak springs
## + gravity droop). Eased in advance() so death melts rather than snaps.
func set_limp(t: float) -> void:
	_limp_target = clampf(t, 0.0, 1.0)


## Feed the owning body's velocity (e.g. Hero.velocity each physics frame).
## The frame-to-frame CHANGE adds a small inertial nudge to the extremities so
## limbs trail when the body accelerates or stops. NaN-guarded; subtle.
func set_body_velocity(v: Vector2) -> void:
	if is_finite(v.x) and is_finite(v.y):
		_body_vel = v


## Freeze/unfreeze the locomotion cycle. True = hold the run/idle animation clock
## (the "frozen under ice" read for hard-CC'd enemies); the spring sim still ticks.
func set_frozen(frozen: bool) -> void:
	_frozen = frozen


## Set the current animation state. Looping states (IDLE/RUN/DASH) are
## ignored while a one-shot (PUNCH/KICK/CAST/HURT) is playing; a one-shot
## may interrupt another one-shot (e.g. HURT during PUNCH).
func play(new_state: State) -> void:
	var is_one_shot: bool = ONE_SHOT_DURATIONS.has(new_state)
	if _one_shot_active and not is_one_shot:
		return
	if not is_one_shot and new_state == state:
		return
	state = new_state
	if is_one_shot:
		_one_shot_active = true
		_one_shot_duration = ONE_SHOT_DURATIONS[new_state]
		_one_shot_time = 0.0
		_hit_frame_emitted = false
	queue_redraw()


## True while a melee strike (PUNCH/KICK) one-shot is playing. Hero faces the
## aim during a strike so the punch animation points at the cursor/target (the
## arm extends in the body-facing direction), matching the aim-directed damage arc.
func is_striking() -> bool:
	return _one_shot_active and (state == State.PUNCH or state == State.KICK)


## Flip horizontally to face `dir`. Unchanged when dir.x == 0.
func set_facing(dir: Vector2) -> void:
	if dir.x < 0.0:
		scale.x = -1.0
	elif dir.x > 0.0:
		scale.x = 1.0


## Aim the CAST lead arm/staff toward `dir` (the cursor direction), stored as a
## world vector so the arm can point at the true cursor even when the body faces
## the other way. _compute_pose mirrors it into the local frame for the flip.
func set_aim(dir: Vector2) -> void:
	if dir != Vector2.ZERO:
		_aim_world = dir.normalized()


## Arm the directional parry shield: a white curved shell drawn facing `dir`
## (the aim/threat direction) for `duration` seconds, fading as it expires. The
## Stick-Fight block/deflect read — replaces the old omni flash.
func set_parry(dir: Vector2, duration: float) -> void:
	if dir != Vector2.ZERO:
		_parry_dir = dir.normalized()
	_parry_duration = maxf(duration, 0.01)
	_parry_timer = _parry_duration
	queue_redraw()


## World position of the lead-weapon tip (staff crystal / sword point / hand), so
## spells emanate FROM the weapon rather than the body centre. Reads the current
## pose (so during a CAST it points at the aim); `to_global` handles the L/R flip.
func get_weapon_tip() -> Vector2:
	var pose: Dictionary = _compute_pose()
	var shoulder: Vector2 = pose["shoulder"]
	var hand: Vector2 = pose["hand_lead"]
	var arm_dir: Vector2 = hand - shoulder
	if arm_dir.length() < 0.001:
		arm_dir = Vector2.RIGHT
	arm_dir = arm_dir.normalized()
	var reach: float = 0.0
	match equipment.get("weapon", ""):
		"staff": reach = height * 0.38
		"sword": reach = height * 0.5
		"orb": reach = height * 0.14
	return to_global(hand + arm_dir * reach)


## Flight lift, 0 (grounded) .. 1 (airborne). Driven by Hero._update_flight;
## raises the drawn figure and drops a shrinking ground shadow beneath it.
func set_airborne(v: float) -> void:
	_airborne = clampf(v, 0.0, 1.0)
	queue_redraw()


## Set the base limb/head color (enemy archetype tint, hero blue, ...).
func set_tint(color: Color) -> void:
	limb_color = color
	queue_redraw()


## Briefly whiten the whole figure (hit feedback), then restore the tint.
func flash(duration: float = 0.06) -> void:
	flash_color(Color.WHITE, duration)


## Flash the figure in an arbitrary color (e.g. red for hero damage), then
## restore the tint. `flash()` is the white default and stays the public API.
func flash_color(color: Color, duration: float = 0.06) -> void:
	_flash_color = color
	_flash_timer = duration
	queue_redraw()


## Visual equipment overlay. slot in {"head","body","feet","weapon"};
## kind "" clears the slot. Unknown kinds draw nothing.
func set_equipment(slot: String, kind: String) -> void:
	if kind == "":
		equipment.erase(slot)
	else:
		equipment[slot] = kind
	queue_redraw()


## Convenience gear bundles — one per playable class. Classes WITH a weapon
## (Hero.CLASS_CONFIG "weapon") override the weapon slot via equip_weapon after
## this; weaponless classes (mage staff, brawler fists) keep what's set here.
## Overlay art is reused (robe/hat/hood/staff/sword/orb/fists) — the strong
## class read comes from the element colour, AoE variant, and signature ult.
func class_preset(preset_name: String) -> void:
	match preset_name:
		"mage":
			set_equipment("body", "robe")
			set_equipment("head", "hat")
			set_equipment("weapon", "staff")
		"rogue":
			set_equipment("head", "hood")
			set_equipment("body", "")
			set_equipment("weapon", "sword")
		"summoner":
			set_equipment("body", "robe")
			set_equipment("head", "hat")
			set_equipment("weapon", "orb")
		"brawler":  # bare-fisted bruiser — no robe, no weapon
			set_equipment("body", "")
			set_equipment("head", "")
			set_equipment("weapon", "")
		"juggernaut":  # heavy — bare torso, weapon (hammer) from equip_weapon
			set_equipment("body", "")
			set_equipment("head", "")
			set_equipment("weapon", "sword")
		"cleric":  # hooded templar with a staff
			set_equipment("body", "robe")
			set_equipment("head", "hood")
			set_equipment("weapon", "staff")
		"cryomancer":  # hatted frost caster
			set_equipment("body", "robe")
			set_equipment("head", "hat")
			set_equipment("weapon", "staff")
		"stormcaller":  # hatted storm caster
			set_equipment("body", "robe")
			set_equipment("head", "hat")
			set_equipment("weapon", "staff")
		"warlock":  # hooded hexer with a scythe (sword overlay)
			set_equipment("body", "robe")
			set_equipment("head", "hood")
			set_equipment("weapon", "sword")


## Enable/retint the under-figure aura glow. strength 0 turns it off.
func set_aura(color: Color, strength: float = 1.0) -> void:
	aura_color = color
	aura_strength = strength
	queue_redraw()


## Set the rank tier (0..5) driving aura escalation. Tier 0 kills the aura
## outright; tier 1 is the baseline look; higher tiers get more layers,
## orbiting motes, and the ground ring.
func set_aura_tier(t: int) -> void:
	aura_tier = clampi(t, 0, 5)
	queue_redraw()


## Spawn a fading afterimage of the current pose under `parent` (dash trail).
## Pure visual: no animation, no collision; self-frees. Optional extras for
## the death-corpse read: `launch_velocity` makes the ghost drift as it
## fades; `fade_time` > 0 overrides RigGhost.FADE_TIME.
func spawn_ghost(
	parent: Node,
	ghost_color: Color,
	wind_dir: Vector2 = Vector2.ZERO,
	launch_velocity: Vector2 = Vector2.ZERO,
	fade_time: float = 0.0,
) -> void:
	if parent == null or not is_inside_tree():
		return
	if get_tree().get_nodes_in_group("rig_ghost").size() >= MAX_GHOSTS:
		return
	var ghost_script: GDScript = load(GHOST_SCRIPT_PATH) as GDScript
	var ghost: Node2D = ghost_script.new() as Node2D
	ghost.set("pose", _compute_pose())
	ghost.set("equipment_slots", equipment.duplicate())
	ghost.set("fig_height", height)
	ghost.set("base_color", ghost_color)
	ghost.set("wind_dir", wind_dir)
	ghost.set("launch_velocity", launch_velocity)
	if fade_time > 0.0:
		ghost.set("fade_time", fade_time)
	parent.add_child(ghost)
	ghost.global_transform = global_transform
	# z_index 0 (not -1): the arena Floor ColorRect is an opaque z=0 canvas item,
	# so a z=-1 ghost renders BEHIND the floor and is invisible. The hero keeps
	# its own higher z (set on the rig) so the figure still draws over its trail.
	ghost.z_index = 0


func _draw() -> void:
	var col: Color = _flash_color if _flash_timer > 0.0 else limb_color
	if _airborne > 0.01:
		_draw_shadow()  # ground shadow stays put while the figure lifts (flight)
	_draw_aura()
	# Draw-time transform: impact pop (scale) composed with flight lift (y-offset).
	# Never touches node.scale — set_facing() owns scale.x for the horizontal flip.
	var pop_scale: Vector2 = Vector2.ONE
	if _pop_timer > 0.0:
		var pop: float = 1.0 + (POP_SCALE - 1.0) * clampf(_pop_timer / POP_TIME, 0.0, 1.0)
		pop_scale = Vector2(pop, pop)
	var lift: Vector2 = Vector2(0.0, -_airborne * height * AIRBORNE_LIFT_FACTOR)
	if lift != Vector2.ZERO or pop_scale != Vector2.ONE:
		draw_set_transform(lift, 0.0, pop_scale)
	var pose: Dictionary = _sim_pose()  # draw the PHYSICAL body, not the raw target
	draw_figure(self, pose, col, equipment, height, OUTLINE_COLOR)
	_draw_slash_arc(pose, col)
	_draw_parry_shield(pose)


## Directional parry SHIELD — a white "section of a sphere": a solid curved band
## in front of the figure, facing _parry_dir, with a bright leading rim. Fades
## over its window. The Stick-Fight block/deflect. The world aim is mirrored into
## the (possibly flipped) local frame so it points at the true threat direction.
func _draw_parry_shield(pose: Dictionary) -> void:
	if _parry_timer <= 0.0 or _parry_duration <= 0.0:
		return
	var frac: float = clampf(_parry_timer / _parry_duration, 0.0, 1.0)
	# Snap in bright, ease out: full for the first half of the window, then fade.
	var alpha: float = minf(1.0, frac * 2.0)
	var s: float = 1.0 if scale.x >= 0.0 else -1.0
	var aim: Vector2 = Vector2(_parry_dir.x * s, _parry_dir.y).normalized()
	var center: Vector2 = pose["shoulder"].lerp(pose["hip"], 0.4)  # chest height
	var ang: float = aim.angle()
	var half_span: float = 0.85                       # ~1.7 rad of arc (a shell)
	var r_in: float = height * 0.5
	var r_out: float = height * 0.66
	# Solid curved band, built as a polygon strip between the inner + outer arcs.
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 12
	for i: int in range(steps + 1):
		var a: float = ang - half_span + (2.0 * half_span) * float(i) / float(steps)
		pts.append(center + Vector2.from_angle(a) * r_out)
	for i: int in range(steps + 1):
		var a: float = ang + half_span - (2.0 * half_span) * float(i) / float(steps)
		pts.append(center + Vector2.from_angle(a) * r_in)
	draw_colored_polygon(pts, Color(0.95, 0.98, 1.0, 0.62 * alpha))
	# Bright leading rim on the outer edge + a soft outer glow.
	draw_arc(center, r_out, ang - half_span, ang + half_span, 16, Color(1, 1, 1, 0.95 * alpha), maxf(2.0, height * 0.05))
	draw_arc(center, r_out + height * 0.06, ang - half_span, ang + half_span, 16, Color(0.85, 0.95, 1.0, 0.22 * alpha), height * 0.09)


## Soft ground shadow beneath the figure while airborne — shrinks + fades as it
## rises, selling the top-down "lifted off the ground" read. Drawn in un-lifted
## space (stays on the floor) before the figure's lift transform.
func _draw_shadow() -> void:
	var sh_scale: float = 1.0 - 0.45 * _airborne
	var sh_alpha: float = 0.30 * (1.0 - 0.35 * _airborne)
	draw_set_transform(Vector2(0.0, height * 0.5), 0.0, Vector2(sh_scale, sh_scale * 0.4))
	draw_circle(Vector2.ZERO, height * 0.42, Color(0.0, 0.0, 0.0, sh_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Player-SHAPED aura: the figure silhouette drawn a few times in the aura
## colour, scaled up + fading outward behind the main figure — a glowing halo
## that follows the pose, not a ground circle. Rank tier escalates it: extra
## layers + intensity + pulse, orbiting motes (tier >= 2), ground ring
## (tier >= 3). Tier 1 is EXACTLY the pre-rank baseline; tier 0 draws nothing.
func _draw_aura() -> void:
	if aura_strength <= 0.0 or aura_tier <= 0:
		return
	# Tier 1 keeps the baseline strength/layers/pulse; each tier above stacks.
	var over: float = float(aura_tier - 1)
	var eff: float = minf(aura_strength + AURA_TIER_STRENGTH_STEP * over, 1.6)
	var layers: int = AURA_LAYERS + maxi(aura_tier - 2, 0)
	var pulse_amount: float = AURA_PULSE_AMOUNT * (1.0 + AURA_TIER_PULSE_STEP * over)
	var pulse: float = 1.0 - pulse_amount * 0.5 \
			+ pulse_amount * 0.5 * sin(_phase * AURA_PULSE_SPEED)
	if aura_tier >= GROUND_RING_MIN_TIER:
		_draw_ground_ring(eff)
	var pose: Dictionary = _sim_pose()  # halo hugs the PHYSICAL body
	var step: float = 0.13      # each halo layer is this much larger than the figure
	var base_alpha: float = 0.3
	# Outer (biggest, faintest) first so brighter inner layers sit on top.
	for i: int in range(layers):
		var layer: int = layers - i               # layers..1 (outer -> inner)
		var s: float = (1.0 + step * float(layer)) * pulse
		var a: float = eff * base_alpha / float(layer)
		var glow: Color = Color(aura_color.r, aura_color.g, aura_color.b, a)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
		draw_figure(self, pose, glow, equipment, height)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # reset for the main figure
	_draw_motes(eff)


## Orbiting element-coloured motes — the "charged" read at tier >= 2. Each
## mote is a bright core over a soft halo, alpha shimmering out of phase so
## the ring never reads as a static decoration.
func _draw_motes(eff: float) -> void:
	var count: int = AURA_TIER_MOTES[aura_tier]
	if count <= 0:
		return
	var orbit_r: float = height * MOTE_ORBIT_RADIUS_FACTOR
	var mote_r: float = maxf(1.2, height * 0.06)
	for i: int in range(count):
		var ang: float = _phase * MOTE_ORBIT_SPEED + TAU * float(i) / float(count)
		var pos: Vector2 = Vector2.from_angle(ang) * orbit_r
		var a: float = clampf(
			eff * (0.4 + 0.25 * sin(_phase * MOTE_PULSE_SPEED + float(i) * 1.7)),
			0.08, 1.0
		)
		var core: Color = Color(aura_color.r, aura_color.g, aura_color.b, a)
		var halo: Color = Color(aura_color.r, aura_color.g, aura_color.b, a * 0.35)
		draw_circle(pos, mote_r * 1.9, halo)
		draw_circle(pos, mote_r, core)


## Faint rotating ground ring under the figure (tier >= 3): two opposed arcs
## squashed into a floor ellipse, spinning with _phase.
func _draw_ground_ring(eff: float) -> void:
	var ring_center: Vector2 = Vector2(0.0, height * 0.55)
	var radius: float = height * 0.62
	var w: float = maxf(1.2, height * 0.05)
	var col: Color = Color(aura_color.r, aura_color.g, aura_color.b, clampf(eff * 0.28, 0.0, 0.6))
	var spin: float = _phase * GROUND_RING_SPIN_SPEED
	draw_set_transform(ring_center, 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, radius, spin, spin + 2.4, 16, col, w)
	draw_arc(Vector2.ZERO, radius, spin + PI, spin + PI + 2.4, 16, col, w)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Anticipation-then-thrust extension curve for PUNCH/KICK, over normalized
## one-shot time t in [0, 1]:
##   [0, STRIKE_ANTICIPATION_FRACTION]  wind back to -STRIKE_PULLBACK (ease-in,
##                                      slow — the "loading up" read)
##   [.., HIT_FRAME_FRACTION]           thrust to 1.0 with cubic ease-out
##                                      (fast — full extension lands exactly
##                                      on the hit_frame moment)
##   [.., 1]                            follow-through: holds near extension,
##                                      then retracts to 0
static func _strike_ext(t: float) -> float:
	if t < STRIKE_ANTICIPATION_FRACTION:
		var wind_u: float = t / STRIKE_ANTICIPATION_FRACTION
		return -STRIKE_PULLBACK * wind_u * wind_u
	if t < HIT_FRAME_FRACTION:
		var thrust_u: float = (t - STRIKE_ANTICIPATION_FRACTION) \
				/ (HIT_FRAME_FRACTION - STRIKE_ANTICIPATION_FRACTION)
		var eased: float = 1.0 - pow(1.0 - thrust_u, 3.0)
		return lerpf(-STRIKE_PULLBACK, 1.0, eased)
	var recover_u: float = (t - HIT_FRAME_FRACTION) / (1.0 - HIT_FRAME_FRACTION)
	return 1.0 - recover_u * recover_u


## Quick swoosh arc in front of the lead hand (PUNCH) or lead foot (KICK),
## fading over the strike window. Local +x is the facing direction (the node
## flip mirrors it for free). Cheap: two draw_arc calls.
func _draw_slash_arc(pose: Dictionary, col: Color) -> void:
	if not _one_shot_active or _one_shot_duration <= 0.0:
		return
	if state != State.PUNCH and state != State.KICK:
		return
	var t: float = clampf(_one_shot_time / _one_shot_duration, 0.0, 1.0)
	if t < SLASH_ARC_START or t > SLASH_ARC_END:
		return
	var p: float = (t - SLASH_ARC_START) / (SLASH_ARC_END - SLASH_ARC_START)
	var fade: float = 1.0 - p
	var center: Vector2 = pose["shoulder"] if state == State.PUNCH else pose["hip"]
	var mid_angle: float = 0.0 if state == State.PUNCH else 0.2
	var radius: float = height * SLASH_ARC_RADIUS_FACTOR * (0.85 + 0.3 * p)
	var start_angle: float = mid_angle - SLASH_ARC_SPAN * 0.5
	var end_angle: float = mid_angle + SLASH_ARC_SPAN * 0.5
	var w: float = pose["w"]
	var glow: Color = Color(col.r, col.g, col.b, 0.35 * fade)
	var core: Color = Color(1.0, 1.0, 1.0, 0.85 * fade)
	draw_arc(center, radius, start_angle, end_angle, 10, glow, w * 1.8)
	draw_arc(center, radius, start_angle, end_angle, 10, core, w * 0.8)


## Compute the current pose skeleton in local space. Keys: head_center,
## neck, hip, shoulder, hand_lead, hand_off, foot_lead, foot_off,
## plus stroke metrics r (head radius) and w (line width).
func _compute_pose() -> Dictionary:
	var w: float = maxf(2.0, height * 0.11)
	var r: float = height * 0.15
	var arm_len: float = height * 0.32
	var leg_len: float = height * 0.4
	var t: float = 0.0
	if _one_shot_active and _one_shot_duration > 0.0:
		t = clampf(_one_shot_time / _one_shot_duration, 0.0, 1.0)
	# PUNCH/KICK: anticipation-then-thrust (negative = wound back).
	# Other one-shots keep the smooth 0 -> 1 -> 0 wave.
	var is_strike: bool = state == State.PUNCH or state == State.KICK
	var ext: float = _strike_ext(t) if is_strike else sin(t * PI)

	# Pose parameters. Angles are radians from each joint: 0 = forward
	# (+x, lead side), PI/2 = straight down, PI = backward.
	var bob: float = 0.0
	var lean: float = 0.0  # +x head/neck offset (forward lean)
	var arm_lead: float = PI * 0.5 + 0.35
	var arm_off: float = PI * 0.5 - 0.35
	var arm_lead_len: float = arm_len
	var leg_lead: float = PI * 0.5 - 0.18
	var leg_off: float = PI * 0.5 + 0.18
	var leg_lead_len: float = leg_len

	match state:
		State.IDLE:
			bob = sin(_phase * 2.0) * height * 0.03
		State.RUN:
			# Smoother, weightier gait (Stick-Fight feel): a calmer stride
			# frequency, a real leg lift on the back-swing (stride, not a scissor),
			# arm counter-swing, and a two-step bounce synced to the footfalls.
			var sp: float = _phase * 9.5
			var swing: float = sin(sp) * 0.9
			lean = height * 0.13
			leg_lead = PI * 0.5 - swing
			leg_off = PI * 0.5 + swing
			# Shorten whichever leg is swinging back so it "lifts" off the ground.
			leg_lead_len = leg_len * (1.0 - 0.16 * maxf(-sin(sp), 0.0))
			arm_lead = PI * 0.5 + swing * 0.75
			arm_off = PI * 0.5 - swing * 0.75
			bob = absf(sin(sp)) * height * 0.055
		State.DASH:
			lean = height * 0.22
			leg_lead = PI * 0.5 + 0.55
			leg_off = PI * 0.5 + 0.85
			arm_lead = PI * 0.5 + 0.7
			arm_off = PI * 0.5 + 0.95
		State.CAST:
			# Lead arm points at the TRUE world cursor — mirror it into the
			# (possibly flipped) local frame so the staff aims right even when the
			# body faces the other way (twin-stick cast).
			lean = height * 0.05
			var cast_s: float = 1.0 if scale.x >= 0.0 else -1.0
			arm_lead = Vector2(_aim_world.x * cast_s, _aim_world.y).angle()
			arm_off = 0.18
		State.PUNCH:
			# ext < 0 during anticipation coils the torso back and retracts
			# the arm; the same formulas then thrust it past neutral.
			lean = height * 0.08 * ext
			arm_lead = lerpf(PI * 0.45, 0.0, ext)
			arm_lead_len = arm_len * (0.8 + 0.5 * ext)
			arm_off = PI * 0.5 + 0.4
		State.KICK:
			lean = -height * 0.04 * ext
			leg_lead = lerpf(PI * 0.5, 0.05, ext)
			leg_lead_len = leg_len * (0.85 + 0.45 * ext)
			leg_off = PI * 0.5 + 0.15
			arm_lead = PI * 0.5 - 0.5
			arm_off = PI * 0.5 + 0.5
		State.HURT:
			lean = -height * 0.14
			arm_lead = -0.5
			arm_off = PI + 0.5
			leg_lead = PI * 0.5 - 0.35
			leg_off = PI * 0.5 - 0.1
		State.WALL_SLIDE:
			# Clinging to a wall (facing it, +x = wall): both arms reach up-into the
			# wall, legs bent + splayed against it. The IK bends knees/elbows so it
			# reads as a real cling + slide, not a stiff stick.
			lean = height * 0.05
			arm_lead = -0.55
			arm_off = 0.25
			arm_lead_len = arm_len * 0.9
			leg_lead = PI * 0.5 - 0.15
			leg_off = PI * 0.5 + 0.4
			leg_lead_len = leg_len * 0.82

	# Skeleton joints (local space; feet at +height/2, head top at -height/2).
	var head_center: Vector2 = Vector2(lean, -height * 0.5 + r + bob)
	var neck: Vector2 = head_center + Vector2(0, r)
	var hip: Vector2 = Vector2(0, height * 0.1 + bob * 0.5)
	var shoulder: Vector2 = neck.lerp(hip, 0.15)

	return {
		"head_center": head_center,
		"neck": neck,
		"hip": hip,
		"shoulder": shoulder,
		"hand_lead": shoulder + Vector2.from_angle(arm_lead) * arm_lead_len,
		"hand_off": shoulder + Vector2.from_angle(arm_off) * arm_len,
		"foot_lead": hip + Vector2.from_angle(leg_lead) * leg_lead_len,
		"foot_off": hip + Vector2.from_angle(leg_off) * leg_len,
		"r": r,
		"w": w,
	}


## Draw a stick-figure pose onto any CanvasItem. Must be called from that
## item's own _draw(). Shared by _draw() and RigGhost so dash afterimages
## render the exact same silhouette. `col.a` scales the robe/gear alphas.
static func draw_figure(
	item: CanvasItem,
	pose: Dictionary,
	col: Color,
	equipment_slots: Dictionary,
	fig_height: float,
	outline_col: Color = Color(0.0, 0.0, 0.0, 0.0),
) -> void:
	var w: float = pose["w"]
	var r: float = pose["r"]
	var head_center: Vector2 = pose["head_center"]
	var neck: Vector2 = pose["neck"]
	var hip: Vector2 = pose["hip"]
	var shoulder: Vector2 = pose["shoulder"]
	var hand_lead: Vector2 = pose["hand_lead"]
	var hand_off: Vector2 = pose["hand_off"]
	var foot_lead: Vector2 = pose["foot_lead"]
	var foot_off: Vector2 = pose["foot_off"]

	# --- ARTICULATED limbs (the Stick-Fight upgrade): solve a KNEE per leg + an
	# ELBOW per arm with 2-bone IK so the figure BENDS like a real body instead of
	# stiff straight sticks. Segment sums exceed the limb reach so there's always
	# a real bend; knees bend forward (+x local), elbows bend down. ---
	var thigh: float = fig_height * 0.23
	var shin: float = fig_height * 0.25
	var upper: float = fig_height * 0.2
	var fore: float = fig_height * 0.2
	var knee_lead: Vector2 = _ik_joint(hip, foot_lead, thigh, shin, Vector2.RIGHT)
	var knee_off: Vector2 = _ik_joint(hip, foot_off, thigh, shin, Vector2.RIGHT)
	var elbow_lead: Vector2 = _ik_joint(shoulder, hand_lead, upper, fore, Vector2.DOWN)
	var elbow_off: Vector2 = _ik_joint(shoulder, hand_off, upper, fore, Vector2.DOWN)

	# Body-slot robe draws under the limbs.
	if equipment_slots.get("body", "") == "robe":
		var robe: PackedVector2Array = PackedVector2Array([
			neck + Vector2(-r * 0.8, 0),
			neck + Vector2(r * 0.8, 0),
			hip + Vector2(r * 1.7, fig_height * 0.22),
			hip + Vector2(-r * 1.7, fig_height * 0.22),
		])
		item.draw_colored_polygon(robe, Color(col.r, col.g, col.b, col.a * 0.45))

	# Crisp dark OUTLINE pass: the same articulated skeleton drawn thicker under so
	# the bold coloured figure reads against any background (the Stick-Fight look).
	# Aura silhouette + dash ghosts pass no outline_col (a==0) -> they stay soft.
	if outline_col.a > 0.0:
		var oc: Color = Color(outline_col.r, outline_col.g, outline_col.b, outline_col.a * col.a)
		var ow: float = w + OUTLINE_EXTRA
		item.draw_line(neck, hip, oc, ow)
		_draw_limb(item, shoulder, elbow_lead, hand_lead, oc, ow)
		_draw_limb(item, shoulder, elbow_off, hand_off, oc, ow)
		_draw_limb(item, hip, knee_lead, foot_lead, oc, ow)
		_draw_limb(item, hip, knee_off, foot_off, oc, ow)
		item.draw_circle(hand_lead, ow * 0.5, oc)
		item.draw_circle(hand_off, ow * 0.5, oc)
		item.draw_circle(foot_lead, ow * 0.5, oc)
		item.draw_circle(foot_off, ow * 0.5, oc)
		item.draw_circle(head_center, r + OUTLINE_EXTRA * 0.7, oc)

	# The figure: head + torso + 2 articulated arms + 2 articulated legs.
	item.draw_circle(head_center, r, col)
	item.draw_line(neck, hip, col, w)
	_draw_limb(item, shoulder, elbow_lead, hand_lead, col, w)
	_draw_limb(item, shoulder, elbow_off, hand_off, col, w)
	_draw_limb(item, hip, knee_lead, foot_lead, col, w)
	_draw_limb(item, hip, knee_off, foot_off, col, w)
	# Rounded joints/ends: filled dots cap the lines so the limbs read solid.
	item.draw_circle(shoulder, w * 0.5, col)
	item.draw_circle(hip, w * 0.55, col)
	item.draw_circle(hand_lead, w * 0.5, col)
	item.draw_circle(hand_off, w * 0.5, col)
	item.draw_circle(foot_lead, w * 0.55, col)  # slightly bigger = a "foot"
	item.draw_circle(foot_off, w * 0.55, col)

	_draw_equipment(
		item, equipment_slots, col, w, r, fig_height,
		head_center, shoulder, hand_lead, foot_lead, foot_off
	)


## Draw a two-segment limb root->mid->end with a rounded joint cap at the mid.
static func _draw_limb(item: CanvasItem, a: Vector2, mid: Vector2, b: Vector2, col: Color, w: float) -> void:
	item.draw_line(a, mid, col, w)
	item.draw_line(mid, b, col, w)
	item.draw_circle(mid, w * 0.5, col)  # knee / elbow cap


## 2-bone IK: the joint of a chain root->end with segment lengths l1 (root->joint)
## and l2 (joint->end), bent toward `hint`. Clamped so an over-extended chain just
## straightens instead of producing NaNs.
static func _ik_joint(root: Vector2, end: Vector2, l1: float, l2: float, hint: Vector2) -> Vector2:
	var delta: Vector2 = end - root
	var dist: float = delta.length()
	if dist < 0.0001:
		return root
	var d: float = clampf(dist, absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var dir: Vector2 = delta / dist
	var along: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h: float = sqrt(maxf(l1 * l1 - along * along, 0.0))
	var perp: Vector2 = dir.orthogonal()
	if perp.dot(hint) < 0.0:
		perp = -perp
	return root + dir * along + perp * h


## Gear overlay. Weapons are oriented ALONG the lead arm (hand - shoulder) so
## they read as HELD and gripped, not floating: the shaft runs through the hand
## and the business end points where the arm points — so casting (arm at cursor)
## aims the staff/sword at the target. A thin dark under-edge keeps the crisp
## outlined Stick-Fight look.
static func _draw_equipment(
	item: CanvasItem,
	equipment_slots: Dictionary,
	col: Color,
	w: float,
	r: float,
	fig_height: float,
	head_center: Vector2,
	shoulder: Vector2,
	hand_lead: Vector2,
	foot_lead: Vector2,
	foot_off: Vector2,
) -> void:
	var gear_col: Color = col.lightened(0.25)
	match equipment_slots.get("head", ""):
		"hat":
			var hat: PackedVector2Array = PackedVector2Array([
				head_center + Vector2(-r * 1.1, -r * 0.6),
				head_center + Vector2(r * 1.1, -r * 0.6),
				head_center + Vector2(0, -r * 2.3),
			])
			item.draw_colored_polygon(hat, gear_col)
		"hood":
			item.draw_arc(head_center, r * 1.35, PI, TAU, 12, gear_col, w)
	match equipment_slots.get("feet", ""):
		"sandals":
			item.draw_line(
				foot_lead + Vector2(-r * 0.5, 0), foot_lead + Vector2(r * 0.5, 0), gear_col, w
			)
			item.draw_line(
				foot_off + Vector2(-r * 0.5, 0), foot_off + Vector2(r * 0.5, 0), gear_col, w
			)

	# Arm direction: from the shoulder through the lead hand, extended outward.
	var arm_dir: Vector2 = hand_lead - shoulder
	if arm_dir.length() < 0.001:
		arm_dir = Vector2.RIGHT
	arm_dir = arm_dir.normalized()
	var perp: Vector2 = arm_dir.orthogonal()
	var edge: Color = Color(0.07, 0.08, 0.13, col.a)  # dark under-edge (OUTLINE feel)
	match equipment_slots.get("weapon", ""):
		"sword":
			# Blade runs out along the arm; a short crossguard sits across the grip.
			var s_len: float = fig_height * 0.5
			var s_base: Vector2 = hand_lead - arm_dir * (fig_height * 0.05)
			var s_tip: Vector2 = hand_lead + arm_dir * s_len
			item.draw_line(hand_lead - perp * r * 0.7, hand_lead + perp * r * 0.7, edge, w * 1.1)
			item.draw_line(s_base, s_tip, edge, w * 1.5)          # dark edge under the blade
			item.draw_line(s_base, s_tip, gear_col, w * 0.95)     # blade body
			item.draw_line(
				hand_lead + arm_dir * (s_len * 0.4), s_tip, gear_col.lightened(0.35), w * 0.35
			)  # bright fuller/shine toward the tip
			item.draw_circle(s_tip, w * 0.5, gear_col)            # rounded point
		"staff":
			# Sleek short WAND: a thin shaft the hand grips, tipped with a small
			# glowing crystal (a cut gem) — reads cool without dominating the figure.
			var st_len: float = fig_height * 0.38
			var st_butt: Vector2 = hand_lead - arm_dir * (fig_height * 0.07)
			var st_tip: Vector2 = hand_lead + arm_dir * st_len
			item.draw_line(st_butt, st_tip, edge, w * 0.95)       # dark edge
			item.draw_line(st_butt, st_tip, gear_col, w * 0.55)   # thin shaft
			# Angular crystal tip (a small 4-point gem), glowing.
			var gem: float = maxf(w * 1.4, 2.4)
			var gp: Vector2 = arm_dir.orthogonal()
			var gem_pts: PackedVector2Array = PackedVector2Array([
				st_tip + arm_dir * gem, st_tip + gp * gem * 0.55,
				st_tip - arm_dir * gem * 0.45, st_tip - gp * gem * 0.55,
			])
			item.draw_colored_polygon(gem_pts, gear_col.lightened(0.45))
			item.draw_circle(st_tip + arm_dir * gem * 0.2, w * 0.45, Color(1, 1, 1, col.a))  # hot glint
		"orb":
			# A floating orb hovering just past the grip, with a soft halo.
			var o_c: Vector2 = hand_lead + arm_dir * (fig_height * 0.14)
			item.draw_circle(o_c, r * 0.85, Color(gear_col.r, gear_col.g, gear_col.b, col.a * 0.3))
			item.draw_circle(o_c, r * 0.55, gear_col.lightened(0.35))
