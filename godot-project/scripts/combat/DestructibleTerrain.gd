class_name DestructibleTerrain
extends StaticBody2D
## Destructible arena terrain: a stone block that physically BLOCKS movement —
## real cover, unlike the pass-through crate prop — until spells and hard hits
## chew through it. Damage reads visually as accumulating cracks; at zero hp it
## bursts into rubble the way DestructibleProp shatters, leaves a crack decal
## on the floor and frees, opening the space so the arena can be torn apart.
## Group "destructible" + take_damage is the damage routing contract
## (mirrors DestructibleProp.gd / the "enemy" pattern in Enemy.gd).
##
## Collision: layer 5 = bit 1 (blocks hero/enemy movement like the walls)
## + bit 4 (the Spell projectile's Area2D mask only scans layer 4, so the
## block must sit there too or bolts would fly straight through it).

# Non-lethal hit feedback: brief lighten + a tiny visual jolt (per the crate).
const HIT_FLASH_TIME: float = 0.09
const HIT_NUDGE: float = 2.0  # px — terrain is heavier than a crate, jolts less
# Small chip burst on every non-lethal hit: stone dust, not spectacle.
const CHIP_AMOUNT: int = 6
const CHIP_LIFETIME: float = 0.35
const CHIP_VELOCITY_MIN: float = 70.0
const CHIP_VELOCITY_MAX: float = 160.0
const CHIP_SCALE_MIN: float = 1.5
const CHIP_SCALE_MAX: float = 3.0
const CHIP_DAMPING_MIN: float = 40.0
const CHIP_DAMPING_MAX: float = 100.0
# Shatter spectacle tuning — chunky: fewer/larger/faster than a spell hit.
const DEBRIS_AMOUNT: int = 18
const DEBRIS_LIFETIME: float = 0.6
const DEBRIS_VELOCITY_MIN: float = 140.0
const DEBRIS_VELOCITY_MAX: float = 340.0
const DEBRIS_SCALE_MIN: float = 3.0
const DEBRIS_SCALE_MAX: float = 6.5
const DEBRIS_DAMPING_MIN: float = 60.0
const DEBRIS_DAMPING_MAX: float = 140.0
# Flying rubble chunks (real Node2Ds, beyond the particle burst — same
# mechanism as DestructibleProp's plank chunks, tinted stone).
const RUBBLE_CHUNK_COUNT: int = 8
const RUBBLE_CHUNK_SPEED: float = 260.0  # px/s initial launch (physics chunks)
const SHATTER_SHAKE: float = 4.0
# Progressive damage cracks across the block face.
const MAX_CRACKS: int = 6
const CRACK_SEGMENTS: int = 3
const CRACK_JAG: float = 0.18  # lateral jitter as a fraction of the short side
const CRACK_WIDTH: float = 1.5

@export var block_size: Vector2 = Vector2(64, 64)
@export var max_hp: int = 60
@export var base_color: Color = Color(0.42, 0.44, 0.5)  # stone-ish

var hp: int = 60
var _flash_timer: float = 0.0
var _nudge: Vector2 = Vector2.ZERO
var _crack_lines: Array[PackedVector2Array] = []


func _ready() -> void:
	add_to_group("destructible")
	hp = max_hp
	collision_layer = 5  # bits 1 + 4, see header
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = block_size
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)  # centered on origin, like the drawn rect
	_generate_cracks()
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0:
			_nudge = Vector2.ZERO
		queue_redraw()


func take_damage(amount: int) -> void:
	if hp <= 0:
		return  # already shattering this frame — post-death hits are no-ops
	hp = max(hp - amount, 0)
	if hp == 0:
		_shatter()
		return
	_flash_timer = HIT_FLASH_TIME
	_nudge = Vector2.from_angle(randf() * TAU) * HIT_NUDGE
	_spawn_chip_burst()
	queue_redraw()  # one more crack may have become visible


## The payoff: chunky debris burst + flying rubble chunks + a persistent crack
## decal on the floor, then gone — the open space IS the reward. Leaves the
## group immediately so same-frame radius queries (blast) don't re-hit it.
func _shatter() -> void:
	remove_from_group("destructible")
	_spawn_debris_burst()
	# Real-physics rubble that bursts radially out of the block and tumbles onto
	# the floor (replaces the old flat ColorRect-tween chunks). No floor decal:
	# the block stood in the AIR, so a crack mark there just floated as spider
	# legs — the flying chunks + burst convey the destruction on their own.
	DebrisChunk.spawn_burst(
		get_parent(), global_position, base_color, RUBBLE_CHUNK_COUNT, Vector2.ZERO, RUBBLE_CHUNK_SPEED
	)
	Juice.shake_camera(SHATTER_SHAKE)
	Sfx.play("enemy_death")
	queue_free()


## Small stone-dust pop on every surviving hit, tinted from base_color.
func _spawn_chip_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
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


## Pre-bake the full jagged crack set once (ScorchDecal's approach) so _draw()
## stays deterministic; damage only changes how many of them are revealed.
func _generate_cracks() -> void:
	_crack_lines.clear()
	var half: Vector2 = block_size * 0.5
	var jag_reach: float = minf(half.x, half.y) * CRACK_JAG
	for i: int in MAX_CRACKS:
		var start: Vector2
		var end: Vector2
		if i % 2 == 0:  # spans left edge -> right edge
			start = Vector2(-half.x, randf_range(-half.y, half.y) * 0.85)
			end = Vector2(half.x, randf_range(-half.y, half.y) * 0.85)
		else:  # spans top edge -> bottom edge
			start = Vector2(randf_range(-half.x, half.x) * 0.85, -half.y)
			end = Vector2(randf_range(-half.x, half.x) * 0.85, half.y)
		var lateral: Vector2 = (end - start).orthogonal().normalized()
		var points: PackedVector2Array = PackedVector2Array()
		points.append(start)
		for s: int in CRACK_SEGMENTS - 1:
			var t: float = float(s + 1) / float(CRACK_SEGMENTS)
			points.append(start.lerp(end, t) + lateral * jag_reach * randf_range(-1.0, 1.0))
		points.append(end)
		_crack_lines.append(points)


## How many of the pre-baked cracks the current damage reveals: 0 near full
## hp, several near death, so damage reads before the block breaks.
func _visible_crack_count() -> int:
	var safe_max: int = maxi(max_hp, 1)
	var damage_frac: float = 1.0 - float(hp) / float(safe_max)
	return clampi(floori(damage_frac * float(MAX_CRACKS)), 0, MAX_CRACKS)


func _draw() -> void:
	var half: Vector2 = block_size * 0.5
	var rect: Rect2 = Rect2(-half + _nudge, block_size)
	var body_color: Color = base_color
	if _flash_timer > 0.0:
		body_color = base_color.lightened(0.45)
	# Chunky rounded-ish read: full rect + a slightly-inset lighter top bevel.
	draw_rect(rect, body_color)
	draw_rect(
		Rect2(rect.position + Vector2(3.0, 3.0), Vector2(block_size.x - 6.0, 4.0)),
		body_color.lightened(0.12)
	)
	draw_rect(rect, base_color.darkened(0.4), false, 2.0)
	# Progressive cracks: reveal more of the pre-baked set as hp drops.
	var crack_color: Color = base_color.darkened(0.55)
	for c: int in _visible_crack_count():
		var line: PackedVector2Array = _crack_lines[c]
		for s: int in line.size() - 1:
			draw_line(line[s] + _nudge, line[s + 1] + _nudge, crack_color, CRACK_WIDTH)
