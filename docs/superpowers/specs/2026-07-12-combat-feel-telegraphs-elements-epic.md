# Combat-Feel Overhaul II — Caster-Emanated Telegraphs, Elemental Effects, Epic Map, Menus

Date: 2026-07-12 · Branch: `v2.0-tower` · Play: `VersusArena.tscn` (F6), `Main.tscn` (F5)

Driver: maker playtest feedback (stacked, autonomous "just build it, ultrathink" session). This
doc pins the design decisions for the two real forks (telegraphs, elemental effects) and lists the
rest of the punch-list. Feel work is UNPLAYTESTED until the maker's hands validate (Gopeak/headless
can't render feel) — every item ends with a playtest ask.

## The maker's punch-list (verbatim intent)

1. **Telegraphs are wrong.** "The red circle on the target is not helpful — it should be a signal
   FROM the caster. Same with that red line, I don't know what it does." Plus: "use other cool prep
   noters — magic circles, stars, ring effects — all based on the attack, what's happening."
2. **Dash must be angle-accurate.** "If I'm holding up and side, the dash should go in that
   direction — accurate to which angle the keys I'm holding are."
3. **Elemental effects are fake.** "Look at the effects of the abilities, like freeze, burn, all
   that." (Today Elements only sets a colour — no gameplay.)
4. **Summoner needs a cap** on how many minions exist at once.
5. **Pause (Esc) needs more** — an Exit button + Settings (volume, controls).
6. **The map needs to look way more epic** generally (ref: `project_world_design`, 17 regions).

Already shipped this cycle (commit `b0f6f76`, verified in code): no instant-VICTORY (grace guard +
BOMBER pulled), pause toggle+overlay, dash-follows-movement (superseded by #2 below), looser ragdoll.

## Fork 1 — Caster-emanated telegraphs ("prep noters")

**Problem.** `Telegraph` is a flat red shape (`CIRCLE`/`LINE`) planted at a WORLD spot. The assassin &
brute plant the circle at the *hero's* position (the "red circle on the target"); the charger plants
an abstract rectangle (the "red line"). The read is: a gamey shape appears near YOU, with no visible
link to who's doing it or what it is.

**Principle.** A good tell (1) draws the eye to the ATTACKER — you learn "that enemy is dangerous
right now" — and (2) says WHERE/HOW to dodge. We keep (2) but make everything read as coming FROM the
caster, and give each attack a DISTINCT, cool sigil so the shape itself telegraphs the attack.

**Design.** Two cooperating pieces:

- **`CasterSignal` (new)** — a charge-up VFX that is a CHILD of the enemy rig (rides along if the
  enemy is knocked around): a gathering, brightening, archetype/element-tinted glow orb at the
  weapon-tip/chest with inward-spiralling motes, growing 0→full over the windup. This is the universal
  "the caster is winding up" read. Every telegraphed attack spawns one.

- **`Telegraph` redesigned** into distinct, animated sigils that emanate from the caster. It gains a
  `source` (the caster node) so it can draw a bright **tether** from the caster to the danger zone
  (causation is always visible) and per-attack SHAPES built from the existing `MagicCircle` sigil
  vocabulary (rings, runic ticks, hexagram, stars, apertures):
  - **CASTER bolt** → a small **face-on magic circle** at the caster's staff tip, muzzle pointed
    along the shot; a thin bright aim-tracer from the tip toward the snapshot aim. "It's charging a
    bolt, aimed there."
  - **CHARGER lane** → replaces the flat rectangle: a **runic charge-lane** originating AT the
    charger — a bright origin sigil + a lane that fills with scrolling chevrons/energy toward the
    target end, capped by an arrowhead. "It's about to rocket down this lane."
  - **ASSASSIN lunge** → replaces the circle-on-target: a short **dart-tracer** (star/cross reticle
    at the far end) from the assassin toward the snapshot spot. "The silver one is about to dart at
    me from over there."
  - **SUMMONER** → a **face-on summoning circle** on the summoner (gathering vortex + inward motes).
  - **BOMBER** → a big **pulsing rune ring** centred on the bomber (it already tells on itself; add
    the body charge-glow + a countdown pulse). "This thing is about to blow."
  - **BRUTE** → charge-glow on the brute + the ground danger-ring at the strike spot WITH a tether
    line back to the brute so it never reads as a free-floating marker.

  Colour: danger-red stays the baseline "this will hurt" signal, but the sigil tints toward the
  enemy's archetype/element accent so casters/chargers/assassins read distinct at a glance.

**Preserved:** the "snapshot the target, dodge the tell" grammar (the zone/tracer still marks where
the hit lands, computed at windup start), the world-anchored truth (the zone doesn't ride the enemy),
the `fired`-once timing and `advance(delta)` headless seam. Only the VISUALS + the caster-side
charge-glow + tether are new. Attack GEOMETRY is unchanged (conservative — this is a readability fix,
not a rebalance).

## Fork 2 — Elemental effects that matter

**Problem.** `Elements` only returns a colour + name. Freeze/burn/etc. do nothing.

**Design — `StatusEffects` (new), applied to enemies on hero-spell hit:**
- **FIRE → Burn (DoT):** ticks damage over ~2.5s; enemy draws flickering flame licks + ember motes;
  stacks refresh duration.
- **ICE → Chill/Freeze (slow):** scales `move_speed`/windup down (e.g. 55%) for ~2s; enemy draws an
  ice crust + frost sheen; heavy hits while chilled can briefly *freeze* (root) — a shattering
  crystal read.
- **LIGHTNING → Shock (arc + brief stun):** small stun on apply + a chain arc to one nearby enemy
  for partial damage; crackling spark VFX.
- **SHADOW → Weaken (amplify):** afflicted takes +X% damage for a few seconds; a dark smoky aura.
- **ARCANE → Unstable (mini-burst):** a small delayed arcane pop on expiry; magenta shimmer.

**Architecture.** A single `StatusComponent` child on Enemy holds active ailments + draws their
overlay; `apply(element, power)` is called from the hero's damage sources (`Spell`, `BlastSpell`,
`EnergyNova`, signatures) which already know `_element`. Enemy exposes `apply_status(element)`.
Pure-data tick logic is headless-testable; the draw overlay is cosmetic. Hero abilities pass the
current element through to what they spawn. Keep it readable + tunable; MVP is Burn + Chill + Shock
landing crisply, the other two lighter.

## Rest of the punch-list

- **Dash angle-accuracy:** `_start_dash` uses `Input.get_vector("move_left","move_right","move_up",
  "move_down")` as the primary dash direction (true 8-way from held keys; W+D → up-right). Falls back
  to velocity, then facing, when no keys are held. `move_*` are all bound (WASD+arrows); W is shared
  with jump so holding W to rise still yields a move_up component.
- **Summoner cap:** track live minions (group-count or a held list); `_start_summon_windup` no-ops /
  the summon spawns fewer when at/over `SUMMON_MAX_ALIVE` (~4). Minions that die free their slot.
- **Pause menu:** a reusable `PauseMenu` with Resume / Settings (master volume slider wired to the
  audio bus + a controls reference list) / Exit-to-hub (or quit in sandbox). Used by VersusArena now,
  Arena where practical.
- **Epic map:** gradient sky + parallax/atmosphere (distant silhouettes, drifting ambient motes,
  vignette, richer platform styling) in VersusArena + the run Arena, theme-tinted where a theme
  exists. Scoped as a visual pass over the existing background/platform builders — no stage-logic
  changes. (Bounded: the 17-region world is a much bigger backlog; this is an atmosphere pass.)
- **Tooling:** a `combat_capture.gd` that renders telegraphs / status effects / the map to PNGs
  (GPU binary) so the visuals are verifiable without the maker for every iteration.

## Verification & sequencing

Order: tooling → telegraphs → elemental effects → dash+summoner cap → pause/settings → epic map.
Each lands as its own commit, headless-verified (keep all slice suites green: telegraph, enemy
archetypes, enemy abilities, versus, parry, etc.) and visually verified via the GPU capture loop.
Then the maker playtests F6/F5 for feel.

---

## ROUND 2 — playtest feedback (2026-07-12, after the overhaul) — being implemented via parallel design agents + sequential build

Constraint: Godot project is single-writer (shared .godot cache + git index) → agents DESIGN in
parallel (read-only), orchestrator builds sequentially. Design workflow: `combat-feedback-design`.

**Bugs**
- After BLINK, gravity feels too heavy (blink doesn't reset velocity → inherited fall + GRAVITY_FALL).
- Can BLINK INTO walls (ends inside a solid) — must relocate landing to nearest open spot.
- Can walk UNDER/INTO the destructible cover block + under the floating stage into the block (cover not solid).
- Point-blank cast passes THROUGH a block (segment ray starts past it).
- Dash cooldown too short → can basically FLY (chained up-diagonal dashes).
- Projectiles STOP mid-air (lifetime timer) — should fly until they hit a platform or leave the map.

**Combat depth / interactions**
- Bots are dumb: just follow, can't dash/jump UP to the player on a ledge, clump under. Want smarter pursuit.
- Want ENEMIES to CAST SPELLS so spell-vs-spell + spell-vs-punch interactions show.
- Spells should have KNOCKBACK; knocked hard into a breakable → it cracks/breaks.
- Block islands = ACTUAL destructible blocks you can also JUMP OFF THE SIDES of (fully solid + breakable).
- Breakable PLATFORMS that REGENERATE naturally after a while.

**Feel (Stick-Fight quality bar)**
- Ragdoll still not floppy enough; want Stick-Fight-level animation/feel — simple + smooth.
- No way to DEFLECT PUNCHES (parry only reflects projectiles) — add melee/lunge deflect in the parry window.
- Jump slightly HIGHER.
- Frozen/CC'd enemies should read as frozen (stop the run cycle).
- Some SFX need work.
- Big spells (meteor, etc.) should ZOOM the camera OUT a little to show the spell action.

**Spell identities + balance (own design agent)**
- Judgment + Heaven's Verdict are WAY too OP → rebalance.
- Every element/signature must look DISTINCT (not one shared beam silhouette recoloured):
  Fire = two moving DRAGONS; Ice = a beam with ice/crystal effects; Arcane(purple) = its own thing.
- Judgment = a SINGLE LINE/column, not the whole-map row.
- Heaven's Verdict = a DIFFERENT spectacle (not another divine ray).
- Balance via risk/reward: harder-to-hit / more-committed spells hit harder.

**Structural**
- Build the PERSISTENT-CLIMB spine (floors step 5): death = drop 2 floors, stay in the tower, town clocks falls.
