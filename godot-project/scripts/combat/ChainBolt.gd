class_name ChainBolt
extends Node2D
## CHAIN LIGHTNING (Stormcaller) / CHAIN-SMITE (Cleric, holy tint) — a jagged bolt
## that LEAPS enemy-to-enemy, up to N hops, shocking each with damage falloff.
## Nothing like a straight beam: it forks around the arena, hitting a whole chain.
## Instantiate .new(), add under the arena, call chain(). Damage/target order is a
## pure static selector (build_chain) — headless-testable.
##
## NO SEEK on the opening strike (magic-overhaul rule 1): the bolt goes exactly
## where you point. Target 1 must lie inside a narrow CORRIDOR around the aim ray
## — aim wide and the bolt rips into empty air and fizzles, no free retarget. The
## arcs AFTER a landed hit are the spell's identity (that is what "chain" means)
## and stay automatic; they are a consequence of connecting, not aim assist.

const FIRST_REACH: float = 560.0   # reach for the initial arc to target 1
const FIRST_CORRIDOR: float = 46.0 # half-width of the aim corridor for target 1
const HOP_RANGE: float = 240.0     # leap distance between links
const FALLOFF: float = 0.82        # damage retained per hop
## Was 0.34 — long enough that the bolt sat on screen as a DECAL, which is the
## corniest thing electricity can do. A discharge is near-instantaneous with an
## afterimage. UNTESTED FEEL GUESS.
const LIFE: float = 0.22
## Was 6. Six evenly-spaced kinks per link is a sawtooth, and on the common
## one-target case that sawtooth rendered as a single smooth drooping thread — the
## "one lonely arc" read. UNTESTED FEEL GUESS.
const SEG: int = 14
## How far a vertex may slide ALONG its link, as a fraction of one segment. Breaks
## the sawtooth rhythm. Under 0.5 so vertices stay strictly ordered.
const AXIS_SCATTER: float = 0.45
const JAG: float = 13.0            # peak lateral wander of a link, px
## How often the whole bolt re-randomises, in Hz. Quantized, not continuous — the
## snap between discrete shapes is what reads as electric rather than as a rope.
const JITTER_HZ: float = 34.0
## Dimmer filaments braided alongside each link. One path is a line; three
## overlapping filaments have volume. UNTESTED FEEL GUESS.
const GHOST_STRANDS: int = 2
const BRANCH_SLOTS: int = 4        # dead-end offshoots considered per link
const BRANCH_CHANCE: float = 0.5   # gate per slot per tick — they strobe
const BRANCH_LEN: float = 26.0     # px, before per-branch hash variation
const FLICKER_FLOOR: float = 0.35  # a dying arc gutters, it does not ramp
const CORE_COLOR: Color = Color(1.7, 1.75, 1.9)  # HDR white-hot core (blooms)

## WHO THIS SPELL MAY HURT. Stamped by SpellCaster._stamp() at cast time, so it
## follows the CASTER's faction rather than being fixed at "enemy" forever.
##
## Every spectacle used to scan the literal group "enemy", which is why a
## hero-shaped bot's spells passed harmlessly through another hero: the aim was
## right, the spectacle spawned and drew, and then it queried a group its target
## was not in. Nothing errored — the spell simply never hit anything, which reads
## as a physics bug rather than a targeting one.
##
## Defaults to "enemy", so every existing caster, capture tool and test is
## byte-identical and single player does not change by one branch.
var target_group: String = "enemy"
var element_id: int = Elements.Element.LIGHTNING
var _color: Color = Color(1.0, 0.95, 0.4, 1.0)
var _points: PackedVector2Array = PackedVector2Array()
var _elapsed: float = -1.0


## Fire the chain from `origin` toward `aim`, hopping up to `max_hops` enemies.
func chain(
	origin: Vector2, aim: Vector2, color: Color,
	max_hops: int = 4, hop_range: float = HOP_RANGE, damage: int = 44, _effect: String = "lightning"
) -> void:
	_color = color
	var d: Vector2 = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	var links: Array = build_chain(origin, d, FIRST_REACH, hop_range, max_hops,
		get_tree().get_nodes_in_group(target_group))
	_points = PackedVector2Array([origin])
	if links.is_empty():
		_whiff(origin, d)
		return
	var dmg: float = float(damage)
	var tint: Color = Color(color.r, color.g, color.b, 1.0)
	for e: Node in links:
		if e is Node2D and is_instance_valid(e):
			_points.append((e as Node2D).global_position)  # capture BEFORE damage (may free)
		if e.has_method("take_damage"):
			SpellTargets.hurt(e, int(round(dmg)), tint)
		if e.has_method("apply_status"):
			e.apply_status(element_id, false)
		if e.has_method("apply_knockback"):
			e.apply_knockback(d * 110.0)
		dmg *= FALLOFF
	_elapsed = 0.0
	global_position = Vector2.ZERO  # drawn in world coords
	# Node-flash bursts at each strike point + juice.
	CombatVfx.spawn_burst(get_parent(), origin, CORE_COLOR, Color(color.r, color.g, color.b, 0.0),
		12, 0.3, 60.0, 160.0, 0.6, 1.6, 0.0, 0.0, true)
	for i in range(1, _points.size()):
		CombatVfx.spawn_burst(get_parent(), _points[i], CORE_COLOR, Color(color.r, color.g, color.b, 0.0),
			8, 0.3, 40.0, 130.0, 0.6, 1.5, 0.0, 0.0, true)
	Juice.shake_camera(6.0)
	Juice.zoom_pull_camera(0.12, 0.35, 0.12, 0.45)
	# A modest screen ripple from the LAST body in the chain, so the eye is pulled
	# down the chain rather than to the caster. Kept well under the Chidori's 0.75
	# — this is a 3 s-cooldown staple, not an ultimate.
	PostProcess.shock(0.35, Juice.world_to_uv(_points[_points.size() - 1]))
	# One LIGHTNING-coloured mark at the end of the chain, on the HEAVY rung —
	# this is a 3 s-cooldown staple, not an ultimate, and the ladder is the thing
	# that keeps it from feeling like one. Staged on the LAST body struck, same as
	# the ripple, so the eye is pulled down the chain rather than back to the
	# caster. Camera + freeze suppressed (fired above).
	Juice.tier_frame(SpellTier.Tier.HEAVY, _points[_points.size() - 1], element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	Sfx.play("zap", -1.0, 0.08)
	queue_redraw()


## A miss: the bolt still rips the full reach down the aim and dies in empty air.
## The player SEES where their aim went — no silent nothing, and no retarget.
func _whiff(origin: Vector2, d: Vector2) -> void:
	_points.append(origin + d * FIRST_REACH)
	_elapsed = 0.0
	global_position = Vector2.ZERO
	CombatVfx.spawn_burst(get_parent(), origin, CORE_COLOR, Color(_color.r, _color.g, _color.b, 0.0),
		8, 0.25, 50.0, 120.0, 0.6, 1.4, 0.0, 0.0, true)
	Juice.shake_camera(2.5)
	Sfx.play("zap_chain", -4.0, 0.08)
	queue_redraw()


## Pure geometry (testable): the ordered chain of nodes struck. Target 1 = the
## nearest node actually ON the aim ray — inside `corridor` perpendicular of it and
## within `first_reach` along it. Each subsequent = nearest unvisited within
## `hop_range` of the previous. Up to `max_hops` total. Empty if the aim misses.
static func build_chain(
	origin: Vector2, dir: Vector2, first_reach: float, hop_range: float, max_hops: int, nodes: Array,
	corridor: float = FIRST_CORRIDOR
) -> Array:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var perp: Vector2 = d.orthogonal()
	var out: Array = []
	var first: Node2D = null
	var best: float = first_reach
	for n: Node in nodes:
		if not n is Node2D:
			continue
		var rel: Vector2 = (n as Node2D).global_position - origin
		var along: float = rel.dot(d)
		if along < 0.0 or along > first_reach:
			continue  # behind the caster, or past the bolt's reach
		if absf(rel.dot(perp)) > corridor:
			continue  # off the aim line — the bolt does NOT bend to find it
		if along < best:
			best = along
			first = n as Node2D
	if first == null:
		return out
	out.append(first)
	var cur: Vector2 = first.global_position
	while out.size() < max_hops:
		var nxt: Node2D = null
		var bestd: float = hop_range
		for n: Node in nodes:
			if n in out or not n is Node2D:
				continue
			var dd: float = cur.distance_to((n as Node2D).global_position)
			if dd < bestd:
				bestd = dd
				nxt = n as Node2D
		if nxt == null:
			break
		out.append(nxt)
		cur = nxt.global_position
	return out


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _elapsed >= LIFE:
		queue_free()
		return
	queue_redraw()


## Deterministic 0..1 hash from an int — same idiom as BeamSpell._hash01. No RNG
## state, so a redraw never pops; feed QUANTIZED time and the shape snaps.
static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


static func _hsign(n: int) -> float:
	return _hash01(n) * 2.0 - 1.0


## One filament between two strike points. `salt` selects the strand (0 = the main
## arc), `tq` is the quantized time tick. Pure + static so the "the drawn path
## stays between the two points it damaged" invariant is headless-testable — same
## reasoning as build_chain being a pure selector.
##
## Endpoints are pinned: a link MUST start and end on the bodies it hit, or the
## picture stops matching the damage. Everything between them scatters.
static func link_points(a: Vector2, b: Vector2, salt: int, tq: int) -> PackedVector2Array:
	var span: Vector2 = b - a
	var perp: Vector2 = span.orthogonal().normalized() if span != Vector2.ZERO else Vector2.UP
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in SEG + 1:
		var t: float = float(i) / float(SEG)
		if i > 0 and i < SEG:
			t += _hsign(i * 31 + salt * 977 + tq * 61) * AXIS_SCATTER / float(SEG)
			t = clampf(t, 0.0, 1.0)
		var env: float = sin(t * PI)  # pinned at both ends
		# Two hash octaves — a coarse wander plus a fine kink, so the path has
		# structure at two scales instead of one uniform zigzag.
		var n: float = _hsign(i * 7 + salt * 131 + tq * 17) * 0.7 \
				+ _hsign(i * 53 + salt * 419 + tq * 5) * 0.3
		pts.append(a.lerp(b, t) + perp * n * env * JAG)
	return pts


func _draw() -> void:
	if _elapsed < 0.0 or _points.size() < 2:
		return
	var intensity: float = clampf(1.0 - _elapsed / LIFE, 0.0, 1.0)
	var tq: int = int(floorf(_elapsed * JITTER_HZ))
	# A dying arc gutters rather than ramping smoothly to nothing.
	intensity *= FLICKER_FLOOR + (1.0 - FLICKER_FLOOR) * _hash01(tq * 991)
	for i in range(_points.size() - 1):
		_draw_link(_points[i], _points[i + 1], intensity, tq, i)
	# Bright node flashes at each strike point — the bolt EARTHING into a body.
	for i in range(_points.size()):
		draw_circle(_points[i], 9.0, Color(_color.r, _color.g, _color.b, 0.35 * intensity), true, -1.0, true)
		draw_circle(_points[i], 4.0, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.85 * intensity), true, -1.0, true)


## One link between two strike points: a faint straight haze marking the true
## path, dim braided ghost filaments, the white-hot main arc, and strobing
## dead-end forks. The old version drew a single smooth polyline, which on the
## common ONE-target case rendered as a lonely drooping thread — a wire, not a
## discharge. Everything here exists to break that single-line read.
func _draw_link(a: Vector2, b: Vector2, intensity: float, tq: int, salt_base: int) -> void:
	draw_line(a, b, Color(_color.r, _color.g, _color.b, 0.12 * intensity), JAG * 1.6, true)
	for s: int in range(GHOST_STRANDS, 0, -1):
		var gp: PackedVector2Array = link_points(a, b, salt_base * 13 + s, tq)
		draw_polyline(gp, Color(_color.r, _color.g, _color.b, 0.32 * intensity), 1.8, true)
		draw_polyline(gp, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.28 * intensity), 1.0, true)
	var pts: PackedVector2Array = link_points(a, b, salt_base * 13, tq)
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.75 * intensity), 3.0, true)
	draw_polyline(pts, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.95 * intensity), 1.2, true)
	_draw_branches(pts, intensity, tq, salt_base)


## Dead-end offshoots off a link. Lightning forks constantly and most forks go
## nowhere; an unbranched path is the tell that it came out of a for-loop. Purely
## decorative — the chain's damage is applied at the NODES, never along the drawn
## path, so a fork cannot promise reach that doesn't exist.
func _draw_branches(pts: PackedVector2Array, intensity: float, tq: int, salt_base: int) -> void:
	var perp: Vector2 = (pts[pts.size() - 1] - pts[0]).orthogonal().normalized()
	for b: int in BRANCH_SLOTS:
		var k: int = b * 397 + salt_base * 53 + tq * 13
		if _hash01(k) > BRANCH_CHANCE:
			continue
		# Never fork off the endpoints — a fork growing out of a struck body reads
		# as a bug rather than as electricity.
		var i: int = 1 + int(_hash01(k + 7) * float(pts.size() - 3))
		var base: Vector2 = pts[i]
		var along: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
		var side: float = 1.0 if _hash01(k + 61) < 0.5 else -1.0
		var reach: float = BRANCH_LEN * (0.5 + 0.8 * _hash01(k + 823))
		var p1: Vector2 = base + perp * side * reach * 0.6 + along * reach * 0.4
		var p2: Vector2 = p1 + perp * side * reach * 0.5 - along * reach * 0.15
		draw_polyline(PackedVector2Array([base, p1, p2]),
			Color(_color.r, _color.g, _color.b, 0.55 * intensity), 1.8, true)
		draw_polyline(PackedVector2Array([base, p1, p2]),
			Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.45 * intensity), 0.9, true)
