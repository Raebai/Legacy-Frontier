# SOCKET GLYPHS — designed, rendered, NOT BUILT

Status: **design verified by render, code not applied.** The ability bar's spell slots
are rotating magic-circle rings now (shipped `fa5d4e3`), but a class whose spells share
an element still shows sockets of the same colour. This is the third axis.

---

## ⚠ THE FINDING THAT KILLS THE OBVIOUS IMPLEMENTATION

**Do NOT key the glyph on `SpellDef.Kind`.** It was built, rendered across all nine
classes, and **eight of nine had a duplicated glyph** — the Shadowblade drew *three
identical BLADE circles*, the Juggernaut *three identical ERUPTION circles*. The
Arcanist, the one class the maker complained about, was the only clean one.

Shipping that fixes the complaint on the reported class and makes eight worse, because
now the identical circles carry an identical figure too.

The cause is structural and is not a bug: `MagicCircle.Motif` is keyed **by
consequence**, deliberately ("two different wall spells SHOULD open the same figure").
That is right for a cast circle and exactly wrong for a hotbar, whose whole job is
telling four spells apart.

**Key on the SPECTACLE instead** — `SpellCaster.spectacle_path(sig)` →
`SpellSigil.MOTIF_BY_SCRIPT`, with a `Kind` table as fallback only. The fallback is
still required and must still cover all 22 kinds, because `spectacle_path` returns
`EnergyNova.**tscn**` for `NOVA` and the script table cannot key a scene — a
silent-`NONE` trap, and a `NONE` draws nothing, which looks exactly like the flat
socket this whole pass replaced.

---

## THE SHAPE OF THE WORK

1. **Extract `MagicCircle._draw_motif` (~147 lines, currently ~1219–1364) into a static**
   `draw_motif(ci, motif, R, col, w, phase, low, shade_alpha, count_work)`, with the
   instance method reduced to a delegate. Then the socket glyph and the world cast
   circle are literally one drawing and cannot drift — the same argument the codebase
   already makes for `SpellSigil` and `SpellDef.resolve_color`.
   - Everything the arms touch becomes a parameter: `_motif`→motif, `_phase`→phase
     (ORBIT's bodies, SPIRAL's winding), `_low`→low, and the sigil's own alpha for
     VOID's black fill (the one place it differs from the brightened colour).
     `_charge`/`_snap` stay in the caller, folded into `col.a` exactly as now.
   - ⚠ Needs a `count_work` flag. The `_work_*` counters are static and
     `tools/profile_magic_circle.gd` reads them; four HUD sockets drawing every frame
     would be counted as sigil work and the profile would silently inflate.
   - `_seg` and `_draw_star` become one-line delegates to `_seg_of` / `draw_star_on`
     so there is still exactly one body of each.
2. **`SpellSigil.MOTIF_BY_SCRIPT` needs 11 additions and 8 re-points.** The 11 are the
   HEX-forked class signatures, which have **no row today and therefore open a
   motif-less cast circle in the world too** — so that half is a strict fix in two
   places. ⚠ The 8 re-points **change existing world cast circles** and are a maker
   call: `RiftDagger`→LANCE (it is thrown), `RockPillar`→BARRIER, `ChainBolt`→SNARE,
   `ShadowRoot`→WARD, `HorizonArc`→PULSE, `StarConvergence`→ORBIT, `DrainTether`→VOID,
   `BlinkStrike`→SPIRAL.
3. **Stamp it** in `AbilityBar._stamp_spell_identity` beside `tier` and `accent`, and
   draw it in `_draw_socket` **unrotated** (LANCE means "that way", and a spinning
   arrow points everywhere) at `GLYPH_RADIUS = SOCKET_RADIUS * 1.16`, width 1.8.

---

## RENDER VERDICT (measured, at true phone pixels then 6× NEAREST)

**The Arcanist four read clearly** — arrow / triangle / beaded ring / three-chevron.
Four different silhouettes at a glance and at final size. `SUMMON` renders as a clean
triangle with an inner ring, **not** the unreadable `#` an earlier attempt reported.

**Two honest weaknesses:**
1. `PULSE` / `SPIRAL` / `SNARE` all read as "a swirl in a circle" at 46 px. Three
   classes carry two of that family. They are separable by colour or by the gold ult
   crown, but the glyph alone does not carry it. No cheap fix inside "one drawing" —
   widening the motif lane would change every cast circle in the game.
2. ULT sockets become busy: gold outer ring + element ring + figure in 46 px. `ORBIT`
   on an ult is the worst case. Worth the maker's eye before it ships.

**Cost:** +4 to +20 draw calls and ≤~170 segments per frame for four sockets — about
half a single magic circle. `PULSE` is the outlier at ~42 segments because
`_seg_of`'s `MIN_SEGMENTS = 12` floor means a 5.6 px arc still gets 12.

---

## THE GUARD (the assertion that IS the maker's complaint)

In `tools/slice_test_spell_buttons.gd`:

- **`socket_glyphs_are_distinct_in_every_hand`** — for every class AND every reachable
  hand (the player leaves one non-ult role behind at class-select, so each class has
  C(4,3)=4 hands, not 1), the four glyphs are pairwise distinct and none is `NONE`.
  ⚠ The first version of the map passed on the DEFAULT hands and collided on six of the
  others. ⚠ Assert the pool size and the hand size BEFORE comparing — a hand that fails
  to build has nothing to compare and passes vacuously. Use `SpellLibrary._spell_by_id()`,
  not `build()`: `build()` omits the HEX-forked class signatures and produced an empty
  hand for eight of nine classes and a confident PASS.
- **`every_kind_maps_to_a_motif`** — iterate the ENUM, not the table (iterating the
  table only proves it agrees with itself). Plus a geometry assertion that the figure
  clears the ULT ring's inner edge, or the socket reads as one candy-striped smear —
  the exact fault the corner brackets were deleted for.
