# Roadmap

How we get from zero to a shipped game. Each tier builds on the last. Don't think about Tier 4 while building Tier 1.

---

## MVP / Post-MVP boundary

Per the operating rules, we explicitly track what's IN the MVP versus what's POST-MVP.

**MVP (Minimum Viable / "MCP" — what we ship to prove the concept and unlock funding):**

- v0.0 → Tier 2 inclusive
- A small handcrafted region with: top-down 2D pixel-art world, 5–10 persistent AI NPCs with memory, action combat with at least 3 weapon types, 1 magic school, basic inventory and stats, 1 dungeon, 3–5 quests, save/load with NPC memory persistence, persistent avatar with Chronicle on return
- Single-player only at this stage
- This is what we pitch to publishers, run on Kickstarter, and demo on Steam Next Fest

**Post-MVP (everything beyond — the full game):**

- Tier 3+
- Procedural world generation, multiplayer, magic system depth, clans/PvP, world bosses, Twitch integration, polish, content scaling

---

## Sprint 0 — Learn Godot

**Goal:** the user becomes comfortable enough with Godot 4 and GDScript to build small things without copying tutorial code.

**Duration:** as long as it takes (typically 1–3 weeks of part-time learning).

**Tasks:**
1. Complete Godot's official "Your First 2D Game" tutorial (the dodge-the-creeps one).
2. Complete a top-down movement tutorial (Heartbeast or GDQuest).
3. Modify both: extend with a stationary NPC, a key-press dialogue print, simple collision detection. The act of *modifying* tutorials proves understanding.
4. Pull and explore the [Topdown Pixelart Starter Project](https://godotengine.org/asset-library/asset/2397) to see how a real Godot RPG is structured.

**Done when:** you can move a sprite, respond to input, change scenes, and load a tilemap without referencing tutorials.

**Content beats:** "Day 1 with Godot — what is this thing", "I built my first NPC", "Reading other people's Godot code so you don't have to."

---

## Tier 1 / v0.0 — The seed

**Goal:** prove the core magic. One NPC who genuinely remembers the player across save loads.

**Scope (very deliberately tiny):**

- One screen, one tilemap (placeholder art is fine).
- Player character with WASD movement, top-down 3/4 perspective.
- One NPC sprite standing in the world.
- Walk near + press E → dialogue UI opens.
- GDScript hits the local Ollama API with: NPC personality prompt + prior conversation history + player's input.
- LLM response streams into the dialogue UI.
- Conversation history persisted to a JSON file on disk.
- On next launch, history reloads; LLM receives it as context.
- **The NPC remembers.**

**Done when:** you can have a conversation with the NPC, quit the game, restart it, and the NPC references something specific you said last session unprompted.

**Content beat:** *"I made an NPC remember me — watch what happens when I quit and come back."* This is potentially the first viral video.

**Why this is the whole goal:** every layer that comes later (combat, party, multiplayer, magic) is just texture on top of *this*. If this moment doesn't feel magical, none of the rest matters.

---

## v0.5 — Two-anchor village (NPC depth before combat)

**Goal:** stop being *"a guy in a room who remembers"* and become *"a small village where two people remember the player and each other."* Per **D-038**, this cycle inserts ahead of Tier 1.5's combat work — NPC depth is the project's distinguishing pillar (D-002, D-007, D-020), and v0.5 directly seeds the patterns Tier 2 needs (consolidated memory, gossip propagation, behavioural state, broadcast reactions). Combat benefits from being designed against a richer NPC layer; ARPG combat against an NPC with mood and trust reads differently than combat against a stat block.

**Scope:**

- Second NPC (Mirelle) in a second handcrafted room, joined to v0.0's room by a 3-tile-wide connector. Per-room `Area2D` tracking via `current_room_id` for O(1) earshot determination.
- **Four-layer memory model** per `architecture.md`: persistent identity (`NPCData` resource) + long-term summary (LLM-generated paragraph, ≤80 words) + short-term transcript (raw role/content dicts since last consolidation) + relationship registry (per-entity valence + key_facts + gossip_inbox). Stored as per-NPC JSON under a `version: 2` schema.
- **LLM consolidation:** async on disengage when `short_term.size() >= 15`; parallel-sync on quit. Structured JSON via Ollama `format: "json"` with truncate-concat fallback.
- **Behavioural state** (D-040): mood (NPC-wide, persisted, LLM-updated) + per-entity valence (persisted, LLM-updated) + runtime-only patience (rule-based per turn). NL band words feed the LLM prompt; raw scalars never appear.
- **NPC-initiated farewell** via patience trigger (< 0.2) + D-037 regex on NPC reply.
- **Gossip propagation** rule-based: NPC A's consolidation emits `strong_facts_to_share`; engine writes them into target NPCs' inboxes after a friendship gate; receiving NPC's prompt includes `Recent rumours:` block; receiving consolidation marks `consumed_inbox_indices`.
- **Tier 0 ambient NPCs** in second room (3 archetypes — village child / grizzled local / passing trader). Canned greetings + classify-once-bucketed canned reactions. No LLM calls per ambient NPC.
- **Broadcast reactions:** Enter-keyed public speech → ambient NPCs canned-react, anchors LLM-react with shallow prompts (personality + state + valence only, no long_term/short_term/inbox). Overheard hostility halves anchor patience.
- **Token + engine efficiency** (D-045, 17 principles): KV-cache-stable prefix order, compact one-line relationship encoding, `keep_alive: "30m"`, parallel-quit consolidation, classify-once broadcast bucket, compile-once regexes, etc.

**Sequencing:** **M9 → M12 → M11 → M10 → M13 → M14.** Foundation first; second NPC immediately so all later state/consolidation work tests against TWO NPCs from the start.

**Done when:** the videoable beat lands — tell Raebai about heading to Coldrose, walk to Mirelle, she says *"heard you're off to Coldrose, love. Raebai's already told me half of it."*

**Effort:** 8–12 sessions / ~6–10 weeks of evening velocity per `docs/v0.5-design.md`.

**Content beat:** *"The world is bigger now — and they talk."*

**Decisions:** D-038 through D-045 (see `docs/decisions.md`). Full design spec at `docs/v0.5-design.md`; per-milestone implementation plans at `docs/v0.5-m9-plan.md`, `docs/v0.5-m12-plan.md` (additional plans authored as their milestones come up).

---

## Tier 1.5 — Core RPG primitives

**Goal:** stop being a chat-with-an-NPC demo and become a tiny RPG.

- Player stats (HP, stamina, base attributes).
- Inventory system (with a few starter items).
- Equipment slots and equipping/unequipping mechanic.
- Action combat: at least one melee weapon, one ranged, one spell.
- Basic enemy AI (a wandering monster with combat behaviour).
- Death and respawn (lose XP + durability).
- Skill-based progression: using a sword increases sword skill.
- Basic UI (HP bar, stamina bar, hotbar, inventory screen).

**Done when:** you can fight a monster with multiple weapon types, gain skill XP, die, respawn, and reload.

**Content beats:** combat reel, "first death", "the rat king" (your first miniboss).

---

## Tier 2 — A small living region (MCP target)

**Goal:** ship the playable vertical slice. This is the MCP.

- One handcrafted region: a town with surrounding wilderness and one dungeon.
- 5–10 NPCs with distinct personalities and routines (work, eat, sleep).
- LLM memory consolidation working (NPCs don't lose history over time).
- 3–5 quests: at least one NPC-needs quest, one board-posting quest, one world-event quest.
- One AI party member you can recruit who follows, fights, and converses.
- One small dungeon with a miniboss.
- NPC-to-NPC gossip propagation working (your reputation precedes you).
- Save/load fully persistent.
- Persistent avatar mechanic with Chronicle generation (still single-player; your character "lives" while game is closed).
- One magic school with 3–5 spells.

**Done when:** a playtester can spend 2–4 hours in the region, complete the quests, recruit the party member, beat the miniboss, and feel like they were inside a small *living* world.

**Content beats:** vertical slice trailer; first publisher pitches; Kickstarter prep; Steam page goes live with wishlist push.

**This is the unlock for the funding phase.**

---

## Tier 3 — World layer

**Goal:** the world stops being a single handcrafted region and becomes large.

- Procedural chunk-based world generation with multiple biomes.
- Day/night cycle with NPC routines tied to it.
- Hand-placed major settlements (towns) with procedural wilderness between them.
- Mounts (basic).
- Portal network at the Tower base for fast travel.
- Multiple dungeons procedurally generated from handcrafted templates.
- Faction reputation system fully working across multiple factions.
- 20+ NPCs across the world.
- 15+ quests.

---

## Tier 4 — Multiplayer foundation

**Goal:** ~15–20 players sharing a persistent world, with offline avatars.

- Server-authoritative architecture.
- Persistent shared world hosted on a server.
- Player accounts and authentication.
- Offline avatars persist server-side; world ticks even when no one's logged in.
- Friends list, party invites, chat (party / clan / proximity / global).
- Player trade.
- PvP zones designated; safe zones outside.
- Player housing in towns.

**Done when:** you can host an alpha event, 15 testers play together for a session, log out, return the next day, and find their avatars have meaningful Chronicles to read.

**This is the moment Legacy Frontier becomes the thing it's been promising.**

---

## Tier 5 — Magic depth

**Goal:** the magic system goes from "spells exist" to "magic is one of the central interesting things in the game."

- Multiple magic schools, each with unique spell families.
- Spell learning gated by NPC teachers, faction reputation, world discovery.
- Cultivation flavour: spells level through repeated casting.
- Magical orders as factions with quests, secrets, and politics.
- Spell crafting / combination at high mastery.

---

## Tier 6 — Bosses and content scaling

**Goal:** late-game content beats that anchor server identity.

- 5–7 named world bosses with deep lore and extreme difficulty.
- First-kill announcements and NPC gossip.
- Boss-specific drops and unique progression unlocks.
- Larger dungeon variety.
- Clan halls.

---

## Tier 7 — Twitch integration

**Goal:** the viewer-NPC mechanic ships.

- OAuth integration with Twitch.
- Viewer usernames spawn as NPCs in a streamer's session.
- NPCs persist server-side.
- Viewer-NPCs have configurable personalities (default templates; advanced customisation later).
- Optional: chat-driven events (low-impact only — chat votes on a lore choice the streamer faces).

**Content beat:** demo videos of streamer worlds being shaped by their audience. This is the marketing flywheel mechanic.

---

## Tier 8 — Public launch and polish

**Goal:** ship to Steam and wider audiences.

- Full polish pass (animation, sound, UI, performance).
- Tutorial and onboarding pass.
- Localisation (English first; community-translated others).
- Accessibility options.
- Steam page, trailer, marketing.
- Mobile launch (iOS, Android) with virtual joystick fully tuned.

---

## Tier 9+ — Live operations

- New Tower floors (each is a content drop).
- New magic schools.
- New world bosses.
- Seasonal events.
- Modding support (if community demands).
- Possibly: second world (parallel server with different seed and themes).

---

## Content beats per tier

A core principle: **every tier ships with one or more videoable moments.** Each is a content beat that drives the build-in-public flywheel.

| Tier | Content beat |
|------|--------------|
| Sprint 0 | Learning journey: *"I'm a Goldman analyst learning Godot"* |
| 1 / v0.0 | *"My NPC remembers me — watch this"* |
| v0.5 | *"The world is bigger now — and they talk"* |
| 1.5 | *"First combat, first death"* |
| 2 | *"A vertical slice — playable region demo"* |
| 3 | *"The world is huge now — exploration video"* |
| 4 | *"Multiplayer alpha — 15 players, persistent avatars"* |
| 5 | *"Magic is alive now — schools, cultivation, secrets"* |
| 6 | *"First world boss — server-wide announcement"* |
| 7 | *"Your name is in the game — viewer NPC reveal"* |
| 8 | Launch trailer |

See `content-strategy.md` for the build-in-public approach in detail.
