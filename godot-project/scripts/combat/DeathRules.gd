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


## ⚠ HOW FAR BACK A WIPE SENDS YOU — the third policy, and it sits between A and B.
##
## Maker, 2026-08-04: "save slots every 10 levels so if you died at 15 you can
## restart at 10 with that friend".
##
## Resuming on the SAME floor (the old policy A) costs a fight and a trip home and
## nothing else; resetting to 1 (policy B) deletes an hour. A checkpoint band is the
## middle: you lose the floors you gained INSIDE the band, and you keep the bands
## you finished.
##
## ⚠ AND IT QUIETLY SOLVES CO-OP PROGRESSION, which is why it is worth more than a
## difficulty dial. Two players in the same band already resume at the SAME floor,
## so "whose climb does the party play" never has to be asked, decided or stored.
## No party save track, no host-decides-progress, no boosting. A re-tread can only
## happen across a band boundary, which the maker has ruled acceptable.
##
## Set to 5 against a 10-floor tower rather than the maker's stated 10, because the
## tower is deliberately short while the combat is unproven — see the spec at
## docs/superpowers/specs/2026-08-04-tower-shape-and-feel-design.md §1.4. THIS
## CONSTANT AND `GameState.TOTAL_FLOORS` ARE THE ONLY TWO NUMBERS that need to move
## to reach the 30-floor / 10-band shape. That is the whole reason they are
## constants and not arithmetic sprinkled through the climb.
const CHECKPOINT_BAND: int = 5


## The floor a climber restarts from, given where they got to. Floors 1-5 -> 1,
## 6-10 -> 6. Pure + static: this is the band arithmetic's ONE implementation, and
## the co-op party start reads it too.
static func checkpoint_for(floor: int) -> int:
	var band: int = maxi(CHECKPOINT_BAND, 1)
	var f: int = maxi(floor, 1)
	@warning_ignore("integer_division")
	return ((f - 1) / band) * band + 1


## Which floor you resume on after a wipe. Pure + static so it tests headlessly and
## so the policy above has exactly one implementation.
static func resume_floor_after_game_over(current: int, total: int) -> int:
	var cap: int = maxi(total, 1)
	if RESET_CLIMB_ON_GAME_OVER:
		return 1
	return checkpoint_for(clampi(current, 1, cap))


# ═══════════════════════════════════════════════════════════════════════════════
# The rest: the shape of a death, not a policy fork.
# ═══════════════════════════════════════════════════════════════════════════════
## The beat between the party wiping and the GAME OVER card offering you a way out.
##
## ⚠ HALVED ON THE MAKER'S CALL (2026-08-04): "the death screen is too long and not
## fun to look at". The old value was 2.4 s and the old comment defended it as "long
## enough to read the word and see who fell" — that reasoning lost to play. At 1.2 s
## the word still lands and the fight still visibly stops before anything moves.
##
## ⚠ AND IT NO LONGER GATES THE RUN ENDING, ONLY THE CARD'S BUTTONS. It used to be a
## countdown you sat through with nothing to do; it is now the pause before the two
## exits fade in, which also makes it the guard against a key still held from the
## fight choosing for you. See `Arena._show_game_over`.
const GAME_OVER_HOLD: float = 1.2

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
