class_name Zanshin
extends Node2D
## ZANSHIN — the SWORDSAINT's Tier 3 boss drop, one charge.
##
## THE RULE IT BENDS: **every area spell in this game gets WEAKER the more people
## are in it**, either by splitting a budget or by staying flat while the danger
## rises. Zanshin is the only one that gets STRONGER. The cut is one cut; letting
## a second body wander into it does not divide it, it sharpens it.
##
## That inversion is the Swordsaint's locked identity — "one cut, guard and
## punish" — expressed as a rule rather than as a bigger number. The whole spell
## is a bet on patience: the stance is drawn the moment you cast, everyone can see
## it, and every second you wait is a second they might walk in and a second they
## might kill you first.
##
## THREE BEATS:
##   STANCE  — the ring is drawn and nothing happens. `length` seconds of nothing,
##             which on a Tier 3 is an eternity and is the point.
##   GATHER  — anything hostile that is inside the ring AT ANY POINT during the
##             stance is marked. Stepping out later does not clear it. So the ring
##             is not a trap you must stand in, it is a promise about the whole
##             window — you were seen.
##   CUT     — one blow, resolved on every mark simultaneously, each for
##             `damage * (1 + PER_EXTRA * (marks - 1))`.
##
## ⚠ THE SCALING IS UNCAPPED BY DESIGN AND THAT IS A REAL RISK. Six bodies is
## 2.5x. If a boss floor ever spawns a crowd inside one ring this will read as
## broken, and `PER_EXTRA` is the one number to walk back — not the base damage,
## which is deliberately the LOWEST of the five new drops so that the multiplier
## has room to be the story.
##
## UNPLAYTESTED. Every number is a reasoned first guess with the reasoning attached.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.ARCANE
var caster_node: Node = null
var spell_tier: int = SpellTier.Tier.ULT

## What each body BEYOND the first adds, as a fraction of the base. 0.5 makes two
## bodies 1.5x and four 2.5x — steep enough that waiting is visibly the play,
## shallow enough that a lone target is not a wasted charge.
const PER_EXTRA: float = 0.5
## How often the ring re-scans for arrivals. Not every frame: a stance that
## sampled at 60 Hz would mark somebody who clipped the rim for one physics step
## on their way past, which is not "you were seen", it is a tripwire.
const SCAN_INTERVAL: float = 0.12
const CUT_TIME: float = 0.34
const STEEL: Color = Color(0.86, 0.93, 1.0)
const FLASH: Color = Color(1.9, 2.0, 2.2)   # HDR — the cut whites out

var _center: Vector2 = Vector2.ZERO
var _radius: float = 240.0
var _damage: int = 120
var _life: float = 2.6
var _color: Color = STEEL
var _elapsed: float = 0.0
var _scan_at: float = 0.0
var _cut: bool = false
## Marked bodies, by instance id so a body cannot be marked twice by re-entering.
var _marked: Dictionary = {}
var _cut_points: Array[Vector2] = []
var _cut_axis: Vector2 = Vector2.RIGHT
var _seed: int = 0


func cataclysm(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_center = target
	_radius = maxf(spell.radius, 30.0)
	_damage = spell.damage
	_life = maxf(spell.length, 0.5)
	_color = color
	_seed = randi()
	global_position = Vector2.ZERO
	# The cut's axis is fixed AT THE CAST, from the caster toward the ring. A cut
	# that re-aimed itself at the end would make the stance a homing missile with
	# extra steps; this way the line you will swing along is decided in front of
	# everyone, at the start.
	if caster is Node2D:
		var d: Vector2 = _center - (caster as Node2D).global_position
		if d.length() > 1.0:
			_cut_axis = d.normalized()
	_gather()
	SpellSigil.open(self, _center, color, maxf(_radius * 1.1, 30.0) / SpellSigil.RADIUS_HEAVY,
		false, _cut_axis, true, 0.14, 0.55)
	SpellDrops.sfx("melee_swing", -4.0, 0.04, 0.5)
	Juice.zoom_pull_camera(0.18, _life * 0.6, 0.24, 0.8)
	queue_redraw()


## Everything hostile inside the ring right now joins the tally. Called on cast and
## then on the scan tick — a body only ever ADDS, never leaves.
func _gather() -> void:
	for n: Node in SpellTargets.in_radius(_center, _radius,
			SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self):
		if n is Node2D:
			_marked[n.get_instance_id()] = n


## The blow this stance is currently worth. Public and pure so the suite can assert
## the inversion — "more bodies is more damage per body" — without staging a cut.
func toll_for(marks: int) -> int:
	if marks <= 0:
		return 0
	return int(round(float(_damage) * (1.0 + PER_EXTRA * float(marks - 1))))


func marked_count() -> int:
	return _marked.size()


func _process(delta: float) -> void:
	_elapsed += delta
	if not _cut:
		_scan_at -= delta
		if _scan_at <= 0.0:
			_scan_at = SCAN_INTERVAL
			_gather()
		if _elapsed >= _life:
			_release()
	elif _elapsed >= _life + CUT_TIME:
		queue_free()
		return
	queue_redraw()


func _release() -> void:
	_cut = true
	var live: Array[Node2D] = []
	for id: Variant in _marked.keys():
		var n: Variant = _marked[id]
		# ⚠ VALIDITY BEFORE `is` — `_marked` holds bodies from cast to release, and dying
		# in between is this spell's normal case, not its edge case.
		if is_instance_valid(n) and n is Node2D and not (n as Node2D).is_queued_for_deletion():
			live.append(n as Node2D)
	# ⚠ PRICED OFF THE LIVE COUNT, not off everything ever marked. A body that died
	# during the stance already paid; counting its ghost would let you inflate the
	# cut by killing the very people it is supposed to land on.
	var toll: int = toll_for(live.size())
	var tint := Color(FLASH.r, FLASH.g, FLASH.b, 1.0)
	for n: Node2D in live:
		_cut_points.append(n.global_position)
		SpellTargets.hurt(n, toll, tint)
		if n.has_method("apply_status"):
			n.call("apply_status", element_id)
	for prop: Node in SpellTargets.in_radius(_center, _radius,
			get_tree().get_nodes_in_group("destructible"), [caster_node], self):
		if prop.has_method("take_damage"):
			prop.call("take_damage", toll)
	CombatVfx.spawn_burst(get_parent(), _center, Color(1.7, 1.8, 2.0, 1.0),
		Color(0.5, 0.6, 0.8, 0.0), 26, 0.42, 120.0, 320.0, 0.6, 2.2, 0.0, 0.0, true)
	SpellDrops.sfx("melee_hit", 0.0, 0.06, 0.4)
	Juice.on_hit({"shake": 14.0 + 3.0 * float(live.size()), "zoom": 0.18,
		"sfx": "ult_unmaking", "sfx_pitch": 0.2, "hitstop": 0.10 + 0.02 * float(live.size())})
	PostProcess.shock(0.6, Juice.world_to_uv(_center))
	Juice.tier_frame(SpellTier.Tier.ULT, _center, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if _cut:
		_draw_cut()
		return
	var t: float = clampf(_elapsed / _life, 0.0, 1.0)
	var n: int = _marked.size()
	# THE STANCE RING. It BRIGHTENS with the tally rather than with time, so the
	# thing the ring is telling you is "how much this is worth now" — the one fact
	# both sides need in order to decide whether to walk in or run.
	var heat: float = clampf(float(n) / 5.0, 0.0, 1.0)
	draw_arc(_center, _radius, 0.0, TAU, 64,
		Color(_color.r, _color.g, _color.b, 0.20 + 0.5 * heat), 1.6 + 2.0 * heat, true)
	# The blade line the cut will travel, drawn faintly across the whole ring from
	# the first frame. Nobody should be surprised by where it lands.
	var perp: Vector2 = _cut_axis.orthogonal()
	draw_line(_center - perp * _radius, _center + perp * _radius,
		Color(_color.r, _color.g, _color.b, 0.10 + 0.30 * t), 1.2, true)
	# One tick per marked body, stacking around the rim: the tally, counted.
	for i: int in n:
		var a: float = -PI * 0.5 + TAU * float(i) / 12.0
		var d: Vector2 = Vector2.from_angle(a)
		draw_line(_center + d * (_radius - 10.0), _center + d * (_radius + 6.0),
			Color(FLASH.r, FLASH.g, FLASH.b, 0.75), 2.4, true)
	# The gathering edge on each mark — a held breath, not a countdown ring.
	for id: Variant in _marked.keys():
		var b: Variant = _marked[id]
		if not is_instance_valid(b) or not (b is Node2D):
			continue
		var p: Vector2 = (b as Node2D).global_position
		draw_line(p - perp * 16.0, p + perp * 16.0,
			Color(_color.r, _color.g, _color.b, 0.25 + 0.5 * t), 1.4, true)


## ONE line across the whole ring, plus a flash on each body it opened.
func _draw_cut() -> void:
	var t: float = clampf((_elapsed - _life) / CUT_TIME, 0.0, 1.0)
	var fade: float = 1.0 - t
	var perp: Vector2 = _cut_axis.orthogonal()
	var reach: float = _radius * (1.0 + 0.25 * t)
	draw_line(_center - perp * reach, _center + perp * reach,
		Color(FLASH.r, FLASH.g, FLASH.b, fade), 6.0 * fade + 0.8, true)
	draw_line(_center - perp * reach, _center + perp * reach,
		Color(1.0, 1.0, 1.0, fade * 0.85), 2.0 * fade + 0.3, true)
	for i: int in _cut_points.size():
		var p: Vector2 = _cut_points[i]
		var spread: float = 30.0 * (0.5 + 0.5 * t)
		draw_line(p - perp * spread, p + perp * spread,
			Color(FLASH.r, FLASH.g, FLASH.b, fade * 0.9), 3.0 * fade + 0.4, true)
