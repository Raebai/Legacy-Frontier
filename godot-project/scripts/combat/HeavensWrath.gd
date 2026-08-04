class_name HeavensWrath
extends Node2D
## HEAVEN'S WRATH — the Stormcaller's ULT. A storm CELL, not a bolt.
##
## It replaces `tempest`, which was a BeamSpell: the fifth of five classes throwing
## the same beam down the same damage corridor. The maker's ruling was "we cannot
## have any recolours", so the replacement is not a lightning-coloured beam — it is
## WEATHER. A thunderhead parks over the ground you marked, drifts, and hammers
## down `STRIKES` separate bolts over `LIFE` seconds, each one marking where it
## will land `MARK_TELL` before it lands there.
##
## ── WHY THIS IS NOT `DivineRay` IN A DIFFERENT COLOUR ────────────────────────
## `DivineRay` is a SINGLE instantaneous vertical pillar on a fixed point — one
## charge, one column, done — and it is already used twice (`judgment`,
## `colossus_pillar`). Reusing it here would have produced a third identical
## silhouette. The shape had to differ, and it does, in three ways that change how
## the spell is played:
##
##   1. REPEATING. Five strikes, not one. The spell is a period of danger rather
##      than an instant, so it AREA-DENIES: it is worth casting on ground you want
##      nobody standing on for three seconds.
##   2. TRACKING. Each strike re-marks — the storm looks down and picks whoever is
##      under it NOW. Standing still through it is not survivable; a beam does not
##      care where you go once it has fired.
##   3. DRIFTING. The cell wanders (`DRIFT`), so its own footprint moves and the
##      safe ground changes under you. Nothing else in the roster does that.
##
## ── TRACKING IS NOT AUTO-AIM, and the distinction is load-bearing ────────────
## The no-auto-aim rule is about the PLAYER's aim never being bent toward a body,
## and it is not bent here: the player aims the CELL, at the ground, and the cell
## goes exactly where it was pointed. What the storm then does inside its own
## footprint is choose which of the bodies already standing under it to mark — and
## it commits that mark to a FIXED WORLD POINT `MARK_TELL` seconds before the bolt
## arrives. The bolt does not follow you. It falls where you were when the sky
## looked. With nobody under the cell it strikes bare ground anyway, which is the
## honest tell that this is weather and not a homing missile.
##
## ── THE TELL AND THE COUNTERPLAY (the locked "everything is dodgeable" rule) ──
##   TELL         Two layers. The cell itself is a large, obvious, drifting cloud —
##                you can see the dangerous ground from across the arena. Then each
##                individual strike lights a shrinking ring on the floor and a
##                charging filament in the cloud directly above it, `MARK_TELL`
##                (0.45 s) before the bolt.
##   COUNTERPLAY  Keep moving and every mark misses — a mark is a snapshot, not a
##                lock. Leave the cell (`CELL_RADIUS`) and you cannot be marked at
##                all. The gap between strikes (`STRIKE_GAP`) is the window to do
##                either.
##
## ⚠ ELEMENT IS DECLARED, NEVER INFERRED — LIGHTNING here, so a struck body is
## Shocked and the cell sits on the right side of every LIGHTNING reaction row.

# ------------------------------------------------------------------- IDENTITY
## Stamped by `SpellCaster._stamp()`. All five DECLARED — `set()` on an undeclared
## property is a silent no-op, and an un-stamped spectacle is quietly inert in the
## whole reaction system without erroring once.
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.LIGHTNING
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## DESCENT — something falls onto this spot. Stated here because `SpellSigil`'s
## script-keyed table lives in a file this agent does not own; the `sigil_motif`
## override is the sanctioned route (`SpellSigil._motif_of`).
var sigil_motif: int = MagicCircle.Motif.DESCENT

# ------------------------------------------------------------------- THE STORM
## How long the cell hangs around. Long enough to be terrain, short enough that
## it is not a permanent no-go zone.
const LIFE: float = 3.4
## Bolts over that life.
const STRIKES: int = 5
## When the first mark is placed, and the gap between marks after it. The gap IS
## the dodge window: it is the time you have to leave a mark you can already see.
const FIRST_MARK: float = 0.30
const STRIKE_GAP: float = 0.62
## How long a mark burns on the floor before the bolt lands on it. THE TELL.
const MARK_TELL: float = 0.45
## How far from the cell's centre the storm can reach — the footprint drawn IS the
## footprint that can mark you. This is the DEFAULT; the SpellDef's `radius`
## overrides it, so the number in the spell tree is not a decoration that the
## spectacle quietly ignores.
const CELL_RADIUS: float = 210.0
## How fast the cell wanders sideways, px/s. Slow: the ground shifting under you
## should be noticed, not raced.
const DRIFT: float = 34.0
## How high above the marked ground the cloud base sits.
##
## ⚠ TUNED BY LOOKING, not guessed. The first pass used 300, which on the
## one-screen floors this game ships put the whole thunderhead off the top of the
## frame and behind the HUD — the storm's single biggest tell was invisible in
## every capture. 190 keeps the cell above head height (the bolt still has a real
## fall) and inside the frame.
const CLOUD_HEIGHT: float = 190.0
## How far DOWN the storm looks for the ground it is claiming, and for the ground
## under each mark.
##
## ⚠ THE OLD NUMBERS WERE 320 (cell) AND 260 (mark) AND THEY WERE TOO SHORT. A
## `floor_point` that finds nothing hands the point straight back unchanged, so a
## cursor held anywhere higher than ~260 px above the floor left the mark — and
## therefore the bolt, and therefore the damage — sitting in open air, silently.
## That is the maker's *"hit the bottom as needed"* on a spell that already
## believed it was floor-aware. One constant now, because two probes answering the
## same question at two different depths is how they drift apart.
##
## It is still a BOUND: below it there is no floor, and the fallback is documented
## at each call site. UNTESTED GUESS.
const FLOOR_DROP: float = 900.0
## Damage radius at a mark. Deliberately much smaller than the cell: being under
## the storm is dangerous, being on the mark is fatal.
const BOLT_RADIUS: float = 54.0
## How long one bolt stays drawn.
const BOLT_FLASH: float = 0.14
const KNOCKBACK: float = 190.0
const DEFAULT_DAMAGE: int = 42
## Cloud lobes drawn, and the cheap count that ships to the phone.
const LOBES: int = 11
const LOBES_LOW: int = 5

# ---------------------------------------------------------------- WORK COUNTERS
## Deterministic tallies, not timings — `Performance.TIME_PROCESS` excludes `_draw`
## and wall-clock here is non-monotonic by ~20x, so the suite asserts what the
## storm DID. They also make "the storm actually fired" assertable, which an
## invariant like "no bolt landed off-mark" is not: that is trivially true of a
## storm that never struck.
var marks_placed: int = 0
var bolts_fired: int = 0
var bodies_struck: int = 0
var marks_on_bodies: int = 0

var _cell: Vector2 = Vector2.ZERO
var _radius: float = CELL_RADIUS
var _ground_y: float = 0.0
var _color: Color = Color(0.55, 0.75, 1.0)
var _damage: int = DEFAULT_DAMAGE
var _elapsed: float = 0.0
var _drift_sign: float = 1.0
var _seed: int = 0
var _next_mark: int = 0
## Each: {pos, land_at, fired, flash}
var _marks: Array = []


## When mark `i` is PLACED, and when its bolt LANDS. Pure and derived, so a
## retune of the cadence cannot leave a stale schedule behind in the tests.
static func mark_time(i: int) -> float:
	return FIRST_MARK + float(i) * STRIKE_GAP


static func land_time(i: int) -> float:
	return mark_time(i) + MARK_TELL


## THE HEX ENTRY POINT. Fixed signature shared by every spell on the
## `SpellDef.Kind.HEX` fork — see `SpellCaster.HEX_SCRIPTS`.
func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_color = color
	_seed = randi()
	if spell != null:
		_damage = maxi(spell.damage, 1)
		if spell.radius > 0.0:
			_radius = spell.radius
	# The cell hangs over the ground under the aim. Over a pit `floor_point` returns
	# the aim unchanged, which is the right answer for weather: the storm still
	# forms, it just has nothing beneath it to strike.
	_cell = SpellWorld.floor_point(target, FLOOR_DROP, [], self)
	_ground_y = _cell.y
	# Drift AWAY from the caster, so the storm is walking off with the ground it
	# took rather than rolling back over its own thrower.
	_drift_sign = 1.0 if target.x >= origin.x else -1.0
	# ⚠ WORLD SPACE. A spectacle parks at the arena origin — `global_position` is
	# (0, 0), NOT where the effect is — so every point below is absolute.
	global_position = Vector2.ZERO
	# THE SUMMONING CIRCLE, laid flat over the ground the storm is claiming and
	# scaled to the cell's own footprint rather than to the ULT shelf's default.
	SpellSigil.open(self, _cell, color, _radius / SpellSigil.RADIUS_ULT,
		false, Vector2.RIGHT, true, 0.16, LIFE)
	SpellDrops.sfx("thunder", -4.0, 0.10, 0.72)
	Juice.epic_moment({"strength": 1.1, "shake": 7.0})
	Juice.zoom_pull_camera(0.22, LIFE * 0.5, 0.20, 0.7)  # pull back: the sky matters now
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	_cell.x += _drift_sign * DRIFT * delta
	while _next_mark < STRIKES and _elapsed >= mark_time(_next_mark):
		_place_mark(_next_mark)
		_next_mark += 1
	for mark: Dictionary in _marks:
		if bool(mark["fired"]):
			continue
		if _elapsed >= float(mark["land_at"]):
			mark["fired"] = true
			mark["flash"] = _elapsed
			_strike(mark["pos"] as Vector2)
	if _elapsed >= LIFE:
		_end()
		return
	queue_redraw()


## Look down through the cell and commit ONE point. See the header for why this is
## tracking and not auto-aim: the point is fixed here, `MARK_TELL` before the bolt.
func _place_mark(_i: int) -> void:
	var pick: Node = SpellTargets.nearest(_cell, _radius,
		SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self)
	var at: Vector2 = Vector2.ZERO
	if pick != null and pick is Node2D:
		at = (pick as Node2D).global_position
		marks_on_bodies += 1
	else:
		# Nobody home. It strikes bare ground anyway — the storm is not waiting for
		# a target, which is exactly what makes it weather.
		at = _cell + Vector2(_hash01(_seed + _next_mark * 53) * _radius
			- _radius * 0.5, 0.0)
	# Drop the mark to the floor so the bolt lands ON something. `floor_point`, not
	# `floor_below` + a `hit` branch, and that IS the decision: on a miss the point
	# comes back untouched, which is what we want here and nowhere else in this
	# sweep. When the mark came from a BODY that point is the body itself, so an
	# airborne target still gets struck rather than having its bolt cancelled —
	# unlike a falling rock, a bolt does not need ground to arrive on.
	at = SpellWorld.floor_point(at, FLOOR_DROP, [], self)
	_marks.append({
		"pos": at,
		"land_at": _elapsed + MARK_TELL,
		"fired": false,
		"flash": -1.0,
	})
	marks_placed += 1
	SpellDrops.sfx("zap_arc", -9.0, 0.14, 1.35)


## One bolt. Everything inside `BOLT_RADIUS` of the committed point.
func _strike(at: Vector2) -> void:
	bolts_fired += 1
	# `SpellTargets.in_radius` over `hostiles()` — the sanctioned selector. It drops
	# the caster's own body (friendly fire points every spell at the shared `mortal`
	# group) and measures to the SILHOUETTE, not to a body's origin.
	for body: Node in SpellTargets.in_radius(at, BOLT_RADIUS,
			SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self):
		var hit: Vector2 = SpellTargets.aim_point(body)
		var dealt: int = SpellDeflect.resolve(body, _damage, Vector2.DOWN, hit)
		if dealt <= 0:
			continue
		# ⚠ `take_damage` ships two signatures (Hero one arg, Enemy two); the wrong
		# one THROWS and aborts the enclosing function. Always via `hurt`.
		SpellTargets.hurt(body, dealt, Color(_color.r, _color.g, _color.b, 1.0))
		if element_id >= 0 and body.has_method("apply_status"):
			body.apply_status(element_id)
		if body.has_method("apply_knockback"):
			body.call("apply_knockback", Vector2(0.0, 1.0) * KNOCKBACK)
		bodies_struck += 1
	for prop: Node in SpellTargets.in_radius(at, BOLT_RADIUS,
			SpellTargets.hostiles(self, &"destructible"), [caster_node], self):
		if prop.has_method("damage_at"):
			prop.call("damage_at", _damage,
				(prop as Node2D).global_position if prop is Node2D else at, Vector2.DOWN)
		else:
			SpellTargets.hurt(prop, _damage, _color)
	CombatVfx.spawn_burst(get_parent(), at,
		Color(1.4, 1.5, 1.9, 0.95), Color(0.5, 0.7, 1.0, 0.0),
		18, 0.35, 120.0, 300.0, 0.5, 1.6, 0.0, 0.0, true)
	ScorchDecal.spawn(get_parent(), at, 22.0, "crack", Color(0.3, 0.35, 0.5, 0.5), 3.0)
	Juice.on_hit({"dir": Vector2.DOWN, "shake": 6.0, "kick": 5.0,
		"sfx": "zap", "sfx_pitch": 0.10, "hitstop": 0.035})


func _end() -> void:
	SpellDrops.sfx("thunder", -8.0, 0.12, 0.9)
	queue_free()


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


# --------------------------------------------------------------------- THE LOOK
## ⚠ MUST DEGRADE AT `graphics_quality = LOW` (the phone preview, a hard rule).
## LOW drops the rain curtain and thins the cloud from `LOBES` to `LOBES_LOW`.
## The mark rings, the charging filament and the bolt itself are drawn identically
## at both settings: they are the telegraph, and thinning a telegraph is a
## fairness change rather than a fidelity one.
func _draw() -> void:
	var low: bool = TuningConfig.quality_is_low()
	var base_y: float = _ground_y - CLOUD_HEIGHT
	_draw_cloud(base_y, low)
	if not low:
		_draw_rain(base_y)
	for mark: Dictionary in _marks:
		if bool(mark["fired"]):
			_draw_bolt(mark, base_y)
		else:
			_draw_mark(mark, base_y)


## A churning thunderhead: overlapping lobes, a lit crown, and an UNDERLIT rim in
## the storm's own colour so the charged base reads against a dark arena.
##
## ⚠ THE FIRST PASS DREW IT IN NEAR-BLACK (0.10, 0.12, 0.20) and it was invisible
## on screen — a cloud is only a tell if you can see it. The body is a mid slate
## now, the crown catches light from above, and the base carries an emissive lip:
## three tones, which is the minimum for a mass to read as a volume rather than a
## smudge.
func _draw_cloud(base_y: float, low: bool) -> void:
	var fade: float = clampf((LIFE - _elapsed) / 0.6, 0.0, 1.0) \
		* clampf(_elapsed / 0.35, 0.0, 1.0)
	var lobes: int = LOBES_LOW if low else LOBES
	for i: int in lobes:
		var f: float = float(i) / float(lobes)
		var x: float = _cell.x + (f - 0.5) * _radius * 2.0
		var wob: float = sin(_elapsed * 1.6 + float(i) * 1.9 + float(_seed % 61)) * 12.0
		var r: float = _radius * (0.30 + 0.22 * _hash01(_seed + i * 29))
		var c := Vector2(x, base_y + wob)
		# Underlit lip first, so the lobes above sit ON it.
		draw_circle(c + Vector2(0.0, r * 0.20), r * 0.92,
			Color(_color.r * 0.45, _color.g * 0.45, _color.b * 0.55, 0.30 * fade),
			true, -1.0, false)
		draw_circle(c, r, Color(0.19, 0.21, 0.30, 0.92 * fade), true, -1.0, false)
		draw_circle(c + Vector2(-r * 0.12, -r * 0.38), r * 0.68,
			Color(0.30, 0.33, 0.43, 0.90 * fade), true, -1.0, false)
	# The internal flicker — the cell is charged, and it says so.
	var pulse: float = 0.5 + 0.5 * sin(_elapsed * 9.0)
	for i: int in (3 if low else 6):
		var a: Vector2 = Vector2(_cell.x + (_hash01(_seed + i * 17) - 0.5) * _radius * 1.6,
			base_y - 18.0)
		var b: Vector2 = a + Vector2((_hash01(_seed + i * 41) - 0.5) * 90.0, 34.0)
		draw_line(a, b, Color(_color.r, _color.g, _color.b, (0.12 + 0.22 * pulse) * fade),
			1.4, true)


## Rain under the cell. Pure garnish — first thing off at LOW — but it is what
## makes the footprint read as weather from across the arena.
func _draw_rain(base_y: float) -> void:
	for i: int in 34:
		var fx: float = _hash01(_seed + i * 131)
		var speed: float = 620.0 + 260.0 * _hash01(_seed + i * 53 + 3)
		var span: float = _ground_y - base_y
		var y: float = fposmod(_hash01(_seed + i * 977 + 7) * span + _elapsed * speed, span)
		var p := Vector2(_cell.x - _radius + fx * _radius * 2.0, base_y + y)
		draw_line(p, p + Vector2(-2.0, 16.0),
			Color(0.62, 0.75, 0.95, 0.18), 1.0, true)


## A committed mark: a ring on the floor closing toward the strike, plus a
## filament in the cloud directly above it so the eye is led up-then-down.
func _draw_mark(mark: Dictionary, base_y: float) -> void:
	var at: Vector2 = mark["pos"]
	var f: float = clampf(1.0 - (float(mark["land_at"]) - _elapsed) / MARK_TELL, 0.0, 1.0)
	draw_set_transform(at, 0.0, Vector2(1.0, 0.42))
	draw_arc(Vector2.ZERO, BOLT_RADIUS, 0.0, TAU, 30,
		Color(0.6, 0.8, 1.0, 0.30 + 0.25 * f), 1.8, true)
	draw_arc(Vector2.ZERO, BOLT_RADIUS * (1.0 - 0.72 * f), 0.0, TAU, 30,
		Color(1.3, 1.45, 1.9, 0.55 + 0.4 * f), 2.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(Vector2(at.x, base_y + 6.0), Vector2(at.x, base_y + 34.0 + 40.0 * f),
		Color(_color.r, _color.g, _color.b, 0.25 + 0.55 * f), 1.2 + 2.0 * f, true)


## The bolt: a jagged polyline from the cloud base to the mark, plus a flat flash
## on the floor. A LINE THAT KINKS, deliberately — a smooth column is the picture
## `DivineRay` already owns twice over.
func _draw_bolt(mark: Dictionary, base_y: float) -> void:
	var age: float = _elapsed - float(mark["flash"])
	if age > BOLT_FLASH:
		return
	var alpha: float = 1.0 - age / BOLT_FLASH
	var at: Vector2 = mark["pos"]
	var pts := PackedVector2Array()
	var steps: int = 9
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		var y: float = lerpf(base_y, at.y, t)
		var jag: float = 0.0
		if i > 0 and i < steps:
			jag = (_hash01(int(mark["flash"] * 1000.0) + i * 71) - 0.5) * 46.0 * (1.0 - t)
		pts.append(Vector2(lerpf(at.x, at.x, t) + jag, y))
	draw_polyline(pts, Color(0.7, 0.85, 1.2, 0.85 * alpha), 8.0 * alpha + 1.0, true)
	draw_polyline(pts, Color(1.6, 1.7, 2.0, 0.95 * alpha), 3.0 * alpha + 0.8, true)
	draw_set_transform(at, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, BOLT_RADIUS * (0.5 + 0.9 * (1.0 - alpha)),
		Color(1.3, 1.5, 1.95, 0.5 * alpha), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
