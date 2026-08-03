# RESUME HERE — 2026-08-03 handoff

Branch `bot-fight-quality` (off `main`). **146/146 suites green, working tree clean,
nothing pushed.** Everything below is committed.

## ▶ WHAT TO PLAY, AND WHAT TO LOOK AT

**F5 → title screen.** The two things most worth your eyes:

1. **THE LEGS.** They stand straight now, everywhere — hero, enemies, bosses, thralls,
   townspeople. `Enemy` DERIVES its leg constants from `CharacterRig`, so it is one
   edit and not a sweep. To look closely without squinting at a clip:
   `godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/rig_legs_capture.gd`
   (GUI binary — headless writes blank PNGs). Renders standing / walking / enemy
   presets LARGE against a ruled floor.
2. **KNOCKBACK FEELS WEAKER, AND THAT IS THE FIX.** See the warning below.

`python python-tools/make_clip.py --a 6 --b 5` → a clip that now opens on the VS card.

## ⚠ TWO THINGS THAT WILL FEEL WRONG BEFORE THEY FEEL RIGHT

- **Hero knockback is ~7x weaker.** It was being INTEGRATED as an acceleration: 6.0x
  the stated impulse at normal speed and **32x while hitstop held `time_scale` at
  0.05**, so the same shot sent a body a different distance every time depending on
  whether it triggered hitstop. `Enemy` and `Boss` always did it correctly — Hero was
  the outlier. Travel is now identical with and without hitstop. If it feels limp,
  the dial is `TuningConfig.knockback_mult` (live, F1 Director) and it now moves Hero
  and Enemy TOGETHER for the first time. That dial was already cut 1.6 -> 1.0 in a
  'knockback is too much' pass — that pass was treating this bug.
- **Ring-out mode has its own 6.0 gain** (`Hero.RINGOUT_LAUNCH_GAIN`, mirrored on
  `Enemy`) because the honest shove took ring-outs from 32/144 bouts to 0/144. Applied
  at the call site so the curve `slice_test_ringout` pins stays untouched.

## WHAT CHANGED THIS SESSION (11 commits)

| | before | after |
|---|---|---|
| knee jut at rest | 8.3% of figure height | **1.6%** |
| bot deflects / 18 duels | 3-4, in 2-3 matches | **18, in 7 matches** |
| sim outcomes | 0 kill / 15 points / 3 draw | **18 kill / 0 / 0** |
| sweep anomalies | 118 (61 error) | **6 (0 error)** |
| difficulty dial (tier 0 v 3) | 61/39 | **89/11** |
| clip length | 2.4 s, 44% a still frame | **4.6 s, opens on the VS card** |

Root causes, each measured not reasoned:

- **Legs.** Two causes that both sound negligible written down, because a two-bone IK
  takes the SQUARE ROOT of a length shortfall. (a) the body stood 3% shorter than its
  own leg bones on purpose; (b) the idle breath was SYMMETRIC, so half of every cycle
  pressed the hip 3% BELOW standing and the ground-locked feet forced it into the
  knees. Also fixed earlier: `draw_figure` drew the shin to the RAW foot while the IK
  had CLAMPED the reach, so the drawn leg reached 1.449x its own bones on 28-43% of
  moving frames.
- **Bots never parried.** `guard_style` was documented with OPPOSITE meanings on the
  two sides of the seam ('0 = press window' on Hero, '0 = BLADE ring' in BotBrain), so
  7 of 9 classes pressed the guard 0.374 s early into a window that opens immediately
  and lasts 0.16 s. The body now publishes `guard_lead` / `guard_tolerance` in seconds.
- **The sim could never report a kill.** `_die()` heals to full outside a run, so the
  poll read a body resurrected microseconds earlier. One bout burned 2319 damage across
  205 max HP and scored a DRAW. Every balance number it ever printed ranked corpses.
- **Two red suites** were CRLF line endings, not regressions. Shipped code was correct.

## STILL OPEN — ranked

1. **PLAYTEST.** Nothing here has been touched by hands. Everything is measured, which
   this file's own standing judgement calls the weaker evidence.
2. **BALANCE IS REAL AND UNTOUCHED.** 288 bouts on the honest harness: Cleric 91%,
   Warlock 84% ... Brawler 22%, Swordsaint 9%. The two LIFESTEAL classes have the two
   LOWEST damage kits and the two highest win rates — `bolt_heal` is the undercosted
   stat. A design call, not a number to pick blind. (The bot SPACING half was fixed:
   four classes stood outside their own attack range.)
3. **Clip strobe.** Full-screen white/yellow blow-out frames; measured mean luminance
   68 -> 146 -> 68 between consecutive 30 fps frames, six such jumps in the first
   twenty. `ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND = 2` exists and LOCAL rings
   are counted SEPARATELY — check whether that is the hole before retuning anything.
4. **Result card lands on live spectacle**, over taunt bubbles and a damage number.
   `FREEZE_BEAT` 0.55 s is not long enough for the killing spectacle to finish.
5. **Lag is unresolved.** Median 1.52 ms (660 fps), worst 13.99 ms over 11.6k frames,
   and every hitch reported 'built that frame: nothing'. An earlier 40 ms outlier was
   probably first-use shader compile. If it stutters in your hands, say WHEN.
6. **CRLF flip-flop.** `core.autocrlf=true`, no `.gitattributes`, so git-written files
   are CRLF and agent-written ones are LF — the next branch switch can redden a
   different suite. Durable fix is `*.gd text eol=lf` + a renormalise: a ~476-file
   diff, wants its own commit and your say-so.
7. **Harness noise not cleaned:** `spell_below_floor` fires only past the slab edge in
   empty space (23 rows of nothing); `damage_outlier` measures against TOWER hp, which
   no hero-vs-hero mode ships. Also `SigilGuard` is attached to no live body anywhere —
   the mage's magic-circle catch is dead code behind a green suite.
> **Read order for a cold start:** this file → `docs/PLAY-TONIGHT.md` (what to play
> and what is knowingly wrong) → `docs/THE-TOWER-mobile-plan.md` (the design + the
> gap analysis) → `docs/audit-fun-and-competitors.md` (the ranked findings).

---

## WHAT THIS GAME IS NOW

**THE TOWER** — a 2-player mobile co-op arena brawler. Stick figures with absurd
magic fight escalating waves on each floor of a tower until a guardian spawns.
Friendly fire is always on and is the social engine. Local wifi. The spec is
`docs/THE-TOWER-mobile-plan.md`.

**Boot: F5 → the title screen.** CLIMB · Free Play · Loadout · Host/Join · Watch
Bots · Credits. **F1 in game opens the DIRECTOR** (jump/re-roll floors, summon any
boss with any modifiers, switch class live, grant any spell, LOW quality, slow-mo,
frame-step, **F9 flags a moment**).

---

## MAKER RULINGS THAT OVERRIDE THE SPEC DOC

These were decided in play and beat anything written earlier:

- **Death = ghost until a teammate revives you; all dead = game over.** Not
  drop-a-floor. Policy dials live in `scripts/combat/DeathRules.gd` and nowhere else.
- **Keep 9 classes and 8 mob types.** The spec's "4 classes / 3 mob types" is
  overruled. Do not propose cutting them again.
- **5 floors, seeded-randomised** rather than the spec's 15 + procedural.
- **The town is the front door** — start there, or press CLIMB and skip it entirely.
- **The AI/LLM/NPC-memory stack is DELETED** (43 files, −2,884 lines). Townspeople
  speak via `Bark` + `Gibberish`. Do not resurrect it.
- **Floor duration:** the spec's "4–7 minutes per floor" has the wrong unit.
  Competitor data says the *climb* is the right target. A climb is ~6:30 and in
  window. `tools/floor_sim.gd` now judges the climb, not the floor.

---

## THE STANDING JUDGEMENT — repeat it, do not soften it

**Every feel number in this stack is reasoning, not feel.** The maker's one-line
complaints from ~40 minutes of live play found more real bugs than the entire
134-suite test run ever has. A sample from that one session, all of which had been
green:

- Bots had **never dodged, guarded or jumped** — a null-returning helper killed the
  whole reflex layer.
- Bot fighters were **literally immortal** — three stacked causes, incl. `Hero._die()`
  running `hp = max_hp` in the same call as the fatal hit.
- The rig was **dropping a quarter of its steps** at 60 Hz (gait ran per-frame; 29
  plants vs 36 at 120 Hz), which is what "walking weird on his legs" was.
- All seven of Hero's Q spells had **no `caster_node`**, so they self-damaged under
  friendly fire *and* were silently inert in the whole reaction system.
- **Spell handoff had never worked once** — it asked heroes for members that exist
  nowhere, and `bool(null)` aborts the enclosing function.
- The cast circle drew **the caster's element, not the spell's**.
- `blink` read a hard-Y-zeroed vector, so it could only go left/right.
- Exiting Free Play dumped you in a **different game's parked village**.

**Playtest beats reasoning every time. Ship things the maker can press.**

---

## TRAPS THAT COST REAL TIME (do not rediscover)

- **`failed += _test_x()` IS BANNED.** A dead property read aborts the enclosing
  function and returns the type's zero, which that idiom reads as "no failures" — it
  silently disabled 64 suites once. Accumulate failures on a **member** and record a
  per-test **completion sentinel** so an aborted test fails BY ABSENCE.
  `tools/slice_test_loadout.gd` is the reference. Also check for `quit(0)` after
  `quit(1)` — one suite always exited 0, hiding its own failures.
- **An invariant that is trivially true of an empty result is not an invariant.**
  Three bugs deleted an entire ledge skyline while the geometry suite stayed green.
  Assert a minimum occurrence rate.
- **A test stub declaring members the shipped class lacks is a fixture more generous
  than reality.** Assert against real scenes.
- **`set()` on an undeclared property is a SILENT no-op.** A spectacle must declare
  `element_id`, `spell_tier`, `caster_node`, `target_group`, `_target_group`.
- **A spectacle built without a caster is silently inert in the reaction system.**
- **Spectacles park at the arena origin** — `global_position` is (0,0), NOT where the
  effect is.
- **`take_damage` ships two signatures** — always route through `SpellTargets.hurt()`.
- **Autoloads are NOT global identifiers under `--script`** (the *nodes* ARE on the
  tree — use a tree lookup). Naming one inside a **static** function breaks the whole
  compile chain and reports as an unrelated missing method.
- **`--headless --import` REWRITES `project.godot`** and silently deletes
  `physics_ticks_per_second`, `rendering_method` and `rendering_method.mobile`.
  `slice_test_mobile_config` guards it. Check after importing.
- **`Performance.TIME_PROCESS` excludes `_draw`.** 40k draw primitives moved it
  0.0000 ms while wall-clock moved 9.2 ms. Every perf figure in `docs/mobile-export.md`
  is process+physics only; draw cost is *on top*.
- **Wall-clock here cannot measure sub-millisecond work** — non-monotonic by 20×.
  Assert deterministic work counters, not milliseconds.
- Group drift: `"hero"` (tower) vs `"player"` (old hub) vs `"mortal"` (faction-blind
  fighters). **Crates are deliberately NOT in `mortal`** — they have their own scan,
  and being in both made them take every hit twice.
- Captures need the **GUI binary**; `--headless` renders blank PNGs while reporting
  success.

---

## HOW TO VERIFY

```
python python-tools/run_all_tests.py --jobs 8        # 134 suites, ~75s
python-tools/coop_smoketest.sh                       # 2-process, prints VERDICT
python python-tools/run_capture.py <name>            # GUI binary; docs/capture-tools.md indexes ~69
python python-tools/make_clip.py --a 6 --b 5         # bot-vs-bot clip
```
A sweep taken while anything else is writing **lies** — re-run before concluding.

---

## OPEN / NEXT

1. **PLAYTEST.** Nothing since the last round has been touched by hands.
2. **ffmpeg is now installed** (`winget`, 2026-08-02) but needs a **fresh shell** for
   PATH. `make_clip.py` auto-detects it and will emit **MP4 instead of an 11 MB GIF**.
3. **No Android build has ever been made.** Needs export templates, JDK 17, SDK,
   keystore — all human steps in `docs/mobile-export.md`. Delete the `MCPRuntime`
   autoload before any export; `tools/release_gate_dev_bridge.gd` fails until you do.
4. **Perf: ~30 ms CPU at the 8-effect ceiling on desktop**, est. 90–150 ms on a
   3-year-old mid-range Android — and that excludes `_draw`. The 25-entity crowd is
   NOT the problem; spell effects are. Partially addressed, not closed.
5. **Music has no recorded licence provenance.** Six tracks, nothing in the repo says
   where they came from. Settle before anything public. Pepper Sound Pack attribution
   IS on the credits screen.
6. **Dead LLM plumbing left in `GameState.gd`**: `returned_to_hub`, `RUN_FACT_PREFIX`,
   `KEY_FACTS_CAP`, `_pending_ingest`, `apply_run_to_hub_npcs()`, `build_run_fact()`,
   `merge_run_fact`, `ingest_run_fact()`. Keep `HUB_SCENE`/`visit_hub()`. Stale
   comments claiming "the hub needs a local Ollama" in `FreePlay.gd:58`,
   `BotMatch.gd:73`, `VersusArena.gd:1444`, `Net.gd:306`, `Gibberish.gd:179`.
7. **Balance, reported not acted on:** head/body gear are **pure upside** (each slot
   has a strictly-best answer — a checklist, not a choice; the weapon slot trades
   correctly). Brawler win rate is disputed between two harnesses — needs a real sweep.
8. **Co-op gaps:** Herald/Keen elite voices are host-only; `DestructibleTerrain` /
   `BreakablePlatform` have no authority guard (only crates do). Everything is
   **loopback-verified only — never two real machines.**
9. **Nothing has ever touched a touchscreen.** Every touch constant is a declared guess.
10. **Nobody has heard the audio mix.** 248 keys mined by filename/duration. Clips are
    silent (PNG frame-grabs carry no audio), so the mix can only be judged in-game.

---

## FILE MAP (the bits that matter)

`Hero.gd` combat body · `CharacterRig.gd` the two-spring rig (**hand-tuned, do not
"improve"**) · `SpellCaster.gd` data→spectacle dispatcher · `SpellLibrary.gd` 38-spell
catalog + `CLASS_KITS`/`SLOT_ROLES` · `MagicCircle.gd`/`SpellSigil.gd` the summoning
circles (**the maker's favourite thing**) · `Encounter.gd` waves/elites/entity cap ·
`scripts/tower/FloorGen.gd` seeded floor generator · `BossRoster.gd` + `bossmods/` ·
`elitemods/` · `Net.gd` co-op spine · `GameState.gd` run spine + climb ·
`StageLayers.gd` the z-order + visual grammar · `DeathRules.gd` the two death dials ·
`World.gd` the town · `Lobby.gd` title · `tools/director/` the audit tool.
