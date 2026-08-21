# RESUME HERE — 2026-08-21 (evening)

**ASHPIRE.** Branch `bot-fight-quality`, **176/176 green**. The maker watches
**F5 → Lobby → Watch Bots** and reviews the final clips before posting.

⚠ The canonical, always-current queue is the `project_v2_resume_queue` memory. This file
is the same list with more room to explain it.

## ▶ OPEN

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

3. **"Ashpire" vs "Ashspire" — a maker's call, and smaller than it looked.** They are not
   a typo of each other: **Ashpire** is the GAME (`config/name`, `GameLogo.TITLE`,
   "Return to Ashpire"); **Ashspire** is the TOWER and its Guardian ("The Ashspire",
   `TowerDef.display_name`, ~38 files). Two deliberate proper nouns one letter apart.
   The only question is whether that is confusable enough to rename the tower. Never
   silently rewritten.

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
