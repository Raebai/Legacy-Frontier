class_name SigilGuard
extends Node2D
## THE CASTER'S GUARD — a magic circle summoned at the right moment. Right click
## and a sigil opens along your aim; a spell that meets it on time is CAUGHT in
## the circle and SENT BACK.
##
## Maker's words, and the whole spec: "the deflect for magic users should be a
## magic circle, and if the spell hits the circle at the exact time like a parry
## it gets absorbed and sent back."
##
## The gate hangs at arm's length and its aperture NARROWS as the window runs
## (see _apply_transform for why it narrows rather than closing inward).
##
## SAME CLOCK, DIFFERENT COSTUME. The timing underneath is ParryRing with
## `style = ParryRing.Style.SIGIL` — not a second implementation. This file owns
## only the two things that are genuinely class-specific: what you SEE (an
## edge-on MagicCircle instead of the swordsman's white arc) and what HAPPENS
## (the spell comes back instead of merely dying). Everything about when the
## window opens, how long it lasts and when it re-arms lives in ParryRing, so
## tuning the defensive budget stays one job in one place.
##
## EDGE-ON, NOT FACE-ON. This is a SIDE view. A circle whose magic travels toward
## the target is seen from the camera as a thin gate, not a flat ring — a face-on
## disc reads as a decal pasted on the screen. A previous session already built
## it face-on and it was wrong by design; BeamSpell's muzzle sigil is the
## reference (`set_orientation(true, dir, ...)`).
##
## ---------------------------------------------------------------------------
## WHAT COMES BACK — the question the maker's phrasing raises and this file has
## to answer. "Absorbed and sent back" is obvious for a bolt and impossible for a
## meteor barrage. Per SpellDeflect there are two spell shapes:
##
##   TRAVELS  (bolt, dagger, crawler, boulder, orbs) -> the reflect() path. The
##            ACTUAL spell reverses and flies back. This file is not involved;
##            the existing `_try_reflect` on the guarding body already does it,
##            and a mage gets the same treatment a swordsman does.
##   DOESN'T  (beams, meteors, zones, walls, pillars) -> SpellDeflect.resolve(),
##            which routes here. There is no meteor to reverse, so the circle
##            condenses what it swallowed into an ECHO: a single returned mote
##            carrying a fraction of the absorbed damage, tinted the colour of
##            the spell it ate.
##
## WHY AN ECHO AND NOT "IT JUST VANISHES": because the player must read ONE verb.
## If the circle sometimes returns fire and sometimes silently eats, the player
## cannot tell whether their read failed or the spell was simply exempt, and the
## whole defensive layer starts to feel unreliable — the exact failure SpellDeflect
## already argues against for unparryable ults. Catch-and-return every time is one
## sentence a player can hold in their head. The echo is deliberately NOT dressed
## up as a second spell with its own name; it is a spark that goes back the way
## the magic came, so it reads as the tail end of your parry, not a new ability.
##
## WHY A FRACTION AND A CAP: the damage a non-travelling spell passes to resolve()
## is per-tick and per-target, and an ult tick is enormous. Returning it at face
## value would make the mage's parry the single highest-damage action in the game
## and turn the defensive verb into the offensive one. ECHO_DAMAGE_MULT keeps it a
## consolation rather than a payday, and ECHO_DAMAGE_CAP stops one absorbed ult
## tick deleting whatever fired it.
## ---------------------------------------------------------------------------
##
## NO AUTO-AIM, EVER (locked project rule). The echo flies where the CIRCLE was
## pointing — which is where the player was pointing, since you had to face the
## sigil at the spell to catch it at all — and falls back to the exact reverse of
## the incoming direction if the sigil has no facing. There is no target search
## anywhere in this file, and the echo damages only what it physically flies into.
##
## Attach with `SigilGuard.of(body)`, the same duck-typed idiom GuardComponent
## uses, so Hero, the spike rig, an Enemy and a future bot all work unchanged and
## SpellDeflect can find it without the victim contract growing a new method.

## Node name used when attaching, so lookups are cheap and repeatable.
const NODE_NAME: StringName = &"SigilGuard"

## ---------------------------------------------------------------------------
## SIGIL TUNING. Like ParryRing's block above: REASONED, NOT FELT. Nothing here
## has been playtested — these are the numbers to argue with first.
## ---------------------------------------------------------------------------

## How far out the circle hangs, in pixels. Deliberately SpikeFigure.PARRY_REACH
## verbatim: the swordsman's shield arc is drawn at that radius, so both guards
## occupy exactly the same ring of space and an opponent reads "they are
## guarding" identically against either class.
const REACH: float = 40.0
## Aperture at full extension. Roughly the figure's own height (neck-to-hip plus
## the head is ~42 px), so the gate reads as a personal ward you aimed rather
## than as cover you hid behind — the circle is a point you defend, not a wall.
const RADIUS: float = 26.0
## Aperture at the tightest, as a fraction of RADIUS. The gate never closes to
## nothing, or the thing you are timing would be invisible at the exact moment
## it matters.
const RADIUS_MIN_FRAC: float = 0.34
## Extra bloom on the frame the circle catches something, as a fraction of radius.
const FLASH_BULGE: float = 0.55
## Seconds the catch-flash takes to settle back down.
const FLASH_DECAY: float = 0.18
## Fraction of the absorbed damage the echo carries back. Half: enough that the
## catch feels like it did something, nowhere near enough to be a damage plan.
const ECHO_DAMAGE_MULT: float = 0.5
## Hard ceiling on one echo, regardless of what was swallowed. An ult tick can be
## several hundred; without this, the safest action in the game is also the
## hardest-hitting one.
const ECHO_DAMAGE_CAP: int = 60
## Minimum gap between echoes. A ZONE spell ticks repeatedly, and a circle held
## across those ticks would machine-gun the sender. Suppressing the extra echoes
## costs the player nothing defensively — every tick is still fully absorbed —
## it only stops the return becoming a firehose.
const ECHO_MIN_INTERVAL: float = 0.35
## Grow time for the summoned circle. Short: the sigil must be UP by the time the
## band opens, or the visual lies about when the catch is live.
const SUMMON_TIME: float = 0.09

## Which group the echo hunts. "enemy" for a player's guard, "hero" for an
## enemy caster's — set by whoever attaches this. NOT a target search: the echo
## flies straight and this only decides what counts as a valid thing to hit.
var return_group: StringName = &"enemy"

var _circle: MagicCircle = null
## Where the circle faces — the player's aim, refreshed every frame by track().
var _dir: Vector2 = Vector2.RIGHT
var _colour: Color = Color(0.72, 0.55, 1.0)
var _flash: float = 0.0
var _echo_cd: float = 0.0
var _radius01: float = 1.0


## Find or create the sigil guard on a body. Mirrors GuardComponent.of() so both
## halves of the defensive story are attached the same way.
static func of(body: Node) -> SigilGuard:
	if body == null or not is_instance_valid(body):
		return null
	var existing: Node = body.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing != null:
		return existing as SigilGuard
	var s := SigilGuard.new()
	s.name = String(NODE_NAME)
	body.add_child(s)
	return s


## Only look it up, never create — for read-only checks on a damage path, which
## is how SpellDeflect asks "is this victim a caster?" without paying for a node
## on every swordsman in the fight.
static func peek(body: Node) -> SigilGuard:
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null(NodePath(String(NODE_NAME))) as SigilGuard


## Open the circle. Called on guard PRESS, i.e. exactly where a swordsman's arc
## blooms, so the two guards start on the same input and the same frame.
func summon(dir: Vector2, colour: Color) -> void:
	_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_colour = colour
	_radius01 = 1.0
	_flash = 0.0
	if _circle != null and is_instance_valid(_circle):
		_circle.queue_free()
	_circle = MagicCircle.new()
	# Parented to THIS node (a child of the guarding body) on purpose: the circle
	# is held by the caster, so it must travel with them. Contrast the echo below,
	# which is deliberately parented to the scene because it outlives the guard.
	add_child(_circle)
	_circle.appear(_colour, RADIUS, SUMMON_TIME)
	_circle.set_orientation(true, _dir, 0.22)
	_apply_transform()


## Per-frame follow. `radius01` comes straight from ParryRing, so the circle you
## watch and the window you are timing are the same number — the sigil closing in
## IS the shrinking ring, drawn as a caster instead of a swordsman.
func track(dir: Vector2, radius01: float) -> void:
	if dir != Vector2.ZERO:
		_dir = dir.normalized()
	_radius01 = clampf(radius01, 0.0, 1.0)
	_apply_transform()


## The circle failed to meet anything and fizzles, or the player let go. Either
## way it blooms out rather than snapping off — a summoning that ENDS reads as a
## cost paid; one that vanishes on a frame reads as a dropped draw call.
func dismiss() -> void:
	if _circle != null and is_instance_valid(_circle):
		_circle.vanish(0.16)
	_circle = null
	_flash = 0.0


func is_armed() -> bool:
	return _circle != null and is_instance_valid(_circle)


## THE OUTCOME. A perfectly-timed circle met a spell that cannot be reversed:
## flare, and spit an echo back along the way the circle was pointing.
##
## Damage is NOT decided here — SpellDeflect already zeroed it, and it also owns
## the shared payoff beat (the ding, the hitstop, the impact frame) so that a
## mage's catch and a swordsman's parry sound like the same verb. This adds only
## what is class-specific on top.
##
## FLARE-ONLY CALL: pass damage 0. The circle flashes and sparks but emits no
## echo, which is exactly what the TRAVELLING path wants — when `_try_reflect`
## sends the real spell back, the sigil should visibly have caught it, but adding
## an echo on top would return the spell twice.
func absorb(damage: int, incoming_dir: Vector2, at: Vector2) -> void:
	_flash = 1.0
	# Return direction: where the CIRCLE points. You had to aim the sigil at the
	# spell to catch it, so this is both player-controlled (the locked no-auto-aim
	# rule) and almost always the reverse of the incoming anyway. The reverse is
	# the fallback for a sigil with no meaningful facing.
	var back: Vector2 = _dir
	if back == Vector2.ZERO:
		back = -incoming_dir
	if back == Vector2.ZERO:
		return
	_catch_vfx(at, back)
	if _echo_cd > 0.0:
		return                       # a ticking zone is fully absorbed, just not re-fired
	var payload: int = mini(int(round(float(damage) * ECHO_DAMAGE_MULT)), ECHO_DAMAGE_CAP)
	if payload <= 0:
		return
	_echo_cd = ECHO_MIN_INTERVAL
	_spawn_echo(at, back.normalized(), payload)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta / FLASH_DECAY, 0.0)
	_echo_cd = maxf(_echo_cd - delta, 0.0)
	if _flash > 0.0:
		_apply_transform()


## The gate HANGS at a fixed arm's length and its APERTURE narrows as the window
## runs. It does not slide inward, for two reasons found by rendering it both
## ways:
##
##  1. It matches what the swordsman's guard actually does. Despite ParryRing's
##     "shrinks toward the body" phrasing, the rig draws the blade arc at a FIXED
##     PARRY_REACH and shrinks the angular SPAN it covers (SpikeFigure._draw /
##     _try_reflect). Coverage narrowing, not distance closing, is the shared
##     language — a sigil that crept inward would be a third behaviour to learn.
##  2. A gate that slides in ends up drawn on top of the caster at the exact
##     moment of the catch, which is the one frame that has to be readable.
##
## So the trade reads the same for both classes: the longer you hold, the less
## you cover, and timing it is the skill.
func _apply_transform() -> void:
	if not is_armed():
		return
	position = _dir * REACH
	var aperture: float = RADIUS * lerpf(RADIUS_MIN_FRAC, 1.0, _radius01)
	_circle.radius = aperture * (1.0 + FLASH_BULGE * _flash)
	_circle.set_orientation(true, _dir, 0.22)


## The catch: a bright ring-burst thrown along the RETURN direction, so the eye
## is already travelling the way the echo is about to go before it appears.
func _catch_vfx(at: Vector2, back: Vector2) -> void:
	var host: Node = _scene()
	if host == null:
		return
	CombatVfx.spawn_burst(host, at,
		Color(_colour.r * 1.6 + 0.4, _colour.g * 1.6 + 0.4, _colour.b * 1.6 + 0.4, 1.0),
		Color(_colour.r, _colour.g, _colour.b, 0.0),
		20, 0.4, 90.0, 260.0, 1.2, 3.4, 0.0, 0.0, true, back, 42.0)
	# Pitched well above the shared parry ding so a caster's catch is audible as
	# ITS OWN event without being a different sound — same family, higher voice.
	_sfx("ding", 5.0)


func _spawn_echo(at: Vector2, dir: Vector2, damage: int) -> void:
	var host: Node = _scene()
	if host == null:
		return
	var e := Echo.new()
	e.dir = dir
	e.damage = damage
	e.colour = _colour
	# FRIENDLY FIRE. The echo is a spell being SENT BACK, so it obeys the same policy
	# every cast spectacle does — `damage_group()` widens it to `mortal` while friendly
	# fire is on, which is what makes "he parried it into his own teammate" possible.
	e.target_group = SpellCaster.damage_group(return_group)
	# ...and the guard's own body is excluded, because that group now contains them.
	# The echo leaves at arm's length pointing away, so this is belt-and-braces today
	# and load-bearing the moment anything gives the echo a lifetime or an arc.
	e.caster_node = get_parent()
	host.add_child(e)
	e.global_position = at


## Where the echo lives. The SCENE, never this node: the echo must survive the
## guard being released, the circle vanishing, and the caster dying to the same
## exchange — all three of which would otherwise cut it off mid-flight.
func _scene() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root


func _sfx(key: String, volume_db: float) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var sfx: Node = tree.root.get_node_or_null(^"/root/Sfx")
	if sfx != null and sfx.has_method(&"play"):
		sfx.call("play", key, volume_db, 0.02)


## THE RETURNED SPARK. Deliberately the smallest possible entity: a point that
## flies straight, hits the first valid thing it physically reaches, and stops on
## walls. It is an inner class rather than a file of its own because it has
## exactly one creator and no meaning apart from it — promoting it to a top-level
## spell would invite it to grow a cooldown, an element and a name, and the whole
## point is that the player reads it as the tail of their parry.
##
## Radius-queries its target group rather than using collision layers, mirroring
## EnemyProjectile — no physics setup, and it stays deterministically testable.
class Echo extends Node2D:
	const SPEED: float = 540.0
	const HIT_RADIUS: float = 15.0
	## Fly until something stops it or it is well past any arena — never a
	## mid-air stop, matching every other projectile in the game.
	const MAX_TRAVEL: float = 1800.0

	var dir: Vector2 = Vector2.RIGHT
	var damage: int = 8
	var colour: Color = Color(0.72, 0.55, 1.0)
	var target_group: StringName = &"enemy"
	## The guarding body, so a friendly-fire-widened `target_group` cannot make the
	## echo turn round into the person who just parried. See SpellTargets.owner_of().
	var caster_node: Node = null
	var _travelled: float = 0.0
	var _dead: bool = false

	func _ready() -> void:
		rotation = dir.angle()

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		var prev: Vector2 = global_position
		global_position += dir * SPEED * delta
		_travelled += SPEED * delta
		queue_redraw()
		if _check_wall(prev):
			return
		if check_hit():
			return
		if _travelled >= MAX_TRAVEL:
			queue_free()

	## Stop on a platform/wall (collision layer 1). No-op without a physics world,
	## so headless tests that drive check_hit() directly never reach here.
	func _check_wall(prev: Vector2) -> bool:
		var world: World2D = get_world_2d()
		if world == null:
			return false
		var q := PhysicsRayQueryParameters2D.create(prev, global_position, 1)
		q.hit_from_inside = true
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return false
		global_position = hit["position"]
		_burst_and_free()
		return true

	## Damage the first member of the target group we physically reach. NO
	## seeking, no nearest-target scan, no steering — the group is a filter on
	## what we run into, which is what keeps this inside the no-auto-aim rule.
	## Public so a headless test can step it without a physics world.
	func check_hit() -> bool:
		if _dead:
			return false
		var tree: SceneTree = get_tree()
		if tree == null:
			return false
		for t: Node in SpellTargets.hostiles(self, target_group):
			if not (t is Node2D) or not is_instance_valid(t):
				continue
			if global_position.distance_to((t as Node2D).global_position) > HIT_RADIUS:
				continue
			if t.has_method("take_damage"):
				t.call("take_damage", damage)
			_burst_and_free()
			return true
		return false

	func _burst_and_free() -> void:
		if _dead:
			return
		_dead = true
		CombatVfx.spawn_burst(get_parent(), global_position,
			Color(colour.r, colour.g, colour.b, 0.9),
			Color(colour.r * 0.4, colour.g * 0.4, colour.b * 0.4, 0.0),
			14, 0.3, 70.0, 170.0, 1.0, 3.0, 0.0, 0.0, true)
		queue_free()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 1.0, 0.95))
		draw_circle(Vector2.ZERO, 7.0, Color(colour.r, colour.g, colour.b, 0.45))
		# Streak behind, so a returned spark reads as travelling rather than
		# hanging — the same shorthand every other bolt in the game uses.
		draw_line(Vector2.ZERO, Vector2(-14.0, 0.0), Color(colour.r, colour.g, colour.b, 0.55), 3.0)
