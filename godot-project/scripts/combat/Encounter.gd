class_name Encounter
extends Node
## The floor's fight: owns enemy spawning (budget / concurrent-cap / pacing), the
## weighted archetype roll + stats, and spawn-point selection. Driven by a
## FloorDef. Emits `cleared` when the floor's whole budget is dead. Added as a
## child of the arena; enemies are spawned into the arena (get_parent()).
##
## Also exposes spawn() directly for the endless F6 SANDBOX (no floor budget).

signal cleared

const ENEMY_SCENE: PackedScene = preload("res://scenes/combat/Enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/combat/Boss.tscn")
const SPAWN_TRIES: int = 20
const SPAWN_INTERVAL: float = 0.55

# BOSS floor: one big GOLD guardian (BRUTE base — telegraphed heavy swing),
# hp scaled by the floor's hp_multiplier. A handful of adds trickle alongside;
# the floor clears only when the guardian AND every add are dead.
const BOSS_BASE_HP: int = 520
const BOSS_HEIGHT: float = 42.0       # rig height (visual size); collision stays clean
const BOSS_TOUCH_DAMAGE: int = 26
const BOSS_MOVE_SPEED: float = 66.0
const BOSS_TINT: Color = Color(0.95, 0.78, 0.25, 1)   # gold
const BOSS_ADD_BUDGET: int = 3        # the guardian is the star; only a few adds

# Spawn area (from the floor's LayoutDef; defaults match the legacy arena rect).
var _rect_min: Vector2 = Vector2(80, 80)
var _rect_max: Vector2 = Vector2(1120, 600)
var _min_dist: float = 160.0
# Finite-floor state.
var _budget: int = 0
var _spawned: int = 0
var _cap: int = 3
var _brute: float = 0.35
var _hp: float = 1.0
var _timer: float = 0.0
var _running: bool = false
var _done: bool = false


func configure(rect_min: Vector2, rect_max: Vector2, min_dist: float) -> void:
	_rect_min = rect_min
	_rect_max = rect_max
	_min_dist = min_dist


## Begin a finite floor from its FloorDef. A REST floor (budget 0) clears the
## instant it starts (nothing to fight).
func run_floor(floor_def: FloorDef) -> void:
	var layout: LayoutDef = floor_def.layout
	if layout != null:
		configure(layout.spawn_rect_min, layout.spawn_rect_max, layout.min_spawn_dist_from_hero)
	_budget = floor_def.enemy_budget
	_cap = floor_def.concurrent_cap
	_brute = floor_def.brute_chance
	_hp = floor_def.hp_multiplier
	_spawned = 0
	_timer = 0.0
	_done = false
	_running = true
	# BOSS floor: spawn the guardian up front + cut the add budget. The guardian
	# joins the "enemy" group, so the existing "alive == 0" clear gate waits for it.
	if floor_def.floor_type == FloorDef.FloorType.BOSS:
		_budget = mini(_budget, BOSS_ADD_BUDGET)
		spawn_boss(_hp)


func stop() -> void:
	_running = false


func _process(delta: float) -> void:
	if not _running or _done:
		return
	var alive: int = get_tree().get_nodes_in_group("enemy").size()
	if _spawned < _budget:
		_timer -= delta
		if _timer <= 0.0 and alive < _cap:
			_timer = SPAWN_INTERVAL
			spawn(_brute, _hp)
			_spawned += 1
	elif alive == 0:
		_done = true
		_running = false
		cleared.emit()


## Spawn the floor's GUARDIAN — a scaled-up gold BRUTE. Stats are set BEFORE
## add_child so _apply_archetype_defaults (which only fills still-default fields)
## leaves them; the rig height is bumped AFTER add_child (rig is @onready). Returns
## the guardian so a caller could wire a health banner / phase logic later.
func spawn_boss(hp_mult: float) -> Node:
	var e: CharacterBody2D = BOSS_SCENE.instantiate()
	e.max_hp = int(round(BOSS_BASE_HP * hp_mult))   # set pre-_ready so defaults don't override
	e.move_speed = BOSS_MOVE_SPEED
	e.touch_damage = BOSS_TOUCH_DAMAGE
	get_parent().add_child(e)   # Boss._ready installs rig height/tint/aura + adornment + bar + intro
	e.global_position = _boss_spawn_position()
	return e


## The guardian stands well to one side of the hero (toward centre) so the
## colossus reads as its own giant silhouette, not stacked on the player.
func _boss_spawn_position() -> Vector2:
	var center := Vector2((_rect_min.x + _rect_max.x) * 0.5, (_rect_min.y + _rect_max.y) * 0.5)
	var heroes: Array[Node] = get_tree().get_nodes_in_group("hero")
	if heroes.size() > 0 and heroes[0] is Node2D:
		var hx: float = (heroes[0] as Node2D).global_position.x
		var bx: float = hx + (300.0 if hx < center.x else -300.0)
		return Vector2(clampf(bx, _rect_min.x + 70.0, _rect_max.x - 70.0), center.y)
	return Vector2(clampf(center.x + 300.0, _rect_min.x, _rect_max.x), center.y)


## Spawn one enemy of a weighted-random archetype into the arena.
func spawn(brute_chance: float, hp_mult: float) -> void:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	_apply_archetype(e, _roll_archetype(brute_chance), hp_mult)
	get_parent().add_child(e)
	e.global_position = _pick_spawn_position()


## Weighted roll over ALL EIGHT archetypes. Chaser is the backbone; the tankier /
## trickier kinds (brute, summoner, assassin, bomber, mage) scale up with
## brute_chance — the FloorDef's floor-difficulty knob — so deeper floors get
## nastier and more varied. Insertion order is deterministic (GDScript dicts keep
## it), so the accumulate-until-r walk is stable.
func _roll_archetype(brute_chance: float) -> int:
	var weights: Dictionary = {
		0: 0.30,                          # CHASER — fast weak backbone
		1: 0.14 + 0.24 * brute_chance,    # BRUTE — telegraphed heavy
		2: 0.16,                          # CASTER — dodgeable bolt
		3: 0.13,                          # CHARGER — lane dash
		4: 0.03 + 0.07 * brute_chance,    # SUMMONER — rare threat-multiplier
		5: 0.06 + 0.08 * brute_chance,    # ASSASSIN — fast hit-and-run
		6: 0.04 + 0.06 * brute_chance,    # BOMBER — biggest telegraphed blast
		7: 0.05 + 0.08 * brute_chance,    # MAGE — telegraphed AoE
	}
	var total: float = 0.0
	for w: float in weights.values():
		total += w
	var r: float = randf() * total
	var acc: float = 0.0
	for kind: int in weights:
		acc += float(weights[kind])
		if r < acc:
			return kind
	return 0  # CHASER fallback


func _apply_archetype(e: CharacterBody2D, kind: int, hp_mult: float) -> void:
	e.archetype = kind
	match kind:
		1:  # BRUTE — slow, tanky, telegraphed heavy strike
			e.max_hp = int(round(70 * hp_mult))
			e.move_speed = 62.0
			e.touch_damage = 18
			e.tint = Color(0.7, 0.25, 0.45, 1)  # magenta
			e.uses_telegraphed_attack = true
		2:  # CASTER — kites and lobs a dodgeable bolt
			e.max_hp = int(round(30 * hp_mult))
			e.move_speed = 80.0
			e.touch_damage = 6
			e.tint = Color(0.55, 0.45, 0.95, 1)  # indigo
		3:  # CHARGER — telegraphs a lane then rockets down it
			e.max_hp = int(round(45 * hp_mult))
			e.move_speed = 55.0
			e.touch_damage = 10
			e.tint = Color(0.9, 0.6, 0.2, 1)  # amber
		4:  # SUMMONER — kites and telegraphs a minion summon; priority target
			e.max_hp = int(round(36 * hp_mult))
			e.move_speed = 72.0
			e.touch_damage = 6
			e.tint = Color(0.35, 0.8, 0.55, 1)  # jade
		5:  # ASSASSIN — fast, fragile hit-and-run, weaving approach
			e.max_hp = int(round(20 * hp_mult))
			e.move_speed = 175.0
			e.touch_damage = 8
			e.tint = Color(0.82, 0.86, 0.92, 1)  # silver
		6:  # BOMBER — walking bomb; roots and telegraphs the biggest blast
			e.max_hp = int(round(55 * hp_mult))
			e.move_speed = 70.0
			e.touch_damage = 6
			e.tint = Color(0.34, 0.35, 0.4, 1)  # charcoal
		7:  # MAGE — kites like a caster but telegraphs a ground AoE
			e.max_hp = int(round(34 * hp_mult))
			e.move_speed = 78.0
			e.touch_damage = 6
			e.tint = Color(0.5, 0.3, 0.85, 1)  # deep violet
		_:  # CHASER — fast, weak
			e.max_hp = int(round(24 * hp_mult))
			e.move_speed = 140.0
			e.touch_damage = 8
			e.tint = Color(0.95, 0.5, 0.25, 1)  # orange


func _pick_spawn_position() -> Vector2:
	# Reject positions within _min_dist of the hero so an enemy can never spawn
	# straight into contact-damage range.
	var heroes: Array[Node] = get_tree().get_nodes_in_group("hero")
	var hero: Node2D = null
	if heroes.size() > 0:
		hero = heroes[0] as Node2D
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist: float = -1.0
	for i in SPAWN_TRIES:
		var pos := Vector2(
			randf_range(_rect_min.x, _rect_max.x),
			randf_range(_rect_min.y, _rect_max.y)
		)
		if hero == null:
			return pos
		var dist: float = pos.distance_to(hero.global_position)
		if dist >= _min_dist:
			return pos
		if dist > best_dist:
			best_dist = dist
			best_pos = pos
	return best_pos
