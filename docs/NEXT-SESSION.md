# RESUME HERE

## STATE — 2026-09-07 (evening). Branch `bot-fight-quality`. THE QUEUE WAS PUBLISHING ONE FIGHT.

⚠ **THIS FILE GOES STALE AND `git log` DOES NOT.** It has been seven commits behind
before, claiming a clear queue while five suites were red. **Check its date against
`git log --oneline` and trust the log.**

**NOTHING IN THE GAME HAS BEEN PLAYTESTED.** That judgement is unchanged and it is the
whole point. The posting work below is different — it was measured against the live
vendor, not a suite.

---

## ▶ THE THING THAT MATTERED MOST TODAY, AND IT WAS NOT IN THE GAME

**The daily queue was 88 scheduled posts holding 5 distinct clips.**
`arcanist_vs_juggernaut.portrait` was queued **57 times** and `arcanist_vs_brawler.portrait`
**28**, `draft: false`, one to four times a day, on Instagram/TikTok/YouTube, out to
4 October. One duplicate of each had already published.

One line. `cmd_topup` reassigned `clip = send_clip` before writing the ledger row, so a
send using a `clip_suffix` recorded the stem of the CUT (`x_vs_y.portrait`) as the thing
spent. `pick()` asks whether the POOL stem (`x_vs_y`) is spoken for. The two strings
never met, nothing was ever retired, and `pick()` returned the first pool entry on every
day of the queue forever. **Every account carries a `clip_suffix`, so it fired on 100% of
sends** — it arrived with the portrait cuts.

⚠ **BOTH INSTRUMENTS THAT COULD HAVE CAUGHT IT WERE DOWNSTREAM OF THE BROKEN FUNCTION.**
`--status` prints the ROW, so the repetition was on screen every day and read as a list
of scheduled posts. `runway()` shares `spoken_for()`, so it reported "5 clips
unspoken-for, 2.5 days" against 88 queued posts. The number that should have screamed was
computed by the thing that was wrong. After the fix: 3 unspoken-for, 1.5 days, and a
SHOOT MORE warning that had never once fired.

**Now: the vendor holds 8 posts and they are 8 different fights**, four of them
shadowblade fights the nightly shoot rendered AFTER the rendering fixes — so the content
going out is finally from the current build. That was the maker's open ask
(*"ensure the content coming out daily is updated with these updates that we send out"*).

## ⚠ AND I BROKE IT FURTHER BEFORE FIXING IT — READ THIS ONE

The first bulk cancel hit the endpoint's rate limit. The next listing came back HTTP 429,
`list_scheduled` returned `[]` for the failure exactly as it does for an empty schedule,
and the caller read that as "the vendor no longer holds these" — **dropping 18 rows from
the ledger that were still queued to publish.** Nothing was cancelled and nothing here
knew they were still coming. Recovered by asking the vendor directly.

The previous commit's own comment had named that exact failure — *"a row forgotten here
while the vendor still holds it is the worst of both"* — and guarded the CANCEL call while
trusting the LIST call that decides which cancels to attempt. **The guard was one call
upstream of where it was needed.**

`list_scheduled` now returns `None` for "could not tell". Every caller reads it. The one
that mattered most was never hit: `vendor_holdings` feeds `--topup`, whose whole
idempotence claim is "fill only the gaps" — a failed listing read as "no days covered"
queues a second post on top of every day already held.

**New verbs:** `--cancel-dupes` (keeps the first showing of each fight, judged on the
VENDOR's rows because the ledger had diverged by 18) and `--assert-no-dupes`, which is
now **step 7 of the nightly wrapper** and exits 1 if the queue repeats itself.
`check_post_rotation.py` has 9 checks and 2 sabotages that put the old behaviour back and
require the guard to go red.

---

## ▶ THE THEME HAS A FONT AT LAST — AND THE PREMISE WAS WRONG

`assets/ui/fonts/`: **DejaVu Sans** is the theme's `default_font` (the only audition
candidate answering `has_char` for all 24 wanted glyphs — every other scored 6, Noto Sans
Symbols 2 got 17 and still missed the block and all four arrows). **Bangers** rides on top
for Buttons via `display_font.tres`, a `FontVariation` with DejaVu in `fallbacks`.
`slice_test_font_coverage` went green on its own, exactly as its own header predicted.

⚠ **BUT THE GLYPHS WERE NEVER BLANK ON THIS MACHINE.** Measured before any font was
added, headless AND GUI: `has_char` false for 13 of 14 — **and a rendered specimen drew
every one of them**, with ⚠ coming out in COLOUR, which is a system emoji font.
`get_string_size` returned non-zero width for all 14. The text server falls back to OS
fonts; **`has_char` on a single Font is not the question the renderer asks.** The maker's
report of blank buttons is real but its cause is unconfirmed — most likely the APK.
`allow_system_fallback=false` on both fonts makes it moot either way, which is why
shipping the font was still right.

Two traps paid for while doing it:

* **`has_char` on an imported FontFile with `allow_system_fallback=true` answers about the
  OS, not the font.** It claimed CJK and emoji alike. Turn it off or the measurement means
  nothing.
* **The suite's canary was ONE codepoint** (U+1F600) asserted absent, to prove `has_char`
  could still say no. DejaVu claims U+1F600 while correctly denying CJK U+4E2D, both with
  fallback off — so the suite refused to run at all. It is now a SET of five, of which at
  least one must come back absent.

**Look at it:** `Godot_v4.6.2-stable_win64.exe --path godot-project --script
tools/title_capture.gd` → `user://title_screen.png` + `title_coop.png`. The front door had
no capture tool at all until today, and it is the screen every player sees.

⚠ **`title_capture` first shot a half-swept sigil on an empty screen** because it waited
150 `process_frame`s for a 3.4 s animation. **A frame count is not a duration.** It waits
on the clock now.

---

## ▶ THE THINGS THE MAKER MUST DECIDE

1. **Restoring the substituted glyphs.** Decision taken today was *ship the font, then
   re-test and unwind* — verifying by capture, not by `has_char`. 237 files are still
   carrying substitutions that the font no longer requires. **Never add to `WAIVED`.**
2. **The `STICKSPIRE` wordmark is deliberately NOT in the display face.** It is
   `GameLogo`, a custom-drawn brand asset also used for the app icon, the social avatar
   and every `tools/render_logo*` stamp. Changing its font changes the brand everywhere.
3. **Bangers reads small inside full-width buttons.** Visible in `title_coop.png`. It is a
   font-size tune, not a font problem, and it wants a playtest not a measurement.
4. **The Sensei's numbers.** Unchanged: longest tells on the roster (0.85–0.95 s) paired
   with the shortest cooldowns (1.9 → 1.0). That pairing IS the fight; read either alone
   and it looks mistuned. Never played.
5. **Roster balance is unsolved** — Stormcaller went 16-0 in bot fights.

## ▶ WHAT IS LEFT

1. **PLAYTEST.** Still the only real item.
2. The glyph unwind (see above).
3. **`probe_reachability` reports 252 of 939 public entry points with no shipping
   caller.** A report, not a gate; it over-reports for autoloads.
4. **Two carve limitations left alone on purpose** — both fixes are FEEL changes.
   `RockPillar` stays on `carve_disc`/`carve_area`; `IceWall`'s piercing seat has a 6 px
   non-piercing probe as a local workaround.
5. ~~`_host()` calls `visit_hub()`, so Start Run is unreachable~~ — **FALSE POSITIVE,
   checked 2026-09-07.** `RealmScreen` carries the real Start Run and its own comment says
   the title panel "is no longer the door"; `Lobby` wires the fallback through
   `_net.server_started` → `_refresh`, which reveals the hidden row. Nothing to fix.
   Left here struck through so it is not re-investigated a third time.

---

## ⚠ TRAPS THIS BRANCH HAS PAID FOR — do not re-learn these

* **A FAILED READ IS NOT AN EMPTY READ.** See above. Any function reading remote state
  must be able to say *could not tell*, and the guard belongs on the read that CHOOSES
  the writes, not only on the writes.
* **A HANDOFF FILE GOES STALE AND A GIT LOG DOES NOT.**
* **A FRAME COUNT IS NOT A DURATION.** 150 `process_frame`s elapsed well under a second
  against a 3.4 s animation, and the capture saved successfully showing nothing.
* **AN INSTRUMENT DOWNSTREAM OF THE BUG WILL REPORT HEALTHY.** `runway()` said 2.5 days
  against 88 queued posts because it shared the broken function. When choosing where to
  put a check, put it downstream of NOTHING — `--assert-no-dupes` reads the vendor.
* **A SINGLE EXOTIC CODEPOINT IS NOT A CANARY.** DejaVu claims emoji and denies CJK.
* **FIVE SUITES IS A SAMPLE, NOT A SWEEP — AND THE GLYPH RESTORE PROVED IT AGAIN.**
  Restoring `▸` on the front door was checked against `font_coverage`, `shell`, `town`,
  `settings` and `outfitter`, all green, and committed. The full sweep then found
  `slice_test_realm` red: it held its OWN copy of the two primary labels, marker
  included, so the two rows read as NEW rows to a suite that has no opinion about
  markers. **This is the hardcoded-glyph trap already in this list, and it was walked
  into anyway.** Fixed the way the rule says: `Lobby.PLAY_LABEL` /
  `Lobby.MULTIPLAYER_LABEL` are the single source, and the suite reflects them out with
  `get_script_constant_map()` — never a bare `Lobby.` reference, which would make it a
  compile-time dependency that a `--script` run resolves before autoloads exist. The
  reflection fails OPEN (a renamed const reads as `""`), so there is an explicit
  assertion that it read something; sabotage-verified by renaming the const.
* **THE LOUD BUG GETS FIXED AND THE QUIET ONE DOES NOT.**
* **A SUITE THAT BUILDS ITS OWN WORLD CAN ONLY TEST THAT WORLD.** `slice_test_hero_plate`
  passed nine assertions about a HUD element that had never appeared in the game.
* **A HIGHLIGHT TWENTY TIMES THE VALUE OF THE THING IT IS ON IS THE ONLY MARK.**
* **A GATE BUILT FROM AN ALLOWLIST OF SINKS MISSES THE FRONT DOOR.**
* **SIX CONCURRENT OPUS AGENTS EXHAUSTED THE SESSION LIMIT.** Run three at a time, and on
  a resume `git status` and prove the tree PARSES before believing any suite result.
* **THE NIGHTLY TASK WRITES TO THIS CHECKOUT.** On 2026-09-07 it fired mid-session: a
  shoot had `project.godot` patched to 1920x1080 (restored in a `finally`) and
  `content/analytics/posts.json` rewritten. Neither is yours — **diff before you stage.**
* **AND SO DOES SOMETHING THAT COMMITS.** Later the same evening, three commits appeared
  on this branch that this session did not make — `2a7b9f8`, `afb700e`, `ce44ccf`,
  timestamped 21:48–21:53, each containing THIS session's uncommitted edits under its own
  terse message. The `git commit` that followed found nothing to commit. Nothing was lost
  and the content is correct (verified line by line, and the 219/219 sweep was run against
  it), but the reasoning those messages were going to carry was — and `2a7b9f8` is
  labelled `docs:` while containing a `Lobby.gd` code change. The identity is the repo's
  own (`Raebai`), so **`git log` cannot tell you whether a commit is yours.** History was
  NOT rewritten to fix it, deliberately: another live writer may be building on those
  commits. **Commit early and in small pieces here, and read `git log` before assuming
  your working tree is still yours.** See `project_collab_concurrent_sessions`.
* **A FULL SWEEP IS UNREADABLE WHILE AGENTS ARE WRITING.** Verify per-suite during, sweep
  once at the end.
* **NAMING A CLASS IN A TEST MAKES IT A COMPILE-TIME DEPENDENCY.** Read constants via
  `get_script_constant_map()`.
* **`--script` DOES register this project's autoloads** (all twelve).
* Still true: **the Godot editor strips `project.godot` keys while it is open**, **do NOT
  edit code through shell heredocs** (write a patch FILE and assert single-occurrence
  anchors — both the `daily_ops.cmd` and the theme edits today went through one), and **a
  precondition ORed against the thing it precedes is not a precondition**.

---

## ▶ THERE IS AN OBSIDIAN SECOND BRAIN

Vault: `C:\Users\Raaed\Documents\Second Brain` (`OBSIDIAN_VAULT_PATH` in
`~/.claude/settings.json`). It holds the DURABLE layer only — what the game is, the
rulings, the lessons that cost real time. **It deliberately does not hold live state:
this file and `git log` remain authoritative.** Read `<vault>/index.md` before searching.
Commands: `/obsidian-save`, `/obsidian-log`, `/obsidian-find`, `/obsidian-world`,
`/obsidian-challenge` and ~42 more.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3        # 219 suites, ~360s
python python-tools/check_post_rotation.py           # the queue-rotation guard + sabotage
python python-tools/check_daily_ops.py               # 7 nightly steps, each failed alone
python python-tools/daily_post.py --assert-no-dupes  # asks the VENDOR, not the ledger
python python-tools/check_window_override.py         # 1366x768 committed
godot --headless --path godot-project --script tools/slice_test_mobile_config.gd
godot --headless --path godot-project --script tools/slice_test_font_coverage.gd
Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/title_capture.gd
python python-tools/run_capture.py tavern            # the lobby, without the HUD
python python-tools/run_capture.py boss_roster       # every artist, side by side
```
