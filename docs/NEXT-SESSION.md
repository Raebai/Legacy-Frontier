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
