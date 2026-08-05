# STICK CUSTOMISATION — designed, NOT BUILT

From the maker's reference (a Rai Lukasha stick animation, 109.7K likes): a yellow
plain figure, a **navy-clothed figure with white hair and a sheathed katana**, and a
**pink figure in sunglasses** — with the dialogue **in the speaking character's own
colour**, in a handwritten font.

Status: **direction captured, nothing implemented.** Written because the session that
found it was nearly out of context and a half-built customisation system is worse
than none.

---

## 1 · THE PLUMBING ALREADY EXISTS — DO NOT REBUILD IT

`CharacterRig.class_preset(name)` already swaps three slots via
`set_equipment(slot, id)`:

    head    "" | hat | hood | crown
    body    "" | robe
    weapon  "" | sword | staff | staff_holy | staff_ice | staff_storm | orb |
                hammer | scythe

and `EQUIP_TEX` overlays PixelLab-generated pixel gear per class
([[project_v2_pixellab_gear]]). **STICKS STAY STICKS** is a locked ruling: PixelLab
only CUSTOMISES them, it never replaces the procedural rig.

So the gap is the **library**, not the system. A new item is a PNG plus a registry
row.

## 2 · WHAT THE REFERENCE HAS THAT WE DO NOT

| thing | today | cost |
|---|---|---|
| **hair** | no slot at all | a 4th `set_equipment` slot; the rig has a head circle to hang it off |
| **clothing that is not a robe** | `body` is ""/robe | more `body` entries — jacket, coat, gi |
| **accessories** (the sunglasses) | none | a 5th slot, or fold into `head` |
| **a SHEATHED weapon** | weapons draw in-hand only | the saya on the hip is most of the katana read, and it is what makes an iai an iai |
| **dialogue in the speaker's colour** | `SpeechBubble.say(text, fade, x_offset)` — no colour | see §3 |

## 3 · THE CHEAPEST REAL WIN: COLOUR THE BARK

The reference's text is the character's own colour, and that one choice is doing a
lot: with no portraits and no names, colour is the ONLY thing telling you who spoke.
This game has the same constraint — nine identical silhouettes told apart by tint.

**⚠ IT IS NOT A TWO-LINER, WHICH IS WHY IT IS NOT DONE.** `SpeechBubble.say()` has no
colour parameter and the same bubble serves the hub NPCs, whose voices were tuned
against the current look. Threading a colour through means touching `Bark.say`,
`SpeechBubble.say`, its shrink-to-fit measuring pass (which re-measures on the
RichTextLabel and would need the BBCode colour run to not change the metrics), and
the thinking-dots animation that already writes its own `[color=#888]` runs.

Do it as its own change, with a rendered before/after.

## 4 · A LIBRARY — WHAT THE SEARCH FOUND

The industry pattern is **paper-doll layering**: separate sheets for hair / clothes /
tools with IDENTICAL layouts so they swap at runtime. That is exactly what
`EQUIP_TEX` already is, so any of these drop in as source material rather than as a
new system.

- [Stickman Fighter Spine 2D sprites](https://overcrafted.itch.io/stickman-fighter-spine-2d-game-character-sprites) — paid (~$7), Spine-based, explicitly built for swapping the weapon out
- [Free Stick Swordman 2D sprite](https://www.artstation.com/marketplace/p/V0Ov/free-stick-swordman-2d-character-sprite) — free, 10 animations, a stick swordsman specifically
- [Animated Stick Figure Character 2D](https://opengameart.org/content/animated-stick-figure-character-2d-free-cc0) — **CC0**, the only no-strings one
- [itch.io character-customization tag](https://itch.io/game-assets/tag-character-customization) — the paper-doll packs, for layout reference

⚠ **THE LICENCE IS THE FIRST QUESTION, NOT THE LOOK.** Only the OpenGameArt one is
CC0. Anything else needs its terms read before a single pixel enters the repo.

⚠ **AND SPRITE PACKS FIGHT THE RIG.** These are pre-drawn frame sequences; this game
draws its figures procedurally, which is what lets a rig ragdoll, flop, and take a
per-limb status effect. Buying an animated stickman does not give this project
animation — it gives it a reference to draw gear against. The honest use is
**texture source for the equipment slots**, not a replacement body.

## 5 · WHY IT MATTERS BEYOND LOOKS

[[project_v2_class_identity_mandate]]: "every class needs a unique signature spell AND
a unique movement verb — NO recolours." Nine classes currently separate by TINT and
by preset. Hair, a coat and a sheathed blade would make a Swordsaint read as a
swordsaint standing still, before it casts anything — which is the same complaint the
socket glyphs answered on the hotbar.
