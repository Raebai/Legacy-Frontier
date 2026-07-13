extends CharacterBody2D

const SPEED: float = 180.0

@onready var speech_bubble: Node2D = $SpeechBubble

# Set by RoomZone Area2Ds on body_entered. M14 broadcast earshot reads it.
var current_room_id: String = ""


func _physics_process(_delta: float) -> void:
	# Frozen while a conversation input bar OR the class-select panel is open.
	var selecting: bool = ClassSelect != null and ClassSelect.is_open()
	if Conversation.is_input_open() or selecting:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Returns a normalised Vector2 from the four movement actions.
	# Diagonal motion is automatically the same speed as cardinal motion;
	# no pythagorean correction needed.
	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	velocity = direction * SPEED
	move_and_slide()


func say(text: String, fade_seconds: float = 6.0, x_offset: float = 0.0) -> void:
	speech_bubble.say(text, fade_seconds, x_offset)
