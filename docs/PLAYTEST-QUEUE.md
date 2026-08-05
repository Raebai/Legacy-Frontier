# LIVE PLAYTEST QUEUE — 2026-08-05 (wave 4)

Written mid-playtest at the maker's request so a CLEARED session can resume on it.
Verbatim intent preserved. **Everything under "OPEN" is unstarted.**

> Branch `bot-fight-quality`, 153/153 green. Read `docs/NEXT-SESSION.md` for the
> session's root-cause notes; this file is only the ask-list.

---

## ▶ OPEN — do these

### 1. Destruction leaves marks that read as bugs
> *"when something gets destroyed it shouldnt leave like a crack in the air or those
> weird circular cracks in the floor"*

Two distinct artefacts. The **crack in the air** is almost certainly a decal or a
crack spawned at an impact point with no floor under it (`ScorchDecal` has no
ground-snap; `GroundCrater` DOES raycast and frees itself over a pit — compare the
two). The **circular cracks in the floor** are `ScorchDecal`'s `kind == "crack"` arm,
which draws a small chip plus radiating lines and was never given the ragged
treatment the scorch and the crater both got.
Start at `ScorchDecal._draw_crack` and every `ScorchDecal.spawn(... "crack" ...)`
call site.

### 2. The camera does not follow the fight
> *"get the camera logic to work properly focussing on the two fighting please"*

`ClipDirector` frames Watch Bots (`_frame`, `_fit_zoom`, `_relieve_the_lean`).
⚠ Known and relevant: **the duel camera is not in the `combat_camera` group**, so
every `Juice.shake_camera` / `zoom_punch_camera` / `zoom_pull_camera` call is a
silent no-op in this mode. That is a one-line add in `VersusArena` — but note
`ClipDirector._frame` WRITES `camera.zoom` and `global_position` every frame, so a
zoom punch will be fought unless the director's KO branch gets a zoom term too.

### 3. Bodies die and glitch into the floor
> *"most the time the characters die and glitch into the floor"*

Related to the death work already done. `BotMatch._put_the_loser_down` force-asserts
`rig.set_grounded(true)` and the rig drops its ride height toward
`PRONE_RIDE_FACTOR`; the topple impulse was just raised to 1050. Suspect the ride
drop plus the new impulse now pushes the drawn figure BELOW the floor line. The rig
draws relative to the body origin and the body is PAUSABLE (frozen at the KO), so
nothing corrects it. Look at `CharacterRig` ride/prone handling against `GROUND_TOP`.

### 4. Bots oscillate
> *"the movement is weird like sometimes the guy is just going back and forward"*

`BotBrain._steer` has a deadband on the spacing band specifically to stop this
(`STEER_DEADBAND`), so either it is too narrow or two bots' bands are interacting.
Reproduce with `tools/bot_duel_probe.gd`, which prints the per-frame intent.

### 5. Spells do not feel tangible
> *"the effect of the spell isnt tangible like a spell should have some knockback and
> stuff not crazy amounts but a decent amount"*

The bolt path is DONE — `SpellTier.push_for_damage` scales the shove off the spell's
own damage. What is untouched is every other spectacle: `BeamSpell`, `DivineRay`,
`EnergyNova`, `ZoneSpell`, `MeteorSigil`, `StarConvergence` etc. all carry their own
hand-tuned constants. Route them through the same helper.
⚠ Floors that matter: under ~12 impulse the rig skips its flop entirely; under
`SlamPhysics.MIN_SLAM_SPEED` (250) a body can no longer crack a wall it is thrown
into, which silently deletes the tower's crater and wall-break reactions.

### 6. Make it cinematic, make the bots smarter
> *"they are spamming spells which is fine but make it more cinematic and the bots
> smarter"*

Pacing work already landed (`FIRE_SPACING`, `ABILITY_SPACING` 0.80, `CAST_LATCH`
0.55, breathing gaps, desperation ults, a flinch on being hit). The maker has seen
some of it. Next honest lever is **the telegraph gap** — see below.

### 7. Warlock ⚠ MEASURED EVIDENCE CONTRADICTS THE REPORT
> *"warlock also needs a buff it got destroyed by the cleric"*

**Do not tune this on one fight.** The last real 72-bout round-robin measured
WARLOCK at **75%** — joint highest in the roster — and CLERIC at 38%. At n=16 per
class the noise is ±12 points, and a single observed bout is n=1. The honest answer
is a sweep, not a number change:

    godot --headless --path godot-project --script tools/botmatch_sim.gd -- \
      --roundrobin=1 --repeat=8 --round=22 --hp=190 --wall=70

Raise it with the maker before touching `CLASS_VITALITY` or the Warlock's kit.

---

## ⚠ THE BIGGEST UNFIXED THING (not yet reported by the maker, but it is the cause)

**`Hero` spawns no `Telegraph` at all.** Every melee swing, uppercut, frost cone and
Q/R/T is therefore invisible to `BotBrain`'s dodge layer — the three contact classes
fight each other producing ZERO threat descriptors, so the reflex ladder returns
empty every frame and the parry rung is never even entered. This is simultaneously:
"not much deflecting", "the bots aren't smart", and "the Juggernaut's punches have no
tell". It is the single highest-leverage change left in the bot stack.

---

## ✅ DONE IN WAVE 4 (all committed, none playtested)

Spawn on the ground (was 64 px in the air) · heavier death topple + faster spin +
immediate limp · burn 21 damage over 7 ticks -> 10 over 5 (fixes the DoT damage AND
the DoT sound, which were one cause) · no more sword drops for casters (layout data
deliberately kept) · storm clouds 190 -> 300 px · Cryomancer cone 12 -> 19 (was the
lowest primary in the game) · Swordsaint 26/0.42 -> 34/0.38 (the one class broken
beyond doubt: 19% then 25% over two sweeps) · dash distances normalised to ~110 px
with four named exceptions, and the suite that asserted the OPPOSITE was inverted.
