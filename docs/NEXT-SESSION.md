# RESUME HERE — 2026-08-04 (e), THE QUEUE IS BUILT

**ASHPIRE.** Branch `bot-fight-quality`, **150/150 green**, tree clean.

Four commits worked the whole playtest queue. **ALL OF IT IS UNPLAYED.**

> **`docs/PLAYTEST-QUEUE.md` is the ledger** — every ask, marked done, with what
> was actually built. Read it before this file.

## ▶ WHAT TO PLAY (F5), in this order

1. **The Antechamber.** It is a different room. The stations are TELEPORT PADS in
   one evenly spaced row — stand on one, press E, a column of light fires and you
   go up; close the screen and you come back down. A signpost stands between the
   last pad and the door. Two townsfolk instead of four, and they hop.
2. **CAST IN THE LOBBY.** The body you drive in the town is a **Hero** now, not the
   old walker — every spell, the ult, blink, nova, parry and melee work in the room,
   and three immortal straw dummies stand at the far left to throw them at. The
   sparring pad (which teleported you out to Free Play) is gone.
3. **FOUR SPELL SLOTS.** `1 2 3 4`. Every class carries four of its five authored
   roles. Five spells changed hands to keep it honest — the Brawler no longer casts
   a lightning chain, the Cleric no longer casts the Warlock's drain.
4. **The Archivist**, which is a tree. Spend a point and watch the branch grow.
5. **Class select**, which is nine names.

## ⚠ WHAT IS MOST LIKELY TO BE WRONG

1. **The Hero in the town is a new body in an old room.** It joins the "player"
   group and is frozen while a pad's screen is up, both of which were bugs until
   they were handled. If something in the room stops reacting to you, that is the
   shape of it.
2. **DIFFICULTY, still.** Four levers moved in one direction two sessions ago and
   nobody has felt any of them. It may be trivial.
3. **The fourth slot's cost.** You hold more, so you find less: the floor pickup
   pool is 14 → 9 and the class-select pick is six hands per class → four. Both are
   pinned by assertions; whether the trade is right is a play question.
4. **The touch arc grew on geometry alone.** Four 60 px buttons on a quarter circle
   need radius >= 164, so it went 126 → 165. Nothing has ever touched a touchscreen.

## ▶ THE NEXT THING TO BUILD

Nothing on the queue. The next move is a playtest, and then whatever it produces.

## HOW TO VERIFY

```
python python-tools/run_all_tests.py --jobs 8                 # 150 suites, ~80s
godot ... --script tools/archivist_capture.gd                 # the tree, GUI binary
godot ... --script tools/town_capture.gd                      # the room, GUI binary
```
After any `--headless --import`, CHECK `project.godot` still has four keys:
`theme/custom`, `physics_ticks_per_second`, and both `rendering_method`s.

## TRAPS THIS SESSION ADDED TO THE PILE

- **A tree that fits on paper does not fit on a phone.** The Archivist's first
  canvas was 324 units tall in a 640x360 base viewport, which put Close off the
  bottom edge. Two nodes also sat 37 px apart inside a 38 px tap box. Both were
  found by `tools/archivist_capture.gd`, neither by a test.
- **A `kind` nothing spawns is dead code behind a live switch.** The sparring
  station was deleted rather than left unbuilt.
- **`root.get_window()` is null at `_initialize` under `--script`** — `root` IS the
  window; set `root.size` directly.

---
---

# RESUME HERE — 2026-08-04 (d), PAUSED MID-PLAYTEST

**ASHPIRE.** Branch `bot-fight-quality` @ `243c03d`, **pushed**, **150/150 green**,
tree clean.

The maker was playing and calling things out faster than they could be built.
Eleven fixes landed in one batch. **All UNPLAYTESTED.**

> **THE LIVE LIST IS `docs/PLAYTEST-QUEUE.md`** — every outstanding ask in the
> maker's own words, done ones marked. Read it before this file.

## ▶ WHAT TO PLAY (F5), in this order

1. **Title screen** — a summoning circle scribes itself and pours elements, forever.
   Buttons glow, lift, punch.
2. **The Antechamber** — legs fixed, campfire music, an Archivist desk by the
   lectern, townsfolk who teach.
3. **Floor 1** — bigger room, no "blinds" over the fight, 36% fewer bodies, enemies
   spawning from doorways/ground marks not mid-air, breaks between waves, a
   readable health bar, health packs.
4. **The ice wizard** — its primary cast now actually throws something.

## ⚠ FOUR BUGS THAT WERE REAL, AND WHY THEY HID

Each is a pattern, not a one-off.

1. **Bent legs / "walking on their limbs."** The town used the SAME `CharacterRig`
   as combat — it just never called `set_grounded()`, which **defaults to `true`**.
   The rig believed it was on the floor at the top of a jump, pinned the feet down,
   and the IK folded a leg that could not reach. *An un-fed input is not neutral.*
2. **The "blinds" over floor 1.** `Atmosphere._draw()` painted its skyline whether
   or not `build()` was called (a CanvasItem draws on entering the tree), and
   **only `build()` applied the z-layer**. The guard suite missed it because it
   scans `StaticBody2D` and Atmosphere is a `Node2D`.
3. **The crate screamed.** It called `Sfx.play("enemy_death")` — as do five other
   inanimate things — and that cue was a body-burst plus two creature screams.
   *Both "weird sound" complaints were ONE cue.*
4. **The ice projectile was never spawned.** `Shatter.hex()` took the caster
   position as `_origin` — underscore and all — and discarded it.

## ▶ NEXT THING TO BUILD

**FOUR SPELL SLOTS** — asked for, not done. `SLOT_COUNT` is 3 while `SpellTier`'s
own docstring already says "four spell slots plus a dedicated ULT slot", so the
CONSTANT drifted from the design. Needs: `SpellTier.SLOT_COUNT` -> 4, a 4th role
per class in `SpellLibrary.SLOT_ROLES`, a `spell_4` input action, a 4th entry in
`Hero.SPELL_KEYS`.

Then from the queue: the Antechamber as a PLACE (teleport pads with a beam of
light, a signpost, fewer townsfolk with personality); the Archivist as a real
clickable TREE whose branches grow as you spend; simpler class select; and the
standing rule — "too much text and random UI pieces we dont need".

## ⚠ NEEDS THE MAKER, NOT AN AGENT

1. **DIFFICULTY IS FOUR LEVERS IN ONE DIRECTION AND NOBODY HAS FELT IT:** hero HP
   x1.4, enemy damage -25% telegraphed / -40% contact, enemy speed -15%, floor 1
   down 36% bodies, plus health packs. **It may be trivial now.**
   - Walkover on floor 1 -> first knob back is floor 1's **wave-3 cap** (4 -> 5).
   - **Floors 6-10 are ~25-30% softer too**, because the damage/speed cuts are
     global while upper body counts were deliberately left alone. If the top has
     gone soft, add BODIES up there — do not put damage back.
   - `TuningConfig.hero_vitality_mult` is a live F1 dial **shipped at 1.0**. Two
     agents independently proposed raising HP; both would have been x1.89.
2. **The audio has still never been heard.** Every replacement is paper-defensible
   only.
3. **Music licence provenance** — all six `.mp3` carry NO ID3 tags of any kind.
   Needs the maker's memory; blocks anything public.
4. **`CombatCamera.FRAME_ZOOM_MIN` 0.5 -> 0.42** bought the bigger room. At full
   fighter spread the picture is ~16% smaller. If that reads as tiny ants, walk it
   back — and `FloorGen.MAX_ROOM` comes back with it.

## TRAPS THAT COST TIME THIS SESSION

- **`git checkout -- project.godot` eats uncommitted settings.** The importer
  strips `rendering_method` / `physics_ticks_per_second`; reverting to fix that
  also reverted the uncommitted `gui/theme/custom` line. Twice. Commit first.
- **A test run used to write the real `climber.json`.** Guarded in `_save_climber`
  now (the real autoload is in the tree; a bare `GameState.new()` never is). It bit
  three times before being fixed at the source.
- **Renaming the app moves `user://`.** "Legacy Frontier" -> "Ashpire" orphaned the
  save, playtest notes, logs and clips. Migrated; old folder kept as backup.
- **Parallel agents must own disjoint files.** Two still landed in `Arena.gd`
  because the game-over card lives nowhere else. Diff before pushing.

## HOW TO VERIFY

```
python python-tools/run_all_tests.py --jobs 8            # 150 suites, ~77s
godot ... --script tools/slice_test_progression.gd       # PRINTS the XP economy
```
After any `--headless --import`, CHECK `project.godot` still has four keys:
`theme/custom`, `physics_ticks_per_second`, and both `rendering_method`s.

---
---

# RESUME HERE — 2026-08-04 (c)

**The game is ASHPIRE.** (Maker dropped the s: it carries *aspire*, which for a
game about climbing is the better word.)

**Branch `bot-fight-quality`. 149/149 green, tree clean, working tree now LF.**

## ⚠ RENAMING THE APP MOVED YOUR SAVE. IT IS MIGRATED — READ THIS ANYWAY.

Godot derives `user://` from `config/name`, so "Legacy Frontier" -> "Ashpire"
silently pointed the game at an EMPTY user directory. Your climb (floor 10, tower
conquered), the playtest notes, `logs/`, `clips/`, `npc_memory/` and every capture
lived in the old one.

**Already done:** `climber.json`, the three playtest-notes files and the four
durable directories were copied to
`%APPDATA%/Godot/app_userdata/Ashpire/`. The old `Legacy Frontier/` folder is
**left in place, untouched**, as the backup — delete it only when you are happy.
The ~500 capture PNGs were NOT copied; they regenerate.

⚠ **If the name is ever changed again, this happens again.** There is no code
migration — writing a cross-app-directory one for a single player is not worth it,
but forgetting the hazard is.

## ▶ WHAT IS LEFT FOR THE MAKER

Three things, and all three are things only you can do:

1. **PLAYTEST.** Nothing below has been touched by hands.
2. **LISTEN to the six `.ogg`** and then delete either them or the `.mp3`.
   Durations verified identical (none truncated); how they SOUND is the open half.
3. **MUSIC PROVENANCE.** I checked — all six `.mp3` carry **no ID3 tags at all**,
   so the files cannot say where they came from. Needs your memory. Names are
   distinctive ("Lord of the Land", "Unexplored Moon"); a search will likely find
   it. This is the only thing blocking a public release.

Everything else on the old queue is built.

## ▶ WHAT LANDED SINCE (c)

- **GEAR: all ten player pieces now pay a cost.** The dagger finally sheds the
  damage its own description already claimed it shed — that sentence had been
  false. "Equip something" is no longer a checklist.
- **CRLF flip-flop ended.** `.gitattributes` + renormalise; the index was already
  LF so this was a working-tree fix. Two suites had once gone red for this alone.
- **`slice_test_xp_flow`** — a new END-TO-END suite. The curve was proven by pure
  functions; this one PLAYS a floor and asserts a level arrives. It immediately
  earned its keep by proving the anti-farm purse holds: **110 kills on a 22-body
  floor bank exactly the floor's kill share, not five times it.**
- **A guard that stops test runs writing the player's real save.** This bit THREE
  times in one session — a suite drove `advance_floor()`, which saves, so
  `climber.json` gained xp, so hero stats changed, so unrelated class-stat suites
  went red. Fixed at `_save_climber` rather than at each call site: the real
  autoload is in the tree, a bare `GameState.new()` never is, and a test that
  genuinely wants the disk passes an explicit path.

---

# RESUME HERE — 2026-08-04 (b)

**The game is now called ASHSPIRE.** Title screen + app name. Already canonical:
`data/towers/ashspire.tres` has been the tower's name all along.

**Branch `bot-fight-quality`. 148/148 green, tree clean.** Two commits worked the
whole resume queue.

## ▶ WHAT TO PLAY, AND WHAT TO JUDGE

**F5 → ASHSPIRE.** Four things are new and none has been touched by hands:

1. **LEVELS.** Kill things → XP → a magic circle blooms at your feet and the level
   number rises off your head. One full climb should land you at ~level 12.
   `godot ... --script tools/slice_test_progression.gd` PRINTS the whole economy
   if you want to argue with a number.
2. **THE ARCHIVIST**, a new desk just left of the lectern. Spend skill points on
   spells. Locked classes now show on the altar as "held by a guardian"; felling
   the floor-5 or floor-10 guardian banks a PICK you spend there.
3. **THE SHADOW SOUNDS** — the ones you called goofy. They were all mined from
   packs literally called *Cartoon Impacts* and *Cartoon & Animation*. Re-cut from
   "Transition Braam Slow Dark Creepy" and "Dark Industrial Ambience". **Listen and
   tell me if they are epic yet** — nobody has heard them.
4. **THE TOWNSFOLK TEACH NOW.** The Doorkeeper reads your climb back at you —
   floor, best, falls, level. That is the deleted AI-NPC stack's actual job, and it
   turned out to need four numbers and a token in a string, not a language model.

## ▶ THE MATHS, IN ONE TABLE

One authored growth rate; the depth curve is DERIVED from it, which is what makes
"proportionally" literally true rather than a claim.

| knob | value | |
|---|---|---|
| `GROWTH` | 1.22 | every level costs 22% more than the last |
| `LEVELS_PER_FLOOR` | 1.2 | the pace target |
| `depth_gain()` | **derived** `GROWTH^1.2` = 1.27 | each floor is worth 27% more than the one below |
| `MAX_LEVEL` | 30 | |

**The farm is dead by arithmetic, not by a ban.** One level costs 30 floor-1 bodies
at level 1, 268 at level 12, 1,312 at level 20, 7,856 at level 29 — and floor 1
only authors 22 bodies. Climbing instead holds a flat 1.2 levels per floor at ANY
depth, because floor value and level cost rise together by construction.

**Co-op:** Growth caps at the PARTY level (the lowest member's), frozen at tower
entry. Spell trees and unlocked classes are never touched. The tower is
deliberately NOT scaled to level — that makes the lower player a ghost.

## ▶ WHAT I DID **NOT** DO, AND WHY

1. **GEAR BALANCE — 17 of 19 pieces still beat the empty slot for free.** This is
   the one queue item I left. The queue itself calls it "a design call", and making
   seventeen pieces pay a cost would move every number in the 288-bout balance
   sweep on a build nobody has playtested. **Say go and it is an afternoon.**
2. **`SigilGuard` is still attached to nothing.** Wiring it re-opens the
   `guard_style` seam whose last disagreement cost a full session. Its header holds
   the 5-edit plan. Unchanged, deliberately.
3. **CRLF renormalise** — still wants your say-so (a ~476-file diff).
4. **Music licence provenance** — still unsettled. Still blocks anything public.
5. **The six `.mp3`** — still waiting on you to listen to the `.ogg`.
6. **Stormcaller 16-0** — partly defused rather than fixed: it is now a LATE
   UNLOCK, so it is a reward instead of a beginner trap, and its Growth row is
   deliberately denied FOCUS 4 (cooldown growth is exactly the axis that compounds
   its win rate). The raw matchup number is untouched.

## ⚠ ONE INSTRUMENT IS LYING AGAIN

**`python-tools/coop_smoketest.sh` prints NO VERDICT LINE.** This file used to
claim it does. Verified byte-identical on the stashed pre-change tree, so it is
**pre-existing and not from this work** — but it means co-op currently has no
green light of its own. The useful signal it still gives: `heroes=2 (peak 2)` on
both peers, which is how I know the re-tagged handshake did not break the arena.

**The teammate's body in the Antechamber is UNVERIFIED end-to-end** for that
reason. The code is ported and the room builds; nothing has proven two bodies
stand in it.

## ⚠ A TRAP THIS WORK WALKED INTO, WORTH KEEPING

**Two suites started testing the tester’s save file.** Hero stats now compose
level Growth, and `GameState` loads the real `user://climber.json` — whose NODE is
on the tree under `--script` even though the autoload IDENTIFIER is not. A test
run had banked 123 xp into the save, so heroes spawned at level 2 and the
class-stat assertions drifted. The red was the lesser half: **they would have gone
green again on a fresh save**, hiding any real class-table regression behind
whatever level the tester happened to be. Both suites now pin level 1, and a
positive counterpart asserts growth actually moves the stats.

---

# RESUME HERE — 2026-08-04 (paused by the maker)

> **THE MAKER PAUSED HERE AND ASKED FOR EVERYTHING OUTSTANDING TO BE RECORDED.**
> When they say **"resume"**, work the ordered queue in the
> `project_v2_resume_queue` memory. This file is its public twin — if the two ever
> disagree, the memory is the one that was written last.

**Branch `bot-fight-quality`, PUSHED to origin, 146/146 green, tree clean.**
Nothing is uncommitted and nothing is unpushed.

## ▶ THE QUEUE, WHEN THEY SAY RESUME

1. **The teammate's BODY does not appear in the Antechamber** — the one
   half-finished thing. Host and client both ROUTE there and the session is live,
   but peer heroes are spawned by `Arena._spawn_hero_net` through a
   `MultiplayerSpawner` + the `party_ready` handshake, and none of that machinery
   exists in `World.gd`. Port it; verify with `python-tools/coop_smoketest.sh`.
2. **Spell trees + levelling + hub NPCs** — designed in full, NOT built. Spec:
   `docs/superpowers/specs/2026-08-04-spell-trees-and-progression-design.md`.
   Build order in its §8; steps 1–2 are pure data + math and testable before any
   pixel is drawn. Three open questions in §9 need the maker.
3. **"Some of the VFX are goofy / weird slightly sounding"** — ⚠ ASK WHICH. 49
   spells and ~187 sounds is too wide to guess. My prior: the HOLY cues, which use
   a CC0 vibraphone as a stand-in and are the known-weakest mappings
   (`assets/audio/CREDITS.md` §2).
4. **The walk, part-open.** The swing leg does not bend at the knee. Feel call,
   judge at F5 — `CharacterRig.gd` is hand-tuned, do not retune blind.
5. Smaller, carried: `DestructibleTerrain` authority (latent), `SigilGuard` still
   attached to nothing, 17 of 19 gear pieces still beat the empty slot for free,
   Stormcaller 16-0, CRLF flip-flop, music licence provenance, and the six `.mp3`
   that can go once the maker has LISTENED to the new `.ogg`.

## ▶ WHAT THE LAST STRETCH CHANGED (after the phase table below)

- **Title: 10 buttons → 3.** ENTER THE TOWER · MULTIPLAYER · Credits. Class,
  loadout, spells and free play moved into the Antechamber, which already owned
  them. ENTER THE TOWER now lands in the ROOM, not straight in a fight — you
  spawn on the door, so it is still one press to descend.
- **The Antechamber is the front door**, with a new SPARRING RING (free play) and
  a co-op-only PARTY STONE.
- **Three feel fixes from live play:** sparring bot to Easy, `shake_scale`
  1.0 → 0.7, `STANCE_FACTOR` 0.052 → 0.034 ("make me stand upright").
- **The walk:** the capture harness never stepped physics, so the ground clamp was
  disabled and the instrument was lying; and `MAX_TRAIL_FACTOR` was authored at
  0.34 against a geometric ceiling of 0.222. Now derived.

---

## ▶ THE TOWER REDESIGN — 4.5 of 5 phases landed

Spec: **`docs/superpowers/specs/2026-08-04-tower-shape-and-feel-design.md`**.
All UNPLAYTESTED. 146/146 green, tree clean.

| phase | state |
|---|---|
| 1 · combat pacing + flagged bugs | ✅ |
| 2 · climb bands + checkpoints + party scaling | ✅ |
| 3 · PvP health/stocks + settings | ✅ |
| 5 · floor biomes + lighting | ✅ |
| 4 · title + **Antechamber** + music | **half** — title + music done, ROOM not built |

### ⚠ WHAT IS LEFT, AND WHY IT WAS NOT HALF-BUILT

**The walkable Antechamber.** Maker: *"practise and all that stuff you can do in a
room in the lobby"*. Design is spec §3.1 — a room you enter with your actual hero,
with four stations: **The Gate** (descend/resume), **The Armoury** (existing
Loadout/Outfitter UI), **The Sparring Ring** (absorbs Free Play + Watch Bots), and
**The Party Stone** (co-op only). `GameState.session_kind` (SOLO/LOCAL/ONLINE) is
set before arrival so one scene serves all three entrances.

It was not started rather than stubbed: a MENU wearing that name would ship the
wrong thing under the right label, and the room is the whole point of the ask.

**Bigger title art.** The `_Paper` backdrop already draws a tower in chalk. The
TOG "epic" register wants scale and depth, not a different drawing.

### THINGS THE PLAYTEST SHOULD ANSWER FIRST

1. **Do spells still chain?** `GLOBAL_CAST_LOCKOUT` is 0.35 s and cooldowns are
   +35% on quick/heavy. All three are live knobs on the **F1 Director**
   (`cd_mult_quick` / `cd_mult_heavy` / `cd_mult_ult`).
2. **Is floor 6 a wall?** Band 2 is new content and has never been fought.
3. **Do the biomes read?** Ten floors, ten palettes, exposure 0.68–1.18.
4. **Is a checkpoint loss too harsh?** Dying on floor 5 now costs floors 2–5.

### ⚠ A GAP I SHIPPED AND THEN CAUGHT, WORTH REMEMBERING

Phase 2 raised `TOTAL_FLOORS` to 10 — but `total_floors()` returns the AUTHORED
tower's size, and Ashspire authored 5. So the constant did nothing, every floor
mapped to checkpoint 1, and a wipe was a total reset: exactly the roguelite
behaviour that was rejected. **Every climb test passed**, because they test the
pure functions and never ask the tower how tall it is. Fixed in Phase 5 by
authoring all ten floors. Integration is where this class of bug lives.

---

# Earlier the same day — 2026-08-04 handoff

Branch `bot-fight-quality` (off `main`). **146/146 suites green, working tree clean.**
Everything below is committed.

## ▶ WHAT CHANGED ON 2026-08-04 (6 commits, all UNPLAYTESTED)

A cleanup pass over this file's own open list. Three were real bugs nobody had
pressed yet; two were the measuring tools lying again; one was dead weight.

| | before | after |
|---|---|---|
| classes that can COUNTER a bolt in a duel | 1 of 9 | **9 of 9** |
| co-op: breakable ledges | desynced collision geometry | host-authoritative |
| co-op: weapon pickup | could arm a different hero per screen | one finish line |
| `spell_below_floor` sweep rows | 23, ERROR, **deleted live spells** | **0** |
| result card | landed on the taunt + damage number | waits for a quiet screen |
| gear items that are unpickable | 2 | **0**, with an invariant |
| music bed (export payload) | 36.4 MB | **15.0 MB** |

1. **THE PARRY WAS UNREACHABLE IN EVERY DUEL.** `Hero.try_parry` was never
   *called* in hero-vs-hero — not gated, absent. A hero's bolt is a `Spell` and
   only `EnemyProjectile` ever offered the hook. It LOOKED fine because the parry
   window still negates the hit in `take_damage`; what never happened was the
   counter, the reward beat, or `note_deflect`. The Swordsaint was exempt (it
   sweeps the `deflectable_spell` group directly), which is why 1 class worked and
   hid it. **This is the one most likely to change how a fight feels.**
2. **Co-op: `BreakablePlatform` had no authority guard**, and `_break` disables the
   collider — so a ledge was solid ground on one screen and open air on the other,
   with both drawing the hero at the same coordinates. Live on every generated
   floor. `WeaponPickup` had the same shape as the crate bug: a photo finish armed
   a different hero on each screen, permanently. Both now on the crate's pattern.
3. **The floor probe was inventing errors AND perturbing the fight.** Past the
   ±900 slab there is no floor to be below, but the predicate was a bare
   y-comparison — so every overshooting bolt filed an ERROR *and got
   `queue_free`d mid-flight*. The body-side check had already learned this and the
   fix was never back-ported twenty lines. `damage_outlier` was also reading a
   `max_hp` snapshot frozen before gear/mode ever set the real pool.
4. **The result card** now waits on `_screen_is_quiet()` (taunt latch +
   `DamageNumber`/`ElementFx` counts) with a 2.5 s ceiling, instead of a flat
   0.55 s that could not have outlasted a 1.9 s taunt bubble.
5. **Two gear pieces were strictly dominated** — `hat` under `helmet`, `sword`
   under `hammer` — i.e. unpickable, not weak. Both now pay a cost.
   `Loadout.gd`'s claim that "dagger sheds damage for speed" was **false** (its bag
   is pure upside) and is the sentence this file was repeating.
6. **The last executable LLM plumbing is gone** (`build_run_fact`,
   `ingest_run_fact`, `apply_run_to_hub_npcs` and friends). All already dead at
   runtime — `World._ready` stopped calling it and `NPC.gd` lost the interface.

**Every new assertion was verified by breaking the fix and watching it go red.**
Nothing here has been touched by hands — see THE STANDING JUDGEMENT below.

## ▶ WHAT TO PLAY, AND WHAT TO LOOK AT

**F5 → title screen.** The two things most worth your eyes:

1. **THE LEGS.** They stand straight now, everywhere — hero, enemies, bosses, thralls,
   townspeople. `Enemy` DERIVES its leg constants from `CharacterRig`, so it is one
   edit and not a sweep. To look closely without squinting at a clip:
   `godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/rig_legs_capture.gd`
   (GUI binary — headless writes blank PNGs). Renders standing / walking / enemy
   presets LARGE against a ruled floor.
2. **KNOCKBACK FEELS WEAKER, AND THAT IS THE FIX.** See the warning below.

`python python-tools/make_clip.py --a 6 --b 5` → a clip that now opens on the VS card.

## ⚠ TWO THINGS THAT WILL FEEL WRONG BEFORE THEY FEEL RIGHT

- **Hero knockback is ~7x weaker.** It was being INTEGRATED as an acceleration: 6.0x
  the stated impulse at normal speed and **32x while hitstop held `time_scale` at
  0.05**, so the same shot sent a body a different distance every time depending on
  whether it triggered hitstop. `Enemy` and `Boss` always did it correctly — Hero was
  the outlier. Travel is now identical with and without hitstop. If it feels limp,
  the dial is `TuningConfig.knockback_mult` (live, F1 Director) and it now moves Hero
  and Enemy TOGETHER for the first time. That dial was already cut 1.6 -> 1.0 in a
  'knockback is too much' pass — that pass was treating this bug.
- **Ring-out mode has its own 6.0 gain** (`Hero.RINGOUT_LAUNCH_GAIN`, mirrored on
  `Enemy`) because the honest shove took ring-outs from 32/144 bouts to 0/144. Applied
  at the call site so the curve `slice_test_ringout` pins stays untouched.

## WHAT CHANGED THIS SESSION (11 commits)

| | before | after |
|---|---|---|
| knee jut at rest | 8.3% of figure height | **1.6%** |
| bot deflects / 18 duels | 3-4, in 2-3 matches | **18, in 7 matches** |
| sim outcomes | 0 kill / 15 points / 3 draw | **18 kill / 0 / 0** |
| sweep anomalies | 118 (61 error) | **6 (0 error)** |
| difficulty dial (tier 0 v 3) | 61/39 | **89/11** |
| clip length | 2.4 s, 44% a still frame | **4.6 s, opens on the VS card** |

Root causes, each measured not reasoned:

- **Legs.** Two causes that both sound negligible written down, because a two-bone IK
  takes the SQUARE ROOT of a length shortfall. (a) the body stood 3% shorter than its
  own leg bones on purpose; (b) the idle breath was SYMMETRIC, so half of every cycle
  pressed the hip 3% BELOW standing and the ground-locked feet forced it into the
  knees. Also fixed earlier: `draw_figure` drew the shin to the RAW foot while the IK
  had CLAMPED the reach, so the drawn leg reached 1.449x its own bones on 28-43% of
  moving frames.
- **Bots never parried.** `guard_style` was documented with OPPOSITE meanings on the
  two sides of the seam ('0 = press window' on Hero, '0 = BLADE ring' in BotBrain), so
  7 of 9 classes pressed the guard 0.374 s early into a window that opens immediately
  and lasts 0.16 s. The body now publishes `guard_lead` / `guard_tolerance` in seconds.
- **The sim could never report a kill.** `_die()` heals to full outside a run, so the
  poll read a body resurrected microseconds earlier. One bout burned 2319 damage across
  205 max HP and scored a DRAW. Every balance number it ever printed ranked corpses.
- **Two red suites** were CRLF line endings, not regressions. Shipped code was correct.

## STILL OPEN — ranked

1. **PLAYTEST.** Nothing here has been touched by hands. Everything is measured, which
   this file's own standing judgement calls the weaker evidence. **Start with a duel
   and try to parry a bolt** — that path has never once worked for 8 of the 9
   classes, so it is the change most likely to feel different in your hands.
2. **BALANCE IS REAL AND UNTOUCHED.** 288 bouts on the honest harness: Cleric 91%,
   Warlock 84% ... Brawler 22%, Swordsaint 9%. The two LIFESTEAL classes have the two
   LOWEST damage kits and the two highest win rates — `bolt_heal` is the undercosted
   stat. A design call, not a number to pick blind. (The bot SPACING half was fixed:
   four classes stood outside their own attack range.)
3. **Clip strobe.** Full-screen white/yellow blow-out frames; measured mean luminance
   68 -> 146 -> 68 between consecutive 30 fps frames, six such jumps in the first
   twenty. `ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND = 2` exists and LOCAL rings
   are counted SEPARATELY — check whether that is the hole before retuning anything.
4. ~~Result card lands on live spectacle~~ **FIXED 2026-08-04** — see above.
5. **Lag is unresolved.** Median 1.52 ms (660 fps), worst 13.99 ms over 11.6k frames,
   and every hitch reported 'built that frame: nothing'. An earlier 40 ms outlier was
   probably first-use shader compile. If it stutters in your hands, say WHEN.
6. **CRLF flip-flop.** `core.autocrlf=true`, no `.gitattributes`, so git-written files
   are CRLF and agent-written ones are LF — the next branch switch can redden a
   different suite. Durable fix is `*.gd text eol=lf` + a renormalise: a ~476-file
   diff, wants its own commit and your say-so.
7. ~~Harness noise: `spell_below_floor`, `damage_outlier`~~ **FIXED 2026-08-04.**
   A 3-seed sweep now reports 17 anomalies, **0 error**, zero `spell_below_floor`.
   ⚠ Still true: **`SigilGuard` is attached to no live body anywhere** — the mage's
   magic-circle catch is dead code behind a green suite. NOT deleted (magic circles
   are the signature) and NOT wired, because wiring it re-opens the `guard_style`
   seam whose last disagreement cost a full session. Both files now say so out loud
   with the 5-edit plan; `SigilGuard.gd`'s header is the place to start.
   ⚠ Also still true: `damage_outlier` fires against the SIM's tower-hp pool
   (78–145), while `BotMatch` plays at `190 x CLASS_VITALITY` and duels at 260. The
   stale-snapshot bug is fixed; the CALIBRATION mismatch is a deliberate
   non-change — putting the sim on the shipping pool moves every balance number and
   wants your say-so.
> **Read order for a cold start:** this file → `docs/PLAY-TONIGHT.md` (what to play
> and what is knowingly wrong) → `docs/THE-TOWER-mobile-plan.md` (the design + the
> gap analysis) → `docs/audit-fun-and-competitors.md` (the ranked findings).

---

## WHAT THIS GAME IS NOW

**THE TOWER** — a 2-player mobile co-op arena brawler. Stick figures with absurd
magic fight escalating waves on each floor of a tower until a guardian spawns.
Friendly fire is always on and is the social engine. Local wifi. The spec is
`docs/THE-TOWER-mobile-plan.md`.

**Boot: F5 → the title screen.** CLIMB · Free Play · Loadout · Host/Join · Watch
Bots · Credits. **F1 in game opens the DIRECTOR** (jump/re-roll floors, summon any
boss with any modifiers, switch class live, grant any spell, LOW quality, slow-mo,
frame-step, **F9 flags a moment**).

---

## MAKER RULINGS THAT OVERRIDE THE SPEC DOC

These were decided in play and beat anything written earlier:

- **Death = ghost until a teammate revives you; all dead = game over.** Not
  drop-a-floor. Policy dials live in `scripts/combat/DeathRules.gd` and nowhere else.
- **Keep 9 classes and 8 mob types.** The spec's "4 classes / 3 mob types" is
  overruled. Do not propose cutting them again.
- **5 floors, seeded-randomised** rather than the spec's 15 + procedural.
- **The town is the front door** — start there, or press CLIMB and skip it entirely.
- **The AI/LLM/NPC-memory stack is DELETED** (43 files, −2,884 lines). Townspeople
  speak via `Bark` + `Gibberish`. Do not resurrect it.
- **Floor duration:** the spec's "4–7 minutes per floor" has the wrong unit.
  Competitor data says the *climb* is the right target. A climb is ~6:30 and in
  window. `tools/floor_sim.gd` now judges the climb, not the floor.

---

## THE STANDING JUDGEMENT — repeat it, do not soften it

**Every feel number in this stack is reasoning, not feel.** The maker's one-line
complaints from ~40 minutes of live play found more real bugs than the entire
134-suite test run ever has. A sample from that one session, all of which had been
green:

- Bots had **never dodged, guarded or jumped** — a null-returning helper killed the
  whole reflex layer.
- Bot fighters were **literally immortal** — three stacked causes, incl. `Hero._die()`
  running `hp = max_hp` in the same call as the fatal hit.
- The rig was **dropping a quarter of its steps** at 60 Hz (gait ran per-frame; 29
  plants vs 36 at 120 Hz), which is what "walking weird on his legs" was.
- All seven of Hero's Q spells had **no `caster_node`**, so they self-damaged under
  friendly fire *and* were silently inert in the whole reaction system.
- **Spell handoff had never worked once** — it asked heroes for members that exist
  nowhere, and `bool(null)` aborts the enclosing function.
- The cast circle drew **the caster's element, not the spell's**.
- `blink` read a hard-Y-zeroed vector, so it could only go left/right.
- Exiting Free Play dumped you in a **different game's parked village**.

**Playtest beats reasoning every time. Ship things the maker can press.**

---

## TRAPS THAT COST REAL TIME (do not rediscover)

- **`failed += _test_x()` IS BANNED.** A dead property read aborts the enclosing
  function and returns the type's zero, which that idiom reads as "no failures" — it
  silently disabled 64 suites once. Accumulate failures on a **member** and record a
  per-test **completion sentinel** so an aborted test fails BY ABSENCE.
  `tools/slice_test_loadout.gd` is the reference. Also check for `quit(0)` after
  `quit(1)` — one suite always exited 0, hiding its own failures.
- **An invariant that is trivially true of an empty result is not an invariant.**
  Three bugs deleted an entire ledge skyline while the geometry suite stayed green.
  Assert a minimum occurrence rate.
- **A test stub declaring members the shipped class lacks is a fixture more generous
  than reality.** Assert against real scenes.
- **`set()` on an undeclared property is a SILENT no-op.** A spectacle must declare
  `element_id`, `spell_tier`, `caster_node`, `target_group`, `_target_group`.
- **A spectacle built without a caster is silently inert in the reaction system.**
- **Spectacles park at the arena origin** — `global_position` is (0,0), NOT where the
  effect is.
- **`take_damage` ships two signatures** — always route through `SpellTargets.hurt()`.
- **Autoloads are NOT global identifiers under `--script`** (the *nodes* ARE on the
  tree — use a tree lookup). Naming one inside a **static** function breaks the whole
  compile chain and reports as an unrelated missing method.
- **`--headless --import` REWRITES `project.godot`** and silently deletes
  `physics_ticks_per_second`, `rendering_method` and `rendering_method.mobile`.
  `slice_test_mobile_config` guards it. Check after importing.
- **`Performance.TIME_PROCESS` excludes `_draw`.** 40k draw primitives moved it
  0.0000 ms while wall-clock moved 9.2 ms. Every perf figure in `docs/mobile-export.md`
  is process+physics only; draw cost is *on top*.
- **Wall-clock here cannot measure sub-millisecond work** — non-monotonic by 20×.
  Assert deterministic work counters, not milliseconds.
- Group drift: `"hero"` (tower) vs `"player"` (old hub) vs `"mortal"` (faction-blind
  fighters). **Crates are deliberately NOT in `mortal`** — they have their own scan,
  and being in both made them take every hit twice.
- Captures need the **GUI binary**; `--headless` renders blank PNGs while reporting
  success.

---

## HOW TO VERIFY

```
python python-tools/run_all_tests.py --jobs 8        # 134 suites, ~75s
python-tools/coop_smoketest.sh                       # 2-process, prints VERDICT
python python-tools/run_capture.py <name>            # GUI binary; docs/capture-tools.md indexes ~69
python python-tools/make_clip.py --a 6 --b 5         # bot-vs-bot clip
```
A sweep taken while anything else is writing **lies** — re-run before concluding.

---

## OPEN / NEXT

1. **PLAYTEST.** Nothing since the last round has been touched by hands.
2. ~~ffmpeg needs a fresh shell~~ **CONFIRMED ON PATH 2026-08-04.** `make_clip.py`
   auto-detects it and will emit MP4. Also unblocked `compress_music.py`, which had
   never run: the six tracks are now **36.4 MB -> 15.0 MB Ogg Vorbis (-21.4 MB)**.
   ⚠ **`assets/audio/music/` is GITIGNORED** — the MP3s were never tracked, so this
   is a local/export-only change with nothing committed, and the "45 MB payload" in
   `assets/audio/CREDITS.md` means the EXPORTED build, not the repo.
   ⚠ **LISTEN BEFORE DELETING THE MP3s.** Lossy-on-lossy; `Music.gd` already
   prefers the `.ogg`. If they hold up, delete the six `.mp3` and the saving is
   real. If not, delete the six `.ogg` and the change is gone completely.
   Originals also backed up to the gitignored `audio-source/raw/music-originals/`.
3. **No Android build has ever been made.** Needs export templates, JDK 17, SDK,
   keystore — all human steps in `docs/mobile-export.md`. Delete the `MCPRuntime`
   autoload before any export; `tools/release_gate_dev_bridge.gd` fails until you do.
4. **Perf: ~30 ms CPU at the 8-effect ceiling on desktop**, est. 90–150 ms on a
   3-year-old mid-range Android — and that excludes `_draw`. The 25-entity crowd is
   NOT the problem; spell effects are. Partially addressed, not closed.
5. **Music has no recorded licence provenance.** Six tracks, nothing in the repo says
   where they came from. Settle before anything public. Pepper Sound Pack attribution
   IS on the credits screen.
6. ~~Dead LLM plumbing in `GameState.gd`~~ **DELETED 2026-08-04**, with the stale
   "needs a local Ollama" comments rewritten. `HUB_SCENE`/`visit_hub()` kept.
7. **Balance.** ~~head/body gear are pure upside~~ **half-fixed 2026-08-04**: the two
   *unpickable* items now pay a cost and an invariant pins it. Still open, and a
   design call: **17 of 19 pieces still beat the EMPTY slot for free**, so "equip
   something" is a checklist even though "equip which" is now a real choice.
   ⚠ **The Brawler dispute is RESOLVED — 22% is the trustworthy number.** 14%
   (`BotMatch.gd:131`, `docs/PLAY-TONIGHT.md:78`) predates `812ca94`, the commit
   that made the harness able to report a kill at all, so it was computed from
   bodies `Hero._die()` had already healed to full. Both citations should be
   corrected. Caveat: the two harnesses never scored the same game anyway — only
   `BotMatch` has ring-outs, `CLASS_VITALITY` and draws in the denominator, so its
   ruleset is the one that matches what a player sees.
8. **Co-op gaps.** ~~`BreakablePlatform` has no authority guard~~ **FIXED
   2026-08-04**, along with `WeaponPickup`'s double-award. Still open, ranked:
   **(a)** `BossDropWatcher` places the guardian drop at `boss.global_position` on
   BOTH peers, but a boss's position is synced with lag and `Net.KEY_TOLERANCE` is
   only 6 px — so the host awards a drop the client's `_find_at` cannot find, and
   the reward silently never applies there. Fails in the direction that still looks
   correct. **(b)** Herald's howl lives in `_tick`, which is host-only — the client
   gets the room-wide speed-up with no audible or visible cause. `EliteQuickened` is
   the pattern to copy (ride synced state) or `broadcast_boss_fx` (host decides,
   every peer rebuilds). **(c)** Keen reads `_evade_cd`, which is not in the puppet
   sync set, so its bark is silent on a client. **(d)** `DestructibleTerrain` /
   `DestructibleFloor` have the same missing guard but are LATENT — nothing in the
   tower builds one yet. Terrain also needs `shattered` authoritative separately,
   because it shatters on cell count, not only hp. Everything is
   **loopback-verified only — never two real machines.**
9. **Nothing has ever touched a touchscreen.** Every touch constant is a declared guess.
10. **Nobody has heard the audio mix.** 248 keys mined by filename/duration. Clips are
    silent (PNG frame-grabs carry no audio), so the mix can only be judged in-game.

---

## FILE MAP (the bits that matter)

`Hero.gd` combat body · `CharacterRig.gd` the two-spring rig (**hand-tuned, do not
"improve"**) · `SpellCaster.gd` data→spectacle dispatcher · `SpellLibrary.gd` 38-spell
catalog + `CLASS_KITS`/`SLOT_ROLES` · `MagicCircle.gd`/`SpellSigil.gd` the summoning
circles (**the maker's favourite thing**) · `Encounter.gd` waves/elites/entity cap ·
`scripts/tower/FloorGen.gd` seeded floor generator · `BossRoster.gd` + `bossmods/` ·
`elitemods/` · `Net.gd` co-op spine · `GameState.gd` run spine + climb ·
`StageLayers.gd` the z-order + visual grammar · `DeathRules.gd` the two death dials ·
`World.gd` the town · `Lobby.gd` title · `tools/director/` the audit tool.
