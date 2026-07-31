# Voice, barks and the game shell — handoff

Written 2026-07-31 on branch `stickman-integrate`. Covers Phase 7 of
`docs/THE-TOWER-mobile-plan.md`: the gibberish voice system, barks, the game
shell (Play Solo), the lobby, the credits screen, and the music-size question.

---

## What to play

**F5.** The boot scene is `scenes/ui/Lobby.tscn`.

- A tower draws itself, live, on the left. Crude scribbles at the bottom,
  confident ink at the top; a class-coloured pencil tip marks how far the hand
  has got. Nothing is authored — it is `_draw()` with a seeded RNG.
- **CLIMB** now starts a run (`GameState.enter_run()`). It used to load the old
  AI-NPC hub. **Ollama is not involved anywhere; nothing was listening on 11434
  during verification.**
- **Credits** opens over the lobby (not a scene change, so hosting survives it).
- Class cycling retints the title and the pencil.

In a run you should hear characters *talk* — pitched vowel gibberish, one voice
per body — and see one-line chalk barks over heads at floor transitions, falls,
low health, kill chains, waves, and every boss phase.

---

## 1. Gibberish voices

| file | what it is |
|---|---|
| `python-tools/generate_gibberish_voices.py` | synthesises the 16 syllables (4 vowel banks × 4 variants, 80 KB total) |
| `godot-project/assets/audio/voice/gib_*.wav` | the assets |
| `scripts/combat/Gibberish.gd` | **pure maths** — identity + intonation, no audio |
| `scripts/combat/Sfx.gd` | `speak()` / `speak_for()`, riding the existing 32-voice pool |

**No second audio pool.** `speak()` goes through `_emit`, the same round-robin
everything else uses; the suite asserts `Sfx`'s children are still exactly the
pool after 40 bodies talk at once.

**Identity is a total function of a seed.** `Gibberish.voice(seed)` → (vowel
bank, pitch band, cadence). Node names are stable and unique per parent, so
`Sfx.speak_for(node)` gives every body its own mouth with nothing stored and
nothing replicated.

**Intonation is the last syllable.** Everything before it is filler; the "land"
multiplier makes a question rise and a death fall. `plan()` is pure — the wobble
is a hash of (seed, index), not an RNG — which is why the suite can assert exact
equality and why a character sounds like itself twice.

> A bug this caught, worth remembering: the first version derived bank/pitch/
> cadence by dividing the raw seed. Godot's `String.hash` is DJB2-flavoured, so
> `"Enemy@2"` and `"Enemy@3"` hash one apart — a whole wave of mobs came out
> with three cadences between them. It now goes through a murmur3 finaliser.

**Nobody has heard a syllable of it.** Headless has no audio device.

---

## 2. Barks

| file | what it is |
|---|---|
| `scripts/ui/Bark.gd` | the line table + the picker + `say()` |
| `scripts/SpeechBubble.gd` / `scenes/SpeechBubble.tscn` | **reused, not rewritten** |
| `scripts/combat/VoiceDirector.gd` | the observer that decides when anyone speaks |

`SpeechBubble` was built for the parked AI-NPC stack and does exactly "one line
above a character, shrink-to-fit, fades on a timer". It survives unchanged apart
from a style pass on the `.tscn` (chalk-on-card instead of the default grey
slab). `Bark` parents one to whoever is speaking and calls `say()`.

**A bark can never block.** `Bark.say()` deliberately does not await the bubble's
shrink-to-fit; it returns a plain `bool` synchronously. The suite asserts the
return type, because the moment somebody adds an `await` there, every call site
becomes a coroutine and a bark can eat a frame of input mid-fight.

House voice: chalk and graphite, five words or fewer (the suite enforces it),
present tense, never an instruction, never a question the player must answer.
The lore is delivered entirely through *what the lines are about* — paper, ink,
lines, the hand — and never explained.

### The VoiceDirector, and why it exists

Every combat call site that *should* fire a bark (`Hero._die`, `Enemy._die`,
`Boss._enter_phase`, `Encounter`) belongs to another agent this session. So the
director observes instead, through signals and groups that are already public,
and touches nothing:

- `GameState` — `run_started` / `floor_advanced` / `fell`
- `Encounter` — `wave_started` / `wave_cleared` / `boss_spawned` (duck-typed)
- `Boss` — `phase_changed` / `defeated` (duck-typed)
- hero health (polled ratio), for the low-health line
- any body in group `"enemy"` — its **built-in** `tree_exiting`, as a death cry,
  with a mass-exit guard so a scene teardown is not 25 simultaneous screams

It installs itself at the tree **root** (not as a child of `Sfx` — that node's
children are its voice pool and a suite asserts the count), from `Sfx` on the
first frame a scene exists, and again from the Lobby. `ensure()` is idempotent.
It never spawns under `--script`, so the headless suites are untouched by it.

### ⚠ REMAINING WORK — a hook that needs the Hype owner

**`Hype.gd` exposes no signals.** Kill streaks, multi-kills, close calls and wave
flourishes are all computed there and announced only as HUD shouts. There is a
`combo()` readout, so the streak bark is driven by **polling** it — which works,
but it is a poll, and multi-kills and close calls cannot be barked at all.

If the Hype owner adds:

```gdscript
signal streak_rung(name: String, count: int)
signal multi_kill(count: int)
signal close_call()
signal wave_flourish(index: int, total: int)
```

…then `VoiceDirector._poll_streak()` deletes, and MASSACRE / CLOSE CALL become
barkable. **I did not edit `Hype.gd`.**

---

## 3. The shell — Play Solo

`Lobby.gd`'s Play Solo used to `change_scene_to_file("res://scenes/Main.tscn")`
— the old hub, whose NPCs talk to a hardcoded Ollama server at
`http://127.0.0.1:11434`. On a phone that is the device's own loopback, so it
could never have worked there; the spec cuts it permanently.

It now calls **`GameState.enter_run()`**, which owns the persistent climb
(resume from the saved floor, never a blanket reset) and does the scene change
itself.

### PARKED, NOT DELETED

Still on disk and still registered, deliberately:

- `scenes/Main.tscn`, `scenes/Conversation.tscn`, `scripts/NPC.gd`,
  `scripts/Player.gd`, and the whole memory stack
- the **`Conversation` autoload** — it is referenced as a *bare global
  identifier* by `Player.gd` and `NPC.gd`, so unregistering it stops `Main.tscn`
  loading at all. Removing it needs a clean excision, not a delete.

`tools/slice_test_shell.gd` asserts all of that still exists, so a future tidy-up
cannot quietly bin it.

**Verified with nothing listening on port 11434** (checked before booting).

---

## 4. The lobby

Keeps Play Solo / Host Co-op / Join by IP / class pick / peer list / Start Run.
Added: Credits.

- Fits the **640×360 base viewport in landscape**, measured in the worst case
  (hosting, with the extra "Start Run" row showing). The suite fails if a future
  row pushes it over — the thing nobody notices on a 768-tall desktop window.
- Every tap target ≥ 30 px in base units and takes no focus ring.
- The class picker derives from `ClassInfo.count()`, never a literal (a hardcoded
  `% 8` once made the 9th class silently unreachable).

---

## 5. Credits — a licensing obligation

`assets/audio/CREDITS.md` §1c records that the **Pepper Sound Pack** readme asks,
in writing, for credit. That pack is under every melee swing, punch, kick, block,
guard break, hurt, body fall, gib, dash and footstep in the game.

`scenes/ui/Credits.tscn` carries the line verbatim, and
`tools/slice_test_shell.gd` pins the exact string *and* asserts it is actually
rendered on a Label — not merely declared in a constant.

### ⚠ Two provenance gaps, both pre-existing, both the maker's call

1. **TomMusic "Free Fantasy SFX Pack" — readme states no licence terms.** Already
   flagged in `CREDITS.md`; still unresolved. Capture the itch.io /
   gamedevmarket licence text for the version held.
2. **The six music tracks have no recorded provenance at all.** `CREDITS.md` §4
   previously just said the music folder "was not covered here". Nothing in the
   repo says where `arcadia`, `lord_of_the_land`, `for_tomorrow`,
   `unexplored_moon`, `combat_theme` or `boss_theme` came from, or under what
   terms. **This is the larger of the two exposures** and it should be settled
   before any public build.

Both are shown on the credits screen under "UNSETTLED", so they cannot be
forgotten.

---

## 6. Music size — ffmpeg is NOT installed, so this was NOT done

Measured in this repo:

| | |
|---|---|
| shipping audio | ~45 MB |
| the six music MP3s | **36.4 MB — about 81% of it** |
| all 187 SFX combined | 4.0 MB (Godot 4.6 imports WAV as QOA) |
| the new gibberish voices | 0.08 MB |

Re-encoding the six to ~96–112 kbps Ogg Vorbis saves roughly **17–20 MB, around
40% of the whole build**.

**`ffmpeg` is not on this machine** (`ffmpeg -version` → not found; not on PATH,
not under Program Files, scoop, chocolatey or WinGet Links). Per instructions I
stopped rather than faking it. `winget` *is* available, so the unblock is one
command:

```
winget install Gyan.FFmpeg
python python-tools/compress_music.py           # 112 kbps, conservative
```

What I did instead, so the conversion is a pure asset drop later:

- `python-tools/compress_music.py` — does the encode, backs the originals up to
  the gitignored `audio-source/raw/music-originals/`, and **refuses to run
  without ffmpeg** rather than pretending.
- `Music._preferred_path()` prefers a same-named `.ogg` beside each listed
  `.mp3`. So the six paths in `Music.gd` stay as `.mp3` on purpose: dropping the
  `.ogg` files in takes effect with no code change, and **deleting them rolls the
  whole thing back**. That matters because it is lossy-on-lossy and the only real
  test is a pair of ears.

**Nobody has heard the result, because the result does not exist yet.**

---

## 7. Tests

New suites, all in the house idiom (failures on a member, per-test completion
sentinel, so an aborted test fails BY ABSENCE):

| suite | covers |
|---|---|
| `tools/slice_test_gibberish.gd` | banks are real roster keys, identity is stable and spreads, `plan()` is pure, intonation lands, `speak()` adds no second pool, per-speaker rate limit |
| `tools/slice_test_bark.gd` | line table obeys the house voice, every event has a mood, `say()` never blocks, one bubble per speaker, cooldown, unknown events are silent, the director installs once and survives an empty world |
| `tools/slice_test_shell.gd` | Play Solo really calls `enter_run()` (observed with a stub, not grepped), no hub/Ollama on the boot path, hub parked-not-deleted, fits 640×360 worst case, thumb-sized targets, the Pepper line is rendered |
| `tools/slice_test_music.gd` | every mood has a playlist and a resting volume, every track resolves, ogg-over-mp3 preference and its rollback, the compressor and the playlist agree |

**Still true, and worth repeating: every feel number here is reasoning, not
feel.** The voice pitch bands, the cadence range, the bark hold and cooldown, the
flavour-roll chance, the syllable counts — all of it is a considered guess, and
none of it has been heard or seen in motion by a human.
