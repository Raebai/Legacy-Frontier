# RESUME HERE

## STATE — 2026-09-05, the live-playtest session. 17 COMMITS, PUSHED.

Branch `bot-fight-quality`, pushed. Seventeen commits landed in one sitting while the
maker played and fed back live. **205+ suites green. NOTHING IN THEM IS PLAYTESTED** —
every claim is a measurement or a headless suite.

### ⚠ FIRST THING: THERE IS UNCOMMITTED WORK IN THE TREE

Three subagents were still running when the session ended. **If their work is not
committed, it is sitting dirty in the tree — `git status` first.** Diff it, run the suites
named beside each, then commit or discard. **Do not assume it parses** — an in-flight
agent edit is how three suites went red mid-session.

**(a) Tavern lobby + title screen** — `scripts/World.gd`, `scripts/HubAmbience.gd`,
`scripts/ui/AntechamberBackdrop.gd`, `scripts/ui/Lobby.gd`, `tools/probe_antechamber_backdrop.gd`,
`tools/slice_test_antechamber_sky.gd`.
The maker PLAYED it and liked it — refine, do not restart. Their four notes: the fire
escapes the furnace and must be bounded to it; there are stray yellow lines that mean
nothing (give them a reason or remove them); add ledges where helpful; add curved
structures (arches, a vaulted ceiling, a curved bar front) because the room is currently
all rectangles. Plus the title buttons, asked TWICE.
`slice_test_town  slice_test_town_bounds  slice_test_town_interact  slice_test_settings
slice_test_shell  slice_test_antechamber_sky  slice_test_stage_layers`

**(b) Gear replaces body parts + unlock legibility** — `scripts/ui/Outfitter.gd`,
`scripts/ClassSelect.gd`, `scripts/combat/CharacterRig.gd`, `scripts/combat/GearAbilities.gd`,
`scripts/GameState.gd`, `scripts/combat/Progression.gd`. See queue item 4 below.
`slice_test_outfitter  slice_test_grimoire  slice_test_class_select_layout
slice_test_rig_body  slice_test_rig_gait  slice_test_climb`

**(c) Floating platforms carve into bits** — `scripts/combat/BreakablePlatform.gd`,
`scripts/combat/RuinPlatform.gd`, `scripts/combat/FloorBuilder.gd`,
`scripts/combat/DestructibleStage.gd`. See queue item 5 below.
`slice_test_destructible_sources  slice_test_destructible_carve  slice_test_floor
slice_test_floorgen  slice_test_one_screen  slice_test_wall_reachable`

### PLAY IT
**F5** → title → Single Player. **Lobby → Watch Bots** for the showcase.
The Android APK is stale — it predates every commit below.

---

## ▶ THE OPEN DESIGN QUESTION — asked, not answered

Maker: *"the classes should amplify current spells but it shouldnt prevent any player for
taking any spell."* The second half is built (the Grimoire pool is not gated by class).
**The first half is not, and needs the maker's steer before anyone builds it.**

There is no per-class amplification today: a Warlock casting The Void casts exactly what
an Arcanist casting The Void does. The bots already have machinery to copy —
`BotMatch.CLASS_POWER` is a per-class damage multiplier written straight onto
`_growth_damage_mult`. The question is which axis it rides:

* element affinity (shadow spells hit harder on the Warlock, holy on the Cleric), or
* a flat per-class multiplier like the bots', or
* per-role (the class's own authored role for that slot is the one amplified).

Ask before building. It moves every class's balance at once.

---

## ▶ THE QUEUE

**1. TAVERN LOBBY + TITLE BUTTONS — IN THE TREE, UNCOMMITTED.** See the block above.
   The brief: *"make the lobby very different like a tavern vibe ... not outside at a
   campfire but instead inside of a tavern with warm lit and cool graphics"*, plus *"the
   far left side of the lobby can be a little further out before the invisible barrier"*.
   ⚠ **THE MAKER ASKED TWICE FOR THE TITLE BUTTONS TO SHRINK**, which usually means the
   first attempt was not visible enough: *"remove the box on the home screen around the
   single player multiplayer etc. options"* and *"make the single player multiplayer etc.
   buttons smaller so that they dont overshadow the cool graphic on the left"*. Read that
   as NARROWER and moved clear of the artwork — `slice_test_settings` requires those two
   named primaries to clear 46 px of HEIGHT (9 mm, a thumb target) and caps the secondary
   band at two rows, so shrinking their height would break a measured rule. Verify with a
   number, not by eye.

**2. CLASS SELECT NEEDS A REVAMP — the one ask left completely untouched.** Maker:
   *"please revamp how the class selection looks it needs to be simple and way more
   aesthetic and easier to use"*, and separately *"there should be class selection as the
   main theme and then a change spells button, no need for the armoury button within the
   class selection"*.
   ⚠ The current master-detail rail was ITSELF the product of an earlier *"revamp how the
   class selection looks"*, so a third pass done blind will probably miss again. **Get a
   direction from the maker first.** The keyboard/hover preview added this session works
   and should survive any restyle (`ClassSelect.gd`: arrows and hover move ONE cursor, and
   the rail rows are `FOCUS_NONE` because Godot's own focus walk eats `ui_down` and skips
   disabled rows — which are exactly the guarded classes a preview is most for).

**3. MULTIPLAYER → A REALM / CHARACTER SCREEN. BLOCKED ON TWO FACTS, not on effort.**
   Maker: *"pressing multiplayer should take you to a character selection screen where you
   can add other people to your realm etc. and connect local play"*.
   * `Net.MAX_PLAYERS = 2`. "Add other people" implies 3+, which contradicts the settled
     mobile scope-lock (2 players, one-screen floors).
   * **There is no player identity at all.** `Net` tracks `peer_class` and nothing else —
     no display name, no friend list, nowhere to store one. A realm screen built today
     could only ever say "Player 2 — Stormcaller". It is a persistence feature wearing a
     UI feature's clothes.
   Local play already exists and works (`Host Co-op` routes through loopback); it is
   simply not labelled as local.

**4. GEAR THAT REPLACES A BODY PART, AND UNLOCKS YOU CAN READ.** In flight as (b) above.
   Maker: *"no need for an armoury button within the changing class selection and the
   grimoire is cool but still not clear what is unlockable and what isnt like for the
   class and how to unlock it same with the armoury items please make mock versions of
   like helmets and stuff that replace the character head are not work on top and other
   items that emphasise what they do and do some thinking on how these items should be
   unlocked"*.
   ⚠ **THE MAKER'S INSIGHT IS THE DESIGN.** A helmet drawn OVER a stick figure's head
   reads as a hat balanced on a dot, which is very likely why `CharacterRig.GEAR_DRAW` is
   `false` and gear does not render at all — overlay gear looked wrong, so it was switched
   off rather than redrawn. If the helm IS the head — same slot, different outline — the
   figure stays a stick figure and the item reads at 640x360. Sticks stay sticks; the
   PARTS change shape.
   **The unlock design, and do not invent a currency:** guardians already grant a banked
   PICK spent at the class altar (`Progression.CLASS_UNLOCK_FLOORS`, real and tested, and
   currently disabled by `ALL_CLASSES_UNLOCKED = true`), and
   `docs/superpowers/specs/2026-08-04-spell-trees-and-progression-design.md` specifies
   Skill Points and was never built. The Grimoire and Armoury should be the VIEW onto
   those: every row HELD / EARNABLE (with the exact verb on it) / CLASS-LOCKED (saying
   whose). ⚠ While `ALL_CLASSES_UNLOCKED` is true everything correctly reads as HELD —
   flip it to actually SEE the three states.

**5. FLOATING PLATFORMS CARVE INTO BITS.** In flight as (c) above. Maker: *"please make
   the floating platforms destroyable into bits just like the floor was beforehand"*.
   Not a contradiction of the solid-ground ruling: a ledge is optional footing, the floor
   is the floor.
   ⚠ **THE TRAP**: `carve_area` finds its stage by scanning `GROUP_NAME` and returning THE
   FIRST MEMBER — written for a world with exactly ONE stage. If platforms join that
   group, every carve in the game routes to whichever platform is first. The right
   primitive is `carve_from_body`, which routes by `BODY_META` on the collider actually
   hit. `slice_test_one_screen` asserts nothing is left in that group; if it goes red, the
   wrong route was taken — do not relax it.

**6. ARMOURY: RECOLOUR THE STICKMAN PER PART.** Maker: *"in the armoury I should also be
   able to change the colour of my stickman figure the colour of his head body and legs
   individually"*. Not started, and distinct from item 4 (that one is SHAPE, this is
   TINT). Today there is one whole-figure colourway (`Outfitter.chosen_colourway` →
   `GameState.colourway` → `Hero._configure_class`). Three independent tints means a new
   save shape and three pickers on a screen already measuring 338 px against a 360 px
   ceiling — the HEIGHT is the hard part, not the tints.

**7. REAL ARMOURY ITEMS.** The placeholders are still inert and the real stat ranges are
   gone: max HP 0.94-1.20x, move speed 0.92-1.12x, melee damage 0.82-1.30x, cooldown
   0.70-1.30x, knockback 0.88-1.40x, a 0.40 one-shot ward, 0.15 flat mitigation. Any class
   quietly tuned around "you will wear a helmet" is squishier than intended. Machinery,
   saves, sanitiser and paper doll are already wired — this is authoring, not plumbing.
   ⚠ `CharacterRig.GEAR_DRAW` is FALSE under the "just stickmen" ruling, so helms and
   armour will not render on the doll even as real items. Only held weapons do.

**8. WALLS DO NOT TAKE THE MATERIAL THEY ARE MADE OF.** Still the best unbuilt idea in the
   destruction work — a rock wall leaving a trench exactly as long as it is wide makes
   cover and hazard one act. Needs a **capsule sibling to `carve_disc`**: a wall's
   footprint is a long thin SPAN, and a row of discs is the shape most likely to move the
   severed-run number off 0. `HorizonArc` is deliberately unwired for the same reason and
   waits on the same primitive.

**9. `probe_reachability` REPORTS 252 OF 939 PUBLIC ENTRY POINTS WITH NO SHIPPING CALLER.**
   It is a REPORT, not a gate, and it over-reports for autoloads. Read it and promote what
   matters, the way `slice_test_wall_reachable` already did for the shove.

---

## WHAT LANDED THIS SESSION (all measured, none playtested)

**THE BIG ONE.** The maker watched Watch Bots and said the main game did not have "all
these cool classes spells and interactions". Investigated rather than guessed; three gaps
were real:

1. **The climb had NO destructible terrain at all.** `VersusArena` held the ONLY line in
   the project that ever constructed a `DestructibleStage` — so the showcase, the duel and
   Free Play had it and the tower never did. All 21 carve call sites were dead there,
   silently, because the refusal counters live ON the stage that did not exist.
   ⚠ **AND THE MAKER THEN RULED IT BACK OUT** after trying it: *"also dont make the ground
   destroyable"*. Ground is solid; crates, props and every ledge break.
   **Do not re-add the ground slab.**
2. **Eleven spells were castable only by bots** — the nine Tier 3s and both Tier 2s,
   reachable only through `BotMatch._grant_showcase_drop`, because `TOWER_SPELL_DROPS` is
   false by the maker's own earlier ruling. Now equippable in the hub: the **Grimoire**.
3. **Showcase fighters are a different power tier** — roughly 3.3x HP, a per-class damage
   multiplier, and `SHOWCASE_COOLDOWN_MULT` 1.6 giving each cast room to READ on screen.
   Untouched, and it is the remaining reason a climb fight does not look like a bot fight.

**Fixed from the playtest:** the RMB/Spc labels overlapped by ~4 px at desktop scale (no
probe in the repo had ever measured two DRAWN strings against each other — only each
string against its own box); slot 1's stray gold ring was a vestigial "last cast" marker
and the ult's ring now closes as it recharges; Juggernaut and Swordsaint drew TWO attack
shapes on one press; **close-range melee missed because the attacker lunges 13-18 px past
the target between the press and the hit frame** (measured 0 hits at every distance
before, 1 after); Nova removed from all nine classes; the class roster previews on arrows
and hover, and its three guarded rows were never actually being dimmed; one sigil on a
cleared floor; the wand's "3 glowing lights" were the aura re-drawing the whole figure —
weapon included — three times, scaled about the BODY origin; Shadowburst travelled 40 px
further than a FREE movement button (now 420); Zanshin's tally buys CUTS instead of one
bigger cut; the head bar sits higher; elites cast the ORPHAN spells no class carries;
**a boss's ballistic leap was overwritten by the walk drive one frame after launch** (113
airborne frames producing 99 px of travel — it pogoed off the ledge's underside for ever),
and the Illuminator and Cartographer now fly; the Warlock carries a void rod, SPACE dashes
and R swaps with its thrall.

---

## ⚠ TRAPS THIS SESSION PAID FOR — do not re-learn these

* **THE GODOT EDITOR STRIPS `project.godot` KEYS WHILE IT IS OPEN.**
  `common/physics_ticks_per_second` and BOTH `renderer/rendering_method` lines went
  missing mid-session while the maker was playtesting. `slice_test_mobile_config` is the
  guard. **Run it before any push**, along with `check_window_override.py`.
* **A tracked file was corrupted by stray keystrokes** — `rigddddddddaaaaaaaa()` appeared
  in `EliteHerald.gd` and took THREE unrelated suites down at once. If several unrelated
  suites fail together, `git diff` before debugging any of them.
* **Do NOT edit code through shell heredocs.** Python-through-bash emitted a literal
  `.strip()` into GDScript this session, on top of the three `\n` incidents already on
  record. Write a patch FILE with single-occurrence anchors and **assert the count** —
  that assertion caught a double-apply that had already duplicated two lines.
* **Subagents with STRICT file ownership work** — five used, zero collisions — but their
  in-flight edits make a full sweep unreadable. Verify per-suite and commit per-agent, and
  never accept "that failure is not mine" without checking: one agent was right about
  exactly that and another was wrong about it an hour apart.
* **A test that has never gone red is a test of the fixture.** Every behavioural change
  here was run against its own disabled fix first, which is what caught: a 0.4 px residual
  overlap AFTER the "fix"; `void_barrage`'s elite damage set to exactly its library value
  ("re-tuned" that had re-tuned nothing); and two preconditions quietly reading a node
  that had already freed itself.
* **A precondition ORed against the thing it precedes is not a precondition.**
  `flag or carve_events > 0` is true on a green tree however dead the flag reads.
* **`_apply_room_size` is re-driven on every floor**, so anything it builds must be
  find-or-create — and a `DestructibleStage` must be removed from its GROUP before being
  freed, because `stage_in` returns the FIRST member and a stale one silently catches
  every carve in the game.

## HOW TO VERIFY
```
python python-tools/run_all_tests.py --jobs 3        # ~205 suites, ~260s
python python-tools/check_window_override.py         # 1366x768 committed
godot --headless --path godot-project --script tools/slice_test_mobile_config.gd
```
