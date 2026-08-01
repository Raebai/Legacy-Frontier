# The director — the review rig

A debug panel that exists so a review session never has to restart the game.

**Open it:** **F1**, or **Esc → ◆ DIRECTOR** (the pause-menu row, which is the
route that survives having no keyboard — a phone has no F1).

It opens over the running game and does **not** pause it. The panel is anchored
to the right third so the fight stays visible beside it, and every button says
what it did on the green status line under the title. If a tap seems to do
nothing, read that line — it will say why.

---

## Why it exists

The first review of this game has to judge **22+ spells, 9 classes, 8 enemy
archetypes, 4 bosses and 6 modifiers, across 5 floors, in one sitting.**

Reaching a floor-5 boss carrying a specific modifier by *playing* there is
minutes per look. At that price the review does not happen, and every feel number
in the codebase stays reasoning instead of feel. Every row in the panel answers
one question: **what did I have to restart to see?**

---

## The tabs

### FLOOR
- **F1–F5** — jump to a floor. Rebuilds it *in place*: new layout, new waves, new
  boss roll. No scene reload, no climb.
- **Re-roll** — rebuild the current floor with new dice. This is how you judge
  whether floor randomisation is real.
- **Clear every enemy** — skips the wave.
- **Force CLEARED** — opens the exit portal without fighting.
- **Start a run** — from the F6 sandbox, which has no floors.
- **Trigger the death path** — the real spine, so the beat is the real beat. The
  status line names which method it reached, because that policy has already
  changed once (`fall` → `game_over`).

> Floor jumps need an active run. The F6 sandbox has no floors; the panel will
> say so rather than doing nothing.

### BOSS
Pick one of the four artists, tick any of the six modifiers, tap **SUMMON**. The
guardian arrives in the room you are standing in.

- **HP x0.25** is the review setting: the whole rotation, a quarter of the fight.
- **SUMMON a seeded roll for this depth** calls `BossRoster.roll()` — the exact
  seeded function the co-op host uses, not a copy of it — so what you review is
  what a real floor at that depth would actually produce, modifier count
  included. The status line prints the seed, so a fight worth reporting can be
  replayed.

### HERO
- **Nine class buttons** — switches live, mid-fight, no respawn.
- **GOD (F4)** — inflates max HP. You still get hit, still get knocked back,
  still see the numbers and the flinch; you just do not die. That is deliberate:
  a hero that ignored hits would tell you nothing about how those hits *read*.
  Reversible — the real value comes back.
- **Full reset** — heal, clear every cooldown, un-down.
- **The whole spell catalogue** — class kits, the six Tier 2 floor pickups and
  the four Tier 3 boss drops, tagged `[Q]` quick / `[H]` heavy / `[U]` ult (the
  weight each fights at in a clash). Pick `auto` or force slot 1/2/3, then tap a
  spell.

### SPAWN
All eight enemy archetypes, x1 / x3 / x5 per tap, dropped in through
`Encounter.spawn()` so they arrive with the same stats, telegraphs and
spawn-distance rules a real wave would give them.

### VIEW
- **Graphics: AUTO / HIGH / LOW** — LOW is what a mobile export resolves to. No
  APK has ever been built, so **this is the only preview of the phone's picture
  that exists.**
- **Perf overlay (F3)** — watch `worst`, not FPS.
- **Speed (F7)** — 1x → 0.5x → 0.25x → 0.1x → 1x. A telegraph is a few tenths of
  a second; at 0.1x it becomes something you can have an opinion about.
- **Freeze (F10)** and **Advance one frame (F8)** — for impact frames and clashes.

### NOTES
- **F9** — flag this moment. No pause, no typing. Use it freely, mid-fight.
- **F2** — freeze, cursor lands in the box, type, Enter, F10 to unfreeze.

Every note is stamped with floor, class, live boss, graphics tier, frame rate,
and whether god mode or slow motion were on. It lands in
`user://playtest-notes.md`.

```
python python-tools/playtest_notes.py                  # read them
python python-tools/playtest_notes.py --export         # copy into docs/, dated
python python-tools/playtest_notes.py --export --archive   # ...and start fresh
```

---

## Hotkeys

| key | does |
|---|---|
| **F1** | open / close the director |
| **F2** | write a note (freezes the game first) |
| **F9** | flag this moment (no freeze, no typing) |
| **F4** | god mode |
| **F7** | cycle slow motion |
| **F8** | advance one frame |
| **F10** | freeze / unfreeze the world |
| **F3** | perf overlay (PerfOverlay's own key, three-finger tap on touch) |

Only these keycodes are consumed; everything else falls straight through to the
game. Every button in the panel is `FOCUS_NONE`, so clicking one never steals
A/D/Space from the hero.

---

## It does not ship — two independent gates

**1. The script is not in the pack.** `tools/director/Director.gd` lives under
`res://tools/`, which `export_presets.cfg` excludes from the export. On a device
`ResourceLoader.exists()` answers false, `PauseMenu.director_available()` returns
false, and no row is ever built. This is the gate that cannot be forgotten,
because it is not a decision made at runtime — the bytes are absent.

**2. `OS.is_debug_build()`** in `PauseMenu.director_available()`. False in a
release export. This is what keeps the director off a **debug APK** — a real
thing this project intends to sideload — even if the exclude list is ever edited
for an unrelated reason.

Both are asserted by the release gate:

```
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
  --script tools/release_gate_dev_bridge.gd
```

It fails if the preset stops excluding `res://tools/*`, if `PauseMenu.gd` loses
its `OS.is_debug_build()` guard, or if any shipped script `preload`s a
`res://tools/` path (a `preload` resolves at compile time and would defeat the
exclude outright; the `load()` behind the guard is correct and stays legal).

The gate is **red by design during development** — the MCP dev bridge is in
`[autoload]` and is used every session. Because a gate that can only ever be
observed red is a gate nobody trusts, its checks are pure functions over file
text in `tools/release_gate_lib.gd`, and `tools/slice_test_release_gate.gd`
exercises every one of them in **both** directions against synthetic inputs —
including asserting that a clean project produces zero blockers, i.e. that the
PASS branch is reachable.

---

## If the director does not appear

| symptom | cause |
|---|---|
| No DIRECTOR row on the pause menu, F1 does nothing | `director_available()` returned false. Check `tools/director/Director.gd` exists and you are not on a release export. |
| F1 works but a tab is empty | The panel is scrolled. Every tab is a scroll view. |
| A button reports "no Encounter in this scene" | You are somewhere with no Arena — the Lobby or the hub. Bosses and enemies need the tower. |
| A button reports "no run active" | You are in the F6 sandbox. Use **FLOOR → Start a run**. |
| Two F1 presses do nothing | Two directors would cancel each other; `PauseMenu` guards against a second one being built. If this ever happens it is a bug — report it. |

---

## Files

| file | what |
|---|---|
| `godot-project/tools/director/Director.gd` | the panel |
| `godot-project/tools/director/DirectorCapture.gd` + `.tscn` | drives the real thing and photographs it, as proof |
| `godot-project/scripts/combat/PauseMenu.gd` | `director_available()`, the row, the CanvasLayer host |
| `godot-project/tools/release_gate_lib.gd` | the ship checks, as pure functions |
| `godot-project/tools/release_gate_dev_bridge.gd` | the gate |
| `godot-project/tools/slice_test_director.gd` | 12 suites over the panel |
| `godot-project/tools/slice_test_release_gate.gd` | the gate, proven red AND green |
| `python-tools/playtest_notes.py` | notes out of `user://` and into `docs/` |

Proof frames from a real run:
`%APPDATA%\Godot\app_userdata\Legacy Frontier\director_capture\` — regenerate
with `python python-tools/run_capture.py DirectorCapture`.
