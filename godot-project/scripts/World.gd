extends Node2D
## SIDE-ON 2D town hub — same look + feel as the combat arena (maker: "the lobby
## needs to be the same style/format as the battle place, side-on all the time").
## A ground plane under the shared Atmosphere sky (gradient + tower spires +
## motes + vignette), cozy lantern-lit huts, a class-select STATUE, ambient NPCs
## that PATROL and stop when you walk up to talk, and the tower entrance. Replaces
## the old top-down two-room tilemap (the TileMapLayer is retired, kept only so the
## existing Main.tscn node refs stay valid).

const TOWN_WIDTH: float = 1180.0          # tighter — everything close, not spread out
const GROUND_Y: float = 452.0            # top surface of the ground
const GROUND_THICKNESS: float = 260.0
## Spawn AT the central campfire — the cozy heart. Class altar left, tower DOOR
## right, a raised loft (armory) up-left. Everything is close together.
const PLAYER_SPAWN: Vector2 = Vector2(560.0, GROUND_Y - 30.0)
const CAMPFIRE_X: float = 600.0                       # the heart of the clearing
const CLASS_ALTAR_X: float = 400.0
const TOWER_X: float = 880.0
const RAEBAI_X: float = 500.0
const MIRELLE_X: float = 720.0
const NPC_PATROL_RANGE: float = 75.0
## Second-floor LOFT (the armory) — a raised deck reachable by a step, up-left.
const LOFT_CENTER: Vector2 = Vector2(215.0, GROUND_Y - 118.0)
const LOFT_SIZE: Vector2 = Vector2(300.0, 16.0)
const STEP_CENTER: Vector2 = Vector2(330.0, GROUND_Y - 58.0)
const STEP_SIZE: Vector2 = Vector2(120.0, 14.0)
const TOWER_DOOR_SCRIPT: Script = preload("res://scripts/TowerDoor.gd")
const ARMORY_SCRIPT: Script = preload("res://scripts/ArmoryStation.gd")

const GROUND_COLOR: Color = Color(0.10, 0.11, 0.13)   # dark mossy forest floor
const GROUND_RIM: Color = Color(0.3, 0.55, 0.42)      # faint mystic teal rim

## Tower entrance + class altar sit on the ground; the mystic-forest ambience
## (stars, trees, campfire, fireflies) is a HubAmbience node.
const RUN_PORTAL_SCRIPT: Script = preload("res://scripts/combat/ExitPortal.gd")
const CLASS_ALTAR_SCRIPT: Script = preload("res://scripts/ClassAltar.gd")
const HUB_AMBIENCE_SCRIPT: Script = preload("res://scripts/HubAmbience.gd")

@onready var tilemap: TileMapLayer = $TileMapLayer


func _ready() -> void:
	tilemap.visible = false  # retire the top-down grass tiles

	# Returning from the combat arena, the shared Conversation autoload had its
	# input disabled by Arena._ready — turn it back on so the hub chat works.
	var conversation: Node = get_node_or_null("/root/Conversation")
	if conversation != null:
		conversation.set_process_unhandled_input(true)

	_build_backdrop()
	_build_ground()
	_build_loft()
	_spawn_ambience()
	_place_player()
	_place_npcs()
	_spawn_tower_entrance()
	_spawn_class_altar()
	_spawn_class_hud()
	_reflect_selected_class()

	# Swap the music bed to the calm mystic-forest ambience for the lobby.
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_hub"):
		music.play_hub()

	# The moat: push the just-finished run into the hub NPCs' durable memory so
	# Raebai/Mirelle can reference it. No-op on a cold boot (no run yet).
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("apply_run_to_hub_npcs"):
		gs.apply_run_to_hub_npcs(get_tree())


# ------------------------------------------------------------------- environment
## The shared epic backdrop (gradient sky + distant tower spires + motes +
## vignette) — identical to the arena so the hub reads as the same world.
func _build_backdrop() -> void:
	# Mystic NIGHT palette (deep indigo -> dusky teal) so the stars + campfire pop.
	var atmo := Atmosphere.new()
	add_child(atmo)
	atmo.build(Rect2(Vector2(-400.0, -320.0), Vector2(TOWN_WIDTH + 800.0, GROUND_Y + 760.0)), {
		"sky_top": Color(0.03, 0.04, 0.11),
		"sky_bottom": Color(0.10, 0.16, 0.24),
		"silhouette_far": Color(0.06, 0.10, 0.16),
		"silhouette_near": Color(0.03, 0.06, 0.10),
		"accent": Color(0.5, 0.85, 0.8),
	})


## The mystic-forest ambience: starfield, tree silhouettes, central campfire,
## fireflies + rising embers.
func _spawn_ambience() -> void:
	var amb: Node2D = HUB_AMBIENCE_SCRIPT.new()
	add_child(amb)
	amb.call("build", TOWN_WIDTH, GROUND_Y, CAMPFIRE_X)


## A solid ground plane spanning the town (StaticBody2D layer 1 so the side-on
## player stands + jumps on it), with a warm gradient body + a bright lit top rim.
func _build_ground() -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(TOWN_WIDTH * 0.5, GROUND_Y + GROUND_THICKNESS * 0.5)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TOWN_WIDTH + 200.0, GROUND_THICKNESS)
	cs.shape = shape
	body.add_child(cs)
	var grad := Gradient.new()
	grad.set_color(0, GROUND_COLOR.lightened(0.10))
	grad.set_color(1, GROUND_COLOR.darkened(0.4))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = shape.size
	rect.position = -shape.size * 0.5
	rect.z_index = -5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rect)
	# Bright lit top rim (the town is lantern-lit — warm, homely).
	var rim := ColorRect.new()
	rim.color = GROUND_RIM
	rim.size = Vector2(shape.size.x, 4.0)
	rim.position = Vector2(-shape.size.x * 0.5, -shape.size.y * 0.5)
	rim.z_index = -4
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rim)
	add_child(body)


# --------------------------------------------------------------------- placement
## Move the pre-instanced Player onto the ground at the spawn point + frame the
## side-on camera to the town.
func _place_player() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player is Node2D:
		return
	(player as Node2D).global_position = PLAYER_SPAWN
	for c: Node in player.get_children():
		if c is Camera2D:
			var cam := c as Camera2D
			cam.limit_left = 0
			cam.limit_top = -260
			cam.limit_right = int(TOWN_WIDTH)
			cam.limit_bottom = int(GROUND_Y + 60.0)
			cam.zoom = Vector2(1.2, 1.2)
			cam.offset = Vector2(0.0, -44.0)  # look UP so the starry sky frames in


## Place the two anchor NPCs on the ground + give them a patrol range so they
## amble around town (and pause when you walk up — set in NPC.set_hub_patrol).
func _place_npcs() -> void:
	var centers: Dictionary = {"raebai": RAEBAI_X, "mirelle": MIRELLE_X}
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not npc is Node2D:
			continue
		var id: String = ""
		var data: Variant = npc.get("data")
		if data != null and "npc_id" in data:
			id = String(data.npc_id)
		var x: float = float(centers.get(id, (npc as Node2D).global_position.x))
		(npc as Node2D).global_position = Vector2(x, GROUND_Y)
		if npc.has_method("set_hub_patrol"):
			npc.call("set_hub_patrol", x, NPC_PATROL_RANGE)


# ----------------------------------------------------------------- interactables
## The tower DOOR — a walk-up, press-E entrance (not a walk-in circle) on the
## ground at the right of the clearing.
func _spawn_tower_entrance() -> void:
	var door: StaticBody2D = TOWER_DOOR_SCRIPT.new()
	add_child(door)
	door.global_position = Vector2(TOWER_X, GROUND_Y)


## Second-floor LOFT (the armory deck) + a step up to it, both solid platforms, with
## an Armory station on top — a raised area for gear so the hub has depth.
func _build_loft() -> void:
	_make_platform(LOFT_CENTER, LOFT_SIZE)
	_make_platform(STEP_CENTER, STEP_SIZE)
	var armory: StaticBody2D = ARMORY_SCRIPT.new()
	add_child(armory)
	armory.global_position = Vector2(LOFT_CENTER.x, LOFT_CENTER.y - LOFT_SIZE.y * 0.5)


## A solid wooden platform (dark body + a warm-lit top rim), matching the ground.
func _make_platform(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var rect := ColorRect.new()
	rect.color = Color(0.14, 0.12, 0.11)
	rect.size = size
	rect.position = -size * 0.5
	rect.z_index = -5
	body.add_child(rect)
	var rim := ColorRect.new()
	rim.color = GROUND_RIM
	rim.size = Vector2(size.x, 3.0)
	rim.position = Vector2(-size.x * 0.5, -size.y * 0.5)
	rim.z_index = -4
	body.add_child(rim)
	add_child(body)


## The Class Altar STATUE — walk up + E opens the ClassSelect lobby panel.
func _spawn_class_altar() -> void:
	var altar: StaticBody2D = CLASS_ALTAR_SCRIPT.new()
	add_child(altar)
	altar.global_position = Vector2(CLASS_ALTAR_X, GROUND_Y)


## A small always-visible HUD label showing the chosen class in the hub.
func _spawn_class_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var label := Label.new()
	label.add_to_group("class_hud_label")
	label.position = Vector2(14, 10)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)


## Reflect the persisted class on hub entry: tint the player + set the HUD label.
func _reflect_selected_class() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var idx: int = int(gs.get("selected_class")) if gs != null else 0
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_class_tint"):
		player.call("set_class_tint", ClassInfo.color_for(idx))
	for label: Node in get_tree().get_nodes_in_group("class_hud_label"):
		if label is Label:
			(label as Label).text = "Class: %s" % ClassInfo.name_for(idx)
