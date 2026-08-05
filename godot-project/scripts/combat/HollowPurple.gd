class_name HollowPurple
extends Node2D
## THE HEADLINER. Two beams of OPPOSING elements fuse, and a magic circle opens
## between them and EATS them both.
##
## ⚠ WHERE IT STAGES IS NOT THIS FILE'S DECISION. `begin()` is handed a point and
## an axis and draws what it is told, because the SAME spectacle serves two
## authored rows (see ReactionTable):
##   SELF-COMBO (priority 100, the headline path) — one caster double-taps two
##     opposing spells; the gate opens a fixed distance in FRONT of them and the
##     annihilation fires along their aim. There is no crossing to stage at:
##     both beams left the same muzzle.
##   CROSSING (priority 95, the rarer surprise) — two SEPARATE casters' beams
##     genuinely overlap; the gate opens at the geometric crossing and fires
##     along the two beams' angle bisector.
## Reading this file as if the crossing were the only case is how the demo path
## drifted into staging two ownerless beams from two origins — a pair that
## matches neither row, so nothing was ever built. `_axis` and `_p` below are the
## caller's answer to both questions and the only geometry that matters here.
##
## Three beats:
##   INTAKE    (0.00 - 0.60)  a magic circle blooms at the fusion point —
##                            ORIENTED ALONG `_axis`, facing where the blast will
##                            go, so the shape is readable a beat early — and both
##                            beams stream INTO it — the far length past the
##                            circle is swallowed first, then each beam is drawn
##                            in from its muzzle until there is nothing left.
##                            The absorption is the whole read: the circle is
##                            the thing that eats your spell.
##   HELD      (0.60 - 0.78)  the intake finishes. The circle turns alone over a
##                            black core with a hairline white horizon, the
##                            screen dimmed around it, and NO audio. The game is
##                            loud constantly; 180 ms of nothing is the loudest
##                            thing available, and it costs zero assets.
##   DISCHARGE (0.78 - 1.70)  the annihilation fires OUT of the circle, along
##                            `_axis` — the caster's aim on a self-combo, the two
##                            beams' angle bisector on a crossing — so either way
##                            it reads as their combined output and a player aims
##                            it by choosing their angle. Plus a radial ring and a
##                            near-black erased scar where the ground was.
##
## THE COLOUR IS COMPUTED, NOT AUTHORED. The two element colours are summed as
## light and renormalised to HDR, so "red + blue -> purple" is literal in the
## code and each of the four opposing pairs yields a different result — the
## circle, the lance and the ring are all tinted from that one sum. Nothing here
## hardcodes purple.
##
## The circle is a plain MagicCircle, the same sigil the whole kit uses for cast
## windups, so the biggest moment in the game speaks the game's own visual
## language instead of inventing a one-off ring.
##
## Drawn in WORLD coordinates from `_p` — this node never moves off the arena
## origin, exactly like every other spectacle (see SpellReactor's trap note).

const INTAKE_END: float = 0.60
const HELD_END: float = 0.78
const DONE: float = 1.70
## Fraction of the intake spent swallowing the length PAST the circle, before
## each beam starts being drawn in from its muzzle.
const FAR_EATEN_AT: float = 0.42

const KNOCKBACK: float = 900.0     # far above BoulderHurl's 460 — this throws you
const DAMAGE_SCALE: float = 1.6    # applied to the two beams' summed damage
const LANCE_WIDTH_SCALE: float = 2.2
const CIRCLE_RADIUS: float = 135.0
## Foreshortening of the sigil's face about the fire axis. Must match the value
## handed to MagicCircle.set_orientation or the vortex will not sit on the ring.
const CIRCLE_EDGE_THICK: float = 0.20
## Both arms wind the same way: one vortex, not two spirals fighting.
const SPIRAL_SIGN: float = 1.0
const DEBRIS_COUNT: int = 26
const DEBRIS_REACH: float = 420.0
const STREAM_DASHES: int = 7

var _p: Vector2 = Vector2.ZERO
var _a: Dictionary = {}
var _b: Dictionary = {}
var _axis: Vector2 = Vector2.RIGHT
var _lance_len: float = 600.0
var _lance_w: float = 60.0
var _radius: float = 190.0
var _damage: int = 150
var _groups: Array[String] = []
## BOTH parent beams' casters. Unlike every other spectacle in the game this one has
## no single owner — it is a FUSION — so self-exclusion is a list rather than a
## `caster_node`, and `SpellTargets.owner_of()` deliberately cannot answer for it.
##
## It matters most in the SELF-COMBO row, which is the headline case: the circle
## opens `SELF_COMBO_OFFSET` in front of its own caster and the annihilation sphere
## is `_radius` (>= 120) wide, so with friendly fire pointing both beams at the
## shared `mortal` group, fusing two of your own beams would erase YOU. The
## cross-caster row is spared for the same reason both duellists survive their own
## clash: you are not killed by the collision of your power with someone else's.
var _casters: Array = []

var _core: Color = Color(1.7, 1.7, 1.7)     # the summed, renormalised light
var _body: Color = Color(0.8, 0.6, 1.0)     # the same sum at display range
var _hue_a: Color = Color.WHITE
var _hue_b: Color = Color.WHITE

var _t: float = 0.0
var _did_held: bool = false
var _did_discharge: bool = false
var _circle: MagicCircle = null
var _veil: ColorRect = null


## Stage the fusion at `point`, firing along `axis`. The caller decides both:
## a SELF-COMBO stages in front of its caster and fires along their aim; a
## cross-caster crossing stages at SpellGeometry.meeting_point and fires along
## the bisector. Either way this node just draws what it is told, which is why
## the same spectacle serves both rows. `a`/`b` are beam descriptors built by
## ReactionOutcomes._beam_data; `rule` is the authored ReactionTable row.
func begin(point: Vector2, axis: Vector2, a: Dictionary, b: Dictionary, rule: Dictionary) -> void:
	_p = point
	_axis = axis.normalized() if axis != Vector2.ZERO else Vector2.RIGHT
	_a = a
	_b = b
	z_index = 90
	global_position = Vector2.ZERO
	_radius = maxf(float(rule.get("radius", 190.0)), 120.0)
	_damage = maxi(int((int(a["damage"]) + int(b["damage"])) * DAMAGE_SCALE), int(rule.get("damage", 0)))
	_groups = _target_groups(String(a["group"]), String(b["group"]))
	_casters = _collect_casters(a, b)
	_compute_colour(int(a["element"]), int(b["element"]))
	_lance_len = maxf(
		(a["from"] as Vector2).distance_to(a["to"] as Vector2),
		(b["from"] as Vector2).distance_to(b["to"] as Vector2))
	_lance_w = (float(a["width"]) + float(b["width"])) * 0.5 * LANCE_WIDTH_SCALE
	_build_veil()
	# The real beams hand over here: from this frame the intake owns their
	# geometry and draws them being swallowed. They are freed WITHOUT their
	# normal end-of-life beat — they did not land, they were eaten.
	for d: Dictionary in [_a, _b]:
		var n: Node = d.get("node")
		if n != null and is_instance_valid(n) and n.has_method(&"reaction_consume"):
			n.call(&"reaction_consume")
	_open_circle()
	queue_redraw()


## ADDITIVE LIGHT MIXING, then renormalised so the core clears the bloom
## threshold. FIRE (1.0, 0.45, 0.15) + ICE (0.5, 0.85, 1.0) = (1.5, 1.3, 1.15):
## a searing near-white violet. SHADOW + HOLY and ARCANE + WIND land visibly
## violet; LIGHTNING + EARTH lands gold. Four pairs, four annihilations, one
## line of maths — and the parent hues are kept alongside so the ancestry stays
## legible on the rims.
func _compute_colour(elem_a: int, elem_b: int) -> void:
	_hue_a = Elements.color(elem_a)
	_hue_b = Elements.color(elem_b)
	var summed := Color(_hue_a.r + _hue_b.r, _hue_a.g + _hue_b.g, _hue_a.b + _hue_b.b, 1.0)
	var peak: float = maxf(summed.r, maxf(summed.g, summed.b))
	var s: float = Elements.EMISSIVE_PEAK * 1.35 / maxf(peak, 0.001)
	_core = Color(summed.r * s, summed.g * s, summed.b * s, 1.0)
	# Display-range companion for the wide, low-alpha bands: the same mix at
	# normal brightness, so the body reads as the blend and only the core blooms.
	var d: float = 1.0 / maxf(peak, 0.001)
	_body = Color(summed.r * d, summed.g * d, summed.b * d, 1.0)


## Everything the annihilation should be allowed to hit: both beams' damage
## groups (a boss beam crossing the hero's makes both sides fair game) plus
## destructibles.
func _target_groups(ga: String, gb: String) -> Array[String]:
	var out: Array[String] = []
	for g: String in [ga, gb, "destructible"]:
		if g != "" and not out.has(g):
			out.append(g)
	return out


## Whoever threw the two beams, deduped. Read through `SpellTargets.owner_of`, which
## already knows all four spellings this codebase uses for "the caster".
## `ReactionOutcomes._beam_data` puts the live beam node under `"node"`, so this is
## available for both rows without changing that contract.
func _collect_casters(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for d: Dictionary in [a, b]:
		var owner_node: Object = SpellTargets.owner_of(d.get("node") as Object)
		if owner_node != null and not out.has(owner_node):
			out.append(owner_node)
	return out


# ------------------------------------------------------------ beats

## Beat one: the circle opens at `_p`, ORIENTED ALONG `_axis` — the same axis the
## annihilation will fire out along. A magic circle in this game stands
## perpendicular to the direction its magic travels, so you can read where an
## attack is pointed off the sigil alone; here that means the shape is legible a
## full beat before the discharge, and the opponent gets that beat.
##
## MagicCircle already models this: set_orientation(true, axis) rotates the node
## to the axis and draws the ring as an ellipse foreshortened about it (narrow
## along the fire direction, full radius across it), which is exactly the
## edge-on portal read. Same call BeamSpell makes for its muzzle sigil — nothing
## in the shared circle needed changing. A little thicker than a beam muzzle
## (0.30 vs 0.14) so it reads as a portal with depth rather than a slit.
func _open_circle() -> void:
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.position = _p            # this node sits at the origin, so local == world
	# Lifted above display range so the sigil blooms instead of sitting flat.
	_circle.appear(Color(_body.r * 1.5, _body.g * 1.5, _body.b * 1.5, 1.0), CIRCLE_RADIUS, 0.20)
	_circle.set_orientation(true, _axis, CIRCLE_EDGE_THICK)
	# In FRONT of the beams so the gate visibly swallows them, rather than being
	# occluded by the very things it is eating.
	_circle.z_index = 2
	Juice.shake_camera(11.0)
	PostProcess.shock(0.75, Juice.world_to_uv(_p))
	# Wider than StarConvergence's 0.22 — the current widest pull in the game —
	# and started HERE so the frame is already open when the beams go in.
	Juice.zoom_pull_camera(0.28, 1.15, 0.18, 0.6)
	Sfx.play("hollow_intake", 1.0, 0.0, 0.55)  # a deep gather, not a hit


func _held() -> void:
	_did_held = true
	# The sigil has been accelerating all through the intake; here it STOPS
	# dead. Freezing its _process pins the spin, the breathing and the grow
	# tween in one call without touching the shared MagicCircle script. That
	# sudden stillness is the anticipation — the discharge then reads as
	# something released rather than something continuing.
	if _circle != null and is_instance_valid(_circle):
		_circle.set_process(false)
	# Otherwise deliberately empty. No sfx, no shake, no camera move: the
	# negative space IS the beat.


func _discharge() -> void:
	_did_discharge = true
	_apply_damage()
	_scar()
	if _circle != null and is_instance_valid(_circle):
		_circle.set_process(true)
		_circle.vanish(0.30)   # blooms outward as the lance leaves it
	# NOTE: still deliberately NOT the WHITE blow-out. Rendered against this, a
	# full-screen white speed-line burst completely buries the lance, and the
	# lance IS the payoff.
	#
	# The BLACK cut is the opposite, and it is this spell's own language handed
	# back to it: the most striking beat this effect already has is a black core
	# with a hairline white horizon, which is exactly what
	# `ImpactFrame.Style.SILHOUETTE` draws. So the discharge now drops the screen
	# out for 0.13 s with the lance lit against it. `lines: false` — the lance is
	# the only line allowed on this frame.
	Juice.epic_moment({
		"strength": 1.35, "shake": 22.0, "at": _p, "sfx": "blast",
		"frame": true, "style": ImpactFrame.Style.SILHOUETTE, "lines": false,
	})
	PostProcess.shock(1.4, Juice.world_to_uv(_p))
	Sfx.play("hollow_erase", -6.0, 0.0, 0.62)  # erasure, not a laser


func _process(delta: float) -> void:
	_t += delta
	# Drive the sigil FASTER as it eats, by feeding it extra phase from outside.
	# MagicCircle is shared with every cast in the game, so its spin rate is not
	# something to edit — but its phase is just an accumulator, and adding to it
	# here accelerates this one instance and nothing else.
	if _circle != null and is_instance_valid(_circle) and _t < INTAKE_END:
		var k: float = _t / INTAKE_END
		_circle.set(&"_phase", float(_circle.get(&"_phase")) + delta * (1.5 + 9.0 * k))
	if not _did_held and _t >= INTAKE_END:
		_held()
	if not _did_discharge and _t >= HELD_END:
		_discharge()
	if _t >= DONE:
		queue_free()
		return
	_update_veil()
	queue_redraw()


# ------------------------------------------------------------ damage

func _apply_damage() -> void:
	var reach: float = _lance_len
	var back: float = reach * 0.42
	var half: float = _lance_w * 0.6
	var origin: Vector2 = _p - _axis * back
	var hit: Dictionary = {}
	# Pre-seeding the dedupe map with both casters is the cheapest possible
	# self-exclusion here and reuses machinery this loop already has: `_hurt()` skips
	# anything already in `hit`, so a caster is "already hit" before the scan starts
	# and can be reached by neither the radial pass nor the lance corridor.
	for c: Object in _casters:
		if c != null and is_instance_valid(c):
			hit[c.get_instance_id()] = true
	for group: String in _groups:
		var nodes: Array = get_tree().get_nodes_in_group(group)
		# Radial: everything inside the annihilation sphere.
		for n: Node in nodes:
			if not n is Node2D:
				continue
			if (n as Node2D).global_position.distance_to(_p) <= _radius:
				_hurt(n, hit, ((n as Node2D).global_position - _p).normalized())
		# Corridor: the lance. Reuses BeamSpell's already-tested pure line test,
		# so the lance needs no new geometry code.
		for n: Node in BeamSpell.targets_on_beam(origin, _axis, back + reach, half, nodes):
			_hurt(n, hit, _axis)
	# Anything hostile in flight is simply erased.
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if proj is Node2D and (proj as Node2D).global_position.distance_to(_p) <= _radius:
			if proj.has_method(&"consume"):
				proj.call(&"consume")


func _hurt(n: Node, hit: Dictionary, dir: Vector2) -> void:
	var id: int = n.get_instance_id()
	if hit.has(id):
		return
	hit[id] = true
	if n.has_method(&"take_damage"):
		n.call(&"take_damage", _damage)
	if n.has_method(&"apply_knockback"):
		var d: Vector2 = dir if dir != Vector2.ZERO else Vector2.RIGHT
		n.call(&"apply_knockback", d * KNOCKBACK)


## The ground is GONE, not burned: a near-black erasure along the lance.
func _scar() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var erased := Color(0.015, 0.01, 0.03, 0.72)
	ScorchDecal.spawn(parent, _p, _lance_w * 1.6, "scorch", erased, 16.0)
	for i: int in 7:
		var t: float = (float(i) + 1.0) / 8.0
		var span: float = _lance_len * 0.55
		var at: Vector2 = _p + _axis * (t * span - span * 0.28)
		ScorchDecal.spawn(parent, at, _lance_w * (1.1 - 0.5 * t), "scorch", erased, 14.0)


# ------------------------------------------------------------ the screen veil

## A full-screen dim that peaks through the HELD beat. The black core only reads
## as negative space if the rest of the frame gets out of its way.
func _build_veil() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 7  # above the world, below the post-process grade (8) and HUD
	add_child(layer)
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.color = Color(0.015, 0.0, 0.03, 0.0)
	layer.add_child(_veil)


func _update_veil() -> void:
	if _veil == null:
		return
	var a: float = 0.0
	if _t < INTAKE_END:
		var k: float = _t / INTAKE_END
		a = lerpf(0.0, 0.60, k * k)
	elif _t < HELD_END:
		var k2: float = (_t - INTAKE_END) / (HELD_END - INTAKE_END)
		a = lerpf(0.60, 0.78, k2)
	else:
		var k3: float = clampf((_t - HELD_END) / 0.22, 0.0, 1.0)
		a = lerpf(0.78, 0.0, k3)
	_veil.color = Color(0.015, 0.0, 0.03, a)


# ------------------------------------------------------------ draw

func _draw() -> void:
	if _t < INTAKE_END:
		_draw_intake(_t / INTAKE_END)
	elif _t < HELD_END:
		_draw_held((_t - INTAKE_END) / (HELD_END - INTAKE_END))
	else:
		_draw_discharge((_t - HELD_END) / (DONE - HELD_END))


## Beat one. Both beams are wound INTO the circle: what is left of each beam runs
## straight until it reaches the circle's face, then spirals around it, tighter
## and faster as it goes, and vanishes into the middle.
func _draw_intake(k: float) -> void:
	_draw_inward_debris(k)
	_draw_absorbed_beam(_a, k)
	_draw_absorbed_beam(_b, k)
	# The mouth: the two elements have become one thing by the time they get
	# here, which is the whole idea of the reaction made literal.
	var gather: float = k * k
	draw_circle(_p, lerpf(10.0, 34.0, gather), Color(_body.r, _body.g, _body.b, 0.35 + 0.3 * gather), true, -1.0, true)
	draw_circle(_p, lerpf(4.0, 18.0, gather), Color(_core.r, _core.g, _core.b, 0.5 + 0.5 * gather), true, -1.0, true)


## ONE beam being eaten, in three overlapping reads:
##
##  1. the length PAST the circle is drawn back to it (the beam stops passing
##     through and starts being caught),
##  2. the remainder is pulled in from the MUZZLE end, so the beam visibly
##     shortens rather than just fading,
##  3. everything that reaches the circle's face SPIRALS — angle accelerating as
##     the radius closes, several wraps before it disappears into the centre.
##
## Both beams wind the same way (SPIRAL_SIGN), so it reads as one vortex rather
## than two spirals fighting. Each beam keeps its own element colour out at the
## rim and only lerps into the computed blend at the middle — you watch red and
## blue become one thing.
func _draw_absorbed_beam(bd: Dictionary, k: float) -> void:
	if bd.is_empty():
		return
	var from: Vector2 = bd["from"]
	var to: Vector2 = bd["to"]
	var dir: Vector2 = (to - from).normalized()
	var far: float = (to - _p).dot(dir)          # length overshooting past the gate
	var w: float = float(bd["width"]) * (1.0 - 0.32 * k)
	var col: Color = Elements.color(int(bd["element"]))
	var core: Color = Elements.emissive(int(bd["element"]))
	# The vortex closes down to nothing in the last quarter of the intake.
	var r_entry: float = CIRCLE_RADIUS * 0.95 * (1.0 - smoothstep(0.74, 1.0, k))
	var start: Vector2 = from
	var straight_end: Vector2 = _p - dir * r_entry
	var spiralling: bool = k >= FAR_EATEN_AT
	if not spiralling:
		# Still passing through: the overshoot is being drawn back to the circle.
		var q: float = k / FAR_EATEN_AT
		straight_end = _p + dir * (far * (1.0 - q * q))
	else:
		var q2: float = (k - FAR_EATEN_AT) / (1.0 - FAR_EATEN_AT)
		start = from.lerp(_p, q2 * q2 * (3.0 - 2.0 * q2))
	if (straight_end - start).dot(dir) > 1.0:
		draw_line(start, straight_end, Color(col.r, col.g, col.b, 0.24), w * 1.7, true)
		draw_line(start, straight_end, Color(col.r, col.g, col.b, 0.62), w * 0.9, true)
		draw_line(start, straight_end, Color(core.r, core.g, core.b, 0.92), w * 0.34, true)
		# Bright dashes running down what is left, toward the circle, so the
		# direction of flow is unambiguous even in a still frame.
		var span: float = (straight_end - start).length()
		for i: int in STREAM_DASHES:
			var t: float = fposmod(float(i) / float(STREAM_DASHES) + _t * 1.8, 1.0)
			var head: Vector2 = start.lerp(straight_end, t)
			var tail: Vector2 = head - dir * minf(span * 0.13, 70.0)
			var a: float = sin(t * PI)
			draw_line(tail, head, Color(core.r, core.g, core.b, 0.85 * a), w * 0.6 * a, true)
	if spiralling and r_entry > 2.0:
		_draw_vortex_arm(dir, r_entry, w, col, core, k)


## The spiral arm: sampled from the circle's rim inward. `u` runs 0 (rim, exactly
## where the straight beam ended, so the two join without a seam) to 1 (centre).
##
## `squash` is why this is drawn as an ellipse and not a circle: the sigil stands
## EDGE-ON along `_axis`, so its face is foreshortened, and energy orbiting
## it has to pass visibly in front of and behind the ring. At the rim the arm is
## round (it has to meet the incoming beam) and it flattens onto the portal's
## face as it winds in.
func _draw_vortex_arm(dir: Vector2, r_entry: float, w: float,
		col: Color, core: Color, k: float) -> void:
	var perp: Vector2 = _axis.orthogonal()
	var inbound: Vector2 = -dir
	var theta0: float = atan2(inbound.dot(perp), inbound.dot(_axis))
	# The whole vortex turns, and turns FASTER the more it has eaten.
	var spin: float = _t * (2.2 + 7.5 * k)
	var turns: float = lerpf(1.6, 3.4, k)
	var pts: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var steps: int = 46
	for i: int in steps + 1:
		var u: float = float(i) / float(steps)
		var r: float = r_entry * (1.0 - u)
		# Angle accelerates as the radius closes — wound tighter and tighter.
		# The spin is weighted by `u` so the arm's ROOT stays pinned to the
		# incoming beam — without that the whole arm rotates away from the beam
		# it is supposed to be swallowing and the two visibly detach.
		var th: float = theta0 + SPIRAL_SIGN * (turns * TAU * pow(u, 1.35)) + spin * pow(u, 0.6)
		var squash: float = lerpf(1.0, CIRCLE_EDGE_THICK, smoothstep(0.0, 0.4, u))
		pts.append(_p + _axis * (cos(th) * r * squash) + perp * (sin(th) * r))
		# Element out at the rim, the computed blend at the heart.
		# Held at the element's own colour for most of the way in and only
		# blended at the heart, so you can watch red and blue become one thing
		# instead of both turning to soup on the way round.
		cols.append(col.lerp(_body, smoothstep(0.42, 1.0, u)))
	# Three passes: a soft halo, the coloured arm, and a hot filament — the same
	# band stack the beam itself uses, so the energy keeps its identity while it
	# is being wound in.
	for pass_i: int in 3:
		var scale: float = [1.7, 0.85, 0.3][pass_i]
		var alpha: float = [0.20, 0.6, 0.95][pass_i]
		for i: int in steps:
			var u: float = float(i) / float(steps)
			var c: Color = cols[i] if pass_i < 2 else core.lerp(_core, smoothstep(0.42, 1.0, u))
			draw_line(pts[i], pts[i + 1],
				Color(c.r, c.g, c.b, alpha * (1.0 - u * 0.35)),
				maxf(w * scale * (1.0 - u * 0.55), 1.0), true)


## Loose light dragged in from everywhere in reach — during the intake it is
## being pulled toward the circle with the beams.
func _draw_inward_debris(k: float) -> void:
	for i: int in DEBRIS_COUNT:
		var h: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var h2: float = fposmod(sin(float(i) * 78.233) * 24634.6345, 1.0)
		var ang: float = h * TAU
		var r: float = lerpf(DEBRIS_REACH * (0.35 + 0.65 * h2), 8.0, k * k)
		var dir: Vector2 = Vector2.from_angle(ang)
		var p: Vector2 = _p + dir * r
		var col: Color = _hue_a if i % 2 == 0 else _hue_b
		# The streak trails OUTWARD behind the mote and the bright head sits on
		# the inner end, so the direction of travel is toward the circle.
		draw_line(p, p + dir * (8.0 + 22.0 * k),
			Color(col.r, col.g, col.b, 0.35 * k), 1.0 + 1.4 * k, true)
		draw_circle(p, 1.2 + 2.2 * k, Color(col.r, col.g, col.b, 0.85 * k), true, -1.0, true)


## Beat two. The beams are gone. The circle turns over a black core with a
## hairline white horizon, and the screen has gone quiet around it.
func _draw_held(k: float) -> void:
	var r: float = lerpf(48.0, 64.0, k)
	draw_circle(_p, r * 2.1, Color(_body.r, _body.g, _body.b, 0.07 * (1.0 - k)), true, -1.0, true)
	draw_circle(_p, r, Color(0.0, 0.0, 0.0, 1.0), true, -1.0, true)
	draw_arc(_p, r + 1.5, 0.0, TAU, 72, Color(1.0, 1.0, 1.0, 0.9), 1.3, true)
	draw_arc(_p, r * 1.35, 0.0, TAU, 72, Color(1.0, 1.0, 1.0, 0.12 * (1.0 - k)), 1.0, true)


## Beat three. It comes OUT of the circle: a lance along `_axis`, a radial ring,
## and the two parent hues bleeding along the rims.
func _draw_discharge(k: float) -> void:
	var burst: float = clampf(k * 7.0, 0.0, 1.0)          # 0 -> 1 in the first ~70 ms
	# Held at full for the first third of the beat, then eased out. An
	# annihilation that starts fading the instant it appears reads as a puff.
	var amp: float = clampf(1.0 - maxf(k - 0.32, 0.0) / 0.68, 0.0, 1.0)
	amp = amp * amp * (3.0 - 2.0 * amp)
	var perp: Vector2 = _axis.orthogonal()
	# Opening flash. ⚠ IT KEEPS ITS PUNCH AND LOSES ITS MIDDLE. As written this went
	# to a 340 px near-white disc at (1.9, 1.9, 1.9) — on a 683 px viewport that is
	# wider than the screen, and the alpha only reaches zero at the very end, so the
	# WHOLE expansion was a white blob with the lance and both fighters inside it.
	# Same fault as `BlastSpell`'s flash and the two before it: an HDR fill scaled by
	# an effect's full reach.
	#
	# The fix keeps frame one — 52 px at near-full alpha IS the crack of the thing
	# opening — and takes the tail off: a squared fade means it is gone by the time it
	# would have been big, and the reach is capped where the lance's own rims take
	# over the read.
	if burst < 1.0:
		var fade: float = (1.0 - burst) * (1.0 - burst)
		draw_circle(_p, lerpf(52.0, 168.0, burst),
			Color(1.6, 1.55, 1.7, 0.9 * fade), true, -1.0, true)
	# THE LANCE. An ERASURE with blazing rims, not a glowing bar: a tapered
	# silhouette (widest at the circle, a point at each end), a near-black
	# interior, and the light living on its edges.
	var reach: float = _lance_len * burst
	var back: float = reach * 0.42
	var tip: Vector2 = _p + _axis * reach
	var tail: Vector2 = _p - _axis * back
	var w: float = _lance_w * (0.6 + 0.4 * amp)
	# The halo is a WIDER COPY of the silhouette, not a thick straight line — a
	# fat draw_line spans the screen as a hard-edged rectangle and reads as a
	# stripe painted over the arena rather than as glow around a lance.
	draw_colored_polygon(_lance_poly(tail, tip, w * 1.25),
		Color(_body.r, _body.g, _body.b, 0.16 * amp))
	draw_colored_polygon(_lance_poly(tail, tip, w * 0.5),
		Color(_body.r, _body.g, _body.b, 0.55 * amp))
	draw_colored_polygon(_lance_poly(tail, tip, w * 0.19),
		Color(0.0, 0.0, 0.0, 0.9 * amp))
	# The two edges of the erasure, burning.
	for side: float in [-1.0, 1.0]:
		var off: Vector2 = perp * side * w * 0.19
		draw_polyline(PackedVector2Array([tail, _p + off, tip]),
			Color(_core.r, _core.g, _core.b, 0.98 * amp), maxf(w * 0.09, 2.0), true)
	# Rim rails in the PARENT hues, hugging the silhouette.
	for pair: Array in [[1.0, _hue_a], [-1.0, _hue_b]]:
		var s: float = pair[0]
		var hue: Color = pair[1]
		draw_polyline(PackedVector2Array([tail, _p + perp * s * w * 0.52, tip]),
			Color(hue.r, hue.g, hue.b, 0.9 * amp), maxf(w * 0.1, 2.0), true)
	# THE RING.
	var rk: float = clampf(k * 2.6, 0.0, 1.0)
	var rr: float = _radius * lerpf(0.12, 1.45, rk * (2.0 - rk))
	draw_arc(_p, rr, 0.0, TAU, 84, Color(_body.r, _body.g, _body.b, 0.22 * amp), lerpf(30.0, 5.0, rk), true)
	draw_arc(_p, rr, 0.0, TAU, 84, Color(_core.r, _core.g, _core.b, 0.9 * amp), lerpf(8.0, 1.5, rk), true)
	# A second, faster ring so the blast has a leading edge instead of one hoop.
	var rk2: float = clampf(k * 4.4, 0.0, 1.0)
	if rk2 < 1.0:
		var mix: Color = _hue_a.lerp(_hue_b, 0.5)
		draw_arc(_p, _radius * lerpf(0.1, 1.9, rk2), 0.0, TAU, 84,
			Color(mix.r, mix.g, mix.b, 0.5 * (1.0 - rk2)), lerpf(14.0, 2.0, rk2), true)
	# The erasure at the heart, shrinking as the light takes over.
	var hole: float = lerpf(46.0, 0.0, clampf(k * 3.0, 0.0, 1.0))
	if hole > 0.5:
		draw_circle(_p, hole, Color(0.0, 0.0, 0.0, 0.9), true, -1.0, true)
		draw_arc(_p, hole + 1.2, 0.0, TAU, 60, Color(1.0, 1.0, 1.0, 0.55), 1.2, true)
	draw_circle(_p, 26.0 * amp, Color(_core.r, _core.g, _core.b, amp), true, -1.0, true)


## The lance silhouette: a point at the tail, `half` wide at the circle, a point
## at the tip. Convex, so draw_colored_polygon handles it directly.
func _lance_poly(tail: Vector2, tip: Vector2, half: float) -> PackedVector2Array:
	var perp: Vector2 = _axis.orthogonal()
	return PackedVector2Array([tail, _p + perp * half, tip, _p - perp * half])
