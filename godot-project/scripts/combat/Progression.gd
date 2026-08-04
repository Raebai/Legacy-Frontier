class_name Progression
extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════════
## LEVELS, XP AND GROWTH. THE ONE PLACE. ALL PURE, ALL STATIC, ALL HEADLESS.
## ═══════════════════════════════════════════════════════════════════════════════
##
## THE MAKER'S BRIEF, verbatim (2026-08-04):
##   "a nice little level up animation around the stickman and of course it harder
##    to level up as you play but villains in the high levels drop more
##    proportionally do all that maths"
##
## The operative word is PROPORTIONALLY, and it is the whole design. Two curves
## that both grow are not automatically fair to each other; two curves where one
## is DERIVED FROM the other cannot drift apart. So there is exactly one authored
## growth rate in this file (`GROWTH`), and the depth curve is computed from it.
##
## ⚠ THIS OVERRIDES THE SPEC. `docs/superpowers/specs/2026-08-04-spell-trees-and-
## progression-design.md` §5.3 says "XP comes from floors cleared and guardians
## felled, NEVER from kills — otherwise the optimal play is farming trash on floor
## 1". The maker's line above puts XP on villains, so kills pay. The farm problem
## is real and is not waved away; it is solved by arithmetic instead of by a ban.
## See THE ANTI-FARM THEOREM below, and `slice_test_progression.gd`, which pins it.
##
## ⚠ EVERY NUMBER HERE IS REASONING, NOT FEEL. Nothing in this file has been
## played. `GROWTH` and `LEVELS_PER_FLOOR` are the two dials; the rest follows.

# ═══════════════════════════════════════════════════════════════════════════════
# THE TWO AUTHORED NUMBERS. EVERYTHING ELSE IS DERIVED FROM THEM.
# ═══════════════════════════════════════════════════════════════════════════════

## What level 1 -> 2 costs. Pure scale — moving it renames every number in the
## system and changes nothing about how it feels.
const BASE_XP: float = 60.0

## ⚠ "HARDER TO LEVEL UP AS YOU PLAY", IN ONE CONSTANT. Each level costs 22% more
## than the one before it, forever. Over the ~12 levels of a first full climb that
## compounds to 10.9x — level 12 costs eleven times what level 1 did, which is a
## slope you can feel without a graph.
##
## GEOMETRIC RATHER THAN A POWER CURVE, deliberately. `BASE * L^k` has a growth
## RATIO that shrinks as L rises (it tends to 1), so levels would come faster and
## faster at the top — the opposite of the brief. A geometric curve's ratio is
## constant, which is the only shape that keeps its promise at every level.
const GROWTH: float = 1.22

## The pace target: how many levels a floor is worth. ~1.2 x 10 floors = ~12
## levels for a full climb of the current tower, which is what the spec sized the
## Growth table against (§5.3).
const LEVELS_PER_FLOOR: float = 1.2

## The hard ceiling. At 30, a class's primary axis (5 Growth/level) has banked 145
## points: +87% HP on VITALITY, or +43% speed on SWIFTNESS. Big, and finite.
const MAX_LEVEL: int = 30

# ═══════════════════════════════════════════════════════════════════════════════
# THE DERIVED ONE — "villains in the high levels drop more, PROPORTIONALLY"
# ═══════════════════════════════════════════════════════════════════════════════
## How much more a floor is worth than the floor below it. **NOT AUTHORED.**
##
## If a floor is worth `LEVELS_PER_FLOOR` levels, and a level costs `GROWTH` times
## the last one, then a floor must be worth `GROWTH ^ LEVELS_PER_FLOOR` times the
## floor below it. That is not a tuning choice; it is the only value that makes
## the two curves agree, and writing it as arithmetic instead of as `1.27` is what
## stops the two from ever disagreeing after a retune.
##
## Same principle as `LEG_LEN_FACTOR` / `HIP_Y_FACTOR` in `CharacterRig`, and for
## the same reason: two sources of truth for one relationship is how a system ends
## up quietly lying about itself.
static func depth_gain() -> float:
	return pow(GROWTH, LEVELS_PER_FLOOR)


# ═══════════════════════════════════════════════════════════════════════════════
# ⚠ THE ANTI-FARM THEOREM — why kills can pay without floor 1 becoming a job
# ═══════════════════════════════════════════════════════════════════════════════
## The spec banned kill-XP because "the optimal play is farming trash on floor 1".
## The ban is not needed, because the farm dies on its own under this curve. The
## argument, and `_test_farming_dies` is the executable version of it:
##
##   * A floor-f enemy is worth `floor_xp_value(f) * KILL_SHARE / budget(f)`.
##     That number is FIXED for a given floor — floor 1 pays 2 XP a body, always.
##   * A level costs `BASE_XP * GROWTH^(L-1)`, which grows without bound.
##   * So kills-to-level on a FIXED floor grows geometrically. MEASURED, by running
##     `slice_test_progression.gd` against the shipping tower: 30 bodies at level 1,
##     268 at level 12, 1,312 at level 20, 7,856 at level 29. Floor 1 authors 22
##     bodies, so by level 20 one level costs SIXTY full clears of it. The farm is
##     never BANNED, it just stops being worth anyone's evening — and it stops being
##     worth it faster the more you have already played.
##   * Meanwhile CLIMBING holds a flat pace at every depth, because floor value and
##     level cost rise together by construction: `floor_xp_value(f)` divided by the
##     cost of a level at the level you are expected to BE on floor f is exactly
##     `LEVELS_PER_FLOOR`, for every f. That identity is the whole system, and
##     `_test_the_pace_is_flat_at_every_depth` asserts it directly.
##
## The short version: farming is not punished, it is out-grown.

## How a floor's XP is paid out. Must sum to 1.0 (pinned).
##
## KILLS ARE THE BIGGEST SHARE because the maker asked for villains to drop it and
## a reward you can see land is worth more than a reward that arrives at a door.
## The other two exist so that a floor is worth its full value whether you fought
## every body or slipped past half of them — the tower should not reward
## room-clearing pedantry, and it should not reward skipping either.
const KILL_SHARE: float = 0.55
const CLEAR_SHARE: float = 0.20
const GUARDIAN_SHARE: float = 0.25


# ═══════════════════════════════════════════════════════════════════════════════
# THE CURVE
# ═══════════════════════════════════════════════════════════════════════════════

## XP to get from `level` to `level + 1`. Zero at the cap — a capped climber banks
## no more XP, rather than banking it into a level they cannot have.
##
## The float form is the REAL curve; the int form is what a player is shown. Every
## invariant that has to hold exactly (the pace identity above) is asserted against
## the float form, so rounding cannot be mistaken for a broken relationship.
static func xp_to_next_exact(level: float) -> float:
	if level >= float(MAX_LEVEL):
		return 0.0
	return BASE_XP * pow(GROWTH, maxf(level, 1.0) - 1.0)


static func xp_to_next(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return maxi(1, int(round(xp_to_next_exact(float(maxi(level, 1))))))


## Total XP banked over a career to REACH `level` (level 1 costs nothing).
static func total_xp_for_level(level: int) -> int:
	var target: int = clampi(level, 1, MAX_LEVEL)
	var sum: int = 0
	for l: int in range(1, target):
		sum += xp_to_next(l)
	return sum


## The level a given lifetime XP total buys. The inverse of `total_xp_for_level`,
## by walk — MAX_LEVEL is 30, so this is thirty adds and needs no cleverness.
static func level_for_xp(xp: int) -> int:
	var banked: int = maxi(xp, 0)
	var level: int = 1
	while level < MAX_LEVEL:
		var cost: int = xp_to_next(level)
		if cost <= 0 or banked < cost:
			break
		banked -= cost
		level += 1
	return level


## XP banked INTO the current level (0 .. xp_to_next(level)). This is the progress
## bar's numerator, and it is derived rather than stored for the same reason Growth
## is: a stored "xp into this level" can disagree with the lifetime total, and then
## the bar and the level are two different opinions about the same save.
static func xp_into_level(xp: int) -> int:
	var level: int = level_for_xp(xp)
	return maxi(xp, 0) - total_xp_for_level(level)


# ═══════════════════════════════════════════════════════════════════════════════
# WHAT A FLOOR IS WORTH
# ═══════════════════════════════════════════════════════════════════════════════

## The level a climber is EXPECTED to be on a given floor, as a continuous value.
## Not a gate and not enforced anywhere — it is the reference point the depth curve
## is calibrated against, and the thing the pace identity is stated in terms of.
static func expected_level_on_floor(floor: int) -> float:
	return 1.0 + float(maxi(floor, 1) - 1) * LEVELS_PER_FLOOR


## Total XP a floor is worth, across all three channels.
##
## `BASE_XP * LEVELS_PER_FLOOR * depth_gain()^(f-1)` — i.e. floor 1 is worth 1.2
## levels at level-1 prices, and every floor above is worth `depth_gain()` times
## the one below. That closed form IS the maker's "proportionally": the phrase is
## not decoration on the design, it is the exponent.
static func floor_xp_value(floor: int) -> float:
	return BASE_XP * LEVELS_PER_FLOOR * pow(depth_gain(), float(maxi(floor, 1) - 1))


## What one body on this floor is worth. **DERIVED BY DIVISION**, not authored.
##
## ⚠ THE FLOOR IS THE UNIT OF XP, NOT THE ENEMY. A floor is worth ~1.2 levels; the
## per-enemy number is that value split over however many bodies the floor actually
## authors. This matters because wave budgets already grow with depth (22 bodies on
## floor 1, 78 on floor 10) — if the per-enemy number were authored to grow too,
## deep floors would pay for depth TWICE and the pace would run away at the top.
##
## It also means the maker can retune a wave budget and the XP economy re-balances
## itself, instead of silently inflating.
static func enemy_xp(floor: int, floor_budget: int) -> int:
	var bodies: int = maxi(floor_budget, 1)
	return maxi(1, int(round(floor_xp_value(floor) * KILL_SHARE / float(bodies))))


## What the floor's guardian is worth. The single biggest XP event on a floor, which
## is correct: it is the one fight the floor is built toward.
static func guardian_xp(floor: int) -> int:
	return maxi(1, int(round(floor_xp_value(floor) * GUARDIAN_SHARE)))


## What taking the exit is worth. Paid for CLEARING, so slipping past bodies costs
## you their share but never the floor's.
static func clear_xp(floor: int) -> int:
	return maxi(1, int(round(floor_xp_value(floor) * CLEAR_SHARE)))


## How many bodies on `floor` it takes to buy one level at `level`. The farm meter —
## exists so the theorem above is a number anyone can print, not a paragraph.
static func kills_to_level(floor: int, level: int, floor_budget: int) -> int:
	var per: int = enemy_xp(floor, floor_budget)
	var cost: int = xp_to_next(level)
	if cost <= 0:
		return 0            # capped: no number of bodies buys anything
	return int(ceil(float(cost) / float(maxi(per, 1))))


# ═══════════════════════════════════════════════════════════════════════════════
# GROWTH — "the same number just in different things"
# ═══════════════════════════════════════════════════════════════════════════════
## Maker, correcting the first draft of the spec: "by stat points I mean points
## that can be spent in the spell tree and levelling should just improve your stats
## by certain amounts based on the class… different classes different themes
## different stat improvements but its the same number just in different things".
##
## So a level gives ONE currency (a Skill Point, spent in the tree) plus a fixed
## budget of Growth that is never chosen. Stats are class CHARACTER, not homework:
## a player asked to allocate stats looks up the correct answer, and then it was
## never a choice.

enum Axis { VITALITY, POWER, FOCUS, SWIFTNESS, WARD }
const AXIS_COUNT: int = 5
const AXIS_NAMES: Array[String] = ["Vitality", "Power", "Focus", "Swiftness", "Ward"]

## ⚠ EVERY ROW SUMS TO EXACTLY THIS. It is the invariant that keeps nine classes on
## one power curve while feeling nothing alike — a class cannot out-level another,
## it can only become more itself. `_test_every_class_row_sums_to_ten` pins it.
const GROWTH_PER_LEVEL: int = 10

## ⚠ THE PER-POINT VALUES ARE NOT EQUAL, ON PURPOSE. A point of speed is worth far
## more than a point of HP in a game about dodging, so they are priced against each
## other rather than printed the same. First pass, untuned, never played.
##
## If playtest shows the climb being SOLVED by levelling rather than climbed, cut
## these — do NOT cut `GROWTH_PER_LEVEL`, because 10-per-level is the thing that
## keeps the nine classes comparable to each other.
const PER_POINT: Array[float] = [
	0.0060,   # VITALITY  -> max hp
	0.0040,   # POWER     -> spell + melee damage
	0.0035,   # FOCUS     -> cooldown recovery
	0.0030,   # SWIFTNESS -> move speed
	0.0025,   # WARD      -> damage reduction
]

## Damage reduction is the one axis with a hard ceiling, because it is the one that
## compounds against every other number in the game. A Juggernaut at level 30 banks
## 87 WARD points = 21.8%, comfortably under it; the cap exists so that raising
## MAX_LEVEL later cannot quietly produce an immortal.
const WARD_CAP: float = 0.40

## Growth per level, per class. Indexed by `Hero.HeroClass`
## (MAGE/Arcanist, ROGUE/Shadowblade, BRAWLER, JUGGERNAUT, CLERIC, CRYOMANCER,
## STORMCALLER, WARLOCK, SWORDSAINT) — spec §5.2.
##
## ⚠ STORMCALLER IS DELIBERATELY NOT GIVEN FOCUS 4. It wins 16-0 in the honest sim
## because it is the only class built end-to-end around ICE-field -> LIGHTNING, and
## cooldown recovery is precisely the axis that would compound that. It gets
## mobility instead. The obvious "combo class -> more FOCUS" read is the wrong one
## here, and the reason is measured rather than felt.
const CLASS_GROWTH: Array[Array] = [
	#  VIT POW FOC SWI WARD
	[   1,  4,  3,  2,  0],   # 0 ARCANIST    — glass zoner: hits hard, recovers fast, dies fast
	[   1,  3,  2,  4,  0],   # 1 SHADOWBLADE — fastest thing in the tower, made of paper
	[   3,  4,  1,  2,  0],   # 2 BRAWLER     — walks in and hits you
	[   4,  2,  1,  0,  3],   # 3 JUGGERNAUT  — immovable; never gets quicker
	[   3,  2,  2,  1,  2],   # 4 CLERIC      — hard to kill from any angle
	[   2,  2,  4,  1,  1],   # 5 CRYOMANCER  — uptime; the field is always up
	[   2,  3,  2,  3,  0],   # 6 STORMCALLER — mobile combo caster (see the ⚠ above)
	[   2,  3,  3,  1,  1],   # 7 WARLOCK     — attrition; the thralls do the running
	[   2,  3,  2,  2,  1],   # 8 SWORDSAINT  — even, because the parry is the stat
]


## Growth points banked on one axis at a given level. Level 1 has banked nothing —
## a level-1 climber is exactly the class's authored base, which is what keeps
## every existing balance number (CLASS_CONFIG hp/speed, BotMatch's CLASS_VITALITY)
## meaningful instead of quietly obsolete.
##
## ⚠ DERIVED, NEVER STORED. Re-reading the table after a retune updates every
## existing save for free, and the save can never hold a Growth total that
## disagrees with the class it belongs to.
static func growth_points(level: int, hero_class: int, axis: int) -> int:
	if hero_class < 0 or hero_class >= CLASS_GROWTH.size():
		return 0
	if axis < 0 or axis >= AXIS_COUNT:
		return 0
	var levels_gained: int = clampi(level, 1, MAX_LEVEL) - 1
	return int(CLASS_GROWTH[hero_class][axis]) * levels_gained


## The multiplier an axis applies at a level. 1.0 at level 1, always.
## WARD is NOT a multiplier and must not be read through here — see `ward_reduction`.
static func stat_mult(level: int, hero_class: int, axis: int) -> float:
	if axis == Axis.WARD:
		return 1.0
	return 1.0 + float(growth_points(level, hero_class, axis)) * PER_POINT[axis]


## Fraction of incoming damage WARD removes, capped. Separate from `stat_mult`
## because a reduction that is applied as a multiplier is a bug waiting for the day
## someone multiplies it by damage instead of subtracting it from 1.
static func ward_reduction(level: int, hero_class: int) -> float:
	return minf(float(growth_points(level, hero_class, Axis.WARD)) * PER_POINT[Axis.WARD], WARD_CAP)


# ═══════════════════════════════════════════════════════════════════════════════
# CO-OP — the party climbs at the trailing member's power
# ═══════════════════════════════════════════════════════════════════════════════
## Maker, 2026-08-04: "in co-op I would want them to experience the climbing of the
## tower without being overlevelled at the first fight".
##
## THE RULE: **Growth is computed from the PARTY level — the lowest member's.
## Unlocked spell nodes and unlocked classes are never touched.**
##
## ⚠ WHY NOT SCALE THE TOWER TO THE PARTY'S LEVELS (the other option on the table).
## Enemies tuned for the level-25 two-shot the level-3, and under the shipped death
## rule (ghost until revived, all dead = over) that cashes out as the newer player
## spending the floor as a corpse. It also puts a second, untested multiplier on a
## difficulty curve nobody has yet fought past floor 5, which is exactly the shape
## of the `TOTAL_FLOORS` bug recorded in docs/NEXT-SESSION.md: a scaling constant
## that silently did nothing while every test stayed green.
##
## ⚠ WHY THIS CUT AND NOT "NOBODY BRINGS LEVELS". A level gives two things that want
## opposite treatment. GROWTH is raw power and is what trivialises floor 1. The
## SPELL TREE is identity — taking it away is what makes people not play with
## friends. So power is capped and identity is kept, and the experienced player
## still carries the party with their build rather than with their stat block.
##
## This mirrors `GameState.party_start_floor`, which takes the lowest CHECKPOINT in
## the party for the same reasons and was already ruled on. Same problem, same shape.
##
## Difficulty DOES still answer the party — through the floor it starts on and
## through `Encounter`'s headcount scaling (budget, concurrent cap, guardian hp).
## It just does not answer POWER, which is the one axis that hurts the person the
## rule exists to protect.
##
## ⚠ RESOLVE ONCE, AT TOWER ENTRY, AND FREEZE FOR THE RUN. Recomputing live means a
## friend joining mid-fight silently drops your max hp out from under your current
## hp. Same moment `party_start_floor` is resolved.
##
## A party of one answers that one member's level exactly — `_test_solo_is_untouched`
## pins it, so the co-op path can never regress solo.
static func party_growth_level(levels: Array) -> int:
	var lowest: int = -1
	for l in levels:
		var v: int = clampi(int(l), 1, MAX_LEVEL)
		if lowest < 0 or v < lowest:
			lowest = v
	return maxi(lowest, 1)


# ═══════════════════════════════════════════════════════════════════════════════
# CLASS UNLOCKING (spec §6)
# ═══════════════════════════════════════════════════════════════════════════════
## Start with six. The three withheld are the hardest to play well —
## combo-dependent, thrall management, parry timing — and withholding Stormcaller
## also defuses the known 16-0 balance problem by making it a late reward instead
## of a beginner trap.
const STARTING_CLASSES: Array[int] = [0, 1, 2, 3, 4, 5]
const LOCKED_CLASSES: Array[int] = [6, 7, 8]   # Stormcaller, Warlock, Swordsaint

## ⚠ THE GUARDIAN GRANTS A CHOICE, NOT A DROP. The maker floated "the 5th floor boss
## is a one time one of the 3 remaining classes"; a RANDOM one means the class you
## get is a coin flip and you farm a boss for it. Beating the guardian lets you PICK.
## Deterministic, still a milestone, and the pick becomes a memory.
const CLASS_UNLOCK_FLOORS: Array[int] = [5, 10]   # …and the third on a full clear


## ═══════════════════════════════════════════════════════════════════════════════
## SURFACED DECISION — IS THE ROSTER GATED AT ALL?
## ═══════════════════════════════════════════════════════════════════════════════
## Maker, 2026-08-04, mid-playtest: "I can only see 6 classes right now for now
## show me all the available classes".
##
## TRUE (shipped right now): every class is pickable immediately. The floor-5 and
## floor-10 guardians still BANK a pick — `pending_class_choices` still increments
## and still persists — it simply has nothing left to buy, so flipping this back
## costs no save migration and loses no progress a player already earned.
##
## FALSE: the designed behaviour — six starters, and Stormcaller / Warlock /
## Swordsaint held by guardians (spec §6). That design is not deleted and is worth
## keeping: it defuses Stormcaller's measured 16-0 by making it a late reward
## rather than a beginner trap, and it gives the floor-5 guardian something to be
## FOR beyond XP.
##
## ⚠ THE WORD IN THE ASK IS "FOR NOW". This is open so the maker can playtest nine
## classes without grinding to floor 5 four times, which is the correct call during
## a balance pass and the wrong one for a shipping build. Flip it before release.
const ALL_CLASSES_UNLOCKED: bool = true


static func is_class_unlocked(hero_class: int, unlocked: Array) -> bool:
	if ALL_CLASSES_UNLOCKED:
		return hero_class >= 0 and hero_class < CLASS_GROWTH.size()
	if STARTING_CLASSES.has(hero_class):
		return true
	for u in unlocked:
		if int(u) == hero_class:
			return true
	return false


## Which locked classes are still available to pick. Empty once all three are had.
static func choosable_classes(unlocked: Array) -> Array[int]:
	var out: Array[int] = []
	for c: int in LOCKED_CLASSES:
		if not is_class_unlocked(c, unlocked):
			out.append(c)
	return out
