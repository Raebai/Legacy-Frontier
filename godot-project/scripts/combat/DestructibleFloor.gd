class_name DestructibleFloor
extends Node2D
## A run of INDEPENDENT destructible floor segments — each its own StaticBody2D — so
## a hard hit opens a REAL passable hole (unlike DestructibleTerrain's single collider
## which only chips visually). Each segment: collision_layer 5 (value 1 blocks
## fighters + value 4 makes it spell-hittable), group "destructible" for the
## damage-routing contract (take_damage / damage_at), high hp so the ground survives
## chip damage and only opens under real blows. Segments overlap horizontally + grow
## down so a running CharacterBody2D never snags on the seam between them.

@export var run_start: Vector2 = Vector2(40.0, 780.0)  # left end (x, SURFACE y)
@export var run_end_x: float = 1120.0
@export var thickness: float = 62.0
@export var segment_w: float = 64.0
@export var segment_hp: int = 90

const OVERLAP: float = 2.0     # horizontal collider overlap (kills the T-junction seam)
const GROW_DOWN: float = 8.0   # extend the collider down (no flush seam below)
const BODY: Color = Color(0.21, 0.20, 0.24)
const RIM: Color = Color(0.5, 0.42, 0.34)


func _ready() -> void:
	var n: int = int(ceil((run_end_x - run_start.x) / segment_w))
	for i in n:
		var cx: float = run_start.x + (float(i) + 0.5) * segment_w
		var seg := FloorSegment.new()
		seg.seg_size = Vector2(segment_w + OVERLAP * 2.0, thickness + GROW_DOWN)
		seg.max_hp = segment_hp
		seg.body_color = BODY
		seg.rim_color = RIM
		add_child(seg)
		# Center so the segment TOP sits exactly on the surface y (grown down below).
		seg.position = Vector2(cx, run_start.y + (thickness + GROW_DOWN) * 0.5)


## One destructible floor tile. Its whole collider vanishes on death -> a real hole.
class FloorSegment:
	extends StaticBody2D
	var seg_size: Vector2 = Vector2(66.0, 70.0)
	var max_hp: int = 90
	var hp: int = 90
	var body_color: Color = Color(0.21, 0.20, 0.24)
	var rim_color: Color = Color(0.5, 0.42, 0.34)
	var _dead: bool = false

	func _ready() -> void:
		hp = max_hp
		collision_layer = 5  # value 1 (blocks fighters) + value 4 (spell-hittable)
		collision_mask = 0
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = seg_size
		cs.shape = rect
		add_child(cs)
		add_to_group("destructible")
		z_index = -3
		queue_redraw()

	## The damage-routing contract every source calls (melee/AoE/slam iterate the
	## "destructible" group; DestructibleTerrain/BreakablePlatform expose the same).
	func take_damage(amount: int) -> void:
		_apply(amount, Vector2.UP)

	func damage_at(amount: int, _world_pos: Vector2, dir: Vector2) -> void:
		_apply(amount, dir if dir != Vector2.ZERO else Vector2.UP)

	func _apply(amount: int, dir: Vector2) -> void:
		if _dead:
			return
		hp -= amount
		if hp <= 0:
			_break(dir)
		else:
			queue_redraw()  # progressive cracks

	func _break(dir: Vector2) -> void:
		_dead = true
		remove_from_group("destructible")  # NOW, so a same-frame AoE can't re-hit
		for c: Node in get_children():
			if c is CollisionShape2D:
				(c as CollisionShape2D).set_deferred("disabled", true)  # the hole opens
		# Rubble parented to the arena (grandparent) so it outlives this freed segment.
		var host: Node = get_parent()
		if host != null and host.get_parent() != null:
			host = host.get_parent()
		DebrisChunk.spawn_burst(host, global_position, body_color, 8, dir, 260.0)
		Juice.shake_camera(4.0)
		var sfx: Node = get_node_or_null("/root/Sfx")
		if sfx != null and sfx.has_method("play"):
			sfx.call("play", "enemy_death", -3.0, 0.12)
		queue_free()

	func _draw() -> void:
		if _dead:
			return
		var r := Rect2(-seg_size * 0.5, seg_size)
		draw_rect(r, body_color, true)
		# Chunky masonry: a couple of inset shade bands so it reads as terrain.
		draw_rect(Rect2(-seg_size.x * 0.5, -seg_size.y * 0.5, seg_size.x, 4.0), rim_color, true)
		draw_rect(r, body_color.darkened(0.4), false, 1.0)
		# Progressive crack as it takes damage.
		if hp < max_hp:
			var frac: float = 1.0 - float(hp) / float(max_hp)
			draw_line(Vector2(-seg_size.x * 0.28, -seg_size.y * 0.5),
				Vector2(seg_size.x * (0.3 * frac - 0.1), seg_size.y * 0.35),
				Color(0.04, 0.03, 0.05, 0.7 * frac), 1.6)
