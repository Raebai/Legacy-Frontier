# Legacy Frontier — EPIC north-star + resume plan (2026-07-14)

> Written at the maker's request as the resume point after a big playtest-feedback storm.
> The **tactical, itemised** TODO also lives at the top of `.superpowers/sdd/progress.md`
> (block "LATER-4 — PLAYTEST FEEDBACK STORM"). This doc is the STRATEGY / why.
> Playtest scene: `scenes/combat/VersusArena.tscn` (F6). Branch `v2.0-tower`, NOT pushed.

## The vibe we're chasing
Fast-paced, anime-epic, **spells flying everywhere**, the map getting **torn apart**, big
screen-filling ultimates with real ceremony — a "can't put it down" game. Right now the
PIECES exist (8 bespoke class kits, spectacles, destruction, ring-out, per-ability SFX)
but they fire FLATLY and don't COMPOSE into epic. "Epic" is not a feature — it's many
systems (sound + VFX + camera + time + destruction) firing IN SYNC on key beats:
**anticipation → crescendo → payoff → aftermath.**

## Progress (2026-07-15)
**Phase 1 ✅ DONE**, **Phase 1b ✅ DONE**, **Phase 2 ✅ DONE**, **Mobile touch ✅ first-pass DONE** —
shipped + pushed to `origin/v2.0-tower` (see `.superpowers/sdd/progress.md` top block for the
commit map). All headless + GPU-verified, UNPLAYTESTED for feel (needs maker F6). Remaining:
Phase 3 (enemy kits/density + bigger natural destruction + de-corny beam SFX) and Phase 4
(DMC style meter + real SFX packs), plus mobile on-device feel tuning.

## Strategy — 4 phases, in order

### Phase 1 — FIX THE FOUNDATION (can't be epic if it's janky) — ✅ DONE
- **Map is scattered + the PLATFORMS LOOK WEIRD/WRONG** (maker: "what's up with all these weird
  platforms, the map needs to look way better, more REALISTIC and actually FUN"): the floating
  ledges (300,560)/(720,470) + breakable (980,380) sit at random heights with big empty gaps to
  the right-third mountain → reads as disconnected abstract blocks, not a place. FULL VISUAL
  REDESIGN: one cohesive, connected, REALISTIC-looking, FUN stage — believable terrain/rock/
  ruins art (not flat dark slabs with green rims), platforms that feel intentional + reachable +
  connected to the ground + mountain, no empty vertical void, clear traversal + fight flow.
  Consider the KayKit / Stylized Nature / VFX assets the maker downloaded for a real look.
  See `tools/arena_wide_capture.gd`.
- **Ducking clips the hero INTO the floor** (hold DOWN ragdoll): the limp rig droops below its
  collision. Clamp the limp droop to the floor / reduce limp gravity when grounded.
- **VOID/ring-out "sends me out of the map"**: blast-zone PITs (or a floor hole opening under
  the hero) ring the hero out from valid spots. Review `BLAST_ZONES` positions + hole-drop.
- **"Entire floor needs fixing"**: review `DestructibleFloor` segment collision/seams.

### Phase 1b — TWO MORE BUGS/ASKS from playtest (fold into Phase 1/2)
- **"I WIN after ~one character — should only win when ALL enemies dead."** VersusArena
  `_finish_match("VICTORY")` fires when `_bots_alive()==0`. BlastSpell uses `target_group`
  ("hero" for the MAGE bot) so it's probably NOT AoE friendly-fire — most likely the **bots
  are RINGING OUT on the broken map / falling into the void** (bad footing, floor holes, or
  the blast-zones catching them), so only ~1 is left to kill. Fixing the map + spawns + void
  (Phase 1) likely resolves it. ALSO verify no enemy projectile/minion friendly-fires other
  enemies, and consider tracking eliminations explicitly vs the transient `_bots_alive()` poll.
- **Q (AoE slot) abilities are "just reworks of each other."** Correct — blast/nova/fist_shock/
  ground_slam are all `BlastSpell.configure` variants. Same fix as the G signatures got: give
  each CLASS a DISTINCT, epic Q spectacle (not a recolored blast). This is a per-class-Q kit
  pass parallel to the signature de-clone already done.

### Phase 2 — MAKE THE G's ANIME FINISHERS (the headline feel ask) — ✅ DONE
Maker: *"isn't G the ULTIMATE where the character does something awesome? ice is cringe — no
spell circle, no summoning animation. They ALL need that for the G's ESPECIALLY."*
- Channeled ults (beam/ray/meteor/convergence) already levitate + grow a `MagicCircle`
  (float-channel). The INSTANT signatures (ice_wall, chain_lightning, rune_orbs, blink_strike,
  blade_flurry, void_zone, drain_tether, boulder/pillar/wall) fire with NO ceremony → cheap.
- **FIX: every signature gets an epic SUMMON windup** — `MagicCircle` spell-circle blooms +
  committed cast pose + gather motes (~0.3–0.6s) → the spell ERUPTS. Route them through a
  short `_begin_channel`-style windup or a shared "summon flash" helper.

### Phase 3 — SPELL-STORM DENSITY + PRESSURE
- **Give the ENEMIES the class kits** so the screen is full of BOTH your spells and theirs.
- Faster pacing (shorter cooldowns, snappier dashes), **trails + bloom on everything**,
  ragdolls launching on death. "Make the enemies even cooler / more diverse."

### Phase 4 — THE HOOK (can't-let-go)
- **DMC-style style/combo meter** rewarding flashy, varied, no-repeat ability chains.
- Riding on the **persistent Tower climb** (death = drop 2 floors, keep everything, NPCs
  remember + roast your run) — escalation + "just one more floor" + a style score to beat.
- Swap in the **real SFX packs** for pro polish.

## The through-line to BUILD: an `EpicMoment` juice system
One system that, on any big beat (ult cast, big hit, kill), SYNCHRONIZES: charge-sound →
growing sigil → camera pull/slow-mo → hitstop → screenshake → bloom flash → aftermath.
Wire every ult + every kill through it. `Juice.on_hit` is the seed — generalize it.

## DESTRUCTION must be BIGGER + NATURAL (maker: "not destroying the map nearly as much as I hoped")
- Spells should TEAR UP the map far more — bigger break radius, more flying chunks, more
  craters, floors/platforms dramatically collapsing where big spells land.
- But LOCALIZED + natural: only the surface AT the impact breaks/chips (not the whole thing),
  diversified block looks, smaller chunks. Cover currently shatters WHOLE — make it chip.

## AUDIO — still corny, needs work (maker)
- **Zoltraak / the `beam` SFX sounds goofy/corny** (the charge_up is good; the discharge isn't).
  Rework the `make_beam` synth (less kazoo, more searing laser) — or replace with a real clip.
- **Meteor animation weird + its ground AREA effect looks off** — rework to look epic (longer-term).
- **Fantasy SFX pack** uploaded at `Effects/Free Fantasy SFX Pack By TomMusic` (+ Sonniss
  downloading). Audit + map clips to the wired `Sfx.gd` keys (cast/charge_up/beam/cannon/zap/
  ice/earth/holy/nova/blast/melee_hit/melee_swing/blink/footstep/ding/hero_hurt/enemy_death/
  spell_impact) — drop `.wav` into `assets/audio/sfx/`, keys already wired. **NO voice grunts**
  (maker: "corny"). Maker also grabbed VFX libs (godot-4-VFX-assets, GODOT-VFX-LIBRARY, portal
  shader) + KayKit packs in Downloads — potential integration.
- **VFX + SFX ASSETS ARE NOW IN `Effects/` (maker extracted them — ACTION ON RESUME):**
  - VFX: **`Effects/GODOT-VFX-LIBRARY-main/addons/vfx_library`** (a Godot 4 VFX addon — enable
    it as a plugin, use its particle effects) + **`Effects/godot-4-VFX-assets-main/effects`**.
    Audit the particle scenes/shaders, wire the epic ones into the spectacle scenes + ElementFx
    + impact sites (beams, meteor, ults, hits) so "all moves look epic" + spell-storm density.
  - SFX (Sonniss/pro packs, replace the synth placeholders — map to the wired Sfx.gd keys):
    `Effects/Cinematic Sound Design - Colossal Impacts` + `Effective Trailer Booms` -> cannon/blast;
    `Alexander Kopeikin - Emotion and Magic` -> beam/cast/charge_up/holy/nova/zap;
    `Alexander Kopeikin - 100 kHz Designed Ice` -> ice; `David Dumais - Melee Weapons` -> melee_hit/swing;
    `Cinematic Sound Design - Cartoon Impacts` -> spell_impact/ding. FIX the corny `beam` synth
    by dropping a real searing-laser clip over `beam_1/2.wav`. NO voice grunts.

## Recommended resume order (next session, fresh context)
1. **Phase 1** — one clean connected arena + fix ducking-clip + void ring-out + floor. (foundation)
2. **Phase 2** — epic summon windup (spell circle + pose) for ALL signatures + the `EpicMoment` sync system.
3. Bigger natural destruction + rework the `beam` SFX.
4. Phase 3 (enemy kits/density) → Phase 4 (style meter + climb + real SFX packs).
