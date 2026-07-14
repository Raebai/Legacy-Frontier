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
const STAGE_SIZE: Vector2 = Vector2(1200, 760)
const STOCKS: int = 3
const BOT_COUNT: int = 5
const RESPAWN_INVULN: float = 0.8

## -- Side-on stage layout (stage-local; the arena node sits at the scene origin) --
## Solid platforms (StaticBody2D, default layer 1 — the hero/enemy masks collide
## with it) the fighters land + jump on: a wide ground plus two floating ledges.
const PLATFORMS: Array[Dictionary] = [
	{"center": Vector2(600, 600), "size": Vector2(780, 60)},  # main ground (top ~570)
	{"center": Vector2(360, 410), "size": Vector2(210, 26)},  # left ledge
	{"center": Vector2(840, 410), "size": Vector2(210, 26)},  # right ledge
]
## Blast zones (StageHazard PIT): fall below the stage or get knocked off the
## sides = ring-out. No top zone — you can jet up freely.
const BLAST_ZONES: Array[Dictionary] = [
	{"center": Vector2(600, 850), "size": Vector2(2000, 260)},   # the void below
	{"center": Vector2(-150, 400), "size": Vector2(260, 1200)},  # off the left
	{"center": Vector2(1350, 400), "size": Vector2(260, 1200)},  # off the right
]
## Fighters spawn ABOVE the ground and drop onto it.
const P1_SPAWN: Vector2 = Vector2(600, 480)
const BOT_SPAWN_POINTS: Array[Vector2] = [
	Vector2(400, 430), Vector2(800, 430), Vector2(360, 330), Vector2(840, 330),
	Vector2(600, 500),  # centre, drops to the main ground — the MAGE / leap demo
]
## Bot archetype rotation — a varied roster so every fight reads different:
## CASTER(2) / SUMMONER(4) / ASSASSIN(5) / BOMBER(6) / CHARGER(3). Tints + speeds
## come from Enemy's per-archetype defaults. See Enemy.Archetype.
## CASTER(2), SUMMONER(4), ASSASSIN(5), CHARGER(3), MAGE(7) — the full readable
## roster. BOMBER(6) stays pulled (it suicide-cleared bots at spawn). The MAGE
## telegraphs a ground AoE; grounded bots LEAP to a hero who climbs a ledge.
const BOT_ARCHETYPES: Array[int] = [2, 4, 5, 3, 7]
## Versus bots are tankier than the tower's trash mobs so fights last.
const BOT_HP: int = 110
## Destructible cover sitting on the ground (64px blocks; centre = ground_top - 32).
const COVER_POINTS: Array[Vector2] = [Vector2(430, 538), Vector2(770, 538)]
## Breakable + regenerating platforms (amber rim) — destroy them, they reform ~6s
## later. A high-traffic lane between the two ledges = a knockback-slam demo.
const BREAKABLE_PLATFORMS: Array[Dictionary] = [
	{"center": Vector2(600, 300), "size": Vector2(160, 22)},
]

## -- Look (clean, simple Stick-Fight): flat sky + dark platforms w/ a bright rim --
const SKY_COLOR: Color = Color(0.53, 0.74, 0.92)
const SKY_LOWER_COLOR: Color = Color(0.63, 0.81, 0.93)
const PLATFORM_COLOR: Color = Color(0.20, 0.22, 0.29)
const PLATFORM_EDGE_COLOR: Color = Color(0.55, 0.85, 0.62)
const PLATFORM_EDGE_H: float = 5.0
const RESPAWN_POOF_START: Color = Color(0.75, 0.85, 1.0, 0.9)
const RESPAWN_POOF_END: Color = Color(0.75, 0.85, 1.0, 0.0)

## instance_id -> {"node": Node2D, "stocks": int, "spawn": Vector2 (global),
## "invuln": float}. Eliminated bots are erased; the eliminated hero stays
## registered at 0 stocks (the _match_over guard makes further falls no-ops).
var _registry: Dictionary = {}
var _p1: Node2D = null
var _class_btn: Button = null
var _match_over: bool = false
var _stocks_label: Label = null
var _banner: Label = null
var _pause_menu: PauseMenu = null
## Victory can't be declared during this opening grace (stops a frame-0 / spawn
## transient from instantly flashing "VICTORY").
var _grace: float = 1.2


func _ready() -> void:
	# ALWAYS so Esc can toggle pause even while the tree is paused; the fighters
	# are set PAUSABLE in _spawn_fighters so THEY still freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Switch the music bed back to combat (the hub swaps it to the calm ambience).
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_combat"):
		music.play_combat()
	_build_background()
	_build_platforms()
	_build_cover()
	_build_breakable_platforms()
	_build_walls()
	_spawn_fighters()
	_build_hud()
	_update_hud()


func _process(delta: float) -> void:
	if get_tree().paused or _match_over:
		return
	_grace = maxf(_grace - delta, 0.0)
	for entry: Dictionary in _registry.values():
		entry["invuln"] = maxf(float(entry["invuln"]) - delta, 0.0)
	# Bots can also die to plain damage (Enemy._die -> queue_free), which never
	# routes through a pit — poll so that kill path ends the match too. Grace-gated
	# so a spawn-frame transient can't instantly flash VICTORY.
	if _grace <= 0.0 and _bots_alive() == 0:
		_finish_match("VICTORY — P1 wins!")
	_update_hud()  # poll-don't-push (the AbilityBar idiom): always current


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


## Toggle a real tree pause + the overlay. VersusArena is ALWAYS so this keeps
## working while paused; the fighters (PAUSABLE) freeze.
func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)


## Pause/unpause + open/close the menu together (bound to Esc + the Resume button).
func _set_paused(p: bool) -> void:
	get_tree().paused = p
	if _pause_menu != null:
		if p:
			_pause_menu.open()
		else:
			_pause_menu.close()


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
		get_tree().create_timer(2.5).timeout.connect(_hide_banner)  # brief, then gone
	_update_hud()


func _hide_banner() -> void:
	if _banner != null:
		_banner.visible = false


# ----------------------------------------------------------------------- build
## Flat sky backdrop (clean Stick-Fight look): a big sky rect + a slightly deeper
## lower band for a hint of depth. Far behind everything; ignores the mouse.
func _build_background() -> void:
	# Epic backdrop (gradient sky + distant tower spires + drifting motes +
	# vignette) instead of two flat ColorRects — see Atmosphere.gd.
	Atmosphere.add_glow(self)  # 2D bloom: pushed spell cores radiate
	var atmo := Atmosphere.new()
	add_child(atmo)
	atmo.build(Rect2(Vector2(-400, -420), STAGE_SIZE + Vector2(800, 900)), {
		"sky_top": Color(0.09, 0.11, 0.26),
		"sky_bottom": Color(0.44, 0.60, 0.82),
		"silhouette_far": Color(0.19, 0.23, 0.40),
		"silhouette_near": Color(0.11, 0.14, 0.24),
		"accent": Color(0.75, 0.88, 1.0),
	})


## Solid platforms the fighters land + jump on (StaticBody2D default layer 1,
## which the hero/enemy masks collide with; spells on mask 4 pass over them).
func _build_platforms() -> void:
	for p: Dictionary in PLATFORMS:
		_make_platform(p["center"], p["size"])


## One platform: a StaticBody2D box with a dark body + a bright top rim.
func _make_platform(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	# Gradient body (top-lit -> darker base) for depth against the epic sky.
	var grad := Gradient.new()
	grad.set_color(0, PLATFORM_COLOR.lightened(0.14))
	grad.set_color(1, PLATFORM_COLOR.darkened(0.28))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 8
	tex.height = 64
	var vis := TextureRect.new()
	vis.texture = tex
	vis.stretch_mode = TextureRect.STRETCH_SCALE
	vis.position = -size * 0.5
	vis.size = size
	vis.z_index = -5
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(vis)
	var rim := ColorRect.new()
	rim.position = Vector2(-size.x * 0.5, -size.y * 0.5)
	rim.size = Vector2(size.x, PLATFORM_EDGE_H)
	rim.color = PLATFORM_EDGE_COLOR
	rim.z_index = -4
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rim)
	# Soft lit-edge glow just under the rim — reads as a lit ledge, not a flat slab.
	var glow := ColorRect.new()
	glow.position = Vector2(-size.x * 0.5, -size.y * 0.5 + PLATFORM_EDGE_H)
	glow.size = Vector2(size.x, 9.0)
	glow.color = Color(PLATFORM_EDGE_COLOR.r, PLATFORM_EDGE_COLOR.g, PLATFORM_EDGE_COLOR.b, 0.16)
	glow.z_index = -4
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(glow)
	add_child(body)


## Real blocking cover that spells + melee chew through (group "destructible").
func _build_cover() -> void:
	for point: Vector2 in COVER_POINTS:
		var block := DestructibleTerrain.new()
		block.position = point
		add_child(block)


## Breakable + regenerating platforms you can stand/jump on and destroy.
func _build_breakable_platforms() -> void:
	for p: Dictionary in BREAKABLE_PLATFORMS:
		var plat := BreakablePlatform.new()
		plat.platform_size = p["size"]
		add_child(plat)
		plat.position = p["center"]


## No falling off (yet): tall side walls contain the fighters. The ring-out
## system (_on_fighter_fell) stays dormant — no blast zones are built for now.
func _build_walls() -> void:
	_make_platform(Vector2(195, 290), Vector2(30, 620))   # left wall
	_make_platform(Vector2(1005, 290), Vector2(30, 620))  # right wall


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
	_p1.process_mode = Node.PROCESS_MODE_PAUSABLE  # freeze when the arena pauses
	_register_fighter(_p1, _p1.global_position)
	_frame_camera_on(_p1)
	var enemy_scene: PackedScene = load(ENEMY_SCENE_PATH)
	for i: int in BOT_COUNT:
		var bot: CharacterBody2D = enemy_scene.instantiate()
		bot.archetype = BOT_ARCHETYPES[i % BOT_ARCHETYPES.size()]
		bot.max_hp = BOT_HP  # set before add_child so Enemy._ready seeds hp = max_hp
		bot.position = BOT_SPAWN_POINTS[i % BOT_SPAWN_POINTS.size()]
		add_child(bot)
		bot.process_mode = Node.PROCESS_MODE_PAUSABLE  # freeze when the arena pauses
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
	cam.zoom = Vector2(1.1, 1.1)  # zoomed out so the big sigils + meteor barrage fit
	cam.limit_left = 0
	cam.limit_top = -200  # sky headroom when you jet up
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
	# Reset-map button (top-right) — clickable on desktop + touch. Rebuilds the
	# whole arena (cover, bots, stocks) by reloading the scene.
	var reset_btn := Button.new()
	reset_btn.text = "Reset Map"
	reset_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	reset_btn.offset_left = -122.0
	reset_btn.offset_right = -10.0
	reset_btn.offset_top = 8.0
	reset_btn.offset_bottom = 36.0
	reset_btn.add_theme_font_size_override("font_size", 13)
	reset_btn.pressed.connect(_reset_arena)
	layer.add_child(reset_btn)
	# Difficulty selector — cycles Easy/Normal/Hard/Impossible and rebuilds the
	# arena so the bots respawn at the new difficulty (Hard+ dodge, Impossible deflects).
	var diff_btn := Button.new()
	diff_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	diff_btn.offset_left = -270.0
	diff_btn.offset_right = -128.0
	diff_btn.offset_top = 8.0
	diff_btn.offset_bottom = 36.0
	diff_btn.add_theme_font_size_override("font_size", 13)
	diff_btn.text = "Difficulty: %s" % _difficulty_name()
	diff_btn.pressed.connect(_cycle_difficulty)
	layer.add_child(diff_btn)
	# CLASS swapper — tap to cycle all 8 classes live (same as Tab), for testing.
	_class_btn = Button.new()
	_class_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_class_btn.offset_left = 10.0
	_class_btn.offset_right = 190.0
	_class_btn.offset_top = 40.0
	_class_btn.offset_bottom = 68.0
	_class_btn.add_theme_font_size_override("font_size", 13)
	_class_btn.text = "Class: —  ▶"
	_class_btn.pressed.connect(_on_class_button)
	layer.add_child(_class_btn)
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
	_build_pause_overlay(layer)


## Hidden dim overlay with PAUSED + Resume/Reset — toggled by Esc. Lives on the
## ALWAYS HUD layer so its buttons work while the tree is paused.
func _build_pause_overlay(layer: CanvasLayer) -> void:
	_pause_menu = PauseMenu.new()
	layer.add_child(_pause_menu)
	_pause_menu.build("Exit to Hub")
	_pause_menu.resume_requested.connect(func() -> void: _set_paused(false))
	_pause_menu.exit_requested.connect(_exit_to_hub)


## Leave the versus sandbox back to the hub (Main.tscn). Unpause first so the
## fresh scene doesn't inherit the paused tree.
func _exit_to_hub() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _difficulty_name() -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	var d: int = int(gs.get("enemy_difficulty")) if gs != null else 1
	var names: Array = ["Easy", "Normal", "Hard", "Impossible"]
	return String(names[clampi(d, 0, 3)])


## Cycle Easy -> Normal -> Hard -> Impossible and rebuild so the bots respawn smarter.
func _cycle_difficulty() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("enemy_difficulty", (int(gs.get("enemy_difficulty")) + 1) % 4)
	get_tree().paused = false
	get_tree().reload_current_scene()


## Full arena reset — reload the scene so cover, bots, stocks + the match state
## all rebuild from scratch. Bound to the Reset Map button.
func _reset_arena() -> void:
	get_tree().paused = false  # don't carry the pause into the fresh scene
	get_tree().reload_current_scene()


func _update_hud() -> void:
	if _stocks_label == null:
		return
	var p1_stocks: int = 0
	if _p1 != null and is_instance_valid(_p1) and _registry.has(_p1.get_instance_id()):
		p1_stocks = int(_registry[_p1.get_instance_id()]["stocks"])
	_stocks_label.text = "P1 stocks: %d    Bots left: %d" % [p1_stocks, _bots_alive()]
	if _class_btn != null and _p1 != null and is_instance_valid(_p1) and _p1.has_method("current_class_name"):
		_class_btn.text = "Class: %s  ▶" % _p1.call("current_class_name")


## Tap the class button = cycle the hero's class live (same as the Tab key).
func _on_class_button() -> void:
	if _p1 != null and is_instance_valid(_p1) and _p1.has_method("cycle_class_next"):
		_p1.call("cycle_class_next")
		_update_hud()
