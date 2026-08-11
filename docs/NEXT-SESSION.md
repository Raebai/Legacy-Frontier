# RESUME HERE — 2026-08-11, THE TESTS WERE LYING

**ASHPIRE.** Branch `bot-fight-quality`, **167/167 green** — and that number now means
something it did not mean yesterday.

## ▶ WHAT HAPPENED

The maker opened the game, pressed **Watch Bots**, and it broke. It had been broken on
every bout of every mode that uses the duel stage — Watch Bots, the PvP duel, free play —
since commit `56ac72e`, roughly a week. **166/166 was green the whole time**, and the
previous edition of this file opened by recommending Watch Bots as the fastest way to
judge the build.

```
SCRIPT ERROR: Invalid assignment of property or key 'terraces' with value of
type 'Array' on a base object of type 'Node2D (ArenaTerrain)'.
    at: VersusArena._build_terrain (VersusArena.gd:862)
```

`ArenaTerrain.terraces` is `Array[Dictionary]`. It used to be handed the typed const
`TERRACES` and matched. The three-stage-variant work made the table
`STAGE_TERRACES: Array[Array]` — and GDScript cannot express `Array[Array[Dictionary]]`,
so the inner arrays are UNTYPED and a plain `=` throws. The fix is `terraces.assign(rows)`.

## ⚠ WHY IT SURVIVED A WEEK OF GREEN — THREE HIDING PLACES, ONE MISTAKE

1. **`slice_test_stage_variants` checked the authored table.** Eight tests, all reading
   `get_script_constant_map()`. The table was always fine. It never looked at the node.
2. **`slice_test_sandbox` DID boot the packed scene, DID hit the error, and passed.**
   A GDScript runtime error is **not fatal** — a failed property set kills only the
   innermost function, so `_ready` walked straight on, built the ruins and spawned both
   fighters. The only casualty was the rock, and nothing asserted on the rock.
3. **`run_all_tests.py` only read each suite's own summary line.** The engine printed the
   fault on stderr on every single run and nobody was listening.

**The rule this cost us:** for anything the player looks at, assert the value that
ARRIVED AT THE NODE. A constant is not evidence that it was applied.

## ▶ THE GATE, AND THE FOUR SUITES IT CAUGHT

`run_all_tests.py` now **fails any suite that emits a runtime `SCRIPT ERROR`**, whatever
the suite says about itself. Scoped to `SCRIPT ERROR` and not the broader `ERROR:`,
which covers benign engine chatter (the MCP runtime failing to bind 7777 when the editor
holds it). A suite that provokes errors deliberately opts out with an
`ALLOWS_SCRIPT_ERRORS` marker in its source — that marker is a claim that the error is
the point of the test, not a way to quiet a noisy suite.

It immediately caught four more suites passing vacuously. All four are fixed:

| suite | what was wrong |
|---|---|
| `slice_test_spell_warm` | **The suite itself failed to compile** and still printed `all PASS`. It named `SpellCaster` / `MeteorSigil` / `ReactionOutcomes` as compile-time globals and ran from `_initialize()`; `MeteorSigil` says `Sfx.play(...)` and autoload globals do not exist before the main loop. |
| `slice_test_health_pickup` | Named `FloorBuilder` by `class_name` → its `preload` of the crate scene → `DestructibleProp` → `Sfx`. Its own header already stated the rule it was breaking. |
| `slice_test_runend` | Ran from `_init`, before autoloads. The one test that instantiates `Net.gd` (whose chain reaches nine spectacle scripts) now runs after the first frame. |
| `slice_test_selfdamage` | `FakeNet` had drifted from `Net.broadcast_hero_action`, so every cast's broadcast threw into the void. The stub now matches the real interface, records what it is handed, and a new assertion pins that the path is live. |

**`spell_warm` also lost its hand-written list of 21 dispatch-arm constants** — that list
was the rot the suite exists to catch and could not see a newly-added arm. It now reads
`SpellCaster`'s constant map. Doing that caught a live detail: `NOVA_PATH` is a `.tscn`
while the other twenty are `.gd`.

**New suite: `tools/slice_test_arena_builds.gd`** — boots all three stage variants and
asserts the `ArenaTerrain` node exists *and carries its rows*. Confirmed failing before
the fix, passing after.

## ▶ THE CRATES ARE GONE FROM THE FIGHT FLOOR

Maker, watching a bot fight: *"they start behind the crate then break the crate and walk
into them"* → *"remove the crates or make them start on the platforms above"*.

`STAGE_COVER` is now **empty** — emptied, not deleted. The builder, the keep-out,
`cover_x_clear_of` and its tests all still work; re-authoring a row brings cover back.

**The keep-out was never the problem.** `cover_x_clear_of` guarantees
`block_w * 0.5 + SPAWN_FOOTPRINT_HALF` = **54 px**, which is exactly "not overlapping"
and nowhere near "out of the way". Spawns at 440 / 1000, blocks at 470 / 1180 — so every
bout opened with both fighters chewing through a crate before they could reach each other.

Moving the fighters onto the terraces was the other option and was declined as the
riskier one: `BotMatch.SPAWN_Y`, the camera clamps, `PROBE_TERRAIN_X0/X1` and ~25 capture
tools are all derived from the main floor row, which `slice_test_stage_variants` pins
precisely because moving it breaks them quietly.

`slice_test_stage_variants.cover_never_gates_the_opening` now fails the build if cover is
re-authored inside the spawn corridor. ⚠ It is a **guard, not a measurement** — with the
table empty it loops zero times today.

## ▶ WHAT TO PLAY

**F5 → Watch Bots.** Three things have never been seen in a real bout:

1. **The terrain draws at all** — rock, soil crust, strata lines, cracks. `ArenaTerrain._draw`
   has been dead code for a week.
2. **The opening is clean** — two fighters, nothing between them.
3. Everything in the previous handoff's list, which was written but never played:
   killing blows that launch, ult name banners, the deflect plane, three stage shapes.

## ⚠ LAUNCHING THE GAME REWRITES TRACKED FILES

Opening the game dropped three keys from `project.godot` (`physics_ticks_per_second`,
both `rendering_method`s) and reformatted `Main.tscn` (losing its entire comment block)
and `ashpire_theme.tres`. It fired on the first launch and not the second. **Check
`git status` after any launch**, not just after `--headless --import`.

## ▶ THE BALANCE NUMBERS — UNCHANGED, AND STILL NOT ACTIONABLE

Two round robins, the second after the Cleric / Warlock / Shadowblade retunes.

| class | 288 bouts | 216 bouts | delta | sigma |
|---|---|---|---|---|
| CLERIC | 73% | 67% | -7pp | -0.8 |
| SWORDSAINT | 53% | 65% | +11pp | 1.2 |
| WARLOCK | **77%** | 58% | **-18pp** | **-2.1** |
| BRAWLER | 47% | 58% | +11pp | 1.2 |
| STORMCALLER | 66% | 50% | -16pp | -1.7 |
| ARCANIST | 39% | 48% | +9pp | 0.9 |
| SHADOWBLADE | **23%** | 38% | +14pp | 1.6 |
| JUGGERNAUT | 36% | 38% | +2pp | 0.2 |
| CRYOMANCER | 36% | 29% | -7pp | -0.8 |

**Only the Warlock's -18pp clears 2 sigma.** The Stormcaller dropped 16pp with nothing
about it changed, which is the clearest warning in the table about how noisy N=48 is.
The robust signal is the aggregate: the spread narrowed from 54 points to 38.
**Do not retune anything on this table.** For per-class certainty:
```
godot --headless --path godot-project --script tools/botmatch_sim.gd --   --roundrobin=1 --repeat=8 --round=22 --hp=190 --wall=70      # ~50 min
```

⚠ Every one of these bouts was fought on a stage with **no terrain drawn**. That is a
visual fault, not a physics one — the terrace COLLIDERS are built separately in
`_make_terrace` and were always present — but the crates were real and are now gone, so
the next sweep is not comparable to these two.

## ▶ STILL OPEN

* **The CRYOMANCER at 29%** is a -0.8 sigma move. Noise. Do not chase without a bigger sample.
* **`aegis_ward`'s own duty-cycle rule is stricter than the one enforced** (50% vs 100%).
  Tightening it would retune half the catalogue on an unmeasured hunch.
* **Cover no longer exists on the duel stage.** If the fights want it back, put it on the
  flanks or the upper terraces — outside the 440..1000 corridor.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 6      # 167 suites, ~135s
```
After any launch OR `--headless --import`, CHECK `project.godot` still has four keys:
`theme/custom`, `physics_ticks_per_second`, and both `rendering_method`s.
