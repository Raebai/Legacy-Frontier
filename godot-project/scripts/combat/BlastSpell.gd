class_name BlastSpell
extends Node2D
## The GIANT blast: telegraph blooms over a windup, then a huge AoE detonation.
## Damage is a pure radius query on the `target_group` group — no Area2D needed.
## Spectacle: big particle burst + expanding shockwave ring + heavy juice.
##
## ⚠ NOTE THE ONE PLACE THIS SPELL DIFFERS FROM ITS SIBLINGS. Most spectacles
## park at the arena origin and draw in world coordinates, so their
## `global_position` is a lie about where the effect is. THIS ONE DOES NOT:
## `detonate_at` / `detonate_now` MOVE the node to the blast centre and `_draw`
## works in local space around it. So `global_position` really is the blast
## centre here, and it is the correct thing to pass to SpellTargets / SpellWorld.
## Every other file in this family must not copy that.
##
## World contract (docs/spell-world-contract.md), all four parts:
##   SPAWN  — ground residue (scorch / debris / crater) is snapped to the FLOOR
##            beneath the blast and skipped entirely over a pit.
##   TRAVEL — nothing travels; a blast is instantaneous at its centre.
##   TARGETS— SpellTargets: silhouette-tested (a head at blast height registers)
##            and line-of-sight-gated, so the blast no longer reaches through a
##            wall it is merely standing next to.
##   DEFLECT— the detonation does not travel, so there is nothing to send back:
##            it routes damage through SpellDeflect.resolve and a well-timed
##            guard EATS it.
##
## ⚠ WHAT THE RADIUS AUDIT FOUND HERE. `radius` is configurable (the Brawler's
## fire punch uses 66, the enemy MAGE 70, the hero's giant blast 92, the
## Juggernaut's ground slam 98, the Boss's slam 100) and it is what DAMAGE used —
## but every DRAWN element was hard-wired to the `BLAST_RADIUS` const, 92. So the
## fire punch drew a blast 39 % wider than it could hurt, and the ground slam
## damaged 6 px outside its own picture. All drawing now reads `radius`. The
## shockwave ring also raced out to 1.35x the radius; it is now capped at the
## radius with a boundary arc held at exactly the radius, which is the treatment
## BlinkStrike already ships for the same reason.

const BLAST_RADIUS: float = 92.0
const WINDUP: float = 0.55
const DAMAGE: int = 40
const KNOCKBACK: float = 220.0   # was 340.0 — maker: spell knockback was way too much
const SHOCKWAVE_TIME: float = 0.25
const CLEANUP_DELAY: float = 0.7
# Every blast chars the floor beneath it: a scorch decal snapped down onto the
# ground (never a mid-air smear) that fades + clears after SCORCH_LIFETIME.
const SCORCH_RADIUS_FACTOR: float = 0.8  # decal size relative to the blast radius
const SCORCH_TINT: Color = Color(0.09, 0.05, 0.03, 0.6)  # warm charred brown
const SCORCH_LIFETIME: float = 7.0  # seconds before the crater fades away
const DEBRIS_COUNT: int = 22  # rock/ember chunks blown up out of the crater (bigger)
const DEBRIS_COLOR: Color = Color(0.36, 0.3, 0.26)  # charred stone
## How far down the floor probe reaches, as a multiple of the blast radius. Deep
## enough to find the ground from a blast placed at head height on a tall ledge,
## shallow enough that a blast over a pit reports "no floor". UNTESTED GUESS.
const FLOOR_PROBE_FACTOR: float = 2.2
## Crater gouge size relative to the blast radius. UNTESTED GUESS (carried over
## from the original hard-wired 0.95 * BLAST_RADIUS).
const CRATER_RADIUS_FACTOR: float = 0.95

var _shockwave_elapsed: float = -1.0  # < 0 means not yet detonated.
## Element index (Elements.Element) applied as an ailment to enemies in radius.
var element_id: int = -1
## Configurable so the SAME spell serves the hero's giant blast AND an enemy
## MAGE's AoE aimed at the hero. Defaults reproduce the hero blast exactly.
var target_group: String = "enemy"   # who the radius query hurts
var damage: int = DAMAGE
var radius: float = BLAST_RADIUS
var knockback: float = KNOCKBACK
var windup: float = WINDUP
## Co-op: a client-side VISUAL twin (Net._client_blast) — plays the full spectacle
## (burst/shockwave/scorch) but applies NO damage (the host's real blast owns that).
var visual_only: bool = false
## Who cast this. Excluded from the damage sweep and from the line-of-sight rays,
## and published to the reaction layer as the owner. Optional: no shipping caller
## sets it yet, and null is a legal "unowned" blast that behaves exactly as today.
var caster_node: Node = null
## Reaction weight — see SpellTier. The default middle shelf keeps an unset blast
## evenly matched with every other un-adopted spectacle.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## How much of a victim's parry window counts against this blast. WINDOW_NORMAL =
## the whole window (an ordinary spell). A caller that reconfigures this into an
## ult-weight AoE should pass SpellDeflect.WINDOW_ULT so only the opening sliver
## of a parry turns it. Nothing sets it today, so behaviour is unchanged.
var deflect_window: float = SpellDeflect.WINDOW_NORMAL


## Reconfigure before detonating (enemy MAGE aims it at group "hero", smaller
## radius, own element). Unspecified keys keep the hero-blast defaults.
func configure(opts: Dictionary) -> void:
	target_group = String(opts.get("target_group", target_group))
	damage = int(opts.get("damage", damage))
	radius = float(opts.get("radius", radius))
	knockback = float(opts.get("knockback", knockback))
	windup = float(opts.get("windup", windup))
	element_id = int(opts.get("element_id", element_id))
	visual_only = bool(opts.get("visual_only", visual_only))
	deflect_window = float(opts.get("deflect_window", deflect_window))


## Public entry: place the blast, start the danger bloom over the windup.
##
## THE WINDUP IS THE DODGE BUDGET. The Telegraph draws a danger ring at exactly
## `radius` — the same number that damages — and you have `windup` seconds to
## leave it. `detonate_now` skips this ONLY for callers that already ran their own
## tell (the enemy MAGE's Enemy-side telegraph) or that are a melee-range punch
## whose own animation is the tell.
func detonate_at(pos: Vector2) -> void:
	global_position = pos
	_join_reaction()
	var telegraph := Telegraph.new()
	add_child(telegraph)
	# ⚠ STAMPED, so `BotController.perceive_threats` can tell whose tell this is.
	# An unstamped hero telegraph is indistinguishable from an enemy one, which
	# makes a bot-driven caster dodge its own spell for the whole wind-up.
	telegraph.source = caster_node as Node2D
	# == RULE 1 OF THE TELL LAYER: COLOUR CARRIES ELEMENT ==
	# Without this the telegraph keeps `Telegraph.RING_COLOR` — the shared danger red —
	# whatever the blast is made of, so a fire punch and an ice slam warn in identical
	# red. That is the widest remaining hole in the audit, because the fire punch, the
	# ground slam, `MeteorFist` and the mage AoE all route through this one function.
	# The geometry was already 1:1 (ring r66 = hitbox r66 on the punch, r98 = r98 on the
	# slam), so this is purely the colour channel.
	#
	# ⚠ GUARDED, AND THE UNGUARDED FORM WOULD HAVE BEEN A REGRESSION. `element_id`
	# defaults to -1 on this class, and `Elements.color` FALLS BACK TO ARCANE MAGENTA
	# for any unrecognised value rather than to anything neutral — read it, it says so.
	# So a bare `telegraph.accent = Elements.color(element_id)` would repaint every
	# unelemented blast from danger red to magenta, i.e. it would announce "arcane" on a
	# spell that has no element at all. Checked rather than assumed: every live
	# construction site does stamp a real element (`Hero._element` defaults to ARCANE,
	# `Enemy._bolt_element`, `EliteVolatile` FIRE, `MeteorFist` passes its own) EXCEPT
	# `Net.gd:986`, which reads `int(data.get("el", -1))` off a replicated payload and
	# hands -1 through when the field is missing. That is the co-op divergence case
	# exactly: one peer's blast warning red and the other's magenta.
	#
	# `element_id >= 0 else <fallback>` is the same idiom this file already uses for its
	# burst colour further down; the fallback here is the ring colour so an unelemented
	# blast keeps precisely the tell it has today.
	if element_id >= 0:
		telegraph.accent = Elements.color(element_id)
	telegraph.fired.connect(_detonate)
	telegraph.start(radius, windup)


## Detonate immediately at `pos` (no windup) — used when the caller already ran
## its own telegraph (the enemy MAGE's Enemy-side tell) or for tests.
func detonate_now(pos: Vector2) -> void:
	global_position = pos
	_join_reaction()
	_detonate()


## Register with the reaction layer. A co-op VISUAL TWIN is deliberately kept
## out: the host's real blast is already registered, and a damage-free duplicate
## on the client would fire a second reaction for the same detonation.
func _join_reaction() -> void:
	if visual_only:
		return
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.IMPACT, element_id)


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) ------------------------------------

## Unlike its siblings this node really is AT the blast centre (see the class
## docs), so `global_position` is the honest answer here and only here.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(global_position, radius)


## LOAD-BEARING: false during the Telegraph windup — a danger ring is not a
## detonation and must not annihilate anything — and false once the shockwave has
## passed. True only while the blast is actually on screen doing something.
func reaction_active() -> bool:
	return _shockwave_elapsed >= 0.0 and _shockwave_elapsed < SHOCKWAVE_TIME


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.IMPACT


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: go without the trailing shockwave beat. NOTE the damage
## has already landed by the time a blast can be reacted to at all — an IMPACT is
## a done deal the instant it fires, which is exactly what distinguishes it from
## a BEAM or a BARRIER that persists.
func reaction_consume() -> void:
	queue_free()


# --- the detonation ----------------------------------------------------------

func _detonate() -> void:
	if not visual_only:  # the twin plays the spectacle only; the host owns the damage
		_apply_blast_damage()
	_spawn_blast_burst()
	# Crater mark + physics debris, snapped to the FLOOR below the blast (never a
	# mid-air smear) and given a lifetime so it clears up. Skipped over a pit —
	# `hit` is checked rather than trusting `position`, because SpellWorld returns
	# the caller's own point unchanged on a miss (see floor_below's ⚠).
	var ground: Dictionary = SpellWorld.floor_below(
		global_position, radius * FLOOR_PROBE_FACTOR,
		SpellWorld.rids([caster_node]), self)
	if bool(ground["hit"]):
		var floor_pos: Vector2 = ground["position"]
		ScorchDecal.spawn(
			get_parent(), floor_pos,
			radius * SCORCH_RADIUS_FACTOR, "scorch", SCORCH_TINT, SCORCH_LIFETIME
		)
		DebrisChunk.spawn_burst(
			get_parent(), floor_pos, DEBRIS_COLOR, DEBRIS_COUNT, Vector2.UP, 300.0
		)
		GroundCrater.spawn(get_parent(), floor_pos, radius * CRATER_RADIUS_FACTOR, false)
		# == SLICE 2: THE CRATER STOPS BEING A DECAL ==
		# `GroundCrater` above draws a mark; this takes the rock out. Deliberately at
		# `floor_pos` and not at `global_position`: a blast that goes off head-high must
		# bite the ground UNDER it, not carve a bubble in mid-air, and `floor_below`
		# already found exactly that point for the decal. Guarded by `ground["hit"]`
		# with everything else in this block, so a detonation over a pit removes nothing.
		#
		# ⚠ IT IS OUTSIDE `_apply_blast_damage`, WHICH THE COSMETIC TWIN SKIPS. Terrain
		# is the one thing a co-op twin must still change — same argument as the crate
		# in `_apply_blast_damage` and as the twin's bolt in `Spell._try_damage`: both
		# peers apply it, so both stages converge. Damage stays on the owner's peer.
		#
		# The blast's own `radius` is passed as a hint because the stage's damage->radius
		# curve is tuned for a projectile impact, and a 90 px detonation that leaves a
		# 30 px dent reads as a miss. `damage_at` can only ever WIDEN on a hint.
		DestructibleStage.carve_area(self, damage, floor_pos, Vector2.UP, radius)
	_shockwave_elapsed = 0.0
	queue_redraw()
	Juice.hit_stop(0.09)  # weighted: the AoE centerpiece, just under a kill
	Juice.shake_camera(12.0)
	Juice.zoom_punch_camera(0.1, 0.2)  # punch-zoom: the camera lunges in and eases back
	# ...then pull the frame back to reveal the whole detonation (the "show the big
	# spell" beat) — a gentle widen that holds through the shockwave and eases home.
	Juice.zoom_pull_camera(0.14, 0.35, 0.14, 0.5)
	PostProcess.shock(0.5)  # the AoE detonation ripples the screen (modest — Q fires often)
	# The punctuation beat, on the rung this blast's own SpellTier shelf puts it:
	# a heavy Q lands a white blow-out, an ult-weight one takes the screen in its
	# ELEMENT's colour, so a fire blast and an ice blast do not end identically.
	# Camera + freeze suppressed — the four lines above already fired them, tuned
	# for this spell; the frame here is the mark only.
	Juice.tier_frame(spell_tier, global_position, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	Sfx.play("blast")
	# Duck the music bed so the blast SFX owns the mix for a beat.
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("duck"):
		music.call("duck", 8.0, 0.4)
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


## Radius-query damage + outward knockback against `target_group`. Split out so
## headless tests can exercise the geometry without driving the Telegraph timing.
##
## Every sweep below uses `radius` — the same number the Telegraph ring, the
## shockwave, the flash core and the crater are drawn at.
func _apply_blast_damage() -> void:
	var skip: Array = [caster_node]
	for victim: Node in SpellTargets.in_radius(global_position, radius,
			get_tree().get_nodes_in_group(target_group), skip, self):
		var away: Vector2 = ((victim as Node2D).global_position - global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.RIGHT
		# Deflectable: a blast does not travel, so there is nothing to send back
		# and a correctly-timed guard EATS it (SpellDeflect's non-travelling path).
		var dealt: int = SpellDeflect.resolve(victim, damage, away,
			SpellTargets.aim_point(victim), deflect_window)
		if dealt > 0 and victim.has_method("take_damage"):
			victim.take_damage(dealt)
		if dealt <= 0:
			continue  # parried: the guard ate the ailment and the shove with it
		if element_id >= 0 and victim.has_method("apply_status"):
			victim.apply_status(element_id)
		if victim.has_method("apply_knockback"):
			victim.apply_knockback(away * knockback)
	# Crates in the blast radius shatter too (no knockback — they're static). An
	# enemy MAGE's blast can crack cover as well, so this isn't hero-gated.
	for prop: Node in SpellTargets.in_radius(global_position, radius,
			get_tree().get_nodes_in_group("destructible"), skip, self):
		# Blow parts off the BLAST-FACING side (localized chip): aim the hit at the
		# point on the prop nearest the blast centre, not its centre, so cover breaks
		# WHERE the blast touched it (maker: "parts break off where hit").
		if prop.has_method("damage_at"):
			var prop_pos: Vector2 = (prop as Node2D).global_position
			var toward: Vector2 = (global_position - prop_pos).normalized()
			var contact: Vector2 = prop_pos + toward * minf(global_position.distance_to(prop_pos), 30.0)
			var out: Vector2 = -toward
			prop.damage_at(damage, contact, out if out != Vector2.ZERO else Vector2.UP)
		elif prop.has_method("take_damage"):
			prop.take_damage(damage)
	# Only the HERO's blast clears enemy bolts from the air (spell-vs-spell); an
	# enemy blast must never eat its own team's projectiles.
	if target_group == "enemy":
		for proj: Node in SpellTargets.in_radius(global_position, radius,
				get_tree().get_nodes_in_group("enemy_projectile"), skip, self):
			if proj.has_method("consume"):
				proj.call("consume")


func _process(delta: float) -> void:
	if _shockwave_elapsed < 0.0:
		return
	_shockwave_elapsed += delta
	queue_redraw()


## Drawn in LOCAL space — this node sits AT the blast centre (see the class
## docs), which is why every point here is relative to Vector2.ZERO.
func _draw() -> void:
	if _shockwave_elapsed < 0.0:
		return
	var t: float = clampf(_shockwave_elapsed / SHOCKWAVE_TIME, 0.0, 1.0)
	if t >= 1.0:
		return
	var alpha: float = 1.0 - t
	# The boundary, held at EXACTLY the damage radius for the whole fade, so the
	# extent stays legible after the wave itself has swept past it.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(1.0, 0.85, 0.5, 0.3 * alpha), 2.0, true)
	# Expanding shockwave ring: races out TO the blast radius and fades. It used
	# to overshoot to 1.35x, drawing 33 px of danger that could never hurt anyone.
	var r: float = lerpf(8.0, radius, t)
	draw_arc(
		Vector2.ZERO, r, 0.0, TAU, 64,
		Color(1.0, 0.85, 0.5, 0.9 * alpha), lerpf(10.0, 2.0, t)
	, true)
	draw_arc(
		Vector2.ZERO, r * 0.78, 0.0, TAU, 48,
		Color(1.0, 0.5, 0.2, 0.5 * alpha), lerpf(6.0, 1.0, t)
	, true)
	# Hot flash core right after detonation — starts at exactly the damage radius
	# and collapses inward, so the very first frame states the true extent.
	if t < 0.4:
		var flash: float = 1.0 - t / 0.4
		# ⚠ CAPPED AT 0.52 OF THE RADIUS, and that is the third time this project has
		# fixed this exact shape: an HDR fill scaled by a whole effect radius reads as
		# a flat opaque disc once bloom has it, not as a flash. (The other two: the
		# sword hit's white sphere on `Enemy._flash`, and the burn status washing the
		# entire frame.) A full-radius fill covered the fighters standing either side
		# of the blast — measured on a delivered clip frame at 41% of the picture
		# above luma 200, with two of these overlapping.
		#
		# The two arcs above already state the true extent, which is the part that has
		# to be honest; this is the heat inside it, and heat does not need to reach the
		# edge to read. Alpha down with it, because a smaller disc at the same alpha is
		# still a disc.
		draw_circle(Vector2.ZERO, radius * flash * 0.52,
			Color(1.5, 1.3, 0.85, 0.26 * flash), true, -1.0, true)


## The shared burst builder, scaled way up for the centerpiece.
func _spawn_blast_burst() -> void:
	# Element-tinted energy shockwave (was a fixed orange burst for EVERY element).
	var ec: Color = Elements.color(element_id) if element_id >= 0 else Color(1.0, 0.9, 0.45)
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(ec.r, ec.g, ec.b, 1.0), Color(ec.r * 0.6, ec.g * 0.6, ec.b * 0.6, 0.0),
		90, 0.6, 160.0, 420.0, 2.0, 6.0, 60.0, 140.0, true
	)
	# The element's ORGANIC signature blooms on top (flame / shards / arcs / smoke /
	# sigil / stone / rays / wisps) — the "realistic + cool for ALL elements" pass.
	if element_id >= 0:
		ElementFx.spawn(get_parent(), global_position, element_id, 50.0)
