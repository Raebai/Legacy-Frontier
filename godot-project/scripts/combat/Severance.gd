class_name Severance
extends Node2D
## SEVERANCE — the SHADOWBLADE's Tier 3 boss drop, one charge.
##
## THE RULE IT BENDS: **every other damage number in this game is flat.** A bolt
## deals 18 whether it hits a full-health Juggernaut or one on his last pixel.
## Severance is the only thing in the roster whose damage is read off the VICTIM
## instead of off the caster — it deals almost nothing to a healthy body and
## everything to a hurt one. It is an EXECUTE, which is the third verb in the
## Shadowblade's locked identity ("mark, vanish, execute") and the only one the
## class had no spell for.
##
## THREE BEATS:
##   MARK    — every hostile in `radius` is marked, and the mark is drawn ON them
##             for the whole window. Nobody is surprised by this; you can see who
##             is condemned and so can they.
##   WINDOW  — `length` seconds. This is the decision, and it runs BOTH ways: a
##             marked body that heals or is shielded walks away with a scratch,
##             and a marked body that keeps trading dies to the cut. Marking early
##             is safe and weak; marking into a bloodbath is the play.
##   SEVER   — one simultaneous cut on every mark, each priced separately.
##
## ⚠ THE DAMAGE IS MISSING HEALTH, NOT CURRENT HEALTH, and the difference is the
## whole spell. Scaling off CURRENT health makes it a nuke that is best opened
## with; scaling off MISSING health makes it a finisher you have to earn. The
## floor keeps it from being literally nothing against a fresh target, so a
## desperate cast is still a cast.
##
## UNPLAYTESTED. Every number is a reasoned first guess with the reasoning attached.

# ── the five stamped properties. `SpellCaster._stamp` writes these by name, and
# `set()` on an undeclared property is a SILENT no-op — a spectacle missing one is
# unowned, matches no clash row and scans the wrong group, with no error anywhere.
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.SHADOW
var caster_node: Node = null
var spell_tier: int = SpellTier.Tier.ULT

## Damage floor, as a fraction of `spell.damage`, paid even against a full-health
## body. Without it the spell reads as "did nothing" on a bad cast, and a Tier 3
## that can do nothing is a Tier 3 nobody picks up.
const MIN_FRACTION: float = 0.22
## ...and the ceiling, at zero remaining health. The full `spell.damage`.
const MAX_FRACTION: float = 1.0
const MARK_COLOR: Color = Color(0.72, 0.35, 1.0)
const CUT_COLOR: Color = Color(1.5, 0.9, 2.0)     # HDR — the sever blooms
const CUT_TIME: float = 0.30

var _center: Vector2 = Vector2.ZERO
var _radius: float = 210.0
var _damage: int = 200
var _life: float = 2.4
var _color: Color = MARK_COLOR
var _elapsed: float = 0.0
var _severed: bool = false
var _marks: Array[Node2D] = []
## Where each cut is drawn, captured AT the sever so a body that dies to it still
## leaves its cut on screen instead of the line vanishing with the corpse.
var _cuts: Array[Vector2] = []
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
	# Draw in WORLD coordinates. The dispatcher adds this node wherever the arena
	# keeps its children, so without this every mark is offset by that parent.
	global_position = Vector2.ZERO
	_mark()
	SpellSigil.open(self, _center, color, maxf(_radius * 1.2, 30.0) / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.12, 0.5)
	SpellDrops.sfx("shadow_mark", -2.0, 0.05, 0.6)
	Juice.zoom_pull_camera(0.20, _life * 0.5, 0.2, 0.7)
	Juice.shake_camera(6.0)
	queue_redraw()


## Condemn everything hostile inside the ring, once, at cast time.
##
## ⚠ MARKS ARE TAKEN AT THE CAST AND NEVER RE-QUERIED. Re-scanning every frame
## would let a body wander into a spell that has already been paid for, which
## makes the ring a no-go zone rather than a decision — and it would let the
## caster walk the marks onto whoever happened to step in last.
func _mark() -> void:
	for n: Node in SpellTargets.in_radius(_center, _radius,
			SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self):
		if n is Node2D:
			_marks.append(n as Node2D)


func _process(delta: float) -> void:
	_elapsed += delta
	if not _severed and _elapsed >= _life:
		_sever()
	elif _severed and _elapsed >= _life + CUT_TIME:
		queue_free()
		return
	queue_redraw()


## How much a body has coming, priced off ITS OWN missing health.
##
## Public and pure so the suite can assert the curve directly rather than inferring
## it from a staged detonation — the same reason `Chronostasis.banked_total()` is
## public. Returns the flat `damage` when a body will not say how hurt it is.
func toll_for(hp: int, max_hp: int) -> int:
	if max_hp <= 0:
		return _damage
	var missing: float = clampf(1.0 - float(hp) / float(max_hp), 0.0, 1.0)
	return int(round(float(_damage) * lerpf(MIN_FRACTION, MAX_FRACTION, missing)))


func _sever() -> void:
	_severed = true
	var tint := Color(CUT_COLOR.r, CUT_COLOR.g, CUT_COLOR.b, 1.0)
	for n: Node2D in _marks:
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		_cuts.append(n.global_position)
		var hp: Variant = n.get(&"hp")
		var mx: Variant = n.get(&"max_hp")
		var toll: int = _damage
		if hp != null and mx != null:
			toll = toll_for(int(hp), int(mx))
		SpellTargets.hurt(n, toll, tint)
		if n.has_method("apply_status"):
			n.call("apply_status", element_id)
	CombatVfx.spawn_burst(get_parent(), _center, Color(1.4, 0.8, 2.0, 1.0),
		Color(0.08, 0.0, 0.14, 0.0), 32, 0.5, 60.0, 260.0, 1.2, 3.6, 0.0, 0.0, true)
	Juice.on_hit({"shake": 18.0, "zoom": 0.16, "sfx": "ult_unmaking", "sfx_pitch": 0.12,
		"hitstop": 0.12})
	PostProcess.shock(0.7, Juice.world_to_uv(_center))
	Juice.tier_frame(SpellTier.Tier.ULT, _center, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if _severed:
		_draw_cuts()
		return
	var t: float = clampf(_elapsed / _life, 0.0, 1.0)
	# The condemned ring: thin, and it does NOT tighten. A ring that shrank would
	# read as an incoming blast; this one is a boundary that was already decided.
	draw_arc(_center, _radius, 0.0, TAU, 56,
		Color(_color.r, _color.g, _color.b, 0.22 + 0.18 * t), 1.8, true)
	for i: int in _marks.size():
		var n: Node2D = _marks[i]
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var p: Vector2 = n.global_position
		# THE MARK, and it TIGHTENS on each body rather than on the ring — the
		# countdown belongs to the person it is counting down for.
		var spin: float = _elapsed * 2.2 + _hash01(_seed + i * 97) * TAU
		var rr: float = lerpf(26.0, 11.0, t)
		draw_arc(p, rr, spin, spin + TAU * 0.78, 20,
			Color(CUT_COLOR.r, CUT_COLOR.g, CUT_COLOR.b, 0.5 + 0.4 * t), 2.0, true)
		draw_arc(p, rr * 0.62, -spin * 1.4, -spin * 1.4 + TAU * 0.6, 16,
			Color(_color.r, _color.g, _color.b, 0.4 + 0.4 * t), 1.5, true)
		# A tally of how close it is, drawn as closing ticks so the read is
		# "something is being counted" and not "a decorative swirl".
		for k: int in 4:
			var a: float = spin + TAU * float(k) / 4.0
			var d: Vector2 = Vector2.from_angle(a)
			draw_line(p + d * rr * 1.5, p + d * (rr * 1.5 + 5.0 * (1.0 - t)),
				Color(CUT_COLOR.r, CUT_COLOR.g, CUT_COLOR.b, 0.35 + 0.5 * t), 1.6, true)


## One flash-cut through every mark at once. Drawn from the captured positions, so
## a body that died to the sever still shows the blow that killed it.
func _draw_cuts() -> void:
	var t: float = clampf((_elapsed - _life) / CUT_TIME, 0.0, 1.0)
	var fade: float = 1.0 - t
	for i: int in _cuts.size():
		var p: Vector2 = _cuts[i]
		var a: float = _hash01(_seed + i * 733) * PI
		var d: Vector2 = Vector2.from_angle(a)
		var reach: float = 44.0 * (0.4 + 0.6 * t)
		draw_line(p - d * reach, p + d * reach,
			Color(CUT_COLOR.r, CUT_COLOR.g, CUT_COLOR.b, fade), 3.4 * fade + 0.6, true)
		draw_line(p - d * reach * 0.5, p + d * reach * 0.5,
			Color(1.0, 1.0, 1.0, fade * 0.9), 1.4 * fade + 0.4, true)
