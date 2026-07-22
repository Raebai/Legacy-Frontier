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

## Cast-gesture kinds — a small vocabulary of LIMB-ISOLATED "turn-on" tells that
## OVERLAY the lead arm only, so they compose over any locomotion (run/jump/dash).
## The ULTIMATE tier (float-channel) is a SEPARATE channel (Hero-side), not here.
enum GestureKind { NONE, FLICK, IGNITE_DROP, RAISE, GATHER, STOMP }

const GESTURE_DURATIONS: Dictionary = {
	GestureKind.FLICK: 0.12,        # quick snap — light bolts
	GestureKind.IGNITE_DROP: 0.20,  # hand drops, fist ignites — the fire-fist tell
	GestureKind.RAISE: 0.30,        # arm gathers overhead — medium AoE
	GestureKind.GATHER: 0.50,       # both hands to chest then thrust — heavy
	GestureKind.STOMP: 0.24,        # fist drives down + foot plant — earth
}

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
const OUTLINE_COLOR: Color = Color(0.10, 0.11, 0.16, 0.85)  # soft rim, not a jet-black keyline (SF is flat/solid)
const OUTLINE_EXTRA: float = 1.0                            # thin edge, not a fat cartoon outline
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
## The FEET spring softer than the rest so the legs lag, swing, and settle loosely
## as you walk (maker: "the legs should feel free and flowy like Stick Fight").
## Lower = floppier legs. Applied on top of the global stiffness in _step_sim.
const LOOSE_LEG_STIFFNESS: float = 0.5
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
## slot -> Texture2D pixel-art overlay. When a set_equipment kind has a matching
## piece in EQUIP_TEX, the TEXTURE supersedes the procedural draw for that slot
## (drawn at the head/hand/body anchor, tracking the pose + facing flip). This is
## how PixelLab-generated gear "customises the stick figure" WITHOUT replacing it.
var equipment_tex: Dictionary = {}
## Equipment-kind -> pixel-art overlay path (PixelLab-generated, see
## python-tools/pixellab_gen.py). A kind with no entry falls back to the procedural
## piece in draw_figure, so partial coverage is fine.
const EQUIP_TEX: Dictionary = {
	"hat": "res://assets/sprites/equipment/hat_wizard.png",
	"hood": "res://assets/sprites/equipment/hood.png",
	"staff": "res://assets/sprites/equipment/staff.png",
	"sword": "res://assets/sprites/equipment/sword.png",
	"hammer": "res://assets/sprites/equipment/hammer.png",
	"scythe": "res://assets/sprites/equipment/scythe.png",
	"orb": "res://assets/sprites/equipment/orb.png",
}

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
## Grounded flag (driven by Hero.is_on_floor). When limp + grounded, the ragdoll
## droop is clamped to the floor line so hold-DOWN ducking can't sink the drawn
## limbs THROUGH the collision (maker: "ducking clips the hero into the floor").
var _grounded: bool = true
## Active-ragdoll sim state: joint key -> simulated LOCAL position / velocity.
## Lazily seeded to the current target pose on first use so limbs never spring
## in from the origin. Pure Dictionary/Vector2 math — headless-safe.
var _sim: Dictionary = {}
var _sim_vel: Dictionary = {}
var _sim_ready: bool = false
## Limpness 0 (fully animated) .. 1 (ragdoll: weak springs + gravity droop).
var _limp: float = 0.0
var _limp_target: float = 0.0
## Transient flop-on-hit: raises _limp_target for a beat then restores whatever it
## was before (so a hit-flop doesn't clobber a held hold-DOWN ragdoll).
var _flop_timer: float = 0.0
var _flop_prev_target: float = 0.0
## Cast-gesture overlay channel — independent of the State one-shot machine so a
## tell can play WHILE running/jumping/dashing. Offsets only the lead arm.
var _gesture_kind: int = GestureKind.NONE
var _gesture_time: float = 0.0
var _gesture_dur: float = 0.0
var _gesture_intensity: float = 0.0  # 0..1 spell power -> offset amplitude + VFX size
var _gesture_element: int = -1       # Elements.Element id for the hand VFX, -1 = none
var _gesture_active: bool = false
## Body velocity fed by set_body_velocity(); its frame-to-frame CHANGE nudges
## the extremities so limbs trail when the body launches/stops.
var _body_vel: Vector2 = Vector2.ZERO
var _prev_body_vel: Vector2 = Vector2.ZERO
## Hard-CC freeze: while true the locomotion cycle (_phase) HOLDS so a frozen /
## shocked enemy reads as genuinely rooted under the ice instead of jogging in
## place. The spring sim + timers still tick (a hit still flails, flashes clear),
## only the animation clock stops. Set by the owner from StatusComponent.is_hard_cc.
var _frozen: bool = false
## Twin-stick lead-arm aim (Hero only): when true the lead arm CONTINUOUSLY points
## at the cursor (_aim_world) while IDLE/RUN, not just during a CAST — so the
## visible hand always aims where the mouse is (Stick-Fight). Enemies leave this
## false so their arms keep the locomotion swing.
var aim_arm: bool = false
## Persistent flaming-fist charge 0..1 (set by Hero after a fire punch): bulks the
## lead fist and drives the on-hand fire draw + embers (item 3). 0 = no fire.
var _hand_fire: float = 0.0
var _hand_fire_element: int = -1


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
	if _flop_timer > 0.0:
		_flop_timer -= delta
		if _flop_timer <= 0.0:
			_limp_target = _flop_prev_target  # recover to the pre-flop resting limp
	if _gesture_active:
		# Real delta, NOT gated by _frozen — a cast tell should still finish under CC.
		_gesture_time += delta
		if _gesture_time >= _gesture_dur:
			_gesture_active = false
			_gesture_kind = GestureKind.NONE
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
	var leg_stiffness: float = stiffness * LOOSE_LEG_STIFFNESS
	for key: String in SIM_JOINTS:
		var target: Vector2 = target_pose[key]
		var vel: Vector2 = _sim_vel[key]
		# The feet spring softer -> the legs lag + swing loosely (the flowy walk).
		var k_stiff: float = leg_stiffness if (key == "foot_lead" or key == "foot_off") else stiffness
		vel += (target - _sim[key]) * k_stiff * delta
		vel += Vector2(0.0, GRAVITY * _limp) * delta
		if SIM_EXTREMITIES.has(key):
			vel += trail
		vel *= damp
		var pos: Vector2 = _sim[key] + vel * delta
		var off: Vector2 = pos - target
		var off_len: float = off.length()
		if off_len > max_off:
			pos = target + off / off_len * max_off
		# Ducking (hold-DOWN ragdoll) must never droop THROUGH the floor: when limp
		# AND grounded, clamp each joint to the standing foot line (y = height*0.5,
		# where the animated feet already rest) and kill downward velocity so the
		# limbs settle ON the floor instead of sinking below the collision box. Only
		# grounded — a mid-air knockback ragdoll still flails freely.
		if _grounded and _limp > 0.01:
			var floor_y: float = height * 0.5
			if pos.y > floor_y:
				pos.y = floor_y
				if vel.y > 0.0:
					vel.y = 0.0
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


## Flop-on-hit: briefly weaken the springs (raise the limp target) so the body
## visibly reels from a blow, then auto-recover to whatever the limp was before
## (0 normally, or 1 if a hold-DOWN ragdoll is active — so they don't fight).
## `strength` 0..1 = how limp; `hold` = seconds before recovery starts. Pair with
## apply_impulse() for the directional whip. Eased both ways via set_limp/advance.
func flop(strength: float = 0.7, hold: float = 0.18) -> void:
	if _flop_timer <= 0.0:
		_flop_prev_target = _limp_target  # remember the resting limp only on entry
	_flop_timer = maxf(_flop_timer, hold)
	_limp_target = maxf(_limp_target, clampf(strength, 0.0, 1.0))


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


## Enable twin-stick lead-arm aim (Hero only): the lead arm continuously points at
## the cursor while IDLE/RUN so the visible hand always aims where the mouse is.
func set_aim_arm(enabled: bool) -> void:
	aim_arm = enabled


## Set the persistent flaming-fist charge (0..1) + its element. Bulks the lead fist
## and drives the on-hand fire draw + trailing embers (fire-punch afterglow, item 3).
func set_hand_fire(strength: float, element: int = -1) -> void:
	_hand_fire = clampf(strength, 0.0, 1.0)
	if element >= 0:
		_hand_fire_element = element
	queue_redraw()


## Fire a limb-isolated cast "turn-on" tell that OVERLAYS the lead arm only, so it
## composes with whatever locomotion is active (run/jump/dash) instead of locking
## the body. Independent of the State machine — call alongside play(CAST) or alone.
## `intensity` 0..1 scales the offset amplitude + VFX size (spell power). `element`
## (Elements.Element id, or -1) drives the hand ignite VFX; -1 = motion only.
func cast_gesture(kind: int, intensity: float = 0.6, element: int = -1) -> void:
	_gesture_kind = kind
	_gesture_intensity = clampf(intensity, 0.0, 1.0)
	_gesture_element = element
	_gesture_dur = float(GESTURE_DURATIONS.get(kind, 0.2)) * (0.9 + 0.2 * _gesture_intensity)
	_gesture_time = 0.0
	_gesture_active = kind != GestureKind.NONE
	queue_redraw()


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


## World position of the LEAD hand (the simulated/drawn one), for trailing fire
## embers etc. Uses the physical sim pose so embers follow the actual drawn hand.
func get_lead_hand_global() -> Vector2:
	return to_global(_sim_pose()["hand_lead"])


## Flight lift, 0 (grounded) .. 1 (airborne). Driven by Hero._update_flight;
## raises the drawn figure and drops a shrinking ground shadow beneath it.
func set_airborne(v: float) -> void:
	_airborne = clampf(v, 0.0, 1.0)
	queue_redraw()


## Grounded state from the owning body (Hero.is_on_floor). Gates the limp
## floor-clamp in _step_sim so ducking never sinks the ragdoll into the ground.
func set_grounded(g: bool) -> void:
	_grounded = g


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
		equipment_tex.erase(slot)
	else:
		equipment[slot] = kind          # always record the LOGICAL kind (state/tests)
		var tex: Texture2D = _equip_texture(kind)
		if tex != null:
			equipment_tex[slot] = tex   # a pixel-art piece exists -> draw it, skip procedural
		else:
			equipment_tex.erase(slot)   # no texture -> draw_figure draws the procedural piece
	queue_redraw()


## The PixelLab pixel-art overlay for an equipment kind, or null if none exists
## (falls back to the procedural draw). Cached by the resource loader.
func _equip_texture(kind: String) -> Texture2D:
	var path: String = EQUIP_TEX.get(kind, "")
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


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
		"juggernaut":  # heavy — bare torso, two-handed war hammer
			set_equipment("body", "")
			set_equipment("head", "")
			set_equipment("weapon", "hammer")
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
		"warlock":  # hooded hexer with a scythe
			set_equipment("body", "robe")
			set_equipment("head", "hood")
			set_equipment("weapon", "scythe")


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
	# Slots with a pixel-art overlay are drawn as textures below — hide their
	# procedural version so the two don't stack (the logical `equipment` is intact).
	var procedural: Dictionary = equipment
	if not equipment_tex.is_empty():
		procedural = {}
		for s: String in equipment:
			if not equipment_tex.has(s):
				procedural[s] = equipment[s]
	draw_figure(self, pose, col, procedural, height, OUTLINE_COLOR)
	if not equipment_tex.is_empty():
		_draw_equipment_textures(pose)
	_draw_slash_arc(pose, col)
	_draw_parry_shield(pose)
	_draw_cast_gesture_vfx(pose)
	_draw_hand_fire(pose)


## Persistent flaming fist: while a fire charge is active (set_hand_fire after a
## fire punch), a small realistic flame licks off the LEAD hand every frame (the
## fire "stays lit" and TRAILS as the hand moves — item 3). Kept SMALL on-character.
func _draw_hand_fire(pose: Dictionary) -> void:
	if _hand_fire <= 0.01 or _hand_fire_element != Elements.Element.FIRE:
		return
	draw_flame(self, pose["hand_lead"], pose["w"] * 1.7, _hand_fire, _phase)


## Crisp pixel-art gear: nearest sampling so the PixelLab overlays don't blur when
## scaled to the rig (the procedural AA lines are unaffected — filter is texture-only).
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Draw the pixel-art gear overlays at their pose anchors, ON TOP of the stick
## figure. Scaled to the rig height; the facing flip (node scale.x) carries the
## horizontal mirror for free since this draws in the rig's local frame. Head gear
## caps the head, weapons rise from the lead hand. This is the "customise the stick
## figure" layer — the silhouette stays a stick, the gear gives it identity.
func _draw_equipment_textures(pose: Dictionary) -> void:
	var r: float = pose["r"]
	for slot: String in equipment_tex:
		var tex: Texture2D = equipment_tex[slot]
		if tex == null or not is_instance_valid(tex):
			continue
		var tsz: Vector2 = tex.get_size()
		if tsz.x <= 0.0 or tsz.y <= 0.0:
			continue
		var anchor: Vector2
		var target_h: float
		match slot:
			"head":
				anchor = pose["head_center"] - Vector2(0.0, r * 0.85)  # sit ON the head
				target_h = r * 2.4
			"weapon":
				# Tall weapons (staff/sword/hammer/scythe) fill the figure height; a
				# square-ish held item (orb) is a small hand prop, not a polearm.
				var aspect: float = tsz.x / tsz.y
				target_h = height * 0.55 if (aspect > 0.7 and aspect < 1.4) else height * 1.0
				anchor = pose["hand_lead"] - Vector2(0.0, target_h * 0.18)  # gripped, rises up
			"body":
				anchor = pose["shoulder"].lerp(pose["hip"], 0.5)
				target_h = height * 0.8
			_:
				anchor = pose["head_center"]
				target_h = height * 0.5
		var s: float = target_h / tsz.y
		var draw_sz: Vector2 = tsz * s
		draw_texture_rect(tex, Rect2(anchor - draw_sz * 0.5, draw_sz), false)


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


## Per-element hand "ignite" VFX drawn at the casting hand during a cast gesture —
## the "turn-on" tell (fire fist, frost hand, sparking fist...). Reuses the HDR-core
## + AA bloom idiom; the glow envelope ignites and dies with the gesture. Only runs
## at draw time (never headless), so Elements lookups here are safe.
func _draw_cast_gesture_vfx(pose: Dictionary) -> void:
	if not _gesture_active or _gesture_element < 0:
		return
	var gu: float = clampf(_gesture_time / _gesture_dur, 0.0, 1.0)
	var glow: float = sin(gu * PI) * (0.4 + 0.6 * _gesture_intensity)
	if glow <= 0.01:
		return
	var p: Vector2 = pose["hand_lead"]
	var rad: float = pose["w"] * (1.6 + 1.4 * _gesture_intensity)
	var ec: Color = Elements.color(_gesture_element)
	var lifted: Color = Color(ec.r, ec.g, ec.b).lerp(Color(1, 1, 1), 0.4)
	var peak: float = maxf(lifted.r, maxf(lifted.g, lifted.b))
	var k: float = 1.55 / maxf(peak, 0.001)
	var core: Color = Color(lifted.r * k, lifted.g * k, lifted.b * k, glow)
	var halo: Color = Color(ec.r, ec.g, ec.b, glow * 0.35)
	match _gesture_element:
		Elements.Element.FIRE: _vfx_fire(p, rad, core, halo)
		Elements.Element.ICE: _vfx_ice(p, rad, core, halo)
		Elements.Element.LIGHTNING: _vfx_lightning(p, rad, core, halo)
		Elements.Element.SHADOW: _vfx_shadow(p, rad, core, halo)
		Elements.Element.ARCANE: _vfx_arcane(p, rad, core, halo)
		Elements.Element.EARTH: _vfx_earth(p, rad, halo)
		Elements.Element.HOLY: _vfx_holy(p, rad, core, halo)
		Elements.Element.WIND: _vfx_wind(p, rad, core, halo)
		_: draw_circle(p, rad * 0.6, core, true, -1.0, true)


func _vfx_fire(p: Vector2, rad: float, _core: Color, _halo: Color) -> void:
	# Realistic organic flame (maker: "the fire effect is so corny; make it seem
	# more like fire"). SMALL/subtle on-character — a compact licking flame, not a
	# big flashy overlay. The shared static draw_flame does tongues + embers.
	draw_flame(self, p, rad, 1.0, _phase)


## Layered organic flame: a deep-red -> orange -> white-hot core with noise-driven
## LICKING tongues (curved teardrops that waver, not flat triangles) and rising
## embers. Additive/HDR so the core blooms. `size` sets the scale, `strength` 0..1
## fades the whole thing. Local -y is UP so the flame rises. STATIC so any canvas
## item (the rig, the enemy status coat) draws the exact same fire. Draw-time only.
static func draw_flame(item: CanvasItem, p: Vector2, size: float, strength: float, phase: float) -> void:
	if strength <= 0.01:
		return
	# Soft outer glow: warm heat haze at the edges (kept faint so it never reads as
	# a dark disc — on the bright arena the bloom pass carries the glow).
	item.draw_circle(p + Vector2(0.0, -size * 0.2), size * 1.5, Color(1.0, 0.4, 0.12, 0.10 * strength), true, -1.0, true)
	# Licking tongues — teardrop polygons that waver with the phase and taper to a
	# flickering tip. Deep-red outer tongue with a brighter orange inner tongue.
	for i: int in 3:
		var seed: float = float(i) * 2.3
		var sway: float = sin(phase * 9.0 + seed) * size * 0.3
		var h: float = size * (1.5 + 0.55 * sin(phase * 13.0 + seed)) * (0.55 + 0.6 * strength)
		var base_w: float = size * (0.44 - 0.08 * float(i))
		var bx: float = (float(i) - 1.0) * size * 0.34
		var basep: Vector2 = p + Vector2(bx, size * 0.35)
		var tip: Vector2 = p + Vector2(bx + sway, -h)
		var mid: Vector2 = basep.lerp(tip, 0.5) + Vector2(sway * 0.5, 0.0)
		item.draw_colored_polygon(PackedVector2Array([
			basep + Vector2(-base_w, 0.0), basep + Vector2(base_w, 0.0),
			mid + Vector2(base_w * 0.5, 0.0), tip, mid + Vector2(-base_w * 0.5, 0.0),
		]), Color(0.9, 0.24, 0.05, 0.6 * strength))
		var iw: float = base_w * 0.55
		item.draw_colored_polygon(PackedVector2Array([
			basep + Vector2(-iw, 0.0), basep + Vector2(iw, 0.0),
			mid.lerp(tip, 0.2) + Vector2(iw * 0.5, 0.0), tip.lerp(basep, 0.12),
			mid.lerp(tip, 0.2) + Vector2(-iw * 0.5, 0.0),
		]), Color(1.15, 0.55, 0.12, 0.8 * strength))
	# White-hot core (HDR > 1 so the bloom pass lifts it).
	item.draw_circle(p + Vector2(0.0, size * 0.05), size * 0.42, Color(1.7, 1.1, 0.5, 0.9 * strength), true, -1.0, true)
	# Rising embers that drift up + fade.
	for i: int in 3:
		var span: float = size * 3.2
		var ey: float = -fposmod(phase * 34.0 + float(i) * 19.0, span)
		var ex: float = sin(phase * 3.0 + float(i) * 2.1) * size * 0.5
		var ea: float = clampf((1.0 - (-ey) / span) * 0.85 * strength, 0.0, 1.0)
		item.draw_circle(p + Vector2(ex, ey), maxf(1.0, size * 0.09), Color(1.4, 0.65, 0.2, ea), true, -1.0, true)


func _vfx_ice(p: Vector2, rad: float, core: Color, halo: Color) -> void:
	draw_arc(p, rad, 0.0, TAU, 12, halo, 1.5, true)
	for i in 6:
		var a: float = TAU * float(i) / 6.0 + _phase * 0.5
		draw_line(p, p + Vector2.from_angle(a) * rad * 1.3, core, 1.6, true)
	draw_circle(p, rad * 0.35, core, true, -1.0, true)


func _vfx_lightning(p: Vector2, rad: float, core: Color, halo: Color) -> void:
	draw_circle(p, rad * 1.2, halo, true, -1.0, true)
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + _phase * 3.0
		var d: Vector2 = Vector2.from_angle(a)
		var pts: PackedVector2Array = PackedVector2Array([
			p, p + d * rad * 0.7 + d.orthogonal() * sin(_phase * 40.0 + float(i)) * rad * 0.3, p + d * rad * 1.4
		])
		draw_polyline(pts, core, 1.4, true)
	draw_circle(p, rad * 0.4, core, true, -1.0, true)


func _vfx_shadow(p: Vector2, rad: float, _core: Color, halo: Color) -> void:
	for i in 2:
		var a0: float = _phase * 1.5 + PI * float(i)
		draw_arc(p, rad * (0.9 + 0.3 * float(i)), a0, a0 + PI * 0.9, 12,
			Color(halo.r, halo.g, halo.b, halo.a * 1.6), 2.0, true)
	draw_circle(p, rad * 0.5, Color(0.5, 0.3, 0.9, halo.a * 1.6), true, -1.0, true)


func _vfx_arcane(p: Vector2, rad: float, core: Color, halo: Color) -> void:
	draw_arc(p, rad, 0.0, TAU, 20, halo, 1.5, true)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 4:
		var a: float = TAU * float(i) / 3.0 + _phase * 2.0  # spinning triangle (wraps closed)
		pts.append(p + Vector2.from_angle(a) * rad * 0.8)
	draw_polyline(pts, core, 1.4, true)
	draw_circle(p, rad * 0.3, core, true, -1.0, true)


func _vfx_earth(p: Vector2, rad: float, halo: Color) -> void:
	# Matte stone chunks coat the fist — no bloom core (earth reads solid, not lit).
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + 0.4
		var c: Vector2 = p + Vector2.from_angle(a) * rad * 0.7
		var s: float = rad * 0.5
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-s, -s * 0.6), c + Vector2(s, -s * 0.4), c + Vector2(s * 0.7, s), c + Vector2(-s * 0.8, s * 0.7)
		]), Color(0.42, 0.3, 0.18, clampf(halo.a * 2.4, 0.0, 1.0)))
	draw_circle(p, rad * 0.3, Color(0.6, 0.46, 0.26, clampf(halo.a * 2.2, 0.0, 1.0)), true, -1.0, true)


func _vfx_holy(p: Vector2, rad: float, core: Color, halo: Color) -> void:
	draw_arc(p, rad * 1.3, 0.0, TAU, 20, core, 1.6, true)
	draw_circle(p, rad * 1.6, Color(halo.r, halo.g, halo.b, halo.a * 0.8), true, -1.0, true)
	draw_circle(p, rad * 0.4, core, true, -1.0, true)


func _vfx_wind(p: Vector2, rad: float, core: Color, _halo: Color) -> void:
	for i in 2:
		var pts: PackedVector2Array = PackedVector2Array()
		for j in 8:
			var t: float = float(j) / 7.0
			var a: float = _phase * 2.0 + PI * float(i) + t * TAU * 0.6
			pts.append(p + Vector2.from_angle(a) * rad * (0.3 + t))
		draw_polyline(pts, Color(core.r, core.g, core.b, core.a * 0.7), 1.5, true)


## Compute the current pose skeleton in local space. Keys: head_center,
## neck, hip, shoulder, hand_lead, hand_off, foot_lead, foot_off,
## plus stroke metrics r (head radius) and w (line width).
func _compute_pose() -> Dictionary:
	var w: float = maxf(2.0, height * 0.12)   # a touch bolder for the iconic SF limb read
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
	var leg_off_len: float = leg_len

	match state:
		State.IDLE:
			bob = sin(_phase * 2.0) * height * 0.03
		State.RUN:
			# Smoother, weightier gait (Stick-Fight feel): a calmer stride
			# frequency, a real leg lift on the back-swing (stride, not a scissor),
			# arm counter-swing, and a two-step bounce synced to the footfalls.
			# Looser, bigger stride — the legs swing wide and the knees lift more, so
			# the soft foot-springs (LOOSE_LEG_STIFFNESS) let them lag + flop loosely
			# for the free, flowy Stick-Fight walk.
			var sp: float = _phase * 9.0
			var swing: float = sin(sp) * 1.1
			lean = height * 0.13
			leg_lead = PI * 0.5 - swing
			leg_off = PI * 0.5 + swing
			# Lift whichever leg is swinging back (knee bends up) — both legs, opposite
			# phase — for a loose knees-up gait rather than stiff scissoring sticks.
			leg_lead_len = leg_len * (1.0 - 0.24 * maxf(-sin(sp), 0.0))
			leg_off_len = leg_len * (1.0 - 0.24 * maxf(sin(sp), 0.0))
			arm_lead = PI * 0.5 + swing * 0.7
			arm_off = PI * 0.5 - swing * 0.7
			bob = absf(sin(sp)) * height * 0.06
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

	# Twin-stick lead-arm AIM (Hero only, via set_aim_arm): outside the committed
	# CAST/strike poses the lead arm CONTINUOUSLY points at the cursor while idle or
	# running, so the visible hand always aims where the mouse is (Stick-Fight). The
	# spring sim eases the drawn hand so it tracks smoothly instead of snapping; the
	# OFF arm keeps its locomotion swing so the body still reads as running.
	if aim_arm and (state == State.IDLE or state == State.RUN):
		var aim_s: float = 1.0 if scale.x >= 0.0 else -1.0
		var aim_local: Vector2 = Vector2(_aim_world.x * aim_s, _aim_world.y)
		if aim_local.length() > 0.001:
			arm_lead = aim_local.angle()
			arm_lead_len = arm_len

	# Skeleton joints (local space; feet at +height/2, head top at -height/2).
	var head_center: Vector2 = Vector2(lean, -height * 0.5 + r + bob)
	var neck: Vector2 = head_center + Vector2(0, r)
	var hip: Vector2 = Vector2(0, height * 0.1 + bob * 0.5)
	var shoulder: Vector2 = neck.lerp(hip, 0.15)
	var hand_lead: Vector2 = shoulder + Vector2.from_angle(arm_lead) * arm_lead_len
	var hand_off: Vector2 = shoulder + Vector2.from_angle(arm_off) * arm_len
	var foot_lead: Vector2 = hip + Vector2.from_angle(leg_lead) * leg_lead_len
	var foot_off: Vector2 = hip + Vector2.from_angle(leg_off) * leg_off_len

	# Cast-gesture overlay: additive, lead-arm-isolated, composes over locomotion.
	# Damped out automatically when limp (the sim's stiffness is _limp-scaled).
	if _gesture_active and _limp < 0.9:
		var gu: float = clampf(_gesture_time / _gesture_dur, 0.0, 1.0)
		var amp: float = height * (0.25 + 0.55 * _gesture_intensity)
		var cast_s: float = 1.0 if scale.x >= 0.0 else -1.0
		var aim_l: Vector2 = Vector2(_aim_world.x * cast_s, _aim_world.y)
		if aim_l.length() < 0.001:
			aim_l = Vector2.RIGHT
		aim_l = aim_l.normalized()
		var aim_perp: Vector2 = aim_l.orthogonal()
		match _gesture_kind:
			GestureKind.FLICK:
				var e: float = sin(gu * PI)  # 0..1..0 snap out then back
				hand_lead += aim_l * amp * 0.9 * e - aim_perp * amp * 0.25 * e
				shoulder += aim_l * amp * 0.12 * e
			GestureKind.IGNITE_DROP:
				var drop: float = 1.0 - pow(1.0 - gu, 2.0)  # ease-out drop
				var back: float = sin(gu * PI)              # recover hump
				hand_lead += Vector2(0.0, amp * 0.8) * drop * (1.0 - 0.6 * back) - aim_l * amp * 0.2 * back
				shoulder += Vector2(0.0, amp * 0.15) * drop
			GestureKind.RAISE:
				var e3: float = sin(gu * PI)
				hand_lead += Vector2(-aim_l.x * amp * 0.3, -amp * 1.1) * e3
				shoulder += Vector2(0.0, -amp * 0.2) * e3
			GestureKind.GATHER:
				var pull: float = smoothstep(0.0, 0.55, gu)
				var thrust: float = smoothstep(0.55, 1.0, gu)
				var chest: Vector2 = shoulder.lerp(hip, 0.35) - hand_lead
				hand_lead += chest * 0.7 * pull * (1.0 - thrust) + aim_l * amp * 1.2 * thrust
				hand_off += (shoulder.lerp(hip, 0.35) - hand_off) * 0.6 * pull * (1.0 - thrust)
				shoulder += aim_l * amp * 0.25 * thrust - Vector2(0.0, amp * 0.1) * pull
			GestureKind.STOMP:
				var slam: float = 1.0 - pow(1.0 - gu, 3.0)  # hard ease-out slam
				var settle: float = sin(gu * PI)
				hand_lead += Vector2(aim_l.x * amp * 0.2, amp * 1.0) * slam
				shoulder += Vector2(0.0, amp * 0.2) * slam
				foot_lead += Vector2(aim_l.x * amp * 0.3, amp * 0.15) * settle

	# Hands/feet as Stick-Fight capsule CAPS (radius = half the limb width) — no
	# ball fists, no toes. The lead hand gets a whisper of clench through a strike
	# and a modest bulk on a flaming charge, but stays SF-scale (the flame VFX
	# carries the fire read, not a bloated fist).
	var hand_base_r: float = w * 0.5
	var hand_lead_r: float = hand_base_r
	if is_strike:
		hand_lead_r = w * lerpf(0.5, 0.8, clampf(ext, 0.0, 1.0))  # subtle SF-scale clench
	if _hand_fire > 0.01:
		hand_lead_r = maxf(hand_lead_r, w * (0.6 + 0.4 * _hand_fire))
	var foot_r: float = w * 0.5

	return {
		"head_center": head_center,
		"neck": neck,
		"hip": hip,
		"shoulder": shoulder,
		"hand_lead": hand_lead,
		"hand_off": hand_off,
		"foot_lead": foot_lead,
		"foot_off": foot_off,
		"hand_lead_r": hand_lead_r,
		"hand_off_r": hand_base_r,
		"foot_r": foot_r,
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
	# Visible hand/fist + foot radii (default to the old joint-cap size for any
	# hand-built pose that predates them, so callers never break).
	var hlr: float = pose.get("hand_lead_r", w * 0.5)
	var hor: float = pose.get("hand_off_r", w * 0.5)
	var ftr: float = pose.get("foot_r", w * 0.5)

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
		item.draw_circle(hand_lead, hlr + OUTLINE_EXTRA * 0.6, oc)
		item.draw_circle(hand_off, hor + OUTLINE_EXTRA * 0.6, oc)
		item.draw_circle(foot_lead, ftr + OUTLINE_EXTRA * 0.5, oc)
		item.draw_circle(foot_off, ftr + OUTLINE_EXTRA * 0.5, oc)
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
	# VISIBLE hands/fists — clearly bigger than a joint cap (Stick-Fight read); the
	# lead fist grows through a strike / flaming charge via hlr from _compute_pose.
	item.draw_circle(hand_off, hor, col)
	item.draw_circle(hand_lead, hlr, col)
	# Feet: rounded leg-ends only (SF has no toe nub).
	item.draw_circle(foot_off, ftr, col)
	item.draw_circle(foot_lead, ftr, col)

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
