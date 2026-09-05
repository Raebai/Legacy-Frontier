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
##
## ⚠ THE DEPTH IS CAPPED, AND IT IS NOT A NERF. The tower is endless now
## (`TowerDef.endless`), so `floor` is no longer bounded by ten. This curve is
## geometric: at floor 999 it evaluates to ~1e103, and `GameState._open_floor_purse`
## rounds it into an int — which is not a big number, it is an OVERFLOW, in the one
## function that decides what a kill pays.
##
## `XP_DEPTH_CAP` is 30 because that is where levelling has already stopped:
## `expected_level_on_floor(26)` is 31 and `MAX_LEVEL` is 30, so from floor 26 the
## curve is already paying into a bar that cannot move. Capping four floors past that
## changes the value of nothing anyone can spend. Below 30 this is the identity.
const XP_DEPTH_CAP: int = 30


static func floor_xp_value(floor: int) -> float:
	var d: int = clampi(maxi(floor, 1), 1, XP_DEPTH_CAP)
	return BASE_XP * LEVELS_PER_FLOOR * pow(depth_gain(), float(d - 1))


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


# ═══════════════════════════════════════════════════════════════════════════════
# OWNERSHIP — "what is unlockable and what isnt … and how to unlock it"
# ═══════════════════════════════════════════════════════════════════════════════
## THE MAKER'S ASK, verbatim (2026-09-05): *"the grimoire is cool but still not clear
## what is unlockable and what isnt like for the class and how to unlock it same with
## the armoury items … and do some thinking on how these items should be unlocked"*.
##
## ⚠ NO NEW CURRENCY, AND THAT IS THE WHOLE DESIGN CONSTRAINT. This project already
## banks three things a player EARNS, all of them persisted and all of them currently
## under-spent. An unlock table is a READ over those, never a fourth ledger:
##
##   1. **DEPTH** — `GameState._highest_floor`, monotonic across falls. The tower is
##      the teacher, so the tower is the shop. This is the axis that carries most of
##      the roster because it is the only one that says "you went somewhere new".
##   2. **LEVEL** — `level_for_xp(GameState.xp())`, the curve at the top of this file.
##      Time served, not distance. It pays out for the player who fights everything on
##      a floor they have already beaten, which depth deliberately does not.
##   3. **THE CLASS YOU ARE** — the roster itself, gated by the guardian PICK mechanic
##      that already exists above (`LOCKED_CLASSES` / `CLASS_UNLOCK_FLOORS` /
##      `GameState.pending_class_choices`). A piece keyed to a class is that class's
##      identity; you hold it while you are them. **No pick is spent on gear** — the
##      banked pick still buys exactly one thing, a class, and this table never
##      touches `pending_class_choices`.
##
## ⚠ AND NOTHING HERE INVENTS A SPEND. `docs/superpowers/specs/2026-08-04-spell-trees-
## and-progression-design.md` reserves the one spendable currency (Skill Points, tree
## only). Every condition below is a THRESHOLD you pass, never a resource you burn, so
## the tree can be built later without this having taken anything from it.

## The three states a row can be in. `EARNABLE` is the one that has to carry a
## sentence — a locked row that does not say the verb is worse than no row at all.
enum Owned { HELD, EARNABLE, CLASS_LOCKED }

## ⚠ SPELLS ARE GATED BY **SHELF AND DEPTH**, DERIVED — never by an id list, and never
## by class. Both halves of that are load-bearing:
##
##   * DERIVED, like `Outfitter._can_equip_here`: the shelf comes from `SpellTier.of`,
##     which reads cast time / cooldown / mana. Re-tune a Tier 2 up into ult territory
##     and its gate moves with it, from the one edit. A hardcoded list here would drift
##     and the drift would look like a row that lies.
##   * **NOT BY CLASS, AND THAT IS THE MAKER'S OWN STANDING RULING** — *"the classes
##     should amplify current spells but it shouldnt prevent any player for taking any
##     spell"* (see `SpellLibrary.equippable`). So `Owned.CLASS_LOCKED` is DELIBERATELY
##     UNREACHABLE for a spell. It is a real state, it is drawn, and it is exercised —
##     by GEAR, where a class signature is the point, and by the roster itself. The
##     grimoire showing two states rather than three is the ruling being kept, not a
##     hole in this table.
##
## ⚠ INDEXED BY `SpellTier.Tier`, WHICH IS QUICK / HEAVY / ULT — three shelves, not four.
## Written as a bare array rather than a dictionary so a shelf inserted between HEAVY and
## ULT (which `SpellTier`'s own header says is the expected growth) is a compile-visible
## gap here rather than a silent fall-through to floor 1.
##
## QUICK at floor 1 means the shallow shelf is HELD from the first step: a fresh save can
## already swap its hand, which is what stopped the pool reading as decoration.
## ⚠ THE FIRST DRAFT GATED HEAVY AT FLOOR 4 AND IT WAS WRONG — MEASURED, not felt.
## `SpellLibrary.equippable()` is the Tier 2s, the Tier 3s and the orphans, and NOT ONE
## of the eighteen is a QUICK: they are all HEAVY or ULT. So a floor-4 HEAVY gate made a
## brand-new climber open the grimoire to eighteen locked rows, which is not "legible
## progression", it is the wall the maker's *"it shouldnt prevent any player for taking
## any spell"* ruling exists to forbid. `slice_test_outfitter` counts the two buckets on a
## fresh save, which is how this surfaced at all.
##
## What is gated is therefore the ULT SHELF only: the one finisher a hand carries. Every
## other row is HELD from the first step, one row in the list reads EARNABLE with the verb
## on it, and the maker gets the three states without losing the library.
const SPELL_UNLOCK_FLOOR: Array[int] = [
	1,    # QUICK — none exist in the pool today; free if one is ever authored
	1,    # HEAVY — the body of the library, HELD from the first step
	5,    # ULT   — the finisher, and the only shelf the climb actually gates
]

## ⚠ MEASURED, AND THE MAKER SHOULD SEE THE NUMBER BEFORE ACCEPTING IT. On a brand-new
## save `slice_test_outfitter` prints **2 held, 16 earnable of 18**: `SpellTier.of` derives
## the shelf from cast time / cooldown / mana, and sixteen of the eighteen pool spells are
## big enough to read as ULTs. So "gate only the ult shelf" is, today, gating most of the
## visible list — which is a far heavier gate than the sentence sounds like.
##
## IT IS SHIPPED ANYWAY, for two reasons, and the dial is one integer:
##   * Those sixteen can only ever enter the ULT SLOT (`set_equipped` refuses them
##     anywhere else), and every class already HAS an ult. Nothing is taken away; what is
##     deferred is SWAPPING your finisher, until floor 5.
##   * A gate nobody meets is a gate nobody can read, and the ask was to make unlockability
##     legible. Floor 5 is one short climb.
## Lower this to 2 or 3 if playtest says the grimoire reads as a wall on a first open.

## GEAR. Exactly one key per row — `floor`, `level` or `class` — because a piece with
## two conditions cannot state itself in the six words a phone row has.
##
## ⚠ THE SHAPE OF THE SPREAD IS THE DESIGN, not the individual numbers. Every slot
## opens with ONE free piece, so the armoury is never a wall of grey on a fresh save;
## the rest fans out across all three axes so no single kind of play buys the whole
## shelf. The numbers themselves are first-pass and unplayed — they are the cheapest
## thing here to move.
const GEAR_UNLOCK: Dictionary = {
	# --- spellements (the `weapon` slot) ---
	"pl_emberglass":   {"floor": 1},
	"pl_rimeshard":    {"floor": 2},
	"pl_stormtooth":   {"floor": 4},
	"pl_gravewick":    {"level": 4},
	"pl_sunmote":      {"class": 4},    # CLERIC — a mend on a cast is the Cleric's whole read
	"pl_voidpin":      {"class": 7},    # WARLOCK — dragging bodies to a point is the hex
	"pl_quickthread":  {"level": 8},
	"pl_echostone":    {"floor": 8},
	# --- helms (the `head` slot) ---
	"pl_veilhood":       {"floor": 1},
	"pl_ironbrow":       {"floor": 3},
	"pl_seers_circlet":  {"level": 5},
	"pl_crown_of_hours": {"floor": 10},
	# --- armour (the `body` slot) ---
	"pl_tideweave":  {"floor": 1},
	"pl_ashplate":   {"floor": 3},
	"pl_thornmail":  {"level": 6},
	"pl_stormcoat":  {"class": 6},      # STORMCALLER — the coat IS the class's silhouette
	# --- greaves (the `legs` slot) ---
	"pl_swiftsoles":  {"floor": 1},
	"pl_ironmarch":   {"floor": 5},
	"pl_ashenstride": {"level": 7},
}


## ⚠ THE SAME ESCAPE HATCH `ALL_CLASSES_UNLOCKED` IS, AND FOR THE SAME REASON. True =
## every row reads HELD and nothing is refused; the table above still answers, so the
## three states stay TESTABLE (`slice_test_unlocks` drives `state_of` directly and never
## reads this flag) and flipping it costs no save migration.
##
## FALSE is shipped, and that is the difference from the class flag. The maker asked to
## see all nine classes *"for now"* mid-balance-pass, which is a request to remove a
## gate. This ask is the opposite one — *"still not clear what is unlockable and what
## isnt"* presupposes that some things are — so the honest read of the newer instruction
## is gates ON. If playtest says otherwise this is the one-line revert.
const ALL_GEAR_UNLOCKED: bool = false


## The state of one gear id. `hero_class` is who you are RIGHT NOW — a class-keyed piece
## is HELD while you are that class and CLASS_LOCKED the moment you walk away from it,
## which is the point: it is the class's identity, not a trophy you keep.
##
## An id with no row is HELD. Silent-default holes are how a registry starts lying, so
## `slice_test_unlocks` asserts every offered id HAS a row — but a missing one must fail
## OPEN (you can wear it) rather than closed (an item nobody can ever reach).
static func gear_state(kind: String, highest_floor: int, level: int, hero_class: int) -> int:
	if ALL_GEAR_UNLOCKED or kind == "":
		return Owned.HELD
	var cond: Dictionary = GEAR_UNLOCK.get(kind, {})
	if cond.is_empty():
		return Owned.HELD
	if cond.has("class"):
		return Owned.HELD if hero_class == int(cond["class"]) else Owned.CLASS_LOCKED
	if cond.has("floor"):
		return Owned.HELD if maxi(highest_floor, 1) >= int(cond["floor"]) else Owned.EARNABLE
	if cond.has("level"):
		return Owned.HELD if maxi(level, 1) >= int(cond["level"]) else Owned.EARNABLE
	return Owned.HELD


## The state of one spell, by SHELF. `already_equipped` grandfathers a spell that is
## sitting in the player's hand from before this table existed — a gate that retroactively
## confiscates something is a bug that reads as a lost save, and there is no upside to it.
static func spell_state(tier: int, highest_floor: int, already_equipped: bool = false) -> int:
	if already_equipped:
		return Owned.HELD
	var need: int = spell_unlock_floor(tier)
	return Owned.HELD if maxi(highest_floor, 1) >= need else Owned.EARNABLE


static func spell_unlock_floor(tier: int) -> int:
	if tier < 0 or tier >= SPELL_UNLOCK_FLOOR.size():
		return 1
	return SPELL_UNLOCK_FLOOR[tier]


## THE VERB, and it is a verb on purpose. "Floor 5" is a label; "Reach floor 5" is an
## instruction, and the maker's ask was *how* to unlock it. `class_name_of` is passed in
## rather than looked up so this file stays free of the roster's display strings.
static func gear_unlock_verb(kind: String, class_names: Array = []) -> String:
	var cond: Dictionary = GEAR_UNLOCK.get(kind, {})
	if cond.is_empty():
		return ""
	if cond.has("class"):
		var ci: int = int(cond["class"])
		var who: String = String(class_names[ci]) if ci >= 0 and ci < class_names.size() else "another class"
		return "%s's own — play as the %s" % [who, who]
	if cond.has("floor"):
		return "Reach floor %d" % int(cond["floor"])
	if cond.has("level"):
		return "Reach level %d" % int(cond["level"])
	return ""


static func spell_unlock_verb(tier: int) -> String:
	return "Reach floor %d" % spell_unlock_floor(tier)


## THE SAME FACT, SHORT ENOUGH FOR A BUTTON. Not a duplicate of `gear_unlock_verb` — a
## different SURFACE for it, and the difference was measured rather than guessed: the full
## verb on the caption made the armoury's HFlowContainer wrap an extra line per row and
## pushed a quarter of the visible menu out of the 158 px bounded scroll
## (`slice_test_armory_layout` counts the buttons still on screen and went from 10 to 8).
## The button is the SCAN — enough to know a row is locked and roughly by what; the detail
## pane under it still carries the whole sentence.
static func gear_unlock_short(kind: String, class_names: Array = []) -> String:
	var cond: Dictionary = GEAR_UNLOCK.get(kind, {})
	if cond.is_empty():
		return ""
	if cond.has("class"):
		var ci: int = int(cond["class"])
		return String(class_names[ci]) if ci >= 0 and ci < class_names.size() else "class"
	if cond.has("floor"):
		return "floor %d" % int(cond["floor"])
	if cond.has("level"):
		return "lvl %d" % int(cond["level"])
	return ""
