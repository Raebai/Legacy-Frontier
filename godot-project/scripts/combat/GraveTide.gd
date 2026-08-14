extends Node2D
## ══ GRAVE TIDE ════════════════════════════════════════════════════════════════
## The Warlock's ULT. The floor of the room gives way in both directions at once and
## a WAVE OF HANDS comes up out of it, sweeping outward from where he stands. What it
## reaches is held where it stands and bled dry into him while it struggles.
##
## ── WHAT THIS REPLACES, AND WHY IT IS NOT THAT ────────────────────────────────
## `void_barrage` was `MeteorSigil.rain()` with a shadow tint — the fourth recolour
## of one bombardment, in a kit that already owns two shadow spells. Recolours are
## banned, so this is deliberately NOT a sky effect: nothing falls, nothing is aimed
## at a marked patch of ground, and there is no overhead sigil.
##
## ── AND WHY IT IS NEITHER OF THE OTHER TWO SHADOW SPELLS ──────────────────────
## The kit already has two ground-borne shadow verbs and the whole risk here was
## becoming a third copy of one of them. The three now split cleanly on DELIVERY:
##
##   SHADOW ROOT     precomputes ONE grasp point at cast time and races a purely
##                   cosmetic vein to it on a fixed clock. Dodged POSITIONALLY —
##                   be off the mark. One victim area, one lock.
##   CREEPING SHADE  is ONE travelling head doing a per-frame floor probe; the
##                   strike point is emergent, it LAUNCHES what it finds, and it is
##                   dodged by TIMING — be airborne when it passes. It goes UNDER
##                   walls, which is documented as its whole identity.
##   GRAVE TIDE      is a WAVEFRONT, not a point and not a head: two advancing
##                   lines with a persistent WAKE behind them. It catches EVERYTHING
##                   the front crosses rather than one thing, it leaves the floor
##                   occupied after it has passed, and it is the only one of the
##                   three that FEEDS the caster. It is dodged by NOT BEING ON THE
##                   FLOOR when the front arrives — a jump clears it — which is a
##                   third answer, not a re-skin of the other two.
##
## Crucially it is STOPPED BY WALLS, where Creeping Shade passes under them. That is
## the deliberate inverse of the crawler's exemption: if the ult also ignored cover
## the kit's answer-to-a-barrier would stop being special.
##
## ── WORLD CONTRACT (docs/spell-world-contract.md) ─────────────────────────────
## SPAWN.   Each front's span is CLIPPED against geometry before anything is drawn,
##          at a real height (`TIDE_HEIGHT`) rather than as a hairline — a knee-high
##          lip stops the tide, and it cannot be drawn through a wall it is not
##          crossing.
## TRAVEL.  The front follows the FLOOR via `SpellWorld.ground_path`, so it climbs
##          steps and slopes, and it STOPS AT THE LIP OF A PIT (the pit rule) rather
##          than sweeping across thin air.
## IMPACT.  Catches are line-of-sight tested from the FRONT, not from the caster —
##          the hands come up under the victim, so what matters is whether anything
##          stands between that patch of floor and the body.
## DEFLECT. Threaded through `SpellDeflect.resolve`, so a correctly-timed guard eats
##          the grasp entirely: no damage, no root, no drain, no victim entry.
##
## Parked at the arena origin like every spectacle here: `global_position` is (0,0)
## and is NOT where the effect is. Everything is resolved and drawn in world space.

# ───────────────────────────────────────────── the five stamped identity fields
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.SHADOW
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

# ═════════════════════════════════════════════════════════ THE TIDE
## The beat between the cast and the first hand — the ground cracks, THEN it opens.
## This is the whole dodge window for anyone standing on the caster, and it is
## shorter than every enemy attack windup on purpose: this is an ult you are
## supposed to be surprised by if you let it be cast next to you.
const SURGE_LEAD: float = 0.35
## How fast each front crosses the floor. Faster than Creeping Shade (520) because a
## wave you can outrun is not a wave; slow enough that a body at the far edge of the
## room genuinely has time to jump.
const TIDE_SPEED: float = 620.0
## How high the hands reach, and therefore how high you must be to have cleared them.
## ⚠ ONE CONSTANT FEEDS BOTH THE DRAW AND THE CATCH. ShadowRoot shipped with a 46 px
## picture and a 100 px hitbox and rooted people through tendrils that visibly ended
## below their feet; that is not repeated here.
const CATCH_HEIGHT: float = 52.0
## ...and how far BELOW the front still counts. A step down, not a floor down.
const CATCH_BELOW: float = -44.0
## The band the span is clipped against when asking "is there a wall in the way".
## A hairline ray slips under every raised lip; the tide is a chunky ground effect.
const TIDE_HEIGHT: float = 40.0
## ⚠ HOW FAR ABOVE THE FLOOR THE WALL PROBE STARTS, AND IT IS LOAD-BEARING.
## `SpellWorld` casts with `hit_from_inside` ON, so a ray whose band touches the floor
## surface reports the FLOOR as the first solid — at distance zero — and every front
## is clipped to nothing before it has travelled a pixel. ShadowRoot documents the
## same trap on its catch ray; this suite caught it here on the first run with a real
## floor slab under the caster (both fronts came back with a span of 0). Six pixels is
## enough to clear the surface and far under the height of anything that should stop a
## ground wave.
const SURGE_CLEAR: float = 6.0
## Floor samples per side. The path is re-walked once, at cast, not per frame.
const PATH_STEPS: int = 22

# ═════════════════════════════════════════════════════════ THE GRIP
## How long a caught body is held after the front reaches it.
const HOLD_TIME: float = 1.7
## Root refresh cadence, and how early to stop refreshing so the release lands with
## the victim breaking free rather than with an invisible timer expiring. Both
## borrowed verbatim from ShadowRoot — one CC scheme in this school, not two.
const REAPPLY_EVERY: float = 0.25
const REAPPLY_CUTOFF: float = 0.5
## The hands sinking back once the grip lets go.
const SINK_TIME: float = 0.5

# ═════════════════════════════════════════════════════════ THE DRAIN
## Seconds between drain ticks, and what one tick takes from each held body.
const DRAIN_EVERY: float = 0.35
const DRAIN_PER_TICK: int = 6
## ...and what one tick gives back to the caster PER HELD BODY.
const HEAL_PER_TICK: int = 4
## ⚠ THE HEAL IS CAPPED BY BODY COUNT, AND THIS IS THE BALANCE OF THE SPELL.
## Uncapped, an ult that heals per victim per tick means a Warlock who catches eight
## trash mobs is at full hp before the grip ends — which turns the finisher into a
## full heal on a 9 s cooldown and makes the class unkillable in exactly the fights
## it is supposed to be spent in. Three bodies is a good catch; the fourth onward
## still DIES faster, it just stops feeding you.
const MAX_HEAL_BODIES: int = 3

# ═════════════════════════════════════════════════════════ FRIENDLY FIRE
## ⚠ THE NAMED ANSWER: YES, THE TIDE TAKES YOUR PARTNER, AND NO, IT NEVER TAKES YOU.
##
## The group this sweeps is whatever `SpellCaster._stamp` wrote, which under friendly
## fire is the shared `mortal` group — so the other hero, and the caster's own
## thralls, are in it. That is not an oversight to be patched out: friendly fire is
## the social engine, an ult that opens the floor under the whole room SHOULD be the
## loudest expression of it, and a co-op partner has the same jump everyone else has.
##
## The caster is the one exception, and it is structural rather than a special case:
## every victim scan goes through `SpellTargets.hostiles()`, which subtracts the
## spectacle's own `caster_node`. The hands come out of HIS floor at HIS command — a
## necromancer rooted by his own dead is a different, worse joke than a necromancer
## rooting his friend.
const TIDE_CATCHES_ALLIES: bool = true

# ═════════════════════════════════════════════════════════ THE PICTURE
## Hands standing in the wake, high picture and cheap picture. The crest gets its own
## denser cluster on top of these.
const WAKE_HANDS: int = 30
const WAKE_HANDS_LOW: int = 12
const CREST_HANDS: int = 9
const CREST_HANDS_LOW: int = 4
const REDRAW_HZ_HIGH: float = 30.0
const REDRAW_HZ_LOW: float = 15.0

# ────────────────────────────────────────────────────────────────────── state
var _color: Color = Color(0.55, 0.35, 0.85)
var _origin: Vector2 = Vector2.ZERO
var _damage: int = 40
var _elapsed: float = 0.0
var _life: float = 4.0
var _low: bool = false
var _next_draw: float = 0.0
var _seed: int = 0
## One entry per side: the floor polyline the front walks, and how far along it is.
var _paths: Array[PackedVector2Array] = []
var _travelled: Array[float] = []
var _spans: Array[float] = []
## `{"node": Node2D, "anchor": Vector2, "held": float}`
var _victims: Array[Dictionary] = []
var _caught_ids: Dictionary = {}   # instance_id -> true, so nobody is caught twice
var _reapply_t: float = 0.0
var _drain_t: float = 0.0
var _drained: int = 0
var _healed: int = 0
## The `_draw` completion sentinel (see SpawnTell / slice_test_loadout): a runtime
## error inside `_draw` aborts it silently, and `entered > completed` is the only
## thing a headless suite can actually observe about that.
var _draw_entered: int = 0
var _draw_done: int = 0


func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_color = color
	_origin = origin
	_seed = randi()
	_low = TuningConfig.quality_is_low()
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	if spell != null:
		_damage = maxi(spell.damage, 1)
	var reach: float = 520.0
	if spell != null and spell.reach > 1.0:
		reach = spell.reach
	# THE AIM DOES NOT CHOOSE A SIDE. A tide that only went the way you pointed would
	# be a lane, and the kit already has lanes; the point of this ult is that there is
	# nowhere on the floor to stand. `target` is consumed only to bias which side runs
	# a touch further, so pointing still means something without meaning "only there".
	var bias: float = signf(target.x - origin.x)
	if bias == 0.0:
		bias = 1.0
	_build_side(Vector2.RIGHT, reach * (1.15 if bias > 0.0 else 0.85))
	_build_side(Vector2.LEFT, reach * (1.15 if bias < 0.0 else 0.85))
	var travel: float = 0.0
	for s: float in _spans:
		travel = maxf(travel, s / TIDE_SPEED)
	_life = SURGE_LEAD + travel + HOLD_TIME + SINK_TIME
	SpellSigil.open(self, origin, color, 1.5, false, Vector2.RIGHT, true, 0.16, 0.55)
	SpellDrops.sfx("void_pull", 0.0, 0.08, 0.62)
	SpellDrops.sfx("rumble", -3.0, 0.1, 0.7)
	Juice.zoom_pull_camera(0.24, _life * 0.5, 0.22, 0.75)   # an ult reveals the room
	Juice.shake_camera(9.0)
	queue_redraw()


## One front: the floor it will walk, clipped at the first wall and truncated at the
## first pit lip. Walked ONCE, here, rather than probed per frame — a wave crossing a
## room is 22 ray casts total instead of 22 a frame.
func _build_side(dir: Vector2, reach: float) -> void:
	# THE TIDE OPENS AT THE FLOOR, NOT AT THE CASTER'S NAVEL. `_origin` is the hero's
	# centre; `floor_point` drops it to the surface he is standing on, and returns it
	# UNCHANGED when there is no floor (see its ⚠), which is exactly the fallback the
	# airborne case wants.
	var base: Vector2 = SpellWorld.floor_point(_origin, SpellWorld.FLOOR_PROBE, [], self)
	var far: Vector2 = base + dir * maxf(reach, 1.0)
	# WALLS. Clipped as a path of real height so a knee-high lip stops the tide rather
	# than being slipped under. Degrades to `far` with no physics world, which is the
	# right way round for a headless harness: a world with no walls.
	var lift := Vector2(0.0, -(TIDE_HEIGHT * 0.5 + SURGE_CLEAR))
	far = SpellWorld.clip(base + lift, far + lift, TIDE_HEIGHT, [], self)
	far.y = base.y
	var path: PackedVector2Array = SpellWorld.ground_path(base, far, PATH_STEPS,
		SpellWorld.FLOOR_PROBE, [], self)
	# ⚠ AN EMPTY PATH IS NOT A REASON TO CANCEL THE ULT. `ground_path` returns nothing
	# the moment the FIRST sample has no floor under it — which is true of every
	# headless harness (no world at all) AND of a Warlock who cast this while airborne,
	# which is a thing players do constantly. Refusing to build the side in that case
	# means a 74-MP finisher that silently does nothing whenever you jump. So the
	# fallback is a flat line at the base: terrain-following is a bonus the geometry
	# grants, never a precondition for the spell existing. The PIT RULE is untouched —
	# a path that finds floor and then stops still truncates at the lip.
	if path.size() < 2:
		path = PackedVector2Array([base, far])
	var span: float = 0.0
	for i: int in range(1, path.size()):
		span += path[i - 1].distance_to(path[i])
	if span <= 1.0:
		return
	_paths.append(path)
	_travelled.append(0.0)
	_spans.append(span)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _life:
		_release()
		return
	if _elapsed >= SURGE_LEAD:
		_advance(delta)
		_hold(delta)
	_next_draw -= delta
	if _next_draw <= 0.0:
		_next_draw = 1.0 / (REDRAW_HZ_LOW if _low else REDRAW_HZ_HIGH)
		queue_redraw()


# ─────────────────────────────────────────────────────────────────── the front
func _advance(delta: float) -> void:
	for i: int in _paths.size():
		var before: float = _travelled[i]
		if before >= _spans[i]:
			continue
		var after: float = minf(before + TIDE_SPEED * delta, _spans[i])
		_travelled[i] = after
		_sweep(i, before, after)


## Everyone the front crossed BETWEEN the last frame and this one. Swept as a band
## rather than tested at a point, because at 620 px/s a point test skips whole bodies
## between frames — the classic "the wave went through me and nothing happened".
func _sweep(side: int, from_d: float, to_d: float) -> void:
	var a: Vector2 = _point_at(side, from_d)
	var b: Vector2 = _point_at(side, to_d)
	var lo: float = minf(a.x, b.x)
	var hi: float = maxf(a.x, b.x)
	var caught: Array = []
	for e: Node in SpellTargets.alive(SpellTargets.hostiles(self, StringName(target_group))):
		var n: Node2D = e as Node2D
		if n == null or _caught_ids.has(n.get_instance_id()):
			continue
		var margin: float = SpellTargets.hit_margin(n)
		if n.global_position.x < lo - margin or n.global_position.x > hi + margin:
			continue
		# Vertical band, measured against the FRONT's own floor height rather than a
		# flat y — the tide climbs, so what counts as "on the floor with it" climbs too.
		var lift: float = b.y - n.global_position.y
		if lift > CATCH_HEIGHT or lift < CATCH_BELOW:
			continue   # airborne over the wave, or standing on another floor — dodged
		caught.append(n)
	# Cover between the FRONT and the body, not between the caster and the body: the
	# hands come up out of the floor under the victim. Lifted clear of the floor
	# surface before the ray starts — SpellWorld casts with hit_from_inside ON, and a
	# ray begun exactly on the ground reports the ground and culls everyone (the bug
	# ShadowRoot's headless suite caught).
	var probe: Vector2 = b + Vector2(0.0, -TIDE_HEIGHT * 0.5)
	for e: Node in SpellWorld.filter_reachable(probe, caught, [], self):
		_grab(e as Node2D)


func _grab(n: Node2D) -> void:
	if n == null or not is_instance_valid(n):
		return
	# Deflectable, on the ULT window (0.22 of the normal one). The shove direction is
	# UP, out of the ground, which is where the hands came from. A guard inside that
	# window eats the grasp whole — no damage, no root, no drain, and crucially no
	# `_victims` entry, so it is not held either. The tighter window is the point of
	# the constant existing: turning aside a finisher should take a read, not a habit.
	var dealt: int = SpellDeflect.resolve(n, _damage, Vector2.UP,
		SpellTargets.aim_point(n), SpellDeflect.WINDOW_ULT)
	if dealt <= 0:
		return
	_caught_ids[n.get_instance_id()] = true
	SpellTargets.hurt(n, dealt, Color(_color.r, _color.g, _color.b, 1.0))
	if n.has_method("apply_status"):
		# EARTH first = StatusComponent's direct-root channel; SHADOW last = Weaken
		# plus the violet overlay tint (the component tints from the LAST element),
		# so the root reads as shadow rather than as earth. Same order ShadowRoot uses.
		n.apply_status(Elements.Element.EARTH)
		n.apply_status(Elements.Element.SHADOW)
	_victims.append({"node": n, "anchor": n.global_position, "held": 0.0})
	# ⚠ WAS `Juice.impact_frame(0.35, ...)` — THE LEGACY PRE-STYLE API, FIRED PER
	# VICTIM. Two faults in one line. It is the white blow-out, so the Warlock's
	# ULTIMATE ended on the same screen as every ordinary heavy attack in the game,
	# which is exactly the sameness that made StarConvergence, EnergyNova and
	# HollowPurple delete their frames outright. And a tide that catches five bodies
	# asked for five of them; the arbiter refused the rest, so the request was
	# noise, but asking five times for the wrong mark is not better than asking once.
	#
	# INVERT is the vocabulary's own answer for "shadow / void / reality-bending
	# beats" — the world stays perfectly readable because it IS the same picture,
	# while reading as deeply wrong. That is the dead coming up through the floor.
	#
	# It shares INVERT with `thousand_cuts`, the Shadowblade's ult, and that is
	# accepted rather than overlooked: the two are never in one kit, the mark
	# belongs to the ELEMENT here, and the failure the vocabulary exists to prevent
	# was every ult sharing ONE mark regardless of element — not two shadow ults
	# agreeing about shadow. The ladder's own COLOR_FIELD was the alternative and
	# would have ended the Warlock on a violet wash, which is a weaker read of
	# "something impossible just happened" than the negative.
	#
	# ON THE FIRST CATCH ONLY, and at ULT weight rather than the old 0.35.
	if _victims.size() == 1:
		Juice.tier_frame(SpellTier.Tier.ULT, n.global_position, element_id,
			{"style": ImpactFrame.Style.INVERT})


# ───────────────────────────────────────────────────────────────────── the grip
## Roots refreshed, bodies eased back to where they were caught, life pulled out of
## them and into the caster. One pass, because all four are the same clock.
func _hold(delta: float) -> void:
	_reapply_t -= delta
	_drain_t -= delta
	var refresh: bool = _reapply_t <= 0.0
	if refresh:
		_reapply_t = REAPPLY_EVERY
	var drain: bool = _drain_t <= 0.0
	if drain:
		_drain_t = DRAIN_EVERY
	var fed: int = 0
	var live: Array[Dictionary] = []
	for v: Dictionary in _victims:
		var n: Node2D = v["node"] as Node2D
		if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var held: float = float(v["held"]) + delta
		v["held"] = held
		if held >= HOLD_TIME:
			continue   # this one has served its time — the grip lets go
		live.append(v)
		# The residual freeze-drift is pinned by easing x back to the catch anchor;
		# gravity keeps owning y, so a rooted body still falls off a ledge it was
		# knocked from. Same treatment ShadowRoot gives its victims.
		var anchor: Vector2 = v["anchor"] as Vector2
		n.global_position.x = lerpf(n.global_position.x, anchor.x, minf(1.0, 14.0 * delta))
		if refresh and held < HOLD_TIME - REAPPLY_CUTOFF and n.has_method("apply_status"):
			n.apply_status(Elements.Element.EARTH)
			n.apply_status(Elements.Element.SHADOW)
		if drain:
			SpellTargets.hurt(n, DRAIN_PER_TICK, Color(_color.r, _color.g, _color.b, 1.0))
			_drained += DRAIN_PER_TICK
			if fed < MAX_HEAL_BODIES:
				fed += 1
	_victims = live
	if drain and fed > 0:
		_feed(fed * HEAL_PER_TICK)


## What the tide gives back. Guarded on `heal` rather than assumed, exactly as
## `DrainTether._heal` is: a caster without the method (a bot rig, a capture stub, a
## headless harness) simply gets nothing instead of erroring mid-ult.
func _feed(amount: int) -> void:
	if amount <= 0 or caster_node == null or not is_instance_valid(caster_node):
		return
	if not caster_node.has_method("heal"):
		return
	caster_node.call("heal", amount)
	_healed += amount


func _release() -> void:
	CombatVfx.spawn_burst(get_parent(), _origin,
		Color(_color.r, _color.g, _color.b, 0.7),
		Color(_color.r * 0.2, _color.g * 0.15, _color.b * 0.35, 0.0),
		22, 0.5, 40.0, 200.0, 1.2, 3.4)
	SpellDrops.sfx("rx_ground_out", -3.0, 0.1, 0.62)
	Juice.shake_camera(6.0)
	queue_free()


# ──────────────────────────────────────────────────────────────────── geometry
## World point `d` px along side `side`'s floor polyline. Clamped at both ends, so a
## caller can hand it the full span without a bounds check.
func _point_at(side: int, d: float) -> Vector2:
	var path: PackedVector2Array = _paths[side]
	if path.size() < 2:
		return _origin
	var left: float = maxf(d, 0.0)
	for i: int in range(1, path.size()):
		var seg: float = path[i - 1].distance_to(path[i])
		if left <= seg or i == path.size() - 1:
			var t: float = clampf(left / maxf(seg, 0.001), 0.0, 1.0)
			return path[i - 1].lerp(path[i], t)
		left -= seg
	return path[path.size() - 1]


# ────────────────────────────────────────────────────────────────────── readout
## How many bodies the tide actually took. Public so a suite can assert the CATCH
## happened — "the cap held" and "nothing was ever caught" are both satisfied by an
## empty result, and only one of them is a passing test.
func caught_count() -> int:
	return _caught_ids.size()


## Total hp drained out of victims, and total hp fed back to the caster. Separate
## numbers on purpose: the heal cap means they are supposed to diverge, and a test
## that only watched one of them could not see the cap work.
func drained_total() -> int:
	return _drained


func healed_total() -> int:
	return _healed


## How far each front has travelled, in px. Read by the suite to prove the tide
## actually moved (and stopped where the geometry said it should).
func front_distances() -> Array[float]:
	return _travelled.duplicate()


func span_totals() -> Array[float]:
	return _spans.duplicate()


func draw_counts() -> Vector2i:
	return Vector2i(_draw_entered, _draw_done)


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


# ───────────────────────────────────────────────────────────────────── picture
## THE WAVE. Drawn in world space along each front's own floor polyline, so the tide
## visibly climbs the step it is actually walking up.
##
## Three layers, in the order they must be read:
##   1. THE CREST — a dense knot of hands at the advancing edge. This is the thing
##      you are dodging, so it is the brightest and the only one drawn at full
##      strength on the cheap picture.
##   2. THE WAKE — thinner hands standing in the floor already crossed, sinking as
##      the effect ends. This is what says the floor is still occupied.
##   3. THE DRAIN THREADS — one line from each held body to the caster. This is the
##      only on-screen statement that the ult is FEEDING him, so it survives LOW.
##
## LOW drops the wake density to a third, the finger count to one, and the near-black
## void fill under the crossed span — never the crest, never the threads.
func _draw() -> void:
	_draw_entered += 1
	var sink: float = 1.0
	var tail: float = _life - SINK_TIME
	if _elapsed > tail:
		sink = clampf(1.0 - (_elapsed - tail) / maxf(SINK_TIME, 0.01), 0.0, 1.0)
	var ink := Color(_color.r, _color.g, _color.b, 0.9 * sink)
	var dark := Color(_color.r * 0.14, _color.g * 0.10, _color.b * 0.22, 0.7 * sink)
	for side: int in _paths.size():
		_draw_side(side, ink, dark, sink)
	# THE DRAIN. Drawn last so the threads sit over the hands.
	for v: Dictionary in _victims:
		var n: Node2D = v["node"] as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var pulse: float = 0.55 + 0.45 * sin(_elapsed * 9.0 + float(n.get_instance_id() % 17))
		draw_line(n.global_position, _origin,
			Color(ink.r, ink.g, ink.b, 0.28 * pulse * sink), 1.6, true)
	_draw_done += 1   # LAST LINE. See _draw_entered.


func _draw_side(side: int, ink: Color, dark: Color, sink: float) -> void:
	var d: float = _travelled[side]
	if d <= 0.5:
		return
	var crest: Vector2 = _point_at(side, d)
	# 1. THE VOID the tide has opened, as a squashed band under the crossed span.
	if not _low:
		var back: Vector2 = _point_at(side, 0.0)
		var poly := PackedVector2Array([
			Vector2(back.x, back.y - 3.0), Vector2(crest.x, crest.y - 3.0),
			Vector2(crest.x, crest.y + 7.0), Vector2(back.x, back.y + 7.0)])
		draw_colored_polygon(poly, dark)
	# 2. THE WAKE.
	var wake: int = WAKE_HANDS_LOW if _low else WAKE_HANDS
	for i: int in wake:
		var f: float = _hash01(_seed + side * 733 + i * 61)
		var at_d: float = f * d
		var p: Vector2 = _point_at(side, at_d)
		# Older hands stand lower and dimmer — the wake settles behind the crest.
		var age: float = clampf(1.0 - (d - at_d) / maxf(d, 1.0), 0.25, 1.0)
		var h: float = (10.0 + 18.0 * _hash01(_seed + i * 97 + side)) * age * sink
		_hand(p + Vector2((_hash01(_seed + i * 13 + side) - 0.5) * 14.0, 0.0), h,
			Color(ink.r, ink.g, ink.b, ink.a * 0.55 * age), _seed + i * 7)
	# 3. THE CREST.
	var n_crest: int = CREST_HANDS_LOW if _low else CREST_HANDS
	for i: int in n_crest:
		var off: float = (float(i) / float(maxi(n_crest - 1, 1)) - 0.5) * 30.0
		var h2: float = (18.0 + 16.0 * _hash01(_seed + i * 311 + side)) * sink
		_hand(crest + Vector2(off, 0.0), h2, ink, _seed + i * 29 + side)
	# The advancing edge itself — a hard line so the front is unmistakable even when
	# the hands are dense.
	draw_line(crest + Vector2(-16.0, 0.0), crest + Vector2(16.0, 0.0),
		Color(ink.r, ink.g, ink.b, ink.a), 2.4, true)


## One hand breaking the surface: a forearm and (on the full picture) three fingers.
func _hand(base: Vector2, height: float, col: Color, salt: int) -> void:
	if height <= 1.0:
		return
	var lean: float = (_hash01(salt) - 0.5) * 0.7
	var wrist: Vector2 = base + Vector2(lean * height * 0.5, -height)
	draw_line(base, wrist, col, 2.0, true)
	var fingers: int = 1 if _low else 3
	for f: int in fingers:
		var a: float = -PI * 0.5 + (float(f) - float(fingers - 1) * 0.5) * 0.6 + lean
		draw_line(wrist, wrist + Vector2.from_angle(a) * (height * 0.4 + 2.0),
			Color(col.r, col.g, col.b, col.a * 0.85), 1.4, true)
