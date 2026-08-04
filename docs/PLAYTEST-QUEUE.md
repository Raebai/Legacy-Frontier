# LIVE PLAYTEST QUEUE — 2026-08-04 (wave 2)

The maker is playing and calling things out faster than they can be built. Verbatim
intent preserved. **Nothing here is a design question — it is all "make it so".**

---

## ✅ DONE THIS ROUND

- **THE LEGS.** Root cause found and MEASURED: a body's collider and its rig
  disagreed about the floor (an 18 px box under a 31 px rig), so every figure drew
  its feet 6.5 px underground and folded 41% of the leg into the knees. Every
  previous fix missed it because the leg harness has no body under the rig.
  `tools/probe_town_feet.gd` is the new instrument; SINK is 0.00 now.
- **The lag when you shoot.** Hit-stop: `Engine.time_scale` → 0.05 for ~50 ms on
  every hit AND on every miss that touched a town wall. Scoped off in the lobby.
- **Big-spell SFX.** Tempest's cue was 20.7 s against a 0.48 s spell. Capped at a
  derived 0.9 s.
- **The dummies** were buried in the floor, and stood still by having physics
  switched OFF — which also took away gravity, knockback, flinch and ragdoll. They
  run the player's physics now via a controller that presses nothing.
- **The townsfolk** were a StaticBody2D teleported along x with a faked velocity.
  They are a CharacterBody2D with gravity and `move_and_slide` now — same three
  lines the player uses.
- **No dash is flattened.** The Cryomancer can dash upward; the sideways skid is
  gone. Blink follows the movement stick, for every class.
- **You can crawl** while holding down + a direction.
- **Pads and door** answer again (the town body is a Hero on a different collision
  layer than the rings were watching), you WALK INTO the tower, the tower is much
  taller and further right, the sign is mid-room and fits its own text, the hotbar
  is in the hub, camera pulled back twice, title taglines gone, class statue gone.

---

## ▶ OPEN — dispatched, in flight

1. **THE BAR IS SIX THINGS: 4 spells + deflect + basic attack.** Remove the
   spacebar/dash slot, the Q and T class abilities ("consecrate and the one next to
   it"), and the R blink from the bar. Spells on the right. Blink stays a SPELL only
   for the electric/fast classes.
2. **Wave 1 spawns two enemies but clears after one is killed.** A miscount.
3. **The boss gets stuck in the floor and cannot move.**
4. **Other opponents must cast spells**, and mobs want telling apart by hats.
5. **No spell pickups in the tower at all** (the Blizzard and anything else found
   mid-climb). **Healing harder to find.**
6. **After the boss dies, the way out is a PAD on the ground in the middle** with a
   beam of light, like the hub's — not a button.

## ▶ OPEN — not started, needs its own pass

7. **The map should be larger and more interactive.**
8. **More bosses and mini-bosses**, custom opponents.
9. **The ragdoll on hold-down** still wants judging now that the legs are correct.
10. **Inventory/menu lag** — the maker suspects blocks falling off props when a
    spell hits them near the pads. Hit-stop is ruled out in the lobby now; if it
    still hitches it is the debris/prop path.

---

# LIVE PLAYTEST QUEUE — 2026-08-04

The maker is playing and calling things out faster than they can be built. This is
the list, verbatim intent preserved. **Nothing here is a design question — it is
all "make it so".**

**Everything on the original list is now BUILT. None of it has been played.**
The open section at the bottom is what is left, and it is all "needs the maker".

---

## ✅ DONE — the room (`17e61f1`)

- **1. A SIGN in the background.** A two-armed signpost, in the world, between the
  last pad and the campfire. Its first position was measured *behind* the tower
  door and moved — the door draws wider than its origin.
- **2. Stations are TELEPORT PADS.** One flat disc, one colour, one glyph, a column
  of light that fires as the screen opens and lowers you back as it closes. The
  collision shape is gone: a pad is floor you stand on. `ClassAltar.gd` was absorbed
  into it (its gold statue survives, standing on the class pad).
- **3. Townsfolk: 4 → 2, and they HOP.** The two kept are the ones a pad cannot
  replace — the Warden (mechanics that are invisible until they kill you) and the
  Doorkeeper (reads your climb back to you).
- **4. Campfire music.** Already shipped in the previous batch.
- **5. More interactive.** The pads, the beams, the hopping, and the dummy yard.
- **NEW, mid-playtest: "make the spacing better and in a certain location".** One
  evenly spaced row, 100 px apart, derived from one constant — with a test that
  fails if any two pads come closer than the proximity ring (the lectern and the
  Archivist used to sit 58 px apart, so two hints fought for the same corner).
- **NEW, mid-playtest: "you should be able to cast spells in the lobby instead of a
  training ground — just standing immortal test dummies on one side".** The body
  you drive in the town is a **Hero** now, so every spell works in the room. Three
  straw 9999-HP dummies at the far end. The sparring pad is deleted.

## ✅ DONE — the sparring room, spell names, combat (`243c03d`)

6, 7, 11, 12, 13, 14, 15, 16, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 31 — the
eleven-fix batch. See that commit for the four bugs and why they hid.

## ✅ DONE — the ability bar (already built, verified this session)

8, 9, 10 — the bar reads in two clusters with a gap, spell slots draw as sockets
with the spell's own colour ringing them, and the row is a strength ramp derived
per frame from `SpellTier.of`, so the ult is always the far-right button.

## ✅ DONE — four spell slots (`bb6842b`)

- **30. FOUR SPELL SLOTS.** `SpellTier.SLOT_COUNT` 3 → 4. It found five borrowed
  spells: at three carried of five authored, a spell two classes shared could sit in
  both reserves unseen; at four it is on both hotbars. Every one is now that class's
  own. Two spells paid a timing to change shelf; no damage number moved.

## ✅ DONE — the screens (`4796987`)

- **17. The Archivist is an ACTUAL TREE.** Trunk, five boughs, a node per shelf,
  distance = cost. Buying thickens and extends the bough and opens buds at the tip.
- **18. Class select is far simpler.** Nine names in their own colours, three
  across. The fantasy line, the kit sentence and the "how to tap a button" hint
  are gone.
- **19. The standing rule** was applied to every screen touched, not swept
  globally: the town's thirteen-word HUD line is deleted (the signpost says it),
  the Archivist has one line of prose, class select has none.

---

## ▶ STILL OPEN — and all of it needs the maker, not an agent

1. **PLAY IT.** Four commits, none of it touched by hands. Start at F5.
2. **DIFFICULTY IS STILL FOUR LEVERS IN ONE DIRECTION AND NOBODY HAS FELT IT** —
   hero HP x1.4, enemy damage −25%/−40%, enemy speed −15%, floor 1 down 36% bodies,
   plus health packs. It may be trivial now. `TuningConfig.hero_vitality_mult` is a
   live F1 dial shipped NEUTRAL at 1.0.
3. **The audio has still never been heard**, and the music licence provenance is
   still the only thing blocking anything public.
4. **The fourth spell slot has a cost that wants a verdict:** you hold more, so you
   find less. The floor pickup pool went 14 → 9 and the class-select pick went from
   six hands per class to four. Both are pinned by assertions so they cannot shrink
   further by accident, but whether the trade feels right is a play question.
5. **Nothing has ever touched a touchscreen.** The touch arc grew to four buttons on
   geometry alone (`R >= 60 / (cos 60 − cos 30) = 164`, so radius 126 → 165).
