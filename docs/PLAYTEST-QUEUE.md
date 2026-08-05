# LIVE PLAYTEST QUEUE — 2026-08-06 (wave 5)

All seven of wave 4's OPEN asks are **actioned**. Branch `bot-fight-quality`,
**155/155 green**, tree clean. **None of it has been played by hand.**

> Wave 4's ask-list is preserved at the bottom for the record. The measurements
> below are all from headless probes and sweeps — your eyes still decide.

---

## ▶ WHAT TO PLAY, AND WHAT TO LOOK FOR

### 1. WATCH BOTS — the camera should now flinch
Every `Juice` camera call in a versus mode was a **silent no-op**: the group
held two disabled, invisible hero cameras and the camera you were looking
through was in no group at all. The `ClipDirector` is now the operator, so
hits shake, kills punch, ults pull back. The shot also stopped being smoothed
**twice** (the director's own lerp plus Godot's built-in), which is what made
it trail a moving fight.

### 2. WATCH A DEATH
The corpse was not sinking through the floor — it was **pancaked onto** it.
The prone sprawl drove the rig's origin 1.6 px underground and the joint clamp
then pinned three of seven joints to one line, with the head half buried.
Measured, settled corpse, lowest **drawn** edge below the floor:
**+2.19 px → 0.00**.

### 3. FIGHT A BRAWLER, A JUGGERNAUT OR A SWORDSAINT
`Hero` published **no `Telegraph` at all**, so the three contact classes
generated zero threat descriptors against each other — the dodge ladder was
never entered and the parry rung under it never reached. Swings now publish
their real 0.077 s window, and the parry band collapses onto a tell shorter
than the band (it could never be satisfied by arithmetic before). **This is
the change most likely to feel different in your hands**, and the one most
likely to be wrong in a way only playing will show.

### 4. THROW SOMEBODY INTO A WALL WITH A SPELL
Five of eight spectacles shoved *below* `SlamPhysics.MIN_SLAM_SPEED`, which
silently deleted the crater, the wall break and the shake from those spells.
`could not crack a wall: 5 of 8 → 0 of 8`, and nothing reaches the 360 you
previously called too much.

### 5. WATCH THE FLOOR AFTER SOMETHING BREAKS
The "crack in the air" was two real placement bugs (a slam marked the body's
centre, which is mid-air against a wall; a breakable platform marked its own
floating position). The "weird circular cracks" was a `draw_circle` chip with
five even spokes — a compass rose. Both fixed.

---

## ⚠ THREE THINGS I MEASURED THAT YOU SHOULD ARGUE WITH

### THE WARLOCK DOES NOT NEED A BUFF — 288 bouts say so
> *"warlock also needs a buff it got destroyed by the cleric"*

Run at **n=64 per class** (4× the old sweep, so the noise band halves to ~±6):

    CLERIC 75%  ·  WARLOCK 75%  ·  STORMCALLER 73%
    SWORDSAINT 50%  ·  ARCANIST 45%  ·  CRYOMANCER 39%
    BRAWLER 33%  ·  JUGGERNAUT 33%  ·  SHADOWBLADE 27%

And in **the exact matchup you watched**, `WARLOCK vs CLERIC` is **5-3 to the
Warlock (62%)**. It is joint-top of the roster. The bout you saw is the 38%.
Nothing was changed. Say the word and I will.

### THE REAL BALANCE PROBLEM IS THE CONTACT CLASSES
The bottom three — Shadowblade 27%, Brawler 33%, Juggernaut 33% — are the
three classes whose attacks nobody could see. **And I have just made those
attacks dodgeable and parryable**, which points them further down. A re-run
sweep is in this session's report; treat any contact-class buff as waiting on
your eyes rather than on the number.

Also confirmed at 4× sample: **the Swordsaint fix worked** — 19%, then 25%,
now **50%**.

### THE BOT STUTTER FIX HAS AN HONEST REGRESSION
Reversals per second, with a control run for every claim:

    worst-case alternating foe   60.00 -> 4.00   (dwell off / on)
    mean, live threat on board    1.18 -> 0.85   (old tie-break / new)
    worst pairing, live threat    1.58 -> 2.92   <-- WORSE

Average chatter is down 28%; one pairing under a sweeping hazard got worse
and is still under the ceiling. If a bot still paces, that number is why.

---

## ▶ WHAT IS STILL OPEN

- **Four hero attacks remain genuinely untelegraphed** — the frost cone,
  the uppercut, the fire punch and the ground slam all deal damage
  **synchronously on the press**. There is no honest way to give a bot a
  window there without deferring the damage, which changes how the button
  feels, and that is a playtest decision, not a reasoning one. The nova is
  deliberately instant and its header says so.
- **Per-class Tier 3 drops** — five new ult-weight spells, unstarted, wants a
  brainstorm first (see the 2026-08-05 (e) section of `NEXT-SESSION.md`).
- `docs/superpowers/specs/2026-08-05-stick-customisation.md` — fully specced,
  unbuilt.

---

## ✅ WAVE 4's ASK-LIST, for the record

1. Destruction leaves marks that read as bugs — **done**
2. The camera does not follow the fight — **done**
3. Bodies die and glitch into the floor — **done**
4. Bots oscillate — **done**
5. Spells do not feel tangible — **done**
6. Make it cinematic, make the bots smarter — **done** (the telegraph gap
   named as "THE BIGGEST UNFIXED THING" was the cause; it is closed)
7. Warlock buff — **measured and declined**, see above

## HOW TO VERIFY

```
python python-tools/run_all_tests.py --jobs 6      # 155 suites, ~104s
godot --headless --path godot-project --script tools/rig_death_floor_probe.gd
godot --headless --path godot-project --script tools/spell_push_probe.gd
godot --headless --path godot-project --script tools/botmatch_sim.gd -- \
  --roundrobin=1 --repeat=8 --round=22 --hp=190 --wall=70   # ~50 min
```
After any `--headless --import`, CHECK `project.godot` still has four keys:
`theme/custom`, `physics_ticks_per_second`, and both `rendering_method`s.

## TRAPS THIS WAVE ADDED

- **A GDScript lambda captures by VALUE**, so a counter incremented inside one
  is not reliably the same counter next call. Nearly put the compass rose back.
- **A `SceneTree` script's `_init` runs before `root` exists.** Two of four
  tests in a new suite passed against an empty world. The fix is an assertion
  that something *else* IS seen in the same call.
- **Naming a class in source makes the compiler resolve it**, and a script that
  reaches for an autoload cannot be resolved while a `--script` main loop is
  still compiling. Read the constant off the loaded script instead.
- **A ceiling derived from the fix is not a test.** The clean-board arm of the
  new steer suite reported identical numbers with the fix on and off; only a
  deliberately hostile input, and a control run, showed it had teeth.
