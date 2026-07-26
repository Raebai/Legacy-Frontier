# Magic Overhaul — Build Plan (stickman-integrate)

> **Goal.** Take the 24-spell kit + the stick rig from "reads as recolored flat shapes" to **anime-grade, dopamine-inducing spectacle** (quality bar: JJK "Hollow Purple") — every spell a distinct, characterful cast, no two alike, all manually-aimed, all dodgeable, most deflectable, wired into a **curated spell-interaction system**. Plus rig polish (speed-lines), Stick-Fight footstep/punch/deflect audio, air-dash + parry in the playground, and **localized** impact frames.
>
> **Maker decisions (locked this session):** interaction system = *curated reactions layer* (element×kind + physics, on the equip-one-spell model — NOT Magicka live-composition); execution = *full autonomous sweep, commit per phase, maker F5s the result*.
>
> **Verify loop = SCREENSHOTS.** `godot-project/tools/spell_playground_capture.gd` renders any spell headless → PNG in `user://`. Every redesign is render-verified by adding a per-spell shot, running the capture, and *looking at the image* until it's thrilling — not just "tests green". Quality north star: `docs/references/stick-fight-feel-study.md`. Foundation detail: `docs/references/spell-polish-plan.md`.

## Rules that bind every spell (from the maker's TODO)
1. **NO auto-aim / NO homing** on anything. Everything aims manually toward the cursor. Kill: `rune_orbs` homing, `chain_lightning` seek, `drain_tether` auto-lock, `chidori` fork auto-aim.
2. **Everything DODGEABLE** — a real on-target telegraph + a reaction window before damage resolves. No instant/undodgeable hits.
3. **Every spell DEFLECTABLE/PARRYABLE** unless it's a giant ult explicitly designed to break through (a real design axis). Today the parry layer only touches the basic bolt — all 24 signatures bypass it. Wire signatures into the parry/reflect system.
4. **A distinct, characterful CAST animation** on the stickman for each spell (ragdoll ground-slam / magic-circle windup / levitate-channel / fist-charge) — never a plain instant spawn. `cast_time` "levitating windup" already exists on beams/rays/meteors/convergence; extend the taxonomy.
5. **No two spells look alike or are recolors.** Break the shared-scene recolor families (below).

## The recolor families to break (from the code map)
- **5 beams → one `BeamSpell`**: only fire (dragons) + frost (hex lens) are bespoke; `zoltraak`/`umbral_lance`/`tempest` are pure tint-swaps. Each element beam needs its own signature motif.
- **4 meteors → one `MeteorSigil`**: fire/shadow/earth/ice recolors of one falling-head template.
- **2 walls → `RockWall` + a literal `IceWall` fork**: same block-stack silhouette. Rock = chunky/opaque + **shoveable** (punch/RMB slides it across the arena until it hits something — maker ask). Ice = translucent crystal, **shatters** into a shard-burst when hit by fire/impact (feeds interactions).
- **`void_zone` + `blizzard` → one `ZoneSpell`**: same ground-ellipse+ring. Blizzard reworked (maker dislikes it). Shadow reworked → **shadows erupt FROM the figure and ROOT the target in place** with a dodge window before it locks (maker ask).
- **`colossus_pillar` = mis-tinted Judgment** (`_ray()` forces `effect="holy"`, never overridden → a "stone spire" renders as a brown holy light column). Give it a real stone-eruption identity distinct from `rock_pillar`.
- **`blink_strike` special dispatch** (routed through `Hero._finish_summon`, no `SpellCaster.BLINK_STRIKE` arm) — normalize onto the standard data→dispatch seam.

## Phase plan (commit per phase)

### Phase 0 — Foundation (shared infra; lifts the whole kit at once)
Per `spell-polish-plan.md` §0. Do FIRST; every later phase builds on it.
- **Soft round particle texture** (shared static dot) + **additive-blend flag** + **material/texture cache** in `CombatVfx.spawn_burst` — kills the "blocky confetti" look everywhere.
- **HDR 2D + WorldEnvironment glow (bloom)** in Arena + SpellPlayground scenes; push spell cores >1.0 so they bloom.
- **Antialiasing sweep** groundwork (helper), applied per-spell in Phase 2 as each spell's `_draw` is rewritten.
- **Element emissive companions** in `Elements.gd` so SHADOW/EARTH don't read muddy under bloom.
- **Localized impact frames**: thread the world hit-position through `Juice.impact_frame()` → `ImpactFrame.flash()`; draw the flash + converging lines AT the hit point (screen-projected), not viewport center. Add an optional world-space variant.

### Phase 1 — Rig + feel (the stickman itself)
- **Rewrite `SpikeFigure._spawn_wind_streaks`** — the "goofy" straight-white-line speed-lines. Make them Stick-Fight-crisp: tapered, curved, motion-biased, additive, short-lived; distinct flavor for punch vs jump vs wall-jump vs hit.
- **Wire spike-rig audio** (assets + `Sfx` autoload already exist, just unwired in the spike scene): `footstep` on step-plant, `melee_swing`/`melee_hit` on punch, land thud, and the `ding` on deflect. Pitch-vary per the feel study.
- **Port air-dash** from `Hero.gd` (`DASH_SPEED 620`, air-capable, i-frames) into `SpikeFigure`/playground — a dash key toward aim/facing with brief i-frames + ghost afterimages.
- **Port parry/deflect** from `Hero.gd` (`PARRY_WINDOW 0.16`, reflect + ding + directional shield shell) into the playground rig; add the incoming-projectile-vs-figure hookup so deflect has something to catch.
- **Add a `cast()` verb + cast poses** to `SpikeFigure` (it has `punch()`/`hit()`/`kill()` but no cast) so Phase 2 windups have a rig hook, mirroring `Hero._begin_summon`/`_process_summon`.

### Phase 2 — Per-spell identity redesign (parallel fan-out, screenshot-verified)
Each spell gets the **redesign template**: (a) a distinct cast windup on the rig, (b) a distinct on-target telegraph + dodge window, (c) manual aim (no homing), (d) a **unique visual language** (motif, palette-beyond-tint, particle character, silhouette), (e) AA + additive + HDR cores, (f) a localized impact beat, (g) a deflect behavior (deflectable / break-through). Anime references welcome per spell. **Verify each by rendering its playground shot and looking.**

### Phase 3 — Interaction system (curated) + deflect wiring
~20-30 hand-authored reactions emergent from element×kind + physics. Headliners:
- **Hollow Purple**: two *opposing-element beams* crossed → collapse into a purple annihilation burst (red+blue→purple, made literal).
- Fire beam/meteor + **Ice Wall** → wall shatters into a shard-burst (AoE).
- Fire + **Blizzard/ice zone** → steam cloud (obscures / soft-CC).
- **Chain Lightning** through a chilled/wet target or frost zone → arcs further / harder shock.
- **Rock Wall shove** into enemies → damage + pin (the maker's shove mechanic as an interaction).
- **Boulder Hurl** through **Ice Wall** → shatters it into shrapnel.
- Meteor landing inside a **Void Zone** → void-charged bigger detonation.
- Full matrix authored as data (element-pair × kind) so new spells inherit reactions. Wire the signature spells into the parry/reflect layer here.

### Phase 4 — Verify + audit
Headless test suites green; render a montage of all 24 + key interactions; self-review the images against the Hollow-Purple bar; balance pass (mp/cd/damage/telegraph windows); commit. Maker F5s.

## Screenshot-verify protocol
Add per-spell shots to `tools/spell_playground_capture.gd` (index into `SpellLibrary.build_all()`; short beams ~40 frames, bombardments ~75). Run: `Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/spell_playground_capture.gd`. PNGs land in `%APPDATA%\Godot\app_userdata\Legacy Frontier\`. Read the PNG, judge, iterate. Reset arena state between big spells so shots don't overlap.
