class_name DestructibleTerrain
extends StaticBody2D
## Destructible arena terrain: a stone block that physically BLOCKS movement —
## real cover, unlike the pass-through crate prop — until spells and hard hits
## chew through it. The block face is modelled as a GRID OF CELLS: every hit
## knocks a cluster of cells out of the face and launches each one as a REAL
## falling physics chunk (RigidBody2D, gravity, tumble, settle), so specific
## parts visibly break off and land on the floor instead of the block merely
## growing cracks. The face redraws with only the still-intact cells, so the
## block gets progressively chewed apart / pockmarked. At zero hp (or when
## almost nothing is left standing) the remaining cells all burst off at once
## and the block frees, opening the space so the arena can be torn apart.
## Group "destructible" + take_damage is the damage routing contract
## (mirrors DestructibleProp.gd / the "enemy" pattern in Enemy.gd).
## damage_at(amount, world_pos, dir) is the aimed variant: projectiles blow a
## hole where they actually land and eject the parts along their travel dir.
##
## Collision: layer 5 = bit 1 (blocks hero/enemy movement like the walls)
## + bit 4 (the Spell projectile's Area2D mask only scans layer 4, so the
## block must sit there too or bolts would fly straight through it).
## The collider stays ONE full RectangleShape2D until destruction — the
## chip-away is visual; shrinking the collider mid-fight risks trapping a
## fighter inside a re-carved shape, and cover that "leaks" at the pocks
## would read as a bug.

# Non-lethal hit feedback: brief lighten + a tiny visual jolt (per the crate).
const HIT_FLASH_TIME: float = 0.09
const HIT_NUDGE: float = 2.0  # px — terrain is heavier than a crate, jolts less
# The collider sinks this far into the ground below so there's no flush T-junction
# seam a CharacterBody could slip through (the "walk under/into the block" bug).
const GROUND_OVERLAP_MARGIN: float = 8.0
# Cell grid: the face is carved into ~this-sized squares; each knocked-out
# cell becomes one recognizable flying "part" (bigger than DebrisChunk dust).
const TARGET_CELL_SIZE: float = 12.0  # smaller cells -> more, finer chip chunks
const MIN_CELLS_PER_AXIS: int = 2
const MAX_CELLS_PER_AXIS: int = 12
# Per-hit caps so a big AoE sweep can't spawn hundreds of bodies in one frame.
const MAX_CELLS_PER_HIT: int = 8
const MAX_CHUNKS_PER_HIT: int = 8
const SHATTER_CHUNK_CAP: int = 14
# When this few cells survive, the block is structurally done: full shatter
# even if hp bookkeeping says a sliver remains (a floating 2-cell crumb
# blocking movement would look absurd).
const SHATTER_MIN_CELLS: int = 3
# Knock-out selection: cells nearest the hit go first, and cells with an
# already-exposed face get a head start so the block crumbles inward from
# its wounds/edges instead of losing random interior teeth.
const EXPOSED_EDGE_BONUS: float = 10.0  # px subtracted from the distance score
# Breakaway part launch shaping.
const PART_SPEED: float = 240.0  # px/s initial launch
const PART_SPEED_VARIANCE: float = 0.3  # +/- fraction
const PART_SPREAD_ARC: float = 0.7  # rad each side around the launch dir
const PART_UPWARD_BIAS: float = 0.55  # blended UP so parts arc, not skid
# Small stone-dust pop layered under every hit (parts carry the spectacle,
# dust sells the impact frame).
const CHIP_AMOUNT: int = 5
const CHIP_LIFETIME: float = 0.35
const CHIP_VELOCITY_MIN: float = 70.0
const CHIP_VELOCITY_MAX: float = 160.0
const CHIP_SCALE_MIN: float = 1.5
const CHIP_SCALE_MAX: float = 3.0
const CHIP_DAMPING_MIN: float = 40.0
const CHIP_DAMPING_MAX: float = 100.0
# Shatter spectacle tuning — the dust layer under the final all-cells burst.
const DEBRIS_AMOUNT: int = 18
const DEBRIS_LIFETIME: float = 0.6
const DEBRIS_VELOCITY_MIN: float = 140.0
const DEBRIS_VELOCITY_MAX: float = 340.0
const DEBRIS_SCALE_MIN: float = 3.0
const DEBRIS_SCALE_MAX: float = 6.5
const DEBRIS_DAMPING_MIN: float = 60.0
const DEBRIS_DAMPING_MAX: float = 140.0
# Small-scale rubble alongside the shatter (DebrisChunk = 4-9 px stones; the
# breakaway parts are the cell-sized recognizable pieces).
const RUBBLE_CHUNK_COUNT: int = 6
const RUBBLE_CHUNK_SPEED: float = 260.0
const SHATTER_SHAKE: float = 4.0
# Per-cell shade jitter so the face reads as fitted masonry, not a flat fill.
# HALVED from 0.07: at the framing zoom the old jitter turned a 64 px block into a
# grey checkerboard that read as noise and pulled the eye off the fighters. Texture
# is for when you stop and look; the block's job in motion is to be one mass.
const CELL_SHADE_VARIANCE: float = 0.035
const EXPOSED_EDGE_WIDTH: float = 1.5
## Length of the amber corner brackets. RULE 2 of the stage legend (see
## StageLayers): a lit cap says "standable", amber says "and it breaks". Corners
## rather than a full rim, so cover is never mistaken for a breakable LEDGE.
const BREAK_TICK: float = 7.0

@export var block_size: Vector2 = Vector2(64, 64)
## Higher than the old 60 so a single blast (~40) CHIPS a corner instead of near-
## destroying the block — cover erodes over several hits then collapses (maker:
## "parts break off WHERE HIT, not the entire thing").
@export var max_hp: int = 120
## Cooled and darkened from 0.42/0.44/0.5. At the played framing the old value made
## the cover blocks the BRIGHTEST things on the stage after the sky — louder than the
## fighters and louder than the ledges the player is trying to read. Cover is a mass
## to hide behind; the lit cap added in `_draw` is what carries its readability now.
@export var base_color: Color = Color(0.30, 0.31, 0.36)

var hp: int = 60
var _flash_timer: float = 0.0
var _nudge: Vector2 = Vector2.ZERO
var _cols: int = 4
var _rows: int = 4
var _cell_size: Vector2 = Vector2(16, 16)
var _cells: Array[bool] = []  # true = intact, indexed row * _cols + col
var _cell_shades: Array[float] = []  # baked per-cell lighten/darken offsets
var _intact_count: int = 0


func _ready() -> void:
	# ⚠ THIS DREW AT z 0 — the fighters' own layer — because it set no z_index. See
	# StageLayers for the one table every stage drawer now reads.
	StageLayers.apply(self, StageLayers.COVER)
	add_to_group("destructible")
	hp = max_hp
	collision_layer = 5  # bits 1 + 4, see header
	var shape: RectangleShape2D = RectangleShape2D.new()
	# Grow the collider DOWN by the overlap margin (the visual face stays block_size)
	# so it overlaps the ground instead of sharing a flush seam — no slip-through.
	shape.size = block_size + Vector2(0.0, GROUND_OVERLAP_MARGIN)
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0.0, GROUND_OVERLAP_MARGIN * 0.5)  # keep the TOP edge fixed
	add_child(collider)  # centered on origin, like the drawn face
	_build_cell_grid()
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0:
			_nudge = Vector2.ZERO
		queue_redraw()


## Un-aimed damage entry point (the group contract — many systems call this
## with only an amount). Delegates to damage_at with a default hit-site of
## the top-centre of the face and an upward ejection dir, so even blind
## damage reads as the block being chewed from its exposed top.
func take_damage(amount: int) -> void:
	damage_at(amount, to_global(Vector2(0.0, -block_size.y * 0.5)), Vector2.UP)


## Aimed damage: knocks out the cluster of cells NEAREST world_pos (with a
## bias toward already-exposed cells so the block crumbles from its wounds)
## and launches each knocked-out cell as a real physics part along `dir`.
## A bolt blows a visible hole exactly where it lands. At hp<=0, or when so
## few cells survive the block can't plausibly stand, everything left bursts
## off and the node frees.
func damage_at(amount: int, world_pos: Vector2, dir: Vector2) -> void:
	if hp <= 0:
		return  # already shattering this frame — post-death hits are no-ops
	hp = max(hp - amount, 0)
	if hp == 0:
		_shatter(dir)
		return
	_knock_out_cells(amount, world_pos, dir)
	if _intact_count <= SHATTER_MIN_CELLS:
		_shatter(dir)
		return
	_flash_timer = HIT_FLASH_TIME
	_nudge = Vector2.from_angle(randf() * TAU) * HIT_NUDGE
	_spawn_chip_burst(world_pos)
	queue_redraw()  # the face just lost cells


## The payoff: every surviving cell breaks off as a tumbling physics part,
## plus the dust burst + small rubble, then gone — the open space IS the
## reward. Leaves the group immediately so same-frame radius queries (blast)
## don't re-hit it.
func _shatter(dir: Vector2) -> void:
	remove_from_group("destructible")
	_burst_remaining_cells(dir)
	_spawn_debris_burst()
	DebrisChunk.spawn_burst(
		get_parent(), global_position, base_color, RUBBLE_CHUNK_COUNT, Vector2.ZERO, RUBBLE_CHUNK_SPEED
	)
	Juice.shake_camera(SHATTER_SHAKE)
	Sfx.play("enemy_death")
	queue_free()


## Carve block_size into a near-square grid of ~TARGET_CELL_SIZE cells and
## bake a per-cell shade so the face reads as fitted stonework.
func _build_cell_grid() -> void:
	_cols = clampi(roundi(block_size.x / TARGET_CELL_SIZE), MIN_CELLS_PER_AXIS, MAX_CELLS_PER_AXIS)
	_rows = clampi(roundi(block_size.y / TARGET_CELL_SIZE), MIN_CELLS_PER_AXIS, MAX_CELLS_PER_AXIS)
	_cell_size = Vector2(block_size.x / float(_cols), block_size.y / float(_rows))
	_intact_count = _cols * _rows
	_cells.clear()
	_cell_shades.clear()
	_cells.resize(_intact_count)
	_cell_shades.resize(_intact_count)
	for i: int in _intact_count:
		_cells[i] = true
		_cell_shades[i] = randf_range(-CELL_SHADE_VARIANCE, CELL_SHADE_VARIANCE)


## Centre of cell `index` in LOCAL space (face is centred on the origin).
func _cell_center_local(index: int) -> Vector2:
	@warning_ignore("integer_division")
	var row: int = index / _cols
	var col: int = index % _cols
	return Vector2(
		-block_size.x * 0.5 + (float(col) + 0.5) * _cell_size.x,
		-block_size.y * 0.5 + (float(row) + 0.5) * _cell_size.y
	)


## A cell is "exposed" when any 4-neighbour is missing or out of bounds —
## border cells start exposed; interiors become exposed as the face erodes.
func _cell_exposed(index: int) -> bool:
	@warning_ignore("integer_division")
	var row: int = index / _cols
	var col: int = index % _cols
	if row == 0 or row == _rows - 1 or col == 0 or col == _cols - 1:
		return true
	return (
		not _cells[index - _cols] or not _cells[index + _cols]
		or not _cells[index - 1] or not _cells[index + 1]
	)


## How many cells this hit chips: LOCAL to the impact + scaled by damage, NOT the
## global hp fraction (which made a single blast erase most of the face -> "shatters
## whole"). A ~40-dmg blast chips ~2 cells near the hit; the block erodes over
## several hits then collapses at hp 0. At least 1 so every hit visibly bites.
func _chip_count(amount: int) -> int:
	return clampi(int(ceil(float(amount) / 22.0)), 1, MAX_CELLS_PER_HIT)


## Remove the cluster of intact cells nearest the hit (exposed cells first)
## and launch each as a breakaway physics part along `dir`.
func _knock_out_cells(amount: int, world_pos: Vector2, dir: Vector2) -> void:
	var local_pos: Vector2 = to_local(world_pos)
	var candidates: Array[int] = []
	for i: int in _cells.size():
		if _cells[i]:
			candidates.append(i)
	if candidates.is_empty():
		return
	var scores: Dictionary = {}
	for i: int in candidates:
		var score: float = _cell_center_local(i).distance_to(local_pos)
		if _cell_exposed(i):
			score -= EXPOSED_EDGE_BONUS
		scores[i] = score
	candidates.sort_custom(
		func(a: int, b: int) -> bool: return scores[a] < scores[b]
	)
	# Chip only the few cells NEAREST the hit (nearest-first sort above) so a hit
	# bites a local hole, not a swath across the whole face.
	var knock: int = mini(_chip_count(amount), candidates.size())
	var chunk_budget: int = mini(MAX_CHUNKS_PER_HIT, _debris_headroom())
	for k: int in knock:
		var index: int = candidates[k]
		_cells[index] = false
		_intact_count -= 1
		if k < chunk_budget:
			_spawn_breakaway(index, dir)


## Final burst: every still-intact cell flies off radially (capped so a
## near-full block dying at once stays within the debris budget).
func _burst_remaining_cells(dir: Vector2) -> void:
	var budget: int = mini(SHATTER_CHUNK_CAP, _debris_headroom())
	var spawned: int = 0
	for i: int in _cells.size():
		if not _cells[i]:
			continue
		_cells[i] = false
		if spawned < budget:
			var out_dir: Vector2 = _cell_center_local(i)
			if out_dir == Vector2.ZERO:
				out_dir = dir if dir != Vector2.ZERO else Vector2.UP
			_spawn_breakaway(i, out_dir)
			spawned += 1
	_intact_count = 0


## One knocked-out cell -> one tumbling RigidBody2D part, cell-sized and
## tinted from base_color, launched out+up along `dir` so it arcs off the
## block and lands on the floor. Parented to the block's parent (the arena —
## long-lived), never to self: self may queue_free this same frame.
func _spawn_breakaway(index: int, dir: Vector2) -> void:
	var parent: Node = get_parent()
	if parent == null or not parent.is_inside_tree():
		return  # teardown mid-blast — mirrors DebrisChunk.spawn_burst's guard
	var part: BreakawayPart = BreakawayPart.new()
	part.part_color = _vary_color(base_color, _cell_shades[index])
	part.part_size = minf(_cell_size.x, _cell_size.y)
	parent.add_child(part)
	part.global_position = to_global(_cell_center_local(index))
	var out_dir: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.UP
	out_dir = out_dir.rotated(randf_range(-PART_SPREAD_ARC, PART_SPREAD_ARC))
	var launch_dir: Vector2 = (out_dir + Vector2.UP * PART_UPWARD_BIAS).normalized()
	part.launch(
		launch_dir * PART_SPEED
		* randf_range(1.0 - PART_SPEED_VARIANCE, 1.0 + PART_SPEED_VARIANCE)
	)


## Remaining headroom under DebrisChunk's global live-body cap — breakaway
## parts join the same "debris_chunk" group so dust rubble + parts share one
## perf budget instead of stacking two caps.
func _debris_headroom() -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	var live: int = 0
	for chunk: Node in tree.get_nodes_in_group(DebrisChunk.GROUP_NAME):
		if is_instance_valid(chunk) and not chunk.is_queued_for_deletion():
			live += 1
	return maxi(DebrisChunk.MAX_LIVE_CHUNKS - live, 0)


## Slight tint variance per part (DebrisChunk._vary_color's idea), seeded
## from the cell's baked shade so a part matches the face it broke off.
func _vary_color(color: Color, shade: float) -> Color:
	if shade < 0.0:
		return color.darkened(-shade * 2.0)
	return color.lightened(shade * 2.0)


## Small stone-dust pop on every surviving hit, at the hit-site.
func _spawn_chip_burst(world_pos: Vector2) -> void:
	CombatVfx.spawn_burst(
		get_parent(), world_pos,
		base_color.lightened(0.3), Color(base_color.r, base_color.g, base_color.b, 0.0),
		CHIP_AMOUNT, CHIP_LIFETIME,
		CHIP_VELOCITY_MIN, CHIP_VELOCITY_MAX,
		CHIP_SCALE_MIN, CHIP_SCALE_MAX,
		CHIP_DAMPING_MIN, CHIP_DAMPING_MAX
	)


## Stone-tinted particle burst via the shared builder (crate's shatter, scaled up).
func _spawn_debris_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		base_color.lightened(0.2), Color(base_color.r, base_color.g, base_color.b, 0.0),
		DEBRIS_AMOUNT, DEBRIS_LIFETIME,
		DEBRIS_VELOCITY_MIN, DEBRIS_VELOCITY_MAX,
		DEBRIS_SCALE_MIN, DEBRIS_SCALE_MAX,
		DEBRIS_DAMPING_MIN, DEBRIS_DAMPING_MAX
	)


func _draw() -> void:
	var half: Vector2 = block_size * 0.5
	var edge_color: Color = base_color.darkened(0.45)
	for i: int in _cells.size():
		if not _cells[i]:
			continue
		@warning_ignore("integer_division")
		var row: int = i / _cols
		var col: int = i % _cols
		var origin: Vector2 = (
			Vector2(-half.x + float(col) * _cell_size.x, -half.y + float(row) * _cell_size.y)
			+ _nudge
		)
		var cell_color: Color = _vary_color(base_color, _cell_shades[i])
		if _flash_timer > 0.0:
			cell_color = cell_color.lightened(0.45)
		draw_rect(Rect2(origin, _cell_size), cell_color)
		# RULE 1 of the stage legend: EVERY upward-facing exposed cell wears the lit
		# cap, because every one of them is a surface a fighter can land on — including
		# the shelves left behind as the block is chewed apart. Same light as the ground
		# crust and the ruin ledges, so "I can stand there" is one signal everywhere.
		if row == 0 or not _cells[i - _cols]:
			var cap: float = StageLayers.cap_height(_cell_size.y)
			draw_rect(Rect2(origin, Vector2(_cell_size.x, cap)), StageLayers.CAP_CORE)
			draw_rect(Rect2(origin, Vector2(_cell_size.x, maxf(cap * 0.45, 1.0))),
				StageLayers.CAP_LIT)
		# Dark lines only along EXPOSED faces: the silhouette (and every bite
		# taken out of it) gets a crisp edge, interior seams stay soft.
		if row == 0 or not _cells[i - _cols]:
			draw_line(origin, origin + Vector2(_cell_size.x, 0.0), edge_color, EXPOSED_EDGE_WIDTH)
		if row == _rows - 1 or not _cells[i + _cols]:
			var bottom: Vector2 = origin + Vector2(0.0, _cell_size.y)
			draw_line(bottom, bottom + Vector2(_cell_size.x, 0.0), edge_color, EXPOSED_EDGE_WIDTH)
		if col == 0 or not _cells[i - 1]:
			draw_line(origin, origin + Vector2(0.0, _cell_size.y), edge_color, EXPOSED_EDGE_WIDTH)
		if col == _cols - 1 or not _cells[i + 1]:
			var right: Vector2 = origin + Vector2(_cell_size.x, 0.0)
			draw_line(right, right + Vector2(0.0, _cell_size.y), edge_color, EXPOSED_EDGE_WIDTH)
	# RULE 2: amber corner brackets — "this mass comes apart". Drawn on the block's
	# own silhouette rather than per cell, so a half-eaten block still declares it.
	if _intact_count > 0:
		var amber: Color = StageLayers.BREAK_AMBER
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var c: Vector2 = Vector2(half.x * sx, half.y * sy) + _nudge
				draw_line(c, c - Vector2(BREAK_TICK * sx, 0.0), amber, 1.5, true)
				draw_line(c, c - Vector2(0.0, BREAK_TICK * sy), amber, 1.5, true)


## One breakaway PART: a cell-sized tumbling stone slab with real gravity —
## bigger and more recognizable than DebrisChunk's 4-9 px dust stones, but
## the same physics recipe (dedicated layer 6, mask 1: rests on platforms,
## passes through fighters and other debris). Joins DebrisChunk's group so
## the global live-debris cap covers both. Headless-safe: no autoloads,
## pure physics + _draw. Launch goes through _integrate_forces because
## damage often arrives from physics-flush signals (Spell.body_entered)
## where poking a fresh RigidBody2D's velocity directly is unsafe.
class BreakawayPart extends RigidBody2D:
	const LIFETIME_MIN: float = 1.3
	const LIFETIME_MAX: float = 2.0
	const FADE_TIME: float = 0.45
	const SPIN_MAX: float = 10.0  # rad/s initial tumble
	const LINEAR_DAMP_AMOUNT: float = 0.35
	const ANGULAR_DAMP_AMOUNT: float = 3.0
	const SURFACE_FRICTION: float = 0.9
	const SURFACE_BOUNCE: float = 0.12

	var part_color: Color = Color(0.42, 0.44, 0.5)
	var part_size: float = 14.0

	var _verts: PackedVector2Array = PackedVector2Array()
	var _age: float = 0.0
	var _lifetime: float = 1.6
	var _pending_launch: Vector2 = Vector2.ZERO
	var _pending_spin: float = 0.0
	var _launched: bool = false

	## Queue the one-shot launch velocity (applied on the first physics step).
	func launch(velocity: Vector2) -> void:
		_pending_launch = velocity
		_pending_spin = randf_range(-SPIN_MAX, SPIN_MAX)

	func _ready() -> void:
		# Debris rung, not the fighters'. A tumbling slab that crosses in FRONT of a
		# 31 px stick figure hides it for the frames that matter most — the ones right
		# after the hit that made the debris.
		StageLayers.apply(self, StageLayers.DEBRIS)
		add_to_group(DebrisChunk.GROUP_NAME)
		collision_layer = DebrisChunk.CHUNK_LAYER
		collision_mask = DebrisChunk.CHUNK_MASK
		gravity_scale = 1.0
		linear_damp = LINEAR_DAMP_AMOUNT
		angular_damp = ANGULAR_DAMP_AMOUNT
		contact_monitor = false  # no contact reports needed — cheapest config
		max_contacts_reported = 0
		var surface: PhysicsMaterial = PhysicsMaterial.new()
		surface.friction = SURFACE_FRICTION
		surface.bounce = SURFACE_BOUNCE
		physics_material_override = surface
		_lifetime = randf_range(LIFETIME_MIN, LIFETIME_MAX)
		_generate_shape()
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = Vector2.ONE * part_size * 0.7  # a touch inside the silhouette
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.shape = shape
		add_child(collider)
		queue_redraw()

	func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
		if _launched:
			return
		_launched = true
		state.linear_velocity = _pending_launch
		state.angular_velocity = _pending_spin

	## Fly + settle for _lifetime, fade over FADE_TIME, then free.
	func _process(delta: float) -> void:
		_age += delta
		if _age >= _lifetime + FADE_TIME:
			queue_free()
		elif _age >= _lifetime:
			modulate.a = clampf(1.0 - (_age - _lifetime) / FADE_TIME, 0.0, 1.0)

	## Bake one chipped-slab silhouette: a cell-sized quad with jittered
	## corners so parts read as broken masonry, not perfect tiles.
	func _generate_shape() -> void:
		_verts.clear()
		var half: float = part_size * 0.5
		var corners: Array[Vector2] = [
			Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half),
		]
		for corner: Vector2 in corners:
			_verts.append(corner + Vector2(
				randf_range(-half * 0.3, half * 0.3),
				randf_range(-half * 0.3, half * 0.3)
			))

	func _draw() -> void:
		if _verts.size() < 3:
			return
		draw_colored_polygon(_verts, part_color)
		var outline: PackedVector2Array = _verts.duplicate()
		outline.append(_verts[0])
		draw_polyline(outline, part_color.darkened(0.3), 1.0)
