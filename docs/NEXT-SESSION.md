# RESUME HERE — 2026-08-07 (i), THE WAVE-6 QUEUE IS EMPTY

**ASHPIRE.** Branch `bot-fight-quality`, **166/166 green**, tree clean, all pushed.

All ten wave-6 asks are actioned, and so are **sixteen more** the maker spoke while the
session ran. **NONE OF IT HAS BEEN PLAYED.** Every item below is headless-verified
only; the whole list is a WHAT-TO-PLAY list.

## ▶ THE FASTEST WAY TO JUDGE IT

**F5 → Watch Bots.** Nine of the changes land there and four are impossible to miss:

1. **Nobody starts inside a crate.** The left fighter was spawning two pixels inside
   the cover block. Cover moves now; the 560 px mirrored footing does not.
2. **The loser actually dies** — thrown by the killing blow, flies, lands ragdolled,
   and stays down. Two separate faults, both fixed (see below).
3. **The stage has three shapes**, rolled per bout. One of them removes the stage's
   handedness entirely.
4. **Ults say their own name across the screen.**

Then **fight a Cleric and a Warlock** — both were retuned, and both were measured.

## ▶ WHAT CHANGED, GROUPED

| | |
|---|---|
| **Deflect** | The guard is a PLANE. Square → still back at the sender; angled → skids off at twice the angle. A real beat too: a longer freeze (the caught spell visibly stops) and a spark cone down the exit so you can see where it went. Horizon Cut sweeps things aside as it travels. |
| **Death** | `Hero._die` healed to full outside a run, AND a flop taken in the 0.4 s before the fatal blow un-limped the corpse afterwards. Two faults, one symptom. Killing blows now launch. |
| **Swordsaint** | Background circle gone (it was the arcane cast gesture; suppressed for plain steel only). Curve is a tapered blade with three trailing ghosts. Connecting swings get a black `SILHOUETTE` frame + edge spray. |
| **Blood Pact** | 5→3 HP/s, 5→6 s, **and it buffs your sword now**. The gold aura could never survive its own duration. |
| **Gravity well** | The **caster** can no longer staircase out on dashes. First fix keyed on the wrong refcount — the maker caught it. |
| **Petrify** | Statues cannot act at all. The stone slab and its cracks are gone; the body itself freezes and frosts. |
| **Weapons** | `class_preset` already authored a scythe / hammer / ice staff and `equip_weapon` was stomping all five. Blades come to a real point. Three casters' staves have distinct heads. |
| **Colours** | Fighters wear their class colour, falling back to yellow-vs-blue when the two classes are not separable (Shadowblade and Warlock are literally the same violet). |
| **Reactions** | Six new spell-vs-spell meetings, incl. the busiest empty bucket in the game (a bolt flying into a beam did nothing). |
| **Bots** | They can see walls now — they had ZERO terrain awareness. Spell emissions cut 22%, measured. |
| **Shake** | The accessibility slider did nothing in any versus mode. It does now; duel shake dropped ~30% on that alone. |

## ⚠ THE THREE THINGS MOST LIKELY TO BE WRONG

1. **The deflect angle** is a feel change on top of a documented decision.
   `SpellDeflect.return_dir` → return `n` unconditionally and it is back to aim-direct.
2. **Blood Pact buffing melee is UNMEASURED.** The sweep predates it. Swordsaint was
   53% before.
3. **Four spell durations/cooldowns moved** (judgment, raise_thrall, mirror_image,
   petrify) and the sweep predates all four.

## ▶ THE NUMBERS — AND WHAT THEY DO AND DO NOT SUPPORT

Two round robins this session. The second was run AFTER the Cleric / Warlock /
Shadowblade retunes.

| class | 288 bouts (before) | 216 bouts (after) | delta | sigma |
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

**⚠ READ THE SIGMA COLUMN BEFORE ACTING ON ANY ROW.** At 48 bouts per class the
1-sigma error on a difference is about 9.5pp, so **only the Warlock's -18pp clears
2 sigma.** Everything else — including the Shadowblade's +14pp, which is the change I
was trying to make — is UNDER the bar. It moved in the intended direction; that is
encouraging, not proven.

The STORMCALLER dropped 16pp with nothing about it changed, which is the clearest
warning in the table about how noisy N=48 is.

**The robust signal is the aggregate, not any row: the spread narrowed from 54 points
(23-77) to 38 points (29-67).** That is what the four duty-cycle fixes and the
Shadowblade kit buff were for, and it is the claim worth making.

**Do not retune anything on this table.** If you want per-class certainty, run both
sides at `--repeat=8` or more:
```
godot --headless --path godot-project --script tools/botmatch_sim.gd --   --roundrobin=1 --repeat=8 --round=22 --hp=190 --wall=70      # ~50 min
```

⚠ The **Swordsaint at +11pp** is the row to watch: it is the class that got the Blood
Pact melee buff, and it is now second. 1.2 sigma, so no mechanism is being claimed —
but it is the first thing to re-price if a bigger sample confirms it.

## ⚠ TWO INSTRUMENTS WERE LYING, AND ONE OF MY OWN THEORIES WAS WRONG

* **`bot_cast_probe` had `const SLOTS = 3` against a 4-slot hand.** It never offered
  slot 3 — every kit's ULT — to the brain, never counted one, and printed "0 of 27 kit
  slots never asked for" over 9 classes × 3. Fixed; the brain asks for its ult as
  often as anything else.
* **`Tuning.cfg.shake_scale` was read by one camera of two.**
* **I then blamed the channel gate for the missing ults and was wrong.** Counted it
  with real bodies: **0 of 242 channelled casts refused.** The gate is innocent. The
  likeliest remaining explanation is that ults were not LEGIBLE as ults — which the
  new `CastName` banner now fixes. Play it and see.

## ▶ WHAT IS STILL OPEN

* **The Shadowblade at 23%** — the floor of the roster, unaddressed, and now the
  best-evidenced balance problem in the game.
* **The bot melee swing has no spacing dial** — 2.85/s for the Brawler and Swordsaint,
  45% of their actions. Deliberately left alone: the body gates real damage at
  `melee_cd`, so a brain-side floor above it cuts melee DPS on the two classes least
  able to take it. Wants the next sweep.
* **`aegis_ward`'s own duty-cycle rule is stricter than the one enforced** (50% vs the
  100% in `slice_test_spell_budget`). Tightening it would retune half the catalogue.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 6      # 166 suites, ~105s
```
After any `--headless --import`, CHECK `project.godot` still has four keys:
`theme/custom`, `physics_ticks_per_second`, and both `rendering_method`s.

## NEW SUITES THIS SESSION
`slice_test_duel_spawn`, `slice_test_deflect_angle`, `slice_test_spectated_death`,
`slice_test_bot_walls`, `slice_test_bot_rhythm`, `slice_test_new_reactions`,
`slice_test_stage_variants`, `slice_test_spell_budget`.
