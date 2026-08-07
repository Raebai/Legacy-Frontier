class_name TheCircuit
extends Node2D
## THE CIRCUIT — the STORMCALLER's Tier 3 boss drop, one charge.
##
## THE RULE IT BENDS: **it has no radius.** Every other area spell in the game is
## a shape with an inside and an outside, and the counterplay is to be outside it.
## The Circuit has neither — it finds every hostile body on the stage, orders them
## nearest-first, and walks an arc through all of them in sequence. There is no
## "out of range" and there is no falloff. Distance stops being an answer.
##
## That is the Stormcaller's locked identity — it "*becomes* the lightning" — and
## it is the one thing `ChainBolt` (its Tier 2) deliberately is not: chain bolt has
## a link cap, a hop range, and loses power down the chain. This has none.
##
## THE ANSWER, because everything must have one, and it is a different KIND of
## answer to every other spell in the game: **you cannot dodge it by moving, so
## the counterplay is the clock.** Links resolve one at a time over `length`
## seconds. Being LAST in the order is most of a second of warning, and killing
## the caster, breaking line of sight or simply dying to something else before
## your link arrives all beat it. It is the only spell here answered by tempo
## rather than by positioning.
##
## ⚠ THE ORDER IS FIXED AT THE CAST. A body that walks closer mid-cast does not
## get struck sooner, and the arc still travels to where it actually IS. Re-sorting
## live would make the last link unpredictable, and the whole counterplay is that
## you can count your place in the queue.
##
## UNPLAYTESTED. Every number is a reasoned first guess with the reasoning attached.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.LIGHTNING
var caster_node: Node = null
var spell_tier: int = SpellTier.Tier.ULT

## Hard cap on links, purely so a pathological crowd cannot stall a frame. Well
## above any authored encounter — this is a backstop, not a design limit, and the
## spell's whole claim is that it has no cap you will ever meet.
const MAX_LINKS: int = 16
## How long the arc lingers after the last link, before the node frees itself.
const AFTERGLOW: float = 0.35
const ARC: Color = Color(0.62, 0.86, 1.0)
const FLASH: Color = Color(1.6, 2.0, 2.4)   # HDR — each strike blooms

var _origin_pos: Vector2 = Vector2.ZERO
var _damage: int = 150
var _life: float = 1.4
var _color: Color = ARC
var _elapsed: float = 0.0
var _seed: int = 0
## The queue, fixed at cast: each entry {"node": Node2D, "at": float, "hit": bool}.
var _links: Array[Dictionary] = []
## Where the arc has actually been, for the drawing. Captured as it goes so a dead
## body still leaves its segment of the circuit on screen.
var _path: Array[Vector2] = []


func cataclysm(caster: Node, origin: Vector2, _target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	# ⚠ THE ARC STARTS AT THE CASTER, NOT AT THE AIM POINT. This is the one Tier 3
	# that is not placed — you do not aim a circuit, you close it. `origin` is the
	# caster's own position, which is why this is the only `cataclysm` here that
	# uses it rather than underscoring it.
	_origin_pos = origin
	_damage = spell.damage
	_life = maxf(spell.length, 0.3)
	_color = color
	_seed = randi()
	global_position = Vector2.ZERO
	_build_queue()
	_path.append(_origin_pos)
	SpellSigil.open(self, _origin_pos, color, 1.0, false, Vector2.RIGHT, true, 0.10, 0.45)
	SpellDrops.sfx("lightning", -1.0, 0.06, 0.7)
	Juice.zoom_pull_camera(0.22, _life * 0.8, 0.18, 0.7)
	Juice.shake_camera(7.0)
	queue_redraw()


## Every hostile on the stage, nearest-first, each with the time its link lands.
##
## ⚠ NO RANGE FILTER AT ALL — that absence IS the spell, and it is the one line
## most likely to be "fixed" by somebody adding a sensible radius to it later.
func _build_queue() -> void:
	var bodies: Array[Node2D] = []
	for n: Node in SpellTargets.hostiles(self, StringName(target_group)):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or not (n is Node2D):
			continue
		if n == caster_node:
			continue
		bodies.append(n as Node2D)
	var from: Vector2 = _origin_pos
	bodies.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return from.distance_squared_to(a.global_position) \
			< from.distance_squared_to(b.global_position))
	var n_links: int = mini(bodies.size(), MAX_LINKS)
	for i: int in n_links:
		# Spread the links across the window, with the FIRST one nearly immediate:
		# the nearest body has almost no warning, the furthest has almost all of it,
		# and that gradient is the counterplay being drawn in time instead of space.
		var at: float = _life * (float(i) + 0.35) / float(maxi(n_links, 1))
		_links.append({"node": bodies[i], "at": at, "hit": false})


## How many bodies this circuit will visit. Public so the suite can assert the
## no-range claim — a body placed absurdly far away must still be in the queue.
func link_count() -> int:
	return _links.size()


func _process(delta: float) -> void:
	_elapsed += delta
	for i: int in _links.size():
		var link: Dictionary = _links[i]
		if bool(link["hit"]) or _elapsed < float(link["at"]):
			continue
		link["hit"] = true
		_links[i] = link
		_strike(link["node"])
	if _elapsed >= _life + AFTERGLOW:
		queue_free()
		return
	queue_redraw()


func _strike(who: Variant) -> void:
	if not (who is Node2D) or not is_instance_valid(who) \
			or (who as Node2D).is_queued_for_deletion():
		return
	var n: Node2D = who as Node2D
	var p: Vector2 = n.global_position
	_path.append(p)
	# NO FALLOFF. Link nine hits exactly as hard as link one — see the header.
	SpellTargets.hurt(n, _damage, Color(FLASH.r, FLASH.g, FLASH.b, 1.0))
	if n.has_method("apply_status"):
		n.call("apply_status", element_id)
	if n.has_method("apply_knockback"):
		var away: Vector2 = (p - _origin_pos).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		n.call("apply_knockback", away * SpellTier.push_for_spectacle(
			float(_damage), SpellTier.PUSH_TIER[SpellTier.Tier.ULT]))
	CombatVfx.spawn_burst(get_parent(), p, Color(1.5, 1.9, 2.3, 1.0),
		Color(0.3, 0.6, 0.9, 0.0), 16, 0.34, 90.0, 240.0, 0.8, 2.4, 0.0, 0.0, true)
	SpellDrops.sfx("lightning", -5.0, 0.10, 0.25)
	Juice.on_hit({"shake": 7.0, "zoom": 0.06, "hitstop": 0.03})


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


## A jagged bolt between two points, drawn as a polyline with a deterministic
## wobble — the same shape the rest of the game's lightning uses.
func _bolt(a: Vector2, b: Vector2, salt: int, col: Color, w: float) -> void:
	var seg: Vector2 = b - a
	var n: int = 5
	var perp: Vector2 = seg.orthogonal().normalized()
	var pts := PackedVector2Array()
	pts.append(a)
	for i: int in range(1, n):
		var f: float = float(i) / float(n)
		var jag: float = (_hash01(salt + i * 131 + int(_elapsed * 22.0)) - 0.5) \
			* seg.length() * 0.14
		pts.append(a + seg * f + perp * jag)
	pts.append(b)
	draw_polyline(pts, col, w, true)


func _draw() -> void:
	# The circuit so far: every segment already travelled, held on screen.
	for i: int in range(1, _path.size()):
		var fade: float = clampf(1.0 - (_elapsed - _life) / AFTERGLOW, 0.0, 1.0) \
			if _elapsed > _life else 1.0
		_bolt(_path[i - 1], _path[i], _seed + i * 311,
			Color(_color.r, _color.g, _color.b, 0.55 * fade), 2.2)
		_bolt(_path[i - 1], _path[i], _seed + i * 977,
			Color(FLASH.r, FLASH.g, FLASH.b, 0.85 * fade), 1.0)
	# The live edge, reaching for whoever is next. This is the countdown: you can
	# see the arc turn toward you before it arrives, which is the warning the
	# spell trades for having no radius.
	for i: int in _links.size():
		var link: Dictionary = _links[i]
		if bool(link["hit"]):
			continue
		var who: Variant = link["node"]
		if not (who is Node2D) or not is_instance_valid(who):
			continue
		var at: float = float(link["at"])
		var lead: float = clampf(1.0 - (at - _elapsed) / maxf(_life * 0.5, 0.001), 0.0, 1.0)
		if lead <= 0.0:
			continue
		var from: Vector2 = _path[_path.size() - 1]
		var to: Vector2 = (who as Node2D).global_position
		_bolt(from, from.lerp(to, lead), _seed + i * 61,
			Color(_color.r, _color.g, _color.b, 0.20 + 0.45 * lead), 1.6)
		# A tightening ring on the body whose turn is coming.
		draw_arc(to, lerpf(30.0, 12.0, lead), 0.0, TAU, 20,
			Color(FLASH.r, FLASH.g, FLASH.b, 0.25 + 0.55 * lead), 1.8, true)
		break   # only the NEXT link is shown reaching; the rest wait their turn
