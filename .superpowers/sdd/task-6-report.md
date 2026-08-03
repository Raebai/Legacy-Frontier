# Task 6 report — RAGDOLL air/hit reactions (loose trailing limbs, no canned pose) + tighter melee hit-frame

Status: DONE

## What the maker directive changed
Reframed from "canned air pose" to "active ragdoll like Stick Fight". No scripted jump
pose. The AIR state is now a LOOSENESS REGIME layered on the existing spring/limp sim.

## Removed
- The Task-2 canned AIR pose branch in `CharacterRig._compute_pose()` (tuck-on-rise /
  reach-on-fall / squash-on-land keyframe math for legs + arms + bob). Replaced with a
  `pass` (neutral standing hang is the target; the sim does the acting).
- The stale test `_test_air_phase_toggle_and_pose()` which asserted rising/falling produce
  different canned foot poses.

## Kept (unchanged)
- `State.AIR` enum + `set_air_phase(rising, grounded)` hook (repurposed, not removed).
- Aim-snap arm (twin-stick), foot-plant IK, bold silhouette/outline, HURT full-limp flail,
  `flop()`/`_limp` full-ragdoll-on-hit machinery, all movement/ring-out/combat/Arena code.

## Added — airborne looseness regime (CharacterRig.gd)
- Constants (near the limp consts):
  - `AIR_LOOSE_FALLING = 0.55` (~halfway to full limp on the way down)
  - `AIR_LOOSE_RISING  = 0.42` (slightly tighter ascending — a coiled leap)
  - `AIR_LOOSE_EASE_SPEED = 9.0` (eases faster than `_limp`'s 5.0 so landing settles promptly)
- State var `_air_loose: float = 0.0`.
- In `_step_sim()`, after `_limp` easing:
  ```
  var air_target := 0.0
  if state == State.AIR and not _air_grounded:
      air_target = AIR_LOOSE_RISING if _air_rising else AIR_LOOSE_FALLING
  _air_loose = move_toward(_air_loose, air_target, AIR_LOOSE_EASE_SPEED * delta)
  var loose := maxf(_limp, _air_loose)
  ```
  `_limp` was then replaced by `loose` in the four spring terms it fed:
  `stiffness` lerp, `max_off` lerp, `leg_stiffness` lerp, the `GRAVITY * loose` droop, and
  the grounded floor-clamp gate (`_grounded and loose > 0.01`).

### Air-looseness factor + final formula (the answer)
- **Factor:** falling 0.55, rising 0.42 (fraction of the way from the settled grounded
  values toward the full-limp flail).
- **Combine rule:** `loose = maxf(_limp, _air_loose)` — a mid-air hit raises `_limp` to 1
  and overrides to FULL limp; otherwise AIR sits at the partial value.
- **Effective spring in air (falling, 0.55):** stiffness `lerpf(180, 3, 0.55) ≈ 82.7`
  (vs 180 grounded, 3 full limp); max_off factor `lerpf(0.35, 0.85, 0.55) ≈ 0.63` (vs 0.35
  grounded, 0.85 full limp). Legs additionally soften and a modest `GRAVITY*0.55 ≈ 440`
  droop pulls the limbs so they hang + trail while the weighty body arcs. Momentum trail
  (from `set_body_velocity` deltas) is unchanged and adds the swing on launch/arc.
- Rising/grounded only BIAS the looseness — there is NO scripted pose.

## HIT_FRAME_FRACTION
Lowered `0.55 -> 0.35` (punch/kick land closer to the click; deferred from Task 5 because
the const lives in the rig).

## Hero.gd
Rig-drive block (after the wall-slide early return): when `not is_on_floor()` →
`rig.play(State.AIR)` + `rig.set_air_phase(velocity.y < 0.0, is_on_floor())`; else RUN/IDLE
(settled + foot-plant, unchanged). Footstep/facing/aim below already gate on `is_on_floor()`,
so no footsteps or stride dust fire in air.

## Tests
Replaced the pose-differ test with `_test_air_phase_and_looseness()` which asserts:
flags still toggle; grounded IDLE keeps `_air_loose == 0`; AIR loosens `_air_loose` to
`(0,1)`; effective stiffness strictly between FULL_LIMP_STIFFNESS and STIFFNESS; effective
offset strictly between MAX_OFFSET_FACTOR and FULL_LIMP_OFFSET_FACTOR; rising < falling;
landing settles back to 0. Kept aim-bypass (idle+air), foot-plant, spring-tamed tests.

Command:
`godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_rig.gd`
→ `rig tests: all PASS`

Full sweep of every `godot-project/tools/slice*_test_*.gd`: **PASS=43 FAIL=0**.
(The "ObjectDB instances leaked / resources still in use at exit" lines are the pre-existing
headless-teardown warnings, not failures.)

## GPU captures (for the controller to eyeball)
- `C:\Users\Ari\AppData\Roaming\Godot\app_userdata\Legacy Frontier\verify_sheet.png`
  — cell [1] (top-right) is the airborne/rising frame. It SHOULD show loose, slightly
  trailing/hanging limbs on the blue hero (no stiff knee-tuck, no jog-in-air). Grounded
  cells [0]/[2]/[3] show the settled foot-planted stance + staff/parry/cast, unchanged.
- `...\combat_sheet.png`, `...\combat_full_a.png`, `...\combat_full_b.png`.
Boots clean; hero renders upright; cast/parry/aura all intact (no collapse/regression).
At the 480x270 thumbnail scale the airborne looseness is subtle — the headless test carries
the mathematical proof; the full-res PNG is where the trailing-limb feel is judged, and the
maker's F5 is the final tuning pass on the 0.42/0.55 factors.

## Self-review
- No new RigidBody2D ragdoll — reuses the existing point-mass spring/limp system as required.
- `maxf(_limp, _air_loose)` keeps hits/flop at FULL limp; air is strictly partial.
- Floor-clamp gate switched `_limp -> loose`: identical in all pre-existing cases (air_loose
  is 0 when grounded+settled), and now also clamps during the brief landing settle so
  residual air-droop can't sink limbs through the floor. In-air the gate is off (`_grounded`
  false), so limbs flail freely.
- Foot-plant + ground probe already skip `state == State.AIR`, so air limbs hang; grounded
  stance stays settled (the maker's earlier "no drift" complaint is preserved).
- Aim-arm and `_is_aim_state()` (which includes AIR) untouched — the lead hand still snaps
  to the cursor in air with no spring lag (test-guarded).

## Concerns
- The 0.42/0.55 looseness factors + the `GRAVITY*loose` droop are feel-tunables; the maker
  will F5-tune. If the air droop reads too "melty" (limbs sagging straight down), lowering
  the gravity contribution in air (e.g. gating `GRAVITY` on `_limp` only, leaving air droop
  to stiffness+trail) is the first knob to try — flagged, not changed, since the brief asks
  for "momentum + gravity".
- Capture thumbnails are too small to definitively judge the trailing feel; needs the F5
  playtest / full-res eyeball.
