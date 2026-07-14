# Slice 0 — Final Whole-Branch Code Review

**Branch:** `v2.0-tower`  **Base:** `429d6ab` (main)  **Reviewer gate:** integration, pre-playtest
**Scope:** `scripts/combat/`, `scenes/combat/`, `project.godot`, `tools/slice0_test_targeting.gd`

## Verdict: READY-TO-PLAYTEST

The core combat loop is correctly wired end-to-end. I traced every integration path the spec flagged as untested-at-runtime and they hold up. **No CRITICAL findings.** The one thing most likely to break — spell→enemy collision detection — is actually correct. Findings below are one feel/design integration issue (IMPORTANT) and several MINOR polish/robustness notes. None block a playtest.

**Counts:** CRITICAL 0 · IMPORTANT 1 · MINOR 4

---

## Verified-working integration paths (the important part)

These were the load-bearing "never exercised with input" paths. All confirmed correct by tracing wiring + collision layers:

1. **Casting damages enemies — WORKS.** `Spell` (Area2D, `monitoring=true`) connects `body_entered → _on_hit → _try_damage`. No combat `.tscn` sets `collision_layer`/`collision_mask`, so every body/area is on the engine default **layer 1 / mask 1**. `Enemy` is a `CharacterBody2D` on layer 1 with a real `CollisionShape2D`; the Spell's mask 1 intersects it, both have shapes, monitoring is on → `body_entered` fires. `_try_damage` gates on `is_in_group("enemy")` + `has_method("take_damage")` → damage applied, `queue_free`. **Correct.**
   - Notable good call: `monitorable=false` on the Spell does **not** suppress its own `body_entered` (monitorable only governs whether *other* areas detect this one). The common misconception was avoided.
   - The Spell also overlaps the Hero on spawn and overlaps Walls in flight; both are correctly ignored by the `"enemy"` group check and the projectile is not freed on them.
2. **Auto-aim — WORKS.** `Hero._cast` passes `get_tree().get_nodes_in_group("enemy")` to `Targeting.aim_direction`. Enemies join `"enemy"` in `Enemy._ready()` before they process. Empty-list/zero-vector fallbacks in `Targeting` are safe (`facing` defaults to `RIGHT`, never zero).
3. **Contact damage — WORKS.** `Enemy` caches the hero via group `"hero"` (baked into `Hero.tscn` groups **and** re-added in `_ready`), then `distance_to < 22.0` + `has_method("take_damage")` → `hero.take_damage`. Box half-extents (9 + 10 = 19px contact distance) sit under the 22px threshold, and the distance check is independent of physical collision, so it fires reliably. Cooldown gate (0.8s) is sound.
4. **Juice — WORKS.** `CombatCamera._ready` joins `"combat_camera"` and exposes `add_shake`; `Juice.shake_camera` iterates that group and calls it. `Juice.hit_stop` sets `Engine.time_scale = 0.05` then awaits `create_timer(duration, true, false, true)` — `process_always=true` + `ignore_time_scale=true` means the restore timer runs in real time and reliably restores `time_scale = 1.0` even while time is slowed. Static-function `await` is valid in GDScript, and calling `Juice.hit_stop()` fire-and-forget (no `await` at the call site) correctly launches the coroutine. Overlapping hit-stops converge back to `1.0` (no stuck slow-mo).
5. **Name/type consistency — CLEAN.** Groups `"hero"`/`"enemy"`/`"combat_camera"`, methods `take_damage`/`add_shake`/`launch`/`hit_stop`/`shake_camera`, and `Targeting.nearest`/`aim_direction` signatures all match across files and the test.

---

## IMPORTANT

### I1 — Hero and enemies share collision layer 1, so the Hero cannot dash *through* enemies (contradicts the stated dodge fantasy)
**Files:** `scenes/combat/Hero.tscn`, `scenes/combat/Enemy.tscn` (neither sets `collision_layer`/`collision_mask`; both default to layer 1 / mask 1).

**What's wrong:** Because the Hero (`CharacterBody2D`, mask 1) and enemies (layer 1) are on the same layer, `Hero.move_and_slide()` physically collides with enemy bodies. The Task 6 playtest goal is explicitly *"move, dash through enemies... Is dodging-by-dash fun?"* — but a dash into an enemy is **blocked**: the hero stops/slides against the enemy body instead of passing through. Enemies also mutually collide (all layer 1), so they clump and jitter against each other.

**Failure scenario:** Maker dashes toward a cluster to escape; the dash halts on the first enemy body, the hero gets pinned between an enemy and a wall, and the "dash to dodge" feel the slice exists to prove reads as clunky rather than snappy.

**Fix:** Split layers. Put enemies on their own layer (e.g. layer 2) and remove layer 2 from the Hero's `collision_mask` so the hero passes through enemy bodies (contact damage still fires — it uses `distance_to`, not physical collision). Keep enemies masking layer 1 so they still collide with walls. **Dependency:** the `Spell` must then detect layer 2 — set the Spell's `collision_mask` to include the enemy layer (e.g. `1|2` or just `2`), otherwise this fix silently breaks spell hits (I1's fix and path #1 are coupled). Alternatively, if the maker *wants* enemies to block the hero, this is fine as-is — flag it as a conscious call at playtest rather than an oversight.

---

## MINOR

### M2 — Enemies can spawn on top of the Hero
**File:** `scripts/combat/Arena.gd:34-37`. `_spawn_enemy` places enemies at a uniformly random point in the arena with no minimum distance from the hero. An enemy spawning within 22px deals instant, unavoidable contact damage. Fix: reject spawn positions within, say, 150px of the hero (loop or reflect).

### M3 — Spells pass through walls and fly out of the arena until lifetime expiry
**File:** `scripts/combat/Spell.gd:37-45`. Walls are on layer 1 so `body_entered` fires for them, but `_try_damage` only frees on `"enemy"` bodies, so a spell cast away from enemies travels through the wall and off-screen for its full 1.4s `LIFETIME`. Cosmetic. Fix (optional): free the spell on any non-enemy body that is a `StaticBody2D`, or give walls a distinct layer and have the spell free on wall contact.

### M4 — Leftover `Conversation` autoload is still active in the Arena and steals Enter
**File:** `project.godot:25` (`Conversation="*res://scenes/Conversation.tscn"`), `scripts/Conversation.gd:160-162`. The hub's `Conversation` singleton still loads in the combat scene. `_unhandled_input` opens a broadcast text bar on the `chat` action (Enter). In the arena the `Hero` polls input (`Input.is_action_pressed`) and does **not** gate on `Conversation.is_input_open()`, so pressing Enter pops a stray hub input bar over the toy while the hero keeps moving/casting — harmless but confusing, and it also runs `set_auto_accept_quit(false)`. No crash (broadcast mode needs no NPC). Slice 0 accepts this (isolation deferred to Slice 1); worth removing the autoload from the run for a clean playtest/clip if Enter gets pressed. Combat input (LMB `cast`, Space `dash`) is unaffected because polling reads global input state regardless of event consumption.

### M5 — Spell knockback calls `move_and_slide()` on an enemy that may already be queued for free; double juice on kill
**File:** `scripts/combat/Spell.gd:39-44`. On a killing hit, `take_damage → _die → queue_free()` runs, then the knockback block still does `node.velocity += ...; node.move_and_slide()` on the queued node (valid until end of frame — no crash, just wasted work). Separately, a killing spell fires `hit_stop` + `shake_camera(6)` from `Spell` **and** `hit_stop` + `shake_camera(8)` from `Enemy._die` — doubled shake/hit-stop per kill. Both are tune-time concerns; note them so the maker knows the stacking is intentional, not a bug, when tuning juice.

---

## Non-findings (checked, deliberately not reported)

- Untuned magic numbers (speeds, cooldowns, damage, shake amounts) — spec says feel is playtest-tuned.
- No dash i-frames yet (`is_dashing` exists unused for that) — plan states i-frames are a later use.
- `Enemy._flash` await vs `queue_free` race — guarded by `is_instance_valid(self)`, safe.
- `area_entered → _on_area_hit` is effectively dead (no monitorable areas exist) — harmless.
- Static-coroutine `await` in `Juice`/spell-frees-on-first-hit/multi-enemy same-frame hit — all behave correctly.
- Targeting unit test constructs off-tree `Node2D`s (global_position == local) — valid.
