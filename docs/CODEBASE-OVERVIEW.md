# The codebase, measured — and what "clean it up" actually means

> Maker: *"this game shouldnt be so complicated and messy its actually really simple
> like its that stick figure with that phycsics logic and a ton of spells some of
> which interact."*

That description is right, and the numbers say the code stopped matching it a while
ago. This is the measurement, then the plan. **Nothing structural has been done yet**
beyond the one free deletion at the bottom — the rest needs your steer on order,
because a blind sweep through 108k lines of live game code is how a working game
stops working.

## What is actually here

| | files | lines |
|---|---|---|
| **Everything** | 567 | **191,659** |
| — code | | 108,352 (57%) |
| — comments | | 63,813 (**33%**) |
| — blank | | 19,494 (10%) |

| where it lives | lines | |
|---|---|---|
| `tools/` | 84,487 | **44% of the repo is tooling, not game** |
| `scripts/combat/` | 89,232 | the game |
| everything else | ~18,000 | ui, tower, net, spike |

Inside `tools/`: **172 test suites (57,941 lines)**, 64 capture tools (8,751), 48
throwaway probes (6,261), 59 other (11,092).

## The four things that make it feel messy

**1. `Hero.gd` is 7,159 lines and 205 functions.** It contains a 434-line
`_physics_process`, a 237-line `_ready`, and a 220-line `exit_grav_field`. Half of it
(3,578 lines) is comment. This one file is movement, dash, jump, melee, casting,
status effects, gravity fields, ghost/revive, net authority, bot body-state
publishing and the class table — all in one scope. It is the single biggest reason a
change anywhere feels risky.

**2. 42 spell files averaging ~738 lines each (31,008 lines).** Your mental model —
"a ton of spells, some of which interact" — is a *data table* plus a handful of
delivery shapes plus an interaction matrix. The code is 42 bespoke scripts that each
re-implement their own targeting, their own drawing, their own knockback and their
own cleanup. `SpellTargets`, `SpellGeometry` and `SpellWorld` were created to end
exactly that duplication and only partly landed — which is precisely how heroes ended
up with no hitbox at all while enemies had one.

**3. Comments are a third of every file.** They are genuinely load-bearing — four of
today's five bugs were found by reading them — but they are written as *history*
("this used to be X, it was wrong because Y, measured at Z"). That belongs in commits
and docs; what belongs inline is the ⚠ trap and the number.

**4. 44% of the repo is tooling.** The 172 suites are the safety net and have earned
their keep. But 48 files describe *themselves* as throwaway.

## The plan, in the order I would do it

| # | move | lines touched | risk | why this order |
|---|---|---|---|---|
| 0 | **delete self-declared throwaway tools** | −4,539 | none | ✅ **DONE**, 173/173 still green |
| 1 | split `Hero.gd` into movement / combat / casting / net, behind the same public API | ~7,000 | low-med | every later change gets cheaper; API unchanged so tests hold |
| 2 | collapse the 42 spell scripts onto the existing `SpellTargets`/`SpellGeometry`/`SpellWorld` seams | ~31,000 | med | this is where "spells that interact" becomes a table instead of 42 files |
| 3 | make spells data-driven: one `SpellDef` row + a delivery shape, bespoke script only when genuinely bespoke | | med-high | the end state your description implies |
| 4 | move historical comment narrative into `docs/`, keep ⚠ traps + numbers inline | −20,000ish | low | do LAST — those comments are the map while steps 1–3 happen |

**Step 1 is the one I would start with** and it is mostly mechanical. Step 4 is
tempting to do first because it deletes the most lines fastest; that would be a
mistake, because it removes the notes that make steps 1–3 safe.

## Two rules this repo has already paid for

- **The safety net is the 173 suites.** Every step above runs them before and after.
  A refactor that "obviously cannot change behaviour" is exactly the one that does —
  this project has a commit where 166/166 was green over a mode that crashed on every
  bout for a week.
- **Deleting a duplicate is only safe once the survivors agree.** `Enemy` and `Hero`
  now both answer `body_distance`, and `slice_test_hit_silhouette` fails if they ever
  disagree. Do that pinning FIRST, then delete — not the other way round.

## Step 0, done

38 files, 4,539 lines, each of which said "throwaway" / "agent-owned" / "safe to
delete" in its own header and was referenced by nothing. Ten more say the same thing
but are named in live comments in `Arena.gd`, `Spell.gd`, `Hero.gd`, `SpellLibrary.gd`
and four suites; those need the comment updated in the same commit and were left.
