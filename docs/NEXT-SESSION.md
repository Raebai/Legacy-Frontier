# RESUME HERE — 2026-08-14

**ASHPIRE.** Branch `bot-fight-quality`, **8b551c9**, **171/171 green**, pushed, clean.

Fourteen commits. Everything below is committed, headless-verified and **unplayed
since it was fixed** — except where it says "verified by looking", which means a real
frame was rendered and examined.

## ▶ THE THREE THAT CHANGE THE MOST

**1. Every fight ended pressed against a wall because a bot could only jump 36 px.**
`Hero` has variable jump height (`Hero.gd:2295` halves upward velocity the frame jump
is RELEASED while rising). The brain emits `jump` for ONE frame and `drive()` rebuilds
the held set every tick, so the release landed on frame two of every jump a bot ever
made: apex ≈ 35.6 px against a human's 105.3. Every terrace riser is 68–84 and every
tower ledge ≥ 72, so **no bot could climb any surface in any stage.** Fixed in the
hands (`BotController._hold_the_jump`, 18 frames) not the brain. Second half:
`BotBrain._unwall` jumped while steering AWAY from the wall — it now steers into it.

**2. All ten biome walls were dead code and 170 tests were green over it.**
`Arena._apply_decor` keyed `FloorDecor` on `theme.resource_path`, which is set only by
the loader, and no `EnvTheme` is ever loaded. Every floor fell through to the generic
arcade wall. The climb looked like one room re-tinted ten times because it was.

**3. Two ledges were authored above the jump ceiling.** Ground 780, jump clears 105.3;
`RUINS[0]` surfaced at 661 (a 119 px rise). Brawler was the only class that could
touch it, and only by spending its air jump — which is why it read as a Brawler
problem. Re-authored as a climb inside `FloorGen.STEP_MAX`.

## ▶ ALSO SHIPPED

| what | verified |
|---|---|
| Ten biomes get their own **weather** (ash/leaves/snow/embers/bubbles/rain/glint/starfall) | rendered + looked at |
| Weather costs **+1 draw call, 2.22% screen fill** worst case; budget pinned at 6% | measured, negative-controlled |
| Three floors open onto a **moving sunset / living eclipse** (`SkyVista`) | rendered + looked at |
| Three of nine **ults ended on the wrong screen or none** | `slice_test_ult_punctuation`, negative-controlled |
| Vertical clips render **9:16 natively** and the camera **follows the action** | rendered + looked at |
| **Falling out of the world** — hub soft-lock, tower enemies, i-frame-proof kill | tests |
| Dead bodies stopped **stretching** (DoT knockback on a corpse) | reasoned from the maker's own diagnosis |
| **Stacked ult titles** — new replaces old | tests |
| Arcanist's **clone no longer spawns in a wall** | tests |
| Bigger hitboxes: boulder 84→118, void 185→250, crawler 26→38, pillar 66→88 | ⚠ feel change, unmeasured |
| **Blink starts on cooldown** so nobody opens by teleporting into your face | tests |
| **VO word bank** — 11 clips cover all 72 matchups | maker listened |

## ▶ STILL OPEN — MAKER FEEDBACK NOT YET BUILT

1. **Bots barely use dash, and never to recover.** Maker: *"if they are being sent up
   in the air they can dash to get back"*. `BotDodge` only reaches dash as a threat
   response; there is no air-recovery rung at all.
2. **Necromancer summons should go and attack.** `Thrall` / `RaiseThrall`.
3. **Knockback missing entirely on 13 damaging spells** — audited and listed:
   `ZoneSpell` (incl. the 34-damage shatter payoff), `ShadowRoot`, `DrainTether`,
   `RuneOrbs`, `GraveTide`, `VoidCollapse`, `Chronostasis`, `Equinox`, `Severance`,
   `Zanshin`, `GravityFlip`, plus partial paths in `LightningRush` (chain arc),
   `Shatter` (splash), `RiftDagger` (impale), `HorizonArc` (destructibles).
   ⚠ `SpellDef` has NO knockback field and deliberately does not get one
   (`SpellTier.gd:162`) — the shove is derived via `push_for_spectacle`. Use that.
4. **Bots cannot perceive 36 of the spectacles.** Threats enter through ONE door,
   `BotController.perceive_threats`, which scans only group `telegraph` (armed) and
   groups `enemy_projectile` / `player_spell`. Beams, meteors, zones, walls, chains,
   tethers and every CATACLYSM are invisible — a bot literally stands in them.
   `EnergyNova`'s own header argues it must be dodgeable; it never joins the group.
   Also: `BotBrain._safest` drops LANE telegraphs when picking a dodge destination
   (they publish `radius: 0.0` and no top-level `shape`), so a bot can dodge INTO one.

## ⚠ TWO REAL BUGS FOUND AND DELIBERATELY NOT FIXED

* **`FloorGen`'s reachability budget is calibrated to DEAD CONSTANTS.** It derives its
  gaps from "JUMP_VELOCITY 580 against GRAVITY 1500", but `TuningConfig` overrides both
  at runtime (740 / 2600). `GAP_UP_MAX` is 110 against an actual 83.6 px reachable far
  edge; `GAP_FLAT_MAX` is 170 against 115.4 px of travel. So `can_step` certifies
  surfaces as connected that nobody can reach, and `_prune_stranded` trusts the same
  wrong numbers. **This affects human players too.** Separate blast radius.
* **`VersusArena` has no y-threshold catch at all** — only two side pits, leaving
  uncovered columns at x 0..40 and 1965..2020 and its entire vertical extent.

## ⚠ PROCESS LESSONS FROM THIS SESSION

* **Never `git checkout --` a file holding uncommitted work.** Done once to undo a
  deliberate test-break; it reverted to HEAD and wiped the whole uncommitted weather
  system. A backup taken a minute earlier saved it. Commit first, then negative-control.
* **Instruments lied three times and every one was caught by verifying.** The ult
  suite's first run reported three failures, all three of which were the suite (a
  match inside a comment, a node-lookup spelling, an unfollowed delegate). The perf
  probe's first two metrics were warm-up staircases. The sky capture's geometry never
  reconciled — that one is still unexplained and the game was used as ground truth.
* **`Sky` cannot be an enum name** — it shadows a native Godot class, and the failure
  cascades into the whole game refusing to boot with nothing pointing at the line.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 6          # 171 suites, ~110s
python python-tools/run_capture.py weather_capture     # the ten biomes
./godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
  --script tools/sky_capture.gd                        # the sunset + eclipse
```
