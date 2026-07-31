class_name HorizonArc
extends Node2D
## HORIZON CUT — the Swordsaint's signature ult, and the kit's first TRAVELLING
## CURVED WALL WITH A HEIGHT BAND.
##
## > The blade is drawn slowly across the body, and when it leaves the sheath a
## > crescent leaves with it — a curved wall of edge that widens as it travels and
## > cuts everything at the height you chose.
##
## WHY IT IS A NEW SHAPE, scored honestly against the delivery-shape census in
## `docs/superpowers/specs/2026-07-27-spell-uniqueness-and-new-spells.md` §A.2:
##   * a BEAM resolves instantly along a line (9 spells) — this has a real position
##     over time and can be watched, out-run and out-jumped;
##   * a PROJECTILE is a point (2 spells) — this is a 180-600 px tall wall;
##   * a MARKED GROUND POINT is placed where you clicked (9 spells) — this is
##     aimed as a DIRECTION and, crucially, as a HEIGHT.
## That last property is the audit's §C.3 gap verbatim: *"aim is only ever used for
## direction or ground placement. Nothing in the kit asks the player to choose a
## height."* Aim high and the cut passes over grounded bodies. Aim low and it
## cannot be jumped. **The band is the spell.**
##
## ⚠ ONE GEOMETRY, DRAWN AND DAMAGED. The maker's standing bug is spells whose hit
## shape disagrees with their picture (*"the spells shouldn't be able to get out
## the radius"*), and five of those were found in one night. The defence here is
## structural rather than careful: `arc_point()` and `band_u()` are PURE STATICS,
## `_draw()` builds its polygon out of `arc_point()`, and the damage sweep tests
## with `band_u()` + `arc_point()`. There is no second description of the shape for
## the two to drift apart, and `tools/slice9_test_swordsaint.gd` asserts the edges
## agree in both directions — including the negative case one pixel outside the
## band.
##
## ⚠ NEVER READ THIS NODE'S TRANSFORM. Like every spectacle in this codebase it
## parks at the arena origin and draws in WORLD coordinates, so `global_position`
## is `(0, 0)` and is NOT where the cut is. `_origin` / `_dir` / `_travelled` are
## the truth; `reaction_shape()` and `deflect_point()` are built from those.
##
## DEFLECT: it physically travels, so it takes the `reflect()` path rather than
## `SpellDeflect.resolve()` — per that file's doctrine, *"if it has a position that
## moves, give it reflect()"*. A turned Horizon Cut comes back at full damage with
## its owner cleared, which is the best moment the class can hand the person
## fighting it, and is why 110 damage is affordable.

# ------------------------------------------------------------------- geometry

## Travel budget and speed. 900 px at 640 px/s is **1.41 s of visible approach** —
## the SECOND of this spell's three dodge windows (see DODGE BUDGET below).
const TRAVEL: float = 900.0
const SPEED: float = 640.0
## Half-height at launch and at full extension. The wall WIDENS as it travels, so
## ducking it is easy up close and hard at range — the opposite of every beam in
## the kit, which is widest at the muzzle.
const HALF_HEIGHT_START: float = 90.0
const HALF_HEIGHT_END: float = 300.0
## Thickness ALONG the travel axis. This is the whole depth of the damaging band:
## a body 16 px behind the trailing face is not hit, and the picture says so.
const THICKNESS: float = 30.0
## How far the tips LEAD the centre, in px. The concave face leads — a "(" opening
## toward you — so the cut closes around a target rather than sweeping past it, and
## the silhouette cannot be confused with a flat wall or a beam.
const BOW: float = 46.0
## Polygon resolution. 18 is enough that the drawn curve has no visible facets at
## 600 px of height while keeping the closed polygon at 38 verts.
const STEPS: int = 18

# --------------------------------------------------------------- DODGE BUDGET
## THREE SEPARATE OUTS, and the 110 damage is priced against all three at once. A
## signature ult needs the LONGEST tell in the game, never an exemption from having
## one.
##
##   1. THE CAST.  `cast_time` 1.25 s of rooted, levitating channel — the caster is
##      visible and interruptible, and `SignatureRite.dodge_window(1.25)` reports
##      ~0.85 s of uninterrupted charge. At `Hero.SPEED` 210 px/s that is ~180 px
##      of approach, i.e. anyone already inside a screen can reach the caster.
##   2. THE FLIGHT. `TRAVEL / SPEED` = 1.41 s of a wall you can watch coming. It
##      never accelerates and never turns (no homing — `_dir` is fixed at launch
##      and only a DEFLECT changes it).
##   3. THE BAND.  You may simply not be in the height it was aimed at.
## Named as constants so the budget is arguable rather than emergent.
const FLIGHT_DODGE: float = TRAVEL / SPEED

## Fade-out once the wall has spent its travel or bitten terrain.
const DISSIPATE: float = 0.28
## One hit per body per cut. A travelling wall that re-damaged every frame would do
## 110 x sixty, and "how long were you inside it" is not a skill anybody is reading.
const HIT_ONCE: bool = true

enum State { SWEEP, DISSIPATE }

# ---------------------------------------------------------------- stamped identity
## Set by `SpellCaster._stamp()`. All three MUST exist as declared properties or the
## `set()` calls are silent no-ops and this spectacle is quietly inert in the whole
## reaction system — the omission that made Hollow Purple look broken for two
## sessions and the single most repeated bug in this codebase.
var element_id: int = Elements.Element.ARCANE
var spell_tier: int = SpellTier.Tier.ULT
var caster_node: Node = null

var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _perp: Vector2 = Vector2.DOWN
var _colour: Color = Color(0.85, 0.9, 1.0, 1.0)
var _damage: int = 110
var _travel: float = TRAVEL
var _thickness: float = THICKNESS
var _h_start: float = HALF_HEIGHT_START
var _h_end: float = HALF_HEIGHT_END
var _travelled: float = 0.0
var _elapsed: float = 0.0
var _state: int = State.SWEEP
var _dissipate_t: float = 0.0
var _hit: Array = []
var _reflected: bool = false
var _target_group: String = "enemy"
var _live: bool = false


# ------------------------------------------------------------------ pure maths
## These two functions are the ONLY description of the shape. Both `_draw()` and
## the damage sweep call them, so the picture and the hitbox cannot disagree, and
## both are static so the test suite can assert the edges without a physics world.

## Where the arc's centre-line sits at normalised height `u` in [-1, 1].
##
## `along(u) = travelled - BOW + BOW * u^2` — the centre trails, the tips lead, so
## the hollow of the crescent faces forward.
static func arc_point(origin: Vector2, dir: Vector2, travelled: float,
		half_height: float, bow: float, u: float) -> Vector2:
	var d: Vector2 = dir.normalized() if dir.length_squared() > 0.0000001 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-d.y, d.x)
	var along: float = travelled - bow + bow * u * u
	return origin + d * along + perp * (u * half_height)


## Signed, UNCLAMPED height of world point `p` in band units. |u| <= 1 means "inside
## the height the player aimed at"; anything else is over or under the cut and is
## simply missed. Deliberately not clamped: clamping would round the band's ends off
## into a capsule and quietly hand the spell up to `half_height * 0.05` of free reach
## at the tips, which is exactly the drawn-vs-damaged lie this file exists to avoid.
static func band_u(origin: Vector2, dir: Vector2, half_height: float,
		p: Vector2) -> float:
	if half_height <= 0.0:
		return INF
	var d: Vector2 = dir.normalized() if dir.length_squared() > 0.0000001 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-d.y, d.x)
	return (p - origin).dot(perp) / half_height


## THE hit predicate as a pure point test — no silhouette, no physics. This is what
## the negative test asserts against, and what the runtime sweep below extends with
## the target's own drawn body.
static func contains_point(origin: Vector2, dir: Vector2, travelled: float,
		half_height: float, bow: float, thickness: float, p: Vector2) -> bool:
	var u: float = band_u(origin, dir, half_height, p)
	if not is_finite(u) or absf(u) > 1.0:
		return false
	var surface: Vector2 = arc_point(origin, dir, travelled, half_height, bow, u)
	var d: Vector2 = dir.normalized() if dir.length_squared() > 0.0000001 else Vector2.RIGHT
	return absf((p - surface).dot(d)) <= thickness * 0.5


## Half-height at normalised flight progress — the widening, in one place.
static func half_height_at(progress: float, h_start: float, h_end: float) -> float:
	return lerpf(h_start, h_end, clampf(progress, 0.0, 1.0))


# --------------------------------------------------------------------- driver

## Launch the cut. `travel` / `thickness` / `h_start` / `h_end` come from the
## SpellDef so the spell is tunable as data (see the library entry in the handoff:
## `length` = travel, `width` = thickness, `radius` = starting half-height,
## `reach` = ending half-height).
func sweep(origin: Vector2, aim: Vector2, colour: Color, travel: float = TRAVEL,
		thickness: float = THICKNESS, h_start: float = HALF_HEIGHT_START,
		h_end: float = HALF_HEIGHT_END, damage: int = 110,
		_effect: String = "arcane") -> void:
	_origin = origin
	_dir = aim.normalized() if aim.length_squared() > 0.0000001 else Vector2.RIGHT
	_perp = Vector2(-_dir.y, _dir.x)
	_colour = colour
	_travel = maxf(travel, 1.0)
	_thickness = maxf(thickness, 1.0)
	_h_start = maxf(h_start, 1.0)
	_h_end = maxf(h_end, _h_start)
	_damage = damage
	_travelled = 0.0
	_elapsed = 0.0
	_state = State.SWEEP
	_live = true
	# Park at the arena origin and draw in world coordinates — the house contract.
	global_position = Vector2.ZERO
	add_to_group("deflectable_spell")
	_register_reaction()
	# THE DRAW GATE. Edge-on across the sweep line at the hilt, so the crescent is
	# visibly UNSHEATHED through a sigil rather than conjured in front of the caster
	# — which is the same idea CastStyle.UNSHEATHE encodes in the body language, and
	# the two have to agree or the wall looks unrelated to the arm that threw it.
	# Held for a beat past the draw; the crescent then travels on alone.
	SpellSigil.open(self, origin, colour, 1.0, true, _dir, false, 0.15, 0.55)
	_sfx("melee_swing", 1.0, -0.25)
	_shake(7.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not _live:
		return
	_elapsed += delta
	if _state == State.DISSIPATE:
		_dissipate_t += delta
		if _dissipate_t >= DISSIPATE:
			queue_free()
			return
		queue_redraw()
		return
	var prev: float = _travelled
	_travelled = minf(_travelled + SPEED * delta, _travel)
	# TERRAIN. A wall of edge may not cut a body through solid rock, and it may not
	# visibly cross one either. The damage half is handled by SpellTargets' default
	# line-of-sight filter below; this half stops the DRAWN wall at the surface it
	# ran into and chews whatever destructibles it tore through on the way, which is
	# the "destroy what it can" half of the spell-world contract.
	var from: Vector2 = _origin + _dir * prev
	var to: Vector2 = _origin + _dir * _travelled
	# `first_solid_thick` rather than `clip`: `clip` returns only the endpoint, and
	# this needs the `smashed` array too — tearing through cover is the "destroy what
	# it can" half of the spell-world contract, not an optional flourish.
	var blocked: Dictionary = SpellWorld.first_solid_thick(from, to, _thickness,
		SpellWorld.THICK_SAMPLES, SpellWorld.rids([caster_node]), self)
	for smashed: Node in blocked.get("smashed", []) as Array:
		if smashed != null and is_instance_valid(smashed) and smashed.has_method("take_damage"):
			smashed.take_damage(_damage)
	if bool(blocked.get("hit", false)):
		_travelled = prev + float(blocked.get("distance", 0.0))
		_sweep_damage()
		_begin_dissipate()
		return
	_sweep_damage()
	if _travelled >= _travel:
		_begin_dissipate()
		return
	queue_redraw()


## Progress along the flight, 0..1 — drives the widening and the draw's intensity.
func _progress() -> float:
	return clampf(_travelled / maxf(_travel, 0.001), 0.0, 1.0)


func _half_height() -> float:
	return half_height_at(_progress(), _h_start, _h_end)


## The arc's own centre, in world space — for the reaction shape, the parry scans
## and anything that needs to know where this spell actually is.
func centre() -> Vector2:
	return arc_point(_origin, _dir, _travelled, _half_height(), BOW, 0.0)


# --------------------------------------------------------------------- damage

## Cut everything the DRAWN wall is currently overlapping, once per body per cut.
##
## Two stages on purpose. The coarse stage is one `SpellTargets.in_radius` around
## the arc's centre, which is where line-of-sight is enforced (`require_los` is left
## at its default TRUE — a cut may not reach through rock) and where the target list
## is trimmed to something worth doing exact maths on. The exact stage is the band
## test, silhouette-aware: it probes both the body ORIGIN and the DRAWN HEAD, which
## is the codebase's answer to *"spells pass through heads without registering"* —
## a rig's head centre sits ~10 px above its node origin (19 px on the 1.9x sparring
## dummies), so an origin-only probe misses a cut aimed at head height entirely.
func _sweep_damage() -> void:
	if not is_inside_tree():
		return
	# Already skipped the caster in the selector below; hostiles() also keeps them
	# out of the COARSE pass, so the cut cannot pick its own swordsman up at all.
	var pool: Array = SpellTargets.hostiles(self, _target_group)
	pool.append_array(get_tree().get_nodes_in_group("destructible"))
	var coarse: Array = SpellTargets.in_radius(centre(), _coarse_radius(), pool,
		[caster_node], self)
	for n: Node in coarse:
		if HIT_ONCE and _hit.has(n):
			continue
		if not _body_in_band(n):
			continue
		_hit.append(n)
		_strike(n)


## The smallest circle that certainly contains the whole drawn wall, used only to
## shortlist. Half-height plus the bow plus half the thickness is the exact bound;
## nothing is padded, because a padded shortlist would let the exact test below be
## the only thing between the spell and the drawn-vs-damaged lie — and it is.
func _coarse_radius() -> float:
	return _half_height() + BOW + _thickness * 0.5


## Is `target`'s DRAWN BODY inside the band? Two probes (origin, head), the same
## sampling `SpellTargets._touches_segment` uses for corridors, extended with the
## target's own `hit_margin()` so a rig gets its published forgiveness and a crate
## or a test stub gets exactly zero — which keeps this byte-identical to a plain
## point test for everything that has no silhouette.
##
## ⚠ THE STACKING CAVEAT (spell-world contract): reach here is measured from a ~31 px
## silhouette PLUS `hit_margin`, so the effective vertical reach is larger than
## `THICKNESS * 0.5` suggests. That growth IS the head-hitbox fix. If the cut ever
## feels too generous, the knob is `THICKNESS` or `Enemy.HIT_MARGIN_FACTOR` — never
## both, and never a third margin added here.
func _body_in_band(target: Object) -> bool:
	var n2: Node2D = target as Node2D
	if n2 == null:
		return false
	var hh: float = _half_height()
	var reach: float = _thickness * 0.5 + SpellTargets.hit_margin(target)
	var probes: Array[Vector2] = [n2.global_position, SpellTargets.aim_point(target)]
	for p: Vector2 in probes:
		var u: float = band_u(_origin, _dir, hh, p)
		if not is_finite(u) or absf(u) > 1.0:
			continue  # over or under the height the player chose — the band is the spell
		var surface: Vector2 = arc_point(_origin, _dir, _travelled, hh, BOW, u)
		if SpellTargets.body_distance(target, surface) <= reach:
			return true
	return false


func _strike(n: Node) -> void:
	var tint := Color(_colour.r, _colour.g, _colour.b, 1.0)
	var at: Vector2 = SpellTargets.aim_point(n)
	# A hero in the path gets the DEFLECT read first: the cut travels, so it takes
	# the reflect() path rather than SpellDeflect.resolve() (that file's doctrine —
	# if it has a position that moves, give it reflect()).
	if _target_group == "hero" and n.has_method("try_parry"):
		if bool(n.call("try_parry", self)):
			return
	# The codebase ships both arities. This USED to branch on group "destructible",
	# which was right for every target the cut could reach at the time — and became
	# wrong the moment the faction seam let it hit a HERO, which takes one argument
	# and is not a destructible. Group membership was never the real question;
	# the method's own signature is. The adapter asks that instead.
	SpellTargets.hurt(n, _damage, tint)
	if n.has_method("apply_status"):
		n.call("apply_status", element_id)
	if n.has_method("apply_knockback"):
		# Flung ALONG the cut, not away from the caster: you go where the blade went.
		n.call("apply_knockback", _dir * 320.0 + Vector2(0.0, -140.0))
	_hit_juice(at)


# -------------------------------------------------------------------- deflect

## How much of a victim's parry window counts against this. Nothing is unparryable;
## an ult is merely brutal to time, so the tier the spell already declares picks the
## dial rather than this file inventing a second one.
func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


## Where this spell physically is, for the parry scans. NOT `global_position`.
func deflect_point() -> Vector2:
	return centre()


## Turned. The wall stops, reverses around the deflector, and comes back with a
## fresh travel budget at FULL damage — and with its owner cleared, so it now cuts
## whoever threw it. That is the whole reason 110 is an affordable number.
func reflect(new_dir: Vector2, colour: Color) -> void:
	if _reflected or _state != State.SWEEP:
		return
	_reflected = true
	_origin = centre()
	_dir = new_dir.normalized() if new_dir.length_squared() > 0.0000001 else -_dir
	_perp = Vector2(-_dir.y, _dir.x)
	_colour = colour
	_target_group = "hero" if _target_group == "enemy" else "enemy"
	_travelled = 0.0
	_hit.clear()
	# Ownership is SEVERED, not transferred: an unowned effect matches no
	# same-owner / different-owner clash rule, which is the honest report for a
	# spell nobody is casting any more.
	caster_node = null
	_sfx("ding", 0.0, 0.05)
	queue_redraw()


## AoE sweeps clear pending hazards through this (mirrors EnemyProjectile.consume).
func consume() -> void:
	queue_free()


# ------------------------------------------------------- reaction participant

## World-space, built from `_origin`/`_dir`/`_travelled` and NEVER from
## `global_position` (which is the arena origin).
##
## A capsule across the crescent at its MID-DEPTH, thick enough to span the whole
## bow. The tips lead by `BOW` and the centre trails by it, so a capsule laid on the
## tip chord would exclude the middle of the very wall it describes — which is how
## two spells visibly cross and nothing happens.
##
## It is deliberately a SUPERSET of the damage band (it fills the hollow of the
## crescent, which the damage does not). Reaction geometry answers "did another
## spell physically meet this", and under-claiming there produces the silent
## no-reaction bug; over-claiming produces a reaction slightly early, which reads as
## the two spells touching. The DAMAGE shape is the exact one, and that is the shape
## the drawn-vs-damaged rule governs.
func reaction_shape() -> Dictionary:
	var hh: float = _half_height()
	var back: Vector2 = _dir * (BOW * 0.5)
	return SpellGeometry.capsule(
		arc_point(_origin, _dir, _travelled, hh, BOW, -1.0) - back,
		arc_point(_origin, _dir, _travelled, hh, BOW, 1.0) - back,
		BOW + _thickness)


## LOAD-BEARING. False while dissipating, so a spent cut cannot annihilate
## something on its way out.
func reaction_active() -> bool:
	return _live and _state == State.SWEEP


func reaction_element() -> int:
	return element_id


## A travelling, reflectable body — the same family as the boulder, the orbs and
## the crawler, which is what `ReactionTable.form_for_kind` already answers for
## every other spell you can send back.
func reaction_form() -> int:
	return ReactionTable.Form.PROJECTILE


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: gone, with none of the dissipate beat. The cut did not
## arrive anywhere — it was met on the way.
func reaction_consume() -> void:
	queue_free()


## Registered by node path rather than by naming the autoload, so this file stays
## loadable in a headless `--script` harness where `SpellReactor` does not exist.
func _register_reaction() -> void:
	if not is_inside_tree():
		return
	var reactor: Node = _autoload(&"SpellReactor")
	if reactor != null and reactor.has_method(&"register"):
		reactor.call("register", self, ReactionTable.Form.PROJECTILE, element_id)


# ----------------------------------------------------------------- life + fx

func _begin_dissipate() -> void:
	_state = State.DISSIPATE
	_dissipate_t = 0.0
	queue_redraw()


## Juice and sound go through node lookups rather than the `Juice.` / `Sfx.` globals
## so the entire spectacle — not just its pure maths — can be driven from a headless
## suite. That is what lets the drawn-vs-damaged assertions run the real code path
## instead of a reimplementation of it.
##
## ⚠ RESOLVED OFF `get_tree().root`, NEVER as the absolute path `"/root/Sfx"`. An
## absolute lookup from a node that is in a tree but NOT under the active
## `current_scene` — which is every `--script` capture harness and the spell
## playground — is refused outright by Godot and spams "Can't use get_node() with
## absolute paths from outside the active scene tree" once per call. Measured, not
## assumed: it fired on the first capture run of this file.
## `is_inside_tree()` FIRST: `get_tree()` on a detached node is not merely null, it
## errors ("Parameter data.tree is null"), so the null-check alone is not a guard.
func _autoload(node_name: StringName) -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(String(node_name)))


func _sfx(key: String, volume_db: float, pitch: float) -> void:
	var sfx: Node = _autoload(&"Sfx")
	if sfx != null and sfx.has_method(&"play"):
		sfx.call("play", key, volume_db, pitch)


func _shake(amount: float) -> void:
	var j: Node = _autoload(&"Juice")
	if j != null and j.has_method(&"shake_camera"):
		j.call("shake_camera", amount)


func _hit_juice(at: Vector2) -> void:
	_sfx("spell_impact", -1.0, -0.1)
	var j: Node = _autoload(&"Juice")
	if j == null:
		return
	if j.has_method(&"hit_stop"):
		j.call("hit_stop", 0.06)
	# SILHOUETTE over the white blow-out, for the same reason the Hero's cut uses it:
	# this ult's whole payoff is a READABLE SHAPE — a crescent wall crossing the
	# arena — and a white wash erases the crescent at the one frame it matters.
	if j.has_method(&"frame"):
		j.call("frame", {"style": ImpactFrame.Style.SILHOUETTE, "strength": 0.9, "at": at})
	elif j.has_method(&"impact_frame"):
		j.call("impact_frame", 0.7, at)   # older Juice without the style vocabulary
	if j.has_method(&"shake_camera"):
		j.call("shake_camera", 8.0)


# ----------------------------------------------------------------------- draw

## The polygon is built from `arc_point()`, the same function the hit test asks. Walk
## the LEADING face from one tip to the other, then the TRAILING face back, giving
## one closed lens exactly `_thickness` deep — which is exactly the depth
## `contains_point()` accepts.
func _face(offset: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hh: float = _half_height()
	for i in STEPS + 1:
		var u: float = -1.0 + 2.0 * float(i) / float(STEPS)
		pts.append(arc_point(_origin, _dir, _travelled + offset, hh, BOW, u))
	return pts


func _band_polygon(scale_thickness: float) -> PackedVector2Array:
	var half: float = _thickness * 0.5 * scale_thickness
	var lead: PackedVector2Array = _face(half)
	var trail: PackedVector2Array = _face(-half)
	var out := PackedVector2Array()
	out.append_array(lead)
	for i in trail.size():
		out.append(trail[trail.size() - 1 - i])
	return out


func _draw() -> void:
	if not _live:
		return
	var fade: float = 1.0
	if _state == State.DISSIPATE:
		fade = clampf(1.0 - _dissipate_t / DISSIPATE, 0.0, 1.0)
	var emissive: Color = Elements.emissive(element_id)
	# Three stacked passes, the same language BladeFlurry uses for the class's
	# damage line so the ult reads as the SAME weapon: a wide soft ghost that sells
	# the motion, a saturated body, and a thin over-1.0 core so the bloom catches the
	# EDGE rather than the whole smear.
	draw_colored_polygon(_band_polygon(2.4),
		Color(_colour.r, _colour.g, _colour.b, 0.16 * fade))
	draw_colored_polygon(_band_polygon(1.0),
		Color(_colour.r * 1.2, _colour.g * 1.1, _colour.b * 1.3, 0.72 * fade))
	draw_colored_polygon(_band_polygon(0.26),
		Color(emissive.r, emissive.g, emissive.b, 0.95 * fade))
	# Tip glints — the two points of the crescent lead, so they catch hardest.
	var hh: float = _half_height()
	for side: float in [-1.0, 1.0]:
		var tip: Vector2 = arc_point(_origin, _dir, _travelled, hh, BOW, side)
		draw_circle(tip, 5.0 * fade,
			Color(emissive.r, emissive.g, emissive.b, 0.9 * fade))
