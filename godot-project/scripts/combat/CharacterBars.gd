class_name CharacterBars
extends Node2D
## Floating HP (+ optional MP) bars over a character's head. A child of the
## fighter (Hero/Enemy) so it follows position without following the rig's L/R
## flip. Polls the target's hp/max_hp (and mp/max_mp) each frame — the
## poll-don't-push idiom (AbilityBar) — so it needs no signals and works for any
## node exposing those fields. Crisp: dark outline + bg + a colour-graded fill.

const WIDTH: float = 30.0
const HP_H: float = 4.0
const MP_H: float = 3.0
const GAP: float = 1.5
const BG: Color = Color(0.06, 0.07, 0.11, 0.85)
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.7)
const MP_COLOR: Color = Color(0.4, 0.62, 1.0, 1.0)

var _target: Node = null
var _show_mp: bool = false
var _hp_ratio: float = 1.0
var _mp_ratio: float = 1.0
var _has_hp: bool = false
var _has_mp: bool = false


## Attach to `target` (read its hp/max_hp; mp/max_mp if `show_mp`) and float the
## bars `y_offset` above the origin (negative = up, above the head).
func configure(target: Node, show_mp: bool = false, y_offset: float = -24.0) -> void:
	_target = target
	_show_mp = show_mp
	position = Vector2(0.0, y_offset)
	z_index = 30  # above the rig + aura


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		visible = false
		return
	var max_hp: Variant = _target.get("max_hp")
	var hp: Variant = _target.get("hp")
	if max_hp != null and hp != null and int(max_hp) > 0:
		_hp_ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		_has_hp = true
	if _show_mp:
		var max_mp: Variant = _target.get("max_mp")
		var mp: Variant = _target.get("mp")
		if max_mp != null and mp != null and int(max_mp) > 0:
			_mp_ratio = clampf(float(mp) / float(max_mp), 0.0, 1.0)
			_has_mp = true
	queue_redraw()


func _draw() -> void:
	if not _has_hp:
		return
	var x: float = -WIDTH * 0.5
	_bar(Vector2(x, 0.0), WIDTH, HP_H, _hp_ratio, _hp_color(_hp_ratio))
	if _show_mp and _has_mp:
		_bar(Vector2(x, HP_H + GAP), WIDTH, MP_H, _mp_ratio, MP_COLOR)


## One bar: dark outline, dark bg track, then a fill of `ratio` width.
func _bar(pos: Vector2, w: float, h: float, ratio: float, fill: Color) -> void:
	draw_rect(Rect2(pos - Vector2(1.0, 1.0), Vector2(w + 2.0, h + 2.0)), OUTLINE)
	draw_rect(Rect2(pos, Vector2(w, h)), BG)
	if ratio > 0.0:
		draw_rect(Rect2(pos, Vector2(w * ratio, h)), fill)


## Green (full) -> yellow (half) -> red (low).
func _hp_color(t: float) -> Color:
	if t > 0.5:
		return Color(0.3, 0.85, 0.35).lerp(Color(0.95, 0.82, 0.2), (1.0 - t) * 2.0)
	return Color(0.95, 0.82, 0.2).lerp(Color(0.92, 0.25, 0.2), (0.5 - t) * 2.0)
