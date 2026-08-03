class_name IaiSlash
extends Node2D
## IAI SLASH — the Swordsaint's damage line. One committed draw-cut: short range,
## brutal damage, a long wait afterwards. The punish half of "guard and punish".
##
## ═══════════════════════════════════════════════════════════════════════════════
## WHY IT EXISTS
## ═══════════════════════════════════════════════════════════════════════════════
## The Swordsaint's damage slot held `blade_flurry` — the SHADOWBLADE's spell, worn
## by two classes at once. Two duelists throwing the identical fan of crescents is
## the recolour problem in its purest form, and it left the class with no verb of its
## own at all: its RMB is a held BLADE guard that banks a parry and returns it as an
## unsheathe cut, and there was nothing in the kit that answered that fantasy. This
## is the answer. The guard is the question; this is the punish.
##
## ── WHAT MAKES IT NOT BLADE FLURRY, AND NOT A BEAM ────────────────────────────
## `BladeFlurry` is FIVE cuts across a wide forward cone, cheap, thrown all fight,
## and forgiving about where you were pointing. This is ONE cut down a NARROW
## corridor, expensive, and it either lands whole or it costs you five seconds. The
## Flurry is attrition; this is a single decision. They are opposites on purpose.
##
## It is also emphatically not a beam: `reach` is 118 px, roughly a body and a half.
## Nothing about this crosses the arena.
##
## ═══════════════════════════════════════════════════════════════════════════════
## THE TELL AND THE COUNTERPLAY (the locked "everything must be dodgeable" rule)
## ═══════════════════════════════════════════════════════════════════════════════
## TELL — `DRAW_TIME` seconds of a shared `Telegraph` LINE laid along EXACTLY the
##   corridor that will be cut (same length, same width, same angle), with the blade's
##   own gleam drawn extending along it. Using the shared Telegraph rather than
##   drawing our own lane buys the danger grammar the game already teaches, and puts
##   the node in the `telegraph` group so `BotDodge` can perceive and dodge it.
##
## COUNTERPLAY — three, and all of them are free:
##   * STEP OUT OF THE LANE. It is 118 px long and 52 px wide, drawn 0.30 s early.
##     One sidestep or one jump clears it.
##   * BACK OFF. Almost every other threat in the game outranges this. Refusing to be
##     within a body and a half of a Swordsaint is a whole strategy.
##   * BAIT IT. WHIFFING MUST HURT, and that is what the 5.0 s cooldown is for — it
##     is not a balance number, it is the counterplay. A dodged Iai Slash is five
##     seconds of a duelist with no damage line.
##
## ═══════════════════════════════════════════════════════════════════════════════
## PLAIN STEEL: WHY THIS CUT APPLIES NO AILMENT
## ═══════════════════════════════════════════════════════════════════════════════
## `Hero.CLASS_CONFIG[SWORDSAINT].melee_element` is -1 on purpose — "plain steel: no
## ailment" — and that idea is respected here: **`apply_status` is never called.** The
## cut burns nothing, freezes nothing and weakens nothing. It just opens you.
##
## ⚠ THAT IS NOT THE SAME AS BEING ELEMENTLESS, and the difference is a trap this
## repo has already paid for twice. Leaving `element_id` at -1 would make
## `SpellCaster.resolve_element` GUESS (its "holy" arm wrongly answers LIGHTNING) and
## would make `SpellReactor.register` silently DROP this effect from the reaction
## system entirely — an invisible failure that looks exactly like working code. So
## ARCANE is declared outright: it is what the class already casts with, it is what
## the reaction table clashes and opposes on, and it tints the steel. The ailment is
## withheld by the one line that is missing below, not by leaving a field unset.
##
## UNPLAYTESTED. Every number is a reasoned first guess with the reasoning attached.

# ------------------------------------------------------------------- the beats
## THE DODGE BUDGET: the draw. Reference points — `BlinkStrike.BLAST_TELL` is 0.30
## for a spell whose whole verb is speed, and `BlastSpell.WINDUP` is 0.55 for an AoE
## you are meant to stroll out of. A committed melee cut sits at the fast end: long
## enough for one reaction, short enough that a duelist inside your guard is still
## terrifying.
const DRAW_TIME: float = 0.30
## How long the cut itself is drawn after it resolves. Must clear `Telegraph.FADE_TIME`
## (0.15) so the lane's own fade is not cut off mid-frame.
const CUT_TIME: float = 0.16
## The sheathe. A committed cut needs a beat of stillness on the end or it reads as a
## poke; this is that beat, and it is when the after-line thins out to nothing.
const SHEATHE_TIME: float = 0.34

## Where the blade actually is, relative to the caster's origin. The rigs draw a body
## whose head centre sits ~10 px above the node origin, so a corridor fired from the
## origin runs through the shins. This lifts it to roughly hand height.
const MUZZLE_LIFT: float = -14.0

## Along the cut, plus a small lift so a struck body rises off the floor rather than
## sliding. Big, because a committed cut that does not move the victim reads as a
## graze. `BladeFlurry.KNOCKBACK` is 150 for one of five cuts; this is one of one.
const KNOCKBACK: float = 330.0
const LIFT: float = 120.0

# ---------------------------------------------------------------- the picture
## Peak of `pow(t, 1.6) * pow(1 - t, 0.7)` over [0, 1], reached at t = 1.6 / 2.3.
## DERIVED, not measured by eye: it is what normalises the lens so its widest point
## is exactly the damage corridor's half-width. Change either exponent and this must
## change with it — which is why it is written as the arithmetic and not as 0.245.
const LENS_PEAK: float = 0.24499  # pow(1.6/2.3, 1.6) * pow(0.7/2.3, 0.7)
const LENS_STEPS: int = 16
## The mobile picture: fewer vertices in the cut lens, no ghost pass, no gleam
## particles. The SHAPE and its extent survive at LOW — see `_low()`.
const LENS_STEPS_LOW: int = 8
## HDR steel-white, > 1.0 so the edge blooms through the post grade while the body of
## the cut stays a controlled arcane magenta.
const CORE: Color = Color(1.60, 1.55, 1.75)
## The danger lane keeps the game's DANGER hue rather than the spell's magenta: red is
## what this codebase has taught the player to read as "move".
const TELL_ACCENT: Color = Color(0.95, 0.16, 0.13, 0.9)

# ------------------------------------------------- the stamp (all five, declared)
## ⚠ ALL FIVE ARE DECLARED BECAUSE `set()` ON AN UNDECLARED PROPERTY IS A SILENT
## NO-OP. `BladeFlurry` shipped with only `element_id` declared, which made it report
## as unowned, match no ownership-gated clash row, and sit quietly inert in the
## reaction system while looking perfectly fine on screen.
var target_group: String = "enemy"
var _target_group: String = "enemy"
## Declared, never guessed — see PLAIN STEEL above.
var element_id: int = Elements.Element.ARCANE
var spell_tier: int = SpellTier.Tier.HEAVY
var caster_node: Node = null
## Overrides `SpellSigil.MOTIF_BY_SCRIPT` (a table this workstream does not own) so
## the summoning circle says "a cut lands" with no entry needed there.
var sigil_motif: int = MagicCircle.Motif.BLADE

var _muzzle: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(0.95, 0.4, 0.85, 1.0)
var _damage: int = 96
var _reach: float = 118.0
var _half: float = 26.0
var _elapsed: float = -1.0    ## < 0 means hex() has not run yet
var _cut_done: bool = false
var _telegraph: Telegraph = null


## Cast entry — the fixed shape every `SpellCaster.HEX_SCRIPTS` entry shares.
## `target` arrives already clamped to the spell's `reach` by the HEX arm; only its
## DIRECTION is used here, because the cut's length is the blade's, not the cursor's.
func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	_muzzle = origin + Vector2(0.0, MUZZLE_LIFT)
	var aim: Vector2 = target - origin
	_dir = aim.normalized() if aim.length_squared() > 0.0001 else Vector2.RIGHT
	_color = color
	_damage = maxi(spell.damage, 1)
	# `reach` is the cut's LENGTH and `width` its full thickness — the same two
	# numbers the Telegraph lane, the damage corridor and the drawn lens all read, so
	# the picture and the hitbox cannot disagree.
	_reach = maxf(spell.reach, 24.0)
	_half = maxf(spell.width, 4.0) * 0.5
	# The blade gate, edge-on down the cut: the cut is DRAWN from a sigil rather than
	# appearing. Held for the draw plus the cut so the gate closes after the edge does.
	SpellSigil.open(self, _muzzle, _color, 0.85, true, _dir, false, 0.14,
		DRAW_TIME + CUT_TIME)
	_arm_telegraph()
	SpellDrops.sfx("melee_swing_heavy", -4.0, 0.05, 0.85)
	_elapsed = 0.0
	# Join the reaction system now; `reaction_active` keeps it inert until the cut
	# actually lands, so a danger lane cannot annihilate anything on its own.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.IMPACT, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


func _life() -> float:
	return DRAW_TIME + CUT_TIME + SHEATHE_TIME


## The lane, laid along EXACTLY the corridor that will be cut. It is placed at the
## muzzle and angled down the aim; `start_line` promotes ZONE style to LANE for us.
##
## ONE CLOCK: its `_process` is off and `advance()` drives it, so the drawn tell and
## the damage cannot drift a frame apart, and the whole timeline is drivable from a
## headless test.
func _arm_telegraph() -> void:
	_telegraph = Telegraph.new()
	add_child(_telegraph)
	_telegraph.global_position = _muzzle
	_telegraph.accent = TELL_ACCENT
	_telegraph.style = Telegraph.Style.LANE
	_telegraph.aim_dir = _dir
	_telegraph.reach = _reach
	_telegraph.set_process(false)
	_telegraph.start_line(_reach, _half * 2.0, _dir.angle(), DRAW_TIME)


func _process(delta: float) -> void:
	advance(delta)


## Deterministic time-step (the idiom `BlinkStrike.advance` established) so a headless
## suite can drive draw -> cut -> sheathe without waiting on real frames.
func advance(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.advance(delta)
	if not _cut_done and _elapsed >= DRAW_TIME:
		_cut_done = true
		_cut()
	if _elapsed >= _life():
		queue_free()
		return
	queue_redraw()


# ------------------------------------------------------------------ the damage
## The cut. A capsule corridor query — silhouette-measured (so a head at blade height
## registers where a point test at the stomach sailed through) and line-of-sight
## gated from the muzzle (so cover stops it). Both are `SpellTargets` behaviours; this
## file re-implements neither.
func _cut() -> void:
	var tint := Color(_color.r, _color.g, _color.b, 1.0)
	var tip: Vector2 = _muzzle + _dir * _reach
	var hit_any: bool = false
	for e: Node in SpellTargets.on_line(_muzzle, _dir, _reach, _half, _hostiles(),
			[caster_node], self):
		# Deflectable: a cut does not travel, so there is nothing to send back and a
		# correctly-timed guard EATS it. The hit point is the closest approach on the
		# corridor, not this node's transform — which is (0, 0).
		var at: Vector2 = SpellGeometry.closest_point_on_segment(
			SpellTargets.aim_point(e), _muzzle, tip)
		var dealt: int = SpellDeflect.resolve(e, _damage, _dir, at, _deflect_window())
		if dealt <= 0:
			continue   # guarded clean: no damage, no shove
		SpellTargets.hurt(e, dealt, tint)
		hit_any = true
		# ⚠ NO `apply_status` HERE, AND ITS ABSENCE IS THE FEATURE. See PLAIN STEEL in
		# the class docs: the Swordsaint's steel carries no element onto a body. Adding
		# one line here would quietly delete the class's stated flavour rule.
		if e.has_method("apply_knockback"):
			e.call("apply_knockback", _dir * KNOCKBACK + Vector2.UP * LIFT)
	for prop: Node in SpellTargets.on_line(_muzzle, _dir, _reach, _half,
			get_tree().get_nodes_in_group("destructible"), [caster_node], self):
		# Chip the cut-FACING side where the prop offers it, so cover breaks WHERE it
		# was struck — the same call BlastSpell and BlinkStrike make.
		if prop.has_method("damage_at"):
			var pp: Vector2 = (prop as Node2D).global_position
			var contact: Vector2 = SpellGeometry.closest_point_on_segment(pp, _muzzle, tip)
			prop.call("damage_at", _damage, contact, _dir)
		elif prop.has_method("take_damage"):
			prop.call("take_damage", _damage)
	CombatVfx.spawn_burst(get_parent(), _muzzle + _dir * _reach * 0.6, CORE,
		Color(_color.r, _color.g, _color.b, 0.0), 22, 0.3, 90.0, 240.0, 0.6, 1.8,
		0.0, 0.0, true, _dir, 24.0)
	# The WEIGHT is all here — a single committed cut should feel like one heavy
	# event, not a patter. A hair under BlastSpell's 0.09 because this is a HEAVY.
	Juice.hit_stop(0.08)
	Juice.shake_camera(9.0)
	Juice.kick_camera(_dir, 5.0)
	# The punctuation, on the rung the spell's own shelf puts it. SILHOUETTE would be
	# the anime pick, but this payoff IS a readable shape, and the tier ladder already
	# picks a mark per shelf — so the shelf decides, not this file.
	Juice.tier_frame(spell_tier, _muzzle + _dir * _reach * 0.5, element_id,
		{"zoom": 0.08, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	SpellDrops.sfx("melee_crit" if hit_any else "melee_swing", -1.0 if hit_any else -8.0,
		0.06, 0.95)


## Everyone this spell may hurt, minus the caster. Never a bare group scan: under
## friendly fire the caster is in that group and would cut itself.
func _hostiles() -> Array:
	return SpellTargets.hostiles(self, StringName(target_group))


## How much of a victim's parry window counts against this cut. The shelf the spell
## already declares picks the dial rather than this file inventing a second one.
func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


# --------------------------------------------- reaction contract (SpellReactor)
## World space, built from `_muzzle` — NOT from `global_position`, which is (0, 0).
## The same capsule the damage query uses, so the reaction footprint and the hitbox
## are one number.
func reaction_shape() -> Dictionary:
	return SpellGeometry.capsule(_muzzle, _muzzle + _dir * _reach, _half * 2.0)


## LOAD-BEARING: false for the whole draw, so the lane is a telegraph and nothing
## more. True only while the cut is actually on screen.
func reaction_active() -> bool:
	return _cut_done and _elapsed < DRAW_TIME + CUT_TIME


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
## The cheap picture (the phone, and the maker's desktop LOW preview). THE RULE:
## thin the garnish, never the read — the lane, the gleam and the cut lens all still
## draw at LOW; what goes is vertex count and the soft ghost pass.
func _low() -> bool:
	return TuningConfig.quality_is_low()


## The cut, as one closed lens: a needle at the muzzle, widest at `_half` about
## two-thirds along, and a needle again at the tip. That taper is the difference
## between a drawn blade and a rectangle — and it states the corridor's true width at
## its widest point, which is what the damage query uses.
func _lens(width_scale: float, length_scale: float) -> PackedVector2Array:
	var steps: int = LENS_STEPS_LOW if _low() else LENS_STEPS
	var n: Vector2 = Vector2(-_dir.y, _dir.x)
	var span: float = _reach * length_scale
	var pts := PackedVector2Array()
	for side: float in [1.0, -1.0]:
		for i: int in steps + 1:
			var t: float = float(i) / float(steps) if side > 0.0 \
				else 1.0 - float(i) / float(steps)
			# SKEWED TAPER, fat about seven tenths of the way out, so it reads as a cut
			# that ACCELERATED rather than as a symmetric leaf. The exponents were the
			# other way round on the first render and put the belly at the MUZZLE, which
			# photographed as a blob hanging off the caster's hand.
			#
			# `LENS_PEAK` normalises the curve so the widest point is exactly `_half` —
			# the corridor's true half-width. Without it the drawing understated the
			# hitbox by ~20 %, and the maker's rule is that nothing may land outside what
			# was drawn.
			var w: float = _half * width_scale 				* pow(t, 1.6) * pow(1.0 - t, 0.7) / LENS_PEAK
			pts.append(_muzzle + _dir * (span * t) + n * (w * side))
	return pts


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if not _cut_done:
		_draw_gleam()
		return
	_draw_cut()


## The draw. A hairline of light creeping down the corridor as the blade leaves the
## sheath — it reaches the tip on the exact frame the cut lands, so the lane's length
## is being counted out in front of the victim. Plus a thickening glint at the muzzle:
## the two together say "from here, to there, now".
func _draw_gleam() -> void:
	var t: float = clampf(_elapsed / DRAW_TIME, 0.0, 1.0)
	var tip: Vector2 = _muzzle + _dir * (_reach * t)
	draw_line(_muzzle, tip, Color(_color.r, _color.g, _color.b, 0.30 + 0.5 * t),
		1.4 + 1.6 * t, true)
	draw_circle(_muzzle, 3.0 + 6.0 * t,
		Color(CORE.r, CORE.g, CORE.b, 0.45 + 0.45 * t), true, -1.0, true)
	if _low():
		return
	# Two hairlines set out at the corridor's true half-width, converging on the tip:
	# the lane's WIDTH stated without a second filled shape competing with the
	# Telegraph's own lane drawing underneath.
	var n: Vector2 = Vector2(-_dir.y, _dir.x)
	for side: float in [1.0, -1.0]:
		draw_line(_muzzle + n * (_half * side), tip + n * (_half * 0.35 * side),
			Color(_color.r, _color.g, _color.b, 0.16 + 0.22 * t), 1.0, true)


## The cut itself: three stacked passes, the same grammar `BladeFlurry` uses for its
## crescents — a soft tinted ghost, a saturated body, and a thin over-1.0 core so the
## bloom catches the EDGE and not the whole smear.
func _draw_cut() -> void:
	var f: float = clampf((_elapsed - DRAW_TIME) / (CUT_TIME + SHEATHE_TIME), 0.0, 1.0)
	var intensity: float = 1.0 - f * f
	var emissive: Color = Elements.emissive(element_id)
	if not _low():
		# The ghost is a HINT of motion blur, not a second blade. It was 2.4x at 0.20
		# alpha on the first render and swallowed the cut it was supposed to trail.
		draw_colored_polygon(_lens(1.7, 1.0),
			Color(_color.r, _color.g, _color.b, 0.13 * intensity))
	draw_colored_polygon(_lens(1.0, 1.0),
		Color(_color.r * 1.25, _color.g * 1.1, _color.b * 1.3, 0.85 * intensity))
	draw_colored_polygon(_lens(0.26, 1.0),
		Color(emissive.r, emissive.g, emissive.b, 0.95 * intensity))
	# The after-line: a hairline held at EXACTLY the full reach for the whole sheathe,
	# so the last thing on screen is an honest statement of how far the cut went. The
	# maker's rule is that nothing may land outside what was drawn.
	draw_line(_muzzle, _muzzle + _dir * _reach,
		Color(CORE.r, CORE.g, CORE.b, 0.55 * intensity), 1.2, true)
