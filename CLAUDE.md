# Claude Operating Rules — Legacy Frontier

> Customised for the Legacy Frontier project. Based on the user's reusable workspace template.

## Mission

Ship a high-quality MVP of Legacy Frontier — a 2D pixel-art top-down RPG with persistent AI NPCs and a living world — incrementally, fast and safely. The MCP target is the Tier 2 vertical slice (see `docs/roadmap.md`).

## Workspace / Repo Map

- Root: `.`
- Key folders:
  - `./godot-project/` — the Godot 4 game project
  - `./python-tools/` — asset pipelines, content generation, AI-art workflows
  - `./ai-bridge/` — Ollama prompt templates and integration helpers
  - `./art-source/` — handcrafted anchor sprites and AI-generated assets (raw work in `.gitignore`)
  - `./docs/` — design, architecture, roadmap, decisions, content strategy, funding
- If structure is unclear, ask before architectural changes.

## Non-negotiables (Process)

- Always read this file at the start of every session and follow it strictly.
- Read `docs/decisions.md` to remember locked design decisions.
- Read `docs/roadmap.md` to know which tier we're building.
- Keep thinking mode ON. Use ultra-think when complexity/risk is high.
- Use `/clear` for fresh starts or when switching to a different task/feature area.
- For ANY new feature/large change: enter planning mode first.
  - Ask clarifying questions BEFORE writing code.
  - Propose a concrete plan + checkpoints.
  - Only then implement.
- After meaningful progress: append a "Session Context Update" to this file (append-only).

## Output Quality Rules

- Prefer small, reviewable changes over large rewrites.
- Keep commits PR-sized and logically grouped.
- Do not introduce new dependencies unless clearly justified.
- Prefer existing patterns in the codebase; be consistent with style + architecture.
- If unsure: explain tradeoffs and ask.

## Scope & MVP Discipline

- Default to the smallest change that achieves the desired user outcome.
- If a request expands scope, propose an MVP cut and a "later" list.
- The MCP boundary is in `docs/roadmap.md`. Don't accidentally build Tier 4 features in Tier 1.

## Tooling

- Godot 4 + GDScript for game code.
- Python (>=3.11) for tools.
- Ollama running locally for AI work.
- Use browser automation (Playwright) only when validating exported web builds (rarely relevant pre-launch).

## Permissions & Safety

- Do not access anything outside this workspace folder.
- Do not read/print secrets unless explicitly instructed.
- Never commit secrets. Maintain strong `.gitignore`. Use `.env.example` templates.
- LLM prompts that go into Ollama can leak game-design surprises if the repo is public — be thoughtful about prompt files in the public repo (see `ai-bridge/README.md` once it exists).

## Engineering Standards (Default Expectations)

- Add or update:
  - `.env.example` when env vars are required
  - `README.md` / `docs/` when usage changes
  - basic tests for critical logic (or at least a manual test checklist)
- Logging:
  - avoid leaking PII/secrets
  - log actionable errors with context
- For GDScript: follow Godot's official style guide.
- For Python: ruff + black formatting.

## Decision Logging

When a meaningful decision is made (naming, architecture, integration choice), record:

- Decision
- Reason
- Alternative considered

into `docs/decisions.md`. New entries appended at the bottom; old entries preserved.

## End-of-Milestone Review (Do before "ship" of any Tier)

- Run lint/format
- Run tests
- Dependency audit (npm/pip/etc.)
- Secret scan (gitleaks or equivalent)
- SAST scan (semgrep or equivalent)
- Quick performance/accessibility spot check for UI (Lighthouse + axe if applicable, mainly post-launch)
- Fix findings before calling the milestone complete

## Project-specific reminders

- **The world is the world.** When designing any feature, ask: "does this make the world bend to the player?" If yes, kill it. (See `docs/vision.md`.)
- **LLM only for deliberate moments.** Never call Ollama in combat, pathfinding, or per-frame logic. (See `docs/architecture.md`.)
- **Mobile-first input.** Every action must work via virtual joystick + tap. Keyboard/mouse adapts up. Never design something that requires pixel-perfect mouse aim.
- **Build-in-public, no face-cam.** Voice-over and screen-capture only. (See `docs/content-strategy.md`.)
- **MCP-first funding.** Don't get distracted pitching publishers before Tier 2 ships. (See `docs/funding-and-resources.md`.)

---

## Session Context Update (append-only)

### Session 1 — Foundation

- **Date:** 2026-05-05
- **Goal of session:** establish the design foundation, lock major decisions, scaffold the repo and doc set.
- **What changed:**
  - Locked all major design decisions (camera, world structure, combat, magic, multiplayer scale, persistence, art pipeline, music direction, monetisation).
  - Adopted *"the world is the world"* as the core design principle.
  - Removed god-mode from the design.
  - Locked stack (Godot 4 + GDScript + Ollama + Llama 3.2 3B + Python).
  - Created the full doc set: vision, design, architecture, art-and-audio, roadmap, decisions, content-strategy, funding-and-resources.
  - Committed to build-in-public strategy without face-cam.
  - Committed to MCP-first funding sequence (don't pitch funders pre-Tier-2).
- **Decisions made:** see `docs/decisions.md` D-001 through D-025.
- **Commands run (important ones only):** none yet — repo not initialised at end of session.
- **Tests/checks run + results:** N/A.
- **Next steps:**
  1. Initialise git repo locally.
  2. Push to GitHub (private initially; flip to public once comfortable).
  3. Install Godot 4.
  4. Install Ollama and run `ollama pull llama3.2:3b`.
  5. Begin Sprint 0 — Godot's official 2D tutorial.
- **Open questions/risks:**
  - Project handle / pseudonym for build-in-public — not chosen yet.
  - UK Ltd incorporation — needed before Prototype Fund eligibility; defer until ~Tier 1.5.
  - Specific class/race list — deferred to Tier 1.5 design.
  - Specific magic schools — deferred to Tier 5.
  - Specific identities of the 5–7 world bosses — deferred to Tier 6.
  - First NPC personality for v0.0 — to be designed in next session.
