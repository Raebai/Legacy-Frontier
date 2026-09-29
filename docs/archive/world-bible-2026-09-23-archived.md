
Legacy Frontier — World Bible
 · 
A running record of the game's narrative, world, tone and visual feel. Append-only as sessions happen — nothing here gets rewritten, only added to.

## Core narrative themes
The world is being built around a small set of questions rather than a fixed plot — meant to sit underneath everything, not be answered outright:
- 
What is legacy?
- 
What is freedom?
- 
Why do we crave fantasy?
- 
Why do we do what we do?
Format: giant open-world map, MMORPG, split into distinct zones to explore rather than one linear path. First-person, with live voice chat and open mic between players — both free-roam and progression-gated play need to coexist.
Tone (emphasised): the world should feel genuinely beautiful across wildly different biomes — wild/magic zones, a necro-themed zone, and other distinct areas, each visually striking in its own way rather than reused assets with a palette swap.
Ambition: Raaed is looking to raise funding to build this out for real — no longer just a side hobby project.

## World structure — the cities
Nine cities/regions planned, each visually and tonally distinct:
- 
Starting village, next to a bridge
- 
Capital city — School of Arcana; class teachers are based here, students travel here to study
- 
The dark / the void
- 
Floating island docks — magic-themed
- 
Bunny island
- 
Dragon's den + enchanted forest
- 
Underwater city
- 
TBD
- 
TBD
Plus one hidden city, not on the map, to be discovered.
Other world notes:
- 
Flight — islands in the clouds as a traversal/exploration layer, tied to the "who are we" question
- 
Possible wizard + monk framing for who the player character is
- 
Each class has its own starting base/home area

## Classes, subclasses & magic
8 base classes, each with its own spell dynamics (mage, sword/melee, summoner, healer, and others still to define). Subclasses are meant to feel genuinely unique rather than palette swaps — target is 64 subclasses total across the 8 base classes (8 per class), each with its own visual style.
Unlocking subclasses should feel like a real starting point on a longer path/tier tree — not a throwaway unlock.
Non-combat / living systems:
- 
Living/non-fighter areas — still open whether these exist as a distinct space
- 
Houses to store items — flagged as technically involved and a longer-term build, not early priority
Each class has its own starting base. Clans are a separate layer from classes — guilds that quest together, cutting across the class system.

## AI NPCs & clans
AI NPC behaviour is class- and clan-dependent — not generic across the world.
What the AI needs to be given:
- 
Skill/quality requirements so it can meaningfully join guilds and parties
- 
Awareness of nearby mobs and the player's level, so it can calculate the most efficient action itself rather than following a script
- 
Custom bosses and dungeons it can generate or populate
Open build question: what tooling/tech actually powers this ("how to code → AI NPCs" is flagged as a research item, not yet decided).

## PvP, exploration & dungeons
Bosses: 7 across the map, with AI driving their behaviour (what they lack/can do still being worked out).
MMO dungeons: small groups can enter to clear an arena of mobs and bosses, with hidden items to uncover. Open question: how these differentiate from side quests.
Quests: one main quest per city, with multiple side quests branching off it.
PvP: no dedicated PvP zones — instead, player-killing (PK) gets the attacker flagged, making open-world PvP a risk/consequence system rather than a designated arena.

## Open questions
- 
What are cities 8 and 9?
- 
What do the 7 bosses actually look like / lack, and how does their AI work?
- 
Do dedicated non-fighter "living areas" exist, separate from combat zones?
- 
How do dungeon side quests differentiate from the main quest line per city?
- 
How do we open-source parts of this / build community support over time?
- 
What's the actual tech approach for AI-driven NPCs?
- 
Fundraising: how Raaed wants to position and raise for this as a real venture, not just a build-in-public side project

## Living world & the Soul Engine
Reference: WorldBox. Little bots/creatures living out a world, users and viewers playing live, players feeling like part of a civilisation rather than the centre of it. Quests and dungeons generate as you play; parties get filled out with AI bosses and dungeons. Considered and dropped: a 2D platformer version.
AI Avatar Creator — possible, Terraria-vibes character creation. Tentatively named the "Soul Engine."
Soul Engine concept: every creature in the world — not just NPCs — gets a "soul": a layer that governs how much it can think, speak, and act. Tiered by creature type, e.g.:
- 
0 — can't speak, minimal reaction (a snail)
- 
10 — basic instinct, e.g. a dog running from something that hurt it
- 
70 — complex knowledge and reasoning
Open question (flagged by Raaed): what demands/limits should this scale, so it doesn't become computationally or design-wise unbounded.
Inter-clan systems: clan battles/war, undercover "underworld" clans made up of players who can be boosted with special abilities.

## Visual style & mystery
Core visual feeling: incredibly pretty, floating islands, giant beings and structures, loads of mystery. A world people want to explore for the side-quest lore alone — "deep passion," not filler.
Other recurring images: giant skeletons, beautiful clouds.
Progression loop: legendary weapons with custom crafting and enchanting, working blacksmiths, but combat itself stays skill-based rather than gear-based — loot should feel meaningful without replacing player skill.
Open question: later on the map, what are we actually showing the player? (i.e. what's visible/telegraphed vs. hidden as mystery).

## Tech research (Sep 2026)

### Soul Engine — prior art
No single existing tool is branded a "soul engine," but the pieces exist separately:
- 
theHunter: Call of the Wild is the industry reference case for believable, species-specific animal behaviour — built from real animal-behaviour research rather than generic AI (gamedeveloper.com)
- 
Red Dead Redemption 2's wildlife uses layered ecosystems where animals react to each other and to their place in the food chain, not just to the player (gameopedia.com)
- 
Academic fuzzy-logic models (confidence/behaviour/health inputs driving output behaviour) are the closest thing to a literal "tiered intelligence" system in published research (sciencedirect.com)
- 
The Animal-AI Environment is a comparative-cognition research platform testing AI agents against real animal-cognition benchmarks — useful as a reference for what a 0–70 tier scale should actually be measuring (ncbi.nlm.nih.gov)
- 
For the higher tiers (NPCs that reason and remember), Inworld AI and Unity ML-Agents Toolkit are the current off-the-shelf options — Inworld for conversational NPCs with persistent memory, ML-Agents for reinforcement/imitation-learned behaviour that adapts to how the player plays
- 
Middle-earth: Shadow of War's Nemesis System is the best-known example of NPCs whose behaviour and relationships evolve permanently from player actions — worth studying as a model for the higher soul tiers

### AI-generated open world
- 
Unreal Engine's own PCG Graph plus Houdini Engine integration are the standard route for procedurally generating terrain, architecture and asset layout inside UE5
- 
Promethean AI generates and populates environments from text prompts with spatial logic (weapons near armouries, etc.), and cut one studio's environment build time from roughly 80 hours to a fraction of that
- 
Dungeon Architect (UE5 plugin) procedurally generates dungeon layouts with guaranteed-solvable rules — keys always reachable, no stranded players — and is built natively for Nanite/Lumen
- 
Academic surveys of GPT-driven procedural content generation confirm quests, dialogue and narrative state can already be generated live in response to player choices, not just pre-authored

### Wukong feel → engine choice
Confirms the instinct: Unreal Engine 5 is the right call. Black Myth: Wukong's look comes from a specific combination, not one setting:
- 
Nanite — film-quality, ultra-high-poly assets imported directly with no manual LOD work, which is what gives environments that dense, detailed feel
- 
Lumen — real-time global illumination, so lighting and mood shift naturally through the day/environment instead of being pre-baked
- 
Niagara — particle system used for spell and environmental effects
- 
Chaos physics — destructible environments
- 
Game Science also used photogrammetry/LIDAR scans of real Chinese temples and landmarks to ground the mythology visually — not required for Legacy Frontier, but the underlying lesson is that the "mystery and grandeur" feeling comes from asset density and lighting quality more than raw art direction alone

## Class & spell progression (draft proposal, Sep 2026)
Not yet confirmed — a proposed system for how the 64 subclass combos and spells actually work, drawing on WoW and Sword Art Online.
Structure (revised Sep 2026): the base+secondary pairing is ordered (primary class × secondary class), so it's a genuine grid, not unordered pairs — picking the same class twice (e.g. Warrior + Warrior) is its own named combo on the diagonal.
Leaning toward 7 normal classes + 3 hidden classes (10 total):
- 
The 7 normal classes fully cross-subclass — 7×7 = 49 combos, each with its own name (Warlock + Warrior etc.)
- 
The 3 hidden classes sit outside the grid entirely — not pickable at creation, not subclassable, found/unlocked rather than chosen. Fits the world's existing mystery and hidden-city themes
- 
Open question: do hidden classes get their own separate mini progression system, or are they intentionally simpler (one strong fixed kit, no subclassing) as the trade-off for rarity
Alternative considered: keep all 8 classes cross-subclassable but pull 2 out as hidden → only 6×6 = 36 combos remain for the normal roster, which loses the "64" figure. Passed over in favour of the 7+3 split.
Unlocking (WoW-style): character level gates which spells you have access to — a spell at level 5, another at 10, an ultimate around 40. Clear power curve, matches the "each class has its own starting base" note above.
Power (SAO-style): once a spell is unlocked, its strength is tied to a proficiency stat that climbs from use (cast count or damage dealt), not level — Novice → Adept → Master, each rank adding damage, shorter cooldown, or a bonus effect. Rewards actually playing a build over just levelling.
Build diversity: at certain levels, a WoW-style choice of one of 2–3 variants/passives for an existing spell — diversity inside a combo without a full tree per combo.
Rare tier: SAO-style Extra Skills — abilities not levelled into at all, found from bosses, hidden quests or exploration. Ties into the legendary weapon crafting and mystery notes above.

## Classes — locked roster (Sep 2026)
Resource system — confirmed: one universal mana pool across every class. No bespoke resources per class; classes differentiate through spell cost, cooldown and effect instead. Keeps the system simple.
7 normal (cross-subclassable) classes:
- 
Warrior — melee/sword. Branches into specs at a level milestone (WoW-style): a DPS swordsman spec and a Guardian tank spec, same class and subclass grid either way
- 
Mage — ranged elemental magic
- 
Summoner — controls a bonded creature/construct
- 
Healer — support and restoration
- 
Necromancer — dark magic, curses, minions (the "necro element" from earlier notes)
- 
Ranger — ranged physical + nature hybrid, mobility
- 
Monk — martial arts + ki-flavoured magic
3 hidden classes (not pickable, not subclassable, own separate progression — unlocked only from legendary/rare in-game content; full design TBD):
- 
Voidwalker — space/dark manipulation, tied to the void city
- 
Dragoon — earned by taming or defeating a dragon, tied to the dragon's den city
- 
Soulbinder — binds and channels the souls of slain creatures — its own fantasy hook, not connected to the Soul Engine tech system

### The 49-combo table (primary → secondary, order matters) | 
Primary \ Secondary | 
Warrior | 
Mage | 
Summoner | 
Healer | 
Necromancer | 
Ranger | 
Monk | 
Warrior | 
Blademaster | 
Arcane Knight | 
Beast Knight | 
Crusader | 
Death Knight | 
Wild Knight | 
Zen Knight | 
Mage | 
Battlemage | 
Archmage | 
Beast Sorcerer | 
Sacred Sorcerer | 
Grim Sorcerer | 
Wild Sorcerer | 
Zen Sorcerer | 
Summoner | 
Iron Conjurer | 
Arcane Conjurer | 
Beastlord | 
Sacred Conjurer | 
Grim Conjurer | 
Wild Conjurer | 
Zen Conjurer | 
Healer | 
Paladin | 
Arcane Cleric | 
Beast Cleric | 
Saint | 
Grim Cleric | 
Wild Cleric | 
Zen Cleric | 
Necromancer | 
Reaver | 
Arcane Reaper | 
Beast Reaper | 
Sacred Reaper | 
Lich | 
Wild Reaper | 
Zen Reaper | 
Ranger | 
Iron Hunter | 
Arcane Hunter | 
Beast Hunter | 
Sacred Hunter | 
Grim Hunter | 
Sentinel | 
Zen Hunter | 
Monk | 
Iron Adept | 
Arcane Adept | 
Beast Adept | 
Sacred Adept | 
Grim Adept | 
Wild Adept | 
Grandmaster
Bold diagonal cells (same class twice) are the "pure" mastery path for that class. Names above are a first pass — flavour and mechanics per combo still to design, but the naming logic (role word from primary + modifier from secondary, with a handful of iconic overrides like Battlemage/Death Knight/Paladin) is reusable once real design time goes into each one.

## Spellcasting (first person, draft Sep 2026)
Hard requirement: the game is first person. Casting is built around that rather than ported over from a third-person hotbar system.
Common spells — aim + incantation: first-person reticle aiming, real projectile travel, no tab-target auto-lock — actual aim skill matters. Casting takes a short incantation, audible and visible to nearby players, interruptible by damage or crowd control. Enemies can read and punch through a cast; players can bait fake casts. Ties directly into the SAO mastery system: as a spell's proficiency rank climbs, incantation time shortens, and at Master rank a spell goes silent — near-instant cast with no incantation. A master caster is visibly and audibly different from a novice, not just a bigger number.
Rare/legendary spells (Extra Skill tier) — gesture-drawn: the signature hook. Instead of a hotbar press, the player physically traces a rune shape in the air (mouse-look or right-stick), watching their own hand perform it in first person. Clean, fast trace = full power; botched shape = fizzle or backfire. This is a genuine embodied skill-check that third-person games can only fake with a canned animation — first person lets the player actually do it. Ties into the legendary weapons/mystery tier already in the doc.
Voice tie-in: the planned open-mic/live-chat feature (from the core narrative notes) doubles as part of the incantation system — nearby players genuinely hear spells being cast aloud, adding real tension/readability in PvP and group content.

## Aura system (Sep 2026)
Each character has an aura, detectable once a player reaches a certain level — One Piece Haki as the reference point.
Two layers (draft):
- 
Sensing: passively detect nearby characters' rough power and position, even through terrain, at a range scaling with the sensing player's own level (Observation Haki equivalent)
- 
Projection: once strong enough, a character's own aura becomes visible/felt by others and can pressure or stagger significantly weaker mobs and players (Conqueror's Haki equivalent)
Aura strength scales off total character power (level + spell mastery + gear) rather than its own separate progression track — keeps it simple, and it reads as an emergent signal of real strength.
Ties into the PK-flagging PvP system: a visibly strong aura becomes a real open-world deterrent, not just a cosmetic effect.

## Locked systems decisions (Sep 2026)
- 
Economy: player-driven market, small transaction tax to control inflation
- 
Death penalty: soft respawn nearby + minor gear durability loss outside PK zones
- 
Endgame: rotating world bosses, legendary hunts tied to lore, clan wars
- 
Travel: portals between the 9 cities + earned mounts, no pay-to-skip
- 
Monetisation: cosmetics only, zero pay-to-win
- 
Clan caps: tiered, grows with clan achievements rather than one flat cap
- 
World structure: persistent open world; dungeons are instanced
- 
Day/night & weather: mechanically meaningful — e.g. necromancer stronger at night, healer stronger by day, tied directly into class fantasy
- 
Character customisation: preset archetypes + palette/accessory layers rather than full sliders
- 
Platform: PC first at launch
- 
Anti-cheat: high priority, especially for gesture casting — server-side validated gesture recognition with timing variance checks to close the "macro draws a perfect shape instantly" exploit
- 
Onboarding: starting village (city 1) doubles as the tutorial; class trainer NPCs ramp gesture-casting complexity gradually
- 
Empty party roles: NOT auto-filled — AI NPCs only join a party if the player explicitly hires them
- 
Servers: sharded/shared realms for now, with cross-realm world-boss events; single mega-server is the long-term goal once population supports it
- 
Dungeon/raid difficulty: Normal / Hard / Legendary tiers, rewards scale with each
- 
Legendary items: a combination of RNG drops and quest/lore-tied sourcing, not purely one or the other
- 
Cross-clan trading: allowed, with a safe-trade window; clan halls double as trade hubs
- 
Localisation: English only at launch
- 
PvP: optional structured arenas alongside the open-world PK-flagging system
- 
First build target (investor demo): one city, one class fully playable end to end — spell tiers, mastery, gesture casting — plus one dungeon

## Dev tooling (locked, Sep 2026)
Editor-control layer: UnrealGenAISupport — free, MIT-licensed, supports UE5.4–5.7+. Runs an MCP server inside the UE5 project that a Claude session connects to directly once linked to Raaed's PC: spawns objects, generates blueprints, runs Python inside the editor, adjusts materials, runs console commands. This is what lets the daily headless build loop turn into real in-editor progress rather than just prepped files waiting to be imported. Project should be backed up before use — direct editor write access.
Fallback if unstable: Unreal Engine Agent, a leaner Go-based MCP server (49 tools), targeting UE 5.7 specifically.
Dev loop: a scheduled task fires hourly, works through the build backlog (kept in the project repo, not this doc), commits progress, and once the backlog is clear loops backward through completed work to optimise it — continuous rather than one task a day. Editor-touching steps are flagged for Raaed's PC rather than attempted headlessly.

## Budget (research, Sep 2026)
Free/already covered: Unreal Engine 5 ($0 until $1M lifetime revenue, then 5% royalty, 3.5% same-day Epic Games Store, 0% Epic-exclusive), UnrealGenAISupport (MIT-licensed), this dev environment, GitHub free tier.
Real spend for the demo slice (1 city, 1 class, 1 dungeon): marketplace character/animation/VFX assets via Fab — roughly £400–2,500 (Quixel Megascans textures are free inside UE5, the spend is rigs/animation/VFX); optional NPC voice/TTS ≈ £4–20/month. Realistic demo-slice total: £500–3,000, mostly asset packs — versus $15K–150K / 6–14 months for a conventionally staffed 3–8 person indie prototype team. The AI dev loop is substituting for most of that labour cost.
AI playtesting exists: modl.ai's modl:test deploys AI bots that play the game to find bugs/edge cases at scale (used by Rare on Sea of Thieves). Integrates with Unreal Engine. Pricing not public, reads as enterprise/custom, sales-contact only — revisit once there's a playable build, not needed for the demo.
HARD CAP: £1,000 (locked, Sep 2026). Allocation: character base mesh + animation set (Warrior) £250–350; starting village environment/prop kit £200–300; spell/gesture-cast VFX pack £100–150; NPC voice/TTS ~£50 (first cut if tight); buffer £150–250. This buys good stock assets that read as cohesive, not a fully custom visual identity — fine for proving mechanics and the gesture-casting hook to investors; a from-scratch art style is a later-round expense.
Not yet costed: legal/incorporation for the raise itself, asset spend for full 9-city scope beyond the demo, server/hosting once past local co-op testing.

## Demo goal, revised (Sep 2026)
The demo isn't just proving the systems work — it needs to convince investors AND be good enough to clip and go viral on social. That means concentrating effort and spend into one unmistakable money shot rather than spreading polish thin across the whole slice.
The money shot: the gesture-cast legendary spell finishing the boss fight, in slow motion, rune trace clearly visible. The village-to-dungeon-to-boss playthrough exists to set this moment up, not to be broad content in its own right. Session length tightened to 3–5 minutes of actual playthrough.
Capture: 60fps+ via OBS (free). Reuses the already-locked stick-fight-game clip format — 30–40s, deep trailer-style narrator voiceover, colour-vs-colour framing — rather than inventing a new one.
Budget reallocated within the £1,000 cap: spell/gesture-cast VFX pack £300–400 (now the top line item), character base mesh + animation £250–350, environment kit £150–250, buffer £50–100. NPC voice/TTS cut entirely. Full breakdown in the project repo's Docs/BUDGET.md.