# Stick Fight Feel Foundation — Design Spec

**Date:** 2026-07-23
**Branch:** `v2.0-tower`
**Status:** design — awaiting maker approval before implementation
**North star:** copy **Stick Fight: The Game** for movement/rig feel; **Super Smash Bros** for the stadium + ring-out.

## Why this exists

The maker playtested the current build and found it does not feel like the target. A 6-agent read-only audit + GPU screenshot capture traced every complaint to a concrete root cause. The Smash "bones" already exist (side arena, `stocks`, ring-out pits `StageHazard`, destructible cover, bot spawns) but are buried under an intro→hub→tower wrapper, and the **feel layer** is broken. This spec covers **Push 1: the feel foundation** — make it a bold, grounded, weighty stickman brawler you spawn straight into and can F5-feel. The spell-picker (free-pick loadout + emergent class name) is **Push 2**, its own spec.

## Locked decisions (maker, 2026-07-23)

1. **Death model = Smash % + ring-out.** No HP depletion. A damage % builds as you get hit; higher % = you fly farther; you're eliminated only by being knocked off the stage. `stocks` already exist.
2. **Spell/class = free-pick with emergent name** — deferred to Push 2.
3. **Sequence = feel foundation first**, one tight loop, maker F5s before Push 2.

## Audit root-cause reference (file:line)

- **Floating/flying:** always-on ragdoll spring smears every pose (`CharacterRig.gd:328-335`, `_sim_pose` at :658; `STIFFNESS=60`/`DAMPING=8`/`MAX_OFFSET_FACTOR=0.85` at :92-102). No JUMP/AIR state in the enum (`CharacterRig.gd:9`); Hero picks only RUN/IDLE ignoring `is_on_floor()` (`Hero.gd:624-625`). Soft rise gravity `GRAVITY=1500` (`Hero.gd:19`, apex ~0.39s); air control `AIR_ACCEL=1450` (`Hero.gd:29`) lets you free-steer mid-air.
- **Hands don't track mouse:** aim is wired (`Hero.gd:341,648`) but only applied in IDLE/RUN (`CharacterRig.gd:1159`) and the drawn hand is the lagging simulated spring value.
- **Not stickman enough:** thin limbs `w=height*0.12`, head `r=height*0.15` (`CharacterRig.gd:1062-1063`), soft rim outline (`:76-77`).
- **Self-damage bug:** `_primary_bolt` sets `spell.caster` **only when `bolt_heal>0`** (`Hero.gd:1414-1417`); for MAGE/STORMCALLER/ROGUE the caster is null so the friendly-fire guard `node != caster` (`Spell.gd:147`) excludes nobody, and the bolt spawns on the caster's body. Co-op-only (SP branch is gated off) but fix regardless.
- **Click/melee weird:** swing gated on cursor-cone `facing.dot(toward) <= _melee_arc_dot` (`Hero.gd:1838`) so it whiffs unless the mouse is aimed at the target even point-blank; impact waits to 55% anim frame; no lunge/arc VFX on the bare fists.
- **Death/ring-out:** HP at `Hero.gd:215-216`, death `if hp==0: _die()` at `:1967-1968`; HP bar drawn by `CharacterBars.gd` configured at `Hero.gd:363-365`. Ring-out primitive `StageHazard.gd` (PIT `Area2D`, emits `fighter_fell`) already wired into `VersusArena.gd:313-323` with stock/respawn at `:159-200`. Knockback is a decaying additive channel scaled by `knockback_mult` (default 1.6) at `Hero.gd:1892`.
- **Boot flow:** main scene = `Lobby.tscn` (`project.godot:19`) → hub `Main.tscn`. Armory instantiated at `World.gd:184-186`. `VersusArena.tscn` is a self-contained Smash stage that already spawns hero + 5 bots + destructible cover + ring-out pits.

## Push 1 workstreams

### A. Strip to the sandbox (unblocks F5 testing)
- Repoint `project.godot:19` `run/main_scene` → `res://scenes/combat/VersusArena.tscn`. Keep `Lobby.tscn` on disk for later co-op.
- Hide the Armory: early-return the instantiation at `World.gd:184-186` (loft platform stays).
- Add **practice dummies**: 2-3 stationary, zero-aggro, knock-out-able targets near the hero spawn in VersusArena, visually distinct from the 5 live bots, so melee/spells register clean hits on a passive target.
- **Bigger, bolder figures** (see B silhouette).

### B. Stickman feel (`CharacterRig.gd`)
- **Tame the ragdoll drift:** raise `STIFFNESS`, lower `MAX_OFFSET_FACTOR` so limbs settle to the pose; keep looseness only as a brief post-hit flail via `flop()`, not the resting state.
- **Foot-planting IK:** raycast each foot to the actual floor/platform Y; lock the stance foot in world space during its ground phase of the run cycle. This is the single biggest fix — kills "floating," makes the run read, and makes the figure interact with the environment.
- **Add a JUMP/AIR state** to the `State` enum; Hero selects it on `not is_on_floor()`: tuck on rise, reach on fall, squash on land.
- **Arm snaps to aim:** bypass/stiffen the spring for the lead hand when `aim_arm`; track the cursor in air/dash/cast too, not just IDLE/RUN.
- **Bolder silhouette:** fatter limb width, larger head, a true dark keyline outline (Stick Fight's bold black puppet), scaled up so the figure isn't a tiny speck.

### C. Movement weight (`Hero.gd` consts — starting targets, maker tunes)
- `GRAVITY 1500 → ~2600` (rise), `GRAVITY_FALL 2100 → ~3000`, `MAX_FALL 1000 → ~1400`, `JUMP_VELOCITY -580 → ~-740`, `AIR_ACCEL 1450 → ~750`.
- Wire these to live `TuningConfig` knobs so the maker can dial feel in-run without a recompile (currently only `hero_speed`/`dash_speed` are live).

### D. Combat model — Smash % + ring-out
- Repurpose the `hp` field as a rising `damage_pct` (0 → high). `take_damage` **adds** to % instead of subtracting HP. No HP→0 death (`Hero.gd:1967-1968` removed/repurposed).
- Scale knockback by damage: at the `apply_knockback` impulse site (`Hero.gd:1892` + enemy equivalent) multiply by `(1 + damage_pct/100)` so high-% fighters launch far.
- **Ring-out is the kill:** ensure hero + all bots route death through `StageHazard.fighter_fell` (already firing in VersusArena) → stock loss + respawn (or elimination). Bots become knock-out-able the same way.
- **Hide the HP bar**, show the **damage %** instead (repurpose `CharacterBars` at `Hero.gd:363-365`). Keep the MP/resource read if a spell cost exists.

### E. Bugfixes
- **Self-damage:** move `spell.set("caster", self)` out of the `if heal>0` block (`Hero.gd:1414-1417`) so it's set for every bolt; defensively exclude the caster by RID in `Spell.gd._ready` and early-return `_try_damage` when `node == caster`.
- **Click/melee:** auto-target the nearest enemy within `_melee_range` (soften/drop the cursor cone at close range) so a click near an enemy connects; add a short forward lunge + a crescent-slash VFX on **every** swing (not only on hit) + a light whoosh/hitstop; tighten the hit frame (~0.35).
- **Right-size spell visuals:** reduce the oversized `MagicCircle`/AoE scale (the ArcaneStorm/nova circle that eats half the screen) so casts read without dominating.

### F. Verification
- Full `tools/slice*_test_*.gd` sweep stays green; SP paths byte-identical where co-op-gated.
- `tools/combat_capture.gd` GPU re-capture to confirm the bolder grounded figure + right-sized spells by eye.
- Maker F5s `VersusArena` (now the boot scene) and reports feel.

## Explicitly NOT in Push 1 (YAGNI / deferred)
- The free-pick loadout + emergent class-name system (**Push 2**, its own spec).
- Co-op boss spectacle replication, gear/armory abilities (Armory is hidden, not deleted).
- The tower-run structure (Arena.gd floors) — untouched; the sandbox is VersusArena only. Ring-out in the tower Arena can follow later.
- New art/asset-gen sprites — the rig stays procedural, just fixed and bolder.

## Risks / guardrails
- **Hero.gd is the hot file** (movement + combat + bolt fix all touch it) — implementation must serialize edits to it, not parallel-write.
- SP must stay byte-identical for co-op-gated paths; run the sweep after each workstream.
- Movement/rig numbers are *starting targets from the audit*, not gospel — the maker's F5 is the real tuning signal; expose knobs so tuning doesn't need code.
- Repurposing `hp`→`damage_pct` touches every `take_damage`/knockback site; keep the field name or alias carefully so ~15 call sites don't break.
