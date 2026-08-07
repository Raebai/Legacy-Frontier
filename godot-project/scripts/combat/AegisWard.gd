class_name AegisWard
extends Node2D
## THE AEGIS WARD — the first PROTECTIVE spell. A standing gate of holy light,
## planted on the ground in front of you, that eats magic aimed through it until
## something big enough breaks it.
##
## Maker's ask: "how a wall defends against a spell, and how there should be some
## protective spells in future."
##
## ---------------------------------------------------------------------------
## WHY THIS AND NOT A SHIELD BUBBLE
##
## A bubble that subtracts damage for N seconds is the easiest defensive spell in
## the world to build and the dullest to play against: the opponent has no read,
## no answer and nothing to decide — they just wait. So this ward is built around
## three properties instead, and each one exists to create a decision:
##
##   1. IT PROTECTS A PLACE, NOT A PERSON. It stands where you planted it and does
##      not follow you. That makes casting it a POSITIONAL commitment — you have
##      chosen a lane to hold and given up the others — and it makes walking round
##      it a real answer rather than a failure of the spell.
##   2. IT VISIBLY WEARS OUT. Three rune plates on its face; each spell it eats
##      takes one. The remaining budget is countable from across the arena, which
##      is the defensive half of the project's dodge-the-tell rule: if every attack
##      must telegraph, every defence must be READABLE, or the defender is the only
##      player in the fight with hidden information.
##   3. THE COUNTER IS "BRING SOMETHING BIGGER", NOT "WAIT". As its plates burn,
##      the ward gets LIGHTER (ULT -> HEAVY -> QUICK), so an ult breaches a
##      half-spent ward and a heavy breaches a nearly-dead one. Nothing about that
##      lives in code: it is `reaction_weight()` plus the three barrier rungs
##      ReactionTable already authored. And a SHADOW spell — the school opposed to
##      this ward's HOLY — pops it outright at any charge, so there is a named
##      elemental answer as well as a brute-force one.
##
## WHAT IT IS NOT, AND WHY: it does not stop bodies, it does not stop melee, it
## does not stop a spell PLACED behind it (a meteor, a divine ray, a pillar), and
## it does not follow you. Every one of those is an opening someone can take.
##
## ---------------------------------------------------------------------------
## HOW IT DIFFERS FROM SigilGuard — this matters, because a protective spell that
## duplicates the caster's free guard has not earned one of only four slots.
##
##   SigilGuard  — TIME. A 0.16 s window you open by hand, at arm's length, facing
##                 where you already look. It is a READ: you predicted the moment.
##                 Free, on a 0.9 s cooldown, and it returns a capped echo.
##   AegisWard   — SPACE. Seconds of standing cover somewhere you are not
##                 necessarily standing, costing MP and a long cooldown and a
##                 loadout slot. It is a PLAN: you predicted the lane.
##
## They also fail differently, which is the honest test of whether both should
## exist. The guard fails when your timing is wrong; the ward fails when your
## positioning is wrong. Neither covers the other's mistake.
##
## ---------------------------------------------------------------------------
## ⚠ IT EATS YOUR OWN SPELLS TOO. `ward_absorb` carries no owner predicate (see
## the row in ReactionTable for the argument). Firing through your own ward burns
## a charge. That is deliberate — without it the ward is planted in front of your
## own face and forgotten, and the positional commitment above evaporates — but it
## is the first thing to re-litigate after an F5.
##
## ⚠ PARKED AT THE ARENA ORIGIN, DRAWN IN WORLD COORDINATES. `global_position` is
## (0, 0) and is NOT where the ward is. The ward is at `_base`, and every drawn
## point, every query and `reaction_shape()` are built from it. See SpellGeometry's
## trap note.
##
## Instantiate .new(), add to the arena, set `caster_node`, then call raise_ward().

## ---------------------------------------------------------------------------
## WARD TUNING. REASONED, NOT FELT — none of this has been playtested. Grouped so
## one pass can retune the whole thing.
## ---------------------------------------------------------------------------

## How far in front of the caster the gate plants. UNTESTED GUESS: a touch past
## RockWall's 90 and IceWall's 90, because this one must not be standing on top of
## you — the whole design is "a place you shoot around", and a ward at melee range
## is a ward you fire into by accident.
const OFFSET: float = 108.0
## Drawn height of the gate, and the length of its reaction capsule. UNTESTED
## GUESS: IceWall's collider is 130 tall and reads as "taller than a fighter";
## matching it means a player who has learned what an ice wall covers already
## knows what this covers.
const HEIGHT: float = 132.0
## Drawn thickness, and the WIDTH of the reaction capsule — one number, two
## consumers, so the picture and the hit test cannot drift apart. UNTESTED GUESS.
const THICKNESS: float = 26.0
## The telegraph. The ward is NOT a reaction participant until it has risen past
## RISE_ACTIVE_FRAC, so there is a real window in which it is visibly coming up and
## not yet doing anything — the defensive mirror of a beam's charge. UNTESTED
## GUESSES.
const RISE_TIME: float = 0.22
const RISE_ACTIVE_FRAC: float = 0.35
## How long it stands once risen, and how long it takes to go once its time is up.
##
## ⚠ 4.0 -> 3.0 WHEN THE WARD ENTERED THE CLERIC'S KIT. This number and the spell's
## cooldown are ONE balance statement, not two, because the protection spec's rules
## (docs/superpowers/specs/2026-07-27-protection-spells.md §6) are both ratios:
## `cooldown >= 2x duration` and `uptime <= 45%`. The ward used to be costed as an
## ULT (11 s cooldown) so that 4.0 s cleared both — but an ult-shelf ward could only
## sit in an ult slot, and no class's ult slot was ever going to be spent on it, so
## the game's only protective spell was equipped by nobody. It is the Cleric's
## CONTROL pick now, which is a non-ult slot, so the cooldown came down to 6.8 s and
## this had to come with it: 3.0 / 6.8 = 44% uptime, 6.8 >= 2 x 3.0. Moving one
## without the other silently breaks a spec rule that nothing else here checks.
const LIFETIME: float = 3.0
const FADE_TIME: float = 0.25
## Rune plates on the face, and therefore spells it can eat. THREE is chosen so the
## weight ladder has one step per plate: 3 = ULT (nothing gets through), 2 = HEAVY
## (an ult breaches), 1 = QUICK (a heavy breaches). Four plates would need a shelf
## that does not exist; two would make the ladder unreadable. UNTESTED GUESS.
const CHARGES: int = 3
## How far down to look for the ground under the plant point.
const FLOOR_PROBE: float = 240.0
## Cadence of the projectile sweep. UNTESTED GUESS: ~16 Hz, fine enough that a
## fast bolt cannot tunnel the 26 px gate at any speed the game throws (the
## fastest thing in the game moves ~540 px/s = 34 px per sweep... which is
## MARGINAL, and the sweep therefore tests the segment a projectile travelled, not
## the point it landed on. See `_screen_projectiles`.)
const SCREEN_INTERVAL: float = 0.06
## Extra forgiveness on the screen test, world px. The gate is thin and a bolt
## clipping its edge should die on it. Bounded well inside the drawn thickness
## plus this, which is what `screens_point` asserts. UNTESTED GUESS.
const SCREEN_PAD: float = 8.0
## The shatter beat: a ring flash at this radius, then gone. It is drawn to exactly
## the radius it damages, the same contract IceWall.SHATTER_RADIUS documents.
const SHATTER_TIME: float = 0.28
const SHATTER_RADIUS: float = 110.0
const SHATTER_DAMAGE: int = 16
const SHATTER_KNOCKBACK: float = 240.0

const GOLD_FILL: Color = Color(1.0, 0.93, 0.6)
const GOLD_EDGE: Color = Color(1.7, 1.5, 0.95)     # HDR: blooms under the glow pass
const GOLD_RUNE: Color = Color(1.9, 1.7, 1.1)
const SPENT_RUNE: Color = Color(0.45, 0.4, 0.32)

## Elemental identity. HOLY is what makes the ward findable in ReactionTable
## (no other barrier carries it) and what gives it a named counter (SHADOW).
## WHO THIS SPELL MAY HURT. Stamped by SpellCaster._stamp() at cast time, so it
## follows the CASTER's faction rather than being fixed at "enemy" forever.
##
## Every spectacle used to scan the literal group "enemy", which is why a
## hero-shaped bot's spells passed harmlessly through another hero: the aim was
## right, the spectacle spawned and drew, and then it queried a group its target
## was not in. Nothing errored — the spell simply never hit anything, which reads
## as a physics bug rather than a targeting one.
##
## Defaults to "enemy", so every existing caster, capture tool and test is
## byte-identical and single player does not change by one branch.
var target_group: String = "enemy"
var element_id: int = Elements.Element.HOLY
## Who raised it. Set by the caster before raise_ward(), same as BeamSpell's.
var caster_node: Node = null
## The shelf the stamp says this ward sits on. Distinct from `reaction_weight()`,
## which degrades with the ward's remaining charges — this is the spell's SHELF and
## it never changes, so it is what the summoning sigil draws from. Declared because
## `set()` on an undeclared property is a silent no-op and the stamp was going
## nowhere.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## The ward's foot, in WORLD space. Everything is built from this.
var _base: Vector2 = Vector2.ZERO
var _colour: Color = GOLD_FILL
var _elapsed: float = -1.0     # < 0 = not raised
var _charges: int = CHARGES
var _screen_t: float = 0.0
## Flash on the frame a charge burns, decaying — the "it just took one" tell.
var _flash: float = 0.0
var _shattered: bool = false
var _shatter_elapsed: float = -1.0
## Set when a reaction spent us, so the shatter skips its own AoE: the reaction
## already paid out, and a ward that also detonated would double-dip.
var _spent_by_reaction: bool = false


## Public entry. Plants the gate on the ground `OFFSET` px along `aim` from
## `from`. Refuses illegal ground and fizzles — see `_fizzle`.
func raise_ward(from: Vector2, aim: Vector2, colour: Color = GOLD_FILL,
		_effect: String = "holy") -> void:
	_colour = colour
	var want: Vector2 = plant_point(from, aim, OFFSET)
	var skip: Array[RID] = SpellWorld.rids([caster_node])
	# ── "NOTHING MAY SIT INSIDE OR BELOW TERRAIN" ──────────────────────────────
	# Two separate questions, and both have to be asked. floor_below answers "is
	# there ground here at all" — over a pit it reports no hit and hands the point
	# back unchanged, which is exactly the case where a ward would otherwise hang
	# in the void. is_blocked then answers "is the gate's own volume inside rock",
	# probed at the MIDDLE of the gate rather than at its foot, because its foot is
	# standing on the floor collider by construction and would report blocked every
	# single time.
	var ground: Dictionary = SpellWorld.floor_below(want, FLOOR_PROBE, skip, self)
	if not bool(ground["hit"]):
		_fizzle(want)
		return
	_base = ground["position"] as Vector2
	if SpellWorld.is_blocked(_base - Vector2(0.0, HEIGHT * 0.5), THICKNESS * 0.5,
			skip, self):
		_fizzle(_base)
		return
	global_position = Vector2.ZERO   # we draw in world space from _base
	_elapsed = 0.0
	add_to_group("ward")   # so a future dispel / bot-perception pass can find one
	CombatVfx.spawn_burst(get_parent(), _base, Color(1.0, 0.97, 0.8, 0.9),
		Color(0.9, 0.8, 0.4, 0.0), 20, 0.5, 40.0, 150.0, 0.8, 2.4, 0.0, 0.0, true,
		Vector2.UP, 40.0)
	# The consecration mark the gate stands up out of. A ward is the most PLACED
	# spell in the game — the whole point is that it occupies a spot — so the flat
	# ground sigil is doing real work here, not decoration: it is where the ward is.
	SpellSigil.open(self, _base, colour, 1.0, false, Vector2.RIGHT, true, 0.14, 0.7)
	Sfx.play("ward_raise", -2.0, 0.04)
	# Join the reaction system NOW, during the rise. reaction_active() keeps the
	# ward inert until it has actually come up, exactly as a beam registers during
	# its charge — so the telegraph is honest without needing a second registration.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.BARRIER, element_id)
	queue_redraw()


## Nowhere legal to stand it up: a puff of light where the player aimed, and gone.
## LOUD ENOUGH TO READ, deliberately — a spell that silently does nothing is
## indistinguishable from a spell that did not cast, and the player needs to learn
## "not over a pit" rather than "sometimes it doesn't work".
func _fizzle(at: Vector2) -> void:
	CombatVfx.spawn_burst(get_parent(), at, Color(1.0, 0.95, 0.75, 0.8),
		Color(0.8, 0.7, 0.35, 0.0), 12, 0.35, 30.0, 110.0, 0.8, 2.0, 0.0, 0.0, true)
	queue_free()


# ------------------------------------------------------------ pure geometry
# Static and side-effect free so the reach contract is provable headlessly —
# both the positive case and, far more importantly, the just-outside NEGATIVE one.

## Where the gate plants, relative to caster and aim.
static func plant_point(from: Vector2, aim: Vector2, offset: float = OFFSET) -> Vector2:
	var d: Vector2 = aim.normalized()
	if d == Vector2.ZERO:
		d = Vector2.RIGHT
	return from + d * offset


## THE ONE CONTAINMENT TEST. Is world point `p` inside the standing gate?
##
## `height01` is how far the gate has risen (0..1), so the screen can never reach
## higher than the gate is DRAWN — a ward that ate bolts through a metre of air it
## had not grown into yet would be "the spell getting out of the radius" in its
## most literal form. `_draw` builds the pane from the same two numbers.
static func screens_point(base: Vector2, height01: float, p: Vector2) -> bool:
	var h: float = HEIGHT * clampf(height01, 0.0, 1.0)
	if h <= 0.0:
		return false
	if absf(p.x - base.x) > THICKNESS * 0.5 + SCREEN_PAD:
		return false
	return p.y <= base.y + SCREEN_PAD and p.y >= base.y - h - SCREEN_PAD


## Is `p` caught in the ward's death flash? Same radius the ring is drawn to.
static func shatter_contains(base: Vector2, p: Vector2) -> bool:
	return (base - Vector2(0.0, HEIGHT * 0.5)).distance_to(p) <= SHATTER_RADIUS


## THE DEGRADATION LADDER, and the whole balance knob for this spell.
##
## Weight is not a hitpoint pool and is not invented here — it is SpellTier's
## QUICK/HEAVY/ULT shelf, the same axis a spell's cast time and cooldown already
## put it on. So "how much can this ward stop" and "how big a spell is this" are
## measured in ONE currency, and the answer to a ward is legible: bring something
## from a heavier shelf than it currently sits on.
##
##   3 plates -> ULT    nothing outweighs it; everything is eaten
##   2 plates -> HEAVY  an ULT now breaches it and carries on
##   1 plate  -> QUICK  a HEAVY breaches it too
##   0 plates -> it is already gone
##
## Static and pure so the ladder is a table a test reads, not behaviour a test has
## to stage a fight to observe.
static func weight_for_charges(charges: int) -> int:
	if charges >= CHARGES:
		return SpellTier.Tier.ULT
	if charges >= 2:
		return SpellTier.Tier.HEAVY
	return SpellTier.Tier.QUICK


## 0..1 of the gate's drawn height right now.
func rise01() -> float:
	if _elapsed < 0.0:
		return 0.0
	return clampf(_elapsed / RISE_TIME, 0.0, 1.0)


func charges() -> int:
	return _charges


func base_point() -> Vector2:
	return _base


# --- reaction contract (see SpellReactor) -----------------------------------

## World-space geometry, built from `_base` — never from global_position, which is
## (0, 0). The capsule runs UP from the foot to the top of the DRAWN pane and is
## exactly THICKNESS wide, so what reacts is what is on screen.
func reaction_shape() -> Dictionary:
	var top: Vector2 = _base - Vector2(0.0, HEIGHT * rise01())
	return SpellGeometry.capsule(_base, top, THICKNESS)


## LOAD-BEARING. False while the gate is still coming up (a real, if short,
## telegraph — you can throw a spell through the space before it closes) and false
## once it has shattered or begun fading out, so a spent ward cannot eat one last
## beam on its way off screen. Same reasoning as ZoneSpell's.
func reaction_active() -> bool:
	if _elapsed < 0.0 or _shattered or _charges <= 0:
		return false
	if rise01() < RISE_ACTIVE_FRAC:
		return false
	return _elapsed < RISE_TIME + LIFETIME


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.BARRIER


func reaction_owner() -> Node:
	return caster_node


## POLLED EVERY TICK by SpellReactor — which is the only reason the degradation
## ladder above can be behaviour at all. See weight_for_charges().
func reaction_weight() -> int:
	return weight_for_charges(_charges)


## Spent by a reaction (a shadow spell popped it, or something heavier breached
## it). Die WITHOUT the normal end-of-life payout: the reaction has already staged
## its own burst and paid its own damage, and a ward that detonated on top of that
## would double-dip.
func reaction_consume() -> void:
	_spent_by_reaction = true
	shatter()


## A reaction ATE a spell on our behalf and we paid for it in a plate.
## Called by ReactionOutcomes._ward_absorb; duck-typed, so a ward that never
## implemented it would simply be indestructible — which is what the suite's
## charge assertions exist to catch.
func reaction_absorb(at: Vector2) -> void:
	if _charges <= 0 or _shattered:
		return
	_charges -= 1
	_flash = 1.0
	# ══ IT HAS TO BE OBVIOUS THAT IT JUST ATE SOMETHING ════════════════════════
	# Maker: *"aegic ward no idea what it does so it needs improvement"*.
	#
	# The ward already counted its plates and already burst particles here, and it
	# still read as nothing — because a particle puff is what EVERYTHING in this game
	# does, and because the pane itself is deliberately translucent (you have to see
	# the fight through your own cover). So the one moment that explains the entire
	# spell — a spell hits the gate and DIES — went by at the same volume as a crate
	# breaking.
	#
	# A deflect-weight beat instead: the freeze that says "that mattered", a ring
	# expanding off the point of impact, and the ding the parry uses. Deliberately
	# borrowed from `SpellDeflect` rather than invented — a ward eating a spell and a
	# guard turning one away are the same event to a player, and they should sound
	# like it.
	CombatVfx.spawn_burst(get_parent(), at, Color(1.6, 1.5, 1.1, 1.0),
		Color(0.9, 0.8, 0.4, 0.0), 30, 0.42, 90.0, 300.0, 1.0, 3.0, 0.0, 0.0, true)
	Sfx.play("ding", 1.0, 0.02)
	Juice.hit_stop(0.10)
	Juice.frame({"style": ImpactFrame.Style.LOCAL, "strength": 0.62, "at": at})
	if _charges <= 0:
		# The last plate went. The gate falls on the very hit that broke it, which
		# is the moment the whole "countable budget" read pays off.
		shatter()
	queue_redraw()


# ------------------------------------------------------------------ lifetime

## The ward's one way to die — expiry, a reaction, or the last plate burning.
## Idempotent, so a reaction and natural expiry can race safely.
func shatter() -> void:
	if _shattered or _elapsed < 0.0:
		return
	_shattered = true
	_shatter_elapsed = 0.0
	_charges = 0
	remove_from_group("ward")
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)
	var centre: Vector2 = _base - Vector2(0.0, HEIGHT * 0.5)
	CombatVfx.spawn_burst(get_parent(), centre, Color(1.9, 1.7, 1.2, 0.95),
		Color(1.0, 0.85, 0.45, 0.0), 30, 0.45, 90.0, 280.0, 0.8, 2.4, 0.0, 0.0, true)
	if not _spent_by_reaction:
		# A ward that ran out of TIME still goes off — a shield collapsing is a
		# beat, not a fade. A ward spent by a reaction skips this because the
		# reaction has already paid.
		_shatter_aoe(centre)
	Juice.shake_camera(6.0)
	# A SHIELD COLLAPSING is a beat, not a fade — and it is one of the reaction
	# payoffs the maker specifically wants punctuated. The HOLY colour field is
	# the right mark: the screen floods gold for a moment, which reads as the
	# ward giving itself up, where a white blow-out would read as an explosion.
	# Camera + freeze suppressed; the shake above is this spell's own weight.
	Juice.tier_frame(SpellTier.Tier.HEAVY, centre, element_id,
		{"style": ImpactFrame.Style.COLOR_FIELD,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	Sfx.play("ward_absorb", -2.0, 0.02)
	queue_redraw()


## The collapse AoE. Drawn ring and damaged ring are the SAME radius, and cover is
## respected — the reach contract in both of its forms.
func _shatter_aoe(centre: Vector2) -> void:
	var in_range: Array = []
	# hostiles(), not a bare group scan: under friendly fire the scanned group
	# contains the ward's own caster, who is inside this ring by construction.
	for e: Node in SpellTargets.hostiles(self, target_group):
		if e is Node2D and is_instance_valid(e) \
				and shatter_contains(_base, (e as Node2D).global_position):
			in_range.append(e)
	for e: Node in SpellWorld.filter_reachable(centre, in_range, [], self):
		if e.has_method("take_damage"):
			e.call("take_damage", SHATTER_DAMAGE)
		if e.has_method("apply_knockback"):
			var away: Vector2 = ((e as Node2D).global_position - centre).normalized()
			e.call("apply_knockback", (away if away != Vector2.ZERO else Vector2.UP)
				* SHATTER_KNOCKBACK)
	# The collapse takes the scenery with it too — same ring, via the same predicate
	# the fighter pass uses, so cover cannot be broken from outside the drawn circle.
	SpellSurfaces.in_shape(self, centre, SHATTER_DAMAGE,
		func(p: Vector2) -> bool: return shatter_contains(_base, p))


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if _shattered:
		_shatter_elapsed += delta
		if _shatter_elapsed >= SHATTER_TIME:
			queue_free()
			return
		queue_redraw()
		return
	_elapsed += delta
	_screen_t -= delta
	if _screen_t <= 0.0:
		_screen_t = SCREEN_INTERVAL
		_screen_projectiles()
	if _elapsed >= RISE_TIME + LIFETIME:
		shatter()
		return
	queue_redraw()


## Eat enemy bolts that fly into the gate.
##
## ⚠ `enemy_projectile` ONLY, HARD-CODED, NEVER CONFIGURABLE. A ward that ate an
## ally's bolts would be the single most infuriating object in the game, and the
## way that ships is by someone making the group a parameter "for flexibility".
##
## Screening does NOT burn a plate. The plates are the ward's budget against
## SPELLS — the thing the reaction layer weighs — and letting a machine-gunning
## boss strip a 4-second ward in half a second of chip fire would make the whole
## degradation ladder unreadable. The cost of screening is that the ward is a
## 26 px pane in one place, which you have to be standing behind.
func _screen_projectiles() -> void:
	if _charges <= 0 or _shattered:
		return
	var h: float = rise01()
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		var p2: Node2D = proj as Node2D
		if p2 == null or not is_instance_valid(p2) or proj.is_queued_for_deletion():
			continue
		if not screens_point(_base, h, p2.global_position):
			continue
		if proj.has_method("consume"):
			proj.call("consume")
			CombatVfx.spawn_burst(get_parent(), p2.global_position,
				Color(1.0, 0.97, 0.8, 0.9), Color(0.9, 0.8, 0.4, 0.0),
				10, 0.3, 50.0, 150.0, 0.7, 2.0, 0.0, 0.0, true)


# -------------------------------------------------------------------- drawing

func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _shattered:
		_draw_collapse()
		return
	var h01: float = rise01()
	var h: float = HEIGHT * h01
	if h <= 1.0:
		return
	# Fade out over the last FADE_TIME so the ward visibly runs down rather than
	# blinking off.
	var left: float = (RISE_TIME + LIFETIME) - _elapsed
	var alpha: float = clampf(left / FADE_TIME, 0.0, 1.0)
	var top: Vector2 = _base - Vector2(0.0, h)
	var half: float = THICKNESS * 0.5
	var bulge: float = 1.0 + 0.35 * _flash
	# The ground sigil the gate stands on — the first thing that appears, so the
	# rise reads as something being summoned rather than a rectangle growing.
	#
	# ⚠ A HALF-DISC, NOT A CIRCLE, AND THAT IS NOT A STYLE CHOICE. The first render
	# of this used draw_circle and put a large glowing disc straight THROUGH the
	# floor it was standing on — visible in the capture as a bead sunk into the
	# ground. "Nothing may sit inside or below terrain" is a drawing rule as much
	# as a damage rule, and a filled circle centred on a floor point breaks it by
	# construction. Godot has no filled arc, so the upper half is built by hand.
	_draw_ground_sigil(THICKNESS * 1.5, bulge, alpha)
	# THE PANE. Deliberately translucent: you have to be able to see the fight
	# through your own cover, or the ward hides the very thing it is protecting you
	# from. Read through, not read over.
	# ⚠ ALPHAS RAISED, AND THE "read through, not read over" RULE IS UNCHANGED. At
	# 0.13 / 0.17 / 0.22 the pane was see-through to the point of being unnoticeable —
	# the maker's *"no idea what it does"* is partly just this. Roughly doubled, which
	# is still well under half opacity: you can read the fight through it, you simply
	# cannot miss that it is there.
	draw_line(_base, top, Color(GOLD_FILL.r, GOLD_FILL.g, GOLD_FILL.b, 0.24 * alpha),
		THICKNESS * 1.9 * bulge, true)
	draw_line(_base, top, Color(GOLD_FILL.r, GOLD_FILL.g, GOLD_FILL.b, 0.32 * alpha),
		THICKNESS * bulge, true)
	draw_line(_base, top, Color(GOLD_EDGE.r, GOLD_EDGE.g, GOLD_EDGE.b, 0.42 * alpha),
		THICKNESS * 0.35, true)
	# HDR rails down each edge — the gate's outline is where the brightness lives,
	# so it stays legible at phone scale even when the fill is nearly invisible.
	var rail: Color = Color(GOLD_EDGE.r, GOLD_EDGE.g, GOLD_EDGE.b, 0.9 * alpha)
	draw_line(_base + Vector2(-half, 0.0), top + Vector2(-half, 0.0), rail, 1.8, true)
	draw_line(_base + Vector2(half, 0.0), top + Vector2(half, 0.0), rail, 1.8, true)
	draw_line(top + Vector2(-half, 0.0), top + Vector2(half, 0.0), rail, 1.8, true)
	_draw_plates(h, alpha)
	# A scan of light climbing the pane — motion, so a standing ward is never a
	# still image, and a slow one so it does not compete with the plates for the eye.
	var scan: float = fposmod(_elapsed * 0.55, 1.0)
	var sy: Vector2 = _base - Vector2(0.0, h * scan)
	draw_line(sy + Vector2(-half, 0.0), sy + Vector2(half, 0.0),
		Color(1.0, 1.0, 1.0, 0.35 * alpha * sin(scan * PI)), 2.4, true)


## The sigil the gate stands on, drawn as the UPPER HALF of a disc so not one
## pixel of it falls below the floor it is planted on. See the warning at the call
## site — the circle version of this shipped a glowing bead buried in the ground.
func _draw_ground_sigil(radius: float, bulge: float, alpha: float) -> void:
	var r: float = radius * bulge
	var fan := PackedVector2Array()
	fan.append(_base)
	for i: int in 17:
		# PI -> TAU is the half ABOVE the base in Godot's y-down space.
		fan.append(_base + Vector2.from_angle(lerpf(PI, TAU, float(i) / 16.0)) * r)
	draw_colored_polygon(fan, Color(GOLD_FILL.r, GOLD_FILL.g, GOLD_FILL.b, 0.10 * alpha))
	draw_arc(_base, r, PI, TAU, 22,
		Color(GOLD_EDGE.r, GOLD_EDGE.g, GOLD_EDGE.b, 0.55 * alpha), 1.6, true)


## THE BUDGET, MADE COUNTABLE. One plate per charge, spaced up the pane: lit while
## the charge is there, a dead grey outline once it has been spent. This is the
## whole of the "every defence must be readable" rule for this spell — an opponent
## across the arena can see how much is left and decide whether to commit.
func _draw_plates(h: float, alpha: float) -> void:
	var w: float = THICKNESS * 0.34
	for i: int in CHARGES:
		# Bottom plate burns LAST, so the ward visibly empties from the top down and
		# the survivor is always the one nearest the ground sigil.
		#
		# The band runs 0.30..0.88 rather than the obvious (i + 0.5)/CHARGES, which
		# put the lowest plate inside the ground sigil's glare — and since that is
		# the plate that survives longest, the ONE reading the player needs most
		# (how much is left) was the one competing with the brightest thing on the
		# ward. Found by looking at the capture, not by reasoning.
		var t: float = lerpf(0.30, 0.88, float(i) / maxf(float(CHARGES - 1), 1.0))
		var c: Vector2 = _base - Vector2(0.0, h * t)
		var spent: bool = i >= _charges
		var col: Color = SPENT_RUNE if spent else GOLD_RUNE
		var a: float = (0.35 if spent else 0.95) * alpha
		# A diamond, not a dot: it reads as an inscribed rune at 46 px on a phone,
		# where a circle just reads as a bead of light.
		var pts := PackedVector2Array([
			c + Vector2(0.0, -w), c + Vector2(w, 0.0),
			c + Vector2(0.0, w), c + Vector2(-w, 0.0),
		])
		if spent:
			# Broken: outline plus a crack, so a spent plate is visibly DAMAGED
			# rather than merely dim. Dim alone is indistinguishable from distance.
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col.r, col.g, col.b, a),
				1.2, true)
			draw_line(c + Vector2(-w * 0.8, -w * 0.5), c + Vector2(w * 0.8, w * 0.5),
				Color(col.r, col.g, col.b, a * 0.8), 1.0, true)
			continue
		var pulse: float = 0.82 + 0.18 * sin(_elapsed * 5.0 + float(i) * 1.4)
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, a * pulse))
		draw_polyline(pts + PackedVector2Array([pts[0]]),
			Color(1.9, 1.8, 1.4, a), 1.2, true)


## The collapse: a ring expanding to exactly SHATTER_RADIUS — the ring you see is
## the ring that hurt — plus the pane breaking into falling shards of light.
func _draw_collapse() -> void:
	var t: float = clampf(_shatter_elapsed / SHATTER_TIME, 0.0, 1.0)
	if t >= 1.0:
		return
	var a: float = 1.0 - t
	var centre: Vector2 = _base - Vector2(0.0, HEIGHT * 0.5)
	var r: float = lerpf(14.0, SHATTER_RADIUS, 1.0 - (1.0 - t) * (1.0 - t))
	draw_arc(centre, r, 0.0, TAU, 40, Color(GOLD_EDGE.r, GOLD_EDGE.g, GOLD_EDGE.b, 0.9 * a),
		lerpf(6.0, 1.0, t), true)
	for k: int in 5:
		var ang: float = TAU * float(k) / 5.0 + 0.3
		var d: Vector2 = Vector2.from_angle(ang)
		draw_line(centre + d * r * 0.5, centre + d * r * 0.92,
			Color(GOLD_RUNE.r, GOLD_RUNE.g, GOLD_RUNE.b, 0.6 * a), 1.4, true)
	if t < 0.4:
		var flash: float = 1.0 - t / 0.4
		draw_circle(centre, 34.0 * flash, Color(1.9, 1.75, 1.3, 0.45 * flash),
			true, -1.0, true)
