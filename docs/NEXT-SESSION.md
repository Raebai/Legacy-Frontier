# RESUME HERE — 2026-08-19

**ASHPIRE.** Branch `bot-fight-quality`, **c14f189**, **173/173 green**, pushed, clean.

The nine asks in the resume queue are **done and pushed**. Everything below is
committed and headless-verified and **UNPLAYTESTED** — the maker watches
**F5 -> Lobby -> Watch Bots** and does not want rendered clips.

## WHAT TO LOOK AT, IN THE ORDER IT WILL SHOW UP

1. **The colours.** Arcanist light orange · Shadowblade BLACK · Brawler red ·
   Stormcaller light blue; bronze/gold/ice/violet/near-white unchanged. The default
   matchup is Stormcaller vs Cryomancer, which was the risky pair — at the authored
   light blue it would have fallen back to yellow/blue and looked unchanged, so
   Stormcaller was pushed deep. All 36 pairs now clear the separation guard (min 0.318),
   so **every bout should show class colours, not yellow-vs-blue.** Mirror matches still
   fall back, correctly.
   ⚠ Two knock-ons to judge by eye: the black fighter now draws with a PALE keyline
   instead of the dark one (a near-black figure with a near-black outline is a blob),
   and every UI surface paints a LIFTED version of the colour (`side_ink`) because a
   black name on a near-black plate is not a name.
2. **The stage is symmetric.** Left platform raised 688 -> 616 to match the far right.
   It is deliberately NOT reachable from the ground any more (164 px vs a 105 px jump)
   — you climb it via the mid platform, the same way the right one always worked.
3. **The Brawler chases upward.** Petrify something in the air and it should now hop to
   reach it instead of standing underneath punching nothing.
4. **Shadowblade holds a dagger**, not the Swordsaint's katana.
5. **Gravity Flip gets the big banner.** Its tier did NOT change.
6. **Cleric -10% damage, Cryomancer +20%** (damage, not health).
7. **Tower: clearing a floor fully heals you** on arrival at the next one.
8. **New sounds**: two more punches, one more swing, and a vocal effort grunt layered
   under the heavy swing.

## ⚠ TWO DECISIONS ARE WAITING ON YOU

* **Clip orientation.** You asked for landscape, then sent four TikTok audios — TikTok
  is portrait. `python python-tools/make_post.py --landscape` renders 1920x1080; the
  DEFAULT is still 9:16. Pick one and it becomes the default.
* **Melee across a severed stage** — blocks slice 4 of the destructible map. Three
  classes are melee-primary and a melee bot will stand at the lip of an uncrossable gap
  doing nothing until the clock. Four options are costed in
  `docs/superpowers/specs/2026-08-19-destructible-map-design.md` §4.

## ⚠ ONE THING I DID NOT FIX, AND WHY

**"Corpses must still fall" did not reproduce in the bot fight.** Killing a fighter in
mid-air measures it falling (+92 px) — `stay_dead` routes to `_enter_defeated`, which
has its own gravity. The queue's diagnosis named `_enter_downed`, which a bot fight
never uses. I fixed a real latent hole found by reading instead (Petrify and
Chronostasis both pinned a victim's position without ever checking it was alive).
**If you still see a body hang, tell me which mode** — the tower GHOST genuinely does
not fall, and that is the revive system working as designed.

## SFX YOU ASKED ME TO FLAG

⚠ **Two of your four files were 24-bit WAVE_FORMAT_EXTENSIBLE and Godot silently would
not import them.** Converted to 16-bit PCM. Send future sounds as **16-bit PCM WAV or
OGG**.

Worth sourcing next:
* `cannon` and `holy_pillar` **share one file** — the only two genuinely different
  events wearing the same sound.
* `effort_grunt` has **one** sample, so it repeats; 2–3 more would let it rotate.
* No variation at all (one sample each): `beam_start`, `beam_end`, `blink`, `ding`,
  `gib`, `holy`, `levitate`, `shadow_cast`, `ult_unmaking`, `verdict_thread`,
  `verdict_burn`, and four `rx_*` reaction cues.

## ⚠ SOMETHING EDITED `ShadowRoot.gd` OUTSIDE THIS SESSION

The full suite went red on a parse error in `ShadowRoot.gd`: `REAPPLY_EVERY` mangled to
`REAPPLY_EdddddVERY`, and a stray `a` prepended to a line. The tree was clean at session
start, so it arrived mid-session — an editor with the file open, or a second session.
Diffed first (never `git checkout --` a file with uncommitted work), found only those
two lines, repaired in place. **Worth checking nothing else has a file open on this
checkout.**

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3        # 173 suites, ~160s
```
⚠ At `--jobs 3` one suite still NO-RESULTed once with an access violation and passed
alone on retry. Re-run a lone NO-RESULT before believing it.

---

# SESSION ADDENDUM — 2026-08-19 (late)

**`853a6d4`, 173/173, pushed.** Everything below is UNPLAYTESTED.

## THE BIG ONE: the picture now CALMS DOWN as the fight gets busy

Aberration, a 40 Hz screen micro-warp and the camera shake were all pure functions of
ONE number (`CombatCamera.trauma()`, additive per hit, clamped at 1.0). Mid-fight all
three sat pinned at maximum on top of the busiest picture — the presentation was
loudest exactly when the read was hardest. Meanwhile `SpellReactor.austerity()` had
been thinning particles and debris all along and **`PostProcess`, `CombatCamera` and
`Juice` never called it once.** They do now. Plus: aberration 4.5→2.2, warp 0.004→0.0018
(and promoted from a bare literal to a uniform), trauma decay 1.4→2.2, dash ghosts
0.03→0.055 (a dash was leaving ~11 full stick figures alive), debris 160→90 and
2.6-4.2s→1.5-2.5s, impact frames 0.26→0.42 with local flashes 6→3/s.

## ALSO IN
* **Nobody stands still** — `_steer` planted whenever the bot was inside its spacing
  band, which is most of a fight. `_idle_jockey` keeps weight moving. (Without it: 0 of
  40 settled frames moved.)
* **Every blink draws the line**, tinted per class off `_element_color`.
* **The Swordsaint's katana comes to a point** — the taper was there, buried under a
  full-length constant-width spine. Same fault `_draw_blade` fixed years-of-comments ago.
* **Stormcaller lime-yellow, Brawler darker red.** Three other yellows were tried and
  collided with the Arcanist.
* **Opening beat covers Q/R/T** — it existed at 1.0s and the abilities ignored it.
* **DoT stops flinching** (`State.HURT` is the arms-up pose) and is 12 dB quieter.
* **Rock Wall stops trapping people** inside itself.

## ✅ DESTRUCTIBLE MAP SLICE 0 IS MEASURED
`tools/probe_gap_reach.gd`. Flat-gap reach is a RANGE, not one number: Juggernaut
**97.1 px**, Arcanist 127.0, Brawler 132.5, Swordsaint 139.7, Stormcaller 147.6.
**The binding constraint is 6 chunks, not the 7.5 the spec assumed** — a 7-chunk hole
already strands the Juggernaut. Seven separate faults had to be fixed to read that
number; they are all in the probe's header.

**The map itself is still PAUSED before slice 1, deliberately** — it adds events to a
fight the maker had just said was too busy. Resume when the calm-down pass has been
played.

## ⚠ STILL OPEN
* **Melee across a severed stage** — the maker said "the melee stuff is cool", which
  reads as approval of the recommendation (clock decides + teach the veto to reverse),
  but it has NOT been built. Blocks slice 4.
* **The second effort grunt never arrived** — only one new file appeared in `Effects/`.
* **SFX still inaccurate:** `cannon` and `holy_pillar` share one file; ~15 pools have a
  single sample. ⚠ Any new sound must be **16-bit PCM WAV or OGG** — three of the
  maker's files so far were 24-bit EXTENSIBLE, which Godot silently refuses to import.
