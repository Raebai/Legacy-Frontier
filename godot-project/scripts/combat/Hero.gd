extends CharacterBody2D
## Slice 0 combat protagonist (the mage). Move now; dash + cast added next.

signal health_changed(current: int, maximum: int)

const SPEED: float = 210.0
const DASH_SPEED: float = 620.0
const DASH_TIME: float = 0.14
const DASH_COOLDOWN: float = 0.55
const CAST_COOLDOWN: float = 0.35
const MELEE_COOLDOWN: float = 0.34
const MELEE_DAMAGE: int = 14
const MELEE_RANGE: float = 46.0
const MELEE_ARC_DOT: float = 0.3
const MELEE_KNOCKBACK: float = 220.0
## Melee tuning per weapon kind; the MELEE_* consts are the "fists" baseline.
const WEAPON_STATS: Dictionary = {
	"fists": {"damage": MELEE_DAMAGE, "range": MELEE_RANGE, "knockback": MELEE_KNOCKBACK},
	"sword": {"damage": 26, "range": 60.0, "knockback": 320.0},
}
const BLAST_COOLDOWN: float = 2.0
const BLAST_FALLBACK_RANGE: float = 200.0
## Blink teleport: instant reposition along facing with a shadow-poof at both
## the origin and the destination (the "yin-yang shadow step").
const BLINK_DISTANCE: float = 175.0
const BLINK_COOLDOWN: float = 1.3
const BLINK_IFRAME: float = 0.22
const BLINK_SHADOW_COLOR: Color = Color(0.25, 0.1, 0.35, 0.8)
## Dark-violet particle poof; end alpha 0 so it dissolves instead of popping.
const BLINK_BURST_START: Color = Color(0.4, 0.18, 0.55, 0.9)
const BLINK_BURST_END: Color = Color(0.08, 0.03, 0.15, 0.0)
## Quick bright flash on arrival so the eye snaps to the new position.
const BLINK_ARRIVAL_FLASH_COLOR: Color = Color(0.85, 0.7, 1.0)
const BLINK_ARRIVAL_FLASH_TIME: float = 0.1
## Back off this many px from a wall hit so we never re-embed in the collider.
const BLINK_WALL_MARGIN: float = 2.0
## Input buffer: a melee/dash/blast press that lands while its gate is closed
## (cooldown running, mid-dash) is held this long and fired the moment the
## gate opens — no more silently dropped presses. `cast` is held/continuous
## and stays un-buffered.
const BUFFER_TIME: float = 0.12
## Hit feedback when damage actually lands (not i-framed).
const HURT_FLASH_COLOR: Color = Color(1.0, 0.2, 0.2)
const HURT_FLASH_TIME: float = 0.12
const HURT_HIT_STOP: float = 0.05
const HURT_SHAKE: float = 7.0
## Weighted hitstop: melee connect sits between spell hit and enemy death.
const MELEE_HIT_STOP: float = 0.07
## Directional camera punch along facing when a melee connects (px).
const MELEE_CAMERA_KICK: float = 5.0
## Dash afterimage cadence/tint (~4-5 ghosts across the 0.14s dash).
const GHOST_INTERVAL: float = 0.03
const GHOST_COLOR: Color = Color(0.6, 0.85, 1.0, 0.72)
## Persistent "charged mage" aura (enemies get none — hero reads as hero).
const AURA_COLOR: Color = Color(0.4, 0.7, 1.0, 1.0)
const AURA_STRENGTH: float = 0.6
const SPELL_SCENE: PackedScene = preload("res://scenes/combat/Spell.tscn")
const BLAST_SCENE: PackedScene = preload("res://scenes/combat/BlastSpell.tscn")

@export var max_hp: int = 100
var hp: int = 100
var facing: Vector2 = Vector2.RIGHT
var is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _ghost_timer: float = 0.0
var _cast_cooldown_timer: float = 0.0
var _melee_cooldown_timer: float = 0.0
var _melee_kick_next: bool = false
var _blast_cooldown_timer: float = 0.0
var _blink_cooldown_timer: float = 0.0
var _blink_iframe_timer: float = 0.0
var _weapon: String = "fists"
var _melee_damage: int = MELEE_DAMAGE
var _melee_range: float = MELEE_RANGE
var _melee_knockback: float = MELEE_KNOCKBACK
var _buffered_action: String = ""
var _buffer_timer: float = 0.0

@onready var rig: CharacterRig = $Rig


func _ready() -> void:
	add_to_group("hero")
	hp = max_hp
	health_changed.emit(hp, max_hp)
	rig.set_tint(Color(0.4, 0.7, 1, 1))
	rig.class_preset("mage")
	rig.set_aura(AURA_COLOR, AURA_STRENGTH)
	rig.hit_frame.connect(_on_melee_hit_frame)


func _physics_process(delta: float) -> void:
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)
	_cast_cooldown_timer = max(_cast_cooldown_timer - delta, 0.0)
	_melee_cooldown_timer = max(_melee_cooldown_timer - delta, 0.0)
	_blast_cooldown_timer = max(_blast_cooldown_timer - delta, 0.0)
	_blink_cooldown_timer = maxf(_blink_cooldown_timer - delta, 0.0)
	_blink_iframe_timer = maxf(_blink_iframe_timer - delta, 0.0)
	_update_input_buffer(delta)
	if Input.is_action_pressed("cast") and _cast_cooldown_timer <= 0.0 and not is_dashing:
		_cast()

	if is_dashing:
		_dash_timer -= delta
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			rig.spawn_ghost(get_parent(), GHOST_COLOR, _dash_dir)
		if _dash_timer <= 0.0:
			is_dashing = false
		rig.play(CharacterRig.State.DASH)
		rig.set_facing(facing)
		return

	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	if direction != Vector2.ZERO:
		facing = direction

	if _try_fire_buffered():
		return  # a dash started this frame — the dash branch owns movement now

	velocity = direction * SPEED
	move_and_slide()
	if direction != Vector2.ZERO:
		rig.play(CharacterRig.State.RUN)
	else:
		rig.play(CharacterRig.State.IDLE)
	rig.set_facing(facing)


## Record melee/dash/blast presses into a single-slot buffer (newest press
## wins) and expire the slot after BUFFER_TIME.
func _update_input_buffer(delta: float) -> void:
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	if _buffer_timer <= 0.0:
		_buffered_action = ""
	for action: String in ["melee", "dash", "blast", "blink"]:
		if Input.is_action_just_pressed(action):
			_buffered_action = action
			_buffer_timer = BUFFER_TIME


## Fire the buffered action if its gate is now open, consuming the buffer so
## nothing double-fires. Only called from the not-dashing path, so the old
## `not is_dashing` gates are implicit. Returns true if a dash started (the
## caller must yield the rest of the frame to the dash branch).
func _try_fire_buffered() -> bool:
	if _buffered_action.is_empty():
		return false
	match _buffered_action:
		"melee":
			if _melee_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_melee()
		"blast":
			if _blast_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_blast()
		"dash":
			if _dash_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_start_dash()
				return true
		"blink":
			if _blink_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_blink()
	return false


func _clear_input_buffer() -> void:
	_buffered_action = ""
	_buffer_timer = 0.0


func _start_dash() -> void:
	is_dashing = true
	_dash_timer = DASH_TIME
	_dash_cooldown_timer = DASH_COOLDOWN
	_dash_dir = facing
	_ghost_timer = 0.0  # first afterimage lands this frame


## Shadow blink: instant teleport up to BLINK_DISTANCE along facing, clamped
## so we never land inside a wall. Leaves a dark silhouette + violet poof at
## the origin, another poof + bright flash at the destination, and grants
## BLINK_IFRAME seconds of invulnerability. Buffered like dash/melee/blast;
## only reachable from the not-dashing path (same implicit gate as dash).
func _blink() -> void:
	if _blink_cooldown_timer > 0.0:
		return
	_blink_cooldown_timer = BLINK_COOLDOWN
	_blink_iframe_timer = BLINK_IFRAME
	var origin: Vector2 = global_position
	var dir: Vector2 = facing.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var dest: Vector2 = _blink_destination(origin, dir)
	# Shadow-poof where we WERE: dark fading silhouette + violet burst.
	rig.spawn_ghost(get_parent(), BLINK_SHADOW_COLOR, Vector2.ZERO, Vector2.ZERO, 0.35)
	CombatVfx.spawn_burst(
		get_parent(), origin, BLINK_BURST_START, BLINK_BURST_END,
		18, 0.35, 40.0, 110.0, 1.5, 3.0
	)
	global_position = dest
	# Arrival poof: bigger burst + a quick bright flash on the rig.
	CombatVfx.spawn_burst(
		get_parent(), dest, BLINK_BURST_START, BLINK_BURST_END,
		24, 0.4, 60.0, 140.0, 1.5, 3.5
	)
	rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("cast", -4.0, 0.15)  # pitched wide: reads as a "vwip" teleport


## Safe destination up to BLINK_DISTANCE along `dir`: a test-only
## move_and_collide sweep finds the first wall, and we stop BLINK_WALL_MARGIN
## short of it so the body never teleports inside a collider.
func _blink_destination(origin: Vector2, dir: Vector2) -> Vector2:
	var travel: float = BLINK_DISTANCE
	var collision: KinematicCollision2D = move_and_collide(dir * BLINK_DISTANCE, true)
	if collision != null:
		travel = maxf(collision.get_travel().length() - BLINK_WALL_MARGIN, 0.0)
	return origin + dir * travel


func _cast() -> void:
	_cast_cooldown_timer = CAST_COOLDOWN
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	var dir: Vector2 = Targeting.aim_direction(global_position, enemies, facing)
	var spell: Area2D = SPELL_SCENE.instantiate()
	get_parent().add_child(spell)
	spell.global_position = global_position
	spell.launch(dir)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("cast", 0.0, 0.08)
	Juice.shake_camera(2.0)


func _blast() -> void:
	_blast_cooldown_timer = BLAST_COOLDOWN
	var target: Node2D = Targeting.nearest(
		global_position, get_tree().get_nodes_in_group("enemy")
	)
	var target_pos: Vector2 = (
		target.global_position if target != null
		else global_position + facing * BLAST_FALLBACK_RANGE
	)
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.detonate_at(target_pos)
	rig.play(CharacterRig.State.CAST)


## Equip a weapon kind: swaps the rig's weapon overlay AND retunes the melee
## attack ("gear = visual + ability"). Unknown kinds fall back to fists.
func equip_weapon(kind: String) -> void:
	if not WEAPON_STATS.has(kind):
		kind = "fists"
	_weapon = kind
	var stats: Dictionary = WEAPON_STATS[kind]
	_melee_damage = stats["damage"]
	_melee_range = stats["range"]
	_melee_knockback = stats["knockback"]
	rig.set_equipment("weapon", kind)


func _melee() -> void:
	_melee_cooldown_timer = MELEE_COOLDOWN
	if _melee_kick_next:
		rig.play(CharacterRig.State.KICK)
	else:
		rig.play(CharacterRig.State.PUNCH)
	_melee_kick_next = not _melee_kick_next
	Sfx.play("melee_swing", 0.0, 0.08)


func _on_melee_hit_frame() -> void:
	var hit_any: bool = false
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Node2D:
			continue
		if global_position.distance_to(enemy.global_position) >= _melee_range:
			continue
		var toward: Vector2 = (enemy.global_position - global_position).normalized()
		if facing.dot(toward) <= MELEE_ARC_DOT:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(_melee_damage)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(toward * _melee_knockback)
		hit_any = true
	# Crates break under melee too — same range/arc gate as enemies.
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if not prop is Node2D:
			continue
		if global_position.distance_to(prop.global_position) >= _melee_range:
			continue
		var toward_prop: Vector2 = (prop.global_position - global_position).normalized()
		if facing.dot(toward_prop) <= MELEE_ARC_DOT:
			continue
		if prop.has_method("take_damage"):
			prop.take_damage(_melee_damage)
		hit_any = true
	if hit_any:
		Juice.hit_stop(MELEE_HIT_STOP)  # weighted: heavier than a spell hit
		Juice.shake_camera(4.0)
		Juice.kick_camera(facing, MELEE_CAMERA_KICK)  # punch INTO the hit
		Sfx.play("melee_hit")


func take_damage(amount: int) -> void:
	# DESIGN: dash grants i-frames (full dash duration). Flip to
	# reposition-only by removing this guard.
	if is_dashing:
		return
	# Blink grants a brief post-teleport i-frame window (BLINK_IFRAME).
	if _blink_iframe_timer > 0.0:
		return
	hp = max(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	rig.play(CharacterRig.State.HURT)
	rig.flash_color(HURT_FLASH_COLOR, HURT_FLASH_TIME)
	Juice.hit_stop(HURT_HIT_STOP)
	Juice.shake_camera(HURT_SHAKE)
	Sfx.play("hero_hurt")
	if hp == 0:
		_die()


func _die() -> void:
	# Slice 0: just reset to full so the feel loop never stops.
	hp = max_hp
	health_changed.emit(hp, max_hp)
