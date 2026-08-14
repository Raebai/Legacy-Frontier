class_name FaultLine
extends Node2D
## FAULT LINE — the Juggernaut's ULT. A rupture that TRAVELS.
##
## It replaces `colossus_pillar`, which was a near-duplicate of the Juggernaut's
## own Rock Pillar: both were "a stone spire erupts on marked ground", one simply
## larger than the other. The maker's ruling was "we cannot have any recolours",
## and a bigger version of your own payoff spell is the purest form of one.
##
## So the ult stopped being a placed eruption and became a MOVING one. The floor
## splits at your feet and the split runs — following the terrain, tearing it as it
## goes, throwing up everything it passes under — until it has spent its travel
## budget or reached the lip of a pit.
##
## ── WHY THIS IS NOT A PILLAR AND NOT A BEAM ──────────────────────────────────
##   vs a PILLAR   A pillar is a point you can simply not stand on, decided at cast
##                 time. This sweeps a whole line over ~1.2 s, so the dangerous
##                 ground is somewhere different every frame and standing still is
##                 never the answer.
##   vs a BEAM     A beam is a straight segment in the air that ignores the world.
##                 This is welded to the FLOOR: it follows the terrain profile via
##                 `SpellWorld.ground_path`, it cannot climb, it cannot cross a
##                 pit, and it cannot touch anything that is not near the ground.
##                 A jump beats it outright; nothing beats a beam by jumping.
##
## ── COMPOSED, NOT REINVENTED ─────────────────────────────────────────────────
## The three pieces of "the floor is wrecked" already exist and are used verbatim:
## `SpellWorld.ground_path` for the terrain profile, `GroundCrater` for the gouges,
## `ScorchDecal` for the cracks, and `DestructibleTerrain.damage_at` for cover that
## happens to be standing on the seam. The launch impulse is DERIVED from
## `SlamPhysics.MIN_SLAM_SPEED` rather than picked, so a body this throws is
## guaranteed to register a slam when it lands — see `knockback()`.
##
## ── THE TELL AND THE COUNTERPLAY (the locked "everything is dodgeable" rule) ──
##   TELL         The ENTIRE path lights up first. For `SEAM_TELL` seconds a
##                glowing fracture seam is drawn along the exact ground the crest
##                will travel, before the crest moves a pixel — so the spell shows
##                you its whole future, not just its origin. The ULT sigil opens on
##                the caster at the same moment.
##   COUNTERPLAY  Three, all readable. JUMP it: the crest only catches bodies
##                within `AIR_CLEAR` px above the floor line, so being airborne as
##                it passes is a clean dodge. STAND OFF IT: the seam is
##                `CREST_HALF_WIDTH` px wide and perfectly straight in x. BE PAST A
##                LIP: it stops at the first gap in the floor, so a pit or a ledge
##                edge is a hard wall to it.
##
## ⚠ ELEMENT IS DECLARED, NEVER INFERRED — EARTH, so a caught body is Staggered
## (a short root) and the rupture opposes the right things in the reaction table.

# ------------------------------------------------------------------- IDENTITY
## Stamped by `SpellCaster._stamp()`. All five DECLARED — `set()` on an undeclared
## property is a silent no-op, and an un-stamped spectacle is quietly inert in the
## entire reaction system without erroring once.
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.EARTH
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## ERUPTION — the ground comes UP here. Stated because `SpellSigil`'s script-keyed
## motif table lives in a file this agent does not own; the `sigil_motif` override
## is the sanctioned route (`SpellSigil._motif_of`).
var sigil_motif: int = MagicCircle.Motif.ERUPTION

# ------------------------------------------------------------------ THE RUPTURE
## How long the whole path glows before the crest starts moving. THE TELL, and the
## single most important number in the file: it is what makes a spell that covers
## 760 px fair.
const SEAM_TELL: float = 0.34
## Crest travel speed, px/s. Fast enough to be a shockwave, slow enough that the
## eye can track it and the legs can leave.
const TRAVEL_SPEED: float = 620.0
## Half-width of the damaging band, measured horizontally from the crest.
const CREST_HALF_WIDTH: float = 34.0
## How far ABOVE the floor line a body is still caught. Above this you jumped it —
## this constant IS the jump dodge, and it is deliberately smaller than a hero's
## jump apex.
const AIR_CLEAR: float = 46.0
## ...and how far BELOW, so a body standing in a shallow dip is not missed.
const GROUND_SLACK: float = 60.0
## Launch impulse, DERIVED rather than picked: `SlamPhysics.check` only registers a
## slam above `MIN_SLAM_SPEED`, so a rupture whose throw sat under that number
## would hurl bodies into walls with no impact at all. The factor is the margin.
const KNOCKBACK_FACTOR: float = 1.7
## Share of the impulse that is UP rather than along the travel. Mostly up: the
## floor is opening underneath you, not shoving you.
const UP_BIAS: float = 0.78
## Terrain samples taken along the path. More is smoother and costs one downward
## raycast each, taken ONCE at cast time and never per frame.
const PATH_SAMPLES: int = 26
## Px between gouges torn out of the floor, and the sparser stride that ships to
## the phone. Cosmetic only — the crater is scenery, nothing reads the floor.
const CRATER_STRIDE: float = 96.0
const CRATER_STRIDE_LOW: float = 176.0
## Fallback travel budget when the SpellDef declares no `length`.
const DEFAULT_LENGTH: float = 760.0
const DEFAULT_DAMAGE: int = 105
## How long the seam keeps smouldering after the crest has finished.
const AFTERGLOW: float = 0.9

# ---------------------------------------------------------------- WORK COUNTERS
## Deterministic tallies, not timings — `Performance.TIME_PROCESS` excludes `_draw`
## and wall-clock here is non-monotonic by ~20x. They also make "the rupture
## actually travelled" assertable: "nothing was hit twice" is trivially true of a
## rupture that never moved, and an invariant true of an empty result is not one.
var crest_steps: int = 0
var bodies_thrown: int = 0
var terrain_bites: int = 0
var cover_smashed: int = 0

var _color: Color = Color(0.78, 0.55, 0.28)
var _damage: int = DEFAULT_DAMAGE
var _length: float = DEFAULT_LENGTH
var _origin: Vector2 = Vector2.ZERO
var _dir_sign: float = 1.0
var _path: PackedVector2Array = PackedVector2Array()
var _cumulative: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0
var _travelled: float = 0.0
var _elapsed: float = 0.0
var _done_at: float = -1.0
var _hit: Dictionary = {}
var _next_crater: float = 0.0
var _seed: int = 0


## The launch impulse, derived from the shared slam threshold rather than restated.
## A hand-copied number here would drift the day `SlamPhysics` is retuned and the
## only symptom would be bodies landing silently.
static func knockback() -> float:
	return SlamPhysics.MIN_SLAM_SPEED * KNOCKBACK_FACTOR


## Seconds the crest needs to cover `distance`. Pure, so the suite can pin the
## whole timeline without running one.
static func travel_time(distance: float) -> float:
	return maxf(distance, 0.0) / TRAVEL_SPEED


## THE HEX ENTRY POINT. Fixed signature shared by every spell on the
## `SpellDef.Kind.HEX` fork — see `SpellCaster.HEX_SCRIPTS`.
func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_color = color
	_seed = randi()
	if spell != null:
		_damage = maxi(spell.damage, 1)
		if spell.length > 0.0:
			_length = spell.length
	_origin = SpellWorld.floor_point(origin, 260.0, [], self)
	_dir_sign = 1.0 if target.x >= origin.x else -1.0
	# ⚠ WORLD SPACE. A spectacle parks at the arena origin — `global_position` is
	# (0, 0), NOT where the effect is — so every point below is absolute.
	global_position = Vector2.ZERO
	_build_path()
	# THE SUMMONING CIRCLE, flat on the floor at the caster's feet: this is where
	# the ground splits, and an ULT-shelf sigil is the widest in the game.
	SpellSigil.open(self, _origin, color, 1.0, false, Vector2.RIGHT, true, 0.18,
		SEAM_TELL + travel_time(_total) + AFTERGLOW)
	SpellDrops.sfx("earth_pillar", -2.0, 0.10, 0.72)
	Juice.epic_moment({"strength": 1.2, "shake": 8.0, "sfx": "ult_eruption"})
	queue_redraw()


## Sample the floor the rupture will run along, ONCE. Two honest degradations:
##
##   THE PIT RULE — `SpellWorld.ground_path` stops at the first x with no floor
##   under it and returns what it found. That truncation IS the counterplay: the
##   fault stops at the lip instead of drawing itself across thin air.
##
##   NO WORLD AT ALL — a headless harness, a capture tool, or an arena with no
##   collision has no floor to find, and the pit rule would then be
##   indistinguishable from "the level ended". `SpellWorld.has_world` separates
##   the two, and the no-world case falls back to a flat line at the caster's own
##   y so the spell still runs and stays testable.
func _build_path() -> void:
	var to: Vector2 = _origin + Vector2(_dir_sign * _length, 0.0)
	if SpellWorld.has_world(self):
		_path = SpellWorld.ground_path(_origin, to, PATH_SAMPLES, 260.0, [], self)
	if _path.size() < 2:
		_path = PackedVector2Array()
		for i: int in PATH_SAMPLES:
			var t: float = float(i) / float(PATH_SAMPLES - 1)
			_path.append(_origin.lerp(to, t))
	_cumulative = PackedFloat32Array()
	_cumulative.append(0.0)
	for i: int in range(1, _path.size()):
		_total += _path[i].distance_to(_path[i - 1])
		_cumulative.append(_total)


## The crest's world point at `d` px along the sampled floor. Linear within a
## segment, which at 26 samples over 760 px is a ~30 px step — finer than the band
## is wide, so the crest never visibly snaps.
func point_at(d: float) -> Vector2:
	if _path.size() == 0:
		return _origin
	if _path.size() == 1 or d <= 0.0:
		return _path[0]
	if d >= _total:
		return _path[_path.size() - 1]
	for i: int in range(1, _cumulative.size()):
		if d <= _cumulative[i]:
			var span: float = _cumulative[i] - _cumulative[i - 1]
			var t: float = 0.0 if span <= 0.0 else (d - _cumulative[i - 1]) / span
			return _path[i - 1].lerp(_path[i], t)
	return _path[_path.size() - 1]


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < SEAM_TELL:
		queue_redraw()
		return          # the seam is lit, the crest has not moved: THE TELL
	if _done_at < 0.0:
		var before: float = _travelled
		_travelled = minf(_travelled + TRAVEL_SPEED * delta, _total)
		if _travelled > before:
			crest_steps += 1
			_sweep(point_at(before), point_at(_travelled))
		if _travelled >= _total:
			_done_at = _elapsed
			_heave()
	elif _elapsed - _done_at >= AFTERGLOW:
		queue_free()
		return
	queue_redraw()


## Everything the crest passed under between two points this frame. Swept from the
## PREVIOUS crest position, never point-tested at the new one: at 620 px/s a point
## test skips a 10 px-wide body entirely on a 60 fps frame, and "the ult passed
## through me" is the worst bug this spell could ship with.
func _sweep(from: Vector2, to: Vector2) -> void:
	var mid: Vector2 = (from + to) * 0.5
	var half: float = absf(to.x - from.x) * 0.5 + CREST_HALF_WIDTH
	for body: Node in SpellTargets.hostiles(self, StringName(target_group)):
		_maybe_throw(body, mid, half, from, to)
	for prop: Node in SpellTargets.hostiles(self, &"destructible"):
		_maybe_smash(prop, mid, half, from, to)
	_tear(from, to)


## Is `body` standing on the seam the crest just crossed? A BOX test, not a radius:
## the whole identity of this spell is that it is a ground wave with a ceiling, and
## a radius would quietly make it catch things it had no business catching.
func caught(pos: Vector2, mid: Vector2, half: float, from: Vector2, to: Vector2) -> bool:
	if absf(pos.x - mid.x) > half:
		return false
	# Floor line under this x, interpolated between the two crest samples.
	var span: float = to.x - from.x
	var t: float = 0.0 if absf(span) < 0.0001 else clampf((pos.x - from.x) / span, 0.0, 1.0)
	var floor_y: float = lerpf(from.y, to.y, t)
	return pos.y >= floor_y - AIR_CLEAR and pos.y <= floor_y + GROUND_SLACK


func _maybe_throw(body: Node, mid: Vector2, half: float, from: Vector2, to: Vector2) -> void:
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	if not body is Node2D:
		return
	var id: int = body.get_instance_id()
	if _hit.has(id):
		return          # one rupture, one hit per body — it passes under you once
	var pos: Vector2 = (body as Node2D).global_position
	if not caught(pos, mid, half, from, to):
		return
	_hit[id] = true
	var up: Vector2 = Vector2(_dir_sign * (1.0 - UP_BIAS), -UP_BIAS).normalized()
	var at: Vector2 = SpellTargets.aim_point(body)
	var dealt: int = SpellDeflect.resolve(body, _damage, up, at)
	if dealt <= 0:
		return
	# ⚠ `take_damage` ships two signatures (Hero one arg, Enemy two); calling the
	# wrong one THROWS and aborts the enclosing function, losing this hit and
	# everything after it. Always route through `SpellTargets.hurt`.
	SpellTargets.hurt(body, dealt, Color(_color.r, _color.g, _color.b, 1.0))
	if element_id >= 0 and body.has_method("apply_status"):
		body.apply_status(element_id)   # EARTH = Stagger, a short root
	if body.has_method("apply_knockback"):
		body.call("apply_knockback", up * knockback())
	bodies_thrown += 1
	CombatVfx.spawn_burst(get_parent(), pos,
		Color(_color.r, _color.g, _color.b, 0.9), Color(0.35, 0.28, 0.2, 0.0),
		16, 0.45, 140.0, 320.0, 1.0, 3.0, 0.0, 0.0, false, Vector2.UP, 55.0)


## Cover standing on the seam. `damage_at` where it exists, so a crate splits where
## the fault crossed it rather than vanishing uniformly.
func _maybe_smash(prop: Node, mid: Vector2, half: float, from: Vector2, to: Vector2) -> void:
	if prop == null or not is_instance_valid(prop) or not prop is Node2D:
		return
	var id: int = prop.get_instance_id()
	if _hit.has(id):
		return
	var pos: Vector2 = (prop as Node2D).global_position
	if not caught(pos, mid, half, from, to):
		return
	_hit[id] = true
	if prop.has_method("damage_at"):
		prop.call("damage_at", _damage, pos, Vector2.UP)
	else:
		SpellTargets.hurt(prop, _damage, _color)
	cover_smashed += 1


## Tear the floor. Purely cosmetic — nothing in the game reads a crater — so this
## is the first thing thinned at LOW, and `GroundCrater` / `ScorchDecal` already
## cap and skip themselves under budget pressure.
func _tear(from: Vector2, to: Vector2) -> void:
	var stride: float = CRATER_STRIDE_LOW if TuningConfig.quality_is_low() else CRATER_STRIDE
	while _next_crater <= _travelled:
		var at: Vector2 = point_at(_next_crater)
		GroundCrater.spawn(get_parent(), at, 26.0, true)
		ScorchDecal.spawn(get_parent(), at, 20.0, "crack", Color(0.22, 0.17, 0.12, 0.55), 6.0)
		terrain_bites += 1
		_next_crater += stride
	CombatVfx.spawn_burst(get_parent(), (from + to) * 0.5,
		Color(0.62, 0.52, 0.38, 0.85), Color(0.45, 0.38, 0.28, 0.0),
		10, 0.4, 90.0, 240.0, 1.2, 3.4, 20.0, 60.0, false, Vector2.UP, 40.0)


## The far end. The fault does not simply stop — it opens.
func _heave() -> void:
	var at: Vector2 = point_at(_total)
	GroundCrater.spawn(get_parent(), at, 52.0, true)
	CombatVfx.spawn_burst(get_parent(), at,
		Color(0.7, 0.58, 0.42, 0.95), Color(0.4, 0.33, 0.24, 0.0),
		26, 0.6, 180.0, 420.0, 1.4, 4.0, 20.0, 70.0, false, Vector2.UP, 50.0)
	Juice.on_hit({"dir": Vector2.UP, "shake": 10.0, "sfx": "rubble",
		"sfx_pitch": 0.08, "hitstop": 0.05})
	# ⚠ THE RUPTURE HAD NO IMPACT FRAME AT ALL — the other ULT that ended on
	# nothing. Same cause as Heaven's Wrath: `epic_moment` at cast spends the
	# camera and the freeze but takes a `frame` flag this spell never passed, so
	# the Juggernaut's ultimate reached its heave and simply stopped.
	#
	# Straight off the ladder, WITHOUT a style override: an ULT carrying an element
	# gets COLOR_FIELD, which floods the screen with earth's own ochre. That is the
	# deliberate opposite of Heaven's Wrath's black SILHOUETTE — the two ults fixed
	# in this pass now end on genuinely different screens, which is the entire
	# argument in ImpactFrame's header ("a spell whose payoff is a readable SHAPE
	# wants a BLACK frame; an elemental payoff wants its own colour").
	#
	# Fired at the heave, not at the cast: the seam travelling is anticipation and
	# the ground coming up is the payoff. Camera + freeze zeroed — `on_hit` above
	# already fired all four and a second set double-punches.
	Juice.tier_frame(SpellTier.Tier.ULT, at, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


# --------------------------------------------------------------------- THE LOOK
## ⚠ MUST DEGRADE AT `graphics_quality = LOW` (the phone preview, a hard rule).
## A travelling rupture is a prime candidate to blow the effect budget, so LOW
## drops the dust plume and the strata teeth and lays craters at a sparser stride.
## The SEAM and the CREST are drawn identically at both settings: the seam is the
## telegraph and the crest is where the damage is, and thinning either would be a
## fairness change rather than a fidelity one.
func _draw() -> void:
	var low: bool = TuningConfig.quality_is_low()
	if _path.size() < 2:
		return
	var tell: float = clampf(_elapsed / SEAM_TELL, 0.0, 1.0)
	_draw_seam(tell, low)
	if _elapsed < SEAM_TELL:
		return
	_draw_crest(low)


## The whole path, lit before anything moves. This is the spell showing you its
## future, and it stays lit (dimmer) behind the crest as the scar it left.
## ⚠ IT MUST NOT READ AS A BEAM. A first pass drew the seam as a straight polyline
## and the capture came back looking exactly like a laser lying on the floor —
## which is the one confusion this whole spell exists to avoid. So the seam is
## JAGGED: a per-sample stagger, a dark gap drawn under the glow (a split has a
## hole in it, a beam does not), and broken strata teeth pushed up along its
## length. The jitter is derived from the sample index, never from time, so the
## crack does not crawl.
func _draw_seam(tell: float, low: bool) -> void:
	var crack: PackedVector2Array = PackedVector2Array()
	for i: int in _path.size():
		var jag: float = (_hash01(_seed + i * 313) - 0.5) * 9.0
		if i == 0 or i == _path.size() - 1:
			jag = 0.0
		crack.append(_path[i] + Vector2(0.0, -1.0 + jag))
	# The GAP: a dark, wider stroke under everything, so the seam is a hole in the
	# floor with light in it rather than a line laid on top of the floor.
	draw_polyline(crack, Color(0.03, 0.02, 0.02, 0.55 + 0.35 * tell),
		5.0 + 5.0 * tell, true)
	draw_polyline(crack, Color(_color.r * 0.9, _color.g * 0.6, _color.b * 0.35,
		0.22 + 0.5 * tell), 2.4 + 2.6 * tell, true)
	# The molten core of the split.
	draw_polyline(crack, Color(1.5, 0.85, 0.35, 0.30 + 0.55 * tell), 1.2 + 1.6 * tell, true)
	if low:
		return
	# Strata teeth: broken slabs shouldered up along the crack, alternating sides.
	for i: int in _path.size():
		if i % 2 == 1:
			continue
		var p: Vector2 = _path[i] + Vector2(0.0, -1.0)
		var side: float = 1.0 if (i / 2) % 2 == 0 else -1.0
		var h: float = (7.0 + 13.0 * _hash01(_seed + i * 47)) * tell
		var w: float = 5.0 + 5.0 * _hash01(_seed + i * 91)
		var slab := PackedVector2Array([
			p + Vector2(-w, 2.0),
			p + Vector2(-w * 0.6 + side * 2.0, -h),
			p + Vector2(w * 0.7 + side * 2.0, -h * 0.7),
			p + Vector2(w, 2.0),
		])
		draw_colored_polygon(slab, Color(0.34, 0.27, 0.20, 0.75 + 0.2 * tell))
		draw_line(slab[1], slab[2], Color(0.72, 0.58, 0.40, 0.55 + 0.35 * tell), 1.4, true)


## The crest itself: a raised wedge of broken floor at the head of the split, with
## a bright fracture mouth behind it.
func _draw_crest(low: bool) -> void:
	var head: Vector2 = point_at(_travelled)
	var tail: Vector2 = point_at(maxf(_travelled - 70.0, 0.0))
	var wedge := PackedVector2Array([
		tail + Vector2(0.0, 4.0),
		head + Vector2(-_dir_sign * 6.0, -34.0),
		head + Vector2(_dir_sign * CREST_HALF_WIDTH, 6.0),
	])
	draw_colored_polygon(wedge, Color(0.42, 0.34, 0.25, 0.95))
	draw_polyline(wedge + PackedVector2Array([wedge[0]]),
		Color(1.25, 0.9, 0.5, 0.9), 2.0, true)
	# The mouth: a hot line under the wedge, the "the floor is open" read.
	draw_line(tail, head, Color(1.6, 0.95, 0.4, 0.85), 4.0, true)
	if low:
		return
	# Dust plume off the head. Garnish, first thing off.
	for i: int in 7:
		var f: float = _hash01(_seed + i * 91 + int(_travelled * 0.05))
		var p: Vector2 = head + Vector2((f - 0.5) * 46.0, -10.0 - f * 40.0)
		draw_circle(p, 3.0 + 5.0 * f, Color(0.6, 0.5, 0.37, 0.22), true, -1.0, false)


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)
