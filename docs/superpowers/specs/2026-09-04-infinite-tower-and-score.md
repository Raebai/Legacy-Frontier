# THE ENDLESS TOWER, AND THE NUMBER YOU ARE RANKED BY

*Design note. Written before the code, and the code follows it.*

> **The maker's ask, verbatim:** *"revamp the tower so thats its infinite and you are
> scored on like how high you get... and the game is just who can get highest in the
> tower"*, entered *"with online people or multiplayer people"*.

---

## 0 · What is true before this change

* The climb is a **10-floor authored table** in `GameState.build_default_tower()`.
  Two of the ten are BOSS floors (5 and 10). Clearing floor 10 **ends the run** in
  victory and sets `tower_conquered`, and the next entry resets you to floor 1.
* Floors are already **data-driven** over one parameterised room shell:
  `TowerDef` -> `FloorDef` -> `WaveDef` / `LayoutDef` / `EnvTheme`, redrawn per climb
  by `FloorGen.apply()` and built by `FloorBuilder` / `Encounter`.
* The climb is already **persistent**: `user://climber.json` holds the floor you
  resume on, your highest floor ever, your falls, and your levelling record. A wipe
  drops you to your checkpoint band (`DeathRules.CHECKPOINT_BAND = 5`), not to 1.
* **There is no score.** `_highest_floor` exists and is shown on the summary card,
  but nothing ranks a run, nothing keeps a run history, and there is no best.
* **There is no backend.** No server, no accounts, no service of any kind.

So the work is three things: make the tower not end, decide what the number is,
and be honest about what a *global* board would actually cost.

---

## 1 · How the tower continues past the authored ten

### 1.1 The authored ten are the opening act, and they are not touched

The ten floors are hand-tuned — twice, on playtest notes (the depth-tapered easing,
the floor-1 double cut). An infinite tower that begins at floor 1 with procedural
filler would be **strictly worse than what exists today**. So:

* **Floors 1-10 are byte-identical to today**, with and without this feature.
  A test pins that (`ascent_never_touches_the_authored_spine`).
* **Floors 11+ are the ASCENT** - synthesized blueprints run through the *same*
  `FloorGen.vary_floor` that redraws an authored floor. They get a generated room,
  a jittered biome, a varied mix, and the same `gen:` / `genseed:` tags.
* **Everything downstream is handed a `FloorDef` and cannot tell which kind it got.**
  `Encounter`, `Arena`, `FloorBuilder`, `BossRoster`, `EliteRoster` are unchanged.

### 1.2 The seam, and where endlessness is switched on

`TowerDef` gains one flag, `endless`, and it **defaults to `false`**.

`GameState.build_default_tower()` - which eight tools and suites call directly and
assert the authored numbers against - returns the plain 10-floor spine, exactly as
before. `GameState._load_or_build_tower()`, which is the only path the *game*
takes, marks it endless.

This is the same split `FloorGen.apply` already uses and for the same stated
reason: the authored table stays the thing that is asserted, and the thing applied
at play time stays the thing that is played. It also means every existing suite
(including `slice_test_climb`'s "clearing the last floor conquers the tower") keeps
describing a true thing rather than being edited to accommodate a new feature.

### 1.3 `total_floors()` keeps its meaning; a new question gets a new method

`total_floors()` continues to answer **"how tall is the authored spine"** (10). It
is read by the checkpoint clamp, the summary card and the floor banner, and
silently redefining it would have been the `TOTAL_FLOORS`-vs-`total_floors()` bug
this repo already recorded once.

The new questions get new methods: `is_endless()`, `has_next_floor()`,
`climb_ceiling()`, `floor_label(f)`.

`climb_ceiling()` is **9999, not infinity**, deliberately. An unbounded integer is
a place for a hand-edited save or a formatting overflow to live, and every consumer
that prints `Floor %d` wants a bound it can trust. At ~90 s a floor, 9999 is 250
hours in one sitting; the difficulty plateau (SS2.6) arrives about 9960 floors
earlier.

### 1.4 What clearing floor 10 means now

It stays a **milestone** and stops being an **ending**:

* `tower_conquered` is still set the first time you clear the summit (the card, the
  hub NPCs and the class-choice hook all read it).
* The run **does not end**; `floor_advanced(11)` fires and the ascent begins.
* On an endless tower, `tower_conquered` **no longer resets you to floor 1** on the
  next entry. It is a badge, not a reset trigger. `reset_climb()` - walking over and
  asking an NPC - remains the one door back to floor 1, exactly as decided.

---

## 2 · The difficulty curve, and why not one HP number moves

> Maker, standing rule, quoted in the code at four sites: *"higher floors add
> modifiers, not HP. HP scaling makes fights longer, not harder, and long is the
> enemy of chaos on a phone."*

Every ascent floor runs `hp_multiplier = 1.0` on trash. **A test enforces it at
every generated depth**, because this is precisely the rule that an infinite curve
tempts you to break.

The ascent escalates on six axes, in this order of importance:

### 2.1 Floor TYPE rhythm - the band shape repeats

`COMBAT, COMBAT, ELITE, COMBAT, BOSS`, restarting every five floors. That is band
1's own shape (floors 1-5), so a guardian stands at 15, 20, 25, 30 ... and the
checkpoint (`DeathRules.checkpoint_for`, band 5) lands at 11, 16, 21 - **immediately
after each guardian**. A wipe therefore costs you a band, and a band always ends in
the thing you were climbing toward. That alignment is free and it is the reason the
period is 5 rather than 4 or 6.

### 2.2 Archetype MIX - the headline axis

The blueprint composes each wave's roster out of the four threat classes FloorGen
already uses (`PRESSURE`, `HEAVY`, `RANGED`, `ODD`).

> **CORRECTED BY MEASUREMENT.** The first version of this section said a floor's
> *maximum* breadth ramps 2 -> 3 -> 4 with depth. That sounds like escalation and is
> actually a cliff at the seam: **the authored spine already ends wide** - floor 10's
> finale is chaser/brute/charger/assassin/bomber/mage, all four classes at once - so
> an ascent opening at two classes made floors 11-15 *narrower* than the floor below
> them. `probe_endless_curve` measured it: floors 11-15 came back at index 32.8 /
> 31.4 / 30.1 / 31.9 / 32.2 against floor 10's 32.4. Four of the first five ascent
> floors were a step **down** from the summit - the "procedural filler is strictly
> worse than what exists" failure, relocated to floor 11.

So the escalation is **how early a floor gets wide, not how wide it ever gets**:

* **Every ascent floor's FINALE fields all four classes**, continuing the spine
  rather than restarting under it. A test pins this against the authored summit's
  own finale, so it cannot silently regress.
* **The OPENING is what climbs**: floor 11 opens at two classes and widens across
  its waves; floor 17 opens at three; from floor 23 every wave is a finale. The floor
  stops giving you a narrow wave to settle into.

The rotating class selection is keyed on depth, so consecutive floors do not field
the same pair; `FloorGen._vary_roster` then swaps within class, widens and applies
the character pass on top, exactly as it does to an authored floor.

### 2.3 Wave COUNT - 4, then 5, then 6, and it stops

Non-boss floors: 4 waves in band 3, 5 in band 4, 6 from band 5. Boss floors take
one more, capped at 6. **Six is the ceiling.** A seven-wave floor is not harder, it
is longer, which is the failure mode the HP rule exists to prevent, wearing a
different hat.

### 2.4 BODY COUNT - grows briefly, then plateaus on purpose

Floor 10 authors 78 bodies. The ascent adds **+2 per floor to a ceiling of 90**,
which is reached at **floor 16** and never moves again.

That plateau is a decision, not an omission. 90 bodies at a cap of 10 is already
around four minutes of continuous fighting; a floor-60 room holding 300 bodies
would be a chore with the same peak intensity. **Past floor 16 the tower stops
getting bigger and starts getting meaner**, which is the whole thesis of the mix
axis.

### 2.5 PRESSURE cap - 8 -> 10, then stop

Concurrent alive: 8 (floors 11-15), 9 (16-20), 10 from 21. Ten bodies on a
640x360 screen under a fit-all camera is already dense; twelve is soup, and the
maker's own note on the early floors was *"there are too many opponents"*.

> **THIS AXIS WAS ENTIRELY DEAD UNTIL THE PROBE FOUND IT.** `FloorGen.vary_waves`
> ended with `clampi(caps[i], 2, 8)` - a hard ceiling that exists for a good reason
> (its `_reshape` conserves a floor's *sum*, not its maximum, so a redraw of the
> authored floor 9 could otherwise come back denser than hand-tuned). Every 9 and 10
> the ascent asked for was being clipped straight back to 8, and **nothing anywhere
> reported it, because a clamped number is not a rejected one**. The probe read the
> cap axis as "last moves at floor 14, settles at 8.00" against a design that said
> floor 21 and 10.
>
> The fix is a depth-gated ceiling, not a raised one: `WAVE_CAP_MAX` (8) still holds
> for every authored floor under every seed, and only a floor synthesized past the
> spine may reach `ASCENT_WAVE_CAP_MAX` (10). Both halves are tested, and the test
> was reverted and seen to fail.

### 2.6 The two dials that keep going after the rest have stopped

Everything above plateaus by floor 23. Two things do not:

* **FLOOR AFFIXES.** One `EliteModifier` rule riding *every body on the floor* -
  quickened / inked / volatile. The machinery has been built and shipped **off**
  since it landed, because `docs/THE-TOWER-mobile-plan.md` lists floor modifiers as
  out for v1. It is turned on **for ascent floors only**, one affix from floor 11,
  two from 26, three from 41. Floors 1-10 stay clean and the v1 spec still holds
  over everything the game ships today.
  WARNING: the existing note on `FloorGen.floor_affixes_enabled` is that a
  per-player static desyncs co-op. This does **not** use that static: the affixes
  are derived from `(tower_id, depth, climb_seed)` in a pure function, so both peers
  derive the same ones. `ASCENT_FLOOR_AFFIXES` is a single named constant so the
  maker can turn this off in one line if they disagree with the call.
* **HEALING, taken away.** `FloorBuilder` places two health packs on any floor with
  no opinion. Ascent floors state one: **2 packs to floor 20, 1 from 21, none from
  36.** This is the honest opposite of an HP sponge - it does not lengthen a fight,
  it shortens your margin for error inside one. It needs the `health_packs_authored`
  flag that `LayoutDef` itself already names as the correct fix for "empty means no
  opinion".

And both of *those* plateau too - at floor 41 the tower is at terminal intensity:
peak density, all four classes, every body carrying three affixes, no healing.

**That is stated rather than hidden.** For a score-chasing endless mode this is the
right shape: past floor 41 the question stops being "can you handle what is next"
and becomes "how long can you hold at the ceiling", which is exactly what a
height score measures. An unbounded curve would just be a wall with a floor number
on it, and every player's score would converge on the same floor.

### 2.7 The guardian's HP, which is the one legitimate curve, and its cap

`FloorDef.boss_hp_multiplier` is the one place depth may buy HP, because it is one
committed duel rather than twelve bodies to shred. Floor 10 sits at x2.4. The
ascent continues at +0.1/floor and **caps at x4.0** (reached at floor 26). Past
that the guardian escalates through the roster it is drawn from and the four
modifiers it carries - and no further, per SS2.6.

### 2.8 XP has a depth cap now, and it is not a nerf

`Progression.floor_xp_value` is `BASE * 1.2 * 1.27^(f-1)`. At floor 999 that
overflows a 64-bit int when the floor purse rounds it. The effective depth is
clamped at **30**, which is where `MAX_LEVEL` has already been reached
(`expected_level_on_floor(26) = 31`) and where XP has therefore already stopped
buying anything. Nothing reachable changes value.

---

## 3 · THE SCORE

### 3.1 Two numbers, and only one of them is the headline

```
PEAK FLOOR   - the headline. The number the board is sorted by.
TIME         - the tiebreak, and nothing else.
```

Ranking is `peak_floor DESC, elapsed_ms ASC`. That is the whole rule, and it fits in
one line for a reason.

### 3.2 What each input had to justify

| Input | Verdict | Why |
|---|---|---|
| **Peak floor** | **KEPT - the headline** | It is the maker's ask, verbatim. It is also the only number in the game that cannot be farmed: the sole way to raise it is to go somewhere you have not been. |
| **Time** | **KEPT - tiebreak only** | Two climbers both reach floor 34; something has to separate them, and time is the only candidate that needs no explanation, cannot be farmed, and is already measured. Deliberately **not** part of the headline number: a visible speed component makes the optimal play "rush and die", which inverts the game. As a tiebreak it can only ever separate equals. |
| Kills | REJECTED | Rewards farming a floor you have already beaten - the exact opposite of climbing. The XP purse already had to be invented to stop that; a score should not reintroduce it. |
| Deaths / falls | REJECTED | A death already costs you floors (checkpoint band). Charging for it twice is a hidden multiplier, and hidden multipliers are how a score stops being legible. |
| Floors cleared without falling | REJECTED | It is peak floor with extra steps, and it needs a sentence to explain. A score that needs a sentence has already lost. |
| Friendly-fire damage | REJECTED | A great line on the summary card and a terrible line in a ranking - it would make the correct co-op play "stop using area spells", which deletes the game's social engine to win a leaderboard. |

Everything rejected still appears **on the run card as a fact**. Facts are free;
score inputs are not.

### 3.3 Where it is stored

A new file, `user://scores.json`, beside `user://climber.json`, written with the
same tmp-then-rename atomic idiom and the same *"a test run must never write the
player's real save"* tree guard.

**Separate from climber.json, deliberately.** The climber is one record rewritten
on every floor transition; the board is a list that grows. Merging them makes the
per-floor write bigger every run and lets a corrupt board take the climber with it.

**Nothing is stored twice.** The board holds a `history` array, best-first, capped
at 25 rows. The personal best is `history[0]` - *derived*, never stored - which
kills the whole class of bug where a stored best drifts from the list it is
supposed to be the best of. On load, `_highest_floor` and the board reconcile
upward, so the monotone counter and the board can never disagree.

Every integer is read back through `int()`. JSON gives floats, and this repo has
lost a save to that exact trap once already (the M9 bug).

---

## 4 · THE LEADERBOARD, honestly

### 4.1 What is built

* **Personal best** - derived from the history, shown on the run card.
* **A local high-score table** - the top 25 runs on this device, sorted by the
  SS3.1 rule, each row carrying floor, time, class, when, and whether the run ended
  in a death.
* **A rank query** - `ClimbScore.rank_of(history, record)` answers "what place
  would this run take", which is what the end-of-run card wants.
* **The seam** - `ClimbScore.to_wire(record, climber_id)` produces the exact JSON a
  remote board would be POSTed, and `from_wire` reads it back. A remote board
  attaches by implementing two calls (submit, fetch-top-N) against that shape.
  Nothing else in the game would have to change.

### 4.2 What is NOT built, and why saying so is the point

**There is no online leaderboard, and one cannot be built from inside this repo.**
It needs three things that do not exist and are not code:

1. **A service.** Somewhere to POST to, that stays up, that costs money, and that
   somebody operates. There is no server here and no hosting.
2. **Identity.** A board without accounts is a board of nicknames, which is a board
   anybody can impersonate. Accounts mean sign-in, storage of personal data, and
   the legal surface that comes with both.
3. **Anti-cheat, which is the hard one.** *Every number in the proposed score is
   computed on the player's own machine.* `user://scores.json` is a plain text file
   in a documented location; raising your floor to 900 is an edit, not an exploit.
   A credible board therefore needs either server-authoritative simulation (the
   server runs the fight - enormous) or replay verification (the client ships its
   input stream and the server re-simulates - large, and it requires the whole game
   to be deterministic, which it currently is not: `FloorGen` is deterministic but
   combat is not).

A fake online board - a "GLOBAL" tab reading local rows, or a stub that always
returns the same five names - would look finished, would be believed, and would be
a lie in the shipped build. So it is not here.

**What IS reachable without a backend, and is the honest next step:** in a co-op
session both peers already exchange state over the existing `Net` layer, so the
party can compare bests *at the end of a session* - a two-person board, no service,
no accounts, and cheating only lets you lie to a friend who is right there. That
is a `Net.gd` change and `Net.gd` is not this change's to make.

---

## 5 · How the curve is READ rather than trusted

`tools/probe_endless_curve.gd` simulates a climb to floor 50 (`--to=N`) and prints,
per floor: type, wave count, total bodies, peak concurrent cap, the archetype-class
histogram and how many distinct classes the floor fields, elite budget and affix
count, boss HP multiplier and modifier count, the floor affixes, and the health
packs on offer. It ends with a summary that names:

* the floor at which each axis **plateaus**,
* the **mean threat classes per wave** (`cls̲`) - deliberately the mean and not the
  max, because once every finale is four classes wide the max carries no signal and
  what escalates is how much *of* the floor is wide,
* any floor that is **easier than the one below it** (a difficulty inversion),
* any floor whose trash `hp_multiplier` is not 1.0 (the rule, checked rather than
  asserted),
* a composite difficulty index per floor so the shape can be seen at a glance.

A curve that becomes unwinnable at floor 12 or trivial at floor 40 is the thing to
look for, and only a simulation finds it.

`tools/slice_test_endless.gd` is the suite (22 tests, vacuous-pass armoured): the
spine is untouched, ascent floors are well-formed and deterministic, trash HP never
scales, the plateaus are where this note says they are, the type rhythm holds, a wipe
deep in the ascent costs a band rather than the climb, `GameState` drags no combat
script into its compile graph, and the score orders, persists and survives a JSON
round-trip.

### 5.1 The measured curve, as shipped

Floors 1-10 are the authored spine; 11+ is the ascent. `index` is the probe's
weighted read, not a measurement.

```
 fl  kind    type    wv  bodies  cap  cls̲  elite  affixes             pk  bossHP  index
  1  spine   COMBAT   3      14    4   1.7  0x1    -                    2   1.00x   12.1
  5  spine   BOSS     5      58    8   3.2  2x2    -                    2   1.60x   28.4
 10  spine   BOSS     5      78    8   3.2  2x2    -                    2   2.40x   30.6
 11  ASCENT  COMBAT   4      80    9   2.8  2x2    inked                2   2.50x   34.5
 15  ASCENT  BOSS     5      88    8   2.8  2x2    inked                2   2.90x   33.9
 20  ASCENT  BOSS     6      90   10   3.2  2x2    volatile             2   3.40x   38.6
 25  ASCENT  BOSS     6      90   10   4.0  2x3    volatile             1   3.90x   44.2
 30  ASCENT  BOSS     6      90   10   4.0  2x3    inked, quickened     1   4.00x   47.3
 40  ASCENT  BOSS     6      90   10   4.0  2x3    quickened, volatile  0   4.00x   48.8
 50  ASCENT  BOSS     6      90   10   4.0  2x3    inked, quick, vol    0   4.00x   51.8
```

Plateaus, as measured: bodies at 16, cap at 20, waves at 20, class breadth at 23,
guardian HP at 26, healing at 36, floor affixes at 41. Trash HP is 1.0 on all 50
floors. Body count is identical across five climb seeds (1.00x spread), so "floor 30"
is the same promise on two machines - which is what co-op needs.

**Residual inversions: two, both worth exactly one cap slot.** Floors 12 and 19 read
1.4 index below the previous floor of their kind, and in both cases the whole delta
is `FloorGen._reshape` drawing a cap of 8 where its neighbour drew 9. That is the
generator's ordinary +/-1 jitter, which authored floors get too, and flattening it
would make the tower more uniform - the opposite of why the generator exists.
