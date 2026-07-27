# Dash effect — archaeology + restoration plan

**Date:** 2026-07-27 · **Branch:** `stickman-integrate` · **Status:** investigation complete, nothing changed in game code.

Maker feedback after playing `scenes/spike/SpellPlayground.tscn`:
> "the like dash effect we used to have please reintroduce that"

---

## 1. What the history actually says

Nothing was deleted. There is no regression commit. Verified:

| Check | Result |
|---|---|
| `git log --all --diff-filter=D --name-only -- godot-project/scripts/**` | only `DialogueUI.gd` (v0.0 era). No dash/VFX file ever deleted. |
| `git log --all -S"_spawn_ghost" -- godot-project/scripts/spike` | one commit only: `158c319` (added). Never removed. |
| `git log --all -S"is_dashing" -- godot-project/scripts/spike` | one commit only: `158c319` (added). Never removed. |
| `git diff v2.0-tower stickman-integrate -- scripts/combat/Hero.gd CharacterRig.gd RigGhost.gd` | 20/14 lines, none dash-related. Hero's dash is byte-identical across branches. |

The dash afterimage system was born on `v2.0-tower` in **`0696c55` "slice1: dash afterimages/wind + hero aura glow"** (+ z-order fix in **`8b3decb`**), lives in `CharacterRig.spawn_ghost` / `RigGhost.gd`, and is still intact.

The spike rig got its own *reimplementation* of a dash in **`158c319` "Phase 1 rig+feel … air-dash"** (yesterday, 2026-07-26) in answer to overhaul ask #8 ("AIR DASH — bring it back"). Phase 2a–2h never touched it.

So the framing "a dash effect existed and is gone" is **false at the repo level**. What is true is that the Phase-1 port is a *partial* port: the spike reimplemented the trail from scratch and dropped several elements the game's Hero dash has.

I rendered both to be certain (`tools/dash_agent_capture.gd`, agent-owned throwaway; also re-ran the existing `tools/phase1_rig_capture.gd`): the spike's blue afterimages **do render** in the playground. The dash is not broken and SHIFT is wired (`SpellPlaygroundController.gd:289-290 → _dash() :234-248`). This is a fidelity gap, not a dead feature.

---

## 2. Side-by-side: Hero dash vs SpikeFigure dash

### Hero (`scripts/combat/Hero.gd:520-540`, `_start_dash` `:1212-1230`)

1. `rig.play(CharacterRig.State.DASH)` — **a dedicated committed dash pose**: `CharacterRig.gd:1253-1258`, `lean = height * 0.22`, both legs swept back (`PI*0.5 + 0.55 / +0.85`), both arms swept back (`+0.7 / +0.95`). The body visibly *leans into* the burst.
2. `rig.set_facing(_dash_dir)` — body turns to face the dash line.
3. `rig.spawn_ghost(get_parent(), GHOST_COLOR, _dash_dir)` every `GHOST_INTERVAL 0.03` (`Hero.gd:118-119`, `GHOST_COLOR = Color(0.6,0.85,1.0,0.72)`).
   - Ghost = `RigGhost.gd`, `FADE_TIME 0.34`, redraws with a real alpha ramp each frame (`RigGhost.gd:35-51`).
   - Ghost draws the **full silhouette including robe/gear** via the shared `CharacterRig.draw_figure` (`RigGhost.gd:49`).
   - **Each ghost emits its own 2 trailing motion streaks** opposite the travel direction (`RigGhost.gd:55-64`, `WIND_STREAKS 2`, `WIND_LENGTH 26`).
   - Ghosts are parented to `get_parent()` (the arena) and copy `global_transform`, so they are truly world-locked; `z_index = 0` deliberately (`CharacterRig.gd:771-776` — the `-1` version was invisible behind the arena floor, the bug fixed in `8b3decb`).
   - Global cap `MAX_GHOSTS 24` via the `rig_ghost` group (`CharacterRig.gd:59, 759`).
4. On dash end: `CombatVfx.spawn_burst(... 8 particles, 0.25s, 30→95 px/s ...)` — a soft additive skid-stop dust kick (`Hero.gd:532-537`).
5. i-frames for the whole dash (`Hero.gd:2009-2011`).
6. Optional rogue `dash_strike` sweep (`Hero.gd:1182-1210`).
7. No dash SFX.

### SpikeFigure (`scripts/spike/SpikeFigure.gd`)

1. **No dash pose at all.** `_process_dash` (`:866-877`) only sets `torso.linear_velocity`; the spring solver keeps whatever idle/run shape it had. The figure slides upright.
2. `_facing` flips (`:349-350`) but there is no leaning silhouette to face.
3. `_spawn_ghost()` every `GHOST_INTERVAL 0.03` (`:64-65`, `GHOST_COLOR = Color(0.6,0.85,1.0,0.55)`).
   - Ghost = ad-hoc `Node2D` of `Line2D`s + a head `Polygon2D` (`:882-917`). Bare lines, no gear, no robe.
   - Fade is a tween on `modulate:a` over **0.22 s** (`:902-904`) — one third shorter than the Hero's 0.34.
   - **No per-ghost wind streaks.** A single 8-streak burst fires once at dash start (`:352`) and that is the whole "wind".
   - Parented to `self` with `z_index = -1` (`:886-887`). This only works because the `SpikeFigure` node itself never moves (only its internal `_torso` RigidBody2D does) and the playground floor polys sit at `z_index = -5` (`SpellPlaygroundController.gd:97`). It is correct today but fragile — it re-introduces exactly the shape of the `8b3decb` bug if the figure is ever reparented or the scene gains a z=0 floor.
   - No ghost cap.
4. On dash end: `torso.linear_velocity *= 0.35` + `_spawn_puffs(..., 4, 5.0)` (`:876-877`) — 4 small dust lumps vs the Hero's 8-particle additive burst.
5. i-frames for the whole dash (`:597-599`) — **present, parity achieved**.
6. `_sfx("melee_swing", -5.0, 0.08, 0.78)` pitched-down whoosh (`:351`) — the spike is *ahead* of Hero here; Hero has no dash sound.
7. Limb jolt on launch (`:354-356`) — also spike-only, and good.

### Colour mismatch (probably the single most visible defect)

`GHOST_COLOR` is hardcoded blue `Color(0.6,0.85,1.0,·)` in both files. On the Hero that matches the mage/arcanist's blue `limb_color`, so the trail reads as *you, fading*. The playground figure is **salmon red** — `FIG_COLOR = Color(0.93,0.51,0.51)` (`SpellPlaygroundController.gd:18` → `SpikeFigure.body_color:113`). The result on screen is a cluster of bright cyan sticks next to a red stickman: it reads as a swarm of blue figures, not as a smear of the player. Confirmed in the rendered captures (`user://phase1_dash.png`, `user://dashcap_spike_mid.png`).

---

## 3. Verdict — what "the dash effect we used to have" most likely means

Ranked by likelihood:

**#1 (most likely) — the committed DASH POSE plus a trail that reads as *you*.**
In the game, dashing snaps the rig into `State.DASH`: a hard forward lean with limbs swept back, and 4–5 same-coloured afterimages of that leaning silhouette. That combination is what makes the game's dash read as a *smear*. The spike has afterimages but of an *upright, un-posed, wrong-coloured* figure, so the motion never resolves into a smear. Distinguishing evidence: `CharacterRig.gd:1253-1258` exists and has no counterpart anywhere in `SpikeFigure.gd`; `GHOST_COLOR` is not derived from `body_color`.

**#2 — the continuous wind/speed-line trail.**
Hero's trail keeps emitting motion lines for the whole dash (2 per ghost × ~5 ghosts = ~10 streaks spread along the dash line, `RigGhost.gd:55-64`). The spike fires one 8-streak burst at the origin and then nothing, so the back half of the dash is visually silent.

**#3 — trail persistence / punch.**
0.22 s @ α0.55 (spike) vs 0.34 s @ α0.72 (Hero). Roughly 35 % shorter and 25 % fainter, so at the playground's larger figure scale the trail barely outlives the body.

**#4 — the skid-stop kick.**
Hero's additive 8-particle `CombatVfx.spawn_burst` vs the spike's 4 plain dust lumps. Smallest contributor.

**Adjacent finding, worth flagging to the maker:** `SpikeFigure.blink_to` (`:369-379`, added in `d0dd794`) only spawns wind streaks. The Hero's blink (`Hero.gd:1258-1272`) leaves a dark ghost silhouette at the origin, an 18-particle violet burst at the origin, a 24-particle burst at the destination, an arrival colour flash and a dedicated `Sfx.play("blink")`. If the maker's "dash effect" was actually about `blink_strike` feeling flat in the playground, this is the gap — same family, larger delta.

---

## 4. Restoration plan

All changes are confined to `godot-project/scripts/spike/` — the throwaway spike. **Zero files under `scripts/combat/` are touched, so the real game's Hero cannot regress.**

### Change A — dash pose (highest value)

`SpikeFigure.gd`

1. Add near the other dash constants (`:61-65`):
   ```
   const DASH_LEAN := 0.42        # rad the torso pitches into the burst
   const DASH_ARM_BACK := 0.85    # rad both arms sweep opposite the dash
   const DASH_LEG_BACK := 0.55    # rad both legs sweep opposite the dash
   ```
   (Angle-space, not `height * 0.22`, because the spike rig is spring/angle-driven rather than offset-driven like `CharacterRig`.)
2. In `_solve_arms` (around `:1015-1050`, where the `_punch_timer > 0.0` and `_cast_timer > 0.0` branches already override the spring targets), add a `is_dashing` branch **above** the air/idle branches that drives both `_arm_ang[i]` targets to `-_dash_dir.angle() ± DASH_ARM_BACK` measured backwards along `_dash_dir`. Same treatment for `_leg_ang` in the leg solver (`:1131-1150`) — legs trail the burst.
3. In `_process_dash` (`:866`), bias the torso's uprighting: temporarily target `_dash_dir.angle()` rotated toward horizontal by `DASH_LEAN * signf(_dash_dir.x)` instead of the usual upright target, then release on dash end.

   **Do it inside the existing spring solver, not as a canned keyframe** — this is the maker's standing directive (memory `project_v2_rig_ragdoll_direction`, and the same rule `d0dd794` followed for cast poses): a hit mid-dash must still ragdoll out of the pose.

### Change B — tint the trail to the figure

`SpikeFigure.gd:65` — replace the hardcoded const with a derived colour:
```
# GHOST_COLOR stays as the fallback; prefer a desaturated, brightened body_color
func _ghost_tint() -> Color:
    return Color(body_color.r, body_color.g, body_color.b).lerp(Color(0.75, 0.9, 1.0), 0.35) with a = 0.72
```
Use it at `:897` (head polygon) and `:913` (`_ghost_line`). Alpha `0.72` matches `Hero.gd:119`.

### Change C — per-ghost trailing streaks

`SpikeFigure._spawn_ghost` (`:882`) — after building the ghost, add 2 short tapered lines from the torso/hip running **opposite** `_dash_dir`, length ~26 px (mirrors `RigGhost.WIND_STREAKS 2` / `WIND_LENGTH 26`). Reuse `_streak_material()` + `_streak_width_curve()` (`:579-592`) so the look matches the rest of the spike's speed-lines. Parent them to the ghost `Node2D` so they fade with it.

### Change D — persistence + cap

- `:903` — fade `0.22` → **`0.34`** (matches `RigGhost.FADE_TIME`).
- `:882` — early-return if `get_tree().get_nodes_in_group("spike_ghost").size() >= 24`, and `g.add_to_group("spike_ghost")` (mirrors `CharacterRig.MAX_GHOSTS`). Cheap insurance now that ghosts live 50 % longer.
- Optional hardening: `g.z_index = -1` is currently only safe by accident. Either keep `-1` and add a comment pointing at `8b3decb`, or move ghosts to `get_parent()` at `z_index = 0` like the Hero does. Recommend the comment — reparenting would change world-lock semantics for no gain in a throwaway spike.

### Change E — skid-stop kick

`:877` — bump `_spawn_puffs(..., 4, 5.0)` to `(..., 8, 7.0)`, or call `CombatVfx.spawn_burst(self, torso.global_position, Color(0.82,0.82,0.88,0.6), Color(0.82,0.82,0.88,0.0), 8, 0.25, 30.0, 95.0)` for literal parity with `Hero.gd:533-537`. `CombatVfx` is already a project-wide static helper the spike may call.

### Suggested order
A → B → D → C → E. A and B alone should close most of the perceived gap; stop and get maker eyes before doing C/E.

### Optional, only if the maker confirms they meant blink
Port the Hero's blink dressing into `SpikeFigure.blink_to` (`:369`): a ghost at the origin using the shadow tint, `CombatVfx.spawn_burst` at both endpoints, an arrival flash, and `Sfx.play("blink")` — matching `Hero.gd:1258-1272`.

---

## 5. Verification

The project's GUI-binary capture pattern already covers this. Two options:

1. **Existing:** `tools/phase1_rig_capture.gd` already renders `phase1_dash.png` (step 3, dash LEFT, 12 physics frames in). Re-run after each change:
   ```
   ./godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/phase1_rig_capture.gd
   ```
   Output → `%APPDATA%\Godot\app_userdata\Legacy Frontier\phase1_dash.png`.
   **Caveat:** the figure spawns at `(0,120)` and a practice dummy sits at `DUMMY_X = -70` (`SpellPlaygroundController.gd:24`), so the leftward dash collides ~72 px in and the trail bunches up. Dash **right** (`Vector2(1,0)`) for a clean open-lane read, or move the capture's dash later in the timeline.

2. **New (added this session, agent-owned, safe to delete):** `tools/dash_agent_capture.gd` renders the *game* Hero's dash and the *spike* figure's dash at matched beats (frames 4 / 14 / 31 / 61 after launch, i.e. mid-dash / last dash frame / post-skid / settled) into `dashcap_hero_*.png` and `dashcap_spike_*.png`. That is the A/B to look at before and after.
   ```
   ./godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/dash_agent_capture.gd
   ```
   Note the Hero half frames wide (VersusArena auto-zooms to fit all bots) — good enough to see the trail exists, not good enough to judge the pose. Judge the pose from the spike shots and from `CharacterRig.gd:1253-1258`.

Headless regression: `tools/spike_test_wall_moves.gd` and the other `slice*_test_*.gd` suites must stay green — none of them assert on dash visuals, so Changes A–E should be inert to them, but run them anyway.

---

## 6. Risk to the real game

**None, if the plan is followed as written.** Every change lands in `scripts/spike/SpikeFigure.gd`, which is imported by nothing outside `scripts/spike/` and `scenes/spike/` (the spike is explicitly deletable — see the header comment in `SpellPlaygroundController.gd:5`).

Risks to actively avoid:

- **Do not "fix" `RigGhost.gd`, `CharacterRig.spawn_ghost`, or `Hero.gd` to make the playground look better.** Those are shared by Hero, Enemy corpses (`Enemy.gd:45` depends on `CORPSE_FADE_TIME 0.6 > ghost 0.34`) and the blink shadow (`Hero.gd:1258`). Changing `FADE_TIME`, `MAX_GHOSTS` or `GHOST_COLOR` would alter single-player behaviour, which the project guardrail forbids without a deliberate decision.
- **Do not change `CharacterRig.State.DASH`'s pose constants** to "port" them — read them, re-express them in the spike's angle space. `Enemy.gd:400` also plays `State.DASH` for its airborne pose, so editing it changes enemy visuals too.
- `CombatVfx.spawn_burst` (Change E) is a pure static spawner — calling it from the spike is additive and cannot affect Hero.
- Changes A/B/C/E are visual-only. Change D's ghost cap is the only one that alters spawn behaviour, and only under load (>24 concurrent ghosts), which the 0.03 s cadence and 0.34 s life make unreachable for a single figure (max ~12).

---

## 7. Open question for the maker

Worth one clarifying question before building, because #1 and the blink finding point at different files:

> When you say "the dash effect we used to have" — do you mean **the leaning smear the hero leaves when you dash in the arena**, or **the shadow-poof teleport** (blink)? The playground already spawns dash afterimages, but they're upright, blue-on-red, and short-lived, so they may not be reading as a smear.
