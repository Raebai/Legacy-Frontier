extends CanvasLayer
## THE ONE LINE THAT TELLS THE PLAYER THE WHOLE FLOOR IS DIFFERENT.
##
## A floor affix rides every body in the room and dresses none of them (see
## `EliteModifier.attach`'s `dressed` argument — sixteen glowing sticks is a light
## show, not a read). So the announcement has to happen ONCE, at the top of the floor,
## or the feature is exactly the thing `BossModifierHud` warns about: behaviour that
## changes without saying so, which is indistinguishable from a bug.
##
## The card is the affix's BLURB rather than its name, and this is the one place in
## the game where that is the right call. A word over a body's head is a mnemonic for
## a thing you can see; a floor-wide rule has nothing to point at, so it has to say
## what it means — "the ink never dried" is a sentence a player can act on before the
## first body lands.
##
## Sits above the wave announce and fades on its own. Nothing here is interactive and
## nothing here is gameplay: if this node fails to build, the floor still plays.

const LAYER: int = 57
const TOP: float = 54.0
const HOLD: float = 2.6
const FADE_IN: float = 0.35
const FADE_OUT: float = 0.7

## Set before the node enters the tree.
var affix_ids: Array = []

var _wrap: Control = null


func _ready() -> void:
	layer = LAYER
	if affix_ids.is_empty():
		queue_free()
		return
	_wrap = Control.new()
	_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_wrap.offset_top = TOP
	_wrap.custom_minimum_size = Vector2(0.0, 30.0)
	_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wrap)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrap.add_child(col)
	for a in affix_ids:
		col.add_child(_line(String(a)))
	_wrap.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_wrap, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(HOLD)
	tw.tween_property(_wrap, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(queue_free)


func _line(affix_id: String) -> Label:
	var l := Label.new()
	var blurb: String = EliteModifier.blurb_for(affix_id)
	l.text = "THIS FLOOR: %s — %s" % [EliteModifier.name_for(affix_id), blurb.to_upper()]
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", EliteModifier.tint_for(affix_id))
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.07, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
