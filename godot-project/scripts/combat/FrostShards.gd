class_name FrostShards
extends Node2D
## CRYOMANCER BASIC ATTACK — CRYSTAL ICE SHARDS. A short volley of hard faceted
## shards thrown along the aim. Replaces the frost CONE that used to sit on this
## button.
##
## ⚠ WHY THE CONE IS GONE. Maker: *"cryomancers left click attack the cone is weird
## and too big just change it all shoot out some crystal ice shards or something
## instead"*. "Too big" was literally true and measurable:
## `tools/probe_basic_attack_visuals.gd` read the Cryomancer's tell as a CONE of
## **reach 118 px, half-angle 60 deg** — 120 degrees of arc, the widest AND longest
## basic attack in the nine-class roster (the Brawler's fist is 58 px / 72.5 deg).
## A 120-deg wedge is also a shape you cannot MISS with, which is the other half of
## why it read as weird: the class's most-pressed button asked nothing of the aim.
##
## ⚠ THIS IS A BASIC ATTACK, NOT A SPELL. It is the thing you press all fight, so it
## stays cheap: no summoning sigil (the Q's `RuneOrbs` volley opens one; this must
## not look like the Q), no homing, no stagger, one draw pass per frame, and a body
## that frees itself the moment the last shard resolves.
##
## ⚠ AND IT IS NOT THE Q WEARING A DIFFERENT HAT. The Cryomancer's Q is already
## called "Ice Shards" (`Hero._ice_shards` -> `RuneOrbs`, 6 orbs at 18). The two are
## deliberately different objects: the Q is a wide staggered FAN of round glowing
## orbs that weave, opened through a sigil; this is a tight simultaneous VOLLEY of
## straight faceted crystal that pierces. If they ever start reading as the same
## press, the thing to move is the SHAPE of one of them, not the colour.

## ⚠ NO HOMING, and no aim-assist of any kind. The locked rule (`Hero._primary_bolt`
## states it) is that hitting is the shooter's skill and dodging is the target's.
## Each shard flies a straight line along its own fixed fan angle from launch.

const SPEED: float = 560.0
## How far a shard flies before it gives out. DELIBERATELY SHORT OF A BOLT.
##
## The five bolt classes reach 560 px. Going from the cone's 118 px to a bolt's 560
## would not be a re-shape, it would be turning the Cryomancer into a sixth bolt
## class and deleting the "forces mid-range" identity the cone existed to enforce.
## 300 px keeps the class fighting inside its own authored band — `BotBrain`'s
## Cryomancer row asks a bot to hold **200 px** — while making the button usable at
## a distance a human can actually read.
const MAX_RANGE: float = 300.0
## Hard backstop on the NODE. MAX_RANGE / SPEED is 0.54 s, so this can only fire if a
## shard somehow stops advancing; it exists so a wedged volley still frees itself.
const MAX_LIFE: float = 1.6
const SHARD_COUNT: int = 3
## Radians between adjacent shards. TIGHT: at the full 300 px the outer shards sit
## only +-25.5 px off the axis, so the volley reads as one thrown handful rather than
## as the Q's wide fan. This number and `HIT_RADIUS` are what size the LANE tell in
## `Hero._primary_frost_shards`; move one and move the tell with it.
const FAN_SPREAD: float = 0.085
## The shard's forgiveness ring, ON TOP OF the target's own silhouette (see
## `_targets_swept`, which measures to the body rather than to its origin). 12 is a
## little wider than the 15 x 7 px shard is drawn — forgiveness comes from the
## attack's SHAPE, never from the engine steering it after release, which is what a
## slightly fat shard is and what homing would not be.
const HIT_RADIUS: float = 12.0
## Shard geometry, in px. Long and narrow so the facets read as crystal at 640x360.
const SHARD_LEN: float = 15.0
const SHARD_HALF_W: float = 3.6

## WHO THIS MAY HURT. Stamped by `Hero._stamp_faction` at cast time so the volley
## follows the CASTER's faction rather than being fixed at "enemy" forever — the same
## bug `RuneOrbs`' header records, avoided here by declaring the field up front.
## `set()` on an UNDECLARED property is a silent no-op in GDScript, which is why all
## three of these are written out rather than assumed.
var target_group: String = "enemy"
var caster_node: Node = null
## The shelf this sits on. A basic attack is the LIGHTEST thing in the kit — it must
## lose every clash contest against a Q or an ult, and saying so costs one line.
## `QUICK` is the lightest shelf `SpellTier.Tier` declares; there is no lighter one.
var spell_tier: int = SpellTier.Tier.QUICK
var element_id: int = Elements.Element.ICE

var _color: Color = Color(0.55, 0.85, 1.0, 1.0)
var _dmg: int = 6
var _shards: Array = []   # each: {origin, dir, alive, pos, hit: Dictionary}
var _elapsed: float = 0.0
## Cached ONCE — `TuningConfig.quality_is_low()` must never be asked per-draw, and
## `_draw` here runs every frame for every live shard. Same pattern as `Telegraph._low`.
var _low: bool = false


func _ready() -> void:
	_low = TuningConfig.quality_is_low()


## `origin` is the weapon tip, `aim` the direction fixed at the press. `damage` is
## PER SHARD — see `Hero._primary_frost_shards` for the before/after arithmetic.
func launch(origin: Vector2, aim: Vector2, color: Color, count: int = SHARD_COUNT,
		damage: int = 6) -> void:
	_color = color
	_dmg = damage
	var base: Vector2 = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	for i: int in maxi(count, 1):
		# Symmetric fan around the aim. NO STAGGER: the Q streams, this one THROWS —
		# three shards leaving together is what makes one press read as one attack.
		var offset: float = float(i) - float(maxi(count, 1) - 1) * 0.5
		var dir: Vector2 = base.rotated(offset * FAN_SPREAD)
		_shards.append({
			"origin": origin,
			"dir": dir,
			"alive": true,
			"pos": origin,
			"hit": {},   # instance ids already damaged by THIS shard — see PIERCE
		})
	global_position = Vector2.ZERO   # draws in world coordinates, like RuneOrbs
	# ⚠ NO `Sfx.play` HERE, AND THAT IS DELIBERATE. `Sfx` is an AUTOLOAD, and naming an
	# autoload inside a script that also carries a `class_name` forces compile-time
	# autoload resolution on every file that references the class — which under
	# `godot --headless --script <suite>` (how every suite in `tools/` runs) fails with
	# "Identifier not found: Sfx" and takes the whole suite down before its first
	# assertion. `RuneOrbs` gets away with it only because `Hero` reaches it through
	# `load()` at runtime rather than by name. `Hero._resolve_frost_shards` plays the
	# throw sound instead; it is loaded at runtime, so the autoload is live by then.
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	var any_alive: bool = false
	for shard: Dictionary in _shards:
		if not bool(shard["alive"]):
			continue
		any_alive = true
		var prev: Vector2 = shard["pos"]
		var travelled: float = SPEED * _elapsed
		shard["pos"] = (shard["origin"] as Vector2) + (shard["dir"] as Vector2) * travelled
		# THE WORLD SWEEP, swept from the PREVIOUS position rather than point-tested at
		# the new one: at 560 px/s a point test tunnels through anything thinner than
		# 9.3 px at 60 fps, which is most ledges. Maker's standing note, recorded on
		# `RuneOrbs`: *"the projectiles shouldn't go through the floor or anything"*.
		var world: Dictionary = SpellWorld.first_solid(prev, shard["pos"], [], self)
		if bool(world["hit"]):
			shard["pos"] = world["position"]
			_shatter(shard["pos"])   # it breaks ON the surface, not inside it
			shard["alive"] = false
			continue
		# ⚠ PIERCE, AND THIS IS A DECISION RATHER THAN AN OVERSIGHT.
		#
		# Two reasons, one of them the maker's. (1) The cone this replaces hit EVERY
		# body in its 120-deg arc for full damage — a shard that died on the first
		# torso would have quietly deleted the ice class's crowd-control identity
		# along with the cone's shape, which is a balance change hiding inside a
		# visual one. (2) The maker complained that Crescent Rush *stops dead on
		# first contact*; read as a general preference, a projectile that expires on
		# the first thing it grazes is the feel being complained about.
		#
		# What pierce does NOT mean: a shard may not damage the same body twice, so
		# `hit` is a per-shard id set. Three shards through one torso is 18, exactly
		# the volley's total — piercing widens the attack across a CROWD, it never
		# multiplies it into a single target.
		#
		# Geometry still ends the flight: a shard stops on the world (above) and at
		# MAX_RANGE (below). It pierces BODIES, not walls.
		for e: Node in _targets_swept(prev, shard["pos"], HIT_RADIUS):
			var id: int = e.get_instance_id()
			if shard["hit"].has(id):
				continue
			shard["hit"][id] = true
			_pierce(shard["pos"], e)
		if travelled >= MAX_RANGE:
			# It SHATTERS rather than blinking out. A spent shard that simply vanished
			# reads as the attack fizzling — the same note `RuneOrbs._burst` records.
			_shatter(shard["pos"])
			shard["alive"] = false
	if _elapsed >= MAX_LIFE:
		for shard: Dictionary in _shards:
			if bool(shard["alive"]):
				_shatter(shard["pos"])
			shard["alive"] = false
		any_alive = false
	if not any_alive:
		queue_free()
		return
	queue_redraw()


## Damage + chill one body the shard has physically flown into.
##
## ⚠ ROUTED THROUGH `SpellTargets.hurt`, NEVER `take_damage` DIRECTLY. Two signatures
## ship in this codebase (Hero takes one arg, Enemy two); calling the wrong one THROWS
## and aborts the enclosing function, losing that hit and every shard after it in the
## same frame. `hurt` adapts the arity.
func _pierce(at: Vector2, e: Node) -> void:
	SpellTargets.hurt(e, _dmg, Color(_color.r, _color.g, _color.b, 1.0))
	if e.has_method("apply_status"):
		e.apply_status(element_id)
	if e.has_method("apply_knockback"):
		# A LIGHT tick, and deliberately far under the cone's 160: three shards through
		# one body would otherwise shove three times for what used to be one push.
		e.apply_knockback((at - (e as Node2D).global_position).normalized() * -55.0)
	_shatter(at)


## The break VFX on its own, so a shard stopped by a wall looks like a shard stopped
## by a body. Halved at LOW quality rather than skipped — a hit with no feedback at
## all is worse than a cheap one.
func _shatter(at: Vector2) -> void:
	CombatVfx.spawn_burst(get_parent(), at,
		Color(_color.r, _color.g, _color.b, 0.95), Color(_color.r, _color.g, _color.b, 0.0),
		3 if _low else 7, 0.22, 40.0, 130.0, 0.6, 1.5, 0.0, 0.0, true)


## Everything damageable the shard SWEPT THROUGH between `from` and `to` — the
## caster's hostile faction first, then the always-neutral destructibles (cover
## belongs to nobody, so it stays a literal rather than following the caster).
##
## ⚠ SWEPT, NOT POINT-TESTED, AND THE FIRST VERSION OF THIS FILE GOT IT WRONG. It
## asked "is anything within HIT_RADIUS of where the shard IS", and at SPEED 560 a
## frame is 9.3 px while HIT_RADIUS is 9 — so a shard steps clean over a body more
## often than not. `slice_test_cryomancer_kit` caught it immediately and precisely: a
## dummy at +150 px was hit and a dummy at +70 px was not, which is the signature of
## sampling rather than of aiming. The same reasoning the world sweep above already
## carries, applied to bodies: measure the SEGMENT the shard covered this frame.
##
## ⚠ THROUGH `SpellTargets.on_line`, NOT A HAND-ROLLED DISTANCE CHECK. The second
## version of this function measured to the target's ORIGIN, and that is the head bug
## the cone this replaces carried a comment about, arriving from the other end: the
## volley leaves `rig.get_weapon_tip()`, measured at **14.2 px above** the body origin,
## so a shard fired dead level at a torso passes over its centre by more than a shard
## is wide. `on_line` measures to the target's SILHOUETTE (`body_distance`) and applies
## the same line-of-sight filter every other spell uses, which is what makes "it looked
## like it went through their chest" and "it hit" the same event.
func _targets_swept(from: Vector2, to: Vector2, r: float) -> Array[Node]:
	var out: Array[Node] = []
	var span: Vector2 = to - from
	if span.length_squared() < 0.0001:
		return out
	for group: String in [target_group, "destructible"]:
		for e: Variant in SpellTargets.on_line(from, span, span.length(), r,
				SpellTargets.hostiles(self, group), [], self):
			if e is Node:
				out.append(e as Node)
	return out


func _draw() -> void:
	for shard: Dictionary in _shards:
		if not bool(shard["alive"]):
			continue
		_draw_shard(shard["pos"], shard["dir"])


## ONE CRYSTAL. Hard straight facets and a bright core — no soft puffs, no halo, no
## round glow. Six points: a sharp tip, two shoulders, two rear facets and a tail, so
## the silhouette reads as a knapped shard rather than as a bullet.
func _draw_shard(p: Vector2, dir: Vector2) -> void:
	var f: Vector2 = dir                       # forward
	var s: Vector2 = dir.orthogonal()          # sideways
	var body := PackedVector2Array([
		p + f * SHARD_LEN * 0.60,                                    # tip
		p + f * SHARD_LEN * 0.12 + s * SHARD_HALF_W,                 # right shoulder
		p - f * SHARD_LEN * 0.28 + s * SHARD_HALF_W * 0.45,          # right rear facet
		p - f * SHARD_LEN * 0.40,                                    # tail
		p - f * SHARD_LEN * 0.28 - s * SHARD_HALF_W * 0.45,          # left rear facet
		p + f * SHARD_LEN * 0.12 - s * SHARD_HALF_W,                 # left shoulder
	])
	draw_colored_polygon(body, Color(_color.r * 0.7, _color.g * 0.85, _color.b, 0.92))
	# THE BRIGHT CORE — a second, narrower facet inside the first, HDR-white so the
	# shard has a lit spine instead of being one flat chip of colour.
	var core := PackedVector2Array([
		p + f * SHARD_LEN * 0.52,
		p + f * SHARD_LEN * 0.06 + s * SHARD_HALF_W * 0.34,
		p - f * SHARD_LEN * 0.30,
		p + f * SHARD_LEN * 0.06 - s * SHARD_HALF_W * 0.34,
	])
	draw_colored_polygon(core, Color(1.35, 1.5, 1.6, 0.95))
	if _low:
		return   # the rim is the first thing to go — the silhouette above survives
	# The rim: a hard unantialiased outline. Straight segments only; this is the line
	# that makes the facets read as cut rather than as a blurred streak.
	draw_polyline(body + PackedVector2Array([body[0]]),
		Color(0.9, 0.98, 1.0, 0.85), 1.0, false)
