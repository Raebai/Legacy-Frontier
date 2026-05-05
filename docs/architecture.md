# Architecture

Technical architecture and the architectural rules that everything else must respect.

---

## Stack

### Game engine
- **Godot 4** (latest stable, non-.NET version)
- **GDScript** as primary language (Python-like syntax, transfers easily for a Python developer)
- Single codebase exports to Windows desktop and Android/iOS mobile

### AI runtime
- **Ollama** running locally
- **Llama 3.2 3B** as default NPC dialogue model
- HTTP API at `http://localhost:11434`
- Game makes HTTP calls from GDScript via `HTTPRequest` node

### Tooling
- **Python 3.11+** for asset pipelines, content generation, AI-assisted pixel art workflows, world-baking scripts, and dataset prep for NPC personalities
- **Aseprite** (paid) or **LibreSprite** (free) for pixel art editing
- **Stable Diffusion + pixel-art LoRAs** (via `diffusers` or `comfyui`) for AI-assisted asset generation in the offline pipeline

### Version control and hosting
- **Git** with GitHub
- Public repo (per build-in-public strategy) — secrets *must* be properly gitignored
- LFS for any binary assets large enough to warrant it

### Future (deferred until needed)
- **Multiplayer networking:** Godot's high-level multiplayer API for early iteration; possibly migrate to a custom server-authoritative architecture at Tier 4
- **Server hosting:** TBD — likely a small VPS for Tier 4 alpha, scale based on player count
- **Database:** SQLite (single-player), PostgreSQL (server-side persistent world)

---

## The AI architecture rule

This is the most important architectural rule in the project. Read it. Understand it. Defend it.

### LLM is for deliberate moments only

Llama 3.2 3B running locally takes 1–5 seconds per response on consumer NVIDIA GPUs. That is **fine** for dialogue (the NPC appears to be thinking) but would be **catastrophic** for combat, pathfinding, or background simulation.

**The LLM is called for:**
- NPC dialogue (when a player initiates conversation)
- Memory consolidation (periodic summarisation of an NPC's interaction history)
- Quest narrative generation (the *story* of a coded-mechanics quest)
- Big personality decisions (an NPC chooses to flee, betray, or confess — uncommon)
- Chronicle generation (when a player logs back in)

**The LLM is NEVER called for:**
- Combat decisions (NPC chooses to attack, dodge, retreat — pure rules)
- Pathfinding (Godot's navigation system handles this)
- Daily routine execution (state machines)
- Background world ticking (probabilistic event simulation)
- Stat calculations, damage rolls, probability checks (math, not language)
- Per-frame anything

If a feature seems to require LLM-per-frame, the design is wrong. Refactor.

### Memory architecture

Each NPC has a memory store with the following structure:

- **Persistent identity:** name, personality prompt, faction memberships, baseline goals (rarely changes)
- **Long-term memory:** consolidated summary of past interactions and significant events
- **Short-term memory:** raw transcript of recent interactions (last N turns)
- **Relationship registry:** `{other_entity_id: {valence: float, key_facts: [...]}}` mapping known people, places, and things to opinions

Memory lifecycle:

1. Player interacts with NPC → raw exchange appended to short-term memory.
2. After short-term memory exceeds size threshold (or on session end), an LLM call **consolidates** it: rewrites it as a compressed long-term summary, then clears short-term.
3. Consolidation also updates the relationship registry where relevant.
4. Future LLM calls receive: persistent identity + long-term summary + relevant relationship facts + recent short-term context. Total prompt stays bounded.

This is the bounded-context pattern. Without it, NPC prompts would grow forever and the game would become unplayable.

### NPC-to-NPC propagation

Memory propagation between NPCs ("gossip") is **not** an LLM call. It is a code-level event:

- When NPC A forms a strong opinion about the player, a "gossip event" is fired.
- Other NPCs in the same settlement, with friendship to NPC A, may receive the gossip when their routines bring them into contact with A.
- Receiving gossip writes a structured fact into the receiving NPC's relationship registry: *"NPC A told me the player did X."*
- The receiving NPC's *next* LLM-driven dialogue with the player can reference that fact naturally.

The propagation is rule-based; the *expression* of it is LLM-driven. This is the right division of labour.

---

## Persistence model

### Single-player (Tier 1–3)

- Save file = local SQLite database in user data directory
- Schema includes: world chunks, NPC state, NPC memory, player state, world clock, quest state, inventory, etc.
- Saves on demand and on quit; auto-saves periodically

### Multiplayer (Tier 4+)

- Server-authoritative
- World state lives on server (PostgreSQL or similar)
- Client holds only what it needs for rendering and input
- Offline avatars persist server-side; world tick runs on server even when a player is logged out

Avatar offline simulation runs as a **separate process** on the server, ticking at a slower rate than live play. Events are logged for Chronicle generation.

---

## Project structure (proposed)

```
legacy-frontier/
├── README.md
├── CLAUDE.md
├── .gitignore
├── .env.example
├── docs/
│   ├── vision.md
│   ├── design.md
│   ├── architecture.md
│   ├── art-and-audio.md
│   ├── roadmap.md
│   ├── decisions.md
│   ├── content-strategy.md
│   └── funding-and-resources.md
├── godot-project/                # The Godot 4 project root
│   ├── project.godot
│   ├── scenes/
│   ├── scripts/
│   ├── assets/
│   │   ├── sprites/
│   │   ├── tilesets/
│   │   ├── audio/
│   │   └── ui/
│   └── addons/
├── python-tools/                 # Asset pipeline, content gen, dev utilities
│   ├── pyproject.toml
│   ├── src/
│   └── tests/
├── ai-bridge/                    # Ollama integration helpers + prompt templates
│   ├── prompts/
│   │   ├── npc_personality_template.txt
│   │   ├── memory_consolidation.txt
│   │   └── chronicle_generation.txt
│   └── README.md
└── art-source/                   # Source files for sprites (not all committed; large raw work in .gitignore)
    ├── anchors/                  # Hand-authored anchor sprites (committed)
    └── generated/                # AI-pipeline outputs (committed once cleaned)
```

This is the target structure. We grow into it.

---

## Performance targets

- **PC desktop:** 60fps with ~50 NPCs visible, vsync on.
- **Mobile:** 30fps with ~30 NPCs visible. Battery-aware mode reduces simulation frequency.
- **LLM call latency:** acceptable up to ~5s for dialogue; if longer, show "thinking" UI. Never block input.
- **Save/load:** under 2s for a typical save.
- **Network (Tier 4+):** designed for typical home internet (50ms-200ms latency).

---

## Security and privacy

- **No secrets in repo, ever.** `.env` files in `.gitignore`. Pre-commit hook (gitleaks) before any public push.
- **Player data minimisation:** collect only what's needed for gameplay. No telemetry without opt-in.
- **Local LLM** means player conversations don't leave their machine in single-player. In multiplayer, NPC interactions occur server-side; we'll be transparent about this in the privacy policy.
- **Twitch integration (Tier 7+):** use OAuth, never store passwords. Streamer's chat data only used as designed.
