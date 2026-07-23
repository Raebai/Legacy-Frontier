# Task 7 report: right-size oversized spell-circle VFX

## Summary

The maker's complaint (GPU capture of the sandbox): on the ARCANIST, the **Q**
(`arcane_meteor` → `MeteorSigil`, "ArcaneStorm") and the **T** (`nova` →
`EnergyNova`) each produced a translucent circle/ring that read as roughly
half the 960px-wide combat frame at the combat camera's default 1.6x zoom
(`CombatCamera.DEFAULT_ZOOM = Vector2(1.6, 1.6)`), dwarfing the fighters
(rig figure height ≈ 62 world-units per `CharacterRig.gd` conventions
`height*1.5` feet-offset + `height*0.5` head-offset → ~99px on screen at 1.6x,
vs. the old ring's ~560px screen diameter — the ring was ~5.6x the fighter's
height).

Both offenders are fixed with a pure visual-scale shrink. **No hit radius,
damage, knockback, or timing constant was touched.**

## What was shrunk

### 1. `godot-project/scripts/combat/MeteorSigil.gd` (Q — ArcaneStorm)

The sky sigil (`MagicCircle`) that opens above the target square before the
meteor barrage.

- **Before:** `_circle.appear(_color, radius * 1.9, CHARGE_TIME * 0.85)` — a
  hardcoded `1.9` visual multiplier on the AoE `radius` param (92.0 for the
  hero's Q → sigil radius 174.8 world-units, diameter ~350).
- **After:** introduced `const SIGIL_VISUAL_RADIUS_FACTOR: float = 1.1` and
  call `_circle.appear(_color, radius * SIGIL_VISUAL_RADIUS_FACTOR, ...)`.
  New sigil radius = 101.2 world-units, diameter ~202.
- **Reduction:** `1.9 → 1.1` = **42.1% smaller** diameter. Within the
  requested 35–50% band.

### 2. `godot-project/scripts/combat/EnergyNova.gd` (T — Nova)

EnergyNova does **not** use `MagicCircle` — it draws its own expanding
shockwave ring/flash directly in `_draw()`, and (critically) that draw code
previously multiplied the SAME `NOVA_RADIUS` constant that
`_apply_nova_damage()` uses for the hit query. Visual and hit radius were the
same value, so per the brief's explicit instruction I **decoupled them**
before shrinking, rather than shrinking `NOVA_RADIUS` itself (which would
have shrunk the hitbox — not acceptable).

- Introduced `const VISUAL_RADIUS_FACTOR: float = 0.62` — a visual-only
  multiplier that feeds **only** `_draw()`.
- `_draw()` ring peak: `NOVA_RADIUS * 1.3` → `NOVA_RADIUS * VISUAL_RADIUS_FACTOR * 1.3`
  = effective multiplier `1.3 → 0.806` (**38% smaller**).
- `_draw()` flash core: `NOVA_RADIUS * 0.9` → `NOVA_RADIUS * VISUAL_RADIUS_FACTOR * 0.9`
  = effective multiplier `0.9 → 0.558` (**38% smaller**, same ratio preserved
  so the flash-to-ring proportion looks the same, just smaller).
- `_apply_nova_damage()` — **completely untouched**, still reads the raw
  `NOVA_RADIUS` constant (135.0) directly (see file:line below).

## Scope discipline — what was NOT touched

- `MagicCircle.gd` itself — shared draw code, untouched. No default/shared
  scale lives there; every caller passes its own radius, so editing per-call
  multipliers was correct rather than touching the shared script.
- `BlastSpell.gd`, `ZoneSpell.gd`, `DivineRay.gd`, `StarConvergence.gd`,
  `BeamSpell.gd` — these also call `MagicCircle.appear()` with their own
  multipliers (2.6x, 2.2x, 3.3x-of-width respectively) but were **not** flagged
  by the maker's capture and are not the Arcanist's Q/T. Per the brief
  ("Focus on the clear offenders first... Do NOT touch... Keep it to the
  spell VFX scale"), left alone to keep the change conservative and
  reviewable. If the maker's next F5 pass flags these too, the same
  decouple-then-shrink pattern applies directly.
- Rig, movement, ring-out, melee, Arena — untouched, per instruction.
- No damage numbers, knockback constants, cooldowns, or timing values changed
  anywhere.

## How I confirmed the hit radius is unchanged

1. **MeteorSigil — already decoupled, confirmed by reading the code.** The
   `radius` param passed into `rain()` only feeds (a) the sigil's visual
   scale (the line I edited) and (b) the meteor *scatter* positions (where
   meteors land within the footprint — a spawn-position concern, not a hit
   query). The actual per-meteor hit/damage query in `_land()` at
   `godot-project/scripts/combat/MeteorSigil.gd:100` calls
   `targets_in_radius(at, METEOR_IMPACT_RADIUS, ...)` — `METEOR_IMPACT_RADIUS`
   is a separate hardcoded constant (`48.0`, `MeteorSigil.gd:30`) that my edit
   never touches. Confirmed unchanged by `git diff` (constant not in the
   diff) and by `tools/slice4_test_spells.gd::_test_meteor_radius()` still
   asserting the 48px boundary (close@30 hits, far@120 misses) after the
   edit — still green.

2. **EnergyNova — was coupled, now decoupled; verified with a new test.**
   The damage query is `godot-project/scripts/combat/EnergyNova.gd:73-87`
   (`_apply_nova_damage`), specifically line 77:
   `if global_position.distance_to(enemy.global_position) > NOVA_RADIUS: continue`
   — this line was **not edited** and still reads the raw `NOVA_RADIUS`
   constant (135.0), never `VISUAL_RADIUS_FACTOR`. I extended
   `godot-project/tools/slice1_test_nova.gd` with a new test,
   `_test_nova_hit_radius_unaffected_by_visual_shrink()`, that places one
   enemy 1px inside the true `NOVA_RADIUS` (134 units out) and one enemy 1px
   outside (136 units out), fires `_apply_nova_damage()` directly, and
   asserts the inside enemy takes damage while the outside enemy takes none.
   This pins the exact boundary at 135.0 — if `VISUAL_RADIUS_FACTOR` (0.62)
   ever leaked into the damage query, the boundary would shrink to ~83.7 and
   the inside-enemy assertion would start failing. **Test passes.**

## Test command + output

Full sweep of every `godot-project/tools/slice*_test_*.gd` plus
`test_class_attacks.gd` (46 files), run headless:

```
for f in godot-project/tools/slice*_test_*.gd godot-project/tools/test_class_attacks.gd; do
  godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script "tools/$(basename $f)"
done
```

**Result: all 46 exit 0.** Representative pass lines:

```
Slice1 nova tests: all PASS          (includes the new hit-radius-precision test)
Slice4 spell tests: all PASS         (includes _test_meteor_radius: 48px boundary intact)
Class-Q tests: all PASS              (arcane_meteor Q still spawns a spectacle node)
Class-attack tests: all PASS
Slice2 rogue tests: all PASS
Slice3 spell-collision tests: all PASS
Boss tests: all PASS
... (43 more, all PASS)
```

(The `ObjectDB instances leaked at exit` / `resources still in use` messages
are the SceneTree-script harness's known headless-teardown noise — present
identically before this change on every one of these scripts; not a
regression.)

New/changed test: `godot-project/tools/slice1_test_nova.gd` now runs 5 test
functions (was 4) — added `_test_nova_hit_radius_unaffected_by_visual_shrink`.

## GPU capture

Ran with the GUI binary (dummy renderer draws black under `--headless`, per
the script's own header comment):

```
godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/combat_capture.gd
godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/meteor_capture.gd
godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/nova_capture.gd   (new, see below)
```

Saved files (all under `%APPDATA%/Godot/app_userdata/Legacy Frontier/`):

- `combat_sheet.png` — 4x3 contact sheet, general VersusArena fight (bots use
  random classes/abilities; may or may not land on the Arcanist's Q/T inside
  the capture window).
- `combat_full_a.png`, `combat_full_b.png` — two full-res frames from that run.
- `meteor_seq.png` — 2x2 sequence of a `MeteorSigil.rain()` call in
  VersusArena at 0.62 zoom (telegraph → barrage → impacts), exercising the
  exact line I edited.
- `nova_seq.png` — 2x2 sequence of an `EnergyNova.activate_at()` call in
  VersusArena at **1.6 zoom (the real `CombatCamera.DEFAULT_ZOOM`, i.e. true
  in-game scale)**, added as `godot-project/tools/nova_capture.gd` (new file,
  modeled on the existing `meteor_capture.gd` pattern) specifically so the
  Nova ring's shrink is visible at the scale the maker actually plays at.

**What SHOULD now be true when eyeballed** (I cannot view the PNGs myself):
in `meteor_seq.png` the sky sigil circle should now span noticeably less of
the frame than before (diameter cut ~42%) relative to the fighter sprites
below it. In `nova_seq.png`, cell `[1]` (near-peak ring) should show the cyan
shockwave ring reaching roughly 38% less far from the hero than the old
version — it should no longer look like it's about to leave the visible
frame at 1.6x zoom, and the fighters should read as clearly larger than the
ring's radius rather than dwarfed by it. `combat_sheet.png` /
`combat_full_a/b.png` are a general sanity check — if either capture happens
to catch the Arcanist casting Q or T, the same reduction should be visible
there too.

## Self-review

- Changes are two `const` additions + two call-site edits (MeteorSigil) and
  one `const` addition + two draw-line edits (EnergyNova). No control flow,
  no signatures, no signal wiring touched.
- Both new constants are documented inline as VISUAL-ONLY with an explicit
  pointer to the (untouched) hit-radius code, so a future editor doesn't
  accidentally conflate them again.
- Reduction percentages (42.1% and 38%) both land inside the requested
  35–50% band.
- Test suite: 46/46 headless scripts green, including one new precision
  assertion added specifically to guard against the exact regression this
  task was warned about (visual shrink leaking into the hitbox).
- `nova_capture.gd` is a new tool file, not a modification to shared/critical
  code — consistent with the many other single-purpose `*_capture.gd` dev
  tools already in `godot-project/tools/`.
- Did not touch `BlastSpell`/`ZoneSpell`/`DivineRay`/`StarConvergence`/
  `BeamSpell`/`MagicCircle.gd` — scoped to the two spells explicitly named as
  the maker's observed offenders (Arcanist Q + T).

## Concerns

- None blocking. The exact shrink factors (1.9→1.1, and the 1.3/0.9→0.806/0.558
  pair) are a judgment call within the requested 35–50% band, not a measured
  "perfect" size — the brief says the maker will F5-tune, and both constants
  are now named + commented so a follow-up tweak is a one-line change.
- I did not shrink `BlastSpell`'s telegraph/shockwave (Arcanist's G / other
  classes' AoE) since it wasn't named as an offender and touching more than
  asked risks scope creep the brief explicitly warned against. If the next
  playtest flags it too, `BlastSpell.gd`'s `_draw()` (lines ~166-180) already
  has the same shape (`BLAST_RADIUS * 1.35` for the ring) and the same
  decouple pattern used for Nova would apply directly since `BLAST_RADIUS` is
  also shared with `_apply_blast_damage()`.
- This report file (`task-7-report.md`) previously held an unrelated
  Task-7-numbered report from an earlier session ("Juice: make hits crunchy",
  commit `97936ff`). It has been overwritten with this task's report per the
  report contract's file path; the old content is preserved in git history
  on this same path if needed.
