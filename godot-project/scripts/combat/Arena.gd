extends Node2D
## Thin arena coordinator. Two modes:
##  - RUN mode (a GameState run is active): each floor is a FloorDef. Build the
##    room (FloorBuilder) + run the fight (Encounter); on clear, open the EXIT
##    portal; take it to climb. Difficulty/theme/layout all come from data.
##  - SANDBOX mode (F6, no active run): the endless ~5-enemy feel toy.
## The heavy lifting lives in FloorBuilder (room props) and Encounter (spawning);
## this script just wires them to the run loop + theme + banner.

const EXIT_PORTAL_SCRIPT: Script = preload("res://scripts/combat/ExitPortal.gd")
const ENCOUNTER_SCRIPT: Script = preload("res://scripts/combat/Encounter.gd")
const TARGET_ENEMY_COUNT: int = 5   # sandbox steady-state
const SANDBOX_SPAWN_INTERVAL: float = 1.2
const DEFAULT_EXIT_POINT: Vector2 = Vector2(600, 130)

var _gs: Node = null
var _run_mode: bool = false
var _current_floor_def: FloorDef = null
var _encounter: Encounter = null
var _room: Node2D = null
var _theme_rect: ColorRect = null
var _portal: ExitPortal = null
var _floor_banner: Label = null
var _spawn_timer: float = 0.0


func _ready() -> void:
	# Slice 0 isolation: keep the hub's Conversation autoload from stealing Enter
	# while combat runs. (Re-enabled by World._ready on return to the hub.)
	var conversation: Node = get_node_or_null("/root/Conversation")
	if conversation != null:
		conversation.set_process_unhandled_input(false)

	_room = Node2D.new()
	_room.name = "Room"
	add_child(_room)
	_encounter = ENCOUNTER_SCRIPT.new()
	add_child(_encounter)
	_encounter.cleared.connect(_on_floor_cleared)

	_gs = get_node_or_null("/root/GameState")
	_run_mode = _gs != null and _gs.is_run_active()
	if _run_mode:
		_build_theme_layer()
		_build_floor_banner()
		if not _gs.floor_advanced.is_connected(_on_floor_advanced):
			_gs.floor_advanced.connect(_on_floor_advanced)
		_setup_floor(_gs.current_floor())
	else:
		# Sandbox: the legacy default room + an endless trickle (below).
		FloorBuilder.build_props(_room, GameState.synthesize_floor_def(1).layout)


func _process(delta: float) -> void:
	if _run_mode:
		return  # Encounter drives the finite floor; nothing to poll here
	# Sandbox trickle: keep ~TARGET_ENEMY_COUNT alive forever.
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SANDBOX_SPAWN_INTERVAL
		if get_tree().get_nodes_in_group("enemy").size() < TARGET_ENEMY_COUNT:
			_encounter.spawn(0.5, 1.0)


# ---------------------------------------------------------------------- RUN
func _setup_floor(floor: int) -> void:
	_current_floor_def = _gs.floor_def_for(floor)
	_rebuild_room()
	_clear_portal()
	var theme: EnvTheme = _resolve_theme()
	if theme != null:
		_apply_theme(theme.wash_tint)
	_show_floor_banner(floor, theme)
	_encounter.run_floor(_current_floor_def)


## A floor's theme, falling back to the tower default, then null.
func _resolve_theme() -> EnvTheme:
	if _current_floor_def.theme != null:
		return _current_floor_def.theme
	if _gs.active_tower != null:
		return _gs.active_tower.theme
	return null


## Fresh room each floor: free the old props, build the new floor's props.
func _rebuild_room() -> void:
	for child in _room.get_children():
		child.queue_free()
	FloorBuilder.build_props(_room, _current_floor_def.layout)


func _on_floor_cleared() -> void:
	if not _run_mode:
		return
	var exit_pt: Vector2 = DEFAULT_EXIT_POINT
	if _current_floor_def.layout != null:
		exit_pt = _current_floor_def.layout.exit_point
	_portal = EXIT_PORTAL_SCRIPT.new() as ExitPortal
	add_child(_portal)
	_portal.global_position = exit_pt
	_portal.taken.connect(_on_portal_taken)


func _on_portal_taken() -> void:
	_clear_portal()
	# advance_floor climbs to the next floor (emits floor_advanced -> re-setup)
	# or ends the run in victory (scene change).
	_gs.advance_floor()


func _on_floor_advanced(new_floor: int) -> void:
	_setup_floor(new_floor)


func _clear_portal() -> void:
	if is_instance_valid(_portal):
		if _portal.taken.is_connected(_on_portal_taken):
			_portal.taken.disconnect(_on_portal_taken)
		_portal.queue_free()
	_portal = null


# ------------------------------------------------------------------- theme/UI
## Subtle full-viewport atmosphere wash so each layer band reads distinct.
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


func _show_floor_banner(floor: int, theme: EnvTheme) -> void:
	if _floor_banner == null:
		return
	var total: int = GameState.TOTAL_FLOORS
	if _gs.active_tower != null:
		total = _gs.active_tower.floors.size()
	var theme_name: String = theme.name if theme != null else "?"
	_floor_banner.text = "Floor %d / %d  ·  %s" % [floor, total, theme_name]
