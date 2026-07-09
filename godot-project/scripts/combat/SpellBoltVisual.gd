class_name SpellBoltVisual
extends Node2D
## Procedural magic-bolt visual: white-hot core + warm glow + tapering trail.
## Local +X is the travel axis — the parent Spell sets `rotation` from its
## direction in launch(), so this node just draws along +X.
## Tuning knobs: CORE_* for bolt size, TRAIL_* for tail length/density,
## FLICKER_SPEED for the energy shimmer.

const CORE_COLOR: Color = Color(1.0, 0.97, 0.8, 1.0)
const TIP_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
const GLOW_COLOR: Color = Color(1.0, 0.7, 0.25, 0.35)
const TRAIL_COLOR: Color = Color(1.0, 0.58, 0.18, 0.55)
const CORE_HALF_LEN: float = 5.0
const CORE_HALF_WIDTH: float = 2.4
const GLOW_SCALE: float = 2.6
const TRAIL_SEGMENTS: int = 4
const TRAIL_SPACING: float = 5.0
const FLICKER_SPEED: float = 40.0

var _phase: float = 0.0


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	var flicker: float = 0.9 + 0.1 * sin(_phase * FLICKER_SPEED)
	# Tapering trail: segments march backwards (-X), fading and thinning.
	for i: int in range(TRAIL_SEGMENTS):
		var f: float = 1.0 - float(i + 1) / float(TRAIL_SEGMENTS + 1)
		var x0: float = -CORE_HALF_LEN - TRAIL_SPACING * float(i)
		var x1: float = x0 - TRAIL_SPACING * 0.9
		var seg_col: Color = Color(
			TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, TRAIL_COLOR.a * f * f
		)
		_draw_capsule(Vector2(x1, 0.0), Vector2(x0, 0.0), CORE_HALF_WIDTH * f, seg_col)
	# Outer warm glow hugging the bolt.
	var glow_col: Color = Color(
		GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, GLOW_COLOR.a * flicker
	)
	_draw_capsule(
		Vector2(-CORE_HALF_LEN - 2.0, 0.0),
		Vector2(CORE_HALF_LEN + 1.0, 0.0),
		CORE_HALF_WIDTH * GLOW_SCALE,
		glow_col
	)
	# Bright hot core (elongated lozenge along the travel axis).
	_draw_capsule(
		Vector2(-CORE_HALF_LEN, 0.0), Vector2(CORE_HALF_LEN, 0.0),
		CORE_HALF_WIDTH, CORE_COLOR
	)
	# White-hot tip.
	var tip_col: Color = Color(TIP_COLOR.r, TIP_COLOR.g, TIP_COLOR.b, TIP_COLOR.a * flicker)
	draw_circle(Vector2(CORE_HALF_LEN, 0.0), CORE_HALF_WIDTH * 0.9, tip_col)


## Elongated capsule/lozenge: a thick line with round end-caps.
func _draw_capsule(from_point: Vector2, to_point: Vector2, half_width: float, col: Color) -> void:
	draw_line(from_point, to_point, col, half_width * 2.0)
	draw_circle(from_point, half_width, col)
	draw_circle(to_point, half_width, col)
