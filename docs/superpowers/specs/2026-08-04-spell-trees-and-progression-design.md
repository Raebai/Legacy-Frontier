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

## 5. Levelling — ONE currency, and stats that are class character

Maker, correcting an earlier draft of this section: *"by stat points I mean points
that can be spent in the spell tree and levelling should just improve your stats
by certain amounts based on the class… different classes different themes
different stat improvements but its the same number just in different things"*.

That is a better model than the two-budget version this replaces, for a reason
worth stating: **a player asked to allocate stats will look up the correct answer**
and then it is not a choice, it is homework. Stats become class CHARACTER —
automatic, themed, not managed — and the only thing you actually spend is
attention on the tree.

| a level gives | |
|---|---|
| **1 Skill Point** | the ONLY currency. Spent in the spell tree. Nothing else. |
| **10 Growth** | automatic, distributed by your CLASS. Never chosen. |

### 5.1 Every class gains exactly 10 Growth per level

Same number, different things — the maker's rule, and it is what keeps nine
classes on one power curve while still feeling nothing like each other. A class
cannot out-level another; it can only become more itself.

| axis | what it moves | per point |
|---|---|---|
| **VITALITY** | max HP | +0.60% |
| **POWER** | spell + melee damage | +0.40% |
| **FOCUS** | cooldown recovery | +0.35% |
| **SWIFTNESS** | move speed | +0.30% |
| **WARD** | damage reduction | +0.25% |

⚠ The per-point values are NOT equal on purpose — a point of speed is worth far
more in a game about dodging than a point of HP, so they are priced against each
other rather than printed the same. **Every number in this table is a first pass
and untuned.**

### 5.2 The nine spreads

Each row sums to **10**. That is the invariant, and the one a test should pin.

| class | VIT | POW | FOC | SWI | WARD | reads as |
|---|---|---|---|---|---|---|
| Arcanist | 1 | 4 | 3 | 2 | 0 | glass zoner — hits hard, recovers fast, dies fast |
| Shadowblade | 1 | 3 | 2 | 4 | 0 | fastest thing in the tower, made of paper |
| Brawler | 3 | 4 | 1 | 2 | 0 | walks in and hits you |
| Juggernaut | 4 | 2 | 1 | 0 | 3 | immovable; never gets quicker |
| Cleric | 3 | 2 | 2 | 1 | 2 | the one that is hard to kill from any angle |
| Cryomancer | 2 | 2 | 4 | 1 | 1 | uptime — the field is always up |
| Stormcaller | 2 | 3 | 2 | 3 | 0 | mobile combo caster |
| Warlock | 2 | 3 | 3 | 1 | 1 | attrition; the thralls do the running |
| Swordsaint | 2 | 3 | 2 | 2 | 1 | even, because the parry is the stat |

⚠ **STORMCALLER IS DELIBERATELY NOT GIVEN FOCUS 4.** It wins 16-0 in the honest
sim because it is the only class built end-to-end around ICE-field → LIGHTNING,
and `BotBrain.COMBO_SETUPS` rates its setup top payoff. Cooldown growth is
precisely the axis that would compound that. It gets mobility instead. The
obvious "combo class → more FOCUS" read is the wrong one here, and the reason is
measured rather than felt.

### 5.3 Where it lands over a climb

At roughly a level per floor plus one per guardian — **~12 levels for the current
10-floor tower** — a class's primary axis (5/level) receives 60 points. On
VITALITY that is **+36% HP**; on SWIFTNESS, 4/level = 48 points = **+14% speed**.

That is meant to be felt and not to be a gate. ⚠ **The trap it must not become:**
if levels are the thing that gets you up the tower, floor 1 turns into a farm and
floor 20 into a stat check you grind for rather than climb to. If playtest shows
the climb being solved by levelling rather than by playing, cut the per-point
values — do NOT cut the Growth budget, because 10-per-level is what keeps the
nine classes comparable.

XP comes from **floors cleared and guardians felled, never from kills** —
otherwise the optimal play is farming trash on floor 1, which is the exact
opposite of a climb.

### 5.4 It needs no new save

`user://climber.json` and `Rank.power` already survive a quit. Level, unspent
skill points and unlocked node ids live there. Growth is not stored at all —
it is **derived** from `level × the class row`, so it can never disagree with the
table, and re-reading the table after a retune updates every existing save for
free. Same principle as `LEG_LEN_FACTOR` and `HIP_Y_FACTOR` in the rig: derived,
not authored, so two sources cannot drift apart.

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
2. **Levelling in `climber.json`**: level, unspent skill points, unlocked node
   ids. Growth is DERIVED from `level × CLASS_GROWTH[class]`, never stored. Pure
   math, testable, and the row-sums-to-10 invariant is one assertion.
3. **The Archivist screen** — the tree UI at the lectern. The biggest piece.
4. **Class unlocking** + the floor-5 guardian choice.
5. **NPC jobs** — barks and the four teaching screens.

Steps 1–2 are pure and can land with tests before any pixel is drawn, which is
the right way round for a system this size.

## 9. Open questions for the maker

- **Respec of SKILL POINTS:** free at the campfire (my recommendation), or paid?
  (Stats need no respec — they are derived from class + level and never chosen.)
- **Do linked nodes need their element unlocked**, or is the link enough?
- **Cryomancer / Stormcaller / Warlock / Swordsaint ults** are marked
  `[class native]` above — I did not invent names. Their real kit ults should be
  read off `CLASS_KITS` when this is built.
- **Does levelling reset per climb?** My assumption: no. It is the one thing that
  is yours regardless of how the run went.
- **Are the 10 Growth per level right, or should it scale with band?** Flat is my
  recommendation — a flat budget is what makes "level 8 Cleric" mean one thing.
