class_name VersusArena
extends Node2D
## Playable versus arena (Slice 3): P1 — the Hero — vs BOT_COUNT AI bots on a
## floating platform ringed by PIT hazards, Smash/Brawlhalla-style. Knock a
## fighter off the platform into a pit and it rings out: -1 stock, respawn at
## its own spawn point with a brief invuln window, eliminated at 0 stocks.
## Destructible cover blocks stand on the platform; SLOPE strips just inside
## the left/right rims slide anyone loitering there toward the nearest pit.
## Everything is built in _ready, in code — no .tscn (the Arena.gd /
## FloorBuilder programmatic-stage idiom).
##
## Ring-out flow: each PIT's fighter_fell routes to _on_fighter_fell, which
## looks the body up in _registry (instance_id -> stocks/spawn/invuln), burns
## a stock, then respawns or eliminates. RESPAWN_INVULN is belt-and-suspenders
## on top of the pit's own per-body dedup: moving a fighter to its spawn
## clears that dedup, so the invuln window is what stops anything re-reporting
## the same fighter from burning a second stock in the same beat.

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
## The tower arena — where the boss lives. Reached by PATH (see _enter_boss_fight).
const ARENA_SCENE: String = "res://scenes/combat/Arena.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/Arena.gd"
## Where backing out of the sandbox lands. Mirrors `GameState.TITLE_SCENE`, written
## as a literal for the same reason every other scene here is: this script is
## load()ed by headless harnesses that have no autoloads registered.
const TITLE_SCENE: String = "res://scenes/ui/Lobby.tscn"

## -- Match rules -----------------------------------------------------------
## A cohesive, realistic, FUN battleground (maker: "the map needs to look way
## better, more REALISTIC and actually FUN ... platforms that feel intentional +
## connected to the ground, not disconnected abstract blocks"). ONE connected rock
## landscape — a broad fight floor rising through jumpable stairs to a right bluff,
## a left mound, and rooted broken-stone ruins over the middle. Everything is SOLID
## (no fall-through-into-the-void): ring-out only off the far L/R edges, so nobody
## is unfairly "sent out of the map" and the bots can't fall through and hand an
## early win. Destruction lives in the cover + craters, not the load-bearing floor.
const STAGE_SIZE: Vector2 = Vector2(2000, 1000)
const GROUND_TOP: float = 780.0    # y of the main walkable ground surface
## THE PAINTED WORLD — the rect `Atmosphere` fills, and therefore the only region the
## camera may show. Outside it there is no sky, no parallax and no rim: just the
## viewport clear colour. `_frame_x` clamps against these, and `_build_atmosphere`
## builds from them, so the two can never disagree again — they were two hand-written
## copies of the same rect, and the camera's copy was `STAGE_SIZE` (which is the
## COLLISION extent, not the painted one).
const BACKDROP_ORIGIN: Vector2 = Vector2(-400.0, -420.0)
const BACKDROP_GROWTH: Vector2 = Vector2(800.0, 900.0)
const BACKDROP_X0: float = BACKDROP_ORIGIN.x
const BACKDROP_X1: float = BACKDROP_ORIGIN.x + STAGE_SIZE.x + BACKDROP_GROWTH.x
## THE TERRAIN RIM. Restated from this file's own load-bearing note above: the outer
## extent of every stage variant is x 40..1965, and `PROBE_TERRAIN_X0/X1` are copies of
## it. Past the rim the backdrop is still painted but there is no ground.
const STAGE_RIM_X0: float = 40.0
const STAGE_RIM_X1: float = 1965.0
## How much past-the-rim emptiness the shot may show before the camera stops following.
## This is the ONE knob on the trade the old constant resolved badly: hold the camera
## in and the fighters slide to the edge of the picture (the maker's complaint), let it
## out and the picture fills with nothing. 150 px is under a quarter of the frame at
## every zoom the showcase reaches, and it keeps a pair pinned against the left wall at
## roughly x=141 of 640 instead of x=38.
const STAGE_RIM_SLACK: float = 150.0
const STOCKS: int = 3
const RESPAWN_INVULN: float = 0.8

## Connected, solid TERRACES forming one realistic rock landmass (drawn by
## ArenaTerrain, collided as permanent StaticBody2Ds). Ordered low-surface -> high
## so the terrain draws back-to-front; overlaps turn the risers into jumpable
## stairs. Each: the walkable SURFACE y + the x span.
const TERRACES: Array[Dictionary] = [
	{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},  # main ground — the fight floor
	{"surface_y": 700.0, "x0": 40.0,   "x1": 250.0},   # left mound
	{"surface_y": 690.0, "x0": 1330.0, "x1": 1580.0},  # right rise — step 1
	{"surface_y": 600.0, "x0": 1540.0, "x1": 1760.0},  # right rise — step 2
	{"surface_y": 510.0, "x0": 1700.0, "x1": 1965.0},  # right bluff — high ground
]
const TERRACE_DEPTH: float = 320.0  # each collider extends this far down (solid rock)

## ══ THREE STAGES, NOT ONE ══════════════════════════════════════════════════
## Maker: *"I think the maps need some more variety as well"*.
##
## What varied per bout before this: the SKY. `_stage_theme` rolls a `GameState.BIOMES`
## row and every consumer of it is `sky_top` / `sky_bottom` / `silhouette_far` /
## `silhouette_near` / `accent` plus a `PostProcess` wash. The BIOMES table carries
## `{name, wash, accent, light}` and is physically incapable of holding a coordinate,
## so ten "different" stages were ten repaints of one shape.
##
## ⚠ AND THE SHAPE WAS ILLEGAL. Run `FloorGen.can_step` over `TERRACES` and it fails
## THREE TIMES: the right rise's steps are 90, 90 and 90 px against that file's own
## documented COMFORTABLE step of `STEP_MAX = 86`, derived from a 580 jump against
## 1500 gravity. So the shipped stage has three risers a body is not meant to be able
## to climb — which is half of *"these guys get stuck in the corner of a wall then
## destroyed"*, since a bot pressed into an unclimbable face has nowhere to go.
##
## Every variant below is checked against that rule by `slice_test_stage_variants.gd`,
## including the original, which is why the original's risers moved 90 -> 84.
##
## ⚠ WHAT MAY NOT VARY, AND WHY. Two facts are load-bearing far outside this file:
##   * THE MAIN FLOOR ROW — surface 780 (`GROUND_TOP`), x 40..1400 — is identical in
##     every variant. `BotMatch.FLOOR_CENTRE_X` is literally commented `(40 + 1400)/2`,
##     `SPAWN_Y` is derived from `GROUND_TOP - 17`, `COVER_X_MIN/MAX` are `40 + 32` and
##     `1400 - 32`, the camera clamps are `GROUND_TOP +/- 330/30`, and about
##     twenty-five capture tools frame against a flat 780 floor.
##   * THE OUTER EXTENT stays x 40..1965, because `PROBE_TERRAIN_X0/X1` are hand-copied
##     from it and the live probe files an anomaly for any body outside.
## Vary the furniture and the high ground; leave the fight floor and the rim alone.
const STAGE_TERRACES: Array[Array] = [
	# 0 — THE ORIGINAL. Ground, a left mound, and a staircase up to a right bluff.
	# Risers 90/90/90 -> 84/84/84 so the climb is legal; the shape is unchanged.
	[
		{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},
		{"surface_y": 700.0, "x0": 40.0,   "x1": 250.0},
		{"surface_y": 696.0, "x0": 1330.0, "x1": 1580.0},
		{"surface_y": 612.0, "x0": 1540.0, "x1": 1760.0},
		{"surface_y": 528.0, "x0": 1700.0, "x1": 1965.0},
	],
	# 1 — MIRRORED VALLEY. High ground on BOTH sides and nothing in the middle, so the
	# fight is fought across a dip instead of uphill in one direction. The single
	# biggest change to how a bout reads, because it removes the stage's handedness.
	[
		{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},
		{"surface_y": 696.0, "x0": 40.0,   "x1": 330.0},
		{"surface_y": 696.0, "x0": 1330.0, "x1": 1640.0},
		{"surface_y": 612.0, "x0": 1640.0, "x1": 1965.0},
	],
	# 2 — THE SHELF. One long mid-height terrace over the right half of the floor, with
	# the far end open — a lane you can be chased along, and the only variant where the
	# high ground is a corridor rather than a summit.
	#
	# ⚠ THE SHELF STARTED AT x 980 AND SWALLOWED THE RIGHT-HAND SPAWN. A terrace is not
	# a surface — `_make_terrace` grows it DOWNWARD by `TERRACE_DEPTH` (320), so this row
	# was one solid StaticBody2D spanning x 980..1560, y 700..1020. Every mode that uses
	# this stage puts the right fighter inside that box:
	#
	#     BotMatch   (FLOOR_CENTRE_X + SPAWN_SPREAD, SPAWN_Y) = (1000, 760)
	#     duel       DUEL_SPAWN_BOT                           = (1120, 716)
	#     showcase   SHOWCASE_SPAWN_B                         = (1080, 716)
	#
	# so on the ~1 bout in 3 that rolled variant 2, a fighter spawned in solid rock and
	# was either shoved sideways off its mirrored footing or left grinding against the
	# face with `is_on_wall()` true and `walk_x` zeroed. That is the maker's "they both
	# lag in the box"; the crates were a separate complaint, fixed separately.
	#
	# x0 980 -> 1180 clears the furthest-right spawn (1120) by 60 px. The riser from the
	# 780 floor stays 80 (under FloorGen's comfortable 86) and the shelf still overlaps
	# the fight floor out to 1400, so it is the same chase corridor, 380 px of it.
	[
		{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},
		{"surface_y": 712.0, "x0": 40.0,   "x1": 200.0},
		{"surface_y": 700.0, "x0": 1180.0, "x1": 1560.0},
		{"surface_y": 620.0, "x0": 1560.0, "x1": 1965.0},
	],
]
## Cover, ruins and breakables, per variant — same index as `STAGE_TERRACES`. Kept
## beside the terraces rather than rolled separately, because cover that lands under a
## ledge on one variant and in the open on another is the difference between a stage
## and a shuffled stage.
##
## ⚠ EMPTY ON THE MAKER'S RULING, 2026-08-11, watching a bot fight: *"they start
## behind the crate then break the crate and walk into them"* → *"remove the crates
## or make them start on the platforms above"*.
##
## THE KEEP-OUT WAS NEVER THE PROBLEM AND WIDENING IT WOULD NOT HAVE FIXED THIS.
## `cover_x_clear_of` only guarantees `block_w * 0.5 + SPAWN_FOOTPRINT_HALF` = 54 px
## of clearance, which is precisely "not overlapping" and nowhere near "out of the
## way": the fighters spawn at 440 / 1000 and the blocks sat at 470 / 1180, so every
## single bout opened with both fighters chewing through a crate before they could
## reach each other. That is dead air at the exact moment the fight should start,
## and it is the first thing anyone watching sees.
##
## The other option on the table was moving the fighters up onto the terraces. That
## was declined as the riskier of the two: `BotMatch.SPAWN_Y`, the camera clamps,
## `PROBE_TERRAIN_X0/X1` and ~25 capture tools are all derived from the main floor
## row, and `slice_test_stage_variants` pins that row precisely because moving it
## breaks them silently rather than loudly.
##
## ⚠ NOT DELETED — EMPTIED. The builder, the keep-out, `cover_x_clear_of` and its
## tests all still work; re-authoring a row here brings cover straight back. If it
## does come back, put it OUTSIDE the 440..1000 spawn corridor (the flanks or the
## upper terraces), which is what `slice_test_stage_variants.cover_never_gates_the_
## opening` now enforces.
const STAGE_COVER: Array[Array] = [
	[],
	[],
	[],
]
## Which stage this bout is on. `-1` rolls; the suite and the capture tools pin it.
static var stage_layout: int = -1
## What the roll landed on. Read by the suite; never written from outside.
static var stage_layout_rolled: int = 0

## Rooted broken-stone ruins filling the vertical space over the ground (RuinPlatform
## draws support struts beneath so they read connected, not floating).
## ⚠ BOTH OF THESE WERE AUTHORED ABOVE THE JUMP CEILING AND NOBODY COULD REACH THEM.
## Maker, playing: "can brawler not jump the ledge whats happening?"
##
## The ground surface is 780 and a jump clears `740^2 / (2*2600)` = **105.3 px**
## (`TuningConfig.jump_velocity` / `gravity_rise` — NOT the dead consts in `Hero.gd`).
## The two ruins sat at:
##
##   RUINS[0]  centre 672, h 22 -> surface 661 -> rise from ground = **119 px**
##   RUINS[1]  centre 588, h 22 -> surface 577 -> rise from the breakable = **112 px**
##
## Both over the ceiling. Brawler is the ONLY class that could touch the first, and
## only by spending its air jump (`CLASS_CONFIG["air_jumps"] = 1`, +33 px) — which is
## exactly why it looked like a Brawler problem rather than a level problem. Every
## other class in the roster simply could not get up there, so two thirds of the
## stage's vertical space was decoration.
##
## Re-authored as a CLIMB with every rise inside `FloorGen.STEP_MAX` (86), the same
## budget the tower holds itself to and the same band as the terrace risers (68-84):
##
##   ground 780 -> breakable 700   rise 80,  jump straight up
##   breakable  -> RUINS[1] 616    rise 84,  40 px horizontal gap
##   ground 780 -> RUINS[0] 696    rise 84,  centre-left, its own way up
##
## The horizontal gap matters as much as the rise and is the half that is easy to get
## wrong: a RISING jump only carries ~83.6 px forward before it drops below the
## landing height, so the 40 px between the breakable's right edge (925) and RUINS[1]'s
## left edge (965) is inside the budget with room to spare.
## ⚠ EMPTY, AND DELIBERATELY SO. Maker: "make all three platforms destroyable".
## All three moved into `BREAKABLE_PLATFORMS` below. Kept as a declared const rather
## than deleted because `_build_terrain` still iterates it and a stage variant may
## want a permanent ledge again later; an empty array is the honest way to say "there
## are none right now" without deleting the seam.
const RUINS: Array[Dictionary] = []

## Ring-out ONLY off the far L/R edges (no void beneath the solid terrain).
const BLAST_ZONES: Array[Dictionary] = [
	{"center": Vector2(-180.0, 480.0), "size": Vector2(360.0, 1800.0)},  # off far left
	{"center": Vector2(2200.0, 480.0), "size": Vector2(360.0, 1800.0)},  # off far right
]
## The reference point the stage is laid out around (the human duellist's side).
const P1_SPAWN: Vector2 = Vector2(320.0, 716.0)
## Destructible cover sitting on the main ground (64px blocks; centre = surface - 32).
const COVER_POINTS: Array[Vector2] = [Vector2(470.0, GROUND_TOP - 32.0), Vector2(1180.0, GROUND_TOP - 32.0)]

## ══ NOBODY MAY START THE FIGHT STANDING INSIDE A BLOCK ══════════════════════
## Maker: *"when bot fight happen they start within the boxes which is a wierd bug"*.
## They were right, and the arithmetic is exact: `COVER_POINTS[0]` is x 470 and a
## `DestructibleTerrain` is 64 px wide, so the left block spans **438..502** — while
## `BotMatch` mirrors its two fighters about the real floor centre at 720 +/- 280,
## which puts the LEFT fighter at **440**. Two pixels inside the cover. The right
## pair (spawn 1000, block 1148..1212) happened to miss, which is why only one
## fighter ever looked wrong.
##
## Nothing reconciled the two because the stage authors its cover in `_ready` and
## `BotMatch` moves the fighters AFTERWARDS — the two facts never met in one place.
##
## ⚠ FIXED AT THE COVER, NOT AT THE SPAWN, and deliberately. The 560 px opening gap
## is a documented duel constant that the clips were framed around, and shoving a
## fighter sideways would break the "MIRRORED FOOTING" the duel spends a paragraph
## guaranteeing. A block is scenery; moving it 24 px costs nothing and keeps the
## cover. This also survives `reset_free_stage`, which rebuilds the cover — a
## spawn-side fix would have to be re-applied there by hand.
##
## Half the width of a body plus the air it wants around it. A fighter's collider is
## ~18 px wide, so 22 leaves a visible gap rather than a touching seam.
const SPAWN_FOOTPRINT_HALF: float = 22.0
## The main fight floor is `TERRACES[0]`, x 40..1400. A displaced block stays on it.
const COVER_X_MIN: float = 72.0     # 40 + half a 64 px block
const COVER_X_MAX: float = 1368.0   # 1400 - half a 64 px block

## WHERE BODIES ACTUALLY STAND, for the keep-out above. Empty means "ask the stage"
## (see `_spawn_keepout`); `BotMatch` writes its own mirrored pair here before
## instantiating the scene, exactly like every other showcase static, because it is
## the only thing that knows it will re-seat the fighters at 440 / 1000.
static var spawn_keepout_x: Array[float] = []
## One breakable + regenerating lane between the ground and the ruins.
## ⚠ 700 -> 711, i.e. surface 689 -> 700. It was a 91 px rise from the ground: under
## the 105 px jump ceiling so a human could just make it, but OVER `FloorGen.STEP_MAX`
## (86), which is the budget every other surface in the game is authored to. It is the
## first rung of the climb described on RUINS above, so it is the one rung that must
## not be marginal.
## ALL THREE LEDGES, AND ALL THREE BREAK. Maker: "make all three platforms
## destroyable". A permanent ledge is a place to camp; a breakable one is a decision,
## and it is the reason a cornered fighter can take the floor out from under whoever
## is standing on it.
##
## ⚠ THE HEIGHTS ARE BOUNDED BY THE JUMP, NOT BY TASTE. Ground is 780 and a jump
## clears `740^2 / (2*2600)` = **105.3 px**, so a surface above ~686 cannot be reached
## from the ground at all — that is exactly how RUINS[0] came to sit at 661 and be
## touchable only by a Brawler spending its air jump.
##
## Maker: "the left platform is too low", then: **"left platform to match the far-right
## height"**. It is now 616 — the same surface as the right ledge, exactly as asked.
##
## ⚠ AND IT TOOK THE STEPPING STONE THE PARAGRAPH ABOVE DEMANDED, NOT A BIGGER NUMBER.
## 616 is a 164 px rise from the 780 ground against a 105.3 px ceiling, so as a
## ground-reachable ledge it would have been the RUINS[0] mistake for the second time
## — an authored surface nobody can touch. What makes it legal is that it does not
## have to be reached from the ground: the MID platform already sits between the two
## high ledges, so the left is climbed the same way the right always was.
##
## THE STAGE IS NOW SYMMETRIC, which is the actual win here. One mid platform at 700
## feeding two ledges at 616, one either side:
##
##     ground 780 -> mid 700   rise 80   (both sides share this rung)
##     mid 700 -> right 616    rise 84, gap 40   (unchanged)
##     mid 700 -> left  616    rise 84, gap 60   (new, and the mirror of it)
##
## Every number checked against the live constants, not the dead ones: the ceiling is
## `740^2 / (2*2600)` = 105.3 from `TuningConfig`, risers are under `FloorGen.STEP_MAX`
## (86) and both gaps are under the ~83.6 px rising-jump reach. `slice_test_stage_variants`
## now PROVES this rather than leaving it to a comment — see `breakable_platforms_are_climbable`,
## which is the guard this table has never had and which is exactly why RUINS[0] shipped broken.
##
## ⚠ IF YOU MOVE THE MID PLATFORM, YOU STRAND BOTH LEDGES. It is load-bearing for the
## whole stage now, not just the right-hand climb.
const BREAKABLE_PLATFORMS: Array[Dictionary] = [
	{"center": Vector2(600.0, 627.0),  "size": Vector2(190.0, 22.0)},  # left,  616 — rise 84 from mid
	{"center": Vector2(840.0, 711.0),  "size": Vector2(170.0, 22.0)},  # mid,   700 — rise 80 from ground
	{"center": Vector2(1050.0, 627.0), "size": Vector2(170.0, 22.0)},  # right, 616 — rise 84 from mid
]

const RESPAWN_POOF_START: Color = Color(0.75, 0.85, 1.0, 0.9)
const RESPAWN_POOF_END: Color = Color(0.75, 0.85, 1.0, 0.0)

## ------------------------------------------------------------------ SHOWCASE
## SHOWCASE MODE — two BOT-DRIVEN HEROES fighting each other on this stage,
## instead of P1 plus a roster of Enemy trash. Built for the clip capture
## (`tools/bot_clip_capture.gd`) and playable from F5 by setting the two statics
## before the scene loads.
##
## It exists because the interesting fight is class-vs-class: opposed elements are
## what make the reaction matrix fire (a FIRE beam shatters an ICE wall; HOLY
## `banish`es SHADOW; LIGHTNING through a frost field `supercharge`s), and none of
## that can happen between a hero and a melee trash mob.
##
## ⚠ NOTHING HERE HELPS A BOT. Both fighters get the same stock `BotController` +
## `BotBrain` + `BotProfile` the game ships, at the same difficulty, seeing only
## what a human sees. A staged fight with rigged bots is worthless for finding
## bugs and dishonest as marketing, so the only thing this mode changes is WHO is
## on the stage — never what they know or how hard they hit.
##
## Statics rather than exports: the capture tool loads this scene by path and has
## no instance to configure before `_ready` runs.
static var showcase_a: int = -1        # Hero.HeroClass, or -1 for the normal arena
static var showcase_b: int = -1
static var showcase_difficulty: int = 2
## Hand the showcase camera to `ClipDirector` instead of the plain pair-framing
## tracker below. OFF by default and deliberately so: the existing pair camera is
## what `tools/bot_clip_capture.gd` and `tools/slice3_test_versus.gd` were measured
## against, and silently changing the framing under them would be a regression
## wearing an improvement's clothes. `tools/directed_clip_capture.gd` and
## `scenes/combat/BotMatch.tscn` opt in.
static var showcase_directed: bool = false
## How many HP each showcase fighter carries. A STATIC so a clip tool can shorten a
## bout (fights that end are clips; fights that do not are footage) without editing
## the constant every other mode reads.
static var showcase_hp_override: int = 0
## Which biome this bout is dressed in (index into `GameState.BIOMES`), or -1 to roll.
## A static for the same reason every other knob here is one: `BotMatch` writes them
## onto the SCRIPT before instantiating the scene, so the value is present before
## `_ready` runs and there is no window in which a drawer sees a half-built stage.
static var stage_biome: int = -1
## What the roll actually landed on. Read by the suite and by anything that wants to
## report the stage — never written from outside.
static var stage_biome_rolled: int = 0
## Leave the Smash damage-% + ring-out model ON for a showcase? TRUE is the stage's
## own model and the shipped behaviour.
##
## A clip tool turns it OFF, and the reason is measured rather than aesthetic: under
## the ring-out model a hit accumulates `damage_pct` instead of draining HP, so two
## bot heroes fought for 65 game-seconds at 219% and 642% accumulated damage without
## either one ever going down — which produces a clip with no ending. A clip needs a
## DECISIVE fight; HP death is the model that reliably provides one.
static var showcase_ringout: bool = true

## --------------------------------------------------------------- FREE PLAY
## FREE PLAY — the stage, you, and NOTHING ELSE.
##
## The maker's ask, verbatim: *"we need the ability for players to choose to just do
## no bots and play on the stage as well"*. No enemies, no waves, no timer, no run,
## no stocks. You drop in and you move, dash, jump, cast all three spells, throw the
## ult, blink, nova, parry, break the cover, ride the terraces, and find out how the
## thing feels.
##
## IT IS ALSO THE ONBOARDING SURFACE. The audit's fourth finding is that this game
## has ZERO onboarding — a player's first contact with the controls is a floor of
## enemies. A room where nothing can kill you is where you learn the verbs, so free
## play prints its controls on the wall and keeps a live hint line.
##
## ⚠ NOT A DEBUG MODE, and it must not become one. `tools/director/Director.gd` (F1)
## already does class-switching and spell-granting far better than this ever will,
## and free play deliberately does NOT duplicate it — it OFFERS it (the pause menu
## has a Director row when the tools script is present) and otherwise stands alone,
## because the director is gated out of release builds and free play is a SHIPPING
## feature.
##
## Everything reconfigurable without a restart: class (live, via `configure_class`),
## a training dummy to hit, ring-out on/off, and the stage rebuilt from scratch. The
## whole point of this mode is to change one thing and immediately feel it, and a
## scene reload between every comparison would make that impossible.
static var free_play: bool = false
## How many practice dummies to stand up. 0 = a genuinely empty stage.
static var free_dummies: int = 0
## Where the free-play hero lands: middle of the main ground, room either side.
const FREE_SPAWN: Vector2 = Vector2(700.0, 716.0)
## Free play gives the hero back its OWN camera (the pair-framing camera exists to
## keep two fighters in shot; with one fighter it is just a worse follow cam).
const FREE_HP: int = 400
## Practice dummies stand here, spaced along the ground so one of them is always in
## reach of the terraces and one is out in the open.
const FREE_DUMMY_POINTS: Array[Vector2] = [
	Vector2(1050.0, 716.0), Vector2(430.0, 716.0), Vector2(1420.0, 626.0),
]
## A dummy is a hero body with no controller, no faction hostility and a big HP
## pool: something to hit that hits back with nothing. Deliberately a HERO and not
## an `Enemy` — the point is to feel your own spells land on a body the same size
## and shape as the one you will fight, and `Enemy` brings AI, telegraphs and a
## death spectacle that belong to the tower, not to a practice range.
const FREE_DUMMY_HP: int = 9999
## Free play's fixed framing. Close enough to read the rig's wind-up (this is where
## the maker judges feel) and wide enough to see a terrace, a cover block and where
## the next platform is.
##
## ⚠ MEASURED AGAINST THE BASE VIEWPORT, NOT THE WINDOW. This project's stretch
## settings give a base viewport of 683x384, so a zoom of 1.0 shows 683 world pixels
## — a third of this 2000 px stage, with the hero's feet under the hotbar. The first
## pass used 1.05 for exactly the "reads the rig clearly" reason and produced a shot
## in which the ground was off the bottom edge. 0.55 shows ~1240 px of stage.
const FREE_ZOOM: float = 0.55
## How far above the hero the eye sits, so the floor falls in the lower third
## instead of the frame being half underground.
const FREE_EYE_LIFT: float = 90.0

## -------------------------------------------------------------------- DUEL
## DUEL MODE — the maker, with their own hands, against ONE bot hero.
##
## The showcase above is two bots fighting for a camera. This is the thing that
## was actually asked for: "I want to fight a bot, and it can learn from me, and
## we can find bugs together." Same stage, same bot stack, same difficulty table
## — the only difference is that fighter A has no controller and therefore reads
## the real `Input`, exactly as it does in the tower.
##
## STATICS, and they SURVIVE A SCENE RELOAD. Every knob below (difficulty, the
## bot's class, whether it is learning) is changed by reloading the scene, so
## they have to outlive the node — a member would reset to its default on the
## first difficulty change and the maker would never be able to leave Normal.
##
## ⚠ THE DUEL IS NOW THE ONLY MODE. The five-bot practice arena was removed at
## maker request ("remove that group battle"), so entering this scene drops you
## straight into the 1v1. `duel_human` is kept because the sim/smoke tools set it,
## but it no longer decides anything: `_is_duel()` is simply "not a showcase".
static var duel_human: bool = true
## The bot's Hero.HeroClass. The human's class is whatever they picked (Tab, or
## GameState.selected_class), so the two are independent — you can fight your own
## class in a mirror or bring a Brawler to a Cryomancer.
static var duel_bot_class: int = 0
## Difficulty tier for the duel bot (BotProfile.Tier). Separate from
## GameState.enemy_difficulty, which drives the trash-mob arena: mixing them
## would mean changing the practice bots' difficulty every time you retuned your
## sparring partner.
## ⚠ EASY BY DEFAULT. Maker: "the bots are spamming and way too good to test with".
## A practice partner exists to let you find out what YOUR buttons do; one that wins
## is not a practice partner. The measured dial runs 89/11 between tier 0 and tier 3,
## so this is a real drop and not a nudge. Raise it live in the F1 Director the
## moment you want a fight instead of a lesson.
##
## (The spam itself is also addressed at the source: bots cast through
## `Hero._cast_signature`, so `GLOBAL_CAST_LOCKOUT` now paces them exactly as it
## paces the player.)
static var duel_difficulty: int = 0
## Is the bot allowed to learn from this fight? A toggle rather than a constant
## because "does it feel different when it has been studying me" is exactly the
## comparison the maker needs to be able to make in one click.
static var duel_learning: bool = true
## Draw the bot's current intent over its head. OFF by default — it is a
## debugging aid, and a permanent readout of what your opponent is about to do
## would wreck the fight it is meant to help you debug.
static var duel_show_intent: bool = false
## Show the learned profile of the human as an overlay. Also off by default; this
## is the "and see it" half of "resettable and inspectable".
static var duel_show_learning: bool = false

## Where the two duellists start. Far enough apart to have an approach, near
## enough that the first exchange happens inside one camera frame.
const DUEL_SPAWN_HUMAN: Vector2 = Vector2(560.0, 716.0)
const DUEL_SPAWN_BOT: Vector2 = Vector2(1120.0, 716.0)
## Both duellists are tanky enough that a fight lasts long enough to read — and
## it is applied to BOTH, so it is a match-length knob and never an advantage.
const DUEL_HP: int = 260
## The pair-framing camera is tighter for a played duel than for a clip: you need
## to read your own rig's wind-up, not just see both fighters somewhere in shot.
const DUEL_FRAME_MARGIN: float = 380.0
const DUEL_ZOOM_MIN: float = 0.72
const DUEL_ZOOM_MAX: float = 1.30
## Hold after a knockdown before the next round starts.
const DUEL_REMATCH_GRACE: float = 1.4

## ------------------------------------------------------------- OBSERVATION
## How long after the bot presses a kit slot a hit on the human still counts as
## THAT SLOT's hit. A window rather than a signal because `Hero` publishes no
## took-damage signal to hang an exact attribution on (only `health_changed`,
## which also fires on heals and respawns) — and because half the kit is a
## travelling projectile or a placed bombardment anyway, so "the damage arrives
## later" is the normal case, not the edge one.
##
## 1.1 s covers a bolt crossing the stage and a meteor's fall. Longer would start
## crediting the wrong spell in a busy exchange.
const CREDIT_WINDOW: float = 1.1
## After the bot whiffs, damage the human deals inside this window is filed as a
## PUNISH. Roughly one recovery animation.
const PUNISH_WINDOW: float = 1.3
## A threat this close to the human counts as "something is coming at you", which
## is the gate on filing a movement as a DODGE rather than as a stroll.
const DODGE_NOTICE_RADIUS: float = 190.0
## Minimum horizontal speed before a movement is a break rather than a shuffle.
const DODGE_SPEED: float = 120.0
## One dodge per this many seconds, so a single evasion is not filed sixty times.
const DODGE_DEBOUNCE: float = 0.7
## How often the learned record is flushed to disk during a fight. Also written
## on quit and on every round end; this is the belt-and-braces for a hard kill.
const LEARN_SAVE_PERIOD: float = 20.0

## ------------------------------------------------------------- LIVE PROBE
## PLAYING THE GAME IS A BUG HUNT. The headless sim's detectors are pure
## predicates in `BotSimProbe`; the duel runs the same ones over the same frames
## the maker is playing, and writes the same machine-readable report. Loaded BY
## PATH and guarded, the `_attach_bot` idiom — a missing tools script must never
## stop the maker from playing.
const PROBE_SCRIPT: String = "res://tools/bot_sim_probe.gd"
const LIVE_REPORT_DIR: String = "user://bot_sim_live"
## THE FLOOR LINE FOR A PLAYED ARENA, and it is not GROUND_TOP.
##
## `GROUND_TOP` is a walkable SURFACE; the terrain colliders extend TERRACE_DEPTH
## below it as solid rock. So "below the floor" here means below the bottom of
## the rock — anything above that is either standing on a terrace or inside one,
## and only the second is a bug the maker can act on.
const PROBE_FLOOR_Y: float = GROUND_TOP + TERRACE_DEPTH
## ...and it only applies OVER the terrain. Off the left and right rims there is
## deliberately nothing to stand on — that is the ring-out, the whole point of
## the stage. Reporting a legitimate knock-off as "fell through the floor" is
## precisely the false positive the headless run produced 329 of.
const PROBE_TERRAIN_X0: float = 40.0
const PROBE_TERRAIN_X1: float = 1965.0
## Collapse identical findings inside this window into one row with a count. The
## detectors run per frame, so without this a single one-second event is 60 rows
## and the report says nothing about how many DISTINCT things went wrong.
const PROBE_DEDUP_WINDOW: float = 1.5

const BOT_CONTROLLER_SCRIPT: String = "res://scripts/combat/BotController.gd"
const BOT_BRAIN_SCRIPT: String = "res://scripts/combat/BotBrain.gd"
const BOT_PROFILE_SCRIPT: String = "res://scripts/combat/BotProfile.gd"
## Where the two showcase fighters start: far enough apart that they have to
## close, near enough that the opening exchange happens inside one camera frame.
const SHOWCASE_SPAWN_A: Vector2 = Vector2(520.0, 716.0)
const SHOWCASE_SPAWN_B: Vector2 = Vector2(1080.0, 716.0)
## Showcase fighters are tankier than a stock hero so the fight lasts long enough
## to show a kit off. Applied to BOTH equally — it is a clip-length knob, not an
## advantage.
const SHOWCASE_HP: int = 320
## Framing. MARGIN is the slack around the two fighters, so a beam or a meteor
## column has room to land inside the shot instead of half off it.
## MEASURED, NOT GUESSED. The first framing pass used a 900 px margin and allowed
## zoom down to 0.42, and the rendered frames showed two fighters the size of
## commas at opposite ends of an empty stage — technically "both in frame", and
## unwatchable. These numbers keep the pair large enough to read the rig, the
## staff and the damage percentage.
const SHOWCASE_FRAME_MARGIN: float = 480.0
const SHOWCASE_ZOOM_MIN: float = 0.60
const SHOWCASE_ZOOM_MAX: float = 1.25

## ── PORTRAIT (9:16) ─────────────────────────────────────────────────────────
## The three numbers above are sized for a 16:9 WIDTH and they are wrong in a tall
## frame — not by a little. Rendered and measured at 720x1280: the solve pinned to
## its 1.25 ceiling, and a rig that is `ClipDirector.RIG_WORLD_PX` = 31 world px
## tall came out 39 px in a 1280-tall frame. **Three percent of frame height.** On a
## phone that is not a fighter, it is a speck, and no amount of spectacle rescues a
## clip whose subjects cannot be seen.
##
## ⚠ THE UNCOMFORTABLE ARITHMETIC, STATED PLAINLY, BECAUSE IT BOUNDS WHAT IS
## POSSIBLE HERE. Two fighters spawn `BotMatch.SPAWN_SPREAD * 2` = 560 world px
## apart. Holding BOTH inside a 720 px-wide frame caps zoom at 720/560 = 1.28, which
## is the ceiling that produced the speck. **A two-shot of a fully-separated pair
## cannot be large in 9:16.** That is geometry, not tuning, and anything claiming to
## fix it by adjusting numbers is fixing something else.
##
## So these numbers buy the case that actually dominates a brawl — the pair CLOSED,
## which is where the hits and the casts are — and let the wide moments stay wide:
##   * the margin drops 480 -> 200. The old value reserves room for a beam or a
##     meteor column to land inside a 16:9 width; a tall frame already has that room
##     above the fighters, so paying for it horizontally as well is paying twice.
##   * the ceiling rises 1.25 -> 2.0. At a closed spread of ~100 px the solve now
##     reaches 720/300 -> clamped 2.0, and the rig reads ~62 px: still modest, but
##     legible, and roughly double what it was.
## At full separation the solve lands at 720/760 = 0.95 and the shot is exactly as
## wide as it is today, which is the graceful degradation rather than a cliff.
##
## The real remaining lever is DIRECTION, not framing: a vertical clip should follow
## the action and let a distant fighter leave frame, the way a two-shot in any other
## medium does. That is `ClipDirector` work and is deliberately not attempted here.
const SHOWCASE_FRAME_MARGIN_PORTRAIT: float = 200.0
const SHOWCASE_ZOOM_MAX_PORTRAIT: float = 2.0
## Where the ground line sits in a portrait frame, as a fraction of frame height.
## 0.80 puts the floor in the bottom fifth, which is what stops the sub-floor void
## from eating a third of the shot — see the note in `_update_showcase_camera`.
const PORTRAIT_GROUND_AT: float = 0.80

## ── FOLLOWING THE ACTION ─────────────────────────────────────────────────────
## The framing block above buys the CLOSED case and says plainly that it cannot buy
## the open one: two fighters 560 px apart cap zoom at 720/560 = 1.28, and a rig at
## that zoom is 3% of a 1280-tall frame. That is geometry, and no margin or ceiling
## crosses it. **The only way out is to stop insisting on a two-shot.**
##
## So in portrait the camera does what a two-shot does in every other medium: it
## holds both while they are together, and when they separate it goes with ONE of
## them and lets the other leave frame. Nothing about that is a compromise — a
## fighting-game clip that always contains both fighters is a wide shot, and a wide
## shot on a phone is a shot of nothing.
##
## The blend is continuous, not a cut. `follow` ramps 0 -> 1 across these two
## spreads, and both the focus point and the zoom target lerp on it, so there is no
## frame where the shot snaps.
const PORTRAIT_TWO_SHOT_COMFORT: float = 170.0
const PORTRAIT_TWO_SHOT_MAX: float = 430.0
## Where the single lands. At 2.8 the rig is ~87 px in a 1280-tall frame — under 7%,
## which is modest for a phone but is more than double the two-shot's 3% and shows a
## face-worth of detail. The visible world is 720/2.8 = 257 px wide, so the subject
## keeps a body-width of context on each side rather than filling the frame.
const PORTRAIT_FOLLOW_ZOOM: float = 2.8

## ⚠ WHO THE CAMERA GOES WITH, AND WHY IT IS THE ONE BEING HIT. Interest accrues to
## the VICTIM more than to the dealer, because the hit is what the viewer came for —
## the impact, the knockback, the number. A camera that follows the aggressor watches
## somebody swing at empty air just off frame.
##
## Both still score, though, or a duel would whip between the two on every trade.
const PORTRAIT_INTEREST_VICTIM: float = 1.0
const PORTRAIT_INTEREST_DEALER: float = 0.55
## Interest bleeds off this fast, per second. Long enough that a flurry keeps the
## camera where it is, short enough that the shot moves on when the fight does.
const PORTRAIT_INTEREST_DECAY: float = 1.4
## ⚠ HYSTERESIS, AND IT IS NOT OPTIONAL. Without both of these the subject changes
## on every trade and the camera whips back and forth — which reads worse than the
## wide shot it replaced. A challenger must beat the incumbent by a MARGIN, and the
## incumbent gets a minimum time in the chair regardless.
const PORTRAIT_SWITCH_MARGIN: float = 0.40
const PORTRAIT_SUBJECT_DWELL: float = 0.90
## How far above the fighters the eye sits, so the floor falls in the lower third.
## Rendered and looked at: at 130 the horizon sat at ~95% of frame height and the
## fighters' feet were clipped by the bottom edge. 45 puts the floor in the lower
## third with headroom above for a meteor column or a raised staff.
## HOW HARD THE EYE CHASES ITS OWN ANSWER — and the LARGER half of *"the camera drifts
## to the side"*.
##
## ⚠ `Camera2D.global_position` IS THE TARGET, NOT THE PICTURE. With
## `position_smoothing_enabled` the drawn centre is `get_screen_center_position()`, and
## at the old rate of 4.0 the two were measured **142 px apart at p95** on a 640-wide
## logical frame — nearly half a half-frame, as pure follow lag. The framer was solving
## correctly and the picture was arriving a quarter-second late. Reading the source
## cannot find this, and neither can reading `global_position`: the first version of
## the probe did exactly that, and reported a camera that tracked perfectly.
##
## Swept over four class pairs, reading the DRAWN channel (`probe_showcase_framing`):
##
##     rate   mean off-centre    p95     someone off screen   jerk
##     4.0        31.7 px      107.9 px         3.2%          0.42
##     12.0       17.2 px       70.2 px         3.0%          0.51
##     18.0       13.2 px       51.2 px         2.7%          0.58
##     26.0        9.9 px       39.9 px         1.7%          0.67
##
## `jerk` is the second difference of the drawn centre — the column that would catch a
## camera buying accuracy by snapping to every twitch. It barely moves, because the
## focus point is the midpoint of two bodies and is inherently smooth. 18 takes almost
## all of the available gain; 26 buys a further 3 px — invisible on a 640 px frame —
## for a 16% stiffer camera, and a stiffer camera cuts harder on the rematch teleport.
## Still smoothed, just no longer behind the fight.
const SHOWCASE_FOLLOW_SPEED: float = 18.0
const SHOWCASE_EYE_LIFT: float = 45.0
## How long the KO banner holds before the next bout begins.
const SHOWCASE_REMATCH_GRACE: float = 1.1

## instance_id -> {"node": Node2D, "stocks": int, "spawn": Vector2 (global),
## "invuln": float}. Eliminated bots are erased; the eliminated hero stays
## registered at 0 stocks (the _match_over guard makes further falls no-ops).
var _registry: Dictionary = {}
var _p1: Node2D = null
var _match_over: bool = false
var _stocks_label: Label = null
var _banner: Label = null
var _pause_menu: PauseMenu = null
## Showcase-only pair-framing camera; see _build_showcase_camera.
var _show_cam: Camera2D = null
## The clip camera operator, when `showcase_directed` asked for one. Null otherwise,
## and every call site is guarded — a showcase without a director is the shipped
## behaviour, not a degraded one.
var _clip: ClipDirector = null
## Pair-camera framing knobs, so the same tracker serves the wide clip framing
## and the tighter played-duel framing without a second copy of the code.
## The pair camera's own smoothed FRAMING zoom, kept separately from `_show_cam.zoom`
## so an operator zoom punch cannot be read back next frame as a framing decision.
var _cam_zoom_smoothed: float = SHOWCASE_ZOOM_MAX
var _cam_margin: float = SHOWCASE_FRAME_MARGIN
var _cam_zoom_min: float = SHOWCASE_ZOOM_MIN
var _cam_zoom_max: float = SHOWCASE_ZOOM_MAX

## PORTRAIT SUBJECT TRACKING — see `_portrait_subject`. All four are dead weight in
## landscape, where the camera never leaves the midpoint.
## instance_id -> decaying "the fight is happening to you" score.
var _cam_interest: Dictionary = {}
## instance_id -> last seen HP, so a drop can be detected without a damage signal.
var _cam_hp: Dictionary = {}
## Who the camera is currently with, and for how long. The dwell is half the
## hysteresis that stops the shot whipping on every trade.
var _cam_subject_id: int = 0
var _cam_subject_dwell: float = 0.0

## ---- duel state ----------------------------------------------------------
var _duel_bot: CharacterBody2D = null
var _duel_ctrl: RefCounted = null          # the bot's BotController
var _duel_clock: float = 0.0               # match clock, for the observation windows
var _learn_store: Dictionary = {}
var _learn_rec: Dictionary = {}
var _learn_class: int = -1                 # which human class the record belongs to
var _learn_save_at: float = 0.0
## Pending cast credit: {"slot": int, "at": float} while a bot cast is in flight.
var _credit: Dictionary = {}
var _last_whiff_at: float = -99.0
var _human_hp_last: int = -1
var _bot_hp_last: int = -1
var _dodge_ready_at: float = 0.0
var _duel_labels: Dictionary = {}          # name -> Label / Button, for live text
var _intent_label: Label = null
var _learn_label: Label = null

## ---- live probe state ----------------------------------------------------
var _probe: GDScript = null
var _findings: Array[Dictionary] = []
var _finding_seen: Dictionary = {}         # "kind|label" -> {"at": float, "row": Dictionary}
var _probe_hp_trail: Array[Dictionary] = []
## Victory can't be declared during this opening grace (stops a frame-0 / spawn
## transient from instantly flashing "VICTORY").
var _grace: float = 1.2


func _ready() -> void:
	# ONE STAGE ROLL PER SCENE, cleared here so the next bout gets a fresh one. Every
	# builder below asks `active_terraces` / `active_cover` separately and they must
	# all get the SAME answer, or the cover would be placed for one stage and the
	# terrain built for another. See `_layout_index`.
	_layout_rolled = false
	# ALWAYS so Esc can toggle pause even while the tree is paused; the fighters
	# are set PAUSABLE in _spawn_fighters so THEY still freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Smash sandbox: switch the whole scene to the damage-% + ring-out model. The
	# tower's Arena leaves this off (hp-death clears floors); enter_run turns it
	# back off, so it never leaks into a run. See GameState.ringout_mode.
	# ⚠ THE PLAYER CHOOSES, and this used to be forced. A duel was ALWAYS the
	# damage-%-and-ring-out model; the maker asked for health instead, with the
	# Smash model kept as an option ("in settings give the users the options to
	# choose lives vs percentages"). Both models were already built here — this is
	# the line that stopped assuming which one you wanted.
	#
	# A SHOWCASE still follows its own `showcase_ringout` flag: it is a capture rig,
	# not a fight, and its framing depends on bodies leaving the stage.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var wants_stocks: bool = int(gs.get("pvp_rules")) == 1
		gs.set("ringout_mode", showcase_ringout if _is_showcase() else wants_stocks)
	# Switch the music bed back to combat (the hub swaps it to the calm ambience).
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_combat"):
		music.play_combat()
	_build_background()
	_build_terrain()           # connected solid rock terraces + realistic look
	_build_ruins()             # rooted broken-stone platforms over the ground
	_build_cover()
	_build_breakable_platforms()
	_build_blast_zones()       # ring-out off the far L/R edges only
	_spawn_fighters()
	_build_hud()
	_update_hud()


func _process(delta: float) -> void:
	if get_tree().paused or _match_over:
		return
	_grace = maxf(_grace - delta, 0.0)
	for entry: Dictionary in _registry.values():
		entry["invuln"] = maxf(float(entry["invuln"]) - delta, 0.0)
	# FREE PLAY ends nothing and polls nothing. There is no opponent to beat, no
	# round to win and no roster to sweep — the whole mode is "the stage stays up".
	# Falling in a pit is handled by `_on_fighter_fell` (respawn, forever).
	if _is_free():
		_update_free_camera(delta)
		_update_hud()
		return
	if _is_duel():
		_duel_clock += delta
		_update_showcase_camera(delta)
		_tick_showcase_banner()
		# Learning and bug-hunting run on the same frames the fight does — they are
		# observers, and neither is allowed to change what happens.
		_observe_duel(delta)
		_probe_tick(delta)
		_update_duel_overlays()
		# Two heroes, no "enemy" side: the roster poll below would read zero bots on
		# frame one and flash VICTORY over the fight. A duel ends on a knockdown.
		_poll_showcase_end()
	else:
		# Showcase: two bot heroes, no "enemy" side at all — the bout ends when one
		# of the two is down, never on an enemy-roster poll.
		_update_showcase_camera(delta)
		_tick_showcase_banner()
		_poll_showcase_end()
	_update_hud()  # poll-don't-push (the AbilityBar idiom): always current


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


## Toggle a real tree pause + the overlay. VersusArena is ALWAYS so this keeps
## working while paused; the fighters (PAUSABLE) freeze.
func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)


## Pause/unpause + open/close the menu together (bound to Esc + the Resume button).
func _set_paused(p: bool) -> void:
	get_tree().paused = p
	if _pause_menu != null:
		if p:
			_pause_menu.open()
		else:
			_pause_menu.close()


# -------------------------------------------------------------------- ring-out
## The core: a PIT reported `body` falling in. Unknown/freed bodies are
## ignored; a body still inside its respawn-invuln window burns nothing.
## Otherwise: -1 stock, then respawn (stocks left) or eliminate (none left).
func _on_fighter_fell(body: Node) -> void:
	if _match_over or body == null or not is_instance_valid(body):
		return
	var id: int = body.get_instance_id()
	if not _registry.has(id):
		return
	var entry: Dictionary = _registry[id]
	if float(entry["invuln"]) > 0.0:
		return
	# FREE PLAY NEVER COSTS A STOCK. Falling off the rim is one of the things you
	# came here to try; the answer is a poof and a respawn, not an elimination
	# screen. Burning the stock anyway would end the sandbox after three curious
	# jumps.
	if _is_free():
		_respawn(body as Node2D, entry)
		return
	entry["stocks"] = int(entry["stocks"]) - 1
	if int(entry["stocks"]) > 0:
		_respawn(body as Node2D, entry)
	else:
		_eliminate(body as Node2D, id)
	_update_hud()


## Back to this fighter's own spawn point (always on the platform — moving it
## also clears the pit's per-body dedup), hp refilled, invuln armed so an
## instant re-report can't burn a second stock, plus a small arrival poof.
func _respawn(body: Node2D, entry: Dictionary) -> void:
	entry["invuln"] = RESPAWN_INVULN
	body.global_position = entry["spawn"]
	var max_hp_v: Variant = body.get("max_hp")
	if max_hp_v != null:
		body.set("hp", max_hp_v)
		if body.has_signal("health_changed"):
			body.emit_signal("health_changed", int(max_hp_v), int(max_hp_v))
	# Smash sandbox: a fresh life starts back at 0% (light again, hard to launch).
	if body.get("damage_pct") != null:
		body.set("damage_pct", 0.0)
	CombatVfx.spawn_burst(
		self, entry["spawn"], RESPAWN_POOF_START, RESPAWN_POOF_END,
		16, 0.35, 50.0, 120.0, 1.5, 3.0
	)


## Out of stocks.
##
## Both fighters here are HEROES (the group battle is gone), so nobody is freed:
## a stock-out ends the MATCH, and the match immediately restocks both sides so
## the maker can keep fighting without reloading the scene. Anything unexpected
## still in group "enemy" (a stray sandbox spawn) is simply removed.
func _eliminate(body: Node2D, id: int) -> void:
	if body.is_in_group("enemy"):
		_registry.erase(id)
		body.queue_free()
		return
	_restock("YOU WIN THE MATCH" if body == _duel_bot else "BOT WINS THE MATCH")


## Refill every registered fighter's stocks and reset the round, so a finished
## match rolls straight into the next one. A "Rematch" that costs a scene reload
## would throw away the learned record's in-flight session for no reason.
func _restock(banner_text: String) -> void:
	for entry: Dictionary in _registry.values():
		entry["stocks"] = STOCKS
		entry["invuln"] = RESPAWN_INVULN
	if _banner != null:
		_banner.text = banner_text
		_banner.visible = true
	_grace = DUEL_REMATCH_GRACE
	_reset_round_bodies()


## True while this scene is running as a two-bot showcase duel.
func _is_showcase() -> bool:
	return showcase_a >= 0 and showcase_b >= 0


## Showcase end condition: the duel is over when a registered hero reaches 0 hp.
## Grace-gated like the normal poll so a spawn-frame transient cannot end it.
## A KO in showcase mode RESETS THE BOUT instead of ending the scene.
##
## A clip that stops the first time somebody goes down is mostly a still frame —
## the first capture ran 400 frames and spent 340 of them watching a corpse. So a
## showcase is a sparring loop: on a knockdown both fighters are restored, both
## are returned to their own spawn, and the fight starts again.
##
## ⚠ SYMMETRICAL, DELIBERATELY. Both sides are reset identically, and neither
## gets health, cooldowns or knowledge the other does not. This changes how long
## the CAMERA rolls, never who wins — a clip of a rigged fight would be worthless
## for finding bugs and dishonest as marketing.
func _poll_showcase_end() -> void:
	if _grace > 0.0:
		return
	var downed: Node = null
	for entry: Dictionary in _registry.values():
		var node: Node = entry["node"]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if int(node.get("hp")) <= 0:
			downed = node
			break
	if downed == null:
		return
	if _banner != null:
		if _is_duel():
			# Say who won in the maker's own terms, not "class X down".
			_banner.text = "BOT WINS THE ROUND" if downed == _p1 else "YOU WIN THE ROUND"
		else:
			_banner.text = "%s DOWN" % _class_label(_showcase_class_of(downed))
		_banner.visible = true
	_grace = DUEL_REMATCH_GRACE if _is_duel() else SHOWCASE_REMATCH_GRACE
	# A round ended: that is the natural moment to bank what was learned, so a
	# crash or an Alt-F4 mid-next-round cannot cost the whole session.
	if _is_duel():
		_flush_learning()
	_reset_round_bodies()


## Restore every registered fighter: full hp, 0%, back on its own spawn, with an
## arrival poof. Shared by the knockdown reset and by the stock-out restock, so
## "a new round starts" means exactly one thing.
func _reset_round_bodies() -> void:
	var showcase_hp: int = showcase_hp_override if showcase_hp_override > 0 else SHOWCASE_HP
	var full_hp: int = DUEL_HP if _is_duel() else showcase_hp
	for entry: Dictionary in _registry.values():
		var node: Node = entry["node"]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		node.set("hp", full_hp)
		if node.get("damage_pct") != null:
			node.set("damage_pct", 0.0)
		if node.has_signal("health_changed"):
			node.emit_signal("health_changed", full_hp, full_hp)
		(node as Node2D).global_position = entry["spawn"]
		CombatVfx.spawn_burst(self, entry["spawn"], RESPAWN_POOF_START,
			RESPAWN_POOF_END, 20, 0.4, 60.0, 150.0, 1.5, 3.5)


## Which showcase slot a fighter is, so the banner can name its class. `_p1` is
## fighter A by construction in `_spawn_showcase`.
func _showcase_class_of(node: Node) -> int:
	return showcase_a if node == _p1 else showcase_b


## Hide the KO banner once the next bout is under way.
func _tick_showcase_banner() -> void:
	if _banner != null and _banner.visible and _grace <= 0.0:
		_banner.visible = false


## Latch _match_over + show the big centre banner. Idempotent — the first
## outcome to land wins; everything downstream early-outs on the flag.
func _finish_match(text: String) -> void:
	if _match_over:
		return
	_match_over = true
	if _banner != null:
		_banner.text = text
		_banner.visible = true
		get_tree().create_timer(2.5).timeout.connect(_hide_banner)  # brief, then gone
	_update_hud()


func _hide_banner() -> void:
	if _banner != null:
		_banner.visible = false


# ----------------------------------------------------------------------- build
## Flat sky backdrop (clean Stick-Fight look): a big sky rect + a slightly deeper
## lower band for a hint of depth. Far behind everything; ignores the mouse.
func _build_background() -> void:
	# Epic backdrop (gradient sky + distant tower spires + drifting motes +
	# vignette) instead of two flat ColorRects — see Atmosphere.gd.
	Atmosphere.add_glow(self)  # 2D bloom: pushed spell cores radiate
	PostProcess.add(self)      # reactive screen-space grade ("the look")
	var atmo := Atmosphere.new()
	add_child(atmo)
	# Warm, readable DUSK (not near-black night) so the battlefield reads as a fun
	# place: a soft blue sky over a warm pale haze at the horizon, with the distant
	# tower-spires HAZED (low contrast) so they recede as background instead of
	# looming as black teeth over the fight.
	# SHOWCASE gets a LIFTED palette. The played arena's dusk reads fine on a lit
	# monitor with a camera close to the action; framed wide for a clip it came out
	# near-black, with two dark stick figures on dark rock against a dark sky —
	# checked by rendering it and looking. Brighter sky, warmer ground haze, and
	# lighter spires give the fighters something to be silhouetted AGAINST.
	var sky: Dictionary = {
		"sky_top": Color(0.23, 0.31, 0.49),
		"sky_bottom": Color(0.72, 0.69, 0.66),
		"silhouette_far": Color(0.42, 0.46, 0.56),
		"silhouette_near": Color(0.30, 0.33, 0.44),
		"accent": Color(0.92, 0.95, 1.0),
	}
	if _is_showcase():
		sky = {
			"sky_top": Color(0.38, 0.50, 0.74),
			"sky_bottom": Color(0.93, 0.86, 0.78),
			"silhouette_far": Color(0.62, 0.66, 0.78),
			"silhouette_near": Color(0.47, 0.50, 0.63),
			"accent": Color(1.0, 0.98, 0.92),
		}
	# ══ TEN SKIES, AND NOT ONE NEW ASSET ════════════════════════════════════════
	# Maker: *"lets randomise the map they fight in give that variety, make some
	# awesome cooler looking maps please with cool backgrounds"*. Measured first: this
	# stage NEVER varied — a grep for `randi|randf|seed` across this whole file
	# returned nothing, and the only branch in the entire look was the two-way
	# showcase palette literal above. Every clip this project has ever shot was the
	# same dusk.
	#
	# The tower already owns ten authored biomes (`GameState.BIOMES`) with a wash, an
	# accent and an exposure each, and `Atmosphere.build` ALREADY takes a palette dict
	# — so the whole win here is feeding one into the other. No new art, no generator,
	# no geometry change (which is where the real risk lives: the spawn symmetry, the
	# camera's vertical band and the rim rules are all pinned to today's layout).
	#
	# ⚠ `GameState` IS LOADED BY PATH, NEVER NAMED. It is an autoload with no
	# `class_name`, and the headless suites run `--script` with no autoloads at all —
	# writing the bare identifier here is a COMPILE-TIME failure in those harnesses,
	# not a runtime one. This file already documents that idiom for the same reason.
	var theme: Object = _stage_theme()
	if theme != null:
		var wash: Color = theme.call("lit_wash")
		var accent: Color = theme.call("accent")
		var lift: float = 1.18 if _is_showcase() else 1.0
		sky = {
			# The sky is the biome's own wash opened up — dark enough to stay a sky,
			# far enough from the ground band that the fighters have something to be
			# silhouetted against. That contrast is the measured constraint the
			# showcase palette above exists to satisfy, so it is preserved as a LIFT
			# rather than replaced.
			"sky_top": (wash * lift).lightened(0.22),
			"sky_bottom": accent.lerp(Color(0.93, 0.90, 0.86), 0.45) * lift,
			"silhouette_far": (wash * lift).lightened(0.44),
			"silhouette_near": (wash * lift).lightened(0.26),
			"accent": accent.lightened(0.35),
		}
		# The screen grade follows the room, exactly as it does in the tower. One line,
		# ten grades, and it was simply never called here — this file calls
		# `PostProcess.add` and then never tells it what colour the world is.
		PostProcess.set_theme(wash)
	atmo.build(Rect2(BACKDROP_ORIGIN, STAGE_SIZE + BACKDROP_GROWTH), sky)


## The biome this bout is dressed in, or null to keep the authored dusk.
##
## Rolled ONCE, here, never in a drawer: `FloorDecor` and `ArenaTerrain` both require
## hashed pseudo-noise rather than an RNG inside `_draw`, because a shape that
## reshuffles every redraw boils. Same rule `BotMatch._roll_matchup` follows.
func _stage_theme() -> Object:
	var gs: GDScript = load("res://scripts/GameState.gd") as GDScript
	if gs == null:
		return null
	var count: int = 10
	var rows: Variant = gs.get("BIOMES")
	if rows is Array and not (rows as Array).is_empty():
		count = (rows as Array).size()
	var pick: int = stage_biome
	if pick < 0:
		pick = randi() % count
	stage_biome_rolled = pick % count
	# `floor_env` is keyed by FLOOR and wraps modulo the table, so floor = index + 1
	# addresses a biome directly. Static and pure — no run state, no autoload instance.
	return gs.call("floor_env", stage_biome_rolled + 1)


## The connected rock landscape: a permanent solid collider per terrace + ONE
## ArenaTerrain node that draws them all as one realistic layered landmass. The
## colliders extend well below their surface + overlap horizontally, so the risers
## are jumpable stairs and no CharacterBody snags a seam. z-order: the terrain draws
## behind the fighters; the colliders carry no visual.
func _build_terrain() -> void:
	var rows: Array = active_terraces()
	for t: Dictionary in rows:
		_make_terrace(float(t["surface_y"]), float(t["x0"]), float(t["x1"]))
	var terrain := ArenaTerrain.new()
	# ⚠ `assign`, NOT `=`. `ArenaTerrain.terraces` is `Array[Dictionary]`; this used to
	# be handed the typed const `TERRACES` and matched. `active_terraces()` indexes
	# `STAGE_TERRACES: Array[Array]`, and GDScript cannot express
	# `Array[Array[Dictionary]]` — so the inner arrays are UNTYPED and a plain `=`
	# throws "Invalid assignment of property or key 'terraces'".
	#
	# It threw on every bout of every mode that uses this stage, and stayed invisible
	# for a week: a failed property set is NOT fatal, so `_ready` walked straight on,
	# built the ruins and cover and spawned both fighters, and the only casualty was
	# the rock nobody asserted on. See `tools/slice_test_arena_builds.gd`.
	terrain.terraces.assign(rows)
	terrain.floor_y = STAGE_SIZE.y
	add_child(terrain)


## ══ WHICH STAGE THIS BOUT IS ON ════════════════════════════════════════════
## Rolled once, on the first ask, and remembered — every builder in `_ready` asks
## separately and they must all get the same answer or the cover would be placed for
## one stage and the terrain built for another.
##
## `TERRACES` is kept as the name for variant 0 so nothing outside this file that
## reads it (the suite, `ArenaTerrain`'s default, the probe bounds) has to change.
static func active_terraces() -> Array:
	return STAGE_TERRACES[_layout_index()]


static func active_cover() -> Array:
	return STAGE_COVER[_layout_index()]


static func _layout_index() -> int:
	if stage_layout >= 0:
		stage_layout_rolled = stage_layout % STAGE_TERRACES.size()
	elif not _layout_rolled:
		_layout_rolled = true
		stage_layout_rolled = randi() % STAGE_TERRACES.size()
	return stage_layout_rolled


static var _layout_rolled: bool = false


## One solid, permanent terrace collider (layer 1). The TOP edge sits exactly on
## surface_y; the box grows down by TERRACE_DEPTH so it reads as deep rock and
## nobody clips under it.
func _make_terrace(surface_y: float, x0: float, x1: float) -> void:
	var body := StaticBody2D.new()
	var w: float = x1 - x0
	body.position = Vector2((x0 + x1) * 0.5, surface_y + TERRACE_DEPTH * 0.5)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, TERRACE_DEPTH)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Rooted broken-stone ruin platforms over the ground (solid; drawn by RuinPlatform).
func _build_ruins() -> void:
	for r: Dictionary in RUINS:
		var ruin := RuinPlatform.new()
		ruin.platform_size = r["size"]
		add_child(ruin)
		ruin.position = r["center"]


## Real blocking cover that spells + melee chew through (group "destructible").
##
## Every block is pushed clear of wherever bodies are about to stand — see
## `SPAWN_FOOTPRINT_HALF`. Doing it here rather than in the authoring table means the
## overlap is IMPOSSIBLE rather than merely currently absent: `COVER_POINTS` and
## `BotMatch.SPAWN_SPREAD` can both move again without anybody re-checking the sum.
func _build_cover() -> void:
	var keepout: Array[float] = _spawn_keepout()
	for point: Vector2 in active_cover():
		var block := DestructibleTerrain.new()
		block.position = Vector2(
			cover_x_clear_of(point.x, block.block_size.x, keepout), point.y)
		add_child(block)


## The x positions bodies will occupy on this stage, for the cover keep-out.
## An explicit `spawn_keepout_x` wins outright; otherwise the stage answers for the
## mode it is running in, so a capture tool that drives the showcase WITHOUT
## `BotMatch` is protected by the same rule.
func _spawn_keepout() -> Array[float]:
	if not spawn_keepout_x.is_empty():
		return spawn_keepout_x
	if _is_showcase():
		return [SHOWCASE_SPAWN_A.x, SHOWCASE_SPAWN_B.x]
	if _is_free():
		return [FREE_SPAWN.x]
	return [P1_SPAWN.x]


## Shove a block of width `block_w` centred at `x` off every point in `keepout`,
## by the SHORT way each time so the stage changes as little as it can, then clamp it
## back onto the fight floor. Pure and static — headless-tested, no scene required.
static func cover_x_clear_of(x: float, block_w: float, keepout: Array[float]) -> float:
	var need: float = block_w * 0.5 + SPAWN_FOOTPRINT_HALF
	var out: float = x
	for sx: float in keepout:
		var gap: float = out - sx
		if absf(gap) >= need:
			continue
		# A block sitting EXACTLY on a spawn has no short way; going right is
		# arbitrary but stable, which matters because both co-op peers build this.
		out = sx + (need if gap >= 0.0 else -need)
	return clampf(out, COVER_X_MIN, COVER_X_MAX)


## Breakable + regenerating platforms you can stand/jump on and destroy.
func _build_breakable_platforms() -> void:
	for p: Dictionary in BREAKABLE_PLATFORMS:
		var plat := BreakablePlatform.new()
		plat.platform_size = p["size"]
		add_child(plat)
		plat.position = p["center"]


## LIVE ring-out: instantiate the far-edge PITs and wire fighter_fell -> the
## stock/respawn manager. Only off the sides now (no void beneath the solid rock),
## so a fall is an earned knock-off, never a floor-hole handing an early win.
func _build_blast_zones() -> void:
	for z: Dictionary in BLAST_ZONES:
		var pit := StageHazard.new()
		pit.mode = StageHazard.Mode.PIT
		pit.zone_size = z["size"]
		pit.position = z["center"]
		pit.fighter_fell.connect(_on_fighter_fell)
		add_child(pit)


## Runtime load()s, never preload: both scenes' scripts reference autoload
## globals (Sfx/Rank/Juice), which only register with GDScript once the main
## loop is live — the headless slice-test harness load()s THIS script first,
## and a preload here would compile them too early (slice1_test_weapon idiom).
## Hero goes in first so each bot's _ready finds it via the "hero" group.
## Bot archetypes are set BEFORE add_child so Enemy._ready sees them.
func _spawn_fighters() -> void:
	if _is_showcase():
		_spawn_showcase()
	elif _is_free():
		_spawn_free()
	else:
		_spawn_duel()


## SHOWCASE: two bot heroes, opposed classes, pointed at each other.
##
## The two things that make hero-vs-hero work at all, and both are easy to miss:
##   FACTION — damage used to be routed by the hardwired group `"enemy"`, so two
##             heroes swinging at each other did nothing whatsoever. `hostile_group`
##             (via `set_hostile`) is what makes the fight real.
##   CAMERA  — `Hero.tscn` carries its own Camera2D. Two live cameras fight over
##             the viewport, so exactly ONE stays enabled and is put in fit-all
##             mode; the second is disabled the way a co-op puppet's is.
func _spawn_showcase() -> void:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var a: CharacterBody2D = _spawn_showcase_fighter(hero_scene, showcase_a, SHOWCASE_SPAWN_A, true)
	var b: CharacterBody2D = _spawn_showcase_fighter(hero_scene, showcase_b, SHOWCASE_SPAWN_B, false)
	_p1 = a
	# BOTH hero cameras are off in showcase mode — the pair-framing camera below
	# owns the viewport, because a camera that follows one fighter loses the other
	# the moment the fight spreads out.
	_build_showcase_camera()
	# ...and a clip tool that asked for a real camera operator gets one that frames the
	# ACTION rather than the pair. The operator is now built EITHER WAY — see
	# `_build_camera_operator`.
	_build_camera_operator(showcase_directed)
	# Face them at each other on frame one so the opening reads as a duel rather
	# than as two bots noticing each other.
	if a != null and b != null:
		a.set("facing", Vector2.RIGHT)
		b.set("facing", Vector2.LEFT)


## One showcase fighter: class, faction, bot brain, camera, registry entry.
func _spawn_showcase_fighter(scene: PackedScene, class_id: int, at: Vector2,
		keep_camera: bool) -> CharacterBody2D:
	var hp: int = showcase_hp_override if showcase_hp_override > 0 else SHOWCASE_HP
	var hero: CharacterBody2D = scene.instantiate()
	hero.set("net_class", class_id)   # read by Hero._ready, before configure_class
	hero.max_hp = hp
	hero.position = at
	add_child(hero)
	hero.process_mode = Node.PROCESS_MODE_PAUSABLE
	if hero.has_method("configure_class"):
		hero.configure_class(class_id)
	hero.set("max_hp", hp)
	hero.set("hp", hp)
	if hero.has_method("set_hostile"):
		hero.call("set_hostile", &"hero")
	else:
		hero.set("hostile_group", &"hero")
	# Every hero camera is disabled in showcase mode (`keep_camera` is unused here
	# and kept only so the signature still reads as intentional): the arena's own
	# pair-framing camera is current instead.
	for child: Node in hero.get_children():
		if child is Camera2D:
			(child as Camera2D).enabled = false
			# ⚠ AND IT LEAVES THE GROUP. `enabled = false` hides a camera; it does not
			# stop `_ready` having joined `combat_camera`, nor stop `_process` running.
			# So every `Juice.shake_camera` in a duel was being delivered to two
			# INVISIBLE cameras, and `PostProcess`, which takes the group's FIRST
			# member, was reading its screen-shake grade off one of them. A camera
			# nobody is looking through must not answer for the camera group.
			(child as Camera2D).remove_from_group("combat_camera")
	_attach_bot(hero)
	_register_fighter(hero, hero.global_position)
	return hero


# ====================================================================== DUEL
## True while this scene is running as HUMAN vs ONE BOT — i.e. always, unless a
## capture tool has set the two showcase classes. The five-bot practice arena
## that used to be the default was removed at maker request.
func _is_duel() -> bool:
	return not _is_showcase() and not _is_free()


## True while this scene is running as FREE PLAY — one hero, no opposition.
## Showcase wins if both were somehow set, because a capture tool asking for a
## two-bot clip and getting an empty room is the worse failure.
func _is_free() -> bool:
	return free_play and not _is_showcase()


## The clip camera operator, for a capture tool that wants to know when the fight
## caught and when somebody went down. Null unless `showcase_directed` was set.
func clip_director() -> ClipDirector:
	return _clip


## The free-play hero, for `FreePlay.gd`. Null in every other mode.
func free_hero() -> CharacterBody2D:
	return _p1 as CharacterBody2D if _is_free() else null


## The pause menu this arena built, so the free-play layer can hang its own rows on
## it instead of standing up a second overlay that fights the first for Esc.
func pause_menu() -> PauseMenu:
	return _pause_menu


## Stand up / tear down practice dummies at runtime. Free play only — everything
## else on this stage is a real fight and a dummy in it would be a bug.
func set_dummy_count(n: int) -> void:
	if not _is_free():
		return
	free_dummies = clampi(n, 0, FREE_DUMMY_POINTS.size())
	_rebuild_dummies()


func dummy_count() -> int:
	return free_dummies


## Everything back to frame one WITHOUT a scene reload: hero healed, 0%, back on
## its spawn, dummies restored, cover and breakable platforms rebuilt.
##
## A reload would also work and is two lines shorter. It is the wrong call: free
## play exists so the maker can change one thing and feel the difference
## immediately, and a reload throws away the class they just switched to, the
## dummies they just placed and the second and a half it takes to get back in.
func reset_free_stage() -> void:
	if not _is_free():
		return
	for child: Node in get_children():
		if child is DestructibleTerrain or child is BreakablePlatform:
			child.queue_free()
	_build_cover()
	_build_breakable_platforms()
	if _p1 != null and is_instance_valid(_p1):
		_p1.set("hp", FREE_HP)
		if _p1.get("damage_pct") != null:
			_p1.set("damage_pct", 0.0)
		if _p1.has_signal("health_changed"):
			_p1.emit_signal("health_changed", FREE_HP, FREE_HP)
		(_p1 as Node2D).global_position = FREE_SPAWN
	_rebuild_dummies()


## FREE PLAY spawn: one hero, its own camera, no opponent, no faction to be
## hostile to. Registered like every other fighter so the ring-out plumbing keeps
## working — but with a stock count nothing can exhaust (see `_on_fighter_fell`).
func _spawn_free() -> void:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	_p1 = hero_scene.instantiate()
	_p1.position = FREE_SPAWN
	_p1.max_hp = FREE_HP
	add_child(_p1)
	_p1.process_mode = Node.PROCESS_MODE_PAUSABLE
	_p1.set("max_hp", FREE_HP)
	_p1.set("hp", FREE_HP)
	# A faction of its own with nothing hostile in it. Free play has no opponent, and
	# leaving the default `enemy` hostility on would make the hero's own auto-target
	# reads point at a group that does not exist on this stage.
	_p1.call("set_faction", &"free_player", &"free_dummy")
	_p1.set("facing", Vector2.RIGHT)
	_register_fighter(_p1, _p1.global_position, 999)
	# ⚠ THE HERO'S OWN CAMERA IS TURNED OFF HERE, and the first version of this mode
	# did not do that. `Hero.tscn`'s Camera2D carries LIMITS tuned for the tower's
	# 1200x680 arena; this stage is 2000x1000, so the camera clamped itself into the
	# top-left corner and every captured frame came back as empty sky with the
	# hotbar floating over it. MEASURED, not assumed — `tools/freeplay_capture.gd`
	# shot exactly that. The arena's own camera has the right clamps for the right
	# stage, so free play borrows it and simply follows one body instead of two.
	for child: Node in _p1.get_children():
		if child is Camera2D:
			(child as Camera2D).enabled = false
			(child as Camera2D).remove_from_group("combat_camera")  # see _spawn_showcase_fighter
	_build_showcase_camera()
	_build_camera_operator(false)
	_show_cam.zoom = Vector2(FREE_ZOOM, FREE_ZOOM)
	# ⚠ THE CAMERA'S OWN POSITION SMOOTHING IS OFF IN FREE PLAY, and leaving it on is
	# what made the first capture unreadable. `_update_free_camera` already lerps, so
	# with `position_smoothing_enabled` the transform is lagged TWICE — the rendered
	# eye trails the solved eye by a large fraction of a second, which on a 2000 px
	# stage is hundreds of pixels of drift and a shot that never quite catches up
	# with the hero. One smoother, not two.
	_show_cam.position_smoothing_enabled = false
	_show_cam.global_position = Vector2(FREE_SPAWN.x, GROUND_TOP - FREE_EYE_LIFT)
	_rebuild_dummies()


## WHERE THE EYE MAY SIT ON X, GIVEN HOW WIDE THE FRAME CURRENTLY IS.
##
## ⚠ THE OLD RULE WAS A CONSTANT AND IT IS HALF OF *"the camera drifts to the side"*.
## Both cameras used `clampf(x, 340.0, STAGE_SIZE.x - 340.0)`. That is wrong twice:
##
##   * A CONSTANT CANNOT BOUND A FRAME WHOSE WIDTH CHANGES EVERY FRAME. 340 is the
##     world half-width at zoom 0.94 — the middle of the showcase's range, so it was a
##     reasonable single sample and not a random number. But the range is 0.47..1.32,
##     where the half-width runs 680 down to 242 px. The rail is therefore too LOOSE
##     when the shot is wide (it lets emptiness in) and too TIGHT when it is close (it
##     stops following while there is still stage to show) — and the close end is the
##     common one.
##   * IT WAS ANCHORED TO `STAGE_SIZE`, the collision extent (2000 wide, centred on
##     x=1000), while the fight floor is x 40..1400, centred on 720. So the band was
##     offset ~280 px to the RIGHT of where the fight happens, and the LEFT rail bit
##     first and hardest — measured at 13.6% of frames in `probe_showcase_framing`.
##
## The rule now: put the eye where it is asked, then pull it back only far enough that
## the frame stays inside the PAINTED world. When the frame is wider than the painting
## there is no position that satisfies that, so centre the painting instead of picking
## an arbitrary rail — a rail would park the fight hard against one edge, which is the
## exact complaint.
func _frame_x(want_x: float, zoom: float, view_w: float) -> float:
	var half_w: float = view_w / (2.0 * maxf(zoom, 0.01))
	var lo: float = (STAGE_RIM_X0 - STAGE_RIM_SLACK) + half_w
	var hi: float = (STAGE_RIM_X1 + STAGE_RIM_SLACK) - half_w
	if lo >= hi:
		return (STAGE_RIM_X0 + STAGE_RIM_X1) * 0.5
	return clampf(want_x, lo, hi)


## Follow the one hero. Same clamps as the pair camera (so the eye can never drift
## off the rock into empty sky) but a fixed zoom, because there is no second fighter
## whose separation would justify changing it.
func _update_free_camera(delta: float) -> void:
	if _show_cam == null or _p1 == null or not is_instance_valid(_p1):
		return
	var at: Vector2 = (_p1 as Node2D).global_position
	# Free play frames itself but still wants the hits to land on the picture — the
	# operator lays shake and the zoom envelopes over the fixed zoom.
	if _clip != null:
		var fz: float = _clip.compose(FREE_ZOOM, delta)
		_show_cam.zoom = Vector2(fz, fz)
	var eye: Vector2 = Vector2(
		_frame_x(at.x, _show_cam.zoom.x, float(get_viewport().get_visible_rect().size.x)),
		clampf(at.y - FREE_EYE_LIFT, GROUND_TOP - 330.0, GROUND_TOP - 30.0))
	_show_cam.global_position = _show_cam.global_position.lerp(eye,
		clampf(delta * 6.0, 0.0, 1.0))


## Rebuild the practice dummies to match `free_dummies`. Cheap and idempotent —
## it frees whatever is there and stands up the requested number, so the count
## button can be pressed as fast as the maker likes.
func _rebuild_dummies() -> void:
	for d: Node in get_tree().get_nodes_in_group(&"free_dummy"):
		if is_instance_valid(d):
			_registry.erase(d.get_instance_id())
			d.queue_free()
	if free_dummies <= 0:
		return
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	for i: int in mini(free_dummies, FREE_DUMMY_POINTS.size()):
		var d: CharacterBody2D = hero_scene.instantiate()
		d.max_hp = FREE_DUMMY_HP
		d.position = FREE_DUMMY_POINTS[i]
		add_child(d)
		d.process_mode = Node.PROCESS_MODE_PAUSABLE
		d.set("max_hp", FREE_DUMMY_HP)
		d.set("hp", FREE_DUMMY_HP)
		# On the team the player is hostile to, and hostile to NOBODY: it can be hit
		# and it never hits back. No controller, so `Hero._pressed` falls through to
		# the real `Input` — which would make every dummy mirror the player's own
		# buttons. Physics off is what stops that, and it is why a dummy stands still
		# instead of walking in lockstep with you.
		d.call("set_faction", &"free_dummy", &"nobody")
		d.set("facing", Vector2.LEFT)
		d.add_to_group(&"free_dummy")
		# ⚠ A DUMMY IS A WHOLE HERO, AND A HERO CARRIES A CAMERA. Every other spawn path
		# in this file disables the hero camera it instantiates and says why; this one
		# never did, so each free-play dummy added an ENABLED Camera2D to the scene —
		# fighting the pair camera for the viewport, since `_rebuild_dummies` runs after
		# `_build_showcase_camera`'s `make_current` — and put another member in
		# `combat_camera` for `Juice` and `PostProcess` to talk to.
		for child: Node in d.get_children():
			if child is Camera2D:
				(child as Camera2D).enabled = false
				(child as Camera2D).remove_from_group("combat_camera")
		d.set_physics_process(false)
		_register_fighter(d, d.global_position, 999)


## THE MAKER'S FIGHT. Two heroes: A has no controller (so `Hero._pressed` falls
## through to the real `Input` and the maker drives it), B carries the shipped
## bot stack at the chosen tier.
##
## THREE THINGS MAKE THIS WORK, and each of them is a bug if forgotten:
##   FACTION — damage routes through `hostile_group`. Two heroes both defaulted to
##             `"enemy"` would swing at each other all day and connect with
##             nothing. `set_faction` puts each on a team the other is hostile to.
##   CAMERA  — `Hero.tscn` carries a Camera2D, and `Hero._setup_net_role` only
##             disables it in a NETWORKED session (it early-returns offline). So
##             offline, a second hero's camera fights the first for the viewport.
##             Both are disabled here and the arena's pair-framing camera owns it.
##   LEARNING— the record is loaded and attached BEFORE the first tick, so the bot
##             walks in already knowing what it learned last time you played.
func _spawn_duel() -> void:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)

	# --- the human. Added FIRST on purpose: `AbilityBar` binds to
	# `get_first_node_in_group("hero")`, and both duellists are heroes, so
	# whichever enters the tree first owns the hotbar. That must be yours.
	_p1 = hero_scene.instantiate()
	_p1.position = DUEL_SPAWN_HUMAN
	_p1.max_hp = DUEL_HP
	add_child(_p1)
	_p1.process_mode = Node.PROCESS_MODE_PAUSABLE
	_p1.set("max_hp", DUEL_HP)
	_p1.set("hp", DUEL_HP)
	_p1.call("set_faction", &"duel_human", &"duel_bot")
	_p1.set("facing", Vector2.RIGHT)
	_register_fighter(_p1, _p1.global_position)

	# --- the bot.
	_duel_bot = hero_scene.instantiate()
	_duel_bot.set("net_class", duel_bot_class)   # read by Hero._ready, before configure_class
	_duel_bot.max_hp = DUEL_HP
	_duel_bot.position = DUEL_SPAWN_BOT
	add_child(_duel_bot)
	_duel_bot.process_mode = Node.PROCESS_MODE_PAUSABLE
	if _duel_bot.has_method("configure_class"):
		_duel_bot.configure_class(duel_bot_class)
	_duel_bot.set("max_hp", DUEL_HP)
	_duel_bot.set("hp", DUEL_HP)
	_duel_bot.call("set_faction", &"duel_bot", &"duel_human")
	_duel_bot.set("facing", Vector2.LEFT)
	_attach_bot(_duel_bot, duel_difficulty)
	_register_fighter(_duel_bot, _duel_bot.global_position)

	# Neither hero's own camera runs: the pair-framing one below does, because a
	# camera glued to you loses your opponent the moment the fight spreads out.
	for h: Node in [_p1, _duel_bot]:
		for child: Node in h.get_children():
			if child is Camera2D:
				(child as Camera2D).enabled = false
				(child as Camera2D).remove_from_group("combat_camera")  # see _spawn_showcase_fighter
	_cam_margin = DUEL_FRAME_MARGIN
	_cam_zoom_min = DUEL_ZOOM_MIN
	_cam_zoom_max = DUEL_ZOOM_MAX
	_build_showcase_camera()
	_build_camera_operator(false)
	_show_cam.zoom = Vector2(DUEL_ZOOM_MAX, DUEL_ZOOM_MAX)
	_cam_zoom_smoothed = DUEL_ZOOM_MAX  # seed the framing state to match, or frame 1 jumps

	_begin_learning()
	_probe_begin()
	_human_hp_last = DUEL_HP
	_bot_hp_last = DUEL_HP


## Load what the bot knows about the human, attach it to the controller, and
## count the session. The record is keyed by the HUMAN'S class: how you play an
## Arcanist and how you play a Brawler are different problems, and one averaged
## record would have learned nothing about either.
func _begin_learning() -> void:
	_learn_store = BotAdapt.load_store()
	_learn_class = int(_p1.get("_hero_class")) if _p1 != null else -1
	if _learn_class < 0:
		var gs: Node = get_node_or_null("/root/GameState")
		_learn_class = int(gs.get("selected_class")) if gs != null else 0
	_learn_rec = BotAdapt.repair_record(BotAdapt.record_for(_learn_store, _learn_class))
	_learn_rec["sessions"] = int(_learn_rec.get("sessions", 0)) + 1
	if _duel_ctrl != null and duel_learning:
		_duel_ctrl.set("adapt", _learn_rec)
		# The middle of this bot's own spacing band, so the spacing half of the
		# adaptation knows what it is comparing your habits against. Read from the
		# brain's own table rather than restated, so a retune over there lands here.
		var bands: Array = BotBrain.CLASS_BAND
		if duel_bot_class >= 0 and duel_bot_class < bands.size():
			var b: Dictionary = bands[duel_bot_class]
			_duel_ctrl.set("band_centre", (float(b["min"]) + float(b["max"])) * 0.5)
	_learn_save_at = LEARN_SAVE_PERIOD


## Bank the record. Cheap (one small JSON, atomically renamed) and called at every
## natural pause, because a "learning" feature that loses the session on an
## Alt-F4 has not learned anything.
func _flush_learning() -> void:
	if _learn_store.is_empty() or _learn_class < 0:
		return
	BotAdapt.save_store(_learn_store)


## Forget everything about this player, from the button. Deletes the file AND
## resets the in-memory record, so the bot you are currently fighting goes back
## to a stock difficulty tier immediately rather than at the next reload.
func _forget_learning() -> void:
	BotAdapt.wipe()
	_learn_store = BotAdapt.empty_store()
	_learn_rec = BotAdapt.record_for(_learn_store, _learn_class)
	if _duel_ctrl != null:
		_duel_ctrl.set("adapt", _learn_rec if duel_learning else {})
	if _banner != null:
		_banner.text = "the bot has forgotten you"
		_banner.visible = true
		get_tree().create_timer(1.6).timeout.connect(_hide_banner)


# ------------------------------------------------------- duel: observation
## WATCH THE HUMAN. Everything sampled here is read off a drawn thing — two
## positions, whether a guard ring is up, whether the feet are on the floor, how
## much a health bar moved. No inputs, no cooldowns, no intent. See the fairness
## note at the top of `BotAdapt`.
func _observe_duel(delta: float) -> void:
	if _p1 == null or _duel_bot == null:
		return
	if not is_instance_valid(_p1) or not is_instance_valid(_duel_bot):
		return
	if not duel_learning or _learn_rec.is_empty():
		return
	_follow_class_swap()

	var human: CharacterBody2D = _p1 as CharacterBody2D
	var sep: float = human.global_position.distance_to(_duel_bot.global_position)
	var guarding: bool = bool(human.call("is_parrying")) if human.has_method("is_parrying") else false
	var airborne: bool = not human.is_on_floor()
	BotAdapt.observe_tick(_learn_rec, sep, guarding, airborne)

	# --- DODGES. Only filed while something is genuinely coming at them, so a
	# stroll across the stage is never recorded as an evasion habit. Debounced so
	# one break is one observation rather than sixty.
	if _duel_clock >= _dodge_ready_at and _threat_near(human.global_position):
		var vx: float = human.velocity.x
		if absf(vx) >= DODGE_SPEED or airborne:
			_dodge_ready_at = _duel_clock + DODGE_DEBOUNCE
			BotAdapt.observe_dodge(_learn_rec, signf(vx), airborne,
				bool(human.get("is_dashing")))

	_observe_damage()
	_observe_bot_casts()

	_learn_save_at -= delta
	if _learn_save_at <= 0.0:
		_learn_save_at = LEARN_SAVE_PERIOD
		_flush_learning()


## TAB MID-FIGHT RE-KEYS THE LEARNED RECORD.
##
## The record is keyed by the HUMAN'S class on purpose — how you play an Arcanist
## and how you play a Brawler are different problems, and one averaged record
## learns neither. But the maker swaps class mid-duel ("I WANT to be able to swap
## classes like the punch and stuff"), and without this every observation after
## the swap would be filed against the class they just stopped playing: the
## Brawler record would slowly fill with Arcanist spacing.
##
## Banks the outgoing record first, so a swap is a save point like every other
## natural pause.
func _follow_class_swap() -> void:
	if _p1 == null or not is_instance_valid(_p1):
		return
	var now: int = int(_p1.get("_hero_class"))
	if now == _learn_class:
		return
	_flush_learning()
	_learn_class = now
	_learn_rec = BotAdapt.repair_record(BotAdapt.record_for(_learn_store, _learn_class))
	_learn_rec["sessions"] = int(_learn_rec.get("sessions", 0)) + 1
	if _duel_ctrl != null:
		_duel_ctrl.set("adapt", _learn_rec)
	# The credit/punish windows describe the PREVIOUS kit; carrying them across a
	# swap would credit the new class's record with the old one's exchange.
	_credit = {}
	_last_whiff_at = -99.0


## Is a live telegraph or an in-flight projectile close enough to the human to be
## the reason they just moved? Reuses the bot's own perception helper so "what
## counts as a threat" cannot drift between what the bot dodges and what the
## learner thinks you dodged.
func _threat_near(at: Vector2) -> bool:
	for t: Variant in BotController.perceive_threats(get_tree(), at, _p1):
		if not (t is Dictionary):
			continue
		var d: Dictionary = t
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		if at.distance_to(p) <= DODGE_NOTICE_RADIUS + float(d.get("radius", 0.0)):
			return true
	return false


## Health bars, both ways. Polled rather than signal-driven because `Hero` has no
## took-damage signal — only `health_changed`, which also fires on heals and on
## the round reset, so a listener would file a respawn as a 260-point hit.
func _observe_damage() -> void:
	var human_hp: int = int(_p1.get("hp"))
	var bot_hp: int = int(_duel_bot.get("hp"))
	# Round resets refill both bars; a RISE is never damage.
	var human_drop: int = _human_hp_last - human_hp
	var bot_drop: int = _bot_hp_last - bot_hp
	_human_hp_last = human_hp
	_bot_hp_last = bot_hp

	if human_drop > 0:
		# The bot connected. Credit the slot it committed if one is still inside
		# its window; otherwise it was a fist or a basic bolt and only the total
		# is recorded.
		if not _credit.is_empty() and _duel_clock - float(_credit["at"]) <= CREDIT_WINDOW:
			BotAdapt.observe_bot_hit(_learn_rec, int(_credit["slot"]), human_drop)
			_credit = {}
		else:
			_learn_rec["bot_damage"] = int(_learn_rec.get("bot_damage", 0)) + human_drop
	if bot_drop > 0:
		# Did this land while the bot was recovering from a whiff? That is the
		# "do they punish a mistake" read, and it is the term that talks the bot
		# out of long channels against a player who does.
		var punished: bool = _duel_clock - _last_whiff_at <= PUNISH_WINDOW
		BotAdapt.observe_human_damage(_learn_rec, bot_drop, punished)
		if punished:
			_last_whiff_at = -99.0   # one punish per whiff, not one per tick of a beam


## Watch the bot's OWN presses through the controller it is driven by, and expire
## a credit that never landed into a whiff.
func _observe_bot_casts() -> void:
	if _duel_ctrl != null:
		var i: Variant = _duel_ctrl.get("intent")
		if i is Dictionary:
			var slot: int = int((i as Dictionary).get("cast_slot", -1))
			# The brain latches a cast for CAST_LATCH, so the press is emitted on
			# exactly one frame — but only file a NEW credit when the previous one
			# has resolved, or a fast rotation would overwrite an in-flight meteor.
			if slot >= 0 and _credit.is_empty():
				_credit = {"slot": slot, "at": _duel_clock}
				BotAdapt.observe_bot_cast(_learn_rec, slot)
	if not _credit.is_empty() and _duel_clock - float(_credit["at"]) > CREDIT_WINDOW:
		BotAdapt.observe_bot_whiff(_learn_rec)
		_last_whiff_at = _duel_clock
		_credit = {}


## Hand a hero the game's own bot stack. Every piece is load()ed at runtime and
## every step is guarded, so a roster where one of the three modules has not
## landed yet produces a hero that simply stands still rather than a crash.
func _attach_bot(hero: CharacterBody2D, tier: int = -1) -> void:
	if not FileAccess.file_exists(BOT_CONTROLLER_SCRIPT):
		return
	var ctrl_script: GDScript = load(BOT_CONTROLLER_SCRIPT) as GDScript
	if ctrl_script == null:
		return
	var ctrl: RefCounted = ctrl_script.new()
	if FileAccess.file_exists(BOT_BRAIN_SCRIPT):
		ctrl.set("brain", load(BOT_BRAIN_SCRIPT))
	if FileAccess.file_exists(BOT_PROFILE_SCRIPT):
		var prof: GDScript = load(BOT_PROFILE_SCRIPT) as GDScript
		if prof != null and prof.has_method("of"):
			ctrl.set("profile", prof.call("of", showcase_difficulty if tier < 0 else tier))
	hero.set("controller", ctrl)
	_duel_ctrl = ctrl


## Registry seam (also driven by the headless test): every fighter enters the
## match with STOCKS stocks, its own
## respawn point, and no invuln.
func _register_fighter(body: Node2D, spawn: Vector2, stocks: int = STOCKS) -> void:
	_registry[body.get_instance_id()] = {
		"node": body,
		"stocks": stocks,
		"spawn": spawn,
		"invuln": 0.0,
	}


# ------------------------------------------------------------------------- HUD
## Screen-space HUD: the AbilityBar hotbar (self-finds the hero via group), a
## top-left stocks readout, and the hidden match-over banner.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60  # AbilityBar's home per Arena.gd — below Conversation (100)
	add_child(layer)
	# SHOWCASE: no chrome. The ability hotbar and the touch pad belong to a PLAYED
	# arena; in a clip they are bands of UI covering the fight and a hotbar reading
	# out cooldowns for a hero nobody is holding. The banner is kept — it is the only
	# element that says anything about the duel.
	if _is_showcase():
		_build_showcase_banner(layer)
		_build_pause_overlay(layer)
		return
	if _is_free():
		_build_free_hud(layer)
		return
	_build_duel_hud(layer)


## FREE PLAY's chrome: your hotbar, the touch pad, the pause menu, and a banner the
## `FreePlay` layer writes into. Everything ELSE that belongs to free play — the
## controls card, the class picker, the dummy count — is built by `FreePlay.gd`, so
## this file stays the STAGE and that one stays the MODE.
func _build_free_hud(layer: CanvasLayer) -> void:
	layer.add_child(AbilityBar.new())
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 64.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.12, 0.95))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.visible = false
	layer.add_child(_banner)
	_build_pause_overlay(layer)
	add_child(TouchControls.new())


## Flash a line across the top of a free-play session — "ARCANIST", "stage reset".
## Public because `FreePlay.gd` is the thing with something to say.
func flash_banner(text: String, seconds: float = 1.2) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.visible = true
	get_tree().create_timer(seconds).timeout.connect(_hide_banner)


## The only HUD a showcase keeps: the match-over banner, and a small corner card
## naming the two classes so a viewer knows what they are watching.
func _build_showcase_banner(layer: CanvasLayer) -> void:
	var card := Label.new()
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.offset_left = 16.0
	card.offset_top = 12.0
	card.add_theme_font_size_override("font_size", 18)
	card.add_theme_color_override("font_color", Color(0.96, 0.96, 1.0, 0.92))
	card.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.09, 0.95))
	card.add_theme_constant_override("outline_size", 6)
	card.text = "%s  vs  %s" % [_class_label(showcase_a), _class_label(showcase_b)]
	layer.add_child(card)
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 56.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.12, 0.95))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.visible = false
	layer.add_child(_banner)


## Class id -> the name the design doc uses (HeroClass.MAGE is the Arcanist).
func _class_label(id: int) -> String:
	var names: Array[String] = [
		"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
		"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
	]
	return names[id] if id >= 0 and id < names.size() else "?"


## THE SHOWCASE CAMERA — the fix for the failure mode every capture tool in this
## project has shipped at least once: the payoff landing off the edge of frame.
##
## Neither hero's own Camera2D can do this job. It follows ONE body, so the moment
## the fight spreads the other fighter leaves the shot, and its limits are tuned
## for a player who is always the centre of attention. This one frames the PAIR:
## it sits on their midpoint and zooms to whatever keeps both inside the frame
## with a margin, so a duel that roams the whole stage stays readable.
## THE CAMERA OPERATOR, built for EVERY versus mode and not just for the clip tools.
##
## ⚠ WITHOUT ONE, EVERY `Juice.*_camera` CALL IN THIS SCENE IS A SILENT NO-OP — no
## shake on a hit, no punch on a kill, no pull-back on an ult — which is a large part
## of what "the camera does not follow the fight" feels like. `Juice` walks the
## `combat_camera` group behind `has_method` guards, the only class implementing those
## methods is `CombatCamera` (which lives on the HERO scene), and every versus mode
## turns both hero cameras off and frames with a bare `Camera2D` that is in no group.
## So the group was two disabled cameras and the visible one answered to nothing.
##
## `frames_the_shot` is what separates the two jobs. Watch Bots / clip capture hand the
## director the whole shot; a played duel and free play keep their own tuned framing in
## `_update_showcase_camera` / `_update_free_camera` and take only the effects, through
## `ClipDirector.compose`. Either way there is exactly ONE writer per channel.
func _build_camera_operator(directed: bool) -> void:
	if _clip != null or _show_cam == null:
		return
	_clip = ClipDirector.new()
	_clip.frames_the_shot = directed
	add_child(_clip)
	_clip.bind(_show_cam, Rect2(Vector2.ZERO, STAGE_SIZE), GROUND_TOP)


func _build_showcase_camera() -> void:
	_show_cam = Camera2D.new()
	_show_cam.zoom = Vector2(0.62, 0.62)
	_show_cam.position_smoothing_enabled = true
	_show_cam.position_smoothing_speed = SHOWCASE_FOLLOW_SPEED
	add_child(_show_cam)
	_show_cam.make_current()


## Track the pair. Called every frame from _process.
## WHO THE PORTRAIT CAMERA IS WITH. Scores every live fighter on how recently the
## fight happened TO them, decays it, and hands back the leader — with hysteresis, so
## the answer is stable enough to point a camera at.
##
## ⚠ IT IS CALLED EVERY FRAME, INCLUDING WHEN THE PAIR IS CLOSED AND NOBODY IS ASKING
## WHO THE SUBJECT IS. That is deliberate: interest has to have been accruing BEFORE
## the fighters separate, or the first frame of every single would pick whoever
## happened to be first in the registry and then correct itself in front of the
## viewer.
##
## Damage is inferred from HP falling rather than from a signal, because every hit
## path in this game already ends in HP and none of them reports to the camera. That
## also means it is immune to a new spell forgetting to tell anybody.
func _portrait_subject(live: Array[Node2D], delta: float) -> Node2D:
	var decay: float = maxf(0.0, 1.0 - PORTRAIT_INTEREST_DECAY * delta)
	for key: int in _cam_interest.keys():
		_cam_interest[key] = float(_cam_interest[key]) * decay

	# Score the frame's damage. In a duel the dealer is "the other one", which is why
	# this does not need to know who swung.
	for n: Node2D in live:
		var id: int = n.get_instance_id()
		var hp: Variant = n.get("hp")
		if hp == null:
			continue
		var now: float = float(hp)
		if _cam_hp.has(id):
			var drop: float = float(_cam_hp[id]) - now
			if drop > 0.0:
				_cam_interest[id] = float(_cam_interest.get(id, 0.0)) \
					+ PORTRAIT_INTEREST_VICTIM
				for other: Node2D in live:
					var oid: int = other.get_instance_id()
					if oid != id:
						_cam_interest[oid] = float(_cam_interest.get(oid, 0.0)) \
							+ PORTRAIT_INTEREST_DEALER
		_cam_hp[id] = now

	_cam_subject_dwell += delta

	# The incumbent, if it is still alive.
	var current: Node2D = null
	for n: Node2D in live:
		if n.get_instance_id() == _cam_subject_id:
			current = n
			break

	# The challenger.
	var best: Node2D = null
	var best_score: float = -1.0
	for n: Node2D in live:
		var s: float = float(_cam_interest.get(n.get_instance_id(), 0.0))
		if s > best_score:
			best_score = s
			best = n

	if current == null:
		# Nobody in the chair (first frame, or the subject died). Take the leader, or
		# just the first live body — anything is better than null, which would drop
		# the shot back to the midpoint mid-fight.
		var pick: Node2D = best if best != null else live[0]
		_cam_subject_id = pick.get_instance_id()
		_cam_subject_dwell = 0.0
		return pick

	if best == null or best == current:
		return current
	# Both gates, and either alone is insufficient: the margin stops a trade from
	# flipping the shot, the dwell stops a sustained beating from flipping it every
	# frame once the margin is exceeded.
	var cur_score: float = float(_cam_interest.get(_cam_subject_id, 0.0))
	if best_score > cur_score + PORTRAIT_SWITCH_MARGIN \
			and _cam_subject_dwell >= PORTRAIT_SUBJECT_DWELL:
		_cam_subject_id = best.get_instance_id()
		_cam_subject_dwell = 0.0
		return best
	return current


func _update_showcase_camera(delta: float) -> void:
	if _show_cam == null:
		return
	# The director owns the camera when it is FRAMING. Two things writing the same
	# transform in the same frame is a fight the director always half-loses, and the
	# result is a camera that judders between two framings. An operator-only director
	# is not a second framer — it never touches position and only lays the shake and
	# the zoom envelopes over the answer solved below.
	if _clip != null and _clip.frames_the_shot:
		return
	var pts: Array[Vector2] = []
	var live: Array[Node2D] = []
	# ⚠ A BODY THAT HAS LEFT THE MAP MUST NOT OWN THE CAMERA. `showcase_ringout` is on
	# by default, so a big enough hit launches a fighter clean off the stage — and the
	# framer averaged its position in all the way out. One measured run framed on the
	# midpoint between a live fighter and a body somewhere past x=5000: the pair's
	# "midpoint" sat 1100 screen px off centre and SOMEBODY WAS OFF SCREEN FOR 55% OF
	# THE FIGHT. Both the focus and the spread (and therefore the zoom) were being
	# decided by a fighter nobody could see.
	#
	# So: frame on the bodies that are inside the painted world. If every body has left
	# it — the instant between the last ring-out and the rematch — keep them all, so the
	# camera still points at something rather than snapping to a default.
	for entry: Dictionary in _registry.values():
		var n: Node = entry["node"]
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			pts.append((n as Node2D).global_position)
			live.append(n as Node2D)
	if pts.is_empty():
		return
	var on_map: Array[Vector2] = []
	var on_map_live: Array[Node2D] = []
	for i: int in pts.size():
		if pts[i].x >= BACKDROP_X0 and pts[i].x <= BACKDROP_X1:
			on_map.append(pts[i])
			on_map_live.append(live[i])
	if not on_map.is_empty():
		pts = on_map
		live = on_map_live
	var mid: Vector2 = Vector2.ZERO
	for p: Vector2 in pts:
		mid += p
	mid /= float(pts.size())
	var spread: float = 0.0
	for p: Vector2 in pts:
		spread = maxf(spread, absf(p.x - mid.x) * 2.0)
	# Zoom so the separation plus a generous margin spans the viewport width. The
	# margin is what leaves room for a beam or a meteor column to land INSIDE the
	# frame rather than half off it.
	var view: Vector2 = get_viewport().get_visible_rect().size
	var view_w: float = float(view.x)
	# PORTRAIT takes its own margin and ceiling — see the block on
	# SHOWCASE_FRAME_MARGIN_PORTRAIT for why the landscape numbers are not merely
	# suboptimal in a tall frame but wrong. Detected from the viewport rather than
	# from a flag so the clip tool, a phone export and a resized window all agree
	# without anyone having to remember to set something.
	var portrait: bool = view.y > view.x
	var margin: float = SHOWCASE_FRAME_MARGIN_PORTRAIT if portrait else _cam_margin
	var zoom_max: float = SHOWCASE_ZOOM_MAX_PORTRAIT if portrait else _cam_zoom_max
	var want: float = clampf(view_w / maxf(spread + margin, 1.0),
		_cam_zoom_min, zoom_max)
	# FOLLOW THE ACTION once the pair opens up — see PORTRAIT_TWO_SHOT_COMFORT. The
	# focus point and the zoom both lerp on one continuous weight, so the shot slides
	# from a two-shot into a single instead of cutting.
	var focus: Vector2 = mid
	if portrait:
		var follow: float = smoothstep(PORTRAIT_TWO_SHOT_COMFORT,
			PORTRAIT_TWO_SHOT_MAX, spread)
		if follow > 0.0:
			var subject: Node2D = _portrait_subject(live, delta)
			if subject != null:
				focus = mid.lerp(subject.global_position, follow)
				want = lerpf(want, PORTRAIT_FOLLOW_ZOOM, follow)
		else:
			# Still score interest while they are together, so the moment they part
			# the camera already knows who it is going with rather than picking on
			# the first frame it needs an answer.
			_portrait_subject(live, delta)
	# The FRAMING answer is smoothed on its own state, then the operator's transient
	# effects are laid over it. Reading the punched zoom back as the next frame's
	# starting point would let a zoom punch drag the actual framing in with it.
	_cam_zoom_smoothed = lerpf(_cam_zoom_smoothed, want, clampf(delta * 2.5, 0.0, 1.0))
	var z: float = _cam_zoom_smoothed
	if _clip != null:
		z = _clip.compose(z, delta)
	_show_cam.zoom = Vector2(z, z)
	# Bias UP from the midpoint: the fighters stand ON the ground, so centring on
	# them puts half the frame underground. Lifting the eye puts the floor in the
	# lower third and gives the sky back to the spectacle.
	# Clamped to the stage so the camera never drifts far enough for the void under
	# the terrain, or the space past the rim, to fill a third of the shot.
	# ⚠ THE VERTICAL CLAMP IS ANCHORED TO THE GROUND, and that is the whole point.
	# The first version clamped to absolute world y and a fighter launched high
	# dragged the eye up with it — 340 of the 400 captured frames came back as
	# empty sky with no floor and no fighters in them, which is how this was
	# found. Holding the camera within a band ABOVE THE FLOOR means the stage is
	# always in shot no matter how far a knockback throws somebody.
	# ⚠ IN PORTRAIT THE EYE IS ANCHORED TO THE GROUND, NOT LIFTED BY A CONSTANT.
	# `SHOWCASE_EYE_LIFT` is 45 px, which puts the floor around 60% down a 16:9 frame.
	# In a 1280-tall frame the same 45 px left roughly 255 world px of SUB-FLOOR — the
	# void under the terrain and the backdrop repeating beneath it — filling about a
	# third of the shot. Measured off a real 720x1280 render, not estimated.
	#
	# A constant cannot fix that, because the amount of frame below the floor depends
	# on the ZOOM, which the solve above changes every frame. So portrait solves for
	# the camera y that puts the ground line at a fixed FRACTION of frame height:
	#
	#   f = (GROUND_TOP - (cam_y - half_h)) / (2 * half_h)
	#     => cam_y = GROUND_TOP + half_h * (1 - 2f)
	#
	# At PORTRAIT_GROUND_AT = 0.80 and zoom 2.0 that is GROUND_TOP - 192; at zoom 0.95
	# it is GROUND_TOP - 404. Both keep the floor low and the sky — where the sigils,
	# the meteors and the beams live — occupying the frame instead of the basement.
	#
	# `minf` against the old lift so a fighter launched high still pulls the eye up:
	# whichever wants to be HIGHER (smaller y) wins. The clamp band widens in portrait
	# because the landscape band was sized for a 768-tall frame and would otherwise
	# undo the solve at the wide end.
	# `focus`, not `mid` — in portrait these diverge once the pair separates and the
	# camera commits to a subject.
	var eye_y: float = focus.y - SHOWCASE_EYE_LIFT
	var floor_y: float = GROUND_TOP - 30.0
	var ceil_y: float = GROUND_TOP - 330.0
	if portrait:
		var half_h: float = float(view.y) / (2.0 * maxf(z, 0.01))
		eye_y = minf(eye_y, GROUND_TOP + half_h * (1.0 - 2.0 * PORTRAIT_GROUND_AT))
		ceil_y = GROUND_TOP - 560.0
	_show_cam.global_position = Vector2(
		_frame_x(focus.x, z, view_w),
		clampf(eye_y, ceil_y, floor_y))


## Hidden dim overlay with PAUSED + Resume/Reset — toggled by Esc. Lives on the
## ALWAYS HUD layer so its buttons work while the tree is paused.
func _build_pause_overlay(layer: CanvasLayer) -> void:
	_pause_menu = PauseMenu.new()
	layer.add_child(_pause_menu)
	_pause_menu.build("Exit to Hub")
	_pause_menu.resume_requested.connect(func() -> void: _set_paused(false))
	_pause_menu.exit_requested.connect(_exit_to_hub)
	if _is_duel():
		_build_duel_settings()


## THE DUEL'S KNOBS, in the Esc menu instead of over the fight.
##
## MAIN menu: the two things you want in one press — a rematch, and the way into
## the boss. SETTINGS: everything that tunes the sparring partner.
##
## The live/reload split is unchanged and deliberate: Learning and the two
## overlays apply on the spot (reloading to turn a debug readout on would throw
## away the fight you turned it on to look at), while difficulty and the bot's
## class need a fresh bot and therefore reload the scene — which is why every one
## of those knobs is a STATIC.
func _build_duel_settings() -> void:
	_pause_menu.add_action("Fight the Boss", _enter_boss_fight)
	_pause_menu.add_action("Rematch", _reset_arena)

	_pause_menu.add_setting_section("Bot Duel")
	_duel_labels["difficulty"] = _pause_menu.add_setting_button(
		"Difficulty: %s" % _duel_difficulty_name(), _cycle_duel_difficulty)
	_duel_labels["botclass"] = _pause_menu.add_setting_button(
		"Bot class: %s" % _class_label(duel_bot_class), _cycle_duel_bot_class)
	_duel_labels["learning"] = _pause_menu.add_setting_button(
		"Learning: %s" % ("ON" if duel_learning else "OFF"), _toggle_duel_learning)
	_duel_labels["show"] = _pause_menu.add_setting_button(
		"Show learned: %s" % ("ON" if duel_show_learning else "OFF"), _toggle_duel_show_learning)
	_duel_labels["intent"] = _pause_menu.add_setting_button(
		"Bot intent: %s" % ("ON" if duel_show_intent else "OFF"), _toggle_duel_show_intent)
	_pause_menu.add_setting_button("Forget me", _forget_learning)


## STRAIGHT TO THE ASHSPIRE GUARDIAN. The boss otherwise costs a full four-floor
## climb to reach, which is not a way to TEST it — so this drops the maker into
## the tower Arena with the guardian already on the stage (see Arena.boss_rush).
## The learned record is banked first: leaving a fight is a save point.
func _enter_boss_fight() -> void:
	_flush_learning()
	_probe_finish()
	# BY PATH, never by `class_name Arena`: naming the class here would compile
	# Arena.gd (and its autoload-referencing chain) whenever THIS script is
	# load()ed by a headless `--script` harness, where no autoload is registered.
	# Same reason the capture tools reach this scene by path. (_attach_bot idiom.)
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script != null:
		arena_script.set("boss_rush", true)
	get_tree().paused = false
	get_tree().change_scene_to_file(ARENA_SCENE)


## Leave the versus sandbox to the TITLE screen. Unpause first so the fresh scene
## doesn't inherit the paused tree.
##
## ⚠ IT USED TO GO TO `res://scenes/Main.tscn` — the PARKED v0.0 village.
## Maker, on finding himself there: *"why is the hub still around, what do I do
## there"*. Nothing, is the answer: it is a different game's town, and arriving in
## it by accident is the only way anyone was
## reaching it. The title screen is the boot scene and works on a phone. The hub is
## still on disk and still reachable deliberately from the run-summary card.
func _exit_to_hub() -> void:
	# Leave the Smash model behind so a subsequent tower run is never stuck in
	# ring-out mode (enter_run also forces this off — belt + suspenders).
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("ringout_mode", false)
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


## Full arena reset — reload the scene so cover, bots, stocks + the match state
## all rebuild from scratch. Bound to the Reset Map button.
func _reset_arena() -> void:
	get_tree().paused = false  # don't carry the pause into the fresh scene
	get_tree().reload_current_scene()


# ================================================================== DUEL HUD
## THE PLAY HUD IS NOW CLEAN. Everything that used to be a right-hand column of
## buttons over the fight — difficulty, the bot's class, learning, the two debug
## overlays, forget, rematch — moved into the Esc pause menu's Settings panel at
## maker request ("all those settings should be in the settings when I press
## escape"). What is left on screen while you play: your hotbar, the score line,
## the two overlays you deliberately turned on, and the round banner.
func _build_duel_hud(layer: CanvasLayer) -> void:
	layer.add_child(AbilityBar.new())   # your own hotbar — you are playing this one

	# Who is fighting whom, top-left, plus the live round state.
	_stocks_label = Label.new()
	_stocks_label.position = Vector2(14, 10)
	_stocks_label.add_theme_font_size_override("font_size", 13)
	_stocks_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 0.95))
	_stocks_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_stocks_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_stocks_label)

	# THE INSPECTION HALF of "resettable and inspectable": everything the bot has
	# learned about you, in words, refreshed live. Off by default.
	_learn_label = Label.new()
	_learn_label.position = Vector2(14, 34)
	_learn_label.add_theme_font_size_override("font_size", 11)
	_learn_label.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0, 0.92))
	_learn_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.09, 0.9))
	_learn_label.add_theme_constant_override("outline_size", 3)
	_learn_label.visible = duel_show_learning
	layer.add_child(_learn_label)
	# Both duel readouts are instruments, so cinematic mode takes them off the screen.
	# `Cinematic.mark` stashes and restores the pre-cinematic state, so leaving the mode
	# does NOT turn a toggle the maker had switched off back on.
	Cinematic.mark(_learn_label)

	# What the bot is doing THIS FRAME — the readable-opponent requirement. Bottom
	# centre so it never sits over either fighter.
	_intent_label = Label.new()
	_intent_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_intent_label.offset_top = -74.0
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.add_theme_font_size_override("font_size", 12)
	_intent_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62, 0.95))
	_intent_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.95))
	_intent_label.add_theme_constant_override("outline_size", 4)
	_intent_label.visible = duel_show_intent
	layer.add_child(_intent_label)
	Cinematic.mark(_intent_label)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 64.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.12, 0.95))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.visible = false
	layer.add_child(_banner)
	_build_pause_overlay(layer)
	add_child(TouchControls.new())


func _duel_difficulty_name() -> String:
	var names: Array = ["Easy", "Normal", "Hard", "Impossible"]
	return String(names[clampi(duel_difficulty, 0, 3)])


## The knobs. Difficulty and class both need a fresh bot, so they reload; the
## three toggles are applied live, because reloading to turn a debug overlay on
## would throw away the fight you turned it on to look at.
func _cycle_duel_difficulty() -> void:
	_flush_learning()
	duel_difficulty = (duel_difficulty + 1) % 4
	get_tree().paused = false
	get_tree().reload_current_scene()


func _cycle_duel_bot_class() -> void:
	_flush_learning()
	duel_bot_class = (duel_bot_class + 1) % 9   # Hero.HeroClass has nine members
	get_tree().paused = false
	get_tree().reload_current_scene()


func _toggle_duel_learning() -> void:
	duel_learning = not duel_learning
	# Applied to the live bot immediately: handing it an EMPTY record is exactly
	# what "off" means — `BotAdapt` treats an empty record as no adaptation at all,
	# so the bot reverts to the stock difficulty tier the same frame.
	if _duel_ctrl != null:
		_duel_ctrl.set("adapt", _learn_rec if duel_learning else {})
	if _duel_labels.has("learning"):
		(_duel_labels["learning"] as Button).text = "Learning: %s" % ("ON" if duel_learning else "OFF")


func _toggle_duel_show_learning() -> void:
	duel_show_learning = not duel_show_learning
	if _learn_label != null:
		_learn_label.visible = duel_show_learning and Cinematic.shows_chrome()
	if _duel_labels.has("show"):
		(_duel_labels["show"] as Button).text = "Show learned: %s" % ("ON" if duel_show_learning else "OFF")


func _toggle_duel_show_intent() -> void:
	duel_show_intent = not duel_show_intent
	if _intent_label != null:
		_intent_label.visible = duel_show_intent and Cinematic.shows_chrome()
	if _duel_labels.has("intent"):
		(_duel_labels["intent"] as Button).text = "Bot intent: %s" % ("ON" if duel_show_intent else "OFF")


## Refresh the two live overlays. Poll-don't-push, the AbilityBar idiom: always
## current, and no signal to forget to disconnect.
func _update_duel_overlays() -> void:
	if _learn_label != null and _learn_label.visible:
		_learn_label.text = "\n".join(BotAdapt.summary_lines(_learn_rec))
	if _intent_label != null and _intent_label.visible and _duel_ctrl != null:
		_intent_label.text = _describe_intent()


## The bot's current intent in one readable line — the "show what it is doing"
## requirement. Names the SLOT ROLE rather than the index, because "payoff" tells
## you what is about to happen and "3" does not.
func _describe_intent() -> String:
	var i: Variant = _duel_ctrl.get("intent")
	if not (i is Dictionary):
		return ""
	var d: Dictionary = i
	var parts: PackedStringArray = PackedStringArray()
	var slot: int = int(d.get("cast_slot", -1))
	if slot >= 0:
		var roles: Array[String] = ["damage", "control", "answer", "payoff", "ULT"]
		var name: String = roles[slot] if slot < roles.size() else str(slot)
		var spell: Variant = _duel_bot.call("signature_at", slot) if _duel_bot != null \
			and _duel_bot.has_method("signature_at") else null
		# `.get()` on a missing property returns null, and `String(null)` renders as
		# "<null>" rather than throwing — so the name is only used when it is one.
		var pretty: Variant = spell.get("display_name") if spell != null else null
		if pretty is String and String(pretty) != "":
			name = "%s (%s)" % [String(pretty), name]
		parts.append("CAST %s" % name)
	if bool(d.get("guard", false)):
		parts.append("GUARD")
	if bool(d.get("dash", false)):
		parts.append("DASH")
	if bool(d.get("jump", false)):
		parts.append("JUMP")
	if bool(d.get("fire", false)):
		parts.append("swing")
	var move: Vector2 = d.get("move", Vector2.ZERO)
	if absf(move.x) > 0.01:
		parts.append("move %s" % ("<-" if move.x < 0.0 else "->"))
	if parts.is_empty():
		parts.append("holding")
	return "BOT: " + "  |  ".join(parts)


# ================================================================ LIVE PROBE
## PLAY THE GAME, FIND THE BUGS. The headless sim's detectors are pure predicates
## in `BotSimProbe`; the duel runs the same ones over the frames the maker is
## actually playing and writes the same machine-readable report, so a session at
## the keyboard produces the same artefact a batch run does.
func _probe_begin() -> void:
	if not FileAccess.file_exists(PROBE_SCRIPT):
		return   # tools script absent — never a reason to stop the maker playing
	_probe = load(PROBE_SCRIPT) as GDScript
	_findings.clear()
	_finding_seen.clear()
	_probe_hp_trail.clear()


## One frame of checks over both fighters and every live projectile.
func _probe_tick(_delta: float) -> void:
	if _probe == null:
		return
	for entry: Dictionary in _registry.values():
		var n: Variant = entry["node"]
		if n == null or not is_instance_valid(n) or not (n is Node2D):
			continue
		_probe_body(n as Node2D)
	for n: Node in get_tree().get_nodes_in_group("player_spell"):
		if not (n is Node2D):
			continue
		var p: Vector2 = (n as Node2D).global_position
		if bool(_probe.call("position_is_broken", p)):
			_file_finding("error", "spell_nan_position", "spell",
				"a projectile reached a non-finite position %s" % p)
			n.queue_free()
		elif _under_terrain(p):
			_file_finding("error", "spell_below_floor", "spell",
				"a projectile resolved inside the terrain at %s" % p)
	_probe_stalemate()


## Per-body world integrity. NaN first, because a broken coordinate makes every
## geometric test after it meaningless.
func _probe_body(node: Node2D) -> void:
	var pos: Vector2 = node.global_position
	var label: String = "you" if node == _p1 else "bot"
	if bool(_probe.call("position_is_broken", pos)):
		_file_finding("error", "nan_position", label,
			"%s reached a non-finite position %s" % [label, pos])
		node.global_position = Vector2(DUEL_SPAWN_HUMAN.x, GROUND_TOP - 60.0)
		return
	if _under_terrain(pos):
		_file_finding("error", "body_below_floor", label,
			"%s is inside the terrain at %s (rock bottom y=%.1f)"
				% [label, pos, PROBE_FLOOR_Y])
	var hp: int = int(node.get("hp"))
	var mx: int = int(node.get("max_hp"))
	if bool(_probe.call("hp_out_of_range", hp, mx)):
		_file_finding("error", "hp_out_of_range", label,
			"%s hp=%d outside [0, %d]" % [label, hp, mx])


## ⚠ THE X GATE IS THE WHOLE POINT, and it is what the headless run was missing.
##
## This stage has no floor past its rims — that IS the ring-out, the central
## mechanic. A fighter falling off the left edge is not "falling through the
## floor", it is losing a stock, and reporting it as a world bug buries the real
## ones. So the check applies only OVER the rock, and "below" means below the
## BOTTOM of the terrain colliders, not below their walkable surface.
func _under_terrain(pos: Vector2) -> bool:
	if pos.x < PROBE_TERRAIN_X0 or pos.x > PROBE_TERRAIN_X1:
		return false
	return pos.y > PROBE_FLOOR_Y


## Nothing is happening. A stalemate between a human and a bot is not a softlock,
## but it IS the exact behavioural gap the headless run found between two ranged
## bots, so it is worth a row when it happens to a person too.
func _probe_stalemate() -> void:
	var total: int = 0
	for entry: Dictionary in _registry.values():
		var n: Variant = entry["node"]
		if n != null and is_instance_valid(n):
			total += int((n as Node).get("hp"))
	_probe_hp_trail.append({"t": _duel_clock, "total": total})
	while _probe_hp_trail.size() > 2 \
			and float(_probe_hp_trail[0]["t"]) < _duel_clock - 12.0:
		_probe_hp_trail.pop_front()
	var span: float = _duel_clock - float(_probe_hp_trail[0]["t"])
	var movement: int = absi(int(_probe_hp_trail[0]["total"]) - total)
	if bool(_probe.call("stalemate", movement, span, 12.0)):
		_file_finding("warn", "stalemate", "match",
			"no HP moved in %.1fs (total stayed at %d)" % [span, total])
		_probe_hp_trail.clear()


## ONE FINDING IS ONE ROW — but a per-frame detector fires per frame, so an event
## that lasts a second is sixty identical rows unless something collapses them.
## Identical kind+subject inside PROBE_DEDUP_WINDOW increments a count on the
## existing row instead of appending. Without this the report says "329
## body_below_floor" when what happened was one fighter falling once.
func _file_finding(severity: String, kind: String, label: String,
		detail: String) -> void:
	var key: String = "%s|%s" % [kind, label]
	if _finding_seen.has(key):
		var prev: Dictionary = _finding_seen[key]
		if _duel_clock - float(prev["at"]) <= PROBE_DEDUP_WINDOW:
			prev["at"] = _duel_clock
			var row: Dictionary = prev["row"]
			row["repeats"] = int(row.get("repeats", 1)) + 1
			return
	var anomaly: Dictionary = _probe.call("anomaly", kind, severity,
		"duel:%s vs %s" % [_class_label(_learn_class), _class_label(duel_bot_class)],
		0, _duel_clock, detail, {"tier": _duel_difficulty_name()})
	anomaly["repeats"] = 1
	_findings.append(anomaly)
	_finding_seen[key] = {"at": _duel_clock, "row": anomaly}
	# Loud in the console too. A report the maker has to remember to go and read
	# is a report that goes unread; a line in the output while they play is not.
	print("[duel-probe] %s %s: %s" % [severity, kind, detail])


## Write the session's findings out in the same JSON + CSV shape the headless run
## produces, so `python-tools/bot_sim_report.py` aggregates a played session and a
## batch run side by side.
func _probe_finish() -> void:
	if _probe == null or _findings.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(LIVE_REPORT_DIR)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var payload: Dictionary = {
		"source": "duel",
		"human_class": _class_label(_learn_class),
		"bot_class": _class_label(duel_bot_class),
		"difficulty": _duel_difficulty_name(),
		"duration": snappedf(_duel_clock, 0.01),
		"anomalies": _findings,
		"summary": _probe.call("summarize", _findings),
	}
	var f: FileAccess = FileAccess.open("%s/duel-%s.json" % [LIVE_REPORT_DIR, stamp],
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
	var rows: PackedStringArray = PackedStringArray([String(_probe.call("csv_header"))])
	for a: Dictionary in _findings:
		rows.append(String(_probe.call("csv_row", a)))
	var c: FileAccess = FileAccess.open("%s/duel-%s.csv" % [LIVE_REPORT_DIR, stamp],
		FileAccess.WRITE)
	if c != null:
		c.store_string("\n".join(rows))
		c.close()
	print("[duel-probe] wrote %d finding(s) to %s" % [_findings.size(), LIVE_REPORT_DIR])


## Leaving the scene by ANY route — the pause menu, the window close, a mode
## switch — banks the learned record and the findings. `_exit_tree` rather than a
## per-button call because there are five ways out of this scene and four of them
## would eventually be forgotten.
func _exit_tree() -> void:
	if not _is_duel():
		return
	_flush_learning()
	_probe_finish()


func _update_hud() -> void:
	if _stocks_label == null:
		return
	if _is_duel():
		var you: int = int(_p1.get("hp")) if _p1 != null and is_instance_valid(_p1) else 0
		var bot: int = int(_duel_bot.get("hp")) if _duel_bot != null and is_instance_valid(_duel_bot) else 0
		_stocks_label.text = "YOU %d    BOT (%s, %s) %d" % [
			you, _class_label(duel_bot_class), _duel_difficulty_name(), bot]
		return
	# Showcase: the corner card already names the two classes; nothing to poll.
