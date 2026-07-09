extends CharacterBody2D
## Slice 0 enemy: chases the hero, takes spell damage, damages on contact, dies.

@export var max_hp: int = 40
@export var move_speed: float = 95.0
@export var touch_damage: int = 12
@export var tint: Color = Color(0.9, 0.35, 0.3, 1)

var hp: int = 40
var _hero: Node2D = null
var _touch_cooldown: float = 0.0

@onready var rig: CharacterRig = $Rig


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	rig.set_tint(tint)
	var heroes: Array = get_tree().get_nodes_in_group("hero")
	if not heroes.is_empty():
		_hero = heroes[0]


func _physics_process(delta: float) -> void:
	_touch_cooldown = max(_touch_cooldown - delta, 0.0)
	if not is_instance_valid(_hero):
		rig.play(CharacterRig.State.IDLE)
		return
	var dir: Vector2 = (_hero.global_position - global_position).normalized()
	velocity = dir * move_speed
	move_and_slide()
	rig.play(CharacterRig.State.RUN)
	rig.set_facing(dir)
	if global_position.distance_to(_hero.global_position) < 22.0 and _touch_cooldown <= 0.0:
		if _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = 0.8


func take_damage(amount: int) -> void:
	hp = max(hp - amount, 0)
	_flash()
	if hp == 0:
		_die()


func _flash() -> void:
	rig.flash()


func _die() -> void:
	Sfx.play("enemy_death")
	Juice.shake_camera(8.0)
	Juice.hit_stop()
	queue_free()
