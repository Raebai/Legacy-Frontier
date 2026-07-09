extends CharacterBody2D
## Slice 0 enemy: chases the hero, takes spell damage, damages on contact, dies.
## Slice 1: brutes (`uses_telegraphed_attack`) wind up a Telegraph danger circle
## and land a heavy strike on whoever is still standing in it — dodge the tell.

@export var max_hp: int = 40
@export var move_speed: float = 95.0
@export var touch_damage: int = 12
@export var tint: Color = Color(0.9, 0.35, 0.3, 1)
@export var uses_telegraphed_attack: bool = false

const KNOCKBACK_DECAY: float = 900.0  # px/s the knockback impulse bleeds off

# Telegraphed heavy attack tuning (brute archetype).
const ATTACK_RANGE: float = 78.0  # start winding up inside this distance
const ATTACK_WINDUP: float = 0.6  # seconds of tell before the strike lands
const ATTACK_RADIUS: float = 40.0  # danger-circle radius
const ATTACK_DAMAGE: int = 22
const ATTACK_COOLDOWN: float = 1.4  # seconds from strike until the next windup
const ATTACK_LUNGE: float = 180.0  # impulse toward the circle on a landed hit
const ATTACK_RECOVER_TIME: float = 0.3  # post-strike pause before re-chasing

enum AttackState { CHASE, WINDUP, RECOVER }

var hp: int = 40
var _hero: Node2D = null
var _touch_cooldown: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _attack_state: AttackState = AttackState.CHASE
var _attack_cooldown: float = 0.0
var _recover_timer: float = 0.0
var _strike_center: Vector2 = Vector2.ZERO
var _telegraph: Telegraph = null

@onready var rig: CharacterRig = $Rig


## Applied by melee / spell / blast. A decaying impulse added ON TOP of the
## chase velocity so the hit actually displaces the enemy instead of being
## stomped by the next physics tick's `velocity = dir * move_speed`.
func apply_knockback(impulse: Vector2) -> void:
	_knockback = impulse


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	rig.set_tint(tint)
	var heroes: Array = get_tree().get_nodes_in_group("hero")
	if not heroes.is_empty():
		_hero = heroes[0]


func _physics_process(delta: float) -> void:
	_touch_cooldown = max(_touch_cooldown - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if not is_instance_valid(_hero):
		# No target, but still honour an in-flight knockback so a killing-blow
		# pop reads even if the hero just vanished.
		if _attack_state != AttackState.CHASE:
			_abort_attack()  # hero vanished mid-windup/recover — bail cleanly
		velocity = _knockback
		move_and_slide()
		rig.play(CharacterRig.State.IDLE)
		return
	match _attack_state:
		AttackState.WINDUP:
			_process_windup()
			return
		AttackState.RECOVER:
			_process_recover(delta)
			return
	var dir: Vector2 = (_hero.global_position - global_position).normalized()
	velocity = dir * move_speed + _knockback
	move_and_slide()
	rig.play(CharacterRig.State.RUN)
	rig.set_facing(dir)
	if uses_telegraphed_attack and _attack_cooldown <= 0.0 \
			and global_position.distance_to(_hero.global_position) <= ATTACK_RANGE:
		_start_windup()
		return
	if global_position.distance_to(_hero.global_position) < 22.0 and _touch_cooldown <= 0.0:
		if _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = 0.8


## WINDUP: rooted in place (knockback still lands), visibly holding the tell.
func _process_windup() -> void:
	velocity = _knockback
	move_and_slide()
	rig.play(CharacterRig.State.IDLE)
	rig.set_facing(_hero.global_position - global_position)


## RECOVER: brief post-strike pause, then back to the chase.
func _process_recover(delta: float) -> void:
	velocity = _knockback
	move_and_slide()
	rig.play(CharacterRig.State.IDLE)
	_recover_timer -= delta
	if _recover_timer <= 0.0:
		_attack_state = AttackState.CHASE


## Snapshot the hero's position, spawn the danger circle there, hold still.
## A stationary player gets hit; a dashing player escapes the circle.
func _start_windup() -> void:
	_attack_state = AttackState.WINDUP
	_strike_center = _hero.global_position
	rig.flash()  # readable tell: the brute blinks as it roots itself
	_telegraph = Telegraph.new()
	# Sibling in the arena, not a child: the circle marks a spot in the world
	# and must not ride along if the brute gets knocked around mid-windup.
	get_parent().add_child(_telegraph)
	_telegraph.global_position = _strike_center
	_telegraph.fired.connect(_on_telegraph_fired)
	_telegraph.start(ATTACK_RADIUS, ATTACK_WINDUP)


func _on_telegraph_fired() -> void:
	_telegraph = null  # the Telegraph fades and frees itself after firing
	_resolve_strike(_strike_center)


## Strike resolution, split out so headless tests can drive it directly:
## hero still inside the circle -> heavy damage + lunge + juice; else a miss.
## Either way the brute enters RECOVER and the cooldown runs from the strike.
func _resolve_strike(center: Vector2) -> void:
	if is_instance_valid(_hero) and _hero.has_method("take_damage") \
			and _hero.global_position.distance_to(center) <= ATTACK_RADIUS:
		_hero.take_damage(ATTACK_DAMAGE)
		# Brief self-impulse toward the circle so the hit reads as a lunge;
		# rides the knockback channel so it decays like any other shove.
		_knockback += (center - global_position).normalized() * ATTACK_LUNGE
		Juice.shake_camera(5.0)
		Sfx.play("melee_hit")
	_attack_state = AttackState.RECOVER
	_recover_timer = ATTACK_RECOVER_TIME
	_attack_cooldown = ATTACK_COOLDOWN


## Cancel an in-progress attack (hero freed mid-windup, or dying) without
## leaving a live danger circle or a dangling signal behind.
func _abort_attack() -> void:
	_attack_state = AttackState.CHASE
	if is_instance_valid(_telegraph):
		if _telegraph.fired.is_connected(_on_telegraph_fired):
			_telegraph.fired.disconnect(_on_telegraph_fired)
		_telegraph.queue_free()
	_telegraph = null


func take_damage(amount: int) -> void:
	hp = max(hp - amount, 0)
	_flash()
	if hp == 0:
		_die()


func _flash() -> void:
	rig.flash()


func _die() -> void:
	_abort_attack()  # never leave an orphaned danger circle behind a corpse
	Sfx.play("enemy_death")
	Juice.shake_camera(8.0)
	Juice.hit_stop()
	queue_free()
