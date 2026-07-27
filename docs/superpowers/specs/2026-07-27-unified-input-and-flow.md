# Unified input model + the flow problem — mobile and desktop, one scheme

**Date:** 2026-07-27
**Branch:** `stickman-integrate`
**Status:** design (READ-ONLY recon) → awaiting maker review → plan → build
**Scope:** how the EXISTING verbs (move, jump, dash, use, deflect, select-slot) are controlled on a phone and on a desktop; every place the current design fights "flow like Stick Fight"; and the defensive-budget consequences of the maker's flow decisions.
**Companion:** `docs/superpowers/specs/2026-07-27-mobile-casting-ux.md` — that spec decides WHICH spells you carry (a capped 4). This one decides HOW you hold and use them. §7 reconciles them.

**Maker decisions taken as GIVEN, not re-derived:**
1. **Casts do not root you.** You keep moving; the body floats slightly or does something spell-relevant; a magic circle blooms.
2. **Cooldowns stay**, made acceptable because **melee is always available** — you fight in the gaps. `HandSlots` slot 0 is fists and fists never cool down.
3. **Domains need arena-scale environmental telegraphs** while casting — magic circles, sky colour, mist rolling in. The tell *is* the fantasy.

---

## 0. TL;DR

- **The drag thesis HOLDS**, for a stronger reason than "the motion is the same": blade damage is a function of *aim velocity* (`SpikeFigure._process_blade` scales by `_blade_speed` against `BLADE_REF_SPEED`, refusing damage below `BLADE_MIN_SPEED`). A thumb drag and a mouse drag are the only two inputs that natively produce that quantity. A stick-plus-fire-button cannot. **Fuse aim and use into one right-thumb zone.** It holds for casting as **one zone, three grammars** — not one gesture.
- **The guard/drag thumb conflict is NOT a platform asymmetry to accept or equalise — it is a balance bug that mobile accidentally hides.** Desktop holding RMB+LMB gets *free permanent 35 % damage reduction while attacking at full strength*. Fix the mechanic: **guarding suppresses the use-verb, by rule, on both platforms.** The rig's own `_update_arms` priority already ranks parry above drag. Once that rule exists the asymmetry vanishes and desktop loses nothing it should have had.
- **Guard therefore belongs on the RIGHT thumb** — this reverses the obvious answer, and reverses my own first draft. The old 0.16 s hidden window demanded a zero-travel button; `ParryRing`'s 0.42 s shrink gives ~0.33 s of lead, which comfortably affords ~90 ms of thumb travel. And the left thumb must stay free, because **you must be able to move while guarding**, whereas you must *not* be able to attack while guarding.
- **The defensive budget is broken. A competent player is effectively un-hittable.** ~32.5 % of all time can be spent invulnerable from dash + blink i-frames alone, on top of a free, cooldown-less, infinitely-holdable 35 % DR, on top of full negation + reflect on a read, on top of multiplicatively-stacking `GuardComponent` mitigation — and casting no longer creates a vulnerability window either. §5 says what to cut, bluntly.
- **Hero's melee cannot carry the connective-tissue load the cooldown philosophy assigns it.** The spike rig's *drag* can, easily. That makes the drag work load-bearing for the whole cooldown design, not a mobile-input nicety.
- **Top three flow-breakers:** (1) `_channeling` / `_summoning` early-return past *everything* — that is the root the maker is deleting, and §6.1 lists every site; (2) input is **discarded**, not buffered, during those windups; (3) holding DOWN silently disables your entire defensive kit.

---

## 1. Ground truth — verified on this branch

### 1.1 The verbs

| verb | desktop | Hero path | forgiveness in code |
|---|---|---|---|
| move | A/D (`move_left/right`) | `Hero.gd:545` `Input.get_axis` | — |
| duck / ragdoll | S (`move_down`) held | `Hero.gd:492` | **early-returns — §6.3** |
| jump | W / Up | `Hero.gd:548,578` | buffer 0.10 s **+** coyote 0.10 s **+** variable height |
| dash | Space | buffered → `_start_dash` (`:1227`) | 0.12 s buffer |
| use | LMB (`cast`), F (`melee`) | `:519`, buffered | `cast` **none**, `melee` 0.12 s |
| deflect | RMB (`parry`) | `:517` → `_try_parry_start` | **none** |
| abilities | Q/R/T/G | buffered except `ultimate` | `ultimate` **none** |
| select | V | `:513` | — |

`BUFFER_TIME = 0.12 s` covers exactly `["melee","dash","blast","blink","nova"]` (`:678`). **`cast`, `parry` and `ultimate` — two of them the highest-stakes inputs in the game — have zero forgiveness.**

### 1.2 The two rigs disagree about commitment

| | `SpikeFigure.cast()` (playground) | `Hero._begin_summon` / `_begin_channel` |
|---|---|---|
| duration | `CastStyle.duration(pose)` = **0.18–0.46 s** | **0.42 s** summon (0.22 rush/blink), **1.0–1.3 s** channel |
| movement | **unaffected** — `_cast_timer` only re-targets the arm springs (`:1458`); the torso keeps its physics | **rooted** — `velocity = ZERO`, `return` before all movement code (`:457-464`) |
| cancel | naturally, by moving | only by being hit, at full MP + cooldown cost |

**The thing the maker F5s and enjoys does not root. The shipped hero roots on every single signature.** Maker decision 1 resolves this in the playground's favour; §6.1 is the work.

### 1.3 The drag, exactly as implemented

`SpikeFigure._update_arms`, `dragging and i == lead` (line 1542):

```gdscript
target = (ctrl_aim - sh).angle()
stiff = w["dstiff"];  damp = w["ddamp"];  fstiff = w["fstiff"];  fdamp = w["fdamp"]
```

The arm spring chases the **angle from shoulder to `ctrl_aim`**, and nothing else scripts it. `_process_blade` tests the **swept quad between physics frames** and scales damage by `_blade_speed / BLADE_REF_SPEED` (1100 px/s), refusing below `BLADE_MIN_SPEED` (260 px/s). `punch()` while armed sets `_punch_timer = 0` and only injects a spring impulse plus `_drag_hold`; the header says it outright (line 691): *"click and hold are the same verb, which is the whole point."*

Geometry: `UARM_LEN + FARM_LEN = 30 px`; a sword adds `56 × 0.86 ≈ 48 px`. **Blade tip radius ≈ 78 world px from the shoulder.**

### 1.4 The rig already ranks the verbs

`_update_arms` resolves in a fixed order:

```
punch > dead > cast > DASH > PARRY > stagger > DRAG > aim-hold > cling > air > duck > idle
```

**Dash and parry both sit above drag.** The rig has already decided the defensive verbs preempt the offensive one. §4 promotes this from an animation detail to the load-bearing rule of the whole input model.

### 1.5 The new defensive layer (built, largely unwired)

**`ParryRing.gd`** — deflect is now a *held* input:

| | value | meaning |
|---|---|---|
| `SHRINK_TIME` | 0.42 s | press → ring closes from arm's length to the body |
| `PERFECT_START/END` | 0.78 → 1.0 | perfect band = **0.328 s to 0.42 s** after press, a **~0.092 s window** |
| `SUSTAIN_REDUCTION` | 0.35 | overshoot → a guard you may **hold forever** at 35 % DR |
| `damage_mult()` | PERFECT **0.0**, SUSTAIN 0.65 | a perfect read fully negates |
| `can_reflect()` | PERFECT only | |
| cooldown | **none** — `release()` just sets `_t = 0` | |

**`SpellDeflect.gd`** — **every** attack spell is now deflectable, including all 26 signatures. `DEFLECTED_DAMAGE_MULT = 0.0` (full negation). `WINDOW_ULT = 0.22` makes ults brutal to time but not exempt.

**`GuardComponent.gd`** — one mitigation path: `immunity → persistent × timed → one-shot → absorb`. Each factor capped at 0.95 **individually**; the *combination* is uncapped. Its own header warns that stacking wards on i-frames and a free parry *"is the fastest route to an un-hittable player"*. It does not enforce that.

**Wiring status:** `ParryRing` is referenced only by `tools/slice6_test_parry_ring.gd`. It is **not yet in `Hero`**, which still runs the old `PARRY_WINDOW = 0.16` / `PARRY_COOLDOWN = 0.9` path. That is fortunate — §5's cuts can land as part of the wiring rather than as a nerf to something shipped.

### 1.6 Other verified numbers

- `DASH_TIME` 0.14 s, i-frames for the whole window, `DASH_COOLDOWN` 0.9 s, 620 px/s → 87 px.
- `BLINK_IFRAME` 0.22 s, `BLINK_COOLDOWN` 1.3 s, `BLINK_DISTANCE` 175 px, **phases through walls**.
- Hero `SPEED` 210 px/s, `MP_REGEN` 20/s.
- Spell cooldowns **3.0–6.5 s**; only **4 of 26** carry a `cast_time` (1.0 / 1.0 / 1.1 / 1.3).
- `Hero` melee: `MELEE_COOLDOWN` 0.34, `MELEE_DAMAGE` 14, `MELEE_RANGE` 58, **auto-targets** via `_nearest_enemy_in_melee_range` (`:1895`).
- Touch aim: `Hero.gd:477-480` snaps to nearest enemy via `Targeting.aim_direction`.
- Base viewport **640 × 360**, `canvas_items` stretch (≈ ×3.0 at 1080p landscape).

---

## 2. THE DRAG THESIS — judged

### 2.1 It holds, and for a mechanical reason

The usual argument is aesthetic. The real one is that **the damage model reads a quantity only a positional drag produces.**

Damage is `f(blade tip speed)`, and tip speed is `angular velocity of the arm target × ~78 px`. The arm target is `(ctrl_aim - shoulder).angle()`. So what the game samples sixty times a second is **the angular velocity of the aim point around the character**.

- A **mouse** produces that directly. A **thumb drag** produces that directly.
- An **analog stick + fire button** does not. A stick reports *deflection* — a position the game must integrate into a heading. Integration decouples thumb speed from blade speed: either the blade caps at the integrator's rate (no fast slashes) or deflection becomes a swing-speed throttle (which is not a drag). Either way the mechanic is replaced by a different one wearing the same art.

**Splitting aim from use would break the melee.** That settles it.

### 2.2 The numbers say mobile is not disadvantaged

With a 1:1 mapping from thumb angle (around the pad's own centre) to aim angle:

| thumb sweep | angular velocity | tip speed | reads as |
|---|---|---|---|
| half-turn in 0.20 s | 15.7 rad/s | ~1225 px/s | saturates `BLADE_REF_SPEED` — a full-power whip |
| half-turn in 0.50 s | 6.3 rad/s | ~490 px/s | a solid slash |
| half-turn in 1.20 s | 2.6 rad/s | ~204 px/s | **below** `BLADE_MIN_SPEED` — carrying, not attacking |

The whole designed dynamic range lands inside comfortable human thumb sweeps **with no gain constant at all**. The mechanic was, accidentally, built mobile-native.

### 2.3 An emergent symmetry worth not breaking

Both platforms have **inverse-radius gain**. Desktop: the further the cursor from the character, the less angle a given mouse move produces — so players learn to bring the cursor in close for fast slashes. Mobile: with a dynamic pad, the further out you hold your thumb, the less angle a given finger move produces. Identical curve, identical geometry. **Do not normalise either.** It is expressive, it is what the maker is already playing, and it means the two platforms perform the same act rather than two acts that resemble each other.

### 2.4 For CASTING: one zone, three grammars

A weapon drag is *continuous* — the damage has already happened by the time you let go, so release means nothing. A cast is *discrete* — nothing happens until you commit, so release means everything. One grammar gives the weapon a meaningless release and the spell a meaningless drag.

> **ONE ZONE. THREE GRAMMARS, chosen by what is in your hand.**

| in hand | touch down | drag | release |
|---|---|---|---|
| **FISTS** | strike immediately along the current aim | re-aims (and, per §5.6, drags) | nothing |
| **WEAPON** | opens the drag (`ctrl_weapon_drag = true`) + the `flick` impulse | **is the swing** | closes the drag. No commit. |
| **SPELL (aimed)** | begins aiming; a ghost line shows the heading | re-aims | **casts** along the held heading |
| **SPELL (placed)** | begins aiming; a ghost footprint appears at `reach` | sweeps direction **and** distance (`0.35–1.0 × reach` by pad radius) | **casts** at the previewed point |

A quick tap on a spell slot (down and up inside `TAP_MS` 140 ms, travel < 12 units) casts down the last aim, so a panic tap still works.

`HandSlots.primary_action()` already answers "what does use mean". It needs one more accessor so the touch layer knows the *grammar*:

```gdscript
enum Grammar { TAP, HOLD_DRAG, RELEASE_TO_COMMIT }
func use_grammar() -> int   # FISTS -> TAP, WEAPON -> HOLD_DRAG, SPELL -> RELEASE_TO_COMMIT
```

**The honest cost:** your right thumb's grammar changes when you change slots — with a sword, letting go does nothing; with a spell, letting go fires. That is a real learning tax and the likeliest source of "I didn't mean to cast that". Mitigations, in order of value: (1) the bar's **kind glyph** (fist / blade / rune) is the primary read on each square, above the name; (2) a **ghost preview appears only for RELEASE grammars**, so seeing a ghost means letting go fires; (3) **auto-return to slot 0** after a cast (§7.4), so the default resting grammar is always the weapon's.

---

## 3. THE THUMB CONFLICT — the crux

Deflect is now a **held** input whose perfect band sits 0.328–0.42 s after the press. The drag is also a held input. One thumb cannot do both. Desktop can hold RMB and LMB with no trouble.

### 3.1 The asymmetry is real, but it is the wrong thing to look at

Follow the desktop side through:

> A desktop player holds RMB. The ring bottoms out at 0.42 s into **SUSTAIN**. Sustain has **no cooldown, no resource cost, no duration limit, and no movement penalty**. They keep holding it, and drag the blade with LMB at full strength.
>
> **That is a permanent, free 35 % damage reduction while attacking at 100 %.**

There is no version of that which is intended. Mobile's one-thumb limit is not a disadvantage — it is the *only thing currently preventing* the degenerate case. **The asymmetry is a symptom; the mechanic is the bug.**

So the question "accept it, equalise it, or move the guard" has a fourth and correct answer: **make guarding and attacking mutually exclusive by rule**, and the asymmetry ceases to exist.

### 3.2 The rule

> **While the guard is held, the use-verb is suppressed.** The drag closes on the frame guard is pressed; spells will not fire; fists will not strike. Releasing guard restores the use-verb on the next frame.
> Symmetrically, **pressing use does not break an active guard** — guard wins, because it is the committed act.

This is not invented. `_update_arms` already resolves `PARRY > DRAG` (§1.4). The input layer is being made to agree with the rig it drives.

Consequences:
- **Desktop loses nothing it should have had.** RMB+LMB now expresses "guard", exactly as it does on mobile.
- **Mobile is no longer disadvantaged.** Zero asymmetry, zero platform-specific balance.
- **The guard becomes a real decision** — which is what `ParryRing`'s own header promises (*"a real decision instead of a reflex"*) and what a free concurrent sustain silently destroys.
- **It creates the vulnerability window that removing the cast-root deleted.** See §5.5 — this is structurally important.

### 3.3 …and therefore the guard belongs on the RIGHT thumb

This reverses the obvious answer, and reverses my own first draft. The reasoning that put deflect on the left thumb was correct **for the old mechanic** and is wrong for the new one:

| | old parry (`PARRY_WINDOW` 0.16 s, hidden) | new `ParryRing` (0.42 s shrink) |
|---|---|---|
| lead time before the block matters | ~0 — you react into a 160 ms window | **~0.33 s** — you commit, then wait |
| affordable input latency | ~0 ms; any thumb travel eats the window | **~90 ms of thumb travel is 27 % of the lead** |
| compatible with attacking | had to be, so it could not share the attack thumb | **must not be** (§3.2), so it *should* share it |

Two independent arguments now point the same way:

1. **The right thumb has nothing to do while guarding.** By §3.2 the use-verb is suppressed, so the drag zone is inert. Putting the guard anywhere else wastes a thumb.
2. **The left thumb must stay free, because you must be able to MOVE while guarding.** Retreating behind a guard is the core defensive act; a guard that stops your feet is a guard nobody uses. Putting the guard on the left thumb would make it mutually exclusive with *movement* — a far worse exclusion than the one with attacking, and one that no rule justifies.

**The shrinking ring is precisely what unlocks this placement.** The old window forbade any travel cost; the new one affords it.

### 3.4 Layout consequence

The right side splits into two touch regions. The split is **positional, so recognition is instantaneous** — no hold-vs-tap discrimination, no swipe recognition, no ambiguity with the drag.

```
                          ╭──────────────────────────╮
                          │                          │
                          │      USE / DRAG ZONE     │
                          │   (aim · swing · cast)   │
                          │                          │
                          ╰──────────────────────────╯
                          ╭──────────────────────────╮
                          │   G U A R D   B A N D    │   ← hold anywhere in here
                          ╰──────────────────────────╯
```

| knob | value (base 640×360) |
|---|---|
| right region | `x > 360` |
| **guard band** | the bottom **74 units** of it: `y > 286`, `x > 400` — a wide, shallow strip your thumb drops onto |
| use / drag zone | the rest of `x > 360`, i.e. `y < 286` |
| thumb travel to guard | ~40–60 base units ≈ 12–18 mm ≈ **60–90 ms** — 18–27 % of the ring's 0.33 s lead |
| ring feedback | the ring is drawn **on the character**, not on the band — you watch the fight, not your thumb |

The band is deliberately a *band*, not a button: under pressure you drop your thumb, you do not aim it. It is also on the outer/lower edge, which is where a thumb naturally rests between actions.

**Desktop:** RMB held = guard; the ring draws on the character; LMB is ignored while RMB is held (§3.2). Identical model, native input.

### 3.5 Honest costs of this decision

1. **You cannot re-aim while guarding.** Your aim freezes at its last heading for the duration. Acceptable — a guard is a committed defensive act — but it means a guard that gets baited leaves you facing the wrong way. That is the intended punish.
2. **60–90 ms of travel is not free.** Against a genuinely unreactable attack you will be late. The ring's lead absorbs it; a *surprise* attack still beats you, which is correct.
3. **Two right-side regions means an edge case at the boundary.** A drag that wanders down into the band must not become a guard. Rule: **the region is decided at touch-down and latched for the life of that touch.** A drag that started in the use zone stays a drag no matter where the thumb travels.

---

## 4. THE MOBILE LAYOUT

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │                                                                      │
 │                      (the fight — nothing occludes it)               │
 │                                                                      │
 │                                          ╭────────────────────────╮  │
 │      LEFT ZONE  x<240                    │                        │  │
 │      dynamic joystick spawns             │     USE / DRAG ZONE    │  │
 │      where you press:                    │   touch-down = pad     │  │
 │        ◄─►  move (analog)                │   centre; angle = aim; │  │
 │        ▲    JUMP  (ny < -0.62)           │   radius = reach       │  │
 │        ▼    DUCK  (ny > +0.60)           │                        │  │
 │        tap-tap-flick = DASH              ╰────────────────────────╯  │
 │                                          ╭────────────────────────╮  │
 │                    ▢ ▢ ▢ ▢ ▢ ▢           │   G U A R D            │  │
 │                    the SLOT BAR          ╰────────────────────────╯  │
 └──────────────────────────────────────────────────────────────────────┘
      LEFT THUMB          between thumbs              RIGHT THUMB
```

**Combat touch targets: 3** (left zone, use zone, guard band) + a bar you touch rarely. Down from the current **8 buttons** + joystick.

### 4.1 Left zone — move, jump, duck, dash

| knob | value | note |
|---|---|---|
| zone | `x < 240` (0.375 × 640), minus the bar hit rect | dynamic joystick, spawns on press |
| `JOY_RADIUS` / `JOY_DEADZONE` | 66 / 0.18 | unchanged |
| `JOY_DUCK_THRESHOLD` | +0.60 → `move_down` | unchanged |
| **`JOY_JUMP_THRESHOLD`** | **−0.62** → press `jump` | new |
| **`JOY_JUMP_RELEASE`** | **−0.40** → release `jump` | hysteresis; also drives variable jump height (`Hero.gd:578` cuts the ascent on `just_released`) |

**Why jump becomes a gesture.** The joystick's vertical axis is currently half-used (down = duck; up does nothing) — one free gesture channel. Assign it by latency tolerance, which the code has already quantified:

| verb | forgiveness in code | tolerates recognition latency? |
|---|---|---|
| **jump** | buffer 0.10 s **and** coyote 0.10 s — the only verb with both | **yes**, ~100 ms either way |
| **guard** | none; a 0.092 s perfect band | **no** |

Jump also happens constantly while moving, so freeing it from a button that costs you the stick is the larger flow win.

**The false positive to watch:** a diagonal up-right push to start running would jump. `−0.62` is deliberately steeper than the duck's `+0.60` for that reason. If F5 says it is not enough, the next lever is a *rate* gate — require the vertical to cross within 120 ms of leaving the deadzone, so a slow diagonal lean never fires.

### 4.2 Use / drag zone

| knob | value | why |
|---|---|---|
| zone | `x > 360`, `y < 286`, region latched at touch-down (§3.5.3) | ~44 % of width |
| pad centre | **the touch-down point** (dynamic) | hold the phone however you like |
| **`DRAG_DEAD`** | **10 units** — below this radius, hold the previous aim | no undefined angle at touch-down; no snap when you plant your thumb |
| aim | `angle(touch − pad_centre)`, **unclamped** | preserves the inverse-radius gain of §2.3 |
| **`R_REACH`** | **70 units** — clamp used *only* for placed-spell reach | `magnitude = clamp(r / 70, 0, 1)` → `0.35–1.0 × spell.reach` |
| **`TAP_MS` / `TAP_TRAVEL`** | **140 ms / 12 units** | a panic tap casts down the last aim |

Everything downstream consumes one unit vector plus one scalar. **No code below the input layer knows which device produced them.**

### 4.3 Guard band

Per §3.4. Held; `ParryRing.press()` on touch-down, `release()` on lift. No cooldown of its own today — §5.2 adds one.

### 4.4 Slot bar

Bottom-centre — **the one region neither thumb occupies.** Direct tap (see §7.1).

| knob | value |
|---|---|
| drawn size | 40 × 40, gap 6 → 6 slots = 270 wide, centred `x ∈ [185, 455]` |
| bottom margin | 12 → `y ∈ [308, 348]` |
| **hit rect** | **48 × 56**, centred on the square, extending **upward** into empty screen |
| touch priority | the bar is a real `Control` and consumes its own touches first (the pattern `TouchControls.gd:69` already establishes); zone tests reject touches inside its hit rect |

A 40-unit square is ~7.6 mm at 1080p/400 ppi — under the comfortable minimum, which is exactly why the hit rect is larger than the drawn rect. Draw small, hit big.

**Slot read, in priority order** (your eye is on the fight, not the bar):

1. **Selected = the square LIFTS 4 units** + a 2 px accent border. Position change is preattentive; colour alone is not.
2. **Kind glyph, top-left, 8 px** — fist / blade / rune. This is your right-thumb *grammar*, so it outranks the name.
3. **Cooling** — the existing bottom-up wipe + 1-decimal seconds from `AbilityBar._draw_slot`. Reuse verbatim; that code is already good.
4. **Selected AND cooling** — wipe + lift + a **diagonal hatch**. This is the state where your USE does nothing and it must be unmistakable.
5. **Key label** — `1`–`6` on desktop, **omitted on touch**.
6. Name: bottom, tiny, dim.

### 4.5 Dash gesture

**Judgement: good idea, real risk.** In its favour, dash direction already comes from the movement thumb (`_start_dash` reads `Input.get_vector` over the move actions, `:1235`), so putting the trigger there reunites it with its direction. Against it: the left thumb is on the joystick continuously, and the naive gesture is close to ordinary movement — and a misfire spends 0.14 s of i-frames, a 0.9 s cooldown, and 87 px of displacement that off a ledge is a death.

So the gesture must require something ordinary movement **physically cannot produce**: a genuine TAP primer.

```
  TAP            LIFT              RE-PRESS            FLICK
  ├──────────────┤                 ├───────────────────────────►  DASH
  ≤180 ms        ≤200 ms gap       within 40 units     ≥41 units within 170 ms
  <24 units                        of the tap point    → direction = the flick vector
```

| symbol | value | rationale |
|---|---|---|
| `DASH_TAP_MAX_MS` | **180 ms** | movement holds are 300 ms+ |
| `DASH_TAP_MAX_TRAVEL` | **24 units** (0.36 × `JOY_RADIUS`) | a movement push clears the 12-unit deadzone and keeps going |
| `DASH_GAP_MAX_MS` | **200 ms** | a deliberate double-tap rhythm is 90–180 ms; a reposition is slower |
| `DASH_REPRESS_MAX_DIST` | **40 units** | a double-tap happens in place |
| `DASH_FLICK_MIN_DIST` | **41 units** (0.62 × `JOY_RADIUS`) | clears the deadzone by a wide margin |
| `DASH_FLICK_MAX_MS` | **170 ms** | implies a floor of ~241 units/s; resuming a walk is slower |
| `DASH_REARM_LOCKOUT` | **400 ms** | kills chain-dashing from a wobbling thumb |
| direction | flick vector at crossing, normalised, **full 360°** | upgrades `_start_dash`'s 8-way-from-keys to analog |

**Accidental-dash prevention, in full:** (1) the tap primer cannot be produced by movement input — this is the load-bearing filter; (2) proximity kills the thumb-reposition case; (3) the flick speed floor kills the resume-walking case; (4) the re-arm lockout kills stutter double-fires; (5) a dash is gated on `_dash_cooldown_timer <= 0` anyway, so a misfire inside the 0.9 s cooldown costs nothing and the *effective* misfire rate is below the *recognition* rate; (6) kill switch `Tuning.dash_gesture_enabled`; (7) **mandatory instrumentation** — print `[dash] gesture fired — primer age N ms, flick M units/s` plus a counter for `fired within 250 ms of a movement resume`. Without a number, "does it misfire?" is unanswerable at F5.

**Plumbing:** `_start_dash` derives direction from `Input.get_vector` over the move actions, and the touch joystick never presses `move_up`. So `TouchControls` sets a `dash_dir_hint: Vector2` on the hero in the same frame it presses `dash`, and `_start_dash` gains a first branch that consumes and clears it, falling through to the existing chain otherwise. Three lines; no desktop behaviour change; headless-testable.

**Desktop parity:** two `is_action_just_pressed` of the **same** move action within `DESKTOP_DOUBLE_TAP_MS` = **260 ms**, firing on the second press with zero added latency; direction from `Input.get_vector` at fire time. **Space stays the primary desktop dash** — desktop has keys to spare, and taking one away to prove a point is what makes a game feel like a phone port. The double-tap transfers the *concept*, not the necessity. 260 ms is deliberately tighter than the classic 300 ms because tapping D twice to inch right is a real desktop pattern.

### 4.6 Desktop control set — native, not a port

```
A / D              move                    W / Up  jump        S  duck / ragdoll
Space              dash                    (double-tap a direction = parity gesture)
LEFT MOUSE         USE — hold and move the mouse to drag the blade;
                   press-and-release to cast the held spell
RIGHT MOUSE        GUARD (held). Suppresses LEFT MOUSE while held (§3.2).
WHEEL              cycle slots             1..6   select slot directly
cursor             aim, always, no button
```

Against today this **removes** Q / R / T / G / F / V as ability keys (they fold into slots) and **adds** the wheel and 1–6. Net: fewer keys, mouse-centric, more of the work done by the mouse. That is more native than the current scheme, not less.

---

## 5. THE DEFENSIVE BUDGET — the blunt answer

### 5.1 Add it up

| source | invulnerability / mitigation | cost | uptime |
|---|---|---|---|
| **dash i-frames** | **total**, 0.14 s | 0.9 s cd | **15.6 %** |
| **blink i-frames** | **total**, 0.22 s, +175 px **through walls** | 1.3 s cd | **16.9 %** |
| **perfect parry** | **1.00× negation** + reflect, vs *every* spell incl. ults | a 0.092 s read | repeatable, **no cooldown** |
| **sustained guard** | **0.35× off everything** | *none* — hold forever | **100 %** when not attacking |
| **`GuardComponent`** | persistent × timed × one-shot × absorb, **uncapped in combination** | gear / wards | persistent |
| **casts no longer root** | removes the last reliable punish window | — | — |

Dash and blink are **independent cooldowns**, so alternated they put an invulnerable frame within reach roughly every 0.45 s, and **32.5 % of all elapsed time can be spent invulnerable** — while also repositioning 87 px or 175 px.

Stacked multiplicatively, a modest kit (gear 0.25, a ward 0.50, sustained guard 0.35) already lands at `0.75 × 0.50 × 0.65 =` **0.244×** — a 76 % reduction — *before* absorb, *before* i-frames, *before* a perfect parry sets it to zero.

### 5.2 Verdict

**Yes. A competent player is effectively un-hittable, and it is not close.** The remaining way to take damage is to choose to.

And the failure mode is worse than "too easy". It is **boring, then unfair**: the only lever left against an un-hittable player is enormous enemy damage, so the rare hits that land delete you. That is the classic over-defence death spiral — a one-mistake game with no mid-range, which is the opposite of Cuphead-hard (Cuphead is hard because you get hit *often* and survive *a bit*).

### 5.3 What I would cut, in order

**CUT 1 — SUSTAIN must cost something. This is the worst item on the list.** A free, permanent, cooldown-less, movement-unimpeded 35 % DR has no cost, no counterplay and no decision. `ParryRing`'s own doc reasons *"not much, or holding would beat timing"* — but 35 % at zero cost beats timing on expected value for anyone not confident of a 0.092 s band, so the intended decision never actually gets made.
- **(a) Sustain drains a guard meter** — deplete over ~1.5 s of holding, refill only while not guarding. This makes holding a real decision, and gives enemies a **guard-break** on depletion, which is also a great spectacle and a great tell.
- **(b) Sustain suppresses movement to ~30 % speed.** Turtling should be static.
- Recommend **(a) + (b)**. Sustain becomes *turtling*: safe, immobile, finite.

**CUT 2 — the ring needs a re-arm cost.** `release()` sets `_t = 0` instantly, so a player can spam press/release fishing for perfects at zero risk. Add `RING_REARM = 0.35 s` after any release, **or** make a *whiffed* guard (released with no hit having arrived) cost 0.6 s. Without this the "real decision" the header promises is not a decision — you simply always guard.

**CUT 3 — pick ONE i-frame mobility, not two.** Dash *and* blink both grant invulnerability *and* displacement; blink additionally phases through walls. Two independent invulnerable escapes is one too many, and it is also what makes kiting (§5.7) degenerate. Recommend: **blink loses its i-frames** and keeps the displacement (175 px + wall-phase is already an enormous escape), **or** blink becomes the MOBILITY *slot* spell so it competes with your other three rather than being free alongside them. The typed-slot model (§7.2) makes the second option natural.

**CUT 4 — cap the `GuardComponent` stack.** Each factor is capped at 0.95 individually; the combination is uncapped. Add a floor: **total pre-guard mitigation cannot exceed 0.60.** The class header already identifies stacking as the fastest route to an un-hittable player; it just does not enforce it.

**CUT 5 — keep `DEFLECTED_DAMAGE_MULT = 0.0` for PERFECT, but only once CUTs 1–2 land.** Full negation on a hard read is correct and it *should* be the best moment in a fight (`SpellDeflect`'s header is right about this). The problem is never the reward; it is that reaching the reward currently costs nothing. Fix the cost, keep the payoff.

**KEEP — casts do not root you.** That is the maker's decision and it is right for flow. But name the consequence honestly: **removing the root removes the only window in which a spell-heavy player was reliably punishable.** It has to be re-created somewhere, and §5.5 is where.

### 5.4 What the cuts add up to

| after the cuts | |
|---|---|
| i-frame uptime | 15.6 % (dash only) instead of 32.5 % |
| sustain | costs a meter, immobilises you, breakable by enemies |
| guard spam | gated by a 0.35 s re-arm |
| mitigation stack | floored at 0.60 pre-guard |
| perfect parry | untouched — still absolute, still the best moment in a fight |

That is still a *generously* defended player. It is no longer an un-hittable one.

### 5.5 The structural payoff — the guard becomes the new vulnerability window

This is the part worth stating on its own, because it is what makes the maker's flow decisions safe:

> Before: you were punishable **while casting** (rooted 0.42–1.3 s).
> After: you are punishable **while guarding** — because guard suppresses attacking (§3.2), drains a meter (CUT 1a), immobilises you (CUT 1b) and can be broken (CUT 1a).

The vulnerability has moved from something the game imposed on you to **something you chose**, which is strictly better design and produces a real rhythm: *attack → get pressured → guard (stop attacking, drain, root yourself) → get baited → punished*. Every one of those beats is a decision.

### 5.6 Is Hero's melee good enough to be the connective tissue?

Maker decision 2 assigns melee a heavy load: it is what makes 3.0–6.5 s cooldowns acceptable. Two different melees exist in this repo and they are not close.

**Hero's melee — NO.** `MELEE_DAMAGE` 14 on a `MELEE_COOLDOWN` 0.34 s = 41 dps, delivered by a discrete button that **auto-targets the nearest enemy** (`_nearest_enemy_in_melee_range`, `:1895`). It has a cooldown, so it is stop-start too; it aims itself, so it has no expression and no skill; and it is one animation. Filling a 6.5 s gap with it means tapping one self-aiming button eighteen times. That makes cooldowns *worse*, not acceptable.

**The spike rig's drag — YES, easily.** Continuous input; a real skill ceiling (damage scales with blade speed, `BLADE_REF_SPEED` 1100, floor 260); five distinct per-weapon heft profiles (`dstiff`/`ddamp`/`fstiff`/`fdamp`); swept-path contact; no resource; per-target `BLADE_HIT_CD` 0.26 rather than a global cooldown; and it is the same act as aiming. It is a fighting *system*, not a filler animation.

**Therefore: the drag is load-bearing for the entire cooldown philosophy, not a mobile-input nicety.** It must land before, or with, any cooldown rebalancing. Sequenced accordingly in §8.

**One gap to close: bare fists have no drag.** `is_dragging()` requires `_weapon != ""`, so slot 0 — the slot `HandSlots` guarantees you always have — is the *weak* melee. `_process_blade` already tests the swept path of a segment, so give the fist a zero-length "blade" on the forearm segment: `dmg` ~10, high `dstiff`/`ddamp` (snappy, short reach), no trail. Unarmed becomes the same verb as armed with less reach and less damage. Small change, large payoff — the connective tissue then works even with nothing in your hands.

### 5.7 Kiting — is casting-while-moving with no auto-aim a problem?

**Not by itself. It becomes one only in combination with CUT 3.**

Three things already limit it:

1. **No auto-aim is the primary limiter, and it cuts against the kiter.** Aiming manually while retreating is genuinely hard: the target's relative angle changes *because you are moving*, so a backpedalling caster is fighting their own movement with their aim thumb. Manual aim makes kiting a skill tax, not a free win. This is the strongest argument that the maker's two decisions are compatible.
2. **Cooldowns.** 3.0–6.5 s across four spells means a kiter is out of spells after roughly four casts and must either close to melee or run in circles doing nothing. Maker decision 2, read from the other direction: **melee is what stops kiting from dominating, because a kiter who refuses to melee simply stops dealing damage.**
3. **Arena geometry.** Floors are one parameterized room shell; walls and breakable platforms cap kite distance. Worth stating explicitly: **arena size is now a balance parameter, not just a layout one.**

What actually breaks it is **mobility with i-frames**: dash (87 px, invulnerable) plus blink (175 px, invulnerable, through walls) lets a player outrun anything and cast in between, with the i-frames covering the approach they failed to prevent. **Fix CUT 3 and kiting self-limits.**

Two cheap additional levers, both compatible with "casts do not root you":

- **A cast movement *penalty*, not a root.** While a cast's pose window is active, movement runs at **70 %** (T1) / **55 %** (T2). You keep full control and full momentum; you are just slower, so backpedalling-while-casting loses ground. This is the single cheapest anti-kite lever and it honours the maker's decision exactly — a slowdown is not a root.
- **Generalise the reach clamp.** `Hero.BLAST_MAX_RANGE = 480` already exists as the "skill-shot, not a cross-stage snipe" clamp. A 1250 px beam (`frostpiercer`) in a room narrower than 1250 px is a free full-screen hit, kiting or not. Move the clamp onto `SpellDef` and apply it to every kind.

Encounter composition is the remaining lever and belongs to the enemy work, not here: a kiter should be answered by ranged casters, a brawler by chargers. Both archetypes already exist from Slice 2.

---

## 6. THE FLOW WORK

### 6.1 Every place movement/input is gated on `_channeling` / `_summoning`

This is the concrete work for maker decision 1. Sites in `Hero.gd`:

| line | what it does | what it becomes |
|---|---|---|
| **457-459** | `if _channeling: _process_channel(delta); return` — **the master gate**. Skips the input buffer, aim resolution, ragdoll, every ability poll, all movement, jump, and the rig state machine. | **delete the return.** `_channeling` becomes a *modifier* flag consumed further down. |
| **462-464** | `if _summoning: _process_summon(delta); return` — same. | **delete the return.** |
| `_begin_channel` **1074** | `_channel_base_y = global_position.y` — anchors the levitation to a fixed world Y | **delete.** Levitation becomes a rig offset, not a position anchor. |
| `_begin_channel` **1076** | `velocity = Vector2.ZERO` | delete |
| `_begin_channel` **1079** | `rig.set_airborne(true)` | keep — it is the "legs dangle" look and is now cosmetic |
| `_process_channel` **1096-1099** | `global_position.y = _channel_base_y - _channel_lift + bob`; `velocity = Vector2.ZERO` | **replace with `rig.set_float_offset(_channel_lift + bob)` plus a gravity bias.** Assigning `global_position` bypasses collision; a rig offset does not. |
| `_process_channel` **1101** | `rig.set_body_velocity(Vector2.ZERO)` | pass the real velocity — the limbs should trail as you drift |
| `_process_summon` **980-982** | `velocity = Vector2.ZERO`; `move_and_slide()`; `rig.set_body_velocity(ZERO)` | apply the §5.7 speed multiplier instead of zeroing |
| `_process_summon` **983** | `rig.play(CAST)` every frame | keep, but let RUN/AIR win when actually moving so the body reads as *moving while casting* |
| `_begin_summon` **964** | `velocity = Vector2.ZERO` | delete |
| `_finish_summon` **1035** / `_finish_channel` **1127** | `_self_recoil(110 / 90)` | make it **additive** to existing velocity — it currently assumes you were standing still |
| `_cancel_channel` **1154** | `rig.apply_impulse(...)` "flung out of the float" | keep; it now reads as being knocked out of a drift |
| `_begin_summon` **963** / `_begin_channel` **1073** | `get_global_mouse_position()` | `origin + aim_dir × reach` — desktop-only code on a mobile-first path |
| **962 / 1073** | `_summon_aim = _aim_dir`, `_channel_target` | **keep the aim latch.** Even a mobile cast must not re-aim mid-windup — that is the drama and the opponent's read. |

Additional rules once the returns are gone:
- `_channeling` / `_summoning` **suppress the use-verb and other casts** (one cast at a time), and **suppress jump** in T2/T3.
- **Dash cancels** a T2 cast for a 50 % cooldown refund (§6.5). T3 stays uncancellable — that is the drama.
- The rig needs `set_float_offset(px: float)`, a purely visual Y offset. This is the one genuinely new rig API.

### 6.2 Input is DISCARDED, not buffered, during windups

`_update_input_buffer(delta)` is at line **472**, *below* the early returns at 457–464. **Nothing pressed during a windup is even recorded**, and `BUFFER_TIME` (0.12 s) is shorter than the 0.42 s summon anyway. This is the classic "the game ate my input", occurring immediately after the most committed action in the game.

**Fix:** (1) move `_update_input_buffer` **above** the committed-state handling; (2) do not expire the buffer while a committed state is active — hold the newest press and fire it on exit; (3) add `parry` and the slot-use action to the buffered list. Right now `cast`, `parry` and `ultimate` are polled raw (`:515-519`) with **zero** forgiveness while `melee`/`dash`/`blast`/`blink`/`nova` get 0.12 s. The two highest-stakes inputs having the least forgiveness is backwards.

### 6.3 Holding DOWN silently disables the entire defensive kit

`Hero.gd:492-502`: the duck / ragdoll branch runs `move_and_slide()` and **returns**. Everything below — the ability polls at 507–520 and `_try_fire_buffered()` at 552 — never runs. **While ducking you cannot guard, cast, dash or ult, and nothing tells you.**

On mobile this is worse, because duck is `ny > 0.60` on an analog stick: a player steering with a low thumb can cross into duck **unintentionally** and lose their block. A silent, invisible, unrecoverable failure at exactly the wrong moment.

**Fix:** duck should suppress *locomotion*, not *defence*. Let `parry` and `dash` fire from inside the duck branch (both have their own gating already); suppress only movement, jump and cast.

### 6.4 Cooldowns make spells punctuation — the UI should agree

With 3.0–6.5 s cooldowns across four spells, a 10-second engagement affords one or two casts. Maker decision 2 is that melee fills the gaps; §5.6 says only the *drag* can do that. The remaining problem is presentational: the input scheme and HUD currently present spells as the primary verb.

**Fix:** `auto_return` on `HandSlots` — after a spell fires, the carousel snaps back to slot 0. Your resting grammar becomes "I am holding a weapon and can fight", casting becomes a deliberate departure, and you are never stranded behind a 6.5 s cooldown with a dead USE button. `pin()` is available for players who want the old behaviour.

### 6.5 Nothing is cancellable by choice

`_cancel_summon` / `_cancel_channel` fire **only when you are hit**, at full MP + cooldown cost. In Stick Fight every commitment can be abandoned; here you can only be *punished* out of one.

**Fix:** a T2 cast is dash-cancellable with a 50 % cooldown refund — the dash i-frames become the escape hatch, which is also good skill expression. A T3 domain is not cancellable; that is the drama, deliberately.

### 6.6 Auto-aim is incompatible with the drag

`Hero.gd:477-480` snaps the touch aim to the nearest enemy. Under the drag model the arm target *is* the aim, so auto-aim would **pin the arm target to an enemy — making your thumb drag inert** — and then **whip the blade at something you did not aim at** whenever the nearest enemy changed. This is a mechanical incompatibility, not only a rules violation. **Delete the `Targeting.aim_direction` branch from the hero's aim path.** `Targeting` stays in the file for enemy AI, which is allowed to aim at the player.

### 6.7 Momentum does not survive UI touches

Leaving the joystick zeroes movement instantly (`_stop_joy` → `_release_all_move`), and every committed windup zeroes `velocity`. Stick Fight's momentum always carries. §6.1 fixes the second; for the first, decelerate over ~0.1 s rather than snapping to zero. In a cast, decelerating to the §5.7 multiplier should read as *bracing*, not as *hitting a wall*.

---

## 7. SLOT SELECTION

The cap is settled: **4 spells, chosen out of combat.** So the in-combat carousel is fists + (0–1 weapon) + 4 spells ≈ **5–6 entries**. The "26-long carousel is too slow" objection is moot and is withdrawn.

### 7.1 Cycle vs direct at ~6 entries

| | cycle (scroll / next-button) | direct (tap a square / press 1–6) |
|---|---|---|
| controls needed | 1–2 | 6 |
| cost to reach a slot | **O(n)** — worst case 3 with `wrapi` | **O(1)** |
| under pressure | you must **watch the bar** to see where you landed | spatial; no readback |
| mobile screen cost | ~0 | **6 targets — but in the dead zone between the thumbs, in neither thumb zone** |
| transfers across platforms | scroll ↔ nothing on mobile | tap ↔ number key: **same index, same order** |

**Recommendation: DIRECT on both platforms.** The deciding arguments are not the O(n) cost (survivable at n=6) but:

1. **Direct tap costs nothing the drag wants.** A cycle button on mobile has to live *somewhere*, and every somewhere is inside a thumb zone. The bottom-centre bar is the one region neither thumb occupies and it is already on screen — so direct is, on mobile, *cheaper* than a cycle button.
2. **Cycling requires visual readback.** Direct selection tells you what you chose by *where* you touched. Cycling makes you look at the bar to find out — the eye leaving the fight at exactly the wrong moment.

**Keep `cycle()` anyway** — it is what the desktop wheel drives (free, natural) and what a gamepad shoulder button will drive. It is just not the primary model. Muscle memory transfers because both platforms use the same index in the same left-to-right order.

### 7.2 What should change in `HandSlots.gd`

The model is right. Four additions:

1. **`use_grammar() -> int`** (§2.4) — the touch layer needs the grammar, not just the action name.
2. **A stable, typed slot order.** `rebuild()` emits `[FISTS, weapon?, PRIMARY, AREA, MOBILITY, SIGNATURE]`. The companion spec's typed slots become an *ordering guarantee* rather than a separate system — this is what makes tap-position muscle memory survive a class change (slot 4 is always "get out of trouble", on Cryomancer and Brawler alike). It is also where blink lands if CUT 3 takes option two.
3. **`auto_return: bool = true`** (§6.4).
4. **`pin()`** — defeats auto-return; long-press the square on touch, hold the number key on desktop.

Keep the `wrapi` wrap; keep cooling slots selectable (the comment at line 117 is right — hiding a slot would make the bar lie about what you own). `auto_return` is what stops "selectable while dead" from producing a dead USE button.

### 7.3 Does selection belong in combat?

**Yes for the bar — it is your hand, not a menu.** Weapons are picked up mid-fight (the Stick-Fight fantasy), and `HandSlots` correctly puts FISTS at index 0 as the never-strandable panic option.
**No for the loadout** — *which* four spells you carry is a grimoire decision, made out of combat, exactly as the companion spec argues.

**The bar is what you are holding; the grimoire is what you brought.**

---

## 8. DOMAIN TELEGRAPHS (maker decision 3)

Arena-scale, not a body effect. `scripts/combat/Atmosphere.gd` is the natural home; this should be **one component driven by the spell's windup progress**, not per-spell art, or 26 spells become 26 telegraph implementations.

`Atmosphere.domain_telegraph(centre, radius, colour, duration)` drives five layers off a single `0→1` progress:

| layer | behaviour | role |
|---|---|---|
| **ground circle** | a world-anchored magic circle grows to the domain radius over the windup | **this is the dodge information** — its edge is the boundary |
| **sky / backdrop** | ramps toward the element colour | the fantasy; readable in peripheral vision |
| **mist / motes** | roll inward across the whole room toward the centre | direction cue — tells you where the centre is without looking |
| **audio** | rising sub-bass + `charge_up` pitched down | the tell you get with your eyes on your own character |
| **camera** | `Juice.zoom_pull_camera` — already used at `_begin_channel:1090` | reuse verbatim |

**The flow-critical consequence of removing the root:** because the caster now MOVES during the cast, **the circle must be anchored to the world at cast start, not to the caster.** A telegraph that slides around with the caster is not dodge information — the boundary would keep moving out from under the player who is trying to leave it. This is non-obvious and it falls straight out of maker decision 1.

Two more consequences worth building in from the start:
- **Co-op:** the boundary needs an ally-readable colour, since "inside or outside" is a shared decision.
- **The caster is now dodgeable-adjacent too.** A moving caster inside their own growing domain is a legible, dramatic image — and it means the domain should damage *by area*, not by "everyone who was in range at cast time", or the movement is cosmetic.

---

## 9. BUILD ORDER

Each phase is felt at F5 before the next starts.

| phase | contents | risk | why here |
|---|---|---|---|
| **0 — verify** | Headless test locking the just-landed `TouchControls` fixes: JUMP presses `jump` (not `move_up`), HIT presses `melee`, PARRY presses `parry`. Extend `tools/slice_test_touch.gd`. | none | lock the regression before the file is rewritten |
| **1 — DEFENSIVE BUDGET** | §5 CUTs 1–4 as part of wiring `ParryRing` into `Hero` (it is unwired today, so these land as *design*, not as a nerf to something shipped). Plus §3.2's guard-suppresses-use rule. | medium | everything downstream is balanced against this; doing it later means re-tuning twice |
| **2 — FLOW** | §6.1 unroot casts (the full site list), §6.2 buffer during windups, §6.3 duck stops eating defence, §6.5 dash-cancel, §6.7 momentum. **`Hero.gd` + rig `set_float_offset`. Desktop only.** | medium | the maker's stated priority, felt the instant you F5 |
| **3 — THE HAND** | `HandSlots` wired to `SpikeFigure` in the playground + the bar renderer + LMB/RMB/wheel/1–6 + `use_grammar()` + `auto_return` + **fists get the drag** (§5.6). **Desktop only — the drag already exists there.** | low (playground) | tests the whole thesis at desktop prices; also the connective tissue that makes phase 2's cooldowns survivable |
| **4 — THE THUMB** | The fused touch drag zone (§4.2), the three grammars, ghost previews, the guard band (§4.3), and **delete the `Targeting` aim path** (§6.6 — required; auto-aim fights the drag). `TouchControls` with `force_visible` in the playground. | medium | first real mobile work, against a model already proven on desktop |
| **5 — THE GESTURES** | Dash flick + instrumentation (§4.5), jump-on-stick-up (§4.1), `Tuning` flags for both. | high (feel) | the only genuinely unproven interactions; isolated so they can be switched off without unpicking anything |
| **6 — DOMAINS + HERO** | §8 telegraph component; port phases 3–5 onto `Hero` + `AbilityBar`; placed-spell point from `origin + aim × reach`. | real | last, on a model felt four times by then |

---

## 10. What will feel bad, and why

1. **The first ten minutes on touch will be worse than today.** Losing auto-aim means missing things you used to hit. That is the price of the drag and the no-auto-aim rule. It recovers; do not mistake it for a bug.
2. **You cannot re-aim while guarding.** Your heading freezes for the guard's duration, so a baited guard leaves you facing the wrong way. That is the intended punish, and it will feel bad on purpose.
3. **60–90 ms of thumb travel to the guard band is not free.** Against a genuinely unreactable attack you will be late. The ring's 0.33 s lead absorbs it; a *surprise* still beats you, which is correct.
4. **CUT 1 will read as a nerf even though sustain never shipped.** Turtling at 35 % forever *feels* good and losing it feels like losing something. It is the difference between the game having a defensive decision and not having one.
5. **The right thumb's grammar changes with the slot.** Sword: letting go does nothing. Spell: letting go fires. Some casts will be accidents. The glyph, the ghost and auto-return reduce this; nothing eliminates it.
6. **The dash flick will misfire in the first hour.** The tap primer is a strong filter, not a proof. This is why §4.5(7) demands a counter rather than a vibe.
7. **Jump-on-stick-up will produce accidental jumps** on a diagonal run start. The `−0.62` threshold and hysteresis reduce it; the rate gate is the next lever.
8. **Placed-spell reach is strictly worse on mobile than on desktop.** Desktop keeps the cursor and gets a point; mobile gets a direction and a radius. An honest asymmetry, and the correct direction for one to run.
9. **Bar squares are small and you will miss under pressure.** The oversized hit rect helps; under `auto_return` a missed tap at least always means "swing the weapon" rather than something random.
10. **Unrooted casting may make the big spells feel less momentous.** The root was doing dramatic work as well as balance work. §8's environmental telegraph is what has to replace that weight — if domains do not feel enormous after unrooting, the answer is more arena-scale telegraph, not the root coming back.

---

## 11. Open questions for the maker

1. **Guard suppresses attacking on BOTH platforms (§3.2)?** This is the single most consequential recommendation here. (Recommend yes — the alternative is a free 35 % DR while attacking on desktop.)
2. **Guard on the right thumb (§3.3)?** It reverses the obvious answer and my own first draft. (Recommend yes — you must move while guarding; you must not attack while guarding.)
3. **CUT 3 — does blink lose its i-frames, or become the MOBILITY slot spell?** (Recommend the slot; it competes rather than being free, and the typed-slot order already makes room.)
4. **CUT 1 — guard meter, or just a decay + movement penalty?** A meter costs a HUD element but gives enemies a guard-break, which is a good spectacle and a good tell.
5. **Cast movement penalty of 70 % / 55 % (§5.7)?** Wants a `Tuning` entry from day one; it is the biggest feel knob in the flow work.
6. **Fists get the drag (§5.6)?** (Recommend yes — otherwise the one slot you are guaranteed to always have is the one that is not fun.)
7. **Dash flick default ON or OFF for playtest 1?** (Recommend ON, so the misfire counter gets real data.)
