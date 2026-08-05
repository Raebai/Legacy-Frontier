# RESUME HERE — 2026-08-05 (d), PAUSED ON THE MAKER'S INSTRUCTION

**ASHPIRE.** Branch `bot-fight-quality`, **152/152 green**, tree clean.
**34 commits, NOT PUSHED. Nothing in this session has been played by hand.**

## ▶ DO THIS FIRST (the one unfinished thing)

**`ScorchDecal` still draws perfect circles.** The ground-decal pass toned its
COLOUR but not its SHAPE, so the large smooth pale discs still on the floor are it.
`GroundCrater._ragged()` is the treatment — copy it onto
`ScorchDecal.gd:160-161`, which are still `draw_circle`. Verify the way the crater
fix was verified: shoot the same matchup, crop the same frame, look at it before
and after.

    python python-tools/make_clip.py --a 8 --b 2 --hp 300 --out check
    ffmpeg -i <clips>/swordsaint_vs_brawler.mp4 -vf "select='eq(n\,150)',crop=420:180:150:210,scale=980:-1:flags=neighbor" -frames:v 1 out.png

## ▶ THEN: THE THINGS WAITING ON YOUR EYES, NOT ON CODE

1. **The weapon trail's ELEMENTAL case has never been seen.** It takes `aura_color`
   when an aura is lit, so a fire fist should streak fire. The frame that verified
   the trail had no aura up, so that path is reasoned only. Load a Brawler with the
   fire fist. Dials: `CharacterRig.TRAIL_WIDTH_FRAC` and the 0.55 alpha.
2. **The time-stop bubble in a real fight.** Chronostasis holds a NEGATIVE inside
   its ring for the whole 3 s freeze, then snaps back with the payout. ⚠ The probe
   that verified it has a BLACK background so the negative reads bright white; the
   real arena sky is pale and will invert DARK. The look in that image is not the
   look you will get.
3. **The Swordsaint's draw-step.** `iai_slash` now lunges on the cut. It is the
   fix for 19%/25% across two sweeps, and it is UNMEASURED — the sweep that would
   price it was killed on your instruction because it was measuring the reverted
   deflect change.

## ▶ THE BIG UNBUILT ONE

**Per-class Tier 3 drops.** `BotMatch.CLASS_DROP` pins one per class today, but
there are SIX drops for NINE classes so three are shared (Juggernaut/Stormcaller,
Shadowblade/Warlock, Cryomancer/Swordsaint). Giving every class its own means
authoring at least three new ult-weight spells with bespoke spectacles — the
existing four are RULE-BENDERS with their own drawing, and the class-identity
ruling forbids making the difference a tint. **That is a session of work and it
has not been started.**

Also unbuilt, fully specced: `docs/superpowers/specs/2026-08-05-stick-customisation.md`
(hair/accessory slots, sheathed weapons, bark text in the speaker's colour — the
paper-doll plumbing ALREADY EXISTS, the gap is a library).

## ▶ WHAT LANDED THIS SESSION

- **Two new bosses** (Eraser, Etcher) — distinct artists per climb 3.7/4 → 4.99/6.
- **Socket glyphs** — hands showing a duplicate figure 24/36 → 0/36.
- **`WaveDef.elite_wave`** — floors 3/7/9 concentrate their elite budget.
- **Clips**: the ult white-out, two AoE paint-blobs, and the camera framing
  (fighters 3.6% → 10.8% of frame height). `python-tools/clip_review.py` scores a
  delivered mp4 and is the regression test for all of it.
- **Chronostasis time-stop bubble** — a negative bounded to its own ring, because
  a full-screen one lies about a bounded spell's extent.
- **Bot duels carry Tier 3 drops**, matchups are RANDOM, and the sweep harness can
  do a real round-robin with drops off.
- **Weapon trails**, **ground decals toned + ragged**.

## ⚠ BALANCE: READ THIS BEFORE TUNING ANYTHING

Two 72-bout round-robins were run. The classes I changed NOTHING about moved by up
to 12 points between them. **At n=16 per class the noise is ±12, so only the
extremes are signal** — eight of the nine are indistinguishable from 50%. The
Swordsaint is the only class broken beyond doubt (19%, then 25%, and unmoved by
+16% health). Separating the middle eight needs ~4x the bouts, which is one ~40
minute sweep — worth doing ONCE, not per tweak.

    godot --headless --path godot-project --script tools/botmatch_sim.gd --         --roundrobin=1 --repeat=8 --round=22 --hp=190 --wall=70

## HOW TO VERIFY

```
python python-tools/run_all_tests.py --jobs 8      # 152 suites, ~80s
python python-tools/clip_review.py --sheet         # every clip, scored
python python-tools/make_clip.py --random          # a rolled matchup
```
After any `--headless --import`, CHECK `project.godot` still has four keys:
`theme/custom`, `physics_ticks_per_second`, and both `rendering_method`s.

## TRAPS THIS SESSION ADDED

- **An instrument that measures brightness cannot tell an INVERSION from a
  blowout.** `clip_review` nearly condemned the best effect in the game; a blowout
  is bright AND FLAT, an inversion is bright and SHARP (more detail than a normal
  close-up).
- **A probe that counts rendered frames as 1/60 s lies on a cheap scene.** The
  time-stop probe rendered far above 60 fps, so "3.32 s" was about one real second.
- **A "dead air" metric keyed on the frame's modal value** scored the very frame it
  was calibrated on at 62.7% against a 5.5% threshold.
- **A test registered in TESTS whose driver call never landed** — caught by the
  by-absence armour, again.
- **Skill that NARROWS a window makes the best bots worst at it.** Reverted on
  instruction, but the observation stands and is why the Swordsaint fix went into
  its spell instead.

---

# RESUME HERE — 2026-08-05 (c), THE QUEUE IS EMPTY

**ASHPIRE.** Branch `bot-fight-quality`, **152/152 green**, tree clean.
**20 commits, NOT PUSHED. Still nothing has been touched by hands.**

Both specs that were "designed, not built" are now built, plus the mini-boss
wave slot. There is no unbuilt item left on the queue.

## ▶ WHAT TO PLAY

1. **CLIMB TO FLOOR 3, 5 AND 7.** Two new bosses are live and they roll on their
   own — **THE ERASER** (floors 1-6) and **THE ETCHER** (3+). Nothing pins a boss,
   so the rows went live on the first run.
   - The Eraser: it eats the floor permanently and never erases under its own
     feet. **The correct play is to walk toward it and stay there.** If that does
     not read in your hands, the whole boss is wrong.
   - The Etcher: `bath` is a 2.2 s rooted wind-up you can **BREAK** by landing
     5.5% of its HP inside the window. Nothing else in the game can be
     interrupted. It opens an acid pool under itself so the break costs you.
2. **LOOK AT THE HOTBAR.** Every spell socket now has a FIGURE in it — the same
   thirteen the cast circles use. Two things want your eye specifically:
   **PULSE / SPIRAL / SNARE all read as "a swirl in a circle" at 46 px**, and an
   **ULT socket** (gold ring + element ring + figure) is busy.
3. **FLOORS 3, 7, 9** now spend their whole elite budget inside one wave instead
   of sprinkling it. It is a concentration, not a staged entrance — see below.

## ⚠ THREE THINGS TO JUDGE, NOT BUGS

1. **THE ERASER MAY BE THE CARTOGRAPHER.** Both are spatial. The separation is of
   KIND — the Cartographer's page resets between figures, the Eraser's never
   does — and it was written down as a cut candidate before it was built. **If
   they feel the same, the Eraser is the one to cut**, because the Cartographer
   owns the compass annulus and nothing else teaches it.
2. **THE ELITE WAVE CONCENTRATES, IT DOES NOT STAGE.** The design wanted a short
   wave — one named body walking into an emptied room. That broke two deliberate
   invariants the suite holds (budgets never shrink across a floor; exactly ONE
   wave in the tower may hand off at 0, because the overlap IS the pacing). So
   the flag rides an existing wave instead. Staging one needs those invariants
   revisited, and that is your call.
3. **8 SPELLS DRAW A DIFFERENT FIGURE ON THE BAR THAN IN THE WORLD.** Deliberate,
   on your ruling: three of the re-points would make the world reading worse (a
   rock pillar really does erupt). Listed and commented in
   `AbilityBar.GLYPH_OVERRIDE`. Without them **19 of 36 hands still showed a
   duplicate figure** — measured.

## WHAT THE SUITES CAUGHT THIS SESSION (all real, none reasoned)

- The `bosses_are_different_fights` test asked its question of a hand-listed
  THREE, and the one it left out was **the Guardian** — the fallback boss and the
  most fought body in the tower. Driving it off `BossRoster.ids()` made it abort:
  the Guardian does not answer `boss_artist` or `phase_cooldown`, because five
  identity virtuals lived on `TowerBoss` and the Guardian is the base.
- `slice_test_boss` asserted a COMBAT-floor guardian is `< 400` hp. **A floor-1
  Guardian is 512** (640 × 0.80). It had been a coin flip passing only on a
  Scribble roll, green for as long as nobody rolled the other side.
- Nine of the eleven "motif-less" spells the glyph spec named **already declared
  `sigil_motif`**. Two of my rows contradicted the declaration and the suite
  failed on exactly that.
- `Encounter.party_size()` carried a comment promising it was guarded for
  headless harnesses. It was not — an absolute `get_node_or_null` outside an
  active tree ERRORS, and an error aborts before the `return 1`.

## HOW TO VERIFY

```
python python-tools/run_all_tests.py --jobs 8      # 152 suites, ~80s
godot ... --headless --script tools/_probe_boss_audit.gd   # boss variety
```
After any `--headless --import`, CHECK `project.godot` still has four keys:
`theme/custom`, `physics_ticks_per_second`, and both `rendering_method`s.

## MEASURED

    distinct artists per 10-floor climb   ~3.7 of 4  ->  4.99 of 6
    mean Guardian appearances per climb        ~3.3  ->  2.33
    eligible boss pool, deep floors                3  ->  4
    hotbar hands showing a duplicate glyph  24 of 36  ->  0 of 36

---

# RESUME HERE — 2026-08-05 (b), THE BIG CHANGES LANDED

**ASHPIRE.** Branch `bot-fight-quality`, **152/152 green**, tree clean. 14 commits.
**All of it UNPLAYTESTED.**

## ▶ THREE THINGS THAT ARE NEW SINCE THE SECTION BELOW

1. **CLIPS HAVE SOUND.** Every clip this project ever made was silent — a PNG
   sequence has no audio track. The default path is now Godot's own Movie Maker
   (`--write-movie`): 48 kHz stereo, measured mean -18.1 dB. ⚠ It is NOT a screen
   recording — `--write-movie` FORCES `--fixed-fps`, so it stays frame-exact. An
   OS-level grabber would capture ~19 fps at 1080p and put the judder back.
   `--silent` keeps the old frame-grab.

2. **ORDINARY ENEMIES CAST SPELLS.** Five archetypes, each answered differently.
   ⚠ Gated to floor 2+, and the spell STARTS ON COOLDOWN — two suites caught that
   the gate was replacing each archetype's own attack rather than adding to it.
   ⚠ Co-op CLIENTS do not see them yet: `Net`'s spell arm is boss-only, so the
   broadcast is a clean no-op behind a `has_method` guard.

3. **GRAVITY FLIP IS A WELL YOU CAN MOVE INSIDE.** ⚠ It is the JUGGERNAUT's spell —
   the Swordsaint carries `blood_pact` and there is no path by which it holds gravity
   flip. Built for the Juggernaut; say if "gravity swordsmen" meant otherwise.
   Measured justification: the old version spent **76% of its duration with everyone
   pinned motionless against the ceiling**. It also dealt ZERO damage — the header
   promised a payoff that was never implemented. Now: a real radius, ground-grade
   steering inside it, and a landing collapse scaled by fall height.
   ⚠ TWO EDGES FOR YOUR EYE: the caster is not billed (one word to flip), but a
   **co-op partner IS** and cannot cheaply not be.

## ▶ WHAT IS STILL NOT BUILT (both fully specced)

- **Socket glyphs** — `docs/superpowers/specs/2026-08-05-socket-glyphs.md`.
  ⚠ Carries the finding that keying on `SpellDef.Kind` duplicates the glyph in
  **8 of 9 classes**; key on the spectacle instead.
- **Two new guardians** — `docs/superpowers/specs/2026-08-05-two-new-guardians.md`.
  ⚠ Carries the 12-point contract a boss must satisfy, and the measurement that
  a 10-floor climb sees ~3.7 of 4 artists with floors 4-10 drawing from THREE.
  Fix the four suites that hardcode the boss count FIRST.

---

# RESUME HERE — 2026-08-05, PAUSED AFTER A LONG BUILD

**ASHPIRE.** Branch `bot-fight-quality`, **152/152 green**, tree clean.
Ten commits. **Everything below is UNPLAYTESTED** — see THE STANDING JUDGEMENT.

---

## ▶ WHAT TO DO FIRST

1. **WATCH A BOT FIGHT.** `F5 → Watch Bots`. That button did not exist an hour ago
   (`Lobby._watch_bots` had **zero callers**), so there has been no in-game route to
   a duel at all.
2. **WATCH THE CLIPS** in `%APPDATA%/Godot/app_userdata/Ashpire/clips/`. Shoot more
   with `python python-tools/make_clip.py --a 6 --b 5`.
3. **TRY TO PARRY A BOLT**, and watch a bot do it. That is the change most likely to
   feel different in your hands.
4. **CLIMB TO FLOOR 2.** The blocker is fixed; the rest of the tower is downstream of
   it and has never been reachable.

---

## ▶ THE HEADLINE: THE CLIP PIPELINE WAS LYING TWICE

**1 · IT WAS ENCODING A FIGHT FROM BEFORE THE RENAME.** Godot derives `user://` from
`config/name`, so "Legacy Frontier" → "Ashpire" moved the whole user directory — and
four Python tools kept the old name hardcoded. Godot wrote frames to `Ashpire/clips/`
while the encoder read `Legacy Frontier/clips/`. **Both directories exist** (the
rename migration copied one across), so it found frames, encoded them, printed a byte
size and "that is the file to post". Fixed at the source: `python-tools/godot_paths.py`
parses `config/name` out of project.godot. `playtest_notes.py` was reading your
PRE-RENAME notes and ignoring every one since; `bot_sim_report.py` was ranking
pre-rename runs.

**2 · THE CLIP PLAYED AT ~3x FAST-FORWARD.** `directed_clip_capture` picks frames with
`every = round(60 / fps)` — it ASSUMES 60 fps of render. At 1920x1080 it renders ~19,
so every 2nd saved frame sampled the game at ~9.7 Hz and replayed at 30. Measured by
timestamping the same KO with two clocks out of `clip.json`: **2.63x, 2.67x, 3.09x**.
A 17.5 s fight was delivered as a 7.4 s clip. `--fixed-fps 60` fixes it; the still-frame
share fell **60% → 8%** on that flag alone.

Also fixed on the clip path: the strobe (both fighters vanished into a white frame —
the full-screen lift is now skipped while recording), the framing (fighters were ~6% of
frame height; `ZOOM_MAX` 1.15 was the real limiter, not the margin), the 2.8-seconds-of-
frozen-still tail, and the winner wearing their own health bar for the whole result card.

---

## ▶ THE DEFLECT, WHICH IS NOW REAL

    before   2 deflects across  2/18 matches
    after   13 deflects across  7/18 matches   (same seed, same harness)

The guard was never the problem — the LADDER was. `BotDodge` answered a vertical
dodge-exit with a jump and returned **before** the parry rung underneath could be
asked, and a horizontal bolt between two grounded fighters yields a vertical exit
*every frame*. So parry was only reachable while airborne. It cannot degenerate into
permanent guarding: `parry_ready` is `guard_ready AND in_lead`, a slack-width band
around each class's own published timing.

Two more: both `Hero.take_damage` deflect branches played the ding with **no hitstop
and no camera kick**, so the most COMMON deflect in the game was the flattest; and
`guard_style` still meant "do I hold a ring" on one side of the seam and "BLADE vs
SIGIL" on the other, costing a bot Swordsaint 0.2 s per guard cycle.

---

## ▶ THE FLOOR 2 BLOCKER — root cause and why it soft-locked

`Arena._on_floor_advanced` rebuilt the room but only repositioned the hero inside a
**co-op-only branch**, so a solo climber kept floor 1's position while floor 2's walls
were built underneath it. Room heights roll 560–620; a ground exit leaves the hero's
box centred at `h1 - 17` and the new bottom wall spans `h2 ± 8`, so a shorter floor 2
puts more of the box below the wall's midline and depenetration ejects it DOWNWARD.
**4 of 20 climbs, and deterministic: 4 of 4 ground exits onto a shorter room.**

⚠ **And nothing in the game caught a hero that left the world.** No kill plane, so it
never died, never became `downed`, and `_check_party_wipe` never reached a verdict —
the run could not even END. `_catch_fallen_heroes` closes that.

`tools/slice_test_floor_advance.gd` guards it and is shaped by two traps: **it must step
physics** (the pure-geometry question finds this on 2% of rolls, the real one on 20%),
and **it carries its own controls** (one known-good and one known-broken placement
through the same predicate, or the suite fails on the instrument).

---

## ▶ EVERYTHING ELSE THAT LANDED

| | |
|---|---|
| **The Warden** | `collision_layer="2"` was written as an *attribute in the `[node]` header*, which Godot silently ignores. Every townsperson shipped on layer 1 = the rig's own ground mask, so each read its own collider as the floor. **Legs 0.09 px** against a normal 16. `probe_town_feet` could never see it — it finds rigs by the node name `Rig`, and `NPC.gd` builds its rig in code |
| **White sphere on hits** | `Enemy._flash` used HDR `(1.7,1.7,1.7)` so bloom blew the figure out; on a stick figure the biggest mass is the head circle. Now red, matching the hero |
| **Status effects** | were discs drawn at the BODY origin, which sits at mid-thigh — a ring the figure stood *inside*. Now drawn by the rig, which has the pose: shock is ticks that skitter along limbs, freeze is rime on the silhouette, burn licks off the shoulder and head. The burn's HDR core was washing the **entire frame** white |
| **Ice class** | Cryomancer measured **25%**, second worst, and nobody had flagged it. HP 123 → 152. HEALTH not damage — `Shatter`'s own header already argues the damage case and is right |
| **Bolts + punches** | a punch now swats a bolt (`Spell.gd` was the ONLY projectile lacking `consume()`), and two bolts meeting head-on pop each other |
| **Spell slots** | were seven flat black rectangles under a screen full of rotating magic circles. Now dashed circles that turn, cooldown = the ring closing, no numerals |
| **Swordsaint** | travel 57.6 → 106.4 px, speed 210 → 222 |
| **"Impossible"** | cut from the clock and from the VS card, where it appeared twice |

---

## ⚠ WHAT I DID **NOT** DO

1. **ORDINARY ENEMIES CASTING SPELLS.** Not started, but there is a complete
   implementation blueprint: the archetype table, which spell each of the five
   casting archetypes should get and why each is a *different* threat, the exact
   `Enemy.gd` methods to add, the co-op broadcast, and a build order. Key finding:
   **nothing on `Enemy` blocks it** — 20 different SpellDefs were cast through a bare
   Enemy and all 20 worked. What is missing is a per-archetype table and a re-tuned
   **duplicate** of each SpellDef (library damage is authored for a hero budget:
   `meteor_fist` is 165 against the mob roster's biggest hit of 22 — and you may never
   scale a SpellDef in place, it is a shared catalog resource).
2. **GRAVITY FLIP.** ⚠ **It is the JUGGERNAUT's spell, not the Swordsaint's** — the
   Swordsaint carries `blood_pact` and no path exists by which it holds gravity flip.
   The Juggernaut has a sword rig, so "gravity swordsmen" reads as the Juggernaut, but
   **confirm before building**. Today the spell has no radius at all (it lifts every
   body in the group at any distance) and deals **zero damage**; the redesign is a real
   zone with free movement inside and a landing collapse as the payoff.
3. **MORE BOSSES / MINI-BOSSES.** Roster is 4 bosses × 7 modifiers. Not started.
4. **THE SPELL-SLOT GLYPH.** A class whose spells share an element still shows three
   sockets of the same colour. The fix is a per-kind glyph sharing `MagicCircle`'s
   motif vocabulary, which needs `_draw_motif` extracted to a static first.
5. **WEAKEN and UNSTABLE** still draw the old mis-centred way. Same fault, but you
   named neither, so they are left visibly inconsistent rather than redesigned on a
   guess.

---

## ⚠ THINGS THAT MIGHT BE WRONG

1. **BALANCE IS A HANDICAP, NOT A KIT FIX.** `CLASS_VITALITY` was re-tuned against a
   real 72-bout sweep (Cleric 75 … Swordsaint 19, a 56-point spread). It makes every
   matchup watchable without touching the tower. It is not the same as fixing the
   kits, and this file's own rules say to report that rather than paper over it.
2. **`body_escaped_bounds` went 1 → 2** in the duel sim after these changes. It is a
   sim-harness observation in a mode that is not the shipping duel, and I did not
   chase it. If a fighter ever leaves the versus stage in front of you, that is this.
3. **`damage_outlier` × 8 is the documented calibration mismatch** (the sim's tower-hp
   pool vs `BotMatch`'s), a deliberate pre-existing non-change.
4. **Nothing here has been touched by hands.** The clips are the only output anyone
   has actually looked at, and I looked at frames, not motion.

## HOW TO VERIFY

```
python python-tools/run_all_tests.py --jobs 8      # 152 suites, ~95s
python python-tools/make_clip.py --a 6 --b 5       # a duel, as an mp4
godot ... --headless --script tools/bot_sim.gd -- --mode=duel --max-matches=18 --difficulty=2
```
After any `--headless --import`, CHECK `project.godot` still has four keys:
`theme/custom`, `physics_ticks_per_second`, and both `rendering_method`s.

## TRAPS THIS SESSION ADDED TO THE PILE

- **A `.tscn` `[node]` header silently ignores unknown attributes.** Only `name`,
  `type`, `parent`, `groups`, `index` and `instance` are header attributes.
  `collision_layer="2"` written there is not an error and not applied.
- **A probe that finds nodes by NAME cannot see nodes built in code.**
  `probe_town_feet` looked up `^"Rig"`; every NPC builds its rig with
  `CharacterRig.new()` and was silently skipped, for as long as that probe existed.
- **A reaction row without an outcome arm is worse than no row** — the pair memoizes
  and then passes through.
- **A 30 Hz reaction poll cannot see two fast projectiles cross.** Point shapes missed
  1 crossing in 5 (measured over 200 phase offsets). Sweep the segment travelled.
- **The by-absence armour works.** Three new tests were registered in `TESTS` and never
  called, and the suite failed on exactly that instead of reporting a cheerful pass.

---

## THE STANDING JUDGEMENT — repeat it, do not soften it

**Every feel number in this stack is reasoning, not feel.** The maker's one-line
complaints from ~40 minutes of live play have repeatedly found more real bugs than the
entire suite ever has. This session alone, four of the things fixed above were reported
by eye in a sentence each and were all real, all root-caused to something no test could
have seen: an ignored `.tscn` attribute, an HDR colour, a co-op-gated branch, and a
ladder ordering.

**Playtest beats reasoning every time. Ship things the maker can press.**
