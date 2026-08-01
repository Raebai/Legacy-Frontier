# PLAY THIS TONIGHT

One page. Everything else is in `docs/playtest-checklist.md` (verdict per row) and
`docs/audit-fun-and-competitors.md` (what to expect to be wrong).

**Nobody has ever played any of this.** Every feel number in it is reasoning, not
feel. That is the whole point of tonight.

---

## Start here — 5 minutes

**F5.** You land on the title screen: a drawn tower, crude scribbles at the bottom
easing into confident ink at the top.

1. **Free Play** — no enemies, no timer, nothing that can end it. Move, jump, dash,
   throw all three spells, break the cover, fall off the rim and come straight back.
   Esc → change class live (all 9), add 0–3 practice dummies, reset.
   **This is the one to judge feel on.** Do this before anything else.
2. **Loadout** — pick *which three* of your class's five spells you carry, the
   armory, and your colourway. 6 hands per class, 54 across the roster.
3. **CLIMB** — five floors, waves → guardian, ascend. Death = ghost until revived;
   solo, death ends the run and you resume on the floor you died on.
4. **Watch Bots** — two AI heroes fight with the clip camera on. Spectator mode and
   the content tool at once.

---

## The director — your audit tool

**F1** in game (or Esc → ◆ DIRECTOR). Opens *over* the running game without pausing
it. Six tabs:

| tab | what it saves you |
|---|---|
| FLOOR | jump to any floor, **re-roll it**, clear the wave, force the exit, trigger death |
| BOSS | any of 4 bosses × any of 6 modifiers × HP scale — or a seeded roll that **prints the seed so you can replay a fight exactly** |
| HERO | 9 classes live mid-fight, GOD mode, and the whole spell catalogue into any slot |
| SPAWN | any of 8 archetypes, ×1/×3/×5 |
| VIEW | **graphics LOW** (your only phone preview), perf overlay, 0.5×/0.25×/0.1× time, freeze + frame-step, friendly-fire toggle |
| NOTES | **F9 flags a moment without stopping the fight** — auto-stamped with floor, class, boss, quality, fps |

`python python-tools/playtest_notes.py --export` pulls your notes out afterwards.

**Use F9 constantly.** A feel note is worthless if the moment passes before you can
write it down.

---

## The five things I most want your verdict on

1. **Does casting feel good?** The magic circles are the signature — element glyph
   band, tier ladder, a charge that lights one glyph at a time. Free Play, slow time
   to 0.25× in the director, and watch one.
2. **Is friendly fire funny or infuriating?** It is always on and it is the spec's
   social engine. It now announces itself loudly. Only two people in a room settle it.
3. **Do the floors feel different each climb?** Re-roll the same floor from the
   director a few times. Variety or noise?
4. **Are the bosses fair?** Every attack has a tell; the Cartographer's sigil states
   its safe radius. If something kills you without warning, that is a bug, not
   difficulty.
5. **Is a floor too short?** Simulated at ~1 minute each, ~6:39 for a whole climb.
   The design doc says 4–7 min *per floor*; competitor research says that unit is
   wrong and the climb is the right target. **Your hands decide.**

---

## Known — do not waste review time reporting these

- **No Android build exists.** Never attempted. Needs export templates, JDK 17, SDK,
  keystore — all human steps, listed in `docs/mobile-export.md`.
- **Nothing has touched a touchscreen.** Every touch constant is a declared guess.
- **~30 ms CPU at the 8-effect ceiling on desktop**, est. 90–150 ms on a mid-range
  phone. Real risk, partially addressed, not closed. And `TIME_PROCESS` excludes
  `_draw`, so the true figure is higher.
- **Head and body gear are pure upside** — each slot has a strictly-best answer, so
  it is a checklist not a choice. One-line data fix, wants your call.
- **Brawler wins 14%** in bot sims — the pure-melee class is hurt most by the reflex
  layer now working.
- **Difficulty dial is shallow** — Impossible only beats Easy 61/39.
- **Music has no recorded licence provenance.** Six tracks, nothing in the repo says
  where they came from. Settle before any public build.
- **Floor affixes are built but off** behind one flag — they compete with elites for
  the same reading channel, and the flag would desync co-op if made per-player.

---

## Co-op, if there are two of you

Host on one machine, **Join a Game** on the other — it discovers hosts on the LAN,
no IP typing. Everything crosses the wire: spells, boss attacks and phases, cover,
pickups, revives, friendly fire. Verified by a two-process loopback test, **never by
two real machines.** That is tonight's other unknown.
