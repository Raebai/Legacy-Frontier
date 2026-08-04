# Spell trees, levelling and the Antechamber as a place

**Date:** 2026-08-04 · **Branch:** `bot-fight-quality` · **Status:** PROPOSAL — not built

Answers the maker's brief: a Wizard-of-Legend-ish hub with NPCs you learn from,
levelling with stat points, and a **spell tree per class** with cross-class links
"based on semi relevant links / strategies", so you choose your binds.

---

## 0. The catalog, counted

**49 spells** — `SpellLibrary` has 49 `static func _x() -> SpellDef` builders.
(A plain grep for `s.id = "…"` finds only 37; the eight BEAMS are built through a
shared `_beam()` helper and set their id there. Count the builders, not the ids.)

**9 classes** — Arcanist, Shadowblade, Brawler, Juggernaut, Cleric, Cryomancer,
Stormcaller, Warlock, Swordsaint.

**5 roles per class** — `ROLE_ORDER = [damage, control, answer, payoff, ult]`.
You already carry **three of your five** (`GameState.spell_roles`, chosen at the
lectern). 9 × 5 = 45 authored role slots over 49 spells.

⚠ **THE CROSS-CLASS LINKS ALREADY EXIST IN THE DATA.** This is the single most
important finding for the maker's ask. `CLASS_KITS` already shares spells between
classes — `rock_pillar` is the Arcanist's payoff AND the Juggernaut's payoff;
`drain_tether` is the Juggernaut's answer, the Cleric's answer AND the Warlock's
damage line; `chain_lightning` is the Brawler's control AND the Cleric's payoff;
`blink_strike` is the Arcanist's answer AND the Shadowblade's payoff.

So a tree does not need a new "borrowing" system invented on top. **It makes a
sharing that is already true visible, and puts a price on it.**

---

## 1. The shape: a tree per ROLE, not one tree per class

Five branches, one per role. A branch holds 2–3 spells that can fill that role.
Unlocking a node makes it **bindable**; you still carry only three roles, so the
tree grows your OPTIONS and never your loadout size.

```
          ┌── damage ──┬── [class native] ── [deeper native]
          │            └── «linked» (another class's, same element)
 CLASS ───┼── control ─┬── [class native]
          │            └── «linked»
          ├── answer ──┬── [class native]
          │            └── «linked»
          ├── payoff ──┬── [class native]
          │            └── «linked»
          └── ult ─────── [class native]         ← never linked. See §3.
```

**Why per-role and not a free web:** the 3-of-5 hand is the existing balance
surface and the thing `slot_accepts_ult` protects. A free web would let a player
carry five damage spells and no answer, which is not a build, it is a hole.

---

## 2. The link grammar — what "semi-relevant" means, made a rule

A class may reach a spell from another class's branch when they share **either**:

- **an ELEMENT** the class already casts (arcane / ice / lightning / holy /
  shadow / fire / earth), **or**
- **a ROLE ARCHETYPE** — the same job done a different way (a wall is a wall).

That is the whole rule, and it is checkable in data rather than curated by hand,
so a spell added later inherits its links automatically.

**Cost:** a native node costs **1 point**, a linked node **2**. A linked node is
a strategy you went and got; it should be felt.

---

## 3. Ults are never linked

The one hard exception. `heavens_wrath`, `thousand_cuts`, `fault_line`,
`meteor_fist` are the class fantasies — the [[project_v2_class_identity_mandate]]
ruling is "every class needs a unique signature spell", and a tradable ult is a
recolour with extra steps. **Your ult is why you picked the class.**

---

## 4. Mock trees — all nine

Native = the class's authored kit spell. «linked» = reachable, 2 points.
Every spell named below is real and in the catalog today.

### Arcanist — arcane zoner
```
damage   ordinary_spell → «frostpiercer» (beam kin)
control  mirror_image   → «chronostasis» (arcane control)
answer   blink_strike   → «rift_dagger» (Shadowblade — get-out kin)
payoff   rock_pillar    → «rune_orbs» (arcane payoff)
ult      meteor_sigil
```

### Shadowblade — in-and-out assassin
```
damage   blade_flurry   → «iai_slash» (Swordsaint — burst kin)
control  creeping_shade → «void_zone» (shadow control)
answer   rift_dagger    → «blink_strike» (Arcanist — mobility kin)
payoff   blink_strike   → «crescent_step» (Swordsaint — reposition kin)
ult      thousand_cuts
```

### Brawler — pure melee
```
damage   shockwave_stomp → «boulder_hurl» (Juggernaut — earth kin)
control  chain_lightning → «thunderclap» (lightning kin)
answer   rock_wall       → «ice_wall» (Cryomancer — wall archetype)
payoff   boulder_hurl    → «rock_pillar» (earth kin)
ult      meteor_fist
```

### Juggernaut — siege tank
```
damage   boulder_hurl   → «shockwave_stomp» (Brawler — earth kin)
control  rock_wall      → «petrify» (earth control)
answer   drain_tether   → «aegis_ward» (Cleric — survival archetype)
payoff   rock_pillar    → «shatter» (Cryomancer — detonator archetype)
ult      fault_line
```

### Cleric — radiant lifesteal bruiser
```
damage   radiant_volley → «judgment» (holy beam kin)
control  aegis_ward     → «equinox» (holy control)
answer   drain_tether   → «blink_strike» (mobility archetype)
payoff   chain_lightning→ «heavens_wrath» (holy payoff)
ult      heavens_verdict
```

### Cryomancer — ice control
```
damage   shatter        → «frozen_comet» (ice kin)
control  blizzard       → «ice_wall» (ice control)
answer   ice_wall       → «rock_wall» (Brawler/Jugg — wall archetype)
payoff   frozen_comet   → «rock_pillar» (detonator archetype)
ult      [class native]
```

### Stormcaller — lightning combo
```
damage   chain_lightning→ «thunderclap» (lightning kin)
control  blizzard       → «creeping_shade» (field archetype)
answer   thunderclap    → «blink_strike» (mobility archetype)
payoff   [class native] → «rune_orbs» (payoff archetype)
ult      [class native]
```
⚠ Stormcaller wins **16-0** in the honest sim because it is the only class built
end-to-end around ICE-field → LIGHTNING. **Do not give it cheap links.** Its
links should be the most expensive in the tree, or the class stays a late unlock
(§6) and the tree does not widen it at all.

### Warlock — thrall hexer
```
damage   drain_tether   → «void_zone» (shadow kin)
control  raise_thrall   → «creeping_shade» (shadow control)
answer   blood_pact     → «the_void» (shadow answer)
payoff   grave_tide     → «arc_of_fools» (chaos payoff)
ult      [class native]
```

### Swordsaint — parry duellist
```
damage   iai_slash      → «blade_flurry» (Shadowblade — burst kin)
control  horizon_cut    → «gravity_flip» (displacement archetype)
answer   crescent_step  → «rift_dagger» (get-out kin)
payoff   thousand_cuts  → «shockwave_stomp» (finisher archetype)
ult      [class native]
```

---

## 5. Levelling — points buy OPTIONS, stats only season

⚠ **THE TRAP TO AVOID, STATED PLAINLY.** If levels give meaningful stats, floor 1
becomes boring and floor 20 becomes a stat check you grind for rather than climb
to. The Tower must stay a test of play. So:

| earn | on | spend on |
|---|---|---|
| **1 skill point** | every level | spell-tree nodes |
| **1 stat point** | every **3rd** level | HP / Focus (cooldown) / Swiftness |

**Stats are capped at +25% total across the whole climb** and are freely
respec-able at the campfire. They are seasoning, not a gate. The BIG axis is
which spells you can bind; the small axis is how they feel.

XP comes from **floors cleared and guardians felled**, not from kills — otherwise
the optimal play is farming trash on floor 1, which is the opposite of a climb.

**This slots into what already persists:** `Rank.power` and `user://climber.json`
already survive a quit, so level/points/allocations live there with no new save.

---

## 6. Class unlocking

Start with **6**: Arcanist, Brawler, Cleric, Cryomancer, Shadowblade, Juggernaut.

Locked: **Stormcaller, Warlock, Swordsaint** — the three that are hardest to play
well (combo-dependent, thrall management, parry timing). This is not arbitrary:
it also defuses the known balance problem, since Stormcaller's 16-0 is a late
reward rather than a beginner trap.

⚠ **THE FLOOR-5 GUARDIAN GRANTS A CHOICE, NOT A DROP.** The maker floated "the
5th floor boss is a one time one of the 3 remaining classes". A random one means
the class you get is a coin flip and you farm a boss for it. Beating the guardian
should let you **pick** one of the three. Deterministic, still a milestone, and
the pick becomes a memory. The remaining two come from the floor-10 guardian and
a full tower clear.

---

## 7. The Antechamber as a place (the Wizard of Legend ask)

The room already has: class statue, armoury rack, spell lectern, sparring ring,
campfire, party stone, tower door, three townsfolk with `Bark` + `Gibberish`
voices. What it lacks is people who TEACH you something.

Give the existing townsfolk jobs, so "interact to learn more" has somewhere to go:

| who | where | teaches |
|---|---|---|
| **The Archivist** | lectern | opens the SPELL TREE; explains what a spell actually does |
| **The Quartermaster** | rack | gear, and what each slot trades away |
| **The Warden** | sparring ring | mechanics — parry timing, dodge i-frames, the cast gap |
| **The Doorkeeper** | tower door | your climb: floor, falls, best, what the next band is |
| **campfire folk** | campfire | the world, the regions, the guardians — lore, no buttons |

Each is a **Bark line on proximity plus one screen**, which is exactly the
"station IS the screen" rule the room already follows. No new dialogue system,
and emphatically no LLM — that stack is deleted and stays deleted.

---

## 8. Build order, if this is taken up

1. **Data first**: a `SpellTree` resource — per class, per role, native + linked
   node lists with costs. Pure data, headless-testable, no UI.
2. **Levelling in `climber.json`**: level, unspent points, unlocked node ids,
   stat allocation. Pure math, testable.
3. **The Archivist screen** — the tree UI at the lectern. The biggest piece.
4. **Class unlocking** + the floor-5 guardian choice.
5. **NPC jobs** — barks and the four teaching screens.

Steps 1–2 are pure and can land with tests before any pixel is drawn, which is
the right way round for a system this size.

## 9. Open questions for the maker

- **Respec:** free at the campfire (my recommendation), or paid?
- **Do linked nodes need their element unlocked**, or is the link enough?
- **Cryomancer / Stormcaller / Warlock / Swordsaint ults** are marked
  `[class native]` above — I did not invent names. Their real kit ults should be
  read off `CLASS_KITS` when this is built.
- **Does levelling reset per climb?** My assumption: no. It is the one thing that
  is yours regardless of how the run went.
