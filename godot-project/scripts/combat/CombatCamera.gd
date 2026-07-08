extends Camera2D
## A Camera2D that can screenshake. Registered in group "combat_camera".

var _shake_amount: float = 0.0
const SHAKE_DECAY: float = 12.0


func _ready() -> void:
	add_to_group("combat_camera")


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
