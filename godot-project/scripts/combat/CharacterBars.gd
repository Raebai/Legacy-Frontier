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

const HudStyle := preload("res://scripts/ui/HudStyle.gd")

const WIDTH: float = 30.0
const HP_H: float = 4.0
const MP_H: float = 3.0
const GAP: float = 1.5

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
const CHIP_COLOR: Color = HudStyle.CHIP

## --- the hit flash ---
const FLASH_TIME: float = 0.18
## --- the heal pop (a green rim, so healing reads as loudly as being hit) ---
const HEAL_TIME: float = 0.30
## ONE green for "alive": the rim, the full end of the HP ramp and Hype's
## wave-cleared shout are now the same colour, because to the player they mean the
## same thing. See HudStyle.MINT.
const HEAL_RIM: Color = HudStyle.MINT

## --- the danger ring at the feet ---
## The hero's collision box is centred on its origin and the figure stands ~15px
## above that; the ring sits at ground level under the body.
const RING_FEET_DROP: float = 14.0
const RING_RADIUS: float = 19.0
const RING_COLOR: Color = HudStyle.DANGER

## Above this % the fill bar saturates (the number keeps climbing regardless).
const PCT_VISUAL_MAX: float = 150.0
## Warm (low %) -> red (high %), Smash-style: the more hurt, the redder + farther you fly.
## ⚠ These were `(1.0, 0.82, 0.35)` and `(0.95, 0.16, 0.12)` — the same two colours
## `RunSummary` stores as `(1.0, 0.82, 0.36)` and the same red the danger ring uses
## at `(1.0, 0.24, 0.2)`. Three files, one gold and one red, three roundings.
const PCT_WARM: Color = HudStyle.GOLD
const PCT_RED: Color = HudStyle.DANGER

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
	# ⚠ ABOVE THE DAMAGE NUMBERS, WHICH IT WAS NOT. This was 30 while
	# `DamageNumber` spawned at 60, so a number could sit on top of the bar it was
	# explaining. The bar is the persistent readout; the number is a garnish that
	# lives 0.7s. See HudStyle.Z_CHARACTER_BARS.
	z_index = HudStyle.Z_CHARACTER_BARS  # above the rig, the aura and the numbers
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


## The multiplier that keeps this node's geometry a constant size ON SCREEN. See
## the ONE ZOOM RULE block in `HudStyle` for the arithmetic and the measurements.
##
## ⚠ TWO THINGS CHANGED HERE AND BOTH WERE BUGS.
##
## 1. IT WAS HERO-ONLY. `if not _is_hero: return 1.0` meant the hero's bar held its
##    size while every ENEMY bar was raw world pixels — so at the camera's 0.46
##    pull-back an enemy's 4px bar was **1.8 screen pixels**, and the hero's grew,
##    in the same frame. Two widgets that are the same widget were visibly
##    disagreeing about what a pixel is. Compensation is NOT "hero mode": the
##    header's rule (enemies do not get the hero's size, segments or chip bar) is
##    untouched — an enemy bar is still 30x4 at the reference zoom. It just stays
##    30x4 instead of shrinking to nothing exactly when eight of them are on screen.
##
## 2. THE CLAMP'S LOW END WAS 1.0, i.e. "never compensate for a camera tighter than
##    1.0" — but the camera SITS at 1.6 and goes to 2.6. Compensation only ever ran
##    at the wide end, so the bar was still a different size at rest than in a
##    pull-back. `HudStyle.ui_scale` clamps to the camera's real range around a 1.6
##    reference, which leaves every widget pixel-identical to today at rest.
##
## ⚠ APPLIED TO THE DRAWING, NEVER TO `scale`. Scaling this node would also scale its
## own `position` offset in the parent's space and drag the bar down through the
## hero's head as the camera pulled back — and it would move the danger ring, which
## has to stay pinned to the feet in the hero's own coordinates.
func _ui_scale() -> float:
	return HudStyle.ui_scale(self)


func _draw() -> void:
	if _ringout:
		_draw_pct()
		return
	if not _has_hp:
		return
	if _is_hero:
		_draw_hero()
		return
	# The enemy bar. Same geometry it has always had at the reference zoom; the
	# only change is that it now holds that size when the camera moves.
	var ui: float = _ui_scale()
	var w: float = WIDTH * ui
	var x: float = -w * 0.5
	_bar(Vector2(x, 0.0), w, HP_H * ui, _hp_ratio, HudStyle.hp_color(_hp_ratio), ui)
	if _show_mp and _has_mp:
		_bar(Vector2(x, (HP_H + GAP) * ui), w, MP_H * ui, _mp_ratio, HudStyle.AZURE, ui)


## The readable bar. Drawn bottom-anchored — the bar's lower edge stays where the old
## 4px bar's did, and every extra pixel grows UPWARD into empty sky rather than down
## over the hero's head.
func _draw_hero() -> void:
	var ui: float = _ui_scale()
	var w: float = HERO_WIDTH * ui
	var h: float = HERO_HP_H * ui
	# ⚠ ANCHORED OFF THE SCALED HEIGHT. This used to read `HP_H - h` — an UNSCALED
	# constant minus a scaled one — so the bar's lower edge crept as the camera
	# moved, which is the one thing a bottom-anchored bar exists to prevent.
	var at := Vector2(-w * 0.5, HP_H * ui - h)
	var low: bool = _hp_ratio <= LOW_FRACTION
	if low:
		_draw_danger(ui)
	var fill: Color = HudStyle.hp_color(_hp_ratio)
	if low:
		# The danger pulse rides the FILL, not just the frame: a bar that is both
		# short and beating is unmistakable in peripheral vision.
		fill = fill.lerp(HudStyle.CHALK, 0.20 + 0.20 * sin(_phase * 7.0))
	# A fat dark frame — the bar has to survive being drawn over a lit floor, and a
	# 1px outline at this size disappears into the post-process grade.
	# ⚠ ONE FRAME WEIGHT FOR EVERY BAR IN THE GAME. This was `maxf(2.0 * ui, 2.0)`
	# while `_bar()` — which draws the MP bar directly underneath, in the same
	# widget — used a hardcoded 1.0. Two border weights inside one column is the
	# kind of near-miss that reads as sloppiness without ever being nameable.
	var pad: float = HudStyle.frame_pad(ui)
	draw_rect(Rect2(at - Vector2(pad, pad), Vector2(w, h) + Vector2(pad, pad) * 2.0),
		HudStyle.frame())
	draw_rect(Rect2(at, Vector2(w, h)), HudStyle.TRACK)
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
		draw_rect(Rect2(at, Vector2(w, h)), HudStyle.with_a(HudStyle.CHALK, a))
	# 4. SEGMENT TICKS, cut through everything above so the shape survives any fill.
	for i: int in range(1, HERO_SEGMENTS):
		var tx: float = at.x + w * (float(i) / float(HERO_SEGMENTS))
		draw_rect(Rect2(Vector2(tx - 0.5 * ui, at.y), Vector2(maxf(ui, 1.0), h)),
			HudStyle.ink(0.55))
	# 5. THE HEAL POP — a green rim, so a health pack landing is as loud as a hit.
	if _heal_pop > 0.0:
		var g: float = _heal_pop / HEAL_TIME
		draw_rect(Rect2(at - Vector2(pad, pad) * 0.5,
			Vector2(w, h) + Vector2(pad, pad)),
			HudStyle.with_a(HEAL_RIM, g * 0.85), false, pad)
	if _show_mp and _has_mp:
		_bar(Vector2(at.x, at.y + h + GAP * ui), w, MP_H * ui, _mp_ratio,
			HudStyle.AZURE, ui)


## The last-legs read, drawn ON THE BODY. Two breathing arcs at the hero's feet —
## where the player's eyes already are — because a warning that lives only above the
## head is a warning you have to look away from the fight to receive.
##
## `-position.y` puts this back at the hero's own origin: `configure` offsets this
## node upward, and the ring must not travel with the bar.
## ⚠ THE ONE PIECE OF THIS FILE THAT IS HONESTLY WORLD-SPACE, and the line that
## decides it is: **a READOUT is zoom-compensated, a piece of BODY DECORATION is
## not.** The bars, the numbers and the % are things you read, so they hold a
## constant on-screen size. This ring is not read — it is a shape drawn AROUND the
## hero's feet, and a ring whose radius is pinned to the screen slides off the body
## the moment the camera moves. At the camera's tight end a compensated ring would
## have a smaller radius than the figure standing inside it.
func _draw_danger(_ui: float) -> void:
	var beat: float = 0.5 + 0.5 * sin(_phase * 6.0)
	# Deeper as the bar empties, so the ring is not a binary "you are low" but a dial.
	var urgency: float = clampf(1.0 - _hp_ratio / maxf(LOW_FRACTION, 0.01), 0.0, 1.0)
	var at := Vector2(0.0, -position.y + RING_FEET_DROP)
	var r: float = RING_RADIUS * (0.88 + 0.14 * beat)
	var a: float = (0.22 + 0.30 * urgency) * (0.55 + 0.45 * beat)
	draw_arc(at, r, 0.0, TAU, 30, HudStyle.with_a(RING_COLOR, a), 2.4, true)
	draw_arc(at, r * 0.6, 0.0, TAU, 24, HudStyle.with_a(RING_COLOR, a * 0.5), 1.4, true)


## Smash readout: a warm->red fill that grows with % + the number itself climbing
## over the head. The fill saturates at PCT_VISUAL_MAX; the number never caps.
func _draw_pct() -> void:
	# ⚠ THE READOUT ON THIS NODE USED TO BE THE ONLY UNCOMPENSATED THING ON IT: the
	# bar above was fully zoom-corrected and the number was drawn at a flat font 11
	# in WORLD units, so it ran 5 screen px at the camera's wide end and 29 at its
	# tight one — on the same node, in the same frame, as a bar that did not move.
	var ui: float = _ui_scale()
	var w: float = WIDTH * ui
	var x: float = -w * 0.5
	var ratio: float = clampf(_pct / PCT_VISUAL_MAX, 0.0, 1.0)
	var col: Color = PCT_WARM.lerp(PCT_RED, ratio)
	_bar(Vector2(x, 0.0), w, HP_H * ui, ratio, col, ui)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	# ⚠ CAPPED AT FOUR CHARACTERS. `"%d%%"` was uncapped into a 30px-wide draw box:
	# "1000%" was exactly clipped and "1234%" lost its last digit, which is worse
	# than saturating because a truncated number is a WRONG number, silently. Past
	# 999 the exact figure stops being information anyway — you are being launched
	# either way — so it saturates and says so.
	var shown: int = int(round(_pct))
	var label: String = "999+%" if shown > 999 else "%d%%" % shown
	var fs: int = int(round(float(HudStyle.SMALL) * ui))
	# Sit the number just above the bar, colour-matched to the fill, dark-outlined.
	var pos := Vector2(x, -3.0 * ui)
	draw_string_outline(font, pos + Vector2(0.0, -ui), label,
		HORIZONTAL_ALIGNMENT_CENTER, w, fs, HudStyle.outline_for(fs), HudStyle.ink(0.95))
	draw_string(font, pos + Vector2(0.0, -ui), label,
		HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


## True when the sandbox ring-out model is active (GameState.ringout_mode).
func _is_ringout_mode() -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	return gs != null and bool(gs.get("ringout_mode"))


## One bar: frame, track, then a fill of `ratio` width. `ui` is the zoom
## compensation so the FRAME scales with the bar — it was a hardcoded 1.0px, which
## is why the hero's MP bar had a hairline frame directly under an HP bar with a
## 2–4.8px one.
func _bar(pos: Vector2, w: float, h: float, ratio: float, fill: Color,
		ui: float = 1.0) -> void:
	var pad: float = HudStyle.frame_pad(ui)
	draw_rect(Rect2(pos - Vector2(pad, pad), Vector2(w + pad * 2.0, h + pad * 2.0)),
		HudStyle.frame())
	draw_rect(Rect2(pos, Vector2(w, h)), HudStyle.TRACK)
	if ratio > 0.0:
		draw_rect(Rect2(pos, Vector2(w * ratio, h)), fill)


## The three-stop HP ramp — green (full) -> gold (half) -> red (low) — MOVED to
## `HudStyle.hp_color`. It lived here as three inline literals whose green, gold
## and red were each within a rounding error of a colour another HUD file was also
## storing; there are no callers outside this file (checked), so it is a move
## rather than a delegate.
