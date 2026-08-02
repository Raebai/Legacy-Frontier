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

# ------------------------------------------------------------- HIT SILHOUETTE
# THE BUG THIS EXISTS TO FIX: Enemy.tscn ships a 20x20 movement collider centred
# on the origin, but the rig it draws is `rig.height` (31) tall and is drawn
# CENTRED on that same origin — head top at -15.5, feet at +15.5. So the solid
# part of an enemy covered only the middle 64% of the drawing, and roughly HALF
# the head circle (y in [-15.5, -10]) had nothing behind it. A bolt aimed at the
# head flew straight through and registered nothing. On the SpellPlayground
# sparring dummies (scale 1.9) that dead zone is 10.4 px tall — big enough to
# aim into deliberately, which is exactly what the maker reported.
#
# The three factors below MIRROR CharacterRig._compute_pose() exactly
# (r = height * 0.18, hip = height * 0.1, leg_len = height * 0.4). They are NOT
# tunables: if the rig's pose maths changes, these must change with it or the hit
# test drifts off the drawing all over again. One silhouette, one source.
## MIRRORS CharacterRig.HEAD_R_FACTOR. Moved 0.18 -> 0.105 with the stickman
## proportion pass — the DRAWN head shrank, so the tested head must shrink with it or
## the hit disc is bigger than the skull and hits register on empty air beside it.
## The head TOP is unchanged (head_center = -h/2 + r), so nothing else re-derives.
const RIG_HEAD_R_FACTOR: float = 0.105
const RIG_HIP_Y_FACTOR: float = 0.1
const RIG_LEG_LEN_FACTOR: float = 0.4
## Forgiveness ring around the silhouette for body_distance() callers, as a
## FRACTION of rig height so a 1.9x-scaled sparring dummy gets a proportionally
## bigger margin rather than the same absolute one. UNTESTED GUESS: 0.12 * 31 =
## 3.7 px on a standard enemy, which is about the drawn limb half-width
## (height * 0.08) plus a whisker. Tune it HERE, never at a call site — a second
## margin constant somewhere else is how the two-schemes bug started.
## Raised 0.12 -> 0.155 alongside the stickman proportion pass. The figure got THINNER
## (head 0.18h -> 0.105h, stroke 0.16h -> 0.075h), so a fixed margin would have quietly
## shrunk the whole catchable area by a third and walked straight back into the "spells
## pass through heads" report. This keeps the effective head reach (r + margin) at
## ~0.26h against the old ~0.30h — still slightly tighter than before, deliberately,
## because the drawing genuinely is slimmer. UNTESTED GUESS: 0.155 * 31 = 4.8 px.
const HIT_MARGIN_FACTOR: float = 0.155
## Physics layer for the hurtbox when this node's own collision_layer is 0
## (headless harnesses build a bare Enemy with engine defaults, not the scene).
## Layer 3 / value 4 is the "spell-hittable" bucket Spell.tscn already masks.
const HURTBOX_FALLBACK_LAYER: int = 4
## Rig height assumed when there is no rig at all (headless stubs). Matches
## CharacterRig's own default so the fallback silhouette is the shipped one.
const RIG_FALLBACK_HEIGHT: float = 31.0
## Hurtbox width when the movement collider isn't a rectangle we can read. 0.65
## is Enemy.tscn's shipped 20/31 ratio — the point is that the fix NEVER widens
## an enemy, it only makes it as tall as it is drawn.
const HURTBOX_WIDTH_FALLBACK_FACTOR: float = 0.65

# ─────────────────────────────── AGGRESSION ──────────────────────────────────
# THE RULE FOR EVERY NUMBER BELOW: shorten the DEAD time, never the TELL.
# "So much going on" means enemies commit rather than loiter, so cooldowns and
# recovery windows are tight — but every windup constant is untouched, because
# the windup IS the fair-play contract and a tell you cannot read is not
# difficulty, it is a cheat. Recovery also no longer roots an enemy in place
# (see _process_recover): a body standing still after its swing is dead air with
# legs, and a floor full of them is a floor where nothing is happening.

# Telegraphed heavy attack tuning (brute archetype).
const ATTACK_RANGE: float = 78.0  # start winding up inside this distance
const ATTACK_WINDUP: float = 0.6  # seconds of tell before the strike lands
const ATTACK_RADIUS: float = 40.0  # danger-circle radius
const ATTACK_DAMAGE: int = 22
const ATTACK_COOLDOWN: float = 1.0  # was 1.4 — a brute that swings every 2s is scenery
const ATTACK_LUNGE: float = 180.0  # impulse toward the circle on a landed hit
const ATTACK_RECOVER_TIME: float = 0.16  # was 0.3 — and it now RE-APPROACHES, not roots
## Fraction of move_speed an enemy walks back in during RECOVER. Not 1.0: the
## recovery still reads as a stagger, it just closes ground instead of posing.
const RECOVER_DRIVE: float = 0.45

# Ranged CASTER archetype: kites in a band, telegraphs, fires a dodgeable bolt.
# Band pulled IN (was 180..320) — in a 960px-wide room a caster parked at 320
# spends the fight as a dot at the far wall. It is a threat, not a sniper.
const CASTER_RANGE_MIN: float = 150.0  # back away if the hero is closer than this
const CASTER_RANGE_MAX: float = 275.0  # close in if farther than this; fire in-band
const CASTER_WINDUP: float = 0.7
const CASTER_COOLDOWN: float = 1.45  # was 1.9
const CASTER_TELE_RADIUS: float = 18.0  # small "charging" tell on the caster itself
## Kiters used to stand PERFECTLY STILL whenever they were in-band and on
## cooldown — the single most "polite queue" behaviour in the roster. They now
## drift along the band at this fraction of move_speed, reversing every
## KITE_STRAFE_PERIOD seconds, so a backline reads as circling for an angle.
const KITE_STRAFE_DRIVE: float = 0.45
const KITE_STRAFE_PERIOD: float = 0.9

# CHARGER archetype: telegraphs a lane at the hero, then rockets down it.
const CHARGE_RANGE: float = 260.0  # start the windup inside this distance
const CHARGE_WINDUP: float = 0.7
const CHARGE_SPEED: float = 520.0
const CHARGE_TIME: float = 0.35  # seconds the charge lasts
const CHARGE_DAMAGE: int = 24
const CHARGE_LEN: float = 300.0  # telegraph lane length
const CHARGE_WIDTH: float = 34.0
const CHARGE_HIT_RADIUS: float = 26.0
const CHARGE_COOLDOWN: float = 1.25  # was 1.6

# SUMMONER archetype: kites like the caster, telegraphs on itself, then calls
# in SUMMON_COUNT weak chaser minions. The tell is the window to burst it down.
const SUMMONER_RANGE_MIN: float = 150.0  # same kite band as the caster
const SUMMONER_RANGE_MAX: float = 275.0
const SUMMON_WINDUP: float = 0.8
const SUMMON_COOLDOWN: float = 3.4  # was 4.0
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
const ASSASSIN_COOLDOWN: float = 0.95       # was 1.1
const ASSASSIN_RETREAT_TIME: float = 0.6    # was 0.8 — disengage, don't emigrate
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
const MAGE_RANGE_MIN: float = 170.0   # kite band, a touch longer than the caster
const MAGE_RANGE_MAX: float = 300.0   # was 380 — over a third of the room away
const MAGE_WINDUP: float = 0.85       # generous — it's a big AoE
const MAGE_COOLDOWN: float = 2.1      # was 2.6
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

# POUNCE. The leap above solves a VERTICAL problem — reaching a hero on a ~170px
# ledge — and the tower arena is a flat 960x480 room with no such ledges, so on
# every floor of the actual game that whole system is unreachable code. The
# ballistic solver is the useful half and it works just as well sideways: a
# grounded CHASER or ASSASSIN that has fallen behind now springs the gap instead
# of jogging across the room in a straight line. It reuses compute_leap_velocity
# and the LEAPING state verbatim (mid-air touch damage included), so a pounce is
# already replicated, already animated and already interruptible.
## Only the two archetypes whose fantasy is "it gets to you". A pouncing BRUTE
## would undermine the readable slow-heavy silhouette; a pouncing BOMBER would
## turn a dodgeable fuse into a homing missile.
const POUNCE_ARCHETYPES: Array[int] = [0, 5]   # CHASER, ASSASSIN
const POUNCE_MIN_DIST: float = 210.0   # closer than this and it can just run at you
const POUNCE_MAX_DIST: float = 430.0   # farther and the arc is silly / unreadable
const POUNCE_COOLDOWN: float = 2.4     # per-enemy, so a pack does not all spring at once
const POUNCE_CHANCE: float = 0.5       # coin-flip per opportunity: pressure, not a metronome
## THE POUNCE IS A FLOOR-2 VERB. The chase itself is untouched at every depth —
## a chaser still runs at you at 140 and never loiters, which is the "chase like
## hell" the maker asked to keep. What waits one floor is the SPRING: a body that
## crosses 400 px of room in an arc is the single hardest thing to answer before
## you have found the dash, and floor 1 is the only place in the game where that
## is true of the player. From floor 2 it is exactly as aggressive as it was.
const POUNCE_MIN_DEPTH: int = 2
## Which floor of the climb this body was spawned on. 0 = "not told" (the F6
## sandbox, VersusArena, every headless harness) and imposes NO restriction, so
## those paths behave byte-identically to before. Set from the replicated spawn
## dict, so host + client agree.
var floor_depth: int = 0

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
var _strafe_timer: float = 0.0              # kiters: time until the drift reverses
var _strafe_sign: float = 1.0               # kiters: current in-band drift direction
var _passive_home: Vector2 = Vector2.ZERO   # passive: fixed spot it respawns to

# Difficulty (GameState.enemy_difficulty): scales stats + unlocks smart evasion.
# Easy/Normal are the shipped behaviour; Hard DODGES incoming hero bolts, and
# Impossible also DEFLECTS them point-blank and counter-fires — the "incredible"
# enemies the maker wants. Each row: hp/speed mult, cooldown-tick speed (higher =
# attacks more often), whether it dodges, whether it can deflect, evade reflex cd.
const DIFFICULTY: Array[Dictionary] = [
	# react = modelled reaction time in seconds; p_miss = share of threats this tier
	# deliberately fumbles. Those two ARE the difficulty dial — never damage buffs,
	# and never letting a bot act on something the player cannot see. A frame-1
	# dodge reads as a cheater; a bot that never whiffs is not beatable-feeling.
	{"hp": 0.7, "speed": 0.85, "cd_speed": 0.7, "dodge": false, "deflect": false, "evade_cd": 1.2, "react": 0.45, "p_miss": 0.45},  # Easy
	{"hp": 1.0, "speed": 1.0, "cd_speed": 1.0, "dodge": false, "deflect": false, "evade_cd": 1.0, "react": 0.35, "p_miss": 0.30},   # Normal
	{"hp": 1.6, "speed": 1.2, "cd_speed": 1.5, "dodge": true, "deflect": false, "evade_cd": 0.85, "react": 0.26, "p_miss": 0.16},   # Hard
	{"hp": 2.4, "speed": 1.5, "cd_speed": 2.1, "dodge": true, "deflect": true, "evade_cd": 0.5, "react": 0.15, "p_miss": 0.03},     # Impossible
]
const EVADE_DANGER_R: float = 155.0   # a hero bolt inside this triggers a dodge
const EVADE_DEFLECT_R: float = 58.0   # ...inside this (Impossible) it's deflected
var _cd_speed: float = 1.0            # attack-cooldown tick multiplier
var _smart_dodge: bool = false        # Hard+: hops away from incoming hero bolts
var _can_deflect: bool = false        # Impossible: point-blank deflect + counter
var _evade_reflex: float = 1.0        # cooldown between evades (difficulty reflex)
var _evade_cd: float = 0.0
## Mirrors Spell.SPEED. Spell.gd declares no class_name, so its const cannot be
## referenced from here; if that speed is ever retuned, this must follow or bots
## will lead their dodges wrongly.
const HERO_BOLT_SPEED: float = 460.0
## Brain time. Accumulated from the SCALED physics delta on purpose: hit-stop drops
## Engine.time_scale to 0.05, so a wall-clock reaction timer would hand every bot a
## ~20x reflex boost on each connect.
var _brain_clock: float = 0.0
var _reactions := BotDodge.Reactions.new()
var _react_delay: float = 0.35
var _p_miss: float = 0.30

@onready var rig: CharacterRig = $Rig

## Silhouette-shaped Area2D that makes the DRAWN figure solid to spells (see the
## HIT SILHOUETTE block up top). Built in _ready, resized whenever rig.height moves.
var _hurtbox: Area2D = null
var _hurtbox_height: float = -1.0  # rig height the current shapes were cut for


# --------------------------------------------------------------- hit silhouette
## Distance from world point `p` to this enemy's REAL silhouette: the spine as a
## segment from neck to hip, plus the head as a circle on top. Negative inside the
## head. This is deliberately the same shape and the same formula as
## SpikeFigure.body_distance() — the player figure and the enemies must agree on
## what a body is, because two different silhouette tests is precisely how "spells
## pass through heads" happened. Callers test `body_distance(p) <= hit_margin()`.
##
## Limbs are excluded on purpose (same reasoning as SpikeFigure): being clipped by
## a flailing arm you did not control feels arbitrary. Spine + head is the honest
## target. Scale-aware — a 1.9x sparring dummy reports 1.9x the reach, so no call
## site needs to know about node scale.
func body_distance(p: Vector2) -> float:
	var s: Dictionary = _silhouette()
	if s.is_empty():
		# No rig (headless stub / mid-teardown): fall back to the origin point so a
		# caller still gets a monotonic distance rather than INF-shaped nonsense.
		return global_position.distance_to(p)
	var spine_d: float = SpellGeometry.point_segment_distance(
		p, s["neck"] as Vector2, s["hip"] as Vector2
	)
	return minf(spine_d, p.distance_to(s["head"] as Vector2) - float(s["head_r"]))


## The forgiveness ring `body_distance` is meant to be compared against, in WORLD
## px (already multiplied by node scale). See HIT_MARGIN_FACTOR.
func hit_margin() -> float:
	var s: Dictionary = _silhouette()
	var h: float = float(rig.height) if is_instance_valid(rig) else RIG_FALLBACK_HEIGHT
	return h * HIT_MARGIN_FACTOR * float(s.get("scale", 1.0))


## World position of the drawn HEAD's centre. Sits well ABOVE global_position
## (which is mid-body): 9.9 px on a standard enemy, 18.9 px on a 1.9x dummy,
## 30.4 px on the Guardian. Anything that wants to aim at, mark, or centre an
## effect on an enemy's head wants this, not global_position.
func head_point() -> Vector2:
	var s: Dictionary = _silhouette()
	return (s["head"] as Vector2) if not s.is_empty() else global_position


## The world-space skeleton the two functions above share: neck / hip / head
## centre / head radius / uniform scale. Empty when there is no rig to measure.
func _silhouette() -> Dictionary:
	if not is_instance_valid(rig):
		return {}
	var h: float = float(rig.height)
	var head_r: float = h * RIG_HEAD_R_FACTOR
	var head_local := Vector2(0.0, -h * 0.5 + head_r)
	var xf: Transform2D = rig.global_transform
	# get_scale().y is the honest uniform scale: set_facing() mirrors only scale.x,
	# and a mirrored basis makes get_scale() report a NEGATIVE y — hence absf.
	var s: float = absf(xf.get_scale().y)
	return {
		"neck": xf * (head_local + Vector2(0.0, head_r)),
		"hip": xf * Vector2(0.0, h * RIG_HIP_Y_FACTOR),
		"head": xf * head_local,
		"head_r": head_r * s,
		"scale": s,
	}


## Build the silhouette hurtbox: a head CIRCLE plus a neck-to-feet BOX, sitting on
## the same physics layer spells already scan. It is a separate Area2D rather than
## a resize of the movement collider on purpose — growing the CharacterBody2D's
## own shape would move where the enemy stands on floors and where it bumps
## ceilings, which is a movement change nobody asked for. The movement collider
## stays on the layer too, so the two overlap and Spell.gd's ray backstop
## (collide_with_areas = false) still has a solid body to hit.
func _build_hurtbox() -> void:
	if _hurtbox != null and is_instance_valid(_hurtbox):
		return
	_hurtbox = Area2D.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = collision_layer if collision_layer != 0 else HURTBOX_FALLBACK_LAYER
	_hurtbox.collision_mask = 0    # it is detected, it never detects
	_hurtbox.monitoring = false    # ...so skip the overlap work entirely
	_hurtbox.monitorable = true
	# Shapes are built with .new() per instance: a shared sub-resource would have
	# every enemy in the arena resizing every other enemy's hurtbox.
	var head := CollisionShape2D.new()
	head.name = "HurtHead"
	head.shape = CircleShape2D.new()
	_hurtbox.add_child(head)
	var torso := CollisionShape2D.new()
	torso.name = "HurtBody"
	torso.shape = RectangleShape2D.new()
	_hurtbox.add_child(torso)
	add_child(_hurtbox)
	_sync_hurtbox()


## Cut the hurtbox shapes to the rig's CURRENT height. Public because anything
## that resizes a rig after spawn (Boss bumps it to 95 in its own _ready, and
## Encounter documents bumping guardian height after add_child) must be able to
## re-cut without knowing how the shapes are laid out.
func refresh_hurtbox() -> void:
	_sync_hurtbox()


## ⚠ WHY THERE IS NO RIG OFFSET HERE, AND WHY THE HURTBOX MUST NOT ASSUME ONE.
##
## The hub does offset its rig — Player.gd and NPC.gd both run
## `_rig.position.y = -_rig.height * 0.5`. Enemy (and Hero) deliberately do not, and
## copying that one line across would be a bug, not a fix. Two reasons, measured
## against the shipped scenes rather than eyeballed:
##
##   1. IT IS HALF OF A PAIR. Player.gd ALSO shifts its collider up by half its
##      height first, so the node origin ends up at the feet and the lifted rig lands
##      on it. Enemy.tscn's collider is centred on the origin. Lifting the rig alone
##      would leave enemies floating a full 15.5 px above the floor they stand on —
##      a much louder bug than the one being fixed.
##   2. THE COMBAT ARENA HAS ONE CONVENTION AND BOTH ACTORS FOLLOW IT. Measured:
##      Enemy draws its feet at y +15.5 with its collider bottom at +10 (sinks 5.5);
##      Hero draws its feet at +15.5 with its collider bottom at +9 (sinks 6.5). The
##      hero sinks MORE. Correcting the enemy alone would not un-sink the arena, it
##      would just make enemies hover relative to the player standing next to them.
##      Whether the arena should adopt the hub's feet-on-origin convention is a
##      combat-wide change (Hero.tscn/Hero.gd + Enemy.tscn + every spawner that
##      positions a body), not an Enemy-local one.
##
## So the silhouette below matches WHAT IS DRAWN, which is the property that has to
## hold: a bolt aimed at a head must hit the head the player can see. IF the arena
## ever does adopt the feet-on-origin convention, every `y` computed here must gain
## the same `rig.position.y` term — otherwise the hitbox stays where the art used to
## be, which is precisely the head-shaped dead zone this hurtbox was added to close.
func _sync_hurtbox() -> void:
	if _hurtbox == null or not is_instance_valid(_hurtbox) or not is_instance_valid(rig):
		return
	var h: float = float(rig.height)
	_hurtbox_height = h
	var head_r: float = h * RIG_HEAD_R_FACTOR
	var head_y: float = -h * 0.5 + head_r          # head TOP lands exactly at -h/2
	var neck_y: float = head_y + head_r
	var feet_y: float = h * RIG_HIP_Y_FACTOR + h * RIG_LEG_LEN_FACTOR
	var head_cs := _hurtbox.get_node_or_null("HurtHead") as CollisionShape2D
	var torso_cs := _hurtbox.get_node_or_null("HurtBody") as CollisionShape2D
	if head_cs != null and head_cs.shape is CircleShape2D:
		(head_cs.shape as CircleShape2D).radius = head_r
		head_cs.position = Vector2(0.0, head_y)
	if torso_cs != null and torso_cs.shape is RectangleShape2D:
		(torso_cs.shape as RectangleShape2D).size = Vector2(_hurtbox_width(h), feet_y - neck_y)
		torso_cs.position = Vector2(0.0, (neck_y + feet_y) * 0.5)


## Keep the hurtbox glued to the DRAWN body once the rig's floating-capsule springs
## start moving it (CharacterRig's ride + pitch — see its FLOATING-CAPSULE BODY block).
##
## `body_distance()` / `head_point()` above already follow for free, because they push
## analytic points through `rig.global_transform`. The hurtbox Area2D does NOT: it is
## a child of the Enemy, not of the rig, so without this it would stay bolt upright at
## the un-squashed height while the figure visibly buckles on landing or topples from a
## hit. That gap is the "spells pass through heads" bug in miniature — a hitbox left
## where the art used to be — so it is closed here rather than left as a rounding error.
##
## Two float writes a frame. The shapes themselves are untouched; only the frame they
## live in moves, so no hitbox is inflated by this.
func _sync_body_offset() -> void:
	if _hurtbox == null or not is_instance_valid(_hurtbox) or not is_instance_valid(rig):
		return
	_hurtbox.position.y = rig.body_ride()
	_hurtbox.rotation = rig.body_pitch()


## The hurtbox is exactly as WIDE as the movement collider already was. The fix is
## "an enemy is as tall as it is drawn", not "enemies are bigger now" — reusing
## the shipped width means no horizontal hitbox inflation sneaks in with it.
func _hurtbox_width(rig_height: float) -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		return (cs.shape as RectangleShape2D).size.x
	return rig_height * HURTBOX_WIDTH_FALLBACK_FACTOR


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


## Global knockback multiplier from the Tuning autoload. The fallback must MATCH
## TuningConfig.knockback_mult's exported default (1.6 -> 1.0 with the "knockback is
## too much" pass) or a headless/autoload-less context keeps the old launch feel.
func _knockback_mult() -> float:
	var t: Node = get_node_or_null(^"/root/Tuning")
	if t != null and t.get(&"cfg") != null:
		var v: Variant = t.cfg.get(&"knockback_mult")
		if v != null:
			return float(v)
	return 1.0


## SANDBOX Smash model: % gained per point of incoming damage, from the Tuning
## autoload (falls back to 0.8) — single shared source with Hero._tune so the two
## can't silently diverge on a retune (see TuningConfig.pct_per_damage).
func _pct_per_damage() -> float:
	var t: Node = get_node_or_null(^"/root/Tuning")
	if t != null and t.get(&"cfg") != null:
		var v: Variant = t.cfg.get(&"pct_per_damage")
		if v != null:
			return float(v)
	return 0.8


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
	# ...and on a FLAT floor (which is every floor of the tower) the same solver
	# becomes the gap-closing pounce. Rolled, not guaranteed, so a pack arrives
	# staggered rather than as a synchronised volley of jumping men.
	if _wants_pounce() and randf() < POUNCE_CHANCE:
		_start_pounce()
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


## Pure "should we POUNCE?" decision (floor check excluded, like _wants_leap, so
## headless tests can drive it): the right archetype, off cooldown, and the hero
## is far enough away on x that closing on foot would be a long boring jog — but
## not so far the arc stops reading. Deliberately does NOT require height: this is
## the flat-room half of the leap system.
func _wants_pounce() -> bool:
	if _leap_cd > 0.0 or not is_instance_valid(_hero):
		return false
	if not POUNCE_ARCHETYPES.has(archetype):
		return false
	# The teaching floor gets the chase, not the spring. See POUNCE_MIN_DEPTH.
	if floor_depth > 0 and floor_depth < POUNCE_MIN_DEPTH:
		return false
	var dx: float = absf(_hero.global_position.x - global_position.x)
	return dx > POUNCE_MIN_DIST and dx < POUNCE_MAX_DIST


## Commit to a gap-closing pounce. Same ballistic launch + LEAPING state as a
## ledge leap, on its own (longer) cooldown so it stays a punctuation mark.
func _start_pounce() -> void:
	_launch_leap(POUNCE_COOLDOWN)


## Commit to a leap: launch, enter LEAPING (owns movement until landing/timeout).
func _start_leap() -> void:
	_launch_leap(LEAP_COOLDOWN)


func _launch_leap(cooldown: float) -> void:
	_attack_state = AttackState.LEAPING
	_leap_timer = LEAP_MAX_AIR_TIME
	_leap_cd = cooldown
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
	_react_delay = float(cfg["react"])
	_p_miss = float(cfg["p_miss"])


## Hard+ reflex: if a hero bolt is closing in, DODGE (hop clear, reusing the leap
## arc) or — point-blank on Impossible — DEFLECT it (fizzle + counter-fire) while
## still advancing. Returns true only when a dodge took over movement this frame.
func _try_evade(delta: float) -> bool:
	_brain_clock += delta
	if _evade_cd > 0.0:
		return false
	var me: Vector2 = global_position
	var live: Array = []
	var nearest_bolt: Node2D = null
	var nearest_d: float = EVADE_DANGER_R
	var best: Dictionary = {}
	var best_tti: float = INF

	# Incoming bolts. Velocity comes free from the projectile's own facing + speed,
	# so this reads nothing a player couldn't see on screen.
	for s: Node in get_tree().get_nodes_in_group("player_spell"):
		if not s is Node2D or not is_instance_valid(s):
			continue
		var sp: Node2D = s as Node2D
		var id: int = sp.get_instance_id()
		live.append(id)
		var d: float = me.distance_to(sp.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest_bolt = sp
		_reactions.observe(id, _brain_clock, _react_delay, randf(), _p_miss)
		if not _reactions.visible(id, _brain_clock):
			continue
		var t: Dictionary = BotDodge.threat_from_projectile(
			me, sp.global_position, Vector2.from_angle(sp.rotation) * HERO_BOLT_SPEED)
		if bool(t["threatening"]) and float(t["tti"]) < best_tti:
			best_tti = float(t["tti"])
			best = t

	# Telegraphed ground danger — the hero's blast/meteor marks. Skip anything an
	# enemy planted: our own tells cannot hurt us, and dodging them looks insane.
	for node: Node in get_tree().get_nodes_in_group(Telegraph.GROUP):
		var tg := node as Telegraph
		if tg == null or not is_instance_valid(tg) or not tg.is_armed():
			continue
		if tg.source != null and tg.source.is_in_group("enemy"):
			continue
		var tid: int = tg.get_instance_id()
		live.append(tid)
		_reactions.observe(tid, _brain_clock, _react_delay, randf(), _p_miss)
		if not _reactions.visible(tid, _brain_clock):
			continue
		var shape: Dictionary = tg.danger_shape()
		var tt: Dictionary = {}
		if String(shape.get("shape", "")) == "line":
			var from: Vector2 = shape["from"]
			var to: Vector2 = shape["to"]
			tt = BotDodge.threat_from_lane(me, velocity, from, (to - from).angle(),
				from.distance_to(to), float(shape["width"]), tg.time_to_impact())
		else:
			tt = BotDodge.threat_from_circle(me, velocity, shape["center"],
				float(shape["radius"]), tg.time_to_impact())
		if bool(tt["threatening"]) and float(tt["tti"]) < best_tti:
			best_tti = float(tt["tti"])
			best = tt

	_reactions.forget_missing(live)

	# Point-blank deflect stays ahead of the dodge: swatting a bolt while still
	# walking at you is more menacing than hopping away from it.
	if _can_deflect and nearest_bolt != null and nearest_d < EVADE_DEFLECT_R:
		_evade_cd = _evade_reflex
		_deflect(nearest_bolt)
		return false

	if best.is_empty():
		return false
	var exit: Vector2 = best.get("exit", Vector2.ZERO)
	# Dead-centre in a blast has no shortest exit — break the tie toward open floor.
	if bool(best.get("degenerate", false)) or exit.length_squared() < 0.001:
		var open: float = signf(me.x - (_hero.global_position.x if is_instance_valid(_hero) else me.x - 1.0))
		exit = Vector2(open if open != 0.0 else 1.0, 0.0) * float(best.get("exit_len", 40.0))
	var choice: Dictionary = BotDodge.choose_response(best, {
		"grounded": is_on_floor(),          # this body has no dash, blink or parry
	})
	var dir: Vector2 = choice.get("dir", Vector2.ZERO)
	match String(choice.get("action", "none")):
		"jump":
			_evade_cd = _evade_reflex
			var away: float = signf(exit.x) if absf(exit.x) > 0.01 else signf(dir.x)
			velocity = Vector2(away * move_speed * 2.2, JUMP_VELOCITY * 0.8)
			_attack_state = AttackState.LEAPING
			_leap_timer = 0.45
			rig.flash()
			_apply_gravity(delta)
			move_and_slide()
			return true
		"walk":
			# Walking out of a marked circle is the new behaviour: the old evade only
			# knew how to hop away from a bolt, so ground AoE simply landed on it.
			_evade_cd = _evade_reflex * 0.5   # cheaper than a leap, so it can re-steer
			velocity.x = signf(exit.x) * move_speed * 1.35
			_apply_gravity(delta)
			move_and_slide()
			return true
	return false


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
	# FRIENDLY FIRE (1.5). `mortal` is the faction-BLIND group: every damageable
	# body joins it IN ADDITION to its faction group, and SpellCaster._stamp()
	# writes "mortal" as the target group when friendly fire is on. That makes a
	# spell hit everything alive with ZERO spectacle edits. `enemy` stays — a lot
	# of code (the clear gate, the camera framing, every bot scan) scans it.
	add_to_group(&"mortal")
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
	# Make the DRAWN figure solid to spells (head included). Deferred re-cut because
	# subclasses resize the rig AFTER super._ready() returns — Boss sets height 95 on
	# the next line of its own _ready, and a deferred call lands after that.
	_build_hurtbox()
	_sync_hurtbox.call_deferred()
	_setup_enemy_net()


func _physics_process(delta: float) -> void:
	# A rig can be resized long after _ready (class presets, guardian scaling). One
	# float compare a frame keeps the hurtbox honest without anyone remembering to
	# call refresh_hurtbox(). Sits ABOVE the co-op puppet early-out on purpose: a
	# client-side puppet is still shot at locally, so its silhouette must be right.
	if is_instance_valid(rig) and not is_equal_approx(_hurtbox_height, rig.height):
		_sync_hurtbox()
	_sync_body_offset()
	# Groundedness for the rig's floating-capsule body: an enemy that is launched,
	# leaps or is knocked off a ledge now gets the same takeoff stretch and weighted
	# landing squash the hero does, instead of touching down like a decal.
	#
	# The `velocity.y` guard is deliberate and load-bearing: several enemy states
	# (passive sparring dummies, frozen/stunned, the co-op puppet path) return before
	# ever calling move_and_slide, so `is_on_floor()` is stale-false for them. A body
	# with no vertical motion is standing on something by definition — that reading
	# keeps every non-moving enemy planted rather than silently switching its gait off.
	if is_instance_valid(rig):
		rig.set_grounded(is_on_floor() or absf(velocity.y) < 1.0)
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


## RECOVER: the brief post-strike stagger — but WALKING BACK IN, not rooted.
## Rooting here was the single largest source of dead time in the roster: with a
## 1.4s cooldown on top, a brute spent most of a fight standing still looking at
## you. It now closes at RECOVER_DRIVE of its speed, so the stagger still reads
## (it is slower than a chase) while the pressure never lets up.
## Kiters (caster / mage / summoner) recover BACKWARDS — retreating out of reach
## is their whole grammar, and shoving them forward would delete the archetype.
func _process_recover(delta: float) -> void:
	var drive: float = 0.0
	if is_instance_valid(_hero):
		var dir_x: float = signf(_hero.global_position.x - global_position.x)
		if _is_kiter():
			dir_x = -dir_x
		drive = dir_x * move_speed * _speed_scale * RECOVER_DRIVE
	velocity.x = drive + _knockback.x
	_apply_gravity(delta)
	move_and_slide()
	rig.play(CharacterRig.State.RUN if absf(drive) > 1.0 else CharacterRig.State.IDLE)
	if is_instance_valid(_hero):
		rig.set_facing(_hero.global_position - global_position)
	_recover_timer -= delta
	if _recover_timer <= 0.0:
		_attack_state = AttackState.CHASE


## The back-line archetypes: they hold a range band instead of closing.
func _is_kiter() -> bool:
	return archetype == Archetype.CASTER or archetype == Archetype.MAGE \
			or archetype == Archetype.SUMMONER


## In-band drift for a kiter that has nothing to do this frame. Returns a signed
## fraction of move_speed, reversing every KITE_STRAFE_PERIOD seconds so the
## backline circles for an angle instead of standing at parade rest.
func _kite_strafe(delta: float) -> float:
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = KITE_STRAFE_PERIOD
		_strafe_sign = -_strafe_sign
	return _strafe_sign * KITE_STRAFE_DRIVE


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
	# `no_resolve`: the caller resolves the attack itself off Telegraph.fired
	# instead of going through _on_telegraph_fired's ARCHETYPE switch. The Boss
	# needs this — it is an Enemy subclass with archetype BRUTE, so the default
	# wiring would answer its beam tell with a brute ground strike.
	var no_resolve: bool = bool(cfg.get("no_resolve", false))
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
	if not no_resolve:
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
	else:
		move_x = _kite_strafe(delta)              # in-band: circle, never freeze
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
	# WHOSE BOLT THIS IS. Set BEFORE add_child so it is true for the whole of the
	# projectile's life, including its first frame. A spectacle built without a
	# caster reports as "unowned" to the reaction layer, which satisfies neither
	# `require_owner: "same"` nor `"different"` — so it matches NO clash row and is
	# silently inert there, with nothing logged to say so. Bolts are not registered
	# reactants yet; this is what makes them attributable the moment they are.
	proj.caster_node = self
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
	else:
		move_x = _kite_strafe(delta)              # in-band: circle, never freeze
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
	# Caster identity — same reasoning as _spawn_enemy_bolt above. `set()` is a
	# silent no-op while BlastSpell has no `caster_node` field, so this is safe now
	# and becomes live the day it grows one.
	blast.set("caster_node", self)
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
	else:
		move_x = _kite_strafe(delta)              # in-band: circle, never freeze
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
	# TWO caps, and the second one is the point of 1.4: the summoner's own
	# SUMMON_MAX_ALIVE (no infinite swarm from one caster) AND the floor's live
	# entity budget, which the Encounter owns and this node must ASK about.
	# Before 1.4 minions bypassed the encounter cap entirely.
	var to_spawn: int = mini(SUMMON_COUNT, maxi(SUMMON_MAX_ALIVE - _live_minion_count(), 0))
	to_spawn = mini(to_spawn, _spawn_headroom())
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


## THE FLOOR'S LIVE-ENTITY BUDGET, asked of the Encounter through the Arena.
## Returns a huge number outside a floor (F6 sandbox, headless helper tests) so
## those paths behave exactly as they did before the cap existed.
func _spawn_headroom() -> int:
	var parent: Node = get_parent()
	if parent == null or not parent.has_method("encounter"):
		return 0x7FFFFFFF
	var enc: Node = parent.call("encounter")
	if enc == null or not enc.has_method("spawn_headroom"):
		return 0x7FFFFFFF
	return int(enc.call("spawn_headroom"))


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
	# Ring-out is the SOLE elimination path in the sandbox (see _is_ringout_mode
	# throughout this file): a bomber's own detonation must not self-remove it via
	# _die()/queue_free(), even though the AoE damage/knockback above is unchanged.
	# BOMBER is currently excluded from VersusArena.BOT_ARCHETYPES, so this branch
	# is dormant today; if BOMBER is ever added to the sandbox roster, revisit
	# whether a ring-out-surviving bomber should recover into CHASE/RECOVER here.
	if not _is_ringout_mode():
		_die()


## Strike resolution, split out so headless tests can drive it directly:
## hero still inside the circle -> heavy damage + lunge + juice; else a miss.
## Either way the brute enters RECOVER and the cooldown runs from the strike.
func _resolve_strike(center: Vector2) -> void:
	# CLASH: this swing may have met the hero's head-on. Enemies declare here rather
	# than at their windup because their attack is already committed by this point —
	# and declaring gets bots, co-op partners and sparring dummies into the clash
	# layer with no bespoke AI code, since nothing scans the world for candidates:
	# only DECLARED swings can clash.
	if MeleeClash.declare_and_spend(self, (center - global_position).normalized(),
			ATTACK_RADIUS, ATTACK_DAMAGE):
		_attack_state = AttackState.RECOVER
		_recover_timer = ATTACK_RECOVER_TIME
		_attack_cooldown = ATTACK_COOLDOWN
		return
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
		damage_pct += float(dealt) * _pct_per_damage()
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
	_notify_hype_kill()
	_spawn_death_burst()
	_spawn_corpse()
	Sfx.play("enemy_death")
	Juice.shake_camera(DEATH_SHAKE)
	# A KILL is punctuation — but the localized ring, never a full-screen flash.
	# A wave fight kills a dozen things in a few seconds and full-screen marks on
	# each would be exactly the strobe the arbiter exists to prevent; the ring is
	# small, low-contrast and cheap to see often, which is precisely the shelf the
	# QUICK rung of the ladder is for. Fired with its own camera/freeze cluster
	# suppressed because the two lines above already fired those, tuned.
	Juice.tier_frame(SpellTier.Tier.QUICK, global_position, -1,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
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
	# ...and the silhouette hurtbox with it, or a "knocked out" dummy would still
	# eat bolts through its (invisible) head for the whole respawn delay.
	if is_instance_valid(_hurtbox):
		_hurtbox.set_deferred("monitorable", false)
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
	if is_instance_valid(_hurtbox):
		_hurtbox.set_deferred("monitorable", true)
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


## Feed the MOMENT-TO-MOMENT reward loop: kill chains, multi-kills, the shout.
## Found by GROUP, not by autoload — Hype is built per-arena so a streak can never
## survive a scene change, and a scene with no Hype (the spike playgrounds, every
## headless suite) simply gets nothing.
func _notify_hype_kill() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var h: Node = tree.get_first_node_in_group(&"hype")
	if h != null and h.has_method("notify_kill"):
		h.call("notify_kill", global_position, tint)


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


## Elemental ailments land on the victim's authority too, for the same reason damage
## does: `StatusComponent` ticks its own DoT through `take_damage`, so applying a
## burn on a client-side puppet would run a whole second damage-over-time on the
## wrong peer. Routed by `Net.deal_status`.
@rpc("any_peer", "call_remote", "reliable")
func _net_apply_status(element: int, can_chain: bool = true) -> void:
	apply_status(element, can_chain)


## Co-op: stand up a MultiplayerSynchronizer that streams this enemy's transform +
## hp from the host (authority) to every client. Built in code (no .tscn surgery),
## mirroring Hero._setup_net_sync. No-op in SP.
##
## The two rates are duplicated from `Hero` rather than imported because `Hero.gd`
## declares no `class_name` (it is instanced from a .tscn), and reaching it by
## `load()` from a hot path to read two floats would be worse than restating them.
## They must stay in step — see the comment in `_setup_enemy_net`.
const NET_TRANSFORM_HZ: float = 30.0
const NET_STATE_HZ: float = 10.0


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
	# BANDWIDTH. A floor can hold 25 of these; at the physics rate that is 1500
	# transform packets a second on phone wifi, for motion nobody can resolve at
	# that granularity. 30 Hz halves it. Same number as the hero's, deliberately —
	# an enemy that updated on a different clock to the hero chasing it would read
	# as stuttering relative to them even though both were smooth in isolation.
	sync.replication_interval = 1.0 / NET_TRANSFORM_HZ
	sync.delta_interval = 1.0 / NET_STATE_HZ
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
