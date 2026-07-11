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
## Bumped for the Stick-Fight "shove" read — a connected punch should visibly
## launch the target, not just tick it.
const MELEE_KNOCKBACK: float = 300.0
## Melee tuning per weapon kind; the MELEE_* consts are the "fists" baseline.
const WEAPON_STATS: Dictionary = {
	"fists": {"damage": MELEE_DAMAGE, "range": MELEE_RANGE, "knockback": MELEE_KNOCKBACK},
	"sword": {"damage": 26, "range": 60.0, "knockback": 400.0},
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
## Energy nova: self-centered instant shockwave — the "get off me" button.
const NOVA_COOLDOWN: float = 3.0
## Perfect-timing parry (rogue only): a short ACTIVE window that REVERSES an
## incoming enemy bolt back at the enemy side. Miss the window and you eat it.
const PARRY_WINDOW: float = 0.16
const PARRY_COOLDOWN: float = 0.9
const PARRY_FLASH_COLOR: Color = Color(0.8, 1.0, 1.0)
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
const AURA_STRENGTH: float = 0.6
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

## Two playable classes. MAGE = ranged zoner (homing bolt + giant telegraphed
## blast + panic nova). ROGUE = in-and-out assassin (fast light thrown blade,
## dash that STRIKES through enemies, snappy blink, a whirlwind AoE, no nova).
## Every rogue ability reuses a mage primitive; the mage config equals the old
## consts so the mage is byte-identical to before this change.
enum HeroClass { MAGE, ROGUE }
const CLASS_CONFIG: Dictionary = {
	HeroClass.MAGE: {
		"preset": "mage", "weapon": "",
		"cast_cd": CAST_COOLDOWN, "dash_cd": DASH_COOLDOWN, "blink_cd": BLINK_COOLDOWN,
		"blast_cd": BLAST_COOLDOWN,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "blast", "has_nova": true, "can_parry": false,
	},
	HeroClass.ROGUE: {
		"preset": "rogue", "weapon": "sword",
		"cast_cd": 0.26, "dash_cd": 0.40, "blink_cd": 1.0,
		"blast_cd": 2.5,
		"throw_blade": true, "blade_damage": 11,
		"dash_strike": true, "dash_strike_damage": 16, "dash_strike_range": 42.0,
		"aoe": "nova", "has_nova": false, "can_parry": true,
	},
}

@export var max_hp: int = 100
var hp: int = 100
## Twin-stick: `facing`/`_aim_dir` track the CURSOR (drive casts, melee arc, cast
## pose, camera peek); `_move_dir` tracks WASD (drives dash + blink dodge). They
## are decoupled so you can run one way while aiming/casting another (strafe).
var facing: Vector2 = Vector2.RIGHT
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
var _blast_cooldown_timer: float = 0.0
var _blink_cooldown_timer: float = 0.0
var _blink_iframe_timer: float = 0.0
var _nova_cooldown_timer: float = 0.0
var _parry_window_timer: float = 0.0
var _parry_cooldown_timer: float = 0.0
var _weapon: String = "fists"
var _melee_damage: int = MELEE_DAMAGE
var _melee_range: float = MELEE_RANGE
var _melee_knockback: float = MELEE_KNOCKBACK
var _buffered_action: String = ""
var _buffer_timer: float = 0.0
var _hero_class: int = HeroClass.MAGE
var _cfg: Dictionary = CLASS_CONFIG[HeroClass.MAGE]
var _dash_hit: Array = []  # enemies/props already struck this dash (rogue no-multi-hit)
## Active element (aura + ability colour). Cycled with `cycle_element` (X).
var _element: int = Elements.Element.ARCANE
var _element_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _colourway: int = 0

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
	# Class comes from GameState (hub selection) if present, else defaults MAGE.
	var gs: Node = get_node_or_null("/root/GameState")
	var start_class: int = HeroClass.MAGE
	if gs != null:
		var sc: Variant = gs.get("selected_class")
		if sc != null:
			start_class = int(sc)
	configure_class(start_class)
	_apply_element()
	# Rank drives aura TIER (elaborateness); the element keeps driving COLOUR.
	Rank.rank_changed.connect(_on_rank_changed)
	rig.set_aura_tier(Rank.tier())
	rig.hit_frame.connect(_on_melee_hit_frame)


func _physics_process(delta: float) -> void:
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)
	_cast_cooldown_timer = max(_cast_cooldown_timer - delta, 0.0)
	_melee_cooldown_timer = max(_melee_cooldown_timer - delta, 0.0)
	_blast_cooldown_timer = max(_blast_cooldown_timer - delta, 0.0)
	_blink_cooldown_timer = maxf(_blink_cooldown_timer - delta, 0.0)
	_blink_iframe_timer = maxf(_blink_iframe_timer - delta, 0.0)
	_nova_cooldown_timer = maxf(_nova_cooldown_timer - delta, 0.0)
	_parry_window_timer = maxf(_parry_window_timer - delta, 0.0)
	_parry_cooldown_timer = maxf(_parry_cooldown_timer - delta, 0.0)
	_update_input_buffer(delta)
	# Twin-stick aim: track the cursor every frame so casts / cast-pose / camera
	# peek use it even mid-dash. Movement (below) feeds _move_dir independently.
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length() > 1.0:
		_aim_dir = to_mouse.normalized()
	facing = _aim_dir
	# Cosmetic + class toggles: instant, un-buffered, legal even mid-dash.
	if Input.is_action_just_pressed("cycle_element"):
		_cycle_element()
	if Input.is_action_just_pressed("cycle_colourway"):
		_cycle_colourway()
	if Input.is_action_just_pressed("switch_class"):
		_cycle_class()
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
		rig.play(CharacterRig.State.DASH)
		rig.set_facing(facing)
		return

	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	if direction != Vector2.ZERO:
		_move_dir = direction

	if _try_fire_buffered():
		return  # a dash started this frame — the dash branch owns movement now

	# Accel/friction ramp for weight + flow (was an instant velocity snap).
	var target_v: Vector2 = direction * _tune("hero_speed", SPEED)
	velocity = velocity.move_toward(target_v, _tune("move_accel", 2600.0) * delta)
	move_and_slide()
	if direction != Vector2.ZERO:
		rig.play(CharacterRig.State.RUN)
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = 0.22 if _hero_class == HeroClass.ROGUE else 0.27
			Sfx.play("footstep", -6.0, 0.14)
	else:
		rig.play(CharacterRig.State.IDLE)
		_footstep_timer = 0.0
	rig.set_facing(facing)
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
	_dash_cooldown_timer = 0.0
	_cast_cooldown_timer = 0.0
	_blink_cooldown_timer = 0.0
	_blast_cooldown_timer = 0.0
	_nova_cooldown_timer = 0.0
	_parry_window_timer = 0.0
	_parry_cooldown_timer = 0.0
	_clear_input_buffer()


## Debug: cycle class live (Tab) and persist the choice to GameState so the hub
## selection and the next run stay in sync.
func _cycle_class() -> void:
	configure_class((_hero_class + 1) % HeroClass.size())
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.selected_class = _hero_class


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
	_dash_dir = _move_dir  # dodge toward MOVEMENT, not the cursor (twin-stick)
	_ghost_timer = 0.0  # first afterimage lands this frame
	_dash_hit.clear()


## Shadow blink: instant teleport up to BLINK_DISTANCE along facing, clamped
## so we never land inside a wall. Leaves a dark silhouette + violet poof at
## the origin, another poof + bright flash at the destination, and grants
## BLINK_IFRAME seconds of invulnerability. Buffered like dash/melee/blast;
## only reachable from the not-dashing path (same implicit gate as dash).
func _blink() -> void:
	if _blink_cooldown_timer > 0.0:
		return
	_blink_cooldown_timer = _cfg["blink_cd"]
	_blink_iframe_timer = BLINK_IFRAME
	var origin: Vector2 = global_position
	var dir: Vector2 = _move_dir.normalized()  # blink dodges toward movement
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
	_cast_cooldown_timer = _cfg["cast_cd"]
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	# Aim at the cursor, softly assisted toward an enemy inside the forgiveness
	# cone so you connect without pixel-hunting (twin-stick, touch-portable).
	var dir: Vector2 = Targeting.assisted_aim(global_position, _aim_dir, enemies)
	var spell: Area2D = SPELL_SCENE.instantiate()
	get_parent().add_child(spell)
	spell.global_position = global_position
	spell.launch(dir)
	if spell.has_method("set_element_color"):
		spell.call("set_element_color", _element_color)
	if bool(_cfg["throw_blade"]):
		spell.set("damage", int(_cfg["blade_damage"]))  # rogue: faster, lighter
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("cast", 0.0, 0.08)
	Juice.shake_camera(1.0)  # trimmed from 2.0 — casting shouldn't rattle the frame
	_notify_element_used()


func _blast() -> void:
	_blast_cooldown_timer = _cfg["blast_cd"]
	# Rogue's Q is a self-centered whirlwind (reuses the nova); mage's Q is the
	# targeted giant blast.
	if String(_cfg["aoe"]) == "nova":
		_spawn_nova()
		return
	# Directional: throw the giant blast toward the cursor. If an enemy sits
	# roughly under the reticle (within the aim cone + range), land it on them;
	# otherwise detonate at arm's length along the aim.
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	var aim: Vector2 = Targeting.assisted_aim(global_position, _aim_dir, enemies)
	var target_pos: Vector2 = global_position + aim * BLAST_FALLBACK_RANGE
	var best_d: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var to_e: Vector2 = e.global_position - global_position
		var dist: float = to_e.length()
		if dist <= 0.0 or dist > BLAST_FALLBACK_RANGE * 1.6:
			continue
		if aim.dot(to_e / dist) < 0.9:
			continue
		if dist < best_d:
			best_d = dist
			target_pos = e.global_position
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.detonate_at(target_pos)
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)


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
	nova.call("activate_at", global_position)
	rig.play(CharacterRig.State.CAST)


## Open the perfect-timing parry window (rogue only, off cooldown). The reward
## (ding + reflect) only fires if a bolt actually arrives during the window —
## see try_parry(). The opening itself is a quick blade-flash tell.
func _try_parry_start() -> void:
	if not bool(_cfg["can_parry"]):
		return  # class can't parry (mage)
	if _parry_cooldown_timer > 0.0:
		return
	_parry_window_timer = PARRY_WINDOW
	_parry_cooldown_timer = PARRY_COOLDOWN
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.flash_color(PARRY_FLASH_COLOR, PARRY_WINDOW)
	CombatVfx.spawn_burst(
		get_parent(), global_position + _aim_dir * 20.0,
		Color(PARRY_FLASH_COLOR.r, PARRY_FLASH_COLOR.g, PARRY_FLASH_COLOR.b, 0.8),
		Color(PARRY_FLASH_COLOR.r, PARRY_FLASH_COLOR.g, PARRY_FLASH_COLOR.b, 0.0),
		10, 0.2, 40.0, 90.0
	)
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
	rig.flash_color(PARRY_FLASH_COLOR, 0.14)
	_parry_window_timer = 0.0
	return true


func is_parrying() -> bool:
	return _parry_window_timer > 0.0


## Cooldown snapshot for the AbilityBar HUD — one dict per slot, in bar order.
## `enabled` false = the slot is dimmed (class can't use it): mage shows Nova,
## rogue shows Parry.
func ability_hud_state() -> Array:
	return [
		{"name": "Cast", "key": "LMB", "remaining": _cast_cooldown_timer, "total": float(_cfg["cast_cd"]), "enabled": true},
		{"name": "Dash", "key": "Spc", "remaining": _dash_cooldown_timer, "total": float(_cfg["dash_cd"]), "enabled": true},
		{"name": "AoE", "key": "Q", "remaining": _blast_cooldown_timer, "total": float(_cfg["blast_cd"]), "enabled": true},
		{"name": "Blink", "key": "R", "remaining": _blink_cooldown_timer, "total": float(_cfg["blink_cd"]), "enabled": true},
		{"name": "Nova", "key": "T", "remaining": _nova_cooldown_timer, "total": NOVA_COOLDOWN, "enabled": bool(_cfg["has_nova"])},
		{"name": "Parry", "key": "RMB", "remaining": _parry_cooldown_timer, "total": PARRY_COOLDOWN, "enabled": bool(_cfg["can_parry"])},
	]


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
		Juice.hit_stop(_tune("melee_hit_stop", MELEE_HIT_STOP))  # weighted: heavier than a spell hit
		Juice.shake_camera(4.0)
		Juice.kick_camera(facing, MELEE_CAMERA_KICK)  # punch INTO the hit
		Sfx.play("melee_hit")
		Sfx.play("ding", -3.0, 0.05)  # the bright Stick-Fight "clean hit" ding


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
	Juice.hit_stop(_tune("hurt_hit_stop", HURT_HIT_STOP))
	Juice.shake_camera(_tune("hurt_shake", HURT_SHAKE))
	Sfx.play("hero_hurt")
	if hp == 0:
		_die()


func _die() -> void:
	# In a run: death ends the run and bounces to the hub (GameState handles the
	# scene change + outcome record). In the standalone sandbox: just reset to
	# full so the feel loop never stops.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.end_run(true)
		return
	hp = max_hp
	health_changed.emit(hp, max_hp)


## Record the element behind an actual thrown ability into the run outcome
## (guarded — no-op in the sandbox).
func _notify_element_used() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.notify_element_used(Elements.display_name(_element))
