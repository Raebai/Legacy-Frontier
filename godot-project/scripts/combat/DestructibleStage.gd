class_name DestructibleStage
extends Node2D
## THE STAGE AS A GRID OF CHUNKS, COLLIDED AS A HANDFUL OF RECTANGLES.
##
## Slice 1 of `docs/superpowers/specs/2026-08-19-destructible-map-design.md`: build the
## grid and the collision that comes off it, and prove a fighter walks the stage exactly
## as before. NO DAMAGE IS WIRED HERE. That is Slice 2, and it is a separate reviewable
## change on purpose — this is the piece with no prior art in the repo, so it is the
## piece that gets to fail on its own.
##
## ⚠ WHY NOT ONE BODY PER CHUNK. 2,584 chunks over the shipped stage. That is 2,584
## `StaticBody2D`s for the physics server to broadphase every frame, and 2,584 seams for
## a `CharacterBody2D` to snag on. The spec settled this: ONE body, whose shapes are
## greedy-merged rectangles re-derived from the intact grid.
##
## ⚠ WHY NOT `TileMapLayer`. `set_cell` has a cost cliff on frequent rewrites, and a
## rewrite is exactly what a hit is.
##
## ⚠ THE SEAM RULE, INHERITED FROM `DestructibleFloor` AND NOT NEGOTIABLE. A body
## running across abutting colliders catches on the joins. Merged rectangles therefore
## overlap sideways and grow DOWNWARD, and never, ever grow UP: the top edge is the
## walking surface, and moving it by one pixel moves every fighter's feet with it. That
## is the `feedback_rig_feet_vs_collider` bug arriving by a different road.

## ══ SLICE 2 — DAMAGE OPENS HOLES ═══════════════════════════════════════════
## A hit clears a DISC of cells and the blocks it touched re-merge. Three things
## about that were decided by measurement rather than by taste, and each one is
## written where it is enforced:
##
##   WHICH HITS CARVE — `CARVE_MIN_DAMAGE`. Not everything may bite the ground or
##   the stage dissolves inside one bout. See that constant.
##
##   WHAT A REBUILD COSTS — `BLOCK_W` / `BLOCK_H`. Slice 1's merge walked all 68,926
##   cells in one sweep and cost **8,587 us mean / 17,645 us worst** on this machine,
##   measured by `tools/probe_destructible_carve_cost` before any of this was written.
##   The frame budget is 16,667 us. So a full re-merge per hit is not "a bit expensive",
##   it is a DROPPED FRAME every single time, and the worst sample drops two. The grid is
##   therefore partitioned into blocks that merge independently, and a hit redoes only
##   the blocks it touched: **767–897 us mean / 1,713–1,886 us worst** per dirty frame
##   across the runs, ~10x better and inside budget.
##
##   ⚠ RE-RUNNING THE PROBE WILL NOT REPRODUCE THE 8,587, and that is not drift. Its
##   "FULL merge" line calls `merged_rects()`, which is now itself block-partitioned and
##   takes the whole-block shortcuts, so it reports ~5,000 us. The 8,587 is the
##   pre-partition number and it is written down here because it is the reason the
##   partition exists.
##
##   WHEN IT HAPPENS — never on the hit. A carve writes cells and marks blocks; the
##   rebuild runs once in `_process`, so thirty carve points from one Fault Line cost
##   ONE rebuild of their union instead of thirty full ones.
##
## ⚠ AND THE ONE THING THIS FILE DELIBERATELY DOES NOT DO: it does not join the
## `"destructible"` group. That looks like the obvious wiring — the group plus
## `damage_at` IS the shipped damage contract — and it is a trap that would have
## broken far more than it fixed. `SpellWorld.is_smashable` returns TRUE for anything
## in that group, and `smash_destructibles` DEFAULTS TO TRUE on every `first_solid`
## query. Putting the ground in the group therefore makes the ground invisible to
## `floor_below` / `floor_point` / `ground_path`, which is where `BoulderHurl` rips its
## rock from, where `FaultLine` gets its terrain profile, where `GraveTide` walks,
## where `AegisWard` plants and where every crater and scorch mark is snapped. It is
## measured, not reasoned: `tools/probe_destructible_group_trap.gd` flips the group on
## and counts the floor queries that stop finding a floor.
##
## So the stage advertises itself on its OWN group (`GROUP_NAME`) and the call sites
## route to it explicitly. `is_smashable` never sees it and the ground stays solid to
## every world query that has always relied on it.

## Chunk edge, in world px.
##
## ⚠ 4, NOT THE SPEC'S 16, AND THE FIRST RUN OF THE TEST IS WHY. The stage's terrace
## surfaces are y = 780, 700, 696, 612, 528. A grid can only put a surface on a cell
## boundary, and no 16 px grid holds all five: from a 528 origin, 780 lands 4 px low,
## 696 lands 8 px HIGH, 612 lands 4 px high. Measured, first run:
##     surface at x=700  is 784.0, terrace says 780.0
##     surface at x=1450 is 688.0, terrace says 696.0
## An 8 px error in the walking surface is every fighter's feet in the wrong place —
## `feedback_rig_feet_vs_collider` arriving by a different road, and invisible until
## somebody says "the legs look weird" three sessions later.
##
## All five surfaces ARE multiples of 4, so a 4 px grid reproduces every one of them
## exactly. It costs ~69k cells instead of ~4.3k; that is a 69 KB `PackedByteArray` and
## a merge that still runs in one sweep, which is a cheap price for a floor that is
## where it says it is.
##
## ⚠ THIS IS THE COLLISION GRID, NOT THE VISUAL UNIT OF DESTRUCTION. The spec's 16 px
## was chosen against the Juggernaut's 97.1 px flat-gap reach (6.1 chunks at 16). That
## reasoning is about how big a HOLE is, and it survives unchanged: Slice 2 knocks out
## 4x4 blocks of cells, so a hole is still counted in 16 px units and 6 of them is still
## the widest gap the whole roster can cross.
const CHUNK: float = 4.0
## How many cells wide a destruction unit is. `CHUNK * DESTRUCTION_CELLS` = the spec's
## 16 px chunk, kept as the unit a hit removes so the gap arithmetic is unchanged.
const DESTRUCTION_CELLS: int = 4

## Sideways overlap between neighbouring merged rectangles, and how far each one grows
## down past its own cells. Both exist only to kill seams; neither may be applied
## upward. `DestructibleFloor` uses 2 and 8 for the same reason.
const SEAM_OVERLAP_X: float = 2.0
const SEAM_GROW_DOWN: float = 8.0

## The group the stage advertises itself on. ⚠ DELIBERATELY NOT `"destructible"` —
## see the SLICE 2 block in the header for the `SpellWorld.is_smashable` trap that
## rules that out, and `tools/probe_destructible_group_trap.gd` for the measurement.
const GROUP_NAME: StringName = &"destructible_stage"
## Set on the collision body, pointing back at the stage, so a call site holding only
## the `StaticBody2D` a bolt hit can route the damage without a group scan or a cast.
const BODY_META: StringName = &"destructible_stage"

## ══ WHICH HITS BITE THE GROUND ═════════════════════════════════════════════
## ⚠ THIS WAS 40 AND THE MAKER RETIRED IT. The shelf was written to keep a jab off the
## floor, and the correction is explicit that everything which strikes rock leaves a
## mark: *"for all things where it was hit much like stick fight"*. A beam — the
## maker's OWN example — carries 58–88 damage and still carved nothing, because the
## beam never asked the world where it landed; but `RadiantVolley` (15), a Blade Flurry
## cut (24), an `EnergyNova` (30) and a `MeteorSigil` meteor (36) were all refused by
## THIS NUMBER even where they were wired.
##
## So the shelf goes to 1: every hit that reaches rock takes rock.
##
## ⚠ AND THE THING THE SHELF WAS ACTUALLY PROTECTING AGAINST IS NOW PROTECTED
## PROPERLY. The documented fear was never the jab, it was the REPEAT: a `ZoneSpell`
## field ticking 8 damage into the same square metre every `TICK` for eight seconds, or
## a beam held on one spot. A damage floor is a blunt instrument for that — it refuses
## the first tick as well as the hundredth. `CARVE_REPEAT_BITE` refuses only the
## re-digging, which is also the Stick Fight property the correction is pointing at:
## shooting the same hole again does not widen it forever, it is already a hole.
const CARVE_MIN_DAMAGE: int = 1

## ══ HOW BIG THE HOLE IS ════════════════════════════════════════════════════
## THE OLD RULE WAS DAMAGE-ONLY AND IT IS THE SECOND THING THE CORRECTION BREAKS.
## `carve_radius_for` maps 40 -> 11 px and 260 -> 34 px, so an 88-damage beam opened a
## 38 px-wide hole with a 30 px-wide beam. The maker: *"nothing more or less than that,
## just that definitive hole"* — the size is a property of the STRIKE, not of the
## damage number attached to it.
##
## So the size is driven by the effect's own contact footprint, and damage only nudges
## it. `sqrt` on the footprint for the same reason the damage curve had it: the roster's
## footprints span 8 px (a bolt) to 210 px (a meteor's blast), a 26x range, and a linear
## map either makes the beam invisible or the meteor uncrossable. The measured spread
## this produces is printed by `tools/slice_test_destructible_hitpoint.gd`, which fails
## if any two of beam / dagger / nova / meteor land within `SIZE_DISTINCT_PX` of each
## other — because "visibly different" is the requirement and a table is not proof.
const CARVE_FOOTPRINT_K: float = 3.4
## Damage moves the crater inside a bounded band around the footprint's answer. Bounded
## on purpose: a 260-damage ult through a 30 px beam is still a 30 px beam, it just
## bites a little harder.
const CARVE_DAMAGE_SCALE_MIN: float = 0.70
const CARVE_DAMAGE_SCALE_MAX: float = 1.30
## The damage band the scale is normalised across — the roster's floor (a zone tick)
## and its ceiling (`Teardown` 210 / `Equinox` 260).
const CARVE_DAMAGE_FLOOR: float = 8.0
const CARVE_DAMAGE_CEILING: float = 260.0

## Hard bounds on any crater.
##
## MIN is 5, not the old 11: a beam has to be ALLOWED to make a small hole, and 5 px of
## radius is still 2 whole cells of the 4 px grid gone plus their neighbours — a hole
## you can see and fall into the edge of, which is the point.
##
## MAX is 46. The Juggernaut's flat-gap reach is 97.1 px and 46 px of radius is a 92 px
## hole, so the widest single crater in the game is still crossable by the whole roster
## — and the maker's ruling that a gap may become uncrossable ("if that happens then it
## happens") is about the UNION of many hits, which nothing here caps.
const CARVE_RADIUS_MIN: float = 5.0
const CARVE_RADIUS_MAX: float = 46.0

## ══ WHAT EACH SPELL DOES TO THE GROUND, AND WHY IT FOLLOWS FROM THE SPELL ══
## The maker's rule: *"use your logic for all the spells to think about how they
## interact with the environment"*, and the result must be PREDICTABLE — a player who
## has watched one boulder land knows what the next one does.
##
## So the footprint every call site passes is THE PHYSICAL THING THAT TOUCHED THE ROCK,
## never the spell's damage number and never its reach. That single rule generates the
## whole table; nothing below was picked to be tidy.
##
##   SPELL              WHAT TOUCHES THE GROUND        FOOTPRINT     HOLE (radius)
##   bolt               the bolt, r6                    6.0            7.3 px
##   rift dagger        the BLADE, half-width 4.2        8.4            8.2 px
##   frostpiercer beam  the beam, half of w22           11.0           10.3 px
##   ice spike          the spike base, half-width      16.0           11.6 px
##   first lance beam   the beam, half of w30           15.0           13.1 px
##   infernal lance     the beam, half of w42           21.0           15.0 px
##   fault line bite    the crack, per bite             20.0           15.7 px
##   boulder hurl       the ROCK, BOULDER_R 26          26.0           17.6 px
##   shockwave stomp    the boot's shock front          30.0           16.8 px
##   divine ray         the pillar's ground disc        70.0           28.8 px
##   blast Q / meteor   the detonation's own radius     90.0           32.7 px
##     fist
##   energy nova        the ring, NOVA_RADIUS           135.0          32.4 px
##   meteor sigil       the meteor's blast              140.0          33.9 px
##   meteor storm       the meteor's blast              210.0          40.4 px
##
## THE ONE ROW THAT LOOKS WRONG AND IS NOT. A nova (32.4) out-carves a boulder (17.6),
## which reads backwards until you say what each one touches: a boulder is 26 px of
## stone landing on a point, a nova is a 135 px shockwave ring scouring every bit of
## floor it crosses. Wide-and-shallow beating small-and-heavy is what those two spells
## LOOK like, so the ground agreeing with the picture is the rule working. Forcing the
## boulder above the nova would mean sizing it off its blast reach instead of its rock,
## and then the rock would excavate ground it never touched.
##
## AND THE ROWS THAT ARE DELIBERATELY ABSENT:
##
##   ZONES AND FIELDS carve ONCE, on the tick that first touches a given patch, and
##   then nothing — not because the tick is too weak (that shelf is gone) but because
##   `CARVE_REPEAT_BITE` refuses a source re-digging its own hole. A burning field
##   leaves a scorched pockmark where it started; it does not eat the floor for eight
##   seconds. That is the same answer the old damage shelf gave, arrived at honestly.
##
##   CHAIN LIGHTNING carves nothing, and that is not an omission. An arc leaps body to
##   body through the AIR; it has no terrain contact to be accurate to. Wiring it would
##   mean inventing a ground strike the spell does not have.
##
##   WALLS RAISED OUT OF THE GROUND (`RockWall`, `IceWall`) DO NOT YET TAKE THE
##   MATERIAL THEY ARE MADE OF, and it is the best unbuilt idea in this pass: a rock
##   wall that leaves a trench where it tore itself free would make cover and hazard the
##   same act, and the trench would be exactly as long as the wall is wide, so it is
##   readable without a tutorial. It is NOT built here for two reasons, both worth
##   stating. Those files are not in this pass's ownership. And a wall's footprint is a
##   long thin SPAN, not a disc — `carve_disc` would need a capsule sibling or a row of
##   overlapping bites, and a row of bites is exactly the shape most likely to move the
##   severed-run number off 0. It wants its own measured slice, not a bolt-on.
##
## The damage-only fallback curve, for a source that cannot publish a footprint. Kept
## because `carve_from_body` is reached by bodies whose caller knows nothing about them,
## and a source with no footprint must still carve SOMETHING rather than nothing.
## Anchored at the same two ends as the size rule so the two curves agree at the edges.
const CARVE_FALLBACK_FOOTPRINT: float = 8.0

## ══ NOTHING CASCADES ═══════════════════════════════════════════════════════
## A second carve from THE SAME SOURCE is refused when its centre falls inside this
## fraction of an earlier crater's radius. That is the whole anti-cascade rule, and it
## is deliberately per-source rather than global:
##
##   - a zone ticking on one spot opens ONE hole and then stops, however long it burns
##   - a beam held on a wall opens ONE hole, not a tunnel
##   - a Fault Line marching along the ground keeps carving, because each bite is a
##     fresh point further along (its stride is larger than 0.75 of its own radius)
##   - two DIFFERENT spells hitting the same spot both carve, because they are two
##     separate strikes and the maker's model is per-strike
##
## ⚠ WHY NOT A COOLDOWN. A wall-clock cooldown lets a long-lived effect dissolve a
## floor slowly instead of quickly, which is the same failure at a different speed. A
## SPATIAL ledger cannot: the ground a source has already taken is the ground it may
## never take again.
const CARVE_REPEAT_BITE: float = 0.75
## Craters remembered per source. A Fault Line is the longest walker in the roster at
## ~30 bites; 48 covers it with room, and the oldest entry is dropped past that so a
## pathological source cannot grow this without bound.
const CARVE_LEDGER_MAX: int = 48
## Sources tracked before a validity sweep runs. Freed spells leave dead ids behind and
## nothing else would ever collect them.
const CARVE_LEDGER_SOURCES_MAX: int = 96

## ⚠ TWO CAPS, NEVER ONE — spec §6.3. The maker's ruling forbids capping the CHUNKS
## REMOVED per hit ("if that happens then it happens it will be a projectile based
## ending"), so nothing here limits the carve. What is capped is the COSMETIC debris,
## which is a frame-rate concern and carries no gameplay information at all.
const MAX_DEBRIS_PER_CARVE: int = 6

## ══ THE REBUILD PARTITION ══════════════════════════════════════════════════
## Block edge, in CELLS. 48 x 48 cells = 192 x 192 world px, so the 482 x 143 grid is
## 11 x 3 = 33 blocks. Each merges alone, and a hit re-merges only the blocks its disc
## overlapped — at most four for the largest crater.
##
## Chosen against the measurement, not by feel. A full merge is 8.6 ms; one block is
## 2,304 cells of the 68,926, i.e. ~1/30th of it, and a block that is ENTIRELY solid or
## entirely empty skips the merge altogether (see `_merge_block`) — which is almost
## every block on an untouched stage. Smaller blocks would be cheaper still but produce
## more rectangles, and every rectangle is a shape the physics broadphase carries for
## the rest of the bout.
const BLOCK_W: int = 48
const BLOCK_H: int = 48
## How many dirty blocks may be re-merged in one frame. The rest wait for the next.
## ⚠ AND A DEFERRAL IS LOGGED, NOT SWALLOWED — spec §6.1: "Silent truncation reads as
## 'it all rebuilt' when it did not." `deferred_rebuilds` counts them and
## `tools/probe_destructible_bot_fight.gd` prints the total.
const MAX_BLOCK_REBUILDS_PER_FRAME: int = 6
## ...and the REAL bound, because a block's cost is its cell count and not its index.
## Measured: one mixed block re-merges in ~450 us, so six of them is ~2.7 ms and thirty
## carve points scattered along the ground dirtied five blocks for 5.4 ms in a single
## frame. A count cap cannot know that; a wall-clock budget can. The first dirty block
## is ALWAYS done even if the budget is already spent, so a carve can never be starved
## forever by a busy frame.
const REBUILD_BUDGET_USEC: int = 1400

## The cavity a carve leaves, drawn so a hole in the collision is a hole you can SEE.
## Cooler and darker than `ArenaTerrain.ROCK_DEEP` (0.22, 0.21, 0.25) on purpose: a
## carved cavity is not "more rock", it is the absence of it, and at the played zoom
## the only thing that separates them is value.
const CAVITY_FILL: Color = Color(0.09, 0.085, 0.11)
## How much of the surrounding rock's colour a hole keeps. A cavity is a SHADOW in
## that rock, not a different material, so it is the same hue several stops down —
## which is what makes it read as depth rather than as a sticker.
const CAVITY_MIX: float = 0.34
## RULE 1 of the stage legend (see `StageLayers`): a lit cap says "standable". A carved
## crater floor IS standable, so it gets the same cap the authored terraces get, and
## for the same reason — one signal, not three near-misses.
const NEW_SURFACE_CAP: Color = Color(0.62, 0.55, 0.38, 0.95)
const NEW_SURFACE_CAP_H: float = 2.0

var origin: Vector2 = Vector2.ZERO      ## world position of cell (0, 0)'s top-left
var cols: int = 0
var rows: int = 0

## One byte per cell, row-major. 1 = intact rock, 0 = air. A PackedByteArray rather than
## a 2D Array because it is read once per cell per rebuild and allocation-free indexing
## is the whole budget.
var _solid: PackedByteArray = PackedByteArray()
## The grid as it was BUILT, never written again. Two things read it: the cavity
## drawing (a cell that is air now but was rock then is a HOLE; a cell that was always
## air is sky) and `carved_fraction()`, which is the budget number.
var _original: PackedByteArray = PackedByteArray()

## source instance id -> Array[Vector3] of (x, y, radius) craters it has opened.
## See `CARVE_REPEAT_BITE`.
var _ledger: Dictionary = {}

var _body: StaticBody2D = null
var _shape_count: int = 0

## ── the block partition ────────────────────────────────────────────────────
var _block_cols: int = 0
var _block_rows: int = 0
## Live solid-cell count per block. The whole point of keeping it: a block whose count
## is 0 or equals its area needs NO merge at all, which is what makes a full rebuild
## of an untouched stage cheap and a dirty rebuild near-free.
var _block_solid: PackedInt32Array = PackedInt32Array()
var _block_area: PackedInt32Array = PackedInt32Array()
var _block_dirty: PackedByteArray = PackedByteArray()
## Per block: the `CollisionShape2D` nodes it owns, the rock rects they came from, the
## cavity rects to draw, and the exposed-surface caps. All four are rebuilt together
## so they can never describe different stages.
var _block_shapes: Array = []
var _block_rects: Array = []
var _block_cavities: Array = []
var _block_caps: Array = []

## ── measurement, printed by the probes and asserted by the suites ──────────
## Cells removed since the stage was built, and how many carve events did it.
var carved_cells: int = 0
var carve_events: int = 0
## Hits that arrived under `CARVE_MIN_DAMAGE` and were refused. Counted because "the
## threshold is doing nothing" and "the threshold is eating everything" look identical
## from the outside, and only this number separates them.
var refused_hits: int = 0
## Hits refused by the anti-cascade ledger — the same source trying to re-dig ground
## it already took. Counted separately from `refused_hits` because "the shelf is
## eating everything" and "one zone is looping on one spot" are different problems
## and a single number cannot tell them apart.
var repeat_refused_hits: int = 0
## Block re-merges pushed to a later frame by `MAX_BLOCK_REBUILDS_PER_FRAME`.
var deferred_rebuilds: int = 0
## Wall-clock microseconds spent in block re-merges, and the worst single frame.
var rebuild_usec_total: int = 0
var rebuild_usec_worst: int = 0

## ══ THE LEDGE MODE ═════════════════════════════════════════════════════════
## Maker: *"please make the floating platforms destroyable into bits just like the
## floor was beforehand as well"*. A ledge is the SAME chunk grid as the ground —
## the four knobs below are the whole difference, and every one of them exists
## because a ledge is a small thing hanging in the air rather than the world's
## floor. See `attach_ledge`, which is the only supported way to set them.

## ⚠ WHETHER THIS STAGE JOINS `GROUP_NAME`, AND THE ANSWER FOR A LEDGE IS NO.
## `stage_in` returns THE FIRST MEMBER of the group, which is written for a world
## with exactly ONE stage. Put twenty ledges in the group and `carve_area` — the
## route used by Blast, Fault Line, Grave Tide, Heaven's Wrath, Ice Spike, Meteor
## Sigil, Radiant Volley, Rock Pillar, Shadow Root, Shockwave Stomp and Star
## Convergence — sends every carve in the game to whichever ledge happens to sort
## first, so a stomp at the player's feet quietly chews a platform across the room
## while the rock under the boot keeps its shape. That is the exact fault
## `slice_test_destructible_sources` records costing it five false failures, and
## `slice_test_one_screen` pins the group empty on a tower floor.
##
## So a ledge routes by `BODY_META` ONLY (`carve_from_body`, which reads the meta off
## the collider that was actually hit) plus its owner's own `damage_at`. Both are
## per-body by construction and cannot cross-talk.
var advertise_in_group: bool = true

## The node whose LOCAL space the grid is expressed in, or null for world space.
##
## The ground stage sits at the origin, so world space and its own space are the same
## and this stays null — `damage_at` is byte-identical for it. A ledge's grid lives in
## its OWNER BODY's local space instead, because the merged collision shapes are
## installed as children of that body (see `rebuild_collision`'s borrowed-body mode)
## and a child's position is local. Carve call sites all speak world, so the
## conversion happens once, here, at the entry.
var space: Node2D = null

## Whether a carve fires the stage's own rubble + crack. A ledge says no and spawns its
## own: `_spawn_carve_spectacle` throws `ArenaTerrain.ROCK_UPPER` chips and stamps a
## `radius * 0.9` crack, which is the right weight for a hole in the world's floor and
## far too much for a 24 px plank — this is a ledge breaking, not the ult that broke it.
var spectacle: bool = true

## False in borrowed-body mode: the body belongs to someone else, so a rebuild must not
## free it, rename it, or reparent it.
var _owns_body: bool = true

## How far each merged rectangle grows DOWN past its own cells. `SEAM_GROW_DOWN` (8) is
## right for the ground, where the extra is buried inside 320 px of rock and only ever
## kills seams. On a 24 px ledge it is a THIRD of the plank hanging below the picture —
## invisible solid air a fighter jumping up from underneath would bonk on early. So a
## ledge trims it to a hair. ⚠ NEVER APPLIED UPWARD, at any value: the top edge is the
## walking surface and moving it moves every fighter's feet
## ([[feedback_rig_feet_vs_collider]]).
var seam_grow_down: float = SEAM_GROW_DOWN


func _ready() -> void:
	# The one z table (see `StageLayers`). A carved cavity is a HOLE IN the ground, so
	# it belongs on exactly the rung `StageHazard`'s pit does and for the identical
	# reason — it must draw in front of `ArenaTerrain` (-6) and behind everything a
	# fighter stands on. ⚠ It is not in `StageLayers.DRAWERS`, because that registry is
	# keyed by files the scanner can see (`extends StaticBody2D`) and this is a Node2D;
	# the one-line entry is named in this slice's report.
	StageLayers.apply(self, StageLayers.HAZARD)
	# ⚠ CONDITIONAL SINCE THE LEDGES ARRIVED. See `advertise_in_group` for why a
	# ledge must stay out of the first-member-wins group scan. The GROUND still
	# joins, unchanged, so `carve_area` finds it exactly as it always has.
	if advertise_in_group:
		add_to_group(GROUP_NAME)


## Lay a grid over `rects` (world-space, e.g. the terrace boxes) and mark every cell
## whose CENTRE falls inside one of them as intact.
##
## ⚠ CENTRE-SAMPLED ON PURPOSE. Sampling by overlap would mark a cell solid when a rect
## clips one pixel of it, growing the stage by up to a chunk on every edge — including
## upward, which moves the walking surface. Centre-sampling can only ever lose a sliver
## smaller than half a chunk, and the surface lands on a chunk boundary because the grid
## is aligned to the rects below.
func build_from_rects(rects: Array[Rect2]) -> void:
	# A rebuild on a BORROWED body has to take its old shapes with it — see
	# `_free_shape_nodes`. A no-op for the ground stage, which has never rebuilt its
	# grid once it was laid.
	if not _owns_body:
		_free_shape_nodes()
	if rects.is_empty():
		cols = 0
		rows = 0
		_solid = PackedByteArray()
		_original = PackedByteArray()
		_init_blocks()
		return
	var bounds: Rect2 = rects[0]
	for r: Rect2 in rects:
		bounds = bounds.merge(r)
	# Snap the origin DOWN to a chunk multiple so the grid is stable between rebuilds
	# and a rect's top edge keeps landing on the same cell boundary.
	origin = Vector2(floorf(bounds.position.x / CHUNK) * CHUNK,
		floorf(bounds.position.y / CHUNK) * CHUNK)
	cols = int(ceilf((bounds.end.x - origin.x) / CHUNK))
	rows = int(ceilf((bounds.end.y - origin.y) / CHUNK))
	_solid = PackedByteArray()
	_solid.resize(cols * rows)
	for cy: int in rows:
		for cx: int in cols:
			var centre: Vector2 = origin + Vector2(
				(float(cx) + 0.5) * CHUNK, (float(cy) + 0.5) * CHUNK)
			for r: Rect2 in rects:
				if r.has_point(centre):
					_solid[cy * cols + cx] = 1
					break
	_original = _solid.duplicate()
	_init_blocks()


## Partition the grid into blocks and count what each one holds. Called once per build;
## everything after it only ADJUSTS the counts, and nothing ever recounts.
func _init_blocks() -> void:
	_block_cols = int(ceilf(float(cols) / float(BLOCK_W))) if cols > 0 else 0
	_block_rows = int(ceilf(float(rows) / float(BLOCK_H))) if rows > 0 else 0
	var n: int = _block_cols * _block_rows
	_block_solid = PackedInt32Array()
	_block_solid.resize(n)
	_block_area = PackedInt32Array()
	_block_area.resize(n)
	_block_dirty = PackedByteArray()
	_block_dirty.resize(n)
	_block_shapes = []
	_block_rects = []
	_block_cavities = []
	_block_caps = []
	for _i: int in n:
		_block_shapes.append([])
		_block_rects.append([])
		_block_cavities.append([])
		_block_caps.append([])
	for by: int in _block_rows:
		for bx: int in _block_cols:
			var x0: int = bx * BLOCK_W
			var y0: int = by * BLOCK_H
			var x1: int = mini(x0 + BLOCK_W, cols)
			var y1: int = mini(y0 + BLOCK_H, rows)
			var b: int = by * _block_cols + bx
			_block_area[b] = (x1 - x0) * (y1 - y0)
			var live: int = 0
			for cy: int in range(y0, y1):
				var row: int = cy * cols
				for cx: int in range(x0, x1):
					live += _solid[row + cx]
			_block_solid[b] = live


func is_solid(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
		return false
	return _solid[cy * cols + cx] == 1


## Was this cell rock when the stage was BUILT? Public because the probes need the
## original silhouette to say how deep a hole is, and reconstructing it from the terrace
## table outside this file gets the cell-edge rounding wrong — measured: it reported an
## 80 px hole on a stage where nothing had been carved at all.
func was_rock(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
		return false
	return _original[cy * cols + cx] == 1


## Clear one cell and keep the block bookkeeping honest. Returns true only if rock was
## actually removed, so callers count real damage rather than attempts.
func clear_cell(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
		return false
	var i: int = cy * cols + cx
	if _solid[i] == 0:
		return false
	_solid[i] = 0
	var b: int = int(cy / BLOCK_H) * _block_cols + int(cx / BLOCK_W)
	_block_solid[b] -= 1
	_block_dirty[b] = 1
	return true


func solid_count() -> int:
	var n: int = 0
	for b: int in _solid:
		n += b
	return n


func shape_count() -> int:
	return _shape_count


## Every cavity rectangle currently being drawn, flattened. For the suite: "the hole in
## the collision is also a hole in the PICTURE" is the one property whose failure mode is
## solid-looking ground you fall through, and it cannot be asserted from outside without
## seeing what `_draw` sees.
func debug_cavity_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for b: int in _block_cavities.size():
		for r: Rect2 in _block_cavities[b]:
			out.append(r)
	return out


func block_count() -> int:
	return _block_cols * _block_rows


func dirty_block_count() -> int:
	var n: int = 0
	for d: int in _block_dirty:
		n += d
	return n


## How much of the rock the stage was BUILT with is gone. THE budget number: if a real
## bot fight leaves this at 0.4 after thirty seconds the carve is far too generous, and
## no amount of looking at a screenshot tells you that.
func carved_fraction() -> float:
	var was: int = 0
	for b: int in _original:
		was += b
	if was <= 0:
		return 0.0
	return float(carved_cells) / float(was)


## GREEDY MERGE: the intact grid as a small set of rectangles, block by block.
##
## Row-major sweep inside each block. For each un-consumed run of solid cells in a row,
## extend the run DOWNWARD as long as every row below carries the identical span, then
## consume the whole cluster. Standard rectangle decomposition, chosen over anything
## cleverer because its failure mode is "more rectangles than strictly necessary"
## rather than "a hole nobody can see".
##
## ⚠ WHY IT IS PARTITIONED AT ALL, since the merge was already correct without it: a
## hit must not pay for the 68,926 cells it did not touch. See `BLOCK_W`.
##
## ⚠ AND WHY THE BLOCK SEAMS ARE SAFE. A vertical seam between two blocks is covered by
## `SEAM_OVERLAP_X`, the same trick that already covers the seam between two merged
## rectangles inside one block. A horizontal seam is INSIDE rock by construction: the
## walking surface at any x is the top of the topmost solid cell in that column, and
## whichever block owns that cell emits a rectangle whose top edge is exactly there.
## The block below emits a rectangle whose top is buried, and `SEAM_GROW_DOWN` makes
## the one above overlap it, so there is no gap to fall through either.
func merged_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for by: int in _block_rows:
		for bx: int in _block_cols:
			out.append_array(_merge_block(bx, by))
	return out


## One block's rock, as rectangles. The two shortcuts are what make this cheap: an
## EMPTY block is nothing and a FULL block is one rectangle, and on an untouched stage
## almost every block is one or the other.
func _merge_block(bx: int, by: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var b: int = by * _block_cols + bx
	if _block_solid[b] <= 0:
		return out
	var x0: int = bx * BLOCK_W
	var y0: int = by * BLOCK_H
	var x1: int = mini(x0 + BLOCK_W, cols)
	var y1: int = mini(y0 + BLOCK_H, rows)
	if _block_solid[b] == _block_area[b]:
		out.append(Rect2(
			origin + Vector2(float(x0) * CHUNK, float(y0) * CHUNK),
			Vector2(float(x1 - x0) * CHUNK, float(y1 - y0) * CHUNK)))
		return out
	var bw: int = x1 - x0
	var bh: int = y1 - y0
	var used: PackedByteArray = PackedByteArray()
	used.resize(bw * bh)
	for ly: int in bh:
		var lx: int = 0
		while lx < bw:
			var li: int = ly * bw + lx
			if _solid[(y0 + ly) * cols + x0 + lx] == 0 or used[li] == 1:
				lx += 1
				continue
			# Widest run on this row, inside the block.
			var span: int = 0
			while lx + span < bw:
				var lj: int = ly * bw + lx + span
				if _solid[(y0 + ly) * cols + x0 + lx + span] == 0 or used[lj] == 1:
					break
				span += 1
			# Deepest stack of rows carrying that exact span.
			var depth: int = 1
			while ly + depth < bh:
				var ok: bool = true
				for k: int in span:
					var lj2: int = (ly + depth) * bw + lx + k
					if _solid[(y0 + ly + depth) * cols + x0 + lx + k] == 0 or used[lj2] == 1:
						ok = false
						break
				if not ok:
					break
				depth += 1
			for dy: int in depth:
				for dx: int in span:
					used[(ly + dy) * bw + lx + dx] = 1
			out.append(Rect2(
				origin + Vector2(float(x0 + lx) * CHUNK, float(y0 + ly) * CHUNK),
				Vector2(float(span) * CHUNK, float(depth) * CHUNK)))
			lx += span
	return out


## The CAVITY in one block: cells that were rock when the stage was built and are air
## now. Same decomposition run over the difference mask, so a hole draws as a few
## rectangles rather than as thousands of 4 px squares.
func _cavity_block(bx: int, by: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var b: int = by * _block_cols + bx
	if _block_solid[b] == _block_area[b]:
		return out  # nothing has been removed here
	var x0: int = bx * BLOCK_W
	var y0: int = by * BLOCK_H
	var x1: int = mini(x0 + BLOCK_W, cols)
	var y1: int = mini(y0 + BLOCK_H, rows)
	var bw: int = x1 - x0
	var bh: int = y1 - y0
	var used: PackedByteArray = PackedByteArray()
	used.resize(bw * bh)
	for ly: int in bh:
		var lx: int = 0
		while lx < bw:
			var gi: int = (y0 + ly) * cols + x0 + lx
			if used[ly * bw + lx] == 1 or _original[gi] == 0 or _solid[gi] == 1:
				lx += 1
				continue
			var span: int = 0
			while lx + span < bw:
				var g2: int = (y0 + ly) * cols + x0 + lx + span
				if used[ly * bw + lx + span] == 1 or _original[g2] == 0 or _solid[g2] == 1:
					break
				span += 1
			var depth: int = 1
			while ly + depth < bh:
				var ok: bool = true
				for k: int in span:
					var g3: int = (y0 + ly + depth) * cols + x0 + lx + k
					if used[(ly + depth) * bw + lx + k] == 1 \
							or _original[g3] == 0 or _solid[g3] == 1:
						ok = false
						break
				if not ok:
					break
				depth += 1
			for dy: int in depth:
				for dx: int in span:
					used[(ly + dy) * bw + lx + dx] = 1
			out.append(Rect2(
				origin + Vector2(float(x0 + lx) * CHUNK, float(y0 + ly) * CHUNK),
				Vector2(float(span) * CHUNK, float(depth) * CHUNK)))
			lx += span
	return out


## The lit caps for one block: the top edge of every rock rectangle that has CARVED-OUT
## air directly above it. That is precisely "a surface destruction created", which is
## the only surface `ArenaTerrain` does not already cap — and RULE 1 of the stage
## legend says a lit cap is how the game says "you can stand here".
func _caps_for(rects: Array) -> Array:
	var out: Array = []
	for r: Rect2 in rects:
		var cy: int = int(roundf((r.position.y - origin.y) / CHUNK)) - 1
		if cy < 0:
			continue
		var cx0: int = int(roundf((r.position.x - origin.x) / CHUNK))
		var cx1: int = cx0 + int(roundf(r.size.x / CHUNK))
		var run_start: int = -1
		for cx: int in range(cx0, cx1 + 1):
			var carved: bool = false
			if cx < cx1 and cx >= 0 and cx < cols:
				var gi: int = cy * cols + cx
				carved = _original[gi] == 1 and _solid[gi] == 0
			if carved and run_start < 0:
				run_start = cx
			elif not carved and run_start >= 0:
				out.append(Rect2(
					origin + Vector2(float(run_start) * CHUNK,
						r.position.y - NEW_SURFACE_CAP_H),
					Vector2(float(cx - run_start) * CHUNK, NEW_SURFACE_CAP_H)))
				run_start = -1
	return out


## Build (or rebuild) the whole collision body from the current grid. This is the
## EXPENSIVE path — 8.6 ms on the shipped stage — and after the initial build it is
## never taken again: `_rebuild_dirty_blocks` does the per-hit work.
## ⚠ `into` IS THE LEDGE MODE, AND IT EXISTS SO A LEDGE STAYS ONE BODY. A platform is
## already a `StaticBody2D` that carries `collision_layer = 5`, the `"destructible"`
## group and the `take_damage` / `damage_at` contract every spell branch routes
## through. Handing it a SECOND body of our own would have split one ledge in two: a
## bolt stopping on the grid body would find a bare `StaticBody2D` that is not in
## `"destructible"`, fall through `Spell._try_damage` to the terrain branch, carve —
## and never reach the owner's `damage_at`, so its hp would never move, it would never
## collapse and the co-op `broadcast_prop_state` wire would never fire.
##
## So the shapes are installed onto the body that is already there. The grid must then
## be expressed in THAT BODY'S LOCAL SPACE, because a `CollisionShape2D`'s position is
## local to its parent — which is what `space` is for.
func rebuild_collision(parent: Node, into: StaticBody2D = null) -> StaticBody2D:
	if into != null:
		_body = into
		_owns_body = false
	else:
		if _body != null and is_instance_valid(_body) and _owns_body:
			_body.queue_free()
		_body = StaticBody2D.new()
		_body.name = "DestructibleStageBody"
		_owns_body = true
	# The back-pointer a call site uses when all it holds is the body a bolt hit.
	# Meta rather than a script on the body, because a scripted body would be picked up
	# by `slice_test_destructible_stage_wired`'s "a bare StaticBody2D is a terrace"
	# discriminator and by `StageLayers`' drawer scanner, neither of which it is.
	_body.set_meta(BODY_META, self)
	_shape_count = 0
	for by: int in _block_rows:
		for bx: int in _block_cols:
			_install_block(bx, by)
	if _owns_body:
		parent.add_child(_body)
	return _body


## Drop every `CollisionShape2D` this stage installed and forget the node lists.
##
## Only borrowed-body mode needs it: an owned body is freed whole by the line above, but
## a BORROWED one outlives the grid — a ledge that reforms builds a fresh grid into the
## same body, and without this the old shapes would stay parented there as invisible
## solid geometry and the ledge would never actually lose a chunk.
func _free_shape_nodes() -> void:
	for nodes: Variant in _block_shapes:
		for n: Variant in (nodes as Array):
			var cs: Node = n as Node
			if cs == null or not is_instance_valid(cs):
				continue
			# REMOVED BEFORE FREED. `queue_free` lands at the end of the frame, so a
			# shape merely queued goes on colliding for one more frame — which on a
			# reforming ledge is a plank you fall through and on a carve is a hole you
			# cannot fall into. Detach first; the free is then just memory.
			if cs.get_parent() != null:
				cs.get_parent().remove_child(cs)
			cs.queue_free()
	_block_shapes = []
	_shape_count = 0


## One block's shapes, cavities and caps — computed together so they can never
## describe different stages, and installed under the shared body.
##
## ⚠ THE NODES ARE REUSED, NOT REBUILT — and the honest report of what that bought is
## "the worst case, not the mean". Freeing a block's `CollisionShape2D`s and allocating
## fresh ones costs a tree removal, a tree insertion, two object allocations and a
## physics-server shape registration EACH, and a re-merge usually hands back a rect list
## of almost the same length as last time, so re-pointing the existing nodes is the
## obviously cheaper shape. Measured on the shipped stage over 60 carves, before and
## after: mean 853 -> 897 us (i.e. NO measurable change — inside the run-to-run spread),
## worst 2487 -> 1713 us. The mean is dominated by the merge itself, not by node churn;
## the tail was the churn. Kept for the tail, and because it stops the body's child list
## from thrashing, but it is NOT the mean-case win it looks like.
func _install_block(bx: int, by: int) -> void:
	var b: int = by * _block_cols + bx
	var rects: Array[Rect2] = _merge_block(bx, by)
	var nodes: Array = _block_shapes[b]
	for i: int in rects.size():
		var r: Rect2 = rects[i]
		# ⚠ SIDEWAYS AND DOWN ONLY. See the seam rule at the top of this file: the top
		# edge is the walking surface and must land exactly where the source rect put it.
		var size := Vector2(r.size.x + SEAM_OVERLAP_X * 2.0, r.size.y + seam_grow_down)
		var at := Vector2(r.position.x + r.size.x * 0.5,
			r.position.y + (r.size.y + seam_grow_down) * 0.5)
		if i < nodes.size():
			var old_cs: CollisionShape2D = nodes[i] as CollisionShape2D
			if old_cs != null and is_instance_valid(old_cs):
				(old_cs.shape as RectangleShape2D).size = size
				old_cs.position = at
				continue
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = size
		cs.shape = shape
		cs.position = at
		_body.add_child(cs)
		if i < nodes.size():
			nodes[i] = cs
		else:
			nodes.append(cs)
	while nodes.size() > rects.size():
		var extra: Node = nodes.pop_back() as Node
		if extra != null and is_instance_valid(extra):
			extra.queue_free()
	_block_shapes[b] = nodes
	_block_rects[b] = rects
	_block_cavities[b] = _cavity_block(bx, by)
	_block_caps[b] = _caps_for(rects)
	_block_dirty[b] = 0
	_shape_count += rects.size()


## The top surface y of the merged geometry at a world x, or INF where there is no rock.
## The one number a walking test actually cares about.
func surface_y_at(world_x: float) -> float:
	var cx: int = int(floorf((world_x - origin.x) / CHUNK))
	if cx < 0 or cx >= cols:
		return INF
	for cy: int in rows:
		if _solid[cy * cols + cx] == 1:
			return origin.y + float(cy) * CHUNK
	return INF


# ═══════════════════════════════════════════════════════ SLICE 2 — DAMAGE

## THE DAMAGE CONTRACT, in the shape every other destructible in the repo speaks
## (`DestructibleTerrain.damage_at`, `DestructibleProp.damage_at`). Returns the number
## of cells actually removed, which is what the probes count.
##
## `world_pos` IS THE CONTACT POINT AND NOTHING ELSE. The maker's correction is
## explicit — *"ensure that the damage done is kept accurate to where it hit"* — so
## every call site owes this function the point the strike actually met the rock, not
## the caster's position, not the spell's origin, and not a floor point snapped some
## distance away from it. Where a source genuinely has no contact point (a detonation
## in mid-air over ground it never touched) it snaps DOWN and says so at the call site.
##
## `footprint` is the effect's own contact RADIUS / half-width in world px, and it is
## what SIZES the hole. ⚠ ITS MEANING CHANGED. It used to be `radius_hint`, a number
## that could only ever WIDEN a damage-derived crater; it is now the primary term, and
## a small footprint therefore makes a SMALL hole however big the damage number is.
## That is the correction: a 30 px beam carrying 88 damage used to open a 38 px hole,
## which is the spell arguing with its own picture. Pass 0 only when the source truly
## has no published size — see `CARVE_FALLBACK_FOOTPRINT`.
##
## `source` is the effect doing the striking, and it exists for the anti-cascade rule
## only — see `CARVE_REPEAT_BITE`. Passing null opts a call site out of repeat
## protection, which is correct for a one-shot projectile that dies on impact and wrong
## for anything that ticks.
##
## ⚠ A REFUSED HIT IS STILL NOT A NO-OP at the call site: the chip and the scorch fire
## regardless, because a spell that visibly hits rock and leaves no mark reads as a bug
## even when the rock is supposed to survive.
func damage_at(amount: int, world_pos: Vector2, dir: Vector2,
		footprint: float = 0.0, source: Object = null) -> int:
	if amount < CARVE_MIN_DAMAGE:
		refused_hits += 1
		return 0
	var r: float = carve_radius_for_strike(amount, footprint)
	# WORLD IN, GRID OUT. Identity for the ground stage (`space` is null and it sits at
	# the origin); a ledge's grid lives in its owner body's local space. The ledger and
	# the carve both work in grid space so they agree with each other; the SPECTACLE
	# keeps the world point, because debris and decals are parented into the arena.
	var at: Vector2 = _to_grid(world_pos)
	if not _ledger_admits(source, r, at):
		repeat_refused_hits += 1
		return 0
	var removed: int = carve_disc(at, r)
	if removed <= 0:
		return 0
	_ledger_record(source, at, r)
	carve_events += 1
	if spectacle:
		_spawn_carve_spectacle(world_pos, r, dir)
	return removed


## World point -> this grid's coordinate space. See `space`.
func _to_grid(world_pos: Vector2) -> Vector2:
	if space != null and is_instance_valid(space) and space.is_inside_tree():
		return space.to_local(world_pos)
	return world_pos


## THE SIZE RULE. Pure and static so a test can print the whole roster's table without
## building a stage — and `tools/slice_test_destructible_hitpoint.gd` does exactly that,
## then fails if the four shapes the maker named are not visibly apart.
##
## Sub-linear in the footprint AND in the damage, for the reason the old damage curve
## already gave: a hit worth five times as much must not dig twenty-five times as wide.
## Here the same argument applies twice over, because the footprint range (8 px to
## 210 px) is wider than the damage range.
static func carve_radius_for_strike(amount: int, footprint: float) -> float:
	var f: float = footprint if footprint > 0.0 else CARVE_FALLBACK_FOOTPRINT
	var base: float = CARVE_FOOTPRINT_K * sqrt(maxf(f, 1.0))
	return clampf(base * carve_damage_scale(amount),
		CARVE_RADIUS_MIN, CARVE_RADIUS_MAX)


## How much damage nudges the footprint's answer. Bounded to
## [`CARVE_DAMAGE_SCALE_MIN`, `CARVE_DAMAGE_SCALE_MAX`] so damage can never take the
## size question away from the footprint — which is the whole point of the correction.
static func carve_damage_scale(amount: int) -> float:
	var lo: float = sqrt(CARVE_DAMAGE_FLOOR)
	var hi: float = sqrt(CARVE_DAMAGE_CEILING)
	var t: float = clampf((sqrt(maxf(float(amount), CARVE_DAMAGE_FLOOR)) - lo)
		/ maxf(hi - lo, 0.001), 0.0, 1.0)
	return lerpf(CARVE_DAMAGE_SCALE_MIN, CARVE_DAMAGE_SCALE_MAX, t)


## The damage-only curve, kept for the call site that has a damage number and nothing
## else. It is now defined AS the size rule with the fallback footprint, so there is one
## curve in this file and not two that can drift apart.
static func carve_radius_for(amount: int) -> float:
	return carve_radius_for_strike(amount, CARVE_FALLBACK_FOOTPRINT)


# ── the anti-cascade ledger ────────────────────────────────────────────────
## May `source` open a crater of `radius` at `at`? No, if it already opened one whose
## centre is within `CARVE_REPEAT_BITE` of ITS radius. See that constant for why this is
## spatial and not a cooldown.
##
## A null source is always admitted: a bolt that dies on impact cannot repeat itself,
## and making every projectile allocate a ledger entry would be pure cost.
## ⚠ `radius` IS THE NEW CRATER'S AND IS DELIBERATELY NOT READ. The question is
## whether this point is inside ground the source ALREADY took, so the test is against
## the OLD crater's radius. Comparing against the new one instead would let a source
## widen its own hole indefinitely by escalating — which is the erosion this exists to
## stop. It stays in the signature so the two ledger calls read alike at the call site.
func _ledger_admits(source: Object, _new_radius: float, at: Vector2) -> bool:
	if source == null or not is_instance_valid(source):
		return true
	var id: int = source.get_instance_id()
	if not _ledger.has(id):
		return true
	for e: Vector3 in (_ledger[id] as Array):
		var old_r: float = e.z
		if Vector2(e.x, e.y).distance_to(at) < old_r * CARVE_REPEAT_BITE:
			return false
	return true


func _ledger_record(source: Object, at: Vector2, radius: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	var id: int = source.get_instance_id()
	if _ledger.size() >= CARVE_LEDGER_SOURCES_MAX and not _ledger.has(id):
		_ledger_sweep()
	var list: Array = _ledger.get(id, []) as Array
	list.append(Vector3(at.x, at.y, radius))
	while list.size() > CARVE_LEDGER_MAX:
		list.remove_at(0)
	_ledger[id] = list


## Drop every source that has been freed. Called only when the table is full, because
## the sweep is O(sources) and a bout opens far fewer than the cap.
func _ledger_sweep() -> void:
	for id: int in _ledger.keys():
		var o: Object = instance_from_id(id)
		if o == null or not is_instance_valid(o):
			_ledger.erase(id)


## Clear every cell whose centre is inside the disc. Returns cells removed.
##
## ⚠ NO CAP ON WHAT COMES OUT, and that is the maker's ruling, not an oversight:
## *"if that happens then it happens it will be a projectile based ending"*. Capping
## chunks-removed to keep the stage crossable is explicitly forbidden by the spec
## (§1). The COSMETIC debris is capped separately, which is a different question.
func carve_disc(world_pos: Vector2, radius: float) -> int:
	if cols <= 0 or rows <= 0 or radius <= 0.0:
		return 0
	var cx0: int = maxi(int(floorf((world_pos.x - radius - origin.x) / CHUNK)), 0)
	var cx1: int = mini(int(ceilf((world_pos.x + radius - origin.x) / CHUNK)), cols - 1)
	var cy0: int = maxi(int(floorf((world_pos.y - radius - origin.y) / CHUNK)), 0)
	var cy1: int = mini(int(ceilf((world_pos.y + radius - origin.y) / CHUNK)), rows - 1)
	var r2: float = radius * radius
	var removed: int = 0
	for cy: int in range(cy0, cy1 + 1):
		var py: float = origin.y + (float(cy) + 0.5) * CHUNK - world_pos.y
		for cx: int in range(cx0, cx1 + 1):
			var px: float = origin.x + (float(cx) + 0.5) * CHUNK - world_pos.x
			if px * px + py * py > r2:
				continue
			if clear_cell(cx, cy):
				removed += 1
	carved_cells += removed
	return removed


## Rubble and a mark, reusing the two systems that already exist for exactly this —
## `DebrisChunk` for the falling stone and `ScorchDecal` for the crack left behind.
## The maker's standing rule: optimise what is here, do not add a new particle system.
##
## Parented to THIS node's parent (the arena, long-lived) rather than to self, so a
## chunk outlives any rebuild of the stage's own subtree. `DestructibleTerrain`
## documents the same choice for the same reason.
func _spawn_carve_spectacle(world_pos: Vector2, radius: float, dir: Vector2) -> void:
	var host: Node = get_parent()
	if host == null or not host.is_inside_tree():
		return
	var away: Vector2 = -dir.normalized() if dir != Vector2.ZERO else Vector2.UP
	# Rock knocked out of the ground goes UP and back along the hit — the same launch
	# shaping `DestructibleTerrain._spawn_breakaway` uses, without a second body type.
	var count: int = clampi(int(radius / 5.0), 2, MAX_DEBRIS_PER_CARVE)
	DebrisChunk.spawn_burst(host, world_pos, ArenaTerrain.ROCK_UPPER, count, away, 240.0)
	ScorchDecal.spawn(host, world_pos, radius * 0.9, "crack",
		Color(0.16, 0.14, 0.13, 0.5), 6.0)


## ══ THE REBUILD, ONCE A FRAME, OFF THE HIT PATH ════════════════════════════
## A carve writes cells and marks blocks. Nothing rebuilds inside the hit, so a Fault
## Line that damages thirty points along the ground costs ONE rebuild of the union of
## the blocks it touched rather than thirty, and a rebuild can never land twice in the
## same frame no matter how many spells resolve in it.
func _process(_delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var pending: int = 0
	var done: int = 0
	var t0: int = Time.get_ticks_usec()
	for by: int in _block_rows:
		for bx: int in _block_cols:
			var b: int = by * _block_cols + bx
			if _block_dirty[b] == 0:
				continue
			pending += 1
			if done >= MAX_BLOCK_REBUILDS_PER_FRAME:
				continue
			# The budget is checked BEFORE the second block and every one after it, so
			# the first always runs: an over-budget frame still makes progress.
			if done > 0 and Time.get_ticks_usec() - t0 >= REBUILD_BUDGET_USEC:
				continue
			_shape_count -= (_block_rects[b] as Array).size()
			_install_block(bx, by)
			done += 1
	if done <= 0:
		return
	var dt: int = Time.get_ticks_usec() - t0
	rebuild_usec_total += dt
	rebuild_usec_worst = maxi(rebuild_usec_worst, dt)
	# ⚠ LOGGED, NEVER SWALLOWED — spec §6.1. A deferral that nobody counts reads as
	# "it all rebuilt" when it did not, and the symptom would be a hole you can see and
	# cannot fall into, one frame late.
	deferred_rebuilds += maxi(pending - done, 0)
	queue_redraw()


## ══ THE HOLE BELONGS TO THE FLOOR IT WAS BLOWN IN ═══════════════════
## Maker: *"destroying the map and stuff is done well but it just needs to match the
## background, the destroyed areas — like make sure it looks and feels actually
## destroyed"*.
##
## `CAVITY_FILL` is one fixed near-black. On the versus stage, whose rock is a fixed
## brown, that reads correctly. The tower tints EVERY floor's ground from its biome
## (`EnvTheme` → `RoomShell.GROUND_MIX`), so the same constant would punch an
## identical brown-black hole in a blue Frostmarch slab and an orange Emberworks one
## — a sticker laid on the floor rather than a hole in it. The caller pushes its own
## rock colour through `set_palette` and the hole becomes a shadow in THAT rock.
##
## The lit cap on a newly exposed surface stays constant across biomes on purpose:
## it is RULE 1 of the stage legend (`StageLayers`) — warm horizontal means YOU CAN
## STAND ON THIS — and a legend that changes colour per floor is not a legend.
var cavity_color: Color = CAVITY_FILL


## Point the hole colour at the rock this stage is cut into. Safe to call every floor.
func set_palette(rock: Color) -> void:
	cavity_color = Color(rock.r * CAVITY_MIX, rock.g * CAVITY_MIX, rock.b * CAVITY_MIX, 1.0)
	queue_redraw()


func _draw() -> void:
	for b: int in _block_cavities.size():
		for r: Rect2 in _block_cavities[b]:
			draw_rect(r, cavity_color, true)
	for b2: int in _block_caps.size():
		for c: Rect2 in _block_caps[b2]:
			draw_rect(c, NEW_SURFACE_CAP, true)


# ═══════════════════════════════════════════════════════════════ THE LEDGE
## Hang a chunk grid on a platform body so the ledge carves the way the ground does.
##
## `body` keeps everything it already had — its layer, its `"destructible"` membership,
## its `damage_at` — and gains the merged collision of a grid plus `BODY_META`, which is
## what makes the six `carve_from_body` call sites (`Spell`, `BeamSpell`, `BoulderHurl`,
## `DivineRay`, `EnergyNova`, `RiftDagger`) start biting ledges for free.
##
## ⚠ `size` IS THE BODY'S OWN LOCAL RECT, centred on its origin, because that is where
## both platform drawers put their slab. The grid, the cavities it paints and the
## shapes it installs are all in that one space; see `space`.
##
## ⚠ MEASURED, NOT ASSUMED — the grid a ledge gets is TINY. `CHUNK` is 4 px and
## `FloorGen.PLATFORM_H` is 24, so a ledge is SIX CELLS DEEP and 28-60 wide. That is
## under one `BLOCK_W` x `BLOCK_H` (48x48) block, so a ledge is a ONE-BLOCK stage: a
## carve dirties one or two blocks rather than the ground stage's thirty, and the
## re-merge walks ~150-330 cells rather than 68,926.
##
## MEASURED by `tools/probe_platform_carve_cost.gd`, and it is the answer to the fair
## objection that N ledges each rebuilding their own collision is N times the cost:
##     12 ledges (100-210 px), ALL carved and ALL re-merged in the SAME frame
##       worst frame 1,235 us   mean frame 839 us   deferred rebuilds 0
## Against a 16,667 us frame, and against the 767-897 us mean / 1,713-1,886 us worst the
## GROUND stage costs for ONE hit. So a whole floor's ledges carving at once costs about
## what one ground carve costs, and nothing is ever pushed to a later frame — which
## matters more than the mean, because a deferral is a hole you can see and cannot fall
## into, one frame late.
##
## The reason it is that cheap is structural rather than lucky: `_process` only walks
## DIRTY blocks, a ledge has at most two of them, and the merge is O(cells in the block).
##
## ⚠ AND SIX CELLS DEEP IS WHY A LEDGE NEEDS A COLLAPSE RULE THE GROUND DOES NOT.
## `CARVE_RADIUS_MAX` is 46 px — wider than a ledge is tall, twice over — so one heavy
## hit takes the FULL DEPTH across ~92 px of a 110-200 px plank. The ground absorbs that
## (its terraces are 320 px deep); a ledge cannot. Owners therefore watch
## `widest_standable_run` and take the whole thing when what is left is a splinter.
static func attach_ledge(body: StaticBody2D, size: Vector2, rock: Color) -> DestructibleStage:
	if body == null or size.x <= 0.0 or size.y <= 0.0:
		return null
	var s := DestructibleStage.new()
	s.name = "CarveGrid"
	s.advertise_in_group = false   # see `advertise_in_group` — the first-member trap
	s.spectacle = false            # the owner fires its own, ledge-sized
	s.space = body
	s.seam_grow_down = 2.0         # see `seam_grow_down` — 8 is a third of a plank
	s.build_from_rects([Rect2(-size * 0.5, size)] as Array[Rect2])
	body.add_child(s)
	# ⚠ NOT `HAZARD` HERE. `_ready` parked it on the pit rung (-5) because a hole in the
	# GROUND draws behind everything you stand on. A hole in a LEDGE has to draw over
	# the ledge's own slab or it is painted out by it, so it shares the ledge's rung and
	# wins on tree order (a child draws after its parent at equal z).
	StageLayers.apply(s, StageLayers.PLATFORM)
	s.rebuild_collision(body, body)
	s.set_palette(rock)
	return s


## The widest unbroken run of columns that still hold rock, in world px. THE ledge
## question: not "how much is left" but "is any of what is left wide enough to land on".
## A plank carved into three 8 px slivers has a healthy `solid_fraction` and nothing you
## can stand on.
func widest_standable_run() -> float:
	if cols <= 0 or rows <= 0:
		return 0.0
	var best: int = 0
	var run: int = 0
	for cx: int in cols:
		var any: bool = false
		for cy: int in rows:
			if _solid[cy * cols + cx] == 1:
				any = true
				break
		if any:
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return float(best) * CHUNK


## How much of the rock this stage was built with is still there. The complement of
## `carved_fraction`, kept separate because that one counts EVENTS (`carved_cells`) and
## this one counts the grid — they disagree the moment a grid is rebuilt under a
## reforming ledge, and the owner's collapse test must read the grid.
func solid_fraction() -> float:
	var was: int = 0
	for b: int in _original:
		was += b
	if was <= 0:
		return 0.0
	return float(solid_count()) / float(was)


# ═══════════════════════════════════════════════════════ CALL-SITE HELPERS

## The live stage, or null. One group scan; the group holds exactly one node.
static func stage_in(ctx: Node) -> DestructibleStage:
	if ctx == null or not ctx.is_inside_tree():
		return null
	var tree: SceneTree = ctx.get_tree()
	if tree == null:
		return null
	for n: Node in tree.get_nodes_in_group(GROUP_NAME):
		var s: DestructibleStage = n as DestructibleStage
		if s != null and is_instance_valid(s):
			return s
	return null


## Route a hit that landed on a specific body. Carves ONLY if that body is the stage's
## own collider, so a bolt stopping on a ruin platform or a rim cannot punch the ground
## underneath it. Returns cells removed; 0 whenever the flag is off, because with the
## flag off there is no stage node and `get_meta` finds nothing.
static func carve_from_body(hit: Object, amount: int, world_pos: Vector2,
		dir: Vector2, footprint: float = 0.0, source: Object = null) -> int:
	if hit == null or not is_instance_valid(hit):
		return 0
	var n: Node = hit as Node
	if n == null or not n.has_meta(BODY_META):
		return 0
	var s: DestructibleStage = n.get_meta(BODY_META) as DestructibleStage
	if s == null or not is_instance_valid(s):
		return 0
	return s.damage_at(amount, world_pos, dir, footprint, source)


## Route an AREA hit that never touched a body — a blast, a nova, a ground slam. The
## stage is found by group, and the carve is refused where there is no rock, so a blast
## detonating in mid-air over a pit removes nothing.
static func carve_area(ctx: Node, amount: int, world_pos: Vector2, dir: Vector2,
		footprint: float = 0.0, source: Object = null) -> int:
	var s: DestructibleStage = stage_in(ctx)
	if s == null:
		return 0
	return s.damage_at(amount, world_pos, dir, footprint,
		source if source != null else ctx)
