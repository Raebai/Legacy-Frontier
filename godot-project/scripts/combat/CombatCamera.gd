extends Camera2D
## A Camera2D that can screenshake. Registered in group "combat_camera".

## Tight Stick Fight-style framing — the ~22px figures fill the screen.
const DEFAULT_ZOOM: Vector2 = Vector2(2.2, 2.2)
const SHAKE_DECAY: float = 12.0

var _shake_amount: float = 0.0


func _ready() -> void:
	add_to_group("combat_camera")
	zoom = DEFAULT_ZOOM


func add_shake(amount: float) -> void:
	_shake_amount = min(_shake_amount + amount, 24.0)


func _process(delta: float) -> void:
	if _shake_amount > 0.0:
		offset = Vector2(
			randf_range(-_shake_amount, _shake_amount),
			randf_range(-_shake_amount, _shake_amount)
		)
		_shake_amount = max(_shake_amount - SHAKE_DECAY * delta, 0.0)
	else:
		offset = Vector2.ZERO
