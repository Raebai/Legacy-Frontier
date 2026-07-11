extends CharacterBody2D
## Slice 0 enemy: chases the hero, takes spell damage, damages on contact, dies.
## Slice 1: brutes (`uses_telegraphed_attack`) wind up a Telegraph danger circle
## and land a heavy strike on whoever is still standing in it — dodge the tell.

@export var max_hp: int = 40
@export var move_speed: float = 95.0
@export var touch_damage: int = 12
@export var tint: Color = Color(0.9, 0.35, 0.3, 1)
@export var uses_telegraphed_attack: bool = false
## 0=CHASER (fast/weak), 1=BRUTE (telegraphed heavy strike, uses the flag above),
## 2=CASTER (kites + telegraphs a bolt to dodge), 3=CHARGER (telegraphs a lane
## then rockets down it), 4=SUMMONER (kites + telegraphs, then calls in weak
## chaser minions — kill it before it swarms you). See Archetype enum below.
@export var archetype: int = 0

const KNOCKBACK_DECAY: float = 900.0  # px/s the knockback impulse bleeds off

# Death spectacle tuning ("bodies fly").
const DEATH_HIT_STOP: float = 0.11  # weighted: a kill is the heaviest impact
const DEATH_SHAKE: float = 8.0
const DEATH_BURST_AMOUNT: int = 42  # bigger than a spell hit (20)
const CORPSE_LAUNCH_SPEED: float = 240.0  # px/s the corpse silhouette flies
const CORPSE_FADE_TIME: float = 0.6  # corpses linger past a dash ghost (0.34)

# Telegraphed heavy attack tuning (brute archetype).
const ATTACK_RANGE: float = 78.0  # start winding up inside this distance
const ATTACK_WINDUP: float = 0.6  # seconds of tell before the strike lands
const ATTACK_RADIUS: float = 40.0  # danger-circle radius
const ATTACK_DAMAGE: int = 22
const ATTACK_COOLDOWN: float = 1.4  # seconds from strike until the next windup
const ATTACK_LUNGE: float = 180.0  # impulse toward the circle on a landed hit
const ATTACK_RECOVER_TIME: float = 0.3  # post-strike pause before re-chasing

# Ranged CASTER archetype: kites in a band, telegraphs, fires a dodgeable bolt.
const CASTER_RANGE_MIN: float = 180.0  # back away if the hero is closer than this
const CASTER_RANGE_MAX: float = 320.0  # close in if farther than this; fire in-band
const CASTER_WINDUP: float = 0.7
const CASTER_COOLDOWN: float = 1.9
const CASTER_TELE_RADIUS: float = 18.0  # small "charging" tell on the caster itself

# CHARGER archetype: telegraphs a lane at the hero, then rockets down it.
const CHARGE_RANGE: float = 260.0  # start the windup inside this distance
const CHARGE_WINDUP: float = 0.7
const CHARGE_SPEED: float = 520.0
const CHARGE_TIME: float = 0.35  # seconds the charge lasts
const CHARGE_DAMAGE: int = 24
const CHARGE_LEN: float = 300.0  # telegraph lane length
const CHARGE_WIDTH: float = 34.0
const CHARGE_HIT_RADIUS: float = 26.0
const CHARGE_COOLDOWN: float = 1.6

# SUMMONER archetype: kites like the caster, telegraphs on itself, then calls
# in SUMMON_COUNT weak chaser minions. The tell is the window to burst it down.
const SUMMONER_RANGE_MIN: float = 180.0  # same kite band as the caster
const SUMMONER_RANGE_MAX: float = 320.0
const SUMMON_WINDUP: float = 0.8
const SUMMON_COOLDOWN: float = 4.0
const SUMMON_COUNT: int = 2
const SUMMON_MINION_HP: int = 18
const SUMMON_TELE_RADIUS: float = 24.0  # "gathering magic" tell on the summoner
const SUMMON_SCATTER: float = 36.0      # max spawn offset around the summoner

enum AttackState { CHASE, WINDUP, RECOVER, CHARGING }
enum Archetype { CHASER, BRUTE, CASTER, CHARGER, SUMMONER }

var hp: int = 40
var _hero: Node2D = null
var _touch_cooldown: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _attack_state: AttackState = AttackState.CHASE
var _attack_cooldown: float = 0.0
var _recover_timer: float = 0.0
var _strike_center: Vector2 = Vector2.ZERO
var _telegraph: Telegraph = null
var _aim_dir: Vector2 = Vector2.RIGHT       # caster: shot direction, snapshot at windup
var _charge_dir: Vector2 = Vector2.RIGHT    # charger: locked lane direction
var _charge_timer: float = 0.0
var _charge_hit: bool = false

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
		AttackState.CHARGING:
			_process_charging(delta)
			return
	# Archetype-specific CHASE behaviour (chaser + brute fall through to default).
	if archetype == Archetype.CASTER:
		_caster_chase()
		return
	if archetype == Archetype.CHARGER:
		_charger_chase()
		return
	if archetype == Archetype.SUMMONER:
		_summoner_chase()
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
	match archetype:
		Archetype.CASTER:
			_fire_projectile()
		Archetype.CHARGER:
			_begin_charge()
		Archetype.SUMMONER:
			_spawn_minions()
		_:
			_resolve_strike(_strike_center)  # brute


# ------------------------------------------------------------- CASTER (ranged)
## Kite in the [MIN,MAX] band; fire when in-band and off cooldown.
func _caster_chase() -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dist: float = to_hero.length()
	var move_dir: Vector2 = Vector2.ZERO
	if dist < CASTER_RANGE_MIN:
		move_dir = -to_hero.normalized()          # too close — back away
	elif dist > CASTER_RANGE_MAX:
		move_dir = to_hero.normalized()           # too far — close in
	velocity = move_dir * move_speed + _knockback
	move_and_slide()
	rig.play(CharacterRig.State.RUN if move_dir != Vector2.ZERO else CharacterRig.State.IDLE)
	rig.set_facing(to_hero)
	if _attack_cooldown <= 0.0 and dist >= CASTER_RANGE_MIN and dist <= CASTER_RANGE_MAX:
		_start_caster_windup()


## Root + a small charging tell on the caster; the shot direction is snapshot
## NOW, so a moving hero can dodge by the time it fires.
func _start_caster_windup() -> void:
	_attack_state = AttackState.WINDUP
	_aim_dir = (_hero.global_position - global_position).normalized()
	if _aim_dir == Vector2.ZERO:
		_aim_dir = Vector2.RIGHT
	rig.flash()
	_telegraph = Telegraph.new()
	get_parent().add_child(_telegraph)
	_telegraph.global_position = global_position   # tell is ON the caster
	_telegraph.fired.connect(_on_telegraph_fired)
	_telegraph.start(CASTER_TELE_RADIUS, CASTER_WINDUP)


func _fire_projectile() -> void:
	var proj := EnemyProjectile.new()
	get_parent().add_child(proj)
	proj.global_position = global_position
	proj.launch(_aim_dir)
	_attack_state = AttackState.RECOVER
	_recover_timer = ATTACK_RECOVER_TIME
	_attack_cooldown = CASTER_COOLDOWN


# --------------------------------------------------------------- CHARGER (lane)
## Chase toward the hero; lock a lane and telegraph it once in range.
func _charger_chase() -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dist: float = to_hero.length()
	velocity = to_hero.normalized() * move_speed + _knockback
	move_and_slide()
	rig.play(CharacterRig.State.RUN)
	rig.set_facing(to_hero)
	if _attack_cooldown <= 0.0 and dist <= CHARGE_RANGE:
		_start_charger_windup()


func _start_charger_windup() -> void:
	_attack_state = AttackState.WINDUP
	_charge_dir = (_hero.global_position - global_position).normalized()
	if _charge_dir == Vector2.ZERO:
		_charge_dir = Vector2.RIGHT
	rig.flash()
	_telegraph = Telegraph.new()
	get_parent().add_child(_telegraph)
	_telegraph.global_position = global_position
	_telegraph.fired.connect(_on_telegraph_fired)
	_telegraph.start_line(CHARGE_LEN, CHARGE_WIDTH, _charge_dir.angle(), CHARGE_WINDUP)


func _begin_charge() -> void:
	_attack_state = AttackState.CHARGING
	_charge_timer = CHARGE_TIME
	_charge_hit = false


## Rocket down the locked lane; hit the hero once; end on timeout or a wall.
func _process_charging(delta: float) -> void:
	velocity = _charge_dir * CHARGE_SPEED
	move_and_slide()
	_charge_timer -= delta
	if not _charge_hit and is_instance_valid(_hero) \
			and _hero.has_method("take_damage") \
			and global_position.distance_to(_hero.global_position) <= CHARGE_HIT_RADIUS:
		_hero.take_damage(CHARGE_DAMAGE)
		_charge_hit = true
		Juice.shake_camera(5.0)
		Sfx.play("melee_hit")
	if _charge_timer <= 0.0 or get_slide_collision_count() > 0:
		_attack_state = AttackState.RECOVER
		_recover_timer = ATTACK_RECOVER_TIME
		_attack_cooldown = CHARGE_COOLDOWN


# ------------------------------------------------------------ SUMMONER (minions)
## Kite in the [MIN,MAX] band like the caster; summon when in-band and off
## cooldown. The summoner itself never melees — its minions apply the pressure.
func _summoner_chase() -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dist: float = to_hero.length()
	var move_dir: Vector2 = Vector2.ZERO
	if dist < SUMMONER_RANGE_MIN:
		move_dir = -to_hero.normalized()          # too close — back away
	elif dist > SUMMONER_RANGE_MAX:
		move_dir = to_hero.normalized()           # too far — close in
	velocity = move_dir * move_speed + _knockback
	move_and_slide()
	rig.play(CharacterRig.State.RUN if move_dir != Vector2.ZERO else CharacterRig.State.IDLE)
	rig.set_facing(to_hero)
	if _attack_cooldown <= 0.0 and dist >= SUMMONER_RANGE_MIN and dist <= SUMMONER_RANGE_MAX:
		_start_summon_windup()


## Root + a "gathering magic" tell on the summoner itself. The windup is the
## fair-play window: burst the summoner (or knock it around) before it fires
## and no minions arrive. _abort_attack() cancels this cleanly like any windup.
func _start_summon_windup() -> void:
	_attack_state = AttackState.WINDUP
	rig.flash()
	_telegraph = Telegraph.new()
	get_parent().add_child(_telegraph)
	_telegraph.global_position = global_position   # tell is ON the summoner
	_telegraph.fired.connect(_on_telegraph_fired)
	_telegraph.start(SUMMON_TELE_RADIUS, SUMMON_WINDUP)


## The tell paid off: pop SUMMON_COUNT weak chaser minions in around the
## summoner as arena siblings (their own _ready joins group "enemy" and finds
## the hero), then recover and start the long summon cooldown.
## Scene load()ed at runtime, not preload: Enemy.tscn references this very
## script, so a preload here would be a cyclic resource dependency.
func _spawn_minions() -> void:
	var enemy_scene: PackedScene = load("res://scenes/combat/Enemy.tscn")
	for i in SUMMON_COUNT:
		var minion: CharacterBody2D = enemy_scene.instantiate()
		minion.archetype = Archetype.CHASER
		minion.max_hp = SUMMON_MINION_HP
		minion.tint = Color(tint.r, tint.g, tint.b, 1.0).lightened(0.35)  # reads as spawn
		get_parent().add_child(minion)
		var offset := Vector2.from_angle(randf() * TAU) * randf_range(SUMMON_SCATTER * 0.4, SUMMON_SCATTER)
		minion.global_position = global_position + offset
	_attack_state = AttackState.RECOVER
	_recover_timer = ATTACK_RECOVER_TIME
	_attack_cooldown = SUMMON_COOLDOWN


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
	_grant_kill_power()
	_notify_run_kill()
	_spawn_death_burst()
	_spawn_corpse()
	Sfx.play("enemy_death")
	Juice.shake_camera(DEATH_SHAKE)
	Juice.hit_stop(DEATH_HIT_STOP)
	queue_free()


## Feed the rank ladder: every kill grants power. Guarded lookup so headless
## test contexts without the Rank autoload never crash.
func _grant_kill_power() -> void:
	var r: Node = get_node_or_null("/root/Rank")
	if r != null and r.has_method("add_power"):
		r.call("add_power", 3)  # matches Rank.KILL_POWER


## Count the kill toward the active run's outcome record (guarded — no-op in
## the standalone sandbox where no run is active).
func _notify_run_kill() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.notify_kill()


## Tint-colored particle pop, noticeably bigger than a spell impact.
func _spawn_death_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(tint.r, tint.g, tint.b, 1.0).lightened(0.3),
		Color(tint.r, tint.g, tint.b, 0.0),
		DEATH_BURST_AMOUNT, 0.5, 110.0, 240.0, 1.5, 4.0, 40.0, 90.0
	)


## Launched fading silhouette along the killing blow's knockback direction
## (fallback: away from the hero) — the "body flies" read. Wind streaks
## follow the launch so the corpse reads as flung, not teleported.
func _spawn_corpse() -> void:
	var launch_dir: Vector2 = _knockback.normalized()
	if launch_dir == Vector2.ZERO and is_instance_valid(_hero):
		launch_dir = (global_position - _hero.global_position).normalized()
	if launch_dir == Vector2.ZERO:
		launch_dir = Vector2.RIGHT
	rig.spawn_ghost(
		get_parent(),
		Color(tint.r, tint.g, tint.b, 0.85),
		launch_dir,
		launch_dir * CORPSE_LAUNCH_SPEED,
		CORPSE_FADE_TIME,
	)
