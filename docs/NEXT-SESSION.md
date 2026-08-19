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
