# Vision

## The pitch

Legacy Frontier is a 2D pixel-art top-down RPG where every NPC has persistent memory and personality, and your character continues to exist as an NPC when you log out. The world ticks forward without you. When you log back in, a Chronicle tells you what your character did while you were away.

Inspired by Terraria's exploration, Tower of God's vertical worldbuilding, Shangri-La Frontier's living-world feel, and Skyrim's atmospheric depth, the game blends cozy pixel-art adventure with AI-driven character depth no other game has cracked yet. Up to ~20 players share each persistent world.

## Core design principle: *The world is the world*

The most important sentence in this document.

The world exists on its own terms. It ticks whether you're there or not. NPCs have their own goals, fears, relationships, and deaths. You are a participant, not a protagonist. Heroism still exists — it's just not handed to you.

What this means concretely:

- **No "main quest for the player."** There is a central mystery (what is at the top of the Tower?) but it belongs to the world, not to any individual player. Anyone can pursue it. Many never will.
- **NPCs do not exist for you.** They have their own routines, fears, goals. They can complete quests without you. They can die without you. They will move on if you ghost them for a month.
- **Permanent consequences.** A war can end before you hear about it. A village can fall while you were elsewhere. You can miss events forever.
- **News and rumour propagate through NPCs.** Travellers tell stories. Tavern gossip carries. Ruins remember. The world tells you what happened — sometimes through people, sometimes through environments.
- **Your impact is real but localised.** You can change a town. You cannot single-handedly save the world.

**Design test:** "Does this feature make the world bend to the player?" If yes, kill it.

## Pillars

Four mechanics that define what makes Legacy Frontier different from every other 2D RPG:

1. **AI NPCs with memory and personality.** Each NPC has a persistent memory store. They remember what you said, what you did, who you wronged, who you helped. They reference past interactions naturally. NPCs gossip about you to each other — your reputation precedes you.

2. **Persistent player avatar.** When you log out, your character does not vanish. They become a simple-AI NPC who continues to live in the world — wandering, working, traveling, defending. Other players can interact with your avatar. World events affect them. When you log back in, you receive a Chronicle: a concise paragraph summarising what happened, plus the stat, item, and relationship deltas. This is the strongest retention mechanic in the design.

3. **AI party members.** You can recruit NPCs to follow you, fight alongside you, and converse with you. They remember the adventures. They can teach you spells. They have opinions about your actions.

4. **Viewer-named NPCs.** Twitch chat (and similar) integration: viewers' usernames spawn as NPCs in the streamer's session and persist permanently in the world. This is a viral hook baked directly into gameplay.

## Inspirations and tonal references

- **Terraria** — sandbox exploration, sense of vast world, creature variety, dungeon descent.
- **Tower of God** — vertical worldbuilding, ascending mystery, dense lore-rich societies, factional depth.
- **Shangri-La Frontier** — game-as-living-thing feel, sense that the world predates you and continues without you, hardcore difficulty in places.
- **Skyrim** — open-world depth, atmosphere, sense that even minor NPCs have routines and stories, weight of choice.
- **Adjacent vibes:** Hollow Knight's atmospheric mystery, Stardew Valley's NPC warmth, RuneScape's persistent-world sociality, Albion Online's top-down PvP architecture.

**Tonal direction:** atmospheric mystery with light isekai/fantasy texture. Friendly enough on the surface; deeper weirdness underneath. Light fantasy by default; darker undertones in deep regions and Tower upper floors.

## Target audience

- Players who love RPGs with depth (Skyrim, Elden Ring fans willing to slow down for a top-down 2D experience)
- Sandbox/exploration fans (Terraria, Stardew, Minecraft)
- Anime/light-novel readers drawn to isekai and Shangri-La Frontier-style worlds
- Streamers and their audiences (gameplay generates content; viewer-NPCs make engagement transactional)
- AI-curious gamers wanting to see what current LLMs can do for in-game character depth

## What this game is *not*

Worth being explicit so we don't drift:

- **Not a civilisation simulator.** No kingdoms-at-war, no nation politics, no rise-and-fall macroeconomics. NPCs are individuals, settlements stay small.
- **Not a Terraria-style sideview platformer.** Top-down 3/4 perspective. Vertical mystery is delivered via the Tower (a structure in the world), not via mining depth.
- **Not a god-simulator.** No god-mode, no world editor, no terraforming tools. Everyone plays as a character. (Originally considered, deliberately removed — see decisions.md.)
- **Not a true MMO.** Target ~20 concurrent players per world instance, not thousands. Persistent and shared, but small-scale.
- **Not a fast-paced action game.** Combat is real-time and deliberate. Exploration is intentional. The pace is contemplative.
- **Not buy-to-play with predatory monetisation.** Buy-once base game. No loot boxes, no energy systems, no paywalled content.

## What success looks like

In rough order of urgency:

1. **v0.0 ships and the magic moment lands.** A single NPC who remembers a player across save loads, in a way that genuinely feels alive. If this fails, nothing else matters.
2. **An MCP (playable vertical slice) that captures all four pillars** in a small handcrafted region. Demonstrable to publishers, streamers, and a Kickstarter audience.
3. **Public alpha with active community.** Discord, social, devlog audience. This is the funding flywheel.
4. **Multiplayer foundation** with ~20 players per world, persistent shared geography, viewer-NPCs working.
5. **Public launch.** Steam premium release, modest cosmetic monetisation, sustainable studio.
