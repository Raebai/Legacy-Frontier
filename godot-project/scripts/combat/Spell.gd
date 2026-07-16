extends Area2D
## A straight-flying auto-aimed projectile. Hits the first enemy, then frees.

const SPEED: float = 460.0
## Fly until a wall/enemy stops it, or this far (well past any arena) — a bolt
## should never just STOP mid-air; the arena walls stop it first.
const MAX_TRAVEL: float = 2600.0

@export var damage: int = 18
## Per-class primary flavour (all default off = the plain Arcanist bolt):
## heal_on_hit lifesteals to `caster` (Cleric/Warlock); chain_count arcs the hit
## to nearby enemies (Stormcaller). caster is the Hero, for the lifesteal callback.
var heal_on_hit: int = 0
var caster: Node = null
var chain_count: int = 0
const CHAIN_RANGE: float = 200.0
const CHAIN_DAMAGE_FACTOR: float = 0.5
var _dir: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0
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
	var netmgr: Node = get_node_or_null("/root/Net")
	if netmgr != null and netmgr.is_active():
		collision_mask = collision_mask | 2  # co-op friendly fire: also hit heroes (layer 2)


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
	_traveled += SPEED * delta
	if _resolve_segment(prev):
		return  # hit a wall / cover / enemy along the path — no pass-through
	if _traveled >= MAX_TRAVEL:
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
	query.hit_from_inside = true  # point-blank: the ray may START inside the block
	if is_instance_valid(caster) and caster is CollisionObject2D:
		query.exclude = [(caster as CollisionObject2D).get_rid()]  # never self-stop on the caster
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
		# Lifesteal (Cleric heal-bolt / Warlock drain-bolt): heal the caster.
		if heal_on_hit > 0 and is_instance_valid(caster) and caster.has_method("heal"):
			caster.call("heal", heal_on_hit)
		# Chain (Stormcaller chain-bolt): arc the hit to nearby stragglers.
		if chain_count > 0:
			_do_chain(node)
		# One dispatcher fires the camera/time/sound cluster in sync (study §4);
		# the burst + knockback (victim body reaction) fire alongside it.
		Juice.on_hit({"sfx": "spell_impact", "hitstop": 0.045, "shake": 6.0, "dir": _dir, "kick": 5.0})
		_spawn_impact_burst()
		if node.has_method("apply_knockback"):
			node.apply_knockback(_dir * 260.0)
		queue_free()
	elif node.is_in_group("hero") and node != caster and node.has_method("take_damage"):
		# FRIENDLY FIRE (co-op): a hero-cast spell can hit OTHER heroes (never the
		# caster). Routed through Net so damage lands on the victim's authority.
		var netmgr: Node = get_node_or_null("/root/Net")
		if netmgr != null and netmgr.is_active():
			_dead = true
			netmgr.deal_damage(node, damage)
			netmgr.deal_knockback(node, _dir * 240.0)
			Juice.on_hit({"sfx": "spell_impact", "hitstop": 0.045, "shake": 6.0, "dir": _dir, "kick": 5.0})
			_spawn_impact_burst()
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


## Chain the hit to the nearest OTHER enemies (Stormcaller). Each arc deals a
## fraction of damage + the element + a spark line so the jump reads.
func _do_chain(first: Node) -> void:
	var here: Vector2 = global_position
	var already: Array = [first]
	var arc_dmg: int = int(round(float(damage) * CHAIN_DAMAGE_FACTOR))
	for _i: int in chain_count:
		var best: Node2D = null
		var best_d: float = CHAIN_RANGE
		for e: Node in get_tree().get_nodes_in_group("enemy"):
			if e in already or not e is Node2D or not is_instance_valid(e):
				continue
			var d: float = here.distance_to((e as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = e as Node2D
		if best == null:
			break
		if best.has_method("take_damage"):
			best.take_damage(arc_dmg)
		if element_id >= 0 and best.has_method("apply_status"):
			best.apply_status(element_id, false)
		var col: Color = _element_color if _has_element_color else Color(1.0, 0.95, 0.4)
		CombatVfx.spawn_burst(
			get_parent(), best.global_position, Color(col.r, col.g, col.b, 0.95),
			Color(col.r, col.g, col.b, 0.0), 8, 0.22, 50.0, 130.0, 1.0, 3.0, 0.0, 0.0, true
		)
		already.append(best)
		here = best.global_position


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
		28, 0.45, 90.0, 220.0, 1.5, 4.0, 0.0, 0.0, true
	)
