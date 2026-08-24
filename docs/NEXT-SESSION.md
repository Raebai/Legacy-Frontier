# RESUME HERE — 2026-08-24

**STICKSPIRE.** Branch `bot-fight-quality`, **176/176 green**. The maker watches
**F5 → Lobby → Watch Bots** and reviews the final clips before posting.

⚠ The canonical, always-current queue is the `project_v2_resume_queue` memory. This file
is the same list with more room to explain it.

## ▶ OPEN — 2026-08-24

**THE BED WAS MISSING FROM EIGHT OF THE NINE POSTS, and the clock is the whole story.**
The pool landed at 14:29 on 08-22; the newest clip before it was cut at **14:28**. One
minute. So `stormcaller_vs_swordsaint` had a bed and the other eight did not, and nothing
in the pipeline says so out loud — the bed is chosen and applied at CUT time, and a clip
cut yesterday is simply a clip from before the feature. **Re-cut the four current-gen
clips; all four now carry a bed** (three different tracks — the sha1-on-stem shuffle
spreads them, as designed).

⚠ **A `--no-shoot` re-cut is the fix for a MIX change and cannot be the fix for a PICTURE
change.** That line divides the whole backlog: the bed, the VO, the titles and the
loudness all re-cut in ~2 minutes from the raw; the opening shot and the ults are baked
in at SHOOT time and cost ~25 min a take.

**`.nomusic.mp4` DID NOT EXIST — it was documented, never written.** The module
docstring listed it as a per-matchup output, `--no-music`'s help called it "the .nomusic
companion", and content-pipeline.md §4 named it as the file to upload when you want a
trending sound. No code path ever produced one. Built now (`3a5ff4a`), as a second encode
rather than a strip: the bed is sidechained into the mix and mastered with it, so once
there is a file there is no music track left to remove. Measured on
stormcaller_vs_cryomancer — post RMS **-15.3 dB**, (post - companion) RMS **-27.5 dB**,
i.e. 12.2 dB down, which is the bed and nothing else.

**RUNNING NOW: the five stale clips are being re-shot** (`--takes 2`):
`juggernaut_vs_stormcaller`, `juggernaut_vs_swordsaint`, `warlock_vs_cleric`,
`cryomancer_vs_brawler`, `shadowblade_vs_juggernaut`. Up to ~4 h.
⚠ **A shoot rewrites `window/size/window_*_override` in project.godot for its duration**
and restores it in a `finally` — so F5 during a shoot gets the clip's window size, and a
hard kill leaves it patched. `python python-tools/check_window_override.py` is the check.

## ▶ OPEN

⚠ *Items 0 and 1 below are superseded by the block above.*

0. **PAUSED HERE (maker said "pause", 2026-08-21 ~19:55).** Repo is clean, both commits
   landed, `project.godot` restored to 1366x768 and verified. Nothing is mid-flight.
   **`stormcaller_vs_swordsaint` is RE-SHOT and verified** — stare-down VS card holds
   2.8s for the names, take 1 rejected as a demolition, take 2 PASS 60.4 with **3 ults**.
   The other three re-shoots (`arcanist_vs_shadowblade`, `swordsaint_vs_arcanist`,
   `stormcaller_vs_cryomancer`) are NOT started — that is the resume point.

   ⚠ Waiting on a shoot by grepping `tasklist` for "Godot" **never exits** — the maker's
   own editor is open and matches. The shoot had actually finished; the watcher had not.
   Watch the OUTPUT FILE's mtime, or the shoot's own pid, not the process name.

1. **THE FOUR OLD CLIPS ARE RE-CUT — one is also RE-SHOT, three still want a re-shoot.** All nine mp4s in
   `content/posts/` now carry a clean four-word announcer line, no white title card, and
   1:1 frames (0 duplicate frames measured across all nine). What a re-cut CANNOT reach
   is baked into the render: the four old shoots have **no in-game VS card at all** —
   measured, the fight is already live at t=1.0s — so the announcer names fighters over
   a moving fight. They also predate the one-announcer fix and the ult fix below.
   A re-shoot (~25 min/take) is the only way to get the stare-down, the single spell
   name, and the ults.

   ⚠ The old handoff said only four clips were stale. It was wrong twice: three OTHERS
   (`warlock_vs_cleric`, `cryomancer_vs_brawler`, `shadowblade_vs_juggernaut`) carried
   the bug too, and `juggernaut_vs_swordsaint` — listed as post-fix — said FIVE words and
   had no `_names` sibling, so it predated the final VO fix. All nine are re-cut now and
   all eighteen VO lines are verified word-by-word.

2. **THE DESTRUCTIBLE MAP — still paused, and the pause is still correct.** Spec
   `docs/superpowers/specs/2026-08-19-destructible-map-design.md`. Slice 0 measured
   (binding constraint: Juggernaut 97.1 px = 6 chunks). Slices 1-5 unbuilt. It adds
   events to a fight the maker called *"too much going on"*, and it rewrites terrain
   collision on the stage the clips are shot on. **It is gated on a maker playtest**,
   not on engineering — resume once the calm-down pass reads right in play.

3. **THE GAME IS NAMED — done, not open.** 2026-08-22: **STICKSPIRE**, tower **The Ashen
   Tower**, guardian **The Ashen Guardian**. The old Ashpire/Ashspire collision is gone
   because neither word survives. See "THE RENAME" below.

## ▶ SOCIAL ACCOUNTS — the setup, and the constraint that decides it

Five accounts: TT `@stick.spire` + `@stickspire.arena`, IG the same two, YT `@stickspire`.
Different clips per account (maker: volume, not mirroring) — so no duplicate-post risk.

**Tool: Upload-Post**, and it is not a taste call — see `docs/content-pipeline.md`.
Five accounts should group into TWO profiles (one account per platform per profile),
which is the free tier's limit; confirm at signup before paying the $16/mo.

⚠ **ACCOUNT TYPE DECIDES WHICH MUSIC YOU CAN USE. Get this right at registration.**

| Account | Register as | Why |
|---|---|---|
| TikTok x2 | **Personal/Creator** | a TikTok BUSINESS account is locked to the Commercial Music Library — no trending/chart sounds, and there is NO toggle. Only way back is switching to Personal. |
| IG flagship | **Creator** | full trending audio, but **cannot** publish via API |
| IG arena | **Business** | publishes via API, but restricted to the Meta Sound Collection |
| YouTube | — | ⚠ our clips are LANDSCAPE; a landscape upload is a normal video, NOT a Short. Shorts need vertical/square. Use `--portrait`. |

⚠ **AUDIO CANNOT BE FULLY AUTOMATED AND TRENDING AT THE SAME TIME.** Trending sounds are
attached IN-APP only. Baking a downloaded master into the file does NOT attach it to the
sound page — TikTok fingerprints on upload and the outcomes are mute / takedown / region
block / strike, while the video is filed as a new "original sound" nobody browses. The
sound page is a REFERENCE stamped by the editor; a baked-in copy has no id.

What IS fully automatable: the game's own bed (already produced per clip), and TikTok's
**Commercial Music Library by track id at publish** (unlocks once an account is
connected). Plan: arena accounts run hands-off; hand-attach a trending sound only on the
flagship clips worth pushing (~30 s each).

## ▶ THE RENAME — Ashpire -> STICKSPIRE (2026-08-22)

Maker approved: *"Stickspire is amazing lets do it and yeah fully rename it all"*.

```
game     Ashpire        -> Stickspire      (config/name, GameLogo.TITLE, death card)
tower    The Ashspire   -> The Ashen Tower (TowerDef, GameState, ~72 refs)
boss     Ashspire Guardian -> Ashen Guardian
theme    ashpire_theme.tres -> stickspire_theme.tres
user://  .../Ashpire    -> .../Stickspire  (MOVED, 2717 entries, 3.6 GB)
```

⚠ **THE `user://` DIRECTORY WAS MOVED, NOT COPIED — deliberately.** The previous rename
(Legacy Frontier -> Ashpire) COPIED it, and because both directories existed and both
held a folder of the same name, `make_clip` encoded frames from before the rename and
reported success. A move leaves no stale twin to read from by accident.

✅ **And `godot_paths.py` did its job.** It derives the name from project.godot, so every
Python tool followed with no code change; the only edit needed was `_FALLBACK_NAME`,
which is never read while project.godot is readable. The module was written after the
last rename went wrong — this rename is the evidence it works.

The logo re-rendered: `STICK` in ember, `SPIRE` in chalk, split on the compound seam.
`_draw_wordmark` now SIZES TO FIT rather than to a constant tuned for a 7-letter word.

176/176 green after the rename.

## ▶ THE FOUR CLIPS ARE SHOT AND DELIVERED (2026-08-22)

All four carry BOTH fixes (ult scoring + the opening shot). Scores as shot:

```
arcanist_vs_shadowblade    PASS 78.2   3 ults   winner_hp  6%
swordsaint_vs_arcanist     PASS 75.0   3 ults   winner_hp 25%   (needed --seconds 34)
stormcaller_vs_cryomancer  PASS 70.4   2 ults   winner_hp 15%
stormcaller_vs_swordsaint       54.7   2 ults   winner_hp 72%   ⚠ below the bar, kept
```

⚠ **`--seconds 24` IS TOO TIGHT NOW THAT ULTS LAND.** `swordsaint_vs_arcanist` ran out
the clock and ended mid-fight — the pipeline's own worst outcome — and re-shooting the
identical matchup at `--seconds 34` scored 75.0 and resolved in 16.8 s. Fights are
longer and swingier now that the showpiece is being cast. **Consider raising the
`--seconds` default from 24.** `stormcaller_vs_swordsaint` failing twice may be the same
cause rather than a bad matchup.

⚠ **THE OTHER FIVE POSTS STILL HAVE THE OLD OPENING.** `juggernaut_vs_stormcaller`,
`juggernaut_vs_swordsaint`, `warlock_vs_cleric`, `cryomancer_vs_brawler`,
`shadowblade_vs_juggernaut` were only RE-CUT — audio and titles only. They still open
off-stage and still have no ults, because both fixes are baked in at SHOOT time. Each
needs a ~25 min re-shoot. Deliberately not done: the maker judges these four first.

## ▶ FIXED 2026-08-22 — THE OPENING SHOT

Maker, on the finished clips: *"why does the video always start in the random top left
corner or something the camera"*. Real, and it affected EVERY clip ever shot.

`ClipDirector._frame` eases both channels toward their solve — position at `POS_LERP` 7,
zoom at `ZOOM_LERP` 2.6. Right on every frame except the first, because on the first
there is nothing behind them to ease FROM: the camera is a bare `Camera2D` sitting where
it was added, and `_zoom_smoothed` is seeded in `bind()` from that camera's default 1.0
while a duel frames between 0.49 and 1.45. So every clip opened off-stage at the wrong
zoom and spent ~0.5 s travelling to the fight — under the VS card, i.e. across the
thumbnail and the whole hook. Measured on the drawn channel, frame 0:

```
without   638.6 px off-centre on a 640 px frame   offscreen 2/2
with       44.7 px                                offscreen 0/2
```

A faster lerp could not have fixed it — the fault is the STARTING VALUE, not the rate.
The first framed frame now establishes the shot outright.

⚠ **`probe_directed_framing` could never have caught this** — `SETTLE = 150` discards the
first 150 frames before measuring. New `tools/probe_opening_frame.gd` looks at the
opening instead. ⚠ **And it under-reports the DURATION**: headless runs uncapped, so the
first delta saturates the lerp to a full snap and an unfixed build reads settled by frame
1. Under `--write-movie` the travel really takes ~0.5 s. Frame 0 is the honest signal;
the rendered mp4 stays the authority.

## ▶ FIXED 2026-08-21 (evening)

**THE BOTS CAST THEIR SHOWPIECE AGAIN — and the standing lead was wrong.**
The queue said the ult drought needed a *"bank your mana"* rung in `BotBrain`. Counted
instead of guessed, over real bodies on the shipped showcase config:

```
botmatch_sim --drops=1   482 looks at the ult slot
                         cooldown 85   absent 0   mana 0   range 21   channel 0
                         scored above zero: 9  (2%)
```

**Mana refused nothing.** The channel gate — the previous suspect — refused nothing
either, 0 of 419. Of the 374 looks that cleared every hard gate, 9 scored.

`SpellGrant.TIER3_SLOT` **is** `SpellTier.ULT_SLOT`, so a drop DISPLACES the ult, and
`BotBrain._facts_of` labels it role `"drop"`. `score_slots` matches on the five authored
role names; `"drop"` matched none, `role` kept its initial `0.0`, and the slot scored
`0.0 * range_fit * safety` — exactly zero, however affordable. The 9 that fired were
carried by a combo bonus alone. `_facts_of` even documents scoring it "on its tier and
its range"; no such scoring was ever written.

The control isolates it: `--drops=0` puts the class's REAL ult in that same slot and
scores 54 of the 78 looks that clear cooldown — **69% against 2%**, one difference, the
role string. After the fix:

```
8/8 bouts land 2-4 ults     spells 6 -> 8-9     4 gate PASS, was 2
ult slot: cooldown 81%  scored 14%    (--drops=0 control: 82% / 13%)
```

The slot is now busy enough to be ON COOLDOWN, which is the signature that it is being
pressed. **Unplaytested** — this is a sim result, not a feel result.

**The counters stay** (`BotBrain.ult_considered` and friends, printed by `botmatch_sim`).
Integer increments on a path that already branches, and this is the second confident
story about this slot that turned out to be wrong.

## ⚠ TRAPS — the expensive ones

* **`BotMatch` ALWAYS sets `showcase_directed = true`**, so the bot fight and every clip
  are framed by `ClipDirector`, and `VersusArena._update_showcase_camera` returns early.
  A probe instantiating `VersusArena` directly measures a path nobody watches.
* **`Camera2D.global_position` is the TARGET**, not the picture
  (`get_screen_center_position()`).
* **Headless has no window, so it has no aspect** — `get_visible_rect()` falls back to a
  SQUARE 640x640. Set `root.size = Vector2i(1366, 768)` and wait a frame.
* **`Time.get_ticks_msec()` is ~20x wrong inside `--write-movie`.** Count frames.
* **Judder is invisible to a timestamp check.** The file is perfect CFR; the frames are
  evenly spaced while the moments they sample are not. Measure frame-to-frame MOTION —
  decode a strip of frames and diff them; duplicates mean decimation.
* **`spell_cast` emits at RELEASE, the gesture plays during the WINDUP.**
* **A clip shoot REWRITES project.godot.** `git add -A` during one commits 1920x1080 as
  the real window size — done three times now. Run
  `python python-tools/check_window_override.py` before any push.
* **A guard that exempts what it cannot explain is not a guard.** Prove a new test FAILS
  without its fix before trusting it — the ult test was reverted-and-run to confirm it
  reads 0.950 as a kit ult and 0.000 as a drop.
* **A shoot costs ~25 minutes per take.**
* **`--no-shoot` re-cuts from the RAW shoot in `user://clips/`, not from `_cut/`.** If the
  raw is gone it silently re-shoots instead. Backups of the four originals are kept as
  `*.raw.bak.mp4` beside them.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3          # 176 suites, ~230s
python python-tools/vo_bank.py --check                 # every VO part says one phrase
python python-tools/check_window_override.py           # 1366x768 committed
godot --headless --path godot-project --script tools/botmatch_sim.gd -- \
    --drops=1 --hp=500 --round=22 --pairs=8            # ult slot telemetry
godot --headless --path godot-project --script tools/probe_cast_visuals.gd
```
