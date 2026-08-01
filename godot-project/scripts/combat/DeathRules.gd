class_name DeathRules
extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════════
## WHAT DYING COSTS. THE ONE PLACE. FLIP THESE AFTER PLAYING, NOT BEFORE.
## ═══════════════════════════════════════════════════════════════════════════════
##
## THE RULE (maker, 2026-08-01, verbatim):
##   "dying cost is a life in ghost form until your teammate revives you;
##    if you all die then the game is over"
##
## That replaces the old rule (die -> drop one floor, keep climbing). A death no
## longer moves you down the tower at all — it takes you OUT OF THE FIGHT until
## someone picks you up, and the party running out of bodies is what ends the run.
##
## Every number below is REASONING, NOT FEEL. Two of them are decisions the maker
## asked to have surfaced rather than buried, and they are the first two blocks.

# ═══════════════════════════════════════════════════════════════════════════════
# SURFACED DECISION 1 — WHAT HAPPENS WHEN YOU DIE ALONE
# ═══════════════════════════════════════════════════════════════════════════════
## Solo has no teammate, so "ghost until revived" has no exit. Something has to
## give, and there are three honest answers:
##
##   A. DEATH ENDS THE RUN IMMEDIATELY.            <- SHIPPED DEFAULT (charges = 0)
##   B. A SELF-REVIVE CHARGE — one free comeback per run.      (charges = 1, 2, …)
##   C. A COUNTDOWN — drift as a ghost for N seconds, then the run ends anyway.
##
## WHY A. The brief for this game is "action packed, so much going on, endorphin
## chasing", and the persistent climb means a solo game-over is *cheap*: you land
## in the hub and re-enter on the floor you were already on. So the fastest possible
## death->retry loop is the one that respects the brief, and C is strictly worse
## than A — it is A with waiting bolted on, and waiting is the exact failure mode
## this whole feature exists to avoid. B is genuinely tempting (Hades' Death
## Defiance is beloved for a reason), but it makes solo *easier* than co-op at the
## same floor, and it dilutes the thing that gives co-op its shape: that the only
## way back up is another person. Ship A; the knob below makes B one edit away.
##
## SET THIS TO 1 AND SOLO GETS ONE FREE COMEBACK PER RUN. It is not aspirational —
## `Hero._enter_downed` reads it, spends a charge, and schedules a SECOND WIND
## (`SECOND_WIND_DELAY` seconds as a ghost, then back up at `REVIVE_HP_FRACTION`).
## `Arena._check_party_wipe` will not call the run while a charge is still resolving.
## Charges are per-hero and per-run, and they work in co-op too — which is exactly
## why the default is 0: at 1, a co-op party effectively has four lives, not two.
const SOLO_SELF_REVIVE_CHARGES: int = 0

## The ghost beat before a self-revive charge fires. Long enough that the death
## READS (you see yourself get rubbed out), short enough that it is a gasp and not
## a wait.
const SECOND_WIND_DELAY: float = 1.1

# ═══════════════════════════════════════════════════════════════════════════════
# SURFACED DECISION 2 — WHAT GAME OVER COSTS THE PERSISTENT CLIMB
# ═══════════════════════════════════════════════════════════════════════════════
## The maker explicitly likes the persistent climb: `GameState` keeps `_floor`,
## `_highest_floor`, `_falls` and `tower_conquered` in `user://climber.json`, and
## re-entering the tower resumes where you left off. A wipe has to cost SOMETHING
## or the floor is meaningless, and there are two shapes for that cost:
##
##   A. THE RUN ENDS, THE CLIMB IS KEPT.  <- SHIPPED DEFAULT (reset = false)
##      Back to the hub; `_falls` ticks; the town clocks it (the NPC memory layer
##      already turns that number into "that is 4 falls now"); re-enter on the same
##      floor. The cost is the fight you lost, the trip home, and being roasted.
##
##   B. THE CLIMB RESETS TO FLOOR 1.      (reset = true — the roguelite reading)
##      Much harsher. Makes floor 5 mean something. Also makes a bad 40 seconds
##      delete an hour, on a phone, in a game whose brief is short bursts of chaos.
##
## WHY A. This was already decided once — the maker's own words were "NO roguelite
## reset -> a PERSISTENT Tower-of-God climb", and a party wipe is not a good enough
## reason to reverse a locked design call by accident. It also keeps the thing that
## makes this project's moat legible: the town remembering a growing fall count is
## only interesting if you keep coming back to the same height.
##
## `_highest_floor` is monotonic and is NEVER touched by either policy — the tower
## remembers your best whatever happens.
const RESET_CLIMB_ON_GAME_OVER: bool = false


## Which floor you resume on after a wipe. Pure + static so it tests headlessly and
## so the policy above has exactly one implementation.
static func resume_floor_after_game_over(current: int, total: int) -> int:
	var cap: int = maxi(total, 1)
	if RESET_CLIMB_ON_GAME_OVER:
		return 1
	return clampi(current, 1, cap)


# ═══════════════════════════════════════════════════════════════════════════════
# The rest: the shape of a death, not a policy fork.
# ═══════════════════════════════════════════════════════════════════════════════
## How long the GAME OVER card holds before the run actually ends. It is a beat,
## not a loading screen — long enough to read the word and see who fell.
const GAME_OVER_HOLD: float = 2.4

## A revive brings you back at a FRACTION of max hp, never full.
##
## ⚠ THIS IS THE WHOLE BALANCE OF THE MECHANIC. At 1.0 a revive is strictly better
## than not dying (you get a full heal out of it) and the correct play becomes
## suiciding into the boss to top up. At 0.45 you are up, you are in the fight, and
## you are one mistake from being a ghost again — which is the tension the rule
## "if you all die then the game is over" needs in order to bite.
const REVIVE_HP_FRACTION: float = 0.45


## Hp to come back with. Never zero — a revive that lands you dead is not a revive.
static func revive_hp(max_hp: int) -> int:
	return maxi(1, int(round(float(maxi(max_hp, 1)) * clampf(REVIVE_HP_FRACTION, 0.05, 1.0))))
