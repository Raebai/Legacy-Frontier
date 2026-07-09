extends Node2D
## Slice 0 combat sandbox. Keeps ~5 enemies alive so the fight never stops.

const ENEMY_SCENE: PackedScene = preload("res://scenes/combat/Enemy.tscn")
const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/combat/WeaponPickup.tscn")
const DESTRUCTIBLE_SCENE: PackedScene = preload("res://scenes/combat/DestructibleProp.tscn")
const WEAPON_PICKUP_POSITION: Vector2 = Vector2(560, 200)
## Crate scatter: interior positions, all >=120 px from the hero start (600,340)
## so nothing shatters in the player's face on frame one.
const CRATE_POSITIONS: Array[Vector2] = [
	Vector2(300, 180), Vector2(900, 180), Vector2(280, 520),
	Vector2(920, 500), Vector2(600, 140), Vector2(770, 470),
]
const TARGET_ENEMY_COUNT: int = 5
const ARENA_MIN: Vector2 = Vector2(80, 80)
const ARENA_MAX: Vector2 = Vector2(1120, 600)
const MIN_SPAWN_DISTANCE_FROM_HERO: float = 160.0
const SPAWN_POSITION_TRIES: int = 20

var _spawn_timer: float = 0.0


func _ready() -> void:
	# Slice 0 isolation: the hub's Conversation autoload still loads here and
	# its _unhandled_input steals Enter (`chat`) to open a broadcast text bar.
	# Disable just its input processing while the arena runs — the autoload
	# itself stays registered because Slice 1's hub merge depends on it.
	var conversation: Node = get_node_or_null("/root/Conversation")
	if conversation != null:
		conversation.set_process_unhandled_input(false)

	# Slice 1: one sword on the floor — walk over it to equip (feel toy).
	var pickup: Area2D = WEAPON_PICKUP_SCENE.instantiate()
	pickup.weapon_kind = "sword"
	add_child(pickup)
	pickup.global_position = WEAPON_PICKUP_POSITION

	# Destructible crates: cover to fight around, spectacle when they burst.
	for pos: Vector2 in CRATE_POSITIONS:
		var crate: StaticBody2D = DESTRUCTIBLE_SCENE.instantiate()
		add_child(crate)
		crate.global_position = pos


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 1.2
		if get_tree().get_nodes_in_group("enemy").size() < TARGET_ENEMY_COUNT:
			_spawn_enemy()


func _spawn_enemy() -> void:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	# Two archetypes, 50/50: fast/weak "chaser" vs slow/tanky "brute".
	if randf() < 0.5:
		e.max_hp = 24
		e.move_speed = 140.0
		e.touch_damage = 8
		e.tint = Color(0.95, 0.5, 0.25, 1)  # orange chaser
	else:
		e.max_hp = 70
		e.move_speed = 62.0
		e.touch_damage = 18
		e.tint = Color(0.7, 0.25, 0.45, 1)  # magenta brute
		e.uses_telegraphed_attack = true  # dodge-the-tell heavy strike
	add_child(e)
	e.global_position = _pick_spawn_position()


func _pick_spawn_position() -> Vector2:
	# Reject positions inside MIN_SPAWN_DISTANCE_FROM_HERO of the hero so an
	# enemy can never spawn straight into contact-damage range (review M2).
	var heroes: Array[Node] = get_tree().get_nodes_in_group("hero")
	var hero: Node2D = null
	if heroes.size() > 0:
		hero = heroes[0] as Node2D
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist: float = -1.0
	for i in SPAWN_POSITION_TRIES:
		var pos := Vector2(
			randf_range(ARENA_MIN.x, ARENA_MAX.x),
			randf_range(ARENA_MIN.y, ARENA_MAX.y)
		)
		if hero == null:
			return pos
		var dist: float = pos.distance_to(hero.global_position)
		if dist >= MIN_SPAWN_DISTANCE_FROM_HERO:
			return pos
		if dist > best_dist:
			best_dist = dist
			best_pos = pos
	# All tries were too close (hero effectively fills the arena):
	# fall back to the farthest candidate so spawning never hangs.
	return best_pos
