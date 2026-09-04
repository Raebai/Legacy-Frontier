class_name BossBar
extends Control
## Top-of-screen boss health HUD: a wide segmented bar + name, phase-colored fill,
## with dark notches at the 66% / 33% phase gates so the player SEES them coming.
## Poll-don't-push (like CharacterBars): reads the boss's hp/max_hp each frame.
## Built in code, lives on its own CanvasLayer (see Boss._build_bar).

const HudStyle := preload("res://scripts/ui/HudStyle.gd")

## The Guardian's colours, kept as the DEFAULT rather than as the truth. See
## `setup()` — this file used to hard-code one boss's name in a `const`.
##
## ⚠ THE PHASE LADDER IS NOW BUILT FROM THE HUD PALETTE rather than from three
## hand-picked oranges. It is the same cool->hot escalation it always was; the
## point of deriving it is that "the hot red the boss bar reaches at P3" and "the
## red the hero's health bar reaches at 10%" were two different reds, and the
## player reads both in the same second of the same fight.
const DEFAULT_ACCENT: Color = HudStyle.EMBER
const PHASE_COLORS: Array[Color] = [
	Color(0.98, 0.62, 0.36),   # P1 — GOLD.lerp(EMBER, 0.5)
	HudStyle.EMBER,            # P2
	Color(0.95, 0.28, 0.23),   # P3 — EMBER.lerp(DANGER, 0.7)
]
const BAR_H: float = 15.0
const WIDTH_FRAC: float = 0.62
## THE MINI-GUARDIAN'S BAR. A floor-1 guardian is an event, not the headline act —
## it still needs its HP read at a glance, it does not need two thirds of a 640 px
## screen to say so. Same bar, same notches, same colours, less real estate. See the
## CEREMONY block in Boss.gd for why the ceremony has two settings at all.
const COMPACT_BAR_H: float = 9.0
const COMPACT_WIDTH_FRAC: float = 0.40
## Where the bar sits inside this control, and how thick its frame is. `BAR_TOP`
## was a bare `24.0` in `_draw`; it is a layout number and it belongs with the band.
const BAR_TOP: float = 22.0
const FRAME: float = 2.0
## Inset for the name label, so a long boss name ellipsises instead of running off
## the screen.
const NAME_INSET: float = 24.0
const COMPACT_NAME_SIZE: int = HudStyle.SMALL

var _boss: Node = null
var _compact: bool = false
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
func setup(boss: Node, boss_name: String = "", accent: Color = DEFAULT_ACCENT,
		compact: bool = false) -> void:
	_boss = boss
	_accent = accent
	_compact = compact
	var title: String = boss_name
	if title == "" and boss != null and boss.has_method("boss_title"):
		title = String(boss.call("boss_title"))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# ⚠ THE CONTROL'S RECT IS THE BAND, EXACTLY. It used to sit at offset_top 40
	# with a 60px minimum height — a rect from y40 to y100 — while drawing nothing
	# below y79. That phantom 21px ran straight through `BossModifierHud`'s row at
	# y84, so the two were only ever kept apart by `APPEAR_DELAY`, i.e. by a timing
	# coincidence rather than by a layout guarantee. 42..80 is the whole band and
	# the whole rect, and `tools/slice_test_hud_layout.gd` measures it.
	offset_top = HudStyle.BAND_BOSS_BAR[0]
	custom_minimum_size = Vector2(0.0, HudStyle.BAND_BOSS_BAR[1] - HudStyle.BAND_BOSS_BAR[0])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.text = title
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# ⚠ A NAME IS ARBITRARY TEXT AND THIS TOOK NONE OF IT ON TRUST. `setup()` accepts
	# any `boss_name` a subclass hands it, with no length contract; a long one used to
	# run off both edges of the screen. Inset + ellipsis is the honest answer — a
	# clipped name is a WRONG name, an ellipsised one is a shortened one.
	_name_label.offset_left = NAME_INSET
	_name_label.offset_right = -NAME_INSET
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.label(_name_label, COMPACT_NAME_SIZE if compact else HudStyle.BODY,
		accent.lerp(HudStyle.CHALK, 0.42))
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


## The bar's height and width right now — the compact pair for a mini-guardian,
## the full pair for the headline act. Public so a test can assert the two shapes
## differ without redrawing the bar and measuring pixels.
func bar_height() -> float:
	return COMPACT_BAR_H if _compact else BAR_H


func bar_width_frac() -> float:
	return COMPACT_WIDTH_FRAC if _compact else WIDTH_FRAC


## The bar's width in pixels for a viewport `full_w` wide.
##
## ⚠ THE WIDTH WAS THE ONLY VIEWPORT-RELATIVE DIMENSION IN THE WIDGET, and that is
## why the bar changed SHAPE per device. `project.godot` runs `aspect="expand"`, so
## a 20:9 phone hands this control a `size.x` of about 800 rather than 640 — the
## fraction then grew the bar to ~496px while `BAR_H`, `BAR_TOP` and the name's
## font size stayed exactly where they were. Same bar, different proportions, on
## the device the game is actually for.
##
## Capping at the base viewport's width makes it one shape everywhere: on a wider
## screen the bar keeps its 640-wide dimensions and simply sits centred in more
## room, which is what every other piece of this HUD already does.
func bar_pixel_width(full_w: float) -> float:
	return minf(full_w, HudStyle.BASE_VIEWPORT.x) * bar_width_frac()


func is_compact() -> bool:
	return _compact


func _draw() -> void:
	var full_w: float = size.x
	var bar_h: float = bar_height()
	var bar_w: float = bar_pixel_width(full_w)
	var x0: float = (full_w - bar_w) * 0.5
	var y0: float = BAR_TOP
	# Frame + track, at the one weight every bar in the game uses.
	draw_rect(Rect2(x0 - FRAME, y0 - FRAME, bar_w + FRAME * 2.0, bar_h + FRAME * 2.0),
		HudStyle.frame())
	draw_rect(Rect2(x0, y0, bar_w, bar_h), HudStyle.TRACK)
	# Trailing white "chip" (recent damage) then the phase-colored fill. The phase
	# ladder is the Guardian's (cool -> hot as the fight escalates), pulled toward
	# THIS boss's accent — so a cyan draughtsman does not get an ember-orange bar,
	# and the Guardian's own bar is within a rounding error of what it always was.
	var col: Color = PHASE_COLORS[_phase_index()].lerp(_accent, 0.55)
	draw_rect(Rect2(x0, y0, bar_w * _shown, bar_h), HudStyle.with_a(HudStyle.CHIP, 0.5))
	draw_rect(Rect2(x0, y0, bar_w * _ratio, bar_h), col)
	# Phase-gate notches at 66% and 33%.
	for frac: float in [0.66, 0.33]:
		var nx: float = x0 + bar_w * frac
		draw_rect(Rect2(nx - 1.0, y0 - 1.0, 2.0, bar_h + 2.0), HudStyle.ink(0.85))


func _phase_index() -> int:
	if _ratio <= 0.33:
		return 2
	if _ratio <= 0.66:
		return 1
	return 0
