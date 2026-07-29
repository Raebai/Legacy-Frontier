# RESUME HERE — 2026-07-29 handoff

Branch `stickman-integrate`. **91/91 suites green; `VersusArena.tscn`, `Main.tscn`
and `SpellPlayground.tscn` all boot clean. NOTHING IS COMMITTED — the whole of the
2026-07-27→29 session is sitting in the working tree.**

Play: **`scenes/combat/VersusArena.tscn` → F6.** You land in a 1v1 against a bot.
**Esc** = Resume · Settings · **Fight the Boss** · Rematch · Exit to Hub.
**Esc → Settings → Bot Duel**: difficulty, bot class, learning, show-learned,
bot-intent, forget-me. F5 still opens the SpellPlayground.

## READ THIS FIRST — "green" now means something

64 of the test suites were silently passing while testing nothing. In GDScript a
dead property read **aborts the enclosing function** and returns the type's zero,
which the `failed += _test_x()` idiom reads as "no failures" — so a renamed member
disabled its own assertion *and every assertion after it*. All suites now
accumulate failures on a **member** and record a **completion sentinel**, so a test
that aborts fails BY ABSENCE. `tools/slice_test_loadout.gd` is the reference.
**Never write `failed += _test_x()` again.**

## The maker's rig — SETTLED, and this was the session's hardest thread

`Hero.tscn` uses `CharacterRig.gd`; the maker's hand-tuned rig is
`scripts/spike/SpikeFigure.gd` (playground only). They are different files, and for
most of this session the game ran the wrong one. Three attempts shipped partial
ports before the real cause was found: the spike's feel comes from **two springs on
a torso that never touches the ground** — a one-sided **ride spring** (legs push up,
never pull down) and a **pitch spring** whose gain IS the state machine (1.0
planted, 0.09 airborne, 2.6 dashing). Earlier ports brought the skin (world-locked
feet, slack limbs, proportions) and left the skeleton. Both springs are now in
`CharacterRig`, driving the rig node's own `position.y`/`rotation` — which is why
`Enemy._silhouette()`, `get_weapon_tip()` and the ghosts all follow for free.
Rig ticks on `_physics_process`, sub-stepped 1/480 s.

**Do not "improve" the spike's numbers.** They are hand-tuned. One is flagged:
`PRONE_RIDE_FACTOR` is the spike's 0.552; 0.30 is also tested if the knocked-down
sprawl sinks too far.

## THE ONE RULE THAT KEEPS FINDING BUGS

**A spectacle built without a caster is silently inert in the whole reaction
system.** `reaction_owner()` returns null → reports "unowned" → satisfies neither
`require_owner: "same"` nor `"different"` → matches NO clash row. Nothing errors.
That single omission was: the Hollow Purple "bug" that burned two sessions (the
spell was never broken — the capture tool spawned casterless beams), seven unowned
Boss spectacles, two on Enemy, and the zone field unable to reach its own authored
rows. `SpellCaster._stamp()` now stamps element + tier + caster + target_group on
all 21 arms, so forgetting is no longer expressible there.

## Other traps that cost real time (do not rediscover)

- **`take_damage` ships two signatures** — 1-arg (Hero, destructibles), 2-arg
  (Enemy, Boss). Calling the 2-arg form on a hero aborts the function, losing the
  hit *and* everything after it. **Always use `SpellTargets.hurt()`.**
- **`Net.is_active()` was true in single player** — Godot installs an
  `OfflineMultiplayerPeer` that reports CONNECTED, so ~40 co-op gates were silently
  open in SP. Fixed by excluding that peer type.
- **Autoloads are NOT registered under `--script`.** Naming `Sfx`/`Net`/`Tuning`
  inside a **static** function is a *compile* error that fails the whole dependency
  chain, and reports as an unrelated missing method. Use the tree lookup
  (`SpellDeflect._sfx`).
- **Spectacles park at the arena origin** — `global_position` is (0,0) and is NOT
  where the effect is.
- **Stale global class cache** — run `--headless --import` after any new
  `class_name`, or Godot reports a missing method on a class that plainly has it.
- **Group drift**: `"hero"` (tower) vs `"player"` (v0.0 hub). Wrong group = a
  mechanic that silently does nothing (it killed the tether's life-drain AND the
  consecration field's heal).

## Built this session (all headless-verified, MOSTLY UNPLAYTESTED)

Melee **clash** (blows declare at the commit, not at contact) · **impact-frame
vocabulary** (white blow-out / black silhouette cut / element field / invert /
cut-in) with a rate-limiting arbiter + accessibility ceiling · **spell-vs-spell
reactions** incl. weight (equal annihilates, heavier overpowers), fire shatters ice,
**holy BANISHES shadow** (erasure, no knockback), the rock-wall **ram** ·
**Aegis Ward** (protective spell; plates burn down, weight drops, no HP number) ·
**Swordsaint** 9th class (guard BANKS a perfect parry into a cut) + Horizon Cut ·
**factions** (hero-vs-hero works at all) · **bots** (three-layer brain, per-instance
input, difficulty dial proven 0.41→0.95 escape) + **adaptive learning** persisted to
`user://bot_adapt/` · **bot sim** with seeded anomaly detection · **twin-stick
touch** · **115-key audio roster** from the local library · meteor **sky gate**
restored (it had been deleted, so rocks fell from off-screen).

## Open / next

1. **COMMIT.** Nothing is committed. This is the biggest risk in the repo.
2. Maker F5 verdict on the rig springs, knockback (`TuningConfig.knockback_mult`
   1.6→1.0; go 1.2 if floaty), and whether the mirror-match beam explosion reads.
3. `BotAdapt.anti_camp` lives in `BotController`; belongs in `BotBrain._steer`.
4. Bot slot coverage uneven — Arcanist leans on its damage line.
5. Licensing: **Pepper Sound Pack wants attribution** on the credits screen;
   TomMusic's licence is unconfirmed (pre-existing). See `assets/audio/CREDITS.md`.
6. `hollow_purple` still to rename (IP); proposal `prism_collapse`, file list in the
   session log.
7. Melee still auto-targets the nearest enemy — in tension with the locked
   no-auto-aim rule. Maker's call.

## Standing judgement — repeat it, do not soften it

Every feel number in this stack is **reasoning, not feel**. Clash window 0.09,
guard bands, impact-frame `MIN_INTERVAL` 0.26, the whole audio mix (nobody has
heard it), knockback, the rig springs. The maker's one-line complaints from live
play found more real bugs this session than the entire test suite did — the dodge
bug, the invisible sky gate, the silent beam clash, the wrong rig. **Playtest
beats reasoning every time.**
