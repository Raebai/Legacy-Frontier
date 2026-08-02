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

## PALETTE — RULE 1 OF THE STAGE LEGEND (see StageLayers). The lit cap is the whole
## point of this platform: it is the one thing that tells a player mid-jump that
## there is something here to land on. Everything below it is deliberately quiet.
##
## The previous pass had a 0.55-value "sunlit bevel" over a 0.41 body — a six-percent
## step, invisible against the tower's near-black wash at the framing zoom. The cap
## is now shared with the ground crust and the breakable ledge, so every standable
## surface in the game wears the same light.
const STONE: Color = Color(0.33, 0.31, 0.32)
const STONE_LIT: Color = StageLayers.CAP_LIT       # the lit top line
const STONE_CORE: Color = StageLayers.CAP_CORE     # the cap's shaded half
const STONE_DARK: Color = Color(0.18, 0.17, 0.19)
const EDGE: Color = StageLayers.EDGE_DARK
const CRACK: Color = Color(0.09, 0.08, 0.10, 0.7)
const MOSS: Color = Color(0.33, 0.44, 0.24, 0.85)
const STRUT: Color = Color(0.16, 0.15, 0.16)


func _ready() -> void:
	StageLayers.apply(self, StageLayers.PLATFORM)
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
	var cap: float = StageLayers.cap_height(platform_size.y)
	# --- Support struts + hanging rubble beneath, so it reads rooted. Two tapered
	# stone legs dropping from the underside + a few clinging chunks. DARK and thin:
	# they are there to root the ledge, and anything below the cap that catches the
	# eye is competing with the cap for the one glance the player has mid-jump.
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
	# Deep underside shade — the dark half of the value step that makes the ledge
	# read as a lit horizontal SURFACE rather than as a floating rectangle.
	draw_rect(Rect2(-half.x, half.y - cap * 0.7, platform_size.x, cap * 0.7),
		StageLayers.UNDERSIDE, true)
	# --- RULE 1: the lit cap along the walkable surface. Two bands (shaded, then
	# lit) so the top edge has thickness at any zoom.
	draw_rect(Rect2(-half.x, -half.y, platform_size.x, cap), STONE_CORE, true)
	draw_rect(Rect2(-half.x, -half.y, platform_size.x, maxf(cap * 0.45, 1.5)), STONE_LIT, true)
	# --- Masonry seams (a few vertical joints) + a diagonal crack. BELOW the cap
	# only: a seam cutting the lit line would break the one unbroken horizontal.
	var joints: int = maxi(2, int(platform_size.x / 46.0))
	for j in range(1, joints):
		var jx: float = -half.x + platform_size.x * float(j) / float(joints) + (_h(seed_x, j) - 0.5) * 6.0
		draw_line(Vector2(jx, -half.y + cap + 1.0), Vector2(jx, half.y - 2.0), EDGE, 1.2, true)
	draw_line(Vector2(-half.x * 0.3, -half.y + cap + 1.0), Vector2(half.x * 0.15, half.y - 3.0), CRACK, 1.6, true)
	# --- Sparse moss clinging to the lit edge. Two tufts, not three, and short: it
	# is flavour on the cap, and the cap has a job.
	for m in range(2):
		if _h(seed_x, m * 11) > 0.55:
			var mx: float = lerpf(-half.x * 0.8, half.x * 0.8, _h(seed_x + m, 9))
			draw_line(Vector2(mx, -half.y), Vector2(mx + 1.0, -half.y - 3.5), MOSS, 1.6, true)
	# Crisp silhouette edge.
	var outline: PackedVector2Array = body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, EDGE, 1.4, true)
