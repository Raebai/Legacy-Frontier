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
var _weapon: String = "fists"
var _melee_damage: int = MELEE_DAMAGE
var _melee_range: float = MELEE_RANGE
var _melee_knockback: float = MELEE_KNOCKBACK

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
	if Input.is_action_pressed("cast") and _cast_cooldown_timer <= 0.0 and not is_dashing:
		_cast()
	if Input.is_action_just_pressed("melee") and _melee_cooldown_timer <= 0.0 and not is_dashing:
		_melee()
	if Input.is_action_just_pressed("blast") and _blast_cooldown_timer <= 0.0 and not is_dashing:
		_blast()

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

	if Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		_start_dash()
		return

	velocity = direction * SPEED
	move_and_slide()
	if direction != Vector2.ZERO:
		rig.play(CharacterRig.State.RUN)
	else:
		rig.play(CharacterRig.State.IDLE)
	rig.set_facing(facing)


func _start_dash() -> void:
	is_dashing = true
	_dash_timer = DASH_TIME
	_dash_cooldown_timer = DASH_COOLDOWN
	_dash_dir = facing
	_ghost_timer = 0.0  # first afterimage lands this frame


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
	if hit_any:
		Juice.hit_stop()
		Juice.shake_camera(4.0)
		Sfx.play("melee_hit")


func take_damage(amount: int) -> void:
	hp = max(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	rig.play(CharacterRig.State.HURT)
	Sfx.play("hero_hurt")
	if hp == 0:
		_die()


func _die() -> void:
	# Slice 0: just reset to full so the feel loop never stops.
	hp = max_hp
	health_changed.emit(hp, max_hp)
