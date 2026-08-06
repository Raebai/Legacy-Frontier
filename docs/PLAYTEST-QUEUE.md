# LIVE PLAYTEST QUEUE — 2026-08-06 (wave 5)

All seven of wave 4's OPEN asks are **actioned**, and so is the one thing wave 5
left open. Branch `bot-fight-quality`, **155/155 green**, tree clean.
**None of it has been played by hand.**

---

## ⚠ 0. FOUR ABILITIES WERE SECRETLY PUNCHING YOU — read this one first

Not on anybody's list; found by probing. `Hero._ready` connects `rig.hit_frame`
to the melee handler once, the rig emits that signal for **every** punch or kick
animation, and the handler never asked whether a swing had been declared. So four
things that play a strike pose for how it *looks* each landed an extra,
undeclared, full-damage melee hit — none paying melee's cooldown, none documented:

    Brawler uppercut       [18, 16]   the 16 is a free swing
    Brawler fire punch     [30, 16]
    Swordsaint unsheathe   [72, 37]   a THIRD of the move
    Thunderclap — a SPELL that also punched

**The fix is damage-neutral where it mattered.** You are near the bottom of the
roster on the Brawler and at exactly 50% on the Swordsaint; a bookkeeping fix
must not silently nerf either. All three now add `_melee_damage` explicitly and
every total is unchanged — 16 / 34 / 46 / 19 / 109. Thunderclap is *not*
compensated: a spell should deal its authored damage.

**What to feel for:** nothing should hit softer. If the Brawler or Swordsaint
suddenly feels weak, this is the first place to look.

---

## ⚠ 0b. AND THE LAST FOUR UNDODGEABLE ATTACKS NOW TELL

The frost cone, uppercut, fire punch and ground slam all resolved *synchronously
with the button* — while each was already playing a wind-up animation. The
picture said "winding up" and the damage had already happened.

**`Hero.ABILITY_TELL_LEAD` = 0.10 s is the one knob, and this is the change in
the whole wave most likely to need reverting.** It is the only one that alters
how a button FEELS. Set it to `0.0` and all four resolve on the press again,
tells intact. One line.

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

### ⚠ I PREDICTED THE CONTACT CLASSES WOULD DROP. THEY DID NOT — RE-MEASURED

Before this wave the bottom three were Shadowblade 27%, Brawler 33% and
Juggernaut 33% — the three classes whose attacks nobody could see. Making those
attacks dodgeable and parryable should have pushed them further down. A second
288-bout sweep against the changed code says otherwise:

    class          before     after    delta   sigma
    CRYOMANCER    25 (39%)  18 (28%)     -7     1.3
    STORMCALLER   47 (73%)  43 (67%)     -4     0.8
    BRAWLER       21 (33%)  19 (30%)     -2     0.4
    WARLOCK       48 (75%)  47 (73%)     -1     0.2
    SWORDSAINT    32 (50%)  32 (50%)     +0     0.0
    ARCANIST      29 (45%)  30 (47%)     +1     0.2
    SHADOWBLADE   17 (27%)  18 (28%)     +1     0.2
    CLERIC        48 (75%)  50 (78%)     +2     0.4
    JUGGERNAUT    21 (33%)  31 (48%)    +10     1.8

**NOTHING REACHES 2σ, so read none of it as settled.** The honest summary is
that the roster shape barely moved and the top three are unchanged.

### ⚠ AND A THIRD SWEEP RETRACTED MY EXPLANATION OF THE SECOND

    class          wave4     wave5    wave5b     5b-5   sigma
    CLERIC        48 (75%)  50 (78%)  52 (81%)     +2     0.4
    STORMCALLER   47 (73%)  43 (67%)  44 (69%)     +1     0.2
    WARLOCK       48 (75%)  47 (73%)  40 (62%)     -7     1.3
    SWORDSAINT    32 (50%)  32 (50%)  38 (59%)     +6     1.1
    ARCANIST      29 (45%)  30 (47%)  26 (41%)     -4     0.7
    BRAWLER       21 (33%)  19 (30%)  25 (39%)     +6     1.1
    JUGGERNAUT    21 (33%)  31 (48%)  22 (34%)     -9     1.6
    SHADOWBLADE   17 (27%)  18 (28%)  21 (33%)     +3     0.6
    CRYOMANCER    25 (39%)  18 (28%)  20 (31%)     +2     0.4

    roster spread (top-bottom):  48 pts -> 50 -> 50

**I said the Juggernaut's +15 in wave 5 was probably real and offered a
mechanism for it — that it publishes a `guard_tolerance` of 0.200 against
everyone else's 0.080, so it gains most from melee becoming parryable. The next
288 bouts took it straight back to 34%. That was noise, and my explanation for
it was a story fitted to one sample.** Nothing at 1.8σ should have been narrated
that confidently, and this is the second time this project has caught a
confident reading of an under-powered measurement.

Two things the data does support, weakly:

- **The Brawler and the Swordsaint did not get weaker** (+6 each) across the
  wave that made their hidden melee coupling explicit. That is the one thing the
  damage-neutral fix needed to show, and it shows it.
- **The Cryomancer is low across two independent samples now** — 39% → 28% →
  31%. Two agreeing samples is the most persistent signal in the whole table,
  and the frost cone is the one primary that gained nothing defensively while
  everything around it did. Still not 2σ. Still your eyes, not the number.

Also confirmed at 4× sample: **the Swordsaint fix worked** — 19%, then 25%,
now **50%**, and unmoved by this wave.

### THE BOT STUTTER FIX HAS AN HONEST REGRESSION
Reversals per second, with a control run for every claim:

    worst-case alternating foe   60.00 -> 4.00   (dwell off / on)
    mean, live threat on board    1.18 -> 0.85   (old tie-break / new)
    worst pairing, live threat    1.58 -> 2.92   <-- WORSE

Average chatter is down 28%; one pairing under a sweeping hazard got worse
and is still under the ceiling. If a bot still paces, that number is why.

---

## ▶ WHAT IS STILL OPEN

- **Per-class Tier 3 drops** — five new ult-weight spells. Deliberately NOT
  started: the class-identity ruling forbids making the difference a tint, so
  each needs its own rule-bending spectacle, and that is design work with your
  taste in it. **It wants a brainstorm, not a build.**
- **Stick customisation** —
  `docs/superpowers/specs/2026-08-05-stick-customisation.md`. Re-read this wave:
  its own "cheapest real win" (§3, dialogue in the speaker's colour) **already
  shipped in wave 4** for the duel. What is left — a hair slot, non-robe
  clothing, accessories, a sheathed katana — all needs **PixelLab art**, which
  costs your API credits and is your aesthetic call. Not something to ship
  without you.
- **The Swordsaint's unsheathe cut has no anticipatory tell**, deliberately. It
  is a *reactive* punish that fires when you spend a banked guard; a wind-up on
  a counter-attack is arguably wrong. Say if you want one anyway.
- The nova stays instant — its own header says so and you did not name it.

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
