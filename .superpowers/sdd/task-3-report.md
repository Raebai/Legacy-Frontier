# Task 3 report — Movement weight (Hero.gd + TuningConfig.gd)

> Note: an older, unrelated "Task 3 Report — Dash" (Slice 0, commit `e39e3ed`)
> previously lived at this path. This report supersedes it for the current
> "Stick Fight Feel Foundation" plan's Task 3 (movement weight).

## What changed

**`godot-project/scripts/combat/TuningConfig.gd`** — added five new `@export`
knobs under the existing "Hero movement" group, defaulting to the new
"weighty" targets specified in the brief:

```gdscript
@export var move_gravity_rise: float = 2600.0  # rise gravity (real weight, not floaty apex)
@export var move_gravity_fall: float = 3000.0  # fall gravity (heavier coming down)
@export var move_jump_velocity: float = -740.0 # jump launch velocity (a committed hop, not a float)
@export var move_air_accel: float = 750.0      # air accel/decel (low = no mid-air free-steer)
@export var move_max_fall: float = 1400.0      # terminal fall speed clamp
```

`data/tuning.tres` was NOT touched — it only overrides a handful of fields
(`hero_speed`, `dash_speed`, `dash_time`, `hurt_hit_stop`, `hurt_shake`,
`melee_hit_stop`); every other `@export` field, including all five new ones,
falls back to the class default declared above when the `.tres` doesn't
mention it. So the maker gets the new 2600/3000/-740/750/1400 defaults
out of the box, and can still open the Inspector on `tuning.tres` and add
overrides live at runtime via Remote -> Tuning, exactly like the existing
knobs.

**`godot-project/scripts/combat/Hero.gd`** — rewired the five movement
const reads inside `_physics_process` to go through the existing `_tune(key,
fallback)` helper (unchanged, at `Hero.gd:327-332`), keeping the old
consts (`GRAVITY`, `GRAVITY_FALL`, `JUMP_VELOCITY`, `AIR_ACCEL`, `MAX_FALL`)
as the fallback argument so nothing breaks if the field is ever missing or
renamed:

- `:559-560` — asymmetric gravity integration:
  `var g: float = _tune("move_gravity_rise", GRAVITY) if velocity.y < 0.0 else _tune("move_gravity_fall", GRAVITY_FALL)`
  `velocity.y = minf(velocity.y + g * delta, _tune("move_max_fall", MAX_FALL))`
- `:570` — buffered jump fire: `velocity.y = _tune("move_jump_velocity", JUMP_VELOCITY)`
- `:595` — air accel (moving toward input): `_tune("move_air_accel", AIR_ACCEL)`
- `:598` — air decel (no input held, "friction"): `_tune("move_air_accel", AIR_ACCEL)`

## The `_tune` pattern mirrored

Hero.gd already had a live-tuning mechanism used by `hero_speed` (`:592`),
`dash_speed` (`:510`), `dash_time` (`:1203`), `melee_hit_stop`/`hurt_hit_stop`/
`hurt_shake`/`knockback_mult` etc. -- a single helper:

```gdscript
var _tuning: Node = null  # cached /root/Tuning (null in headless tests -> fallbacks)

func _tune(key: String, fallback: float) -> float:
	if _tuning != null and _tuning.cfg != null:
		var v: Variant = _tuning.cfg.get(key)
		if v != null:
			return float(v)
	return fallback
```

`_tuning` is cached from the `Tuning` autoload (`get_node_or_null("/root/Tuning")`)
in `_ready()`. `Tuning.gd` (autoload) loads `res://data/tuning.tres` into
`cfg: TuningConfig`, falling back to `TuningConfig.new()` (pure code
defaults) if the `.tres` is missing. I did not invent any new mechanism --
every one of the five new reads is a direct `_tune("move_x", OLD_CONST)`
call, byte-for-byte the same call shape as the existing knobs.

Two sites (`:595` and `:598`, air-accel and air-decel) intentionally read
the *same* key `"move_air_accel"` -- this matches the pre-existing code,
which already used the single `AIR_ACCEL` const for both accelerating
toward input and decelerating toward zero in the air.

## Scope decision -- two sites left untouched (flagging, not hiding)

`Hero.gd` has two OTHER places that also apply `GRAVITY_FALL`/`MAX_FALL`
directly, outside the movement branch the brief scoped:

- `:484` -- inside the "hold DOWN to go limp" ragdoll-flop branch (a
  distinct cosmetic mechanic, early-returns before the main movement code).
- `:2013` -- inside `_process_downed()`, the co-op "downed, just slump"
  physics (also early-returns, a separate function).

The brief scoped the change to "the movement const reads in
`_physics_process`" via the specific line refs `:19-29` (consts) and
`:595,598` (air accel), and the five knobs it asked for map 1:1 onto the
five reads in the main jump/fall/air-control block (`:559-598`). Ragdoll-flop
and downed-slump are separate physics paths with their own feel intent
(a full stop/slump, not a jump arc) and weren't named in the brief or the
verify section's apex-time formula. I left them as hardcoded consts rather
than guess whether the maker wants them to track the same knobs. Flagging
this explicitly in case the maker wants `move_gravity_fall`/`move_max_fall`
applied there too in a follow-up.

## Test -- `godot-project/tools/slice_test_movement.gd` (new)

Mirrors the `SceneTree` runner shape of `tools/slice_test_coop.gd` /
`tools/slice1_test_blink.gd` (load-at-runtime idiom since `Hero.gd`
references autoloads like `Sfx`/`Targeting`, so it can't be `preload()`ed).

Four test functions, all invoked from `_process()`:

1. **`_test_tuning_knobs_exist_with_new_defaults`** -- instantiates
   `TuningConfig.new()` directly and asserts all five fields equal the
   specified new defaults (2600 / 3000 / -740 / 750 / 1400).
2. **`_test_hero_reads_tuning_knobs_live`** -- instantiates a real `Hero`
   scene and calls `hero._tune("move_gravity_rise", hero.GRAVITY)` etc. for
   all five keys, asserting each resolves to the NEW value, not the OLD
   const. This is the load-bearing check that Hero is actually wired to
   `TuningConfig`, not just that the field exists somewhere.
3. **`_test_jump_apex_matches_gravity_jump_formula`** -- drives the REAL
   `Hero._physics_process()` by hand (`hero.set_physics_process(false)`,
   then call it tick-by-tick, the same pattern used by
   `slice2_test_enemy_archetypes.gd` / `slice3_test_enemy_sideon.gd` for
   Enemy). The hero is placed at `(20000, 20000)` -- open space, no
   collision geometry -- so `is_on_floor()` is false throughout and the
   integration is pure free-flight, isolating gravity/jump from any
   floor/collision variables. Forces the buffered-jump branch to fire by
   poking `_jump_buffer`/`_coyote` directly (mirrors how
   `slice1_test_blink.gd` pokes `hero._move_dir` / `hero._blink_cooldown_timer`
   -- same private-property test idiom already used in this codebase), then
   steps physics ticks until `velocity.y` crosses back to non-negative,
   accumulating elapsed time as the measured apex time. Asserts:
   - jump fires at exactly `-740.0`
   - the analytic apex time from the live knobs (`|jump_velocity| /
     gravity_rise` = `740/2600` ~= `0.2846s`) is within the `0.28s +- 0.06`
     target band
   - the MEASURED (simulated) apex time matches the analytic formula within
     2 physics ticks (~0.033s) of discretization slop
   - the new apex is meaningfully snappier than the old floaty ~0.387s
     apex (`580/1500`)
4. **`_test_air_control_cannot_reach_full_speed_quickly`** -- same
   hand-driven physics approach; holds `move_right` via `Input.action_press`
   (the same headless-input idiom already used by `demo_capture.gd` /
   `sequence_capture.gd` / `verify_feel_capture.gd`) for a 0.1s / 6-tick
   window while airborne. Asserts both the closed-form reachable delta
   (`air_accel * elapsed_time`, independent of `move_toward`'s exact
   overshoot handling) and the actual simulated `velocity.x` stay well
   below full ground run speed (`hero_speed`), proving reduced air control
   without free-steer.

Print statement on success: `movement tests: all PASS` (matches the brief's
requested wording).

## Test command + output

```
$ ./godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_movement.gd
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
[MCP Runtime] Server listening on port 7777
[MCP Runtime] Autoload ready, server starting on port 7777
movement tests: all PASS
WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
ERROR: 1 resources still in use at exit (run with --verbose for details).
```

The trailing `ObjectDB leaked` / `1 resources still in use` warning is
**pre-existing and harmless** -- I confirmed it also fires on the unmodified
`slice_test_coop.gd` (same SceneTree-script-exit idiom across the whole
`tools/` suite; nodes/resources added under `root` aren't explicitly freed
before `quit()`). Not something this task introduced.

### Full sweep -- every `godot-project/tools/slice*_test_*.gd`

Ran all 39 suites (38 existing + the new one) headless, one process each:

```
slice0_test_sfx.gd .......................... PASS
slice0_test_targeting.gd .................... PASS
slice1_test_blink.gd ........................ PASS
slice1_test_destructible.gd ................. PASS
slice1_test_elements.gd ..................... PASS
slice1_test_enemy_attack.gd ................. PASS
slice1_test_music.gd ........................ PASS
slice1_test_nova.gd ......................... PASS
slice1_test_rank.gd ......................... PASS
slice1_test_rig.gd .......................... PASS
slice1_test_telegraph.gd .................... PASS
slice1_test_weapon.gd ....................... PASS
slice2_test_enemy_archetypes.gd ............. PASS
slice2_test_rogue.gd ........................ PASS
slice2_test_runloop.gd ...................... PASS
slice3_test_aiming.gd ....................... PASS
slice3_test_destructible_terrain.gd ......... PASS
slice3_test_enemy_abilities.gd .............. PASS
slice3_test_enemy_sideon.gd ................. PASS
slice3_test_parry.gd ........................ PASS
slice3_test_spell_collision.gd .............. PASS
slice3_test_stage_hazard.gd .................. PASS
slice3_test_versus.gd ....................... PASS
slice4_test_spells.gd ....................... PASS
slice5_test_classes.gd ...................... PASS
slice_test_boss.gd .......................... PASS
slice_test_class_q.gd ....................... PASS
slice_test_climb.gd ......................... PASS
slice_test_coop.gd .......................... PASS
slice_test_coop_effects.gd .................. PASS
slice_test_debris.gd ........................ PASS
slice_test_floor.gd ......................... PASS
slice_test_gear.gd .......................... PASS (20 pieces)
slice_test_ground_crater.gd ................. PASS
slice_test_loadout.gd ....................... PASS
slice_test_movement.gd ...................... PASS   <- new, this task
slice_test_rig.gd ........................... PASS
slice_test_sandbox.gd ....................... PASS
slice_test_status.gd ........................ PASS
slice_test_summon.gd ........................ PASS
slice_test_touch.gd ......................... PASS
OVERALL: 0 failures
```

Also ran `godot --headless --path godot-project --import` -- clean, zero
errors (confirms `TuningConfig` global class + the new script edits parse
fine, per the repo's recurring `class_name` cache-registration discipline).

### Existing suites I had to update

**None.** `slice3_test_enemy_sideon.gd` also references `GRAVITY`/`MAX_FALL`,
but those are `Enemy.gd`'s own separate side-on-physics consts (a different
script, unrelated to Hero's movement consts) -- confirmed by reading the
file; no change needed there. No other suite referenced Hero's old
apex/gravity/jump/air-accel constants or values, so nothing needed
updating.

## Files changed

- `godot-project/scripts/combat/TuningConfig.gd` -- 5 new `@export` knobs.
- `godot-project/scripts/combat/Hero.gd` -- 5 const reads in
  `_physics_process` (lines 559, 560, 570, 595, 598) rewired through
  `_tune()`.
- `godot-project/tools/slice_test_movement.gd` -- new headless test (+ its
  auto-generated `.uid` sidecar).

## Self-review

- Confirmed I did NOT touch rig state selection, damage/knockback code, or
  any co-op-gated path -- grepped the diff, it's exactly the five read
  sites plus the five new knob declarations.
- Confirmed SP behavior: these consts apply unconditionally to every hero
  (no `is_multiplayer_authority()` branching around them), so there's no
  co-op-gated path being touched; the co-op-gate check at `Hero.gd:416`
  (`if _net != null and _net.is_active() and not is_multiplayer_authority()`)
  returns early via `_remote_visual()` before any of the five edited lines
  run for remote-controlled heroes -- unaffected.
- Verified the new defaults produce the intended feel numerically: apex
  time drops from ~0.387s (old) to ~0.285s (new) -- a ~26% snappier,
  more "committed" hop -- and air accel drops from 1450 to 750 (~48%
  reduction), meaningfully cutting mid-air free-steer, matching the
  brief's stated intent.
- Did not touch `data/tuning.tres` -- verified its existing overrides don't
  collide with the five new field names, so the new code defaults take
  effect immediately without needing a resource-file edit.

## Concerns

- The two "left untouched" sites (`:484` ragdoll-flop, `:2013` downed-slump)
  still use the OLD hardcoded `GRAVITY_FALL`/`MAX_FALL` consts (2100/1000).
  This is a deliberate scope decision (see above), not an oversight -- but
  it means those two states will now feel inconsistent with the new
  weightier main-movement fall speed if the maker compares them side by
  side. Flagging for a possible fast-follow if that inconsistency reads
  badly in playtest.
- `AIR_ACCEL` is genuinely one const doing double duty (accel toward input
  AND friction-to-zero) both before and after this change -- I preserved
  that exactly rather than splitting it, since the brief didn't ask for a
  behavioral split, only a live-knob rewire.
