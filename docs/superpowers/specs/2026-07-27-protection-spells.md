# Protection Spells — design spec

**Date:** 2026-07-27 · **Branch:** `stickman-integrate` · **Status:** design only, READ-ONLY recon — no game code was modified producing this document.
**Maker ask:** *"look at like protection spells and stuff like that... also remember there is classes swordsmen assassin all that stuff so keep that in mind."*
**Governing rules:** `docs/references/magic-overhaul-plan.md` (five binding rules) · `docs/superpowers/specs/2026-07-27-mobile-casting-ux.md` (aim is a DIRECTION, forgiveness is bought with SHAPE) · `docs/superpowers/specs/2026-07-27-spell-interaction-layer.md` (curated reaction layer).

---

## 0. TL;DR

- **Thesis verdict: agree on the axis, reject it at two seats, and add a rule the thesis is missing.** Casters-get-wards / melee-get-counters is right in spirit. It is wrong for **Juggernaut** (a siege tank's fantasy *is* eating the hit — this is the one melee seat where a bubble is correct, and the one where a body-block protects allies) and wrong for **Cleric** (config says *bruiser*, not zoner — its protection is a spell cast on **someone else**, which is a different verb from a self-ward). The missing rule: **rule 2 has a mirror — if every attack must be dodgeable and telegraphed, every defence must be READABLE and BEATABLE.** An invisible absorb pool is the defensive equivalent of the homing we just spent a whole phase killing.
- **8 spells, one per class**, over **3 new `SpellDef.Kind` values** (`WARD`, `STANCE`, `DECOY`) and **4 new `CastStyle.Pose` values** (`GUARD`, `OFFER`, `PLANT`, `BRACE`).
- **Plumbing decision: `GuardComponent`, a structural twin of `StatusComponent`** — a lazily-created `Node2D` child of the guarded body that ticks its own timers, draws its own overlay in the owner's local space, and exposes `mitigate()` / `reflect_frac()` / `is_immune()` for the owner's `take_damage` to read. `StatusComponent` is the debuff half; this is the buff half. Because it is created by a duck-typed `apply_guard()` on any node with `take_damage`, it works on `Enemy` and `Boss` and any future bot with zero extra code.
- **Structural note in the brief is confirmed and is worse than stated:** there is no persistent-effect-on-caster concept for spells — *and* there are already **three hardcoded defensive knobs** living inline in `Hero.take_damage` (`_gear_damage_reduction`, `_gear_ward_frac`, `_gear_ward_used`, `Hero.gd:2064-2070`). Those are the same feature, built ad-hoc, hero-only, and non-expiring. The component must subsume them or the game will have two mitigation paths that silently disagree.
- **Honest correction to the brief:** protection spells will **not** "inherit reactions for free" by slotting into an existing Form. `Form.AURA` is an **orphan** — `TETHER` is its only member and **not one authored rule in `ReactionTable.rules()` mentions AURA**. And `ReactionTable` currently has **zero callers** — the reactor that consumes it does not exist yet. Four AURA rows are proposed in §5; they are inert until Phase 3 ships. `STANCE → Form.BARRIER` is the one that genuinely inherits (and inherits *well* — see §5.2).

---

## 1. Ground truth (verified by reading, with citations)

### 1.1 The defensive vocabulary that exists today

| Thing | Where | Shape |
|---|---|---|
| Dash i-frames | `Hero.gd:2042` | full-negate for `DASH_TIME` 0.14 s, `DASH_COOLDOWN` 0.9 s (class-tuned 0.55–0.90) |
| Blink i-frames | `Hero.gd:2045` | `BLINK_IFRAME` 0.22 s post-teleport |
| Parry | `Hero.gd:2049`, `_try_parry_start:1717`, `try_parry:1736` | `PARRY_WINDOW` 0.16 s, `PARRY_COOLDOWN` 0.9 s, **free (no MP)**, full-negates melee/contact/charge AND reflects a projectile |
| Juggernaut BLOCK | `_cfg["defense"] == "block"`, `_parry_window_len` `Hero.gd:266` | the same parry with a longer window (0.40 s) |
| Gear ward | `Hero.gd:305-307, 2064-2070` | `_gear_damage_reduction` (permanent %), `_gear_ward_frac` (one-shot % on the first hit of a fight), both inline in `take_damage` |
| Downed state | `Hero.gd:331, 2038` | co-op only; damage-immune while downed |

**That is the entire list.** Every one of the 24 spells in `SpellLibrary.build_all()` is offensive. `rock_wall` and `ice_wall` are *situationally* defensive but they are placed world geometry, not protection on a body.

### 1.2 The three facts that constrain everything below

1. **A spell spectacle is a one-shot world-coords node parented to the arena.** `SpellGeometry.gd:14-18` states the trap explicitly: *"spell spectacle nodes park at the arena origin and draw in world coordinates, so their global_position is (0,0) and is NOT where the effect is."* A protection effect must travel with a moving body, so it **cannot** be built like `ZoneSpell` / `BeamSpell`. It must be built like `StatusComponent` — a child of the body, drawing in local space (`StatusComponent.gd:216 _draw`).
2. **`take_damage` is already the authority seam in co-op.** `Hero.gd:2034` forwards a hit to the hero's owning peer; `Enemy.gd:1294` forwards to the host. Mitigation placed inside `take_damage` therefore resolves on the authority automatically and needs **no RPC for correctness** — only for the remote *visual*.
3. **Barriers block your own team today.** Hero is `collision_layer = 2, collision_mask = 1` (`scenes/combat/Hero.tscn:11-12`); `RockWall`/`IceWall` build a `StaticBody2D` on `collision_layer = 1` (`RockWall.gd:82`, `IceWall.gd:73`). A wall raised by your ally is solid to you. This is live, not hypothetical.

### 1.3 Friendly fire is currently INCONSISTENT — say so before designing on top of it

- The basic bolt friendly-fires in co-op: `Spell.gd:69` ORs hero layer 2 into the collision mask when `Net.is_active()`.
- **The 24 signatures do not.** Every spectacle resolves damage by iterating `get_tree().get_nodes_in_group("enemy")` (`BeamSpell`, `MeteorSigil`, `ZoneSpell`, `IceWall.shatter:161`, `ChainBolt`, `BladeFlurry`, …). A hero is in group `"hero"`, never `"enemy"`, so an ally standing inside your Meteor Sigil takes nothing.
- Walls block allies physically (§1.2.3).

So the current answer to *"is friendly fire on?"* is **"for the basic bolt and for physics, yes; for spells, no."** Ally-protection design must not assume more friendly fire than exists — and §7 flags where the inconsistency will bite.

---

## 2. Verdict on the design thesis

### 2.1 Where the thesis is right

**"An assassin's protection is NOT BEING THERE or PUNISHING THE SWING"** is the single best line in the brief and it should be promoted to a binding rule for this whole feature:

> **P1 — For a class whose fantasy is pressure, defence must produce tempo or damage. A pure mitigation button on a pressure class converts it into a patience class.**

This is verifiably how the codebase already thinks. The parry is not a shield — it *reflects* (`Hero.try_parry:1755` sends the bolt at the nearest enemy) and pays out a ding + hitstop + camera shake. The game's existing defensive verb is already a counter, not a bubble. Shadowblade and Brawler getting bubbles would fight both the class fantasy and the established feel.

### 2.2 Where the thesis is wrong — two seats

**Juggernaut.** The thesis puts Juggernaut in the "active counters" camp with Shadowblade and Brawler. That is a mis-grouping. `CLASS_CONFIG[JUGGERNAUT]` (`Hero.gd:181-188`) is *slow siege tank*: `melee_cd` 0.55 (slowest), `melee_arc_dot` 0.0 (widest swing), `melee_range` 96, `melee_knockback` 470, `"defense": "block"`, **no blink**. It is the only class in the roster that was *already* given a defensive identity in data. Its fantasy is not evasion or riposte — it is **occupying space and refusing to move**. A held, directional, rooted bulwark is exactly right for it, and in co-op it is the only class that can meaningfully **body-block for someone else**. Give Juggernaut the bubble; it is the seat where a bubble is a class fantasy rather than a stat.

**Cleric.** The thesis files Cleric under "casters get wards". But `CLASS_CONFIG[CLERIC]` (`Hero.gd:189-196`) is annotated *"radiant sustain bruiser"* — staff weapon, `melee_element` HOLY, lifesteal on the primary. Cleric is a front-liner. More importantly: a *self*-ward on the class whose entire identity is sustaining **other people** is the wrong verb. Cleric's protection spell must be **cast on an ally**, which is a genuinely different mechanic (a target, a link, a range at which it breaks) — and it must self-target when solo or it is dead content in singleplayer, which is 90% of play.

### 2.3 The rule the thesis is missing

> **P2 — Every defence must be READABLE by the attacker and BEATABLE by a specific counter.**

Rule 2 of the magic overhaul says everything must be dodgeable, with a real telegraph and a reaction window. Applied only to attacks, that ruleset makes the game asymmetric in the defender's favour: the attacker must telegraph, the defender may be invisible. An absorb pool with no visual state is the defensive equivalent of homing — an outcome the opponent cannot read and therefore cannot learn.

Concretely this means, for every entry in §4:
- The guard has a **body-legible visual whose STATE changes as it is consumed** (plates falling off a lattice, a crust cracking), not a flat coloured circle.
- The guard names **one thing that beats it**, and that thing is not "wait it out".
- No guard is strictly better than the free parry at equal cost (see §7.1).

### 2.4 Verdict, stated plainly

**Agree, with two reseatings and one added rule.** The correct axis is not caster-vs-melee but *at what range do you resolve a threat*:

| Band | Classes | Protection grammar |
|---|---|---|
| **Resolve at range** | Arcanist, Cryomancer, Warlock | WARD — a persistent mitigation worn on the body, elementally flavoured, elementally counterable |
| **Resolve for someone else** | Cleric, Juggernaut | LINK / BULWARK — the protection lands on, or covers, another body |
| **Resolve by not being there** | Shadowblade, Stormcaller | DECOY — a thing that is not you absorbs the attention |
| **Resolve by eating it** | Brawler | STANCE — take the hit, bank it, return it |

### 2.5 The "swordsmen" question — there is no swordsman, and that is a real gap

The maker said *"there is classes swordsmen assassin all that stuff."* Verified against `CLASS_NAMES` (`Hero.gd:151`) and `CLASS_CONFIG`:

- **Shadowblade** is a *knife assassin*, not a swordsman. `"weapon": "sword"` in data, but the kit is `blink_strike` / `blade_flurry` / `creeping_shade` / `rift_dagger` — teleport, burst, disengage. Element SHADOW. `dash_strike` on. It is Wizard-of-Legend rogue, not a duelist.
- **Juggernaut** is a *hammer tank* wearing the `"sword"` weapon string — `melee_arc_dot: 0.0` is a 180° sweep, `melee_cd: 0.55`, damage 30, range 96. That is a greatsword/hammer swing, not fencing.

Neither covers the **duelist**: mid-weight, no magic, footwork and timing, whose whole identity is the *riposte* — block precisely, punish precisely. **My recommendation: do not force this onto one of the eight.** Shadowblade would lose its twitchiness and Juggernaut would lose its immovability. Instead:

> Reserve the duelist as a **9th class candidate (working name: Bladedancer)** whose entire kit is built from the `STANCE` verb this spec introduces. The `STANCE` kind, the `PLANT`/`BRACE` poses, and the blocked-hit→riposte conversion in §4.6/§4.8 are deliberately authored as *general* mechanics so that class can be assembled from them later without new plumbing.

Flag for the maker: this is the one place where the answer is "a class is missing", not "a spell is missing". Worth an explicit yes/no before building §4.6 and §4.8, because those two spells define how much of the duelist's space gets pre-spent.

---

## 3. The plumbing — `GuardComponent`

### 3.1 What does not exist, stated plainly

There is **no** concept of a persistent effect attached to a caster in the spell system. `SpellCaster.cast()` (`SpellCaster.gd:40`) takes `caster_pos` (a `Vector2`, not a node) for every kind except `BLINK_STRIKE` and `THROWN_ANCHOR`, which take `caster` purely to call a duck-typed method once and then forget it. Every spectacle is parented to the *arena*, draws in world coordinates, and dies on a timer.

What *does* exist, and is the correct model, is `StatusComponent`:
- A `Node2D` child of the afflicted body (`Enemy.apply_status:1327` lazily creates it on first use).
- Ticks its own timers in `_process` and applies effects to `get_parent()` through duck-typed calls (`_deal_self:142`).
- Draws its overlay in the **owner's local space** (`_draw:216`), so it follows the body for free.
- Exposes pure query functions the owner reads during damage resolution: `slow_factor()`, `damage_mult()`, `is_hard_cc()`, `is_active()`.
- Headless-safe. No autoload dependency in the hot path.

`GuardComponent` is that, mirrored.

### 3.2 The contract

New file: `godot-project/scripts/combat/GuardComponent.gd`, `class_name GuardComponent extends Node2D`.

```
# --- granting (called by the WARD/STANCE spectacle, or by gear) ---
absorb(pool: int, duration: float, tint: Color, element: int) -> void
reduce(frac: float, duration: float, tint: Color, element: int) -> void
reflect(flat: int, frac: float, duration: float) -> void
immune(duration: float) -> void
cleanse() -> void                      # clears the sibling StatusComponent
cap_per_hit(cap: int, duration: float) -> void   # Brawler Iron Chin

# --- queried by the owner's take_damage, in this order ---
is_immune() -> bool
mitigate(amount: int) -> int           # per-hit cap -> reduce % -> drain absorb -> leftover
reflect_payload(amount: int) -> int    # what to send back to the attacker (flat-capped)
absorbed_last_hit() -> bool            # true if mitigate() ate the hit entirely
is_active() -> bool                    # owner frees the component when false
```

Ownership: **the guarded body owns the component**, exactly as with `StatusComponent`. Grant path:

```
Hero.apply_guard() / Enemy.apply_guard()   # lazily creates the child, returns it
```

`Enemy.apply_status` (`Enemy.gd:1327`) is the template — copy it verbatim, swap the class. That one method is why this works for enemies, bosses and bots for free: a future *shielded caster* enemy archetype needs zero new plumbing, and a bot running a class kit will get its class's ward as a side effect of casting it.

### 3.3 Where it hooks into `Hero.take_damage`

Current order (`Hero.gd:2029-2089`), and where the new line goes:

```
1.  net authority forward                       (unchanged)
2.  downed guard                                (unchanged)
3.  is_dashing            -> return             (unchanged)
4.  _blink_iframe_timer   -> return             (unchanged)
5.  _parry_window_timer   -> ding + return      (unchanged)
6.  NEW: guard.is_immune()-> return
7.  NEW: amount = guard.mitigate(amount)
8.  NEW: if amount > 0 and _channeling: _cancel_channel()
        if amount > 0 and _summoning:  _cancel_summon()
        (was unconditional at :2060-2063)
9.  NEW: var back := guard.reflect_payload(original); if back > 0 -> attacker.take_damage(back)
10. gear reduction / gear ward                  (MIGRATE into the component — §3.5)
11. ringout vs hp                               (unchanged)
12. damage number, flash, hitstop, sfx          (unchanged)
13. hp == 0 -> _die()                           (unchanged)
```

**Step 8 is a design decision, not a refactor.** Today *any* landed hit shatters a levitating channel or a summon windup. Making that conditional on `amount > 0` means **a fully-absorbed hit does not break your cast**. That is the entire reason a caster ward is worth a button: it buys you the 1.0–1.3 s levitating channel on Zoltraak / Heaven's Verdict that you otherwise cannot commit to with an enemy on you. Without this, a ward is a stat; with it, a ward is a *plan*. Recommend adopting it, and calling it out in the commit message because it changes the feel of every big spell.

Step 9 needs an attacker reference. `take_damage(amount: int)` on Hero has no attacker arg; `Enemy.take_damage(amount, tint)` has no attacker either. **Do not widen every call site.** Instead: `GuardComponent.reflect_payload()` returns the number, and the *reflect grant* stores a resolution strategy — `Targeting.nearest(global_position, get_tree().get_nodes_in_group("enemy"))`, the same helper `Hero.try_parry:1746` already uses to pick a reflect target. Reflect goes to the nearest enemy, not literally the attacker. That is a small fiction, it matches the parry's existing behaviour, and it avoids a signature change across ~30 call sites.

### 3.4 Interaction with `StatusComponent`

Both are children of the same body. Ordering: `StatusComponent.damage_mult()` (Weaken, +30%) is applied by `Enemy.take_damage:1300` *before* anything else. The equivalent for a hero does not exist yet (heroes have no weaken path). Rule: **amplification resolves before mitigation** — being weakened then warded should feel like a bigger hit partly eaten, not a smaller hit fully eaten. `cleanse()` reaches sideways to the sibling via `get_parent().get_node_or_null(...)`, guarded, so a body with no ailments cleanses harmlessly.

### 3.5 Migrating the two gear knobs (do this, but second)

`_gear_damage_reduction` and `_gear_ward_frac` (`Hero.gd:305-307`, applied `:2064-2070`) are the same feature built ad-hoc. Once `GuardComponent` exists they should be granted at `_recompute_gear_effects` (`Hero.gd:867`) as **permanent entries** (`duration = INF`), so there is exactly one mitigation path. Two cautions:
- `_gear_ward_used` is reset on every loadout/class change (`Hero.gd:883`). A permanent one-shot absorb entry must reproduce that reset or a class-cycle (Tab) will silently refresh a ward it should not.
- This touches gear behaviour that has capture-tool coverage (`tools/gear_capture.gd`, `tools/enemy_gear_capture.gd`). Read those before migrating. **Ship the component and the first ward first; migrate gear after the component is proven.**

### 3.6 Co-op

Correctness is free (§1.2.2 — mitigation runs inside the authority-forwarded `take_damage`). What is *not* free is the **remote visual**: a peer watching your warded hero must see the lattice, and see it chip. That is one synced float (`absorb_remaining / absorb_max`) on the `MultiplayerSynchronizer`, in the same shape `downed` already uses (`Hero.gd:331`, *"Public for the MultiplayerSynchronizer property path"*). Phase 2 work; singleplayer never touches it.

### 3.7 Headless testability

`GuardComponent` must be pure enough to test with no scene: timers, `mitigate()` arithmetic, expiry, replace-not-stack, cleanse against a stub `StatusComponent`. Model the runner on `tools/m11_test_patience.gd` — same `all PASS` idiom, same `--script` invocation. **Nine tests minimum**: absorb drains partially, absorb drains exactly, absorb overflows to hp, reduce rounds like the gear path (`int(round(...))`, `Hero.gd:2066`), reduce+absorb compose in the right order, per-hit cap clamps before reduce, expiry frees, a second grant replaces rather than stacks, reflect is flat-capped.

---

## 4. The eight spells

Every entry: **name · class · Kind · reaction Form · mechanic · cast pose · counterplay · model on.**
Costs assume the live baselines — hero `max_hp` 100, `max_mp` 100, `MP_REGEN` 20/s, signature MP costs 40–85, signature cooldowns 2.6–7.0 s.

### 4.1 Prismatic Lattice — Arcanist — `Kind.WARD` — Form.AURA

**Mechanic.** Absorb pool **45**, duration **6.0 s**, cooldown **14.0 s**, **35 MP**. Element ARCANE. The pool is drawn as **six geometric plates** orbiting the body; each 7.5 absorbed removes a plate, so the remaining pool is countable **from across the arena** — this is the reference implementation of rule P2. When the last plate goes, the lattice bursts (small 60 px knockback, 0 damage) so the moment of dropping is loud.

**Pose.** `GUARD` (new) — arms cross at the chest, then snap outward; the plates bloom off the forearms. 0.26 s.

**Counterplay.** 45 absorb is two enemy hits or one signature. It is elementally opposed by WIND (`ReactionTable.OPPOSED`), so a wind effect pops it outright (§5.1). It does not stop CC — a Stagger or Freeze lands through it at full duration. And 6 s up / 14 s down means 43% uptime: if you burn it early you fight the next 8 s naked.

**Model on.** `StatusComponent.gd` for the component-child structure and the local-space `_draw`; `StatusComponent._draw_unstable:286` for the "ring that reads its own progress" idiom.

### 4.2 Rimeguard — Cryomancer — `Kind.WARD` — Form.AURA

**Mechanic.** Damage **reduction 30%**, duration **5.0 s**, cooldown **12.0 s**, **30 MP**. Element ICE. Not a bubble — a **frost crust on the body** (reuse the `_draw_chill` / `_draw_freeze` visual language, `StatusComponent.gd:242,252`). Any body that lands a **melee** hit on you while the crust holds takes `apply_status(ICE)` — chill on the first, freeze on the second, per the existing chill→freeze escalation (`StatusComponent.apply:65-69`). Contact punish, once per attacker per 1.0 s.

**Pose.** `CIRCLE` (reuse) — a ritual sweep that draws the crust onto the body. Distinct from Prismatic Lattice's `GUARD` snap.

**Counterplay.** 30% is thin against a big hit and does nothing against ranged attackers who never touch you — it is a *melee* answer specifically. FIRE is its opposing element: a fire beam or fire impact strips it (§5.1). And it makes the wearer visually frost-crusted, which telegraphs to a Cryomancer's opponent that this is the window to back off rather than trade.

**Model on.** `StatusComponent._draw_chill` for the crust; `IceWall._chill_touching:186` for the proximity-scan-and-apply loop.

### 4.3 Aegis Link — Cleric — `Kind.WARD` (targeted) — Form.AURA

**Mechanic.** Grants the target absorb **30** + a full **`cleanse()`** of all active ailments, duration **5.0 s**, cooldown **15.0 s**, **40 MP**. Target selection is **one button, no aiming**: nearest *other* hero within 300 px; **if none, the Cleric itself**. A visible light tether runs caster→target for the duration and **breaks if the pair separate past 260 px** — the ward ends early. Protection as a *relationship*, not a bubble.

**Pose.** `OFFER` (new) — one arm extended flat toward the target, palm open, body turned to them. 0.30 s.

**Counterplay.** The link's range leash is the counter: split the party and the Cleric's protection evaporates. In singleplayer it self-targets, so it is never dead content, but at 30 absorb + cleanse for 40 MP it is deliberately the *worst* raw self-ward in the game — the cleanse is what you are paying for, and the ally case is where it is efficient.

**Model on.** `DrainTether.gd` for the caster→target tether visual and its per-frame endpoint tracking; `Hero.heal:1539` for the target-side feedback flash.

**⚠ In singleplayer the ally half of this spell is unreachable.** Flagged in §7.4 — if the maker's near-term playtest is solo, ship this fourth, not second.

### 4.4 Blood Pact — Warlock — `Kind.WARD` — Form.AURA

**Mechanic.** Duration **5.0 s**, cooldown **16.0 s**, **costs 12 HP, no MP** — the Warlock pays in the only currency that matters. While the pact holds: incoming damage is **halved**, and a **flat 14** is dealt back to the nearest enemy per hit taken (flat, not a percentage — see §7.3). Does not absorb, does not cleanse. A ring of siphoned shadow orbits the caster and visibly thickens with each hit returned.

**Pose.** `LASH` (reuse) — one arm whipped across the chest, opening the cut. Fast (0.18 s) because it costs blood, not time.

**Counterplay.** It is the only guard that can **kill you** — 12 HP up front, and a hit that halves to more than your remaining HP still kills. Against a single hard-hitting enemy the halving is great; against a swarm the flat-14 return is irrelevant and you have simply paid 12 HP. HOLY is its opposing element.

**Model on.** `DrainTether.gd:_tick` for the periodic damage-out; `StatusComponent._draw_weaken:277` for the dark-aura language.

### 4.5 Grounding Rod — Stormcaller — `Kind.DECOY` — Form.BARRIER

**Mechanic.** Plants a lightning rod at the caster's feet. Duration **4.0 s**, cooldown **13.0 s**, **32 MP**. Any node in group **`enemy_projectile`** within **200 px** is bent toward the rod and **consumed** on contact (`proj.call("consume")` — the exact idiom `IceWall.shatter:174-177` already uses). Every **3** consumed, the rod discharges a 120 px shock (18 damage + `apply_status(LIGHTNING)`). The rod is destructible: 3 melee/impact hits break it early.

**Pose.** `THROW` (reuse) — the rod is driven into the ground with an over-the-shoulder commit.

**Counterplay.** It only eats **projectiles** — a charger walks straight past it, and a placed spell (meteor, divine ray) ignores it entirely. It is stationary while Stormcaller is the most mobile class, so using it means giving up the thing you are good at for 4 s. It can be destroyed.

**⚠ Friendly-fire hazard, and the design rule that fixes it:** the rod must filter on **`enemy_projectile` only**, never group `player_spell` (`Spell.gd:66`). A rod that eats your ally's bolts is the single most infuriating thing in this document. Hard-code the group filter; do not make it configurable.

**Model on.** `RiftDagger.gd` — the closest existing precedent for a world-anchored, caster-owned, lifetimed node with a group and a static lookup; `IceWall.shatter:174` for the projectile-consume loop.

### 4.6 Bulwark — Juggernaut — `Kind.STANCE` — Form.BARRIER

**Mechanic.** A **held**, **rooted**, **directional** brace. Hold up to **2.5 s**, cooldown **9.0 s**, **25 MP**. Within a **140° front cone** facing the aim: **80% damage reduction**. Outside the cone: **0%**. While braced you **cannot move and cannot attack**. Any single blocked hit of **≥25 damage** triggers a **shove-shockwave** — 150 px, 20 damage, knockback 400 — so holding the line generates output.

**Co-op:** the cone reduction also applies to **any hero standing inside it**, which is the body-block fantasy and the strongest co-op moment in this spec.

**Pose.** `PLANT` (new) — feet set wide, hammer driven into the ground, weight forward, **held for the duration** (the only pose that is a sustained state rather than a windup).

**Counterplay.** The back is completely open — flank it. It roots you, so a placed spell (meteor, divine ray, `RockPillar`) lands on a target that has voluntarily given up its dodge. It costs you your offence for the duration. And as `Form.BARRIER` with the Juggernaut's EARTH element it inherits `ground_out` from the existing table — earth grounds lightning (§5.2), which is a real school-vs-school counter *in the Juggernaut's favour*, offset by `shatter_ice_barrier` and `carve` working against it.

**Model on.** `Hero._try_parry_start:1717` — the directional shell is already implemented as `rig.set_parry(dir, time)`; Bulwark is that shell held open. **Do not build a `StaticBody2D`** (see §7.5).

### 4.7 Nightfeint — Shadowblade — `Kind.DECOY` — Form.BARRIER

**Mechanic.** Instant. Cooldown **10.0 s**, **34 MP**. Leaves a shadow-clone of you standing exactly where you were, and **displaces you 120 px in the direction OPPOSITE your aim**. Every enemy within 400 px retargets the clone for **2.5 s**. The clone has 1 HP; when destroyed or on expiry it **pops for 25 damage in a 90 px radius** and applies Weaken.

The inversion is the whole design: **you aim where you want them to look, and you go the other way.** One button, one direction, no precision. Mobile-clean.

**Pose.** `COIL` (reuse) — `CastStyle.gd:42` already documents COIL as *"mobility + melee ultimates come from the body"*, 0.22 s, and lists `BLINK_STRIKE` under it. Nightfeint belongs in exactly that family.

**Counterplay.** It does not reduce a single point of damage. If a hit is already in flight it lands on you regardless. The displacement is short (120 px vs blink's 175 and Shadow Step's 300) so it repositions but does not escape. And an attentive opponent can read the clone — it does not move.

**Model on.** `Hero.blink_to()` (`Hero.gd`, invoked from `SpellCaster.gd:196`) for **pit-safe displacement — the displacement MUST go through this or Nightfeint will feint you into a pit**; `Enemy.gd:1491` for the hero-scan retarget loop; `CharacterRig` for drawing the clone from the caster's own rig state.

### 4.8 Iron Chin — Brawler — `Kind.STANCE` — Form.BARRIER

**Mechanic.** A **0.6 s** window. Cooldown **8.0 s**, **20 MP**. Damage taken during the window is **capped at 12 per hit** (hp still drops — this is not a shield). Each hit eaten grants **+30% melee damage**, stacking to **3**, expiring **2.0 s** after the window closes. Defence that is literally a damage buff.

**Pose.** `BRACE` (new) — fists up, chin tucked, weight stepped *into* the incoming hit. 0.22 s.

**Counterplay.** Your HP still goes down — spam it into a swarm and you die with three stacks. It does **not** stop CC: a Freeze, Stagger or Shock lands at full duration (`StatusComponent.is_hard_cc:114`), and a stunned Brawler cannot spend the stacks. It does not stop DoT ticks. And 0.6 s is short enough that using it means *predicting* the swing, not reacting to it — which is exactly the Brawler's skill expression.

**⚠ Ringout-mode trap:** in the Smash sandbox HP does not drain — `damage_pct` accrues instead (`Hero.gd:2075-2077`). A "cap the HP loss" mechanic silently does nothing there. Iron Chin **must** read `_is_ringout_mode()` and cap the `damage_pct` contribution instead. This is exactly the class of bug that ships unnoticed.

**Model on.** `Hero._try_parry_start:1717` for the timed-window state machine; the `_flaming_fist_timer` pattern (`Hero.gd:257`) for a temporary melee buff that decays.

### 4.9 Summary table

| Spell | Class | Kind | Form | MP | CD | Dur | Uptime | Pose |
|---|---|---|---|---|---|---|---|---|
| Prismatic Lattice | Arcanist | WARD | AURA | 35 | 14.0 | 6.0 | 43% | GUARD *(new)* |
| Rimeguard | Cryomancer | WARD | AURA | 30 | 12.0 | 5.0 | 42% | CIRCLE |
| Aegis Link | Cleric | WARD | AURA | 40 | 15.0 | 5.0 | 33% | OFFER *(new)* |
| Blood Pact | Warlock | WARD | AURA | 12 **HP** | 16.0 | 5.0 | 31% | LASH |
| Grounding Rod | Stormcaller | DECOY | BARRIER | 32 | 13.0 | 4.0 | 31% | THROW |
| Bulwark | Juggernaut | STANCE | BARRIER | 25 | 9.0 | ≤2.5 | ≤28% | PLANT *(new)* |
| Nightfeint | Shadowblade | DECOY | BARRIER | 34 | 10.0 | 2.5 *(clone)* | — | COIL |
| Iron Chin | Brawler | STANCE | BARRIER | 20 | 8.0 | 0.6 | 8% | BRACE *(new)* |

No two share a Kind+Form+Pose triple. No two resolve with the same math (absorb / reduce+contact-punish / absorb+cleanse+link / halve+reflect / projectile-eat / directional-reduce+shove / retarget+displace / per-hit-cap+buff).

---

## 5. Reactions — what actually gets inherited

### 5.1 `Form.AURA` is an orphan — the brief's assumption does not hold

`ReactionTable.form_for_kind` (`ReactionTable.gd:43`) maps only `TETHER → Form.AURA`. Reading all 13 rules in `ReactionTable.rules()`: **none of them mention `Form.AURA`.** A `WARD` mapped to AURA therefore inherits **nothing**. Worse, `ReactionTable` has **zero callers anywhere in the project** — the reactor that evaluates the table is Phase 3 and is not built.

So the honest statement is: *wards slot cleanly into the Form taxonomy, but the taxonomy has no AURA content yet, and no engine reading it yet.* Four rows are proposed to make AURA live — they are inert until the Phase 3 reactor ships, and they cost nothing to author now:

```gdscript
# A ward has an ELEMENTAL WEAKNESS. One row, all four opposing pairs.
_rule("shatter_ward", Form.BEAM, Form.AURA, {
    "require_opposed": true, "priority": 92, "consumes_b": true,
    "radius": 110.0, "damage": 20,
}),
# ...and the same for a physical/impact source, mirroring the ice-barrier pair.
_rule("shatter_ward", Form.IMPACT, Form.AURA, {
    "require_opposed": true, "priority": 86, "consumes_b": true,
    "radius": 110.0, "damage": 20,
}),
# The CONSTRUCTIVE case — same element FEEDS the ward. In co-op your ally's
# holy beam tops up the Cleric's holy ward. Mirrors `beam_resonance`.
_rule("overcharge_ward", Form.BEAM, Form.AURA, {
    "require_same": true, "priority": 58,
}),
# Standing in a hostile lingering field drains a ward faster than hits do.
_rule("field_ward_drain", Form.FIELD, Form.AURA, {
    "require_opposed": true, "priority": 46,
}),
```

`shatter_ward` is the load-bearing one: it is what makes P2 true at the system level rather than per-spell. Every ward gains a named elemental counter for free — Prismatic Lattice (ARCANE) dies to WIND, Rimeguard (ICE) to FIRE, Aegis Link (HOLY) to SHADOW, Blood Pact (SHADOW) to HOLY.

### 5.2 `Form.BARRIER` inherits well — recommend it for STANCE and DECOY

`STANCE` and `DECOY` should both map to `Form.BARRIER`. Unlike AURA, BARRIER already has five authored rules, and the inheritance is genuinely good:

| Existing rule | `ReactionTable.gd` | Effect on Bulwark (EARTH) / Rod (LIGHTNING) / Nightfeint clone (SHADOW) |
|---|---|---|
| `ground_out` (lightning beam vs earth barrier, consumes the beam) | `:145` | **Juggernaut's earth Bulwark hard-counters lightning beams.** Free, thematic, and a real school-vs-school answer. |
| `carve` (any beam vs earth barrier, +25 damage) | `:150` | Beams chew through the Bulwark rather than stopping — correct, it is 80% reduction not immunity. |
| `shatter_ice_barrier` | `:111,:116` | Does not fire (no ICE stance today) but a future frost stance would inherit it automatically — this is the taxonomy working. |
| `shrapnel_cone` (projectile vs ice barrier) | `:120` | Same — reserved. |
| `none` (barrier vs barrier, suppressed) | `:159` | A Bulwark planted next to an ally's Rock Wall is architecture, not an event. Correct and already decided. |

**Two `form_for_kind` arms** (`ReactionTable.gd:43`) do all of this:
```gdscript
SpellDef.Kind.WARD:                     return Form.AURA
SpellDef.Kind.STANCE, SpellDef.Kind.DECOY: return Form.BARRIER
```

### 5.3 Kinds and poses, appended (never inserted)

`SpellDef.Kind` is append-only by contract (`SpellDef.gd:13-15` — *"inserting would renumber BOULDER/PILLAR/WALL and break their arms"*). Append at the end:

```gdscript
enum Kind { ..., THROWN_ANCHOR, WARD, STANCE, DECOY }
```

`CastStyle.Pose` has no ordinal contract (matched by name in `for_spell`), but append anyway for consistency: `GUARD, OFFER, PLANT, BRACE`. Add durations to `CastStyle.duration()` — `GUARD` 0.26, `OFFER` 0.30, `BRACE` 0.22, and `PLANT` **held** (returns the stance's own duration, the first pose that is a state rather than a windup — call that out, it is a small break in the pose contract).

Each new Kind needs exactly one `match` arm in `SpellCaster.cast()` (`SpellCaster.gd:52`). **All three arms need the `caster: Node` argument**, which already exists on the signature (`SpellCaster.gd:42`) and is already used by `BLINK_STRIKE` and `THROWN_ANCHOR`. Protection makes `caster` load-bearing for the first time rather than optional — worth noting in the arm's comment, since a caller that forgets to pass it gets a silent no-op.

---

## 6. Mobile-first check

Every one of the eight is **one button, no aim precision**:

| Spell | Input | Aim used for |
|---|---|---|
| Prismatic Lattice / Rimeguard / Blood Pact | tap | nothing — self-centred |
| Aegis Link | tap | nothing — nearest ally, else self |
| Grounding Rod | tap | nothing — plants at your feet |
| Bulwark | **hold** | facing only (a direction, never a target) |
| Nightfeint | tap | a *direction* to feint toward (inverted); any direction is valid |
| Iron Chin | tap | nothing |

This satisfies the mobile-casting spec's rule — *"aim is a DIRECTION, never a TARGET; forgiveness is bought with SHAPE."* The two aim-reading spells read a direction and use it to size a **cone** (Bulwark, 140°) or pick a **hemisphere** (Nightfeint). Nothing reads an entity's position to change a spell's direction.

**Aegis Link's nearest-ally selection is target-reading, and that is a deliberate, narrow exception.** It selects *whom to help*, never *where to shoot*. The rule exists so that offence cannot be auto-corrected; extending it to friendly targeting would make every co-op support spell need pixel-aiming on a phone, which is the opposite of the rule's purpose. Worth an explicit maker yes.

**Bulwark is the only HELD input in the kit.** `TouchControls` (`scripts/combat/TouchControls.gd`) already presses/releases named actions (`Input.action_press` / `action_release`), so hold works on touch with no new plumbing — but `TouchControls` currently has **no melee and no parry button** (defect #2 in the mobile-casting spec, `§1.2`). Bulwark on a phone therefore depends on that defect being fixed. Dependency, not a blocker.

**Button-budget dependency.** `AbilityBar.ability_hud_state()` (`Hero.gd:1774`) has **7 slots and they are all full**. There is no free key. Protection spells must live in the **signature cycle** (V / `_signatures`), which means **a protection spell competes with your ultimate for the same button**. That is not a compromise — it is the best balance lever in this document: you choose *protection or the big damage*, and you cannot have both. Recommend shipping it that way deliberately, and letting the 4-slot typed loadout from the mobile-casting spec be the eventual home.

---

## 7. What would be unbalanced or un-fun — called out honestly

### 7.1 Stacking is the number-one risk

Dash i-frames (0.14 s, full negate) + parry (0.16 s, full negate, **free**) + a 45-point absorb + 30% reduction = un-hittable. Three hard rules:

1. **One absorb entry and one reduce entry at a time.** A new grant **replaces**, never stacks. (`StatusComponent.apply` already sets rather than adds — same idiom.)
2. **A guard cannot be granted while `is_dashing` or while `_parry_window_timer > 0`.** You cannot layer a ward under an i-frame.
3. **`cooldown ≥ 2× duration` and uptime ≤ 45%** for every entry. The §4.9 table is built to this; check it on every future addition.

### 7.2 Nothing may be strictly better than the free parry

The parry costs **0 MP**, has a **0.9 s** cooldown, **fully negates**, and **reflects**. That is a very strong baseline. If any ward beats it on value at equal cost, the parry becomes dead content and the game loses its best skill-expression moment. Every entry in §4 is deliberately **partial** (absorb caps, 30–80% reduction, per-hit caps) and **MP-priced**. Watch this specifically in playtest: the failure signal is *"I stopped parrying"*.

### 7.3 Reflect scales catastrophically against big hits

Boss and signature damage reaches 130 (`heavens_verdict`). A percentage-based reflect on a 130 hit returns 65 — larger than most spells. **Blood Pact's return is a flat 14, deliberately.** Never express reflect as a percentage of the incoming hit. This is the single most likely balance blow-up in the document.

### 7.4 Ally protection is dead content in singleplayer

Aegis Link's ally half and Bulwark's cover-your-team half are both unreachable solo, and solo is the overwhelming majority of current play (co-op exists but *"remaining gap = replicate enemy ATTACK visuals + real 2-machine feel"* per the co-op memory). Mitigations: Aegis Link self-targets when alone (built in), and Bulwark's shove-shockwave gives it solo value. But **do not sequence these first** — build them after the solo-legible wards.

### 7.5 A barrier that blocks your own team is already infuriating, and this spec must not add to it

`RockWall`/`IceWall` build `StaticBody2D` on layer 1 and heroes mask layer 1 — an ally's wall is solid to you *today* (§1.2.3). **Therefore: `STANCE` and `DECOY` must NOT create collision bodies.** Bulwark's mitigation is a query inside `take_damage`, and its visual is `rig.set_parry`'s directional shell. A Juggernaut planting a physical Bulwark in a doorway and sealing his own team in is a guaranteed rage moment. Nightfeint's clone likewise: visual + retarget only, no body.

Separately worth raising with the maker: **the existing walls should probably stop colliding with group `"hero"` in co-op.** Out of scope here, but this feature makes it visible.

### 7.6 Everything else that will bite

- **Iron Chin in ringout mode does nothing** unless it reads `_is_ringout_mode()` (§4.8). Silent no-op class of bug.
- **Grounding Rod eating ally projectiles** — hard-filter on `enemy_projectile` (§4.5). Never configurable.
- **Warlock reflect hitting an ally** in co-op — `Targeting.nearest(..., get_nodes_in_group("enemy"))` already excludes heroes; keep it that way and do not "improve" it into a generic nearest-body search.
- **Nightfeint feinting you into a pit** — route displacement through `Hero.blink_to()`, which already refuses pit landings (`SpellCaster.gd:186-191`).
- **A ward that survives death/respawn.** `Hero._die` (`:2092`) resets hp or enters downed; `_enter_downed` makes you damage-immune. The component must be cleared on both paths or a downed hero revives pre-warded.
- **The invisible-guard failure.** If the visual does not read at 46 px on a phone, the whole guard layer is a stat block. Verify with `tools/spell_playground_capture.gd` **at mobile scale**, not just desktop — and look at the image, per the overhaul's screenshot-verify protocol.
- **`GuardComponent` is a per-frame `_draw` on the hero.** `StatusComponent` proved the cost is fine for one overlay; adding a second always-on child on every hero *and* enemy in a dense floor is worth one profiling pass before shipping §4.5 onward.

---

## 8. Build order

**Must build first (this is the whole feature; everything after is content):**

1. **`GuardComponent.gd` + `tools/guard_test.gd`.** No spells. Prove absorb/reduce/reflect/per-hit-cap math, expiry, replace-not-stack, cleanse against a `StatusComponent` sibling, and correct behaviour on an `Enemy` stub. `all PASS` before anything else moves. *(model: `StatusComponent.gd`, `tools/m11_test_patience.gd`)*
2. **Wire `Hero.take_damage`** per §3.3 — including the `amount > 0` guard on channel/summon interrupt (§3.3 step 8), which is a **feel change to every big spell** and must be called out in the commit. Add `Hero.apply_guard()` / `Enemy.apply_guard()`. Do **not** migrate gear yet.
3. **`Kind.WARD` + `Pose.GUARD` + one spell: Prismatic Lattice.** One `SpellCaster` arm, one `CastStyle` arm, one `WardAura.gd` drawn as a child of the caster in local space. **Maker F5s this alone.** One ward proves the whole layer; if the plate-count read does not land at mobile scale, everything downstream is wrong and it is cheap to find out here.

**Then (content, in risk order):**

4. **Rimeguard** (Cryomancer) — second WARD, proves the reduce path + contact punish. Solo-legible.
5. **`Kind.STANCE` + `Pose.PLANT`/`BRACE` → Bulwark + Iron Chin.** The melee half of the thesis. Iron Chin needs the ringout-mode branch (§4.8).
6. **`Kind.DECOY` + Nightfeint + Grounding Rod.** New verb, most new code, highest visual-authoring cost.
7. **`ReactionTable` AURA rows + the two `form_for_kind` arms** (§5). Authored now, inert until the Phase 3 reactor exists — so this can land any time after step 3 and costs nothing.
8. **Aegis Link** (Cleric) — sequenced late because its ally half is unreachable solo (§7.4).
9. **Blood Pact** (Warlock) — last. Reflect is the most balance-dangerous mechanic here (§7.3) and benefits from having the other seven tuned first.
10. **Migrate the two gear knobs onto `GuardComponent`** (§3.5) once it is proven. Read `tools/gear_capture.gd` and `tools/enemy_gear_capture.gd` first.

**Nice-to-have / not now:** co-op synced ward visuals (§3.6); the Bladedancer duelist class the `STANCE` verb is being built to support (§2.5); making existing walls non-colliding with heroes (§7.5).

---

## 9. Open questions for the maker

1. **The missing swordsman (§2.5)** — reserve the duelist as a 9th class built from `STANCE`, or fold the riposte fantasy into Shadowblade/Juggernaut now? This changes how much of §4.6/§4.8 gets spent.
2. **Absorbed hits not breaking a channel (§3.3 step 8)** — this makes wards a *plan* rather than a stat, but it changes the feel of every levitating ult. Yes or no?
3. **Aegis Link's nearest-ally auto-select (§6)** — a narrow, deliberate exception to "never read an entity's position". Acceptable for *friendly* targeting?
4. **Protection lives in the signature cycle (V), competing with your ultimate (§6)** — deliberate constraint, or wait for the 4-slot typed loadout?
5. **Should existing Rock/Ice Walls stop colliding with heroes in co-op (§7.5)?** Out of scope, but this feature makes it visible.
