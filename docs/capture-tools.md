# The capture tools — an index

**Generated. Do not hand-edit — run `python python-tools/run_capture.py
--write-index` instead.** The summaries below are each tool's own first
header line, so a tool that describes itself badly here describes itself
badly in its own file, which is where to fix it.

These are the only instrument in this repo that answers a question about how
the game LOOKS. Everything else asserts about state.

## How to run one

```
python python-tools/run_capture.py --list          # everything, with descriptions
python python-tools/run_capture.py boss            # run it (substring match)
python python-tools/run_capture.py boss --open     # ...and open the output folder
```

⚠ **They need the GUI binary, never `--headless`.** Headless uses the dummy
renderer: every tool runs, every tool reports success, and every PNG is blank.
The runner always picks the GUI build so this cannot happen by accident.

Frames land in `C:\Users\Raaed\AppData\Roaming\Godot\app_userdata\Ashpire`.

## The tools

| tool | shows | run as |
|---|---|---|
| `archivist_capture` | THE ARCHIVIST — the spell tree, drawn. Three frames, because the whole point of | script |
| `arena_wide_capture` | Wide overview of the whole VersusArena stage (to see the mountain + terrain). | script |
| `blink_aim_capture` | Shows the three things about blink that no assertion can settle: it goes where you | script |
| `boss_capture` | Force a floor-5 (BOSS) run and render the Ashspire Guardian across its 3 phases. | script |
| `boss_redraw_capture` | Render THE FLOOR REDRAWING ITSELF at a boss phase break — all four artists. | script |
| `bot_clip_capture` | THE CLIP ENGINE — renders a real bot-vs-bot fight to a PNG frame sequence that | script |
| `cast_pose_capture` | Visual check for the per-spell CAST POSES (magic-overhaul rule 4). Renders the | script |
| `cast_windup_capture` | Visual check for the SHIPPED hero's casting PROCESS (not the spike rig — see | script |
| `ceremony_capture` | LOOK AT THE TWO CEREMONIES. A floor-1 mini-guardian and the floor-5 headline act, | script |
| `circle_capture` | Focused showcase of the upgraded MagicCircle: a big sigil on a plain backdrop, | script |
| `clash_capture` | Throwaway visual check for THE CLASH (scripts/combat/MeleeClash.gd): stage two | script |
| `class_spell_demo` | Fires the NEW class spectacles in VersusArena and renders a 2x2 sheet to | script |
| `combat_capture` | Combat capture: boot a combat scene, let bots fight, and render a CONTACT SHEET | script |
| `dash_agent_capture` | Throwaway agent-owned A/B check for the DASH visual (safe to delete). | script |
| `death_capture` | LOOK AT THE DEATH. Tests cannot judge "small but cute" — the maker's actual words | script |
| `debris_demo` | Deterministic debris/crater money-shot: loads the versus arena, detonates a | script |
| `demo_capture` | Non-headless demo + screenshot harness for the stick-fight combat core. | scene |
| `directed_clip_capture` | THE DIRECTED CLIP ENGINE — renders a bot-vs-bot MATCH as a PNG frame sequence that | script |
| `DirectorCapture` | PROOF THAT THE DIRECTOR ACTUALLY WORKS — drives the real thing and photographs it. | scene |
| `drain_tether_capture` | Saves four PNGs to user:// — one per beat of the spell, because the whole point | script |
| `drain_tether_ingame_capture` | Drain Tether, cast IN THE SPELL PLAYGROUND — the scene the maker actually plays. | script |
| `drop_capture` | Visual verification for the DROP ECONOMY's pickup entity + the handoff prompt. | script |
| `elite_capture` | ELITE READ CAPTURE — can you tell an elite from an ordinary body BEFORE it hits | script |
| `enemy_gear_capture` | Enemy gear capture: render the archetype weapons on stick rigs (brute club, | script |
| `floor_sim` | HOW LONG IS A FLOOR? — a headless estimator for the wave tables. | script |
| `floorgen_capture` | LOOK AT THE ROLLS. Renders the SAME floor drawn several different ways, into real | script |
| `freeplay_capture` | FREE PLAY, rendered — proof that the no-bots stage actually comes up: the | script |
| `friendly_fire_capture` | python python-tools/run_capture.py friendly_fire | script |
| `gear_capture` | Gear capture: render a row of stick-figure rigs, each with a class_preset, so the | script |
| `ghost_revive_capture` | Render GHOST FORM and the REVIVE prompt so they can be LOOKED at instead of | script |
| `handoff_capture` | CIRCLE HAND-OFF capture (circle-agent-owned; named uniquely so parallel agents' | script |
| `handoff_pad_capture` | Render the two HUD gaps this task closed, so they can be LOOKED at instead of | script |
| `hero_weight_capture` | THE IN-GAME PROOF — the same weight test, but on a REAL Hero in the REAL arena. | script |
| `horizon_cut_capture` | HORIZON CUT, across its flight -> user://horizon_cut.png (2x2). | script |
| `impact_frame_capture` | Visual verification for the IMPACT FRAME vocabulary + the arbiter (agent-owned; | script |
| `lightning_agent_capture` | Throwaway visual check for the LIGHTNING spells (thunderclap RUSH + chain_lightning | script |
| `loadout_capture` | Loadout UI capture: stand up the GameState + Loadout autoloads, open the panel, | script |
| `loadout_combat_capture` | Full-stack capture: set a custom LOADOUT (ice staff + hat + robe) on GameState, boot | script |
| `melee_signature_capture` | LOOK AT THE FIVE MELEE SIGNATURES. Tests cannot settle whether a cut reads as a | script |
| `meteor_capture` | Zoomed-out 2x2 time sequence of ONE Meteor Sigil so the whole shower reads: | script |
| `movement_verb_capture` | LOOK AT THE NINE MOVEMENT VERBS. No assertion can settle whether a Shoulder Charge | script |
| `new_spells_capture` | Saves user://new_spells.png. Shows Ice Wall, Chain Lightning, Void Zone, Rune Orbs, | script |
| `nova_capture` | Task 7 (right-size spell VFX) verification aid: fires the Arcanist's T (Nova) | script |
| `outfitter_capture` | CUSTOMISATION capture: the three screens a player now has that they did not before — | script |
| `postprocess_capture` | Post-process "look" capture: boot a combat arena and grab full-res frames of the | script |
| `rig_legs_capture` | THE LEGS, BIG ENOUGH TO JUDGE. Not a test — tests cannot see a leg. | script |
| `rig_look_capture` | Look-test for the stickman-integrate rig work. Tests cannot judge this — the whole | script |
| `rig_ragdoll_capture` | THE RAGDOLL A/B — does the game rig now have the spike's WEIGHT? | script |
| `rig_tickrate_capture` | THE MAKER'S COMPLAINT IS ABOUT HOW THE WALK LOOKS, SO LOOK AT IT. | script |
| `rig_vs_spike_capture` | THE THREE-WAY LOOK TEST: does the game rig STAND and RAGDOLL like the spike? | script |
| `rig_walk_capture` | THE MAKER'S COMPLAINT IS ABOUT HOW THE WALK LOOKS, SO LOOK AT IT. | script |
| `roster_capture` | LOOK AT THE ROSTER. Renders every boss in BossRoster, plus a modifier showcase, | script |
| `run_end_capture` | Render THE RUN-END CEREMONY — both endings — so the maker can LOOK at them | script |
| `sequence_capture` | Drives scripted inputs on a combat scene and renders a 4x4 CONTACT SHEET of | script |
| `sigil_matrix_capture` | LOOK AT THE SUMMONING CIRCLES. Renders the MagicCircle signature vocabulary as | script |
| `sigil_motif_capture` | LOOK AT WHAT THE CIRCLE SAYS THE SPELL IS. | script |
| `sky_capture` | LOOK AT THE SKY. The three floors that open onto one, each at two points in its | script |
| `spell_demo_capture` | Fires the spectacle signature spells in VersusArena and renders a 2x2 sheet to | script |
| `spell_ingame_capture` | Verifies the full IN-GAME signature path: presses the Ultimate action so the | script |
| `spike_capture` | Saves user://spike.png — four RAGDOLL figures aiming in different directions | script |
| `stickman_look_capture` | STICKMAN LOOK capture — the "is it actually a stickman?" render. | script |
| `summon_capture` | Capture a hero mid-SUMMON (spell circle blooming) then at ERUPTION, to review the | script |
| `summon_showcase_capture` | LOOK AT EVERY SPELL SUMMONING. Fires the eighteen spectacles that gained a | script |
| `terrain_capture` | Frame the playable TERRAIN band of VersusArena (HUD hidden) so the terrain look | script |
| `thrall_capture` | Visual verification for RAISE THRALL and GRAVE TIDE. | script |
| `tier_spell_capture` | Visual verification for the seven NEW drop spectacles (the three that reuse an | script |
| `touch_capture` | Force-show the mobile TouchControls over VersusArena to review the pad layout. | script |
| `town_capture` | THE TOWN — the game's front door. Four frames, so the layout can be judged by | script |
| `ult_focus_capture` | Full-resolution single-moment look at ONE ult, for when the contact sheet | script |
| `ult_sheet_capture` | THE ULT CONTACT SHEET — the only tool that can answer the maker's complaint | script |
| `verify_feel_capture` | Renders a 2x2 sheet of LARGE cells to user://verify_sheet.png so the maker's | script |
| `vfx_demo_capture` | Fire a Brawler's fire Q in the arena and catch the explosion layered over the | script |
| `wall_agent_capture` | Throwaway visual check for the WALL redesigns (rock vs ice + shove + shatter). | script |
| `wall_primed_capture` | Look at THE TELL. The two-beat is only fair if the player can see, before they | script |
| `ward_capture` | Visual verification for the AEGIS WARD and the STEAM CLOUD (agent-owned; safe | script |
| `weather_capture` | LOOK AT THE FLOOR'S AIR. One cell per biome, all ten, each showing that floor's | script |

_76 tools._
