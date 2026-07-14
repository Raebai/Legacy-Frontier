# Spell Polish & Optimisation Plan

> **Purpose.** A per-spell, buildable work plan to raise every spell/spectacle in the side-on stick-figure spell-brawler to *Stick-Fight-crisp* quality — smooth (never pixelated), aesthetic, readable, and satisfying. Quality bar: `docs/references/stick-fight-feel-study.md` (readable vector art + reactive physics + amplified, synchronized feedback).
>
> **Scope.** READ-ONLY audit of the combat draw/particle/juice code. Every recommendation is concrete GDScript. Files reviewed: `Spell.gd`, `SpellBoltVisual.gd`, `BeamSpell.gd`, `DivineRay.gd`, `MeteorSigil.gd`, `StarConvergence.gd`, `LightningRush.gd`, `BlastSpell.gd`, `EnergyNova.gd`, `MagicCircle.gd`, `CombatVfx.gd`, `Elements.gd`.

---

## 0. Cross-cutting findings (fix these once, every spell benefits)

These four levers touch shared infrastructure and lift the entire kit at once. They are the highest ROI in the whole plan — do them before per-spell tuning.

### 0.1 — Add HDR 2D + a WorldEnvironment glow (bloom). THE single biggest beauty lever.
Right now nothing blooms. Every spell is built from layered translucent bands and "white-hot cores", but without bloom a white core is just a flat white shape with a hard edge. Enabling 2D HDR + a glow pass makes bright cores bleed light exactly like real energy/lightning/holy beams, and lets you push core colours **above 1.0** so they read as genuinely incandescent.

- Project Settings: `rendering/viewport/hdr_2d = true` (Forward+ is already the renderer — see `project.godot` `config/features`).
- Add a `WorldEnvironment` to `scenes/combat/Arena.tscn` (and the hub/versus arenas) with an `Environment` that has **Glow enabled**: `glow_enabled=true`, `glow_intensity≈0.8`, `glow_bloom≈0.15`, `glow_blend_mode=SCREEN` (or ADDITIVE for hotter), `glow_hdr_threshold≈1.0`. Set `background_mode=CANVAS`.
- Then push spell cores into HDR, e.g. beam/lightning/nova cores from `Color(1,1,1)` → `Color(1.6, 1.6, 1.7)` and holy gold → `Color(1.8, 1.6, 1.0)`. Only the values above 1.0 bloom, so telegraphs and soft outer bands stay controlled.
- This is also what lets the hero **aura be re-enabled** (`Hero.gd: AURA_STRENGTH = 0.0` was killed because "the glow behind the figure obscured it" — that was glow *without* bloom; with a real bloom pass a subtle aura reads instead of muddying).

### 0.2 — Give particles a soft round texture + additive blend. Kills the "blocky confetti" look.
`CombatVfx.spawn_burst` never assigns `burst.texture`, so **every particle in the game renders as a small hard white/colored square** (1–6 px). At the game's 640×360 base upscaled ~2.1× that is precisely the "reads as pixelated / muddy" complaint, and it affects *every* spell because they all route through this one function.

- Generate one shared **soft radial-gradient dot** once (static, cached) and assign it to `burst.texture`:
  ```gdscript
  static var _DOT: Texture2D = _make_soft_dot()
  static func _make_soft_dot() -> Texture2D:
      var grad := Gradient.new()
      grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
      grad.colors = PackedColorArray([Color(1,1,1,1), Color(1,1,1,0.7), Color(1,1,1,0.0)])
      var t := GradientTexture2D.new()
      t.gradient = grad
      t.fill = GradientTexture2D.FILL_RADIAL
      t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(1.0, 0.5)
      t.width = 32; t.height = 32
      return t
  ```
  Assign `burst.texture = _DOT`. Instantly every burst becomes soft round glowing motes instead of squares. Re-tune `scale_min/scale_max` down (a 32px dot at scale 1.0 is already large; start `scale_min≈0.15, scale_max≈0.5`).
- Add an **additive** `CanvasItemMaterial` to bursts that are pure energy/light (spell impacts, blast, nova, beam/ray charge sprays) so overlapping motes build to white-hot instead of averaging to grey:
  ```gdscript
  static var _ADD_MAT: CanvasItemMaterial = _make_add_mat()  # blend_mode = BLEND_MODE_ADD
  ```
  Pass a flag through `spawn_burst` (e.g. `additive: bool = true` for energy, `false` for smoke/debris-dust).

### 0.3 — Pass `antialiased = true` on every line/polyline/arc/circle draw call.
Grep confirms **`antialiased` appears in zero combat scripts.** MSAA 2D is already at 4× (`msaa_2d=2` is the 4× enum), which helps polygon fills, but thin primitives — lance lines, lightning forks, magic-circle ticks/spokes, shockwave arcs, meteor trails — look visibly cleaner with the per-primitive AA feather on top of MSAA. In Godot 4.6 `draw_line`, `draw_polyline`, `draw_arc`, and `draw_circle` all accept a trailing `antialiased` arg. This is a cheap, mechanical, repo-wide sweep. (`draw_colored_polygon` has no AA arg — those keep relying on MSAA 4×, which is fine for the wide soft bands; for a crisp bright band edge, replace the polygon with a thick `antialiased` `draw_line`, see §Beam.)

### 0.4 — Pool / cache particle materials in `CombatVfx`. Removes per-cast GC churn.
`spawn_burst` allocates a fresh `ParticleProcessMaterial` + `Gradient` + `GradientTexture1D` + `GPUParticles2D` **every call**. A meteor shower alone fires 10+ bursts; blasts/novas/beam impacts add more. See §CombatVfx for the caching recipe. The soft-dot texture (0.2) must be a shared static, never regenerated.

---

## 1. `Spell.gd` + `SpellBoltVisual.gd` — the basic auto-aimed bolt

### Current state
A straight Area2D projectile with a procedural `_draw()` visual: tapering trail capsules + warm glow capsule + hot core lozenge + white tip, plus a `Trail` GPUParticles2D and an impact burst via `CombatVfx`. Element tint flows through `set_element_color()` → `SpellBoltVisual.set_tint()` (steers glow/trail fully to element, nudges core 25%) and duplicates the trail particle material per-instance. Solid architecture. On hit: SFX + `hit_stop(0.045)` + `shake_camera(6)` + 28-particle burst + knockback.

**Visual weaknesses**
- `_draw_capsule` uses `draw_line`/`draw_circle` with **no `antialiased`** → the bolt body edges shimmer, especially at small size (`CORE_HALF_WIDTH 2.4`).
- Core/glow are alpha-blended, so with no bloom the "white-hot core" is a flat lozenge, not luminous. This is the spell the player sees most — it should sparkle.
- Trail is only 4 discrete capsule segments with a gap (`TRAIL_SPACING 5.0`) → reads as a dashed tail, not a smooth streak, at speed 460.
- Flicker is `0.9 + 0.1*sin(phase*40)` — a barely-visible brightness wobble; doesn't add much.

### Visual improvements
1. `_draw_capsule`: add `antialiased=true` to the `draw_line` and `filled` circles (§0.3).
2. Push the core + tip into HDR once bloom lands (§0.1): `CORE_COLOR → Color(1.5,1.45,1.2)`, `TIP_COLOR → Color(1.7,1.7,1.7)`. The bolt then blooms a soft halo for free and the element glow reads.
3. Give `SpellBoltVisual` an additive `CanvasItemMaterial` (set in `_ready`/scene) so glow+core+tip layer to white-hot at the head.
4. Smooth the trail: raise `TRAIL_SEGMENTS` to 6 and overlap them (`TRAIL_SPACING ≈ CORE_HALF_LEN*0.8`) so it's a continuous taper, or replace the discrete capsules with a single `draw_polyline` of ~6 points from tail→head with decreasing width isn't possible (polyline is constant width) — keep capsules but overlap them and AA them.
5. Lean on the existing `Trail` GPUParticles2D more (soft-dot texture from §0.2 makes it a gorgeous ember streak) and make the drawn trail subtler — two systems doing the same job currently fight.
6. Impact burst (`_spawn_impact_burst`, 28 particles): with the soft dot + additive it becomes a proper spark pop. Add 4–6 fast **directional** sparks along `_dir` (Stick-Fight bullet-impact recipe) by spawning a second small burst with reduced `spread` — see §CombatVfx for a `direction`/`spread` param.

### Optimisation
- `SpellBoltVisual._process` calls `queue_redraw()` **every frame** purely to animate a ±10% flicker. With many bolts airborne this is N redraws/frame for a near-invisible effect. Either drop the per-frame flicker (redraw only when tint changes) or gate it (`if Engine.get_frames_drawn() % 2`). Low risk, real savings in bullet-heavy fights.
- `set_element_color` duplicates the trail `ParticleProcessMaterial` per bolt (necessary for per-instance tint) — fine, but cache the `Gradient`/`GradientTexture1D` construction pattern (§0.4).
- `_resolve_segment` does a raycast every physics frame per bolt — correct and necessary (anti-tunnel); leave it.

---

## 2. `BeamSpell.gd` — Zoltraak sigil beam (fire-dragons / frost-lens / holy / arcane)

### Current state
The most elaborate spectacle: charge (0.34s) with a `MagicCircle` edge-on gate + gather particles, then a screen-crossing layered beam (soft glow → body → hot core bands) for 0.26s, then fade. Fire skin draws two serpentine dragon polylines; frost adds a hexagonal muzzle lens + crystalline shards; holy adds a feathery halo + motes; arcane draws pulsing arcs. Heavy juice on discharge (hitstop 0.09, shake 16, zoom-punch). Damage is a clean geometric line test. Genuinely impressive; the issues are all crispness/timing polish.

**Visual weaknesses**
- The beam bands are `draw_colored_polygon` **rectangles** (`_draw_beam_band`). The long edges are axis-diagonal and, for the narrow bright core band, alias against the background even at MSAA 4×. Rectangular caps also make the beam look like a flat ribbon, not a round-profile energy bolt.
- No additive blending: the 4 stacked translucent bands **average toward the base colour** instead of building a luminous core. A "white-hot core inside element glow" needs additive to actually look white-hot.
- Every garnish (`_draw_effect_detail`, dragons, lens, arcs, forks) is a non-AA `draw_line`/`draw_polyline`/`draw_colored_polygon` → the fine detail (frost shards, dragon spines, arcane spoke-lines) shimmers.
- `intensity` "snap up" is good, but the fade is linear; a beam should decay with an ease-out flicker-off, not a straight ramp.
- Frost "shards" and arcane "arcs" are drawn with hard triangles/thin lines that look geometric/wireframe rather than crystalline/energetic.

### Visual improvements
1. **Replace `_draw_beam_band` rectangles with thick antialiased lines.** `draw_line(a, b, col, thick, true)` gives a smooth capsule with round caps and AA edges — a rounder, cleaner beam profile than a polygon rectangle, and it AAs for free:
   ```gdscript
   func _draw_beam_band(a: Vector2, b: Vector2, thick: float, col: Color) -> void:
       draw_line(a, b, col, thick, true)   # AA capsule, round caps
   ```
2. **Additive material** on the BeamSpell node (energy/light) so the wide-soft → body → core stack blooms to white at the centre line. With HDR (§0.1) push `_effect_core_color()` fire/holy/arcane cores above 1.0.
3. AA sweep (§0.3) on the dragon polylines, frost shards' outlines, holy motes, arcane arcs/spokes, muzzle/tip flash circles.
4. Fire dragons: they're the standout — add a soft additive under-glow polyline (already have 3 width tiers) and let the HDR core bloom; the dragon heads (`draw_circle`) become little suns.
5. Frost shards: draw them as thin AA lines radiating + a small bright tip circle instead of flat triangles, so they read as sharp icicles catching light rather than paper cutouts. Keep them steady (frost flicker already 1.0 — good, cold = still).
6. Timing: extend `FADE_TIME` slightly (0.22→0.28) and ease the fade (`intensity = pow(1.0 - x, 1.6)`) so the beam lingers and dims like cooling plasma rather than blinking off.

### Optimisation
- `_draw()` runs a lot of primitives per frame while firing (dragons = 14-seg polylines ×3 tiers ×2 + scales/forks). It's one short-lived node, so acceptable, but the AA lines are marginally more expensive — fine at this scale (a beam is not spammed).
- `_charge_burst` / `_impact_burst` allocate CombatVfx bursts — routes through §0.4 caching.
- No unbounded loops; `targets_on_beam` is O(n) over the enemy group, called once. Good.

---

## 3. `DivineRay.gd` — Judgment pillar (holy / frost / fire / arcane)

### Current state
Sky `MagicCircle` + growing ground danger-ring telegraph (0.42s), then a vertical column of light (soft → body → core `_draw_column` polygons) held 0.18s and faded 0.30s, with per-effect garnish, a ground flash disc + expanding ring. Radius damage, heavy juice. Reads as a clean single-target smite.

**Visual weaknesses**
- Same as Beam: `_draw_column` is a `draw_colored_polygon` rectangle → the two vertical edges of the bright narrow core alias, and the pillar looks like a flat bar rather than a shaft of light with soft falloff across its width.
- No additive → the pillar doesn't feel radiant; holy especially should blow out to white at the core.
- The ground `draw_arc` ring and telegraph arc are non-AA.
- The pillar has uniform width top-to-bottom; real light shafts are slightly wider/brighter where they hit and taper up. Minor.

### Visual improvements
1. Keep `_draw_column` polygons for the wide **soft** outer bands (cheap, low-alpha, MSAA is fine there) but draw the **bright core** as a thick AA `draw_line(sky, ground, core, w*0.4, true)` so its edges are clean and it has soft round ends.
2. Additive material on the node; push holy/arcane core to HDR (§0.1) → the pillar blooms into the sky sigil beautifully.
3. Add a subtle **width gradient**: draw 2–3 core segments from sky→ground with slightly increasing alpha/width toward the ground impact, so the base flares. Cheap, sells the "slam."
4. AA the telegraph ring, the ground flash `draw_arc`, and the frost/fire/holy garnish (§0.3).
5. Ground impact: on `_smite`, in addition to the burst, drop a brief **radial ground-flash decal** (bright disc that fades in 0.15s) so the moment of contact pops — currently the flash is a single `draw_circle` that fades with the pillar.

### Optimisation
- Clean. One node, short-lived, O(n) radius query once. Route bursts through §0.4. `_process` redraws every frame (needed while animating). No issues.

---

## 4. `MeteorSigil.gd` — meteor barrage (fire / frost / arcane / holy)

### Current state
Sky sigil (0.5s) then 10 staggered meteors over 1.15s, each a `draw_line` trail + halo/head/core circles, detonating with a radius burst + `shake_camera(5)` + SFX + scorch/crack decal + debris. Staggered spawn reads as a shower. Good silhouette.

**Visual weaknesses**
- Each meteor trail is a **single straight `draw_line(trail, pos, col, 10.0)` with no AA** → a fat hard-edged bar, the blockiest-looking element in the kit. Ten of them at once = ten aliased bars.
- The trail is a hard-cut segment (from `f-0.38` to `f`), not a smooth fading streak — it pops in/out length rather than tapering.
- Head is `draw_circle` (round, ok) but non-AA rim; the "hot core" circle is tiny (4.5px) and won't read as incandescent without bloom.
- No motion blur / no per-meteor light — a fiery meteor should glow. Currently all glow is a flat 0.4-alpha halo circle.

### Visual improvements
1. Trail → **antialiased tapered streak.** Replace the single fat `draw_line` with a short multi-point `draw_polyline([...], col, width, true)` (4–5 points from `trail`→`pos`) or, simplest, two AA `draw_line`s (wide soft + thin bright) both with `antialiased=true`. Widen the trail sampling window slightly (`f-0.5`) so it streaks.
2. Additive on the sigil node → meteor heads + trails glow and overlap into a fiery rain. Push head core to HDR (§0.1) so each meteor is a little sun with a bloom tail.
3. Add a faint **per-meteor drawn glow** growing as it nears the ground (scale the halo with `f`) so impact feels like arrival, not a static dot.
4. AA the head/halo/core circles and the telegraph ring (§0.3).
5. Stagger the **impact flash**: on `_land`, add a quick bright `CombatVfx` mini-flash (soft dot, additive, ~6 particles, high velocity) on top of the existing debris/scorch so each hit punches.

### Optimisation
- `_process` iterates `_meteors` twice per frame (land check + draw). Fine at count 10; if `DEFAULT_COUNT` ever scales up, merge into one loop.
- 10 `CombatVfx.spawn_burst` calls across the barrage = 10 fresh materials/textures without §0.4 caching — this is the **most alloc-heavy single spell**; prioritise it for the pooled-material path.
- `shake_camera(5)` per meteor ×10 over 1.15s can stack into a long rumble — intentional-ish, but consider scaling trauma down per-meteor (e.g. 3–4) and letting the climax meteors (last 2–3) shake harder for a build.

---

## 5. `StarConvergence.gd` — Heaven's Verdict (radial lance convergence + nova)

### Current state
Longest telegraph in the kit: sky sigil + ground ring + 8 poised lance markers (0.55s), lances streak inward accelerating (`f*f`) for 0.55s, then a nova flash + two expanding shockwave `draw_arc` rings (0.12s hold, 0.45s fade). Biggest damage + biggest juice (hitstop 0.14, shake 24, zoom-punch). The finisher.

**Visual weaknesses**
- Lances are `draw_line(tail, head, col, 9.0)` + a thin bright core `draw_line(…, 3.5)` — **no AA** → 8 aliased streaks converging, the moment that should look most epic.
- Convergence has no trail persistence; each lance is a single segment that shrinks — no sense of a searing streak. Adding a faint lag streak would help.
- Nova impact is two `draw_arc` rings + two flash circles — clean but flat without additive/bloom; the "cataclysmic" payoff currently looks similar in luminosity to the smaller nova/blast.
- Impact burst is a single 64-particle `CombatVfx` (good count) but squares (until §0.2).

### Visual improvements
1. AA all lance lines, the point-brighten circle, the charge markers, and both shockwave `draw_arc` rings (§0.3).
2. Additive node material + HDR cores (§0.1): the 8 lances slamming into one point should **blow the centre out to pure white** as they converge — additive makes overlapping lance heads at the point sum to incandescent. This is the single biggest upgrade for the finisher's impact.
3. Lance streaks: give each lance a short tapering tail by drawing a 3-point AA polyline (start-lagged head → head) instead of a fixed `tail=eased-0.28` segment, and brighten as `eased→1` so they sear inward.
4. Nova payoff: add a third, larger, faster shockwave ring and a **bright full-screen-ish flash** (a big low-alpha additive disc, 0.08s) at detonation so the finisher visibly out-punches Blast/Nova. Pair with the existing `zoom_punch`.
5. Consider a brief **radial motion-streak burst** (CombatVfx with low spread aligned outward) at detonation for the "shockwave debris" read.

### Optimisation
- Clean and bounded (8 lances, 2 rings). One-off node. Route the impact burst through §0.4. No concerns.

---

## 6. `LightningRush.gd` — Chidori / Thunderclap

### Current state
Snappy charge (0.16s) → jagged lightning lance (`_jag` tapered noise, 12 segments) at full for 0.10s → 0.30s crackle fade, plus mid-bolt forks and a chain-arc to a straggler. Heavy juice + music duck. Per-frame `_flick_seed` re-jitter reads as crackle. Best-feeling of the line spells conceptually.

**Visual weaknesses**
- The bolt is 3 stacked `draw_polyline`s (glow/body/core) + fork `draw_line`s + flash circles — **all non-AA.** Lightning is the effect where hard aliased edges hurt most: jagged thin lines against a dark arena shimmer badly.
- No additive → the white-hot core doesn't blow out; lightning should be the brightest thing on screen for its 0.1s.
- Forks are single thin `draw_line`s that pop each frame; with AA + additive they'd read as branching arcs.
- The chain-arc jitter is a fixed 6-point polyline — fine, just non-AA.

### Visual improvements
1. AA sweep on all three body polylines, the forks, the chain-arc polylines, and the muzzle/tip circles (§0.3). **Highest-impact AA target in the kit** — lightning benefits most.
2. Additive node material + HDR core (`CORE_COLOR → Color(1.7,1.75,1.9)`, §0.1) so the strike blows out to white and blooms a halo — instantly reads as a real thunderclap.
3. Add a second, offset jag polyline per frame at low alpha (a "ghost" bolt) so the arc has volume/branch density rather than a single ribbon.
4. Muzzle + tip: with additive + bloom the existing flash circles become brilliant nodes; bump their alpha slightly.
5. Keep the fast `_flick_seed` re-jitter — it's the soul of the effect — but see optimisation.

### Optimisation
- `_process` sets `queue_redraw()` every frame (correct — the jitter animates). Bolt lives only ~0.56s total, so fine.
- `_jag` and the draw loop rebuild the `PackedVector2Array` every frame — unavoidable for crackle, and only 12 segments. No concern.
- `_resolve_chain` is O(n) over enemies once at discharge. Good.

---

## 7. `BlastSpell.gd` — giant blast / fist-shock / ground-slam

### Current state
Telegraph bloom (0.55s windup via `Telegraph`) → radius detonation: 90-particle burst, expanding shockwave (2 `draw_arc` rings + hot flash circle over 0.25s), floor scorch decal + 12 debris chunks (floor-snapped via raycast), heavy juice (hitstop 0.09, shake 12, zoom-punch + zoom-pull), music duck. The AoE centrepiece. Well-built, floor-aware.

**Visual weaknesses**
- Shockwave rings (`draw_arc`) are non-AA → the signature expanding ring shimmers as it grows.
- The 90-particle burst is squares (until §0.2) — this is the biggest single burst count, so the blocky look is most visible here.
- The flash core is a flat alpha disc; without bloom the "detonation" doesn't blow out.
- Only one ring pair — a big blast wants a fast inner ring + a slower outer ring for depth.

### Visual improvements
1. AA both shockwave `draw_arc` rings and the flash `draw_circle` (§0.3).
2. Soft-dot + additive burst (§0.2): 90 soft additive embers = a proper fireball instead of orange squares. Re-tune scale down.
3. HDR flash (§0.1): `Color(1.6,1.4,0.9)` core → blooms the detonation.
4. Add a **second faster shockwave ring** (starts smaller, races ahead) and a thin bright leading edge on the main ring for a crisp "wave."
5. The debris + scorch already give great permanence (per the study's "permanence" principle) — keep. Consider a brief lingering smoke puff (CombatVfx, low velocity, grey, non-additive, 1–1.5s life) rising from the crater for Stick-Fight "smoke lingers" permanence.

### Optimisation
- 90 particles + material/texture alloc per blast → §0.2 shared texture + §0.4 material cache matters here.
- `_floor_below` raycast once per detonation — fine.
- `_apply_blast_damage` loops enemies + destructibles + (hero blast) enemy_projectiles — all O(n) once. Good.

---

## 8. `EnergyNova.gd` — self-centred "get off me" nova

### Current state
Instant (no windup) cyan-white shockwave from the hero: 110-particle burst, 2 expanding energy `draw_arc` rings + white-blue flash over 0.32s, floor crack decal + 8 debris, heavy juice. Cool palette deliberately distinct from the warm blast. Mirrors BlastSpell structure.

**Visual weaknesses**
- Identical class of issues to Blast: non-AA rings, square particles (110 of them — the highest count in the kit → most visible blockiness), flat flash disc without bloom.
- Because it's instant and self-centred it fires under the hero constantly in panic moments — the square-particle look is on screen a lot.

### Visual improvements
1. AA the two ring `draw_arc`s + flash circle (§0.3).
2. Soft-dot + additive burst (§0.2) with the cool cyan gradient → a clean energy ring-out. This one *especially* benefits: additive cyan-white over a dark arena is gorgeous and reads instantly as "force push."
3. HDR flash core (`Color(1.3,1.5,1.8)`, §0.1) → the nova blooms outward.
4. Add a thin ultra-bright leading ring edge (AA `draw_arc`, high alpha, width 2) racing at the wavefront so the push has a crisp boundary — sells the "shove."

### Optimisation
- 110 particles is the single largest allocation event — §0.2/§0.4 caching is most impactful here. Consider dropping to ~80 once they're soft additive dots (soft dots read as denser than squares, so you need fewer).
- Otherwise clean; O(n) queries once.

---

## 9. `MagicCircle.gd` — shared arcane sigil (face-on portal + edge-on gate)

### Current state
The most detailed procedural art in the project: face-on mode (pulse rings, spinning outer/dashed/tick rings, counter-rotating spokes, hexagram over square, orbiting motes, breathing core) and edge-on mode (nested ellipses, foreshortened rim glyphs, runic ticks, bright central aperture). Grows in, spins/breathes, blooms out. Reused by every spectacle. Beautiful concept.

**Visual weaknesses**
- **Everything is non-AA** — dozens of thin `draw_arc`/`draw_line`/`draw_polyline` primitives (rings, ticks, spokes, stars, dashed ring, glyphs). At the small-ish radii and thin widths (1.5–3.5px) these are the most AA-starved shapes in the game; the fine runic detail shimmers/crawls as the sigil spins. This is the effect where AA matters *most* and is currently absent everywhere.
- No additive/bloom → the "hot core" and "bright aperture" are flat; a summoning sigil should glow.
- `draw_set_transform` is used for rotation (good) but stacked layers of thin alpha lines without bloom muddy into a busy tangle rather than a luminous seal.

### Visual improvements
1. **AA sweep is the priority here** (§0.3): every `draw_arc`, `draw_line`, `draw_polyline`, `_draw_star`, `_draw_dashed_ring`, `_ellipse_pts` polyline, and the mote/core `draw_circle`s. This single file has the highest count of thin primitives → biggest crispness payoff per edit.
2. Additive material on the MagicCircle node + HDR core/aperture (§0.1): the summoning ring blooms, the aperture becomes a genuine slit of light, and the whole sigil reads as *projected light* rather than *drawn lines*.
3. Because it now blooms, you can slightly **reduce line density/alpha** (fewer competing thin strokes) and let glow carry the richness — cleaner + cheaper.
4. Optional: give the outer ring a subtle colour-gradient stroke by drawing two offset arcs (element + white) for a chromatic edge.

### Optimisation
- `_draw_face`/`_draw_edge` issue a large number of draw primitives per frame while a spectacle is active. Usually only 1 sigil exists at a time, so acceptable, but: the pulse rings + ticks + spokes + hexagram + square + motes is a lot. If profiling shows cost, reduce `TICKS` (28) / `DASH_SEGMENTS` (22) / mote counts, or bake the static rings once to a `Texture`/`Line2D` and only animate the spinning layers.
- `_process` redraws every frame (needed — it spins). Fine for a single instance.

---

## 10. `CombatVfx.gd` — shared particle burst builder

### Current state
One static `spawn_burst()` builds a self-freeing one-shot `GPUParticles2D` with a fresh `ParticleProcessMaterial` + `Gradient` + `GradientTexture1D` each call, radial `spread=180`, tunable count/lifetime/velocity/scale/damping. Auto-frees via a timer. Clean, well-factored — but it's the root cause of the two biggest kit-wide problems.

**Weaknesses**
- **No `texture`** → every particle is a hard square (§0.2). This is *the* pixelation source across all spells.
- **No blend control** → energy bursts can't glow additively (§0.2).
- **Per-call allocation** of material + gradient + texture + node (§0.4) → GC churn, worst on meteor/blast/nova.
- No directional option → all bursts are 360° radial; bullet-impact "sparks along the hit direction" (study §4) isn't expressible.

### Improvements (this is the highest-leverage single file)
1. **Shared soft-dot texture** (static, cached) assigned to `burst.texture` (§0.2). One change → every spell stops looking blocky.
2. **Additive flag**: `additive: bool = true` param → assign a cached additive `CanvasItemMaterial` for energy bursts, none (alpha) for smoke/dust. (Debris chunks are separate — `DebrisChunk`.)
3. **Material cache**: key a small `Dictionary` by the tuning tuple (or at least reuse the additive material + soft dot; the `ParticleProcessMaterial` can be duplicated from a template and only its `color_ramp` + velocity/scale set, avoiding rebuilding the gradient texture when colours repeat). Even caching just the texture + additive material removes most of the churn.
4. **Optional direction/spread params** (`dir: Vector2`, `spread_deg: float`) so callers can emit focused spark cones (bolt impacts, blast leading edge). Defaults keep the current 180° radial behaviour.
5. Consider a tiny **pool** of `GPUParticles2D` nodes reused across bursts (reset + restart) to avoid node create/free per hit in bullet-heavy fights — medium effort, do only if profiling shows node churn.

---

## 11. `Elements.gd` — 8-element colour/identity + how tints flow

### Current state
Static `color(e)` / `display_name(e)` / `count()` for FIRE, ICE, LIGHTNING, SHADOW, ARCANE, EARTH, HOLY, WIND. Colours are reasonable and saturated. Tints flow outward: the element colour is passed into each spell (`set_element_color`, `fire(...,color,...)`, `strike(...,color,...)`, etc.), which recolours glow/trail/bands and the `MagicCircle`, while cores stay near-white per-effect. Good separation (element ≠ body colourway).

**Weaknesses**
- Colours are all LDR (≤1.0) and fairly mid-value. `SHADOW` (0.6,0.35,0.9) and `EARTH` (0.78,0.55,0.28) are darker/desaturated → against a dark arena they read muddier than FIRE/HOLY. Without bloom, the darker elements' spells look flatter.
- The `_effect` string ("fire"/"frost"/"holy"/"arcane") that drives particle *character* in the spectacles is decoupled from the 8-element enum — SHADOW/EARTH/WIND/LIGHTNING fall through to the default/arcane character. So a Shadow beam gets arcane garnish tinted violet, not a bespoke shadow language. Readability gap, not a bug.

### Improvements
1. Add an **HDR-friendly "core/emissive" companion** per element (a brighter >1.0 variant) once bloom lands (§0.1), so `SHADOW`/`EARTH` spells still bloom a bright core and don't read muddy. E.g. `emissive(e)` returning the color scaled to peak ~1.6–1.8 for the core band.
2. Map each of the 8 elements to an `_effect` **character** string (e.g. EARTH→a new "earth" = dusty chunky debris + amber; WIND→"wind" = fast wispy motes + teal; SHADOW→"shadow" = inky particles that fade to violet) so every element reads distinctly in the spectacles, not just the four that have skins today. Medium effort per new character; can be staged.
3. Slightly lift `SHADOW`/`EARTH` value/saturation, or rely on the emissive core so they pop.

### Optimisation
- Pure static match lookups, called rarely (on cast). Zero concern. (If ever hot, a `const` colour array indexed by enum avoids the `match`, but it's irrelevant here.)

---

## Ranked "do-first" list (highest impact / lowest risk first)

| # | Change | Files | Why (impact) | Risk |
|---|--------|-------|--------------|------|
| **1** | **Soft round particle texture** (shared static dot) assigned in `spawn_burst` | `CombatVfx.gd` | Kills the "blocky/pixelated confetti" look across **every** spell in one edit. The biggest single visual win. | Low — one function; re-tune `scale_min/max` down. |
| **2** | **`antialiased = true` sweep** on all `draw_line`/`draw_polyline`/`draw_arc`/`draw_circle` | all spell files + `MagicCircle.gd`, `SpellBoltVisual.gd` | Removes shimmer on lances, lightning, forks, sigil ticks, shockwave rings, beams. Cheap, mechanical, huge crispness gain. | Very low — additive arg, no logic change. |
| **3** | **HDR 2D + WorldEnvironment glow (bloom)** + push cores >1.0 | project settings + Arena scenes; then per-spell core colours | Turns flat white cores into genuinely radiant, blooming energy — the "beautiful/premium" lever. Also unlocks re-enabling the hero aura. | Low–med — global setting; tune glow threshold so it doesn't over-bloom UI. |
| **4** | **Additive blend for energy bursts + beam/ray/nova/lightning/sigil nodes** | `CombatVfx.gd` (flag) + spectacle node materials | Overlapping bands/motes build to white-hot instead of muddy grey; pairs with #3. | Low–med — must exclude smoke/debris/scorch from additive. |
| **5** | **Replace beam/pillar `draw_colored_polygon` bands with thick AA `draw_line`s** | `BeamSpell.gd`, `DivineRay.gd` | Round-profile, clean-edged beams/pillars instead of aliased flat ribbons. | Low — swap helper body. |
| **6** | **Meteor + Blast + Nova burst/ring polish** (AA rings, additive soft dots, HDR flash, extra shockwave ring) | `MeteorSigil.gd`, `BlastSpell.gd`, `EnergyNova.gd` | The three highest particle-count spells → most visible pixelation today; also the most-seen AoEs. | Low — visual only. |
| **7** | **`CombatVfx` material/texture caching (+ optional node pool)** | `CombatVfx.gd` | Removes per-cast `ParticleProcessMaterial`/`Gradient`/`GradientTexture1D` allocation; worst on meteor showers, blast, nova. | Med — cache invalidation care; behaviour-preserving. |
| **8** | **Smooth the basic bolt trail + drop its per-frame flicker redraw** | `SpellBoltVisual.gd` | Continuous streak instead of dashed tail; removes N redraws/frame for a near-invisible flicker in bullet-heavy fights. | Low. |
| **9** | **Meteor trail → antialiased tapered streak** (kill the fat hard `draw_line`) | `MeteorSigil.gd` | The single blockiest-looking primitive in the kit; ×10 on screen. | Low. |
| **10** | **StarConvergence finisher payoff** (additive lance convergence blow-out + bigger flash/3rd ring) | `StarConvergence.gd` | Makes the ultimate visibly out-punch the smaller AoEs. | Low. |
| **11** | **Element emissive/core companions + map 8 elements to particle characters** | `Elements.gd` (+ spectacle `_effect` maps) | SHADOW/EARTH/WIND stop reading muddy; every element becomes distinct in spectacles. | Med — new particle skins are per-element work; stageable. |
| **12** | **Timing/easing pass** (ease-out fades on beam/ray/nova; per-meteor shake build; lingering blast smoke) | beam/ray/nova/meteor/blast | Effects cool/decay instead of blinking off; permanence per the study. | Low. |

**Meta:** Items **1–4 are the backbone** — a soft-dot texture, an AA sweep, bloom, and additive blending will move the entire kit from "reads as pixelated flat shapes" to "crisp glowing energy" before any per-spell tuning. Everything below #4 is refinement on top of that foundation. All are independently shippable and low-risk; none touch damage/geometry logic (the pure `targets_*` tests stay green).
