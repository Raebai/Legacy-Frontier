class_name GroundCrater
extends Node2D
## A persistent CRATER gouged into the floor where a big hit lands: a dark gouge +
## a raised broken rim + a few edge chunks (maker: "carve VISIBLE CRATERS into the
## floor where big hits land"). Accumulates as the arena wrecks, capped so a long
## fight can't flood the screen. Mirrors ScorchDecal's lifecycle + z-order; uses NO
## autoloads (draw + one raycast only), so the headless harness can load() it.

const GROUP_NAME: String = "ground_crater"
## ⚠ 44 -> 20, AND THE CAP WAS THE SMALLEST PART OF THE PROBLEM. Maker: "I don't
## like how those cracks and spheres look on the ground... less in your face and
## goofy". Cropped and looked at: the gouges were near-OPAQUE BLACK ELLIPSES wider
## than a fighter is tall, with a hard bright rim, stacking into one solid dark mass
## that sat visually ON TOP of the crates it was supposed to be under.
##
## Four causes, all of them here, in the order they hurt:
##   1. `gouge_tint` alpha 0.8 of near-black, drawn as THREE stacked discs — the
##      middle of a crater was a hole in the floor rather than a mark on it.
##   2. the rim's lit arc was brightened x1.3 on top of a 0.95 alpha, which is what
##      made each one read as a cartoon sticker with an outline.
##   3. the chunks were `rim_tint` at 0.95 — opaque brown slabs, and they are the
##      big flat rectangles in the frame.
##   4. and 44 of them compounding turned all of the above into a floor-wide bruise.
##
## A crater is a STAIN AND A SHADOW, not a pit. Everything below is the same drawing
## at a weight the eye reads as damage instead of as decoration.
const MAX_CRATERS: int = 20        # session cap; oldest freed past this
const SNAP_MAX_DIST: float = 260.0 # downward raycast reach to find the floor

@export var radius: float = 40.0
## Warmer and far lighter than the old near-black: a gouge tinted toward the floor's
## own colour reads as ground that has been hurt, where 0.05-grey reads as a hole cut
## in the level.
@export var gouge_tint: Color = Color(0.16, 0.13, 0.12, 0.34)
@export var rim_tint: Color = Color(0.34, 0.28, 0.22, 0.55)

var _chunks: Array[PackedVector2Array] = []


## Spawn a crater under `parent` at `world_pos`. snap=true raycasts DOWN (mask 1)
## to seat it on the floor and SKIPS (frees itself) when nothing is below (over a
## pit) so craters never float. snap=false places exactly at world_pos.
static func spawn(parent: Node, world_pos: Vector2, crater_radius: float, snap: bool = true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	# ⚠ THIS HAD NO BUDGET GATE AND NO O(1) CAP, AND IT IS A BOSS-FIGHT PROBLEM.
	# Maker: *"the third and 4th boss and probably onwards cast too much stuff at the
	# same time it lags the whole game out"*. A crater is scenery — nothing reads the
	# floor to decide anything — so it is exactly the thing to skip when the arena is
	# already carrying its effect budget. `ScorchDecal.spawn` has had this guard for a
	# while and the two systems stack on the SAME floor; only one of them was paying
	# attention. The Illuminator's `psalm` alone asks for FOURTEEN of these inside about
	# a second, each costing a downward raycast plus (below) an allocating group walk.
	if SpellReactorNode.vfx_over_budget():
		_skipped += 1
		return
	_spawned += 1
	var c := GroundCrater.new()
	c.radius = crater_radius
	c.z_index = -1
	parent.add_child(c)
	c.add_to_group(GROUP_NAME)  # membership NOW so the cap counts it this frame
	c.global_position = world_pos
	if snap:
		var world: World2D = c.get_world_2d()
		if world != null:
			var q := PhysicsRayQueryParameters2D.create(world_pos, world_pos + Vector2(0.0, SNAP_MAX_DIST), 1)
			var hit: Dictionary = world.direct_space_state.intersect_ray(q)
			if hit.is_empty():
				c.queue_free()  # over a pit — no floating crater
				return
			c.global_position = hit["position"]
	# ⚠ GATED BEHIND AN O(1) COUNTER, like `ScorchDecal` and `DebrisChunk` already are.
	# This used to run on EVERY crater and it is a group walk that allocates twice —
	# once for `get_nodes_in_group`'s array and again for the typed one built from it.
	# So a boss barrage paid an O(n) allocating scan per mark to discover, almost every
	# time, that it was nowhere near the cap.
	if _alive > MAX_CRATERS:
		_enforce_cap(parent.get_tree())


## Live craters, O(1) — see the note at the `_enforce_cap` call site.
static var _alive: int = 0
## Deterministic work counters, matching `ScorchDecal.work_stats`: the harness
## measures COUNTS rather than milliseconds, so a budget regression is a failing
## assertion rather than a stopwatch reading that drifts with the machine.
static var _spawned: int = 0
static var _skipped: int = 0


static func alive_count() -> int:
	return _alive


static func work_stats() -> Dictionary:
	return {"spawned": _spawned, "skipped": _skipped}


static func reset_count() -> void:
	_alive = 0
	_spawned = 0
	_skipped = 0


## Cap against unbounded growth: past MAX_CRATERS, free the oldest (add order).
static func _enforce_cap(tree: SceneTree) -> void:
	if tree == null:
		return
	var alive: Array[Node] = []
	for cr: Node in tree.get_nodes_in_group(GROUP_NAME):
		if is_instance_valid(cr) and not cr.is_queued_for_deletion():
			alive.append(cr)
	var overflow: int = alive.size() - MAX_CRATERS
	for i: int in overflow:
		alive[i].queue_free()


var _counted: bool = false


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_alive += 1
	_counted = true
	_bake_chunks()
	queue_redraw()


## Counter safety net — a crater freed with its arena still has to give its slot back,
## or `_alive` ratchets up and every spawn starts paying for the group walk the counter
## exists to avoid. Same shape as `ScorchDecal._exit_tree`.
func _exit_tree() -> void:
	if _counted:
		_counted = false
		_alive = maxi(_alive - 1, 0)


## Pre-bake the broken edge-chunk quads once so _draw stays deterministic. Chunk
## centres sit on the (squashed) rim ellipse; the quads themselves are un-squashed.
func _bake_chunks() -> void:
	var n: int = 5
	for i: int in n:
		var a: float = TAU * float(i) / float(n) + randf_range(-0.3, 0.3)
		var c: Vector2 = Vector2(cos(a) * radius * randf_range(0.85, 1.05), sin(a) * radius * 0.5 * randf_range(0.85, 1.05))
		var s: float = radius * randf_range(0.14, 0.24)
		_chunks.append(PackedVector2Array([
			c + Vector2(-s, -s * 0.6), c + Vector2(s, -s * 0.4), c + Vector2(s * 0.7, s), c + Vector2(-s * 0.8, s * 0.7),
		]))


func _draw() -> void:
	# Gouge: concentric dark discs squashed onto the floor plane (a flat ellipse,
	# reading as a pit dug into the ground rather than a face-on disc).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	# THREE DISCS, BUT THEY NO LONGER COMPOUND TO OPAQUE. The old ramp ran
	# 0.32 / 0.56 / 0.80 of a near-black; this one runs 0.10 / 0.20 / 0.34 of a warm
	# dark, so the centre of a crater is a stain you can still see the floor through.
	# ⚠ AND NOT A PERFECT CIRCLE, which was the rest of the "goofy". A blast does not
	# leave a compass-drawn disc; three concentric perfect ellipses read as a target
	# painted on the floor. Each ring is a jittered polygon instead, seeded off the
	# crater's own position so it is stable frame to frame (a gouge that reshuffled
	# every redraw would boil) and different from its neighbours.
	_ragged(radius, Color(gouge_tint.r, gouge_tint.g, gouge_tint.b, gouge_tint.a * 0.30), 0)
	_ragged(radius * 0.62, Color(gouge_tint.r, gouge_tint.g, gouge_tint.b, gouge_tint.a * 0.60), 7)
	_ragged(radius * 0.3, gouge_tint, 13)
	# The rim is a LIP CATCHING LIGHT, not an outline. The x1.3 brightening is gone —
	# that highlight is most of what made these read as stickers — and both arcs are
	# thinner and softer.
	draw_arc(Vector2.ZERO, radius, PI, TAU, 22, Color(rim_tint.r, rim_tint.g, rim_tint.b, rim_tint.a * 0.7), 1.4, true)
	draw_arc(Vector2.ZERO, radius, 0.0, PI, 22, Color(0.12, 0.1, 0.09, rim_tint.a * 0.5), 1.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Broken rock chunks seated on the rim.
	# Chunks at the rim's own (now much lower) alpha — they were opaque slabs, and at
	# crater sizes they are the big flat rectangles the maker was looking at.
	for ch: PackedVector2Array in _chunks:
		draw_colored_polygon(ch, Color(rim_tint.r, rim_tint.g, rim_tint.b, rim_tint.a * 0.75))


## One ring of the gouge as a torn polygon. `salt` offsets the seed so the three
## rings are not the same shape scaled, which would look like a printed target.
##
## Deterministic in the crater's WORLD POSITION rather than in a counter: two
## craters that land in the same place across a replay draw the same scar, and the
## shape never changes under a redraw.
func _ragged(r: float, col: Color, salt: int) -> void:
	var pts := PackedVector2Array()
	var seed_i: int = int(absf(global_position.x) * 7.0 + absf(global_position.y) * 13.0) + salt
	var steps: int = 14
	for i: int in steps:
		var a: float = TAU * float(i) / float(steps)
		# Cheap deterministic hash -> 0..1, then a +-18% radius wobble.
		var h: int = (seed_i * 1103515245 + i * 12345) & 0x7FFFFFFF
		var n: float = float(h % 1000) / 1000.0
		pts.append(Vector2.from_angle(a) * (r * (0.82 + 0.36 * n)))
	draw_colored_polygon(pts, col)
