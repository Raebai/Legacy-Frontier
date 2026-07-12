extends CharacterBody2D
## Slice 0 enemy: chases the hero, takes spell damage, damages on contact, dies.
## Slice 1: brutes (`uses_telegraphed_attack`) wind up a Telegraph danger circle
## and land a heavy strike on whoever is still standing in it — dodge the tell.
## Now a seven-archetype roster (see Archetype below) with signature tints +
## speeds (_apply_archetype_defaults) — every attack is telegraphed, every
## silhouette color-coded.

@export var max_hp: int = 40
@export var move_speed: float = 95.0
@export var touch_damage: int = 12
@export var tint: Color = Color(0.9, 0.35, 0.3, 1)
@export var uses_telegraphed_attack: bool = false
## 0=CHASER (fast/weak), 1=BRUTE (telegraphed heavy strike, uses the flag above),
## 2=CASTER (kites + telegraphs a bolt to dodge), 3=CHARGER (telegraphs a lane
## then rockets down it), 4=SUMMONER (kites + telegraphs, then calls in weak
## chaser minions — kill it before it swarms you), 5=ASSASSIN (jittery
## hit-and-run: quick telegraphed lunge, then retreats out of reach),
## 6=BOMBER (waddles in and self-detonates on a big slow tell — area denial;
## kill it at range or dodge the circle). See Archetype enum below.
@export var archetype: int = 0

const KNOCKBACK_DECAY: float = 900.0  # px/s the knockback impulse bleeds off

# Side-on platformer physics (mirrors Hero.gd's GRAVITY/MAX_FALL model):
# enemies fall, stand on platforms, and chase-jump toward a hero above them.
const GRAVITY: float = 1500.0
const MAX_FALL: float = 950.0
const JUMP_VELOCITY: float = -520.0
const JUMP_TRIGGER_HEIGHT: float = 60.0     # hero at least this far ABOVE -> chase-jump
const JUMP_HORIZONTAL_RANGE: float = 260.0  # ...and roughly this near on x
const JUMP_COOLDOWN: float = 0.6

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

# ASSASSIN archetype: fast, fragile hit-and-run. Weaves on approach (jittery
# direction feints), snapshots the hero under a QUICK small tell, lunges the
# lane, then RETREATS out of reach — hard to pin, easy to kill if you do.
const ASSASSIN_STRIKE_RANGE: float = 120.0  # start the windup inside this distance
const ASSASSIN_WINDUP: float = 0.35         # the fastest tell in the roster
const ASSASSIN_TELE_RADIUS: float = 26.0    # small strike-point circle
const ASSASSIN_LUNGE_SPEED: float = 620.0
const ASSASSIN_LUNGE_TIME: float = 0.22
const ASSASSIN_DAMAGE: int = 14
const ASSASSIN_HIT_RADIUS: float = 24.0
const ASSASSIN_COOLDOWN: float = 1.1
const ASSASSIN_RETREAT_TIME: float = 0.8    # disengage window after each strike
const ASSASSIN_JITTER_INTERVAL: float = 0.28  # re-roll the feint this often
const ASSASSIN_JITTER_CHANCE: float = 0.4     # odds a roll reverses the approach

# BOMBER archetype: walking bomb. Waddles in, roots, and telegraphs the BIGGEST,
# SLOWEST tell in the roster centered on the marked spot — then detonates,
# killing itself. Dodge the circle or burst it down before the tell fills.
const BOMB_TRIGGER_RANGE: float = 72.0  # start the fuse inside this distance
const BOMB_WINDUP: float = 0.9          # long fuse — generous dodge window
const BOMB_RADIUS: float = 78.0         # big danger circle
const BOMB_DAMAGE: int = 30
const BOMB_KNOCKBACK: float = 320.0     # shove on a caught hero (if supported)

enum AttackState { CHASE, WINDUP, RECOVER, CHARGING }
enum Archetype { CHASER, BRUTE, CASTER, CHARGER, SUMMONER, ASSASSIN, BOMBER }

# Signature stats + tint per archetype so a glance tells them apart even when a
# spawner sets ONLY `archetype` (VersusArena bots, sandbox tools). Values mirror
# Encounter.gd's stat table for the first five so both spawn paths agree.
# Applied field-by-field in _apply_archetype_defaults ONLY where the export is
# still at its generic script default — explicit spawner overrides always win.
const ARCHETYPE_DEFAULTS: Dictionary = {
	Archetype.CHASER: {"hp": 24, "speed": 140.0, "touch": 8, "tint": Color(0.95, 0.5, 0.25, 1)},   # orange
	Archetype.BRUTE: {"hp": 70, "speed": 62.0, "touch": 18, "tint": Color(0.7, 0.25, 0.45, 1)},    # magenta
	Archetype.CASTER: {"hp": 30, "speed": 80.0, "touch": 6, "tint": Color(0.55, 0.45, 0.95, 1)},   # indigo
	Archetype.CHARGER: {"hp": 45, "speed": 55.0, "touch": 10, "tint": Color(0.9, 0.6, 0.2, 1)},    # amber
	Archetype.SUMMONER: {"hp": 36, "speed": 72.0, "touch": 6, "tint": Color(0.35, 0.8, 0.55, 1)},  # jade
	Archetype.ASSASSIN: {"hp": 20, "speed": 175.0, "touch": 8, "tint": Color(0.82, 0.86, 0.92, 1)},  # silver
	Archetype.BOMBER: {"hp": 55, "speed": 70.0, "touch": 6, "tint": Color(0.34, 0.35, 0.4, 1)},    # charcoal
}

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
var _jump_cd: float = 0.0                   # chase-jump cooldown, ticks down each frame
var _retreat_timer: float = 0.0             # assassin: post-strike disengage window
var _jitter_timer: float = 0.0              # assassin: time until the next feint roll
var _jitter_sign: float = 1.0               # assassin: current approach feint (+1/-1)

@onready var rig: CharacterRig = $Rig


## Applied by melee / spell / blast. A decaying impulse added ON TOP of the
## chase velocity so the hit actually displaces the enemy instead of being
## stomped by the next physics tick's `velocity = dir * move_speed`.
func apply_knockback(impulse: Vector2) -> void:
	_knockback = impulse
	# Side-on: the VERTICAL part lands once as a real impulse into velocity.y so
	# a hard hit pops the enemy off the ground (gravity owns y from here). Adding
	# _knockback.y every frame instead would integrate the decaying impulse as an
	# acceleration and launch bodies at absurd speeds. The horizontal part keeps
	# the old decaying-channel treatment (`velocity.x = chase_x + _knockback.x`).
	velocity.y += impulse.y


## A hard-knocked enemy that slams into a wall craters the floor + kicks up dust
## ("damage the floor wherever they're sent"). Spends the remaining knockback so
## it fires once per slam, not every frame it stays pinned.
func _check_wall_slam() -> void:
	if _knockback.length() < 250.0 or get_slide_collision_count() <= 0:
		return
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(0.72, 0.7, 0.68, 0.7), Color(0.72, 0.7, 0.68, 0.0),
		12, 0.32, 40.0, 130.0
	)
	ScorchDecal.spawn(get_parent(), global_position, 15.0, "crack", Color(0.2, 0.2, 0.22, 0.5))
	Juice.shake_camera(3.0)
	_knockback = Vector2.ZERO  # spent on the wall


## Side-on vertical core: rest on the floor, else integrate gravity toward
## MAX_FALL. A rising velocity (upward knockback pop from apply_knockback, or a
## chase-jump) beats the floor-zeroing so the body actually leaves the ground.
func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y >= 0.0:
		velocity.y = 0.0
	else:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)


## Pure "should we chase-jump?" decision, floor check deliberately EXCLUDED so
## headless tests can drive it without stepped physics: cooldown elapsed, and
## the hero is meaningfully above us while roughly near on x.
func _wants_chase_jump() -> bool:
	if _jump_cd > 0.0 or not is_instance_valid(_hero):
		return false
	return _hero.global_position.y < global_position.y - JUMP_TRIGGER_HEIGHT \
			and absf(_hero.global_position.x - global_position.x) < JUMP_HORIZONTAL_RANGE


## Chase-jump: hop toward a hero that's above us, or over an obstacle we're
## walking into. Called between _apply_gravity and move_and_slide, so the
## is_on_floor()/is_on_wall() reads reflect the previous frame's slide state.
func _try_chase_jump() -> void:
	if not is_on_floor() or _jump_cd > 0.0:
		return
	# is_on_wall(), not get_slide_collision_count(): standing on the floor IS a
	# slide collision every frame, which would read as permanently "blocked".
	var blocked: bool = is_on_wall() and absf(velocity.x) > 10.0
	if _wants_chase_jump() or blocked:
		velocity.y = JUMP_VELOCITY
		_jump_cd = JUMP_COOLDOWN


## Per-archetype signature stats/looks, applied ONLY to fields still at their
## generic script defaults so explicit spawner values (Encounter's stat table,
## VersusArena's BOT_HP) always win. A bare Enemy with just `archetype` set now
## reads distinct at a glance instead of shipping five identical red rigs.
func _apply_archetype_defaults() -> void:
	var d: Dictionary = ARCHETYPE_DEFAULTS.get(archetype, ARCHETYPE_DEFAULTS[Archetype.CHASER])
	if max_hp == 40:
		max_hp = int(d["hp"])
	if move_speed == 95.0:
		move_speed = float(d["speed"])
	if touch_damage == 12:
		touch_damage = int(d["touch"])
	if tint == Color(0.9, 0.35, 0.3, 1):
		tint = d["tint"] as Color
	if archetype == Archetype.BRUTE:
		uses_telegraphed_attack = true  # a brute that never swings isn't a brute


func _ready() -> void:
	add_to_group("enemy")
	_apply_archetype_defaults()
	hp = max_hp
	rig.set_tint(tint)
	var heroes: Array = get_tree().get_nodes_in_group("hero")
	if not heroes.is_empty():
		_hero = heroes[0]
	# Floating HP bar over the head (enemies have no MP).
	var bars := CharacterBars.new()
	add_child(bars)
	bars.configure(self, false, -24.0)


func _physics_process(delta: float) -> void:
	_touch_cooldown = max(_touch_cooldown - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_jump_cd = maxf(_jump_cd - delta, 0.0)
	if not is_instance_valid(_hero):
		# No target, but still honour an in-flight knockback so a killing-blow
		# pop reads even if the hero just vanished.
		if _attack_state != AttackState.CHASE:
			_abort_attack()  # hero vanished mid-windup/recover — bail cleanly
		velocity.x = _knockback.x
		_apply_gravity(delta)
		move_and_slide()
		rig.play(CharacterRig.State.IDLE)
		return
	match _attack_state:
		AttackState.WINDUP:
			_process_windup(delta)
			return
		AttackState.RECOVER:
			_process_recover(delta)
			return
		AttackState.CHARGING:
			_process_charging(delta)
			return
	# Archetype-specific CHASE behaviour (chaser + brute fall through to default).
	if archetype == Archetype.CASTER:
		_caster_chase(delta)
		return
	if archetype == Archetype.CHARGER:
		_charger_chase(delta)
		return
	if archetype == Archetype.SUMMONER:
		_summoner_chase(delta)
		return
	if archetype == Archetype.ASSASSIN:
		_assassin_chase(delta)
		return
	if archetype == Archetype.BOMBER:
		_bomber_chase(delta)
		return
	# Side-on chase: close the HORIZONTAL gap; gravity owns y; jump to reach a
	# hero above us or hop an obstacle in the way.
	var chase_x: float = signf(_hero.global_position.x - global_position.x) * move_speed
	velocity.x = chase_x + _knockback.x
	_apply_gravity(delta)
	_try_chase_jump()
	move_and_slide()
	_check_wall_slam()  # crater + dust if a hard hit just slammed us into a wall
	rig.play(CharacterRig.State.RUN)
	rig.set_facing(Vector2(signf(chase_x), 0.0))
	if uses_telegraphed_attack and _attack_cooldown <= 0.0 \
			and global_position.distance_to(_hero.global_position) <= ATTACK_RANGE:
		_start_windup()
		return
	if global_position.distance_to(_hero.global_position) < 22.0 and _touch_cooldown <= 0.0:
		if _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = 0.8


## WINDUP: rooted in place (knockback still lands), visibly holding the tell.
## Rooted means no CHASE drive — gravity still applies so the tell can't float.
func _process_windup(delta: float) -> void:
	velocity.x = _knockback.x
	_apply_gravity(delta)
	move_and_slide()
	rig.play(CharacterRig.State.IDLE)
	rig.set_facing(_hero.global_position - global_position)


## RECOVER: brief post-strike pause, then back to the chase.
func _process_recover(delta: float) -> void:
	velocity.x = _knockback.x
	_apply_gravity(delta)
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
		Archetype.ASSASSIN:
			_begin_lunge()
		Archetype.BOMBER:
			_detonate()
		_:
			_resolve_strike(_strike_center)  # brute


# ------------------------------------------------------------- CASTER (ranged)
## Kite in the HORIZONTAL [MIN,MAX] band; fire when in-band and off cooldown.
## Side-on: the band is measured on x only — gravity owns y. The bolt itself
## still fires along the full 2D _aim_dir, so it can angle up/down at the hero.
func _caster_chase(delta: float) -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dist_x: float = absf(to_hero.x)
	var move_x: float = 0.0
	if dist_x < CASTER_RANGE_MIN:
		move_x = -signf(to_hero.x)                # too close — back away
	elif dist_x > CASTER_RANGE_MAX:
		move_x = signf(to_hero.x)                 # too far — close in
	velocity.x = move_x * move_speed + _knockback.x
	_apply_gravity(delta)
	move_and_slide()
	rig.play(CharacterRig.State.RUN if move_x != 0.0 else CharacterRig.State.IDLE)
	rig.set_facing(to_hero)
	if _attack_cooldown <= 0.0 and dist_x >= CASTER_RANGE_MIN and dist_x <= CASTER_RANGE_MAX:
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
## Chase toward the hero on x; lock a lane and telegraph it once in range.
## The approach also chase-jumps so it can reach a hero on a platform above.
func _charger_chase(delta: float) -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dist: float = to_hero.length()
	velocity.x = signf(to_hero.x) * move_speed + _knockback.x
	_apply_gravity(delta)
	_try_chase_jump()
	move_and_slide()
	rig.play(CharacterRig.State.RUN)
	rig.set_facing(to_hero)
	if _attack_cooldown <= 0.0 and dist <= CHARGE_RANGE:
		_start_charger_windup()


func _start_charger_windup() -> void:
	_attack_state = AttackState.WINDUP
	# Side-on: the charge is a HORIZONTAL rocket — lock a flat lane toward the
	# hero's side of the screen, never a diagonal.
	_charge_dir = Vector2(signf(_hero.global_position.x - global_position.x), 0.0)
	if _charge_dir.x == 0.0:
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
## Gravity still applies, so a charge off a ledge arcs down instead of flying.
## Shared by CHARGER (long heavy rocket -> RECOVER) and ASSASSIN (short quick
## lunge -> straight back to CHASE with a retreat window: no standing around).
func _process_charging(delta: float) -> void:
	var is_assassin: bool = archetype == Archetype.ASSASSIN
	var lunge_speed: float = ASSASSIN_LUNGE_SPEED if is_assassin else CHARGE_SPEED
	var lunge_damage: int = ASSASSIN_DAMAGE if is_assassin else CHARGE_DAMAGE
	var hit_radius: float = ASSASSIN_HIT_RADIUS if is_assassin else CHARGE_HIT_RADIUS
	velocity.x = _charge_dir.x * lunge_speed
	_apply_gravity(delta)
	move_and_slide()
	_charge_timer -= delta
	if not _charge_hit and is_instance_valid(_hero) \
			and _hero.has_method("take_damage") \
			and global_position.distance_to(_hero.global_position) <= hit_radius:
		_hero.take_damage(lunge_damage)
		_charge_hit = true
		Juice.shake_camera(5.0)
		Sfx.play("melee_hit")
	# is_on_wall(), not get_slide_collision_count(): a grounded charge collides
	# with the FLOOR every frame, which would end the rocket on frame one.
	if _charge_timer <= 0.0 or is_on_wall():
		if is_assassin:
			_attack_state = AttackState.CHASE
			_retreat_timer = ASSASSIN_RETREAT_TIME
			_attack_cooldown = ASSASSIN_COOLDOWN
		else:
			_attack_state = AttackState.RECOVER
			_recover_timer = ATTACK_RECOVER_TIME
			_attack_cooldown = CHARGE_COOLDOWN


# ------------------------------------------------------------ SUMMONER (minions)
## Kite in the HORIZONTAL [MIN,MAX] band like the caster; summon when in-band
## and off cooldown. The summoner itself never melees — its minions apply the
## pressure. Side-on: band on x only, gravity owns y (same as _caster_chase).
func _summoner_chase(delta: float) -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dist_x: float = absf(to_hero.x)
	var move_x: float = 0.0
	if dist_x < SUMMONER_RANGE_MIN:
		move_x = -signf(to_hero.x)                # too close — back away
	elif dist_x > SUMMONER_RANGE_MAX:
		move_x = signf(to_hero.x)                 # too far — close in
	velocity.x = move_x * move_speed + _knockback.x
	_apply_gravity(delta)
	move_and_slide()
	rig.play(CharacterRig.State.RUN if move_x != 0.0 else CharacterRig.State.IDLE)
	rig.set_facing(to_hero)
	if _attack_cooldown <= 0.0 and dist_x >= SUMMONER_RANGE_MIN and dist_x <= SUMMONER_RANGE_MAX:
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


# ---------------------------------------------------------- ASSASSIN (hit-and-run)
## Approach with feints (brief random direction reversals so it's hard to pin),
## strike with a QUICK small tell + lunge, then retreat out of reach. The
## retreat window overrides everything: after a strike it runs AWAY first.
func _assassin_chase(delta: float) -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dir_x: float = signf(to_hero.x)
	if dir_x == 0.0:
		dir_x = 1.0
	var move_x: float = dir_x
	if _retreat_timer > 0.0:
		_retreat_timer -= delta
		move_x = -dir_x                           # disengage: sprint away
	else:
		_jitter_timer -= delta
		if _jitter_timer <= 0.0:
			_jitter_timer = ASSASSIN_JITTER_INTERVAL
			_jitter_sign = -1.0 if randf() < ASSASSIN_JITTER_CHANCE else 1.0
		if absf(to_hero.x) < ASSASSIN_STRIKE_RANGE * 2.0:
			move_x = dir_x * _jitter_sign         # feint: jittery, unpredictable
	velocity.x = move_x * move_speed + _knockback.x
	_apply_gravity(delta)
	_try_chase_jump()
	move_and_slide()
	_check_wall_slam()
	rig.play(CharacterRig.State.RUN)
	rig.set_facing(to_hero)
	if _retreat_timer <= 0.0 and _attack_cooldown <= 0.0 \
			and global_position.distance_to(_hero.global_position) <= ASSASSIN_STRIKE_RANGE:
		_start_assassin_windup()


## Snapshot the hero under a small FAST tell (the quickest windup in the
## roster) and lock a flat lunge lane toward it — same side-on grammar as the
## charger, just faster, shorter, and weaker.
func _start_assassin_windup() -> void:
	_attack_state = AttackState.WINDUP
	_strike_center = _hero.global_position
	_charge_dir = Vector2(signf(_strike_center.x - global_position.x), 0.0)
	if _charge_dir.x == 0.0:
		_charge_dir = Vector2.RIGHT
	rig.flash()
	_telegraph = Telegraph.new()
	get_parent().add_child(_telegraph)
	_telegraph.global_position = _strike_center
	_telegraph.fired.connect(_on_telegraph_fired)
	_telegraph.start(ASSASSIN_TELE_RADIUS, ASSASSIN_WINDUP)


## The assassin's lunge rides the CHARGING state; _process_charging branches
## on archetype for speed/damage/exit (retreat instead of RECOVER).
func _begin_lunge() -> void:
	_attack_state = AttackState.CHARGING
	_charge_timer = ASSASSIN_LUNGE_TIME
	_charge_hit = false


# ------------------------------------------------------------- BOMBER (walking bomb)
## Standard side-on waddle toward the hero; inside trigger range it roots and
## lights the fuse. Slower and fatter than a chaser — the threat is the blast,
## not the chase, so kill it at range or hold the dodge for the fuse.
func _bomber_chase(delta: float) -> void:
	var chase_x: float = signf(_hero.global_position.x - global_position.x) * move_speed
	velocity.x = chase_x + _knockback.x
	_apply_gravity(delta)
	_try_chase_jump()
	move_and_slide()
	_check_wall_slam()
	rig.play(CharacterRig.State.RUN)
	rig.set_facing(Vector2(signf(chase_x), 0.0))
	if _attack_cooldown <= 0.0 \
			and global_position.distance_to(_hero.global_position) <= BOMB_TRIGGER_RANGE:
		_start_bomb_windup()
		return
	if global_position.distance_to(_hero.global_position) < 22.0 and _touch_cooldown <= 0.0:
		if _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = 0.8


## Root and mark the blast zone where the bomber stands: the BIGGEST, SLOWEST
## tell in the roster. Interrupting is the counter — _abort_attack (via death)
## defuses it cleanly like any other windup, and a knocked-around bomber still
## detonates on the MARKED circle, not wherever it got shoved (dodge-the-tell
## grammar: the telegraph is always the truth).
func _start_bomb_windup() -> void:
	_attack_state = AttackState.WINDUP
	_strike_center = global_position
	rig.flash()
	_telegraph = Telegraph.new()
	get_parent().add_child(_telegraph)
	_telegraph.global_position = _strike_center
	_telegraph.fired.connect(_on_telegraph_fired)
	_telegraph.start(BOMB_RADIUS, BOMB_WINDUP)


## The fuse ran out: damage + shove a hero still inside the marked circle,
## scorch the ground, and die in the blast (the death spectacle in _die stacks
## on top — bomb VFX first, then the corpse launch). Suicide trade by design.
func _detonate() -> void:
	if is_instance_valid(_hero) and _hero.has_method("take_damage") \
			and _hero.global_position.distance_to(_strike_center) <= BOMB_RADIUS:
		_hero.take_damage(BOMB_DAMAGE)
		if _hero.has_method("apply_knockback"):
			var away: Vector2 = (_hero.global_position - _strike_center).normalized()
			if away == Vector2.ZERO:
				away = Vector2.UP
			_hero.apply_knockback(away * BOMB_KNOCKBACK)
	CombatVfx.spawn_burst(
		get_parent(), _strike_center,
		Color(1.0, 0.75, 0.35, 0.95), Color(0.9, 0.3, 0.15, 0.0),
		36, 0.45, 120.0, 260.0, 1.5, 4.0, 40.0, 90.0
	)
	ScorchDecal.spawn(get_parent(), _strike_center, BOMB_RADIUS * 0.55, "scorch", Color(0.15, 0.13, 0.12, 0.55))
	Juice.shake_camera(7.0)
	Sfx.play("blast")
	_die()


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
