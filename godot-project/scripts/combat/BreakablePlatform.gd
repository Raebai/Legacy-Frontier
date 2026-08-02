class_name BreakablePlatform
extends StaticBody2D
## A platform you can stand/jump on AND destroy — then it REGENERATES naturally
## after a while (the maker's ask). A lean single-hp break/reform state machine
## (NOT DestructibleTerrain's cell-grid, which frees permanently on shatter):
## spells / melee / hard knockback-slams chew its hp; at zero it shatters into
## debris, drops its collider + visual for `regen_time`, warns with a fading
## outline in the last second, then reforms with a poof. An amber rim marks it as
## the breakable one (permanent ledges have a green rim). Group "destructible" +
## take_damage/damage_at is the damage-routing contract (like DestructibleTerrain).

@export var platform_size: Vector2 = Vector2(160, 22)
@export var max_hp: int = 50
@export var regen_time: float = 6.0
@export var base_color: Color = Color(0.20, 0.22, 0.29)

const REFORM_WARNING_TIME: float = 1.0
## ⚠ AMBER IS RULE 2 OF THE STAGE LEGEND (see StageLayers): a lit cap says "you can
## land here", and amber says "and it breaks". Both come from StageLayers so this
## ledge and a permanent one are the same shape in different paint — which is the
## only way the difference between them is learnable at 31 px.
const BREAK_EDGE_COLOR: Color = StageLayers.BREAK_AMBER
const HIT_FLASH_TIME: float = 0.09
const HIT_NUDGE: float = 2.0
const REFORM_POOF_START: Color = Color(0.75, 0.85, 1.0, 0.9)
const REFORM_POOF_END: Color = Color(0.75, 0.85, 1.0, 0.0)

var hp: int = 50
var _broken: bool = false
var _regen_timer: float = 0.0
var _flash_timer: float = 0.0
var _nudge: Vector2 = Vector2.ZERO
var _collider: CollisionShape2D = null


func _ready() -> void:
	# ⚠ THE BUG THE MAKER PLAYED INTO. This drawer set no z_index at all, so it sat
	# at 0 — the fighters' own layer — and drew among them. See StageLayers.
	StageLayers.apply(self, StageLayers.PLATFORM)
	add_to_group("destructible")
	add_to_group("breakable_platform")
	hp = max_hp
	collision_layer = 5  # bit1 (blocks + supports movement) + bit3 (spell-Area2D bucket)
	var shape := RectangleShape2D.new()
	shape.size = platform_size
	_collider = CollisionShape2D.new()
	_collider.shape = shape
	add_child(_collider)
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0:
			_nudge = Vector2.ZERO
		queue_redraw()
	if _broken:
		_regen_timer -= delta
		if _regen_timer <= REFORM_WARNING_TIME:
			queue_redraw()  # fade the "it's coming back" outline in
		if _regen_timer <= 0.0:
			_reform()


## Group contract entry (blind damage): chew from the centre.
func take_damage(amount: int) -> void:
	damage_at(amount, global_position, Vector2.UP)


func damage_at(amount: int, world_pos: Vector2, dir: Vector2) -> void:
	if _broken:
		return
	hp = max(hp - amount, 0)
	if hp == 0:
		_break(dir)
		return
	_flash_timer = HIT_FLASH_TIME
	_nudge = Vector2.from_angle(randf() * TAU) * HIT_NUDGE
	CombatVfx.spawn_burst(
		get_parent(), world_pos, base_color.lightened(0.3),
		Color(base_color.r, base_color.g, base_color.b, 0.0), 5, 0.35, 70.0, 160.0, 1.5, 3.0
	)
	queue_redraw()


func _break(dir: Vector2) -> void:
	_broken = true
	remove_from_group("destructible")  # same-frame AoE queries don't re-hit a dead platform
	_collider.disabled = true
	visible = false
	DebrisChunk.spawn_burst(get_parent(), global_position, base_color, 10, dir, 260.0)
	ScorchDecal.spawn(get_parent(), global_position, platform_size.x * 0.4, "crack", Color(0.2, 0.15, 0.1, 0.6))
	Juice.shake_camera(4.0)
	Sfx.play("enemy_death")
	_regen_timer = regen_time


func _reform() -> void:
	_broken = false
	hp = max_hp
	_collider.disabled = false
	visible = true
	add_to_group("destructible")
	CombatVfx.spawn_burst(
		get_parent(), global_position, REFORM_POOF_START, REFORM_POOF_END,
		18, 0.4, 60.0, 150.0, 1.5, 3.5
	)
	Juice.shake_camera(2.0)
	Sfx.play("blink", -4.0, 0.1)  # magical materialise cue (closest existing sfx)
	queue_redraw()


func _draw() -> void:
	if _broken:
		# Fading dashed "it's coming back" outline in the last warning second.
		if _regen_timer <= REFORM_WARNING_TIME:
			var a: float = clampf(1.0 - _regen_timer / REFORM_WARNING_TIME, 0.0, 1.0)
			var half: Vector2 = platform_size * 0.5
			draw_rect(Rect2(-half, platform_size), Color(BREAK_EDGE_COLOR.r, BREAK_EDGE_COLOR.g, BREAK_EDGE_COLOR.b, 0.4 * a), false, 2.0)
		return
	var half2: Vector2 = platform_size * 0.5
	var o: Vector2 = -half2 + _nudge
	var w: float = platform_size.x
	var h: float = platform_size.y
	var cap: float = StageLayers.cap_height(h)
	var body_col: Color = base_color.lightened(0.45) if _flash_timer > 0.0 else base_color
	# Body + a dark underside so the silhouette detaches from the floor wash.
	draw_rect(Rect2(o, platform_size), body_col)
	draw_rect(Rect2(o + Vector2(0.0, h - cap * 0.6), Vector2(w, cap * 0.6)),
		StageLayers.UNDERSIDE)
	# RULE 1 + RULE 2: the lit cap says "land here", in amber because it breaks.
	draw_rect(Rect2(o, Vector2(w, cap)), StageLayers.BREAK_AMBER_DIM)
	draw_rect(Rect2(o, Vector2(w, maxf(cap * 0.45, 1.5))), BREAK_EDGE_COLOR)
	# Fracture hairlines across the body — "fragile" said quietly, under the cap, so
	# it never competes with the cap for the eye.
	var seams: int = maxi(2, int(w / 40.0))
	for s in range(1, seams):
		var sx: float = o.x + w * float(s) / float(seams)
		draw_line(Vector2(sx, o.y + cap), Vector2(sx + 3.0, o.y + h - 1.0),
			StageLayers.BREAK_AMBER_DIM, 1.0, true)
	draw_rect(Rect2(o, platform_size), StageLayers.EDGE_DARK, false, 1.0)
