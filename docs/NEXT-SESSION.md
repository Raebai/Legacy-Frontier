# RESUME HERE

## STATE — 2026-09-06. QUEUE CLEARED. 8 COMMITS, 215/215 GREEN, TREE CLEAN, PUSHED.

Branch `bot-fight-quality`. **Every item in the previous queue is now built** — items 1–8,
plus the open design question, which the maker answered. Six agents ran with strict
disjoint file ownership; all six landed.

**NOTHING HERE IS PLAYTESTED.** Every claim below is a measurement or a headless suite.
That judgement is unchanged and it is the whole point: playtest beats reasoning.

### ▶ PLAY IT FIRST — three things you can only judge by looking

**F5** → title → Single Player. **Lobby → Watch Bots** for the showcase. The Android APK
is stale — it predates every commit below.

1. **Half the UI's icons were never being drawn and now are.** See the font block below.
   The touch D-pad, the title screen's two primary buttons and every padlock were blank.
   Look at the title screen, the pause menu, the armoury, and a phone build.
2. **The class roster is restyled** — element-coloured rows, a drawn stickman, a real type
   hierarchy, no armoury button.
3. **Nineteen armoury items are real** and unplaytested. "Nothing is unpickable" is not
   "these are the right numbers".

---

## ⚠ THE FINDING THAT MATTERS MOST — THE THEME HAS NO FONT

`assets/ui/stickspire_theme.tres` carries 21 font_size/font_color entries and **not one
Font resource**, and there is no font file anywhere in the repo. Every control falls back
to Godot's built-in Open Sans subset, whose coverage stops at Latin-1. `has_char` is false
for 12 of 15 symbols probed. **Godot draws a zero-width nothing and raises no error**,
which makes this the hardest class of bug to report: the person looking at it can only say
"it needs to look better".

What was invisible — not decoration:

* **The on-screen touch D-pad.** `◂ ▸ ▲ ✕` are left, right, jump and close in `World._pad`.
  On a phone, the platform this game is built for, they were four blank rectangles.
* **Both primary verbs on the title screen.** `SINGLE PLAYER ▸` and `MULTIPLAYER ▸` drew
  the words followed by two blank columns.
* **The padlock** on every locked armoury row and every locked spell.
* The class roster's leading colour block — the source calls it "the leading block on a
  rail row, drawn in the class colour" and it had never once been drawn.
* The colour picker's swatch and both state marks — a colour picker with no colour.
* The hub signpost, the guardian banner, the exit pad arrow, the speech bubble's dots, the
  music toast, all four Settings chevrons, and the Armory and Reset Hand buttons.

Fixed by DRAWING blocks as `StyleBoxFlat` borders and substituting verified-drawable
characters (`« » ‹ › • · † ‡ × §`). `slice_test_font_coverage` guards 237 files.

> **⚠ THIS IS THE WORKAROUND. THE FIX IS A FONT, AND IT IS THE MAKER'S CALL.**
> Ship a font with symbol coverage and the suite goes green on its own, and every glyph
> above comes back looking the way it was written. `WAIVED` is deliberately empty:
> anything that needs to be in it is a symbol someone wants and cannot have.

---

## ▶ THE THREE THINGS THE MAKER MUST DECIDE

**1. A FONT (see above).** The single highest-value visual change available.

**2. THE BRAWLER IS PAID NOTHING BY ELEMENT AFFINITY.** Measured, not assumed: its class
element is FIRE and its entire hand is EARTH (Stomp, Petrify, Rock Wall, Boulder Hurl,
Meteor Fist). Coherent for a no-magic class whose fire lives in `melee_element`, but
coherent is not intended. Three ways out, all the maker's: `CLASS_CONFIG` is stale and the
Brawler is really EARTH; it wants one fire spell in hand; or the melee class sits this out.
Recorded in `UNPAID_CLASSES` and asserted BOTH ways, so giving it a fire spell goes red
pointing at the note, and a second class falling off goes red too.

**3. WHY A CLIMB FIGHT STILL DOES NOT LOOK LIKE A BOT FIGHT — AND IT IS NOT COOLDOWNS.**
The climb already pays x1.8 on quick and heavy spells. The gap is **HP**: a showcase
fighter has 320 to a base hero's 100, so the fight lasts long enough to see a whole kit.
Left untouched deliberately — it moves the whole game's balance at once.

---

## ▶ WHAT LANDED (8 commits; each message carries its own red-run evidence)

* **`a438566` the Music and SFX sliders were writing into a mixer that did not exist.** The
  bus layout was referenced by `uid://`, which resolves through untracked build output the
  editor rewrites. When it failed Godot booted a ONE-BUS default, so
  `get_bus_index("Music")` was -1 and every volume write was silently discarded. Now a
  `res://` path, which consults no cache. The re-import on record treated the symptom once
  per machine.
* **`3b7d16f` element affinity** — a spell of your class's own element hits 1.25x harder.
  Shatter 62 → 78 for a Cryomancer, 62 for an Arcanist. Bonus-only, never a penalty. Rides
  `_base_element`, not `_element`, or a spellement staff would make it unconditional. The
  amplified slot wears its element's colour on `LoadoutBar`, because the damage number is
  already tinted by element, so the bonus is invisible at impact by construction.
* **`bd86a75` three tints** — head, body, legs, and a helmet takes the head's. Six capture
  tools write `limb_color` DIRECTLY, so the parts are OVERRIDES with an unset sentinel;
  plain fields would have drawn a recoloured torso on a default-blue head in every one of
  them, and no existing test could have seen it.
* **`518deeb` walls take the material they are made of** — `carve_capsule`. Severed run
  0 → 56 px, honestly compared against 16 px for the best a single disc could do (the walls
  carved nothing before, so 0 was trivially true). **Cheaper** than the 36 disc calls it
  replaces — 516 vs 637 us — while removing more, because a disc row leaves scallops.
  `HorizonArc` finally wired.
* **`0c22676` the class roster restyled** — the maker picked this shape from three mockups.
* **`1d6e220` nineteen real armoury items** — and **the legs slot was never being read**:
  `Hero` walked a three-slot literal in TWO places while `GameState.LOADOUT_SLOTS` has said
  four for a long time. Found by DRIVING a real Hero (16 of 19 pieces moved a stat, the
  three greaves moved exactly 0), not by reading the table. Both loops walk
  `Hero.GEAR_SLOTS` now.
* **`d135120` the player has a name** — `user://profile.json`, carried across the wire and
  sanitised ON RECEIPT, bidi overrides included (U+202E reverses the rendering of
  everything after it, so a peer's name could rewrite the text this game wrote next to it).
  And **Local Play finally exists**: `LocalCoop.gd` was real and built on every offline run,
  but `SessionKind.LOCAL` was written by nobody, so a couch game was never a party.
* **`9be9624` the font fix** (above).

---

## ▶ WHAT IS LEFT

**1. PLAYTEST.** Nothing above has been. That is the only real item.

**2. A FONT.** See above.

**3. `probe_reachability` REPORTS 252 OF 939 PUBLIC ENTRY POINTS WITH NO SHIPPING CALLER.**
A report, not a gate, and it over-reports for autoloads. Read it and promote what matters,
the way `slice_test_wall_reachable` already did for the shove.

**4. TWO CARVE LIMITATIONS LEFT ALONE ON PURPOSE — both fixes are FEEL changes.**
`RockPillar` stays on `carve_disc`/`carve_area`: a column's contact IS round, and its seat
comes from a piercing floor probe that has already gone through any plank the fang grew
through, so routing it by body would carve UNDER the ledge. `IceWall` has the same piercing
seat and got a 6 px non-piercing probe as a local workaround; making the seat itself
non-piercing, as `RockWall` already is, would move where every ice wall in the game plants
itself.

**5. `GameState.colourway` STILL HAS NO WRITER.** Pre-existing. It is the middle link of
the per-part fallback chain, so wiring `Outfitter.chosen_colourway` into it would make
unpainted parts follow the pause-menu pick automatically. Until then they follow the
fallback, which is what `Hero` passes.

**6. `_host()` CALLS `visit_hub()`**, so hosting navigates immediately and Start Run is
effectively unreachable from the title. Already true of the old coop panel; the button is
kept as a fallback for when `visit_hub` fails.

---

## ⚠ TRAPS THIS SESSION PAID FOR — do not re-learn these

* **A GATE BUILT FROM AN ALLOWLIST OF SINKS MISSED THE FRONT DOOR.** The font suite matched
  `.text =` and walked straight past `_button("SINGLE PLAYER ▸", …)` — a CONSTRUCTOR
  ARGUMENT. The set of ways a string can reach a control is open; the set of sinks that are
  NOT the screen is small and closed. **Invert the rule: suspect everything, exempt the
  console.** That widening took the count from 3 remaining to 36.
* **SIX CONCURRENT OPUS AGENTS EXHAUSTED THE SESSION LIMIT** and all six died mid-edit. One
  had called two helpers it had not yet written, so `CharacterRig.gd` did not parse and
  EVERY rig suite went down — while the other five were being told to verify against it.
  Run **three at a time**, and on a resume `git status` and prove the tree PARSES before
  believing any suite result.
* **A FULL SWEEP IS UNREADABLE WHILE AGENTS ARE WRITING.** Proved, not assumed:
  `slice_test_bout_runs_clean` reported FAIL in a sweep and passed clean run alone. Verify
  per-suite during, sweep once at the end.
* **NAMING A CLASS IN A TEST MAKES IT A COMPILE-TIME DEPENDENCY**, which in a `--script` run
  resolves BEFORE autoloads register — so an audio autoload was unresolvable, `load().new()`
  handed back an uncompiled script, three tests aborted, and the console blamed an unrelated
  file another agent happened to be editing. Read constants via `get_script_constant_map()`.
* **`--script` DOES register this project's autoloads** (all twelve). Only `--check-only`
  against a script compiles its chain before the autoload table exists.
* **A TEST THAT HARDCODES A GLYPH BREAKS WHEN THE GLYPH MOVES.** `slice_test_outfitter`
  asserted a literal `◈` that was never drawn, then failed on its own private copy of the
  answer. Both sides read `Outfitter.RARE_BADGE` now.
* **SCRAPING SOURCE TEXT FOR A LITERAL IS WHY THE LITERAL DRIFTED.** `slice_test_gear`
  scraped Hero's inline slot array because "there is nothing to reflect over" — which is
  exactly how the same list came to say three slots in two functions. Name the const and
  reflect over it.
* Still true from before: **the Godot editor strips `project.godot` keys while it is open**
  (`slice_test_mobile_config` guards it; run it before any push), **do NOT edit code through
  shell heredocs** (write a patch FILE and assert single-occurrence anchors — that assertion
  caught a double-apply again this session), and **a precondition ORed against the thing it
  precedes is not a precondition**.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3        # 215 suites, ~340s
python python-tools/check_window_override.py         # 1366x768 committed
godot --headless --path godot-project --script tools/slice_test_mobile_config.gd
godot --headless --path godot-project --script tools/slice_test_font_coverage.gd
```
