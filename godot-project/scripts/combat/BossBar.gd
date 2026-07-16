class_name BossBar
extends Control
## Top-of-screen boss health HUD: a wide segmented bar + name, phase-colored fill,
## with dark notches at the 66% / 33% phase gates so the player SEES them coming.
## Poll-don't-push (like CharacterBars): reads the boss's hp/max_hp each frame.
## Built in code, lives on its own CanvasLayer (see Boss._build_bar).

const NAME_TEXT: String = "THE ASHSPIRE GUARDIAN"
const PHASE_COLORS: Array[Color] = [
	Color(0.95, 0.55, 0.2),   # P1
	Color(0.95, 0.35, 0.15),  # P2
	Color(0.9, 0.2, 0.1),     # P3
]
const BAR_H: float = 15.0
const WIDTH_FRAC: float = 0.62

var _boss: Node = null
var _ratio: float = 1.0
var _shown: float = 1.0   # eased display ratio (a smooth drain)
var _name_label: Label = null


func setup(boss: Node) -> void:
	_boss = boss
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_top = 40.0
	custom_minimum_size = Vector2(0.0, 60.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.text = NAME_TEXT
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color(0.98, 0.9, 0.78))
	_name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.05, 0.95))
	_name_label.add_theme_constant_override("outline_size", 5)
	add_child(_name_label)


func _process(delta: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		queue_redraw()
		return
	var mx: float = float(_boss.get("max_hp"))
	var hp: float = float(_boss.get("hp"))
	if mx > 0.0:
		_ratio = clampf(hp / mx, 0.0, 1.0)
	_shown = move_toward(_shown, _ratio, delta * 0.6)   # smooth drain
	queue_redraw()


func _draw() -> void:
	var full_w: float = size.x
	var bar_w: float = full_w * WIDTH_FRAC
	var x0: float = (full_w - bar_w) * 0.5
	var y0: float = 24.0
	# Outline + dark track.
	draw_rect(Rect2(x0 - 2.0, y0 - 2.0, bar_w + 4.0, BAR_H + 4.0), Color(0.0, 0.0, 0.0, 0.7))
	draw_rect(Rect2(x0, y0, bar_w, BAR_H), Color(0.08, 0.06, 0.09, 0.9))
	# Trailing white "chip" (recent damage) then the phase-colored fill.
	var col: Color = PHASE_COLORS[_phase_index()]
	draw_rect(Rect2(x0, y0, bar_w * _shown, BAR_H), Color(0.95, 0.9, 0.85, 0.5))
	draw_rect(Rect2(x0, y0, bar_w * _ratio, BAR_H), col)
	# Phase-gate notches at 66% and 33%.
	for frac: float in [0.66, 0.33]:
		var nx: float = x0 + bar_w * frac
		draw_rect(Rect2(nx - 1.0, y0 - 1.0, 2.0, BAR_H + 2.0), Color(0.05, 0.03, 0.05, 0.85))


func _phase_index() -> int:
	if _ratio <= 0.33:
		return 2
	if _ratio <= 0.66:
		return 1
	return 0
