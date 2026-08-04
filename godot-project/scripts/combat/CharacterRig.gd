class_name CharacterRig
extends Node2D
## Procedural stick-figure visual rig. Placeholder for real animated stick
## sprites later — the public API (play/set_facing/set_tint/flash/
## set_equipment/class_preset + hit_frame) is the swap contract.

signal hit_frame
## Fires the instant the RUN cycle plants a foot — i.e. on the frame the visible
## body bob bottoms out. Hooked for the footstep sound below; also the right hook
## for anything else that should land on a footfall (dust puffs, screen wobble)
## instead of on a separate timer that will drift out of sync with the feet.
signal foot_planted

## AIR is the jump/fall/land locomotion state (added at the END so existing
## indices are stable). Hero drives it via play(State.AIR) + set_air_phase(...).
enum State { IDLE, RUN, DASH, CAST, PUNCH, KICK, HURT, WALL_SLIDE, AIR }

## One-shot states auto-return to IDLE after their fixed duration.
const ONE_SHOT_DURATIONS: Dictionary = {
	State.PUNCH: 0.22,
	State.KICK: 0.26,
	State.CAST: 0.28,
	State.HURT: 0.18,
}
## Fraction of a PUNCH/KICK duration at which hit_frame fires. Tightened 0.55 -> 0.35
## so the hit lands closer to the click (deferred from Task 5 — the const lives here).
const HIT_FRAME_FRACTION: float = 0.35

## Cast-gesture kinds — a small vocabulary of LIMB-ISOLATED "turn-on" tells that
## OVERLAY the lead arm only, so they compose over any locomotion (run/jump/dash).
## The ULTIMATE tier (float-channel) is a SEPARATE channel (Hero-side), not here.
enum GestureKind { NONE, FLICK, IGNITE_DROP, RAISE, GATHER, STOMP }

const GESTURE_DURATIONS: Dictionary = {
	GestureKind.FLICK: 0.12,        # quick snap — light bolts
	GestureKind.IGNITE_DROP: 0.20,  # hand drops, fist ignites — the fire-fist tell
	GestureKind.RAISE: 0.30,        # arm gathers overhead — medium AoE
	GestureKind.GATHER: 0.50,       # both hands to chest then thrust — heavy
	GestureKind.STOMP: 0.24,        # fist drives down + foot plant — earth
}

## Melee feel tuning. The strike curve is: wind BACK for the first
## STRIKE_ANTICIPATION_FRACTION of the one-shot (down to -STRIKE_PULLBACK
## extension), then snap forward (cubic ease-out) to full extension exactly
## at HIT_FRAME_FRACTION, then follow through back to rest.
const STRIKE_ANTICIPATION_FRACTION: float = 0.30
const STRIKE_PULLBACK: float = 0.35
## Squash-stretch impact pop: draw-time size multiplier applied when
## hit_frame fires, easing back to 1.0 over POP_TIME seconds.
const POP_SCALE: float = 1.12
const POP_TIME: float = 0.1
## Flight: fraction of the figure's height it rises at full airborne (set_airborne).
const AIRBORNE_LIFT_FACTOR: float = 0.7
## Slash-arc swoosh: visible over [start, end] of the one-shot's normalized
## time, sweeping SLASH_ARC_SPAN radians at radius height * factor.
const SLASH_ARC_START: float = 0.38
const SLASH_ARC_END: float = 0.9
const SLASH_ARC_SPAN: float = 1.5
const SLASH_ARC_RADIUS_FACTOR: float = 0.52

## Dash afterimages: script loaded lazily to keep the dependency one-way
## (RigGhost references CharacterRig for the shared figure draw).
const GHOST_SCRIPT_PATH: String = "res://scripts/combat/RigGhost.gd"
const MAX_GHOSTS: int = 24
## Aura tuning: layer count + pulse speed/amount.
const AURA_LAYERS: int = 3
const AURA_PULSE_SPEED: float = 3.2
const AURA_PULSE_AMOUNT: float = 0.15
## Rank-driven aura escalation. Tier 0 = aura off; tier 1 = the baseline aura
## (exactly the pre-rank look); tiers 2..5 stack intensity, extra silhouette
## layers, orbiting motes, and (tier >= 3) a rotating ground ring. Everything
## is element-coloured via `aura_color`.
const AURA_TIER_MOTES: Array[int] = [0, 0, 4, 6, 9, 12]
const AURA_TIER_STRENGTH_STEP: float = 0.14  # +strength per tier above 1
const AURA_TIER_PULSE_STEP: float = 0.25     # +pulse fraction per tier above 1
const MOTE_ORBIT_RADIUS_FACTOR: float = 0.7  # orbit radius = height * this
const MOTE_ORBIT_SPEED: float = 1.6          # rad/s around the figure
const MOTE_PULSE_SPEED: float = 4.2          # alpha shimmer speed
const GROUND_RING_MIN_TIER: int = 3
const GROUND_RING_SPIN_SPEED: float = 1.1    # rad/s arc rotation
## Crisp Stick-Fight read: a dark outline drawn under the bold limb colour, and
## how much wider than the limb the outline extends (px). The main _draw passes
## OUTLINE_COLOR; the aura silhouette + dash ghosts draw outline-less (soft).
const OUTLINE_COLOR: Color = Color(0.04, 0.04, 0.07, 1.0)   # true dark keyline — bold SF silhouette against any bg
## Keyline width, as a FRACTION of the limb width rather than a flat +2 px. It used
## to be an absolute, which was survivable while limbs were 16% of height (5 px at
## the default) but swamps the now-spindly stroke (a flat +2 on a 2.3 px limb is a
## keyline nearly as wide as the limb, and the figure turns back into a black blob).
## Scaling it keeps the exact same read at every rig height AND every stroke weight.
const OUTLINE_FACTOR: float = 0.62
## Absolute floor so the keyline never vanishes on a tiny rig at 640x360.
const OUTLINE_MIN: float = 1.0

## --- STICKMAN PROPORTIONS ---
## The maker has said twice, flatly: "the characters are not stickmen, I just want to
## see STICKMEN". These two numbers are why. They were 0.18 (head) and 0.16 (limb),
## i.e. a head 36% of the figure's height and limbs a sixth of it — bobble-headed and
## stubby, which reads as a chibi mascot, not a stick figure.
##
## The hand-tuned spike rig (scripts/spike/SpikeFigure.gd, the look the maker signed
## off on) sits at head r ~= 0.094 of height and stroke ~= 0.064: SPINDLY. These are
## pulled to just above the spike's numbers — a hair bolder, because this rig draws at
## ~31 px against the spike's ~86 px and has to survive a 640x360 backbuffer.
##
## ⚠ Enemy.RIG_HEAD_R_FACTOR MIRRORS HEAD_R_FACTOR and must move with it, or the hit
## silhouette drifts off the drawing and spells start passing through heads again.
## The head TOP still lands exactly at -height/2 either way (head_center = -h/2 + r),
## so nothing that frames off the figure's extents changes.
const HEAD_R_FACTOR: float = 0.105
const LIMB_W_FACTOR: float = 0.075
## --- Active-ragdoll spring sim: the DRAWN limbs physically lag/swing/flail
## toward the procedural pose (_compute_pose is the animation TARGET) instead
## of snapping to it, and go limp on death. Stable point-mass springs in LOCAL
## space — deliberately NOT RigidBody2D/PinJoint2D, which explode and fight the
## kinematic controller. ---
## Joints driven by the sim; neck is re-derived from head_center in _sim_pose().
const SIM_JOINTS: Array[String] = [
	"head_center", "shoulder", "hip",
	"hand_lead", "hand_off", "foot_lead", "foot_off",
]
## Extremities flail harder on impulses + receive the inertial trail nudge.
const SIM_EXTREMITIES: Array[String] = [
	"head_center", "hand_lead", "hand_off", "foot_lead", "foot_off",
]
const STIFFNESS: float = 180.0         # STIFF — the resting/running pose SETTLES, no float smear
## Full-ragdoll (_limp==1) stiffness floor: an ABSOLUTE value (not a fraction of the
## now-higher STIFFNESS) so taming the resting pose can't also tame the post-hit HURT
## flail / hold-DOWN ragdoll. Matches the pre-tame feel exactly (old STIFFNESS=60 *
## 0.05 == 3.0). See _step_sim: stiffness = lerpf(STIFFNESS, FULL_LIMP_STIFFNESS, _limp).
const FULL_LIMP_STIFFNESS: float = 3.0
const DAMPING: float = 8.0             # less = more overshoot/swing (still stable)
## ⚠ THE DAMPING HAS TO GO SLACK WITH THE SPRING, AND IT DID NOT. THIS IS WHY A HIT
## OOZED INSTEAD OF FLAILING.
##
## `DAMPING` was applied FLAT at every looseness while the stiffness dropped 60-fold
## (STIFFNESS 180 -> FULL_LIMP_STIFFNESS 3). Damping ratio is `c / (2 * sqrt(k))`, so
## holding `c` while `k` collapses does not merely damp the ragdoll, IT INVERTS IT:
##
##     grounded   k=180  c=8   -> w 13.4 rad/s, zeta 0.30   underdamped, springy
##     full limp  k=3    c=8   -> w  1.7 rad/s, zeta 2.31   OVERDAMPED — no swing at all
##     limp legs  k=1.5  c=8   -> w  1.2 rad/s, zeta 3.27   worse still
##
## A zeta above 1 cannot overshoot, so at full ragdoll every limb crept toward its
## target on a monotone curve. That is a body sagging, not a body flailing, and it is
## the exact opposite of what going limp is supposed to look like.
##
## SpikeFigure — the signed-off reference — damps its SLACK limbs at 2.0 / 2.5 / 2.2 /
## 3.0 (`ARM_AIR_DAMP`, `FARM_AIR_DAMP`, `LEG_AIR_DAMP`, `SHIN_AIR_DAMP`) against 11
## and 9 for the same limbs planted. Its slack zetas land at 0.19-0.22. Those constants
## are UNIT-COMPATIBLE with this one — both sides are an exponential velocity decay
## rate in 1/s (`vel *= exp(-c*dt)` there, `vel *= 1 - c*dt` here) — so this is a port
## of the spike's number, not a guess: their mean is 2.4.
##
## Lerped by `loose` in _step_sim, so the resting/running pose keeps DAMPING exactly
## and only a genuine flop/air/death gets the slack value.
const LIMP_DAMPING: float = 2.5
## The FEET spring softer than the rest — but ONLY as the body goes limp (the
## post-hit HURT flail / hold-DOWN ragdoll). At rest _limp is 0, so the legs spring
## at FULL stiffness and plant firmly; they only go loose/flowy under a real flop.
## (See _step_sim: leg_stiffness = stiffness * lerpf(1, LOOSE_LEG_STIFFNESS, _limp) —
## at full limp this derives 3.0 * 0.5 == 1.5, the pre-tame full-flail leg stiffness.)
const LOOSE_LEG_STIFFNESS: float = 0.5
const GRAVITY: float = 800.0           # applied only when limp (ragdoll droop)
const MAX_OFFSET_FACTOR: float = 0.35  # limbs settle tight to the pose; only a limp flail drifts far
## Full-ragdoll (_limp==1) offset clamp: the pre-tame amplitude, restored ONLY as the
## body goes limp (see _step_sim: max_off = height * lerpf(MAX_OFFSET_FACTOR,
## FULL_LIMP_OFFSET_FACTOR, _limp)) so the resting pose stays tight but a real flail
## still has its old reach.
const FULL_LIMP_OFFSET_FACTOR: float = 0.85
const LIMP_EASE_SPEED: float = 5.0     # _limp eases toward _limp_target at this /s
## Airborne active-ragdoll looseness (NO canned jump pose — maker directive: "ragdoll
## exactly like Stick Fight"). While the AIR state is active the spring is lerped
## PARTWAY toward the full-limp flail — never all the way (full limp stays reserved for
## hits / flop()) — so the DRAWN limbs trail + swing with the body's momentum + gravity
## while the weighty CharacterBody2D arcs. Falling is a touch looser than rising (a loose
## drop vs a coiled leap). Combined with _limp via maxf so a hit mid-air still hits FULL
## limp. Eased faster than _limp so landing settles back to the foot-planted stance promptly.
const AIR_LOOSE_FALLING: float = 0.55   # ~halfway to full limp on the way down
const AIR_LOOSE_RISING: float = 0.42    # slightly tighter ascending (coiled leap)
const AIR_LOOSE_EASE_SPEED: float = 9.0
## ⚠ THE ONE THING THE SPIKE'S AIRBORNE LIMBS HAVE THAT THIS RIG HAD NOTHING FOR.
##
## `SpikeFigure._update_legs` / `_update_arms` add `FLAIL_NOISE` (7.0 rad/s^2 of a
## two-sine pseudo-random churn, per limb, seeded per figure) to every slack limb. It
## is what stops an airborne ragdoll being a smooth pendulum: real limbs judder. This
## rig had no equivalent term at all, so a loose limb swung on a perfectly clean arc.
##
## Ported as a LENGTH-scaled acceleration because this rig's springs are positional
## where the spike's are angular: 7 rad/s^2 on its ~30 px limb is ~210 px/s^2 of
## tangential acceleration, and the two-sine sum spans +/-2, so the peak is ~420 px/s^2
## on an 84 px figure = 5.0 heights/s^2. Halved from there because it is applied on BOTH
## axes here rather than tangentially only. Scaled by `loose`, so a planted figure never
## sees it, and applied to the EXTREMITIES only (hands, feet, head) — a churning hip is
## a glitch, a churning hand is a ragdoll.
const FLAIL_NOISE: float = 2.4
const IMPULSE_EXTREMITY_MULT: float = 2.6  # hands/feet/head whip harder on hits
## Clash recoil amplitude (see clash_recoil). Louder than the ordinary knockback
## flop Hero.apply_knockback fires (0.2..0.7 limp, ~680 jolt) because meeting a
## blow head-on stops the arm dead, where a knockback only shoves the torso.
## UNTESTED GUESS — tune with MeleeClash's budget, not on its own.
const CLASH_FLOP: float = 0.62
const CLASH_FLOP_HOLD: float = 0.20
const CLASH_LIMB_JOLT: float = 900.0
## Death topple (see `collapse`). Sits BETWEEN an ordinary knockback flop (~680) and
## a clash (900): a dying body is not being punched harder than a living one, it is
## simply not resisting, and the `set_limp(1)` that goes with this is what makes the
## same jolt read as a topple rather than a stagger. UNTESTED GUESS — judged by eye
## in `tools/death_collapse_capture.gd`, never by a number.
const DEATH_TOPPLE_IMPULSE: float = 760.0
## rad/s of torso spin a death is GUARANTEED, in the direction the body is going to
## sprawl (see `collapse`). Sized so the ~1.42 rad fall (`PRONE_LEAN`) is most of the
## way done inside the bot match's 0.55 s `FREEZE_BEAT`, which is the window the KO is
## actually looked at in. UNTESTED GUESS — judged in `tools/death_capture.gd`.
const DEATH_SPIN: float = 3.4
## Looseness a death STARTS at, so `_step_body`'s sprawl branch (`loose > 0.35`) is
## already engaged on the frame the body dies. See the note in `collapse` — the rest
## of the way to full limp still eases at `LIMP_EASE_SPEED`.
const DEATH_LIMP_SNAP: float = 0.55
const BODY_TRAIL_FACTOR: float = 0.26  # more inertial limb-trail on launch/stop
## RUN arm-swing frequency. Since the WORLD-LOCKED gait (below) took over the legs
## this only drives the arm counter-swing and the idle breath; the legs no longer
## read off it at all. Kept as the public stride-rate knob (tests + tuning).
const RUN_PHASE_RATE: float = 9.0

## --- WORLD-LOCKED FOOT PLANTS (ported from SpikeFigure._update_legs) ---
## THE anti-slide. A phase-driven sine gait makes the feet skate along the ground —
## the figure jogs in place while the body translates, which is exactly the "old
## stickman" read. Instead a foot is NAILED to a WORLD position and stays there while
## the body travels over it; when the hip gets STEP_TRIGGER ahead of the rearmost
## plant, that foot swings through a lifted arc to a new plant STEP_LENGTH ahead.
## The contact point does not move while it bears weight, so the ground grips.
##
## ⚠ WHAT WENT WRONG THE FIRST TWO TIMES, AND WHAT THE UNIT OF EACH NUMBER IS.
##
## A gait has two independent quantities and they are NOT the same kind of thing:
##   * LENGTHS (stance width, foot lift, plant distance) scale with the figure.
##   * TIMES (how long a leg takes to swing through) do NOT. A swing is a pendulum
##     of flesh; a small fighter does not swing its leg six times faster because it
##     is small, and neither does a fast one.
## The first port treated the lengths as fractions of LEG REACH and the swing TIME as
## a fraction of the step interval (`SWING_DUTY`, swing rate = speed / step length).
## Both are wrong in the same direction, and together they produce the bug the maker
## has now reported twice:
##
##   Deriving the swing rate from speed holds the STRIDE constant and lets the
##   CADENCE scale linearly with speed. So the figure does not lengthen its stride
##   when it runs — it takes the same little 9.5 px step faster and faster. MEASURED
##   (tools/rig_gait_measure.gd): stride 0.31 body-heights at 40, 140, 210 AND
##   300 px/s, while cadence went 4.0 -> 14.7 -> 22.0 -> 28.0 steps per second.
##   SpikeFigure, at matched speed, does the opposite and correct thing: cadence
##   7.3 -> 7.7 steps/s across a 43% speed change, stride 0.32 -> 0.44 heights.
##   Twenty-two steps a second is not a stride, it is a buzz, and a buzz on
##   world-locked feet is exactly "why are they walking on their legs".
##
## So the swing rate is now ABSOLUTE, in seconds, copied from SpikeFigure:2047, and
## the STRIDE is derived from it — `step_len = speed * swing_time + reach`, i.e. plant
## the foot where the hip WILL BE when the swing ends, plus a little forward reach.
## The spike gets the same answer with a hardcoded 30 px only because 30 px happens to
## be `speed * swing_time` at the one speed it was tuned at; write it out and it works
## at every speed and every figure size, which is what this rig needs.
##
## Lengths are still fractions, but of HEIGHT, not of leg reach. The spike's leg is
## 0.51 of its height and this rig's is 0.40, so matching the spike "as a fraction of
## leg" silently shrank every length by 22% — which is how the foot lift ended up at
## 11.8% of body height against the spike's 15.1%.
const STEP_TRIGGER_FACTOR: float = 0.20  # rear-plant lag before it steps / height
const STANCE_FACTOR: float = 0.052       # half stance width / height (spike 4.5/86)
const STEP_LIFT_FACTOR: float = 0.151    # swing-arc apex / height (spike 13/86)
## How far AHEAD of where the hip will be the swing foot plants, as a fraction of
## height. This is the forward reach of the stride — the leg is at its straightest
## here, and it is the single thing that makes a walk read as covering ground rather
## than shuffling. Bounded by what the leg can actually reach (see LEG_REACH_FACTOR
## in _compute_pose): too big and the shin visibly stretches.
const STEP_REACH_FACTOR: float = 0.18
## ⚠ THE LEASH ON THE TRAILING LEG, and the thing that decides how fast this figure is
## ALLOWED to stride. A planted foot is nailed to the world, so the longer it stays
## down the further behind the hip it ends up — and past thigh+shin it cannot be drawn
## at all without the shin visibly stretching (a straight rubber leg trailing the body,
## which is its own kind of wrong). So the swing time is capped: once the support foot
## has trailed this far, the swing MUST already be finishing.
##
## The consequence is deliberate and is real biomechanics rather than a fudge: this
## figure's legs are 0.40 of its height, and Hero.SPEED moves it 6.8 body-heights every
## second. Something with legs that short going that fast cannot take longer strides —
## it runs out of leg — so it takes FASTER ones. The stride therefore grows with speed
## up to what the leg can span and the cadence stays flat until that ceiling, then
## creeps. That is the correct shape; it is only the old law's UNBOUNDED cadence with a
## FROZEN stride that read as a buzz.
## ⚠ DERIVED, NOT AUTHORED — and it was authored at 0.34, which is further than the
## leg can physically span. THIS IS THE "why are their legs lagging in that weird
## way" BUG, and it is arithmetic rather than feel.
##
## A support foot is on the FLOOR, so the leg has to cover the hip's full standing
## height (`LEG_LEN_FACTOR`, 0.519 h) vertically before a single pixel of it is
## available for trailing behind. The stride dip buys some of that height back, but
## only up to `MAX_STRIDE_DIP_FACTOR` (0.05 h). So the real horizontal ceiling is
##
##     sqrt(reach^2 - (rest_height - max_dip)^2)
##   = sqrt(0.519^2 - 0.469^2)  =  0.222 h
##
## At 0.34 the leash let the support foot trail HALF AGAIN further than the leg
## could reach. The IK then does the only thing left to it: straightens the leg to
## full extension and points it at a plant it cannot touch — a rigid limb raked out
## behind the body, dragging. That is the exact silhouette in `rigleg_walk_*.png`.
##
## `STEP_TRIGGER_FACTOR` (0.20) was always inside this ceiling, which is why a slow
## walk looked better than a run: the trigger governs at low speed and only the
## LEASH governs once the swing rate saturates. Deriving it means the two can never
## disagree again — the same reason `LEG_LEN_FACTOR` and `HIP_Y_FACTOR` are derived.
const MAX_TRAIL_FACTOR: float = sqrt(
	LEG_LEN_FACTOR * LEG_LEN_FACTOR
	- (LEG_LEN_FACTOR - MAX_STRIDE_DIP_FACTOR) * (LEG_LEN_FACTOR - MAX_STRIDE_DIP_FACTOR)
)
## Below this world speed (px/s) the figure is idle: feet stop stepping and ease
## back under the hips so a standing fighter SETTLES instead of marching on the spot.
const GAIT_IDLE_SPEED: float = 14.0
## Swing rate in SWINGS PER SECOND — a time, so no height scaling (see above).
## SpikeFigure:2047 lerps exactly these two between a standstill and its top speed.
const SWING_RATE_SLOW: float = 5.0
const SWING_RATE_FAST: float = 9.5
## The speed at which the swing rate reaches SWING_RATE_FAST, in BODY-HEIGHTS per
## second, so it means the same thing to a minion and a boss. The spike's own top
## speed is 300 px/s on an 86 px figure.
const GAIT_FULL_SPEED_HEIGHTS: float = 300.0 / 86.0
## How fast idle feet ease back to the stance position (fraction per frame at 60 fps).
const IDLE_SETTLE: float = 0.25
## --- LEG LENGTH AND HIP HEIGHT, IN ONE PLACE ---
##
## ⚠ THIS IS WHY HE USED TO STAND IN A PERMANENT CROUCH, AND IT WAS MEASURABLE.
##
## `tools/rig_posture_measure.gd` reads the DRAWN idle stance off `_sim_pose` and
## solves the same 2-bone IK `draw_figure` does. Before this pass it reported:
##
##     rig    hip ride 0.411 h | leg drawn 0.480 h | extension 0.856 | knee 119.2 deg
##     spike  hip ride 0.508 h | leg drawn 0.522 h | extension 0.972 | knee 155.5 deg
##
## The drawn leg was 0.48 of the figure's height but the hip only rode 0.41 above the
## foot, so ~14% of the leg had to be folded away in the knee ON EVERY SINGLE FRAME.
## 119 degrees is not "a slight bend for life", it is a groucho squat, and it was the
## resting pose of every fighter in the game — hero, minion, elite, boss and hub NPC.
## The knee jutted 12.1% of the figure's height off the hip->foot line where the
## signed-off spike juts 5.4%.
##
## The fix is to make the three numbers agree by CONSTRUCTION instead of by hand:
##   * the leg is the spike's own 0.52 of height (22+22 px on its 84 px figure),
##   * the hip rides at exactly LEG_REACH_USABLE of that leg, so the knee carries the
##     spike's ~3% of slack and nothing more,
##   * and the hip's y then FALLS OUT of "feet at +height/2", rather than being a
##     second independent guess that the leg has to absorb.
##
## HEIGHT IS UNCHANGED. head_center is still -height/2 + r and the feet are still at
## +height/2, so the silhouette, the camera framing and Enemy's hit model all see the
## same extents; what moved is the hip INSIDE that silhouette (legs longer, torso
## correspondingly shorter — the spike's own build).
##
## ⚠ Enemy.RIG_HIP_Y_FACTOR / RIG_LEG_LEN_FACTOR MIRROR the two derived values below,
## and slice_test_rig_posture pins that they still agree.
const THIGH_FACTOR: float = 0.26
const SHIN_FACTOR: float = 0.26
const LEG_REACH_FACTOR: float = THIGH_FACTOR + SHIN_FACTOR
## Fraction of that reach the body STANDS at, and the single number behind "everyone's
## legs are bent and weird — I need them to be straight when standing".
##
## ⚠ A TINY SHORTFALL DRAWS A HUGE BEND, because a two-bone IK takes the SQUARE ROOT
## of it. The knee's sideways displacement is `thigh * sqrt(1 - u^2)`, so:
##       u = 0.97   ->  knee juts 8.3% of figure height   (MEASURED at rest)
##       u = 0.998  ->  knee juts ~1.6%
## At 0.97 that is a quarter of the leg's own length thrown sideways — the figure
## stands in a permanent half-squat. "3% short" sounds like nothing and is not.
##
## The old value was chosen so a planted leg is "never dead straight (which reads as a
## stilt)". That intent is kept — 0.998 is still short of the bone length, so the IK
## never hits its singularity and the knee still has a side to bend to — but the
## visible crouch is gone. A stickman standing still has straight legs; that is most
## of what makes it read as a stickman at all.
##
## Enemy.RIG_LEG_LEN_FACTOR / RIG_HIP_Y_FACTOR are DERIVED from this (not copied), so
## every enemy, boss and thrall in the game stands up with the same edit.
const LEG_REACH_USABLE: float = 0.998
## Hip-to-foot distance at rest — the height the body actually STANDS at. Derived,
## not authored, so it can never disagree with the leg it hangs off.
const LEG_LEN_FACTOR: float = LEG_REACH_FACTOR * LEG_REACH_USABLE
## ...and therefore where the hip sits in the figure's own frame, given that the feet
## rest at +height/2. Very slightly negative: a stick figure's hips are a hair above
## its mid-line, which is exactly where SpikeFigure's are (HIP_OFF +12 under a 58.5
## ride on an 84 px figure = -0.009 h).
const HIP_Y_FACTOR: float = 0.5 - LEG_LEN_FACTOR
## Ceiling on the stride dip, as a fraction of height. Without it a foot target left
## somewhere absurd (a blink mid-swing, a rig teleported by a test) could fold the
## figure into the floor. At the shipped stride the real dip peaks well under this.
## ⚠ WAS 0.14, AND IT WAS LOAD-BEARING FOR REACH RATHER THAN A WALK BOB. The dip
## drops head / neck / hip / shoulders so the legs can still touch their plants, and
## with the drawn leg free to stretch it never had to recover: MEASURED mean hip
## height 14.1-14.4 px against 15.64 standing, i.e. the figure walked permanently
## 8-10% shorter than it stands, for as long as it kept moving. Once the drawn leg is
## held to its own bones (see `draw_figure`) the dip stops carrying reach and can go
## back to being a subtle bob. FEEL — the maker judges this number at F5.
const MAX_STRIDE_DIP_FACTOR: float = 0.05
## Footstep audio. OFF by default and per-instance: this rig drives every enemy
## as well as the hero, and a room of eight enemies all ticking would be a
## cacophony — the owner opts in (see `step_sfx`). Levels are UNTESTED GUESSES;
## the maker asked for SMALL steps, and Sfx grades `step` at its quietest class.
const STEP_SFX_DB: float = -6.0
const STEP_SFX_PITCH_VAR: float = 0.16   # ±16% per step so a run doesn't machine-gun one tone
const STEP_SFX_DB_VAR: float = 2.2       # ± dB per step — footfalls are never identical weight
## THE LAST UNPORTED LINE OF THE SPIKE'S FOOTSTEP GUARD (`SpikeFigure.gd:53`).
##
## The pitch and dB variance above came across; the FLOOR BETWEEN STEPS did not, and
## its comment there says exactly why it exists: "a jittery gait can't stutter-fire".
## Without it the rig fired a step every time the gait said so, and once the gait was
## sub-stepped back to its tuned resolution that became ~19 steps/second at a 53 ms
## spacing — a machine-gun, and audibly wrong on the one sound the player hears most.
##
## It is a floor, not a rate limit: a slow walk is untouched, and only a cadence
## faster than a human foot can fall gets swallowed.
const STEP_SFX_MIN_GAP: float = 0.085
## Above this looseness the figure is ragdolling (hit flail, airborne trail, hold-
## DOWN flop) and has no feet under it to plant, so no step fires. Deliberately
## well under AIR_LOOSE_RISING (0.42) so leaving the ground silences steps at once.
const STEP_SFX_MAX_LOOSE: float = 0.25
## Foot-plant IK raycast layer. World/platform solids all sit on physics layer bit 1
## (value 1): VersusArena._make_terrace terraces (StaticBody2D default layer 1),
## RuinPlatform (default layer 1), BreakablePlatform (collision_layer 5 = bits 1+3),
## Rock/IceWall (layer 1) — matching Hero.BLINK_WALL_MASK. Fighter bodies live on
## layers 2/4, so a mask-1 downward ray never hits the figure's own body.
const GROUND_MASK: int = 1

## --- THE FLOATING-CAPSULE BODY (ported from SpikeFigure's RigidBody2D torso) ---
##
## THIS is the thing two previous ports left behind, and it is where the spike's
## whole sense of WEIGHT lives. Everything above (world-locked feet, slack airborne
## limbs, slimmer proportions) is the spike's SKIN. This is its SKELETON.
##
## In `SpikeFigure` the torso is a `RigidBody2D` that does not rest on the floor —
## it FLOATS on a spring probe above it (`_support`):
##
##     f = (ride_height - ground_distance) * RIDE_SPRING + velocity.y * RIDE_DAMP
##
## and its rotation is a second spring, a torque toward a lean target whose GAIN is
## the state machine's real voice: 1.0 planted, 0.09 airborne (so the body tips and
## tumbles with its own momentum rather than holding a pose), 2.6 through a dash.
## Two springs, and between them you get: knees that BUCKLE and rebound when you
## land, a body that pitches into a run and rights itself late, a hit that tips you
## over instead of nudging a stack of static sticks.
##
## PORTED AS HAND-INTEGRATED MATH, NOT AS A PHYSICS BODY — and that is not a
## compromise, it is the correct reading of what the RigidBody was doing. Strip the
## collision response (which `Hero`'s `CharacterBody2D` already owns) and the spike's
## torso is exactly two damped harmonic oscillators. A real `RigidBody2D` here would
## have to OWN the character's world position — which is precisely the hazard that
## made a wholesale swap impossible: `SpikeFigure`'s node never moves, the body hangs
## off a child, and every `to_global` / `get_weapon_tip` / `Enemy.body_distance()` /
## `SpellTargets` caller in the game reads a node that would stand still while the
## character walked away. So the springs are integrated by hand, in the rig's OWN
## transform, and the node keeps tracking the character exactly as before.
##
## ⚠ THE OUTPUT IS THE NODE'S OWN `position.y` AND `rotation`, ON PURPOSE.
## It would have been easier to bend the drawing (a `draw_set_transform`, or an
## offset baked into `_compute_pose`). That is the trap: `Enemy._silhouette()` builds
## the hit shape by pushing ANALYTIC head/hip points through `rig.global_transform`,
## so a drawing that moves without the transform moving is the "spells pass through
## heads" bug returning by the back door. Driving the transform means the silhouette,
## `get_weapon_tip()`, `get_lead_hand_global()`, the dash ghosts and the world-locked
## foot plants ALL follow for free, because every one of them already goes through
## `to_local` / `to_global` / `global_transform`.
##
## And the world-locked feet are what turn a body offset into a real SQUASH: the
## plants are held in WORLD space, so when the body drops 4 px the feet do not, the
## hip-to-foot distance shrinks, and `draw_figure`'s 2-bone IK bends the knees out.
## The compression is a CONSEQUENCE of the body sinking over planted feet — the same
## way it is in the spike — not a keyframe of a crouch.
##
## Spring rates are the spike's own, converted from force/torque to acceleration by
## dividing out its torso's mass and inertia, so the RESPONSE CURVE is identical:
##   ride:  RIDE_SPRING 4200 / mass 8      = 525   -> w = 22.9 rad/s, zeta = 0.71
##   pitch: upright_k 55000 / inertia ~1067 = 51.5 -> w = 7.2 rad/s,  zeta = 0.39
## Frequency is a TIME property and is deliberately NOT rescaled for this smaller
## figure — a landing thump reads at ~0.27 s whether the fighter is 86 px or 31 px.
## AMPLITUDES are scaled by height/SPIKE_HEIGHT_REF, because those are lengths.
const RIDE_SPRING_K: float = 525.0      # SpikeFigure RIDE_SPRING / torso mass
const RIDE_DAMP_K: float = 32.5         # SpikeFigure RIDE_DAMP / torso mass
## ⚠ THE RIDE SPRING IS ONE-SIDED, AND THAT IS WHERE THE BOUNCE COMES FROM.
##
## Easy to miss, and missing it is the difference between a landing that thumps and a
## landing that merely cushions. `SpikeFigure._support` does:
##
##     f = clampf(comp * RIDE_SPRING + velocity.y * RIDE_DAMP, 0.0, RIDE_FORCE_MAX)
##
## clamped at ZERO on the low end: the probe can PUSH THE BODY UP off its legs, it can
## never PULL IT DOWN. What pulls it down is gravity, always on (`grav_scale` 2.0).
##
## So a landing is not a symmetric damped oscillator at all. It is: compress, the
## spring fires the body back up, the spring then SWITCHES OFF as the body rises past
## its rest height, and the body is in genuine free fall until it lands on the spring
## again. Two or three diminishing hops — which is exactly what a Stick Fight landing
## looks like, and what a symmetric spring (zeta 0.71 -> 4% overshoot) cannot produce.
##
## The steady sag confirms the reading arithmetically: the spike annotates RIDE_HEIGHT
## as "hip(12) + legs(44)*0.97 + spring sag ~4", and sag = gravity / spring = 1960/525
## = 3.7 px. That is the same 4 px, derived independently. `_ride` here is measured
## from the SAGGED rest so a standing figure idles at exactly 0.
## (literal denominator, not SPIKE_HEIGHT_REF — that constant is declared below.)
const RIDE_SAG_FACTOR: float = 4.0 / 86.0   # rest compression / figure height
const PITCH_SPRING_K: float = 51.5      # SpikeFigure upright_k / torso inertia
const PITCH_DAMP_K: float = 5.6         # SpikeFigure upright_d / torso inertia
## The spike stands ~86 px (head 8 + torso 26 + legs 44). Every LENGTH ported from it
## is expressed as a fraction of this so a 31 px fighter, a 1.9x sparring dummy and
## the 60 px Guardian all squash in proportion instead of by a hardcoded pixel count.
const SPIKE_HEIGHT_REF: float = 86.0
## Fraction of the impact speed that becomes downward squash velocity on touchdown.
##
## 1.0, i.e. ALL OF IT, and that is the faithful number rather than a bold one. In
## SpikeFigure the falling `RigidBody2D` arrives at the contact point still travelling
## at its full descent speed and the ride spring catches every bit of it; nothing
## bleeds the impact off first. Anything less here is a landing with the weight turned
## down, which is precisely the note that came back twice.
##
## What it produces, checked against the source rather than eyeballed: a 700 px/s fall
## into a zeta-0.71 spring peaks at (v/w) * 0.49 = 15 px of compression on the spike's
## 86 px figure — 17% of its height, a deep visible crouch that recovers in ~0.15 s.
## `_body_scale()` reproduces the same 17% on a 31 px fighter (5.4 px). The clamp below
## is set with headroom so even a terminal-velocity drop is not flattened by it.
const LAND_ABSORB: float = 1.0
## Descent speed (px/s) at/above which a landing is a full-weight slam. Matches
## SpikeFigure.LAND_SFX_FULL_FALL so the visible squash and the land THUD peak together.
const LAND_FALL_FULL: float = 900.0
## Below this descent speed a touchdown is a step off a curb — no squash at all
## (SpikeFigure.LAND_SFX_MIN_FALL, same reasoning).
const LAND_FALL_MIN: float = 140.0
## Ceiling on the support the legs can produce, as an ACCELERATION — the port of
## SpikeFigure's `RIDE_FORCE_MAX` (120000) over its torso mass (8). The spike bounds
## the FORCE, not the travel, and that difference matters: a force cap lets an enormous
## impact compress further, where a travel cap would flatten every big landing to the
## same depth. There is deliberately no position clamp here for the same reason.
const RIDE_ACCEL_MAX: float = 15000.0
## Where the body SITS when fully limp and on the ground — the hold-DOWN ragdoll /
## death sprawl. Straight from the spike: RIDE_HEIGHT 58.5 -> RIDE_PRONE 11 is a drop
## of 47.5 px on its ~86 px figure.
##
## ⚠ FLAGGED, NOT TUNED. An earlier pass of this port pulled the number back to 0.30
## by eye, reasoning that CharacterRig's limbs ALSO droop under `_limp` (the spike's do
## not — its legs stay IK'd to their plants) so the two effects stack and 0.55 would be
## double-counting. That reasoning may well be right, but it is a JUDGEMENT about the
## maker's hand-tuned number, and the standing instruction is to port the number and
## raise the concern rather than quietly correct it. So: 0.552, and if the prone sprawl
## reads as sinking too far on F5, THIS is the constant, and 0.30 is the tested
## alternative.
const PRONE_RIDE_FACTOR: float = 47.5 / 86.0
## Lean TARGETS per regime, radians (SpikeFigure._support, verbatim).
const RUN_LEAN: float = 0.16
const AIR_LEAN: float = 0.68
const DASH_LEAN: float = 0.62
const WALL_LEAN: float = 0.12
const PRONE_LEAN: float = 1.42
## Lean-spring GAIN per regime. The 0.09 is the important one: airborne, the upright
## spring is almost switched OFF, so the body keeps whatever rotation the launch or
## the hit gave it and only slowly rights itself. That is what "loose" looks like.
const PITCH_GAIN_GROUND: float = 1.0
const PITCH_GAIN_AIR: float = 0.09
const PITCH_GAIN_DASH: float = 2.6
const PITCH_GAIN_WALL: float = 0.55
const PITCH_GAIN_LIMP: float = 0.22
## Lean CAPS per regime (SpikeFigure MAX_LEAN and its per-branch overrides). Eased
## toward, never snapped, so touching down does not jerk the body upright.
const LEAN_CAP_GROUND: float = 0.5
const LEAN_CAP_AIR: float = 1.15
const LEAN_CAP_DASH: float = 1.0
const LEAN_CAP_WALL: float = 0.4
const LEAN_CAP_PRONE: float = 1.85
const LEAN_CAP_EASE: float = 5.0
## Reference ground speed the lean normalises against — Hero.SPEED. A fighter at full
## run leans RUN_LEAN; the spike divides by its own move_speed for the same reason.
const LEAN_REF_SPEED: float = 210.0

## UPRIGHT RECOVERY — untested guesses, all three. `loose` below this counts as
## "the flop is over"; the body then returns to its stance lean at this rate
## (rad/s) and its residual spin is bled off so it settles instead of hunting.
## Turn RATE up if he still looks drunk after a hit; turn it DOWN if knockdowns
## snap back too eagerly and stop reading as a ragdoll.
const UPRIGHT_RECOVER_LOOSE: float = 0.35
const UPRIGHT_RECOVER_RATE: float = 5.0
const UPRIGHT_SETTLE_DAMP: float = 0.55
## Above this much residual spin (rad/s) the body is still mid-blow and recovery
## keeps its hands off. UNTESTED GUESS.
const UPRIGHT_RECOVER_MAX_SPIN: float = 1.2
## How much of an `apply_impulse` / `clash_recoil` reaches the BODY rather than only
## the drawn limbs. This is the other half of "hits go loose": SpikeFigure.hit() throws
## the whole capsule torso with `apply_central_impulse`, so the figure is shoved at
## chest height while its feet are still planted, and it TIPS. The old rig only rattled
## the hands, which is why a hit never read as the character being hit.
##
## ⚠ LATERAL ONLY, and that is the spike's own rule rather than a simplification of it.
## `hit()` routes every blow through `Juice.lateral_knockback` first, whose entire job
## is to flatten the vertical — the comment there is explicit that a blast at your feet
## used to launch you straight up. Feeding the vertical component into the ride spring
## would reintroduce exactly what that helper exists to prevent, so it is dropped here
## too and only the sideways shove reaches the body.
##
## The SCALE is re-derived rather than ported, and there is no honest alternative:
## `strength` in this rig is a limb-velocity number, the spike's is an impulse into an
## 8 kg RigidBody2D, and the two share no unit. Set so the knockback flop Hero already
## fires (~220) leans the body a few degrees and a full clash jolt (900) topples it —
## the same outcomes the spike produces at its own amplitudes.
const IMPULSE_TO_SPIN: float = 0.0055
## Integration sub-step for the body springs AND the gait, and its ceiling. 1/480 s is
## comfortably inside the stiff ride spring's stability and accuracy band; the cap
## bounds the cost of a single long frame (an alt-tab, a level load).
## See the ⚠ in _step_body for why this exists at all.
##
## ⚠ THE CAP WAS 8, WHICH IS EXACTLY THE 60 Hz REQUIREMENT — I.E. ZERO HEADROOM.
##
## The spike hosts force 120 Hz (`RigSpikeController`, `SpellPlaygroundController`), so
## a 1/120 frame asks for 4 sub-steps and sits at half the cap. The shipped game runs 60
## (`project.godot [physics]`), where 1/60 / (1/480) is 8 ON THE NOSE. At exactly 60 Hz
## that still resolves to a true 1/480 s sub-step, so the springs themselves were never
## degraded — MEASURED, see tools/rig_tickrate_trace.gd, `ride_y` converges to 0.02 px.
## But every path that hands `advance()` something longer than 1/60 silently integrated
## COARSER than the numbers were tuned at, with no margin at all: `Engine.time_scale`
## above 1, any owner accumulating deltas, and every capture harness that drives the rig
## by hand. 16 buys a full 1/30 s frame at the tuned resolution.
##
## And the headroom is FREE AT THE RATES WE ACTUALLY SHIP, which is the part worth
## knowing: `delta / BODY_SUBSTEP` is exactly 8.0 at 60 Hz and exactly 4.0 at 120 Hz, so
## `ceil` returns the same count under either ceiling and the sub-step loop runs an
## identical number of times. Raising the cap changes NOTHING in the nominal case — it
## only stops a long frame (1/30 s) being integrated at half resolution, where the old
## cap silently halved it. Measured cost of the springs overall, per
## tools/bench_rig_substep.gd at 25 rigs: 0.04-0.23 ms/frame depending on state and
## machine load, against a 16.67 ms budget.
const BODY_SUBSTEP: float = 1.0 / 480.0
const BODY_MAX_SUBSTEPS: int = 16

## Master switch for the floating-capsule body springs. ON everywhere by default —
## this is the rig, not an effect. It exists for two reasons: the A/B capture
## (tools/rig_ragdoll_capture.gd renders both columns through this SAME code path, so
## a before/after is a real comparison rather than a reconstruction), and as a kill
## switch if a particular figure ever needs to be nailed rigidly upright. Turning it
## off zeroes the springs and leaves the transform exactly where the owner put it.
@export var body_springs: bool = true

## Opt in to gait-driven footstep audio for THIS figure. Off by default because
## the same rig drives every enemy. The `foot_planted` signal fires either way.
@export var step_sfx: bool = false

@export var limb_color: Color = Color(0.55, 0.75, 1.0, 1.0)
## Moderate size bump (was 26) so the fighter reads as a bold puppet, not a speck.
## Boss.tscn / capture rigs override this per-instance, so only the default fighters grow.
@export var height: float = 31.0
## Soft radial glow under the figure ("charged" hero read). Strength 0
## disables it entirely — enemies stay bare sticks.
@export var aura_color: Color = Color(0.4, 0.7, 1.0, 1.0)
@export var aura_strength: float = 0.0
## Rank tier (0..5) driving aura elaborateness. Enemies stay at strength 0 so
## their tier never matters; the hero's tier is fed by Rank via set_aura_tier.
var aura_tier: int = 1

var state: State = State.IDLE
## slot ("head"/"body"/"feet"/"weapon") -> kind id ("" clears).
var equipment: Dictionary = {}

## Every gear kind the rig can draw. This USED to be EQUIP_TEX — a kind -> PixelLab
## PNG map whose textures were blitted ON TOP of the finished stick figure. That is
## gone (maker: "remove the clothing … replace the gear, like replace the torso or
## head etc., not be on top of them"): a pixel-art sprite pasted over a flat-vector
## stickman reads as a sticker on a character rather than as the character, and at
## 640x360 the detailed pieces collapsed into dark smears anyway — the same judgement
## SpikeFigure reached from renders and wrote up above its own procedural weapons.
##
## Gear is now drawn PROCEDURALLY in the rig's own line-art idiom, and — for the head
## and torso — INSTEAD OF the default part rather than over it (see _draw_head /
## _draw_torso). A helmet IS the head; armour IS the torso. Held weapons stay props,
## because a sword is not a body part. STICKS STAY STICKS: every piece is a bold flat
## fill in the figure's own colour with the same dark keyline and the same stroke
## weights, so the silhouette is a stickman WEARING gear.
##
## Kept as a flat registry (not a path map) because the loadout UI, the enemy
## archetype table and GearAbilities all need to agree on which kinds exist.
const GEAR_KINDS: Array[String] = [
	# head — each REPLACES the head circle, at head-circle scale
	"hat", "hood", "helmet", "crown",
	# body — each REPLACES the torso segment
	"robe", "armor",
	# held weapons
	"staff", "staff_ice", "staff_storm", "staff_holy", "orb",
	"sword", "greatsword", "dagger", "hammer", "scythe", "spear", "club", "bomb",
]
## MASTER CLOTHING SWITCH. False = helmets / hoods / hats / crowns / robes / armour /
## sandals are NOT DRAWN AT ALL, and every figure is a plain stick figure. Default
## false on the maker's twice-repeated instruction ("the characters are not stickmen,
## I just want to see STICKMEN" + the earlier "remove the clothing"), and because the
## whole point of the substitution scheme above — gear that REPLACES a body part — is
## that it changes the silhouette, which is exactly what stops it reading as a stick
## figure. HELD WEAPONS are deliberately NOT covered by this flag: a stickman with a
## sword is still a stickman.
##
## Static so the flag is a property of the drawing, not of any one instance — the
## rig, RigGhost's afterimages and the aura silhouette all go through draw_figure and
## must never disagree about what the character looks like. Flip it to true (from a
## capture tool, or permanently) to get the armoured look back; nothing else changes.
static var draw_clothing: bool = false
## Head kinds that BECOME the head (the default head circle is suppressed for them).
const HEAD_GEAR: Array[String] = ["hat", "hood", "helmet", "crown"]
## Body kinds that BECOME the torso (the default spine stroke is suppressed).
const TORSO_GEAR: Array[String] = ["robe", "armor"]
## Element tints for the staff variants' crystal — the ONE spot of non-body colour a
## piece is allowed, because it is the gameplay read (your staff sets your element).
const STAFF_GEM_TINT: Dictionary = {
	"staff_ice": Color(0.55, 0.9, 1.0),
	"staff_storm": Color(1.0, 0.92, 0.4),
	"staff_holy": Color(1.0, 0.97, 0.8),
}
## PixelLab magic-circle emblem for the ground aura (tier >= 3), tinted per element.
const AURA_CIRCLE_PATH: String = "res://assets/sprites/fx/magic_circle.png"

var _phase: float = 0.0
## --- world-locked gait state (see the STEP_* constants) ---
## WORLD-space plant positions, one per foot. Held still while the foot bears
## weight; that immobility IS the anti-slide.
var _plant_w: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
## Seeded false so the first grounded frame plants the feet under wherever the body
## actually is, instead of springing them in from a stale world position.
var _gait_ready: bool = false
var _swing_foot: int = 0
var _swing_t: float = 1.0                  # 1.0 = both feet planted
var _swing_from: Vector2 = Vector2.ZERO
var _swing_to: Vector2 = Vector2.ZERO
## Previous frame's world x, for deriving travel speed WITHOUT requiring the owner to
## call set_body_velocity — Boss and the capture rigs don't, and the gait must still work.
var _prev_gx: float = 0.0
var _prev_gx_valid: bool = false
var _gait_speed: float = 0.0
var _one_shot_active: bool = false
var _one_shot_time: float = 0.0
var _one_shot_duration: float = 0.0
var _hit_frame_emitted: bool = false
var _pop_timer: float = 0.0
var _flash_timer: float = 0.0
var _flash_color: Color = Color.WHITE
## World-space cursor direction for the CAST lead arm, from set_aim(). The arm
## points at the TRUE cursor even when the body faces the other way (twin-stick):
## _compute_pose mirrors it into the (possibly flipped) local frame.
var _aim_world: Vector2 = Vector2.RIGHT
## Directional parry SHIELD (Stick-Fight block): a white curved shell drawn in
## the aim direction while active. set_parry() arms it; it fades over its window.
## Faceless otherwise — Stick-Fight fighters convey aim by the body + the shield,
## never a face.
var _parry_dir: Vector2 = Vector2.RIGHT
var _parry_timer: float = 0.0
var _parry_duration: float = 0.0
## Airborne lift for the flight ability (0 = grounded, 1 = fully lifted).
var _airborne: float = 0.0
## Grounded flag (driven by Hero.is_on_floor). When limp + grounded, the ragdoll
## droop is clamped to the floor line so hold-DOWN ducking can't sink the drawn
## limbs THROUGH the collision (maker: "ducking clips the hero into the floor").
var _grounded: bool = true
## AIR-state phase (set by Hero via set_air_phase). There is NO scripted jump pose —
## these only BIAS the airborne looseness regime (_air_loose) in _step_sim: _air_rising
## = ascending (biased a touch tighter, a coiled leap), else falling (looser drop);
## _air_grounded = the brief landing frame (looseness settles back to 0). Harmless in
## any state — only consumed while state == State.AIR.
var _air_rising: bool = false
var _air_grounded: bool = false
## Airborne looseness 0 (grounded / settled) .. AIR_LOOSE_* (trailing-limb ragdoll in
## the air). Eased toward its state-driven target in _step_sim and combined with _limp
## via maxf, so the AIR state loosens the spring PARTWAY toward full limp without ever
## reaching the hit/flop full-ragdoll amplitude.
var _air_loose: float = 0.0
## Cached LOCAL-space y of the floor directly under the figure this frame (INF = no
## ground found / airborne). Refreshed once per frame by _update_ground_probe and
## consumed by the foot-plant in _sim_pose so the stance foot rests ON the ground.
var _ground_local_y: float = INF
## Active-ragdoll sim state: joint key -> simulated LOCAL position / velocity.
## Lazily seeded to the current target pose on first use so limbs never spring
## in from the origin. Pure Dictionary/Vector2 math — headless-safe.
var _sim: Dictionary = {}
var _sim_vel: Dictionary = {}
var _sim_ready: bool = false
## Flail-noise clock and this figure's own phase offset (see FLAIL_NOISE). Randomised
## per instance exactly as SpikeFigure seeds its own `_flail_seed`, so a room full of
## knocked-down fighters does not churn in unison.
var _flail_t: float = 0.0
var _flail_seed: float = randf() * TAU
## Limpness 0 (fully animated) .. 1 (ragdoll: weak springs + gravity droop).
var _limp: float = 0.0
var _limp_target: float = 0.0
## THIS BODY IS DEAD. Set only by `collapse()`, cleared by any `set_limp` below full.
## Its one job is to stop `flash_color` repainting a corpse — see the note there.
var _collapsed: bool = false
## Transient flop-on-hit: raises _limp_target for a beat then restores whatever it
## was before (so a hit-flop doesn't clobber a held hold-DOWN ragdoll).
var _flop_timer: float = 0.0
var _flop_prev_target: float = 0.0
## Cast-gesture overlay channel — independent of the State one-shot machine so a
## tell can play WHILE running/jumping/dashing. Offsets only the lead arm.
var _gesture_kind: int = GestureKind.NONE
var _gesture_time: float = 0.0
var _gesture_dur: float = 0.0
var _gesture_intensity: float = 0.0  # 0..1 spell power -> offset amplitude + VFX size
var _gesture_element: int = -1       # Elements.Element id for the hand VFX, -1 = none
var _gesture_active: bool = false
## Body velocity fed by set_body_velocity(); its frame-to-frame CHANGE nudges
## the extremities so limbs trail when the body launches/stops.
var _body_vel: Vector2 = Vector2.ZERO
var _prev_body_vel: Vector2 = Vector2.ZERO
## Hard-CC freeze: while true the locomotion cycle (_phase) HOLDS so a frozen /
## shocked enemy reads as genuinely rooted under the ice instead of jogging in
## place. The spring sim + timers still tick (a hit still flails, flashes clear),
## only the animation clock stops. Set by the owner from StatusComponent.is_hard_cc.
var _frozen: bool = false
## Twin-stick lead-arm aim (Hero only): when true the lead arm CONTINUOUSLY points
## at the cursor (_aim_world) while IDLE/RUN, not just during a CAST — so the
## visible hand always aims where the mouse is (Stick-Fight). Enemies leave this
## false so their arms keep the locomotion swing.
var aim_arm: bool = false
## Persistent flaming-fist charge 0..1 (set by Hero after a fire punch): bulks the
## lead fist and drives the on-hand fire draw + embers (item 3). 0 = no fire.
var _hand_fire: float = 0.0
var _hand_fire_element: int = -1

## --- floating-capsule body state (see the FLOATING-CAPSULE BODY block) ---
## Vertical displacement of the body from its rest height, in LOCAL px, POSITIVE =
## sunk/compressed. Written out to the node's own `position.y` each frame.
## Wall-clock of the last footstep sound, for STEP_SFX_MIN_GAP. Wall-clock rather
## than an accumulated rig clock so the floor stays a real 85 ms even under a
## hitstop's 0.05 time_scale — a freeze must not bank up a burst of steps.
var _last_step_sfx: float = -999.0
var _ride: float = 0.0
var _ride_vel: float = 0.0
## Body lean in radians, world space. Written out to the node's own `rotation`.
var _pitch: float = 0.0
var _pitch_vel: float = 0.0
## Eased lean clamp — ported from SpikeFigure._lean_cap. Eased rather than switched
## so leaving a loose regime (landing, ending a dash) does not snap the body upright.
var _lean_cap: float = LEAN_CAP_GROUND
## What this rig last WROTE into the node transform, so the owner's own base offset
## is recoverable. Player.gd and NPC.gd set `_rig.position.y = -height * 0.5` once in
## _ready to stand their hub figures on the node origin; subtracting what we applied
## recovers that base instead of fighting it. (Both write before the first advance(),
## when the applied offset is still 0, so the base is read correctly.)
var _applied_ride: float = 0.0
## Previous frame's UN-SQUASHED world y + validity, for deriving fall speed without
## requiring the owner to feed velocity — Enemy, Boss and every capture harness drive
## the rig without ever calling set_grounded/set_body_velocity, and a landing must
## still land. Mirrors the _prev_gx idiom the gait already uses.
var _prev_gy: float = 0.0
var _prev_gy_valid: bool = false
var _fall_speed: float = 0.0
## Fastest descent seen during the current airtime — the landing squash scales on it,
## exactly as SpikeFigure._peak_fall scales its land thud.
var _peak_fall: float = 0.0
## Airborne last frame, for edge-detecting takeoff and touchdown.
var _was_airborne: bool = false
## World y of the floor under the figure this frame (INF = none found). The WORLD
## twin of _ground_local_y: once the body can PITCH, a single local y is no longer a
## horizontal floor line, so anything clamping a limb to the ground has to go through
## _local_floor_y(x) instead. Kept alongside rather than replacing it because the
## local value is still the honest answer for a point directly under the origin.
var _ground_world_y: float = INF


## ⚠ THE RIG TICKS ON PHYSICS, NOT ON RENDER — and this line moved for a measured
## reason, not a stylistic one.
##
## It used to be `_process`. That was harmless while the rig was a pure poser, and
## became a real bug the moment the body springs landed, because the springs measure
## the CHARACTER'S OWN MOTION and the character moves in `_physics_process`:
##
##   * UNDERSAMPLED IMPACT. Fall speed is derived from the node's world travel. Sampled
##     off-cadence from the body that produces it, a hero touching down at 900 px/s was
##     measured at 604 — the landing arrived a third lighter than the fall that caused
##     it. MEASURED in a probe against a real Hero in VersusArena, not reasoned about.
##   * A LOST PEAK. The squash is a ~10-physics-frame event. Whenever a render frame
##     spanned several physics ticks, the whole compression happened between two
##     samples and the deepest part of it was never drawn at all. In-game the landing
##     came out at 1.75 px where the isolated rig produced 5.4.
##
## SpikeFigure drives its torso from `_physics_process` for exactly this reason. On a
## fixed 60 Hz tick the springs are also deterministic, so the feel no longer depends on
## the player's monitor — which matters more than smoothness here, because everything
## the rig is drawn RELATIVE to (the hero's position, the world-locked plants) is
## already on the physics clock.
func _physics_process(delta: float) -> void:
	advance(delta)


## Per-frame update, split out from _process so headless tests can drive
## the rig deterministically without a real frame loop.
func advance(delta: float) -> void:
	# Frozen: hold the locomotion phase so the run/idle cycle stops dead. Timers +
	# sim below still advance so the ice-shatter flash and a knock still read.
	if not _frozen:
		_phase += delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
	if _flop_timer > 0.0:
		_flop_timer -= delta
		if _flop_timer <= 0.0:
			_limp_target = _flop_prev_target  # recover to the pre-flop resting limp
	if _gesture_active:
		# Real delta, NOT gated by _frozen — a cast tell should still finish under CC.
		_gesture_time += delta
		if _gesture_time >= _gesture_dur:
			_gesture_active = false
			_gesture_kind = GestureKind.NONE
	if _pop_timer > 0.0:
		_pop_timer -= delta
	if _parry_timer > 0.0:
		_parry_timer -= delta
	if _one_shot_active:
		_one_shot_time += delta
		var is_strike: bool = state == State.PUNCH or state == State.KICK
		if is_strike and not _hit_frame_emitted \
				and _one_shot_time >= _one_shot_duration * HIT_FRAME_FRACTION:
			_hit_frame_emitted = true
			_pop_timer = POP_TIME
			hit_frame.emit()
		if _one_shot_time >= _one_shot_duration:
			_one_shot_active = false
			state = State.IDLE
	# Ground probe FIRST: both the gait (where to plant) and the sim's foot clamp read
	# the floor line, so it has to be this frame's, not last frame's.
	_update_ground_probe()
	# Then the BODY, then the LIMBS — in that order and not the other way round.
	# The body springs move the node's own transform, and the world-locked foot plants
	# are pulled back through `to_local`, so the limbs must be solved AFTER the body has
	# settled this frame or the knees would buckle one frame late (which reads as a
	# floaty landing rather than a heavy one).
	_track_body_motion(delta)
	_update_gait(delta)
	_step_body(delta)
	_apply_body_transform()
	_step_sim(delta)
	queue_redraw()


## Derive this frame's true vertical motion and edge-detect takeoff / touchdown.
##
## Reads the NODE's own world travel rather than a fed velocity, on purpose: `Enemy`
## and `Boss` never call `set_grounded`, most enemy states never call
## `set_body_velocity`, and every capture harness drives the rig by moving it. The
## gait already derives horizontal speed this way for exactly the same reason.
##
## The rig's OWN squash is subtracted out before measuring, or the ride spring would
## read its own oscillation back as body motion and drive itself.
func _track_body_motion(delta: float) -> void:
	if delta <= 0.0:
		return
	var gy: float = global_position.y - _applied_ride
	if _prev_gy_valid:
		var raw: float = (gy - _prev_gy) / delta
		# Same teleport guard the gait uses: a blink must not read as a 20,000 px/s fall.
		_fall_speed = raw if absf(raw) < 4000.0 else 0.0
	_prev_gy = gy
	_prev_gy_valid = true

	# "Airborne" is whatever the owner tells us, if it tells us anything. Hero drives
	# both; Enemy leaves _grounded true and never plays AIR, so its fighters simply
	# never take off and the landing path never fires for them — correct, and free.
	var airborne: bool = state == State.AIR or not _grounded
	if airborne:
		# Take the OWNER'S fed velocity when there is one, and the derived travel
		# otherwise. Both are needed: `move_and_slide` clips the node's motion on the
		# contact frame, so travel alone under-reports the very impact being measured;
		# and Enemy/Boss/capture rigs never feed velocity at all, so the fed value alone
		# would leave them landing weightless. `maxf` of the two is right because
		# `_body_vel` rests at ZERO for the owners that do not feed it.
		_peak_fall = maxf(_peak_fall, maxf(_fall_speed, _body_vel.y))   # +y is down
	if airborne and not _was_airborne:
		# TAKEOFF. Nothing is injected, deliberately: SpikeFigure sets JUMP_CROUCH to
		# 0.0 ("Stick Fight jumps fire immediately") and gates its ride spring OFF for
		# the whole `_jump_lock` window, so leaving the ground neither crouches nor
		# stretches the body there. An earlier pass of this port added an upward yank
		# because it looked good; it is not in the source, so it is gone. All that
		# happens on takeoff is that the airtime measurement starts.
		_peak_fall = 0.0
	elif not airborne and _was_airborne:
		# TOUCHDOWN — inject the impact as downward ride velocity and let the spring
		# do the rest: compress, rebound, settle. The knees buckle because the feet are
		# world-locked and the hips have just dropped toward them.
		var impact: float = clampf(_peak_fall, 0.0, LAND_FALL_FULL)
		if impact > LAND_FALL_MIN:
			_ride_vel += impact * LAND_ABSORB * _body_scale()
		_peak_fall = 0.0
	_was_airborne = airborne


## How many sub-steps this frame is worth, at the tuned 1/480 s resolution.
##
## ONE budget shared by the body springs and the gait, deliberately: they are two halves
## of the same figure and a stride that advances on a different clock from the squash is
## how the feet stop agreeing with the hips. See the ⚠ on BODY_MAX_SUBSTEPS.
func _substeps(delta: float) -> int:
	return clampi(int(ceil(delta / BODY_SUBSTEP)), 1, BODY_MAX_SUBSTEPS)


## Length scale for everything ported from the spike: it hand-tuned its amplitudes
## against an ~86 px figure, and this rig draws fighters from 31 px to the Guardian's
## 60. Frequencies are NOT scaled (see the constants block) — only lengths.
func _body_scale() -> float:
	return height / SPIKE_HEIGHT_REF


## Integrate the two body springs — the port of SpikeFigure._support().
##
## RIDE: a damped harmonic oscillator toward a rest height. Nothing drives it in
## steady state; it only ever has energy because a landing, a takeoff or a hit put
## some in. That is why it reads as weight rather than as a bob.
##
## PITCH: a torque spring toward a per-regime lean target, whose GAIN is the whole
## point — near-zero in the air so the body tips with its momentum, hard through a
## dash so the burst is a committed shape, slack when limp so a hit topples you.
func _step_body(delta: float) -> void:
	if not body_springs:
		# Kill switch / the capture's BEFORE column. Zeroed rather than merely skipped,
		# so _apply_body_transform hands the node straight back to its owner.
		_reset_body_springs()
		return
	if delta <= 0.0:
		return
	var loose: float = maxf(_limp, _air_loose)
	var airborne: bool = state == State.AIR or not _grounded
	var facing: float = 1.0 if scale.x >= 0.0 else -1.0

	# ---- ride target ----
	# Rest is 0. The one thing that MOVES it is going limp on the ground: the
	# hold-DOWN ragdoll / death sprawl drops the body toward the floor, which is
	# SpikeFigure's RIDE_HEIGHT -> RIDE_PRONE collapse.
	var ride_target: float = 0.0
	if _grounded and not airborne:
		ride_target = PRONE_RIDE_FACTOR * height * clampf(_limp, 0.0, 1.0)
	# Frozen (hard CC): rooted under the ice — hold the body still rather than letting
	# it keep swaying, but keep the spring live so the shatter still knocks it.
	if _frozen:
		ride_target = 0.0
	# ⚠ SUB-STEPPED, AND IT IS NOT AN OPTIMISATION DETAIL — IT IS THE LANDING.
	#
	# The ride spring is STIFF: w = 22.9 rad/s and a damping coefficient of 32.5, so at
	# a 60 Hz frame the damping term alone is 32.5/60 = 0.54 of the velocity per step.
	# Explicit Euler at that rate does not merely lose accuracy, it eats the effect: a
	# 700 px/s landing that should compress ~17% of the figure's height came out at 8%,
	# because the first frame threw away more than half the impact velocity before it
	# had moved the body anywhere. MEASURED — that discrepancy is what sent this back
	# for a second pass, and it would have shipped as "the landing still feels light".
	#
	# It also makes the feel FRAME-RATE INDEPENDENT, which matters beyond correctness:
	# without it the same jump lands heavier at 30 fps than at 144 fps, and the maker
	# would be tuning against their own monitor.
	var steps: int = _substeps(delta)
	var sdt: float = delta / float(steps)
	# ONE-SIDED spring + constant weight — see the ⚠ on RIDE_SAG_FACTOR. `sag` is the
	# rest compression that exactly balances the weight, so a standing figure idles at
	# _ride == 0 while the maths underneath stays the spike's. The `maxf(..., 0.0)` is
	# the asymmetry: the moment the body rises past where the legs can push, the support
	# vanishes and it falls back onto the spring under its own weight.
	var sag: float = RIDE_SAG_FACTOR * height
	var weight: float = RIDE_SPRING_K * sag
	# The clamp is on the SUPPORT, exactly as SpikeFigure clamps its ride force to
	# RIDE_FORCE_MAX — bounding what the legs can push with, never bounding how far the
	# body is allowed to travel. A travel clamp would flatten every heavy landing to the
	# same depth, which is the one thing a weight system must not do.
	for _s: int in steps:
		var support: float = clampf(
			RIDE_SPRING_K * (_ride - ride_target + sag) + RIDE_DAMP_K * _ride_vel,
			0.0, RIDE_ACCEL_MAX
		)
		_ride_vel += (weight - support) * sdt
		_ride += _ride_vel * sdt

	# ---- lean target + gain + cap, by regime (SpikeFigure._support's branch chain) ----
	var vx_n: float = clampf(_gait_speed / LEAN_REF_SPEED, -1.0, 1.0)
	var lean: float = 0.0
	var gain: float = PITCH_GAIN_GROUND
	var cap: float = LEAN_CAP_GROUND
	if _frozen:
		gain = PITCH_GAIN_GROUND
		cap = 0.12                      # rooted: barely allowed to lean at all
	elif state == State.DASH:
		# The ONE committed body shape in the whole chain. Everything else here is
		# reactive; a dash has to read as DRIVEN or the afterimages are five copies of
		# a standing man. Still a spring TARGET, so hits and terrain keep fighting it.
		#
		# Leans off the dash DIRECTION, not the facing, because SpikeFigure does
		# (`_dash_dir.x * DASH_LEAN`): a dash straight up must not pitch the body over.
		# Falls back to facing for any owner that does not feed velocity.
		var ddir: Vector2 = _body_vel.normalized()
		lean = (ddir.x if ddir != Vector2.ZERO else facing) * DASH_LEAN
		gain = PITCH_GAIN_DASH
		cap = LEAN_CAP_DASH
	elif state == State.WALL_SLIDE:
		# Clinging: firm uprighting, tight cap, a slight lean into the wall. The spike
		# learned the hard way that letting the body tip here pulls the hip out of
		# wall-probe range and drops the grip.
		lean = -facing * WALL_LEAN
		gain = PITCH_GAIN_WALL
		cap = LEAN_CAP_WALL
	elif airborne:
		# THE LOOSE ONE. Barely uprighted, wide cap: the body tips with its momentum
		# and rights itself only slowly, like a ragdoll that happens to land feet first.
		lean = vx_n * AIR_LEAN
		gain = PITCH_GAIN_AIR
		cap = LEAN_CAP_AIR
	elif loose > 0.35:
		# Limp on the ground — the duck-flop / knocked-down sprawl. The lean target
		# itself rotates the body down flat, and the cap opens to let it get there.
		lean = facing * PRONE_LEAN * loose
		gain = PITCH_GAIN_LIMP
		cap = LEAN_CAP_GROUND + (LEAN_CAP_PRONE - LEAN_CAP_GROUND) * loose
	else:
		# Planted. Lean with the run, and lean HARDER when you are being held back:
		# input that is not turning into motion (walking into a wall, shoving through
		# a body) shows as a strain. `_body_vel` is the INTENDED velocity the owner
		# fed us; `_gait_speed` is what the world actually granted. The difference is
		# the resistance. Zero for any owner that never feeds velocity.
		lean = vx_n * RUN_LEAN
		if _body_vel != Vector2.ZERO:
			var resist: float = clampf((_body_vel.x - _gait_speed) / LEAN_REF_SPEED, -1.0, 1.0)
			lean += resist * RUN_LEAN * 1.6
	# (An earlier pass added a "fold forward on landing" term here, tipping the body into
	# its own arrival. It read well and it is not in SpikeFigure — its landing lean is
	# just the ordinary velocity lean, with `_lean_cap` easing so touching down does not
	# snap. Removed rather than kept: differences from the source are regressions.)

	# Same sub-stepping, same reason (the dash gain of 2.6 pushes the pitch spring into
	# the same stiffness band the ride spring lives in permanently).
	for _s: int in steps:
		var err: float = wrapf(lean - _pitch, -PI, PI)
		_pitch_vel += (PITCH_SPRING_K * err - PITCH_DAMP_K * _pitch_vel) * gain * sdt
		_pitch += _pitch_vel * sdt
	# UPRIGHT RECOVERY. Once the body is planted and the looseness has drained, the
	# pose belongs to the stance again — but the pitch spring alone takes a long time
	# to get there, because the branch that tipped him over runs at PITCH_GAIN_LIMP
	# (0.22, deliberately weak so a knockdown *sprawls* instead of snapping back).
	# The result the maker reported is a figure that never quite stands up straight
	# after its first hit. Recovery is therefore its own term rather than a bigger
	# limp gain: raising that gain would stiffen the sprawl itself, which is the one
	# thing the ragdoll is for.
	# Gated on residual SPIN as well as looseness. Without the spin test this term
	# cancelled a blow outright — a hit imparts pitch velocity before `_limp` has
	# eased up, so recovery would haul the body upright on the very frame it was
	# supposed to be knocked over. The tilt is allowed to happen and to ring out;
	# recovery only owns the tail.
	if state != State.AIR and loose <= UPRIGHT_RECOVER_LOOSE 			and absf(_pitch_vel) < UPRIGHT_RECOVER_MAX_SPIN:
		_pitch = move_toward(_pitch, lean, UPRIGHT_RECOVER_RATE * delta)
		if absf(_pitch - lean) < 0.004:
			_pitch_vel *= UPRIGHT_SETTLE_DAMP
	_lean_cap = move_toward(_lean_cap, cap, LEAN_CAP_EASE * delta)
	if absf(_pitch) > _lean_cap:
		_pitch = clampf(_pitch, -_lean_cap, _lean_cap)
		_pitch_vel = 0.0
	if not (is_finite(_ride) and is_finite(_pitch)):
		_reset_body_springs()
	# (An earlier pass also fed the ride velocity into the limb sim as an inertial drag.
	# Removed: SpikeFigure has no such coupling, and it does not need one — its limbs are
	# IK'd off the torso body, so they follow it for free. The same is true here once the
	# springs drive the NODE transform: the limb sim works in local space, so the whole
	# skeleton travels with the body automatically and an extra nudge is double-counting.)


## Push this frame's body springs out into the node's own transform. See the ⚠ in the
## FLOATING-CAPSULE BODY block for why it has to be the transform and not the drawing.
##
## `position.y` is written as base + ride, where the base is recovered by subtracting
## what we applied last frame — so an owner that sets its own rig offset (the hub's
## Player.gd / NPC.gd) keeps it. `rotation` is owned outright: nothing else in the
## codebase writes it (set_facing owns scale.x, and only scale.x).
func _apply_body_transform() -> void:
	var base_y: float = position.y - _applied_ride
	position.y = base_y + _ride
	_applied_ride = _ride
	rotation = _pitch


## Drop all body-spring energy and return to a clean upright rest. Used as the NaN
## backstop and by owners that teleport a figure (so it does not arrive mid-topple).
func _reset_body_springs() -> void:
	_ride = 0.0
	_ride_vel = 0.0
	_pitch = 0.0
	_pitch_vel = 0.0
	_lean_cap = LEAN_CAP_GROUND
	_peak_fall = 0.0


## LOCAL y of the world floor directly beneath the LOCAL x given.
##
## Exists because the body can now PITCH: once the node is rotated, "the floor" is no
## longer a constant local y, and clamping a foot to one would let a leaning figure
## push a foot through the ground on one side and hover it on the other. Round-trips
## through the real transform, so it is exact under rotation, ride offset AND the
## facing flip. INF when no ground was found (airborne / headless / off-tree), which
## every caller already treats as "do not clamp".
func _local_floor_y(local_x: float) -> float:
	if not is_finite(_ground_world_y):
		return INF
	return to_local(Vector2(to_global(Vector2(local_x, 0.0)).x, _ground_world_y)).y


## Current body-spring squash in local px (positive = compressed). Public so the
## owner can keep anything it parents SEPARATELY from the rig — notably Enemy's
## hurtbox Area2D — locked to the drawn body. See Enemy._sync_body_offset.
func body_ride() -> float:
	return _ride


## Current body lean in radians (world space). Public for the same reason.
func body_pitch() -> float:
	return _pitch


## Advance the WORLD-LOCKED gait: hold each planted foot still in world space while
## the body travels over it, and swing the rearmost foot forward when the hip has
## outrun it. This is the port of SpikeFigure._update_legs' grounded branch, and it
## is the single biggest reason the spike rig reads as PLANTED where the phase-driven
## one reads as skating.
##
## Runs in WORLD space on purpose. The plants have to be independent of the node
## (which is translating, and flips scale.x on a turn); _compute_pose converts them
## back through to_local, which mirrors them into the facing frame for free.
##
## `foot_planted` now fires on the REAL plant event — the frame a foot actually
## touches down — rather than on a sine crossing that merely correlated with it. The
## signal contract is unchanged, but the tick can no longer drift from the visible
## footfall, and it naturally scales with travel speed instead of a fixed cadence.
func _update_gait(delta: float) -> void:
	if delta <= 0.0:
		return
	# Travel speed from the node's OWN world motion, not set_body_velocity: Boss, the
	# hub NPC rigs and the capture harnesses never feed velocity, and they must still
	# stride correctly. One frame of history, guarded so a teleport/blink can't be read
	# as a 20,000 px/s sprint.
	var gx: float = global_position.x
	var gx_start: float = _prev_gx if _prev_gx_valid else gx
	if _prev_gx_valid:
		var raw: float = (gx - _prev_gx) / delta
		if absf(raw) < 4000.0:
			_gait_speed = raw
		else:
			_gait_speed = 0.0
			_gait_ready = false   # blink/teleport: re-seed the plants at the new spot
			gx_start = gx         # nothing to interpolate across a teleport
	_prev_gx = gx
	_prev_gx_valid = true

	var stance: float = height * STANCE_FACTOR
	# Airborne, ragdolling or frozen: no gait. Drop readiness so the next grounded
	# frame re-seeds the plants under the body (a landing must never drag the feet
	# back to where the jump started).
	if not _grounded or state == State.AIR or _frozen \
			or maxf(_limp, _air_loose) > STEP_SFX_MAX_LOOSE:
		_gait_ready = false
		_swing_t = 1.0
		return

	# Floor line in world y. No probe hit (off-tree/headless) -> the figure's own
	# standing foot line, so a detached test rig still produces a sane stride.
	#
	# ⚠ The fallback measures from the UN-SQUASHED body (global y minus the ride
	# spring's current compression). If the plants sank with the squash there would be
	# no squash: the feet would follow the hips down and the knees would never bend.
	# The whole landing read depends on the ground staying where the ground is.
	var floor_w: float = _ground_world_y if is_finite(_ground_world_y) \
			else (global_position.y - _ride) + height * 0.5
	if not _gait_ready:
		_plant_w[0] = Vector2(gx + stance, floor_w)
		_plant_w[1] = Vector2(gx - stance, floor_w)
		_swing_t = 1.0
		_gait_ready = true
		return

	var moving: bool = absf(_gait_speed) > GAIT_IDLE_SPEED
	if moving:
		# SUB-STEPPED. The gait has the shortest natural period of anything in the rig,
		# so it is the part that can least afford one iteration per physics frame: at
		# 60 Hz the trigger phase aliases against the frame grid, steps land at irregular
		# intervals, and irregular timing on world-locked feet is precisely a limp.
		# The body travels at essentially constant velocity within a frame, so `gx` is
		# interpolated across it and the trigger fires at the world x it would have fired
		# at on a finer clock. A step may both COMPLETE and RE-TRIGGER inside one frame;
		# that is what happens across two frames at 120 Hz, and `foot_planted` fires once
		# per real plant either way, so the signal and the footstep audio stay honest.
		var walk_dir: float = signf(_gait_speed)
		# ABSOLUTE swing rate — a TIME, lerped by how fast this figure is going relative
		# to its own size. See the ⚠ on SWING_RATE_SLOW for why deriving this from the
		# step length instead is the bug the maker keeps seeing.
		var rate: float = lerpf(SWING_RATE_SLOW, SWING_RATE_FAST, clampf(
			absf(_gait_speed) / maxf(height * GAIT_FULL_SPEED_HEIGHTS, 0.001), 0.0, 1.0))
		# ...but never slower than the leash allows (see MAX_TRAIL_FACTOR): the support
		# foot must not still be down once it has trailed further than the leg can span.
		var swing_time: float = minf(
			1.0 / maxf(rate, 0.001),
			height * (STEP_REACH_FACTOR + MAX_TRAIL_FACTOR)
					/ maxf(absf(_gait_speed), 0.001))
		rate = 1.0 / maxf(swing_time, 0.0001)
		# Plant where the hip WILL BE when this swing ends, plus the forward reach of
		# the stride. THE STRIDE THEREFORE GROWS WITH SPEED and the cadence does not —
		# which is the whole difference between a run and a buzz.
		var step_len: float = absf(_gait_speed) * swing_time + height * STEP_REACH_FACTOR
		var steps: int = _substeps(delta)
		var sdt: float = delta / float(steps)
		for s: int in steps:
			var gx_s: float = lerpf(gx_start, gx, float(s + 1) / float(steps))
			if _swing_t >= 1.0:
				# Step whichever foot is furthest BEHIND along the direction of travel.
				var behind: int = 0 if (_plant_w[0].x - _plant_w[1].x) * walk_dir <= 0.0 else 1
				if (gx_s - _plant_w[behind].x) * walk_dir > height * STEP_TRIGGER_FACTOR:
					_swing_foot = behind
					_swing_from = _plant_w[behind]
					_swing_to = Vector2(gx_s + walk_dir * step_len, floor_w)
					_swing_t = 0.0
			else:
				_swing_t += sdt * rate
				if _swing_t >= 1.0:
					_swing_t = 1.0
					_plant_w[_swing_foot] = _swing_to
					foot_planted.emit()
					if step_sfx:
						_play_step_sfx()
	else:
		# Idle: stop stepping and let the feet ease back under the hips, so a standing
		# fighter settles into a clean stance instead of marching on the spot.
		_swing_t = 1.0
		var ease: float = clampf(IDLE_SETTLE * delta * 60.0, 0.0, 1.0)
		_plant_w[0] = _plant_w[0].lerp(Vector2(gx + stance, floor_w), ease)
		_plant_w[1] = _plant_w[1].lerp(Vector2(gx - stance, floor_w), ease)


## This frame's WORLD foot position for index `i`: the held plant, or the lifted arc
## if this is the swinging foot. Pure read of the gait state — safe to call from
## _compute_pose (which must stay side-effect free; the ghost + aura call it too).
func _gait_foot_world(i: int) -> Vector2:
	if i == _swing_foot and _swing_t < 1.0:
		return Vector2(
			lerpf(_swing_from.x, _swing_to.x, _swing_t),
			lerpf(_swing_from.y, _swing_to.y, _swing_t)
					- sin(_swing_t * PI) * height * STEP_LIFT_FACTOR
		)
	return _plant_w[i]


## Extra per-step level jitter on top of Sfx's own: a footstep repeats far more
## often than any other sound in the game, so it is the one most likely to be
## heard as "the same sample again".
##
## Sfx is resolved through the tree, and RELATIVE to root rather than as the
## absolute "/root/Sfx": a `--script` test context has no active scene, and an
## absolute get_node from there errors on every single call. Relative-from-root
## resolves the autoload at runtime and quietly returns null in tests.
func _play_step_sfx() -> void:
	# is_inside_tree() FIRST: get_tree() itself errors on a detached node, which a
	# --script test harness produces.
	if not is_inside_tree():
		return
	# The spike's stutter-fire floor — see STEP_SFX_MIN_GAP. Checked before the tree
	# lookup is used but after the detached guard, so a harness still exits cheaply.
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - _last_step_sfx < STEP_SFX_MIN_GAP:
		return
	_last_step_sfx = now
	var sfx: Node = get_tree().root.get_node_or_null(^"Sfx")
	if sfx != null and sfx.has_method(&"play"):
		sfx.call(
			&"play",
			"step",
			STEP_SFX_DB + randf_range(-STEP_SFX_DB_VAR, STEP_SFX_DB_VAR),
			STEP_SFX_PITCH_VAR
		)


## Step the active-ragdoll spring sim toward the current animation target pose.
## Stable by construction: springs weaken as _limp rises, damping is clamped,
## and every joint is hard-clamped to height * MAX_OFFSET_FACTOR from its
## target so the sim can never explode. _compute_pose() is called ONCE here
## and reused for every joint.
func _step_sim(delta: float) -> void:
	var target_pose: Dictionary = _compute_pose()
	_ensure_sim(target_pose)
	if delta <= 0.0:
		return
	_limp = move_toward(_limp, _limp_target, LIMP_EASE_SPEED * delta)
	# Airborne looseness (NO canned pose): while in AIR, ease PARTWAY toward full limp so
	# the limbs trail/flail with momentum + gravity; rising is biased tighter than falling;
	# _air_grounded (the landing frame) drops the target to 0 so the stance settles fast.
	# `loose` = maxf(_limp, _air_loose): a hit mid-air still overrides to FULL limp.
	var air_target: float = 0.0
	if state == State.AIR and not _air_grounded:
		air_target = AIR_LOOSE_RISING if _air_rising else AIR_LOOSE_FALLING
	_air_loose = move_toward(_air_loose, air_target, AIR_LOOSE_EASE_SPEED * delta)
	var loose: float = maxf(_limp, _air_loose)
	# Lerp toward an ABSOLUTE full-limp floor (not a fraction of STIFFNESS) so the
	# resting-pose tame (STIFFNESS 60->180) can't also tighten the post-hit flail.
	var stiffness: float = lerpf(STIFFNESS, FULL_LIMP_STIFFNESS, loose)
	# The damping goes slack WITH the spring — see the ⚠ on LIMP_DAMPING. Holding it
	# flat while the stiffness collapsed drove the full ragdoll to zeta 2.3, i.e. it
	# could not overshoot at all, and a limb that cannot overshoot cannot flail.
	var damp: float = clampf(1.0 - lerpf(DAMPING, LIMP_DAMPING, loose) * delta, 0.0, 1.0)
	# Airborne/limp limb churn — the spike's FLAIL_NOISE, which this rig had no term
	# for. Advanced on the REAL delta (not `_phase`, which `_frozen` holds) so a body
	# knocked loose still judders while a hard-CC'd one stands rooted.
	_flail_t += delta
	# Limp-scale the clamp too: tight at rest (MAX_OFFSET_FACTOR), the old wide
	# reach (FULL_LIMP_OFFSET_FACTOR) back at full ragdoll so a real flail isn't capped.
	var max_off: float = height * lerpf(MAX_OFFSET_FACTOR, FULL_LIMP_OFFSET_FACTOR, loose)
	# Inertial trail: extremities get a nudge OPPOSITE the body's velocity
	# change (mirrored into the local flip) so limbs lag on launch/stop.
	var dv: Vector2 = _body_vel - _prev_body_vel
	_prev_body_vel = _body_vel
	if not (is_finite(dv.x) and is_finite(dv.y)):
		dv = Vector2.ZERO
	var flip_s: float = 1.0 if scale.x >= 0.0 else -1.0
	var trail: Vector2 = Vector2(-dv.x * flip_s, -dv.y) * BODY_TRAIL_FACTOR
	# WORLD-down expressed in this node's LOCAL frame, for the floor clamp below.
	# Derived from the real basis so it stays correct under the body pitch AND the
	# facing flip, which is exactly what the old local-y clamp could not do.
	var down_local: Vector2 = global_transform.basis_xform_inv(Vector2.DOWN)
	if down_local.length_squared() > 0.000001:
		down_local = down_local.normalized()
	else:
		down_local = Vector2.DOWN
	# Legs spring at FULL stiffness for a planted, settled stance (no float smear);
	# they only go loose/flowy (LOOSE_LEG_STIFFNESS) as the body goes limp — the
	# post-hit HURT flail / hold-DOWN ragdoll — so normal walking can't drift.
	var leg_stiffness: float = stiffness * lerpf(1.0, LOOSE_LEG_STIFFNESS, loose)
	for key: String in SIM_JOINTS:
		var target: Vector2 = target_pose[key]
		var vel: Vector2 = _sim_vel[key]
		# The feet spring softer -> the legs lag + swing loosely (the flowy walk).
		var k_stiff: float = leg_stiffness if (key == "foot_lead" or key == "foot_off") else stiffness
		vel += (target - _sim[key]) * k_stiff * delta
		vel += Vector2(0.0, GRAVITY * loose) * delta
		if SIM_EXTREMITIES.has(key):
			vel += trail
			if loose > 0.01:
				# Two incommensurate sines per axis, offset per joint and per figure, so
				# no two limbs (and no two fighters) churn in lockstep. Same construction
				# as SpikeFigure's own noise, which is why it is sines and not randf():
				# it is continuous, so it perturbs a swing instead of shaking it.
				var ph: float = _flail_t + _flail_seed + float(SIM_EXTREMITIES.find(key)) * 1.9
				var nx: float = sin(ph * 6.0) + sin(ph * 11.3 + _flail_seed * 3.0)
				var ny: float = sin(ph * 7.4 + 1.1) + sin(ph * 9.7 + _flail_seed * 2.0)
				vel += Vector2(nx, ny) * FLAIL_NOISE * height * loose * delta
		vel *= damp
		var pos: Vector2 = _sim[key] + vel * delta
		var off: Vector2 = pos - target
		var off_len: float = off.length()
		if off_len > max_off:
			pos = target + off / off_len * max_off
		# Ducking (hold-DOWN ragdoll) must never droop THROUGH the floor: when limp
		# AND grounded, clamp each joint to the standing foot line (y = height*0.5,
		# where the animated feet already rest) and kill downward velocity so the
		# limbs settle ON the floor instead of sinking below the collision box. Only
		# grounded — a mid-air knockback ragdoll still flails freely.
		if _grounded and loose > 0.01:
			# ⚠ CLAMPED IN WORLD SPACE, AND IT HAS TO BE. MEASURED.
			#
			# This used to ask `_local_floor_y(pos.x)` for a per-joint "floor line" and clamp
			# the joint's LOCAL y against it. That is exact only while the body is near
			# upright — and the one moment it matters most is the moment it is not:
			# `_step_body`'s sprawl branch drives the pitch to PRONE_LEAN (1.42 rad, i.e. 81
			# degrees), where the local x axis is nearly VERTICAL in world terms and "the
			# local y of the floor at this local x" stops meaning anything. Worse, clamping
			# local y MOVES the joint's world x, so the line it was clamped against is not
			# the line it ends up over.
			#
			# MEASURED on an 84 px figure taking a knockback flop over a real floor: the
			# lowest DRAWN joint finished 25 px UNDER the ground — 30% of the figure's
			# height — and the looser springs ported from the spike in this same pass took
			# that to 46 px. A body drawn half a body-height through the floor is the same
			# defect as the duck that "clips the hero into the floor"; it was simply hiding
			# behind a pose that never leaned far enough to expose it.
			#
			# Pushing the joint up to the floor in WORLD space and converting back is exact
			# at any pitch, any facing flip and any ride offset, because it goes through the
			# real transform in both directions.
			if is_finite(_ground_world_y):
				var wp: Vector2 = to_global(pos)
				if wp.y > _ground_world_y:
					pos = to_local(Vector2(wp.x, _ground_world_y))
					# Kill the WORLD-downward part of the velocity, not the local-y part:
					# under a near-horizontal body those are different directions.
					var into: float = vel.dot(down_local)
					if into > 0.0:
						vel -= down_local * into
			else:
				# No probe (detached rig / headless suite): fall back to the figure's own
				# standing foot line, the honest answer when the world is unknown.
				var floor_y: float = height * 0.5 - _ride
				if pos.y > floor_y:
					pos.y = floor_y
					if vel.y > 0.0:
						vel.y = 0.0
		_sim[key] = pos
		_sim_vel[key] = vel


## Lazily seed the sim at the target pose (first advance, or an apply_impulse
## arriving before the first frame) so joints never spring in from the origin.
func _ensure_sim(target_pose: Dictionary = {}) -> void:
	if _sim_ready:
		return
	var pose: Dictionary = target_pose if not target_pose.is_empty() else _compute_pose()
	for key: String in SIM_JOINTS:
		_sim[key] = pose[key]
		_sim_vel[key] = Vector2.ZERO
	_sim_ready = true


## Raycast straight down from above the figure to the nearest world/platform collider
## (GROUND_MASK) and cache the contact point in LOCAL y, so _sim_pose can plant the
## stance foot ON the real floor instead of floating above / sinking below it. Runs
## once per frame; sets _ground_local_y = INF when airborne, off-tree (headless), or
## no ground is within reach (feet then hang at their natural pose). A downward ray is
## vertical regardless of scale.x, so the facing flip doesn't matter.
func _update_ground_probe() -> void:
	_ground_local_y = INF
	_ground_world_y = INF
	if not _grounded or state == State.AIR or not is_inside_tree():
		return
	var world: World2D = get_world_2d()
	if world == null:
		return
	var space: PhysicsDirectSpaceState2D = world.direct_space_state
	if space == null:
		return
	# From ~head height down past the feet; long enough to reach the floor a standing
	# figure rests on, short enough that a launched fighter finds no ground (INF).
	var from_w: Vector2 = global_position + Vector2(0.0, -height * 0.5)
	var to_w: Vector2 = global_position + Vector2(0.0, height * 1.5)
	var q := PhysicsRayQueryParameters2D.create(from_w, to_w, GROUND_MASK)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	# WORLD y is the authority now that the body can pitch (see _local_floor_y); the
	# local twin is kept because it is still the right answer under the origin and
	# because _sim_pose's plant contract is expressed in local space.
	_ground_world_y = (hit["position"] as Vector2).y
	_ground_local_y = to_local(hit["position"] as Vector2).y


## Clamp a drawn foot so it rests ON the ground contact line, never sinking below it:
## a support foot (at/below the line) plants exactly on the floor; a lifted foot
## (above the line — a mid-stride swing / kick) is left untouched so the stride still
## reads. Pure math, headless-testable; callers decide WHEN to plant (grounded only).
func _plant_foot(local_foot: Vector2, ground_local_y: float) -> Vector2:
	if local_foot.y >= ground_local_y:
		return Vector2(local_foot.x, ground_local_y)
	return local_foot


## The pose actually DRAWN: _compute_pose() with the driven joints replaced by
## their simulated positions, neck re-derived from the simmed head so head and
## torso stay connected. r + w pass through. draw_figure's 2-bone IK then bends
## knees/elbows from the simmed hip/shoulder/hand/foot for free. Falls back to
## the raw animation pose until the sim is seeded.
func _sim_pose() -> Dictionary:
	var pose: Dictionary = _compute_pose()
	if not _sim_ready:
		return pose
	var target_hand_lead: Vector2 = pose["hand_lead"]  # the aim TARGET, before sim overwrite
	# The gait's own answer for the feet, likewise captured before the sim overwrites it.
	var target_foot: Array[Vector2] = [pose["foot_lead"], pose["foot_off"]]
	for key: String in SIM_JOINTS:
		pose[key] = _sim[key]
	pose["neck"] = _sim["head_center"] + Vector2(0.0, pose["r"])
	# --- THE PLANT IS THE DRAWING. This is the actual anti-slide. ---
	#
	# ⚠ THE BUG THAT SURVIVED TWO FIXES. The world-locked gait has always been right:
	# measured with tools/rig_gait_measure.gd, `_plant_w` holds a support foot to
	# 0.00 px of world drift across a three-second walk. But nothing DREW it. The feet
	# went into the spring sim like every other joint, and the spring (STIFFNESS 180,
	# DAMPING 8 -> damping ratio ~0.3) is badly underdamped and slower than the gait it
	# was chasing: it rings around each new plant instead of settling on it. The foot
	# that reached the screen wandered 12.6 px at Hero.SPEED and 14.3 px at a slow amble
	# — 41% and 46% OF THE FIGURE'S ENTIRE HEIGHT — around a plant that had not moved at
	# all. That is the skate the world-locked gait was built to kill, reintroduced one
	# stage further down the pipe, and it is why the rig read as an animation playing
	# over a sliding body rather than a body standing on its feet. It also ate the
	# stride: a commanded 3.66 px foot lift was drawn as 1.42 px, because the same
	# spring low-passed the swing arc.
	#
	# So while the figure is grounded and settled, the drawn foot IS the gait's foot.
	# The spring still runs underneath and still tracks (its target is the same plant),
	# so handing control back is seamless: `lock` fades to 0 exactly as the figure goes
	# loose, at the same looseness where _update_gait itself gives up (STEP_SFX_MAX_LOOSE).
	# Ragdoll, flop, death collapse, airborne trail and hit flail are therefore untouched
	# — at loose >= STEP_SFX_MAX_LOOSE this branch contributes nothing at all.
	if _gait_ready and (state == State.IDLE or state == State.RUN):
		var lock: float = 1.0 - clampf(
			maxf(_limp, _air_loose) / STEP_SFX_MAX_LOOSE, 0.0, 1.0)
		if lock > 0.0:
			pose["foot_lead"] = (pose["foot_lead"] as Vector2).lerp(target_foot[0], lock)
			pose["foot_off"] = (pose["foot_off"] as Vector2).lerp(target_foot[1], lock)
	# Aim-snap: while twin-stick aiming (Hero), the lead hand tracks the cursor with
	# NO spring lag in the aim states, so the visible hand points EXACTLY where the
	# player aims instead of smearing behind it. Strikes/other states keep the sim.
	if aim_arm and _is_aim_state():
		pose["hand_lead"] = target_hand_lead
	# Foot-plant IK: grounded (and not mid-flail) -> plant the support foot on the real
	# floor line so the figure stands ON the ground; the swing foot keeps its lift.
	if _grounded and state != State.AIR and _limp < 0.5 and is_finite(_ground_world_y):
		# Per-foot floor line, for the same reason the sim's clamp is per joint: a
		# pitched body has no single local ground y.
		var fl: Vector2 = pose["foot_lead"]
		var fo: Vector2 = pose["foot_off"]
		pose["foot_lead"] = _plant_foot(fl, _local_floor_y(fl.x))
		pose["foot_off"] = _plant_foot(fo, _local_floor_y(fo.x))
	return pose


## States in which the twin-stick lead arm points at the cursor (aim_arm heroes only):
## the resting/moving/airborne/dashing poses + the committed cast. Strikes + wall-slide
## keep their scripted arm so the punch/cling reads.
func _is_aim_state() -> bool:
	return state == State.IDLE or state == State.RUN or state == State.AIR \
			or state == State.DASH or state == State.CAST


## Jolt the limbs: mirror `world_dir` into the (possibly flipped) local frame
## and kick every simmed joint's velocity — extremities harder — so a hit
## sends hands/feet/head flailing before the springs reel them back in.
func apply_impulse(world_dir: Vector2, strength: float) -> void:
	if world_dir == Vector2.ZERO \
			or not (is_finite(world_dir.x) and is_finite(world_dir.y)) \
			or not is_finite(strength) or strength == 0.0:
		return
	_ensure_sim()
	var flip_s: float = 1.0 if scale.x >= 0.0 else -1.0
	var local: Vector2 = Vector2(world_dir.x * flip_s, world_dir.y).normalized()
	for key: String in SIM_JOINTS:
		var mult: float = IMPULSE_EXTREMITY_MULT if SIM_EXTREMITIES.has(key) else 1.0
		_sim_vel[key] += local * strength * mult
	# ...AND THE BODY ITSELF. This is the half that was missing, and it is why hits
	# used to rattle a fighter's hands without ever making the fighter look hit:
	# SpikeFigure.hit() throws the whole capsule torso, so the figure tips and sinks.
	# The blow is applied in WORLD terms (the facing flip is a drawing concern, not a
	# physical one): a downward blow compresses the ride, a lateral one spins the body
	# away from it — the torso is shoved at chest height while the feet are still
	# planted, which is exactly what topples a standing person.
	var wd: Vector2 = world_dir.normalized()
	_pitch_vel += wd.x * strength * IMPULSE_TO_SPIN
	queue_redraw()


## Set the limpness target: 0 = fully animated, 1 = full ragdoll (weak springs
## + gravity droop). Eased in advance() so death melts rather than snaps.
func set_limp(t: float) -> void:
	_limp_target = clampf(t, 0.0, 1.0)
	# Anything that un-limps a body brings it back to life for drawing purposes. This
	# is what clears the death state: `Hero.revive` already calls `set_limp(0.0)`, and
	# the hold-DOWN duck's release does too, so no caller had to learn a new verb.
	if _limp_target < 1.0:
		_collapsed = false


## Flop-on-hit: briefly weaken the springs (raise the limp target) so the body
## visibly reels from a blow, then auto-recover to whatever the limp was before
## (0 normally, or 1 if a hold-DOWN ragdoll is active — so they don't fight).
## `strength` 0..1 = how limp; `hold` = seconds before recovery starts. Pair with
## apply_impulse() for the directional whip. Eased both ways via set_limp/advance.
func flop(strength: float = 0.7, hold: float = 0.18) -> void:
	if _flop_timer <= 0.0:
		_flop_prev_target = _limp_target  # remember the resting limp only on entry
	_flop_timer = maxf(_flop_timer, hold)
	_limp_target = maxf(_limp_target, clampf(strength, 0.0, 1.0))


## CLASH RECOIL — the rig's reaction to a blow that MET another blow rather than
## landing on a body (see MeleeClash). Driven separately from, and on top of, the
## knockback flop the body already takes, because the two are different events: a
## knockback is the torso being shoved, a clash is the STRIKING ARM being stopped
## dead by something as hard as it is.
##
## NOT A CANNED POSE, deliberately — per the standing rig directive, the reaction
## is the existing active-ragdoll machinery at clash amplitude and nothing else:
## `flop()` raises the limp target so the springs go slack and the body visibly
## reels, `apply_impulse()` whips every simmed joint (extremities hardest) BACK
## along the axis the blow came from. Two calls, no new state, no keyframes, and it
## composes with a hold-DOWN ragdoll or a death melt instead of fighting them.
##
## `strength01` 0..1 scales both halves together so an even clash and a swatted
## overpower differ in amplitude without differing in kind.
func clash_recoil(away_dir: Vector2, strength01: float = 1.0) -> void:
	var s: float = clampf(strength01, 0.0, 1.0)
	flop(CLASH_FLOP * s, CLASH_FLOP_HOLD)
	apply_impulse(away_dir, CLASH_LIMB_JOLT * s)


## Feed the owning body's velocity (e.g. Hero.velocity each physics frame).
## The frame-to-frame CHANGE adds a small inertial nudge to the extremities so
## limbs trail when the body accelerates or stops. NaN-guarded; subtle.
func set_body_velocity(v: Vector2) -> void:
	if is_finite(v.x) and is_finite(v.y):
		_body_vel = v


## Freeze/unfreeze the locomotion cycle. True = hold the run/idle animation clock
## (the "frozen under ice" read for hard-CC'd enemies); the spring sim still ticks.
func set_frozen(frozen: bool) -> void:
	_frozen = frozen


## Enable twin-stick lead-arm aim (Hero only): the lead arm continuously points at
## the cursor while IDLE/RUN so the visible hand always aims where the mouse is.
func set_aim_arm(enabled: bool) -> void:
	aim_arm = enabled


## Set the persistent flaming-fist charge (0..1) + its element. Bulks the lead fist
## and drives the on-hand fire draw + trailing embers (fire-punch afterglow, item 3).
func set_hand_fire(strength: float, element: int = -1) -> void:
	_hand_fire = clampf(strength, 0.0, 1.0)
	if element >= 0:
		_hand_fire_element = element
	queue_redraw()


## Fire a limb-isolated cast "turn-on" tell that OVERLAYS the lead arm only, so it
## composes with whatever locomotion is active (run/jump/dash) instead of locking
## the body. Independent of the State machine — call alongside play(CAST) or alone.
## `intensity` 0..1 scales the offset amplitude + VFX size (spell power). `element`
## (Elements.Element id, or -1) drives the hand ignite VFX; -1 = motion only.
func cast_gesture(kind: int, intensity: float = 0.6, element: int = -1) -> void:
	_gesture_kind = kind
	_gesture_intensity = clampf(intensity, 0.0, 1.0)
	_gesture_element = element
	_gesture_dur = float(GESTURE_DURATIONS.get(kind, 0.2)) * (0.9 + 0.2 * _gesture_intensity)
	_gesture_time = 0.0
	_gesture_active = kind != GestureKind.NONE
	queue_redraw()


## Set the current animation state. Looping states (IDLE/RUN/DASH) are
## ignored while a one-shot (PUNCH/KICK/CAST/HURT) is playing; a one-shot
## may interrupt another one-shot (e.g. HURT during PUNCH).
func play(new_state: State) -> void:
	var is_one_shot: bool = ONE_SHOT_DURATIONS.has(new_state)
	if _one_shot_active and not is_one_shot:
		return
	if not is_one_shot and new_state == state:
		return
	state = new_state
	if is_one_shot:
		_one_shot_active = true
		_one_shot_duration = ONE_SHOT_DURATIONS[new_state]
		_one_shot_time = 0.0
		_hit_frame_emitted = false
	queue_redraw()


## True while a melee strike (PUNCH/KICK) one-shot is playing. Hero faces the
## aim during a strike so the punch animation points at the cursor/target (the
## arm extends in the body-facing direction), matching the aim-directed damage arc.
func is_striking() -> bool:
	return _one_shot_active and (state == State.PUNCH or state == State.KICK)


## Flip horizontally to face `dir`. Unchanged when dir.x == 0.
func set_facing(dir: Vector2) -> void:
	if dir.x < 0.0:
		scale.x = -1.0
	elif dir.x > 0.0:
		scale.x = 1.0


## Aim the CAST lead arm/staff toward `dir` (the cursor direction), stored as a
## world vector so the arm can point at the true cursor even when the body faces
## the other way. _compute_pose mirrors it into the local frame for the flip.
func set_aim(dir: Vector2) -> void:
	if dir != Vector2.ZERO:
		_aim_world = dir.normalized()


## Arm the directional parry shield: a white curved shell drawn facing `dir`
## (the aim/threat direction) for `duration` seconds, fading as it expires. The
## Stick-Fight block/deflect read — replaces the old omni flash.
func set_parry(dir: Vector2, duration: float) -> void:
	if dir != Vector2.ZERO:
		_parry_dir = dir.normalized()
	_parry_duration = maxf(duration, 0.01)
	_parry_timer = _parry_duration
	queue_redraw()


## World position of the lead-weapon tip (staff crystal / sword point / hand), so
## spells emanate FROM the weapon rather than the body centre. Reads the current
## pose (so during a CAST it points at the aim); `to_global` handles the L/R flip.
func get_weapon_tip() -> Vector2:
	var pose: Dictionary = _compute_pose()
	var shoulder: Vector2 = pose["shoulder"]
	var hand: Vector2 = pose["hand_lead"]
	var arm_dir: Vector2 = hand - shoulder
	if arm_dir.length() < 0.001:
		arm_dir = Vector2.RIGHT
	arm_dir = arm_dir.normalized()
	var reach: float = 0.0
	match equipment.get("weapon", ""):
		"staff", "staff_ice", "staff_storm", "staff_holy": reach = height * 0.38
		"greatsword": reach = height * 0.62
		"dagger": reach = height * 0.24
		"spear": reach = height * 0.72
		"scythe": reach = height * 0.6
		"sword": reach = height * 0.5
		"orb": reach = height * 0.14
	return to_global(hand + arm_dir * reach)


## World position of the LEAD hand (the simulated/drawn one), for trailing fire
## embers etc. Uses the physical sim pose so embers follow the actual drawn hand.
func get_lead_hand_global() -> Vector2:
	return to_global(_sim_pose()["hand_lead"])


## Flight lift, 0 (grounded) .. 1 (airborne). Driven by Hero._update_flight;
## raises the drawn figure and drops a shrinking ground shadow beneath it.
func set_airborne(v: float) -> void:
	_airborne = clampf(v, 0.0, 1.0)
	queue_redraw()


## Grounded state from the owning body (Hero.is_on_floor). Gates the limp
## floor-clamp in _step_sim so ducking never sinks the ragdoll into the ground.
func set_grounded(g: bool) -> void:
	_grounded = g


## Set the AIR-state phase (Hero drives this alongside play(State.AIR)). NO pose is
## keyframed off these — they only BIAS the airborne looseness regime (_air_loose) in
## _step_sim: `rising` = ascending (biased a touch tighter, a coiled leap); false =
## falling (looser drop); `grounded` = the landing frame (looseness settles to 0).
## Harmless to call in any state — only consumed while state == State.AIR.
func set_air_phase(rising: bool, grounded: bool) -> void:
	_air_rising = rising
	_air_grounded = grounded


## Set the base limb/head color (enemy archetype tint, hero blue, ...).
func set_tint(color: Color) -> void:
	limb_color = color
	queue_redraw()


## Briefly whiten the whole figure (hit feedback), then restore the tint.
func flash(duration: float = 0.06) -> void:
	flash_color(Color.WHITE, duration)


## Flash the figure in an arbitrary color (e.g. red for hero damage), then
## restore the tint. `flash()` is the white default and stays the public API.
func flash_color(color: Color, duration: float = 0.06) -> void:
	# A COLLAPSED BODY DOES NOT FLASH. See `collapse` for the flag; the short version is
	# that a corpse still gets hit — leftover projectiles, a lingering zone, a spectacle
	# that outlives its caster — and each of those repaints the whole figure in
	# `Hero.HURT_FLASH_COLOR` (1, 0.2, 0.2). On a frozen bot-match stage that is a KO
	# frame recorded in flat RED with the corner colour nowhere on it, which is exactly
	# the bug this pass was sent to fix, arriving by a second door. PHOTOGRAPHED at
	# +1.60 s in `user://death_ko_04_zoom.png` after the first fix, which cleared the
	# flash once a frame and lost the race to a spell that damages later in the same one.
	if _collapsed:
		return
	_flash_color = color
	_flash_timer = duration
	queue_redraw()


## END A FLASH NOW, whatever is left of it, and go back to the tint.
##
## ⚠ THE BUG THIS EXISTS FOR, because it is not obvious and it cost a whole capture.
## `_flash_timer` is decremented in `advance()`, which runs off the PHYSICS clock. So
## a flash cannot expire while the tree is paused — and `BotMatch._freeze()` pauses
## the tree on the decisive frame and holds it under the result card. The loser takes
## its fatal hit, `Hero.take_damage` sets `HURT_FLASH_COLOR` (1, 0.2, 0.2), the tree
## freezes a few statements later, and the KO frame — the frame that gets RECORDED —
## shows a fighter painted pure RED with its corner colour nowhere in sight. The tint
## was never lost; `_draw` prefers `_flash_color` over `limb_color` and the timer that
## should have handed it back never ticked again.
##
## `Engine.time_scale = 0.05` (hit-stop, which also fires on a kill) is the same bug
## an order of magnitude smaller: a 0.12 s flash lasts 2.4 REAL seconds under it.
##
## Called by `BotMatch._freeze` on both fighters. Cheap, idempotent, no-op if nothing
## is flashing.
func clear_flash() -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer = 0.0
	queue_redraw()


## THE DEATH BEAT ON A BODY THAT IS STILL THERE — a downed hero, the loser of a bot
## match. Deliberately NOT a new animation system: per the standing rig directive
## ("airborne + hits = loose/reactive ragdoll reusing the flop/limp system; true
## physics-body ragdoll only as a last resort"), a death is the flop machinery already
## in this file, taken to its endpoint and held there:
##
##   * `set_limp(1)` — full ragdoll. The springs go slack, gravity droops the limbs,
##     and `_step_body` drops the ride height toward `RIDE_PRONE` (see
##     `PRONE_RIDE_FACTOR`), which is what actually puts the body ON THE FLOOR rather
##     than leaving it standing while its arms dangle.
##   * `apply_impulse()` — the topple. Whips every simmed joint away from the killing
##     blow and imparts the pitch that spins the torso over, so the body falls in the
##     direction it was hit rather than folding straight down.
##   * `play(HURT)` — the pose target underneath the springs.
##
## It is a HOLD, not a flop: `set_limp` is used rather than `flop()` precisely because
## `flop()` auto-recovers to the pre-hit limp after its hold, and a dead body does not
## get back up. `revive()` clears it with `set_limp(0)`, which is what `Hero.revive`
## already does.
##
## `from_dir` is the direction the blow came FROM, in world space; ZERO is legal and
## simply folds the body straight down.
func collapse(from_dir: Vector2 = Vector2.ZERO, strength: float = DEATH_TOPPLE_IMPULSE) -> void:
	set_limp(1.0)
	# ...AFTER `set_limp`, which clears this flag on anything below full limp.
	_collapsed = true
	clear_flash()
	play(State.HURT)
	if from_dir != Vector2.ZERO:
		apply_impulse(from_dir.normalized(), strength)
	# ⚠ AND THEN MAKE THE TORSO SPIN THE WAY IT IS GOING TO SPRAWL ANYWAY.
	#
	# The measured bug this line exists for. `_step_body`'s limp branch drives the
	# pitch toward `facing * PRONE_LEAN` — the sprawl direction is fixed by FACING, not
	# by the blow. `apply_impulse` meanwhile adds `world_dir.x * strength *
	# IMPULSE_TO_SPIN` to the pitch velocity, in WORLD space. So any death where the
	# killing blow came from in front (i.e. most of them) starts the body spinning
	# AWAY from the sprawl it is about to do, and `PITCH_GAIN_LIMP` is 0.22 —
	# deliberately weak, so a knockdown sprawls instead of snapping — which means the
	# spring spends most of a second cancelling the impulse before the body starts
	# going down at all. Measured on a real bot-match KO: pitch was 0.03 rad at +0.2 s
	# and had not passed 0.24 rad by +0.4 s, so the win card slammed in over a fighter
	# still standing more or less upright. Exactly the maker's complaint, one layer down.
	#
	# `maxf` rather than an assignment: a harder blow still topples harder, it simply
	# cannot topple BACKWARDS. Nothing about the sprawl itself is retuned — this only
	# stops the entry from fighting it.
	var face: float = 1.0 if scale.x >= 0.0 else -1.0
	_pitch_vel = face * maxf(absf(_pitch_vel), DEATH_SPIN)
	# ...and START THE BODY ALREADY LOOSE, rather than easing up from wherever it was.
	#
	# ⚠ THE SECOND MEASURED BUG, and it is a chain. `_step_body` only takes its sprawl
	# branch above `loose > 0.35`; below that the body is "planted" and `cap` stays at
	# `LEAN_CAP_GROUND` (0.5 rad), and the clamp at the end of `_step_body` does not
	# merely pin the pitch there — it ZEROES `_pitch_vel`, deleting the spin two lines
	# up. So the whole collapse waits on `_limp` easing past 0.35... which happens at
	# `LIMP_EASE_SPEED` against the SCALED clock, and `Juice.hit_stop` has just dropped
	# `Engine.time_scale` to 0.05 ON THE KILLING BLOW. Measured on a real KO: `_limp`
	# was still 0.05 a fifth of a second after the fatal hit, the pitch had moved 0.06
	# rad, and the result card slammed in over a fighter standing up straight. The two
	# fixes before this one were both real and both invisible behind this.
	#
	# `DEATH_LIMP_SNAP` is a floor, not an assignment, and it is deliberately NOT 1.0:
	# past the sprawl threshold the branch engages, the cap opens honestly through the
	# existing `loose` term, and the remaining 45% still MELTS at the usual rate. So the
	# death starts on the frame it happens and still eases rather than snapping.
	_limp = maxf(_limp, DEATH_LIMP_SNAP)
	_lean_cap = maxf(_lean_cap, LEAN_CAP_GROUND
		+ (LEAN_CAP_PRONE - LEAN_CAP_GROUND) * _limp)
	queue_redraw()


## The pose as DRAWN this frame — the physical, spring-simmed one, not the raw
## animation target. Handed to `DeathSmudge` so a body that is about to be freed can
## be folded down and rubbed out from exactly the shape it died in.
##
## Returns the sim pose (which `_draw` itself uses); `spawn_ghost` deliberately uses
## the target pose instead, because a dash afterimage wants the crisp intended shape
## while a corpse wants the one that was actually on screen.
func snapshot_pose() -> Dictionary:
	return _sim_pose()


## Visual equipment overlay. slot in {"head","body","feet","weapon"};
## kind "" clears the slot. Unknown kinds draw nothing.
func set_equipment(slot: String, kind: String) -> void:
	if kind == "":
		equipment.erase(slot)
	else:
		equipment[slot] = kind
	queue_redraw()


## Convenience gear bundles — one per playable class. Classes WITH a weapon
## (Hero.CLASS_CONFIG "weapon") override the weapon slot via equip_weapon after
## this; weaponless classes (mage staff, brawler fists) keep what's set here.
## Overlay art is reused (robe/hat/hood/staff/sword/orb/fists) — the strong
## class read comes from the element colour, AoE variant, and signature ult.
func class_preset(preset_name: String) -> void:
	match preset_name:
		"mage":
			set_equipment("body", "robe")
			set_equipment("head", "hat")
			set_equipment("weapon", "staff")
		"rogue":
			set_equipment("head", "hood")
			set_equipment("body", "")
			set_equipment("weapon", "sword")
		"summoner":
			set_equipment("body", "robe")
			set_equipment("head", "hat")
			set_equipment("weapon", "orb")
		"brawler":  # bare-fisted bruiser — no robe, no weapon
			set_equipment("body", "")
			set_equipment("head", "")
			set_equipment("weapon", "")
		"juggernaut":  # heavy — bare torso, two-handed war hammer
			set_equipment("body", "")
			set_equipment("head", "")
			set_equipment("weapon", "hammer")
		"cleric":  # hooded templar with a radiant holy staff
			set_equipment("body", "robe")
			set_equipment("head", "hood")
			set_equipment("weapon", "staff_holy")
		"cryomancer":  # hatted frost caster with an ice staff
			set_equipment("body", "robe")
			set_equipment("head", "hat")
			set_equipment("weapon", "staff_ice")
		"stormcaller":  # hatted storm caster with a lightning staff
			set_equipment("body", "robe")
			set_equipment("head", "hat")
			set_equipment("weapon", "staff_storm")
		"warlock":  # hooded hexer with a scythe
			set_equipment("body", "robe")
			set_equipment("head", "hood")
			set_equipment("weapon", "scythe")


## Enable/retint the under-figure aura glow. strength 0 turns it off.
func set_aura(color: Color, strength: float = 1.0) -> void:
	aura_color = color
	aura_strength = strength
	queue_redraw()


## Set the rank tier (0..5) driving aura escalation. Tier 0 kills the aura
## outright; tier 1 is the baseline look; higher tiers get more layers,
## orbiting motes, and the ground ring.
func set_aura_tier(t: int) -> void:
	aura_tier = clampi(t, 0, 5)
	queue_redraw()


## Spawn a fading afterimage of the current pose under `parent` (dash trail).
## Pure visual: no animation, no collision; self-frees. Optional extras for
## the death-corpse read: `launch_velocity` makes the ghost drift as it
## fades; `fade_time` > 0 overrides RigGhost.FADE_TIME.
func spawn_ghost(
	parent: Node,
	ghost_color: Color,
	wind_dir: Vector2 = Vector2.ZERO,
	launch_velocity: Vector2 = Vector2.ZERO,
	fade_time: float = 0.0,
) -> void:
	if parent == null or not is_inside_tree():
		return
	if get_tree().get_nodes_in_group("rig_ghost").size() >= MAX_GHOSTS:
		return
	var ghost_script: GDScript = load(GHOST_SCRIPT_PATH) as GDScript
	var ghost: Node2D = ghost_script.new() as Node2D
	ghost.set("pose", _compute_pose())
	ghost.set("equipment_slots", equipment.duplicate())
	ghost.set("fig_height", height)
	ghost.set("base_color", ghost_color)
	ghost.set("wind_dir", wind_dir)
	ghost.set("launch_velocity", launch_velocity)
	if fade_time > 0.0:
		ghost.set("fade_time", fade_time)
	parent.add_child(ghost)
	ghost.global_transform = global_transform
	# z_index 0 (not -1): the arena Floor ColorRect is an opaque z=0 canvas item,
	# so a z=-1 ghost renders BEHIND the floor and is invisible. The hero keeps
	# its own higher z (set on the rig) so the figure still draws over its trail.
	ghost.z_index = 0


func _draw() -> void:
	var col: Color = _flash_color if _flash_timer > 0.0 else limb_color
	if _airborne > 0.01:
		_draw_shadow()  # ground shadow stays put while the figure lifts (flight)
	_draw_aura()
	# Draw-time transform: impact pop (scale) composed with flight lift (y-offset).
	# Never touches node.scale — set_facing() owns scale.x for the horizontal flip.
	var pop_scale: Vector2 = Vector2.ONE
	if _pop_timer > 0.0:
		var pop: float = 1.0 + (POP_SCALE - 1.0) * clampf(_pop_timer / POP_TIME, 0.0, 1.0)
		pop_scale = Vector2(pop, pop)
	var lift: Vector2 = Vector2(0.0, -_airborne * height * AIRBORNE_LIFT_FACTOR)
	if lift != Vector2.ZERO or pop_scale != Vector2.ONE:
		draw_set_transform(lift, 0.0, pop_scale)
	var pose: Dictionary = _sim_pose()  # draw the PHYSICAL body, not the raw target
	# One pass, one drawing: draw_figure now substitutes geared parts for default
	# parts internally, so there is no second overlay layer to keep in sync.
	draw_figure(self, pose, col, equipment, height, OUTLINE_COLOR)
	_draw_slash_arc(pose, col)
	_draw_parry_shield(pose)
	_draw_cast_gesture_vfx(pose)
	_draw_hand_fire(pose)


## Persistent flaming fist: while a fire charge is active (set_hand_fire after a
## fire punch), a small realistic flame licks off the LEAD hand every frame (the
## fire "stays lit" and TRAILS as the hand moves — item 3). Kept SMALL on-character.
func _draw_hand_fire(pose: Dictionary) -> void:
	if _hand_fire <= 0.01 or _hand_fire_element != Elements.Element.FIRE:
		return
	draw_flame(self, pose["hand_lead"], pose["w"] * 1.7, _hand_fire, _phase)


## The magic-circle ground emblem is still a texture, so keep nearest sampling (the
## procedural AA lines are unaffected — the filter is texture-only).
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Directional parry SHIELD — a white "section of a sphere": a solid curved band
## in front of the figure, facing _parry_dir, with a bright leading rim. Fades
## over its window. The Stick-Fight block/deflect. The world aim is mirrored into
## the (possibly flipped) local frame so it points at the true threat direction.
func _draw_parry_shield(pose: Dictionary) -> void:
	if _parry_timer <= 0.0 or _parry_duration <= 0.0:
		return
	var frac: float = clampf(_parry_timer / _parry_duration, 0.0, 1.0)
	# Snap in bright, ease out: full for the first half of the window, then fade.
	var alpha: float = minf(1.0, frac * 2.0)
	var s: float = 1.0 if scale.x >= 0.0 else -1.0
	var aim: Vector2 = Vector2(_parry_dir.x * s, _parry_dir.y).normalized()
	var center: Vector2 = pose["shoulder"].lerp(pose["hip"], 0.4)  # chest height
	var ang: float = aim.angle()
	var half_span: float = 0.85                       # ~1.7 rad of arc (a shell)
	var r_in: float = height * 0.5
	var r_out: float = height * 0.66
	# Solid curved band, built as a polygon strip between the inner + outer arcs.
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 12
	for i: int in range(steps + 1):
		var a: float = ang - half_span + (2.0 * half_span) * float(i) / float(steps)
		pts.append(center + Vector2.from_angle(a) * r_out)
	for i: int in range(steps + 1):
		var a: float = ang + half_span - (2.0 * half_span) * float(i) / float(steps)
		pts.append(center + Vector2.from_angle(a) * r_in)
	draw_colored_polygon(pts, Color(0.95, 0.98, 1.0, 0.62 * alpha))
	# Bright leading rim on the outer edge + a soft outer glow.
	draw_arc(center, r_out, ang - half_span, ang + half_span, 16, Color(1, 1, 1, 0.95 * alpha), maxf(2.0, height * 0.05))
	draw_arc(center, r_out + height * 0.06, ang - half_span, ang + half_span, 16, Color(0.85, 0.95, 1.0, 0.22 * alpha), height * 0.09)


## Soft ground shadow beneath the figure while airborne — shrinks + fades as it
## rises, selling the top-down "lifted off the ground" read. Drawn in un-lifted
## space (stays on the floor) before the figure's lift transform.
func _draw_shadow() -> void:
	var sh_scale: float = 1.0 - 0.45 * _airborne
	var sh_alpha: float = 0.30 * (1.0 - 0.35 * _airborne)
	draw_set_transform(Vector2(0.0, height * 0.5), 0.0, Vector2(sh_scale, sh_scale * 0.4))
	draw_circle(Vector2.ZERO, height * 0.42, Color(0.0, 0.0, 0.0, sh_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Player-SHAPED aura: the figure silhouette drawn a few times in the aura
## colour, scaled up + fading outward behind the main figure — a glowing halo
## that follows the pose, not a ground circle. Rank tier escalates it: extra
## layers + intensity + pulse, orbiting motes (tier >= 2), ground ring
## (tier >= 3). Tier 1 is EXACTLY the pre-rank baseline; tier 0 draws nothing.
func _draw_aura() -> void:
	if aura_strength <= 0.0 or aura_tier <= 0:
		return
	# Tier 1 keeps the baseline strength/layers/pulse; each tier above stacks.
	var over: float = float(aura_tier - 1)
	var eff: float = minf(aura_strength + AURA_TIER_STRENGTH_STEP * over, 1.6)
	var layers: int = AURA_LAYERS + maxi(aura_tier - 2, 0)
	var pulse_amount: float = AURA_PULSE_AMOUNT * (1.0 + AURA_TIER_PULSE_STEP * over)
	var pulse: float = 1.0 - pulse_amount * 0.5 \
			+ pulse_amount * 0.5 * sin(_phase * AURA_PULSE_SPEED)
	if aura_tier >= GROUND_RING_MIN_TIER:
		_draw_ground_ring(eff)
	var pose: Dictionary = _sim_pose()  # halo hugs the PHYSICAL body
	var step: float = 0.13      # each halo layer is this much larger than the figure
	var base_alpha: float = 0.3
	# Outer (biggest, faintest) first so brighter inner layers sit on top.
	for i: int in range(layers):
		var layer: int = layers - i               # layers..1 (outer -> inner)
		var s: float = (1.0 + step * float(layer)) * pulse
		var a: float = eff * base_alpha / float(layer)
		var glow: Color = Color(aura_color.r, aura_color.g, aura_color.b, a)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
		draw_figure(self, pose, glow, equipment, height)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # reset for the main figure
	_draw_motes(eff)


## Orbiting element-coloured motes — the "charged" read at tier >= 2. Each
## mote is a bright core over a soft halo, alpha shimmering out of phase so
## the ring never reads as a static decoration.
func _draw_motes(eff: float) -> void:
	var count: int = AURA_TIER_MOTES[aura_tier]
	if count <= 0:
		return
	var orbit_r: float = height * MOTE_ORBIT_RADIUS_FACTOR
	var mote_r: float = maxf(1.2, height * 0.06)
	for i: int in range(count):
		var ang: float = _phase * MOTE_ORBIT_SPEED + TAU * float(i) / float(count)
		var pos: Vector2 = Vector2.from_angle(ang) * orbit_r
		var a: float = clampf(
			eff * (0.4 + 0.25 * sin(_phase * MOTE_PULSE_SPEED + float(i) * 1.7)),
			0.08, 1.0
		)
		var core: Color = Color(aura_color.r, aura_color.g, aura_color.b, a)
		var halo: Color = Color(aura_color.r, aura_color.g, aura_color.b, a * 0.35)
		draw_circle(pos, mote_r * 1.9, halo)
		draw_circle(pos, mote_r, core)


## Rotating ground ring under the figure (tier >= 3): a PixelLab magic-circle
## emblem squashed onto the floor + element-tinted + slowly spinning, with the two
## opposed procedural arcs counter-spinning over it for extra motion. The emblem is
## a white/cyan sigil so aura_color tints it to the wielder's element.
func _draw_ground_ring(eff: float) -> void:
	var ring_center: Vector2 = Vector2(0.0, height * 0.55)
	var radius: float = height * 0.62
	var w: float = maxf(1.2, height * 0.05)
	var col: Color = Color(aura_color.r, aura_color.g, aura_color.b, clampf(eff * 0.28, 0.0, 0.6))
	var spin: float = _phase * GROUND_RING_SPIN_SPEED
	# Pixel magic-circle emblem: squashed to the floor, tinted, counter-spinning.
	var emblem: Texture2D = _aura_circle_texture()
	if emblem != null:
		var tsz: Vector2 = emblem.get_size()
		if tsz.x > 0.0:
			var esz: float = (height * 1.7) / tsz.x  # emblem diameter vs figure
			var ecol: Color = Color(aura_color.r, aura_color.g, aura_color.b, clampf(eff * 0.55, 0.0, 0.95))
			draw_set_transform(ring_center, -spin * 0.5, Vector2(esz, esz * 0.4))
			draw_texture(emblem, -tsz * 0.5, ecol)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_set_transform(ring_center, 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, radius, spin, spin + 2.4, 16, col, w)
	draw_arc(Vector2.ZERO, radius, spin + PI, spin + PI + 2.4, 16, col, w)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Lazily-loaded, cached PixelLab magic-circle emblem for the ground aura (null if
## the asset is missing -> falls back to the procedural arcs only).
static var _aura_circle: Texture2D = null
static var _aura_circle_tried: bool = false

func _aura_circle_texture() -> Texture2D:
	if not _aura_circle_tried:
		_aura_circle_tried = true
		if ResourceLoader.exists(AURA_CIRCLE_PATH):
			_aura_circle = load(AURA_CIRCLE_PATH) as Texture2D
	return _aura_circle


## Anticipation-then-thrust extension curve for PUNCH/KICK, over normalized
## one-shot time t in [0, 1]:
##   [0, STRIKE_ANTICIPATION_FRACTION]  wind back to -STRIKE_PULLBACK (ease-in,
##                                      slow — the "loading up" read)
##   [.., HIT_FRAME_FRACTION]           thrust to 1.0 with cubic ease-out
##                                      (fast — full extension lands exactly
##                                      on the hit_frame moment)
##   [.., 1]                            follow-through: holds near extension,
##                                      then retracts to 0
static func _strike_ext(t: float) -> float:
	if t < STRIKE_ANTICIPATION_FRACTION:
		var wind_u: float = t / STRIKE_ANTICIPATION_FRACTION
		return -STRIKE_PULLBACK * wind_u * wind_u
	if t < HIT_FRAME_FRACTION:
		var thrust_u: float = (t - STRIKE_ANTICIPATION_FRACTION) \
				/ (HIT_FRAME_FRACTION - STRIKE_ANTICIPATION_FRACTION)
		var eased: float = 1.0 - pow(1.0 - thrust_u, 3.0)
		return lerpf(-STRIKE_PULLBACK, 1.0, eased)
	var recover_u: float = (t - HIT_FRAME_FRACTION) / (1.0 - HIT_FRAME_FRACTION)
	return 1.0 - recover_u * recover_u


## Quick swoosh arc in front of the lead hand (PUNCH) or lead foot (KICK),
## fading over the strike window. Local +x is the facing direction (the node
## flip mirrors it for free). Cheap: two draw_arc calls.
func _draw_slash_arc(pose: Dictionary, col: Color) -> void:
	if not _one_shot_active or _one_shot_duration <= 0.0:
		return
	if state != State.PUNCH and state != State.KICK:
		return
	var t: float = clampf(_one_shot_time / _one_shot_duration, 0.0, 1.0)
	if t < SLASH_ARC_START or t > SLASH_ARC_END:
		return
	var p: float = (t - SLASH_ARC_START) / (SLASH_ARC_END - SLASH_ARC_START)
	var fade: float = 1.0 - p
	var center: Vector2 = pose["shoulder"] if state == State.PUNCH else pose["hip"]
	var mid_angle: float = 0.0 if state == State.PUNCH else 0.2
	var radius: float = height * SLASH_ARC_RADIUS_FACTOR * (0.85 + 0.3 * p)
	var start_angle: float = mid_angle - SLASH_ARC_SPAN * 0.5
	var end_angle: float = mid_angle + SLASH_ARC_SPAN * 0.5
	var w: float = pose["w"]
	var glow: Color = Color(col.r, col.g, col.b, 0.35 * fade)
	var core: Color = Color(1.0, 1.0, 1.0, 0.85 * fade)
	draw_arc(center, radius, start_angle, end_angle, 10, glow, w * 1.8)
	draw_arc(center, radius, start_angle, end_angle, 10, core, w * 0.8)


## Per-element hand "ignite" VFX drawn at the casting hand during a cast gesture —
## the "turn-on" tell (fire fist, frost hand, sparking fist...). Reuses the HDR-core
## + AA bloom idiom; the glow envelope ignites and dies with the gesture. Only runs
## at draw time (never headless), so Elements lookups here are safe.
func _draw_cast_gesture_vfx(pose: Dictionary) -> void:
	if not _gesture_active or _gesture_element < 0:
		return
	var gu: float = clampf(_gesture_time / _gesture_dur, 0.0, 1.0)
	var glow: float = sin(gu * PI) * (0.4 + 0.6 * _gesture_intensity)
	if glow <= 0.01:
		return
	var p: Vector2 = pose["hand_lead"]
	var rad: float = pose["w"] * (1.6 + 1.4 * _gesture_intensity)
	var ec: Color = Elements.color(_gesture_element)
	var lifted: Color = Color(ec.r, ec.g, ec.b).lerp(Color(1, 1, 1), 0.4)
	var peak: float = maxf(lifted.r, maxf(lifted.g, lifted.b))
	var k: float = 1.55 / maxf(peak, 0.001)
	var core: Color = Color(lifted.r * k, lifted.g * k, lifted.b * k, glow)
	var halo: Color = Color(ec.r, ec.g, ec.b, glow * 0.35)
	match _gesture_element:
		Elements.Element.FIRE: _vfx_fire(p, rad, core, halo)
		Elements.Element.ICE: _vfx_ice(p, rad, core, halo)
		Elements.Element.LIGHTNING: _vfx_lightning(p, rad, core, halo)
		Elements.Element.SHADOW: _vfx_shadow(p, rad, core, halo)
		Elements.Element.ARCANE: _vfx_arcane(p, rad, core, halo)
		Elements.Element.EARTH: _vfx_earth(p, rad, halo)
		Elements.Element.HOLY: _vfx_holy(p, rad, core, halo)
		Elements.Element.WIND: _vfx_wind(p, rad, core, halo)
		_: draw_circle(p, rad * 0.6, core, true, -1.0, true)


func _vfx_fire(p: Vector2, rad: float, _core: Color, _halo: Color) -> void:
	# Realistic organic flame (maker: "the fire effect is so corny; make it seem
	# more like fire"). SMALL/subtle on-character — a compact licking flame, not a
	# big flashy overlay. The shared static draw_flame does tongues + embers.
	draw_flame(self, p, rad, 1.0, _phase)


## Layered organic flame: a deep-red -> orange -> white-hot core with noise-driven
## LICKING tongues (curved teardrops that waver, not flat triangles) and rising
## embers. Additive/HDR so the core blooms. `size` sets the scale, `strength` 0..1
## fades the whole thing. Local -y is UP so the flame rises. STATIC so any canvas
## item (the rig, the enemy status coat) draws the exact same fire. Draw-time only.
static func draw_flame(item: CanvasItem, p: Vector2, size: float, strength: float, phase: float) -> void:
	if strength <= 0.01:
		return
	# Soft outer glow: warm heat haze at the edges (kept faint so it never reads as
	# a dark disc — on the bright arena the bloom pass carries the glow).
	item.draw_circle(p + Vector2(0.0, -size * 0.2), size * 1.5, Color(1.0, 0.4, 0.12, 0.10 * strength), true, -1.0, true)
	# Licking tongues — teardrop polygons that waver with the phase and taper to a
	# flickering tip. Deep-red outer tongue with a brighter orange inner tongue.
	for i: int in 3:
		var seed: float = float(i) * 2.3
		var sway: float = sin(phase * 9.0 + seed) * size * 0.3
		var h: float = size * (1.5 + 0.55 * sin(phase * 13.0 + seed)) * (0.55 + 0.6 * strength)
		var base_w: float = size * (0.44 - 0.08 * float(i))
		var bx: float = (float(i) - 1.0) * size * 0.34
		var basep: Vector2 = p + Vector2(bx, size * 0.35)
		var tip: Vector2 = p + Vector2(bx + sway, -h)
		var mid: Vector2 = basep.lerp(tip, 0.5) + Vector2(sway * 0.5, 0.0)
		item.draw_colored_polygon(PackedVector2Array([
			basep + Vector2(-base_w, 0.0), basep + Vector2(base_w, 0.0),
			mid + Vector2(base_w * 0.5, 0.0), tip, mid + Vector2(-base_w * 0.5, 0.0),
		]), Color(0.9, 0.24, 0.05, 0.6 * strength))
		var iw: float = base_w * 0.55
		item.draw_colored_polygon(PackedVector2Array([
			basep + Vector2(-iw, 0.0), basep + Vector2(iw, 0.0),
			mid.lerp(tip, 0.2) + Vector2(iw * 0.5, 0.0), tip.lerp(basep, 0.12),
			mid.lerp(tip, 0.2) + Vector2(-iw * 0.5, 0.0),
		]), Color(1.15, 0.55, 0.12, 0.8 * strength))
	# White-hot core (HDR > 1 so the bloom pass lifts it).
	item.draw_circle(p + Vector2(0.0, size * 0.05), size * 0.42, Color(1.7, 1.1, 0.5, 0.9 * strength), true, -1.0, true)
	# Rising embers that drift up + fade.
	for i: int in 3:
		var span: float = size * 3.2
		var ey: float = -fposmod(phase * 34.0 + float(i) * 19.0, span)
		var ex: float = sin(phase * 3.0 + float(i) * 2.1) * size * 0.5
		var ea: float = clampf((1.0 - (-ey) / span) * 0.85 * strength, 0.0, 1.0)
		item.draw_circle(p + Vector2(ex, ey), maxf(1.0, size * 0.09), Color(1.4, 0.65, 0.2, ea), true, -1.0, true)


func _vfx_ice(p: Vector2, rad: float, core: Color, halo: Color) -> void:
	draw_arc(p, rad, 0.0, TAU, 12, halo, 1.5, true)
	for i in 6:
		var a: float = TAU * float(i) / 6.0 + _phase * 0.5
		draw_line(p, p + Vector2.from_angle(a) * rad * 1.3, core, 1.6, true)
	draw_circle(p, rad * 0.35, core, true, -1.0, true)


func _vfx_lightning(p: Vector2, rad: float, core: Color, halo: Color) -> void:
	draw_circle(p, rad * 1.2, halo, true, -1.0, true)
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + _phase * 3.0
		var d: Vector2 = Vector2.from_angle(a)
		var pts: PackedVector2Array = PackedVector2Array([
			p, p + d * rad * 0.7 + d.orthogonal() * sin(_phase * 40.0 + float(i)) * rad * 0.3, p + d * rad * 1.4
		])
		draw_polyline(pts, core, 1.4, true)
	draw_circle(p, rad * 0.4, core, true, -1.0, true)


func _vfx_shadow(p: Vector2, rad: float, _core: Color, halo: Color) -> void:
	for i in 2:
		var a0: float = _phase * 1.5 + PI * float(i)
		draw_arc(p, rad * (0.9 + 0.3 * float(i)), a0, a0 + PI * 0.9, 12,
			Color(halo.r, halo.g, halo.b, halo.a * 1.6), 2.0, true)
	draw_circle(p, rad * 0.5, Color(0.5, 0.3, 0.9, halo.a * 1.6), true, -1.0, true)


func _vfx_arcane(p: Vector2, rad: float, core: Color, halo: Color) -> void:
	draw_arc(p, rad, 0.0, TAU, 20, halo, 1.5, true)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 4:
		var a: float = TAU * float(i) / 3.0 + _phase * 2.0  # spinning triangle (wraps closed)
		pts.append(p + Vector2.from_angle(a) * rad * 0.8)
	draw_polyline(pts, core, 1.4, true)
	draw_circle(p, rad * 0.3, core, true, -1.0, true)


func _vfx_earth(p: Vector2, rad: float, halo: Color) -> void:
	# Matte stone chunks coat the fist — no bloom core (earth reads solid, not lit).
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + 0.4
		var c: Vector2 = p + Vector2.from_angle(a) * rad * 0.7
		var s: float = rad * 0.5
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-s, -s * 0.6), c + Vector2(s, -s * 0.4), c + Vector2(s * 0.7, s), c + Vector2(-s * 0.8, s * 0.7)
		]), Color(0.42, 0.3, 0.18, clampf(halo.a * 2.4, 0.0, 1.0)))
	draw_circle(p, rad * 0.3, Color(0.6, 0.46, 0.26, clampf(halo.a * 2.2, 0.0, 1.0)), true, -1.0, true)


func _vfx_holy(p: Vector2, rad: float, core: Color, halo: Color) -> void:
	draw_arc(p, rad * 1.3, 0.0, TAU, 20, core, 1.6, true)
	draw_circle(p, rad * 1.6, Color(halo.r, halo.g, halo.b, halo.a * 0.8), true, -1.0, true)
	draw_circle(p, rad * 0.4, core, true, -1.0, true)


func _vfx_wind(p: Vector2, rad: float, core: Color, _halo: Color) -> void:
	for i in 2:
		var pts: PackedVector2Array = PackedVector2Array()
		for j in 8:
			var t: float = float(j) / 7.0
			var a: float = _phase * 2.0 + PI * float(i) + t * TAU * 0.6
			pts.append(p + Vector2.from_angle(a) * rad * (0.3 + t))
		draw_polyline(pts, Color(core.r, core.g, core.b, core.a * 0.7), 1.5, true)


## Compute the current pose skeleton in local space. Keys: head_center,
## neck, hip, shoulder, hand_lead, hand_off, foot_lead, foot_off,
## plus stroke metrics r (head radius) and w (line width).
func _compute_pose() -> Dictionary:
	# THIN limbs + a small round head — the stick-figure read. See HEAD_R_FACTOR.
	var w: float = maxf(1.6, height * LIMB_W_FACTOR)
	var r: float = maxf(2.0, height * HEAD_R_FACTOR)
	var arm_len: float = height * 0.32
	# The RESTING hip->foot span. Derived from the drawn leg (see LEG_LEN_FACTOR) so a
	# leg the figure stands on can never be shorter than the leg that is painted.
	var leg_len: float = height * LEG_LEN_FACTOR
	var t: float = 0.0
	if _one_shot_active and _one_shot_duration > 0.0:
		t = clampf(_one_shot_time / _one_shot_duration, 0.0, 1.0)
	# PUNCH/KICK: anticipation-then-thrust (negative = wound back).
	# Other one-shots keep the smooth 0 -> 1 -> 0 wave.
	var is_strike: bool = state == State.PUNCH or state == State.KICK
	var ext: float = _strike_ext(t) if is_strike else sin(t * PI)

	# Pose parameters. Angles are radians from each joint: 0 = forward
	# (+x, lead side), PI/2 = straight down, PI = backward.
	var bob: float = 0.0
	var lean: float = 0.0  # +x head/neck offset (forward lean)
	var arm_lead: float = PI * 0.5 + 0.35
	var arm_off: float = PI * 0.5 - 0.35
	var arm_lead_len: float = arm_len
	var leg_lead: float = PI * 0.5 - 0.18
	var leg_off: float = PI * 0.5 + 0.18
	var leg_lead_len: float = leg_len
	var leg_off_len: float = leg_len

	match state:
		State.IDLE:
			# ⚠ THE BREATH ONLY LIFTS — it must never press the hip DOWN.
			#
			# This was `sin(_phase * 2.0) * height * 0.03`, a symmetric bob, so for half
			# of every cycle it drove the hip 3% of the figure's height BELOW its
			# standing position. The feet are ground-locked, so that shortfall has
			# nowhere to go but the knees, and a two-bone IK takes its SQUARE ROOT —
			# MEASURED, the knee jutted 8.3% of figure height at rest and the figure
			# stood in a permanent half-squat. A stick figure standing still has
			# straight legs; that is most of what makes it read as a stickman.
			#
			# `-absf(sin)` keeps the same breathing rhythm and spends it entirely on the
			# UP stroke, where a planted leg simply straightens instead of folding.
			# Smaller too, because it no longer has to be felt through a crouch.
			bob = -absf(sin(_phase * 2.0)) * height * 0.012
		State.AIR:
			# STILL no scripted jump pose (maker: "there shouldnt be like a jump pose it
			# should be ragdoll exactly like Stick Fight"). What the TARGET now is, ported
			# from SpikeFigure's airborne branch, is a SLACK HANG: both legs dangle toward
			# world-down and TRAIL the body's horizontal momentum (leap right and the legs
			# are left behind, to the left), splayed a little so the silhouette isn't two
			# sticks glued together. That is derived from velocity, not keyframed — there
			# is no pose clock here, only "where would loose legs be at this speed".
			var air_flip: float = 1.0 if scale.x >= 0.0 else -1.0
			var air_trail: float = clampf(_body_vel.x * air_flip / 420.0, -1.0, 1.0)
			# Split wider than SpikeFigure's 0.2 rad: it draws a 44 px leg where this rig
			# draws a 12 px one, so the same angle collapsed both legs into a single blob.
			leg_lead = PI * 0.5 - air_trail * 0.95 + 0.34
			leg_off = PI * 0.5 - air_trail * 0.95 - 0.34
			# AIR is a LOOSENESS REGIME, not a
			# keyframe: the springs do the rest —
			# _step_sim lerps the spring PARTWAY toward full limp (see _air_loose) so the
			# limbs trail + swing with the body's momentum + gravity while the weighty
			# CharacterBody2D arcs. No run-cycle leg pumping here (that read as jogging in
			# mid-air); rising/falling only BIAS the looseness, never the pose. The aim
			# arm still overrides the lead hand below (twin-stick), unchanged.
			pass
		State.RUN:
			# Smoother, weightier gait (Stick-Fight feel): a calmer stride
			# frequency, a real leg lift on the back-swing (stride, not a scissor),
			# arm counter-swing, and a two-step bounce synced to the footfalls.
			# Looser, bigger stride — the legs swing wide and the knees lift more, so
			# the soft foot-springs (LOOSE_LEG_STIFFNESS) let them lag + flop loosely
			# for the free, flowy Stick-Fight walk.
			var sp: float = _phase * RUN_PHASE_RATE
			var swing: float = sin(sp) * 1.1
			# ⚠ THE RUN LEAN WAS COUNTED TWICE. This shifts `head_center.x` forward by
			# 0.13 of the figure height — 4.03 px on an 8.85 px torso, which is 24.5 deg
			# of SPINE tilt on its own — and the node ALSO pitches by `RUN_LEAN`. The
			# figure therefore ran bent double. `SpikeFigure` keeps its spine a rigid
			# vertical line in torso space and puts 100% of the lean in body rotation
			# (`RUN_LEAN` 0.16 rad = 9.2 deg); that is the architectural difference
			# behind "not straight". FEEL — the maker judges this number at F5.
			lean = height * 0.04
			leg_lead = PI * 0.5 - swing
			leg_off = PI * 0.5 + swing
			# Lift whichever leg is swinging back (knee bends up) — both legs, opposite
			# phase — for a loose knees-up gait rather than stiff scissoring sticks.
			leg_lead_len = leg_len * (1.0 - 0.24 * maxf(-sin(sp), 0.0))
			leg_off_len = leg_len * (1.0 - 0.24 * maxf(sin(sp), 0.0))
			arm_lead = PI * 0.5 + swing * 0.7
			arm_off = PI * 0.5 - swing * 0.7
			# NO stride bob is authored here any more. The body's rise and fall over the
			# support leg now falls out of the leg geometry itself — see the ride dip in
			# the world-locked-feet block below, where the hips drop because the legs are
			# split and rise because they are together. A sine added on top of that would
			# beat against it. The leg angles above survive only as the pre-seed fallback;
			# the world-locked plants overwrite both feet outright.
		State.DASH:
			lean = height * 0.22
			leg_lead = PI * 0.5 + 0.55
			leg_off = PI * 0.5 + 0.85
			arm_lead = PI * 0.5 + 0.7
			arm_off = PI * 0.5 + 0.95
		State.CAST:
			# Lead arm points at the TRUE world cursor — mirror it into the
			# (possibly flipped) local frame so the staff aims right even when the
			# body faces the other way (twin-stick cast).
			lean = height * 0.05
			var cast_s: float = 1.0 if scale.x >= 0.0 else -1.0
			arm_lead = Vector2(_aim_world.x * cast_s, _aim_world.y).angle()
			arm_off = 0.18
		State.PUNCH:
			# ext < 0 during anticipation coils the torso back and retracts
			# the arm; the same formulas then thrust it past neutral.
			lean = height * 0.08 * ext
			arm_lead = lerpf(PI * 0.45, 0.0, ext)
			arm_lead_len = arm_len * (0.8 + 0.5 * ext)
			arm_off = PI * 0.5 + 0.4
		State.KICK:
			lean = -height * 0.04 * ext
			leg_lead = lerpf(PI * 0.5, 0.05, ext)
			leg_lead_len = leg_len * (0.85 + 0.45 * ext)
			leg_off = PI * 0.5 + 0.15
			arm_lead = PI * 0.5 - 0.5
			arm_off = PI * 0.5 + 0.5
		State.HURT:
			lean = -height * 0.14
			arm_lead = -0.5
			arm_off = PI + 0.5
			leg_lead = PI * 0.5 - 0.35
			leg_off = PI * 0.5 - 0.1
		State.WALL_SLIDE:
			# Clinging to a wall (facing it, +x = wall): both arms reach up-into the
			# wall, legs bent + splayed against it. The IK bends knees/elbows so it
			# reads as a real cling + slide, not a stiff stick.
			lean = height * 0.05
			arm_lead = -0.55
			arm_off = 0.25
			arm_lead_len = arm_len * 0.9
			leg_lead = PI * 0.5 - 0.15
			leg_off = PI * 0.5 + 0.4
			leg_lead_len = leg_len * 0.82

	# Twin-stick lead-arm AIM (Hero only, via set_aim_arm): outside the committed
	# CAST/strike poses the lead arm CONTINUOUSLY points at the cursor while idle or
	# running, so the visible hand always aims where the mouse is (Stick-Fight). The
	# spring sim eases the drawn hand so it tracks smoothly instead of snapping; the
	# OFF arm keeps its locomotion swing so the body still reads as running.
	if aim_arm and _is_aim_state():
		var aim_s: float = 1.0 if scale.x >= 0.0 else -1.0
		var aim_local: Vector2 = Vector2(_aim_world.x * aim_s, _aim_world.y)
		if aim_local.length() > 0.001:
			arm_lead = aim_local.angle()
			arm_lead_len = arm_len

	# Skeleton joints (local space; feet at +height/2, head top at -height/2).
	var head_center: Vector2 = Vector2(lean, -height * 0.5 + r + bob)
	var neck: Vector2 = head_center + Vector2(0, r)
	var hip: Vector2 = Vector2(0, height * HIP_Y_FACTOR + bob * 0.5)
	var shoulder: Vector2 = neck.lerp(hip, 0.15)
	var hand_lead: Vector2 = shoulder + Vector2.from_angle(arm_lead) * arm_lead_len
	var hand_off: Vector2 = shoulder + Vector2.from_angle(arm_off) * arm_len
	var foot_lead: Vector2 = hip + Vector2.from_angle(leg_lead) * leg_lead_len
	var foot_off: Vector2 = hip + Vector2.from_angle(leg_off) * leg_off_len

	# --- WORLD-LOCKED FEET (the anti-slide) ---
	# In the grounded locomotion states the drawn feet are NOT derived from a swing
	# angle at all: they are the gait's world plants pulled back through to_local, so
	# a foot bearing weight stays nailed to the same point on the floor while the body
	# travels over it. to_local also mirrors them into the facing frame, so a turn
	# doesn't teleport the stance. Strikes (KICK), CAST, DASH, HURT, WALL_SLIDE and AIR
	# keep their own scripted/loose legs — those poses are not standing on anything.
	if _gait_ready and (state == State.IDLE or state == State.RUN):
		foot_lead = to_local(_gait_foot_world(0))
		foot_off = to_local(_gait_foot_world(1))
		# --- THE BODY RIDES ON ITS LEGS ---
		# A leg is a fixed length. Split the feet wide and the hips MUST come down;
		# bring them together and the body rises to its full height. Without this the
		# hip sat at a constant height and any stride worth the name simply stretched
		# the shin — the "sticks on rails" read, and the reason the first port had to
		# keep the stride tiny to hide it. Deriving the dip instead means the stride can
		# be as long as the leg allows, and the vertical bounce of the walk comes out as
		# a CONSEQUENCE of the geometry (hips highest at mid-stance, lowest at the split)
		# rather than a sine bolted alongside it.
		#
		# BOTH feet are asked, support and swing alike. They reach their extremes at the
		# same instant — the split stance, one foot forward and one just leaving — so
		# this is one dip per step at the widest point, not two. The swing foot stops
		# asking for depth the moment it lifts, because its own arc raises it.
		var reach: float = height * LEG_REACH_FACTOR * LEG_REACH_USABLE
		var dip: float = 0.0
		for i: int in 2:
			var f: Vector2 = foot_lead if i == 0 else foot_off
			var dx: float = absf(f.x - hip.x)
			# How high above this foot the hip can be while the leg still reaches it.
			var lift_ok: float = sqrt(maxf(reach * reach - dx * dx, 0.0))
			dip = maxf(dip, (f.y - lift_ok) - hip.y)
		dip = clampf(dip, 0.0, height * MAX_STRIDE_DIP_FACTOR)
		if dip > 0.0:
			# The WHOLE upper body drops together — head, neck, hips, shoulders and the
			# hands hanging off them. Dropping the hip alone would stretch the torso.
			var d := Vector2(0.0, dip)
			head_center += d
			neck += d
			hip += d
			shoulder += d
			hand_lead += d
			hand_off += d

	# Cast-gesture overlay: additive, lead-arm-isolated, composes over locomotion.
	# Damped out automatically when limp (the sim's stiffness is _limp-scaled).
	if _gesture_active and _limp < 0.9:
		var gu: float = clampf(_gesture_time / _gesture_dur, 0.0, 1.0)
		var amp: float = height * (0.25 + 0.55 * _gesture_intensity)
		var cast_s: float = 1.0 if scale.x >= 0.0 else -1.0
		var aim_l: Vector2 = Vector2(_aim_world.x * cast_s, _aim_world.y)
		if aim_l.length() < 0.001:
			aim_l = Vector2.RIGHT
		aim_l = aim_l.normalized()
		var aim_perp: Vector2 = aim_l.orthogonal()
		match _gesture_kind:
			GestureKind.FLICK:
				var e: float = sin(gu * PI)  # 0..1..0 snap out then back
				hand_lead += aim_l * amp * 0.9 * e - aim_perp * amp * 0.25 * e
				shoulder += aim_l * amp * 0.12 * e
			GestureKind.IGNITE_DROP:
				var drop: float = 1.0 - pow(1.0 - gu, 2.0)  # ease-out drop
				var back: float = sin(gu * PI)              # recover hump
				hand_lead += Vector2(0.0, amp * 0.8) * drop * (1.0 - 0.6 * back) - aim_l * amp * 0.2 * back
				shoulder += Vector2(0.0, amp * 0.15) * drop
			GestureKind.RAISE:
				var e3: float = sin(gu * PI)
				hand_lead += Vector2(-aim_l.x * amp * 0.3, -amp * 1.1) * e3
				shoulder += Vector2(0.0, -amp * 0.2) * e3
			GestureKind.GATHER:
				var pull: float = smoothstep(0.0, 0.55, gu)
				var thrust: float = smoothstep(0.55, 1.0, gu)
				var chest: Vector2 = shoulder.lerp(hip, 0.35) - hand_lead
				hand_lead += chest * 0.7 * pull * (1.0 - thrust) + aim_l * amp * 1.2 * thrust
				hand_off += (shoulder.lerp(hip, 0.35) - hand_off) * 0.6 * pull * (1.0 - thrust)
				shoulder += aim_l * amp * 0.25 * thrust - Vector2(0.0, amp * 0.1) * pull
			GestureKind.STOMP:
				var slam: float = 1.0 - pow(1.0 - gu, 3.0)  # hard ease-out slam
				var settle: float = sin(gu * PI)
				hand_lead += Vector2(aim_l.x * amp * 0.2, amp * 1.0) * slam
				shoulder += Vector2(0.0, amp * 0.2) * slam
				foot_lead += Vector2(aim_l.x * amp * 0.3, amp * 0.15) * settle

	# Hands/feet as Stick-Fight capsule CAPS (radius = half the limb width) — no
	# ball fists, no toes. The lead hand gets a whisper of clench through a strike
	# and a modest bulk on a flaming charge, but stays SF-scale (the flame VFX
	# carries the fire read, not a bloated fist).
	var hand_base_r: float = w * 0.5
	var hand_lead_r: float = hand_base_r
	if is_strike:
		hand_lead_r = w * lerpf(0.5, 0.8, clampf(ext, 0.0, 1.0))  # subtle SF-scale clench
	if _hand_fire > 0.01:
		hand_lead_r = maxf(hand_lead_r, w * (0.6 + 0.4 * _hand_fire))
	var foot_r: float = w * 0.5

	return {
		"head_center": head_center,
		"neck": neck,
		"hip": hip,
		"shoulder": shoulder,
		"hand_lead": hand_lead,
		"hand_off": hand_off,
		"foot_lead": foot_lead,
		"foot_off": foot_off,
		"hand_lead_r": hand_lead_r,
		"hand_off_r": hand_base_r,
		"foot_r": foot_r,
		"r": r,
		"w": w,
	}


## Draw a stick-figure pose onto any CanvasItem. Must be called from that
## item's own _draw(). Shared by _draw() and RigGhost so dash afterimages
## render the exact same silhouette. `col.a` scales the robe/gear alphas.
static func draw_figure(
	item: CanvasItem,
	pose: Dictionary,
	col: Color,
	equipment_slots: Dictionary,
	fig_height: float,
	outline_col: Color = Color(0.0, 0.0, 0.0, 0.0),
) -> void:
	var w: float = pose["w"]
	var r: float = pose["r"]
	var head_center: Vector2 = pose["head_center"]
	var neck: Vector2 = pose["neck"]
	var hip: Vector2 = pose["hip"]
	var shoulder: Vector2 = pose["shoulder"]
	var hand_lead: Vector2 = pose["hand_lead"]
	var hand_off: Vector2 = pose["hand_off"]
	var foot_lead: Vector2 = pose["foot_lead"]
	var foot_off: Vector2 = pose["foot_off"]
	# Visible hand/fist + foot radii (default to the old joint-cap size for any
	# hand-built pose that predates them, so callers never break).
	var hlr: float = pose.get("hand_lead_r", w * 0.5)
	var hor: float = pose.get("hand_off_r", w * 0.5)
	var ftr: float = pose.get("foot_r", w * 0.5)

	# --- ARTICULATED limbs (the Stick-Fight upgrade): solve a KNEE per leg + an
	# ELBOW per arm with 2-bone IK so the figure BENDS like a real body instead of
	# stiff straight sticks. Segment sums exceed the limb reach so there's always
	# a real bend; knees bend forward (+x local), elbows bend down. ---
	var thigh: float = fig_height * THIGH_FACTOR
	var shin: float = fig_height * SHIN_FACTOR
	var upper: float = fig_height * 0.2
	var fore: float = fig_height * 0.2
	# ⚠ NEVER DRAW A LIMB LONGER THAN ITS OWN BONES. `_ik_joint` CLAMPS its reach
	# (`d = clampf(dist, .., l1 + l2 - 0.01)`) — but the drawn shin then ran from that
	# clamped knee to the RAW, unclamped foot, so whatever the clamp refused to solve
	# was simply drawn as extra shin. MEASURED on the shipped build: the drawn leg
	# reached 1.449x thigh+shin, the shin alone hit 1.9x its own length, and because
	# the clamp had collapsed the bend to 0.28 px the knee sat on the straight line —
	# one long straight stick with no knee in it, on 28-43% of moving frames.
	#
	# THAT is "the legs are not straight or look like a stickman". It is not the lean
	# and it is not the plants: the spine angle is identical to the decimal with the
	# gait on and off (25.6 / 28.1 / 40.3 deg across the same six shots).
	#
	# Re-deriving the drawn foot from the SOLVED leg is `SpikeFigure.gd:2092` verbatim,
	# and it is the Stick Fight push-off rather than a compromise: the trailing heel
	# lifts and the knee bends behind you instead of the leg scraping after the body.
	# The PLANT is untouched (`_plant_w` never sees this), so nothing here reintroduces
	# skating — measured drift of the drawn foot off its plant is <= 2.3 px in steady
	# state, against the 12.6 px ring the last rig fix removed.
	var knee_lead: Vector2 = _ik_joint(hip, foot_lead, thigh, shin, Vector2.RIGHT)
	foot_lead = knee_lead + (foot_lead - knee_lead).normalized() * shin
	var knee_off: Vector2 = _ik_joint(hip, foot_off, thigh, shin, Vector2.RIGHT)
	foot_off = knee_off + (foot_off - knee_off).normalized() * shin
	var elbow_lead: Vector2 = _ik_joint(shoulder, hand_lead, upper, fore, Vector2.DOWN)
	var elbow_off: Vector2 = _ik_joint(shoulder, hand_off, upper, fore, Vector2.DOWN)

	# CLOTHING IS OFF BY DEFAULT (see draw_clothing). A stickman holding a sword is
	# still unmistakably a stickman; a stickman in a cuirass and a great-helm is a
	# little armoured man. The slots are still SET (GearAbilities, the loadout UI and
	# the enemy archetype table all read `equipment`) — they simply aren't DRAWN, so
	# the ability plumbing is untouched and this is one boolean away from coming back.
	var head_kind: String = String(equipment_slots.get("head", "")) if draw_clothing else ""
	var body_kind: String = String(equipment_slots.get("body", "")) if draw_clothing else ""

	# Crisp dark OUTLINE pass: the same articulated skeleton drawn thicker under so
	# the bold coloured figure reads against any background (the Stick-Fight look).
	# Aura silhouette + dash ghosts pass no outline_col (a==0) -> they stay soft.
	# The GEARED head/torso are outlined by the same helpers that draw them, so a
	# helmet gets the identical keyline the bare head would have had — the gear is
	# part of the drawing, not a decal sitting on it.
	if outline_col.a > 0.0:
		var oc: Color = Color(outline_col.r, outline_col.g, outline_col.b, outline_col.a * col.a)
		# Keyline scaled off the stroke (see OUTLINE_FACTOR) rather than a flat +2 px,
		# so a spindly limb keeps a proportionate dark edge instead of disappearing
		# under one. `oe` is the per-side bleed the joint dots reuse below.
		var oe: float = maxf(OUTLINE_MIN, w * OUTLINE_FACTOR)
		var ow: float = w + oe
		_draw_torso(item, body_kind, neck, hip, oc, ow, r)
		_draw_limb(item, shoulder, elbow_lead, hand_lead, oc, ow)
		_draw_limb(item, shoulder, elbow_off, hand_off, oc, ow)
		_draw_limb(item, hip, knee_lead, foot_lead, oc, ow)
		_draw_limb(item, hip, knee_off, foot_off, oc, ow)
		item.draw_circle(hand_lead, hlr + oe * 0.6, oc)
		item.draw_circle(hand_off, hor + oe * 0.6, oc)
		item.draw_circle(foot_lead, ftr + oe * 0.5, oc)
		item.draw_circle(foot_off, ftr + oe * 0.5, oc)
		# The head keyline is sized off the LIMB bleed, not the head radius, so the
		# skull keeps a matching line weight rather than a fat ring of its own.
		_draw_head(item, head_kind, head_center, r + oe * 0.7, oc, ow)

	# The figure: head + torso + 2 articulated arms + 2 articulated legs. The head and
	# torso are drawn THROUGH the gear helpers, which substitute the geared part for
	# the default one rather than stacking a second shape over it.
	_draw_head(item, head_kind, head_center, r, col, w)
	_draw_torso(item, body_kind, neck, hip, col, w, r)
	_draw_limb(item, shoulder, elbow_lead, hand_lead, col, w)
	_draw_limb(item, shoulder, elbow_off, hand_off, col, w)
	_draw_limb(item, hip, knee_lead, foot_lead, col, w)
	_draw_limb(item, hip, knee_off, foot_off, col, w)
	# Rounded joints/ends: filled dots cap the lines so the limbs read solid.
	item.draw_circle(shoulder, w * 0.5, col)
	item.draw_circle(hip, w * 0.55, col)
	# VISIBLE hands/fists — clearly bigger than a joint cap (Stick-Fight read); the
	# lead fist grows through a strike / flaming charge via hlr from _compute_pose.
	item.draw_circle(hand_off, hor, col)
	item.draw_circle(hand_lead, hlr, col)
	# Feet: rounded leg-ends only (SF has no toe nub).
	item.draw_circle(foot_off, ftr, col)
	item.draw_circle(foot_lead, ftr, col)

	_draw_equipment(
		item, equipment_slots, col, w, r, fig_height,
		head_center, shoulder, hand_lead, foot_lead, foot_off
	)


## THE HEAD — geared or bare. Head gear does not sit ON the head, it IS the head:
## the default circle is never drawn underneath, so the figure reads as a stickman
## whose head is a helmet, not a stickman with a helmet sticker.
##
## HITBOX CONTRACT: every variant keeps a filled disc of EXACTLY radius `r` centred
## on `head_center`, because that circle is what Enemy.body_distance / SpellTargets
## test against. Silhouette embellishments (a hat's cone, a crown's points) only ever
## ADD outside that disc — they never shrink or move it. Break this and spells start
## passing through heads again.
##
## Called twice: once with the outline colour + inflated radius, once with the body
## colour, so the gear inherits the same keyline treatment as the rest of the figure.
static func _draw_head(
	item: CanvasItem, kind: String, c: Vector2, r: float, col: Color, w: float
) -> void:
	# The mandated disc, always. Everything below only extends the silhouette upward.
	item.draw_circle(c, r, col)
	match kind:
		"helmet":
			# A closed great-helm: the skull disc plus a squared jaw-guard dropping
			# past it, with a visor slit cut in the body colour's dark twin.
			item.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.95, -r * 0.1), c + Vector2(r * 0.95, -r * 0.1),
				c + Vector2(r * 0.8, r * 1.15), c + Vector2(-r * 0.8, r * 1.15),
			]), col)
			# Crest ridge along the top — the read that says "plate", at outline weight.
			item.draw_line(c + Vector2(0.0, -r * 1.25), c + Vector2(0.0, -r * 0.2), col, w * 0.7)
		"hat":
			# Pointed wizard cone rising straight out of the skull, plus a wide brim.
			item.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.85, -r * 0.4), c + Vector2(r * 0.85, -r * 0.4),
				c + Vector2(r * 0.12, -r * 2.5),
			]), col)
			# Brim kept just wider than the skull. At r*1.7 it read as a crossbar bolted
			# through the head rather than a hat the head is wearing.
			item.draw_line(c + Vector2(-r * 1.2, -r * 0.45), c + Vector2(r * 1.2, -r * 0.45), col, w * 0.6)
		"hood":
			# A cowl peak swept back off the crown, so the head is a hooded shape.
			item.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 1.15, r * 0.5), c + Vector2(-r * 1.05, -r * 0.75),
				c + Vector2(r * 0.2, -r * 1.5), c + Vector2(r * 1.1, -r * 0.2),
				c + Vector2(r * 0.95, r * 0.85),
			]), col)
		"crown":
			# Three points straight off the skull — regalia, not a hat.
			for i: int in 3:
				var bx: float = (float(i) - 1.0) * r * 0.72
				item.draw_colored_polygon(PackedVector2Array([
					c + Vector2(bx - r * 0.33, -r * 0.75), c + Vector2(bx + r * 0.33, -r * 0.75),
					c + Vector2(bx, -r * 1.85),
				]), col)
			item.draw_line(c + Vector2(-r, -r * 0.72), c + Vector2(r, -r * 0.72), col, w * 0.8)


## THE TORSO — geared or bare. Same substitution rule: armour IS the torso, so the
## plain spine stroke is not drawn under it.
##
## HITBOX CONTRACT: every variant is built around the neck->hip segment, which is
## what body_distance measures the spine against. Gear may only THICKEN that segment
## (making the drawn body bigger than the hitbox, which is forgiving); it must never
## displace it.
##
## `cape` was dropped outright rather than drawn. It is an accessory that hangs off
## a body, so there is no body part for it to become — and the maker's first
## instruction was "remove the clothing". Its GearAbilities entry is untouched, so
## nothing that reads the ability registry breaks; it simply has no silhouette.
static func _draw_torso(
	item: CanvasItem, kind: String, neck: Vector2, hip: Vector2, col: Color, w: float, r: float
) -> void:
	match kind:
		"armor":
			# A plated slab: the spine stroke widened into a cuirass with squared
			# pauldron shoulders. Solid fill in the body colour — same drawing, more
			# of it — rather than a lighter sheet laid over a thin stick.
			var down: Vector2 = (hip - neck)
			if down.length() < 0.001:
				down = Vector2.DOWN
			var side: Vector2 = down.orthogonal().normalized()
			item.draw_colored_polygon(PackedVector2Array([
				neck + side * r * 1.05, neck - side * r * 1.05,
				hip - side * r * 0.95, hip + side * r * 0.95,
			]), col)
			item.draw_line(neck, hip, col, w)     # keeps the exact spine axis solid
		"robe":
			# The torso flares into a bell down past the hip: the caster's body IS the
			# robe. Fully opaque in the body colour (the old version was a 45%-alpha
			# sheet draped over the stick — visibly a garment ON a figure).
			var d: Vector2 = (hip - neck)
			if d.length() < 0.001:
				d = Vector2.DOWN
			var sd: Vector2 = d.orthogonal().normalized()
			var hem: Vector2 = hip + d.normalized() * r * 1.6
			item.draw_colored_polygon(PackedVector2Array([
				neck + sd * r * 0.75, neck - sd * r * 0.75,
				hem - sd * r * 1.9, hem + sd * r * 1.9,
			]), col)
			item.draw_line(neck, hip, col, w)
		_:
			item.draw_line(neck, hip, col, w)


## Draw a two-segment limb root->mid->end with a rounded joint cap at the mid.
static func _draw_limb(item: CanvasItem, a: Vector2, mid: Vector2, b: Vector2, col: Color, w: float) -> void:
	item.draw_line(a, mid, col, w)
	item.draw_line(mid, b, col, w)
	item.draw_circle(mid, w * 0.5, col)  # knee / elbow cap


## 2-bone IK: the joint of a chain root->end with segment lengths l1 (root->joint)
## and l2 (joint->end), bent toward `hint`. Clamped so an over-extended chain just
## straightens instead of producing NaNs.
static func _ik_joint(root: Vector2, end: Vector2, l1: float, l2: float, hint: Vector2) -> Vector2:
	var delta: Vector2 = end - root
	var dist: float = delta.length()
	if dist < 0.0001:
		return root
	var d: float = clampf(dist, absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var dir: Vector2 = delta / dist
	var along: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h: float = sqrt(maxf(l1 * l1 - along * along, 0.0))
	var perp: Vector2 = dir.orthogonal()
	if perp.dot(hint) < 0.0:
		perp = -perp
	return root + dir * along + perp * h


## Gear overlay. Weapons are oriented ALONG the lead arm (hand - shoulder) so
## they read as HELD and gripped, not floating: the shaft runs through the hand
## and the business end points where the arm points — so casting (arm at cursor)
## aims the staff/sword at the target. A thin dark under-edge keeps the crisp
## outlined Stick-Fight look.
static func _draw_equipment(
	item: CanvasItem,
	equipment_slots: Dictionary,
	col: Color,
	w: float,
	r: float,
	fig_height: float,
	_head_center: Vector2,
	shoulder: Vector2,
	hand_lead: Vector2,
	foot_lead: Vector2,
	foot_off: Vector2,
) -> void:
	var gear_col: Color = col.lightened(0.25)
	# NOTE: the head slot is NOT handled here any more — head gear replaces the head
	# itself (see _draw_head), so drawing it a second time here would put the sticker
	# back on top of the body part it is supposed to BE.
	# Footwear is clothing too — gated with the rest of it (see draw_clothing).
	match (equipment_slots.get("feet", "") if draw_clothing else ""):
		"sandals":
			item.draw_line(
				foot_lead + Vector2(-r * 0.5, 0), foot_lead + Vector2(r * 0.5, 0), gear_col, w
			)
			item.draw_line(
				foot_off + Vector2(-r * 0.5, 0), foot_off + Vector2(r * 0.5, 0), gear_col, w
			)

	# Arm direction: from the shoulder through the lead hand, extended outward.
	var arm_dir: Vector2 = hand_lead - shoulder
	if arm_dir.length() < 0.001:
		arm_dir = Vector2.RIGHT
	arm_dir = arm_dir.normalized()
	var perp: Vector2 = arm_dir.orthogonal()
	var edge: Color = Color(0.07, 0.08, 0.13, col.a)  # dark under-edge (OUTLINE feel)
	match equipment_slots.get("weapon", ""):
		"sword":
			# Blade runs out along the arm; a short crossguard sits across the grip.
			var s_len: float = fig_height * 0.5
			var s_base: Vector2 = hand_lead - arm_dir * (fig_height * 0.05)
			var s_tip: Vector2 = hand_lead + arm_dir * s_len
			item.draw_line(hand_lead - perp * r * 0.7, hand_lead + perp * r * 0.7, edge, w * 1.1)
			item.draw_line(s_base, s_tip, edge, w * 1.5)          # dark edge under the blade
			item.draw_line(s_base, s_tip, gear_col, w * 0.95)     # blade body
			item.draw_line(
				hand_lead + arm_dir * (s_len * 0.4), s_tip, gear_col.lightened(0.35), w * 0.35
			)  # bright fuller/shine toward the tip
			item.draw_circle(s_tip, w * 0.5, gear_col)            # rounded point
		"staff":
			# Sleek short WAND: a thin shaft the hand grips, tipped with a small
			# glowing crystal (a cut gem) — reads cool without dominating the figure.
			var st_len: float = fig_height * 0.38
			var st_butt: Vector2 = hand_lead - arm_dir * (fig_height * 0.07)
			var st_tip: Vector2 = hand_lead + arm_dir * st_len
			item.draw_line(st_butt, st_tip, edge, w * 0.95)       # dark edge
			item.draw_line(st_butt, st_tip, gear_col, w * 0.55)   # thin shaft
			# Angular crystal tip (a small 4-point gem), glowing.
			var gem: float = maxf(w * 1.4, 2.4)
			var gp: Vector2 = arm_dir.orthogonal()
			var gem_pts: PackedVector2Array = PackedVector2Array([
				st_tip + arm_dir * gem, st_tip + gp * gem * 0.55,
				st_tip - arm_dir * gem * 0.45, st_tip - gp * gem * 0.55,
			])
			item.draw_colored_polygon(gem_pts, gear_col.lightened(0.45))
			item.draw_circle(st_tip + arm_dir * gem * 0.2, w * 0.45, Color(1, 1, 1, col.a))  # hot glint
		"greatsword":
			# The sword's silhouette at brutal scale: longer, thicker, blunter tip.
			_draw_blade(item, hand_lead, arm_dir, perp, fig_height * 0.62, w * 1.2, r * 0.95, gear_col, edge, col)
		"dagger":
			# The same blade language, short and quick — identifiable from outline alone.
			_draw_blade(item, hand_lead, arm_dir, perp, fig_height * 0.26, w * 0.85, r * 0.45, gear_col, edge, col)
		"spear":
			# Long plain haft ending in a leaf point. Reach IS the read.
			var sp_tip: Vector2 = hand_lead + arm_dir * (fig_height * 0.72)
			var sp_butt: Vector2 = hand_lead - arm_dir * (fig_height * 0.16)
			item.draw_line(sp_butt, sp_tip, edge, w * 0.9)
			item.draw_line(sp_butt, sp_tip, gear_col, w * 0.5)
			var sp_base: Vector2 = sp_tip - arm_dir * (fig_height * 0.12)
			item.draw_colored_polygon(PackedVector2Array([
				sp_base + perp * w * 0.9, sp_tip, sp_base - perp * w * 0.9,
			]), gear_col.lightened(0.3))
		"hammer":
			# Short haft, big square head — the mass is all at the far end, which is
			# exactly what should read at a glance.
			_draw_hafted(item, hand_lead, arm_dir, perp, fig_height * 0.44, w, gear_col, edge)
			var h_c: Vector2 = hand_lead + arm_dir * (fig_height * 0.44)
			var h_s: float = fig_height * 0.095
			item.draw_colored_polygon(PackedVector2Array([
				h_c + perp * h_s - arm_dir * h_s * 0.72, h_c + perp * h_s + arm_dir * h_s * 0.72,
				h_c - perp * h_s + arm_dir * h_s * 0.72, h_c - perp * h_s - arm_dir * h_s * 0.72,
			]), gear_col)
		"club":
			# A haft that simply swells toward the business end — the crude cousin of
			# the hammer, told entirely through taper.
			var c_butt: Vector2 = hand_lead - arm_dir * (fig_height * 0.08)
			var c_tip: Vector2 = hand_lead + arm_dir * (fig_height * 0.42)
			item.draw_line(c_butt, c_tip, edge, w * 1.9)
			item.draw_colored_polygon(PackedVector2Array([
				c_butt + perp * w * 0.4, c_butt - perp * w * 0.4,
				c_tip - perp * w * 0.95, c_tip + perp * w * 0.95,
			]), gear_col)
			item.draw_circle(c_tip, w * 0.95, gear_col)
		"scythe":
			# Long haft with a crescent sweeping off the tip — the one weapon whose
			# outline is a curve, so it can't be confused with the straight family.
			_draw_hafted(item, hand_lead, arm_dir, perp, fig_height * 0.6, w, gear_col, edge)
			var sc_tip: Vector2 = hand_lead + arm_dir * (fig_height * 0.6)
			var sc_r: float = fig_height * 0.2
			var sc_c: Vector2 = sc_tip - perp * sc_r * 0.55
			var sc_a: float = perp.angle()
			item.draw_arc(sc_c, sc_r, sc_a - 0.35, sc_a + 1.5, 14, edge, w * 1.5)
			item.draw_arc(sc_c, sc_r, sc_a - 0.35, sc_a + 1.5, 14, gear_col.lightened(0.3), w * 0.8)
		"bomb":
			# A held sphere with a lit fuse — a prop in the fist, not a polearm.
			var b_c: Vector2 = hand_lead + arm_dir * (r * 0.5)
			item.draw_circle(b_c, r * 0.95, edge)
			item.draw_circle(b_c, r * 0.78, gear_col.darkened(0.35))
			item.draw_line(b_c + Vector2(0.0, -r * 0.78), b_c + Vector2(r * 0.4, -r * 1.8), gear_col, w * 0.4)
			item.draw_circle(b_c + Vector2(r * 0.4, -r * 1.8), w * 0.55, Color(1.0, 0.75, 0.3, col.a))
		"staff_ice", "staff_storm", "staff_holy":
			# Same wand silhouette as "staff" — only the crystal changes colour, because
			# the element is the gameplay read and the shape is the class read.
			_draw_wand(
				item, hand_lead, arm_dir, fig_height, w, gear_col, edge, col,
				STAFF_GEM_TINT.get(equipment_slots.get("weapon", ""), gear_col) as Color
			)
		"orb":
			# A floating orb hovering just past the grip, with a soft halo.
			var o_c: Vector2 = hand_lead + arm_dir * (fig_height * 0.14)
			item.draw_circle(o_c, r * 0.85, Color(gear_col.r, gear_col.g, gear_col.b, col.a * 0.3))
			item.draw_circle(o_c, r * 0.55, gear_col.lightened(0.35))


## Bold flat blade with a dark keyline + a crossguard: the shared shape behind
## sword / greatsword / dagger, so the family reads as one weapon at three scales.
static func _draw_blade(
	item: CanvasItem, grip: Vector2, dir: Vector2, perp: Vector2,
	blade_len: float, thick: float, guard: float,
	gear_col: Color, edge: Color, col: Color
) -> void:
	var base: Vector2 = grip - dir * (blade_len * 0.1)
	var tip: Vector2 = grip + dir * blade_len
	item.draw_line(grip - perp * guard, grip + perp * guard, edge, thick * 0.8)
	item.draw_line(base, tip, edge, thick * 1.5)
	item.draw_line(base, tip, gear_col, thick)
	item.draw_line(grip + dir * (blade_len * 0.4), tip, gear_col.lightened(0.35), thick * 0.35)
	item.draw_circle(tip, thick * 0.5, gear_col)
	# Silence the unused-parameter warning without dropping the alpha contract:
	# every colour above already carries col.a through gear_col/edge.
	if col.a < 0.0:
		return


## Plain hafted shaft (hammer/scythe/spear backbone): keyline under, body over.
static func _draw_hafted(
	item: CanvasItem, grip: Vector2, dir: Vector2, _perp: Vector2,
	shaft_len: float, w: float, gear_col: Color, edge: Color
) -> void:
	var butt: Vector2 = grip - dir * (shaft_len * 0.22)
	var tip: Vector2 = grip + dir * shaft_len
	item.draw_line(butt, tip, edge, w * 0.95)
	item.draw_line(butt, tip, gear_col, w * 0.55)


## The wand shape shared by every staff variant; `gem` tints only the crystal.
static func _draw_wand(
	item: CanvasItem, grip: Vector2, dir: Vector2, fig_height: float, w: float,
	gear_col: Color, edge: Color, col: Color, gem_col: Color
) -> void:
	var st_len: float = fig_height * 0.38
	var butt: Vector2 = grip - dir * (fig_height * 0.07)
	var tip: Vector2 = grip + dir * st_len
	item.draw_line(butt, tip, edge, w * 0.95)
	item.draw_line(butt, tip, gear_col, w * 0.55)
	var gem: float = maxf(w * 1.4, 2.4)
	var gp: Vector2 = dir.orthogonal()
	item.draw_colored_polygon(PackedVector2Array([
		tip + dir * gem, tip + gp * gem * 0.55, tip - dir * gem * 0.45, tip - gp * gem * 0.55,
	]), Color(gem_col.r, gem_col.g, gem_col.b, col.a))
	item.draw_circle(tip + dir * gem * 0.2, w * 0.45, Color(1, 1, 1, col.a))
