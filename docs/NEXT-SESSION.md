# RESUME HERE — 2026-08-20

**ASHPIRE.** Branch `bot-fight-quality`, **67c884e**, **175/175 green**, pushed, clean.

Everything below is committed and **UNPLAYTESTED**. The maker watches
**F5 → Lobby → Watch Bots**.

## ▶ THE FIVE OPEN ASKS

1. **The bot-fight camera drifts off the fighters.** It is the SHOWCASE camera
   (`VersusArena._update_showcase_camera`, ~:1935-2044), not `CombatCamera`. ⚠ That
   framer solves ONLY on X (`view.y` is never read in landscape) and clamps position to
   `clampf(focus.x, 340.0, STAGE_SIZE.x - 340.0)` — that clamp is the prime suspect:
   near a stage edge the camera stops following and the pair slide off centre.
2. **The bottom bar still blocks fighters on the tower's ground floor.** Half-done: the
   bar is 0.62x + left-anchored on desktop and `CombatCamera` reserves
   `AbilityBar.occupied_height()`. If it still blocks on floor 1, look at `FRAME_PAD.y`
   (140 → only 70 px of guaranteed margin).
3. **Final content clips** — the maker will review before posting.
   ⚠ **The quality gate still does not reach `make_post`.** `FightScore`/`BotMatch` emit
   correctly; three forwarding bugs were fixed and it STILL prints "(no fight verdict
   reported)". Debug godot → make_clip → make_post before trusting `--takes`.
4. **Destructible map — PAUSED before slice 1**, deliberately (it adds events to a fight
   the maker called too busy). Slice 0 IS measured: flat-gap reach is a RANGE, and the
   binding constraint is the **Juggernaut at 97.1 px = 6 chunks**, not the 7.5 the spec
   first assumed. Slice 4 needs the melee-across-a-gap ruling built.
5. **SFX**: `cannon` + `holy_pillar` share a file; ~15 pools have one sample.
   ⚠ New sounds must be **16-bit PCM WAV or OGG** — three of the maker's were 24-bit
   EXTENSIBLE, which Godot silently refuses to import.

## ▶ WHAT TO LOOK AT IN THIS BUILD

Class colours (Arcanist light orange · Shadowblade BLACK · Brawler dark red ·
Stormcaller lime) · the fight CALMS DOWN as it gets busy instead of winding up · bots
never stand still · every blink draws a class-tinted line · Swordsaint's katana has a
point and draws ONE blade · Thousand Cuts 418 damage on a 10.5 s cooldown · showcase
cooldowns 1.6x · **F11 fullscreen** (+ Pause → Settings, persists) · spell boxes 0.62x
in the bottom-left · **you cannot walk out of the town**, and falling respawns you at the
door · **ask the Doorkeeper to reset the tower** (confirms; keeps your best floor + falls).

## ⚠ TRAPS PAID FOR THIS SESSION

* `_initialize()` in a SceneTree script runs **before the tree exists** — `/root/X` is
  null. Defer a frame. One of my suites reported a missing autoload that was fine.
* **Appending to project.godot lands you in the LAST section.** That is how the
  `fullscreen` action ended up under `[rendering]`, silently dead, passing every source
  grep. Ask the INPUT MAP, not the file.
* `slice_test_render_budget` **bans 8x MSAA by name**; a linear canvas texture filter
  **blurs the pixel-art atlas**. Both were tried and correctly reverted.
* `AbilityBar.SLOT_SIZE` 46 is a locked **thumb** target — scale the bar, not the const.
* A new `class_name` needs a headless `--import` before anything can reference it.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3        # 175 suites, ~175s
```
⚠ `slice_test_sandbox` NO-RESULTs occasionally from MCP port contention. Re-run it alone
before believing it.
