# THE TOWER — the first playtest

**Nobody has ever played any of this.** Every feel number in the codebase is
reasoning, not feel: the clash window, the guard bands, the knockback, the rig
springs, the drop odds, the whole audio mix — nobody has heard it. This session
is the first time the game meets a person.

So the job here is not "find bugs". It is **to have opinions and get them
written down.** A bug you find will still be there tomorrow; the thought you had
about how the dash felt will not.

Prior art for the shape of this: `docs/v0.0-test-checklist.md`,
`docs/v2.0-slice2-checklist.md`.

---

## How to use this

Work down the tables. One line per thing, one verdict per line.

| mark | means |
|---|---|
| **A** | good. Ship it. Do not touch it. |
| **B** | fine, not exciting. Would improve later. |
| **C** | wrong. Not broken — wrong. This is the most valuable mark on the page. |
| **X** | broken / didn't happen / couldn't get there. |
| **–** | didn't reach it this session. |

**C is the mark this whole document is for.** X gets found eventually by
anybody. A gets found by nobody but you.

### Write the note in the moment, not after

The director stamps floor, class, boss, graphics tier and frame rate onto every
note automatically, so you never have to remember context.

- **F9** — flag this moment. No pause, no typing. Use it mid-fight, freely, when
  something felt off and you do not want to stop.
- **F2** — freeze the game, cursor lands in the note box, type, Enter, **F10** to
  unfreeze.

Afterwards: `python python-tools/playtest_notes.py` prints them,
`--export` copies them into `docs/`.

In the tables below, put the note's timestamp (or just `✓`) in the **note**
column so a verdict and its reason can find each other later.

---

## Preflight

| # | do | expect |
|---|---|---|
| P1 | `python python-tools/run_all_tests.py --jobs 8` | every suite green |
| P2 | Ollama running with `llama3.2:3b` | only needed for the hub NPCs; combat does not touch it |
| P3 | Open the project, **F5** | the **Lobby** (title / Play Solo / Host / Join / class picker) |
| P4 | **Esc → DIRECTOR**, or **F1** | the review panel, right-hand side |

If P4 shows nothing, the director did not build — see `docs/director.md`.

**Two entry points, and they answer different questions:**

- **F5 → Lobby → Play Solo** — the whole game. Use this for anything about the
  loop, progression, pacing or the hub.
- **F6 on `scenes/combat/Arena.tscn`** — the endless sandbox. Use this for
  anything about how a single thing FEELS, where you do not want a run's state
  in the way.

---

## 1 · The loop

The spine. If any of this is X, stop and report it — everything below it is
being judged through a broken frame.

| # | check | verdict | note |
|---|---|---|---|
| 1.1 | Lobby → Play Solo → you are in the tower, on a floor, with a class | | |
| 1.2 | The floor banner names the floor, the total and the theme band | | |
| 1.3 | Waves arrive, escalate, and the beat between them is legible | | |
| 1.4 | Final wave cleared → the boss arrives, and the arrival READS | | |
| 1.5 | Boss dies → exit portal opens → taking it climbs a floor | | |
| 1.6 | The gold return portal also appears, and going back to the hub works | | |
| 1.7 | Dying does what the current policy says it does *(see §9)* | | |
| 1.8 | Back in the hub, an NPC mentions the run you just had | | |
| 1.9 | Quit and relaunch — the climb resumes where you left it | | |
| 1.10 | **A floor takes 4–7 minutes.** Time one. Write the actual number. | | |

> 1.10 is the single most important number on this page. Everything about wave
> budgets is guesswork until a floor has been timed by a human who was bored or
> wasn't.

---

## 2 · Moving and hitting

Judge these in the **F6 sandbox**. This is the layer everything else sits on; if
it is B, nothing above it can be A.

| # | check | verdict | note |
|---|---|---|---|
| 2.1 | Walking — weight, acceleration, turn-around | | |
| 2.2 | Jump, and the fall after it | | |
| 2.3 | Dash — distance, cooldown, and whether the i-frames feel earned | | |
| 2.4 | Melee — does the swing connect where you think it will | | |
| 2.5 | Getting hit — knockback amount, hitstop, screen shake | | |
| 2.6 | Enemy death — does killing something feel like an event | | |
| 2.7 | The stick rig — does the figure have WEIGHT | | |
| 2.8 | Parry / guard — is the window findable without knowing the number | | |
| 2.9 | The clash (blade meets blade) — does it read at speed | | |
| 2.10 | Impact frames — right amount, or too many | | |
| 2.11 | **The mix.** Nobody has ever heard this game. Is it loud, thin, muddy? | | |

> 2.3, 2.5 and 2.8 are the three the maker's own live play has previously caught
> and the test suite never did. Trust the hands.

---

## 3 · The three spell buttons

`1` `2` `3` on desktop; the three buttons on the right thumb arc on touch.

| # | check | verdict | note |
|---|---|---|---|
| 3.1 | Each slot has its OWN cooldown — spending 1 leaves 2 and 3 ready | | |
| 3.2 | The bar shows what is ready, and the ready-flash is noticed | | |
| 3.3 | A big spell feels COMMITTAL — you can be punished for throwing it | | |
| 3.4 | You can aim well enough without aim assist *(ships at 0, Esc→Settings)* | | |
| 3.5 | Three buttons is the right number. Not two, not five. | | |
| 3.6 | Casting a spell reads as a PROCESS — windup, sigil, release | | |

---

## 4 · The nine classes

**Director → HERO → tap a class.** It switches live, mid-fight, no respawn. Give
each one two minutes in the sandbox.

| # | class | its promise | verdict | note |
|---|---|---|---|---|
| 4.1 | Arcanist | ranged arcane zoner | | |
| 4.2 | Shadowblade | in-and-out assassin | | |
| 4.3 | Brawler | pure melee, no magic | | |
| 4.4 | Juggernaut | unbreakable siege tank | | |
| 4.5 | Cleric | radiant lifesteal bruiser | | |
| 4.6 | Cryomancer | ice control caster | | |
| 4.7 | Stormcaller | hyper-mobile chain caster | | |
| 4.8 | Warlock | dark attrition hexer | | |
| 4.9 | Swordsaint | guard-and-punish duelist | | |

| # | across all nine | verdict | note |
|---|---|---|---|
| 4.10 | Do they actually feel DIFFERENT, or is it the same hero in nine colours | | |
| 4.11 | Is there one you want to keep playing | | |
| 4.12 | Is there one that is obviously the strongest | | |
| 4.13 | Does the class card's promise match what the kit does | | |

---

## 5 · The spell catalogue

**Director → HERO → pick a slot → tap a spell.** The list is the whole
catalogue: class kits, the six Tier 2 floor pickups and the four Tier 3 boss
drops, tagged `[Q]` quick / `[H]` heavy / `[U]` ult.

Rather than 30 rows, judge them in groups and name the exceptions.

| # | group | verdict | note |
|---|---|---|---|
| 5.1 | Beams (Ordinary, Frostpiercer, Infernal Lance, Umbral Lance, Tempest) | | |
| 5.2 | Lightning (Thunderclap rush, Chain Lightning) | | |
| 5.3 | Rays and pillars (Judgment, Colossus Pillar, Rock Pillar) | | |
| 5.4 | Bombardment (Meteor Sigil, Void Barrage, Avalanche, Frozen Comet) | | |
| 5.5 | Projectiles (Rune Orbs, Boulder Hurl) | | |
| 5.6 | Melee bursts (Blink Strike, Blade Flurry) | | |
| 5.7 | Zones and drain (Void Zone, Blizzard, Drain Tether) | | |
| 5.8 | Walls (Rock Wall, Ice Wall, Aegis Ward) | | |
| 5.9 | New shapes (Creeping Shade, Rift Dagger) | | |
| 5.10 | The six Tier 2 drops | | |
| 5.11 | The four Tier 3 drops | | |
| 5.12 | **Which ones are boring?** Name them. | | |
| 5.13 | **Which one is the best moment in the game?** Name it. | | |
| 5.14 | Spell-vs-spell: fire shatters ice, holy banishes shadow, equal annihilates | | |

---

## 6 · Enemies

**Director → SPAWN → pick an archetype, x1 / x3 / x5.** Judge each one alone
first, then in a crowd.

| # | archetype | the question | verdict | note |
|---|---|---|---|---|
| 6.1 | Chaser | is the pressure fun or noise | | |
| 6.2 | Brute | is the telegraph readable | | |
| 6.3 | Caster | is the bolt dodgeable | | |
| 6.4 | Charger | can you get out of the lane in time | | |
| 6.5 | Summoner | do you notice it and prioritise it | | |
| 6.6 | Assassin | fast and fragile, or just annoying | | |
| 6.7 | Bomber | is the blast worth the space it takes | | |
| 6.8 | Mage | is the ground AoE fair | | |
| 6.9 | A mixed crowd of 15+ — is it readable or is it soup | | |
| 6.10 | At the 25 ceiling — does the screen still make sense | | |

---

## 7 · The four bosses and the six modifiers

**Director → BOSS.** Pick the artist, tick modifiers, tap SUMMON. **Set HP to
x0.25** to see a whole rotation quickly, and turn **GOD** on (HERO tab) to watch
a full moveset without dying to it.

| # | boss | the question | verdict | note |
|---|---|---|---|---|
| 7.1 | The Scribble | is a short violent fight actually short and violent | | |
| 7.2 | The Ashen Tower Guardian | do the three phases escalate | | |
| 7.3 | The Cartographer | does the slow ruler-and-compass identity land | | |
| 7.4 | The Illuminator | does it earn being the deep-floor one | | |
| 7.5 | Every boss attack has a tell you can act on | | |
| 7.6 | The intro card and boss bar land without eating the fight | | |

Now the modifiers. **The spec's claim is that these change BEHAVIOUR, not
numbers** — "higher floors add modifiers, not HP". The row that matters is
whether you can TELL, from playing, which one is on.

| # | modifier | can you tell it is on, from the fight alone | verdict | note |
|---|---|---|---|---|
| 7.7 | Enraged | | | |
| 7.8 | Split | | | |
| 7.9 | Void-touched | | | |
| 7.10 | Mirrored | | | |
| 7.11 | Patient | | | |
| 7.12 | Unfinished | | | |
| 7.13 | All six at once — noise, or gloriously unfair | | | |
| 7.14 | **SUMMON a seeded roll** for depth 5 a few times — is the variety real | | | |

---

## 8 · Drops and the handoff

| # | check | verdict | note |
|---|---|---|---|
| 8.1 | A Tier 2 pickup appears on a floor often enough to matter, rarely enough to be an event | | |
| 8.2 | You can SEE it across the room at 640×360 | | |
| 8.3 | Tier 3 vs Tier 2 is distinguishable at a glance (crown, size, colour) | | |
| 8.4 | Picking one up displaces a kit slot in a way you understand | | |
| 8.5 | A boss kill drops a Tier 3 and it feels like a reward | | |
| 8.6 | Tier 3 charges running out and reverting to your ult reads correctly | | |
| 8.7 | **Handoff** (co-op): the prompt appears, `E` gives it, the right player gets it | | |
| 8.8 | Is scarcity the right balance lever, or does it just feel like bad luck | | |

---

## 9 · Death, ghost form and revive

⚠ **The death policy changed during this build.** `fall()` (drop two floors,
stay in the tower) was replaced by `game_over()` (the run ends, the town clocks
it). **Check which one you actually get and write it down** — the director's
FLOOR → *Trigger the death path* names the method it reached on the status line.

| # | check | verdict | note |
|---|---|---|---|
| 9.1 | Solo death does what you expected it to do | | |
| 9.2 | Co-op: going down puts you in GHOST FORM, not on a spectator camera | | |
| 9.3 | A ghost can drift freely and see the whole fight | | |
| 9.4 | **HAUNT** — does shoving the pack off your friend feel useful | | |
| 9.5 | Being dead is not boring. This is the whole test of the mechanic. | | |
| 9.6 | The revive channel is long enough to be a decision, short enough to attempt | | |
| 9.7 | Reviving under pressure is a read you enjoy making | | |
| 9.8 | Everyone down → the run ends, and the ending reads | | |
| 9.9 | The hub NPCs clock your falls in a way that stings pleasantly | | |

---

## 10 · Floor randomisation

**Director → FLOOR → Re-roll**, several times on the same floor. Then jump
between floors and come back.

| # | check | verdict | note |
|---|---|---|---|
| 10.1 | The same floor genuinely looks different between rolls | | |
| 10.2 | ...but it still feels like the SAME floor — same difficulty, same identity | | |
| 10.3 | Ledges and cover are placed somewhere a fight wants them | | |
| 10.4 | No roll produces an unplayable room (unreachable ledge, hero in a wall, no cover at all) | | |
| 10.5 | Enemy leap actually happens now that there are ledges | | |
| 10.6 | Theme bands (surface → underground → sky) read as different places | | |
| 10.7 | Roll ~10 floors. Was any one of them memorable? | | |

---

## 11 · Friendly fire

The spec calls this the social engine. Needs two players, or a bot.

| # | check | verdict | note |
|---|---|---|---|
| 11.1 | You can hit your teammate with a spell | | |
| 11.2 | ...and it is FUNNY rather than infuriating | | |
| 11.3 | Knockback from a friendly hit is the right amount | | |
| 11.4 | Chain Lightning / Arc of Fools arcing onto your friend lands as a joke | | |
| 11.5 | Nobody can nuke themselves with their own spell | | |
| 11.6 | Is friendly fire ON the right default? | | |

---

## 12 · Co-op, on two machines

⚠ **This is the section most likely to be blocked.** Do it anyway, even
partially — everything about knockback and friendly fire is untunable solo.

| # | check | verdict | note |
|---|---|---|---|
| 12.1 | Host on one machine, Join on the other, by IP | | |
| 12.2 | Both heroes move smoothly on both screens | | |
| 12.3 | **You can SEE your teammate's spells.** *(see limitations)* | | |
| 12.4 | Enemies agree between the two screens | | |
| 12.5 | Both phones draw the SAME floor and the SAME boss | | |
| 12.6 | Boss phase changes are visible on the client | | |
| 12.7 | Remote hero animation: do they cast, swing, dash — or just slide | | |
| 12.8 | A floor advance carries both players | | |
| 12.9 | Party wipe → both get the ending | | |
| 12.10 | Pull the plug on one machine — does the other soft-lock | | |

---

## 13 · The mobile picture

No APK has ever been built. **Director → VIEW → Graphics: LOW** is currently the
only preview of the phone's picture that exists.

| # | check | verdict | note |
|---|---|---|---|
| 13.1 | On LOW, is the game still good-looking, or is the identity in the grade | | |
| 13.2 | Specifically: no chromatic aberration, no shockwave ripple, no heat haze | | |
| 13.3 | Impact frames on LOW (paint-only) still read | | |
| 13.4 | The bloom is doing the work you thought the post-process was | | |
| 13.5 | Resize the window to a phone aspect — does anything fall off the screen | | |
| 13.6 | HUD, boss bar and floor banner at 640×360 — legible? | | |
| 13.7 | **F3 perf overlay:** watch `worst`, not FPS. Amber past 16.7 ms. | | |
| 13.8 | Spawn 25 entities and cast into them — where does `worst` go | | |
| 13.9 | Touch layout (if you have a touchscreen): can two thumbs reach everything | | |
| 13.10 | The **II** pause button top-right is findable and hittable | | |

---

## 14 · The hub

| # | check | verdict | note |
|---|---|---|---|
| 14.1 | Raebai and Mirelle remember the run you just had | | |
| 14.2 | Their comment is specific enough to be worth reading twice | | |
| 14.3 | The tower door / portal is obvious | | |
| 14.4 | Class selection before a run works and sticks | | |
| 14.5 | Is the hub a place you want to spend 30 seconds in, or a lobby you skip | | |

---

## The big three

Answer these last, in prose, in a note. They are the only questions that decide
anything.

1. **Is it fun?** Not "is it working". Would you play another floor right now?
2. **What is the best 5 seconds in the game?** If nothing comes to mind, that is
   the finding.
3. **What would you cut?**

---

## Known limitations — NOT failures

Everything here is already known and deliberate. **Reporting one costs review
time and buys nothing.** If you hit something in this list, move on; if you hit
something that ISN'T in this list, that is a finding.

### Not built yet

- **Teammate spells may be invisible in co-op.** `SpellCaster` was net-blind by
  design until the replication pass; if your friend's magic does not render on
  your screen, that is the known top risk in
  `docs/THE-TOWER-mobile-plan.md` §3.1 — not a new bug.
- **Remote hero animation is limited.** A teammate may slide in a run cycle
  instead of casting, swinging or dashing. Known (plan §3.3).
- **No LAN auto-discovery.** Co-op is manual IP entry. Known (plan §3.4).
- **No APK exists.** Nothing here has ever run on a phone. Everything in §13 is
  a desktop approximation and the frame budget on a real device is unmeasured.
- **Touch numbers are untested guesses.** Every position and size in
  `TouchControls.gd` is reasoning. A thumb reach that is wrong on glass is
  expected — say WHICH way it is wrong, that is useful.
- **A phone player is short three verbs** a desktop player has (blast / blink /
  nova have no touch button). Deliberate consolidation, not an oversight.
- **No death screen, no credits screen.** Known gap.

### Deliberate design decisions, already argued

- **No auto-aim.** Locked. Spells are forgiving by SHAPE (cones, bursts, zones),
  not by snapping to a target. The aim-assist slider exists, ships at 0, and 0
  is genuinely inert. "I missed" is the intended experience; "I could never hit
  anything" is a finding.
- **Melee auto-targets the nearest enemy.** A known exception to the rule above,
  flagged and awaiting a decision. Not a bug.
- **Drop odds are guesses.** Every number in `SpellDrops.gd` is reasoned, not
  felt. They are all in one file so they can move after this session. "This felt
  too rare/common" is exactly the wanted feedback.
- **Higher floors add modifiers, not HP.** If a deep floor feels *tanky* rather
  than *different*, that is a finding — it is not supposed to be possible.
- **`hollow_purple` still needs renaming** (IP). Known.
- **Attribution owed** to the Pepper Sound Pack on a credits screen that does
  not exist yet. Known.

### Test / tooling noise

- **The release gate is RED on purpose.** `tools/release_gate_dev_bridge.gd`
  fails while the MCP dev bridge is in `[autoload]`. It is meant to be red
  during development and green only for a build that leaves the machine.
- **The director is not in a shipping build.** It lives in `res://tools/`, which
  the export preset excludes. Its absence on a phone is the design.
- **`--headless` capture runs are blank.** The dummy renderer draws nothing.
  Always use `python python-tools/run_capture.py`, which picks the GUI binary.
- **Boot logs `[MCP Runtime] ... port 7777`** — the dev bridge, expected.

---

## When you are done

```
python python-tools/playtest_notes.py --export      # notes into docs/, dated
```

Then hand back: the verdict columns, and the three answers.

**The single most useful thing you can produce is a list of C's.**
