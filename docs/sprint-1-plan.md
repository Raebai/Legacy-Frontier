# Sprint 1 / v0.0 Plan — The Seed

The plan to deliver **Tier 1 / v0.0** from `roadmap.md`: one NPC who genuinely remembers the player across save loads.

We are **skipping Sprint 0** entirely (decision D-026). The user is learning by reading the code I write, not by completing tutorials. Every milestone introduces Godot concepts inline as they appear, in 1–2 sentence explanations. If at any point velocity feels too high, the user says *"explain that"* and we pause.

---

## Definition of done — the whole sprint

- One Godot scene, one tilemap (placeholder coloured tiles).
- Player character moves with WASD on PC and a virtual joystick on mobile (input architecture must be touch-friendly from day one — D-011).
- A camera follows the player smoothly.
- Walls block movement.
- One NPC sprite stands somewhere on the map.
- Walking near the NPC and pressing **E** opens a dialogue UI overlay.
- The dialogue UI hits the local Ollama HTTP API at `http://localhost:11434/api/generate`, sending: NPC personality prompt + prior conversation history + the player's current input.
- The LLM response streams into the dialogue UI as it arrives.
- The conversation transcript is persisted to a JSON file under Godot's `user://` directory after every exchange.
- On the *next* game launch, the NPC's prior history is loaded back from disk; the LLM receives it as context and naturally references things you said in the previous session.

**The magic moment we are shooting for:** quit Godot mid-conversation, restart, walk back up to the NPC, and have it pick up where you left off — referencing something specific. *That* is v0.0.

---

## Milestone-by-milestone

### Milestone 1 — Godot project + WASD-controlled square *(visible on screen by end of this milestone)*

**What we build:** the Godot 4 project itself, scaffolded inside `godot-project/` per architecture.md. A single scene with a coloured square the user can move around with WASD. No tilemap, no NPC, nothing else yet — the goal is "I can see something move."

**Godot concepts introduced inline:**
- *Project (`project.godot`):* the file Godot reads to know what's a project. Open this folder in Godot and it loads the whole thing.
- *Scene (`.tscn`):* a tree of nodes saved as a file. Roughly: a "screen" or a "prefab." The game's running scene is whatever's marked as the main scene.
- *Node:* the unit Godot is built from. Everything is a node. Some nodes have visual representation, some are pure logic.
- *`CharacterBody2D`:* the standard 2D node for a player or moveable character with physics. It has built-in helpers for movement and collision.
- *`_process(delta)`:* a function Godot calls on every frame; `delta` is the seconds since the last frame. This is where WASD reads happen.
- *Input map:* Godot's abstraction layer between physical keys and game actions. We register `move_up`, `move_down`, `move_left`, `move_right` as actions, bound to W/A/S/D *and* arrow keys *and* (later) virtual joystick events. Code only ever asks "is `move_left` pressed?" — never "is A pressed?". This is what makes mobile-first input architecture work without rewriting code (D-011).

**Done when:**
- Pressing F5 in the Godot editor opens a window with a coloured square.
- WASD moves the square in all four directions, including diagonally.
- Releasing a key stops movement immediately.

**One thing for the user to do:** open the Godot editor at `godot-engine\Godot_v4.6.2-stable_win64.exe`, point it at `godot-project/`, hit F5.

**Commit:** `M1: Godot project bootstrap + WASD-controlled placeholder character`

---

### Milestone 2 — Tilemap, camera follow, wall collisions

**What we build:** a small placeholder tilemap (~16×12 tiles, simple grass + stone-wall theme; coloured rectangles fine for art). The player can't walk through walls. A `Camera2D` follows the player smoothly so the world feels bigger than the viewport.

**Godot concepts introduced inline:**
- *`TileMapLayer`:* the node that paints a 2D grid of tiles. We give it a tileset (a palette of tile types).
- *`TileSet`:* the palette resource — defines what tiles exist, their textures, and which ones have collision.
- *Collision shape:* a separate child node attached to physics-aware nodes that defines the actual hitbox.
- *`Camera2D`:* a node that becomes the active camera when present. Smooth-follow is a built-in property.

**Done when:**
- Walking the player around reveals a tile-based room with visible walls.
- Walls block player movement.
- The camera follows the player smoothly without jitter.

**Commit:** `M2: tilemap + Camera2D follow + wall collisions`

---

### Milestone 3 — NPC entity with proximity detection

**What we build:** a static NPC sprite (different colour from the player) placed somewhere on the map. When the player walks within ~32 px of the NPC, a small `[E] Talk` hint appears above the NPC. When the player walks away, the hint disappears.

**Godot concepts introduced inline:**
- *`Area2D`:* a node that detects overlap with other physics bodies but doesn't *block* them. Perfect for proximity triggers.
- *Signals:* Godot's event system — nodes emit signals (e.g., `body_entered`), other nodes connect to them. This is how "player got close to NPC" turns into "show the hint."
- *Resource-style data:* we'll define the NPC's identity (name, personality prompt) as a small resource attached to the NPC node, so the same NPC scene can be reused for different characters later.

**Done when:**
- Approaching the NPC shows the hint label.
- Walking away hides it.
- The label position floats above the NPC, not the player.

**Commit:** `M3: NPC entity scene with proximity-triggered interaction hint`

---

### Milestone 4 — Dialogue UI scaffold *(no LLM yet — placeholder echo)*

**What we build:** pressing **E** while the proximity hint is visible opens a full dialogue UI overlay. The UI has: NPC name banner, message history pane, single-line text input, and a way to close (E again or Esc). For this milestone, the NPC just echoes the player's input back with `"[NPC]: I heard you say: ..."` — no LLM yet. This isolates the UI work.

**Godot concepts introduced inline:**
- *`Control` nodes:* Godot's UI system. A different family from the 2D world nodes. They live on a `CanvasLayer` so they render on top regardless of camera position.
- *`CanvasLayer`:* renders its children on a layer above the world, immune to the camera transform.
- *`LineEdit`:* a single-line text input control.
- *`RichTextLabel`:* a multi-line text display that supports BBCode (bold, colour, etc.) — useful for distinguishing player vs. NPC messages later.

**Done when:**
- Walk up, press E → dialogue opens, world dims slightly behind it.
- Type a message, press Enter → it appears in the history pane, NPC echoes back.
- Press E or Esc → dialogue closes, you're back to walking around.

**Commit:** `M4: dialogue UI overlay with placeholder echo NPC`

---

### Milestone 5 — Ollama integration: real LLM responses *(blocked on model pull)*

**What we build:** swap the placeholder echo for a real call to the local Ollama HTTP API. The NPC has a hardcoded personality prompt (we'll write it together — first NPC personality is open per CLAUDE.md). When the player sends a message, GDScript POSTs to `http://localhost:11434/api/generate` with the personality + the message, and streams the response into the dialogue history pane as it arrives.

**Godot concepts introduced inline:**
- *`HTTPRequest`:* Godot's built-in node for HTTP calls. Async by design — emits a signal when the response arrives.
- *`JSON.stringify` / `JSON.parse_string`:* GDScript helpers for the request body and response.
- *Streaming:* Ollama's `/api/generate` supports `stream: true`, returning newline-delimited JSON chunks. We append each chunk to the UI as it arrives so the NPC appears to type, not freeze.
- *Architectural rule recap (architecture.md):* this is one of the *deliberate* moments where we call the LLM. Movement, collision, hints — never call the LLM. Dialogue — call the LLM. Hold this line.

**Done when:**
- Type a message → real Llama 3.2 3B response streams into the dialogue pane.
- Latency feels acceptable (1–5 s on first response, faster after model is hot).
- If Ollama isn't running, the dialogue shows a clear error and stays usable.

**Blocker:** requires `llama3.2:3b` pulled (currently pending). Step 4 of the setup plan also tests this; that test is the precursor to this milestone.

**Commit:** `M5: live Ollama integration with streamed NPC dialogue`

---

### Milestone 6 — In-session conversation history

**What we build:** the NPC remembers what was said *during the current session*. Every player message and NPC response is appended to a per-NPC history list in memory. On every new turn, we send the full history (within token bounds) along with the new player input, so the LLM has context. This is the *short-term memory* tier from architecture.md — no consolidation yet.

**Godot concepts introduced inline:**
- *Autoload / singleton:* a script that lives for the whole game session, accessible from any scene. Perfect home for `MemoryManager` — the thing that owns conversation histories.
- *`Array` of `Dictionary`:* GDScript's standard for "list of structured records." Each turn is `{role: "player"|"npc", text: "..."}`.
- *Architectural foreshadowing:* this is the structure that will later be consolidated into long-term memory by an LLM call (architecture.md's memory lifecycle). We're laying the foundation here, not building consolidation in v0.0 — Tier 2 territory.

**Done when:**
- Send three messages in a row → the NPC's third response demonstrably references the first two.
- E.g.: tell the NPC your name, ask an unrelated question, then ask "do you remember my name?" — it should.

**Commit:** `M6: in-session conversation history with context-aware LLM calls`

---

### Milestone 7 — Persistence: JSON save/load *(the magic moment)*

**What we build:** every time a dialogue closes, the NPC's history is written to a JSON file at `user://npc_memory/<npc_id>.json`. On NPC initialisation (game launch), the file is read back and the conversation history is restored. The LLM now receives history that survives Godot quitting.

**Godot concepts introduced inline:**
- *`user://` path:* Godot's per-user data directory (on Windows: `%APPDATA%\Godot\app_userdata\<project_name>\`). Save files live here, not next to the executable.
- *`FileAccess`:* Godot's file I/O API. We open in WRITE for save, READ for load.
- *JSON serialisation:* same `JSON.stringify` / `JSON.parse_string` helpers from M5.
- *Deferred save vs. immediate:* we'll save on dialogue close to avoid disk I/O per turn. If Godot crashes mid-conversation we lose the in-flight exchange — acceptable for v0.0; tighten later.

**Done when:**
- Have a conversation with the NPC. Mention something specific (e.g., "my name is Raaed and I love tigers").
- Close Godot.
- Re-launch Godot. Walk back to the NPC. Open dialogue.
- Ask: "do you remember anything about me?"
- The NPC references the name *and* the tigers, unprompted.

**This is the moment v0.0 is "done" in the spirit of roadmap.md.**

**Commit:** `M7: persistent NPC memory via JSON — the seed magic moment`

---

### Milestone 8 — Polish, robustness, and a manual test checklist

**What we build:** the difference between "it worked once on my machine" and "it's reliable enough to film for the build-in-public content beat." Specifically:

- **Loading state:** a "..." or shimmering label while the LLM is generating, so the UI never appears frozen.
- **Error handling:** Ollama not running → clear message. Model not loaded → clear message. Network timeout → clear message. None of these crash the game.
- **Input edge cases:** empty input rejected. Very long input clipped or warned. Repeated rapid Enter presses ignored while a response is generating.
- **Visual contrast pass:** placeholder art remains, but tweak colours so the player, NPC, and tiles are clearly distinguishable on a recording.
- **Manual test checklist** added to `docs/v0.0-test-checklist.md` — the steps anyone (including future-you) follows to confirm v0.0 still works.
- **Mobile input verification:** even though we're recording on PC for the content beat, confirm the input map still resolves on touch — we don't break D-011 silently.

**Done when:**
- The full magic-moment loop (talk → quit → restart → NPC remembers) is reproducible from the test checklist three times in a row, no surprises.
- A 60-second screen recording of the loop is something you'd be willing to post.

**Commit:** `M8: error handling, loading state, polish + v0.0 test checklist`

---

## Out of scope for v0.0 *(deliberately deferred)*

These are tempting but explicitly *not* in this sprint, per roadmap.md and the discipline rule in CLAUDE.md:

- Multiple NPCs *(Tier 2 — MCP)*
- Combat / stats / inventory *(Tier 1.5)*
- NPC routines (work, sleep, eat) *(Tier 2)*
- NPC-to-NPC gossip propagation *(Tier 2)*
- Memory consolidation via LLM *(Tier 2 — bounded-context architecture)*
- Persistent player avatar / Chronicle *(Tier 2)*
- Quests *(Tier 2)*
- Magic, factions, PvP, mounts, housing, clans *(later tiers)*
- Multiplayer of any kind *(Tier 4)*

If the urge to build any of these creeps in mid-milestone: kill it. v0.0 is *one NPC remembering*. That is the entire job.

---

## Risk register

- **LLM latency on first call:** 5–15 s while the model warms. If it's worse on the user's hardware, we add a "thinking..." indicator early (M5) and don't optimise further until v0.0 ships.
- **JSON corruption from a crash mid-write:** mitigated by writing to a temp file then renaming (atomic on Windows). M7 will use this pattern.
- **Personality prompt drift:** the LLM may forget personality after enough turns. Acceptable in v0.0 because we re-prepend the personality on every call. Real fix is consolidation, deferred to Tier 2.
- **Streaming response parsing:** newline-delimited JSON streaming in GDScript is mildly annoying. If it eats >2 hours in M5, we fall back to non-streamed responses and add a "thinking" UI; can revisit streaming as M8 polish.

---

## Cadence and review

Per-milestone cycle (from the operating rules):

1. I write the code and scene work.
2. I run / test where I can; I give the user one specific GUI action ("open Godot, hit F5, tell me what you see").
3. I show the diff.
4. User approves or redirects.
5. I commit, append a Session Context Update to `CLAUDE.md`, mark the milestone complete.
6. Move to the next milestone.

No batched commits across milestones. No surprises. No code that wasn't shown in a diff first.
