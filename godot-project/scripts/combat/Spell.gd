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
		Juice.hit_stop()
		Juice.shake_camera(6.0)
		_spawn_impact_burst()
		if node.has_method("apply_knockback"):
			node.apply_knockback(_dir * 260.0)
		queue_free()


func _spawn_impact_burst() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var burst := GPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 20
	burst.lifetime = 0.4
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.spread = 180.0
	mat.initial_velocity_min = 60.0
	mat.initial_velocity_max = 130.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 1.0
	mat.scale_max = 3.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
	ramp.set_color(1, Color(1.0, 0.55, 0.15, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	burst.process_material = mat
	parent.add_child(burst)
	burst.global_position = global_position
	burst.restart()
	burst.emitting = true
	get_tree().create_timer(0.6).timeout.connect(burst.queue_free)
