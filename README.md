# Legacy Frontier

A 2D pixel-art top-down RPG where the world is the world.

Every NPC has persistent memory and personality. Your character continues to exist as an NPC when you log out. The world ticks forward without you. You are a participant, not a protagonist.

**Status:** Pre-development. Sprint 0 (learning Godot) in progress.

---

## The pitch

Legacy Frontier blends Terraria's exploration, Tower of God's worldbuilding, Shangri-La Frontier's living-world feel, and Skyrim's open-world depth — held together by AI-driven NPCs that remember and a persistent shared world that continues whether you're online or not. Up to ~20 players share each world.

**Core pillars:**
- Persistent AI NPCs with memory and personality
- Persistent player avatar (lives as an NPC offline; LLM-generated Chronicle on return)
- AI party members you recruit and adventure with
- Viewer-named NPCs (Twitch chat → in-world character)

**Design principle:** *The world is the world.* No chosen-one framing. NPCs have their own goals, lives, and deaths. Consequences are permanent. You can miss things forever.

---

## Stack

- **Engine:** Godot 4 + GDScript
- **AI:** Ollama running Llama 3.2 3B locally for NPC dialogue and memory consolidation
- **Tooling:** Python for asset pipelines, content generation, and AI-assisted pixel art
- **Platform:** PC (Windows) primary; mobile (virtual joystick) target from day one

---

## Documentation

| Document | Purpose |
|----------|---------|
| [docs/vision.md](docs/vision.md) | What the game is and why it exists |
| [docs/design.md](docs/design.md) | Systems, world, combat, magic, NPCs, multiplayer |
| [docs/architecture.md](docs/architecture.md) | Tech stack and AI architecture rules |
| [docs/art-and-audio.md](docs/art-and-audio.md) | Visual and music direction |
| [docs/roadmap.md](docs/roadmap.md) | Sprints, tiers, milestones, MVP boundaries |
| [docs/decisions.md](docs/decisions.md) | Decision log (append-only) |
| [docs/content-strategy.md](docs/content-strategy.md) | Build-in-public approach |
| [docs/funding-and-resources.md](docs/funding-and-resources.md) | Funding paths and external resources |

`CLAUDE.md` contains operating rules for AI-assisted development.

---

## Setup (placeholder — fill in once Godot project exists)

1. Install [Godot 4](https://godotengine.org/download).
2. Install [Ollama](https://ollama.com/) and pull the model: `ollama pull llama3.2:3b`.
3. Clone this repo.
4. Open the `godot-project/` folder in Godot.
5. Press F5 to run.

---

## License

Private. All rights reserved while in development. License to be determined at launch.
