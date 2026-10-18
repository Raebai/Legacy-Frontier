# Third-party packs (raw, not imported)

Raw downloads live here, outside godot-project/, so Godot does not import all of it.
Copy only the files a feature uses into godot-project/assets/ and add the credit to
godot-project/assets/audio/CREDITS.md or a sibling CREDITS file. Licences as of 18 Oct 2026.

| Pack | Source | Licence | Use for |
| --- | --- | --- | --- |
| GODOT-VFX-LIBRARY | github.com/haowg/GODOT-VFX-LIBRARY | MIT | 35+ GPUParticles2D effects, 17 shaders (flash, dissolve, outline). Already installed as addons/vfx_library |
| saltmire-fx | github.com/saltmire/saltmire-fx | MIT | one-line hit flash, dissolve, outline, freeze on any CanvasItem |
| saltmire-juice | github.com/saltmire/saltmire-juice | MIT | trauma shake, hit-stop, flash, pooled damage numbers |
| sparkelite | github.com/Sublime-Porte-Studios/sparkelite | MIT | feedback events: shake, hit pause, screen flash, scale punch |
| juice-shaders-lite | github.com/janeduardo19/juice-shaders-lite | MIT | hit_flash, outline, dissolve shaders |
| godot-vfx-2d-free | github.com/Spyridon-Pikoulas/godot-vfx-2d-free | CC BY 4.0 | pure-shader explosion, smoke, spark, fire; resolution independent |
| trauma-gd | github.com/filipbasara/trauma-gd | MIT | camera shake profiles |
| phantom-camera | github.com/ramokz/phantom-camera | MIT | camera follow, zoom, transitions |
| inventory-system | github.com/expressobits/inventory-system | MIT | inventory, equipment slots, crafting, loot; multiplayer example |
| dialogic | github.com/dialogic-godot/dialogic | MIT | dialogue trees for the souls' scripted lines |
| netfox | github.com/foxssake/netfox | MIT | client-server prediction and reconciliation, interpolation |
| Sonniss GDC 2026 bundle | gdc.sonniss.com (in ../../Effects and ~/Downloads) | royalty-free, no credit | all SFX |

| kenney-particle-pack | github.com/Calinou/kenney-particle-pack (mirror of kenney.nl) | CC0 | 80 white 512px particle sprites: sparks, smoke, glows, magic, scorch |

Still to get (needs a browser or a purchase):
Arcane Magic Circles ($4.99, game-dev-goose.itch.io), Scott Buckley music (CC BY, scottbuckley.com.au).

## Tooling (dev only, not shipped)

| Pack | Source | Licence | Use for |
| --- | --- | --- | --- |
| Godot-MCP-Native | github.com/yurineko73/Godot-MCP-Native | MIT | 155-tool editor plugin for Claude Code: run/stop, editor and runtime screenshots with pixel diff, logs, breakpoints, scene and script editing, headless --mcp-server. Replaces the HaD0Yun godot_mcp addons once tested |
| gdUnit4 | github.com/MikeSchulze/gdUnit4 | MIT | headless test runner with input-simulating scene runner, JUnit output, GitHub Action; candidate to sit beside the existing Python runner |
| godot-game-feel-flow | github.com/kezhihao/godot-game-feel-flow | MIT | 77 feel effects and a sequencer, for the legendary-spell-lands moment; heavier than saltmire |
| nakama-godot | github.com/heroiclabs/nakama-godot | Apache-2.0 | client for Nakama: accounts, storage (progression), friends, matchmaking, leaderboards. Server brokers; the Godot headless server stays the authority |
