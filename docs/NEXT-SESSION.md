# RESUME HERE — 2026-08-20 (evening)

**ASHPIRE.** Branch `bot-fight-quality`. **176/176 green.** Everything below is
committed and **UNPLAYTESTED** — the maker watches **F5 → Lobby → Watch Bots**.

## ▶ WHAT CHANGED THIS SESSION

Four of the five open asks are closed and MEASURED. One is deliberately not built.

1. **The bot-fight camera no longer drifts off the fighters.** Three causes, all found
   by measuring the DRAWN channel (`tools/probe_showcase_framing.gd`):
   * follow lag — `position_smoothing_speed` was 4.0, putting the picture a measured
     142 px (p95) behind its own answer. Swept 4/12/18/26 against a jerk column; **18**.
   * the x clamp was the constant `340` (the half-width at ONE zoom) anchored to
     `STAGE_SIZE`, whose centre is 280 px right of the fight floor's. Now zoom-aware,
     solved per frame, in one helper both cameras share.
   * a ringed-out body flying off the map still voted on focus and zoom — one measured
     run had somebody off screen for **55% of the fight**.

   Measured: mean off-centre 31.7 → 8.4–30.9 px, clamp bites 13.6% → 0.1%.

2. **The hotbar no longer covers fighters on the tower's ground floor.** The previous
   fix had the **sign inverted** — it pushed fighters half a bar-height FURTHER under
   the bar. Plus `Hero.tscn` carried hardcoded camera limits of `1200x680` (the box
   `Arena.tscn` used to hardcode before `room_size` drove geometry), and Godot clamps
   *position* then applies *offset*, while the framer expresses everything AS offset —
   so the limits could never have worked. Limits off, room clamp moved into the
   framer's own space, HUD lift **solved** rather than taxed. Measured across five
   generated rooms: worst clearance **-80 px → +14.7 px**.

3. **SFX**: `cannon` was playing `holy_pillar` (a 1.5 s choral swell standing in for an
   artillery shot). Now its own sound. Six burst-firing pools that held ONE sample
   (`blink`, `gib`, `shadow_cast`, `ding`, `beam_start`, `beam_end`) got variants.
   The other eleven shared files are generic ALIASES and are fine — left alone.

4. **The game has a name and a mark.** `ASHPIRE` (ash + spire + aspire). `GameLogo` is
   drawn from the same primitives `MagicCircle` casts with, so the Lobby title, the app
   icon and the social avatar are one object. `config/icon` set (never was), and a
   `config/description` that still described the v0.0 AI-NPC game replaced.

5. **`docs/content-pipeline.md`** written — `publish_clip.py` has cited it since it was
   written and it never existed.

## ▶ THE ONE ASK NOT BUILT, AND WHY

**The destructible map (spec `2026-08-19-destructible-map-design.md`) is still paused.**
Its own status block says it was paused because *"there is like too much going on all
the time"* — it ADDS events to a fight the maker had just called too busy, and that
density complaint has not been playtested as resolved. Building slices 1–5 now would
also rewrite terrain collision on the versus stage **the content clips are shot on**,
days before shooting them.

Slice 0 remains DONE and measured: flat-gap reach is a RANGE, and the binding constraint
is the **Juggernaut at 97.1 px = 6 chunks**, not 7.5.

**Resume it after the maker confirms the calm-down pass reads right in play.**

## ▶ CLIPS — THE STATE, HONESTLY

* The pipeline works end to end. `make_post.py` produces `<a>_vs_<b>.mp4` and
  `<a>_vs_<b>.nomusic.mp4` in `content/posts/`.
* ⚠ **A SHOOT TAKES ~25 MINUTES PER TAKE.** Measured: ~1 rendered frame per second of
  wall time at 1920x1080, and a 20 s clip is 1200+ frames. `--takes 2` doubles it.
  Budget hours, not minutes, for a batch of five.
* ⚠ **The `[fight]` verdict still needs watching.** It has to survive Godot stdout →
  `make_clip` → `make_post` and has been swallowed at each layer at least once. If the
  log says *"(no fight verdict reported; keeping this take)"*, `--takes` is an expensive
  way to shoot once.
* Upload path: Upload-Post free tier is **10 uploads/month, no card, no expiry** — a
  batch of five costs nothing. See `docs/content-pipeline.md`. Upload the **`.nomusic`**
  file and attach the trending sound in-app; that is what puts the post on the sound's
  page, which is the reach.

## ▶ THE GATE'S DATA IS A ROSTER-BALANCE SIGNAL, AND IT IS FREE

Eleven scored takes across two batches, and **`leadchg` is the only discriminator**:

| matchup | takes | lead changes | verdict |
|---|---|---|---|
| Juggernaut v Stormcaller | 1 | 4 | PASS 74.7 |
| Stormcaller v Swordsaint | 1 | 4 | PASS 69.4 |
| Arcanist v Shadowblade | 1 | 3 | PASS 63.6 |
| Cryomancer v Brawler | 4 | **0, 0, 0, —** | REJECT 40.6 / 39.3 / 35.5 |
| Shadowblade v Juggernaut | 3 | **0, 0, …** | REJECT 49.7 / 34.4 |
| Warlock v Cleric | 1 | — | never resolved |

Every PASS had **3+ lead changes**; every REJECT had **zero**. Two matchups produced no
lead change across seven takes — the winner took the lead early and simply kept it. That
is not a capture problem, it is the roster, and it is the same open question as the
Stormcaller 16-0 note in [[project_v2_bot_fight_quality_todo]]. `FightScore` is now
generating this data for free on every shoot; it is worth reading as balance telemetry
rather than only as a keep/re-roll switch.

⚠ Also note `ults 0` on **every single take**. No ultimate landed in eleven bouts. Either
the bots never reach the ult, or the showcase cooldowns (1.6x) outlast the fight. Worth a
look — an ult landing is the single most clippable thing the game has.

## ⚠ TRAPS PAID FOR THIS SESSION

* **`Camera2D.global_position` IS THE TARGET, NOT THE PICTURE.** With smoothing on, the
  drawn centre is `get_screen_center_position()`. A probe reading the target reported a
  camera that tracked perfectly while the picture lagged 142 px behind.
* **HEADLESS HAS NO WINDOW, SO IT HAS NO ASPECT.** `DisplayServer.window_get_size()` is
  `(0,0)` and the stretch solve falls back to a **square 640x640** viewport. Every probe
  reading `get_visible_rect()` was silently solving for a frame 280 px taller than the
  real one. Fix: `root.size = Vector2i(1366, 768)`, then the logical viewport is 640x360.
* **A STALE NODE LIST IS A SILENT CONFOUND.** `Encounter` trickles waves in *during* a
  probe, so foes captured once stand at their own spawn points and set the real bounding
  box. This made one reading move 65 px between runs and looked exactly like a real
  effect. Re-collect every frame.
* **Godot clamps camera POSITION and applies OFFSET afterwards.** Any framer that works
  through `offset` is in a different coordinate space from the limits, and they fight.
* **Two `--import` passes** are needed after adding audio: the first parses `Sfx.gd`
  before the new WAVs are scanned and reports "no resource loaders".
* **A blank PNG saves successfully.** `save_png` returning OK says a file was written,
  not that anything is in it — a null renderer produces perfectly successful empty
  exports. `render_logo.gd` samples for non-zero alpha rather than trusting the return.

## ▶ OPEN, SMALL

* **"Ashpire" vs "Ashspire"** ship on the same screen, one letter apart — the game is
  ASHPIRE, the tower is "The Ashspire". A real collision, but which one wins is the
  maker's call and `Ashspire` is a proper noun in 50+ files including test assertions.
  Flagged, not silently rewritten.
* A stray `Godot_v4.6.2-stable_win64.exe` (PID from a killed shoot) resisted `taskkill`.
  Harmless, but kill it before a big batch so it is not eating a core.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3        # 176 suites, ~176s
godot --headless --path godot-project --script tools/probe_showcase_framing.gd -- 6 8
godot --headless --path godot-project --script tools/probe_hud_occlusion.gd
```
⚠ `slice_test_sandbox` NO-RESULTs occasionally from MCP port contention. Re-run it alone
before believing it.
