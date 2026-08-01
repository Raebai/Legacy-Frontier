# THE TOWER — fun, playability and completeness audit

**Written 2026-08-01, branch `stickman-integrate`, HEAD `3da149c`.**

> ⚠ **THIS BRANCH MOVED WHILE THE AUDIT RAN.** Five other agents were working on it.
> HEAD advanced `485870a → 3da149c` mid-audit, and by the end there were **eight
> modified files and a large uncommitted working tree** including a brand-new
> ghost/revive/game-over system (`DeathRules.gd`, `GhostForm.gd`, `Revive.gd`) and a
> seeded floor generator (`FloorGen.gd`). Where a finding has been overtaken by that
> work I say so explicitly and review the new design instead. Re-check line numbers
> before acting on anything here.

**The governing fact: nobody has ever played this game.** Every feel number in it is
reasoning. This document's job is to predict, from the code, where a first playtest
breaks — specifically enough that each prediction can be checked in ten minutes.

Claims are marked **VERIFIED** (read in code, cited `file:line`), **MEASURED** (I ran
a harness in this repo), or **PREDICTED** (a judgement about feel, with the check
that would settle it).

A note on scope: I was asked to judge this as a *game*, not a codebase. As a codebase
it is in unusually good shape — 115 headless suites, a working release gate (I ran
it; it correctly reports red), and a `docs/mobile-export.md` more candid about its own
unknowns than most shipped postmortems. **Almost every problem below is a
game-design problem, not a quality problem.** That distinction matters, because the
temptation with a well-built thing is to keep building it rather than to go and play it.

---

## Part 0 — Verdict in a paragraph

The combat engine is real, the wave pacing is genuinely solved, and the
moment-to-moment reward loop is dense. What is missing is **everything that frames
it**: no onboarding, no victory screen, and an exit door that leads into a different,
parked game requiring a local LLM server. The death half of the frame was being
built *as this audit ran* and looks well-designed. The two things nobody is currently
fixing are **the win path** and **the fact that the game never tells you when
friendly fire happens** — which is the mechanic the whole design is named after.

---

## Part 1 — Ranked top 10, "fix before the maker plays"

### 1. Beating the game dumps you into a parked, broken hub. There is no victory screen. — VERIFIED

Clearing floor 5 → `GameState.advance_floor()` sets `tower_conquered` and calls
`end_run(false)` (`scripts/GameState.gd:158-163`) → `_change_scene(HUB_SCENE)`
(`:263`) → `HUB_SCENE = "res://scenes/Main.tscn"` (`:23`) — the **v0.0 top-down
AI-NPC town**, whose conversation stack talks to Ollama on `127.0.0.1:11434`.

`scripts/ui/Lobby.gd:23-28` says "THE HUB IS PARKED, NOT DELETED… Nothing here
reaches for any of it." True of the Lobby, false of the game. There are **five** routes
into `Main.tscn`, and one of them is winning:

| Route | Trigger | Cite |
|---|---|---|
| **Victory** | clear floor 5 | `GameState.gd:158-163` → `:263` |
| **RETURN TO TOWN portal** | spawns on *every* non-final cleared floor | `Arena.gd:308-321`, `:332` |
| **Pause → Exit** | any time | `Arena.gd:646-649` |
| Co-op session end | host returns | `Net.gd:308` |
| Versus sandbox exit | F6 duel | `VersusArena.gd:1151` |

There is **no victory banner, card or text in the tower run at all.** Grep for
`victory|conquer|you win` finds banners only in `VersusArena.gd` (the duel sandbox,
`:404`, `:455`). `GameState.gd:426` builds the string *"conquered all %d floors and
felled the guardian"* — fed only to hub-NPC memory, never rendered.

And **no route back to the Lobby exists anywhere in the game.** The only
`change_scene_to_file(".../Lobby.tscn")` in the project is `scripts/ui/Credits.gd:164`.
Once a run ends, the title screen is unreachable.

**Predicted:** the maker beats the tower, the screen cuts without ceremony to a green
tile-grid town with two NPCs in it, and either Ollama answers or they are mute. It is
the most embarrassing thing in the build and it is on the *win* path.

> ⚠ **AND THE IN-FLIGHT DEATH WORK MAKES THIS WORSE, NOT BETTER — VERIFIED.** The new
> `GameState.game_over()` ends with `end_run(true, died_on)`, and `end_run`
> (`GameState.gd:272-285`) still finishes on `_change_scene(HUB_SCENE)`. So once that
> lands, **both terminal states of the game lead into the parked AI-NPC hub**: you win
> → parked hub; your party wipes → GAME OVER card → parked hub.
>
> It also becomes **far more reachable**. Under the old rule, solo death bounced you
> one floor and kept playing, so a solo player might never hit this. Under the new
> rule solo death **ends the run immediately** (`DeathRules.SOLO_SELF_REVIVE_CHARGES = 0`),
> which means a new player can be standing in the old v0.0 town **inside the first
> sixty seconds** — after their first death, having seen nothing of the game.
>
> This single scene target is now the highest-leverage line in the project.

**⚠ And it is a genuine unresolved design conflict, not just an oversight.** The
in-flight death code routes there *on purpose*: `Arena._show_game_over`'s own comment
says *"the run ends and the hub loads (the trip home is where the town gets to clock
the death)"*, and `GameState.game_over()` reasons that *"the town clocking your deaths
is the moat, and it is the only lasting cost under the shipped policy."* That is a
coherent position — the AI-NPC memory layer genuinely is this project's differentiator.

It also directly contradicts `docs/THE-TOWER-mobile-plan.md` Part 3 item 3, which
records the LLM/NPC stack as **"out permanently"** and notes it is *"genuinely
incompatible with mobile: it hardcodes `http://127.0.0.1:11434` (Ollama), which on a
phone is the device's own loopback — it cannot work there."*

**Somebody has to decide this, and it cannot be decided by whichever agent commits
last.** The three honest options:
- **Cut it.** Game-over and victory both route to `Lobby.tscn` with a results card. The
  falls counter becomes a line on that card. Simplest; loses the moat.
- **Keep it, but build a real hub.** A small tower-side hub scene that is not
  `Main.tscn` and does not need Ollama — the barks/`SpeechBubble` layer can carry
  "that's 4 falls now" with no LLM at all.
- **Keep `Main.tscn`, desktop only.** Then mobile needs a different terminal path
  anyway, and the game has two shapes.

Option two looks like the one that keeps both commitments, and it is not much work —
the `build_run_fact` text already exists (`GameState.gd:413-444`) and `SpeechBubble`
is already the shipped bark renderer.

**Check in 10 min:** Pause → Exit on floor 1.

**Note:** `GameState.build_outcome` (`:390-406`) already captures floor, kills, boss
killed, elements used, rank tier/title and falls. A results card is close to free —
the data is sitting there being used only as NPC memory text.

---

### 2. Friendly fire — the stated social engine — has zero game-side feedback. — VERIFIED

The *mechanism* is elegant and done: one shared `&"mortal"` group, one line in
`SpellCaster._stamp` (`SpellCaster.gd:93-115`), self-exclusion via
`SpellTargets._pool(nodes, skip)` (`SpellTargets.gd:136-141`). Melee deliberately
scans the *faction*, never `mortal` (`Hero.gd:3441-3461`), so you cannot
auto-punch your friend — a good, deliberate asymmetry.

But grep across `Bark.gd`, `VoiceDirector.gd`, `Hype.gd` and `SpellTargets.gd` for
`friendly|ally|team_hit` returns **nothing**:

- `Bark.gd:67-137` defines 14 event categories — `run_start`, `floor_enter`,
  `floor_clear`, `fall`, `low_health`, `streak`, `close_call`, `wave_start`,
  `wave_clear`, `enemy_spawn`, `enemy_die`, `boss_arrive`, `boss_phase`, `boss_down`.
  **No category for hitting or being hit by a teammate.**
- Damage numbers are the same colour whoever dealt them (`Hero.gd:3726`).
- No `Hype` event, no distinct sound.

So the funniest thing that can happen — you delete your friend with the Void — renders
exactly like a stray enemy hit. **The game does not notice.**

This is the single cheapest high-value item in the audit: one bark table entry and a
damage-number tint. It is also the item most likely to decide whether the game's
identity lands, because **comedy needs attribution.**

**Three further gaps, all with strong competitor precedent:**

**(a) There is no friendly-fire dial, and effectively nobody ships flat-on FF without
one.** `SpellCaster.friendly_fire` is a static bool (`:101`) with no settings row —
grep of `PauseMenu.gd` and `TuningConfig.gd` for `friendly_fire` returns nothing. Every
shipped game that kept FF and kept its reception scaled or redirected it:

| Game | What they ship instead of on/off |
|---|---|
| Left 4 Dead 2 | damage multiplier by difficulty: **0.0 / 0.1 / 0.3 / 0.5** |
| Deep Rock Galactic | by hazard: **Haz1 0.10 → Haz5 0.70** |
| Nine Parchments | **invert** (aggressor takes it) or **50-50 split** |
| The Spell Brigade | disabling it **costs a modifier slot** — available, never free |
| Magicka 1 / Helldivers 2 | nothing — but recovery is trivially cheap |

Sources: [L4D2 FF config](https://cybrancee.com/learn/knowledge-base/how-to-disable-or-customise-friendly-fire-damage-on-your-left-4-dead-2-server/) ·
[DRG damage wiki](https://deeprockgalactic.wiki.gg/wiki/Damage) ·
[Nine Parchments dev post](https://steamcommunity.com/app/471550/discussions/0/1488866813773589018/) ·
[Spell Brigade FF guide](https://thespellbrigade.wiki/guides/friendly-fire/)

**(b) There is no co-op-only upside to pair with the downside.** Magicka pairs FF with
**merged beams** (*"Multiple beams can be brought together to create a more powerful
one"* — [Shacknews](https://www.shacknews.com/article/89356/co-optimized-magicka)) and
~200% boosted cross-healing; The Spell Brigade ships **Healing Fire**, which *"converts
all friendly fire damage from that spell into healing for affected teammates"*.
**Friendly fire alone is a tax; friendly fire plus a two-player-only power multiplier
is a system.** THE TOWER has the perfect substrate for this already — `SpellReactor`
and `ReactionTable` do cross-caster spell-vs-spell reactions today, and a
*same-team* reaction row that rewards combining is a data edit, not a new system.

**(c) It is not signposted anywhere.** Magicka 2's own Steam feature list reads
*"Friendly fire is always on, promoting emergent gameplay humor"*
([Steam](https://store.steampowered.com/app/238370/Magicka_2/)). Frozenbyte publicly
conceded that Nine Parchments' FF *"was not well represented in trailers and
descriptions, which was a clear mistake on their part"* — Nine Parchments sits at
Metascore 66 against Magicka's 74. **If FF is your engine it must be your headline,
not a surprise** — including on the class-select screen a new player sees.

**Check in 10 min:** two instances, hit your friend, see if anything acknowledges it.

---

### 3. Performance on the target device is the largest unknown, and the honest numbers are alarming. — MEASURED (by this repo, desktop)

`docs/mobile-export.md` §6, measured 2026-07-31 with spells actually casting, 25
entities, the real dispatcher:

| concurrent spell effects | CPU/frame (desktop) |
|---|---|
| 0 | 8.7 ms |
| 4 | 20.9 ms |
| 9 | 32.3 ms |

That is **~30 ms of desktop CPU at the game's own 8-effect ceiling**
(`SpellReactor.gd:107`), GPU contributing nothing (headless = dummy renderer). The
doc's own read: a 3-year-old mid-range Android is 3–5× slower single-threaded →
**~90–150 ms/frame**, i.e. 7–11 fps.

**One piece of good news the doc does not draw out, which materially lowers the risk:
the game never produces 25 entities in normal play.** Authored concurrent caps are
**4–7** (`GameState.gd:604-646`), summoner minions cap at 4 (`Enemy.gd:150-151`),
boss adds at 3 (`Encounter.gd:70`). Realistic peak is **~8–14 bodies**, not 25. The
crowd half of the measured cost is roughly a third of what was tested.

The spell half is not discounted, though — the 8-effect ceiling is reachable by two
players mashing three buttons each, which is exactly what the design asks of them.

**Not fixable by reasoning.** Needs `docs/mobile-export.md` §1.6 on a real phone. The
instrumentation is built (`PerfOverlay`, three-finger tap), the export preset is
tracked, and the release gate works — I ran it and it correctly reports red on
`MCPRuntime` still being in `[autoload]`.

**Recommendation:** do the device spike *before* the next content phase. It is the
only workstream with a genuinely unknown cost.

**Cross-check from competitors:** Vampire Survivors mobile's most-cited technical
complaint is framerate collapse with high enemy counts, and its original Android
build was *"so sluggish that very few people played it"*
([Pocket Tactics](https://www.pockettactics.com/vampire-survivors/review)). The
25-entity ceiling is a correct and citable instinct.

---

### 4. No onboarding at all, and class choice is a blind 9-way cycler written in keyboard. — VERIFIED

**Onboarding is zero.** An exhaustive sweep for `tutorial|how to play|hint|legend|
first_time|onboard|swipe|tap to|hold to` found exactly one piece of control
documentation in the project: `PauseMenu.CONTROLS_TEXT` (`PauseMenu.gd:20`), three
taps deep in Settings, entirely keyboard:

```
A / D  Move    W / Up  Jump    Space  Dash    LMB  Cast
1 / 2 / 3  Spells    RMB  Parry / Block
F  Melee    R  Blink    Q  AoE    T  Nova
```

Six of those verbs cannot be performed on a phone.

**Class selection:** `Lobby.gd:184-191` builds one button and one label;
`_cycle_class` (`:304`) steps `(_selected_class + 1) % 9`. No grid, no comparison, no
back-step — **eight taps to see the last class.** The label is **9 pt** in a 640×360
base viewport (`:189`).

And what it says is keyboard too. `ClassInfo.CLASSES` (`ClassInfo.gd:27-61`) gives each
class a `fantasy` string *and* a `kit` string. The lobby renders **only `kit`**
(`Lobby.gd:322`), deliberately, to keep the panel inside 360 px (`:318-321`). So the
player sees:

> `LMB arcane bolt · Q ArcaneStorm · Ult Meteor Sigil`

…and never sees `"Ranged arcane zoner"` — the one line that would help. Worse, four
classes advertise a **`Q`** (`ClassInfo.gd:31, 39, 41, 45, 49`) and `blast` has **no
touch affordance at all**. The card promises a button that does not exist on the device.

This is the same class of bug `ClassInfo.gd:8-13` was written to fix — cards promising
what the class does not have. It was fixed for spell *names* and is still live for
*bindings*.

**The genre's answer, from every competitor studied:** *don't offer the choice yet.*
Soul Knight ships with **only the Knight unlocked** — high HP, forgiving, explicitly
"very suitable for starting players"
([wiki](https://soul-knight.fandom.com/wiki/Knight)); 38 other characters are locked.
Otherworld Legends drops you **straight into a fight** as one fixed character
([Level Winner](https://www.levelwinner.com/otherworld-legends-beginners-guide-10-tips-cheats-strategies-to-beat-every-dungeon/)).
Archero and Vampire Survivors have **no class choice at all** — variety arrives as
in-run upgrade cards, so the player never faces a decision they lack the vocabulary for.

**Recommendation:** render `fantasy` instead of `kit`, rewrite kit strings
device-neutrally ("tap 1 / 2 / 3"), and consider defaulting to one class with the
cycler behind a "more" affordance. THE TOWER's per-floor pickups are structurally the
Archero model already — lean on in-run choice rather than a pre-run screen.

---

### 5. The mini-guardians are 6–13 second speed bumps wearing a boss's full ceremony. — MEASURED

I ran this repo's own `tools/floor_sim.gd`, which drives the **real** `Encounter`
against the **real** floor tables. Guardian-fight durations:

| Floor | dps 30 | dps 45 | dps 65 |
|---|---|---|---|
| 1 | 0:13 | 0:10 | **0:06** |
| 2 | 0:19 | 0:10 | 0:08 |
| 3 | 0:22 | 0:15 | 0:09 |
| 4 | 0:26 | 0:16 | 0:10 |
| 5 | 1:04 | 0:35 | 0:22 |

Against what the boss *does on arrival*: `Boss._play_intro()` (`Boss.gd:501-504`) sets
`BPhase.INTRO` for `INTRO_TIME = 2.6` s (`:20`), during which it **cannot attack**
(`:93` gates attacks on `_bphase != BPhase.INTRO`) — plus a camera pull, a name card
and a boss bar (`:494`, `:501-521`).

**On floor 1 at a competent damage rate the boss spends 2.6 s posturing and 6 s
fighting.** The ceremony is 30% of the encounter.

Worse: `Boss` has **three HP-gated phases** at 66% and 33% (`:18-19`) with escalating
cadence (`PHASE_CD`, `:22`). In a 6-second fight both thresholds are crossed in about
four seconds. **The multi-phase boss design — the best-built thing in the combat
layer — is invisible on floors 1–4.**

This follows from `boss_scale_for_type` giving non-BOSS floors 0.45×
(`Encounter.gd:557-566`). `Encounter.gd:61-65` records that `BOSS_BASE_HP` was already
raised 520→640 because floor 1's guardian was "a ~7-second speed bump". **It still is.**

**Recommendation:** either give it enough HP to reach its second phase (~2–2.5×), or
drop the ceremony on non-BOSS floors entirely — no intro card, no name, no bar, just a
big elite. Do not keep the ceremony without the fight.

---

### 6. The sword out-damages the magic. — VERIFIED (numbers) / PREDICTED (consequence)

Melee is free, unlimited, on a 0.34 s swing (`Hero.gd:57`), and arcs across multiple
bodies (`MELEE_ARC_DOT = 0.3`, `:42`). Damage: fists **14**, sword **26**
(`Hero.gd:58`, `:77-78`).

- **Fists: 14 / 0.34 = ~41 DPS.**
- **Sword: 26 / 0.34 = ~76 DPS.**

Now the spell kits. **The mana gate is gone** — confirmed at `Hero.gd:770-780`
(*"Mana no longer gates a cast"*), `:1848`, `:3382`; `mp_cost` survives only as a
sizing input for the cast sigil and as a `SpellTier` derivation input. So spells are
purely cooldown-limited:

| Class | 3-slot spell DPS, single target | + melee | Sword available? |
|---|---|---|---|
| Arcanist | 48/3.2 + ~80/6.0 + ~22/6.0 ≈ **32** | +41 fists | yes, floors 1–4 |
| Brawler | 62/3.4 + 58/4.0 ≈ **33** | +41 fists | yes |
| Shadowblade | 96/3.0 + 85/3.2 + 50/3.4 ≈ **73** | +41 | yes |

(Spell values from `SpellLibrary.gd:684-688`, `:1085-1101`, `:768-772`, `:784-799`,
`:702-705`, `:1004-1036`, `:804-807`.)

**Against a single target, the one sword lying on the floor (`GameState.gd:519`) is
worth more than an Arcanist's or Brawler's entire three-spell kit.** AoE closes the gap
in a crowd — but the single-target case *is the boss*, the one fight that is supposed
to matter.

**Predicted:** the optimal play on floors 1–4 for a caster is "grab the sword, hold
melee, use spells as garnish". In a game whose pitch is *absurd magic*, that is the
wrong dominant strategy. Note floor 5 has **no sword** (`_boss_layout`, `:711-715`),
so the finale silently plays by different rules than everything that taught you.

**Check in 10 min:** play Arcanist, grab the sword, and see whether you ever feel a
reason to cast.

---

### 7. Readability: the fighters render ~19 px tall while the buttons are 60 px. — VERIFIED (geometry) / PREDICTED (feel)

`Arena._apply_floor_camera` (`:167-172`) turns on `set_frame_all(true)` for **every**
floor. `CombatCamera._frame_group_update` (`:206-240`):

```gdscript
var span: Vector2 = (mx - mn) + FRAME_PAD          # FRAME_PAD = (300, 220)
var fit: float = minf(640.0 / span.x, 360.0 / span.y)
fit = clampf(fit, 0.5, 2.6)
```

Room is 960×480 (`LayoutDef.gd:14`), hero rig is **31 px** (`CharacterRig.gd:429`):

- **Alone:** span ≈ (300, 220) → clamps to `DEFAULT_ZOOM` 1.6 → hero ≈ 50 px.
- **Seven enemies spread out:** span ≈ (1000, 570) → `fit` ≈ 0.63 → **hero ≈ 19 px**
  on a 360 px viewport, ~5% of screen height.

In that same space a spell button is **60 px**, an `AbilityBar` slot **46 px**, the
pause button **44 px**. **The UI chrome is two to three times taller than the
characters.**

Two checkable predictions:

1. **Telegraph soup.** Enemy windups are 0.35–0.9 s (`Enemy.gd:108-185`) — generous
   and well-designed — but at 0.63 zoom, with up to 7 enemies plus the 8-effect
   ceiling plus bloom plus impact frames, the tells compete with the spectacle at a
   third of their authored size. "Dodge the tell" depends on seeing it.
2. **The camera pumps continuously.** `fit` is recomputed every frame from where
   enemies happen to stand, easing out at `FRAME_ZOOM_SPEED_OUT = 7.0` (`:32`). Across
   a wave the zoom swings ~1.6 → 0.6 → 1.6 as bodies spawn, spread and die — a
   **2.7× continuous oscillation** for the whole fight.

**Also: there is no screen-anchored health bar.** Player HP is a 30×4 px floating bar
over the hero's head (`Hero.gd:902-905` → `CharacterBars.gd:9-21`). At 19 px character
height that bar is smaller than a UI icon, in the middle of the chaos. Playdigious'
Dead Cells post-mortem is explicit on this: they moved health/currency to the
**top-left** because *"everything was at the bottom of the screen, and this doesn't
work well on mobile since players have their hands and fingers there"*
([Game Developer](https://www.gamedeveloper.com/design/porting-i-dead-cells-i-to-mobile-an-in-depth-breakdown)).

**And a third, which is structural rather than tunable: in a fixed one-screen arena,
the bottom corners are permanently dead space.** Brawl Stars can afford stick-left /
actions-right because its camera follows the brawler, so *the thing that matters is
always near screen centre*. A one-screen arena has no such guarantee — the bottom-left
and bottom-right of your play space sit under a thumb for the entire fight. Supercell
learned this the expensive way: they abandoned **portrait** orientation during beta
because *"all action and important information was covered with players' fingers"*
([Deconstructor of Fun](https://www.deconstructoroffun.com/blog/2018/5/11/bs)).
Practical options: inset the arena above the control band, keep spawn points and
telegraphed ground AoE out of the thumb zones, or accept the corners are cover-only.
The spawn-point rejection logic in `Encounter._pick_spawn_position` (`:825-847`)
already takes a rejection predicate — adding thumb-zone exclusion is cheap.

**Check in 10 min:** play floor 4 (46 bodies, cap 7), watch the zoom, then try to read
a bomber's fuse and your own health at the same time.

**Context:** frame-all was previously boss-floors-only and was made the default per
`docs/THE-TOWER-mobile-plan.md` step 1.3 to deliver "one screen". It delivers one
screen; the cost is character scale, and nobody has looked at it yet.

---

### 8. The reward cadence has two holes: rank dies on floor 1, and the boss fight is a reward desert. — VERIFIED

Reward cadence is mostly a **success** — see Part 3.2. Two specific holes:

**(a) The rank channel is exhausted in the first 40 seconds of the game.**
`Rank.TIER_POWER = [0, 6, 16, 32, 54, 84]` with `KILL_POWER = 3`
(`scripts/combat/Rank.gd:9, 14`). Floor 1 alone banks 27 kills × 3 = 81, plus 3 wave
clears × 6 = 18, plus streak bonuses ≈ **100+ power** — the top tier (84, "Ascendant")
lands around kill 28. Rank power **persists across floors and runs** and is never reset
(`GameState._live_rank_power:334-340`, `_restore_rank_power:345-350`, saved at `:292`).
**After roughly the first floor, the rank channel is permanently dead for the rest of
the game — and for every future run.**

**(b) The boss fight is the longest stretch with no reward event.** `Hype` pays out on
kill streaks (3 kills inside a 3.2 s window) and multi-kills (2 inside 0.7 s)
(`Hype.gd:38-54`). **Neither is possible in a 1v1.** There is no phase-transition
flourish and no chunk-of-HP beat. On floor 5 that is **~23 seconds of zero reward
events** — terminated by a **coin flip** on whether anything drops
(`TIER3_BOSS_CHANCE = 0.5`, `SpellDrops.gd:78`). If it says no, the climactic fight of
the entire tower pays out nothing at all.

**Recommendation:** give the boss its own beat vocabulary — a flourish on each phase
break (the hook already exists in `Boss._enter_phase`), and make the Tier 3 boss drop
guaranteed on the *final* floor at minimum.

---

### 9. The loot is identical on every climb, forever — and the in-flight floor generator does not change that. — VERIFIED

`SpellDrops._rng_for` seeds on the floor number and nothing else:

```gdscript
rng.seed = hash(Vector3i(SEED_SALT, floor_no, channel))
```
`SpellDrops.gd:159-162`, with `SEED_SALT` a compile-time constant (`:87`).

The file knows and defends this (`:44-47`) — it exists so co-op peers agree without a
packet, which is a good reason. But combined with `enter_run` re-climbing a conquered
tower from floor 1 (`GameState.gd:102-104`), the consequence is:

> **Every climb rolls the identical drops on the identical floors, forever.**

**The in-flight `FloorGen.gd` does not fix this.** It re-draws room proportion, ledges,
cover, spawn geometry, wave rhythm and palette from a climb seed — genuinely good work —
but `SpellDrops.gd` is **not modified** in the working tree. So after that lands, the
*room* varies per climb (solo) and the *loot* still does not. And `FloorGen`'s own
policy pins the seed to 0 in a live co-op session (documented in its header), so **in
co-op neither varies.**

There is a second, subtler problem. `SpellDrops.gd:28-29` reasons: *"a SPECIFIC Tier 2
signature is about 0.55 × 0.35 / 6 ≈ 3% per floor. You will see Petrify roughly once
every thirty floors."* **That assumes an endless tower.** This tower is five floors.
With a fixed salt, most of the six Tier 2 signatures are not *rare* — they are
**unreachable**, and the two or three that do land, land every single run. The scarcity
dial is set so tight it has stopped being a balance system and become a
content-deletion system.

**Cadence is fine; variety is zero.** Expected ~2.75 Tier 2 (0.55 × 5) + ~2.5 Tier 3
(0.5 × 5) ≈ **5 pickups per run**, about one per floor.

**Smallest honest fix:** mix a per-climb value into the drop seed (a climb counter in
`climber.json` would do) and ship it to the party once at `enter_coop_run` — exactly
the hook `FloorGen.climb_seed` already defines. That single change makes "seeded
randomisation" real for loot as well as rooms.

**One more:** `the_void` — a 260-damage ULT-weight nuke — has `SIGNATURE_MIN_FLOOR = 1`
(`SpellDrops.gd:84`), i.e. no depth gate. It is obtainable from the floor-1
mini-guardian, which has 190–288 HP.

---

### 10. The RETURN TO TOWN portal can end the run by accident, with no confirmation. — VERIFIED

Two portals spawn **simultaneously** on every non-final cleared floor
(`Arena.gd:297-321`) — a cyan one that advances the climb and a gold one that **ends
the run for the whole party** — and **neither has a confirmation.** A player who walks
the wrong way loses the session, on a phone, with a virtual stick, seconds after a fight.

`ExitPortal` also polls overlap every frame with no state check:

```gdscript
if _armed and not _taken:
    for body in get_overlapping_bodies():
        if body.is_in_group(trigger_group):
            _fire()
```
`ExitPortal.gd:53-57`.

**Partially resolved by accident.** In the old `downed` model a corpse lying on the
portal would fire it. The in-flight `GhostForm.enter` sets `collision_layer = 0`
(`GhostForm.gd:147`), so a ghost is invisible to the portal's `Area2D` mask and can no
longer trigger it — even though ghosts can steer. That is correct behaviour arrived at
**incidentally**, not deliberately: nothing documents it and no test pins it. One
future change restoring the ghost's collision layer re-opens it.

**Recommendation:** add an explicit `is_downed()`/ghost guard to `ExitPortal` plus a
regression test, and put a confirm (or a hold-to-activate) on the run-ending portal.

---

## Part 2 — Session shape: is the 4–7 minute floor target right?

This was the explicit open question. It is now answerable with data.

### What the game actually does — MEASURED

`tools/floor_sim.gd`, unmodified, default sweep. It drives the real `Encounter` over
the real floor tables; its hardcoded target window is 240–420 s (`:43-44`).

```
Floor 1  COMBAT  3 waves, 27 bodies    dps30 1:12   dps45 0:47   dps65 0:36
Floor 2  COMBAT  3 waves, 31 bodies    dps30 1:29   dps45 0:57   dps65 0:44
Floor 3  ELITE   4 waves, 34 bodies    dps30 1:40   dps45 1:06   dps65 0:46
Floor 4  COMBAT  4 waves, 46 bodies    dps30 2:13   dps45 1:16   dps65 1:05
Floor 5  BOSS    5 waves, 58 bodies    dps30 3:31   dps45 1:58   dps65 1:30

TOWER TOTAL      dps30 10:08   dps45 6:06   dps65 4:44
```

Every floor at every damage rate is flagged `OUTSIDE 4-7min`. **Dead air is 0.0 s
everywhere** — the pacing pass in `Encounter.gd` did its job completely.

The sim is optimistic by construction (enemy AI off, nobody kites, nobody dies), so
real floors run longer — but not 4× longer.

### What the competitors do — with sources

| Game | Unit closest to a "floor" | Whole run |
|---|---|---|
| **Archero** | one room **&lt;1 min**; a stage-block is ~4 rooms + boss | **2–10 min** |
| **Soul Knight** | one level (5–8 rooms) **~1–3 min** | ~15–20 min casual; **6:04 WR** |
| **Otherworld Legends** | one scene (~6–8 rooms) **~3–4 min** | **20–40 min** |
| **Vampire Survivors** | n/a (continuous) | **exactly 30:00** |
| **Dead Cells mobile** | biome ~5–10 min | **50–60 min** |

Sources: [Soul Knight Levels wiki](https://soul-knight.fandom.com/wiki/Levels) ·
[speedrun.com/soul_knight](https://www.speedrun.com/soul_knight) ·
[Archero design deep-dive](http://scottfinegamedesign.com/design-blog/2019/7/2/archero-part-1-gameplay) ·
[Deconstructor of Fun on Archero](https://www.deconstructoroffun.com/blog/2019/8/9/why-archero-banked-25m-but-leaves-25m-hanging-hlx9n) ·
[OWL Scenes wiki](https://otherworld-legends.fandom.com/wiki/Scenes) ·
[Gamezebo OWL review](https://www.gamezebo.com/reviews/otherworld-legends-review-mobile-hack-and-slash-done-pretty-well/) ·
[VS Stages wiki](https://vampire.survivors.wiki/w/Stages) ·
[Dead Cells run-length thread](https://steamcommunity.com/app/588650/discussions/0/3819655068771560434/)

Two of these are cautionary. **Dead Cells mobile's 50–60 minute run is repeatedly
named as the port's core design mismatch** — 148Apps: a loop *"designed for extended
play sessions feels demanding in mobile burst-play contexts"*
([review](http://www.148apps.com/reviews/dead-cells-review/)). **Otherworld Legends
draws the same complaint at 30+ minutes** — Steam reviewers cite *"runs requiring at
least 30 minutes or more"* against a **Mixed, 66% positive** rating
([Steam](https://store.steampowered.com/app/1761380/Otherworld_Legends/)).

### The reading — my recommendation

**The 4–7 minute target is being applied at the wrong level.** The whole five-floor
climb measures 4:44–10:08. A single floor at 4–7 min would make a run **20–35
minutes** — precisely the Otherworld Legends / Dead Cells band that draws
session-length complaints on mobile.

Meanwhile the measured run length sits almost exactly on **Archero's 2–10 minute
run**, which is the most successful session shape in this comparison set.

**Recommendation: reinterpret 4–7 minutes as the RUN length, not the floor length.**
The tables are then already close at the high-damage end and slightly long at the low
end. What is actually left to tune is not "make floors 4× longer" but:

- floors 1 and 2 are genuinely thin (0:36–0:47 at pace) — one more wave each;
- the **mini-guardian** is the real hole (#5) — fixing it adds 15–30 s of *good* time
  per floor rather than more trash;
- floor 5 at 1:30–3:31 is already the right shape for a finale.

If the maker does want long floors, the honest lever is **more waves**, never HP — and
`GameState.gd:495-500` plus `Encounter.gd`'s header already commit, correctly, to
never scaling trash HP with depth. Note the arithmetic: hitting 240 s at 45 DPS would
need **~163 bodies per floor** against the current 27–58, while the concurrent cap
still only holds 7 — a four-minute conveyor of seven enemies.

**The check that settles it:** play one full climb with a stopwatch. If ~6 minutes
feels like a satisfying session, the tables are right and the target is wrong.

---

## Part 3 — Fun and playability

### 3.1 The first sixty seconds — PREDICTED

`Lobby.tscn` (`project.godot:19`) → cycle a class blind → `CLIMB ▸` →
`GameState.enter_run()` (`:96-114`) → `Arena.tscn` on your **saved floor**.

Three things a new player meets:

1. **A class choice they cannot evaluate** (#4).
2. **No instruction whatsoever** (#4). On a phone: two floating sticks that only exist
   once you touch the screen, and six buttons labelled `JUMP`, `PARRY`, `DASH`, `1`,
   `2`, `3`. The `1/2/3` labels say nothing about what those spells do; the tooltip
   that would (`TouchControls.gd:640`) is hover-only and unreachable on touch.
3. **A fight that starts immediately** — and this part is **good**. Floor 1 wave 1 is
   deliberately `[7, 4, [A_CHASER]]` — *"pure pressure, nothing to read"*
   (`GameState.gd:609`) — a well-judged opener that teaches movement before reading.
   This is exactly the genre's own onboarding answer.

**One design note I would push back on:** `enter_run` resumes the **saved floor** and
never resets (`GameState.gd:100-105`). Correct for a persistent climb, but it means a
returning player's "first sixty seconds" can be floor 4, with a class they picked
weeks ago and no reminder of what it does. There is no loadout readout on the shipping
path — `LoadoutBar.gd` is instantiated **only** in
`scripts/spike/SpellPlaygroundController.gd:295`.

### 3.2 Reward cadence — the strongest part of the game, with two holes

`Hype.gd` is a purpose-built fast loop (`:1-31`), deliberately separate from the slow
`Rank` loop, with kill streaks on a 3.2 s rolling window and six named rungs
(`:42-50`), multi-kills inside 0.7 s (`:39`), close calls (`:57-60`), and wave
flourishes with a shout, camera punch, music swell and banked power.

Against the sim's floor-1 timeline at dps 45 (waves at ~6 s / ~17 s / ~32 s, then a
10 s guardian), a player gets a named beat roughly **every 8–9 seconds**, with streak
shouts continuously between them. **Measured dead air: 0.0 s on every floor.** The
endorphin bar is met.

For calibration, competitor cadence: Vampire Survivors fires an upgrade card every few
seconds early, tapering to ~10–30 s
([Level up wiki](https://vampire.survivors.wiki/w/Level_up)); Archero gives a
3-option card per level-up plus a **guaranteed angel every 10 rooms**
([Angels wiki](https://archero.fandom.com/wiki/Angels)); Soul Knight flags **one chest
room and one merchant room on every level map**
([Levels wiki](https://soul-knight.fandom.com/wiki/Levels)); Otherworld Legends
guarantees a shop, a secret room and a treasury per scene, where the treasury is often
a **pick-1-of-2 pedestal** — a forced choice, not a grant
([wiki](https://otherworld-legends.fandom.com/wiki/Treasury_rooms)).

**Where THE TOWER falls short of that bar is not frequency, it is agency.** Its one
pickup per floor is placed at **floor build time** (`FloorBuilder.build_props` →
`build_drop_economy`, `FloorBuilder.gd:46, 52-68`, called from `Arena._rebuild_room`
`:251`) — it is **lying on the ground before the first enemy spawns**. It is scenery,
not a reward: no beat, no sound, nothing earned. And collecting it is
`_on_body_entered` → `SpellGrant.apply` (`SpellPickup.gd:106-143`): **walk over it and
it is yours**, no prompt, no compare, no undo.

Plus the two holes in #8 (rank dead after floor 1; boss fight is a 23-second reward
desert).

**Cheapest wins, straight from the competitor set:** telegraph the pickup on arrival
(Soul Knight's map icon), and make at least one floor reward a **pick-1-of-2** (OWL's
pedestals) so the drop economy contains a decision at all.

### 3.3 The wave-design warning — the most directly applicable lesson found

Archero's most credible design critique is that its **wave rooms** are where the fun
breaks. Rather than the puzzle-like feel of discrete staged encounters, waves create
sustained pressure that *"devolves into simply dodging projectiles"* with no strategic
breathing room — flagged as a frustration-and-abandonment risk
([Scott Fine](http://scottfinegamedesign.com/design-blog/2019/7/2/archero-part-1-gameplay)).

**THE TOWER is explicitly "escalating waves until a boss spawns", and it has
deliberately engineered the breathing room *out*.** `Encounter.gd:7-35` is candid about
this: waves now OVERLAP (a wave hands off at its last few bodies, not an empty room),
open with a VANGUARD burst, and the old 1.5 s break became a 0.85 s "SURGE, not
BREAK" — *"it exists to let the flourish and the next wave's announce land, not to
give anyone a rest."*

That was the right fix for the problem it addressed (dead air, now 0.0 s). But the
competitor evidence says the opposite failure — **unrelenting pressure with no lull** —
is this genre's known killer, and Archero's own design keeps *"a lull that lets players
rest for a bit before challenging the next room."*

**Prediction: the pacing pass has overcorrected.** The honest test is to play it and
ask "did I ever get a breath?" rather than "was there dead air?". `DEFAULT_SURGE`
(`Encounter.gd:83`) and `HANDOFF_ALIVE_FRACTION` (`:86`) are the two dials, both
one-line changes.

### 3.4 Difficulty and failure feel — being fixed as this audit ran

**This was my #2 finding and it has been overtaken by in-flight work.** Recording both
states, because the new code is uncommitted and could still change.

**What was true at HEAD (`3da149c`) — VERIFIED:** `Hero._die` (`:3737-3753`) branched
co-op → `_enter_downed()`, solo-in-run → `GameState.fall()` (drop one floor, full
heal), sandbox → reset. `end_run(true)` was **never called from anywhere** — all three
callsites pass `false` (`GameState.gd:163`, `:237`, `:246`) — so there was **no game
over at all**, and the `died` branches at `:421`, `:437-444` were unreachable dead
code. In co-op, `downed` had **no timer, no revive verb and no UI**; you got up only
when your teammate cleared the whole floor or also died.

**What is now in the working tree — VERIFIED, uncommitted:** `DeathRules.gd`,
`GhostForm.gd`, `Revive.gd`, plus ~200 changed lines in `Hero.gd` and ~99 in
`Arena.gd`. The design:

- Death costs **a life, not a floor**; you become a **ghost** that still steers but
  cannot hit or be hit (`GhostForm.enter` drops the hero from `mortal` and its faction
  group and sets `collision_layer = 0`, `:143-148`).
- A teammate revives you with a **2.0 s channel at 92 px range**
  (`Revive.gd:62-70`), with a progress ring, a tether, an on-screen prompt and a
  **touch pad** (`:76-96`) — so it works on a phone.
- Revive returns you at **45% HP**, never full — with an explicit rationale that at
  1.0 *"the correct play becomes suiciding into the boss to top up"*
  (`DeathRules.gd:102-106`).
- Everyone down = **game over**, with a 2.4 s hold card (`:93`).
- Solo death ends the run immediately, with a `SOLO_SELF_REVIVE_CHARGES` knob defaulted
  to 0 and a documented argument for why (`:20-49`).
- A wipe **keeps the persistent climb** (`RESET_CLIMB_ON_GAME_OVER = false`, `:76`),
  consistent with the maker's earlier locked call.

**Assessment: this is good work and it closes the largest design hole in the game.**
The policy forks are surfaced as named constants with the reasoning written down, which
is exactly right for numbers nobody has felt yet.

**Three things to check when it lands:**
1. **The game-over card routes into the parked hub — VERIFIED, and it is the one thing
   this work makes worse.** `game_over()` → `end_run(true, died_on)` → `_change_scene(HUB_SCENE)`
   (`GameState.gd:272-285`). Because solo death now ends the run immediately instead of
   bouncing a floor, a new player reaches the old v0.0 AI-NPC town **on their first
   death**. Fix the scene target in the same change that lands the death rule, or this
   feature ships a regression. See #1.
2. **`fell`, `fall()` and `fall_floor()` are deleted** (documented in the new
   `GameState.gd` header). `_falls` survives purely as a death counter for the hub NPCs
   — which are in the parked hub. Worth confirming that counter still has a consumer
   the player ever sees.
3. **The `ExitPortal` guard is incidental, not explicit** (#10 / B2).

**And three gaps in the new design itself, each with a directly applicable precedent —
VERIFIED absent in the working tree:**

**(a) The ghost has no countdown.** Grep of `GhostForm.gd` finds no bleedout, no
timer, no expiry (`HAUNT_TIME = 0.36` is a VFX flash, not a clock). A ghost is
unbounded until a teammate walks over. The most on-point source found is a developer
who surveyed **exactly this genre** (co-op roguelikes — Lost Castle, Spelunky, Enter
the Gungeon, Rampage Knights) and shipped a **20-second countdown**, 60 s for bosses:

> *"The timer also removes the boring parts. If a player dies he knows that in 20
> seconds he will either be revived or a new game will start."* … *"The possibility of
> the countdown timer makes the players care about each other more."*
> — [Bigosaur, Designing death in co-op roguelikes](https://bigosaur.com/blog/165-soaw-death)

He also names the failure mode THE TOWER currently has — teammate-only revive with no
clock causes *"skilled players to neglect combat while babysitting less-skilled
allies"*. **Your worst case is a player going down 20 seconds into a floor and being
inert for the rest of it.** Note the in-flight code already does the cheaper half of
the fix: `Arena.gd:419-422` stands ghosts back up on floor clear — Soul Knight's exact
solution. A countdown would close the rest.

**(b) There is no invulnerability on revive, and no protection for the reviver.**
`DeathRules` returns you at 45% HP with no grace window (grep for
`invuln|immune|GRACE` across `DeathRules.gd`, `Revive.gd`, `GhostForm.gd` returns
nothing), and `Revive.CANCEL_ON_DAMAGE = false` (`:72`) means the reviver stands still
for **2.0 seconds** while remaining fully killable. **With friendly fire always on in a
fixed one-screen arena, the revive is now the most abusable moment in the game.** Every
comparable game protects it: Soul Knight gives **2 s invincibility** on revive; RoR2's
Dio's Best Friend gives **3 s**; Gunfire Reborn's *Benevolence* keeps the reviver's HP
*"never below 1"* during the channel. Also worth weighing: Nintendo's bubble pop is
**one touch**, not a 2-second hold — a hold is a long time to stand still next to
someone who can hit you.

**(c) The game does not get easier when you go down.** Cuphead reverts its co-op
scaling (2× boss HP, 0.5× player damage) *"as soon as one player dies… until they get a
parry revive"* ([Steam](https://steamcommunity.com/app/268910/discussions/0/3277925755434832969/)).
THE TOWER's wave budgets and caps are fixed per floor and do not read hero count or
downed state — so the survivor faces a two-player floor alone, which is precisely the
death spiral that turns "go rescue them" into "we both lose". Gunfire Reborn, which
does *not* shed difficulty, produced reports of 40-minute solo-survivor boss fights.

**One last verb gap:** the ghost can steer and nothing else. Enter the Gungeon gives
its ghost a **reusable mini-blank on a short cooldown** (blue when ready, grey when
not) — non-damaging, un-stealable, and it creates plays ("blank *now*"). Spelunky 2's
ghost blows a **gust that shoves enemies**. Either would reuse VFX and cooldown UI THE
TOWER already has, and turn dead time into participation.

Once it lands, the underlying difficulty design is sound: eight archetypes with
distinct generous telegraphs (0.35–0.9 s, `Enemy.gd:108-185`), and escalation authored
as **composition** rather than HP — every floor runs `hp_multiplier = 1.0`
(`GameState.gd:695`). That is the right call, executed consistently, and it finally has
a consequence attached to it.

### 3.5 Friendly fire: funny or infuriating? — PREDICTED

**Predicted: neither at first — invisible.** Because the game does not acknowledge it
(#2), the first several friendly-fire deaths will read as *"I don't understand what
killed me"*, not as comedy. **Comedy needs attribution.**

The thing that decides funny-vs-infuriating is the *recovery time*, and the in-flight
revive work (3.4) is what makes that survivable: being killed by your friend is funny
if you are back in ten seconds and someone has to walk over and pick you up. It is
infuriating if it is unbounded. That fix is landing; the acknowledgement is not, and
it is one bark table entry.

### 3.6 Is 2-player better than solo? — PREDICTED

**At HEAD: no** — solo was strictly better, because solo death was a one-floor bounce
with a full heal while co-op death was unbounded. **With the in-flight work: yes,
structurally** — co-op now has an exclusive verb (revive) that solo cannot use, and
`DeathRules.gd:33-37` reasons about that deliberately (*"it dilutes the thing that gives
co-op its shape: that the only way back up is another person"*). That is the right
instinct.

What still limits it: the one mechanic that makes co-op *interesting* beyond revive —
the spell handoff (`SpellHandoff.gd`, surfaced on touch as `GIVE <SPELL>`) — has ~5
drops per run to work with, all of them identical every climb (#9). Note also
`SpellHandoff.gd:145-157` records that this mechanic **never once worked in a real
game** until recently, so it has essentially zero play time on it.

The co-op **engineering** is genuinely impressive — victim-authority damage routing,
host-authoritative enemies, replicated hero spells, boss phases crossing the wire, LAN
beacon discovery with a manual-IP fallback (`Lobby.gd:222-233`). The plumbing is done.
What was missing was the **social design layer**, and it is now half-built: revive is
landing, acknowledgement is not.

### 3.7 Touch — better than the brief assumed — VERIFIED

Touch is **not** four verbs short of a stick-and-three-buttons. `TouchControls.gd`
ships twin floating sticks, six buttons, and a contextual pad:

| Control | Action | Rect (base 640×360) |
|---|---|---|
| left floating stick | `move_*` (+ duck past 0.6) | spawns anywhere `x < 288` |
| right floating stick | `aim_*`, holds `cast` past 0.55 | spawns anywhere `x > 352` |
| `JUMP` | `jump` | x 14–68, y 244–298 |
| `PARRY` | `parry` | x 14–66, y 182–234 |
| `DASH` | `dash` | x 568–624, y 290–346 |
| `1` / `2` / `3` | `spell_1/2/3` | 60 px each, on a 126 px thumb arc |
| `HandoffPad` | `talk` (give a spell) | x 264–376, y 296–330, contextual |

Cites: `TouchControls.gd:73-97`, `:439-455`, `:462-464`, `:184-194`.
`tools/slice_test_touch.gd:150` pins the count at 6.

Aiming is a **real decoupled right stick** (`publish_aim` `:400-406` →
`Hero.gd:1210-1215`, single deadzone owner `TOUCH_AIM_DEADZONE = 0.20` at
`Hero.gd:196`), and **lifting the thumb holds the last aim** so flicking to a spell
button does not fling the shot. That is genuinely good design. A thumb-reachable pause
button exists (`PauseMenu.gd:95-130`), so Settings is reachable on a phone.

**Against the competitor bar, 3 spells + stick is at or below the safe ceiling.** Dead
Cells shipped jump + dodge + 2 weapons + 2 skills + potion + interact + menu and drew
*"far too many tiny buttons… it's nigh impossible to activate more than one ability at
a time"*
([Gamezebo](https://www.gamezebo.com/reviews/dead-cells-mobile-review-how-does-the-souls-like-metroidvania-hold-up/))
plus hand-cramp complaints ([NME](https://www.nme.com/reviews/game-reviews/dead-cells-review-a-good-mobile-port-of-an-excellent-roguelike-game-2699135)).
Otherworld Legends ships attack + dodge + 2 skills and still draws "clunky".

**What is actually missing:** `melee`, `blast`, `blink`, `nova`, plus mid-fight
`cycle_element` / `switch_class`. `TouchControls.gd:35-46` owns this as a deliberate
trade. Defensible — except (a) class cards still sell `Q` (#4), and (b) `blink` is the
mage get-out, so a phone Arcanist has **no escape verb** while a phone Brawler keeps
its full kit through `cast` (`Hero._cast()` `:2615-2629` routes per-class).

**Two unadopted lessons from Playdigious' Dead Cells post-mortem** — the richest
touch-porting source found
([Game Developer](https://www.gamedeveloper.com/design/porting-i-dead-cells-i-to-mobile-an-in-depth-breakdown)):
- their playtests split **80% floating stick / 20% fixed**, so they shipped **both**;
  THE TOWER ships floating only.
- they shipped **move-and-resize customisation for every button** because *"no single
  layout worked universally"*; THE TOWER's layout is fixed constants.

**And the thing that blocks all touch judgement:** `Arena.gd:605` constructs
`TouchControls.new()` with no way to set `force_visible` (`TouchControls.gd:67`) — no
exported flag, no CLI switch, no debug key. Adding that one-line seam is the cheapest
item in this entire audit.

### 3.8 On auto-aim — the one locked decision I will question once

The locked rule is no auto-aim, with an assist slider shipping at 0
(`PauseMenu.gd:346-364`), and a regression test asserting the deleted `Targeting`
helper stays deleted.

**The competitor evidence is unanimous in the other direction, and it is worth stating
once.** Soul Knight's auto-aim is **mandatory** and is credited as the reason the game
is not frustrating; TouchArcade: *"Targeting is done completely automatically… letting
you focus on dodging bullets and enemies"*
([review](https://toucharcade.com/2017/03/10/soul-knight-review/)). Archero auto-fires
at the nearest enemy whenever you stand still, and *"splitting the controls between the
player (movement) and the game (shooting) gives the player the right amount of control
and agency"* ([Deconstructor of Fun](https://www.deconstructoroffun.com/blog/2019/8/9/why-archero-banked-25m-but-leaves-25m-hanging-hlx9n)) —
and it still produced a ~20% skill-expression tech. Vampire Survivors automates
attacks entirely. Dead Cells' opt-in **Auto-Hit** *"became by far the team's favorite
control option"*. Otherworld Legends makes it a toggle — and its reviewers say its
**ranged characters are the weak point precisely because there is no manual aim**
([Frank Gamer](https://frankgamer.com/2023/08/01/otherworld-legends-review-button-mashing-fun/)).

**However — the decision is defensible on its own terms, and I would keep it.** The
spec's actual rule is *"no spell's fun should depend on precise aiming"*, and THE TOWER
satisfies it structurally through **aim-forgiving shapes** (cones, novas, zones,
`bolt_burst`, `bolt_spread`) rather than through targeting assistance. That is a real
and coherent alternative, and the decoupled right stick (3.7) is a better input than
Soul Knight's "aim by walking that way", which TouchArcade itself calls *"awkward"*.

**My only concrete recommendation:** the assist slider already exists and is inert.
Otherworld Legends' *"Track & Target"* toggle is the proven shape. Making the slider
actually do something — off by default, available to players who want it — costs
nothing and reverses no decision. Moving on.

---

## Part 4 — Completeness: what a player will notice is missing

**Blocking a first play:**

1. **No victory screen / run summary** — #1. `GameState.build_outcome` (`:390-406`)
   already captures everything a results card needs.
2. **No route back to the title screen** — #1.
3. **Death / game-over screen** — being built now (3.4); verify where it routes.

**Noticeable, not blocking:**

4. **No loadout readout in the real game.** `LoadoutBar.gd` is wired only into the
   spike playground (`SpellPlaygroundController.gd:295`), and on touch `AbilityBar`
   stands down entirely (`AbilityBar.gd:110-119`) — so a phone player cannot see what
   their three spells *are*, only three buttons labelled 1, 2, 3. This also means
   **desktop and phone show different information**, and the maker will be play-testing
   desktop.
5. **No persistent wave counter** — only transient shouts (`Hype.gd:184-209`). On a
   4-wave floor you cannot tell how much is left, which is exactly the "how close am I
   to the boss" question. Soul Knight's answer — flag it on the map — is the cheap one.
6. **No key rebinding.** Confirmed absent; low priority for mobile-first.
7. **`FloorType.PVP` is a live enum value** (`FloorDef.gd:7`) with a scale entry
   (`Encounter.gd:563-564`) in a game whose spec says there is no PvP. Vestigial;
   delete so it cannot be built against.

**Housekeeping / risk:**

8. **Music licensing — partially recorded, and better than the brief suggested.**
   `assets/audio/CREDITS.md` §4 flags all six MP3s as licence-unconfirmed and the
   credits screen names the gap under "UNSETTLED" (pinned by
   `tools/slice_test_shell.gd`). **But provenance is not entirely absent:**
   `docs/v2.0-climb-checklist.md:60` records that *For Tomorrow* (Savfk) and
   *Unexplored Moon* (Miguel Johnson) are royalty-free, and names the boss track as
   *Shores of Avalon*. So the outstanding set is **three tracks** — `arcadia`,
   `lord_of_the_land`, and the boss theme — not six. Worth consolidating that line into
   `CREDITS.md` so the two documents stop disagreeing.
   The SFX side is properly documented: Sonniss GDC bundle royalty-free without
   attribution, TomMusic flagged unconfirmed, Pepper Sound Pack's attribution
   discharged on the credits screen (`CREDITS.md` §1a–1c, §5).
9. **Music is 36.4 MB of a ~45 MB audio payload** (`docs/mobile-export.md` §5).
   `python-tools/compress_music.py` exists and has never been run (needs ffmpeg).
   ~17–20 MB saving, ~40% of the shipping payload.
10. **No Android build has ever been made** — #3.
11. **`hollow_purple` is lower risk than logged.** It survives as an internal
    identifier (`ReactionOutcomes.gd:179-180`) but grep shows **no player-facing
    string** — it is absent from `SpellLibrary.gd`. Rename when convenient; not a ship
    blocker.
12. **No run-all test harness.** 115 suites in `tools/`, one process each.
    `docs/THE-TOWER-mobile-plan.md:335` estimated an hour; still not done, and with
    five agents committing concurrently it is now worth more than an hour.
13. **`data/towers/ashspire.tres` does not exist.** `GameState.TOWER_PATH` (`:89`)
    points at it, so `_load_or_build_tower` (`:119-124`) always falls through to the
    code table. The data-driven authoring path is entirely unexercised — worth knowing
    before anyone plans content work against it.

---

## Part 5 — Bugs found (write-ups only; nothing was edited)

| # | Severity | Bug | Cite | Repro |
|---|---|---|---|---|
| B1 | **High** | Two portals with opposite consequences spawn together, no confirmation; the gold one ends the run for the party | `Arena.gd:297-321` | Clear any non-final floor, walk into the gold one |
| B2 | **Medium** | `ExitPortal` has no downed/ghost state check; currently saved only *incidentally* by `GhostForm` setting `collision_layer = 0`, which nothing documents or tests | `ExitPortal.gd:53-57` vs `GhostForm.gd:147` | Restore a ghost's collision layer and it returns |
| B3 | **Medium** | At HEAD, `end_run(true)` is never called → `died` branches are unreachable dead code (being addressed by the in-flight death work) | `GameState.gd:163`, `:237`, `:246` vs `:400-401`, `:421`, `:437-444` | Static |
| B4 | **Medium** | Party-wipe check runs only on a co-op host in run mode; a co-op session not in run mode leaves both players down forever | `Arena.gd:134-137`, `:386-387` | Latent; not reachable via `enter_coop_run` |
| B5 | **Low** | Comment rot: four files document a 2-floor fall; the code drops 1 (and the in-flight work drops 0) | `Hero.gd:3738`, `GameState.gd:213`, `Net.gd:424`, `docs/v2.0-coop-and-boss-checklist.md:30` | Static |
| B6 | **Low** | `TouchControls` is `PROCESS_MODE_ALWAYS` and is not hidden on pause — sticks may keep publishing actions behind the pause menu | `TouchControls.gd:239-240` | Needs a device |
| B7 | **Low** | Pause button rect (x 586–630) sits inside the aim-stick zone (x > 352); tap consumption order untested | `PauseMenu.gd:95-130` vs `TouchControls.gd:297`, `:339-341` | Needs a device |
| B8 | **Low** | `Arena.gd:605` constructs `TouchControls` with no way to set `force_visible`, so touch cannot be previewed on desktop without a source edit | `Arena.gd:605`, `TouchControls.gd:67` | Static |

---

## Part 6 — Things that are right, and should not be touched

An audit that only lists problems invites breaking what works.

- **The wave pacing pass.** Vanguard bursts, overlap handoff, loud surge beat
  (`Encounter.gd:7-35`). Measured dead air: 0.0 s on every floor. It solved the problem
  it set out to solve. (See 3.3 for the one caveat.)
- **Escalation by composition, never HP.** Held consistently across the authored tower,
  the synthesized fallback, and the in-flight `FloorGen` — which explicitly refuses to
  write an HP multiplier and has a suite that fails the build if one appears.
- **`Hype` as a fast loop separate from `Rank`.** The reasoning at `Hype.gd:6-13` is
  right and the implementation matches it.
- **The friendly-fire mechanism** — one group, one line, zero spectacle edits
  (`SpellCaster.gd:81-115`). Only the *feedback* is missing.
- **The touch aim stick**, including thumb-lift-holds-aim (`Hero.gd:1191-1192`).
- **Enemy telegraph budget** — 0.35–0.9 s, generous, per-archetype.
- **The boss multi-phase design** — which is exactly why #5 (nobody sees it on floors
  1–4) matters.
- **`DeathRules.gd`'s shape** — policy forks surfaced as named constants with the
  argument written down, for numbers nobody has felt yet. This is the right way to ship
  an unplaytested decision.
- **`FloorGen.gd`'s constraint discipline** — identity fixed, expression redrawn, purity
  enforced for co-op, and honest in its own header about pinning the seed in co-op.
- **`docs/mobile-export.md`.** It corrects its own earlier numbers, names two harness
  bugs that made prior measurements worthless, and refuses to claim the GPU cost it
  cannot measure.

---

## Part 7a — The chassis and the soul disagree about friendly fire

Worth stating on its own because it is the deepest tension in the design, and it is not
resolvable by tuning.

**Wizard of Legend — the combat chassis this game is built on — ships local co-op with
friendly fire OFF.** Contingent99's stated reason is that with it on, *"the game doesn't
make things impossible for players"*
([Worthplaying](https://worthplaying.com/article/2018/12/3/reviews/111988-pc-review-wizard-of-legend/)).
Magicka — the co-op soul — is built entirely around FF being on. The difference is
**tempo**: Magicka is slower and cast-command-based, so every spell is a deliberate
decision you can be blamed for. WoL is dense, fast, arena-bound and full of large AoE.

THE TOWER currently has **WoL's tempo and Magicka's friendly fire.** That is the
combination neither game shipped. It is not necessarily wrong — but it means the FF
dial (#2a) is not a nice-to-have, it is the instrument for finding the tempo at which
both can coexist.

Two supporting warnings from the same two games:

- **WoL's own mobile port** draws exactly the complaints this audit predicts from code:
  the pace *"feels a bit too hectic for the game's unwieldy touch controls"*
  ([148Apps](https://www.148apps.com/wizard-of-legend/review/)), and **"visual clutter
  during intense combat makes it hard to track incoming attacks"**
  ([TapTap](https://www.taptap.io/post/6473734)) — independent confirmation of finding
  #7 from the closest existing test of this chassis on a virtual stick.
- **Stick Fight** — the skin — has 94% of 52,614 reviews, and its loudest *negative* is
  literally *"fun with friends but i have no friends"*
  ([Steam](https://steamcommunity.com/app/674940/negativereviews/?browsefilter=toprated)).
  It has no single-player mode. **THE TOWER does have solo, and should keep it
  first-class** — that is a genuine advantage over its own reference point, and it is
  the reason finding #1 (solo death routing into the parked hub) matters so much.

One more from Stick Fight worth internalising: its rounds last **~5 seconds to a
minute**, and *"the game has such a rapid turnaround that it's hard to get mad"*
([Nintendo World Report](https://www.nintendoworldreport.com/review/56733/stick-fight-the-game-switch-review)).
**The round is the unit of forgiveness.** THE TOWER's equivalent unit is the floor, and
the in-flight "clear a floor and your ghost stands up" rule is exactly the right
instinct.

---

## Part 7b — The four most important competitor lessons

1. **Your run length is right; your floor target is wrong.** The measured 4:44–10:08
   climb sits on Archero's 2–10 minute run, the most successful shape in the set. A
   4–7 minute *floor* would put the run at 20–35 minutes — the exact band where
   Otherworld Legends (Mixed, 66%) and Dead Cells mobile draw explicit
   session-length complaints. Reinterpret the target at the run level.

2. **Waves with no lull are this genre's known killer.** Archero's wave rooms are its
   most credible design criticism — sustained pressure that *"devolves into simply
   dodging projectiles"*. THE TOWER is a wave game that has deliberately engineered
   the lull *out* (`Encounter.gd:7-35`, dead air now 0.0 s). That was right for dead
   air and may be wrong for fatigue. Play it and ask "did I get a breath?", not "was
   there dead air?".

3. **Nobody in the genre makes a new player choose a class.** Soul Knight unlocks one
   character. Otherworld Legends drops you into a fight as a fixed one. Archero and
   Vampire Survivors have no class choice at all and move all build decisions *inside*
   the run, where an icon and one line can explain them. THE TOWER offers nine, blind,
   at 9 pt, described in keyboard bindings that do not exist on the device — and it
   already has the per-floor pickup system that is the genre's actual answer.

4. **Nobody ships "all dead = game over" as a default, and the wipe is not the risky
   part — the dead time before it is.** The one game that implements the rule verbatim
   is RoR2's *Artifact of Death*, which is **opt-in** and cancellable by a revive item
   ([wiki](https://riskofrain2.wiki.gg/wiki/Artifacts)). Deep Rock Galactic's phrasing
   is the model: the mission fails when all are down **"unless some possibility of
   revival is available"**, with a 10-second grace window that turns a wipe into a
   contested heroic moment. THE TOWER's wipe rule is fine; what it needs is a **ghost
   countdown** (3.4a), **a protected revive** (3.4b), and **difficulty that sheds when
   you are down a player** (3.4c).

**One number that reframes your session length:** Supercell rebuilt an entire engine
because *"the loading time had started deciding when people could play"* — cutting
Android load from 35 s to 5–6 s, after which *"Android behaviour moved closer to iOS:
shorter sessions, more often"*
([Supercell](https://supercell.com/en/news/titan-game-engine/)). **Your session unit is
not floor length — it is pairing time plus floor length**, and local-wifi pairing is
your loading screen. If discovery-to-fighting takes 45 seconds, that is the number to
attack first, ahead of any floor tuning.

**One hazard worth internalising:** Soul Knight's forced always-online since v8.1.0
dropped its recent weekly rating from a 4.59 lifetime average to **3.5**, with
mandatory internet as the #1 complaint theme
([marlvel intel report](https://marlvel.ai/intel-report/games/soul-knight)). A
local-wifi co-op game must work fully offline in single player. THE TOWER does —
`Net.is_active()` correctly excludes Godot's `OfflineMultiplayerPeer` — keep it that way.

---

## Part 8 — The shortest path to a playable first session

If only three things get done before the maker next plays:

1. **Change one scene target and add a results card.** `end_run` →
   `_change_scene(HUB_SCENE)` (`GameState.gd:285`) is now the exit from **winning, losing
   and quitting alike**, and it points at the parked v0.0 AI-NPC hub. Point it at
   `Lobby.tscn` with a summary card in front (the data is already in
   `build_outcome`), and gate or confirm the `RETURN TO TOWN` portal. This is finding
   #1 plus bug B1, and it is urgent specifically **because** the death work is landing:
   solo death now ends the run instantly, so this path goes from rarely-hit to
   hit-on-your-first-death.
2. **Make friendly fire audible.** One bark category, one damage-number tint. Finding
   #2. Cheapest high-value item in the audit, and it is the mechanic the game is
   named after.
3. **Protect the revive, and put a clock on the ghost.** Two constants and a timer:
   invulnerability on revive, the reviver unkillable during the 2 s channel, and a
   visible countdown so a downed player knows what is about to happen. With friendly
   fire always on, an unprotected revive in a fixed arena is the most abusable moment
   in the game — and an unbounded ghost inside a multi-minute floor is the largest
   dead-time exposure in the design. See 3.4a–b.

4. **Add the `force_visible` seam** (B8) so touch can be judged at all, then **build
   the APK and put it on a phone** (#3).

Everything else on this list can wait for a playtest to confirm it.

---

*Audit performed read-only. The only file created was this document; no `.gd`, `.tscn`
or `.godot` file was modified. The one harness executed was `tools/floor_sim.gd`
(read-only simulation) and `tools/release_gate_dev_bridge.gd` (read-only check).*
