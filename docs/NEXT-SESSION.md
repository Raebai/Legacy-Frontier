# RESUME HERE

## ⚠ 2026-09-29 — "RESUME" NOW MEANS THE ISEKAI MMO. STICKSPIRE IS ON THE BACK BURNER.

Maker, 2026-09-29, when asked whether to keep working the STICKSPIRE queue below:

> *"this is to do with the old game that is being replaces stickspire please pause it and
> put it on the back end we are focussing on the isekai project thats the main thing with
> the artifact file as well all focus on that when I say resume keep this noted"*

**So: do not start on anything under "PARKED — STICKSPIRE" below unless the maker names it.**

### The active project

A first-person heavy-fantasy **isekai MMO in Unreal Engine 5.8**. Co-op PvE *and* PvP,
premium, never free-to-play; 10 players now, architected so thousands is possible later.
It reuses the maker's existing 17-region world design — out is Lord of the Rings, down is
Made in Abyss, up is Tower of God. ⚠ **Its name is NOT settled.** The plan document is
*titled* "Legacy Frontier" — also this repo folder's name and the parked 2D game's original
name — but nothing on record says the maker ratified that as the new game's name. Ask
rather than asserting it.

**⚠ THE CANONICAL DESIGN IS A CLAUDE DOC, NOT A FILE IN THIS REPO:**
https://claude.ai/code/artifact/53c7c6d1-5489-4d97-affa-0d721e62b4cf

Reading or editing it **needs the Claude Docs connector enabled for the session** — the
`mcp__claude_ai_Claude_Docs__*` tools the 2026-09-27 session used. On 2026-09-29 it was not
connected and **all three routes to the document were tried and all three are dead ends.
Do not re-walk them:**

1. **The `Artifact` tool cannot read it.** `action: "read"` returns the Claude Docs
   *viewer's* own HTML — 56 KB of JS shell. Grepped it for nine distinctive plan words
   (`swordsman`, `isekai`, `empyrean`, `mushoku`, `crater`, `hoodie`, `Soul Engine`,
   `Anterill`, `Manyak`): **zero hits.** The content is fetched at runtime from the Claude
   Docs service and is not in the page.
2. **`claude-in-chrome` is not connected** — "Browser extension is not connected."
3. **The `chrome-devtools` CDP browser is not signed in.** Navigating it to the artifact URL
   returns **"Page not found – Claude"**, because it runs a fresh profile with none of the
   maker's cookies. A 404 there means *not logged in*, not *no such document*.

So if the connector is missing, **say so and ask** rather than guessing at the plan's
contents or treating the archived World Bible as canonical. There is
exactly ONE document by the maker's explicit ask (*"I want there to be one"*); a second
World Bible doc was folded in and deleted on 2026-09-27, with a plain-text copy kept at
`docs/archive/world-bible-2026-09-23-archived.md`.

### Locked rulings — do not re-litigate

* **HARD CAP £1,000** on one-off demo assets, separate from monthly tooling.
* **No sale, no release date.** A Steam page collects wishlists only. The
  Early-Access-product framing was rejected outright: *"stop analysing it as like a product
  I can sell."*
* **Traditional classes** — Swordsman, Knight, Mage, Priest, Ranger, Rogue. Invented
  abstract classes were *"too confusing"*. Copy Mushoku Tensei and World of Warcraft.
* **Casting = hold to chant, release.** Chant shrinks with rank, chantless at Saint.
  **No microphone** — the character speaks, the player never does. **Gesture casting is
  OUT**, and the rune-trace money shot went out with it; the money shot is now the
  legendary spell landing on a boss in slow motion, magic circle blooming under the cast.
* **Bosses must be things that FIGHT, not concepts.** *"these are not like cool enough i
  dont want to fiht a tree"* killed a tree/choir/floating-hand roster permanently. The
  replacement is corporeal: wolf, knight, giant, dragon-mountain, Vessel, hoodie-man,
  Architect-colossus. **That roster is still unconfirmed by the maker** — it was the last
  thing on screen when the 2026-09-27 session ended.
* **Rank ladder is Mushoku Tensei's:** Beginner → Intermediate → Advanced → Saint → King
  → Emperor → God, per school, public and certified.
* **Few NPCs.** *"we want to limit the amount of NPCs, player-player interactions are
  cool."* The world, the Spire's archive and other players carry the story.
* **Colour before fidelity.** Anime-cel-shaded high fidelity was rejected on cost.
* **The opening is the maker's own idea and they love it:** jump off a ledge in a hoodie,
  **the fall is the character creator**, land in a crater that never disappears.
* **Spend nothing until the editor opens.** *"Order matters: install Unreal first, confirm
  the free Manyak cel shader before paying for Anterill, and claim the free Paladin set
  before 6 October. Don't buy a single thing until the editor opens and the MCP screenshot
  loop works."*
* **Epic shipped a first-party MCP plugin in UE 5.8** (17 June 2026) and it supersedes
  UnrealGenAISupport, which is kept only for its image/3D-gen API wiring.
* Engineering rulings from research, meant to stick: **never replicate the Niagara actor,
  only the ~40-byte spectacle event** (NetMulticast from a culled actor silently fails);
  **don't build terrain on Mesh Terrain** (experimental); **don't ship gameplay
  replication on Iris** (experimental); **Soul Engine tier-70 LLM brains run server-side
  in a sidecar, never client-side** (client inference costs 1/3–1/2 frame rate); **cap
  tier-70 souls per region to a handful, not a population.**

### State of the toolchain, 2026-09-29

The maker said **"Start the installs"**. Kicked off via `winget` on this machine:
Blender, the Epic Games Launcher, and Visual Studio 2022 Community with the
`NativeGame` + `NativeDesktop` + `ManagedDesktop` workloads (Build Tools 2022 was
already present but has no IDE and no Unreal integration). Script and log:
`scratchpad/install_ue_stack.ps1` → `install_log.txt`.

⚠ **UNREAL ENGINE 5.8 ITSELF IS NOT SCRIPTABLE.** There is no winget package for it; it
installs from inside the Epic Games Launcher, which needs an Epic account login. **That
click is the maker's.** Launcher → Unreal Engine → Library → + → 5.8 → Install
(~115 GB with the editor symbols deselected).

### Verified tooling research lives in the new repo, not here

`C:\Users\Raaed\Documents\Isekai MMO\docs\` — written 2026-09-30, every claim marked
VERIFIED / CONTRADICTED / COULD-NOT-CONFIRM against Epic's own 5.8 docs and the GitHub API:

* **`unreal-mcp-setup.md`** — UE 5.8 ships an MCP server *inside the editor*
  (`ModelContextProtocol`, HTTP on 127.0.0.1:8000, does viewport screenshots).
  ⚠ **It ships ZERO tools unless you also enable `AllToolsets`** — a connected server with an
  empty tool list looks exactly like a working one. Epic also ships a Claude Code plugin:
  `/plugin install unreal-engine-skills-for-claude-code@claude-plugins-official`.
* **`engineering-stack.md`** — GAS / Iris / terrain / hosting / LLM-sidecar findings.
  **Every locked engineering ruling was checked and none were overturned.**

**Two costs that were not priced anywhere, and one strategic fact:**

1. **A dedicated server requires a SOURCE build of Unreal** (Epic's own words). The launcher
   build cannot produce one. ~100+ GB and a recompile per hotfix.
2. **UE 5.8 is the LAST UE5 release** — Epic has moved to UE6. Every "architected for
   thousands later" decision has a UE6 migration in front of "later".
3. At 100 players, measured: **replication is 79% of frame time and game logic is 4%.** The
   ~40-byte-spectacle-event ruling is right and generalises — *not sending things* is the
   optimisation.

⚠ **Corrections to the options list:** **Hathora shut down 5 May 2026.** **SpatialOS
UnrealGDK is ARCHIVED** and is the most-cited server-meshing answer online. There is **no
maintained open-source UE MMO framework at all.** And **star count is not a safety signal** —
the two most-starred UE-MCP servers (2087★ and 612★) are both abandoned *and* unlicensed.

### Still open on the active project

1. **The seven-boss roster needs the maker's yes** (see above).
2. **Cities 8 and 9** are provisional only — desert city in the Wandering Wilds, forge
   city in the Crimson Reach — *"not ratified."*
3. Do non-combat living areas exist, separate from the fighting?
4. How do dungeon side quests differ from each city's main quest?
5. The Soul Engine's real tech approach, and the limits that keep it from becoming
   computationally unbounded.
6. How much gets open-sourced, and how a community is built around it.
7. Fundraising: positioning this as a venture rather than a build-in-public side project.
8. Monetisation — deliberately set aside.
9. Late-map reveal: what is shown to the player versus kept as mystery.
10. **`concept_art.py` has no key and the maker said skip it for now.** Its live API call
    is therefore still unverified. `--list`, `--dry-run` and the missing-key path are.
11. ~~The isekai project has no repo or folder of its own~~ — **it does now, as of
    2026-09-29: `C:\Users\Raaed\Documents\Isekai MMO`**, git repo on `main`, first commit
    `04ef67b`, with Git LFS configured and *proved* before any binary asset exists (a
    200,000-byte `.uasset` staged as a 131-byte pointer) and `.uasset`/`.umap` marked
    `lockable`, because Unreal assets cannot be merged. It carries its own `CLAUDE.md` and
    **no design doc, deliberately** — there is only ever the one Claude Doc.
    ⚠ **Its folder name is a placeholder** and says so in its README: rename it freely, but
    do it **before** a `.uproject` exists, because that one is painful to change after.
    `concept_art.py` was **copied, not moved** — this repo keeps its commit history.
    **The engine project itself does not exist yet** and cannot until UE 5.8 is installed.

---

# PARKED — STICKSPIRE (the 2D tower-climber). Everything below this line is the OLD project.

**Parked clean on 2026-09-29: branch `bot-fight-quality`, pushed, `219/219` suites green
(319 s wall, measured that day). Nothing in it has been playtested to completion.** The
two questions it was waiting on were never answered because the project was paused
instead — the lobby dummies and the display face. Kept verbatim below so that if the
maker ever says "back to STICKSPIRE", nothing has to be re-derived.

## ⏸ PAUSED 2026-09-08, MID-PLAYTEST. THE MAKER WAS AT THE CONTROLS.

Branch `bot-fight-quality`, **pushed**, tree clean, 219/219 on a frozen tree. This is the
first arc in a long time where findings came from PLAYING rather than from measuring, so
the notes below are worth more than usual.

**THREE ANSWERED, TWO OPEN.** Answered by the maker at the controls and already shipped:
the font (Bangers out, Chakra Petch on Buttons + Inter for body), the strike key, and
training moving to the dojo. Still waiting on them:

1. **Should the LOBBY DUMMIES go too?** Only the lobby *lesson* was removed
   (`World._spawn_coach` is no longer called). `_spawn_dummy_yard` still puts three
   straw bodies in the hub. The maker said *"not in the lobby with the dummies"*, which
   may mean the dummies as well — unresolved, deliberately not guessed.
2. **Is Chakra Petch the right face?** Picked by me, not by them. The specimen at
   `user://font_specimen.png` also carries Rajdhani, Exo 2, Barlow Semi Condensed and
   Inter-everywhere; swapping is one `base_font` line in
   `assets/ui/fonts/display_font.tres`.

**⚠ THE ONE PIECE OF THEIR ASK THAT IS NOT BUILT: THE SENSEI DOES NOT WALK.** Maker:
*"that sensei who is walking around and talking to you"*. He is a stick figure, he is on
screen, and he talks — he stands still. Left unbuilt rather than half-built.

**AND THE STRIKE WAS NEVER BROKEN, WHICH IS THE LESSON.** The report was *"strike isnt
regstering in the training"*. `tools/probe_town_strike.gd` drives the real sweep: dummy
in `mortal`, 29.7 px against a 62 px reach, 9999 → 9986. The damage path is healthy. What
was missing is that **`melee` is bound to F and nothing in the game ever said so** — no
lesson step named its key, and the hotbar advertises RMB/Spc/1-4 and never the strike.
A verb with no affordance reads exactly like a broken verb.

⚠ **AND THE FIRST VERSION OF THAT PROBE INVENTED A BUG.** It reported "NO DAMAGE" and
was one step from being filed. `facing` is aim-driven, so a `facing = RIGHT` written
sixty frames before the sweep had been overwritten to (-0.71, -0.71) — the player was
swinging AWAY. Always assert the harness's own preconditions AT the moment of the
measurement, not sixty frames earlier.


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

## ▶ THE LOOK PASS — WHAT WAS ACTUALLY BROKEN, AND WHAT ALREADY WORKED

Maker: *"make the graphics way better ... the shadows the effects ... small changes that
make a big impact"*. Two real faults, and a longer list of things that turned out to be
**already built and working**, which is worth writing down so the next pass does not
re-investigate them.

**FIXED — FOUR ULTS OPENED IN SILENCE.** `slice_test_perf_budget` prints
`Sfx: unknown key 'rock_rise'` while casting every spell. A scan of every literal key in
`scripts/` against `STREAMS` found three dead names over five call sites — `lightning`
(TheCircuit, its open AND every arc), `rock_rise` (Siegeworks, Teardown), `shadow_mark`
(Severance). Each sits one line under a `SpellSigil.open` and one above a camera pull:
the sigil blooms, the camera lurches, no sound. Re-pointed at streams that exist.
⚠ The gate that should have caught it was `CALLED_KEYS`, **21 names hand-copied and
frozen** while the game grew to 55 — the allowlist trap again. It scans now.

**FIXED — THE HEAD BAR OUT-INKED THE FIGHTER 3.8:1.** Probed off a real frame: bar ink
4272 px vs the fighter's 1122, at salience density 0.724 against red's 0.348, and MINT is
the only green in a stage that is 68% red. 52x7 -> 34x5. ⚠ This is the un-plated path,
which is what `BotMatch` uses — **so it was the biggest thing in every posted clip**.

**FIXED — TEN BIOMES, ONE GROUND.** `tools/biome_read_capture.gd` (new) shoots the versus
stage in every biome, **one engine boot each**. Across the ten the sky moved by
(79, 77, 104) per channel and the ground band moved by **(1, 1, 2)**. `ArenaTerrain`
carried twelve hardcoded colours and no palette parameter, so it could not vary — "ten
skies" was literal and the variety never reached the middle of the screen. Now dressed
via `StageLayers.dress`, which moves hue and puts the original's luma back: measured
after, ground range (13, 4, 15) with luma range 1.2/255. `ArenaTerrain.DRESS_AMOUNT`
(0.30) is the one knob.

⚠ **ALREADY WORKING — DO NOT "FIX" THESE.** Checked, measured, and left alone: contact
shadows (luma ~40 under the feet against ~88 either side — the `_airborne` bug really was
fixed); aerial perspective (`Atmosphere` hazes spires 0.86/0.70 toward the sky *by
design*, so sky and spires sharing a value is the feature, not a fault); the rig's
inverting keyline (dark, flipping pale for dark classes — the fighters read against all
ten biomes); MSAA 4x + `hdr_2d` + the glow environment; every one of 572 literal resource
paths; every boss and elite rider script. Performance measures clean — no frame over
12 ms, `slice_test_perf_budget` green.

⚠ **AND A PHANTOM I NEARLY REPORTED.** `profile_draw_cost` showed `PauseMenu` plus 172
Buttons in the frame census — which looked like a fat always-on cost. It is not: the tool
does `get_tree().paused = true` for its ablation, and that opens the menu. The census is
of the harness. Read line 422 before believing that table.

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
