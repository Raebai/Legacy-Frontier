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
var _atmo: Atmosphere = null
var _portal: ExitPortal = null
var _return_portal: ExitPortal = null
const RETURN_PORTAL_COLOR: Color = Color(1.0, 0.85, 0.4)   # warm gold vs the cyan climb-exit
var _floor_banner: Label = null
var _pause_menu: PauseMenu = null
var _spawn_timer: float = 0.0


func _ready() -> void:
	# Slice 0 isolation: keep the hub's Conversation autoload from stealing Enter
	# while combat runs. (Re-enabled by World._ready on return to the hub.)
	var conversation: Node = get_node_or_null("/root/Conversation")
	if conversation != null:
		conversation.set_process_unhandled_input(false)
	# Music mood is chosen per-mode: run mode -> _setup_floor picks adventure/boss
	# from the floor type; sandbox -> adventure (below). (The hub set the town bed.)

	Atmosphere.add_glow(self)  # 2D bloom: pushed spell cores radiate
	_room = Node2D.new()
	_room.name = "Room"
	add_child(_room)
	_encounter = ENCOUNTER_SCRIPT.new()
	add_child(_encounter)
	_encounter.cleared.connect(_on_floor_cleared)
	_build_ability_bar()
	_build_pause_overlay()

	_gs = get_node_or_null("/root/GameState")
	_run_mode = _gs != null and _gs.is_run_active()
	if _run_mode:
		_build_theme_layer()
		_build_floor_banner()
		if not _gs.floor_advanced.is_connected(_on_floor_advanced):
			_gs.floor_advanced.connect(_on_floor_advanced)
		if not _gs.fell.is_connected(_on_fell):
			_gs.fell.connect(_on_fell)
		_setup_floor(_gs.current_floor())
	else:
		# Sandbox: the legacy default room + an endless trickle (below).
		FloorBuilder.build_props(_room, GameState.synthesize_floor_def(1).layout)
		var music: Node = get_node_or_null("/root/Music")
		if music != null and music.has_method("play_adventure"):
			music.play_adventure()


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
	_apply_floor_music()
	_rebuild_room()
	_clear_portal()
	var theme: EnvTheme = _resolve_theme()
	if theme != null:
		_apply_theme(theme.wash_tint)
	_show_floor_banner(floor, theme)
	_encounter.run_floor(_current_floor_def)


## Boss floors get the boss bed; everything else the adventure bed. Fires on
## every floor (re)build, so stepping onto floor 5 (BOSS) auto-swaps with a fade.
func _apply_floor_music() -> void:
	var music: Node = get_node_or_null("/root/Music")
	if music == null:
		return
	if _current_floor_def != null and _current_floor_def.floor_type == FloorDef.FloorType.BOSS:
		if music.has_method("play_boss"):
			music.play_boss()
	elif music.has_method("play_adventure"):
		music.play_adventure()


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
	var layout: LayoutDef = _current_floor_def.layout
	var exit_pt: Vector2 = DEFAULT_EXIT_POINT
	if layout != null:
		exit_pt = layout.exit_point
	_portal = EXIT_PORTAL_SCRIPT.new() as ExitPortal
	add_child(_portal)
	_portal.global_position = exit_pt
	_portal.taken.connect(_on_portal_taken)
	# A deliberate hub-return portal appears alongside the climb-exit on every
	# non-final floor. Clearing the BOSS floor is the conquer (the climb-exit's
	# advance path handles it), so no return portal there.
	if _gs.current_floor() < _gs.total_floors():
		var return_pt: Vector2 = Vector2(exit_pt.x, 520.0)
		if layout != null:
			return_pt = Vector2(layout.hero_start.x, layout.room_size.y - 120.0)
		_return_portal = EXIT_PORTAL_SCRIPT.new() as ExitPortal
		_return_portal.portal_label = "RETURN TO TOWN"
		_return_portal.ring_color = RETURN_PORTAL_COLOR
		_return_portal.trigger_group = "hero"
		add_child(_return_portal)
		_return_portal.global_position = return_pt
		_return_portal.taken.connect(_on_return_taken)


func _on_return_taken() -> void:
	_clear_portal()
	_gs.return_to_hub()


func _on_portal_taken() -> void:
	_clear_portal()
	# advance_floor climbs to the next floor (emits floor_advanced -> re-setup)
	# or ends the run in victory (scene change).
	_gs.advance_floor()


func _on_floor_advanced(new_floor: int) -> void:
	_setup_floor(new_floor)


## A fall landed us on an earlier floor: clear the current fight, rebuild the
## dropped floor, and revive the hero. Reuses the same floor-rebuild path as a
## normal climb — the only difference is we may have live enemies to clear.
func _on_fell(new_floor: int) -> void:
	_clear_portal()
	_clear_enemies()
	_setup_floor(new_floor)   # sets _current_floor_def to the dropped floor, respawns the fight
	_revive_hero()            # after _setup_floor so hero_start reflects the new floor
	_flash_fall(new_floor)    # a brief "YOU FELL" beat so the drop reads


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()


## Full-heal + reposition the hero to the (new) floor's start. MVP revive: HP +
## position. The active-ragdoll rig self-recovers from the death flinch.
func _revive_hero() -> void:
	var heroes: Array[Node] = get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		return
	var hero: Node2D = heroes[0] as Node2D
	if hero == null:
		return
	if hero.has_method("revive"):
		hero.call("revive")   # full clean reset: hp, cooldowns, channel/summon, ragdoll
	else:
		var full: int = int(hero.get("max_hp"))
		hero.set("hp", full)
		if hero.has_signal("health_changed"):
			hero.emit_signal("health_changed", full, full)
	var start: Vector2 = Vector2(600, 340)
	if _current_floor_def != null and _current_floor_def.layout != null:
		start = _current_floor_def.layout.hero_start
	hero.global_position = start


## A brief red "YOU FELL — dropped to Floor N" flash on a fall (fades after ~1.8s).
func _flash_fall(new_floor: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_top = 150.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "▼  YOU FELL  ▼\ndropped to Floor %d" % new_floor
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(0.96, 0.42, 0.36))
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.05, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)


func _clear_portal() -> void:
	if is_instance_valid(_portal):
		if _portal.taken.is_connected(_on_portal_taken):
			_portal.taken.disconnect(_on_portal_taken)
		_portal.queue_free()
	_portal = null
	if is_instance_valid(_return_portal):
		if _return_portal.taken.is_connected(_on_return_taken):
			_return_portal.taken.disconnect(_on_return_taken)
		_return_portal.queue_free()
	_return_portal = null


## MMO-style ability/cooldown hotbar. Reads the hero each frame and self-finds
## it via the "hero" group, so it works in both RUN and SANDBOX modes and simply
## draws nothing if no hero is present.
func _build_ability_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60  # above the floor banner (50), below Conversation (100)
	add_child(layer)
	layer.add_child(AbilityBar.new())
	# Mobile two-thumb touch pad (self-hides on desktop; keyboard/mouse unaffected).
	add_child(TouchControls.new())


## Pause overlay on its own ALWAYS layer so Resume/Settings/Exit work while the
## tree is paused. Esc toggles it; Exit bails to the hub (mid-floor = no bank).
func _build_pause_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90  # above the ability bar (60), below Conversation (100)
	add_child(layer)
	_pause_menu = PauseMenu.new()
	layer.add_child(_pause_menu)
	_pause_menu.build("Exit to Town")
	_pause_menu.resume_requested.connect(func() -> void: _set_paused(false))
	_pause_menu.exit_requested.connect(_exit_to_hub)


func _unhandled_input(event: InputEvent) -> void:
	# Arena is PAUSABLE, so this only fires while UNPAUSED -> it can only OPEN the
	# menu. The PauseMenu (ALWAYS) handles Esc-to-resume once the tree is paused.
	if event.is_action_pressed("ui_cancel") and not get_tree().paused:
		_set_paused(true)
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	if _pause_menu != null:
		if p:
			_pause_menu.open()
		else:
			_pause_menu.close()


## Leave the tower back to the hub. Mid-floor in a run -> abandon (no bank, resume
## here next time). Sandbox (no active run) -> straight to Main.tscn.
func _exit_to_hub() -> void:
	get_tree().paused = false
	if _gs != null and _gs.is_run_active() and _gs.has_method("abandon_to_hub"):
		_gs.abandon_to_hub()
	else:
		get_tree().change_scene_to_file("res://scenes/Main.tscn")


# ------------------------------------------------------------------- theme/UI
## Themed atmosphere per floor band (tint + vignette + drifting motes) so each
## layer of the climb reads distinct — richer than the old flat colour wash.
func _build_theme_layer() -> void:
	_atmo = Atmosphere.new()
	add_child(_atmo)


func _apply_theme(tint: Color) -> void:
	if _atmo != null:
		var accent: Color = Color(tint.r, tint.g, tint.b, 1.0).lightened(0.55)
		_atmo.build_wash(tint, accent)


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
	var label: String = "Floor %d / %d  ·  %s" % [floor, total, theme_name]
	if _current_floor_def != null and _current_floor_def.floor_type == FloorDef.FloorType.BOSS:
		label = "⚔  GUARDIAN  ⚔   ·   " + label
	_floor_banner.text = label
