class_name CharacterBars
extends Node2D
## Floating HP (+ optional MP) bars over a character's head. A child of the
## fighter (Hero/Enemy) so it follows position without following the rig's L/R
## flip. Polls the target's hp/max_hp (and mp/max_mp) each frame — the
## poll-don't-push idiom (AbilityBar) — so it needs no signals and works for any
## node exposing those fields.
##
## ══ HERO MODE — "I CANNOT READ MY HEALTH" ══════════════════════════════════════
## Maker: the game "is hard right now" and the health "needs to be clearere". This
## was the only health readout in the game — there is no HUD health bar anywhere —
## and for the hero it was 30x4 WORLD pixels. Two things made that unreadable, and
## the second one is the real culprit:
##
##   1. It was tiny. 4px tall next to a 31px figure, in a frame with spell light all
##      over it.
##   2. ⚠ IT SHRANK EXACTLY WHEN IT MATTERED. This is a Node2D, so its on-screen size
##      is its world size times the camera zoom — and `CombatCamera` zooms OUT to
##      frame the whole fight (`FRAME_ZOOM_MIN` is 0.5 against a 2.6 max). So the
##      busier the screen got, the SMALLER the health bar became: at full pull-back
##      those 4 world pixels are 2 screen pixels on a 360-tall viewport. The bar was
##      least legible in precisely the moments the player needed it.
##
## So hero mode does four things, each answering one way the old bar failed:
##   * SCREEN-CONSTANT SIZE. Everything is multiplied by `1 / camera.zoom`, so the
##     bar occupies the same fraction of a phone screen whether the camera is tight
##     on one enemy or pulled back over the whole room. This is the fix.
##   * BIGGER, AND SEGMENTED. Wider + taller, with a tick every 25%, so "a quarter
##     left" is read as a SHAPE from across the room instead of as a length you have
##     to estimate.
##   * A CHIP BAR. The damage you just took stays on screen as a pale ghost that
##     drains a beat later. It answers "how hard was that hit" — a question a bar
##     that snaps instantly cannot answer at all — and it is the thing that makes a
##     hit READ without adding a damage number to a screen the maker already thinks
##     has too much text on it.
##   * A DANGER STATE. Under `LOW_FRACTION` the bar pulses and a soft red ring
##     breathes at the hero's feet. That ring is on the BODY, which is where the
##     player is already looking, so "I am about to die" does not require glancing up.
##
## ⚠ NO NUMBERS, NO LABELS, ON PURPOSE. The standing rule is "this game has too much
## text and random UI pieces we dont need". Everything above is size, shape, motion
## and colour — nothing here asks the player to read a word mid-fight.
##
## ⚠ ENEMIES ARE UNCHANGED. Hero mode is keyed off `is_in_group("hero")` and nothing
## else, because `configure()`'s signature is called from `Hero.gd` and `Enemy.gd`,
## which this file does not own. A screen with eight enemies on it must not become a
## screen with eight big screen-constant bars on it — the enemy bar's job is "how
## close is that one to dying", and it has always done that fine.

const WIDTH: float = 30.0
const HP_H: float = 4.0
const MP_H: float = 3.0
const GAP: float = 1.5
const BG: Color = Color(0.06, 0.07, 0.11, 0.85)
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.7)
const MP_COLOR: Color = Color(0.4, 0.62, 1.0, 1.0)

## --- hero geometry (screen pixels at zoom 1; see `_ui_scale`) ---
const HERO_WIDTH: float = 52.0
const HERO_HP_H: float = 7.0
## A tick every quarter. Four segments is the most a bar can carry and still be read
## as a shape rather than counted.
const HERO_SEGMENTS: int = 4

## Above this the bar is a resource; below it, it is a warning.
const LOW_FRACTION: float = 0.35

## --- the chip bar (damage just taken) ---
## Hold the ghost still for this long so the hit is legible, then drain it.
const CHIP_HOLD: float = 0.32
## Fraction of the bar the ghost drains per second once it lets go. 1.2 empties a
## full bar in under a second — fast enough not to lie about your current health.
const CHIP_DRAIN: float = 1.2
const CHIP_COLOR: Color = Color(1.0, 0.86, 0.72, 0.9)

## --- the hit flash ---
const FLASH_TIME: float = 0.18
## --- the heal pop (a green rim, so healing reads as loudly as being hit) ---
const HEAL_TIME: float = 0.30
const HEAL_RIM: Color = Color(0.5, 1.0, 0.65)

## --- the danger ring at the feet ---
## The hero's collision box is centred on its origin and the figure stands ~15px
## above that; the ring sits at ground level under the body.
const RING_FEET_DROP: float = 14.0
const RING_RADIUS: float = 19.0
const RING_COLOR: Color = Color(1.0, 0.24, 0.2)

## Clamp on the zoom compensation. Below 1 the camera is pulled back and the bar is
## grown to match; the ceiling stops a hypothetical 0.1 zoom producing a bar that
## covers the arena.
const UI_SCALE_MAX: float = 2.4

## Above this % the fill bar saturates (the number keeps climbing regardless).
const PCT_VISUAL_MAX: float = 150.0
## Warm (low %) -> red (high %), Smash-style: the more hurt, the redder + farther you fly.
const PCT_WARM: Color = Color(1.0, 0.82, 0.35)
const PCT_RED: Color = Color(0.95, 0.16, 0.12)

var _target: Node = null
var _show_mp: bool = false
var _hp_ratio: float = 1.0
var _mp_ratio: float = 1.0
var _has_hp: bool = false
var _has_mp: bool = false
## SANDBOX Smash mode (GameState.ringout_mode): render a rising damage % instead
## of the green HP bar.
var _ringout: bool = false
var _pct: float = 0.0

## --- hero mode state ---
var _is_hero: bool = false
var _chip_ratio: float = 1.0
var _chip_hold: float = 0.0
var _flash: float = 0.0
var _heal_pop: float = 0.0
var _phase: float = 0.0


## Attach to `target` (read its hp/max_hp; mp/max_mp if `show_mp`) and float the
## bars `y_offset` above the origin (negative = up, above the head).
func configure(target: Node, show_mp: bool = false, y_offset: float = -24.0) -> void:
	_target = target
	_show_mp = show_mp
	position = Vector2(0.0, y_offset)
	z_index = 30  # above the rig + aura
	# ⚠ GROUP MEMBERSHIP, not a new parameter. `Hero.gd` and `Enemy.gd` own the two
	# call sites and neither can be edited from here, so hero mode has to be something
	# this node can work out for itself. `"hero"` is the identity group ~40 places
	# already read (see `GhostForm.enter`'s note on why it is never dropped), which
	# makes it the one answer that cannot drift.
	_is_hero = target != null and target.is_in_group(&"hero")


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		visible = false
		return
	_phase += delta
	# Sandbox Smash: show the accrued damage % (rising, warm->red) instead of HP.
	_ringout = _is_ringout_mode()
	if _ringout:
		var pct: Variant = _target.get("damage_pct")
		_pct = float(pct) if pct != null else 0.0
		queue_redraw()
		return
	var max_hp: Variant = _target.get("max_hp")
	var hp: Variant = _target.get("hp")
	if max_hp != null and hp != null and int(max_hp) > 0:
		_set_hp_ratio(clampf(float(hp) / float(max_hp), 0.0, 1.0), delta)
		_has_hp = true
	if _show_mp:
		var max_mp: Variant = _target.get("max_mp")
		var mp: Variant = _target.get("mp")
		if max_mp != null and mp != null and int(max_mp) > 0:
			_mp_ratio = clampf(float(mp) / float(max_mp), 0.0, 1.0)
			_has_mp = true
	queue_redraw()


## Fold a fresh reading in, and run the chip/flash/heal clocks off the DELTA between
## readings. Derived from the polled ratio rather than from `health_changed` on
## purpose: the signal also fires on heals, on class config, on the round reset and
## on `_die` (which reports 0 and then heals straight back) — a chip bar driven by it
## would flash on all five. The difference between two polls is only ever the thing
## that actually happened to the bar.
func _set_hp_ratio(now: float, delta: float) -> void:
	if not _is_hero:
		_hp_ratio = now
		return
	if now < _hp_ratio - 0.0005:
		_flash = FLASH_TIME
		_chip_hold = CHIP_HOLD          # the ghost stays where the bar WAS
	elif now > _hp_ratio + 0.0005:
		_heal_pop = HEAL_TIME
		_chip_ratio = maxf(_chip_ratio, now)   # never let the ghost sit BELOW the fill
	_hp_ratio = now
	_flash = maxf(_flash - delta, 0.0)
	_heal_pop = maxf(_heal_pop - delta, 0.0)
	if _chip_hold > 0.0:
		_chip_hold -= delta
	else:
		_chip_ratio = maxf(_chip_ratio - CHIP_DRAIN * delta, _hp_ratio)
	_chip_ratio = maxf(_chip_ratio, _hp_ratio)


## The multiplier that keeps hero geometry a constant size ON SCREEN. `zoom` is a
## magnification, so the compensation is its reciprocal.
##
## ⚠ APPLIED TO THE DRAWING, NEVER TO `scale`. Scaling this node would also scale its
## own `position` offset in the parent's space and drag the bar down through the
## hero's head as the camera pulled back — and it would move the danger ring, which
## has to stay pinned to the feet in the hero's own coordinates.
func _ui_scale() -> float:
	if not _is_hero or not is_inside_tree():
		return 1.0
	var vp: Viewport = get_viewport()
	if vp == null:
		return 1.0
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return 1.0
	var z: float = minf(cam.zoom.x, cam.zoom.y)
	if z <= 0.01:
		return 1.0
	return clampf(1.0 / z, 1.0, UI_SCALE_MAX)


func _draw() -> void:
	if _ringout:
		_draw_pct()
		return
	if not _has_hp:
		return
	if _is_hero:
		_draw_hero()
		return
	var x: float = -WIDTH * 0.5
	_bar(Vector2(x, 0.0), WIDTH, HP_H, _hp_ratio, _hp_color(_hp_ratio))
	if _show_mp and _has_mp:
		_bar(Vector2(x, HP_H + GAP), WIDTH, MP_H, _mp_ratio, MP_COLOR)


## The readable bar. Drawn bottom-anchored — the bar's lower edge stays where the old
## 4px bar's did, and every extra pixel grows UPWARD into empty sky rather than down
## over the hero's head.
func _draw_hero() -> void:
	var ui: float = _ui_scale()
	var w: float = HERO_WIDTH * ui
	var h: float = HERO_HP_H * ui
	var at := Vector2(-w * 0.5, HP_H - h)
	var low: bool = _hp_ratio <= LOW_FRACTION
	if low:
		_draw_danger(ui)
	var fill: Color = _hp_color(_hp_ratio)
	if low:
		# The danger pulse rides the FILL, not just the frame: a bar that is both
		# short and beating is unmistakable in peripheral vision.
		fill = fill.lerp(Color(1.0, 0.95, 0.9), 0.20 + 0.20 * sin(_phase * 7.0))
	# A fat dark frame — the bar has to survive being drawn over a lit floor, and a
	# 1px outline at this size disappears into the post-process grade.
	var pad: float = maxf(2.0 * ui, 2.0)
	draw_rect(Rect2(at - Vector2(pad, pad), Vector2(w, h) + Vector2(pad, pad) * 2.0), OUTLINE)
	draw_rect(Rect2(at, Vector2(w, h)), BG)
	# 1. THE CHIP — what you just lost, still on screen a beat later.
	if _chip_ratio > _hp_ratio:
		var cx: float = w * _hp_ratio
		draw_rect(Rect2(at + Vector2(cx, 0.0),
			Vector2(w * (_chip_ratio - _hp_ratio), h)), CHIP_COLOR)
	# 2. THE FILL.
	if _hp_ratio > 0.0:
		draw_rect(Rect2(at, Vector2(w * _hp_ratio, h)), fill)
	# 3. THE HIT FLASH — the whole fill whitens for a frame or two.
	if _flash > 0.0:
		var a: float = (_flash / FLASH_TIME) * 0.75
		draw_rect(Rect2(at, Vector2(w, h)), Color(1.0, 1.0, 1.0, a))
	# 4. SEGMENT TICKS, cut through everything above so the shape survives any fill.
	for i: int in range(1, HERO_SEGMENTS):
		var tx: float = at.x + w * (float(i) / float(HERO_SEGMENTS))
		draw_rect(Rect2(Vector2(tx - 0.5 * ui, at.y), Vector2(maxf(ui, 1.0), h)),
			Color(0.0, 0.0, 0.0, 0.55))
	# 5. THE HEAL POP — a green rim, so a health pack landing is as loud as a hit.
	if _heal_pop > 0.0:
		var g: float = _heal_pop / HEAL_TIME
		draw_rect(Rect2(at - Vector2(pad, pad) * 0.5,
			Vector2(w, h) + Vector2(pad, pad)),
			Color(HEAL_RIM.r, HEAL_RIM.g, HEAL_RIM.b, g * 0.85), false, maxf(2.0 * ui, 2.0))
	if _show_mp and _has_mp:
		_bar(Vector2(at.x, at.y + h + GAP * ui), w, MP_H * ui, _mp_ratio, MP_COLOR)


## The last-legs read, drawn ON THE BODY. Two breathing arcs at the hero's feet —
## where the player's eyes already are — because a warning that lives only above the
## head is a warning you have to look away from the fight to receive.
##
## `-position.y` puts this back at the hero's own origin: `configure` offsets this
## node upward, and the ring must not travel with the bar.
func _draw_danger(ui: float) -> void:
	var beat: float = 0.5 + 0.5 * sin(_phase * 6.0)
	# Deeper as the bar empties, so the ring is not a binary "you are low" but a dial.
	var urgency: float = clampf(1.0 - _hp_ratio / maxf(LOW_FRACTION, 0.01), 0.0, 1.0)
	var at := Vector2(0.0, -position.y + RING_FEET_DROP)
	var r: float = RING_RADIUS * ui * (0.88 + 0.14 * beat)
	var a: float = (0.22 + 0.30 * urgency) * (0.55 + 0.45 * beat)
	draw_arc(at, r, 0.0, TAU, 30,
		Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, a), 2.4 * ui, true)
	draw_arc(at, r * 0.6, 0.0, TAU, 24,
		Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, a * 0.5), 1.4 * ui, true)


## Smash readout: a warm->red fill that grows with % + the number itself climbing
## over the head. The fill saturates at PCT_VISUAL_MAX; the number never caps.
func _draw_pct() -> void:
	var x: float = -WIDTH * 0.5
	var ratio: float = clampf(_pct / PCT_VISUAL_MAX, 0.0, 1.0)
	var col: Color = PCT_WARM.lerp(PCT_RED, ratio)
	_bar(Vector2(x, 0.0), WIDTH, HP_H, ratio, col)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var label: String = "%d%%" % int(round(_pct))
	# Sit the number just above the bar, colour-matched to the fill, dark-outlined.
	var pos := Vector2(x, -3.0)
	draw_string_outline(font, pos + Vector2(0, -1), label, HORIZONTAL_ALIGNMENT_CENTER, WIDTH, 11, 3, Color(0.05, 0.05, 0.08, 0.9))
	draw_string(font, pos + Vector2(0, -1), label, HORIZONTAL_ALIGNMENT_CENTER, WIDTH, 11, col)


## True when the sandbox ring-out model is active (GameState.ringout_mode).
func _is_ringout_mode() -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	return gs != null and bool(gs.get("ringout_mode"))


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
