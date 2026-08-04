extends CharacterBody2D
## Hub player — now SIDE-ON (gravity + jump), matching the combat feel (maker:
## "the lobby should be side-on all the time like the battle place"). A/D move,
## W/Up/Space jump; stands + jumps on the town ground plane.

const SPEED: float = 200.0
const GRAVITY: float = 1400.0
const JUMP_VELOCITY: float = -520.0
const MAX_FALL: float = 1000.0

@onready var speech_bubble: Node2D = $SpeechBubble

## The procedural stick figure that replaces the old block placeholder (maker:
## "everything should be in stick form"). Tinted to the chosen class.
var _rig: CharacterRig = null


func _ready() -> void:
	# Replace the block "Visual" with a stick-figure rig (same look as combat).
	var block: Node = get_node_or_null("Visual")
	if block != null:
		(block as CanvasItem).visible = false
	_rig = CharacterRig.new()
	add_child(_rig)
	_rig.play(CharacterRig.State.IDLE)
	# Feet-on-ground: the rig draws its feet height*0.5 BELOW its origin, and the
	# 16x16 collision is centred. Shift the collision up so the node origin sits at
	# the feet, then lift the rig so its drawn feet land on that origin — no more
	# characters sunk into the floor.
	for c: Node in get_children():
		if c is CollisionShape2D:
			(c as CollisionShape2D).position.y -= 8.0
	_rig.position.y = -_rig.height * 0.5
	var gs: Node = get_node_or_null("/root/GameState")
	var idx: int = int(gs.get("selected_class")) if gs != null else 0
	_rig.set_tint(ClassInfo.color_for(idx))


## Retint the stick figure to a class colour (called by the Class-Select panel).
func set_class_tint(c: Color) -> void:
	if _rig != null:
		_rig.set_tint(c)


## Live loadout PREVIEW for the hub Armory (Loadout UI): dress the hub stick in the
## class's default gear (`preset`) then apply the chosen weapon/head/body overrides
## so the player sees exactly what the run hero will wear. Cosmetic only.
func preview_loadout(preset: String, loadout: Dictionary) -> void:
	if _rig == null:
		return
	if preset != "":
		_rig.class_preset(preset)
	for slot: String in ["weapon", "head", "body"]:
		var kind: String = String(loadout.get(slot, ""))
		if kind != "":
			_rig.set_equipment(slot, kind)


func _physics_process(delta: float) -> void:
	# Frozen while any town screen is up — gravity still applies so we rest on the
	# ground, but no walking or jumping underneath an open panel.
	#
	# ⚠ `Conversation.is_input_open()` used to be the first term here, as a BARE
	# GLOBAL. That autoload is deleted with the rest of the LLM stack, and a bare
	# global to a missing autoload is a parse error that stops the whole town scene
	# loading — which is exactly why the stack was parked rather than removed
	# before. Everything this gate asks is now asked through the tree.
	if _screen_open():
		velocity.x = 0.0
		velocity.y = 0.0 if is_on_floor() else minf(velocity.y + GRAVITY * delta, MAX_FALL)
		move_and_slide()
		if _rig != null:
			# Frozen under a panel still has to tell the truth about the floor, or the
			# figure stands on its knees behind the screen you are reading.
			_rig.set_grounded(is_on_floor())
			_rig.set_body_velocity(Vector2.ZERO)
			_rig.set_air_phase(false, is_on_floor())
			_rig.play(CharacterRig.State.IDLE)
		return
	# Side-on: horizontal walk, gravity, jump off the ground.
	var move_x: float = Input.get_axis("move_left", "move_right")
	velocity.x = move_x * SPEED
	if is_on_floor():
		velocity.y = 0.0
		if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_up"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	move_and_slide()
	_drive_rig(move_x)


## ══ THE TOWN WAS RUNNING THE RIG BLIND, AND THAT IS THE BENT-LEGS BUG ═════════
##
## Maker, 2026-08-04: "the movement of the characters and the stick figures are all
## messed up… everyone is walking on their limbs".
##
## `CharacterRig` is the SAME rig the combat hero uses — the town was never using a
## different or older one. What it was not doing is TELLING it anything. `Hero`
## feeds three signals every physics frame and this file fed none of them:
##
##   1. `set_grounded()` — and this is the one that caused the picture. It gates the
##      floor clamp in `_step_sim`, and it **defaults to `true`**. So a rig nobody
##      talks to believes it is standing on the ground AT ALL TIMES — including at
##      the top of a jump. The feet stayed pinned to the ground plane while the hips
##      rose, the two-bone IK had to fold a leg that could not reach, and the figure
##      walked on its knees through the air.
##   2. `set_body_velocity()` — the inertial trail on the extremities. Without it
##      the limbs are rigid under acceleration and the walk reads as a puppet.
##   3. `set_air_phase()` — biases the airborne looseness (rising = coiled, falling
##      = loose, grounded = settled). `play(State.DASH)` was standing in for a jump
##      pose, which is a taut DASH read on a body that is actually falling.
##
## ⚠ THE STATE IS `AIR`, NOT `DASH`. The rig has a real airborne state that the air
## phase above drives; DASH is a horizontal lunge and was the wrong pose being asked
## to do a jump's job.
func _drive_rig(move_x: float) -> void:
	if _rig == null:
		return
	var grounded: bool = is_on_floor()
	_rig.set_grounded(grounded)
	_rig.set_body_velocity(velocity)
	_rig.set_air_phase(velocity.y < 0.0, grounded)
	if absf(move_x) > 0.01:
		_rig.set_facing(Vector2(move_x, 0.0))
	if not grounded:
		_rig.play(CharacterRig.State.AIR)
	elif absf(move_x) > 0.01:
		_rig.play(CharacterRig.State.RUN)
	else:
		_rig.play(CharacterRig.State.IDLE)


## True while a town panel (class altar / armory / outfitter) is up.
func _screen_open() -> bool:
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		return true
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("is_open") and lo.is_open():
		return true
	for o: Node in get_tree().get_nodes_in_group("town_overlay"):
		if o is CanvasItem and (o as CanvasItem).visible:
			return true
	return false


func say(text: String, fade_seconds: float = 6.0, x_offset: float = 0.0) -> void:
	speech_bubble.say(text, fade_seconds, x_offset)
