extends Area2D
## A straight-flying projectile — the basic cast every class throws. Hits the
## first thing in its path, then frees.
##
## ⚠ NOT AUTO-AIMED, DESPITE WHAT THIS DOC USED TO SAY. The bolt flies down the
## direction `launch()` was given and never seeks anything: `_dir` is written
## once and only ever changed by `reflect()`, i.e. by a player's parry. The class
## docstring claimed "auto-aimed" because the CALLER (Hero) used to pick a target
## for it; the projectile itself has no homing and must not grow any.
##
## World contract (docs/spell-world-contract.md):
##   TRAVEL — the segment JUST TRAVELLED is raycast every frame, so a bolt cannot
##            tunnel past a wall on a slow frame. That was already true; what is
##            new is the GHOST GUARD (see `_is_ghost`), which stops a bolt dying
##            on a crate that collapsed earlier in the same frame.
##   TARGETS— the chain hop goes through SpellTargets, so it tests the victim's
##            drawn silhouette (heads register) and will not arc through a wall.
##   DEFLECT— the bolt physically TRAVELS, so it takes the `reflect()` path: you
##            catch it and send it back, rather than merely eating it.
##   REACT  — registered as a PROJECTILE so it can clash with other live spells.
##
## ⚠ THE ONE PLACE THIS FILE MAY READ ITS OWN TRANSFORM. Almost every spectacle
## in this family parks at the arena origin and draws in world coordinates, so
## `global_position` is (0, 0) and lies about where the effect is. A bolt is a
## real moving body: the node IS the projectile, so `global_position` genuinely
## is where it is, and that is what the reaction shape and the deflect point use.

const SPEED: float = 460.0
## Fly until a wall/enemy stops it, or this far (well past any arena) — a bolt
## should never just STOP mid-air; the arena walls stop it first.
const MAX_TRAVEL: float = 2600.0

## The bolt's DRAWN extent, in px. It is both the collider's half-length
## (RectangleShape2D 12x6 in Spell.tscn) and roughly the drawn glow's half-width
## (SpellBoltVisual: CORE_HALF_WIDTH 2.4 * GLOW_SCALE 2.6 = 6.24), so the picture,
## the hitbox and the reaction shape all say the same thing. UNTESTED GUESS in the
## sense that it was never tuned — it is a measurement, not a feel number.
const BOLT_RADIUS: float = 6.0

## How many already-dying colliders one segment may step past before we give up
## and let the bolt stop. A pile of three collapsing crates is already absurd; the
## cap exists so a pathological frame cannot loop. UNTESTED GUESS.
const GHOST_PIERCE_STEPS: int = 4

# ── the muzzle beat (see `_muzzle_flash`) ────────────────────────────────────
## How far back along the travel axis the flash is staged, in px. Roughly one
## frame of travel at SPEED, so it lands on the hand rather than on the bolt.
## UNTESTED GUESS.
const MUZZLE_SETBACK: float = 8.0
## Particle counts. Deliberately small — this fires on EVERY basic cast, and the
## muzzle's job is a one-frame punctuation, not a firework. UNTESTED GUESSES.
const MUZZLE_SPARKS: int = 9
const MUZZLE_BACKSPRAY: int = 4
## Half-angle of the forward discharge cone, in degrees. Narrow, so the sparks
## read as following the shot out rather than as an explosion at the hand.
const MUZZLE_CONE_DEG: float = 26.0

# ── the impact beat (see `_spawn_impact_burst`) ──────────────────────────────
## The hit splits into a radial POP and a forward CONE of sparks continuing along
## the travel axis. One symmetric puff (what this used to be) reads as the bolt
## evaporating; a directional continuation reads as something being HIT, which is
## the Stick-Fight recipe the rest of the combat already uses. UNTESTED GUESSES.
const IMPACT_POP: int = 16
const IMPACT_SPRAY: int = 14
const IMPACT_CONE_DEG: float = 42.0

## A bolt cannot be caught during its first moments in the air. It spawns
## OVERLAPPING its own caster, so without this a caster who parries on the same
## frame they cast would catch their own bolt out of their own hand.
## UNTESTED GUESS: 0.06 s at 460 px/s puts the bolt ~28 px clear of the muzzle,
## which is past the body it was fired from.
const REFLECT_GRACE: float = 0.06

@export var damage: int = 18
## Per-class primary flavour (all default off = the plain Arcanist bolt):
## heal_on_hit lifesteals to `caster` (Cleric/Warlock); chain_count arcs the hit
## to nearby enemies (Stormcaller). caster is the Hero, for the lifesteal callback.
var heal_on_hit: int = 0
var caster: Node = null
var chain_count: int = 0
const CHAIN_RANGE: float = 200.0
const CHAIN_DAMAGE_FACTOR: float = 0.5
## How close cover has to be to a chain HOP to be caught in it. Small: the arc lands
## on a body, and this is the splash off that landing, not a second search radius.
const CHAIN_COVER_REACH: float = 30.0
## WHOSE SIDE THIS BOLT IS ON — the group it is allowed to damage.
##
## Damage routing in this file used to be group-HARDWIRED: the `enemy` branch was
## a literal, and the only way a bolt could ever hurt a hero was a live co-op
## session or a parry. That is why hero-vs-hero did literally nothing in single
## player, and it is the reason a bot-driven hero could not fight anything.
##
## The default is `&"enemy"`, so every existing caster is byte-identical — a
## spell only becomes hostile to something else when a caller deliberately opts
## in via `set_hostile_group()`. It is a GROUP and not a team id because that is
## how targeting already works everywhere else in the codebase: a faction is
## simply "the group my attacks scan", and two bots on the same side share a
## group that neither of them is hostile to.
var hostile_group: StringName = &"enemy"
## CO-OP COSMETIC TWIN. A bolt rebuilt on another peer to show you what your
## teammate just fired: it flies, trails, bursts and DIES on the same things the
## real one does, but hurts no fighter — the real bolt's damage is already resolving
## on its own peer through the victim-authority router, and a second live bolt would
## simply double it.
##
## ⚠ COVER IS THE DELIBERATE EXCEPTION. A twin still breaks crates. That is not an
## oversight, it is what stops the two phones' cover geometry from diverging: every
## peer now sees every hero attack, so every peer applies the same damage to its own
## copy of the crate and they converge. Excluding destructibles here would restore
## exactly the divergence this replication work exists to fix.
var visual_only: bool = false
var _dir: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0
var _age: float = 0.0
## Element tint (see Elements.gd). While unset, every visual keeps the
## original warm fire-bolt default — set_element_color() flips the flag.
var _element_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _has_element_color: bool = false
## Element index (Elements.Element) so a hit applies the matching ailment.
## -1 = no element (never applies a status).
var element_id: int = -1
## Reaction weight — see SpellTier. A basic cast is genuinely the QUICK shelf,
## but the default stays the middle shelf so an unset bolt remains evenly matched
## with every other un-adopted spectacle; the spawning caster sets it.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## Set the instant we consume ourselves, so the segment raycast and the Area2D
## callbacks can't both resolve the same bolt (double-damage / freed-node errors).
var _dead: bool = false
## Caught and turned by a parry. Named exactly this because the parry scans test
## `n.get("_reflected") == true` to avoid catching the same projectile twice —
## the same field name EnemyProjectile and RiftDagger publish.
var _reflected: bool = false
## Reaction registration is deferred to the first physics frame ON PURPOSE. The
## spawning caller does `add_child()` (which runs `_ready`) and only THEN sets
## `element_id`, so registering in `_ready` would always hand the reactor -1 —
## and `SpellReactor.register` correctly refuses an elementless effect, silently
## leaving every bolt out of the system.
var _registered: bool = false
## The MUZZLE beat, fired once on the first physics frame. See `_muzzle_flash`.
var _muzzled: bool = false


## Give the drawn bolt its element's SHAPE (not just its tint) and fire the
## muzzle. Deferred to the first physics frame for the same reason the reaction
## registration is: the spawning caller does `add_child()` (which runs `_ready`)
## and only THEN sets `element_id` / calls `set_element_color`, so doing either of
## these in `_ready` would hand them -1 and draw every bolt as plain arcane.
func _first_frame_dress() -> void:
	var visual: SpellBoltVisual = get_node_or_null("BoltVisual") as SpellBoltVisual
	if visual != null:
		visual.set_shape(Elements.effect_name(element_id) if element_id >= 0 else "")
	_muzzle_flash()


## THE MUZZLE. A projectile that simply EXISTS one frame and is 30 px further on
## the next has no moment of being fired — it is a thing that was always in the
## air. The maker's "the direct attack isn't cool" is partly about that missing
## beat: the cast animation ends, and then a bolt is just there.
##
## Staged in WORLD space under the arena (get_parent()), not under this node, for
## the usual reason every impact burst in this family is: it has to stay where the
## shot left from while the bolt travels away, and it has to outlive the bolt.
##
## Two emitters, both cheap and one-shot: a tight forward CONE (the discharge
## following the shot out) and a small back-spray (the recoil). Bolts are the
## highest-traffic event in the game, so this stops at two — the third emitter
## everyone wants to add is what turns a muzzle into a frame-rate problem.
func _muzzle_flash() -> void:
	var hot: Color = Color(1.6, 1.45, 1.1, 0.95)
	var fade: Color = Color(1.0, 0.6, 0.2, 0.0)
	if _has_element_color:
		hot = Color(_element_color.r * 1.5, _element_color.g * 1.5, _element_color.b * 1.5, 0.95)
		fade = Color(_element_color.r, _element_color.g, _element_color.b, 0.0)
	# Pulled BACK to the hand: the bolt has already moved a frame's worth by the
	# time this runs, and a flash centred on the bolt reads as the bolt glowing
	# rather than as the muzzle discharging.
	var at: Vector2 = global_position - _dir * MUZZLE_SETBACK
	CombatVfx.spawn_burst(
		get_parent(), at, hot, fade, MUZZLE_SPARKS, 0.16, 150.0, 340.0,
		0.7, 1.9, 4.0, 8.0, true, _dir, MUZZLE_CONE_DEG)
	CombatVfx.spawn_burst(
		get_parent(), at, hot, fade, MUZZLE_BACKSPRAY, 0.13, 60.0, 150.0,
		0.5, 1.3, 6.0, 10.0, true, -_dir, 60.0)


func launch(direction: Vector2) -> void:
	_dir = direction.normalized()
	rotation = _dir.angle()


## Where this bolt is going, in px/s. Published so a perceiving bot does not have
## to know that `launch()` writes `rotation = dir.angle()` and that SPEED is
## constant — it asks the bolt instead. Read-only; nothing here steers.
func travel_velocity() -> Vector2:
	return _dir * SPEED


## Point this bolt at a faction. Two jobs in one call because doing them
## separately is how the bug happens:
##   1. `hostile_group` — who `_try_damage` is allowed to hurt.
##   2. the COLLISION MASK. Heroes sit on layer 2, which a bolt only monitors in
##      a live co-op session. A hero-hostile bolt that never gets that bit simply
##      passes through its target, silently, with correct-looking damage code.
##
## Must be called AFTER `add_child()`, because `_ready()` (which sets the base
## mask) runs on add and the caller sets its properties afterwards — that
## ordering is why this is a method and not just a field write.
##
## Only a non-default group adds the bit, so single player with the default
## `&"enemy"` is untouched.
func set_hostile_group(group: StringName) -> void:
	hostile_group = group
	if group != &"enemy":
		collision_mask = collision_mask | 2


## Recolour the bolt toward an element: forwards to the drawn bolt visual
## and retints the particle trail. Impact burst picks it up via the flag.
func set_element_color(c: Color) -> void:
	_element_color = c
	_has_element_color = true
	var visual: SpellBoltVisual = get_node_or_null("BoltVisual") as SpellBoltVisual
	if visual != null:
		visual.set_tint(c)
	var trail: GPUParticles2D = get_node_or_null("Trail") as GPUParticles2D
	if trail != null and trail.process_material is ParticleProcessMaterial:
		# Duplicate the material so the tint is per-instance (the .tscn
		# sub-resource is shared across every live spell otherwise).
		var mat: ParticleProcessMaterial = (
			trail.process_material.duplicate() as ParticleProcessMaterial
		)
		var grad: Gradient = Gradient.new()
		grad.colors = PackedColorArray([
			Color(c.r, c.g, c.b, 0.85), Color(c.r, c.g, c.b, 0.0)
		])
		var ramp: GradientTexture1D = GradientTexture1D.new()
		ramp.gradient = grad
		mat.color_ramp = ramp
		trail.process_material = mat


func _ready() -> void:
	add_to_group("player_spell")  # projectile-vs-projectile clash (EnemyProjectile)
	# Deflect path #1 (the reflect() half): a thing that physically travels can be
	# CAUGHT and sent back, which is strictly the better fantasy and is what the
	# parry scans (Hero._try_parry / SpikeFigure._try_reflect) look for.
	add_to_group("deflectable_spell")
	body_entered.connect(_on_hit)
	area_entered.connect(_on_area_hit)
	collision_mask = collision_mask | 1  # also stop on platforms/walls (layer 1)
	var netmgr: Node = get_node_or_null("/root/Net")
	if netmgr != null and netmgr.is_active():
		collision_mask = collision_mask | 2  # co-op friendly fire: also hit heroes (layer 2)


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- deflect contract (the reflect() half — see SpellDeflect's class docs) ----

## Where the bolt physically is. It is a real moving body, so this is one of the
## few places in the spell family where the node's own transform is the truth.
func deflect_point() -> Vector2:
	return global_position


## Caught and sent back. Clearing `caster` is the half that makes it a
## counter-attack rather than a cancel: the bolt may now hit the person who threw
## it, and the "never damage your own caster" backstop no longer shields them.
##
## Deliberately silent — the parrier already plays the "ding"; a second one here
## would double it.
func reflect(new_dir: Vector2, color: Color) -> void:
	if _dead or _reflected or _age < REFLECT_GRACE:
		return
	_reflected = true
	_dir = new_dir.normalized() if new_dir != Vector2.ZERO else -_dir
	rotation = _dir.angle()
	_traveled = 0.0
	caster = null
	set_element_color(color)


# --- reaction contract (see SpellReactor) ------------------------------------

## Where this bolt was at the end of the previous physics frame, so the reaction
## shape can be the segment TRAVELLED rather than a 6 px dot. `Vector2.INF` means
## "no previous frame yet" — the bolt has existed for less than a tick.
var _prev_pos: Vector2 = Vector2.INF


## The bolt's swept extent since last frame (see the ⚠ in the class docs about why
## reading the transform is legitimate here and nowhere else).
##
## ⚠ IT IS SWEPT, NOT A POINT, AND THAT IS THE DIFFERENCE BETWEEN A FEATURE AND AN
## INTERMITTENT ONE. `SpellReactor` polls at 30 Hz. Two bolts closing head-on close
## 2 x 460 px/s = 30.7 px per reactor tick, against an overlap window of only 24 px
## for two 6 px circles — so the pair can be on either side of each other on
## consecutive polls and never once overlap.
##
## MEASURED (`tools/_probe_spell_clash.gd` case E), 200 sub-frame phase offsets:
##     60 Hz, point shapes   200/200 detected
##     30 Hz, point shapes   157/200 detected   <-- 1 crossing in 5 MISSED
##     30 Hz, swept capsule  200/200 detected
## An intermittent clash is worse than none: the player cannot learn a rule that
## only fires four times in five. This is the same anti-tunnelling reasoning
## `_resolve_segment` already applies to the physics query, applied to reactions.
func reaction_shape() -> Dictionary:
	if _prev_pos == Vector2.INF:
		return SpellGeometry.circle(global_position, BOLT_RADIUS)
	return SpellGeometry.capsule(_prev_pos, global_position, BOLT_RADIUS * 2.0)


## Which way this bolt is travelling. OPTIONAL on the participant contract — read by
## `SpellReactor` only for rows that ask for `require_head_on`, so an effect without
## a heading simply cannot match those rows (and no other rule notices).
func reaction_heading() -> Vector2:
	return _dir


## A bolt has no telegraph phase — it is dangerous the moment it exists — so the
## only inert state is "already consumed".
func reaction_active() -> bool:
	return not _dead


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.PROJECTILE


func reaction_owner() -> Node:
	return caster


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: gone WITHOUT its impact beat. `fizzle()` is the
## projectile-clash version and keeps the burst; this one does not, because the
## bolt did not land — it was eaten.
func reaction_consume() -> void:
	if _dead:
		return
	_dead = true
	queue_free()


## Consumed by a projectile clash (a stronger enemy bolt): burst + free.
func fizzle() -> void:
	if _dead:
		return
	_dead = true
	_spawn_impact_burst()
	queue_free()


## SWATTED OUT OF THE AIR BY A MELEE SWING. Maker: "brawler punching a spell, that
## sort of stuff."
##
## ⚠ THE WHOLE MECHANIC ALREADY EXISTED AND THIS FILE WAS THE ONE HOLE IN IT.
## `Hero._on_melee_hit_frame` has always swept the `player_spell` and
## `enemy_projectile` groups inside the melee cone, skipped anything you cast
## yourself, and called `consume()` on what it found. `EnemyProjectile`, `BoulderHurl`,
## `RiftDagger`, `ShadowCrawler`, `HorizonArc` and `DrainTether` all answer that call.
## The ordinary bolt — the single most-thrown thing in the game, and the obvious thing
## anyone would try to punch — was the only projectile that did not implement the
## method, so the sweep found it, tested `has_method("consume")`, and walked past.
##
## A fist could therefore smash a hurled boulder and phase clean through a bolt.
##
## Aliased to `fizzle()` rather than to `reaction_consume()` on purpose: a swatted bolt
## is a HIT, and it keeps its impact burst. `reaction_consume` is the "eaten, no beat"
## path, which is the wrong read for a punch that connected.
##
## Every class gets this, not just the Brawler — but it matters most there: it is the
## one class with no ranged answer at all, so being kited had no counter.
func consume() -> void:
	fizzle()


func _physics_process(delta: float) -> void:
	_age += delta
	if not _registered:
		_registered = true
		var reactor: Node = get_node_or_null(^"/root/SpellReactor")
		if reactor != null:
			reactor.call(&"register", self, ReactionTable.Form.PROJECTILE, element_id)
	if not _muzzled:
		_muzzled = true
		_first_frame_dress()
	var prev: Vector2 = global_position
	global_position += _dir * SPEED * delta
	_traveled += SPEED * delta
	# The segment just travelled, kept for `reaction_shape` so a 30 Hz reactor tick
	# cannot step two closing bolts straight past each other. Written BEFORE the
	# hit test below can return, so it is never a frame stale.
	_prev_pos = prev
	if _resolve_segment(prev):
		return  # hit a wall / cover / enemy along the path — no pass-through
	if _traveled >= MAX_TRAVEL:
		queue_free()


## Deterministic anti-pass-through: raycast the segment we just travelled against
## our own collision_mask (walls L1, enemies + destructible cover L3) and route
## whatever we hit through _try_damage — the same enemy / destructible / wall
## handling as the Area2D callbacks. A ray can't tunnel past a fast frame, and it
## catches solids reliably even when Area2D monitoring misses a dynamically-added
## StaticBody collider (the bug where bolts phased through cover). Headless helper
## tests have no physics world -> no-op, so they keep driving _try_damage directly.
##
## Routed through SpellWorld rather than a hand-rolled query for one reason worth
## the change: `smash_destructibles = false` is correct for a bolt (a bolt is not
## a boulder — LIVE cover stops it and breaks), but that alone would leave the
## bolt dying on GHOSTS. See `_is_ghost`.
func _resolve_segment(prev: Vector2) -> bool:
	if _dead:
		return true
	if not SpellWorld.has_world(self):
		return false
	# Excluded unconditionally whenever caster is set (not gated on heal_on_hit) —
	# a bolt spawns overlapping its own caster's body, so without this every
	# class's bolt (not just lifesteal ones) could immediately self-stop / self-hit.
	var skip: Array[RID] = SpellWorld.rids([caster])
	for _step: int in GHOST_PIERCE_STEPS:
		var r: Dictionary = SpellWorld.first_solid(
			prev, global_position, skip, self, false, collision_mask)
		if not bool(r["hit"]):
			return false
		var col: Object = r["collider"]
		if _is_ghost(col):
			skip.append(r["rid"] as RID)
			continue
		global_position = r["position"]
		_try_damage(col as Node)
		return _dead  # true if the hit consumed us; a no-op hit lets the bolt fly on
	return false


## Is this collider something that is not really THERE any more?
##
## THE TRAP, learned the hard way in RockWall._is_smashable and baked into
## SpellWorld: a cover block that has just collapsed leaves the "destructible"
## group IMMEDIATELY while its collider survives until the deferred free. A bolt
## that stops on it dies on nothing, one frame after breaking it.
##
## The bolt's policy differs from SpellWorld's default in one deliberate way:
## LIVE destructible cover is SOLID to a bolt (it stops and breaks it), because a
## bolt is a small projectile, not a boulder. So only the "already on its way out"
## half of the smash rule applies here.
static func _is_ghost(collider: Object) -> bool:
	if not SpellWorld.is_smashable(collider):
		return false  # ordinary solid geometry — it stops the bolt, as it should
	if collider == null or not is_instance_valid(collider):
		return true  # already freed; there is nothing left to stop against
	var n: Node = collider as Node
	return n != null and n.is_queued_for_deletion()


func _on_area_hit(area: Area2D) -> void:
	_try_damage(area.get_parent())


func _on_hit(body: Node) -> void:
	_try_damage(body)


func _try_damage(node: Node) -> void:
	if _dead or node == null:
		return
	# Defensive backstop: a bolt must never damage its own caster, regardless of
	# which group/branch below would otherwise match (Area2D overlap fires the
	# instant the bolt spawns on the caster's own body). This holds even if some
	# future call site forgets to set caster, or the group-specific guards below
	# are bypassed by a new node type. A REFLECTED bolt has had `caster` cleared,
	# which is precisely how catching one turns it back on its thrower.
	if node == caster:
		return
	# The cosmetic twin's whole contract, in one place: it STOPS where the real bolt
	# stopped (so the picture matches) and deals nothing. Cover falls through to the
	# real branches below — see `visual_only`'s docs for why that is on purpose.
	if visual_only and not node.is_in_group("destructible"):
		if node.is_in_group("hero") or node.is_in_group(SpellCaster.MORTAL_GROUP) \
				or node.is_in_group("enemy") or node is StaticBody2D:
			_dead = true
			_spawn_impact_burst()
			queue_free()
		return
	# ⚠ THE HERO TEST COMES FIRST, and the reorder is behaviour-preserving because
	# `hero` and `enemy` are disjoint groups: an enemy still falls straight through
	# to the faction branch below and takes the identical path it always did.
	# It has to be first because a hero victim is the one case with EXTRA rules
	# (co-op authority routing, the reflected-bolt exception) that the generic
	# faction branch must not bypass — and once `hostile_group` can be `&"hero"`,
	# a generic-first ordering would do exactly that.
	if node.is_in_group("hero") and node != caster and node.has_method("take_damage"):
		_damage_hero(node)
		return
	if node.is_in_group(hostile_group) and node.has_method("take_damage"):
		_dead = true
		node.take_damage(damage)
		if element_id >= 0 and node.has_method("apply_status"):
			node.apply_status(element_id)
		# Lifesteal (Cleric heal-bolt / Warlock drain-bolt): heal the caster.
		if heal_on_hit > 0 and is_instance_valid(caster) and caster.has_method("heal"):
			caster.call("heal", heal_on_hit)
		# Chain (Stormcaller chain-bolt): arc the hit to nearby stragglers.
		if chain_count > 0:
			_do_chain(node)
		# One dispatcher fires the camera/time/sound cluster in sync (study §4);
		# the burst + knockback (victim body reaction) fire alongside it.
		Juice.on_hit({"sfx": "spell_impact", "hitstop": 0.045, "shake": 6.0, "dir": _dir, "kick": 5.0})
		_punctuate()
		_spawn_impact_burst()
		if node.has_method("apply_knockback"):
			node.apply_knockback(_dir * 260.0)
		queue_free()
	elif node.is_in_group("destructible") and node.has_method("take_damage"):
		# Props take spell damage too. Prefer damage_at so parts break off exactly
		# where the bolt lands, along its travel direction (falls back to take_damage).
		_dead = true
		if node.has_method("damage_at"):
			node.damage_at(damage, global_position, _dir)
		else:
			node.take_damage(damage)
		Sfx.play("spell_impact")
		Juice.hit_stop(0.045)
		Juice.shake_camera(6.0)
		_spawn_impact_burst()
		DebrisChunk.spawn_burst(get_parent(), global_position, Color(0.4, 0.4, 0.45), 4, _dir, 200.0)
		queue_free()
	elif node is StaticBody2D:
		# A platform/wall stops the bolt — small explosion + stone chips fly off
		# the surface in the bolt's travel direction (the "spells hit the floor").
		_dead = true
		Sfx.play("spell_impact")
		Juice.hit_stop(0.03)
		Juice.shake_camera(3.0)
		_spawn_impact_burst()
		DebrisChunk.spawn_burst(get_parent(), global_position, Color(0.5, 0.5, 0.55), 5, _dir, 210.0)
		queue_free()


## A hero victim, split into the two questions that used to be tangled into one
## `elif` chain: MAY this bolt hurt this hero, and WHERE does the damage get
## applied. Conflating them is what made the faction seam necessary and also what
## would have made it wrong.
##
## PERMISSION — three ways a bolt may legitimately hurt a hero:
##   REFLECTED — someone parried it and sent it back. Its own clause because a
##       reflected bolt has had `caster` cleared and turns on its thrower
##       regardless of which faction it started out hostile to.
##   FACTION — the bolt was deliberately pointed at this hero's group. NEW: this
##       is what lets a bot-driven hero actually fight, and what makes "same team
##       cannot hurt each other" expressible.
##   FRIENDLY FIRE — an un-factioned bolt in a live session may hit any hero.
##       Gated on `hostile_group == &"enemy"` (i.e. nobody opted in) so this is
##       EXACTLY today's rule and nothing more.
##
## ⚠ THE FRIENDLY-FIRE CLAUSE IS LOAD-BEARING AND ITS CONDITION IS SUBTLE.
## `Net.is_active()` is documented as false in single player, but it reads TRUE
## whenever the SceneTree has its default `OfflineMultiplayerPeer` (whose
## connection status is CONNECTED) — so in practice this branch is live in single
## player too, and un-factioned hero-vs-hero bolts already damaged. Gating the
## clause on the DEFAULT group is what keeps that pre-existing behaviour byte-
## identical while still letting a bot's faction-pointed bolt be strict.
##
## ROUTING — a live session applies the damage on the victim's OWN authority
## (`Net.deal_damage`), never locally. That must not be bypassed just because a
## faction also permitted the hit, or a co-op bot would apply damage on the wrong
## peer, so permission is resolved first and routing second.
func _damage_hero(node: Node) -> void:
	var netmgr: Node = get_node_or_null("/root/Net")
	var session: bool = netmgr != null and netmgr.is_active()
	var allowed: bool = _reflected or node.is_in_group(hostile_group) \
		or (session and hostile_group == &"enemy")
	if not allowed:
		return
	# THE HERO-VS-HERO PARRY HOOK, AND IT HAD NEVER BEEN HERE.
	#
	# `EnemyProjectile._check_hit` has always offered the victim a parry before
	# resolving damage — but an ENEMY's shot is an `EnemyProjectile` and a HERO's
	# shot is a `Spell`, and `Spell` never asked. Every hero-only mode
	# (VersusArena / BotMatch / FreePlay) spawns nothing but heroes, so
	# `Hero.try_parry` — and with it the reflect, the reward beat and the deflect
	# counter — was unreachable in every duel the game ships.
	#
	# The symptom was one class deep: the Swordsaint could still turn a bolt,
	# because `_guard_deflect_sweep` scans the `deflectable_spell` group directly.
	# The other EIGHT classes press a parry window that negates the hit
	# (Hero.take_damage) but can never send it back. 1 of 9 could counter.
	#
	# `_reflected` guards a second press on an already-turned bolt, matching the
	# reasoning in RiftDagger. `Spell.reflect()` clears `caster`, and the
	# `_reflected` clause in the permission ladder above already lets a turned bolt
	# hit anyone including the original thrower — so the counter lands with no
	# group juggling.
	if not _reflected and node.has_method("try_parry") and node.try_parry(self):
		return
	if session:
		_dead = true
		netmgr.deal_damage(node, damage)
		netmgr.deal_knockback(node, _dir * 240.0)
		# ⚠ THE AILMENT USED TO BE DROPPED HERE, and only here. The branch below
		# applies it; this one did not, so in a live co-op session — the ONLY place
		# hero-on-hero bolts fly in the first place — burning, chilling and shocking
		# your teammate did literally nothing. Elemental friendly fire did not exist,
		# silently, because both branches otherwise looked complete.
		#
		# Routed rather than called directly for the same reason the damage above is:
		# `StatusComponent` ticks a damage-over-time through its owner's
		# `take_damage`, so applying it on a puppet would run the DoT on the wrong peer.
		if element_id >= 0:
			netmgr.deal_status(node, element_id)
		Juice.on_hit({"sfx": "spell_impact", "hitstop": 0.045, "shake": 6.0, "dir": _dir, "kick": 5.0})
		_spawn_impact_burst()
		queue_free()
	else:
		_dead = true
		node.take_damage(damage)
		if element_id >= 0 and node.has_method("apply_status"):
			node.apply_status(element_id)
		if node.has_method("apply_knockback"):
			node.apply_knockback(_dir * 240.0)
		Juice.on_hit({"sfx": "spell_impact", "hitstop": 0.045, "shake": 6.0, "dir": _dir, "kick": 5.0})
		_punctuate()
		_spawn_impact_burst()
		queue_free()


## The punctuation beat for a landing bolt — but ONLY for a bolt that earned one.
##
## A QUICK bolt deliberately gets NO frame here. Bolts are the highest-traffic
## damage event in the game: even the cheap localized ring on every one of them
## would turn the punctuation into a texture, and a beat that happens constantly
## stops being a beat. What a quick bolt already has is the hit-stop, the shake,
## the kick and the spark burst fired one line above this — a frame on top adds
## nothing except noise. The deserving small moments are covered elsewhere: the
## KILL gets one (Enemy._die), and a parry gets one (SpellDeflect).
##
## A HEAVY or ULT-weight bolt is a different animal — you spent a cooldown on it —
## and lands on its rung of the ladder, tinted by its own element so a fire bolt
## and a shadow bolt do not end on the same screen. The arbiter is the second
## line of defence if a burst of them ever lands together; this is the first.
func _punctuate() -> void:
	if spell_tier <= SpellTier.Tier.QUICK:
		return
	Juice.tier_frame(spell_tier, global_position, element_id)


## Chain the hit to the nearest OTHER enemies (Stormcaller). Each arc deals a
## fraction of damage + the element + a spark burst so the jump reads.
##
## The hop search is SpellTargets.nearest, which buys two fixes over the loop that
## used to live here: it measures to the victim's DRAWN SILHOUETTE (so a hop to a
## tall enemy whose head is nearer than a short one's stomach picks the right
## target, and a head at chain range registers at all), and it will not arc
## THROUGH A WALL — line of sight is on by default. Lightning that jumps through
## solid rock is the "spells get out of the radius" bug wearing a nicer hat.
func _do_chain(first: Node) -> void:
	var here: Vector2 = global_position
	# `already` doubles as the skip list: hopped targets and the caster are both
	# excluded from the search AND from the line-of-sight rays.
	var already: Array = [first, caster]
	var arc_dmg: int = int(round(float(damage) * CHAIN_DAMAGE_FACTOR))
	for _i: int in chain_count:
		# Hops within the bolt's OWN faction, not a hardcoded "enemy": a chain bolt
		# thrown by a hero-hostile caster must arc between heroes, or the flavour
		# silently evaporates the moment the thrower changes sides.
		var best: Node2D = SpellTargets.nearest(here, CHAIN_RANGE,
			get_tree().get_nodes_in_group(hostile_group), already, self)
		if best == null:
			break
		if best.has_method("take_damage"):
			best.take_damage(arc_dmg)
		if element_id >= 0 and best.has_method("apply_status"):
			best.apply_status(element_id, false)
		# Cover at the hop takes the arc too. The bolt's DIRECT hit already damaged
		# destructibles (`_try_damage`); only the chain arm was blind to them, so a
		# bolt that landed on a body and then jumped left the second crate standing.
		SpellSurfaces.in_radius(self, best.global_position, CHAIN_COVER_REACH, arc_dmg)
		var col: Color = _element_color if _has_element_color else Color(1.0, 0.95, 0.4)
		# Staged on the victim's HEAD, not their origin: `aim_point` is the drawn
		# head when there is one, so the arc lands on the body rather than in the
		# dirt at their feet.
		CombatVfx.spawn_burst(
			get_parent(), SpellTargets.aim_point(best), Color(col.r, col.g, col.b, 0.95),
			Color(col.r, col.g, col.b, 0.0), 8, 0.22, 50.0, 130.0, 1.0, 3.0, 0.0, 0.0, true
		)
		already.append(best)
		here = best.global_position


## THE IMPACT. Two emitters, because a hit has two halves the eye reads
## separately: the POP (the bolt's own energy released outward, radial) and the
## SPRAY (the momentum that was in it continuing along the travel axis, a cone).
## The single symmetric puff this used to be reads as the projectile quietly
## evaporating; splitting it is what makes the hit look like it PUSHED something.
##
## HDR start colour so the pop clears the arena's bloom threshold — a hit moment
## is supposed to be the brightest thing on screen (the Stick-Fight rule the rest
## of the combat already follows), and the old 1.0-clamped start never bloomed.
func _spawn_impact_burst() -> void:
	# Warm fire-bolt default; element-tinted when set_element_color() ran.
	var start: Color = Color(1.7, 1.35, 0.7, 0.95)
	var end: Color = Color(1.0, 0.55, 0.15, 0.0)
	if _has_element_color:
		var peak: float = maxf(_element_color.r, maxf(_element_color.g, _element_color.b))
		var k: float = 1.7 / maxf(peak, 0.001)
		start = Color(_element_color.r * k, _element_color.g * k, _element_color.b * k, 0.95)
		end = Color(
			_element_color.r * 0.5, _element_color.g * 0.5, _element_color.b * 0.5, 0.0
		)
	CombatVfx.spawn_burst(
		get_parent(), global_position, start, end,
		IMPACT_POP, 0.34, 110.0, 260.0, 1.4, 3.6, 1.0, 3.0, true
	)
	CombatVfx.spawn_burst(
		get_parent(), global_position, start, end,
		IMPACT_SPRAY, 0.42, 180.0, 420.0, 0.8, 2.2, 3.0, 6.0, true,
		_dir, IMPACT_CONE_DEG
	)
