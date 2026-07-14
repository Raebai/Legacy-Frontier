class_name MountainMass
extends Node2D
## Draw-only MOUNTAIN silhouette behind the stepped permanent tiers (the collision
## is the MOUNTAIN_TIERS StaticBody2Ds in VersusArena). A jagged triangular rock
## mass with stacked shades + a snow cap, so the right third of the stage reads as
## a climbable mountain. z_index -18 (in front of the Atmosphere spires at ~-22,
## behind the platforms at -5). Deterministic jitter (no RNG) so it stays stable.

@export var foot_left: Vector2 = Vector2(1120.0, 780.0)
@export var foot_right: Vector2 = Vector2(2000.0, 900.0)
@export var peak: Vector2 = Vector2(1800.0, 205.0)

const BODY_DARK: Color = Color(0.12, 0.14, 0.22)
const BODY_LIT: Color = Color(0.19, 0.21, 0.31)
const SNOW: Color = Color(0.82, 0.87, 0.94, 0.92)


func _ready() -> void:
	z_index = -18
	queue_redraw()


## A jagged ridge of `segs` points from a to b, jittered perpendicular (deterministic).
func _ridge(a: Vector2, b: Vector2, segs: int, jag: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var perp: Vector2 = (b - a).orthogonal().normalized()
	for i in range(1, segs):
		var t: float = float(i) / float(segs)
		var base: Vector2 = a.lerp(b, t)
		var j: float = (sin(t * 13.0 + a.x * 0.01) * 0.6 + sin(t * 5.0 + 1.7) * 0.4) * jag * (0.5 + 0.5 * (1.0 - t))
		out.append(base + perp * j)
	return out


func _draw() -> void:
	# Full silhouette: up the left face to the peak, down the right face.
	var pts := PackedVector2Array([foot_left])
	for p: Vector2 in _ridge(foot_left, peak, 7, 30.0):
		pts.append(p)
	pts.append(peak)
	for p2: Vector2 in _ridge(peak, foot_right, 7, 34.0):
		pts.append(p2)
	pts.append(foot_right)
	draw_colored_polygon(pts, BODY_DARK)
	# Lit upper face (a lighter triangle toward the peak).
	var lit_l: Vector2 = foot_left.lerp(peak, 0.5)
	var lit_r: Vector2 = foot_right.lerp(peak, 0.5)
	draw_colored_polygon(PackedVector2Array([lit_l, peak, lit_r]), BODY_LIT)
	# Snow cap.
	var snow_l: Vector2 = foot_left.lerp(peak, 0.8)
	var snow_r: Vector2 = foot_right.lerp(peak, 0.8)
	draw_colored_polygon(PackedVector2Array([snow_l, peak, snow_r]), SNOW)
