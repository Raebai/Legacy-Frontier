class_name BossBar
extends Control
## Top-of-screen boss health HUD: a wide segmented bar + name, phase-colored fill,
## with dark notches at the 66% / 33% phase gates so the player SEES them coming.
## Poll-don't-push (like CharacterBars): reads the boss's hp/max_hp each frame.
## Built in code, lives on its own CanvasLayer (see Boss._build_bar).

## The Guardian's colours, kept as the DEFAULT rather than as the truth. See
## `setup()` — this file used to hard-code one boss's name in a `const`.
const DEFAULT_ACCENT: Color = Color(1.0, 0.55, 0.2)
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
var _accent: Color = DEFAULT_ACCENT


## THE BAR IS TOLD WHO IT IS DRAWING.
##
## ⚠ THIS USED TO BE `setup(boss)` READING A `const NAME_TEXT = "THE ASHSPIRE
## GUARDIAN"`. That was fine while there was one boss. With four, the roster had to
## work around it by reaching into the bar AFTER construction and rewriting the
## label it found (`TowerBoss._apply_identity`) — which meant the top of the screen
## briefly said the wrong boss's name, the workaround silently depended on a private
## member called `_name_label`, and the fifth boss's author had to know to do it
## again. A const naming one specific boss is a trap, not a default.
##
## `boss_name` empty falls back to asking the boss itself (`Boss.boss_title`), so a
## caller that forgets still gets the right name rather than the Guardian's.
func setup(boss: Node, boss_name: String = "", accent: Color = DEFAULT_ACCENT) -> void:
	_boss = boss
	_accent = accent
	var title: String = boss_name
	if title == "" and boss != null and boss.has_method("boss_title"):
		title = String(boss.call("boss_title"))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_top = 40.0
	custom_minimum_size = Vector2(0.0, 60.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.text = title
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", accent.lerp(Color(1, 1, 1), 0.42))
	_name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.05, 0.95))
	_name_label.add_theme_constant_override("outline_size", 5)
	add_child(_name_label)


## The name currently on the bar. Exists so a test can assert the bar says what the
## boss says without reading a private member the way the old workaround did.
func displayed_name() -> String:
	return _name_label.text if _name_label != null else ""


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
	# Trailing white "chip" (recent damage) then the phase-colored fill. The phase
	# ladder is the Guardian's (cool -> hot as the fight escalates), pulled toward
	# THIS boss's accent — so a cyan draughtsman does not get an ember-orange bar,
	# and the Guardian's own bar is within a rounding error of what it always was.
	var col: Color = PHASE_COLORS[_phase_index()].lerp(_accent, 0.55)
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
