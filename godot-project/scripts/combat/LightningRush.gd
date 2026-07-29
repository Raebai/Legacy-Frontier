class_name LightningRush
extends Node2D
## Signature spectacle — CHIDORI / Thunderclap. The Brawler's ultimate: a brief
## crackling charge, then a JAGGED lightning LANCE rips down the aim in an instant
## — nothing like the clean Zoltraak beam. Everything on the line takes heavy
## damage + Shock and is thrown along the strike; the bolt then FORKS a fixed arc
## off the tip. Heavy juice: hitstop, big shake, zoom-punch, thunder crack.
##
## Damage is a pure line test (targets_on_line, headless-testable). rush() drives
## the visual/juice timeline. Instantiate .new(), add under the arena, call rush().
## The hero does its own forward lunge on cast (Hero._cast_signature) so it READS
## as a dash-punch; this node owns the bolt + damage + chain + screen kick.

## The caster's own tell. This is NOT the whole dodge window: Hero gates every
## signature behind a CastStyle COIL summon windup first (~0.22 s x the spell's
## tier multiplier), so the opponent sees a sigil + a committed cast pose and only
## THEN this crackle, before any damage exists. 0.16 s is the final "it's coming
## RIGHT NOW" beat on top of that, not the entire warning. UNTESTED FEEL GUESS.
const CHARGE_TIME: float = 0.16
## Was 0.10 + 0.30. A bolt that lingers for a third of a second is a DECAL, and a
## static decal is the corniest possible lightning — real discharges are gone
## before you can look at them and leave only an afterimage. Shortened hard; the
## 0.1 s hit_stop in _discharge stretches these in wall-clock anyway, so the frame
## the player actually reads is longer than the number suggests. UNTESTED.
const STRIKE_TIME: float = 0.06   # the bolt at full intensity
const FADE_TIME: float = 0.18     # guttering afterimage
## The opening white-out. For this long after the discharge the whole lane is
## flooded — real lightning LIGHTS ITS SURROUNDINGS, and that flash sells the
## strike far more than the filament does. UNTESTED FEEL GUESS.
const FLASH_TIME: float = 0.05
const DEFAULT_LENGTH: float = 620.0
const DEFAULT_WIDTH: float = 26.0
const DEFAULT_DAMAGE: int = 62
const KNOCKBACK: float = 460.0    # brutal — it's a committed melee ultimate
## Slack added to the half-width when testing what the lance hits. Named (it used
## to be a bare `+ 10.0` inside _discharge) because the DRAWING now derives from
## the same number — see _damage_half.
const HIT_FORGIVENESS: float = 10.0
const CHAIN_RANGE: float = 220.0  # fork-arc reach off the lance tip
const FORK_ANGLE: float = 0.85    # radians the fork kicks off the lance axis
const FORK_CORRIDOR: float = 34.0 # half-width of the fork's damage corridor
const CHAIN_DAMAGE_FACTOR: float = 0.5
## Was 12. At 12 the vertices sat ~52 px apart over a 620 px lance and the result
## read as a few lazy S-bends — a wobbling ROPE, not a discharge. Electricity
## needs kinks at a finer scale than the eye tracks. UNTESTED FEEL GUESS.
const BOLT_SEGMENTS: int = 26
## How far each vertex may slide ALONG the axis off its evenly-spaced slot, as a
## fraction of one segment. Evenly spaced kinks are a sawtooth, and a sawtooth is
## a pattern the eye clocks as generated in about one frame. Kept under 0.5 so the
## vertices stay strictly ordered (0.5 would let neighbours coincide). UNTESTED.
const AXIS_SCATTER: float = 0.45
## Peak lateral wander of a filament, as a fraction of the damage half-corridor.
## Deliberately a FRACTION and not its own px constant: see _damage_half — the
## picture is not allowed to drift wider than the hitbox.
const JAG_FRACTION: float = 0.62
## Extra dimmer filaments braided alongside the main arc. One line is a line; three
## overlapping filaments read as a discharge with volume. UNTESTED FEEL GUESS.
const GHOST_STRANDS: int = 2
## How often the whole bolt re-randomises, in Hz. QUANTIZED, not continuous: the
## old code slid the shape smoothly every frame, which reads as a rope swaying.
## Snapping between discrete shapes ~30 times a second is what reads as electric.
## Same idiom as BeamSpell's tempest torrent. UNTESTED FEEL GUESS.
const JITTER_HZ: float = 34.0
## Dead-end offshoots considered per redraw (each is hash-gated, so fewer draw).
## Lightning FORKS; an unbranched path is the tell that it came out of a for-loop.
const BRANCH_SLOTS: int = 8
const BRANCH_CHANCE: float = 0.55   # gate per slot per quantized tick — they strobe
## Dimmest the guttering fade is allowed to flicker to. A dying arc gutters; it
## does not ramp linearly to nothing. UNTESTED FEEL GUESS.
const FLICKER_FLOOR: float = 0.35
const CORE_COLOR: Color = Color(1.7, 1.75, 1.9)  # HDR white-hot lightning core (blooms)

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
var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(1.0, 0.9, 0.35, 1.0)
var _length: float = DEFAULT_LENGTH
var _width: float = DEFAULT_WIDTH
var _damage: int = DEFAULT_DAMAGE
var _elapsed: float = -1.0
var _fired: bool = false
var _chain_from: Vector2 = Vector2.ZERO
var _chain_to: Vector2 = Vector2.ZERO
var _has_chain: bool = false
## Elemental ailment (Elements.Element) applied to struck enemies — LIGHTNING.
var element_id: int = Elements.Element.LIGHTNING


## Public entry: charge at `origin`, then rip a lightning lance of length/width
## along `dir` for `damage`. Colour tints the arc (defaults to the lightning
## yellow); the core stays white-hot.
func rush(
	origin: Vector2,
	dir: Vector2,
	color: Color,
	length: float = DEFAULT_LENGTH,
	width: float = DEFAULT_WIDTH,
	damage: int = DEFAULT_DAMAGE,
	_effect: String = "lightning",
) -> void:
	_origin = origin
	_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_color = color
	_length = length
	_width = width
	_damage = damage
	global_position = Vector2.ZERO  # drawn in world space from _origin
	_elapsed = 0.0
	# Charge crackle at the fist — sharp electric sparks gathering.
	CombatVfx.spawn_burst(
		get_parent(), _origin, Color(1.0, 1.0, 0.85, 0.95), Color(_color.r, _color.g, _color.b, 0.0),
		20, CHARGE_TIME * 0.9, 60.0, 150.0, 0.6, 1.6, 2.5, 5.0, true
	)
	Sfx.play("charge_up", 1.0, 0.04)  # chidori charge — epic power-up before the strike
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if not _fired and _elapsed >= CHARGE_TIME:
		_discharge()
	if _elapsed >= CHARGE_TIME + STRIKE_TIME + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## The lance rips: line damage + Shock + shove, a fork-arc to a straggler, and a
## heavy screen kick. Thunder crack SFX + music duck for the impact beat.
func _discharge() -> void:
	_fired = true
	var half: float = _damage_half()
	var struck: Array = targets_on_line(_origin, _dir, _length, half, get_tree().get_nodes_in_group(target_group))
	for enemy: Node in struck:
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(_dir * KNOCKBACK)
	for prop: Node in targets_on_line(_origin, _dir, _length, half, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	_resolve_chain(struck)
	CombatVfx.spawn_burst(
		get_parent(), _beam_tip(), CORE_COLOR, Color(_color.r, _color.g, _color.b, 0.0),
		34, 0.4, 140.0, 380.0, 0.7, 2.0, 3.0, 6.0, true
	)
	Juice.hit_stop(0.1)
	Juice.shake_camera(15.0)
	Juice.zoom_punch_camera(0.11, 0.22)
	Juice.zoom_pull_camera(0.14, 0.3, 0.12, 0.45)  # brief pull to show the strike
	# The screen itself feels it. Centred on the STRIKE POINT rather than the screen
	# middle so the ripple radiates from where the lance landed (Juice.world_to_uv
	# is the house helper for that conversion — see HollowPurple).
	PostProcess.shock(0.75, Juice.world_to_uv(_beam_tip()))
	# The lance landing takes the screen in LIGHTNING yellow — the ULT rung, and
	# the element is what stops this ending on the same frame as every other ult.
	# Camera + freeze suppressed: four lines of tuned camera work already fired,
	# and letting the frame add a fifth double-punches it.
	Juice.tier_frame(SpellTier.Tier.ULT, _beam_tip(), element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	Sfx.play("zap", 2.0, 0.06)
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("duck"):
		music.call("duck", 7.0, 0.35)


## Fork an arc off the tip — a FIXED geometric branch, not a search for a victim
## (magic-overhaul rule 1: no auto-aim anywhere). The arc kicks off at a set angle
## from the lance and damages whatever happens to be standing in it, with partial
## damage + Shock, so the strike jumps like real lightning without hunting.
func _resolve_chain(already_hit: Array) -> void:
	var tip: Vector2 = _beam_tip()
	# Deterministic side from the strike's own geometry — reads random, never seeks.
	var side: float = 1.0 if sin(_origin.x * 0.07 + _origin.y * 0.11) >= 0.0 else -1.0
	var fork_dir: Vector2 = _dir.rotated(side * FORK_ANGLE)
	_chain_from = tip
	_chain_to = tip + fork_dir * CHAIN_RANGE
	_has_chain = true
	for e: Node in targets_on_line(tip, fork_dir, CHAIN_RANGE, FORK_CORRIDOR,
			get_tree().get_nodes_in_group(target_group)):
		if e in already_hit or not is_instance_valid(e):
			continue
		if e.has_method("take_damage"):
			e.take_damage(int(round(float(_damage) * CHAIN_DAMAGE_FACTOR)))
		if e.has_method("apply_status"):
			e.apply_status(element_id, false)  # no further chain


## Pure geometry (testable): nodes whose centre projects onto the segment
## [0, length] along `dir` from `origin`, within `half_width` perpendicular.
static func targets_on_line(
	origin: Vector2, dir: Vector2, length: float, half_width: float, nodes: Array
) -> Array:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var perp: Vector2 = d.orthogonal()
	var out: Array = []
	for n: Node in nodes:
		if not n is Node2D:
			continue
		var rel: Vector2 = (n as Node2D).global_position - origin
		var proj: float = rel.dot(d)
		if proj < 0.0 or proj > length:
			continue
		if absf(rel.dot(perp)) <= half_width:
			out.append(n)
	return out


func _beam_tip() -> Vector2:
	return _origin + _dir * _length


## THE single authority for how wide this spell is. The damage corridor and every
## drawn filament are both derived from it, so the picture can never promise reach
## the hitbox does not have (maker: "the spells shouldn't be able to get out the
## radius"). Before this the two had drifted badly apart: damage stopped at 23 px
## off-axis while the drawn bolt swung out past 40 and its glow past 60, so the
## lance visibly swept through enemies that took nothing.
func _damage_half() -> float:
	return _width * 0.5 + HIT_FORGIVENESS


## Deterministic 0..1 hash from an int — same idiom as BeamSpell._hash01. No RNG
## state, so a redraw with the same inputs never pops; feed QUANTIZED time and the
## whole shape snaps between discrete states, which is the difference between
## "electricity" and "a rope swaying".
static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


## Signed (-1..1) form of the above.
static func _hsign(n: int) -> float:
	return _hash01(n) * 2.0 - 1.0


## Which discrete shape the bolt is wearing right now. Everything drawn keys off
## this instead of raw _elapsed, so the filaments SNAP rather than slide.
func _tick() -> int:
	return int(floorf(_elapsed * JITTER_HZ))


## Force a drawn point back inside the damage corridor. EVERY point of EVERY
## filament goes through this — the invariant is much harder to break later if it
## lives at one choke point than if seven draw sites each have to remember it.
## This is also what the headless test asserts against.
static func clamp_in_corridor(
	p: Vector2, origin: Vector2, dir: Vector2, length: float, half: float
) -> Vector2:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var perp: Vector2 = d.orthogonal()
	var rel: Vector2 = p - origin
	return origin \
		+ d * clampf(rel.dot(d), 0.0, length) \
		+ perp * clampf(rel.dot(perp), -half, half)


## One filament of the bolt, origin -> tip, guaranteed inside the damage corridor.
## `salt` selects the strand (0 = the main white-hot arc, >0 = braided ghosts) and
## `tq` is the quantized time tick. Pure + static so the corridor invariant is
## headless-testable without a scene — same reasoning as targets_on_line.
##
## Two things here are doing the heavy lifting against "corny":
##  - vertices slide ALONG the axis (AXIS_SCATTER), killing the sawtooth rhythm
##    that evenly-spaced zigzags always produce;
##  - the lateral offset is two hash octaves, so the path has a coarse wander AND
##    a fine kink instead of one uniform amplitude everywhere.
static func strand_points(
	origin: Vector2, dir: Vector2, length: float, half: float,
	segments: int, salt: int, tq: int
) -> PackedVector2Array:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var perp: Vector2 = d.orthogonal()
	var tip: Vector2 = origin + d * length
	var jag: float = half * JAG_FRACTION
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in segments + 1:
		var t: float = float(i) / float(segments)
		# Endpoints stay pinned: the lance must CONNECT to the fist and to the
		# impact point. Only the interior scatters.
		if i > 0 and i < segments:
			t += _hsign(i * 31 + salt * 977 + tq * 61) * AXIS_SCATTER / float(segments)
			t = clampf(t, 0.0, 1.0)
		var env: float = sin(t * PI)  # 0 at both ends, widest mid-bolt
		var n: float = _hsign(i * 7 + salt * 131 + tq * 17) * 0.7 \
				+ _hsign(i * 53 + salt * 419 + tq * 5) * 0.3
		pts.append(clamp_in_corridor(
			origin.lerp(tip, t) + perp * n * env * jag, origin, d, length, half))
	return pts


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < CHARGE_TIME:
		_draw_charge()
		return
	var since: float = _elapsed - CHARGE_TIME
	var intensity: float
	if since < STRIKE_TIME:
		intensity = 1.0
	else:
		intensity = clampf(1.0 - (since - STRIKE_TIME) / FADE_TIME, 0.0, 1.0)
	if intensity <= 0.01:
		return
	# A dying arc GUTTERS — it does not ramp smoothly to nothing. Flicker only
	# during the fade so the strike frames themselves stay solid.
	var tq: int = _tick()
	if since >= STRIKE_TIME:
		intensity *= FLICKER_FLOOR + (1.0 - FLICKER_FLOOR) * _hash01(tq * 991)
	var tip: Vector2 = _beam_tip()
	var half: float = _damage_half()
	# The lane haze, drawn STRAIGHT down the axis at exactly the damage corridor's
	# width. Two jobs: it honestly shows the player where the hitbox is, and it
	# replaces the old glow — which was a fat polyline that FOLLOWED the wobble and
	# so rendered as a flat mustard highlighter stroke, the single worst tell in
	# the old picture. Idiom borrowed from BeamSpell's tempest torrent.
	# The opening beat brightens the haze rather than adding a second bar on top of
	# it. A white-hot straight line down the lane was tried first and it was the
	# original bug in a brighter colour — a hard-edged solid slab reads as a
	# painted beam, and no amount of jagged filament on top rescues it. The flash
	# lives in the RADIAL blooms below instead, where lightning's light actually is.
	var flash: float = clampf(1.0 - since / FLASH_TIME, 0.0, 1.0)
	draw_line(_origin, tip,
		Color(_color.r, _color.g, _color.b, (0.10 + 0.14 * flash) * intensity), half * 2.0, true)
	# Braided filaments: one dim ghost pass per extra strand, then the main arc on
	# top. Three overlapping paths read as a discharge with volume; one path reads
	# as a line, which is exactly what was wrong.
	for s: int in range(GHOST_STRANDS, 0, -1):
		var gp: PackedVector2Array = strand_points(_origin, _dir, _length, half, BOLT_SEGMENTS, s, tq)
		draw_polyline(gp, Color(_color.r, _color.g, _color.b, 0.34 * intensity), maxf(half * 0.16, 1.5), true)
		draw_polyline(gp, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.30 * intensity), 1.0, true)
	var pts: PackedVector2Array = strand_points(_origin, _dir, _length, half, BOLT_SEGMENTS, 0, tq)
	# Main arc: saturated body under a thin white-hot core. The core is THIN on
	# purpose — real lightning is a hairline that blooms, and a thick core just
	# reads as a painted stroke. Both stay inside the corridor by construction.
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.75 * intensity), maxf(half * 0.34, 2.0), true)
	draw_polyline(pts, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.95 * intensity), maxf(half * 0.12, 1.2), true)
	_draw_branches(pts, half, intensity, tq)
	# Muzzle + impact bloom — THE flash. Radial, at the two points the lance
	# actually touches, drawn as stacked circles so the light falls off instead of
	# ending at a hard edge. A bloom is light spill, not a claim about the corridor.
	for k: int in 3:
		var f: float = 1.0 - float(k) / 3.0        # 1.0, 0.67, 0.33
		var a: float = 0.16 + 0.34 * float(k) / 2.0  # faintest when widest
		draw_circle(tip, half * (1.0 + 2.2 * flash) * (1.0 - f * 0.55),
			Color(_color.r, _color.g, _color.b, a * intensity), true, -1.0, true)
		draw_circle(_origin, half * (0.7 + 1.5 * flash) * (1.0 - f * 0.55),
			Color(_color.r, _color.g, _color.b, a * intensity), true, -1.0, true)
	draw_circle(tip, half * (0.35 + 0.6 * flash),
		Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.85 * intensity), true, -1.0, true)
	draw_circle(_origin, half * (0.28 + 0.4 * flash),
		Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.8 * intensity), true, -1.0, true)
	# Expanding impact ring — the shockwave leaving the strike point.
	if flash > 0.0:
		draw_arc(tip, half * (0.6 + 3.4 * (1.0 - flash)), 0.0, TAU, 32,
			Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.75 * flash), 2.5, true)
	# The fork-arc off the tip. Drawn with the SAME strand builder as the lance so
	# it is recognisably the same electricity, and confined to the fork's own
	# damage corridor for the same honesty reason.
	if _has_chain:
		var cdir: Vector2 = (_chain_to - _chain_from)
		var clen: float = cdir.length()
		if clen > 1.0:
			var cpts: PackedVector2Array = strand_points(
				_chain_from, cdir / clen, clen, FORK_CORRIDOR, BOLT_SEGMENTS / 2, 7, tq)
			draw_polyline(cpts, Color(_color.r, _color.g, _color.b, 0.7 * intensity), 3.0, true)
			draw_polyline(cpts, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.8 * intensity), 1.2, true)


## The charge tell. This is the last beat of the opponent's dodge window (Hero's
## summon windup already ran), so it has to READ, not just glow: a ball of
## crackling stubs at the fist plus a collapsing ring that closes as the strike
## arrives, so "how long have I got" is legible from the ring alone.
func _draw_charge() -> void:
	var cp: float = _elapsed / CHARGE_TIME
	var tq: int = _tick()
	var r: float = _damage_half() * (0.5 + 0.6 * cp)
	draw_circle(_origin, r, Color(_color.r, _color.g, _color.b, 0.35 * cp), true, -1.0, true)
	draw_circle(_origin, r * 0.4, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.8 * cp), true, -1.0, true)
	# Collapsing ring: reads as a countdown to the discharge.
	draw_arc(_origin, r * (2.6 - 1.6 * cp), 0.0, TAU, 32,
		Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.5 * cp), 2.0, true)
	# Crackle stubs snapping around the fist — hash-gated on the quantized tick so
	# they flick to new angles rather than rotating smoothly.
	for i: int in 7:
		if _hash01(i * 71 + tq * 29) > 0.6:
			continue
		var a: float = _hash01(i * 17 + tq * 5) * TAU
		var v: Vector2 = Vector2.from_angle(a)
		var mid: Vector2 = _origin + v * r * 1.1 + v.orthogonal() * r * 0.35 * _hsign(i * 5 + tq)
		draw_polyline(PackedVector2Array([_origin + v * r * 0.3, mid, _origin + v * r * (1.5 + 0.6 * cp)]),
			Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.7 * cp), 1.5, true)


## Short dead-end offshoots hanging off the main arc. An unbranched path is the
## single clearest tell that a bolt came out of a for-loop — real lightning forks
## constantly and most of those forks go nowhere. Each slot is hash-gated on the
## quantized tick so individual branches STROBE in and out between snaps rather
## than all sitting there for the bolt's whole life.
func _draw_branches(pts: PackedVector2Array, half: float, intensity: float, tq: int) -> void:
	var perp: Vector2 = _dir.orthogonal()
	for b: int in BRANCH_SLOTS:
		if _hash01(b * 397 + tq * 13) > BRANCH_CHANCE:
			continue
		# Never branch off the two endpoints — a fork at the fist or at the impact
		# point reads as a mistake rather than a fork.
		var i: int = 1 + int(_hash01(b * 211 + tq * 7) * float(pts.size() - 3))
		var base: Vector2 = pts[i]
		var side: float = 1.0 if _hash01(b * 61 + tq * 3) < 0.5 else -1.0
		# Two-kink offshoot leaning forward along the strike (it carries the
		# lance's momentum) and tapering out to nothing.
		var reach: float = half * (0.5 + 0.8 * _hash01(b * 823 + tq))
		var p1: Vector2 = base + perp * side * reach * 0.55 + _dir * reach * 0.45
		var p2: Vector2 = p1 + perp * side * reach * 0.5 - _dir * reach * 0.2
		var p3: Vector2 = p2 + perp * side * reach * 0.35 + _dir * reach * 0.5
		var fork: PackedVector2Array = PackedVector2Array([
			base,
			clamp_in_corridor(p1, _origin, _dir, _length, half),
			clamp_in_corridor(p2, _origin, _dir, _length, half),
			clamp_in_corridor(p3, _origin, _dir, _length, half),
		])
		draw_polyline(fork, Color(_color.r, _color.g, _color.b, 0.55 * intensity), 2.0, true)
		draw_polyline(fork, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.5 * intensity), 1.0, true)
