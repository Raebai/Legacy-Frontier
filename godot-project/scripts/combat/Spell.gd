extends Area2D
## A straight-flying auto-aimed projectile. Hits the first enemy, then frees.

const SPEED: float = 460.0
const LIFETIME: float = 1.4

@export var damage: int = 18
var _dir: Vector2 = Vector2.RIGHT
var _life: float = LIFETIME
## Element tint (see Elements.gd). While unset, every visual keeps the
## original warm fire-bolt default — set_element_color() flips the flag.
var _element_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _has_element_color: bool = false


func launch(direction: Vector2) -> void:
	_dir = direction.normalized()
	rotation = _dir.angle()


## Recolour the bolt toward an element: forwards to the drawn bolt visual
## and retints the particle trail. Impact burst picks it up via the flag.
func set_element_color(c: Color) -> void:
	_element_color = c
	_has_element_color = true
	var visual: SpellBoltVisual = get_node_or_null("BoltVisual") as SpellBoltVisual
	if visual != null:
		visual.set_tint(c)
	var trail: GPUParticles2D = get_node_or_null("Trail") as GPUParticles2D
	if trail != null and trail.process_material is ParticleProcessMaterial:
		# Duplicate the material so the tint is per-instance (the .tscn
		# sub-resource is shared across every live spell otherwise).
		var mat: ParticleProcessMaterial = (
			trail.process_material.duplicate() as ParticleProcessMaterial
		)
		var grad: Gradient = Gradient.new()
		grad.colors = PackedColorArray([
			Color(c.r, c.g, c.b, 0.85), Color(c.r, c.g, c.b, 0.0)
		])
		var ramp: GradientTexture1D = GradientTexture1D.new()
		ramp.gradient = grad
		mat.color_ramp = ramp
		trail.process_material = mat


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
	if node == null:
		return
	if node.is_in_group("enemy") and node.has_method("take_damage"):
		node.take_damage(damage)
		Sfx.play("spell_impact")
		Juice.hit_stop(0.045)  # weighted: lightest impact in the ladder
		Juice.shake_camera(6.0)
		_spawn_impact_burst()
		if node.has_method("apply_knockback"):
			node.apply_knockback(_dir * 260.0)
		queue_free()
	elif node.is_in_group("destructible") and node.has_method("take_damage"):
		# Props take spell damage too (no knockback — crates don't slide).
		node.take_damage(damage)
		Sfx.play("spell_impact")
		Juice.hit_stop(0.045)
		Juice.shake_camera(6.0)
		_spawn_impact_burst()
		queue_free()


func _spawn_impact_burst() -> void:
	# Warm fire-bolt default; element-tinted when set_element_color() ran.
	var start: Color = Color(1.0, 0.8, 0.3, 0.9)
	var end: Color = Color(1.0, 0.55, 0.15, 0.0)
	if _has_element_color:
		start = Color(_element_color.r, _element_color.g, _element_color.b, 0.9)
		end = Color(
			_element_color.r * 0.5, _element_color.g * 0.5, _element_color.b * 0.5, 0.0
		)
	CombatVfx.spawn_burst(
		get_parent(), global_position, start, end,
		20, 0.4, 60.0, 130.0, 1.0, 3.0
	)
