# Stickman Physics-Rig Spike — Design Spec

**Date:** 2026-07-25
**Branch:** `v2.0-tower`
**Status:** Approved (maker), ready for implementation plan.
**Type:** Throwaway de-risking spike (isolated; no game code touched).

---

## 1. Problem & goal

F5 playtest of the current stickman rejected it as "not Stick Fight enough." The maker's directive: **rewire the stickman completely so it follows gravity, has individual physics limbs, and moves exactly like Stick Fight — research how Stick Fight does it and copy it.**

A full rewrite of the character system is high-risk (the same technique lands as snappy *Stick Fight* or floppy *Gang Beasts* depending entirely on tuning) and has a large blast radius (see §7). So we **de-risk with a throwaway spike first**: build the candidate rig(s) in an isolated test scene, F5 to judge the feel, and only then commit to rewiring `Hero`/`Enemy`/`Boss`.

**Maker decisions locked:**
- Sequence: **spike first**, then commit.
- Scope of spike: **build BOTH candidate architectures (A and B) side by side** and pick the winner by feel.

---

## 2. Why the current rig hit a ceiling

`scripts/combat/CharacterRig.gd` (1585 lines) is a **draw-only procedural rig**. Its "ragdoll" is a point-mass spring simulation in *draw space* — deliberately **not** real physics bodies (the header comment says RigidBody2D/PinJoint2D "explode and fight the kinematic controller"). Consequences:
- Limbs droop/trail visually but never become real bodies that collide or fly apart.
- On hit/death the drawn limbs go limp, but the body does not tumble as a real ragdoll.

That draw-space ceiling is what the playtest felt.

## 3. How Stick Fight actually works (research summary, sourced)

- Landfall's characters (TABS/Stick Fight share one system) are **always a physics ragdoll, continuously driven toward a target pose by strong, damped corrective torques**, plus an **uprighting force** on the torso/head and a **balance handler** on the feet. (Game Developer feature on Landfall's physics-animation system.)
- **"Alive" and "dead" are the same simulation.** Death/knockback simply **switches the corrective forces off** — the same body goes limp and flies. No separate ragdoll prefab / state swap.
- **Snappy vs floppy is entirely the strength/damping of those corrective forces** — identical architecture to Gang Beasts, just stronger and better-damped gains.
- **Locomotion:** legs receive torque from animation curves (a procedural shuffle); foot-to-floor contact plus a torso velocity assist propel the body; lean emerges from the balance handler; airborne the standing/balance handlers can't fire, so limbs dangle under gravity (matches the maker's "grounded=planted, airborne=loose" directive).

### Godot 4.6 reality that shapes the implementation
- Godot 2D physics has **no joint motors and no angular limits** (unlike Unity `HingeJoint2D`); `PhysicalBone2D` is **passive-only**.
- Therefore we **hand-roll the drive**: each limb is a `RigidBody2D`, and every `_physics_process` we apply torque toward its target angle:
  ```
  error  = wrap(target_angle - body.rotation)          # shortest signed angle
  torque = stiffness * error - damping * body.angular_velocity
  body.apply_torque(clamp(torque, -max_torque, max_torque))
  ```
  `stiffness` is the single snappy↔floppy dial. Segments hang together via `PinJoint2D`; hyperextension is bounded by a soft angular PD limit we add ourselves. Stability: raise 2D solver iterations, run physics ≥60 Hz, clamp torque and angular velocity.

## 4. Architecture options & decision

| | **A — Hybrid** | **B — Full active ragdoll** |
|---|---|---|
| Torso | Kinematic `CharacterBody2D` (keeps the tuned snappy movement) | Driven `RigidBody2D` with uprighting + stand + balance forces |
| Limbs | Real `RigidBody2D`, PD-driven to pose; go limp + fly on hit/death | Same |
| Feel | Snappy by construction; limbs overshoot/settle + real ragdoll on hit | Most authentic (torso is physics too) |
| Risk | Low — mobile-touch + co-op-netcode friendly; **promotable to B later without redoing the limb layer** | High — no Godot 2D motors to lean on; hardest to keep snappy; real floppy risk; roughest on touch + netcode |

Research recommendation is **A** (the two things that *read* as Stick Fight — PD limbs that overshoot/settle, and whole-body ragdoll fly on hit — are both delivered by A at a fraction of B's risk). **Maker chose to build BOTH in the spike** and decide by feel, since the whole point of a spike is to remove doubt cheaply.

## 5. Spike design

### 5.1 Isolation & safety (non-negotiable)
- All spike code lives in a new **throwaway `spike/` namespace**: new scene + new scripts only.
- **Zero edits** to `Hero`, `Enemy`, `Boss`, `CharacterRig`, or any existing game file.
- Cannot destabilize the game; worst case the folder is deleted. The winning *approach's PD-limb code* is reused by the later real rewrite, but the spike files themselves are disposable.
- Launch: run the spike scene directly; the spike window is pinned to a visible on-screen position/size (the earlier off-screen-window problem is explicitly handled).

### 5.2 Scene & controls
- One test scene: flat floor + a couple of platforms + a wall (exercises grounded / airborne / collision).
- **Two stick figures side by side — LEFT = Approach A, RIGHT = Approach B — both receiving the same input simultaneously** for direct comparison. Big on-screen `A` / `B` labels.
- Controls: move/jump (WASD or arrows), mouse to aim, click = punch, **H** = take a hit (fires a knockback impulse to watch each ragdoll fly), **K** = kill / full-limp, **R** = reset.

### 5.3 The two figures share one "muscle"
- Both figures are built from the **same 10 physics segments**: head, torso, 2-segment arms (upper + forearm, bending elbow), 2-segment legs (thigh + shin, bending knee), pinned together — real individual limbs under real gravity.
- **Shared PD-limb module** (the reusable core): each limb PD-driven toward a target angle (aim → lead arm; run-cycle sine → legs; velocity → lean). Airborne → stiffness drops so limbs dangle/trail. Hit/death → drives off → real ragdoll fly. **This is the code the eventual full rewrite reuses**, so the spike is not throwaway effort — only the harness around it is.
- **A (left):** torso kinematic (movement math shaped like the current Hero controller — gravity rise/fall, jump, air accel), limbs are the physics layer above it.
- **B (right):** torso is a `RigidBody2D` with an uprighting torque + a stand-up force (grounded) + foot-balance repositioning — the full Landfall model.
- **Open design point (to be answered by the side-by-side):** in A the torso is kinematic, so "whole-body fly on death" is knockback-velocity on the torso + limbs ragdolling behind it, rather than B's true full-body physics tumble. If A's death read is unsatisfying next to B, that is exactly what the comparison surfaces (and the promote-A's-torso-to-physics path is available).

### 5.4 Live tuning (the whole game)
On-screen, adjustable live via keys, with current values displayed:
- Both figures: **limb stiffness, damping, max torque**.
- B additionally: **uprighting strength, stand force, balance strength**.

The objective is to find the gains where limbs **overshoot and settle** (Stick Fight) rather than flail (Gang Beasts) or lock rigid (puppet). Numbers are found by feel in the spike; there are no published Stick Fight values.

### 5.5 Success criteria (what F5 judges)
For each figure:
1. Runs and lands feeling **weighty but snappy**.
2. Shows **loose, trailing limbs in the air**.
3. **Flies as a believable ragdoll when hit (H)** and settles / recovers.
4. Reads as a proper **Stick Fight figure** (silhouette, individual bending limbs).
5. **Verdict: which of A or B nails it** (or what tuning gets it there).

## 6. Out of scope for the spike
- No integration with `Hero`/`Enemy`/`Boss`, spells, gear, aura, equipment textures, or the melee `hit_frame` damage contract.
- No enemy AI, no run loop, no co-op, no mobile touch layer (the winning approach's real rewrite handles these).
- No polish/VFX beyond what's needed to judge motion.

## 7. Blast radius the real rewrite must respect (recorded now, used later)
The recon mapped the full integration surface so the post-spike rewrite plan can preserve it. Key contracts that must survive the eventual swap of `CharacterRig`:
- **`hit_frame` signal drives ALL melee damage** (`Hero._on_melee_hit_frame`, Hero.gd:1873) — timing must be preserved.
- **`get_weapon_tip()` / `get_lead_hand_global()`** are spell/VFX emission points.
- **`is_striking()`** gates Hero facing during a strike.
- **`spawn_ghost`** is reused for dash trails AND death corpses.
- Per-instance **`height`** scaling (Boss sets 95).
- Full public API (play/set_facing/set_aim/set_body_velocity/set_grounded/set_air_phase/flop/set_limp/apply_impulse/set_tint/flash/set_equipment/class_preset/set_aura/…) is the swap contract — enumerated in the recon report.
- Headless test pattern: rig tests instantiate `RigScript.new()` and drive `advance(delta)` directly; a physics-body rig needs an equivalent headless-drivable stepping path.

## 8. Parked backlog (diagnosed, fixes ready — NOT in this spike)
Triaged during recon; to be picked up after the rig direction is chosen:
1. **No knockback on basic moves** — knockback IS wired (Hero.gd:1896, Spell.gd:155) but enemy chase-drive re-grounds them every frame and impulses are horizontal-only (no pop-up). Fix: add a brief staggered state + a vertical launch component.
2. **Percentages mean nothing** — `ringout_knockback_scale` (Hero.gd:1943 / Enemy.gd:271) is weak+linear (`1 + pct/100`) and horizontal-only. Fix: superlinear curve + %-scaled launch angle.
3. **Too many mobs at start** — `VersusArena.BOT_COUNT=5` (line 34) + `DUMMY_COUNT=2` (line 82) + summoner minions. Fix: lower counts.
4. **Map not destroyed** — the landscape is intentionally permanent; only 2 small 64px cover blocks + 1 platform break, and they chip slowly (max_hp 120). Fix: more/faster-breaking cover, or make terrain destructible (design change).

## 9. Testing
- Per-figure **headless stability smoke test**: instantiate + step N physics frames, assert no NaN / no positional explosion (matches the project's headless discipline; proportionate to a throwaway spike).
- Manual F5 feel test against §5.5.

## 10. File structure (all throwaway)
- `scenes/spike/RigSpike.tscn` — test scene (floor, platforms, wall, two figures, HUD).
- `scripts/spike/RigSpikeController.gd` — input, HUD, live tuning; drives both figures.
- `scripts/spike/PdLimb.gd` — shared PD-drive limb helper (the reusable core).
- `scripts/spike/HybridFigure.gd` — Approach A.
- `scripts/spike/ActiveRagdollFigure.gd` — Approach B.
- `tools/spike_test_rig.gd` — headless stability smoke test.

## 11. Next steps after the spike
1. Maker F5s the spike, tunes live, delivers the verdict (A or B, and the winning gains).
2. Write the **real rewrite** spec + plan for the chosen approach, honoring §7's contracts, with per-task headless + F5 verification.
3. Return to the §8 backlog.
