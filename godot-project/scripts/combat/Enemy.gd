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
## Practice-dummy mode (Task 1 sandbox): skips chase/retarget + all attack
## windups so the enemy just stands and takes hits — a stationary punching bag.
## Still joins group "enemy" via the normal _ready path, so every existing
## hero attack/spell (which targets that group) hits it with zero spell-file
## edits. _die() respawns a passive enemy in place instead of freeing it.
@export var passive: bool = false
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

# Passive practice-dummy tuning (Task 1 sandbox): a shorter, quieter "knocked
# out" beat than a real kill, then it pops back up at its home spot.
const PASSIVE_RESPAWN_DELAY: float = 1.0

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
const SUMMON_MAX_ALIVE: int = 4  # hard cap on concurrent minions — no infinite swarm
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

# MAGE archetype: kites like the caster but instead of a bolt it telegraphs a
# ground AoE at the marked spot (a parameterized BlastSpell aimed at the hero).
# The tell is a big danger ZONE — dodge OUT of the circle. Elemental (rolled).
const MAGE_RANGE_MIN: float = 210.0   # kite band, a touch longer than the caster
const MAGE_RANGE_MAX: float = 380.0
const MAGE_WINDUP: float = 0.85       # generous — it's a big AoE
const MAGE_COOLDOWN: float = 2.6
const MAGE_AOE_RADIUS: float = 70.0
const MAGE_AOE_DAMAGE: int = 20
const MAGE_AOE_KNOCKBACK: float = 260.0
const MAGE_BLAST_SCENE: String = "res://scenes/combat/BlastSpell.tscn"

# LEAP system: a fixed chase-hop tops out around JUMP_VELOCITY^2/(2*GRAVITY)
# (~90px); arena ledges sit ~170px up, out of hop reach. A leap solves a
# ballistic launch that CLEARS the target height, so enemies actually pursue a
# hero onto a platform instead of milling below it.
const LEAP_MIN_HEIGHT: float = 105.0   # above the hop's reach -> needs a real leap
const LEAP_MAX_HEIGHT: float = 340.0   # don't attempt absurd heights
const LEAP_HORIZONTAL_RANGE: float = 400.0  # ...and roughly under/near the ledge on x
const LEAP_CLEARANCE: float = 46.0     # arc apex clears the target height by this
const LEAP_COOLDOWN: float = 1.5
const LEAP_MAX_SPEED: float = 900.0    # cap the horizontal launch (no rail-gun leaps)
const LEAP_MAX_AIR_TIME: float = 1.6   # safety timeout out of the LEAPING state

enum AttackState { CHASE, WINDUP, RECOVER, CHARGING, LEAPING }
enum Archetype { CHASER, BRUTE, CASTER, CHARGER, SUMMONER, ASSASSIN, BOMBER, MAGE }

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
	Archetype.MAGE: {"hp": 34, "speed": 78.0, "touch": 6, "tint": Color(0.5, 0.3, 0.85, 1)},       # deep violet
}

## Per-archetype pixel WEAPON (PixelLab overlay on the stick, via CharacterRig's
## equipment system) so the roster reads distinct at a glance (maker: "loads of
## enemies ... cooler"). CHASER stays bare (fast/weak); the rest carry a signature.
const ARCHETYPE_GEAR: Dictionary = {
	Archetype.BRUTE: "club",
	Archetype.CASTER: "staff",
	Archetype.CHARGER: "spear",
	Archetype.SUMMONER: "orb",
	Archetype.ASSASSIN: "dagger",
	Archetype.BOMBER: "bomb",
	Archetype.MAGE: "staff",
}

## Per-archetype telegraph accent so each tell reads distinct ("cool prep noters
## based on the attack"): area-denial tells stay danger-red, directional tells
## take the archetype's own hue. Falls back to red.
const TELE_ACCENTS: Dictionary = {
	Archetype.BRUTE: Color(0.95, 0.16, 0.13),
	Archetype.CASTER: Color(0.62, 0.52, 1.0),
	Archetype.CHARGER: Color(1.0, 0.65, 0.2),
	Archetype.SUMMONER: Color(0.4, 0.9, 0.6),
	Archetype.ASSASSIN: Color(0.9, 0.95, 1.0),
	Archetype.BOMBER: Color(1.0, 0.5, 0.15),
	Archetype.MAGE: Color(0.72, 0.45, 1.0),
}

var hp: int = 40
## SANDBOX Smash model (GameState.ringout_mode): hits pile onto this damage_pct
## instead of draining hp, knockback scales with it, and the enemy can ONLY be
## removed by a ring-out (VersusArena). Tower mode ignores it (hp-death clears
## floors). Reset to 0 on a ring-out respawn / passive respawn.
var damage_pct: float = 0.0
## Each point of incoming damage adds this much % — shared value with Hero.PCT_PER_DAMAGE.
const PCT_PER_DAMAGE: float = 0.8
## Co-op: cached /root/Net. Enemies are HOST-authoritative — the host spawns them
## through a MultiplayerSpawner (authority = peer 1) and streams pos/vel/hp via a
## code-built MultiplayerSynchronizer; clients run NO AI (puppets animate from the
## sync). null / inactive in SP -> every guard below is a no-op (byte-identical).
var _net: Node = null
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
var _leap_timer: float = 0.0                # LEAPING: remaining airborne safety window
var _leap_cd: float = 0.0                   # cooldown between ledge leaps
var _retreat_timer: float = 0.0             # assassin: post-strike disengage window
var _jitter_timer: float = 0.0              # assassin: time until the next feint roll
var _jitter_sign: float = 1.0               # assassin: current approach feint (+1/-1)
var _caster_signal: CasterSignal = null     # on-body charge glow (the "from caster" tell)
var _minions: Array = []                    # live summoned minions, pruned for the cap
var _status: StatusComponent = null         # elemental ailments (burn/chill/shock/...)
var _speed_scale: float = 1.0               # movement slow from chill/freeze/shock
var _bolt_element: int = -1                 # caster: rolled element tint for its bolt
var _passive_home: Vector2 = Vector2.ZERO   # passive: fixed spot it respawns to

# Difficulty (GameState.enemy_difficulty): scales stats + unlocks smart evasion.
# Easy/Normal are the shipped behaviour; Hard DODGES incoming hero bolts, and
# Impossible also DEFLECTS them point-blank and counter-fires — the "incredible"
# enemies the maker wants. Each row: hp/speed mult, cooldown-tick speed (higher =
# attacks more often), whether it dodges, whether it can deflect, evade reflex cd.
const DIFFICULTY: Array[Dictionary] = [
	{"hp": 0.7, "speed": 0.85, "cd_speed": 0.7, "dodge": false, "deflect": false, "evade_cd": 1.2},  # Easy
	{"hp": 1.0, "speed": 1.0, "cd_speed": 1.0, "dodge": false, "deflect": false, "evade_cd": 1.0},   # Normal
	{"hp": 1.6, "speed": 1.2, "cd_speed": 1.5, "dodge": true, "deflect": false, "evade_cd": 0.85},   # Hard
	{"hp": 2.4, "speed": 1.5, "cd_speed": 2.1, "dodge": true, "deflect": true, "evade_cd": 0.5},     # Impossible
]
const EVADE_DANGER_R: float = 155.0   # a hero bolt inside this triggers a dodge
const EVADE_DEFLECT_R: float = 58.0   # ...inside this (Impossible) it's deflected
var _cd_speed: float = 1.0            # attack-cooldown tick multiplier
var _smart_dodge: bool = false        # Hard+: hops away from incoming hero bolts
var _can_deflect: bool = false        # Impossible: point-blank deflect + counter
var _evade_reflex: float = 1.0        # cooldown between evades (difficulty reflex)
var _evade_cd: float = 0.0

@onready var rig: CharacterRig = $Rig


## Applied by melee / spell / blast. A decaying impulse added ON TOP of the
## chase velocity so the hit actually displaces the enemy instead of being
## stomped by the next physics tick's `velocity = dir * move_speed`.
func apply_knockback(impulse: Vector2, do_flop: bool = true) -> void:
	# Co-op: a shove landing on a client-side PUPPET is forwarded to the host (who
	# owns the real enemy + its synced transform). SP / host -> apply locally.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_apply_knockback", impulse)
		return
	impulse *= _knockback_mult()  # global over-tune (Stick-Fight: displacement IS the feel)
	# Smash sandbox: the higher this enemy's damage %, the farther the same hit
	# sends it — that's what makes a ring-out reachable. No-op in tower mode.
	if _is_ringout_mode():
		impulse *= ringout_knockback_scale(damage_pct)
	_knockback = impulse
	# Side-on: the VERTICAL part lands once as a real impulse into velocity.y so
	# a hard hit pops the enemy off the ground (gravity owns y from here). Adding
	# _knockback.y every frame instead would integrate the decaying impulse as an
	# acceleration and launch bodies at absurd speeds. The horizontal part keeps
	# the old decaying-channel treatment (`velocity.x = chase_x + _knockback.x`).
	velocity.y += impulse.y
	# Direction-aware ragdoll FLOP — bigger hit = bigger flop (the visual "reel").
	if do_flop and rig != null and impulse.length() > 12.0:
		var mag: float = impulse.length()
		rig.flop(clampf(mag / 700.0, 0.25, 0.8), 0.2)
		rig.apply_impulse(impulse.normalized(), minf(mag, 900.0) * 0.9)


## SANDBOX Smash: knockback multiplier at a given damage %. Pure + static (mirrors
## Hero.ringout_knockback_scale) — 0% -> 1.0x, 100% -> 2.0x, linear beyond.
static func ringout_knockback_scale(pct: float) -> float:
	return 1.0 + pct / 100.0


## True when the sandbox ring-out model is active (GameState.ringout_mode). Guarded
## so headless / host-authoritative contexts without the autoload read false.
func _is_ringout_mode() -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	return gs != null and bool(gs.get("ringout_mode"))


## Global knockback multiplier from the Tuning autoload (falls back to 1.6).
func _knockback_mult() -> float:
	var t: Node = get_node_or_null(^"/root/Tuning")
	if t != null and t.get(&"cfg") != null:
		var v: Variant = t.cfg.get(&"knockback_mult")
		if v != null:
			return float(v)
	return 1.6


## A hard-knocked enemy that slams into a wall craters the floor + kicks up dust
## ("damage the floor wherever they're sent"). Spends the remaining knockback so
## it fires once per slam, not every frame it stays pinned.
func _check_wall_slam() -> void:
	# Hard slam into a wall/breakable: crater + crack whatever it was (shared helper).
	_knockback = SlamPhysics.check(self, _knockback)


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


## Chase-jump / LEAP: reach a hero that's above us, or hop an obstacle we're
## walking into. Called between _apply_gravity and move_and_slide, so the
## is_on_floor()/is_on_wall() reads reflect the previous frame's slide state.
## A high hero (on a ledge, past the fixed hop's reach) triggers a ballistic
## LEAP; a modestly-higher hero or a wall triggers the small fixed hop.
func _try_chase_jump() -> void:
	if not is_on_floor():
		return
	# Leap has priority: it's the only way to actually reach a hero on a ledge.
	if _wants_leap():
		_start_leap()
		return
	if _jump_cd > 0.0:
		return
	# is_on_wall(), not get_slide_collision_count(): standing on the floor IS a
	# slide collision every frame, which would read as permanently "blocked".
	var blocked: bool = is_on_wall() and absf(velocity.x) > 10.0
	if _wants_chase_jump() or blocked:
		velocity.y = JUMP_VELOCITY
		_jump_cd = JUMP_COOLDOWN


## Pure "should we LEAP?" decision (floor check excluded, like _wants_chase_jump,
## so headless tests can drive it): cooldown elapsed and the hero sits above us
## by more than a fixed hop can clear, but within a leapable height + x window.
func _wants_leap() -> bool:
	if _leap_cd > 0.0 or not is_instance_valid(_hero):
		return false
	var dy: float = global_position.y - _hero.global_position.y  # positive = hero above
	var dx: float = absf(_hero.global_position.x - global_position.x)
	return dy > LEAP_MIN_HEIGHT and dy < LEAP_MAX_HEIGHT and dx < LEAP_HORIZONTAL_RANGE


## Ballistic launch velocity that carries `from` up and over to `to`: pick a
## vertical velocity whose apex clears the target height by LEAP_CLEARANCE, then
## the horizontal that lands at the target on the descending arc. Pure math —
## headless-testable. Solves 0.5*g*t^2 + vy*t - dy = 0 for the descending root.
func compute_leap_velocity(from: Vector2, to: Vector2) -> Vector2:
	var g: float = GRAVITY
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y                 # negative when the target is above
	var rise: float = maxf(-dy, 0.0) + LEAP_CLEARANCE
	var vy: float = -sqrt(2.0 * g * rise)         # upward launch (y-down: negative)
	var disc: float = vy * vy + 2.0 * g * dy
	disc = maxf(disc, 0.0)
	var t: float = (-vy + sqrt(disc)) / g          # time to reach target.y descending
	t = maxf(t, 0.05)
	var vx: float = clampf(dx / t, -LEAP_MAX_SPEED, LEAP_MAX_SPEED)
	return Vector2(vx, vy)


## Commit to a leap: launch, enter LEAPING (owns movement until landing/timeout).
func _start_leap() -> void:
	_attack_state = AttackState.LEAPING
	_leap_timer = LEAP_MAX_AIR_TIME
	_leap_cd = LEAP_COOLDOWN
	velocity = compute_leap_velocity(global_position, _hero.global_position)
	rig.flash()  # a quick "it's springing at you" tell


## LEAPING: ride the ballistic arc (no chase drive so the launch holds), gravity
## owns y. Touch-damages a hero we pass through mid-air. Exits to CHASE on landing
## (grounded + descending) or the safety timeout.
func _process_leap(delta: float) -> void:
	_leap_timer -= delta
	_apply_gravity(delta)
	move_and_slide()
	_check_wall_slam()
	rig.play(CharacterRig.State.DASH)  # a taut airborne pose
	if is_instance_valid(_hero):
		rig.set_facing(_hero.global_position - global_position)
		if global_position.distance_to(_hero.global_position) < 24.0 and _touch_cooldown <= 0.0 \
				and _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = 0.8
	var landed: bool = is_on_floor() and velocity.y >= 0.0
	if landed or _leap_timer <= 0.0:
		_attack_state = AttackState.CHASE


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
	if archetype == Archetype.CASTER or archetype == Archetype.MAGE:
		_bolt_element = randi() % Elements.count()  # a visible elemental bolt / AoE


## Equip the archetype's signature pixel weapon on the rig (no-op for CHASER + when
## the piece has no texture). Boss overrides this (it dresses itself in _ready).
func _apply_archetype_gear() -> void:
	var kind: String = ARCHETYPE_GEAR.get(archetype, "")
	if kind != "" and is_instance_valid(rig):
		rig.set_equipment("weapon", kind)


## Scale stats + unlock smart behaviours from GameState.enemy_difficulty.
func _apply_difficulty() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var d: int = int(gs.get("enemy_difficulty")) if gs != null else 1
	d = clampi(d, 0, DIFFICULTY.size() - 1)
	var cfg: Dictionary = DIFFICULTY[d]
	max_hp = int(round(float(max_hp) * float(cfg["hp"])))
	move_speed *= float(cfg["speed"])
	_cd_speed = float(cfg["cd_speed"])
	_smart_dodge = bool(cfg["dodge"])
	_can_deflect = bool(cfg["deflect"])
	_evade_reflex = float(cfg["evade_cd"])


## Hard+ reflex: if a hero bolt is closing in, DODGE (hop clear, reusing the leap
## arc) or — point-blank on Impossible — DEFLECT it (fizzle + counter-fire) while
## still advancing. Returns true only when a dodge took over movement this frame.
func _try_evade(delta: float) -> bool:
	if _evade_cd > 0.0:
		return false
	var threat: Node2D = null
	var best: float = EVADE_DANGER_R
	for s: Node in get_tree().get_nodes_in_group("player_spell"):
		if not s is Node2D or not is_instance_valid(s):
			continue
		var dd: float = global_position.distance_to((s as Node2D).global_position)
		if dd < best:
			best = dd
			threat = s as Node2D
	if threat == null:
		return false
	_evade_cd = _evade_reflex
	if _can_deflect and best < EVADE_DEFLECT_R:
		_deflect(threat)
		return false  # deflect keeps us advancing — menacing
	# Dodge: hop away from the bolt, riding the ballistic LEAPING state.
	var away: float = signf(global_position.x - threat.global_position.x)
	if away == 0.0:
		away = 1.0
	velocity = Vector2(away * move_speed * 2.2, JUMP_VELOCITY * 0.8)
	_attack_state = AttackState.LEAPING
	_leap_timer = 0.45
	rig.flash()
	_apply_gravity(delta)
	move_and_slide()
	return true


## Point-blank deflect (Impossible): block the hero bolt + counter-fire back.
func _deflect(bolt: Node2D) -> void:
	if bolt.has_method("fizzle"):
		bolt.call("fizzle")
	elif bolt.has_method("consume"):
		bolt.call("consume")
	rig.flash()
	Sfx.play("ding", 0.0, 0.02)
	if is_instance_valid(_hero):
		_spawn_enemy_bolt(
			global_position,
			(_hero.global_position - global_position).normalized(),
			_bolt_element if _bolt_element >= 0 else 2)


func _ready() -> void:
	add_to_group("enemy")
	_net = get_node_or_null("/root/Net")
	_apply_archetype_defaults()
	_apply_difficulty()
	hp = max_hp
	rig.set_tint(tint)
	_apply_archetype_gear()
	var heroes: Array = get_tree().get_nodes_in_group("hero")
	if not heroes.is_empty():
		_hero = heroes[0]
	# Floating HP bar over the head (enemies have no MP).
	var bars := CharacterBars.new()
	add_child(bars)
	bars.configure(self, false, -24.0)
	if passive:
		_passive_home = global_position  # position is set by the spawner before add_child
	_setup_enemy_net()


func _physics_process(delta: float) -> void:
	# Co-op: enemies are HOST-authoritative. A client-side puppet runs NO AI/physics —
	# its transform + hp arrive over the MultiplayerSynchronizer; it only animates.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		_remote_enemy_visual(delta)
		return
	if passive:
		_process_passive(delta)
		return
	_retarget()  # multi-hero: chase the nearest LIVING hero (SP: the one hero, unchanged)
	_touch_cooldown = max(_touch_cooldown - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_attack_cooldown = maxf(_attack_cooldown - delta * _cd_speed, 0.0)  # harder = faster attacks
	_evade_cd = maxf(_evade_cd - delta, 0.0)
	if _smart_dodge and _attack_state == AttackState.CHASE and _try_evade(delta):
		return  # dodged / deflected a hero bolt this frame
	_jump_cd = maxf(_jump_cd - delta, 0.0)
	_leap_cd = maxf(_leap_cd - delta, 0.0)
	_speed_scale = _status.slow_factor() if _status != null and is_instance_valid(_status) else 1.0
	# Hard CC (freeze/shock) suppresses NEW attacks: hold the cooldown just above
	# zero so no windup can trigger until it wears off. Chill only slows (above).
	# It also FREEZES the rig's locomotion cycle so the body reads as rooted under
	# the ice instead of jogging in place.
	var hard_cc: bool = _status != null and is_instance_valid(_status) and _status.is_hard_cc()
	if is_instance_valid(rig):
		rig.set_frozen(hard_cc)
	if hard_cc:
		_attack_cooldown = maxf(_attack_cooldown, 0.05)
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
		AttackState.LEAPING:
			_process_leap(delta)
			return
	# Archetype-specific CHASE behaviour (chaser + brute fall through to default).
	if archetype == Archetype.CASTER:
		_caster_chase(delta)
		return
	if archetype == Archetype.MAGE:
		_mage_chase(delta)
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
	var chase_x: float = signf(_hero.global_position.x - global_position.x) * move_speed * _speed_scale
	velocity.x = chase_x + _knockback.x + _separation_x()
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


## Practice dummy (Task 1 sandbox): no chase, no retarget, no attack windup —
## just absorb knockback/gravity and stand there so it reads as an inert
## punching bag. Still takes damage normally via take_damage/_die below.
func _process_passive(delta: float) -> void:
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	velocity.x = _knockback.x
	_apply_gravity(delta)
	move_and_slide()
	_check_wall_slam()
	rig.play(CharacterRig.State.IDLE)


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


## True only on the co-op HOST (the only peer whose AI reaches an attack windup:
## client enemies are puppets that return early from _physics_process). False in
## SP (no session) — so every broadcast below is a no-op and SP stays byte-identical.
func _coop_active() -> bool:
	return _net != null and _net.is_host()


## Build THE host's danger indicator for an attack tell and — in a co-op session —
## broadcast a source-less VISUAL twin to every client so a remote hero sees the
## same tell before it can land (a Telegraph carries no damage; the twin is safe).
## Single construction path for all seven archetype windups. Returns the host node
## so the caller holds it in `_telegraph` (for abort/clear). `cfg` keys mirror the
## Telegraph fields: style, pos, accent, radius, windup; plus line/length/width/angle
## for LANE and aim/reach for MUZZLE.
func _emit_telegraph(cfg: Dictionary) -> Telegraph:
	var style_v: Variant = cfg.get("style", Telegraph.Style.ZONE)
	var pos: Vector2 = cfg.get("pos", global_position)
	var accent: Color = cfg.get("accent", _accent())
	var radius: float = float(cfg.get("radius", ATTACK_RADIUS))
	var windup: float = float(cfg.get("windup", ATTACK_WINDUP))
	var is_line: bool = bool(cfg.get("line", false))
	var aim: Vector2 = cfg.get("aim", Vector2.RIGHT)
	var reach: float = float(cfg.get("reach", 120.0))
	var length: float = float(cfg.get("length", 0.0))
	var width: float = float(cfg.get("width", 0.0))
	var angle: float = float(cfg.get("angle", 0.0))

	var tele := Telegraph.new()
	# Sibling in the arena, not a child: the sigil marks a spot in the world and
	# must not ride along if the caster gets knocked around mid-windup.
	get_parent().add_child(tele)
	tele.global_position = pos
	tele.source = self
	tele.accent = accent
	tele.style = style_v
	tele.aim_dir = aim
	tele.reach = reach
	tele.fired.connect(_on_telegraph_fired)
	if is_line:
		tele.start_line(length, width, angle, windup)
	else:
		tele.start(radius, windup)

	if _coop_active():
		_net.broadcast_telegraph({
			"style": style_v, "pos": pos, "accent": accent,
			"radius": radius, "windup": windup, "line": is_line,
			"aim": aim, "reach": reach, "length": length, "width": width, "angle": angle,
		})
	return tele


## Snapshot the hero's position, spawn the danger circle there, hold still.
## A stationary player gets hit; a dashing player escapes the circle.
func _start_windup() -> void:
	_attack_state = AttackState.WINDUP
	_strike_center = _hero.global_position
	rig.flash()  # readable tell: the brute blinks as it roots itself
	_telegraph = _emit_telegraph({
		"style": Telegraph.Style.ZONE, "pos": _strike_center,
		"radius": ATTACK_RADIUS, "windup": ATTACK_WINDUP,
	})
	_spawn_caster_signal(14.0, ATTACK_WINDUP)


func _on_telegraph_fired() -> void:
	_telegraph = null  # the Telegraph fades and frees itself after firing
	_free_caster_signal()
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
		Archetype.MAGE:
			_cast_mage_aoe()
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
	velocity.x = move_x * move_speed * _speed_scale + _knockback.x
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
	_telegraph = _emit_telegraph({
		"style": Telegraph.Style.MUZZLE, "pos": global_position,  # tell is ON the caster
		"radius": CASTER_TELE_RADIUS, "windup": CASTER_WINDUP,
		"aim": _aim_dir, "reach": 130.0,
	})
	_spawn_caster_signal(11.0, CASTER_WINDUP)


## Spawn a hostile bolt (the REAL, damaging one, host-authoritative) and — in a
## co-op session — broadcast a VISUAL-only twin so a remote hero sees the shot that
## can hit it. Shared by the caster's fire and the Impossible-tier deflect counter.
func _spawn_enemy_bolt(pos: Vector2, dir: Vector2, element: int) -> void:
	var proj := EnemyProjectile.new()
	get_parent().add_child(proj)
	proj.global_position = pos
	proj.launch(dir)
	proj.set_element(element)
	if _coop_active():
		_net.broadcast_projectile({"pos": pos, "dir": dir, "element": element})


func _fire_projectile() -> void:
	_spawn_enemy_bolt(global_position, _aim_dir, _bolt_element)
	_attack_state = AttackState.RECOVER
	_recover_timer = ATTACK_RECOVER_TIME
	_attack_cooldown = CASTER_COOLDOWN


# ---------------------------------------------------------------- MAGE (AoE zoner)
## Kite in the HORIZONTAL [MIN,MAX] band like the caster; when in-band and off
## cooldown, telegraph a big ground AoE at the hero's snapshot position — dodge
## OUT of the marked circle. The AoE itself is a parameterized BlastSpell aimed at
## group "hero". Side-on: band on x only, gravity owns y.
func _mage_chase(delta: float) -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dist_x: float = absf(to_hero.x)
	var move_x: float = 0.0
	if dist_x < MAGE_RANGE_MIN:
		move_x = -signf(to_hero.x)                # too close — back away
	elif dist_x > MAGE_RANGE_MAX:
		move_x = signf(to_hero.x)                 # too far — close in
	velocity.x = move_x * move_speed * _speed_scale + _knockback.x
	_apply_gravity(delta)
	move_and_slide()
	rig.play(CharacterRig.State.RUN if move_x != 0.0 else CharacterRig.State.IDLE)
	rig.set_facing(to_hero)
	if _attack_cooldown <= 0.0 and dist_x >= MAGE_RANGE_MIN and dist_x <= MAGE_RANGE_MAX:
		_start_mage_windup()


## Root + mark the AoE ZONE where the hero stands NOW (snapshot). A moving hero
## dodges out of the circle by the time it lands. Self charge-glow reads "FROM me".
func _start_mage_windup() -> void:
	_attack_state = AttackState.WINDUP
	_strike_center = _hero.global_position
	rig.flash()
	_telegraph = _emit_telegraph({
		"style": Telegraph.Style.ZONE, "pos": _strike_center,  # ground zone to dodge out of
		"radius": MAGE_AOE_RADIUS, "windup": MAGE_WINDUP,
	})
	_spawn_caster_signal(13.0, MAGE_WINDUP)


## The tell paid off: drop a configured BlastSpell on the marked spot, targeting
## the HERO group, tinted + ailment-ed by the mage's rolled element. detonate_now
## skips the BlastSpell's own windup — the Enemy telegraph already served the tell.
func _cast_mage_aoe() -> void:
	var blast_scene: PackedScene = load(MAGE_BLAST_SCENE)
	var blast: Node2D = blast_scene.instantiate()
	get_parent().add_child(blast)
	blast.call("configure", {
		"target_group": "hero",
		"damage": MAGE_AOE_DAMAGE,
		"radius": MAGE_AOE_RADIUS,
		"knockback": MAGE_AOE_KNOCKBACK,
		"element_id": _bolt_element,
	})
	blast.call("detonate_now", _strike_center)
	if _coop_active():  # clients see a damage-free twin of the detonation
		_net.broadcast_blast(_strike_center, _bolt_element, MAGE_AOE_RADIUS)
	_attack_state = AttackState.RECOVER
	_recover_timer = ATTACK_RECOVER_TIME
	_attack_cooldown = MAGE_COOLDOWN


# --------------------------------------------------------------- CHARGER (lane)
## Chase toward the hero on x; lock a lane and telegraph it once in range.
## The approach also chase-jumps so it can reach a hero on a platform above.
func _charger_chase(delta: float) -> void:
	var to_hero: Vector2 = _hero.global_position - global_position
	var dist: float = to_hero.length()
	velocity.x = signf(to_hero.x) * move_speed * _speed_scale + _knockback.x
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
	_telegraph = _emit_telegraph({
		"style": Telegraph.Style.LANE, "pos": global_position, "line": true,
		"length": CHARGE_LEN, "width": CHARGE_WIDTH, "angle": _charge_dir.angle(),
		"windup": CHARGE_WINDUP,
	})
	_spawn_caster_signal(12.0, CHARGE_WINDUP)


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
	velocity.x = move_x * move_speed * _speed_scale + _knockback.x
	_apply_gravity(delta)
	move_and_slide()
	rig.play(CharacterRig.State.RUN if move_x != 0.0 else CharacterRig.State.IDLE)
	rig.set_facing(to_hero)
	if _attack_cooldown <= 0.0 and dist_x >= SUMMONER_RANGE_MIN and dist_x <= SUMMONER_RANGE_MAX \
			and _live_minion_count() < SUMMON_MAX_ALIVE:
		_start_summon_windup()


## Root + a "gathering magic" tell on the summoner itself. The windup is the
## fair-play window: burst the summoner (or knock it around) before it fires
## and no minions arrive. _abort_attack() cancels this cleanly like any windup.
func _start_summon_windup() -> void:
	_attack_state = AttackState.WINDUP
	rig.flash()
	_telegraph = _emit_telegraph({
		"style": Telegraph.Style.GATHER, "pos": global_position,  # tell is ON the summoner
		"radius": SUMMON_TELE_RADIUS, "windup": SUMMON_WINDUP,
	})
	_spawn_caster_signal(12.0, SUMMON_WINDUP)


## The tell paid off: pop SUMMON_COUNT weak chaser minions in around the
## summoner as arena siblings (their own _ready joins group "enemy" and finds
## the hero), then recover and start the long summon cooldown.
## Scene load()ed at runtime, not preload: Enemy.tscn references this very
## script, so a preload here would be a cyclic resource dependency.
func _spawn_minions() -> void:
	# Never exceed the concurrent cap: only fill the remaining room.
	var to_spawn: int = mini(SUMMON_COUNT, maxi(SUMMON_MAX_ALIVE - _live_minion_count(), 0))
	var chaser: Dictionary = ARCHETYPE_DEFAULTS[Archetype.CHASER]
	var lit: Color = Color(tint.r, tint.g, tint.b, 1.0).lightened(0.35)  # reads as spawn
	for i in to_spawn:
		var offset := Vector2.from_angle(randf() * TAU) * randf_range(SUMMON_SCATTER * 0.4, SUMMON_SCATTER)
		var pos: Vector2 = global_position + offset
		var minion: Node = _spawn_runtime_enemy({
			"boss": false, "arch": Archetype.CHASER, "hp": SUMMON_MINION_HP,
			"spd": float(chaser["speed"]), "touch": int(chaser["touch"]), "tint": lit, "tele": false,
			"x": pos.x, "y": pos.y,
		})
		if minion != null:
			_minions.append(minion)
	_attack_state = AttackState.RECOVER
	_recover_timer = ATTACK_RECOVER_TIME
	_attack_cooldown = SUMMON_COOLDOWN


## Spawn a runtime enemy (summoner minion / boss add) through the Arena so it goes
## via the co-op MultiplayerSpawner when a session is up (replicated + host-owned),
## or straight into the arena in SP. Falls back to a plain instantiate when the
## parent isn't an Arena (headless helper tests). Returns the node (may be null).
func _spawn_runtime_enemy(data: Dictionary) -> Node:
	var parent: Node = get_parent()
	if parent != null and parent.has_method("spawn_extra_enemy"):
		return parent.spawn_extra_enemy(data)
	var e: Node = load("res://scenes/combat/Enemy.tscn").instantiate()
	e.archetype = int(data["arch"])
	e.max_hp = int(data["hp"])
	e.move_speed = float(data["spd"])
	e.touch_damage = int(data["touch"])
	e.tint = data["tint"]
	if parent != null:
		parent.add_child(e)
		(e as Node2D).global_position = Vector2(float(data["x"]), float(data["y"]))
	return e


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
	velocity.x = move_x * move_speed * _speed_scale + _knockback.x
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
	_telegraph = _emit_telegraph({
		"style": Telegraph.Style.DART, "pos": _strike_center,
		"radius": ASSASSIN_TELE_RADIUS, "windup": ASSASSIN_WINDUP,
	})
	_spawn_caster_signal(10.0, ASSASSIN_WINDUP)


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
	var chase_x: float = signf(_hero.global_position.x - global_position.x) * move_speed * _speed_scale
	velocity.x = chase_x + _knockback.x + _separation_x()
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
	_telegraph = _emit_telegraph({
		"style": Telegraph.Style.BOMB, "pos": _strike_center,
		"radius": BOMB_RADIUS, "windup": BOMB_WINDUP,
	})
	_spawn_caster_signal(16.0, BOMB_WINDUP)


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
	if _coop_active():  # clients see the bomber's detonation burst
		_net.broadcast_burst(_strike_center, Color(1.0, 0.75, 0.35, 0.95), Color(0.9, 0.3, 0.15, 0.0))
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
	_free_caster_signal()


## The on-body charge glow (CasterSignal) — the tell reading as "FROM this enemy."
## A child of the enemy so it follows a shoved body; freed on fire/abort.
func _spawn_caster_signal(base_r: float, windup: float) -> void:
	_free_caster_signal()
	_caster_signal = CasterSignal.new()
	add_child(_caster_signal)
	_caster_signal.position = Vector2(0.0, -8.0)  # around the chest / weapon
	_caster_signal.charge(_accent(), windup, base_r)


func _free_caster_signal() -> void:
	if is_instance_valid(_caster_signal):
		_caster_signal.queue_free()
	_caster_signal = null


## Telegraph accent colour for this archetype (falls back to danger-red).
func _accent() -> Color:
	var c: Color = TELE_ACCENTS.get(archetype, Telegraph.RING_COLOR)
	return c


## Boids-style separation nudge so chasers don't stack into one body on the hero
## (enemies don't physically collide with each other). O(n) over the small roster.
func _separation_x() -> float:
	var push: float = 0.0
	for other: Node in get_tree().get_nodes_in_group("enemy"):
		if other == self or not other is Node2D:
			continue
		var d: Vector2 = global_position - (other as Node2D).global_position
		var dist: float = d.length()
		if dist > 0.001 and dist < 34.0:
			push += signf(d.x) * (34.0 - dist) / 34.0
	return clampf(push, -1.0, 1.0) * 70.0


## Live minion count for the summoner cap — prunes freed/queued refs in place.
func _live_minion_count() -> int:
	var alive: Array = []
	for m: Node in _minions:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			alive.append(m)
	_minions = alive
	return _minions.size()


## `tint` with alpha > 0 marks an ELEMENTAL source (a DoT tick / chain / pop):
## the hit flashes + the floating number take that element hue and the body pulses
## a bloomed glow in the ailment colour (maker: "make them glow w tik damage").
## Alpha 0 (the default) is a plain physical hit — the HDR white pop as before.
func take_damage(amount: int, tint: Color = Color(1.0, 1.0, 1.0, 0.0)) -> void:
	# Co-op: enemies are host-authoritative. A hit landing on a client-side PUPPET is
	# forwarded to the host, who owns the real enemy, resolves it, and syncs hp back.
	# SP / host (authority) -> apply locally (byte-identical to before).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_take_damage", amount, tint)
		return
	# Weaken (shadow) amplifies incoming damage.
	var dealt: int = amount
	if _status != null and is_instance_valid(_status):
		dealt = int(round(float(amount) * _status.damage_mult()))
	# Smash sandbox: accrue damage % (no hp drain, no hp-death — only a ring-out
	# removes a bot). Tower mode: drain hp and die at 0 (unchanged).
	var ringout: bool = _is_ringout_mode()
	if ringout:
		damage_pct += float(dealt) * PCT_PER_DAMAGE
	else:
		hp = max(hp - dealt, 0)
	var is_elemental: bool = tint.a > 0.0
	if is_elemental:
		# Glow-on-tick: a brief bloomed pulse in the ailment hue (HDR > 1 so it
		# blooms) — damage-over-time reads as a rhythmic glow + a floating number.
		rig.flash_color(Color(tint.r * 1.5 + 0.2, tint.g * 1.5 + 0.2, tint.b * 1.5 + 0.2), 0.12)
	else:
		_flash()
	# Floating combat number over the head. Elemental ticks take the hue; physical
	# hits are near-white. Big hits get the crit treatment.
	var num_col: Color = Color(tint.r, tint.g, tint.b, 1.0) if is_elemental else Color(1.0, 0.96, 0.9)
	DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, -16.0), dealt, num_col, dealt >= 20)
	if not ringout and hp == 0:
		_die()


## Apply an elemental ailment (called by the hero's element-carrying spells).
## Lazily creates the StatusComponent child on first use; can_chain gates the
## lightning hop so a chained shock can't re-chain forever.
func apply_status(element: int, can_chain: bool = true) -> void:
	if _status == null or not is_instance_valid(_status):
		_status = StatusComponent.new()
		add_child(_status)
	_status.apply(element, can_chain)


func _flash() -> void:
	rig.flash_color(Color(1.7, 1.7, 1.7), 0.08)  # HDR white hit-pop (blooms)


func _die() -> void:
	_abort_attack()  # never leave an orphaned danger circle behind a corpse
	if passive:
		# Practice dummy: never actually leaves — a quieter "knocked out" beat,
		# then it pops back up at its fixed spot (see _respawn_passive). No kill
		# power / run-kill credit — it isn't a real kill.
		_spawn_death_burst()
		Sfx.play("enemy_death")
		Juice.shake_camera(DEATH_SHAKE * 0.4)
		_respawn_passive()
		return
	_grant_kill_power()
	_notify_run_kill()
	_spawn_death_burst()
	_spawn_corpse()
	Sfx.play("enemy_death")
	Juice.shake_camera(DEATH_SHAKE)
	Juice.hit_stop(DEATH_HIT_STOP)
	queue_free()


## Hide + disable the collider for PASSIVE_RESPAWN_DELAY, then pop back up at
## `_passive_home` with hp refilled — a permanent punching bag that never
## actually leaves the tree. Guards `is_instance_valid(self)` after the await
## in case the whole arena (and this node with it) got torn down meanwhile.
func _respawn_passive() -> void:
	visible = false
	set_physics_process(false)
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if cs != null:
		cs.set_deferred("disabled", true)
	await get_tree().create_timer(PASSIVE_RESPAWN_DELAY).timeout
	if not is_instance_valid(self):
		return
	global_position = _passive_home
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	hp = max_hp
	damage_pct = 0.0        # fresh punching bag: reset the accrued Smash %
	visible = true
	set_physics_process(true)
	if cs != null:
		cs.set_deferred("disabled", false)
	CombatVfx.spawn_burst(
		get_parent(), _passive_home,
		Color(0.75, 0.85, 1.0, 0.9), Color(0.75, 0.85, 1.0, 0.0),
		16, 0.35, 50.0, 120.0, 1.5, 3.0
	)


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


# ------------------------------------------------------------- co-op networking
## Damage/knockback forwarded from a puppet (any peer) run on the HOST authority
## here — the same take_damage/apply_knockback the local hit path uses, so the
## resolution (hp, death, phase logic in Boss) lives in one place.
@rpc("any_peer", "call_remote", "reliable")
func _net_take_damage(amount: int, tint: Color = Color(1.0, 1.0, 1.0, 0.0)) -> void:
	take_damage(amount, tint)


@rpc("any_peer", "call_remote", "reliable")
func _net_apply_knockback(impulse: Vector2) -> void:
	apply_knockback(impulse)


## Co-op: stand up a MultiplayerSynchronizer that streams this enemy's transform +
## hp from the host (authority) to every client. Built in code (no .tscn surgery),
## mirroring Hero._setup_net_sync. No-op in SP.
func _setup_enemy_net() -> void:
	if _net == null or not _net.is_active():
		return
	var cfg := SceneReplicationConfig.new()
	for p: String in [":position", ":velocity", ":hp"]:
		cfg.add_property(NodePath(p))
	cfg.property_set_replication_mode(NodePath(":position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(":velocity"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	sync.root_path = NodePath("..")
	sync.replication_config = cfg
	add_child(sync)
	sync.set_multiplayer_authority(get_multiplayer_authority())


## Client puppet: no AI, no move_and_slide (position is streamed). Just animate the
## rig from the synced velocity + face the nearest hero, and keep the HP bar honest
## (hp is synced, so CharacterBars follows automatically).
func _remote_enemy_visual(_delta: float) -> void:
	if not is_instance_valid(rig):
		return
	rig.set_body_velocity(velocity)
	rig.play(CharacterRig.State.RUN if absf(velocity.x) > 8.0 else CharacterRig.State.IDLE)
	var nearest: Node2D = _nearest_hero()
	if nearest != null:
		rig.set_facing(nearest.global_position - global_position)


## Retarget to the nearest LIVING hero each host frame (co-op: chase whoever is
## closest; SP: the single hero, so this is a no-op change in feel).
func _retarget() -> void:
	var nearest: Node2D = _nearest_hero()
	if nearest != null:
		_hero = nearest


## Nearest hero that isn't downed (co-op). Falls back to any hero. null if none.
func _nearest_hero() -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	var any: Node2D = null
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if not (h is Node2D) or not is_instance_valid(h):
			continue
		any = h as Node2D
		if h.has_method("is_downed") and h.is_downed():
			continue
		var d: float = global_position.distance_squared_to((h as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = h as Node2D
	return best if best != null else any
