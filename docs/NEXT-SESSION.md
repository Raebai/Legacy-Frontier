# RESUME HERE — 2026-08-21

**ASHPIRE.** Branch `bot-fight-quality`, **176/176 green**. The maker watches
**F5 → Lobby → Watch Bots** and reviews the final clips before posting.

⚠ The canonical, always-current queue is the `project_v2_resume_queue` memory. This file
is the same list with more room to explain it.

## ▶ OPEN — three things

1. **RE-CUT THE FOUR OLD CLIPS.** `content/posts/` holds 9 mp4s; only
   `juggernaut_vs_stormcaller` and `juggernaut_vs_swordsaint` are post-fix. Four older
   gate-passing ones are worth saving — `stormcaller_vs_swordsaint`,
   `arcanist_vs_shadowblade`, `swordsaint_vs_arcanist`, `stormcaller_vs_cryomancer` —
   but they carry the "slash" voice bug, doubled spell names and the white title card.
   The audio/title fixes are POST-PROCESSING: `make_post.py --no-shoot --a N --b M`
   re-cuts one in about a minute. Only the shorter opening needs a real re-shoot.

2. **THE DESTRUCTIBLE MAP — paused, and the pause is still correct.** Spec
   `docs/superpowers/specs/2026-08-19-destructible-map-design.md`. Slice 0 measured
   (binding constraint: Juggernaut 97.1 px = 6 chunks). Slices 1-5 unbuilt. It adds
   events to a fight the maker called *"too much going on"*, and it rewrites terrain
   collision on the stage the clips are shot on.

3. **BOTS ONLY ULT IN ~40% OF BOUTS.** The drop is affordable now, but there is no
   "bank your mana" rung in `BotBrain` — a human stops casting for a beat to afford an
   ult and a bot never does. With `charges = 1` the ceiling is one per bout by design.
   A feel change; wants its own pass.

Smaller: **"Ashpire" vs "Ashspire"** ship one letter apart (game vs tower). Maker's call
which wins; `Ashspire` is a proper noun in 50+ files including test assertions.

## ▶ WHAT WAS FIXED 2026-08-20/21

**The clips.** The announcer said "A, *slash*, versus, B" in all 72 lines (the TTS read a
"/" aloud) and had a stray word before "who will win". The line talked over the fight —
`intro_hold` came only from `--vo`, which is never passed, AND the intro was timed on the
wall clock, which is ~20x wrong inside a render. The picture juddered from an 8:5 frame
decimation. The quality gate rejected every take because `FightScore.seconds` was also on
the wall clock (a 14.2 s fight scored 314.7 s). A missing verdict — a fight that never
ended — was treated as "keep this take". The white title card duplicated the game's own
VS card. All fixed; the bell now follows the NAMES and "who will win?" lands over the
opening exchange.

**The game.** There were TWO spell-name announcers (`SignatureRite` at windup in the
spell's colour, `CastName` at release in the caster's class colour) — that is the
brown/greenish double on Gravity Flip. `CastName.gd` is deleted and `SignatureRite` owns
it, tiered: ULT gets the full-width card, everything else a small name above the caster.
`EnemyProjectile` measured to the ORIGIN against a flat 16 px radius while the head sits
~22 px up, so head shots registered nothing — in the TOWER. The showcase tier-3 drop cost
80-95 MP of a 100 pool and was never cast.

## ⚠ TRAPS — the expensive ones

* **`BotMatch` ALWAYS sets `showcase_directed = true`**, so the bot fight and every clip
  are framed by `ClipDirector`, and `VersusArena._update_showcase_camera` returns early.
  A probe instantiating `VersusArena` directly measures a path nobody watches — that is
  how a camera fix landed on the wrong renderer for a whole day.
* **`Camera2D.global_position` is the TARGET**, not the picture
  (`get_screen_center_position()`).
* **Headless has no window, so it has no aspect** — `get_visible_rect()` falls back to a
  SQUARE 640x640. Set `root.size = Vector2i(1366, 768)` and wait a frame.
* **`Time.get_ticks_msec()` is ~20x wrong inside `--write-movie`.** Count frames.
* **Judder is invisible to a timestamp check.** The file is perfect CFR; the frames are
  evenly spaced while the moments they sample are not. Measure frame-to-frame MOTION.
* **`spell_cast` emits at RELEASE, the gesture plays during the WINDUP.** Sampling the
  rig on the signal reports "no gesture" for every short-windup spell.
* **A clip shoot REWRITES project.godot.** `git add -A` during one commits 1920x1080 as
  the real window size — done three times now. Run
  `python python-tools/check_window_override.py` before any push.
* **A guard that exempts what it cannot explain is not a guard** — `vo_bank --check`
  was written to expect the stray word.
* **A shoot costs ~25 minutes per take.**

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3          # 176 suites, ~165s
python python-tools/vo_bank.py --check                 # every VO part says one phrase
python python-tools/check_window_override.py           # 1366x768 committed
godot --headless --path godot-project --script tools/probe_cast_visuals.gd
godot --headless --path godot-project --script tools/probe_directed_framing.gd -- 3 6
```
