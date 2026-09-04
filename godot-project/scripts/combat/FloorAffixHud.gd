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

const HudStyle := preload("res://scripts/ui/HudStyle.gd")

const LAYER: int = HudStyle.LAYER_AFFIX
## ⚠ 108, NOT 54. At 54 this card ran from y54 to y84 — straight through the boss
## bar (y64-79) and hard up against `BossModifierHud`'s row at y84. On a boss floor
## with a floor affix, which is the exact case this card exists for, the one line
## explaining the whole floor was drawn over the boss's health. It now has its own
## band; see the LAYERS AND BANDS block in `HudStyle`.
const TOP: float = HudStyle.BAND_AFFIX[0]
## One row per affix. The band holds two; see MAX_ROWS.
const ROW_H: float = 16.0
## ⚠ A THIRD AFFIX USED TO SPILL. The wrap was a flat 30px — exactly two rows at
## font 11 — with no autowrap and no cap, so a third row grew SYMMETRICALLY out of
## the centred VBox and pushed its bottom edge into the modifier row below. Two
## rows is what the band holds, so two rows is what is drawn, and the rest is
## counted rather than silently lost.
const MAX_ROWS: int = 2
## Left/right inset. The strings are up to 49 characters ("THIS FLOOR: INKED —
## PRESSED TOO HARD INTO THE PAGE") on a 640px base with `aspect="expand"`, and the
## old label had no autowrap, no clip and no bounded width at all.
const SIDE_INSET: float = 20.0
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
	_wrap.offset_left = SIDE_INSET
	_wrap.offset_right = -SIDE_INSET
	var rows: int = mini(affix_ids.size(), MAX_ROWS)
	_wrap.custom_minimum_size = Vector2(0.0, float(rows) * ROW_H)
	_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wrap)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# ⚠ ZERO SEPARATION, DELIBERATELY. A VBoxContainer's default 4px gap is invisible
	# in a one-row card and is exactly what pushes a two-row card 4px past the band
	# — the widget's own rect stays honest while its CONTENT spills, which is the
	# most annoying shape this class of bug takes.
	col.add_theme_constant_override(&"separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrap.add_child(col)
	# The overflow is SAID, not dropped: row two carries "+N MORE" so a player on a
	# three-affix floor knows a rule they cannot see is running.
	var extra: int = affix_ids.size() - rows
	for i: int in rows:
		var last_row: bool = extra > 0 and i == rows - 1
		var suffix: String = ("   ·   +%d MORE" % extra) if last_row else ""
		col.add_child(_line(String(affix_ids[i]), suffix))
	_wrap.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_wrap, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(HOLD)
	tw.tween_property(_wrap, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(queue_free)


func _line(affix_id: String, suffix: String = "") -> Label:
	var l := Label.new()
	var blurb: String = EliteModifier.blurb_for(affix_id)
	l.text = "THIS FLOOR: %s — %s%s" % [
		EliteModifier.name_for(affix_id), blurb.to_upper(), suffix]
	HudStyle.label(l, HudStyle.SMALL, EliteModifier.tint_for(affix_id))
	# One row, ellipsised. `clip_text` alone would cut a word mid-stroke and read as
	# a rendering fault; the ellipsis reads as "there is more of this sentence".
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(0.0, ROW_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
