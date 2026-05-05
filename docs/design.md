# Design

The full systems specification for Legacy Frontier. Updated as decisions are locked or refined.

---

## Camera and view

**Top-down 3/4 perspective** (Stardew Valley / Pokémon / Albion angle).

- **Default play:** zoomed in on the player, WASD movement on PC, virtual joystick on mobile.
- **Map view:** zoom out to see the wider region — discovered geography, points of interest, your party, other players nearby.
- **Single camera, no separate UI mode for the map.** The zoom is a continuous spectrum.

## World structure

**Hybrid: massive overworld + central Tower with portal-gated floor dungeons.**

- The overworld is one large interconnected map with biomes (forest, plains, coast, mountains, desert, ruins, etc.). Players are all in the same world.
- A central **Tower** dominates the geography — a literal structure in the overworld and the central mystery of the game. Floors of the Tower are accessed via portals at the Tower's base. Each floor is an instanced dungeon zone with its own theme, threats, and lore.
- Lower Tower floors are accessible to all. Higher floors are gated by progression, key items, or NPC permissions.
- Players never see "loading screens" between overworld zones — only when entering Tower-floor instances.

**Persistent expanding world (chunk-based):**

- The overworld is divided into chunks. A chunk doesn't fully exist until a player enters it.
- When a player enters virgin territory, the server generates the chunk deterministically using a seed and biome rules, then stores it forever.
- All players who later visit see the same generated content.
- A world-wide discovery layer marks which chunks have been explored by anyone. On the map, undiscovered chunks are pure fog. You can see other players' frontier from afar.

## Player character

### Creation

- **Classless skill-based progression** (Skyrim / RuneScape model). You become what you do. Use a sword → swordcraft increases. Cast spells → magic schools level. Read books → lore knowledge increases.
- **Races** with mechanical and aesthetic variation (specifics to be designed in Tier 1.5+).
- **No preset destiny.** No "chosen one" framing. You enter as a stranger.

### Stats and progression

- Core stats (TBD: STR, DEX, INT, etc., or skill-only — design in Tier 1.5).
- Skills level through use. Practice makes you better.
- Spells learned from scrolls, NPC teachers, or discovery. Magic schools (specifics in Tier 5).

### Inventory and equipment

- Equipment slots: head, chest, hands, legs, feet, mainhand, offhand, accessory slots.
- Inventory has weight or slot limits (TBD).
- Items have rarity, durability, and optional enchantments.
- Item durability damaged on death (see Death below).

## Combat

**Weapon-based action combat.** Real-time, deliberate, rhythm-driven.

- Each weapon archetype is its own combat feel:
  - Swords: balanced melee, swing arcs.
  - Daggers: fast, light, mobility.
  - Heavy weapons: slow, knockback, stamina-heavy.
  - Bows: ranged, requires aiming.
  - Staves: spell projection, magic-channel weapons.
- **Stamina bar** gates dodge, sprint, heavy attacks, and spellcasting. No stamina = mash-spam combat.
- **Dodge roll with iframes.** Standard ARPG-pattern.
- **Block** for shielded weapons.
- **Status effects:** burn, poison, slow, freeze, bleed.
- **Critical hits** with weapon-dependent crit rates.
- Combo systems and weapon arts are nice-to-haves for later tiers.

**Mobile considerations from day one:**

- All actions map to both keyboard/mouse and touch (left joystick = move, right joystick or tap-to-aim = direction, on-screen hotbar buttons for spells/items).
- Soft auto-aim assist on mobile, off on PC.
- No mechanic requires pixel-perfect mouse aim.

## Magic

**Spell-based magic with multiple schools.** Specifics designed in Tier 5; principles locked now:

- Spells learned from scrolls, NPC teachers, or world discovery (not skill trees you click in a menu).
- **Magic schools** with thematic identity (elemental, scholastic, blood/spirit, etc.). NPCs may belong to specific schools.
- **Cultivation flavour:** spells level through repeated casting. A spell mastered over weeks becomes more powerful, faster, cheaper.
- Magic-school progression intersects with factional reputation (some schools won't teach you if you've wronged them).
- Spell power scales with appropriate stats and equipment (a fire mage with a fire staff casts stronger fire spells).

## NPCs

The most distinctive system in the game.

### Memory and personality

- Each NPC has:
  - A **personality prompt** (defines voice, mannerisms, beliefs, fears).
  - A **memory store** (interactions, observations, gossip received).
  - A **routine** (daily schedule, profession, locations, sleep pattern).
  - **Faction memberships** (with reputation tracked).
- NPCs are powered by Llama 3.2 3B running locally via Ollama for dialogue.
- After interactions, the LLM **consolidates memory** into a per-NPC summary so context doesn't bloat over months of play.
- See `architecture.md` for the LLM-call rules.

### Behaviour

- NPCs follow routines (work, eat, sleep, socialise) driven by code, not LLM calls.
- NPCs interact with each other; relationships, friendships, rivalries form through routine encounters.
- **NPCs gossip.** When NPC A interacts with the player and forms an opinion, there is some probability that opinion propagates to NPC B over time. Your reputation precedes you.
- NPCs can die — to monsters, accidents, age, plague, or player action. Deaths are remembered.
- NPCs have own goals they pursue independently. Some quests exist *because* an NPC has a need.

### Quests

Three sources, combined:

1. **NPC-needs quests.** An NPC has a real need (their daughter is sick, a tool was stolen, a debt is owed). Mechanics are coded; narrative is LLM-written. Quest expires if the need is resolved by another player or by world events.
2. **Village quest boards.** Procedural low-stakes posts (kill X bandits, gather Y herbs, deliver Z parcel). Always available.
3. **World events.** A storm hit a coastal village. A bandit raid is incoming. A monster has been spotted. These quests are *open to anyone* for a window of time, then they are gone — whether you participated or not. This is the strongest expression of "the world is the world."

## Persistent avatar (core pillar)

When you log out, your character continues to exist as a simple-AI NPC.

### Offline mode toggles

- **Safe mode** (default for new players): avatar holed up at an inn or safe location, near-zero offline risk.
- **Adventure mode:** avatar actively seeks quests and travels.
- **Goal mode:** set an objective (travel to X, find Y, befriend Z). Avatar pursues it.
- **Permadeath:** opt-in only. Special server flag.

### World tick

- Real-time clock, accelerated. Default: 1 IRL hour ≈ 1 game day. Tunable.
- World runs in **fast simulation mode** while no players are loaded into a region — probabilistic outcomes, no LLM calls.
- When a player loads in, real-time simulation resumes.

### Chronicle

When you log back in, an LLM-generated **Chronicle** appears:

- Format: **concise paragraph** summary + structured list of stat, item, and relationship deltas.
- Generated locally via Ollama from the world tick log relevant to your avatar.
- Example: *"You spent three days in Ashen Hollow, were hired by Mira the smith to recover stolen tools, befriended a wandering monk, took a wound fighting bandits in the eastern pass, and now carry a strange iron key found in the wreckage."*
- Followed by: `+24 XP swordcraft`, `-1 stamina potion`, `+1 strange iron key`, `+15 reputation with Ashen Hollow`, `+8 friendship with Eron the monk`.

This is one of the strongest retention mechanics in the design.

## Movement and traversal

- **Walking** by default.
- **Mounts** unlock mid-game. Faster than walking but slower than portals. Have stamina, can be killed.
- **Portal network** primarily centered at the Tower base and major settlements. Endgame fast-travel.
- Distances are meaningful but not punishing. World scale tuned during prototyping.

## Death and respawn

**Soft death.** Default for all players unless permadeath flagged.

- Respawn at the nearest safe location (inn, Tower base, last visited shrine).
- **Lose XP** in your most-recently-used skill.
- **Item durability damaged.** Equipment takes a wear hit. Repairs cost in-game currency.
- No item drop on death except in PvP zones (see below).

## PvP

**Designated PvP zones only.** Most of the world is PvE.

- Specific high-risk areas are flagged as PvP-enabled. Often the most dangerous regions also have the best loot.
- In PvP zones: full loot drops on death (some items, possibly equipped gear).
- Outside PvP zones: players cannot attack each other.
- Faction-vs-faction warfare may emerge in late tiers.

## Factions and reputation

Multiple major factions, each with own goals, members, and territory. Examples (provisional):

- **Tower acolytes** — religious/scholarly order around the Tower.
- **Town militias / civic guards** — order-keepers in settlements.
- **Criminal undergrounds** — thieves' guilds, smuggling rings.
- **Magical orders** — schools of magic, each with own membership.
- **Nomadic clans** — wandering peoples with their own customs.

Reputation tracked per faction. Actions affect rep with multiple factions simultaneously (kill a thief = +rep with militia, -rep with thieves' guild). Locked NPC dialogue, quests, vendors, and zones gated by reputation.

## Crafting and economy

**Minimalist.** Not a sandbox-builder game.

- **Gathering professions:** mining, herbalism, fishing, woodcutting.
- **Crafting:** weaponsmithing, alchemy, cooking, basic enchanting. Maybe 5–10 craftable categories total.
- **Player-to-player trade** unlocks emergent player economy.
- **NPC vendors** as price floor and bootstrap supply.
- **Currency** — single in-world currency (TBD name). No real-money currency, ever.

## Building and housing

- **Player housing:** claim a small plot in approved town zones. Decorate the interior. Sleep there.
- **No permanent territory claims** in the open world. The wilderness is shared.
- **Clan halls** later — small shared bases for clans.

## Clans

- Player-formed groups with shared identity, optional clan tag.
- Shared chat channel.
- Shared territory (a clan hall, not wilderness ownership).
- Optional: clan-specific quests and bosses.

## Multiplayer

- ~15–20 concurrent players per world instance/shard.
- Server-authoritative world.
- Persistent shared chunks; offline avatars persist as NPCs.
- Friends list, party invites, in-world chat, party chat, clan chat.

## Time, day/night, seasons

- Real-time game clock, accelerated. Default: 1 IRL hour = 1 game day.
- Day/night cycle affects:
  - NPC routines (work during day, sleep at night, taverns open at dusk).
  - Monster spawns (different creatures by time).
  - Magic potency for some spells.
- **Seasons:** stretch goal. Visual changes, season-specific events.
- **Calendar:** in-world calendar with festivals and recurring events.

## Bosses

**5–7 named world bosses** (Shangri-La Frontier-inspired):

- Each is a uniquely named being with deep lore and historical significance.
- Extreme difficulty. Designed for coordinated parties of multiple players.
- First-kill triggers world-wide announcement and NPC gossip ("I heard a stranger felled the Sleeping King...").
- The world remembers the kill. The NPCs talk about it for weeks.
- Drops are unique and consequential.
- Specific bosses to be designed in Tier 6.

## Onboarding

- New player arrives at the **base of the Tower** via portal, with no equipment and a single starter item.
- Lore framing explains why strangers regularly arrive at the Tower base.
- Tutorial is **baked into early NPC interactions**, not a separate tutorial mode. The first NPC you meet teaches you movement. The second teaches you combat. The third gives you a starter quest.
- No hand-holding "destiny calls" framing. You are a newcomer to an ongoing world.
