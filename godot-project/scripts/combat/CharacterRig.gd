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

## Dash afterimages: script loaded lazily to keep the dependency one-way
## (RigGhost references CharacterRig for the shared figure draw).
const GHOST_SCRIPT_PATH: String = "res://scripts/combat/RigGhost.gd"
const MAX_GHOSTS: int = 24
## Aura tuning: layer count + pulse speed/amount.
const AURA_LAYERS: int = 3
const AURA_PULSE_SPEED: float = 3.2
const AURA_PULSE_AMOUNT: float = 0.15

@export var limb_color: Color = Color(0.55, 0.75, 1.0, 1.0)
@export var height: float = 22.0
## Soft radial glow under the figure ("charged" hero read). Strength 0
## disables it entirely — enemies stay bare sticks.
@export var aura_color: Color = Color(0.4, 0.7, 1.0, 1.0)
@export var aura_strength: float = 0.0

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


## Enable/retint the under-figure aura glow. strength 0 turns it off.
func set_aura(color: Color, strength: float = 1.0) -> void:
	aura_color = color
	aura_strength = strength
	queue_redraw()


## Spawn a static, fading afterimage of the current pose under `parent`
## (dash trail). Pure visual: no animation, no collision; self-frees.
func spawn_ghost(parent: Node, ghost_color: Color, wind_dir: Vector2 = Vector2.ZERO) -> void:
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
	parent.add_child(ghost)
	ghost.global_transform = global_transform
	ghost.z_index = -1


func _draw() -> void:
	var col: Color = Color.WHITE if _flash_timer > 0.0 else limb_color
	_draw_aura()
	draw_figure(self, _compute_pose(), col, equipment, height)


## Concentric fading circles under the figure, gently pulsing.
func _draw_aura() -> void:
	if aura_strength <= 0.0:
		return
	var pulse: float = 1.0 - AURA_PULSE_AMOUNT * 0.5 \
			+ AURA_PULSE_AMOUNT * 0.5 * sin(_phase * AURA_PULSE_SPEED)
	var center: Vector2 = Vector2(0.0, height * 0.05)
	for i: int in range(AURA_LAYERS):
		var frac: float = 1.0 - float(i) / float(AURA_LAYERS)  # 1.0 -> outermost
		var radius: float = height * (0.35 + 0.45 * frac) * pulse
		var alpha: float = aura_strength * 0.05 * (float(i) + 1.0)
		draw_circle(center, radius, Color(aura_color.r, aura_color.g, aura_color.b, alpha))


## Compute the current pose skeleton in local space. Keys: head_center,
## neck, hip, shoulder, hand_lead, hand_off, foot_lead, foot_off,
## plus stroke metrics r (head radius) and w (line width).
func _compute_pose() -> Dictionary:
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

	# Body-slot robe draws under the limbs.
	if equipment_slots.get("body", "") == "robe":
		var robe: PackedVector2Array = PackedVector2Array([
			neck + Vector2(-r * 0.8, 0),
			neck + Vector2(r * 0.8, 0),
			hip + Vector2(r * 1.7, fig_height * 0.22),
			hip + Vector2(-r * 1.7, fig_height * 0.22),
		])
		item.draw_colored_polygon(robe, Color(col.r, col.g, col.b, col.a * 0.45))

	# The stick figure: head + torso + 2 arms + 2 legs.
	item.draw_circle(head_center, r, col)
	item.draw_line(neck, hip, col, w)
	item.draw_line(shoulder, hand_lead, col, w)
	item.draw_line(shoulder, hand_off, col, w)
	item.draw_line(hip, foot_lead, col, w)
	item.draw_line(hip, foot_off, col, w)

	_draw_equipment(
		item, equipment_slots, col, w, r, fig_height,
		head_center, hand_lead, foot_lead, foot_off
	)


static func _draw_equipment(
	item: CanvasItem,
	equipment_slots: Dictionary,
	col: Color,
	w: float,
	r: float,
	fig_height: float,
	head_center: Vector2,
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
	match equipment_slots.get("weapon", ""):
		"sword":
			item.draw_line(
				hand_lead, hand_lead + Vector2(fig_height * 0.32, -fig_height * 0.1), gear_col, w
			)
		"staff":
			item.draw_line(
				hand_lead + Vector2(-fig_height * 0.08, fig_height * 0.3),
				hand_lead + Vector2(fig_height * 0.1, -fig_height * 0.55),
				gear_col, w
			)
			item.draw_circle(
				hand_lead + Vector2(fig_height * 0.1, -fig_height * 0.55), w * 1.2, gear_col
			)
		"orb":
			item.draw_circle(hand_lead + Vector2(fig_height * 0.14, 0), r * 0.6, gear_col)
