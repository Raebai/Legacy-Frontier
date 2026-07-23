extends CharacterBody2D
## Slice 0 combat protagonist (the mage). Move now; dash + cast added next.

signal health_changed(current: int, maximum: int)
signal mana_changed(current: float, maximum: int)
signal signature_changed(display_name: String)

const SPEED: float = 210.0
## Mana (MP): gates the big SIGNATURE spectacle spells (the magic-circle beam /
## divine ray). Regenerates over time so ultimates are a paced resource, not
## spammable. Costs + cooldowns live per-spell on the SpellDef.
const MP_REGEN: float = 20.0  # mp/sec
const DASH_SPEED: float = 620.0
const DASH_TIME: float = 0.14
const DASH_COOLDOWN: float = 0.9  # was 0.55 — chained diagonal dashes let you "fly"
## Side-on platformer physics (Stick-Fight feel): asymmetric gravity (floaty
## apex, weighty landing), snappy accel + friction, WALL-SLIDE + WALL-JUMP so you
## can cling to and scale walls. Movement is horizontal (A/D); jump; dash.
const GRAVITY: float = 1500.0          # rise gravity (floaty apex)
const GRAVITY_FALL: float = 2100.0     # heavier coming down (weighty landing)
const MAX_FALL: float = 1000.0
const JUMP_VELOCITY: float = -580.0  # slightly higher jump (maker feedback)
const DOUBLE_JUMP_VELOCITY: float = -470.0
const MAX_AIR_JUMPS: int = 0  # no mid-air double-jump — wall-jump is the air move
const COYOTE_TIME: float = 0.10      # jump slightly after leaving a ledge
const JUMP_BUFFER_TIME: float = 0.10 # jump queued slightly before landing
const GROUND_ACCEL: float = 2600.0
const GROUND_FRICTION: float = 2900.0  # crisp stop with a hint of slide
const AIR_ACCEL: float = 1450.0        # strong air control (Stick-Fight)
## Wall-slide + wall-jump (the Stick-Fight wall tech): grip a wall while falling
## into it (clamped slide speed), then kick off away+up; a slide-then-jump boosts.
const WALL_SLIDE_MAX_FALL: float = 150.0
const WALL_STICK_PUSH: float = 6.0     # tiny into-wall x so is_on_wall stays true
const WALL_JUMP_PUSH: float = 300.0    # launch away from the wall (> SPEED)
const WALL_JUMP_UP: float = -460.0     # up kick — a diagonal arc, not a rocket
const WALL_JUMP_LOCKOUT: float = 0.15  # brief horizontal-input lock after the kick
const SLIDE_JUMP_BOOST: float = 1.25   # extra push jumping straight out of a slide
const CAST_COOLDOWN: float = 0.35
const MELEE_COOLDOWN: float = 0.34
const MELEE_DAMAGE: int = 14
const MELEE_RANGE: float = 58.0  # was 46 — short fists whiffed (Brawler LMB "not working")
const MELEE_ARC_DOT: float = 0.3
## Bumped for the Stick-Fight "shove" read — a connected punch should visibly
## launch the target, not just tick it.
const MELEE_KNOCKBACK: float = 300.0
## Ragdoll shove the hero RECEIVES (bomb blast / reflected bolt / slam) — decays
## like the enemy channel so a hit displaces you, then you regain control.
const KNOCKBACK_DECAY: float = 900.0
## Melee tuning per weapon kind; the MELEE_* consts are the "fists" baseline.
const WEAPON_STATS: Dictionary = {
	"fists": {"damage": MELEE_DAMAGE, "range": MELEE_RANGE, "knockback": MELEE_KNOCKBACK},
	"sword": {"damage": 26, "range": 60.0, "knockback": 400.0},
}
## After a fire-element melee the lead fist stays LIT for this long, the flame
## trailing embers as the hand moves (item 3). Strength decays with the timer.
const FLAMING_FIST_TIME: float = 1.6
const BLAST_COOLDOWN: float = 2.0
const BLAST_FALLBACK_RANGE: float = 200.0
## Meteor is player-placed at the cursor, clamped to this reach (skill-shot, not
## a cross-stage snipe).
const BLAST_MAX_RANGE: float = 480.0
## Blink teleport: instant reposition along facing with a shadow-poof at both
## the origin and the destination (the "yin-yang shadow step").
const BLINK_DISTANCE: float = 175.0
## Blink lands you THROUGH walls but never INSIDE one: probe the endpoint against
## solids (layer 1) and relocate to the nearest clear spot if it's blocked.
const BLINK_WALL_MASK: int = 1
const BLINK_PROBE_STEP: float = 6.0
const BLINK_PROBE_EXTRA: float = 60.0
const BLINK_COOLDOWN: float = 1.3
const BLINK_IFRAME: float = 0.22
## You may never blink OUT of the map — a landing spot inside a ring-out PIT (or
## within this margin of one) is rejected and pulled back toward the origin (maker:
## "you shouldn't be able to teleport out of the map ... limit it to where you
## actually can teleport"). Landing inside a solid is already rejected separately.
const BLINK_PIT_MARGIN: float = 22.0
const BLINK_SHADOW_COLOR: Color = Color(0.25, 0.1, 0.35, 0.8)
## Dark-violet particle poof; end alpha 0 so it dissolves instead of popping.
const BLINK_BURST_START: Color = Color(0.4, 0.18, 0.55, 0.9)
const BLINK_BURST_END: Color = Color(0.08, 0.03, 0.15, 0.0)
## Quick bright flash on arrival so the eye snaps to the new position.
const BLINK_ARRIVAL_FLASH_COLOR: Color = Color(0.85, 0.7, 1.0)
const BLINK_ARRIVAL_FLASH_TIME: float = 0.1
## Energy nova: self-centered instant shockwave — the "get off me" button.
## Bumped 3->5s: at 3s it was spammable enough to be oppressive.
const NOVA_COOLDOWN: float = 5.0
## Perfect-timing parry (rogue only): a short ACTIVE window that REVERSES an
## incoming enemy bolt back at the enemy side. Miss the window and you eat it.
const PARRY_WINDOW: float = 0.16
const PARRY_COOLDOWN: float = 0.9
const PARRY_FLASH_COLOR: Color = Color(0.8, 1.0, 1.0)
## The directional block SHELL lingers a touch longer than the active window so
## the deflect reads (the arc is the whole tell — no omni flash).
const PARRY_SHIELD_TIME: float = 0.26
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
## Aura COLOUR comes from the active element (see _apply_element); only the
## strength is fixed here.
const AURA_STRENGTH: float = 0.6  # re-enabled: the HDR bloom pass now carries the
# glow as a soft halo instead of a flat sprite that obscured the figure.
## Body colourways (limb palette). Independent of the element — you can be a
## Jade stickman casting Fire. Cycled with `cycle_colourway` (C).
const COLOURWAYS: Array[Color] = [
	Color(0.4, 0.7, 1.0),  # Azure (the original hero blue)
	Color(1.0, 0.55, 0.35),  # Ember
	Color(0.6, 0.4, 0.95),  # Void
	Color(0.45, 0.9, 0.55),  # Jade
	Color(0.85, 0.85, 0.9),  # Mono
]
const SPELL_SCENE: PackedScene = preload("res://scenes/combat/Spell.tscn")
const BLAST_SCENE: PackedScene = preload("res://scenes/combat/BlastSpell.tscn")
const NOVA_SCENE: PackedScene = preload("res://scenes/combat/EnergyNova.tscn")

## EIGHT playable classes over ONE mobile-first slot system (see
## docs/superpowers/specs/2026-07-13-eight-class-roster-and-abilities.md). Each
## configures the SAME 7 slots with its own flavour — element, weapon, AoE
## variant, signature loadout — so touch controls never change but each class
## FEELS distinct. Enum names MAGE/ROGUE keep indices 0/1 (Arcanist/Shadowblade
## display names) so existing saves + tests stay valid; the mage config still
## equals the old consts, so index 0 is byte-identical to before.
##
## AoE (Q) variants: "blast" (placed meteor), "nova" (self whirlwind),
## "fist_shock" (fire-punch shockwave), "ground_slam" (earth crater). `element`
## is the class's default element (auto-set on switch; X still cycles). Signature
## loadout comes from SpellLibrary.build_for_class(class_id).
enum HeroClass { MAGE, ROGUE, BRAWLER, JUGGERNAUT, CLERIC, CRYOMANCER, STORMCALLER, WARLOCK }
const CLASS_NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut",
	"Cleric", "Cryomancer", "Stormcaller", "Warlock",
]
const CLASS_CONFIG: Dictionary = {
	HeroClass.MAGE: {  # ARCANIST — ranged arcane zoner (byte-identical to the old mage)
		"preset": "mage", "weapon": "", "element": Elements.Element.ARCANE, "melee_element": -1,
		"cast_cd": CAST_COOLDOWN, "dash_cd": DASH_COOLDOWN, "blink_cd": BLINK_COOLDOWN,
		"blast_cd": BLAST_COOLDOWN,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "arcane_meteor", "has_nova": true, "can_parry": true,  # Q: arcane star-fall
	},
	HeroClass.ROGUE: {  # SHADOWBLADE — twitchy assassin; LMB = 3-dagger flurry
		"preset": "rogue", "weapon": "sword", "element": Elements.Element.SHADOW, "melee_element": Elements.Element.SHADOW,
		"primary": "bolt", "bolt_burst": 3, "bolt_spread": 0.13,
		"cast_cd": 0.30, "dash_cd": 0.70, "blink_cd": 1.0,
		"blast_cd": 2.5,
		"throw_blade": true, "blade_damage": 9,
		"dash_strike": true, "dash_strike_damage": 16, "dash_strike_range": 42.0,
		"aoe": "nova", "has_nova": false, "can_parry": true,
	},
	HeroClass.BRAWLER: {  # PURE MELEE, no magic — punch/kick combo + double-jump + Chidori
		"preset": "brawler", "weapon": "", "element": Elements.Element.FIRE, "melee_element": Elements.Element.FIRE,
		"primary": "melee_combo", "air_jumps": 1, "melee_cd": 0.20, "melee_knockback": 320.0,
		"cast_cd": 0.22, "dash_cd": 0.70, "blink_cd": 1.1, "blast_cd": 2.2,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": true, "dash_strike_damage": 20, "dash_strike_range": 44.0,
		"mobility2": "uppercut", "aoe": "fist_shock", "has_nova": true, "can_parry": true,
	},
	HeroClass.JUGGERNAUT: {  # slow siege tank — wide heavy hammer, BLOCK, no blink
		"preset": "juggernaut", "weapon": "sword", "element": Elements.Element.EARTH, "melee_element": Elements.Element.EARTH,
		"primary": "heavy_swing", "melee_cd": 0.55, "melee_arc_dot": 0.0, "melee_damage": 30, "melee_range": 96.0, "melee_knockback": 470.0,
		"cast_cd": 0.40, "dash_cd": 0.90, "blink_cd": 1.4, "blast_cd": 2.6,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": true, "dash_strike_damage": 22, "dash_strike_range": 48.0,
		"defense": "block", "aoe": "ground_slam", "has_nova": true, "can_parry": true,
	},
	HeroClass.CLERIC: {  # radiant sustain bruiser — LMB heal-bolt (lifesteal)
		"preset": "cleric", "weapon": "staff", "element": Elements.Element.HOLY, "melee_element": Elements.Element.HOLY,
		"primary": "bolt", "bolt_heal": 4,
		"cast_cd": 0.32, "dash_cd": 0.85, "blink_cd": 1.2, "blast_cd": 2.4,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "consecrate", "has_nova": true, "can_parry": true,  # Q: consecrated ground
	},
	HeroClass.CRYOMANCER: {  # ice control — LMB is a FROST CONE, not a bolt
		"preset": "cryomancer", "weapon": "staff", "element": Elements.Element.ICE, "melee_element": Elements.Element.ICE,
		"primary": "frost_cone",
		"cast_cd": 0.34, "dash_cd": 0.90, "blink_cd": 1.2, "blast_cd": 2.6,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "ice_shards", "has_nova": true, "can_parry": true,  # Q: homing frost shards
	},
	HeroClass.STORMCALLER: {  # hyper-mobile chain caster — LMB arcs, fast wind-dash
		"preset": "stormcaller", "weapon": "staff", "element": Elements.Element.LIGHTNING, "melee_element": Elements.Element.LIGHTNING,
		"primary": "bolt", "bolt_chain": 2,
		"cast_cd": 0.30, "dash_cd": 0.55, "blink_cd": 1.0, "blast_cd": 2.4,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "call_lightning", "has_nova": true, "can_parry": true,  # Q: lightning strike column
	},
	HeroClass.WARLOCK: {  # dark attrition hexer — LMB drain-bolt (weaken + lifesteal)
		"preset": "warlock", "weapon": "sword", "element": Elements.Element.SHADOW, "melee_element": Elements.Element.SHADOW,
		"primary": "bolt", "bolt_heal": 3,
		"cast_cd": 0.30, "dash_cd": 0.85, "blink_cd": 1.1, "blast_cd": 2.5,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "curse_chain", "has_nova": true, "can_parry": true,  # Q: leaping shadow chain
	},
}

@export var max_hp: int = 100
var hp: int = 100
@export var max_mp: int = 100
var mp: float = 100.0
## Equipped SIGNATURE loadout (SpellLibrary) — the spell tree the player cycles
## (V) and unleashes (Ultimate key), MP-gated with a per-spell cooldown.
var _signatures: Array = []
var _signature_index: int = 0
var _signature_cd_timer: float = 0.0
## Twin-stick: `facing`/`_aim_dir` track the CURSOR (drive casts, melee arc, cast
## pose, camera peek); `_move_dir` tracks WASD (drives dash + blink dodge). They
## are decoupled so you can run one way while aiming/casting another (strafe).
var facing: Vector2 = Vector2.RIGHT

## Co-op: the class comes from the lobby (net_class >= 0), not GameState. `_net`
## caches /root/Net so the per-frame authority check is cheap. Singleplayer leaves
## net_class at -1 and _net.is_active() false, so nothing below changes SP.
var net_class: int = -1
var _net: Node = null
var _aim_dir: Vector2 = Vector2.RIGHT
var _move_dir: Vector2 = Vector2.RIGHT
var _footstep_timer: float = 0.0
var is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _ghost_timer: float = 0.0
var _cast_cooldown_timer: float = 0.0
var _melee_cooldown_timer: float = 0.0
var _melee_kick_next: bool = false
var _flaming_fist_timer: float = 0.0
var _fist_ember_timer: float = 0.0
var _last_hand_pos: Vector2 = Vector2.ZERO
var _blast_cooldown_timer: float = 0.0
var _blink_cooldown_timer: float = 0.0
var _blink_iframe_timer: float = 0.0
var _nova_cooldown_timer: float = 0.0
var _parry_window_timer: float = 0.0
var _parry_cooldown_timer: float = 0.0
var _parry_window_len: float = PARRY_WINDOW  # per-class (Juggernaut BLOCK = longer window)
var _wall_jump_lock: float = 0.0   # horizontal-input lock after a wall-kick
var _was_wall_sliding: bool = false
var _wall_dust_timer: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _air_jumps: int = 0
var _max_air_jumps: int = 0  # per-class air jumps (Brawler double-jumps); set in configure_class
var _was_on_floor: bool = true  # for the landing-dust transition edge
var _weapon: String = "fists"
var _melee_damage: int = MELEE_DAMAGE
var _melee_range: float = MELEE_RANGE
var _melee_knockback: float = MELEE_KNOCKBACK
var _melee_cd: float = MELEE_COOLDOWN     # per-class swing cadence (Brawler fast, Juggernaut slow)
var _melee_arc_dot: float = MELEE_ARC_DOT # per-class arc width (Juggernaut swings wide)
var _buffered_action: String = ""
var _buffer_timer: float = 0.0
var _knockback: Vector2 = Vector2.ZERO  # shove received from an enemy hit / bomb
var _ragdolling: bool = false  # hold DOWN -> go limp + flop (the Stick-Fight ragdoll toy)
var _hero_class: int = HeroClass.MAGE
var _cfg: Dictionary = CLASS_CONFIG[HeroClass.MAGE]
var _dash_hit: Array = []  # enemies/props already struck this dash (rogue no-multi-hit)
## Active element (aura + ability colour). Cycled with `cycle_element` (X).
var _element: int = Elements.Element.ARCANE
var _element_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## GEAR EFFECTS (GearAbilities): aggregated from the equipped weapon/head/body and
## applied at single clean hooks — an elemental weapon overrides `_element`, melee
## mults rescale the melee profile, the hat rescales max HP, the hood rescales move
## speed, the robe wards the first hit each fight. Recomputed idempotently from the
## class BASE in _recompute_gear_effects (safe to re-run on a loadout swap).
const BASE_MAX_HP: int = 100
const GEAR_ELEMENT: Dictionary = {
	"arcane": Elements.Element.ARCANE, "ice": Elements.Element.ICE,
	"lightning": Elements.Element.LIGHTNING, "holy": Elements.Element.HOLY,
	"shadow": Elements.Element.SHADOW, "fire": Elements.Element.FIRE,
	"earth": Elements.Element.EARTH,
}
var _gear_speed_mult: float = 1.0
var _gear_ward_frac: float = 0.0
var _gear_ward_used: bool = false
var _gear_damage_reduction: float = 0.0  # armor: flat % off every hit (persistent)
## Class melee/HP base snapshot (captured post-class-setup incl. equip_weapon) that
## the gear mults scale FROM — so _recompute is idempotent and never clobbers the
## weapon-specific melee tuning equip_weapon already applied.
var _base_melee_damage: int = MELEE_DAMAGE
var _base_melee_knockback: float = MELEE_KNOCKBACK
var _base_melee_cd: float = MELEE_COOLDOWN
var _base_max_hp: int = BASE_MAX_HP
var _base_element: int = Elements.Element.ARCANE  # class innate element (revert target)
## The player's LOADOUT choices (from the hub Armory). Only these override the class
## and grant gear abilities — class-default gear stays cosmetic + as-tuned, so a class
## you never re-geared plays exactly as balanced. slot -> kind.
var _gear_override: Dictionary = {}
var _colourway: int = 0
## Mobile: set by TouchControls when the on-screen pad is active (or true on any
## touchscreen). Switches aim from the cursor to auto-target the nearest enemy so
## every ability works by tapping a button — no pixel-precise aiming (mobile-first).
var touch_input: bool = false

## Co-op: a died hero is DOWNED (ragdoll, no input, damage-immune) instead of
## instantly reviving — enemies ignore it and the party stays in the fight. When
## EVERY hero is downed the host drops the party a floor (revives all). Synced so
## the host + peers can read each hero's state. SP never sets this (Hero._die keeps
## the old fall/reset). Public for the MultiplayerSynchronizer property path.
var downed: bool = false

@onready var rig: CharacterRig = $Rig
var _tuning: Node = null  # cached /root/Tuning (null in headless tests -> fallbacks)


## Live-tunable feel value: reads res://data/tuning.tres via the Tuning autoload,
## falling back to the const default if the autoload/field is absent or unset.
func _tune(key: String, fallback: float) -> float:
	if _tuning != null and _tuning.cfg != null:
		var v: Variant = _tuning.cfg.get(key)
		if v != null:
			return float(v)
	return fallback


func _ready() -> void:
	add_to_group("hero")
	_tuning = get_node_or_null("/root/Tuning")
	hp = max_hp
	health_changed.emit(hp, max_hp)
	rig.set_tint(COLOURWAYS[_colourway])
	rig.set_aim_arm(true)  # twin-stick: the lead hand always aims at the cursor
	# Class comes from the co-op lobby (net_class) first, else GameState, else MAGE.
	_net = get_node_or_null("/root/Net")
	var gs: Node = get_node_or_null("/root/GameState")
	var start_class: int = HeroClass.MAGE
	if net_class >= 0:
		start_class = net_class
	elif gs != null:
		var sc: Variant = gs.get("selected_class")
		if sc != null:
			start_class = int(sc)
	# configure_class sets the class element, rig preset, weapon, AND the class's
	# signature loadout (SpellLibrary.build_for_class) + emits signature_changed.
	configure_class(start_class)  # also applies the hub Armory loadout (GameState.loadout)
	_setup_net_role()
	mp = float(max_mp)
	mana_changed.emit(mp, max_mp)
	# Rank drives aura TIER (elaborateness); the element keeps driving COLOUR.
	Rank.rank_changed.connect(_on_rank_changed)
	rig.set_aura_tier(Rank.tier())
	rig.hit_frame.connect(_on_melee_hit_frame)
	# Floating HP + MP bars over the head.
	var bars := CharacterBars.new()
	add_child(bars)
	bars.configure(self, true, -26.0)


## Float-channel: the 4 big spectacles (beam/ray/meteor/convergence) become a
## committed levitating cast. Press G -> the hero lifts off + a build-up sigil
## grows for cast_time; if a hit lands the channel is INTERRUPTED (cast lost, mana
## + cooldown already spent). Survive it and the ultimate unleashes.
const CHANNEL_LIFT_HEIGHT: float = 34.0
const CHANNEL_LIFT_SPEED: float = 180.0
var _channeling: bool = false
var _channel_timer: float = 0.0
var _channel_total: float = 0.0
var _channel_spell: SpellDef = null
var _channel_target: Vector2 = Vector2.ZERO
var _channel_sky: bool = false
var _channel_lift: float = 0.0
var _channel_base_y: float = 0.0
var _channel_circle: Node2D = null

## Epic SUMMON windup: every INSTANT signature (ice_wall / chain / rune_orbs /
## flurry / void_zone / tether / boulder / pillar / wall / rush / blink) now blooms
## a grounded spell-circle + committed cast pose + gather motes for a short beat,
## THEN ERUPTS (maker: "ice is cringe — no spell circle, no summoning animation;
## they ALL need that for the G's ESPECIALLY"). Lighter than the channel: grounded
## (no levitation), shorter, and mobility bursts (rush/blink) get a faster windup so
## they stay snappy. Interruptible by a hit (ult lost, MP/cd spent — like the channel).
const SUMMON_WINDUP: float = 0.42       # planted / erupting signatures
const SUMMON_WINDUP_FAST: float = 0.22  # rush / blink — keep the mobility snappy
const SUMMON_NORMAL: int = 0
const SUMMON_RUSH: int = 1
const SUMMON_BLINK: int = 2
var _summoning: bool = false
var _summon_timer: float = 0.0
var _summon_total: float = 0.0
var _summon_spell: SpellDef = null
var _summon_sky: bool = false
var _summon_special: int = 0
var _summon_aim: Vector2 = Vector2.RIGHT
var _summon_target: Vector2 = Vector2.ZERO
var _summon_circle: Node2D = null


## True when aim should auto-target (mobile): the TouchControls pad is active, or the
## device is a touchscreen. Cached DisplayServer call is cheap.
func _touch_aim() -> bool:
	return touch_input or DisplayServer.is_touchscreen_available()


func _physics_process(delta: float) -> void:
	# Co-op: you only drive YOUR hero. Remote heroes follow the synchronizer and
	# just animate (no Input, no move_and_slide).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		_remote_visual(delta)
		return
	# Co-op: downed = a limp ragdoll on the ground, no input/abilities, until the party
	# falls or clears the floor and everyone revives.
	if downed:
		_process_downed(delta)
		return
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)
	_cast_cooldown_timer = max(_cast_cooldown_timer - delta, 0.0)
	_melee_cooldown_timer = max(_melee_cooldown_timer - delta, 0.0)
	_blast_cooldown_timer = max(_blast_cooldown_timer - delta, 0.0)
	_blink_cooldown_timer = maxf(_blink_cooldown_timer - delta, 0.0)
	_blink_iframe_timer = maxf(_blink_iframe_timer - delta, 0.0)
	_nova_cooldown_timer = maxf(_nova_cooldown_timer - delta, 0.0)
	_parry_window_timer = maxf(_parry_window_timer - delta, 0.0)
	_parry_cooldown_timer = maxf(_parry_cooldown_timer - delta, 0.0)
	_signature_cd_timer = maxf(_signature_cd_timer - delta, 0.0)
	_wall_jump_lock = maxf(_wall_jump_lock - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_update_flaming_fist(delta)
	# Mana regenerates every frame (even mid-dash) so ultimates stay paced.
	if mp < float(max_mp):
		mp = minf(mp + MP_REGEN * delta, float(max_mp))
		mana_changed.emit(mp, max_mp)
	# FLOAT-CHANNEL: while casting a big spectacle the hero levitates + is fully
	# committed (no movement/input) until the cast fires or a hit interrupts it.
	if _channeling:
		_process_channel(delta)
		return
	# SUMMON WINDUP: while the spell circle blooms the hero is committed (grounded,
	# no movement/input) until it erupts or a hit interrupts it.
	if _summoning:
		_process_summon(delta)
		return
	# Landing dust: white puff the instant we touch down after being airborne (not
	# while gliding). At the top so it fires even on dash frames. is_on_floor()
	# here reflects the previous frame's move_and_slide.
	if is_on_floor() and not _was_on_floor:
		_spawn_foot_puff()
		Juice.shake_camera(2.5)  # a little land thud (Stick-Fight juice)
	_was_on_floor = is_on_floor()
	_update_input_buffer(delta)
	# Aim resolution. On MOBILE (touch) there's no cursor — auto-aim at the nearest
	# enemy (movement biases the fallback) so every ability is usable by just tapping
	# a button, no pixel-precise aiming. On desktop, twin-stick: track the cursor
	# every frame so casts / cast-pose / camera peek use it even mid-dash.
	if _touch_aim():
		var enemies: Array = get_tree().get_nodes_in_group("enemy")
		var fallback: Vector2 = _move_dir if _move_dir != Vector2.ZERO else facing
		_aim_dir = Targeting.aim_direction(global_position, enemies, fallback)
	else:
		var to_mouse: Vector2 = get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			_aim_dir = to_mouse.normalized()
	facing = _aim_dir
	# Feed groundedness to the rig so a limp (hold-DOWN) ragdoll clamps to the floor
	# instead of drooping through it. Set every frame; cheap.
	rig.set_grounded(is_on_floor())
	# Hold DOWN to go LIMP — the Stick-Fight ragdoll flop. Abilities + walking are
	# suspended; the active-ragdoll rig droops and gravity/friction bring you to the
	# ground. Release to snap back up.
	if Input.is_action_pressed("move_down") and not is_dashing:
		if not _ragdolling:
			_ragdolling = true
			rig.set_limp(1.0)
			rig.apply_impulse(Vector2(0.0, 1.0), 220.0)  # a little flop-down kick
		velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta) + _knockback.x
		velocity.y = 0.0 if (is_on_floor() and velocity.y >= 0.0) else minf(velocity.y + GRAVITY_FALL * delta, MAX_FALL)
		move_and_slide()
		rig.play(CharacterRig.State.HURT)
		rig.set_body_velocity(velocity)
		return
	elif _ragdolling:
		_ragdolling = false
		rig.set_limp(0.0)
	# Cosmetic + class toggles: instant, un-buffered, legal even mid-dash.
	if Input.is_action_just_pressed("cycle_element"):
		_cycle_element()
	if Input.is_action_just_pressed("cycle_colourway"):
		_cycle_colourway()
	if Input.is_action_just_pressed("switch_class"):
		_cycle_class()
	if Input.is_action_just_pressed("cycle_signature"):
		_cycle_signature()
	if Input.is_action_just_pressed("ultimate") and not is_dashing:
		_cast_signature()
	if Input.is_action_just_pressed("parry") and not is_dashing:
		_try_parry_start()
	if Input.is_action_pressed("cast") and _cast_cooldown_timer <= 0.0 and not is_dashing:
		_cast()

	if is_dashing:
		_dash_timer -= delta
		velocity = _dash_dir * _tune("dash_speed", DASH_SPEED)
		move_and_slide()
		if _cfg["dash_strike"]:
			_dash_strike_sweep()  # rogue: dash deals melee damage through enemies
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			rig.spawn_ghost(get_parent(), GHOST_COLOR, _dash_dir)
		if _dash_timer <= 0.0:
			is_dashing = false
			# Skid-to-a-stop dust puff — the "come down to the ground" kick-up.
			CombatVfx.spawn_burst(
				get_parent(), global_position,
				Color(0.82, 0.82, 0.88, 0.6), Color(0.82, 0.82, 0.88, 0.0),
				8, 0.25, 30.0, 95.0
			)
		rig.play(CharacterRig.State.DASH)
		rig.set_facing(_dash_dir)  # body faces where the dash is going
		return

	# --- Side-on movement: horizontal input, gravity, jumping ---
	var move_x: float = Input.get_axis("move_left", "move_right")
	if move_x != 0.0:
		_move_dir = Vector2(signf(move_x), 0.0)  # dash/blink dodge direction
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	if _try_fire_buffered():
		return  # a dash started this frame — the dash branch owns movement now

	# Coyote window + air-jump refill while grounded (per-class: Brawler double-jumps).
	if is_on_floor():
		_coyote = COYOTE_TIME
		_air_jumps = _max_air_jumps
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	# --- Wall-slide: gripping a wall while falling INTO it (is_on_wall_only so a
	# grounded corner never counts). get_wall_normal points AWAY from the wall. ---
	var wall_normal: Vector2 = get_wall_normal()
	var pushing_into_wall: bool = move_x != 0.0 and is_on_wall_only() \
			and signf(move_x) == -signf(wall_normal.x)
	var wall_sliding: bool = is_on_wall_only() and velocity.y > 0.0 and pushing_into_wall

	# Vertical: asymmetric gravity (floaty apex, weighty fall); wall-slide clamps it.
	if is_on_floor() and velocity.y >= 0.0:
		velocity.y = 0.0  # guard: an upward knockback pop must beat the floor-zero
	else:
		var g: float = _tune("move_gravity_rise", GRAVITY) if velocity.y < 0.0 else _tune("move_gravity_fall", GRAVITY_FALL)
		velocity.y = minf(velocity.y + g * delta, _tune("move_max_fall", MAX_FALL))
		if wall_sliding:
			velocity.y = minf(velocity.y, WALL_SLIDE_MAX_FALL)
	# Variable jump height: releasing jump while rising cuts the ascent short.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	# Jump (buffered): ground/coyote, else a WALL-JUMP off a gripped wall.
	if _jump_buffer > 0.0:
		if is_on_floor() or _coyote > 0.0:
			velocity.y = _tune("move_jump_velocity", JUMP_VELOCITY)
			_jump_buffer = 0.0
			_coyote = 0.0
			_spawn_foot_puff()
		elif is_on_wall_only():
			# Kick away from the wall + up; a slide-then-jump gets a speed boost.
			var boost: float = SLIDE_JUMP_BOOST if _was_wall_sliding else 1.0
			velocity.x = wall_normal.x * WALL_JUMP_PUSH * boost
			velocity.y = WALL_JUMP_UP
			_wall_jump_lock = WALL_JUMP_LOCKOUT
			_jump_buffer = 0.0
			_spawn_foot_puff()
		elif _air_jumps > 0:
			# Air (double) jump — classes with air_jumps > 0 (Brawler). A puff + a
			# quick flip-flourish sells the mid-air kick.
			velocity.y = DOUBLE_JUMP_VELOCITY
			_air_jumps -= 1
			_jump_buffer = 0.0
			_spawn_foot_puff()

	# Horizontal: accel toward input, friction to a stop. The wall-jump lockout
	# briefly preserves the kick-off so it can't be cancelled back into the wall.
	var spd: float = _tune("hero_speed", SPEED) * _gear_speed_mult  # gear: hood = fleet-footed
	if _wall_jump_lock <= 0.0:
		if move_x != 0.0:
			var accel: float = GROUND_ACCEL if is_on_floor() else _tune("move_air_accel", AIR_ACCEL)
			velocity.x = move_toward(velocity.x, move_x * spd, accel * delta)
		else:
			var fric: float = GROUND_FRICTION if is_on_floor() else _tune("move_air_accel", AIR_ACCEL)
			velocity.x = move_toward(velocity.x, 0.0, fric * delta)
	# Tiny push into the wall so move_and_slide keeps registering the slide.
	if wall_sliding:
		velocity.x = -wall_normal.x * WALL_STICK_PUSH
	velocity.x += _knockback.x  # ragdoll shove from an enemy hit / bomb
	move_and_slide()
	_check_wall_slam()  # crack a breakable we were slammed into
	_was_wall_sliding = wall_sliding
	rig.set_body_velocity(velocity)  # ragdoll: limbs trail when you launch/stop

	# Rig: a distinct WALL-SLIDE cling (so you read as ON the wall) with friction
	# dust; otherwise run/idle with grounded footsteps.
	if wall_sliding:
		rig.play(CharacterRig.State.WALL_SLIDE)
		rig.set_facing(Vector2(-wall_normal.x, 0.0))  # turn to face the wall
		_wall_dust_timer -= delta
		if _wall_dust_timer <= 0.0:
			_wall_dust_timer = 0.09
			CombatVfx.spawn_burst(
				get_parent(), global_position + Vector2(-wall_normal.x * 9.0, 8.0),
				Color(0.85, 0.85, 0.9, 0.6), Color(0.85, 0.85, 0.9, 0.0),
				5, 0.25, 20.0, 70.0
			)
		rig.set_aim(_aim_dir)
		return
	var moving: bool = absf(move_x) > 0.01
	rig.play(CharacterRig.State.RUN if moving else CharacterRig.State.IDLE)
	if moving and is_on_floor():
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = 0.22 if _hero_class == HeroClass.ROGUE else 0.27
			Sfx.play("footstep", -6.0, 0.14)
			# Stick-Fight walk dust: a small puff kicks up at the feet each footfall.
			CombatVfx.spawn_burst(
				get_parent(), global_position + Vector2(-signf(move_x) * 6.0, 12.0),
				Color(0.85, 0.85, 0.9, 0.45), Color(0.85, 0.85, 0.9, 0.0),
				4, 0.24, 14.0, 52.0
			)
	else:
		_footstep_timer = 0.0
	# Stick-Fight decouple: the BODY faces MOVEMENT (idle keeps the last facing —
	# set_facing ignores x==0); the cast arm/weapon aims at the true cursor. The
	# figure is FACELESS (no eyes) — aim reads from the body + the pointed weapon +
	# the parry shield, the Stick-Fight way. During a melee strike the body turns
	# to the aim so the punch points at the target.
	if rig.is_striking():
		rig.set_facing(_aim_dir)
	else:
		rig.set_facing(Vector2(move_x, 0.0))
	rig.set_aim(_aim_dir)


## Record melee/dash/blast presses into a single-slot buffer (newest press
## wins) and expire the slot after BUFFER_TIME.
func _update_input_buffer(delta: float) -> void:
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	if _buffer_timer <= 0.0:
		_buffered_action = ""
	for action: String in ["melee", "dash", "blast", "blink", "nova"]:
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
		"nova":
			if _nova_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_nova()
	return false


func _clear_input_buffer() -> void:
	_buffered_action = ""
	_buffer_timer = 0.0


## Advance to the next element (wraps) and re-apply aura + ability colour.
func _cycle_element() -> void:
	_element = (_element + 1) % Elements.count()
	_apply_element()


## Element = aura + ability colour. The aura recolours instantly (the colour
## change IS the feedback); _element_color feeds every subsequent cast.
func _apply_element() -> void:
	_element_color = Elements.color(_element)
	rig.set_aura(_element_color, AURA_STRENGTH)


## Rank-up: the aura escalates a tier (more layers/motes/ring) plus a quick
## element-coloured pop on the figure. No menus — this IS the feedback.
func _on_rank_changed(new_tier: int, _title: String) -> void:
	rig.set_aura_tier(new_tier)
	rig.flash_color(_element_color, 0.18)


## Advance to the next body colourway (wraps) and retint the rig limbs.
## Purely cosmetic — independent of the element.
func _cycle_colourway() -> void:
	_colourway = (_colourway + 1) % COLOURWAYS.size()
	rig.set_tint(COLOURWAYS[_colourway])


## Configure the hero for a class: rig preset + weapon + per-class ability
## tuning (_cfg). Called at _ready and on the debug switch. Clears cooldowns +
## buffer so a mid-fight swap can't double-fire.
func configure_class(cls: int) -> void:
	_hero_class = cls
	_cfg = CLASS_CONFIG[cls]
	rig.class_preset(_cfg["preset"])
	if String(_cfg["weapon"]) != "":
		equip_weapon(String(_cfg["weapon"]))  # rogue: sword overlay + melee retune
	else:
		# Mage: keep the preset's staff overlay; melee falls back to fists stats.
		_weapon = "fists"
		_melee_damage = MELEE_DAMAGE
		_melee_range = MELEE_RANGE
		_melee_knockback = MELEE_KNOCKBACK
	# Per-class melee tuning (cadence + arc width + optional stat overrides) so a
	# Brawler jabs fast/narrow and a Juggernaut swings slow/wide/hard.
	_melee_cd = float(_cfg.get("melee_cd", MELEE_COOLDOWN))
	_melee_arc_dot = float(_cfg.get("melee_arc_dot", MELEE_ARC_DOT))
	if _cfg.has("melee_damage"):
		_melee_damage = int(_cfg["melee_damage"])
	if _cfg.has("melee_range"):
		_melee_range = float(_cfg["melee_range"])
	if _cfg.has("melee_knockback"):
		_melee_knockback = float(_cfg["melee_knockback"])
	_dash_cooldown_timer = 0.0
	_cast_cooldown_timer = 0.0
	_blink_cooldown_timer = 0.0
	_blast_cooldown_timer = 0.0
	_nova_cooldown_timer = 0.0
	_parry_window_timer = 0.0
	_parry_cooldown_timer = 0.0
	_clear_input_buffer()
	# Per-class movement identity: air (double) jumps refill count.
	_max_air_jumps = int(_cfg.get("air_jumps", 0))
	_air_jumps = _max_air_jumps
	# Juggernaut BLOCK = a longer, more forgiving defensive window than a parry.
	_parry_window_len = 0.40 if String(_cfg.get("defense", "parry")) == "block" else PARRY_WINDOW
	# Auto-set the class's signature element (X still cycles from here) + swap in
	# the class's themed signature loadout (its hero-fantasy ultimate first).
	if _cfg.has("element"):
		_element = int(_cfg["element"])
		_apply_element()
	_signatures = SpellLibrary.build_for_class(cls)
	_signature_index = 0
	_signature_cd_timer = 0.0
	if not _signatures.is_empty():
		signature_changed.emit(_signatures[_signature_index].display_name)
	# Snapshot the fully-tuned class base (post equip_weapon) so gear mults scale from
	# it idempotently, then apply any loadout overrides' abilities.
	_base_melee_damage = _melee_damage
	_base_melee_knockback = _melee_knockback
	_base_melee_cd = _melee_cd
	_base_max_hp = max_hp
	_base_element = _element  # class innate element (a non-elemental weapon reverts here)
	_gear_override.clear()  # a fresh class = a fresh loadout base...
	_recompute_gear_effects()
	_apply_gamestate_loadout(get_node_or_null("/root/GameState"))  # ...then re-apply the hub loadout


# ---------------------------------------------------------------- gear abilities
## Public loadout hook (the loadout UI): swap the piece in `slot` ("weapon"/"head"/
## "body") to `kind` ("" clears), update the rig overlay, and re-apply the gear
## abilities. Idempotent — the effects recompute from the class base every time.
func set_loadout(slot: String, kind: String) -> void:
	if kind == "":
		_gear_override.erase(slot)
	else:
		_gear_override[slot] = kind
	rig.set_equipment(slot, kind)  # cosmetic overlay follows the choice
	_recompute_gear_effects()


## Apply the hub Armory's loadout override (GameState.loadout) after the class base:
## any non-empty slot swaps the class-default piece for the player's choice, then the
## gear abilities recompute once. No-op when nothing is overridden (default classes).
func _apply_gamestate_loadout(gs: Node) -> void:
	if gs == null:
		return
	var lo: Variant = gs.get("loadout")
	if not (lo is Dictionary):
		return
	var changed: bool = false
	for slot: String in ["weapon", "head", "body"]:
		var kind: String = String((lo as Dictionary).get(slot, ""))
		if kind != "":
			_gear_override[slot] = kind
			rig.set_equipment(slot, kind)
			changed = true
	if changed:
		_recompute_gear_effects()


## Aggregate the equipped gear's effect bags (weapon/head/body) into one modifier
## set. Mults multiply, ward takes the strongest, an elemental weapon wins the element.
func _aggregate_gear() -> Dictionary:
	var out: Dictionary = {
		"melee_damage": 1.0, "melee_knockback": 1.0, "melee_cd": 1.0,
		"max_hp": 1.0, "speed": 1.0, "ward": 0.0, "damage_reduction": 0.0, "element": -1,
	}
	for slot: String in ["weapon", "head", "body"]:
		var kind: String = String(_gear_override.get(slot, ""))  # only player CHOICES grant abilities
		if kind == "":
			continue
		var e: Dictionary = GearAbilities.effect(kind)
		for k: String in ["melee_damage", "melee_knockback", "melee_cd", "max_hp", "speed"]:
			if e.has(k):
				out[k] *= float(e[k])
		for k: String in ["ward", "damage_reduction"]:
			if e.has(k):
				out[k] = maxf(out[k], float(e[k]))
		if e.has("element"):
			out["element"] = int(GEAR_ELEMENT.get(String(e["element"]), -1))
	return out


## Apply the aggregated gear effects from the class BASE (idempotent). Called on
## class config + every loadout swap; safe to re-run.
func _recompute_gear_effects() -> void:
	var g: Dictionary = _aggregate_gear()
	# Melee profile from the captured class base * gear mult (idempotent).
	_melee_damage = int(round(float(_base_melee_damage) * float(g["melee_damage"])))
	_melee_knockback = _base_melee_knockback * float(g["melee_knockback"])
	_melee_cd = _base_melee_cd * float(g["melee_cd"])
	# Max HP from the class base * gear mult (keep the current fill ratio).
	var new_max: int = maxi(int(round(float(_base_max_hp) * float(g["max_hp"]))), 1)
	if new_max != max_hp:
		var ratio: float = float(hp) / float(maxi(max_hp, 1))
		max_hp = new_max
		hp = clampi(int(round(float(new_max) * ratio)), 1, new_max)
		health_changed.emit(hp, max_hp)
	_gear_speed_mult = float(g["speed"])
	_gear_ward_frac = float(g["ward"])
	_gear_damage_reduction = float(g["damage_reduction"])
	_gear_ward_used = false  # a fresh loadout / class = a fresh ward
	# Element follows the WEAPON: an elemental weapon (staff_ice, scythe, ...) sets it;
	# a non-elemental weapon reverts to the class's innate element (never sticks).
	var ge: int = int(g["element"])
	_element = ge if ge >= 0 else _base_element
	_apply_element()


## Debug: cycle class live (Tab) and persist the choice to GameState so the hub
## selection and the next run stay in sync.
func _cycle_class() -> void:
	configure_class((_hero_class + 1) % HeroClass.size())
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.selected_class = _hero_class


## Live class cycle for a test button (mirrors the Tab press).
func cycle_class_next() -> void:
	_cycle_class()


func current_class_name() -> String:
	return CLASS_NAMES[_hero_class] if _hero_class < CLASS_NAMES.size() else "Class"


## Unleash the equipped SIGNATURE spectacle toward the aim, if off cooldown and
## MP allows. Consumes the SpellDef's mp_cost; SpellCaster picks the spectacle
## (magic-circle beam / divine ray / ...). Not buffered — a deliberate press.
func _cast_signature() -> void:
	if _signatures.is_empty() or _signature_cd_timer > 0.0:
		return
	var spell: SpellDef = _signatures[_signature_index]
	if mp < float(spell.mp_cost):
		# Not enough mana: a soft fizzle cue, no cast, no cooldown burned.
		rig.flash_color(Color(0.5, 0.5, 0.6), 0.08)
		Sfx.play("melee_swing", -14.0, 0.0)
		return
	mp -= float(spell.mp_cost)
	mana_changed.emit(mp, max_mp)
	_signature_cd_timer = spell.cooldown
	# Sky spells (meteor / divine row) raise the staff UP and place from the hero;
	# beams emanate FROM the staff tip toward the aim.
	var sky: bool = spell.kind == SpellDef.Kind.METEOR or spell.kind == SpellDef.Kind.DIVINE_RAY \
			or spell.kind == SpellDef.Kind.CONVERGENCE
	# Big spectacles LEVITATE + channel for cast_time, THEN fire — they carry their
	# own float ceremony already.
	if spell.cast_time > 0.0:
		_begin_channel(spell, sky)
		return
	# Every OTHER signature now blooms an epic SUMMON windup (spell circle + committed
	# cast pose + gather motes) before it erupts. Rush + blink keep their special
	# fire logic (lunge / teleport), routed through _finish_summon.
	var special: int = SUMMON_NORMAL
	if spell.kind == SpellDef.Kind.RUSH:
		special = SUMMON_RUSH
	elif spell.kind == SpellDef.Kind.BLINK_STRIKE:
		special = SUMMON_BLINK
	_begin_summon(spell, sky, special)


## Start the epic summon windup: freeze committed, bloom a grounded spell circle,
## GATHER pose, charge SFX. The actual spell fires in _finish_summon.
func _begin_summon(spell: SpellDef, sky: bool, special: int) -> void:
	_summoning = true
	_summon_spell = spell
	_summon_sky = sky
	_summon_special = special
	_summon_total = SUMMON_WINDUP_FAST if special != SUMMON_NORMAL else SUMMON_WINDUP
	_summon_timer = _summon_total
	_summon_aim = _aim_dir
	_summon_target = get_global_mouse_position()
	velocity = Vector2.ZERO
	rig.set_aim(Vector2.UP if sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.GATHER, 0.9, _element)  # both hands gather the power
	# The summoning sigil blooms beneath the caster over the windup (sized by cost).
	_summon_circle = MagicCircle.new()
	get_parent().add_child(_summon_circle)
	_summon_circle.global_position = global_position + Vector2(0.0, 8.0)
	var r: float = 34.0 + 22.0 * clampf(spell.mp_cost / 90.0, 0.0, 1.0)
	_summon_circle.call("appear", _element_color, r, _summon_total)
	Sfx.play("charge_up", -6.0, 0.05)


## Hold the committed summon each frame: stay put + grounded, grow the sigil, gather
## converging motes, then erupt when the windup elapses.
func _process_summon(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()  # hold position (gravity zeroed -> committed in place)
	rig.set_body_velocity(Vector2.ZERO)
	rig.play(CharacterRig.State.CAST)  # keep the committed cast pose held
	if _summon_circle != null and is_instance_valid(_summon_circle):
		_summon_circle.global_position = global_position + Vector2(0.0, 8.0)
		var prog: float = 1.0 - _summon_timer / maxf(_summon_total, 0.001)
		_summon_circle.scale = Vector2.ONE * (0.55 + 0.7 * prog)  # sigil grows as it charges
	# Energy motes converge inward on the caster (the wind-up).
	if fmod(_summon_timer, 0.09) < delta:
		CombatVfx.spawn_burst(get_parent(), global_position,
			Color(_element_color.r, _element_color.g, _element_color.b, 0.75),
			Color(_element_color.r, _element_color.g, _element_color.b, 0.0),
			5, 0.26, 48.0, 100.0, 0.5, 1.4, 0.0, 0.0, true)
	_summon_timer -= delta
	if _summon_timer <= 0.0:
		_finish_summon()


## The eruption: run the signature's real fire logic, then fire ONE synchronized
## epic beat (camera reveal + punch + shake + hitstop) as the payoff.
func _finish_summon() -> void:
	var spell: SpellDef = _summon_spell
	var special: int = _summon_special
	var sky: bool = _summon_sky
	var aim: Vector2 = _summon_aim
	var target: Vector2 = _summon_target
	_end_summon()
	if spell == null:
		return
	match special:
		SUMMON_RUSH:
			# Chidori / rush: LUNGE forward as the lance rips out.
			rig.set_aim(aim)
			rig.play(CharacterRig.State.PUNCH)
			rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.9, _element)
			if aim.x != 0.0:
				velocity.x = signf(aim.x) * 360.0
			SpellCaster.cast(spell, get_parent(), rig.get_weapon_tip(), target, _element_color, spell.effect)
		SUMMON_BLINK:
			# Shadow-step: TELEPORT to the marked point mid-slash (moves the Hero node).
			var bfrom: Vector2 = global_position
			var to_aim: Vector2 = target - bfrom
			if to_aim.length() > spell.reach:
				to_aim = to_aim.normalized() * spell.reach
			var dest: Vector2 = _safe_blink_destination(bfrom, bfrom + to_aim)
			var bs: Node2D = (load("res://scripts/combat/BlinkStrike.gd") as GDScript).new()
			get_parent().add_child(bs)
			bs.set("element_id", SpellCaster.resolve_element(spell))
			global_position = dest
			velocity.y = 0.0
			_blink_iframe_timer = BLINK_IFRAME
			bs.call("strike", bfrom, dest, _element_color, spell.damage, spell.effect)
			rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
			rig.play(CharacterRig.State.CAST)
		_:
			rig.set_aim(Vector2.UP if sky else aim)
			rig.play(CharacterRig.State.CAST)
			var origin: Vector2 = global_position if sky else rig.get_weapon_tip()
			SpellCaster.cast(spell, get_parent(), origin, target, _element_color, spell.effect)
			_self_recoil(110.0)  # the ultimate shoves you back
	_notify_element_used()
	# THE PAYOFF — the crescendo after the anticipation. Blink already flashes, so
	# skip the heavy speed-line frame on it; the planted/rush eruptions get it.
	Juice.epic_moment({"strength": 1.0, "frame": special != SUMMON_BLINK})


## Shared summon teardown: clear state + bloom the sigil out (the eruption flare).
func _end_summon() -> void:
	_summoning = false
	_summon_spell = null
	if _summon_circle != null and is_instance_valid(_summon_circle):
		_summon_circle.call("vanish", 0.2)  # blooms out as the spell erupts
	_summon_circle = null


## A landed hit shatters the summon — sigil breaks, the ult is lost (MP + cooldown
## already spent, like the channel). Lighter feedback than the channel interrupt.
func _cancel_summon() -> void:
	var pos: Vector2 = global_position
	_end_summon()
	CombatVfx.spawn_burst(get_parent(), pos,
		Color(_element_color.r, _element_color.g, _element_color.b, 0.9),
		Color(_element_color.r, _element_color.g, _element_color.b, 0.0),
		14, 0.4, 60.0, 200.0, 1.0, 3.0)
	rig.flash_color(Color(0.7, 0.4, 0.9), 0.12)
	Juice.shake_camera(6.0)
	Sfx.play("melee_swing", -8.0, 0.0)


## Enter the levitating cast: lift off, lock the aim, grow a build-up sigil, hold
## a committed CAST pose. MP + cooldown are already spent (interrupt = no refund).
func _begin_channel(spell: SpellDef, sky: bool) -> void:
	_channeling = true
	_channel_spell = spell
	_channel_sky = sky
	_channel_timer = spell.cast_time
	_channel_total = spell.cast_time
	_channel_target = get_global_mouse_position()
	_channel_base_y = global_position.y
	_channel_lift = 0.0
	velocity = Vector2.ZERO
	rig.set_aim(Vector2.UP if sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.set_airborne(true)  # legs dangle while floating
	# Build-up sigil that grows beneath/around the caster over the channel.
	_channel_circle = MagicCircle.new()
	get_parent().add_child(_channel_circle)
	_channel_circle.global_position = global_position + Vector2(0.0, 6.0)
	_channel_circle.call("appear", _element_color, 44.0 + 26.0 * clampf(spell.mp_cost / 90.0, 0.0, 1.0), spell.cast_time)
	Sfx.play("charge_up", -2.0, 0.04)  # anime beam/ult power-up swell
	# Pull the camera WIDE for the whole build-up + release so the "insane spell"
	# reads (maker: "when these insane spells are being cast we should zoom out to
	# see the spell"). Hold spans the channel; the fire-time pull in SpellCaster
	# composes on top (max-of-amounts), and it eases back after the cast lands.
	Juice.zoom_pull_camera(0.26, spell.cast_time + 0.55, 0.2, 0.7)


## Per-frame while channeling: ease the levitation, hold the pose, count down, and
## on completion fire the spell (or the physics loop already returned early on cancel).
func _process_channel(delta: float) -> void:
	_channel_lift = move_toward(_channel_lift, CHANNEL_LIFT_HEIGHT, CHANNEL_LIFT_SPEED * delta)
	var bob: float = sin((_channel_total - _channel_timer) * 6.0) * 2.0
	global_position.y = _channel_base_y - _channel_lift + bob
	velocity = Vector2.ZERO
	rig.set_airborne(true)
	rig.set_body_velocity(Vector2.ZERO)
	if _channel_circle != null and is_instance_valid(_channel_circle):
		_channel_circle.global_position = global_position + Vector2(0.0, 6.0)
		# The sigil GROWS as the cast charges — small at first, large at release.
		var prog: float = 1.0 - _channel_timer / maxf(_channel_total, 0.001)
		_channel_circle.scale = Vector2.ONE * (0.5 + 0.85 * prog)
	# Gather motes now and then — energy converging on the caster.
	if fmod(_channel_timer, 0.12) < delta:
		CombatVfx.spawn_burst(get_parent(), global_position, Color(_element_color.r, _element_color.g, _element_color.b, 0.7),
			Color(_element_color.r, _element_color.g, _element_color.b, 0.0), 6, 0.3, 40.0, 90.0, 0.5, 1.4, 0.0, 0.0, true)
	_channel_timer -= delta
	if _channel_timer <= 0.0:
		_finish_channel()


## Channel completed uninterrupted — unleash the spectacle, then settle back down.
func _finish_channel() -> void:
	var spell: SpellDef = _channel_spell
	_end_channel()
	if spell == null:
		return
	rig.set_aim(Vector2.UP if _channel_sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	var origin: Vector2 = global_position if _channel_sky else rig.get_weapon_tip()
	SpellCaster.cast(spell, get_parent(), origin, _channel_target, _element_color, spell.effect)
	_notify_element_used()
	_self_recoil(90.0)
	# The biggest beat in the game — the full synchronized epic payoff (the channeled
	# ults are the screen-fillers, so strength + speed-lines are dialed up).
	Juice.epic_moment({"strength": 1.25, "frame": true})


## A hit landed mid-channel — the ultimate is DISRUPTED (mana/cooldown stay spent).
## Make this UNMISTAKABLE (maker: "the interrupt isn't quite working properly" —
## it fired but read as nothing happening): the growing sigil SHATTERS in the
## element hue, the screen flashes + shakes hard, and the caster is flung out of
## the float. You should never wonder whether the ult got cut.
func _cancel_channel() -> void:
	if not _channeling:
		return
	var burst_pos: Vector2 = global_position
	if _channel_circle != null and is_instance_valid(_channel_circle):
		burst_pos = _channel_circle.global_position
	var ec: Color = _element_color
	_end_channel()
	# Sigil shatter: a bright element-hued blowout ring of shards where the circle was.
	CombatVfx.spawn_burst(get_parent(), burst_pos,
		Color(ec.r, ec.g, ec.b, 0.95), Color(ec.r, ec.g, ec.b, 0.0),
		26, 0.45, 90.0, 280.0, 1.5, 3.2, 0.0, 0.0, true)
	# A grey "fizzle" puff over the caster reads as the spell collapsing.
	CombatVfx.spawn_burst(get_parent(), global_position, Color(0.7, 0.6, 0.75, 0.85),
		Color(0.3, 0.25, 0.4, 0.0), 14, 0.4, 50.0, 150.0)
	rig.flash_color(Color(0.85, 0.55, 1.0), 0.18)  # violet disrupt flash
	rig.apply_impulse(Vector2(-facing.x, 0.6), 260.0)  # flung out of the float
	Juice.impact_frame(0.8)  # brief anime freeze so the cut lands
	Juice.shake_camera(9.0)
	Sfx.play("hero_hurt", 0.0, 0.1)
	Sfx.play("melee_swing", -6.0, 0.14)


## Shared channel teardown: drop the float, fizzle the sigil, restore physics.
func _end_channel() -> void:
	_channeling = false
	_channel_spell = null
	rig.set_airborne(false)
	if _channel_circle != null and is_instance_valid(_channel_circle):
		_channel_circle.call("vanish", 0.2)
	_channel_circle = null


## Swap to the next equipped signature (the loadout cycle — V). On mobile this is
## a loadout selector, not a per-cast key, so the in-combat input set stays small.
func _cycle_signature() -> void:
	if _signatures.is_empty():
		return
	_signature_index = (_signature_index + 1) % _signatures.size()
	signature_changed.emit(_signatures[_signature_index].display_name)
	Sfx.play("footstep", -3.0, 0.25)


## Active signature (or null) — for the HUD label + cooldown/MP readout.
func current_signature() -> SpellDef:
	if _signatures.is_empty():
		return null
	return _signatures[_signature_index]


func signature_cooldown_ratio() -> float:
	var s: SpellDef = current_signature()
	if s == null or s.cooldown <= 0.0:
		return 0.0
	return clampf(_signature_cd_timer / s.cooldown, 0.0, 1.0)


## Rogue dash-strike: every enemy/crate the dash passes within range takes melee
## damage once per dash (dedupe via _dash_hit). Mirrors _on_melee_hit_frame.
func _dash_strike_sweep() -> void:
	var rng: float = _cfg["dash_strike_range"]
	var dmg: int = _cfg["dash_strike_damage"]
	var hit_any: bool = false
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Node2D or enemy in _dash_hit:
			continue
		if global_position.distance_to(enemy.global_position) >= rng:
			continue
		_dash_hit.append(enemy)
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(_dash_dir * _melee_knockback)
		hit_any = true
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if not prop is Node2D or prop in _dash_hit:
			continue
		if global_position.distance_to(prop.global_position) >= rng:
			continue
		_dash_hit.append(prop)
		if prop.has_method("take_damage"):
			prop.take_damage(dmg)
		hit_any = true
	if hit_any:
		Juice.hit_stop(0.05)
		Juice.shake_camera(4.0)
		Sfx.play("melee_hit")


func _start_dash() -> void:
	is_dashing = true
	_dash_timer = _tune("dash_time", DASH_TIME)
	_dash_cooldown_timer = _cfg["dash_cd"]
	# Dash the EXACT angle of the held movement keys (true 8-way): W+D -> up-right,
	# S+A -> down-left, D alone -> flat right. Accurate to which keys are down,
	# including vertical. Falls back to live velocity, then the last walk dir /
	# facing, only when no direction key is held (a standing dash).
	var keys: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if keys.length() > 0.1:
		_dash_dir = keys.normalized()
	elif velocity.length() > 40.0:
		_dash_dir = velocity.normalized()
	elif _move_dir != Vector2.ZERO:
		_dash_dir = _move_dir
	else:
		_dash_dir = Vector2(signf(facing.x), 0.0) if facing.x != 0.0 else Vector2.RIGHT
	_ghost_timer = 0.0  # first afterimage lands this frame
	_dash_hit.clear()


## Shadow blink: instant teleport BLINK_DISTANCE along the MOVEMENT direction,
## phasing THROUGH walls (no clamp — mobile-friendly, no aim needed). Leaves a
## dark silhouette + violet poof at the origin, another poof + bright flash at
## the destination, and grants BLINK_IFRAME seconds of invulnerability. Buffered
## like dash/melee/blast; only reachable from the not-dashing path.
func _blink() -> void:
	# Brawler can't teleport — its R is a launcher UPPERCUT that pops enemies into
	# the air (double-jump after them to juggle).
	if String(_cfg.get("mobility2", "blink")) == "uppercut":
		_uppercut()
		return
	if _blink_cooldown_timer > 0.0:
		return
	_blink_cooldown_timer = _cfg["blink_cd"]
	_blink_iframe_timer = BLINK_IFRAME
	var origin: Vector2 = global_position
	# Blink along the MOVEMENT/walk direction (mobile-friendly — no aim needed),
	# phasing THROUGH walls a fixed BLINK_DISTANCE. _move_dir persists the last
	# walk direction, so a standing blink still fires (falls back to RIGHT).
	var dir: Vector2 = _move_dir
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	# Land THROUGH walls but never INSIDE one (relocate a blocked endpoint).
	var dest: Vector2 = _safe_blink_destination(origin, origin + dir.normalized() * BLINK_DISTANCE)
	# Shadow-poof where we WERE: dark fading silhouette + violet burst.
	rig.spawn_ghost(get_parent(), BLINK_SHADOW_COLOR, Vector2.ZERO, Vector2.ZERO, 0.35)
	CombatVfx.spawn_burst(
		get_parent(), origin, BLINK_BURST_START, BLINK_BURST_END,
		18, 0.35, 40.0, 110.0, 1.5, 3.0
	)
	global_position = dest
	velocity.y = 0.0  # don't inherit fall speed -> no "heavy gravity" right after a blink
	# Arrival poof: bigger burst + a quick bright flash on the rig.
	CombatVfx.spawn_burst(
		get_parent(), dest, BLINK_BURST_START, BLINK_BURST_END,
		24, 0.4, 60.0, 140.0, 1.5, 3.5
	)
	rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("blink", 0.0, 0.1)  # dedicated synth "vwip" teleport sound


## BRAWLER uppercut (R) — a rising launcher: the hero hops and everything in a
## short forward range is popped UP (sets up an air-juggle with the double-jump).
func _uppercut() -> void:
	if _blink_cooldown_timer > 0.0:
		return
	_blink_cooldown_timer = maxf(_cfg["blink_cd"], 1.1)
	rig.set_facing(_aim_dir)
	rig.play(CharacterRig.State.KICK)
	velocity.y = -320.0  # the hero rises with the uppercut
	var face_x: float = signf(_aim_dir.x) if _aim_dir.x != 0.0 else 1.0
	var hit_any: bool = false
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Node2D:
			continue
		var to: Vector2 = enemy.global_position - global_position
		if to.length() > 70.0 or signf(to.x) != face_x and absf(to.x) > 10.0:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(18)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(Vector2(face_x * 120.0, -470.0))  # POP up + slight away
		if enemy.has_method("apply_status"):
			enemy.apply_status(_element)
		hit_any = true
	CombatVfx.spawn_burst(
		get_parent(), global_position + Vector2(face_x * 20.0, -6.0),
		Color(1.0, 0.9, 0.5, 0.8), Color(1.0, 0.5, 0.15, 0.0), 12, 0.3, 60.0, 180.0
	)
	Sfx.play("melee_hit")
	if hit_any:
		Juice.hit_stop(0.06)
		Juice.shake_camera(5.0)


## Blink landing safety: the endpoint may never rest INSIDE a solid. Test the
## destination against layer-1 solids; if blocked, probe forward past a thin wall,
## then back toward the origin, returning the first clear spot. Phasing THROUGH a
## wall mid-blink stays fine — only the resting spot matters.
func _safe_blink_destination(origin: Vector2, dest: Vector2) -> Vector2:
	var world: World2D = get_world_2d()
	if world == null:
		return dest  # headless / no physics world — leave as-is
	var shape: Shape2D = _blink_shape()
	if shape == null:
		return dest
	var space: PhysicsDirectSpaceState2D = world.direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = BLINK_WALL_MASK
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	var span: Vector2 = dest - origin
	if span.length() < 1.0:
		return dest
	var dir: Vector2 = span.normalized()
	q.transform = Transform2D(0.0, dest)
	if space.intersect_shape(q, 1).is_empty() and not _dest_in_pit(dest):
		return dest  # clear — the common case
	# Blocked (solid OR over the void): look for daylight just PAST a thin wall first...
	var d: float = BLINK_PROBE_STEP
	while d <= BLINK_PROBE_EXTRA:
		var pf: Vector2 = dest + dir * d
		q.transform = Transform2D(0.0, pf)
		if space.intersect_shape(q, 1).is_empty() and not _dest_in_pit(pf):
			return pf
		d += BLINK_PROBE_STEP
	# ...else fall back toward the origin (which is on the map) — this is what
	# "limits it to where you can actually teleport": you slide back onto solid map.
	var max_back: float = span.length()
	d = BLINK_PROBE_STEP
	while d <= max_back:
		var pb: Vector2 = dest - dir * d
		q.transform = Transform2D(0.0, pb)
		if space.intersect_shape(q, 1).is_empty() and not _dest_in_pit(pb):
			return pb
		d += BLINK_PROBE_STEP
	return origin  # nowhere clear — don't move


## True if `pos` lands inside a ring-out PIT (a StageHazard in PIT mode), plus a
## margin off the lip. Loose group + property lookup so Hero doesn't hard-depend on
## StageHazard. Headless (no stage_hazard group) -> always false, so blink tests
## are unaffected. Mode.PIT == 0.
func _dest_in_pit(pos: Vector2) -> bool:
	for h: Node in get_tree().get_nodes_in_group("stage_hazard"):
		if not h is Node2D or int(h.get("mode")) != 0:
			continue
		var size_v: Variant = h.get("zone_size")
		if not size_v is Vector2:
			continue
		var half: Vector2 = (size_v as Vector2) * 0.5 + Vector2(BLINK_PIT_MARGIN, BLINK_PIT_MARGIN)
		var rel: Vector2 = pos - (h as Node2D).global_position
		if absf(rel.x) <= half.x and absf(rel.y) <= half.y:
			return true
	return false


## The hero's own collision shape (found at runtime — no hard-coded node name).
func _blink_shape() -> Shape2D:
	for c: Node in get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null:
			return (c as CollisionShape2D).shape
	return null


## The LMB PRIMARY — dispatched per class so no two classes attack the same way:
## melee_combo (Brawler punch/kick, no magic), heavy_swing (Juggernaut wide slow
## hammer), frost_cone (Cryomancer chilling cone), or a bolt with per-class flavour
## flags (plain / heal / drain / chain / burst). This is the core "classes feel
## different, not just different spells" fix.
func _cast() -> void:
	match String(_cfg.get("primary", "bolt")):
		"melee_combo":
			_primary_melee_combo()
		"heavy_swing":
			_primary_heavy_swing()
		"frost_cone":
			_primary_frost_cone()
		_:
			_primary_bolt()


## Ranged bolt with per-class flavour: bolt_heal (Cleric/Warlock lifesteal),
## bolt_chain (Stormcaller arc), bolt_burst (Shadowblade flurry, spread shots).
func _primary_bolt() -> void:
	_cast_cooldown_timer = _cfg["cast_cd"]
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	# Aim at the cursor, softly assisted toward an enemy inside the forgiveness cone.
	var base_dir: Vector2 = Targeting.assisted_aim(global_position, _aim_dir, enemies)
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.5, _element)  # quick hand-flick tell
	var origin: Vector2 = rig.get_weapon_tip()
	var burst: int = int(_cfg.get("bolt_burst", 1))
	var spread: float = float(_cfg.get("bolt_spread", 0.0))
	for i: int in maxi(burst, 1):
		# Fan a burst symmetrically around the aim (single shot -> no offset).
		var off: float = 0.0 if burst <= 1 else (float(i) - float(burst - 1) * 0.5) * spread
		var dir: Vector2 = base_dir.rotated(off)
		var spell: Area2D = SPELL_SCENE.instantiate()
		get_parent().add_child(spell)
		spell.global_position = origin
		spell.launch(dir)
		if spell.has_method("set_element_color"):
			spell.call("set_element_color", _element_color)
		spell.set("element_id", _element)
		if bool(_cfg["throw_blade"]):
			spell.set("damage", int(_cfg["blade_damage"]))
		# Flavour flags.
		var heal: int = int(_cfg.get("bolt_heal", 0))
		if heal > 0:
			spell.set("heal_on_hit", heal)
			spell.set("caster", self)
		var chain: int = int(_cfg.get("bolt_chain", 0))
		if chain > 0:
			spell.set("chain_count", chain)
	Sfx.play("cast", 0.0, 0.08)
	Juice.shake_camera(1.0)
	_notify_element_used()


## BRAWLER primary — a punch→punch→KICK melee combo that steps you forward. No
## projectile. The melee cooldown gates the cadence, so holding LMB auto-combos;
## every 3rd swing is a launcher kick. Reuses the rig PUNCH/KICK + hit_frame path.
func _primary_melee_combo() -> void:
	if _melee_cooldown_timer > 0.0:
		return
	rig.set_facing(_aim_dir)
	_melee()  # alternates PUNCH/KICK via _melee_kick_next, sets _melee_cooldown, swing sfx
	# Step INTO the combo so the boxer walks his punches forward.
	if _aim_dir.x != 0.0:
		velocity.x = signf(_aim_dir.x) * 200.0


## JUGGERNAUT primary — a slow, wide overhead hammer swing that staggers a crowd.
## Wide arc + big knockback come from the per-class melee params (configure_class);
## the slow _melee_cd is the commitment.
func _primary_heavy_swing() -> void:
	if _melee_cooldown_timer > 0.0:
		return
	rig.set_facing(_aim_dir)
	rig.play(CharacterRig.State.PUNCH)
	# Smaller wind-up (maker: "make the charge up for the heavys just slightly smaller").
	rig.cast_gesture(CharacterRig.GestureKind.STOMP, 0.4, _element)
	# STEP INTO the swing so the heavy actually closes + CONNECTS (maker: the heavy
	# attacks "aren't working" — they were whiffing at its short reach). The lunge +
	# the wider reach (CLASS_CONFIG) make the hammer land instead of swinging air.
	if _aim_dir.x != 0.0:
		velocity.x = signf(_aim_dir.x) * 190.0
	_melee_cooldown_timer = _melee_cd
	Sfx.play("melee_swing", 0.0, 0.12)


## CRYOMANCER primary — a short-range FROST CONE (no projectile): every enemy in
## the forward arc is chilled (2nd stack freezes) + lightly shoved. Forces mid-range.
func _primary_frost_cone() -> void:
	if _cast_cooldown_timer > 0.0:
		return
	_cast_cooldown_timer = _cfg["cast_cd"]
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.6, _element)  # frost coats the hand
	const CONE_RANGE: float = 118.0
	const CONE_COS: float = 0.5  # ~60° half-angle
	const CONE_DAMAGE: int = 12
	var hit_any: bool = false
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Node2D:
			continue
		var to: Vector2 = enemy.global_position - global_position
		if to.length() > CONE_RANGE or _aim_dir.dot(to.normalized()) < CONE_COS:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(CONE_DAMAGE)
		if enemy.has_method("apply_status"):
			enemy.apply_status(_element)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(to.normalized() * 160.0)
		hit_any = true
	# Frost fan VFX along the aim.
	var fan_at: Vector2 = global_position + _aim_dir * CONE_RANGE * 0.55
	CombatVfx.spawn_burst(
		get_parent(), fan_at, Color(0.85, 0.97, 1.0, 0.9), Color(0.5, 0.8, 1.0, 0.0),
		20, 0.32, 120.0, 260.0, 0.6, 1.8
	)
	Sfx.play("cast", -2.0, 0.06)
	if hit_any:
		Juice.shake_camera(2.0)
	_notify_element_used()


## Heal the hero (Cleric/Warlock lifesteal, Cleric heal-nova). Clamps to max_hp.
func heal(amount: int) -> void:
	if amount <= 0 or hp >= max_hp:
		return
	hp = mini(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)
	rig.flash_color(Color(0.6, 1.0, 0.7), 0.08)  # a soft green heal tick


## The Q slot — dispatched on the class's AoE variant. Every variant carries the
## hero's ACTIVE element (so a Brawler who cycles to Ice throws an ice-punch).
func _blast() -> void:
	_blast_cooldown_timer = _cfg["blast_cd"]
	_self_recoil(80.0)  # the giant blast kicks the caster back
	match String(_cfg["aoe"]):
		"nova":
			_spawn_nova()          # rogue whirlwind
		"fist_shock":
			_fire_punch()          # brawler — lunging elemental shockwave
		"ground_slam":
			_ground_slam()         # juggernaut — self-centred crater
		"arcane_meteor":
			_arcane_meteor()       # arcanist — arcane star-fall barrage
		"consecrate":
			_consecrate()          # cleric — hallowed ground field
		"ice_shards":
			_ice_shards()          # cryomancer — homing frost shard spray
		"call_lightning":
			_call_lightning()      # stormcaller — lightning strike column
		"curse_chain":
			_curse_chain()         # warlock — leaping shadow chain
		_:
			_meteor_blast()        # placed giant blast (fallback)


## Placed giant blast: lands where the cursor points, clamped to a max cast range
## so it stays a skill-shot, not a whole-stage snipe.
func _meteor_blast() -> void:
	var to_target: Vector2 = get_global_mouse_position() - global_position
	if to_target.length() > BLAST_MAX_RANGE:
		to_target = to_target.normalized() * BLAST_MAX_RANGE
	var target_pos: Vector2 = global_position + to_target
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.set("element_id", _element)
	blast.detonate_at(target_pos)
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.65, _element)  # arm gathers, lobs the blast


## FIRE PUNCH — the Brawler's Q. A lunging straight that erupts an elemental
## shockwave just in front of the fist: instant (no windup), tight radius, HUGE
## knockback + the active element's ailment. Reads as a committed melee blast.
func _fire_punch() -> void:
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.PUNCH)
	rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.8, _element)  # the FIST ignites
	# A short forward lunge so the punch drives INTO the target.
	velocity.x = signf(_aim_dir.x) * 300.0 if _aim_dir.x != 0.0 else velocity.x
	var center: Vector2 = global_position + _aim_dir.normalized() * 44.0
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.call("configure", {
		"target_group": "enemy", "damage": 30, "radius": 66.0,
		"knockback": 430.0, "element_id": _element,
	})
	blast.call("detonate_now", center)
	Juice.impact_frame(0.8)  # the cool PUNCH beat


## GROUND SLAM — the Juggernaut's Q. A small hop then a self-centred crater: wide
## radius, heavy knockback + the active element's ailment (Stagger by default).
func _ground_slam() -> void:
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.STOMP, 0.8, _element)  # fist drives down
	velocity.y = -240.0  # a small hop into the slam
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.call("configure", {
		"target_group": "enemy", "damage": 34, "radius": 98.0,
		"knockback": 380.0, "element_id": _element,
	})
	blast.call("detonate_now", global_position)


## Energy nova: instant self-centered shockwave. No telegraph — the panic
## button fires the moment the press lands (buffered like blast/blink). Mage
## only; the rogue's whirlwind reuses _spawn_nova through _blast.
func _nova() -> void:
	if not bool(_cfg["has_nova"]):
		return
	if _nova_cooldown_timer > 0.0:
		return
	_nova_cooldown_timer = NOVA_COOLDOWN
	_spawn_nova()


func _spawn_nova() -> void:
	var nova: Node2D = NOVA_SCENE.instantiate()
	get_parent().add_child(nova)
	nova.set("element_id", _element)
	nova.call("activate_at", global_position)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.6, _element)  # arms fling out the nova


## Cursor target for a placed Q, clamped to BLAST_MAX_RANGE so it stays a skill-shot.
func _aoe_target() -> Vector2:
	var to_target: Vector2 = get_global_mouse_position() - global_position
	if to_target.length() > BLAST_MAX_RANGE:
		to_target = to_target.normalized() * BLAST_MAX_RANGE
	return global_position + to_target


# ---- Per-class DISTINCT Q spectacles (maker: "Q's are just reworks of each other
# — give each CLASS a distinct epic Q, not a recolored blast"). Each reuses a
# proven spectacle scene in a config distinct from that class's G signature, and
# carries the hero's ACTIVE element. Runtime-load()ed (never preload) so the
# headless slice harness that compiles Hero doesn't early-compile these.

## ARCANIST Q — Arcane Storm: a short barrage of arcane meteors rains on the cursor.
func _arcane_meteor() -> void:
	var meteor: Node2D = (load("res://scripts/combat/MeteorSigil.gd") as GDScript).new()
	get_parent().add_child(meteor)
	meteor.set("element_id", _element)
	meteor.call("rain", _aoe_target(), _element_color, 92.0, 22, 5, Elements.effect_name(_element))
	rig.set_aim(Vector2.UP)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.7, _element)


## CLERIC Q — Consecrate: hallowed ground pulses holy damage where the cursor points.
func _consecrate() -> void:
	var zone: Node2D = (load("res://scripts/combat/ZoneSpell.gd") as GDScript).new()
	get_parent().add_child(zone)
	zone.set("element_id", _element)
	zone.call("open", _aoe_target(), _element_color, 98.0, 11, Elements.effect_name(_element), 4.0)
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.6, _element)


## CRYOMANCER Q — Ice Shards: a spray of homing frost shards toward the aim.
func _ice_shards() -> void:
	var orbs: Node2D = (load("res://scripts/combat/RuneOrbs.gd") as GDScript).new()
	get_parent().add_child(orbs)
	orbs.set("element_id", _element)
	orbs.call("launch", rig.get_weapon_tip(), _aim_dir.normalized(), _element_color, 6, 18, Elements.effect_name(_element))
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.7, _element)


## STORMCALLER Q — Call Lightning: a bolt column crashes down on the cursor.
func _call_lightning() -> void:
	var ray: Node2D = (load("res://scripts/combat/DivineRay.gd") as GDScript).new()
	get_parent().add_child(ray)
	ray.set("element_id", _element)
	ray.call("strike", _aoe_target(), _element_color, 74.0, 34, Elements.effect_name(_element))
	rig.set_aim(Vector2.UP)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.7, _element)


## WARLOCK Q — Curse Chain: a shadow bolt leaps enemy-to-enemy from the aim.
func _curse_chain() -> void:
	var ch: Node2D = (load("res://scripts/combat/ChainBolt.gd") as GDScript).new()
	get_parent().add_child(ch)
	ch.set("element_id", _element)
	ch.call("chain", rig.get_weapon_tip(), _aim_dir.normalized(), _element_color, 4, 240.0, 30, Elements.effect_name(_element))
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.7, _element)


## Open the perfect-timing parry window (rogue only, off cooldown). The reward
## (ding + reflect) only fires if a bolt actually arrives during the window —
## see try_parry(). The opening itself is a quick blade-flash tell.
func _try_parry_start() -> void:
	if not bool(_cfg["can_parry"]):
		return  # class can't parry (mage)
	if _parry_cooldown_timer > 0.0:
		return
	_parry_window_timer = _parry_window_len
	_parry_cooldown_timer = PARRY_COOLDOWN
	# The Stick-Fight block: a white curved shield SHELL thrown up in the aim
	# direction (the tell), plus an arm-raise. No omni flash/burst.
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.set_parry(_aim_dir, PARRY_SHIELD_TIME)
	Sfx.play("melee_swing", -2.0, 0.1)


## Called by an incoming enemy bolt as it reaches the hero. If the parry window
## is open, reverse the bolt toward the nearest enemy (fallback: where the hero
## aims), pay out the reward juice (bright ding + hitstop + flash), and return
## true — the bolt keeps flying, now hostile to enemies. One reflect per window.
func try_parry(proj: Node) -> bool:
	if _parry_window_timer <= 0.0:
		return false
	if not is_instance_valid(proj) or not proj.has_method("reflect"):
		return false
	var target: Node2D = Targeting.nearest(global_position, get_tree().get_nodes_in_group("enemy"))
	var dir: Vector2 = _aim_dir
	if target != null:
		dir = (target.global_position - global_position).normalized()
	proj.reflect(dir, _element_color)
	Sfx.play("ding", 2.0, 0.02)  # the whole payoff — a crisp, loud parry ding
	Juice.hit_stop(0.09)
	Juice.shake_camera(4.0)
	# Snap the shield toward where the bolt was sent — a bright deflect flourish.
	rig.set_parry(dir, PARRY_SHIELD_TIME)
	rig.flash_color(PARRY_FLASH_COLOR, 0.1)
	_parry_window_timer = 0.0
	return true


func is_parrying() -> bool:
	return _parry_window_timer > 0.0


## Small white dust puff at the feet — jump kick-off + landing touchdown. The
## Stick-Fight jump/land dust; spawned a touch below the origin so it sits at the
## ground contact, not the torso.
func _spawn_foot_puff() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position + Vector2(0.0, 12.0),
		Color(1.0, 1.0, 1.0, 0.72), Color(1.0, 1.0, 1.0, 0.0),
		9, 0.28, 22.0, 95.0
	)


## Cooldown snapshot for the AbilityBar HUD — one dict per slot, in bar order.
## `enabled` false = the slot is dimmed (class can't use it): mage shows Nova,
## rogue shows Parry.
func ability_hud_state() -> Array:
	return [
		{"name": "Cast", "key": "LMB", "remaining": _cast_cooldown_timer, "total": float(_cfg["cast_cd"]), "enabled": true},
		{"name": "Dash", "key": "Spc", "remaining": _dash_cooldown_timer, "total": float(_cfg["dash_cd"]), "enabled": true},
		{"name": _aoe_slot_name(), "key": "Q", "remaining": _blast_cooldown_timer, "total": float(_cfg["blast_cd"]), "enabled": true},
		{"name": "Blink", "key": "R", "remaining": _blink_cooldown_timer, "total": float(_cfg["blink_cd"]), "enabled": true},
		{"name": "Nova", "key": "T", "remaining": _nova_cooldown_timer, "total": NOVA_COOLDOWN, "enabled": bool(_cfg["has_nova"])},
		{"name": "Parry", "key": "RMB", "remaining": _parry_cooldown_timer, "total": PARRY_COOLDOWN, "enabled": bool(_cfg["can_parry"])},
		# Signature ultimate — name updates as you cycle the loadout (V). Dimmed
		# when mana can't cover the cast; the floating MP bar shows the fill.
		_signature_hud_slot(),
	]


## Short HUD label for the Q slot, per the class's AoE variant.
func _aoe_slot_name() -> String:
	match String(_cfg["aoe"]):
		"nova": return "Whirl"
		"fist_shock": return "FirePunch"
		"ground_slam": return "Slam"
		"arcane_meteor": return "ArcaneStorm"
		"consecrate": return "Consecrate"
		"ice_shards": return "IceShards"
		"call_lightning": return "CallLightning"
		"curse_chain": return "CurseChain"
		_: return "Meteor"


## Class display name (Arcanist / Brawler / ...) for HUD / debug.
func class_display_name() -> String:
	return CLASS_NAMES[_hero_class] if _hero_class < CLASS_NAMES.size() else "Class"


## Hotbar slot for the equipped signature: short name (first word of the spell),
## the Ultimate key, its cooldown wipe, and dimmed when mana can't cover it.
func _signature_hud_slot() -> Dictionary:
	var sig: SpellDef = current_signature()
	if sig == null:
		return {"name": "Ult", "key": "G", "remaining": 0.0, "total": 0.0, "enabled": false}
	var short_name: String = sig.display_name.split(" ")[0]
	return {
		"name": short_name, "key": "G",
		"remaining": _signature_cd_timer, "total": maxf(sig.cooldown, 0.01),
		"enabled": mp >= float(sig.mp_cost),
	}


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
	_melee_cooldown_timer = _melee_cd
	if _melee_kick_next:
		rig.play(CharacterRig.State.KICK)
	else:
		rig.play(CharacterRig.State.PUNCH)
		rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.4, _element)  # fist ignites on the punch
	_melee_kick_next = not _melee_kick_next
	# A fire-element punch LIGHTS the fist: it stays lit + trails embers for ~1.6s.
	if int(_cfg.get("melee_element", -1)) == Elements.Element.FIRE:
		_flaming_fist_timer = FLAMING_FIST_TIME
	Sfx.play("melee_swing", 0.0, 0.08)


## Drive the persistent flaming fist: decay the timer, feed the rig the current
## fire strength, and trail small embers from the moving hand. Runs every frame.
func _update_flaming_fist(delta: float) -> void:
	if _flaming_fist_timer <= 0.0:
		return
	_flaming_fist_timer = maxf(_flaming_fist_timer - delta, 0.0)
	var s: float = clampf(_flaming_fist_timer / FLAMING_FIST_TIME, 0.0, 1.0)
	rig.set_hand_fire(s, Elements.Element.FIRE)
	var hand_pos: Vector2 = rig.get_lead_hand_global()
	_fist_ember_timer -= delta
	if _fist_ember_timer <= 0.0 and _last_hand_pos != Vector2.ZERO \
			and hand_pos.distance_to(_last_hand_pos) > 4.0:
		_fist_ember_timer = 0.045
		CombatVfx.spawn_burst(
			get_parent(), hand_pos,
			Color(1.3, 0.55, 0.15, 0.8 * s), Color(0.8, 0.2, 0.05, 0.0),
			3, 0.4, 20.0, 75.0, 0.6, 1.5, 0.0, 0.0, true
		)
	_last_hand_pos = hand_pos
	if _flaming_fist_timer <= 0.0:
		rig.set_hand_fire(0.0, Elements.Element.FIRE)  # snuff out


func _on_melee_hit_frame() -> void:
	var hit_any: bool = false
	var melee_el: int = int(_cfg.get("melee_element", -1))  # class element on the strike
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Node2D:
			continue
		if global_position.distance_to(enemy.global_position) >= _melee_range:
			continue
		var toward: Vector2 = (enemy.global_position - global_position).normalized()
		if facing.dot(toward) <= _melee_arc_dot:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(_melee_damage)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(toward * _melee_knockback)
		if melee_el >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(melee_el)  # burning / staggering / etc. fists
		hit_any = true
	# Crates break under melee too — same range/arc gate as enemies.
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if not prop is Node2D:
			continue
		if global_position.distance_to(prop.global_position) >= _melee_range:
			continue
		var toward_prop: Vector2 = (prop.global_position - global_position).normalized()
		if facing.dot(toward_prop) <= _melee_arc_dot:
			continue
		if prop.has_method("take_damage"):
			prop.take_damage(_melee_damage)
		hit_any = true
	# A swing also SWATS enemy bolts out of the air (punch-fizzles-bolt): same
	# range + facing-arc gate, so a well-timed punch is a melee "parry".
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if not proj is Node2D:
			continue
		if global_position.distance_to((proj as Node2D).global_position) >= _melee_range:
			continue
		var toward_proj: Vector2 = ((proj as Node2D).global_position - global_position).normalized()
		if facing.dot(toward_proj) <= _melee_arc_dot:
			continue
		if proj.has_method("consume"):
			proj.call("consume")
			hit_any = true
	if hit_any:
		# Unified hit juice (study §4) — heavier freeze than a spell hit + a punch
		# INTO the strike direction, all in sync.
		Juice.on_hit({
			"sfx": "melee_hit", "hitstop": _tune("melee_hit_stop", MELEE_HIT_STOP),
			"shake": 4.0, "dir": facing, "kick": MELEE_CAMERA_KICK,
		})
		Sfx.play("ding", -3.0, 0.05)  # the bright Stick-Fight "clean hit" ding


## Receive a shove (bomb blast / reflected bolt / slam). Same i-frame contract as
## take_damage — a dashing or just-blinked hero shrugs it off. The .y lands once as
## a real impulse; .x rides the decaying channel (added into velocity each frame).
func apply_knockback(impulse: Vector2, do_flop: bool = true) -> void:
	# Co-op: a shove computed on another peer is forwarded to this hero's owner.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_apply_knockback", impulse)
		return
	if is_dashing or _blink_iframe_timer > 0.0:
		return
	impulse *= _tune("knockback_mult", 1.6)  # global over-tune knob
	_knockback = impulse
	velocity.y += impulse.y
	# Reel from the blow (skip while the manual hold-DOWN ragdoll owns the limp,
	# and skip for self-recoil which passes do_flop=false).
	if do_flop and rig != null and impulse.length() > 12.0 and not _ragdolling:
		var mag: float = impulse.length()
		rig.flop(clampf(mag / 800.0, 0.2, 0.7), 0.18)
		rig.apply_impulse(impulse.normalized(), minf(mag, 800.0) * 0.85)


## Firing a big spell shoves the caster back (Stick-Fight recoil = power is
## dangerous). Horizontal-only + opposite the aim, so directed beams push you
## back while sky-aimed spells (aim.x ~ 0) barely recoil and vertical hops
## aren't fought. Routes through apply_knockback with do_flop=false (no self-flop).
func _self_recoil(amount: float) -> void:
	if absf(_aim_dir.x) < 0.15:
		return
	apply_knockback(Vector2(-signf(_aim_dir.x) * amount, 0.0), false)


## Slammed hard into a destructible/breakable this frame? Crack it (shared helper).
func _check_wall_slam() -> void:
	_knockback = SlamPhysics.check(self, _knockback)


func take_damage(amount: int) -> void:
	# Co-op: a hit computed on another peer (e.g. the host's enemy AI striking THIS
	# hero, whom the host only holds as a puppet) is forwarded to this hero's owner,
	# where its i-frames / parry / channel-break all resolve authoritatively. SP /
	# owner -> fall through and apply locally (byte-identical to before).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_take_damage", amount)
		return
	# Co-op: a downed hero is out of the fight — immune until revived.
	if downed:
		return
	# DESIGN: dash grants i-frames (full dash duration). Flip to
	# reposition-only by removing this guard.
	if is_dashing:
		return
	# Blink grants a brief post-teleport i-frame window (BLINK_IFRAME).
	if _blink_iframe_timer > 0.0:
		return
	# Perfect-parry window also BLOCKS a melee / contact / charge hit (deflect
	# punches, not just projectiles) — the reward is the same crisp ding + flash.
	if _parry_window_timer > 0.0:
		Sfx.play("ding", 2.0, 0.02)
		rig.flash_color(PARRY_FLASH_COLOR, 0.1)
		rig.set_parry(_aim_dir, PARRY_SHIELD_TIME)
		Juice.impact_frame(1.0)  # the DEFLECT beat — anime freeze-frame
		_parry_window_timer = 0.0
		return
	# A LANDED hit (not dodged/parried) shatters a float-channel OR a summon windup —
	# lose the ult (mana + cooldown already spent).
	if _channeling:
		_cancel_channel()
	if _summoning:
		_cancel_summon()
	# Gear: plate armour flatly reduces EVERY hit; a warding robe softens the FIRST hit.
	if _gear_damage_reduction > 0.0 and amount > 0:
		amount = int(round(float(amount) * (1.0 - _gear_damage_reduction)))
	if _gear_ward_frac > 0.0 and not _gear_ward_used and amount > 0:
		amount = int(round(float(amount) * (1.0 - _gear_ward_frac)))
		_gear_ward_used = true
		rig.flash_color(Color(0.75, 0.85, 1.0), 0.14)  # a pale ward shimmer
	hp = max(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, -18.0), amount, Color(1.0, 0.35, 0.35), amount >= 18)
	rig.play(CharacterRig.State.HURT)
	rig.flash_color(HURT_FLASH_COLOR, HURT_FLASH_TIME)
	rig.apply_impulse(Vector2(-facing.x, -0.7), 300.0)  # ragdoll flinch on the hit
	Juice.hit_stop(_tune("hurt_hit_stop", HURT_HIT_STOP))
	Juice.shake_camera(_tune("hurt_shake", HURT_SHAKE))
	Sfx.play("hero_hurt")
	if hp == 0:
		_die()


func _die() -> void:
	# In a run: a death is a FALL — drop 2 floors but stay in the tower (GameState
	# ticks the fall counter + saves; the Arena rebuilds the dropped floor in place
	# and revives us). In the standalone sandbox: just reset to full so the feel
	# loop never stops.
	# Co-op: go DOWNED (out of the fight, not gone). The Arena host watches for a full
	# party wipe -> drops the party a floor + revives everyone; a floor advance also
	# revives the downed. The owner drives its own downed state; it syncs to the others.
	if _net != null and _net.is_active():
		_enter_downed()
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.fall()
		return
	hp = max_hp
	health_changed.emit(hp, max_hp)


## Co-op: fall limp and drop out of the fight (immune, no input). hp stays 0. Cancels
## any in-flight channel/summon so nothing fires from a corpse.
func _enter_downed() -> void:
	downed = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	if _channeling:
		_cancel_channel()
	if _summoning:
		_cancel_summon()
	if is_instance_valid(rig):
		rig.set_limp(1.0)
		rig.apply_impulse(Vector2(-facing.x, -0.6), 260.0)  # a death flop
		rig.play(CharacterRig.State.HURT)
	Sfx.play("hero_hurt", 0.0, 0.1)


## Downed physics: just slump — gravity + friction to a stop, limp rig, no abilities.
func _process_downed(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
	if is_on_floor() and velocity.y >= 0.0:
		velocity.y = 0.0
	else:
		velocity.y = minf(velocity.y + GRAVITY_FALL * delta, MAX_FALL)
	move_and_slide()
	if is_instance_valid(rig):
		rig.set_body_velocity(velocity)
		rig.play(CharacterRig.State.HURT)


func is_downed() -> bool:
	return downed


## Full clean reset after a FALL (Arena calls this on the fell-respawn) so you
## resume upright — not mid-channel, on-cooldown, knocked-back, or ragdolling.
func revive() -> void:
	downed = false
	hp = max_hp
	health_changed.emit(hp, max_hp)
	_dash_cooldown_timer = 0.0
	_cast_cooldown_timer = 0.0
	_melee_cooldown_timer = 0.0
	_blast_cooldown_timer = 0.0
	_blink_cooldown_timer = 0.0
	_nova_cooldown_timer = 0.0
	_parry_cooldown_timer = 0.0
	_signature_cd_timer = 0.0
	if _channeling:
		_cancel_channel()
	if _summoning:
		_cancel_summon()
	_ragdolling = false
	_knockback = Vector2.ZERO
	velocity = Vector2.ZERO
	if is_instance_valid(rig):
		rig.set_limp(0.0)   # clear the downed ragdoll
		rig.play(CharacterRig.State.IDLE)


# ------------------------------------------------------------- co-op networking
## Camera + synchronizer role. Only in a live session; SP leaves the camera as-is.
func _setup_net_role() -> void:
	if _net == null or not _net.is_active():
		return
	_setup_net_sync()
	var cam := get_node_or_null("Camera2D") as Camera2D
	if is_multiplayer_authority():
		if cam != null:
			cam.make_current()   # the local hero owns the viewport
	elif cam != null:
		cam.enabled = false      # remote heroes never steal the view


## A MultiplayerSynchronizer that streams this hero's transform + state from its
## owner to every peer. Built in code (no .tscn surgery).
func _setup_net_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for p: String in [":position", ":velocity", ":facing", ":hp", ":net_class", ":downed"]:
		cfg.add_property(NodePath(p))
	cfg.property_set_replication_mode(NodePath(":position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(":velocity"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	sync.root_path = NodePath("..")   # relative to this Hero
	sync.replication_config = cfg
	add_child(sync)
	sync.set_multiplayer_authority(get_multiplayer_authority())


## Remote heroes animate from replicated velocity/facing; no input, no physics.
func _remote_visual(_delta: float) -> void:
	if not is_instance_valid(rig):
		return
	if downed:
		rig.set_limp(1.0)
		rig.play(CharacterRig.State.HURT)
		return
	rig.set_limp(0.0)
	rig.set_body_velocity(velocity)
	rig.set_facing(facing)
	rig.play(CharacterRig.State.RUN if absf(velocity.x) > 8.0 else CharacterRig.State.IDLE)


@rpc("any_peer", "call_remote", "reliable")
func _net_take_damage(amount: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
	take_damage(amount)


@rpc("any_peer", "call_remote", "reliable")
func _net_apply_knockback(impulse: Vector2) -> void:
	apply_knockback(impulse)


## Record the element behind an actual thrown ability into the run outcome
## (guarded — no-op in the sandbox).
func _notify_element_used() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.notify_element_used(Elements.display_name(_element))
