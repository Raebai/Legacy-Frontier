class_name BossAdornment
extends Node2D
## Molten core + ember eyes + lava cracks drawn ON TOP of the boss rig (the
## bespoke flourish that turns a giant stick figure into a stone-and-ember
## colossus). Offsets derive from the rig height; set_intensity(0..1) cranks core
## brightness, eye heat, crack glow, and pulse speed together so phases escalate
## it. HDR colours (>1) rely on the arena bloom (Atmosphere.add_glow) to radiate.

var _height: float = 95.0
var _intensity: float = 0.35
var _t: float = 0.0


func configure(rig_height: float) -> void:
	_height = rig_height
	z_index = 40  # above the rig + aura


func set_intensity(v: float) -> void:
	_intensity = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta * (2.0 + 4.0 * _intensity)   # a faster molten pulse when enraged
	queue_redraw()


func _draw() -> void:
	var pulse: float = 0.85 + 0.15 * sin(_t)
	var glow: float = 0.4 + 0.6 * _intensity
	# Molten core at chest height — an EMBER glow (kept orange/red so it never
	# blooms the whole stone body to white; only the tiny centre goes hot).
	var core_pos := Vector2(0.0, -_height * 0.18)
	var core_r: float = _height * (0.055 + 0.025 * _intensity) * pulse
	draw_circle(core_pos, core_r * 2.2, Color(0.9, 0.28, 0.06, 0.13 * glow))
	draw_circle(core_pos, core_r * 1.4, Color(1.3, 0.45, 0.12, 0.28 * glow))
	draw_circle(core_pos, core_r, Color(1.7, 0.65, 0.18, 0.5 * glow))
	draw_circle(core_pos, core_r * 0.45, Color(2.0, 1.0, 0.35, 0.7 * glow))
	# Two ember eyes on the head — brighten with phase.
	var eye_y: float = -_height * 0.34
	var eye_dx: float = _height * 0.055
	var eye_r: float = _height * 0.02 * (0.8 + 0.6 * _intensity)
	var eye_col := Color(2.0, 0.5 + 0.5 * _intensity, 0.15, 0.7 + 0.3 * _intensity)
	draw_circle(Vector2(-eye_dx, eye_y), eye_r, eye_col)
	draw_circle(Vector2(eye_dx, eye_y), eye_r, eye_col)
	# Lava cracks down the torso — dark in P1, glowing in P3.
	var crack_col := Color(1.5, 0.5, 0.15, (0.18 + 0.7 * _intensity) * pulse)
	var cw: float = maxf(1.5, _height * 0.028)
	for seam: PackedVector2Array in _seams():
		draw_polyline(seam, crack_col, cw)


func _seams() -> Array:
	var h: float = _height
	return [
		PackedVector2Array([Vector2(-h * 0.04, -h * 0.12), Vector2(-h * 0.09, -h * 0.02), Vector2(-h * 0.06, h * 0.08)]),
		PackedVector2Array([Vector2(h * 0.05, -h * 0.13), Vector2(h * 0.02, -h * 0.03), Vector2(h * 0.08, h * 0.05)]),
		PackedVector2Array([Vector2(0.0, -h * 0.10), Vector2(h * 0.02, 0.0), Vector2(-h * 0.02, h * 0.12)]),
	]
