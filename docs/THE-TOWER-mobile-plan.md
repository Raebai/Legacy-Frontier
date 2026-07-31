# THE TOWER (mobile) — synergy map + build steps

Written 2026-07-31 against branch `stickman-integrate`, after a full audit of the
296-script Godot project. Input: the mobile game spec ("A co-op arena brawler for
mobile. Stick figures with absurd magic…").

**Governing constraint from the maker: use as much of what already exists as
possible. We build ON this stack, not beside it.** Every step below is written as
*reuse / rewire / policy-flip* wherever that is honestly possible, and flags the
handful of places where it genuinely is not.

**Headline:** roughly **75% of the spec is already built.** The combat feel, the
spell system, the boss, the co-op spine, the touch controls, the floor loop, the
audio roster — all exist and are headless-tested. What is missing is mostly
*plumbing between built things* plus one genuinely absent workstream (mobile
export/performance, which has never been attempted even once).

The two largest single risks are **not** gameplay features. They are:

1. **Hero spells are not replicated at all.** In co-op your teammate's magic is
   invisible on your screen. Friendly fire — the spec's entire social engine —
   cannot be funny if you cannot see the thing that killed you.
2. **No mobile build has ever been made.** Not a failed one. Zero.

---

## Part 1 — SYNERGIES: what the spec asks for vs what is already here

### Tier A — already built, needs only rewiring or a constant change

| Spec requirement | What already exists | The move |
|---|---|---|
| One caster runs any spell | `SpellCaster.cast()` + `SpellDef` Resource + 20 `Kind` shapes + 28 spells in `SpellLibrary.build_all()` | Nothing. This *is* the spec's architecture, already shipped. |
| Spells are data | `SpellDef.gd` is fully `@export`ed and `.tres`-authorable | Optional polish only. Adding a spell that reuses a `Kind` is 2 edits today. |
| Cooldowns, not mana | Both implemented (`Hero.gd:1460-1469`) | Gate off the `mp` check. Keep the field; it costs nothing. |
| Tier 1 = class kits, 3 spells, short CD | `CLASS_KITS` (`SpellLibrary.gd:85-155`), 9 classes × 5 roles | Trim 5 roles → 3 buttons. Data edit. |
| Big spells loud/committal/answerable | `SpellTier` (QUICK/HEAVY/ULT) derived from cast_time/cooldown/mp; every attack spell is deflectable; `ParryRing` | Nothing. Already the locked design. |
| Rarity is the balance system | `SpellTier` doubles as clash weight | Reuse as the drop-rarity gate. |
| Boss with phases + telegraphs | `Boss.gd` — Ashspire Guardian, 3 HP-gated phases, intro card, boss bar, 8 attacks | Reuse wholesale as boss #1 of 4. |
| Mobs reuse the player controller | `BotController`/`BotBrain`/`BotIntent` already drive real `Hero` bodies in `VersusArena` | Already solved — see the decision note below. |
| Local co-op, host-authoritative | `Net.gd` — ENet, 2 `MultiplayerSpawner`s, 2 `MultiplayerSynchronizer`s, victim-authority damage routing, 2-process smoke test | `MAX_PLAYERS: 4 → 2` (`Net.gd:19`). |
| Two thumbs, landscape, floating sticks | `TouchControls.gd` — twin-stick, 8 buttons, 12 headless tests, gated on `is_touchscreen_available()` | Trim 8 buttons → 3 spells + dash. Wire into the real boot path. |
| Floor state machine + ascend/descend | `Arena.gd` + `Encounter.gd` + `GameState` (persistent floor, portals, fall-on-death) | Fall depth `2 → 1` (`GameState.gd:500`). |
| Barks over a character's head | `SpeechBubble.gd` (137 lines) | Reuse verbatim. It outlives the NPC stack that spawned it. |
| Authored floor redraw at phase change | `Boss._enter_phase()` already retints, escalates aura, fires `epic_moment` | Extend the same hook. No new system. |
| Audio | `Sfx.gd` — 248 keys, 230 files, **a real 32-voice pool**; `Music.gd` — 3 moods, 7 tracks, crossfade + ducking | Reuse. Needs a mix pass by ear, not code. |
| Settings menu | `PauseMenu.gd` — volume, zoom, shake, hit-stop, injectable rows | Reuse; add rows. |
| Title / co-op screen | `Lobby.tscn` + `Lobby.gd` — Play Solo / Host / Join / class picker / peer list | **Already written and orphaned.** Point `main_scene` at it. |

### Tier B — built, but pointed somewhere else

| Spec requirement | What exists | Where it currently points |
|---|---|---|
| One-screen arena | `CombatCamera.set_frame_all(true)` — fit-everything framing | Used on **boss floors only** (`Arena.gd:144-148`). Make it the default and the arena becomes one screen for free. |
| Per-spell cooldowns | `HandSlots.gd` has real per-slot cooldowns (`:139-159`) | Spike playground + HUD only. `Hero` still runs **one shared cooldown bank** (`Hero.gd:334`). Wiring `HandSlots` into `Hero` is the single highest-value reuse in the repo. |
| 3 spell buttons | `LoadoutBar.gd` draws the slot bar with per-kind glyphs | Playground only. |
| Floor variety without new art | `DestructibleTerrain`, `BreakablePlatform`, `RuinPlatform`, `ArenaTerrain`, `StageHazard` (pits/ring-out) | **All built, all wired only into `VersusArena`.** The tower arena is a bare 1200×680 box. Free level variety already paid for. |
| Enemy leap | `Enemy.gd:172-182` leap system, tuned for ~170px ledges | There are no ledges in the tower. Ships the moment Tier-B terrain lands. |
| Mid-floor pickups | `WeaponPickup.tscn` + `FloorBuilder.build_props()` | Exists, drops one sword. The delivery mechanism for Tier 2 spell pickups already works. |

### Tier C — genuinely missing

| Spec requirement | Status | Est. size |
|---|---|---|
| **Hero spell replication in co-op** | `SpellCaster.gd` has **zero** networking references | Medium — the top risk |
| Discrete waves (3–5, escalating) | `Encounter` is a continuous budget trickle, no wave concept | Small |
| Boss after waves on **every** floor | Boss spawns immediately, and only on BOSS-typed floors | Small |
| Friendly fire on every damage source | Structurally blocked by one-group faction scans | Small — see the trick below |
| LAN auto-discovery ("two phones in one room") | Nothing. Manual IP entry only | Small (~100 lines, UDP broadcast) |
| Tier 2 floor pickups / Tier 3 boss drops / spell handoff | No drop pool, no handoff | Medium |
| 3 more bosses + 6 modifiers | 1 boss, 0 modifiers | Large (content) |
| Gibberish voice system | Nothing | Small (rides the existing `Sfx` pool) |
| 25-entity live cap | Current cap is 3–4 and **summons bypass it** | Small |
| Object pooling | Only audio is pooled. `DamageNumber`'s "pool" is an O(n) group scan per hit | Medium |
| **Mobile export** | No `export_presets.cfg`, no Android config, never attempted | Large workstream |

---

## Part 2 — the friendly-fire trick (why it is cheap)

Friendly fire looks like it needs edits across ~23 spell scripts. It does not.

Every spectacle scans exactly one group via `get_nodes_in_group(target_group)`,
and that string is written in **one place**: `SpellCaster._stamp()`
(`SpellCaster.gd:74-79`), which stamps both spellings onto all 21 dispatch arms.

So: put every damageable body into a shared group `&"mortal"` at spawn (heroes,
enemies, destructibles), and have `_stamp` write `"mortal"` when friendly fire is
on. **Zero spectacle edits.** Self-exclusion already exists — `SpellTargets._pool(nodes, skip)`
takes a skip array and callers already pass `[caster]`.

Precedent that this works: `ReactionOutcomes.HURT_GROUPS = ["enemy",
"destructible", "hero"]` (`:102`) already does faction-blind damage today, and
`Spell.gd:236-238` already widens the collision mask to hit heroes in co-op.

The one thing to verify per-spectacle during the step: that every scan passes the
caster into its skip list. Anything that misses will let a caster nuke itself.

---

## Part 3 — the decisions the spec forces (maker's call, with a recommendation)

These are places where the spec contradicts something already locked in this
codebase. I am flagging them once, recommending, and then proceeding — none of
them block starting work.

**1. "Mobs reuse the player controller. Refactor first if not."**
Reality: there are two systems. `Enemy.gd` (1787 lines, 8 archetypes, telegraphs,
**already replicated in co-op**) and bot-driven `Hero` bodies (`BotBrain`, full
spell kits, difficulty dial proven 0.41→0.95).
The spec's rule exists to prevent maintaining two damage paths. That cost is
**already paid** — all damage routes through `SpellTargets.hurt()`, and enemies
already render with the hero's rig.
→ **Recommend: do not refactor.** Keep `Enemy.gd` for the 3 cheap mob types the
spec asks for; use bot-`Hero`s for elites when we want a mob that fights like a
player. Ripping out `Enemy.gd` is the single largest destroy-work move available
and buys an architectural purity we already have in practice.

**2. Aim assist vs the locked no-auto-aim rule.**
The spec wants soft-lock by default with an assist slider. This codebase
**deleted** its `Targeting` helper and has a regression test asserting it stays
deleted (`tools/slice0_test_targeting.gd`), per a locked maker directive.
But the spec's actual rule — *"no spell's fun should depend on precise aiming"* —
is already satisfied by shape-based forgiveness (`bolt_burst`, `bolt_spread`,
cones, zones), which is exactly the approach the maker chose.
→ **Recommend: keep no-auto-aim. Ship the assist slider defaulting to 0**, so the
spectrum the spec asks for exists without reversing the decision. Note that melee
*already* auto-targets (`Hero.gd:2827-2840`, self-flagged as a violation) — the
spec makes that legal, so it can simply stop being an exception.

**3. "Out permanently: NPC memory, LLM anything."**
That is ~1,670 lines (`Conversation`, `NPC`, `MemoryUtils`, `MemoryConsolidator`,
`Patience`) and it is the thing every marketing note in this project calls the
moat. It is also genuinely incompatible with mobile: it hardcodes
`http://127.0.0.1:11434` (Ollama), which on a phone is the device's own loopback —
it cannot work there.
→ **Recommend: park, do not delete.** Branch it. `Conversation` is an autoload
referenced as a bare global by `Player.gd:66` and `NPC.gd`, so removing it breaks
`Main.tscn` from loading — it needs a clean excision, not a `rm`. `SpeechBubble`
survives and becomes the bark system.

**4. "Destructible terrain: none."**
The spec cuts *simulated* terrain. Crates (`DestructibleProp`) are not that, and
they are already built and placed per floor. Keep them — but note they are
currently **per-peer** (`Hero.gd:1887` breaks props with no authority guard), so
cover geometry diverges between the two phones. That needs one guard.

**5. Fall depth.** Spec says drop one floor; code drops two (`GameState.gd:500`).
One-constant change, but it is a real difficulty decision — flagging so it is
deliberate.

---

## Part 4 — THE STEPS

Ordered. Each phase ends somewhere playable. The spec's own build order is
honoured, re-sequenced only where the audit shows a dependency it could not have
known about.

### Phase 0 — make the game boot as the game (half a day)

Right now **F5 opens a spike sandbox**, not the game. Everything downstream is
untestable end-to-end until this is fixed.

0.1 `project.godot:19` — `run/main_scene` → `res://scenes/ui/Lobby.tscn`.
    `Lobby.gd` already has Play Solo / Host / Join / class picker and says in its
    own header it was meant to be the main scene.
0.2 Remove `MCPRuntime` from `[autoload]` (`project.godot:28`) behind a dev flag.
    It is a WebSocket dev bridge that would ship into the APK.
0.3 `Net.gd:19` — `MAX_PLAYERS: 4 → 2`.
0.4 `GameState.gd:500` — fall depth `2 → 1`.
0.5 Add `display/window/handheld/orientation="landscape"` and
    `window/stretch/aspect="expand"` (currently both absent; phones will rotate
    and letterbox).
0.6 Stop the 120 Hz physics override (`SpellPlaygroundController.gd:87`) leaking
    into any shipping path.

**Playable at:** boot → title → solo run → floors → boss → death → floors.

### Phase 1 — the loop the spec actually describes (2–3 days)

1.1 **Waves.** Refactor `Encounter.gd` from one budget-trickle into an ordered
    list of 3–5 wave budgets with a beat between them. Everything needed —
    budget, concurrent cap, spawn interval, weighted archetype roll, spawn-point
    rejection — already exists (`Encounter.gd:112-125`, `:207-275`); this adds a
    wave index and a gate. Add `waves: Array` to `FloorDef`.
1.2 **Boss after waves, every floor.** Move `spawn_boss()` from "immediately on
    BOSS floors" (`Encounter.gd:98-105`) to "on final wave cleared". Reuses
    `Boss.gd` untouched.
1.3 **One screen.** Make `CombatCamera.set_frame_all(true)` the default for all
    floors, not just boss floors (`Arena.gd:144-148`). Then make
    `LayoutDef.room_size` actually drive geometry — the arena is 4 `StaticBody2D`
    walls in `Arena.tscn`; today `room_size` is read once, only to place a portal.
1.4 **Live-entity cap.** Make `Encounter`'s alive-count authoritative at 25 and
    have summoner minions (`Enemy.gd:1305`) and boss adds (`Boss.gd:321`) ask it
    before spawning. Both currently bypass the cap entirely.
1.5 **Floor timing.** Tune wave budgets to 4–7 minutes. Numbers, not code.

### Phase 2 — friendly fire + the 3-button hand (2–3 days)

2.1 **Friendly fire.** The `&"mortal"` group trick in Part 2. One group added at
    spawn, one line in `_stamp`. Then audit that every spectacle's scan passes
    `caster` into its skip list.
2.2 **Per-slot cooldowns.** Wire `HandSlots.gd` into `Hero`, replacing the single
    `_signature_cd_timer` bank (`Hero.gd:334`). This is already-written, already-
    tested code that the shipped hero simply does not call.
2.3 **Three spell buttons.** Trim `CLASS_KITS` from 5 roles to 3 per class
    (`SpellLibrary.gd:85-155`) — a data edit. Point `LoadoutBar` at the real HUD.
2.4 **Kill the mana gate** (`Hero.gd:1462-1466`). Keep the field.
2.5 **Aim assist slider**, defaulting to 0, in `PauseMenu` settings (it already
    has an injectable-row API at `:80-103`).

### Phase 3 — co-op that actually works on two phones (4–6 days) ⚠ HIGHEST RISK

3.1 **Replicate hero spells.** `SpellCaster` is entirely net-blind. The pattern to
    copy already exists — enemy telegraphs and caster bolts are replicated as
    cosmetic "twins" (`Net.gd:357-431`, `Enemy.gd:1028`, `:1123`). Broadcast the
    cast (spell id, origin, aim, element, caster) and let each peer build the
    spectacle locally; damage keeps flowing through the existing victim-authority
    router. **Without this the spec's central image — screaming because your
    friend cast the Void on you — does not exist.**
3.2 **Replicate boss spectacle + phase transitions.** `Boss.gd` has no broadcasts
    at all; a client never sees the boss escalate.
3.3 **Remote hero animation** beyond IDLE/RUN/HURT (`Hero.gd:3207-3217`) — cast,
    swing, dash, parry. Teammates currently slide around in a run cycle.
3.4 **LAN discovery.** UDP broadcast beacon so hosting shows up as a button
    instead of an IP to type. Nothing like this exists yet.
3.5 **Disconnect cleanup** — `Net.gd:139-142` leaves an orphan hero puppet that
    permanently blocks party-wipe detection (`Arena.gd:288-290`). A dropped phone
    currently soft-locks the run.
3.6 **Prop authority guard** (`Hero.gd:1887`) so cover does not diverge.
3.7 Replace the bare `0.6 s` hero-spawn timer (`Arena.gd:399`) with a ready
    handshake — its own comment admits this.

**Validate here, on two phones, before adding content.** The spec is right that
friendly-fire knockback values cannot be tuned solo.

### Phase 4 — Tier 2 / Tier 3 spells and the drop economy (3–4 days)

4.1 Spell **pickup** entity — reuse `WeaponPickup.tscn` + `FloorBuilder.build_props()`,
    which already places and collects props per floor.
4.2 Tier 2 drop pool per floor; Tier 3 from boss kill. Gate rarity on the
    existing `SpellTier` derivation.
4.3 The 6 Tier 2 + 4 Tier 3 spells. Most map onto existing `Kind` shapes:
    Chain Lightning → `chain_lightning` (**already built**), Meteor →
    `meteor_sigil` (**built**), Gravity Flip / Petrify / Blood Pact / Mirror Image
    / Chronostasis / Rewind / Roulette are new behaviour.
    → Honest note: **Rewind is the one to be suspicious of.** A 4-second state
    rewind across two networked peers is a different engineering problem to
    everything else on the list. Recommend proving it as a spike before
    committing it to v1, or swapping it for a fourth Tier 3 that isn't a
    time-travel system.
4.4 **Spell handoff between players.** New, small, and the spec is right that it
    is where the clips come from.

### Phase 5 — bosses and modifiers (content-bound, 1–2 weeks)

5.1 Boss **modifier** system — a small resource + hooks into the existing
    `Boss._enter_phase()`. Enraged / Split / Void-touched / Mirrored / Patient.
5.2 Bosses 2–4, built on `Boss.gd`'s existing phase/telegraph/intro scaffolding.
5.3 Add a windup telegraph to `Boss._atk_beam` (`Boss.gd:283-301`) — it currently
    fires a 1400-speed beam with no tell, which breaks the spec's own rule.
5.4 Move floor difficulty from HP multipliers to modifiers, per the spec.

### Phase 6 — mobile reality (1–2 weeks) ⚠ NEVER ATTEMPTED

Do this **earlier than it appears here if there is any doubt** — an unknown-cost
workstream at the end of a plan is how schedules die. Recommend spiking 6.1–6.3
during Phase 1 just to see a build run on a real phone.

6.1 Create `export_presets.cfg` (note: currently **git-ignored**, `.gitignore:5`),
    exclude `tools/` and `addons/godot_mcp_*`.
6.2 Renderer: set `rendering_method.mobile`. Drop `msaa_2d` from **8×** to 0–2.
    Reconsider `hdr_2d=true` (required by the bloom).
6.3 Default `post_process_enabled=false` on mobile — the kill switch already
    exists (`TuningConfig.gd:52`). `post_process.gdshader` does 3 screen-texture
    fetches + ~5 transcendentals per pixel; `ImpactFrame.gd` stacks **two more**
    full-screen screen-reads during heavy combat. On a tile GPU that is the whole
    frame budget.
6.4 **Audio is 59 MB of the 61 MB asset folder** — 187 raw WAVs plus 38 MB of
    MP3s. Import-preset pass to Vorbis/QOA before any store build.
6.5 Pooling: projectiles, VFX bursts, damage numbers. `DamageNumber` currently
    does an O(n) group scan on **every hit and every DoT tick**
    (`DamageNumber.gd:34`).
6.6 Kill the `preprocess = 9.0` particle warm-up (`Atmosphere.gd:96`, `:147`) — it
    simulates 9 seconds of particles synchronously at every arena load.
6.7 Touch: pause button (currently Esc-only — **the settings menu is unreachable
    on a phone**), 3-spell layout, and a real device playtest. Every number in
    `TouchControls.gd` is a self-declared untested guess (`:41-43`).
6.8 Test on a **3-year-old mid-range Android**, watching thermals — per the spec.

### Phase 7 — flavour and tail

7.1 Gibberish voices — pitch-randomised syllables riding the existing 32-voice
    `Sfx` pool (`Sfx.gd:902`).
7.2 Barks via `SpeechBubble.gd`, reused verbatim.
7.3 Park the LLM/NPC-memory stack on a branch; excise the `Conversation` autoload
    cleanly (it is a bare global identifier in `Player.gd:66` and `NPC.gd`).
7.4 Death screen (none exists), credits (**the Pepper Sound Pack requires
    attribution** — see `assets/audio/CREDITS.md`), pause polish, crash handling.
7.5 Rename `hollow_purple` (IP risk; proposal `prism_collapse`).

---

## Part 5 — sequencing note

The spec's build order is sound and I have kept it. Two deviations, both
audit-driven:

- **Phase 0 is new.** The spec assumes the project boots into the game. It does
  not — it boots into a spike sandbox, and the title screen that already exists
  is orphaned. Six one-line changes unlock end-to-end testing of everything else.
- **Mobile export moved up in priority** even though it appears late. It is the
  only workstream with genuinely unknown cost, because it has never been run once.
  Everything else has a working precedent somewhere in this repo.

## Part 6 — how to verify

91 headless suites already exist. The runner is one process per suite:

```
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --import
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/<suite>.gd
```

Two standing traps that will cost time if forgotten:

- Run `--import` after adding any new `class_name`, or Godot reports a missing
  method on a class that plainly has it.
- **Never write `failed += _test_x()`.** A dead property read aborts the enclosing
  function and returns zero, which that idiom reads as "no failures" — it silently
  disabled 64 suites once already. Accumulate on a member and record a completion
  sentinel; `tools/slice_test_loadout.gd` is the reference.

There is **no run-all harness**. Worth writing one in Phase 0 — it is an hour.

And the standing judgement from the last handoff, which this plan does not
override: every feel number in this stack is reasoning, not feel. Two phones, one
room, weekly.
