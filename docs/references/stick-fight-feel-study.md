# Stick Fight: The Game — Game-Feel Study & Godot 4 Replication Reference

> **Purpose.** This is the canonical reference for how *Stick Fight: The Game* (Landfall Games, 2017, Unity) achieves its crisp, non-pixelated, extremely satisfying game-feel — decomposed into the underlying **techniques and design principles** so that our own procedural stick-figure brawler in **Godot 4 (GDScript)** can re-implement the same *feel* from scratch. It focuses on *why* things feel good and *how to reproduce them ourselves*. It does **not** reproduce Stick Fight's copyrighted assets, audio files, level data, or source code — everything here is technique described in our own words, cross-referenced against dev interviews, the game-feel literature (Vlambeer, Eiserloh), community docs, and the official settings menu, with sources listed at the bottom.

> **Legal boundary.** Design principles and techniques are not copyrightable; specific art, audio, and code are. We study the *approach* and build our own implementation. Where a number comes directly from a developer it is marked **[dev-confirmed]**; where it is standard game-feel practice or our recommended starting value it is marked **[inferred / our recipe]**.

---

## How to use this doc

- Each major section is structured as **(a) What Stick Fight does → (b) Why it works (the principle) → (c) How to replicate in Godot 4**.
- The **"How to replicate"** blocks contain concrete numbers, tuning ranges, and GDScript-shaped pseudocode you can lift into `scenes/combat/` and the `Tuning` autoload.
- Start with the **Priority action list** at the bottom — it is the ranked, most-impactful-first checklist for Legacy Frontier's `v2.0-tower` combat.
- Treat every number as a **starting point to feel-tune**, not gospel. Stick Fight's own feel came from hundreds of iteration passes; the values here get you to the right ballpark fast.

---

## 0. The one-sentence thesis

Stick Fight feels premium not because of high-fidelity art but because **every input produces an immediate, physical, over-amplified reaction** — clean high-resolution vector silhouettes (so nothing is ever muddy) driven by **active-ragdoll physics** (so bodies always react believably), wrapped in a thick layer of **juice** (screenshake, hit-stop, particles, knockback, sound) that makes even a single punch read as an *event*. Readable art + reactive physics + amplified feedback = the whole trick.

---

## 1. Art & rendering — why it looks crisp, never pixelated

### (a) What Stick Fight does
- Characters are **minimal vector-style stick figures**: a round head + a few thick, solid-color limb segments, rendered as clean geometry, not sprite pixels. The silhouette is instantly readable at any size.
- **Flat, high-contrast colors.** Each player is a single saturated solid color (red/blue/green/yellow) against relatively muted, low-detail backgrounds so players never lose track of their own character in chaos.
- Rendered at **native high resolution with anti-aliasing** (the options menu exposes an explicit *Anti Aliasing* toggle; default resolution is the desktop's, e.g. 2560×1600). Because the shapes are vector-clean and MSAA smooths the edges, there is **no pixelation** — lines stay smooth at any zoom.
- **Lineage:** the look descends from the *Xiao Xiao* Flash stick-fight animations (Zhu Zhiqiang, 2000–2002), whose whole appeal was that extreme simplicity made the *motion* the star. Stick Fight inherits that: simple bodies, expressive movement.
- Backgrounds and levels are **low-detail, flat-shaded platforms** — deliberately un-busy so the eye tracks the fighters and projectiles.

### (b) Why it works (the principle)
- **Silhouette readability is the #1 art priority in a chaotic brawler.** When four bodies, several guns, and a dozen projectiles are on screen, the player must parse the scene in a fraction of a second. Solid shapes + one color per fighter + calm backgrounds = zero visual ambiguity.
- **Vector/geometry art is resolution-independent.** Unlike pixel art (which is intentionally aliased) or low-res sprites, clean geometry scales to any display and camera zoom without ever looking muddy — this is *the* reason it never looks pixelated. Anti-aliasing removes the last hard jaggies.
- **Simplicity frees the budget for motion & juice.** No animator needed, no texture memory spent — all the "production value" goes into physics reaction and effects, which is what the player actually *feels*.

### (c) How to replicate in Godot 4
- **Draw the stick figure procedurally, not as a sprite.** Use `_draw()` on a `Node2D` with `draw_line(from, to, color, width, antialiased=true)` for limbs and `draw_circle()` / `draw_arc()` for the head. Limb widths ~4–8 px at 1× let you scale freely. This keeps bodies vector-crisp and lets ragdoll joint positions drive the drawing directly.
  - Alternatively use `Line2D` nodes (set `width`, `antialiased = true`, `joint_mode = LINE_JOINT_ROUND`, `begin/end_cap_mode = LINE_CAP_ROUND`) parented to the physics bones so limbs are smooth capsules with rounded caps.
- **Enable MSAA for 2D** in Project Settings → Rendering → Anti Aliasing → **`msaa_2d = 4×`** (`rendering/anti_aliasing/quality/msaa_2d`). Also turn on **2D HDR off / linear**, and set `rendering/anti_aliasing/quality/screen_space_aa` only if you have non-geometry edges. For `_draw()` lines, pass `antialiased = true`.
- **Render at native resolution; never at a low base.** Set the stretch mode to **`canvas_items`** with an aspect of `expand`, and let the viewport run at the window resolution. Do NOT use `viewport` stretch with a tiny base size (that's the pixel-art path — the opposite of what we want). If you support mobile, keep the design resolution high (e.g. 1920×1080 reference) and let `canvas_items` scale it cleanly.
- **Color discipline:** one saturated solid color per fighter, pulled from a small high-contrast palette; keep backgrounds desaturated / lower-value so fighters pop. Reserve pure white/bright flashes for hit feedback only (see §4).
- **Keep the world flat and calm.** Platforms as solid flat shapes with a subtle outline; avoid busy textures behind combat. Readability beats detail.
- **Our project note:** Legacy Frontier already uses procedural stick-figure rigs (Slice 1). The upgrade path is: (1) turn MSAA 2D to 4×, (2) convert limb rendering to `antialiased` lines/`Line2D` with round caps, (3) audit the palette for one-color-per-fighter contrast against the background.

---

## 2. Movement & JUMP feel

### (a) What Stick Fight does
- Movement is **snappy and light but grounded** — fast horizontal acceleration, quick stop, generous air control. Bodies are physics ragdolls but a "standing/balance" controller keeps them upright and responsive so control feels tight, not floppy, until they get *hit* (then they flop).
- **Jump** is a quick, punchy arc with strong gravity — you go up fast and come down fast (low float). Air control lets you steer mid-jump.
- **Advanced movement tech emerges from the physics:** *punch-jumping* (punch + jump together to gain height/speed), and *double-jumping / weapon-jumping* off thrown or falling weapons (weapons are physics objects you can bounce/launch off). None of this was hand-authored — it falls out of the consistent physics rules. **[community-confirmed]**
- **Landings and impacts read physically** because the ragdoll's mass reacts — there's weight to hitting the ground and to being knocked around.

### (b) Why it works (the principle)
- **Responsiveness first, realism second.** The character responds to input *this frame*; the physics ragdoll adds believable secondary motion on top. Players forgive floppy bodies as long as the *control* is crisp.
- **Low float = weighty & decisive.** A fast up/down arc with high gravity reads as "weighty and skillful"; a slow floaty arc reads as "mushy." Stick Fight leans weighty.
- **Emergent tech = depth for free.** Because the same physics rules apply to bodies and weapons alike, expert players discover movement combos the devs never scripted. Consistent rules > special cases.

### (c) How to replicate in Godot 4
Use a **`CharacterBody2D`** for the *control* capsule (tight, deterministic movement) and drive a *cosmetic* active ragdoll on top for the flop (see §6). This "control body + reactive visual" split is the key to "crisp control, floppy reaction."

**Jump & gravity tuning (design-driven, not realistic) — [inferred / our recipe]:**
Pick the *feel* (height + time), then derive gravity and jump velocity so they're never arbitrary:
```gdscript
# Design intent: jump peaks at ~2.2 tiles, ~0.32s up.
const JUMP_HEIGHT := 96.0        # px to apex
const TIME_TO_APEX := 0.32       # seconds
var gravity := (2.0 * JUMP_HEIGHT) / (TIME_TO_APEX * TIME_TO_APEX)   # ~1875 px/s^2
var jump_velocity := -sqrt(2.0 * gravity * JUMP_HEIGHT)              # ~ -600 px/s
```
- **Asymmetric gravity for punch:** multiply gravity by ~**1.3–1.8×** while falling (`velocity.y > 0`) so the descent is snappier than the rise — this is the single biggest "weighty jump" trick.
- **Fast-fall / low apex hang:** optionally add a tiny gravity reduction (×0.85) for a few frames near the apex for a hint of hang time, then the heavy fall.
- **Air control:** allow ~**70–90%** of ground acceleration in air; keep full directional steering.
- **Ground accel/decel:** reach max speed in ~**6–10 frames** (accel ≈ `max_speed / 0.1s`), stop in ~**4–6 frames**. Snappy but not instant.
- **Coyote time** ~**0.08–0.10s** and **jump buffer** ~**0.10s** — invisible forgiveness that makes jumps feel "fair" and responsive. (Legacy Frontier already has input buffering; extend it to jump.)
- **Variable jump height:** cut upward velocity (`velocity.y *= 0.5`) on jump-button release for skill expression.
- **Emergent tech, on purpose:** make weapons/projectiles real physics bodies the player can stand/bounce on, and let a jump-during-attack add a small upward impulse — this reproduces punch-jump/weapon-jump depth without scripting each case. Keep physics rules *uniform* across bodies and items.

**Landing feel:** on `is_on_floor()` transition from airborne with downward speed above a threshold, fire a **land event** → dust puff particles + small squash (scale.y ×0.8 for ~80 ms then ease back) + micro screenshake proportional to impact speed (see §4). This is where "weight" is sold.

---

## 3. Combat & fighting style

### (a) What Stick Fight does
- **Melee** (punch/kick) is fast, short-range, and lands with heavy knockback for its size — a punch can shove or juggle an opponent.
- **Guns are the stars:** a wide arsenal — Pistol, Revolver, Deagle, Uzi, AK47, M16 (3-round burst), Sniper (with laser sight), Minigun, plus exotic ones — Laser, Snake/Gun, Time-Bubble (freeze), Ice gun (slow), Black-Hole gun. Each has distinct **damage, ammo, rate of fire, and knockback**. Examples **[community-confirmed]**: Fists ~22 dmg; Pistol ~32; Revolver ~44; Deagle ~56 with very high knockback; Sniper ~75; the **Laser** and **Minigun** have knockback so extreme they can launch *the shooter themselves* off the map.
- **Pick-up-a-random-weapon design:** weapons spawn/drop into the arena; everyone scrambles for them. You hold one at a time, can throw it, and it runs dry — forcing constant re-arming and role changes. This randomness is the core chaos engine.
- **Recoil is real and dangerous:** firing pushes *you* backward (the Minigun/Laser can self-eject you off a ledge). Recoil is not cosmetic — it's a risk/reward mechanic.
- **Hit reaction = ragdoll.** Getting shot/punched doesn't play a canned hurt animation — it applies a physics impulse to the ragdoll, so bodies **fly, spin, tumble, and flop** believably and comically. Death = full limp ragdoll launched by the killing blow.
- **Aiming** is analog/directional (aim the held weapon toward a direction); no pixel-perfect precision required — the chaos and knockback do the work.

### (b) Why it works (the principle)
- **Knockback is the feel.** In a brawler, *displacement* is the clearest possible feedback: you see the enemy physically move because of your action. Over-tuned knockback (bigger than "realistic") reads as powerful and funny.
- **Physics hit-reactions never repeat.** Because impulses + ragdoll produce a unique flop every time, combat never looks canned — infinite comedic variety from one rule.
- **Random weapons = infinite fresh scenarios.** You can't master a loadout; you master *adaptation*. Every round is a new joke. This is the "easy to learn, endlessly chaotic" loop.
- **Self-affecting recoil adds risk.** Making the weapon push you too means power is dangerous — this is emergent, self-balancing, and hilarious.

### (c) How to replicate in Godot 4
- **Data-drive weapons** as `Resource`s: `damage`, `fire_rate`, `projectile_speed`, `spread_degrees`, `knockback_impulse` (applied to target), `self_recoil_impulse` (applied to shooter), `ammo`, `screenshake_trauma`, `hitstop_ms`, `muzzle_scale`, `sfx`. This matches Legacy Frontier's data-driven ethos and lets you tune feel per-weapon in one place.
- **Knockback as impulse toward the hit direction:**
  ```gdscript
  var dir := (target.global_position - source.global_position).normalized()
  target.apply_knockback(dir * weapon.knockback_impulse)   # e.g. 250–900 for light→Deagle-tier
  ```
  On the control body, translate the impulse into a decaying velocity add (`knockback_vel += impulse/mass`) that the character controller blends with input over ~0.15–0.4s; on the ragdoll, `apply_central_impulse()` to the torso bone so the *visual* flails.
- **Over-tune knockback ~1.5–2× past "realistic"** — it should look slightly absurd. Scale knockback with damage so big hits shove hard.
- **Self-recoil:** apply a smaller opposite impulse to the shooter (`self_recoil_impulse` ~ 10–30% of muzzle power for normal guns, up to *launch-you* levels for a joke Minigun/Laser). Recoil is a mechanic, not decoration.
- **Random weapon pickups:** spawn weapon pickup bodies into the arena on a timer / on kills; one held weapon at a time; throwable (convert to a physics projectile with the same knockback rules); ammo depletes → auto-drop to fists. The scramble *is* the game.
- **Hit reaction via ragdoll impulse, never a canned clip** (see §6). On any hit: (1) apply knockback impulse to torso, (2) trigger hit-stop, (3) spawn impact particles, (4) flash the victim white for 2–3 frames, (5) screenshake, (6) play layered impact SFX. All six fire together — that stacked simultaneity is what makes a hit feel "premium."
- **Aim model:** directional/auto-assisted, not pixel-perfect (Legacy Frontier's auto-aim cast already fits this). Keep it mobile-friendly per the project's mobile-first rule — knockback + juice carry the impact so precision isn't required.

---

## 4. JUICE / game-feel (the core of the premium feel)

This is the highest-leverage section. Stick Fight's "expensive" feel is ~80% juice on top of simple parts. The canonical playbook is **Vlambeer's "The Art of Screenshake"** (Jan Willem Nijman) and **Squirrel Eiserloh's trauma-shake model** — both are the *techniques* Stick Fight uses in spirit.

### (a) What Stick Fight does
- **Screenshake** on impacts, shots, and explosions (exposed as a player-tunable slider in options — see §7).
- **Hit-stop / freeze-frames:** a micro-pause at the moment of a big impact that sells weight.
- **Particles everywhere:** muzzle flashes, sparks/debris on bullet impact, dust on landing/running, smoke on explosions, block/wall chunks.
- **Impact flashes:** bright pops at the hit point and on the struck body.
- **Camera behavior:** smooth follow that frames the action; kicks/shakes on events; keeps all fighters in view.
- **Comedic timing:** the ragdoll flop + a beat of hit-stop + an over-big knockback lands the joke. The *timing* of the amplified reaction is the humor.

### (b) Why it works (the principle)
Nijman's thesis: a game's feel is built from **many tiny amplifications of feedback**, each nearly invisible alone, enormous in aggregate. Eiserloh's thesis: shake should be driven by a **single `trauma` scalar, squared, decaying** — so it's smooth, controllable, and never linear/janky. Together they explain *why* Stick Fight punches above its visual weight.

### (c) How to replicate in Godot 4

**1) Trauma-based screenshake [Eiserloh model — dev-confirmed formulas]:**
```gdscript
# On the Camera2D (or a Node that offsets it)
var trauma := 0.0                 # 0..1
const TRAUMA_DECAY := 1.2         # per second (linear decay)
const MAX_OFFSET := Vector2(24, 16)   # px
const MAX_ROLL := deg_to_rad(4.0)     # radians
var _t := 0.0

func add_trauma(amount: float) -> void:
    trauma = clampf(trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
    _t += delta
    trauma = maxf(trauma - TRAUMA_DECAY * delta, 0.0)
    var shake := trauma * trauma           # SQUARED — non-linear (key!)
    var nx := _noise(0, _t * 30.0)         # Perlin/FastNoiseLite, seed 0
    var ny := _noise(1, _t * 30.0)         # seed 1
    var nr := _noise(2, _t * 30.0)         # seed 2
    offset = Vector2(MAX_OFFSET.x * shake * nx, MAX_OFFSET.y * shake * ny)
    rotation = MAX_ROLL * shake * nr
```
- **Square the trauma** (`trauma^2`, optionally `^3` for even punchier): trauma 0.3/0.6/0.9 → ~9%/36%/81% shake — small hits barely shake, big hits slam. **[dev-confirmed]**
- **Add trauma per event, don't set it:** light hit `+= 0.15`, medium `+= 0.3`, big/explosion `+= 0.5–0.7`, landing scaled by impact speed. Trauma *accumulates* then decays, so rapid events stack.
- **Use `FastNoiseLite` (Perlin), not `randf()`** — smoothed noise looks like a real physical shake; pure random looks like a seizure. Separate seed per axis.
- **Add both translational offset AND small rotation (roll)** — rotation reads as much more violent for the same magnitude.
- **Always expose an intensity slider** (0–1 multiplier) so players who dislike shake can turn it down (Stick Fight does exactly this; it even ships defaulting the slider low).

**2) Hit-stop / freeze-frame [Vlambeer "sleep" — dev-confirmed ~ tens of ms]:**
```gdscript
func hitstop(ms: float) -> void:
    Engine.time_scale = 0.0            # or 0.05 for a near-freeze that still animates
    await get_tree().create_timer(ms/1000.0, true, false, true).timeout  # ignore_time_scale
    Engine.time_scale = 1.0
```
- Durations: light hit **~40–60 ms**, solid hit **~80–120 ms**, kill/heavy **~150–250 ms**. Nijman's original "sleep" was ~**20–100 ms**. Too long feels laggy; tune down until it's felt-not-noticed.
- Use `Engine.time_scale` globally, or (cleaner) freeze only the combatants for the window while VFX keep playing at 0.05× — a partial hit-stop reads as "impact bit into time."
- **Pair hit-stop with a 1–2px punch-in zoom** and the white flash for max impact.

**3) Particle recipes (`GPUParticles2D`, one-shot, `emitting=true`, `one_shot=true`) — [our recipe]:**
- **Muzzle flash:** 1 short-lived bright quad/star at the barrel, life ~**60–90 ms**, scaled by weapon `muzzle_scale`; plus 4–8 spark particles ejected in the fire cone.
- **Bullet impact:** 6–12 spark/debris particles, high initial velocity along reflection, gravity on, life 0.2–0.4s; a small flat impact flash sprite (life ~60 ms).
- **Dust puff (land/run):** 4–8 soft round particles, low velocity, upward+outward, life 0.3–0.5s, fade + grow. Emit on land and every few strides while running.
- **Explosion:** flash (1 frame bright), 20–40 debris particles, expanding smoke puffs with **persistence** (smoke lingers 1–2s and fades) — Nijman specifically calls out lingering smoke/shells as "permanence" that makes the world feel affected.
- **Blood/impact spray (stylized):** small colored particle burst on hit — keep it stylized/comedic to match the tone (or debris chunks instead of blood, per art direction).
- **Permanence:** leave decals (scorch marks, bullet holes) and shell casings that fall and rest as physics bodies — Legacy Frontier already has scorch decals; extend with shell casings and lingering smoke.

**4) Impact flash:** on hit, tint the victim's material white/additive for **2–3 frames** (`modulate = Color(4,4,4)` with HDR, or a flash shader `flash_amount`), then lerp back over ~120 ms. Cheap, enormous readability payoff.

**5) Camera behavior:**
- **Smooth follow** with `position_smoothing_enabled = true`, speed ~5–8 (Legacy Frontier already uses this).
- **Dynamic framing for multiplayer:** compute the bounding box of all live fighters each frame; set camera position to its center and `zoom` so everyone fits with padding (lerp zoom, clamp min/max). This is the couch-brawler camera and it keeps chaos legible.
- **Camera punch/kick:** on firing/explosions, add a tiny directional offset that springs back (separate from trauma shake) — Nijman's "camera kick."
- **Slow-mo on the final kill** (optional, big payoff): drop `Engine.time_scale` to ~0.3 for ~0.5s when the round-winning blow lands, then ramp back — turns the last flop into a highlight.

**Golden rule:** every meaningful hit fires **all** of these at once — hit-stop + flash + particles + knockback + shake + layered sound. The simultaneity is the "premium" feeling. Fire them from a single `Combat.on_hit(context)` dispatcher so they're always in sync and easy to tune centrally (a good fit for a `Tuning`/`Juice` autoload).

---

## 5. Sound design (principles + how to synthesize our own)

> We design/synthesize our own SFX — never reuse Stick Fight's files. What follows is the *technique* of why punchy game audio works and how to build equivalents.

### (a) What Stick Fight does (observed)
- **Punchy, layered impact sounds:** hits and shots have a sharp transient (the "crack") plus body plus a short tail — they cut through and feel physical.
- **Distinct weapon voices:** each gun has a recognizable sound so you know what's firing without looking; big guns sound big (more low-end/bass).
- **Reinforcement, not realism:** sounds are tuned to *sell the hit*, exaggerated and immediate, matching the exaggerated physics.
- **Footsteps, jump/land** cues give movement weight; **explosions** carry heavy low-end.
- **Music** is upbeat and energetic, driving the chaotic pace without competing with the SFX.
- The options menu exposes **Master / SFX / Music** volumes separately.

### (b) Why it works (the principle)
- **Audio is 50% of impact.** Nijman's very first feel-improvement was *sound* — before any visual trick. A hit with a sharp punchy sound feels twice as strong as the same hit silent.
- **Layered transient + body + tail** = the standard "weapon/impact" recipe: the **attack transient** grabs attention, the **body** gives weight/character, the **tail** places it in space and gives it size. Bass on big events makes them feel powerful.
- **Consistency & distinctness** let players parse a chaotic soundscape by ear (which gun, whose hit).

### (c) How to replicate in Godot 4
- **Layer every impact from 3 parts** when designing/synthesizing:
  1. **Transient / attack** — a click/crack/snap (short, bright, <30 ms). Sells "contact."
  2. **Body** — the tone/character (a thud, a boom, a mid punch), 50–150 ms.
  3. **Tail** — short reverb/decay/debris that gives size; bigger weapon = longer, bassier tail.
- **Add sub-bass to big events** (explosions, Deagle, Minigun) — a 40–80 Hz thump layer makes them feel heavy on real speakers/headphones. Nijman explicitly adds "bass."
- **Randomize pitch ±5–12%** per play (`AudioStreamPlayer.pitch_scale = randf_range(0.9, 1.1)`) and rotate 2–3 variant samples so repeated hits don't get "machine-gun same-sample" fatigue. Vary volume slightly too.
- **Play SFX exactly on the hit frame**, synchronized with hit-stop and flash — timing alignment is what makes it "connect."
- **Tools to synthesize our own:** jsfxr/sfxr/Bfxr for retro punches and lasers; Chiptone; or record + layer real foley (snap a ruler, punch a cushion) and pitch/EQ it. Reuse the project's already-licensed audio packs where they fit (per the asset-pipeline memory). Keep a small library of transient/body/tail one-shots to mix per weapon.
- **Bus routing:** separate **Master / SFX / Music** buses (mirror Stick Fight's options), add a limiter on Master and light compression on the SFX bus so stacked impacts stay punchy and don't clip. Add a subtle **ducking** of music under big explosions for extra impact.
- **Movement audio:** short footstep tick on stride, soft "whoomph" on jump, a heavier thud on land (scaled by impact speed, matched to the dust puff + shake).
- **Distinct weapon voices:** give each weapon a signature transient+body so it's identifiable by ear; scale low-end with weapon size.

---

## 6. Physics — the active ragdoll & physics-driven world

### (a) What Stick Fight does [dev-confirmed via Landfall interview]
- Bodies are **active ragdolls** built on the same physics-animation system Landfall used in *Totally Accurate Battle Simulator*. Landfall went physics-animation-first **out of necessity** (no animator) and it became their signature.
- The rig is a set of physics bones/joints with **controller scripts layered on top** that keep it alive and upright:
  - **Torque applied to legs via animation curves** to create a walk cycle (procedural, not keyframed).
  - **Step Handler** — decides when a step completes and the next can begin.
  - **Standing Handler** — measures head-to-floor distance and applies upward torque to keep the body standing.
  - **Balance script** — applies force to legs/feet to hold the center of mass over the base so it stays balanced.
- **Modularity:** each behavior is a separate script you mix per unit; a snake reuses gravity/rotation handlers but drops the standing handler (no legs). Same idea powers Stick Fight's characters.
- The **whole world is physics:** weapons are rigid bodies that react to bullets even when not held (shoot a falling gun and it flies off along the bullet vector), destructible/interactive level pieces, knockback impulses that fling bodies. Consistent rules across everything → emergent chaos.

### (b) Why it works (the principle)
- **Active ragdoll = crisp control + believable reaction in one system.** The controller scripts make it stand and walk responsively (feels like a normal character), but any external impulse (a hit) instantly wins and the body flops — free, unique, believable hit reactions with zero animation authoring.
- **"Wonky but intentional."** Landfall's craft is tuning the controllers so the physics reads as *characterful* rather than *broken*. The looseness is a feature (comedy + surprise), not a bug.
- **Uniform physics rules create emergent depth** (punch-jumps, weapon-launches, shooting held items out of hands) — content the devs never authored.

### (c) How to replicate in Godot 4
**Architecture: "control body + cosmetic active ragdoll."**
- **Control:** a `CharacterBody2D` capsule handles movement/collision deterministically (from §2). This is what the *player controls*.
- **Visual ragdoll:** a chain of `RigidBody2D` bones (torso, head, upper/lower arms, upper/lower legs) connected by **`PinJoint2D`** (or `DampedSpringJoint2D` for springier limbs). The ragdoll normally *follows* the control body; on a hit it's released to flop.

**Making the ragdoll stand & move (mirror Landfall's handlers):**
- **Standing/upright torque (Hooke's-law spring toward target angle):**
  ```gdscript
  # On each bone's _physics_process (or _integrate_forces):
  var angle_error := wrapf(target_angle - rotation, -PI, PI)
  var torque := SPRING_K * angle_error - DAMPING * angular_velocity
  apply_torque(torque)     # spring-damper drives bone toward pose (PD controller)
  ```
  Tune `SPRING_K` (stiffness) and `DAMPING` per bone: stiff torso/legs = stands firmly; looser arms = expressive flail. This is exactly the "apply torque to keep it upright/posed" technique.
- **Walk cycle:** drive each leg bone's `target_angle` from a looping curve (a `Curve` resource or `sin()` offset by phase) scaled by movement speed — "torque to legs via animation curves." Emit a step (dust + tick sound) at curve phase crossings (your **Step Handler**).
- **Balance:** nudge the control body / hip target so the center of mass stays over the feet; snap the ragdoll's hip toward the control capsule each frame with a spring (your **Standing/Balance handler**).
- **Follow-then-release:** while alive, springs pull bones toward the posed target (crisp control). On hit/death, **drop `SPRING_K` toward 0** (or raise damping only), and `apply_central_impulse(knockback)` to the torso — the body goes limp and flies. Ramp stiffness back up over ~0.3–0.6s to "recover" (or stay limp if dead). This gives Stick Fight's exact "controlled → flop → maybe recover" arc.
- **Modularity like Landfall:** make each behavior (Upright, Walk, Balance, Flop) a small component/script you attach per creature; a legless enemy just omits Walk/Balance. Reuse across your enemy archetypes.

**World physics:**
- Weapons/pickups = `RigidBody2D` that react to bullet impulses even when unheld (`apply_impulse` at hit point along the projectile's velocity). Uniform rules = emergent play.
- Destructibles = bodies that break into physics chunks on hard hits (Legacy Frontier already has breakable crates/platforms — keep those rules uniform with everything else).
- Knockback = `apply_central_impulse` on the ragdoll torso + a decaying velocity add on the control body, as in §3.

**Tuning warning (from Landfall):** active ragdolls are *fiddly*; budget real iteration time on `SPRING_K`/`DAMPING`/mass ratios. Start stiff and readable, then loosen until it's characterful but still controllable. Use a `Tuning` autoload with live sliders (Legacy Frontier already has one) to feel-tune without recompiling.

**Pragmatic MVP fallback:** if a full 2D active ragdoll is too heavy right now, get 80% of the feel with a **rigid posed character that switches to a full passive `RigidBody2D` ragdoll only on hit/death** (the classic "kinematic until killed" trick, per Godot's ragdoll docs), plus procedural squash/stretch + limb lag on the living character. Upgrade to fully-active later.

---

## 7. Settings / options / accessibility

### (a) What Stick Fight exposes [community-confirmed from the options menu]
- **Audio:** Master Volume, SFX Volume, Music Volume (independent).
- **Graphics:** Resolution, Framerate cap, Fullscreen, VSync, **Anti-Aliasing** toggle, and a **Screen Shake** slider (notably it ships with screenshake defaulted *low/0* — they respect motion sensitivity).
- **Controls:** fully **rebindable** keybinds; supports keyboard and controllers; local 2–4 player couch + online.
- Note: AA is described in-game as "smooths edges, looks better, costs performance" — confirming AA is the deliberate anti-pixelation lever.

### (b) Why it works (the principle)
- **Screenshake is polarizing → make it a slider.** Juice that some players find nauseating must be tunable; shipping a shake slider (and even defaulting it conservative) is best practice.
- **Rebindable controls + controller support = accessibility + couch play.** A party brawler must meet players on whatever input they have.
- **Separate audio sliders** let players balance punchy SFX vs. music to taste.
- **Explicit AA toggle** lets low-end machines trade the crisp edges for framerate — framerate *is* feel (input latency).

### (c) How to replicate in Godot 4
- Ship an options menu with: **Master/SFX/Music** volume (map to audio bus volumes via `AudioServer.set_bus_volume_db`), **Resolution + Fullscreen + VSync** (`DisplayServer` / `Window`), **Framerate cap** (`Engine.max_fps`), **MSAA/AA toggle** (`get_viewport().msaa_2d`), and a **Screen Shake intensity slider (0–1)** multiplying the trauma output. Default shake to ~0.5, allow full 0.
- Add a **hit-stop toggle/intensity** too (some players dislike time-freeze) — cheap accessibility win Stick Fight didn't have.
- **Fully rebindable input** via `InputMap` at runtime (Legacy Frontier is already action-based / mobile-first, so this is a natural fit) + on-screen/virtual controls for mobile.
- Persist settings to `user://settings.cfg` (`ConfigFile`).
- **Never lock framerate low** — high FPS *is* responsiveness. Uncap or cap high; let VSync be optional.

---

## 8. What made it unique & successful (design pillars)

### (a) What Stick Fight got right
- **Instantly readable + universally familiar** stick-figure aesthetic (Xiao Xiao nostalgia) — zero onboarding friction; anyone "gets it" in one glance.
- **Easy to learn, endlessly chaotic:** trivial controls (move, jump, attack, pick up weapon) + physics + random weapons = a new emergent story every round. Low skill floor, surprisingly high ceiling (punch-jumps, recoil control, weapon-juggling).
- **Physics-driven comedy = infinite, streamable content.** Ragdoll flops and self-inflicted recoil deaths are funny *every time* and never identical — this drove its viral "streamability."
- **Couch + online multiplayer, 2–4 players**, no single-player — it's a *social* chaos machine, built for reactions and laughter.
- **100+ interactive/destructible levels** with hazards keep the same simple ruleset endlessly fresh.
- **Premium feel on a tiny budget** — achieved entirely through physics + juice + readability, not art fidelity. This is the exact lesson for a solo/small dev.

### (b) The transferable principles
1. **Readability > fidelity.** Clean silhouettes and calm scenes beat detailed art in chaos.
2. **Reactive physics > canned animation.** One impulse-driven ragdoll rule yields infinite believable, comedic reactions for free.
3. **Amplify all feedback.** Over-tune knockback, shake, sound, particles — the "too much" point is usually right.
4. **Uniform rules create emergent depth.** Same physics for bodies, weapons, projectiles → tech the devs never scripted.
5. **Chaos is content.** Randomness (weapons, hazards) manufactures fresh, shareable moments indefinitely.
6. **Social by design.** Built around shared reactions (couch/online), which is also its marketing engine.

### (c) How this maps to Legacy Frontier
- Our **AI-NPC memory hub is the differentiator/moat**, but the *moment-to-moment* must feel Stick-Fight-crisp or nothing else matters. The tower-climb combat is where we win or lose on feel.
- We already have the right bones: procedural stick rigs, data-driven weapons/floors, `Tuning` live-knobs, scorch decals, breakables, input buffering, dash i-frames, trauma screenshake, hitstop, enemy death spectacle. The work is **tuning and stacking** these to Stick Fight's amplitude, plus the readability/AA pass and the active-ragdoll upgrade.
- Keep the **build-in-public** angle in mind: physics-comedy clips are the single most shareable thing we can produce (per the marketing memory) — the better the ragdoll/juice, the better the content engine.

---

## Priority action list for Legacy Frontier (ranked, most-impactful first)

> Ordered by feel-impact-per-effort for the `v2.0-tower` combat. Each is independently shippable.

1. **Turn on crisp rendering (fast, huge).** Set `rendering/anti_aliasing/quality/msaa_2d = 4×`; convert stick-limb drawing to `antialiased` lines / `Line2D` with round joints & caps; confirm `canvas_items` stretch at native res (not a low pixel base). Kills any pixelation/muddiness instantly. *(§1)*
2. **Unify the "on-hit" juice into one dispatcher and fire ALL of it every hit.** A `Juice.on_hit(ctx)` that triggers, together: hit-stop, white flash, impact particles, knockback impulse, trauma screenshake, layered SFX. Simultaneity = premium feel. *(§4)*
3. **Adopt the trauma screenshake model properly.** `trauma` scalar, **squared**, linear decay ~1.2/s, `FastNoiseLite` per-axis, offset **+ small rotation**, per-event `add_trauma` (0.15/0.3/0.6), plus a 0–1 **intensity slider** in options (default ~0.5). *(§4, §7)*
4. **Tune hit-stop to taste.** ~40–60 ms light / 80–120 ms solid / 150–250 ms kill, via `Engine.time_scale` with an ignore-time-scale timer; pair with a 1–2 px punch-in zoom + the flash. Add an accessibility toggle. *(§4)*
5. **Over-tune knockback + real self-recoil.** Make displacement the primary feedback: scale knockback with damage (~1.5–2× "realistic"); apply opposite recoil to the shooter (up to launch-you levels on the biggest weapon as a signature joke). *(§3)*
6. **Rebuild the jump for weight.** Derive gravity/jump-velocity from intended height+time; add **fall-gravity ×1.3–1.8**, variable jump height, coyote time ~0.09s, jump buffer ~0.10s, dust-puff + squash + micro-shake on land scaled by impact speed. *(§2)*
7. **Layer the audio (design our own).** Every impact = transient + body + tail; sub-bass on big hits; ±5–12% pitch randomization + 2–3 variants per sound; separate Master/SFX/Music buses with a limiter; play exactly on the hit frame. *(§5)*
8. **Upgrade hit-reactions to active-ragdoll flop.** Control-body + cosmetic ragdoll (PinJoint2D bones + PD/spring-damper upright torque, walk via leg curves, balance snap). On hit: drop stiffness + impulse the torso → flop; ramp back to recover, or stay limp on death. MVP fallback: kinematic-until-killed passive ragdoll first. *(§6)*
9. **Particle & permanence pass.** Muzzle flash, bullet-impact sparks, run/land dust, explosion smoke that **lingers 1–2 s**, shell casings as physics bodies, keep scorch decals. Permanence makes the world feel affected. *(§4)*
10. **Dynamic multiplayer/co-op camera.** Bounding-box-of-all-fighters framing with lerped zoom (clamped), smooth follow, small "camera kick" on fire/explosions, optional slow-mo on the round-winning blow. *(§4)*
11. **Random-weapon scramble loop (if not already).** Weapons spawn/drop into the arena, one held at a time, throwable as physics projectiles, ammo runs dry → fists. This is the chaos/replay engine. *(§3, §8)*
12. **Ship the options menu** (volumes, resolution, fullscreen, vsync, framerate, AA toggle, **screenshake slider**, hit-stop toggle) + fully rebindable/mobile input; persist to `user://settings.cfg`. *(§7)*

**Meta-principle to hold onto:** Stick Fight's premium feel is *readable art + reactive physics + amplified, synchronized feedback*. We already have most of the parts — the win is stacking them so every single hit is an over-amplified, multi-sensory event, and never looks or sounds canned.

---

## Sources

- Landfall physics-animation approach, ragdoll handlers (Step/Standing/Balance), procedural walk via torque + curves, "physics animation over keyframing," modular per-unit scripts — Game Developer: *How Landfall Games finds the fun in physics engines*: https://www.gamedeveloper.com/design/how-landfall-games-finds-the-fun-in-physics-engines
- Landfall / Stick Fight overview, procedural animation from TABS, viral streamability — GeForce NOW developer profile: https://gfn.co.kr/en/games/developers/landfall-games-ab/ and ABGames spotlight: https://blog.abgames.io/landfall-games-developer-spotlight/
- Official game page — Landfall: https://landfall.se/stickfightthegame
- Weapons (damage/ammo/knockback/recoil, self-launch guns), physics-object weapon behavior — Stick Fight Wiki: https://stickfightgame.fandom.com/wiki/Weapons ; NamuWiki: https://en.namu.wiki/w/Stick%20Fight:%20The%20Game ; Steam weapons tier guide: https://steamcommunity.com/sharedfiles/filedetails/?id=1280860224
- Advanced movement tech (punch-jump, double/weapon jump, juggling) — gameplay.tips guide: https://gameplay.tips/guides/1800-stick-fight-the-game.html ; Steam "Comprehensive Guide": https://steamcommunity.com/sharedfiles/filedetails/?id=1500250345
- Options/settings menu (Master/SFX/Music, Resolution/Framerate/Fullscreen/VSync/Anti-Aliasing/Screen-Shake, rebindable controls) — Steam "In Depth Guide to Stick Fight": https://steamcommunity.com/sharedfiles/filedetails/?id=2821046017 ; controls & local MP guide: https://steamcommunity.com/sharedfiles/filedetails/?id=1150529630
- PC technical/settings reference — PCGamingWiki: https://www.pcgamingwiki.com/wiki/Stick_Fight:_The_Game
- Store / multiplayer scope / positioning — Steam store page: https://store.steampowered.com/app/674940/Stick_Fight_The_Game/ ; SteamDB: https://steamdb.info/app/674940/
- Art lineage (Xiao Xiao, simplicity, motion-first, Matrix/slow-mo cinematography) — Animation Obsessive, *When Stick Figures Fought*: https://animationobsessive.substack.com/p/when-stick-figures-fought ; TV Tropes, Xiao Xiao: https://tvtropes.org/pmwiki/pmwiki.php/WebAnimation/XiaoXiao
- Trauma-based screenshake model (trauma 0–1, trauma² / trauma³, linear decay, Perlin noise per-axis, offset + rotation, sample numbers) — Squirrel Eiserloh, GDC 2016 *Math for Game Programmers: Juicing Your Cameras With Math*: slides http://www.mathforgameprogrammers.com/gdc2016/GDC2016_Eiserloh_Squirrel_JuicingYourCameras.pdf ; talk archive: https://archive.org/details/GDC2016Eiserloh ; transcript: https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt
- The full "juice" playbook (muzzle flash, bigger/faster bullets, impact effects, hit animation, knockback, screenshake, ~20–100 ms sleep/hit-stop, gun kickback, shell casings, added bass, permanence/smoke, camera lerp/kick) — Jan Willem Nijman (Vlambeer), *The Art of Screenshake*: talk https://www.youtube.com/watch?v=SkgkIXZ_13Y ; summarized principles: https://theengineeringofconsciousexperience.com/jan-willem-nijman-vlambeer-the-art-of-screenshake/
- Godot 4 active-ragdoll / physics-animation techniques (torque-driven joints, Hooke's-law balance, kinematic-until-killed) — Godot docs *Ragdoll system*: https://docs.godotengine.org/en/stable/tutorials/physics/ragdoll_system.html ; Active Rigid Body Ragdolls asset: https://godotengine.org/asset-library/asset/1218 ; example repo: https://github.com/CBerry22/Active-Ragdoll---Physics-Animations-in-Godot-4.0 ; forum thread on 2D active ragdolls (Stick-Ranger-style): https://forum.godotengine.org/t/2d-active-ragdolls/57016
- General game-feel/juice technique references — GameJuice *Juice it or Lose it*: https://gamejuice.co.uk/resources/juice-it-or-lose-it ; camera shake juice write-up: https://gt3000.medium.com/juice-it-adding-camera-shake-to-your-game-e63e1a16f0a6

---

*Compiled 2026-07-14. Marked **[dev-confirmed]** = stated by Landfall/Nijman/Eiserloh; **[community-confirmed]** = from wikis/player guides; **[inferred / our recipe]** = standard game-feel practice and recommended starting values for us to tune. All numbers are starting points for feel-iteration, not fixed truths.*
