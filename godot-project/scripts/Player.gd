# Player.gd
#
# Top-down 3/4 movement for the player character. Reads the move_* input
# actions defined in project.godot — never raw keycodes — so the same code
# works on PC keyboard today and virtual joystick on mobile later (D-011).
#
# Lives on a CharacterBody2D. M1 has no walls, but move_and_slide() is the
# right pattern from day one — M2 adds tile collision and this code stays
# identical.

extends CharacterBody2D

# Movement speed in pixels per second. Tune by feel later.
const SPEED: float = 180.0


func _physics_process(_delta: float) -> void:
	# Returns a normalised Vector2 from the four movement actions.
	# Diagonal motion is automatically the same speed as cardinal motion;
	# no pythagorean correction needed.
	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	velocity = direction * SPEED
	move_and_slide()
