class_name ScorchDecal
extends Node2D
## Persistent floor damage decal: a scorch splotch or crack lines drawn once in
## _draw() and left alive for the whole session — the ACCUMULATION is the
## point (the arena visibly wrecks as the fight goes on). Sits at z_index -1:
## above the Floor (z -2 in Arena.tscn) but below characters (z 0).

const GROUP_NAME: String = "floor_decal"
const MAX_DECALS: int = 60  # session safety cap: oldest decals free past this
const CRACK_LINE_COUNT: int = 5
const CRACK_SEGMENTS: int = 3
const CRACK_WIDTH: float = 2.0
const CRACK_JAG: float = 0.18  # lateral jitter as a fraction of radius

@export var radius: float = 24.0
@export var kind: String = "scorch"  # "scorch" | "crack"
@export var tint: Color = Color(0.05, 0.03, 0.02, 0.55)

var _crack_lines: Array[PackedVector2Array] = []


## Instantiate a decal under `parent` at world `pos`. Null-safe: silently
## skips when the parent is gone (e.g. a blast resolving during teardown).
static func spawn(
	parent: Node, pos: Vector2, decal_radius: float, decal_kind: String, decal_tint: Color
) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var decal: ScorchDecal = ScorchDecal.new()
	decal.radius = decal_radius
	decal.kind = decal_kind
	decal.tint = decal_tint
	decal.z_index = -1
	parent.add_child(decal)
	decal.global_position = pos
	_enforce_cap(parent.get_tree())


## Cheap safety against unbounded growth over a long session: past MAX_DECALS
## live decals, free the oldest (group order follows add order).
static func _enforce_cap(tree: SceneTree) -> void:
	if tree == null:
		return
	var alive: Array[Node] = []
	for decal: Node in tree.get_nodes_in_group(GROUP_NAME):
		if is_instance_valid(decal) and not decal.is_queued_for_deletion():
			alive.append(decal)
	var overflow: int = alive.size() - MAX_DECALS
	for i: int in overflow:
		alive[i].queue_free()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	if kind == "crack":
		_generate_cracks()
	queue_redraw()


## Pre-bake the jagged crack geometry once so _draw() stays deterministic.
func _generate_cracks() -> void:
	_crack_lines.clear()
	for i: int in CRACK_LINE_COUNT:
		var angle: float = TAU * float(i) / float(CRACK_LINE_COUNT) + randf_range(-0.5, 0.5)
		var reach: float = radius * randf_range(0.6, 1.0)
		var dir: Vector2 = Vector2.from_angle(angle)
		var lateral: Vector2 = Vector2.from_angle(angle + PI * 0.5)
		var points: PackedVector2Array = PackedVector2Array()
		points.append(Vector2.ZERO)
		for s: int in CRACK_SEGMENTS:
			var t: float = float(s + 1) / float(CRACK_SEGMENTS)
			var jag: float = radius * CRACK_JAG * randf_range(-1.0, 1.0)
			points.append(dir * reach * t + lateral * jag)
		_crack_lines.append(points)


func _draw() -> void:
	if kind == "crack":
		_draw_crack()
	else:
		_draw_scorch()


## Soft dark radial splotch: concentric translucent discs, densest at center.
func _draw_scorch() -> void:
	draw_circle(Vector2.ZERO, radius, Color(tint.r, tint.g, tint.b, tint.a * 0.35))
	draw_circle(Vector2.ZERO, radius * 0.66, Color(tint.r, tint.g, tint.b, tint.a * 0.6))
	draw_circle(Vector2.ZERO, radius * 0.34, Color(tint.r, tint.g, tint.b, tint.a))


## Small dark impact chip at the center plus jagged radiating lines.
func _draw_crack() -> void:
	draw_circle(Vector2.ZERO, radius * 0.16, tint)
	for line: PackedVector2Array in _crack_lines:
		draw_polyline(line, tint, CRACK_WIDTH)
