# RESUME HERE — 2026-07-27 handoff

Branch `stickman-integrate`. **52/52 suites green, all three scenes boot clean,
working tree committed.** F5 = `scenes/spike/SpellPlayground.tscn`.

## Controls (playground now matches the game's input map)

`LMB` use what you hold (punch / cast) · `RMB` **HOLD** to guard · `SPACE` dash ·
`W/↑` jump · `A/D` move · `S` duck · `Q/E` or **scroll** cycle spell ·
`G` cycle weapon · `B` test bolt · `H` hit · `K` kill · `R` reset · `TAB` tune.

## THE ONE BROKEN THING — Hollow Purple's gate

The fusion **seizes correctly** (both beams visibly bend into the crossing — that
part looks right) but the magic-circle gate never appears and the sequence ends
without a discharge.

What is already ruled OUT — do not repeat these:
- Not orientation. Side-on (`edge_on`) is CORRECT for this 2D side view; a
  face-on ring was tried and is wrong by design. Reverted.
- Not z-order. Tried in front of the beams; no change.
- Not the parent lookup. That was a genuine bug (it froze both beams then bailed
  without consuming OR releasing them, so the fusion grabbed the beams and let
  go) and it is FIXED — `reaction_release()` + a current-scene fallback.
- Not a crash. No runtime error is raised during the effect.

The decisive clue: a `print` placed inside `HollowPurple._process` produced **no
output at all**. So either that `_process` never runs, or `_circle` is never
assigned in `_open_circle()`. Start there — instrument `begin()` and
`_open_circle()` directly rather than guessing at draw parameters, which is the
mistake that burned two attempts.

Note the capture still stages it as **two crossing beams**. The maker wants the
SELF-COMBO: spells shoot from the caster, are absorbed into a circle in front of
them, and fire back out along the aim. The data rule exists
(`require_owner: "same"` in `ReactionTable`) but the demo path does not use it.

## BUILT BUT NEVER WIRED — audit results

Several systems were finished, tested and then never connected. Three remain:

1. **`SpellDeflect` has ZERO consumers.** So "every attack spell is deflectable"
   is still NOT true in game — only the basic bolt is. It needs threading through
   each spectacle's existing damage loop (one call, no new per-frame work).
2. **`CastStyle` is not used by `Hero`.** Per-spell cast poses exist only in the
   playground; the shipped hero still hardcodes one gesture for every spell.
   Wiring this is also where the maker's "magic circle + slight levitation when
   casting the more powerful spells" belongs.
3. **Auto-aim is still live in `Hero.gd`** at three sites — `Targeting.aim_direction`
   (485), `assisted_aim` (1436), and `nearest` (1746, which redirects a parried
   bolt at the nearest enemy). This contradicts the locked no-auto-aim rule.

Already wired this session: `GuardComponent`→Hero, `BotDodge`→Enemy,
`ParryRing`+`HandSlots`+`LoadoutBar`→playground, `Telegraph` perception.

## TOP PRIORITY NEXT — spells must respect the environment

Maker, and it is the biggest outstanding gameplay gap: **no spell may pass
through geometry.** Meteors currently fall THROUGH the floor; nothing may end up
below or inside the environment. A spell that meets a wall, the ground, or cover
should IMPACT there — and destroy what it can. "Every single spell should be
interactive." Environment-shaped spells included, and the whole thing should feel
more natural.

This is systemic, not a one-file fix: most spectacles resolve damage with a
geometry query and never ask what is between them and the target. Expect to
touch most scripts in `scripts/combat/`. Suggested approach: one shared
"stop at the first solid" helper (there is already a segment-raycast idiom in
`Spell.gd` and in `RockWall._hit_world`, which also documents the trap that
destructibles must be smashed THROUGH rather than treated as walls), then thread
each spectacle's spawn/travel/impact through it. Falling spells need their
impact Y resolved against the floor beneath the target, not the target's own Y.

Related and unbuilt: the maker wants a magic circle + slight levitation when
casting the more powerful spells (this belongs with the CastStyle wiring, #2
below), and the circle should sit ABOVE.

## SPELL-vs-SPELL INTERACTION (maker, and it pairs with the environment work)

"If any two of these line spells hit each other they should EXPLODE and go away.
Same if it hits the ice wall — use common sense for how they interact." So:
colliding spells must resolve against each other, not pass through.

Most of the machinery already exists and is unused: `SpellReactor` (autoload)
already detects two live effects overlapping and dispatches through
`ReactionTable`, which already carries rows for shatter-ice-barrier, steam,
ground-out, carve and a same-element merge. What is missing is that only
`BeamSpell` implements the participant contract — every other spectacle is
invisible to the reactor. Wiring the rest (reaction_shape/_active/_element/
_form/_owner/_consume) is the unlock, plus a generic "two projectiles meet ->
both detonate" row, which is the common-sense default the maker is describing.

## MAGE DEFLECT = AN ABSORBING MAGIC CIRCLE (maker)

For a caster, the guard should be a magic circle summoned at the right moment:
right click, and a spell that meets the circle on time is ABSORBED into it rather
than reflected. Same `ParryRing` timing underneath (perfect band = absorb), but a
class-specific presentation and outcome. This is the natural home for the
"different classes guard differently" idea — the swordsman parries with the
blade, the mage catches it in a sigil.

## HITBOX — spells pass through heads without registering (maker)

Reported live. The FIGURE's hit test was rewritten this session to use the real
silhouette (`SpikeFigure.body_distance`: spine segment + head circle, 9 px
margin). The dummies are `Enemy` nodes and were NOT changed — they still use
their own detection, so this is most likely on the Enemy side. Check what radius
Enemy uses and whether it accounts for the rig's height at all.

## Next work the maker asked for

- **Organise the spells**: pick 4 into slots, make the kit make sense per class,
  then test them all. The 26 in `build_all()` are a review harness — the real
  loadout caps at 4.
- Cast-time magic circles + slight levitation for the bigger spells (see #2).
- **Legendary weapon tiers** (e.g. the teleport dagger as a legendary variant).
- Screen effects on the big casts (PostProcess already has the primitives).
- Swordsman class + signature-ult framework + domains — specs are written in
  `docs/superpowers/specs/2026-07-27-*`.

## Standing judgement to repeat, not soften

Everything above is headless-verified and **almost entirely unplaytested**. The
defence numbers especially are reasoning, not feel: `DASH_IFRAME_FRACTION` 0.6,
`GuardComponent.MIN_DAMAGE_MULT` 0.60, `ParryRing.REARM_TIME` 0.35 and the ~0.09 s
perfect window are all guesses until played. Retune from one session rather than
building further on top of them.

Three live IP borrows still in shipped strings: `"Zoltraak"` (its description
names Frieren outright), `"Chidori"`, and `hollow_purple`. The maker agreed to
structure-not-silhouettes, so these want renaming.
