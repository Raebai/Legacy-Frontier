extends Node2D
## Combat arena. Two modes:
##  - RUN mode (a GameState run is active): finite enemies per FLOOR, clear them
##    all to open the EXIT, take the exit to climb to the next floor; clear the
##    last floor to win, die to lose. Difficulty + theme ramp per floor.
##  - SANDBOX mode (launched standalone via F6, no active run): the original
##    Slice 0/1 endless ~5-enemy trickle — the pure feel toy, unchanged.

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
const TARGET_ENEMY_COUNT: int = 5   # sandbox steady-state
const ARENA_MIN: Vector2 = Vector2(80, 80)
const ARENA_MAX: Vector2 = Vector2(1120, 600)
const MIN_SPAWN_DISTANCE_FROM_HERO: float = 160.0
const SPAWN_POSITION_TRIES: int = 20
const EXIT_PORTAL_POSITION: Vector2 = Vector2(600, 130)
const EXIT_PORTAL_SCRIPT: Script = preload("res://scripts/combat/ExitPortal.gd")

var _spawn_timer: float = 0.0
var _gs: Node = null
var _run_mode: bool = false
# Floor state (run mode only).
var _floor_budget: int = 0     # total enemies this floor
var _floor_spawned: int = 0    # spawned so far this floor
var _floor_cleared: bool = false
var _brute_chance: float = 0.5
var _theme_rect: ColorRect = null
var _portal: ExitPortal = null
var _floor_banner: Label = null


func _ready() -> void:
	# Slice 0 isolation: keep the hub's Conversation autoload from stealing Enter
	# while combat runs. (Re-enabled by World._ready on return to the hub.)
	var conversation: Node = get_node_or_null("/root/Conversation")
	if conversation != null:
		conversation.set_process_unhandled_input(false)

	# One sword on the floor — walk over it to equip (feel toy, both modes).
	var pickup: Area2D = WEAPON_PICKUP_SCENE.instantiate()
	pickup.weapon_kind = "sword"
	add_child(pickup)
	pickup.global_position = WEAPON_PICKUP_POSITION

	# Destructible crates: cover to fight around, spectacle when they burst.
	for pos: Vector2 in CRATE_POSITIONS:
		var crate: StaticBody2D = DESTRUCTIBLE_SCENE.instantiate()
		add_child(crate)
		crate.global_position = pos

	_gs = get_node_or_null("/root/GameState")
	_run_mode = _gs != null and _gs.is_run_active()
	if _run_mode:
		_build_theme_layer()
		_build_floor_banner()
		if not _gs.floor_advanced.is_connected(_on_floor_advanced):
			_gs.floor_advanced.connect(_on_floor_advanced)
		_setup_floor(_gs.current_floor())


func _process(delta: float) -> void:
	if _run_mode:
		_process_run(delta)
	else:
		_process_sandbox(delta)


# ------------------------------------------------------------------- SANDBOX
func _process_sandbox(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 1.2
		if get_tree().get_nodes_in_group("enemy").size() < TARGET_ENEMY_COUNT:
			_spawn_enemy(0.5, 1.0)


# ---------------------------------------------------------------------- RUN
func _setup_floor(floor: int) -> void:
	_floor_budget = GameState.floor_enemy_budget(floor)
	_floor_spawned = 0
	_floor_cleared = false
	_brute_chance = GameState.floor_brute_chance(floor)
	_spawn_timer = 0.0
	_clear_portal()
	_apply_theme(GameState.floor_theme_tint(floor))
	_show_floor_banner(floor)


func _process_run(delta: float) -> void:
	if _floor_cleared:
		return
	var alive: int = get_tree().get_nodes_in_group("enemy").size()
	if _floor_spawned < _floor_budget:
		_spawn_timer -= delta
		var cap: int = GameState.floor_concurrent_cap(_gs.current_floor())
		if _spawn_timer <= 0.0 and alive < cap:
			_spawn_timer = 0.55
			# Deeper floors: tankier enemies, more brutes.
			var hp_mult: float = 1.0 + 0.15 * float(_gs.current_floor() - 1)
			_spawn_enemy(_brute_chance, hp_mult)
			_floor_spawned += 1
	elif alive == 0:
		_on_floor_cleared()


func _on_floor_cleared() -> void:
	_floor_cleared = true
	_portal = EXIT_PORTAL_SCRIPT.new() as ExitPortal
	add_child(_portal)
	_portal.global_position = EXIT_PORTAL_POSITION
	_portal.taken.connect(_on_portal_taken)


func _on_portal_taken() -> void:
	_clear_portal()
	# advance_floor either climbs to the next floor (emits floor_advanced ->
	# _on_floor_advanced repopulates) or ends the run in victory (scene change).
	_gs.advance_floor()


func _on_floor_advanced(new_floor: int) -> void:
	_setup_floor(new_floor)


func _clear_portal() -> void:
	if is_instance_valid(_portal):
		if _portal.taken.is_connected(_on_portal_taken):
			_portal.taken.disconnect(_on_portal_taken)
		_portal.queue_free()
	_portal = null


# Subtle full-viewport atmosphere wash so each layer band reads distinct.
func _build_theme_layer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1  # above the world, below the Rank HUD (50) + Conversation (100)
	add_child(layer)
	_theme_rect = ColorRect.new()
	_theme_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_theme_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_theme_rect.color = Color(0, 0, 0, 0)
	layer.add_child(_theme_rect)


func _apply_theme(tint: Color) -> void:
	if _theme_rect != null:
		_theme_rect.color = Color(tint.r, tint.g, tint.b, 0.14)


func _build_floor_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_floor_banner = Label.new()
	_floor_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_floor_banner.offset_top = 22.0
	_floor_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_banner.add_theme_font_size_override("font_size", 13)
	_floor_banner.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 0.95))
	_floor_banner.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_floor_banner.add_theme_constant_override("outline_size", 4)
	layer.add_child(_floor_banner)


func _show_floor_banner(floor: int) -> void:
	if _floor_banner == null:
		return
	var theme_name: String = GameState.floor_theme(floor)
	_floor_banner.text = "Floor %d / %d  ·  %s" % [floor, GameState.TOTAL_FLOORS, theme_name]


# ------------------------------------------------------------------- shared
## Spawn one enemy of a weighted-random archetype. `brute_chance` biases the
## brute weight (deeper floors -> tankier mix); `hp_mult` scales HP for depth
## (1.0 in sandbox). All four archetypes appear in both modes.
func _spawn_enemy(brute_chance: float, hp_mult: float) -> void:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	_apply_archetype(e, _roll_archetype(brute_chance), hp_mult)
	add_child(e)
	e.global_position = _pick_spawn_position()


## Weighted archetype roll. Chaser is the backbone; brute weight rises with the
## floor; caster + charger add dodge-the-tell variety.
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
	# All tries too close (hero fills the arena): farthest candidate.
	return best_pos
