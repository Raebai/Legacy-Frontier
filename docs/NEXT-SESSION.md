# RESUME HERE — 2026-08-14

**ASHPIRE.** Branch `bot-fight-quality`, **b01bbd8**, **171/171 green**, committed, NOT PUSHED.

Seven commits this session. Everything below is committed and headless-verified.
**None of it has been played.** Two things were verified by LOOKING at rendered
frames (the weather and the vertical clip); the rest is measured or tested.

## ▶ THE ONE THAT MATTERS MOST

**All ten biome walls were dead code and every test in the repo was green over it.**

`FloorDecor._draw_motif` is a ten-arm match on the biome NAME — Ashfall's broken
gantry, Verdant's canopy and hanging roots, Frostmarch's icicles, the Crimson
banners, the Vault's niches, Emberworks' furnace mouths, Glasswood's leaning panes,
the Drowned Gallery's waterline, Stormreach's masts, the Apex's stars. All authored,
all shipped, **none ever drawn.**

`Arena._apply_decor` keyed it on `theme.resource_path`. That is set by the LOADER,
and no `EnvTheme` is ever loaded — every one is built in code and there is not a
single theme `.tres` on disk. So the key was `""` on every floor of every run and
all ten fell through to the generic arcade wall. **The climb looked like one room
re-tinted ten times because that is what it was.**

Second fault beside it: `FloorGen._jitter_theme` copied `name` + `wash_tint` and
stopped, resetting `light` on every generated floor. That is the "dim lights as you
climb" dial; the authored spread runs 0.68 → 1.18, and flattening it to 1.0 meant
the deeper you went, the less the tower changed.

`slice_test_biome_walls` guards the AGREEMENT between the two files, so a rename on
either side is a red build. Negative-controlled.

## ▶ WHAT ELSE SHIPPED

| what | where | verified how |
|---|---|---|
| **Ten biomes, ten weathers** — ash, leaves, snow, embers, bubbles, rain, glint, starfall | `EnvTheme.weather`, `GameState.BIOMES.wx`, `Atmosphere.build_weather` | rendered + looked at, `tools/weather_capture.gd` |
| **Weather costs +1 draw call, +104 primitives, 2.22% screen fill** worst case | `tools/weather_perf_probe.gd` | measured; budget pinned at 6% and negative-controlled |
| **Three of nine ults ended on the wrong screen or none** | HeavensWrath, FaultLine, GraveTide | `slice_test_ult_punctuation`, negative-controlled |
| **Vertical clips render 9:16 natively** instead of cropping a column | `tools/bot_clip_capture.gd` | rendered + looked at |
| **Portrait camera framing** — own margin, ceiling and ground line | `VersusArena._update_showcase_camera` | rendered + looked at |
| **VO word bank** — 11 clips cover all 72 matchups | `python-tools/vo_bank.py`, `content/vo/` | assembled and listened to by the maker |

## ⚠ TWO INSTRUMENTS LIED THIS SESSION, BOTH CAUGHT BEFORE THEY DID DAMAGE

**The ult suite's first run reported three failures and all three were the suite.**
Grave Tide matched `Juice.impact_frame` inside the COMMENT explaining it no longer
calls it. Horizon Arc reaches Juice through a node lookup rather than the global.
Meteor Fist delegates its whole payoff to `BlastSpell`, where the frame lives. Every
one was checked against the source before being called a bug.

**The perf probe's first two metrics were garbage.** `TIME_PROCESS` read 53.488 ms
for five rows then 10.780 for the rest — a warm-up staircase. `TIME_FPS` in a
`--script` loop read 1.000, then 2007.000. Frame time is now deliberately NOT
reported; it is a device measurement, taken with PerfOverlay (F3) on the phone.

## ▶ STILL OPEN

* **The vertical shot's remaining fault is DIRECTION, not aspect.** Two fighters
  spawn 560 world px apart; holding both in a 720px frame caps zoom at 1.28. A
  two-shot of a fully separated pair cannot be large in 9:16 — geometry, not tuning.
  The lever is `ClipDirector`: follow the action and let a distant fighter leave
  frame, the way a two-shot does in any other medium.
* **Sunset and eclipse** are NOT built. Weather is precipitation; those are sky
  treatments, and the tower rooms are interiors with no sky — that work belongs in
  `FloorDecor`'s back wall, not in `Atmosphere`.
* **The spell audit's remaining list** (measured, not guessed): `ElementFx` — the
  eight hand-drawn per-element bursts — is reached by 5 spells out of 54;
  `chain_lightning` and `arc_of_fools` are visually identical (same script, same
  element, same circle, same frame); `Kind.NOVA` is fully built, has its own
  spectacle, impact frame and 14.0 shake, and NO SpellDef anywhere targets it;
  `horizon_cut` fires zero particle bursts.
* **The content programme** — researched, not built. Highest leverage: sim many
  bouts, score the ENDING SHAPE, publish only the good ones.
* **Blotato** ($29/mo, REST + MCP, TikTok+IG, comment reply) is the recommended
  posting tool. Two things to prove inside the free trial before paying: that a
  TikTok post lands PUBLIC, and that comment-reply works over the API. Trustpilot
  is contradictory on billing — pay monthly, not annual.

## ⚠ NEVER DO THIS

**Do not `git checkout --` a file that holds uncommitted work.** Done once this
session to undo a deliberate test-break; it reverted the file to HEAD and wiped the
uncommitted weather system. A backup taken a minute earlier saved it. Commit first,
then negative-control.

**Do not rewrite source files with PowerShell `Get-Content | Set-Content`.** On PS
5.1 it reads UTF-8 as ANSI and writes the damage back with a BOM.

Also: **launching the game rewrites tracked files** — check `git status` after any
launch.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 6          # 171 suites, ~100s
python python-tools/run_capture.py weather_capture     # look at the ten biomes
./godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
  --script tools/weather_perf_probe.gd                 # what the air costs
```
