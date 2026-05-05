# Content Strategy

How Legacy Frontier markets itself while it's being built. The mechanics are unusually content-rich — we lean into that.

---

## North star

**The development of Legacy Frontier produces content while it's being built. The content recruits players. The players generate emergent stories (because of the AI). The stories are *more* content. Flywheel.**

This is not promotional fluff. It's the actual marketing strategy. Every tier milestone is also a content beat. Every AI-NPC moment is potentially a video. Every Chronicle is a screenshot share. Every world-boss first-kill is a streaming event.

---

## The constraints

- **No face on camera.** The developer does not appear in videos. Brand is the game, not the developer.
- **Anonymous or pseudonymous.** A consistent project handle / persona, not the developer's real name front-and-centre. This protects privacy and builds an identity tied to the game.
- **Voice-over + screen capture + game footage** is the entire video format toolkit. No face-cam, no in-person interviews, no "studio tour" content.

This is a feature, not a bug. Many of the most successful indie dev channels work exactly this way. The game does the talking.

---

## Channels and cadence

### Primary channels

- **YouTube** — long-form devlogs (7–15 min) anchoring the journey. Highest-leverage long-term.
- **TikTok / YouTube Shorts / Instagram Reels** — short clips of "wow moments" (15–60s). High discovery, fast iteration. The clip is the AI-NPC magic moment, the boss reveal, the Chronicle screenshot.
- **X (Twitter)** — daily/weekly progress, screenshots, GIFs, thread-form devlogs. Gaming X is alive.
- **Discord** — community hub. Where wishlisters and supporters live. Funnel from all other channels.

### Secondary channels

- **Reddit** — `r/IndieDev`, `r/gamedev`, `r/IndieGaming`, `r/pixelart`, `r/Terraria` (audience adjacency). Be a member of communities, not a spammer. Post when there's genuine value.
- **Itch.io** devlog + early demo distribution.
- **Steam page** — open as soon as Tier 2 has a trailer-able vertical slice. Wishlists are the publisher currency.

### Cadence

- **Daily:** something on X (a screenshot, a problem, a question).
- **Weekly:** a short clip on TikTok / Shorts.
- **Bi-weekly to monthly:** a long-form YouTube devlog.
- **Per-tier-milestone:** a "big moment" video — the trailer for that tier.

Cadence is sustainable, not gruelling. Better to ship 50% less content forever than 200% more for two months and burn out.

---

## Content beats by tier

Every tier ships with at least one videoable moment. From `roadmap.md`:

| Tier | Content beat |
|------|--------------|
| Sprint 0 | "Learning Godot from scratch — week 1" |
| 1 / v0.0 | *"My NPC remembers me — watch what happens when I quit and come back."* (potential viral moment) |
| 1.5 | First combat reel; first death; the rat king miniboss |
| 2 | Vertical slice trailer — *"This is Legacy Frontier"* — the Kickstarter-quality video |
| 3 | "The world got huge" exploration video |
| 4 | "Multiplayer alpha — 15 players, persistent avatars, Chronicles" |
| 5 | "Magic system reveal — schools, spells, cultivation" |
| 6 | First world boss kill — streaming event |
| 7 | "Your Twitch username is in my game" — viewer-NPC reveal |
| 8 | Launch trailer |

Plan content for each tier *before* the tier ships. Don't scramble for content after the fact.

---

## The developer's persona

A consistent persona/handle makes the project recognisable. Some considerations:

- **Pick a handle.** Doesn't have to be the developer's real name. Could be a handle that ties to the game (`@legacyfrontier`, `@towerdev`, `@frontiergamedev`, etc.).
- **Lean into the *journey* of building, not biography.** Audience cares about the game and the path; they don't need life story.
- **Goldman-analyst-builds-AI-RPG is a hook**, but it can be told entirely through screen and voice. *"My day job is finance; my real obsession is this game."* No face required.
- **Honesty about challenges.** When things break, show them. When something works, show why it almost didn't. *"Build in public"* means real, not curated.

---

## Audience-as-funding-flywheel

This is the strategic core. Each downstream funding mechanism gets *easier* as the audience grows:

| Mechanism | What audience size unlocks |
|-----------|----------------------------|
| Patreon | A few hundred dedicated fans = real monthly income covering asset / tooling budget |
| Kickstarter | 10K+ wishlisters / followers = realistic shot at hitting funding goal (35–40% of game Kickstarters succeed; this number jumps with pre-existing audience) |
| Publisher pitch | "Here's our wishlist count" is the single most-asked metric in publisher meetings |
| Angel / VC | "Community validation" is what 2026-era game investors weight heaviest |
| Press / streamers | They reach out to *you* once you cross visibility thresholds |

**Therefore:** the most important Tier 0 metric is not lines of code shipped. It is people who care.

---

## What to film and post during Sprint 0

While the game itself is just tutorials and experiments:

- "Why I'm building Legacy Frontier" — vision video. No game footage; concept art and music. 90 seconds.
- "Day 1 with Godot" — opening the engine, first impressions.
- "First NPC standing in a tutorial scene" — a sprite, motionless, a screenshot. Caption: *"It begins."*
- Behind-the-scenes of the AI architecture decision. Simple diagrams. Voice-over. People love nerd-content when it's earnest.

You don't need finished gameplay to start building audience. You need *credible journey content*. Start posting the day you install Godot.

---

## Boundaries and red flags

- **No engagement bait.** "Like if you want me to keep building this!" type stuff is corrosive long-term.
- **No fake hype.** If a tier was hard, say it was hard. The audience smells curation.
- **No spamming communities.** Be a participant in places like `r/IndieDev` and `r/gamedev` before you post about your own game. Drive-by self-promotion gets you banned.
- **No comparison to bigger games as marketing.** *"Like Terraria meets Skyrim"* is fine in private pitch decks; in public marketing, talk about Legacy Frontier on its own terms.
- **No revealing the AI roadmap publicly until it's working.** The "AI NPC that remembers" is your wedge — don't telegraph it before v0.0 ships, or the moment loses surprise.

---

## Content rights

- **Music in videos:** ensure royalty-free licensing extends to YouTube monetisation. Some "free" libraries are fine for in-game but flagged on YouTube. Check before publishing each video.
- **Stable Diffusion outputs:** be aware of model licensing. Open-source LoRAs trained on game art can have unclear rights. For commercial use, prefer SDXL base + your own LoRA trained on assets you own.
- **Asset packs:** track licenses. Many free itch.io packs allow commercial use; some don't. Maintain a `LICENSES.md` listing every external asset and its terms.

---

## Streamer outreach (Tier 4+)

When the multiplayer alpha exists:

- **Don't cold-pitch big streamers early.** The game has to be *worth* their time first.
- **Build a private Discord for select creators** around Tier 3. Mid-tier streamers (1K–50K followers) are gold — they engage and they amplify.
- **Tier 4 alpha → invite curated creator group.** The viewer-NPC mechanic is your wedge — *every viewer who watches them play wants to be in their world too*.
- **Tier 7 → wider creator access** as Twitch integration ships.

The viewer-NPC mechanic was *designed* as a streamer-marketing flywheel. Honor that in execution.
