# The Look — Reactive Screen-Space Post-Process Grade

**Date:** 2026-07-22 · **Branch:** `v2.0-tower` · **Status:** approved, building

## Goal

One cohesive cinematic grade over the combat arenas that makes everything read richer and *punchier* — and, crucially, **reacts to gameplay** (the "wow"). Cosmetic only: no gameplay logic changes, complements the existing `WorldEnvironment` bloom. Maker's ask: "awesome to see and play, fun, simple, insane." So the base grade is tasteful; the insanity comes from **reactivity** — the screen smears and ripples when things happen.

## Why a screen-space shader layer

The game already has HDR-2D bloom (`combat_glow.tres`) and a `CombatCamera` trauma model. A single full-screen shader reading the framebuffer gives full control (aberration, haze, grade, vignette, shockwave) AND can be driven by live uniforms off the trauma the camera already tracks. Rejected alternatives: tuning only the `WorldEnvironment` (static, no reactivity) and per-camera `CanvasModulate` (too limited).

## Components

### 1. `scenes/combat/post_process.gdshader` (`shader_type canvas_item`)
Reads `hint_screen_texture`; a full-rect `ColorRect` outputs the graded frame. In order:
- **Chromatic aberration** — radial R/B split from screen-center; px magnitude = `aberration_base` (idle whisper, lens feel) + `aberration_trauma * u_trauma` (spikes on hits, ~4px at the edges). *The reactive punch.*
- **Shockwave ripple** — a decaying radial UV displacement ring (`u_shock` = center.xy + age, `u_shock_amp`), fired on epic moments / impact frames. *The headline "insane" beat.*
- **Heat-haze** — animated sinusoidal UV warp, amplitude `u_heat`, pulsed on fire beats and decays.
- **Color grade** — lift/gain/gamma + saturation + a warm-shadow/cool-highlight split-tone; all uniforms so floor bands re-tint.
- **Vignette** — soft, theme-tinted radial frame.
- **Grain** — subtle, low default (uniform-gated; drop if it muddies).

### 2. `scripts/combat/PostProcess.gd` (`class_name PostProcess extends Node`)
- `static add(parent)` — idempotent build (mirrors `Atmosphere.add_glow`): a `CanvasLayer` (layer 8: above world + atmosphere vignette@1, below HUD@50/60/100) holding the `ColorRect` + `ShaderMaterial`. Joins group `post_process`.
- `_process` (skips when disabled): mirrors the active `combat_camera` trauma → `u_trauma`; decays `u_heat`; advances/decays the shockwave; re-reads the enable toggle so a pause-menu switch is live.
- Static pokes (find the node via group; no-op if absent — e.g. the calm hub): `pulse_heat(amount)`, `shock(strength, center=screen-center)`, `set_theme(tint)`, plus enable via `Tuning`.

### 3. Reactivity plumbing (tiny, decoupled)
- `CombatCamera.trauma()` getter (new) — the single source `PostProcess` polls. Hits smear the screen for free; **no new call sites** on the hit path.
- `Juice.epic_moment` / `Juice.impact_frame` → `PostProcess.shock(strength)` (the juice hub already fans out to cameras/Sfx — right place).
- `Vfx.explosion` → `PostProcess.pulse_heat(size-scaled)` (the existing fire chokepoint).
- `Arena` floor build → `PostProcess.set_theme(tint)` alongside `Atmosphere.build_wash`.

### 4. Wiring + safety
- `PostProcess.add(self)` at the two `Atmosphere.add_glow` sites: `Arena` + `VersusArena`. Hub stays calm.
- `TuningConfig.post_process_enabled: bool = true` — accessibility / low-end off-switch, live via `Tuning`.
- Mobile-safe: one full-screen pass (~6 samples). `ColorRect.mouse_filter = IGNORE` so it never eats touch input.
- SP unaffected (pure visual layer, present in SP and co-op identically).

## Verification
- `tools/postprocess_capture.gd` (GUI binary): idle look, a forced-`u_trauma` frame, a fired shockwave, a heat pulse → PNGs (my eyes).
- Full `slice_test_*` sweep stays green (cosmetic — nothing gameplay touched).
- `--headless scenes/Main.tscn --quit-after` boot check clean.
- Then maker F5/F6 for feel.

## Out of scope (later)
Per-spell shader VFX (chose whole-scene first), animated sprite pipeline, hub grade, a full pause-menu slider row for each grade knob (ship the on/off toggle now).
