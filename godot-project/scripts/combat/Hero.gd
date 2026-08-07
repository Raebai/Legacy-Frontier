extends CharacterBody2D
## Slice 0 combat protagonist (the mage). Move now; dash + cast added next.

signal health_changed(current: int, maximum: int)
signal mana_changed(current: float, maximum: int)
signal signature_changed(display_name: String)

const SPEED: float = 210.0
## Mana (MP): gates the big SIGNATURE spectacle spells (the magic-circle beam /
## divine ray). Regenerates over time so ultimates are a paced resource, not
## spammable. Costs + cooldowns live per-spell on the SpellDef.
const MP_REGEN: float = 20.0  # mp/sec
const DASH_SPEED: float = 620.0
const DASH_TIME: float = 0.18
const DASH_COOLDOWN: float = 0.9  # was 0.55 — chained diagonal dashes let you "fly"
## Side-on platformer physics (Stick-Fight feel): asymmetric gravity (floaty
## apex, weighty landing), snappy accel + friction, WALL-SLIDE + WALL-JUMP so you
## can cling to and scale walls. Movement is horizontal (A/D); jump; dash.
const GRAVITY: float = 1500.0          # rise gravity (floaty apex)
const GRAVITY_FALL: float = 2100.0     # heavier coming down (weighty landing)
const MAX_FALL: float = 1000.0
const JUMP_VELOCITY: float = -580.0  # slightly higher jump (maker feedback)
## ⚠ -470 -> -415. Maker: *"the dash distance and jump height for shadowblade is too
## much so any classes that have that as well please reduce slightly"*. This constant
## is read at exactly ONE site — the `_air_jumps > 0` branch — so it is already scoped
## to precisely the classes that have the extra air: the Shadowblade (2 air jumps) and
## the Brawler (1). The GROUND jump (`JUMP_VELOCITY`) is deliberately untouched, since
## lowering that would shorten every class's jump in the tower to answer a note about
## two of them.
const DOUBLE_JUMP_VELOCITY: float = -415.0
const MAX_AIR_JUMPS: int = 0  # no mid-air double-jump — wall-jump is the air move
const COYOTE_TIME: float = 0.10      # jump slightly after leaving a ledge
const JUMP_BUFFER_TIME: float = 0.10 # jump queued slightly before landing
const GROUND_ACCEL: float = 2600.0
const GROUND_FRICTION: float = 2900.0  # crisp stop with a hint of slide
const AIR_ACCEL: float = 1450.0        # strong air control (Stick-Fight)
## Wall-slide + wall-jump (the Stick-Fight wall tech): grip a wall while falling
## into it (clamped slide speed), then kick off away+up; a slide-then-jump boosts.
const WALL_SLIDE_MAX_FALL: float = 150.0
const WALL_STICK_PUSH: float = 6.0     # tiny into-wall x so is_on_wall stays true
const WALL_JUMP_PUSH: float = 300.0    # launch away from the wall (> SPEED)
const WALL_JUMP_UP: float = -460.0     # up kick — a diagonal arc, not a rocket
const WALL_JUMP_LOCKOUT: float = 0.15  # brief horizontal-input lock after the kick
const SLIDE_JUMP_BOOST: float = 1.25   # extra push jumping straight out of a slide
## ------------------------------------------------------------------ GHOST FORM
## Dying costs a LIFE, not a floor (see `DeathRules`). A downed hero becomes a
## ghost: it still steers, it cannot hit and cannot be hit, and it stays that way
## until a teammate picks it up. These are the numbers of being dead.
##
## Drift is SLOWER than a living hero on purpose. Being a ghost has to feel like
## being outside the fight looking in — full speed with no consequences would make
## it the more comfortable state to be in.
const GHOST_SPEED: float = 155.0
const GHOST_ACCEL: float = 900.0
## HAUNT — the ghost's one verb. Zero damage, pure shove. It exists so the downed
## player can buy their rescuer the ~2 seconds the revive channel costs; see the
## header of `GhostForm.gd` for why a ghost that could kill would be a ghost you
## would rather be. All three numbers are UNTESTED FEEL GUESSES.
const GHOST_HAUNT_RADIUS: float = 120.0
const GHOST_HAUNT_FORCE: float = 420.0
const GHOST_HAUNT_COOLDOWN: float = 3.0

const CAST_COOLDOWN: float = 0.35
const MELEE_COOLDOWN: float = 0.34
const MELEE_DAMAGE: int = 14
const MELEE_RANGE: float = 58.0  # was 46 — short fists whiffed (Brawler LMB "not working")
const MELEE_ARC_DOT: float = 0.3
## Bumped for the Stick-Fight "shove" read — a connected punch should visibly
## launch the target, not just tick it.
const MELEE_KNOCKBACK: float = 300.0
## Short forward step on EVERY plain melee swing (Stick-Fight punches step INTO
## the hit). Softer than the combo/heavy-swing lunges (200/190) since this is
## the bare-fists baseline they build on top of.
const MELEE_LUNGE_SPEED: float = 170.0
## Small always-fires hitstop/shake so a swing reads even when it misses —
## much lighter than the on-connect Juice.on_hit cluster below.
const MELEE_SWING_HIT_STOP: float = 0.02
const MELEE_SWING_SHAKE: float = 1.5
## Ragdoll shove the hero RECEIVES (bomb blast / reflected bolt / slam) — decays
## like the enemy channel so a hit displaces you, then you regain control.
const KNOCKBACK_DECAY: float = 900.0
## Melee tuning per weapon kind; the MELEE_* consts are the "fists" baseline.
const WEAPON_STATS: Dictionary = {
	"fists": {"damage": MELEE_DAMAGE, "range": MELEE_RANGE, "knockback": MELEE_KNOCKBACK},
	"sword": {"damage": 26, "range": 60.0, "knockback": 400.0},
}
## After a fire-element melee the lead fist stays LIT for this long, the flame
## trailing embers as the hand moves (item 3). Strength decays with the timer.
const FLAMING_FIST_TIME: float = 1.6
const BLAST_COOLDOWN: float = 2.0
const BLAST_FALLBACK_RANGE: float = 200.0
## Meteor is player-placed at the cursor, clamped to this reach (skill-shot, not
## a cross-stage snipe).
const BLAST_MAX_RANGE: float = 480.0
## Blink teleport: instant reposition along facing with a shadow-poof at both
## the origin and the destination (the "yin-yang shadow step").
const BLINK_DISTANCE: float = 175.0
## Blink lands you THROUGH walls but never INSIDE one: probe the endpoint against
## solids (layer 1) and relocate to the nearest clear spot if it's blocked.
##
## THE RULE, stated once (maker: "can go through stuff ... just make sure you can't
## blink into a wall"): a blink is a PHASE, not a move. The PATH is never tested —
## no raycast, no sweep, `global_position` is assigned outright — so cover, ruins,
## ledges and breakable platforms are all passed straight through by construction.
## Only the RESTING SPOT is vetted, against three rules (see `_blink_spot_legal`):
## not inside solid geometry, not over a ring-out pit, not outside the room.
## An illegal spot SLIDES ALONG THE BLINK RAY — forward first (finish the phase,
## come out the far side of whatever the endpoint landed in), then backward toward
## the origin, which is legal by construction because you were just standing on it.
## First legal point wins, so you always travel as far toward your aim as the map
## allows. If nothing on the whole ray clears `BLINK_MIN_TRAVEL`, the press is
## REFUSED AND REFUNDED rather than eating the cooldown for a 6-px shuffle.
const BLINK_WALL_MASK: int = 1
const BLINK_PROBE_STEP: float = 6.0
## Forward phase budget: how far PAST a blocked endpoint we keep looking for
## daylight before giving up and sliding back. This number is the thickest thing a
## blink may pass through when your endpoint lands inside it. Room walls are 16 px
## (Arena.WALL_THICKNESS) and cover blocks/ruins are thicker; 96 clears any single
## piece of the stage's geometry, which is what "goes through stuff" has to mean to
## be worth pressing. (Was 60 — enough for a wall, not for a cover block.)
const BLINK_PROBE_EXTRA: float = 96.0
## The floor on a USEFUL blink. The backward slide walks all the way home in 6-px
## steps, and its last candidate is ~1 px from where you stand — technically legal,
## and exactly the "the button ate my cooldown and did nothing" outcome. Anything
## shorter than this is treated as no legal destination at all: refused, refunded,
## press again. Roughly a hero's own width, so a refused blink is unambiguous.
const BLINK_MIN_TRAVEL: float = 24.0
## Length of the four enclosure rays that decide whether a landing spot is still
## INSIDE the room. Must comfortably exceed any room's diagonal (`FloorGen` tops
## out well under this); over-long is free because the ray stops at the first hit.
const BLINK_BOUNDS_RAY: float = 6000.0
const BLINK_COOLDOWN: float = 1.3
const BLINK_IFRAME: float = 0.22
## Share of a dash that is invulnerable, measured from its START. Below 1.0 the
## dash stops being a reactive get-out-of-jail button and becomes a commitment
## you have to read early — the tail of the dash can still be hit. This is the
## primary dial for how forgiving evasion feels; 1.0 restores the old behaviour.
const DASH_IFRAME_FRACTION: float = 0.6
## You may never blink OUT of the map — a landing spot inside a ring-out PIT (or
## within this margin of one) is rejected and pulled back toward the origin (maker:
## "you shouldn't be able to teleport out of the map ... limit it to where you
## actually can teleport"). Landing inside a solid is already rejected separately.
const BLINK_PIT_MARGIN: float = 22.0
const BLINK_SHADOW_COLOR: Color = Color(0.25, 0.1, 0.35, 0.8)
## Dark-violet particle poof; end alpha 0 so it dissolves instead of popping.
const BLINK_BURST_START: Color = Color(0.4, 0.18, 0.55, 0.9)
const BLINK_BURST_END: Color = Color(0.08, 0.03, 0.15, 0.0)
## Quick bright flash on arrival so the eye snaps to the new position.
const BLINK_ARRIVAL_FLASH_COLOR: Color = Color(0.85, 0.7, 1.0)
const BLINK_ARRIVAL_FLASH_TIME: float = 0.1
## Energy nova: self-centered instant shockwave — the "get off me" button.
## Bumped 3->5s: at 3s it was spammable enough to be oppressive.
const NOVA_COOLDOWN: float = 5.0
## Perfect-timing parry (rogue only): a short ACTIVE window that REVERSES an
## incoming enemy bolt back at the enemy side. Miss the window and you eat it.
const PARRY_WINDOW: float = 0.16
const PARRY_COOLDOWN: float = 0.9
const PARRY_FLASH_COLOR: Color = Color(0.8, 1.0, 1.0)
## The directional block SHELL lingers a touch longer than the active window so
## the deflect reads (the arc is the whole tell — no omni flash).
const PARRY_SHIELD_TIME: float = 0.26

# ==================================================== THE NINE MOVEMENT VERBS
## THE MAKER'S RULING: "we cannot have any recolours — I want all the classes to be
## different and unique and not similar at all", and specifically "the necromancer
## should be able to swap with their minions ... the air one should be able to hop and
## dash in the air really far ... the lightning one, instead of dashing it blinks with
## electricity in a slightly longer distance".
##
## WHAT WAS WRONG. Every class moved identically. `SPEED`, `DASH_SPEED` and
## `JUMP_VELOCITY` were global, and the entire movement identity of a nine-class roster
## was a `dash_cd` between 0.55 and 0.90 s. Two classes swapped R for an uppercut and
## the Brawler got a double jump; that was the whole spread. A player could not tell
## who they were holding until they cast something.
##
## THE SHAPE OF THE FIX, and the one rule that constrains it: **every verb is behind
## the SAME `dash` action**. That is not tidiness, it is the mobile spec. `TouchControls`
## ships exactly ONE movement button (`_button_layout()`: JUMP / PARRY / DASH plus the
## the spell slots) — `blast`, `blink` and `nova` have no touch affordance at all. A
## verb bound to a new action would be desktop-only, which fails D-011 outright. Behind
## the shared button it is also free for the BOTS: `BotIntent.DASH` is one key that the
## brain already presses without knowing what a body does with it (see BotIntent's own
## note: "the same brain drives a class whose R is a blink and a class whose R is an
## uppercut without knowing the difference").
##
## Dispatch is `_cfg["move_verb"]` -> `_start_dash()`. The nine values are unique by
## construction and `tools/slice_test_class_movement.gd` asserts that no two classes
## resolve to the same one; the pre-change code has NO `move_verb` key at all, so that
## assertion fails on it (all nine fall back to one string), which is the point.
##
## I-FRAMES ARE NOW A DECISION, NOT AN ACCIDENT. `DASH_IFRAME_FRACTION` used to apply
## to every class. Each verb below names its own fraction and CLASS_CONFIG carries it as
## `dash_iframe_fraction`, so "this verb dodges" and "this verb commits" is a number you
## can read rather than a side effect of sharing one code path.

## --- 0 ARCANIST: ARCANE PHASE --------------------------------------------------
## Step, and be UNTOUCHABLE for the whole of it. The Arcanist does not dodge the way
## everyone else dodges (early, then exposed on the tail) — it stops being a body at
## all for the length of the step, leaves a violet after-image standing where it was,
## and re-forms where it is going.
##
## ⚠ REMOVED 2026-08-04 — THE RETURN LEG (the "Arcane Recall" second press). This verb
## used to drop an anchor on press one and TELEPORT YOU BACKWARDS to it on a second
## press inside `RECALL_WINDOW`. The maker killed it on sight: *"im confused on this
## backwards teleporting when I press space twice get rid of that its just a repeat of
## blink we dont want that"* — and they are right, it WAS a blink. R is already a
## vetted teleport (`_blink`), the Stormcaller's whole verb is a vetted teleport
## (`_lightning_blink`), and a third one sharing the movement button meant the same
## press did two unrelated things depending on hidden state you could not see. Gone
## with it: `RECALL_WINDOW`, `_recall_anchor`, `_recall_timer`, `_recall_pending()`,
## `_arcane_recall_return()`, the `"rc"` net beat and `_replay_recall()`. Do not
## re-add a second beat to this button.
##
## WHAT KEEPS IT FROM BEING A RECOLOURED DASH — because "every class needs a unique
## movement verb, no recolours" is a standing ruling and deleting the second beat left
## this row at literally the baseline dash (0.6 i-frames, ~84 px). The identity moved
## into the i-frame profile: this is the ONLY verb in the roster that is invulnerable
## for 100% of its duration. Everything else is a read you can be punished for
## finishing (0.8 air dash, 0.6 baseline, 0.0 for the two commitments); the phase is
## the one press that cannot be clipped. That is the same fantasy the out-and-back was
## reaching for — "step into a lane you have no business standing in and don't pay for
## it" — bought with ONE press and no hidden state.
##
## ⚠ IT IS STILL NOT A BLINK, and the difference is legible at a glance: a blink is
## instant, long, and vetted against geometry (you appear elsewhere); a phase is a
## TRAVEL — you can be watched crossing, a wall stops you short, and it is the shortest
## fully-committed step in the roster. Rejected alternatives: making the forward leg a
## teleport (that is Stormcaller's verb, verbatim), and a cosmetic-only after-image
## with baseline numbers (that is the recolour the ruling forbids).
const ARCANE_PHASE_SPEED: float = 600.0
const ARCANE_PHASE_TIME: float = 0.19
## ⚠ THE ONLY 1.0 IN THE TABLE, and it is the class's movement identity rather than a
## generosity — see `_dash_invulnerable`, where the fraction is measured from the START
## of the travel. If this ever feels oppressive the dial is `dash_cd` or
## `ARCANE_PHASE_TIME`, NOT this number: shave the fraction and the Arcanist is a
## slightly-slower dash again, which is exactly what was just deleted.
const ARCANE_PHASE_IFRAME_FRACTION: float = 1.0
const ARCANE_PHASE_COLOR: Color = Color(0.55, 0.45, 1.0, 0.75)
## How long the after-image left at the origin takes to fade. Long enough to still be
## standing there when you arrive, so the eye reads "she left that behind" rather than
## "a trail ghost spawned".
const ARCANE_PHASE_ECHO_FADE: float = 0.3

## --- 1 SHADOWBLADE: AIR DASH --------------------------------------------------
## "The air one." The best air game in the roster and the only verb that IGNORES
## GRAVITY for its whole duration: a Shadowblade dash in mid-air is a flat, long,
## fully-aimed 360° traversal, not a hop that sags. Paired with TWO air jumps
## (`air_jumps: 2`) it is the only class that can cross a room without touching a
## floor. It pays for that with 78 HP — the lowest in the game.
## ⚠ 700 -> 615. Same note: *"the dash distance ... for shadowblade is too much"*.
## 700 x 0.18 was 126 px, and 151 px in the air once `AIR_DASH_AIRBORNE_BONUS` is
## applied — the longest travel in the roster on the fastest body in it (speed 240),
## which is what let it leave any exchange it did not like. 615 gives 111 / 133 px.
## The TIME is left alone on purpose: shortening it would make the dash snappier as
## well as shorter, and the note was about distance.
const AIR_DASH_SPEED: float = 615.0
const AIR_DASH_TIME: float = 0.18
## Airborne dashes travel FURTHER than grounded ones. Every other class in the game is
## worse in the air; this one is better, and that inversion is the whole identity.
const AIR_DASH_AIRBORNE_BONUS: float = 1.20
const AIR_DASH_IFRAME_FRACTION: float = 0.8

## --- 2 BRAWLER: SHOULDER CHARGE -----------------------------------------------
## Grounded, long, and it CARRIES. No teleport anywhere in the kit: this is the "no
## magic" class and it closes distance the honest way. What it hits is staggered — a
## much bigger shove than the dash-strike it shares plumbing with — and the charge
## keeps most of its speed when it ends, so a connected charge shoves you both.
## ══ THE DASH BASELINE, AND THE FOUR EXCEPTIONS TO IT ════════════════════════════
## Maker's ruling: *"the dashes should all mostly be the same distance and strength
## across the classes except some classes have certain exceptions"* — after *"brawler
## dash is too long now"*, which it was: I had taken it to 171 px, the longest travel
## in the game, answering "make it stronger" with distance alone.
##
## So travel is now ~110 px for everybody, and the SPEED of each verb is what still
## differs — a charge is a fast shove and a surge is a slow shoulder, and they cover
## the same ground. That is the honest reading of "same distance and strength": the
## distance is shared, the CHARACTER is not.
##
##   arcane phase   114      air dash       111  (+20% AIRBORNE — the exception)
##   generic dash   112      charge         110
##   radiant step   112      ice slide      a decaying steerable slide, not a dash
##   surge          129      committed step  95
##
## THE FOUR EXCEPTIONS, each one a rule the class already had:
##   SHADOWBLADE — the only body in the game that is BETTER in the air. Grounded it
##                 is baseline; airborne it keeps `AIR_DASH_AIRBORNE_BONUS`. The
##                 exception is a CONDITION, not a bigger number.
##   SWORDSAINT  — deliberately the smallest dodge in the roster. Its own note says
##                 it gets a way IN, not a way out, and that is still true at 95.
##   JUGGERNAUT  — modestly longer, because the maker asked for it directly two
##                 rounds ago and because it is the slowest body in the game: equal
##                 travel on a 165 px/s walker is less reach than on a 240 px/s one.
##   STORMCALLER / WARLOCK — teleports. Not travel at all, so not measured here.
##
## ⚠ THE SUITE USED TO ASSERT THE OPPOSITE and had to be inverted, not loosened —
## `slice_test_class_movement` demanded at least 7 of 9 classes travel a VISIBLY
## DIFFERENT distance. That was a fair reading of the old "nine distinct verbs" goal
## and it is not what the maker wants now, so it now pins the cluster and the named
## exceptions instead. A test that contradicts a live ruling is the ruling's problem
## only until somebody writes it down.
##
## ⚠ 520 -> 610 SPEED IS KEPT. The other half of *"brawler dash needs to be
## stronger"* was that it could not dash UP, which was a flattening in
## `_travel_velocity` one layer below this table, and that fix stands. What is undone
## here is only the distance.
##
## The exit momentum is UNCHANGED: a charge that carries is the Brawler's identity
## ("a connected charge shoves you both"), and scaling the carry with the speed would
## have turned a stronger opener into a body that cannot stop.
const CHARGE_SPEED: float = 610.0
const CHARGE_TIME: float = 0.18
## Fraction of charge speed kept on exit, plus how long ground friction is suppressed
## so the carry survives long enough to be felt. Reuses `_wall_jump_lock`, which is
## already the "do not fight this momentum" gate in the movement block — a second flag
## meaning the same thing is how two of them drift apart.
const CHARGE_EXIT_MOMENTUM: float = 0.55
const CHARGE_MOMENTUM_LOCK: float = 0.18
const CHARGE_STAGGER_KNOCKBACK: float = 470.0
## NO I-FRAMES, and that is the trade. The longest travel in the roster is also the
## most committed: a charge read early is a charge punished.
const CHARGE_IFRAME_FRACTION: float = 0.0

## --- 3 JUGGERNAUT: UNSTOPPABLE SURGE ------------------------------------------
## Short, slow, and ARMOURED. It does not dodge — it refuses to be moved. Knockback
## and flop are ignored for the surge AND for a tail after it, which is the part that
## makes it different from "every dash already ignores knockback" (see
## `apply_knockback`): the Juggernaut is the only body that stays unmovable once the
## travel is over, so a surge into a crowd is not immediately shoved back out of it.
## ⚠ FASTER, FURTHER, AND IT GOES UP NOW. Maker: *"make juggernaut better like make it
## be able to dash up and faster and further"*. 330 x 0.30 was 99 px of travel — the
## shortest verb in the roster on the slowest body in it (speed 165, also the lowest),
## so the siege class could neither reach anything nor leave anything. 430 x 0.34 is
## 146 px, a 48% increase, and it is no longer flattened to the ground plane (see the
## `charge`/`surge` split in `_travel_velocity`) so it takes the full 8-way direction
## and can climb.
##
## The armour tail is UNCHANGED on purpose: the surge's identity is that it refuses to
## be moved, not that it is evasive, and lengthening the unmovable window as well would
## turn a mobility buff into a survivability one.
const SURGE_SPEED: float = 430.0
const SURGE_TIME: float = 0.38
const SURGE_ARMOR_TAIL: float = 0.35
## No i-frames — armour is not invulnerability. It eats the hit and keeps walking.
const SURGE_IFRAME_FRACTION: float = 0.0

## --- 4 CLERIC: RADIANT STEP ---------------------------------------------------
## A dash that leaves a HEALING WAKE — pulses dropped along the path that mend any
## ally standing in them. The only movement verb in the game that is a team action:
## the Cleric's repositioning is worth something to somebody else, which is the whole
## co-op reason to bring one.
const RADIANT_STEP_SPEED: float = 560.0
const RADIANT_STEP_TIME: float = 0.20
const RADIANT_WAKE_INTERVAL: float = 0.05
const RADIANT_WAKE_RADIUS: float = 70.0
const RADIANT_WAKE_HEAL: int = 3
const RADIANT_WAKE_COLOR: Color = Color(1.0, 0.95, 0.65, 0.85)
const RADIANT_STEP_IFRAME_FRACTION: float = 0.6

## --- 5 CRYOMANCER: ICE SLIDE --------------------------------------------------
## A long low-friction SLIDE along the floor. Fast and by far the longest-lasting verb
## in the roster, but you barely steer once it is going (`ICE_SLIDE_STEER` is the
## fraction of normal ground authority you keep) and it bleeds speed instead of
## stopping. Commit to the line or do not press it.
const ICE_SLIDE_SPEED: float = 470.0
const ICE_SLIDE_TIME: float = 0.55
const ICE_SLIDE_FRICTION: float = 240.0
## Turning authority mid-slide, as a fraction of GROUND_ACCEL. 0.0 would be a rail;
## this is "you can lean, you cannot turn around".
const ICE_SLIDE_STEER: float = 0.12
const ICE_SLIDE_IFRAME_FRACTION: float = 0.25
const ICE_SLIDE_FROST_COLOR: Color = Color(0.65, 0.9, 1.0, 0.7)

## --- 6 STORMCALLER: LIGHTNING BLINK -------------------------------------------
## "Instead of dashing it blinks with electricity in a slightly longer distance."
## There is NO dash on this class at all: the movement button teleports. Range is
## comfortably past both a dash's travel (~87 px) and the shadow blink on R (175 px),
## and it goes through geometry under exactly the same landing rules — this file's
## `_safe_blink_destination` owns where a teleport may rest, and nothing about that
## is re-implemented here.
const LIGHTNING_BLINK_DISTANCE: float = 260.0
const LIGHTNING_BLINK_IFRAME: float = 0.18
const LIGHTNING_BLINK_START: Color = Color(1.0, 0.95, 0.45, 0.95)
const LIGHTNING_BLINK_END: Color = Color(0.45, 0.6, 1.0, 0.0)
const LIGHTNING_BLINK_FLASH: Color = Color(1.0, 1.0, 0.7)

## --- 7 WARLOCK: THRALL SWAP ---------------------------------------------------
## Trade places with one of your own minions. The attrition class's escape is
## something it had to BUILD first, which is the only movement verb in the game with a
## setup cost — and the only one that can put a body where you were standing.
##
## ⚠ THE MINIONS ARE ANOTHER AGENT'S FILE. This codes against the published contract
## and nothing else: group `&"thrall"`, node meta `&"thrall_owner"` pointing at the
## Hero that raised it. Anything in the group whose owner is not us is ignored, so a
## teammate's thralls are not a free taxi. BOTH landings go through
## `_safe_blink_destination`.
##
## NO THRALL = A SHORT BLINK, NEVER A DEAD BUTTON. Degradation is stated once, here:
## with nothing to swap with, the press becomes a `THRALL_SWAP_FALLBACK_DISTANCE`
## teleport along the aim — same vetting, same refuse-and-refund floor. So a Warlock
## who has not summoned yet still has a mobility button; it is simply a worse one.
const THRALL_GROUP: StringName = &"thrall"
const THRALL_OWNER_META: StringName = &"thrall_owner"
## How far away a thrall may be and still be swappable. Generous — the fantasy is
## "across the room", and the landing rules stop it being a map-wide escape anyway.
const THRALL_SWAP_RANGE: float = 620.0
const THRALL_SWAP_FALLBACK_DISTANCE: float = 115.0
const THRALL_SWAP_IFRAME: float = 0.20
const THRALL_SWAP_START: Color = Color(0.55, 0.2, 0.65, 0.9)
const THRALL_SWAP_END: Color = Color(0.1, 0.02, 0.15, 0.0)

## How fast a LIMP body can drag itself. Deliberately a fraction of `SPEED` (210) —
## about a fifth — so the flop keeps costing you almost everything it always did.
const CRAWL_SPEED: float = 46.0

## --- 8 SWORDSAINT: COMMITTED STEP ---------------------------------------------
## ⚠ RETUNED 2026-08-05 ON A MAKER RULING, AND THE OLD REASONING IS DELETED RATHER
## THAN LEFT TO ARGUE WITH THE NUMBERS. This block used to read: "the shortest,
## fastest-recovering, least forgiving travel in the roster ... the guard class does
## not get to leave." That was a coherent design and it was the wrong one for the
## class that shipped. Maker: "swordsaint should move faster and dash longer."
##
## WHAT THE OLD ARGUMENT MISSED. "Does not get to leave" is a fair price for a class
## whose defence pays — but the Swordsaint's problem was never that it left too
## easily, it was that it could not ARRIVE. Its own spec (§6.4.1) states the
## structural fact plainly: eight of the other nine classes can hurt it from 900 px,
## and it carries no answer to that (Closed Ground is designed and unbuilt). At
## 57.6 px the step closed 6% of that gap, on a 0.80 s cooldown, for a body that then
## has to survive at 86 px reach. The commitment was real and it bought nothing.
##
## WHERE IT SITS NOW, read off the roster rather than picked: 106.4 px is 6th of 9 —
## past the Cleric's Radiant Step (89.6) and the Arcanist's Phase (84), 41% short of
## the Warlock's worst-case fallback blink (115) and 59% short of the Stormcaller's
## teleport (260). No longer the shortest travel in the game, nowhere near a blink.
## `tools/slice_test_class_movement.gd` pins both ends of that claim.
##
## WHAT IS DELIBERATELY UNCHANGED: the i-frame FRACTION. 0.35 stays, so the window
## grows only as a side effect of the longer travel (0.042 s -> 0.0665 s) and this is
## still the smallest dodge in the roster by a clear margin — next is the Cleric at
## 0.096 s. The class got a way IN; it did not get a way out. That is the half of the
## old paragraph worth keeping, and it is the only half kept.
##
## ⚠ THE STEP IS ALSO A DAMAGE TOOL AND THIS CHANGE BUFFS IT. `dash_strike` sweeps a
## 52 px radius every frame of the travel, so the struck corridor is `travel + 104`:
## 161 px before, 210 px now (+30%), over 11 physics frames instead of 7. That is a
## real throughput increase hidden inside a mobility number, and it is stated here
## rather than discovered later in a balance sweep.
const COMMITTED_STEP_SPEED: float = 560.0
const COMMITTED_STEP_TIME: float = 0.17
const COMMITTED_STEP_IFRAME_FRACTION: float = 0.35

## ⚠ EMPTY, AND DELIBERATELY STILL HERE. These are the verbs whose travel USED to be
## bound to the ground plane: `charge`, `surge` and `ice_slide` flattened whatever you
## held down to a pure ±X, so pressing up-right gave you a flat sideways skid.
##
## Maker, on the Cryomancer: "why can't cryomancer dash upwards, please fix — and
## remove that weird dash thing it does where it goes sideways." That IS the
## flattening; the Ice Slide is one of the three, so up-right came out as right.
##
## The list is kept rather than deleted along with `_verb_is_grounded`, because the
## argument it encoded was a real one — a shoulder charge aimed at the sky is a
## strange shoulder charge — and a future class may want it back for one verb. What
## is not acceptable is a whole class that cannot dash upward. Put a verb back in here
## and it flattens again; the mechanism is intact and unused.
const GROUNDED_VERBS: Array[String] = []
## Verbs that are TELEPORTS rather than travel: they resolve instantly inside
## `_start_dash` and never enter the per-frame dash branch. Every one of them lands
## through `blink_to`/`_safe_blink_destination`.
const TELEPORT_VERBS: Array[String] = ["lightning_blink", "thrall_swap"]

## --- THE BLADE GUARD (Swordsaint) --------------------------------------------
## THE CLASS'S WHOLE IDENTITY IN ONE MECHANIC: it is the only class whose DEFENCE
## PRODUCES ITS OFFENCE. Everyone else guards to survive a beat; the Swordsaint
## guards to be PAID, and the payment is the biggest single number in its kit.
##
## The clock is `ParryRing` in `Style.BLADE` — NOT a third scheme. That file is
## explicit that a second timing implementation is how two guard paths drift apart
## ("one gets a balance tweak, the other silently does not"), so everything about
## WHEN the guard is good — the 0.42 s shrink, the ~0.09 s perfect band, the 0.35 s
## re-arm, the offence lock — is read from there and none of it is re-declared
## here. What lives here is only what happens AFTERWARDS, which is the part that is
## this class's rather than the ring's.
##
## BLADE is also the style with a SAFE FALLBACK: overshoot the band and steel is
## still in the way, so you bottom out into a chip-reducing sustained guard. That
## asymmetry against the mage's SIGIL (tighter band, longer re-arm, and a circle
## that catches nothing simply COLLAPSES) is already built and tested in ParryRing
## and SigilGuard; this class is the BLADE half of it, wired up.
##
## Only a PERFECT read banks. A sustained guard survives; it does not earn — or
## holding the button would be both the safe option and the strong one.
const GUARD_BANK_HITS: int = 3
## Cap on the banked total. Without it, one blocked boss slam (130) would return
## 234 from a single button, which is a bigger hit than any ult in the game.
const GUARD_BANK_CAP: int = 60
## What the bank pays back on release. Above 1.0 because the read is hard and the
## commitment is real — you gave up moving and attacking to earn it. 60 banked
## returns 108.
const GUARD_RETURN_MULT: float = 1.8
## The unsheathe cut: a short LINE along the aim, not a circle. Range is deliberately
## under the class's 86 px blade reach plus a step, so cashing the bank still requires
## the attacker to be in front of you rather than merely nearby.
const GUARD_CUT_RANGE: float = 120.0
const GUARD_CUT_HALF_WIDTH: float = 18.0
const GUARD_CUT_KNOCKBACK: float = 380.0
## Reach of the guard's own deflect sweep, in px from the body. The blade is held
## out, so this is arm's length plus the blade — anything that physically travels
## and touches it while the ring is PERFECT gets turned. There is no separate timing
## window: the ring is the window.
const GUARD_DEFLECT_REACH: float = 74.0
## Input buffer: a melee/dash/blast press that lands while its gate is closed
## (cooldown running, mid-dash) is held this long and fired the moment the
## gate opens — no more silently dropped presses. `cast` is held/continuous
## and stays un-buffered.
const BUFFER_TIME: float = 0.12
## Actions that go through that single-slot buffer (newest press wins).
const BUFFERED_ACTIONS: Array[StringName] = [&"melee", &"dash", &"blast", &"blink", &"nova"]

## THE THREE SPELL BUTTONS, in kit-slot order — the right thumb's whole job.
##
## One action per kit slot, so slot 3 is ONE press away instead of three presses of a
## cycle key that passes through two spells you did not want on the way. Before this
## the hand had three real per-slot cooldowns and exactly one trigger, so the hotbar
## had to label the selected slot with the cast key and the other two with the cycle
## key — the bar telling the truth about a control scheme that had not been built.
##
## WHAT SURVIVES, and why neither is dead weight:
##   * `ultimate` — "throw whatever is SELECTED". It is `BotController.CAST_ACTION`:
##     a bot picks a slot by index (`bot_select_signature`) and then pulls this one
##     trigger, because pressing a per-slot key through the global `Input` singleton
##     would drive the human's hero too. Retiring it would cut the bot seam in half.
##   * `cycle_signature` (V) — DEMOTED, not retired. It moves the selection that the
##     hotbar lifts and that `ultimate` fires. It is no longer how a player reaches a
##     spell, and no HUD label mentions it any more.
##
## Kept the same length as `SpellTier.SLOT_COUNT` by `_verify_spell_actions()` at
## `_ready`, so growing the hand can never leave a slot silently unreachable.
const SPELL_ACTIONS: Array[StringName] = [&"spell_1", &"spell_2", &"spell_3", &"spell_4"]
## What the hotbar prints on each spell slot. Derived from the bindings above rather
## than typed in twice — the labels were wrong for exactly as long as they were a
## separate list from the actions.
const SPELL_KEYS: Array[String] = ["1", "2", "3", "4"]
## Spell presses buffer LONGER than the melee/dash set. A dash is 0.14 s and eats any
## press made during it, so a 0.12 s buffer drops a spell queued at the START of a
## dash — which is precisely the moment you queue one ("dash in, then hit them").
## 0.22 s covers a whole dash plus a frame.
const SPELL_BUFFER_TIME: float = 0.22
## How the buffer encodes a spell slot. `#` so it can never collide with a plain
## action name if one is ever added that starts with "spell".
const SPELL_BUFFER_PREFIX: String = "spell#"
## ⚠ THE GAP BETWEEN SPELLS. Maker, on the current feel: "it feels a little too
## chaotic right now… back to back effects".
##
## Casting DURING a cast was never possible — a windup cannot be cancelled, and
## `_physics_process` early-returns through `_process_channel`/`_process_summon`.
## What produced back-to-back effects is that a press made during a windup was
## BUFFERED and fired on the very frame the windup ended, so two spectacles landed
## with no readable gap between them.
##
## Two changes answer it, and this constant is the second half: after a cast
## resolves, every kit slot is refused for this long. Per-slot cooldowns cannot do
## this job — they are per-slot by design, so three ready slots still chain.
##
## Tuned as the shortest gap that reads as two separate events rather than one
## smear. It is deliberately SHORTER than the shortest windup, so it never becomes
## the thing you are waiting on when playing one spell at a time.
const GLOBAL_CAST_LOCKOUT: float = 0.35
## Aim-stick deadzone: how far the AIM stick (right thumb on touch, `aim_*` actions)
## must be pushed before it re-points the aim. Below this the last aim is HELD, so
## lifting the thumb to tap an ability doesn't fling the shot somewhere random.
## This is the ONE owner of that number — TouchControls deliberately publishes the raw
## stick with no deadzone of its own, because a per-axis deadzone up there would carve
## dead sectors near the axes (a 5-degree-up shot snapping flat).
## UNTESTED FEEL GUESS — no device playtest has happened yet.
const TOUCH_AIM_DEADZONE: float = 0.20
## Hit feedback when damage actually lands (not i-framed).
const HURT_FLASH_COLOR: Color = Color(1.0, 0.2, 0.2)
const HURT_FLASH_TIME: float = 0.12
## The body a downed hero leaves behind (see `_enter_downed`). Graphite, not the
## player's colourway: the fiction is a PENCIL DRAWING being rubbed off the page, and
## a bright coloured corpse would read as a second live fighter lying there.
const HERO_CORPSE_COLOR: Color = Color(0.42, 0.44, 0.52, 0.95)
## A hero death gets a slightly longer beat than a trash mob's — it is the moment the
## run can end — but it is still a beat and not a cutscene.
const HERO_DEATH_BEAT: float = 0.68
## The death animation (fold + rub-out), loaded by PATH — see `Enemy._spawn_corpse`
## for why a brand-new `class_name` must not be NAMED from a shipped script.
const DEATH_SMUDGE_SCRIPT: String = "res://scripts/combat/DeathSmudge.gd"
const HURT_HIT_STOP: float = 0.05
const HURT_SHAKE: float = 7.0
## Weighted hitstop: melee connect sits between spell hit and enemy death.
const MELEE_HIT_STOP: float = 0.07
## Directional camera punch along facing when a melee connects (px).
const MELEE_CAMERA_KICK: float = 5.0
## Dash afterimage cadence/tint (~4-5 ghosts across the 0.14s dash).
const GHOST_INTERVAL: float = 0.03
const GHOST_COLOR: Color = Color(0.6, 0.85, 1.0, 0.72)
## Persistent "charged mage" aura (enemies get none — hero reads as hero).
## Aura COLOUR comes from the active element (see _apply_element); only the
## strength is fixed here.
const AURA_STRENGTH: float = 0.6  # re-enabled: the HDR bloom pass now carries the
# glow as a soft halo instead of a flat sprite that obscured the figure.
## Body colourways (limb palette). Independent of the element — you can be a
## Jade stickman casting Fire. Cycled with `cycle_colourway` (C).
const COLOURWAYS: Array[Color] = [
	Color(0.4, 0.7, 1.0),  # Azure (the original hero blue)
	Color(1.0, 0.55, 0.35),  # Ember
	Color(0.6, 0.4, 0.95),  # Void
	Color(0.45, 0.9, 0.55),  # Jade
	Color(0.85, 0.85, 0.9),  # Mono
]
const SPELL_SCENE: PackedScene = preload("res://scenes/combat/Spell.tscn")
const BLAST_SCENE: PackedScene = preload("res://scenes/combat/BlastSpell.tscn")
const NOVA_SCENE: PackedScene = preload("res://scenes/combat/EnergyNova.tscn")

## EIGHT playable classes over ONE mobile-first slot system (see
## docs/superpowers/specs/2026-07-13-eight-class-roster-and-abilities.md). Each
## configures the SAME 7 slots with its own flavour — element, weapon, AoE
## variant, signature loadout — so touch controls never change but each class
## FEELS distinct. Enum names MAGE/ROGUE keep indices 0/1 (Arcanist/Shadowblade
## display names) so existing saves + tests stay valid; the mage config still
## equals the old consts, so index 0 is byte-identical to before.
##
## AoE (Q) variants: "blast" (placed meteor), "nova" (self whirlwind),
## "fist_shock" (fire-punch shockwave), "ground_slam" (earth crater). `element`
## is the class's default element (auto-set on switch; X still cycles). Signature
## loadout comes from SpellLibrary.build_for_class(class_id).
## APPEND ONLY. `_cycle_class` already wraps with `% HeroClass.size()`, but two
## places in the project hardcode the old count and must be widened alongside any
## addition here — `scripts/ui/Lobby.gd:83` (`% 8`, which would silently make a new
## class unselectable in co-op) and `tools/slice5_test_classes.gd`.
enum HeroClass { MAGE, ROGUE, BRAWLER, JUGGERNAUT, CLERIC, CRYOMANCER, STORMCALLER, WARLOCK, SWORDSAINT }
const CLASS_NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut",
	"Cleric", "Cryomancer", "Stormcaller", "Warlock", "Swordsaint",
]
## ⚠ `hp` AND `speed` ARE THE STAT SPINE, AND THEY DID NOT EXIST. Before this table
## carried them there was no `hp` key at all — every class was `BASE_MAX_HP = 100` —
## and `SPEED = 210.0` was a global const read straight out of `_physics_process`. Nine
## classes were mechanically identical before either player cast anything, which is the
## thing the maker's ruling is actually about.
##
## THE SPREAD, and why it stops where it does. HP runs 109 (Shadowblade) to 203
## (Juggernaut) — 1.86x — and speed 165 to 240 — 1.45x. Both are chosen to be READABLE
## in a two-second look and no wider: this is a co-op brawler, not an MMO, and a spread
## big enough to make a class strictly correct is a spread that has removed a choice.
## The two axes trade against each other on purpose (the fastest body is the frailest,
## the toughest is the slowest), so no class is simply better at existing.
##
## ⚠ EVERY `hp` BELOW WAS MULTIPLIED BY 1.4 ON 2026-08-04 AND THE SPREAD IS UNCHANGED.
## Maker: *"the character needs more HP ... the opponents should do less damage its
## very difficult of a game right now"*. The table used to run 78-145; it now runs
## 109-203. A UNIFORM multiplier was chosen over nine hand-picked numbers precisely
## because it PROVABLY preserves the thing the paragraph above defends — 203/109 is
## still 1.86x, the ordering is untouched, and no two rows collided on the rounding.
## Hand-tuning nine numbers to "feel right" would have quietly rewritten the roster's
## shape while claiming to fix difficulty.
##
## WHY 1.4 AND NOT 1.5. Raising HP is the only difficulty lever reachable from this
## file — enemy damage lives in `Enemy.gd` / `Encounter.gd` and is another agent's — and
## 1.4x is a ~29% cut in effective incoming damage, which is a felt change without
## making the early floors trivial. It does NOT stand alone: `Progression`'s VITALITY
## axis multiplies this base by up to +87% at level 30, so a levelled climber is
## already carrying ~2.1x the old pool. The complaint is about the EARLY game, where
## Growth has banked nothing and this table IS the whole health bar — so the fix goes
## here, at level 1, and the late game is deliberately not compensated further.
##
## HOW A PER-CLASS BASE COMPOSES WITH GEAR. `configure_class` seeds `_base_max_hp` FROM
## THIS TABLE and `_recompute_gear_effects` scales `max_hp` off that base, idempotently
## — so the hat multiplies the class number instead of overwriting it, and re-running a
## loadout swap never compounds. A spawner that wants to impose its own pool (BotMatch's
## `CLASS_VITALITY`, VersusArena's showcase HP) still writes `max_hp` AFTER
## `configure_class` and still wins, exactly as before.
const CLASS_CONFIG: Dictionary = {
	HeroClass.MAGE: {  # ARCANIST — ranged arcane zoner (byte-identical to the old mage)
		"preset": "mage", "weapon": "", "element": Elements.Element.ARCANE, "melee_element": -1,
		"hp": 126, "speed": 205.0,  # was 90
		# Staff POKE: a caster's melee is a shove to buy space, not a trade.
		"melee_cd": 0.36, "melee_arc_dot": 0.25, "melee_damage": 13,
		"melee_range": 62.0, "melee_knockback": 280.0,
		"cast_cd": CAST_COOLDOWN, "dash_cd": DASH_COOLDOWN, "blink_cd": BLINK_COOLDOWN,
		"blast_cd": BLAST_COOLDOWN,
		"move_verb": "arcane_phase", "dash_iframe_fraction": ARCANE_PHASE_IFRAME_FRACTION,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "arcane_meteor", "has_nova": true, "can_parry": true,  # Q: arcane star-fall
	},
	HeroClass.ROGUE: {  # SHADOWBLADE — twitchy assassin; LMB = 3-dagger flurry
		"preset": "rogue", "weapon": "sword", "element": Elements.Element.SHADOW, "melee_element": Elements.Element.SHADOW,
		# ⚠ 109 -> 122 ON MEASUREMENT, and it costs the class its "frailest" title.
		# The Shadowblade read 27% / 28% / 33% across three 288-bout sweeps — the only
		# class in the bottom three of ALL THREE, which is the strongest signal in the
		# whole table (nothing else agrees across more than two samples).
		#
		# HP rather than damage, following the Cryomancer's own precedent two rows
		# down: a glass cannon that dies before its third exchange never gets to be a
		# cannon, and its damage case has not been argued out the way `Shatter`'s was.
		# ⚠ 114 AND NOT MORE, BECAUSE THE FRAILTY IS A GUARDED INVARIANT. The first
		# pass at this put it at 122 and `slice_test_class_movement` failed on exactly
		# the right thing: "the Shadowblade is the frailest body in the roster". That
		# is a design ruling with a suite behind it, not an accident, and the maker
		# asked for a slight buff — not for the assassin to stop being the squishiest
		# thing on the floor. 114 sits one point under the Stormcaller's 115 and keeps
		# the title. The rest of the help comes from the band below, not from meat.
		# ⚠ AND IT IS UNPRICED. Every sweep quoted above predates BOTH this change and
		# the class's new bespoke Tier 3 (`severance`), which is itself an unmeasured
		# buff. Two changes, one measurement, and the measurement is older than both.
		"hp": 114, "speed": 240.0,  # was 78, then 109
		"primary": "bolt", "bolt_burst": 3, "bolt_spread": 0.13,
		"cast_cd": 0.30, "dash_cd": 0.70, "blink_cd": 1.0,
		"blast_cd": 2.5,
		# THE BEST AIR GAME IN THE ROSTER: two air jumps AND a gravity-ignoring dash.
		"air_jumps": 2,
		"move_verb": "air_dash", "dash_iframe_fraction": AIR_DASH_IFRAME_FRACTION,
		# ⚠ 9 -> 6, AND IT IS THE ONLY BURST PRIMARY IN THE ROSTER. Maker: *"the default
		# attack for the shadowclass shooting loads of different 3 in a direction is
		# cool but the damage may make it too op right now"* — and the arithmetic agrees
		# rather than just the eye. `bolt_burst: 3` at 9 each on a 0.30 s cooldown is
		# 90 DPS, against a field mean of 56 and a second place (Brawler) of 70: +60%
		# over the roster and +29% over anything else, delivered at 560 px while the
		# two classes near it have to be in contact. At 6 it lands on 60 DPS, which is
		# the middle of the field, and the THREE SHOTS — the thing the maker likes —
		# are untouched.
		"throw_blade": true, "blade_damage": 6,
		"dash_strike": true, "dash_strike_damage": 16, "dash_strike_range": 42.0,
		"aoe": "nova", "has_nova": false, "can_parry": true,
	},
	HeroClass.BRAWLER: {  # PURE MELEE, no magic — punch/kick combo + double-jump + Thunderclap
		"preset": "brawler", "weapon": "", "element": Elements.Element.FIRE, "melee_element": Elements.Element.FIRE,
		"hp": 161, "speed": 215.0,  # was 115
		"primary": "melee_combo", "air_jumps": 1, "melee_cd": 0.20, "melee_knockback": 320.0,
		"cast_cd": 0.22, "dash_cd": 0.70, "blink_cd": 1.1, "blast_cd": 2.2,
		"move_verb": "charge", "dash_iframe_fraction": CHARGE_IFRAME_FRACTION,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": true, "dash_strike_damage": 20, "dash_strike_range": 44.0,
		"dash_strike_knockback": CHARGE_STAGGER_KNOCKBACK,  # the charge STAGGERS
		"mobility2": "uppercut", "aoe": "fist_shock", "has_nova": true, "can_parry": true,
	},
	HeroClass.JUGGERNAUT: {  # slow siege tank — wide heavy hammer, BLOCK, no blink
		"preset": "juggernaut", "weapon": "sword", "element": Elements.Element.EARTH, "melee_element": Elements.Element.EARTH,
		"hp": 203, "speed": 165.0,  # was 145 — still the toughest body in the roster
		"primary": "heavy_swing", "melee_cd": 0.55, "melee_arc_dot": 0.0, "melee_damage": 30, "melee_range": 96.0, "melee_knockback": 470.0,
		"cast_cd": 0.40, "dash_cd": 0.90, "blink_cd": 1.4, "blast_cd": 2.6,
		"move_verb": "surge", "dash_iframe_fraction": SURGE_IFRAME_FRACTION,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": true, "dash_strike_damage": 22, "dash_strike_range": 48.0,
		"defense": "block", "aoe": "ground_slam", "has_nova": true, "can_parry": true,
	},
	HeroClass.CLERIC: {  # radiant sustain bruiser — LMB heal-bolt (lifesteal)
		"preset": "cleric", "weapon": "staff", "element": Elements.Element.HOLY, "melee_element": Elements.Element.HOLY,
		"hp": 154, "speed": 200.0,  # was 110
		"primary": "bolt", "bolt_heal": 2,   # 4 -> 2: see the lifesteal note below
		# ⚠ LIFESTEAL WAS THE UNDERCOSTED STAT IN THE GAME. Cleric and Warlock are the
		# ONLY two classes with `bolt_heal`, they carry the two LOWEST-throughput kits
		# in the roster (65.4 and 65.1 dmg/s, the bottom two), and they finished 1st and
		# 2nd across 288 measured bouts — 91% and 84%. They were not out-damaging
		# anyone; they were refusing to die. Cleric also SCALED with fight length (88%
		# at high HP vs 69% at low), which is the signature of sustain rather than of a
		# strong kit. Both cut to 2 rather than removed: the heal is the CLASS, and the
		# fix is to make it a trade instead of a free win. FEEL — the maker judges at F5.
		# Censer SWING: slow, wide-ish, the heaviest shove of the four staff casters.
		"melee_cd": 0.40, "melee_arc_dot": 0.15, "melee_damage": 17,
		"melee_range": 68.0, "melee_knockback": 340.0,
		"cast_cd": 0.32, "dash_cd": 0.85, "blink_cd": 1.2, "blast_cd": 2.4,
		"move_verb": "radiant_step", "dash_iframe_fraction": RADIANT_STEP_IFRAME_FRACTION,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "consecrate", "has_nova": true, "can_parry": true,  # Q: consecrated ground
	},
	HeroClass.CRYOMANCER: {  # ice control — LMB is a FROST CONE, not a bolt
		"preset": "cryomancer", "weapon": "staff", "element": Elements.Element.ICE, "melee_element": Elements.Element.ICE,
		# ⚠ 123 -> 152 ON A MAKER RULING BACKED BY MEASUREMENT. Maker: "the ice class
		# needs a buff." A 72-bout sweep (all 36 pairings, both side orders) put the
		# Cryomancer at 25% — second worst in the roster, and a finding nobody had
		# flagged before.
		#
		# THE BUFF IS HEALTH, AND DELIBERATELY NOT DAMAGE. `Shatter`'s own header
		# already argues the damage case out and is right: base 62 x FROZEN_MULT 3.0 is
		# 186 on one body, which is the single biggest hit in the roster, on the DAMAGE
		# slot, on a 4 s cooldown. This class's ceiling is not the problem.
		#
		# What the sweep actually shows is a class that DIES WHILE SETTING UP. Its kit
		# combos with itself — Blizzard to chill, Shatter to cash it in — so its damage
		# costs two casts and a global lockout before anything lands, and it pays for
		# that wait with the roster's 2nd-lowest health, its LOWEST melee damage (11),
		# and a short-range `frost_cone` primary that puts a caster inside the range it
		# is least able to survive. 152 is the number `BotMatch.CLASS_VITALITY` 1.10
		# previews (the two tables agree to within 0.1 across all nine rows, which is
		# what makes a bot match a faithful preview of a class change).
		"hp": 152, "speed": 195.0,  # was 88, then 123
		"primary": "frost_cone",
		# Rimed JAB: little damage, wide arc, and the biggest shove of any caster —
		# the control class's melee CONTROLS.
		"melee_cd": 0.30, "melee_arc_dot": 0.35, "melee_damage": 11,
		"melee_range": 56.0, "melee_knockback": 420.0,
		"cast_cd": 0.34, "dash_cd": 0.90, "blink_cd": 1.2, "blast_cd": 2.6,
		"move_verb": "ice_slide", "dash_iframe_fraction": ICE_SLIDE_IFRAME_FRACTION,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "ice_shards", "has_nova": true, "can_parry": true,  # Q: homing frost shards
	},
	HeroClass.STORMCALLER: {  # hyper-mobile chain caster — LMB arcs, fast wind-dash
		"preset": "stormcaller", "weapon": "staff", "element": Elements.Element.LIGHTNING, "melee_element": Elements.Element.LIGHTNING,
		"hp": 115, "speed": 230.0,  # was 82
		"primary": "bolt", "bolt_chain": 2,
		# Crackling SWAT: the fastest, weakest, widest melee in the game — it is a
		# panic button that buys a beat, not an attack.
		"melee_cd": 0.24, "melee_arc_dot": 0.40, "melee_damage": 10,
		"melee_range": 54.0, "melee_knockback": 250.0,
		"cast_cd": 0.30, "dash_cd": 0.55, "blink_cd": 1.0, "blast_cd": 2.4,
		# NO DASH AT ALL — the movement button teleports (LIGHTNING_BLINK_DISTANCE).
		"move_verb": "lightning_blink", "dash_iframe_fraction": 0.0,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "call_lightning", "has_nova": true, "can_parry": true,  # Q: lightning strike column
	},
	HeroClass.WARLOCK: {  # dark attrition hexer — LMB drain-bolt (weaken + lifesteal)
		"preset": "warlock", "weapon": "sword", "element": Elements.Element.SHADOW, "melee_element": Elements.Element.SHADOW,
		"hp": 133, "speed": 190.0,  # was 95
		"primary": "bolt", "bolt_heal": 2,   # 3 -> 2: see the Cleric lifesteal note above
		# Scythe RAKE: the slowest, longest, most committed swing short of the
		# Juggernaut's hammer, and the narrowest arc in the game.
		"melee_cd": 0.46, "melee_arc_dot": 0.05, "melee_damage": 21,
		"melee_range": 74.0, "melee_knockback": 300.0,
		"cast_cd": 0.30, "dash_cd": 0.85, "blink_cd": 1.1, "blast_cd": 2.5,
		"move_verb": "thrall_swap", "dash_iframe_fraction": 0.0,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "curse_chain", "has_nova": true, "can_parry": true,  # Q: leaping shadow chain
	},
	# 8 SWORDSAINT — the DUELIST. The only class whose DEFENCE produces its OFFENCE:
	# every other class guards to survive a beat, this one guards to be paid. See the
	# BLADE-GUARD block below for the whole identity.
	#
	# `defense: "held_guard"` is the switch. It routes RMB onto ParryRing's BLADE
	# style — a visible ring you close on the hit rather than a hidden 0.16 s window —
	# and banks what it turns away into an unsheathe cut on release.
	#
	# NO BLINK (`blink_cd` is left at a real value only because `_blink()` reads it;
	# `mobility2: "uppercut"` sends R to the rising cut instead, so this class has no
	# teleport at all). It closes on foot or by dash-strike and does not teleport out
	# of its own mistakes — the same trade Juggernaut makes.
	#
	# `melee_element: -1` is deliberate and is the class's whole flavour rule: PLAIN
	# STEEL APPLIES NO AILMENT. Give the Swordsaint a burn and it becomes "the fire
	# melee class"; the point is that the blade is just a blade, and the X-cycle only
	# tints the edge (which is what still feeds the reaction layer).
	#
	# `preset: "rogue"` because CharacterRig ships no "swordsaint" arm and an
	# unmatched preset name silently leaves the PREVIOUS class's kit on the figure.
	# "rogue" is hood + sword, and `get_weapon_tip()` gives "sword" a real
	# `height * 0.5` reach. A bespoke preset with a two-handed greatsword is a
	# CharacterRig change and is reported in the handoff, not faked here.
	HeroClass.SWORDSAINT: {
		"preset": "rogue", "weapon": "sword",
		"element": Elements.Element.ARCANE, "melee_element": -1,  # plain steel: no ailment
		# 210 -> 222 on the same 2026-08-05 ruling as COMMITTED_STEP_*. The walk was
		# already 4th of 9, so the felt slowness was the verb — but the approach is
		# the one part of this class's offence that is not on a cooldown, so it moves
		# too. 222 keeps all nine speeds distinct, stays under Shadowblade's 240 and
		# over Juggernaut's 165, and leaves the roster spread at 1.45x (cap 1.6x).
		"hp": 147, "speed": 222.0,  # was 105, then 210
		"primary": "heavy_swing",
		# The greatsword profile, expressed as melee overrides rather than a new
		# WEAPON_STATS row: a "greatsword" kind would have no rig texture and no
		# `get_weapon_tip` arm, so the blade would vanish and every spell would spawn
		# out of the hero's navel. Slower and wider than the Shadowblade, shorter and
		# far more controllable than the Juggernaut's 96 px hammer.
		## ⚠ 26 -> 34 AND 0.42 -> 0.38. Maker: *"the brawler also has a close range but
		## destroyed sword saint maybe the saint needs a buff dmg"*. Unlike most balance
		## reports this one is NOT a single fight — the Swordsaint is the only class in
		## the roster broken beyond doubt, measured at 19% and then 25% across two
		## separate 72-bout round-robins, and unmoved by +45% health. Its own balance
		## table says in writing that a class needing that much vitality to reach parity
		## does not have a health problem.
		##
		## The Brawler comparison is the sharp end of it: 14 damage on a 0.20 s cadence
		## is 70 DPS, against this class's 26 on 0.42 s — 62 — while ALSO being the
		## slower body with the smaller dodge. 34 on 0.38 s is 89, which is what a
		## committed two-handed swing on a duellist should be worth against a jab.
		"melee_cd": 0.38, "melee_arc_dot": 0.05, "melee_damage": 34,
		"melee_range": 86.0, "melee_knockback": 430.0,
		## ⚠ THE TWO SLOWEST COLUMNS IN THE ROSTER, BOTH ON ONE CLASS. Maker: *"the other
		## two abilities before that need shorter cool downs and need to be buffed they
		## dont look that coool right now or do much"*. `cast_cd` 0.45 and `blast_cd` 3.0
		## were the longest of all nine — on the class that also had the smallest dodge —
		## so the Swordsaint spent more of every fight waiting than any other body in the
		## game, which is most of why it measures 19-25% on the honest harness. This is
		## the KIT fix the balance table's own header keeps saying is the real answer,
		## rather than another point of vitality.
		"cast_cd": 0.34, "dash_cd": 0.72, "blink_cd": 1.0, "blast_cd": 2.2,
		"throw_blade": false, "blade_damage": 18,
		## The rising cut is this class's only vertical answer and it hit for less than
		## its own basic swing. 24 -> 34, and the reach comes up with it.
		"dash_strike": true, "dash_strike_damage": 34, "dash_strike_range": 60.0,
		"mobility2": "uppercut",  # a rising cut, not a teleport
		# Retuned 2026-08-05: no longer the roster's shortest travel (106.4 px, 6th of
		# 9), but still its smallest dodge. It gets a way IN, not a way out.
		"move_verb": "committed_step",
		"dash_iframe_fraction": COMMITTED_STEP_IFRAME_FRACTION,
		"defense": "held_guard", "aoe": "ground_slam",
		"has_nova": false, "can_parry": true,
	},
}

@export var max_hp: int = 100
var hp: int = 100
## SANDBOX Smash model (GameState.ringout_mode): instead of draining hp, hits pile
## onto this damage_pct, and knockback scales with it (higher % = you fly farther).
## Reset to 0 on a ring-out respawn (VersusArena._respawn). Tower mode ignores it.
var damage_pct: float = 0.0
## ⚠ MANA NO LONGER GATES ANYTHING. Per the mobile spec — "Cooldowns, not mana. Mana
## makes people hoard and play safe, which is the opposite of what this game wants" —
## `_cast_signature` no longer checks or spends it. The pool is still tracked and still
## regenerates (so it reads full, and so `mana_changed` keeps its subscribers), but
## nothing can run out of it and no cast is ever refused for it.
##
## WHY THE FIELDS SURVIVE RATHER THAN BEING DELETED. `SpellDef.mp_cost` is read by two
## systems that have nothing to do with resource management: `SpellTier.of()` uses it
## as one of three shelf thresholds (>= 70 forces ULT), which is ALSO the reaction
## clash weight and the loadout slot rule; and the cast/channel sigils scale their
## radius by it, so the tell of a big spell is literally sized from its cost. Deleting
## the field would silently reshelve spells and shrink their telegraphs — an expensive
## change to save a float per hero.
##
## There is no mana UI to hide: `CharacterBars.configure(show_mp)` defaults to false
## and no caller has ever passed true, so the bar has never been drawn.
@export var max_mp: int = 100
var mp: float = 100.0
## Equipped SIGNATURE loadout (SpellLibrary) — the spell tree the player cycles
## (V) and unleashes (Ultimate key), MP-gated with a per-spell cooldown.
var _signatures: Array = []
var _signature_index: int = 0

## PER-SLOT COOLDOWNS, owned by `HandSlots`.
##
## This used to be a single `_signature_cd_timer` float: ONE bank shared by the whole
## kit, so throwing a 1.2 s jab locked your 9 s ult for 1.2 s and — much worse —
## throwing the ult locked every other spell in the kit for nine seconds. With three
## spell buttons on the right thumb that is not a balance quirk, it is the buttons not
## working: two of the three are dark most of the fight for reasons the player cannot
## see, because the bar was showing three cooldowns that were secretly one number.
##
## `HandSlots` already implemented real per-slot cooldowns (`start_cooldown` / `tick`
## / `is_ready`), fully headless-tested, and was used by nothing but the spike
## playground and `LoadoutBar`. This is that code finally being called by the shipped
## hero rather than a second implementation of it.
##
## ⚠ THE INDEX OFFSET. `HandSlots` always keeps FISTS at index 0 so a player can never
## end up with no melee option, so signature slot `i` lives at hand index `i + 1`.
## Never index `_hand` with a signature index directly — go through `_hand_slot()`.
var _hand: HandSlots = HandSlots.new()
const HAND_SPELL_OFFSET: int = 1
## READY-FLASH. How long a slot celebrates coming off cooldown. Long enough to catch
## out of the corner of an eye mid-fight, short enough that three slots recovering in
## sequence do not merge into one continuous glow. UNTESTED FEEL GUESS.
const READY_PULSE_TIME: float = 0.38
## Per-slot flash timers + the not-ready -> ready edge detector behind them. Sized
## lazily to `SpellTier.SLOT_COUNT` on the first tick.
var _ready_pulse: Array[float] = []
var _was_slot_ready: Array[bool] = []
## Twin-stick: `facing`/`_aim_dir` track the CURSOR (drive casts, melee arc, cast
## pose, camera peek); `_move_dir` tracks WASD (drives dash + blink dodge). They
## are decoupled so you can run one way while aiming/casting another (strafe).
var facing: Vector2 = Vector2.RIGHT

## Co-op: the class comes from the lobby (net_class >= 0), not GameState. `_net`
## caches /root/Net so the per-frame authority check is cheap. Singleplayer leaves
## net_class at -1 and _net.is_active() false, so nothing below changes SP.
var net_class: int = -1
var _net: Node = null

# ---------------------------------------------------- co-op replicated visual state
## THE SYNC SET, published by the owner and read by every puppet. Before this, a
## teammate slid around in a run cycle no matter what they were doing, remote HP bars
## misread whenever two classes had different max_hp, and nothing about aim, element,
## guard or casting crossed the wire at all. These are plain public vars because a
## `MultiplayerSynchronizer` replicates PROPERTIES — see `_setup_net_sync`.
##
## `net_anim` is the rig State the owner is actually playing (cast, swing, dash,
## parry-hurt, wall-slide, air), not a guess reconstructed from velocity.
var net_anim: int = 0
## Where the owner is pointing. Drives the puppet's aim arm and weapon, so a
## teammate visibly tracks a target instead of staring down their movement vector.
var net_aim: Vector2 = Vector2.RIGHT
## The owner's ACTIVE element — a teammate who cycles to fire should visibly change
## colour on your screen, and every replayed cast is tinted from it.
var net_element: int = Elements.Element.ARCANE
## Bitfield of the states that have no rig State of their own. Cheaper and far less
## churn-prone than five more synced booleans.
const NET_F_GUARD: int = 1 << 0
const NET_F_PARRY: int = 1 << 1
const NET_F_CASTING: int = 1 << 2     # channel or summon windup — the levitating commit
const NET_F_DASH: int = 1 << 3
const NET_F_LIMP: int = 1 << 4        # hold-DOWN ragdoll flop
var net_flags: int = 0
## Edge-detect for the flag bits above, so a one-shot visual (the parry shell) fires
## once on the transition rather than every frame the bit is set.
var _remote_flags: int = 0
var _remote_element: int = -1

## THE DEAD GROUP a puppet's attacks scan. See `attack_group()` and `Net.GHOST_GROUP`.
const NET_GHOST_GROUP: StringName = &"none"
## True only for the duration of one replayed action (see `net_replay_action`).
## Scoped, unlike `_is_net_puppet()`: it exists so `_aim_point()` can answer with the
## ORIGINATING player's cursor instead of ours, and so `_melee` can skip declaring a
## clash on behalf of a body it does not own.
var _replaying: bool = false
var _replay_point: Vector2 = Vector2.ZERO
## Puppet-side windup clock — grows the replayed cast sigil (see `_remote_visual`).
var _remote_cast_elapsed: float = 0.0
var _remote_cast_total: float = 0.0
## Elemental ailment component, created on the first status a hero actually takes.
## Mirrors `Enemy._status`; null until then, so nothing costs anything until you
## are set on fire.
var _status: StatusComponent = null

var _aim_dir: Vector2 = Vector2.RIGHT
var _move_dir: Vector2 = Vector2.RIGHT
var is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _ghost_timer: float = 0.0
var _cast_cooldown_timer: float = 0.0
var _melee_cooldown_timer: float = 0.0
var _melee_kick_next: bool = false
var _flaming_fist_timer: float = 0.0
var _fist_ember_timer: float = 0.0
var _last_hand_pos: Vector2 = Vector2.ZERO
var _blast_cooldown_timer: float = 0.0
var _blink_cooldown_timer: float = 0.0
var _blink_iframe_timer: float = 0.0
var _nova_cooldown_timer: float = 0.0
var _parry_window_timer: float = 0.0
var _parry_cooldown_timer: float = 0.0
var _parry_window_len: float = PARRY_WINDOW  # per-class (Juggernaut BLOCK = longer window)
## The BLADE guard ring — non-null ONLY for a class whose `defense` is
## "held_guard" (today: Swordsaint). Null everywhere else, so all eight shipped
## classes keep the press-window parry they were balanced against and nothing about
## their defensive feel moves. Migrating the other eight onto the ring is a real
## improvement and a separate change; doing it inside a new class's commit would
## retune eight classes under cover of adding a ninth.
var _guard: ParryRing = null
var _guard_bank: int = 0
var _guard_hits: int = 0
var _wall_jump_lock: float = 0.0   # horizontal-input lock after a wall-kick
var _was_wall_sliding: bool = false
var _wall_dust_timer: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _air_jumps: int = 0
var _max_air_jumps: int = 0  # per-class air jumps (Brawler double-jumps); set in configure_class
var _was_on_floor: bool = true  # for the landing-dust transition edge

## HOW MANY GRAVITY WELLS THIS BODY IS INSIDE. A COUNTER, not a bool, and that is
## load-bearing: two overlapping wells (two Juggernauts, or one re-cast over its own
## tail) would each clear a bool on the way out, and the first exit would strip a grant
## the second field still owns.
##
## While it is > 0 the hero steers with GROUND-grade authority despite being airborne.
## That is the whole of "move freely inside the gravity radius" on this side — every
## other verb already worked while lifted, because `GravityFlip` only ever writes
## `velocity.y`. What losing the floor cost was 44% of the steering (AIR_ACCEL 1450 vs
## GROUND_ACCEL 2600), and this is that back.
##
## ⚠ IT DOES NOT GIVE BACK THE JUMP. `is_on_floor()` is still false inside a well, so no
## jump, no wall-jump, no landing. That is correct: the well is supposed to take the
## floor away. It gives back CONTROL, not ground.
var grav_fields: int = 0


func enter_grav_field() -> void:
	grav_fields += 1


func exit_grav_field() -> void:
	grav_fields = maxi(grav_fields - 1, 0)
var _weapon: String = "fists"
var _melee_damage: int = MELEE_DAMAGE
var _melee_range: float = MELEE_RANGE
var _melee_knockback: float = MELEE_KNOCKBACK
var _melee_cd: float = MELEE_COOLDOWN     # per-class swing cadence (Brawler fast, Juggernaut slow)
## Seconds a DECLARED swing still has to reach its own hit frame. Gates
## `_on_melee_hit_frame`, which the rig fires for any PUNCH/KICK animation — see the
## block at the top of that function for the four things that played one without
## meaning to swing.
##
## A self-expiring WINDOW rather than a bare flag on purpose: a swing interrupted
## before its hit frame (a HURT one-shot cutting in) would leave a flag raised, and the
## next animation to fire — quite possibly one of the four — would spend it. A window
## closes on its own.
var _swing_window: float = 0.0
## How long that window stays open. The longest strike one-shot is the 0.26 s KICK and
## its hit frame lands at 0.35 of that; this is comfortably past it while still being
## far shorter than any ability cooldown.
const SWING_WINDOW: float = 0.30
var _melee_arc_dot: float = MELEE_ARC_DOT # per-class arc width (Juggernaut swings wide)
var _buffered_action: String = ""
var _buffer_timer: float = 0.0
## Seconds until any kit slot may be cast again. See GLOBAL_CAST_LOCKOUT.
var _cast_lockout: float = 0.0
## True when the buffered entry came from a HELD button rather than a fresh press.
## Only the spell buttons can produce one (hold = repeat-cast), and it is what stops
## a held button from firing the Rift Dagger's free RECALL beat the instant the throw
## leaves your hand: recall is a second PRESS, not a continuation of the first.
var _buffer_from_hold: bool = false
var _knockback: Vector2 = Vector2.ZERO  # shove received from an enemy hit / bomb
## How much of `velocity.x` is knockback OFFSET rather than locomotion, as laid on
## last frame. Taken back off before locomotion reads `velocity.x` again.
##
## ⚠ WITHOUT THIS THE SHOVE IS INTEGRATED AS AN ACCELERATION. `_knockback` is a
## channel that decays at KNOCKBACK_DECAY, and it was being ADDED to `velocity.x`
## every frame on top of a velocity that is only ever nudged toward walk speed — so
## each frame re-added a shove the previous frame had already banked. MEASURED on a
## flat slab with no opponent, for the 240 px/s impulse a plain bolt hit uses:
##     ridden once, decaying:      peak  240 px/s, travel  32 px
##     as shipped, time_scale 1.0: peak 1429 px/s, travel 219 px   (6.0x)
##     as shipped, during hitstop: peak 7676 px/s                  (32.0x)
## The second multiplier is the ugly one: `Juice.hit_stop` holds `time_scale` at 0.05
## for 0.06 s on EVERY connect while the tick rate stays put, so the addition — which
## is per-FRAME, not per-DELTA — runs ~20x as often. Launch distance therefore
## depended on whether a hit happened to trigger hitstop, which is why the same shot
## sent a body a different distance every time.
##
## `Enemy.gd:1037` and `Boss.gd:458` have always ASSIGNED (`velocity.x = chase +
## _knockback.x`), and `Enemy.gd:562` documents this exact failure mode on the other
## axis. Hero's `+=` was the outlier, not the pattern.
var _knockback_applied: float = 0.0
var _ragdolling: bool = false  # hold DOWN -> go limp + flop (the Stick-Fight ragdoll toy)
var _hero_class: int = HeroClass.MAGE
var _cfg: Dictionary = CLASS_CONFIG[HeroClass.MAGE]
var _dash_hit: Array = []  # enemies/props already struck this dash (rogue no-multi-hit)
# --------------------------------------------------- the nine movement verbs
## Which verb the CURRENT travel is (set at `_start_dash`, read by the per-frame dash
## branch). Cached rather than re-read from `_cfg` every tick so a mid-dash class
## switch — which `_cycle_class` makes reachable with Tab — cannot change the rules of
## a travel that is already in the air.
var _dash_verb: String = "dash"
## Travel speed + duration of the verb in flight. Members, not consts, because six of
## the nine differ and the dash branch must not carry a nine-way match per tick.
var _dash_speed: float = DASH_SPEED
var _dash_total: float = DASH_TIME
## ⚠ REMOVED with the recall return leg: `_recall_anchor` (where the outbound leg
## started) and `_recall_timer` (how long the second press stayed available). The
## Arcane Phase has NO state at all beyond the shared travel members above — that is
## the point of the redesign, since invisible per-class state was what made one button
## do two different things. See the ARCANE PHASE block up in the movement verbs.
## JUGGERNAUT: seconds of post-surge armour still owed. Read by `apply_knockback`.
var _surge_armor_timer: float = 0.0
## CLERIC: countdown to the next healing pulse dropped along a Radiant Step.
var _radiant_wake_timer: float = 0.0
## Active element (aura + ability colour). Cycled with `cycle_element` (X).
var _element: int = Elements.Element.ARCANE
var _element_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## GEAR EFFECTS (GearAbilities): aggregated from the equipped weapon/head/body and
## applied at single clean hooks — an elemental weapon overrides `_element`, melee
## mults rescale the melee profile, the hat rescales max HP, the hood rescales move
## speed, the robe wards the first hit each fight. Recomputed idempotently from the
## class BASE in _recompute_gear_effects (safe to re-run on a loadout swap).
const BASE_MAX_HP: int = 100
const GEAR_ELEMENT: Dictionary = {
	"arcane": Elements.Element.ARCANE, "ice": Elements.Element.ICE,
	"lightning": Elements.Element.LIGHTNING, "holy": Elements.Element.HOLY,
	"shadow": Elements.Element.SHADOW, "fire": Elements.Element.FIRE,
	"earth": Elements.Element.EARTH,
}
var _gear_speed_mult: float = 1.0
# Gear mitigation moved to GuardComponent (see _apply_gear / take_damage) so ward
# spells, armour and the one-shot robe all resolve through a single path.
## Class melee/HP base snapshot (captured post-class-setup incl. equip_weapon) that
## the gear mults scale FROM — so _recompute is idempotent and never clobbers the
## weapon-specific melee tuning equip_weapon already applied.
var _base_melee_damage: int = MELEE_DAMAGE
var _base_melee_knockback: float = MELEE_KNOCKBACK
var _base_melee_cd: float = MELEE_COOLDOWN
var _base_max_hp: int = BASE_MAX_HP
var _base_element: int = Elements.Element.ARCANE  # class innate element (revert target)
## The player's LOADOUT choices (from the hub Armory). Only these override the class
## and grant gear abilities — class-default gear stays cosmetic + as-tuned, so a class
## you never re-geared plays exactly as balanced. slot -> kind.
var _gear_override: Dictionary = {}
var _colourway: int = 0
## Mobile: set by TouchControls when the on-screen pad is active (or true on any
## touchscreen). Switches aim from the cursor to auto-target the nearest enemy so
## every ability works by tapping a button — no pixel-precise aiming (mobile-first).
var touch_input: bool = false

## THE DEATH RULE (maker, 2026-08-01): "dying cost is a life in ghost form until
## your teammate revives you; if you all die then the game is over."
##
## `downed` == "this hero is a GHOST": out of the fight, immune, no attacks, but
## still steering its own body (see `_process_downed`). It is set in a RUN in single
## player as well as in co-op — the two paths are the same one now, and
## `Arena._check_party_wipe` is the single place that decides the run is over.
## The standalone sandbox (F6 / the duel) still just resets to full, so the feel toy
## never stops. Public for the MultiplayerSynchronizer property path.
var downed: bool = false
## Self-revive charges left this run — `DeathRules.SOLO_SELF_REVIVE_CHARGES`, which
## ships at 0. At 1+ a death spends one and schedules a SECOND WIND instead of
## waiting for a teammate. See `DeathRules` for the argument.
var _self_revive_left: int = 0
## Counting down to a second wind; 0 = not pending. `Arena._check_party_wipe` refuses
## to call the run while this is running, or the charge would never get to fire.
var _second_wind_timer: float = 0.0
## HAUNT recovery, ticked only while a ghost.
var _ghost_haunt_cd: float = 0.0
## Puppet-side edge detector for the replicated `downed` flag, so a remote hero
## grows and sheds its ghost form on the other phone too.
var _ghost_shown: bool = false

@onready var rig: CharacterRig = $Rig
var _tuning: Node = null  # cached /root/Tuning (null in headless tests -> fallbacks)

# ------------------------------------------------- FACTIONS + BOT CONTROL SEAM
## THE GROUP THIS HERO'S ATTACKS SCAN — its faction, expressed the way targeting
## already works everywhere else in this codebase.
##
## Damage routing here used to be group-HARDWIRED rather than faction-based: the
## melee/dash/uppercut sweeps iterated `get_nodes_in_group("enemy")` as a literal,
## `_fire_punch` / `_ground_slam` hard-coded `"target_group": "enemy"`, and
## `SpellCaster.cast` had no group parameter at all, so every spectacle kept its
## `"enemy"` default whoever threw it. The consequence was that a hero-shaped bot
## could be driven perfectly and still could not fight ANYONE: it ignored other
## heroes completely, and in single player hero-vs-hero did literally nothing in
## either direction.
##
## Default `&"enemy"` = exactly today's behaviour, everywhere, so single player is
## unchanged unless a caller deliberately opts in.
var hostile_group: StringName = &"enemy"
## The team group this hero ANSWERS to, joined on top of the permanent `hero`
## group. Empty = no team, which is single player.
##
## This is the half that makes "same faction cannot hurt each other" expressible
## rather than just "heroes can hurt heroes": two bots on one side share a team
## group and both point `hostile_group` at the OTHER team's, so neither one's
## attacks can find the other at all. With `hostile_group = &"hero"` alone the
## only reachable arrangement is everyone-hits-everyone.
@export var faction_group: StringName = &""
## The per-instance input source. `null` = the human path — real `Input`, real
## cursor, byte-identical to before this seam existed, which is why every helper
## below is written as `controller != null` and not the other way round.
##
## Untyped so a scripted stub (a test, a replay) only has to implement the six
## polling methods, matching how the rest of this codebase duck-types its seams.
## In practice this is a `BotController`; see that file for why global
## `Input.action_press` cannot do this job.
var controller: Object = null
## The bot's own clock, advanced on SCALED delta. It exists so a bot's reaction
## timing lives on the SAME clock the player perceives: `Juice.hit_stop` drops
## `Engine.time_scale` to 0.05, so a bot ticking on unscaled time would get a
## ~20x reflex boost every time anything connected — a difficulty cheat that
## would look like physics.
var _bot_clock: float = 0.0


## Join a faction: which team I am on, and which team I attack. One call because
## setting one without the other is always a bug — a hero with a team but no
## hostile group attacks nobody, and one with a hostile group but no team cannot
## be attacked back.
##
## Safe before OR after the node enters the tree: `_ready` re-joins the group, and
## this joins immediately when already inside.
func set_faction(team: StringName, hostile: StringName) -> void:
	faction_group = team
	hostile_group = hostile
	if team != &"" and is_inside_tree():
		add_to_group(team)


## THE GROUP THIS HERO'S ATTACKS ACTUALLY SCAN — `hostile_group` with friendly fire
## folded in. Every damage sweep in this file goes through this; nothing else does.
##
## ⚠ THE SPLIT MATTERS, and collapsing it would be the obvious wrong shortcut.
## `hostile_group` is FACTION — "whose side am I not on". It is read by `BotBrain`
## through `bot_body_state()`, by `Spell._damage_hero`'s permission ladder, and it is
## the only way "two bots on one team" is expressible at all. Overwrite it with
## `mortal` and every bot in the game immediately treats its own teammates as the
## enemy it should be walking toward.
##
## What an ATTACK asks is the narrower question — "who may this blow touch" — and
## under friendly fire the answer is *everyone with a body*. So the faction stays put
## and the attack scans widen. One consequence worth stating out loud because it is
## the entire feature: your teammate is in this group, and the spec wants them there.
##
## ⚠ THE CO-OP CLAUSE IS PERSISTENT, NOT SCOPED, AND THAT IS THE WHOLE POINT. A
## remote hero on this screen is a COSMETIC copy: the real one is being played on
## another phone, and its damage already resolves there through the victim-authority
## router. Everything this puppet throws must therefore find nobody, or every hit in
## a co-op game would land twice.
##
## It is answered here rather than by a flag around the replay call because half of a
## hero's damage resolves LATER than the call that started it — `_on_melee_hit_frame`
## fires off the rig's own `hit_frame` signal, frames after the swing was replayed. A
## transient flag would have covered the spells and silently missed the fists.
func attack_group() -> StringName:
	if _is_net_puppet():
		return NET_GHOST_GROUP
	return SpellCaster.damage_group(hostile_group)


## True when this node is another player's hero being drawn on our screen. Every
## co-op gate in this file that must distinguish "I drive this body" from "I only
## draw it" asks this, so the OfflineMultiplayerPeer exclusion in `Net.is_active()`
## is honoured in exactly one place.
func _is_net_puppet() -> bool:
	return _net != null and _net.is_active() and not is_multiplayer_authority()


## SELECT A KIT SPELL BY INDEX — the seam that makes a bot able to use its whole
## kit at all.
##
## `cast_slot` indexes `_signatures`, which `SpellLibrary.build_for_class` returns
## in `ROLE_ORDER` (damage / control / answer / payoff / ult), so `idx` IS the
## role for every class.
##
## ⚠ WHY THIS EXISTS RATHER THAN A BOT PRESSING `cycle_signature`. That action is
## SHARED UI: it is the player's V key, it walks the selection one step at a time
## (so reaching slot 3 takes three presses and passes through two wrong spells),
## and pressing it through global `Input` would cycle the HUMAN'S selection too.
## `BotController` therefore keeps `cycle_signature` permanently forbidden and
## comes here instead. Without this method a bot can only ever cast whichever
## signature happened to be selected — i.e. it spams one spell forever, which is
## exactly what it did before this landed.
##
## Deliberately does NOT emit `signature_changed`: that signal drives the player's
## on-screen loadout label, and a bot silently retargeting its own kit must not
## make the human's HUD flicker through spell names they did not choose.
## Returns false for an out-of-range index rather than clamping, so a brain bug
## reads as "the cast did not happen" instead of as a plausible wrong spell.
func bot_select_signature(idx: int) -> bool:
	if idx < 0 or idx >= _signatures.size():
		return false
	_signature_index = idx
	return true


## The spell currently selected for the `ultimate` button, or null.
func signature_at(idx: int) -> SpellDef:
	if idx < 0 or idx >= _signatures.size():
		return null
	return _signatures[idx] as SpellDef


## Everything a bot brain is allowed to know about THIS body, in the blackboard's
## key names. Lives here rather than in BotController so the private cooldown
## timers stay private and so any other body type (an Enemy, later) can become
## bot-drivable by implementing this one method.
##
## FAIRNESS: own state only. Every field is something the player reads off their
## own screen — their body, their floating HP/MP bars, their ability bar, their
## own class and its loadout. There is deliberately no field describing the
## OPPONENT'S cooldowns, mana or intent.
func bot_body_state() -> Dictionary:
	var cds: Array[float] = []
	for _i: int in BotIntent.CD_COUNT:
		cds.append(0.0)
	# PER-SLOT, and now genuinely so. This used to publish the single shared bank
	# under every slot index — the shape was already right ("ask cooldowns[cast_slot]")
	# and the numbers were a lie, so a brain that reasoned about which slot to reach
	# for was reasoning about one timer wearing five hats.
	#
	# Slots past the kit's size report 0.0 (ready). `slot_affordable` below is what
	# actually tells a brain those slots hold nothing, and it is the stricter answer.
	for slot: int in BotIntent.SLOT_COUNT:
		cds[slot] = signature_cooldown(slot)
	cds[BotIntent.CD_PRIMARY] = _cast_cooldown_timer
	cds[BotIntent.CD_DASH] = _dash_cooldown_timer
	cds[BotIntent.CD_BLAST] = _blast_cooldown_timer
	cds[BotIntent.CD_BLINK] = _blink_cooldown_timer
	cds[BotIntent.CD_NOVA] = _nova_cooldown_timer
	cds[BotIntent.CD_SWING] = _melee_cooldown_timer
	# The defensive slot is two different verbs behind one button, so the number
	# published is the one the ability bar shows: a press class reports its wipe,
	# a held-guard class reports its re-arm.
	cds[BotIntent.CD_GUARD] = _parry_cooldown_timer
	if _guard != null:
		cds[BotIntent.CD_GUARD] = 0.0 if _guard.is_ready() else _guard.rearm_time()
	# Per-kit-slot facts a brain cannot derive from `class_id` alone because they
	# move at runtime: can I actually throw this right now, and does it commit me to
	# an interruptible levitating channel (`cast_time > 0`) that any landed hit
	# shatters.
	#
	# ⚠ `slot_affordable` KEPT ITS NAME AND CHANGED ITS MEANING, deliberately. Mana no
	# longer gates a cast (see `_cast_signature`), so `mp >= mp_cost` was about to
	# become permanently true and the field would have quietly stopped carrying any
	# information at all — a blackboard key that always says yes is worse than no key,
	# because a brain keeps consulting it. It now means "this slot exists AND is off
	# cooldown", which is the question the old field was a proxy for, and it is the
	# answer that also stops a bot reaching for a slot its class does not have now
	# that kits are `SpellTier.SLOT_COUNT` spells and `BotIntent.SLOT_COUNT` is still five.
	var affordable: Array[bool] = []
	var cast_times: Array[float] = []
	for slot: int in BotIntent.SLOT_COUNT:
		var s: SpellDef = signature_at(slot)
		affordable.append(s != null and signature_ready(slot))
		cast_times.append(s.cast_time if s != null else 0.0)
	return {
		"self_id": get_instance_id(),
		"self_pos": global_position,
		"self_vel": velocity,
		"self_hp_frac": clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0),
		"self_mp_frac": clampf(mp / float(maxi(max_mp, 1)), 0.0, 1.0),
		"on_floor": is_on_floor(),
		"facing": signf(facing.x),
		"reach": _melee_range,
		"cooldowns": cds,
		"hostile_group": hostile_group,
		# WHICH CLASS I AM. Unlocks the kit facts, the role meanings and every
		# reaction combo for a brain that wants to look them up in SpellLibrary.
		# Fair: it is your own character, named on your own HUD.
		"class_id": _hero_class,
		# WHAT MY MOVEMENT BUTTON ACTUALLY DOES. `BotBrain` carries a hand-copied
		# `DASH_DIST = 86.8  # Hero.DASH_SPEED 620 * DASH_TIME 0.14` and its own header
		# admits those mirrors are copies that a retune must chase by hand. Nine verbs
		# with travels from ~84 px (arcane phase) to 260 px (lightning blink) make that copy
		# wrong for eight of nine classes, so the body publishes the DERIVED number and
		# the brain prefers it — the same "read it from the seam" fix `_ready_flag`
		# already applies to `dash_ready`.
		"dash_dist": movement_verb_distance(),
		# ...and whether spending it dodges anything, because two of the nine verbs
		# have no i-frames at all and a bot answering a telegraph with one is choosing
		# to be hit.
		"dash_iframes": movement_verb_iframe_fraction() > 0.0,
		"move_verb": movement_verb_name(),
		"slot_affordable": affordable,
		"slot_cast_time": cast_times,
		# The defensive verb, which differs in KIND and not just in numbers.
		#
		# ⚠ THIS PUBLISHED `_guard != null` — "do I hold a ring" — WHILE BotBrain READ
		# IT AS `ParryRing.Style` ("0 BLADE / 1 SIGIL"). The Swordsaint holds a BLADE
		# ring, so it published 1, so the brain charged it the SIGIL re-arm (0.55 s)
		# instead of the blade's (0.35 s) and a bot Swordsaint under-used its own
		# signature verb by 0.2 s every guard cycle. This is the same two-meanings-one-
		# field seam that once made 7 of 9 classes press the guard 0.374 s early; that
		# half was closed by publishing `guard_lead`/`guard_tolerance` in seconds, and
		# this is the half that was left.
		#
		# Now it publishes the ring's OWN style, with -1 for "no ring, a press window"
		# — a value the old encoding could not express at all, because both "press
		# window" and "BLADE ring" collapsed onto 0/1 of a two-value enum.
		"guard_style": _guard.style if _guard != null else -1,
		# ...and the re-arm in SECONDS, read off the ring rather than re-derived from
		# the style by a consumer that has to know the mapping. Same rule as
		# `dash_dist` and `guard_lead`: publish the number, not the category.
		"guard_rearm": _guard.rearm_time() if _guard != null else PARRY_COOLDOWN,
		# ⚠ HOW EARLY THE GUARD MUST BE PRESSED, IN SECONDS, AND HOW FAR OFF THAT A
		# PRESS MAY BE AND STILL CONNECT. Numbers, not a style enum — and that
		# distinction is the whole bug this closes.
		#
		# The two guard shapes are not two settings of one clock. A PRESS WINDOW opens
		# IMMEDIATELY and lasts `_parry_window_len` (0.16 s, or 0.40 s for the
		# Juggernaut's "block"). The BLADE RING opens its perfect band ~0.33 s AFTER the
		# press. `BotBrain` inferred the lead from `guard_style` — and read that field
		# with the OPPOSITE meaning to the one documented here (its header says
		# "0 BLADE / 1 SIGIL", this one says "0 = a press window"). So every
		# press-window class was treated as a shrinking ring and pressed 0.374 s early,
		# into a window that had lapsed 0.21 s before the blow arrived.
		#
		# MEASURED on real Hero scenes through the real `take_damage` path: 7 of 9
		# classes could not convert a reflex parry at ANY difficulty tier. Across 18
		# duels the brain committed 50 parries and landed ~3 — and 56 of 57 hits taken
		# within 3 s of a guard press arrived with the window already shut. The only
		# two classes that ever deflected were the Juggernaut (0.40 s window, wide
		# enough to catch the mistimed press) and the Swordsaint (an actual ring).
		"guard_lead": (ParryRing.SHRINK_TIME
			* (_guard.perfect_start() + ParryRing.PERFECT_END) * 0.5) if _guard != null
			else (_parry_window_len * 0.5),
		"guard_tolerance": (ParryRing.SHRINK_TIME
			* (ParryRing.PERFECT_END - _guard.perfect_start()) * 0.5) if _guard != null
			else (_parry_window_len * 0.5),
		"can_parry": bool(_cfg.get("can_parry", false)),
	}


# --- the six polling helpers every input call site in this file now goes through.
# With `controller == null` each one resolves to the IDENTICAL `Input` call it
# replaced — same order, same allocation, no branch reordering — which is the
# whole basis for claiming single player is unchanged. TouchControls also keeps
# working untouched, because it drives these same named actions through global
# `Input`, which is still exactly the null-controller path.

func _pressed(action: StringName) -> bool:
	return controller.pressed(action) if controller != null else Input.is_action_pressed(action)


func _just(action: StringName) -> bool:
	return controller.just_pressed(action) if controller != null \
		else Input.is_action_just_pressed(action)


func _released(action: StringName) -> bool:
	return controller.just_released(action) if controller != null \
		else Input.is_action_just_released(action)


func _axis(neg: StringName, pos: StringName) -> float:
	return controller.axis(neg, pos) if controller != null else Input.get_axis(neg, pos)


func _vector(nx: StringName, px: StringName, ny: StringName, py: StringName) -> Vector2:
	return controller.vector(nx, px, ny, py) if controller != null \
		else Input.get_vector(nx, px, ny, py)


## Replaces `get_global_mouse_position()`. A bot has no cursor, so its controller
## projects a point along the direction its brain chose — which is why this is a
## world POINT and not a direction: the placed spells (`_aoe_target`, the summon
## target) need real ground coordinates, and only the controller knows how far
## down the aim the bot meant.
func _aim_point() -> Vector2:
	# CO-OP REPLAY: a remote peer's cast carries the point its OWNER aimed at. A
	# puppet has no cursor and no brain, so without this every placed spell in the
	# replayed copy would land wherever THIS player's mouse happens to be.
	if _replaying:
		return _replay_point
	return controller.aim_point(global_position) if controller != null \
		else get_global_mouse_position()


## Live-tunable feel value: reads res://data/tuning.tres via the Tuning autoload,
## falling back to the const default if the autoload/field is absent or unset.
func _tune(key: String, fallback: float) -> float:
	if _tuning != null and _tuning.cfg != null:
		var v: Variant = _tuning.cfg.get(key)
		if v != null:
			return float(v)
	return fallback


## How much longer this spell's reuse timer runs than its authored `cooldown`.
##
## ⚠ APPLIED AT `start_cooldown`, NEVER TO `SpellDef.cooldown` ITSELF, and that is
## load-bearing rather than stylistic: `SpellTier.of()` DERIVES a spell's tier from
## its cooldown (`cooldown >= ULT_COOLDOWN`, 7.0). The heavies sit at 6.0-6.9, so
## scaling the stored value by 1.35 would push every one of them past that line,
## classify them all as ults, and then `slot_accepts_ult` would reject the very
## hands they belong to. The entire loadout system would reshuffle to buy a longer
## timer. Scaling the TIMER leaves the data, the tier and every pinned test alone.
##
## Quick and heavy carry the increase because they are what chain into a smear;
## ults are already 12-26 s and making the payoff rarer was never the ask.
func cooldown_mult_for(spell: SpellDef) -> float:
	if spell == null:
		return 1.0
	match SpellTier.of(spell):
		SpellTier.Tier.ULT:
			return maxf(_tune("cd_mult_ult", 1.0), 0.0)
		SpellTier.Tier.QUICK:
			return maxf(_tune("cd_mult_quick", 1.35), 0.0)
		_:
			return maxf(_tune("cd_mult_heavy", 1.35), 0.0)


## THE THREE SPELL BUTTONS MUST COVER THE WHOLE HAND. A kit that grew to four slots
## with three bound actions would leave slot 4 castable only through the demoted
## cycle key — silently, with a hotbar that draws it and a button that never reaches
## it. Shouted at boot rather than discovered in a playtest.
func _verify_spell_actions() -> void:
	if SPELL_ACTIONS.size() != SpellTier.SLOT_COUNT:
		push_error("Hero: %d spell buttons for %d kit slots — a slot is unreachable."
			% [SPELL_ACTIONS.size(), SpellTier.SLOT_COUNT])
	if SPELL_KEYS.size() != SPELL_ACTIONS.size():
		push_error("Hero: spell key labels and spell actions have drifted apart.")
	for a: StringName in SPELL_ACTIONS:
		if not InputMap.has_action(a):
			push_error("Hero: spell action '%s' is not in the input map." % a)


func _ready() -> void:
	_verify_spell_actions()
	_self_revive_left = maxi(DeathRules.SOLO_SELF_REVIVE_CHARGES, 0)
	add_to_group("hero")
	# FRIENDLY FIRE, the hero half. `mortal` is the shared "I am a damageable
	# fighter" group every spell scans once friendly fire is on (see
	# SpellCaster.MORTAL_GROUP); Enemy/Boss join it from their side.
	#
	# ADDED, never swapped. `hero` is identity and is scanned by ~40 places — the
	# camera's framing, the encounter's party-wipe check, enemy target selection,
	# Arena's spawn logic. Removing it to "clean up" would silently break all of
	# them, which is exactly the group-drift trap this codebase has been bitten by
	# twice already ("hero" the tower group vs "player" the old hub group).
	add_to_group(SpellCaster.MORTAL_GROUP)
	# Team membership, when a spawner set one before add_child(). The permanent
	# `hero` group above is identity ("I am a hero"); this one is allegiance, and a
	# hero with no team simply never joins a second group — which is single player.
	if faction_group != &"":
		add_to_group(faction_group)
	_tuning = get_node_or_null("/root/Tuning")
	hp = max_hp
	health_changed.emit(hp, max_hp)
	rig.set_tint(COLOURWAYS[_colourway])
	rig.set_aim_arm(true)  # twin-stick: the lead hand always aims at the cursor
	# Class comes from the co-op lobby (net_class) first, else GameState, else MAGE.
	_net = get_node_or_null("/root/Net")
	var gs: Node = get_node_or_null("/root/GameState")
	var start_class: int = HeroClass.MAGE
	if net_class >= 0:
		start_class = net_class
	elif gs != null:
		var sc: Variant = gs.get("selected_class")
		if sc != null:
			start_class = int(sc)
	# The colourway the player picked in the Outfitter, applied AT SPAWN.
	# It used to be replayed onto the hero the first time the pause menu opened,
	# so you played the whole first floor as the default palette and only became
	# yourself after pausing. Read before configure_class so the retint below
	# happens once, with the right colour, rather than twice.
	if gs != null:
		var cw: Variant = gs.get("colourway")
		if cw != null and int(cw) >= 0:
			_colourway = int(cw) % COLOURWAYS.size()
			rig.set_tint(COLOURWAYS[_colourway])
	# configure_class sets the class element, rig preset, weapon, AND the class's
	# signature loadout (SpellLibrary.build_for_class) + emits signature_changed.
	configure_class(start_class)  # also applies the hub Armory loadout (GameState.loadout)
	# LEVELS. Applied AFTER configure_class for the same reason the colourway is read
	# before it: `configure_class` re-seeds `_base_max_hp` from the class table and
	# calls `_recompute_gear_effects`, so Growth applied earlier would be overwritten
	# by the class config and the hero would spawn at level-1 stats regardless of level.
	refresh_growth()
	if gs != null and gs.has_signal(&"leveled_up") and not gs.is_connected(&"leveled_up", _on_leveled_up):
		gs.connect(&"leveled_up", _on_leveled_up)
	_setup_net_role()
	mp = float(max_mp)
	mana_changed.emit(mp, max_mp)
	# Rank drives aura TIER (elaborateness); the element keeps driving COLOUR.
	Rank.rank_changed.connect(_on_rank_changed)
	rig.set_aura_tier(Rank.tier())
	rig.hit_frame.connect(_on_melee_hit_frame)
	# Footfalls come off the RIG's own run cycle, not a timer here. The rig watches the
	# same phase expression the pose is drawn from, so the step can never drift off the
	# visible feet and retuning the stride moves the sound with it. `step_sfx` is off by
	# default because the same rig drives every enemy (eight of them ticking would be a
	# cacophony) — the HERO opts in. The parallel _footstep_timer that used to live in
	# _physics_process is GONE: two footstep clocks fighting each other sounded worse
	# than the original stacking bug.
	rig.step_sfx = true
	rig.foot_planted.connect(_on_foot_planted)
	# Floating HP + MP bars over the head.
	var bars := CharacterBars.new()
	add_child(bars)
	bars.configure(self, true, -26.0)


## Float-channel: the 4 big spectacles (beam/ray/meteor/convergence) become a
## committed levitating cast. Press G -> the hero lifts off + a build-up sigil
## grows for cast_time; if a hit lands the channel is INTERRUPTED (cast lost, mana
## + cooldown already spent). Survive it and the ultimate unleashes.
const CHANNEL_LIFT_HEIGHT: float = 34.0
const CHANNEL_LIFT_SPEED: float = 180.0
var _channeling: bool = false
var _channel_timer: float = 0.0
var _channel_total: float = 0.0
var _channel_spell: SpellDef = null
var _channel_target: Vector2 = Vector2.ZERO
var _channel_sky: bool = false
var _channel_lift: float = 0.0
var _channel_base_y: float = 0.0

## Epic SUMMON windup: every INSTANT signature (ice_wall / chain / rune_orbs /
## flurry / void_zone / tether / boulder / pillar / wall / rush / blink) blooms a
## spell-circle + a committed cast pose + gather motes for a short beat, THEN
## ERUPTS (maker: "ice is cringe — no spell circle, no summoning animation; they
## ALL need that for the G's ESPECIALLY"). Interruptible by a hit (ult lost, MP/cd
## spent — like the channel).
##
## The windup is no longer one length and one gesture for every spell: it comes
## from CastStyle (kind -> body language) scaled by SpellTier (how much the spell
## costs you). The two hand-tuned constants this replaces — a 0.42 s planted windup
## and a 0.22 s fast one for rush/blink — now fall out of the table instead of
## being special-cased: RUSH and BLINK_STRIKE are COIL poses, and COIL is 0.22 s
## precisely because mobility must not feel sticky.
const SUMMON_NORMAL: int = 0
const SUMMON_RUSH: int = 1
const SUMMON_BLINK: int = 2
## load()ed by path, never class_name: this file is compiled by headless tools
## that have no autoloads, and RiftDagger touches Sfx/Juice at parse time.
const RIFT_DAGGER_PATH: String = "res://scripts/combat/RiftDagger.gd"
var _summoning: bool = false
var _summon_timer: float = 0.0
var _summon_total: float = 0.0
var _summon_spell: SpellDef = null
var _summon_sky: bool = false
var _summon_special: int = 0
var _summon_aim: Vector2 = Vector2.RIGHT
var _summon_target: Vector2 = Vector2.ZERO
var _summon_pose: int = CastStyle.Pose.POINT
var _summon_tier: int = SpellTier.Tier.HEAVY
## Levitation bookkeeping for the windup. `_summon_lift` is a pure POSITION offset
## from the y we lifted off at — never a velocity — so it cannot fight the gravity
## integration in _physics_process, and _end_summon can always put the hero back on
## exactly the ground they left.
var _summon_lift: float = 0.0
var _summon_lift_target: float = 0.0
var _summon_base_y: float = 0.0
## spell.id -> the timestamp its name card was last shown at. Feeds
## SignatureRite's repeat-suppression rule; per-hero so co-op players do not share
## a clock. See _declare_signature.
var _last_declared: Dictionary = {}

## --- THE CASTING PROCESS (CastStyle + SpellTier) -----------------------------
## A cast is a PROCESS, not a spawn: the body winds up, a sigil opens, and only
## then does the spectacle exist. The length of that windup is the opponent's
## DODGE WINDOW (CastStyle's own rule), so these are balance numbers dressed as
## animation timings — which is why the windup has to gate the spawn rather than
## play alongside it.
##
## THE WINDUP LADDER NOW LIVES IN `SignatureRite.TIER_WINDUP`, and the length of
## any one cast comes from `SignatureRite.windup_for(spell)`. It moved because the
## windup is not private bookkeeping — it IS the opponent's dodge budget, and the
## rite has to be able to report that number for a caster that is not this file
## (a boss, the playground rig). One table, read from both sides, rather than two
## that drift.
## Slight levitation (px) held during the windup, indexed by SpellTier.Tier. QUICK
## never leaves the floor: the maker asked for "SLIGHT levitation when casting the
## MORE POWERFUL spells", and a kit where every jab hops reads floaty, not weighty.
## UNTESTED FEEL GUESS — this is the "is it a flourish or a jump" dial.
const CAST_TIER_LIFT: Array[float] = [0.0, 6.0, 11.0]
## How fast the lift eases in (px/s). Fast enough to be at full height inside even
## the shortest non-quick windup (LASH, 0.18 s), slow enough to read as gathering
## rather than popping. UNTESTED FEEL GUESS.
const CAST_LIFT_SPEED: float = 70.0
## How airborne the RIG is told it is at full lift (0..1). Not 1.0: the legs should
## dangle a little, not fully unweight like the float-channel does. UNTESTED.
const CAST_LIFT_AIRBORNE: float = 0.35
## The sigil hangs ABOVE the caster (maker: "the circle should sit ABOVE"). The rise
## is this much from the hero origin (which sits at the figure's MIDDLE, so ~24 px
## already clears the head) PLUS a share of the sigil's own radius — a bigger ring
## has to float HIGHER or it sinks back onto the caster, and "above" would only be
## true for the smallest spell. Not the full radius: a little overlap keeps the ring
## reading as attached to the caster rather than as scenery floating nearby.
##
## This offset is only authoritative WHILE the caster still owns the sigil. Once a
## spectacle claims it (see the hand-off seam below) the claimer is free to travel
## it down/forward to the muzzle, and this file stops touching its position at all.
## UNTESTED FEEL GUESSES.
const CAST_CIRCLE_ABOVE: float = 24.0
const CAST_CIRCLE_CLEARANCE: float = 0.9
## Windup-sigil radius: a base plus a part that scales with the spell's MP cost, so
## the ring's SIZE is how the picture says "this one is expensive".
##
## Deliberately small against the ~40 px figure. The numbers these replace (34 + 22,
## and 44 + 26 for the channel) were tuned for a sigil that sat at the caster's FEET
## as a ground aura; hung above the head at that size it drew a portal that
## swallowed the caster whole — visible in tools/cast_windup_capture.gd. The channel
## still runs bigger because it is the screen-filler ceremony. UNTESTED FEEL GUESSES.
const CAST_SIGIL_RADIUS: float = 17.0
const CAST_SIGIL_RADIUS_PER_COST: float = 11.0
const CHANNEL_SIGIL_RADIUS: float = 21.0
const CHANNEL_SIGIL_RADIUS_PER_COST: float = 13.0

## --- ONE SIGIL PER CAST: THE CASTER SIDE OF THE HAND-OFF ---------------------
## Maker, mid-playtest: "there should be no spells where I summon a circle, it goes
## away, and then another circle spawns which the spell comes out of."
##
## That bug is two independent spawners with no knowledge of each other: the caster
## opens a windup sigil and dismisses it, and then the spectacle opens its OWN
## muzzle sigil. The player watches the ritual visibly restart mid-cast.
##
## The protocol lives in MagicCircle.gd (read its hand-off block — it owns both
## halves). This file is only the CASTER side, which is two calls:
##
##     MagicCircle.offer(_cast_sigil, self)   # at the moment the spell fires
##     MagicCircle.withdraw(self)             # on ANY interruption
##
## Offering does not dismiss: the spectacle spawned on the same frame adopts the
## live node, reparents it and glides it to the muzzle with its spin and phase
## running on unbroken. An offer nobody takes blooms itself out after MagicCircle's
## own TTL, which is what most spells want — a wall or a nova opens no sigil of its
## own, so its offer is MEANT to go unclaimed and degrade to the old behaviour.
## `withdraw` is therefore belt-and-braces rather than load-bearing, but a shattered
## cast should not wait out a TTL to clear its ring.
##
## Because adoption happens in the SAME FRAME as the offer, offering must be the
## last thing that happens before SpellCaster.cast() — which is why _end_summon /
## _end_channel take a `handoff` flag rather than always doing one or the other.
##
## The live windup sigil, while the CASTER still owns it. One variable for both
## ceremonies (summon windup and float-channel) precisely so there is a single
## thing to hand over — and the beam case, which is the duplicate-circle bug the
## maker actually reported, goes through the channel.
var _cast_sigil: MagicCircle = null
## Rise above the hero origin for the CURRENT sigil, computed when it opens because
## it depends on that sigil's radius (see CAST_CIRCLE_CLEARANCE).
var _cast_sigil_rise: float = CAST_CIRCLE_ABOVE


## Open the windup sigil above the caster. `radius` scales with the spell's cost so
## the ring's SIZE carries how expensive the thing coming out of it is.
##
## Orientation is deliberately left FACE-ON — the maker asked for a circle sitting
## ABOVE the caster, and a summoning ring read head-on is what that picture is. An
## edge-on gate belongs at the MUZZLE, pointed down the shot, and that is the
## adopting spectacle's business: BeamSpell.adopt_or_open() passes edge_on and the
## sigil FOLDS into the gate as it travels down. Setting it edge-on here produced a
## tall vertical lens hanging over the head that read as a bug, not a ritual.
## ⚠ THE CIRCLE DRAWS THE SPELL, NOT THE CASTER. It used to draw `_element_color` —
## the hero's CLASS element — so an Arcanist charging a meteor watched a magenta
## arcane ring for the whole 1.1 s cast and it only snapped to fire at release.
## The maker's note was "meteor should be red and look slightly different"; the data
## was already right (every one of the 38 spells declares a correct element, and
## meteor is FIRE end to end) and this call site was throwing it away.
##
## `spell` is optional because the summon and channel paths both have it but a
## future caller might not; passing null keeps exactly the old behaviour.
func _open_cast_sigil(radius: float, grow_time: float, spell: SpellDef = null) -> void:
	_discard_cast_sigil()  # a cast can be interrupted but never queued — never stack two
	_cast_sigil_rise = CAST_CIRCLE_ABOVE + radius * CAST_CIRCLE_CLEARANCE
	var sigil := MagicCircle.new()
	get_parent().add_child(sigil)
	sigil.global_position = _cast_sigil_pos()
	var tint: Color = _element_color
	if spell != null:
		tint = spell.resolve_color(_element_color)
	sigil.appear(tint, radius, grow_time)
	# The glyph band and the tier ladder — the two things that make one circle
	# recognisable as a different spell from another at 640x360.
	if spell != null:
		sigil.set_signature(SpellCaster.resolve_element(spell), SpellTier.of(spell))
	_cast_sigil = sigil


## Offer the sigil to whichever spectacle is about to spawn. Deliberately does NOT
## vanish it — dismissing here is precisely the duplicate-circle bug. Hero drops its
## own reference immediately: from this instant the node belongs to the protocol,
## and this file must never move or rescale it again.
func _release_cast_sigil() -> void:
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		MagicCircle.offer(_cast_sigil, self)
	_cast_sigil = null


## Dismiss the sigil outright. For a cast that produces NO spectacle — an
## interrupted windup, a shattered channel — where there is nothing to hand it to.
## The withdraw() covers the narrow case of a cast that already offered and is then
## torn down before anything adopted; it is a no-op otherwise, so it is safe to call
## unconditionally.
func _discard_cast_sigil() -> void:
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		_cast_sigil.vanish(0.2)
	_cast_sigil = null
	MagicCircle.withdraw(self)


## Where the sigil hangs while the CASTER still owns it: clear above the head,
## tracking them upward as they levitate. Once offered, this file stops positioning
## it entirely so the adopting spectacle can travel it down to the muzzle.
func _cast_sigil_pos() -> Vector2:
	return global_position + Vector2(0.0, -_cast_sigil_rise)


## True when aim should auto-target (mobile): the TouchControls pad is active, or the
## device is a touchscreen. Cached DisplayServer call is cheap.
func _touch_aim() -> bool:
	return touch_input or DisplayServer.is_touchscreen_available()


func _physics_process(delta: float) -> void:
	# Co-op: you only drive YOUR hero. Remote heroes follow the synchronizer and
	# just animate (no Input, no move_and_slide).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		_remote_visual(delta)
		return
	# Co-op: downed = a limp ragdoll on the ground, no input/abilities, until the party
	# falls or clears the floor and everyone revives.
	if downed:
		_process_downed(delta)
		return
	# BOT: decide this frame's intent before anything reads input. Above the
	# cooldown ticks so the brain sees the same cooldowns the player's ability bar
	# showed at the end of last frame, and `delta` is the SCALED one every other
	# timer in this function uses — see `_bot_clock`.
	if controller != null:
		_bot_clock += delta
		controller.tick(self, _bot_clock)
	# ⚠ FOCUS IS APPLIED TO COOLDOWN **RECOVERY**, NOT TO COOLDOWN LENGTH, and that
	# is why it lands here rather than at the thirteen scattered assignment sites.
	# The spec's word for the axis is "cooldown recovery", so recovering faster is
	# the literal reading — and one hook on the decay covers every cooldown the class
	# has, including any added later, instead of thirteen edits that can drift apart.
	#
	# `_cd_delta` is `delta` at level 1, exactly, so an unlevelled hero ticks
	# byte-identically to before this line existed.
	var _cd_delta: float = delta * _growth_cd_recovery
	_dash_cooldown_timer = max(_dash_cooldown_timer - _cd_delta, 0.0)
	_cast_cooldown_timer = max(_cast_cooldown_timer - _cd_delta, 0.0)
	_melee_cooldown_timer = max(_melee_cooldown_timer - _cd_delta, 0.0)
	# ⚠ REAL TIME, NOT FOCUS-SCALED. This is the window a DECLARED swing has to reach
	# its own hit frame, and that frame is emitted by the rig's animation clock — which
	# does not know about cooldown-recovery growth. Ticking it at `_cd_delta` would let
	# a levelled hero's window expire before the animation it belongs to.
	_swing_window = maxf(_swing_window - delta, 0.0)
	_blast_cooldown_timer = max(_blast_cooldown_timer - _cd_delta, 0.0)
	_blink_cooldown_timer = maxf(_blink_cooldown_timer - _cd_delta, 0.0)
	_nova_cooldown_timer = maxf(_nova_cooldown_timer - _cd_delta, 0.0)
	_parry_cooldown_timer = maxf(_parry_cooldown_timer - _cd_delta, 0.0)
	# ⚠ THE TWO WINDOWS TICK AT REAL TIME, NOT AT FOCUS SPEED. An i-frame window and
	# a parry window are how long a DEFENCE LASTS — accelerating them would make a
	# levelled hero's dodge and parry SHORTER, i.e. FOCUS would make you worse at the
	# two things the game is hardest on. They are not cooldowns and must not ride the
	# cooldown dial.
	_blink_iframe_timer = maxf(_blink_iframe_timer - delta, 0.0)
	_parry_window_timer = maxf(_parry_window_timer - delta, 0.0)
	# The one movement-verb clock left, ticked with everything else: the Juggernaut's
	# post-surge armour tail. (The Arcanist's recall-anchor window used to tick here
	# too; the return leg it gated is gone.)
	_surge_armor_timer = maxf(_surge_armor_timer - delta, 0.0)
	# The BLADE ring is ticked HERE, above the channel/summon early-returns, so its
	# re-arm keeps running while the hero is committed to something else. A guard
	# whose recovery paused whenever you were busy would silently re-arm instantly
	# after every cast.
	if _guard != null:
		_guard.tick(delta)
	# Every kit slot recovers independently, and they all recover WHILE you are
	# committed to something else — same reasoning as the guard ring above.
	_hand.tick(delta)
	# The global gap between spells recovers on the same clock as the per-slot banks
	# — scaled delta — so a hit-stop stretches all of them together rather than
	# letting the lockout expire inside a freeze the cooldowns sat through.
	_cast_lockout = maxf(_cast_lockout - delta, 0.0)
	# ...and so does the input buffer, for the same reason: a press queued a moment
	# before a channel started must not be sitting there when the channel ends.
	_age_input_buffer(delta)
	# THE WINDUP IS NOT A DEAD BEAT. Recording presses HERE — above the channel and
	# summon early-returns — is what lets you queue the next move while a spell is
	# still blooming, so the instant it resolves the dash or the follow-up spell is
	# already coming out. It used to sit below those returns, which meant every press
	# made during a windup was silently thrown away: the most committed, most
	# expressive moment in the game was also the one where the buttons stopped
	# answering. The commitment itself is untouched — a windup still cannot be
	# cancelled, it just no longer eats the press that comes after it.
	_update_input_buffer(delta)
	_tick_ready_pulse(delta)
	_wall_jump_lock = maxf(_wall_jump_lock - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_update_flaming_fist(delta)
	# Mana regenerates every frame (even mid-dash) so ultimates stay paced.
	if mp < float(max_mp):
		mp = minf(mp + MP_REGEN * delta, float(max_mp))
		mana_changed.emit(mp, max_mp)
	# FLOAT-CHANNEL: while casting a big spectacle the hero levitates + is fully
	# committed (no movement/input) until the cast fires or a hit interrupts it.
	if _channeling:
		_process_channel(delta)
		return
	# SUMMON WINDUP: while the spell circle blooms the hero is committed (grounded,
	# no movement/input) until it erupts or a hit interrupts it.
	if _summoning:
		_process_summon(delta)
		return
	# Landing dust: white puff the instant we touch down after being airborne (not
	# while gliding). At the top so it fires even on dash frames. is_on_floor()
	# here reflects the previous frame's move_and_slide.
	if is_on_floor() and not _was_on_floor:
		_spawn_foot_puff()
		Juice.shake_camera(2.5)  # a little land thud (Stick-Fight juice)
	_was_on_floor = is_on_floor()
	# Aim resolution. LOCKED RULE: no auto-aim, no homing — on EVERY platform the aim
	# is the direction the player is actually pointing, and landing a spell is their
	# skill, not the game's. On desktop that's the cursor, tracked every frame so
	# casts / cast-pose / camera peek use it even mid-dash.
	# On MOBILE there is no cursor, so the aim is the RIGHT THUMB STICK'S own direction
	# (the `aim_*` actions, published by TouchControls). It used to snap to the nearest
	# enemy here, which quietly handed the phone player a targeting computer the desktop
	# player is denied — exactly the auto-aim the rule forbids.
	#
	# It then briefly read the MOVE stick, which was worse than it looked: that layer
	# published no upward component at all, so a touch player could not aim above the
	# horizon at anything, ever. Aim now has its own stick and its own actions, fully
	# decoupled from movement (pushing move-down ducks you; it does not aim at the
	# floor). A released thumb HOLDS the last aim rather than resetting to a default,
	# so letting go to tap an ability button doesn't fling the shot somewhere else.
	#
	# The stick is checked BEFORE the platform test on purpose: any device that can
	# push `aim_*` past the deadzone (touch pad, a gamepad's right stick, the IJKL
	# keyboard fallback) steers the aim, and the mouse only takes over when the stick
	# is at rest. That keeps one code path for every input device instead of three.
	#
	# A CONTROLLER WINS OVER BOTH. It is checked first and returns before the stick
	# and the cursor are consulted, because both of those read PROCESS-GLOBAL state:
	# a bot sharing a machine with a player would otherwise inherit the human's
	# thumbstick and the human's cursor as its own aim. The same "hold the last aim
	# rather than snap to a default" rule applies, so a brain that declines to aim
	# on a frame keeps pointing where it was.
	if controller != null:
		var to_aim: Vector2 = _aim_point() - global_position
		if to_aim.length() > 1.0:
			_aim_dir = to_aim.normalized()
	else:
		var aim_stick: Vector2 = Vector2(
			Input.get_action_strength("aim_right") - Input.get_action_strength("aim_left"),
			Input.get_action_strength("aim_down") - Input.get_action_strength("aim_up")
		)
		if aim_stick.length() > TOUCH_AIM_DEADZONE:
			_aim_dir = aim_stick.normalized()
		elif not _touch_aim():
			var to_mouse: Vector2 = get_global_mouse_position() - global_position
			if to_mouse.length() > 1.0:
				_aim_dir = to_mouse.normalized()
	# AIM ASSIST, applied ONCE at the source. Bending here rather than per-cast
	# means the rig's aim arm, the melee arc, the camera peek and every spell all
	# agree — what you SEE the figure pointing at is where the shot goes. Inert at
	# the shipping default of 0 (see SpellTargets.assist_aim).
	_apply_aim_assist()
	facing = _aim_dir
	# Feed groundedness to the rig so a limp (hold-DOWN) ragdoll clamps to the floor
	# instead of drooping through it. Set every frame; cheap.
	rig.set_grounded(is_on_floor())
	# Hold DOWN to go LIMP — the Stick-Fight ragdoll flop. Abilities + walking are
	# suspended; the active-ragdoll rig droops and gravity/friction bring you to the
	# ground. Release to snap back up.
	if _pressed(&"move_down") and not is_dashing:
		if not _ragdolling:
			_ragdolling = true
			rig.set_limp(1.0)
			rig.apply_impulse(Vector2(0.0, 1.0), 220.0)  # a little flop-down kick
		# Same offset rule as the main locomotion path — see `_knockback_applied`.
		# The flop branch reached `move_and_slide` without ever stripping last frame's
		# shove, so holding DOWN while knocked back integrated it exactly as the main
		# path did.
		_knockback_applied = _knockback.x
		# ⚠ YOU CAN CRAWL. Maker: "if I am holding down and right it should be crawling
		# on the ground in that direction — right now it doesn't crawl, it just stays
		# down." The limp branch used to drive velocity.x toward ZERO unconditionally,
		# so a flopped body was not merely slow, it was nailed down: holding a direction
		# did nothing at all, which reads as the ragdoll being broken rather than as a
		# deliberate cost.
		#
		# CRAWL_SPEED is a fraction of the walk, so going limp is still a real trade —
		# you give up almost all of your speed, your abilities and your guard, and you
		# keep just enough authority to drag yourself somewhere.
		var crawl: float = _axis(&"move_left", &"move_right") * CRAWL_SPEED
		velocity.x = move_toward(velocity.x - _knockback_applied, crawl,
			GROUND_FRICTION * delta) + _knockback_applied
		if absf(crawl) > 1.0:
			rig.set_facing(Vector2(signf(crawl), 0.0))
		velocity.y = 0.0 if (is_on_floor() and velocity.y >= 0.0) else minf(velocity.y + GRAVITY_FALL * delta, MAX_FALL)
		move_and_slide()
		rig.play(CharacterRig.State.HURT)
		rig.set_body_velocity(velocity)
		return
	elif _ragdolling:
		_ragdolling = false
		rig.set_limp(0.0)
	# Cosmetic + class toggles: instant, un-buffered, legal even mid-dash.
	if _just(&"cycle_element"):
		_cycle_element()
	if _just(&"cycle_colourway"):
		_cycle_colourway()
	if _just(&"switch_class"):
		_cycle_class()
	if _just(&"cycle_signature"):
		_cycle_signature()
	# THE DEFENSIVE VERB. Two shapes behind one button: eight classes press for a
	# fixed window, the Swordsaint HOLDS a shrinking ring. `_guard != null` is the
	# only switch, so nothing about the press path changed for anyone else.
	if _guard != null:
		_process_blade_guard(delta)
	elif _just(&"parry") and not is_dashing:
		_try_parry_start()
	# GUARDING LOCKS OUT ATTACKING — ParryRing's own rule, and a balance one rather
	# than a UI limitation: a sustained guard that cost nothing offensively would be
	# a permanent free damage reduction. It also removes the platform asymmetry where
	# a desktop player could hold guard and swing but a thumb cannot.
	var guard_locked: bool = _guard != null and _guard.blocks_attack()
	# `ultimate` = "throw whatever is SELECTED", and it is what a BOT pulls after
	# choosing a slot by index (see SPELL_ACTIONS). Unbuffered on purpose: a bot
	# re-decides its whole intent every physics tick, so a queued press would fire a
	# decision it had already changed its mind about. The three PLAYER spell buttons
	# go through the buffer instead — `_try_fire_buffered_spell`.
	if _just(&"ultimate") and not is_dashing and not guard_locked:
		_cast_signature()
	if _pressed(&"cast") and _cast_cooldown_timer <= 0.0 and not is_dashing \
			and not guard_locked:
		_cast()

	if is_dashing:
		_dash_timer -= delta
		# THE SEVEN TRAVEL VERBS, one branch. `_travel_velocity` is the only thing that
		# differs per class inside the loop — everything below it (the strike sweep,
		# the afterimages, the exit puff, the rig feed) is shared, which is why a new
		# verb is a case there rather than a second copy of this block.
		velocity = _travel_velocity(delta)
		move_and_slide()
		if _cfg["dash_strike"]:
			_dash_strike_sweep()  # rogue: dash deals melee damage through enemies
		if _dash_verb == "radiant_step":
			# CLERIC: drop healing pulses along the path (allies only).
			_radiant_wake_timer -= delta
			if _radiant_wake_timer <= 0.0:
				_radiant_wake_timer = RADIANT_WAKE_INTERVAL
				_radiant_wake_pulse()
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			rig.spawn_ghost(get_parent(), _travel_ghost_color(), _dash_dir)
		if _dash_timer <= 0.0:
			is_dashing = false
			_end_travel()
			# Skid-to-a-stop dust puff — the "come down to the ground" kick-up.
			CombatVfx.spawn_burst(
				get_parent(), global_position,
				Color(0.82, 0.82, 0.88, 0.6), Color(0.82, 0.82, 0.88, 0.0),
				8, 0.25, 30.0, 95.0
			)
		rig.play(CharacterRig.State.DASH)
		rig.set_facing(_dash_dir)  # body faces where the dash is going
		# The dash branch returns early, so the rig used to spend the whole burst on a
		# stale velocity: no inertial limb trail, and (since the body springs landed)
		# no way to tell a horizontal dash from a vertical one. Feeding it here gives
		# the rig the dash's true DIRECTION, which is what SpikeFigure leans off
		# (`lean = _dash_dir.x * DASH_LEAN` — a straight-up dash does not pitch).
		rig.set_body_velocity(velocity)
		return

	# --- Side-on movement: horizontal input, gravity, jumping ---
	var move_x: float = _axis(&"move_left", &"move_right")
	# A HELD BLADE GUARD ROOTS YOU. The blade is planted, not carried, and that is
	# what makes walking away the clean counter to it: an opponent who simply
	# declines to swing beats the guard outright, and the Swordsaint has spent the
	# hold for nothing. Rooting is also what keeps the bank honest — you cannot chase
	# someone down while holding a loaded return.
	if _guard != null and _guard.blocks_attack():
		move_x = 0.0
		_jump_buffer = 0.0
	if move_x != 0.0:
		_move_dir = Vector2(signf(move_x), 0.0)  # dash/blink dodge direction
	if _just(&"jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	if _try_fire_buffered():
		# A dash started (the dash branch owns movement now), or a spell committed to a
		# channel/summon that owns the body until it resolves.
		return

	# Coyote window + air-jump refill while grounded (per-class: Brawler double-jumps).
	if is_on_floor():
		_coyote = COYOTE_TIME
		_air_jumps = _max_air_jumps
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	# --- Wall-slide: gripping a wall while falling INTO it (is_on_wall_only so a
	# grounded corner never counts). get_wall_normal points AWAY from the wall. ---
	var wall_normal: Vector2 = get_wall_normal()
	var pushing_into_wall: bool = move_x != 0.0 and is_on_wall_only() \
			and signf(move_x) == -signf(wall_normal.x)
	var wall_sliding: bool = is_on_wall_only() and velocity.y > 0.0 and pushing_into_wall

	# Vertical: asymmetric gravity (floaty apex, weighty fall); wall-slide clamps it.
	if is_on_floor() and velocity.y >= 0.0:
		velocity.y = 0.0  # guard: an upward knockback pop must beat the floor-zero
	else:
		var g: float = _tune("move_gravity_rise", GRAVITY) if velocity.y < 0.0 else _tune("move_gravity_fall", GRAVITY_FALL)
		velocity.y = minf(velocity.y + g * delta, _tune("move_max_fall", MAX_FALL))
		if wall_sliding:
			velocity.y = minf(velocity.y, WALL_SLIDE_MAX_FALL)
	# Variable jump height: releasing jump while rising cuts the ascent short.
	if _released(&"jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	# Jump (buffered): ground/coyote, else a WALL-JUMP off a gripped wall.
	if _jump_buffer > 0.0:
		if is_on_floor() or _coyote > 0.0:
			velocity.y = _tune("move_jump_velocity", JUMP_VELOCITY)
			_jump_buffer = 0.0
			_coyote = 0.0
			_spawn_foot_puff()
		elif is_on_wall_only():
			# Kick away from the wall + up; a slide-then-jump gets a speed boost.
			var boost: float = SLIDE_JUMP_BOOST if _was_wall_sliding else 1.0
			velocity.x = wall_normal.x * WALL_JUMP_PUSH * boost
			velocity.y = WALL_JUMP_UP
			_wall_jump_lock = WALL_JUMP_LOCKOUT
			_jump_buffer = 0.0
			_spawn_foot_puff()
		elif _air_jumps > 0:
			# Air (double) jump — classes with air_jumps > 0 (Brawler). A puff + a
			# quick flip-flourish sells the mid-air kick.
			velocity.y = DOUBLE_JUMP_VELOCITY
			_air_jumps -= 1
			_jump_buffer = 0.0
			_spawn_foot_puff()

	# Horizontal: accel toward input, friction to a stop. The wall-jump lockout
	# briefly preserves the kick-off so it can't be cancelled back into the wall.
	# gear: hood = fleet-footed. `_status_speed_mult` is the ailment half — a chilled
	# or shocked hero moves like one now that heroes can actually catch ailments.
	var spd: float = _class_speed() * _gear_speed_mult * _status_speed_mult()
	# ...and the same ailment, published to the rig so it is DRAWN as well as felt.
	_push_status_to_rig()
	# THE SHOVE IS AN OFFSET, NOT AN ACCELERATION — see `_knockback_applied`. Strip
	# last frame's offset before locomotion reads this, or the decaying channel gets
	# integrated into velocity and a 240 px/s shove peaks at 1429 (6x), or 7676 (32x)
	# while hitstop is holding time_scale down.
	var walk_x: float = velocity.x - _knockback_applied
	if is_on_wall():
		# `move_and_slide` is authoritative about a body against a wall; resurrecting
		# the pre-collision intent would push it back through.
		walk_x = 0.0
	if _wall_jump_lock <= 0.0:
		# `grav_fields > 0` reads as GROUNDED for STEERING ONLY — see the counter on
		# `grav_fields`. Deliberately NOT folded into `is_on_floor()`: everything else
		# that branch drives (jump, coyote refill, landing dust, the rig's grounded
		# pose) must keep answering "no floor", because there is no floor.
		var planted: bool = is_on_floor() or grav_fields > 0
		if move_x != 0.0:
			var accel: float = GROUND_ACCEL if planted else _tune("move_air_accel", AIR_ACCEL)
			walk_x = move_toward(walk_x, move_x * spd, accel * delta)
		else:
			var fric: float = GROUND_FRICTION if planted else _tune("move_air_accel", AIR_ACCEL)
			walk_x = move_toward(walk_x, 0.0, fric * delta)
	# Tiny push into the wall so move_and_slide keeps registering the slide.
	if wall_sliding:
		walk_x = -wall_normal.x * WALL_STICK_PUSH
	_knockback_applied = _knockback.x
	velocity.x = walk_x + _knockback_applied  # ragdoll shove from an enemy hit / bomb
	move_and_slide()
	_check_wall_slam()  # crack a breakable we were slammed into
	_was_wall_sliding = wall_sliding
	rig.set_body_velocity(velocity)  # ragdoll: limbs trail when you launch/stop

	# Rig: a distinct WALL-SLIDE cling (so you read as ON the wall) with friction
	# dust; otherwise run/idle with grounded footsteps.
	if wall_sliding:
		rig.play(CharacterRig.State.WALL_SLIDE)
		rig.set_facing(Vector2(-wall_normal.x, 0.0))  # turn to face the wall
		_wall_dust_timer -= delta
		if _wall_dust_timer <= 0.0:
			_wall_dust_timer = 0.09
			CombatVfx.spawn_burst(
				get_parent(), global_position + Vector2(-wall_normal.x * 9.0, 8.0),
				Color(0.85, 0.85, 0.9, 0.6), Color(0.85, 0.85, 0.9, 0.0),
				5, 0.25, 20.0, 70.0
			)
		rig.set_aim(_aim_dir)
		return
	var moving: bool = absf(move_x) > 0.01
	# Airborne: drive the loose-air ragdoll regime (NO canned jump pose — the limbs
	# trail/flail via _step_sim's air looseness). Grounded: settle into RUN/IDLE with
	# the foot-plant. rising = velocity.y < 0.0 (ascending) biases the looseness only.
	if not is_on_floor():
		rig.play(CharacterRig.State.AIR)
		rig.set_air_phase(velocity.y < 0.0, is_on_floor())
	else:
		rig.play(CharacterRig.State.RUN if moving else CharacterRig.State.IDLE)
	# NOTE: no footstep/dust block here any more. Both are driven by the rig's
	# `foot_planted` signal (see _on_foot_planted) so the crunch and the puff land on
	# the frame the foot visibly hits the ground, instead of on a timer that slowly
	# slid out of phase with the animation.
	# Stick-Fight decouple: the BODY faces MOVEMENT (idle keeps the last facing —
	# set_facing ignores x==0); the cast arm/weapon aims at the true cursor. The
	# figure is FACELESS (no eyes) — aim reads from the body + the pointed weapon +
	# the parry shield, the Stick-Fight way. During a melee strike the body turns
	# to the aim so the punch points at the target.
	if rig.is_striking():
		rig.set_facing(_aim_dir)
	else:
		rig.set_facing(Vector2(move_x, 0.0))
	rig.set_aim(_aim_dir)


## Age the buffer. Split out from `_update_input_buffer` and ticked with the cooldown
## timers at the TOP of the frame, ABOVE the channel/summon early-returns — otherwise
## a buffered press froze for the whole of a levitating cast and then fired on the
## frame it ended, seconds after the player let go of the button.
##
## ⚠ THE TIMER DECAYS ON SCALED DELTA, which is deliberate and worth stating: during
## a `Juice.hit_stop` the whole game runs at `time_scale = 0.05`, so a 0.22 s buffer
## becomes ~4 seconds of WALL time. A press made during the freeze therefore survives
## the freeze, which is exactly what you want — the hit-stop is a punctuation mark,
## not a window where your buttons stop working.
func _age_input_buffer(delta: float) -> void:
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	if _buffer_timer <= 0.0:
		_buffered_action = ""
		_buffer_from_hold = false


## Record melee/dash/blast/spell presses into the single-slot buffer (newest press
## wins).
func _update_input_buffer(_delta: float) -> void:
	for action: StringName in BUFFERED_ACTIONS:
		if _just(action):
			_latch_buffer(String(action), BUFFER_TIME, false)
	# ⚠ SPELLS DO NOT QUEUE DURING A CAST — and MOVEMENT STILL DOES, which is the
	# whole point of the split. The loop above (melee/dash/blast) is untouched.
	#
	# The buffer's own rationale is sound and is preserved: a press must not be
	# "silently thrown away" at the most committed moment in the game. But applying
	# it to SPELLS meant a press made mid-windup fired on the exact frame the windup
	# ended, so two spectacles landed with no gap — the maker's "back to back
	# effects". Queuing a DASH out of a cast is expressive; queuing the next spell
	# is just holding the button down and watching.
	#
	# So during a windup the spell buttons stop latching. You may still dash, still
	# swing, still blast the instant the cast lets go.
	if _channeling or _summoning:
		return
	# THE THREE SPELL BUTTONS. A press latches; a HELD button re-latches once the
	# buffer has been spent, which is what makes holding one repeat-cast the moment
	# the slot comes back instead of sitting there doing nothing. A fresh press of a
	# DIFFERENT button always wins over a hold, because the hold branch only fills an
	# empty buffer.
	for i: int in SPELL_ACTIONS.size():
		var action: StringName = SPELL_ACTIONS[i]
		if _just(action):
			_latch_buffer(spell_buffer_key(i), SPELL_BUFFER_TIME, false)
		elif _buffered_action.is_empty() and _pressed(action):
			_latch_buffer(spell_buffer_key(i), SPELL_BUFFER_TIME, true)


## The buffer's encoding of "the player asked for kit slot `i`". Static + public so
## the tests pin the same string the hero writes rather than re-deriving it.
static func spell_buffer_key(slot: int) -> String:
	return SPELL_BUFFER_PREFIX + str(slot)


## Which kit slot a buffered entry refers to, or -1 when it is not a spell entry.
static func spell_buffer_slot(entry: String) -> int:
	if not entry.begins_with(SPELL_BUFFER_PREFIX):
		return -1
	return int(entry.substr(SPELL_BUFFER_PREFIX.length()))


func _latch_buffer(entry: String, window: float, from_hold: bool) -> void:
	_buffered_action = entry
	_buffer_timer = window
	_buffer_from_hold = from_hold


## THE PRESS THAT FALLS BETWEEN TWO PHYSICS FRAMES.
##
## Every gate in this file is polled from `_physics_process`, and `Juice.hit_stop`
## drops `Engine.time_scale` to 0.05 — so a 0.06 s hit-stop is ~0.003 s of GAME time
## and the physics step simply does not run during it. A tap that starts AND ends
## inside that window is never seen by a physics-frame poll: the button did nothing,
## at the single most action-packed moment in the game. That is not a theory about
## the engine, it is the arithmetic of a fixed-timestep loop under a time scale.
##
## `_process` runs once per RENDERED frame regardless of `time_scale`, so latching
## the same edges here catches those taps and shaves up to a physics frame (~16 ms)
## off every other press. The buffer is idempotent — the physics poll re-latching the
## same entry a frame later is a no-op — so the two paths cannot double-fire.
##
## ⚠ HUMAN PATH ONLY. A bot's edges live on its `BotController`, which is advanced
## once per PHYSICS tick inside `controller.tick()`; polling it from a render frame
## would read the same intent two, three, four times and hand bots extra presses.
## `controller != null` is the same seam test every input call in this file uses.
func _process(_delta: float) -> void:
	# Publish FIRST, above every early return. A downed hero and a bot-driven hero
	# both still have to be drawn correctly on the other phone — the returns below
	# are about reading INPUT, which is a different question.
	if _net != null and _net.is_active() and is_multiplayer_authority():
		_publish_net_state()
	if controller != null or downed:
		return
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		return
	for action: StringName in BUFFERED_ACTIONS:
		if Input.is_action_just_pressed(action):
			_latch_buffer(String(action), BUFFER_TIME, false)
	for i: int in SPELL_ACTIONS.size():
		if Input.is_action_just_pressed(SPELL_ACTIONS[i]):
			_latch_buffer(spell_buffer_key(i), SPELL_BUFFER_TIME, false)


## Fire the buffered action if its gate is now open, consuming the buffer so
## nothing double-fires. Only called from the not-dashing path, so the old
## `not is_dashing` gates are implicit. Returns true when the CALLER MUST YIELD the
## rest of the frame — a dash started, or a spell committed to a channel/summon that
## has already zeroed the velocity and set the cast pose.
func _try_fire_buffered() -> bool:
	if _buffered_action.is_empty():
		return false
	# A held BLADE guard locks out the offence (ParryRing.blocks_attack). The press
	# is deliberately NOT dropped, only held: the buffer already exists so a press
	# through a closed gate fires the moment the gate opens, and that is exactly the
	# right feel here — let go of guard and the swing you asked for comes out.
	if _guard != null and _guard.blocks_attack():
		return false
	match _buffered_action:
		"melee":
			if _melee_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_melee()
		"blast":
			if _blast_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_blast()
		"dash":
			# ONE GATE, FOR ALL NINE VERBS. This used to read `or _recall_pending()` —
			# the Arcanist's return leg being waved through a cooldown its own outbound
			# leg had just spent, on the grounds that a recall was a SECOND DECISION
			# rather than a continuation. With the return leg deleted the movement button
			# is one press with one cost again, and that exception would be a hole with
			# nothing left to walk through it.
			if _dash_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_start_dash()
				return true
		"blink":
			if _blink_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_blink()
		"nova":
			if _nova_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_nova()
		_:
			return _try_fire_buffered_spell()
	return false


## The buffered half of the spell buttons.
##
## Returns true when the cast committed to a channel/summon, because those set
## `velocity = Vector2.ZERO` and a committed cast pose, and the movement block below
## the caller would spend the rest of the frame re-accelerating the body and stomping
## the pose back to RUN/IDLE. One frame, but it is the FIRST frame of the cast — the
## one the whole "casting must feel incredible" ceremony opens on.
func _try_fire_buffered_spell() -> bool:
	var slot: int = spell_buffer_slot(_buffered_action)
	if slot < 0 or slot >= _signatures.size():
		return false
	# A HELD button waits for the slot to actually recover. A fresh PRESS may also
	# take the Rift Dagger's free RECALL beat, which lives above the cooldown gate in
	# `_cast_signature` — holding the button through a throw must not instantly yank
	# the dagger back, because recall is a second decision and not a continuation.
	if not signature_ready(slot) and (_buffer_from_hold or not _slot_recall_pending(slot)):
		return false
	_clear_input_buffer()
	cast_signature_slot(slot)
	return _channeling or _summoning


## True when slot `i` holds a live thrown anchor, so the next press means RECALL and
## is free rather than blocked by the throw's own cooldown. Mirrors the same query
## `_signature_hud_slot` makes to draw "RECALL" on the bar — one rule, two readers.
func _slot_recall_pending(i: int) -> bool:
	var sig: SpellDef = signature_at(i)
	if sig == null or sig.kind != SpellDef.Kind.THROWN_ANCHOR:
		return false
	return (load(RIFT_DAGGER_PATH) as GDScript).find_anchor(get_tree(), self) != null


func _clear_input_buffer() -> void:
	_buffered_action = ""
	_buffer_timer = 0.0
	_buffer_from_hold = false


## Advance to the next element (wraps) and re-apply aura + ability colour.
func _cycle_element() -> void:
	_element = (_element + 1) % Elements.count()
	_apply_element()


## Element = aura + ability colour. The aura recolours instantly (the colour
## change IS the feedback); _element_color feeds every subsequent cast.
func _apply_element() -> void:
	_element_color = Elements.color(_element)
	rig.set_aura(_element_color, AURA_STRENGTH)


## Rank-up: the aura escalates a tier (more layers/motes/ring) plus a quick
## element-coloured pop on the figure. No menus — this IS the feedback.
func _on_rank_changed(new_tier: int, _title: String) -> void:
	rig.set_aura_tier(new_tier)
	rig.flash_color(_element_color, 0.18)


## Advance to the next body colourway (wraps) and retint the rig limbs.
## Purely cosmetic — independent of the element.
func _cycle_colourway() -> void:
	_colourway = (_colourway + 1) % COLOURWAYS.size()
	rig.set_tint(COLOURWAYS[_colourway])


## Configure the hero for a class: rig preset + weapon + per-class ability
## tuning (_cfg). Called at _ready and on the debug switch. Clears cooldowns +
## buffer so a mid-fight swap can't double-fire.
func configure_class(cls: int) -> void:
	_hero_class = cls
	_cfg = CLASS_CONFIG[cls]
	rig.class_preset(_cfg["preset"])
	if String(_cfg["weapon"]) != "":
		equip_weapon(String(_cfg["weapon"]))  # rogue: sword overlay + melee retune
	else:
		# Mage: keep the preset's staff overlay; melee falls back to fists stats.
		_weapon = "fists"
		_melee_damage = MELEE_DAMAGE
		_melee_range = MELEE_RANGE
		_melee_knockback = MELEE_KNOCKBACK
	# Per-class melee tuning (cadence + arc width + optional stat overrides) so a
	# Brawler jabs fast/narrow and a Juggernaut swings slow/wide/hard.
	_melee_cd = float(_cfg.get("melee_cd", MELEE_COOLDOWN))
	_melee_arc_dot = float(_cfg.get("melee_arc_dot", MELEE_ARC_DOT))
	if _cfg.has("melee_damage"):
		_melee_damage = int(_cfg["melee_damage"])
	if _cfg.has("melee_range"):
		_melee_range = float(_cfg["melee_range"])
	if _cfg.has("melee_knockback"):
		_melee_knockback = float(_cfg["melee_knockback"])
	_dash_cooldown_timer = 0.0
	_cast_cooldown_timer = 0.0
	_blink_cooldown_timer = 0.0
	_blast_cooldown_timer = 0.0
	_nova_cooldown_timer = 0.0
	_parry_window_timer = 0.0
	_parry_cooldown_timer = 0.0
	# Movement-verb state, cleared for exactly the reason every other timer here is:
	# Tab swaps classes live, and a surge armour tail that survived the swap would be
	# the previous class's ability still running on this one. (The recall anchor was
	# cleared here too until the return leg was removed — the Arcane Phase carries no
	# state across a swap because it carries none at all.)
	_surge_armor_timer = 0.0
	_dash_verb = String(_cfg.get("move_verb", "dash"))
	_dash_speed = DASH_SPEED
	_dash_total = DASH_TIME
	_clear_input_buffer()
	# Per-class movement identity: air (double) jumps refill count.
	_max_air_jumps = int(_cfg.get("air_jumps", 0))
	_air_jumps = _max_air_jumps
	# Juggernaut BLOCK = a longer, more forgiving defensive window than a parry.
	var defense: String = String(_cfg.get("defense", "parry"))
	_parry_window_len = 0.40 if defense == "block" else PARRY_WINDOW
	# HELD GUARD: swap the press-window parry for ParryRing's BLADE style. Rebuilt
	# (not merely reset) on every class change so a ring can never survive a swap
	# half-held — a stuck `held` would silently lock the next class out of attacking.
	_guard = ParryRing.for_style(ParryRing.Style.BLADE) if defense == "held_guard" else null
	_guard_bank = 0
	_guard_hits = 0
	# Auto-set the class's signature element (X still cycles from here) + swap in
	# the class's themed signature loadout (its hero-fantasy ultimate first).
	if _cfg.has("element"):
		_element = int(_cfg["element"])
		_apply_element()
	_signatures = SpellLibrary.build_for_class(cls)
	_signature_index = 0
	# Rebuild the cooldown bank FROM the new kit, which also clears every timer. A
	# per-slot bank makes this load-bearing in a way the old single float was not: a
	# leftover timer would otherwise lock a slot of a class the player has never cast
	# with, and Tab swaps classes live.
	_hand.rebuild([], _signatures)
	if not _signatures.is_empty():
		signature_changed.emit(_signatures[_signature_index].display_name)
	# Snapshot the fully-tuned class base (post equip_weapon) so gear mults scale from
	# it idempotently, then apply any loadout overrides' abilities.
	_base_melee_damage = _melee_damage
	_base_melee_knockback = _melee_knockback
	_base_melee_cd = _melee_cd
	# THE CLASS'S OWN HEALTH, and the one line that makes it compose with gear instead
	# of being clobbered by it. `_recompute_gear_effects` (called at the bottom of this
	# function) scales `max_hp` off `_base_max_hp` idempotently — so seeding the BASE
	# from the class table means the hat MULTIPLIES the class number and re-running a
	# loadout swap can never compound. Seeding `max_hp` itself instead would have been
	# the bug: the next gear recompute would scale an already-scaled value.
	#
	# ⚠ A SPAWNER THAT IMPOSES ITS OWN POOL STILL WINS, and must still write AFTER this
	# call — which every one of them already does (BotMatch `_adopt_fighters`,
	# VersusArena `_spawn_showcase_fighter`, the duel). Nothing about that ordering
	# changed; what changed is that a hero nobody overrides is no longer 100 HP
	# regardless of who it is.
	#
	# ⚠ `max_hp` IS DELIBERATELY NOT WRITTEN HERE. `_recompute_gear_effects` a few lines
	# below is the single writer: it rescales from this base, preserves the current fill
	# RATIO, and emits `health_changed`. Assigning `max_hp` here as well would skip the
	# emit (the HUD would show the previous class's bar until the next damage tick) and
	# would hand the recompute an already-scaled value to scale again.
	#
	# ⚠ A SPAWNER THAT IMPOSES ITS OWN POOL STILL WINS, and must still write AFTER this
	# call — which every one of them already does (BotMatch `_adopt_fighters`,
	# VersusArena `_spawn_showcase_fighter`, the duel). Nothing about that ordering
	# changed; what changed is that a hero nobody overrides is no longer 100 HP
	# regardless of who it is. Such an override does NOT re-base `_base_max_hp`, so a
	# LATER loadout swap on an overridden body would recompute back to the class number
	# — the same one-writer caveat the field has always had, now with a different value.
	_base_max_hp = int(_cfg.get("hp", BASE_MAX_HP))
	_base_element = _element  # class innate element (a non-elemental weapon reverts here)
	_gear_override.clear()  # a fresh class = a fresh loadout base...
	_recompute_gear_effects()
	_apply_gamestate_loadout(get_node_or_null("/root/GameState"))  # ...then re-apply the hub loadout


# ---------------------------------------------------------------- gear abilities
## Public loadout hook (the loadout UI): swap the piece in `slot` ("weapon"/"head"/
## "body") to `kind` ("" clears), update the rig overlay, and re-apply the gear
## abilities. Idempotent — the effects recompute from the class base every time.
func set_loadout(slot: String, kind: String) -> void:
	if kind == "":
		_gear_override.erase(slot)
	else:
		_gear_override[slot] = kind
	rig.set_equipment(slot, kind)  # cosmetic overlay follows the choice
	_recompute_gear_effects()


## Apply the hub Armory's loadout override (GameState.loadout) after the class base:
## any non-empty slot swaps the class-default piece for the player's choice, then the
## gear abilities recompute once. No-op when nothing is overridden (default classes).
func _apply_gamestate_loadout(gs: Node) -> void:
	if gs == null:
		return
	var lo: Variant = gs.get("loadout")
	if not (lo is Dictionary):
		return
	var changed: bool = false
	for slot: String in ["weapon", "head", "body"]:
		var kind: String = String((lo as Dictionary).get(slot, ""))
		if kind != "":
			_gear_override[slot] = kind
			rig.set_equipment(slot, kind)
			changed = true
	if changed:
		_recompute_gear_effects()


## Aggregate the equipped gear's effect bags (weapon/head/body) into one modifier
## set. Mults multiply, ward takes the strongest, an elemental weapon wins the element.
## ══ LEVEL GROWTH ═════════════════════════════════════════════════════════════
## The five axes, resolved once per class-config / level-up and then composed
## through the SAME aggregate gear already flows through — so there is one place
## that answers "how strong is this hero", not two that can disagree.
##
## ⚠ ALL FIVE ARE THE IDENTITY AT LEVEL 1. `Progression.stat_mult(1, …) == 1.0` is
## pinned by its own suite, so an unlevelled hero is byte-identical to the hero
## that existed before levelling shipped — which is what keeps CLASS_CONFIG's
## hp/speed table, BotMatch's CLASS_VITALITY and the 288-bout balance sweep
## meaningful instead of silently obsolete.
var _growth_cd_recovery: float = 1.0     # FOCUS — see the decay block in _physics_process
var _growth_damage_mult: float = 1.0     # POWER — melee via gear aggregate, spells via SpellCaster
var _growth_ward: float = 0.0            # WARD  — a REDUCTION, folded into GuardComponent


## Re-read Growth from the run's power level. Called on class config and whenever
## `GameState.leveled_up` fires, so a level gained mid-floor is felt immediately
## rather than at the next scene load.
##
## ⚠ READS `power_level()`, NOT `level()`. In co-op that is the party cap — the
## whole point of the rule is that it lands here, on the stat block, and nowhere
## near the spell tree.
func refresh_growth() -> void:
	var lvl: int = 1
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("power_level"):
		lvl = int(gs.call("power_level"))
	_growth_cd_recovery = Progression.stat_mult(lvl, _hero_class, Progression.Axis.FOCUS)
	_growth_damage_mult = Progression.stat_mult(lvl, _hero_class, Progression.Axis.POWER)
	_growth_ward = Progression.ward_reduction(lvl, _hero_class)
	_recompute_gear_effects()


## PUBLIC, for `SpellCaster`: how much harder this caster's spells hit. Melee is
## already scaled through the gear aggregate; a spell's damage lives on a shared
## `SpellDef` resource and cannot be pre-scaled without mutating the catalog, so it
## is applied per-cast at the one place a cast already duplicates its def.
func growth_damage_mult() -> float:
	return _growth_damage_mult


## A LEVEL LANDED. Re-read the stats, then play the beat.
##
## ⚠ ONLY ON THE HERO YOU ARE PLAYING. `GameState` is per-peer, so in co-op every
## peer's own `leveled_up` fires locally — but the arena holds one Hero PER PLAYER,
## and without the authority gate a client would watch the burst fire on its own
## hero AND on the puppet standing next to it, i.e. the level-up would look like it
## happened to both of you.
##
## ⚠ THE STAT REFRESH IS NOT GATED. A puppet's stat block still has to track its
## owner's, or a client's damage numbers against a levelled teammate would be
## computed off level-1 values.
func _on_leveled_up(new_level: int) -> void:
	refresh_growth()
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		return
	if not is_inside_tree():
		return
	LevelUpBurst.play(get_parent(), self, new_level, ClassInfo.color_for(_hero_class))


func _aggregate_gear() -> Dictionary:
	var out: Dictionary = {
		"melee_damage": 1.0, "melee_knockback": 1.0, "melee_cd": 1.0,
		"max_hp": 1.0, "speed": 1.0, "ward": 0.0, "damage_reduction": 0.0, "element": -1,
	}
	# GROWTH COMPOSES WITH GEAR, MULTIPLICATIVELY, BEFORE ANY ITEM IS READ. Seeding
	# the aggregate rather than adding a second pass downstream means every consumer
	# of `_recompute_gear_effects` — max hp, melee damage, speed, mitigation — picks
	# levels up for free and none of them needs to know levels exist.
	var lvl: int = 1
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("power_level"):
		lvl = int(gs.call("power_level"))
	# ⚠ THE SURVIVABILITY DIAL, AND IT DEFAULTS TO 1.0 ON PURPOSE.
	#
	# `TuningConfig.hero_vitality_mult` is live on the F1 Director, so "the character
	# needs more HP" can be answered with a slider in front of the maker instead of a
	# rebuild. It multiplies into the AGGREGATE, so it composes with the class table
	# and with Growth rather than replacing either, and `_recompute_gear_effects`
	# rescales from `_base_max_hp` and keeps the fill ratio for free.
	#
	# ⚠ IT IS NEUTRAL BY DEFAULT BECAUSE THE CLASS TABLE ALREADY MOVED. Two separate
	# passes answered the same complaint in the same hour: `CLASS_CONFIG` was raised
	# x1.4 (78-145 -> 109-203), and this knob was proposed at 1.35. Shipping both
	# would be x1.89 — very nearly double — on top of enemy damage down 25-40%, enemy
	# speed down 15% and floor 1 carrying 36% fewer bodies. That is four levers in one
	# direction and it lands in "trivial", not "survivable". The table raise is the
	# durable half; this stays a dial until the maker has played it.
	out["max_hp"] = Progression.stat_mult(lvl, _hero_class, Progression.Axis.VITALITY) \
		* _tune("hero_vitality_mult", 1.0)
	out["speed"] = Progression.stat_mult(lvl, _hero_class, Progression.Axis.SWIFTNESS)
	out["melee_damage"] = Progression.stat_mult(lvl, _hero_class, Progression.Axis.POWER)
	# FOCUS shortens the melee swing's own gate as well as riding the decay dial —
	# melee_cd is a DURATION here, so faster recovery means a smaller number.
	out["melee_cd"] = 1.0 / maxf(Progression.stat_mult(lvl, _hero_class, Progression.Axis.FOCUS), 0.01)
	# ⚠ WARD IS DELIBERATELY **NOT** SEEDED HERE. The gear loop below combines
	# `damage_reduction` with `maxf`, not multiplication — it takes the single best
	# piece rather than stacking them. Seeding Growth into it would mean a level-30
	# Juggernaut's 21.8% simply SWALLOWS a 15% gear piece, so the armour you equipped
	# would silently stop doing anything the moment you out-levelled it.
	# Growth's WARD is composed as its own layer in `_recompute_gear_effects`.
	for slot: String in ["weapon", "head", "body"]:
		var kind: String = String(_gear_override.get(slot, ""))  # only player CHOICES grant abilities
		if kind == "":
			continue
		var e: Dictionary = GearAbilities.effect(kind)
		for k: String in ["melee_damage", "melee_knockback", "melee_cd", "max_hp", "speed"]:
			if e.has(k):
				out[k] *= float(e[k])
		for k: String in ["ward", "damage_reduction"]:
			if e.has(k):
				out[k] = maxf(out[k], float(e[k]))
		if e.has("element"):
			out["element"] = int(GEAR_ELEMENT.get(String(e["element"]), -1))
	return out


## Apply the aggregated gear effects from the class BASE (idempotent). Called on
## class config + every loadout swap; safe to re-run.
func _recompute_gear_effects() -> void:
	var g: Dictionary = _aggregate_gear()
	# Melee profile from the captured class base * gear mult (idempotent).
	_melee_damage = int(round(float(_base_melee_damage) * float(g["melee_damage"])))
	_melee_knockback = _base_melee_knockback * float(g["melee_knockback"])
	_melee_cd = _base_melee_cd * float(g["melee_cd"])
	# Max HP from the class base * gear mult (keep the current fill ratio).
	var new_max: int = maxi(int(round(float(_base_max_hp) * float(g["max_hp"]))), 1)
	if new_max != max_hp:
		var ratio: float = float(hp) / float(maxi(max_hp, 1))
		max_hp = new_max
		hp = clampi(int(round(float(new_max) * ratio)), 1, new_max)
		health_changed.emit(hp, max_hp)
	_gear_speed_mult = float(g["speed"])
	# Gear mitigation lives on the shared guard, not in local fields, so ward
	# spells and armour resolve through ONE path instead of two that disagree.
	# Re-applying also re-arms the one-shot robe: a fresh loadout = a fresh ward.
	# GEAR MITIGATION + LEVEL WARD, combined the only way two reductions may be:
	# multiplicatively on what GETS THROUGH, `1 - (1-a)(1-b)`. Adding them reaches
	# 100% and makes a hero immortal; taking the max means one of the two is wasted.
	# This form stacks honestly and can never reach 1.0 while either input is under it.
	var gear_dr: float = clampf(float(g["damage_reduction"]), 0.0, 0.95)
	var combined_dr: float = 1.0 - (1.0 - gear_dr) * (1.0 - clampf(_growth_ward, 0.0, 0.95))
	GuardComponent.of(self).set_gear(combined_dr, float(g["ward"]))
	# Element follows the WEAPON: an elemental weapon (staff_ice, scythe, ...) sets it;
	# a non-elemental weapon reverts to the class's innate element (never sticks).
	var ge: int = int(g["element"])
	_element = ge if ge >= 0 else _base_element
	_apply_element()


## Debug: cycle class live (Tab) and persist the choice to GameState so the hub
## selection and the next run stay in sync.
func _cycle_class() -> void:
	configure_class((_hero_class + 1) % HeroClass.size())
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.selected_class = _hero_class


## Live class cycle for a test button (mirrors the Tab press).
func cycle_class_next() -> void:
	_cycle_class()


func current_class_name() -> String:
	return CLASS_NAMES[_hero_class] if _hero_class < CLASS_NAMES.size() else "Class"


## Unleash the equipped SIGNATURE spectacle toward the aim, if THAT SLOT is off
## cooldown. SpellCaster picks the spectacle (magic-circle beam / divine ray / ...).
## Not buffered — a deliberate press.
##
## ⚠ NO MANA GATE. Deleted deliberately, per the spec: "Cooldowns, not mana. Mana
## makes people hoard and play safe, which is the opposite of what this game wants."
## A pool you can run dry teaches you to stop pressing buttons, and a co-op brawler
## whose social engine is friendly fire needs people pressing buttons. `mp_cost`
## SURVIVES on `SpellDef` and is still read — `SpellTier.of()` uses it as one of its
## three shelf thresholds, and the cast/channel sigils scale their radius by it — so
## deleting the field would silently reshelve spells and shrink their tells. It costs
## nothing to keep; it just no longer stops a cast.
func _cast_signature() -> void:
	if _signatures.is_empty():
		return
	var spell: SpellDef = _signatures[_signature_index]
	# Second beat of a THROWN_ANCHOR: with a dagger already out, this press means
	# RECALL, and it must be free. This branch has to sit ABOVE the gate below —
	# the cooldown is running from the throw.
	if spell.kind == SpellDef.Kind.THROWN_ANCHOR \
			and (load(RIFT_DAGGER_PATH) as GDScript).try_recall(get_tree(), self):
		return
	# THE GLOBAL GAP. Sits BELOW the recall branch on purpose — a dagger recall is
	# free by design and is the second half of a throw you already paid for, not a
	# new spell. Sits ABOVE the per-slot bank because it is a different question:
	# the bank asks "has THIS slot recovered", and three recovered slots still chain
	# into one smear without this. See GLOBAL_CAST_LOCKOUT.
	if _cast_lockout > 0.0:
		rig.flash_color(Color(0.5, 0.5, 0.6), 0.08)
		return
	var slot: int = _hand_slot(_signature_index)
	if not _hand.is_ready(slot):
		# THIS slot is still recovering. A different slot may well be ready, which is
		# the entire point of the per-slot bank.
		rig.flash_color(Color(0.5, 0.5, 0.6), 0.08)
		Sfx.play("melee_swing", -14.0, 0.0)
		return
	_hand.start_cooldown(slot, spell.cooldown * cooldown_mult_for(spell))
	# Armed at COMMIT so an instant signature (one that never opens a windup) is
	# covered; `_end_summon`/`_end_channel` re-arm it so for everything else the gap
	# is measured from when the effect LANDS, not from the button press.
	_cast_lockout = GLOBAL_CAST_LOCKOUT
	# Sky spells (meteor / divine row) raise the staff UP and place from the hero;
	# beams emanate FROM the staff tip toward the aim.
	var sky: bool = spell.kind == SpellDef.Kind.METEOR or spell.kind == SpellDef.Kind.DIVINE_RAY \
			or spell.kind == SpellDef.Kind.CONVERGENCE
	# Big spectacles LEVITATE + channel for cast_time, THEN fire — they carry their
	# own float ceremony already.
	if spell.cast_time > 0.0:
		# CO-OP: announce the WINDUP, not just the eruption. The ceremony is the tell
		# — it is the window the other player has to get out of the way, or to decide
		# to stand in it — so a teammate who only ever saw the payoff would be being
		# hit by a spell that had no telegraph on their screen.
		_net_send("cb", {"sid": spell.id, "sky": sky, "ch": true, "w": spell.cast_time})
		_begin_channel(spell, sky)
		return
	# Every OTHER signature now blooms an epic SUMMON windup (spell circle + committed
	# cast pose + gather motes) before it erupts. Rush + blink keep their special
	# fire logic (lunge / teleport), routed through _finish_summon.
	var special: int = SUMMON_NORMAL
	if spell.kind == SpellDef.Kind.RUSH:
		special = SUMMON_RUSH
	elif spell.kind == SpellDef.Kind.BLINK_STRIKE:
		special = SUMMON_BLINK
	_net_send("cb", {"sid": spell.id, "sky": sky, "sp": special,
		"w": SignatureRite.windup_for(spell)})
	_begin_summon(spell, sky, special)


## Start the summon windup: freeze committed, throw the spell's OWN body language,
## and (for anything above a jab) open a sigil overhead + lift slightly off the
## floor. The actual spell fires in _finish_summon, after the windup elapses — the
## delay is the point, not a side effect.
func _begin_summon(spell: SpellDef, sky: bool, special: int) -> void:
	_summoning = true
	_summon_spell = spell
	_summon_sky = sky
	_summon_special = special
	# BODY LANGUAGE comes from the spell's KIND, not from one gesture reused for
	# everything: a wall gets slammed out of the ground, a bombardment gets a ritual
	# circle, a lightning rush gets coiled into the chest. Same table the playground rig
	# reads, so a spell looks like ITSELF regardless of who throws it.
	_summon_pose = CastStyle.for_spell_def(spell)
	_summon_tier = SpellTier.of(spell)
	_summon_total = SignatureRite.windup_for(spell)
	_summon_timer = _summon_total
	# THE DECLARE BEAT rides the windup that is already being spent — it adds no
	# time, and the suppression rules keep it from becoming a tax (see SignatureRite).
	_declare_signature(spell, _summon_total, _summon_tier)
	_summon_aim = _aim_dir
	_summon_target = _aim_point()
	velocity = Vector2.ZERO
	# Levitation is armed here but applied per-frame in _process_summon, so a windup
	# that is cancelled on its very first frame never leaves the hero off the ground.
	_summon_lift = 0.0
	_summon_base_y = global_position.y
	_summon_lift_target = CAST_TIER_LIFT[_summon_tier]
	rig.set_aim(Vector2.UP if sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	# Intensity rises with the tier so the arms commit harder for the expensive
	# spells — the same escalation the windup length and the lift already carry.
	rig.cast_gesture(_pose_gesture(_summon_pose), 0.5 + 0.25 * float(_summon_tier), _element)
	# A QUICK spell gets NO sigil: the maker's ask was a circle for the MORE POWERFUL
	# spells, and a summoning ring opening for a throwaway would cheapen the ones
	# that matter. (Nothing in the shipped library is QUICK yet — this is the gate
	# for when cheap signatures land.)
	if _summon_tier != SpellTier.Tier.QUICK:
		_open_cast_sigil(
			CAST_SIGIL_RADIUS + CAST_SIGIL_RADIUS_PER_COST * clampf(spell.mp_cost / 90.0, 0.0, 1.0),
			_summon_total, spell)
	Sfx.play("charge_up", -6.0, 0.05)


## Play the DECLARE beat for a signature, if the rite's three suppression rules
## allow it. `_last_declared` is PER HERO on purpose: two co-op players must not
## share a repeat clock, or one of them ulting would silence the other's card.
##
## The card is tinted with the SPELL's resolved colour rather than the caster's
## current element, so a spell that overrides its tint announces itself in its own
## colour and the card is class-legible before any of the spell exists.
func _declare_signature(spell: SpellDef, windup: float, tier: int) -> void:
	if spell == null:
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if not SignatureRite.should_declare(tier, spell.id, _last_declared, now,
			SignatureRite.card_live()):
		return
	if SignatureRite.announce(self, spell.display_name.to_upper(),
			spell.resolve_color(_element_color), windup):
		_last_declared[spell.id] = now


## CastStyle.Pose -> the rig's cast-gesture vocabulary. CastStyle names EIGHT body
## languages; CharacterRig ships SIX limb-isolated verbs, so this is a deliberate
## lossy translation that picks the verb whose MOTION is closest to the pose's
## intent. That is exactly the split CastStyle documents: a pose is DIRECTION, and
## each rig interprets it with the joints it actually has.
static func _pose_gesture(pose: int) -> int:
	match pose:
		CastStyle.Pose.SLAM:
			return CharacterRig.GestureKind.STOMP       # fist drives down + foot plant
		CastStyle.Pose.CIRCLE, CastStyle.Pose.CHANNEL, CastStyle.Pose.THROW:
			return CharacterRig.GestureKind.RAISE       # the arm goes overhead first
		CastStyle.Pose.LASH:
			return CharacterRig.GestureKind.FLICK       # one sharp snap off one hand
		CastStyle.Pose.SWEEP:
			return CharacterRig.GestureKind.IGNITE_DROP # the hand has to go LOW
		_:
			# POINT and COIL are the two-handed ones: hands to the chest, then drive
			# out along the aim. GATHER is the rig's only both-hands verb.
			return CharacterRig.GestureKind.GATHER


## Hold the committed summon each frame: stay put, ease the slight levitation, grow
## the sigil, gather converging motes, then erupt when the windup elapses.
func _process_summon(delta: float) -> void:
	velocity = Vector2.ZERO
	# SLIGHT levitation: the toes leaving the floor as the power gathers. Written as
	# an absolute offset from the take-off y (not an upward velocity) so gravity —
	# which this branch skips entirely — has nothing to fight, and so the restore in
	# _end_summon is exact rather than "fall back down eventually".
	if _summon_lift_target > 0.0:
		_summon_lift = move_toward(_summon_lift, _summon_lift_target, CAST_LIFT_SPEED * delta)
		global_position.y = _summon_base_y - _summon_lift
		rig.set_airborne(CAST_LIFT_AIRBORNE * (_summon_lift / _summon_lift_target))
	move_and_slide()  # hold position (gravity zeroed -> committed in place)
	rig.set_body_velocity(Vector2.ZERO)
	rig.play(CharacterRig.State.CAST)  # keep the committed cast pose held
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		_cast_sigil.global_position = _cast_sigil_pos()
		var prog: float = 1.0 - _summon_timer / maxf(_summon_total, 0.001)
		_cast_sigil.scale = Vector2.ONE * (0.55 + 0.7 * prog)  # sigil grows as it charges
	# Energy motes converge inward on the caster (the wind-up).
	if fmod(_summon_timer, 0.09) < delta:
		CombatVfx.spawn_burst(get_parent(), global_position,
			Color(_element_color.r, _element_color.g, _element_color.b, 0.75),
			Color(_element_color.r, _element_color.g, _element_color.b, 0.0),
			5, 0.26, 48.0, 100.0, 0.5, 1.4, 0.0, 0.0, true)
	_summon_timer -= delta
	if _summon_timer <= 0.0:
		_finish_summon()


## The eruption: run the signature's real fire logic, then fire ONE synchronized
## epic beat (camera reveal + punch + shake + hitstop) as the payoff.
func _finish_summon() -> void:
	var spell: SpellDef = _summon_spell
	var special: int = _summon_special
	var sky: bool = _summon_sky
	var aim: Vector2 = _summon_aim
	var target: Vector2 = _summon_target
	# handoff: OFFER the windup sigil instead of dismissing it, so the spectacle
	# spawned on this same frame adopts and continues it. Every SpellCaster.cast()
	# below therefore passes `self` — that is the key MagicCircle.adopt_or_open()
	# looks the pending offer up by.
	_end_summon(true)
	if spell == null:
		# Nothing will spawn, so nothing can adopt the offer. Withdraw it rather than
		# leaving a ring hanging over a cast that never happened.
		_discard_cast_sigil()
		return
	# CO-OP: the eruption itself. Sent SEPARATELY from the windup rather than letting
	# each peer run its own timer, because a windup can be shattered mid-flight — a
	# puppet that fired on its own clock would throw spells that never happened.
	_net_send("cf", {"sid": spell.id, "sky": sky, "sp": special, "aim": aim, "pt": target})
	match special:
		SUMMON_RUSH:
			# Thunderclap / rush: LUNGE forward as the lance rips out.
			rig.set_aim(aim)
			rig.play(CharacterRig.State.PUNCH)
			rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.9, _element)
			if aim.x != 0.0:
				velocity.x = signf(aim.x) * 360.0
			SpellCaster.cast(spell, get_parent(), rig.get_weapon_tip(), target, _element_color, spell.effect, self, attack_group())
		SUMMON_BLINK:
			# Shadow-step: TELEPORT to the marked point mid-slash. The displacement
			# itself lives in blink_to() below, which SpellCaster calls back into —
			# so blink now goes through the same data->dispatch seam as every other
			# spell instead of being hand-rolled here.
			SpellCaster.cast(spell, get_parent(), global_position, target, _element_color, spell.effect, self, attack_group())
			rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
			rig.play(CharacterRig.State.CAST)
		_:
			rig.set_aim(Vector2.UP if sky else aim)
			rig.play(CharacterRig.State.CAST)
			var origin: Vector2 = global_position if sky else rig.get_weapon_tip()
			# `self` is passed on the plain path too now: a deferred-resolution
			# spell (Rift Dagger) needs to know whose anchor it is, and the arg is
			# ignored by every kind that doesn't move or own the caster.
			SpellCaster.cast(spell, get_parent(), origin, target, _element_color, spell.effect, self, attack_group())
			_self_recoil(110.0)  # the ultimate shoves you back
	_notify_element_used()
	# THE PAYOFF — the crescendo after the anticipation. Blink already flashes, so
	# skip the heavy speed-line frame on it; the planted/rush eruptions get it.
	Juice.epic_moment({"strength": 1.0, "frame": special != SUMMON_BLINK})


## Shared summon teardown: put the hero back on the ground, clear state, and either
## hand the sigil on or dismiss it.
##
## EVERY exit runs through here — the spell firing, a hit shattering the windup, a
## co-op down, a revive — which is the whole reason the levitation is undone here
## and nowhere else. The windup branch returns before gravity is integrated, so a
## cast that ended mid-lift without this restore would leave the hero parked in
## mid-air with no force to bring them back down.
##
## `handoff` true = a spectacle is about to spawn and should CONTINUE this sigil
## (no dismissal — dismissing is the duplicate-circle bug). False = the cast died,
## so there is nothing to hand it to and it goes out.
func _end_summon(handoff: bool = false) -> void:
	_summoning = false
	_summon_spell = null
	# Re-armed so the gap runs from where the effect LANDS. `handoff` false means the
	# windup was SHATTERED rather than spent — there is no spectacle to separate, and
	# a player who just got hit out of a cast should be able to answer immediately.
	# Being interrupted is the punishment; it must not also be a lockout.
	_cast_lockout = GLOBAL_CAST_LOCKOUT if handoff else 0.0
	if _summon_lift != 0.0:
		global_position.y = _summon_base_y
		_summon_lift = 0.0
	_summon_lift_target = 0.0
	if is_instance_valid(rig):
		rig.set_airborne(0.0)
	if handoff:
		_release_cast_sigil()
	else:
		_discard_cast_sigil()


## A landed hit shatters the summon — sigil breaks, the ult is lost (MP + cooldown
## already spent, like the channel). Lighter feedback than the channel interrupt.
func _cancel_summon() -> void:
	var pos: Vector2 = global_position
	_net_send("cx")   # co-op: shatter the windup on every other screen too
	_end_summon()
	# The name goes with the cast. A card left hanging over a shattered windup reads
	# as "the ult went off" at the exact moment the player needs to know it did not.
	SignatureRite.dismiss(self)
	CombatVfx.spawn_burst(get_parent(), pos,
		Color(_element_color.r, _element_color.g, _element_color.b, 0.9),
		Color(_element_color.r, _element_color.g, _element_color.b, 0.0),
		14, 0.4, 60.0, 200.0, 1.0, 3.0)
	rig.flash_color(Color(0.7, 0.4, 0.9), 0.12)
	Juice.shake_camera(6.0)
	Sfx.play("melee_swing", -8.0, 0.0)


## Enter the levitating cast: lift off, lock the aim, grow a build-up sigil, hold
## a committed CAST pose. MP + cooldown are already spent (interrupt = no refund).
func _begin_channel(spell: SpellDef, sky: bool) -> void:
	_channeling = true
	_channel_spell = spell
	_channel_sky = sky
	_channel_timer = spell.cast_time
	_channel_total = spell.cast_time
	_channel_target = _aim_point()
	# The channelled tier is where the rite reads best: a 1.0-1.3 s windup gives the
	# card its full 0.30-0.39 s DECLARE and still leaves the longest CHARGE — i.e.
	# the longest dodge window — in the game.
	_declare_signature(spell, spell.cast_time, SpellTier.of(spell))
	_channel_base_y = global_position.y
	_channel_lift = 0.0
	velocity = Vector2.ZERO
	rig.set_aim(Vector2.UP if sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.set_airborne(true)  # legs dangle while floating
	# The channel gets the spell's own body language too, so a channelled wall still
	# reads as a slam and a beam still reads as a thrust. The channel's LENGTH stays
	# the spell's authored cast_time — that number is already the balance-tuned dodge
	# window, so it is never scaled by CastStyle/tier on top.
	rig.cast_gesture(_pose_gesture(CastStyle.for_spell_def(spell)), 1.0, _element)
	# Build-up sigil that grows ABOVE the caster over the channel (maker: "the circle
	# should sit ABOVE"), opened through the SAME seam as the summon windup. This is
	# the path the reported duplicate-circle bug lives on — a channelled BEAM used to
	# dismiss this ring and then BeamSpell.fire() opened a second one at the muzzle —
	# so it matters most here that the sigil is handed over rather than dismissed.
	_open_cast_sigil(
		CHANNEL_SIGIL_RADIUS + CHANNEL_SIGIL_RADIUS_PER_COST * clampf(spell.mp_cost / 90.0, 0.0, 1.0),
		spell.cast_time, spell)
	Sfx.play("charge_up", -2.0, 0.04)  # anime beam/ult power-up swell
	# Pull the camera WIDE for the whole build-up + release so the "insane spell"
	# reads (maker: "when these insane spells are being cast we should zoom out to
	# see the spell"). Hold spans the channel; the fire-time pull in SpellCaster
	# composes on top (max-of-amounts), and it eases back after the cast lands.
	Juice.zoom_pull_camera(0.26, spell.cast_time + 0.55, 0.2, 0.7)


## Per-frame while channeling: ease the levitation, hold the pose, count down, and
## on completion fire the spell (or the physics loop already returned early on cancel).
func _process_channel(delta: float) -> void:
	_channel_lift = move_toward(_channel_lift, CHANNEL_LIFT_HEIGHT, CHANNEL_LIFT_SPEED * delta)
	var bob: float = sin((_channel_total - _channel_timer) * 6.0) * 2.0
	global_position.y = _channel_base_y - _channel_lift + bob
	velocity = Vector2.ZERO
	rig.set_airborne(true)
	rig.set_body_velocity(Vector2.ZERO)
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		_cast_sigil.global_position = _cast_sigil_pos()
		# The sigil GROWS as the cast charges — small at first, large at release.
		var prog: float = 1.0 - _channel_timer / maxf(_channel_total, 0.001)
		_cast_sigil.scale = Vector2.ONE * (0.5 + 0.85 * prog)
	# Gather motes now and then — energy converging on the caster.
	if fmod(_channel_timer, 0.12) < delta:
		CombatVfx.spawn_burst(get_parent(), global_position, Color(_element_color.r, _element_color.g, _element_color.b, 0.7),
			Color(_element_color.r, _element_color.g, _element_color.b, 0.0), 6, 0.3, 40.0, 90.0, 0.5, 1.4, 0.0, 0.0, true)
	_channel_timer -= delta
	if _channel_timer <= 0.0:
		_finish_channel()


## Channel completed uninterrupted — unleash the spectacle, then settle back down.
func _finish_channel() -> void:
	var spell: SpellDef = _channel_spell
	# handoff: the build-up sigil survives the end of the channel so the spectacle
	# below can adopt it instead of opening a second ring at the muzzle.
	_end_channel(true)
	if spell == null:
		_discard_cast_sigil()  # nothing will spawn, so nothing can adopt it
		return
	_net_send("cf", {"sid": spell.id, "sky": _channel_sky, "pt": _channel_target})
	rig.set_aim(Vector2.UP if _channel_sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	var origin: Vector2 = global_position if _channel_sky else rig.get_weapon_tip()
	# `self` is the key MagicCircle.adopt_or_open() looks the pending offer up by, so
	# BeamSpell continues THIS sigil rather than opening a second one at the muzzle.
	# Kinds that don't want a caster ignore the argument.
	SpellCaster.cast(spell, get_parent(), origin, _channel_target, _element_color, spell.effect, self, attack_group())
	_notify_element_used()
	_self_recoil(90.0)
	# The biggest beat in the game — the full synchronized epic payoff (the channeled
	# ults are the screen-fillers, so strength + speed-lines are dialed up).
	Juice.epic_moment({"strength": 1.25, "frame": true})


## A hit landed mid-channel — the ultimate is DISRUPTED (mana/cooldown stay spent).
## Make this UNMISTAKABLE (maker: "the interrupt isn't quite working properly" —
## it fired but read as nothing happening): the growing sigil SHATTERS in the
## element hue, the screen flashes + shakes hard, and the caster is flung out of
## the float. You should never wonder whether the ult got cut.
func _cancel_channel() -> void:
	if not _channeling:
		return
	_net_send("cx")   # co-op: shatter the windup on every other screen too
	var burst_pos: Vector2 = global_position
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		burst_pos = _cast_sigil.global_position
	var ec: Color = _element_color
	_end_channel()  # no handoff — an interrupted channel spawns nothing to adopt it
	SignatureRite.dismiss(self)  # the announcement dies with the cast it announced
	# Sigil shatter: a bright element-hued blowout ring of shards where the circle was.
	CombatVfx.spawn_burst(get_parent(), burst_pos,
		Color(ec.r, ec.g, ec.b, 0.95), Color(ec.r, ec.g, ec.b, 0.0),
		26, 0.45, 90.0, 280.0, 1.5, 3.2, 0.0, 0.0, true)
	# A grey "fizzle" puff over the caster reads as the spell collapsing.
	CombatVfx.spawn_burst(get_parent(), global_position, Color(0.7, 0.6, 0.75, 0.85),
		Color(0.3, 0.25, 0.4, 0.0), 14, 0.4, 50.0, 150.0)
	rig.flash_color(Color(0.85, 0.55, 1.0), 0.18)  # violet disrupt flash
	rig.apply_impulse(Vector2(-facing.x, 0.6), 260.0)  # flung out of the float
	# SILHOUETTE, not the white blow-out: this cut's payoff is a READABLE SHAPE, and
	# white erases the very crescent the beat exists to show off. The black cut keeps
	# the arc and both fighters lit against near-nothing.
	Juice.frame({"style": ImpactFrame.Style.SILHOUETTE, "strength": 0.95,
		"at": global_position + _aim_dir * 40.0})
	Juice.shake_camera(9.0)
	Sfx.play("hero_hurt", 0.0, 0.1)
	Sfx.play("melee_swing", -6.0, 0.14)


## Shared channel teardown: drop the float, restore physics, and either hand the
## sigil to the spectacle about to spawn (`handoff`) or put it out.
func _end_channel(handoff: bool = false) -> void:
	_channeling = false
	_channel_spell = null
	# Same rule as `_end_summon`: the gap follows a spectacle, not an interruption.
	_cast_lockout = GLOBAL_CAST_LOCKOUT if handoff else 0.0
	if is_instance_valid(rig):
		rig.set_airborne(false)
	if handoff:
		_release_cast_sigil()
	else:
		_discard_cast_sigil()


## CAST KIT SLOT `idx` DIRECTLY — what a spell BUTTON does, as opposed to the
## select-then-trigger pair a cycle key forces.
##
## Moving `_signature_index` is not a side effect, it is half the point: the hotbar's
## lifted frame follows the spell you actually threw, `ultimate`/`cycle_signature`
## carry on meaning what they always meant, and `start_signature_cooldown` (the Rift
## Dagger's deferred bill) charges the slot the dagger came out of.
##
## `signature_changed` is emitted only on a real change, so mashing one button does
## not spam the HUD label every press.
##
## Returns false for a slot this class does not carry, rather than clamping — a
## button that reaches nothing must read as "nothing happened", never as a plausible
## wrong spell fired on your behalf (the same rule as `bot_select_signature`).
## Take a picked-up or handed-over spell into slot `nth`. THE PUBLIC HOOK
## `SpellGrant._install` looks for first.
##
## SpellGrant works without this — it falls back to reaching into `_signatures`
## and `_hand` directly, guarded by a test that goes red if either is renamed.
## That fallback is a tripwire, not a design. This is the door it should be using,
## so the drop system stops depending on two private member names staying put.
##
## Both halves are written and they are NOT redundant: `_signatures` is what
## `cast_signature_slot` reads to decide WHAT to cast, `_hand` owns the per-slot
## cooldown and is what the loadout bar draws. Writing one and not the other gives
## you a bar showing a spell that casts something else — this codebase already has
## a scar from exactly that two-sources-of-truth shape.
func receive_spell(spell: SpellDef, nth: int) -> bool:
	return SpellGrant.install(_signatures, _hand, spell, nth)


func cast_signature_slot(idx: int) -> bool:
	if idx < 0 or idx >= _signatures.size():
		return false
	if idx != _signature_index:
		_signature_index = idx
		signature_changed.emit(_signatures[idx].display_name)
	_cast_signature()
	return true


## Everything a spell BUTTON needs to draw itself, for one kit slot. One publisher
## for the hotbar, the loadout bar and the touch pad, so a fourth reader cannot
## invent a fifth answer to "is this button ready".
##
## `pulse` is 0..1 and decays from 1 on the frame the slot came off cooldown — the
## READY-FLASH. It is here rather than in each HUD because three HUDs each keeping
## their own "was it ready last frame" latch is three chances to disagree, and
## because a HUD that is not on screen yet would miss the edge entirely.
func spell_button_state(slot: int) -> Dictionary:
	var sig: SpellDef = signature_at(slot)
	var pulse: float = 0.0
	if slot >= 0 and slot < _ready_pulse.size():
		pulse = _ready_pulse[slot] / READY_PULSE_TIME
	return {
		"slot": slot,
		"key": SPELL_KEYS[slot] if slot >= 0 and slot < SPELL_KEYS.size() else "",
		"name": AbilityBar.short_spell_name(sig.display_name) if sig != null else "--",
		"remaining": signature_cooldown(slot) if sig != null else 0.0,
		"total": maxf(sig.cooldown, 0.01) if sig != null else 0.0,
		"ready": sig != null and signature_ready(slot),
		"filled": sig != null,
		"pulse": clampf(pulse, 0.0, 1.0),
		"selected": slot == _signature_index,
	}


## The same answer for a NON-spell touch button, keyed by the action it drives, so the
## pad can draw a cooldown veil on DASH and PARRY without knowing which row of
## `ability_hud_state()` they happen to occupy. That index coupling is exactly how a
## HUD ends up drawing the wrong ability's timer after someone reorders the bar.
##
## An action with no cooldown (jump) reports ready with a zero total, which the veil
## renders as "nothing to draw" — one shape for every button rather than a special
## case per verb.
func touch_button_state(action: StringName) -> Dictionary:
	match action:
		&"dash":
			return _touch_state(_dash_cooldown_timer, float(_cfg["dash_cd"]))
		&"parry":
			if _guard != null:
				var rearm: float = _guard.rearm_time()
				return _touch_state(0.0 if _guard.is_ready() else rearm, rearm)
			return _touch_state(_parry_cooldown_timer, PARRY_COOLDOWN)
		&"blast":
			return _touch_state(_blast_cooldown_timer, float(_cfg["blast_cd"]))
		&"blink":
			return _touch_state(_blink_cooldown_timer, float(_cfg["blink_cd"]))
		&"nova":
			return _touch_state(_nova_cooldown_timer, NOVA_COOLDOWN)
		&"melee":
			return _touch_state(_melee_cooldown_timer, _melee_cd)
	return _touch_state(0.0, 0.0)


func _touch_state(remaining: float, total: float) -> Dictionary:
	return {"remaining": maxf(remaining, 0.0), "total": maxf(total, 0.0),
		"ready": remaining <= 0.0, "pulse": 0.0, "filled": true, "name": ""}


## Age the ready-flash timers and catch the not-ready -> ready edge on every slot.
## Ticked with the cooldown bank (above the channel/summon early-returns) so a slot
## that recovers DURING a long cast still flashes when the cast ends.
func _tick_ready_pulse(delta: float) -> void:
	var n: int = SpellTier.SLOT_COUNT
	if _ready_pulse.size() != n:
		_ready_pulse.resize(n)
		_was_slot_ready.resize(n)
		for i: int in n:
			_ready_pulse[i] = 0.0
			# Seeded from the LIVE state, not from `true`: seeding optimistic would
			# make every slot that happened to be recovering at spawn flash once for
			# no reason the player could connect to anything.
			_was_slot_ready[i] = signature_at(i) != null and signature_ready(i)
	for i: int in n:
		_ready_pulse[i] = maxf(_ready_pulse[i] - delta, 0.0)
		var now_ready: bool = signature_at(i) != null and signature_ready(i)
		if now_ready and not _was_slot_ready[i]:
			_ready_pulse[i] = READY_PULSE_TIME
			# The ULT gets an audible tick as well as a visual one. Only the ult: three
			# chimes a rotation is noise, and the ult is the one you are actually
			# waiting on. Quiet and pitched up so it sits above the fight rather than
			# in it.
			if i == SpellTier.ULT_SLOT:
				Sfx.play("sigil_form", -13.0, 0.02, 1.5)
		_was_slot_ready[i] = now_ready


## Swap to the next equipped signature (the loadout cycle — V). DEMOTED by the three
## spell buttons: it still moves the selection the hotbar lifts and `ultimate` fires,
## but it is no longer how a player reaches a spell, and no HUD label names it.
func _cycle_signature() -> void:
	if _signatures.is_empty():
		return
	_signature_index = (_signature_index + 1) % _signatures.size()
	signature_changed.emit(_signatures[_signature_index].display_name)
	Sfx.play("footstep", -3.0, 0.25)


## Active signature (or null) — for the HUD label + cooldown/MP readout.
func current_signature() -> SpellDef:
	if _signatures.is_empty():
		return null
	return _signatures[_signature_index]


## Hand index of signature slot `i`. See `_hand`'s note: FISTS permanently occupies
## hand index 0, so the kit starts one along. Never do this arithmetic inline.
func _hand_slot(sig_index: int) -> int:
	return sig_index + HAND_SPELL_OFFSET


## Seconds left on signature slot `i` — the per-slot replacement for reading the old
## shared `_signature_cd_timer`. Public so the HUD, the bots and the tests all ask the
## same question of the same owner instead of three of them keeping their own copy.
func signature_cooldown(sig_index: int) -> float:
	return _hand.cooldown(_hand_slot(sig_index))


func signature_ready(sig_index: int) -> bool:
	return _hand.is_ready(_hand_slot(sig_index))


func signature_cooldown_ratio() -> float:
	var s: SpellDef = current_signature()
	if s == null or s.cooldown <= 0.0:
		return 0.0
	return clampf(signature_cooldown(_signature_index) / s.cooldown, 0.0, 1.0)


## Rogue dash-strike: every enemy/crate the dash passes within range takes melee
## damage once per dash (dedupe via _dash_hit). Mirrors _on_melee_hit_frame.
func _dash_strike_sweep() -> void:
	var rng: float = _cfg["dash_strike_range"]
	var dmg: int = _cfg["dash_strike_damage"]
	# THE STAGGER. A Shoulder Charge shoves far harder than the class's own melee
	# knockback — that is what makes it a charge rather than a dash that ticks damage.
	# Optional key: absent -> the melee value, i.e. byte-identical to before.
	var kb: float = float(_cfg.get("dash_strike_knockback", _melee_knockback))
	var hit_any: bool = false
	# SILHOUETTE, NOT ORIGIN. This used to be `distance_to(enemy.global_position)`,
	# a zero-size point test against a node origin that sits ~10 px BELOW the drawn
	# head (19 px on the 1.9x sparring dummies) — the maker's "spells pass through
	# heads without registering" bug, in its melee form. `SpellTargets` measures the
	# drawn body and adds the target's OWN published forgiveness, and it filters
	# line-of-sight so a dash can no longer strike through a wall it passed beside.
	#
	# ⚠ The reach GROWS as a result — up to about half a rig height on the vertical
	# axis — and that growth is the fix, not a side effect. If dash-strike ever feels
	# too generous the knob is `dash_strike_range` in CLASS_CONFIG or
	# `Enemy.HIT_MARGIN_FACTOR`, never both, and never a third margin added here.
	for enemy: Node in SpellTargets.in_radius(global_position, rng,
			get_tree().get_nodes_in_group(attack_group()), [self], self):
		if enemy in _dash_hit:
			continue
		_dash_hit.append(enemy)
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(_dash_dir * kb)
		hit_any = true
	for prop: Node in SpellTargets.in_radius(global_position, rng,
			get_tree().get_nodes_in_group("destructible"), [self], self):
		if prop in _dash_hit:
			continue
		_dash_hit.append(prop)
		if prop.has_method("take_damage"):
			prop.take_damage(dmg)
		hit_any = true
	if hit_any:
		Juice.hit_stop(0.05)
		Juice.shake_camera(4.0)
		Sfx.play("melee_hit")


## THE ONE MOVEMENT BUTTON, dispatched nine ways. Kept as `_start_dash` because it is
## the name `_try_fire_buffered` presses, the name `tools/dash_agent_capture.gd` calls,
## and the name the `dash` action has always mapped to — renaming it would be a rename
## of the seam, not of a verb.
##
## Two of the nine (`lightning_blink`, `thrall_swap`) are TELEPORTS: they resolve
## entirely inside this call and never set `is_dashing`, so the per-frame dash branch
## below never sees them. The other seven are travel and share the branch, parameterised
## by `_dash_verb` / `_dash_speed` / `_dash_total`.
func _start_dash() -> void:
	var verb: String = _move_verb()
	# ⚠ NO PRESS-DEPENDENT BRANCH ABOVE THIS MATCH, AND THAT IS DELIBERATE. The
	# Arcanist used to be checked here first — a live recall anchor turned the SAME
	# press into a backwards teleport instead of a step, ahead of the cooldown and
	# ahead of the travel setup. One button meaning two things depending on state the
	# player could not see is exactly what the maker called confusing. Every verb now
	# resolves purely from WHICH CLASS YOU ARE.
	match verb:
		"lightning_blink":
			_lightning_blink()
			return
		"thrall_swap":
			_thrall_swap()
			return
	_begin_travel(verb)


## The shared setup for the seven TRAVEL verbs. Everything that used to be inlined in
## `_start_dash` lives here unchanged except that the speed, the duration and the
## i-frame slice now come from the class rather than from three globals.
func _begin_travel(verb: String) -> void:
	is_dashing = true
	_dash_verb = verb
	_dash_speed = _verb_speed(verb)
	_dash_total = _verb_time(verb)
	_dash_timer = _dash_total
	_dash_cooldown_timer = _cfg["dash_cd"]
	# Dash the EXACT angle of the held movement keys (true 8-way): W+D -> up-right,
	# S+A -> down-left, D alone -> flat right. Accurate to which keys are down,
	# including vertical. Falls back to live velocity, then the last walk dir /
	# facing, only when no direction key is held (a standing dash).
	var keys: Vector2 = _vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if keys.length() > 0.1:
		_dash_dir = keys.normalized()
	elif velocity.length() > 40.0:
		_dash_dir = velocity.normalized()
	elif _move_dir != Vector2.ZERO:
		_dash_dir = _move_dir
	else:
		_dash_dir = Vector2(signf(facing.x), 0.0) if facing.x != 0.0 else Vector2.RIGHT
	# GROUND-PLANE VERBS travel horizontally whatever the stick says. A shoulder charge
	# aimed up-right is still a shoulder charge; only the Shadowblade gets to fly.
	if _verb_is_grounded(verb):
		var fx: float = signf(_dash_dir.x)
		if fx == 0.0:
			fx = signf(facing.x) if facing.x != 0.0 else 1.0
		_dash_dir = Vector2(fx, 0.0)
	_ghost_timer = 0.0  # first afterimage lands this frame
	_dash_hit.clear()
	_begin_verb_extras(verb)
	_net_send("ds", {"dir": _dash_dir, "vb": verb})


## The per-verb one-shot that fires as travel STARTS. Everything here is additive to
## the shared setup above; a verb with nothing to add is simply absent.
func _begin_verb_extras(verb: String) -> void:
	match verb:
		"arcane_phase":
			# THE BODY IS LEFT BEHIND. A violet after-image STANDING at the origin (zero
			# wind, zero launch, so it holds the pose instead of streaking like a trail
			# ghost) plus a dissolve poof. This is the whole tell for a step you cannot
			# be hit out of — an invulnerable travel that looked like everyone else's
			# dash would just read as "the hit missed", and the Arcanist's one defensive
			# trick has to be legible to the person being dodged as well.
			#
			# This is the ONLY thing left of the old two-beat recall: the burst used to
			# mark where the anchor was DROPPED so you could aim your way back to it.
			# Nothing returns here now — it marks where you stopped being.
			rig.spawn_ghost(get_parent(), ARCANE_PHASE_COLOR, Vector2.ZERO, Vector2.ZERO,
				ARCANE_PHASE_ECHO_FADE)
			CombatVfx.spawn_burst(
				get_parent(), global_position, ARCANE_PHASE_COLOR, BLINK_BURST_END,
				10, 0.5, 10.0, 30.0, 1.0, 2.0
			)
		"surge":
			# Armour is owed for the travel PLUS a tail. The tail is the whole
			# difference from "every dash ignores knockback" (`apply_knockback`).
			_surge_armor_timer = _dash_total + SURGE_ARMOR_TAIL
		"radiant_step":
			_radiant_wake_timer = 0.0  # first pulse lands on frame one
		"ice_slide":
			# Enter the slide at speed; the branch bleeds it from here rather than
			# holding it flat like a dash does.
			velocity.x = _dash_dir.x * _dash_speed
		"charge":
			Sfx.play("dash", 1.0, 0.05, 0.8)


## Travel speed for a verb. `_tune("dash_speed", ...)` still scales the baseline dash so
## the live feel knob keeps working, applied as a RATIO so a class that is deliberately
## slower stays proportionally slower when the maker drags the slider.
func _verb_speed(verb: String) -> float:
	var scale: float = _tune("dash_speed", DASH_SPEED) / DASH_SPEED
	var base: float = DASH_SPEED
	match verb:
		"arcane_phase":
			base = ARCANE_PHASE_SPEED
		"air_dash":
			base = AIR_DASH_SPEED
			if not is_on_floor():
				base *= AIR_DASH_AIRBORNE_BONUS  # BETTER in the air, uniquely
		"charge":
			base = CHARGE_SPEED
		"surge":
			base = SURGE_SPEED
		"radiant_step":
			base = RADIANT_STEP_SPEED
		"ice_slide":
			base = ICE_SLIDE_SPEED
		"committed_step":
			base = COMMITTED_STEP_SPEED
	return base * scale


func _verb_time(verb: String) -> float:
	var scale: float = _tune("dash_time", DASH_TIME) / DASH_TIME
	var base: float = DASH_TIME
	match verb:
		"arcane_phase":
			base = ARCANE_PHASE_TIME
		"air_dash":
			base = AIR_DASH_TIME
		"charge":
			base = CHARGE_TIME
		"surge":
			base = SURGE_TIME
		"radiant_step":
			base = RADIANT_STEP_TIME
		"ice_slide":
			base = ICE_SLIDE_TIME
		"committed_step":
			base = COMMITTED_STEP_TIME
	return base * scale


## This class's movement verb. One reader, so a class table that forgets the key
## degrades to the old shared dash instead of crashing — and so the pre-change table
## resolves all nine to the same string, which is what the distinctness test catches.
func _move_verb() -> String:
	return String(_cfg.get("move_verb", "dash"))


func _verb_is_grounded(verb: String) -> bool:
	return GROUNDED_VERBS.has(verb)


## This class's WALK speed. `SPEED` used to be read straight out of the movement block
## for all nine; it is now the fallback and the shape of the live tuning knob.
##
## The knob is applied as a RATIO rather than as an absolute, deliberately: dragging
## `hero_speed` must move the whole roster together, so a Juggernaut that is 79% of the
## baseline stays 79% of it at any setting. Reading `_tune` as an absolute (the obvious
## version) would have collapsed all nine classes back to one number the moment the
## maker touched the slider — i.e. it would have silently undone this entire task from
## the tuning panel.
func _class_speed() -> float:
	# THE PACT MOVES YOU. Maker: a pacted body should *"move faster and do more
	# damage"* and be able to *"get up close and personal"*. Multiplied here rather
	# than written into `_cfg` so it is temporary by construction — when the pact
	# leaves its group the multiplier is 1.0 again on the very next frame, with
	# nothing to restore and nothing that can leak.
	return float(_cfg.get("speed", SPEED)) * (_tune("hero_speed", SPEED) / SPEED) \
		* BloodPact.speed_mult(self, self)


## PUBLIC, for the bot seam and the tests: roughly how far one press of the movement
## button carries this class. DERIVED from the verb's own numbers rather than restated
## — `BotBrain.DASH_DIST` is a hand-copied `620 * 0.14` literal and this is exactly the
## drift that comment warns about, so the blackboard publishes this instead.
func movement_verb_distance() -> float:
	var verb: String = _move_verb()
	match verb:
		"lightning_blink":
			return LIGHTNING_BLINK_DISTANCE
		"thrall_swap":
			# Honest answer: with a thrall in reach it is arbitrarily far, so publish
			# what a bot can COUNT on, which is the no-thrall fallback.
			return THRALL_SWAP_FALLBACK_DISTANCE
		"ice_slide":
			# A slide BLEEDS speed, so speed * time overstates it by a lot. Integrate
			# the linear decay instead: it stops early if friction wins first.
			var t_stop: float = minf(_verb_time(verb), ICE_SLIDE_SPEED / ICE_SLIDE_FRICTION)
			return ICE_SLIDE_SPEED * t_stop - 0.5 * ICE_SLIDE_FRICTION * t_stop * t_stop
	return _verb_speed(verb) * _verb_time(verb)


## PUBLIC: does one press of the movement button dodge anything? A bot that spends its
## movement button as an i-frame answer needs to know that a Brawler charge and a
## Juggernaut surge do not have any (see `_dash_invulnerable`).
##
## A TELEPORT answers 1.0 because it grants a flat post-arrival window
## (`LIGHTNING_BLINK_IFRAME` / `THRALL_SWAP_IFRAME`) rather than a fraction of a travel
## it does not have. The question the callers ask is "does pressing this dodge", and for
## those two the answer is an unqualified yes.
##
## ⚠ 1.0 NO LONGER IMPLIES "TELEPORT". The Arcanist's Arcane Phase is a TRAVEL that
## answers 1.0 from its own class row — it really is invulnerable for its whole
## duration. Anything reading this to infer WHICH KIND of verb it is wants
## `_verb_is_teleport` instead.
func movement_verb_iframe_fraction() -> float:
	if _verb_is_teleport(_move_verb()):
		return 1.0
	return float(_cfg.get("dash_iframe_fraction", DASH_IFRAME_FRACTION))


## Verbs that resolve instantly inside `_start_dash` and never enter the travel branch.
## Reads the documented list so the list cannot drift from the dispatch it describes.
func _verb_is_teleport(verb: String) -> bool:
	return TELEPORT_VERBS.has(verb)


## PUBLIC: the verb's name, for the HUD, the bots and the suites. One spelling.
func movement_verb_name() -> String:
	return _move_verb()


## ⚠ DELETED HERE: `_recall_pending()` and `_arcane_recall_return()` — the Arcanist's
## backwards teleport. `_arcane_recall_return` ran the anchor through
## `_safe_blink_destination`, charged the dash cooldown, granted `BLINK_IFRAME`, poofed
## at both ends and sent an `"rc"` packet. In other words it was a third blink wearing
## the movement button, which is precisely why it went (maker: *"its just a repeat of
## blink"*). If a future Arcanist wants a repositioning tool it belongs on a SPELL SLOT
## with its own key and its own icon, not as a hidden second meaning for Space.


## STORMCALLER: no dash on this class at all — the movement button TELEPORTS, in a
## crackle, further than either a dash or the shadow blink on R.
##
## Aim, vetting, refusal and refund are the shadow blink's, verbatim, because there is
## exactly one set of rules about where a body may rest and `_blink()` already writes
## them down. What differs is the distance, the colour and the cooldown it charges.
func _lightning_blink() -> void:
	var origin: Vector2 = global_position
	# ⚠ THE STICK, NOT THE AIM — AND THIS ONE WAS MISSED THE FIRST TIME. Maker: "make
	# sure that the blink when you press space is in the direction of movement, not
	# where we are facing." The R-blink (`_blink`) was moved onto the movement vector
	# when that ruling landed; THIS is the Stormcaller's SPACE verb, and it resolves on
	# a different dispatch path (`TELEPORT_VERBS`, inside `_start_dash`) so it never
	# went through `_begin_travel` where the movement read lives. It kept reading
	# `_aim_dir` — which is exactly the "where we are facing" the maker is describing.
	#
	# Same order as `_blink` and `_begin_travel`, so all three answer the same thumb:
	# the 8-way movement vector, then aim for a standing blink, then RIGHT so it always
	# fires rather than refusing.
	var dir: Vector2 = _vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if dir.length() <= 0.1:
		dir = _aim_dir
	if dir == Vector2.ZERO:
		dir = _move_dir
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var dest: Vector2 = _safe_blink_destination(
		origin, origin + dir.normalized() * LIGHTNING_BLINK_DISTANCE)
	if origin.distance_to(dest) < BLINK_MIN_TRAVEL:
		# REFUSED -> REFUNDED, same contract as `_blink`: nothing is spent above this
		# line, so a blink with nowhere legal to land can be re-aimed and pressed again.
		CombatVfx.spawn_burst(get_parent(), origin, Color(0.5, 0.5, 0.3, 0.5),
			LIGHTNING_BLINK_END, 6, 0.2, 20.0, 55.0, 1.0, 2.0)
		Sfx.play("blink", -14.0, 0.1, 1.4)
		return
	_dash_cooldown_timer = _cfg["dash_cd"]
	_blink_iframe_timer = LIGHTNING_BLINK_IFRAME
	rig.spawn_ghost(get_parent(), LIGHTNING_BLINK_START, Vector2.ZERO, Vector2.ZERO, 0.28)
	_lightning_blink_fx(origin, dest)
	global_position = dest
	velocity.y = 0.0
	rig.play(CharacterRig.State.CAST)
	_net_send("lb", {"to": dest})


## The crackle at both ends plus a few arc motes strung along the line, so the eye
## reads a DISCHARGE rather than a body that skipped some frames. Shared with the
## puppet replay so both screens draw the same thing.
func _lightning_blink_fx(origin: Vector2, dest: Vector2) -> void:
	CombatVfx.spawn_burst(get_parent(), origin, LIGHTNING_BLINK_START,
		LIGHTNING_BLINK_END, 20, 0.3, 60.0, 190.0, 1.5, 3.0)
	CombatVfx.spawn_burst(get_parent(), dest, LIGHTNING_BLINK_START,
		LIGHTNING_BLINK_END, 26, 0.35, 80.0, 240.0, 1.5, 3.5)
	# Three motes down the line: cheap, and it is what makes the two poofs read as
	# ONE event instead of two unrelated sparks.
	for i: int in 3:
		var t: float = float(i + 1) / 4.0
		CombatVfx.spawn_burst(get_parent(), origin.lerp(dest, t), LIGHTNING_BLINK_START,
			LIGHTNING_BLINK_END, 5, 0.18, 30.0, 90.0, 1.0, 2.0)
	rig.flash_color(LIGHTNING_BLINK_FLASH, BLINK_ARRIVAL_FLASH_TIME)
	Sfx.play("blink", 1.0, 0.08, 1.5)


## WARLOCK: trade places with one of YOUR OWN minions.
##
## THE CONTRACT (another agent owns the minions): group `THRALL_GROUP`, node meta
## `THRALL_OWNER_META` -> the Hero that raised it. Anything in the group that is not
## ours, not alive, or out of `THRALL_SWAP_RANGE` is not a candidate, so a teammate's
## thralls are not a free taxi and a corpse is not a destination.
##
## BOTH landings are vetted. Ours through `_safe_blink_destination` exactly like every
## other teleport; the thrall's through the same call from its own end. If OUR half has
## nowhere legal to go the whole swap is refused and refunded — a half-completed swap
## that moved the minion and not the caster is worse than no swap at all.
##
## NO THRALL -> a short blink along the aim (`THRALL_SWAP_FALLBACK_DISTANCE`), with the
## same refuse-and-refund floor. The button is never dead and it never strands anyone.
func _thrall_swap() -> void:
	var thrall: Node2D = _nearest_thrall()
	if thrall == null:
		_thrall_swap_fallback()
		return
	var origin: Vector2 = global_position
	var their_origin: Vector2 = thrall.global_position
	var mine: Vector2 = _safe_blink_destination(origin, their_origin)
	if origin.distance_to(mine) < BLINK_MIN_TRAVEL:
		_thrall_swap_fizzle(origin)
		return
	# The minion's landing, vetted from ITS end toward ours. `_safe_blink_destination`
	# probes with OUR collision shape and excludes only OUR rid, so this is an
	# approximation of the thrall's own footprint — deliberately, because Hero must not
	# start reaching into another agent's body for a shape. It is conservative in the
	# direction that matters (a hero capsule is not smaller than a minion) and the
	# fallback is the thrall simply staying put, never the thrall inside a wall.
	var theirs: Vector2 = _safe_blink_destination(their_origin, origin)
	if their_origin.distance_to(theirs) < BLINK_MIN_TRAVEL:
		theirs = their_origin  # our half still happens; the minion holds its ground
	_dash_cooldown_timer = _cfg["dash_cd"]
	_blink_iframe_timer = THRALL_SWAP_IFRAME
	rig.spawn_ghost(get_parent(), THRALL_SWAP_START, Vector2.ZERO, Vector2.ZERO, 0.32)
	CombatVfx.spawn_burst(get_parent(), origin, THRALL_SWAP_START, THRALL_SWAP_END,
		20, 0.35, 50.0, 150.0, 1.5, 3.0)
	CombatVfx.spawn_burst(get_parent(), their_origin, THRALL_SWAP_START, THRALL_SWAP_END,
		20, 0.35, 50.0, 150.0, 1.5, 3.0)
	global_position = mine
	velocity.y = 0.0
	thrall.global_position = theirs
	if thrall.has_method("set"):
		thrall.set("velocity", Vector2.ZERO)  # a swapped minion does not inherit a fall
	rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("blink", -1.0, 0.1, 0.7)
	_net_send("sw", {"to": mine, "th": theirs})


## Nearest LIVING thrall of OURS inside range, or null. Duck-typed throughout: Hero has
## no compile-time knowledge of the minion class and must not grow any.
func _nearest_thrall() -> Node2D:
	var best: Node2D = null
	var best_d: float = THRALL_SWAP_RANGE
	for n: Node in get_tree().get_nodes_in_group(THRALL_GROUP):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if n.get_meta(THRALL_OWNER_META, null) != self:
			continue  # somebody else's minion is not our escape route
		# A dying/dead minion is not a destination. `hp` is optional — a thrall that
		# does not publish one is treated as alive, which is the safe default.
		var hp_v: Variant = n.get("hp")
		if hp_v != null and float(hp_v) <= 0.0:
			continue
		# ...and the same guard for `downed`, for the same reason and a worse symptom.
		# `Object.get()` on a property a script has not DECLARED returns null, and
		# `bool(null)` is not false — it is the runtime error "Nonexistent 'bool'
		# constructor", which ABORTS this function on the spot and hands the caller
		# back null. Every thrall trips it: `Thrall.gd` declares no `downed`. So the
		# whole thrall-swap read as "no thrall in range" and silently dropped the
		# Warlock into `_thrall_swap_fallback` every single time, with the error
		# scrolling past in a place nobody looks.
		#
		# Found by `tools/bot_sim.gd` in STORMCALLER_vs_WARLOCK — i.e. only once the
		# Warlock actually CARRIED Raise Thrall and there were minions on the floor to
		# find. It was unreachable, and therefore invisible, before the kit change.
		var downed_v: Variant = n.get("downed")
		if downed_v != null and bool(downed_v):
			continue
		var d: float = global_position.distance_to((n as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node2D
	return best


## The no-thrall degradation, stated in code as well as in the header: a short vetted
## blink along the aim. Refused and refunded when even that has nowhere to land.
func _thrall_swap_fallback() -> void:
	var origin: Vector2 = global_position
	# ⚠ THE STICK, NOT THE AIM — the last of the three, and the maker named it: "dash
	# should not be in the way it's facing but the movement on the joystick or walking,
	# for all the characters, INCLUDING WARLOCK'S BLINK."
	#
	# With a thrall alive this verb has no direction at all — it swaps two bodies, and
	# that is the class identity. This is the no-thrall path, where it degrades to an
	# ordinary blink, and a blink answers the movement vector like every other one.
	# `tools/probe_dash_up.gd` had this as the ONE class of nine still travelling
	# toward the aim.
	var dir: Vector2 = _vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if dir.length() <= 0.1:
		dir = _aim_dir
	if dir == Vector2.ZERO:
		dir = _move_dir
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var dest: Vector2 = _safe_blink_destination(
		origin, origin + dir.normalized() * THRALL_SWAP_FALLBACK_DISTANCE)
	if origin.distance_to(dest) < BLINK_MIN_TRAVEL:
		_thrall_swap_fizzle(origin)
		return
	_dash_cooldown_timer = _cfg["dash_cd"]
	_blink_iframe_timer = THRALL_SWAP_IFRAME
	rig.spawn_ghost(get_parent(), THRALL_SWAP_START, Vector2.ZERO, Vector2.ZERO, 0.28)
	CombatVfx.spawn_burst(get_parent(), origin, THRALL_SWAP_START, THRALL_SWAP_END,
		14, 0.3, 40.0, 110.0, 1.5, 3.0)
	global_position = dest
	velocity.y = 0.0
	CombatVfx.spawn_burst(get_parent(), dest, THRALL_SWAP_START, THRALL_SWAP_END,
		18, 0.35, 50.0, 130.0, 1.5, 3.0)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("blink", -3.0, 0.1, 0.7)
	_net_send("sw", {"to": dest, "th": origin})


## Refused: a dim fizzle at the feet, nothing spent. Same read as `_blink`'s refusal so
## a player learns ONE "that press was blocked" tell rather than three.
func _thrall_swap_fizzle(at: Vector2) -> void:
	CombatVfx.spawn_burst(get_parent(), at, Color(0.3, 0.15, 0.35, 0.5),
		THRALL_SWAP_END, 6, 0.2, 20.0, 55.0, 1.0, 2.0)
	Sfx.play("blink", -14.0, 0.1, 0.55)


## CLERIC: one healing pulse dropped in the wake. Allies only — every living
## non-downed body in the `hero` group except us — and it never touches the caster,
## because a self-heal on a mobility button is a sustain button wearing a disguise.
func _radiant_wake_pulse() -> void:
	CombatVfx.spawn_burst(get_parent(), global_position, RADIANT_WAKE_COLOR,
		Color(1.0, 0.95, 0.65, 0.0), 6, 0.35, 10.0, 40.0, 1.0, 2.5)
	for n: Node in get_tree().get_nodes_in_group(&"hero"):
		if n == self or not (n is Node2D) or not is_instance_valid(n):
			continue
		if bool(n.get("downed")):
			continue
		if global_position.distance_to((n as Node2D).global_position) > RADIANT_WAKE_RADIUS:
			continue
		if n.has_method("heal"):
			n.call("heal", RADIANT_WAKE_HEAL)


## THE ONE THING THAT DIFFERS PER CLASS INSIDE THE TRAVEL LOOP. Four of the seven
## travel verbs are a flat gravity-free burst (the old dash's behaviour, which is why
## they fall through); the three GROUNDED_VERBS keep falling, and the Cryomancer's
## slide additionally bleeds and half-steers instead of holding its speed.
func _travel_velocity(delta: float) -> Vector2:
	var v: Vector2 = velocity
	match _dash_verb:
		"ice_slide":
			# LOW FRICTION, POOR AUTHORITY. Speed decays linearly; the stick can lean
			# the line but cannot turn it around inside the slide.
			v.x = move_toward(v.x, 0.0, ICE_SLIDE_FRICTION * delta)
			var steer_x: float = _axis(&"move_left", &"move_right")
			if steer_x != 0.0:
				v.x = move_toward(v.x, steer_x * _dash_speed,
					GROUND_ACCEL * ICE_SLIDE_STEER * delta)
			v.y = 0.0 if is_on_floor() else minf(v.y + GRAVITY_FALL * delta, MAX_FALL)
			return v
		# ⚠ THIS BRANCH IS NOW EMPTY OF CLASSES, and both departures were the same bug.
		# `surge` (Juggernaut) and then `charge` (Brawler) each sat here having their
		# vertical thrown away and replaced with gravity — `GROUNDED_VERBS` is empty, so
		# `_start_dash` was already handing both of them a true 8-way `_dash_dir`, and
		# the flattening the class comments blame was happening HERE, one layer below
		# where anyone was looking for it. Maker, twice: *"make juggernaut... be able to
		# dash up"*, then *"the brawler should be able to dash up as well just like the
		# sword saint"*.
		#
		# Kept rather than deleted: it is the honest home for a future verb that really
		# is meant to be ground-locked, and the note above is the argument for why one
		# would be. Nothing routes here today.
		"ground_locked_verb_placeholder":
			v.x = _dash_dir.x * _dash_speed
			v.y = 0.0 if is_on_floor() else minf(v.y + GRAVITY_FALL * delta, MAX_FALL)
			return v
	return _dash_dir * _dash_speed


## Afterimage colour, per verb — the cheapest possible way to make nine verbs read as
## nine different things at a glance. Falls back to the shared dash trail.
func _travel_ghost_color() -> Color:
	match _dash_verb:
		"ice_slide":
			return ICE_SLIDE_FROST_COLOR
		"arcane_phase":
			return ARCANE_PHASE_COLOR
		"radiant_step":
			return RADIANT_WAKE_COLOR
	return GHOST_COLOR


## The frame travel ENDS. Only the two verbs whose exit is part of their identity say
## anything here; the rest keep the old behaviour of leaving the velocity where the
## burst left it and letting the movement block decelerate.
func _end_travel() -> void:
	match _dash_verb:
		"charge":
			# IT CARRIES. Keep a share of the charge speed and suppress ground friction
			# for a beat — `_wall_jump_lock` is already the movement block's "do not
			# fight this momentum" gate, so this reuses it rather than adding a second
			# flag that means the same thing and drifts from it.
			velocity.x = _dash_dir.x * _dash_speed * CHARGE_EXIT_MOMENTUM
			_wall_jump_lock = maxf(_wall_jump_lock, CHARGE_MOMENTUM_LOCK)
		"surge":
			velocity.x = 0.0  # a siege engine stops exactly where it decided to stop


## Shadow blink: instant teleport BLINK_DISTANCE along the direction you are
## FACING — full 360°, phasing THROUGH geometry. Leaves a dark silhouette + violet
## poof at the origin, another poof + bright flash at the destination, and grants
## BLINK_IFRAME seconds of invulnerability. Buffered like dash/melee/blast; only
## reachable from the not-dashing path.
##
## ⚠ DIRECTION CHANGED TWICE, AND THE SECOND RULING REVERSES THE FIRST. Recorded in
## full because the two are easy to mistake for each other.
##
## FIRST (maker, mid-playtest): "blink should just be in the direction it is facing
## ... not just side to side." It read `_move_dir` then — assigned as
## `Vector2(signf(move_x), 0.0)`, a HORIZONTAL unit vector, ±1 on X and always 0 on Y
## — so the ability was structurally incapable of going anywhere but left or right.
## The complaint was the FLATNESS. The fix moved it to `_aim_dir`, which is 360°.
##
## SECOND (maker, this playtest): "dash should not be in the way it's facing but the
## movement on the joystick or walking, for all the characters, including Warlock's
## blink." That is a different axis entirely, and it wins: the WHOLE ROSTER now
## travels along the movement input, so blink and dash answer to the same thumb and a
## player never has to hold two directions to go one way.
##
## Both rulings are satisfied at once, which is why this is not a revert: the source
## is the 8-way movement VECTOR (`_vector`, including up and down), not `_move_dir`.
## It is 360° like the aim version and it is the stick like the new ruling. Aim
## survives only as the fallback for a frame where nothing is held, so a standing
## blink still fires where you are pointing rather than refusing.
##
## NOT AUTO-AIM. `_aim_dir` is raw player input (cursor / right stick / touch aim
## pad), resolved in `_physics_process` before anything reads it. Nothing here looks
## at where an enemy is, and the locked no-auto-aim rule is untouched — see
## tools/slice0_test_targeting.gd.
##
## STILL MOBILE-FIRST (D-011). Aim is a first-class touch input, not a mouse-only
## luxury: `_touch_aim()` routes the on-screen pad into the same `_aim_dir`. And
## because aim PERSISTS between frames, a thumb that is only on the move stick
## blinks along the last direction it aimed — which is also the way the figure is
## visibly facing, so the read is honest either way.
func _blink() -> void:
	# Brawler can't teleport — its R is a launcher UPPERCUT that pops enemies into
	# the air (double-jump after them to juggle).
	if String(_cfg.get("mobility2", "blink")) == "uppercut":
		_uppercut()
		return
	if _blink_cooldown_timer > 0.0:
		return
	var origin: Vector2 = global_position
	# WHERE YOU ARE MOVING — the same 8-way read `_begin_travel` uses, so the dash and
	# the blink cannot disagree about which way "up-right" is. Aim is the fallback for
	# a standing blink (nothing held), and RIGHT the last resort so it always fires.
	var dir: Vector2 = _vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if dir.length() <= 0.1:
		dir = _aim_dir
	if dir == Vector2.ZERO:
		dir = _move_dir
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	# Phase THROUGH geometry, but never REST in it (see BLINK_WALL_MASK's note).
	var dest: Vector2 = _safe_blink_destination(origin, origin + dir.normalized() * BLINK_DISTANCE)
	# REFUSED -> REFUNDED. Everything above this line is free; the cooldown and the
	# i-frames are spent BELOW it, so a blink with nowhere legal to land costs
	# nothing and can be re-aimed and pressed again immediately. The alternative —
	# charging 1.3 s for a body that did not move — is the failure mode that makes a
	# mobility button feel broken rather than blocked.
	if origin.distance_to(dest) < BLINK_MIN_TRAVEL:
		# A quiet, dim fizzle at the feet so the press reads as REFUSED rather than
		# as dropped input. Deliberately nothing like the arrival flash.
		CombatVfx.spawn_burst(
			get_parent(), origin, Color(0.3, 0.2, 0.4, 0.5), BLINK_BURST_END,
			6, 0.2, 20.0, 55.0, 1.0, 2.0
		)
		Sfx.play("blink", -14.0, 0.1, 0.6)
		return
	_blink_cooldown_timer = _cfg["blink_cd"]
	_blink_iframe_timer = BLINK_IFRAME
	# Shadow-poof where we WERE: dark fading silhouette + violet burst.
	rig.spawn_ghost(get_parent(), BLINK_SHADOW_COLOR, Vector2.ZERO, Vector2.ZERO, 0.35)
	CombatVfx.spawn_burst(
		get_parent(), origin, BLINK_BURST_START, BLINK_BURST_END,
		18, 0.35, 40.0, 110.0, 1.5, 3.0
	)
	global_position = dest
	velocity.y = 0.0  # don't inherit fall speed -> no "heavy gravity" right after a blink
	# Arrival poof: bigger burst + a quick bright flash on the rig.
	CombatVfx.spawn_burst(
		get_parent(), dest, BLINK_BURST_START, BLINK_BURST_END,
		24, 0.4, 60.0, 140.0, 1.5, 3.5
	)
	rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("blink", 0.0, 0.1)  # dedicated synth "vwip" teleport sound
	_net_send("bl", {"to": dest})


## BRAWLER uppercut (R) — a rising launcher: the hero hops and everything in a
## short forward range is popped UP (sets up an air-juggle with the double-jump).
func _uppercut() -> void:
	if _blink_cooldown_timer > 0.0:
		return
	_blink_cooldown_timer = maxf(_cfg["blink_cd"], 1.1)
	_net_send("uc")
	rig.set_facing(_aim_dir)
	rig.play(CharacterRig.State.KICK)
	velocity.y = -320.0  # the hero rises with the uppercut
	var face_x: float = signf(_aim_dir.x) if _aim_dir.x != 0.0 else 1.0
	# ⚠ TELEGRAPHED. The launcher resolved on the press frame while the rig was still
	# playing a KICK — the leap read as a wind-up the damage had already skipped — and
	# it left `BotDodge` nothing to perceive. The hero still rises immediately; only
	# the connect waits, which is also how a real uppercut reads. `ABILITY_TELL_LEAD`
	# is the one knob; 0.0 restores the press-frame hit.
	_telegraphed_ability({
		"pos": global_position + Vector2(face_x * 24.0, -10.0),
		"radius": UPPERCUT_REACH * 0.6,
		"windup": ABILITY_TELL_LEAD,
		"style": Telegraph.Style.DART,
		"aim": Vector2(face_x, -0.5), "reach": UPPERCUT_REACH,
	}, _resolve_uppercut.bind(face_x))


## The uppercut's actual hit. `face_x` is passed in rather than re-read, so turning
## during the lead cannot re-aim a launcher that has already committed.
func _resolve_uppercut(face_x: float) -> void:
	var hit_any: bool = false
	# A launcher is the one melee move whose whole point is VERTICAL, so an
	# origin-point test was the worst possible fit: it measured to a spot below the
	# head of the very thing it is trying to pop into the air. Silhouette-measured
	# now, in a wedge that is the forward half plus a small overlap behind — which is
	# what the old `signf(to.x) != face_x and absf(to.x) > 10.0` clause was
	# approximating for a body standing directly on top of you.
	for enemy: Node in SpellTargets.in_cone(global_position, Vector2(face_x, 0.0),
			UPPERCUT_REACH, UPPERCUT_DOT, get_tree().get_nodes_in_group(attack_group()),
			[self], self):
		if enemy.has_method("take_damage"):
			# ⚠ 18 + `_melee_damage`, AND THAT IS NOT A BUFF — it is the same total this
			# move has always dealt, made visible. The KICK animation used to land a
			# free undeclared melee hit on top of the 18 (measured: [18, 16] against a
			# recorder), and gating that off would have quietly cut a bottom-of-the-
			# roster class's launcher by nearly half. Reading `_melee_damage` rather
			# than the literal 34 keeps it tracking the class it belongs to.
			# ⚠ ONE EDGE MOVES: the free hit used melee's own cone, so a body inside
			# melee reach but outside this wedge used to take 16 and now takes nothing.
			enemy.take_damage(18 + _melee_damage)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(Vector2(face_x * 120.0, -470.0))  # POP up + slight away
		if enemy.has_method("apply_status"):
			enemy.apply_status(_element)
		hit_any = true
	CombatVfx.spawn_burst(
		get_parent(), global_position + Vector2(face_x * 20.0, -6.0),
		Color(1.0, 0.9, 0.5, 0.8), Color(1.0, 0.5, 0.15, 0.0), 12, 0.3, 60.0, 180.0
	)
	Sfx.play("melee_hit")
	if hit_any:
		Juice.hit_stop(0.06)
		Juice.shake_camera(5.0)


## SpellCaster's BLINK_STRIKE callback (duck-typed `blink_to`): vet the requested
## landing spot, actually move, and return where we ENDED UP so the blast is drawn
## at the real destination. Hero's own rule — never blink into a pit, a wall, or out
## of the room — stays owned here rather than leaking into the generic dispatcher.
##
## THE SPELL IS NOT REFUNDED WHEN THE ABILITY WOULD BE, and the split is deliberate.
## `_blink()` is PURE MOVEMENT: a blink that cannot move has delivered nothing, so it
## costs nothing. This spell's payload is the BLAST (see BlinkStrike's "REPOSITION +
## PUNCTUATION" note) — a Shadow Step that cannot find room to travel still detonates
## where you stand and still does its damage, which is a real outcome rather than a
## swallowed button. So the travel is dropped, not the cast: below `BLINK_MIN_TRAVEL`
## we simply do not move, and the caller draws the blast at our feet.
##
## CO-OP: a puppet is NOT displaced. Position on a non-authority peer comes from the
## MultiplayerSynchronizer, so writing `global_position` here would fight it and then
## snap back — the same rule `_replay_dash` documents for the dash. The vetted point
## is still RETURNED, so the remote copy of the spectacle draws its (already
## disarmed) blast where the owner is about to appear.
func blink_to(dest: Vector2) -> Vector2:
	var safe: Vector2 = _safe_blink_destination(global_position, dest)
	if _is_net_puppet():
		return safe  # replay is visual only; the synchronizer owns this body
	if global_position.distance_to(safe) < BLINK_MIN_TRAVEL:
		return global_position  # nowhere useful to go — blast at our feet
	global_position = safe
	velocity.y = 0.0
	_blink_iframe_timer = BLINK_IFRAME
	return safe


## Blink landing safety. Returns the point the body may legally REST on, which is
## `dest` in the common case and a slid-along-the-ray substitute otherwise. Returns
## `origin` when the whole ray is illegal; callers treat "moved less than
## BLINK_MIN_TRAVEL" as a refusal (see `_blink`), so the exact sentinel is never
## load-bearing on its own.
##
## The full rule — phase the path, vet only the resting spot, slide forward then
## backward — is written out at BLINK_WALL_MASK. The one thing worth repeating here:
## there is deliberately NO raycast from `origin` to `dest`. A segment test would
## report every legally-crossed wall as a block and turn the blink back into a dash.
func _safe_blink_destination(origin: Vector2, dest: Vector2) -> Vector2:
	var world: World2D = get_world_2d()
	if world == null:
		return dest  # headless / no physics world — leave as-is
	var shape: Shape2D = _blink_shape()
	if shape == null:
		return dest
	var space: PhysicsDirectSpaceState2D = world.direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = BLINK_WALL_MASK
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	var span: Vector2 = dest - origin
	if span.length() < 1.0:
		return dest
	var dir: Vector2 = span.normalized()
	# Is this world walled at all? Asked ONCE, of the spot we are standing on — see
	# `_enclosed`. An open stage answers false and the bounds rule switches itself
	# off for the whole blink, which is why the versus terraces and the headless
	# suites (no walls anywhere) behave exactly as they did before.
	var bounded: bool = _enclosed(space, origin)
	if _blink_spot_legal(space, q, dest, bounded):
		return dest  # clear — the common case
	# Blocked: look for daylight just PAST whatever the endpoint landed in. This is
	# the branch that makes "goes through stuff" true when you aim INTO cover rather
	# than past it — you come out the far side instead of bouncing off.
	var d: float = BLINK_PROBE_STEP
	while d <= BLINK_PROBE_EXTRA:
		var pf: Vector2 = dest + dir * d
		if _blink_spot_legal(space, q, pf, bounded):
			return pf
		d += BLINK_PROBE_STEP
	# ...else slide back toward the origin, which is legal by construction. Walking
	# from the far end means we take the FURTHEST legal point, so you still travel as
	# far as the map allows instead of being dumped next to your own feet. This is
	# also the branch that catches "aimed through the outer wall": every candidate
	# outside the room fails the bounds rule, and the first one that passes is the
	# spot just inside it.
	var max_back: float = span.length()
	d = BLINK_PROBE_STEP
	while d <= max_back:
		var pb: Vector2 = dest - dir * d
		if _blink_spot_legal(space, q, pb, bounded):
			return pb
		d += BLINK_PROBE_STEP
	return origin  # nowhere legal on the entire ray — refused


## The three rules a landing spot must satisfy, in cheapest-first order. `q` is
## reused across candidates (only its transform changes), which is why this takes it
## rather than building one per call.
func _blink_spot_legal(
	space: PhysicsDirectSpaceState2D, q: PhysicsShapeQueryParameters2D,
	at: Vector2, bounded: bool
) -> bool:
	q.transform = Transform2D(0.0, at)
	if not space.intersect_shape(q, 1).is_empty():
		return false  # 1. never INSIDE solid geometry
	if _dest_in_pit(at):
		return false  # 2. never over a ring-out pit you did not choose
	if bounded and not _enclosed(space, at):
		return false  # 3. never OUTSIDE the room
	return true


## True when `at` is enclosed by geometry — a cheap stand-in for "inside the room"
## that costs nothing to keep in sync with the room, because it asks the room itself.
##
## WHY NOT READ THE ROOM RECT. Arena builds its four walls from `LayoutDef.room_size`
## and the versus stage has no walls at all, so any number Hero cached would be a
## second source of truth that drifts the first time a floor resizes. Instead: fire
## one ray along each axis. A point inside a closed room hits a wall in all four
## directions; a point in the void outside it misses in at least one. That is exact
## for the shape Arena actually builds (four full-span walls) and self-disabling
## everywhere else — an open stage fails the test AT THE ORIGIN, and the caller then
## skips the rule entirely rather than refusing every blink on the map.
##
## `hit_from_inside` is on so a point buried in a wall reports enclosed rather than
## leaking out through its own collider; rule 1 above has already rejected it anyway.
func _enclosed(space: PhysicsDirectSpaceState2D, at: Vector2) -> bool:
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var r := PhysicsRayQueryParameters2D.create(
			at, at + dir * BLINK_BOUNDS_RAY, BLINK_WALL_MASK)
		r.collide_with_areas = false
		r.hit_from_inside = true
		r.exclude = [get_rid()]
		if space.intersect_ray(r).is_empty():
			return false
	return true


## True if `pos` lands inside a ring-out PIT (a StageHazard in PIT mode), plus a
## margin off the lip. Loose group + property lookup so Hero doesn't hard-depend on
## StageHazard. Headless (no stage_hazard group) -> always false, so blink tests
## are unaffected. Mode.PIT == 0.
func _dest_in_pit(pos: Vector2) -> bool:
	for h: Node in get_tree().get_nodes_in_group("stage_hazard"):
		if not h is Node2D or int(h.get("mode")) != 0:
			continue
		var size_v: Variant = h.get("zone_size")
		if not size_v is Vector2:
			continue
		var half: Vector2 = (size_v as Vector2) * 0.5 + Vector2(BLINK_PIT_MARGIN, BLINK_PIT_MARGIN)
		var rel: Vector2 = pos - (h as Node2D).global_position
		if absf(rel.x) <= half.x and absf(rel.y) <= half.y:
			return true
	return false


## The hero's own collision shape (found at runtime — no hard-coded node name).
func _blink_shape() -> Shape2D:
	for c: Node in get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null:
			return (c as CollisionShape2D).shape
	return null


## The LMB PRIMARY — dispatched per class so no two classes attack the same way:
## melee_combo (Brawler punch/kick, no magic), heavy_swing (Juggernaut wide slow
## hammer), frost_cone (Cryomancer chilling cone), or a bolt with per-class flavour
## flags (plain / heal / drain / chain / burst). This is the core "classes feel
## different, not just different spells" fix.
func _cast() -> void:
	# CO-OP: the LMB primary is the highest-traffic thing a hero does, and it was
	# entirely invisible to the other player — enemies simply lost HP for no reason.
	# Broadcast at the DISPATCHER rather than in each of the four variants below, so
	# a fifth primary can never be added without crossing the wire.
	_net_send("pr")
	match String(_cfg.get("primary", "bolt")):
		"melee_combo":
			_primary_melee_combo()
		"heavy_swing":
			_primary_heavy_swing()
		"frost_cone":
			_primary_frost_cone()
		_:
			_primary_bolt()


## Ranged bolt with per-class flavour: bolt_heal (Cleric/Warlock lifesteal),
## bolt_chain (Stormcaller arc), bolt_burst (Shadowblade flurry, spread shots).
func _primary_bolt() -> void:
	_cast_cooldown_timer = _cfg["cast_cd"]
	# The bolt goes EXACTLY where the player is pointing. It used to be bent toward
	# an enemy inside a forgiveness cone, which is aim assist by another name: the
	# locked rule is that hitting is the shooter's skill and dodging is the target's,
	# and a cone that quietly corrects a near-miss steals from both sides of that.
	# Forgiveness now has to come from the spell's SHAPE (width/arc/burst spread),
	# never from the engine steering it after release.
	var base_dir: Vector2 = _aim_dir.normalized() if _aim_dir != Vector2.ZERO else facing
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.5, _element)  # quick hand-flick tell
	var origin: Vector2 = rig.get_weapon_tip()
	var burst: int = int(_cfg.get("bolt_burst", 1))
	var spread: float = float(_cfg.get("bolt_spread", 0.0))
	for i: int in maxi(burst, 1):
		# Fan a burst symmetrically around the aim (single shot -> no offset).
		var off: float = 0.0 if burst <= 1 else (float(i) - float(burst - 1) * 0.5) * spread
		var dir: Vector2 = base_dir.rotated(off)
		var spell: Area2D = SPELL_SCENE.instantiate()
		get_parent().add_child(spell)
		spell.global_position = origin
		spell.launch(dir)
		if spell.has_method("set_element_color"):
			spell.call("set_element_color", _element_color)
		spell.set("element_id", _element)
		if bool(_cfg["throw_blade"]):
			spell.set("damage", int(_cfg["blade_damage"]))
		# WHOSE SIDE THE BOLT IS ON. A method rather than a field write because
		# it also opens the hero collision layer on the projectile: a
		# hero-hostile bolt that never gets that mask bit passes clean through
		# its target with damage code that looks perfectly correct.
		spell.call("set_hostile_group", attack_group())
		# Caster is set for EVERY class's bolt (not just heal-flavoured ones) so the
		# friendly-fire guard in Spell.gd can always exclude the caster from their
		# own bolt — MAGE/STORMCALLER/ROGUE bolts were previously spawning with
		# caster == null and could hit their own thrower.
		spell.set("caster", self)
		# CO-OP: a puppet's bolt is a PICTURE of someone else's shot. It flies, trails
		# and bursts identically and hurts no fighter — the real one is already
		# resolving on its owner's peer. See Spell.visual_only.
		spell.set("visual_only", _is_net_puppet())
		# ...and its WEIGHT. Without this the bolt reports SpellTier.DEFAULT_WEIGHT
		# (HEAVY), so a free, spammable primary would trade evenly in a clash against
		# a committed heavy spell, and would be read as HEAVY by the deflect window
		# fraction. A basic cast belongs on the QUICK shelf.
		spell.set("spell_tier", SpellTier.Tier.QUICK)
		# Flavour flags.
		var heal: int = int(_cfg.get("bolt_heal", 0))
		if heal > 0:
			spell.set("heal_on_hit", heal)
		var chain: int = int(_cfg.get("bolt_chain", 0))
		if chain > 0:
			spell.set("chain_count", chain)
	Sfx.play("cast", 0.0, 0.08)
	Juice.shake_camera(1.0)
	_notify_element_used()


## BRAWLER primary — a punch→punch→KICK melee combo that steps you forward. No
## projectile. The melee cooldown gates the cadence, so holding LMB auto-combos;
## every 3rd swing is a launcher kick. Reuses the rig PUNCH/KICK + hit_frame path.
func _primary_melee_combo() -> void:
	if _melee_cooldown_timer > 0.0:
		return
	rig.set_facing(_aim_dir)
	_melee()  # alternates PUNCH/KICK via _melee_kick_next, sets _melee_cooldown, swing sfx
	# Step INTO the combo so the boxer walks his punches forward.
	if _aim_dir.x != 0.0:
		velocity.x = signf(_aim_dir.x) * 200.0


## JUGGERNAUT primary — a slow, wide overhead hammer swing that staggers a crowd.
## Wide arc + big knockback come from the per-class melee params (configure_class);
## the slow _melee_cd is the commitment.
func _primary_heavy_swing() -> void:
	if _melee_cooldown_timer > 0.0:
		return
	rig.set_facing(_aim_dir)
	rig.play(CharacterRig.State.PUNCH)
	# This path never calls `_melee`, and its damage IS the rig hit frame — so it has
	# to declare the swing itself or it would stop dealing any. See _on_melee_hit_frame.
	_swing_window = SWING_WINDOW
	# Smaller wind-up (maker: "make the charge up for the heavys just slightly smaller").
	rig.cast_gesture(CharacterRig.GestureKind.STOMP, 0.4, _element)
	# STEP INTO the swing so the heavy actually closes + CONNECTS (maker: the heavy
	# attacks "aren't working" — they were whiffing at its short reach). The lunge +
	# the wider reach (CLASS_CONFIG) make the hammer land instead of swinging air.
	if _aim_dir.x != 0.0:
		velocity.x = signf(_aim_dir.x) * 190.0
	_melee_cooldown_timer = _melee_cd
	Sfx.play("melee_swing", 0.0, 0.12)
	# THE CRESCENT. Maker: *"each swing of the sword basic attack should shoot out a
	# short curved attack with low range to explain why the range is big for its basic
	# attack"* — and that is exactly what it does: it draws the reach the melee hitbox
	# ALREADY has. It carries no damage of its own, deliberately (see `SwingArc`), so
	# the roster's slowest swinger does not quietly become its highest per-swing.
	SwingArc.spawn(get_parent(), rig.get_weapon_tip(),
		_aim_dir if _aim_dir != Vector2.ZERO else facing, _melee_range, _element_color)
	# ⚠ AND THE TELL — this path never calls `_melee`, so it was missed by the clash
	# declaration AND by the tell that goes with it. `SwingArc` above is explicitly NOT
	# one: its own header says it is explanatory garnish, it joins no group, and it is
	# dropped entirely when the arena is over its vfx budget. It is also spawned AT the
	# swing, so it has never offered a single frame of lead. This is the Juggernaut's
	# missing tell, and it is the reason a heavy hammer blow arrived unannounced.
	if not _replaying:
		_publish_swing_tell(CharacterRig.State.PUNCH)


## CRYOMANCER primary — a short-range FROST CONE (no projectile): every enemy in
## the forward arc is chilled (2nd stack freezes) + lightly shoved. Forces mid-range.
func _primary_frost_cone() -> void:
	if _cast_cooldown_timer > 0.0:
		return
	_cast_cooldown_timer = _cfg["cast_cd"]
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.6, _element)  # frost coats the hand
	const CONE_RANGE: float = 118.0
	const CONE_COS: float = 0.5  # ~60° half-angle
	## ⚠ 12 -> 19. Maker: *"cryomancer needs a buff as well the spells make sure they
	## actually do something"* — and the arithmetic agreed before the eye did: 12 on a
	## 0.34 s cooldown is 35 DPS against a roster mean of 56, the LOWEST primary in the
	## game, on the class that also has to be in cone range to use it. The five bolt
	## classes get 60 DPS at 560 px; this asks you to walk into the fight for less.
	## 19 puts it just over the mean, which is what a short-range primary should be
	## worth for the risk it carries.
	const CONE_DAMAGE: int = 19
	# ⚠ TELEGRAPHED, AND THIS WAS THE ONLY HITSCAN PRIMARY IN THE GAME WITH NOTHING TO
	# PERCEIVE. It resolved in the same synchronous call as the press while the rig was
	# still playing a CAST and coating the hand in frost — so the picture promised a
	# wind-up that the damage had already skipped, and `BotDodge` had no object to read.
	# The lead is `ABILITY_TELL_LEAD`; set that to 0.0 to restore the press-frame hit.
	_telegraphed_ability({
		"pos": global_position + _aim_dir.normalized() * CONE_RANGE * 0.5,
		"radius": CONE_RANGE * 0.5,
		"windup": ABILITY_TELL_LEAD,
		"style": Telegraph.Style.MUZZLE,
		"aim": _aim_dir, "reach": CONE_RANGE,
	}, _resolve_frost_cone.bind(_aim_dir, CONE_RANGE, CONE_COS, CONE_DAMAGE))


## The frost cone's actual hit, split out so the tell above owns the timing. Takes the
## aim as an ARGUMENT rather than reading `_aim_dir`: the cone is fixed at the press,
## exactly like a telegraph lane, so spinning during the lead cannot re-point it.
func _resolve_frost_cone(aim: Vector2, cone_range: float, cone_cos: float,
		cone_damage: int) -> void:
	var hit_any: bool = false
	# The cone is now measured against the DRAWN body and line-of-sight filtered,
	# through the same selector every spell uses. It was the clearest instance of the
	# head bug in a primary attack: a frost cone aimed at head height resolved
	# against an origin ~10 px lower and simply did not connect.
	for enemy: Node in SpellTargets.in_cone(global_position, aim, cone_range,
			cone_cos, get_tree().get_nodes_in_group(attack_group()), [self], self):
		var to: Vector2 = (enemy as Node2D).global_position - global_position
		if enemy.has_method("take_damage"):
			enemy.take_damage(cone_damage)
		if enemy.has_method("apply_status"):
			enemy.apply_status(_element)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(to.normalized() * 160.0)
		hit_any = true
	# Frost fan VFX along the aim.
	var fan_at: Vector2 = global_position + aim * cone_range * 0.55
	CombatVfx.spawn_burst(
		get_parent(), fan_at, Color(0.85, 0.97, 1.0, 0.9), Color(0.5, 0.8, 1.0, 0.0),
		20, 0.32, 120.0, 260.0, 0.6, 1.8
	)
	Sfx.play("cast", -2.0, 0.06)
	if hit_any:
		Juice.shake_camera(2.0)
	_notify_element_used()


## Heal the hero (Cleric/Warlock lifesteal, Cleric heal-nova). Clamps to max_hp.
func heal(amount: int) -> void:
	if amount <= 0 or hp >= max_hp:
		return
	hp = mini(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)
	rig.flash_color(Color(0.6, 1.0, 0.7), 0.08)  # a soft green heal tick


## The Q slot — dispatched on the class's AoE variant. Every variant carries the
## hero's ACTIVE element (so a Brawler who cycles to Ice throws an ice-punch).
func _blast() -> void:
	_blast_cooldown_timer = _cfg["blast_cd"]
	# CO-OP: same reasoning as `_cast` — broadcast at the dispatcher so all eight
	# per-class Q spectacles replicate without eight separate edits.
	_net_send("q")
	_self_recoil(80.0)  # the giant blast kicks the caster back
	match String(_cfg["aoe"]):
		"nova":
			_spawn_nova()          # rogue whirlwind
		"fist_shock":
			_fire_punch()          # brawler — lunging elemental shockwave
		"ground_slam":
			_ground_slam()         # juggernaut — self-centred crater
		"arcane_meteor":
			_arcane_meteor()       # arcanist — arcane star-fall barrage
		"consecrate":
			_consecrate()          # cleric — hallowed ground field
		"ice_shards":
			_ice_shards()          # cryomancer — homing frost shard spray
		"call_lightning":
			_call_lightning()      # stormcaller — lightning strike column
		"curse_chain":
			_curse_chain()         # warlock — leaping shadow chain
		_:
			_meteor_blast()        # placed giant blast (fallback)


## Placed giant blast: lands where the cursor points, clamped to a max cast range
## so it stays a skill-shot, not a whole-stage snipe.
func _meteor_blast() -> void:
	var to_target: Vector2 = _aim_point() - global_position
	if to_target.length() > BLAST_MAX_RANGE:
		to_target = to_target.normalized() * BLAST_MAX_RANGE
	var target_pos: Vector2 = global_position + to_target
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.set("element_id", _element)
	_stamp_faction(blast)
	# OWNERSHIP. A spectacle with no caster reports as "unowned", which satisfies
	# neither `require_owner: "same"` nor `"different"` — so it matches NO clash row
	# and is silently inert in the entire reaction system. Nothing errors; the spell
	# simply never reacts with anything, which is the single most repeated bug in
	# this codebase.
	blast.set("caster_node", self)
	blast.detonate_at(target_pos)
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.65, _element)  # arm gathers, lobs the blast


## FIRE PUNCH — the Brawler's Q. A lunging straight that erupts an elemental
## shockwave just in front of the fist: instant (no windup), tight radius, HUGE
## knockback + the active element's ailment. Reads as a committed melee blast.
func _fire_punch() -> void:
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.PUNCH)
	rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.8, _element)  # the FIST ignites
	# A short forward lunge so the punch drives INTO the target.
	velocity.x = signf(_aim_dir.x) * 300.0 if _aim_dir.x != 0.0 else velocity.x
	var center: Vector2 = global_position + _aim_dir.normalized() * 44.0
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.call("configure", {
		# ⚠ 30 + `_melee_damage`, AND THAT IS NOT A BUFF. The PUNCH animation this
		# plays for flavour used to land a free undeclared melee hit on top of the
		# blast (measured: [30, 16] against a recorder). Same total, now in one number.
		"target_group": String(attack_group()), "damage": 30 + _melee_damage,
		"radius": 66.0, "knockback": 430.0, "element_id": _element,
		"windup": ABILITY_TELL_LEAD,
	})
	blast.set("caster_node", self)  # unowned = inert in the reaction layer (see _blast)
	# ⚠ `detonate_at`, NOT `detonate_now`. The header of `detonate_now` reserves it for
	# callers that "already ran their own tell, or are a melee-range punch whose own
	# ANIMATION is the tell" — and an animation is exactly the thing a dodging brain
	# cannot see. This is the same tested telegraphed path the placed giant blast uses,
	# so it costs no new code and brings a drawn danger ring with it.
	blast.call("detonate_at", center)
	# The PUNCH beat, graded off the shared tier ladder rather than a bare 0.8 — a
	# punch is a physical concussion, so it lands on BLOWOUT, and it now reads as
	# lighter than an ult instead of matching one. Localized on the blast, because
	# an unpositioned frame whites out screen centre wherever the hit actually was.
	Juice.tier_frame(SpellTier.Tier.HEAVY, center, _element)


## GROUND SLAM — the Juggernaut's Q. A small hop then a self-centred crater: wide
## radius, heavy knockback + the active element's ailment (Stagger by default).
func _ground_slam() -> void:
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.STOMP, 0.8, _element)  # fist drives down
	velocity.y = -240.0  # a small hop into the slam
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.call("configure", {
		"target_group": String(attack_group()), "damage": 34, "radius": 98.0,
		"knockback": 380.0, "element_id": _element,
		"windup": ABILITY_TELL_LEAD,
	})
	blast.set("caster_node", self)  # unowned = inert in the reaction layer (see _blast)
	# Telegraphed, for the reason given on the fire punch. This one is the Juggernaut's,
	# and "the Juggernaut's punches have no tell" is on the maker's own list.
	blast.call("detonate_at", global_position)


## Energy nova: instant self-centered shockwave. No telegraph — the panic
## button fires the moment the press lands (buffered like blast/blink). Mage
## only; the rogue's whirlwind reuses _spawn_nova through _blast.
func _nova() -> void:
	if not bool(_cfg["has_nova"]):
		return
	if _nova_cooldown_timer > 0.0:
		return
	_nova_cooldown_timer = NOVA_COOLDOWN
	_net_send("nv")
	_spawn_nova()


func _spawn_nova() -> void:
	var nova: Node2D = NOVA_SCENE.instantiate()
	get_parent().add_child(nova)
	nova.set("element_id", _element)
	_stamp_faction(nova)
	nova.call("activate_at", global_position)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.6, _element)  # arms fling out the nova


## Point a spectacle this file spawned DIRECTLY at this hero's faction.
##
## The per-class Q's below bypass `SpellCaster.cast` (they hand-build their
## spectacle from a `load()`ed script), so they miss `SpellCaster._stamp` and
## would otherwise keep the `"enemy"` default forever — the exact silent gap that
## made hero-vs-hero inert. Both property spellings are written for the same
## reason and with the same safety as the stamp: `set()` on a property a
## spectacle has not declared is a silent no-op, so a spectacle that hard-codes
## its target group today simply starts obeying this the day it grows the field.
## ⚠ THIS USED TO STAMP ONLY THE GROUP, AND THAT WAS TWO SILENT BUGS IN ONE.
##
## The seven Q spectacles below are hand-built here rather than going through
## `SpellCaster._stamp`, which writes element + tier + CASTER + group on all its
## arms. This helper wrote the group and nothing else, so `caster_node` stayed
## null on every one of them — and `set()` on a property a node has not declared
## is a silent no-op, so nothing ever complained.
##
## 1. THE MAKER'S NOVA BUG. Both of `SpellTargets`' self-exclusion layers read
##    `caster_node`, and both correctly no-op when it is null: the skip list was
##    `[null]` and `owner_of()` answered null. That was harmless while these
##    scanned `"enemy"` — a hero is not in `"enemy"`. The moment friendly fire
##    pointed the scan at `"mortal"`, the caster was a legal target standing at
##    range zero of their own nova. Reported as nova because that is the one
##    centred on your own feet; meteor, zone, orbs, ray and chain had it too.
## 2. THEY WERE INERT IN THE REACTION SYSTEM. `reaction_owner()` returns null,
##    which satisfies neither `require_owner: "same"` nor `"different"`, so these
##    seven matched NO clash row. They could not fuse, annihilate or be overpowered
##    by anything, and nothing errored — the exact failure mode `docs/NEXT-SESSION.md`
##    calls "the one rule that keeps finding bugs".
##
## Fixed at the helper rather than at six call sites, so a spectacle added here
## later cannot inherit the omission.
func _stamp_faction(node: Node) -> void:
	node.set("target_group", String(attack_group()))
	node.set("_target_group", String(attack_group()))
	node.set("caster_node", self)


## Cursor target for a placed Q, clamped to BLAST_MAX_RANGE so it stays a skill-shot.
func _aoe_target() -> Vector2:
	var to_target: Vector2 = _aim_point() - global_position
	if to_target.length() > BLAST_MAX_RANGE:
		to_target = to_target.normalized() * BLAST_MAX_RANGE
	return global_position + to_target


# ---- Per-class DISTINCT Q spectacles (maker: "Q's are just reworks of each other
# — give each CLASS a distinct epic Q, not a recolored blast"). Each reuses a
# proven spectacle scene in a config distinct from that class's G signature, and
# carries the hero's ACTIVE element. Runtime-load()ed (never preload) so the
# headless slice harness that compiles Hero doesn't early-compile these.

## ARCANIST Q — Arcane Storm: a short barrage of arcane meteors rains on the cursor.
func _arcane_meteor() -> void:
	var meteor: Node2D = (load("res://scripts/combat/MeteorSigil.gd") as GDScript).new()
	get_parent().add_child(meteor)
	meteor.set("element_id", _element)
	_stamp_faction(meteor)
	meteor.call("rain", _aoe_target(), _element_color, 92.0, 22, 5, Elements.effect_name(_element))
	rig.set_aim(Vector2.UP)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.7, _element)


## CLERIC Q — Consecrate: hallowed ground pulses holy damage where the cursor points.
func _consecrate() -> void:
	var zone: Node2D = (load("res://scripts/combat/ZoneSpell.gd") as GDScript).new()
	get_parent().add_child(zone)
	zone.set("element_id", _element)
	_stamp_faction(zone)
	zone.call("open", _aoe_target(), _element_color, 98.0, 11, Elements.effect_name(_element), 4.0)
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.6, _element)


## CRYOMANCER Q — Ice Shards: a spray of homing frost shards toward the aim.
func _ice_shards() -> void:
	var orbs: Node2D = (load("res://scripts/combat/RuneOrbs.gd") as GDScript).new()
	get_parent().add_child(orbs)
	orbs.set("element_id", _element)
	_stamp_faction(orbs)
	orbs.call("launch", rig.get_weapon_tip(), _aim_dir.normalized(), _element_color, 6, 18, Elements.effect_name(_element))
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.7, _element)


## STORMCALLER Q — Call Lightning: a bolt column crashes down on the cursor.
func _call_lightning() -> void:
	var ray: Node2D = (load("res://scripts/combat/DivineRay.gd") as GDScript).new()
	get_parent().add_child(ray)
	ray.set("element_id", _element)
	_stamp_faction(ray)
	ray.call("strike", _aoe_target(), _element_color, 74.0, 34, Elements.effect_name(_element))
	rig.set_aim(Vector2.UP)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.7, _element)


## WARLOCK Q — Curse Chain: a shadow bolt leaps enemy-to-enemy from the aim.
func _curse_chain() -> void:
	var ch: Node2D = (load("res://scripts/combat/ChainBolt.gd") as GDScript).new()
	get_parent().add_child(ch)
	ch.set("element_id", _element)
	_stamp_faction(ch)
	ch.call("chain", rig.get_weapon_tip(), _aim_dir.normalized(), _element_color, 4, 240.0, 30, Elements.effect_name(_element))
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.7, _element)


## Open the perfect-timing parry window (rogue only, off cooldown). The reward
## (ding + reflect) only fires if a bolt actually arrives during the window —
## see try_parry(). The opening itself is a quick blade-flash tell.
func _try_parry_start() -> void:
	if not bool(_cfg["can_parry"]):
		return  # class can't parry (mage)
	if _parry_cooldown_timer > 0.0:
		return
	_parry_window_timer = _parry_window_len
	_parry_cooldown_timer = PARRY_COOLDOWN
	_net_send("py")
	# The Stick-Fight block: a white curved shield SHELL thrown up in the aim
	# direction (the tell), plus an arm-raise. No omni flash/burst.
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.set_parry(_aim_dir, PARRY_SHIELD_TIME)
	Sfx.play("melee_swing", -2.0, 0.1)


## Called by an incoming enemy bolt as it reaches the hero. If the parry window is
## open, send the bolt back out ALONG THE SHIELD'S FACING — i.e. wherever the
## player is aiming — pay out the reward juice (bright ding + hitstop + flash), and
## return true; the bolt keeps flying, now hostile to enemies. One reflect per window.
##
## It used to redirect at the nearest enemy, which made a parry a homing missile:
## you only had to get the TIMING right and the engine picked the victim. Two
## honest options were on the table — bounce it straight back along the incoming
## line (return-to-sender), or send it along the defender's aim. The aim wins,
## because the incoming line is chosen by the ATTACKER, so return-to-sender still
## leaves the defender with nothing to steer. Aim makes a parry two skills stacked:
## time the window AND have the shield pointed where you want the bolt to go. It
## also matches what is already on screen — _try_parry_start throws the shell up in
## _aim_dir, so the bolt leaving along that same line is the picture you just saw.
func try_parry(proj: Node) -> bool:
	# Two guards, one answer. The press-window classes consume their window on a
	# reflect (one per press); the BLADE ring does NOT — its ~0.09 s perfect band is
	# already the whole limit, and consuming on top would mean a wall of arrows costs
	# a Swordsaint one deflect and then hits them with the rest, which is the
	# opposite of what holding a blade in the way looks like.
	var ring_perfect: bool = _guard != null and _guard.can_reflect()
	if _parry_window_timer <= 0.0 and not ring_perfect:
		return false
	if not is_instance_valid(proj) or not proj.has_method("reflect"):
		return false
	var dir: Vector2 = _aim_dir.normalized() if _aim_dir != Vector2.ZERO else facing
	proj.reflect(dir, _element_color)
	# One counter for all three deflect paths — see SpellDeflect.note_deflect.
	SpellDeflect.note_deflect(self)
	Sfx.play("ding", 2.0, 0.02)  # the whole payoff — a crisp, loud parry ding
	Juice.hit_stop(0.09)
	Juice.shake_camera(4.0)
	# Snap the shield toward where the bolt was sent — a bright deflect flourish.
	rig.set_parry(dir, PARRY_SHIELD_TIME)
	rig.flash_color(PARRY_FLASH_COLOR, 0.1)
	if not ring_perfect:
		_parry_window_timer = 0.0
	return true


## SpellDeflect's victim contract. A held BLADE guard reports as parrying whenever
## it is doing ANYTHING — a perfect read or the weaker sustained bottom-out — so a
## spell that only chips through a sustain still routes through the deflect path
## and still reads as "I blocked that".
func is_parrying() -> bool:
	if _parry_window_timer > 0.0:
		return true
	return _guard != null and _guard.quality() != ParryRing.Quality.NONE


## SpellDeflect's optional freshness hook, and the ONE place the two guard shapes
## genuinely differ in outcome.
##
## The press-window classes return 1.0 whenever their window is open. That is not
## laziness — it preserves TODAY'S behaviour exactly: Hero previously had no
## `parry_freshness` at all, and `SpellDeflect.would_deflect` treats a missing
## method as fully lenient. Returning a decaying value here would silently make
## every ult in the game far harder for eight shipped classes to block, under cover
## of adding a ninth.
##
## The BLADE ring reports `ParryRing.freshness()`, which is 1.0 on a PERFECT read
## and 0.0 on a SUSTAIN. Against `SpellDeflect.WINDOW_ULT` (0.22) only the perfect
## read clears the bar, so the asymmetry falls out of the ring rather than being
## invented here: a Swordsaint can eat an ult, but only by closing the ring exactly
## on it — holding a guard up will never do it.
func parry_freshness() -> float:
	if _parry_window_timer > 0.0:
		return 1.0
	return _guard.freshness() if _guard != null else 0.0


## A non-travelling spell was eaten by the guard (SpellDeflect's optional hook).
## Strike the pose toward it; the bank is handled in take_damage, which is the only
## place that knows how much was turned away.
func on_spell_deflected(dir: Vector2) -> void:
	if is_instance_valid(rig):
		rig.set_parry(dir if dir != Vector2.ZERO else _aim_dir, PARRY_SHIELD_TIME)
		rig.flash_color(PARRY_FLASH_COLOR, 0.1)


# --------------------------------------------------------------- BLADE GUARD
## Per-frame guard handling for a `defense: "held_guard"` class. Press to bloom the
## ring, hold to close it, release to cash whatever it banked.
##
## The ring's own clock is ticked at the top of `_physics_process` (so the re-arm
## runs even while committed); this is only input, pose and the deflect sweep.
func _process_blade_guard(delta: float) -> void:
	if is_dashing:
		return
	if _just(&"parry"):
		if _guard.press():
			_guard_bank = 0
			_guard_hits = 0
			# The tell is the same Stick-Fight shell every other class throws up, so
			# an opponent reads "they are guarding" identically whoever it is. What
			# differs is what happens next, not what it looks like starting.
			rig.set_aim(_aim_dir)
			rig.set_parry(_aim_dir, ParryRing.SHRINK_TIME + 0.2)
			Sfx.play("melee_swing", -4.0, 0.14)
	elif _released(&"parry"):
		_release_blade_guard()
	if _guard.held:
		# Hold the plant: the blade tracks the aim so the guard is directional, and
		# the shell is refreshed so it never blinks out mid-hold.
		rig.set_aim(_aim_dir)
		rig.set_parry(_aim_dir, 0.12)
		rig.play(CharacterRig.State.CAST)
		_guard_deflect_sweep()
		# Auto-cash at the bank limit. Holding past three turned hits would let a
		# Swordsaint stand in a barrage and walk out with a capped return for free;
		# forcing the release makes the third block the DECISION point.
		if _guard_hits >= GUARD_BANK_HITS:
			_release_blade_guard()


## Let go. Cash the bank as an unsheathe cut, then start the ring's re-arm.
func _release_blade_guard() -> void:
	if _guard == null or not _guard.held:
		return
	var banked: int = _guard_bank
	_guard.release()
	_guard_bank = 0
	_guard_hits = 0
	if banked > 0:
		_unsheathe_cut(banked)


## THE PAYMENT. A short line along the aim carrying `banked * GUARD_RETURN_MULT`.
##
## A LINE and not a circle, on purpose: an omni-burst would make the guard a
## panic button that punishes everyone who happened to be nearby, whereas a line
## means you must still be pointed at the thing you blocked. It is aimed with
## `_aim_dir`, so it is a real aim decision and never an auto-target.
func _unsheathe_cut(banked: int) -> void:
	# ⚠ + `_melee_damage`, AND THAT IS NOT A BUFF. The PUNCH this plays for the draw
	# used to land a free undeclared melee hit on top of the cut — measured [72, 37]
	# against a recorder, i.e. a THIRD of the move. Same total, now in one number, on a
	# class sitting at exactly 50% that must not be nerfed by a bookkeeping fix.
	# ⚠ ONE EDGE MOVES: the free hit used melee's cone and this cut is a LINE, so a body
	# beside the line but inside melee reach used to take the 37 and now takes nothing.
	var dmg: int = int(round(float(banked) * GUARD_RETURN_MULT)) + _melee_damage
	var dir: Vector2 = _aim_dir.normalized() if _aim_dir != Vector2.ZERO else facing
	rig.set_aim(dir)
	rig.play(CharacterRig.State.PUNCH)
	var pool: Array = get_tree().get_nodes_in_group(attack_group())
	pool.append_array(get_tree().get_nodes_in_group("destructible"))
	# Silhouette-aware, line-of-sight filtered — the same selector every spell now
	# uses, so the cut cannot reach a body through a wall and cannot pass through a
	# head without registering.
	var hit_any: bool = false
	for n: Node in SpellTargets.on_line(global_position, dir, GUARD_CUT_RANGE,
			GUARD_CUT_HALF_WIDTH, pool, [self], self):
		if n.is_in_group("destructible"):
			if n.has_method("take_damage"):
				n.call("take_damage", dmg)
			hit_any = true
			continue
		if n.has_method("take_damage"):
			n.call("take_damage", dmg)
		if n.has_method("apply_knockback"):
			n.call("apply_knockback", dir * GUARD_CUT_KNOCKBACK)
		hit_any = true
	CombatVfx.spawn_burst(get_parent(), global_position + dir * GUARD_CUT_RANGE * 0.55,
		Color(1.0, 0.98, 0.9, 0.95), Color(_element_color.r, _element_color.g, _element_color.b, 0.0),
		20, 0.3, 140.0, 340.0, 0.8, 2.4, 0.0, 0.0, true)
	Sfx.play("melee_hit", 2.0, 0.08)
	Juice.on_hit({
		"hitstop": 0.08 if hit_any else 0.03, "shake": 9.0 if hit_any else 3.0,
		"dir": dir, "kick": MELEE_CAMERA_KICK,
	})


## THE DRAG IS THE DEFLECT. While the ring is in its PERFECT band, anything that
## physically travels and touches the blade is turned — no separate button, no
## second timer. Only travelling things: a beam or a meteor has nothing to send
## back, so those go through `SpellDeflect.resolve()` on the damage path instead
## (that file's doctrine, and why both groups are not swept here).
func _guard_deflect_sweep() -> void:
	if not _guard.can_reflect():
		return
	var dir: Vector2 = _aim_dir.normalized() if _aim_dir != Vector2.ZERO else facing
	for group: String in ["enemy_projectile", "deflectable_spell"]:
		for proj: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(proj) or not proj.has_method("reflect"):
				continue
			if bool(proj.get("_reflected")):
				continue
			# A spectacle parks at the arena origin, so its transform is a lie —
			# ask it where it actually is (the house `deflect_point` contract) and
			# only fall back to the transform for a genuine moving body.
			var at: Vector2 = (proj as Node2D).global_position if proj is Node2D else global_position
			if proj.has_method("deflect_point"):
				at = proj.call("deflect_point") as Vector2
			if global_position.distance_to(at) > GUARD_DEFLECT_REACH:
				continue
			proj.call("reflect", dir, _element_color)
			# THE FOURTH DEFLECT PATH, and it was the one nothing counted. A harness
			# that watches only `SpellDeflect.resolve` reports the Swordsaint — the
			# class whose whole identity is turning things away — as the one that never
			# deflects. See `SpellDeflect.note_deflect`.
			SpellDeflect.note_deflect(self)
			Sfx.play("ding", 2.0, 0.02)
			Juice.hit_stop(0.09)
			Juice.shake_camera(4.0)
			rig.set_parry(dir, PARRY_SHIELD_TIME)
			rig.flash_color(PARRY_FLASH_COLOR, 0.1)


## One foot has hit the ground on the rig's run cycle — kick up the Stick-Fight walk
## dust behind it. The rig fires this twice per stride, only while grounded, running,
## un-frozen and not ragdolled, so there is nothing to re-gate here; it also owns the
## STEP SOUND (rig.step_sfx, enabled in _ready), so this handler is purely the visual
## half. Trails behind the direction of travel, hence the -signf on the live velocity.
func _on_foot_planted() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position + Vector2(-signf(velocity.x) * 6.0, 12.0),
		Color(0.85, 0.85, 0.9, 0.45), Color(0.85, 0.85, 0.9, 0.0),
		4, 0.24, 14.0, 52.0
	)


## Small white dust puff at the feet — jump kick-off + landing touchdown. The
## Stick-Fight jump/land dust; spawned a touch below the origin so it sits at the
## ground contact, not the torso.
func _spawn_foot_puff() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position + Vector2(0.0, 12.0),
		Color(1.0, 1.0, 1.0, 0.72), Color(1.0, 1.0, 1.0, 0.0),
		9, 0.28, 22.0, 95.0
	)


## Cooldown snapshot for the AbilityBar HUD — one dict per slot, in bar order.
## `enabled` false = the slot is dimmed (class can't use it): rogue shows Parry.
##
## ⚠ SIX ROWS, AND THAT IS A RULING, NOT A REGRESSION. Watching a live playtest the
## maker cut the bar down to it in one line: **"4 spells, deflect and basic attack —
## that's all there should be to all of them."** So the publisher answers with exactly
## the basic attack, the defensive verb, and `SpellTier.SLOT_COUNT` spell sockets.
##
## The four rows that USED to sit here — the movement verb (Spc), the class AoE (Q),
## Blink (R) and Nova (T) — are gone from this contract and therefore from every HUD
## that reads it. They are NOT gone from the game: the keys still fire, because
## `blast` / `blink` / `nova` / `dash` are wired into `BotBrain`'s kit table,
## `BotController`'s action map, `PauseMenu`'s rebind list and several harnesses, and
## tearing the verbs out of the kit is a far wider change than the one that was asked
## for. What the maker judged was the SCREEN — nine squares is too many to read while
## something is winding up at you — so the screen is what changed. If the verbs should
## stop existing as well, that is a second, deliberate pass across those files.
##
## Nothing below is indexed positionally by the HUD: `AbilityBar` finds the spell
## sockets by counting BACK `SpellTier.SLOT_COUNT` from the end, so this prefix can
## shrink again without re-teaching it.
func ability_hud_state() -> Array:
	# ⚠ THE LEFT CLUSTER IS PARRY THEN DASH, AND THE MAKER CORRECTED ME ONCE ON IT.
	# The first cut of this ruling published LMB (basic attack) and RMB (parry). Shown
	# that screen: "no no, it should be RMB parry, Space to dash with its cooldown on
	# the left, then 1 2 3 4 on the right, and the 4 ultra should have that special
	# border."
	#
	# So the BASIC ATTACK loses its square and the DASH gets one back. That reads
	# strangely until you notice what the left cluster is FOR: it is the two buttons
	# with a COOLDOWN you have to watch — the guard you have to re-arm and the escape
	# you have to ration. LMB has a cooldown too, but it is 0.34 s and you press it
	# constantly; a square that is always full teaches nothing. Dash is the one whose
	# readiness decides whether you commit.
	var left: Array = [_defense_hud_slot(), _move_hud_slot()]
	# ⚠ NOVA CAME BACK, BY NAME. Maker: "I really like Nova and its equivalent, so make
	# sure those spells are one of the 4 — and if not, then one of the 5, including
	# Nova." It was cut with the Q/R/T rows in the six-thing pass and that was the one
	# removal they missed.
	#
	# It joins the LEFT cluster rather than becoming a fifth socket, and that is the
	# whole reason this lands as three-plus-four instead of five-on-the-right: the four
	# sockets are the KIT — ramped weakest-to-heaviest with the ult crowned on the far
	# right — and appending a class ability to that row would put something after the
	# ult and break the ramp the maker specifically asked for. The left cluster is
	# already "the buttons with a cooldown worth watching", which is exactly what Nova
	# is. `has_nova` is false on the Shadowblade, so it publishes nothing there rather
	# than a dead square.
	if bool(_cfg.get("has_nova", false)):
		left.append({
			"name": "Nova", "key": "T",
			"remaining": _nova_cooldown_timer, "total": float(_cfg.get("nova_cd", 6.0)),
			"enabled": true,
		})
	return left + _signature_hud_slots()


## THE DASH SQUARE — back on the bar, and it carries the class's own verb name.
##
## The bar is where a player learns that this button is not the same button on the
## next class: a Cryomancer reading "Dash" and then sliding half a room would be the
## HUD lying. `_move_slot_name()` answers with eleven different words.
func _move_hud_slot() -> Dictionary:
	return {
		"name": _move_slot_name(), "key": "Spc",
		"remaining": _dash_cooldown_timer, "total": float(_cfg["dash_cd"]),
		"enabled": true,
	}


## The movement slot's NAME. The bar is where a player learns that this button is not
## the same button on the next class — a Cryomancer reading "Dash" and then sliding
## half a room would be the HUD lying about the ability. Short enough for the slot.
##
## ⚠ PUBLISHED AGAIN. This left the bar with the first cut of the six-thing ruling and
## came straight back when the maker corrected the layout — see `_move_hud_slot`.
## Kept, not deleted, because this table IS the naming authority for eleven movement
## verbs — re-deriving it from scratch to put the row back would be the expensive half.
func _move_slot_name() -> String:
	match _move_verb():
		"arcane_phase":
			# ONE NAME, ALWAYS. This slot used to flip between "Step" and "Recall"
			# depending on whether an anchor was live — the HUD faithfully reporting
			# that the button had changed meaning under the player's thumb. A label
			# that rewrites itself mid-fight is not a fix for a confusing ability, it
			# is the confusion given a caption.
			return "Phase"
		"air_dash":
			return "Air Dash"
		"charge":
			return "Charge"
		"surge":
			return "Surge"
		"radiant_step":
			return "Radiant"
		"ice_slide":
			return "Slide"
		"lightning_blink":
			return "Bolt Step"
		"thrall_swap":
			return "Swap"
		"committed_step":
			return "Lunge"
	return "Dash"


## The defensive slot, which is two different verbs behind one button.
##
## A press-window class shows PARRY and its cooldown wipe. A held-guard class shows
## GUARD and its RE-ARM — different word because it is a different act, and the bar
## is where a player learns that. ParryRing does not publish the remaining re-arm
## (only `is_ready()`), so the wipe is full-or-empty: it answers "can I guard yet",
## which is the only question the bar is actually being asked here.
func _defense_hud_slot() -> Dictionary:
	if _guard != null:
		return {
			"name": "Guard", "key": "RMB",
			"remaining": 0.0 if _guard.is_ready() else _guard.rearm_time(),
			"total": _guard.rearm_time(), "enabled": true,
		}
	return {
		"name": "Parry", "key": "RMB", "remaining": _parry_cooldown_timer,
		"total": PARRY_COOLDOWN, "enabled": bool(_cfg["can_parry"]),
	}


## Short HUD label for the Q slot, per the class's AoE variant.
##
## ⚠ CURRENTLY UNPUBLISHED, same ruling as `_move_slot_name`: "consecrate and the one
## next to it" — the Cleric's Q and the Nova beside it on the bar — were named
## explicitly as the two rows to cut, and the whole Q row went with them. `ClassInfo`
## still cites this function as the naming authority for a class's AoE, so it stays.
func _aoe_slot_name() -> String:
	match String(_cfg["aoe"]):
		"nova": return "Whirl"
		"fist_shock": return "FirePunch"
		"ground_slam": return "Slam"
		"arcane_meteor": return "ArcaneStorm"
		"consecrate": return "Consecrate"
		"ice_shards": return "IceShards"
		"call_lightning": return "CallLightning"
		"curse_chain": return "CurseChain"
		_: return "Meteor"


## Class display name (Arcanist / Brawler / ...) for HUD / debug.
func class_display_name() -> String:
	return CLASS_NAMES[_hero_class] if _hero_class < CLASS_NAMES.size() else "Class"


## Start the CURRENTLY SELECTED signature's cooldown from OUTSIDE. A
## deferred-resolution spell (the Rift Dagger) only "completes" when its anchor
## resolves or expires, so it — not _cast_signature — decides when the timer starts.
## Never allowed to SHORTEN a running timer, which is why the maxf survives the move
## to a per-slot bank: `HandSlots.start_cooldown` assigns, so the guard has to live
## on this side of it.
##
## ⚠ Charges the SELECTED slot, which is the honest reading of the old shared bank
## and is right for its one caller — the dagger resolves while you still hold it. A
## spell that could resolve after you had switched away would need the slot INDEX
## plumbed through it; nothing does that today, and guessing which slot to bill would
## be worse than not offering it.
func start_signature_cooldown(seconds: float) -> void:
	var slot: int = _hand_slot(_signature_index)
	if seconds > _hand.cooldown(slot):
		_hand.start_cooldown(slot, seconds)


## Hotbar slot for the equipped signature: short name (first word of the spell),
## the Ultimate key, its cooldown wipe, and dimmed when mana can't cover it.
##
## With a live rift anchor out, the slot changes MEANING rather than gaining a
## second binding — so the bar shows RECALL, ready, for as long as the press
## would recall. AbilityBar renders from this dictionary alone, so nothing on the
## UI side needs to know the spell has two beats.
## THE THREE SPELL BUTTONS, one hotbar slot each.
##
## The bar used to show ONE signature slot whose name changed as you cycled (V), which
## made the kit's other spells invisible: you could not see that your ult was ready
## while your damage line recovered, because there was nothing on screen for it and —
## before per-slot cooldowns — no separate number to show anyway. Three slots is the
## control scheme drawn honestly.
##
## KEY LABELS ARE THE TRUTH ABOUT THE BINDINGS, not an aspiration. They used to read
## "G" on the selected slot and "V" on the other two, because there was exactly one
## trigger and a cycle key — the bar honestly describing a control scheme that had
## not been built. Now each slot has its OWN action (`SPELL_ACTIONS`) and its own key,
## so the labels come straight off `SPELL_KEYS` and the bar and the bindings cannot
## drift apart without `_verify_spell_actions` shouting at boot.
func _signature_hud_slots() -> Array:
	var out: Array = []
	for i: int in SpellTier.SLOT_COUNT:
		out.append(_signature_hud_slot(i))
	return out


## Hotbar slot for signature `i`: short name, the key that reaches it, its OWN
## cooldown wipe.
##
## With a live rift anchor out, the slot changes MEANING rather than gaining a second
## binding — so it shows RECALL, ready, for as long as the press would recall.
## AbilityBar renders from this dictionary alone, so nothing on the UI side needs to
## know the spell has two beats.
func _signature_hud_slot(i: int = -1) -> Dictionary:
	var idx: int = _signature_index if i < 0 else i
	var selected: bool = idx == _signature_index
	# This slot's OWN key. Every slot is one press away now, so there is no "the one
	# you can cast" and "the ones you have to cycle to" any more.
	var key: String = SPELL_KEYS[idx] if idx >= 0 and idx < SPELL_KEYS.size() else ""
	var pulse: float = 0.0
	if idx >= 0 and idx < _ready_pulse.size():
		pulse = clampf(_ready_pulse[idx] / READY_PULSE_TIME, 0.0, 1.0)
	var sig: SpellDef = signature_at(idx)
	if sig == null:
		# An empty slot is DRAWN, dimmed, rather than skipped: a hand with a hole in it
		# is information (this class carries two spells, or a pickup slot is open), and
		# a bar that silently shrinks makes the remaining buttons move under the thumb.
		return {"name": "--", "key": key, "remaining": 0.0, "total": 0.0,
			"enabled": false, "selected": selected, "pulse": 0.0}
	if sig.kind == SpellDef.Kind.THROWN_ANCHOR 			and (load(RIFT_DAGGER_PATH) as GDScript).find_anchor(get_tree(), self) != null:
		return {"name": "RECALL", "key": key, "remaining": 0.0, "total": 0.01,
			"enabled": true, "selected": selected, "pulse": pulse}
	# Not split(" ")[0]: the IP rename made zoltraak "The Ordinary Spell", so the
	# ability bar proudly read **The**. short_spell_name() drops leading articles
	# and takes the first real word.
	return {
		"name": AbilityBar.short_spell_name(sig.display_name), "key": key,
		"remaining": signature_cooldown(idx),
		"total": maxf(sig.cooldown, 0.01),
		# Was `mp >= sig.mp_cost`. With the mana gate gone, "enabled" means the slot
		# exists and is yours — the cooldown wipe above is what says "not yet", and a
		# slot that was BOTH dimmed and wiped said the same thing twice.
		"enabled": true,
		"selected": selected,
		# 1 -> 0 across READY_PULSE_TIME on the frame this slot came back. The bar
		# draws it as a flare; a ready button should INVITE the press, not merely
		# stop refusing it.
		"pulse": pulse,
	}


## Equip a weapon kind: swaps the rig's weapon overlay AND retunes the melee
## attack ("gear = visual + ability"). Unknown kinds fall back to fists.
func equip_weapon(kind: String) -> void:
	if not WEAPON_STATS.has(kind):
		kind = "fists"
	_weapon = kind
	var stats: Dictionary = WEAPON_STATS[kind]
	_melee_damage = stats["damage"]
	_melee_range = stats["range"]
	_melee_knockback = stats["knockback"]
	rig.set_equipment("weapon", kind)


func _melee() -> void:
	_melee_cooldown_timer = _melee_cd
	_swing_window = SWING_WINDOW  # this one really is a swing; see _on_melee_hit_frame
	_net_send("ml")
	if _melee_kick_next:
		rig.play(CharacterRig.State.KICK)
	else:
		rig.play(CharacterRig.State.PUNCH)
		rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.4, _element)  # fist ignites on the punch
	_melee_kick_next = not _melee_kick_next
	# A fire-element punch LIGHTS the fist: it stays lit + trails embers for ~1.6s.
	if int(_cfg.get("melee_element", -1)) == Elements.Element.FIRE:
		_flaming_fist_timer = FLAMING_FIST_TIME
	# Short forward lunge on EVERY swing, not just the combo/heavy-swing primaries
	# (maker: the plain click/melee "feels weird" — it used to just plant the
	# figure in place). _primary_melee_combo()/_primary_heavy_swing() set
	# velocity.x again right after calling into this, so this is simply
	# overwritten there — no double-step / compounding for those callers.
	if _aim_dir.x != 0.0:
		velocity.x = signf(_aim_dir.x) * MELEE_LUNGE_SPEED
	Sfx.play("melee_swing", 0.0, 0.08)
	# DECLARE the swing for the clash layer — at the COMMIT, not at contact. That
	# ordering is the whole trick: declaring on contact means this blow has already
	# hurt the other fighter before they swing, and fixing THAT would mean holding
	# every punch in the game for the clash window (~90 ms of latency on every
	# swing) to pay for a rare event. Declaring here decides the clash while both
	# fighters are still in wind-up, at zero cost to the ones that never clash.
	#
	# NOT on a replayed puppet swing: a clash is a DECISION about who wins an
	# exchange, and it has to be made on the peer that owns the swing. Declaring it
	# here as well would let a cosmetic copy cancel a real blow on this screen only.
	if not _replaying:
		MeleeClash.declare(self, _aim_dir, _melee_range, _melee_damage)
		# The flip above already advanced the flag, so the state JUST played is the
		# opposite of what it now says.
		_publish_swing_tell(CharacterRig.State.PUNCH if _melee_kick_next
			else CharacterRig.State.KICK)


# ══ THE HERO'S OWN TELLS ════════════════════════════════════════════════════════
## ⚠ `Hero` PUBLISHED NO `Telegraph` AT ALL, AND THAT ONE ABSENCE IS THREE OF THE
## MAKER'S REPORTS AT ONCE.
##
## `BotController.perceive_threats` builds its entire threat picture from the
## `telegraph` group plus projectiles already in flight. Only `Enemy` and a handful of
## spell spectacles ever joined that group — so in a hero-versus-hero fight the three
## CONTACT classes (Brawler, Juggernaut, Swordsaint) generated **zero** threat
## descriptors between them. `BotBrain._reflex` therefore returned empty on every
## single frame of every melee exchange, which means the dodge ladder was never
## entered, which means the parry rung underneath it was never reached. That reads
## from the couch as *"not much deflecting"*, as *"the bots aren't smart"*, and as
## *"the Juggernaut's punches have no tell"* — one gap wearing three costumes.
##
## ⚠ AND IT COSTS THE PLAYER NOTHING, because the window already existed. Damage does
## not land on the press: `_melee` plays the rig animation and the hit arrives on
## `rig.hit_frame`, `HIT_FRAME_FRACTION` (0.35) of the way through a 0.22 s PUNCH or a
## 0.26 s KICK. This publishes exactly that interval, so the tell is a description of
## the swing that was already happening rather than a delay added to it. Nothing about
## the feel of the button changes.
const SWING_TELL_HEAVY_DAMAGE: int = 20
## How much of the swing's reach the tell's circle is centred at, and its radius as a
## fraction of that reach. Between them they cover the cone `_on_melee_hit_frame`
## actually queries without claiming the ground behind the swinger.
const SWING_TELL_CENTRE: float = 0.55
const SWING_TELL_RADIUS: float = 0.55

## ══ THE ONE KNOB FOR THE FOUR ABILITIES THAT USED TO HIT ON THE PRESS ══════════
## Seconds of warning the frost cone, the uppercut, the fire punch and the ground
## slam give before they land.
##
## ⚠ THESE FOUR DEALT DAMAGE SYNCHRONOUSLY WITH THE BUTTON, and each of them was
## ALREADY PLAYING A WIND-UP ANIMATION while doing it — a CAST, a KICK, a PUNCH, a
## STOMP gesture. So the picture on screen said "winding up" and the damage had
## already happened. This does not add a delay so much as make the damage agree with
## the animation that was always there.
##
## It also closes the last hole in the locked *"everything must be dodgeable"* rule
## (see `CrescentStep`'s header) and is what lets `BotDodge` see them at all — a
## hitscan cone that resolves on the press frame leaves nothing to perceive.
##
## ⚠ THIS IS THE CHANGE IN THIS WAVE MOST LIKELY TO NEED REVERTING, because it is the
## only one that alters how a button FEELS and it has not been played. **Set it to 0.0
## and all four resolve on the press again** — one line, and the tells stay.
## UNTESTED GUESS at 0.10: shorter than the melee tell's own 0.077 s would be
## pointless, and much longer starts reading as input lag on a primary.
const ABILITY_TELL_LEAD: float = 0.10

## The launcher's wedge: the forward half plus a small overlap behind, so a body
## standing directly on top of you is still popped. Promoted out of `_uppercut`'s body
## when the hit was split from the tell — both halves read them now.
const UPPERCUT_REACH: float = 70.0
const UPPERCUT_DOT: float = -0.2


## Seconds from a swing's COMMIT to the frame it deals damage — the rig's own timing,
## derived rather than restated, so retuning the animation retunes the tell with it.
## Takes the state EXPLICITLY: `_melee` flips `_melee_kick_next` before it declares, and
## `_primary_heavy_swing` never touches the flag at all, so reading it here would give
## the wrong answer for two of the three callers.
func _swing_tell_windup(state: int) -> float:
	var dur: float = float(CharacterRig.ONE_SHOT_DURATIONS.get(state, 0.22))
	return maxf(dur * CharacterRig.HIT_FRAME_FRACTION, 0.02)


## Publish the swing as a danger the dodge layer can see and the eye can read.
func _publish_swing_tell(state: int = CharacterRig.State.PUNCH) -> void:
	var aim: Vector2 = _aim_dir if _aim_dir != Vector2.ZERO else facing
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	aim = aim.normalized()
	# A heavy, committed swing gets the full ground ring; a fast jab gets the light
	# crosshair. Both are perceived identically — the weight is purely what the eye
	# gets, so a Brawler on a 0.20 s cadence does not strobe a danger ring at you.
	var heavy: bool = _melee_damage >= SWING_TELL_HEAVY_DAMAGE
	_emit_hero_telegraph({
		"pos": global_position + aim * _melee_range * SWING_TELL_CENTRE,
		"radius": _melee_range * SWING_TELL_RADIUS,
		"windup": _swing_tell_windup(state),
		"style": Telegraph.Style.ZONE if heavy else Telegraph.Style.DART,
		"aim": aim,
		"reach": _melee_range,
	})


## Build one of this hero's tells. Mirrors `Enemy._emit_telegraph`: a SIBLING in the
## arena rather than a child, so the mark stays where the danger is even if the
## swinger gets knocked across the room mid-wind-up.
##
## ⚠ `source` IS ALWAYS STAMPED, and it is load-bearing. `perceive_threats` skips a
## telegraph whose `source` is the perceiving body — without it a bot-driven hero
## reads its own wind-up as incoming danger and dodges away from its own punch on
## every frame it swings.
func _emit_hero_telegraph(cfg: Dictionary) -> Telegraph:
	var parent: Node = get_parent()
	if parent == null:
		return null
	var tele := Telegraph.new()
	parent.add_child(tele)
	tele.global_position = cfg.get("pos", global_position)
	tele.source = self
	tele.accent = _element_color
	tele.style = cfg.get("style", Telegraph.Style.ZONE)
	tele.aim_dir = cfg.get("aim", Vector2.RIGHT)
	tele.reach = float(cfg.get("reach", 120.0))
	# NOTHING IS CONNECTED TO `fired`. The swing resolves on its own clock through
	# `rig.hit_frame`; this node is a DESCRIPTION of that swing, not a second timer
	# that could drift from it or a second place damage could come from.
	tele.start(float(cfg.get("radius", 40.0)), float(cfg.get("windup", 0.1)))
	return tele


## Publish an ability's tell, wait out its lead, then resolve it.
##
## ⚠ THE TELEGRAPH IS THE CLOCK — deliberately, and not a `SceneTreeTimer`.
##
## A `Telegraph` is a NODE, so a headless test can step it with `advance(delta)` the
## way `MeteorFist` already drives its own. A `SceneTreeTimer` can only be advanced by
## real frames, and this project's suites drive combat by calling `rig.advance(0.02)`
## in a tight synchronous loop with no frames passing at all — so a timer-based lead
## would simply never elapse under test, and the first version of this did exactly that
## (`test_class_attacks` caught it: the Cryomancer's cone stopped landing entirely).
## It is also the same pattern `BlastSpell.detonate_at` has always used.
##
## A REPLAYED PUPPET still resolves, but its tell leaves the perception group the frame
## it is born: a cosmetic copy of somebody else's swing must not put a second threat on
## this peer's board for a swing already represented by the original.
##
## ⚠ AND ITS DAMAGE IS ALREADY SAFE — CHECKED, NOT ASSUMED. `net_replay` clears
## `_replaying` synchronously, so a deferred hit resolves OUTSIDE the replay guard and a
## flag-scoped defence would miss it entirely. It does not matter, because the defence
## is not a flag: `attack_group()` returns `NET_GHOST_GROUP` for a puppet PERSISTENTLY,
## and its own header says it is written that way precisely because "half of a hero's
## damage resolves LATER than the call that started it". Both `_resolve_*` helpers go
## through it, so a puppet's deferred ability finds nobody, exactly as its fists already
## did.
func _telegraphed_ability(cfg: Dictionary, resolve: Callable) -> void:
	if ABILITY_TELL_LEAD <= 0.0:
		resolve.call()   # the documented revert path: instant, exactly as before
		return
	var tele: Telegraph = _emit_hero_telegraph(cfg)
	if tele == null:
		resolve.call()   # no arena to hang a tell on; the hit still has to happen
		return
	if _replaying:
		tele.remove_from_group(Telegraph.GROUP)
	# A body that died or left the arena during the lead must not resolve into a
	# freed tree, so the guard rides with the callable rather than the caller.
	tele.fired.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			resolve.call())


## Drive the persistent flaming fist: decay the timer, feed the rig the current
## fire strength, and trail small embers from the moving hand. Runs every frame.
func _update_flaming_fist(delta: float) -> void:
	if _flaming_fist_timer <= 0.0:
		return
	_flaming_fist_timer = maxf(_flaming_fist_timer - delta, 0.0)
	var s: float = clampf(_flaming_fist_timer / FLAMING_FIST_TIME, 0.0, 1.0)
	rig.set_hand_fire(s, Elements.Element.FIRE)
	var hand_pos: Vector2 = rig.get_lead_hand_global()
	_fist_ember_timer -= delta
	if _fist_ember_timer <= 0.0 and _last_hand_pos != Vector2.ZERO \
			and hand_pos.distance_to(_last_hand_pos) > 4.0:
		_fist_ember_timer = 0.045
		CombatVfx.spawn_burst(
			get_parent(), hand_pos,
			Color(1.3, 0.55, 0.15, 0.8 * s), Color(0.8, 0.2, 0.05, 0.0),
			3, 0.4, 20.0, 75.0, 0.6, 1.5, 0.0, 0.0, true
		)
	_last_hand_pos = hand_pos
	if _flaming_fist_timer <= 0.0:
		rig.set_hand_fire(0.0, Elements.Element.FIRE)  # snuff out


## The nearest HOSTILE within _melee_range (or null) — the melee auto-target.
##
## ⚠ This is aim assist and it predates the locked no-aim-assist rule. It survives
## deliberately (`slice_test_selfdamage.gd` asserts it: an enemy directly BEHIND
## you still eats the swing) and it only ever ADDS a guaranteed hit, never removes
## an arc-gated one — but it is in genuine tension with that rule and stays
## flagged rather than quietly deleted. What changed here is only WHOSE nearest
## body it finds: the scan is the caster's faction now, so a bot-driven hero
## auto-targets the hero it is fighting instead of ignoring it and hunting for
## monsters that are not in this arena.
##
## ⚠ THIS SCAN DELIBERATELY STAYS ON `hostile_group`, NOT `attack_group()`, and that
## asymmetry is the whole answer to "friendly fire must not turn the melee
## auto-target into a teammate-killer". The arc sweep in `_on_melee_hit_frame`
## widened to `mortal` — you CAN punch your friend, and under this spec you should
## be able to — but the auto-target is the game aiming FOR you, and a game that
## silently redirects your fist onto the person standing next to you is not friendly
## fire, it is a bug that feels like betrayal. So: aim at your teammate and you hit
## them; do not aim at them and nothing reaches for them on your behalf. True
## hostiles keep the free hit exactly as before, which is what the existing
## regression test pins.
## AIM ASSIST — the maker's LOCKED no-auto-aim rule, honoured with a dial on it.
##
## ⚠ DEFAULT 0, AND 0 IS INERT. `SpellTargets.assist_strength` reads the live Tuning
## value and answers 0.0 when there is no autoload, no field, or the slider is down —
## and `assist_aim` returns its argument untouched before it scans anything at that
## strength. So the shipping build behaves exactly as a build with none of this in it,
## which is the condition the slider is shipped under. `tools/slice0_test_targeting.gd`
## keeps asserting the deleted `Targeting` helper stays deleted, and nothing here
## brings it back: there is no target SELECTION, no lock, no fire-at-what-I-picked.
##
## SCANS THE FACTION, NEVER `mortal`. Same rule as the melee auto-target, for the same
## reason: friendly fire means you CAN hit your team-mate, and it must never mean the
## game quietly steers your shot into one.
##
## Skips itself for the same reason every spell does — the caster is in its own
## hostile group the moment two heroes are on opposite factions.
func _apply_aim_assist() -> void:
	var strength: float = SpellTargets.assist_strength(self)
	if strength <= 0.0:
		return
	_aim_dir = SpellTargets.assist_aim(global_position, _aim_dir,
		get_tree().get_nodes_in_group(hostile_group), strength, [self], self)


func _nearest_enemy_in_melee_range() -> Node2D:
	# Nearest measured to the SILHOUETTE, so a tall enemy whose head is closer than a
	# short enemy's origin wins — which is what the eye expects, and which is what
	# `SpellTargets.nearest` is documented as the seam for.
	return SpellTargets.nearest(global_position, _melee_range,
		get_tree().get_nodes_in_group(hostile_group), [self], self)


func _on_melee_hit_frame() -> void:
	# ══ ONLY A DECLARED SWING LANDS ═════════════════════════════════════════════
	# ⚠ THIS HANDLER USED TO FIRE FOR ANY PUNCH OR KICK ANIMATION IN THE GAME, and
	# four things play one WITHOUT being a melee swing. MEASURED against a recorder
	# with `tools/hero_hitframe_probe.gd`:
	#
	#   Brawler uppercut   -> [18, 16]   the 16 is a free melee swing
	#   Brawler fire punch -> [30, 16]   likewise
	#
	# `rig.hit_frame` is emitted for every PUNCH/KICK one-shot, `_ready` connects this
	# handler to it once, and the only early-out was the clash check. So the uppercut
	# (KICK, for the launcher pose), the fire punch (PUNCH, so the fist ignites), the
	# Swordsaint's `_unsheathe_cut` (PUNCH) and **Thunderclap — a SPELL** (PUNCH, for
	# the lunge) each landed an extra, undeclared, full-damage melee hit. None of them
	# consumed `_melee_cooldown_timer`, so none of them paid melee's cadence for it,
	# and nothing anywhere documented that it happened.
	#
	# Nobody designs "casting Thunderclap also punches". The animation was chosen for
	# how it LOOKS and quietly bought a hitbox.
	#
	# ⚠ AND THE FIX IS DAMAGE-NEUTRAL WHERE IT MATTERED — see `_uppercut` and
	# `_fire_punch`, which now add `_melee_damage` to their own numbers explicitly. The
	# Brawler is near the bottom of the roster and this must not be a silent nerf to it.
	if _swing_window <= 0.0:
		return
	_swing_window = 0.0
	# The swing was spent meeting another blow head-on, so it must NOT also land.
	# A clash that still dealt its damage would read as "we both hit each other"
	# rather than "our blows cancelled", and the whole beat is the cancellation.
	if MeleeClash.consume_spent(self):
		return
	var hit_any: bool = false
	var melee_el: int = int(_cfg.get("melee_element", -1))  # class element on the strike
	# Auto-target (Stick-Fight punches don't need pixel-perfect aim): the single
	# NEAREST enemy within _melee_range always connects, regardless of the facing
	# cone below — a click near an enemy shouldn't whiff just because the cursor
	# isn't exactly on them. Wide swings (Juggernaut's soft _melee_arc_dot) still
	# additionally cleave every OTHER enemy that IS inside the strict arc, so
	# that crowd-hit behaviour is unchanged; auto-target only adds a guaranteed
	# hit, it never removes the arc-gated ones.
	var nearest_enemy: Node2D = _nearest_enemy_in_melee_range()
	# THE ARC IS NOW MEASURED AGAINST THE DRAWN BODY. All three loops below used to
	# be `distance_to(node.global_position)` — a point test against an origin that
	# sits ~10 px under the head being aimed at (19 px on the 1.9x dummies), which is
	# the maker's "spells pass through heads without registering" bug in the form the
	# player meets it most often. `SpellTargets.in_cone` keeps the exact same
	# `facing.dot(toward) > _melee_arc_dot` predicate (strict, so no swing silently
	# widens) but measures REACH to the silhouette, adds the target's own published
	# `hit_margin`, and filters line-of-sight so a punch cannot land through a wall.
	#
	# ⚠ THE STACKING CAVEAT: reach therefore grows, by up to about half a rig height
	# on the vertical axis. That IS the fix. If melee starts feeling too long, tune
	# `MELEE_RANGE` / the per-class `melee_range` OR `Enemy.HIT_MARGIN_FACTOR` —
	# never both, and never a third margin at this call site.
	var enemies_in_arc: Array = SpellTargets.in_cone(global_position, facing,
		_melee_range, _melee_arc_dot, get_tree().get_nodes_in_group(attack_group()),
		[self], self)
	# The auto-target is PRESERVED deliberately, not reintroduced: it predates this
	# change, `slice_test_selfdamage.gd` asserts it explicitly (an enemy directly
	# BEHIND you still eats the swing), and it only ever ADDS a guaranteed hit — it
	# never removes an arc-gated one. It is, however, in genuine tension with the
	# locked no-aim-assist rule, and it is flagged in the handoff rather than
	# silently deleted here.
	if nearest_enemy != null and not enemies_in_arc.has(nearest_enemy):
		enemies_in_arc.append(nearest_enemy)
	for enemy: Node in enemies_in_arc:
		var toward: Vector2 = ((enemy as Node2D).global_position - global_position).normalized()
		if enemy.has_method("take_damage"):
			enemy.take_damage(_melee_damage)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(toward * _melee_knockback)
		if melee_el >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(melee_el)  # burning / staggering / etc. fists
		hit_any = true
	# Crates break under melee too — same range/arc gate as enemies.
	for prop: Node in SpellTargets.in_cone(global_position, facing, _melee_range,
			_melee_arc_dot, get_tree().get_nodes_in_group("destructible"), [self], self):
		if prop.has_method("take_damage"):
			prop.take_damage(_melee_damage)
		hit_any = true
	# A swing also SWATS enemy bolts out of the air (punch-fizzles-bolt): same
	# range + facing-arc gate, so a well-timed punch is a melee "parry". LOS is off
	# for this one — a bolt is IN FLIGHT between you and whatever fired it, and
	# culling it for cover it is currently passing would make the swat unreliable
	# in exactly the cluttered rooms where it matters.
	# BOTH bolt groups. Scanning only "enemy_projectile" meant a hero could never
	# swat a RIVAL HERO's bolt, which joins "player_spell" — invisible while every
	# fight was hero-vs-enemy, and a hole the moment factions let two heroes fight.
	# The blade guard could already catch them (it scans "deflectable_spell"), so
	# the punch-parry was the odd one out rather than the rule.
	#
	# ⚠ NOT ON A PUPPET, and this one is easy to miss because the swat has no damage
	# number attached to it. `consume()` DELETES a projectile. A remote copy of
	# someone else's swing eating a live local bolt would remove that bolt on this
	# screen and nowhere else — the two phones would stop agreeing about what is in
	# the air, which is the same class of divergence as double damage and harder to
	# see. The real swing already resolves on its owner's peer.
	var bolts: Array = []
	if not _is_net_puppet():
		bolts = get_tree().get_nodes_in_group("enemy_projectile")
		bolts.append_array(get_tree().get_nodes_in_group("player_spell"))
	for proj: Node in SpellTargets.in_cone(global_position, facing, _melee_range,
			_melee_arc_dot, bolts, [self], self, false):
		# Never swat your own shot out of the air on the follow-through.
		if proj.get("caster") == self or proj.get("caster_node") == self:
			continue
		if proj.has_method("consume"):
			proj.call("consume")
			hit_any = true
	if hit_any:
		# Unified hit juice (study §4) — heavier freeze than a spell hit + a punch
		# INTO the strike direction, all in sync.
		Juice.on_hit({
			"sfx": "melee_hit", "hitstop": _tune("melee_hit_stop", MELEE_HIT_STOP),
			"shake": 4.0, "dir": facing, "kick": MELEE_CAMERA_KICK,
		})
		Sfx.play("ding", -3.0, 0.05)  # the bright Stick-Fight "clean hit" ding
	else:
		# Every swing reads even on a MISS — a small hitstop/shake so the punch
		# still has weight when it doesn't land (much lighter than the on-connect
		# cluster above). The melee_swing whoosh SFX + rig slash-arc already fire
		# unconditionally at swing-start, so this is just the missing impact beat.
		Juice.on_hit({"hitstop": MELEE_SWING_HIT_STOP, "shake": MELEE_SWING_SHAKE, "dir": facing})


## SANDBOX Smash: the knockback multiplier at a given damage %. Pure + static so
## it's headless-testable: 0% -> 1.0x, 100% -> 2.0x, and it grows linearly beyond.
## HOW MUCH HARDER A SHOVE LAUNCHES IN THE RING-OUT SANDBOX.
##
## ⚠ APPLIED AT THE CALL SITE, NEVER FOLDED INTO THE CURVE BELOW. That curve is a
## CONTRACT SHARED WITH `Enemy` — `slice_test_ringout` pins its exact outputs (0% ->
## 1.0x, 100% -> 2.0x) AND asserts the two bodies' copies agree — so baking a gain into
## it would either break the pin or force the suite to be widened to accept a guess.
## Keeping it separate leaves the pinned curve untouched and the parity intact, and
## `Enemy.RINGOUT_LAUNCH_GAIN` mirrors this value so both bodies still eject alike.
##
## WHY IT IS 6.0. The sandbox's whole win condition is putting a body off the stage,
## and it was tuned against a knockback that was being INTEGRATED as an acceleration —
## measured at 6.0x the stated impulse at normal time scale (see `_knockback_applied`).
## Fixing that integration made the shove honest and took ring-outs from 32/144 bouts
## to 0/144: the mode stopped working. 6.0 restores the launch the sandbox was actually
## built around while keeping what the fix bought — the distance no longer depends on
## whether the hit happened to trigger hitstop, so the same shot travels the same
## distance every time. Tower combat is untouched; this only applies in ring-out mode.
## FEEL — the maker judges the number at F5, and this constant is the dial.
const RINGOUT_LAUNCH_GAIN: float = 6.0


static func ringout_knockback_scale(pct: float) -> float:
	return 1.0 + pct / 100.0


## True when the sandbox ring-out model is active (GameState.ringout_mode). Guarded
## lookup so headless contexts / a bare instance without the autoload read false.
func _is_ringout_mode() -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	return gs != null and bool(gs.get("ringout_mode"))


## Receive a shove (bomb blast / reflected bolt / slam). Same i-frame contract as
## take_damage — a dashing or just-blinked hero shrugs it off. The .y lands once as
## a real impulse; .x rides the decaying channel (added into velocity each frame).
func apply_knockback(impulse: Vector2, do_flop: bool = true) -> void:
	# Co-op: a shove computed on another peer is forwarded to this hero's owner.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_apply_knockback", impulse)
		return
	if is_dashing or _blink_iframe_timer > 0.0:
		return
	# JUGGERNAUT, UNSTOPPABLE SURGE. Every dash already ignores knockback (the line
	# above), so armour that only lasted the travel would be indistinguishable from
	# everyone else's. The TAIL is the ability: for `SURGE_ARMOR_TAIL` after the surge
	# ends the Juggernaut still cannot be moved, so a surge INTO a crowd is not
	# immediately shoved back out of it. It is not invulnerability — the damage lands
	# in full (`SURGE_IFRAME_FRACTION` is 0.0), the body just refuses to go anywhere.
	if _surge_armor_timer > 0.0:
		return
	# THE knockback knob (TuningConfig.knockback_mult). Fallback must MATCH the
	# exported default — 1.6 -> 1.0 with the "knockback is too much" pass, or a
	# context without the Tuning autoload silently keeps the old launch feel.
	impulse *= _tune("knockback_mult", 1.0)
	# Smash sandbox: the higher THIS fighter's damage %, the farther the same hit
	# sends them (that's how a ring-out becomes reachable). No-op in tower mode.
	if _is_ringout_mode():
		impulse *= ringout_knockback_scale(damage_pct) * RINGOUT_LAUNCH_GAIN
	_knockback = impulse
	velocity.y += impulse.y
	# Reel from the blow (skip while the manual hold-DOWN ragdoll owns the limp,
	# and skip for self-recoil which passes do_flop=false).
	if do_flop and rig != null and impulse.length() > 12.0 and not _ragdolling:
		var mag: float = impulse.length()
		# ══ THE BODY ANSWERS THE SIZE OF THE BLOW ═══════════════════════════════
		# Maker: *"the stick figures need to react to being hit more like knockback
		# or equivalent depending on the hit like if its a beam from space then it
		# should knock them down"*.
		#
		# The scaling was already here and it was capped where nothing could ever
		# read as a knockdown: `clampf(mag / 800.0, 0.2, 0.7)` means a 240-impulse
		# bolt and a 900-impulse Hollow Purple differ by 0.3 to 0.7 of a flop — a
		# lean either way — and the two looked nearly identical. Everything in the
		# roster from a pillar (620) upward saturated the same ceiling.
		#
		# The ceiling goes to a full 1.0 and the curve is widened so the range the
		# game actually uses is spread across it: a 150-impulse flurry cut still
		# barely rocks the figure, a 300 melee visibly staggers it, and the 600+ band
		# — pillars, walls, ults, a ray out of the sky — goes all the way over. The
		# limp is also held longer at the top, because a knockdown that recovers in
		# the same 0.18 s as a graze is a stagger with a bigger number on it.
		var weight: float = clampf((mag - 120.0) / 520.0, 0.0, 1.0)
		rig.flop(lerpf(0.18, 1.0, weight), lerpf(0.16, 0.42, weight))
		rig.apply_impulse(impulse.normalized(), minf(mag, 900.0) * 0.95)


## Firing a big spell shoves the caster back (Stick-Fight recoil = power is
## dangerous). Horizontal-only + opposite the aim, so directed beams push you
## back while sky-aimed spells (aim.x ~ 0) barely recoil and vertical hops
## aren't fought. Routes through apply_knockback with do_flop=false (no self-flop).
func _self_recoil(amount: float) -> void:
	if absf(_aim_dir.x) < 0.15:
		return
	apply_knockback(Vector2(-signf(_aim_dir.x) * amount, 0.0), false)


## Slammed hard into a destructible/breakable this frame? Crack it (shared helper).
func _check_wall_slam() -> void:
	_knockback = SlamPhysics.check(self, _knockback)


## True only during the opening slice of a dash. _dash_timer counts DOWN from the
## dash duration, so "early" is a HIGH remaining time.
##
## THE FRACTION IS PER CLASS NOW, and it is a decision rather than an accident of a
## shared code path: `dash_iframe_fraction` in CLASS_CONFIG, named per verb up at the
## MOVEMENT VERBS block. 0.0 means the verb dodges NOTHING (the Brawler's charge and
## the Juggernaut's surge are commitments, not escapes) and that is a real number in the
## table, not an omission. `DASH_IFRAME_FRACTION` survives only as the fallback for a
## class that forgets the key.
##
## `_dash_total` — the verb's own duration — replaces the global `dash_time` read. With
## the global the Cryomancer's 0.55 s slide would have measured its i-frame slice
## against 0.14 s and been invulnerable for exactly none of it.
func _dash_invulnerable() -> bool:
	if not is_dashing:
		return false
	var frac: float = float(_cfg.get("dash_iframe_fraction", DASH_IFRAME_FRACTION))
	if frac <= 0.0:
		return false
	return _dash_timer >= maxf(_dash_total, 0.0001) * (1.0 - frac)


func take_damage(amount: int) -> void:
	# Co-op: a hit computed on another peer (e.g. the host's enemy AI striking THIS
	# hero, whom the host only holds as a puppet) is forwarded to this hero's owner,
	# where its i-frames / parry / channel-break all resolve authoritatively. SP /
	# owner -> fall through and apply locally (byte-identical to before).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_take_damage", amount)
		return
	# Co-op: a downed hero is out of the fight — immune until revived.
	if downed:
		return
	# Dash i-frames cover only the EARLY part of the dash, not all of it. Full-
	# duration invulnerability made dash a free "delete that attack" button: you
	# could react late, dash into a hit that had already connected, and take
	# nothing. Now a dash must be started BEFORE the hit lands, so it is a read
	# rather than a panic button, and a late dash still gets punished.
	if _dash_invulnerable():
		return
	# ══ THE PACT SHRUGS IT OFF ══════════════════════════════════════════════════
	# Maker: a pacted body should *"deflect most attacks for the next 5 seconds so it
	# can get up close and personal"*.
	#
	# A REDUCTION, not an immunity, and the difference is the whole design: the pact
	# is still draining you through this same function, so a body that took literally
	# nothing could stand in a boss's lap forever and lose only to its own bleed —
	# which is a timer, not a fight. At this ward the approach is survivable and a bad
	# approach still kills you.
	#
	# Applied above mitigation and below the i-frames, so it compounds with gear and
	# growth ward rather than replacing them, and so a dash or a blink still beats it
	# outright — a free window should always beat a paid one. Floored at 1 so a hit is
	# never silently erased; being untouchable is the i-frames' job, not the ward's.
	var pact_ward: float = BloodPact.ward_for(self, self)
	if pact_ward > 0.0:
		amount = maxi(int(round(float(amount) * (1.0 - pact_ward))), 1)
	# Blink grants a brief post-teleport i-frame window (BLINK_IFRAME).
	if _blink_iframe_timer > 0.0:
		return
	# Perfect-parry window also BLOCKS a melee / contact / charge hit (deflect
	# punches, not just projectiles) — the reward is the same crisp ding + flash.
	if _parry_window_timer > 0.0:
		# One counter for all three deflect paths — see SpellDeflect.note_deflect.
		SpellDeflect.note_deflect(self)
		Sfx.play("ding", 2.0, 0.02)
		rig.flash_color(PARRY_FLASH_COLOR, 0.1)
		rig.set_parry(_aim_dir, PARRY_SHIELD_TIME)
		# ⚠ THE HIT-STOP AND THE SHAKE ARE NOT DECORATION — THEY ARE THE OTHER TWO
		# PATHS' BEAT, AND THIS PATH WAS MISSING THEM. `try_parry` (Hero.gd:4434) and
		# `SpellDeflect._payoff` both play ding + hit_stop(0.09) + shake(4.0); this
		# branch played the ding alone. Since this is the CATCH-ALL path — every
		# melee, contact, charge and every one of the spectacles that route through
		# neither of the other two — the most COMMON deflect in the game was also the
		# flattest, and read on camera as though nothing had happened. One deflect
		# must feel like one deflect whichever path resolved it.
		Juice.hit_stop(0.09)
		Juice.shake_camera(4.0)
		# The DEFLECT beat — anime freeze-frame localized AT the hero, biased a
		# touch toward the attacker (aim side) so the burst reads at the clash.
		Juice.frame({"style": ImpactFrame.Style.LOCAL, "strength": 0.7,
			"at": global_position + _aim_dir * 18.0})
		# ══ THE WINDOW SURVIVES THE BURST IT WAS OPENED FOR ═════════════════════
		# Maker: *"how is brawler meant to kill the first boss like if they are
		# getting up close... all the classes actually need a way to deflect the
		# bosses attacks"*.
		#
		# The finding is NOT that boss attacks are unblockable — every one of them
		# routes through this catch-all and is fully negated here, which a live probe
		# confirms (a beam into a raised guard: 0 damage, 1 deflect counted). The
		# defect is that this line ZEROED the window on the first hit, while the
		# attacks that make melee range lethal all arrive in bursts: the Guardian's
		# rays are 3, its meteor is 12, the Scribble's frenzy is 4, the Eraser's
		# unmake is 6. A perfect read stopped ONE of them and then ate the rest, on a
		# 0.9 s cooldown. That is why standing close reads as unsurvivable.
		#
		# So the window now runs its remaining time instead of being spent. It is not
		# refreshed and it is not lengthened — `PARRY_WINDOW` is still 0.16 s and
		# `PARRY_COOLDOWN` is still 0.9 s, both untouched, because widening either is
		# the change that trivialises every mob and every PvP bout in the game rather
		# than answering a boss. What it buys is exactly one burst per read.
		#
		# The precedent is already in this file and already argued: the Swordsaint's
		# BLADE ring deliberately does NOT consume on a reflect. This gives the other
		# eight classes the same property for the length of one press.
		return
	# THE BLADE GUARD. Resolved ABOVE ordinary mitigation because its outcome is
	# categorical rather than a percentage: a perfect read is a total negate plus a
	# BANK, and banking a number that gear had already shaved would pay the
	# Swordsaint less for the same read the better armoured they were, which is
	# backwards. A sustained (overshot) guard only chips, and banks nothing — see
	# the BLADE-GUARD constants block for why holding must never earn.
	if _guard != null:
		match _guard.quality():
			ParryRing.Quality.PERFECT:
				_guard_bank = mini(_guard_bank + amount, GUARD_BANK_CAP)
				_guard_hits += 1
				# One counter for all three deflect paths — see SpellDeflect.note_deflect.
				SpellDeflect.note_deflect(self)
				Sfx.play("ding", 2.0, 0.02)
				rig.flash_color(PARRY_FLASH_COLOR, 0.1)
				rig.set_parry(_aim_dir, PARRY_SHIELD_TIME)
				# Same beat as every other deflect path — see the press-window branch
				# above for why these two lines are load-bearing.
				Juice.hit_stop(0.09)
				Juice.shake_camera(4.0)
				Juice.frame({"style": ImpactFrame.Style.LOCAL, "strength": 0.7,
			"at": global_position + _aim_dir * 18.0})
				return
			ParryRing.Quality.SUSTAIN:
				amount = int(round(float(amount) * _guard.damage_mult()))
	# MITIGATION RUNS BEFORE THE INTERRUPT. It used to run after, so a hit your
	# gear soaked entirely still shattered a 1.3 s channel — the ward paid for
	# nothing. Maker's rule: only a hit that actually LANDS breaks your cast.
	# GuardComponent is the single mitigation path (gear armour, the one-shot
	# warding robe, and ward spells), replacing three fields that were inlined
	# here and invisible to every other body in the game.
	var guard: GuardComponent = GuardComponent.peek(self)
	if guard != null:
		amount = guard.mitigate(amount)
	# A hit that got through shatters a float-channel OR a summon windup — the ult
	# is lost with its mana and cooldown already spent. Fully absorbed = cast survives.
	if amount > 0:
		if _channeling:
			_cancel_channel()
		if _summoning:
			_cancel_summon()
		rig.flash_color(Color(0.75, 0.85, 1.0), 0.14)  # a pale ward shimmer
	# Smash sandbox: pile onto the damage % (no hp drain, no hp-death — the only
	# way out is a ring-out). Tower mode: drain hp and die at 0 (unchanged).
	# pct_per_damage is read from Tuning (single shared source with Enemy — see
	# TuningConfig.pct_per_damage) so a retune can't silently diverge the two.
	var ringout: bool = _is_ringout_mode()
	if ringout:
		damage_pct += float(amount) * _tune("pct_per_damage", 0.8)
	else:
		hp = max(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, -18.0), amount, Color(1.0, 0.35, 0.35), amount >= 18)
	rig.play(CharacterRig.State.HURT)
	rig.flash_color(HURT_FLASH_COLOR, HURT_FLASH_TIME)
	rig.apply_impulse(Vector2(-facing.x, -0.7), 300.0)  # ragdoll flinch on the hit
	Juice.hit_stop(_tune("hurt_hit_stop", HURT_HIT_STOP))
	Juice.shake_camera(_tune("hurt_shake", HURT_SHAKE))
	Sfx.play("hero_hurt")
	if not ringout and hp == 0:
		_die()


func _die() -> void:
	# THE DEATH RULE (maker, 2026-08-01): "dying cost is a life in ghost form until
	# your teammate revives you; if you all die then the game is over." So a death
	# NEVER moves you down the tower any more — it takes you out of the fight.
	#
	# ONE PATH FOR CO-OP AND SOLO, which is the point: whether or not a session is up,
	# a death inside a run drops you into GHOST FORM, and `Arena._check_party_wipe` is
	# the single place that notices the party has run out of bodies and ends the run.
	# In solo that verdict lands the same frame (you are the whole party), which is
	# exactly the shipped `DeathRules.SOLO_SELF_REVIVE_CHARGES == 0` policy.
	#
	# Outside a run — the F6 feel sandbox, the 1v1 duel — a death still just resets to
	# full, so the feel toy never stops.
	var gs: Node = get_node_or_null("/root/GameState")
	var in_run: bool = gs != null and gs.is_run_active()
	if in_run or (_net != null and _net.is_active()):
		_enter_downed()
		return
	hp = max_hp
	health_changed.emit(hp, max_hp)


## Become a GHOST: out of the fight, immune, untargetable, but still yours to steer.
## hp stays 0. Cancels any in-flight channel/summon so nothing fires from a corpse.
##
## `GhostForm.enter` does the state surgery (leave the target groups, zero the
## collision layer, fade the rig) and owns the look; everything here is the BEAT —
## the flop, the sound, and the second-wind bookkeeping. Idempotent, because both the
## local death path and the replicated-flag path can reach it.
func _enter_downed() -> void:
	if downed:
		return
	downed = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_ghost_haunt_cd = 0.0
	if _channeling:
		_cancel_channel()
	if _summoning:
		_cancel_summon()
	GhostForm.enter(self)
	if is_instance_valid(rig):
		# THE BODY LEFT BEHIND, spawned BEFORE the collapse so it is a snapshot of the
		# fighter as it stood, not of a heap. It folds and is RUBBED OUT — the run-end
		# card for a death is literally titled RUBBED OUT — while the pale, translucent
		# ghost the live body has just become drifts up out of it. That peel-apart is
		# the whole read: a drawing being erased, and the part of you that keeps going.
		#
		# It is a free-standing node that self-frees on a real-time clock; it holds no
		# reference to this hero and touches nothing the revive path reads.
		# Loaded BY PATH, never named — see the note in `Enemy._spawn_corpse`.
		var smudge: GDScript = load(DEATH_SMUDGE_SCRIPT) as GDScript
		if smudge != null:
			smudge.call("spawn", get_parent(), rig, HERO_CORPSE_COLOR,
				Vector2(-facing.x, 0.0), Vector2.ZERO, HERO_DEATH_BEAT)
		# ...and the body itself GOES DOWN on the real rig — the existing flop/limp
		# machinery held at full ragdoll, not a canned pose. See `CharacterRig.collapse`.
		rig.collapse(Vector2(-facing.x, -0.6))
	Sfx.play("hero_hurt", 0.0, 0.1)
	# SECOND WIND — only ever live if the maker has turned the solo charge on. See
	# `DeathRules.SOLO_SELF_REVIVE_CHARGES`; it ships at 0, so this is dead by default.
	if _self_revive_left > 0:
		_self_revive_left -= 1
		_second_wind_timer = DeathRules.SECOND_WIND_DELAY


## GHOST PHYSICS. Not a slump — a DRIFT. No gravity, no friction to a halt, full
## twin-stick steering at `GHOST_SPEED`, and `collision_layer == 0` (set by
## `GhostForm.enter`) so the body passes through everything except the arena walls
## its mask still respects.
##
## ⚠ THIS IS THE ANSWER TO "WHAT DOES A DOWNED PLAYER DO FOR 40 SECONDS". They fly to
## their teammate — the revive needs the two of you in the same place and the ghost is
## the one who can cross the room without dying — and then they HAUNT to blow the pack
## off the person picking them up. Both players are working. See `GhostForm.gd`.
func _process_downed(delta: float) -> void:
	_ghost_haunt_cd = maxf(_ghost_haunt_cd - delta, 0.0)
	if _second_wind_timer > 0.0:
		_second_wind_timer -= delta
		if _second_wind_timer <= 0.0:
			revive(DeathRules.REVIVE_HP_FRACTION)
			return
	var dir: Vector2 = _vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = velocity.move_toward(dir * GHOST_SPEED, GHOST_ACCEL * delta)
	move_and_slide()
	if dir.x != 0.0:
		facing = Vector2(signf(dir.x), 0.0)
	if is_instance_valid(rig):
		rig.set_body_velocity(velocity)
		rig.set_facing(facing)
		rig.set_airborne(1.0)   # a ghost never stands on anything
		rig.play(CharacterRig.State.HURT)
	if _ghost_haunt_cd <= 0.0 and _just(SPELL_ACTIONS[0]):
		_ghost_haunt()


## HAUNT — the ghost's one verb. A chalk gust that deals NO damage and shoves every
## enemy in `GHOST_HAUNT_RADIUS` directly away. It is how a dead player buys their
## rescuer the seconds the revive channel costs.
##
## Knockback goes through `Net.deal_knockback`, so it lands on each enemy's own
## authority (the host) exactly like every other force in the game — a client ghost
## shoving a host-owned enemy is the router's normal case, not a special one. The
## GUST is broadcast separately because the shove would otherwise be invisible magic
## on the other phone: bodies flying apart with nothing on screen that did it.
func _ghost_haunt() -> void:
	_ghost_haunt_cd = GHOST_HAUNT_COOLDOWN
	GhostForm.gust_on(self, GHOST_HAUNT_RADIUS)
	var live_net: bool = _net != null and _net.is_active()
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.is_queued_for_deletion() or not (e is Node2D):
			continue
		var to: Vector2 = (e as Node2D).global_position - global_position
		var d: float = to.length()
		if d > GHOST_HAUNT_RADIUS:
			continue
		var push: Vector2 = (to / maxf(d, 0.001)) * GHOST_HAUNT_FORCE
		if live_net:
			_net.deal_knockback(e, push)
		elif e.has_method("apply_knockback"):
			e.apply_knockback(push)
	Sfx.play("dash", -6.0, 0.08)
	_net_send("gh", {})


func is_downed() -> bool:
	return downed


## The same answer as `is_downed`, named for the thing the player sees. Read by
## `Revive` and by the party-wipe verdict.
func is_ghost() -> bool:
	return downed


## True while a SECOND WIND charge is resolving. `Arena._check_party_wipe` waits for
## this rather than calling the run over a body that is already coming back.
func awaiting_second_wind() -> bool:
	return _second_wind_timer > 0.0


## Come back up. `hp_fraction` is 1.0 for the party-carries-you cases (a floor
## advance) and `DeathRules.REVIVE_HP_FRACTION` for a teammate's revive — coming back
## at full would make dying a free heal, which is the one thing that would break the
## rule. Also a full clean reset so you resume upright: not mid-channel, not
## on-cooldown, not knocked-back, not ragdolling, not still on fire.
func revive(hp_fraction: float = 1.0) -> void:
	downed = false
	_second_wind_timer = 0.0
	_ghost_haunt_cd = 0.0
	_ghost_shown = false
	GhostForm.exit(self)
	hp = maxi(1, int(round(float(max_hp) * clampf(hp_fraction, 0.05, 1.0))))
	health_changed.emit(hp, max_hp)
	_dash_cooldown_timer = 0.0
	_cast_cooldown_timer = 0.0
	_melee_cooldown_timer = 0.0
	_blast_cooldown_timer = 0.0
	_blink_cooldown_timer = 0.0
	_nova_cooldown_timer = 0.0
	_parry_cooldown_timer = 0.0
	_hand.clear_cooldowns()  # every kit slot, not one shared bank
	if _channeling:
		_cancel_channel()
	if _summoning:
		_cancel_summon()
	_ragdolling = false
	_knockback = Vector2.ZERO
	velocity = Vector2.ZERO
	# A revive clears elemental ailments too — coming back up still burning is not a
	# revive, and the party has no way to cleanse.
	if _status != null and is_instance_valid(_status):
		_status.queue_free()
	_status = null
	# CLEAR A HELD BLADE GUARD. `_physics_process` returns early while downed, so a
	# player who was holding guard when they went down never gets their RELEASE seen
	# — and a ring left `held` blocks attacking and rooting FOREVER after the revive.
	# A genuine softlock, and the only place it can be reached.
	if _guard != null:
		_guard.release()
		_guard_bank = 0
		_guard_hits = 0
	if is_instance_valid(rig):
		rig.set_limp(0.0)   # clear the downed ragdoll
		rig.play(CharacterRig.State.IDLE)


# ------------------------------------------------------------- co-op networking
## Camera + synchronizer role. Only in a live session; SP leaves the camera as-is.
func _setup_net_role() -> void:
	if _net == null or not _net.is_active():
		return
	_setup_net_sync()
	var cam := get_node_or_null("Camera2D") as Camera2D
	if is_multiplayer_authority():
		if cam != null:
			cam.make_current()   # the local hero owns the viewport
	elif cam != null:
		cam.enabled = false      # remote heroes never steal the view


## A MultiplayerSynchronizer that streams this hero's transform + state from its
## owner to every peer. Built in code (no .tscn surgery).
## ⚠ THE SYNC SET IS THE FEATURE, not bookkeeping. What was here before —
## position / velocity / facing / hp / net_class / downed — left a teammate as a
## sliding run cycle with a lying health bar: `max_hp` was absent (so a remote bar
## read a Juggernaut's 140 hp against the local class's denominator), and aim,
## element, casting, guard/parry and dash state crossed no wire at all.
##
## BANDWIDTH. Everything used to stream at the physics rate, which on phone wifi is
## 60 packets a second per body for values nobody can perceive at that resolution.
## The transform block now runs at 30 Hz (`replication_interval`) and the
## on-change block is batched at 10 Hz (`delta_interval`); the on-change properties
## are only sent when they actually change, so the anim/flag/element fields cost
## nothing while a hero stands still. 30 Hz is a deliberate floor rather than the
## lowest number that "looks fine" — at DASH_SPEED a body covers ~30 px per tick,
## and coarser than that starts to read as teleporting rather than moving.
const NET_TRANSFORM_HZ: float = 30.0
const NET_STATE_HZ: float = 10.0


func _setup_net_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for p: String in [":position", ":velocity", ":facing", ":hp", ":max_hp", ":net_class",
			":downed", ":net_anim", ":net_aim", ":net_element", ":net_flags"]:
		cfg.add_property(NodePath(p))
	cfg.property_set_replication_mode(NodePath(":position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(":velocity"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	sync.root_path = NodePath("..")   # relative to this Hero
	sync.replication_config = cfg
	sync.replication_interval = 1.0 / NET_TRANSFORM_HZ
	sync.delta_interval = 1.0 / NET_STATE_HZ
	add_child(sync)
	sync.set_multiplayer_authority(get_multiplayer_authority())


## Publish what this body is DOING so every other screen can draw it. Called from
## `_process` on the owner only. Reads the rig rather than reconstructing state from
## velocity: the rig already knows whether it is mid-swing, mid-cast or gripping a
## wall, and guessing that from a velocity vector is exactly what made teammates
## look like they were permanently jogging.
func _publish_net_state() -> void:
	net_aim = _aim_dir
	net_element = _element
	if is_instance_valid(rig):
		net_anim = int(rig.state)
	var f: int = 0
	if _guard != null and _guard.blocks_attack():
		f |= NET_F_GUARD
	if _parry_window_timer > 0.0:
		f |= NET_F_PARRY
	if _channeling or _summoning:
		f |= NET_F_CASTING
	if is_dashing:
		f |= NET_F_DASH
	if _ragdolling:
		f |= NET_F_LIMP
	net_flags = f


## Remote heroes animate from the replicated state set. No input, no physics, no
## damage — everything here is drawing.
func _remote_visual(delta: float) -> void:
	if not is_instance_valid(rig):
		return
	# GHOST FORM ON THE OTHER PHONE. `downed` replicates; the ghost's LOOK does not,
	# so the flag is edge-detected here and the same `GhostForm` the owner wears is
	# grown and shed on the puppet. Without this a downed teammate is just a teammate
	# who stopped moving — and "is my friend dead or lagging" is not a question a
	# co-op game gets to leave open.
	if downed != _ghost_shown:
		_ghost_shown = downed
		if downed:
			GhostForm.enter(self)
		else:
			GhostForm.exit(self)
	if net_element != _remote_element:
		_remote_element = net_element
		_element = net_element
		_element_color = Elements.color(net_element)
		rig.set_aura(_element_color, 0.5)
	rig.set_body_velocity(velocity)
	rig.set_aim(net_aim)
	if downed:
		# A drifting ghost, not a corpse: it is still being steered on its own phone,
		# so the puppet reads the synced velocity and stays loose and airborne.
		rig.set_limp(1.0)
		rig.set_airborne(1.0)
		rig.set_facing(facing)
		rig.play(CharacterRig.State.HURT)
		return
	# The hold-DOWN flop is a sustained limp, not a state — it has no rig State of
	# its own, which is why it rides a flag.
	rig.set_limp(1.0 if (net_flags & NET_F_LIMP) != 0 else 0.0)
	rig.set_grounded(is_on_floor())
	# Edge-triggered one-shots. The parry SHELL is a timed visual the rig plays out
	# on its own, so re-issuing it every frame the bit is set would freeze it open.
	var rising: int = net_flags & ~_remote_flags
	if (rising & NET_F_PARRY) != 0 or (rising & NET_F_GUARD) != 0:
		rig.set_parry(net_aim, PARRY_SHIELD_TIME)
	_remote_flags = net_flags
	# A levitating cast dangles its legs and holds a committed pose; the summon sigil
	# it opened has to be carried and grown here, because `_process_summon` (which
	# does that for the owner) lives behind the authority gate in `_physics_process`.
	if (net_flags & NET_F_CASTING) != 0:
		rig.set_airborne(true)
		_tick_remote_cast_sigil(delta)
	else:
		rig.set_airborne(0.0)
	# Facing: while striking, the body turns to the aim (same rule the owner uses);
	# otherwise it follows travel, so a teammate backpedalling reads as backpedalling.
	if rig.is_striking() or (net_flags & NET_F_CASTING) != 0:
		rig.set_facing(net_aim)
	else:
		rig.set_facing(facing)
	rig.play(net_anim as CharacterRig.State)


## Grow + carry the puppet's cast sigil during a replayed windup. Mirrors the
## owner-side growth in `_process_summon` / `_process_channel` without any of the
## physics those functions also own.
func _tick_remote_cast_sigil(delta: float) -> void:
	if _cast_sigil == null or not is_instance_valid(_cast_sigil):
		return
	_remote_cast_elapsed += delta
	_cast_sigil.global_position = _cast_sigil_pos()
	var total: float = maxf(_remote_cast_total, 0.001)
	var prog: float = clampf(_remote_cast_elapsed / total, 0.0, 1.0)
	_cast_sigil.scale = Vector2.ONE * (0.55 + 0.7 * prog)


@rpc("any_peer", "call_remote", "reliable")
func _net_take_damage(amount: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
	take_damage(amount)


@rpc("any_peer", "call_remote", "reliable")
func _net_apply_knockback(impulse: Vector2) -> void:
	apply_knockback(impulse)


@rpc("any_peer", "call_remote", "reliable")
func _net_apply_status(element: int, can_chain: bool = true) -> void:
	apply_status(element, can_chain)


# ==================================================== HERO SPELL REPLICATION
## Broadcast one thing this hero just did. No-op in single player, on a puppet, and
## for a bot (a bot-driven hero in the versus sandbox is not a networked player).
##
## The payload keys are deliberately terse — these go out on every cast, and on a
## phone the difference between `"aim"` and `"aim_direction"` is real traffic.
func _net_send(kind: String, data: Dictionary = {}) -> void:
	if _net == null or not _net.is_active() or not is_multiplayer_authority():
		return
	if not data.has("aim"):
		data["aim"] = _aim_dir
	if not data.has("pt"):
		data["pt"] = _aim_point()
	data["el"] = _element
	_net.broadcast_hero_action(kind, data)


## REBUILD another player's action on this screen.
##
## ⚠ THE FRIENDLY-FIRE TOGGLE IS LOAD-BEARING AND IT IS NOT A HACK. `attack_group()`
## already answers `NET_GHOST_GROUP` for a puppet — but `SpellCaster._stamp` does not
## write what it is given, it writes `damage_group(...)`, which folds EVERY group to
## `mortal` while friendly fire is on. So the ghost group would be erased on its way
## into the spectacle. Turning the substitution off for the duration of the rebuild
## is what lets the dead group survive `_stamp`, and it is the documented one-line
## switch on that static rather than a new concept.
##
## Synchronous throughout: `SpellCaster.cast` builds and fires inside this call, so
## the toggle is never observable by another cast.
## ⚠ RETURNS BOOL, AND THAT IS A TEST AFFORDANCE RATHER THAN AN API NICETY. A dead
## property read ABORTS the enclosing function in GDScript and hands the caller back
## the type's zero — the exact failure mode that once left 64 suites green while
## testing nothing. So this reports whether it reached the end, `Net` counts only the
## true answers, and a replay that aborts half-way makes the smoke test fail BY
## ABSENCE instead of quietly reporting a spell it never actually drew.
func net_replay_action(kind: String, data: Dictionary) -> bool:
	if is_multiplayer_authority() or not is_instance_valid(rig):
		return false
	# A ghost cannot cast — but it CAN haunt, and the gust is the one thing a downed
	# teammate does that the living player has to be able to see. So `gh` is the sole
	# kind allowed through the downed gate.
	if downed and kind != "gh":
		return false
	var prev_ff: bool = SpellCaster.friendly_fire
	SpellCaster.friendly_fire = false
	_replaying = true
	_replay_point = data.get("pt", global_position)
	_aim_dir = data.get("aim", _aim_dir)
	facing = _aim_dir
	_element = int(data.get("el", _element))
	_element_color = Elements.color(_element)
	_net_dispatch_replay(kind, data)
	_replaying = false
	SpellCaster.friendly_fire = prev_ff
	return true


func _net_dispatch_replay(kind: String, data: Dictionary) -> void:
	match kind:
		"cb":   # signature windup began (the summoning ceremony + the DECLARE card)
			_replay_cast_begin(data)
		"cx":   # windup interrupted — shatter the sigil, no spell
			if _channeling:
				_cancel_channel()
			elif _summoning:
				_cancel_summon()
			_remote_cast_total = 0.0
		"cf":   # the eruption
			_replay_cast_fire(data)
		"pr":
			_cast()
		"q":
			_blast()
		"nv":
			_spawn_nova()
		"ml":
			_melee()
		"uc":
			_uppercut()
		"py":
			_try_parry_start()
		"ds":
			_replay_dash(data.get("dir", _aim_dir), String(data.get("vb", "dash")))
		"bl":
			_replay_blink(data.get("to", global_position))
		# ⚠ NO "rc" CASE ANY MORE. It replayed the Arcanist's recall return leg, which
		# no longer exists; the Arcane Phase is a TRAVEL, so it crosses the wire on the
		# ordinary "ds" dash packet like the other six and `_replay_dash` draws its
		# echo. An "rc" from a stale peer falls through this match harmlessly.
		"lb":   # STORMCALLER — the lightning blink's crackle at both ends
			_lightning_blink_fx(global_position, data.get("to", global_position))
		"sw":   # WARLOCK — the thrall swap's two poofs (see `_replay_swap`)
			_replay_swap(data.get("to", global_position), data.get("th", global_position))
		"gh":   # a ghost's HAUNT gust — the shove already crossed via the knockback
			# router, so all that is missing on this screen is the thing that did it.
			GhostForm.gust_on(self, GHOST_HAUNT_RADIUS)


## The windup. `_begin_summon` / `_begin_channel` do exactly the right things for a
## puppet — pose, gesture, sigil, declare card, charge-up sfx — and the only parts
## they own that a puppet must not run are the per-frame lift and the fire, both of
## which live in `_process_summon` / `_process_channel` behind the authority gate.
func _replay_cast_begin(data: Dictionary) -> void:
	var spell: SpellDef = _net_spell(String(data.get("sid", "")))
	if spell == null:
		return
	_remote_cast_elapsed = 0.0
	_remote_cast_total = float(data.get("w", 0.4))
	if bool(data.get("ch", false)):
		_begin_channel(spell, bool(data.get("sky", false)))
	else:
		_begin_summon(spell, bool(data.get("sky", false)), int(data.get("sp", SUMMON_NORMAL)))


## The eruption. Routed through the SAME `_finish_*` the owner used, so the puppet
## gets the identical spectacle, recoil animation, epic beat and sigil handoff —
## disarmed only by the ghost group.
func _replay_cast_fire(data: Dictionary) -> void:
	var spell: SpellDef = _net_spell(String(data.get("sid", "")))
	if spell == null:
		return
	_remote_cast_total = 0.0
	var sky: bool = bool(data.get("sky", false))
	var target: Vector2 = data.get("pt", global_position + _aim_dir * 200.0)
	if _channeling:
		_channel_spell = spell
		_channel_sky = sky
		_channel_target = target
		_finish_channel()
		return
	# A packet that arrives without its windup (loss, or a peer that joined between
	# the two) still fires: `_finish_summon` reads only these fields.
	_summoning = true
	_summon_spell = spell
	_summon_sky = sky
	_summon_special = int(data.get("sp", SUMMON_NORMAL))
	_summon_aim = _aim_dir
	_summon_target = target
	_finish_summon()


## Resolve a spell id. The puppet's own kit first (it is already built from the
## synced class and costs nothing), then the whole tree — a peer whose class table
## has not landed yet must still be able to draw the spell it just saw thrown.
func _net_spell(sid: String) -> SpellDef:
	if sid == "":
		return null
	for s: SpellDef in _signatures:
		if s != null and s.id == sid:
			return s
	var v: Variant = SpellLibrary._spell_by_id().get(sid)
	return v as SpellDef if v != null else null


## A dash on someone else's screen is the afterimage trail, not the displacement —
## position comes from the synchronizer, so moving the body here would fight it.
## CO-OP: the movement button, on somebody else's screen.
##
## THE RULE, and it is the one `blink_to` already writes down: a puppet is NEVER
## DISPLACED here. Position on a non-authority peer comes from the
## MultiplayerSynchronizer, so writing `global_position` in a replay would fight it and
## snap back. What crosses the wire is the READ — the trail, the poofs, the crackle —
## because without it a teammate simply teleports with no explanation, which looks like
## a dropped packet rather than an ability.
##
## `vb` carries WHICH verb it was so the trail is the right colour on both screens; an
## old peer that does not send the key falls back to the shared dash trail.
func _replay_dash(dir: Vector2, verb: String = "dash") -> void:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else facing
	var prev: String = _dash_verb
	_dash_verb = verb  # only so `_travel_ghost_color` reads the right one
	rig.set_facing(d)
	rig.play(CharacterRig.State.DASH)
	var trail: Color = _travel_ghost_color()
	_dash_verb = prev
	for i: int in 3:
		rig.spawn_ghost(get_parent(), trail, d)
	# THE ARCANIST'S ECHO CROSSES TOO. `_begin_verb_extras` draws it for the owner; a
	# teammate who only saw the trail would read the phase as an ordinary dash and have
	# no idea why their hit passed through. The one verb that is invulnerable for its
	# whole duration is the one that most needs the other screen to understand it.
	# (This replaces `_replay_recall`, which drew the deleted return leg's two poofs.)
	if verb == "arcane_phase":
		rig.spawn_ghost(get_parent(), ARCANE_PHASE_COLOR, Vector2.ZERO, Vector2.ZERO,
			ARCANE_PHASE_ECHO_FADE)
		CombatVfx.spawn_burst(get_parent(), global_position, ARCANE_PHASE_COLOR,
			BLINK_BURST_END, 10, 0.5, 10.0, 30.0, 1.0, 2.0)
	Sfx.play("dash", -4.0, 0.06)


## WARLOCK swap, replayed — and THE HONEST LIMIT OF THIS PASS, stated where it happens.
##
## The HERO half is correct on both screens: the poofs are drawn at both ends and the
## body arrives via the synchronizer, same as every other teleport in this file. The
## THRALL half is NOT replicated. The minion's displacement is a write to another
## agent's node, and whether that node is host-authoritative, synchronized, or
## client-local is a fact this file does not get to assume. Rather than guess and ship a
## desync, the remote copy draws the second poof at the swap point and leaves the
## minion's position to whoever owns it.
##
## The failure is SAFE: a teammate sees the swap happen, sees the shadow at the far end,
## and the worst case is that the minion visibly catches up a moment later. Nothing is
## displaced twice, nothing is stranded, and no position is written on a peer that does
## not own it. It needs a second pass once the minion's own net role exists.
func _replay_swap(dest: Vector2, thrall_at: Vector2) -> void:
	var origin: Vector2 = global_position
	rig.spawn_ghost(get_parent(), THRALL_SWAP_START, Vector2.ZERO, Vector2.ZERO, 0.32)
	CombatVfx.spawn_burst(get_parent(), origin, THRALL_SWAP_START, THRALL_SWAP_END,
		20, 0.35, 50.0, 150.0, 1.5, 3.0)
	CombatVfx.spawn_burst(get_parent(), dest, THRALL_SWAP_START, THRALL_SWAP_END,
		20, 0.35, 50.0, 150.0, 1.5, 3.0)
	CombatVfx.spawn_burst(get_parent(), thrall_at, THRALL_SWAP_START, THRALL_SWAP_END,
		14, 0.3, 40.0, 110.0, 1.5, 3.0)
	rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("blink", -1.0, 0.1, 0.7)


## The blink's two poofs, drawn at the ends the owner actually used. The teleport
## itself arrives via the synchronizer; what does not arrive is the READ — without
## the shadow at the origin and the flash at the destination a teammate simply
## vanishes and reappears, which looks like a dropped packet rather than a spell.
func _replay_blink(dest: Vector2) -> void:
	var origin: Vector2 = global_position
	rig.spawn_ghost(get_parent(), BLINK_SHADOW_COLOR, Vector2.ZERO, Vector2.ZERO, 0.35)
	CombatVfx.spawn_burst(get_parent(), origin, BLINK_BURST_START, BLINK_BURST_END,
		18, 0.35, 40.0, 110.0, 1.5, 3.0)
	CombatVfx.spawn_burst(get_parent(), dest, BLINK_BURST_START, BLINK_BURST_END,
		24, 0.4, 60.0, 140.0, 1.5, 3.5)
	rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("blink", 0.0, 0.1)


# ------------------------------------------------------------ elemental ailments
## HEROES CAN BE BURNED NOW. Every spell in the game carries an element and calls
## `apply_status` on what it hits — but only `Enemy` ever implemented it, so the
## `has_method` guard at each of those ~20 call sites silently answered false for a
## hero and the ailment evaporated. With friendly fire on, that is the difference
## between setting your teammate on fire and doing nothing visible at all.
##
## Reuses `StatusComponent` verbatim (it drives itself off `get_parent()`'s
## `take_damage` + transform, both of which a Hero has). The only thing this file
## has to do is READ the slow it produces — see `_status_speed_mult`.
func apply_status(element: int, can_chain: bool = true) -> void:
	if downed or element < 0:
		return
	if _status == null or not is_instance_valid(_status):
		_status = StatusComponent.new()
		add_child(_status)
	_status.apply(element, can_chain)


## Movement multiplier from any active ailment (chill/freeze/shock/stagger). 1.0
## when nothing is on you, which is the overwhelmingly common case.
func _status_speed_mult() -> float:
	if _status == null or not is_instance_valid(_status):
		return 1.0
	return _status.slow_factor()


## Publish the live ailment to the rig so it can draw it ON the limbs.
##
## ⚠ THE HERO NEVER DID THIS AT ALL. `Enemy` pushed `set_frozen` every frame; the Hero
## pushed nothing, so a burning or frozen PLAYER got only whatever the StatusComponent
## drew for itself — which was the mis-centred overlay this change deletes. Called from
## `_physics_process` so the coat tracks the pose rather than the last time an ailment
## was applied.
func _push_status_to_rig() -> void:
	if not is_instance_valid(rig) or not rig.has_method(&"set_status"):
		return
	var live: bool = _status != null and is_instance_valid(_status)
	rig.set_status(
		_status.status_bits() if live else 0,
		_status.tint() if live else Color.WHITE)


## Record the element behind an actual thrown ability into the run outcome
## (guarded — no-op in the sandbox).
func _notify_element_used() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.notify_element_used(Elements.display_name(_element))
