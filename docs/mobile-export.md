# THE TOWER — mobile export

Phase 6 of `docs/THE-TOWER-mobile-plan.md`. Written 2026-07-31 against branch
`stickman-integrate`.

**No mobile build has ever been made. Not a failed one. Zero.** Everything below
that could be done without a device or an SDK has been done and headless-verified.
What remains is a short list of things that genuinely require a human, an
installer, and a phone — [§1](#1-what-only-a-human-can-do).

Target device, per the spec: **a three-year-old mid-range Android**, not a
current iPhone. Watch thermals.

---

## 1. What only a human can do

In order. Steps 1–3 are one-time setup; 4–6 are every build.

### 1.1 Install the Android export templates (one-time)

Godot cannot export without them and there is no CLI that conjures them.

- Editor → **Editor → Manage Export Templates… → Download and Install**, matching
  the running engine **exactly: 4.6.2.stable**.
- They land in `%APPDATA%\Godot\export_templates\4.6.2.stable\`.
- Verify `android_debug.apk` and `android_release.apk` are both present.

Until this is done, an export attempt fails with precisely:

```
No export template found at the expected path:
C:/Users/<user>/AppData/Roaming/Godot/export_templates/4.6.2.stable/android_debug.apk
```

### 1.2 Install the Android SDK + JDK and point the editor at them (one-time)

- **JDK 17** (Temurin/Adoptium is fine). Godot 4.6 wants 17 specifically.
- **Android SDK** with **build-tools** and **platform-tools**. The least painful
  route is Android Studio; the command-line tools alone also work.
- Editor → **Editor → Editor Settings → Export → Android**:
  - `Java SDK Path` → the JDK root
  - `Android SDK Path` → the SDK root (the folder containing `build-tools/`)

The current failure without this is `Unable to open Android 'build-tools'
directory.` — confirmed on this machine.

These are **editor settings, not project settings**: they live in the user's Godot
config, never in the repo, and every machine needs its own.

### 1.3 Generate a keystore (one-time)

- **Debug** keystore — for sideloading to your own phone. Godot can generate one:
  Editor Settings → Export → Android → **Debug Keystore**. Or by hand:
  ```
  keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
    -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" \
    -validity 9999 -deststoretype pkcs12
  ```
- **Release** keystore — only needed for a store build. **Back it up somewhere
  that is not this repo.** Losing it means never being able to update the app
  under the same package name again.

> **Keep secrets out of git.** `.gitignore` now covers `export_credentials.cfg`,
> `*.keystore` and `*.jks`. `export_presets.cfg` itself is **tracked** (see
> [§3](#3-export_presetscfg-is-tracked-now)), and Godot writes signing
> credentials into the separate `export_credentials.cfg` — but glance at the
> tracked file before committing anyway. `tools/slice_test_mobile_config.gd`
> fails if a `password` or `.keystore` string ever appears in it.

### 1.4 Remove the MCP dev bridge — **EVERY BUILD**

See [§2](#2-the-mcpruntime-problem) for why this cannot be automated. Before
exporting, in `godot-project/project.godot`, delete this line from `[autoload]`:

```ini
MCPRuntime="*uid://qc4i28l1mvja"
```

Verify, then put it back after exporting:

```
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
  --script tools/release_gate_dev_bridge.gd
```

It must print `Release gate: PASS`. **It is red right now, on purpose.**

### 1.5 Export

```
godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
  --export-debug "Android" ../exports/android/the-tower.apk
```

`exports/` is git-ignored. The preset is arm64-v8a only and APK format — see
[§3](#3-export_presetscfg-is-tracked-now) for switching to AAB for the Play Store.

### 1.6 Test on the device — the protocol that matters

Everything in this repo is reasoning, not feel, and on mobile that is doubly
true because **nothing here has ever run on a phone.**

1. Install, launch, get to a floor.
2. **Turn on the perf overlay: three-finger tap** (F3 on desktop). See
   [§6](#6-the-instruments).
3. Watch `worst`, not FPS. The panel goes amber past 16.7 ms and red past
   33.3 ms.
4. **Climb for ten minutes without putting the phone down.** Thermal throttle
   does not show up in a thirty-second test — it shows up as `worst` drifting
   upward with nothing on screen having changed. That drift *is* the
   measurement.
5. If it struggles, work down [§7](#7-levers-if-the-device-struggles) in order.

---

## 2. The MCPRuntime problem

`project.godot` `[autoload]` carries `MCPRuntime="*uid://qc4i28l1mvja"` →
`addons/godot_mcp_runtime/`. It is a **WebSocket dev bridge**: it opens a
listening socket on port 7777 at boot and exposes live scene-tree introspection
and performance monitors to whatever connects. On this machine it is the most
useful tool in the project. In a shipping app on a stranger's phone it is a
listening socket and a remote introspection surface.

**Autoloads are exported. There is no debug-only flag on them.**

### The automated fix does not exist — measured, not assumed

The obvious answer is a Godot feature-tag override, the same mechanism that makes
`renderer/rendering_method.mobile` work. **It does not work for autoloads.** With

```ini
[autoload]
MCPRuntime="*uid://qc4i28l1mvja"
MCPRuntime.windows=""
```

a boot probe on Windows (where `windows` is a live feature tag) printed:

```
PROBE root children:     [MCPRuntime, Conversation, Sfx, Music, Rank, GameState, ...]
PROBE autoload settings: [autoload/MCPRuntime, autoload/MCPRuntime.windows, ...]
ERROR: Failed to create an autoload, can't load from UID or path: .
```

The bridge **still loaded**; the dotted key registered as a *second, separate*
autoload rather than an override; and the empty path spammed a boot error. It is
strictly worse than doing nothing.

The cause is in the engine, and it is structural rather than a bug:
`ProjectSettings::_set` intercepts any key beginning `autoload/` *before* the
override machinery is consulted, and takes the node name as everything after the
first slash — so `MCPRuntime.mobile` is simply a different autoload named
`"MCPRuntime.mobile"`. Only `get_setting_with_override()` reads the override map,
and autoload registration never calls it.

### The route taken

**Leave the autoload alone; make forgetting it structurally impossible.**

1. **`tools/release_gate_dev_bridge.gd`** fails (exit 1) while `MCPRuntime` is in
   the `[autoload]` list, and prints the exact line to delete. It is *expected to
   be red during development* and must be green before a build leaves the machine.
   Verified both ways: red now, green with the line removed.
2. **Backstop:** the export preset excludes `res://addons/godot_mcp_runtime/*`
   (and `godot_mcp_editor`, `auto_reload`), so even a forgotten autoload cannot
   find its script in the pack. That leaves a boot *error* in a shipping build,
   which is why it is a backstop and not the plan.

The gate is deliberately **not** named `*_test_*`, so `run_all_tests.py` does not
collect it and its intentional red does not pollute the green sweep.

---

## 3. `export_presets.cfg` is tracked now

It was git-ignored (`.gitignore:5`). It is real shared project config — the
exclude list is the only thing keeping the MCP bridge, the spike sandboxes and
327 `tools/` scripts out of the APK — and that must not be a per-machine setting
somebody silently lacks. The ignore was removed; credential files stay ignored.

### Excluded from the pack

`res://tools/*` · `res://addons/godot_mcp_runtime/*` ·
`res://addons/godot_mcp_editor/*` · `res://addons/auto_reload/*` ·
`res://scripts/spike/*` · `res://scenes/spike/*`

`tools/` is safe to exclude by prior design: `VersusArena._probe_begin` already
guards with `if not FileAccess.file_exists(PROBE_SCRIPT): return`, commented
*"tools script absent — never a reason to stop the maker playing."*

### NOT excluded, and why

- **`effects/*/source`** — the plan listed it as excludable "if unused at
  runtime". It is **used**: `Vfx.gd:14` loads
  `res://effects/2d_explosion/source/explosion.tscn`. Excluding it would have
  produced a build that looks fine in the editor and has no explosions. It is
  0.01 MB.

### `export_filter="all_resources"`, deliberately

Not `resources` (dependency-scanned). Godot's scanner cannot see a path held in a
String constant, and this codebase loads that way everywhere — `SimArena.HERO_SCENE`,
`PostProcess.SHADER_PATH`, `Atmosphere.GLOW_ENV_PATH`, `Vfx.EXPLOSION`,
`Sfx`'s roster. A scanned export ships a game that is missing half its content on
the device only.

### Other preset choices

| Choice | Value | Why |
|---|---|---|
| Architectures | `arm64-v8a` only | Play Store requires 64-bit; any target device is arm64. Halves the binary. |
| Format | APK (`use_gradle_build=false`) | Sideloading to your own phone. **For the Play Store**: set `gradle_build/use_gradle_build=true` and `export_format=1` (AAB) — that needs §1.2 fully working. |
| Package | `com.legacyfrontier.thetower` | Change before publishing if you want a different identity. **It is permanent per store listing.** |
| Permissions | internet, wifi state, multicast, vibrate, wake lock | ENet co-op + the planned LAN discovery beacon (multicast) + rumble. |
| `screen/immersive_mode` | true | Full-screen landscape, no system bars over the arena. |

---

## 4. Renderer decisions

Setting values verified against Godot 4.6.2 docs and source; pinned by
`tools/slice_test_mobile_config.gd`, which asserts them against the **file text**
because `ProjectSettings.get_setting()` answers from built-in engine defaults
even when our line has been deleted, and the editor rewrites this file.

```ini
[rendering]
renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_2d=3          ; 8x, desktop
anti_aliasing/quality/msaa_2d.mobile=1   ; 2x
viewport/hdr_2d=true
```

### Why `mobile` and not `gl_compatibility`

Compatibility is the lighter renderer and the docs say it is "usually good enough
for 2D" — but it would silently take away **both** things this game's look is
built on:

- **`hdr_2d` is unsupported in Compatibility.** No warning; the bloom in
  `scenes/combat/combat_glow.tres` is what makes pushed spell cores radiate, and
  it depends on colours above 1.0 existing at all.
- **2D MSAA is unsupported in Compatibility.** GLES3 prints
  `WARN_PRINT("2D MSAA is not yet supported for GLES3.")` and does nothing.

That second one matters more here than in most games. **This game draws its
fighters as procedural lines and arcs, not sprites** — the stick rig, the impact
frames, the spires. MSAA is doing real work on those in a way it would not for
pixel art. The maker's 8x is a deliberate look decision (see the Stick Fight feel
study), not an oversight, and Compatibility would flatten it to nothing.

So: the Mobile renderer, which supports both. If a target device turns out to
have a bad Vulkan driver, `gl_compatibility` is the fallback — and it is a
**look** change, not a free switch. Note also that Mobile's dynamic range only
reaches 2.0, so glow may want `glow_hdr_threshold` ≈ 0.9 and `glow_intensity`
≈ 1.5 to look the same; that is a `combat_glow.tres` tweak to make *on device*.

### MSAA 8x → 2x on mobile

8x MSAA on a tile GPU is the worst setting in the file. 2x keeps the rig's lines
from crawling at a quarter of the cost. Kept at 8x on desktop — the mobile
override exists to spare the phone, not to walk the desktop decision back, and
the suite asserts the desktop value was not quietly zeroed along with it.

### `hdr_2d` kept ON — the tradeoff, stated

`hdr_2d=true` makes the 2D framebuffer `RGBA16F` instead of `RGB10A2`: **double
the colour-buffer bytes, and double the bandwidth on every write, blend and
resolve.** On a tiler that is the classic mid-range bottleneck. And because the
project uses `canvas_items` stretch (native-resolution rendering, the maker's
choice — *not* the pixelated `viewport` mode), the buffer is the phone's real
panel size, not 640×360. On a 2400×1080 screen that is ~20.7 MB versus ~10.4 MB.

**Kept on anyway**, because the bloom is the visual identity and turning it off
is a look change that must be *seen* before it is *chosen*. It is the **first
lever** in §7, with the exact one-line change.

### `default_texture_filter` — deliberately NOT changed to Nearest

The plan flagged the 640×360 base viewport as wanting Nearest. **It does not, and
setting it would look worse.** This game leans on small gradient textures
stretched large — `CombatVfx._soft_dot()` is a 16×16 radial gradient scaled up to
be every particle in the game, and `Atmosphere`'s vignette is a 256×256 gradient
stretched full-screen. Nearest would band both badly. Left at Linear (default).

> Trap if anyone revisits this: the project-setting integers do **not** match
> `CanvasItem.TextureFilter`. Here `0` = Nearest, `1` = Linear. Setting it to
> `CanvasItem.TEXTURE_FILTER_NEAREST` (which is `1`) silently gives you Linear.

`textures/default_filters/anisotropic_filtering_level=0` was already present and
is **inert** — it only applies to `*_WITH_MIPMAPS_ANISOTROPIC` filter modes,
which nothing here uses. Harmless hygiene, not a win; don't count it as one.

### `[physics]`

`common/physics_ticks_per_second=60` is now written explicitly. It was implicit,
and `SpellPlaygroundController.gd:87` overrides it to 120 — pinning the shipping
value makes that leak visible instead of silent. The rig sub-steps at 1/480 off
`_physics_process`, so **lowering this is a feel change, not a free saving.**

> **The rig sub-step was investigated as a performance lever on 2026-07-31 and
> deliberately left alone.** `CharacterRig` runs two springs at 1/480 s, i.e. 8
> sub-steps per body per physics frame, which at 25 bodies looks like a lot of
> integration. It is not where the time is: ablating the entire rig tick — springs,
> limb sim, gait and all — across the whole 25-body crowd moved a ~35 ms frame by
> **~1.4 ms (4%)**, and the sub-step loop is only a fraction of that. Scaling the
> sub-step rate by distance or under load could therefore recover well under a
> millisecond, in exchange for putting a hand-tuned landing (the spring numbers
> are the spike's, and the sub-stepping is explicitly *"NOT AN OPTIMISATION
> DETAIL — IT IS THE LANDING"*) onto a variable integration budget that would make
> the feel depend on how busy the screen is. Bad trade. Not done.
`max_physics_steps_per_frame` (default 8) is the other mobile-relevant knob — a
lower value makes a hitching phone slow down rather than spiral — but it is
untested here and changes gameplay timing, so it is left alone and noted.

---

## 5. Asset size — what is actually true

**The plan's premise for 6.5 is false for Godot 4.6, and the pass was already
done by the engine.**

`assets/` is 58.3 MB of source, 57.9 MB of it audio. But **source size is not
ship size** — what ships is the imported artefact.

| | source | shipped |
|---|---|---|
| 187 SFX WAVs | 17.46 MB | **3.93 MB** (QOA) |
| 44 SFX OGGs | 3.86 MB | 4.64 MB |
| 6 music MP3s | 36.43 MB | **36.44 MB** |

Godot 4.6 imports WAV as **QOA by default** (`compress/mode=2`). Verified by
probe: a freshly copied `.wav` given to `--import` came back with
`compress/mode=2` written by the engine, with no `.import` file to inherit it
from. All 187 already carry it. **There was no raw-WAV problem to fix.** (This
also means the git-ignored `.import` files are not losing the setting — a fresh
clone regenerates the same thing.)

**Live import payload ≈ 44 MB**, of which **36.4 MB (83%) is music**. The
`.godot/imported` folder is 122 MB, but 78 MB of that is `.ctex` orphaned from
the deleted `/Effects/` and `/Music/` staging folders and will not ship.

### The one real size win, and it needs a human

Godot ships MP3 as-is; there is no import-side quality knob. The music is CBR at
**320 / 256 / 192 kbps** — mastering bitrates, ~23 minutes total:

| file | size | bitrate |
|---|---|---|
| `boss_theme.mp3` | 9.01 MB | 320 kbps |
| `unexplored_moon.mp3` | 7.89 MB | 192 kbps |
| `lord_of_the_land.mp3` | 5.69 MB | 256 kbps |
| `combat_theme.mp3` | 5.01 MB | 192 kbps |
| `for_tomorrow.mp3` | 5.01 MB | 192 kbps |
| `arcadia.mp3` | 3.82 MB | VBR |

Re-encoding to **~96–112 kbps Ogg Vorbis** — transparent for game music under a
phone speaker or earbuds — lands around **15–19 MB, saving roughly 17–20 MB, or
about 40% of the entire shipping payload.**

Not done here, deliberately: it needs `ffmpeg` (not installed on this machine),
it re-encodes lossy-on-lossy so it should be **listened to**, and it requires
editing the six paths in `Music.gd` (`.mp3` → `.ogg`), which is another agent's
file. Recipe when someone wants it:

```
ffmpeg -i boss_theme.mp3 -c:a libvorbis -b:a 112k boss_theme.ogg
```

`hub_ambience.wav` (1.68 MB) is already fine — it imports to QOA like the rest.

---

## 6. The instruments

Before Phase 6 there was **no performance instrumentation in game code at all** —
not one `Performance.get_monitor` call outside a vendored addon.

### `PerfOverlay` — autoload `Perf`, on the device

**F3**, or a **three-finger tap** on a touchscreen. The gesture is the point: the
phone has no F3, and an instrument you cannot reach on the device you are
profiling is not an instrument. Three fingers because one and two are gameplay
(the twin-stick), so a third finger cannot be produced by playing.

Shows FPS, **worst frame time in the last second**, process/physics CPU ms, draw
calls, node count, active 2D bodies, VRAM, live entities against the 25 ceiling,
both pool occupancies, and the resolved quality tier. Panel tints amber past
16.7 ms and red past 33.3 ms.

`worst` is the headline, not FPS, because a 16 ms average with one 90 ms hitch
per second reads as "60 fps" on any counter that reports a mean and reads as a
stutter to the player.

Samples at 4 Hz and does nothing while hidden, so it ships.

### `tools/stress_mobile_entities.gd` — the crowd, headless

```
... --script tools/stress_mobile_entities.gd ++entities=25 ++seconds=15 ++quality=low
```

Spawns the 25-entity ceiling on the shared `SimArena` stage, spread to match the
real 960 px room so collision density is representative.

**Desktop baseline, measured 2026-07-31** (Godot 4.6.2, this machine):

| entities | physics ms | process ms | total | per entity |
|---|---|---|---|---|
| 1 | 0.90 | 1.22 | 2.12 | 2.121 |
| 8 | 2.99 | 1.27 | 4.27 | 0.533 |
| 25 | 5.47 | 1.63 | **7.09** | 0.284 |

**Scaling is sub-linear** — 3.1× the entities costs 1.7× the physics — so there
is no O(n²) hiding in the crowd. That is the good news.

> ⚠ **THE 7.09 FIGURE ABOVE IS A FLOOR, NOT A CEILING, AND WAS READ AS A CEILING
> FOR A WHILE.** That run measured a crowd *walking*. Nothing in it ever cast
> anything, so the magic-circle sigils now on all 22 spells, the spell-vs-spell
> reaction sweep, the impact-frame arbiter, the element ailments and every
> particle burst contributed exactly zero to it. The table is kept because the
> sub-linear scaling result is still valid — it is the crowd's own cost — but it
> is not the frame.

### With spells actually being cast (`++casting=1`), 2026-07-31

Same 25 entities, the real roster cycled through the real dispatcher:

| concurrent spell effects | CPU per frame |
|---|---|
| 0 | 8.7 ms |
| 1 | 14.2 ms |
| 4 | 20.9 ms |
| 9 | 32.3 ms |
| 19 | 34.3 ms |

**Roughly +2.6 ms of desktop CPU per live spell effect**, and until the VFX
budget landed nothing capped the count. This is the largest single cost driver
in the frame — far larger than the rig (~1.4 ms for all 25 figures), the enemy
AI, or the reaction sweep (~0.9 ms), all three of which measure within noise of
each other by ablation.

**The sober read:** ~30 ms of CPU at the spec's own 8-effect ceiling, on a
desktop, with the GPU contributing nothing. A three-year-old mid-range Android
core is roughly 3–5× slower single-threaded, which puts that frame at **~90–150
ms before a single pixel is drawn.** The 25-entity crowd is not the problem; the
spells on top of it are. Treat both as numbers that must be *measured* on device.

> **Two harness bugs found and fixed on 2026-07-31, both of which made earlier
> numbers untrustworthy:**
>
> - **`++quality=low` had never once forced LOW.** It ran inside `_initialize()`,
>   where the root is not yet the active tree, so the `Tuning` lookup printed
>   "Can't use get_node() with absolute paths from outside the active scene tree",
>   returned null, and the null-guard meant to make it safe under `--script`
>   swallowed the failure. Every "LOW" figure the harness printed was a HIGH run
>   wearing a LOW label. It now runs on the first physics tick and prints what it
>   resolved to.
> - **Runs were not deterministic.** Spells draw from the global RNG and the crowd
>   was being killed off mid-run, so the second half of a measurement was a
>   different experiment from the first, and two runs of the same command
>   disagreed by 40%. `++seed` and `++immortal` fix both; the cast count is now
>   identical run to run.
>
> **Wall-clock on this machine still is not trustworthy to better than ~±30%.**
> Identical seeded 37-cast runs timed 33 ms and 57 ms twenty minutes apart purely
> from background load. That is why the harness now also prints deterministic
> WORK counters (particles requested vs emitted, debris requested vs made, decals
> spawned vs skipped) and why `tools/slice_test_perf_budget.gd` asserts against
> those rather than against times.

> ⚠⚠ **EVERY NUMBER ON THIS PAGE EXCLUDES `_draw`. ALL OF IT.** Measured
> 2026-08-01, not assumed.
>
> `Performance.TIME_PROCESS` and `TIME_PHYSICS_PROCESS` are what every harness here
> reads, and **the process counter closes before the canvas draw pass**. A probe
> with 200 nodes each issuing 200 `draw_line` calls — 40,000 draw primitives per
> frame, confirmed running by a counter inside `_draw` itself — moved `TIME_PROCESS`
> by **0.0000 ms**, while the wall-clock between the same two frames moved by
> **9.2 ms**.
>
> So the ~30 ms at the 8-effect ceiling is `_process` + `_physics_process` +
> physics + node churn. The entire `_draw` cost of all 32 spell spectacles — which
> is where a procedural-vector game like this one puts most of its per-frame work —
> **is on top of that figure, not inside it.** The frame is worse than this document
> has ever said.
>
> (`_draw` *does* run under `--headless` — 21 draws in 21 frames — so it is being
> executed and simply not counted. Do not "fix" this by assuming headless skips it.)
>
> ⚠ **And do not reach for wall-clock to fill the gap.** It is not merely noisy
> here, it is *non-monotonic*: an A/B probe drawing 250 rings of 60 segments each
> reported 0.42 µs/node, while the same probe at 200 segments reported 9.14 µs/node.
> The cause is that a headless frame absorbs extra work into idle time until it
> crosses the pacing budget, so cost is invisible right up until it is not — the
> same family of trap as the harness that once confidently reported a perfect
> 16.67 ms. **Use deterministic work counters** (`CombatVfx` / `DebrisChunk` /
> `ScorchDecal` / `ElementFx` / now `MagicCircle` all expose `work_stats()`), which
> is why `tools/slice_test_perf_budget.gd` asserts against counts and not times.
>
> ⚠ Headless runs the **dummy renderer**. Every number above is CPU. The GPU
> cost — which is what actually decides whether this holds 30 fps on a tile GPU —
> is not measured and cannot be measured this way. Only §1.6 answers that.
>
> The harness also timed wall-clock between physics frames in its first version
> and confidently reported 16.67 ms — which is 1/60 exactly, i.e. it was
> measuring the engine's frame *pacing*, not the work. It now reads Godot's own
> `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` counters. Worth remembering before
> trusting any similar harness.

---

## 6b. The worst frame in the game is a script load — and it is fixed

Nothing above measures the single largest stall this game produces, because it
happens once per spell type and every harness here averages it away.

`SpellCaster` reaches its 25 spectacle scripts with `load()` by **path** rather
than `preload`, deliberately, so headless tools can call `cast()` without
early-compiling the autoload-referencing scenes (`SpellCaster.gd:8-9`). The cost
of that design is that the **first** cast of each spell type parses and compiles
its script on the spot. Measured by `tools/probe_cast_warmup.gd`, which times
casts #1/#2/#3 of every spell and prints `ResourceLoader.has_cached()` beside
each:

| | rows still cold | worst first cast | Σ first casts |
|---|---|---|---|
| no warm-up | 18 of 38 | **126 ms** | 1411 ms |
| after `SpellCaster.warm()` | **0** | **3.1 ms** | **16.5 ms** |

The `has_cached` column is the proof rather than the timer: every expensive row
read `no` and every cheap row read `YES`. `chain_lightning` (ChainBolt, cold)
cost 45.7 ms; `arc_of_fools` — *the same script*, now warm — cost 0.51 ms.

**On the target phone that is a 130–630 ms freeze, and it lands the first time the
player throws each spell — i.e. all through the first minute of play.** It is the
`worst`-frame number §1.6 tells you to watch, and averages will never show it.

**`SpellCaster.warm()`** pays all of it up front: 22 scripts, ~718 ms on this
desktop, idempotent, guarded so it runs once per session. It is a *when* fix, not
a *what* fix — the by-path `load()` design is untouched, because headless tooling
depends on it.

> ⚠ **It still needs a call site.** `SpellCaster.warm()` is not called by anything
> yet. It belongs wherever there is already a loading beat: the **lobby/title
> screen** hides it completely (the player is idle and the cost is invisible), and
> a **floor build** is the fallback. One line, no arguments.
>
> ⚠ **Nested loads are the part that rots.** `frozen_comet` measured a 61 ms first
> cast while its own arm's script was already cached, because `MeteorSigil` forks
> to `IceSpikeLine` from inside `rain()`. `tools/slice_test_spell_warm.gd`
> cross-checks the warm list against the dispatcher's own constants and fork tables
> so a new spectacle cannot be added without being warmed.

## 7. Levers if the device struggles

In order. Each is a smaller loss than the one after it.

1. **`graphics_quality` is already LOW on mobile** (`TuningConfig`, resolves via
   `OS.has_feature("mobile")`). That already turns off `post_process.gdshader`
   (3 screen fetches, one of them `filter_linear_mipmap` — a mipmap chain
   regenerated from the framebuffer *every frame*), downgrades ImpactFrame's
   INVERT/SILHOUETTE screen plates to the paint-only COLOR_FIELD, and thins the
   ambient motes 40→16. **Set `graphics_quality = LOW` on the desktop to see the
   phone's picture without a phone** — that is the whole reason it is a dial and
   not an `OS.has_feature` check.

   Since 2026-07-31 LOW is also a **CPU/content** lever, not only a shader gate:
   it carries a tighter live-spell-VFX budget (5 concurrent effects against
   HIGH's 8), which measurably thins particles ~26%, debris ~27% and scorch
   decals ~80% on a crowded screen. That mattered because everything LOW gated
   before was GPU-side, while the measured problem at the ceiling is ~30 ms of
   *CPU* before anything is drawn — LOW was saving nothing on the axis that was
   actually over budget.
2. **`viewport/hdr_2d.mobile=false`** in `[rendering]`. Halves colour-buffer
   bandwidth. Costs the bloom; retune `combat_glow.tres`'s `glow_hdr_threshold`
   below 1.0 with `background_mode = Canvas` to get some of it back.
3. **`anti_aliasing/quality/msaa_2d.mobile=0`.** The rig's lines will crawl. Try
   this only after 2.
4. **Lower the live-SPELL-VFX budget** below 8 in
   `SpellReactorNode.SPECTACLE_BUDGET_HIGH` / `_LOW`. Measured at ~2.6 ms of
   desktop CPU per concurrent effect, this is the steepest lever on the list and
   it degrades gracefully by design — the garnish thins, no spell is ever dropped
   or hidden. Try it before touching the entity ceiling below.
5. **Lower the live-entity ceiling** below 25 in `Encounter`. A gameplay change,
   and the one most likely to be *felt*; make it deliberately. Note the crowd is
   the *smaller* half of the cost: 25 entities alone are 8.7 ms, the spells on
   top of them are the other ~22 ms.
6. **`renderer/rendering_method.mobile="gl_compatibility"`.** Last resort — it
   removes `hdr_2d` and MSAA outright (§4), so it is a different-looking game.

---

## 8. Known gaps

- **No APK has been built.** Everything above is verified as far as the SDK
  boundary and no further. The preset itself *is* verified — Godot parses it and
  fails only on the two missing human prerequisites.
- **Touch is untested on glass.** Phase 6.7 is not in this pass: there is still
  **no pause button**, so on a phone the settings menu is unreachable (Esc-only).
  `TouchControls.gd:41-43` self-documents its numbers as untested guesses.
- **The perf overlay's thermal read is a method, not a result.** Nobody has held
  the phone for ten minutes yet.
- **Nobody has called `SpellCaster.warm()` yet** (§6b). The 44-126 ms first-cast
  freezes are fixed in code and still live in the build until it has a call site.
- **The frame is over budget on CPU alone, at the spec's own ceiling.** ~30 ms
  desktop with 8 concurrent spell effects and 25 entities → ~90–150 ms on the
  target device. The VFX budget bounds the *worst* case (it was unbounded), but
  it does not make the in-budget case cheap. The remaining cost is inside the
  spell spectacles' own `_process` / `_physics_process` / `_draw`, spread thinly
  across ~32 scripts rather than concentrated anywhere ablation can find. That has
  now been profiled *inside* — `tools/profile_spectacles.gd` gives per-spell and
  per-SCRIPT attribution, and found `MagicCircle` (the sigil that opens on 31 of
  the 38 spells) was **87.9% of all spectacle `_draw` cost**. It now tessellates to
  a quarter-pixel sagitta budget instead of a flat segment count, which halved its
  geometry at both quality levels with no visible change; `tools/profile_magic_circle.gd`
  is the deterministic bench for it. Steady-state `_process` per spectacle measured
  1-15 µs and is not worth chasing. The older per-spell tool `tools/stress_spell_cost.gd` casts one
  spell id at a time and is the tool for it, but its per-spell deltas are still
  noisy with cross-contamination from lingering zones and DoTs (settle window
  needs to exceed the longest spell lifetime, currently it does not).
- **The pooling question is answered for the shared services and open for the
  spectacles.** `Sfx` (32 voices), `DamageNumber` and `CombatVfx` are real pools.
  Spell spectacles are still `.new()` + `add_child()` per cast, and co-op doubles
  that because every peer rebuilds them — but they are 32 scripts in another
  agent's ownership, and the measurement says their per-frame cost dominates
  their allocation cost, so pooling them is not obviously the first move.
- **Music re-encoding** (§5) is the largest single size win and is not done.
- **`max_physics_steps_per_frame`** is untuned for mobile (§4).
