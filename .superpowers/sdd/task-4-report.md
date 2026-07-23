# Task 4 report — Smash damage-% + ring-out death model (sandbox mode flag)

> Supersedes an earlier unrelated "Task 4 — Auto-aim targeting" note that used to
> live at this path (different plan/numbering).

## Outcome
Shipped the Super-Smash-Bros model in the SANDBOX only, gated behind a
`GameState.ringout_mode` flag (per the brief's architectural resolution — NOT a
global `hp`-repurpose). The tower (`Arena.gd`) is untouched and keeps hp-death;
every tower/climb slice test stays green. All 42 slice suites pass, including the
new `slice_test_ringout`.

## Mode-flag design
- `GameState.ringout_mode: bool = false` (new autoload field). Default false =
  tower behaviour everywhere.
- `VersusArena._ready()` sets it **true**; `VersusArena._exit_to_hub()` sets it
  **false**; `GameState.enter_run()` and `enter_coop_run()` both force it **false**
  at the top. So a tower run — SP or co-op — can never be in ring-out mode
  regardless of how the player got there (belt + suspenders: the arena clears it on
  exit AND every run entry re-clears it).
- Hero/Enemy/CharacterBars read the flag via a guarded `/root/GameState` lookup
  (`_is_ringout_mode()`), so a bare instance or headless context without the
  autoload safely reads false.

## Damage / knockback model
- New `damage_pct: float = 0.0` on **both** Hero and Enemy (the `hp` field is kept
  intact for tower mode — no rename, no touched call sites).
- `PCT_PER_DAMAGE = 0.8` (shared const in Hero and Enemy). Rationale: typical hits
  land 12–28 damage → +10–22% each, so % builds over a fight (single-to-low-double
  digits per hit) instead of spiking. Cumulative ~125 damage → 100% → 2× knockback.
  A natural `Tuning` candidate later.
- `take_damage(amount)` signature is UNCHANGED (all ~15 call sites compile as-is).
  Internally it branches on `_is_ringout_mode()`:
  - ON: `damage_pct += amount * PCT_PER_DAMAGE`; hp left untouched; `_die()` NOT
    called (`if hp == 0: _die()` gated to `if not ringout and hp == 0`). All juice
    (flash, hit-stop, shake, damage number, hurt anim) preserved.
  - OFF: unchanged — hp drains, hp==0 → `_die()` (tower behaviour, byte-identical).
- Knockback scales with the VICTIM's % (correct Smash semantics — the fighter being
  hit flies farther). At the `impulse *= knockback_mult` site in both
  `apply_knockback`s: `if _is_ringout_mode(): impulse *= ringout_knockback_scale(damage_pct)`.
  `ringout_knockback_scale(pct)` is a pure static helper (`1.0 + pct/100.0`) on both
  classes — the headless-testable seam. Tower mode leaves knockback exactly as-is.

## Ring-out is the only elimination (sandbox)
`StageHazard.fighter_fell → VersusArena._on_fighter_fell` is unchanged and remains
the sole elimination path: hero → stock loss/respawn; enemy → `queue_free()` +
counts down "Bots left" via `_bots_alive()`. Because damage no longer kills bots in
ring-out mode, bots can ONLY be removed by a pit ring-out — and the round still ends
(VICTORY) once every real bot is ringed out. `damage_pct` resets to 0 on respawn in
`VersusArena._respawn` (hero + bot) and in `Enemy._respawn_passive` (dummy).

## Dummies (Task 1) interaction
Practice dummies (`passive`, `DUMMY_HP=9999`) never reach hp==0 in ring-out mode, so
they can't `_die` from hits — pure punching bags that now show a rising %. Their
group-`dummy` exclusion from `_bots_alive()` is untouched, so they never block the
win condition. If ever ringed out (they stand far from pits), the near-infinite
`DUMMY_STOCKS` respawns them through the normal registry path (now also zeroing %).

## CharacterBars
`CharacterBars` (child of both Hero + Enemy, poll-don't-push) now checks
`GameState.ringout_mode` each frame. When on, it renders the damage `%`: a warm→red
fill (`PCT_WARM`→`PCT_RED`, saturating at `PCT_VISUAL_MAX=150%`) plus the number
itself climbing over the head (`draw_string`, dark-outlined). When off, it renders
the green→yellow→red HP bar exactly as before.

## Co-op / tower safety
- Co-op death is `_enter_downed()`, checked FIRST in `Hero._die` (before any
  ring-out/run logic) — untouched. And `enter_coop_run` forces `ringout_mode=false`,
  so co-op never enters the Smash branch: hp still drains, downed still fires.
- `Arena.gd` (tower), the rig, movement consts, and Hero's AIR-state selection were
  not touched.

## Files touched
- `godot-project/scripts/GameState.gd` — `ringout_mode` field; force-false in
  `enter_run` + `enter_coop_run`.
- `godot-project/scripts/combat/Hero.gd` — `damage_pct` + `PCT_PER_DAMAGE`;
  `ringout_knockback_scale` (static) + `_is_ringout_mode`; branch in `take_damage`;
  knockback scale in `apply_knockback`.
- `godot-project/scripts/combat/Enemy.gd` — same as Hero, plus `damage_pct` reset in
  `_respawn_passive`.
- `godot-project/scripts/combat/VersusArena.gd` — set flag on in `_ready`, off in
  `_exit_to_hub`; reset `damage_pct` in `_respawn`.
- `godot-project/scripts/combat/CharacterBars.gd` — render % (warm→red + number) in
  ring-out mode.
- `godot-project/tools/slice_test_ringout.gd` — new headless suite (5 tests).

## Suites updated
None. `slice3_test_versus` already drives eliminations exclusively through the
ring-out path (`_on_fighter_fell`), never hp-death for bots, so it passes unchanged
even though `VersusArena._ready` now flips `ringout_mode` true for it.
`slice_test_sandbox` loads `VersusArena.tscn` (also flips the flag) but only asserts
dummy existence/flags/position — unaffected. All other suites never load VersusArena,
so `ringout_mode` stays default-false and hp-death is exercised as before.

## Verification
- `tools/slice_test_ringout.gd`: `ringout tests: all PASS`. Covers: (a) pure scale
  0%→1.0x / 100%→2.0x, Hero==Enemy; (b) take_damage raises damage_pct and does NOT
  kill hero or bot at huge damage; (c) live apply_knockback ~2× at 100% vs 0%;
  (d) full VersusArena — damage can't remove a bot, ring-out through the pit path
  does, round ends VICTORY with all real bots out and dummies alive; (e) with
  `ringout_mode=false`, hp drains on a hit and a lethal hit frees the bot (hp-death).
- Full sweep: 42/42 slice suites PASS (tower/climb: `slice_test_climb`,
  `slice2_test_runloop`, `slice_test_floor`, `slice_test_boss`, `slice_test_coop` —
  all green). Headless `--import` clean.

## Self-review / concerns
- **UNPLAYTESTED feel:** `PCT_PER_DAMAGE=0.8` and `PCT_VISUAL_MAX=150` are best
  guesses; whether high-% knockback actually reaches the far-L/R blast zones is a
  feel question only F5 answers. Both cheap to retune (candidates for `Tuning`).
- **Flag is global runtime state.** The only writer that turns it ON is VersusArena;
  every tower entry + the arena exit turn it OFF. I traced the transitions and see no
  leak, but correctness rests on that discipline rather than a scene-local scope. A
  future non-tower combat scene must set its mode explicitly.
- **CharacterBars %-draw** is only visible in the live sandbox (not headless-drawn);
  compiled clean on import but its exact look is unconfirmed until playtest —
  consistent with the project's current UNPLAYTESTED status.
- **Co-op** was verified only through the existing construction test + code trace
  (`enter_coop_run` clears the flag; `_enter_downed` unchanged); a real 2-machine
  session wasn't exercised.

## Fix pass

Closed three review findings on the mode-flag/damage-% work above. The
`GameState.ringout_mode` boundary itself (writers/readers, `Arena.gd`, movement,
the rig) was NOT touched, per the review's instruction.

### Finding 1 (Important) — bomber self-detonation bypassed ring-out
`Enemy._detonate()` (~Enemy.gd:1112) called `_die()` unconditionally, and `_die()`
`queue_free()`s a non-passive enemy — which `_bots_alive()` counts as eliminated.
That let a BOMBER remove itself from the match independent of a ring-out,
violating "ring-out is the sole elimination." Fixed by gating the `_die()` call:
```gdscript
	Juice.shake_camera(7.0)
	Sfx.play("blast")
	# Ring-out is the SOLE elimination path in the sandbox (see _is_ringout_mode
	# throughout this file): a bomber's own detonation must not self-remove it via
	# _die()/queue_free(), even though the AoE damage/knockback above is unchanged.
	# BOMBER is currently excluded from VersusArena.BOT_ARCHETYPES, so this branch
	# is dormant today; if BOMBER is ever added to the sandbox roster, revisit
	# whether a ring-out-surviving bomber should recover into CHASE/RECOVER here.
	if not _is_ringout_mode():
		_die()
```
The AoE damage + knockback + VFX/SFX block above the guard is byte-identical —
only the trailing `_die()` call is gated. In tower mode (`_is_ringout_mode()`
false) behaviour is unchanged: the bomber always dies on detonation, exactly as
before. In ring-out mode a detonating bomber now survives (does its blast, keeps
standing) instead of quietly vanishing outside the pit path. BOMBER is still
excluded from `VersusArena.BOT_ARCHETYPES = [2,4,5,3,7]`, so this is dormant in
the current sandbox roster; left a comment flagging that a future BOMBER addition
should reconsider whether it needs a real post-detonation state (it currently sits
in whatever `_attack_state` it had, i.e. WINDUP, rather than recovering to CHASE —
acceptable for a dormant path per the review's own scoping, but worth a follow-up
if BOMBER ever ships to the sandbox).

Not separately unit-tested with a live bomber (driving a BOMBER through its
windup->telegraph-fired->detonate sequence headlessly would require faking the
hero-proximity trigger and telegraph timer, and BOMBER isn't reachable through
`VersusArena.BOT_ARCHETYPES` today) — verified by code-path inspection: the only
call site of `Enemy._die()` inside `_detonate()` is now behind
`if not _is_ringout_mode()`, so in ring-out mode the queue_free/elimination branch
in `_die()` (and its `passive` respawn branch) is provably unreachable from
`_detonate()`. The existing `_test_ring_out_is_the_only_elimination` suite
continues to pass unchanged (it doesn't drive BOMBER, since BOMBER isn't in the
sandbox roster), confirming no regression to the archetypes that ARE active.

### Finding 2 (Minor) — hero-side ring-out was untested
Added `_test_hero_ring_out()` to `tools/slice_test_ringout.gd`, matching the
existing helper/assertion style (`_expect`, fresh `arena_script.new()` instance,
`entry["invuln"] = 0.0` before each `_on_fighter_fell` call, mirroring
`_test_ring_out_is_the_only_elimination`). It:
1. Spins up its own `VersusArena` and confirms `ringout_mode` is on.
2. Reads `arena._p1` (the hero body — confirmed via `VersusArena.gd`: `_p1` is
   the field the arena's own registry/build/respawn code uses for the hero) and
   sets `damage_pct = 42.0` to simulate mid-fight state.
3. Fall #1 (`arena._on_fighter_fell(arena._p1)` with stocks remaining): asserts
   stocks decremented by exactly 1, `damage_pct` reset to `0.0` (via
   `VersusArena._respawn`, which zeroes `damage_pct` on any body that has the
   property), and the match is NOT yet over.
4. Burns the rest of P1's stocks through the same pit path; asserts the final
   fall sets `_match_over = true` and shows a `"DEFEAT"`-prefixed banner (the
   non-enemy branch of `VersusArena._eliminate`).
Wired into the suite's `_process` runner alongside the existing 5 tests.

### Finding 3 (Minor) — `PCT_PER_DAMAGE` duplicated
Removed the two independent `const PCT_PER_DAMAGE: float = 0.8` declarations
(Hero.gd, Enemy.gd) and made it a single shared field, following the exact
pattern the codebase already uses for shared live-tunable combat constants
(`TuningConfig.knockback_mult`, read via `Hero._tune()` / `Enemy._knockback_mult()`):
- **New home:** `TuningConfig.gd`, `Combat feel` export group —
  `@export var pct_per_damage: float = 0.8`. Lives in the same live-tunable
  Resource (`res://data/tuning.tres`, autoload `Tuning`) as `knockback_mult`, so
  it can be retuned from the inspector or Remote debugger without a relaunch —
  the value is a `Tuning` candidate, so it now literally IS one. `pct_per_damage`
  is not present in the checked-in `data/tuning.tres` (same as `knockback_mult`,
  `hit_stop_enabled`, `post_process_enabled`, etc. — TuningConfig's documented
  contract is that an unset field falls back to the script default, so no `.tres`
  edit was needed or made).
- **Hero.gd** (`take_damage`): reads it via the existing `_tune("pct_per_damage", 0.8)`
  helper (same helper already used for `hurt_hit_stop`/`hurt_shake`/`knockback_mult`).
- **Enemy.gd** (`take_damage`): added `_pct_per_damage()`, a guarded
  `/root/Tuning` lookup that mirrors `_knockback_mult()`'s exact shape
  (null-safe, falls back to `0.8` if the autoload/cfg/field is missing — headless
  contexts without the autoload behave exactly as before).
Both call sites (`Hero.take_damage`, `Enemy.take_damage`) now read the one
value; no other call sites existed (confirmed via a repo-wide grep for
`PCT_PER_DAMAGE` — zero remaining references after the edit). The knockback-scale
path (`ringout_knockback_scale`, `apply_knockback`) doesn't use this constant at
all (it operates on the already-accrued `damage_pct`, not the per-hit conversion
rate), so it was untouched, exactly as scoped.

### Test commands + output
```
$ ./godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --import
... [DONE] first_scan_filesystem / update_scripts_classes / loading_editor_layout, zero errors

$ ./godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_ringout.gd
ringout tests: all PASS
(exit code 0; benign "ObjectDB instances leaked at exit" / "resources still in
use at exit" warnings are pre-existing test-harness behaviour — the suite never
frees its scratch Hero/Enemy/VersusArena instances, matching the existing
`_test_ring_out_is_the_only_elimination` pattern — not a regression)

$ for f in godot-project/tools/slice*_test_*.gd; do
    godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script "tools/$(basename "$f")"
  done
```
Full sweep: **42/42 slice suites PASS**, exit code 0 on every one, including
`slice_test_climb`, `slice2_test_runloop`, `slice_test_floor`, `slice_test_boss`,
`slice_test_coop`, `slice3_test_versus`, `slice_test_sandbox`, and the extended
`slice_test_ringout` (now 6 test functions, was 5). No regressions.

### Files touched (fix pass)
- `godot-project/scripts/combat/Enemy.gd` — gate `_detonate()`'s `_die()` call on
  `not _is_ringout_mode()`; new `_pct_per_damage()` helper; `take_damage` reads it.
- `godot-project/scripts/combat/Hero.gd` — removed the local `PCT_PER_DAMAGE`
  const; `take_damage` reads `_tune("pct_per_damage", 0.8)` instead.
- `godot-project/scripts/combat/TuningConfig.gd` — new `pct_per_damage` export
  in the `Combat feel` group.
- `godot-project/tools/slice_test_ringout.gd` — new `_test_hero_ring_out()`.

### Concerns carried forward
- Finding 1's fix is code-path-verified, not exercised through a live BOMBER
  detonation (BOMBER is dormant in the sandbox roster today — same caveat the
  finding itself named). If/when BOMBER joins `VersusArena.BOT_ARCHETYPES`, add a
  driven test (fake hero proximity + advance the telegraph timer to fire) and
  decide whether a surviving bomber should transition out of WINDUP.
- `pct_per_damage`'s value is unchanged (0.8) — this is a pure de-duplication /
  single-source-of-truth refactor, not a retune. Feel is still UNPLAYTESTED per
  the base report.
