# Stick Fight Feel Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Legacy Frontier's combat feel like Stick Fight (grounded, weighty, bold puppet) + Smash (spawn-into arena, damage-% + ring-out), by fixing the rig, movement, death model, and the self-damage/melee bugs — without the intro/hub/armory wrapper.

**Architecture:** `VersusArena.tscn` becomes the boot scene (a self-contained Smash stage that already spawns hero + bots + destructible cover + ring-out pits). The procedural `CharacterRig` is fixed to plant feet and track aim; `Hero.gd` gains weighty movement, a Smash damage-% model, and ring-out death. `Hero.gd` is the hot file and is edited serially; `CharacterRig.gd` and the sandbox scene are independent and parallelizable.

**Tech Stack:** Godot 4.6.2 / GDScript. Verification via the repo's headless slice-test runners (`tools/slice*_test_*.gd`) + GPU screenshot capture (`tools/combat_capture.gd`, GUI binary) + maker F5 — NOT pytest. Follow the established repo pattern.

## Global Constraints

- Branch: `v2.0-tower`. Godot binary (headless tests): `godot-engine/Godot_v4.6.2-stable_win64_console.exe`. GUI binary (capture, real renderer): `godot-engine/Godot_v4.6.2-stable_win64.exe`.
- **SP must stay byte-identical for co-op-gated paths.** Every co-op branch is gated on `Net.is_active()`/`is_host()`; do not change SP behaviour except where this plan explicitly does (death model, movement, rig).
- After each task: run the full `tools/slice*_test_*.gd` sweep — it must stay green (currently ~52 suites).
- Feel numbers (gravity, jump, stiffness) are **starting targets from the audit**, not gospel. Expose them as live `TuningConfig` knobs where noted so the maker tunes by F5, not recompile.
- Frequent commits — one per task. Commit message co-author line:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- The `class_name` cache trap: after adding/renaming any `class_name`, run a headless `--import` before the next capture/run.

---

## Execution waves

- **Wave 1 (parallel subagents):** Task 1 (sandbox boot), Task 2 (rig feel). Independent files.
- **Wave 2 (serial, one hand on `Hero.gd`):** Task 3 (movement weight), Task 4 (damage-% + ring-out), Task 5 (self-damage + melee bugfixes), Task 6 (jump/air state wiring). All touch `Hero.gd`.
- **Wave 3:** Task 7 (right-size spell VFX), Task 8 (integration verify + capture + maker F5 handoff).

Interface contract between Task 2 (rig) and Task 6 (Hero): the rig exposes
`CharacterRig.State.AIR`, `rig.play(State.AIR)`, and `rig.set_air_phase(rising: bool, grounded: bool)`. Task 6 calls these from `Hero.gd`.

---

### Task 1: Strip to the sandbox

**Files:**
- Modify: `godot-project/project.godot:19` (main scene)
- Modify: `godot-project/scripts/World.gd:181-186` (hide armory)
- Modify: `godot-project/scripts/combat/VersusArena.gd:297-352` (add practice dummies)
- Test: `godot-project/tools/slice_test_sandbox.gd` (new — asserts dummies spawn, are in "enemy" group, are flagged passive)

**Interfaces:**
- Produces: a boot that lands directly in `VersusArena` with N stationary practice dummies near `P1_SPAWN`, distinct from the 5 live bots.

- [ ] **Step 1:** Repoint `project.godot:19` `run/main_scene="res://scenes/ui/Lobby.tscn"` → `run/main_scene="res://scenes/combat/VersusArena.tscn"`. Leave `Lobby.tscn` on disk.
- [ ] **Step 2:** In `World.gd._build_loft()` (~:184-186) wrap the Armory instantiation in `if false:` / early-return guard with a `# hidden 2026-07-23 (sandbox focus)` comment so the loft stays but the station doesn't spawn.
- [ ] **Step 3:** In `VersusArena.gd`, add `_spawn_dummies()` called from `_ready()` after `_spawn_fighters()`: instantiate 2-3 `Enemy` (or `Hero`-as-dummy) at fixed positions near `P1_SPAWN`, archetype set to a passive/zero-aggro mode (no attack, no chase — set their AI-active flag off or `_attack_cooldown` to infinity and skip retarget), joined to group `"enemy"` so hits register + ring-out counts them, tinted a distinct grey, HP/`%` reset each time they're knocked out (respawn in place after a short delay) so they're a permanent punching bag.
- [ ] **Step 4:** Write `tools/slice_test_sandbox.gd` (duck-typed `SceneTree` runner mirroring `slice_test_coop.gd` shape): load `VersusArena.tscn`, settle frames, assert ≥2 dummies exist in group `"enemy"` with the passive flag and are positioned near spawn. Print `sandbox tests: all PASS`.
- [ ] **Step 5:** Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_sandbox.gd` — expect `all PASS`.
- [ ] **Step 6:** Run the full slice sweep — expect green.
- [ ] **Step 7:** Commit `feat: boot straight into VersusArena sandbox + practice dummies, hide armory`.

---

### Task 2: Stickman feel — CharacterRig

**Files:**
- Modify: `godot-project/scripts/combat/CharacterRig.gd` (spring consts :92-102; `_sim_pose` :328-335,658; State enum :9; aim gate :1159; silhouette :1062-1063,76-77; add foot IK + AIR pose)
- Test: `godot-project/tools/slice_test_rig.gd` (new — asserts AIR state exists, foot-plant clamps to a passed ground_y, aim arm reaches target angle when set)
- Capture: `godot-project/tools/verify_feel_capture.gd` (existing — re-run to eyeball)

**Interfaces:**
- Produces: `CharacterRig.State.AIR`; `play(State.AIR)`; `set_air_phase(rising: bool, grounded: bool)`; foot-plant that raycasts to floor/platform and locks the stance foot during ground phase; lead hand that snaps to `set_aim()` angle in IDLE/RUN/AIR/CAST/DASH; bolder silhouette.

- [ ] **Step 1:** Add `AIR` to the `State` enum (:9). Add `_air_rising: bool` + `_air_grounded: bool` fields and `set_air_phase(rising, grounded)`.
- [ ] **Step 2:** Add an AIR pose branch in the pose builder: tuck knees + raise arms on rise, reach legs down on fall, brief squash on land. Runs before the RUN/IDLE branches when `state == State.AIR`.
- [ ] **Step 3:** Foot-plant IK: add `_plant_foot(local_target, ground_y) -> Vector2` that raycasts from the hip down to the nearest floor/platform collider (mask = world/platform layers) and clamps the drawn foot to that Y during the stance (grounded) phase of the run cycle; hang naturally when airborne. Wire both feet through it in the RUN/IDLE draw.
- [ ] **Step 4:** Tame the spring — raise `STIFFNESS` (60 → ~180), lower `MAX_OFFSET_FACTOR` (0.85 → ~0.35), keep `LOOSE_LEG_STIFFNESS`/`flop()` only for the post-hit HURT flail. Verify the resting/running pose no longer drifts.
- [ ] **Step 5:** Aim arm — extend the gate at :1159 from `IDLE/RUN` to also `AIR`, `DASH`, and the cast pose; and drive the drawn lead hand from the **target** aim angle (bypass the spring for the lead hand when `aim_arm`) so it snaps to the cursor.
- [ ] **Step 6:** Bolder silhouette — limb `w=height*0.12 → ~0.16`, head `r=height*0.15 → ~0.18`, outline `OUTLINE_COLOR` to a true dark keyline + thicker `OUTLINE_EXTRA`. Scale overall figure size up (coordinate the scale constant with VersusArena so the fighter isn't a speck).
- [ ] **Step 7:** Write `tools/slice_test_rig.gd`: instance a rig, assert `State.AIR` exists; call `set_aim` toward a known angle in IDLE and assert the computed lead-hand angle matches within tolerance; call the foot-plant with a mock ground_y and assert the foot clamps. Print `rig tests: all PASS`.
- [ ] **Step 8:** Run the rig test headless — expect PASS. Run the full slice sweep — green.
- [ ] **Step 9:** Capture: `Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/verify_feel_capture.gd` → read `user://verify_sheet.png` to confirm grounded stance + aim arm + bold silhouette by eye.
- [ ] **Step 10:** Commit `feat: rig feel — foot-plant IK, air pose, aim-snap arm, bold silhouette, tamed spring`.

---

### Task 3: Movement weight — Hero.gd (serial wave 2 start)

**Files:**
- Modify: `godot-project/scripts/combat/Hero.gd:19-29` (movement consts), `:595,598` (air accel usage)
- Modify: `godot-project/scripts/combat/TuningConfig.gd` (add live knobs for gravity/jump/air)
- Test: `godot-project/tools/slice_test_movement.gd` (new — asserts consts read from TuningConfig, apex height/time in target band)

**Interfaces:**
- Consumes: nothing from Task 1/2.
- Produces: weighty movement; live `TuningConfig` knobs `move_gravity_rise`, `move_gravity_fall`, `move_jump_velocity`, `move_air_accel`, `move_max_fall`.

- [ ] **Step 1:** Add the five knobs to `TuningConfig.gd` defaulting to the new targets: rise 2600, fall 3000, jump -740, air_accel 750, max_fall 1400.
- [ ] **Step 2:** In `Hero.gd`, replace the hardcoded const reads in `_physics_process` (gravity/jump/air/max-fall sites) with `_tune("move_gravity_rise", GRAVITY)` etc., keeping the consts as fallbacks. Air accel at :595/:598 reads `move_air_accel`.
- [ ] **Step 3:** Write `tools/slice_test_movement.gd`: simulate a jump (apply jump velocity, step physics), assert apex time ≈ 0.28s ±0.05 and no free-steer overshoot at the low air_accel. Print `movement tests: all PASS`.
- [ ] **Step 4:** Run headless — PASS. Full sweep — green.
- [ ] **Step 5:** Commit `feat: weighty movement (real gravity, committed jump, low air control) + live tuning knobs`.

---

### Task 4: Smash damage-% + ring-out — Hero.gd + Enemy.gd

**Files:**
- Modify: `Hero.gd:215-216` (hp field → damage_pct role), `:1918` (`take_damage` adds %), `:1892` (knockback scales by %), `:1967-1968` (remove HP=0 death), `:363-365` (bars show %)
- Modify: `godot-project/scripts/combat/Enemy.gd:1145,1157-1158,228-253` (same % + ring-out for bots)
- Modify: `godot-project/scripts/combat/CharacterBars.gd:52-73` (render % instead of HP; invert grade)
- Modify: `godot-project/scripts/combat/VersusArena.gd` (confirm `fighter_fell` → stock loss is the sole elimination path)
- Test: `godot-project/tools/slice_test_ringout.gd` (new)

**Interfaces:**
- Consumes: `StageHazard.fighter_fell` (existing).
- Produces: `Hero.damage_pct` / `Enemy.damage_pct` (float, rises with hits); knockback scaled `(1 + damage_pct/100)`; death only via ring-out.

- [ ] **Step 1:** Introduce `damage_pct: float = 0.0` on Hero + Enemy (alias/repurpose `hp` carefully so the ~15 `take_damage` call sites keep compiling — keep `take_damage(amount)` signature; internally `damage_pct += amount * PCT_PER_DAMAGE`).
- [ ] **Step 2:** Scale knockback: at `Hero.gd:1892` (and Enemy equiv) multiply the impulse by `(1.0 + damage_pct/100.0)`.
- [ ] **Step 3:** Remove/neutralize HP=0 death (`Hero.gd:1967-1968`, `Enemy.gd:1157-1158`); the only elimination is `StageHazard.fighter_fell` → (hero: stock loss/respawn via VersusArena's existing `_on_fighter_fell`; enemy: `queue_free()` + counts toward "bots left"). Confirm bots reaching a pit are removed.
- [ ] **Step 4:** `CharacterBars` renders the damage `%` (number + a fill that grows with %, warm→red grade); drop the green HP fill. Hero's bar config at `:363-365` shows %.
- [ ] **Step 5:** Write `tools/slice_test_ringout.gd`: apply damage → assert `damage_pct` rises and knockback impulse grows with %; drop a fighter into a `StageHazard` pit → assert elimination path fires (stock decremented for hero / freed for enemy), NOT an HP=0 death. Print `ringout tests: all PASS`.
- [ ] **Step 6:** Run headless — PASS. Full sweep — green (fix any suite asserting HP-death).
- [ ] **Step 7:** Commit `feat: Smash damage-% + ring-out death model (no HP depletion); bots knock-out-able`.

---

### Task 5: Self-damage + melee bugfixes — Hero.gd + Spell.gd

**Files:**
- Modify: `Hero.gd:1414-1417` (set caster for all bolts), `:1829-1846` (melee auto-target + lunge), `HIT_FRAME` frac
- Modify: `godot-project/scripts/combat/Spell.gd:67-69,108-109,147` (RID exclude + null-caster guard)
- Test: `godot-project/tools/slice_test_selfdamage.gd` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: no bolt hits its own caster; click/melee auto-connects on nearest enemy in range with a lunge + arc.

- [ ] **Step 1:** In `_primary_bolt` move `spell.set("caster", self)` OUT of the `if bolt_heal > 0` block so caster is set for every class's bolt (`Hero.gd:1414-1417`).
- [ ] **Step 2:** In `Spell.gd`, add the caster's RID to the raycast exceptions in `_ready` regardless of heal, and early-return `_try_damage` when `node == caster`; treat this as the defensive backstop (`:108-109,147`).
- [ ] **Step 3:** Melee auto-target: in `_on_melee_hit_frame` pick the nearest enemy within `_melee_range` and hit it; drop/soften the `facing.dot(toward) <= _melee_arc_dot` cone at close range so a click near an enemy connects.
- [ ] **Step 4:** Add a short forward lunge on every `_melee` (not just combo/heavy) + a crescent-slash VFX on the swing itself + a light whoosh/hitstop; lower `HIT_FRAME_FRACTION` to ~0.35 so the punch lands closer to the click.
- [ ] **Step 5:** Write `tools/slice_test_selfdamage.gd`: fire a MAGE/STORMCALLER/ROGUE bolt with `Net` active; assert the caster's `damage_pct`/hp is unchanged (no self-hit). Assert a melee with the cursor NOT on the target still connects when the enemy is within range. Print `selfdamage tests: all PASS`.
- [ ] **Step 6:** Run headless — PASS. Full sweep — green.
- [ ] **Step 7:** Commit `fix: bolt never damages its own caster; melee auto-targets + lunges (Stick-Fight swing)`.

---

### Task 6: RAGDOLL air/hit reactions (REFRAMED per maker 2026-07-23) — Hero.gd ↔ CharacterRig

**Maker directive:** "there shouldnt be like a jump pose it should be ragdoll exactly like how the figure moves in Stick Fight." So this task does NOT wire a canned air pose. It makes airborne + hit reactions read as an **active ragdoll** (loose, trailing limbs) by reusing the existing spring/`flop()`/limp machinery. Grounded stays settled (foot-plant from Task 2). See memory `[[project_v2_rig_ragdoll_direction]]`.

**Key insight:** Task 3 made the body weighty (real gravity, low air control). On a weighty body, loosening the LIMB sim in the air reads as Stick-Fight ragdoll, NOT the old "floating drift" (which was floaty *body* movement, now fixed).

**Files:**
- Modify: `godot-project/scripts/combat/CharacterRig.gd` (remove the Task-2 canned AIR tuck/reach/land pose; make airborne a LOOSE stiffness regime; tighten `HIT_FRAME_FRACTION`)
- Modify: `godot-project/scripts/combat/Hero.gd` (drive the loose-air regime when `not is_on_floor()`)
- Modify: `godot-project/tools/slice_test_rig.gd` (assert airborne loosens effective stiffness, not a fixed pose)

**Interfaces:**
- Reuses the Task-2 hook `rig.set_air_phase(rising, grounded)` and `State.AIR`, but repurposes them: AIR = a looseness regime, not a keyframe pose.

- [ ] **Step 1:** In `CharacterRig.gd`, REMOVE the canned AIR pose branch added in Task 2 (the tuck-on-rise / reach-on-fall / squash-on-land keyframe math). Keep the `State.AIR` enum + `set_air_phase(rising, grounded)` as the hook.
- [ ] **Step 2:** Add an **airborne looseness regime**: when airborne, lerp the spring stiffness/`max_off` toward a LOOSE setting — partway between the grounded (settled) values and the full-limp flail values — so limbs trail/flail with momentum + gravity but the body still tracks the weighty CharacterBody2D position. NOT full limp (that stays for hits). Reuse the existing limp/flail formulation (a partial `_limp`-like factor for air) rather than authoring poses. `rising`/`grounded` may bias the looseness (e.g. slightly looser on the way down) but there is NO scripted pose.
- [ ] **Step 3:** Tighten melee impact: lower `HIT_FRAME_FRACTION` (0.55 → ~0.35) in `CharacterRig.gd` (deferred from Task 5 — the const lives in the rig) so the punch lands closer to the click.
- [ ] **Step 4:** In `Hero.gd`'s rig-drive block, when `not is_on_floor()` drive the loose-air regime (call `play(State.AIR)` + `set_air_phase(velocity.y < 0.0, is_on_floor())`); else RUN/IDLE grounded (settled + foot-plant, unchanged). On landing, settle promptly.
- [ ] **Step 5:** Update `slice_test_rig.gd`: replace any assertion that AIR produces a specific canned pose with an assertion that AIR produces a LOOSER effective stiffness/offset than grounded (and looser than resting, but not fully limp). Keep the aim-bypass + foot-plant tests. Print `rig tests: all PASS`.
- [ ] **Step 6:** Run the new rig test + the FULL sweep — green.
- [ ] **Step 7:** Capture `verify_feel_capture.gd` + `combat_capture.gd`; confirm the airborne figure shows LOOSE trailing limbs (ragdoll), not a canned tuck, and grounded stays settled. Report the PNG paths for the controller to eyeball.
- [ ] **Step 8:** Commit `feat: ragdoll air/hit reactions (loose trailing limbs, no canned pose) + tighter melee hit-frame`.

---

### Task 7: Right-size spell VFX

**Files:**
- Modify: the oversized `MagicCircle`/AoE scale (grep `MagicCircle`, the ArcaneStorm/nova radius-to-visual scale in the relevant spell scripts)
- Capture: `combat_capture.gd`

- [ ] **Step 1:** Reduce the screen-eating spell-circle visual scale (the giant purple/red ring in the capture) so a cast reads without dominating the arena; keep the actual hit radius unchanged (visual-only shrink).
- [ ] **Step 2:** Full sweep — green.
- [ ] **Step 3:** Capture → confirm the circle no longer eats half the screen.
- [ ] **Step 4:** Commit `polish: right-size oversized spell-circle VFX (visual-only)`.

---

### Task 8: Integration verify + maker handoff

- [ ] **Step 1:** Run the ENTIRE `tools/slice*_test_*.gd` sweep — all green.
- [ ] **Step 2:** Boot check: `Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project scenes/combat/VersusArena.tscn --quit-after 180` — clean, no errors.
- [ ] **Step 3:** GPU capture `combat_capture.gd` + `verify_feel_capture.gd`; read both PNGs and confirm: bold grounded figure (settled, feet planted), aim arm tracks, airborne = LOOSE ragdoll limbs (not a canned pose), right-sized spells, `%` bars (no HP bar).
- [ ] **Step 4:** Launch the real GUI window for the maker (`Godot_v4.6.2-stable_win64.exe --path godot-project`) and hand off an F5 checklist: grounded feel (no flying), arm follows the mouse, jumping/getting-hit reads as Stick-Fight ragdoll (loose limbs, not a stiff pose), melee connects on click, getting launched off the edge = death (no HP bar), your own spells no longer hurt you.
- [ ] **Step 5:** Update `.superpowers/sdd/progress.md` READ-FIRST block with the new state. Commit `docs: ledger — Stick Fight feel foundation (Push 1) shipped, awaiting maker F5`.

## Self-Review

**Spec coverage:** A(sandbox)=T1; B(rig)=T2+T6; C(movement)=T3; D(%+ring-out)=T4; E(self-damage)=T5, E(melee)=T5, E(spell size)=T7; F(verify)=T8. All spec sections covered.
**Placeholder scan:** feel numbers are explicit targets (not "tune appropriately") with live knobs; tests have concrete assertions. No TBDs.
**Type consistency:** rig interface (`State.AIR`/`play`/`set_air_phase`) defined in T2, consumed in T6. `damage_pct` defined T4, used T4/T5. `take_damage(amount)` signature preserved so the ~15 call sites don't break.
