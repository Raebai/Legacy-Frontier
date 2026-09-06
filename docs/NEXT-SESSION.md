# RESUME HERE

## STATE — 2026-09-07. Branch `bot-fight-quality`. THE ROSTER IS GREEN AGAIN.

⚠ **THE PREVIOUS VERSION OF THIS FILE WAS SEVEN COMMITS STALE** and said the queue was
clear at 215/215. It was written at `8be29c5`; the session then kept working until
`9c3c7de` and left **five red suites** behind. That is this file's failure mode: it is
written once and the work continues. **Always check its date against
`git log --oneline` and trust the log.**

Now: **219 suites, all green**, tree clean.

**NOTHING BELOW HAS BEEN PLAYTESTED.** Every claim is a measurement or a headless suite.
That judgement is unchanged and it is the whole point.

---

## ▶ PLAY IT FIRST — two things you can only judge by looking

**F5** → title → Single Player.

1. **THE TAVERN IS RE-CUT.** Walk the whole room. Its atmosphere was being drawn thirty
   times brighter than its structure; the beam, the bar, the barrels, the fireplace and
   the tower door have bodies now, and the haze is smoke instead of a field of
   hard-edged circles. The two station pads say what they are with a drawn breastplate
   and a drawn figure instead of a floating `†` and `§`.
2. **THE SENSEI IS A REAL BOSS.** Floor 20. He was a table row pointing at the Ashen
   Guardian's own scene, so he had the Guardian's name, voice, body and moveset. He has
   his own everything now. His numbers are a FIRST PASS — see the open question below.

Render the room without the HUD in the way:
`python python-tools/run_capture.py tavern`
Render every boss side by side: `python python-tools/run_capture.py boss_roster`

---

## ▶ WHAT LANDED THIS SESSION (3 commits; each carries its own red-run evidence)

* **`eb94f27` the Brawler is Earth and two guards still said Fire.** `da6ec14` acted on
  the maker's ruling and left the roster red. Both suites had been written to notice
  exactly this and both said so in their own failure text. The class-select assertion is
  FLIPPED rather than deleted, so the tripwire still points at the same fault from the
  other side — the melee class falling back off the affinity ladder goes red there now.
* **`ce508a4` the tavern was drawing its atmosphere thirty times brighter than its
  structure.** Measured off the screen, not reasoned about: the tie-beam reached drawn
  luma **1**, the bar counter's body **6** under a cap of **123**, the chimney breast a
  flat **3** across nine thousand pixels — while the haze reached **190**, all of it
  hard-rimmed `draw_circle`. Also fixed: an arch-head ternary whose two branches were
  the same value, which had been painting a dark disc across every window in the room;
  and the tower door's threshold glow, built behind the opaque slab that entirely covers
  it, reaching zero pixels for the life of the game.
* **`(the Sensei commit)` the promise on floor 20 is kept by a real body.** Bespoke
  scene, moveset, voice, rig height and redraw hand.

---

## ⚠ THE FINDING THAT REACHES BEYOND THE LOBBY

**`slice_test_hero_plate` passed nine assertions about a HUD element that had never
appeared in the game.** `CharacterBars._find_bound_ability_bar` walked only
`tree.root.get_children()` and descended only into children that WERE CanvasLayers — the
one arrangement no scene in this project builds (`Arena`, `LocalCoop` and `World` all
`add_child(layer)` onto themselves). The suite parented its own hotbar that one way, so
it could only ever have passed.

**Every hero in this game, arena included, was still wearing the head bar the maker
asked to have moved.** Proved with `tools/probe_plate_in_real_scenes.gd`, fixed,
re-probed, and the suite now carries one case built the way production builds one.
Worth re-reading whenever a suite is about to be used as evidence.

---

## ▶ THE THINGS THE MAKER MUST DECIDE

**1. A FONT. Still the single highest-value visual change available.**
`assets/ui/stickspire_theme.tres` carries 21 font_size/font_color entries and **not one
Font resource**, and there is no font file anywhere in the repo. Everything falls back to
Godot's built-in Open Sans subset, whose coverage stops at Latin-1, and Godot draws a
zero-width nothing with no error. `slice_test_font_coverage` guards 237 files with
substitutions. Two of those substitutions were deleted this session by DRAWING the icons
instead (the armoury and class pads), which is the better fix wherever it is affordable
— but it is not affordable for every glyph. Ship a font and the suite goes green on its
own, and every glyph comes back looking the way it was written.

**2. THE SENSEI'S NUMBERS.** His tells are the longest on the roster (0.85–0.95 s) and
his cooldowns the shortest (1.9 → 1.0). That pairing IS the fight — a long tell is what
makes crossing his lane possible, a short cooldown is what stops crossing once being the
answer forever — so read either number alone and it looks mistuned. It has never been
played. `BossRoster` also gives him hp_scale 2.4 and speed_scale 1.55, both inherited
from the dojo.

**3. WHY A CLIMB FIGHT STILL DOES NOT LOOK LIKE A BOT FIGHT — AND IT IS NOT COOLDOWNS.**
Unchanged from the last handoff. The climb already pays x1.8 on quick and heavy spells.
The gap is **HP**: a showcase fighter has 320 to a base hero's 100, so the fight lasts
long enough to see a whole kit. Left untouched deliberately — it moves the whole game's
balance at once.

---

## ▶ WHAT IS LEFT

1. **PLAYTEST.** The only real item.
2. **A font.** See above.
3. **`probe_reachability` reports 252 of 939 public entry points with no shipping
   caller.** A report, not a gate, and it over-reports for autoloads. Read it and
   promote what matters.
4. **Two carve limitations left alone on purpose** — both fixes are FEEL changes.
   `RockPillar` stays on `carve_disc`/`carve_area` (a column's contact IS round);
   `IceWall`'s piercing seat got a 6 px non-piercing probe as a local workaround, and
   making the seat itself non-piercing would move where every ice wall in the game
   plants itself.
5. **`_host()` calls `visit_hub()`**, so hosting navigates immediately and Start Run is
   effectively unreachable from the title. Already true of the old coop panel; the
   button is kept as a fallback for when `visit_hub` fails.
6. **Roster balance is unsolved** — Stormcaller went 16-0 in bot fights.

---

## ⚠ TRAPS THIS BRANCH HAS PAID FOR — do not re-learn these

* **A HANDOFF FILE GOES STALE AND A GIT LOG DOES NOT.** See the top of this file.
* **THE LOUD BUG GETS FIXED AND THE QUIET ONE DOES NOT.** The same 270-degree
  `_arc_points` sweep existed in two sibling functions in one file. The one that printed
  `Invalid polygon data, triangulation failed` every frame was fixed in `5d40d74`; the
  one that triangulated cleanly into the wrong shape survived two more commits and was
  only found by photographing the room. Do not let the console define the search.
* **A SUITE THAT BUILDS ITS OWN WORLD CAN ONLY TEST THAT WORLD.** See the hero-plate
  finding above. When a suite constructs its own scaffolding, add one case built the way
  production builds it — that case is usually the whole value of the file.
* **A HIGHLIGHT TWENTY TIMES THE VALUE OF THE THING IT IS ON IS NOT A HIGHLIGHT, IT IS
  THE ONLY MARK.** Every "random line" in the maker's lobby report was a rim, cap or
  hoop that had outlived the object it described. Capture the screen and measure it —
  `tools/tavern_capture.gd` plus a pixel probe found all of them in one pass.
* **A GATE BUILT FROM AN ALLOWLIST OF SINKS MISSES THE FRONT DOOR.** The font suite
  matched `.text =` and walked past a CONSTRUCTOR ARGUMENT. The set of ways a string
  reaches a control is open; the set of sinks that are NOT the screen is small and
  closed. Invert the rule: suspect everything, exempt the console.
* **SIX CONCURRENT OPUS AGENTS EXHAUSTED THE SESSION LIMIT** and all six died mid-edit.
  One left `CharacterRig.gd` unparseable while the other five were being told to verify
  against it. Run **three at a time**, and on a resume `git status` and prove the tree
  PARSES before believing any suite result.
* **A FULL SWEEP IS UNREADABLE WHILE AGENTS ARE WRITING.** Proved, not assumed. Verify
  per-suite during, sweep once at the end.
* **NAMING A CLASS IN A TEST MAKES IT A COMPILE-TIME DEPENDENCY**, which in a `--script`
  run resolves BEFORE autoloads register. Read constants via `get_script_constant_map()`.
* **`--script` DOES register this project's autoloads** (all twelve). Only `--check-only`
  compiles a script's chain before the autoload table exists.
* **A TEST THAT HARDCODES A GLYPH BREAKS WHEN THE GLYPH MOVES.** Both sides must read
  the same named constant.
* **SCRAPING SOURCE TEXT FOR A LITERAL IS WHY THE LITERAL DRIFTED.** Name the const and
  reflect over it.
* Still true: **the Godot editor strips `project.godot` keys while it is open**
  (`slice_test_mobile_config` guards it; run it before any push), **do NOT edit code
  through shell heredocs** (write a patch FILE and assert single-occurrence anchors),
  and **a precondition ORed against the thing it precedes is not a precondition**.

---

## ▶ THERE IS NOW AN OBSIDIAN SECOND BRAIN

Installed 2026-09-07 at the maker's request, so context survives between sessions.

* **Vault:** `C:\Users\Raaed\Documents\Second Brain`, wired as `OBSIDIAN_VAULT_PATH` in
  `~/.claude/settings.json`, with a SessionStart hook that publishes it.
* **What is in it:** the DURABLE layer only — what the game is, the rulings that must
  not be re-litigated, and the lessons that cost real time. **It deliberately does not
  hold live state**: this file and `git log` remain authoritative, because a note that
  duplicates a branch name is a note that will be wrong next week. Anything
  time-sensitive in the vault carries an `as of` stamp.
* **Commands:** `/obsidian-save`, `/obsidian-log`, `/obsidian-find`, `/obsidian-world`,
  `/obsidian-challenge` and ~42 more. Read `<vault>/index.md` before searching it.

---

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3        # 219 suites, ~340s
python python-tools/check_window_override.py         # 1366x768 committed
godot --headless --path godot-project --script tools/slice_test_mobile_config.gd
godot --headless --path godot-project --script tools/slice_test_font_coverage.gd
python python-tools/run_capture.py tavern            # the lobby, without the HUD
python python-tools/run_capture.py boss_roster       # every artist, side by side
```
