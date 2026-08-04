# THE TOWER — shape, feel and front door

**Date:** 2026-08-04 · **Branch:** `bot-fight-quality` · **Status:** approved by the maker

One brief, five phases. This document is the durable record — if a session is lost
mid-build, resume from the phase table at the bottom.

---

## 0. What the maker asked for, in their words

- A title screen that looks "sexier", with a Tower-of-God-ish tower and music.
- `ENTER THE TOWER` and `MULTIPLAYER` buttons; multiplayer offers local and online.
  "way simpler and less buttons and less confusing".
- A lobby you enter, where you resume your journey and sort everything out.
- "you should not be able to cast a spell as a spell is being cast".
- Longer cooldowns, per spell — "feels a little too chaotic right now".
- Knockback is heavy; **health** preferred for PvP, with a **lives vs percentages**
  option in settings.
- Co-op starts from floor 1 with **checkpoints**, so "if you died at 15 you can
  restart at 10 with that friend". Re-treading is fine. Players must not get too
  far ahead.
- Higher-ranked players should be stronger — cooler spells, ability items.
- "more diversity on the floors like a snow place background a sunny green one
  like a red room".
- Practice "and all that stuff you can do in **a room in the lobby**".
- The TOG look: "how epic it feels… the colouring the shading the lighting… dim
  lights and things like that on certain floors as you climb".

---

## 1. Decisions, and the reasoning that must not be re-litigated

### 1.1 Casting was already blocked. The queue was the problem.

A windup **cannot** be cancelled today — `Hero._physics_process` early-returns
through `_process_channel` / `_process_summon`. So "cast while casting" was never
possible. What *was* possible: `_update_input_buffer` deliberately records presses
during a windup so the next move fires **the instant** the current one resolves.
Its own comment defends this:

> "every press made during a windup was silently thrown away: the most committed,
> most expressive moment in the game was also the one where the buttons stopped
> answering."

That buffer is why effects land **back-to-back with zero gap**, which is what the
maker means by chaotic. The fix is therefore *not* to block casting (already true)
and *not* to delete the buffer (it was added for a good reason):

- **Spells stop being buffered.** Movement and dash stay buffered — that is the
  responsiveness the buffer actually exists to protect.
- **A global cast lockout** (~0.35 s) after any cast resolves.
- Cooldowns lengthen by tier as a *second* lever, not the primary one.

### 1.2 Cooldowns were never short

Measured: ~3.4 s quick, 6–7 s mid, 12–26 s ult. A flat increase would slow ults
that are already slow. Multiplier is **tier-indexed and applied in one place** at
kit-build time — not 38 hand edits, which would rot on the next spell added.

### 1.3 Checkpoint granularity solves the co-op sync problem for free

The question "whose floor does a party play" dissolves once checkpoints are coarse:
two players in the same band already resume at the same floor. No party save track,
no per-pair bookkeeping, no host-decides-progression.

- `checkpoint_for(floor) = ((floor - 1) / BAND_SIZE) * BAND_SIZE + 1`
- **Solo:** resume at your checkpoint.
- **Co-op:** party resumes at `min(checkpoint_for(p)) over the party`.
- Re-treading happens only across a band boundary. The maker has ruled that fine.

`DeathRules.resume_floor_after_game_over(floor, total)` **already exists** and is
the only place this lands. `RESET_CLIMB_ON_GAME_OVER` sits beside it as the
companion dial. The architecture anticipated this.

### 1.4 ⚠ TOWER HEIGHT 5 → 10 OVERTURNS A PRIOR MAKER RULING

`docs/NEXT-SESSION.md` records, as a ruling that overrode the design doc:

> **5 floors, seeded-randomised** rather than the spec's 15 + procedural.

Checkpoints need a taller tower. The maker was shown this conflict explicitly and
chose **build the system, keep it short**: `TOTAL_FLOORS = 10`, `BAND_SIZE = 5`.
The reasoning is that nothing is playtested yet, so six-fold content growth before
the combat feels good is the risky move — the same logic the maker applied to
customisables. **Height and band size are single constants**, so growing to 30/10
later is a data change plus floor authoring, never a rewrite.

### 1.5 Party scaling adds bodies, not bullet sponges

`×1.6` enemy budget, `+2` concurrent cap, `×1.7` boss HP. Individual enemy stats
are untouched. This matches the tower's existing written policy — "higher floors
add modifiers, not HP" (`GameState.synthesize_floor_def`) — and friendly fire
already supplies real chaos with a second body on screen.

### 1.6 Both PvP models already exist

`VersusArena` ships HP-drain (`DUEL_HP = 260`) *and* percentage + stocks with
respawn and invuln. This phase **routes between them**; it builds no new mechanic.
Default is HEALTH per the maker.

---

## 2. Floor biomes — the diversity ask

`EnvTheme` is deliberately thin ("grows later… without touching consumers") and is
the correct seam. It gains backdrop/light fields; `wash_tint` stays for compat.

Ten floors, ten identities. Band 1 is floors 1–5, band 2 is 6–10.

| # | biome | register |
|---|---|---|
| 1 | Ashfall Verge | grey ash, dim ember light |
| 2 | Verdant Tier | **sunny green** |
| 3 | Frostmarch | **snow**, cold blue-white |
| 4 | The Crimson Room | **deep red**, oppressive |
| 5 | Sunken Vault | underground cold — band 1 guardian |
| 6 | Emberworks | molten orange |
| 7 | Glasswood | pale, ethereal |
| 8 | The Drowned Gallery | teal, submerged |
| 9 | Stormreach | violet, lightning |
| 10 | The Apex | harsh gold-white sky — final guardian |

**Dim is the default register, not a uniform colour.** Each biome is its own hue;
the moody treatment is exposure/vignette on top. That is what makes spell light
read as an actual light source, which is the TOG feel the maker described.

Names draw on the existing 17-region world design (`project_world_design` memory).

---

## 3. Navigation

```
TITLE ─ ENTER THE TOWER ─────────────▶ ANTECHAMBER (solo)
      ├ MULTIPLAYER ─ LOCAL ─────────▶ ANTECHAMBER (party)
      │             └ ONLINE ─ Host/Join ▶ ANTECHAMBER (party)
      └ ⚙ SETTINGS
```

`GameState.session_kind` (SOLO / LOCAL / ONLINE) is set before arrival; the
Antechamber reads it to show or hide the party strip. **One prep-room scene,
three entrances** — a second multiplayer lobby is the classic duplication trap.

### 3.1 The Antechamber is a ROOM, not a menu

Maker amendment: practice "and all that stuff you can do in a room in the lobby".
So it is walkable, entered with your actual hero, with a small number of stations:

| station | does |
|---|---|
| **The Gate** | DESCEND — resumes at your checkpoint. The primary verb. |
| **The Armoury** | class + spell slots + gear (existing Loadout/Outfitter UI) |
| **The Sparring Ring** | practice — absorbs Free Play and Watch Bots |
| **The Party Stone** | co-op only: who is here, ready state |

Reuses the hero controller, so walking in the lobby is walking in the game.
Keeps the *title* at two buttons while the depth lives where it belongs.

### 3.2 Naming

`Lobby.tscn` **stays the title screen** — it is the boot scene and `TITLE_SCENE`
points at it; renaming it to `Title` is a wide rename across tests for no
player-facing gain. The new prep room is `Antechamber.tscn`. Noted as a wart.

---

## 4. Deferred, deliberately

- **Rank power / cooler spells / ability items / customisation.** The maker parked
  these: "we need to work on customisables once we are happy with the base game."
  The climb design must leave a clean seam (`Rank.power` already persists) and
  nothing more.
- **Growing to 30 floors / 3 bands.** Two constants when the combat is proven.
- **Music licensing.** The six tracks still have no provenance
  (`assets/audio/CREDITS.md` §4). Title music **reuses an existing track**; this
  phase acquires nothing new and settles nothing. Flagged before any public build.

---

## 5. Phases

Phase 1 first because it is the only one that changes how the game feels in the
hand — the maker can judge it while the rest is built.

| # | phase | touches | done |
|---|---|---|---|
| 1 | **Flagged bugs + combat pacing** | `Hero.gd`, `TuningConfig.gd`, `BossDropWatcher.gd`, `EliteHerald/Keen`, `DestructibleFloor`, `Net.gd` | ✅ |
| 2 | **Climb bands + checkpoints + party scaling** | `GameState.gd`, `DeathRules.gd`, `Encounter.gd`, `Net.gd` | ✅ |
| 3 | **PvP rules + Settings** | `PauseMenu.gd` (NOT a new scene — it already is the reusable settings panel), `VersusArena.gd`, `GameState.gd` | ✅ |
| 4 | **Title + Antechamber + music** | `Lobby.gd`, `Music.gd` ✅ · **`Antechamber.tscn` NOT BUILT** — see §3.1; not stubbed on purpose, a menu under that name ships the wrong thing | ⚠ half |
| 5 | **Floor biomes + band lighting** | `EnvTheme.gd`, `GameState.BIOMES`, `Arena._apply_theme` | ✅ (also grew the tower to 10 AUTHORED floors — `total_floors()` reads the authored size, so Phase 2's constant was inert without it) |

### Verification standard for every phase

This repo's own hard-won rules apply and are not optional:

- Accumulate failures on a **member**, never `failed += _test_x()`; every test
  records a completion sentinel so an aborted test fails **by absence**.
- An invariant trivially true of an empty result is not an invariant — assert a
  minimum occurrence.
- A stub more generous than the shipped class is not a fixture. Assert against
  real scenes.
- **Prove each new test catches its bug** by breaking the fix and watching it go
  red. Measurement is the weaker evidence; a test that has never failed is worth
  less than one that has.
- `python python-tools/run_all_tests.py --jobs 8` green before every commit.
