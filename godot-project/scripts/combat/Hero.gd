extends CharacterBody2D
## Slice 0 combat protagonist (the mage). Move now; dash + cast added next.

signal health_changed(current: int, maximum: int)

const SPEED: float = 210.0
const DASH_SPEED: float = 620.0
const DASH_TIME: float = 0.14
const DASH_COOLDOWN: float = 0.55

@export var max_hp: int = 100
var hp: int = 100
var facing: Vector2 = Vector2.RIGHT
var is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT


func _ready() -> void:
	add_to_group("hero")
	hp = max_hp
	health_changed.emit(hp, max_hp)


func _physics_process(delta: float) -> void:
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)

	if is_dashing:
		_dash_timer -= delta
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
		if _dash_timer <= 0.0:
			is_dashing = false
		return

	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	if direction != Vector2.ZERO:
		facing = direction

	if Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		_start_dash()
		return

	velocity = direction * SPEED
	move_and_slide()


func _start_dash() -> void:
	is_dashing = true
	_dash_timer = DASH_TIME
	_dash_cooldown_timer = DASH_COOLDOWN
	_dash_dir = facing


func take_damage(amount: int) -> void:
	hp = max(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		_die()


func _die() -> void:
	# Slice 0: just reset to full so the feel loop never stops.
	hp = max_hp
	health_changed.emit(hp, max_hp)
