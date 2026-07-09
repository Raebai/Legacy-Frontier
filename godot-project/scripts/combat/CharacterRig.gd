class_name CharacterRig
extends Node2D
## Procedural stick-figure visual rig. Placeholder for real animated stick
## sprites later — the public API (play/set_facing/set_tint/flash/
## set_equipment/class_preset + hit_frame) is the swap contract.

signal hit_frame

enum State { IDLE, RUN, DASH, CAST, PUNCH, KICK, HURT }

## One-shot states auto-return to IDLE after their fixed duration.
const ONE_SHOT_DURATIONS: Dictionary = {
	State.PUNCH: 0.22,
	State.KICK: 0.26,
	State.CAST: 0.28,
	State.HURT: 0.18,
}
## Fraction of a PUNCH/KICK duration at which hit_frame fires.
const HIT_FRAME_FRACTION: float = 0.55

@export var limb_color: Color = Color(0.55, 0.75, 1.0, 1.0)
@export var height: float = 22.0

var state: State = State.IDLE
## slot ("head"/"body"/"feet"/"weapon") -> kind id ("" clears).
var equipment: Dictionary = {}

var _phase: float = 0.0
var _one_shot_active: bool = false
var _one_shot_time: float = 0.0
var _one_shot_duration: float = 0.0
var _hit_frame_emitted: bool = false
var _flash_timer: float = 0.0


func _process(delta: float) -> void:
	advance(delta)


## Per-frame update, split out from _process so headless tests can drive
## the rig deterministically without a real frame loop.
func advance(delta: float) -> void:
	_phase += delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
	if _one_shot_active:
		_one_shot_time += delta
		var is_strike: bool = state == State.PUNCH or state == State.KICK
		if is_strike and not _hit_frame_emitted \
				and _one_shot_time >= _one_shot_duration * HIT_FRAME_FRACTION:
			_hit_frame_emitted = true
			hit_frame.emit()
		if _one_shot_time >= _one_shot_duration:
			_one_shot_active = false
			state = State.IDLE
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


## Flip horizontally to face `dir`. Unchanged when dir.x == 0.
func set_facing(dir: Vector2) -> void:
	if dir.x < 0.0:
		scale.x = -1.0
	elif dir.x > 0.0:
		scale.x = 1.0


## Set the base limb/head color (enemy archetype tint, hero blue, ...).
func set_tint(color: Color) -> void:
	limb_color = color
	queue_redraw()


## Briefly whiten the whole figure (hit feedback), then restore the tint.
func flash(duration: float = 0.06) -> void:
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


## Convenience gear bundles — substrate for classes later.
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


func _draw() -> void:
	var col: Color = Color.WHITE if _flash_timer > 0.0 else limb_color
	var w: float = maxf(1.5, height * 0.09)
	var r: float = height * 0.16
	var arm_len: float = height * 0.32
	var leg_len: float = height * 0.4
	var t: float = 0.0
	if _one_shot_active and _one_shot_duration > 0.0:
		t = clampf(_one_shot_time / _one_shot_duration, 0.0, 1.0)
	var ext: float = sin(t * PI)  # 0 -> 1 at mid-point -> 0

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
			lean = height * 0.08
			var swing: float = sin(_phase * 12.0) * 0.55
			leg_lead = PI * 0.5 - swing
			leg_off = PI * 0.5 + swing
			arm_lead = PI * 0.5 + swing * 0.7
			arm_off = PI * 0.5 - swing * 0.7
			bob = absf(sin(_phase * 12.0)) * height * 0.02
		State.DASH:
			lean = height * 0.22
			leg_lead = PI * 0.5 + 0.55
			leg_off = PI * 0.5 + 0.85
			arm_lead = PI * 0.5 + 0.7
			arm_off = PI * 0.5 + 0.95
		State.CAST:
			lean = height * 0.05
			arm_lead = -0.12
			arm_off = 0.18
		State.PUNCH:
			lean = height * 0.06 * ext
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

	# Skeleton joints (local space; feet at +height/2, head top at -height/2).
	var head_center: Vector2 = Vector2(lean, -height * 0.5 + r + bob)
	var neck: Vector2 = head_center + Vector2(0, r)
	var hip: Vector2 = Vector2(0, height * 0.1 + bob * 0.5)
	var shoulder: Vector2 = neck.lerp(hip, 0.15)
	var hand_lead: Vector2 = shoulder + Vector2.from_angle(arm_lead) * arm_lead_len
	var hand_off: Vector2 = shoulder + Vector2.from_angle(arm_off) * arm_len
	var foot_lead: Vector2 = hip + Vector2.from_angle(leg_lead) * leg_lead_len
	var foot_off: Vector2 = hip + Vector2.from_angle(leg_off) * leg_len

	# Body-slot robe draws under the limbs.
	if equipment.get("body", "") == "robe":
		var robe: PackedVector2Array = PackedVector2Array([
			neck + Vector2(-r * 0.8, 0),
			neck + Vector2(r * 0.8, 0),
			hip + Vector2(r * 1.7, height * 0.22),
			hip + Vector2(-r * 1.7, height * 0.22),
		])
		draw_colored_polygon(robe, Color(col.r, col.g, col.b, 0.45))

	# The stick figure: head + torso + 2 arms + 2 legs.
	draw_circle(head_center, r, col)
	draw_line(neck, hip, col, w)
	draw_line(shoulder, hand_lead, col, w)
	draw_line(shoulder, hand_off, col, w)
	draw_line(hip, foot_lead, col, w)
	draw_line(hip, foot_off, col, w)

	_draw_equipment(col, w, r, head_center, hand_lead, foot_lead, foot_off)


func _draw_equipment(
	col: Color,
	w: float,
	r: float,
	head_center: Vector2,
	hand_lead: Vector2,
	foot_lead: Vector2,
	foot_off: Vector2,
) -> void:
	var gear_col: Color = col.lightened(0.25)
	match equipment.get("head", ""):
		"hat":
			var hat: PackedVector2Array = PackedVector2Array([
				head_center + Vector2(-r * 1.1, -r * 0.6),
				head_center + Vector2(r * 1.1, -r * 0.6),
				head_center + Vector2(0, -r * 2.3),
			])
			draw_colored_polygon(hat, gear_col)
		"hood":
			draw_arc(head_center, r * 1.35, PI, TAU, 12, gear_col, w)
	match equipment.get("feet", ""):
		"sandals":
			draw_line(foot_lead + Vector2(-r * 0.5, 0), foot_lead + Vector2(r * 0.5, 0), gear_col, w)
			draw_line(foot_off + Vector2(-r * 0.5, 0), foot_off + Vector2(r * 0.5, 0), gear_col, w)
	match equipment.get("weapon", ""):
		"sword":
			draw_line(hand_lead, hand_lead + Vector2(height * 0.32, -height * 0.1), gear_col, w)
		"staff":
			draw_line(
				hand_lead + Vector2(-height * 0.08, height * 0.3),
				hand_lead + Vector2(height * 0.1, -height * 0.55),
				gear_col, w
			)
			draw_circle(hand_lead + Vector2(height * 0.1, -height * 0.55), w * 1.2, gear_col)
		"orb":
			draw_circle(hand_lead + Vector2(height * 0.14, 0), r * 0.6, gear_col)
