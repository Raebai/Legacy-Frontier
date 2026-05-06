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

### Session 6 — Milestone 3: NPC entity with proximity-triggered hint

- **Date:** 2026-05-06
- **Goal of session:** ship M3 — a static NPC that blocks movement, shows a `[E] Talk` hint when the player walks within 32 px, and hides it when they walk away. First milestone with a `Resource`-backed identity (NPCData) so the same scene can become any character later.
- **What changed:**
  - **`NPCData` resource class** (`scripts/NPCData.gd`). Two `@export` fields: `npc_name: String` and `personality_prompt: String` (multiline). Marked with `class_name NPCData` so any future scene/script can type-hint against it.
  - **`first_npc.tres`** placeholder data instance at `data/npcs/first_npc.tres`. Name `"First NPC"`, prompt empty (filled in M5 — first NPC personality is the deliberate-design moment, not a Tier-1 detail). New top-level `data/` directory created for game-data resources distinct from `assets/`.
  - **NPC scene** (`scenes/NPC.tscn`). `StaticBody2D` root (so the player physically can't walk through it) carrying: a 16×16 orange `ColorRect` visual (Color 0.95, 0.5, 0.2 — warm contrast against the player's blue), a 16×16 box `CollisionShape2D` for the body, a child `Area2D` (`ProximityArea`) with a 32-px radius `CircleShape2D` for the trigger zone, and a hidden `Label` (`HintLabel`) at offset `(-28, -32)` with text `"[E] Talk"` and centred horizontal alignment. The NPC instance gets `data = ExtResource(first_npc.tres)` baked in at scene level — assigning per-instance happens later when there's more than one NPC.
  - **NPC controller** (`scripts/NPC.gd`). Extends `StaticBody2D`. In `_ready()` connects `proximity_area.body_entered` → `_on_body_entered`, `body_exited` → `_on_body_exited`, and forces `hint_label.visible = false` in case the scene file got corrupted. The handlers gate on `body.is_in_group("player")` — group-based identity instead of name/path coupling, so a hypothetical second player or a respawned player still triggers it.
  - **`Player.tscn` joins the `"player"` group.** Added `groups=["player"]` to the root `CharacterBody2D` declaration. This is why NPC.gd's `is_in_group("player")` works at all — the group membership is baked in at scene definition time, no `_ready()` glue needed.
  - **`Main.tscn` instances the NPC** at world position `(576, 256)` — six tiles east of the player at `(384, 256)`, well inside the 24-tile-wide room. Same column as the player so a single press of `D` brings them into proximity range.
- **Decisions made:** None new. (Group-based body identity, StaticBody2D for the NPC body, NPCData as Resource — all natural Godot 4 idioms; logging only if they later get challenged.)
- **Commands run (important ones only):**
  - First `editor-run` → debugger break: `Parser Error: Could not find type "NPCData" in the current scope` at `NPC.gd:3`. Cause: Godot's global script class cache hadn't picked up the new `class_name NPCData` script yet — the auto-reload addon caught the file write but doesn't refresh `.godot/global_script_class_cache.cfg`.
  - Recovery: `editor-stop`, then a headless `--import` against the project (`godot --headless --path ... --import`), confirmed `NPCData` appeared in `global_script_class_cache.cfg`, then re-ran. Clean boot, no errors.
  - Final `editor-run` succeeded; user verified all three acceptance criteria.
- **Tests/checks run + results:**
  - Class cache check after headless reimport: `NPCData` present with base `Resource`, path `res://scripts/NPCData.gd`. ✅
  - Project boot post-fix: clean (Vulkan + MCP runtime banner only, zero errors).
  - User verified: orange NPC visible, hint appears within ~32 px and hides on departure, NPC body blocks movement. ✅
- **Open questions/risks:**
  - **`class_name` not auto-registering during a live editor session is a recurring trap** — the auto_reload addon updates the script files on disk and the editor's open buffer, but doesn't trigger Godot's filesystem rescan that rebuilds `global_script_class_cache.cfg`. Workaround for future milestones: after writing any new `class_name` script, run a headless `--import` once before the next `editor-run`. Cheap, deterministic. Could also automate as a pre-`editor-run` step if the trap recurs more than once.
  - First NPC's personality + name still placeholder. M5 is when "First NPC" gets a real identity.
  - Llama 3.2 3B still un-talked-to.
  - Public-vs-private repo flip decision still pending.
- **Next steps:** Milestone 4 — dialogue UI scaffold. Pressing **E** while the hint is visible opens a full-screen overlay with: NPC name banner, message history pane (`RichTextLabel`), a single-line `LineEdit`, and a way to close (E or Esc). The NPC echoes input back as `"[NPC]: I heard you say: ..."` — no LLM yet, isolating the UI work before the streaming integration in M5.

### Session 7 — Milestone 4: dialogue UI scaffold with placeholder echo

- **Date:** 2026-05-06
- **Goal of session:** ship M4 — pressing **E** in NPC proximity opens a centred dialogue overlay over a dimmed world; typing a line and pressing Enter appends `You: ...` then `NPC: I heard you say: ...` to a scrolling history; **Esc** closes the dialogue and unfreezes the player. No LLM yet — the milestone exists to isolate UI work before streaming integration lands in M5.
- **What changed:**
  - **`DialogueUI.tscn`** — `CanvasLayer` (layer 100, above world) → full-screen `ColorRect` dimmer at 55 % black → centred `PanelContainer` (520×260) → `VBoxContainer` holding `Label` (NameBanner), `RichTextLabel` (HistoryPane, BBCode + scroll-following + `focus_mode=0`) and `LineEdit` (InputField). `RichTextLabel` was chosen over plain `Label` precisely so M5 can colour-code player vs. NPC turns without touching the structure.
  - **`DialogueUI.gd`** — autoloaded as singleton `Dialogue` via `[autoload] Dialogue="*res://scenes/DialogueUI.tscn"` in `project.godot`. Public surface: `open(data: NPCData)`, `close()`, `is_open() -> bool`. On open: shows the layer, sets the banner, clears history+input, calls `grab_focus()` on the LineEdit. On close: hides + releases focus. `_unhandled_input` only listens for `ui_cancel` (Esc) — does *not* listen for `talk` (E) because while open the LineEdit consumes E for normal text input, so binding E for close would conflict.
  - **`NPC.gd`** updated to track `_player_in_range` and, in `_unhandled_input`, fire `Dialogue.open(data)` when the `talk` action presses while in range and dialogue is closed. `_unhandled_input` is the right hook here: GUI controls (the LineEdit when dialogue is open) get first crack at events, so once dialogue opens, NPC stops seeing keys → no double-trigger.
  - **`Player.gd`** gated: at the top of `_physics_process`, if `Dialogue.is_open()` then zero velocity, `move_and_slide()`, return. WASD typed during dialogue typing therefore can't drive the player — and because the LineEdit is focused, those W/A/S/D presses go into the message text instead.
  - **`project.godot`** — added `talk` input action bound to physical keycode 69 (E), and registered the `Dialogue` autoload alongside `MCPRuntime`.
- **Bug ladder + final fix:**
  1. **First run:** parser break — `Could not find type "NPCData" in the current scope` at `DialogueUI.gd:open(data: NPCData)`. Same trap as M3 (auto_reload addon updates files on disk but doesn't refresh `global_script_class_cache.cfg` mid-session).
  2. **Recovery:** ran `godot --headless --path … --import` → cache rebuilt → next `editor-run` clean.
  3. **Second issue (the real M4 saga):** after Enter-to-submit, the LineEdit *visually* still looked focused but **typed letters were dropped**; the user had to press Enter *again* to "wake it up." First attempt: synchronous `grab_focus()` after clearing — no help. Second: `call_deferred("grab_focus")` — no help. Third: `await get_tree().process_frame` + `_process` safety net that re-grabbed every frame — *also* no help.
  4. **Root cause finally identified:** Godot 4 LineEdit defaults to **releasing focus on `text_submitted`**. The runtime fights any external `grab_focus` because LineEdit's own internal logic re-releases focus the next time it processes input. The canonical fix is the boolean property **`keep_editing_on_text_submit = true`** (added in Godot 4.0+). Setting it in `_ready()` flips LineEdit from "release on submit, you must regrab" to "stay focused, keep editing." With this property set, the convoluted `_process`/`await`/`call_deferred` stack collapses to a single line, and focus survives every submission cleanly.
- **Decisions made:** None new (architectural choices — autoload singleton, `_unhandled_input` for NPC trigger, `keep_editing_on_text_submit` for LineEdit — are natural Godot 4 idioms; logging only if challenged).
- **Commands run (important ones only):**
  - `godot --headless --path … --import` (twice — once to register the new `class_name`, once just to be safe before the second debug run).
  - `mcp__gopeak__editor-run` / `editor-debug-output` / `editor-stop` (multiple cycles during the LineEdit-focus saga).
- **Tests/checks run + results:**
  - Boot clean after each iteration; final run had zero errors with `keep_editing_on_text_submit = true` set.
  - User verified the four acceptance criteria: walk-up + E opens dialogue with dimmed world, typing+Enter renders both turns to history, **continuous-typing across multiple submissions works without re-pressing Enter to refocus** (the M4 saga fix), Esc closes and movement returns.
- **Open questions/risks:**
  - **Recurring `class_name` cache trap** — every milestone that adds a new `class_name` script and immediately consumes it from another script (M3, M4) hits the parser-error-on-first-run quirk. Mitigation: I now do `--headless --import` automatically before any milestone that introduces a new `class_name`. Could automate as a hook before `editor-run` if it persists.
  - **`keep_editing_on_text_submit` is the kind of trap that costs 30+ minutes if not known** — a future M8 polish item could be a "Godot UI gotchas" note in `docs/architecture.md` (text-input focus, modal stacking, when to use `_input` vs `_unhandled_input` vs `_gui_input`).
  - First NPC's personality + name still placeholder. M5 is when "First NPC" gets a real identity.
  - Llama 3.2 3B still un-talked-to. M5 is the test.
  - Public-vs-private repo flip decision still pending.
- **Next steps:** Milestone 5 — Ollama integration. Replace `_on_text_submitted`'s echo line with a real `HTTPRequest` POST to `http://localhost:11434/api/generate` carrying the personality prompt + the player's message; stream the response into the history pane chunk-by-chunk so the NPC appears to type. Architectural rule (architecture.md) holds: this is a *deliberate* LLM moment; movement / collision / hint logic still never call the LLM. M5 also requires the user to choose the first NPC's name + personality prompt — that's the design ask before I write the integration code.

### Session 8 — Milestone 5 + UI rebuild: live LLM + speech-bubble paradigm pivot

- **Date:** 2026-05-06
- **Goal of session:** ship M5 (real Ollama integration so Raebai actually responds) and M7's first half (in-session memory). Mid-session, the M4 dialogue UI got pivoted from a full-screen modal to in-world speech bubbles + a thin bottom input bar — a design-shaped change captured as D-032 through D-037.
- **What changed (high level):**
  - **M5 baseline shipped (then reshaped).** First pass: `HTTPRequest` node on the dialogue UI POSTing to `/api/chat` with `system + user` messages, non-streaming, with placeholder "thinking…" text in the history pane and red-italic error rendering. Llama 3.2 3B confirmed warm at ~3 s round-trip. Then the playtest unlocked the bigger redesign.
  - **`localhost` → `127.0.0.1` IPv4 pin.** First in-game LLM call hung 30 s and surfaced "Could not reach Ollama". Root cause: Godot's HTTPClient resolved `localhost` to IPv6 `::1` first on Windows, while Ollama only binds to IPv4 127.0.0.1. PowerShell tests had used `127.0.0.1` directly so they passed. Fixed at the constant in `Conversation.gd`.
  - **Dialogue UI pivot (D-032).** Full-screen `DialogueUI` modal retired; replaced with `scenes/Conversation.tscn` + `scripts/Conversation.gd` (autoload HUD with bottom input bar) and `scenes/SpeechBubble.tscn` + `scripts/SpeechBubble.gd` (Node2D bubble that lives above each character). NPC and Player both instance the bubble. The autoload's role shifted from "modal owner" to "conversation state machine + HTTP client + audience-router". Old `DialogueUI.tscn`/`.gd`/`.uid` deleted from the tree.
  - **Audience model (D-033).** Two modes, separate input shapes. **Whisper:** `E` in proximity opens the bar addressed to that NPC, full LLM with personality + per-NPC history. **Broadcast:** `Enter` from anywhere opens the bar in public mode, submission renders as a player speech bubble and the bar closes immediately so WASD goes back to movement. Broadcast plumbing built; no LLM/audience reaction wired since v0.0 has only one NPC (deferred to v0.5 alongside D-031 Tier 0/1 implementation).
  - **History merged into M5 (D-035).** Plan separated M5 (Ollama integration) and M6 (history). Playtest of M5 alone showed Raebai repeating questions and losing the thread — broken-looking enough that the planned M5 ship would have regressed UX. Per-NPC `messages: Array[Dictionary]` (role/content) now appended both sides of every exchange and sent in full on each `/api/chat` call. M6 task folded into M5.
  - **Player-bubble-in-whisper killed (D-036).** Initially the player's whisper message bubbled above their head with smart side-offset to dodge Raebai's bubble. Even with dynamic sizing it overlapped at proximity range, and the metaphor was wrong (whisper is private; world bubbles are public). Replaced with a small italic "you said: …" line above the input bar, fades after 3 s or on next keystroke. Broadcast still uses an in-world bubble. NPCs always use bubbles.
  - **Farewell detection (D-037).** Player message matches a regex of farewell keywords (`bye|goodbye|farewell|later|peace|see you|i'm out|gotta go|good night|safe travels|take care`) → input bar closes instantly, player movement is freed, but the in-flight LLM request keeps cooking and lands on the NPC's bubble when it arrives. Implemented via a state split: `_engaged_npc` controls UI/movement, `_pending_npc` keeps the in-flight target alive after disengagement. NPC-initiated endings deferred (D-034 territory).
  - **Speech-bubble shrink-to-fit.** Several iterations to make the bubble actually hug text. Final implementation: pass-1 measure unwrapped natural width with `autowrap_mode=OFF`; if ≤ MAX_WIDTH (220 px) bubble = natural width; else wrap at MAX_WIDTH, count lines, then binary search for the smallest width that maintains the same line count (6 iterations, ~100 ms total). Plus `_process` forces `panel.size = panel.get_combined_minimum_size()` every frame so layout doesn't drift back to stale `.tscn` defaults. The hardcoded `offset_left=-100, offset_right=100` on the panel were removed — they were silently locking the panel to a default 200 px width regardless of content.
  - **Personality prompt iteration loop.** Three rewrites this session as the failure modes surfaced: (1) initial 250-word prompt → incoherent (3B model overwhelmed); (2) 70-word minimal → "AI slop" therapy-bot replies on emotional cues; (3) ~140-word current with explicit anti-patterns ("never say 'I understand', 'tell me more', 'how does that make you feel'") + 4 micro-examples covering refusals, complaints, and direct-at-Raebai statements. Also added Ollama API options `num_predict: 60` and `stop: ["\n\n"]` as a triple-layer length cap (prompt + token cap + paragraph stop).
  - **Ollama auto-restart.** During testing, Ollama service had stopped. Restored via `Start-Process "ollama app.exe"` (the tray-app entrypoint, not `ollama serve` directly — the latter ran but didn't bind cleanly).
  - **Build-side hardening.** `chat` action added to project.godot input map (Enter / physical keycode 4194309). `Conversation` autoload registered in place of the retired `Dialogue` autoload. Player joins `"player"` group at scene level (carried from M3); player movement now gates on `Conversation.is_input_open()` rather than `is_engaged()` so broadcast composition also freezes movement (prevents WASD double-firing as both typing and walking).
  - **Auto-memory: collaboration style.** New feedback memory `feedback_collaboration_style.md` captures the user's directive: don't take their input as gospel; debate, surface tradeoffs, recommend, then defer. Indexed in `memory/MEMORY.md`. Anything design-shaped now gets the debate-first treatment by default.
- **Decisions made:** D-031 (logged earlier in this session), D-032, D-033, D-034, D-035, D-036, D-037. See `docs/decisions.md`.
- **Commands run (important ones only):**
  - Ollama API smoke: `Invoke-RestMethod -Uri http://127.0.0.1:11434/api/chat ...` confirmed reply in 3.2 s.
  - Multiple `editor-run` / `editor-debug-output` / `editor-stop` cycles for each iteration (~15 cycles total).
  - One headless reimport per significant `class_name` or scene change, per the recurring class-cache trap noted in Session 6.
- **Tests/checks run + results:**
  - Boot clean across all final-state runs.
  - User confirmed: bubble shrink-to-fit lands; whisper mode reads cleanly with HUD echo; broadcast bubble + close-on-submit feels right; farewell instant-close + parting reply lands; Raebai's character voice now lands on direct-at-him statements.
  - Conversation history continuity confirmed (no more "what brought you here?" loops).
  - 6 final commits-worth of changes ready to push as one M5 commit (this session).
- **Open questions/risks:**
  - **3B model character ceiling.** Llama 3.2 3B held character better with the current prompt + few-shot examples, but it's near the ceiling for nuanced emotional replies. If v0.5 testing shows persistent slop, swap to Llama 3.2 8B (5 GB, ~5–6 s per reply). Logged informally; not yet a decision because v0.0 doesn't justify the latency hit.
  - **NPC ambient reaction in broadcast.** Plumbing exists; nobody to react. Fully wired in v0.5 with NPC #2 + D-031 Tier 0/1.
  - **NPC-initiated farewell.** Deferred to D-034's v0.5 design pass.
  - First NPC's deeper history hooks ("you said your name was X — do they remember tomorrow?") gated on M7 persistence (next milestone).
  - Public-vs-private repo flip still pending.
- **Next steps:** Milestone 7 — JSON persistence. Save `_engaged_npc.messages` to `user://npc_memory/<npc_id>.json` after every disengage; load it back into the NPC instance on `_ready()`. The magic moment ("close Godot mid-conversation, restart, walk back, NPC remembers") becomes testable. Polish/error-handling work (M8) sits after that — input edge cases, cleaner error rendering, manual test checklist for v0.0.

### Session 9 — Milestone 7: persistent NPC memory (the seed magic moment) + callback greeting + EntityStats shape

- **Date:** 2026-05-06
- **Goal of session:** ship M7 — Raebai remembers across game launches. Bonus scope this session: contextual callback greeting on re-engagement, and the `EntityStats` data shape promised for v0.5 prep.
- **What changed:**
  - **`NPCData.npc_id`** added (default `""`). Stable per-NPC string used as the memory filename. Raebai's `first_npc.tres` set to `npc_id = "raebai"`. Empty `npc_id` means an NPC is transient (never persists), giving us a no-cost opt-out for ambient NPCs in v0.5.
  - **NPC.gd `_load_memory()` / `save_memory()`**. `_load_memory()` runs at the end of `_ready()`: reads `user://npc_memory/<npc_id>.json`, validates the shape, hydrates `messages`. Silent skip if file is missing/invalid (so deleting the JSON is a clean reset). `save_memory()` does an atomic write — JSON dumped to `<file>.tmp`, then renamed to the final path via `DirAccess.rename` (which uses `MoveFileEx(MOVEFILE_REPLACE_EXISTING)` on Windows). A crash mid-write can't corrupt an existing memory file. JSON wraps the messages array in `{version: 1, npc_id, messages}` so future schema bumps stay readable.
  - **Save trigger points** wired in `Conversation.gd`. `disengage()` (Esc / walk-out / empty-submit close) saves before clearing engagement. The farewell flow saves after the parting reply lands in `_on_request_completed` (because `_engaged_npc` was already nulled when "bye" was detected, so the disengage path didn't fire — the farewell save trigger fills that gap). Per the plan's risk register, no per-turn saves; a Godot crash mid-conversation loses the in-flight exchange but the prior history is safe.
  - **Magic-moment verified end-to-end.** First session: introduced as Raaed, mentioned heading to Coldrose, said "who knows, goodbye". JSON file confirmed on disk at `%APPDATA%\Godot\app_userdata\Legacy Frontier\npc_memory\raebai.json` — 691 bytes, three exchanges including Raebai's parting line "May the road rise up to meet you, Raaed." Closed Godot, restarted, walked back, asked Raebai a recall question — he answered with prior context. Magic moment landed.
  - **Callback greeting on re-engagement.** When player presses E and `npc.messages.size() > 0`, `Conversation.engage()` fires a one-shot LLM call before any user message: appends a synthetic user turn `(walks back up to you)` to keep the chat-grammar alternating, then calls `_send_to_ollama()` with a `_system_addendum` (one-shot system-prompt augmentation, cleared after use) instructing Raebai to greet with a callback line referencing prior content. Strong directive + 3 concrete examples + explicit anti-patterns ("never say 'how can I help you', 'welcome back, traveller', etc."). User confirmed the second iteration of the prompt worked: Raebai's greeting referenced specifics from the prior chat.
  - **`EntityStats` Resource shape**. New `class_name EntityStats extends Resource` with three groups: identity tags (`race`, `character_class`, `traits: Array[String]`), combat stats (`max_hp`, `current_hp` — passive in v0.0, used from Tier 1.5+), behavioural state (`mood`, `trust`, `patience` — passive in v0.0, will inject into LLM system prompt in v0.5 per D-034). `NPCData.stats: EntityStats` field. Raebai's data instance wires a sub-resource: race=`human`, character_class=`chronicler`, traits=`["scholar", "patient", "watcher"]`, hp=100/100, mood=0, trust=0, patience=1. **Shape only — no behaviour wiring.** Future-proofs the persistence layer (stats live in the .tres so they're already "saved" via git) and gives the user a tangible "Raebai has stats now" feel without expanding v0.0 behavioural surface.
  - **Callback prompt iteration.** First version was too abstract — Raebai gave a generic response that ignored the prior history. Second version (which landed) carried explicit must-do/must-not-do clauses, three concrete example greetings, and a forbidden-phrases list. Took one round of telemetry (a single `print()` confirming the callback fired with 6 prior messages) to confirm the issue was prompt-shape, not plumbing.
- **Decisions made:** No new decisions. EntityStats lands per D-034's design intent; callback greeting is the natural follow-on of D-035 (history sent every call) plus D-031's anchor-tier behaviour.
- **Commands run (important ones only):**
  - `Get-Content` on `%APPDATA%\Godot\app_userdata\Legacy Frontier\npc_memory\raebai.json` to verify save shape mid-test.
  - One headless `--import` cycle to register `EntityStats` `class_name` before the post-stats run (per the recurring trap noted in Sessions 6/8).
- **Tests/checks run + results:**
  - Save: confirmed on disk after first "bye" — file exists, JSON valid, 6 messages captured (including farewell parting line).
  - Load: after restart, Raebai's memory hydrated automatically in `_ready()`. User's recall question got answered with prior-session context. ✅
  - Callback greeting: confirmed firing via `print()` (`callback firing — 6 prior messages with Raebai`). After prompt iteration, Raebai's actual greeting referenced prior content. User confirmed: *"Yeah it was good! I like that I added some more information as well."*
  - EntityStats: clean boot after class_name registered; sub-resource loads correctly into NPCData; values reflect in the inspector.
- **Open questions/risks:**
  - **History grows unbounded.** Every exchange + every callback is appended to `messages`. After ~50 turns the API call gets expensive (token-wise). Memory consolidation (per architecture.md's bounded-context system) is genuinely needed before the v0.5 broadcast/ambient layer multiplies conversation surface area. Tier 2 work.
  - **Synthetic stage-direction turns bloat history.** Every callback adds `(walks back up to you)` and the resulting greeting to the persisted message array. After 100 engagements the history is ~10% stage directions. Acceptable for v0.0; consolidation pass will collapse them.
  - **EntityStats shape may need refactor when behaviour wires up.** Currently fields are flat; v0.5 behavioural integration may prefer a richer shape (decay rates per scalar, derived computed fields, observers). Acceptable risk — refactoring a Resource shape with one consumer is cheap.
  - **Llama 3.2 3B character ceiling.** Raebai's character voice held in this session including across the persistence test. Stays on 3B.
  - First NPC's deeper hooks gated on M8 polish + a real test checklist.
  - Public-vs-private repo flip still pending.
- **Next steps:** Milestone 8 — polish, error handling, manual test checklist. Specifically: loading-state visuals (the "..." thinking indicator could shimmer), better error rendering (the red BBCode currently looks placeholder-y), input edge cases (empty submit handling, very long input clipping, repeated rapid Enter while waiting), visual contrast pass for clip-readiness, mobile-input verification (D-011 doesn't break silently with the bottom-anchored bar), and `docs/v0.0-test-checklist.md` so anyone can run the magic-moment loop deterministically. After M8 lands, v0.0 ships.
