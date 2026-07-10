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
const SPAWN_TRIES: int = 20
const SPAWN_INTERVAL: float = 0.55

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


## Spawn one enemy of a weighted-random archetype into the arena.
func spawn(brute_chance: float, hp_mult: float) -> void:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	_apply_archetype(e, _roll_archetype(brute_chance), hp_mult)
	get_parent().add_child(e)
	e.global_position = _pick_spawn_position()


## Chaser is the backbone; brute weight rises with the floor; caster + charger
## add dodge-the-tell variety.
func _roll_archetype(brute_chance: float) -> int:
	var w_chaser: float = 0.32
	var w_brute: float = 0.18 + 0.30 * brute_chance
	var w_caster: float = 0.22
	var total: float = w_chaser + w_brute + w_caster + 0.28  # charger fills the rest
	var r: float = randf() * total
	if r < w_chaser:
		return 0  # CHASER
	if r < w_chaser + w_brute:
		return 1  # BRUTE
	if r < w_chaser + w_brute + w_caster:
		return 2  # CASTER
	return 3  # CHARGER


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
