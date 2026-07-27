# The Swordsaint + the Signature framework, Sealed Grounds, and the Second Sun — design spec

**Date:** 2026-07-27 · **Branch:** `stickman-integrate` · **Status:** design only, READ-ONLY recon — no game code was modified producing this document.

**Maker ask:** a **swordsman** class ("epic weapons, sword use generally"), and ults with the weight of Fate's saber-class named attacks, Gilgamesh's weapon-portal volley, Escanor **summoning the sun**, and Gojo's collapses and **domains**. Fate's *class system* is cited as good structural inspiration. Domains are the thing they are most excited about.

**Three requirements folded in mid-recon:** (1) a visible **spell circle** is part of the casting ritual, not just a pose; (2) **cast time scales with power**, domains longest; (3) **casts can now be broken** — `Hero.take_damage` resolves mitigation *before* the interrupt, so only damage that actually lands shatters a cast.

**Governing rules:** `docs/references/magic-overhaul-plan.md` (five binding rules) · `docs/superpowers/specs/2026-07-27-spell-uniqueness-and-new-spells.md` (delivery-shape audit — every new thing must be a NEW SHAPE) · `docs/superpowers/specs/2026-07-27-protection-spells.md` (the duelist seat is empty; `STANCE` is reserved for it) · `docs/superpowers/specs/2026-07-27-mobile-casting-ux.md` (aim is a DIRECTION, never a TARGET).

---

## 0. TL;DR

- **(a) Signature framework — AGREE, with one refactor that makes it free.** The three-beat grammar is right, but it must **ride the windup that already exists** rather than adding time. `Hero._begin_summon` already holds 0.42 s and `_begin_channel` already holds 1.0–1.3 s, both already bloom a `MagicCircle`. DECLARE dresses that existing beat. Zero added latency for 26 ults, ~150 lines. **This is the highest-value build in the document.**
- **(b) Domains — AGREE, best idea on the list, and it is the design's natural next system.** A Sealed Ground is a **bounded rule flip with a physical anchor you can break**. Three escapes (walk out / break the anchor / interrupt the 2.6 s cast), symmetric rules, and **domains never deal damage** — except when two of them collapse into each other, which is the one authored exception. The brief's claim that "the reaction layer already exists to express it" **became true during this recon**: a parallel workstream landed the `SpellReactor` autoload plus `ReactionOutcomes` and the first outcome. §6.5 is therefore written against a real contract rather than a hypothetical one — a domain becomes a reactant by implementing six duck-typed methods and calling `register()` once.
- **(c) The sun — a persistent EMITTING SOURCE, not a bombardment.** `Kind.SOURCE`: a colossal holy body that **hangs in the arena for 8 s**, scorches radially with distance falloff, drifts, recolours the world through `PostProcess`, and **can be shot down (90 HP) or physically shoved**. That is a delivery shape the kit does not have; a descend-and-detonate sun would land straight in the four-identical-bombardments cluster the audit named its worst offender.
- **(d) The weapon-portal volley — genuinely new, but ONLY if built as a sequenced, steerable emitter array.** A one-press instant fan is a reskin of `rune_orbs`. Eight rifts firing one every 0.2 s **along your aim at the moment each one fires** makes it the kit's first *sustained output you steer* — every one of the 26 existing spells is fire-and-forget.
- **(e) IP — three live borrows in shipped strings, and they are not close calls.** `"Zoltraak · Arcane Beam"` whose description literally reads *"Frieren's ordinary offensive magic"*; `"Chidori · Thunderclap"`; and the `hollow_purple` outcome key. Mechanics are not ownable, names and named techniques are. §8 renames them and gives originals for everything proposed here. **Nothing in this document is called Excalibur, Noble Phantasm, Gate of Babylon, Domain Expansion, or Hollow Purple.**
- **The class: SWORDSAINT** (`HeroClass` index 8). No magic in the caster sense; the damage is **the path of the blade**. This is the duelist seat the protection spec reserved as "Bladedancer" — same seat, renamed, and it adopts `STANCE` exactly as that spec designed it.
- **Highest-value first build:** the DECLARE beat. It costs nothing in balance, touches two functions, and makes every existing ultimate feel like a named attack before a single new spell is written.

---

## 1. Ground truth (verified by reading, with citations)

### 1.1 What a signature cast actually does today

| Path | Trigger | Duration | Circle | Pose |
|---|---|---|---|---|
| `_begin_channel` (`Hero.gd:1067`) | `spell.cast_time > 0` — 12 spells | 1.0 / 1.1 / 1.3 s | face-on `MagicCircle` at the feet, r = `44 + 26 × (mp/90)` → **44–70 px**, grows 0.5→1.35 (`:1084`, `:1106`) | levitate + held `State.CAST` |
| `_begin_summon` (`Hero.gd:955`) | `cast_time == 0` — the rest | `SUMMON_WINDUP` **0.42 s**, or `SUMMON_WINDUP_FAST` **0.22 s** for rush/blink (`:402-403`) | face-on `MagicCircle` at the feet, r = `34 + 22 × (mp/90)` → **34–56 px**, grows 0.55→1.25 (`:969-973`) | `GestureKind.GATHER` for **every** spell (`:967`) |

**So the maker's "spell circles on cast" ask is already 80 % built and wired in the real game, not only the playground.** `MagicCircle` is instantiated at `Hero.gd:969` and `Hero.gd:1081`, plus four spectacle-side circles (`BeamSpell.gd:79` edge-on muzzle, `DivineRay.gd:108`, `MeteorSigil.gd:100`, `StarConvergence.gd:53` sky sigils). The gap is not existence — it is that **every one of them is the same face-on ring at a near-identical radius in a different tint**, which is the same complaint as the recolor families, applied to the ritual. §3.3 fixes that with a `motif` field.

The other half of the ask is real, though: **`CastStyle` still has one caller in the whole project** (`scripts/spike/SpellPlaygroundController.gd:225`). `Hero.gd` never references it, so in the shipped game there are two cast animations for 26 spells. That finding is the spell-uniqueness spec's §A.5 and it stands unfixed.

### 1.2 The interrupt rule, as it now reads in code

`Hero.take_damage` (`Hero.gd:2058-2075`), verbatim intent from its own comments:

```
5. parry window          -> ding, return
6. guard.mitigate(amount)                      # MITIGATION FIRST
7. if amount > 0: _cancel_channel() / _cancel_summon()
```

`GuardComponent` (`GuardComponent.gd`) is live and is now the single mitigation path — `grant_absorb`, `grant_reduction`, `grant_reflect`, `grant_immunity`, `mitigate()`, `is_immune()`. **A fully absorbed hit lets the cast survive.** Mana and cooldown are spent at `_cast_signature` (`:930-932`), *before* the windup — so a broken cast is a total loss, today, with no refund. Every number in this document is designed against that.

`Kind.WARD` / `STANCE` / `DECOY` from the protection spec are **not yet appended** to `SpellDef.Kind` — the component landed, the spells did not.

### 1.3 The delivery-shape census this document must not make worse

From the uniqueness audit (§A.2), plus the two shapes shipped since:

| Shape | Count | Verb |
|---|---|---|
| **L** line from the caster | 9 | point → the line is hit |
| **G** marked ground point | 9 | put a circle on the floor → get out |
| **P** travelling projectile | 2 | lead the target |
| **B** barrier | 2 | block a lane |
| **M** melee arc | 1 | be close, press |
| **C** ground traveller | 1 | jump it |
| **A** thrown anchor (two-beat) | 1 | throw, then decide |

Everything proposed below is scored against this table in §9.1. **Four of the five things in this document are new shapes; the fifth (Panoply) is new only under one specific construction, and I say so.**

### 1.4 Four other verified facts the design leans on

1. **The reaction layer acquired a runtime engine mid-recon.** When this document started, `ReactionTable` had no production caller. It now does: `scripts/combat/SpellReactor.gd` (`class_name SpellReactorNode`, autoload `SpellReactor`) polls registered live effects at **30 Hz**, capped at `MAX_LIVE = 12` reactants and `MAX_REACTIONS_PER_TICK = 2`, memoises fired pairs, and dispatches through `ReactionOutcomes.apply()`. `BeamSpell` is its first participant and `HollowPurple.gd` its first outcome. **The participant contract is six duck-typed methods** — `reaction_shape()` (world-space, built with `SpellGeometry`, never `global_position`), `reaction_active()`, `reaction_element()`, `reaction_form()`, `reaction_consume()`, and optional `reaction_freeze()`. Anything that implements them and calls `SpellReactor.register(node, form, element)` is in the system; anything that does not is provably unaffected. **`SpellDeflect` is still un-consumed** — the deflect policy file exists and is tested, but nothing routes damage through `resolve()` yet.
2. **`SpellDeflect` already settled the doctrine this spec must obey** (`SpellDeflect.gd:29-41`): *"if it has a position that moves, give it `reflect()`. Otherwise route its damage through `resolve()`."* Plus `WINDOW_ULT = 0.22` — only the opening fifth of a parry window counts against an ult.
3. **The class enum is append-safe.** `_cycle_class` uses `% HeroClass.size()` (`Hero.gd:894`). Two hardcoded 8s must change: `scripts/ui/Lobby.gd:83` (`% 8`) and `tools/slice5_test_classes.gd:67` (`== 8`).
4. **`PostProcess` already exposes the hooks a world-reacting spell needs** — `_bump_heat`, `_begin_shock(strength, center)`, `_apply_theme(tint)`, and it reads camera trauma. The Second Sun and the domain seal both drive these rather than inventing new screen effects.

---

## 2. Verdicts

### 2.1 (a) The Fate structure, not the characters — **AGREE, and the structure is even cheaper than the brief thinks**

The thesis is correct and the reason it is correct is mechanical, not thematic. What makes a named attack land is not the name — it is that **the fiction and the mechanics announce the same thing at the same moment**. The kit already commits the body for 0.42–1.3 s before an ult and already blooms a sigil for exactly that long. That window is *already* the ceremony; it is simply undressed. Adding a card, a colour drain and a per-class glyph to a beat that already exists is a **presentation change with zero balance consequence**.

**Where I refine it: do not add a fourth beat, and do not declare on everything.**

- **Adding time is the failure mode.** A 0.42 s summon plus a 0.9 s declare is a 1.3 s ult. Cast it forty times in a climb and the ceremony becomes a tax. The maker's own standing feedback on mobility ("keep the mobility snappy" — the reason `SUMMON_WINDUP_FAST` exists at 0.22 s) is the warning shot.
- **Suppress DECLARE on the 0.22 s fast path entirely.** Shadow Step and Levin Fist are mobility bursts. A name card on a blink is a name card you cannot read.
- **Suppress the repeat.** If the same signature is declared again within **12 s**, the card is skipped and only the circle + colour drain play. You announce your sword once; you do not re-introduce yourself every eight seconds.

With those three rules the grammar makes ults feel epic *and* does not slow them down, because it never costs a frame that was not already being spent. Verdict: **adopt, with §3 as the spec.**

### 2.2 (b) Domains — **AGREE. This is the most valuable idea in the brief and the correct next system.**

The reasoning in the brief is exactly right and worth restating as the design's binding rule:

> **A domain is not a bigger explosion. It is a bounded space in which one rule of the game is different.**

The kit has 26 spells and **not one of them changes a rule**. They all resolve to "damage happens in this shape." That is precisely why the maker's complaint ("spells all do the same thing") survived a whole art phase — the art changed, the verb did not. A rule flip is a different *category* of thing, and it is the only proposal in this document that could not be described as "a new-shaped hit."

**Three refinements, each of which fixes a way domains normally go wrong:**

1. **Domains must have a physical anchor, not a caster leash.** If the caster is the anchor, domains chain your mobility and become a ranged class's suicide. A destructible sigil at the domain's centre (§6.2) gives every archetype something to do about it, works identically when a boss casts one, and makes the domain's *real* duration a function of how much attention it draws.
2. **Domains never damage.** The moment a domain does damage it becomes an explosion with extra steps, and in co-op with friendly fire it becomes the single most infuriating object in the game. The only exception is a domain **collapse** (§6.5), which damages everyone including both casters — a mutual punishment, not a weapon.
3. **The rule flip is symmetric, and the boundary is walkable.** A domain you can be trapped in is a stun with a big radius. At hero `SPEED` 210 px/s and a 480 px radius, the worst case is ~2.3 s of running to leave. That is a real cost and a real out.

Verdict: **adopt, with §6 as the spec, and build it AFTER the framework and the class — it is the most expensive item here (§9.3).**

### 2.3 (c) The sun — **a persistent emitting SOURCE. Justified against the audit.**

The brief offers two constructions. They are not equal:

| Construction | Shape it lands in | Verdict |
|---|---|---|
| Descend-and-detonate | **G** (marked ground, 9 spells) — specifically the `MeteorSigil` cluster the audit called *"one spell with a skin picker"* | **Reject.** It would be the fifth bombardment. |
| **Persistent burning body that hangs and applies pressure** | **NEW — S, the emitting source object** | **Adopt.** |

Nothing in the kit is a **source**: an object with a world position *in the air*, that persists, that emits continuously with distance falloff (no boundary you step over), that **moves on its own**, that **can be attacked**, and that changes how the arena looks while it is up. `ZoneSpell`/blizzard is the closest and is none of those — it is a static ground ellipse with a lifetime, i.e. Shape G.

Two further reasons the source construction is the right one:

- **It is the same design family as domains.** A sun and a Sealed Ground are both "the space is different now." Building them in the same cycle means the direction reinforces itself instead of the kit gaining a seventh flavour of explosion.
- **It creates counterplay the kit cannot currently express.** You can shoot the sun down. You can shove it. You can bait enemies under it. A detonation offers none of that — it happens and it is over.

Verdict: **adopt as `Kind.SOURCE`, with the Second Sun as its first instance (§5).**

### 2.4 (d) The weapon-portal volley — **distinct, conditionally**

Scored honestly against `rune_orbs` (`RuneOrbs.gd`, Shape P, a fan of six from the hand):

| | `rune_orbs` | Portal volley as a **one-press fan** | Portal volley as a **sequenced steerable array** |
|---|---|---|---|
| Origin | one point (the hand) | a ring | a ring |
| Timing | one instant burst | one instant burst | **8 shots over 1.6 s** |
| Aim decisions | 1 | 1 | **8 — one per shot, live** |
| Verb | press, done | press, done | **press, then steer** |
| Verdict | — | **a reskin** | **new** |

The ring of origins alone is a visual difference, not a mechanical one — the player's decision is identical. What makes it new is the **sequence**: every one of the 26 existing spells is fire-and-forget, so a spell whose output you keep aiming *while it happens* is a verb the kit has never had. It also satisfies the no-auto-aim rule better than almost anything else in the kit, because manual steering is the entire mechanic.

Verdict: **adopt, built as `Kind.VOLLEY` with the sequence (§4.6). If it ever gets "simplified" to a single burst, cut it — at that point it is `rune_orbs` with a different sprite.**

### 2.5 (e) IP — **agree, bluntly, and there are live borrows in shipped strings today**

Mechanics are not ownable. A beam, a portal volley, a bounded rule-change field and a summoned sun are all fair game and always have been. **Names and specific named techniques are not**, and neither are distinctive visual signatures copied shot-for-shot.

**Currently in the repo, in strings a player can read:**

| Where | String | Risk |
|---|---|---|
| `SpellLibrary.gd:80-83` | `display_name = "Zoltraak · Arcane Beam"`, description `"Frieren's ordinary offensive magic, perfected."` | **Highest.** A named spell from a named work, *plus* the work is cited in the shipped description. |
| `SpellLibrary.gd:122` | `display_name = "Chidori · Thunderclap"`; also `Hero.gd:173` comment | **High.** A named technique from a named work. |
| `ReactionTable.gd:98` | outcome key `"hollow_purple"` | **Low** (never surfaced to a player) but free to fix — the file has no callers. |

Everything else in `SpellLibrary` (`Judgment`, `Heaven's Verdict`, `Shadow Step`, `Blade Flurry`, `Meteor Sigil`, `Rift Dagger`, `Creeping Shade`) is generic fantasy vocabulary and is fine. Class names are fine. The doc-level references (`magic-overhaul-plan.md` naming JJK as a quality bar, `SpellLibrary`'s "Frieren / isekai" header comment) are **internal** and carry no risk — comments do not ship as player-facing text.

The standing project rule *"don't cosplay the references"* is the same instruction from the design side: **borrow the silhouette, never the signature.** §8 is the rename pass. Nothing proposed in this document reuses a protected name.

---

## 3. The Signature framework — DECLARE / CHARGE / RELEASE

The reusable spec every class adopts. New file `scripts/combat/SignatureRite.gd` (static helpers + the card) plus a `motif` field on `MagicCircle`; **no new spell scenes, no balance change.**

### 3.1 The three beats and their timings

| Beat | Fraction of the existing windup | What happens |
|---|---|---|
| **DECLARE** | first **0.30** of the windup, capped at **0.45 s** | Name card fades in (0.10 s) at the top third. World desaturates to **0.55** saturation and darkens **12 %** over 0.12 s. The class's spell circle blooms at the caster's feet. `Sfx.play("charge_up", -6.0, 0.05)` — already there. |
| **CHARGE** | the middle | The circle grows and spins (already implemented at `Hero.gd:987` / `:1106`). Gather motes converge (already implemented). **This is the dodge window** — nothing else is happening, deliberately. |
| **RELEASE** | last **0.08** of the windup | Card fades out (0.15 s). Saturation snaps back over 0.25 s with a 6 % overshoot. Circle `vanish(0.2)` (already implemented at `Hero.gd:1047`). `Juice.epic_moment` (already implemented at `:1039` / `:1130`). |

**Total added time: zero.** Every beat maps onto a window `_begin_summon` / `_begin_channel` already hold.

**Concrete numbers per tier** (from `Hero.gd:402-403` and the `cast_time` values in `SpellLibrary`):

| Tier | Windup | DECLARE window | Card? |
|---|---|---|---|
| Mobility burst (`SUMMON_WINDUP_FAST`) | 0.22 s | — | **No.** Suppressed entirely. |
| Planted signature (`SUMMON_WINDUP`) | 0.42 s | 0.126 s | Yes |
| Channelled signature (`cast_time`) | 1.0–1.3 s | 0.30–0.39 s | Yes |
| **Second Sun** | 1.9 s | 0.45 s (capped) | Yes, plus the darkening is doubled (§5.4) |
| **Sealed Ground** | 2.6 s | 0.45 s (capped) | Yes, plus the boundary preview (§6.3) |

### 3.2 The card

Model it on `Boss._play_intro` (`Boss.gd:350-369`) — that code is already the right shape and is the cheapest possible proof the maker likes the beat, because they have already seen it working:

```
Label on a CanvasLayer, PRESET_TOP_WIDE, offset_top 120 → use 96 for the hero (the boss
card sits lower because the boss bar is above it)
font_size 36 → 28 for a signature (the boss is the bigger event; keep the hierarchy)
font_color = the spell's resolved colour, not white — so the card is already class-legible
outline 7, outline_color (0.05, 0.02, 0.03, 0.95)
tween: fade 0.10 → hold → fade 0.15   (the boss uses 0.5 / 1.4 / 0.5 — far too slow here)
```

**Text = `spell.display_name.to_upper()`.** No subtitle, no class name, no "ULTIMATE" chrome. The name is the whole point.

**Suppression rules, all three load-bearing:**
1. Never on a `SUMMON_WINDUP_FAST` cast.
2. Never if the same `spell.id` was declared within **12.0 s** (a `Dictionary<String, float>` of last-declare timestamps on the Hero).
3. Never while another card is on screen (co-op: two heroes ulting at once must not stack two labels — the second one's circle and colour drain still play).

### 3.3 The spell circle, per class — the fix for "24 spells all open the same ring"

`MagicCircle` already draws two orientations well (face-on portal, edge-on beam gate). What it lacks is **identity**. Add one field and one match:

```gdscript
@export var motif: int = Motif.ARCANE
enum Motif { ARCANE, SHADOW, FRACTURE, MASONRY, HALO, HEXFROST, STORM, INVERSE, LINE, ECLIPSE, SEAL }
```

`_draw_face` already parameterises everything a motif needs — `TICKS`, `DASH_SEGMENTS`, `SPOKES`, `MOTES`, `_draw_star(r, points, offset, col)`, spin direction, and whether the dashed ring is drawn at all. A motif is a small dictionary of those knobs plus at most one bespoke primitive.

| Class | Motif | Geometry — what makes it unmistakable at a glance |
|---|---|---|
| Arcanist | `ARCANE` | The current default: hexagram over a counter-rotating square, 28 ticks, 8 spokes. Filigree. |
| Shadowblade | `SHADOW` | **No outer ring.** Three broken crescents, counter-rotating; ticks point **inward**. A wound, not a wheel. |
| Brawler | `FRACTURE` | **No circle at all.** Radial ground fractures spreading from the feet. He has no magic; the ground just gives. |
| Juggernaut | `MASONRY` | One heavy band, 4 thick spokes, an inscribed square. No dashes, no motes. Stonework, not lace. |
| Cleric | `HALO` | Three concentric haloes, 12 spokes, no polygon, motes drifting **upward** out of the ring. |
| Cryomancer | `HEXFROST` | A hexagonal frame instead of a circle; spokes are 6-fold snowflake arms; no dashed ring. |
| Stormcaller | `STORM` | The ring itself is a **jagged polyline**, redrawn every 0.08 s; spokes fork. It never sits still. |
| Warlock | `INVERSE` | Drawn inside-out: a filled dark disc with the light at the rim. Five-point star. |
| **Swordsaint** | `LINE` | **Not a circle.** A row of glyphs laid along the **aim**, from the caster to the reach of the spell. He does not circle; he lines up. Doubles as the height-band telegraph for Horizon Cut (§4.5). |
| *Second Sun* | `ECLIPSE` | A filled dark disc with a thin corona ring and licking prominences. |
| *Sealed Ground* | `SEAL` | The boundary itself (§6.3). |

**Radii, per tier** (existing formulas, adjusted so the tiers read as a ladder):

| Tier | Radius | Source |
|---|---|---|
| Mobility burst | 26 px flat, 0.22 s | new; the current 34–56 formula is too big to appear and vanish in 0.22 s |
| Planted signature | `40 + 24 × (mp/90)` → **40–64 px** | was `34 + 22×` (`Hero.gd:972`) |
| Channelled signature | `44 + 26 × (mp/90)` → **44–70 px** | unchanged (`Hero.gd:1084`) |
| Second Sun | **96 px** at the caster **+ a 190 px sky sigil** at the target from t=1.1 | new |
| Sealed Ground | grows **60 px → the full domain radius** over the cast | new — the circle *is* the footprint telegraph |

Wire-up: `Hero._begin_summon` / `_begin_channel` pass `motif` from a `CLASS_MOTIF` lookup; the spell may override (`SpellDef.circle_motif`, default −1 = inherit the class). Verify by extending `tools/circle_capture.gd` to render all eleven motifs in a grid and **looking at the image** — per the overhaul's screenshot protocol.

### 3.4 Cast time scales with power — the ladder, and what the opponent does with each window

Longer casts are not flavour. **The windup is the counterplay budget**, and the budget has to be spendable on something specific.

| Tier | Windup | Distance a body covers at 210 px/s | What the opponent is meant to DO |
|---|---|---|---|
| Primary (LMB) | 0.00 s | 0 | Nothing. It is the baseline; the spell-level counterplay is the projectile itself. |
| Mobility burst | 0.22 s | 46 px | **Brace.** Too short to close, long enough to start a dash or a parry. |
| Planted signature | 0.42 s | 88 px | **Leave the footprint.** The circle is at the caster's feet and the spell erupts from there or along the aim — one dash (0.14 s, 620 px/s ≈ 87 px) clears most of it. |
| Channelled signature | 1.0–1.3 s | 210–273 px | **Break it.** The caster is levitating, rooted and visible. One landed hit costs them the mana and the cooldown. This is the first tier where interrupting is strictly better than dodging. |
| **Second Sun** | **1.9 s** | 399 px | **Break it, or claim the ground.** 1.9 s is enough to cross half an arena. If you cannot reach the caster, the sky sigil opens at t=1.1 and tells you exactly where the sun will hang — so you spend the last 0.8 s getting outside 300 px of it. |
| **Sealed Ground** | **2.6 s** | 546 px | **Break it, or leave.** The boundary preview grows from the first frame, so you know both the footprint and the deadline. Nothing else in the game gives an opponent this much information this early, and that is deliberate: a domain is the biggest commitment in the game and must be the most punishable. |

**Why a domain sits at the top of the ladder.** It is the only cast whose payoff is *not* a hit — it changes the rules for up to 7 s across 480 px. There is no dodge for a rule. So the entire counterplay budget has to be paid **before it seals**, which means the cast must be long enough that a competent opponent who is paying attention can always do something about it. 2.6 s is chosen so that a body anywhere within ~540 px can reach the caster, which is roughly "anywhere you can already see them."

**Corollary — do not put domains on a short cast "because they feel clunky."** If a domain feels clunky the fix is a better DECLARE beat, not a shorter one. A 1.2 s domain is uncounterable and the whole system rots.

### 3.5 Breakability — designing against the new interrupt rule

The rule as it now stands (`Hero.gd:2058-2075`): mitigation resolves first; only damage that **lands** cancels a channel or a summon; a broken cast keeps its spent mana and cooldown.

**Consequence 1 — a long cast is a real bet, and it must feel like one.** A broken Sealed Ground costs 90 MP (of a 100 pool) and burns a 22 s cooldown for nothing. That is severe, and it should stay severe: it is what makes interrupting one a win worth going for. Two feedback requirements so the loss reads instead of just happening:

- `_cancel_channel` already exists; **give the domain and sun casts a heavier cancel** — the growing boundary/eclipse circle should **shatter outward** (reuse `MagicCircle.vanish` with a larger fade scale, plus a `CombatVfx` shard burst), `Juice.shake_camera(10.0)`, and the world's desaturation snaps back **hard** (0.06 s, not 0.25). The player must never be unsure whether their domain went off.
- **No partial credit.** Do not ship a "half-sealed domain that lasts half as long." Partial results teach players that commitment is hedged, which is the opposite of what a 2.6 s cast is for.

**Consequence 2 — this is exactly why a defensive spell is worth a button, and it is NOT too strong.** A ward that eats one hit lets a domain finish. Check the arithmetic against the live pool (`max_mp` 100, `MP_REGEN` 20/s):

- Prismatic Lattice (protection spec §4.1): 35 MP, 45 absorb, 6.0 s duration.
- Sealed Ground: 90 MP.
- 35 + 90 = **125 MP against a 100 pool** → you must ward, then wait **≥1.25 s** of regen, then start a 2.6 s cast. Total commitment ≈ **4.3 s** in which you cast nothing else.
- And both live in the **signature cycle**, which the protection spec (§6) already establishes is a single button with 7 full slots. Protecting yourself and sealing the ground means you have brought no third option.

**Verdict: the combination is priced correctly by the button budget and the mana pool, and it is a *plan*, which is the point.** One hard exception, because it is the single combination with no counterplay:

> **A Sealed Ground cast may not be started while `GuardComponent.is_immune()` is true, and granting immunity does not protect an in-progress domain cast.** Absorb and reduction are fine — they can be out-damaged. Immunity plus a 2.6 s cast cannot.

**Consequence 3 — can a sealed domain be broken from inside? Yes, and that is the anchor's whole job.** Once sealed, the cast is no longer interruptible (there is no cast). What is breakable is the **anchor** (§6.2): a 40 px sigil at the domain's centre, **60 HP**, in group `"destructible"`, reachable by anyone on either side, from inside or outside. Killing it:

- collapses the boundary inward over 0.35 s;
- deals **no damage to anybody** (domains do not damage);
- **staggers the caster for 0.8 s** wherever they are — `apply_status(EARTH)` is the existing Stagger path (`StatusComponent.STAGGER_DURATION` 0.7 s; 0.8 s here so a domain break is felt as slightly worse than an ordinary stagger);
- does **not** refund the cooldown.

That single rule does five jobs at once: it gives ranged classes a target, gives melee a reason to dive, makes a domain's real duration a function of attention rather than a timer, works unchanged when a boss casts one, and stops a domain from ever being fire-and-forget.

---

## 4. The SWORDSAINT

`HeroClass` index **8**, `CLASS_NAMES[8] = "Swordsaint"`.

**This is the duelist seat `docs/superpowers/specs/2026-07-27-protection-spells.md` §2.5 reserved** ("working name: Bladedancer... whose entire kit is built from the `STANCE` verb this spec introduces"). Same seat, renamed because "Bladedancer" reads light and quick and this class is neither. It adopts `STANCE` exactly as that spec designed it, and it does **not** take a `WARD` — that spec's rule P1 (*"for a class whose fantasy is pressure, defence must produce tempo or damage"*) applies here more than anywhere.

### 4.1 Identity

**The only class whose damage comes from the path of the weapon rather than from a spell.** No bolt, no beam, no bombardment. It has a great sword, three signatures, and a stance. Its power comes from being *inside* range, and its skill ceiling is entirely in how you move the blade.

- `element`: `ARCANE` by default with `melee_element: -1` — **the plain steel strike applies no ailment.** Giving the Swordsaint a burn or a chill would make it "the fire melee class"; the whole point is that the blade is just a blade. The X-cycle still tints the edge, and the tint is what feeds the reaction layer.
- `defense: "held_guard"` — the `STANCE` verb, on RMB.
- **`can_parry: false`.** The drag *is* the deflect (§4.3). Giving it the free 0.16 s parry button on top would make it strictly better defensively than all eight other classes, which is the failure the protection spec's §7.2 warns about.
- **No blink.** Like Juggernaut. It closes on foot or by dash-strike; it does not teleport out of its own mistakes.

### 4.2 The melee: the drag

The verb: **hold the melee input → the blade lifts and follows your aim with lag → the swept path between last frame's tip and this frame's tip is what damages → release to settle.** There is no swing animation to trigger and no cooldown to wait out. The damage is a function of how fast you moved the blade.

**Constants** (new file `scripts/combat/BladeDrag.gd`, static helpers + the swept-capsule test; state lives on the Hero, mirroring how `Patience.gd` and `MemoryUtils.gd` are structured):

| Const | Value | Meaning |
|---|---|---|
| `BLADE_REACH` | `86.0` | tip distance from the body centre (Juggernaut's `melee_range` is 96 — the Swordsaint is slightly shorter and far more controllable) |
| `SWEEP_WIDTH` | `16.0` | half-width of the swept quad; the cut is the *path*, not a cone |
| `FOLLOW_RATE` | `9.0` rad/s | max angular speed the blade tracks the aim at. **This lag is the entire skill.** |
| `MIN_CUT_SPEED` | `220.0` px/s | below this the blade is merely held out; it does not cut |
| `REF_CUT_SPEED` | `900.0` px/s | reference tip speed for full damage |
| `CUT_BASE` | `20` | damage at reference speed |
| `PARRY_CUT_SPEED` | `520.0` px/s | at or above, the drag deflects (§4.3) |
| `REBOUND` | `-0.4` | angular-velocity multiplier when the blade strikes terrain |
| `STROKE_DEAD` | `0.08` s | tip-speed dropout that ends a stroke |

**Damage:** `int(round(CUT_BASE * clampf(tip_speed / REF_CUT_SPEED, 0.35, 1.6)))` → **7 at a crawl, 20 at reference, 32 at a whip.** That single line is what makes the drag ≠ a canned swing: the input is analogue and the output tracks it.

**Knockback:** `(240.0 + 220.0 * clampf(tip_speed / REF_CUT_SPEED, 0.0, 1.6)) ` along the **tip velocity**, not along `facing`. You fling bodies where the blade went. This is the Stick-Fight read and it is why the drag is fun to whiff with.

**The anti-exploit rule, and it is mandatory.** Speed-scaled damage invites wiggling the cursor to shred. The counter:

> **One hit per target per STROKE.** A stroke ends when the blade's angular-velocity sign flips, or when tip speed sits under `MIN_CUT_SPEED` for `STROKE_DEAD`. Reversing direction therefore *costs* you the momentum you were paid for — a wiggle is a chain of near-zero-speed strokes, each landing the 0.35× floor.

Wiggling is not merely nerfed; it is the *worst* way to use the weapon, which is the correct shape for an anti-exploit rule.

**Terrain.** If the swept quad strikes layer 1 above 600 px/s: angular velocity `*= REBOUND`, sparks at the contact point, **0.12 s blade stun**, `Sfx.play("ding", -6.0, -0.2)`. Swinging hard in a corridor punishes you. It also chips `destructible` props and `BreakablePlatform` — the Swordsaint is the class that visibly wrecks the room it fights in.

**Cast pose:** none. The drag has no pose because the blade *is* the pose — `CharacterRig` drives the arms from the blade angle rather than the other way round.

### 4.3 The deflect, which is the same verb

If, in a frame, the swept quad overlaps a node in `"enemy_projectile"` or `"deflectable_spell"` **and** `tip_speed >= PARRY_CUT_SPEED` **and** the tip velocity opposes the projectile's velocity (`dot < -0.2`), the projectile is **reflected along the tip velocity**. No button, no timer window — the window is emergent from the motion.

For the non-travelling half of the kit (beams, meteors, zones — the spells `SpellDeflect` covers), the Swordsaint satisfies the existing duck-typed contract with no new plumbing:

```gdscript
func is_parrying() -> bool:
    return _blade_tip_speed >= PARRY_CUT_SPEED

func parry_freshness() -> float:
    return clampf((_blade_tip_speed - PARRY_CUT_SPEED) / (REF_CUT_SPEED - PARRY_CUT_SPEED), 0.0, 1.0)
```

Read what that produces against `SpellDeflect.WINDOW_ULT = 0.22`: to eat an **ult**, `parry_freshness()` must be ≥ 0.78, i.e. a tip speed of ~816 px/s — a genuinely hard swing landing on the exact frame. **The Swordsaint's ult-parry is "you must be swinging your hardest at the exact moment,"** which is the best-feeling version of that read anyone has proposed and it costs zero new code beyond two four-line methods.

### 4.4 The defensive verb: Held Guard (`Kind.STANCE`)

**Mechanic.** Held, rooted. Max hold **1.6 s**, cooldown **8.0 s**, **22 MP**. While held, the blade is planted point-down and the body turns into the aim:

- Incoming **melee, contact and charge** damage from the front 180° is **fully negated and BANKED** (up to **3 hits**, banked total capped at **60**).
- Incoming **projectiles and spells** are *not* negated — they take the ordinary `GuardComponent` path (i.e. nothing, unless a ward is up). Held Guard is a **melee** answer specifically.
- **Release** (or auto-release on the 3rd bank) fires an **unsheathe cut** along the aim: a 120 px line, `banked × 1.8` damage, knockback 380. Banking 60 returns **108**.
- You cannot move, dash, or drag while held.

**Pose:** `Pose.PLANT` — the protection spec (§5.3) already defines it as the one held pose, added for Juggernaut's Bulwark. Reused, not duplicated.

**Why this does not duplicate Bulwark or Iron Chin:**

| | Juggernaut Bulwark | Brawler Iron Chin | **Swordsaint Held Guard** |
|---|---|---|---|
| Math | 80 % reduce in a 140° cone | per-hit cap 12, grants melee stacks | **full negate → bank → return as one cut** |
| Output | 150 px shove-shockwave on a big blocked hit | a damage buff | **a directed 120 px line for up to 108** |
| Duration | ≤2.5 s | 0.6 s window | ≤1.6 s |
| Covers allies | yes | no | no |

**Counterplay.** It negates only melee, roots you, and the bank is worthless if nobody swings — walking away beats it outright. And it is the one moment the Swordsaint is not deflecting, because the blade is planted, not moving.

### 4.5 Signature 1 — **Horizon Cut** (`Kind.ARC`, new shape)

> The blade is drawn slowly across the body, and when it leaves the sheath a crescent leaves with it — a curved wall of edge that widens as it travels, and cuts everything at the height you chose.

**Why it is a new shape.** A beam resolves instantly along a line (Shape L, 9 spells). A projectile is a point (Shape P). This is a **travelling curved wall**: it has a real position over time, it widens, it cuts terrain along its path, and — critically — **it occupies a vertical BAND you choose with the aim.** That is the audit's §C.3 gap (*"nothing in the kit asks the player to choose a height"*) and half of its §C.2 gap (*"a threat is coming and it does not stop"*), which the audit ranked its second-highest-value missing shape.

| Field | Value |
|---|---|
| `kind` | `Kind.ARC` (append) |
| `mp_cost` / `cooldown` | **78** / **6.5 s** |
| `damage` | **110** |
| `cast_time` | **1.25 s** (channel tier) |
| travel | **900 px at 640 px/s** → 1.4 s of flight |
| half-height | grows **90 → 300 px** over the flight (the concave face leads) |
| thickness | 30 px |
| band | centred on the aim line. **Aim high and it passes over grounded bodies.** |

**Dodge window:** the 1.25 s cast, *then* 1.4 s of visible travel, *then* the band choice — three separate outs. The high-damage number is priced against all three.

**Deflect:** it travels → the `reflect()` path (`SpellDeflect.gd:34`). A deflected Horizon Cut **turns around and comes back**, at full damage, with `_owner` cleared. That is the best moment this class can produce for the person fighting it, and it is why 110 is acceptable.

**Cast pose:** new `Pose.UNSHEATHE` — the blade drawn across the body over the charge, released in a single frame. Duration = the spell's `cast_time`. Append to `CastStyle.Pose` and `CastStyle.duration()`.

**Circle:** `LINE` motif, laid **along the aim from the caster to 900 px**, glyphs igniting in sequence outward as the charge progresses. The glyph line **is** the height-band telegraph — anyone can see exactly which horizontal band is about to be deleted, from the first 0.2 s. This is the single best argument in the document for the class-motif work in §3.3: a bespoke circle here is not decoration, it is the counterplay.

### 4.6 Signature 2 — **Panoply** (`Kind.VOLLEY`, new shape)

> Eight rifts open in a ring around you and start throwing blades — one every fifth of a second, each one along wherever you are pointing at the instant it fires. You do not aim it. You conduct it.

| Field | Value |
|---|---|
| `kind` | `Kind.VOLLEY` (append) |
| `mp_cost` / `cooldown` | **62** / **5.5 s** |
| `damage` | **26** per blade |
| `count` | **8** |
| ring radius | 110 px around the caster |
| sequence | one blade every **0.20 s** → **1.6 s** total |
| blade speed | **900 px/s**, 700 px range |
| caster | moves at **60 %** speed for the duration; not rooted |
| `cast_time` | 0 → the **0.42 s** planted-signature windup |

**The interrupt curve is deliberately partial.** A landed hit of **≥18** shatters the remaining rifts; blades already fired stay. That is a better shape than all-or-nothing for a sustained spell — a hit costs you the rest of the volley, not the whole cast — and it is the one place in this document where partial credit is correct, because the spell's output is genuinely incremental.

**Deflect:** each blade travels → `reflect()` path, each independently. Deflecting one blade out of eight is a small win, which is right.

**Circle:** the eight rifts **are** the circles — eight small **edge-on** `MagicCircle`s (radius 26), each rotated to face its own firing direction at the moment it opens. No separate ground sigil. This is the cleanest instance of "the spell circle is the mechanic" in the whole kit.

**Pose:** `POINT`, held for the full 1.6 s while the free hand sweeps.

**Distinctness is conditional and stated in §2.4.** If this ever becomes a single instant fan, delete it.

### 4.7 Signature 3 — **Closed Ground** (`Kind.DOMAIN`)

The Swordsaint's Sealed Ground. Full spec in §6.4.1.

### 4.8 The config

```gdscript
HeroClass.SWORDSAINT: {  # SWORDSAINT — the drag duelist; damage is the PATH of the blade
    "preset": "swordsaint", "weapon": "greatsword",
    "element": Elements.Element.ARCANE, "melee_element": -1,   # plain steel: no ailment
    "primary": "blade_drag",
    "cast_cd": 0.45, "dash_cd": 0.80, "blink_cd": -1.0, "blast_cd": 3.0,
    "throw_blade": false, "blade_damage": 18,
    "dash_strike": true, "dash_strike_damage": 24, "dash_strike_range": 52.0,
    "defense": "held_guard", "aoe": "cross_slash",
    "has_nova": false, "can_parry": false,   # the drag IS the deflect
},
```

`WEAPON_STATS["greatsword"] = {"damage": 26, "range": 86.0, "knockback": 430.0}` — used by `dash_strike` and by the rig; the drag computes its own damage.

`SpellLibrary.build_for_class(8)` → `[_horizon_cut(), _panoply(), _closed_ground()]`.

**Files that must change for a 9th class to exist at all:**
- `Hero.gd:150` enum, `:151` `CLASS_NAMES`, `:155+` `CLASS_CONFIG`
- `scripts/ui/Lobby.gd:83` — `% 8` → `% Hero.HeroClass.size()` (**this is a live bug waiting to happen**, not a nicety: the lobby would silently make the 9th class unselectable)
- `tools/slice5_test_classes.gd:67` — `== 8` → `== 9`
- `CharacterRig` — a `"swordsaint"` preset and, more importantly, `set_blade_angle(rad)` plus `get_weapon_tip()` honouring it. **This is the largest rig change in the document** (§10.3).
- `AbilityBar` slot 6 label: `"Guard"` instead of `"Parry"` when `defense == "held_guard"`.

### 4.9 Mobile — the one honest problem in this document

Every other thing here is one tap. **The drag is not**, and pretending otherwise would be dishonest.

The good news is that a drag is arguably a *better* fit for a finger than for a mouse: on touch, the **right half of the screen becomes the blade** — where your thumb is, the blade points; how fast you move it, that is the swing speed. That is a direct, physical, one-to-one mapping with no buttons at all, and the right half is currently free real estate (`TouchControls` has no melee button today — defect #2 in the mobile-casting spec).

But it **collides with the 4-slot tap pad** that spec proposes for the same region. Two options, both needing a maker decision:

- **(A)** Slots move to the left rail above the joystick; the right half is the blade. Cleanest for the Swordsaint, disruptive for the other eight classes.
- **(B)** The right half is the blade **only for the Swordsaint**; other classes keep the tap pad. Per-class input layouts are a maintenance smell, but it is the smaller change and it keeps the eight shipped classes untouched.

**Recommendation: (B), and treat it as the reason to build the drag in the playground first** (§9.1 step 4). If the drag does not feel extraordinary with a mouse it will not survive a per-class touch layout either, and that is cheap to find out.

---

## 5. **Second Sun** — the sun-summon signature (`Kind.SOURCE`, new shape)

> The world goes dark. A sigil opens overhead. And then something too bright to look at settles into the arena and stays there, and for the next eight seconds the fight is about where that thing is.

**Class: Cleric.** Element **HOLY**. Three reasons: the class is a *radiant* sustain bruiser whose current signature is a convergence nova (`heavens_verdict`) and this is a bigger, stranger, better version of that fantasy; HOLY is already the game's sun colour and this avoids adding a sixth fire spell; and HOLY opposes SHADOW in `ReactionTable.OPPOSED`, so a Warlock's shadow domain versus the sun is an authored reaction for free.

### 5.1 Why a source and not a bombardment — scored against the audit

§2.3 has the verdict. The property list that makes `SOURCE` a genuinely new shape:

| Property | Any existing spell? |
|---|---|
| A world position **in the air** that persists | No |
| Emits **continuously with distance falloff** (no boundary to step over) | No — `ZoneSpell` is a hard-edged ground ellipse |
| **Moves on its own** | No |
| **Attackable** — the spell itself has HP | **No. Nothing in the kit can be destroyed by the enemy.** |
| **Shoveable** — physics apply to it | Only `RockWall.shove()`, on a barrier |
| Changes the **arena's look** while up | No |

That fourth row is the most important one in this document after the domain anchor. **The kit has never had a spell the opponent can fight.**

### 5.2 Numbers

| Field | Value |
|---|---|
| `kind` | `Kind.SOURCE` (append) |
| `element` / `effect` | `HOLY` / `"holy"` |
| `mp_cost` / `cooldown` | **92** / **20.0 s** |
| `cast_time` | **1.9 s** (second-longest in the game; see the ladder, §3.4) |
| `damage` | **14** per scorch tick |
| tick rate | **0.5 s** → 16 ticks over its life |
| lifetime (`length`) | **8.0 s** |
| `radius` | **300 px** influence; full damage inside **120 px**, linear falloff to **25 %** at 300 |
| burn | `apply_status(HOLY)` inside 180 px |
| placement (`reach`) | `caster + aim × 260`, clamped **180–420 px**, then raised so it hangs **≥150 px above the floor** (raycast up; hangs under a ceiling if there is one) |
| drift | **22 px/s toward the arena's horizontal centre**, plus a ±6 px bob |
| HP | **90**, in groups `"destructible"` and `"spell_source"` |

**Friendly fire: ON.** It scorches the caster, allies and enemies alike. That is the honest reading of the project's Magicka-soul direction, it is why the drift exists (you cannot camp under your own sun), and it is what makes the spell a decision rather than a button.

**Death:** at 0 HP it does **not** explode — it gutters out over 0.5 s with the light draining from the arena. Punishing the opponent for killing it would delete the counterplay the whole shape exists to create.

### 5.3 What the world does

- `PostProcess._bump_heat` driven continuously while it is up — the heat haze the effect already implements becomes literal.
- `_apply_theme` shifts the arena tint warm over 0.4 s on arrival and back over 0.8 s on death. `Atmosphere.gd` handles the theme; the sun overrides it temporarily.
- `_begin_shock(1.0, sun_screen_pos)` fires once on arrival — the existing ripple, at the right place.

### 5.4 The three beats

| t | Beat | What happens |
|---|---|---|
| 0.00–0.45 | **DECLARE** | Card: `SECOND SUN`. **The world darkens 25 % and desaturates to 0.45** — double the ordinary declare, and the *opposite* direction from what is coming. The eclipse before the dawn. Caster's circle: `ECLIPSE` motif, face-on, **radius 96**. |
| 0.45–1.10 | **CHARGE (near)** | Levitating channel (`_begin_channel`, existing). Circle grows and spins; motes converge. |
| **1.10** | **CHARGE (far) — the on-target telegraph** | A **190 px face-on sky sigil** opens at the placement point with a white point of light at its centre, growing. **Everyone now knows exactly where the sun will hang, 0.8 s before it does.** This is the spell's dodge window and it is generous on purpose — the counterplay to a persistent hazard is positional, so the position has to be published. |
| **1.90** | **RELEASE** | The point detonates into the body. `Juice.epic_moment({"strength": 1.4, "frame": true})`, `Juice.zoom_pull_camera(0.34, 1.0, 0.15, 0.7)`, `PostProcess._begin_shock`. The world snaps from dark to **over-bright** over 0.25 s with a 12 % overshoot. |
| 1.90–9.90 | **UP** | Drift, bob, tick, burn, light. |

### 5.5 What the opponent does about it

Four distinct answers, which is more than any other spell in the kit offers:

1. **Break the cast.** 1.9 s and the caster is levitating and rooted. 399 px of approach at walking speed.
2. **Read the sky sigil** at t=1.10 and be outside 300 px when it lands.
3. **Shoot it down.** 90 HP. This is the answer that does not exist anywhere else in the game.
4. **Shove it.** It responds to `apply_knockback` — a Juggernaut boulder, a nova, a wall shove sends it drifting at 140 px/s for 1.2 s. Putting the enemy's sun over the enemy is the best play in the document.

### 5.6 Deflection

Per `SpellDeflect`'s own doctrine (`SpellDeflect.gd:29-41`): *"if it has a position that moves, give it `reflect()`; otherwise route its damage through `resolve()`."* The sun moves, but it is not aimed at anyone and cannot be sent back to sender — the doctrine's intent is reversibility, not motion. So:

- **Each scorch tick routes through `SpellDeflect.resolve(victim, damage, dir, at, WINDOW_ULT)`.** A parry (or a Swordsaint drag above ~816 px/s, §4.3) timed into a tick **eats that tick**. You cannot reflect a sun; a perfect guard shrugs off a pulse.
- The **physical** counterplay (shove, §5.5.4) is the reflect-shaped answer, and it is better than reflection would be because it moves the threat rather than deleting it.

Note the interaction: at 0.5 s between ticks and a 0.16 s parry window, parrying the sun continuously is impossible. It is a way to survive a bad moment, not a way to ignore the spell. That is correct.

---

## 6. Sealed Grounds (domains)

### 6.1 The mechanic in one paragraph

A **Sealed Ground** is a bounded region in which **one rule of the game is different for everyone inside**, anchored to a destructible sigil, sealed after the longest cast in the game, and escapable by walking out. It deals **no damage**. It is `Kind.DOMAIN`, `ReactionTable.Form.DOMAIN`, and it is the first thing in the kit whose payoff is not a hit.

### 6.2 Shared numbers

| Field | Value | Why |
|---|---|---|
| `cast_time` | **2.6 s** | The counterplay budget (§3.4). Non-negotiable downward. |
| `mp_cost` | **90** | Nearly the whole 100 pool. A domain is your turn. |
| `cooldown` | **22.0 s** | ≈3× the duration; uptime ≤32 %, matching the protection spec's §7.1 uptime rule. |
| `radius` | **480 px** | ~2.3 s of running from centre to edge at `SPEED` 210. Big enough to matter, small enough to leave. **First tuning knob.** |
| duration | **7.0 s** nominal | Nominal, not actual — the anchor decides (below). |
| **anchor** | **40 px sigil at the centre, 60 HP**, groups `"destructible"` + `"domain_anchor"` | ~3 s of focused fire. The real duration knob. |
| collapse | boundary implodes 0.35 s, **0 damage**, caster **staggered 0.8 s** (`apply_status(EARTH)`), no cooldown refund | §3.5 consequence 3 |
| rule scope | **symmetric** — allies, enemies and the caster alike | A domain is a bet, not a buff |

**Three escapes, always:** interrupt the 2.6 s cast · walk across the boundary · break the anchor.

### 6.3 The seal, as a visual

The `SEAL` motif is not a decoration; it is the entire telegraph.

- **During the cast (0 → 2.6 s):** a `MagicCircle` at the caster's feet grows from **60 px to the full 480 px radius**, drawn on the ground. Anyone can see the exact footprint and the exact deadline from the first frame.
- **At 2.6 s — the seal:** the boundary snaps upward into a translucent vertical wall of glyphs. `Juice.epic_moment({"strength": 1.3})`, `PostProcess._begin_shock(1.2, centre)`. Inside, the arena tint shifts to the domain's colour.
- **Crossings:** a body crossing the boundary flashes it at the crossing point. **No damage, no slow, no push** — the wall is information, not a wall.
- **The anchor:** a floating sigil at the centre, visibly cracking as its HP falls, with a small ring showing the fraction remaining. It must read as a target from across the arena.

### 6.4 Three domains

Each flips a **different existing rule**, so no two feel alike. Rules chosen because the player already understands them — a flipped rule reads instantly only if it was legible in the first place.

#### 6.4.1 **Closed Ground** — Swordsaint

**The rule: no ranged damage crosses the boundary.** Any travelling projectile, beam, or placed spell that crosses the seal — in either direction — is **nullified at the edge** with a visible pop. Inside, spells still work *on things inside*.

- `element: -1` — **inherits the caster's current element**, so the X-cycle changes which domains it collapses against (§6.5). The only spell in the game where element cycling has a strategic consequence.
- **This is the swordsman's answer to the whole ranged half of the roster.** The Swordsaint's structural problem is that eight other classes can hurt him from 900 px. Closed Ground says: not in here.
- **It does not silence anyone.** Your co-op mage can still cast, still hit things inside the box, still be useful. That distinction is the difference between a great co-op mechanic and the most rage-inducing object ever shipped. *(An earlier draft of this spec proposed a silence domain. Cut it. Silencing an ally for 7 s is indefensible.)*
- **Counterplay:** step out and shoot from outside — the caster cannot reach you through his own wall either. Or break the anchor; the Swordsaint has no way to protect it while he is fighting you.

#### 6.4.2 **Overtone** — Arcanist

**The rule: amplified casting, no fuel.** Inside: all spell damage **×1.5**, cooldowns tick at **2×** — and **MP does not regenerate at all**.

- `element: ARCANE`.
- The purest expression of "a domain is a bet." You get a burst window whose length is exactly however much mana you walked in with.
- **Symmetric, and that is the whole game with it.** Dropping Overtone in a room of enemy casters doubles *their* output too. Against chargers it is free; against a caster pack it can kill you.
- **Counterplay:** leave, and their amplification leaves with them. Or fight them at the edge, where you can duck in and out of the buff and they are committed to it.

#### 6.4.3 **Leadfall** — Juggernaut

**The rule: nobody escapes.** Inside: **no dashes, no blinks, no i-frames**; gravity **×1.8**; jump height **×0.7**. Everything connects.

- `element: EARTH`.
- The cleanest possible demonstration that a domain is a rule change and not an explosion: it does not add a single point of damage, and it is terrifying.
- **Class-asymmetric by design, not by cheat.** Juggernaut has the slowest dash (0.90) and no blink; he gives up the least. That is a legitimate class advantage in a symmetric rule, which is exactly how a good rule flip should work.
- **Counterplay:** walk out — you can still walk, just not dash. Or break the anchor, which is now the only thing worth doing inside it.

### 6.5 The clash rule

`ReactionTable` gains `Form.DOMAIN`, one `form_for_kind` arm, and three rows. `SpellGeometry.overlaps(circle, circle)` is a single distance test and `meeting_point` / `bisector` already do the rest — this is the case the geometry file was built for.

| Condition | Outcome | Effect |
|---|---|---|
| **Same element** | `domain_merge` (priority 60) | The two boundaries fuse into one region; **both rules apply**. Both anchors persist — killing **either** collapses the whole thing. Constructive case, mirroring the existing `field_merge` row (`ReactionTable.gd:154`). |
| **Opposed elements** | `domain_collapse` (priority 100, consumes both) | **Mutual annihilation.** Both anchors shatter, both rules end, and a **220 px, 120-damage** burst fires at `SpellGeometry.meeting_point()` along `SpellGeometry.bisector()`, **hitting everyone including both casters**. This is the one time a domain damages anything. Structurally identical to the existing `hollow_purple` row (`:100`) — same predicate, same consumption, same reason. |
| **Different, non-opposed** | `domain_contest` (priority 30) | **Neither rule applies inside the overlap lens.** A dead zone. Both boundaries visibly bow away from each other. Tactically the most interesting outcome: you can neutralise someone's rule by parking your own on top of it. |

```gdscript
_rule("domain_collapse", Form.DOMAIN, Form.DOMAIN, {
    "require_opposed": true, "priority": 100,
    "consumes_a": true, "consumes_b": true, "radius": 220.0, "damage": 120,
}),
_rule("domain_merge", Form.DOMAIN, Form.DOMAIN, {"require_same": true, "priority": 60}),
_rule("domain_contest", Form.DOMAIN, Form.DOMAIN, {"priority": 30}),
```

**How a domain plugs into the reactor that now exists (§1.4.1).** `DomainField` implements the six-method participant contract and calls `SpellReactor.register(self, ReactionTable.Form.DOMAIN, element)` **at the moment it seals** — never during the cast, which is exactly what `reaction_active()` is for (a domain must not clash while it is still a growing preview, the same way a beam must not clash during its 0.34 s charge). Specifically:

- `reaction_shape()` → `SpellGeometry.circle(_centre, radius)`. **Built from `_centre`, never from `global_position`** — the reactor's header calls that out as the trap it is built around, and a domain parked at the arena origin would otherwise report as touching everything.
- `reaction_active()` → `_sealed and not _collapsing`.
- `reaction_consume()` → collapse without the ordinary end-of-life beat (no stagger refund logic, no cooldown change — the collapse *is* the reaction's payment).
- `reaction_freeze()` → **not implemented.** A domain has nothing to pin; two domains resolve, they do not seize each other.

Then three new outcome arms in `ReactionOutcomes.apply()` (`domain_collapse`, `domain_merge`, `domain_contest`) and one `form_for_kind` arm. `MAX_LIVE = 12` is far above realistic domain concurrency (1–2), and `MAX_REACTIONS_PER_TICK = 2` means a three-way domain pile-up resolves over two 33 ms ticks rather than in one frame — acceptable, and worth asserting in the test so the ordering is deliberate rather than incidental.

### 6.6 The implementation seam, and its real cost

A rule flip is not free. Each one is a handful of query calls scattered through existing code, and pretending otherwise is how this feature becomes a three-week hole.

New static file `scripts/combat/DomainField.gd`:

```gdscript
static var active: Array = []                              # live DomainField nodes

static func any() -> bool                                  # early-out; empty = zero cost
static func at(p: Vector2) -> Array                        # domains containing p
static func blocks_crossing(from: Vector2, to: Vector2) -> bool   # Closed Ground
static func cast_mult(p: Vector2) -> float                 # Overtone damage
static func cooldown_mult(p: Vector2) -> float             # Overtone cooldowns
static func mp_regen_allowed(p: Vector2) -> bool           # Overtone fuel
static func mobility_locked(p: Vector2) -> bool            # Leadfall dash/blink/i-frames
static func gravity_mult(p: Vector2) -> float              # Leadfall
```

Call-site count, counted honestly:

| Rule | Sites | Where |
|---|---|---|
| Closed Ground | **~8** | the move loop of each travelling spectacle (`Spell`, `EnemyProjectile`, `BoulderHurl`, `RuneOrbs`, `RiftDagger`, `ShadowCrawler`, plus the two new travelling shapes) |
| Overtone | **~5** | `Hero._cast_signature`, `Hero._physics_process` (regen + cooldown ticks), `Enemy` equivalents |
| Leadfall | **~6** | `Hero._physics_process` gravity, `_try_dash`, blink, the two i-frame checks in `take_damage`, `Enemy` |

**Every one is a one-line guard behind `DomainField.any()`, so with no domain live the cost is a single static array emptiness check.** Each predicate gets a headless test (`tools/domain_test.gd`, the `all PASS` idiom from `tools/m11_test_patience.gd`). ~19 call sites is the number; it is not enormous, but it is the reason domains are step 8 and not step 1.

---

## 7. The framework applied to all nine classes

Every class's **first** signature becomes its declared one. Two of the nine currently have the wrong spell in the first slot, and that is worth fixing while the framework is being wired.

| Class | Declared signature | Card text | Circle motif | Tier / windup | Note |
|---|---|---|---|---|---|
| **Arcanist** | `zoltraak` → **"The Ordinary Spell"** | `THE ORDINARY SPELL` | `ARCANE` face-on + the existing edge-on muzzle gate | Channel 1.0 s | **Renamed (§8).** The description is rewritten to drop the citation; the fantasy — the most basic magic, perfected — is kept, because the fantasy is not the property. |
| **Shadowblade** | `blink_strike` "Shadow Step" | — | `SHADOW` | **Fast 0.22 s** | **No card.** Mobility burst; declaring a blink is declaring nothing. |
| **Brawler** | `chidori` → **"Levin Fist"** | `LEVIN FIST` | `FRACTURE` (no ring) | **Fast 0.22 s** | **Renamed (§8).** No card, same reason. His declaration is the ground cracking. |
| **Juggernaut** | `boulder_hurl` → **reorder to `colossus_pillar`** | `COLOSSUS PILLAR` | `MASONRY` | Channel 1.0 s | **Reorder.** Boulder Hurl is a good spell and a poor identity; the titanic spire is the class. One-line change in `build_for_class(3)`. |
| **Cleric** | `heavens_verdict` | `HEAVEN'S VERDICT` | `HALO` | Channel 1.3 s | The longest existing telegraph in the kit — already the best-suited to ceremony. Gains **Second Sun** as a second declared signature (§5). |
| **Cryomancer** | `ice_wall` → **reorder to `blizzard`** | `BLIZZARD` | `HEXFROST` | Planted 0.42 s | **Reorder.** A defensive utility wall is not a signature. Flagged as the weakest signature in the roster even after the swap — this class wants a bespoke one eventually. |
| **Stormcaller** | `chain_lightning` | `CHAIN LIGHTNING` | `STORM` (ring redraws every 0.08 s) | Planted 0.42 s | Generic name, but genuinely its own shape. Fine. |
| **Warlock** | `void_zone` "Shadow Root" | `SHADOW ROOT` | `INVERSE` | Planted 0.42 s | Fine as-is. |
| **Swordsaint** | `horizon_cut` | `HORIZON CUT` | `LINE` (along the aim) | Channel 1.25 s | New (§4.5). |

**Two structural observations from building this table:**

1. **The declared signature should be the class's identity, not its first-authored spell.** Two of eight are wrong today purely because of authoring order. Worth a one-line reorder each and a note in `build_for_class`'s docstring that **position 0 is the declared signature**.
2. **Cryomancer is the roster's weakest identity** and the framework makes that visible rather than causing it. Not this document's job to fix; flagged so it does not get discovered during a playtest and misattributed to the framework.

---

## 8. The IP rename pass

**The rule: any string a player can SEE must be original. `id` values are not player-visible and may stay** (they key saved loadouts and the playground's raw-index capture tool — renaming them is a migration for no safety gain).

| File · line | Field | From | To |
|---|---|---|---|
| `SpellLibrary.gd:80` | `display_name` | `"Zoltraak · Arcane Beam"` | **`"The Ordinary Spell"`** |
| `SpellLibrary.gd:81-82` | `description` | `"Frieren's ordinary offensive magic, perfected. A sigil blooms and a lance of mana crosses the whole arena."` | **`"The first spell anyone learns, practised until it is the last one you need. A sigil blooms and a lance of mana crosses the whole arena."`** |
| `SpellLibrary.gd:122` | `display_name` | `"Chidori · Thunderclap"` | **`"Levin Fist"`** |
| `ReactionTable.gd:98,100` + `ReactionOutcomes.gd` + `SpellReactor.gd` + `HollowPurple.gd` + `tools/hollow_purple_capture.gd` | outcome key, class name, file name | `"hollow_purple"` / `HollowPurple` | **`"annihilation_collapse"` / `AnnihilationCollapse`** — **no longer free (§10.12).** A live multi-file system as of this recon; sequence it as its own atomic rename commit after that feature stabilises, not as part of step 3. |
| `Hero.gd:173` | comment | `"+ Chidori"` | `"+ Levin Fist"` (cosmetic, keeps grep honest) |

**Safe as-is** (generic fantasy vocabulary, no rename needed): `Judgment · Divine Ray`, `Heaven's Verdict`, `Meteor Sigil`, `Shadow Step`, `Blade Flurry`, `Shadow Root`, `Drain Tether`, `Creeping Shade`, `Rift Dagger`, `Colossus Pillar`, `Frostpiercer`, `Infernal Lance`, `Umbral Lance`, `Tempest`, `Avalanche`, `Blizzard`, `Boulder Hurl`, `Rock Pillar`, `Rock Wall`, `Ice Wall`, `Arcane Missiles`, `Chain Lightning`, `Void Barrage`, `Frozen Comet`. All nine class names are safe.

**Internal-only, no risk:** `magic-overhaul-plan.md` citing JJK as a quality bar; `SpellLibrary.gd`'s "Frieren / isekai / divine north-star" header comment; this document. Comments and design docs do not ship as player-facing text.

**Names this document deliberately does not use, and neither should anything downstream:** Excalibur · Noble Phantasm · Saber · Gate of Babylon · Unlimited Blade Works · Domain Expansion · Hollow Purple · Infinite Void · Chidori · Zoltraak · The One · Sunshine.

**Originals introduced here, all checked as ordinary English or coinages:** Swordsaint · Horizon Cut · Panoply · Held Guard · Second Sun · Sealed Ground · Closed Ground · Overtone · Leadfall · Levin Fist · The Ordinary Spell.

---

## 9. Build order

Cheapest convincing thing first. Each step is independently verifiable and independently shippable.

### 9.1 The order

| # | Step | Why here | Verification |
|---|---|---|---|
| **1** | **The DECLARE beat.** `SignatureRite.gd` + the card + world desaturation + the three suppression rules; hooks in `Hero._begin_summon` (`:955`) and `_begin_channel` (`:1067`). No new spells. No balance change. | **Highest value in the document.** ~150 lines make all 26 existing ultimates feel like named attacks. If the maker does not like the beat, everything downstream is cheaper to redesign now than later. | New `tools/signature_capture.gd`: render three casts (planted / channelled / fast-suppressed) → PNGs in `%APPDATA%\Godot\app_userdata\Legacy Frontier\`. **Look at them.** Then maker F5. |
| **2** | **`MagicCircle.motif` + the nine class motifs** + `CLASS_MOTIF` lookup + `SpellDef.circle_motif` override. | Independent of step 1, makes it three times better, and directly answers the maker's spell-circle ask. | Extend `tools/circle_capture.gd` to a grid of all eleven motifs. Look at the image. |
| **3** | **The IP rename pass — the two `display_name`/`description` fixes only** (§8). | Two strings and a comment. Cheap, independent, and exactly the sort of thing that gets forgotten for a year. **The `hollow_purple` rename is explicitly NOT part of this step** — it is now a live multi-file system (§10.12) and gets its own commit later. | `grep -rn "Zoltraak\|Chidori" godot-project/scripts` returns only `id` values. |
| **4** | **The blade drag, in the playground only.** `scripts/spike/SpikeFigure.gd` gains `blade_drag`; no class, no Hero changes. | **The highest-risk feel item in the document.** The Swordsaint is worthless if the drag is not extraordinary, and this is the cheapest possible way to find out. | Maker F5s `SpellPlayground`. Pure go/no-go. |
| **5** | **The Swordsaint class.** `CLASS_CONFIG[8]`, `greatsword` stats, `CharacterRig.set_blade_angle`, Held Guard on RMB, `Lobby.gd:83` fix, `slice5_test_classes.gd` → 9. | Only after step 4 says the verb is good. | `tools/slice5_test_classes.gd` green at 9 classes; `tools/loadout_capture.gd` extended. |
| **6** | **Second Sun** (`Kind.SOURCE`, `SunBody.gd`). | Fully independent of 4–5 — it is a Cleric spell. The single most spectacular thing here, and the best build-in-public clip in the document. | New capture: 1.9 s cast + 8 s life + a shoot-it-down pass + a shove pass. Look at the images. |
| **7** | **Horizon Cut** (`Kind.ARC`, `HorizonArc.gd`, `Pose.UNSHEATHE`). | Needs the class. Proves the travelling-arc shape and the height band. | Capture at three aim heights: over a grounded enemy, through it, under it. Plus a deflect pass. |
| **8** | **Domain plumbing + Closed Ground.** `Kind.DOMAIN`, `DomainField.gd`, `DomainAnchor`, the 2.6 s cast path, the ~8 Closed Ground call sites. | The most expensive step (§6.6). Do it once the class it belongs to exists and is fun. | `tools/domain_test.gd` — every predicate, plus the anchor-death collapse and the caster stagger. Then F5. |
| **9** | **Panoply** (`Kind.VOLLEY`). | Cheapest of the three Swordsaint signatures; deliberately last of them so the class ships playable at step 7. | Capture the full 1.6 s sequence with the aim sweeping. |
| **10** | **Overtone + Leadfall + the three clash rows** (registered against the existing `SpellReactor`, §6.5). | The clash is the payoff, and it needs two domains to exist before it can be seen. | `tools/domain_test.gd` extended: merge / collapse / contest, plus the origin-parked negative case the reactor's own suite asserts. |

### 9.2 Shape scorecard — every new thing, against §1.3

| Thing | Shape | New? |
|---|---|---|
| DECLARE beat | — | Presentation, not a shape. Costs nothing against the census. |
| Blade drag | **M** melee arc | **Not a new shape — a new INPUT MODEL for an existing one.** Honest: the census does not move. The novelty is analogue damage and emergent deflect, not delivery. |
| Held Guard | `STANCE` / `Form.BARRIER` | New verb (bank-and-return), reusing the protection spec's Kind. |
| **Horizon Cut** | **travelling curved wall + height band** | **New.** Fills audit §C.2 (partly) and §C.3 (fully). |
| **Panoply** | **sequenced steerable emitter array** | **New, conditionally** (§2.4). |
| **Second Sun** | **persistent emitting SOURCE object** | **New.** The kit's first attackable, shoveable, world-altering spell. |
| **Sealed Ground** | **bounded rule flip** | **New category**, not merely a new shape. |

Four new shapes, one new category, one honest "not a new shape."

### 9.3 Cost, honestly

| Step | Rough size | Risk |
|---|---|---|
| 1 DECLARE | ~150 lines, 2 functions touched | Low |
| 2 Motifs | ~200 lines of `_draw` branches | Low |
| 3 Rename | 5 strings | None |
| 4 Drag (playground) | ~250 lines | **High — it either feels great or the class dies** |
| 5 Class | ~200 lines + a real rig change | Medium — `set_blade_angle` is the largest rig change here |
| 6 Second Sun | ~400 lines (a new spectacle with HP, drift, light) | Medium |
| 7 Horizon Cut | ~300 lines | Medium |
| 8 Domains | ~350 lines + ~19 call sites + tests | **Highest total cost in the document** |
| 9 Panoply | ~200 lines | Low |
| 10 Two more domains + clash rows | ~180 lines (the reactor already exists) | Medium |

---

## 10. Risks — what will be un-fun, unbalanced, or too expensive

### 10.1 Declare fatigue is the number-one risk to step 1

Forty ults into a climb, ceremony becomes a tax. The three suppression rules (§3.2) exist entirely for this, and the 12 s repeat window is the one most likely to need tuning. **The failure signal in playtest is specific: the maker starts saying "get on with it."** If that happens, tune the repeat window up before touching the card's timing — a card that flashes too fast is worse than no card.

### 10.2 The drag can shred, and the stroke rule is the only thing stopping it

Speed-scaled damage plus a continuous verb is an exploit-shaped hole. The one-hit-per-stroke rule (§4.2) closes it, but it must be tested adversarially: **deliberately try to wiggle-shred in the playground before shipping the class.** If a fast circular drag out-DPSes every other class's primary, the fix is a longer `STROKE_DEAD`, not a lower `CUT_BASE` — lowering the base punishes good play to fix bad.

### 10.3 `CharacterRig.set_blade_angle` is the largest hidden cost in the document

Every other class's weapon is a prop that follows a canned animation. The Swordsaint's must be **driven per-frame from an external angle**, and `get_weapon_tip()` (`CharacterRig.gd:597`) — which four spell paths already call for their spawn origin — must honour it. This is the item most likely to be underestimated. Read `CharacterRig.gd:295` (`hit_frame` emission) before starting: the drag does **not** use `hit_frame` at all, which means the Swordsaint is the first class whose melee bypasses the rig's strike-frame signal, and `Hero._on_melee_hit_frame` must not run for it.

### 10.4 Domains in co-op with symmetric rules will annoy someone

Overtone doubling an enemy caster pack's damage is a design feature. **Your ally's Leadfall taking your dash away for 7 s is a design feature that will feel like a bug.** Mitigations are already in: rules never silence, boundaries are always walkable, durations are ≤7 s, and the anchor lets an annoyed ally end it themselves. If playtest still says it is miserable, the lever is a `friendly_exempt: bool` on the domain def — **but do not ship that lever pre-emptively.** Symmetric rules are what make a domain a bet, and pre-emptively softening it means never finding out whether the bet was fun.

### 10.5 Enemy AI does not know how to leave a domain

`Enemy.gd` has no concept of a hazard region. A domain that hurts enemies is therefore free value against them, and a domain a *boss* casts is unfairly good against the player, who *can* leave. Two consequences: (a) domains will test stronger against AI than they are; (b) do not give a boss a domain until enemies can path out of one. **Flagged as a prerequisite for boss domains, not for player domains.**

### 10.6 Second Sun's friendly fire will be the loudest complaint and is the most correct decision here

A sun that scorches your ally is exactly the Magicka-soul the project chose, and it is why the spell has a drift and a shove interaction. **Expect the first co-op playtest to hate it.** Hold the line for at least two sessions before changing it; the alternative (a sun that only burns enemies) is a bombardment with a long duration and belongs in the cluster the audit condemned.

### 10.7 A ninth class multiplies QA surface across six systems

Gear (`GearAbilities`, `tools/gear_capture.gd`), the co-op lobby (`Lobby.gd`), the bot layer (the smart-bots plan assumes a `ClassDef` per class), touch controls, the ability bar, and the class-cycle test all take the ninth class. **`Lobby.gd:83`'s `% 8` is the specific one that will silently make the class unselectable in co-op** and produce a bug report that reads as "the Swordsaint doesn't exist."

### 10.8 The reactor exists now, which moves the clash risk rather than removing it

`SpellReactor` landed during this recon (§1.4.1), so §6.5 is no longer blocked on first-of-kind engine work — it is three data rows, three outcome arms, and six contract methods. The residual risks are different and more specific:

- **`reaction_active()` is load-bearing and easy to get wrong for a domain.** Registering during the 2.6 s cast would let two growing previews annihilate before either sealed. Register at seal, not at cast.
- **`reaction_shape()` must be built from the domain's own `_centre`.** The reactor's own header documents this as *"a bug that fails LOUD in the wrong direction"* — every pair reporting as touching at the arena origin. `tools/slice6_test_reactor.gd` already asserts the negative case; the domain test must add its own.
- **The reactor is a new autoload with a 30 Hz poll**, and this document adds the largest reactants it will ever hold (480 px circles). That is cheaper than beams, not more expensive, but it is the first time the geometry is circle-vs-circle at that scale.

### 10.12 The `hollow_purple` rename is no longer free

§8 lists renaming the `"hollow_purple"` outcome key as costless because the table had no callers. **That changed during this recon:** there is now `scripts/combat/HollowPurple.gd`, an arm in `ReactionOutcomes.apply()`, a `_hollow_purple` handler, `SpellReactor._hollow_purple` / `hollow_purple_live()` / `claim_hollow_purple()`, and `tools/hollow_purple_capture.gd`. The rename is now a **multi-file refactor of a live system**, not a string edit. It is still worth doing — the key is a named technique from a named work, and it will eventually surface in a debug HUD or a capture filename — but it should be **sequenced after that feature stabilises**, and it should be one atomic rename commit rather than folded into §9.1 step 3. Step 3 should ship the two `display_name`/`description` fixes only.

### 10.9 `Kind` is append-only and this document appends four

`SpellDef.gd:13-15` is explicit: inserting renumbers `BOULDER`/`PILLAR`/`WALL` and breaks their dispatch arms. This document appends **`ARC`, `VOLLEY`, `SOURCE`, `DOMAIN`** — and the protection spec independently appends **`WARD`, `STANCE`, `DECOY`**. **If both land in either order, they must not both claim the same ordinals.** Recommendation: land the protection spec's three first (they are already specified and `GuardComponent` is live), then these four. Note it in whichever commit goes second.

### 10.10 `tools/spell_playground_capture.gd` addresses spells by raw index

The uniqueness spec's §D.12 warning still applies and now applies harder: the tool indexes into `SpellLibrary.build_all()`, so **appending is safe and inserting silently re-points every existing capture.** Five new spells go on the end, in this order: `horizon_cut`, `panoply`, `closed_ground`, `second_sun`, then the two other domains.

### 10.11 The two "reorders" in §7 change what players see on the V cycle

Swapping Juggernaut's and Cryomancer's position-0 signature changes which spell is equipped by default and therefore which one appears in the ability bar on class select. Harmless in the sandbox; in a persistent climb it changes a saved loadout's meaning if position is what is persisted. **Check `GameState.loadout`'s shape before reordering** — if it stores an index rather than an id, the reorder is a save migration.

---

## 11. Open questions for the maker

1. **The DECLARE repeat window (§3.2) — 12 s, or should the card only ever play once per floor?** Once-per-floor is more special and more likely to be under-used; 12 s is safer. My recommendation is 12 s, tuned upward on complaint.
2. **Mobile input for the drag (§4.9) — layout (A) or (B)?** (B) — per-class right-half — is my recommendation, and it is a decision that can wait until after step 4 proves the verb.
3. **Domain rules symmetric, including on allies (§10.4)?** My recommendation is yes, and do not build the exemption lever until playtest demands it.
4. **Second Sun friendly fire (§10.6) — hold the line?** My recommendation is yes, for at least two sessions.
5. **Which spec lands first, protection or this one (§10.9)?** Protection, since `GuardComponent` is already live and its three Kinds are specified.
6. **Cryomancer's signature (§7)** — accept `blizzard` as the reorder, or is a bespoke Cryomancer signature worth its own slot in a later cycle?
