# Funding & Resources

How to fund Legacy Frontier and where to find tools, libraries, and infrastructure.

---

## Funding strategy: MCP-first

The locked principle: **self-fund through the MCP. Don't pursue funding until there's something playable.**

Pre-prototype, almost no funder will write a check. With an MCP (Tier 2 vertical slice) and a real audience, every door opens. Until then, every hour spent pitching is an hour not spent building.

### Phasing

| Phase | Tier | Funding model |
|-------|------|---------------|
| 0 | Sprint 0 → v0.0 | Self-fund. Costs: ~£0–£100 (Aseprite, free engine, free LLM). |
| 1 | Tier 1.5 → 2 | Self-fund + early Patreon. Audience-building begins. Costs: £100s/month for tooling + commissioned art if needed. |
| 2 | Tier 2 ships (MCP) | **Funding window opens.** Kickstarter, publisher pitches, UK Games Fund, indie publishers. |
| 3 | Tier 3 → 4 | Whatever was raised in Phase 2 funds development. Patreon continues. Possibly second funding round. |
| 4 | Tier 5+ | Studio formation if game is succeeding. VC potentially relevant. Or stay solo if numbers support it. |

---

## Funding sources

### UK-specific (your strongest plays as a UK resident)

#### UK Games Fund

The UK Games Fund got a major refresh in April 2026 with a £28.5m budget over three years. Three funding tracks:

- **Starter Fund (Entry Track) — up to £20,000.** For solo developers and university grad companies. Covers UK-based labour costs only. Two pathways: Head Start (more experience) or Fresh Start (early-stage with more business support).
- **Prototype Fund (Emergent Track) — up to £100,000.** For established SMEs with at least one PAYE employee, typically 3–10 person studios. **Not for solo developers** in their current solo form — would require setting up a UK Ltd with PAYE registration first.
- **Content Fund (Expansion Track) — up to £250,000.** For established studios with track records.

**Important catch:** UK Games Fund requires a UK-registered company, PAYE registration, and UK-domiciled labour spend. Logara AI (Singapore) doesn't qualify. Need a separate UK Ltd specifically for Legacy Frontier — easy and cheap (~£12 + a few forms via Companies House), but it's a step.

**For your situation:** Starter Fund is the realistic entry point once you have an MCP. Prototype Fund becomes viable once you incorporate UK Ltd and have at least one PAYE setup (could be yourself part-time).

Apply via https://ukgamesfund.com — watch their funding round announcements.

#### Video Games Tax Relief / Video Games Expenditure Credit (VGEC)

UK has actual tax relief for "British" video games (passing the cultural test administered by the BFI). Once Legacy Frontier is a UK Ltd with development spend, this recoups a meaningful chunk of dev cost (roughly 25–35% effective rate on qualifying expenditure, depending on year and rules).

Worth a tax advisor conversation once revenue or major spend starts.

#### Innovate UK

Has occasional digital and creative sector grants. Less specific to games than UK Games Fund but worth monitoring.

---

### Publishers (approach only after MCP exists)

Most publishers want a vertical slice + audience metrics before committing. Categorised by typical investment size.

#### $1M+ tier
- **Devolver Digital** — quirky, innovative, creative freedom; strong fit for Legacy Frontier's hook
- **Annapurna Interactive** — narrative-driven, artistic
- **Raw Fury** — strong indie partner; "interesting mechanics" is their brand
- **Hooded Horse** — strategy / sim leaning (less fit for Legacy Frontier specifically)
- **Playstack**
- **11 Bit Studios**
- **Yogscast Games**

#### $250K–$1M tier
- **Bigmode** — Dunkey's label, focused on standout games
- **Curve Games**
- **Panic** — high creative bar
- **Critical Reflex**

#### Under $250K tier
- **Digital Pajamas**
- **Poncle**
- Many smaller publishers — useful primarily for marketing + platform relationships

**For Legacy Frontier specifically:** Devolver, Raw Fury, Annapurna, Bigmode are the strongest fits given the AI-NPC hook and atmospheric mystery tone. Hooded Horse skews wrong genre.

#### Standard publisher deal mechanics

- Publisher invests $250K–$1M+ as advance against royalties
- Recoup model: publisher recovers advance from sales first
- Post-recoup: revenue split, typically 30–50% to publisher
- IP retention: confirm you keep IP. Walk if you don't.
- Marketing, platform deals, QA, localisation usually included

Red flags: vague contract language, demands for IP rights without major investment, lack of transparency about previous launches, pressure to sign quickly.

---

### Funds and investors

#### Indie Fund
- Founder-friendly terms: monthly payments during dev; repayment is initial investment back + 25% revenue share for first 2 years, capped at double the investment
- **You don't apply directly.** The fund watches the indie scene and approaches teams whose games they notice
- Implication: visibility (build-in-public, audience size) is your application
- https://indie-fund.com/

#### Blue Ocean Games
- $30M fund launched in 2026, backed by Krafton
- Specifically targets early-stage indie devs who have *community validation* rather than proven track record
- Plans to back ~100 studios over three years
- Highly relevant if your build-in-public audience is real

#### Bitkraft Ventures
- Gaming-focused VC. Earlier-stage, larger checks
- Better fit for studio-building than single-game funding

#### a16z Games
- Andreessen Horowitz's gaming arm
- Skews toward bigger swings; studio formation, not pre-MCP indie

#### Xsolla Funding
- Connects developers to 250+ investors and publishers via pitch events and online portal
- About 1 in 10 applicants gets a match
- Good for getting in front of multiple funders at once
- https://xsolla.com/funding

---

### Crowdfunding

#### Kickstarter
- ~35–40% success rate for game projects. Audience pre-existing dramatically improves these odds
- Best when you have a vertical slice + active community
- Build-in-public audience IS the funding flywheel
- Time the launch carefully — campaign should hit when audience is hot

#### Fig
- Game-specific platform; can offer revenue share to backers
- Smaller than Kickstarter; less generic-audience reach but more game-savvy backers

#### Patreon
- **Especially relevant for Legacy Frontier.** Build-in-public model is Patreon-native: monthly devlogs, behind-the-scenes content, supporter-named NPCs as a tier reward
- Realistic monthly income at small scale (£200–£500/month) covers asset / tooling budget while building audience
- Ladder reward tiers carefully — your scarcest commodity is in-game NPC slots, so price them well

---

### Grants

Beyond UK Games Fund:

- **Epic MegaGrants — disqualified.** They require Unreal Engine. Don't switch engines for the grant.
- **Creative Europe** — EU funding for cultural/creative projects. Eligibility is an EU member; UK post-Brexit eligibility varies by programme. Check current rules.
- **IGDA Foundation Diverse Game Developers Fund** — supports marginalised developers
- **Unity for Humanity** — for projects with social impact
- **NEOM Gaming Level Up (Saudi)** — Saudi-based studios primarily; relevant only via partnerships

---

## Tools and resources

### Game engine and AI runtime

- **Godot 4** — https://godotengine.org/download. Free.
- **Ollama** — https://ollama.com. Free local LLM runner.
- **Llama 3.2 3B model** — `ollama pull llama3.2:3b` after Ollama install. Free.
- **VS Code** with Godot extension for non-engine scripting.
- **Aseprite** (~$20) or **LibreSprite** (free) for pixel art.

### AI sprite generation
- **PixelLab.ai** — purpose-built for game devs; sprites, animations, multi-direction rotations, tilesets. Free tier + paid plans.
- **Sprite-AI** (sprite-ai.art) — exact pixel sizing, built-in editor. Free tier; paid from $5/month.
- **Pixie.haus** — true 1:1 grid snapping, image-to-image consistency.
- **Stable Diffusion + pixel-art LoRAs** (via `diffusers` or `comfyui`) — DIY, free, runs on NVIDIA GPU.
- **Adobe Firefly** — broader AI generation; commercial-safe but not pixel-specific.

### Pixel art asset libraries

- **itch.io game assets** — biggest marketplace; both free and paid. Search tags: `pixel-art`, `top-down`, `RPG`, `Godot`. https://itch.io/game-assets
- **Kenney.nl** — free, CC0, prototyping gold. https://kenney.nl
- **OpenGameArt.org** — free, mixed quality, search-heavy.
- **CraftPix** — paid themed RPG asset packs.
- **Topdown Pixelart Starter Project** for Godot — free MIT-licensed template with 2 levels, quests, combat, talking NPCs (excellent reference for v0.0). https://godotengine.org/asset-library/asset/2397

### Notable pixel artists on itch.io
- **LimeZu** — high-quality 16×16 RPG tilesets (modern interiors/exteriors, fantasy)
- **HoriHoriPixel** — character / background / portrait packs
- **Penzilla** — characters and portraits
- **Cup Nooble** — fantasy outdoor / dungeon tilesets

### Music libraries

- **Soundimage.org** (Eric Matyas) — gigantic free fantasy game music. Tracks like *Some Dreamy Place*, *Fantascape*, *Magic Ocean* fit the brief.
- **Tabletop Audio** — atmospheric ambient tracks made for tabletop RPGs; transfer perfectly.
- **WOW Sound** — 700+ loopable DMCA-safe tracks, commercial-use licensed.
- **Dark Fantasy Studio** — royalty-free music packs across horror, epic, ambient, action.
- **itch.io** music tag (free section) — many indie composers offering free or pay-what-you-want.
- **Pixabay Music** + **Free Music Archive** — broad CC libraries.

### Sound effects

- **Freesound.org** — Creative Commons SFX library
- **Kenney's audio packs** — free CC0
- **ZapSplat** — free with account

### Godot learning resources

- **Heartbeast** (YouTube) — best free Godot 4 tutorials, including 2D ARPG series
- **GDQuest** — free + premium courses, very high quality
- **Godot docs** — surprisingly readable. The official tutorials are Sprint 0.
- **Godot Asset Library** — built into Godot itself; free addons and templates.

### Hosting and infra (for later tiers)

- **Hetzner** — cheap dedicated servers, good for indie alpha hosting
- **DigitalOcean / Linode** — VPS, friendly UX
- **AWS Lightsail** — simpler AWS for small servers
- **Cloudflare** — DNS, CDN, DDoS protection. Free tier covers small projects.

### Analytics and telemetry (deferred)

- **GameAnalytics** — free, indie-friendly
- **Sentry** — error reporting; generous free tier

### Community infrastructure

- **Discord** — community hub. Free.
- **Substack** or **Beehiiv** — long-form devlog newsletter. Optional.
- **Steam developer account** — $100 one-time fee for first game release

### Legal / business

- **Companies House** (UK) — incorporate UK Ltd, ~£12.
- Indie game lawyer — useful when signing publisher deals. Networks like SpritesAndDice (private) or Games & The Law are worth seeking out near contract time.

### Publisher / pitch resources

- **IndieGameBusiness** — list of 1,400+ game investors and publishers (newsletter access)
- **FirstLook.gg** — playtester network + publisher directory
- **GDC, Gamescom, EGX, PAX, London Games Festival** — industry events; valuable from Tier 3+ once you have something to demo

---

## Cost projection (very rough)

Pre-MCP through Tier 2:

- **Tools and software:** £100–£500 total (Aseprite + plugins + occasional asset pack)
- **Commissioned art** (if needed, optional): £500–£3,000 for a polished anchor library
- **Music placeholders:** £0 (royalty-free)
- **Hosting:** £0 (single-player)
- **Marketing:** £0 (organic build-in-public)
- **Misc:** £100–£500

**Total Phase 0–1 budget: under £5,000** if disciplined. Achievable on existing income.

Tier 4 multiplayer foundation adds:
- Server hosting: £50–£200/month for alpha-scale
- Possibly contracted networking expertise: £5K–£20K depending on scope

These numbers grow once funding kicks in at MCP launch.

---

## When to revisit this document

- After Tier 2 ships — funding strategy goes from theory to action.
- After a successful funding event — re-plan around new runway.
- Annually — funding landscape changes; UK Games Fund rounds open; new publishers emerge.
