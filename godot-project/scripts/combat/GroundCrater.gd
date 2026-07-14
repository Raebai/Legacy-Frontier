class_name GroundCrater
extends Node2D
## A persistent CRATER gouged into the floor where a big hit lands: a dark gouge +
## a raised broken rim + a few edge chunks (maker: "carve VISIBLE CRATERS into the
## floor where big hits land"). Accumulates as the arena wrecks, capped so a long
## fight can't flood the screen. Mirrors ScorchDecal's lifecycle + z-order; uses NO
## autoloads (draw + one raycast only), so the headless harness can load() it.

const GROUP_NAME: String = "ground_crater"
const MAX_CRATERS: int = 24        # session cap; oldest freed past this
const SNAP_MAX_DIST: float = 260.0 # downward raycast reach to find the floor

@export var radius: float = 40.0
@export var gouge_tint: Color = Color(0.05, 0.04, 0.05, 0.8)
@export var rim_tint: Color = Color(0.34, 0.28, 0.22, 0.95)

var _chunks: Array[PackedVector2Array] = []


## Spawn a crater under `parent` at `world_pos`. snap=true raycasts DOWN (mask 1)
## to seat it on the floor and SKIPS (frees itself) when nothing is below (over a
## pit) so craters never float. snap=false places exactly at world_pos.
static func spawn(parent: Node, world_pos: Vector2, crater_radius: float, snap: bool = true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var c := GroundCrater.new()
	c.radius = crater_radius
	c.z_index = -1
	parent.add_child(c)
	c.add_to_group(GROUP_NAME)  # membership NOW so the cap counts it this frame
	c.global_position = world_pos
	if snap:
		var world: World2D = c.get_world_2d()
		if world != null:
			var q := PhysicsRayQueryParameters2D.create(world_pos, world_pos + Vector2(0.0, SNAP_MAX_DIST), 1)
			var hit: Dictionary = world.direct_space_state.intersect_ray(q)
			if hit.is_empty():
				c.queue_free()  # over a pit — no floating crater
				return
			c.global_position = hit["position"]
	_enforce_cap(parent.get_tree())


## Cap against unbounded growth: past MAX_CRATERS, free the oldest (add order).
static func _enforce_cap(tree: SceneTree) -> void:
	if tree == null:
		return
	var alive: Array[Node] = []
	for cr: Node in tree.get_nodes_in_group(GROUP_NAME):
		if is_instance_valid(cr) and not cr.is_queued_for_deletion():
			alive.append(cr)
	var overflow: int = alive.size() - MAX_CRATERS
	for i: int in overflow:
		alive[i].queue_free()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_bake_chunks()
	queue_redraw()


## Pre-bake the broken edge-chunk quads once so _draw stays deterministic. Chunk
## centres sit on the (squashed) rim ellipse; the quads themselves are un-squashed.
func _bake_chunks() -> void:
	var n: int = 5
	for i: int in n:
		var a: float = TAU * float(i) / float(n) + randf_range(-0.3, 0.3)
		var c: Vector2 = Vector2(cos(a) * radius * randf_range(0.85, 1.05), sin(a) * radius * 0.5 * randf_range(0.85, 1.05))
		var s: float = radius * randf_range(0.14, 0.24)
		_chunks.append(PackedVector2Array([
			c + Vector2(-s, -s * 0.6), c + Vector2(s, -s * 0.4), c + Vector2(s * 0.7, s), c + Vector2(-s * 0.8, s * 0.7),
		]))


func _draw() -> void:
	# Gouge: concentric dark discs squashed onto the floor plane (a flat ellipse,
	# reading as a pit dug into the ground rather than a face-on disc).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, radius, Color(gouge_tint.r, gouge_tint.g, gouge_tint.b, gouge_tint.a * 0.4))
	draw_circle(Vector2.ZERO, radius * 0.62, Color(gouge_tint.r, gouge_tint.g, gouge_tint.b, gouge_tint.a * 0.7))
	draw_circle(Vector2.ZERO, radius * 0.3, gouge_tint)
	# Raised broken rim: a lit upper arc + a dark lower arc (a lip pushed up).
	draw_arc(Vector2.ZERO, radius, PI, TAU, 22, Color(rim_tint.r * 1.3, rim_tint.g * 1.3, rim_tint.b * 1.3, rim_tint.a), 2.4, true)
	draw_arc(Vector2.ZERO, radius, 0.0, PI, 22, Color(0.12, 0.1, 0.09, rim_tint.a * 0.85), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Broken rock chunks seated on the rim.
	for ch: PackedVector2Array in _chunks:
		draw_colored_polygon(ch, rim_tint)
