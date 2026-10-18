# The tutorial: flying bodies, a card on top of the label, and lore you walked past

**Date:** 2026-10-18 · **Lane:** Feel · **Where:** PC · **Not a board row** — maker-reported
while playing.

Maker, playing the tutorial: *"during the tutorial the bots are flying and the text is weird
and like when I click a button its not interactive or slow enough it feels rushed and
cofusing"*.

Three separate faults. All three were visible in a single `dojo_capture` frame.

| File | What it is |
|---|---|
| `dojo_after.png` | The dojo now: everyone standing, card clear of the label. |
| `probe_feet_after.txt` | `probe_dojo_feet.gd` output after the fix — every GAP 0.00. |

---

## 1. The flying bodies — two bugs stacked, either one invisible alone

`tools/probe_dojo_feet.gd` (new), after 40 physics frames:

```
figure                    body   box_foot   rig_foot     ground       GAP  falling
Hero (hero)              771.00     780.00     779.97     780.00      0.03      0.0
@CharacterBody2D@563     716.00     725.00     725.00     780.00     55.00      0.0
@CharacterBody2D@565     716.00     725.00     725.00     780.00     55.00      0.0
@CharacterBody2D@567     626.00     635.00     635.00     696.00     61.00      0.0
@CharacterBody2D@569     716.00     725.00     725.00     780.00     55.00      0.0
```

Four of five hung 55–61 px up with **y velocity 0.00 after 40 physics frames** — not
mid-fall, not falling at all.

**Fault A — the spawn y values were written as if the floor were ~60 px higher.**
`GROUND_TOP` is 780 and the ruin terrace is 696, but the dummies were placed at 716 and
626. The sensei was worse: he was placed at `player.global_position + Vector2(SENSEI_X, 0)`
— the right idea, *stand beside the student*, taken on the wrong frame. The hero is at
`FREE_SPAWN`'s y of 716 then and has not fallen yet, so the sensei copied a hero that was
still in the air.

**Fault B — `set_physics_process(false)`, which is deliberate and stays.** A dummy has no
controller, so `Hero._pressed` falls through to the real `Input` and every dummy would
mirror the player's own buttons. Physics off is what stops the shadow-boxing. It also
removes gravity, so nothing ever corrected Fault A.

Gravity is exactly what hid Fault A everywhere else: the hero spawns at the **same** wrong
y and simply falls, landing at 771 with its feet on 780. That is why one figure looked
right and four did not.

**Fix:** spawn points are now derived — `GROUND_TOP - BODY_FEET_OFFSET`, where the 9 px
offset is measured off a settled hero rather than guessed, and the terrace dummy uses the
terrace's own surface. The sensei takes his **x** from the student and his **y** from the
floor, via a new `VersusArena.ground_stand_y()`. Every GAP is now 0.00, terrace included.

**Guarded:** `tools/slice_test_dojo_feet.gd` (new, suite 220). It asserts what the player
*sees* — feet on floor — not that a constant equals a constant, because a constant check
would pass the moment someone edited the constant and would never cover the terrace case.

**Sabotage, seen both ways:** the suite was written first and went RED naming all four
bodies and their exact gaps. After the fix it went green. Then `RUIN_TERRACE_TOP` was
deliberately set to 780 (the mistake someone would actually make — assuming flat ground):
RED again, naming the terrace dummy at x=1420. Restored, green.

## 2. "The text is weird" — the card was drawn on top of the room label

The stage draws `THE DOJO — ARCANIST    Esc: settings, class, dummies` across the top-left.
The lesson card was anchored at `CARD_TOP = 14`, which put its panel *inside* that line —
the label's words rendering over the card's dark fill, two unrelated pieces of text sharing
the same pixels. `CARD_TOP` is now 34, which clears the label's baseline at the 640x360
base size. Compare `dojo_after.png` against the first frame in
`proof/2026-10-18-1.2-editor-loop/` if you want to see the collision.

## 3. "Rushed and confusing" — a movement key was skipping the story

The lore card accepted `talk` **or `jump` or `melee`**. `jump` is bound to **W and Up** —
the keys a player holds to walk, and the keys this very lesson is about to teach. So anyone
who touched a movement key during the eleven lore cards blew through the story they were
being told, while the card in front of them read *"Press E to continue"*.

`jump` is out of the accept set. `talk` (E, and the on-screen E pad) is what the card names;
`melee` (F) stays as the second key because it is not a movement key and cannot be hit by
accident while trying to walk — so no touch player is stranded by the change.

## ⚠ Still open, and deliberately not decided here

**"Not interactive" is only half-fixed.** A card press still has no *visible* response: the
press sets `TICK_HOLD = 0.45 s`, during which input is ignored and nothing on screen moves,
and then the card swaps. That dead beat reads as an unresponsive button. The systemic fix is
already a board row — **1.6d**, *"one shared Button scene: hover tilt, squash on press,
border ripple and warm chime on release"* — which is a **Cloud** row and unbuilt. Worth
doing before judging the tutorial's feel again.

**Eleven lore cards before you play is a design call, not a bug**, so it was left alone. The
"rushed" half had a mechanical cause and that is fixed; whether eleven cards is the right
number is the maker's.

**Not playtested.** All three fixes are verified by probe, suite and captured frame. Nobody
has played the tutorial since.
