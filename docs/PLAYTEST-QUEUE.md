# ▶ 2026-08-11 — WAVE 7: ONE ASK, ACTIONED

> *"they start behind the crate then break the crate and walk into them"* →
> *"remove the crates or make them start on the platforms above"*

`STAGE_COVER` is empty (emptied, not deleted). Spawns 440/1000 vs blocks 470/1180, and
the keep-out only ever guaranteed 54 px — "not overlapping", not "out of the way".

⚠ **AND THE MODE THIS FILE TELLS YOU TO PLAY WAS CRASHING.** `VersusArena._build_terrain`
threw on every bout of every mode using the duel stage for about a week, and **166/166
was green over it** — three suites and the runner itself all failed to notice. Fixed;
the runner now fails any suite that emits a runtime `SCRIPT ERROR`, which caught four
more vacuous suites. **167/167.** Full account in `docs/NEXT-SESSION.md`.

---

# ▶ THE WAVE-6 QUEUE IS EMPTY — 2026-08-07

All ten wave-6 asks below are **actioned**, plus sixteen more spoken during the same
session. **Nothing below this line was ever played** — see the wave-7 block above for
why the headline test number could not have told you that.

Two asks were answered by DECLINING to do the obvious thing, and both are worth
knowing before re-opening them:

* **"cooldowns should be DERIVED from damage/usefulness"** — not built as a
  derivation. `SpellTier.of` derives the SHELF from the cooldown, so deriving the
  cooldown from damage makes damage a transitive shelf input, and eleven spells deal
  zero damage. Built as a BUDGET that fails the build instead
  (`slice_test_spell_budget`). It immediately caught four real outliers.
* **"I havent seen many ults"** — I blamed the channel gate and was WRONG. Counted
  with real bodies: 0 of 242 channelled casts refused. The brain asks for its ult as
  often as anything else. The likeliest remaining cause is that ults were not legible
  AS ults, which the new on-cast banner fixes.

One ask was left deliberately undone: **the bot melee swing still has no spacing
dial** (2.85/s, 45% of a Brawler's actions). The body gates real damage at `melee_cd`,
so a brain-side floor cuts melee DPS on the two weakest classes. It wants a sweep.

---

# ▶ LIVE ASK-LIST — 2026-08-07, WAVE 6 (TEN ASKS, ALL UNSTARTED)

Spoken during a live playtest, verbatim intent preserved. **Nothing below is built.**
Everything above this block IS built and pushed (`ad229d0`, 158/158 green).

### 1. DEFLECT SHOULD RETURN THE SPELL ALONG THE DEFLECT ANGLE
> *"remember deflect should send the spell back out from the deflect angle as well"*

Some things already reflect, but the RETURN DIRECTION is the ask. Today a caught
projectile goes back at whoever threw it (`BoulderHurl.reflect` — "you catch it and
send it back at whoever threw it", `RiftDagger.reflect`, `EnemyProjectile._reflected`).
The maker wants the guard's own ANGLE to decide where it goes, so a parry is an aim
decision rather than an automatic return-to-sender. Start at `SpellDeflect.resolve`
and the two `reflect()` implementations; the angle source is the defender's
`_aim_dir` / guard facing at the moment of the parry.

### 2. BOT FIGHTS START INSIDE THE BOXES
> *"when bot fight happen they start within the boxes which is a wierd bug as wel"*

Sounds like a real spawn bug, not feel — **do this one first**. Fighters are placed at
`BotMatch.FLOOR_CENTRE_X ± SPAWN_SPREAD` (720 ± 280) and the crates come from
`layout.crate_positions` via `FloorBuilder.build_props`. Nothing reconciles the two,
so a crate authored near a spawn point overlaps the fighter.

### 3. THE BOTS SPAM — cooldowns feel too low, want it more interactive
> *"the bot fights the cool downs are a little too low I think they are just spaming
> spells I want to mae it more interactive as well"*

⚠ **ATTEMPTED AND REVERTED — read this before retrying.** The lever is NOT the spells'
own cooldowns (those are the player's numbers too; slowing them nerfs every class in
the tower to fix a spectating problem). It is the bot's self-imposed rhythm:
`BotBrain.CAST_LATCH` (0.55), `ABILITY_SPACING` (0.80), `FIRE_SPACING` (0.42),
`BREATHE_CHANCE/MIN/MAX`.

Raising all four **fails `slice6_test_bot_brain`**, which asserts the bot lands
**≥12 casts** across a neutral window; the slowed bot got 10, and it stayed at 10
across two backoff attempts — so the guard binds harder than the dials move and
something else (probably the breathe roll) dominates. **That guard encodes "a bot
must not go quiet" and the maker is asking for exactly fewer casts, so loosening it
is a JUDGEMENT CALL, not a test-fixing chore.** Decide the threshold with the game
open; do not push numbers blind.

### 4. SWORDSAINT — the curve is good, make it epic; kill the circle
> *"the sword saint shows the sword curve already which is good make it look more
> epic and remov ethat background circle when I attack"*

The strike tell is now a `Telegraph.Style.CRESCENT` (a thin air-curve) — that is the
part they like. The remaining **background circle on attack** is a separate object:
look at `SpellSigil.open` / `MagicCircle` on the melee path, not at the telegraph.

### 5. SWORDSAINT NEEDS MORE PUNCH GENERALLY
> *"the first boss is lit but swords person needs a better effect or damagge or
> something"*

Note the class measured **exactly 50%** across three sweeps, so this is a FEEL ask,
not a balance one. Effect first, damage second.

### 6. BLOOD PACT — costs too much, wants a lasting aura
> *"the blood pact takes up too much damage and it needs to have a long effect on the
> sword person like give them an aura"* / *"the blood pact needs to be buffed"*

`BloodPact.gd`. Two halves: cut the self-damage cost, and give the caster a visible
long-duration aura (the rig already has an aura pass — `_draw_aura`, and
`CharacterRig` carries `aura_color`).

### 7. HORIZON CUT SHOULD DEFLECT EVERYTHING IN FRONT OF IT
> *"horizon cut should also defelct any and everything in front of it as it sends"*

The cut should sweep incoming projectiles/spectacles aside as it travels, not just
damage bodies. Pairs naturally with ask 1 — same deflect layer.

### 8. THE CLERIC IS OVERPOWERED — and cooldowns should be DERIVED, not hand-set
> *"cleric is very OP, different classes and different spells should have diffferent
> cooldowns based on damage output usefulnness all that sort of stuff"*

⚠ **THIS ONE IS BACKED BY THE MEASUREMENT, unlike the Warlock ask that was declined.**
The Cleric read **75% / 78% / 81%** across three 288-bout sweeps — top of the roster
in all three and the only class that RISES across them. Together with the bottom
three that is the strongest signal in the table. Do not decline this one.

The systemic half is the more interesting request: **a cooldown should be derived
from what a spell is worth** (damage output + utility), not authored by hand per
spell. The codebase already has the machinery pointing the other way — `SpellTier.of`
DERIVES a spell's shelf from `cast_time` / `cooldown` / `mp_cost`, and its header
argues that deriving means "a spell cannot lie about its tier". The ask is to invert
that for cooldown, and the same argument applies: a spell should not be able to lie
about its cost. ⚠ Note the circularity — if cooldown becomes derived FROM damage while
tier is derived FROM cooldown, one of the two has to become the input. Settle that
before writing code.

Cheapest honest first step: a probe that tables every spell's damage-per-second and
utility against its cooldown, so the outliers are visible before anything is retuned.

### 9. THE DEAD STAND BACK UP WHEN SPECTATING
> *"when they die in spectating they shouldnt stand up they died"*

⚠ **STRONG LEAD, from code read this session — check this first.** `Hero._die()`
(~`Hero.gd:5587`) branches on whether a run is active. **Outside a run — which is
exactly the duel and Watch Bots — it does `hp = max_hp` and returns**, i.e. the loser
is HEALED TO FULL rather than dying. Its own comment says this is so "the feel toy
never stops". `BotMatch._put_the_loser_down` separately collapses the rig, so the two
disagree: the rig is toppled while the body is alive and at full health, and anything
that re-drives the rig from a live body stands it back up.

The fix is a mode question, not a rig question: a SPECTATED bout has a loser and must
keep one, so the "heal and carry on" arm needs to exclude `BotMatch`. Do not chase it
in `CharacterRig` — the ragdoll is behaving correctly for a body that is not dead.

### 10. OLD SPEECH BUBBLES ARE STILL SHOWING IN SOME CLASS FIGHTS
> *"none of the text should have those old speech bubbles as well now I saw a couple
> in some calsses fights"*

The duel barks were changed to **bare coloured text with no box** in wave 4
(`BotMatch._taunt` — "THE LINE WEARS THE SPEAKER'S OWN COLOUR"). But that is only
`BotMatch`'s own taunt path. **`SpeechBubble` is shared**, and other speakers still
route through it with the old boxed look: `Bark.say()` (used by `VoiceDirector` for
wave_start / wave_clear / streak / low_health, and by `EliteRider`) and the hub NPCs.

So the fix is NOT in `BotMatch` — that one is already right. Find the speakers still
drawing the box and bring them to the same bare-text treatment, or move the box
removal INTO `SpeechBubble` so no caller can opt back into it. ⚠ The hub NPCs
(Raebai, Mirelle) use the same bubble and their look was tuned against the boxed
version, so decide deliberately whether the town keeps the box or loses it too.

---

# LIVE PLAYTEST QUEUE — 2026-08-06 (wave 5)

All seven of wave 4's OPEN asks are **actioned**, so is the one thing wave 5 left
open, and so are both items that were being deferred as "needs your taste" —
the nine boss drops and the stick customisation. Branch `bot-fight-quality`,
**157/157 green**, tree clean. **None of it has been played by hand.**

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

## ▶ WAVE 5c — THE TWO DEFERRED ITEMS ARE BUILT

### 6. NINE CLASSES NOW HAVE NINE DIFFERENT BOSS DROPS
Three PAIRS used to share a Tier 3, and two of the six were Tier 2 spells standing
in for a Tier 3 that did not exist. Five new ones, and **none is a bigger number** —
each bends a different rule:

| class | drop | the rule it bends |
|---|---|---|
| Shadowblade | **Severance** | the only damage read off the **victim** (missing health) |
| Swordsaint | **Zanshin** | the only AoE that gets **stronger** with more bodies in it |
| Brawler | **Teardown** | the only damage that comes from the **arena**, not the spell |
| Juggernaut | **Siegeworks** | the only spell that **takes the room away** |
| Stormcaller | **The Circuit** | the only one with **no radius** — beaten by tempo, not position |

**What to feel for:** Teardown in an empty corridor is *meant* to be a near-wasted
charge; Siegeworks' first second is *meant* to be a free exit. If either reads as a
bug rather than a decision, say so — `BASE_DAMAGE` and the ease curve are the dials.

Two things that had never existed and now do: `CastStyle` had **no CATACLYSM arm**,
so every Tier 3 in the game was thrown with the aimed dart pose; `BotBrain` had none
either, so a bot sized `equinox` — which levels the room — as a 300 px poke.

### 7. HAIR, SHADES AND A SHEATH — and the spec was wrong about needing art
`2026-08-05-stick-customisation.md` said a new item is "a PNG plus a registry row".
**`EQUIP_TEX` is gone** — removed on your own ruling that gear must replace a part
rather than sit on it — so the rig has been fully procedural for a while and this
needed no assets at all. Three slots: `hair` (spiky/long/mop), `face`
(shades/visor), `sheath` (saya/scabbard). **The Swordsaint wears its saya**, because
an iai is a draw.

Nothing joins `GEAR_KINDS` — that registry obliges a stat bag and a balance sweep,
which is right for a hammer and absurd for sunglasses. The head hitbox contract is
asserted across every combination.

**Still open there:** hair takes a lightened body colour, not its own. Your
reference wants white hair on a navy figure — one export plus one parameter.

---

## ▶ WHAT IS STILL OPEN

- **Hair colour** — hair derives from the body colour instead of carrying its own.
  One export plus one parameter through `draw_figure`.
- **Non-robe clothing** (jackets, coats, gi) — the one row of the customisation
  spec still untouched. Procedural like the rest; no art needed.
- **The five new drops are UNPLAYTESTED and unpriced.** No balance sweep has been
  run with them in — and `CLASS_DROP` only feeds bot duels, so they are reachable
  in a tower run only if `SpellDrops.TOWER_SPELL_DROPS` is flipped on.
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
