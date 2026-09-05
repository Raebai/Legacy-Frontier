# RESUME HERE

## THE POLISH PASS — 2026-09-04/05

Branch `bot-fight-quality`. **18+ commits ahead of `origin` and NOT PUSHED** — that is the
first decision for whoever reads this.

The maker asked for a full polish pass (*"the game is really ugly and unpolished... dont
just add random effects optimise the ones that current exist"*), then added: make it feel
precise and professional, optimise the stick-figure hitboxes, make the map destroyable,
have spells interact, verify local multiplayer, and get an Android APK they can play.
Fifteen agents ran against a partitioned file-ownership map. Everything below is measured
and revert-tested, and **none of it is playtested**.

### ▶ PLAY IT

* **Android:** `exports/android/Stickspire.apk` — signed, verified, `com.stickspire.game`.
  ⚠ **REBUILD BEFORE HANDING IT OVER**; the current file predates most of these commits.
  `"godot-engine/Godot_v4.6.2-stable_win64_console.exe" --headless --path godot-project --export-debug "Android" "../exports/android/Stickspire.apk"`
* **PC:** F5 → Lobby → Watch Bots. `boot_check: OK`.

### ▶ THE ONE THAT COST THE MOST TO FIND

**`#` IS NOT A COMMENT IN `project.godot`.** Godot parses it with VariantParser, whose only
comment character is `;`. A `#` line is a PARSE ERROR whose recovery **swallows the
assignment on the next line**.

Commit `84caf09` added five careful `#` lines explaining why Android needs ETC2, then the
setting they explained. The comment switched off the line it documented. `grep` found it,
every human read it as set, and `ProjectSettings` returned `false` — so every Android
export kept failing, **with a blank error body**, because the Android exporter's ETC2 check
sets `valid = false` without writing a reason into the string headless prints. Four signals
all read "fixed" while the build stayed broken. `tools/slice_test_project_config.gd` now
bans `#`-led lines and asserts platform gates on their PARSED VALUE, never on presence.

### ▶ WHAT LANDED

* **The hero had no hurtbox** — an 18×18 box under a 33 px figure, so head/neck/chest (41%
  of a stick figure) were unhittable. The enemy's was 5.6 px short at the top; the
  guardian's was never synced, because `Boss._physics_process` does not chain `super`.
* **Melee auto-target deleted** under the standing **"NO auto-aim"** ruling.
* **Player two could not move** — `PadController` never implemented `tick`, and a missing
  method ABORTS the enclosing function, so P2's whole `_physics_process` returned above
  movement at 60 errors/sec. Three green suite runs had said 2P worked.
* **The tower is endless and scored.** The probe found the pressure-cap axis was DEAD
  (`clampi(caps[i], 2, 8)` silently clipped every 9 and 10 — a clamped number is not a
  rejected one) and that the seam was a step DOWN (floor 10 already ends with all four
  classes, so the first five generated floors were easier than the summit).
  ⚠ **No online board is possible here** — no backend, scores are client-side plain text.
* **HUD unified:** 56 colour literals → 5, four rect collisions → 0, one zoom rule.
* **Hotbar:** the socket circle measured 32.00 px inside a 28.52 px slot and crossed into
  its neighbour; three labels clipped mid-word. Spell slots are discs now.
* **Telegraph:** draw calls 103 → 60, and five effects had NO low-quality gate at all.
* **Mobile:** DASH sat inside Android's home-swipe strip; JUMP was 115 mm from the right
  knuckle against a 62 mm sweep; nothing read `get_display_safe_area()`.
* **Hub:** two pads per the maker's ruling; the town overlay drew at layer 95 while
  `ClassSelect`/`Loadout` are autoloads at 90, so the Outfitter's Armory button opened the
  armoury BEHIND its own dimmer.
* **Both known-flaky suites fixed** — one awaited idle frames while asserting about
  physics-frame positions; the other randomised its matchup and was reporting the dice.

### ▶ OPEN — FOR THE MAKER, NOT FOR ENGINEERING

1. **The melee cone is 10–11× wider than the lane that draws it** (Brawler 110.7 vs
   10.4 px). A cone-sized lane is wider than the swing is long (already vetoed: *"i hate
   that circle thing for brawler"*); a lane-sized cone is a needle. Measured, not decided.
2. **The auto-aim contradiction, now sharp.** To hit someone behind you: keep the aim stick
   (today) = flick the thumb back ~10 mm and tap, sub-degree error; drag-to-aim (spec, not
   built) = press, drag, release; facing-follows-movement (spec as written) = **walk
   backward to turn around**, which on a ledge in a ring-out game is the swing killing you.
   **The spec's aiming scheme breaks melee unless drag-to-aim ships with it.**
3. **The 4→2 spell trim and parry cut are built behind consts but NOT defaulted on** — the
   measurement does not support them; the spec's case is *attention*, which needs eyes.

### ▶ HARD-WON FACTS — do not re-learn these

* **`#` in `project.godot` eats the next line.** Use `;`.
* **`preload` yields the SCRIPT OBJECT** — entry points must be `static func`. A plain
  `func` fails at RUNTIME, not parse time. Four agents hit a variant of this in one session.
* **A static method named `reload()` IS `Script.reload()`** — it recompiles and resets every
  static. A suite's redirect was undone two lines after it was made and the tests overwrote
  the maker's real `settings.cfg` while reporting all PASS.
* **`Sfx`/`GameState`/`Music` are AUTOLOADS, not `class_name`s** — naming one at compile
  scope from a file a `--script` suite loads in `_init` fails with "Identifier not found".
* **Count the frames your subject moves on** — gravity advances on `physics_frame`.
* **`aspect="expand"` keeps HEIGHT and adds WIDTH** — 20:9 is an 800×360 logical viewport,
  so right-anchored controls drift up to 200 px from left-anchored ones.
* **A suite printing NEITHER summary line is a FAILURE**, and one printing `all PASS`
  alongside a runtime SCRIPT ERROR is also failed by the harness.
* **`.gd` is pinned to LF but the tree has stale CRLF files** (`Arena.gd`, `Boss.gd`,
  `GameState.gd`, `TouchControls.gd`). Preserve each file's endings when patching.

### ▶ STILL FLAGGED, NOT FIXED

The Gopeak MCP runtime autoload is an unauthenticated `call_method` on port 7777. The
export excludes the addon so it does not ship, but `project.godot` still registers it, so
an exported build logs "failed to instantiate an autoload" on boot. The clean fix is a tiny
exported shim that loads the real addon only in the editor; deferred because changing an
autoload mid-session breaks every running agent.

---

# EARLIER HANDOFF (preserved — marketing/ops below is still live)

## THE NIGHTLY SHOOT WAS NEVER RUNNING (fixed 2026-09-01)

**One byte.** `daily_ops.cmd` held a literal `0x07` where `\a` belonged, so step 3
ran as `python-tools<BEL>uto_shoot.py`, python said `can't open file`, and the
wrapper — which only checked the last two steps' exit codes — reported OK. The
pool never refilled. Every "OUT OF CLIPS" and the 0-day runway trace back to it.

Fixed, and the two properties that let it hide are now both tested:

- every step's exit code is read and named in the alert
  (`pull= rank= shoot= cut= topup= verify=`)
- `python python-tools/check_daily_ops.py` runs the wrapper for real against a
  stubbed interpreter and fails it if a byte is out of place, a named script is
  missing, or **any single step's** failure does not reach the alert. Run it
  after editing `daily_ops.cmd`.

**A second bug fell out of checking today's posts: the analytics store was keyed
by `request_id` alone.** One Upload-Post request fans out to several platforms
and the history returns one row PER PLATFORM sharing that id, so the Instagram
row and the TikTok row of the same upload were the same record: the second
overwrote the first's `post_url`, and the deep read appended BOTH platforms'
metrics to one snapshot list at one timestamp. `reach_of` then read Instagram
impressions as TikTok views. The store is rekeyed by `(request, platform)`,
`insights.py` migrates an old one on first pull, and the corrected re-rank
already moved `swordsaint_vs_arcanist` from 2nd to 4th in the queue.

**Today's posts all went out — five of them, not the three the store claimed:**
YouTube 11:24, Instagram + TikTok for `brawler_vs_stormcaller` 19:09, Instagram
+ TikTok for `arcanist_vs_cryomancer` 20:26. TikTok is live and returning
retention curves.

---

## GROWTH STACK IS LIVE (2026-08-31)

Marketing/posting is no longer a plan, it is running. **Read
`docs/GROWTH-OPS.md` and the `project_v2_growth_stack` memory before touching
posting, the website or the optimiser.**

- **Queue is firing.** 14 posts held at Upload-Post, 1-5 Sep, across both
  Instagrams, both TikToks and YouTube Shorts. Plan is Basic (paid).
- **Site is live:** <https://stickspire.pages.dev>, Kit wishlist working end to
  end (form 9866820). Redeploy with
  `npx wrangler pages deploy site --project-name stickspire --branch main`.
- **Nightly task registered:** `StickSpire daily ops`, 11:47. It snapshots
  analytics, re-ranks and re-weights, SHOOTS new fights and deletes the
  failures, builds 9:16 cuts, tops the vendor queue to 30 days, and verifies
  yesterday. Nothing in it posts; the vendor posts.

### ▶ The one thing waiting on the maker

Runway is **0 days unspoken-for** with 4 days queued (2-5 Sep). The nightly
shoot now actually runs — it never did before today's fix — and attempts 3
matchups a night, so the pool heals on its own from here. To catch up faster,
run once while not using the machine:

    python python-tools/auto_shoot.py --live --max 8

(~3.5 hours. It refuses to start while Godot is open, measures every render and
deletes blanks and quality-gate failures rather than queueing them.)

Also outstanding: rename the YouTube channel from `@raaedali271` to
`@stickspire`, and delete the `claude-deploy-check@example.com` test subscriber
in Kit.

---

## Earlier handoff — 2026-08-24

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
in at SHOOT time and cost ~10 min a take.

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
   A re-shoot (~10 min/take) is the only way to get the stare-down, the single spell
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
needs a ~10 min re-shoot. Deliberately not done: the maker judges these four first.

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
* **The " M project.godot with an empty `git diff`" quirk is FIXED (2026-09-01), and the
  old note about it had the direction backwards.** `render_size_override` restored the
  file with `write_text`, which translates `\n` to CRLF on Windows, while
  `.gitattributes` pins the file to `eol=lf`. So the restore returned identical content
  with 230 line endings flipped and left the tree permanently dirty. It writes with
  `newline=""` now and the round trip is byte-exact; a simulated shoot leaves the tree
  clean. Six other tools had the same bug, including the one that writes
  `site/index.html`, which is deployed as-is.
* **A guard that exempts what it cannot explain is not a guard.** Prove a new test FAILS
  without its fix before trusting it — the ult test was reverted-and-run to confirm it
  reads 0.950 as a kit ult and 0.000 as a drop.
* **A shoot costs ~10 minutes per take, not ~25.** The five-clip re-shoot on
  2026-08-24 took 64 minutes, not the ~4 h this file predicted. The old number is
  what made re-shooting feel expensive enough to defer.
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
