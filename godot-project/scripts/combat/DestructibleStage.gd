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

var origin: Vector2 = Vector2.ZERO      ## world position of cell (0, 0)'s top-left
var cols: int = 0
var rows: int = 0

## One byte per cell, row-major. 1 = intact rock, 0 = air. A PackedByteArray rather than
## a 2D Array because it is read once per cell per rebuild and allocation-free indexing
## is the whole budget.
var _solid: PackedByteArray = PackedByteArray()

var _body: StaticBody2D = null
var _shape_count: int = 0


## Lay a grid over `rects` (world-space, e.g. the terrace boxes) and mark every cell
## whose CENTRE falls inside one of them as intact.
##
## ⚠ CENTRE-SAMPLED ON PURPOSE. Sampling by overlap would mark a cell solid when a rect
## clips one pixel of it, growing the stage by up to a chunk on every edge — including
## upward, which moves the walking surface. Centre-sampling can only ever lose a sliver
## smaller than half a chunk, and the surface lands on a chunk boundary because the grid
## is aligned to the rects below.
func build_from_rects(rects: Array[Rect2]) -> void:
	if rects.is_empty():
		cols = 0
		rows = 0
		_solid = PackedByteArray()
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


func is_solid(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
		return false
	return _solid[cy * cols + cx] == 1


## Clear one cell. Slice 2 will call this from the damage contract; Slice 1 only needs
## it so the merge can be tested against a hole.
func clear_cell(cx: int, cy: int) -> void:
	if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
		return
	_solid[cy * cols + cx] = 0


func solid_count() -> int:
	var n: int = 0
	for b: int in _solid:
		n += b
	return n


func shape_count() -> int:
	return _shape_count


## GREEDY MERGE: the intact grid as a small set of rectangles.
##
## Row-major sweep. For each un-consumed run of solid cells in a row, extend the run
## DOWNWARD as long as every row below carries the identical span, then consume the
## whole block. This is the standard rectangle decomposition, and it is chosen over
## anything cleverer because it is the one whose failure mode is "more rectangles than
## strictly necessary" rather than "a hole nobody can see".
func merged_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if cols <= 0 or rows <= 0:
		return out
	var used: PackedByteArray = PackedByteArray()
	used.resize(cols * rows)
	for cy: int in rows:
		var cx: int = 0
		while cx < cols:
			var i: int = cy * cols + cx
			if _solid[i] == 0 or used[i] == 1:
				cx += 1
				continue
			# Widest run on this row.
			var span: int = 0
			while cx + span < cols:
				var j: int = cy * cols + cx + span
				if _solid[j] == 0 or used[j] == 1:
					break
				span += 1
			# Deepest block with that exact span.
			var depth: int = 1
			while cy + depth < rows:
				var ok: bool = true
				for k: int in span:
					var j2: int = (cy + depth) * cols + cx + k
					if _solid[j2] == 0 or used[j2] == 1:
						ok = false
						break
				if not ok:
					break
				depth += 1
			for dy: int in depth:
				for dx: int in span:
					used[(cy + dy) * cols + cx + dx] = 1
			out.append(Rect2(
				origin + Vector2(float(cx) * CHUNK, float(cy) * CHUNK),
				Vector2(float(span) * CHUNK, float(depth) * CHUNK)))
			cx += span
	return out


## Build (or rebuild) the single collision body from the current grid.
func rebuild_collision(parent: Node) -> StaticBody2D:
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
	_body = StaticBody2D.new()
	_body.name = "DestructibleStageBody"
	var rects: Array[Rect2] = merged_rects()
	_shape_count = rects.size()
	for r: Rect2 in rects:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		# ⚠ SIDEWAYS AND DOWN ONLY. See the seam rule at the top of this file: the top
		# edge is the walking surface and must land exactly where the source rect put it.
		shape.size = Vector2(r.size.x + SEAM_OVERLAP_X * 2.0, r.size.y + SEAM_GROW_DOWN)
		cs.shape = shape
		cs.position = Vector2(r.position.x + r.size.x * 0.5,
			r.position.y + (r.size.y + SEAM_GROW_DOWN) * 0.5)
		_body.add_child(cs)
	parent.add_child(_body)
	return _body


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
