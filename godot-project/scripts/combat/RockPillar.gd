class_name RockPillar
extends Node2D

## Who this pillar's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## Earthbending ROCK PILLAR (the uppercut). A telegraphed danger footprint +
## rumble, then ONE sharp stone FANG jabs up from the ground at the marked point,
## launching everything in its footprint straight UP (big vertical knockback) +
## damage + Stagger, then crumbles into rubble and leaves a cracked ground.
## Instantiate .new(), add to arena, call erupt(). Draws in world coordinates.
##
## Identity split (magic-overhaul phase 2): rock_pillar is the FAST, SHARP,
## SINGLE spike — warm brown, snappy, punts one target skyward. The slow, vast,
## multi-slab area-denial spire is Colossus Pillar (DivineRay stone mode). The
## old stacked-block column read as a mini-colossus, so the silhouette here is
## now a tapering fang with an HDR tip glint instead of block strata.
##
## ⚠ THIS SPELL USED TO LIE ABOUT ITS OWN SIZE, and the fix is the main change in
## this file. It DREW a 46 px-wide fang and DAMAGED a 66 px circle centred on the
## ground point — 2.9x the drawn horizontal reach, and (much worse) 66 px of that
## circle pointed straight DOWN THROUGH THE FLOOR, so anything standing in the
## room below took an uppercut through solid rock. Both halves violate the
## maker's rule ("the spells shouldn't be able to get out the radius"), and the
## downward half violates the bigger one ("no spell may pass through geometry").
## The damage footprint is now the DRAWN FANG: a vertical capsule from the ground
## point up to the fang's tip, half as wide as the fang is wide, and nothing
## below the ground line at all. See `_apply_launch`.
##
## World contract (docs/spell-world-contract.md), all four parts:
##   SPAWN  — the fang stands on the floor found by SpellWorld.floor_below, and
##            over a pit there is NO eruption rather than a fang hanging in air.
##   TRAVEL — the fang GROWS upward, so it is clipped against whatever is above
##            it (a ledge, a platform, a ceiling) and smashes the destructible
##            cover it tears through on the way.
##   TARGETS— SpellTargets.on_line against the fang capsule: silhouette-tested
##            (so a head at fang-tip height registers) and line-of-sight-gated.
##   DEFLECT— the fang does not TRAVEL as a body, so it is the SpellDeflect.resolve
##            flavour of deflectable: a well-timed guard EATS the uppercut.

## THE DODGE BUDGET. You get this long, with a drawn danger footprint and a
## rumble under your feet, to walk out of the fang's column before a single point
## of damage lands. Nothing about this spell is instant.
## UNTESTED GUESS: 0.40 s is a hair under BlastSpell's 0.55 giant-AoE windup —
## the pillar is a snappy uppercut, not a bombardment, so its tell is shorter,
## but it is still long enough to react to rather than only to pre-empt.
const CHARGE_TIME: float = 0.40
const ERUPT_RISE: float = 0.14     # column shoots up
const PILLAR_HOLD: float = 0.22
const CRUMBLE_TIME: float = 0.34
const PILLAR_HEIGHT: float = 150.0
const PILLAR_WIDTH: float = 46.0
const DEFAULT_RADIUS: float = 66.0
const DEFAULT_DAMAGE: int = 58
const UP_KNOCKBACK: float = 620.0  # BIG vertical launch — routed into velocity.y
const DEBRIS_COUNT: int = 18
const BLOCKS: int = 5

## HALF the drawn fang's width, and therefore the damage capsule's half-width.
## ONE number for the picture and the hitbox — the whole point of this file's fix.
## Do not add "a little forgiveness" on top of it at the call site: the target's
## own `hit_margin()` already supplies that, and a second margin scheme here is
## exactly the two-schemes bug SpellTargets exists to end.
const FANG_HALF_WIDTH: float = PILLAR_WIDTH * 0.5

## How far down we look for the ground the fang stands on. Generous enough to
## find the floor when the aim point is marked above a target's head, short
## enough that a mark over a genuine pit reports "no floor" rather than finding
## some slab three screens down. UNTESTED GUESS.
const FLOOR_PROBE: float = 200.0

## Parallel samples used when clipping the growing fang against what is above it.
## The fang is 46 px wide, so a hairline centre ray would let it grow straight
## past the corner of a ledge it visibly punches into. UNTESTED GUESS: 3, the
## same count SpellWorld's THICK_SAMPLES settled on for a wall's front edge.
const CEILING_SAMPLES: int = 3

## The damage capsule — and therefore its line-of-sight rays — starts this far
## ABOVE the ground point. `_ground` is a raycast hit position, i.e. EXACTLY on
## the floor's top face, and a LOS ray fired from a point sitting on a collider
## can report an instant block against the very surface the fang is growing out
## of, which would cull every target the pillar has. Two px is invisible at the
## fang's base and is well inside any standing body's silhouette.
## UNTESTED GUESS — if pillars ever start hitting nothing at all, look here first.
const LOS_LIFT: float = 2.0

## Below this the fang is not worth erupting at all — it would be a stub of rock
## with a damage capsule too short to read as an uppercut. Happens when the mark
## lands in a crawlspace. UNTESTED GUESS.
const MIN_FANG_HEIGHT: float = 24.0

const BODY_COLOR: Color = Color(0.34, 0.24, 0.15)
const LIT_COLOR: Color = Color(0.62, 0.46, 0.26)
const RIM_COLOR: Color = Color(1.15, 0.92, 0.55)
const SEAM_COLOR: Color = Color(0.2, 0.14, 0.09)

var _ground: Vector2 = Vector2.ZERO
var _color: Color = Color(0.78, 0.55, 0.28)
## NOTE there is deliberately NO `_radius` field any more. Storing the caller's
## radius alongside `_half_width` / `_height` is exactly how the drawn-vs-damaged
## drift started: two numbers describing one shape, and only one of them read by
## the draw. `radius` is consumed once, in `erupt`, to scale the fang — after that
## the fang's own dimensions are the only truth in this file.
var _damage: int = DEFAULT_DAMAGE
var element_id: int = -1
## Who cast this, for the reaction layer's same-owner rules and so the fang's own
## caster is never treated as world geometry standing in its way. Set by the
## caller (SpellCaster / Boss); null is a legal "unowned" pillar.
var caster_node: Node = null
## Reaction weight — see SpellTier. Set by SpellCaster at cast time; the default
## middle shelf means an unset pillar stays evenly matched with every other
## un-adopted spectacle, exactly as it behaves today.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## The fang's ACTUAL drawn size this cast, after `radius` scaling and after the
## ceiling clip. Both the draw and the damage capsule read these and nothing else.
var _half_width: float = FANG_HALF_WIDTH
var _height: float = PILLAR_HEIGHT

var _elapsed: float = -1.0
var _erupted: bool = false
var _rumble_accum: float = 0.0
var _jitter: PackedFloat32Array = PackedFloat32Array()


## Erupt a fang at `target`. `radius` scales the WHOLE fang — width, height and
## the drawn danger footprint together — rather than inflating an invisible
## damage circle around it. At the library's 66.0 (and the Boss's 66.0) the scale
## is exactly 1.0, so every shipping caster draws precisely what it drew before.
func erupt(
	target: Vector2, color: Color = Color(0.78, 0.55, 0.28),
	radius: float = DEFAULT_RADIUS, damage: int = DEFAULT_DAMAGE, _effect: String = "earth"
) -> void:
	_color = color
	_damage = damage
	var scale_f: float = maxf(radius, 1.0) / DEFAULT_RADIUS
	_half_width = FANG_HALF_WIDTH * scale_f
	# THE FLOOR RULE (docs/spell-world-contract.md): a ground-planted spell resolves
	# its base against the floor BENEATH the mark, never against the mark's own y —
	# an aim point is a cursor position and lands in mid-air as often as not.
	var ground: Dictionary = SpellWorld.floor_below(
		target, FLOOR_PROBE, SpellWorld.rids([caster_node]), self)
	if not bool(ground["hit"]):
		# Over a pit. A pillar of rock cannot erupt out of a hole, and dropping it
		# to the end of the probe would plant a fang in the void — the exact class
		# of bug this contract exists to stop. No strike, no spectacle.
		queue_free()
		return
	_ground = ground["position"]
	# THE CEILING RULE: the fang GROWS, so it is a travelling thing and must stop
	# at the first solid it meets. Thick, because a 46 px fang straddles corners a
	# hairline ray slips past. Destructible cover overhead is torn through, not
	# respected — and comes back to be damaged.
	#
	# The ray STARTS at LOS_LIFT above the ground point, not at it. `_ground` is a
	# raycast hit position — exactly on the floor's top face — and a ray fired from
	# a point lying on a collider reports an instant hit at distance zero against
	# the very floor the fang is growing out of. Left uncorrected the fang clips
	# itself to nothing on flat ground, which is a silent "this spell does nothing"
	# rather than a loud failure.
	var natural: float = PILLAR_HEIGHT * scale_f
	var base: Vector2 = _ground + Vector2.UP * LOS_LIFT
	var up_tip: Vector2 = _ground + Vector2.UP * natural
	var clipped: Dictionary = SpellWorld.first_solid_thick(
		base, up_tip, _half_width * 2.0, CEILING_SAMPLES,
		SpellWorld.rids([caster_node]), self)
	_height = (LOS_LIFT + float(clipped["distance"])) if bool(clipped["hit"]) else natural
	if _height < MIN_FANG_HEIGHT:
		queue_free()
		return
	for smashed: Node in (clipped["smashed"] as Array[Node]):
		_smash(smashed)
	_elapsed = 0.0
	for i in BLOCKS:
		_jitter.append(randf_range(-0.28, 0.28))
	# THE MARK ON THE GROUND THE FANG COMES OUT OF. Laid flat at the resolved floor
	# point — NOT at the aim point, which is a cursor position and is in mid-air as
	# often as not. Sized off the fang's own width so the mark and the stone match,
	# and held through the charge so it is the telegraph and not an afterthought.
	SpellSigil.open(self, _ground, color, maxf(_half_width * 2.4, 26.0) / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.14, 0.5)
	Sfx.play("earth", -3.0, 0.08)
	Juice.shake_camera(3.0)
	# Join the reaction system. Registering during the CHARGE is correct and
	# mirrors BeamSpell: `reaction_active()` keeps the fang inert until the stone
	# is actually there, so a telegraph cannot annihilate anything.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.BARRIER, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) -----------------------------------

## World-space geometry built from `_ground` and the CLIPPED fang — never from
## `global_position`, which is (0, 0) because this node draws in world
## coordinates. Deliberately the SAME capsule `_apply_launch` damages, so the
## shape a reaction resolves against and the shape that hurts you cannot drift.
func reaction_shape() -> Dictionary:
	return SpellGeometry.capsule(_ground, _fang_tip(), _half_width * 2.0)


## LOAD-BEARING: false for the whole CHARGE_TIME telegraph (there is no stone
## yet) and false once the fang has finished crumbling. True exactly while rock
## is standing there.
func reaction_active() -> bool:
	return _erupted and _elapsed < _total_time()


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.BARRIER


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: the fang was eaten, so it goes without its crumble beat
## and without leaving the cracked-ground decal a completed eruption leaves.
func reaction_consume() -> void:
	queue_free()


# --- the eruption ------------------------------------------------------------

func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _elapsed < CHARGE_TIME:
		# Rumble pulses during the tell.
		_rumble_accum += delta
		if _rumble_accum >= 0.12:
			_rumble_accum = 0.0
			Juice.shake_camera(2.0)
			CombatVfx.spawn_burst(get_parent(), _ground, Color(0.7, 0.52, 0.3, 0.5),
				Color(0.4, 0.28, 0.15, 0.0), 4, 0.35, 30.0, 90.0, 1.0, 2.5)
	elif not _erupted:
		_erupted = true
		_apply_launch()
		DebrisChunk.spawn_burst(get_parent(), _ground, Color(0.5, 0.38, 0.22), DEBRIS_COUNT, Vector2.UP, 300.0)
		CombatVfx.spawn_burst(get_parent(), _ground, Color(0.85, 0.62, 0.35, 0.9),
			Color(0.4, 0.28, 0.15, 0.0), 24, 0.5, 90.0, 280.0, 1.6, 4.5)
		Juice.on_hit({"shake": 15.0, "zoom": 0.1, "sfx": "blast", "sfx_pitch": 0.08, "hitstop": 0.09})
		Juice.zoom_pull_camera(0.14, 0.4, 0.14, 0.5)
		# Stone punching up out of the floor is pure CONCUSSION — no shape to
		# preserve, nothing elemental to say — which is the one thing the white
		# blow-out has always been exactly right for. Straight off the ladder at
		# this pillar's own shelf. Camera + freeze suppressed (fired above).
		Juice.tier_frame(spell_tier, _ground, element_id,
			{"style": ImpactFrame.Style.BLOWOUT,
			"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	var total: float = _total_time()
	if _elapsed >= CHARGE_TIME + ERUPT_RISE + PILLAR_HOLD and _elapsed < total:
		# Crumble: shed rubble as it collapses (a couple of staggered pops).
		if fmod(_elapsed, 0.12) < delta:
			DebrisChunk.spawn_burst(get_parent(), _ground - Vector2(0.0, _height * 0.6),
				Color(0.5, 0.38, 0.22), 6, Vector2.ZERO, 170.0)
	if _elapsed >= total:
		ScorchDecal.spawn(get_parent(), _ground, _half_width, "crack",
			Color(0.6, 0.45, 0.28, 0.55), 7.0)
		queue_free()
		return
	queue_redraw()


func _total_time() -> float:
	return CHARGE_TIME + ERUPT_RISE + PILLAR_HOLD + CRUMBLE_TIME


## The tip of the drawn fang, in world space. The one place the fang's extent is
## computed, so the draw, the damage capsule and the reaction shape agree by
## construction rather than by three matching edits.
func _fang_tip() -> Vector2:
	return _ground + Vector2.UP * _height


## THE FIX. Damage is the DRAWN FANG and nothing else: a vertical capsule from
## the ground point up to the tip, `_half_width` either side, with line of sight
## from the base. What that changes, plainly:
##
##   * horizontal reach drops from 66 px to 23 px (+ the target's own hit_margin,
##     ~3.7 px on a standard rig, ~7 px on a 1.9x sparring dummy). The pillar IS
##     less generous now — it is an uppercut you have to be standing in, not a
##     small blast. That is the intended balance consequence, not a side effect.
##   * VERTICAL reach grows: it now covers the fang's whole 150 px column, so
##     something already airborne over the mark is caught, which is what the
##     picture always promised.
##   * downward reach becomes ZERO. Nobody under the floor is uppercut through it.
func _apply_launch() -> void:
	var base: Vector2 = _ground + Vector2.UP * LOS_LIFT  # see LOS_LIFT
	var reach: float = maxf(_height - LOS_LIFT, 0.0)
	var skip: Array = [caster_node]
	for enemy: Node in SpellTargets.on_line(base, Vector2.UP, reach, _half_width,
			get_tree().get_nodes_in_group(target_group), skip, self):
		# Deflect at the moment of DAMAGE — the fang is not a body that travels,
		# so there is nothing to send back and a well-timed guard EATS the hit
		# (SpellDeflect's non-travelling path). WINDOW_NORMAL: the pillar is a
		# heavy but ordinary spell, not an ult, so the whole parry window counts.
		var dealt: int = SpellDeflect.resolve(enemy, _damage, Vector2.UP,
			SpellTargets.aim_point(enemy))
		if dealt > 0 and enemy.has_method("take_damage"):
			enemy.take_damage(dealt)
		if dealt <= 0:
			continue  # parried: no ailment, no launch — the guard ate all of it
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			# Straight up (small horizontal jitter) — the uppercut launch.
			var up: Vector2 = Vector2(randf_range(-0.2, 0.2), -1.0).normalized()
			enemy.apply_knockback(up * UP_KNOCKBACK)
	for prop: Node in SpellTargets.on_line(base, Vector2.UP, reach, _half_width,
			get_tree().get_nodes_in_group("destructible"), skip, self):
		_smash(prop)


## Damage one destructible, preferring the localized `damage_at` so cover breaks
## where the fang split it. Shared by the ceiling clip (things the fang tore
## through on the way up) and the eruption footprint.
func _smash(prop: Node) -> void:
	if prop == null or not is_instance_valid(prop) or prop.is_queued_for_deletion():
		return
	if prop.has_method("damage_at"):
		var at: Vector2 = (prop as Node2D).global_position if prop is Node2D else _ground
		prop.call("damage_at", _damage, at, Vector2.UP)
	elif prop.has_method("take_damage"):
		prop.call("take_damage", _damage)


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < CHARGE_TIME:
		_draw_telegraph()
		return
	# Column height + fade.
	var local: float = _elapsed - CHARGE_TIME
	var height: float
	var alpha: float = 1.0
	if local < ERUPT_RISE:
		height = _height * (1.0 - pow(1.0 - local / ERUPT_RISE, 2.0))
	elif local < ERUPT_RISE + PILLAR_HOLD:
		height = _height
	else:
		height = _height
		alpha = clampf(1.0 - (local - ERUPT_RISE - PILLAR_HOLD) / CRUMBLE_TIME, 0.0, 1.0)
	if height <= 1.0:
		return
	_draw_column(height, alpha)
	# Dust skirt at base.
	draw_circle(_ground, _half_width * 1.8, Color(0.55, 0.42, 0.28, 0.35 * alpha), true, -1.0, true)


## The tell, drawn at EXACTLY the footprint that will hurt you. It used to be a
## ring swelling to 0.9 * 66 px — a promise of a 59 px danger circle in front of
## a 23 px fang, which taught the player the wrong shape twice over. Now it is
## the fang's own column: two rising ground marks at the capsule's edges plus a
## filling floor bar between them, so what lights up is what erupts.
func _draw_telegraph() -> void:
	var tp: float = _elapsed / CHARGE_TIME
	var a: float = 0.55 * tp
	var c := Color(_color.r, _color.g, _color.b, a)
	var l := Vector2(_ground.x - _half_width, _ground.y)
	var r := Vector2(_ground.x + _half_width, _ground.y)
	draw_line(l, r, c, 3.0, true)
	# Edge ticks growing upward: the column you must not be standing in.
	var tick: float = _height * 0.18 * tp
	draw_line(l, l + Vector2.UP * tick, c, 2.0, true)
	draw_line(r, r + Vector2.UP * tick, c, 2.0, true)
	# A low ground glow filling toward the moment of eruption.
	draw_circle(_ground, _half_width * tp, Color(_color.r, _color.g, _color.b, 0.22 * tp),
		true, -1.0, true)


## ONE sharp tapering fang (not stacked blocks — that silhouette now belongs to
## Colossus Pillar). Kinked edges keep it reading as fractured stone; the lit
## left face gives it volume and the HDR tip glint sells "sharp".
func _draw_column(height: float, alpha: float) -> void:
	var hw: float = _half_width
	var x: float = _ground.x
	var base_l := Vector2(x - hw, _ground.y)
	var base_r := Vector2(x + hw, _ground.y)
	var apex := Vector2(x + _jitter[0] * 10.0, _ground.y - height)
	# Jagged silhouette: base → left kink → apex → right kink → base.
	var kink_l := Vector2(x - hw * 0.42 + _jitter[1] * 7.0, _ground.y - height * 0.52)
	var kink_r := Vector2(x + hw * 0.5 + _jitter[2] * 7.0, _ground.y - height * 0.44)
	draw_colored_polygon(PackedVector2Array([base_l, kink_l, apex, kink_r, base_r]),
		Color(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b, alpha))
	# Lit left face (sun side) + central fracture seam down from the apex.
	draw_line(base_l, kink_l, Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, 0.8 * alpha), 2.2, true)
	draw_line(kink_l, apex, Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, alpha), 2.6, true)
	draw_line(apex, Vector2(x + _jitter[3] * 5.0, _ground.y),
		Color(SEAM_COLOR.r, SEAM_COLOR.g, SEAM_COLOR.b, 0.85 * alpha), 2.0, true)
	# HDR glint running down from the tip — the "sharp" read (blooms).
	draw_line(apex, apex.lerp(kink_r, 0.35),
		Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, alpha), 1.6, true)
	draw_circle(apex, 2.6, Color(1.6, 1.3, 0.8, alpha), true, -1.0, true)
	# Dark seam where the fang split the ground.
	draw_line(base_l, base_r, Color(SEAM_COLOR.r, SEAM_COLOR.g, SEAM_COLOR.b, alpha), 2.0, true)
