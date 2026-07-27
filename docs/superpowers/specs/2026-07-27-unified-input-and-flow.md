# Unified input model + the flow problem — mobile and desktop, one scheme

**Date:** 2026-07-27
**Branch:** `stickman-integrate`
**Status:** design (READ-ONLY recon) → awaiting maker review → plan → build
**Scope:** how the EXISTING verbs (move, jump, dash, use, deflect, select-slot) are controlled on a phone and on a desktop, and every place the current design fights "flow like Stick Fight".
**Companion:** `docs/superpowers/specs/2026-07-27-mobile-casting-ux.md` — that spec decides WHICH spells you carry (a capped, typed 4). This spec decides HOW you hold and use them. Where they disagree, §6 reconciles them explicitly.

---

## 0. TL;DR

- **The drag thesis HOLDS, and it is stronger than stated.** Blade damage is a function of *aim velocity* (`SpikeFigure._process_blade` scales damage by `_blade_speed` against `BLADE_REF_SPEED`, and refuses to damage below `BLADE_MIN_SPEED`). A thumb drag and a mouse drag are not merely analogous — they are the only two input devices that natively produce the quantity the mechanic reads. A stick-plus-fire-button *cannot* express it. **Verdict: fuse aim and use into one right-thumb zone.**
- **It holds for casting as ONE ZONE, not as one gesture.** Same zone, three grammars chosen by what is in your hand: fists = tap, weapon = hold-and-drag (no commit moment), spell = drag-to-aim, release-to-cast. This is exactly the seam `HandSlots.primary_action()` already models; it needs one new accessor.
- **DEFLECT must stay a discrete button.** 0.16 s window, zero input buffer, no coyote time. Every gesture costs 60–120 ms of *recognition* latency before it is even recognised, and any right-side swipe is ambiguous against the drag — a misread makes you *swing* when you meant to *block*. Button, on the left thumb.
- **JUMP moves onto the joystick (push up).** Argued from the code, not taste: jump is the only verb in the game with BOTH an input buffer (`JUMP_BUFFER_TIME` 0.10 s) and a coyote window (`COYOTE_TIME` 0.10 s) — it is by construction the most latency-tolerant verb we have, so it gets the gesture and deflect gets the button.
- **Slot selection stays in combat**, on a bottom-centre League-style bar, **direct tap** (not scroll) on both platforms — because with the cap at 4 spells the carousel is ~6 entries and a 6-square bar fits between the thumbs, out of both thumb zones. The *loadout* (which 4) still changes only out of combat.
- **Dash gesture: judged workable but risky**, specified with a hard tap-primer that movement input physically cannot produce, plus a re-arm lockout and a kill switch. It ships with a dash button still available until F5 says otherwise.
- **Top three flow-breakers:** (1) every signature roots you for ≥0.42 s while the playground rig roots you for 0 s — two different games; (2) input is *discarded*, not buffered, during those windups; (3) holding DOWN (duck/ragdoll) silently disables your entire defensive kit.

---

## 1. Ground truth — verified on this branch

Everything below is read from the code, not assumed.

### 1.1 The verbs, and what actually drives them

| verb | desktop binding | Hero path | notes |
|---|---|---|---|
| move | A/D + arrows (`move_left`/`move_right`) | `Hero.gd:545` `Input.get_axis` | horizontal only; vertical axis is unused for movement |
| duck / ragdoll | S (`move_down`) held | `Hero.gd:492` | **returns early — see §7.3** |
| jump | W / Up (`jump`) | `Hero.gd:548,578` | buffered 0.10 s + coyote 0.10 s + variable height on release |
| dash | Space (`dash`) | buffered → `_start_dash` (`Hero.gd:1227`) | 0.14 s, 620 px/s, i-frames, `DASH_COOLDOWN` 0.9 s |
| use | LMB (`cast`), F (`melee`) | `Hero.gd:519`, buffered | two separate actions today |
| deflect | RMB (`parry`) | `Hero.gd:517` → `_try_parry_start` | `PARRY_WINDOW` **0.16 s**, `PARRY_COOLDOWN` 0.9 s, **not buffered** |
| abilities | Q/R/T/G | buffered except `ultimate` | `blast`/`blink`/`nova` buffered; `ultimate` + `parry` + `cast` polled raw |
| select | V (`cycle_signature`) | `Hero.gd:513` | cycles signatures only |

`BUFFER_TIME = 0.12 s`, and the buffer covers exactly `["melee","dash","blast","blink","nova"]` (`Hero.gd:678`). **`cast`, `parry` and `ultimate` — two of which are the highest-stakes inputs in the game — have no forgiveness at all.**

### 1.2 The two rigs disagree about commitment

| | `SpikeFigure.cast()` (playground) | `Hero._begin_summon` / `_begin_channel` |
|---|---|---|
| duration | `CastStyle.duration(pose)` = **0.18–0.46 s** | **0.42 s** summon (0.22 rush/blink), **1.0–1.3 s** channel |
| movement | **unaffected** — `_cast_timer` only re-targets the arm springs (`SpikeFigure.gd:1458`); the torso keeps its physics | **rooted** — `velocity = Vector2.ZERO`, `move_and_slide()` to hold position, `return` before all movement code (`Hero.gd:457-464`, `_process_summon`, `_process_channel`) |
| jump / dash during | yes | no |
| cancel | naturally, by moving | only by being hit, which costs MP + cooldown |

This is the single biggest finding in this document. **The thing the maker F5s and enjoys does not root; the shipped hero roots on every single signature.** "Make it flow like Stick Fight" is, mechanically, "make Hero behave like SpikeFigure, except where the drama is deliberate."

### 1.3 The drag, exactly as implemented

`SpikeFigure._update_arms`, the `dragging and i == lead` branch (line 1542):

```gdscript
target = (ctrl_aim - sh).angle()
stiff  = w["dstiff"];  damp  = w["ddamp"]
fstiff = w["fstiff"];  fdamp = w["fdamp"]
```

- The arm spring chases **the angle from the shoulder to `ctrl_aim`**. Nothing else scripts it. There is no swing animation.
- Damage (`_process_blade`) tests the **swept quad between physics frames** and scales by `_blade_speed / BLADE_REF_SPEED` (1100 px/s), refusing to fire below `BLADE_MIN_SPEED` (260 px/s). A sword resting on someone does nothing.
- `punch()` while armed sets `_punch_timer = 0` and only injects a spring impulse (`flick`) plus `_drag_hold` seconds of drag. The header says it outright (line 691): *"click and hold are the same verb, which is the whole point."*

Reach geometry: `UARM_LEN + FARM_LEN = 30 px`; a sword adds `56 × 0.86 ≈ 48 px` of steel past the fist. **Blade tip radius ≈ 78 world px from the shoulder.**

### 1.4 The rig already ranks the verbs

`_update_arms` resolves its branches in a fixed priority order:

```
punch  >  dead  >  cast  >  dash  >  parry  >  stagger  >  DRAG  >  aim-hold  >  ...
```

**Dash and parry both sit ABOVE drag.** The rig has already decided that the defensive verbs preempt the offensive one. §5 promotes this from an animation detail to the input model's organising principle.

### 1.5 `TouchControls.gd` as it now stands

`CanvasLayer` layer 70, hidden unless `DisplayServer.is_touchscreen_available()` or `force_visible`. Left 45% = a dynamic joystick (`JOY_RADIUS` 66, `JOY_DEADZONE` 0.18, `JOY_DUCK_THRESHOLD` 0.6 → `move_down`). Right = a fixed arc of buttons; the recent fix corrected JUMP from `move_up` to `jump` and added the missing `HIT` (`melee`) and `PARRY` buttons.

Current button count: **8** (JUMP, CAST, DASH, Q, G, BLINK, HIT, PARRY) plus the joystick. That is the number this spec exists to reduce.

The layer feeds `Input.action_press` / `action_release` on named actions, so it composes with `Hero` with zero combat-code change. **That seam is correct and every recommendation here preserves it.**

Two structural facts worth keeping: the joystick's **vertical axis is only half used** (down = duck; up does nothing), and the code already establishes that *"buttons consume their own taps in `_gui_input` first, so those never reach here"* (line 69) — i.e. HUD Controls take touch priority over the zones.

### 1.6 The aim path violates the drag

`Hero.gd:477-480` — on touch, aim comes from `Targeting.aim_direction()`, a **hard snap to the nearest enemy**. §5.4 shows this is not merely a rules violation; it is *mechanically incompatible* with the drag.

### 1.7 `HandSlots.gd`

Pure data, headless-tested (`tools/slice6_test_hand_slots.gd`), **not yet wired to any rig or renderer**. Slot 0 is always FISTS, then weapons, then spells; `cycle()` wraps via `wrapi`; per-slot cooldowns; `primary_action()` returns `punch` / `swing` / `cast`; a cooling slot stays *selectable* by design (line 117).

### 1.8 The spell set

`SpellLibrary.build_all()` returns **26** spells. Cooldowns run **3.0–6.5 s**. Only **4 of the 26** carry a `cast_time` (1.0 / 1.0 / 1.1 / 1.3) — the levitating channel. Everything else routes to the 0.42 s summon.

**Per the maker: a character never carries more than 4.** `build_all()` is a review harness, not a loadout.

---

## 2. THE DRAG THESIS — judged

### 2.1 It holds, for a stronger reason than "the motion is the same"

The usual argument is aesthetic: dragging your thumb looks like dragging a blade. True, but weak — plenty of mechanics look like their input and still play badly.

The real argument is that **the mechanic's damage model reads a quantity that only a positional drag produces.**

Damage is `f(blade tip speed)`, and blade tip speed is `angular velocity of the arm target × ~78 px`. The arm target is `(ctrl_aim - shoulder).angle()`. So what the game actually samples, sixty times a second, is **the angular velocity of the player's aim point around the character.**

- A **mouse** produces that directly.
- A **thumb drag** produces that directly.
- An **analog stick + fire button** does not. A stick reports *deflection*, a position that the game would have to integrate into an aim heading. Integrating means thumb speed is decoupled from blade speed: you would either cap the blade at the integrator's rate (no fast slashes) or make deflection mean "swing speed" (which is a throttle, not a drag). Either way you have replaced the mechanic with a different one that happens to share art.

So the fusion is not a convenience that saves a button. **Splitting aim from use would break the melee.** That settles it.

### 2.2 The numbers say mobile is not disadvantaged

With a 1:1 mapping from thumb angle (around the pad's own centre) to aim angle:

| thumb sweep | angular velocity | blade tip speed | reads as |
|---|---|---|---|
| half-turn in 0.20 s | 15.7 rad/s | ~1225 px/s | saturates `BLADE_REF_SPEED` — a full-power whip |
| half-turn in 0.50 s | 6.3 rad/s | ~490 px/s | a solid slash |
| half-turn in 1.20 s | 2.6 rad/s | ~204 px/s | **below** `BLADE_MIN_SPEED` — carrying, not attacking |

The entire designed dynamic range of the damage model lands inside the range of comfortable human thumb sweeps **with no gain constant at all**. That is a strong signal the mechanic was, accidentally, built mobile-native.

### 2.3 An emergent symmetry worth not breaking

Both platforms have **inverse-radius gain**:

- Desktop: the further the cursor sits from the character, the less angle a given mouse movement produces. Players naturally learn to bring the cursor in close for fast slashes and hold it out for slow, menacing drags.
- Mobile: with a dynamic pad, the further out from the pad centre you hold your thumb, the less angle a given finger movement produces. Identical curve, for identical geometric reasons.

**Do not normalise either one.** This is expressive, it is already what the maker is playing, and it means the two platforms really are performing the same act rather than two acts that look alike.

### 2.4 Does it hold for CASTING? — partly, and here is the honest line

**No, not as the same gesture. Yes, as the same zone and the same aim source.**

A weapon drag is *continuous*: the damage has already happened by the time you let go, so release means nothing. A cast is *discrete*: nothing happens until you commit, so release means everything. Forcing them into one grammar gives the weapon a meaningless release and the spell a meaningless drag.

But the aim source is identical, and for the *placed* spells the drag does real work (direction **and** reach). So:

> **ONE ZONE. THREE GRAMMARS, chosen by what is in your hand.**

| in hand | touch down | drag | release |
|---|---|---|---|
| **FISTS** | `punch()` immediately along the current aim | re-aims (arms track, via `ctrl_aim_hold`) | nothing |
| **WEAPON** | opens the drag (`ctrl_weapon_drag = true`) + the `flick` impulse | **is the swing** — this is where damage happens | closes the drag. No commit. |
| **SPELL (aimed)** | begins aiming; a ghost line shows the heading | re-aims | **casts** along the held heading |
| **SPELL (placed)** | begins aiming; a ghost footprint appears at `reach` | sweeps direction **and** distance (`0.35–1.0 × reach` by pad radius) | **casts** at the previewed point |

A quick tap on a spell slot (down and up inside `TAP_MS` = 140 ms, travel < 12 units) casts straight down the last aim, so a panic tap still works.

`HandSlots` already answers "what does use mean" via `primary_action()`. It needs one more accessor so the touch layer knows the *grammar*, not just the *action*:

```gdscript
enum Grammar { TAP, HOLD_DRAG, RELEASE_TO_COMMIT }
func use_grammar() -> int   # FISTS -> TAP, WEAPON -> HOLD_DRAG, SPELL -> RELEASE_TO_COMMIT
```

**The honest cost:** your right thumb's grammar changes when you change slots. Holding a sword, letting go does nothing; holding a spell, letting go fires. That is a real learning tax and the single most likely source of "I didn't mean to cast that". Mitigations, in order of value: (1) the bar's kind glyph (fist / blade / rune) is the *primary* read on each square, not the name; (2) the ghost preview only appears for the RELEASE grammars, so seeing a ghost means "letting go fires"; (3) auto-return to slot 0 after a cast (§6.4) means the default resting grammar is always the weapon's.

---

## 3. THE MOBILE LAYOUT

Base space is 640×360 (`project.godot` `viewport_width/height`, `canvas_items` stretch). All numbers below are base units; multiply by ~3.0 for a 1080p phone in landscape.

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │                                                                      │
 │                                                                      │
 │                     (the fight — nothing occludes it)                │
 │                                                                      │
 │                                              ╭───────────────╮       │
 │                                              │               │       │
 │        LEFT ZONE  x<240                      │   USE / DRAG  │       │
 │        dynamic joystick spawns               │   ZONE        │       │
 │        where you press:                      │   x>360       │       │
 │          ◄─►  move (analog)                  │               │       │
 │          ▲    JUMP  (ny < -0.62)             │  touch-down = │       │
 │          ▼    DUCK  (ny > +0.60)             │  pad centre;  │       │
 │          tap-tap-flick = DASH                │  angle = aim; │       │
 │                                              │  radius=reach │       │
 │   ╭────────╮                                 ╰───────────────╯       │
 │   │DEFLECT │        ▢ ▢ ▢ ▢ ▢ ▢                       ╭─────╮        │
 │   │  58²   │        the SLOT BAR                      │DASH │        │
 │   ╰────────╯        (bottom-centre, tap to select)    ╰─────╯        │
 └──────────────────────────────────────────────────────────────────────┘
      LEFT THUMB              between thumbs                RIGHT THUMB
```

**Combat touch targets: 3** (left zone, deflect, use zone) + an optional dash button + a bar you touch rarely. Down from 8 buttons + joystick.

### 3.1 Left zone — movement, jump, duck, dash

| knob | value | note |
|---|---|---|
| zone | `x < 0.375 × 640 = 240`, minus the deflect rect + a 10-unit halo, minus the bar hit rect | the joystick spawns on press, as today |
| `JOY_RADIUS` | 66 (unchanged) | |
| `JOY_DEADZONE` | 0.18 (unchanged) | |
| `JOY_DUCK_THRESHOLD` | +0.60 (unchanged) → `move_down` | |
| **`JOY_JUMP_THRESHOLD`** | **−0.62** → press `jump` | new |
| **`JOY_JUMP_RELEASE`** | **−0.40** → release `jump` | hysteresis; also drives variable jump height, since `Hero.gd:578` cuts the ascent on `just_released` |

**Why jump becomes a gesture and deflect does not.** We have exactly one free gesture channel on the left thumb — the joystick's upper half, currently unused — and exactly one verb that cannot tolerate a gesture. Assign by latency tolerance, which the code has already quantified for us:

| verb | input forgiveness in code | tolerates recognition latency? |
|---|---|---|
| **jump** | `JUMP_BUFFER_TIME` 0.10 s **and** `COYOTE_TIME` 0.10 s — the only verb with both | **yes**, ~100 ms in both directions |
| **deflect** | none. Not buffered (`Hero.gd:678` list excludes `parry`), 0.16 s reward window | **no** |

Jump also happens constantly while moving, so freeing it from a button that costs you the stick is the larger flow win; deflect happens at most every 0.9 s.

**The false positive to watch:** a diagonal up-right push to run right would jump. `−0.62` is deliberately steeper than the duck's `+0.60` for this reason (running is a horizontal act; ducking is a deliberate one). If F5 says people still jump by accident, the next lever is a *rate* gate — require the vertical to cross the threshold within 120 ms of leaving the deadzone, so a slow diagonal lean never fires.

### 3.2 Deflect — a discrete button, and why no gesture can do this

Budget: `PARRY_WINDOW` is **0.16 s**, and it is a *reward* window — a projectile must arrive inside it. The player must see the tell, decide, input, and have the window still open when the bolt lands. There is no buffer and no coyote.

| candidate | recognition latency | ambiguity |
|---|---|---|
| **discrete button** | **0 frames** — `InputEventScreenTouch.pressed` is the decision | none |
| swipe | ≥ the swipe duration; a 40-unit swipe at a brisk 600 units/s = **67 ms**, realistically 90–120 ms under panic | **fatal** — a right-zone swipe *is* the weapon drag. A misread swings your sword when you meant to block. |
| double-tap | two contacts, ≥ 120–180 ms, cannot fire before the second | none, but strictly worse than a button |
| hold-vs-tap | needs a ~200 ms discriminator | worst of both |

A gesture eats **45–75 % of a 160 ms window before the game has even decided what you did**. Verdict: **button, non-negotiable.**

Placement: **bottom-left corner, 58×58, offset (10, 10)** — the left thumb, not the right, because `HandSlots` specifies deflect works *in every state*, and if it lived on the right thumb you could not deflect mid-drag. It is also consistent with the rig, which already ranks parry above drag (§1.4).

| knob | value |
|---|---|
| rect | `(10, 292)` → `(68, 350)` in base space |
| joystick exclusion | the rect + 10-unit halo |
| **`DEFLECT_MOVE_GRACE`** | **0.25 s** — when the left thumb leaves the joystick to hit deflect, hold the last horizontal move action rather than zeroing it |

`DEFLECT_MOVE_GRACE` is the small change that keeps this from breaking flow. Without it, every block stops you dead; with it, you keep your momentum through the block, which is the Stick-Fight read.

**Honest cost:** you still cannot steer *during* the block. Accepted, because the block is 0.26 s of shell and comes with a 0.9 s cooldown.

**A contradiction to resolve before building:** `HandSlots` says deflect is available *"always, in every state, armed or not"*, but `Hero._try_parry_start` gates on `_cfg["can_parry"]`, which is **false for the mage**. A prominent on-screen button that does nothing for one class is a mobile-UX landmine. **Recommend resolving toward `HandSlots`:** every class deflects; classes differ in *window length* and *cooldown*, not in whether the verb exists. Maker call, flagged.

### 3.3 The use / drag zone — the fused right thumb

| knob | value | why |
|---|---|---|
| zone | `x > 360`, excluding the bar hit rect and the dash button | ~44 % of the width, the whole height |
| pad centre | **the touch-down point** (dynamic, like the left stick) | you can hold the phone however you like |
| **`DRAG_DEAD`** | **10 units** — below this radius, hold the previous aim | avoids an undefined angle at touch-down and stops the aim snapping when you first plant your thumb |
| aim | `angle(touch − pad_centre)`, **unclamped** | leaving it unclamped is what preserves the inverse-radius gain of §2.3 |
| **`R_REACH`** | **70 units** — radius clamp used *only* for the placed-spell reach magnitude | `magnitude = clamp(r / 70, 0, 1)`, mapped to `0.35–1.0 × spell.reach` |
| **`TAP_MS` / `TAP_TRAVEL`** | **140 ms / 12 units** — a tap, not a drag | lets a panic tap cast down the last aim |

Everything downstream consumes one plain unit vector plus one scalar magnitude. **No code below the input layer knows which device produced them** — that is the seam that keeps desktop and mobile from forking.

### 3.4 The slot bar

Bottom-centre, **between the thumb zones** — the one piece of screen neither thumb occupies. Direct tap; see §6 for why tap beats scroll.

| knob | value |
|---|---|
| slot size (drawn) | 40 × 40, gap 6 |
| 6 slots | 270 wide, centred → `x ∈ [185, 455]` |
| bottom margin | 12 → `y ∈ [308, 348]` |
| **hit rect** | **48 wide × 56 tall**, centred on the drawn square, extending *upward* into empty screen |
| touch priority | the bar is a real `Control` and consumes its own touches first; the zone tests reject touches inside its hit rect (the pattern `TouchControls.gd:69` already establishes) |

A 40-unit square is ~120 device px ≈ 7.6 mm at 1080p/400 ppi — under the comfortable minimum, which is exactly why the *hit* rect is larger than the *drawn* rect. That is standard and honest: draw small, hit big.

**Slot read (in priority order — the eye is on the fight, not the bar):**

1. **Selected = the square LIFTS 4 units** and gains a 2 px accent border. Position change is preattentive; colour alone is not.
2. **Kind glyph, top-left, 8 px** — fist / blade / rune. This is what tells you your right-thumb *grammar*, so it outranks the name.
3. **Cooling** — the existing bottom-up wipe + 1-decimal seconds from `AbilityBar._draw_slot`. That code is already good; reuse it verbatim.
4. **Selected AND cooling** — wipe + lift + a **diagonal hatch**. This is the state where your USE button does nothing, and it must be unmistakable.
5. **Key label** — `1`–`6` on desktop, **omitted on touch** (there are no keys).
6. Name: bottom, tiny, dim. Identification only.

### 3.5 Dash button (optional, default ON for playtest 1)

Bottom-right, 46×46, offset (10, 10). Dashes along the current joystick heading, else `facing`. It exists so the gesture in §4 can be judged on its merits rather than shipped because there is no alternative.

---

## 4. THE DASH GESTURE — judged, then specified

### 4.1 The judgement

**The idea is good and the risk is real.** In its favour: dash direction already comes from the movement thumb (`_start_dash` reads `Input.get_vector` over the move actions, `Hero.gd:1235`), so putting the *trigger* on the movement thumb reunites it with its *direction*. It is also a known idiom.

Against it: the left thumb is on the joystick continuously, and the naive gesture ("move, then move again") is uncomfortably close to ordinary movement — stop, start again; micro-adjust at a ledge; reposition a drifting thumb. And the cost of a misfire is unusually high:

- dash spends **0.14 s of i-frames** and a **0.9 s cooldown** — your defensive resource, gone
- it displaces you `620 × 0.14 ≈ 87 px`, which off a ledge is a death
- in a Cuphead-hard game those are the same event

So the gesture must require something ordinary movement **physically cannot produce**. That discriminator is a genuine TAP as the primer: a contact that lifts within 180 ms having travelled less than 24 units. Movement input never does that — a movement push holds for hundreds of milliseconds and travels past the 0.18 deadzone and keeps going.

### 4.2 The gesture, exactly

```
  TAP            LIFT              RE-PRESS            FLICK
  ├──────────────┤                 ├───────────────────────────►  DASH
  ≤180 ms        ≤200 ms gap       within 40 units     ≥41 units within 170 ms
  <24 units                        of the tap point    → direction = the flick vector
```

| symbol | value | rationale |
|---|---|---|
| `DASH_TAP_MAX_MS` | **180 ms** | the primer must lift fast; movement holds are 300 ms+ |
| `DASH_TAP_MAX_TRAVEL` | **24 units** (0.36 × `JOY_RADIUS`) | a tap barely moves; a movement push clears the 12-unit deadzone and keeps going |
| `DASH_GAP_MAX_MS` | **200 ms** | lift → re-press. A deliberate double-tap rhythm is 90–180 ms; a thumb reposition or a movement pause is longer |
| `DASH_REPRESS_MAX_DIST` | **40 units** | a double-tap happens in place; a reposition travels further |
| `DASH_FLICK_MIN_DIST` | **41 units** (0.62 × `JOY_RADIUS`) | must clear the deadzone by a wide margin |
| `DASH_FLICK_MAX_MS` | **170 ms** | from re-press to threshold crossing → implies a floor of **~241 units/s**; resuming a walk is slower |
| `DASH_REARM_LOCKOUT` | **400 ms** | after a dash fires, no new gesture recognition — kills chain-dashing from a wobbling thumb |
| direction | the flick vector at the moment of crossing, normalised, **full 360°** | upgrades `_start_dash`'s 8-way-from-keys to analog |

### 4.3 How accidental dashes are prevented — the full list

1. **The tap primer cannot be produced by movement input.** This is the load-bearing filter. To move, you hold; to prime, you must lift within 180 ms having barely moved.
2. **Proximity requirement** kills the thumb-reposition false positive (repositioning lands somewhere else).
3. **Flick speed floor** (~241 units/s) kills the resume-walking false positive.
4. **Re-arm lockout** kills stutter double-fires.
5. **The dash is gated on `_dash_cooldown_timer <= 0` anyway** — a misfire inside the 0.9 s cooldown costs literally nothing, so the *effective* misfire rate is lower than the *recognition* misfire rate.
6. **Kill switch:** `Tuning.dash_gesture_enabled`, and the dash button of §3.5 stays available.
7. **Instrumentation, mandatory in the playground build:** print `[dash] gesture fired — primer age N ms, flick M units/s`, and a second counter for `gesture fired within 250 ms of a movement resume` — a suspected-misfire proxy. Without a number, "does it misfire?" is unanswerable at F5.

### 4.4 Plumbing note

`_start_dash` derives its direction from `Input.get_vector` over the move actions, and the touch joystick never presses `move_up`. So a 360° flick dash needs the direction passed explicitly. Minimal change that preserves the action seam:

- `TouchControls` sets a `dash_dir_hint: Vector2` on the hero in the same frame it presses the `dash` action.
- `_start_dash` gains a first branch: if the hint is non-zero, use it and clear it; otherwise fall through to the existing key/velocity/facing chain, unchanged.

Three lines, no behavioural change on desktop, headless-testable.

### 4.5 Desktop parity

| knob | value |
|---|---|
| gesture | two `is_action_just_pressed` of the **same** move action within `DESKTOP_DOUBLE_TAP_MS` = **260 ms** |
| fires | on the second press, immediately — zero added latency |
| direction | `Input.get_vector(...)` at fire time, so W held + double-tapped D = up-right |
| toggle | `Tuning.dash_double_tap_enabled`, default ON |

**Space stays the primary desktop dash.** Desktop has keys to spare; taking one away to prove a point would make it feel like a phone port. The double-tap is a *parity* gesture that transfers the *concept* (direction-first dash), not a replacement. 260 ms is deliberately tighter than the classic 300 ms because tapping D twice to inch right is a real desktop pattern.

---

## 5. Consequences for the aim path

### 5.1 Auto-aim is not merely against the rules — it is incompatible with the drag

`Hero.gd:477-480` snaps the touch aim to the nearest enemy. Under the drag model, the arm target *is* the aim. So auto-aim would:

- pin the arm target to an enemy, meaning **your thumb drag produces no arm motion at all** — the drag input would be inert
- and when the nearest enemy changes, **whip the blade at something you did not aim at**, at whatever speed the snap implies

The earlier spec argued this on rules grounds. The drag makes it a mechanical argument. **Delete the `Targeting.aim_direction` branch from the hero's aim path.** `Targeting` stays in the file for enemy AI, which is allowed to aim at the player.

### 5.2 Aim latch on committed casts

`_begin_summon` / `_begin_channel` already snapshot the aim (`_summon_aim = _aim_dir`). Keep that. A committed windup that silently re-aims is a lie about commitment, and a thumb resting on a pad wobbles. But see §7.2 — the *placed point* should come from `origin + aim × reach`, not `get_global_mouse_position()` (`Hero.gd:963, 1073`), which is desktop-only code sitting on a mobile-first path.

### 5.3 Defensive verbs preempt the drag

Promote `_update_arms`'s existing priority order (§1.4) to an input-layer rule:

> **Pressing DEFLECT or DASH closes the drag immediately, on the frame of the press, without requiring the right thumb to lift.**

The rig already renders it this way. Making the input layer agree means you never get the state where you are holding a swing you cannot escape.

---

## 6. SLOT SELECTION — reconciling the two specs

The cap is settled: **4 spells, chosen out of combat.** So the in-combat carousel is fists + (0–1 weapon) + 4 spells ≈ **5–6 entries**. The "26-long carousel" objection is moot and is withdrawn.

### 6.1 Scroll/cycle vs direct selection at ~6 entries

| | cycle (scroll / next-button) | direct (tap a square / press 1–6) |
|---|---|---|
| controls needed | 1 (or 2 for bidirectional) | 6 |
| cost to reach a specific slot | **O(n)** — with `wrapi` the worst case is 3 steps | **O(1)** |
| under pressure | you must *watch the bar* to know where you landed — your eyes leave the fight | spatial; no readback needed |
| mobile screen cost | ~0 | **6 targets — but they sit in the dead zone between the thumbs, not in either thumb zone** |
| transfers between platforms | scroll ↔ nothing on mobile | tap ↔ number key: **same spatial order, same index** |

**Recommendation: DIRECT on both platforms.** The deciding argument is not the O(n) cost — at n=6 that is survivable. It is these two:

1. **Direct tap costs nothing that the drag wants.** A cycle button on mobile has to live *somewhere*, and every somewhere is inside a thumb zone. The bottom-centre bar is the one region neither thumb occupies, and it is already on screen. So direct selection is, on mobile, *cheaper* than a cycle button.
2. **Cycling requires visual readback.** With direct selection you know what you selected because you chose *where* you touched. With cycling you must look at the bar to find out where you ended up — in a Cuphead-hard game, that is the eye leaving the fight at exactly the wrong moment.

**Keep `cycle()` anyway.** It is what the desktop scroll wheel drives (free, natural, no cost), and it is what a gamepad shoulder button will drive. It just is not the primary model.

Muscle memory transfers because both platforms use the *same index in the same left-to-right order*: slot 3 is slot 3 whether you press `3` or tap the third square.

### 6.2 Does slot selection belong in combat?

**Yes — because a "slot" here is your hand, not a menu.** Weapons are picked up mid-fight (that is the Stick-Fight fantasy), and `HandSlots` correctly puts FISTS at index 0 as the never-strandable panic option.

**No — for the loadout.** *Which* 4 spells you carry is a grimoire decision, made out of combat, exactly as the companion spec argues.

That is the clean reconciliation: **the bar is what you are holding; the grimoire is what you brought.**

### 6.3 What should change in `HandSlots.gd`

The model is right. Four additions, all small:

1. **`use_grammar() -> int`** (§2.4). The touch layer needs the grammar, not just the action name.
2. **A stable, typed slot order.** `rebuild()` should emit `[FISTS, weapon?, PRIMARY, AREA, MOBILITY, SIGNATURE]` — the companion spec's typed slots become an *ordering guarantee* rather than a separate system. This is what makes tap-position muscle memory survive a class change: slot 4 is always "get out of trouble", on Cryomancer and on Brawler alike.
3. **`auto_return: bool = true`** — after a SPELL slot fires, return `selected` to 0. See §7.4; this is a flow fix, not a convenience.
4. **`pin()`** — the player can pin a slot to defeat auto-return (long-press the square on touch; hold the number key on desktop).

Keep `cycle()`'s wrap, keep cooling slots selectable (the comment at line 117 is right — hiding a slot would make the bar lie about what you own); auto-return is what stops "selectable while dead" from producing a dead USE button.

### 6.4 Desktop control set — native, not a port

```
A / D              move
W / Up             jump          S    duck / ragdoll
Space              dash          (double-tap a direction = parity gesture)
LEFT MOUSE         USE — hold and move the mouse to drag the blade;
                   press-and-release to cast the held spell
RIGHT MOUSE        DEFLECT
WHEEL              cycle slots            1..6   select slot directly
cursor             aim, always, no button
```

Compared with today this **removes** Q / R / T / G / F / V as ability keys — they fold into slots — and **adds** the wheel and 1–6. Net: fewer keys, mouse-centric, and the mouse does more of the work. That is more native than the current scheme, not less.

---

## 7. THE FLOW PROBLEM — every breaker, with a fix

Stick Fight flows because it has few verbs, no modal states, momentum that always carries, and a weapon whose aiming and attacking are one act. We have the last one already (§2). Here is everything fighting the other three.

### 7.1 BREAKER #1 — every signature roots you; the playground rig roots you for nothing

**The evidence** (§1.2): `_process_channel` and `_process_summon` zero velocity, hold position and `return` before all movement code. `SpikeFigure.cast()` only re-targets the arm springs and lets the torso keep its physics. All 26 spells route through one of the two Hero windups, so **every signature roots you for at least 0.42 s**, and 4 of them root you for 1.0–1.3 s while levitating.

**The maker's instinct — tiered commitment — is right. But the tiers should be read out of the data we already have, not invented.** `CastStyle.duration()` already encodes a per-kind commitment scale (LASH 0.18 → COIL 0.22 → SWEEP 0.28 → SLAM 0.34 → CIRCLE 0.40 → CHANNEL 0.46) and `SpellDef.cast_time` already separates the four true spectacles. So:

| tier | source | duration | movement | jump / dash | cancel | spells |
|---|---|---|---|---|---|---|
| **T1 SNAP** | pose is LASH / THROW / COIL | 0.18–0.22 s | **full** | **yes** | n/a | tether, chain, missiles, rush, nova, flurry, blink-strike, rift dagger |
| **T2 PLANT** | pose is SLAM / SWEEP / CIRCLE / POINT | 0.28–0.42 s | **40 % speed**, no jump | **dash cancels** (50 % cooldown refund) | yes, by dash | walls, pillars, boulders, meteors, zones, crawler, beams |
| **T3 COMMIT** | `cast_time > 0` | 1.0–1.3 s | **rooted + levitating** (unchanged) | no | **no** | the 4 channelled spectacles, and future domains |

**The commitment IS the drama — so it must be rare.** Under this split, 22 of 26 spells stop rooting you outright or become dash-cancellable, and the 4 that root you become genuinely special rather than the default tax on casting. That is the whole answer to "make it flow", and it maps onto existing fields with zero new authoring.

Note the tiering also fixes the rig divergence for free: T1 is exactly what `SpikeFigure` already does, so the playground and the hero converge instead of drifting.

### 7.2 BREAKER #2 — input is DISCARDED, not buffered, during windups

`Hero._physics_process` returns at lines 457–464 for channel/summon, but `_update_input_buffer(delta)` is at line **472**. **Nothing you press during a windup is even recorded.** And `BUFFER_TIME` is 0.12 s — shorter than the 0.42 s summon — so even if it were recorded it would expire.

This is the classic "the game ate my input" feeling, and it is at its worst immediately after the most committed action in the game.

**Fix, three parts:**
1. Move `_update_input_buffer(delta)` **above** the channel/summon early returns.
2. While a committed state is active, do not expire the buffer — hold the newest press and fire it on exit.
3. Add `parry` and the slot-use action to the buffered list. Right now `cast`, `parry` and `ultimate` are polled raw (`Hero.gd:515-519`) and get **zero** forgiveness, while `melee`/`dash`/`blast`/`blink`/`nova` get 0.12 s. The two highest-stakes inputs having the least forgiveness is backwards.

### 7.3 BREAKER #3 — holding DOWN silently disables your entire defensive kit

`Hero.gd:492-502`: the duck / ragdoll branch runs `move_and_slide()` and **returns**. Everything below it — the ability polls at 507–520 and `_try_fire_buffered()` at 552 — never runs. So while ducking you cannot deflect, cast, dash, or fire an ultimate, and nothing tells you.

On mobile this is worse than on desktop, because duck is `ny > 0.60` on the analog joystick: a player steering with a low thumb can cross into duck **without intending to**, and lose their block. That is a silent, invisible, unrecoverable failure at exactly the moment they most need the block.

**Fix:** duck should suppress *locomotion*, not *defence*. Let `parry` and `dash` fire from inside the duck branch (both already have their own gating), and only suppress movement/jump/cast. Alternatively, raise `JOY_DUCK_THRESHOLD` on touch and require the crossing to be *fast*, as with the jump gate — but the real fix is the first one.

### 7.4 BREAKER #4 — cooldowns make spells punctuation, but the UI treats them as the sentence

Spell cooldowns are 3.0–6.5 s. With 4 spells, a 10-second engagement affords roughly **one or two casts**, after which you are holding fists or steel. The weapon drag, by contrast, has a `cd` of 0.12–0.34 s and costs no resource.

**So the game already has the Stick-Fight-paced layer it needs — it is the drag.** The flow problem is not that cooldowns exist (they are what makes a spell an event). It is that the input scheme and the HUD present spells as the primary verb while the drag carries the actual tempo.

**Fix:** `auto_return` (§6.3). After a spell fires, the carousel snaps back to slot 0, so your resting grammar is always "I am holding a weapon and can fight". Casting becomes a deliberate departure from the default rather than a state you get stranded in behind a 6.5 s cooldown with a dead USE button. Pinning is available for players who want the old behaviour.

### 7.5 BREAKER #5 — nothing is cancellable by choice

`_cancel_summon` / `_cancel_channel` fire **only when you are hit**, and they cost MP and cooldown. In Stick Fight, every commitment can be abandoned. Here you can only be *punished* out of one.

**Fix:** T2 PLANT is dash-cancellable with a 50 % cooldown refund (the dash i-frames become the escape hatch, which is also a nice skill expression). T3 COMMIT stays uncancellable — that is the drama, deliberately.

### 7.6 BREAKER #6 — the aim mode changes what your thumb does (covered in §5.1)

Auto-aim makes the drag input inert. Deleting it is a flow fix, not only a rules fix.

### 7.7 BREAKER #7 — the right thumb's grammar changes with the slot (covered in §2.4)

Real, unavoidable given one carousel for weapons and spells, mitigated by the kind glyph, the ghost preview and auto-return.

### 7.8 BREAKER #8 — momentum does not survive UI touches

Two places today: leaving the joystick to press a button zeroes your movement instantly (`_stop_joy` → `_release_all_move`), and every committed windup zeroes `velocity` outright. Stick Fight's momentum always carries.

**Fix:** `DEFLECT_MOVE_GRACE` (§3.2) for the first; T1/T2 not zeroing velocity for the second. In T2, decelerate to 40 % over ~0.1 s rather than snapping to zero — a planted cast should read as *bracing*, not as *hitting a wall*.

---

## 8. Build order

Each phase is felt at F5 before the next one starts. Phases 1 and 2 are the maker's stated priorities and neither one touches mobile.

| phase | contents | risk | why here |
|---|---|---|---|
| **0 — verify** | Headless test asserting the just-landed `TouchControls` fixes: JUMP presses `jump` (not `move_up`), HIT presses `melee`, PARRY presses `parry`. Extend `tools/slice_test_touch.gd`. | none | lock the regression before the file is rewritten |
| **1 — FLOW** | §7.1 commitment tiers, §7.2 buffer during windups + buffer `parry`/use, §7.3 duck stops eating defence, §7.5 dash-cancel on T2, §7.8 no velocity snap. **`Hero.gd` only. Desktop only. Subtractive.** | medium (touches Hero) | the maker's stated next priority, and it is felt the instant you F5 |
| **2 — THE HAND** | Wire `HandSlots` to `SpikeFigure` in the playground + the bar renderer + LMB/RMB/wheel/1–6 + `use_grammar()` + `auto_return`. **Desktop only — the drag already exists there.** | low (playground) | tests the whole thesis for the price of a desktop change |
| **3 — THE THUMB** | The fused touch drag zone (§3.3), the three grammars, ghost previews, and **delete the `Targeting` aim path** (§5.1 — required, auto-aim fights the drag). `TouchControls` with `force_visible` in the playground. | medium | the first real mobile work, judged against a model already proven on desktop |
| **4 — THE GESTURES** | Dash flick (§4) + instrumentation, jump-on-stick-up (§3.1), deflect button + `DEFLECT_MOVE_GRACE` (§3.2), dash button toggle. All behind `Tuning` flags. | high (feel) | the only genuinely unproven interactions; isolated so they can be switched off without unpicking anything |
| **5 — THE HERO** | Port phases 2–4 from the playground onto `Hero` + `AbilityBar`; placed-spell point from `origin + aim × reach` instead of `get_global_mouse_position()` (§5.2). | real | last, on a model that has been felt three times by then |

---

## 9. What will feel bad, and why

Stated plainly, because each of these is a real cost being knowingly accepted.

1. **The first ten minutes on touch will be worse than today.** Losing auto-aim means you will miss things you used to hit. That is the price of the drag and of the no-auto-aim rule; it recovers, but the first session is a regression and should not be mistaken for a bug.
2. **Deflect costs you your steering for a beat.** `DEFLECT_MOVE_GRACE` preserves your *momentum* but you cannot *change* direction during the block. Unavoidable with two thumbs and three left-side verbs.
3. **The right thumb's grammar changes with the slot.** Sword: letting go does nothing. Spell: letting go fires. Some casts will be accidents. The glyph, the ghost and auto-return reduce this; nothing eliminates it.
4. **The dash flick will misfire in the first hour.** The tap primer is a strong filter but not a proof. This is why the button and the kill switch ship alongside, and why §4.3(7) demands a misfire counter rather than a vibe.
5. **Jump-on-stick-up will produce accidental jumps** when a player pushes diagonally to start running. The `−0.62` threshold and the hysteresis reduce it; the rate gate is the next lever if F5 says it is not enough.
6. **Placed-spell reach is strictly worse on mobile than on desktop.** Desktop keeps the cursor and gets a point; mobile gets a direction and a radius. This is an honest asymmetry, not a bug, and it is the correct direction for the asymmetry to run.
7. **Bar squares are small and you will miss under pressure.** The oversized hit rect helps; a missed tap means your USE does the *previous* thing, which under auto-return is at least always "swing the weapon" rather than something random.
8. **Tiering may make signatures feel less special.** If T1 swallows too many spells, casting stops being an event. The tier assignment is a `CastStyle`-driven table, so it is one line per kind to move a spell up a tier — expect to move two or three after the first playtest.
9. **T3 is uncancellable on purpose, and it will kill you.** A 1.3 s levitating root in a Cuphead-hard fight is a genuine gamble. That is the design. If it reads as unfair rather than dramatic, the lever is the *count* of T3 spells (currently 4), not the mechanic.

---

## 10. Open questions for the maker

1. **Deflect for every class?** `HandSlots` says always; `Hero._cfg["can_parry"]` says not for the mage. A visible button that does nothing is worse than either answer. (Recommend: everyone deflects; window length and cooldown vary by class.)
2. **Jump on the stick, or keep the JUMP button?** (Recommend the stick — it frees the button for deflect, and jump is the only verb with both a buffer and a coyote window.)
3. **Auto-return to slot 0 after a cast?** (Recommend yes, with pinning. It is the difference between spells being punctuation and spells being a state you get stranded in.)
4. **T2 at 40 % movement speed** — or fully mobile, or fully rooted? This is the single biggest feel knob in the flow work and it wants a `Tuning` entry from day one.
5. **Dash flick default ON or OFF for playtest 1?** (Recommend ON *with* the button also present, so the misfire counter gets real data.)
6. **Desktop: does the wheel cycle, or is 1–6 enough?** (Recommend both — the wheel is free and some players never learn number rows.)
