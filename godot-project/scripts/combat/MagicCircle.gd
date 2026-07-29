class_name MagicCircle
extends Node2D
## Procedural animated ARCANE SIGIL, in TWO orientations because this is a
## SIDE-ON 2D game and a sigil's look depends on the spell's geometry:
##
##  FACE-ON (set_orientation false) — the full summoning circle you see head-on:
##    emanating pulse rings, an outer ring + dashed summoning ring + runic ticks
##    (spin CW), a counter-rotating mid ring with radial spokes (CCW), an
##    inscribed hexagram over a counter-rotating square, orbiting glyph motes, a
##    breathing core. Used for AREA / portal spells (meteor sky sigil, summons,
##    ground AoE) — where magic pours out of a 2D disc.
##
##  EDGE-ON (set_orientation true, along the beam axis) — the sigil seen from the
##    SIDE: a thin lens/gate the beam bursts THROUGH. In side-on 2D a beam's
##    circle faces the target, so from the camera it's a LINE perpendicular to
##    the beam. Nested edge-on rings, rim glyphs orbiting (foreshortened front/
##    back), a bright central aperture, a breathing core. Used for BEAMS (the
##    Zoltraak muzzle sigil, the divine-ray sky sigil).
##
## Grows in (appear), spins + breathes, blooms out (vanish + self-free). Reusable
## by every spectacle spell. Pure Node2D draw — no scene file.
##
##
## ============================ THE CAST → SPELL HAND-OFF ======================
## ONE CONTINUOUS SIGIL PER CAST. A cast is a ritual with a beginning, a middle
## and an end; the sigil the caster opens during the windup must be the SAME
## sigil the spell erupts from. Two independent spawners used to run per cast —
## the caster opened a windup circle and dismissed it, then the spectacle opened
## its own muzzle circle — so the player watched the ritual visibly RESTART
## mid-cast. That reads as a glitch, and it was the maker's report.
##
## The fix is a hand-off, not a second construction. The caster OFFERS its live
## circle at the moment of release; the spectacle ADOPTS it — reparented,
## re-anchored to the muzzle, TRAVELLING there from wherever the windup hung it
## (over the caster's head, for the big spells), with its spin, phase and
## breathing carried straight through. No appear() replay, no blink.
##
## ---- CASTER SIDE (one line, at the moment the spell actually fires) ---------
##     MagicCircle.offer(my_circle, self)        # instead of my_circle.vanish(t)
## and on any INTERRUPTION (windup cancelled, caster hit, caster died):
##     MagicCircle.withdraw(self)                # blooms an un-taken offer out
## `withdraw` is belt-and-braces, not load-bearing: an offer nobody claims within
## OFFER_TTL_MS blooms itself out anyway (see _process). That is deliberate —
## most spells (walls, novas, dashes) open no sigil of their own, so their offers
## are MEANT to go unclaimed and must degrade to exactly the old behaviour.
##
## ---- SPECTACLE SIDE (one line, replacing `MagicCircle.new()` + appear) ------
##     _circle = MagicCircle.adopt_or_open(
##         self, caster_node, muzzle_world_pos, colour, radius, grow_time,
##         edge_on, axis_dir, thickness, travel_time)
## Returns a circle either way, so ADOPTION IS OPTIONAL AND NEVER REQUIRED: with
## no offer pending (enemy casts, boss casts, reaction-spawned spectacles, remote
## co-op peers) it constructs and appear()s one exactly as before. Every existing
## `_circle.vanish(...)` / `is_instance_valid(_circle)` call site keeps working
## untouched — an adopted circle is an ordinary MagicCircle.
##
## ---- THREE RULES THE CALL SITES MUST HONOUR --------------------------------
## 1. ORDER: offer() must run BEFORE the spell is spawned, in the SAME FRAME.
##    The spectacle adopts inside its own constructor path, so an offer made
##    after SpellCaster.cast() arrives too late and the spectacle has already
##    built its own sigil — the exact bug this seam exists to kill. In Hero that
##    means the offer belongs in the teardown that already runs ahead of the
##    cast, not after it.
## 2. LET GO: the caster must null its own reference right after offering. The
##    sigil now belongs to the spell; a caster that keeps driving its position or
##    scale per-frame will fight the travel and drag the sigil back to its head.
## 3. SUCCESS PATH ONLY: offer() on the path where the spell actually fires.
##    An interrupted windup should still vanish() (or shatter) as it always did —
##    a shattered cast has no spell to hand its sigil to, and the shatter VFX is
##    the point of that moment.
##
## THE COORDINATE TRAP: spell spectacle nodes park at the arena origin and draw
## in WORLD coordinates, so their global_position is (0,0) and is NOT where the
## effect is (SpellGeometry.gd documents this at length). A circle handed from a
## caster (real transform) to a spectacle (parked at origin) is exactly where
## that bites, so the reparent goes through Node.reparent(keep_global_transform)
## and every position in this API is WORLD space. Never pass a local offset.

const SPIN_SPEED: float = 1.15
const TICKS: int = 28
const DASH_SEGMENTS: int = 22
const SPOKES: int = 8
const MOTES: int = 7
const PULSE_RINGS: int = 3
const GROW_TIME_DEFAULT: float = 0.3
const EDGE_TICKS: int = 12

## ---- hand-off tuning -------------------------------------------------------
## UNTESTED GUESSES, every one: these are reasoning about how a ritual should
## flow, not numbers anybody has felt yet. Kept together so a playtest can retune
## the whole hand-off from one place.
##
## How long the adopted sigil takes to glide from where the windup hung it (over
## the caster's head) to the spell's muzzle, morphing radius/colour/orientation
## on the way. Chosen to land WELL INSIDE a spectacle's own charge window so the
## sigil is settled and spinning at the muzzle before the shot leaves — the
## travel should read as the ritual descending into the hand, never as the sigil
## still sliding when the beam fires.
const HANDOFF_TRAVEL_TIME: float = 0.2
## Ease curve for that glide. < 1 = ease-OUT: leaves fast, settles gently, which
## is the shape of something being PULLED into the hand.
const HANDOFF_EASE: float = 0.42
## How long an offer stays claimable, in milliseconds. Adoption happens in the
## SAME FRAME as the offer (caster fires -> SpellCaster spawns -> spectacle
## adopts), so this only has to survive a few frames of slack. Deliberately tiny:
## most spells open no sigil, so their offers go unclaimed on purpose, and a long
## TTL would leave those sigils hanging past the cast they belonged to.
const OFFER_TTL_MS: int = 60
## Fade an un-taken / withdrawn offer blooms out over — matched to the 0.2 s that
## every caster passed to vanish() before the seam existed, so a spell that does
## NOT adopt looks byte-for-byte like it did.
const OFFER_EXPIRE_FADE: float = 0.2

@export var color: Color = Color(0.95, 0.4, 0.85, 1.0)
@export var radius: float = 130.0

var _phase: float = 0.0
var _alpha: float = 0.0
var _scale: float = 0.35
var _grow_time: float = GROW_TIME_DEFAULT
var _growing: bool = false
var _vanishing: bool = false
var _vanish_time: float = 0.2
var _vanish_elapsed: float = 0.0
## Orientation: face-on disc (default) or an edge-on gate aligned to an axis.
var _edge_on: bool = false
var _edge_thick: float = 0.15  # x-extent of the edge-on lens as a fraction of radius

# ---- hand-off state (see the seam doc at the top) ---------------------------
## Circles currently OFFERED for adoption: caster instance_id -> MagicCircle.
## A Dictionary rather than a single slot because co-op has two heroes who can
## release on the same frame, and a one-slot registry would let hero B's sigil be
## adopted by hero A's beam. Keyed by instance_id (an int) so a caster that frees
## itself mid-cast can never keep this alive.
static var _offers: Dictionary = {}
## Whose offer slot this instance sits in, or 0. Kept on the instance purely so
## _exit_tree can clear the registry without scanning it.
var _offer_caster_id: int = 0
## When this instance was offered, in engine ms; 0 = not offered. Drives the TTL
## self-clean, which is what stops a cast that nobody adopts (a wall, a nova, an
## interrupted windup) from leaving an orphaned sigil floating in the world.
var _offered_at_ms: int = 0
## Hand-off glide: interpolating position / radius / colour / orientation from
## where the windup left the sigil to where the spectacle wants it. Every field
## is a FROM value captured at adoption; the TO values are the spectacle's.
var _ho_active: bool = false
var _ho_elapsed: float = 0.0
var _ho_time: float = HANDOFF_TRAVEL_TIME
var _ho_from_pos: Vector2 = Vector2.ZERO
var _ho_to_pos: Vector2 = Vector2.ZERO
var _ho_from_scale: Vector2 = Vector2.ONE
var _ho_from_radius: float = 0.0
var _ho_to_radius: float = 0.0
var _ho_from_color: Color = Color.WHITE
var _ho_to_color: Color = Color.WHITE
var _ho_from_rot: float = 0.0
var _ho_to_rot: float = 0.0
var _ho_from_thick: float = 0.15
var _ho_to_thick: float = 0.15
## Rotation is NOT interpolated when the sigil is round at the start of the glide
## (a face-on disc, or an edge-on gate opened to full thickness): with ex == ey
## the drawing is rotationally symmetric, so the angle can be snapped invisibly
## and lerping it would only risk the long way round.
var _ho_snap_rot: bool = false
## Deferred face-on flip: going edge-on -> face-on, the gate OPENS to full
## roundness first and only becomes a face-on disc at the end of the glide. The
## flip is invisible because both draws are round at that instant.
var _ho_flip_to_face: bool = false


func appear(circle_color: Color, circle_radius: float, grow_time: float = GROW_TIME_DEFAULT) -> void:
	color = circle_color
	radius = circle_radius
	_grow_time = maxf(grow_time, 0.01)
	_growing = true
	_alpha = 0.0
	_scale = 0.35
	queue_redraw()


## Orient the sigil. `edge_on` true = a thin gate seen from the side, aligned so
## `axis_dir` (the beam direction) passes through its centre; the node rotates so
## the gate is perpendicular to the beam. false = a full face-on circle.
func set_orientation(edge_on: bool, axis_dir: Vector2 = Vector2.RIGHT, thickness: float = 0.15) -> void:
	_edge_on = edge_on
	_edge_thick = clampf(thickness, 0.04, 0.5)
	rotation = axis_dir.angle() if edge_on and axis_dir != Vector2.ZERO else 0.0
	queue_redraw()


# ========================= HAND-OFF SEAM: CASTER SIDE ========================

## Offer this caster's live windup sigil to whatever spectacle the cast is about
## to spawn. Call this INSTEAD of vanish() at the moment the spell actually fires
## — and only on the success path; an interrupted windup should still vanish (or
## shatter) as it always did.
##
## Safe to call for spells that open no sigil of their own: an offer nobody
## claims within OFFER_TTL_MS blooms itself out, which is exactly the vanish()
## it replaced, just a few frames later.
static func offer(circle: MagicCircle, caster: Node) -> void:
	if circle == null or not is_instance_valid(circle) or caster == null:
		return
	if circle._vanishing:
		return  # already dying — offering it would hand over a corpse
	var id: int = caster.get_instance_id()
	# A caster with a stale offer still pending (a cast that spawned nothing,
	# fired again inside the TTL) must not leak the first sigil.
	_expire_offer(id)
	_offers[id] = circle
	circle._offer_caster_id = id
	circle._offered_at_ms = Time.get_ticks_msec()


## Cancel an un-taken offer from `caster` and bloom the sigil out now. Call from
## every interruption path — windup cancelled, caster hit, caster died, co-op
## down — so a shattered cast can never leave a sigil hanging in the world. A
## no-op if the offer was already adopted, so it is safe to call unconditionally.
static func withdraw(caster: Node) -> void:
	if caster == null:
		return
	_expire_offer(caster.get_instance_id())


## Internal: drop `id`'s offer and bloom its circle out if it is still alive.
static func _expire_offer(id: int) -> void:
	var c: Variant = _offers.get(id)
	_offers.erase(id)
	if c is MagicCircle and is_instance_valid(c):
		(c as MagicCircle)._offer_caster_id = 0
		(c as MagicCircle)._offered_at_ms = 0
		(c as MagicCircle).vanish(OFFER_EXPIRE_FADE)


# ======================= HAND-OFF SEAM: SPECTACLE SIDE =======================

## THE ONE LINE every spectacle needs. Adopt the caster's windup sigil if one is
## on offer — reparenting it under `host`, gliding it to `world_pos` and morphing
## it to this spell's colour/radius/orientation while its spin and phase run on
## unbroken — otherwise construct a fresh one and appear() it exactly as before.
##
## `world_pos` is WORLD space (the muzzle / focus). Spectacles park at the arena
## origin and draw in world coordinates, so passing anything derived from the
## host's transform would put the sigil at the top-left of the arena — see the
## coordinate-trap note in the class doc.
##
## `caster` may be null: with no identity to match, an offer is still adopted if
## exactly ONE is pending (the overwhelmingly common single-caster case), and
## declined if several are, because guessing wrong in co-op would steal the other
## player's sigil. Declining just means a fresh circle — never a missing one.
static func adopt_or_open(
	host: Node,
	caster: Node,
	world_pos: Vector2,
	circle_color: Color,
	circle_radius: float,
	grow_time: float = GROW_TIME_DEFAULT,
	edge_on: bool = false,
	axis_dir: Vector2 = Vector2.RIGHT,
	thickness: float = 0.15,
	travel_time: float = HANDOFF_TRAVEL_TIME,
) -> MagicCircle:
	var adopted: MagicCircle = _take(caster)
	if adopted != null and host != null and host.is_inside_tree():
		# keep_global_transform: the sigil must not jump when it crosses from the
		# caster's transform into a spectacle parked at (0, 0).
		adopted.reparent(host, true)
		adopted._begin_handoff(world_pos, circle_color, circle_radius,
			edge_on, axis_dir, thickness, travel_time)
		return adopted
	if adopted != null:
		# Host not in the tree yet — cannot reparent, so let the offer die its
		# normal death rather than stranding it half-handed-over.
		adopted.vanish(OFFER_EXPIRE_FADE)
	var fresh: MagicCircle = MagicCircle.new()
	host.add_child(fresh)
	fresh.global_position = world_pos
	fresh.appear(circle_color, circle_radius, grow_time)
	fresh.set_orientation(edge_on, axis_dir, thickness)
	return fresh


## Internal: claim `caster`'s pending offer, or the single pending offer when
## `caster` is null. Returns null when there is nothing safe to claim.
static func _take(caster: Node) -> MagicCircle:
	_sweep_offers()
	var id: int = 0
	if caster != null:
		id = caster.get_instance_id()
		if not _offers.has(id):
			return null
	elif _offers.size() == 1:
		id = int(_offers.keys()[0])
	else:
		return null
	var c: Variant = _offers.get(id)
	_offers.erase(id)
	if not (c is MagicCircle) or not is_instance_valid(c):
		return null
	var circle: MagicCircle = c as MagicCircle
	# Cleared BEFORE the reparent: reparent() fires _exit_tree, which clears the
	# registry, and we must not have it clear a slot we have already claimed.
	circle._offer_caster_id = 0
	circle._offered_at_ms = 0
	return circle


## Internal: drop registry entries whose circle has been freed. Cheap (the
## dictionary holds at most one entry per live caster) and it keeps a null-caster
## adoption honest — a stale corpse must not count toward "exactly one pending".
static func _sweep_offers() -> void:
	for id: Variant in _offers.keys():
		var c: Variant = _offers[id]
		if not (c is MagicCircle) or not is_instance_valid(c):
			_offers.erase(id)


## Internal: start the glide from wherever the windup left this sigil to the
## spectacle's muzzle. Deliberately does NOT touch `_phase` — the spin and the
## breathing carry straight through, which is the whole point of adopting rather
## than rebuilding.
func _begin_handoff(
	world_pos: Vector2, new_color: Color, new_radius: float,
	edge_on: bool, axis_dir: Vector2, thickness: float, travel_time: float,
) -> void:
	# The ritual is at FULL power at the moment of release: cancel any residual
	# grow-in, and defensively cancel a vanish (offer() refuses vanishing circles,
	# but a spectacle could be handed one by some future caller).
	_growing = false
	_vanishing = false
	_alpha = 1.0
	_scale = 1.0
	_ho_active = true
	_ho_elapsed = 0.0
	_ho_time = maxf(travel_time, 0.001)
	_ho_from_pos = global_position
	_ho_to_pos = world_pos
	# The caster scales the NODE while the sigil charges (it grows as it gathers);
	# the spectacle owns the radius instead, so the node scale eases back to 1.
	_ho_from_scale = scale
	_ho_from_radius = radius
	_ho_to_radius = maxf(new_radius, 1.0)
	_ho_from_color = color
	_ho_to_color = new_color
	_ho_from_thick = _edge_thick
	_ho_to_thick = clampf(thickness, 0.04, 1.0)
	_ho_from_rot = rotation
	_ho_to_rot = axis_dir.angle() if edge_on and axis_dir != Vector2.ZERO else 0.0
	_ho_snap_rot = false
	_ho_flip_to_face = false
	# ORIENTATION WITHOUT A FLICKER. A hard switch between the two draw routines
	# would read as a SECOND glitch, so a mode change is animated as the sigil
	# TURNING: an edge-on gate at thickness 1.0 is round, which is the same
	# silhouette a face-on disc presents, so that roundness is the hinge both
	# directions pivot through.
	if _edge_on != edge_on:
		if edge_on:
			# Face-on disc -> edge-on gate: become edge-on immediately but fully
			# ROUND, then FOLD closed to the target thickness. Reads as the disc
			# swinging round to face the target. Rotation can be snapped now
			# because a round gate draws identically at any angle.
			_edge_on = true
			_ho_from_thick = 1.0
			_edge_thick = 1.0
			rotation = _ho_to_rot
			_ho_snap_rot = true
		else:
			# Edge-on gate -> face-on disc: OPEN to round over the glide, then
			# flip the draw at the end, where the two are indistinguishable.
			_ho_to_thick = 1.0
			_ho_flip_to_face = true
			_ho_snap_rot = true
	queue_redraw()


## Per-frame hand-off glide. Split out of _process so the ordering is explicit:
## this runs BEFORE the grow/vanish block, so a circle consumed by a reaction
## mid-glide still dissolves normally on top of wherever the glide had it.
func _process_handoff(delta: float) -> void:
	_ho_elapsed += delta
	var t: float = clampf(_ho_elapsed / _ho_time, 0.0, 1.0)
	var e: float = ease(t, HANDOFF_EASE)
	global_position = _ho_from_pos.lerp(_ho_to_pos, e)
	scale = _ho_from_scale.lerp(Vector2.ONE, e)
	radius = lerpf(_ho_from_radius, _ho_to_radius, e)
	color = _ho_from_color.lerp(_ho_to_color, e)
	_edge_thick = lerpf(_ho_from_thick, _ho_to_thick, e)
	if not _ho_snap_rot:
		# lerp_angle, not lerpf: an aim that crosses ±PI between the windup and
		# the release must take the SHORT way round, or the gate spins wildly.
		rotation = lerp_angle(_ho_from_rot, _ho_to_rot, e)
	if t >= 1.0:
		_ho_active = false
		if _ho_flip_to_face:
			_edge_on = false
			rotation = 0.0


func vanish(fade_time: float = 0.2) -> void:
	if _vanishing:
		return
	_vanishing = true
	_growing = false
	_vanish_time = maxf(fade_time, 0.01)
	_vanish_elapsed = 0.0


## Registry hygiene. reparent() fires this too, but _take() clears the slot
## before it reparents, so an adoption never trips over its own hand-off; this
## only ever fires for a sigil that leaves the tree while STILL on offer.
func _exit_tree() -> void:
	if _offer_caster_id != 0 and _offers.get(_offer_caster_id) == self:
		_offers.erase(_offer_caster_id)
	_offer_caster_id = 0
	_offered_at_ms = 0


func _process(delta: float) -> void:
	_phase += delta
	if _ho_active:
		_process_handoff(delta)
	# TTL self-clean. THE INTERRUPTION SAFETY NET: a caster who offers and then
	# spawns nothing — a wall, a nova, a windup shattered by a hit, a caster who
	# died on the release frame — leaves this sigil unclaimed, and without this it
	# would hang in the world forever. Adoption happens the same frame as the
	# offer, so anything still pending after OFFER_TTL_MS is never coming.
	if _offered_at_ms != 0 and Time.get_ticks_msec() - _offered_at_ms > OFFER_TTL_MS:
		_expire_offer(_offer_caster_id)
	if _growing:
		_alpha = minf(_alpha + delta / _grow_time, 1.0)
		_scale = lerpf(0.35, 1.08, ease(_alpha, 0.4))
		if _alpha >= 1.0:
			_scale = 1.0
			_growing = false
	if _vanishing:
		_vanish_elapsed += delta
		var v: float = clampf(_vanish_elapsed / _vanish_time, 0.0, 1.0)
		_alpha = 1.0 - v
		_scale = lerpf(1.0, 1.5, ease(v, 0.6))
		if v >= 1.0:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	if _edge_on:
		_draw_edge()
	else:
		_draw_face()


# -------------------------------------------------------------- EDGE-ON (beams)
## A thin gate seen from the side (local +x = beam axis after the node rotation;
## the gate spans local y). The beam bursts through the centre along +x.
func _draw_edge() -> void:
	var a: float = _alpha
	var c: Color = color
	var s: float = _scale
	var R: float = radius * s
	var ex: float = maxf(R * _edge_thick, 3.0)   # half-thickness (along the beam)
	var ring: Color = Color(c.r, c.g, c.b, 0.9 * a)
	var soft: Color = Color(c.r, c.g, c.b, 0.5 * a)
	var white: Color = Color(1.7, 1.7, 1.8, a)  # HDR aperture/core blooms
	var breath: float = 1.0 + 0.04 * sin(_phase * 4.0)

	# Emanating edge-on ripples, expanding along the gate.
	for i: int in PULSE_RINGS:
		var t: float = fposmod(_phase * 0.55 + float(i) / float(PULSE_RINGS), 1.0)
		var k: float = 0.75 + t * 0.9
		draw_polyline(_ellipse_pts(ex * k, R * k, 48), Color(c.r, c.g, c.b, (1.0 - t) * 0.2 * a), 2.0, true)

	# Nested edge-on rings.
	draw_polyline(_ellipse_pts(ex * breath, R * breath, 56), ring, 3.0, true)
	draw_polyline(_ellipse_pts(ex * 0.72 * breath, R * 0.72 * breath, 48), soft, 2.0, true)
	draw_polyline(_ellipse_pts(ex * 0.46, R * 0.46, 40), soft, 1.5, true)

	# Rim glyphs orbiting the edge-on ring — foreshortened, brighter at the front.
	for i: int in MOTES:
		var th: float = _phase * 1.6 + TAU * float(i) / float(MOTES)
		var pos: Vector2 = Vector2(ex * cos(th), R * 0.94 * sin(th))
		var depth: float = 0.45 + 0.55 * (0.5 + 0.5 * cos(th))  # front (cos>0) bigger/brighter
		var ma: float = clampf(0.35 + 0.5 * depth, 0.12, 1.0) * a
		draw_circle(pos, maxf(2.0, R * 0.03) * depth, Color(c.r, c.g, c.b, ma * 0.5), true, -1.0, true)
		draw_circle(pos, maxf(1.2, R * 0.02) * depth, Color(1.0, 1.0, 1.0, ma), true, -1.0, true)

	# Runic ticks around the rim, extending outward, sliding with the spin.
	for i: int in EDGE_TICKS:
		var th2: float = _phase * 1.6 + TAU * float(i) / float(EDGE_TICKS)
		var p0: Vector2 = Vector2(ex * cos(th2), R * sin(th2))
		var p1: Vector2 = Vector2(ex * 1.7 * cos(th2), R * 1.07 * sin(th2))
		draw_line(p0, p1, Color(c.r, c.g, c.b, 0.4 * a), 1.5, true)

	# Central APERTURE — the bright slit the beam bursts from (pulses).
	var pulse: float = 0.8 + 0.2 * sin(_phase * 8.0)
	draw_line(Vector2(0.0, -R * 0.62), Vector2(0.0, R * 0.62), Color(c.r, c.g, c.b, 0.55 * a), maxf(3.0, ex * 1.3) * pulse, true)
	draw_line(Vector2(0.0, -R * 0.5), Vector2(0.0, R * 0.5), white, maxf(1.5, ex * 0.5) * pulse, true)
	# Hot core.
	draw_circle(Vector2.ZERO, R * 0.12 * pulse, Color(c.r, c.g, c.b, 0.3 * a), true, -1.0, true)
	draw_circle(Vector2.ZERO, R * 0.07 * pulse, white, true, -1.0, true)


## A closed ellipse polyline with x half-extent `ex`, y half-extent `ey`.
func _ellipse_pts(ex: float, ey: float, n: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n + 1:
		var t: float = TAU * float(i) / float(n)
		pts.append(Vector2(ex * cos(t), ey * sin(t)))
	return pts


# ------------------------------------------------------------ FACE-ON (portals)
func _draw_face() -> void:
	var a: float = _alpha
	var c: Color = color
	var s: float = _scale
	var R: float = radius * s
	var ring: Color = Color(c.r, c.g, c.b, 0.9 * a)
	var soft: Color = Color(c.r, c.g, c.b, 0.5 * a)
	var white: Color = Color(1.7, 1.7, 1.8, a)  # HDR aperture/core blooms
	var breath: float = 1.0 + 0.03 * sin(_phase * 4.0)

	for i: int in PULSE_RINGS:
		var t: float = fposmod(_phase * 0.55 + float(i) / float(PULSE_RINGS), 1.0)
		var rr: float = R * (0.75 + t * 0.9)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 60, Color(c.r, c.g, c.b, (1.0 - t) * 0.22 * a), 2.0, true)

	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED, Vector2(s, s) * breath)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 84, ring, 3.5, true)
	draw_arc(Vector2.ZERO, radius * 0.965, 0.0, TAU, 84, Color(1, 1, 1, 0.2 * a), 1.5, true)
	_draw_dashed_ring(radius * 0.88, DASH_SEGMENTS, 0.55, Color(c.r, c.g, c.b, 0.75 * a), 3.0)
	for i: int in TICKS:
		var dirv: Vector2 = Vector2.from_angle(TAU * float(i) / float(TICKS))
		draw_line(dirv * radius * 0.76, dirv * radius * 0.94, Color(c.r, c.g, c.b, 0.5 * a), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.7, Vector2(s, s) * breath)
	draw_arc(Vector2.ZERO, radius * 0.64, 0.0, TAU, 60, soft, 2.0, true)
	for i: int in SPOKES:
		var sd: Vector2 = Vector2.from_angle(TAU * float(i) / float(SPOKES))
		draw_line(sd * radius * 0.34, sd * radius * 0.6, Color(c.r, c.g, c.b, 0.4 * a), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED * 0.35, Vector2(s, s))
	_draw_star(radius * 0.55, 3, 0.0, ring)
	_draw_star(radius * 0.55, 3, PI / 3.0, ring)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.5, Vector2(s, s))
	_draw_star(radius * 0.4, 4, PI / 4.0, soft)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for i: int in MOTES:
		var ang: float = _phase * 1.5 + TAU * float(i) / float(MOTES)
		var pos: Vector2 = Vector2.from_angle(ang) * R * 0.72
		var ma: float = clampf(0.55 + 0.35 * sin(_phase * 5.0 + float(i) * 1.6), 0.15, 1.0) * a
		draw_circle(pos, maxf(2.0, radius * 0.03), Color(c.r, c.g, c.b, ma * 0.4), true, -1.0, true)
		draw_circle(pos, maxf(1.2, radius * 0.018), Color(1, 1, 1, ma), true, -1.0, true)

	var pulse: float = 0.82 + 0.18 * sin(_phase * 7.5)
	draw_circle(Vector2.ZERO, radius * 0.22 * s * pulse, Color(c.r, c.g, c.b, 0.28 * a), true, -1.0, true)
	draw_arc(Vector2.ZERO, radius * 0.15 * s, 0.0, TAU, 28, ring, 2.0, true)
	draw_circle(Vector2.ZERO, radius * 0.09 * s * pulse, white, true, -1.0, true)


func _draw_dashed_ring(r: float, count: int, fill: float, col: Color, width: float) -> void:
	var slot: float = TAU / float(count)
	for i: int in count:
		var start: float = slot * float(i)
		draw_arc(Vector2.ZERO, r, start, start + slot * fill, 6, col, width, true)


func _draw_star(r: float, points: int, offset: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in points:
		pts.append(Vector2.from_angle(offset - PI / 2.0 + TAU * float(i) / float(points)) * r)
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0, true)
