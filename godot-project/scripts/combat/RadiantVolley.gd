class_name RadiantVolley
extends Node2D
## RADIANT VOLLEY — the Cleric's damage signature, and the maker's "archer" ask
## ("what about like archer, can they fire multi beams and cool abilities").
##
## Holy lances RACK themselves on an arc behind the caster, fanned across the aim,
## and settle into the rank as they arm — then fire FORWARD IN PARALLEL, three
## escalating waves of 5, then 7, then 9. They PIERCE: a lance passes through every
## body on its lane and hurts each of them once, so a rank of enemies lined up
## along the aim is the shot this spell is built to reward.
##
## ── WHY THIS IS NOT `RuneOrbs` WITH MORE ORBS ────────────────────────────────
## The maker's ruling was "no recolours", and `RuneOrbs` is the multi-projectile
## substrate that a lazy version of this spell would have been. Four structural
## differences, each of which changes how the spell is PLAYED and not just how it
## looks:
##
##   1. RuneOrbs fans OUTWARD from one muzzle point — every orb diverges, so the
##      spread grows with distance and the volley is a shotgun. These fire
##      PARALLEL from an arc of separate origins, so the band is the same width
##      at 60 px as at 700 px. It is a RANK, not a cone.
##   2. RuneOrbs pop on the first body they touch — one orb, one victim. A lance
##      pierces, keeps its own hit-set, and is worth more the more bodies share
##      its lane. Positioning is the damage dial.
##   3. RuneOrbs is one wave. This is three, escalating, over ~0.9 s: the volley
##      has a shape in TIME, which is the window the target dodges through.
##   4. The rack IS the tell. The lances exist, visibly, before they are dangerous.
##
## ── THE TELL AND THE COUNTERPLAY (the locked "everything is dodgeable" rule) ──
##   TELL         Each wave's lances materialise above the rack arc behind the
##                caster and SETTLE onto it over `RACK_HOLD`, brightening as they
##                arm. Where a lance is sitting when it stops moving is exactly the
##                lane it will fly down. The holy sigil opens with the first rack.
##   COUNTERPLAY  The band is finite (`band_half()` px each side of the aim axis)
##                and it never widens, so ONE sidestep perpendicular to the aim
##                leaves it for good — and the three-wave cadence means there are
##                two more chances to leave after the first wave has shown you
##                exactly where the lane is. Lances also die on geometry, so cover
##                works. What does NOT save you is standing behind a friend: they
##                pierce.
##
## ⚠ ELEMENT IS DECLARED, NEVER INFERRED. `SpellCaster.resolve_element()` maps the
## effect string "holy" onto LIGHTNING — a fallback from before HOLY existed as an
## element — so a def that leaves `element` at -1 lands a Shock instead of a
## Radiance burn and drops out of every HOLY reaction row. The SpellDef states
## `element = Elements.Element.HOLY`; this file's default matches it so a bare
## instantiation (capture tool, test) behaves the same as a real cast.

# ------------------------------------------------------------------- IDENTITY
## Stamped by `SpellCaster._stamp()` at cast time. All five are DECLARED because
## `set()` on an undeclared property is a silent no-op in Godot 4: the write goes
## nowhere, the spectacle keeps its defaults, and nothing errors. A missing
## `caster_node` in particular makes an effect "unowned", which satisfies neither
## `require_owner: "same"` nor `"different"` and quietly removes it from the
## entire reaction system.
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.HOLY
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## The sigil's inner figure. `SpellSigil.MOTIF_BY_SCRIPT` is keyed on script file
## and this script is not in it (that table lives in a file this agent does not
## own), so the stated-answer override is the sanctioned route — see
## `SpellSigil._motif_of`. LANCE, because that is exactly what comes out.
var sigil_motif: int = MagicCircle.Motif.LANCE

# ----------------------------------------------------------------- THE VOLLEY
## Lances per wave. Escalating on purpose: the first wave is a warning you can
## still act on, the last is the one that punishes having stayed.
const WAVES: Array[int] = [5, 7, 9]
## Seconds between one wave racking and the next racking.
const WAVE_GAP: float = 0.30
## How long a racked wave hangs before it fires. THE TELL. Long enough to be a
## decision, short enough that the volley still reads as a volley.
const RACK_HOLD: float = 0.18
## Micro-stagger between adjacent lances inside one wave, so a wave STREAMS out
## across a few frames instead of arriving as a flat wall.
const LANCE_STAGGER: float = 0.016
## Radius of the rack arc, measured from the caster, and the angle it spans.
##
## ⚠ THE ARC IS CENTRED ON THE AIM AXIS AND HAS NO VERTICAL BIAS, deliberately.
## An earlier pass floated the whole rack `RACK_LIFT` px above the caster, which
## quietly moved every lane that far off the aim: you pointed at a chest and the
## entire volley flew over the head. The rack is now a fan swept BACKWARD around
## the aim (the centre lane sits exactly `RACK_RADIUS` px behind the caster and
## flies exactly down the aim), so where you point is where the rank goes. The
## lift survives only as a DRAW-time settle — see `RACK_LIFT`.
##
## Together these two — and nothing else — define the width of the firing band;
## see `band_half()`, which is what the tests and the draw both read.
const RACK_RADIUS: float = 96.0
const RACK_ARC: float = 0.72
## COSMETIC ONLY. How far above its true lane a racked lance is drawn when it
## first materialises; it eases to zero across `RACK_HOLD` so the lances visibly
## SETTLE into the rank. It is applied in `_draw_racked` and nowhere else — it must
## never touch a launch position, which is the bug described above.
const RACK_LIFT: float = 40.0
## Travel speed. Fast — a lance is a loosed arrow, not a drifting mote.
const SPEED: float = 1150.0
## Radius at which a lance registers a body, on top of that body's own
## `hit_margin()`. Deliberately tight: the band is the aim, not the hitbox.
const HIT_RADIUS: float = 13.0
## Drawn length of a lance's shaft. Long and thin — a spear silhouette is what
## separates this at a glance from `RuneOrbs`' round motes.
const LANCE_LEN: float = 42.0
## Fallback travel budget when the SpellDef declares no `length`.
const DEFAULT_REACH: float = 760.0
## Outward shove on a pierced body. Small: a lance passes THROUGH, it does not
## carry you — being shoved out of the lane would defeat the piercing fantasy.
const PIERCE_KNOCKBACK: float = 90.0

# ---------------------------------------------------------------- WORK COUNTERS
## Deterministic tallies, not timings. `Performance.TIME_PROCESS` excludes
## `_draw` and wall-clock in this harness is non-monotonic by ~20x, so the suite
## asserts what the spell DID rather than how long it took — and an invariant
## that is trivially true of an empty volley ("no lance misbehaved") is not an
## invariant, so these also make "at least N lances actually flew" assertable.
var lances_fired: int = 0
var pierce_hits: int = 0
var lances_expired: int = 0
var lances_blocked: int = 0

var _color: Color = Color(1.0, 0.92, 0.55)
var _dmg: int = 14
var _reach: float = DEFAULT_REACH
var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _perp: Vector2 = Vector2.DOWN
var _anchor: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _life: float = 0.0
var _seed: int = 0
## Each: {rack, pos, prev, fire_at, alive, fired, hit (Dictionary of ids), shimmer}
var _lances: Array = []


## Half-width of the firing band, DERIVED from the rack geometry rather than
## restated as a literal — the rack arc and the band are the same fact seen twice,
## and a second number for it is exactly how two-schemes bugs start.
static func band_half() -> float:
	return RACK_RADIUS * sin(RACK_ARC * 0.5)


## Seconds a lance is alive, DERIVED from its travel budget and its speed.
static func lance_life(reach: float) -> float:
	return maxf(reach, 1.0) / SPEED


## Total lances a full volley fires — derived from `WAVES`, so retuning the ladder
## cannot leave a stale count behind.
static func volley_size() -> int:
	var n: int = 0
	for w: int in WAVES:
		n += w
	return n


## When wave `i` LAUNCHES (its rack opens `RACK_HOLD` earlier).
static func wave_launch_time(i: int) -> float:
	return float(i) * WAVE_GAP + RACK_HOLD


## THE HEX ENTRY POINT. Fixed signature shared by every spell on the
## `SpellDef.Kind.HEX` fork — see `SpellCaster.HEX_SCRIPTS`.
func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_color = color
	_seed = randi()
	if spell != null:
		_dmg = maxi(spell.damage, 1)
		if spell.length > 0.0:
			_reach = spell.length
	var aim: Vector2 = target - origin
	_dir = aim.normalized() if aim.length_squared() > 0.000001 else Vector2.RIGHT
	_perp = _dir.orthogonal()
	_origin = origin
	_anchor = origin   # see RACK_RADIUS: no vertical bias, or the aim is a lie
	# ⚠ WORLD SPACE. A spectacle parks at the arena origin — `global_position` is
	# (0, 0) and NOT where the effect is — so every point below is absolute and
	# `_draw` never leans on this node's transform.
	global_position = Vector2.ZERO
	_build_rack()
	# The volley outlives its last lance by a hair so the final spear's fade lands.
	_life = wave_launch_time(WAVES.size() - 1) \
		+ float(WAVES[WAVES.size() - 1]) * LANCE_STAGGER \
		+ lance_life(_reach) + 0.10
	# THE SUMMONING CIRCLE. Edge-on along the aim, because the volley has a
	# direction of travel and the lances leave THROUGH the gate rather than out of
	# a puddle. Held past the last launch so the gate closes behind the volley.
	SpellSigil.open(self, origin, color, 1.15, true, _dir, false, 0.15,
		wave_launch_time(WAVES.size() - 1) + 0.30)
	SpellDrops.sfx("holy_swell", -2.0, 0.08, 1.05)
	queue_redraw()


## Rack every lance of every wave up front. They exist from frame one — that is
## the tell — and simply are not dangerous until their `fire_at`.
func _build_rack() -> void:
	var base_angle: float = (-_dir).angle()
	for w: int in WAVES.size():
		var n: int = WAVES[w]
		for k: int in n:
			# lane in [-0.5, +0.5]; a one-lance wave sits dead centre.
			var lane: float = 0.0
			if n > 1:
				lane = float(k) / float(n - 1) - 0.5
			var rack: Vector2 = _anchor \
				+ Vector2.from_angle(base_angle + lane * RACK_ARC) * RACK_RADIUS
			_lances.append({
				"rack": rack,
				"pos": rack,
				"prev": rack,
				"fire_at": wave_launch_time(w) + float(k) * LANCE_STAGGER,
				"alive": true,
				"fired": false,
				"hit": {},
				"shimmer": float(_seed % 97) * 0.13 + float(w) * 1.7 + float(k) * 0.9,
			})


func _process(delta: float) -> void:
	_elapsed += delta
	# Resolved ONCE per frame, not once per lance. Twenty-one lances asking the
	# scene tree the same two questions sixty times a second is the difference
	# between a volley and a stall, and the answer cannot change mid-frame.
	var bodies: Array = SpellTargets.hostiles(self, StringName(target_group))
	var cover: Array = SpellTargets.hostiles(self, &"destructible")
	for lance: Dictionary in _lances:
		if not bool(lance["alive"]):
			continue
		var age: float = _elapsed - float(lance["fire_at"])
		if age <= 0.0:
			continue  # still racked
		if not bool(lance["fired"]):
			lance["fired"] = true
			lances_fired += 1
		lance["prev"] = lance["pos"]
		lance["pos"] = (lance["rack"] as Vector2) + _dir * SPEED * age
		if age >= lance_life(_reach):
			lance["alive"] = false
			lances_expired += 1
			continue
		_advance(lance, bodies, cover)
	if _elapsed >= _life:
		queue_free()
		return
	queue_redraw()


## One lance's frame: sweep the world, then pierce everything new on the segment.
func _advance(lance: Dictionary, bodies: Array, cover: Array) -> void:
	# ⚠ SWEPT FROM THE PREVIOUS POSITION, never point-tested at the new one. At
	# 1150 px/s a point test tunnels through anything thinner than 19 px at 60 fps,
	# which is most ledges — the exact bug `RuneOrbs` shipped with before its own
	# world sweep landed.
	var world: Dictionary = SpellWorld.first_solid(
		lance["prev"] as Vector2, lance["pos"] as Vector2, [], self)
	if bool(world["hit"]):
		lance["pos"] = world["position"]
		lance["alive"] = false
		lances_blocked += 1
		_spark(lance["pos"] as Vector2, 0.7)
		# THE ONLY TERRAIN CONTACT THIS SPELL HAS. It never dealt the ground a damage
		# number before — it stopped, sparked, and left the rock exactly as it found
		# it — so the rank punched through crates and left the wall behind them clean.
		#
		# Footprint is `HIT_RADIUS`, the lance's own 13 px, which is the width of the
		# thing that hit the rock. Not `LANCE_LEN`: 42 px is how LONG the spear is
		# along its flight, and a spear does not excavate its own length sideways.
		# It lands between the beam half-widths already in the table (11 and 21), so a
		# volley stipples a wall rather than demolishing it, which is what eight thin
		# lances look like.
		DestructibleStage.carve_area(self, _dmg, lance["pos"] as Vector2, _dir, HIT_RADIUS)
		return
	# PIERCE. Every body the segment crossed that this lance has not already hurt.
	# `SpellTargets.on_line` is the sanctioned selector: it applies the caster
	# self-exclusion (friendly fire points every spell at the shared `mortal`
	# group, and the caster is standing in it) and it measures to the SILHOUETTE
	# rather than to a body's origin.
	var span: float = (lance["prev"] as Vector2).distance_to(lance["pos"] as Vector2)
	for body: Node in SpellTargets.on_line(lance["prev"] as Vector2, _dir, span,
			HIT_RADIUS, bodies, [caster_node], self, false):
		_pierce(lance, body, false)
	for prop: Node in SpellTargets.on_line(lance["prev"] as Vector2, _dir, span,
			HIT_RADIUS, cover, [caster_node], self, false):
		_pierce(lance, prop, true)


## Hurt one body ONCE per lance. The per-lance hit-set is what makes piercing a
## reward for lining a rank up rather than a free multi-hit on a single victim.
func _pierce(lance: Dictionary, body: Node, is_cover: bool) -> void:
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	var hit: Dictionary = lance["hit"]
	var id: int = body.get_instance_id()
	if hit.has(id):
		return
	hit[id] = true
	var at: Vector2 = SpellTargets.aim_point(body)
	if is_cover:
		if body.has_method("damage_at"):
			body.call("damage_at", _dmg, at, _dir)
		else:
			SpellTargets.hurt(body, _dmg, _color)
		pierce_hits += 1
		_spark(at, 0.6)
		return
	# A guard eats the lance's damage outright (a lance is a travelling body, so
	# the deflect payoff has something real to point at).
	var dealt: int = SpellDeflect.resolve(body, _dmg, _dir, at)
	if dealt <= 0:
		return
	# ⚠ `take_damage` ships TWO signatures in this codebase (Hero takes one arg,
	# Enemy takes two). Calling the wrong one THROWS and aborts the enclosing
	# function, losing this hit and everything after it — always route through
	# `SpellTargets.hurt`, which adapts the arity.
	SpellTargets.hurt(body, dealt, Color(_color.r, _color.g, _color.b, 1.0))
	if element_id >= 0 and body.has_method("apply_status"):
		body.apply_status(element_id)   # HOLY = Radiance, a radiant burn
	if body.has_method("apply_knockback"):
		body.call("apply_knockback", _dir * PIERCE_KNOCKBACK)
	pierce_hits += 1
	_spark(at, 1.0)


func _spark(at: Vector2, strength: float) -> void:
	CombatVfx.spawn_burst(get_parent(), at,
		Color(_color.r * 1.3, _color.g * 1.2, _color.b, 0.95 * strength),
		Color(_color.r, _color.g, _color.b, 0.0),
		int(8.0 * strength) + 2, 0.26, 50.0, 170.0, 0.6, 1.7, 0.0, 0.0, true)


# --------------------------------------------------------------------- THE LOOK
## ⚠ MUST DEGRADE AT `graphics_quality = LOW` (the phone preview, a hard rule).
## Twenty-one lances is a prime candidate to blow the effect budget, so LOW drops
## the trail ribbon and the rack shimmer — GARNISH. The spear head, the shaft and
## the rack itself are READABILITY (they are the tell and the hitbox's advert) and
## are drawn identically at both settings. Thin the garnish, never the read.
func _draw() -> void:
	var low: bool = TuningConfig.quality_is_low()
	for lance: Dictionary in _lances:
		var age: float = _elapsed - float(lance["fire_at"])
		if age <= 0.0:
			_draw_racked(lance, low)
			continue
		if not bool(lance["alive"]):
			continue
		_draw_lance(lance["pos"] as Vector2, low)


## A racked lance: dim, SETTLING down onto its true lane, and brightening as its
## launch approaches. Both the descent and the brightening are the countdown — they
## are the only things on screen that say how long you have, and the lane a lance
## comes to rest on is exactly the lane it will fly down.
func _draw_racked(lance: Dictionary, low: bool) -> void:
	var until: float = float(lance["fire_at"]) - _elapsed
	if until > RACK_HOLD + WAVE_GAP:
		return  # not this wave's turn yet — keep the screen legible
	var arm: float = clampf(1.0 - until / RACK_HOLD, 0.0, 1.0)
	# ⚠ DRAW-ONLY. The settle offset is added HERE and never written back into
	# `lance["rack"]`, which is the launch position — see RACK_LIFT.
	var p: Vector2 = (lance["rack"] as Vector2) + Vector2.UP * RACK_LIFT * (1.0 - arm)
	if not low:
		p += _perp * sin(_elapsed * 24.0 + float(lance["shimmer"])) * 1.6
	var tip: Vector2 = p + _dir * LANCE_LEN * (0.45 + 0.55 * arm)
	draw_line(p, tip, Color(_color.r, _color.g, _color.b, 0.25 + 0.55 * arm),
		1.4 + 1.4 * arm, true)
	draw_circle(tip, 1.6 + 2.0 * arm,
		Color(1.5, 1.35, 0.95, 0.35 + 0.6 * arm), true, -1.0, true)


## A flying lance: an HDR head, a tapered shaft and (at full quality) a ribbon of
## afterglow behind it.
func _draw_lance(tip: Vector2, low: bool) -> void:
	var tail: Vector2 = tip - _dir * LANCE_LEN
	if not low:
		var ribbon: Vector2 = tip - _dir * LANCE_LEN * 2.6
		draw_line(tail, ribbon, Color(_color.r, _color.g, _color.b, 0.20), 2.0, true)
	# Barbed head: two short flanges swept back off the point.
	var flare: PackedVector2Array = PackedVector2Array([
		tip,
		tip - _dir * 11.0 + _perp * 4.2,
		tip - _dir * 11.0 - _perp * 4.2,
	])
	draw_colored_polygon(flare, Color(1.55, 1.38, 0.98, 0.95))
	draw_line(tail, tip, Color(_color.r, _color.g, _color.b, 0.95), 3.2, true)
	draw_line(tail, tip - _dir * 8.0, Color(1.45, 1.3, 0.95, 0.75), 1.4, true)
