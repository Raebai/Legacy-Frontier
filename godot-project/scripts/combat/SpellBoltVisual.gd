class_name SpellBoltVisual
extends Node2D
## Procedural magic-bolt visual: white-hot core + warm glow + tapering trail.
## Local +X is the travel axis — the parent Spell sets `rotation` from its
## direction in launch(), so this node just draws along +X.
## Tuning knobs: CORE_* for bolt size, TRAIL_* for tail length/density.

const CORE_COLOR: Color = Color(1.5, 1.45, 1.2, 1.0)  # HDR >1.0 so the core blooms
const TIP_COLOR: Color = Color(1.8, 1.8, 1.8, 0.95)  # HDR white-hot tip
const GLOW_COLOR: Color = Color(1.0, 0.7, 0.25, 0.35)
const TRAIL_COLOR: Color = Color(1.0, 0.58, 0.18, 0.55)
const CORE_HALF_LEN: float = 5.0
const CORE_HALF_WIDTH: float = 2.4
const GLOW_SCALE: float = 2.6
const TRAIL_SEGMENTS: int = 6
const TRAIL_SPACING: float = 4.2

## Live palette — starts at the warm defaults; set_tint() steers glow/trail
## fully toward the element colour and only nudges the hot core, so the bolt
## keeps its white-hot heart while reading unmistakably as its element.
var _core_color: Color = CORE_COLOR
var _glow_color: Color = GLOW_COLOR
var _trail_color: Color = TRAIL_COLOR


## Recolour the bolt toward an element colour (alphas preserved). Called by
## the parent Spell's set_element_color(); never called = default warm look.
func set_tint(c: Color) -> void:
	_glow_color = Color(c.r, c.g, c.b, GLOW_COLOR.a)
	_trail_color = Color(c.r, c.g, c.b, TRAIL_COLOR.a)
	# HDR core: lift the element colour toward white then push >1.0 so the bolt's
	# heart BLOOMS in its own hue (shadow=violet, earth=amber, lightning=yellow)
	# instead of washing to generic white — keeps element identity through bloom.
	var lifted: Color = Color(c.r, c.g, c.b).lerp(Color(1, 1, 1), 0.4)
	var peak: float = maxf(lifted.r, maxf(lifted.g, lifted.b))
	var k: float = 1.55 / maxf(peak, 0.001)
	_core_color = Color(lifted.r * k, lifted.g * k, lifted.b * k, CORE_COLOR.a)
	queue_redraw()


func _draw() -> void:
	# The bolt draws in its own LOCAL frame (the parent moves it), so it only
	# needs to redraw when the tint changes — no per-frame queue_redraw for a
	# near-invisible flicker (that was N redraws/frame in bullet-heavy fights).
	# Trail: segments march backwards (-X), fading and thinning into a taper.
	for i: int in range(TRAIL_SEGMENTS):
		var f: float = 1.0 - float(i + 1) / float(TRAIL_SEGMENTS + 1)
		var x0: float = -CORE_HALF_LEN - TRAIL_SPACING * float(i)
		var x1: float = x0 - TRAIL_SPACING * 0.9
		var seg_col: Color = Color(
			_trail_color.r, _trail_color.g, _trail_color.b, _trail_color.a * f * f
		)
		_draw_capsule(Vector2(x1, 0.0), Vector2(x0, 0.0), CORE_HALF_WIDTH * f, seg_col)
	# Outer warm glow hugging the bolt.
	var glow_col: Color = _glow_color
	_draw_capsule(
		Vector2(-CORE_HALF_LEN - 2.0, 0.0),
		Vector2(CORE_HALF_LEN + 1.0, 0.0),
		CORE_HALF_WIDTH * GLOW_SCALE,
		glow_col
	)
	# Bright hot core (elongated lozenge along the travel axis).
	_draw_capsule(
		Vector2(-CORE_HALF_LEN, 0.0), Vector2(CORE_HALF_LEN, 0.0),
		CORE_HALF_WIDTH, _core_color
	)
	# White-hot tip.
	draw_circle(Vector2(CORE_HALF_LEN, 0.0), CORE_HALF_WIDTH * 0.9, TIP_COLOR, true, -1.0, true)


## Elongated capsule/lozenge: a thick line with round end-caps.
func _draw_capsule(from_point: Vector2, to_point: Vector2, half_width: float, col: Color) -> void:
	draw_line(from_point, to_point, col, half_width * 2.0, true)
	draw_circle(from_point, half_width, col, true, -1.0, true)
	draw_circle(to_point, half_width, col, true, -1.0, true)
