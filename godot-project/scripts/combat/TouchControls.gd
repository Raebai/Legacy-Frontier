class_name TouchControls
extends CanvasLayer
## Mobile-first TWIN-STICK touch layer (CLAUDE.md non-negotiable D-011: "every action
## must work via virtual joystick + tap"). Feeds the SAME named input actions the
## keyboard uses (move_*, aim_*, dash, cast, blast, blink, ultimate) so it composes
## with Hero with almost no combat-code changes.
##
## WHY TWO STICKS NOW. This layer used to publish only move_left / move_right /
## move_down — no upward component at all — and that was survivable only because Hero
## snapped the aim to the nearest enemy on touch. That auto-aim has been deleted (the
## locked rule is: you point, you throw, and landing it is your skill). The moment it
## went, a touch player could no longer aim at anything above them, because the input
## layer had no way to say "up". So aim gets its own stick, movement gets its missing
## up, and the two are fully decoupled — which also un-tangles the old mess where
## pushing the move stick DOWN both ducked you and aimed you at the floor.
##
## ⚠ THE LAYOUT HAS NOW BEEN MEASURED ON PHONE ASPECTS, WHICH IT NEVER HAD BEEN, AND
## THREE OF THE THINGS IT FOUND WERE BUGS RATHER THAN TUNING.
## `tools/probe_touch_layout.gd` sweeps 16:9 / 19.5:9 / 20:9 / 21:9 reading the DRAWN
## rects off the real Controls, in logical px, in device px and in MILLIMETRES;
## `tools/slice_test_touch_layout.gd` is the suite that fails on what it finds. It
## found:
##
##   1. DASH SAT IN THE ANDROID HOME-SWIPE STRIP on every aspect — the panic button,
##      inside the 24 dp the OS steals drags from. Lifted (see DASH_BTN_OFFSET).
##   2. JUMP COULD NOT BE PRESSED WHILE MOVING. A landscape hand puts ONE finger on the
##      glass, so the left thumb on the move stick is the left hand's whole input, and
##      JUMP was bottom-left — 115 mm from the right knuckle against a 62 mm sweep.
##      Moved to the right cluster (see JUMP_BTN_OFFSET). This is the one change a
##      player will feel immediately.
##   3. NOTHING IN THE PROJECT READ THE SAFE AREA. No `get_display_safe_area()` call
##      existed anywhere in `scripts/` or `tools/`; a display cutout in landscape would
##      have eaten a cluster whole. Now read on boot and on every resize
##      (see `_refresh_insets`).
##
## Two smaller ones: the contextual handoff pad was 6 mm on its short axis (under the
## 9 mm floor) and, once the insets moved the arc inboard, overlapped spell button 1's
## hit box by 13x54 px. Both fixed at the HANDOFF_* block.
##
## Layout (landscape, base viewport 640x360, canvas_items stretch):
##   LEFT THUMB  — DYNAMIC move stick (appears where you press in the left zone):
##                 full 360 analog move, push DOWN past a threshold = duck/ragdoll
##                 (move_down). A SNAP of the stick dashes (DASH_ON_FLICK), so the one
##                 movement verb that used to need the other thumb no longer does.
##                 PARRY sits above it — and ONLY parry, because a held guard ROOTS you
##                 (Hero zeroes move_x while blocking), so it is the single verb that
##                 provably cannot be simultaneous with movement.
##   RIGHT THUMB — DYNAMIC aim stick (appears where you press in the right zone,
##                 anywhere that is not a button). Full 360 aim, and pushing past
##                 AIM_FIRE_THRESHOLD also holds `cast` — classic twin-stick. A dim
##                 home ring marks the natural resting spot. A quick TAP in this zone
##                 fires one shot along the aim already held (AIM_TAP_FIRES) — the half
##                 of the spec's tap/drag ATTACK that needs no ruling, because it points
##                 nowhere the player was not already pointing. THE SPELL BUTTONS sit
##                 on an arc swept around the bottom-right corner, with JUMP in the
##                 corner itself and DASH one seat inboard; they consume their own taps,
##                 so a tap on a button never spawns a stick under it.
##   CENTRE      — the dead band between the two zones, normally empty. The only
##                 thing that ever appears there is the CONTEXTUAL HANDOFF PAD,
##                 which exists exactly while a teammate is in range and you are
##                 holding something to give (see the HANDOFF_* block).
##   (Class / element / signature swapping is set in the hub, not mid-fight — ~14
##   keyboard actions won't fit two thumbs, so combat is consolidated to these.)
##
## THE CONSOLIDATION, and what it cost. This layer used to ship EIGHT corner-anchored
## buttons: JUMP / CAST / DASH / Q / G / BLINK / HIT / PARRY — a keyboard drawn on a
## phone. The spec is "left thumb: stick; right thumb: three spell buttons", so the
## right thumb now carries the KIT SLOTS (`spell_1..4`) and nothing else but
## dash, and the primary attack moved onto the aim stick where it was already half
## living (AIM_STICK_FIRES). Four verbs lost their touch affordance in the trade:
##   * `melee` — the primary IS the melee swing for the melee classes
##     (Hero._cast dispatches per class), so a phone Brawler still punches.
##   * `blast` / `blink` / `nova` — the class ability trio.
##
## ⚠ AND THE DESKTOP HAS NOW FOLLOWED THE PAD, which reverses what that trio cost.
## This block used to say a phone player was "short three verbs a desktop player has";
## with the maker's six-thing ruling ("4 spells, deflect and basic attack — that's all
## there should be to all of them") those three are gone from the hotbar too, so the
## pad is no longer the poorer surface — it got there first. The KEYS still fire on a
## keyboard (see the ⚠ block on `Hero.ability_hud_state` for why they were not torn
## out), so the honest statement is now "three verbs no HUD advertises, reachable only
## by a key". Nothing to remove here: this layer never drew a button for any of them.
##
## ⚠ DASH AND JUMP STAY, THOUGH THE BAR NO LONGER DRAWS THE DASH. They are MOVEMENT,
## and movement is the one thing the pad may not drop: a keyboard player who loses the
## dash SQUARE still has the space bar, a thumb has nothing at all, and D-011 (mobile
## -first, every action reachable by joystick + tap) is a project non-negotiable. The
## ruling was about how many squares the eye has to read mid-fight, not about deleting
## the movement verb — `Hero._move_slot_name` is still authoritative for eleven of them.
## `_button_layout()` below is one table, so if the maker wants the corner emptier too,
## it is one row.
##
## Every position/size below is computed from a handful of named constants (a thumb
## pivot, an arc radius, three angles) rather than typed in per button, so tuning the
## reach on a device moves the whole arc coherently instead of one button at a time.
##
## THE TWO-THUMB QUESTION — AND WHAT NOW ANSWERS HALF OF IT. With the aim stick firing,
## the right thumb has two jobs: hold the stick to spray the primary, or lift onto a
## spell button. AIM_TAP_FIRES takes the HOLD out of the first job: a tap fires once
## along the aim already held, so between shots the thumb is free rather than
## committed. The rest of this paragraph still stands. Lifting is safe
## because Hero HOLDS the last aim below its deadzone (Hero.TOUCH_AIM_DEADZONE) — the
## shot does not fling somewhere random while your thumb is off the stick. So the
## real loop is: steer left, aim+fire right, flick the right thumb onto 1/2/3 to spend
## a slot along the aim you were already holding. That is why the aim stick carries
## the primary and the spells stay as buttons, rather than the reverse.
##
## Shows only on a touchscreen (or force_visible for on-device-preview from desktop);
## desktop keyboard/mouse play is completely unaffected. On-device FEEL (button size,
## reach, stick radius, fire threshold) is the maker's tuning pass — the knobs are the
## consts below, and EVERY ONE of them is an untested guess: no touch device has ever
## run this.

## Force the pad visible on desktop to preview/verify (normally touchscreen-gated).
@export var force_visible: bool = false
## Simulate a phone's OS-owned edges during a desktop preview, in LOGICAL pixels, as
## (left, top, right, bottom). A desktop has no cutout and no gesture bar, so a preview
## is honest about the layout and silent about the thing that actually broke it; set
## this to the numbers `tools/probe_touch_layout.gd` prints and the preview shows what
## the phone shows. Ignored on a real device, which reports its own.
@export var preview_insets: Vector4 = Vector4.ZERO

## The layout maths, shared with `tools/probe_touch_layout.gd` and
## `tools/slice_test_touch_layout.gd` so the pad and the things that measure it cannot
## disagree about where a thumb target is. Every entry point on it is `static func` —
## a `preload` of a .gd yields the SCRIPT OBJECT, not an instance.
const TouchLayout := preload("res://scripts/combat/TouchLayout.gd")

# ------------------------------------------------------------------ TUNING KNOBS
# All UNTESTED GUESSES — nothing here has been felt on a real phone yet.

## --- left move stick ---
const JOY_RADIUS: float = 66.0        # max knob travel from the origin (px, base space)
const JOY_DEADZONE: float = 0.18      # ignore tiny wobble before we call it "moving"
const JOY_DUCK_THRESHOLD: float = 0.6 # push down past this -> duck (move_down)
## Push the MOVE stick up past this to also press `jump`. OFF by default: there is a
## dedicated JUMP button, and a stick that jumps when you meant to walk up-left is a
## classic mobile annoyance. One flip to try it.
const LEFT_STICK_UP_JUMPS: bool = false
const JOY_UP_JUMP_THRESHOLD: float = 0.7
const LEFT_ZONE_FRAC: float = 0.45    # left of this fraction of the screen = move zone

## --- right aim stick ---
## Deliberately a little smaller than the move stick: aiming is a fine gesture made
## with the thumb tip, walking is a coarse one made with the pad of the thumb.
const AIM_RADIUS: float = 52.0
## Push past this (0..1 of AIM_RADIUS) and the stick also holds `cast`. It is well
## ABOVE Hero.TOUCH_AIM_DEADZONE (0.20) on purpose, which buys a quiet ring between
## the two: a gentle push RE-AIMS without shooting, a committed push shoots. If the
## maker wants aim and fire fully separated, set AIM_STICK_FIRES = false and the CAST
## button becomes the only trigger.
const AIM_FIRE_THRESHOLD: float = 0.55
const AIM_STICK_FIRES: bool = true
## Right of this fraction of the screen = aim zone. The gap between LEFT_ZONE_FRAC and
## this is a deliberate dead band down the middle: a stray tap in the centre of the
## screen must not yank the aim off target mid-fight.
const RIGHT_ZONE_FRAC: float = 0.55
## Where the dim "put your thumb here" ring sits, as (from the right edge, up from the
## bottom) in base-viewport px. Sits just INBOARD of the spell arc so the resting thumb
## is a short flick from every button. The stick itself is floating, so this ring is
## guidance, not a hitbox.
const AIM_HOME_OFFSET: Vector2 = Vector2(268.0, 88.0)

## --- TAP TO FIRE, the half of the spec's ATTACK button that needs no ruling ---
## A quick tap-and-release inside the aim zone fires ONE shot along the aim you are
## already holding, without ever pushing the stick past AIM_FIRE_THRESHOLD.
##
## ⚠ THIS IS NOT AUTO-AIM AND IT IS DELIBERATELY NOT THE SPEC'S VERSION OF THE IDEA.
## `docs/superpowers/specs/2026-09-04-mobile-controls-design.md` §5 proposes "tap =
## fires at the obvious target", and flags in the same breath that it contradicts the
## maker's standing NO-AUTO-AIM ruling. That contradiction is a maker decision and is
## left alone here. What this does instead is the part nobody has to rule on: the tap
## fires exactly where `Hero._aim_dir` is ALREADY pointing — the direction the player
## themself last set and which Hero holds below its deadzone. No target is consulted,
## nothing snaps, and a tap can no more hit an enemy you were not pointing at than a
## keyboard click can.
##
## What it buys is the thing the file header calls "THE TWO-THUMB QUESTION": the right
## thumb no longer has to HOLD the stick to keep the primary going, so lifting onto a
## spell button stops being a trade.
const AIM_TAP_FIRES: bool = true
## How long a press may last and still count as a tap rather than a stick grab.
const AIM_TAP_MSEC: float = 220.0
## ...and how far it may travel. Above this the thumb was steering, not tapping.
const AIM_TAP_SLOP: float = 18.0
## How long the tap holds `cast` down. One frame is not enough: `Hero` samples the
## action in `_physics_process`, so a press released inside the same render frame can
## be missed entirely. Two physics ticks at 60 Hz, with slack.
const AIM_TAP_HOLD_MSEC: float = 60.0

## --- DASH ON A STICK FLICK (spec §4, §7.2) ---
## Snap the MOVE stick sideways and you dash, with no button involved.
##
## ⚠ ADDITIVE, NOT A REPLACEMENT. The spec's §4 table removes the DASH button in the
## same breath; the measurement in `tools/probe_touch_layout.gd` does not support
## removing it — DASH overlaps nothing, sits 8 mm from the right thumb's knuckle (the
## closest target on the pad, exactly as a panic button should be) and is well over the
## 9 mm floor. So the flick is added as a SECOND way in, the button stays, and the cut
## stays a maker call rather than a side effect of implementing a flick.
const DASH_ON_FLICK: bool = true
## Stick speed, in stick-units per second (the stick is normalised to 1.0 at full
## deflection), that counts as a flick. A walk ramps; a dash snaps.
const FLICK_SPEED: float = 7.0
## ...and the deflection it must reach. A tiny fast wobble near centre is a hand
## tremor, not an intention — this is the flick's deadzone, and it is what
## `tools/slice_test_touch_layout.gd` pins so a resting stick can never dash.
const FLICK_MIN_DEFLECTION: float = 0.55
## Refractory window, so one physical flick fires exactly one dash instead of one per
## frame while the stick is still travelling.
const FLICK_COOLDOWN_MSEC: float = 260.0
## How long the flick holds `dash`. Same reasoning as AIM_TAP_HOLD_MSEC.
const FLICK_HOLD_MSEC: float = 60.0

## --- the right thumb's arc ---
## Everything below is an UNTESTED GUESS: no touch device has ever run this layout.
## They are named and derived rather than hand-placed so a device pass moves the whole
## arc at once — change the radius and all three buttons stay a thumb-sweep apart.
##
## Where the right thumb PIVOTS, as (from the right edge, up from the bottom) in the
## 640x360 base space. Roughly the knuckle of a thumb on a phone held in landscape.
const THUMB_PIVOT: Vector2 = Vector2(30.0, 26.0)
## How far the thumb TIP sits from that pivot. The spell buttons live on this arc.
##
## ⚠ 126 -> 165 WHEN THE FOURTH SLOT LANDED, and it is geometry, not taste. The
## buttons are drawn as circles but TAPPED as axis-aligned rectangles, so the binding
## constraint is the 30-60 degree pair, whose separation is R * (cos 60 - cos 30) =
## 0.366 R on BOTH axes. Four 60 px buttons spread across the same quarter-circle
## therefore need R >= 60 / 0.366 = 164. Shrinking the button instead was the other
## way out and it is the one thing this layout may not do: 60 px at the 640-wide base
## is the thumb target.
const SPELL_ARC_RADIUS: float = 165.0
## Where on the arc, in degrees measured from "straight inboard" (toward the screen
## centre) round to "straight up". Spell 1 — the one you throw most — is the flattest
## and therefore the shortest reach; the ULT is the top of the sweep, which is the
## same "heaviest thing furthest from rest" ramp the desktop hotbar draws.
##
## ⚠ THESE ARE NOT FREE. Buttons are drawn as circles but TAPPED as rectangles, so two
## neighbours whose circles clear each other can still have overlapping hit boxes.
## `SPELL_ARC_ANGLES` + `SPELL_ARC_RADIUS` + `SPELL_BTN_SIZE` are checked against each
## other in tools/slice_test_spell_buttons.gd; retune them there, not by eye.
const SPELL_ARC_ANGLES: Array[float] = [0.0, 30.0, 60.0, 90.0]
const SPELL_BTN_SIZE: float = 60.0
## HOW MANY OF THEM ARE DRAWN. Normally all of them — one per kit slot.
##
## ⚠ THE SPEC ASKS FOR 4 -> 2 + A CONTEXTUAL ULT AND THE MEASUREMENT DOES NOT BACK IT.
## `tools/probe_touch_layout.gd` swept 16:9 / 19.5:9 / 20:9 / 21:9 and found the four
## arc buttons overlapping nothing, all four between 10.4 and 11.3 mm (over the 9 mm
## floor and at the 11 mm thumb-contact width), and all four between 23 and 32 mm from
## the right thumb's knuckle — comfortably inside a 45 mm sweep. The arc is not
## crowded and it is not out of reach. The spec's case for cutting it is ATTENTION —
## "we dont want to overwhelm them with buttons" — which is a claim about a person's
## eyes during a fight and cannot be settled from this machine.
##
## So the trim is a KNOB, not a decision taken here. Set this to 2 and the arc draws
## the first two slots only. ⚠ IT WILL FAIL TWO SUITES THIS LAYER DOES NOT OWN, both
## of which derive their expectation from `SpellTier.SLOT_COUNT` rather than from here:
## `tools/slice_test_touch.gd` (button-count equality, and its required-actions list
## naming spell_3 / spell_4) and `tools/slice_test_spell_buttons.gd`
## (`_test_touch_arc`, "the arc has one button per kit slot"). Both should be re-derived
## from THIS constant when the maker makes the call.
const SPELL_BUTTONS_SHOWN: int = 4
## Is PARRY a touch button at all? Spec §6 asks for the cut to live behind a constant
## so a device pass can put it back in one line — this is that constant, and it is
## deliberately still TRUE.
##
## ⚠ THE SPEC SAYS "CUT IT BY DEFAULT" AND THE MEASUREMENT SAYS THERE IS NO ROOM
## PROBLEM TO SOLVE: PARRY overlaps nothing at any aspect, sits 24 mm from the left
## knuckle, and is 9.0-9.8 mm across — at the floor, but not under it. Cutting a real
## defensive verb (Hero reads `parry` in three places, and the bots parry) on a
## geometric argument that does not exist would be spending a mechanic to buy nothing.
## Flipping this to false also fails `tools/slice_test_touch.gd`, whose required-verbs
## list names `parry` — one line there, and it is the maker's line to write.
const PARRY_ON_TOUCH: bool = true
## DASH lives in the corner itself — under the thumb at rest, because it is the panic
## button and the one press that must never need a reach.
##
## ⚠ THE LIFT WENT 14 -> 26 AND IT IS THE ONE MEASURED BUG THIS PASS EXISTS FOR.
## At 14, DASH's bottom edge sat 2.4-2.6 mm off the bottom of the screen, INSIDE the
## 3.81 mm (24 dp) strip Android reserves for the swipe-up-from-the-bottom system
## gesture — on every one of the four aspects probed. The safe area does NOT report
## that strip: this game ships `screen/immersive_mode=true`, so the nav bar is hidden,
## the safe area grows to the whole screen, and the gesture keeps working anyway. The
## symptom on a device is the worst possible one for a panic button — a dash that
## USUALLY works and occasionally throws the player to the home screen instead.
## 26 clears 3.81 mm at the tightest pitch in the device table (0.173 mm/px -> 22 px)
## with slack, and `_refresh_insets()` adds the device's measured strip on top at
## runtime.
##
## ⚠ AND THE CORNER SEAT WENT TO JUMP — see JUMP_BTN_OFFSET for why that is a
## measurement and not a preference. DASH sits one seat inboard at 84, which leaves
## 12 logical px of clear air to JUMP on one side and 55 to spell button 1 on the other.
## 12 px is tighter than a thumb pad (~11 mm ~ 60 px), so a mis-tap between these two IS
## possible — accepted deliberately, because they are both MOVEMENT verbs and confusing
## a dash for a jump costs a moment, whereas confusing a spell for a dash costs a
## cooldown. The pair with the expensive mis-tap is the one given the wide gap.
const DASH_BTN_OFFSET: Vector2 = Vector2(84.0, 26.0)
const DASH_BTN_SIZE: float = 56.0
## ⚠ JUMP MOVED TO THE RIGHT THUMB, AND IT IS THE SECOND MEASURED BUG IN THIS PASS.
##
## It used to be bottom-LEFT at (14, 62) — stacked above the move stick. In landscape a
## hand puts exactly ONE finger on the screen (the thumb; the index is behind the
## phone), so the left thumb holding the move stick is the left hand's only contact.
## JUMP therefore could not be pressed WITHOUT LETTING GO OF MOVEMENT, and running off
## a ledge and jumping is not an advanced technique in a side-on platform fighter with
## gravity, terraces and ring-out — it is the basic verb.
##
## Measured rather than argued: from the RIGHT thumb's knuckle, the old left-hand JUMP
## sat ~115 mm away on a 20:9 phone, against a 62 mm maximum sweep. Not "awkward" —
## geometrically out of reach. `tools/slice_test_touch_layout.gd` now fails on exactly
## that class of pairing.
##
## The two ways out that were rejected:
##   * `LEFT_STICK_UP_JUMPS = true`. It COLLIDES: `move_up` is not spare on this stick —
##     `Hero` reads it in five places to resolve the DIRECTIONAL DASH (Hero.gd:3769 and
##     four more), so up-to-jump would make every up-left dash a jump.
##   * A second JUMP button on the right, keeping the left one. Two buttons for one verb
##     is the "a keyboard drawn on a phone" failure the consolidation pass existed to
##     undo.
##
## So JUMP takes the CORNER — the press that must never need a reach, which is the
## claim the spec makes for it ("the most-pressed verb, must be dead reliable") — and
## DASH moves one seat inboard. Dash can afford it: since DASH_ON_FLICK it has a second
## way in that needs no button at all, and jump does not.
const JUMP_BTN_OFFSET: Vector2 = Vector2(16.0, 26.0)
const JUMP_BTN_SIZE: float = 54.0
## PARRY on the LEFT, which looks wrong and is not: a held guard ROOTS you (Hero zeroes
## move_x while ParryRing.blocks_attack), so it costs the left thumb nothing it was
## using — and it leaves the right thumb free to keep aiming through a block.
const PARRY_BTN_OFFSET: Vector2 = Vector2(14.0, 126.0)
## ⚠ 52 -> 54, WHICH IS ONE MEASUREMENT AND NOT A NUDGE. On the smallest device in
## `TouchLayout.DEVICES` (5", 1280x720) the pitch is 0.1730 mm per logical px, so 52 px
## is 8.996 mm — a hair UNDER the 9 mm floor every other target on this pad clears, and
## PARRY is the target you press while something is already swinging at you. 54 is
## 9.34 mm there and 10.2 mm on a 6.5" phone. It stays clear of JUMP above it by 10 px.
const PARRY_BTN_SIZE: float = 54.0

## --- shared ---
const PAD_ALPHA: float = 0.34         # translucent so it doesn't hide the fight
## Cooldown veil over a spell button, drawn as a bottom-anchored wipe that shrinks as
## the slot recovers — the same read as the hotbar's, so the two never disagree.
const CD_VEIL_COLOR: Color = Color(0.02, 0.03, 0.06, 0.66)
## The ready-flash: a slot that just came back flares its rim. A ready button should
## invite the press, not merely stop refusing it.
const READY_FLASH_COLOR: Color = Color(0.65, 0.95, 1.0)
## Resting rim of a spell button that is ready to throw, vs one that is not.
const RIM_READY: Color = Color(0.72, 0.92, 1.0, 0.85)
const RIM_COOLING: Color = Color(0.5, 0.53, 0.62, 0.5)
## --- Tier 3 charge pips on a spell pad ---
## A picked-up spell has 1–2 uses and then evaporates back into your class ult. On a
## phone this pad is the ONLY readout there is (the desktop hotbar stands down when
## the pad is live), so without these the count is invisible and "picking one up is a
## decision" becomes a surprise mid-fight. Gold, because that is what the pickup was
## wearing on the floor (`SpellPickup.TIER3_GOLD`).
const PIP_COLOR: Color = Color(1.0, 0.86, 0.42, 0.98)
const PIP_RADIUS: float = 3.2
const PIP_GAP: float = 8.5
const PIP_INSET: Vector2 = Vector2(9.0, 9.0)
const PIP_MAX_DOTS: int = 4

## --- the contextual HANDOFF pad ---
## ⚠ WHY THIS IS NOT A SEVENTH THUMB BUTTON. The right thumb already carries three
## spell pads plus DASH on one arc, and the consolidation pass that got the layout
## there deliberately COST four verbs (blast/blink/nova/melee) rather than let the pad
## grow back into a keyboard. A permanent handoff button would spend that hard-won
## corner on a verb that is useful for perhaps two seconds a floor — and it would sit
## under the thumb that is aiming, so its most likely press is an accidental one.
##
## But the mechanic cannot be unreachable either: the spec says build it because it
## produces both the generous play and the betrayal.
##
## So the pad is CONTEXTUAL and lives in the CENTRE DEAD BAND — the strip between
## LEFT_ZONE_FRAC and RIGHT_ZONE_FRAC that exists precisely so no stick ever spawns
## there. Three things fall out of that choice:
##   * It costs the fight layout nothing. When there is no offer it does not exist,
##     and the band goes back to being dead.
##   * Its APPEARANCE is the prompt. `SpellHandoff` already draws "[E] give X" above
##     the receiver; the pad appearing at the same instant is the same signal in the
##     place your thumb can act on, so a phone player learns the mechanic the first
##     time they stand next to a teammate.
##   * Either thumb can take it. A handoff is a lull — you both stopped fighting —
##     so neither thumb is committed, and the centre is the one place both can reach.
## It consumes its own taps (like the buttons do), so it can be wider than the band
## without a near-miss spawning a stick underneath it.
## ⚠ 34 px IS 5.9-6.4 mm ON ITS SHORT AXIS — UNDER THE 9 mm FLOOR EVERY OTHER TARGET
## ON THIS PAD CLEARS, and it stays that way, which is a tracked decision rather than an
## oversight. It looked fine because it is WIDE; the axis a miss happens on is the short
## one. It was measured, then grown, then put back:
##
##   * Growing it to 54 (9.3-10.2 mm, the band JUMP and PARRY sit in) works
##     geometrically and then collides with a file this layer does not own.
##     `Revive.PAD_LIFT` is 74 and its own comment DERIVES that number from this pair —
##     "`TouchControls.HANDOFF_LIFT` is 30 and its pad is 34 tall, so 74 clears it" —
##     and `tools/slice_test_ghost_revive.gd:397` asserts the two stay disjoint.
##   * The three constraints are then unsatisfiable by 2 px: height >= 53 for the 9 mm
##     floor, lift >= 23 to clear the home-swipe strip when a phone misreports its DPI,
##     and lift + height <= 74 for the revive pad. 23 + 53 = 76.
##   * THE FIX IS TWO LINES IN ANOTHER FILE — `Revive.PAD_LIFT` 74 -> 96 and
##     `Revive.PAD_SIZE.y` 34 -> 54, which that pad needs for the same reason — and it
##     is left to whoever owns it rather than reached across for.
##
## AND IT IS THE RIGHT TARGET TO LEAVE SMALL IF ONE HAS TO BE. What a miss COSTS is the
## measure: missing DASH or JUMP mid-fight is a death; missing this is "nothing
## happened, tap it again" during a lull in which both thumbs are already free. The 9 mm
## floor is a floor for the fight, and this pad is not in the fight.
## `tools/slice_test_touch_layout.gd` carries the exemption BY NAME and still PRINTS the
## measurement every run, so it is a tracked finding and not folklore.
##
## ⚠ AND THE WIDTH IS WIDER THAN THE DEAD BAND IT CLAIMS TO LIVE IN. Measured: the
## band is 64 logical px at 16:9 and 84 at 21:9; this pad is 112. So while an offer is
## live it overhangs the bottom-centre of BOTH stick zones by ~24 px a side. Left as
## it is on purpose — it consumes its own taps, so the only cost is that a thumb landing
## on those 24 px gives a spell instead of spawning a stick, and a handoff is by
## definition a lull in which neither thumb is committed. Narrowing it instead would
## put "GIVE METEOR STORM" into 64 px, which is not a legible label at 11 pt.
## Short axis raised 34 -> 54 so it clears the 9 mm thumb floor; see `Revive.PAD_SIZE`
## for why this and the revive pad could only be fixed together.
const HANDOFF_SIZE: Vector2 = Vector2(112.0, 54.0)
## Clear air the pad keeps between itself and the nearest thumb button, and the width
## below which "GIVE METEOR STORM" stops being legible at HANDOFF_FONT_SIZE.
##
## ⚠ THESE EXIST BECAUSE A CENTRE-ANCHORED PAD AND A CORNER-ANCHORED ARC MOVE APART.
## The pad used to be pinned to the screen's midpoint, which is only the midpoint
## BETWEEN THE THUMBS at 640x360 with no cutout. The moment `_refresh_insets` pulled
## the arc 22 px inboard on a 16:9 phone with a notch, spell button 1's hit box and
## this pad's overlapped by 13x52 logical px — a tap meant to cast that would sometimes
## give the spell away instead. `_place_all()` now centres it in the MEASURED gap
## between the two clusters rather than on the screen, which is what "the centre dead
## band" was always trying to mean.
const HANDOFF_GAP_MARGIN: float = 8.0
const HANDOFF_MIN_WIDTH: float = 84.0
## Up from the bottom edge, well inboard of both thumbs.
##
## ⚠ 30 CLEARS THE ANDROID HOME-SWIPE STRIP ON ITS OWN, and it has to, because the
## runtime inset cannot be relied on to do it for anybody: `_gesture_lift()` is derived
## from `DisplayServer.screen_get_dpi()`, and DPI is a number Android OEMs are entitled
## to report badly (0 and 72 both happen in the wild). At the tightest pitch in
## `TouchLayout.DEVICES` that strip is 22 logical px, so any BASE lift under it is a pad
## the OS can steal a drag from the moment the fallback fires. `_refresh_insets()` adds
## the measured strip on top of this where the device reports honestly; this number is
## what is left when it does not.
const HANDOFF_LIFT: float = 30.0
const HANDOFF_BG: Color = Color(0.13, 0.11, 0.06, 0.72)
const HANDOFF_RIM: Color = Color(1.0, 0.95, 0.7, 0.9)
const HANDOFF_TEXT: Color = Color(1.0, 0.97, 0.85, 0.98)
const HANDOFF_FONT_SIZE: int = 11
## The action the pad presses. Deliberately the SAME action `SpellHandoff` polls on
## the keyboard, so there is one path into the transfer and not a touch-only copy of
## it that can drift.
const HANDOFF_ACTION: String = "talk"
## ⚠ THE GROUP NAME IS A LITERAL, NOT `SpellHandoff.HANDOFF_GROUP`, and that is not
## laziness. Naming the class here would drag `SpellHandoff` — and through it
## `Juice`, `CombatVfx` and the drop economy — into this file's compile graph, and
## `tools/slice_test_touch.gd` runs under `--script`, where autoloads do not exist
## and one autoload identifier anywhere in that chain fails the WHOLE chain to
## compile. This layer already duck-types `Hero` for the same reason.
## `tools/slice_test_handoff_pad.gd` asserts the two constants still agree.
const HANDOFF_GROUP: StringName = &"spell_handoff"

## Actions each stick owns. Kept as lists so a stick can release exactly its own
## actions on lift-off without stomping the other thumb's state.
const MOVE_ACTIONS: Array[String] = ["move_left", "move_right", "move_up", "move_down"]
const AIM_ACTIONS: Array[String] = ["aim_left", "aim_right", "aim_up", "aim_down"]

var _move_stick: Stick = null
var _aim_stick: Stick = null
var _aim_home: Control = null
## Every button and its cooldown/ready overlay, in build order...
var _buttons: Array[Button] = []
var _veils: Array[SpellVeil] = []
## ...and just the spell ones, in kit-slot order.
var _spell_buttons: Array[Button] = []
var _spell_veils: Array[SpellVeil] = []
## The contextual handoff pad. Deliberately NOT a `Button` and deliberately NOT in
## `_buttons`: it carries no cooldown veil, it is not part of the thumb arcs, and it
## must not read as the persistent button set growing back — which is a rule
## `tools/slice_test_touch.gd` pins with an equality on the Button count, and which
## this pad honours in substance and not merely in letter.
var _handoff: HandoffPad = null
## Which stick the desktop-preview mouse is currently driving (null = none).
var _mouse_stick: Stick = null
## The OS-owned edges currently being honoured, as (left, top, right, bottom) in
## logical px. Recomputed whenever the viewport resizes — an Android task-switch, a
## fold, or a rotation all change it without restarting the game.
var _insets: Vector4 = Vector4.ZERO
## Every corner-anchored control plus the row that placed it, so `_place_all()` can be
## re-run idempotently from the ORIGINAL offsets. Re-applying insets to already-inset
## offsets is the obvious bug here and this is what stops it.
var _placed: Array[Dictionary] = []
## Tap-to-fire / flick-to-dash bookkeeping (see AIM_TAP_FIRES / DASH_ON_FLICK).
var _aim_press_msec: float = 0.0
var _aim_press_pos: Vector2 = Vector2.ZERO
var _tap_cast_until: float = 0.0
var _flick_dash_until: float = 0.0
var _flick_ready_msec: float = 0.0
var _last_move_vec: Vector2 = Vector2.ZERO
var _last_move_msec: float = 0.0
## Every action this layer is currently holding down, so each press/release is
## edge-guarded and just_pressed/just_released stay clean for everyone else.
var _held_actions: Dictionary = {}


## Group joined by a LIVE pad, so the desktop hotbar can stand down without either of
## them importing the other. A pad that hid itself never joins, which is what makes
## "is the pad live" a different question from "does this device have a touchscreen"
## — a touchscreen laptop being played with a keyboard must keep its hotbar.
const PAD_GROUP: StringName = &"touch_pad"


func _ready() -> void:
	layer = 70  # above the AbilityBar (60), below Conversation (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A thumb pad has no business in a recorded frame. Marked BEFORE the touchscreen
	# gate below so the mark lands whichever branch is taken — and `Cinematic.mark`
	# only ever hides, so `tools/touch_capture.gd` (which exists to photograph exactly
	# this pad, with cinematic mode off) is untouched.
	Cinematic.mark(self)
	if not (force_visible or DisplayServer.is_touchscreen_available()):
		visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return
	add_to_group(PAD_GROUP)
	_build_sticks()
	_build_buttons()
	_refresh_insets()
	# ⚠ RE-MEASURED ON EVERY RESIZE, NOT ONCE AT BOOT. On Android the safe area is not
	# a constant: it changes when the player rotates the device (the cutout swaps ends),
	# when a foldable unfolds, and when the app comes back from a task switch. A pad
	# that read it once is a pad that is correct until the first phone call.
	get_viewport().size_changed.connect(_refresh_insets)
	_adopt_heroes()


# ------------------------------------------------------------ the OS-owned edges
## What the operating system has a claim on, in logical px, as (l, t, r, b).
##
## ⚠ NOTHING IN THIS PROJECT READ THIS BEFORE. Not one `get_display_safe_area()` call
## anywhere in `scripts/` or `tools/`. Two separate claims are being honoured and they
## come from different places, which is the part that makes it easy to get wrong:
##
##   * THE DISPLAY CUTOUT / SAFE AREA — `DisplayServer.get_display_safe_area()`. In
##     LANDSCAPE the notch eats a vertical strip off one END of the long axis (Godot's
##     Android manifest asks for `shortEdges`), and WHICH end depends on which way the
##     player turned the phone. So this can only ever be read, never assumed.
##   * THE SYSTEM GESTURE STRIP — which the safe area does NOT report, because this
##     game ships `screen/immersive_mode=true`: the nav bar is hidden, the safe area
##     therefore grows to the full screen, and the swipe-up-from-the-bottom gesture
##     keeps working regardless. Derived from real DPI instead, at Android's documented
##     24 dp.
##
## Measured, not modelled: `tools/probe_touch_layout.gd` found DASH sitting inside that
## strip on all four aspects it swept, which on a device is a panic button that
## sometimes throws you to the home screen.
func _refresh_insets() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ins: Vector4 = Vector4.ZERO
	if DisplayServer.is_touchscreen_available():
		ins = TouchLayout.safe_insets(vp)
		ins.w = maxf(ins.w, _gesture_lift(vp))
	elif force_visible:
		# A desktop has no cutout and no gesture bar, so a preview that invented one
		# would be lying. `preview_insets` lets the maker paste the numbers the probe
		# printed for a specific phone and see that layout instead.
		ins = preview_insets
	_insets = ins
	_place_all()


## The bottom strip Android reserves for the home-swipe, in logical px.
##
## ⚠ COMPUTED FROM REAL DPI, NOT FROM A PIXEL COUNT. 24 dp is 3.81 mm on every device
## by definition, and millimetres are the only unit that survives the trip through
## `canvas_items` stretch — the same 24 logical px is a different physical strip on
## every phone in the table. Clamped because `screen_get_dpi()` is allowed to lie (it
## returns 72 on some desktops and 0 on a headless server) and a wrong answer here
## shoves the whole thumb cluster up the screen.
func _gesture_lift(vp: Vector2) -> float:
	var dpi: float = float(DisplayServer.screen_get_dpi())
	var win: Vector2i = DisplayServer.window_get_size()
	if dpi <= 1.0 or win.y <= 0 or vp.y <= 0.0:
		return 0.0
	var device_px: float = TouchLayout.GESTURE_STRIP_MM / TouchLayout.MM_PER_INCH * dpi
	return clampf(device_px * (vp.y / float(win.y)), 0.0, 40.0)


## Re-place every corner-anchored control from its ORIGINAL offset plus the current
## insets. Idempotent by construction: it always starts from `row.off`, never from
## where the control currently is.
func _place_all() -> void:
	for p: Dictionary in _placed:
		var c: Control = p["ctrl"]
		if not is_instance_valid(c):
			continue
		var off: Vector2 = p["off"]
		var size: float = float(p["size"])
		c.offset_top = -(off.y + _insets.w) - size
		c.offset_bottom = -(off.y + _insets.w)
		if String(p["corner"]) == "br":
			c.offset_left = -(off.x + _insets.z) - size
			c.offset_right = -(off.x + _insets.z)
		else:
			c.offset_left = off.x + _insets.x
			c.offset_right = off.x + _insets.x + size
	if _handoff != null:
		_handoff.offset_top = -(HANDOFF_LIFT + _insets.w) - HANDOFF_SIZE.y
		_handoff.offset_bottom = -(HANDOFF_LIFT + _insets.w)
		_place_handoff()
	if _aim_home != null:
		var half: float = AIM_RADIUS * 0.75
		_aim_home.offset_left = -(AIM_HOME_OFFSET.x + _insets.z) - half
		_aim_home.offset_right = -(AIM_HOME_OFFSET.x + _insets.z) + half
		_aim_home.offset_top = -(AIM_HOME_OFFSET.y + _insets.w) - half
		_aim_home.offset_bottom = -(AIM_HOME_OFFSET.y + _insets.w) + half


## Centre the contextual handoff pad in the MEASURED gap between the two thumb
## clusters, not on the screen's midpoint. See HANDOFF_GAP_MARGIN for the overlap this
## exists to kill.
##
## Both edges of the gap are read off the placement table rather than recomputed, so
## this cannot drift from where the buttons actually went — including after a rotation
## swaps which end of the phone the cutout is on.
func _place_handoff() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var left_edge: float = _insets.x
	var right_edge: float = vp.x - _insets.z
	for p: Dictionary in _placed:
		var c: Control = p["ctrl"]
		if not is_instance_valid(c):
			continue
		var off: Vector2 = p["off"]
		var size: float = float(p["size"])
		if String(p["corner"]) == "br":
			right_edge = minf(right_edge, vp.x - (off.x + _insets.z) - size)
		else:
			left_edge = maxf(left_edge, _insets.x + off.x + size)
	left_edge += HANDOFF_GAP_MARGIN
	right_edge -= HANDOFF_GAP_MARGIN
	# ⚠ THE FLOOR WINS OVER THE GAP, deliberately. If a future arc squeezes the gap
	# under HANDOFF_MIN_WIDTH the pad stays legible and overlaps a button, because an
	# unreadable offer is a worse failure than a crowded one — and the geometry suite
	# fails on the overlap, which is how anyone finds out.
	var w: float = maxf(HANDOFF_MIN_WIDTH, minf(HANDOFF_SIZE.x, right_edge - left_edge))
	var centre: float = (left_edge + right_edge) * 0.5
	_handoff.offset_left = centre - vp.x * 0.5 - w * 0.5
	_handoff.offset_right = centre - vp.x * 0.5 + w * 0.5


## The insets currently being honoured. Public so a test can assert the pad ACTED on a
## safe area rather than merely that a function to read one exists.
func safe_insets() -> Vector4:
	return _insets


## Tell heroes the on-screen pad is live so they read the aim STICK instead of the
## mouse. On a real device Hero._touch_aim() is already true from DisplayServer, so
## this only really matters for force_visible desktop previews — which is also the
## only case where a hero can spawn after us, hence the re-adopt in _process.
func _adopt_heroes() -> void:
	for h: Node in get_tree().get_nodes_in_group("hero"):
		h.set("touch_input", true)


# ------------------------------------------------------------------------ sticks
func _build_sticks() -> void:
	_move_stick = _make_stick(JOY_RADIUS, Color(0.85, 0.9, 1.0, PAD_ALPHA * 0.7))
	# Warm tint so the two sticks are never confused at a glance mid-fight.
	_aim_stick = _make_stick(AIM_RADIUS, Color(1.0, 0.86, 0.68, PAD_ALPHA * 0.7))
	# Dim always-on ring showing where the aim thumb wants to live. Anchored to the
	# bottom-right corner so it scales with the window like everything else here.
	_aim_home = _circle(AIM_RADIUS * 1.5, Color(1.0, 0.86, 0.68, PAD_ALPHA * 0.35))
	_aim_home.anchor_left = 1.0
	_aim_home.anchor_right = 1.0
	_aim_home.anchor_top = 1.0
	_aim_home.anchor_bottom = 1.0
	var half: float = AIM_RADIUS * 0.75
	_aim_home.offset_left = -AIM_HOME_OFFSET.x - half
	_aim_home.offset_right = -AIM_HOME_OFFSET.x + half
	_aim_home.offset_top = -AIM_HOME_OFFSET.y - half
	_aim_home.offset_bottom = -AIM_HOME_OFFSET.y + half
	add_child(_aim_home)


func _make_stick(radius: float, tint: Color) -> Stick:
	var s := Stick.new()
	s.radius = radius
	s.base = _circle(radius * 2.0, tint)
	s.base.visible = false
	add_child(s.base)
	s.knob = _circle(radius * 0.9, Color(tint.r + 0.1, tint.g + 0.07, tint.b + 0.05, PAD_ALPHA + 0.15))
	s.knob.visible = false
	add_child(s.knob)
	return s


## Both sticks are read live from raw touches, not from Controls: buttons consume
## their own taps in _gui_input first, so a tap on CAST never reaches here and never
## spawns a stick underneath it. Fingers are tracked by index so the two thumbs are
## genuinely independent (the whole point of twin-stick).
func _unhandled_input(event: InputEvent) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var took: Stick = _try_start(t.index, t.position, vp)
			if took == _aim_stick and took != null:
				_arm_tap(t.position)
		else:
			if _move_stick.index == t.index:
				_stop_move()
			if _aim_stick.index == t.index:
				var was: Vector2 = _aim_stick.cur
				_stop_aim()
				_maybe_tap_fire(was)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _move_stick.active and _move_stick.index == d.index:
			_move_stick.cur = d.position
		elif _aim_stick.active and _aim_stick.index == d.index:
			_aim_stick.cur = d.position
	# Desktop preview: drive whichever stick the click landed in with the mouse. One
	# mouse can only hold one stick at a time, which is exactly why the preview can
	# never fully stand in for a device playtest.
	elif event is InputEventMouseButton and force_visible:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_stick = _try_start(-1, mb.position, vp)
				if _mouse_stick == _aim_stick and _mouse_stick != null:
					_arm_tap(mb.position)
			elif _mouse_stick != null:
				if _mouse_stick == _move_stick:
					_stop_move()
				else:
					var was: Vector2 = _aim_stick.cur
					_stop_aim()
					_maybe_tap_fire(was)
				_mouse_stick = null
	elif event is InputEventMouseMotion and _mouse_stick != null:
		_mouse_stick.cur = (event as InputEventMouseMotion).position


## Route a fresh press to the stick whose zone it landed in. Returns the stick that
## took it, or null (centre dead band, or that thumb is already down).
func _try_start(index: int, pos: Vector2, vp: Vector2) -> Stick:
	if pos.x < vp.x * LEFT_ZONE_FRAC:
		if not _move_stick.active:
			_move_stick.start(index, pos)
			return _move_stick
	elif pos.x > vp.x * RIGHT_ZONE_FRAC:
		if not _aim_stick.active:
			_aim_stick.start(index, pos)
			return _aim_stick
	return null


func _stop_move() -> void:
	_move_stick.stop()
	_release(MOVE_ACTIONS)


func _stop_aim() -> void:
	_aim_stick.stop()
	_release(AIM_ACTIONS)
	# Lifting the aim thumb must stop the gun, but must NOT reset the aim: Hero holds
	# the last direction below its deadzone precisely so this lift is free.
	_release(["cast"])


func _process(_delta: float) -> void:
	# Desktop preview only: a hero spawned after us still needs adopting. On a device
	# DisplayServer already answers this, so this costs nothing where it matters.
	if force_visible:
		_adopt_heroes()
	_sync_buttons()
	if _move_stick.active:
		_move_stick.sync_knob()
		var mv: Vector2 = _move_stick.vector()
		_watch_for_flick(mv)
		publish_move(mv)
	else:
		_last_move_msec = 0.0
	if _aim_stick.active:
		_aim_stick.sync_knob()
		publish_aim(_aim_stick.vector())
	_expire_pulses()


# ---------------------------------------------------- tap to fire, flick to dash
## A press landed on the aim stick: remember when and where, so the lift can tell a tap
## from a steer.
func _arm_tap(pos: Vector2) -> void:
	_aim_press_msec = float(Time.get_ticks_msec())
	_aim_press_pos = pos


## The aim thumb lifted. If it was quick and it barely moved, fire ONE shot along the
## aim the player is already holding.
##
## ⚠ `_stop_aim()` HAS ALREADY RELEASED `cast` BY THE TIME THIS RUNS, and that ordering
## is deliberate rather than incidental: the tap press must land on a clean edge, or a
## thumb that grazed past AIM_FIRE_THRESHOLD on its way out would leave `cast` held and
## the tap would be a no-op that looks like a dead button.
##
## The direction is NOT computed here and that is the whole point — `Hero` holds its
## last `_aim_dir` below `TOUCH_AIM_DEADZONE`, so the shot goes exactly where the player
## last pointed. Nothing is snapped to a target. See AIM_TAP_FIRES for why that
## distinction is the one that keeps this off the maker's no-auto-aim ruling.
func _maybe_tap_fire(released_at: Vector2) -> void:
	if not AIM_TAP_FIRES or _aim_press_msec <= 0.0:
		return
	var held: float = float(Time.get_ticks_msec()) - _aim_press_msec
	_aim_press_msec = 0.0
	if not is_tap(held, released_at.distance_to(_aim_press_pos)):
		return
	_set_move("cast", 1.0, true)
	_tap_cast_until = float(Time.get_ticks_msec()) + AIM_TAP_HOLD_MSEC


## Snap the move stick and you dash. Watches the stick's own SPEED rather than its
## position, because "how fast did the thumb move" is the thing that separates a dash
## from a walk — a slow push to full deflection is a run, the same push in 40 ms is a
## dash.
##
## ⚠ AND IT IS GATED ON DEFLECTION TOO, not on speed alone. A resting thumb jitters,
## and jitter near the centre can clear any speed threshold you like over one frame;
## requiring FLICK_MIN_DEFLECTION as well is what makes "a resting stick dashes nobody"
## true rather than merely likely. `tools/slice_test_touch_layout.gd` pins it.
func _watch_for_flick(v: Vector2) -> void:
	var now: float = float(Time.get_ticks_msec())
	if not DASH_ON_FLICK:
		_last_move_vec = v
		_last_move_msec = now
		return
	if _last_move_msec > 0.0 and now >= _flick_ready_msec 			and is_flick(_last_move_vec, v, (now - _last_move_msec) / 1000.0):
		_set_move("dash", 1.0, true)
		_flick_dash_until = now + FLICK_HOLD_MSEC
		_flick_ready_msec = now + FLICK_COOLDOWN_MSEC
	_last_move_vec = v
	_last_move_msec = now


## Did the stick SNAP? Pure, static and public for the same reason `publish_move` was
## split out of `_process`: the decision is the only part of a gesture that can be
## judged without a device, so it lives somewhere a headless suite can call it with
## made-up numbers instead of having to fake the passage of time.
static func is_flick(prev: Vector2, cur: Vector2, dt_sec: float) -> bool:
	if dt_sec <= 0.0:
		return false
	if cur.length() < FLICK_MIN_DEFLECTION:
		return false
	return (cur - prev).length() / dt_sec >= FLICK_SPEED


## Was that press a TAP rather than a steer? Same reasoning as `is_flick`.
static func is_tap(held_msec: float, travel_px: float) -> bool:
	return held_msec <= AIM_TAP_MSEC and travel_px <= AIM_TAP_SLOP


## Drop the one-shot holds once their window is up. Both are TIMED rather than
## single-frame because `Hero` samples input in `_physics_process`: a press raised and
## dropped inside one render frame can be missed entirely at a high frame rate, which
## on a device reads as "the tap only works sometimes".
func _expire_pulses() -> void:
	var now: float = float(Time.get_ticks_msec())
	if _tap_cast_until > 0.0 and now >= _tap_cast_until:
		_tap_cast_until = 0.0
		if not (_aim_stick.active and AIM_STICK_FIRES \
				and _aim_stick.vector().length() >= AIM_FIRE_THRESHOLD):
			_release(["cast"])
	if _flick_dash_until > 0.0 and now >= _flick_dash_until:
		_flick_dash_until = 0.0
		_release(["dash"])


## Publish a move-stick vector (components in -1..1) onto the named move actions.
## Split out from _process so the input MATHS — the only part of a touch layer that
## can be judged without a device — is directly testable headlessly.
func publish_move(v: Vector2) -> void:
	_set_move("move_right", v.x, v.x > JOY_DEADZONE)
	_set_move("move_left", -v.x, v.x < -JOY_DEADZONE)
	# UP was simply missing before, which quietly broke more than aim: Hero._start_dash
	# reads get_vector(... "move_up" ...), so a touch dash could never go up-left or
	# up-right either. Publishing it fixes the dash and any future up-consumer for free.
	_set_move("move_up", -v.y, v.y < -JOY_DEADZONE)
	# Push down -> duck (hold move_down, the ragdoll flop). Deliberately a much higher
	# threshold than walking: you should have to MEAN it, since ducking suspends
	# abilities. No longer doubles as "aim at the floor" — that is the aim stick's job.
	_set_move("move_down", 1.0, v.y > JOY_DUCK_THRESHOLD)
	if LEFT_STICK_UP_JUMPS:
		_set_move("jump", 1.0, v.y < -JOY_UP_JUMP_THRESHOLD)


## Publish an aim-stick vector (components in -1..1) onto the named aim actions, and
## hold `cast` once it is pushed far enough to count as firing.
##
## NOTE there is no deadzone here on purpose. A per-AXIS deadzone would carve dead
## sectors: aiming 5 degrees above horizontal would zero the tiny vertical component
## and snap the shot flat — the exact "can't aim where I'm pointing" bug this task
## exists to kill. Both components go out at full analog value and the single
## magnitude deadzone lives in ONE place, Hero.TOUCH_AIM_DEADZONE, which is also what
## implements hold-the-last-aim when the thumb is lifted. One owner, no drift.
func publish_aim(v: Vector2) -> void:
	_set_move("aim_right", v.x, v.x > 0.0)
	_set_move("aim_left", -v.x, v.x < 0.0)
	_set_move("aim_up", -v.y, v.y < 0.0)
	_set_move("aim_down", v.y, v.y > 0.0)
	if AIM_STICK_FIRES:
		_set_move("cast", 1.0, v.length() >= AIM_FIRE_THRESHOLD)


## Press/release an action with analog strength, edge-guarded so we only touch the
## input on each transition (keeps just_pressed/released clean for other systems).
## Re-pressing while already held is harmless and self-healing: if the CAST button and
## the firing aim stick disagree for a frame, the next frame settles it.
func _set_move(action: String, strength: float, on: bool) -> void:
	if on:
		Input.action_press(action, clampf(absf(strength), 0.0, 1.0))
		_held_actions[action] = true
	elif _held_actions.get(action, false):
		Input.action_release(action)
		_held_actions[action] = false


## Release just these actions — per-stick, so lifting the move thumb cannot silently
## drop the aim thumb's state (they are independent fingers).
func _release(actions: Array) -> void:
	for a: String in actions:
		if _held_actions.get(a, false):
			Input.action_release(a)
			_held_actions[a] = false


# ---------------------------------------------------------------- the buttons
## THE WHOLE LAYOUT, as data. One row per button so adding, removing or moving one is
## a single edit — the previous version spread eight hand-placed call sites across the
## file and there was no way to see the layout without simulating it in your head.
##
## Positions are in the project's 640x360 base space (canvas_items stretch) and
## CORNER-ANCHORED, so they stick to the thumbs at any resolution. `off` = (distance
## from that side, distance UP from the bottom).
func _button_layout() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		# JUMP presses "jump", NOT "move_up": Hero polls the "jump" action, so pressing
		# move_up made the touch jump button silently do nothing at all on a device.
		{"label": "JUMP", "action": "jump", "corner": "br",
			"off": JUMP_BTN_OFFSET, "size": JUMP_BTN_SIZE},
		{"label": "DASH", "action": "dash", "corner": "br",
			"off": DASH_BTN_OFFSET, "size": DASH_BTN_SIZE},
	]
	if PARRY_ON_TOUCH:
		rows.append({"label": "PARRY", "action": "parry", "corner": "bl",
			"off": PARRY_BTN_OFFSET, "size": PARRY_BTN_SIZE})
	for i: int in mini(SPELL_BUTTONS_SHOWN, SPELL_ARC_ANGLES.size()):
		rows.append({
			"label": str(i + 1), "action": "spell_%d" % (i + 1), "corner": "br",
			"off": spell_button_offset(i), "size": SPELL_BTN_SIZE, "spell_slot": i,
		})
	return rows


## Where spell button `i` sits, as (from the right edge, up from the bottom). Static +
## public so the geometry test can check the arc for overlapping hit boxes without
## building a pad — the maths IS the layout, and it is the only part of a touch layer
## that can be judged without a device.
## ⚠ FORWARDS TO `TouchLayout.arc_offset` RATHER THAN RE-DOING THE TRIG. The maths
## moved so the probe and the geometry suite can sweep an arc without building a pad;
## this name stays because `tools/slice_test_spell_buttons.gd` already calls it and a
## rename would be a change to a file this layer does not own.
static func spell_button_offset(i: int) -> Vector2:
	return TouchLayout.arc_offset(THUMB_PIVOT, SPELL_ARC_RADIUS, SPELL_ARC_ANGLES, i)


func _build_buttons() -> void:
	for row: Dictionary in _button_layout():
		_add_button(row)
	_build_handoff_pad()


## Built once, hidden, and shown only while `SpellHandoff.can_hand_over()` is true.
## Built up front rather than instanced on demand because allocating a Control the
## first frame a teammate walks into range is a hitch at exactly the moment the
## player is being asked to react.
func _build_handoff_pad() -> void:
	_handoff = HandoffPad.new()
	_handoff.visible = false
	# Bottom-CENTRE: anchored to the middle of the screen so it lands in the dead band
	# at every resolution, rather than at a pixel that is central only at 640x360.
	_handoff.anchor_left = 0.5
	_handoff.anchor_right = 0.5
	_handoff.anchor_top = 1.0
	_handoff.anchor_bottom = 1.0
	_handoff.offset_left = -HANDOFF_SIZE.x * 0.5
	_handoff.offset_right = HANDOFF_SIZE.x * 0.5
	_handoff.offset_top = -HANDOFF_LIFT - HANDOFF_SIZE.y
	_handoff.offset_bottom = -HANDOFF_LIFT
	# STOP, not PASS: the pad eats its own tap so a near-miss on the narrow dead band
	# cannot also spawn a thumb stick under the finger that just gave a spell away.
	_handoff.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_handoff)


## The live `SpellHandoff` for this floor, or null. Found by group so neither file
## imports the other and a floor without the drop economy simply has no pad.
func _handoff_node() -> Node:
	return get_tree().get_first_node_in_group(HANDOFF_GROUP)


## Show/hide + relabel the contextual pad from the SAME state the in-world prompt is
## drawn from, so the two can never disagree about whether an offer exists.
func _sync_handoff() -> void:
	if _handoff == null:
		return
	var node: Node = _handoff_node()
	var live: bool = node != null and node.has_method(&"can_hand_over") \
		and bool(node.call(&"can_hand_over"))
	if not live:
		if _handoff.visible:
			_handoff.release()   # hidden mid-press must not leave `talk` held down
			_handoff.visible = false
		return
	_handoff.label = String(node.call(&"offer_label")) if node.has_method(&"offer_label") else ""
	_handoff.visible = true


## Is the contextual handoff pad on screen right now, and what is it offering?
## Public so a test can assert the affordance without reading a member that a
## refactor could rename out from under it.
func handoff_visible() -> bool:
	return _handoff != null and _handoff.visible


func handoff_label() -> String:
	return "" if _handoff == null else _handoff.label


## Repaint every readout now instead of on the next frame. Public so a headless test
## can pump the pad deterministically — `_process` is the only other caller.
func refresh() -> void:
	_sync_buttons()


## What the spell pad for kit slot `nth` is currently DRAWING as its charge count:
## a remaining Tier 3 count, or -1 for "no pips". Public so a test can assert the
## readout the player sees rather than re-deriving it from the ledger and proving
## only that the ledger agrees with itself.
func spell_pad_charges(nth: int) -> int:
	if nth < 0 or nth >= _spell_veils.size():
		return -1
	return _spell_veils[nth].charges


func _add_button(row: Dictionary) -> void:
	var label: String = String(row["label"])
	var action: String = String(row["action"])
	var size: float = float(row["size"])
	var off: Vector2 = row["off"]
	var b := Button.new()
	b.text = label
	# The action this button drives, readable from outside so a test can assert the
	# wiring rather than just counting buttons.
	b.set_meta("action", action)
	if row.has("spell_slot"):
		b.set_meta("spell_slot", int(row["spell_slot"]))
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16 if row.has("spell_slot") else 12)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	b.add_theme_constant_override("outline_size", 3)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		# PRESS STATE. The press has to be visible on a screen your own thumb is
		# covering, so it brightens AND lifts its rim rather than only changing alpha.
		var down: bool = state == "pressed"
		sb.bg_color = Color(0.2, 0.24, 0.34, PAD_ALPHA + (0.3 if down else 0.0))
		sb.set_corner_radius_all(int(size * 0.5))
		sb.border_color = Color(0.9, 0.96, 1.0, 0.85) if down else Color(0.8, 0.88, 1.0, 0.5)
		sb.set_border_width_all(3 if down else 2)
		b.add_theme_stylebox_override(state, sb)
	# Anchor to the chosen bottom corner; the pixel offsets themselves are applied by
	# `_place_all()`, which folds in the OS-owned insets and can be re-run on a resize.
	# ⚠ THE ANCHORS ARE STILL SET HERE and the offsets are still given a sane value,
	# because a control that spends one frame at (0,0) before the first `_place_all`
	# is a control that flashes in the top-left corner on boot.
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	if String(row["corner"]) == "br":
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_left = -off.x - size
		b.offset_right = -off.x
	else:  # bottom-left
		b.offset_left = off.x
		b.offset_right = off.x + size
	b.offset_top = -off.y - size
	b.offset_bottom = -off.y
	_placed.append({"ctrl": b, "off": off, "size": size, "corner": String(row["corner"])})
	# Hold-to-repeat where the verb repeats (a held spell button re-fires the moment
	# its slot recovers — Hero._update_input_buffer), a tap for the one-shots. Both are
	# the same press/release pair; the difference lives in the consumer, not here.
	b.button_down.connect(func() -> void: Input.action_press(action))
	b.button_up.connect(func() -> void: Input.action_release(action))
	add_child(b)
	# EVERY button gets a veil, not just the spell ones. DASH and PARRY are cooldown
	# verbs too, and on a phone this pad is the ONLY cooldown readout there is — the
	# desktop hotbar stands down when the pad is live (see `AbilityBar`), because its
	# slots sit directly under the thumb cluster. That was nine squares before the
	# six-thing ruling and is six now; the collision is the same either way.
	var veil := SpellVeil.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(veil)
	_buttons.append(b)
	_veils.append(veil)
	if row.has("spell_slot"):
		_spell_buttons.append(b)
		_spell_veils.append(veil)


## Repaint every button from the hero's own state: the cooldown wipe, the ready rim
## and the just-came-back flash. Polled rather than pushed, the `AbilityBar` idiom —
## the numbers tick every frame anyway, and a HUD that subscribes to six signals is a
## HUD that can miss one.
##
## `Hero.spell_button_state` / `Hero.touch_button_state` are the single publishers, so
## this pad, the hotbar and the loadout bar cannot disagree about whether a button is
## ready — and neither of them depends on a slot's POSITION in some other array.
func _sync_buttons() -> void:
	_sync_handoff()
	if _buttons.is_empty():
		return
	var hero: Node = get_tree().get_first_node_in_group("hero")
	var live: bool = hero != null and hero.has_method("spell_button_state")
	for i: int in _buttons.size():
		var btn: Button = _buttons[i]
		var veil: SpellVeil = _veils[i]
		if not live:
			# No hero this scene (a hub, a menu): draw the buttons plain rather than
			# faking a ready state nobody can act on.
			veil.frac = 0.0
			veil.flash = 0.0
			veil.slot_ready = true
			veil.charges = -1
			veil.queue_redraw()
			continue
		var st: Dictionary
		if btn.has_meta("spell_slot"):
			var nth: int = int(btn.get_meta("spell_slot"))
			st = hero.call("spell_button_state", nth)
			# The number stays the button's label (a thumb finds a shape, not a word),
			# but the SPELL's name rides the tooltip so a desktop preview can read it.
			btn.tooltip_text = String(st.get("name", ""))
			btn.disabled = not bool(st.get("filled", true))
			# HOW MANY LEFT. Only a granted drop answers >= 0; a class spell reports
			# -1 and draws nothing, which is what keeps the count meaningful.
			veil.charges = SpellGrant.charges_in_slot(hero, nth)
		else:
			veil.charges = -1
			st = hero.call("touch_button_state", StringName(String(btn.get_meta("action", ""))))
		var total: float = float(st.get("total", 0.0))
		veil.frac = 0.0 if total <= 0.0 else clampf(float(st.get("remaining", 0.0)) / total, 0.0, 1.0)
		veil.flash = float(st.get("pulse", 0.0))
		veil.slot_ready = bool(st.get("ready", true))
		veil.queue_redraw()


## The cooldown wipe + ready flare drawn over one spell button. An inner Control
## because a Button cannot draw over its own StyleBox, and a shader would be a whole
## dependency for two rectangles.
class SpellVeil extends Control:
	var frac: float = 0.0    # 1 = just cast, 0 = fully recovered
	var flash: float = 0.0   # 1 -> 0 across the ready-flash
	var slot_ready: bool = true
	## Remaining Tier 3 charges, or -1 for "not a granted drop, draw nothing".
	var charges: int = -1

	func _draw() -> void:
		var r: float = size.x * 0.5
		var c: Vector2 = size * 0.5
		if frac > 0.0:
			# Bottom-anchored wipe that shrinks as the slot fills back up — the same
			# direction the hotbar sweeps, so the two read as one system.
			var h: float = size.y * frac
			draw_rect(Rect2(Vector2(0.0, size.y - h), Vector2(size.x, h)),
				TouchControls.CD_VEIL_COLOR)
		draw_arc(c, r - 2.0, 0.0, TAU, 28,
			TouchControls.RIM_READY if slot_ready else TouchControls.RIM_COOLING, 2.0, true)
		if flash > 0.0:
			# A rim that flares OUTWARD and fades: motion, which the eye catches in
			# peripheral vision while it is busy watching the fight.
			var grow: float = (1.0 - flash) * 7.0
			var f: Color = TouchControls.READY_FLASH_COLOR
			draw_arc(c, r + grow, 0.0, TAU, 28, Color(f.r, f.g, f.b, flash), 2.5, true)
		_draw_charges()

	## HOW MANY USES ARE LEFT, drawn LAST so the cooldown wipe cannot hide it — "one
	## charge left" is exactly the fact you need while the button is still recovering
	## and you are deciding whether to spend it here or save it for the guardian.
	##
	## Inside the rim, along the TOP of the round pad, where the wipe (which fills from
	## the bottom) reaches last. Bigger and further apart than the desktop bars': this
	## is a 60 px circle being read at arm's length with a thumb near it.
	func _draw_charges() -> void:
		if charges < 0:
			return
		if charges > TouchControls.PIP_MAX_DOTS:
			var font: Font = ThemeDB.fallback_font
			if font != null:
				draw_string(font, Vector2(size.x - 22.0, 16.0), "x%d" % charges,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, TouchControls.PIP_COLOR)
			return
		# Centred as a row so 1 and 2 charges both read as a deliberate count rather
		# than as a smudge drifting in from one corner.
		var span: float = float(charges - 1) * TouchControls.PIP_GAP
		var y: float = TouchControls.PIP_INSET.y
		for i: int in charges:
			draw_circle(Vector2(size.x * 0.5 - span * 0.5 + float(i) * TouchControls.PIP_GAP, y),
				TouchControls.PIP_RADIUS, TouchControls.PIP_COLOR, true, -1.0, true)


## THE CONTEXTUAL HANDOFF PAD — "give Meteor Storm", in the centre dead band, and
## only while there is something to give. See the HANDOFF_* constants for why this is
## contextual and centred rather than a seventh thumb button.
##
## It presses the same `talk` action the keyboard handoff uses rather than calling
## `SpellHandoff.try_local_handoff()` directly. That is the point: one input path, so
## a change to when a handoff is legal cannot land on the keyboard and miss the phone.
## The press is edge-guarded and released on hide, because a pad that vanishes
## mid-press (the teammate walked away) must not leave `talk` held forever.
class HandoffPad extends Control:
	var label: String = ""
	var _held: bool = false
	var _phase: float = 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_phase += delta
		if visible:
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var pressed: bool = false
		var is_press_event: bool = false
		if event is InputEventScreenTouch:
			is_press_event = true
			pressed = (event as InputEventScreenTouch).pressed
		elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			is_press_event = true
			pressed = (event as InputEventMouseButton).pressed
		if not is_press_event:
			return
		accept_event()   # consumed here so no thumb stick spawns under the tap
		if pressed:
			press()
		else:
			release()

	## Public so a headless test can drive the affordance the way a thumb does,
	## through the real action, rather than by calling the transfer directly.
	func press() -> void:
		if _held:
			return
		_held = true
		Input.action_press(HANDOFF_ACTION)

	func release() -> void:
		if not _held:
			return
		_held = false
		Input.action_release(HANDOFF_ACTION)

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		# Pulses in step with SpellHandoff's in-world prompt (same 4.0 rate), so the
		# thing above your teammate's head and the thing under your thumb breathe
		# together and read as one offer rather than two notifications.
		var pulse: float = 0.5 + 0.5 * sin(_phase * 4.0)
		draw_rect(box, TouchControls.HANDOFF_BG, true)
		draw_rect(box, Color(TouchControls.HANDOFF_RIM.r, TouchControls.HANDOFF_RIM.g,
			TouchControls.HANDOFF_RIM.b, 0.45 + 0.45 * pulse), false, 2.0 if _held else 1.5)
		var font: Font = ThemeDB.fallback_font
		if font == null:
			return
		# The SPELL'S NAME, not "handoff": what you are about to lose is the decision,
		# and a generic verb would make the betrayal thoughtless instead of chosen.
		var text: String = "GIVE" if label == "" else "GIVE %s" % label.to_upper()
		draw_string(font, Vector2(0.0, size.y * 0.5 + float(TouchControls.HANDOFF_FONT_SIZE) * 0.38),
			text, HORIZONTAL_ALIGNMENT_CENTER, size.x, TouchControls.HANDOFF_FONT_SIZE,
			TouchControls.HANDOFF_TEXT)


## A round translucent Control (a stick base/knob, or the aim home ring), drawn via a
## circular stylebox.
func _circle(diameter: float, color: Color) -> Control:
	var c := Panel.new()
	c.custom_minimum_size = Vector2(diameter, diameter)
	c.size = Vector2(diameter, diameter)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter * 0.5))
	sb.border_color = Color(color.r, color.g, color.b, minf(color.a + 0.2, 1.0))
	sb.set_border_width_all(2)
	c.add_theme_stylebox_override("panel", sb)
	return c


## One floating thumb stick: where it was pressed, where the finger is now, and the
## two Controls that draw it. Both sticks are the same object so the aim stick cannot
## quietly drift out of sync with the move stick's behaviour.
class Stick extends RefCounted:
	var active: bool = false
	var index: int = -99          # touch finger index (-1 = desktop mouse preview)
	var origin: Vector2 = Vector2.ZERO
	var cur: Vector2 = Vector2.ZERO
	var radius: float = 66.0
	var base: Control = null
	var knob: Control = null

	## Floating/relative, NOT fixed: the stick materialises under wherever the thumb
	## lands in its zone. On a phone you cannot see your own thumb, and a fixed stick
	## means constantly re-finding it by feel; a floating one is always exactly where
	## you put your thumb. Cost is that the on-screen art moves around, which is why
	## the aim side also gets a static home ring as a visual anchor.
	func start(idx: int, pos: Vector2) -> void:
		active = true
		index = idx
		origin = pos
		cur = pos
		base.position = pos - base.size * 0.5
		base.visible = true
		knob.visible = true

	func stop() -> void:
		active = false
		index = -99
		base.visible = false
		knob.visible = false

	## Finger offset from the origin, clamped to the ring and normalised to -1..1.
	## Full 360 by construction — nothing here quantises to an axis or a sector.
	func vector() -> Vector2:
		if not active:
			return Vector2.ZERO
		var v: Vector2 = cur - origin
		if v.length() > radius:
			v = v.normalized() * radius
		return v / radius

	func sync_knob() -> void:
		knob.position = origin + vector() * radius - knob.size * 0.5
