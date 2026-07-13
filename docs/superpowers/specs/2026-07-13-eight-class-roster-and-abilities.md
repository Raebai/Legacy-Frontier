# The Eight-Class Roster + Full Ability Kits

Date: 2026-07-13 · Branch: `v2.0-tower` · Play: `VersusArena.tscn` (F6), `Main.tscn` (F5)

Driver: maker ask — "a full punching class with knockback + cool punching abilities (fire punch,
chidori equivalent...), a whole list of abilities for each class, ~8 classes, every ability unique
and cool with effects + animations." Autonomous "ultrathink, no questions" build.

## Design principle — 8 distinct fantasies over ONE slot system

Mobile-first means a FIXED, small input set. Every class uses the same 7 slots so touch controls
never change; what changes is the FLAVOUR of each slot (element, spectacle, params, weapon). This
is how you get 8 classes that *feel* unique without 8 bespoke control schemes:

| Slot | Key | Role |
|------|-----|------|
| Cast | LMB (hold) | primary ranged/短 attack |
| Melee | F | close strike (PUNCH/KICK/weapon), class element on hit |
| Dash | Space | mobility (some classes strike through) |
| AoE | Q | the signature *area* move — the class's identity beat |
| Blink | R | reposition |
| Nova | T | get-off-me / utility burst |
| Parry | RMB | timed defence |
| Ultimate | G (cycle V) | the legendary spectacle (MP-gated, SpellLibrary) |

Reused primitives: `Spell` bolt, `BlastSpell` (meteor/giant AoE, now element+group configurable),
`EnergyNova`, `BeamSpell`/`DivineRay`/`MeteorSigil`/`StarConvergence` (via `SpellCaster`),
dash-strike, blink, parry, melee. NEW primitives this build: **LightningRush** (Chidori — charge +
lightning dash through a line, chain-shock), **fist_shock** AoE (fire-punch shockwave), **ground_slam**
AoE (earth crater), and 3 new **Elements** (EARTH, HOLY, WIND) so each class owns an element identity.

## Elements — extended 5 → 8

| Element | Colour | Ailment (StatusComponent) |
|---------|--------|---------------------------|
| FIRE | orange-red | Burn (DoT) |
| ICE | cyan | Chill → Freeze (slow/root) |
| LIGHTNING | yellow | Shock (stun + 1 chain hop) |
| SHADOW | violet | Weaken (+dmg taken) |
| ARCANE | magenta | Unstable (delayed pop) |
| **EARTH** | amber-brown | Stagger (short root — reuses freeze mechanic, brown crust) |
| **HOLY** | gold-white | Radiance (radiant DoT — reuses burn mechanic, gold flame) |
| **WIND** | teal-white | Gale (brief stun — reuses shock mechanic, teal arcs) |

New ailments reuse proven mechanics with their own tint/name so gameplay stays tested + bounded, but
each class's hits READ distinct. (`StatusComponent.apply` maps EARTH→freeze-lite, HOLY→burn, WIND→shock.)

## The eight classes

### 0 · ARCANIST (Mage)  — element ARCANE — *ranged elemental zoner*  [existing MAGE, id 0 preserved]
Cast: homing arcane bolt · Melee: staff bonk · Dash · AoE(Q): **Meteor Blast** (giant telegraphed
BlastSpell) · Blink · Nova(T) · Ult(G): **Zoltraak** arcane beam. The baseline; byte-identical for
selected_class 0.

### 1 · SHADOWBLADE (Rogue) — element SHADOW — *in-and-out assassin*  [existing ROGUE, id 1 preserved]
Cast: fast thrown blade · Melee: sword · Dash: **dash-STRIKE** (cuts through) · AoE(Q): whirlwind
Nova · Blink (snappy) · Parry · Ult(G): **Umbral Lance** (shadow beam). Byte-identical for id 1.

### 2 · BRAWLER (Fist) — element FIRE (fists) / LIGHTNING (ult) — *pure melee, huge knockback*  ★ the ask
Cast: rapid jab (short fire-fist shove) · Melee: heavy fist combo, big knockback + Burn · Dash:
shoulder-CHARGE (dash-strike, heavy knock) · **AoE(Q): FIRE PUNCH** — lunge that erupts a fire
shockwave (`fist_shock`: fire nova + Burn + huge knockback) · Blink: step-in · Nova(T): ground-pound
· Parry: counter-stance · **Ult(G): CHIDORI / Thunderclap** — charge, then a lightning RUSH through a
line, chain-shocking everything (new LightningRush). The star class.

### 3 · JUGGERNAUT — element EARTH — *tank bruiser*
Cast: hurled rock · Melee: hammer, MASSIVE knockback + Stagger · Dash: shield-charge (dash-strike) ·
**AoE(Q): GROUND SLAM** (`ground_slam`: earth BlastSpell crater + SlamPhysics + big knockback) ·
Blink · Nova: quake · Parry: **BLOCK** (longest window) · Ult(G): **Colossus Pillar** (earth-tinted
DivineRay — a stone spire slams the marked spot).

### 4 · CLERIC (Templar) — element HOLY — *radiant bruiser*
Cast: holy bolt · Melee: mace + Radiance · Dash · AoE(Q): **Consecration** (holy BlastSpell) · Blink:
light-step · Nova: smite · Parry: aegis · Ult(G): **Heaven's Verdict** (StarConvergence) — with
**Judgment** (single divine pillar) as the cycle alt.

### 5 · CRYOMANCER — element ICE — *control caster*
Cast: frost shard (Chill→Freeze) · Melee: ice staff · AoE(Q): **Blizzard** (ice BlastSpell, Freeze) ·
Dash · Blink: frost-step · Nova: ice nova · Ult(G): **Frostpiercer** (ice beam).

### 6 · STORMCALLER — element LIGHTNING — *chain-lightning caster*
Cast: chain bolt (Shock + hop) · Melee: staff + Gale · AoE(Q): **Thunderstorm** (lightning BlastSpell)
· Dash: WIND-dash (faster/longer) · Blink: thunder-step · Nova: static burst · Ult(G): **Tempest**
(lightning beam).

### 7 · WARLOCK — element SHADOW/ARCANE — *dark hexer*
Cast: shadow bolt (Weaken) · Melee: scythe · AoE(Q): **Void Rupture** (arcane BlastSpell, Unstable) ·
Dash · Blink: shadow-step · Nova: void nova · Ult(G): **Void Barrage** (Meteor Sigil recoloured
shadow-purple).

## Data model changes

- `Elements`: 8 enum values + colours + names + count() = 8.
- `StatusComponent.apply`: EARTH→freeze-lite, HOLY→burn, WIND→shock (with element tint).
- `SpellDef.Kind`: add `RUSH`. `SpellCaster`: add RUSH arm → `LightningRush`.
- `SpellLibrary`: `build_for_class(id)` returns each class's themed loadout (its hero-fantasy ult
  first); `build()` stays as the full cycle (back-compat). Add Chidori (rush), Colossus Pillar (earth
  ray), Umbral Lance (shadow beam), Tempest (lightning beam), Void Barrage (shadow meteor),
  Consecration/Blizzard/Thunderstorm live as AoE variants not signatures.
- `Hero.CLASS_CONFIG`: 8 entries; new fields — `element` (default class element), `aoe` variant
  (`blast`|`nova`|`fist_shock`|`ground_slam`), `melee_element` (applied on melee hit), `signature_class`
  (loadout key). `configure_class` sets the class element + rig preset + kit.
- `CharacterRig.class_preset`: presets for all 8 (weapon + build). Reuse staff/sword/orb/fists overlays
  (bounded — no new weapon art this pass; brawler = bare fists, distinct tints per class).

## New spectacle — LightningRush (Chidori)

`LightningRush.gd` (Node2D): a charged lightning dash. On cast the hero surges `RUSH_DIST` along the
aim at high speed with i-frames; every enemy within the swept lane takes damage + Shock + a chain hop,
a jagged white-blue bolt trail draws along the path and fades, screenshake + zoom-punch + a thunder
crack. Headless-testable via a pure `swept_targets(from,to,enemies)` seam.

## Verification

Headless: extend the slice suites (new `slice5_test_classes` for the 8 kits + element mapping + rush
sweep; extend enemy side-on for leap + a mage test). Keep every existing suite green. Visual: the
`combat_capture` loop for the new spectacles. Then maker F6/F5 for feel — every ability needs the
maker's hands to tune (Gopeak can't render feel).
```

Play controls unchanged (mobile-first). Tab live-cycles all 8 classes; X cycles element; the class's
default element is auto-set on switch. HUD ability names reflect each class's kit.
