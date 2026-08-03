class_name CrescentStep
extends Node2D
## CRESCENT STEP — the Swordsaint's way IN. A forward dash-cut that passes THROUGH
## bodies, opening each one as it crosses it.
##
## ═══════════════════════════════════════════════════════════════════════════════
## WHY IT EXISTS, AND WHY IT IS NOT A BLINK
## ═══════════════════════════════════════════════════════════════════════════════
## The Swordsaint's gap-close was `blink_strike` — Shadow Step, the same spell the
## Arcanist, the Cryomancer and the Shadowblade already carry. Four classes pressing
## the same button is the recolour problem, and for THIS class it is also wrong on
## its own terms: a duelist who wins by reading distance should not skip the distance,
## he should cross it with the blade out.
##
## So: **he moves.** The body is carried along the lane in `STEP_COUNT` visible
## sub-steps, and everything the lane crosses is cut on the way past. Set against the
## teleports already in the game —
##   * `BlinkStrike` (Shadow Step): instant, no travel, the payoff is a blast at the
##     destination. You were there, now you are here.
##   * `Hero._blink` (R): instant, no damage, pure mobility.
##   * `ThousandCuts`: a sequence of teleports AROUND one fixed point.
##   * this: continuous forward travel WITH a damage corridor behind it.
## — it is the only one of the four where the space between the two ends is a place
## the spell happened.
##
## ⚠ IT STILL ROUTES THROUGH `blink_to`, AND THAT IS NOT A CONTRADICTION. Every
## sub-step is offered to the caster's own vetting contract, which is what stops the
## step ENDING inside geometry, over a ring-out pit, or outside the room
## (`Hero._safe_blink_destination` owns those three rules; this file must not
## reimplement them). What the player sees is continuous movement, because six vetted
## resting points 40 px apart across 0.22 s is what continuous movement looks like.
## A step the caster refuses stops the dash there — he ran into a wall, which is the
## honest outcome — see `_advance_one`.
##
## ⚠ AND THE ONE HONEST COST OF ROUTING THROUGH IT, stated plainly because nobody has
## playtested this: `Hero.blink_to` grants `BLINK_IFRAME` (0.22 s) on every accepted
## move, and this makes six of them. So the Swordsaint is untouchable for roughly the
## dash plus 0.22 s afterwards — about 0.44 s total. For a dash that phases THROUGH
## bodies that is arguably correct (a body you pass through cannot hit you), but it
## is a real strength this design did not explicitly buy, and it is the first number
## to look at if the class feels slippery. There is no way to move a body through the
## Hero's own safety rules without also taking its i-frames, short of editing Hero.
##
## ═══════════════════════════════════════════════════════════════════════════════
## THE TELL AND THE COUNTERPLAY (the locked "everything must be dodgeable" rule)
## ═══════════════════════════════════════════════════════════════════════════════
## TELL — `WINDUP` seconds of a shared `Telegraph` LINE laid along the ENTIRE lane
##   before he moves: the full length, the full width, the exact angle. The lane is
##   the promise, and it is drawn in full before a single pixel of travel happens.
##   Shared Telegraph, so it joins the `telegraph` group and `BotDodge` can read it.
##
## COUNTERPLAY — the lane is STRAIGHT and FIXED at the moment of the press. It does
##   not track. Step off it, jump it, or drop below it and the whole dash is spent on
##   empty air. And because it passes THROUGH bodies rather than stopping on the
##   first, standing in it as a wall for your team-mate does nothing — the only
##   answer is to not be on the line.
##
## PLAIN STEEL: like `IaiSlash`, this applies NO ailment — the Swordsaint's
## `melee_element` is -1 on purpose. `element_id` is still declared ARCANE, because an
## element-less effect is silently DROPPED by `SpellReactor.register` and makes
## `resolve_element` guess. The flavour rule is kept by the missing `apply_status`
## call, never by an unset field.
##
## UNPLAYTESTED. Every number is a reasoned first guess with the reasoning attached.

# ------------------------------------------------------------------- the beats
## THE DODGE BUDGET. Shorter than `IaiSlash.DRAW_TIME` (0.30) on purpose: this is the
## class's mobility answer, and a gap-close you can see coming from half a second
## away is a gap-close that never closes. Long enough to read the lane and move.
const WINDUP: float = 0.18
## How long the travel takes. `STEP_COUNT` resting points across this window.
const TRAVEL: float = 0.22
## How long the trail lingers after he arrives.
const AFTER_GLOW: float = 0.24

## How many vetted sub-steps the lane is walked in.
##
## ⚠ THE STEP LENGTH IT IMPLIES MUST STAY ABOVE `Hero.BLINK_MIN_TRAVEL` (24 px) OR
## EVERY STEP IS REFUSED AND THE DASH DOES NOT MOVE. At the shipping lane length of
## 240 px this gives 40 px a step, which clears it with room to spare. If the lane is
## ever shortened below ~170 px, lower this count with it. `_step_length()` is the one
## place that arithmetic lives, and `tools/slice_test_melee_signatures.gd` pins it.
const STEP_COUNT: int = 6

## Half-height of the damage corridor above and below the lane's centre line, ADDED
## to the spell's own `width`. Named because the drawing derives from it too — the
## picture may not be narrower than the hitbox.
const CORRIDOR_PAD: float = 4.0

## Lateral shove: bodies are pushed OFF the line rather than down it. A dash-cut that
## dragged its victims along would pile them at the far end and make the second half
## of the lane hit nothing.
const KNOCKBACK: float = 190.0
const LIFT: float = 90.0

# ---------------------------------------------------------------- the picture
const CRESCENT_STEPS: int = 14
## The mobile picture: coarser crescents, no ghost pass, no trail sparks. The lane,
## the leading edge and the extent all survive at LOW — see `_low()`.
const CRESCENT_STEPS_LOW: int = 7
const CRESCENT_SPAN: float = 0.85   ## half-angle of the leading blade, radians
const CRESCENT_RADIUS: float = 30.0
## How long one sub-step's afterimage cut lingers. Longer than the whole TRAVEL, so
## every cut he made is still on screen when he arrives — the picture of the dash is
## the WHOLE row of them, not just the last one.
const MARK_FADE: float = 0.30
const CORE: Color = Color(1.60, 1.50, 1.75)
const TELL_ACCENT: Color = Color(0.95, 0.16, 0.13, 0.9)

# ------------------------------------------------- the stamp (all five, declared)
## ⚠ ALL FIVE, because `set()` on an undeclared property is a SILENT no-op and a
## spectacle built without a caster is quietly inert in the whole reaction system.
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.ARCANE
var spell_tier: int = SpellTier.Tier.HEAVY
var caster_node: Node = null
## "It goes THAT way, in a line" — the lane, not a cut landing on a spot. Overrides
## `SpellSigil.MOTIF_BY_SCRIPT`, a table this workstream does not own.
var sigil_motif: int = MagicCircle.Motif.LANCE

var _origin: Vector2 = Vector2.ZERO   ## where the dash began (world)
var _at: Vector2 = Vector2.ZERO       ## where the body actually is now (world)
var _dir: Vector2 = Vector2.RIGHT
var _lane: float = 240.0              ## planned travel distance
var _half: float = 22.0               ## corridor half-width
var _color: Color = Color(0.95, 0.4, 0.85, 1.0)
var _damage: int = 58
var _elapsed: float = -1.0            ## < 0 means hex() has not run yet
var _stepped: int = 0
var _blocked: bool = false
## Instance ids already cut. A body the lane crosses is opened ONCE, however many
## sub-step corridors happen to overlap it — six steps of a 40 px lane against a
## ~30 px body would otherwise land two or three hits on the same target and turn a
## dash into the hardest attack in the game by accident.
var _cut: Dictionary = {}
## Where each sub-step ENDED and when, so the trail can leave a cut behind at every
## point he passed through rather than only at the head.
##
## ⚠ THIS IS THE FRAME THAT MAKES IT NOT A TELEPORT. The first render drew one blade
## at the body and a flat ribbon behind it, which photographed as a laser line with a
## crescent on the end — a beam, i.e. exactly the thing this spell exists to not be.
## An afterimage at every resting point is what says a body was AT each of those
## places and cut what was standing there.
var _marks: PackedVector2Array = PackedVector2Array()
var _mark_at: PackedFloat32Array = PackedFloat32Array()
var _telegraph: Telegraph = null


## Cast entry — the fixed shape every `SpellCaster.HEX_SCRIPTS` entry shares.
func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	_origin = origin
	_at = origin
	var aim: Vector2 = target - origin
	_dir = aim.normalized() if aim.length_squared() > 0.0001 else Vector2.RIGHT
	_color = color
	_damage = maxi(spell.damage, 1)
	# `reach` is the travel distance, `width` the corridor's full thickness. The
	# Telegraph lane, the damage corridor and the drawn trail all read these two, so
	# the promise and the hitbox are one pair of numbers.
	_lane = maxf(spell.reach, 60.0)
	_half = maxf(spell.width, 8.0) * 0.5 + CORRIDOR_PAD
	# The gate he steps THROUGH — edge-on down the lane, so the dash reads as being
	# drawn out of a sigil rather than as a slide.
	SpellSigil.open(self, _origin, _color, 0.8, true, _dir, false, 0.14,
		WINDUP + TRAVEL)
	_arm_telegraph()
	SpellDrops.sfx("dash", -4.0, 0.06, 1.1)
	_elapsed = 0.0
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.IMPACT, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


## How far one sub-step travels. DERIVED, never a literal: the lane length is the
## spell's and the count is a constant, and the one invariant that matters
## (step > `Hero.BLINK_MIN_TRAVEL`) is a property of their ratio.
func _step_length() -> float:
	return _lane / float(STEP_COUNT)


func _life() -> float:
	return WINDUP + TRAVEL + AFTER_GLOW


## The whole lane, drawn before he moves. ONE CLOCK — its `_process` is off and
## `advance()` drives it, so the promise and the travel cannot drift apart.
func _arm_telegraph() -> void:
	_telegraph = Telegraph.new()
	add_child(_telegraph)
	_telegraph.global_position = _origin
	_telegraph.accent = TELL_ACCENT
	_telegraph.style = Telegraph.Style.LANE
	_telegraph.aim_dir = _dir
	_telegraph.reach = _lane
	_telegraph.set_process(false)
	_telegraph.start_line(_lane, _half * 2.0, _dir.angle(), WINDUP)


func _process(delta: float) -> void:
	advance(delta)


## Deterministic time-step, so a headless suite can drive windup -> travel -> arrival
## without waiting on real frames.
func advance(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.advance(delta)
	# How many sub-steps SHOULD have happened by now. Driven off the clock rather
	# than one-per-frame so the dash takes the same time at 30 fps and at 144.
	if not _blocked and _elapsed > WINDUP:
		var want: int = clampi(
			int(ceil(clampf((_elapsed - WINDUP) / TRAVEL, 0.0, 1.0) * float(STEP_COUNT))),
			0, STEP_COUNT)
		while _stepped < want and not _blocked:
			_advance_one()
	if _elapsed >= _life():
		queue_free()
		return
	queue_redraw()


# ------------------------------------------------------------------ the travel
## One sub-step: offer the next resting point to the caster's own vetting, cut
## everything in the segment actually crossed, and adopt wherever the body ended up.
func _advance_one() -> void:
	_stepped += 1
	var planned: Vector2 = _origin + _dir * (_step_length() * float(_stepped))
	var landed: Vector2 = _move_caster(planned)
	_sweep(_at, landed)
	# ⚠ THE STOP RULE. `Hero.blink_to` returns where the body may LEGALLY rest, which
	# is the planned point in the common case and a slid-back substitute when the lane
	# runs into a wall, a pit lip or the edge of the room. Landing appreciably short
	# of the plan means the world said no, and the dash ends there rather than
	# continuing to sweep damage down a corridor the body never travelled. Half a step
	# of slack, so a couple of pixels of vetting nudge is not read as a wall.
	if landed.distance_to(planned) > _step_length() * 0.5:
		_blocked = true
	_at = landed
	_marks.append(landed)
	_mark_at.append(_elapsed)
	if _stepped >= STEP_COUNT:
		_blocked = true   # arrived: nothing left to walk


## Offer `to` to the caster's own landing rules and return where it actually ended up.
##
## ⚠ NEVER A RAW `global_position` WRITE. The caster owns where its body may rest
## (geometry, pits, room bounds) and on a co-op peer the position belongs to the
## MultiplayerSynchronizer, which a direct write would fight and lose to.
## `Hero.blink_to` handles both. A caster that declares no `blink_to` — a bare test
## stub, a playground figure — is NOT moved, and the lane still sweeps: the spell's
## damage must not depend on whether the thrower opted into being relocated.
func _move_caster(to: Vector2) -> Vector2:
	if caster_node == null or not is_instance_valid(caster_node):
		return to
	if not caster_node.has_method("blink_to"):
		return to
	return caster_node.call("blink_to", to) as Vector2


## Cut everything in the corridor from `from` to `to`. Silhouette-measured and
## line-of-sight gated, both by `SpellTargets`; each body only ever once (`_cut`).
func _sweep(from: Vector2, to: Vector2) -> void:
	var span: Vector2 = to - from
	var dist: float = span.length()
	if dist <= 0.01:
		return
	var d: Vector2 = span / dist
	var tint := Color(_color.r, _color.g, _color.b, 1.0)
	# The corridor is measured from a point lifted to mid-body, for the same reason
	# `SpellTargets` exists at all: a lane run from the node origin passes under the
	# silhouette it is supposed to cross.
	var lift := Vector2(0.0, -14.0)
	for e: Node in SpellTargets.on_line(from + lift, d, dist, _half, _hostiles(),
			[caster_node], self):
		var id: int = (e as Object).get_instance_id()
		if _cut.has(id):
			continue
		_cut[id] = true
		var at: Vector2 = SpellGeometry.closest_point_on_segment(
			SpellTargets.aim_point(e), from + lift, to + lift)
		# Deflectable: a well-timed guard EATS the pass. Nothing physically travels
		# that could be sent back.
		var dealt: int = SpellDeflect.resolve(e, _damage, d, at, _deflect_window())
		if dealt <= 0:
			continue
		SpellTargets.hurt(e, dealt, tint)
		# ⚠ NO `apply_status` — plain steel. See the class docs.
		if e.has_method("apply_knockback"):
			# OFF the line, not along it: whichever side of the lane the body sits,
			# plus a lift. A body shoved down the lane would be re-crossed by the
			# remaining steps and shielded from nothing.
			var n := Vector2(-d.y, d.x)
			var side: float = signf(n.dot((e as Node2D).global_position - at))
			if side == 0.0:
				side = 1.0
			e.call("apply_knockback", n * side * KNOCKBACK + Vector2.UP * LIFT)
	for prop: Node in SpellTargets.on_line(from + lift, d, dist, _half,
			get_tree().get_nodes_in_group("destructible"), [caster_node], self):
		var pid: int = (prop as Object).get_instance_id()
		if _cut.has(pid):
			continue
		_cut[pid] = true
		if prop.has_method("damage_at"):
			var pp: Vector2 = (prop as Node2D).global_position
			var contact: Vector2 = SpellGeometry.closest_point_on_segment(
				pp, from + lift, to + lift)
			prop.call("damage_at", _damage, contact, d)
		elif prop.has_method("take_damage"):
			prop.call("take_damage", _damage)
	CombatVfx.spawn_burst(get_parent(), to + lift, CORE,
		Color(_color.r, _color.g, _color.b, 0.0), 6, 0.2, 40.0, 110.0, 0.5, 1.4,
		0.0, 0.0, true, -d, 40.0)
	SpellDrops.sfx("melee_swing", -10.0, 0.1, 1.35)


func _hostiles() -> Array:
	return SpellTargets.hostiles(self, StringName(target_group))


func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


# --------------------------------------------- reaction contract (SpellReactor)
## World space, from `_origin` to WHERE THE BODY ACTUALLY IS — not the planned end,
## and never `global_position`, which is (0, 0). A dash stopped by a wall presents a
## short capsule, which is the truth about where it can clash.
func reaction_shape() -> Dictionary:
	return SpellGeometry.capsule(_origin, _at, _half * 2.0)


## LOAD-BEARING: false during the whole windup (a drawn lane is a promise, not a
## hit) and false once he has arrived.
func reaction_active() -> bool:
	return _elapsed >= WINDUP and _elapsed < WINDUP + TRAVEL


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.IMPACT


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


func reaction_consume() -> void:
	queue_free()


# ------------------------------------------------------------------ the picture
func _low() -> bool:
	return TuningConfig.quality_is_low()


## The leading blade: a tapered crescent standing across the lane at the body's
## current position, needle-pointed at both tips. Same construction as
## `BladeFlurry._crescent`, but perpendicular to travel rather than sweeping a cone —
## which is the visual difference between "he swung" and "he went through you".
func _crescent(center: Vector2, thickness: float) -> PackedVector2Array:
	var steps: int = CRESCENT_STEPS_LOW if _low() else CRESCENT_STEPS
	var mid: float = _dir.angle()
	var pts := PackedVector2Array()
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		var a: float = mid - CRESCENT_SPAN + 2.0 * CRESCENT_SPAN * t
		pts.append(center + Vector2.from_angle(a)
			* (CRESCENT_RADIUS + thickness * 0.5 * sin(t * PI)))
	for i: int in steps + 1:
		var t: float = 1.0 - float(i) / float(steps)
		var a: float = mid - CRESCENT_SPAN + 2.0 * CRESCENT_SPAN * t
		pts.append(center + Vector2.from_angle(a)
			* (CRESCENT_RADIUS - thickness * 0.5 * sin(t * PI)))
	return pts


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < WINDUP:
		_draw_promise()
		return
	_draw_trail()


## The windup, on top of the Telegraph's lane: the corridor's two edges drawn out to
## full length as the blade comes free. The Telegraph says "danger here"; these two
## lines say exactly how WIDE, which is the number a player needs to decide whether
## one sidestep is enough.
func _draw_promise() -> void:
	var t: float = clampf(_elapsed / WINDUP, 0.0, 1.0)
	var n := Vector2(-_dir.y, _dir.x)
	var tip: Vector2 = _origin + _dir * (_lane * t)
	for side: float in [1.0, -1.0]:
		draw_line(_origin + n * (_half * side), tip + n * (_half * side),
			Color(_color.r, _color.g, _color.b, 0.20 + 0.30 * t), 1.4, true)
	draw_circle(_origin, 3.0 + 5.0 * t,
		Color(CORE.r, CORE.g, CORE.b, 0.4 + 0.4 * t), true, -1.0, true)


## The travel: a fading ribbon along the ground he has covered, plus the leading
## crescent at the body. The ribbon is what says HE MOVED rather than blinked — it is
## continuous from the origin to the body and has no gap in it anywhere.
func _draw_trail() -> void:
	var age: float = clampf((_elapsed - WINDUP - TRAVEL) / AFTER_GLOW, 0.0, 1.0)
	var fade: float = 1.0 - age
	if fade <= 0.0:
		return
	var emissive: Color = Elements.emissive(element_id)
	var n := Vector2(-_dir.y, _dir.x)
	var lift := Vector2(0.0, -14.0)
	var a: Vector2 = _origin + lift
	var b: Vector2 = _at + lift
	if not _low():
		# The ribbon body: a tapering wedge, widest at the leading end, so the shape
		# itself points the way he went.
		draw_colored_polygon(PackedVector2Array([
			a + n * (_half * 0.25), b + n * _half,
			b - n * _half, a - n * (_half * 0.25)]),
			Color(_color.r, _color.g, _color.b, 0.22 * fade))
	draw_line(a, b, Color(CORE.r, CORE.g, CORE.b, 0.70 * fade), 2.0, true)
	# A cut left behind at EVERY place he stood, thinning with age. See `_marks`.
	for i: int in _marks.size():
		var mark_age: float = clampf((_elapsed - _mark_at[i]) / MARK_FADE, 0.0, 1.0)
		var strength: float = (1.0 - mark_age) * fade
		if strength <= 0.02:
			continue
		var m: Vector2 = _marks[i] + lift
		if not _low():
			draw_colored_polygon(_crescent(m, 15.0 * 2.2),
				Color(_color.r, _color.g, _color.b, 0.16 * strength))
		draw_colored_polygon(_crescent(m, 15.0 * (0.5 + 0.5 * strength)),
			Color(_color.r * 1.25, _color.g * 1.1, _color.b * 1.3, 0.80 * strength))
		draw_colored_polygon(_crescent(m, 15.0 * 0.28),
			Color(emissive.r, emissive.g, emissive.b, 0.9 * strength))
