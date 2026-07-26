# Stick Fight Feel — Bucket A: the safe parity wins

**Date:** 2026-07-26
**Branch:** `v2.0-tower`
**Status:** design → awaiting maker review → plan → build (Fable)

## Why this exists

A grounded Stick Fight → what-we-have comparison (built off `docs/references/stick-fight-feel-study.md` + a full code inventory) found the combat is ~90% of the way to SF feel on paper, with one **keystone gap** and a handful of cheap, directionally-certain wins. This spec is the six "build without needing a playtest first" items. Everything here is SF-correct *regardless of feel-taste* — the amplitudes are then tuned live at F5 via `tuning.tres`.

Two items carry **mild rebalance risk** and are called out explicitly (hitstun-on-hero, enemy-gravity-parity). Everything else is additive.

Non-goals (Bucket B, deferred to a maker feel-call): air-control philosophy fork, true physics-body ragdoll, dash i-frame generosity, weapon-scramble chaos.

## The six changes

### 1. Hitstun / stagger — THE keystone

**Problem:** a hit adds damage-%, applies knockback, and plays a cosmetic `rig.flop()` — but the victim's AI/input never pauses. Enemies keep swinging through your hits; the inventory itself notes "trades feel mushy." This is the single biggest thing separating "a punch that registers a number" from "a punch that *connects*."

**Design:** a `_hitstun` timer on both `Hero` and `Enemy`. On a solid hit (knockback magnitude ≥ `hitstun_min_kb`), set:

```
stun = clampf(hitstun_base + hitstun_scale * (knockback_mag / 600.0), 0.0, hitstun_cap)
_hitstun = maxf(_hitstun, stun)   # max(), never additive → no infinite lock
```

While `_hitstun > 0`:
- **Enemy:** skip the AI act/attack/decision step; knockback velocity + flop still carry the body (it flies and flails, just can't *choose* to attack).
- **Hero:** same, but scaled by `hitstun_hero_mult` (default **0.5** — players hate losing control; keep it light and let dash/blink i-frames remain the skill-out).

**No stun-lock, by construction:** `max()` not sum, hard `hitstun_cap`, and higher damage-% already means bigger knockback → the victim flies further out of range → natural diminishing returns. No artificial post-stun immunity (SF has none — separation does the work).

**Synergy:** the existing `flop()` already fires on the same event. Hitstun is the *control lock* layered on the flop — together they are the SF knockdown. Zero new visual work.

**Knobs:** `hitstun_base=0.12`, `hitstun_scale=0.14`, `hitstun_cap=0.32`, `hitstun_hero_mult=0.5`, `hitstun_min_kb=180`.

**Decision for maker:** hero gets hitstun too (SF-accurate, consistent) but light (×0.5). Alternative: hero immune, enemies only (more power-fantasy, less fair/consistent). *Recommend: light hero hitstun as specced — it's a knob, trivially tuned to 0 at F5 if it feels bad.*

### 2. Rotational camera shake

**Problem:** trauma shake is offset-only. The feel study is explicit: *rotation reads as far more violent for the same magnitude* — it's the cheapest juice win we're missing.

**Design:** in `CombatCamera`, add `rotation = MAX_ROLL * trauma*trauma * noise3 * shake_scale`, third noise channel, eased back to 0 as trauma decays. `MAX_ROLL = deg_to_rad(shake_roll_deg)`. Respects the existing shake slider (`shake_scale`).

**Knob:** `shake_roll_deg=3.5`. (First: confirm in code the camera doesn't already touch `rotation` anywhere; if it does, compose, don't clobber.)

### 3. Impact-scaled landing

**Problem:** landing fires a fixed `shake_camera(2.5)` + puff regardless of fall speed. SF sells weight by scaling the land to the *impact*.

**Design:** on hero touchdown, read the landing `velocity.y`. Above `land_min_speed`:
- **Squash** the rig (scale.y ×`land_squash` ≈ 0.82 → ease back over ~90ms), reusing CharacterRig's existing squash-pop mechanism (currently ×1.12 on melee).
- **Shake** scaled by fall speed: `add_shake(remap(vy, land_min_speed, move_max_fall, 1.0, land_shake_max))`.
- Bigger dust puff on hard landings.

**Knobs:** `land_min_speed=520`, `land_squash=0.82`, `land_shake_max=5.5`.

### 4. Enemy / hero gravity parity

**Problem:** enemies fall under gravity 1500 (max fall 950); the hero under 2600↑/3000↓ (max fall 1400). Enemies visibly **float** relative to you in the same air — breaks the "uniform physics" feel and reads slightly wrong.

**Design:** enemies read the same gravity/max-fall tuning knobs as the hero. **To preserve enemy reach**, derive enemy `jump_velocity` from the new gravity so leap *heights* stay constant (`v = -sqrt(2*g*current_leap_height)`) — enemies fall at your rate without shortening their jumps/leaps.

**Risk (mild):** changes enemy air time → telegraph/dodge timing shifts slightly. Flagged for an F5 dodge-feel check. Fully knob-gated so it can be reverted live.

### 5. Hit-stop stacking

**Problem:** `Juice.hit_stop` sets `Engine.time_scale = 0.05` on an await; overlapping stops (multi-kill, cleave) each set it and the *first* timer to expire restores 1.0 — truncating later freezes.

**Design:** track a single `_hitstop_until` target time; each call extends it via `max(current, now + dur)`; one running loop restores `time_scale = 1.0` only when `now >= _hitstop_until`. Overlaps now *extend* rather than cut short.

### 6. Tuning cleanup (the F5 enabler)

**Problem:** `move_accel` is declared but never read (ground accel is a hard const — not actually tunable despite the comment). `tuning.tres` pins only 6 of ~18 fields, so the inspector hides most knobs — an F5 tuning pass is a scavenger hunt.

**Design:**
- Wire `move_accel`: Hero ground accel reads `_tune("move_accel", GROUND_ACCEL)`.
- Pin **all** fields in `tuning.tres` (existing + the new hitstun/roll/landing knobs) so every feel value is visible + live-editable in the inspector.
- Fix the stale `Hero.gd` comments (air_accel says "strong air control (Stick-Fight)" while the value is deliberately low — the comment should state the *actual* philosophy so the air-control fork is an honest, visible decision, not a buried contradiction).

## Testing

- Extend/author headless suites under `tools/`: a `slice_test_hitstun.gd` (stun set on hit, cleared on timeout, capped, hero-mult applied, `max()`-not-additive invariant), plus assertions that hit-stop stacking extends rather than truncates.
- Full existing `tools/slice*_test_*.gd` sweep stays green (SP byte-identical; co-op gated on `Net.is_active()` — none of these touch net paths).
- `--headless scenes/Main.tscn --quit-after 180` boot check clean.
- Gopeak GPU capture where a change is visible (landing squash, camera roll) — but **feel is F5-only**; the deliverable of this spec is a build where F5 is a *tuning* pass, not a *is-it-broken* pass.

## What "done" means

Every hit **commits** the victim (hitstun), the camera **rolls** on big shakes, landings **scale** to impact, enemies **fall like you do**, overlapping freezes **stack**, and **every feel value is a visible knob in `tuning.tres`**. Then one maker F5 dials amplitudes — including revisiting the Bucket B air-control fork with real hands on the pad.
