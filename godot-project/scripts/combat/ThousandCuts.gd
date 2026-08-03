class_name ThousandCuts
extends Node2D
## THOUSAND CUTS — Shadowblade ULT. Mark one body, vanish, and open it from every
## angle at once.
##
## ═══════════════════════════════════════════════════════════════════════════════
## WHY IT EXISTS: THE FIVE-BEAM PROBLEM
## ═══════════════════════════════════════════════════════════════════════════════
## The maker's ruling was "we cannot have any recolours — I want all the classes to
## be different and unique and not similar at all". Five of nine classes threw a
## beam down the same `BeamSpell` corridor, and the Shadowblade's was `umbral_lance`
## — a violet copy of the Arcanist's magenta one. An in-and-out assassin whose
## finisher is a stationary channelled lance is not an assassin, it is a mage with a
## darker palette. This replaces it.
##
## ── WHAT MAKES IT NOT THE STORMCALLER'S CHAIN-BLINK ───────────────────────────
## Deliberately the exact inverse. `ChainBolt` hops between DIFFERENT bodies and
## spends one hit on each. This spends EVERY hit on ONE body, from `count` angles
## walked around it. The chain is "the room is the target"; this is "you, and only
## you, and from everywhere".
##
## And it is not `BladeFlurry` either, which is the same class's damage line: a
## flurry sweeps a forward CONE from where the caster stands. This ORBITS — the
## caster is relocated to a new point on the circle before every cut, so the crescents
## cross the anchor from all sides instead of fanning out in front of one.
##
## ═══════════════════════════════════════════════════════════════════════════════
## THE TELL AND THE COUNTERPLAY (the locked "everything must be dodgeable" rule)
## ═══════════════════════════════════════════════════════════════════════════════
## TELL — `LOCK_TELL` seconds of a shared `Telegraph` danger ring at exactly the
##   radius that will be cut, plus a shrinking shadow noose drawn on top of it and a
##   ground sigil under the mark. Using the shared Telegraph rather than drawing our
##   own ring buys two things for free: it is the danger grammar the game already
##   teaches, and it joins the `telegraph` group so `BotDodge` can perceive it.
##
## COUNTERPLAY — **the orbit is anchored to the ground, not to the victim.** The
##   mark is taken once, at cast time, and every cut afterwards is measured from
##   that fixed point. Walk out of the ring during the tell and the cuts fall on
##   empty floor. That is the whole answer, it is legible from the ring alone, and it
##   is why this can be allowed to hit as hard as it does: staying still against a
##   marked assassin is the mistake being punished.
##
##   It also means the reverse is true, and it is supposed to be: friendly fire is
##   always on, so a team-mate who wanders into the ring is cut by the arcs facing
##   them. A body at the CENTRE is inside every cut's bite (see CUT_REACH); a body
##   out on the rim is only inside the two or three arcs on its own side. That
##   asymmetry is the picture the spell is drawing.
##
## ═══════════════════════════════════════════════════════════════════════════════
## THE TRAPS THIS FILE IS WRITTEN AGAINST (each has cost real time in this repo)
## ═══════════════════════════════════════════════════════════════════════════════
##  * `set()` ON AN UNDECLARED PROPERTY IS A SILENT NO-OP. All five of the stamped
##    fields are declared below — `element_id`, `spell_tier`, `caster_node`,
##    `target_group` AND its other spelling `_target_group`. `BladeFlurry` shipped
##    with only the first of those and was quietly inert in the reaction system.
##  * A SPECTACLE PARKS AT THE ARENA ORIGIN. `global_position` is (0, 0) and is NOT
##    where the effect is. Everything here draws in WORLD space off `_anchor`.
##  * `take_damage` SHIPS TWO SIGNATURES. Every hit routes through
##    `SpellTargets.hurt()`, never a direct two-arg call — a one-arg receiver would
##    throw, and a GDScript runtime error ABORTS the enclosing function, silently
##    swallowing the ailment and the knockback below it as well.
##  * AN ELEMENTLESS EFFECT IS DROPPED BY `SpellReactor.register`. SHADOW is
##    declared outright rather than being left at -1 for `resolve_element` to guess.
##  * AUTOLOADS ARE NOT GLOBAL IDENTIFIERS under `--script`. Sound goes through
##    `SpellDrops.sfx` (which does the guarded `/root/Sfx` lookup) and the reactor
##    through `get_node_or_null`.
##
## UNPLAYTESTED. Every number below is a reasoned first guess with its rationale
## attached, so the maker can move it after one F5 instead of re-deriving it.

# ------------------------------------------------------------------ the mark
## How far from the aim point a body may be and still be the one that gets marked.
##
## ⚠ THIS IS NOT AUTO-AIM AND MUST NOT BECOME IT. The search starts at the point the
## player aimed at (already clamped to the spell's `reach` by SpellCaster's HEX arm),
## not at the caster, so the only bodies it can find are ones you were pointing at.
## 130 px is about two body-widths of slack on a thumb-aimed mark. Raise this past a
## couple of hundred and it stops being "the one you pointed at" and starts being
## "whoever the game likes", which is the thing the no-auto-aim rule forbids.
const LOCK_RADIUS: float = 130.0

## THE DODGE BUDGET: seconds between the ring appearing and the first cut landing.
## Sibling reference points — `BlinkStrike.BLAST_TELL` is 0.30 for a small burst,
## `BlastSpell.WINDUP` is 0.55 for a giant walkable-out-of AoE. This is an ULT with a
## walk-out answer, so it sits nearer the blast: long enough to read the ring and
## take three steps, short enough that the assassin still arrives inside one beat.
const LOCK_TELL: float = 0.45

# ------------------------------------------------------------------ the orbit
## Where the blade appears each time, measured from the anchor.
const ORBIT_RADIUS: float = 62.0
## How far each individual cut bites from its own blade point.
##
## ⚠ DELIBERATELY LARGER THAN `ORBIT_RADIUS`, and the inequality is load-bearing
## rather than cosmetic: a cut whose reach did not clear the orbit could not touch
## the body standing at the centre, which is the one body the entire spell is about.
## The 8 px of surplus is the margin that keeps that true if either number moves.
const CUT_REACH: float = 70.0
## Total span the cuts are spread over. Under a second, per the design brief's
## "~0.7-0.9 s" — long enough to read as a sequence, short enough to read as one
## continuous assault rather than a queue.
const CUT_WINDOW: float = 0.80
## Pause between the last orbiting cut and the reappearance, so the finisher is a
## separate beat and not the eighth item in a list.
const FINAL_GAP: float = 0.12
## The finisher's damage, as a multiple of one orbiting cut.
const FINAL_MULT: float = 2.4
## How long the whole picture lingers after the finisher.
const AFTER_GLOW: float = 0.30

## Shove per orbiting cut — small on purpose. A body knocked clean out of the ring
## by cut one would take the other six for nothing, which turns the spell's own
## payoff off. The FINISHER is where the weight goes.
const CUT_KNOCK: float = 60.0
const FINAL_KNOCK: float = 300.0

## How far outside the orbit the caster's body is placed for each strike, so the rig
## reads as standing at the edge of the circle rather than inside the victim.
const STAND_OFF: float = 18.0

# ------------------------------------------------------------------ the picture
## Seconds one crescent stays on screen.
##
## ⚠ DELIBERATELY LONGER THAN THE GAP BETWEEN TWO CUTS (`CUT_WINDOW / count`, about
## 0.11 s at the shipping count). The first render of this spell used 0.22 with a
## fast fade and photographed as ONE lonely arc at a time — a queue of separate
## slashes rather than a body being worked over. Three crescents alive at once, at
## different ages, is what reads as an assault. If the count is ever raised a lot,
## this can come back down.
const CUT_VISIBLE: float = 0.30
## Half-angle of a crescent, radians. Wide enough that a blade wraps a real slice of
## the orbit rather than reading as a tick mark on a big ground sigil.
const CUT_SPAN: float = 0.78
const CUT_THICKNESS: float = 21.0
const CRESCENT_STEPS: int = 18
## The mobile picture. Fewer vertices per crescent — the SHAPE survives, the
## smoothness does not. See `_low()`.
const CRESCENT_STEPS_LOW: int = 9
## HDR violet-white, > 1.0 so the core blooms through the post grade.
const CORE: Color = Color(1.45, 1.20, 1.85)
## The danger ring keeps the game's DANGER hue, not the spell's violet: red is what
## this codebase has taught the player to read as "move", and a violet ring under
## violet crescents is a tell nobody sees.
const TELL_ACCENT: Color = Color(0.95, 0.16, 0.13, 0.9)

# ------------------------------------------------- the stamp (all five, declared)
## WHO THIS SPELL MAY HURT. Written by `SpellCaster._stamp` at cast time under BOTH
## spellings, so it follows the CASTER's faction instead of being fixed at "enemy"
## forever. Friendly fire is always on, so in a real fight this is the shared
## `mortal` group.
var target_group: String = "enemy"
var _target_group: String = "enemy"
## The ailment applied on hit, and the reaction layer's element. SHADOW -> Weaken.
var element_id: int = Elements.Element.SHADOW
## The clash shelf, and therefore how brutal this is to parry.
var spell_tier: int = SpellTier.Tier.ULT
## WHO CAST IT. Load-bearing three times over: the reaction layer's ownership
## predicate, the line-of-sight exclude list, and the body this spell relocates.
var caster_node: Node = null
## What the summoning circle draws in its inner court. Overrides
## `SpellSigil.MOTIF_BY_SCRIPT` (a table in a file this workstream does not own), so
## the circle says "a cut lands" without that table needing an entry.
var sigil_motif: int = MagicCircle.Motif.BLADE

var _origin: Vector2 = Vector2.ZERO      ## where the caster stood when it was cast
var _anchor: Vector2 = Vector2.ZERO      ## the marked point — the orbit's centre
var _color: Color = Color(0.6, 0.35, 0.95, 1.0)
var _damage: int = 16
var _count: int = 7
var _elapsed: float = -1.0               ## < 0 means hex() has not run yet
var _fired: int = 0
var _final_done: bool = false
var _cut_at: PackedFloat32Array = PackedFloat32Array()
var _cut_angle: PackedFloat32Array = PackedFloat32Array()
var _telegraph: Telegraph = null


## Cast entry — the fixed shape every `SpellCaster.HEX_SCRIPTS` entry shares.
## `target` arrives already clamped to the spell's `reach` by the HEX arm.
func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	_origin = origin
	_color = color
	_damage = maxi(spell.damage, 1)
	_count = clampi(spell.count, 3, 12)
	_anchor = _mark(target)
	_schedule()
	# The gate the assassin leaves through, edge-on down the line of the lunge —
	# the same grammar BlinkStrike uses for a departure, so a vanish looks like a
	# vanish whichever spell caused it.
	var axis: Vector2 = _anchor - _origin
	SpellSigil.open(self, _origin, _color, 0.7, true,
		axis.normalized() if axis.length_squared() > 0.0001 else Vector2.RIGHT,
		false, 0.15, LOCK_TELL)
	# ...and the ring the cuts come out of, laid FLAT on the ground under the mark.
	SpellSigil.open(self, _anchor, _color, 1.0, false, Vector2.RIGHT, true, 0.16,
		LOCK_TELL + CUT_WINDOW)
	_arm_telegraph()
	CombatVfx.spawn_burst(get_parent(), _origin, Color(0.35, 0.15, 0.5, 0.9),
		Color(0.1, 0.03, 0.2, 0.0), 16, 0.35, 50.0, 150.0, 1.2, 3.0)
	SpellDrops.sfx("shadow_cast", -2.0, 0.06, 0.9)
	Juice.zoom_pull_camera(0.16, LOCK_TELL + CUT_WINDOW * 0.6, 0.16, 0.6)
	# Join the reaction system NOW but stay inert until the cuts start — see
	# `reaction_active`. Registering during the tell matches BeamSpell and
	# BlinkStrike; a danger ring must never annihilate anything on its own.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.IMPACT, element_id)
	_elapsed = 0.0
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


## THE MARK. The nearest hostile body to the point the player aimed at, or that point
## itself when there is nobody there.
##
## Falling back to the bare aim point rather than fizzling is deliberate: an ULT that
## silently does nothing because the lock missed by 20 px is a button the player
## stops trusting. With no body to mark, the orbit simply opens on the ground and
## cuts whoever walks into it — a worse outcome than a clean mark, which is the
## correct price for a bad aim, but never a dud.
##
## The centre is taken at MID-BODY (halfway between the origin and the drawn head)
## rather than at either end: an orbit centred on the feet puts every crescent below
## the silhouette, and one centred on the head puts them above it.
func _mark(aim_point: Vector2) -> Vector2:
	var victim: Node2D = SpellTargets.nearest(aim_point, LOCK_RADIUS, _hostiles(),
		[caster_node], self)
	if victim == null:
		return aim_point
	return victim.global_position.lerp(SpellTargets.aim_point(victim), 0.5)


## When each cut lands and at what angle. Built once so the timeline is data the
## draw and the damage both read, rather than two clocks that can drift apart.
##
## The angles walk once round the circle from the side the caster came in on, with a
## small deterministic wobble so seven cuts do not look like a compass rose. The
## wobble is derived from the count (never `randf()`) so a headless test that fires
## this twice gets the same picture both times.
func _schedule() -> void:
	var base: Vector2 = _anchor - _origin
	var base_angle: float = base.angle() + PI if base.length_squared() > 0.0001 else 0.0
	for i: int in _count:
		_cut_at.append(LOCK_TELL + CUT_WINDOW * (float(i) + 0.5) / float(_count))
		_cut_angle.append(base_angle + TAU * float(i) / float(_count)
			+ 0.18 * sin(float(i) * 2.399))


## The finisher's timestamp, and the end of the node's life. Derived rather than
## stored: two constants and one schedule is one source of truth.
func _final_time() -> float:
	return LOCK_TELL + CUT_WINDOW + FINAL_GAP


func _life() -> float:
	return _final_time() + AFTER_GLOW


func _arm_telegraph() -> void:
	_telegraph = Telegraph.new()
	add_child(_telegraph)
	# Our own transform is the identity (we park at the origin), but set the GLOBAL
	# position anyway so this keeps working if a spectacle is ever parented somewhere
	# offset. The Telegraph is the one child here that is a real positioned node.
	_telegraph.global_position = _anchor
	_telegraph.accent = TELL_ACCENT
	_telegraph.style = Telegraph.Style.ZONE
	# ONE CLOCK. Its `_process` is off and we advance it by hand from `advance()`, so
	# the drawn tell and the damage cannot drift a frame apart. A tell that lies about
	# when the hit lands is worse than no tell.
	_telegraph.set_process(false)
	_telegraph.start(ORBIT_RADIUS + CUT_REACH, LOCK_TELL)


func _process(delta: float) -> void:
	advance(delta)


## Deterministic time-step, so a headless suite can drive the whole timeline without
## waiting on real frames (the idiom `BlinkStrike.advance` established).
func advance(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.advance(delta)
	while _fired < _cut_at.size() and _elapsed >= _cut_at[_fired]:
		var i: int = _fired
		_fired += 1
		_cut(_cut_angle[i], _damage, CUT_KNOCK, false)
	if not _final_done and _elapsed >= _final_time():
		_final_done = true
		_finish()
	if _elapsed >= _life():
		queue_free()
		return
	queue_redraw()


# ----------------------------------------------------------------- the damage
## One cut: the caster appears on the rim at `angle` and opens everything the blade
## reaches. Every body in the bite is measured to its DRAWN SILHOUETTE and gated on
## line of sight, so a head at blade height registers and a body behind cover does
## not.
func _cut(angle: float, damage: int, knock: float, is_final: bool) -> void:
	var dir: Vector2 = Vector2.from_angle(angle)
	var blade: Vector2 = _anchor + dir * ORBIT_RADIUS
	_place_caster(blade + dir * STAND_OFF)
	var tint := Color(_color.r, _color.g, _color.b, 1.0)
	var reach: float = CUT_REACH * (1.25 if is_final else 1.0)
	for e: Node in SpellTargets.in_radius(blade, reach, _hostiles(),
			[caster_node], self):
		# Deflectable: nothing physically travels here, so there is nothing to send
		# back and a correctly-timed guard EATS the cut. `blade` is the WORLD hit
		# point; this node's own transform is (0, 0).
		var dealt: int = SpellDeflect.resolve(e, damage, -dir, blade, _deflect_window())
		if dealt <= 0:
			continue   # guarded clean: no damage, no ailment, no shove
		SpellTargets.hurt(e, dealt, tint)
		if e.has_method("apply_status"):
			e.call("apply_status", element_id)   # SHADOW -> Weaken
		if e.has_method("apply_knockback"):
			# INWARD on the orbiting cuts (they hold the victim in the circle) and
			# OUTWARD on the finisher (which is supposed to end with a body leaving).
			var push: Vector2 = -dir if not is_final else \
				((e as Node2D).global_position - _anchor).normalized()
			if push == Vector2.ZERO:
				push = Vector2.UP
			e.call("apply_knockback", push * knock)
	for prop: Node in SpellTargets.in_radius(blade, reach,
			get_tree().get_nodes_in_group("destructible"), [caster_node], self):
		if prop.has_method("take_damage"):
			prop.call("take_damage", damage)
	SpellDrops.sfx("melee_hit" if not is_final else "melee_crit",
		-6.0 if not is_final else 0.0, 0.08, 1.15 if not is_final else 0.9)
	if not is_final:
		Juice.shake_camera(2.2)


## The reappearance. A heavier cut on the side the caster came in on, plus the whole
## punctuation budget — this is the beat the spell is for.
func _finish() -> void:
	var back: Vector2 = _origin - _anchor
	var angle: float = back.angle() if back.length_squared() > 0.0001 else 0.0
	_cut(angle, int(round(float(_damage) * FINAL_MULT)), FINAL_KNOCK, true)
	CombatVfx.spawn_burst(get_parent(), _anchor, CORE,
		Color(_color.r, _color.g, _color.b, 0.0), 34, 0.45, 90.0, 260.0, 0.8, 2.4,
		0.0, 0.0, true)
	Juice.hit_stop(0.10)
	Juice.shake_camera(11.0)
	# The shadow family's shared mark — the NEGATIVE (see BlinkStrike._detonate and
	# ShadowRoot._erupt), so the three shadow payoffs punctuate identically and the
	# player learns one reading for "the dark one landed".
	Juice.frame({
		"style": ImpactFrame.Style.INVERT, "strength": 0.9, "at": _anchor,
		"zoom": 0.10, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})
	SpellDrops.sfx("ult_unmaking", -3.0, 0.05, 1.05)


## Put the caster's body on the rim, through ITS OWN vetting contract.
##
## ⚠ NEVER A RAW `global_position` WRITE, for two separate reasons. The caster owns
## where its body may legally rest (`Hero.blink_to` refuses a spot inside geometry,
## over a ring-out pit, or outside the room and slides to the nearest legal one), and
## on a co-op peer the position comes from the MultiplayerSynchronizer — writing it
## here would fight the synchronizer and snap back. `blink_to` already handles both;
## a caster that does not declare it simply is not moved, which is the conservative
## direction and exactly the rule BlinkStrike._rescue_caster writes down.
func _place_caster(at: Vector2) -> void:
	if caster_node == null or not is_instance_valid(caster_node):
		return
	if not caster_node.has_method("blink_to"):
		return
	caster_node.call("blink_to", at)


## Everyone this spell may hurt, minus the caster. Never a bare
## `get_nodes_in_group(target_group)`: under friendly fire the caster is IN that
## group, and an ult that opens with a free cut on its own thrower is not a feature.
func _hostiles() -> Array:
	return SpellTargets.hostiles(self, StringName(target_group))


## How much of a victim's parry window counts against a cut. An ULT is BRUTAL to
## time — only the opening sliver connects — and the shelf the spell already declares
## picks the dial rather than this file inventing one.
func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


# --------------------------------------------- reaction contract (SpellReactor)
## World space, built from `_anchor` — NOT from `global_position`, which is (0, 0).
## The SAME radius the danger ring was drawn at and the cuts are measured in, so the
## reaction footprint cannot drift from the picture.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(_anchor, ORBIT_RADIUS + CUT_REACH)


## LOAD-BEARING: false for the whole tell, so the ring is a telegraph and nothing
## more, and false again once the afterglow is all that is left.
func reaction_active() -> bool:
	return _elapsed >= LOCK_TELL and _elapsed < _final_time() + 0.12


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.IMPACT


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: go without the finisher. There is nothing to dismiss — the
## Telegraph is our own child and dies with us.
func reaction_consume() -> void:
	queue_free()


# ------------------------------------------------------------------ the picture
## Is the cheap picture in force (the phone, and the maker's desktop LOW preview)?
## THE RULE: thin the GARNISH, never the READ. The crescents, the ring and the
## finisher all still draw at LOW — what goes is vertex count, the soft ghost pass
## and the tip glints.
func _low() -> bool:
	return TuningConfig.quality_is_low()


## A cut shape: widest mid-arc, tapering to needle points at both tips, drawn as one
## closed lens. `sin(t * PI)` is the taper. `draw_arc` cannot do this — its band is a
## constant width, which is why a slash drawn with it reads as a highlighter stroke.
func _crescent(radius: float, mid_angle: float, thickness: float) -> PackedVector2Array:
	var steps: int = CRESCENT_STEPS_LOW if _low() else CRESCENT_STEPS
	var pts := PackedVector2Array()
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		var a: float = mid_angle - CUT_SPAN + 2.0 * CUT_SPAN * t
		pts.append(_anchor + Vector2.from_angle(a) * (radius + thickness * 0.5 * sin(t * PI)))
	for i: int in steps + 1:
		var t: float = 1.0 - float(i) / float(steps)
		var a: float = mid_angle - CUT_SPAN + 2.0 * CUT_SPAN * t
		pts.append(_anchor + Vector2.from_angle(a) * (radius - thickness * 0.5 * sin(t * PI)))
	return pts


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < LOCK_TELL:
		_draw_mark()
	_draw_cuts()
	if _final_done:
		_draw_finish()


## The tell, drawn ON TOP of the Telegraph's danger ring: a noose of shadow closing
## on the mark. The ring says WHERE, the noose says WHEN — the tighter it is, the
## less time is left. Six spokes rather than a second ring, so it cannot be confused
## with the danger boundary it sits inside.
func _draw_mark() -> void:
	var t: float = clampf(_elapsed / LOCK_TELL, 0.0, 1.0)
	var r: float = (ORBIT_RADIUS + CUT_REACH) * (1.0 - 0.55 * t)
	var spokes: int = 4 if _low() else 6
	for i: int in spokes:
		var a: float = TAU * float(i) / float(spokes) + t * 1.4
		var d: Vector2 = Vector2.from_angle(a)
		draw_line(_anchor + d * r, _anchor + d * maxf(r - 26.0, 6.0),
			Color(_color.r, _color.g, _color.b, 0.35 + 0.5 * t), 2.4, true)
	draw_circle(_anchor, 3.5 + 8.0 * t,
		Color(CORE.r, CORE.g, CORE.b, 0.45 + 0.4 * t), true, -1.0, true)


## The orbiting crescents. Each fades over `CUT_VISIBLE`, so at any instant two or
## three are on screen at different ages — that overlap is what reads as a body being
## worked over rather than as a sequence of separate hits.
func _draw_cuts() -> void:
	var emissive: Color = Elements.emissive(element_id)
	var low: bool = _low()
	for i: int in _fired:
		var age: float = _elapsed - _cut_at[i]
		if age < 0.0 or age > CUT_VISIBLE:
			continue
		var life: float = age / CUT_VISIBLE
		var intensity: float = 1.0 - life * life   # ease-out: the cut lingers, then snaps
		var mid: float = _cut_angle[i]
		# The blade SWEEPS a little as it fades, so a crescent reads as a moving edge
		# rather than a decal that was switched on.
		mid += 0.30 * life * (1.0 if i % 2 == 0 else -1.0)
		var thick: float = CUT_THICKNESS * (0.55 + 0.45 * intensity)
		if not low:
			# 1) soft ghost — the wide tinted smear that sells the motion blur.
			draw_colored_polygon(_crescent(ORBIT_RADIUS, mid, thick * 2.3),
				Color(_color.r, _color.g, _color.b, 0.18 * intensity))
		# 2) body — the saturated blade.
		draw_colored_polygon(_crescent(ORBIT_RADIUS, mid, thick),
			Color(_color.r * 1.25, _color.g * 1.15, _color.b * 1.35, 0.82 * intensity))
		# 3) core — thin, over 1.0, so bloom catches the EDGE and not the whole smear.
		draw_colored_polygon(_crescent(ORBIT_RADIUS, mid, thick * 0.28),
			Color(emissive.r, emissive.g, emissive.b, 0.95 * intensity))
		if low:
			continue
		for tip: float in [-1.0, 1.0]:
			var p: Vector2 = _anchor + Vector2.from_angle(mid + tip * CUT_SPAN) * ORBIT_RADIUS
			draw_circle(p, 2.6 * intensity,
				Color(emissive.r, emissive.g, emissive.b, 0.85 * intensity))


## The finisher's afterglow: a hard ring held at EXACTLY the radius that was cut, so
## the last thing on screen is an honest statement of the spell's extent. The maker's
## rule is that nothing may land outside what was drawn.
func _draw_finish() -> void:
	var f: float = clampf((_elapsed - _final_time()) / AFTER_GLOW, 0.0, 1.0)
	var alpha: float = 1.0 - f
	draw_arc(_anchor, ORBIT_RADIUS + CUT_REACH, 0.0, TAU, 40,
		Color(_color.r, _color.g, _color.b, 0.40 * alpha), 2.0, true)
	draw_arc(_anchor, (ORBIT_RADIUS + CUT_REACH) * f, 0.0, TAU, 40,
		Color(CORE.r, CORE.g, CORE.b, 0.85 * alpha), lerpf(6.0, 1.5, f), true)
