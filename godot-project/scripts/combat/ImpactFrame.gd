class_name ImpactFrame
extends CanvasLayer
## Anime-style IMPACT FRAME: a brief full-screen burst of converging speed lines
## + a high-contrast flash, for the "cool moment" beats (a big deflect, a heavy
## punch, a finisher). Self-frees after DURATION and runs while time is frozen
## (PROCESS_MODE_ALWAYS). Spawned by Juice.impact_frame().

const DURATION: float = 0.22

var _t: float = 0.0
var _strength: float = 1.0
var _rect: Control = null
## World-space hit position the burst converges on. Vector2.INF = no position
## supplied -> legacy behaviour (viewport centre). Passing the real hit point
## makes the flash + speed lines happen AT the impact instead of centre-screen.
var _world_pos: Vector2 = Vector2.INF


func _init() -> void:
	layer = 90  # above the world + HUD, below nothing important
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_rect = Control.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_rect.draw.connect(_draw_frame)


func flash(strength: float = 1.0, world_pos: Vector2 = Vector2.INF) -> void:
	_strength = clampf(strength, 0.3, 1.6)
	_world_pos = world_pos


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	if _rect != null:
		_rect.queue_redraw()


func _draw_frame() -> void:
	var u: float = clampf(_t / DURATION, 0.0, 1.0)
	var vp: Vector2 = _rect.size
	var c: Vector2 = _convergence_point(vp)
	var fade: float = 1.0 - u
	# White flash that snaps in then falls off fast.
	if u < 0.35:
		var flash_a: float = (1.0 - u / 0.35) * _strength
		_rect.draw_rect(Rect2(Vector2.ZERO, vp), Color(1.4, 1.4, 1.5, 0.45 * flash_a))
	# Radial speed lines rushing inward from the edges toward the center.
	var n: int = 44
	var col: Color = Color(0.04, 0.04, 0.07, 0.8 * fade * _strength)
	var diag: float = vp.length()
	var inner: float = diag * (0.16 + 0.18 * u)
	for i in n:
		var a: float = TAU * float(i) / float(n) + sin(float(i) * 12.3) * 0.06
		var d: Vector2 = Vector2.from_angle(a)
		var w: float = (2.0 + 6.0 * absf(sin(float(i) * 7.7))) * _strength
		_rect.draw_line(c + d * inner, c + d * diag * 0.8, col, w)


## Screen-space point the flash + speed lines converge on: the world hit
## position projected through the active camera's canvas transform, clamped
## a margin inside the screen so near-edge / off-screen hits still read.
## No world position -> viewport centre (backward-compatible default).
func _convergence_point(vp: Vector2) -> Vector2:
	if not _world_pos.is_finite():
		return vp * 0.5
	var screen: Vector2 = _rect.get_viewport().get_canvas_transform() * _world_pos
	var margin: Vector2 = vp * 0.12
	return screen.clamp(margin, vp - margin)
