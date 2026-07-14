# Task 1 Report — Combat input actions + empty Arena sandbox

**Branch:** `v2.0-tower` (confirmed via `git branch --show-current`)
**Commit:** `d0aa498` — `slice0: combat input actions + empty arena sandbox (run scene -> Arena.tscn)`

## Files changed

- `godot-project/project.godot` (modified)
  - Added `dash` action (InputEventKey, physical_keycode 32 / Space) and `cast` action (InputEventMouseButton, button_index 1 / LMB) to `[input]`, immediately after the `chat={...}` block, matching the existing block formatting exactly (Step 1).
  - Changed `[application] run/main_scene` from `res://scenes/Main.tscn` to `res://scenes/combat/Arena.tscn` (Step 2). Temporary for Slice 0 — restore `Main.tscn` in Slice 1; noted in the commit body per the plan.
- `godot-project/scripts/combat/Arena.gd` (new)
  - Exactly the plan's Step 3 code: `extends Node2D`, doc comment, `ARENA_WIDTH: float = 1200.0`, `ARENA_HEIGHT: float = 680.0`, empty `_ready()`. Tabs for indentation.
- `godot-project/scenes/combat/Arena.tscn` (new, hand-authored)
  - `[gd_scene load_steps=6 format=3]`, syntax matched against `scenes/Player.tscn` (path-based ext_resource, sub_resources, node blocks).
  - Root `Arena` (Node2D) with `Arena.gd` attached via ExtResource.
  - `Floor` ColorRect: offsets 0/0/1200/680, `color = Color(0.14, 0.15, 0.18, 1)`.
  - `Walls` StaticBody2D with four CollisionShape2D children, each a RectangleShape2D per the plan's "easiest reliable form":
    - WallTop pos (600, 0) size (1200, 16)
    - WallBottom pos (600, 680) size (1200, 16)
    - WallLeft pos (0, 340) size (16, 680)
    - WallRight pos (1200, 340) size (16, 680)

## Validation

1. Import:
   ```
   "godot-engine/Godot_v4.6.2-stable_win64_console.exe" --headless --path godot-project --import
   ```
   Result: exit 0. `first_scan_filesystem [ DONE ]`, `loading_editor_layout [ DONE ]`. No errors — only MCP AutoReload/Runtime plugin banner lines.

2. Boot:
   ```
   "godot-engine/Godot_v4.6.2-stable_win64_console.exe" --headless --path godot-project --quit-after 120
   ```
   Result: exit 0. Output was ONLY the Godot banner and `[MCP Runtime] Server listening on port 7777` / `Autoload ready` lines. Zero parse errors, zero script errors. Arena loaded as the main scene and the process exited cleanly after 120 frames.

## Deviations from the plan

- **`--quit-after 120` instead of the plan's `--quit-after 3`** — per the task environment instructions, to give runtime errors time to surface. Boot still passed clean.
- **Commit body added** — the plan's Step 2 says to note the temporary run-scene change in the commit; the plan's one-line message in Step 6 was used verbatim as the subject, with the Main.tscn-restore note (and Co-Authored-By trailer per workspace convention) in the body.
- **`.uid` sidecar follow-up commit** — headless import generated `godot-project/scripts/combat/Arena.gd.uid`. Repo convention (Sessions 4/5) is to commit Godot-generated sidecars, so it landed as follow-up commit `d61fc9f` ("slice0: commit Godot-generated .uid sidecar for Arena.gd").
- No other deviations. Hub/memory files (Conversation.gd, NPC.gd, Player.gd, World.gd, Memory*) untouched; no raw keycodes added to any script (actions live only in project.godot's input map, per D-011).
