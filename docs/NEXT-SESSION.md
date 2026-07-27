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
