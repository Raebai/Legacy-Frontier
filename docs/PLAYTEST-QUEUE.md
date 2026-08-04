# LIVE PLAYTEST QUEUE — 2026-08-04

The maker is playing and calling things out faster than they can be built. This is
the list, verbatim intent preserved. **Nothing here is a design question — it is
all "make it so".**

Two things are DONE and pushed; everything else is open.

---

## ✅ DONE (pushed, `931aa78`)

- **The bent legs / "everyone is walking on their limbs".** Root cause: the town
  used the same `CharacterRig` as combat but never fed it `set_grounded()`,
  `set_body_velocity()` or `set_air_phase()`. `set_grounded` **defaults to true**,
  so an un-fed rig thinks it is on the floor even at the top of a jump — feet
  pinned to the ground plane, hips rising, IK folding a leg that cannot reach.
- **Title screen:** "Nameless · Tier 0" gone (hidden outside a run AND at tier 0),
  the stale "new here?" line gone, the chalk tower replaced by `_Sigil` — a
  summoning circle that scribes itself and then pours elements forever — and the
  buttons now glow, lift on hover and punch on press.

---

## ▶ OPEN — THE ANTECHAMBER

1. **A SIGN in the background**, part of the map, telling you where to go.
2. **Stations should be DOORS or TELEPORT PADS**, not scattered props. Maker's
   preferred shape: *"a teleportation pad — when you stand on it and press
   teleport a beam of light comes up and you teleport, and then you teleport
   down"*. Applies to ALL of them (sparring ring included). Possibly all on one
   side so they are easier to reach.
3. **Townsfolk need PERSONALITY** — have them jump around. **Fewer of them.**
4. **CAMPFIRE MUSIC, adventurer vibe.** Use one of the six tracks already in
   `assets/audio/music/` — do not source a new one.
5. **Make the whole place far more interactive and fun.**

## ▶ OPEN — THE SPARRING RING / TRAINING ROOM

6. **The instructions are too long.** *"this game should be super simple"*. Cut hard.
7. **A weird SFX plays when a box is destroyed. Remove it — and never use that
   sound effect again anywhere.**
8. **Ability bar layout:** parry and blink on the LEFT, then a small gap, then the
   four spell slots.
9. **Spell slots must LOOK like slots** — a coloured border or equivalent.
10. **Order the slots by STRENGTH, heavy on the far right.**

## ▶ OPEN — SPELL NAMES

11. **"Ordinary" is an awful name.** Rename it.
12. **Across ALL classes: drop "step" and "cast" from spell names.**

## ▶ OPEN — COMBAT BEHAVIOUR

13. **Double-space does a backwards teleport — remove it.** *"it's just a repeat of
    blink"*. This is the Arcanist's RECALL return-leg (`_recall_timer` in
    `Hero.gd`, `move_verb = "recall"`).
14. **Mirror Image must cast what the player casts**, and **attack nearby mobs**
    while it is out.
15. **Projectiles must travel until they HIT something.** Meteors, arcane storm,
    *"all of them"* — they currently despawn in mid-air. They should reach the
    floor if nothing stops them, and have longer range.

## ▶ OPEN — UI, GENERALLY

16. **Settings: remove the HEAL button.** Replace with real settings — exit to hub,
    brightness, controls.
17. **The Archivist must be an ACTUAL TREE** — click a node to spend a point, and
    the branches visibly grow as you invest. Not a list of rows.
18. **Class select must be far simpler.**
19. **Standing note: this game has too much text and too many random UI pieces.**
    Every screen should be cut, not added to. Treat this as a rule, not a ticket.

---

## THE RULE BEHIND MOST OF THIS

*"this game should be super simple I want it to be as such"* — said about the
sparring instructions, but it is clearly the general bar. When in doubt on any of
the above: remove the words, keep the picture.

---

## ▶ OPEN — ADDED MID-PLAYTEST (second wave)

20. **Mob death SFX is a "weird scrunching noise".** All the combat cues want to be
    **more subtle and better** — this one fires every couple of seconds in a wave.
21. **GAME OVER screen:** the text is too big, **the bots keep fighting behind it**,
    and there is **no return-to-menu button**.
22. **FLOOR 1 OF THE TOWER LOOKS BAD AND READS BADLY.** Verbatim: *"really bad it
    needs to be larger, clearer to the user where it is like there are weird blinds
    covering the front of the map that should be background and other random things
    that all need to be optimised"*. Something is drawing in FRONT of the fight that
    belongs behind it.
23. **Floor 1 difficulty is a little high.**
24. **There need to be BREAKS between stages/waves.**
25. **Make the arena LARGER and CLEARER to fight in.**
26. **THE GAME IS TOO HARD.** Four separate levers, all in flight together:
    - **Hero HP is too low** — raise the `CLASS_CONFIG` table, keeping the 1.86x
      spread between classes intact (scale it, do not compress it).
    - **HP is not readable** — the maker cannot tell how hurt they are.
    - **Health packs** — there should be pickups that heal.
    - **Enemies hit too hard and there are too many of them**, on every floor, not
      just floor 1.
    ⚠ These four combine MULTIPLICATIVELY. Tougher player + softer enemies + fewer
    enemies + heals is very easy to overshoot into trivial. Whoever tunes this last
    should say so out loud rather than assume the sum is right.
27. **The map is too small** — said twice. Overrides Arena.gd's "ONE SCREEN"
    framing comment, which was a real decision but is now the complaint.
28. **Opponents move too fast.**
29. **⚠ OPPONENTS SPAWN "RANDOMLY IN THE AIR".** They should arrive from a small
    number of legible PLACES — doorways, edges, the ground plane. The current
    spawn is a RECT sampled anywhere inside, and a rect that includes air is
    exactly the bug. The spawn TELL should land on the place, so the player learns
    where things come from.
30. **FOUR SPELL SLOTS, not three.** Maker: "lets make it 4 spell slots as there
    are 4 spells currently going on". `SpellTier.SLOT_COUNT` is 3 and
    `SpellLibrary.SLOT_ROLES` gives each class 3 of its 5 roles. Going to 4 means
    each class carries 4 of 5, needs a `spell_4` input action, a 4th entry in
    `Hero.SPELL_KEYS`, and a 4th role picked per class in SLOT_ROLES.
    ⚠ `SpellTier`'s own docstring ALREADY says "four spell slots plus a dedicated
    ULT slot" — the constant is what drifted from the design, not the other way up.
31. **Ice wizard:** primary cast has no visible projectile; kit feels weak and
    unspectacular next to the others.
