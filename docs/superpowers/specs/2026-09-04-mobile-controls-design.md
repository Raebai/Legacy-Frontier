# Mobile controls — cutting the hand down to a thumb

**Date:** 2026-09-04 · **Status:** design, approved to build · **Branch:** `bot-fight-quality`

Maker: *"we are concerned with how mobile players will play the game given it has buttons
and facing and movement with dashes and stuff, we dont want to overwhelm them with
buttons"*.

---

## 1. The problem, in numbers

`TouchControls.gd` (870 lines) currently puts **two sticks and seven buttons** on a
640×360 screen:

| | what | knobs |
|---|---|---|
| left stick | move, duck past 0.6, optional up-to-jump (off) | `JOY_RADIUS 66`, `JOY_DEADZONE 0.18`, `JOY_DUCK_THRESHOLD 0.6` |
| right stick | aim, **and fires** past 0.55 | `AIM_RADIUS 52`, `AIM_FIRE_THRESHOLD 0.55`, `AIM_STICK_FIRES true` |
| buttons | jump, dash, parry | `_button_layout()` |
| spell arc | four slots on a thumb arc | `SPELL_ARC_ANGLES [0, 30, 60, 90]` |

Nine touch targets, two of which are sticks that must be *held*. The file's own header
already names the squeeze:

> THE TWO-THUMB QUESTION. With the aim stick firing, the right thumb has two jobs: hold
> the stick to spray the primary, or lift onto a spell button.

That is the bug. It is not a layout problem to be tuned — it is one thumb with two jobs.

⚠ **Every constant above is an untested guess. No mobile build has ever been made — not
a failed one, zero.** Nothing in this document is validated by a device.

## 2. Why the obvious references do not apply

The game is a **side-on platform fighter**: gravity, jump, dash, terraces, ring-out
(21 gravity/jump/floor call sites in `Hero.gd`). That rules out most of what gets cited
for mobile action games.

- **Soul Knight** — the project's stated feel reference — is *top-down*. Its left thumb
  does coarse work, so it can spare attention. On a platformer the left thumb is doing
  **precise** work: ledges, spacing, dash timing, not falling off. It cannot help.
- **Twin-stick** schemes assume aiming is the primary skill. Here the primary skill is
  *positioning*.

The references that actually transfer are the ones built for this shape:

- **Brawlhalla** ships a real platform fighter on mobile: a stick and a few buttons, with
  the **stick direction changing what each button does**.
- **Super Smash Bros** is the same idea and the origin of it — ~5 buttons, dozens of
  moves, because direction modifies the button.
- **Brawl Stars** solves aiming without an aim stick: **tap to fire with assist, drag to
  aim manually, release to fire**.

## 3. The four techniques

1. **Direction × button.** The stick you are already holding multiplies your buttons.
   Three buttons × (neutral / up / down / back) is twelve actions from three targets.
   The current scheme already does a weak version: stick-down is duck.
2. **Tap vs drag on one button.** Tap = assisted, drag = aimed. One button serves both
   the person who wants speed and the person who wants precision.
3. **Verbs that should not be buttons.** Dash → a flick of the stick. Revive → a button
   that only exists when you are over a downed ally. Ultimate → a button that only exists
   when it is charged. *A button that is not there costs no attention.*
4. **Cut the kit; do not port it.** `THE-TOWER-mobile-plan.md` already says this:
   *"Trim 8 buttons → 3 spells + dash"*, *"Trim `CLASS_KITS` from 5 roles to 3 per class"*.

## 4. The scheme

**Kill the aim stick.** It is what eats the right thumb, and a fighter does not need one
— Smash and Brawlhalla have no aim control at all. Removing it frees the entire right
side for buttons and removes the "hold or lift?" conflict the header describes.

| Desktop verb | Mobile |
|---|---|
| move / duck | left stick (unchanged) |
| **dash** | **flick or double-tap the stick** — no button |
| jump | JUMP button — the most-pressed verb, must be dead reliable |
| cast (held) | **ATTACK**: tap = assisted, drag = aim + release, hold = charge |
| melee | folded into ATTACK when a target is inside melee range |
| **parry** | **cut on mobile** — dash already carries i-frames; that is the defensive verb |
| spells | **two SPELL buttons** — the equipped loadout *is* the control scheme |
| ultimate | contextual — appears only when charged |
| revive (`talk`) | contextual — appears only near a downed ally |
| switch_class | hub only, never in combat |

**Result: one stick + four thumb targets** (jump, attack, spell A, spell B), occasionally
five. That is the same order as Brawl Stars and Soul Knight.

### Facing

Follows movement while walking; follows the drag while aiming. There is never a manual
facing control — the maker's "facing" concern is answered by removing the question.

## 5. The aiming decision, and the conflict it carries

⚠ **This contradicts a previous maker ruling of "NO auto-aim"** (recorded in the spell
redesign notes). It is called out here rather than buried.

The proposal is *not* auto-aim. It is **per-shot, player-chosen** assistance, the Brawl
Stars resolution: a tap fires at the obvious target, a drag aims by hand. Nobody has aim
taken away from them; the assisted path is simply the default for a thumb that is also
steering.

If the maker holds the line, the fallback is **drag-only** — the same button, no tap
shortcut. It costs fluency on a small screen and nothing else. **This is a maker
decision, not an engineering one.**

## 6. What cutting parry costs

Parry is a real verb: `Hero` reads it in three places, and the bots parry. Removing it on
mobile means:

- mobile and desktop combat are no longer identical, so balance work has two targets;
- a defensive option disappears, and dash i-frames must carry the load;
- bot parry behaviour is unaffected — bots do not use the touch layer.

The alternative is keeping parry as a fifth button and accepting the crowding. **Cut it
by default, behind a constant, so a device pass can put it back in one line.**

## 7. Implementation

Order matters: each step is playable on its own, and each is revertible by a constant.

1. **`AIM_STICK_FIRES = false`, then remove the aim stick.** `Hero._aim_point` /
   `TOUCH_AIM_DEADZONE` already hold the last aim below the deadzone, so nothing flings
   when the stick disappears. Facing falls back to movement.
2. **Dash on a stick flick.** New knobs on the left stick: a speed threshold and a
   re-tap window. Removes the dash button.
3. **Trim the spell arc 4 → 2**, plus a contextual ult slot. `SPELL_ARC_ANGLES` shrinks;
   the arc geometry is already derived rather than hand-placed, so the buttons stay a
   thumb-sweep apart with no re-tuning.
4. **ATTACK: tap / drag / hold.** The one genuinely new mechanic. Tap resolves a target
   assist; drag sets `aim_point` directly; hold feeds the existing charge path.
5. **Contextual buttons** for ult and revive — draw only when the verb is live.
6. **Direction × ATTACK** (up / down / neutral) — last, because it is the piece most
   likely to need device feel.

**Touched:** `scripts/combat/TouchControls.gd` (layout + input), `scripts/combat/Hero.gd`
(aim path only), `scripts/combat/AbilityBar.gd` (already stands down on touch).
**Not touched:** desktop input, the action map, `PadController` — all three stay
byte-identical, which is the same guarantee the pad work kept.

## 8. Testing

`TouchControls` already carries 12 headless tests. Extend, do not replace:

- every verb in §4 is reachable — the mobile equivalent of the pad's
  "layout covers every action a hero reads" test;
- no two touch targets overlap at 640×360 **or** at a 21:9 logical viewport (`expand`
  widens it to ~853×360, which is where a corner button drifts);
- thumb targets stay ≥ the locked 46 px (D-011);
- the dash flick cannot fire from a resting stick (the deadzone equivalent of the pad's
  "a resting stick walks nobody").

⚠ **A green suite is not a working game.** None of this is felt until it is on a phone.

## 9. Out of scope

Class kit trimming (5 roles → 3) is its own data change and its own spec. Landscape-only
lock, pause reachability on touch, and the mobile renderer/perf pass are Phase 6 of
`THE-TOWER-mobile-plan.md` and stay there.

## 10. The blocker

**An APK cannot be built on this machine today:** no Android SDK
(`%LOCALAPPDATA%/Android/Sdk` does not exist), no JDK on PATH, no debug keystore. The
Android export preset exists and the export templates are now installed, so once the SDK
and a JDK are present the build is one command. Until then this spec ships to desktop
only, where the touch layer can be previewed with `TouchControls.force_visible`.
