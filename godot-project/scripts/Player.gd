extends CharacterBody2D
## Hub player — now SIDE-ON (gravity + jump), matching the combat feel (maker:
## "the lobby should be side-on all the time like the battle place"). A/D move,
## W/Up/Space jump; stands + jumps on the town ground plane.

const SPEED: float = 200.0
const GRAVITY: float = 1400.0
const JUMP_VELOCITY: float = -520.0
const MAX_FALL: float = 1000.0

@onready var speech_bubble: Node2D = $SpeechBubble

# Set by RoomZone Area2Ds on body_entered. M14 broadcast earshot reads it.
var current_room_id: String = ""
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
	# Frozen while a conversation input bar OR the class-select panel is open —
	# gravity still applies so we rest on the ground, but no walking/jumping.
	var selecting: bool = (ClassSelect != null and ClassSelect.is_open()) \
			or (Loadout != null and Loadout.is_open())
	if Conversation.is_input_open() or selecting:
		velocity.x = 0.0
		velocity.y = 0.0 if is_on_floor() else minf(velocity.y + GRAVITY * delta, MAX_FALL)
		move_and_slide()
		if _rig != null:
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
	# Drive the stick figure: airborne pose, else run/idle facing travel.
	if _rig != null:
		if not is_on_floor():
			_rig.play(CharacterRig.State.DASH)  # a taut airborne pose
			if absf(move_x) > 0.01:
				_rig.set_facing(Vector2(move_x, 0.0))
		elif absf(move_x) > 0.01:
			_rig.play(CharacterRig.State.RUN)
			_rig.set_facing(Vector2(move_x, 0.0))
		else:
			_rig.play(CharacterRig.State.IDLE)


func say(text: String, fade_seconds: float = 6.0, x_offset: float = 0.0) -> void:
	speech_bubble.say(text, fade_seconds, x_offset)
