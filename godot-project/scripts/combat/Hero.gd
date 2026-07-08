extends CharacterBody2D
## Slice 0 combat protagonist (the mage). Move now; dash + cast added next.

signal health_changed(current: int, maximum: int)

const SPEED: float = 210.0

@export var max_hp: int = 100
var hp: int = 100
var facing: Vector2 = Vector2.RIGHT


func _ready() -> void:
	add_to_group("hero")
	hp = max_hp
	health_changed.emit(hp, max_hp)


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	if direction != Vector2.ZERO:
		facing = direction
	velocity = direction * SPEED
	move_and_slide()


func take_damage(amount: int) -> void:
	hp = max(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		_die()


func _die() -> void:
	# Slice 0: just reset to full so the feel loop never stops.
	hp = max_hp
	health_changed.emit(hp, max_hp)
