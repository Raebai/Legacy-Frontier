extends Area2D
## A straight-flying auto-aimed projectile. Hits the first enemy, then frees.

const SPEED: float = 460.0
const LIFETIME: float = 1.4

@export var damage: int = 18
var _dir: Vector2 = Vector2.RIGHT
var _life: float = LIFETIME


func launch(direction: Vector2) -> void:
	_dir = direction.normalized()
	rotation = _dir.angle()


func _ready() -> void:
	body_entered.connect(_on_hit)
	area_entered.connect(_on_area_hit)


func _physics_process(delta: float) -> void:
	global_position += _dir * SPEED * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_area_hit(area: Area2D) -> void:
	_try_damage(area.get_parent())


func _on_hit(body: Node) -> void:
	_try_damage(body)


func _try_damage(node: Node) -> void:
	if node != null and node.is_in_group("enemy") and node.has_method("take_damage"):
		node.take_damage(damage)
		Sfx.play("spell_impact")
		Juice.hit_stop(0.045)  # weighted: lightest impact in the ladder
		Juice.shake_camera(6.0)
		_spawn_impact_burst()
		if node.has_method("apply_knockback"):
			node.apply_knockback(_dir * 260.0)
		queue_free()


func _spawn_impact_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(1.0, 0.8, 0.3, 0.9), Color(1.0, 0.55, 0.15, 0.0),
		20, 0.4, 60.0, 130.0, 1.0, 3.0
	)
