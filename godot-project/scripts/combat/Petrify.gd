class_name Petrify
extends Node2D
## PETRIFY — Tier 2 floor pickup. Stone crawls up the first body inside the marked
## footprint. While it is a statue it takes NO damage and cannot move; the next
## solid hit does not hurt it, it THROWS it, and the flying statue is a weapon.
##
## ⚠ IT WORKS ON YOUR TEAMMATE, and that is the spec's requirement rather than an
## accident of friendly fire. The catch scan goes through `SpellTargets.hostiles`
## against the stamped `target_group`, which under friendly fire is the shared
## `mortal` group — so it catches heroes, enemies and the guardian identically. The
## only body it can never catch is its own caster (`hostiles` subtracts them).
##
## THE THREE BEATS, and each is a different answer to "what is this spell for":
##   CATCH   — a short telegraph ring, then the nearest body in the footprint is
##             stone. If nobody is standing there the spell fizzles visibly; it does
##             not widen its search, because widening a search is auto-aim.
##   HOLD    — the statue is pinned and INVULNERABLE. That cuts both ways and is the
##             decision the spell exists to create: petrifying the thing that is
##             about to die saves its life, and petrifying your friend mid-combo
##             takes them out of the fight but also out of danger.
##   THROW   — the first damage that lands on the stone is converted into a launch.
##             The statue becomes a travelling body that hurts everything it passes,
##             then shatters — hurting the body inside it hardest of all.
##
## HOW "NO DAMAGE WHILE STONE" IS IMPLEMENTED, because it is unusual: this file
## OBSERVES the victim's `hp` every physics frame and puts back anything that went
## missing (`HpWatch`). It does not intercept `take_damage` — that lives on
## `Hero`/`Enemy`, which this agent does not own — so instead the rule holds for
## every damage source in the game at once. See `HpWatch`'s header for the tradeoff.

## Where the statue's damage is allowed to land, stamped by SpellCaster._stamp.
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.EARTH
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## THE TELL. Long enough to walk out of, short enough that the spell still feels
## like a snap decision. UNTESTED FEEL GUESS — the same 0.40 the Rock Pillar's
## eruption uses, because it is the same promise: a footprint on the ground and a
## beat to leave it.
const CATCH_TIME: float = 0.40
## How hard the statue hits whatever it is thrown through, and how hard the body
## inside it lands when it shatters. UNTESTED GUESS: 70 is above the biggest class
## HEAVY (Shadow Step's 85 is a single-body burst; this is a moving line) and well
## under an ult, so throwing your teammate at a brute is a real play and not a
## one-button kill.
const THROW_DAMAGE: int = 96
const THROW_SPEED: float = 900.0
## How long the statue stays in the air before it shatters on its own. It also
## shatters early on solid geometry.
const THROW_TIME: float = 0.55
## How far the launch looks for somebody to be thrown AWAY from. Beyond this the
## direction falls back to caster -> statue, so a throw always has a direction and
## never a zero vector.
const THROW_SENSE: float = 150.0
## Radius of the shatter burst that lands when the flight ends.
const SHATTER_RADIUS: float = 74.0
## Half-width of the statue's body as it flies — what it sweeps through.
const STATUE_HALF_WIDTH: float = 26.0
## Statue silhouette, drawn over the victim so the stone READS at 640x360: a solid
## slab body, a blockier head, and bright fracture lines. Grey against every
## element palette in the game on purpose.
const STONE_BODY: Color = Color(0.42, 0.40, 0.44)
const STONE_LIT: Color = Color(0.68, 0.66, 0.70)
const STONE_CRACK: Color = Color(0.16, 0.14, 0.18)
const STATUE_HEIGHT: float = 34.0

enum Phase { TELEGRAPH, STONE, FLYING, DONE }

var _phase: int = Phase.TELEGRAPH
var _center: Vector2 = Vector2.ZERO
var _radius: float = 92.0
var _life: float = 4.5
var _color: Color = Color(0.7, 0.6, 0.45)
var _elapsed: float = 0.0
var _victim: Node2D = null
## The HP the victim had at the last frame boundary. Anything below it is a hit the
## stone is supposed to swallow.
var _hp_mark: int = -1
var _vel: Vector2 = Vector2.ZERO
var _flight: float = 0.0
## Bodies already hurt by THIS throw, by instance id — a statue passing through a
## brute must not tick it every frame.
var _struck: Dictionary = {}
var _crack_seed: int = 0
## Where the statue is held. INF = not pinned yet (the first pin latches it).
var _pin_at: Vector2 = Vector2.INF


## The HEX entry point (see SpellCaster's HEX arm). `target` is the aimed ground
## point, already clamped to the spell's reach by the dispatcher.
func hex(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_center = target
	_radius = maxf(spell.radius, 20.0)
	_life = maxf(spell.length, 0.5)
	_color = color
	_crack_seed = randi()
	# Drawn in WORLD coordinates like every other spectacle in this codebase —
	# global_position stays at the arena origin and is NOT where the effect is.
	global_position = Vector2.ZERO
	# Run LATE in the frame. The pin below writes the victim's position and
	# velocity, and a hero writes both in its own `_physics_process`; whichever
	# runs last wins, so this must be last or the pin silently does nothing on
	# roughly half the bodies in the game.
	process_priority = 200
	process_physics_priority = 200
	SpellSigil.open(self, _center, color, maxf(_radius * 1.6, 26.0) / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.12, 0.45)
	SpellDrops.sfx("earth_pillar", -4.0, 0.06)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	match _phase:
		Phase.TELEGRAPH:
			if _elapsed >= CATCH_TIME:
				_catch()
		Phase.STONE:
			_hold(delta)
		Phase.FLYING:
			_fly(delta)
	queue_redraw()


# ------------------------------------------------------------------------ catch

func _catch() -> void:
	var found: Array = SpellTargets.in_radius(_center, _radius,
		SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self)
	var nearest: Node2D = null
	var best: float = INF
	for n: Node in found:
		if not HpWatch.is_alive(n):
			continue
		var d: float = SpellTargets.body_distance(n, _center)
		if d < best:
			best = d
			nearest = n as Node2D
	if nearest == null:
		# A visible fizzle. The spell did something even when it caught nothing —
		# silence would read as the button not working.
		CombatVfx.spawn_burst(get_parent(), _center, Color(0.6, 0.55, 0.45, 0.8),
			Color(0.3, 0.26, 0.2, 0.0), 10, 0.35, 40.0, 120.0, 1.0, 2.6)
		_finish()
		return
	_victim = nearest
	_hp_mark = HpWatch.hp_of(_victim)
	_phase = Phase.STONE
	_elapsed = 0.0
	if _victim.has_method("apply_status"):
		_victim.apply_status(element_id, false)   # the EARTH stagger, for the tint
	DebrisChunk.spawn_burst(get_parent(), _victim.global_position,
		Color(0.5, 0.48, 0.52), 10, Vector2.UP, 180.0)
	Juice.on_hit({"shake": 7.0, "sfx": "earth", "sfx_pitch": 0.05, "hitstop": 0.05})


# ------------------------------------------------------------------------ hold

## Pin the body, swallow anything that hits it, and turn the first hit into a
## launch. Ends by releasing the victim if nobody ever touched the statue.
func _hold(_delta: float) -> void:
	if not _statue_ok():
		_finish()
		return
	var hp_now: int = HpWatch.hp_of(_victim)
	if _hp_mark >= 0 and hp_now < _hp_mark:
		# Somebody hit the stone. Give the damage back — a statue takes none — and
		# spend the hit as the shove that throws it.
		HpWatch.restore(_victim, _hp_mark)
		_launch()
		return
	_hp_mark = hp_now
	_pin()
	if _elapsed >= _life:
		_finish()


## Freeze the body in place. Both writes are needed: zeroing velocity alone lets
## gravity re-accelerate it within the tick, and writing position alone fights the
## body's own `move_and_slide` on the next one.
func _pin() -> void:
	_victim.set(&"velocity", Vector2.ZERO)
	if _pin_at == Vector2.INF:
		_pin_at = _victim.global_position
	_victim.global_position = _pin_at


## Deterministic 0..1 hash — the same idiom as `BeamSpell._hash01` / `ChainBolt`.
## Local rather than borrowed so the crack pattern cannot change out from under
## this file when somebody retunes lightning.
static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


# ----------------------------------------------------------------------- throw

## Launch the statue AWAY from whoever is standing closest to it — which, since the
## thing standing closest is almost always the thing that just hit it, reads as
## "they punched the statue across the room". Falls back to the caster's own aim so
## a throw always has a direction.
func _launch() -> void:
	var away: Vector2 = Vector2.ZERO
	var closest: Node2D = null
	var best: float = THROW_SENSE
	for n: Node in get_tree().get_nodes_in_group(target_group):
		if n == _victim or not (n is Node2D) or not is_instance_valid(n):
			continue
		var d: float = SpellTargets.body_distance(n, _victim.global_position)
		if d < best:
			best = d
			closest = n as Node2D
	if closest != null:
		away = _victim.global_position - closest.global_position
	elif caster_node is Node2D and is_instance_valid(caster_node):
		away = _victim.global_position - (caster_node as Node2D).global_position
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	# Lifted off the horizontal so a thrown statue ARCS rather than skidding along
	# the floor. Not `Juice.lateral_knockback` — that exists to keep knockback from
	# launching people, and launching people is the entire point of this beat.
	_vel = (away.normalized() + Vector2.UP * 0.45).normalized() * THROW_SPEED
	_phase = Phase.FLYING
	_flight = 0.0
	_struck.clear()
	Juice.on_hit({"shake": 11.0, "zoom": 0.08, "sfx": "blast", "sfx_pitch": 0.1,
		"hitstop": 0.07})
	Juice.tier_frame(spell_tier, _victim.global_position, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


func _fly(delta: float) -> void:
	if not _statue_ok():
		_finish()
		return
	_flight += delta
	var from: Vector2 = _victim.global_position
	var to: Vector2 = from + _vel * delta
	# Solid geometry ends the flight where it meets it, rather than the statue
	# tunnelling through the arena wall it should be smashing against.
	var hit: Dictionary = SpellWorld.first_solid(from, to,
		SpellWorld.rids([_victim, caster_node]), self)
	if bool(hit.get("hit", false)):
		_victim.global_position = hit["position"]
		_pin_at = _victim.global_position
		_shatter()
		return
	_victim.global_position = to
	_pin_at = to
	_victim.set(&"velocity", Vector2.ZERO)   # the statue does not steer itself
	# Everything the statue sweeps through takes the hit, once each.
	for n: Node in SpellTargets.on_line(from, _vel.normalized(),
			from.distance_to(to) + STATUE_HALF_WIDTH, STATUE_HALF_WIDTH,
			SpellTargets.hostiles(self, StringName(target_group)),
			[_victim, caster_node], self):
		if _struck.has(n.get_instance_id()):
			continue
		_struck[n.get_instance_id()] = true
		SpellTargets.hurt(n, THROW_DAMAGE, Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 1.0))
		if n.has_method("apply_knockback"):
			n.apply_knockback(_vel.normalized() * 340.0)
	# A body turned to stone and hurled across the room is a PROJECTILE, and the most
	# obvious thing a thrown boulder does is demolish what it lands on. Swept along
	# the same segment as the fighter pass so the statue cannot pass through a crate
	# it visibly ploughs into.
	SpellSurfaces.on_line(self, from, _vel.normalized(),
		from.distance_to(to) + STATUE_HALF_WIDTH, STATUE_HALF_WIDTH, THROW_DAMAGE)
	if _flight >= THROW_TIME:
		_shatter()


## The stone comes apart. The body inside it takes the worst of it — being thrown
## across a room is supposed to hurt the thing that was thrown.
func _shatter() -> void:
	var at: Vector2 = _victim.global_position
	SpellTargets.hurt(_victim, THROW_DAMAGE, Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 1.0))
	for n: Node in SpellTargets.in_radius(at, SHATTER_RADIUS,
			SpellTargets.hostiles(self, StringName(target_group)), [_victim, caster_node], self):
		if _struck.has(n.get_instance_id()):
			continue
		SpellTargets.hurt(n, int(THROW_DAMAGE * 0.5),
			Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 1.0))
	# The statue coming apart shatters nearby cover at the same half damage the
	# splash deals to bodies.
	SpellSurfaces.in_radius(self, at, SHATTER_RADIUS, int(THROW_DAMAGE * 0.5))
	DebrisChunk.spawn_burst(get_parent(), at, Color(0.46, 0.44, 0.48), 22, Vector2.UP, 320.0)
	CombatVfx.spawn_burst(get_parent(), at, Color(0.8, 0.78, 0.82, 0.9),
		Color(0.32, 0.3, 0.34, 0.0), 20, 0.5, 90.0, 260.0, 1.4, 4.0)
	# Snapped: `at` is where the statue came apart, which is a BODY position and can be
	# mid-air against a wall. See `ScorchDecal.SNAP_LIFT`.
	ScorchDecal.spawn(get_parent(), at, SHATTER_RADIUS * 0.5, "crack",
		Color(0.55, 0.52, 0.56, 0.5), 6.0, true)
	Juice.on_hit({"shake": 14.0, "zoom": 0.1, "sfx": "blast", "sfx_pitch": 0.0,
		"hitstop": 0.08})
	_finish()


# --------------------------------------------------------------------- lifetime

## Is there still a statue to be a spell about? A victim that died, despawned or
## left the tree ends the effect rather than leaving a pin writing to a dead node.
func _statue_ok() -> bool:
	return _victim != null and is_instance_valid(_victim) \
		and not _victim.is_queued_for_deletion()


func _finish() -> void:
	_phase = Phase.DONE
	queue_free()


# ------------------------------------------------------------------------ draw

func _draw() -> void:
	match _phase:
		Phase.TELEGRAPH:
			_draw_telegraph()
		Phase.STONE, Phase.FLYING:
			if _statue_ok():
				_draw_statue(_victim.global_position)


## The footprint you must not be standing in, drawn at EXACTLY the catch radius —
## the same number `_catch` scans. One shape for the promise and the rule.
func _draw_telegraph() -> void:
	var t: float = clampf(_elapsed / CATCH_TIME, 0.0, 1.0)
	var a: float = 0.20 + 0.35 * t
	draw_arc(_center, _radius, 0.0, TAU, 44,
		Color(_color.r, _color.g, _color.b, a), 2.4, true)
	draw_circle(_center, _radius * t, Color(_color.r, _color.g, _color.b, 0.14), true, -1.0, true)
	# Four stone teeth closing inward — the shape of the thing about to happen.
	for i: int in 4:
		var ang: float = TAU * float(i) / 4.0
		var outer: Vector2 = _center + Vector2.RIGHT.rotated(ang) * _radius
		var inner: Vector2 = _center + Vector2.RIGHT.rotated(ang) * lerpf(_radius, _radius * 0.35, t)
		draw_line(outer, inner, Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 0.6 * t), 3.0, true)


## A stone slab over the body. Deliberately BLOCKIER than the stick rig underneath
## it — at 640x360 a tinted stick figure is indistinguishable from a stick figure,
## and "is that one petrified?" has to be answerable at a glance across the room.
func _draw_statue(at: Vector2) -> void:
	var h: float = STATUE_HEIGHT
	var w: float = STATUE_HALF_WIDTH * 0.72
	# ══ SAY THAT IT IS HAPPENING ════════════════════════════════════════════════
	# Maker: *"what does juggernaut petrification do it needs to be more visible"* —
	# asked about a spell they had just cast, which is the finding. A grey figure among
	# grey rubble on a floor full of spell light is nearly invisible, and everything
	# that made this spell interesting (it is HELD, it is INVULNERABLE, and it can be
	# thrown) is information the player had no way to read off the screen.
	#
	# Three marks, none of them a new node: a warm earth ring on the ground so the eye
	# is sent there, a HALO on the statue itself so it separates from the terrain it
	# is the same colour as, and a countdown arc — because "how long do I have to go
	# and throw this" is the only question the spell actually poses, and the answer was
	# nowhere on screen. Same shape `BloodPact` uses for its own duration, so the two
	# held effects in the game read the same way.
	if _phase != Phase.FLYING:
		var beat: float = 0.5 + 0.5 * sin(_elapsed * 5.0)
		var left: float = clampf(1.0 - _elapsed / maxf(_life, 0.001), 0.0, 1.0)
		draw_arc(at + Vector2(0.0, 4.0), w * 1.9, 0.0, TAU, 28,
			Color(0.85, 0.62, 0.30, 0.30 + 0.20 * beat), 2.4, true)
		draw_arc(at + Vector2(0.0, -h * 0.5), h * 0.78, 0.0, TAU, 30,
			Color(1.0, 0.82, 0.45, 0.16 + 0.12 * beat), 5.0, true)
		draw_arc(at + Vector2(0.0, 4.0), w * 2.3, -PI * 0.5, -PI * 0.5 + TAU * left,
			34, Color(1.2, 0.80, 0.35, 0.85), 2.6, true)
	var top: float = at.y - h
	var body := PackedVector2Array([
		Vector2(at.x - w, at.y + 4.0), Vector2(at.x - w * 0.8, top + h * 0.30),
		Vector2(at.x - w * 0.55, top), Vector2(at.x + w * 0.55, top),
		Vector2(at.x + w * 0.8, top + h * 0.30), Vector2(at.x + w, at.y + 4.0)])
	draw_colored_polygon(body, STONE_BODY)
	draw_polyline(body, Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 0.9), 2.0, true)
	# Fracture lines. Deterministic from a per-cast seed so the cracks do not crawl
	# frame to frame — a statue that shimmers reads as a bug, not as stone.
	for i: int in 3:
		var f: float = _hash01(_crack_seed + i * 733)
		var g: float = _hash01(_crack_seed + i * 977 + 17)
		draw_line(Vector2(at.x - w + w * 2.0 * f, top + h * 0.15),
			Vector2(at.x - w + w * 2.0 * g, at.y),
			Color(STONE_CRACK.r, STONE_CRACK.g, STONE_CRACK.b, 0.85), 1.6, true)
	# A dust plume trailing a thrown statue so the throw reads as travel.
	if _phase == Phase.FLYING:
		var back: Vector2 = at - _vel.normalized() * 22.0
		draw_line(at, back, Color(0.75, 0.72, 0.76, 0.45), 8.0, true)
