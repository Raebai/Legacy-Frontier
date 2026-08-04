# Audio credits and licences

Provenance for everything under `godot-project/assets/audio/`. This file exists so
the question "are we allowed to ship this?" has an answer that does not depend on
anyone's memory.

The key → source-file mapping (which library file became which game sound, the
window it was cut at, and a confidence rating) lives in
**`python-tools/build_combat_sfx.py`**. This file covers **licensing** only.

---

## 1. Local library — `Effects/` (gitignored, not distributed)

`Effects/` is a ~2 GB local sound library of 773 files across 45 packs. It is in
`.gitignore` and is **not** part of the repo. Only the small processed clips
selected from it ship.

### 1a. Sonniss #GameAudioGDC Bundle 2026 (Part 9)

Most of the premium packs used here arrived in this bundle. From
`Effects/Readme.txt`, verbatim:

> (347 WAV files) 7.47GB+ of high-quality sound effects from many of the best
> sound recordists and designers in the World. **Use them personally or
> commercially without attribution.**
>
> LICENSE: ROYALTY-FREE — contact: timothy@sonniss.com | @sonnissdotcom
> — Timothy McHugh, (CEO) Sonniss LTD, https://sonniss.com

There is also `Effects/License - GDC Game Audio.pdf` alongside it.

**Commercial use: permitted. Attribution: not required.** The contributors are
credited below anyway, because it costs nothing and it is the decent thing.

Packs drawn on:

| Pack | Used for |
|---|---|
| Alexander Kopeikin — 100 kHz Designed Ice | Glacial Spine, Frostpiercer, rime ticks, ice shatter, ward crack, shrapnel |
| Alexander Kopeikin — Emotion and Magic | arcane/shadow casts, the shadow beam, levitation, drain pull, field merge |
| Cinematic Sound Design — Colossal Impacts | Colossus Pillar, avalanche, bombardment, rubble, breach |
| Cinematic Sound Design — Ultra Transitions & Impacts | beam start/end, siege ult, resonance, Hollow Purple erase, every SHADOW cue (2026-08-04) |
| Cinematic Sound Design — Sci-Fi Drones | rift open, the unmaking ult, the rumble stem, the shadow crawl bed |
| Cinematic Sound Design — Interface & Infographics / System & UI / UI Interaction / User Interface / Hybrid Game & UI | ward raise, ward absorb, ground out, telegraph, banish, the crack stem |
| Federico Soler — Effective Trailer Booms Vol. 2 | the `sub_boom` layer stem, holy pillar, eruption, verdict burn, overpower, thunder tail |
| Federico Soler — Effective Trailer Alarms Vol. 2 | ult charge riser, siege ult, Heaven's Verdict thread, telegraph |
| David Dumais Audio — Melee Weapons Pack 2 | **Drain Tether's whip lash** (the single best filename match in the library), heavy swings, the metal clash, carve |
| Epic Stock Media — Humanoid Creatures Vol 4 | enemy death and hurt vocalisations |
| Epic Stock Media — Tower Defense Game | ice encase / ice shatter, ground out |
| Epic Stock Media — Synthesized Nature Loops and Sounds | fire beam body, steam reaction, storm beam |
| Epic Stock Media — Strange Game Ambient Loops 3 | the sigil forming |
| Epic Stock Media — Public Spaces (Storms…) | thunder — located by peak-scanning a seven-minute storm recording |
| CB_Sounddesign — Applicable Sounds | holy cast, ward raise, banish |

> **2026-08-04 — the cartoon packs are gone.** Maker: *"some of the vfx are goofy
> or weird slightly sounding so they need to be changed to something way more
> epic"*, naming the SHADOW cues. Every one of them had been mined from packs
> literally called **Cartoon Impacts** and **Cartoon & Animation Vol 2**, so
> "goofy" was not a matter of taste — it was the source doing exactly what its
> label says. `shadow_root`, `shadow_crawl`, `void_pull`, `rx_void_pull`,
> `rift_open`, `hollow_intake` and `ult_shove` now come from **Ultra Transitions
> & Impacts** ("Transition Braam Slow Dark Creepy") and **Sci-Fi Drones** ("Dark
> Industrial Ambience"). No file from either cartoon pack is referenced anywhere
> in `build_combat_sfx.py` any more.
>
> ⚠ **UNHEARD.** Nobody has listened to these. The mapping is defensible on
> paper — a slow descending braam IS what a pull and a crawl are — but the
> standing judgement on this project is that playtest beats reasoning, and audio
> is the one channel a screenshot cannot check.

### 1b. Free Fantasy SFX Pack — TomMusic

`Effects/Free Fantasy SFX Pack By TomMusic/ReadMe.txt` thanks the downloader and
gives contact details but **states no licence terms**. It is distributed as a
free pack via https://tommusic.itch.io/ and gamedevmarket.

> ⚠️ **FLAG — licence not confirmed in-repo.** This pack was already in use in the
> shipped game before this work (`cast`, `blast`, `spell_impact`, `nova` and the
> old melee clips all came from it), so this is a pre-existing exposure rather
> than a new one — but the terms are not written down anywhere we hold.
> **Recommended action:** capture the itch.io / gamedevmarket licence text for the
> pack version we hold and paste it here. Until then, treat every `.ogg` in
> `assets/audio/sfx/` as licence-unconfirmed.
>
> Used for: fire/ice/earth casts, the arcane beam, ice wall, frost field, ice
> throw/encase, rock wall, meteor throw/swarm, avalanche, sword parry and blocked
> (clash), crate/platform break.

### 1c. Pepper Sound Pack — Keisan / Fabien Boulanger

`Effects/ReadMeRandom1.txt`, verbatim:

> Merci de bien vouloir ajouter Pepper aux credits de vos vidéos si vous vous
> servez de ce pack.
> *That's it, buddies! Keisan (AK Fabien Boulanger) to serve you, as always.
> I classed ALL THE SOUNDS in ANY FOLDER. :)
> **Thanks for crediting Pepper if this pack serves you in your videos.***

> ⚠️ **ATTRIBUTION REQUESTED.** The readme asks for credit and does not otherwise
> restrict use. It says "videos" rather than "games", so the exact scope is not
> spelled out. **Action: add "Pepper Sound Pack — Keisan (Fabien Boulanger)" to
> the game's credits screen.** Cheap, and it satisfies the only thing asked.
>
> Used for: all melee swings and hits, punches, kicks, block, clash, guard break,
> hero hurt, enemy hurt, body falls, gib, dash, whip bite/miss, footsteps,
> landings, tether tear, shrapnel.

---

## 2. Downloaded — all CC0, all from OpenGameArt

Downloaded because the local library, for all its size, has **no designed
electric arc anywhere in 45 packs** and **no angelic/holy material at all**.
Staged in `Effects/_cc0_downloads/` (gitignored); only the processed clips ship.

CC0 = public domain dedication. **Commercial use permitted, attribution not
required.** Authors are credited anyway.

| File shipped | Source page | Original file | Author | Licence |
|---|---|---|---|---|
| `zap_1.wav`, `zap_arc_1.wav`, `zap_chain_2.wav` | https://opengameart.org/content/electricity-sound-effects-0 | `spark.wav` | BMacZero (Brian MacIntosh) | CC0 |
| `zap_2.wav`, `zap_chain_1.wav` | https://opengameart.org/content/electricity-game-sound-pack | `groundhit.wav` | faxcorp | CC0 |
| `zap_3.wav`, `zap_arc_2.wav`, `cast_storm_2.wav`, `rx_supercharge_1.wav` | https://opengameart.org/content/electricity-game-sound-pack | `crackleelectricityloop.wav` | faxcorp | CC0 |
| `cast_storm_1.ogg` | https://opengameart.org/content/spell-sounds | `electricspell2.ogg` | HaelDB | CC0 ¹ |
| `beam_storm_1.ogg` | https://opengameart.org/content/spell-sounds | `electricspell.ogg` | HaelDB | CC0 ¹ |
| `thunder_1.ogg` | https://opengameart.org/content/100-cc0-sfx-2 | `sfx100v2_thunder_01.ogg` (from `sfx_100_v2.zip`) | rubberduck | CC0 |
| `ward_crack_1.ogg` | https://opengameart.org/content/100-cc0-sfx-2 | `sfx100v2_glass_02.ogg` | rubberduck | CC0 |
| `ward_break_1.ogg` | https://opengameart.org/content/100-cc0-sfx-2 | `sfx100v2_glass_05.ogg` | rubberduck | CC0 |
| `cast_holy_1.wav`, `holy_swell_1.wav`, `ward_raise_2.wav` | https://opengameart.org/content/bell-arpeggio-24 | `24.wav` | cynicmusic | CC0 |
| `cast_arcane_2.ogg` | https://opengameart.org/content/magic-spell-sfx | `magical_1_0.ogg` | JaggedStone | CC0 |
| `cast_arcane_3.ogg` | https://opengameart.org/content/magic-spell-sfx | `magical_5_0.ogg` | JaggedStone | CC0 |
| `sigil_form_2.ogg` | https://opengameart.org/content/magic-spell-sfx | `magical_3_0.ogg` | JaggedStone | CC0 |

¹ OpenGameArt lists *Spell sounds* under **two** licences: `CC0` and `OGA-BY 3.0`.
A dual listing means the author offers the work under either, so taking it under
CC0 is legitimate. **We elect CC0.** Recorded explicitly so the choice is not
re-litigated later.

### Not used, and why

- **Freesound** — every download URL redirects to a login (`302 → /home/login/`).
  No no-auth direct URL exists. Do not plan around it.
- **Kenney.nl** — unambiguously CC0 and trivially fetchable, but its audio
  catalogue contains no thunder, no choir, and no crackling electricity. The only
  near-hits are synth chiptune `zap*.ogg` tones, which are the wrong texture.
- **An angelic choir swell** — **there is no licence-safe CC0 one.** OGA returns
  zero CC0 sound-effect results for *heaven / angel / angelic / divine / holy
  magic*. The holy cues here use a CC0 vibraphone arpeggio as the nearest safe
  substitute, and they are the roster's weakest mappings as a result. Options if
  the maker wants a real choir: trim the CC0 *Fantasy Choir* **music** track
  (https://opengameart.org/content/fantasy-choir-3-orchestral-pieces, cesisco,
  CC0, 69 MB), or commission/generate one. Zapsplat- and Mixkit-style sources
  were **not** used: their bespoke licences are not CC0 and were not verified.

---

## 3. Generated

`python-tools/generate_placeholder_sfx.py` and `generate_epic_sfx.py` synthesise a
few remaining clips from scratch (no third-party material): `blink.wav`,
`ding.wav`, `holy.wav`. Fully owned, no licence obligation.

### 3a. Gibberish voices — `assets/audio/voice/`

`python-tools/generate_gibberish_voices.py` synthesises the game's entire spoken
vocabulary: 16 clips (4 vowel banks × 4 variants, ~110 ms each, 22050 Hz mono,
80 KB total). Each is a glottal pulse train through two formant resonators — no
recording, no pack, no sample source of any kind.

**Fully owned. No licence obligation, and nothing to localise** — which is
half the reason the spec asked for gibberish rather than VO. Per-character
identity comes from re-pitching these at playback (`scripts/combat/Gibberish.gd`
+ `Sfx.speak()`), so 16 assets cover unlimited voices.

## 4. Music

⚠ **`assets/audio/music/` is still not covered here.** Six MP3s ship — `arcadia`,
`lord_of_the_land`, `for_tomorrow`, `unexplored_moon`, `combat_theme`,
`boss_theme` — and **no provenance or licence is recorded anywhere in this
repo**. That is a real pre-existing gap, not an oversight of this file: nothing
in the history says where they came from or what terms they arrived under.

> **Action for the maker:** record the source and licence of each of the six
> tracks here before any public build. Until then, treat the music folder as
> licence-unconfirmed, exactly like the TomMusic pack in §1b.

The in-game credits screen (`scenes/ui/Credits.tscn`, reachable from the Lobby)
names both gaps out loud under "UNSETTLED", so they cannot be forgotten between
now and a store submission.

### Size note (not a licence matter)

Those six MP3s are **36.4 MB of a ~45 MB shipping audio payload, about 81% of
it**, at 320/256/192 kbps. The 187 SFX are 4.0 MB combined, because Godot 4.6
imports WAV as QOA. `python-tools/compress_music.py` re-encodes the six to
~96–112 kbps Ogg Vorbis for a saving of roughly 17–20 MB, and `Music.gd` picks up
a same-named `.ogg` automatically with no code change. **It has not been run:
ffmpeg is not installed on this machine.**

## 5. Where the attribution actually appears

The obligation in §1c is discharged by the in-game **credits screen**
(`scripts/ui/Credits.gd`), opened from the Lobby. The exact line is pinned by
`tools/slice_test_shell.gd`, so a future layout tidy cannot silently drop it.
