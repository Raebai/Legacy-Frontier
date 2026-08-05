# TWO NEW GUARDIANS — designed, measured, NOT BUILT

Status: **design + audit complete, code not applied.** Written 2026-08-05 so the
measurement and the contract survive; the implementation is a session's work from here.

---

## 1 · THE MEASUREMENT THAT JUSTIFIES IT

`data/towers/ashspire.tres` **does not exist** — the tower is built in code by
`GameState.build_default_tower()`, and **no floor pins a boss**, so every floor rolls.

Measured over 200 climbs (`tools/_probe_boss_audit.gd`):

| | value |
|---|---|
| bosses in the roster | **4** (guardian, scribble, cartographer, illuminator) |
| full-ceremony floors | **only 5 and 10** — the other eight are minis at `body_scale` 0.45–0.62 |
| eligible pool, floors 4–10 | **3** (the Scribble's window closes at floor 3 and nothing replaces it) |
| distinct artists per 10-floor climb | **~3.7 of 4** |
| mean Guardian appearances per climb | **~3.3**, and up to 8 |

So each artist is fought ~2.7 times and the deep half of the tower draws from three.
The 7 modifiers re-skin the repeats, but **the question the fight asks** repeats with
them. Two more guardians takes the deep pool 3 → 5 and the mean repeat 2.7 → ~1.7.

---

## 2 · THE CONTRACT A NEW BOSS MUST SATISFY

⚠ **This is the most valuable part of this document.** A boss that misses any of these
is *silently* broken — no error, no red suite.

1. `_phase_attack_ids(1|2|3)` returns ≥2 ids each, and phase 3 ≠ phase 1.
2. `phase_cooldown(3) < phase_cooldown(1)`.
3. Every attack id is **unique across the whole roster** (`slice_test_bossmods` asserts
   one owner per id).
4. Every attack telegraphs via `TowerBoss.lane_tell` / `zone_tell` / `summon_circle`.
   ⚠ Those pass **`"no_resolve": true`** — MANDATORY, because every boss is an `Enemy`
   carrying archetype BRUTE, and without it `Enemy._on_telegraph_fired` answers your
   tell with a **brute ground strike** instead of your attack.
5. Every attack calls `_bfx(kind, data)` — `slice_test_bossnet` fails any id that puts
   nothing on the wire within 2.6 s. `_bfx` is host-gated internally.
6. ⚠ **Only 15 kinds exist** in `Net._client_boss_fx`: `beam, pillar, ray, meteor,
   convergence, nova, slam, crater, root, zone, circle, burst, dash, beat, spell`.
   A 16th falls through the `match` **in total silence**. A new boss composes from
   this vocabulary; it does not invent one.
7. Spectacles go through `TowerBoss.spawn_spectacle(path, element, tier)`, which sets
   `target_group`, `_target_group`, `caster_node`, `element_id`, `spell_tier`. `set()`
   on an undeclared property is a **silent no-op**; a spectacle with no caster is
   **inert in the reaction layer with no error**. `EnergyNova` is a `.tscn` and cannot
   go through `spawn_spectacle` — set all five by hand (copy `ScribbleBoss._atk_tantrum`).
8. Spectacles **park at the arena origin**. Never read a spectacle's `global_position`.
9. Damage routes through `SpellTargets.hurt()` — `take_damage` ships two arities.
10. Do **not** override `take_damage` / `apply_knockback` / `_die` / `_physics_process`
    without `super` — all four carry the co-op authority path. `ScribbleBoss` shows the
    legal shape.
11. Identity virtuals: `boss_title`, `boss_accent`, `boss_epithet` (non-empty),
    `bark_suffix` (**with 4 authored rows in `ui/Bark.gd`** + a `MOODS` entry each),
    `redraw_style` (**unique per boss**), `boss_tint`, `boss_rig_height` (**unique per
    boss**), `boss_preset`.
12. `Boss._ready` order is `_fit_box_to_scale()` → `rig.height = boss_rig_height() *
    body_scale` → `_realign_feet()` → `refresh_hurtbox()`. A subclass `_ready` calls
    `super._ready()` FIRST. The scene's shape must be a `RectangleShape2D` or
    `_fit_box_to_scale` cannot see it and the body is born 12 px inside the floor.

---

## 3 · THE TWO DESIGNS

Chosen against the four answers already taken — out-time (Scribble) / out-position
(Cartographer) / survive-then-punish (Illuminator) / generalist (Guardian).

### THE ERASER — `eraser`, floors 1–6
*The hand that takes the page back.*

**The player must come to it and STAY.** Every other fight is about making space; this
one eats the room permanently (erased patches last ~9 s and **accumulate**) and the one
place it never erases is under its own feet. Kiting loses.

| attack | phases | what it does |
|---|---|---|
| `smudge` | 1,2,3 | one persistent erased patch on your ground — the clock |
| `press` | 1,2,3 | close nova; the **near** edge of the pocket, so "stay near" is a band not a corner |
| `swathe` | 2,3 | four patches marching *away* from the boss — herds you inward |
| `smear` | 2,3 | a scrawl that DRAGS you off your clean ground |
| `unmake` | 3 | six patches at ±150/±260/±370 with a clean ±110 pocket — the thesis, stated |

Cadence 2.2 → 1.7 → 1.3. Redraw hand `erase`. Accent `(0.95,0.72,0.74)`, rig 78,
preset `juggernaut`, `hp_scale` 0.94, `speed_scale` 0.80.

⚠ **Named weakness:** this is spatial, and so is the Cartographer. The separation is
real but is of KIND — the Cartographer's page RESETS between figures (read and step),
this one's never does (commit and shrink). **If a playtest says they feel the same,
this is the one to cut.**

### THE ETCHER — `etcher`, floors 3+
*A copper plate, bitten in acid.*

**The answer to its biggest tell is to walk toward it and hit it.** `bath` is a 2.2 s
rooted wind-up resolving into the heaviest single hit in the kit — and it is
**BREAKABLE**: land `max_hp * 0.055` inside the window and the cast aborts, the boss
staggers 1.6 s, and that stagger is a free window it handed you by failing.

The price is `mordant`: an acid pool it opens **under itself**, so getting close enough
to break the bath costs HP. Without it the boss is a QTE.

| attack | phases | what it does |
|---|---|---|
| `bite` | 1,2,3 | fast ray — stops "idle until the next bath" being a strategy |
| `foul` | 1,2 | short pool on your ground — range is not free either |
| `mordant` | 2,3 | pool under ITSELF — the price of the break |
| `bath` | 1,2,3 | the breakable cast; unbroken → arena convergence, 46 dmg |
| `plate` | 3 | two baths back to back, shorter, ×1.5 break threshold |

Cadence 2.6 → 2.1 → 1.6. Redraw hand `bite`. Accent `(0.45,0.95,0.62)`, rig 86,
preset `warlock`, `hp_scale` 1.05, `speed_scale` 0.55.

⚠ The break must be sampled in `_physics_process` (after `super`), **not** in
`take_damage` — that function carries the co-op authority path. Read `hp`, which the
enemy synchronizer already replicates. Nothing new crosses the wire.

⚠ The Telegraph fires on its own clock whatever happens, so a broken bath must
**early-return** in `_bath_resolve`. That is the one place the mechanic can silently do
nothing.

---

## 4 · WIRING

- `BossRoster.ENTRIES`: **append** the two rows. ⚠ `entry()` falls back to `ENTRIES[1]`
  **by index**, so the Guardian must stay at index 1 forever — inserting above it
  silently changes what an unknown boss id degrades to.
- `ui/Bark.gd`: 4 rows × 2 bosses + 8 `MOODS` entries, or both fall back to the generic
  guardian voice and `slice_test_bossvoice` fails.
- **No tower data change is required** — nothing pins a boss, so the rows are live on
  the first run.
- The two new redraw hands need their own file (`PageRedrawExtra.gd`): the base's page
  is an inner class of the shared `Boss.gd`, and `_redraw_the_page` is overridable.

Projected after: deep pool 3 → 4 eligible, mean Guardian appearances ~3.3 → ~2.1,
distinct artists ~3.7/4 → ~4.6/6.

---

## 5 · ⚠ FOUR SUITES HARDCODE THE BOSS COUNT

This is why adding a boss is more expensive than it looks, and it is worth fixing FIRST:

| suite | breaks how |
|---|---|
| `slice_test_bossroster` | `_expect(ids.size() == 4, …)` |
| `slice_test_bossmods` | hardcoded 3-id list, `heights.size() == 3`, `owners.size() == 3` |
| `slice_test_bossnet` | two hardcoded 4-id lists |
| `slice_test_bossvoice` | `ALL_BOSSES` is a 4-entry const |

**Drive all four off `BossRoster.ids()`** and the *next* boss costs zero suite edits.

Also: `slice_test_boss.gd` has **no completion sentinel**, so a dead property read
aborts `_run()` and it prints `all PASS`. It is the only suite walking the real
Encounter→boss spawn path, so it is the worst one able to pass vacuously. Retrofit
`TESTS` + `_completed` + the by-absence sweep.

---

## 6 · MINI-BOSSES — recommendation

`body_scale` already produces mini-guardians on **eight of ten floors**. So the tower
has them; the question is whether it needs a second kind.

**Recommend: elite-modified ordinary enemies** (`scripts/combat/elitemods/` +
`EliteRoster`, already built and tested), and **reject new mini-boss bodies** — each
would have to satisfy the entire 12-point contract above for a body fought for ten
seconds.

The concrete gap is not a body, it is a **wave slot**: `WaveDef` has no "this wave is
one named body" shape, so elites arrive scattered rather than as an event. A
`WaveDef.elite_wave: bool` that spends the floor's whole elite budget into one
low-count wave is ~30 lines against a system already built, versus ~600 for two more
boss bodies.
