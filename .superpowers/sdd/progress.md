# Slice 0 (+ Slice 1) — Subagent-Driven Execution Ledger

Branch: `v2.0-tower` (built directly on branch — Godot/Gopeak bind to this working dir).
Plan: `docs/v2.0-slice0-plan.md`. Slice 1 plan: TBD.
Godot headless binary: `godot-engine/Godot_v4.6.2-stable_win64_console.exe`
Builder model: Fable 5.

=== SIDE-ON PLATFORMER CONVERSION (2026-07-11, maker thumbs-up) ===
Maker played the top-down versus arena + decided: make it genuinely SIDE-ON (gravity + jumping, Stick Fight / Brawlhalla), "aesthetic like a proper simple stick fight game." Control scheme approved: A/D move, Space jump (+double), Ctrl dash, hold Shift = jetpack-fly (ascend), LMB cast / F melee / Q meteor / T nova / R blink / RMB parry — all aim at cursor. This IS the pivot I flagged; rigs already draw side-on so the LOOK barely changes, the PHYSICS change.
PLAYTEST TUNES SHIPPED FIRST (9f6ca30): nova 3->5s, meteor is player-placed at cursor (BLAST_MAX_RANGE 480), parry UNIVERSAL (mage can_parry true now), versus bots tankier (BOT_HP 110) + spell-slingers (BOT_ARCHETYPES [CASTER,SUMMONER,CHARGER]), music -12->-20db, victory banner moved to top.
STEP 1 DONE+VERIFIED+COMMITTED (421a067): Hero side-on physics — GRAVITY 1500, jump (Space, JUMP_VELOCITY -540) + double-jump + coyote 0.1 + jump-buffer 0.1, horizontal move via get_axis, dash->Ctrl (input remapped, jump added Space+W), fly->jetpack (velocity.y ascend while held, fuel unchanged), blink->aim (cursor). is_on_floor via default up_direction. Removed flight's ring-out immunity (blast zones are hard now). 22/22 suites green + import clean. NOTE: versus scene NOT playable yet — no physical platforms, so the hero falls through; needs STEP 2.
STEP 2 (VersusArena side-on stage) — NOT STARTED (maker does not: I do it, conflict-prone + logic-interwoven). Rebuild: sky background (clean/simple), SOLID StaticBody2D platforms on layer 1 (main ground + 2 float), blast zones (StageHazard PIT) below + far L/R = ring-out, DestructibleTerrain cover, spawns ABOVE platforms, camera limits framing stage+sky. Keep ring-out/registry/HUD logic untouched.
STEP 3 (Enemy side-on AI: gravity + horizontal chase + jump) — Fable subagent BUILDING NOW (Enemy.gd + test). Integrate after step 2.
*** CLAUDE CAN NOW SEE THE GAME (965ad9a) *** tools/screenshot.gd: run with the GUI binary (real GPU renderer, NOT headless which is a dummy black frame):
  "godot-engine/Godot_v4.6.2-stable_win64.exe" --path godot-project --script tools/screenshot.gd
  -> saves user://shot.png (C:/Users/Raaed/AppData/Roaming/Godot/app_userdata/Legacy Frontier/shot.png); Read that PNG to see the current build. Optional 2nd user-arg (after --) = a res:// scene path. NEXT ENHANCEMENT (maker asked for a "better way"): make it capture a SEQUENCE of frames (~2s burst) + optionally DRIVE scripted inputs (Input.action_press move/jump/cast) so motion/animation/physics are visible, not just a static idle frame. That's the real fix for verifying walk/jump/mouse-follow.
FIRST SCREENSHOT OBSERVATIONS: player figure is FAINT/BLOBBY/low-contrast vs the sky ("weird player", "can't see him") -> make the stickman crisp: darker/heavier line weight + maybe an outline. WEIRD PINK ARCS in the top-left/top-right corners = an artifact to find + remove (Rank aura? some screen-space draw). Stage otherwise reads clean.

SIDE-ON PLAYTEST FEEDBACK BACKLOG (maker, 2026-07-11 — "take your time make sure its amazing"; do WITH the screenshot loop + copy Stick Fight's feel EXACTLY):
- SETTLED CONTROLS: A/D move, UP or W = single jump, Space = dash (toward AIM, any direction), Shift = jetpack, R blink, LMB cast, F melee, Q meteor, T nova, RMB parry. (jump was reported broken on up-only -> added W; VERIFY up-arrow actually jumps, could be an is_on_floor/landing bug not just binding.)
- MOVEMENT/LOOK (copy Stick Fight): the whole BODY should NOT flip/rotate with the mouse — only the FACE/HEAD tracks the cursor; body faces MOVEMENT. Head should "somewhat follow the mouse." Want the SMOOTHNESS of Stick Fight. Visible WALK motion (small leg movement) — current run cycle reads as not-moving. Punch (F) should visibly connect + knock the target back. Dash needs a WIND effect.
- BLINK: should go THROUGH walls to the cursor (or facing dir) a set distance — remove the wall-collision clamp in _blink/_blink_destination. Better blink SFX (synth one like ding/footstep).
- SPELLS: STILL passing through blocks/items despite the mask+StaticBody2D fix (965ad9a era) — DEBUG with a screenshot; also EnemyProjectile (radius-based) still passes through (needs a wall check). Spells should COLLIDE with each other: stronger fizzles the weaker (projectile-vs-projectile). "Flowier" combat. Magic bolt impact = a small explosion (partly done, verify).
- NOVA: must NOT crack the SKY (nonsense) — only crack nearby items/the floor. METEOR effect should CLEAR UP over time (the scorch/decal lingers). Want ACTUAL particle physics + map-based destruction: things destroyed by certain spells depending on the map.
- PHYSICS DESTRUCTION (big): rigid-body CHUNKS that break off + FALL based on where hits land ("realistic"). Ground/arena pieces physics.
- DEFLECT/PARRY: show the little Stick-Fight BARRIER/shield; only deflects if you FACE the bolt + time it (directional + timed) — currently omnidirectional, no visible shield.
- RING-OUT: disabled for now ("no falling off yet") via walls; re-enable later.
- MOBILE-FIRST (standing constraint): ~10 actions won't fit touch — must CONSOLIDATE to joystick + a few buttons. Design the control set to be SIMPLE for mobile. Think about this before adding more abilities.
- SCROLLABLE SPELL-SLOTS: mouse-wheel to switch the active cast spell (loadout) — do after platforming/look feels right.

=== SLICE 3 (combat feel + MMO layer + world unification) — 2026-07-11 ===
Spec: docs/superpowers/specs/2026-07-11-slice3-combat-feel-and-mmo-layer-design.md. Driver: maker playtest feedback on the Slice 2 loop. Approved: aim-to-cursor+soft-assist, ground the floaty look (wave 3), combat-feel first, "get this ALL done" (all 3 waves incl. parry). Sequenced feel->depth->looks.

WAVE 1 (Combat feel) — DONE + HEADLESS-VERIFIED + COMMITTED (e5b3acb, 2043050, 6e0090d, c75ff22). UNPLAYTESTED.
- Twin-stick aiming: `_aim_dir` (cursor) drives cast/blast/melee-arc/cast-pose/camera-peek; `_move_dir` (WASD) drives dash+blink. Decoupled = strafe. `Targeting.assisted_aim` bends aim toward an enemy in a ~18° forgiveness cone within 420px (bend 0.6) — precise but forgiving, maps to a mobile aim-stick later (D-S3-1, preserves mobile-first).
- Cast pose: `CharacterRig.set_aim` points the lead arm/staff at the cursor (pitch only; body still flips L/R, stays upright).
- Camera calm: lookahead 22->8px, now tracks AIM not movement (strafe stops lurching); cast shake 2.0->1.0. `lookahead_dist` + `shake_scale` are LIVE Tuning knobs (Remote->Tuning) for maker taste-tuning.
- Portal fix: ExitPortal polls get_overlapping_bodies() each armed frame (was enter-edge only) + one-shot `_taken` guard. Fixes hub tower-entrance AND arena floor-exit ("walk in, nothing happens").
- Juice+audio: punch knockback 220->300 fists / 320->400 sword (shove read), bright "ding" on clean melee, footstep ticks while running (rogue 0.22s / mage 0.27s), movement accel/friction ramp (`move_accel` knob) for weight. ding.wav/footstep.wav synth'd by a Fable subagent via python stdlib (python-tools/generate_placeholder_sfx.py) — zero external-asset dep.
- Tests: new tools/slice3_test_aiming.gd (6 assisted_aim cases). Updated slice1_test_weapon (knockback 300/400) + slice1_test_blink (blink follows _move_dir). ALL 16 SUITES GREEN. Import clean, no errors.
- WATCH recurred: the open editor lossy-resaved first_npc.tres/mirelle.tres/placeholder_atlas.tres/Main.tscn/project.godot on close — REVERTED before commit (only the 7 intended combat scripts + assets shipped). Confirm those .tres fields survive if the editor reopens.

WAVE 1 NEEDS MAKER F5 (Gopeak can't render feel): does aim-at-cursor feel right; is the strafe/dash-follows-movement split intuitive; is the camera calm enough; punch shove + ding land; portal reliable now. Twin-stick decoupling (D-S3-1) is the big feel call — validate before waves 2-3 build on it.

WAVE 2 (MMO layer) — PARRY + HOTBAR DONE + VERIFIED + COMMITTED (dccfa8c parry, 0c8f9d3 HUD, uid commit). Enemy abilities IN PROGRESS (Fable subagent).
- Parry (rogue only, RMB): PARRY_WINDOW 0.16s active window; a bolt arriving in-window triggers EnemyProjectile.reflect() -> flips to hunt "enemy" group, 1.5x dmg, recolored to hero element, back toward nearest enemy (fallback: aim). Reward = loud "ding" + hitstop + flash. Miss = eat it. Mage can't parry (can_parry in CLASS_CONFIG). Melee moved to F-only, RMB freed for parry.
- Hotbar HUD (AbilityBar.gd, Fable-authored): bottom-center per-class slots (Cast/Dash/AoE/Blink/Nova/Parry) w/ cooldown fill-sweep + ready-glow + dimmed-disabled (mage shows Nova, rogue shows Parry). Reads Hero.ability_hud_state() each frame; null-safe; on a layer-60 CanvasLayer in Arena (run+sandbox). NOTE: AbilityBar _draw path not yet runtime-exercised (headless --script doesn't boot Arena) — validate in the final boot/playtest pass.
- Tests: slice3_test_parry.gd (4 cases: rogue reflect, mage-can't, no-window-takes-hit, reflected-hits-enemy). ALL 17 SUITES GREEN. Import clean.
- Enemy abilities: SUMMONER archetype (telegraph -> spawn chaser minions) being authored by a Fable subagent (Enemy.gd + Encounter weighting + test). Integrate+verify next.

WAVE 2 enemy abilities: SUMMONER archetype DONE + VERIFIED + COMMITTED (93b836c) — telegraphs then spawns 2 chaser minions; Encounter-weighted toward deeper floors; jade tint. 18/18 suites green.

WAVE 3 REFRAMED -> VERSUS ARENA (maker redirect 2026-07-11, in spec). NOT a pivot — a continuation toward the Smash/Brawlhalla/Stick-Fight versus vibe. View/movement UNCHANGED (already side-on stick figures, top-down free movement). NO gravity/jumping rebuild (deferred). Additive build order: (1) destructible map DONE+VERIFIED+COMMITTED (9f2bb48) — DestructibleTerrain StaticBody2D, group "destructible" + collision_layer 5 (matches crate), so Spell/Blast/Nova/melee/dash ALL already damage it (spells-hit-destructible was ALREADY wired — my "only melee" worry was stale). Multi-hit, progressive cracks, shatters to open the space. 19/19 suites green. Placed-in-stage happens with the versus stage (step 5). NOTE: new class_name -> import before run; (2) ring-out pit/edge/slope zones + stocks/respawn; (3) impact juice (landing dust, hard-hit floor craters "where they're sent"); (4) flight ability (grounded default, dust on land); (5) versus stage + P1-vs-AI-bots mode w/ stocks (local gamepad P2 later — twin-stick maps to controller); (6) mobile-aware throughout. North-star LATER: anime ultimates (divine smite, magic-circle bear summon) on the telegraph->long-cast pattern. Hub walking/talking stick NPCs deferred behind the versus focus.

VERSUS ARENA PLAYABLE (2026-07-11) — commits 9f2bb48 (DestructibleTerrain), 05a146e (StageHazard pit/slope), 17e7648 (VersusArena: P1 vs 2 AI bots, 4-side pit ring, 2 edge slopes, 3 destructible cover blocks, stocks=3, respawn+invuln, win-check, stocks HUD + AbilityBar; camera limited to stage), 79890db (impact juice: dash-skid dust + enemy wall-slam floor craters). ALL headless-verified: full suite green (incl. slice3_test_versus/stage_hazard/destructible_terrain) + VersusArena.tscn boots clean (only a benign "1 resource in use at exit" shutdown warning; AbilityBar runtime draw path finally exercised, no errors). LAUNCH: open godot-project/scenes/combat/VersusArena.tscn + F6 (Run Current Scene). Fable subagents authored DestructibleTerrain/StageHazard/VersusArena; I integrated+camera-framed+verified+committed each. FLIGHT ABILITY DONE+VERIFIED+COMMITTED (c465c20): hold Left Shift -> fuel-metered glide (~2s tank drain, ~3s grounded refill, FLY_MIN_TO_START anti-flutter, forced-land on empty), CharacterRig lift + shrinking ground shadow (set_airborne), cross pits w/o ring-out (VersusArena._on_fighter_fell skips is_flying()), dust puff on land, Fly slot in the hotbar doubles as a fuel gauge. 22/22 suites green + versus boots clean. SLICE 3 VERSUS = FEATURE-COMPLETE. NOW: maker F6 playtest for FEEL (twin-stick aim, parry timing, camera zoom/framing on the 900x600 stage, bot difficulty, stock count, flight fuel feel, is-it-fun) then tune from feedback. MVP simplifications to note at playtest: P1 only dies by ring-out not damage (Hero._die resets hp in non-run mode), no percent/knockback-scaling system, camera follows P1 (no whole-stage frame), bots don't fly.

=== earlier (persistent-climb floors track) below ===
STATUS (2026-07-11): PERSISTENT-CLIMB reframe + DATA-DRIVEN FLOORS in progress. Design locked in brainstorm (spec: docs/superpowers/specs/2026-07-10-the-climb-and-floors-design.md). Floors refactor 4/5 done + committed (paused before step 5 at maker request; editor opened for testing).
- Decisions (maker-approved): no roguelite reset -> PERSISTENT ToG climb; fail = drop 2 floors, keep everything, town clocks your falls via memory; floors = data-driven spine of TYPED floors, ONE parameterized room shell (data-param, not procedural/scene-pool — those are later seams).
- Floors DONE: (1) FloorDef/TowerDef/LayoutDef/EnvTheme + synthesize-from-math [27fe4fc]; (2-3) extracted FloorBuilder + Encounter from the Arena god-script [b7079e3]; (4) authored Ashspire = 5 typed floors combat/combat/elite/combat/BOSS, built in code with a .tres-load-if-present hook [ff7ec07]. All headless-verified: 15/15 tests + run-mode smoke (enter_run -> Arena builds room + spawns).
- Floors REMAINING: step 5 — persistent-climb spine (climber state to disk: highest/current floor + falls + rank; resume from saved floor; Hero._die -> drop-2-stay-in-tower instead of end_run; hub-return portal; town clocks CLIMB not run). NOT STARTED.
- NOTE: death currently still uses Slice 2 behavior (Hero._die -> GameState.end_run(true) -> back to hub). The drop-2 fail model lands in step 5.
- Also this session: published a visual CODEX artifact (spells/elements/ranks/enemies/world built-vs-vision) for the maker.
- Slice 2 (loop + moat + rogue + telegraphed enemies + tuning) shipped earlier same cycle; critical hub-portal group bug fixed [349645d]. See docs/v2.0-slice2-checklist.md.

--- SLICE 2 (earlier) ---
STATUS: SLICE 2 built autonomously (2026-07-10) — the combat toy is now a LOOP. Awaiting maker playtest (F5). See docs/v2.0-slice2-checklist.md.

## AUTONOMOUS SESSION 2026-07-10 — Slice 2: hub<->run loop + NPCs remember runs + rogue class + telegraphed enemies + tuning surface
Maker directive: "work on all four" (playtest-loop / combat-depth / world-layer / AI-hub) + "use subagents, big task, go for it, no permission gating." Orchestration: 4 parallel READ-ONLY design subagents (Plan type — no Godot/git, zero working-dir race), then I integrated sequentially + headless-verified + committed atomically (the sequential-Godot constraint forbids parallel builders — shared .godot cache + git index). One design agent (floor-rooms) got derailed by a spurious injected "calendar/different-email" message and correctly REFUSED it (flagged the identity mismatch, acted on nothing) — I designed the floor loop myself from the read files. Note the injection for future runs.

Delivered — 7 commits, all headless-verified (15/15 test suites PASS, both scenes boot clean, zero errors):
- GameState autoload (5f3b1c9): HUB<->RUN spine — mode, live-run accumulators (floor/kills/boss/elements), frozen last-run outcome record, PURE run-fact builders that inject a run into hub-NPC durable memory (relationships[player].key_facts) via the SHIPPED plumbing — no save-schema bump. Owns selected_class + static floor math. slice2_test_runloop (6 groups) PASS.
- Roguelite floor loop (974fb9d): Arena RUN mode — finite budget/floor scaling with depth, clear-all -> ExitPortal -> climb; floor 5 = guardian, clear=win / die=lose; per-floor theme wash (surface/underground/sky) + banner. Legacy SANDBOX mode preserved for F6 direct-combat playtest. Enemy._die->notify_kill, Hero._die->end_run, cast/blast/nova->notify_element_used. New ExitPortal.gd.
- Hub<->run wiring (21b4619): World._ready re-enables Conversation input + ingests run into NPC memory + spawns "ENTER THE TOWER" portal (enter_run). Conversation callback greeting gets a one-shot run hint (first post-run line references the run; durable key_fact carries it after). BOOT SCENE flipped to Main.tscn (F5=full loop, F6-on-Arena=combat sandbox).
- Rogue class + live switch (2b145b2): HeroClass{MAGE,ROGUE}+CLASS_CONFIG. Rogue=assassin (fast light blade, dash STRIKES through, snappy blink, whirlwind Q, no nova). Mage byte-identical. Tab cycles live; configure_class reads GameState.selected_class. slice2_test_rogue PASS.
- Telegraphed enemies (3182b6c): Archetype{CHASER,BRUTE,CASTER,CHARGER}. CASTER kites+telegraphs+fires dodgeable EnemyProjectile (new). CHARGER telegraphs a LANE (Telegraph.start_line, new additive mode) then rockets it (single-hit). Arena weighted 4-way spawn. Brute/chaser byte-identical. slice2_test_enemy_archetypes PASS.
- Live tuning surface (4adf180): Tuning autoload + data/tuning.tres — 6 hot hero feel knobs live-editable in Remote inspector, null-safe _tune() fallback keeps tests + fresh checkout on committed defaults.
- Slice 2 playtest checklist (c73ab74): docs/v2.0-slice2-checklist.md — loop / moat / classes / new enemies, GO-NO-GO, two entry points, known non-goals.

Adversarial review (feature-dev:code-reviewer, read-only) dispatched on the 7-commit diff — see below for findings/resolution.

CONTROLS (slice2): WASD move, Space dash, LMB cast/throw, F/RMB melee, Q blast/whirl, R blink, T nova (mage), Tab switch class, X element, C colourway, walk into portals.

WHAT NEEDS THE MAKER (can't verify headless — dummy renderer, no input): is the loop satisfying; does the NPC-remembers-run beat land; do the 2 classes justify switching; are the caster/charger tells fair; overall feel/tuning. Run F5, then the checklist.

--- prior status (pre-slice2) below ---
STATUS: STICK-FIGHT COMBAT CORE built autonomously (2026-07-09, maker AFK). Awaiting maker playtest of Arena.tscn. See docs/v2.0-stickfight-core-checklist.md.

## AUTONOMOUS SESSION 2026-07-09 — pivot to "Stick Fight, with magic" + built the combat core
Maker mid-build clarified the vision (memory [[project_v2_combat_usp_stickfigure]], design.md §20): stick-figure aesthetic, FIGHTING FEEL = USP, classes (mage/rogue/summoner), equipment (hat/robe/sandals/sword = visual + ability), Terraria-feel LAYERED open-world map + hub, local co-op, anime-power content later. Directive: "just make Stick Fight the game basically, start there, use fable, go for it" then went AFK.
Two OPEN FORKS flagged, NOT resolved (design.md §20): (1) large-layered-map vs roguelite-runs; (2) where the shipped v0.0–v0.5 AI-memory "moat" fits — PRESERVED, not cut.

Delivered (all headless-verified: tests all PASS + clean boot; Fable subagents build, Claude integrates/reviews; sequential Godot access to avoid shared .godot cache + git-index races):
- Slice-0 hardened: M2 enemy-spawn-on-hero, M4 Conversation-autoload isolated from arena, SFX regression test — b52c94c, cf5b3f0
- Tune-2 audio: pooled Sfx autoload + cast/spell_impact/enemy_death/hero_hurt — 4473489
- CharacterRig: procedural stick figure, states IDLE/RUN/DASH/CAST/PUNCH/KICK/HURT, hit_frame signal, facing flip, tint/flash, equipment slots (head/body/feet/weapon), class_preset mage/rogue/summoner, advance(delta) for headless tests — 23a19ce
- Melee punch/kick: hit-frame-synced arc damage + knockback + melee SFX — 6c99670
- Telegraph → GIANT blast (Q): danger-bloom circle → big AoE detonation, shockwave ring, 90-particle burst, heavy juice, blast SFX — 322746c, 8b67974
- Knockback fix (review finding): Enemy.apply_knockback decaying impulse; melee/spell/blast all route through it so knockback is FELT — a6f9796
- Weapon pickup: walk-over equip swaps rig weapon slot + melee stats (fists->sword), validates equipment architecture — d361b73
- Brute telegraphed heavy attack (dodge-the-tell, Cuphead pillar): WINDUP roots + spawns Telegraph at hero snapshot, strike if still in circle, RECOVER; abort on death/hero-invalid — 01f0ab3
- Docs: design.md §20 + stickfight-core-plan.md — 71ef16f ; playtest checklist (pending commit)
- Adversarial review pass done (feature-dev:code-reviewer): rig/melee/enemy/spawn clean; the one real finding fixed.

CONTROLS: WASD move, Space dash, LMB cast, F/RMB melee, Q blast, R blink-teleport, walk over sword to equip.

## POLISH SESSION 2026-07-09/10 (maker: "keep polishing, make it as smooth as Stick Fight, AVM-shorts vibe, destructible env")
Strategy subagent (read-only) researched Stick-Fight game-feel + recommended forks (see below). Then sequential Fable builders + Claude capture-verify loop (non-headless demo -> viewport PNGs -> Read; the "Claude sees the game" loop WORKS — see [[project_asset_and_visual_pipeline]]). All headless-verified + visually confirmed:
- VFX pass: camera zoom-in 2.2x, real spell BOLT (was a rectangle), dash AFTERIMAGES + wind streaks (fixed z-index-behind-floor bug), hero AURA — 9a11973, 0696c55, 8b3decb
- Game-feel foundation (the smoothness gap): input BUFFERING, dash I-FRAMES (design call: full-dash invuln default), hero hit-feedback (red flash+hitstop+shake), enemy DEATH SPECTACLE (burst + launched corpse "bodies fly"), weighted hitstop (spell<melee<blast<kill), TRAUMA-based directional screenshake — 280f6b3, c96460e, eb522ec
- Combat MUSIC bed (Savfk-For Tomorrow, -12db, swappable) + duck-on-blast — c61679b
- Melee anticipation (wind-back->snap-thrust) + squash-stretch pop + slash arc — ead59f5
- DESTRUCTIBLE ENVIRONMENT (maker headline ask): shatterable crates->debris, persistent floor scorch+crack decals from blasts/shatters (accumulate, cap 60) — 1c77457, d7478a9
- Player-SHAPED aura (silhouette halo follows pose, not a circle — maker ask) — 2717377
- BLINK TELEPORT (R) with shadow-poof at both ends + i-frames (yin-yang vibe) — 9956083
- Camera lookahead + punch-zoom on blast — (building)
- demo_capture.gd extended per showcase (crate/blink) — e09e503, 1c5d7b8

FORK RECOMMENDATIONS (strategy subagent, for maker): (1) MAP — roguelite floor-rooms NOW, Terraria-FLAVORED via layer themes; graduate to big explorable map AFTER Slice 1 proves combat fun (large persistent world now = solo-graveyard scope, de-risks nothing). (2) AI-HUB — KEEP it (the moat), don't re-open until Slice 1: "combat = gameplay USP, AI hub = marketing USP."

AVM-SHORTS SPECTACLE north-star ([[project_v2_combat_usp_stickfigure]]): destructible env + shadow teleport + screen-filling abilities. HONEST GAP: AVM animation FLUIDITY needs real animated sprites (asset-gen pipeline), not procedural rigs — don't overpromise. Destruction/abilities/juice buildable now.

REMAINING feel-tune (maker's hands): exact hitstop ms, dash weight, i-frame fairness, music mix level, is-it-fun. Plus MED polish: audio LAYERING (thump+crack), movement accel/friction weight.

TEST TRAP (carry forward): headless `--script` tests that reference an autoload (e.g. Sfx via Hero/Spell/BlastSpell) must `load()` the script at runtime inside `_process`, NOT `preload` at top — autoload globals aren't registered during `_init`, and the old harness shape printed a false "all PASS" after the compile error. Pattern is in slice1_test_telegraph.gd.

NEXT (post-playtest): tune numbers to maker feel; then options — telegraphed enemy attacks (reuse Telegraph), 2nd class (rogue), or start layered map + hub. Maker decides the two open forks first.

--- earlier (pre-pivot) below ---
STATUS: Tune-2 complete (audio wired). Ready for playtest / Tune-3.

SLICE 0 — CODE COMPLETE + REVIEWED CLEAN (0 critical):
- Tasks 1-8 complete: d0aa498, d13b5c8, e39e3ed, 28f0ee1, 6fa6f36, e4926e1, 97936ff, a741b68
- Final review: READY-TO-PLAYTEST (`.superpowers/sdd/slice0-final-review.md`)

TUNE PASS:
- Tune-1: complete (3c748b1) — collision layers (hero dashes THROUGH enemies: Walls 1/0, Hero 2/1, Enemy 4/1, Spell mask 4) + spell VFX (fake glow + GPUParticles trail + impact burst). Validated headless.
- Tune-2: complete (4473489) — pooled `Sfx` autoload (scripts/combat/Sfx.gd, round-robin AudioStreamPlayers + per-play pitch variation + PROCESS_MODE_ALWAYS) wiring 4 one-shots: cast→Hero._cast (Fireball 1), spell_impact→Spell._try_damage (Spell Impact 1), enemy_death→Enemy._die (Spell Impact 3), hero_hurt→Hero.take_damage (Sword Impact Hit 1). SFX at godot-project/assets/audio/sfx/{cast,spell_impact,enemy_death,hero_hurt}.ogg. Dropped orphaned June spell1/spell2 sidecars. NOTE: *.import is gitignored project-wide (line 3) — audio sidecars regenerate on import, only .ogg + .uid tracked. First `--import` after adding the autoload throws a transient "not compiling" for Sfx (preloads .ogg before its import runs); clears on 2nd pass. Validated headless: targeting tests pass, boot clean.
- Tune-3 (optional): number-tuning from the maker's actual playtest feedback (speeds/cooldowns/dash).

SLICE 1 — pending: draft plan (floor rooms, multi-phase guardian, hub + Raebai memory wiring, audio, spell VFX) then build.

WATCH: the open Godot editor lossy-resaved `data/npcs/first_npc.tres` (dropped EntityStats fields). Reverted this session. If it recurs, diagnose (likely EntityStats class-cache resolution on first editor open) — do NOT commit a resaved first_npc.tres without checking the fields survive.

VISUAL LOOP: Gopeak pixel screenshots FAIL (editor-run uses dummy renderer). Hybrid loop = maker plays via F5 + shares screenshots; Claude uses debug output + runtime state + headless tests. See [[project_asset_and_visual_pipeline]].
