# Task 1.2 — the editor loop, and the capture that had never written a file

**Date:** 2026-10-18 · **Lane:** QA · **Where:** PC · **Board:** Phase 1, row 1.2

Board asked for: *install Godot-MCP-Native, disable the two old MCP addons, prove the
screenshot and pixel-diff loop on boss_capture.* Proof column: *a diffed pair of
screenshots in proof/.*

---

## What the files here show

| File | What it is |
|---|---|
| `boss_p1.png` | The Ashspire Guardian, phase 1 (waking colossus). |
| `boss_p2.png` | Phase 2 (fury) — one bar segment gone. |
| `boss_p3.png` | Phase 3 (ashfall) — the streak wall, two adds up. |
| `pair_a.png` / `pair_b.png` | **The diffed pair**: two separate runs of `boss_roster` guardian. |
| `pair_diff.png` | Their pixel-diff heatmap. Red = moved, dim grey = unchanged. |

## 1. `boss_capture` had never written a frame, and said so in one line

The tool is dated and so is its approach. It forced `GameState` to floor 5, instantiated
the Arena, settled 70 frames and expected the guardian to be standing there. That was true
of an older `Encounter`. It is not true now: the guardian arrives in `Phase.BOSS`, which is
the **end** of a floor, after WAVES and SURGE have been fought through. At frame 70 there is
no boss and never will be. `_find_boss()` returned null, the tool printed
`boss_capture: no boss spawned` to stderr and quit, and `run_capture.py` correctly reported
`NO FRAMES WRITTEN`. `user://boss_p1.png` did not exist on this machine.

The Arena had already grown the seam this needed — `Arena.boss_rush`, a static whose own
comment reads *"set true (by the duel's Esc menu, **or by a tool**) before this scene
loads"*. It spawns the guardian alone, immediately, with boss framing. Two other callers
(`boot_check.gd`, `VersusArena._enter_boss_fight`) already use it. This capture was never
migrated. It is now.

Arming it is also the safer path: boss_rush leaves `GameState` untouched, so a capture can
no longer leave a half-begun climb in the save. The old code wrote `_run_active` and `_floor`.

**Reproduce:** `python python-tools/run_capture.py boss_capture` → three frames.

## 2. ⚠ `boss_capture` is NOT a valid subject for a regression diff

This is the finding that matters more than the fix, and it would have made the loop lie.

Diffing the post-addon-swap frames against the pre-swap baseline gave 8.6% / 20.4% / 36.2%
changed pixels — which reads as "the addon swap changed the rendering". It did not. Two
runs of the **same code with the same addons** differ by 15.9% / 20.6% / 35.1%. The
run-to-run noise is *larger* than the across-change difference.

`boss_capture` runs a live arena: the boss acts, embers drift, spell icons spin, the hero
casts. The heatmap says so plainly — every animated thing is red, while every static HUD
element (the title card, the bar frames, the pause button, `ARCANIST`, the key caps) is
pixel-identical grey.

So: **`boss_capture` is for LOOKING at, never for diffing.** A diff against it can only ever
say DIFFERENT, which is a guard that carries no information.

## 3. The subject the loop CAN guard

`boss_roster_capture` renders static posed sheets. Two consecutive runs:

| Sheet | Changed px | % |
|---|---|---|
| scribble | 5 | 0.000% |
| etcher | 794 | 0.076% |
| cartographer | 1,188 | 0.113% |
| sensei | 1,358 | 0.129% |
| eraser | 1,421 | 0.135% |
| illuminator | 2,652 | 0.253% |
| guardian | 15,697 | 1.496% |

Six of seven sit under the differ's 0.5% default gate. Only `guardian` exceeds it, and
`pair_diff.png` here shows why: its ember aura animates. `proof/_baseline/` now holds these
seven sheets, so `--against-baseline` has a subject whose movement means something.

## 4. The differ, and the guard that is the point of it

`python-tools/pixel_diff.py`. Exit 0 = match, 1 = differs, 2 = unusable input.

A naive differ reports *"0.00% different — identical"* for two blank images, which is
exactly what a `--headless` capture produces (dummy renderer draws nothing, every tool still
reports success). That reading is indistinguishable from a clean pass. So each input must
first prove it is a drawn frame — enough distinct colours and enough luma spread — and a
blank one is a named refusal, never a pass.

**Sabotage pass — every one of these was run, and seen:**

| Sabotage | Expected | Got |
|---|---|---|
| real frame vs flat black | refuse | `UNUSABLE: 1 distinct colour, luma range 0/255` + exit 2 |
| flat black vs flat dark grey | refuse (**not** "identical") | exit 2 |
| frame vs itself | match | 0 px, 0.000%, exit 0 |
| phase 1 vs phase 2 | differ | 349,084 px, 33.275%, exit 1 |
| 40 px nudged out of 1,049,088 | counted exactly | 40 px, 0.004%, exit 0 |

The two blank cases are the ones that matter: that is the shape of lie this repo keeps
meeting, and the guard has now been seen to fire.

## 5. The addon swap

- `godot-project/addons/godot_mcp/` — Godot-MCP-Native 1.0.8 (MIT), 99 files, from
  `art-source/third_party/Godot-MCP-Native.zip`.
- `project.godot` `[editor_plugins]` now enables `auto_reload` + `godot_mcp`. The two
  HaD0Yun addons (`godot_mcp_editor`, `godot_mcp_runtime`) are **disabled**, not deleted.
- The `MCPRuntime` autoload is gone. The release gate names it a dev bridge that "opens a
  listening socket at boot"; it no longer loads in every capture and every run.
- Export excludes + `release_gate_lib.DEV_PATHS` + `slice_test_mobile_config` now carry
  `res://addons/godot_mcp/*`. A disabled plugin's **files** still pack, so the two old ones
  stay excluded too.
- `.mcp.json` points at the native server: `http://localhost:9080/mcp`.

## ⚠ What is NOT proven here, and needs the maker

**The native MCP tools have not been called.** Claude Code reads `.mcp.json` at startup, so
the `godot` server only becomes callable in a **new session**, with the Godot editor open.
Everything above was done through `run_capture.py`, which drives the GUI binary directly and
needs no MCP at all — so the capture half of the loop is proven and the interactive-editor
half is not. First thing next session: open the editor, confirm the tool list, take an
editor screenshot.

**A feel note, not a bug:** in `boss_p3.png` the ashfall streaks are dense enough that the
guardian's body is nearly invisible behind them. Phase 3 should probably still show its
boss. The maker's call.
