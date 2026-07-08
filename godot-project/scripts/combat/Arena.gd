extends Node2D
## Slice 0 combat sandbox. Keeps ~5 enemies alive so the fight never stops.

const ENEMY_SCENE: PackedScene = preload("res://scenes/combat/Enemy.tscn")
const TARGET_ENEMY_COUNT: int = 5
const ARENA_MIN: Vector2 = Vector2(80, 80)
const ARENA_MAX: Vector2 = Vector2(1120, 600)

var _spawn_timer: float = 0.0


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
	add_child(e)
	e.global_position = Vector2(
		randf_range(ARENA_MIN.x, ARENA_MAX.x),
		randf_range(ARENA_MIN.y, ARENA_MAX.y)
	)
