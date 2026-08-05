class_name ScorchDecal
extends Node2D
## Persistent floor damage decal: a scorch splotch or crack lines drawn once in
## _draw() and left alive for the whole session — the ACCUMULATION is the
## point (the arena visibly wrecks as the fight goes on). Sits at z_index -1:
## above the Floor (z -2 in Arena.tscn) but below characters (z 0).

const GROUP_NAME: String = "floor_decal"
const MAX_DECALS: int = 60  # session safety cap: oldest decals free past this
const CRACK_LINE_COUNT: int = 5
const CRACK_SEGMENTS: int = 3
const CRACK_WIDTH: float = 2.0
const CRACK_JAG: float = 0.18  # lateral jitter as a fraction of radius
const FADE_OUT: float = 1.6  # seconds of alpha ramp before a lifetime'd decal frees

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


## Instantiate a decal under `parent` at world `pos`. Null-safe: silently
## skips when the parent is gone (e.g. a blast resolving during teardown).
## `decal_lifetime` > 0 makes it fade + free (see the `lifetime` export).
static func spawn(
	parent: Node, pos: Vector2, decal_radius: float, decal_kind: String, decal_tint: Color,
	decal_lifetime: float = 0.0,
) -> void:
	if parent == null or not parent.is_inside_tree():
		return
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
	if _alive > MAX_DECALS:
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
	var overflow: int = alive.size() - MAX_DECALS
	for i: int in overflow:
		alive[i].queue_free()


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
func _generate_cracks() -> void:
	_crack_lines.clear()
	for i: int in CRACK_LINE_COUNT:
		var angle: float = TAU * float(i) / float(CRACK_LINE_COUNT) + randf_range(-0.5, 0.5)
		var reach: float = radius * randf_range(0.6, 1.0)
		var dir: Vector2 = Vector2.from_angle(angle)
		var lateral: Vector2 = Vector2.from_angle(angle + PI * 0.5)
		var points: PackedVector2Array = PackedVector2Array()
		points.append(Vector2.ZERO)
		for s: int in CRACK_SEGMENTS:
			var t: float = float(s + 1) / float(CRACK_SEGMENTS)
			var jag: float = radius * CRACK_JAG * randf_range(-1.0, 1.0)
			points.append(dir * reach * t + lateral * jag)
		_crack_lines.append(points)


func _draw() -> void:
	if kind == "crack":
		_draw_crack()
	else:
		_draw_scorch()


## Soft dark radial splotch: concentric translucent discs, densest at center.
func _draw_scorch() -> void:
	draw_circle(Vector2.ZERO, radius, Color(tint.r, tint.g, tint.b, tint.a * 0.35))
	draw_circle(Vector2.ZERO, radius * 0.66, Color(tint.r, tint.g, tint.b, tint.a * 0.6))
	draw_circle(Vector2.ZERO, radius * 0.34, Color(tint.r, tint.g, tint.b, tint.a))


## Small dark impact chip at the center plus jagged radiating lines.
func _draw_crack() -> void:
	draw_circle(Vector2.ZERO, radius * 0.16, tint)
	for line: PackedVector2Array in _crack_lines:
		draw_polyline(line, tint, CRACK_WIDTH)
