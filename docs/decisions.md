# Decisions

Append-only decision log. Newest entries at the bottom. Format per the operating rules:

- **Decision:** what was decided
- **Reason:** why
- **Alternative considered:** what else was on the table and why we didn't pick it
- **Date:** when locked
- **Status:** locked / under review / superseded

---

## D-001 — Engine: Godot 4 + GDScript

- **Decision:** Use Godot 4 with GDScript as the primary language.
- **Reason:** Best-in-class for 2D games. Free, open source, single codebase exports to PC and mobile. GDScript is Python-flavoured, so Python instincts transfer. Strong tutorial ecosystem.
- **Alternatives considered:** Unity (heavier, .NET-tied, larger ecosystem but overkill); Unreal (3D-first, heavyweight, harder for 2D and beginners); pure Python (Pygame/Arcade — would require building everything from scratch and would never ship).
- **Status:** Locked.

## D-002 — Local LLM: Ollama + Llama 3.2 3B

- **Decision:** Use Ollama running locally with Llama 3.2 3B as the default NPC dialogue model.
- **Reason:** Hardware (NVIDIA GPU on Windows) supports it easily. Free, no API costs. Players' conversations stay on-device. HTTP API is trivial to call from GDScript. Latency acceptable for dialogue.
- **Alternatives considered:** API-based models (Claude, GPT — high quality but expensive per call and adds dependencies); larger local models (8B, 13B — slower, may not fit on all target hardware); rule-based dialogue (cheaper but doesn't deliver the core pillar).
- **Status:** Locked.

## D-003 — Project name: Legacy Frontier

- **Decision:** Game is named "Legacy Frontier."
- **Reason:** *Legacy* captures the persistent memory and history themes (NPCs remember, world remembers, civilisations leave traces). *Frontier* captures the exploration loop and the unknown edge.
- **Alternatives considered:** Multiple unnamed candidates; nothing else surfaced as cleanly tied to the thesis.
- **Status:** Locked.

## D-004 — Camera: top-down 3/4 perspective

- **Decision:** Top-down 3/4 perspective (Stardew Valley / Pokémon / Albion angle), zoomable for map view.
- **Reason:** Best fit for the described gameplay (massive shared world with portals, clans, dungeons, magic). RuneScape, Tibia, Albion all built that vibe top-down for a reason — sideview struggles with many players in one space. Top-down also makes UI simpler (one camera, zoom for map view).
- **Alternatives considered:** Sideview (Terraria-style — locked initially, then revisited; killed because civ-sim and many-player elements don't read well in sideview); pure top-down (WorldBox-clinical, too cold); hybrid sideview with separate Atlas screen (more complex, second camera).
- **Status:** Locked. (Note: this decision flipped multiple times during early design exploration; this is the final lock.)

## D-005 — World structure: hybrid overworld + Tower

- **Decision:** A single massive interconnected overworld with a central Tower as a literal landmark structure. Tower floors are accessed via portals at the base; each floor is an instanced dungeon zone with its own theme, threats, and lore.
- **Reason:** Combines Albion-style open exploration with Tower of God's vertical mystery and bounded progression. Open world feels alive; Tower delivers the "how far can you go" mystery driver. Floors are scoped content drops post-launch.
- **Alternatives considered:** Pure Tower of floors (loses open-world feel); pure single open world (loses bounded mystery driver); infinite horizontal expansion (no progression structure).
- **Status:** Locked.

## D-006 — Civilisation simulation: out of scope

- **Decision:** No civ-sim layer. NPCs are individuals; settlements stay small. No kingdoms-at-war, no nation politics.
- **Reason:** The user explicitly pulled back from civ-sim depth. Civ-sim is also visually unreadable in any 2D camera mode at the player scales we're targeting. Scope reduction.
- **Alternatives considered:** Full civ-sim (rejected — adds enormous scope, doesn't visualise well, not core to the player experience the user wants).
- **Status:** Locked.

## D-007 — Persistent avatar with Chronicle

- **Decision:** When a player logs out, their character continues to exist as a simple-AI NPC. The world ticks forward. On login, an LLM-generated Chronicle (concise paragraph summary + structured deltas) tells the player what their character did while away.
- **Reason:** This is the strongest retention mechanic in the design. Players log in daily to see the Chronicle. It also creates emergent stories that no scripted game can produce. Unifies offline simulation with the AI-NPC pillar — same engine viewed from different angle.
- **Alternatives considered:** Character vanishes on logout (boring, world feels static); avatar persists but no Chronicle (hidden — players don't see the value); dramatic multi-page Chronicle (rejected as too overwhelming and expensive to generate).
- **Status:** Locked.

## D-008 — Chronicle format: concise

- **Decision:** Chronicle is a concise paragraph summary + structured list of stat, item, and relationship deltas.
- **Reason:** Cheaper to generate, faster to read, dopamine hit of "what changed?" without slogging through chapters. Can promote to "deluxe" mode later if tech and audience support it.
- **Alternatives considered:** Dramatic multi-page narrated chapters; tiered (concise default + deluxe unlockable). Rejected for v1 — adds cost and complexity without proven demand.
- **Status:** Locked for v1.

## D-009 — Multiplayer scale: ~15–20 players per world

- **Decision:** Target ~15–20 concurrent players per world instance/shard. Not a true MMO.
- **Reason:** Achievable for a small dev team. Larger scales (100+) require dedicated MMO infrastructure, server engineering, and anti-cheat — all of which kill ambitious indies. 15–20 still feels populated in a large 2D world; players naturally spread across geography.
- **Alternatives considered:** 100+ (initial target — too ambitious); 8 (Terraria default — too small for the multiplayer feel); single-player only (loses the shared-world pillar).
- **Status:** Locked.

## D-010 — Combat: weapon-based action combat

- **Decision:** Real-time action combat where each weapon archetype defines its own combat feel. Stamina-gated dodge/sprint/heavy attacks. Iframes on dodge.
- **Reason:** Standard ARPG pattern, well-trodden, references abound (Terraria, Dead Cells, Hollow Knight, Albion). Weapon-driven feel pairs with magic schools to create distinct character builds.
- **Alternatives considered:** Turn-based (cooler for storytelling but doesn't match Terraria/Skyrim DNA); pure click-targeting MMO combat (less engaging); auto-battler (rejected as low-skill).
- **Status:** Locked.

## D-011 — Mobile-first input architecture

- **Decision:** Virtual joystick + on-screen controls for mobile from day one. Keyboard/mouse adapts up from this baseline.
- **Reason:** Retrofitting touch controls onto a desktop-first game is hell. Designing both in parallel from the start is the only sane path. Also forces clean input abstraction in code.
- **Alternatives considered:** Desktop-first then port (rejected — would require rebuilding combat tuning); mobile-only (loses PC market and streaming audience).
- **Status:** Locked.

## D-012 — Death: soft (respawn + XP loss + durability damage)

- **Decision:** Soft death by default. Respawn at nearest safe location. Lose XP in most-recently-used skill. Equipment takes durability damage. Permadeath is opt-in only.
- **Reason:** Friendly enough for casual players; meaningful enough to make combat matter. Hardcore option for those who want stakes.
- **Alternatives considered:** Permadeath default (too hostile); no penalty (no stakes); item drop on death (only in PvP zones now).
- **Status:** Locked.

## D-013 — PvP: designated zones only

- **Decision:** Most of the world is PvE. Specific high-risk areas are flagged as PvP-enabled. PvP zones have full loot drops on death and better loot rewards.
- **Reason:** Open-world full PvP divides players. PvE-only kills emergent player-vs-player drama. RuneScape's Wilderness model is the proven middle ground.
- **Alternatives considered:** Open-world PvP (Albion-style, hardcore, niche); PvE-only (loses tension); faction-vs-faction warfare everywhere (rejected as scope creep).
- **Status:** Locked.

## D-014 — Magic: spell-based with magic schools, designed in Tier 5

- **Decision:** Spells learned from scrolls / NPCs / discovery, organised into magic schools. Cultivation flavour (spells level through repeated casting). Specifics deferred to Tier 5.
- **Reason:** Magic systems benefit from being designed once we understand the rest of the game. Premature design here would be wasted.
- **Alternatives considered:** Skill-tree clickable magic (gamey, less in-world); single magic style (less variety); designed now (rejected — defer).
- **Status:** Principles locked; specifics deferred.

## D-015 — Crafting: minimalist, not core

- **Decision:** Crafting and gathering exist (mining, herbalism, fishing, basic crafting) but are not central. Maybe 5–10 craftable categories.
- **Reason:** Adds depth without consuming the design budget. Terraria-level crafting is a separate game.
- **Alternatives considered:** Full sandbox crafting (Terraria-scale — rejected, too much scope); no crafting (less to do); deep crafting later (deferred).
- **Status:** Locked at minimalist.

## D-016 — Building: housing yes, no permanent territory

- **Decision:** Players can claim small plots in approved town zones for housing. No permanent territory claims in the open world.
- **Reason:** Personal expression without breaking shared-world dynamics. Wilderness stays shared.
- **Alternatives considered:** Full territory claims (rejected — fragments the world); no housing (less expression); clan-only territory (deferred to Tier 6+).
- **Status:** Locked.

## D-017 — Pixel art: layered/AI-assisted pipeline

- **Decision:** Anchor library handcrafted; layered sprite system for variation; Stable Diffusion / PixelLab.ai for AI-assisted asset creation in the offline pipeline. Runtime is 100% pre-baked sprites.
- **Reason:** Style consistency (humans set style, AI scales it). Performance (no inference at runtime). Quality control (human review before ship).
- **Alternatives considered:** Pure handcrafted (too slow for solo dev); runtime AI generation (style breaks, perf issues, weird artifacts); pure asset-pack purchase (no original style).
- **Status:** Locked.

## D-018 — Music: atmospheric melancholy fantasy, royalty-free placeholder until Tier 5

- **Decision:** Music brief is "atmospheric melancholy fantasy with hypnotic, time-soaked textures." Royalty-free placeholders during dev; commission a composer at Tier 5+.
- **Reason:** Game vibe reads even with placeholders if other systems are tight. Real composer cost is justifiable once the game has audience and funding.
- **Alternatives considered:** Commission immediately (premature spend); chiptune (off-brief); orchestral epic (off-brief).
- **Status:** Locked.

## D-019 — God-mode: REMOVED

- **Decision:** No god-mode play option. No world editor, no terraforming tools, no GM mode. Everyone plays as a character.
- **Reason:** Tightens the pitch. Aligns with "the world is the world" — players don't bend the world. Removes a substantial chunk of work (Tier 8 god-mode tools).
- **Alternatives considered:** Solo god-mode toggle; multiplayer GM/director role; streamer-as-god mode. All rejected.
- **Status:** Locked. (Originally part of the trinity; removed mid-design.)

## D-020 — Core design principle: "The world is the world"

- **Decision:** Adopt "the world is the world" as the foundational design principle. The world exists on its own terms. The player is a participant, not a protagonist. NPCs have their own goals, lives, and deaths. No chosen-one framing. No main quest for the player. Permanent consequences.
- **Reason:** Unifies all the other locked decisions (persistent avatar, AI NPC autonomy, no god-mode, world tick). Gives a clean test for future design questions: "does this make the world bend to the player?" If yes, kill it.
- **Alternatives considered:** Standard chosen-one RPG framing (rejected — generic, contradicts the AI pillar); player-as-god framing (rejected with god-mode); hybrid (rejected as muddled).
- **Status:** Locked. *Most important entry in this log.*

## D-021 — Onboarding: arrive at the Tower base via portal

- **Decision:** New players arrive at the base of the Tower via portal, equipped with a starter item only. Tutorial baked into early NPC interactions. Lore framing explains why strangers regularly appear.
- **Reason:** Aligns with "world is the world" (no chosen-one wakeup). Gives every new player a shared cultural starting point. Tower-base as a hub funnels social interaction.
- **Alternatives considered:** Wash up at coastal town (less central); standard "wake up amnesiac" (off-principle); separate tutorial mode (jarring).
- **Status:** Locked.

## D-022 — Quests: NPC needs + village boards + world events

- **Decision:** Three quest sources combined. NPC-needs (LLM-narrated, mechanics coded). Village quest boards (procedural low-stakes). World events (open to all for a window, then gone whether you helped or not).
- **Reason:** World-event quests are the strongest expression of "world is the world." Multiple sources mean variety; LLM narration makes each feel personal.
- **Alternatives considered:** Single quest source (less variety); pure procedural (less narrative weight); pure scripted (doesn't scale).
- **Status:** Locked.

## D-023 — World bosses: 5–7 named, Shangri-La Frontier-inspired

- **Decision:** 5–7 uniquely named world bosses with deep lore and extreme difficulty. First-kill triggers world-wide announcement and NPC gossip. Tier 6 design.
- **Reason:** Anchors endgame content. Streaming-friendly (first-kills are events). Aligns with the source-material inspirations.
- **Alternatives considered:** Many small bosses (less impact); single endgame boss (less variety); generic dungeon bosses (less narrative).
- **Status:** Locked at concept; specifics designed in Tier 6.

## D-024 — Build-in-public, no face-cam

- **Decision:** Develop the game in public (public GitHub, devlogs, social content). The user will not appear on camera. Content is voice-over + screen capture + game footage. Brand is the game, not the developer's face.
- **Reason:** User preference (privacy / personal choice). Plenty of successful indie devs build in public without face-cam (ConcernedApe, many others). Doesn't reduce the strategy's effectiveness.
- **Alternatives considered:** Full face-cam build-in-public (rejected by user); silent development (loses the funding flywheel); pseudonymous (compatible with this).
- **Status:** Locked.

## D-025 — MCP-first funding strategy

- **Decision:** Self-fund through the MCP (~Tier 2). Don't pursue publishers, grants, or investors until the MCP is playable.
- **Reason:** Pre-prototype, almost no funder will write checks. With an MCP and audience, doors open. Self-funding through Tier 2 is feasible given the user's existing income (Goldman role).
- **Alternatives considered:** Pursue funding from day one (rejected — wasted effort, weak position); fund only at launch (rejected — leaves money on the table during alpha); take on investor before product exists (rejected — bad terms, distraction).
- **Status:** Locked.

## D-026 — Skip Sprint 0; learn Godot by reading the code shipped

- **Decision:** Skip Sprint 0 (the tutorial-driven Godot learning runway in `roadmap.md`) entirely. Go directly from scaffolding to v0.0 implementation. The user (a Godot beginner with strong Python fluency) learns Godot concepts by reading the code Claude writes during v0.0 milestones, with concepts annotated inline in 1–2 sentence explanations as they appear. If velocity feels too high, the user pauses Claude with *"explain that"* and gets a deeper walkthrough.
- **Reason:** The user explicitly opted to skip tutorials in favour of learning-by-doing on the real project, in service of part-time velocity and content-strategy deadlines. The Sprint 0 "Goldman analyst learning Godot" content beat is also retired by this decision (it surfaced a partial-dox concern around naming the day-job employer in public posts).
- **Alternatives considered:** Run Sprint 0 fully as written (rejected — slower; user prefers learning on the real codebase); a half-Sprint-0 of just the official "Your First 2D Game" tutorial (rejected as still slower than the chosen path; can be revisited if v0.0 milestones reveal genuine fundamentals gaps).
- **Status:** Locked. Risk: heavier inline annotation burden on Claude during v0.0 milestones, accepted.
- **Date locked:** 2026-05-05.

## D-027 — Project structure laid out at scaffolding commit

- **Decision:** At the initial scaffolding commit, create the full directory structure proposed in `architecture.md` (`docs/`, `godot-project/`, `python-tools/`, `ai-bridge/`, `art-source/`), with `.gitkeep` files in the empty subdirectories.
- **Reason:** Locks the structure into commit #1 with no churn later. Every later commit places files in their architecture-correct location from the start. The cost is four `.gitkeep` files; the benefit is consistency.
- **Alternatives considered:** Create directories lazily as files arrive (rejected — every "first file in this folder" commit becomes a structural decision; more drift risk).
- **Status:** Locked.
- **Date locked:** 2026-05-05.

## D-028 — Git commit identity: pseudonymous (`Raebai` + GitHub noreply)

- **Decision:** Configure `user.name = "Raebai"` and `user.email = "Raebai@users.noreply.github.com"` at `--local` scope in this repo only. The user's real email never appears in commit history.
- **Reason:** Aligns with D-024 (build-in-public, no face-cam, pseudonymous). `Raebai` is the user's existing GitHub handle. Local-scope config keeps Legacy Frontier's identity isolated from any other git work on the same machine. The noreply form is GitHub-recognised and routes to the user's real address without exposing it.
- **Alternatives considered:** Real email (rejected — permanent in commit history once repo goes public); a project-themed handle like `@legacyfrontier` (deferred — can switch the config later if the brand wants to be the game rather than the dev; old commits keep `Raebai`).
- **Status:** Locked for now; revisit if a project-themed brand handle is chosen later.
- **Date locked:** 2026-05-05.

## D-029 — Smart App Control disabled on the dev machine

- **Decision:** Smart App Control (SAC) was turned off on the development machine to allow installing Ollama (and the broader set of dev tools required for Tiers 1–8: Aseprite, Stable Diffusion tooling, Steam SDK, etc.). SAC's off state is permanent without an OS reinstall.
- **Reason:** SAC is a security feature designed for non-developer machines; it silently blocks unsigned/low-reputation executables. For a developer machine that will install many dev tools over the project lifetime, SAC creates constant friction in exchange for marginal additional protection beyond what Microsoft Defender, SmartScreen, Firewall, Controlled Folder Access, and Tamper Protection already provide.
- **Alternatives considered:** Run Ollama in WSL2 (rejected for solo + part-time velocity reasons — adds a second OS to manage and re-introduces friction every time another Windows-native dev tool is installed); leave SAC on and avoid Ollama (rejected — Ollama is core infrastructure for the AI-NPC pillar, D-002, non-negotiable).
- **Status:** Locked. Note: SAC cannot be re-enabled without a Windows reinstall; this is a one-way door per Microsoft policy.
- **Date locked:** 2026-05-05.

## D-030 — Adopt Gopeak Godot MCP server for Claude Code ↔ Godot integration

- **Decision:** Use **HaD0Yun/Gopeak-godot-mcp** (MIT-licensed, ~160 stars, v2.3.6 released 2026-04-05) as the bridge between Claude Code and the Godot editor + runtime. Configured at *project* scope via `.mcp.json` (committed to the repo) so any future Claude Code session in this repo auto-loads the same MCP. The Gopeak Godot addons (`auto_reload`, `godot_mcp_runtime`, `godot_mcp_editor`) are vendored under `godot-project/addons/` so the project is reproducible without re-running install scripts. Tool surface limited to the core 33 via `GOPEAK_TOOL_PROFILE=compact` to keep my context window clean; remaining 80+ tools available on demand via Gopeak's `tool.catalog` mechanism.
- **Reason:** v0.0 milestones M2 onward (tilemap, NPC sprite, dialogue UI, Ollama-streamed responses) increasingly require Claude to *see* the running game state — viewport screenshots, runtime scene-tree, node properties — and to *act on it* (run scenes, edit nodes, simulate input). The Tier 1 visibility model (CLI validation + user-pasted screenshots) was sufficient through M1 but becomes a velocity bottleneck once visuals become non-trivial. Gopeak ships 110+ tools covering exactly this surface (`capture_screenshot`, `inspect_runtime_tree`, `scene.create`, `editor.run`, GDScript LSP/DAP, input injection).
- **Alternatives considered:**
  - **Coding-Solo/godot-mcp** (3.4k stars, MIT) — most popular but missing screenshot capture, scene-tree readout, and live editing. Rejected because the user's stated need is exactly those features.
  - **3ddelano/gdai-mcp-plugin-godot** (80 stars, *"All rights reserved"*) — failed the "open source" filter; eliminated immediately.
  - **Tier 1.5 hand-rolled `tools/capture.gd`** (the screenshot-via-headless-script pattern) — kept as backup if Gopeak ever breaks; not chosen as primary because it's screenshot-only with no scene-tree access or interactive control.
- **Status:** Locked. Risks accepted: 110+ tool surface area mitigated by `compact` profile; three localhost ports (6005/6006/7777) opened by addon, localhost-only and standard for IDE-bridge tooling; vendoring third-party GDScript into our `addons/` accepted as the Godot community norm and audited at install time.
- **Date locked:** 2026-05-06.
