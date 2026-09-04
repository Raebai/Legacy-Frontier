class_name ScorchDecal
extends Node2D
## Persistent floor damage decal: a scorch splotch or crack lines drawn once in
## _draw() and left alive for the whole session — the ACCUMULATION is the
## point (the arena visibly wrecks as the fight goes on). Sits at z_index -1:
## above the Floor (z -2 in Arena.tscn) but below characters (z 0).

const GROUP_NAME: String = "floor_decal"
const MAX_DECALS: int = 60  # session safety cap: oldest decals free past this
## ⚠ THE CAP IGNORED `graphics_quality`, AND A DECAL IS A PER-FRAME COST FOREVER.
## Every other pooled effect in this repo caps lower on the phone — `DeathSmudge`
## has MAX_ALIVE_LOW, `ElementFx` has MAX_ALIVE_LOW, `CombatVfx` thins — but this
## one did not, and it is the layer whose whole design is ACCUMULATION. A decal
## draws once and is then RETAINED: its commands are re-submitted to the renderer
## on every frame for the rest of the session, and a crack is ~28 individually
## tapered `draw_line`s (the taper is per-segment on purpose; see `_draw_crack`).
## Sixty of those is a standing bill of roughly 1,700 line primitives a frame that
## nothing in the fight is looking at any more. 24 keeps the arena visibly wrecked
## — the point of the system — at 40% of the standing cost.
const MAX_DECALS_LOW: int = 24
## ⚠ FIVE EVENLY-SPACED SPOKES AROUND A PERFECT DISC IS A COMPASS ROSE, NOT A CRACK.
## Maker: *"those weird circular cracks in the floor"*. That is this — `_draw_crack`
## was the one arm of the two decal systems that never got the ragged treatment the
## scorch and the crater both did, and radial symmetry is what made it read as a
## printed symbol rather than damage. Real fractures are uneven in COUNT, ANGLE,
## REACH and WIDTH, and they branch. All four are now varied off the same
## position-seeded hash `_ragged` uses, so a crack is stable across redraws and two
## cracks in the same place across a replay still draw the same mark.
const CRACK_LINE_COUNT: int = 7   # candidates; roughly a third are dropped per decal
const CRACK_SEGMENTS: int = 4
const CRACK_WIDTH: float = 2.0
const CRACK_JAG: float = 0.30  # lateral jitter as a fraction of radius
const FADE_OUT: float = 1.6  # seconds of alpha ramp before a lifetime'd decal frees

## ⚠ A DECAL IS FLOOR DAMAGE AND IT HAD NO WAY TO CHECK THERE WAS A FLOOR.
## Maker: *"when something gets destroyed it shouldnt leave like a crack in the air"*.
## `GroundCrater` has raycast down and freed itself over a pit since it was written;
## this class, which stacks on the SAME floor, never did — so a body slammed into a
## WALL and a breakable platform shattering in mid-air both left a mark hanging in
## space with no crater beside it (the crater at the same call site correctly vanished).
## Opt-IN rather than default-on, because most call sites already pass a known floor
## point and silently raycasting those would delete correctly-placed marks the first
## time a ray started flush against the surface it was meant to find.
const SNAP_LIFT: float = 24.0      # start the ray ABOVE the point, so a mark already
                                   # flush with the floor still finds it
const SNAP_MAX_DIST: float = 120.0 # ...and a mark this far above nothing is no mark

@export var radius: float = 24.0
@export var kind: String = "scorch"  # "scorch" | "crack"
## ⚠ LIGHTENED WITH THE CRATERS, and for the same reason — see the block on
## `GroundCrater.MAX_CRATERS`. These two decal systems stack on the SAME floor, so
## toning one and not the other just makes the untouched one the new loudest thing.
## 0.05-grey at 0.55 is a black patch; this is a warm scorch you can see the ground
## through.
@export var tint: Color = Color(0.14, 0.10, 0.08, 0.34)
## 0 = persist for the session (the old accumulate-forever behaviour). > 0 =
## the decal holds, then fades over the last FADE_OUT seconds and frees, so
## meteor/nova scars "clear up over time" instead of cluttering the arena.
@export var lifetime: float = 0.0

var _crack_lines: Array[PackedVector2Array] = []
var _age: float = 0.0
## Counted in `_alive`? Keeps `_exit_tree` from double-decrementing.
var _counted: bool = false


## ⚠ NOTHING IS LEFT ON THE FLOOR ANY MORE. Maker, playing it: *"the meteor fist
## circle that comes after doesnt have to be there in the map, it's weird — it should
## just show the impact on the area hit, way more subtle and cooler effect. in fact
## these things that stay afterwards, remove all of them"*.
##
## ⚠ THIS REVERSES A STATED DESIGN GOAL, and that is worth saying plainly rather than
## quietly deleting: this file's own header argued that "the ACCUMULATION is the point
## (the arena visibly wrecks as the fight goes on)", and `GroundCrater`'s argued the
## same. A ruling from the maker with the game in front of them beats a design note
## written without it. The impact still reads — `CombatVfx.spawn_burst`, the shake,
## the hitstop and the debris all fire exactly as before; what is gone is the MARK
## that outlived them.
##
## Killed at the single spawn gate rather than at the ~30 call sites, so every caller
## keeps its intent and this is one boolean to walk back if the floor turns out to
## look empty without them.
static var leave_marks: bool = false


## Instantiate a decal under `parent` at world `pos`. Null-safe: silently
## skips when the parent is gone (e.g. a blast resolving during teardown).
## `decal_lifetime` > 0 makes it fade + free (see the `lifetime` export).
## `snap` seats the mark on the floor beneath `pos` and SKIPS entirely when there is
## nothing under it — pass it wherever `pos` is a BODY's position rather than a known
## floor point. See the `SNAP_LIFT` block.
static func spawn(
	parent: Node, pos: Vector2, decal_radius: float, decal_kind: String, decal_tint: Color,
	decal_lifetime: float = 0.0, snap: bool = false,
) -> void:
	if not leave_marks:
		return
	if parent == null or not parent.is_inside_tree():
		return
	if snap:
		var snapped: Variant = _floor_under(parent, pos)
		if snapped == null:
			return  # over a pit, or against a wall in mid-air — no floating mark
		pos = snapped
	# A scorch mark is scenery. It carries no gameplay information at all — nothing
	# reads the floor to decide anything — and it is spawned per impact, so a meteor
	# barrage lays down a dozen while the screen is already at its effect budget.
	# First thing to skip, and skipping it costs the player nothing they can act on.
	if SpellReactorNode.vfx_over_budget():
		_skipped += 1
		return
	_spawned += 1
	var decal: ScorchDecal = ScorchDecal.new()
	decal.radius = decal_radius
	decal.kind = decal_kind
	decal.tint = decal_tint
	decal.lifetime = decal_lifetime
	decal.z_index = -1
	parent.add_child(decal)
	decal.global_position = pos
	if _alive > max_decals():
		_enforce_cap(parent.get_tree())


## Fade-and-free for lifetime'd decals (no-op for persistent ones).
func _process(delta: float) -> void:
	if lifetime <= 0.0:
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
	elif _age > lifetime - FADE_OUT:
		modulate.a = clampf((lifetime - _age) / FADE_OUT, 0.0, 1.0)


## The live cap for the current quality setting. A pure static so the degradation
## is arithmetic a headless suite can check, in the same idiom as
## `SpawnTell.redraw_hz` and `Telegraph.ghosts_for`.
static func max_decals() -> int:
	return MAX_DECALS_LOW if TuningConfig.quality_is_low() else MAX_DECALS


## Live decals, O(1). See the note on `_enforce_cap` for why this exists.
static var _alive: int = 0
## Deterministic work counters — see the header on `CombatVfx.work_stats` for why
## the harness measures counts rather than milliseconds.
static var _spawned: int = 0
static var _skipped: int = 0


## Diagnostics + tests.
static func alive_count() -> int:
	return _alive


static func work_stats() -> Dictionary:
	return {"spawned": _spawned, "skipped": _skipped}


## Test hook / arena teardown.
static func reset_count() -> void:
	_alive = 0
	_spawned = 0
	_skipped = 0


## Cheap safety against unbounded growth over a long session: past MAX_DECALS
## live decals, free the oldest (group order follows add order).
##
## ⚠ THIS USED TO RUN ON EVERY SINGLE DECAL SPAWN, and it is a group walk that
## allocates TWICE — once for `get_nodes_in_group`'s array and again for the typed
## `alive` array built from it. A meteor barrage or a nova lays down decals in
## bursts, so the arena's busiest moments paid an O(n) allocating scan per mark to
## discover, almost every time, that it was nowhere near the cap. It is now gated
## behind an O(1) counter and runs only when the cap can actually have been passed,
## which in a normal fight is never. Same fix as `DamageNumber` and `DebrisChunk`.
static func _enforce_cap(tree: SceneTree) -> void:
	if tree == null:
		return
	var alive: Array[Node] = []
	for decal: Node in tree.get_nodes_in_group(GROUP_NAME):
		if is_instance_valid(decal) and not decal.is_queued_for_deletion():
			alive.append(decal)
	var overflow: int = alive.size() - max_decals()
	for i: int in overflow:
		alive[i].queue_free()


## The floor point under `pos`, or null when there is nothing under it within reach.
##
## ⚠ IGNORANCE IS NOT A PIT. When the world cannot be queried at all — a headless
## harness with no physics space, a parent that is not a Node2D — this returns `pos`
## unchanged rather than null, so a decal is only ever DELETED by a ray that actually
## ran and actually found nothing. The opposite default would make every decal test in
## the suite pass by drawing nothing.
static func _floor_under(parent: Node, pos: Vector2) -> Variant:
	var n2: Node2D = parent as Node2D
	if n2 == null or not n2.is_inside_tree():
		return pos
	var world: World2D = n2.get_world_2d()
	if world == null:
		return pos
	# Mask 1 = the ground layer, the same one `GroundCrater` and the rig's own
	# footing probe use. Bodies live on 2/4, so a mark never seats on a fighter.
	var q := PhysicsRayQueryParameters2D.create(
		pos + Vector2(0.0, -SNAP_LIFT), pos + Vector2(0.0, SNAP_MAX_DIST), 1)
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit["position"]


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_alive += 1
	_counted = true
	if kind == "crack":
		_generate_cracks()
	queue_redraw()


## Counter safety net — a decal freed with its arena still has to give its slot
## back, or `_alive` ratchets up and every spawn starts paying for the group walk
## the counter exists to avoid.
func _exit_tree() -> void:
	if _counted:
		_counted = false
		_alive = maxi(_alive - 1, 0)


## Pre-bake the jagged crack geometry once so _draw() stays deterministic.
##
## Seeded off the decal's WORLD POSITION rather than the global RNG, for the reason
## `_ragged` gives: two cracks in the same place across a replay draw the same mark,
## and nothing about the shape can shift under a redraw. Every axis of the old shape
## that was REGULAR is now varied — a fracture that agrees with its neighbours on
## angle, reach and width is a symbol, and a symbol on the floor reads as a bug.
func _generate_cracks() -> void:
	_crack_lines.clear()
	_roll = int(absf(global_position.x) * 7.0 + absf(global_position.y) * 13.0)
	for i: int in CRACK_LINE_COUNT:
		# DROP ROUGHLY A THIRD. An uneven COUNT is most of what stops a mark reading
		# as a compass rose, and it costs nothing to not draw a line.
		if _next() < 0.34:
			continue
		# Wander far off the even spoke — most of the gap either way — so no two
		# cracks in the arena share a silhouette.
		var angle: float = TAU * float(i) / float(CRACK_LINE_COUNT) \
			+ (_next() - 0.5) * (TAU / float(CRACK_LINE_COUNT)) * 1.6
		var reach: float = radius * (0.42 + 0.58 * _next())
		var dir: Vector2 = Vector2.from_angle(angle)
		var lateral: Vector2 = Vector2.from_angle(angle + PI * 0.5)
		var points: PackedVector2Array = PackedVector2Array()
		points.append(Vector2.ZERO)
		for s: int in CRACK_SEGMENTS:
			var t: float = float(s + 1) / float(CRACK_SEGMENTS)
			# Jitter GROWS along the line: a fracture is tight at the impact and
			# wanders as it runs out, which a constant jag cannot show.
			var jag: float = radius * CRACK_JAG * (_next() - 0.5) * 2.0 * t
			points.append(dir * reach * t + lateral * jag)
		_crack_lines.append(points)
		# ...and every so often it FORKS. One branch off the midpoint is the single
		# cheapest thing that makes a set of lines read as stone giving way rather
		# than as spokes.
		if _next() < 0.42:
			var from: Vector2 = points[maxi(points.size() / 2, 1)]
			var bdir: Vector2 = Vector2.from_angle(angle + (_next() - 0.5) * 1.3)
			var blen: float = reach * (0.22 + 0.30 * _next())
			_crack_lines.append(PackedVector2Array([
				from, from + bdir * blen * 0.5, from + bdir * blen,
			]))
	# A mark with nothing left on it after the drops is not a mark. Guarantee one.
	if _crack_lines.is_empty():
		_crack_lines.append(PackedVector2Array([
			Vector2.ZERO, Vector2.from_angle(float(_roll % 628) * 0.01) * radius * 0.8,
		]))


## Position-seeded 0..1 stream, advanced in place.
##
## ⚠ DELIBERATELY A METHOD AND NOT A LAMBDA. GDScript lambdas capture the local
## environment BY VALUE, so a counter incremented inside one is not reliably the same
## counter on the next call — which would have made every draw of every crack read the
## same hash and put the compass rose straight back.
var _roll: int = 0


func _next() -> float:
	_roll = (_roll * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_roll % 10007) / 10007.0


func _draw() -> void:
	if kind == "crack":
		_draw_crack()
	else:
		_draw_scorch()


## Soft dark radial splotch: concentric translucent splotches, densest at center.
##
## ⚠ THESE WERE PERFECT CIRCLES, and that is the half of the "goofy" the tone pass
## did not touch. The craters were re-toned AND torn (`GroundCrater._ragged`); the
## scorches were only re-toned, so the smooth pale discs left on the floor were
## these. Fire does not leave a compass-drawn disc, and three concentric perfect
## circles read as a target painted on the ground rather than a burn. Same
## treatment, same reason.
func _draw_scorch() -> void:
	_ragged(radius, Color(tint.r, tint.g, tint.b, tint.a * 0.35), 0)
	_ragged(radius * 0.66, Color(tint.r, tint.g, tint.b, tint.a * 0.6), 7)
	_ragged(radius * 0.34, tint, 13)


## One ring of the splotch as a torn polygon. `salt` offsets the seed so the three
## rings are not one shape scaled, which is what makes a printed-target look.
##
## Deterministic in the decal's WORLD POSITION rather than in a counter, so the
## shape is stable across redraws (a scorch that reshuffled every frame would boil)
## and two decals in the same place across a replay draw the same mark. Copied
## deliberately from `GroundCrater._ragged` — these two systems stack on the SAME
## floor, and a torn crater next to a compass-drawn scorch just moves the problem.
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


## Small dark impact chip at the center plus jagged radiating lines.
##
## ⚠ THE CHIP WAS A `draw_circle`. That is the "weird CIRCULAR crack" in the maker's
## report, literally — a compass-drawn disc with five even spokes off it. It gets the
## same torn polygon the scorch rings and the crater gouges already use, so the two
## decal systems that stack on one floor now agree about what damage looks like.
func _draw_crack() -> void:
	_ragged(radius * 0.19, tint, 21)
	# Thinner as they run out, and never all the same weight. A polyline is one width
	# end to end, so the taper is done by drawing each segment separately — cheap at
	# four segments, and it is the difference between a drawn line and a split.
	var idx: int = 0
	for line: PackedVector2Array in _crack_lines:
		idx += 1
		var n: int = line.size() - 1
		for s: int in n:
			var t: float = float(s) / float(maxi(n, 1))
			var w: float = CRACK_WIDTH * (1.0 - 0.55 * t) * (0.75 + 0.25 * float(idx % 3))
			draw_line(line[s], line[s + 1],
				Color(tint.r, tint.g, tint.b, tint.a * (1.0 - 0.35 * t)), maxf(w, 0.6))
