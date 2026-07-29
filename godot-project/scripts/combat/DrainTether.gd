class_name DrainTether
extends Node2D
## Warlock — LIFE-DRAIN TETHER (SpellDef.Kind.TETHER). A barbed whip is COILED at
## the caster's hand, then LASHED down the aim as a real travelling hook. What it
## catches gets bitten and DRAINED over a short channel — the victim bleeds shadow
## while the caster is healed — and the victim can TEAR FREE by dragging the barb
## BREAK_PULL px from where it went in. Draws in world coordinates.
##
## WHY THIS WAS REWRITTEN (maker, mid-playtest: "that stringy attack — is it
## dodgeable? I don't like it"). It was not. The old version resolved a corridor
## query and applied its first drain tick on the SAME FRAME it was cast: no
## windup, no travel, no telegraph. Its own docs claimed counterplay ("latches
## only onto a target inside a narrow corridor", "the victim SNAPS the tether by
## opening more than BREAK_RANGE") but a corridor is aim skill for the ATTACKER,
## not counterplay for the DEFENDER, and BREAK_RANGE (520) sat only ~80 px past
## the latch range (440) measured from the CASTER, so how far you had to run to
## escape depended on how close you were when it hit — unreadable, and impossible
## at point-blank. That violated the locked rule that every ability is dodgeable
## with a real telegraph and a window to move.
##
## THE FOUR COUNTERPLAY LAYERS NOW, IN THE ORDER A DEFENDER MEETS THEM:
##   1. COIL   — WINDUP seconds of visible wind-up with a dashed aim guide down
##               the whole reach. This is the guaranteed dodge budget floor: even
##               a point-blank cast gives it.
##   2. LASH   — the hook TRAVELS at LASH_SPEED, so anything further away gets
##               proportionally more time (see `dodge_window`). Because it is a
##               real moving position it also joins the deflect layer — group
##               "deflectable_spell" + deflect_point() + reflect() — and can be
##               parried straight back at the warlock.
##   3. COVER  — and the cheapest of the four: put a WALL between you and the
##               caster and the whip cracks on it and never arrives. Destructible
##               cover does not save you (the lash shreds through it) but it is
##               not wasted either — it takes the bite on the way past.
##   4. TEAR   — once bitten you are not sentenced. Drag the barb BREAK_PULL px
##               from the bite point and it rips out. The break ring is DRAWN
##               around the bite, and the cable visibly strains toward it, so the
##               escape is something you can see yourself winning.
##
## NO AUTO-AIM, NO HOMING (locked rule): the hook flies exactly where it was
## pointed and never bends. The catch test is a swept capsule of radius CATCH_R
## along the segment the head travelled this frame — which is EXACTLY the hook
## disc plus the motion streak that `_draw_hook` puts on screen, so the damage
## can never reach outside the drawn shape. Sweeping (rather than testing the
## head point alone) is anti-tunnelling: one long frame steps further than the
## catch radius and a point test would drop a body sitting in the middle of it.
##
## Whether a given body is inside that capsule is SpellTargets' call, so the whip
## catches the DRAWN SILHOUETTE — spine plus head — rather than the node origin
## about ten pixels below the head a player actually aimed at. Cover is
## SpellWorld's call: the flight probe is `first_solid` over the segment just
## travelled, so the whip stops at walls and shreds destructibles on the way.
## Neither rule is re-implemented here; see docs/spell-world-contract.md.
##
## LOOK: the old thin writhing polyline is what "stringy" meant. This is built
## with the kit's established shadow language (ShadowCrawler / ShadowRoot) — a
## light-eating near-black core with a wide violet halo, a bright rim, and BARBS
## sprouting along its length, so it has mass and reads as a threat rather than a
## thread. HDR is reserved for the hook sparks and the drain motes so bloom
## accents the darkness instead of washing it out.
##
## DEFLECT PATH: it travels, so it takes the reflect() contract and NOT
## SpellDeflect.resolve() — see SpellDeflect's class docs on why a spell picks
## exactly one of the two. Routing damage through both would make a parry read as
## two different verbs on the same spell.
##
## Damage/heal are applied by calling the victim's own methods, which self-route
## in co-op (Enemy.take_damage forwards to the host, Hero.take_damage forwards to
## its owner), so there is no Net gating to do here.

# --- timing: this is the dodge budget ---------------------------------------
## The coil before the lash. THE DODGE-WINDOW FLOOR: the shortest warning any
## victim can ever get, since it is paid before the hook has moved a pixel. At
## the hero's 210 px/s that is ~55 px of free repositioning, and the catch radius
## is 22 px, so simply walking is enough at point-blank. UNTESTED GUESS — if it
## feels sluggish to cast, cut toward 0.20; if it still feels cheap to be hit by,
## push toward 0.32.
const WINDUP: float = 0.26
## px/s the hook travels. Deliberately between the Rift Dagger's readable 780 and
## a beam's instant: fast enough to crack, slow enough to watch come. UNTESTED.
const LASH_SPEED: float = 900.0
## Travel budget. Unchanged from the old RANGE so reach/balance did not silently
## move while the delivery was being fixed.
const RANGE: float = 440.0
## The drain channel once latched. UNTESTED GUESS.
const DRAIN_TIME: float = 1.2
## Drain cadence. DRAIN_TIME / TICK = 5 ticks if never broken.
const TICK: float = 0.24
## The torn / whiffed whip snapping home. Short — it is punctuation, not a beat.
const RECOIL_TIME: float = 0.22

# --- geometry: exactly what is drawn ----------------------------------------
## The hook's grasping radius. ONE constant for both the catch test and the drawn
## hook disc, because the maker's rule is that the spell must not be able to hurt
## anything outside its own silhouette — two numbers would drift apart.
const CATCH_R: float = 22.0
## Drag the barb this far from the bite point and it tears out. Measured from the
## BITE, not from the caster, so the demand is the same every time no matter what
## range you were caught at — that is what makes it readable. ~1.7 hero dashes
## (620 x 0.14 = 87 px each) or ~0.7 s of running at 210 px/s. UNTESTED GUESS.
const BREAK_PULL: float = 150.0
## Sanity leash on the cable: the caster running away also ends the drain, so
## holding the channel is a commitment rather than a free tax on the victim.
const LEASH: float = 640.0

# --- payload ----------------------------------------------------------------
## The bite is worth this many drain ticks. A travelling whip that connects
## should feel like a hit landing, not like a field switching on.
const BITE_MULT: float = 2.0
const HEAL_ON_BITE: int = 8
const HEAL_PER_TICK: int = 5
## px/s the cable reels a caught body toward the caster. Must stay far under
## every enemy walk speed (55-175 px/s) so it adds weight to the struggle without
## ever becoming a lock. Never applied to a hero — see `_reel`. UNTESTED GUESS.
const REEL_SPEED: float = 40.0

# --- look -------------------------------------------------------------------
const CABLE_SEGS: int = 16      # points along the cable polyline
const CABLE_WAVE: float = 13.0  # whip-wave amplitude at full slack
const BARBS: int = 7            # hooked spikes sprouting along the cable
const MOTES: int = 3            # life-motes flowing victim -> caster while draining
## How near the caster a hero must be for the fallback owner-guess to adopt them.
## See `_resolve_caster` — remove once SpellCaster passes the caster explicitly.
const CASTER_ADOPT_R: float = 140.0

enum State { COIL, LASH, DRAIN, RECOIL, DEAD }

var element_id: int = Elements.Element.SHADOW

var _origin: Vector2 = Vector2.ZERO   # where the cast happened (cable root fallback)
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(0.55, 0.2, 0.6, 1.0)
var _tick_dmg: int = 10
var _caster: Node = null              # healed by the drain; also anchors the cable

var _state: int = State.COIL
var _t: float = 0.0                   # seconds in the current state
var _elapsed: float = 0.0             # since the cast, for the writhe phases
var _head: Vector2 = Vector2.ZERO
var _prev: Vector2 = Vector2.ZERO     # head last frame — the swept catch capsule
var _travelled: float = 0.0
var _victim: Node2D = null
var _anchor: Vector2 = Vector2.ZERO   # the victim's position at the bite; the break is measured here
var _grip_offset: Vector2 = Vector2.ZERO  # barb contact point RELATIVE to the victim's body
var _tear_at: Vector2 = Vector2.ZERO  # where the cable let go, for the recoil draw
var _tick_t: float = 0.0
var _guide_reach: float = RANGE       # telegraph length, clipped at the first wall
var _seed: PackedFloat32Array = PackedFloat32Array()

## Read by the parry scans (Hero.try_parry / SpikeFigure._try_reflect) to skip a
## whip that is already flying back out.
var _reflected: bool = false
var _target_group: String = "enemy"


## Entry point, mirroring every other spectacle's single driver method.
##
## `caster` is optional ONLY because SpellCaster's TETHER arm does not pass it
## yet (that file is not mine to edit). When it is null the caster is guessed —
## see `_resolve_caster` — which is right in singleplayer and wrong in co-op.
func tether(
	origin: Vector2, aim: Vector2, color: Color, damage: int = 10,
	_effect: String = "shadow", caster: Node = null
) -> void:
	_origin = origin
	_color = color
	_tick_dmg = damage
	_dir = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	_caster = _resolve_caster(caster, origin)
	global_position = Vector2.ZERO  # parks at the arena origin; draws in world coords
	_state = State.COIL
	_t = 0.0
	# The telegraph must promise only what the whip can actually deliver. Clipped
	# at the first wall (SpellWorld contract, "a drawn length"), so the dashed
	# lance stops at the cover it will crack on instead of drawing through the
	# floor and out the bottom of the level — which is what it did before, and is
	# a promise of reach the spell cannot keep.
	var hand: Vector2 = _hand()
	_guide_reach = hand.distance_to(
		SpellWorld.clip(hand, hand + _dir * RANGE, 2.0, _skip_rids(), self))
	for i: int in 24:
		_seed.append(randf())
	# The coil beat AT the hand: dark motes dragged BACKWARD along the aim, so the
	# wind-up reads as the whip being pulled in before it is thrown out.
	CombatVfx.spawn_burst(get_parent(), _hand(),
		Color(0.16, 0.04, 0.24, 0.9), Color(0.05, 0.0, 0.1, 0.0),
		10, 0.3, 40.0, 120.0, 0.7, 1.7, 0.0, 0.0, false, -_dir, 45.0)
	Sfx.play("cast", -4.0, 0.08, 0.85)  # pitched DOWN — this is a wind-up, not a release
	queue_redraw()


# ---- pure selectors (headless-testable, no scene needed) --------------------
#
# NOTE these name SpellGeometry / SpellTargets and nothing else. A `--script`
# tool compiles this file BEFORE the autoloads register, so a static function
# here may never name Sfx / Juice / Tuning / Net — that is a compile error which
# takes the whole dependency chain down with it. The instance methods below are
# free to call them; only the statics are constrained.

## Is `target` inside the whip's swept catch capsule for one frame of travel?
## `radius` is the hook's grasping radius and is the SAME number the hook is
## drawn at, so the damage can never reach outside the silhouette.
##
## The body test is delegated to SpellTargets so the whip catches the DRAWN
## SILHOUETTE — spine segment plus head circle — instead of the node origin. That
## matters here more than almost anywhere: `Enemy`'s head centre sits ~10 px ABOVE
## its origin (~19 px on the SpellPlayground's 1.9x sparring dummies), so a whip
## lashed at somebody's head against an origin-only test passes straight through
## it. Targets with no silhouette (a plain Node2D, a crate, a headless stub) fall
## back to a point test on global_position with a zero margin, byte-identically to
## the old behaviour — no stealth hitbox inflation.
static func caught_by(from: Vector2, to: Vector2, radius: float, target: Object) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	# Measure the silhouette from the nearest point ON the sweep rather than from
	# either endpoint: the sweep is a capsule, and asking "how far is this body
	# from the whole segment" is the only test that does not tunnel.
	var probe: Vector2 = SpellGeometry.closest_point_on_segment(
		SpellTargets.aim_point(target), from, to)
	return SpellTargets.hits(target, probe, radius)


## The first node the hook crosses this frame — nearest along the sweep, so a
## whip through two stacked bodies bites the near one. Null when it caught air;
## the hook never bends to find a target.
##
## Deliberately NOT SpellTargets.on_line: that filters by line of sight from the
## origin, which here would be a second, WORSE answer to a question the whip has
## already answered better. The whip stops AT the wall it meets (see `_travel`),
## so by the time this runs there is nothing left in between to filter.
static func first_caught(from: Vector2, to: Vector2, radius: float, nodes: Array) -> Node2D:
	var seg: Vector2 = to - from
	var len2: float = seg.length_squared()
	var best: Node2D = null
	var nearest: float = INF
	for n: Node in nodes:
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if not caught_by(from, to, radius, n):
			continue
		# Progress along the sweep, 0 at `from`. A zero-length sweep (the launch
		# frame, before the head has moved) leaves every hit at 0 and the first
		# match wins, which is correct — they are all at the same place.
		var at: Vector2 = SpellTargets.aim_point(n)
		var along: float = 0.0 if len2 <= 0.0 else (at - from).dot(seg) / len2
		if along < nearest:
			nearest = along
			best = n as Node2D
	return best


## How close a caught body is to tearing the barb out: 0 at the bite point, 1.0
## at the break. Drives BOTH the break test and the strain visuals, so what the
## player sees straining is literally the number that frees them.
static func break_strain(anchor: Vector2, at: Vector2, break_pull: float) -> float:
	return clampf(anchor.distance_to(at) / maxf(break_pull, 1.0), 0.0, 1.0)


## Seconds a victim `distance` px from the caster has between the cast starting
## and the hook arriving. Exists as a function (rather than living only inside
## _process) so the dodge budget is an asserted, reviewable number in the test
## suite instead of a claim in a comment.
static func dodge_window(distance: float) -> float:
	return WINDUP + clampf(distance, 0.0, RANGE) / LASH_SPEED


# ---- deflect contract (the travelling half of the parry layer) --------------

## Where this spell physically IS, for the parry scans. The node parks at the
## arena origin, so global_position is emphatically not it.
func deflect_point() -> Vector2:
	return _head


## Parried mid-flight: the whip is turned around and lashes back with a fresh
## travel budget, hunting the side that threw it. The owner is CLEARED, so a
## reflected tether drains but heals nobody — the warlock does not get to keep
## sipping life off a whip somebody took away from them.
func reflect(new_dir: Vector2, color: Color) -> void:
	if _reflected or _state != State.LASH:
		return
	_reflected = true
	_dir = new_dir.normalized() if new_dir != Vector2.ZERO else -_dir
	_color = color
	_caster = null
	_target_group = "hero"
	_travelled = 0.0
	_prev = _head
	Sfx.play("ding", 0.0, 0.05)
	queue_redraw()


## AoE sweeps clear pending hazards through this (mirrors EnemyProjectile.consume).
func consume() -> void:
	queue_free()


# ---- lifecycle -------------------------------------------------------------

func _process(delta: float) -> void:
	_elapsed += delta
	_t += delta
	match _state:
		State.COIL:
			if _t >= WINDUP:
				_launch()
		State.LASH:
			_travel(delta)
		State.DRAIN:
			_channel(delta)
		State.RECOIL:
			if _t >= RECOIL_TIME:
				queue_free()
				return
	queue_redraw()


## The coil releases. Only from here on is the whip a thing in the world that can
## catch anybody — and only from here on is it something a parry can catch.
func _launch() -> void:
	_state = State.LASH
	_t = 0.0
	_head = _hand()
	_prev = _head
	_travelled = 0.0
	add_to_group("deflectable_spell")
	Sfx.play("whip_lash", -3.0, 0.06, 0.85)  # the whip crack, pitched down for weight


## One frame of flight. Order matters: move, then ask the world what is in the
## way, THEN look for a body — so a whip that would cross a wall and a body on
## the same frame stops at the wall, which is what "the wall was in the way" has
## to mean. Cover is the fourth counterplay layer and the cheapest one: break
## line of sight and the whip never arrives.
##
## The world probe is `SpellWorld.first_solid` over the segment JUST TRAVELLED
## (never a forward guess), which is the shared contract — see
## docs/spell-world-contract.md. It hands back everything destructible the lash
## tore through on the way; a barbed whip shreds a crate and keeps going, so those
## are damaged rather than treated as a stop.
##
## HAIRLINE, not `first_solid_thick`, even though the hook is CATCH_R*2 = 44 px
## wide. The hook flies at the caster's chest height, and a 44 px-thick probe
## reaches BELOW their feet — every flat cast would crack instantly on the floor
## it is travelling over. The width exists to catch tall bodies, not to bump into
## the ground.
func _travel(delta: float) -> void:
	_prev = _head
	var step: float = LASH_SPEED * delta
	_head += _dir * step
	_travelled += step
	var probe: Dictionary = SpellWorld.first_solid(_prev, _head, _skip_rids(), self)
	for torn: Node in (probe["smashed"] as Array[Node]):
		_shred(torn, probe["position"] as Vector2)
	if bool(probe["hit"]):
		_crack(probe["position"] as Vector2)
		return
	var caught: Node2D = first_caught(_prev, _head, CATCH_R,
		get_tree().get_nodes_in_group(_target_group))
	if caught != null:
		_bite(caught)
		return
	if _travelled >= RANGE:
		_crack(_head)  # out of reach — it cracks at empty air and snaps home


## The caster's own body, so a whip does not collide with the arm that threw it.
## Rule 3 of the SpellWorld contract, and the one that fails most obviously.
func _skip_rids() -> Array[RID]:
	return SpellWorld.rids([_caster] if _caster != null else [])


## Cover the lash tore through. "Destroy what it can" is the other half of the
## no-passing-through-geometry ask: a whip that phased through a crate without
## marking it would read as the crate not being there.
func _shred(torn: Node, at: Vector2) -> void:
	if torn == null or not is_instance_valid(torn):
		return
	var dmg: int = int(round(float(_tick_dmg) * BITE_MULT))
	if torn.has_method("damage_at"):
		torn.call("damage_at", dmg, at, _dir)
	elif torn.has_method("take_damage"):
		torn.call("take_damage", dmg)


## The catch. One solid bite, then the channel opens. The whip leaves the deflect
## group here: it is no longer a travelling thing, and a parry aimed at a cable
## already buried in someone would be catching nothing.
func _bite(n: Node2D) -> void:
	_state = State.DRAIN
	_t = 0.0
	_tick_t = TICK
	_victim = n
	# TWO points, and conflating them is a bug waiting to happen:
	#   _anchor      — the victim's own position at the bite. The break is measured
	#                  against the victim's position, so both sides of that
	#                  comparison must be the same kind of point, or the strain
	#                  starts non-zero and the escape distance silently changes.
	#   _grip_offset — where the barb actually went IN, relative to the body, so
	#                  the maw rides the wound (head, chest) rather than snapping
	#                  to the feet. The hook caught the silhouette, so the visual
	#                  has to land on the silhouette too.
	_anchor = n.global_position
	var contact: Vector2 = SpellGeometry.closest_point_on_segment(
		SpellTargets.aim_point(n), _prev, _head)
	_grip_offset = contact - n.global_position
	if is_in_group("deflectable_spell"):
		remove_from_group("deflectable_spell")
	_hurt(n, int(round(float(_tick_dmg) * BITE_MULT)))
	if n.has_method("apply_status"):
		n.call("apply_status", element_id)
	_heal(HEAL_ON_BITE)
	# Dark implosion first, HDR violet flecks on top — the light goes out at the
	# bite and only the sparks bloom (the kit's shadow recipe).
	CombatVfx.spawn_burst(get_parent(), contact,
		Color(0.12, 0.02, 0.2, 0.95), Color(0.03, 0.0, 0.07, 0.0),
		18, 0.45, 90.0, 240.0, 0.9, 2.0, 0.0, 0.0, false, -_dir, 60.0)
	CombatVfx.spawn_burst(get_parent(), contact,
		Elements.emissive(element_id), Color(_color.r, _color.g, _color.b, 0.0),
		9, 0.32, 110.0, 260.0, 0.4, 1.1, 0.0, 0.0, true)
	Juice.hit_stop(0.06)
	Juice.shake_camera(8.0)
	# The shadow family's shared mark — the negative (see ShadowRoot._erupt).
	# The bite is the moment the leash CATCHES; the frame lands on it and not on
	# the drain that follows, because a channel punctuated on a cadence would be
	# a strobe with extra steps.
	Juice.frame({
		"style": ImpactFrame.Style.INVERT, "strength": 0.9, "at": contact,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})
	Sfx.play("melee_hit", -1.0, 0.05, 0.8)
	Sfx.play("spell_impact", -4.0, 0.06, 0.75)


## The drain channel. Every exit from here is a DIFFERENT read for the player:
## torn free (the victim won), leash broken (the caster walked), victim gone, or
## the channel simply running out.
func _channel(delta: float) -> void:
	if _victim == null or not is_instance_valid(_victim):
		_state = State.DEAD
		queue_free()
		return
	var at: Vector2 = _victim.global_position
	if break_strain(_anchor, at, BREAK_PULL) >= 1.0:
		_tear(at)
		return
	if _hand().distance_to(at) > LEASH:
		_tear(at)
		return
	_reel(delta, at)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = TICK
		_drain_tick()
	if _t >= DRAIN_TIME:
		_release()


## A light drag toward the caster while the cable holds — the struggle should
## have weight. Heroes are exempt on purpose: a hero's controller owns its
## position, and yanking it would read as input loss, which is the one thing this
## rework must not reintroduce.
func _reel(delta: float, at: Vector2) -> void:
	if _victim.is_in_group("hero"):
		return
	var hand: Vector2 = _hand()
	# x only. Gravity owns y for every body in this game, and pulling on it would
	# either float the victim or fight its floor snap.
	_victim.global_position.x = move_toward(at.x, hand.x, REEL_SPEED * delta)


func _drain_tick() -> void:
	if _victim == null or not is_instance_valid(_victim):
		return
	_hurt(_victim, _tick_dmg)
	if _victim.has_method("apply_status"):
		_victim.call("apply_status", element_id)
	_heal(HEAL_PER_TICK)


## The victim dragged the barb out. Loud and legible: this is THEIR win, so it
## gets a real beat rather than the cable quietly vanishing.
func _tear(at: Vector2) -> void:
	_state = State.RECOIL
	_t = 0.0
	_tear_at = at
	_victim = null
	CombatVfx.spawn_burst(get_parent(), at,
		Color(0.4, 0.18, 0.7, 0.85), Color(0.1, 0.03, 0.2, 0.0),
		14, 0.3, 120.0, 300.0, 0.6, 1.6, 0.0, 0.0, false, -_dir, 70.0)
	Juice.shake_camera(4.0)
	Sfx.play("tether_tear", -4.0, 0.06, 1.4)  # a line under tension letting go


## The channel simply ran its course: the barb withdraws, no snap.
func _release() -> void:
	_state = State.RECOIL
	_t = 0.0
	_tear_at = _grip_point()
	_victim = null
	Sfx.play("cast", -10.0, 0.2, 1.1)


## The whip landed on nothing that can be drained — it ran out of reach, or it
## met a wall. (Destructible cover is NOT a stop; the lash shreds through it, see
## `_travel`.) It cracks where it ended and snaps home, so the player always SEES
## where their aim went instead of getting a silent nothing.
func _crack(at: Vector2) -> void:
	_state = State.RECOIL
	_t = 0.0
	_tear_at = at
	if is_in_group("deflectable_spell"):
		remove_from_group("deflectable_spell")
	CombatVfx.spawn_burst(get_parent(), at,
		Color(0.3, 0.12, 0.5, 0.7), Color(0.08, 0.02, 0.16, 0.0),
		10, 0.28, 60.0, 180.0, 0.5, 1.4, 0.0, 0.0, false, -_dir, 55.0)
	Juice.shake_camera(2.5)
	Sfx.play("whip_miss", -9.0, 0.1, 1.2)  # thin and empty — it bit air


# ---- helpers ---------------------------------------------------------------

## Damage a victim through its own method. Hero.take_damage takes one argument
## and Enemy.take_damage takes two (amount + elemental tint), so the arity is
## chosen by group — a reflected whip hunting heroes would otherwise error out
## mid-flight the moment it connected.
func _hurt(n: Node2D, amount: int) -> void:
	if not n.has_method("take_damage"):
		return
	if n.is_in_group("hero"):
		n.call("take_damage", amount)
	else:
		# Adapter: Hero takes take_damage(int), Enemy takes (int, Color). The 2-arg
		# form on a hero THROWS and aborts the enclosing function, losing the hit and
		# everything after it. Latent until factions let these point at a hero.
		SpellTargets.hurt(n, amount, Color(_color.r, _color.g, _color.b, 1.0))


func _heal(amount: int) -> void:
	if _caster == null or not is_instance_valid(_caster) or not _caster.has_method("heal"):
		return
	_caster.call("heal", amount)


## Who this whip feeds. The old code healed every node in group "player", which
## fed NOBODY in the tower — the combat hero joins group "hero"; "player" is the
## v0.0 overworld scene — and in co-op would have healed the whole party off one
## warlock's tether.
##
## The fallback only adopts a hero standing within CASTER_ADOPT_R of the cast
## origin, so a distant teammate is never mistaken for the caster. It should be
## deleted the moment SpellCaster's TETHER arm passes `caster` through.
func _resolve_caster(explicit: Node, origin: Vector2) -> Node:
	if explicit != null and is_instance_valid(explicit):
		return explicit
	var best: Node = null
	var nearest: float = CASTER_ADOPT_R
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if not (h is Node2D) or not is_instance_valid(h):
			continue
		var d: float = origin.distance_to((h as Node2D).global_position)
		if d < nearest:
			nearest = d
			best = h
	return best


## The cable root: the caster's hand, tracked live so the tether stays attached
## while they move. Falls back to the cast origin when there is no caster node
## (headless, or a reflected whip whose owner was severed).
func _hand() -> Vector2:
	if _caster != null and is_instance_valid(_caster) and _caster is Node2D:
		return (_caster as Node2D).global_position + Vector2(0.0, -6.0) + _dir * 10.0
	return _origin + Vector2(0.0, -6.0) + _dir * 10.0


## Where the barb is buried, tracked live so it rides the body it is stuck in.
func _grip_point() -> Vector2:
	if _victim == null or not is_instance_valid(_victim):
		return _head
	return _victim.global_position + _grip_offset


## Current strain, or 0 when nothing is caught. One accessor so the break test
## and every strain visual read the same value on the same frame.
func _strain() -> float:
	if _victim == null or not is_instance_valid(_victim):
		return 0.0
	return break_strain(_anchor, _victim.global_position, BREAK_PULL)


# ---- draw ------------------------------------------------------------------

func _draw() -> void:
	match _state:
		State.COIL:
			_draw_aim_guide()
			_draw_coil()
		State.LASH:
			_draw_cable(_hand(), _head, 1.0, 0.35)
			_draw_hook(_head, 1.0)
		State.DRAIN:
			if _victim == null or not is_instance_valid(_victim):
				return
			# The cable ends at the WOUND, not at the victim's origin — the hook
			# caught a silhouette, so the barb has to be drawn where it bit.
			var at: Vector2 = _grip_point()
			var strain: float = _strain()
			_draw_break_ring(strain)
			# The cable STRAIGHTENS as it strains — slack is the visual currency
			# of "you are not getting out", so spending it is how the victim is
			# told they are winning.
			_draw_cable(_hand(), at, 1.0, 0.45 + 0.55 * strain, strain)
			_draw_maw(at, strain)
			_draw_drain_motes(at, _hand())
		State.RECOIL:
			var k: float = clampf(1.0 - _t / RECOIL_TIME, 0.0, 1.0)
			# The torn cable whips back toward the hand, shrinking as it goes.
			_draw_cable(_hand(), _hand().lerp(_tear_at, k), k, 0.2)


## The telegraph. A dashed lance down the FULL reach plus a closing bracket at
## its end: the victim is told both the direction and that something is about to
## be thrown along it, and has WINDUP seconds to not be there.
func _draw_aim_guide() -> void:
	var p: float = clampf(_t / WINDUP, 0.0, 1.0)
	var a: Vector2 = _hand()
	var b: Vector2 = a + _dir * _guide_reach
	draw_dashed_line(a, b, Color(_color.r, _color.g, _color.b, 0.18 + 0.42 * p), 2.6, 9.0, true, true)
	# Brackets sliding IN along the lance — converging tells read as "incoming",
	# where expanding ones read as "already happened".
	var perp: Vector2 = _dir.orthogonal()
	for i: int in 3:
		var u: float = 0.45 + 0.25 * float(i) - 0.18 * p
		var c: Vector2 = a.lerp(b, clampf(u, 0.0, 1.0))
		var w: float = CATCH_R * (2.0 - p)
		draw_line(c + perp * w, c + perp * (w * 0.45),
			Color(0.62, 0.34, 1.0, 0.35 * p), 1.8, true)
		draw_line(c - perp * w, c - perp * (w * 0.45),
			Color(0.62, 0.34, 1.0, 0.35 * p), 1.8, true)


## The whip gathering at the hand: a tightening loop of cable, growing dark and
## heavy, that visibly has somewhere to go.
func _draw_coil() -> void:
	var p: float = clampf(_t / WINDUP, 0.0, 1.0)
	var c: Vector2 = _hand() - _dir * (6.0 + 10.0 * p)
	var perp: Vector2 = _dir.orthogonal()
	for loop: int in 3:
		var r: float = (16.0 - 3.5 * float(loop)) * (1.15 - 0.35 * p)
		var pts := PackedVector2Array()
		for i: int in 15:
			var u: float = float(i) / 14.0
			var ang: float = u * TAU + _elapsed * 5.0 + float(loop) * 1.1
			# Squashed against the aim axis so the loop reads as a coil seen
			# edge-on rather than three flat rings stacked on the hand.
			pts.append(c + _dir * (cos(ang) * r * 0.45) + perp * (sin(ang) * r))
		draw_polyline(pts, Color(0.4, 0.18, 0.7, 0.20 * p), 7.0, true)
		draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.85 * p), 4.0, true)
		draw_polyline(pts, Color(0.62, 0.34, 1.0, 0.5 * p), 1.4, true)
	var em: Color = Elements.emissive(element_id)
	for i: int in 4:
		var off := Vector2(sin(_elapsed * 19.0 + float(i) * 1.9) * 9.0,
			-4.0 - 8.0 * _seed[(i + 12) % 24])
		draw_circle(c + off, 1.6 * p, Color(em.r, em.g, em.b, 0.8 * p), true, -1.0, true)


## The cable itself. Three passes in the kit's shadow language — a wide violet
## halo (the only thing that defines a light-eating shape against a dark arena),
## a near-black core, a bright rim — plus BARBS sprouting along it. The barbs are
## the fix for "stringy": a bare polyline of any thickness still reads as a
## thread, where a barbed one reads as something you do not want wrapped round
## you. `taut` 0..1 flattens the whip wave; `strain` heats the rim toward the
## break so the victim can see the cable losing.
func _draw_cable(a: Vector2, b: Vector2, k: float, taut: float, strain: float = 0.0) -> void:
	if a.distance_to(b) < 2.0:
		return
	var perp: Vector2 = (b - a).orthogonal().normalized()
	var slack: float = CABLE_WAVE * (1.0 - clampf(taut, 0.0, 1.0))
	var pts := PackedVector2Array()
	for i: int in CABLE_SEGS + 1:
		var u: float = float(i) / float(CABLE_SEGS)
		var wob: float = sin(u * 7.0 + _elapsed * 14.0) * slack * sin(u * PI)
		pts.append(a.lerp(b, u) + perp * wob)
	var hot: Color = Color(1.0, 0.45, 0.55)  # strain colour — a line about to go
	var rim: Color = Color(0.62, 0.34, 1.0).lerp(hot, strain)
	draw_polyline(pts, Color(0.4, 0.18, 0.7, 0.20 * k), 11.0 - 3.0 * strain, true)
	draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.95 * k), 6.5 - 2.0 * strain, true)
	draw_polyline(pts, Color(rim.r, rim.g, rim.b, (0.65 + 0.3 * strain) * k), 2.0, true)
	# Barbs. Alternating sides, angled BACK toward the caster like a fish-hook, so
	# the silhouette explains why pulling away has to tear.
	for i: int in BARBS:
		var u: float = (float(i) + 0.6) / float(BARBS)
		var idx: int = clampi(int(u * float(CABLE_SEGS)), 0, CABLE_SEGS)
		var base: Vector2 = pts[idx]
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var s: float = _seed[i % 24]
		var back: Vector2 = (a - b).normalized()
		var len_px: float = (6.0 + 5.0 * s) * k * (0.7 + 0.3 * sin(_elapsed * 9.0 + s * TAU))
		var tip: Vector2 = base + (perp * side * 0.85 + back * 0.55).normalized() * len_px
		draw_line(base, tip, Color(0.04, 0.0, 0.09, 0.9 * k), 2.6, true)
		draw_line(base, tip, Color(rim.r, rim.g, rim.b, 0.5 * k), 1.1, true)


## The hook. The dark disc is drawn at EXACTLY CATCH_R — the radius the catch
## test uses — and the motion streak covers exactly the segment that was swept,
## so everything the whip can hurt is inside what you can see. Three curved fangs
## give it a bite direction; HDR sparks are the only bloomed part.
func _draw_hook(at: Vector2, k: float) -> void:
	# Motion streak over the swept capsule: this is the hit shape, made visible.
	if _prev.distance_to(at) > 1.0:
		draw_line(_prev, at, Color(0.4, 0.18, 0.7, 0.22 * k), CATCH_R * 2.0, true)
		draw_line(_prev, at, Color(0.05, 0.01, 0.1, 0.5 * k), CATCH_R * 0.9, true)
	draw_circle(at, CATCH_R, Color(0.4, 0.18, 0.7, 0.22 * k), true, -1.0, true)
	draw_circle(at, CATCH_R * 0.62, Color(0.03, 0.0, 0.07, 0.96 * k), true, -1.0, true)
	draw_arc(at, CATCH_R, 0.0, TAU, 26, Color(0.7, 0.4, 1.05, 0.8 * k), 2.0, true)
	var perp: Vector2 = _dir.orthogonal()
	for i: int in 3:
		var side: float = float(i) - 1.0                       # -1, 0, 1
		var root: Vector2 = at + perp * side * CATCH_R * 0.55 - _dir * 4.0
		var tip: Vector2 = at + _dir * (CATCH_R * 0.95) + perp * side * CATCH_R * 0.9
		var mid: Vector2 = at + _dir * (CATCH_R * 0.7) + perp * side * CATCH_R * 0.35
		var pts := PackedVector2Array()
		for j: int in 7:
			var u: float = float(j) / 6.0
			pts.append(root.lerp(mid, u).lerp(mid.lerp(tip, u), u))  # quadratic bezier
		draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.95 * k), 3.6, true)
		draw_polyline(pts, Color(0.62, 0.34, 1.0, 0.6 * k), 1.3, true)
	var em: Color = Elements.emissive(element_id)
	for i: int in 5:
		var off := Vector2(sin(_elapsed * 24.0 + float(i) * 2.1) * 9.0,
			-3.0 - 7.0 * _seed[(i + 17) % 24])
		draw_circle(at + off, 1.6 * k, Color(em.r, em.g, em.b, 0.85 * k), true, -1.0, true)


## The escape, drawn. A dashed ring at BREAK_PULL around the bite point, brighter
## and hotter the closer the victim gets to it. Without this the break condition
## is folklore; with it, running is a thing you can see yourself completing.
func _draw_break_ring(strain: float) -> void:
	var hot: Color = Color(1.0, 0.45, 0.55)
	var col: Color = Color(0.55, 0.28, 0.9).lerp(hot, strain)
	var alpha: float = 0.18 + 0.55 * strain
	var arcs: int = 18
	for i: int in arcs:
		var a0: float = TAU * float(i) / float(arcs) + _elapsed * 0.6
		var a1: float = a0 + TAU / float(arcs) * 0.55
		draw_arc(_anchor, BREAK_PULL, a0, a1, 4, Color(col.r, col.g, col.b, alpha), 1.8, true)
	# A pip on the ring at the victim's bearing, sliding out as they run: the
	# progress bar for the escape.
	if _victim != null and is_instance_valid(_victim):
		var brg: Vector2 = (_victim.global_position - _anchor)
		if brg.length_squared() > 1.0:
			var p: Vector2 = _anchor + brg.normalized() * BREAK_PULL
			draw_circle(p, 3.0 + 2.5 * strain, Color(col.r, col.g, col.b, 0.35 + 0.6 * strain), true, -1.0, true)


## What the barb looks like buried in someone: a light-eating pool over the body
## with fangs wrapping in and a pulse that keeps time with the drain ticks, so
## the channel reads as ongoing rather than as a decal.
func _draw_maw(at: Vector2, strain: float) -> void:
	var pulse: float = 0.85 + 0.15 * sin((TICK - _tick_t) / maxf(TICK, 0.001) * PI)
	draw_circle(at, 26.0 * pulse, Color(0.02, 0.0, 0.05, 0.42), true, -1.0, true)
	draw_arc(at, 26.0 * pulse, 0.0, TAU, 26, Color(0.5, 0.25, 0.85, 0.35), 1.6, true)
	var toward: Vector2 = (_hand() - at)
	toward = toward.normalized() if toward.length_squared() > 1.0 else _dir
	var perp: Vector2 = toward.orthogonal()
	for i: int in 4:
		var side: float = (float(i) / 3.0 - 0.5) * 2.0
		var s: float = _seed[(i + 8) % 24]
		var tip: Vector2 = at + perp * side * 20.0 - toward * (12.0 + 8.0 * s)
		var mid: Vector2 = at + perp * side * 14.0 - toward * 4.0
		var pts := PackedVector2Array()
		for j: int in 6:
			var u: float = float(j) / 5.0
			pts.append(at.lerp(mid, u).lerp(mid.lerp(tip, u), u))
		draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.9), 3.0, true)
		draw_polyline(pts, Color(0.55, 0.28, 0.9, 0.45), 1.2, true)
	# The barb itself, glowing hotter as it strains against the flesh.
	var em: Color = Elements.emissive(element_id)
	draw_circle(at, 4.0 + 2.0 * strain, Color(em.r, em.g, em.b, 0.75 + 0.25 * strain), true, -1.0, true)


## The drain made literal: bright motes travelling victim -> caster along the
## cable, GROWING as they arrive. Without a visible flow the channel is just a
## number going down somewhere off-screen.
func _draw_drain_motes(from: Vector2, to: Vector2) -> void:
	var em: Color = Elements.emissive(element_id)
	for i: int in MOTES:
		var phase: float = fposmod(_elapsed * 1.9 + float(i) / float(MOTES), 1.0)
		var p: Vector2 = from.lerp(to, phase)
		# Ride the cable's wave so the motes travel ALONG the whip rather than
		# through the air beside it.
		var perp: Vector2 = (to - from).orthogonal().normalized()
		p += perp * sin(phase * 7.0 + _elapsed * 14.0) * 6.0 * sin(phase * PI)
		var grow: float = 1.6 + 2.6 * phase
		draw_circle(p, grow + 2.0, Color(_color.r, _color.g, _color.b, 0.30), true, -1.0, true)
		draw_circle(p, grow, Color(em.r, em.g, em.b, 0.9), true, -1.0, true)
