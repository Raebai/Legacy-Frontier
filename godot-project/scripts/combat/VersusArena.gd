class_name VersusArena
extends Node2D
## Playable versus arena (Slice 3): P1 — the Hero — vs BOT_COUNT AI bots on a
## floating platform ringed by PIT hazards, Smash/Brawlhalla-style. Knock a
## fighter off the platform into a pit and it rings out: -1 stock, respawn at
## its own spawn point with a brief invuln window, eliminated at 0 stocks.
## Destructible cover blocks stand on the platform; SLOPE strips just inside
## the left/right rims slide anyone loitering there toward the nearest pit.
## Everything is built in _ready, in code — no .tscn (the Arena.gd /
## FloorBuilder programmatic-stage idiom).
##
## Ring-out flow: each PIT's fighter_fell routes to _on_fighter_fell, which
## looks the body up in _registry (instance_id -> stocks/spawn/invuln), burns
## a stock, then respawns or eliminates. RESPAWN_INVULN is belt-and-suspenders
## on top of the pit's own per-body dedup: moving a fighter to its spawn
## clears that dedup, so the invuln window is what stops anything re-reporting
## the same fighter from burning a second stock in the same beat.

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const ENEMY_SCENE_PATH: String = "res://scenes/combat/Enemy.tscn"

## -- Match rules -----------------------------------------------------------
const STAGE_SIZE: Vector2 = Vector2(900, 600)
const STOCKS: int = 3
const BOT_COUNT: int = 2
const RESPAWN_INVULN: float = 0.8

## -- Layout (stage-local; the stage centre is STAGE_SIZE * 0.5) -------------
## Width of the pit ring framing the platform on every side.
const PIT_MARGIN: float = 120.0
## P1 respawns dead centre — the safest spot on the platform, never in a pit.
const P1_SPAWN: Vector2 = STAGE_SIZE * 0.5
const BOT_SPAWN_POINTS: Array[Vector2] = [
	Vector2(260, 210), Vector2(640, 390), Vector2(640, 210), Vector2(260, 390),
]
## Bot archetype rotation: CASTER / SUMMONER / CHARGER — spell-slinging opponents
## (casters + summoners give you bolts to parry). See Enemy.Archetype.
const BOT_ARCHETYPES: Array[int] = [2, 4, 3]
## Versus bots are tankier than the tower's trash mobs so fights last.
const BOT_HP: int = 110
## Destructible cover blocks, spread across the platform (64px default size).
const COVER_POINTS: Array[Vector2] = [
	Vector2(340, 220), Vector2(560, 380), Vector2(450, 170),
]
## Edge slopes just inside the platform's left/right rims, each pointing at
## the pit it feeds: standing there slides you off.
const SLOPE_ZONE_SIZE: Vector2 = Vector2(60, 240)
const SLOPE_LAYOUT: Array[Dictionary] = [
	{"center": Vector2(150, 300), "dir": Vector2.LEFT},
	{"center": Vector2(750, 300), "dir": Vector2.RIGHT},
]
const SLOPE_STRENGTH: float = 140.0

## -- Look --------------------------------------------------------------------
const FLOOR_COLOR: Color = Color(0.16, 0.17, 0.22)
const FLOOR_BORDER_COLOR: Color = Color(0.52, 0.54, 0.64)
const FLOOR_BORDER_WIDTH: float = 3.0
const RESPAWN_POOF_START: Color = Color(0.75, 0.85, 1.0, 0.9)
const RESPAWN_POOF_END: Color = Color(0.75, 0.85, 1.0, 0.0)

## instance_id -> {"node": Node2D, "stocks": int, "spawn": Vector2 (global),
## "invuln": float}. Eliminated bots are erased; the eliminated hero stays
## registered at 0 stocks (the _match_over guard makes further falls no-ops).
var _registry: Dictionary = {}
var _p1: Node2D = null
var _match_over: bool = false
var _stocks_label: Label = null
var _banner: Label = null


func _ready() -> void:
	_build_floor()
	_build_cover()
	_build_hazards()
	_spawn_fighters()
	_build_hud()
	_update_hud()


func _process(delta: float) -> void:
	if _match_over:
		return
	for entry: Dictionary in _registry.values():
		entry["invuln"] = maxf(float(entry["invuln"]) - delta, 0.0)
	# Bots can also die to plain damage (Enemy._die -> queue_free), which never
	# routes through a pit — poll so that kill path ends the match too.
	if _bots_alive() == 0:
		_finish_match("VICTORY — P1 wins!")
	_update_hud()  # poll-don't-push (the AbilityBar idiom): always current


# -------------------------------------------------------------------- ring-out
## The core: a PIT reported `body` falling in. Unknown/freed bodies are
## ignored; a body still inside its respawn-invuln window burns nothing.
## Otherwise: -1 stock, then respawn (stocks left) or eliminate (none left).
func _on_fighter_fell(body: Node) -> void:
	if _match_over or body == null or not is_instance_valid(body):
		return
	var id: int = body.get_instance_id()
	if not _registry.has(id):
		return
	var entry: Dictionary = _registry[id]
	if float(entry["invuln"]) > 0.0:
		return
	entry["stocks"] = int(entry["stocks"]) - 1
	if int(entry["stocks"]) > 0:
		_respawn(body as Node2D, entry)
	else:
		_eliminate(body as Node2D, id)
	_update_hud()


## Back to this fighter's own spawn point (always on the platform — moving it
## also clears the pit's per-body dedup), hp refilled, invuln armed so an
## instant re-report can't burn a second stock, plus a small arrival poof.
func _respawn(body: Node2D, entry: Dictionary) -> void:
	entry["invuln"] = RESPAWN_INVULN
	body.global_position = entry["spawn"]
	var max_hp_v: Variant = body.get("max_hp")
	if max_hp_v != null:
		body.set("hp", max_hp_v)
		if body.has_signal("health_changed"):
			body.emit_signal("health_changed", int(max_hp_v), int(max_hp_v))
	CombatVfx.spawn_burst(
		self, entry["spawn"], RESPAWN_POOF_START, RESPAWN_POOF_END,
		16, 0.35, 50.0, 120.0, 1.5, 3.0
	)


## Out of stocks. Bots free + leave the registry (then check victory); P1
## stays in the tree — its camera is the viewport — but the match ends.
func _eliminate(body: Node2D, id: int) -> void:
	if body.is_in_group("enemy"):
		_registry.erase(id)
		body.queue_free()
		if _bots_alive() == 0:
			_finish_match("VICTORY — P1 wins!")
		return
	_finish_match("DEFEAT — the bots hold the stage")


## Bots still standing: registered, alive, and not mid-free. Ring-out
## eliminations leave the registry; damage kills go invalid/queued here.
func _bots_alive() -> int:
	var count: int = 0
	for entry: Dictionary in _registry.values():
		var node: Node = entry["node"]
		if is_instance_valid(node) and not node.is_queued_for_deletion() \
				and node.is_in_group("enemy") and int(entry["stocks"]) > 0:
			count += 1
	return count


## Latch _match_over + show the big centre banner. Idempotent — the first
## outcome to land wins; everything downstream early-outs on the flag.
func _finish_match(text: String) -> void:
	if _match_over:
		return
	_match_over = true
	if _banner != null:
		_banner.text = text
		_banner.visible = true
	_update_hud()


# ----------------------------------------------------------------------- build
## Platform rect in stage-local space: STAGE_SIZE minus the pit ring.
func _platform_rect() -> Rect2:
	var margin := Vector2(PIT_MARGIN, PIT_MARGIN)
	return Rect2(margin, STAGE_SIZE - margin * 2.0)


## Central platform: a border rect peeking out from under the floor rect.
## Plain ColorRects at negative z so fighters/hazards/cover all draw above;
## mouse_filter IGNORE so they never eat the hero's aim clicks.
func _build_floor() -> void:
	var rect: Rect2 = _platform_rect()
	var border := ColorRect.new()
	border.position = rect.position - Vector2(FLOOR_BORDER_WIDTH, FLOOR_BORDER_WIDTH)
	border.size = rect.size + Vector2(FLOOR_BORDER_WIDTH, FLOOR_BORDER_WIDTH) * 2.0
	border.color = FLOOR_BORDER_COLOR
	border.z_index = -10
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	var floor_rect := ColorRect.new()
	floor_rect.position = rect.position
	floor_rect.size = rect.size
	floor_rect.color = FLOOR_COLOR
	floor_rect.z_index = -9
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_rect)


## Real blocking cover that spells + melee chew through (group "destructible").
func _build_cover() -> void:
	for point: Vector2 in COVER_POINTS:
		var block := DestructibleTerrain.new()
		block.position = point
		add_child(block)


## PIT ring on all four sides — each wired to _on_fighter_fell — plus the two
## edge slopes that feed the left/right pits.
func _build_hazards() -> void:
	var pit_defs: Array[Dictionary] = [
		{"center": Vector2(PIT_MARGIN * 0.5, STAGE_SIZE.y * 0.5),
			"size": Vector2(PIT_MARGIN, STAGE_SIZE.y)},
		{"center": Vector2(STAGE_SIZE.x - PIT_MARGIN * 0.5, STAGE_SIZE.y * 0.5),
			"size": Vector2(PIT_MARGIN, STAGE_SIZE.y)},
		{"center": Vector2(STAGE_SIZE.x * 0.5, PIT_MARGIN * 0.5),
			"size": Vector2(STAGE_SIZE.x - PIT_MARGIN * 2.0, PIT_MARGIN)},
		{"center": Vector2(STAGE_SIZE.x * 0.5, STAGE_SIZE.y - PIT_MARGIN * 0.5),
			"size": Vector2(STAGE_SIZE.x - PIT_MARGIN * 2.0, PIT_MARGIN)},
	]
	for pit_def: Dictionary in pit_defs:
		var pit := StageHazard.new()
		pit.mode = StageHazard.Mode.PIT
		pit.zone_size = pit_def["size"]
		pit.position = pit_def["center"]
		pit.fighter_fell.connect(_on_fighter_fell)
		add_child(pit)
	for slope_def: Dictionary in SLOPE_LAYOUT:
		var slope := StageHazard.new()
		slope.mode = StageHazard.Mode.SLOPE
		slope.zone_size = SLOPE_ZONE_SIZE
		slope.slide_dir = slope_def["dir"]
		slope.slide_strength = SLOPE_STRENGTH
		slope.position = slope_def["center"]
		add_child(slope)


## Runtime load()s, never preload: both scenes' scripts reference autoload
## globals (Sfx/Rank/Juice), which only register with GDScript once the main
## loop is live — the headless slice-test harness load()s THIS script first,
## and a preload here would compile them too early (slice1_test_weapon idiom).
## Hero goes in first so each bot's _ready finds it via the "hero" group.
## Bot archetypes are set BEFORE add_child so Enemy._ready sees them.
func _spawn_fighters() -> void:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	_p1 = hero_scene.instantiate()
	_p1.position = P1_SPAWN
	add_child(_p1)
	_register_fighter(_p1, _p1.global_position)
	_frame_camera_on(_p1)
	var enemy_scene: PackedScene = load(ENEMY_SCENE_PATH)
	for i: int in BOT_COUNT:
		var bot: CharacterBody2D = enemy_scene.instantiate()
		bot.archetype = BOT_ARCHETYPES[i % BOT_ARCHETYPES.size()]
		bot.max_hp = BOT_HP  # set before add_child so Enemy._ready seeds hp = max_hp
		bot.position = BOT_SPAWN_POINTS[i % BOT_SPAWN_POINTS.size()]
		add_child(bot)
		_register_fighter(bot, bot.global_position)


## Clamp P1's follow-camera to the stage bounds so it frames the platform + pits
## instead of drifting into the void past the edges. Stage-local == global here
## (the VersusArena node sits at the scene origin). The Hero's camera is a
## Camera2D child of the Hero scene.
func _frame_camera_on(hero: Node) -> void:
	var cam: Camera2D = null
	for child: Node in hero.get_children():
		if child is Camera2D:
			cam = child as Camera2D
			break
	if cam == null:
		return
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(STAGE_SIZE.x)
	cam.limit_bottom = int(STAGE_SIZE.y)


## Registry seam (also driven by the headless test): every fighter enters the
## match with STOCKS stocks, its own respawn point, and no invuln.
func _register_fighter(body: Node2D, spawn: Vector2) -> void:
	_registry[body.get_instance_id()] = {
		"node": body,
		"stocks": STOCKS,
		"spawn": spawn,
		"invuln": 0.0,
	}


# ------------------------------------------------------------------------- HUD
## Screen-space HUD: the AbilityBar hotbar (self-finds the hero via group), a
## top-left stocks readout, and the hidden match-over banner.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60  # AbilityBar's home per Arena.gd — below Conversation (100)
	add_child(layer)
	layer.add_child(AbilityBar.new())
	_stocks_label = Label.new()
	_stocks_label.position = Vector2(14, 10)
	_stocks_label.add_theme_font_size_override("font_size", 13)
	_stocks_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 0.95))
	_stocks_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_stocks_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_stocks_label)
	# Banner sits near the TOP (was dead-center, covering the fight).
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 64.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.12, 0.95))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.visible = false
	layer.add_child(_banner)


func _update_hud() -> void:
	if _stocks_label == null:
		return
	var p1_stocks: int = 0
	if _p1 != null and is_instance_valid(_p1) and _registry.has(_p1.get_instance_id()):
		p1_stocks = int(_registry[_p1.get_instance_id()]["stocks"])
	_stocks_label.text = "P1 stocks: %d    Bots left: %d" % [p1_stocks, _bots_alive()]
