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
## Element index (Elements.Element) so a hit applies the matching ailment.
## -1 = no element (never applies a status).
var element_id: int = -1
## Set the instant we consume ourselves, so the segment raycast and the Area2D
## callbacks can't both resolve the same bolt (double-damage / freed-node errors).
var _dead: bool = false


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
	add_to_group("player_spell")  # projectile-vs-projectile clash (EnemyProjectile)
	body_entered.connect(_on_hit)
	area_entered.connect(_on_area_hit)
	collision_mask = collision_mask | 1  # also stop on platforms/walls (layer 1)


## Consumed by a projectile clash (a stronger enemy bolt): burst + free.
func fizzle() -> void:
	if _dead:
		return
	_dead = true
	_spawn_impact_burst()
	queue_free()


func _physics_process(delta: float) -> void:
	var prev: Vector2 = global_position
	global_position += _dir * SPEED * delta
	_life -= delta
	if _resolve_segment(prev):
		return  # hit a wall / cover / enemy along the path — no pass-through
	if _life <= 0.0:
		queue_free()


## Deterministic anti-pass-through: raycast the segment we just travelled against
## our own collision_mask (walls L1, enemies + destructible cover L3) and route
## whatever we hit through _try_damage — the same enemy / destructible / wall
## handling as the Area2D callbacks. A ray can't tunnel past a fast frame, and it
## catches solids reliably even when Area2D monitoring misses a dynamically-added
## StaticBody collider (the bug where bolts phased through cover). Headless helper
## tests have no physics world -> no-op, so they keep driving _try_damage directly.
func _resolve_segment(prev: Vector2) -> bool:
	if _dead:
		return true
	var world: World2D = get_world_2d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(prev, global_position, collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	global_position = hit["position"]
	_try_damage(hit["collider"])
	return _dead  # true if the hit consumed us; a no-op hit lets the bolt fly on


func _on_area_hit(area: Area2D) -> void:
	_try_damage(area.get_parent())


func _on_hit(body: Node) -> void:
	_try_damage(body)


func _try_damage(node: Node) -> void:
	if _dead or node == null:
		return
	if node.is_in_group("enemy") and node.has_method("take_damage"):
		_dead = true
		node.take_damage(damage)
		if element_id >= 0 and node.has_method("apply_status"):
			node.apply_status(element_id)
		Sfx.play("spell_impact")
		Juice.hit_stop(0.045)  # weighted: lightest impact in the ladder
		Juice.shake_camera(6.0)
		_spawn_impact_burst()
		if node.has_method("apply_knockback"):
			node.apply_knockback(_dir * 260.0)
		queue_free()
	elif node.is_in_group("destructible") and node.has_method("take_damage"):
		# Props take spell damage too. Prefer damage_at so parts break off exactly
		# where the bolt lands, along its travel direction (falls back to take_damage).
		_dead = true
		if node.has_method("damage_at"):
			node.damage_at(damage, global_position, _dir)
		else:
			node.take_damage(damage)
		Sfx.play("spell_impact")
		Juice.hit_stop(0.045)
		Juice.shake_camera(6.0)
		_spawn_impact_burst()
		DebrisChunk.spawn_burst(get_parent(), global_position, Color(0.4, 0.4, 0.45), 4, _dir, 200.0)
		queue_free()
	elif node is StaticBody2D:
		# A platform/wall stops the bolt — small explosion + stone chips fly off
		# the surface in the bolt's travel direction (the "spells hit the floor").
		_dead = true
		Sfx.play("spell_impact")
		Juice.hit_stop(0.03)
		Juice.shake_camera(3.0)
		_spawn_impact_burst()
		DebrisChunk.spawn_burst(get_parent(), global_position, Color(0.5, 0.5, 0.55), 5, _dir, 210.0)
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
		28, 0.45, 90.0, 220.0, 1.5, 4.0
	)
