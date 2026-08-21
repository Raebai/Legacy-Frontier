class_name BotBrain
extends RefCounted
## THE BOT BRAIN — three layers of pure math over a blackboard, producing one
## intent dictionary per frame. No nodes, no tree, no signals, no LLM.
##
## ---------------------------------------------------------------------------
## THE THREE LAYERS, AND HOW THEY COMPOSE
##
##   1. REFLEX      (BotDodge)  — "is something about to hit me, and what is the
##                  shortest way out". Runs first and PREEMPTS: a bot that finishes
##                  its cast animation inside a meteor is not a bot anyone believes.
##                  Pure threat geometry; already its own module.
##   2. STEERING    (_steer)    — "where do I want to stand". A spacing band per
##                  class, blended against danger: telegraph footprints, pit rects,
##                  and cover. Flattened to move.x because this is a side-on
##                  platformer — vertical intent becomes a jump, not a Y velocity.
##   3. UTILITY     (_score_slots) — "what do I press". Every ready slot is scored
##                  against the situation and the best one wins, if it clears a
##                  threshold. This is the layer that makes the bot use its whole
##                  kit instead of throwing its damage line at the wall.
##
## They compose by PRIORITY, not by blending: the reflex layer can veto the other
## two outright (you do not cast while diving out of a blast), steering always
## contributes movement (moving is free — it never conflicts with a cast), and the
## utility layer is the only thing allowed to press a button. Guard is the one
## exception in the other direction: MeleeClash's locked rule is that guarding
## locks out attacking, so a held guard suppresses fire and cast in the same frame.
##
## WHY THIS SHAPE AND NOT GOAP OR A BEHAVIOUR TREE. Attack wind-ups here are
## 0.35-0.9 s and every telegraph RE-SNAPSHOTS its target when the wind-up starts,
## so a plan older than about a second is already describing a fight that no longer
## exists. Utility re-scores from the live blackboard every `period` seconds and
## therefore cannot hold a stale plan; a tree would encode the same decisions as
## structure, where they are far harder to retune than a weights table.
##
## ---------------------------------------------------------------------------
## FAIRNESS IS STRUCTURAL. The brain is handed a blackboard built from what is on
## screen and a profile built from BotProfile — and it has NO other input. It
## cannot query the world, cannot read a private field, cannot see an untelegraphed
## attack. Difficulty is reaction delay and error rate (BotProfile), never
## knowledge and never stats. Aim carries a bounded error at EVERY tier because
## no-auto-aim is a locked project rule: the bot points, and it can miss.
##
## COST. This runs per bot per frame. The reflex layer is a handful of dot products
## over the visible threats; the expensive layer (utility, which touches the kit
## table) is rate-limited to once per `profile.period` and LATCHED in between — so
## the per-frame cost in the common case is the reflex pass and a vector subtract.
##
## ---------------------------------------------------------------------------
## THE CONTRACT (fixed by the caller; another module builds the body seam against
## it, so nothing here may drift from it).
##
##   BotBrain.decide(bb: Dictionary, profile: Dictionary, mem: Memory = null)
##       -> Dictionary
##
## INTENT out — every key OPTIONAL, missing means "no":
##   "move": Vector2   x in [-1,1] walk; y < 0 means "wants up"
##   "aim":  Vector2   normalised world aim direction
##   "fire": bool      the LMB primary (a bolt on six classes, fists on three)
##   "swing": bool     the MELEE button — a different button from `fire` on every
##                     class, and one no brain pressed until the Q/R/T pass
##   "cast_slot": int  0..SLOT_COUNT-1; slot 0 is always the damage line and the
##                     last slot is always the ult (omitted entirely = no cast)
##   "ability_blast"/"ability_blink"/"ability_nova": bool   Q / R / T
##   "dash": bool
##   "guard": bool     HELD this frame
##   "jump": bool
##
## BLACKBOARD in — the guaranteed minimum, all of it screen-visible:
##   "self_pos", "self_vel": Vector2; "self_hp_frac", "self_mp_frac": float
##   "on_floor": bool; "facing": float
##   "foe_pos", "foe_vel": Vector2; "foe_hp_frac", "foe_facing": float
##   "threats": Array    telegraph / projectile descriptors (see _normalise)
##   "cooldowns": Array  float per slot, 0.0 = ready
##   "reach": float; "now": float
##
## ...plus these OPTIONAL enrichments. Every one of them is inert when absent, so
## a caller that supplies only the minimum gets a working bot — a duller one.
##   "class_id": int          Hero.HeroClass. Unlocks the real kit (elements, cast
##                            times, ranges, costs) via SpellLibrary, and with it
##                            the channel-safety gate and every combo set-up.
##   "hazards": Array[Rect2]  pit footprints. Without them the bot will dodge into
##                            a pit, so this is the one enrichment worth insisting on.
##   "fields": Array          live ground effects: {element:int, pos, radius, mine:bool}.
##                            The other half of the combo layer.
##   "barriers": Array        live walls: {element:int, pos, radius}.
##   "pickups": Array[Vector2] uncollected spell drops on the floor. Without them a
##                            bot walks past every Tier 2 / Tier 3 upgrade in the run.
##   "slot_affordable": Array[bool]  does slot i EXIST on this body and is it off
##                            cooldown. Strictly stronger than `cooldowns[i] == 0`,
##                            which reports a slot the class does not hold as ready.
##   "slot_cast_time": Array[float]  the LIVE channel length per slot, which a drop
##                            changes at runtime under the cached kit facts.
##   "foe_guarding": bool     is their ring up RIGHT NOW (present tense only).
##   "dash_ready", "blink_ready", "guard_ready": bool
##   "guard_style": int       0 BLADE / 1 SIGIL (ParryRing.Style) — different band.
##   "can_parry": bool
##   "mem": Memory            see the note on Memory below.

# ---------------------------------------------------------------- slot roles
## SLOT INDEX STILL CARRIES A ROLE MEANING, but a weaker one than it used to, and the
## difference is worth reading before touching the scorer.
##
## It used to be exact: kits were five spells emitted in `SpellLibrary.ROLE_ORDER`, so
## slot 1 was ALWAYS "control" for every class in the game. Kits are `SLOT_COUNT` spells
## (the right thumb has three buttons), and which three a class carries is chosen per
## class from its fantasy — so slot 1 is "control" for the Arcanist, "answer" for the
## Brawler and "payoff" for the Shadowblade.
##
## What SURVIVES, and what the scorer actually relies on:
##   slot 0            — ALWAYS the damage line. Every class carries it.
##   slot SLOT_COUNT-1 — ALWAYS the ult. Every class carries it, and
##                       `SpellTier.slot_accepts_ult` enforces the shelf.
##   the middle slot   — the class's ONE non-damage, non-ult tool, whichever of
##                       control / answer / payoff its fantasy names.
## So "reach for my utility spell" is still a fixed index; "reach for my WALL
## specifically" is not, and never was reliable anyway — the control role answers with
## an ice wall, a shadow root or a rock pillar depending on the class. A brain that
## wants the exact role asks `SpellLibrary.slot_roles_for_class(class_id)`; the facts
## table below already carries the per-spell properties that made the role a proxy for.
const ROLE_DAMAGE: int = 0
## The single utility slot. The three old aliases all point at it because a class
## carries exactly ONE of control / answer / payoff, so "give me my control spell" and
## "give me my answer" are now the same question with the same honest answer.
const ROLE_UTILITY: int = 1
const ROLE_CONTROL: int = ROLE_UTILITY
const ROLE_ANSWER: int = ROLE_UTILITY
const ROLE_PAYOFF: int = ROLE_UTILITY
const ROLE_ULT: int = BotIntent.SLOT_ULT
## Derived, never a literal: the hand size is owned by `SpellTier.SLOT_COUNT` and a
## second copy of it here is exactly how the two would drift.
const SLOT_COUNT: int = BotIntent.SLOT_COUNT

## EXTRA COOLDOWN INDICES, past the castable slots. The body seam publishes a
## longer `cooldowns` array than the brain strictly needs: after the kit slots it
## appends the primary attack, the dash, the guard, the three ability buttons and
## the melee swing, because a brain has to know whether those are ready before
## committing to a plan — but they are NOT reachable through `cast_slot` (the
## primary is held and the dash is an edge, so folding them into the slot numbering
## would make one index mean two kinds of press).
##
## ⚠ DERIVED FROM `BotIntent`, NEVER RESTATED — and this file used to restate them.
## They were written as the literals 5 / 6 / 7 back when the hand was five spells
## and `SLOT_COUNT + 1` happened to be 6. The hand is `SpellTier.SLOT_COUNT` spells, so the body publishes primary at 3, dash at 4 and guard
## at 5 — and the brain was reading the GUARD timer to decide whether its fists were
## ready, the BLAST timer to decide whether it could dash, and the BLINK timer to
## decide whether it could parry. Every one of those reads was silently wrong for
## every bot in the game. Aliasing the seam's own constants makes the next hand-size
## change a no-op here instead of a second silent drift.
const CD_PRIMARY_INDEX: int = BotIntent.CD_PRIMARY
const CD_DASH_INDEX: int = BotIntent.CD_DASH
const CD_GUARD_INDEX: int = BotIntent.CD_GUARD
const CD_BLAST_INDEX: int = BotIntent.CD_BLAST
const CD_BLINK_INDEX: int = BotIntent.CD_BLINK
const CD_NOVA_INDEX: int = BotIntent.CD_NOVA
const CD_SWING_INDEX: int = BotIntent.CD_SWING

# ------------------------------------------------------------ body constants
## Mirrors of the hero's own numbers. They are COPIES on purpose: this module must
## stay pure (no Hero import, no autoload) so it is headless-testable and can drive
## an Enemy body as easily as a hero one. Each is annotated with its source so a
## retune over there is a one-line find here.
const DASH_DIST: float = 86.8          # Hero.DASH_SPEED 620 * DASH_TIME 0.14
const DASH_COOLDOWN: float = 0.9       # Hero.DASH_COOLDOWN
const BLINK_DIST: float = 175.0        # Hero.BLINK_DISTANCE
const BLINK_COOLDOWN: float = 1.3      # Hero.BLINK_COOLDOWN
const MELEE_COOLDOWN: float = 0.34     # Hero.MELEE_COOLDOWN
## ParryRing's shrinking-ring geometry. The guard is HELD, and its perfect band
## opens LATE in the shrink — so pressing on reaction to a hit is always too late.
## The brain must press EARLY, timed so the blow arrives inside the band; these
## are the two moments to aim impact at.
const GUARD_SHRINK: float = 0.42       # ParryRing.SHRINK_TIME
const GUARD_BAND_BLADE: float = 0.374  # midpoint of PERFECT_START 0.78 .. 1.0
const GUARD_BAND_SIGIL: float = 0.392  # midpoint of SIGIL_PERFECT_START 0.865 .. 1.0
const GUARD_REARM_BLADE: float = 0.35  # ParryRing.REARM_TIME
const GUARD_REARM_SIGIL: float = 0.55  # ParryRing.SIGIL_REARM_TIME
const GUARD_HOLD_TAIL: float = 0.06    # keep holding a hair past the band

# ------------------------------------------------------------ brain tunables
## How far past a channel's cast_time the board must stay clear before the brain
## will commit to it. A channel is interrupted by ANY landed hit, so starting one
## with a threat resolving at cast_time + epsilon is just donating the spell.
const CHANNEL_MARGIN: float = 0.25
## Minimum utility a slot must reach before the brain spends it. Below this it
## would rather walk and keep the cooldown, which is what stops a bot dumping its
## ult into an empty arena the instant it comes off cooldown.
const CAST_THRESHOLD: float = 0.20
## The anti-spam term. Re-using the slot you just used is penalised, decaying over
## RECENCY_TAU seconds. This is the single term that most visibly turns "throws its
## damage line forever" into "plays its kit".
##
## IT IS THE SECOND VARIETY SOURCE, NOT THE FIRST. Real cooldowns do most of this
## work — a kit whose slots are on 3-6 s timers cannot be spammed. What this term
## covers is the window INSIDE a cooldown where two slots are both ready and one of
## them was just thrown: without it the higher-scoring of the two wins every single
## time, measured at 21 of 24 casts on one slot in a cooldown-free scenario. 0.70 was
## picked because 0.55 left the damage line above every other role's base even while
## penalised, so the rotation never started at all.
const RECENCY_PENALTY: float = 0.70
const RECENCY_TAU: float = 2.5
## How long a chosen cast / dodge is held before the brain is allowed to change its
## mind. Re-deciding every frame is what makes bots twitch, and a cast that is
## re-picked mid-wind-up never comes out at all.
## ⚠ 0.22 -> 0.55. Maker, after the first pacing pass: *"again slightly increase
## their spell cooldown I think thats important"*. The previous pass gated the PRIMARY
## (`FIRE_SPACING`) and the three ability buttons (`ABILITY_SPACING`) but left the KIT
## untouched, so the loudest things on screen — the authored spells with the magic
## circles — still went out as fast as `profile.period` allowed, which at the tier
## Watch Bots runs is every 0.22 s.
##
## This is a MINIMUM GAP BETWEEN KIT CASTS, not a change to any spell's own cooldown:
## the per-spell cooldowns, mana costs and the global cast lockout are all untouched
## and still apply underneath. A bot simply no longer chains its whole kit as fast as
## the scorer can name the next entry. It is also the dial that gives the magic
## circles room to be SEEN, which is most of what makes them worth drawing.
# ══ THE RHYTHM — RAISED 2026-08-19 ═════════════════════════════════════════
# Maker, watching bot fights: *"they are spamming spells too much it makes it hard
# to follow what they are doing"*.
#
# ⚠ THIS WAS ATTEMPTED ONCE AND REVERTED, and the reason it stuck this time is that
# the maker has now made the call the revert was waiting on. `docs/PLAYTEST-QUEUE.md`
# records the first attempt: raising these four dials failed `slice6_test_bot_brain`,
# which asserts a bot lands >= 12 casts across a neutral window, and the note ends
# "that guard encodes 'a bot must not go quiet' and the maker is asking for exactly
# fewer casts, so loosening it is a JUDGEMENT CALL, not a test-fixing chore."
#
# ⚠ AND THE COOLDOWNS THEMSELVES ARE STILL NOT THE LEVER. The same note: the spells'
# own cooldowns are the PLAYER's numbers too, so slowing them nerfs every class in
# the tower to fix a spectating problem. These four are the bot's SELF-IMPOSED
# rhythm and nothing else reads them, so a slower bot fight costs a human player
# nothing. The one global change that does touch both is `Hero.GLOBAL_CAST_LOCKOUT`,
# which is a floor on chaining rather than a nerf, and is argued at its own constant.
#
# ⚠ ONLY TWO DIALS MOVED, AND `slice_test_bot_rhythm` IS WHY.
#
# The first version of this change raised FOUR of them — CAST_LATCH to 0.85 and the
# BREATHE trio as well — and that guard caught the first one with a message left by
# the previous attempt: CAST_LATCH is the ONE pacing dial that
# `slice6_test_bot_brain`'s `>= 12 casts` assertion constrains, raising it "is what
# made the last attempt at this fail three times", and FIRE_SPACING / ABILITY_SPACING
# are invisible to that guard while emitting far more of what actually reads as spam.
#
# It was right, and it was worth isolating rather than believing: with CAST_LATCH put
# back the count was still 9, so the remaining loss was tested one dial at a time and
# it was BREATHE — reverting the breathe trio alone restored the count with both
# spacing dials still doubled. So the pacing the maker asked for comes entirely from
# FIRE_SPACING (0.60 -> 1.25) and ABILITY_SPACING (1.05 -> 2.10), the >= 12 guard is
# untouched and still passing, and no test was loosened to land this.

## ⚠ 0.55 -> 1.10 ON THE MAKER'S SECOND ASK, AND THIS IS THE DIAL THEY DESCRIBED.
## *"no need to spam abilities like 3 in a 2 second window play smart"* — 0.55 s
## permits exactly three casts in two seconds, which is the number they counted.
## 1.10 permits two.
##
## `slice_test_bot_rhythm` guarded this at <= 0.60 and `slice6_test_bot_brain` demands
## >= 12 casts in a neutral window; both are relaxed in the same commit, deliberately,
## with the reasoning recorded at each. That guard was written to stop a change like
## this being made CASUALLY, and it worked — the first attempt today was casual and it
## caught it. This one is the maker asking twice, by name, for fewer casts.
const CAST_LATCH: float = 1.10
const DODGE_LATCH: float = 0.29        # dash 0.14 + a short lockout

# ── TRAVERSAL DASH — see `_traverse_dash` ───────────────────────────────────
## A floor on the gap between traversal dashes, ON TOP of the body's own cooldown.
## The cooldown alone is not a pace: this file's own warning is that trusting
## readiness "would show up in play as a bot dashing four times a second", and a
## class with a fast dash would do exactly that on every approach.
const DASH_TRAVEL_SPACING: float = 1.7
## How far away the foe has to be before walking is the wrong answer. Below this the
## bot is already in the fight and a dash would overshoot past them.
const DASH_CLOSE_MIN: float = 260.0
## How fast a body has to be moving AWAY from the fight, while airborne, before the
## dash counts as a recovery rather than as interrupting its own arc.
const DASH_RECOVER_SPEED: float = 60.0

## ══ REACHING SOMETHING THAT IS ABOVE YOU ═══════════════════════════════════════
## Maker: *"brawler would petrify an enemy in the air then not be able to reach them
## ... ensure that it can jump and punch as well or dash and punch"*.
##
## ⚠ THE BOT WAS NOT FAILING TO ATTACK. IT WAS ATTACKING AND MISSING, FOREVER. Every
## distance in this brain is a 2D `distance_to`, so a statue 60 px straight overhead
## reports dist 60 — INSIDE the Brawler's 35..70 band — and `_steer` reads "correct
## spacing, hold" and never takes a step. `_wants_swing` then passes on the same 2D
## number (60 <= 58*1.05) and the bot presses melee. But the hit test is a radius AND
## A FORWARD CONE (`SpellTargets.in_cone`, `MELEE_ARC_DOT` 0.3) and a hero's `facing`
## is horizontal, so a target straight up scores dot ~0.0 and is rejected every time.
## The bot stands under the statue punching the air until the petrify expires.
##
## Nothing above could have fixed it: `_steer`'s only vertical term is a dodge exit
## from a live threat, and a statue is not a threat (it publishes no telegraph, so it
## never enters `evaluated` at all); `_traverse_dash` early-returns whenever the x
## separation is under DASH_CLOSE_MIN, which is exactly the overhead case; and the
## only two writers of `intent["jump"]` in this file are a dodge and a wall-unstick.
## `move.y` is NOT a jump either — `BotController._actions_of` maps it to `move_up`,
## which `Hero` reads only for dash angles and aim.
##
## So this is a new rung with one job: get level with a foe that is above you.
## How much higher the foe must be before this is a vertical problem at all. Under
## this the ordinary walk-and-swing already works and a hop would just be noise.
const AIR_REACH_MIN_RISE: float = 46.0
## How far sideways the foe may be while this still applies. Beyond it the gap is
## mostly horizontal, walking is the right answer and `_steer` already owns it —
## jumping here would fire on every foe standing on any terrace on the map.
const AIR_REACH_MAX_SPAN: float = 150.0
## Inside this x separation the bot is aligned enough; it stops shuffling and jumps
## straight up rather than sliding out from under the target as it rises.
const AIR_REACH_ALIGN: float = 26.0
## ⚠ SPACED, FOR THE REASON THIS FILE ALREADY WARNS ABOUT. Gating on readiness alone
## "would show up in play as a bot dashing four times a second" — a jump re-armed
## every frame the foe is overhead is the same failure with a different button, and
## it reads as a bot vibrating under a ledge. One attempt, then commit to the arc.
const AIR_REACH_SPACING: float = 0.75
## Distance probed when scoring "which way should I step". A step shorter than this
## cannot leave a telegraph footprint, so scoring it would always tie.
const STEER_PROBE: float = 90.0
## Deadband on the spacing band, as a fraction of it. Without one the bot oscillates
## across the ideal distance forever, which reads as a stutter rather than a stance.
const BAND_DEADZONE: float = 0.16
## Minimum seconds a steering answer holds before it may REVERSE. Sits between
## DODGE_LATCH (0.29) and nothing, because a walk should commit for less time than a
## dodge does — long enough that a trade-heavy exchange cannot make the bot alternate
## at the hit rate, short enough that it never reads as ignoring you.
## UNTESTED GUESS on the exact value; the SHAPE is what the fix rests on.

## ══ NOBODY IS EVER FULLY STILL ═════════════════════════════════════════════════
## Maker: *"I dont think they should ever be fully standing still"*.
##
## ⚠ THE STATUE IS A REAL BRANCH, NOT A DROPPED FRAME. `intent` above resolves to 0
## whenever the bot is INSIDE its spacing band with no committed direction — which is
## the state a well-behaved bot spends most of a fight in, because holding the correct
## range is the whole job of the band. `want` then multiplies out to exactly 0.0 and
## the body plants, so the better the spacing logic worked, the more the fighter stood
## there like furniture.
##
## The answer is not to widen the band — that would break the spacing the band exists
## to hold. It is to keep WEIGHT MOVING while the spacing is held: a small shuffle
## around the spot the bot already wants to be on. It reads as a fighter jockeying and
## it changes the held distance by only a few px either way.
##
## ⚠ IT GOES THROUGH THE SAME DANGER SCORER AS A REAL STEP. Applied BEFORE the pit and
## telegraph probe below, deliberately: a shuffle that could walk a bot off a ledge
## would be a new way to die inventing itself out of an idle animation.
## How hard the settled shuffle pushes, as a fraction of full walk speed. Small enough
## to read as weight shifting rather than as walking somewhere.
const IDLE_JOCKEY: float = 0.30
## How fast it sways, in Hz. Slow — a fighter settling, not a fighter fidgeting.
const IDLE_JOCKEY_HZ: float = 0.55
const STEER_MIN_DWELL: float = 0.24
## Two of the caster's own spells fusing (ReactionTable's hollow_purple, the
## headline self-combo) needs the second beam thrown inside this window.
const FUSION_WINDOW: float = 1.1
## A threat closer than this many seconds counts as "pressure" at full weight.
const PRESSURE_HORIZON: float = 1.2

## Preferred spacing band per Hero.HeroClass — {min, max} px from the foe. This is
## the class's STANCE, and it is what makes an Arcanist read as an Arcanist: it
## wants to stand where its beam works and the foe's fists do not. Aggression
## (BotProfile) pulls the whole band toward contact, so an aggressive Arcanist
## fights closer than a cautious one without needing a second table.
##
## Indexed by Hero.HeroClass — MAGE 0, ROGUE 1, BRAWLER 2, JUGGERNAUT 3, CLERIC 4,
## CRYOMANCER 5, STORMCALLER 6, WARLOCK 7, SWORDSAINT 8.
## ⚠ FOUR OF THESE STOOD OUTSIDE THE CLASS'S OWN ATTACK RANGE. The table was authored
## from each class's FANTASY and never cross-checked against what its primary actually
## reaches (`CLASS_ABILITIES.primary`, or `Hero._melee_range * 1.1` when that is 0), so
## a bot could hold a stance from which it could not hit anything and then wonder why
## it was losing. Aggression scales the whole band by 0.91 at tier 3, which was not
## enough to rescue it. MEASURED, band top vs primary reach, before this pass:
##     CRYOMANCER  182-327  vs  200 (frost cone)   -> 31% win rate
##     BRAWLER      36-100  vs   66                -> 22%
##     SWORDSAINT   45-118  vs   95                ->  9%
##     JUGGERNAUT   73-200  vs  106                -> 50%
## Every band whose top already sat INSIDE its reach belonged to a class at >= 44%.
## Three of the four fixed here are the three weakest classes in a 288-bout table.
## FEEL: a Cryomancer that fights at 200 px instead of 360 is a different character —
## the maker judges whether it still reads as a zoner.
const CLASS_BAND: Array[Dictionary] = [
	{"min": 190.0, "max": 340.0},   # ARCANIST  — caster band
	# ⚠ 200 -> 165, AND THIS IS WHERE THE SHADOWBLADE'S HELP ACTUALLY COMES FROM.
	# HP was the obvious knob and it is capped at one point by a guarded invariant
	# (the assassin must stay the frailest body), so the honest lever is letting the
	# class REACH with the kit it has. `BladeFlurry` — its damage line — has a RANGE
	# of 100. The old band scaled by aggression 0.80 to 49-164 and centred the bot at
	# 107: outside the flurry, so `_range_fit` skipped the slot and the bot fell back
	# on its bolt while standing in the open. 55-165 scales to 45-135, centre 90,
	# which is inside the flurry with room to spare and still a WIDE band — the class
	# is "in and out" and must keep the room to be out.
	{"min": 55.0, "max": 165.0},    # SHADOWBLADE — in and out; the flurry reaches 100
	{"min": 35.0, "max": 70.0},     # BRAWLER   — contact; melee reaches 66
	{"min": 70.0, "max": 115.0},    # JUGGERNAUT— close; heavy swing reaches 106
	{"min": 120.0, "max": 260.0},   # CLERIC    — mid, tether range
	# ⚠ THE COMMENT WAS WRONG AND THE BAND WAS BUILT ON IT. It said "the frost CONE
	# only reaches 200"; `Hero._primary_frost_cone`'s `CONE_RANGE` is **118**. So the
	# authored band 120-210 scaled by aggression 0.80 (x0.82) to 98-172 and PARKED THE
	# BOT AT 135 — seventeen pixels outside the reach of its own primary attack, for
	# the whole fight. The only class in the roster whose LMB is a short hitscan cone
	# was the one class standing where it could not use it.
	#
	# That is the measurement, not a taste call: the Cryomancer read 39% / 28% / 31%
	# across three 288-bout sweeps, bottom three in two of them. This is a BUG FIX and
	# not a handicap — `BotMatch`'s own header forbids papering over a lopsided matchup
	# with a thumb on the scale, and a band derived from a reach that does not exist is
	# exactly the kind of thing it means.
	#
	# 80-150 scales to 66-123, centre 94: inside the cone with 24 px of margin for a
	# target that is moving. It stays a MID band — the class is still not a brawler.
	{"min": 80.0, "max": 150.0},    # CRYOMANCER— the frost cone reaches 118
	{"min": 170.0, "max": 320.0},   # STORMCALLER
	{"min": 150.0, "max": 300.0},   # WARLOCK   — attrition at tether range
	{"min": 45.0, "max": 95.0},     # SWORDSAINT— guard-and-punish; reaches 95
]
const DEFAULT_BAND: Dictionary = {"min": 150.0, "max": 300.0}

## ---------------------------------------------------------------------------
## THE THREE ABILITY BUTTONS (Q / R / T), per class.
##
## These were a whole third of the hero's offence that no bot had ever pressed. The
## intent keys existed (`BotIntent.ABILITY_*`) and `BotController` already knew
## which button each one is — the brain simply never emitted them, so every bot in
## the game fought with its kit and its fists and left Q, R and T on the floor.
##
## Mirrors of `Hero.CLASS_CONFIG`, annotated so a retune over there is a one-line
## find here. Three facts per class, and each one changes what the ability IS:
##   primary  how far the LMB attack reaches. `bolt` throws a projectile across the
##            stage; `frost_cone` is a short cone; `melee_combo` / `heavy_swing` are
##            the fists, so they use the body's own `reach`. 0.0 means "use reach".
##            Without this the fists gate (`_wants_fire`) held EVERY class to melee
##            distance, so a Cryomancer at its own preferred spacing never threw a
##            single basic attack.
##   blink    what R does: a real teleport, or a rising UPPERCUT (Brawler,
##            Swordsaint) which is a close-range attack and must not be used to
##            cross the stage. "" = the class has none worth pressing.
##   nova     does T exist at all (`has_nova`). The Shadowblade's is false.
const CLASS_ABILITIES: Array[Dictionary] = [
	{"primary": 620.0, "blink": "teleport", "nova": true},   # 0 ARCANIST    bolt
	{"primary": 560.0, "blink": "teleport", "nova": false},  # 1 SHADOWBLADE bolt x3 spread
	{"primary": 0.0,   "blink": "uppercut", "nova": true},   # 2 BRAWLER     melee_combo
	{"primary": 0.0,   "blink": "",         "nova": true},   # 3 JUGGERNAUT  heavy_swing, no blink
	{"primary": 600.0, "blink": "teleport", "nova": true},   # 4 CLERIC      heal-bolt
	{"primary": 200.0, "blink": "teleport", "nova": true},   # 5 CRYOMANCER  frost_cone
	{"primary": 620.0, "blink": "teleport", "nova": true},   # 6 STORMCALLER chain bolt
	{"primary": 600.0, "blink": "teleport", "nova": true},   # 7 WARLOCK     drain bolt
	{"primary": 0.0,   "blink": "uppercut", "nova": true},   # 8 SWORDSAINT  heavy_swing
]
const DEFAULT_ABILITIES: Dictionary = {"primary": 0.0, "blink": "teleport", "nova": true}

## Q — the class AoE. Every class has one; they are all placed or self-centred
## bursts, so the useful window is "the foe is close enough to be inside it but I
## am not standing on top of my own detonation".
const BLAST_MIN: float = 70.0
const BLAST_MAX: float = 430.0
## R-as-uppercut is a rising melee cut, so it only makes sense in contact.
const UPPERCUT_RANGE: float = 96.0
## R-as-teleport is used for two opposite jobs: closing a gap that is too big to
## walk, and leaving one that is too small. Both need the foe outside comfort.
const BLINK_CLOSE_MIN: float = 300.0
## T — a self-centred nova. Pure "get off me".
const NOVA_RANGE: float = 150.0
## Minimum gap between two ability presses of ANY kind. The cooldowns already pace
## each button; this stops all three going out on the same frame, which reads as a
## seizure rather than as a play.
## ⚠ 0.45 -> 0.80. Maker, watching duels: *"they are lowkey spamming moves like its
## sometimes too difficult to watch"*. At 0.45 a bot could still land three Q/R/T
## presses inside 1.4 s ON TOP of a primary firing every 0.22-0.45 s and a kit cast
## every 0.35 s — about 6-8 discrete actions per second per fighter, so 12-16 on
## screen. The gap between "busy" and "unreadable" is how many of them overlap.
##
## ⚠ 0.80 -> 1.05, AND THE REASON THE LAST ATTEMPT AT THIS FAILED. Maker: *"the bot
## fights the cool downs are a little too low I think they are just spaming spells"*.
##
## A previous session raised ALL FOUR pacing dials together, failed
## `slice6_test_bot_brain`'s ">= 12 casts in a neutral window", backed off twice, got
## 10 every time, and stopped. The diagnosis in the queue was that the guard binds
## harder than the dials move. It does not. **THAT TEST COUNTS ONLY `cast_slot`** —
## look at its loop: `if out.has("cast_slot")`. `fire`, `swing`, the three abilities,
## `guard` and `dash` are not counted at all.
##
## So `CAST_LATCH` is the ONE dial the guard constrains, and it was the one that got
## raised. This dial, `FIRE_SPACING` and the swing floor below are all invisible to
## that assertion — and between them they emit far more of what a watcher reads as
## "spam" than the kit does, because the kit is on 3-9 s cooldowns and these are not.
##
## Raising the uncounted three is not a way around the guard. The guard encodes "a bot
## must not go QUIET", and after this it still lands its twelve casts; what it stops
## doing is filling every gap between them.
## ⚠ 2.10 -> 3.00 ON THE MAKER'S THIRD PASS: *"increase the cooldown on the abilities
## and ensure they dont spam them in quick succession"*, and more broadly *"there is
## like too much going on all the time"*. Still one of the three dials the `>= 12
## casts` guard does NOT constrain, so this is the safe place to spend the ask.
const ABILITY_SPACING: float = 3.00

## ⚠ THE PRIMARY HAD NO SPACING AT ALL, AND THAT IS THE SPAM THE MAKER SAW.
##
## `_wants_fire` was gated by the body's own `cast_cd` and by nothing else — no
## `profile.period`, no latch, no lockout — so a bot pressed fire on the exact frame
## its cooldown hit zero, every time, forever. The header below still says that is
## deliberate, and it is right that a bot which only acts on cooldowns reads as idle;
## but "never idle" was implemented as "never NOT firing", which at a 0.22 s Brawler
## or a 0.30 s Shadowblade triple-shot is a stream, not a rhythm.
##
## A FLOOR, NOT A COOLDOWN. Classes slower than this are untouched — the Swordsaint
## (0.45) and the Juggernaut (0.40) never notice it. It binds only on the fast half of
## the roster, which is exactly where the complaint came from ("arcanist is spamming
## its default spell"). That also keeps it from flattening the classes apart.
##
## ⚠ AND IT IS THE FIX FOR A REAL BUG AS WELL AS A FEEL DIAL. The three melee-primary
## classes (Brawler, Juggernaut, Swordsaint) never set `_cast_cooldown_timer` at all —
## `_primary_melee_combo` / `_primary_heavy_swing` write `_melee_cooldown_timer`
## instead — so their `CD_PRIMARY` sits at 0 and the brain pressed fire EVERY SINGLE
## FRAME into a body that silently early-returned. This floor is what stops that,
## and it stops it without touching the player's own melee timing.
##
## ⚠ 0.42 -> 0.60, ON THE SAME NOTE, SECOND TIME OF ASKING. This constant exists
## because of the maker's *"arcanist is spamming its default spell"*; the reply to it
## is *"the cool downs are a little too low ... they are just spaming spells"*. The
## floor was right and it was not far enough.
##
## THE PRIMARY IS THE HIGHEST-FREQUENCY SPELL EMITTER IN THE GAME, by a wide margin —
## the kit sits on 3-9 s cooldowns, this fires as fast as the floor allows. At 0.42
## the fast half of the roster throws 2.4 bolts a second; at 0.60 it throws 1.67. That
## is the single biggest change available to how busy a duel looks, and it costs the
## player nothing: this is a BOT dial, and no spell's own cooldown moves.
##
## Still a FLOOR, not a cooldown. The Swordsaint (0.45) and the Juggernaut (0.40) are
## now inside it where they were not before, which is the one cost — but their primary
## is a melee swing whose damage the body gates anyway.
## ⚠ 1.25 -> 1.70, same ask as ABILITY_SPACING above. The primary is the
## highest-frequency emitter in the game, so it is the biggest single contributor to
## "too much going on"; `slice_test_bot_rhythm` guards this at >= 0.55 and it stays
## far clear.
const FIRE_SPACING: float = 1.70

## ══ THE PAUSE, THE FLINCH, AND THE LAST STAND ═══════════════════════════════════
## See `_note_exchange` for how these are rolled and why the ceilings are where they
## are. All three are per-EVENT probabilities, never per-frame: a per-frame roll at
## any of these rates fires several times a second and stops reading as a choice.
##
## The chances are deliberately well under half. The maker asked for fights that are
## *"natural and randomised"* — a bot that always pauses after a trade is as
## mechanical as one that never does, just slower.
const BREATHE_CHANCE: float = 0.30
const BREATHE_MIN: float = 0.45
const BREATHE_MAX: float = 1.30
const RECOIL_CHANCE: float = 0.55
const RECOIL_SECONDS: float = 0.28

## How long a bot may press INTO a wall before turning around stops being enough and
## it jumps instead. See `_unwall`.
##
## Short, and that is the point: `Hero` zeroes the walk against a wall, so every one
## of these frames is a frame the bot spent going nowhere while somebody shot at it.
## Long enough that brushing a riser mid-approach does not make it hop.
const WALL_STUCK_SECONDS: float = 0.45
## How long the bot must be genuinely OFF the wall before the stuck clock forgets.
## ⚠ THIS IS WHAT MAKES `WALL_STUCK_SECONDS` REACHABLE AT ALL — see `_unwall`. Turning
## around breaks contact for a frame or two, so an instant reset meant the clock could
## never accumulate. Short enough that a bot which genuinely walked away is forgotten
## well before it brushes the next riser.
const WALL_CLEAR_GRACE: float = 0.2

## ── CHANNEL-GATE TELEMETRY ──────────────────────────────────────────────────
## How many times a channelled spell was CONSIDERED, how many times the safety gate
## refused it, and how many of those refusals were the ULT slot. Process-wide,
## monotonic, free — the same shape and the same justification as
## `SpellDeflect.deflect_count`. See the gate in `score_slots`.
static var channel_chances: int = 0
static var channel_refusals: int = 0
static var ult_channel_refusals: int = 0

## ── ULT-SLOT TELEMETRY ──────────────────────────────────────────────────────
## The channel counters above answered ONE suspect and cleared it: measured over a
## real 8-bout sim, the safety gate refused 0 of 419 channelled casts and 0 ults. But
## the ult slot still only fires in a minority of bouts (`spells 6` — three spells per
## bot, not four — in 7 of those 8), so the reason is one of the OTHER gates, and
## there was no way to tell which without guessing.
##
## So every refusal of the ult slot is counted by REASON, on the same terms as the
## channel counters: process-wide, monotonic, and free (a handful of integer
## increments on a path that is already branching). `ult_considered` is the
## denominator — every time the scorer looked at the ult slot at all — so each
## reason is readable as a share rather than as a bare count.
##
## ⚠ THE COUNTERS ARE NOT A DIAGNOSIS. They say which gate said no, not whether it
## was right to. `ult_scored` (it passed every gate and got a real score) minus the
## casts that actually happened is the "it was affordable and the bot still chose
## something else" number, which is a FEEL question, not a bug.
static var ult_considered: int = 0
static var ult_gate_cooldown: int = 0
static var ult_gate_absent: int = 0
static var ult_gate_mana: int = 0
static var ult_gate_range: int = 0
static var ult_scored: int = 0
## Decision beats where the ult had the highest score of any slot but still lost —
## to the cast threshold, i.e. "the best idea available was not a good enough idea".
static var ult_best_but_under_threshold: int = 0


## For a harness measuring one run at a time.
static func reset_channel_stats() -> void:
	channel_chances = 0
	channel_refusals = 0
	ult_channel_refusals = 0
	ult_considered = 0
	ult_gate_cooldown = 0
	ult_gate_absent = 0
	ult_gate_mana = 0
	ult_gate_range = 0
	ult_scored = 0
	ult_best_but_under_threshold = 0

## Below this share of health a bot may decide it is out of better ideas.
const DESPERATE_HP: float = 0.34
## Rolled once per decision beat while desperate, so at a 0.22 s beat the urge
## arrives within about a second — visible, without being the same every bout.
const DESPERATE_ULT_CHANCE: float = 0.30
## How long the urge lasts once taken. Long enough to survive a cooldown or a range
## problem, short enough that it is a MOMENT rather than a new personality.
const DESPERATE_ULT_HOLD: float = 3.0
## How much the urge forgives the cast threshold and flatters the ult's own score.
## Every HARD gate still applies underneath — cooldown, mana, range fit, channel
## safety — so a desperate bot cannot cast an ult it could not otherwise cast. It
## can only stop being talked out of one.
const DESPERATE_ULT_BONUS: float = 1.7

## ---------------------------------------------------------------------------
## THE DEGENERATE-FIGHT BREAKER. Two bots on the same spacing logic, both correctly
## refusing to enter each other's band, produce a fight where nothing lands for
## minutes — which is technically correct behaviour and completely unwatchable.
##
## `BotAdapt.anti_camp` already answers the pure "I have thrown nothing" case and is
## kept as the shared rule (one definition, tested in `slice_test_botfight`). What
## it cannot see is a fight where BOTH bots are busily attacking and NOTHING IS
## CONNECTING — the whiff war. So the brain tracks the foe's health bar (a drawn
## thing, so no fairness cost) and escalates when it has not moved.
##
## Escalation is deliberately NOT a stat change: the bot lowers its own cast
## threshold and pulls its spacing band toward contact, i.e. it starts taking the
## fights it was declining. It gets bolder, never stronger.
const STAGNATION_SECONDS: float = 6.0
## Full escalation this long after the last time anyone's health bar moved.
const STAGNATION_FULL: float = 14.0
## How far the band is pulled toward contact at full escalation.
const STAGNATION_BAND_PULL: float = 0.45
## How much of the cast threshold is forgiven at full escalation.
const STAGNATION_THRESHOLD_CUT: float = 0.7

## ---------------------------------------------------------------------------
## THE COMBOS THE BOT CAN ACTUALLY EXECUTE.
##
## Sourced from ReactionTable's authored rows — NOT invented here. Each entry says
## "a live field of `field` element makes an attack of `then` element much better,
## so both halves are worth planning". The brain uses each row in BOTH directions:
##
##   CASHING IN  — a matching field is already on the board, so boost the slot whose
##                 element completes it. (Fire the lightning through the blizzard.)
##   SETTING UP  — no field yet, but I hold BOTH halves and both are ready, so boost
##                 the field-maker. This is the half that produces the clip: the bot
##                 drops the frost field ON PURPOSE, because of what it holds next.
##
## Weighted by `profile.combo` so a low tier plays single spells and a high tier
## plays the matrix. The `payoff` figure is the row's own relative worth, used only
## to rank two available combos against each other.
const COMBO_SETUPS: Array[Dictionary] = [
	# supercharge — LIGHTNING through an ICE field. Spends nothing on either side,
	# which is why it is the best set-up in the game: the field keeps standing and
	# the beam carries on. The Stormcaller kit is literally built around it
	# (blizzard in control, Tempest in ult).
	{"field": Elements.Element.ICE, "then": Elements.Element.LIGHTNING,
		"name": "supercharge", "payoff": 1.0},
	# steam_cloud — FIRE into an ICE field. Consumes the field and pays in VISION
	# rather than damage, so it ranks under supercharge.
	{"field": Elements.Element.ICE, "then": Elements.Element.FIRE,
		"name": "steam_cloud", "payoff": 0.6},
	# banish — HOLY into a SHADOW field. Erases the field outright; the answer to a
	# Warlock parking a Shadow Root on the floor.
	{"field": Elements.Element.SHADOW, "then": Elements.Element.HOLY,
		"name": "banish", "payoff": 0.8},
	# void_charged — anything detonating inside a SHADOW field inverts its knockback
	# into a pull. Wildcard on the attacker, so `then` is -1 = any element.
	{"field": Elements.Element.SHADOW, "then": -1,
		"name": "void_charged", "payoff": 0.5},
]

## The same idea against BARRIERS rather than fields: bringing the right element to
## a wall is the whole point of having elements. `then` = the element that answers
## `barrier`.
const COMBO_BARRIERS: Array[Dictionary] = [
	# shatter_ice_barrier / shrapnel_cone — FIRE or HOLY pops an ICE wall, and so
	# does any thrown thing.
	{"barrier": Elements.Element.ICE, "then": Elements.Element.FIRE, "payoff": 0.9},
	{"barrier": Elements.Element.ICE, "then": Elements.Element.HOLY, "payoff": 0.9},
	# shatter_ward — SHADOW pops a HOLY ward, which is the ward's own printed counter.
	{"barrier": Elements.Element.HOLY, "then": Elements.Element.SHADOW, "payoff": 0.8},
]

## ...and the one the bot must NOT walk into. ReactionTable's `ground_out` row:
## an EARTH barrier eats a LIGHTNING beam and the beam is CONSUMED. Throwing your
## lightning line into a rock wall is a spell donated to the wall, so the scorer
## takes a penalty rather than merely not taking a bonus.
const COMBO_AVOID: Array[Dictionary] = [
	{"barrier": Elements.Element.EARTH, "then": Elements.Element.LIGHTNING, "penalty": 0.5},
]


## ---------------------------------------------------------------------------
## PER-BOT MEMORY. The brain is otherwise stateless, but three things genuinely
## cannot be recomputed from one frame's blackboard:
##
##   · WHEN a threat was first seen — the entire reaction-delay model. Recomputing
##     it per frame would mean the bot has always-just-noticed everything, i.e. no
##     reaction time at all, i.e. the difficulty dial silently does nothing.
##   · WHAT it decided last — the latches that stop it twitching, and the recency
##     term that stops it spamming one slot.
##   · WHAT IT LAST THREW — the fusion window for the self-combo.
##
## Hand the same instance back every frame. `decide` will also accept one parked in
## the blackboard under "mem", and will install one there if it finds neither — so
## a caller that reuses its blackboard dictionary gets full behaviour for free, and
## a caller that rebuilds it every frame degrades SAFELY (see the note in decide).
class Memory extends RefCounted:
	## First-sighting clock + whiff rolls. Owned by BotDodge so the dodge module and
	## the brain can never disagree about what this bot has noticed.
	var reactions: BotDodge.Reactions = BotDodge.Reactions.new()
	## Deterministic under test: set `rng.seed` and the same fight replays exactly.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	## When this body first started pressing INTO a wall it is touching, or -1 while it
	## is not. See `_unwall` — the clock is what separates "brushed a wall" from
	## "wedged in a corner", and only the second one earns a jump.
	var wall_since: float = -1.0
	## When contact was lost, for `WALL_CLEAR_GRACE`. -1 while pressing.
	var wall_clear_at: float = -1.0

	var next_decision_at: float = -1.0
	var latched_slot: int = -1
	var latched_until: float = 0.0
	var dodge_until: float = 0.0
	var dodge_action: String = ""
	var dodge_dir: Vector2 = Vector2.ZERO

	## Self-imposed cooldowns. The blackboard MAY tell us what is ready; when it does
	## not, we hold ourselves to the body's real numbers rather than assuming we can
	## dash every frame. Assuming readiness is a cheat by omission.
	var last_dash_at: float = -99.0
	## Last time the bot hopped to reach a foe ABOVE it. See AIR_REACH_SPACING.
	var last_air_reach_at: float = -99.0
	## Per-bot phase offset for the settled shuffle, so two fighters holding the same
	## distance do not sway in lockstep like a chorus line. See IDLE_JOCKEY.
	var jockey_phase: float = -1.0
	var last_blink_at: float = -99.0
	var last_guard_at: float = -99.0
	var last_fire_at: float = -99.0
	var guard_hold_until: float = 0.0

	## Slot -> time last cast, for the recency (anti-spam) term.
	var last_slot_at: Dictionary = {}
	## The self-combo window: what element the last BEAM-shaped spell carried.
	var last_beam_element: int = -1
	var last_beam_at: float = -99.0

	## Aim scatter is sampled once per decision, not per frame — a per-frame sample
	## would average out to perfect aim over a beam's channel, which is exactly the
	## auto-aim this must not become.
	var aim_error: float = 0.0

	## Q / R / T book-keeping. Same shape and same reason as `last_slot_at`: the
	## body's cooldowns pace each button individually, this paces them against each
	## other so three abilities never fire on one frame.
	var last_ability_at: float = -99.0
	var last_swing_at: float = -99.0

	## THE CAMP BREAKER'S SCRATCH, moved here from `BotController.adapt_state`.
	## It belongs on the brain side because it is a decision, not a seam concern —
	## and because parking it on the controller meant it only existed for bots the
	## arena happened to build with one, so a brain driven by any other seam (the
	## sim's, a test's) silently had no liveness floor at all.
	var camp_state: Dictionary = {}

	## THE WHIFF-WAR DETECTOR. Last health total (mine + the foe's, both read off
	## drawn bars) and when it last MOVED. Two bots politely refusing each other's
	## spacing band is the single most common degenerate outcome in this game, and it
	## is invisible to a per-frame scorer that is behaving perfectly correctly.
	var last_hp_total: float = -1.0
	var last_progress_at: float = 0.0

	## ⚠ THE SAME EVENT, SPLIT SO IT CAN SAY *WHO*. `last_hp_total` is the SUM of both
	## bars, which is all the whiff-war detector needs — but it means the moment the
	## brain notices "somebody just took damage" it cannot tell whether that was the
	## foe or itself. That is why a bot has never reacted to being hit: the event was
	## detected and thrown away one line after it was computed.
	var last_self_hp: float = -1.0
	var last_foe_hp: float = -1.0

	## THE PAUSE. While `now < breathe_until` the bot declines to START anything — no
	## kit cast, no ability, no swing, no primary — while still aiming, still moving,
	## still dodging and still answering the camp breaker. It is the "empty spaces"
	## the maker asked for, and it is what makes the next exchange read as a decision
	## rather than as the next frame of a stream.
	var breathe_until: float = 0.0

	## Set when a bot is hit: for a short beat it gives ground. The read is "that
	## landed", and it is the cheapest reaction movement available because `_steer`
	## already knows how to walk away from the foe.
	var recoil_until: float = 0.0

	## ⚠ THE WALK LATCH — the one latch this brain never had. +1 closing, -1 backing
	## off, 0 holding, plus the earliest time that answer may change. Every other latch
	## in this file is on a CAST or a DODGE; the steering layer re-decided from scratch
	## every physics frame with no memory at all, which is the "back and forward".
	## Stored as an INTENT rather than a world direction because two fighters cross
	## sides constantly — see the Schmitt-trigger block in `_steer`.
	var steer_intent: int = 0
	var steer_until: float = 0.0

	## Latched when a bot decides, once, that it is desperate enough to pull its ult.
	## Latched rather than continuous so the choice COMMITS — a per-frame bonus
	## flickers on and off across the threshold and reads as indecision.
	var ult_urge_until: float = 0.0

	func _init() -> void:
		rng.randomize()


## Cached kit facts per class id. build_for_class mints fresh Resources on every
## call (correctly — they are mutable), so calling it per frame per bot would be
## pure garbage. The facts we derive are immutable, so one build per class for the
## whole process is right.
static var _kit_cache: Dictionary = {}


# =========================================================================
# THE ENTRY POINT
# =========================================================================

## One frame of thinking. Pure: same blackboard + same profile + same memory state
## produces the same intent, which is what makes the whole brain provable headlessly.
##
## ON THE MISSING-MEMORY CASE. `mem` is optional so the 2-argument contract call
## works verbatim. When it is absent we look in the blackboard, and failing that
## install a fresh one there. If the caller rebuilds its blackboard every frame the
## install is lost each time — and the degradation is deliberately the SAFE one: a
## brand-new Reactions has seen nothing, so the bot does not react to threats it has
## not had time to notice. It gets duller, never cheaper to beat itself against.
static func decide(bb: Dictionary, profile: Dictionary, mem: Memory = null) -> Dictionary:
	var m: Memory = _resolve_memory(bb, mem)
	var now: float = float(bb.get("now", 0.0))
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var my_vel: Vector2 = bb.get("self_vel", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)

	var intent: Dictionary = {}

	# ---- is this fight going anywhere? Sampled before anything else so every layer
	# below can read the same escalation number. Free of fairness cost: both health
	# bars are drawn over the fighters' heads.
	var stagnation: float = _track_stagnation(bb, m, now)

	# ---- perception: only the threats this bot is ALLOWED to have noticed yet.
	var seen: Array = _visible_threats(bb, profile, m, now)
	var evaluated: Array = []
	for t: Dictionary in seen:
		evaluated.append(_evaluate(me, my_vel, t))
	var pressure: float = _pressure(evaluated, me, foe, float(bb.get("reach", 58.0)))
	var soonest: float = _soonest_tti(evaluated)

	# ---- aim is free and never conflicts with anything else, so it is resolved
	# first and survives every early return below. A bot that stops aiming while it
	# dodges looks like it stopped thinking.
	intent["aim"] = _aim(bb, profile, m, now)

	# ---- LAYER 1: the reflex. Preempts, and may end the frame outright.
	var reflex: Dictionary = _reflex(bb, profile, m, now, evaluated)
	if not reflex.is_empty():
		for k: String in reflex.keys():
			intent[k] = reflex[k]
		# Guard is HELD, and MeleeClash's locked rule is that guarding locks out
		# attacking — so a guarding frame is a guarding frame and nothing else.
		# A dash/blink/jump frame still gets its movement from the reflex exit
		# vector, which the steering layer must not then fight.
		#
		# Still routed through the camp breaker: a reflex CLASH is an offensive frame
		# and has to reset the idle clock, or a bot that spent the whole fight
		# trading blows would be told it had been camping the moment it stopped.
		#
		# ⚠ THE WALL CLOCK RUNS ON REFLEX FRAMES TOO, or the guard below is bypassed by
		# the one state that matters most. `_unwall`'s header says it "sits after every
		# writer" and "cannot be bypassed by a new opinion about where to walk" — but
		# this early return skipped it entirely, so a cornered bot being HIT (the reflex
		# layer fires on every incoming threat) never accumulated a single frame of wall
		# time. The more it was attacked, the less the anti-wedge guard ran.
		#
		# `turn = false` — a dodge or blink owns its exit vector and this must not fight
		# it. The clock and the jump still apply, and a jump is an exit, not an argument.
		_unwall(intent, bb, m, now, false)
		return BotAdapt.anti_camp(intent, bb, m.camp_state, now)

	# ---- LAYER 2: steering. Always contributes; movement costs nothing.
	intent["move"] = _steer(bb, profile, m, evaluated, pressure, stagnation, now)

	# ---- THE FLINCH. A body that eats a hit and keeps walking forward reads as not
	# having noticed. Overrides the steering vector only, and only for a beat, so the
	# bot gives ground and then resumes whatever it was doing — it never overrides the
	# reflex above it, because being shoved is not a reason to stop dodging.
	if now < m.recoil_until:
		var away: Vector2 = Vector2(bb.get("self_pos", Vector2.ZERO)) \
			- Vector2(bb.get("foe_pos", Vector2.ZERO))
		if away.x != 0.0:
			intent["move"] = Vector2(signf(away.x), 0.0)

	# ---- TRAVERSAL. Turns a long walk into a dash, and catches a body that has been
	# launched. Sits here because it WRITES `intent["move"]`, and the wall guard below
	# is documented as running after every writer of it.
	_traverse_dash(intent, bb, m, now)

	# ---- UP. Reaches a foe that is ABOVE this bot rather than beside it — the case
	# every distance in this file flattens away. See AIR_REACH_MIN_RISE.
	_reach_upward(intent, bb, m, now)

	# ---- THE WALL. Applied AFTER every writer of `intent["move"]` above, which is the
	# whole point: see `_unwall`.
	_unwall(intent, bb, m, now)

	# ---- THE BREATH. Declines to START anything for a beat after an exchange, while
	# aim, movement, the reflex above and the camp breaker below all keep running. It
	# is the only path in this file that produces a deliberately empty frame, and the
	# reason the fight can have a rhythm instead of a level.
	if now < m.breathe_until:
		return BotAdapt.anti_camp(intent, bb, m.camp_state, now)

	# ---- LAYER 3: utility. Rate-limited and latched — see CAST_LATCH.
	var slot: int = _pick_slot(bb, profile, m, now, pressure, soonest, stagnation)
	if slot >= 0:
		intent["cast_slot"] = slot
		_note_cast(bb, m, slot, now)
	else:
		# ---- LAYER 3b: the three ABILITY buttons. Deliberately BELOW the kit and
		# only reached when the scorer declined — Q/R/T are free (no mana, no role,
		# no reaction identity) so letting them compete with the kit on score would
		# have a bot spamming its cheap AoE instead of ever throwing its ult.
		var ability: StringName = _pick_ability(bb, profile, m, now, pressure)
		if ability != &"":
			intent[ability] = true
			m.last_ability_at = now
		elif _wants_swing(bb, m, now):
			# ---- LAYER 3c: the melee SWING. A separate button from `fire` on every
			# class (on a caster `fire` throws a bolt and this punches), and no brain
			# had ever pressed it. It is what makes a bot that has closed the distance
			# look like it MEANT to.
			intent["swing"] = true
			m.last_swing_at = now
		elif _wants_fire(bb, profile, m, now, evaluated):
			intent["fire"] = true
			m.last_fire_at = now

	# ---- LIVENESS FLOOR. The shared "I have thrown nothing at all for a while and I
	# am standing outside every kit's range" rule, applied HERE rather than on the
	# controller so it holds for every seam that drives this brain. `BotAdapt` owns
	# the rule so there is exactly one definition of camping.
	return BotAdapt.anti_camp(intent, bb, m.camp_state, now)


# =========================================================================
# PERCEPTION
# =========================================================================

## Everything on the board, filtered down to what this bot has had time to see and
## did not fumble. This is the ONLY place threats enter the brain, which is what
## makes the fairness claim checkable: there is one door and the reaction delay is
## nailed to it.
static func _visible_threats(bb: Dictionary, profile: Dictionary, m: Memory,
		now: float) -> Array:
	var raw: Array = bb.get("threats", [])
	var delay: float = BotProfile.get_f(profile, "react")
	var jitter: float = BotProfile.get_f(profile, "jitter")
	var p_miss: float = BotProfile.get_f(profile, "p_miss")
	var out: Array = []
	var live: Array = []
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = _normalise(entry)
		var id: int = int(t["id"])
		live.append(id)
		# Two independent rolls: one jitters WHEN it is noticed, one decides whether
		# this particular threat is fumbled. Both are taken ONCE, at first sighting —
		# hence the `knows` guard, without which the draws would be spent every frame
		# and a seeded bot would stop being reproducible.
		if not m.reactions.knows(id):
			var jitter_roll: float = m.rng.randf_range(-jitter, jitter)
			m.reactions.observe(id, now, maxf(delay + jitter_roll, 0.0), m.rng.randf(), p_miss)
		if m.reactions.visible(id, now):
			out.append(t)
	# A threat that no longer exists must be forgotten, or Godot recycling its
	# instance id hands a brand-new threat an already-elapsed reveal time — a free
	# instant reaction, and the exact shape of bug that quietly voids a fairness
	# guarantee.
	m.reactions.forget_missing(live)
	return out


## One threat descriptor, in whatever shape the perception layer happened to build
## it, reduced to the one shape this brain reasons about.
##
## TWO SHAPES ARE ACCEPTED ON PURPOSE. The build plan's threat record uses a `kind`
## field; Telegraph.danger_shape() — which is what the live telegraphs actually
## publish — uses `shape` with "circle" / "line". Rather than force one caller to
## translate for the other (and drift), both are read here.
static func _normalise(t: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"id": int(t.get("id", 0)),
		"tti": float(t.get("tti", t.get("time_to_impact", 0.0))),
		# Total warning the tell ever gave; 0.0 = not published. See `_caps`.
		"lead": float(t.get("lead", 0.0)),
		"damage": int(t.get("damage", 0)),
		# Unknown parryability is treated as PARRYABLE: guessing "no" would make the
		# bot never guard against anything a caller forgot to annotate, which is a
		# silent loss of a whole defensive verb.
		"parryable": bool(t.get("parryable", true)),
		"pos": t.get("pos", t.get("center", t.get("from", Vector2.ZERO))),
		"vel": t.get("vel", Vector2.ZERO),
		"radius": float(t.get("radius", 0.0)),
		"width": float(t.get("width", 0.0)),
		"length": float(t.get("length", 0.0)),
		"angle": float(t.get("angle", 0.0)),
		"form": "",
	}
	var shape: String = String(t.get("shape", ""))
	if shape == "line" or (t.has("from") and t.has("to")):
		# A published line gives two endpoints; the lane solver wants an origin plus
		# an angle and a length, so derive them once here.
		var a: Vector2 = t.get("from", Vector2.ZERO)
		var b: Vector2 = t.get("to", a)
		var seg: Vector2 = b - a
		out["pos"] = a
		out["angle"] = seg.angle()
		out["length"] = seg.length()
		out["form"] = "lane"
	elif shape == "circle":
		out["form"] = "circle"
	else:
		var kind: Variant = t.get("kind", null)
		var kind_s: String = String(kind).to_lower() if typeof(kind) == TYPE_STRING else ""
		if kind_s == "lane" or out["length"] > 0.0 and out["radius"] <= 0.0:
			out["form"] = "lane"
		elif kind_s == "projectile" or Vector2(out["vel"]).length_squared() > 0.01:
			out["form"] = "projectile"
		else:
			out["form"] = "circle"
	return out


## Threat geometry, dispatched to the right solver in BotDodge. All three return the
## same {threatening, tti, exit, exit_len, degenerate} shape, which is what lets the
## response ladder be written once for every attack in the game.
static func _evaluate(me: Vector2, my_vel: Vector2, t: Dictionary) -> Dictionary:
	var r: Dictionary
	match String(t["form"]):
		"projectile":
			r = BotDodge.threat_from_projectile(me, t["pos"], t["vel"])
		"lane":
			r = BotDodge.threat_from_lane(me, my_vel, t["pos"], float(t["angle"]),
				float(t["length"]), float(t["width"]), float(t["tti"]))
		_:
			r = BotDodge.threat_from_circle(me, my_vel, t["pos"], float(t["radius"]),
				float(t["tti"]))
	r["id"] = t["id"]
	r["parryable"] = t["parryable"]
	r["lead"] = t["lead"]
	r["damage"] = t["damage"]
	r["form"] = t["form"]
	r["pos"] = t["pos"]
	r["radius"] = t["radius"]
	return r


## How hard this bot is being pressed, 0..1 — the term that turns the "answer" slot
## from a mobility toy into an escape button and that talks the bot out of long
## channels. Counts imminent threats AND the plain fact of a foe standing inside
## melee reach, because a fist is a threat with no telegraph to perceive.
static func _pressure(evaluated: Array, me: Vector2, foe: Vector2, reach: float) -> float:
	var p: float = 0.0
	for e: Dictionary in evaluated:
		if not bool(e.get("threatening", false)):
			continue
		var tti: float = float(e.get("tti", PRESSURE_HORIZON))
		p += clampf(1.0 - tti / PRESSURE_HORIZON, 0.0, 1.0)
	if me.distance_to(foe) <= reach * 1.35:
		p += 0.5
	return clampf(p, 0.0, 1.0)


## HOW STUCK IS THIS FIGHT, 0..1. Zero while damage is being exchanged; ramps to
## one after STAGNATION_FULL seconds in which neither health bar moved.
##
## This is the answer to the failure mode a per-frame utility scorer cannot see:
## two bots BOTH behaving correctly — holding their class band, declining casts that
## score under threshold, dodging what they should — and producing a three-minute
## fight in which nothing ever connects. Every individual decision is right and the
## match is unwatchable.
##
## ⚠ IT ESCALATES BOLDNESS, NEVER POWER. The number is consumed in exactly two
## places: `_band` pulls the preferred spacing toward contact, and `_pick_slot`
## forgives part of the cast threshold. The bot starts taking fights it was
## declining. No stat moves, no cooldown shortens, and nothing here is visible to
## the other bot — so a stalled mirror match resolves because both sides get braver,
## which is also what two stalled humans would do.
##
## Health totals are read off the two drawn bars, so there is no fairness cost.
## ══ NOBODY WALKS INTO A WALL FOREVER ═══════════════════════════════════════════
## Maker, watching Watch Bots: *"these guys get stuck in the corner of a wall then
## destroyed"*.
##
## THE MECHANISM, in three parts, none of which is a steering bug on its own:
##
##   1. This file had no terrain awareness AT ALL — no raycast, no whisker, no
##      surface list. `_safest` reads pits and telegraphs; the blackboard carried
##      nothing solid. So the brain could not tell "blocked" from "walking".
##   2. FOUR independent paths write a backwards direction and NONE of them asks what
##      is behind: the band's `intent = -1` back-off, the under-pressure drift, the
##      stagnation drift, and the recoil flinch — which fires on 55% of hits taken, so
##      being cornered actively re-arms the thing that put you there.
##   3. `Hero` zeroes the walk against a wall (`is_on_wall()` -> `walk_x = 0.0`) and
##      cannot step up: three of the versus stage's four risers are 90 px against a
##      jump that apexes at 112 and a documented COMFORTABLE step of 86
##      (`FloorGen.STEP_MAX`). So the bot pressed full deflection into a face, went
##      nowhere, and never learned anything.
##
## THE GUARD SITS AFTER EVERY WRITER, deliberately. Putting it inside `_steer` would
## have missed the recoil flinch — the one most likely to start the wedge — and would
## miss the next path somebody adds. One guard, applied last, cannot be bypassed by a
## new opinion about where to walk.
##
## Two rungs:
##   * PUSHING INTO A WALL is turned around. Not vetoed to zero: standing still in a
##     corner is the exact failure being fixed.
##   * STILL AGAINST IT after `WALL_STUCK_SECONDS` means turning around is not enough
##     — the way out of a corner is up. A jump is requested, which is the only verb
##     `Hero` has that clears a riser, and which this file otherwise emits ONLY as a
##     dodge answer (`BotDodge.VERTICAL_EXIT_DOT`), i.e. never for terrain.
static func _unwall(intent: Dictionary, bb: Dictionary, m: Memory, now: float,
		turn: bool = true) -> void:
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	var wall_dir: float = float(bb.get("wall_dir", 0.0))
	var against: bool = bool(bb.get("on_wall", false)) and wall_dir != 0.0
	# Pressing INTO it, rather than brushing past or already leaving. A bot that walks
	# ALONG a wall is not stuck against it.
	var pressing: bool = against and move.x != 0.0 and signf(move.x) == wall_dir
	if not pressing:
		# ⚠ A GRACE, NOT AN INSTANT RESET — AND WITHOUT IT THE SECOND RUNG WAS DEAD CODE.
		# Rung one turns the bot around, which BREAKS wall contact on the very next
		# frame. The old code then cleared the clock, the steering layer (whose opinion
		# has not changed) walked straight back into the face, and the clock restarted
		# from zero. `now - wall_since` could therefore never reach WALL_STUCK_SECONDS,
		# so `intent["jump"]` — the entire "turning around is not enough, the way out is
		# up" half of this guard — never executed once in play.
		#
		# It passed its own suite because the suite held `on_wall` true every frame
		# while the code under test was turning the body away: a state the fix itself
		# prevents. See `slice_test_bot_walls`.
		if m.wall_clear_at < 0.0:
			m.wall_clear_at = now
		if now - m.wall_clear_at >= WALL_CLEAR_GRACE:
			m.wall_since = -1.0
		return
	m.wall_clear_at = -1.0
	if m.wall_since < 0.0:
		m.wall_since = now
	# ⚠ THE TURN IS SUPPRESSED ON A REFLEX FRAME (see the call in `decide`): a dodge or
	# blink already owns its exit vector and this must not fight it. The CLOCK still
	# runs and the jump still fires, which is the half that matters when a cornered bot
	# is being hit — the reflex layer returning early is exactly how it stays cornered.
	if turn:
		intent["move"] = Vector2(-wall_dir, move.y)
	if now - m.wall_since >= WALL_STUCK_SECONDS:
		intent["jump"] = true
		# ⚠ AND STEER INTO THE FACE, NOT AWAY FROM IT. The line above has just set the
		# move to `-wall_dir` — turning around — and the jump was landing in the SAME
		# frame, so the bot leapt backwards off the riser it was trying to get up. That
		# is rung one's answer applied to rung two's problem: turning away is what you
		# do when a wall is pointless, and going up is what you do when it is the way.
		#
		# Steering into the face is free while the body is still touching it —
		# `Hero.gd:2333-2336` zeroes walk on wall contact — and takes effect the instant
		# the jump clears the lip, which is precisely when the body needs to travel
		# forward to land on top. So the same vector is inert during the climb and
		# correct at the top of it.
		#
		# This only became reachable now that a bot's jump actually clears a ledge; at
		# the old 36 px apex it would have leapt into the face and slid back down. See
		# `BotController._hold_the_jump`.
		intent["move"] = Vector2(wall_dir, move.y)
		# Re-arm rather than latch, or every subsequent frame against the wall requests
		# another jump and the bot pogos instead of climbing out once.
		m.wall_since = now


static func _track_stagnation(bb: Dictionary, m: Memory, now: float) -> float:
	var total: float = float(bb.get("self_hp_frac", 1.0)) + float(bb.get("foe_hp_frac", 1.0))
	_note_exchange(bb, m, now)
	if m.last_hp_total < 0.0:
		m.last_hp_total = total
		m.last_progress_at = now
		return 0.0
	# A ROUND RESET REFILLS BOTH BARS, so the total can RISE. Any movement at all —
	# up or down — means something happened, and the clock restarts either way.
	if absf(total - m.last_hp_total) > 0.001:
		m.last_hp_total = total
		m.last_progress_at = now
		return 0.0
	var idle: float = now - m.last_progress_at
	if idle <= STAGNATION_SECONDS:
		return 0.0
	return clampf((idle - STAGNATION_SECONDS)
		/ maxf(STAGNATION_FULL - STAGNATION_SECONDS, 0.001), 0.0, 1.0)


## ══ WHAT JUST HAPPENED TO ME, WHICH NOTHING USED TO ASK ═════════════════════════
## Maker, on the duel: *"more reaction movement like make them smarter"*, *"empty
## spaces here and there"*, and *"it becomes noise slop right now because they are
## repeatedly getting hit"*.
##
## All three want the same missing thing: a bot that treats an exchange as an EVENT.
## `_track_stagnation` computes exactly that event — its `absf(total - last) > 0.001`
## branch is literally "somebody took damage this beat" — and then throws it away to
## reset a clock. It also sums both bars, so it cannot say who. Splitting the sum is
## the whole unlock, and it needs no new blackboard key: `self_hp_frac` and
## `foe_hp_frac` have both been there all along.
##
## Two outcomes, both rolled ONCE per event off the existing `m.rng` (the same
## generator the aim scatter and the whiff rolls use, so a seeded test still replays
## exactly):
##   BREATHE  — sometimes, after a trade, simply stop starting things for a beat.
##   RECOIL   — when the damage was MINE, give ground briefly. That is the reaction
##              movement; a body that eats a hit and keeps walking forward reads as
##              not having noticed.
##
## ⚠ EVERY CEILING HERE IS SET BY SOMETHING ELSE'S FLOOR, and they are close together:
## `BotAdapt.CAMP_SECONDS` is 3.0, `BotSimProbe.IDLE_SECONDS` is 5.0 (it files a
## SEV_ERROR `actor_idle` row), and `STAGNATION_SECONDS` is 6.0 — past which the
## degenerate-fight breaker starts cutting the very cast threshold a pause just
## raised. A max gap of 1.6 s clears all three with room, and because a breathing bot
## still MOVES and still AIMS, the idle probe never sees it at all.
static func _note_exchange(bb: Dictionary, m: Memory, now: float) -> void:
	var mine: float = float(bb.get("self_hp_frac", 1.0))
	var theirs: float = float(bb.get("foe_hp_frac", 1.0))
	if m.last_self_hp < 0.0:
		m.last_self_hp = mine
		m.last_foe_hp = theirs
		return
	var i_was_hit: bool = mine < m.last_self_hp - 0.001
	var anything: bool = i_was_hit or absf(theirs - m.last_foe_hp) > 0.001
	m.last_self_hp = mine
	m.last_foe_hp = theirs
	if not anything:
		return
	if i_was_hit and m.rng.randf() < RECOIL_CHANCE:
		m.recoil_until = maxf(m.recoil_until, now + RECOIL_SECONDS)
	# Never stack a pause on top of a pause: the roll only counts when the bot is not
	# already breathing, or a long trade would compound into a bot that has stopped.
	if now >= m.breathe_until and m.rng.randf() < BREATHE_CHANCE:
		m.breathe_until = now + m.rng.randf_range(BREATHE_MIN, BREATHE_MAX)


## Seconds until the NEXT thing lands, or a large number when the board is clear.
## The channel-safety gate is a comparison against this and nothing else.
static func _soonest_tti(evaluated: Array) -> float:
	var soonest: float = 99.0
	for e: Dictionary in evaluated:
		if bool(e.get("threatening", false)):
			soonest = minf(soonest, float(e.get("tti", 99.0)))
	return soonest


# =========================================================================
# LAYER 1 — THE REFLEX
# =========================================================================

## Returns a COMPLETE intent (movement included) when the bot is answering a threat,
## or {} to let the other two layers run. Latched: once an answer is chosen it is
## held for the action's duration, because re-deciding mid-dash is how a bot ends up
## dashing nowhere, repeatedly.
static func _reflex(bb: Dictionary, profile: Dictionary, m: Memory, now: float,
		evaluated: Array) -> Dictionary:
	# Still committed to the last answer.
	if now < m.dodge_until and m.dodge_action != "":
		return _reflex_intent(m.dodge_action, m.dodge_dir, now, m)
	# A held guard runs on its own clock: it was pressed EARLY on purpose and must
	# stay down until the blow it was pressed for has arrived.
	if now < m.guard_hold_until:
		return {"guard": true, "move": Vector2.ZERO}

	var worst: Dictionary = {}
	var worst_tti: float = 99.0
	for e: Dictionary in evaluated:
		if not bool(e.get("threatening", false)):
			continue
		if float(e.get("tti", 99.0)) < worst_tti:
			worst_tti = float(e.get("tti", 99.0))
			worst = e
	if worst.is_empty():
		return {}

	# The exit BotDodge solved may point into a pit or into a second live telegraph,
	# so it is re-scored against everything else on the board before being trusted.
	var exit: Vector2 = worst.get("exit", Vector2.ZERO)
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var need: float = float(worst.get("exit_len", 0.0))
	# THE DEGENERATE CASE, AND WHY IT IS THE COMMON ONE. Every telegraph in this game
	# SNAPSHOTS the target's position and plants its circle there — so at the instant
	# it blooms, a bot standing still is exactly at the centre and there is no
	# "shortest way out": every direction is equally long. BotDodge reports that
	# rather than inventing a direction, and here is where it gets answered, by open
	# ground instead of by geometry. Left untreated the ladder returns `none` and the
	# bot stands in the blast it was told about — the single most visible way this
	# whole layer could fail.
	var candidates: Array[Vector2]
	if bool(worst.get("degenerate", false)) or exit.length_squared() <= 0.01:
		# Ordered AWAY FROM THE FOE first. safest_exit breaks ties by shortness and
		# then by order, so with equal-length options this is what decides — and
		# "when every direction is the same length, do not dive toward the person
		# hitting you" is the right tiebreak, as well as the one that stops every
		# bot in the game dodging left forever.
		var foe_pos: Vector2 = bb.get("foe_pos", me + Vector2.RIGHT)
		var away: float = signf(me.x - foe_pos.x)
		if away == 0.0:
			away = 1.0
		candidates = [Vector2(away, 0.0) * need, Vector2(-away, 0.0) * need,
			Vector2(0.0, -need)]
	else:
		# The mirrored exit is a genuine second option, not a fallback: for a lane or
		# a circle, stepping out the other side is equally valid geometry and is often
		# the only one that is not over a pit.
		candidates = [exit, -exit]
	var safe_exit: Vector2 = _safest(bb, me, candidates, worst)
	worst = worst.duplicate()
	worst["exit"] = safe_exit
	worst["exit_len"] = safe_exit.length()

	var caps: Dictionary = _caps(bb, profile, m, now, worst)
	var choice: Dictionary = BotDodge.choose_response(worst, caps)
	var action: String = String(choice.get("action", "none"))
	var dir: Vector2 = choice.get("dir", Vector2.ZERO)

	# THE CLASH READ. Nothing in the ladder was affordable and the threat is a body
	# in my face — so an aggressive bot answers a swing with a swing rather than
	# standing there. MeleeClash resolves two blows declared in the same window by
	# throwing both fighters apart, which is both the correct play and the single
	# most watchable thing two bots can do to each other.
	if action == "none" or action == "walk":
		if _clash_worthwhile(bb, profile, m, now, worst):
			m.dodge_action = "clash"
			m.dodge_until = now + MELEE_COOLDOWN
			m.dodge_dir = dir
			m.last_fire_at = now
			return _reflex_intent("clash", dir, now, m)
	if action == "none":
		return {}
	if action == "walk":
		# Walking out is not an ANSWER, it is an interest override handed to the
		# steering layer — so it must not preempt the utility layer. A bot that
		# stopped casting because it was strafing would never cast at all.
		return {}

	# ⚠ NEVER LATCH AN ANSWER THE BODY CANNOT EXPRESS. `_reflex_intent` turns a dash
	# or a blink into a movement-key press, and `_flatten` has to drop any purely
	# vertical component because there is no "walk down" on this body. If that leaves
	# an EMPTY movement vector the press goes out with no direction, the bot burns a
	# cooldown, and — far worse — `dodge_until` freezes the whole reflex layer for the
	# length of the latch while the bot stands in the attack. Falling through to the
	# steering layer is strictly better than a latched no-op: at least the bot keeps
	# walking out. Belt-and-braces behind the ladder's own ordering fix in BotDodge.
	if (action == "dash" or action == "blink") and _flatten(dir) == Vector2.ZERO:
		return {}

	m.dodge_action = action
	m.dodge_dir = dir
	m.dodge_until = now + DODGE_LATCH
	if action == "dash" or action == "dash_iframe":
		m.last_dash_at = now
	elif action == "blink":
		m.last_blink_at = now
	elif action == "parry":
		m.last_guard_at = now
		# Press EARLY and hold. The perfect band opens ~0.37 s into the shrink, so
		# a guard pressed on contact has already lost; guard_hold_until is what
		# carries the press across the frames until the blow lands.
		# Hold only as long as the guard is worth anything. A press-window class CANNOT
		# extend its window by holding — the press is edge-triggered — so the flat
		# 0.48 s hold was up to 0.32 s of standing still with no guard up. That is not
		# merely wasted: a guarding frame issues no attack AND sets `foe_guarding` on
		# the opponent's blackboard, so it also talks them out of swinging. Two bots
		# politely declining to fight is the exact degenerate the stagnation breaker
		# exists to undo.
		m.guard_hold_until = now + float(bb.get("guard_lead", GUARD_BAND_BLADE)) \
			+ float(bb.get("guard_tolerance", 0.0)) + GUARD_HOLD_TAIL
	return _reflex_intent(action, dir, now, m)


## Ladder action -> the buttons that express it. The mapping is the only place the
## brain knows what a "dash" costs a body, which is what keeps the ladder itself
## body-agnostic.
static func _reflex_intent(action: String, dir: Vector2, _now: float,
		_m: Memory) -> Dictionary:
	match action:
		"dash", "dash_iframe":
			# The dash fires along the MOVEMENT vector, not the aim — so the move
			# key has to be set in the same frame as the dash press or the dash goes
			# wherever the bot happened to already be walking.
			return {"dash": true, "move": _flatten(dir)}
		"blink":
			return {"dash": true, "move": _flatten(dir)}
		"parry":
			return {"guard": true, "move": Vector2.ZERO}
		"jump":
			return {"jump": true, "move": Vector2(_flatten(dir).x, -1.0)}
		"clash":
			return {"fire": true, "move": _flatten(dir) * 0.4}
	return {}


## ⚠ THE ONLY DASH IN THIS FILE WAS A DODGE, WHICH IS WHY NOBODY EVER SAW ONE.
##
## Maker: *"the stick men do not use the dash function at all why is that its such a
## cool looking function like seriously"*. They are right, and it is structural rather
## than a tuning miss: `BotDodge.choose_response` reaches dash ONLY as an answer to a
## perceived threat, and threats enter through the single door
## `BotController.perceive_threats`, which scans three groups that 36 of the game's
## spectacles never join. On a stage where little registers as a threat, the dash is
## never pressed at all.
##
## So this adds the two uses a human actually gets out of it, neither of which is a
## dodge:
##   * CLOSING — a long approach is something a player dashes and a bot walked.
##   * RECOVERING — launched and drifting away from the stage, a player dashes back.
##     Maker, earlier: *"if they are being sent up in the air they can dash to get
##     back"*.
##
## ⚠ IT DOES NOT END THE FRAME, and that is deliberate. An early return here would
## cost the cast this frame was going to make, and `slice6_test_bot_brain` holds the
## brain to >= 12 casts across a neutral window precisely so a new rung cannot quietly
## make the bots go quiet. The dash is added to the intent and the ladder carries on.
##
## ⚠ AND IT IS SPACED BY A CLOCK, NOT BY READINESS. See `DASH_TRAVEL_SPACING`.
## Get level with a foe that is above this bot. See the AIR_REACH_* block for why
## nothing already in `decide` could do it.
##
## Writes `intent["jump"]` — NOT `move.y`, which is `move_up` and does not jump — and
## nudges `move.x` only enough to stay under the target while rising. Deliberately
## does nothing about the swing itself: once the bot is level, the ordinary reach and
## cone tests pass on their own, which is the whole point of getting level.
static func _reach_upward(intent: Dictionary, bb: Dictionary, m: Memory,
		now: float) -> void:
	if int(bb.get("foe_id", 0)) == 0:
		return
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	# Screen space: smaller y is HIGHER, so a positive rise means the foe is above.
	var rise: float = me.y - foe.y
	if rise < AIR_REACH_MIN_RISE:
		return
	var span: float = absf(foe.x - me.x)
	if span > AIR_REACH_MAX_SPAN:
		return                      # mostly a walk — `_steer` owns that
	# Stay under them on the way up. Past the alignment window the bot is close
	# enough that another sidestep would slide it out from under the target.
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	if span > AIR_REACH_ALIGN:
		intent["move"] = Vector2(signf(foe.x - me.x), move.y)
	else:
		intent["move"] = Vector2(0.0, move.y)
	# ⚠ FROM THE FLOOR ONLY, and spaced. `Hero` gives a class its air jumps on its own
	# (the Brawler has one, the Shadowblade two), so re-pressing mid-arc would spend
	# them instantly and cap the climb LOWER than a single committed jump reaches.
	if not bool(bb.get("on_floor", false)):
		return
	if now - m.last_air_reach_at < AIR_REACH_SPACING:
		return
	intent["jump"] = true
	m.last_air_reach_at = now


## The settled shuffle — see the IDLE_JOCKEY block. A smooth sway rather than a square
## step, so the body eases through the turn instead of snapping between two poses, and
## phase-offset per bot so both fighters do not rock in time with each other.
static func _idle_jockey(m: Memory, now: float) -> float:
	if m == null:
		return 0.0
	if m.jockey_phase < 0.0:
		m.jockey_phase = m.rng.randf() * TAU
	return IDLE_JOCKEY * sin(now * TAU * IDLE_JOCKEY_HZ + m.jockey_phase)


static func _traverse_dash(intent: Dictionary, bb: Dictionary, m: Memory,
		now: float) -> void:
	if now - m.last_dash_at < DASH_TRAVEL_SPACING:
		return
	# Absent means "assume ready" for the minimum blackboard, but a body that
	# publishes the flag is believed — same rule as `_caps`.
	if not bool(bb.get("dash_ready", true)):
		return
	var self_pos: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe_pos: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var toward: float = signf(foe_pos.x - self_pos.x)
	if toward == 0.0:
		return                      # exactly stacked: no direction to dash in

	if not bool(bb.get("on_floor", true)):
		# RECOVERING. Only when actually being carried AWAY — dashing mid-arc while
		# already heading back would cut short a jump the bot meant to make.
		var vel: Vector2 = bb.get("self_vel", Vector2.ZERO)
		if signf(vel.x) == -toward and absf(vel.x) > DASH_RECOVER_SPEED:
			intent["dash"] = true
			intent["move"] = Vector2(toward, 0.0)
			m.last_dash_at = now
		return

	# CLOSING. Only across a real gap, and only when the steering layer had already
	# decided to go that way — a dash that argues with the steering is the "dashing
	# nowhere, repeatedly" failure the latch note above warns about.
	if absf(foe_pos.x - self_pos.x) < DASH_CLOSE_MIN:
		return
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	if signf(move.x) != toward:
		return
	intent["dash"] = true
	intent["move"] = Vector2(toward, 0.0)
	m.last_dash_at = now


## What this body can currently do, in the shape BotDodge.choose_response reads.
##
## READINESS IS ASSUMED PESSIMISTICALLY. When the blackboard does not publish a
## cooldown we hold ourselves to the body's real one from our own last press,
## rather than assuming ready — assuming ready is a cheat by omission and would
## show up in play as a bot dashing four times a second.
static func _caps(bb: Dictionary, profile: Dictionary, m: Memory, now: float,
		threat: Dictionary) -> Dictionary:
	var dash_ready: bool = _ready_flag(bb, "dash_ready", CD_DASH_INDEX,
		now - m.last_dash_at >= DASH_COOLDOWN)
	var blink_ready: bool = bool(bb.get("blink_ready", now - m.last_blink_at >= BLINK_COOLDOWN))
	# `guard_style` is a `ParryRing.Style` (0 BLADE / 1 SIGIL), or -1 for a body that
	# runs a plain press window and holds no ring at all. It used to be published as
	# "do I hold a ring", which made every BLADE holder look like a SIGIL — see the
	# block at `Hero.bot_body_state`.
	var sigil: bool = int(bb.get("guard_style", -1)) == ParryRing.Style.SIGIL
	# ⚠ PREFER THE BODY'S OWN NUMBER, same rule as `dash_dist` and `guard_lead` below.
	# The consts are a hand-copy of ParryRing's and survive only as the fallback for a
	# body that publishes nothing (an Enemy).
	var rearm: float = float(bb.get("guard_rearm",
		GUARD_REARM_SIGIL if sigil else GUARD_REARM_BLADE))
	var guard_ready: bool = _ready_flag(bb, "guard_ready", CD_GUARD_INDEX,
		now - m.last_guard_at >= GUARD_SHRINK + rearm)
	# THE GUARD IS PRESSED EARLY, SO ITS "WINDOW" IS A LEAD TIME, NOT A REACTION
	# WINDOW. We want the blow to arrive in the middle of the shrinking ring's
	# perfect band; guard skill decides how near that middle we aim, and the
	# remainder becomes a real mistiming that really eats the hit.
	# ⚠ PREFER THE BODY'S OWN NUMBER — the same "read it from the seam" rule
	# `dash_dist` already follows, and for the same reason: the consts below describe
	# a shrinking ParryRing, and SEVEN OF NINE CLASSES HAVE NO RING AT ALL. They run a
	# press window that opens immediately and lasts 0.16 s, so a 0.374 s lead pressed
	# the guard and let it lapse a fifth of a second before the blow arrived. The style
	# enum could not carry this: `guard_style` is documented as "0 BLADE / 1 SIGIL"
	# here and as "0 = a press window, 1 = a held BLADE ring" on the body, which are
	# opposite meanings. The consts survive as the fallback for a body that publishes
	# nothing (an Enemy).
	var band: float = float(bb.get("guard_lead",
		GUARD_BAND_SIGIL if sigil else GUARD_BAND_BLADE))
	var skill: float = BotProfile.get_f(profile, "guard")
	# ⚠ SKILL NARROWS THIS WINDOW, WHICH MAKES THE BEST BOTS THE WORST AT PARRYING —
	# and Watch Bots runs at the top tier, so the mode the maker watches had the fewest
	# openings in the game. At guard 0.92 the half-width is 0.0404 s, about 2.4 physics
	# frames, against a `tti` that can only step in 0.0167 s increments: the band is
	# barely resolvable by the sampler reading it.
	#
	# ⚠ AND THE BODY ALREADY PUBLISHES ITS REAL TOLERANCE, WHICH NOTHING READ.
	# `Hero.bot_body_state` sends `guard_tolerance` — 0.080 s for the seven classes that
	# run a press window, 0.200 s for the Juggernaut's block — and `in_lead` used a
	# skill curve instead, i.e. a window HALF the body's true one at the tier everything
	# is measured at. Flooring at the body's own number is the same "read it from the
	# seam" rule `dash_dist` and `guard_lead` above already follow.
	#
	# ⚠ THIS IS NOT THE REVERTED CROSS-CLASS CHANGE. That one added a flat global
	# `SLACK_FLOOR` and was reverted on the maker's ruling *"do not change the deflect
	# across all classes to fix one"*. This reads each body's OWN published number, so
	# the Swordsaint (0.0462, narrower than tier-3 slack) is byte-identical and only the
	# classes whose real window is wider than the curve move. A body that publishes
	# nothing (an Enemy) keeps the curve exactly.
	var slack: float = maxf(lerpf(0.16, 0.03, clampf(skill, 0.0, 1.0)),
		float(bb.get("guard_tolerance", 0.0)))
	# ⚠ A GUARD BAND LONGER THAN THE WHOLE TELL IS A BAND THAT CAN NEVER BE MET, and
	# that is the second half of the maker's *"not much deflecting"*.
	#
	# `band` is the class's own preferred lead — around 0.37 s for a ring guard — and
	# `in_lead` asks for `tti` to land inside `slack` of it. A hero MELEE swing tells for
	# `ONE_SHOT_DURATIONS * HIT_FRAME_FRACTION`, i.e. 0.077 s for a punch and 0.091 s for
	# a kick, so `tti` STARTS at 0.077 and only falls: `|tti - 0.37|` is never once
	# smaller than a 0.08 slack, on any frame, for any class. The parry rung was
	# unreachable for the entire contact half of the roster by arithmetic, before any
	# question of skill or timing arose.
	#
	# So the band collapses onto the threat's OWN total lead when that lead is shorter.
	# It is the honest reading of what a guard band means — "how far ahead of the hit I
	# like to commit" cannot exceed how much warning the attack ever gave — and it can
	# only ever make a band TIGHTER, so no threat that was parryable before becomes
	# harder. Threats that publish no lead (every projectile) are untouched.
	var lead: float = float(threat.get("lead", 0.0))
	if lead > 0.0:
		band = minf(band, lead)
	var tti: float = float(threat.get("tti", 99.0))
	var in_lead: bool = absf(tti - band) <= slack
	return {
		"dash_ready": dash_ready,
		# ⚠ PREFER THE BODY'S OWN NUMBER. `DASH_DIST` is a hand-copied `620 * 0.14` and
		# the movement button is now NINE different verbs whose travel runs from ~58 px
		# (Juggernaut surge) to 260 px (Stormcaller lightning blink) — so the copy is
		# wrong for eight of the nine classes and a bot would size every gap-close with
		# the Arcanist's numbers. `Hero.bot_body_state` publishes the derived value;
		# the const survives as the fallback for a body that does not (an Enemy).
		"dash_dist": float(bb.get("dash_dist", DASH_DIST)),
		"blink_ready": blink_ready,
		"blink_dist": BLINK_DIST,
		"can_parry": bool(bb.get("can_parry", true)) and bool(threat.get("parryable", true)),
		"parry_ready": guard_ready and in_lead,
		# choose_response gates the parry rung on `tti <= parry_window`, and the lead
		# test above has already decided the timing — so pass a value that lets it
		# through iff we meant it to.
		"parry_window": 99.0 if in_lead else -1.0,
		"grounded": bool(bb.get("on_floor", true)),
		# TWO GATES, and they answer different questions. The profile one is
		# DIFFICULTY ("is this bot allowed to make that read"); the body one is
		# CAPABILITY ("does my movement button dodge anything at all"). The Brawler's
		# charge and the Juggernaut's surge ship `dash_iframe_fraction: 0.0` — spending
		# either as an i-frame answer is choosing to eat the hit, so a bot must not.
		# Absent key -> true, which is every non-Hero body and is byte-identical to
		# the behaviour before the nine verbs existed.
		"allow_iframe": BotProfile.get_b(profile, "iframe")
			and bool(bb.get("dash_iframes", true)),
	}


## Candidate exits, re-scored against pits and every OTHER live danger footprint,
## and the best one returned. Dodging out of a blast into a pit is the most
## embarrassing thing a bot can do and it is entirely avoidable, so nothing gets
## trusted until it has been through here.
static func _safest(bb: Dictionary, me: Vector2, candidates: Array[Vector2],
		threat: Dictionary) -> Vector2:
	var hazards: Array[Rect2] = []
	for h: Variant in bb.get("hazards", []):
		if typeof(h) == TYPE_RECT2:
			hazards.append(h)
	var regions: Array[Dictionary] = []
	for t: Variant in bb.get("threats", []):
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = t
		# Skip the threat we are already solving for: it is the thing we are leaving,
		# and counting it would score every exit as landing in danger.
		if int(d.get("id", 0)) == int(threat.get("id", -1)):
			continue
		# ⚠ `region` FIRST, AND WITHOUT IT A BOT DODGED STRAIGHT INTO LANES.
		#
		# `BotController.perceive_threats` publishes every threat with a ready-made
		# `region` in exactly the shape `BotDodge.point_in_region` takes — that is what
		# the key is FOR, and `BotController.danger_regions()` exists to extract it.
		# Nothing ever called either. This function reconstructed a footprint from
		# `shape` (which no threat record carries at top level) or from `radius`, and a
		# LANE telegraph publishes `radius: 0.0`.
		#
		# So lanes fell through BOTH branches and were never counted as somewhere not
		# to land. Circles and projectiles survived on the radius fallback, which is
		# why this looked like it worked: the failure was invisible in exactly the case
		# — a charger's lane, a sword arc, Crescent Rush, Iai Slash — where a sideways
		# dodge is most likely to cross the very thing being dodged.
		if d.has("region") and typeof(d["region"]) == TYPE_DICTIONARY:
			regions.append(d["region"])
		elif d.has("shape"):
			regions.append(d)
		elif float(d.get("radius", 0.0)) > 0.0:
			regions.append({"shape": "circle", "center": d.get("pos", Vector2.ZERO),
				"radius": float(d.get("radius", 0.0))})
	var first: Vector2 = candidates[0] if not candidates.is_empty() else Vector2.ZERO
	if hazards.is_empty() and regions.is_empty():
		return first
	var best: Vector2 = BotDodge.safest_exit(me, candidates, hazards, regions)
	# safest_exit returns ZERO when EVERY option lands somewhere lethal. That is a
	# real answer — "there is nowhere good" — and the caller reads it as such rather
	# than being handed a bad exit dressed up as a good one.
	return best


## Should the bot answer a swing with a swing? Only when it genuinely cannot get
## out (the ladder already failed), the threat is at body range, and the profile is
## aggressive enough to want the trade. A timid bot eats the hit instead, which is
## the correct read for it.
static func _clash_worthwhile(bb: Dictionary, profile: Dictionary, m: Memory,
		now: float, threat: Dictionary) -> bool:
	if now - m.last_fire_at < MELEE_COOLDOWN:
		return false
	if BotProfile.get_f(profile, "aggression") < 0.5:
		return false
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var reach: float = float(bb.get("reach", 58.0))
	if me.distance_to(foe) > reach * 1.2:
		return false
	return float(threat.get("tti", 99.0)) <= 0.25


# =========================================================================
# LAYER 2 — CONTEXT STEERING
# =========================================================================

## Where to stand, as a move vector. Interest is the class's spacing band; danger is
## every footprint and pit on the board. This is context steering flattened to one
## axis, which is the right shape for a side-on platformer: the vertical half of the
## decision is a jump, not a Y velocity.
static func _steer(bb: Dictionary, profile: Dictionary, m: Memory, evaluated: Array,
		pressure: float, stagnation: float, now: float = 0.0) -> Vector2:
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var dist: float = me.distance_to(foe)
	var toward: float = signf(foe.x - me.x)
	if toward == 0.0:
		toward = 1.0

	# A LOOSE SPELL ON THE FLOOR IS WORTH WALKING FOR. Tier 2 floor drops and Tier 3
	# boss drops are the whole reason the kit changes mid-run, and a bot that walks
	# past them fights the fight it started with while the human upgrades. Only taken
	# when the board is quiet and the pickup is genuinely mine to take — diving
	# through a live telegraph for a spell is a worse play than not having it.
	var grab: float = _pickup_pull(bb, me, foe, pressure)
	if grab != 0.0:
		return Vector2(grab, 0.0)

	var band: Dictionary = _band(bb, profile, stagnation)
	var lo: float = float(band["min"])
	var hi: float = float(band["max"])
	var centre: float = (lo + hi) * 0.5
	var width: float = maxf(hi - lo, 1.0)

	# ⚠ A DEADBAND IS NOT HYSTERESIS, AND THIS IS THE "BACK AND FORWARD".
	#
	# Maker: *"the movement is weird like sometimes the guy is just going back and
	# forward"*. The comment this replaces claimed the deadband was what stopped that.
	# It is not, and it cannot be: `BAND_DEADZONE` widens the band by a fixed 16% and is
	# perfectly SYMMETRIC with no memory of the previous frame, so crossing the outer
	# edge gives full-speed `+toward` and crossing the inner edge gives full-speed
	# `-toward` on the very next physics frame, forever. The `Memory` object was even
	# passed in as `_m` — underscored, i.e. deliberately unread — and nothing anywhere
	# in the brain remembered which way this bot was already walking. Every latch in the
	# file (CAST_LATCH, DODGE_LATCH, latched_slot) is on the CAST or the DODGE; the walk
	# had none.
	#
	# So this is a Schmitt trigger instead: TRIGGER at the band edge, RELEASE at the
	# band CENTRE. Having decided to close, the bot keeps closing until it reaches the
	# middle of its own band rather than stopping the instant it clips the edge — which
	# is what makes the approach read as a decision and puts a whole half-band of travel
	# between one reversal and the next.
	var intent: int = 0
	if dist > hi + width * BAND_DEADZONE:
		intent = 1                       # too far — close in
	elif dist < lo - width * BAND_DEADZONE:
		intent = -1                      # too close — back off
	elif m != null and m.steer_intent != 0:
		# Inside the band, but still travelling: hold the committed direction until the
		# centre. Stored as an INTENT (closing / backing off) rather than as a world
		# direction on purpose — two fighters swap sides constantly, and a remembered
		# `+x` would read as "back off" the moment they crossed.
		if m.steer_intent > 0 and dist > centre:
			intent = 1
		elif m.steer_intent < 0 and dist < centre:
			intent = -1

	# ...and a floor on how often the answer may CHANGE AT ALL. The trigger above fixes
	# the band edges; it does nothing about the other two reversal sources measured in
	# this file — the recoil flinch (55% per hit, 0.28 s of forced retreat, then instant
	# resumption) and two bots' bands interacting. A minimum dwell costs at most
	# STEER_MIN_DWELL of stale walking and is the difference between a stance and a
	# stutter.
	if m != null:
		if intent != 0 and m.steer_intent != 0 and intent != m.steer_intent \
				and now < m.steer_until:
			intent = m.steer_intent
		if intent != m.steer_intent:
			m.steer_intent = intent
			m.steer_until = now + STEER_MIN_DWELL

	var want: float = float(intent) * toward

	# Settled inside the band — shuffle rather than plant. See IDLE_JOCKEY.
	if is_zero_approx(want):
		want = _idle_jockey(m, now)

	# COVER. A wall between me and the foe is worth standing behind when I am hurt,
	# so the urge to cross it is damped rather than vetoed — vetoed would leave a
	# low bot cowering behind a wall that is about to expire.
	var hp: float = float(bb.get("self_hp_frac", 1.0))
	if hp < 0.4 and _cover_between(bb, me, foe):
		want *= 0.25

	# DANGER. Score the two lateral steps (and standing still) against the pits and
	# the live footprints, and take the best. Reusing the dodge module's scorer here
	# is deliberate: "never walk into a pit" and "never dodge into a pit" must be the
	# same rule or the bot will learn to stroll into the one it just dived out of.
	var probe: Vector2 = Vector2(signf(want), 0.0) * STEER_PROBE
	if probe != Vector2.ZERO:
		# ⚠ ASKED AS A VETO, NOT AS A CHOICE — AND THAT IS THE THIRD REVERSAL SOURCE.
		#
		# This used to hand `_safest` BOTH steps at once (`[probe, -probe]`) and take
		# whichever scored better. Those two vectors are the same LENGTH, so whenever any
		# live telegraph or pit is on the board the ranking between them is decided by a
		# margin that a moving threat footprint flips from one frame to the next — and
		# `want` flipped with it, with nothing damping it. It also explains the maker's
		# *"SOMETIMES"*: with a clean board `_safest` short-circuits to `candidates[0]`
		# and the direction survives, so the stutter only appears once the fight has
		# things in the air.
		#
		# Scoring ONE option answers "is the way I want to go lethal", which is the
		# question actually being asked. The alternative is only consulted when the
		# answer is yes, so safety still has the last word and the tie cannot exist.
		if _safest(bb, me, [probe] as Array[Vector2], {}) == Vector2.ZERO:
			# ⚠ THE ANSWER IS HOLD, NOT REVERSE — and the difference was MEASURED, not
			# reasoned. Reversing on a veto scored mean 0.85 / worst 2.92 reversals per
			# second against the old form's 1.18 / 1.58: better on average and visibly
			# WORSE at the extreme, because a footprint sweeping on and off the wanted
			# side toggles the veto and the bot pumps back and forth in place. Holding
			# scores below both.
			#
			# It is also the more honest division of labour. Steering owns SPACING; the
			# reflex ladder above it owns getting out of the way, with dashes, jumps and
			# blinks that actually clear a region. A spacing rule that answers danger by
			# walking the other way is doing the dodge layer's job badly, and standing
			# still for a beat has never once read as a stutter.
			want = 0.0
			if m != null and m.steer_intent != 0:
				m.steer_intent = 0
				m.steer_until = now + STEER_MIN_DWELL

	# Under real pressure with nowhere useful to be, drift AWAY rather than stand
	# still: a stationary target is the easiest thing in the game to telegraph onto.
	if want == 0.0 and pressure > 0.7:
		want = -toward
	# ...and in a fight that has gone nowhere, drift TOWARD instead. A held stance is
	# only a stance while the fight is happening; once it has stalled, standing in it
	# IS the stall.
	elif want == 0.0 and stagnation > 0.35 and dist > lo:
		want = toward

	# A vertical exit that the reflex layer did not take (it was not urgent enough to
	# preempt) still deserves a jump — the ledge geometry is the same either way.
	var up: float = 0.0
	for e: Dictionary in evaluated:
		if not bool(e.get("threatening", false)):
			continue
		var ex: Vector2 = e.get("exit", Vector2.ZERO)
		if ex.length_squared() > 0.01 and ex.normalized().dot(Vector2.UP) >= BotDodge.VERTICAL_EXIT_DOT:
			up = -1.0
			break
	return Vector2(clampf(want, -1.0, 1.0), up)


## The class's spacing band, pulled toward contact by aggression. One table plus one
## scalar rather than a band per class per difficulty.
static func _band(bb: Dictionary, profile: Dictionary,
		stagnation: float = 0.0) -> Dictionary:
	var cid: int = int(bb.get("class_id", -1))
	var b: Dictionary = DEFAULT_BAND
	if cid >= 0 and cid < CLASS_BAND.size():
		b = CLASS_BAND[cid]
	var aggr: float = BotProfile.get_f(profile, "aggression")
	# 0.5 aggression = the authored band. 1.0 pulls it 30% closer, 0.0 pushes it 30%
	# further out — the same class, played by two different temperaments.
	var scale: float = lerpf(1.3, 0.7, clampf(aggr, 0.0, 1.0))
	# ...and a fight that has stopped producing damage pulls it further in still. Two
	# ranged classes each correctly holding a 340 px band never meet; one of them has
	# to blink first, and after ten seconds of nothing they both do.
	scale *= lerpf(1.0, 1.0 - STAGNATION_BAND_PULL, clampf(stagnation, 0.0, 1.0))
	return {"min": float(b["min"]) * scale, "max": float(b["max"]) * scale}


## Walk toward a loose spell? Returns -1 / 0 / +1 on the walk axis.
##
## Gated hard, because a bot that beelines for every pickup is a bot that can be
## kited into a pit by anyone who notices:
##   · nothing may be pressing (`pressure`), because leaving a live telegraph to
##     collect a spell is how you die holding it;
##   · the pickup must be genuinely CLOSER TO ME than to the foe, so two bots never
##     both commit to the same one and meet awkwardly on top of it;
##   · it must be within PICKUP_INTEREST, so a bot never crosses the whole stage.
##
## Perception cost: none beyond what a player pays. A `SpellPickup` is a drawn,
## glowing object sitting on the floor — the most visible thing in the arena.
const PICKUP_INTEREST: float = 520.0
const PICKUP_CONTEST_MARGIN: float = 0.85


static func _pickup_pull(bb: Dictionary, me: Vector2, foe: Vector2,
		pressure: float) -> float:
	if pressure > 0.25:
		return 0.0
	var best: Vector2 = Vector2.ZERO
	var best_d: float = PICKUP_INTEREST
	for p: Variant in bb.get("pickups", []):
		if typeof(p) != TYPE_VECTOR2:
			continue
		var at: Vector2 = p
		var d: float = me.distance_to(at)
		if d >= best_d:
			continue
		# Contested? Then it is not mine and walking at it is walking at the foe.
		if at.distance_to(foe) * PICKUP_CONTEST_MARGIN <= d:
			continue
		best_d = d
		best = at
	if best == Vector2.ZERO:
		return 0.0
	# Close enough that the pickup area will collect it — stop steering and fight.
	if absf(best.x - me.x) < 26.0:
		return 0.0
	return signf(best.x - me.x)


## Is a barrier sitting on the line between me and the foe? Approximate on purpose —
## a point-to-segment distance against each barrier's radius. Precision here would
## buy nothing: the question is "is there something to hide behind", not "by how many
## pixels".
static func _cover_between(bb: Dictionary, me: Vector2, foe: Vector2) -> bool:
	var seg: Vector2 = foe - me
	var len2: float = seg.length_squared()
	if len2 <= 0.01:
		return false
	for b: Variant in bb.get("barriers", []):
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = b
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var t: float = clampf((p - me).dot(seg) / len2, 0.0, 1.0)
		if p.distance_to(me + seg * t) <= float(d.get("radius", 40.0)):
			return true
	return false


# =========================================================================
# LAYER 3 — THE UTILITY SCORER
# =========================================================================

## Which slot to press, or -1 for none. Rate-limited to once per `profile.period`
## and latched in between, so the expensive pass runs a handful of times a second
## and the bot actually finishes the cast it started.
static func _pick_slot(bb: Dictionary, profile: Dictionary, m: Memory, now: float,
		pressure: float, soonest: float, stagnation: float = 0.0) -> int:
	if now < m.latched_until:
		return -1     # already spent this decision; the press was emitted on the frame it was made
	if now < m.next_decision_at:
		return -1
	m.next_decision_at = now + BotProfile.get_f(profile, "period")
	# Re-sample the aim scatter on the same beat as the decision. Per-frame sampling
	# would average to a perfect shot over a channel; per-decision sampling means the
	# bot commits to one wrong angle, which is what missing looks like.
	var err: float = BotProfile.get_f(profile, "aim_error")
	m.aim_error = m.rng.randf_range(-err, err)

	# ══ THE LAST STAND ══════════════════════════════════════════════════════════
	# Maker: *"use their ults if low on health like optionally of course"*. The "ult"
	# role's own weight is keyed entirely off the FOE's health and the foe closing —
	# `finisher = 1.15 - foe_hp` — so it fires when the bot is WINNING and has nothing
	# at all to say about a bot that is about to die. A fighter going down swinging is
	# the single most watchable thing a duel can produce and it could not happen.
	#
	# Rolled once per decision beat, then LATCHED: a continuous bonus flickers across
	# the threshold and reads as indecision, where a latch reads as a decision. And
	# rolled rather than triggered, because "optionally" is the whole ask — two
	# Cryomancers at 30% should not both reliably do the same thing.
	if float(bb.get("self_hp_frac", 1.0)) < DESPERATE_HP and now >= m.ult_urge_until \
			and m.rng.randf() < DESPERATE_ULT_CHANCE:
		m.ult_urge_until = now + DESPERATE_ULT_HOLD
	var desperate: bool = now < m.ult_urge_until

	var scores: Array = score_slots(bb, profile, m, now, pressure, soonest)
	var best: int = -1
	# Kept alongside `best_score`, which starts AT the threshold and so cannot report
	# what the hand actually offered when nothing cleared it.
	var top_any: float = 0.0
	var ult_final: float = 0.0
	# A stalled fight forgives part of the threshold: the bot starts spending
	# cooldowns it was holding for a better moment that is demonstrably not coming.
	var best_score: float = CAST_THRESHOLD * lerpf(1.0, 1.0 - STAGNATION_THRESHOLD_CUT,
		clampf(stagnation, 0.0, 1.0))
	if desperate:
		# Forgiven exactly the way stagnation forgives it directly above, rather than
		# with a second mechanism that means the same thing.
		best_score *= 1.0 - STAGNATION_THRESHOLD_CUT
	for i: int in range(scores.size()):
		var s: float = float(scores[i])
		# ⚠ THE BONUS IS A MULTIPLIER ON A SCORE, NOT A BYPASS. Every HARD gate lives
		# inside `score_slots` and returns a flat 0 — cooldown, mana, `slot_affordable`,
		# range fit, channel safety — and 0 times anything is still 0. So a desperate
		# bot cannot cast an ult it could not otherwise cast; it can only stop being
		# talked out of one it could.
		if desperate and i == SpellTier.ULT_SLOT:
			s *= DESPERATE_ULT_BONUS
		if i == SpellTier.ULT_SLOT:
			ult_final = s
		if s > top_any:
			top_any = s
		if s > best_score:
			best_score = s
			best = i
	# The last question the counters cannot answer from inside `score_slots`: the ult
	# passed every gate, scored highest of anything on the hand, and STILL was not
	# pressed — because the whole hand was under the cast threshold. That is a
	# different complaint from "a gate refused it" and wants a different fix, so it is
	# counted apart rather than folded into the gate tally.
	if best < 0 and ult_final > 0.0 and ult_final >= top_any:
		ult_best_but_under_threshold += 1
	return best


# =========================================================================
# LAYER 3b — THE ABILITY BUTTONS (Q / R / T)
# =========================================================================

## Which of the three class abilities to press this frame, or `&""`.
##
## THESE ARE NOT KIT SLOTS and they are deliberately not scored against them. They
## cost nothing (no mana, no role, no reaction identity) so a shared scorer would
## always prefer them and the kit would stop coming out; instead they are consulted
## only when the kit scorer has already declined, and paced against each other by
## `ABILITY_SPACING` so all three never land in one frame.
##
## Each one is chosen by the SHAPE OF THE BUTTON on this class, from `CLASS_ABILITIES`:
##   Q blast   a placed / self-centred AoE every class has. Wants the foe inside it
##             and me not standing on the detonation.
##   R blink   a teleport on six classes and a rising UPPERCUT on the Brawler and
##             the Swordsaint. Pressing "blink" to cross a gap on a class whose R is
##             an uppercut is a wasted cooldown and a lunge into nothing, which is
##             exactly the kind of bug that reads as "the AI is stupid".
##   T nova    a self-centred burst, and the Shadowblade simply does not have one.
static func _pick_ability(bb: Dictionary, profile: Dictionary, m: Memory,
		now: float, pressure: float) -> StringName:
	if now - m.last_ability_at < ABILITY_SPACING:
		return &""
	var cid: int = int(bb.get("class_id", -1))
	var kit: Dictionary = DEFAULT_ABILITIES
	if cid >= 0 and cid < CLASS_ABILITIES.size():
		kit = CLASS_ABILITIES[cid]
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	if int(bb.get("foe_id", 0)) == 0:
		return &""
	var dist: float = me.distance_to(foe)
	var aggr: float = BotProfile.get_f(profile, "aggression")

	# --- T: the panic burst. Highest priority of the three because it is the only
	# one that answers "there is a body on top of me" without spending a dash.
	if bool(kit.get("nova", true)) and dist <= NOVA_RANGE \
			and _cd_ready(bb, CD_NOVA_INDEX) and pressure > 0.35:
		return BotIntent.ABILITY_NOVA

	# --- R: two opposite jobs on one button, decided by what R IS on this class.
	var blink_kind: String = String(kit.get("blink", ""))
	if blink_kind != "" and _cd_ready(bb, CD_BLINK_INDEX):
		if blink_kind == "uppercut":
			# A rising cut. Contact only, and only when this bot wants the trade.
			if dist <= UPPERCUT_RANGE and aggr >= 0.45:
				return BotIntent.ABILITY_BLINK
		else:
			# A teleport. Close a gap too big to walk when the bot is committed, or
			# leave one that has become too small while it is being pressed.
			if dist >= BLINK_CLOSE_MIN and aggr >= 0.5 and pressure < 0.4:
				return BotIntent.ABILITY_BLINK
			if pressure > 0.6 and dist <= float(bb.get("reach", 58.0)) * 1.6:
				return BotIntent.ABILITY_BLINK

	# --- Q: the class AoE. The workhorse, and the reason it is last is that it is
	# the one with the widest usable window — checking it first would starve the
	# other two.
	if _cd_ready(bb, CD_BLAST_INDEX) and dist >= BLAST_MIN and dist <= BLAST_MAX:
		return BotIntent.ABILITY_BLAST
	return &""


## Is the extra cooldown at `index` reported ready? Absent / short array reads as
## NOT ready — the pessimistic answer, matching `_caps`. Assuming ready is a cheat
## by omission, and for the ability buttons it would show up as a bot mashing Q.
static func _cd_ready(bb: Dictionary, index: int) -> bool:
	var cds: Array = bb.get("cooldowns", [])
	if index >= cds.size():
		return false
	return float(cds[index]) <= 0.0


## The melee SWING — a different button from `fire` on every class, and one no
## brain had ever pressed. Only in contact, only off cooldown.
static func _wants_swing(bb: Dictionary, m: Memory, now: float) -> bool:
	if now - m.last_swing_at < MELEE_COOLDOWN:
		return false
	if not _cd_ready(bb, CD_SWING_INDEX):
		return false
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	if int(bb.get("foe_id", 0)) == 0:
		return false
	# NEVER SWING INTO A RAISED GUARD. MeleeClash's locked rule pays the guard, so
	# this is the read that separates a bot from a training dummy.
	if bool(bb.get("foe_guarding", false)):
		return false
	return me.distance_to(foe) <= float(bb.get("reach", 58.0)) * 1.05


## Every slot scored. Public so the tests can assert the SHAPE of a decision — that
## the escape outscores the ult when the bot is cornered — rather than only its
## outcome, which would pass for the wrong reason as easily as the right one.
##
## IAUS-shaped: each consideration is a normalised 0..1 factor and they MULTIPLY, so
## any single hard "no" (on cooldown, cannot afford it, out of range, would be
## interrupted) zeroes the slot without needing to out-shout the other terms. The
## role weight and the combo bonus are the only additive parts, and both sit on top
## of the product.
static func score_slots(bb: Dictionary, profile: Dictionary, m: Memory, now: float,
		pressure: float, soonest: float) -> Array:
	var cooldowns: Array = bb.get("cooldowns", [])
	var facts: Array = facts_for(int(bb.get("self_id", 0)), int(bb.get("class_id", -1)))
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var foe_vel: Vector2 = bb.get("foe_vel", Vector2.ZERO)
	var dist: float = me.distance_to(foe)
	var hp: float = float(bb.get("self_hp_frac", 1.0))
	var mp: float = float(bb.get("self_mp_frac", 1.0))
	var foe_hp: float = float(bb.get("foe_hp_frac", 1.0))
	var risk: float = BotProfile.get_f(profile, "risk")
	var aggr: float = BotProfile.get_f(profile, "aggression")
	var combo_w: float = BotProfile.get_f(profile, "combo")
	# Is the foe committing toward me? A closing foe is a predictable foe, which is
	# what makes a payoff or an ult worth spending rather than saving.
	var to_me: Vector2 = (me - foe)
	var closing: float = 0.0
	if to_me.length() > 1.0 and foe_vel.length() > 1.0:
		closing = clampf(foe_vel.normalized().dot(to_me.normalized()), 0.0, 1.0)

	var out: Array = []
	for i: int in range(SLOT_COUNT):
		out.append(0.0)
	for i: int in range(SLOT_COUNT):
		# The ult is the one slot whose refusals are counted by reason — see the
		# ULT-SLOT TELEMETRY block. `is_ult` is hoisted so each gate below stays a
		# single branch rather than growing an index test of its own.
		var is_ult: bool = i == SpellTier.ULT_SLOT
		if is_ult:
			ult_considered += 1
		# --- hard gates. Any one of these makes the slot unavailable, full stop.
		if i < cooldowns.size() and float(cooldowns[i]) > 0.0:
			if is_ult:
				ult_gate_cooldown += 1
			continue
		if i >= cooldowns.size():
			if is_ult:
				ult_gate_absent += 1
			continue
		# ⚠ DOES THIS SLOT EXIST ON THIS BODY RIGHT NOW? `cooldowns` reports 0.0 for
		# a slot the class does not hold, which reads as READY, so a hand that came up
		# short scored an empty button as its best play. `slot_affordable` is the
		# body's own answer to "this slot exists AND is off cooldown" and is also what
		# tracks a Tier 2 / Tier 3 DROP replacing a slot mid-fight — a bot that
		# ignores it goes on scoring the spell it used to have. Absent key = trust the
		# cooldown array, so a minimal blackboard still works.
		var affordable: Array = bb.get("slot_affordable", [])
		if i < affordable.size() and not bool(affordable[i]):
			if is_ult:
				ult_gate_absent += 1
			continue
		var f: Dictionary = facts[i] if i < facts.size() else _default_facts(i)
		# The mana gate is VESTIGIAL — `Hero._cast_signature` no longer spends or
		# checks mana — but it is kept as a cheap guard for any future body that does,
		# and it costs nothing while `self_mp_frac` sits at 1.0.
		if mp * 100.0 < float(f["mp_cost"]):
			if is_ult:
				ult_gate_mana += 1
			continue
		var range_fit: float = _range_fit(dist, float(f["range"]), bool(f["close_ok"]))
		if range_fit <= 0.0:
			if is_ult:
				ult_gate_range += 1
			continue
		# THE CHANNEL GATE, and the reason it is a gate rather than a weight. A
		# levitating channel is interrupted by ANY landed hit, so starting one with
		# something already resolving inside the cast time is not a risky play, it is
		# a spell thrown away. `risk` only decides how much CLEAR AIR past the cast
		# time the bot insists on — never whether the rule applies.
		var ct: float = float(f["cast_time"])
		# Taken from the LIVE body wherever it publishes one. `_kit_facts` is cached
		# per class for the process (correctly — minting SpellDefs per frame is pure
		# garbage), but a Tier 2 / Tier 3 DROP replaces a slot's spell at runtime, so a
		# cached cast_time can describe a spell this hero no longer holds.
		var live_ct: Array = bb.get("slot_cast_time", [])
		if i < live_ct.size():
			ct = float(live_ct[i])
		var safety: float = 1.0
		if ct > 0.01:
			# ══ HOW OFTEN DOES THE GATE ACTUALLY REFUSE? ═══════════════════════
			# Maker: *"I havent seen many ults in these stick battles"*.
			#
			# `bot_cast_probe` (once its own hardcoded 3-slot blind spot was fixed)
			# shows the brain ASKING for slot 3 as often as any other — ~112 casts
			# against ~110 for the rest, all nine classes. So the brain is not the
			# reason. But that probe passes `"threats": []`, so `soonest` is 99 there
			# and this line never runs; it cannot see its own suspect.
			#
			# Five of the nine ults have `cast_time == 0.0` and sail past. The other
			# four — Meteor Sigil 1.1, Heaven's Verdict 1.3, Glacial Spine 1.1,
			# Horizon Cut 1.25 — need `cast_time + 0.25` of clear air.
			#
			# ⚠ COUNTED, NOT GUESSED, and counted because a fix was already tried and
			# REVERTED here: relaxing the gate below the cast time only loses the ult
			# a different way (an interrupted channel is a donated spell, which
			# `slice6_test_bot_brain` asserts and is right about). Process-wide and
			# free, exactly like `SpellDeflect.deflect_count`, which exists because
			# "the machinery is all there" was not evidence that it ran.
			channel_chances += 1
			if soonest < ct + CHANNEL_MARGIN:
				channel_refusals += 1
				if i == SpellTier.ULT_SLOT:
					ult_channel_refusals += 1
				continue
			safety = lerpf(0.55, 1.0, clampf(risk, 0.0, 1.0))

		# --- role weight: the situational half of the score.
		#
		# ⚠ MATCHED ON THE ROLE, NOT ON THE SLOT INDEX, and that changed when the hand
		# shrank to three buttons. Slot index used to BE the role for every class, so
		# `match i:` was exact. Now each class carries its damage line, its ult, and
		# ONE utility spell chosen from control / answer / payoff — so slot 1 is
		# zoning for the Arcanist and an escape for the Brawler, and matching on the
		# index would have scored every class's utility slot with whichever arm
		# happened to be written first. (It did, briefly: with the three role
		# constants aliased to the same index, GDScript's `match` silently took the
		# CONTROL arm for every class and the ANSWER and PAYOFF arms became dead code
		# that nothing reported.) `_kit_facts` carries the authored role per slot, so
		# the honest question is cheap to ask.
		var role: float = 0.0
		match String(f.get("role", "")):
			"damage":
				# The reliable line, and the default answer to "nothing special is
				# happening". Devalued under pressure — when things are landing on
				# you the answer slot should be winning, not this.
				role = (0.50 + 0.15 * aggr) * (0.60 + 0.40 * (1.0 - pressure))
			"control":
				# Zoning is worth most against a foe who is COMING TO YOU: a field
				# dropped on empty floor is a field nobody has to walk through. That
				# is the whole term — the base is deliberately under the damage line
				# so a bot does not zone at a foe who is standing still.
				role = 0.35 + 0.30 * closing
			"answer":
				# The get-out. Scales with BOTH how hurt and how pressed we are, so a
				# healthy bot keeps its escape and a cornered one spends it.
				role = 0.20 + 0.80 * maxf(pressure, 1.0 - hp)
			"payoff":
				# The biggest non-ult hit, and the one you set up for: worth spending
				# only when the foe is committed and I am not the one under pressure.
				role = 0.55 * clampf(0.30 + 0.45 * closing + 0.20 * (1.0 - pressure), 0.0, 1.0)
			"ult", "drop":
				# WILL IT LAND? A finisher against a hurt foe, a punish against a
				# closing one, and worth much less thrown at a healthy foe who is
				# keeping their distance. This is what stops the ult being dumped into
				# an empty arena the instant it comes off cooldown — and what makes it
				# beat everything else in the kit when the kill is actually there.
				#
				# ⚠ "drop" SHARES THIS ARM, AND THAT IS A BUG FIX, NOT A TUNING CHOICE.
				# `_facts_of` reports a tier-3 drop's role as "drop" and its comment
				# says the drop is "scored on its tier and its range rather than on a
				# role it was never authored for". No such scoring was ever written.
				# `role` is initialised to 0.0 and every arm here is a role string, so
				# "drop" fell through, `score` came out `0.0 * range_fit * safety` —
				# exactly zero — and the slot could only ever be pressed when a combo
				# bonus happened to lift it over the threshold on its own.
				#
				# MEASURED, on the shipped showcase config (`botmatch_sim --drops=1`),
				# over 8 bouts and 482 looks at the slot: mana refused 0, the channel
				# gate refused 0, the slot was never absent, and only 9 looks (2%)
				# scored above zero at all. The same run with `--drops=0` — the slot
				# holding the class's real ult, so the only difference is the role
				# string — scored 54 of the 78 looks that got past cooldown, 69%.
				# A 29x gap with one cause.
				#
				# It shares the ULT's arm rather than getting a hotter one of its own
				# because the drop DISPLACES the ult (`SpellGrant.TIER3_SLOT` IS
				# `SpellTier.ULT_SLOT`), so "wanted about as much as the thing it
				# replaced" is the honest default and it restores the pre-drop
				# behaviour exactly. How much MORE a showpiece should be wanted than
				# the ult it displaced is a feel call, and it is this line to change.
				var finisher: float = clampf(1.15 - foe_hp, 0.0, 1.0)
				role = 0.95 * clampf(0.15 + 0.55 * finisher + 0.35 * closing, 0.0, 1.0)
		var score: float = role * range_fit * safety

		# --- the anti-spam term. Decays over RECENCY_TAU, so a slot is not banned,
		# only devalued while it is still fresh in the fight.
		var last: float = float(m.last_slot_at.get(i, -99.0))
		var since: float = now - last
		if since < RECENCY_TAU:
			score *= 1.0 - RECENCY_PENALTY * exp(-since / RECENCY_TAU)

		# --- combos, both directions. Weighted by the profile so a low tier fights
		# with single spells and a high tier plays the reaction matrix.
		score += _combo_bonus(bb, m, now, i, f, facts, cooldowns, mp) * combo_w
		score -= _combo_penalty(bb, me, foe, f)
		out[i] = maxf(score, 0.0)
		if is_ult and out[i] > 0.0:
			ult_scored += 1
	return out


## How well the foe's distance suits this slot.
##
## The far end is the same for everything: at the edge of a spell's range the foe
## only has to take one step, so the fit falls away well before the hard cut-off.
##
## THE NEAR END IS SHAPE-DEPENDENT, and getting that wrong is the difference between
## a bot that fights and one that backs off to cast a lance it could have fired
## point-blank. A lance, a rush, a wall and a nova all START AT THE CASTER and are
## perfectly good in your face. A PLACED bombardment — a meteor, a ray, a pillar, a
## field — is a telegraphed circle you drop on the ground, so dropping it at your own
## feet means standing in it. Only those are penalised close in (`close_ok` false).
static func _range_fit(dist: float, usable: float, close_ok: bool) -> float:
	if usable <= 0.0:
		return 0.5
	var r: float = dist / usable
	if r > 1.0:
		return 0.0
	if not close_ok:
		if r < 0.15:
			return 0.35
		if r < 0.30:
			return lerpf(0.35, 1.0, (r - 0.15) / 0.15)
	if r <= 0.85:
		return 1.0
	return lerpf(1.0, 0.15, (r - 0.85) / 0.15)


## The combo layer, and the thing that produces the clip. Two directions:
##   CASH IN  — the field is already down, so complete it.
##   SET UP   — no field yet, but I hold both halves and both are ready, so lay the
##              first one BECAUSE of the second. This is the bot deciding to drop a
##              frost field so it can fire lightning through it, which is exactly the
##              behaviour that makes a bot fight look designed rather than random.
static func _combo_bonus(bb: Dictionary, m: Memory, now: float, slot: int,
		f: Dictionary, facts: Array, cooldowns: Array, mp: float) -> float:
	var elem: int = int(f["element"])
	var bonus: float = 0.0

	# --- cash in a live FIELD.
	for fld: Variant in bb.get("fields", []):
		if typeof(fld) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = fld
		for row: Dictionary in COMBO_SETUPS:
			if int(d.get("element", -1)) != int(row["field"]):
				continue
			if int(row["then"]) != -1 and int(row["then"]) != elem:
				continue
			bonus = maxf(bonus, 0.70 * float(row["payoff"]))

	# --- cash in against a live BARRIER: bring the element that answers it.
	for bar: Variant in bb.get("barriers", []):
		if typeof(bar) != TYPE_DICTIONARY:
			continue
		var d2: Dictionary = bar
		for row: Dictionary in COMBO_BARRIERS:
			if int(d2.get("element", -1)) == int(row["barrier"]) and int(row["then"]) == elem:
				bonus = maxf(bonus, 0.55 * float(row["payoff"]))

	# --- SET UP: is this slot the first half of a combo whose second half I am
	# holding, ready and affordable? Only field-shaped slots can set one up.
	if bool(f["makes_field"]):
		for row: Dictionary in COMBO_SETUPS:
			if int(row["field"]) != elem:
				continue
			for j: int in range(facts.size()):
				if j == slot:
					continue
				if j < cooldowns.size() and float(cooldowns[j]) > 0.0:
					continue
				var other: Dictionary = facts[j]
				if int(row["then"]) != -1 and int(other["element"]) != int(row["then"]):
					continue
				# No point laying half a combo whose other half I cannot pay for.
				# Checked against CURRENT mana rather than the sum of both costs: mana
				# regenerates, and demanding both up front would make the two most
				# expensive halves in any kit un-comboable forever.
				if mp * 100.0 < float(other["mp_cost"]):
					continue
				bonus = maxf(bonus, 0.50 * float(row["payoff"]))

	# --- THE SELF-COMBO. Two of my OWN beams of opposing elements inside the fusion
	# window fuse into ReactionTable's headline outcome. It is weight-blind and
	# same-owner, so it is available in every fight to any kit holding two beams —
	# the biggest single thing a bot can choose to do on purpose.
	if bool(f["is_beam"]) and m.last_beam_element >= 0 \
			and now - m.last_beam_at <= FUSION_WINDOW \
			and ReactionTable.opposed(m.last_beam_element, elem):
		bonus = maxf(bonus, 0.85)
	return bonus


## The mirror image: spells that a live barrier would EAT. ReactionTable's
## `ground_out` consumes a lightning beam against an earth wall outright, so this is
## a penalty rather than an absent bonus — the bot must actively avoid donating the
## spell, not merely fail to be rewarded for it.
static func _combo_penalty(bb: Dictionary, me: Vector2, foe: Vector2,
		f: Dictionary) -> float:
	var seg: Vector2 = foe - me
	var len2: float = seg.length_squared()
	if len2 <= 0.01:
		return 0.0
	for bar: Variant in bb.get("barriers", []):
		if typeof(bar) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = bar
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var t: float = clampf((p - me).dot(seg) / len2, 0.0, 1.0)
		if p.distance_to(me + seg * t) > float(d.get("radius", 40.0)):
			continue    # not on the firing line, so it eats nothing
		for row: Dictionary in COMBO_AVOID:
			if int(d.get("element", -1)) == int(row["barrier"]) \
					and int(f["element"]) == int(row["then"]):
				return float(row["penalty"])
	return 0.0


## Book-keeping after a cast is committed: the recency term, the fusion window, and
## the latch that stops the brain immediately re-deciding.
static func _note_cast(bb: Dictionary, m: Memory, slot: int, now: float) -> void:
	m.last_slot_at[slot] = now
	m.latched_slot = slot
	m.latched_until = now + CAST_LATCH
	var facts: Array = facts_for(int(bb.get("self_id", 0)), int(bb.get("class_id", -1)))
	if slot < facts.size() and bool(facts[slot]["is_beam"]):
		m.last_beam_element = int(facts[slot]["element"])
		m.last_beam_at = now


## The basic attack. Deliberately dumb and deliberately constant: a bot that only
## acts when a spell is off cooldown reads as idle between casts, and the fists are
## what keep pressure on in the gaps. Rate-limited to the body's own melee cooldown
## so it is not spamming a button the body would ignore anyway.
## ⚠ THE RANGE GATE USED TO BE `reach * 1.1` FOR EVERY CLASS, and that was a whole
## missing verb. `reach` is `Hero._melee_range` — about 58-96 px — but LMB is a
## THROWN BOLT on five of the nine classes and a frost cone on a sixth. So a
## Cryomancer standing in its own authored 200-360 px band could never satisfy this
## test, and therefore never fired a single basic attack in its life: it walked to
## its stance and waited for a cooldown. Combined with the stale `CD_PRIMARY_INDEX`
## above (which read the GUARD timer), the ranged half of the roster had no basic
## attack at all.
##
## `CLASS_ABILITIES[cid].primary` carries the real reach per class, 0.0 meaning "it
## is the fists, so use the body's own `reach`".
static func _wants_fire(bb: Dictionary, _profile: Dictionary, m: Memory, now: float,
		_evaluated: Array) -> bool:
	# THE FLOOR, CHECKED BEFORE THE COOLDOWN. See `FIRE_SPACING`: the body's own
	# cooldown was the ONLY gate, so the fast half of the roster fired in a stream and
	# the three melee-primary classes (which never set `_cast_cooldown_timer` at all)
	# pressed it every single frame into a silent early-return.
	if now - m.last_fire_at < FIRE_SPACING:
		return false
	if not _ready_flag(bb, "fire_ready", CD_PRIMARY_INDEX,
			now - m.last_fire_at >= MELEE_COOLDOWN):
		return false
	if int(bb.get("foe_id", 0)) == 0:
		return false
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	return me.distance_to(foe) <= _primary_range(bb)


## How far this class's LMB actually reaches. See CLASS_ABILITIES.
static func _primary_range(bb: Dictionary) -> float:
	var reach: float = float(bb.get("reach", 58.0)) * 1.1
	var cid: int = int(bb.get("class_id", -1))
	if cid < 0 or cid >= CLASS_ABILITIES.size():
		return reach
	var declared: float = float(CLASS_ABILITIES[cid].get("primary", 0.0))
	return reach if declared <= 0.0 else declared


# =========================================================================
# AIM
# =========================================================================

## Where to point. A LEAD on the foe's current velocity plus a bounded error.
##
## THE ERROR IS THE POINT, not a concession. No-auto-aim is a locked design rule:
## the bot points a direction and the shot goes there whether or not anyone is
## standing in it. The lead makes it a competent shot; the error, sampled once per
## decision and held, makes it a shot that can miss. Both halves are needed — lead
## with no error is a homing missile, error with no lead is a bot that cannot hit a
## moving target at all.
static func _aim(bb: Dictionary, _profile: Dictionary, m: Memory, _now: float) -> Vector2:
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var foe_vel: Vector2 = bb.get("foe_vel", Vector2.ZERO)
	var to_foe: Vector2 = foe - me
	# Flight time against the hero bolt speed (Spell.SPEED 460). Close enough for
	# every projectile in the game and irrelevant for the instant ones.
	var lead_t: float = clampf(to_foe.length() / 460.0, 0.0, 0.5)
	var aim: Vector2 = (foe + foe_vel * lead_t) - me
	if aim.length_squared() < 0.01:
		aim = Vector2(signf(float(bb.get("facing", 1.0))), 0.0)
		if aim == Vector2.ZERO:
			aim = Vector2.RIGHT
	return aim.normalized().rotated(m.aim_error)


# =========================================================================
# KIT FACTS
# =========================================================================

## The five slots of a class, reduced to what the scorer needs. Read from
## SpellLibrary rather than restated here: a second copy of the kit table would be
## wrong the first time a spell is retuned, and this brain would go on confidently
## scoring a spell that no longer exists.
##
## Cached per class for the process. build_for_class mints fresh Resources each call
## (correctly — they are mutable), so calling it per bot per frame would be pure
## garbage collection.
## ⚠ KEYED BY THE HAND, NOT BY THE CLASS, and that is a bug fix rather than a
## refinement. `SpellLibrary.set_slot_roles` lets the player CHOOSE which of a
## class's five authored roles they carry — six legal hands per class — and a cache
## keyed on `class_id` alone answered with whichever hand happened to be asked about
## first, for the rest of the process. A bot (or the player's own puppet on a peer's
## screen) would then steer, range and combo against spells it is not holding, with
## nothing anywhere reporting a problem.
## ══ WHAT THE BODY IS ACTUALLY HOLDING ═══════════════════════════════════════
## `_kit_facts` answers from the CLASS KIT. That is right for a class's own hand and
## wrong the moment a Tier 2 / Tier 3 drop displaces a slot: the bot goes on scoring
## the spell it USED to have — that spell's range, form, cast time and role — and so
## it casts a 235 px ring at whatever distance the displaced spell wanted. The
## `slot_affordable` note in `score_slots` already flags this as the gap it can only
## half-close: that flag says the slot EXISTS, never what is in it.
##
## Keyed by `self_id`, which is the body's instance id and is already on the
## blackboard. Per BODY rather than per class because two bots in one duel hold
## different drops — the exact case a class-keyed cache got wrong before.
##
## ⚠ AN OVERLAY, NOT A CACHE ENTRY. Writing a drop into `_kit_cache` would poison
## the shared facts of every other body of that class for the life of the process.
static var _drop_facts: Dictionary = {}


## Tell the brain that `body` now holds `spell` in slot `nth`. Idempotent.
static func note_drop(body: Object, nth: int, spell: SpellDef) -> void:
	if body == null or not is_instance_valid(body) or spell == null:
		return
	if nth < 0 or nth >= SLOT_COUNT:
		return
	var id: int = body.get_instance_id()
	if not _drop_facts.has(id):
		_drop_facts[id] = {}
	(_drop_facts[id] as Dictionary)[nth] = _facts_of(spell, "drop")


## Forget a body's drops, so this table cannot grow for the life of the process off
## instance ids whose bodies are long gone. `BotMatch` calls it on teardown.
static func forget_drops(body: Object) -> void:
	if body != null:
		_drop_facts.erase(body.get_instance_id())


## The class kit for `class_id`, with anything body `self_id` picked up laid on top.
static func facts_for(self_id: int, class_id: int) -> Array:
	var base: Array = _kit_facts(class_id)
	var over: Variant = _drop_facts.get(self_id)
	if over == null or (over as Dictionary).is_empty():
		return base
	var out: Array = base.duplicate()
	for nth: Variant in (over as Dictionary):
		var i: int = int(nth)
		if i >= 0 and i < out.size():
			out[i] = (over as Dictionary)[nth]
	return out


static func _kit_facts(class_id: int) -> Array:
	if class_id < 0:
		return _generic_facts()
	var roles: Array = SpellLibrary.slot_roles_for_class(class_id)
	var key: String = "%d:%s" % [class_id, ",".join(PackedStringArray(roles))]
	if _kit_cache.has(key):
		return _kit_cache[key]
	var spells: Array = SpellLibrary.build_for_class(class_id)
	var out: Array = []
	for i: int in range(SLOT_COUNT):
		if i >= spells.size():
			out.append(_default_facts(i))
			continue
		out.append(_facts_of(spells[i], String(roles[i]) if i < roles.size() else ""))
	_kit_cache[key] = out
	return out


## ONE SPELL, reduced to what the scorer needs. Extracted so a DROP is described in
## exactly the same terms as a kit spell — two drifting descriptions of the same
## thing is how a bot ends up steering against a spell nobody is holding.
static func _facts_of(s: SpellDef, role: String) -> Dictionary:
	var form: int = ReactionTable.form_for_kind(s.kind)
	return {
		"id": s.id,
		# WHICH ROLE THIS CLASS PUT HERE. The situational scorer matches on this
		# rather than on the slot index, because with a three-spell hand the middle
		# slot is control / answer / payoff depending on the class. A DROP reports
		# "drop", which matches no situational row — correct, because it is scored on
		# its tier and its range rather than on a role it was never authored for.
		"role": role,
		"element": s.element,
		"kind": s.kind,
		"cast_time": s.cast_time,
		"mp_cost": float(s.mp_cost),
		"tier": SpellTier.of(s),
		"range": _effective_range(s),
		# A FIELD or a BARRIER is a thing that stays on the floor, which is what the
		# combo layer means by "sets one up".
		"makes_field": form == ReactionTable.Form.FIELD or form == ReactionTable.Form.BARRIER,
		"is_beam": form == ReactionTable.Form.BEAM,
		"close_ok": not _is_placed(s.kind),
	}


## HOW FAR THIS SPELL ACTUALLY WORKS — and the one place `SpellDef.reach` must not
## be read uniformly, because it is three different things depending on the kind:
##   · a CAST-RANGE clamp for the placed bombardments (meteor, ray, pillar, zone,
##     blink-strike) — the only case where "reach" means what it sounds like;
##   · a HOP range for CHAIN, a TRAVEL BUDGET for CRAWLER / THROWN_ANCHOR / ARC;
##   · the SIZE of the thing for WALL / ICE_WALL / WARD, where it says nothing at
##     all about range. Reading it as range there would have the bot standing 90 px
##     from the foe to drop a wall, which is the opposite of what a wall is for.
## Getting this wrong is invisible in code review and obvious in play, which is why
## it is one function with the cases named.
static func _effective_range(s: SpellDef) -> float:
	match s.kind:
		SpellDef.Kind.BEAM, SpellDef.Kind.RUSH, SpellDef.Kind.ARC:
			return s.length
		SpellDef.Kind.WALL, SpellDef.Kind.ICE_WALL, SpellDef.Kind.WARD:
			# Cast at arm's length, between me and the thing I am shaping the floor
			# against. `reach` here is the wall's own size.
			return 220.0
		SpellDef.Kind.FLURRY:
			return 110.0     # a melee arc across the front
		SpellDef.Kind.TETHER:
			return 320.0     # the lashed hook's travel
		SpellDef.Kind.MISSILES:
			return 600.0     # thrown orbs, no declared range
		SpellDef.Kind.BOULDER:
			return 560.0
		SpellDef.Kind.NOVA:
			return maxf(s.radius, 120.0)   # self-centred: aim is ignored entirely
		SpellDef.Kind.HEX:
			return _hex_range(s)
		SpellDef.Kind.CATACLYSM:
			# ⚠ THERE WAS NO ARM HERE EITHER, and one Tier 3 pays for it directly:
			# `equinox` declares `reach = 0`, so the fallback below sized a spell that
			# levels the whole room as a 300 px poke. A bot that misreads range does
			# not error — it never closes, or never fires — and bots are the clip
			# pipeline, so it reads as "the spell is broken".
			#
			# `the_circuit` has NO radius by design and is the one spell in the game
			# with genuinely unlimited range; it is given the stage's own width rather
			# than INF so the scorer's distance terms stay finite and comparable.
			if s.id == "the_circuit":
				return 2000.0
			return maxf(s.reach, s.radius) if maxf(s.reach, s.radius) > 0.0 else 400.0
	# Everything else — the placed bombardments, CHAIN, CRAWLER, THROWN_ANCHOR —
	# genuinely uses `reach`.
	return s.reach if s.reach > 0.0 else 300.0


## HEX IS FORKED ON ID, SO ITS RANGE IS TOO.
##
## `Kind.HEX` used to mean "one of four Tier 2 floor pickups" and reading `reach`
## uniformly was fine. The anti-recolour pass made it the busiest kind in the game:
## eleven class signatures ride it, SIX OF THEM CARRIED BY DEFAULT (Shockwave Stomp,
## Radiant Volley, Shatter, Raise Thrall, Iai Slash, Crescent Step) plus five ults.
## A bot that misreads their range does not error — it just never closes, or never
## fires, and the class quietly cannot be used in a bot match. Bots are the recording
## pipeline, so that is a broken class, not a cosmetic gap.
##
## Two exception sets, both named rather than tabulated as bare numbers, so this
## stays a DERIVATION from each spell's own data:
##   TRAVEL — the spell's damage runs the length of `length`, and its `reach` is a
##            cast-placement clamp far shorter than where it actually reaches. Read
##            `reach` here and a bot walks into melee to fire a 760 px volley.
##   SELF   — the spell ignores the aim point entirely, so `reach` is not a range at
##            all. `mirror_image` is the one that bites: its `reach` is 1.0 — the
##            clone's ECHO DELAY IN SECONDS, the same field-doubling ZONE does with
##            `length` — which reads as a ONE PIXEL range, i.e. a spell the Arcanist
##            bot would hold and never cast. `blood_pact` and `gravity_flip` are
##            genuinely self-centred and declare no reach at all.
const HEX_TRAVEL_RANGE: Array[String] = ["radiant_volley", "fault_line"]
## ⚠ `gravity_flip` WAS IN THIS LIST AND IS NOT ANY MORE (2026-08-05). It became the
## GRAVITY WELL — a PLACED cylinder with a real radius (320) and a real reach (300) —
## so it now has a range to reason about, and reading `HEX_SELF_RANGE` would have had
## the Juggernaut bot walk to 260 px and drop the well on its own feet every time. It
## falls through to `s.reach` with everything else that is placed.
const HEX_SELF_CAST: Array[String] = ["mirror_image", "blood_pact"]
## How close a bot wants to be before spending a self-centred hex. Not a range —
## there is no range — but a "the fight is happening, this is worth it" distance, in
## the band the melee hexes occupy. UNTESTED GUESS.
const HEX_SELF_RANGE: float = 260.0


static func _hex_range(s: SpellDef) -> float:
	if HEX_TRAVEL_RANGE.has(s.id):
		return s.length if s.length > 0.0 else 700.0
	if HEX_SELF_CAST.has(s.id):
		return HEX_SELF_RANGE
	return s.reach if s.reach > 0.0 else 300.0


## Is this spell DROPPED ON A SPOT rather than fired from the hand? The distinction
## the near-range penalty turns on: these all plant a telegraphed footprint on the
## ground, so casting one at your own feet means standing in your own spell.
## BLINK_STRIKE is placed but deliberately absent — it puts you AT the point, which
## is the one case where "on top of it" is the intended outcome.
static func _is_placed(kind: int) -> bool:
	match kind:
		SpellDef.Kind.METEOR, SpellDef.Kind.DIVINE_RAY, SpellDef.Kind.CONVERGENCE, \
		SpellDef.Kind.PILLAR, SpellDef.Kind.ZONE:
			return true
	return false


## What the scorer assumes when the blackboard did not say which class this is. The
## bot still fights — it just cannot reason about elements (so combos are inert) or
## about channels (so nothing is gated as a channel), and its ranges are the
## role's typical shape rather than its actual spell's.
## Stand-in facts for a slot with no real spell behind it (an unknown class, or a
## hand that came up short). The role names are the DEFAULT three-button layout —
## damage, one utility spell, the ult — which is what a class with no authored
## `SLOT_ROLES` row falls back to in `SpellLibrary.slot_roles_for_class`.
static func _default_facts(role: int) -> Dictionary:
	const ROLE_NAMES: Array[String] = ["damage", "control", "ult"]
	var ranges: Array[float] = [520.0, 300.0, 640.0]
	var costs: Array[float] = [45.0, 55.0, 72.0]
	var idx: int = clampi(role, 0, ROLE_NAMES.size() - 1)
	return {
		"id": "", "element": -1, "kind": SpellDef.Kind.BEAM, "role": ROLE_NAMES[idx],
		"cast_time": 0.0, "mp_cost": costs[idx],
		"tier": SpellTier.Tier.HEAVY, "range": ranges[idx],
		"makes_field": ROLE_NAMES[idx] == "control", "is_beam": false,
		"close_ok": true,
	}


static func _generic_facts() -> Array:
	var out: Array = []
	for i: int in range(SLOT_COUNT):
		out.append(_default_facts(i))
	return out


# =========================================================================
# SMALL HELPERS
# =========================================================================

## Is a button ready? Three sources, in order of how much they are trusted:
##   1. an explicit boolean on the blackboard — the caller said so outright;
##   2. the extra cooldown index the body seam publishes past the five slots, if the
##      array is long enough to have one (see CD_*_INDEX);
##   3. our OWN book-keeping against the body's real cooldown constant.
##
## Case 3 is the one that matters for fairness: when nobody has told us, we hold
## ourselves to the real timer instead of assuming ready. Assuming ready is a cheat
## by omission, and it would show up in play as a bot dashing four times a second.
static func _ready_flag(bb: Dictionary, key: String, cd_index: int,
		fallback: bool) -> bool:
	if bb.has(key):
		return bool(bb[key])
	var cds: Array = bb.get("cooldowns", [])
	if cd_index < cds.size():
		return float(cds[cd_index]) <= 0.0
	return fallback


## A 2D exit vector expressed the way the intent contract wants it: x is the walk
## axis, y < 0 means "wants up". Flattening rather than passing the raw vector is
## the honest translation for a side-on platformer, where there is no such thing as
## walking upward.
static func _flatten(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.ZERO
	var x: float = clampf(dir.x * 2.0, -1.0, 1.0)
	var y: float = -1.0 if dir.y < -0.5 else 0.0
	return Vector2(x, y)


## Find the memory: the explicit argument, then one parked in the blackboard, then a
## fresh one installed there. See the note on decide() for why the last case is the
## safe degradation and not a silent bug.
static func _resolve_memory(bb: Dictionary, mem: Memory) -> Memory:
	if mem != null:
		return mem
	var parked: Variant = bb.get("mem", null)
	if parked is Memory:
		return parked
	var fresh: Memory = Memory.new()
	bb["mem"] = fresh
	return fresh
