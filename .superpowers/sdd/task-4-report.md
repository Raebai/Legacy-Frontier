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
