class_name MeteorFist
extends Node2D
## METEOR FIST — the Brawler's ULT. He leaves the floor, comes down fist-first, and
## the ground he lands on stops being ground.
##
## ═══════════════════════════════════════════════════════════════════════════════
## WHY IT EXISTS
## ═══════════════════════════════════════════════════════════════════════════════
## The Brawler's ult was `infernal_lance` — a `BeamSpell`. Five of nine classes threw
## a beam down that same corridor, and this one belonged to the class whose entire
## definition in `Hero.CLASS_CONFIG` is "PURE MELEE, no magic". A screen-crossing
## roaring lance of fire is the single least brawler-shaped thing in the tree. This is
## the replacement: the biggest hit a man can throw is his own body.
##
## ── COMPOSED, NOT REBUILT ─────────────────────────────────────────────────────
## Two pieces of this already existed and are used rather than reimplemented:
##   `BlastSpell`  — the detonation. It owns the radius query, the deflect pass, the
##                   floor-snapped crater, the debris, the scorch, the shockwave
##                   drawing capped at exactly the damage radius, the music duck and
##                   the reaction registration. Configured and fired at the landing
##                   point; this file adds nothing to it and copies none of it.
##   `SlamPhysics` — the BODY's own impact. Called on the caster for a few frames
##                   after touchdown so a Brawler who lands on cover cracks it, which
##                   is a different (and much smaller) event than the shockwave: a
##                   boot-shaped dent inside a crater.
##
## ⚠ AND THE CONSEQUENCE OF COMPOSING `BlastSpell`: **this node does NOT register with
## `SpellReactor`.** The BlastSpell it spawns does, carrying this spell's element,
## weight and caster. Registering here as well would put two entries in the reaction
## table for one detonation and let the impact clash with itself. There is deliberately
## no `reaction_*` block below; that is not an omission.
##
## ═══════════════════════════════════════════════════════════════════════════════
## WHY EARTH AND NOT FIRE
## ═══════════════════════════════════════════════════════════════════════════════
## The brief allowed either "if the fantasy demands". It does not. A flaming meteor is
## a spell, and the whole point of replacing `infernal_lance` is that this class does
## not cast. Nothing here burns: a heavy body arrives and the floor fails. EARTH is
## what the spell is actually made of, it matches `ShockwaveStomp` so the kit reads as
## ONE fighter rather than two, and it opposes LIGHTNING in `ReactionTable.OPPOSED` —
## which is the pleasing inverse of the lightning spell this class just gave up.
##
## (`Hero.CLASS_CONFIG[BRAWLER].melee_element` is FIRE, so his PUNCHES still burn.
## That is the class's fist, not this spell, and the two are allowed to differ — the
## Swordsaint's steel and his arcane spells differ the same way.)
##
## ═══════════════════════════════════════════════════════════════════════════════
## THE TELL AND THE COUNTERPLAY (the locked "everything must be dodgeable" rule)
## ═══════════════════════════════════════════════════════════════════════════════
## TELL — the longest in this workstream, because it is the hardest hit in it.
##   `WINDUP` seconds of a shared `Telegraph` danger ring at the LANDING POINT, drawn
##   at exactly `radius` — the number that damages — before he leaves the floor. Then
##   `LEAP_TIME` more seconds of him visibly in the air above it. Roughly 0.8 s of
##   warning, all of it pointed at one marked circle on the ground.
##   Shared Telegraph, so it joins the `telegraph` group and `BotDodge` can dodge it.
##
## COUNTERPLAY — **leave the circle.** The landing point is committed at the moment of
##   the press and does not track; the ring IS the blast radius, drawn at 1:1. Walking
##   out of a marked circle over 0.8 s is not a reaction test, it is an attention test,
##   which is the correct shape of counterplay for an ult you can see from across the
##   arena. Friendly fire is always on, so this cuts both ways: the ring is also the
##   warning your team-mate gets.
##
## ⚠ THE HONEST COST OF MOVING THE CASTER, stated because nobody has playtested this:
## the leap is walked in vetted sub-steps through `Hero.blink_to`, and every accepted
## move grants `BLINK_IFRAME` (0.22 s). So the Brawler is untouchable for the flight
## plus ~0.22 s. For a body that is genuinely airborne that is defensible, but it is a
## real strength this design did not explicitly buy, and it is the first number to
## look at if the ult feels safe to throw into anything. It cannot be avoided without
## editing Hero: `blink_to` is the only contract that vets a landing spot.
##
## UNPLAYTESTED. Every number below is a reasoned first guess with its rationale.

# ------------------------------------------------------------------- the beats
## THE FIRST DODGE BUDGET: the crouch, with the ring already on the ground. Longer
## than `BlastSpell.WINDUP` (0.55 for an AoE you are meant to stroll out of)? No —
## deliberately a little shorter, because the FLIGHT is the second half of the warning
## and the two together are what a body has to react to.
const WINDUP: float = 0.38
## How long he is in the air. Long enough to read as a leap and to give the ring a
## second beat of "he is coming down HERE"; short enough that the ult does not feel
## like it was cancelled and re-cast.
const LEAP_TIME: float = 0.42
## How long the trail lingers after touchdown. The BlastSpell owns the detonation's
## own timings from there.
const AFTER_GLOW: float = 0.26

## Vetted resting points along the arc.
##
## ⚠ EACH HOP MUST CLEAR `Hero.BLINK_MIN_TRAVEL` (24 px) OR IT IS REFUSED AND THE
## LEAP DOES NOT MOVE. At the shipping reach of 260 px plus the arc height this gives
## hops comfortably above it even for a straight-down dive; `_arc_point` keeps them
## spread by using an eased parameter rather than a linear one, so no two consecutive
## points collapse together at the apex.
const LEAP_STEPS: int = 7
## How high above the straight line between the two ends the arc bulges. This is what
## makes it a LEAP and not a slide — with 0 here the body would skim the floor to the
## landing point and the whole read would be gone.
const ARC_HEIGHT: float = 140.0

## The impact speed handed to `SlamPhysics.check`. Must exceed `MIN_SLAM_SPEED` (250)
## or the slam never fires; sized well above it so the derived damage lands near
## `SlamPhysics.DAMAGE_MAX` — a body arriving from that height should not tickle the
## crate it lands on.
const SLAM_SPEED: float = 640.0
## How many `advance()` calls after touchdown the slam is attempted for.
##
## ⚠ WHY IT IS A WINDOW AND NOT ONE CALL. `SlamPhysics.check` needs
## `get_slide_collision_count() > 0`, and on the frame `blink_to` sets the body down
## it has not run `move_and_slide` yet, so it is touching nothing. The hero falls the
## last pixel and collides a frame or two later. Eight frames is a generous window at
## any tick rate and costs nothing when it is never satisfied — which is exactly what
## happens headless, where the fallback is simply that the body-slam beat does not
## fire and the BlastSpell's own crater is the whole residue.
const SLAM_FRAMES: int = 8

## How deep the ground is looked for under the marked point.
const FLOOR_PROBE: float = 200.0
## How far ABOVE each probe point the floor ray starts. A downward ray that begins
## exactly ON a collider's top surface does not reliably register a hit, and a marked
## point at foot height is exactly that case — so without this the landing silently
## stops snapping to the floor and the pit walk-back never runs. The same trap
## `ShockwaveStomp.PROBE_LIFT` documents at length; it was caught in a rendered frame.
const PROBE_LIFT: float = 24.0
## Terrain samples used to walk the landing point back out of a pit. See `_landing`.
const PATH_SAMPLES: int = 14

# ---------------------------------------------------------------- the picture
## HDR amber-white, > 1.0 so the falling fist blooms through the post grade.
const CORE: Color = Color(1.65, 1.30, 0.75)
const TELL_ACCENT: Color = Color(0.95, 0.16, 0.13, 0.9)
const TRAIL_STEPS: int = 22
const TRAIL_STEPS_LOW: int = 10

# ------------------------------------------------- the stamp (all five, declared)
## ⚠ ALL FIVE, because `set()` on an undeclared property is a SILENT no-op. Note that
## `element_id` and `spell_tier` are not decoration here: they are forwarded onto the
## `BlastSpell` this spell fires, so a missing stamp would produce an elementless,
## middle-weight detonation that `SpellReactor` treats as somebody else's spell.
var target_group: String = "enemy"
var _target_group: String = "enemy"
## EARTH — see WHY EARTH AND NOT FIRE above.
var element_id: int = Elements.Element.EARTH
var spell_tier: int = SpellTier.Tier.ULT
var caster_node: Node = null
## "Something falls onto this spot." Overrides `SpellSigil.MOTIF_BY_SCRIPT`, a table
## this workstream does not own.
var sigil_motif: int = MagicCircle.Motif.DESCENT

var _origin: Vector2 = Vector2.ZERO    ## where he jumped from (world)
var _landing: Vector2 = Vector2.ZERO   ## where the ring is, and where he comes down
var _at: Vector2 = Vector2.ZERO        ## where the body actually is right now
var _color: Color = Color(0.78, 0.55, 0.28, 1.0)
var _damage: int = 120
var _radius: float = 110.0
var _elapsed: float = -1.0             ## < 0 means hex() has not run yet
var _stepped: int = 0
var _landed: bool = false
var _slammed: bool = false
var _slam_tries: int = 0
var _telegraph: Telegraph = null


## Cast entry — the fixed shape every `SpellCaster.HEX_SCRIPTS` entry shares.
## `target` arrives already clamped to the spell's `reach` by the HEX arm.
func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	_origin = origin
	_at = origin
	_color = color
	_damage = maxi(spell.damage, 1)
	_radius = maxf(spell.radius, 30.0)
	_landing = _find_landing(origin, target)
	# The ULT circle, laid FLAT on the ground where he is going to arrive — the
	# loudest object in the frame, which is what `SpellSigil.RADIUS_ULT` is for. Held
	# through the whole flight so the mark is continuous from the press to the impact.
	SpellSigil.open(self, _landing, _color, 1.0, false, Vector2.RIGHT, true, 0.18,
		WINDUP + LEAP_TIME)
	_arm_telegraph()
	CombatVfx.spawn_burst(get_parent(), _origin, Color(0.62, 0.52, 0.40, 0.8),
		Color(0.62, 0.52, 0.40, 0.0), 18, 0.4, 40.0, 130.0, 1.0, 3.0)
	SpellDrops.sfx("charge_ult", -3.0, 0.04, 0.8)
	# Pull the frame back: an ult that changes the floor should be seen whole.
	Juice.zoom_pull_camera(0.22, WINDUP + LEAP_TIME, 0.20, 0.7)
	_elapsed = 0.0
	queue_redraw()


## ⚠ NO `_exit_tree` REACTOR UNREGISTER, because there is no register. See the
## COMPOSED, NOT REBUILT note in the class docs: the `BlastSpell` this spawns is the
## thing that lives in the reaction table, and it manages its own lifetime there.


## Where he actually comes down.
##
## Two corrections, in order:
##   1. SNAP TO THE FLOOR. A marked point in mid-air (aimed up a ledge, or just aimed
##      high) would put the crater in empty space. `SpellWorld.floor_below` answers
##      this, and returns the point UNCHANGED when there is no floor — which is the
##      case the next step exists for.
##   2. NEVER OVER A PIT. `SpellWorld.ground_path` walks the terrain from the caster's
##      feet toward the mark and STOPS at the first x with no floor under it, so its
##      last point is the lip. Landing on the lip rather than in the void is the
##      correct read for a body: he jumps as far as the floor goes.
## With no physics world at all (a headless suite, a bare capture rig) both degrade to
## "the marked point, untouched", which is the right answer on notional flat ground.
##
## The final `blink_to` in `_advance_one` vets this again against the caster's own
## rules, so a point that survives here can still be pulled back by the Hero.
func _find_landing(origin: Vector2, marked: Vector2) -> Vector2:
	var lift := Vector2(0.0, -PROBE_LIFT)
	var ground: Dictionary = SpellWorld.floor_below(marked + lift,
		FLOOR_PROBE + PROBE_LIFT, SpellWorld.rids([caster_node]), self)
	# On a MISS `floor_below` hands back the point it was given — the LIFTED one — so
	# the miss path must fall back to the mark itself rather than to a point in the air.
	var snapped: Vector2 = (ground["position"] as Vector2) if bool(ground["hit"]) else marked
	var path: PackedVector2Array = SpellWorld.ground_path(origin + lift, snapped + lift,
		PATH_SAMPLES, FLOOR_PROBE + PROBE_LIFT, SpellWorld.rids([caster_node]), self)
	if path.size() >= 2:
		return path[path.size() - 1]
	return snapped


func _life() -> float:
	return WINDUP + LEAP_TIME + AFTER_GLOW


## The danger ring, at EXACTLY the blast radius, at the landing point, before he
## moves. ONE CLOCK: its `_process` is off and `advance()` drives it, so the drawn
## promise and the impact cannot drift a frame apart.
func _arm_telegraph() -> void:
	_telegraph = Telegraph.new()
	add_child(_telegraph)
	# ⚠ STAMPED, so `BotController.perceive_threats` can tell whose tell this is.
	# An unstamped hero telegraph is indistinguishable from an enemy one, which
	# makes a bot-driven caster dodge its own spell for the whole wind-up.
	_telegraph.source = caster_node as Node2D
	_telegraph.global_position = _landing
	_telegraph.accent = TELL_ACCENT
	_telegraph.style = Telegraph.Style.ZONE
	_telegraph.set_process(false)
	# The ring counts the WHOLE warning, windup plus flight, so it is still tightening
	# while he is in the air rather than completing before he has left the ground.
	_telegraph.start(_radius, WINDUP + LEAP_TIME)


func _process(delta: float) -> void:
	advance(delta)


## Deterministic time-step, so a headless suite can drive windup -> leap -> impact
## without waiting on real frames.
func advance(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.advance(delta)
	if not _landed and _elapsed > WINDUP:
		# Clock-driven rather than one-hop-per-frame, so the leap takes the same time
		# at 30 fps and at 144.
		var want: int = clampi(
			int(ceil(clampf((_elapsed - WINDUP) / LEAP_TIME, 0.0, 1.0) * float(LEAP_STEPS))),
			0, LEAP_STEPS)
		while _stepped < want and not _landed:
			_advance_one()
	if _landed and not _slammed and _slam_tries < SLAM_FRAMES:
		_slam_tries += 1
		_try_slam()
	if _elapsed >= _life():
		queue_free()
		return
	queue_redraw()


# ------------------------------------------------------------------- the leap
## One hop along the arc, offered to the caster's own landing rules.
func _advance_one() -> void:
	_stepped += 1
	var t: float = float(_stepped) / float(LEAP_STEPS)
	var planned: Vector2 = _arc_point(t)
	_at = _move_caster(planned)
	if _stepped >= LEAP_STEPS:
		_land()


## A point on the dive arc at parameter `t` in [0, 1].
##
## The horizontal component is EASED (t^1.35) rather than linear, so he hangs at the
## top and comes down fast — which is both what a dive looks like and, incidentally,
## what keeps consecutive hops apart near the apex where a linear parameterisation
## would bunch them under `Hero.BLINK_MIN_TRAVEL` and get them refused.
## `sin(t * PI)` is the height bulge: 0 at both ends, `ARC_HEIGHT` in the middle.
func _arc_point(t: float) -> Vector2:
	var flat: Vector2 = _origin.lerp(_landing, pow(clampf(t, 0.0, 1.0), 1.35))
	return flat + Vector2.UP * (ARC_HEIGHT * sin(clampf(t, 0.0, 1.0) * PI))


## Offer `to` to the caster's own landing rules and return where it actually ended up.
##
## ⚠ NEVER A RAW `global_position` WRITE: the caster owns where its body may legally
## rest (geometry, ring-out pits, the room's bounds) and on a co-op peer the position
## belongs to the MultiplayerSynchronizer, which a direct write would fight and lose
## to. `Hero.blink_to` handles both. A caster that declares no `blink_to` is simply not
## moved, and the spell still detonates where it said it would — the damage must not
## depend on whether the thrower opted into being relocated.
func _move_caster(to: Vector2) -> Vector2:
	if caster_node == null or not is_instance_valid(caster_node):
		return to
	if not caster_node.has_method("blink_to"):
		return to
	return caster_node.call("blink_to", to) as Vector2


## Touchdown. The whole payoff is delegated: `BlastSpell` for the shockwave, the
## `SlamPhysics` window for the body's own dent.
func _land() -> void:
	_landed = true
	# ⚠ THE BLAST GOES WHERE THE BODY ACTUALLY IS, not where it was marked. `blink_to`
	# may have pulled the last hop short (a wall, a pit lip, the room's edge), and a
	# crater 40 px from the fist would decouple the explosion from the thing that
	# caused it — the same bug `BlinkStrike.safe_blast_point` exists to prevent.
	var at: Vector2 = _at
	var blast: Node2D = BlastSpell.new()
	get_parent().add_child(blast)
	blast.configure({
		"target_group": target_group,
		"damage": _damage,
		"radius": _radius,
		"knockback": 380.0,
		"element_id": element_id,
		# An ULT is BRUTAL to parry — only the opening sliver of a guard window turns
		# it. BlastSpell defaults to the whole window; the shelf this spell already
		# declares picks the dial rather than this file inventing a second one.
		"deflect_window": SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT
			else SpellDeflect.WINDOW_NORMAL,
	})
	# Not part of `configure`'s dictionary, and both are load-bearing: the caster is
	# the reaction layer's ownership predicate AND the exclude list for the blast's
	# line-of-sight rays, and the weight is what decides every clash it enters.
	blast.caster_node = caster_node
	blast.spell_tier = spell_tier
	# `detonate_now`, not `detonate_at`: the windup and the flight above were the
	# telegraph, and a second Telegraph ring blooming at the moment of impact would be
	# a warning arriving after the hit.
	blast.detonate_now(at)
	Juice.hit_stop(0.12)
	Juice.shake_camera(9.0)   # ON TOP of BlastSpell's own 12.0 — this is the ult beat
	Juice.kick_camera(Vector2.DOWN, 8.0)
	SpellDrops.sfx("ult_eruption", 0.0, 0.05, 0.85)


## The BODY's impact, as distinct from the shockwave's. See `SLAM_FRAMES` for why
## this is attempted over a window rather than once.
##
## `SlamPhysics.check` returns `Vector2.ZERO` when a slam actually fired and the value
## unchanged when it did not, which is exactly the "did it happen yet?" answer this
## needs — no second bookkeeping scheme.
func _try_slam() -> void:
	var body: CharacterBody2D = caster_node as CharacterBody2D
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		_slammed = true   # nothing to slam with — stop asking
		return
	var spent: Vector2 = SlamPhysics.check(body, Vector2.DOWN * SLAM_SPEED)
	if spent == Vector2.ZERO:
		_slammed = true


# ------------------------------------------------------------------ the picture
## The cheap picture (the phone, and the maker's desktop LOW preview). THE RULE:
## thin the garnish, never the read. The ring, the fist and the shadow all survive at
## LOW; the trail resolution and the ember spokes are what go.
func _low() -> bool:
	return TuningConfig.quality_is_low()


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < WINDUP:
		_draw_crouch()
		return
	if not _landed:
		_draw_flight()
		return
	_draw_settle()


## The crouch: the fist gathering over the caster and a shrinking mark on the landing
## ring. Drawn on top of the Telegraph's danger circle — the ring says WHERE, the
## closing chevrons say WHEN.
func _draw_crouch() -> void:
	var t: float = clampf(_elapsed / WINDUP, 0.0, 1.0)
	var above: Vector2 = _origin + Vector2(0.0, -34.0 - 14.0 * t)
	draw_circle(above, 5.0 + 7.0 * t, Color(CORE.r, CORE.g, CORE.b, 0.4 + 0.45 * t),
		true, -1.0, true)
	var spokes: int = 3 if _low() else 5
	for i: int in spokes:
		var a: float = TAU * float(i) / float(spokes) - PI * 0.5
		var d: Vector2 = Vector2.from_angle(a)
		var r: float = _radius * (1.0 - 0.45 * t)
		draw_line(_landing + d * r, _landing + d * maxf(r - 24.0, 6.0),
			Color(_color.r, _color.g, _color.b, 0.30 + 0.45 * t), 2.6, true)


## The flight: the arc already travelled drawn as a thinning comet tail, the fist at
## the body's real position, and a SHADOW on the ground that tightens as he falls.
##
## The shadow is the piece that does the actual work — a falling body against a
## uniform background has no depth cue at all, and the shrinking ellipse is the only
## thing on screen that says how close the impact is.
func _draw_flight() -> void:
	var t: float = clampf((_elapsed - WINDUP) / LEAP_TIME, 0.0, 1.0)
	var steps: int = TRAIL_STEPS_LOW if _low() else TRAIL_STEPS
	var emissive: Color = Elements.emissive(element_id)
	var prev: Vector2 = _arc_point(0.0)
	for i: int in range(1, steps + 1):
		var u: float = t * float(i) / float(steps)
		var p: Vector2 = _arc_point(u)
		var age: float = float(i) / float(steps)   # 1.0 = the head of the comet
		draw_line(prev, p, Color(_color.r, _color.g, _color.b, 0.10 + 0.45 * age),
			1.5 + 5.0 * age, true)
		prev = p
	# ⚠ THE FIST IS DRAWN AT THE BODY'S REAL POSITION, not at `_arc_point(t)`. The two
	# differ by up to one hop (the body only moves at vetted resting points), and on
	# the first render the glowing fist visibly led the figure it was supposed to BE.
	var head: Vector2 = _at
	draw_circle(head, 9.0 + 5.0 * t, Color(CORE.r, CORE.g, CORE.b, 0.9), true, -1.0, true)
	if not _low():
		# Embers streaming UP off the falling fist — the direction states that the
		# thing is going DOWN, which a symmetric glow cannot.
		for i: int in 4:
			var a: float = TAU * float(i) / 4.0 + t * 3.0
			var d: Vector2 = Vector2.from_angle(a)
			draw_line(head + d * 10.0, head + d * 10.0 + Vector2.UP * (10.0 + 14.0 * t),
				Color(emissive.r, emissive.g, emissive.b, 0.5), 1.6, true)
	# The shadow: an ellipse on the landing point, tightening and darkening as he
	# closes. Drawn as an arc rather than a filled disc so it never hides the ring.
	var close: float = t * t
	draw_arc(_landing, _radius * (1.0 - 0.62 * close), 0.0, TAU, 32,
		Color(0.05, 0.04, 0.03, 0.30 + 0.45 * close), 3.0 + 4.0 * close, true)


## After touchdown this node has almost nothing left to say — `BlastSpell` owns the
## detonation's whole picture, and drawing a second shockwave here would be two rings
## racing each other. All that is left is the arc dissolving.
func _draw_settle() -> void:
	var f: float = clampf((_elapsed - WINDUP - LEAP_TIME) / AFTER_GLOW, 0.0, 1.0)
	var alpha: float = (1.0 - f) * 0.35
	if alpha <= 0.0:
		return
	var steps: int = TRAIL_STEPS_LOW if _low() else TRAIL_STEPS
	var prev: Vector2 = _arc_point(0.0)
	for i: int in range(1, steps + 1):
		var p: Vector2 = _arc_point(float(i) / float(steps))
		draw_line(prev, p, Color(_color.r, _color.g, _color.b, alpha), 1.5, true)
		prev = p
