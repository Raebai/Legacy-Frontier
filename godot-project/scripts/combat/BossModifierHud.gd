extends CanvasLayer
## The one line of screen that tells the player WHICH MODIFIERS ARE LIVE.
##
## A modifier that changes behaviour without announcing itself is indistinguishable
## from a bug. "Why did it teleport?" and "why are there two of them?" have to have
## answers the player can read off the screen in the half-second before the fight
## resumes — otherwise the whole system reads as inconsistency rather than variety,
## and inconsistency is what makes a hard boss feel unfair rather than hard.
##
## So: a row of short, coloured words under the boss bar, each in its own
## modifier's colour, fading in after the name card has had the screen to itself.
## Names only, no blurbs — at 640x360 on a phone a sentence is a grey smear, and the
## word is the mnemonic. The blurb exists in BossModifier.REGISTRY for a codex that
## does not exist yet.

const HudStyle := preload("res://scripts/ui/HudStyle.gd")

## Layer 56 sits one above the boss bar's 55, so the row always draws over the bar
## rather than under it. Both indices, and the band below, now come from one place
## — see the LAYERS AND BANDS block in `HudStyle`.
const LAYER: int = HudStyle.LAYER_BOSS_MODS
## Under the bar. ⚠ THIS WAS ONLY EVER SAFE BY ACCIDENT: the boss bar's Control
## rect ran to y100 (offset_top 40 + a 60px minimum height) even though it drew
## nothing below y79, so this row at y84 sat inside it and the two were kept apart
## by `APPEAR_DELAY` — a timing coincidence, not a layout guarantee. The bar's rect
## is now its band (42-80) and this one starts where that ends.
const TOP: float = HudStyle.BAND_BOSS_MODS[0]
const ROW_H: float = HudStyle.BAND_BOSS_MODS[1] - HudStyle.BAND_BOSS_MODS[0]
## Held back until the boss's own name card has finished its entrance — two pieces
## of text arriving together is neither of them landing.
const APPEAR_DELAY: float = 1.35
const FADE_TIME: float = 0.45

var modifier_ids: Array = []

var _row: HBoxContainer = null


func _ready() -> void:
	layer = LAYER
	if modifier_ids.is_empty():
		queue_free()
		return
	var wrap := Control.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	wrap.offset_top = TOP
	wrap.custom_minimum_size = Vector2(0.0, ROW_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 14)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_row)
	for m in modifier_ids:
		_row.add_child(_chip(String(m)))
	wrap.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(APPEAR_DELAY)
	tw.tween_property(wrap, "modulate:a", 1.0, FADE_TIME)


func _chip(mod_id: String) -> Label:
	var l := Label.new()
	l.text = BossModifier.name_for(mod_id)
	HudStyle.label(l, HudStyle.SMALL, BossModifier.tint_for(mod_id))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
