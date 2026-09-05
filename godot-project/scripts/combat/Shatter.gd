class_name Shatter
extends Node2D
## SHATTER — the Cryomancer's damage signature, and the second half of the only
## two-button combo in the game.
##
## It replaces `frostpiercer`, which was a BeamSpell — one of FIVE classes that
## all threw the same beam down the same damage corridor. The maker's ruling was
## "we cannot have any recolours", and the answer for this class was not a
## different-looking beam but a different QUESTION: the Cryomancer already owns
## the only spell in the game that takes a body off the board (Blizzard's
## rime -> encase -> shatter fuse). Nothing consumed that state. Now something does.
##
## ── THE WHOLE IDENTITY: FREEZE, THEN BREAK ───────────────────────────────────
## The mark RIMES what is standing in it when it lands (`_rime`), so a clean hit is
## an ordinary hit and the spell arms its own middle rung. Cast at a body that walks
## in late, or one that is already leaving, and it is a weak thump. Cast on a body
## that is ENCASED, or frozen by any other means, it detonates the casing:
## triple damage on that body, and the flying casing shards splash everything
## standing near it. Freezing a crowd and then breaking all of them at once is the
## Cryomancer's payoff and nobody else in the roster can express it.
##
##   WARM   x `WARM_MULT`   (0.35)
##   RIMED  x `RIMED_MULT`  (1.00)  — chilled, or carrying a live rime meter
##   FROZEN x `FROZEN_MULT` (3.00)  — frozen/staggered, or encased by a Blizzard
##
## ⚠ IT APPLIES NO ICE TO AN ALREADY-COLD BODY, and that is a rule rather than an
## oversight. `StatusComponent.apply(ICE)` on an already-chilled body FREEZES it,
## so a spell that re-applied ice on every hit would rebuild exactly the
## chill->freeze->chill stunlock that Blizzard's rework was written to delete
## ("ice is not fair"). Shatter CONSUMES cold; only a warm target is chilled, and
## that is the spell setting up its own next cast.
##
## ── THE TELL AND THE COUNTERPLAY (the locked "everything is dodgeable" rule) ──
##   TELL         A cryo-mark snaps flat onto the ground at the aimed point and a
##                fracture lattice etches outward across the full blast radius for
##                `FUSE` seconds. Anything already frozen inside it visibly
##                crazes. The footprint drawn IS the footprint that bites.
##   COUNTERPLAY  Two, at different timescales. Immediately: the fuse plus a small
##                fixed radius — step off the mark. Structurally: do not be
##                frozen. The whole spell is a conditional, and leaving the
##                Blizzard before the rime meter fills turns a 3x detonation into
##                a 0.35x tap. That second one is the real counterplay, and it is
##                readable a second and a half before this spell is even cast.
##
## ⚠ ELEMENT IS DECLARED, NEVER INFERRED — see the same note on `RadiantVolley`.
## ICE here, so the mark opposes FIRE in the reaction table rather than guessing.
##
## ── THE THROW, AND WHY IT EXISTS (maker: "the cast, you can't see the projectile,
##    I'm unsure if it even sends one out") ──────────────────────────────────────
## He was right, and not about a colour: NOTHING WAS EVER SENT. This spell placed
## its mark at the aim point instantly and discarded the `origin` argument the HEX
## arm hands it, so the entire cast was a thin pale-cyan ring appearing 300 px away
## with no line of causation back to the hand that cast it. Every other damage hand
## in the roster puts something in the air.
##
## So the charge is now THROWN, and the flight is timed to be exactly the fuse —
## `_shard_at()` is `_from -> _at` over `FUSE` seconds. That is deliberate and it is
## the reason this is a visibility fix rather than a balance one:
##   * the footprint ring still snaps to full radius on the cast frame, so the
##     telegraph and its warning window are UNCHANGED (thinning or delaying a
##     telegraph is a fairness change; this is not one),
##   * the break still lands at `FUSE`, so no damage moved in time,
##   * and the projectile IS the fuse timer — the thing you watch to know when it
##     goes off is the thing flying at the mark. One read, not two.
##
## ── MAKING THE CONDITIONAL VISIBLE (the other half of "not as damaging") ──────
## The 0.35 / 1.0 / 3.0 ladder was already in the code and already enormous at the
## top (see the arithmetic on `FROZEN_MULT`). What the player could not do was TELL
## WHICH ONE HE WAS ABOUT TO GET, so a correct 0.35x tap on a warm body read as the
## spell being weak rather than as him having skipped its set-up.
##
## The fuse therefore SCANS its own footprint and states the answer:
##   WARM    thin, small, pale — a mark that visibly is not going to do anything
##   PRIMED  the ring thickens and warms; the rime is taking
##   ARMED   the whole mark goes hot white, a counter-ring spins up, and a lattice
##           tether snaps from the mark to EVERY frozen body it has claimed, each
##           wearing a crazing casing. Plus its own sound. You know, seventeen
##           frames early, that this one is the 3x.
## The break then branches to match: a warm break is a tap, an armed break is a
## white-out with casing fans off every body that came apart.
##
## ⚠ NO DAMAGE NUMBER MOVED. See the note on `FROZEN_MULT`.

# ------------------------------------------------------------------- IDENTITY
## Stamped by `SpellCaster._stamp()`. All five DECLARED, because `set()` on an
## undeclared property is a silent no-op and an un-stamped spectacle is inert in
## the entire reaction system without erroring once.
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.ICE
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## PULSE — a ring leaves this centre. Stated here because `SpellSigil`'s
## script-keyed motif table lives in a file this agent does not own; the
## `sigil_motif` override is the sanctioned route (`SpellSigil._motif_of`).
var sigil_motif: int = MagicCircle.Motif.PULSE

# --------------------------------------------------------------- THE CONDITION
## How cold a body is when the casing breaks. The ONE axis this spell reads.
enum Cold { WARM, RIMED, FROZEN }

## ⚠ THESE THREE NUMBERS ARE THE SPELL. Named constants rather than inline
## literals precisely so the combo can be tuned (and tested) as a ratio.
## Weak enough on a warm target that opening with it is a mistake.
const WARM_MULT: float = 0.35
## Ordinary against a chilled/riming body — the mid rung exists so the fuse has a
## meaningful middle rather than a cliff.
const RIMED_MULT: float = 1.0
## The payoff. 3x is the reason to spend a second and a half holding someone in a
## Blizzard, and it is why this class's control slot is not filler.
##
## ⚠ DO NOT RAISE THIS, OR THE BASE, TO ANSWER "ice isn't damaging". The arithmetic
## already answers it: base 62 x 3.0 = 186 on one body, plus 22 of casing splash on
## every neighbour. The heaviest ULT in the game is Heaven's Wrath at 130 across
## five separate strikes; Fault Line is 105 and this class's own ult is 48 a spike.
## A landed armed Shatter is therefore already the single biggest hit in the roster
## and it is on a 4 s cooldown on the DAMAGE slot. The complaint was never that this
## number is small — it is that the player could not see which rung he was on, and
## the warm rung (62 x 0.35 = 22) is the one he kept landing. Fixing the read is the
## fix. Inflating a number that is already top-of-roster, into a build where hero HP
## just went up 1.4x and enemy damage is coming down, would be a second bug.
const FROZEN_MULT: float = 3.0
## Rime-meter fraction at or above which a body counts as RIMED. Below this the
## frost has barely started and calling it cold would make the fuse meaningless.
const RIME_MIN: float = 0.15

## Casing shards from a FROZEN break splash everything near that body, once each.
## The crowd payoff: freeze a cluster, break one, the rest wear the debris.
const SHARD_DAMAGE_FRAC: float = 0.35
const SHARD_RADIUS: float = 96.0

## The tell window. Short — this is a combo finisher, not a bombardment — but a
## real one: at 60 fps it is seventeen frames of warning.
const FUSE: float = 0.28
## How long the break stays on screen after it bites.
const BURST_LIFE: float = 0.40
## Outward shove, scaled by how cold the victim was: a warm body is nudged, a
## casing bursting is a real hit.
const KNOCKBACK: float = 240.0
const DEFAULT_RADIUS: float = 104.0
## Blades of the fracture lattice drawn during the fuse, and the cheap count that
## ships to the phone.
const FRACTURES: int = 14
const FRACTURES_LOW: int = 7

# ------------------------------------------------------------------- THE THROW
## Half-height of the shard's arc, as a fraction of the distance thrown. A dead
## straight line between two points on a flattened floor reads as a static streak;
## a shallow lob reads as an object with weight travelling THROUGH the scene.
const ARC_RISE: float = 0.22
## Ghosts trailed behind the shard, and the phone's count. The trail is what makes
## a 0.28 s flight legible at all — at 1070 px/s a single quad is four smeared
## pixels, and "I can't see the projectile" is exactly what four smeared pixels look
## like. The ghosts are the thing the eye actually catches.
const TRAIL: int = 7
const TRAIL_LOW: int = 3
## Length of the shard's body, before the flight's own stretch.
const SHARD_LEN: float = 26.0

# --------------------------------------------------------- READING THE CONDITION
## How often the fuse re-asks its own footprint how cold it is. Not every frame:
## the answer is drawn, not damaged with, and a body that walks in at the last
## instant is caught by `_break`'s own query regardless. 0.05 s is five looks across
## the fuse, which is faster than the eye resolves the state change anyway.
const SCAN_EVERY: float = 0.05
## What the mark is about to be worth, as the fuse currently reads it. Ordered, so
## `maxi` composes it the same way `Cold` does.
enum Arm { COLD_NONE, PRIMED, ARMED }

# ---------------------------------------------------------------- WORK COUNTERS
## Deterministic tallies (see the same note on `RadiantVolley`): the suite asserts
## what the break DID, never how many milliseconds it took.
var bodies_hit: int = 0
## Warm bodies the MARK rimed on the way in - see `_rime`. Counted rather than
## inferred, so the suite can assert the rung the spell arms for itself.
var rimed_on_cast: int = 0
var frozen_breaks: int = 0
var shard_hits: int = 0
var damage_dealt: int = 0

var _at: Vector2 = Vector2.ZERO
## Where the shard was thrown FROM — the `origin` the HEX arm has always passed and
## this spell used to discard. Nothing else is needed to put a projectile in the air.
var _from: Vector2 = Vector2.ZERO
var _color: Color = Color(0.55, 0.85, 1.0)
var _radius: float = DEFAULT_RADIUS
var _base_damage: int = 42
var _elapsed: float = 0.0
var _broken: bool = false
var _seed: int = 0

## The fuse's live read of its own footprint. Drawn, never damaged with.
var _arm: int = Arm.COLD_NONE
var _scan_at: float = -1.0
## Frozen bodies the fuse has claimed, for the tethers and casing craze. Positions
## are re-read each frame from the live nodes, so a body sliding out is not drawn
## still attached.
var _marked: Array[Node2D] = []
## Where casings ACTUALLY came apart. Written by `_break`, so the fans in
## `_draw_break` mark real breaks and not the fuse's prediction of them.
var _broke_at: PackedVector2Array = PackedVector2Array()


## Damage multiplier for a cold state. Pure, so the combo's whole balance claim is
## assertable without a scene.
static func multiplier_for(state: int) -> float:
	match state:
		Cold.FROZEN:
			return FROZEN_MULT
		Cold.RIMED:
			return RIMED_MULT
	return WARM_MULT


## What `base` damage becomes against a body in `state`. Derived from
## `multiplier_for`, never restated — a second copy of the ladder is how the
## tested number and the dealt number drift apart.
static func damage_for(base: int, state: int) -> int:
	return maxi(int(round(float(base) * multiplier_for(state))), 1)


## THE HEX ENTRY POINT. Fixed signature shared by every spell on the
## `SpellDef.Kind.HEX` fork — see `SpellCaster.HEX_SCRIPTS`.
## ⚠ `origin` LOST ITS UNDERSCORE AND THAT IS THE BUG FIX. It was `_origin` — the
## unused-parameter convention — for as long as this spell had no projectile.
func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_color = color
	_seed = randi()
	if spell != null:
		_base_damage = maxi(spell.damage, 1)
		if spell.radius > 0.0:
			_radius = spell.radius
	# Seat the mark on the actual floor under the aim, via the shared probe rather
	# than a private raycast (docs/spell-world-contract.md). Over a pit this hands
	# the aim point straight back, which is correct: the fracture still happens in
	# the air where you pointed, it just has no floor to craze.
	_at = SpellWorld.floor_point(target, 220.0, [], self)
	# THE HAND. Lifted so the shard leaves a body rather than a pair of boots — a
	# throw that starts at floor level reads as the ground spitting, not as a cast.
	_from = origin + Vector2(0.0, -26.0)
	# ⚠ WORLD SPACE. A spectacle parks at the arena origin, so `global_position` is
	# (0, 0) and not where the effect is. Everything below is absolute.
	global_position = Vector2.ZERO
	# TWO CIRCLES, because there are two events. The ritual has to be continuous from
	# the hand to the impact or the mark is just something that appeared.
	#   1. The GATE at the hand, edge-on along the throw, that the shard bursts
	#      through. `SpellSigil.open` adopts the caster's live wind-up sigil when one
	#      is on offer, so on a player cast this is literally the same circle his
	#      hand was already drawing. Short hold — it belongs to the throw, not to the
	#      fuse. (BlinkStrike opens two the same way; this is the sanctioned shape.)
	#   2. The floor circle at the mark, scaled to the footprint it is about to break.
	var throw_axis: Vector2 = _at - _from
	throw_axis = throw_axis.normalized() if throw_axis.length_squared() > 1.0 else Vector2.RIGHT
	SpellSigil.open(self, _from, color, 0.55, true, throw_axis, false, 0.13, FUSE * 0.7)
	SpellSigil.open(self, _at, color, _radius / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.16, FUSE + BURST_LIFE)
	# The HURL, not the encasing — `ice_encase` now belongs to the moment the mark
	# ARMS (see `_scan`), which is the beat that actually means something.
	SpellDrops.sfx("ice_throw", -2.0, 0.0, 1.15)
	# BEFORE the first scan, so the fuse's own read already reflects the rung the mark
	# just armed for itself rather than showing WARM for a frame and then correcting.
	_rime()
	_scan()
	_join_reactor()
	queue_redraw()


## THE MARK RIMES WHAT IS STANDING IN IT, on the cast frame.
##
## ⚠ THIS SUPERSEDES ONE HALF OF THE RULING ON `FROZEN_MULT` ABOVE; the other half
## still stands and is still enforced here. That note says: do not raise this spell's
## damage, the armed case is already the biggest single hit in the roster, and "the
## warm rung (62 x 0.35 = 22) is the one he kept landing" - so FIXING THE READ IS THE
## FIX. The read fix shipped (the fuse now states its rung out loud) and the maker came
## back anyway: *"shatter is too weak of a spell change it or make it more powerful or
## easier to hit with"*. This takes the SECOND of the two routes he named. `WARM_MULT`,
## `RIMED_MULT`, `FROZEN_MULT` and `SpellDef.damage` are all untouched - what changes
## is which rung a landed cast reaches, not what a rung is worth.
##
## THE EVIDENCE THAT IT IS A WINDOW PROBLEM AND NOT A DAMAGE ONE, because "too weak"
## can mean either. This file already claims the warm cast sets up its own next one -
## "only a warm target is chilled, and that is the spell setting up its own next cast".
## THAT LOOP CANNOT CLOSE: `StatusComponent.CHILL_DURATION` is 2.2 s and this spell's
## cooldown is 4.0 s, so the chill it applies has expired 1.8 s before it can be cast
## again. The documented set-up was arithmetically impossible, which is precisely why
## the 0.35x rung was the one he kept landing - the only other route to cold is
## Blizzard's 1.5 s rime fuse, and `FREEZE_DURATION` is 0.6 s against a 0.28 s fuse
## plus a 300 px throw. So the mark rimes on the way IN instead: a landed Shatter now
## scores at least `RIMED_MULT` on its own account, and the 3x still costs a Blizzard.
##
## ⚠ WARM BODIES ONLY, AND THE GUARD IS LOAD-BEARING - it is the same rule `_hurt_one`
## already keeps, for the same reason. `StatusComponent.apply(ICE)` on an ALREADY
## chilled body FREEZES it, so riming indiscriminately would rebuild the
## chill -> freeze -> chill stunlock that Blizzard's rework exists to delete ("ice is
## not fair"). Anything already cold is left completely alone; this spell only ever
## lays the FIRST layer, and it still never lays the one that roots you.
##
## The telegraph is untouched by all of this: the footprint ring still snaps to full
## radius on the cast frame and the break still lands at `FUSE`. Stepping off the mark
## is the counterplay it always was, and a body that walks IN after the cast is not
## rimed and takes the 0.35x tap - the rime is a reward for the mark landing on you,
## not a field.
func _rime() -> void:
	for body: Node in SpellTargets.in_radius(_at, _radius,
			SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self):
		if body == null or not is_instance_valid(body):
			continue
		if cold_state(body) != Cold.WARM:
			continue
		if element_id < 0 or not body.has_method("apply_status"):
			continue
		body.apply_status(element_id)
		rimed_on_cast += 1


func _process(delta: float) -> void:
	_elapsed += delta
	if not _broken:
		if _elapsed - _scan_at >= SCAN_EVERY:
			_scan()
		if _elapsed >= FUSE:
			_broken = true
			_break()
	if _elapsed >= FUSE + BURST_LIFE:
		queue_free()
		return
	queue_redraw()


## Ask the footprint what it is worth, and SAY SO. Purely presentational — `_break`
## re-queries and scores every body itself, so a wrong answer here costs a look and
## never a damage number.
##
## The state can only ever climb during a fuse. A body that is frozen at cast and
## walks out at frame ten still LEAVES the mark armed, which is the honest reading:
## the mark was armed, and he dodged it. Downgrading mid-fuse would flicker the
## whole colour scheme on a body wandering along the rim.
func _scan() -> void:
	_scan_at = _elapsed
	var caught: Array = SpellTargets.in_radius(_at, _radius,
		SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self)
	var was: int = _arm
	_marked.clear()
	for body: Node in caught:
		match cold_state(body):
			Cold.FROZEN:
				_arm = maxi(_arm, Arm.ARMED)
				if body is Node2D:
					_marked.append(body as Node2D)
			Cold.RIMED:
				_arm = maxi(_arm, Arm.PRIMED)
	if _arm > was and _arm == Arm.ARMED:
		# The one moment in the fuse that carries information. It gets the encasing
		# sound this spell used to spend on its own cast frame, pitched up so it
		# reads as a latch closing rather than as a second impact.
		SpellDrops.sfx("ice_encase", -4.0, 0.0, 1.45)


# ------------------------------------------------------------------- THE BREAK
## The one damaging beat. Everything inside the drawn footprint, each body scored
## on its own cold state — this is the only place the multipliers are applied.
func _break() -> void:
	# `SpellTargets.in_radius` over `hostiles()`: the sanctioned selector. It
	# excludes the caster's own body (friendly fire points every spell at the
	# shared `mortal` group, and the caster is usually standing in the blast) and
	# it measures to the SILHOUETTE rather than to a body's origin.
	var caught: Array = SpellTargets.in_radius(_at, _radius,
		SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self)
	var frozen: Array[Node2D] = []
	for body: Node in caught:
		var state: int = cold_state(body)
		if _hurt_one(body, damage_for(_base_damage, state), state) and state == Cold.FROZEN:
			frozen_breaks += 1
			if body is Node2D:
				frozen.append(body as Node2D)
				# Remembered as a POINT, not as a reference: the whole reason to draw
				# a casing fan is that something came apart there, and half the time
				# the body it came apart on is dead and freed before the fan finishes.
				_broke_at.append((body as Node2D).global_position)
	# The casing shards. Splash from each broken casing, once per victim across the
	# whole detonation, so a tight cluster of frozen bodies does not multiply into
	# a nonsense number.
	if not frozen.is_empty():
		_splash(frozen, caught)
	# Cover is faction-blind — it belongs to nobody — so it stays a literal group
	# and takes the flat base, never a cold multiplier (a crate cannot be frozen).
	for prop: Node in SpellTargets.in_radius(_at, _radius,
			SpellTargets.hostiles(self, &"destructible"), [caster_node], self):
		if prop.has_method("damage_at"):
			prop.call("damage_at", _base_damage,
				(prop as Node2D).global_position if prop is Node2D else _at, Vector2.UP)
		else:
			SpellTargets.hurt(prop, _base_damage, _color)
	_burst()


## Apply one body's share. Returns true when damage actually landed (a guard can
## eat it whole), so the caller can tell a real casing break from a parried one.
func _hurt_one(body: Node, amount: int, state: int) -> bool:
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return false
	var at: Vector2 = SpellTargets.aim_point(body)
	var away: Vector2 = Vector2.UP
	if body is Node2D:
		var span: Vector2 = (body as Node2D).global_position - _at
		if span.length_squared() > 0.0001:
			away = span.normalized()
	var dealt: int = SpellDeflect.resolve(body, amount, away, at)
	if dealt <= 0:
		return false
	# ⚠ `take_damage` ships two signatures (Hero one arg, Enemy two). The wrong one
	# THROWS and aborts the enclosing function — always route through
	# `SpellTargets.hurt`, which adapts the arity.
	SpellTargets.hurt(body, dealt, Color(_color.r, _color.g, _color.b, 1.0))
	bodies_hit += 1
	damage_dealt += dealt
	# ⚠ ICE ONLY ON A WARM BODY. See the header: a second ICE application on an
	# already-chilled body is a FREEZE, and re-freezing on every hit is the exact
	# stunlock Blizzard's rework deleted. Shatter consumes cold, it does not stack it.
	if state == Cold.WARM and element_id >= 0 and body.has_method("apply_status"):
		body.apply_status(element_id)
	if body.has_method("apply_knockback"):
		body.call("apply_knockback", away * KNOCKBACK * multiplier_for(state))
	return true


## Casing shards. Each frozen body that actually broke throws debris; every OTHER
## caught body within `SHARD_RADIUS` of any of them takes one shard hit, total.
func _splash(frozen: Array[Node2D], caught: Array) -> void:
	var amount: int = maxi(int(round(float(_base_damage) * SHARD_DAMAGE_FRAC)), 1)
	var spent: Dictionary = {}
	for source: Node2D in frozen:
		if not is_instance_valid(source):
			continue
		CombatVfx.spawn_burst(get_parent(), source.global_position,
			Color(1.05, 1.35, 1.7, 0.95), Color(0.5, 0.75, 1.0, 0.0),
			22, 0.45, 120.0, 340.0, 0.5, 1.6, 0.0, 0.0, true)
		for body: Node in caught:
			if body == source or body == null or not is_instance_valid(body):
				continue
			if not body is Node2D:
				continue
			var id: int = body.get_instance_id()
			if spent.has(id):
				continue
			if source.global_position.distance_to((body as Node2D).global_position) > SHARD_RADIUS:
				continue
			spent[id] = true
			if SpellTargets.hurt(body, amount, Color(0.85, 0.97, 1.0, 1.0)):
				shard_hits += 1


## ⚠ THE TWO OUTCOMES MUST NOT SOUND OR LOOK RELATED. That is the entire readability
## fix expressed in one function: a warm break has to land as a disappointment the
## player can hear, so that an armed one lands as the thing he set up. The old code
## separated them by 3 units of screenshake and 0.03 s of hitstop, which is a
## difference the hand cannot feel and the eye cannot see — so a 22 and a 186 were
## the same event with different numbers floating off them.
func _burst() -> void:
	var low: bool = TuningConfig.quality_is_low()
	var broke: bool = frozen_breaks > 0
	if not broke:
		# A TAP. Small, dry, quick, no decal worth the name. If this is what he keeps
		# getting, the spell is telling him he skipped its set-up.
		CombatVfx.spawn_burst(get_parent(), _at,
			Color(0.85, 1.05, 1.3, 0.8), Color(0.45, 0.72, 1.0, 0.0),
			8 if low else 14, 0.34, 60.0, 170.0, 0.5, 1.3, 0.0, 0.0, true)
		# Snapped: `_at` is a frozen BODY's position, and a casing that pops in mid-air
		# left its rime patch hanging there. See `ScorchDecal.SNAP_LIFT`.
		ScorchDecal.spawn(get_parent(), _at, _radius * 0.34, "crack",
			Color(0.62, 0.82, 1.0, 0.26), 1.4, true)
		Juice.on_hit({"dir": Vector2.UP, "shake": 2.5, "sfx": "ice_shatter",
			"sfx_pitch": 0.34, "sfx_db": -5.0, "hitstop": 0.015})
		return
	# A DETONATION. The casing came apart, and every channel says so at once —
	# particle count, decal size, shake, hitstop, and a pitch DROP rather than the
	# rise the tap gets.
	CombatVfx.spawn_burst(get_parent(), _at,
		Color(1.35, 1.6, 1.95, 1.0), Color(0.45, 0.72, 1.0, 0.0),
		18 if low else 46, 0.62, 140.0, 480.0, 0.7, 2.6, 0.0, 0.0, true)
	ScorchDecal.spawn(get_parent(), _at, _radius * 0.9, "crack",
		Color(0.78, 0.94, 1.0, 0.6), 3.2, true)
	# One rime patch per casing, so the floor afterwards records WHERE things broke
	# rather than only that something did. Skipped on LOW: decals are the cheapest
	# thing to cut and the count scales with the crowd, which is the worst case.
	if not low:
		for p: Vector2 in _broke_at:
			ScorchDecal.spawn(get_parent(), p, 46.0, "crack",
				Color(0.86, 0.97, 1.0, 0.5), 2.6, true)
	# `ice_shatter`, not the generic `ice` stem: the whole point of this spell is
	# that it is Blizzard's third beat fired on demand, and the ear should agree.
	# Pitched DOWN and scaled by how many casings went, so breaking a frozen crowd is
	# audibly a bigger event than breaking one.
	Juice.on_hit({"dir": Vector2.UP,
		"shake": 9.0 + 2.0 * float(mini(frozen_breaks, 3)),
		"sfx": "ice_shatter", "sfx_pitch": -0.16, "sfx_db": 1.5,
		"hitstop": 0.10 + 0.02 * float(mini(frozen_breaks, 2))})


# ------------------------------------------------------- reading how cold it is
## How cold `body` is, WITHOUT touching a single file this agent does not own.
##
## Two independent sources, because the two mechanics that make a body cold live
## in two different places and neither publishes a getter:
##   1. Its `StatusComponent` child — the chill/freeze channel every element uses.
##      Duck-typed on `is_hard_cc` + `slow_factor` rather than on the node's NAME,
##      because a node added with `add_child(StatusComponent.new())` is named by
##      the engine and that name is not a contract.
##   2. A live `ZoneSpell` (Blizzard) that has rime accrued on this body. Its
##      `_rime` dictionary is keyed by instance id; a body with a casing (`enc >= 0`)
##      is FROZEN outright and one with a part-filled meter is RIMED.
##
## ⚠ EVERY READ GOES THROUGH `Object.get()`, which answers `null` for a property
## that has moved rather than erroring — so a rename downstream degrades this to
## "warm" instead of aborting the detonation half-way. The suite pins the property
## NAMES separately so the degradation is loud rather than silent.
func cold_state(body: Node) -> int:
	if body == null or not is_instance_valid(body):
		return Cold.WARM
	var status: int = _status_cold(body)
	if status == Cold.FROZEN:
		return Cold.FROZEN
	var rime: int = _rime_cold(body)
	return maxi(status, rime)   # Cold is ordered WARM < RIMED < FROZEN


func _status_cold(body: Node) -> int:
	for child: Node in body.get_children():
		if not child.has_method(&"is_hard_cc") or not child.has_method(&"slow_factor"):
			continue
		var freeze: Variant = child.get(&"_freeze")
		if freeze != null and float(freeze) > 0.0:
			return Cold.FROZEN
		var chill: Variant = child.get(&"_chill")
		if chill != null and float(chill) > 0.0:
			return Cold.RIMED
	return Cold.WARM


## Blizzard's fuse, read off any live field that is tracking this body. Fields are
## siblings — `SpellCaster` parents every spectacle to the same arena node — so the
## sibling walk is both the cheapest and the only reliable place to find them.
func _rime_cold(body: Node) -> int:
	var parent: Node = get_parent()
	if parent == null:
		return Cold.WARM
	var id: int = body.get_instance_id()
	var best: int = Cold.WARM
	for sibling: Node in parent.get_children():
		if sibling == self or not is_instance_valid(sibling):
			continue
		var raw: Variant = sibling.get(&"_rime")
		if raw == null or not (raw is Dictionary):
			continue
		var table: Dictionary = raw as Dictionary
		if not table.has(id):
			continue
		var rec: Dictionary = table[id] as Dictionary
		if float(rec.get("enc", -1.0)) >= 0.0:
			return Cold.FROZEN   # encased: nothing colder to find
		# ⚠ THE FULL-METER VALUE IS READ OFF THE FIELD'S OWN SCRIPT, not restated
		# here. `Object.get()` cannot see a `const` (constants are not properties),
		# so the script's constant map is the only honest route — and it keeps this
		# file from naming `ZoneSpell` at all, which is what makes "a future field
		# with a different fuse length" score correctly for free. A field that
		# publishes no fuse length cannot be scored, so it is skipped rather than
		# guessed at.
		var scr: Script = sibling.get_script() as Script
		if scr == null:
			continue
		var consts: Dictionary = scr.get_script_constant_map()
		if not consts.has("RIME_TO_ENCASE"):
			continue
		var full: float = float(consts["RIME_TO_ENCASE"])
		if full > 0.0 and float(rec.get("t", 0.0)) / full >= RIME_MIN:
			best = maxi(best, Cold.RIMED)
	return best


# --------------------------------------------------------------------- THE LOOK
## ⚠ MUST DEGRADE AT `graphics_quality = LOW` (the phone preview, a hard rule).
## LOW halves the fracture blades, drops the rime spurs, the shard's facets and
## frost flake, thins the trail from seven ghosts to three, and cuts the break's
## splinters and casing fans entirely. `_burst` cuts its particle counts and skips
## the per-casing decals on the same probe.
##
## WHAT MAY NEVER THIN, at either setting:
##   * the FOOTPRINT RING and the fuse's closing arc — they are the tell and the
##     hitbox's advert, and thinning a telegraph is a fairness change, not a
##     fidelity one;
##   * the SHARD's core and glow, and the ARMED tether and casing craze — they are
##     the two things the maker could not see, and a fidelity setting that hides
##     them again would be this bug shipping with a switch on it.
func _draw() -> void:
	var low: bool = TuningConfig.quality_is_low()
	if not _broken:
		_draw_fuse(low)
		return
	_draw_break(low)


## The mark's colour for its current reading. Three genuinely different tones, not
## three alphas of one: pale-cyan-on-a-bright-floor is the exact combination that
## disappears, so ARMED leaves the element's hue behind and goes hot white.
func _tone() -> Color:
	match _arm:
		Arm.ARMED:
			return Color(1.30, 1.62, 1.95)
		Arm.PRIMED:
			return Color(0.80, 1.00, 1.22)
	return Color(0.55, 0.82, 1.00)


func _draw_fuse(low: bool) -> void:
	var f: float = clampf(_elapsed / FUSE, 0.0, 1.0)
	var armed: bool = _arm == Arm.ARMED
	var tone: Color = _tone()
	var weight: float = 2.0 + 1.2 * float(_arm)     # 2.0 warm / 3.2 primed / 4.4 armed
	# The footprint, flat on the floor. Same radius the damage query uses.
	draw_set_transform(_at, 0.0, Vector2(1.0, 0.42))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 40,
		Color(tone.r, tone.g, tone.b, 0.30 + 0.34 * f), weight, true)
	if armed:
		# The counter-ring. It runs the other way, which is what makes the mark read
		# as MACHINERY winding up rather than as a bigger version of the same ring.
		var spin: float = _elapsed * 9.0
		for i: int in 3:
			var o: float = spin + TAU * float(i) / 3.0
			draw_arc(Vector2.ZERO, _radius * 0.66, o, o + 1.05, 14,
				Color(1.5, 1.75, 2.0, 0.55 + 0.4 * f), 3.0, true)
	# The closing arc: how much fuse is left, drawn on the floor so it cannot be
	# mistaken for the blast itself. Identical at both quality settings and at all
	# three readings — it is the TELL, and a telegraph that varies is a fairness bug.
	draw_arc(Vector2.ZERO, _radius * 0.86, -PI * 0.5, -PI * 0.5 + TAU * f, 40,
		Color(1.15, 1.5, 1.85, 0.9), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Fracture blades etching outward from the mark. An armed lattice is denser and
	# reaches the whole footprint; a warm one barely leaves the centre, which is the
	# spell drawing its own 0.35x.
	var blades: int = FRACTURES_LOW if low else FRACTURES
	var span: float = 0.62 if _arm == Arm.COLD_NONE else (1.0 if armed else 0.82)
	if armed:
		blades = int(float(blades) * 1.5)
	for i: int in blades:
		var ang: float = TAU * float(i) / float(blades) + float(_seed % 31) * 0.07
		var length: float = _radius * span * (0.35 + 0.65 * f) * (0.7 + 0.3 * _hash01(i * 71))
		var a: Vector2 = _at + Vector2.from_angle(ang) * (_radius * 0.12)
		var b: Vector2 = _at + Vector2.from_angle(ang) * length
		draw_line(a, b, Color(tone.r + 0.2, tone.g + 0.1, tone.b, 0.35 + 0.5 * f),
			1.0 + (2.4 if armed else 1.6) * f, true)
		if low:
			continue
		var mid: Vector2 = a.lerp(b, 0.62)
		draw_line(mid, mid + Vector2.from_angle(ang + 0.9) * length * 0.22,
			Color(0.9, 1.0, 1.15, 0.28 * f), 1.0, true)
		# RIME TAKING on the floor — crystal spurs budding off the lattice. Only
		# where the ground is actually cold, so it doubles as the PRIMED read.
		if _arm != Arm.COLD_NONE:
			var tip: Vector2 = a.lerp(b, 0.86)
			var out: Vector2 = Vector2.from_angle(ang + PI * 0.5) * (2.5 + 4.5 * f)
			draw_line(tip - out, tip + out,
				Color(tone.r, tone.g, tone.b, 0.5 * f), 1.4, true)
	if armed:
		_draw_marked(low, f)
	_draw_shard(low, f)


# ------------------------------------------------------------------- THE SHARD
## Where the thrown charge is at fuse fraction `f`. A shallow lob rather than a
## straight line: over a floor drawn at 0.42 vertical squash a straight segment
## between two ground points is a horizontal streak, and a horizontal streak at
## 1000 px/s is indistinguishable from a rendering artefact.
func _shard_at(f: float) -> Vector2:
	var p: Vector2 = _from.lerp(_at, f)
	p.y -= sin(PI * clampf(f, 0.0, 1.0)) * _from.distance_to(_at) * ARC_RISE
	return p


func _draw_shard(low: bool, f: float) -> void:
	var head: Vector2 = _shard_at(f)
	var back: Vector2 = _shard_at(maxf(f - 0.07, 0.0))
	var dir: Vector2 = head - back
	# ⚠ THE FALLBACK IS THE THROW, NOT `Vector2.RIGHT`. On the first frames `back`
	# and `head` are the same point, and a `RIGHT` default would spin the shard
	# sideways for the opening quarter of a 17-frame flight — the most visible part
	# of it, and on a leftward cast it would point the wrong way entirely.
	var throw: Vector2 = _at - _from
	dir = dir.normalized() if dir.length_squared() > 0.01 else (
		throw.normalized() if throw.length_squared() > 0.01 else Vector2.RIGHT)
	var tone: Color = _tone()
	# The trail FIRST, so the head draws over it. Ghosts of the same shard sampled
	# backwards along its own path — the trail is the projectile as far as the eye
	# is concerned at this speed.
	var ghosts: int = TRAIL_LOW if low else TRAIL
	for i: int in range(ghosts, 0, -1):
		var gf: float = f - 0.055 * float(i)
		if gf <= 0.0:
			continue
		var g: Vector2 = _shard_at(gf)
		var fade: float = 1.0 - float(i) / float(ghosts + 1)
		draw_line(g - dir * SHARD_LEN * 0.4 * fade, g + dir * SHARD_LEN * 0.4 * fade,
			Color(tone.r, tone.g, tone.b, 0.5 * fade * fade), 2.0 + 5.0 * fade, true)
	# The shard itself: a wide cold glow with a white-hot core through it, plus two
	# facets so it reads as a crystal rather than as a dash.
	var tip: Vector2 = head + dir * SHARD_LEN * 0.5
	var tail: Vector2 = head - dir * SHARD_LEN * 0.5
	draw_line(tail, tip, Color(tone.r * 0.7, tone.g * 0.85, tone.b, 0.55), 11.0, true)
	draw_line(tail, tip, Color(1.45, 1.7, 2.0, 0.95), 3.4, true)
	if low:
		return
	var side: Vector2 = dir.orthogonal()
	var waist: Vector2 = head.lerp(tail, 0.25)
	draw_line(waist - side * 6.0, tip, Color(1.2, 1.5, 1.85, 0.8), 1.8, true)
	draw_line(waist + side * 6.0, tip, Color(1.2, 1.5, 1.85, 0.8), 1.8, true)
	# Frost flaking off the shard as it flies. Cheap, and it is what sells the thing
	# as COLD rather than as a generic bolt recoloured blue.
	for i: int in 4:
		var h: float = _hash01(_seed + i * 91 + int(f * 40.0) * 13)
		var off: Vector2 = side * (h - 0.5) * 22.0 - dir * (6.0 + 18.0 * h)
		draw_line(head + off, head + off - dir * 5.0,
			Color(0.9, 1.1, 1.4, 0.5 * (1.0 - h)), 1.4, true)


## THE CLAIM. A lattice tether from the mark to every frozen body inside it, each
## wearing a crazing casing. This is the frame that says "these ones are the 3x",
## and it is the piece no other class in the roster has any version of.
func _draw_marked(low: bool, f: float) -> void:
	for idx: int in _marked.size():
		var body: Node2D = _marked[idx]
		if body == null or not is_instance_valid(body):
			continue
		var to: Vector2 = body.global_position
		# Jagged, in three segments — a straight tether reads as a laser, and this is
		# frost creeping along the ground to reach something.
		var prev: Vector2 = _at
		for s: int in 3:
			var t: float = float(s + 1) / 3.0
			var pt: Vector2 = _at.lerp(to, t)
			if s < 2:
				var jitter: float = (_hash01(idx * 53 + s * 17 + _seed) - 0.5) * 26.0
				pt += (to - _at).orthogonal().normalized() * jitter
			draw_line(prev, pt, Color(1.3, 1.6, 1.95, 0.35 + 0.5 * f), 1.6 + 1.8 * f, true)
			prev = pt
		# The casing, crazing over the body it is about to leave.
		draw_arc(to, 20.0 + 4.0 * f, 0.0, TAU, 22,
			Color(1.4, 1.68, 2.0, 0.4 + 0.5 * f), 2.0 + 1.5 * f, true)
		if low:
			continue
		for c: int in 5:
			var ang: float = TAU * _hash01(idx * 97 + c * 29) + f * 0.6
			draw_line(to + Vector2.from_angle(ang) * 6.0,
				to + Vector2.from_angle(ang) * (16.0 + 8.0 * f),
				Color(1.2, 1.5, 1.9, 0.55 * f), 1.5, true)


func _draw_break(low: bool) -> void:
	var k: float = clampf((_elapsed - FUSE) / BURST_LIFE, 0.0, 1.0)
	var alpha: float = 1.0 - k
	var broke: bool = frozen_breaks > 0
	draw_set_transform(_at, 0.0, Vector2(1.0, 0.42))
	if broke:
		# The WHITE-OUT. Front-loaded into the first third of the burst so it lands as
		# a flash and not as a fog — this is the frame the 186 happens on.
		var flash: float = clampf(1.0 - k * 3.0, 0.0, 1.0)
		if flash > 0.0:
			draw_circle(Vector2.ZERO, _radius * (0.5 + 0.9 * k),
				Color(1.6, 1.8, 2.0, 0.55 * flash))
		# Two rings at different speeds. One ring is a pulse; two is a detonation.
		draw_arc(Vector2.ZERO, _radius * (0.4 + 1.35 * k), 0.0, TAU, 48,
			Color(1.5, 1.75, 2.0, 0.9 * alpha), 7.0 * alpha + 1.5, true)
		draw_arc(Vector2.ZERO, _radius * (0.2 + 0.7 * k), 0.0, TAU, 44,
			Color(1.1, 1.45, 1.9, 0.6 * alpha), 3.0 * alpha + 1.0, true)
	else:
		# The TAP. Deliberately the small version of the same idea.
		draw_arc(Vector2.ZERO, _radius * (0.3 + 0.55 * k), 0.0, TAU, 44,
			Color(0.85, 1.05, 1.3, 0.55 * alpha), 2.5 * alpha + 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if low or not broke:
		return
	# Crystal splinters thrown out of the break. Garnish — first thing to go.
	for i: int in 20:
		var ang: float = TAU * _hash01(_seed + i * 37)
		var d: float = _radius * (0.3 + 1.3 * k) * (0.6 + 0.5 * _hash01(i * 13 + 5))
		var p: Vector2 = _at + Vector2.from_angle(ang) * d
		draw_line(p, p - Vector2.from_angle(ang) * (9.0 + 13.0 * k),
			Color(0.95, 1.15, 1.4, 0.8 * alpha), 2.0, true)
	# CASING FANS. One per body that actually came apart, thrown from where it stood
	# — so a frozen crowd breaking is visibly several separate things breaking rather
	# than one bigger ring at the centre.
	for b: int in _broke_at.size():
		var at: Vector2 = _broke_at[b]
		for s: int in 9:
			var ang2: float = TAU * float(s) / 9.0 + _hash01(b * 61 + _seed) * TAU
			var reach: float = 20.0 + 70.0 * k * (0.6 + 0.6 * _hash01(b * 7 + s * 3))
			var tip: Vector2 = at + Vector2.from_angle(ang2) * reach
			draw_line(at + Vector2.from_angle(ang2) * 8.0, tip,
				Color(1.25, 1.55, 1.9, 0.85 * alpha), 2.4 * alpha + 0.8, true)


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


# --- reaction contract (see SpellReactor) ------------------------------------
## THE CRYOMANCER'S DAMAGE HAND, ENTERING THE REACTION SYSTEM.
##
## Measured (`tools/probe_reaction_count.gd`, 36-bout round robin): the registry
## averaged 0.84 live effects and a reaction needs TWO, so only ~600-1300 pair tests
## happened in a whole sweep and 12 reactions fired from 6 of 21 authored rows.
## Twenty of the thirty-six kit spells never called `register` at all. This is one of
## them, and it is the whole of a class's damage output — every Cryomancer bout was
## a fight with a hole in the reaction matrix where its attacking spell should be.
##
## AN IMPACT, and unusually literally so: this spell is a detonation and nothing
## else. It does not travel (the thrown shard is the fuse timer made visible, not a
## damaging body — see the class docs), it does not stand, it does not sweep. It goes
## off once at `_at`.
##
## WHAT IT UNLOCKS, none of it needing a new row: ICE meets FIRE as
## `mutual_annihilation` wherever the two schools cross; a break beside an ice wall
## bursts it (`shatter_ice_barrier` IMPACT x BARRIER is wildcard on the attacking
## element); a break inside a void field is `void_charged`.
##
## ⚠ ONE OF THOSE IS A SELF-INTERACTION AND IT IS WORTH SAYING OUT LOUD, because it
## is not something this file chose. The Cryomancer kit is
## `damage: shatter / control: blizzard / answer: ice_wall`, and the
## `shatter_ice_barrier` IMPACT arm carries no `require_owner` — so a break that goes
## off next to your OWN ice wall bursts your own wall. "You detonated an ice casing
## against your own sheet of ice and it came apart" is the honest reading and it is
## legible in one play, which is why it is left alone rather than special-cased here:
## if it turns out to be annoying, the fix is ONE predicate on that row in
## `ReactionTable`, never a branch in this file.
##
## ⚠ AND THE LIMIT, the same one `ChainBolt` carries: the damage is already paid by
## the time anything can react, so an outcome that CONSUMES this takes nothing back.
## It cuts the burst short, which is the right picture, but no row may be authored on
## the assumption that spending this prevents a hit.

## Set by a reaction that spent this break.
var _consumed: bool = false


## The footprint, in world space — the same `_at` and `_radius` that `_break()`
## queries and `_draw_break()` draws, so what reacts, what is hurt and what is shown
## are one circle and cannot drift apart.
##
## ⚠ NEVER `global_position`. `hex()` parks this node at the arena origin and draws
## in world coordinates, so its transform is (0, 0) and is NOT where the mark is.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(_at, _radius)


## LOAD-BEARING. `FUSE` is a real telegraph — the mark snaps down at full radius and
## the fracture lattice etches outward for seventeen frames before anything happens,
## and the whole "everything is dodgeable" rule for this spell lives in that window.
## An effect that reacted during it would burst a wall, or annihilate an oncoming
## fireball, BEFORE the break it is supposed to be caused by. `_broken` flips in
## `_process` on the frame `_break()` runs, i.e. exactly when the damage lands.
func reaction_active() -> bool:
	return _broken and not _consumed


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.IMPACT


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: the burst is cut short, without the rest of `BURST_LIFE`.
func reaction_consume() -> void:
	if _consumed:
		return
	_consumed = true
	queue_free()


## Joined at the end of `hex()`. Registering during the fuse is correct and
## expected — `reaction_active()` above is what decides when this may actually react,
## and holding registration back until `_break()` would mean an effect that is
## visible on the floor for 0.28 s before the registry has ever heard of it.
##
## The node is in the tree by here: `SpellCaster` does `arena.add_child()` then
## `_stamp()` then `hex()`, so `element_id`, `caster_node` and `spell_tier` are all
## written before this runs.
func _join_reactor() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.IMPACT, element_id)


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)
