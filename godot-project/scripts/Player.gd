extends CharacterBody2D

const SPEED: float = 180.0

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
	var gs: Node = get_node_or_null("/root/GameState")
	var idx: int = int(gs.get("selected_class")) if gs != null else 0
	_rig.set_tint(ClassInfo.color_for(idx))


## Retint the stick figure to a class colour (called by the Class-Select panel).
func set_class_tint(c: Color) -> void:
	if _rig != null:
		_rig.set_tint(c)


func _physics_process(_delta: float) -> void:
	# Frozen while a conversation input bar OR the class-select panel is open.
	var selecting: bool = ClassSelect != null and ClassSelect.is_open()
	if Conversation.is_input_open() or selecting:
		velocity = Vector2.ZERO
		move_and_slide()
		if _rig != null:
			_rig.play(CharacterRig.State.IDLE)
		return
	# Returns a normalised Vector2 from the four movement actions.
	# Diagonal motion is automatically the same speed as cardinal motion;
	# no pythagorean correction needed.
	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	velocity = direction * SPEED
	move_and_slide()
	# Drive the stick figure: run while moving, face the horizontal travel.
	if _rig != null:
		if direction.length() > 0.1:
			_rig.play(CharacterRig.State.RUN)
			if absf(direction.x) > 0.01:
				_rig.set_facing(direction)
		else:
			_rig.play(CharacterRig.State.IDLE)


func say(text: String, fade_seconds: float = 6.0, x_offset: float = 0.0) -> void:
	speech_bubble.say(text, fade_seconds, x_offset)
