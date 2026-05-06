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

### Session 2 — Repo bootstrap, environment, v0.0 plan

- **Date:** 2026-05-05
- **Goal of session:** finish scaffolding into a working repo, install game-side AI infrastructure, lock the v0.0 implementation plan, ready M1 to start.
- **What changed:**
  - Read all existing docs and synthesised the project; flagged that `docs/` directory hadn't been created (files were at workspace root) and several smaller inconsistencies.
  - **Filesystem layout aligned to `architecture.md`:** created `docs/`, moved 8 design docs into it, created `godot-project/`, `python-tools/`, `ai-bridge/`, `art-source/` with `.gitkeep` placeholders. Renamed unpacked Godot zip folder to `godot-engine/`.
  - **`.gitignore` updated:** added `.claude/` (Claude Code session data) and `godot-engine/` (172 MB editor binary) so neither is ever committed.
  - **Tooling installed:** Python 3.14.2 already present; Godot 4.6.2 stable manually placed under `godot-engine/`; Ollama 0.23.0 installed via winget after Smart App Control was disabled (D-029). Llama 3.2 3B *not yet pulled* — pending.
  - **Git repo initialised** (`main` branch), local-scope identity set to `Raebai` + GitHub noreply email (D-028), initial scaffolding commit `d65a448` made (16 files, 1,750 insertions), pushed to private `https://github.com/Raebai/Legacy-Frontier`.
  - **v0.0 implementation plan written** at `docs/sprint-1-plan.md` — 8 milestones from Godot project bootstrap through persistent NPC memory, with Godot concepts annotated inline since Sprint 0 is being skipped (D-026).
  - **Sprint 0 retired** in favour of learn-by-reading-the-code approach (D-026); the *"Goldman analyst learning Godot"* content beat is also dropped.
- **Decisions made:** D-026 (skip Sprint 0), D-027 (project structure at scaffolding), D-028 (pseudonymous git identity), D-029 (SAC disabled).
- **Commands run (important ones only):**
  - `git init -b main`, `git add .`, `git commit`, `git remote add origin ...`, `git push -u origin main`
  - `winget install --id=Ollama.Ollama -e` (after disabling SAC; first attempt failed with `0x8007029c` due to SAC blocking installer execution)
- **Tests/checks run + results:**
  - `git log --oneline -1` → `d65a448 Initial scaffolding...`; `git branch -vv` shows `main` tracking `origin/main`. Push verified.
  - `ollama --version` → `0.23.0`. HTTP API at `localhost:11434/api/tags` returns `HTTP 200 {"models":[]}`.
  - `ollama list` → empty (model pull not yet run).
- **Next steps:**
  1. User runs `ollama pull llama3.2:3b` in a fresh Warp tab (~2 GB).
  2. Once the model is local, run Step 4 — verify Ollama HTTP API with a real prompt via `Invoke-RestMethod`.
  3. Begin **Milestone 1** of the v0.0 plan — Godot project bootstrap + WASD-controlled placeholder character.
- **Open questions/risks:**
  - Llama 3.2 3B pull is the only blocker on Step 4 and Milestone 5.
  - First NPC's personality + name still undesigned — user picks in Milestone 5 territory.
  - SAC is now permanently off on this machine (D-029); future Windows reinstall is the only way back. Acceptable for a dev machine.
  - Public-vs-private repo timing tension carried forward: repo is private; reassess flipping to public after v0.0 ships.

### Session 3 — Milestone 1: Godot project bootstrap + WASD-controlled placeholder character

- **Date:** 2026-05-06
- **Goal of session:** ship M1 of the v0.0 plan — a moving placeholder character that proves the project loads, the input map works, and the per-milestone build/commit loop is real.
- **What changed:**
  - Created the Godot 4 project under `godot-project/`: `project.godot` (config + input map), `scenes/Main.tscn` (root Node2D, Player instanced at viewport centre), `scenes/Player.tscn` (CharacterBody2D + ColorRect placeholder + RectangleShape2D collider), `scripts/Player.gd` (12-line `_physics_process` using `Input.get_vector` over the four `move_*` actions).
  - Filled out the architecture-proposed directory layout under `godot-project/`: `assets/{sprites,tilesets,audio,ui}/` and `addons/`, with `.gitkeep` placeholders. Removed the now-redundant top-level `godot-project/.gitkeep`.
  - Defined the input map in `project.godot` with `move_up/down/left/right` actions bound to W/A/S/D + arrow keys, using `physical_keycode` so QWERTY/AZERTY users behave identically. Action names — never raw keycodes — referenced in code, preserving D-011's mobile-input architecture for later virtual-joystick additions.
  - Validated the project headlessly *before* the user opened the editor (`godot --headless --path ... --import` exited cleanly with both `first_scan_filesystem` and `loading_editor_layout` `[ DONE ]`).
  - Godot 4.6.2 auto-normalised `project.godot` on import: bumped min-version flag from `4.4` to `4.6`, added the 4.6-default `[animation]` block, dropped a redundant `window/stretch/aspect="keep"` line. Changes accepted as the canonical form.
  - Established the per-milestone collaboration loop: I write code → headless validate → user opens Godot + F5 → user reports → commit + CLAUDE.md update → next milestone. Tier 1 visibility (CLI validation + user screenshots) is sufficient through v0.0; Tier 1.5 (a `tools/capture.gd` headless screenshot script) deferred until a visual milestone needs it.
- **Decisions made:** None new this milestone.
- **Commands run (important ones only):**
  - `godot.exe --headless --path godot-project --import` (succeeded, no errors).
  - User opened the editor, hit F5, confirmed the placeholder square moves in all 8 directions and stops on key release.
- **Tests/checks run + results:**
  - Headless project import: clean.
  - Manual runtime test: light-blue 16×16 square moves cardinal + diagonal at 180 px/s, releases stop instantly. ✅
- **Next steps:** Milestone 2 — `TileMapLayer` + tileset, `Camera2D` smooth-follow, wall collisions.
- **Open questions/risks:** None new this milestone.

### Session 4 — Adopt Gopeak MCP, then pause

- **Date:** 2026-05-06
- **Goal of session:** raise the Claude ↔ Godot collaboration loop from "user pastes screenshots + runs F5" (Tier 1 visibility) to a real interactive bridge that lets Claude see scene state, capture screenshots, edit nodes, and run scenes directly. Then snapshot a clean handoff state.
- **What changed:**
  - Compared the top three open-source Godot MCP servers (Coding-Solo/godot-mcp at 3.4k stars, HaD0Yun/Gopeak-godot-mcp at 160 stars, 3ddelano/gdai-mcp-plugin-godot at 80 stars). GDAI eliminated as not actually open-source ("All rights reserved"); Coding-Solo eliminated despite the star lead because it lacks screenshot capture, scene-tree readout, and live editing — exactly the capabilities we need.
  - Picked **Gopeak** (110+ tools, MIT, v2.3.6 — 2026-04-05). Logged as **D-030** with full rationale.
  - Audited Gopeak's `install-addon.ps1` before user ran it (clean: 13 files into three addon dirs under `addons/`, no permission shenanigans).
  - User ran `iwr | iex` from inside `godot-project/`; `auto_reload`, `godot_mcp_runtime`, and `godot_mcp_editor` addons landed in `godot-project/addons/` (Godot also auto-generated `.uid` sidecars on scan, also committed).
  - Registered the MCP at *project* scope via `claude mcp add gopeak -s project ...`, creating `.mcp.json` at the repo root with `GODOT_PATH` and `GOPEAK_TOOL_PROFILE=compact` baked in. Project-scope means any future Claude Code session in this repo auto-loads the same MCP.
  - User enabled the three plugins in Project Settings → Plugins. Godot wrote `[autoload] MCPRuntime` and `[editor_plugins] enabled=...` to `project.godot`.
  - Two pushes to `origin/main` this session: `b4fed8c` (M1) and `4bb98ed` (MCP setup).
- **Decisions made:** D-030 (adopt Gopeak MCP at project scope, vendored addons, compact tool profile).
- **Commands run (important ones only):**
  - `iwr https://raw.githubusercontent.com/HaD0Yun/Gopeak-godot-mcp/main/install-addon.ps1 -UseBasicParsing | iex` (from inside `godot-project/`).
  - `claude mcp add gopeak -s project -e "GODOT_PATH=..." -e "GOPEAK_TOOL_PROFILE=compact" -- npx -y gopeak`.
  - `git push origin main` (twice).
- **Tests/checks run + results:**
  - `node --version` → v24.13.0; `claude --version` → 2.1.129 (Claude Code).
  - All 13 expected addon files (plus 9 Godot-generated `.uid` sidecars) verified in place.
  - `git status` clean at end of session, both commits on `origin/main`.
  - **MCP smoke test NOT yet run** — requires a fresh Claude Code session to load `.mcp.json`. Deferred to next session.
- **Next steps (read on resume):**
  1. **Keep Godot open** with the Legacy Frontier project loaded — the runtime + editor addons listen on localhost ports inside Godot.
  2. **Restart Claude Code** if not already restarted: from a Warp tab in `C:\Users\Raaed\Documents\Legacy Frontier`, run `claude --continue` (or `claude --resume` if `--continue` misbehaves; or `claude` for a fresh session — this CLAUDE.md plus `docs/sprint-1-plan.md` and `docs/decisions.md` are sufficient context for cold-start).
  3. **Approve the MCP prompt** that Claude Code shows on first run after seeing `.mcp.json`. The first `npx -y gopeak` invocation will download the package (~10–20 s).
  4. **Smoke test:** Claude calls `ToolSearch` to load Gopeak tool schemas, then `capture_screenshot` to verify the bridge is real.
  5. **Begin Milestone 2** of `docs/sprint-1-plan.md` — `TileMapLayer` + tileset, `Camera2D` smooth-follow, wall collisions. Now MCP-assisted: Claude writes/modifies the scene programmatically and verifies visually without forcing the user to F5-and-report each step.
- **Open questions/risks:**
  - Gopeak MCP smoke test still pending. Possible failures: ports blocked by firewall, `npx -y gopeak` resolution issues, addon initialisation errors on Godot side. If anything errors on next-session smoke test, paste the error and triage before touching M2.
  - First NPC personality + name still undesigned — surfaces in M5 territory.
  - Llama 3.2 3B is local and warm-tested (cold ~58 s, warm ~230 ms) but no NPC has been talked to yet; M5 is when that gets real.
  - Public-vs-private repo flip decision still pending (currently private; reassess after v0.0 ships).

### Session 5 — Milestone 2: tilemap, camera follow, wall collisions

- **Date:** 2026-05-06
- **Goal of session:** ship M2 — a 24×16 tile room with grass interior, stone wall border that blocks movement, and a smooth-follow camera. First milestone with real Gopeak MCP assistance.
- **What changed:**
  - **Gopeak MCP smoke test passed.** `project-info` returned live data ("Legacy Frontier", 4.6.2.stable, 2 scenes, 10 scripts); `editor-status` reported `connected: true` once Godot was open with plugins enabled; `runtime-status` confirmed the autoload bound port 7777 once the game ran. The bridge is real and three-layered (static file ops / live editor / live runtime).
  - **Placeholder atlas pipeline.** Wrote `python-tools/generate_placeholder_atlas.py` — stdlib-only PNG writer (`zlib` + `struct`, no Pillow dependency) that emits a 64×32 atlas: tile 0 grass (R78,G138,B64), tile 1 stone (R118,G118,B122), with a 4-px micro-checker so 32-px tile boundaries are visible at runtime. Output: `godot-project/assets/tilesets/placeholder_atlas.png` (155 bytes).
  - **TileSet resource (`.tres`) hand-authored.** `godot-project/assets/tilesets/placeholder_atlas.tres` defines one `TileSetAtlasSource` over the PNG, two atlas tiles, and a single `physics_layer_0`. Wall tile `(1,0)` carries a polygon collider covering the full 32×32 cell; grass tile `(0,0)` is collision-free. Godot's importer auto-generated `.uid` sidecars and `.godot/imported/placeholder_atlas.png-*.ctex` cleanly on first load.
  - **Programmatic room paint.** New `scripts/World.gd` extends `Node2D` and is attached to `Main`. In `_ready()` it loops a 24×16 grid and calls `tilemap.set_cell()` — wall on borders, grass inside. Reasoning: hand-encoding `tile_map_data` as a `PackedByteArray` blob in the `.tscn` is opaque and brittle; a 12-line GDScript painter is readable in git, easy to extend in M3 (NPC placement), and runs in <1 ms at startup.
  - **`Main.tscn` rewritten.** Added `TileMapLayer` child (with `tile_set = ExtResource(...)` pointing at the `.tres`), attached `World.gd` to root, moved Player from `(320, 180)` (old viewport-centre) to `(384, 256)` (room-centre at 12×8 tiles of 32 px).
  - **Camera2D added to `Player.tscn`.** Single new child node with `position_smoothing_enabled = true` and `position_smoothing_speed = 5.0`. Placing it inside `Player.tscn` (not `Main.tscn`) means the camera travels with the player automatically — no script glue needed. Camera2D also auto-promotes to active camera on `_ready()` because there's only one in the scene.
  - **Per-milestone loop upgraded to Tier 2 visibility.** I drove `editor-run` directly via MCP (no F5 from the user), polled `editor-debug-output` for boot output (clean: only Vulkan banner + MCP runtime startup messages, zero errors), confirmed `runtime-status` showed the autoload connected on port 7777, then asked the user to play and report. Compared to M1, the user's job collapsed from "open editor → F5 → describe what you see" to "watch and report on feel."
- **Decisions made:** None new. (D-030 covered Gopeak adoption; M2 used it as designed.)
- **Commands run (important ones only):**
  - `python python-tools/generate_placeholder_atlas.py` → `Wrote ...placeholder_atlas.png (155 bytes)`.
  - `mcp__gopeak__editor-run` (M2 verification launch).
  - `mcp__gopeak__editor-stop` (clean shutdown before commit).
- **Tests/checks run + results:**
  - Project boot via MCP `editor-run` — clean, no errors. Vulkan device picked up the RTX 4070 Laptop.
  - `runtime-status` post-launch — `processActive: true`, `runtimeAddon: connected`, ping-pong RTT confirmed.
  - User visually confirmed: grass + walls render, walls block movement, camera smoothly trails the player. ✅
- **Open questions/risks:**
  - **Gopeak dynamic-group tool schemas don't refresh mid-session in Claude Code.** Activating the `testing` group (which contains `capture_screenshot`, `inject_action`, `inject_key`) inside an already-running CC session reports the tools as "active" inside Gopeak, but their MCP tool schemas never become callable from this side until a CC restart. Workaround: pre-activate testing group at session start, or accept that for any *new* milestone needing screenshot/input injection, a quick CC restart is the price. Not blocking — fall back to user-as-camera works fine. Worth retesting on Gopeak v2.4 if/when it ships.
  - First NPC personality + name still undesigned. Surfaces in M5.
  - Llama 3.2 3B still un-talked-to; M5 is the test.
  - Public-vs-private repo flip decision still pending; reassess after v0.0 ships.
- **Next steps:** Milestone 3 — NPC entity + proximity detection (`Area2D` + signals). Per `docs/sprint-1-plan.md`. Will need an NPC sprite (different colour, `CharacterBody2D` or `StaticBody2D`), a child `Area2D` for the trigger zone, and a `Label`/`Control` floating hint that toggles via `body_entered` / `body_exited` signals.
