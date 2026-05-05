# Art & Audio Direction

## Visual style

**2D pixel art.** Top-down 3/4 perspective.

**Tonal direction:** atmospheric mystery with light isekai/fantasy texture. Friendly enough on the surface; deeper weirdness underneath. Cozy in towns; ominous in deep regions; surreal in the upper Tower.

**Reference north star:** TBD — to be locked before serious art production begins (Tier 2). Spectrum:

- **Stardew Valley** — cozy, warm, simple, readable.
- **Eastward** — atmospheric, cinematic, painterly.
- **Octopath Traveler** (HD-2D) — painterly, lit, more modern.
- **Terraria** — busy, detailed, maximalist.
- **Hyper Light Drifter** — moody, neon, sparse.

For Legacy Frontier, target somewhere between **Eastward and Stardew** — atmospheric and warm enough to be inviting, detailed enough to support depth, dark enough to support the Tower's mystery.

---

## Pixel art pipeline (layered + AI-assisted)

The architecture decision: **handcrafted anchor library + procedural variation + AI-assisted asset creation**, all baked offline. No runtime AI sprite generation.

### Layer 1 — Anchor library (handcrafted)

A small set of hand-authored or carefully-cleaned sprites that define the game's visual DNA. Maybe 50–100 sprites total at v0.0:

- 4–6 character body shapes (heights, builds)
- 6–10 head/face shapes
- A handful of anchor outfits (for vibe)
- 5–10 anchor monster forms
- 20–30 anchor environment tiles

These are the *style bible*. Everything else must visually match.

### Layer 2 — Variation system (procedural)

Layered sprite system in Godot:

- Body + outfit + hair + accessory + weapon as separate sprite layers
- Per-layer palette swaps for colour variants
- Mix and match generates thousands of unique-looking characters from a small library

Implementation: modular `Node2D` with stacked `Sprite2D` children, each driven by character data.

### Layer 3 — AI-assisted asset creation (offline pipeline)

Python scripts using Stable Diffusion (or PixelLab API, or similar) to generate *new* assets:

- New outfit variations
- Monster types
- Accessories
- Environmental tiles
- Item icons (the 50+ icons we'd otherwise hand-pixel for weeks)

**Workflow:** generate ~20 variations → pick best → clean up in Aseprite → match palette → add to library → commit.

**Style consistency:** train a custom LoRA on the anchor library so AI generations stay on-brand. The pipeline becomes its own piece of content (*"watch me train an AI to generate Legacy Frontier monsters"* is a videoable story).

### Why this architecture

- **Style consistency:** humans set the style, AI scales it
- **Performance:** runtime is 100% pre-baked sprites. Fast, predictable, no inference cost during play
- **Quality control:** every sprite gets human review before it ships
- **Avoids the trap:** runtime AI sprite generation breaks visual consistency and produces weird artifacts

---

## Tools and resources

### AI sprite generators
- **PixelLab.ai** — purpose-built for game devs (sprites, animations, multi-direction rotations, tilesets); likely best fit
- **Sprite-AI** (sprite-ai.art) — exact pixel sizing, built-in pixel editor, sprite sheets
- **Pixie.haus** — true 1:1 grid snapping, image-to-image consistency
- **Stable Diffusion + pixel-art LoRAs** — DIY route; max control with custom LoRA training

### Pixel editors
- **Aseprite** (~$20) — industry standard
- **LibreSprite** — free open-source fork, fully usable

### Asset libraries (for tilesets, characters, props — placeholder and reference)
- **itch.io game assets** — biggest marketplace; search tags `pixel-art`, `top-down`, `RPG`, `Godot`
- **Kenney.nl** — free CC0, prototyping gold
- **OpenGameArt.org** — free, mixed quality, search-heavy
- **Topdown Pixelart Starter Project** for Godot — free MIT-licensed template with 2 levels, quests, combat, talking NPCs (great reference for v0.0)

### Notable artists on itch.io worth knowing
- LimeZu — high-quality 16×16 RPG tilesets
- HoriHoriPixel — character / background / portrait packs
- Penzilla — characters and portraits
- Cup Nooble — fantasy outdoor / dungeon tilesets

---

## Audio direction

### Music brief

**Atmospheric melancholy fantasy with hypnotic, time-soaked textures.**

Reference tracks the user has flagged:
- *Time Flows Ever Onward* (the FF7 piano arrangement vibe)
- *Golden Brown* by The Stranglers

Adjacent territory:
- Joe Hisaishi (Howl's Moving Castle, Spirited Away)
- Christopher Larkin (Hollow Knight)
- Andrew Prahlow (Outer Wilds)
- Austin Wintory (Journey)
- Spiritfarer score (Max LL)
- Hades' more contemplative tracks

**Instrumentation cues:** harp, acoustic guitar, sparse piano, soft strings, occasional choir, ambient pads. Avoid: epic orchestral bombast, chiptune, electronic dance.

**Adaptive music:** tracks shift based on biome, time of day, faction territory, combat state. Implementation deferred to Tier 5+; placeholder tracks earlier.

### Plan

- **Tier 1–4:** royalty-free placeholder music. Game vibe will read even with placeholders if other systems are tight.
- **Tier 5+:** commission an indie composer for the actual soundtrack.

### Royalty-free music libraries

- **Soundimage.org** (Eric Matyas) — gigantic free fantasy game music; tracks like *Some Dreamy Place*, *Fantascape*, *Magic Ocean* fit the brief
- **Tabletop Audio** — atmospheric ambient tracks made for tabletop RPGs; transfer perfectly to game backgrounds
- **WOW Sound** — 700+ loopable DMCA-safe tracks, commercial-use licensed
- **Dark Fantasy Studio** — royalty-free music packs across horror, epic, ambient, action
- **itch.io** music tag (free section) — many indie composers offering free or pay-what-you-want
- **Pixabay Music + Free Music Archive** — broad CC libraries, less curated

### Sound effects

- **Freesound.org** — Creative Commons SFX library
- **Kenney's audio packs** — free CC0
- **ZapSplat** — free with account
- Field recording where it makes sense (footsteps, ambient nature, etc.)

---

## UI design

- **Diegetic where possible.** Map screen feels like a cartographer's parchment. Inventory feels like a satchel. Health/stamina bars are subtle, not RPG-loud.
- **Minimal HUD.** Health and stamina bars only when relevant. Everything else is one tap/key away.
- **Mobile-first design language.** Big tap targets, no hover states. Keyboard/mouse adapts up from this baseline (reverse of the usual approach).
- **Typography:** consider an evocative pixel font with a clear secondary readable font for longer text.

---

## Style guide (to be developed)

A `style-guide.md` will live in `art-source/anchors/` once the anchor library exists. It'll document:

- Approved palette
- Sprite dimensions per category (16×16, 32×32, 48×48, etc.)
- Outline rules (yes/no, colour)
- Lighting direction
- Approved animation frame counts per action

For now: defer until Tier 1.5 when art production seriously begins.
