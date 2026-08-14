class_name StageLayers
extends RefCounted
## THE ONE PLACE THE STAGE'S Z-ORDER AND ITS VISUAL GRAMMAR ARE WRITTEN DOWN.
##
## ⚠ WHY THIS FILE EXISTS. `ArenaTerrain` (-6) and `RuinPlatform` (-4) each set a
## z_index and each explained the scheme in a comment. Three other stage drawers —
## `BreakablePlatform`, `DestructibleTerrain`, `StageHazard` — set NONE, so they
## defaulted to 0: the fighters' own layer. The maker played it and reported that he
## could not see the game. A convention that lives in two comments is not a
## convention; a fourth drawer will always miss it. So it lives here, as data, and
## `tools/slice_test_stage_layers.gd` fails the build if a stage drawer is not in
## `DRAWERS` or does not park itself where `DRAWERS` says.
##
## ADDING A STAGE DRAWER? Two lines: `StageLayers.apply(self, StageLayers.<SLOT>)`
## in `_ready`, and an entry in `DRAWERS`. The test will tell you if you forget.
##
## ------------------------------------------------------------------ THE LADDER
## Everything the player fights ON is NEGATIVE. Fighters own 0. Nothing that is
## scenery may ever sit at 0 — that is the whole bug this table closes.
##
##   -30  SKY        the gradient backdrop
##   -22  SKYLINE    Atmosphere itself (its spire _draw; hazed, see below)
##   -21  MOTES      drifting ambient dust
##   -18  MOUNTAIN   MountainMass, the big near-background landform
##   -10  BACKDROP   a room's opaque floor/wall wash (the tower Arena's Floor rect)
##    -6  TERRAIN    ArenaTerrain / RoomShell — the ground you start on
##    -5  HAZARD     StageHazard — a pit is a HOLE IN the ground, so it sits in it
##    -4  PLATFORM   RuinPlatform / BreakablePlatform — the ledges you jump to
##    -3  COVER      DestructibleTerrain / DestructibleFloor / DestructibleProp
##    -1  DEBRIS     scorch decals, breakaway chunks, rubble
##     0  FIGHTER    heroes, enemies, bosses — RESERVED
const SKY: int = -30
const SKYLINE: int = -22
const MOTES: int = -21
const MOUNTAIN: int = -18
const BACKDROP: int = -10
const TERRAIN: int = -6
const HAZARD: int = -5
## ⚠ THE SAME RUNG AS `HAZARD`, DELIBERATELY, AND THE PRECEDENT IS TWO LINES ABOVE:
## `ArenaTerrain` and `RoomShell` share `TERRAIN` because the two stages never coexist.
## Same here. `StageHazard` (a pit) is versus-stage furniture; `FloorDecor` (the tower's
## painted back wall) only ever exists inside a tower floor. Nothing can put one behind
## the other because nothing ever puts them in the same room.
##
## ⚠ AND IT CANNOT GO ANY FURTHER BACK, which is the real reason for the sharing.
## `RoomShell` paints the tower room's air as an OPAQUE rect on `TERRAIN` (-6), so every
## rung behind it — BACKDROP, and the unused -9/-8/-7 — is invisible INSIDE the room.
## -5 is the first rung a back wall can occupy and still be seen, and it is still behind
## every ledge (-4), every crate (-3) and every fighter (0), which is all a backdrop has
## to be. Anyone tempted to "tidy" this to -7 should draw a floor and look at it first.
const DECOR: int = -5
const PLATFORM: int = -4
const COVER: int = -3
const DEBRIS: int = -1
const FIGHTER: int = 0

## Every stage drawer, and where it must park. Keyed by script BASENAME (these
## classes are reached by path in half the codebase, so a name is the stable key).
## The test walks `scripts/combat/` and requires every StaticBody2D that owns a
## `_draw` to appear here — which is what stops a fourth drawer defaulting to 0.
const DRAWERS: Dictionary = {
	## ⚠ NOT FOUND BY THE SCANNER, AND THAT IS WHY IT BROKE. The scanner in
	## `slice_test_stage_layers` matches `extends StaticBody2D` — `Atmosphere` is a
	## Node2D, so it was invisible to the one rule that catches a drawer defaulting to
	## z 0, and it duly defaulted to z 0. Its `_draw` painted two rows of tall spires
	## across every tower floor, IN FRONT of the fight; the maker called them "weird
	## blinds covering the front of the map that should be background". Listing it here
	## makes rule 1 (a registered drawer must park where the table says) cover it.
	"Atmosphere": SKYLINE,
	## Same reason as Atmosphere: a Node2D, so the scanner cannot see it, so listing
	## it here is the only thing that makes "parks itself where the table says" a
	## build failure rather than a comment.
	##
	## ⚠ IT SHARES `DECOR` WITH `FloorDecor` ON PURPOSE, and the pairing is ordered by
	## TREE ORDER rather than by z. The sky is an OPENING cut into the wall that
	## FloorDecor paints, so it has to land ON TOP of that wall — `Arena._apply_sky`
	## therefore adds it after `_apply_decor`. The alternative rung, -2, is the only
	## other visible one in a tower room and it sits in FRONT of PLATFORM and COVER,
	## which would put the sky over the ledges and the crates.
	"SkyVista": DECOR,
	"ArenaTerrain": TERRAIN,
	## The tower's ground + room frame. Same rung as `ArenaTerrain` because it is the
	## same thing for the other stage: the surface you start on. The two never coexist
	## — the versus stage builds terraces, the tower builds a shell.
	"RoomShell": TERRAIN,
	"StageHazard": HAZARD,
	"RuinPlatform": PLATFORM,
	"BreakablePlatform": PLATFORM,
	"DestructibleTerrain": COVER,
	## CONTAINER, not a drawer: a Node2D holding StaticBody2D slabs. The SLABS park
	## themselves on this rung; the container must stay at 0, because its children
	## set a RELATIVE z and a non-zero parent would push them a rung too far back.
	"DestructibleFloor": COVER,
	"DestructibleProp": COVER,
}

## Scripts under `scripts/combat/` that LOOK like stage geometry to the scanner
## (a StaticBody2D with a `_draw`) but are not, with the reason. Empty today; it
## exists so that adding one is a deliberate, explained act rather than a quiet
## deletion of the rule.
const NOT_STAGE_GEOMETRY: Dictionary = {}


## Park a stage drawer on its slot. `z_as_relative = false` so a drawer parented
## under something with its own z (a room container, a spawner) still lands on the
## absolute rung the table promises instead of an offset from it.
static func apply(node: CanvasItem, slot: int) -> void:
	if node == null:
		return
	node.z_index = slot
	node.z_as_relative = false


# ============================================================== THE VISUAL GRAMMAR
## THE SECOND HALF OF "I CAN'T SEE THE GAME", and the harder half: layering the
## stage correctly only stops it drawing OVER the fighters. It does not tell the
## player where to jump.
##
## Fighters are procedural BLUE LINES about 31 px tall on a 640x360 canvas. So the
## stage must not answer in the same language: no thin bright blue anything, and no
## detail that competes for the eye at that size. What the stage gets instead is ONE
## learnable legend, three rules, applied by every drawer from these constants:
##
##   1. A BRIGHT WARM CAP ALONG THE TOP EDGE = YOU CAN STAND ON THIS.
##      Ground crust, ruin ledge, breakable ledge, the top of a cover block — all
##      wear the same lit band. It is the only bright horizontal line on the stage,
##      so "where can I land" is answerable in one glance, at any zoom.
##   2. AMBER = IT BREAKS. A breakable ledge's cap is amber instead of stone; a
##      destructible cover block wears amber corner ticks. Same shape, warned colour.
##   3. NEAR-BLACK INSIDE A HARD RED LIP = IT KILLS YOU. Pits, and nothing else.
##
## Everything else — bodies, struts, seams, strata, cracks — is deliberately LOW
## CONTRAST against the wash. Texture is for when you stop and look; the cap is for
## when you are mid-air and have 200 ms.

## The lit cap. Warm and pale so it separates from every blue in the game (sky,
## spires, hero, ice) by HUE as well as by value.
const CAP_LIT: Color = Color(0.92, 0.87, 0.74)
## The cap's shaded half — the band immediately under the lit line, so the top edge
## reads as a lit SURFACE with thickness rather than as a drawn 1 px stroke.
const CAP_CORE: Color = Color(0.66, 0.60, 0.48)
## How tall the whole lit cap is, and the minimum it may shrink to on a thin ledge.
## Measured, not guessed: the tower framing puts a 22 px ledge at roughly 9 px of a
## 360-line canvas, so a fixed 2 px cap disappears there while a fixed 6 px cap eats
## a versus-stage ledge whole. A fraction with a floor survives both.
const CAP_FRACTION: float = 0.30
const CAP_MIN: float = 3.0

## The dark underside every solid thing gets, so its silhouette detaches from the
## floor wash instead of dissolving into it.
const UNDERSIDE: Color = Color(0.10, 0.09, 0.12)
## Silhouette stroke. Near-black, never pure black — pure black reads as a hole,
## and holes are rule 3.
const EDGE_DARK: Color = Color(0.07, 0.06, 0.09, 0.9)

## Rule 2. The one warning colour on the stage.
const BREAK_AMBER: Color = Color(0.95, 0.62, 0.18)
const BREAK_AMBER_DIM: Color = Color(0.58, 0.36, 0.10)

## Rule 3. The pit lip, and the void behind it.
const KILL_RED: Color = Color(0.92, 0.22, 0.16)
const VOID: Color = Color(0.02, 0.015, 0.035, 0.97)


## The lit-cap height for a body `h` tall. See CAP_FRACTION.
static func cap_height(h: float) -> float:
	return maxf(CAP_MIN, h * CAP_FRACTION)


## ATMOSPHERIC PERSPECTIVE, as a function rather than as a hand-tuned palette.
##
## The maker's report was "the blue lines mean I cant see anything they should be in
## the background of the map". The blue lines are `Atmosphere`'s tower spires, and
## they were drawn in their palette colour at full alpha — which on the versus stage
## put a row of LIGHTER-than-sky blue bars, in the hero's own hue, straight through
## the airspace he is trying to read platforms in.
##
## Real distance desaturates toward the sky. Pushing every distant layer through
## this makes "further away = closer to the sky colour" structural, so a future
## palette cannot re-create the problem by picking a punchy silhouette colour.
static func haze(col: Color, sky: Color, amount: float) -> Color:
	return col.lerp(Color(sky.r, sky.g, sky.b, col.a), clampf(amount, 0.0, 1.0))
