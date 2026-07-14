class_name RuinPlatform
extends StaticBody2D
## A weathered broken-stone platform you can stand + jump on — the "ruins" that
## fill the vertical space over the ground so the stage reads as a real place with
## aerial routes, not scattered abstract slabs. Solid (layer 1). Drawn as a fitted
## masonry slab with a sunlit bevel, cracks + chipped corners, sparse moss, and a
## couple of support struts / hanging rubble BENEATH so it looks ROOTED to the
## world rather than floating (maker: "platforms that feel intentional + connected
## to the ground, not disconnected abstract blocks").

@export var platform_size: Vector2 = Vector2(190.0, 24.0)

const STONE: Color = Color(0.41, 0.39, 0.38)
const STONE_LIT: Color = Color(0.55, 0.52, 0.47)     # sunlit top bevel
const STONE_DARK: Color = Color(0.24, 0.23, 0.25)
const EDGE: Color = Color(0.12, 0.11, 0.13, 0.8)
const CRACK: Color = Color(0.09, 0.08, 0.10, 0.7)
const MOSS: Color = Color(0.33, 0.44, 0.24, 0.85)
const STRUT: Color = Color(0.24, 0.22, 0.23)


func _ready() -> void:
	z_index = -4
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = platform_size
	cs.shape = rect
	add_child(cs)
	queue_redraw()


func _h(a: int, b: int) -> float:
	var n: int = (a * 73856093) ^ (b * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65536.0


func _draw() -> void:
	var half: Vector2 = platform_size * 0.5
	var seed_x: int = int(position.x)
	# --- Support struts + hanging rubble beneath, so it reads rooted. Two tapered
	# stone legs dropping from the underside + a few clinging chunks.
	for s in range(2):
		var sx: float = lerpf(-half.x * 0.55, half.x * 0.55, float(s))
		var drop: float = 26.0 + _h(seed_x, s * 3) * 20.0
		var leg := PackedVector2Array([
			Vector2(sx - 6.0, half.y - 2.0),
			Vector2(sx + 6.0, half.y - 2.0),
			Vector2(sx + 3.0, half.y + drop),
			Vector2(sx - 3.0, half.y + drop),
		])
		draw_colored_polygon(leg, STRUT)
	for r in range(3):
		var rx: float = lerpf(-half.x * 0.7, half.x * 0.7, _h(seed_x, r * 7 + 1))
		var rr: float = 3.0 + _h(seed_x + r, 5) * 4.0
		draw_circle(Vector2(rx, half.y + 4.0 + _h(seed_x, r * 5) * 10.0), rr, STONE_DARK, true, -1.0, true)
	# --- The slab body with a jittered (chipped) silhouette.
	var body := PackedVector2Array([
		Vector2(-half.x + _h(seed_x, 1) * 5.0, -half.y),
		Vector2(half.x - _h(seed_x, 2) * 5.0, -half.y + _h(seed_x, 8) * 3.0),
		Vector2(half.x, half.y - _h(seed_x, 3) * 4.0),
		Vector2(-half.x + _h(seed_x, 4) * 3.0, half.y),
	])
	draw_colored_polygon(body, STONE)
	# Deep underside shade.
	draw_rect(Rect2(-half.x, half.y - 6.0, platform_size.x, 6.0), STONE_DARK, true)
	# --- Sunlit top bevel (a lit band along the walkable surface) + bright rim.
	draw_rect(Rect2(-half.x, -half.y, platform_size.x, 6.0), STONE_LIT, true)
	draw_rect(Rect2(-half.x, -half.y, platform_size.x, 2.0), STONE_LIT.lightened(0.2), true)
	# --- Masonry seams (a few vertical joints) + a diagonal crack.
	var joints: int = maxi(2, int(platform_size.x / 46.0))
	for j in range(1, joints):
		var jx: float = -half.x + platform_size.x * float(j) / float(joints) + (_h(seed_x, j) - 0.5) * 6.0
		draw_line(Vector2(jx, -half.y + 5.0), Vector2(jx, half.y - 2.0), EDGE, 1.2, true)
	draw_line(Vector2(-half.x * 0.3, -half.y + 4.0), Vector2(half.x * 0.15, half.y - 3.0), CRACK, 1.6, true)
	# --- Sparse moss clinging to the lit edge.
	for m in range(3):
		if _h(seed_x, m * 11) > 0.5:
			var mx: float = lerpf(-half.x * 0.8, half.x * 0.8, _h(seed_x + m, 9))
			draw_line(Vector2(mx, -half.y), Vector2(mx + 1.0, -half.y - 4.0), MOSS, 1.6, true)
	# Crisp silhouette edge.
	var outline: PackedVector2Array = body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, EDGE, 1.4, true)
