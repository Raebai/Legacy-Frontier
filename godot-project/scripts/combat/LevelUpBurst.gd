class_name LevelUpBurst
extends Node2D
## THE LEVEL-UP BEAT — "a nice little level up animation around the stickman".
##
## Built out of the vocabulary the game already has rather than a new one: the
## summoning circle lies down at the hero's feet and BLOOMS UPWARD, motes rise
## through the body, a shockring leaves, and the number lands. The circle is a real
## `MagicCircle`, the same object every spell in the game summons through, because
## it is the one visual this project has committed to as its signature.
##
## ⚠ IT IS A REWARD, NOT AN ATTACK. There is no `target_group`, no `caster_node`
## and no damage — deliberately. A spectacle built with a caster joins the reaction
## system, and a level-up that made other spells react to it would be a body-double
## for a spell going off in the middle of a fight. This one is scenery.
##
## ⚠ IT FOLLOWS THE HERO. `_host` is tracked every frame rather than the burst
## being parented to the hero, because a hero that dashes mid-level-up would drag a
## ground circle sideways through the floor; and parenting to a body that can
## `queue_free` (a co-op puppet despawning) takes the effect down with it.

## Beat lengths. The whole thing is ~1.1 s: long enough to read the number, short
## enough that it never becomes a cutscene in the middle of a wave.
const RISE_TIME: float = 0.34         # circle blooms, motes leave the floor
const HOLD_TIME: float = 0.34         # the number is legible
const FADE_TIME: float = 0.42

const CIRCLE_RADIUS: float = 34.0
const CIRCLE_GROUND_SQUASH: float = 0.30

const MOTES: int = 14
const MOTES_LOW: int = 5              # the phone picture — see _low
const MOTE_RISE: float = 46.0         # how far a mote climbs, in px
const MOTE_SPREAD: float = 15.0       # horizontal scatter around the body

const RING_RADIUS_START: float = 8.0
const RING_RADIUS_END: float = 52.0

## Where the number sits relative to the hero's origin. Above the head, clear of
## the damage numbers that spawn at -16.
const LABEL_OFFSET: Vector2 = Vector2(0.0, -46.0)

var _host: Node2D = null
var _tint: Color = Color(1.0, 0.92, 0.55, 1.0)
var _level: int = 1
var _t: float = 0.0
var _total: float = RISE_TIME + HOLD_TIME + FADE_TIME
var _circle: MagicCircle = null
var _label: Label = null
## Per-mote horizontal offset + phase, rolled once so the column does not shimmer
## by re-randomising every frame.
var _mote_x: PackedFloat32Array = PackedFloat32Array()
var _mote_delay: PackedFloat32Array = PackedFloat32Array()


## Fire the beat. `host` is the body it happens around; `tint` the class colour.
##
## ⚠ ADD TO THE ARENA, NOT TO THE HERO. See the header.
static func play(arena: Node, host: Node2D, level: int, tint: Color) -> LevelUpBurst:
	if arena == null or host == null or not is_instance_valid(host):
		return null
	var b := LevelUpBurst.new()
	b._host = host
	b._level = maxi(level, 1)
	b._tint = tint
	b.global_position = host.global_position
	# One rung IN FRONT of the fighters. `StageLayers` names every rung from SKY
	# (-30) up to FIGHTER (0) and stops there — everything above the bodies is
	# spectacle and picks its own. +1 is the minimum that reads: the circle is at the
	# hero's feet and must not be hidden by the hero standing on it.
	b.z_index = StageLayers.FIGHTER + 1
	arena.add_child(b)
	b._begin()
	return b


## ⚠ MUST DEGRADE AT `graphics_quality = LOW` (the phone preview, a hard rule).
## What survives is the CIRCLE and the NUMBER — the two things that carry the
## meaning. What thins is the mote column and the shockring, which are texture.
func _low() -> bool:
	return TuningConfig.quality_is_low()


func _begin() -> void:
	var count: int = MOTES_LOW if _low() else MOTES
	for i: int in count:
		_mote_x.append(randf_range(-MOTE_SPREAD, MOTE_SPREAD))
		# Staggered so the column reads as a rising CURRENT rather than one puff.
		_mote_delay.append(randf_range(0.0, RISE_TIME * 0.7))

	# THE SIGIL. Laid on the floor under the feet and snapped at full charge — the
	# same release flare a cast gets, which is what ties the reward visually to the
	# thing the player spends their whole time doing.
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.appear(_tint, CIRCLE_RADIUS, RISE_TIME)
	_circle.set_ground(CIRCLE_GROUND_SQUASH)
	_circle.hold(HOLD_TIME, FADE_TIME)
	_circle.snap(1.0)

	_label = Label.new()
	_label.text = "LEVEL %d" % _level
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.90, 1.0))
	# Outlined in the class colour rather than in black: the tint is how you know
	# WHOSE level-up this is when two heroes ding in the same second.
	_label.add_theme_color_override("font_outline_color",
		Color(_tint.r * 0.4, _tint.g * 0.4, _tint.b * 0.4, 1.0))
	_label.add_theme_constant_override("outline_size", 5)
	# Sized and centred by hand — a Label with no container parents itself at its
	# top-left, so without this the text hangs off to the right of the body.
	_label.size = Vector2(120.0, 18.0)
	_label.position = LABEL_OFFSET + Vector2(-60.0, 0.0)
	add_child(_label)

	Sfx.play("ward_raise")
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	# Track the body. A dead or despawned host simply stops moving the effect rather
	# than taking it down — the beat has already been earned.
	if _host != null and is_instance_valid(_host):
		global_position = _host.global_position
	if _label != null:
		# The number drifts up and fades on the back half, so it clears the head
		# instead of sitting on it.
		var p: float = clampf(_t / maxf(_total, 0.01), 0.0, 1.0)
		_label.position = LABEL_OFFSET + Vector2(-60.0, -14.0 * p)
		_label.modulate.a = _fade_alpha()
	queue_redraw()
	if _t >= _total:
		queue_free()


## One alpha curve, shared by the label and every drawn element, so nothing outlives
## anything else by a frame.
func _fade_alpha() -> float:
	if _t < RISE_TIME:
		return clampf(_t / maxf(RISE_TIME, 0.01), 0.0, 1.0)
	if _t < RISE_TIME + HOLD_TIME:
		return 1.0
	return clampf(1.0 - (_t - RISE_TIME - HOLD_TIME) / maxf(FADE_TIME, 0.01), 0.0, 1.0)


func _draw() -> void:
	var a: float = _fade_alpha()
	if a <= 0.001:
		return
	_draw_shockring(a)
	_draw_motes(a)


## A single expanding ring leaving the feet. One, not three: this fires in the
## middle of a wave fight and a stack of rings on a level-up would compete with the
## spell circles that actually mean something.
func _draw_shockring(a: float) -> void:
	if _low():
		return
	var p: float = clampf(_t / maxf(RISE_TIME + HOLD_TIME, 0.01), 0.0, 1.0)
	if p >= 1.0:
		return
	var r: float = lerpf(RING_RADIUS_START, RING_RADIUS_END, ease(p, 0.35))
	var col := Color(_tint.r, _tint.g, _tint.b, a * (1.0 - p) * 0.55)
	# Squashed to the same ellipse the ground circle uses, so the two read as one
	# object on the floor rather than a circle and a sphere.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, CIRCLE_GROUND_SQUASH))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 30, col, 1.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The rising current. Each mote climbs on its own clock and fades as it goes, so
## the column dissolves at the top instead of stopping dead.
func _draw_motes(a: float) -> void:
	for i: int in _mote_x.size():
		var local_t: float = _t - _mote_delay[i]
		if local_t <= 0.0:
			continue
		var p: float = clampf(local_t / maxf(RISE_TIME + HOLD_TIME, 0.01), 0.0, 1.0)
		var y: float = -MOTE_RISE * ease(p, 0.6)
		# Motes converge slightly as they rise — a column that narrows reads as
		# something being drawn INTO the body, which is what a level-up is.
		var x: float = _mote_x[i] * (1.0 - p * 0.55)
		var col := Color(_tint.r, _tint.g, _tint.b, a * (1.0 - p * p))
		draw_circle(Vector2(x, y), maxf(1.8 * (1.0 - p * 0.4), 0.6), col)
