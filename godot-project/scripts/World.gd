extends Node2D
## THE TOWN — the game's front door.
##
## ══ WHY IT EXISTS AGAIN, AND WHAT WOULD MAKE IT WORTHLESS ═══════════════════
## The maker played this an hour before it was rewritten and ruled: "it's just
## another layer that doesn't add any value." That verdict stands and this file is
## written against it. A town you have to WALK ACROSS TO REACH A MENU is friction,
## and on a phone it is worse than friction. Three rules follow, and every layout
## number below is one of them:
##
##   1. **THE TOWN IS THE INTERFACE, NOT A LOBBY YOU WALK TO A MENU INSIDE.** The
##      statue IS class select, the rack IS the armory, the lectern IS your three
##      spells, the door IS the tower. There is no "open the menu" step anywhere.
##   2. **YOU SPAWN ON THE DOORSTEP.** `PLAYER_SPAWN` is `TOWER_X - 54` — inside
##      the door's own proximity ring. The hint is already up on the first frame,
##      so the town costs ONE key press to leave and ZERO steps of walking. Every
##      station is BEHIND you; you go to them because you want something, never
##      because the route to the tower runs through them.
##   3. **THERE IS ALWAYS A FASTER PATH.** The title screen still opens with
##      CLIMB, which never enters the town at all. Nobody who just wants to fight
##      is ever taken on a tour.
##
## ══ NO LLM, ANYWHERE ═══════════════════════════════════════════════════════
## The v0.0 town's two anchors talked to a local Ollama server. That whole stack —
## the `Conversation` autoload, the four-layer memory files, the consolidation
## pipeline — is deleted. Townspeople speak in `Bark`'s voice: one line over a
## head, then gone. See `NPC.gd`.
##
## Side-on, same look and feel as the arena, under the shared `Atmosphere` sky.

const TOWN_WIDTH: float = 1180.0
const GROUND_Y: float = 452.0
const GROUND_THICKNESS: float = 260.0

## LEFT TO RIGHT, IN THE ORDER YOU MEET THEM WALKING BACK FROM THE DOOR. Ordered
## by how often a player actually wants them: gear least, class most, and the
## tower under your feet.
## ⚠ THE SPREAD IS THE COST OF THE TOWN. Farthest station to the door is ~540 px,
## which at Player.SPEED is under three seconds each way. It was 700 px on the
## first pass and that already felt like a corridor; if this ever widens again,
## the town is drifting back toward being the layer it was deleted for being.
const ARMORY_X: float = 306.0        # the rack — weapon / head / body
const ALTAR_X: float = 480.0         # the statue — which of the nine you are
const LECTERN_X: float = 648.0       # the book — which three spells you carry
## THE ARCHIVIST'S DESK — which spells you may carry AT ALL (the tree).
##
## ⚠ NEXT TO THE LECTERN, NOT ACROSS THE ROOM, because the two are one thought:
## the tree decides your options and the lectern picks three of them, so a player
## who has just learned a spell should be able to bind it without a walk. 58 px
## apart is far enough that their proximity hints never fight for the same corner
## (see the note on TOWNSFOLK wander ranges) and close enough to read as one desk.
const ARCHIVIST_X: float = 590.0
const CAMPFIRE_X: float = 740.0      # the warm middle; nothing to press
const SPARRING_X: float = 180.0      # the chalk ring — free play, no stakes
## The party stone stands between the campfire and the door, so the last thing you
## pass on the way out is the answer to "is my friend actually here".
const PARTY_X: float = 820.0
const TOWER_X: float = 900.0         # the door out

## ON THE DOORSTEP. See rule 2 above — this is the single most important number
## in the file. `TowerDoor.PROXIMITY_RADIUS` is sized to reach it.
const PLAYER_SPAWN: Vector2 = Vector2(TOWER_X - 54.0, GROUND_Y)

## Where the three townspeople stand, and how far they wander from it. They are
## posted NEXT TO the thing they talk about, so a bark is a signpost as well as a
## bit of character, and their wander ranges are small enough that they never
## drift into a station's own hint and make two prompts fight for the same corner.
##
## ⚠ EACH ONE NOW HAS A JOB (spec §7). They were flavour; they are the town's
## teaching layer. The Quartermaster says what a gear slot TRADES AWAY, the
## Archivist says how the tree is priced, the Warden teaches the three mechanics
## that are invisible until they kill you, and the Doorkeeper reads your climb back
## to you — floor, best, falls, level — through `NPC._fill`.
##
## That last one is the deleted AI-NPC stack's actual job, and it turns out it never
## needed a language model. It needed four numbers and a token in a string.
const TOWNSFOLK: Array[Dictionary] = [
	{"res": "res://data/npcs/warden.tres", "x": 232.0, "range": 26.0},   # the sparring ring
	{"res": "res://data/npcs/smith.tres", "x": 362.0, "range": 34.0},    # the rack
	{"res": "res://data/npcs/scribe.tres", "x": 550.0, "range": 24.0},   # the Archivist's desk
	{"res": "res://data/npcs/doorkeeper.tres", "x": 762.0, "range": 26.0},  # the door
]

## Decoration only — a raised deck up-left that gives the skyline some depth. It
## used to be where the armory lived, behind a jump. Nothing a phone player needs
## is up a platform any more.
const LOFT_CENTER: Vector2 = Vector2(215.0, GROUND_Y - 118.0)
const LOFT_SIZE: Vector2 = Vector2(300.0, 16.0)
const STEP_CENTER: Vector2 = Vector2(340.0, GROUND_Y - 58.0)
const STEP_SIZE: Vector2 = Vector2(120.0, 14.0)

const GROUND_COLOR: Color = Color(0.10, 0.11, 0.13)
const GROUND_RIM: Color = Color(0.3, 0.55, 0.42)
const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)

const TOWER_DOOR_SCRIPT: Script = preload("res://scripts/TowerDoor.gd")
const STATION_SCRIPT: Script = preload("res://scripts/ArmoryStation.gd")
const CLASS_ALTAR_SCRIPT: Script = preload("res://scripts/ClassAltar.gd")
const HUB_AMBIENCE_SCRIPT: Script = preload("res://scripts/HubAmbience.gd")
const NPC_SCENE: PackedScene = preload("res://scenes/NPC.tscn")

## Every tappable target in the town clears this, in base units, matching the
## floor `Outfitter` and `Lobby` hold themselves to.
const MIN_TAP: float = 30.0

var _outfitter_layer: CanvasLayer = null
var _outfitter: Control = null
var _tree_screen: Control = null


func _ready() -> void:
	_build_backdrop()
	_build_ground()
	_build_loft()
	_spawn_ambience()
	_place_player()
	# AFTER `_place_player`, so the peer bodies are laid out relative to a doorstep
	# the local player is already standing on rather than to wherever Main.tscn
	# happened to park it.
	_setup_peer_bodies()
	_spawn_tower_entrance()
	_spawn_class_altar()
	_spawn_stations()
	_spawn_townsfolk()
	_spawn_hud()
	_spawn_touch_pad()
	_reflect_selected_class()

	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_hub"):
		music.play_hub()

	# The bark/voice observer normally installs itself from Sfx on the first frame
	# a scene exists; re-ensuring it is free and covers entering the town directly.
	VoiceDirector.ensure(get_tree())


# ------------------------------------------------------------------- environment
func _build_backdrop() -> void:
	var atmo := Atmosphere.new()
	add_child(atmo)
	atmo.build(Rect2(Vector2(-400.0, -320.0), Vector2(TOWN_WIDTH + 800.0, GROUND_Y + 760.0)), {
		"sky_top": Color(0.03, 0.04, 0.11),
		"sky_bottom": Color(0.10, 0.16, 0.24),
		"silhouette_far": Color(0.06, 0.10, 0.16),
		"silhouette_near": Color(0.03, 0.06, 0.10),
		"accent": Color(0.5, 0.85, 0.8),
	})


func _spawn_ambience() -> void:
	var amb: Node2D = HUB_AMBIENCE_SCRIPT.new()
	add_child(amb)
	amb.call("build", TOWN_WIDTH, GROUND_Y, CAMPFIRE_X)


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
	var rim := ColorRect.new()
	rim.color = GROUND_RIM
	rim.size = Vector2(shape.size.x, 4.0)
	rim.position = Vector2(-shape.size.x * 0.5, -shape.size.y * 0.5)
	rim.z_index = -4
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rim)
	add_child(body)


func _build_loft() -> void:
	_make_platform(LOFT_CENTER, LOFT_SIZE)
	_make_platform(STEP_CENTER, STEP_SIZE)


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


# --------------------------------------------------------------------- placement
## ══ THE TEAMMATE'S BODY ═══════════════════════════════════════════════════════
## Maker: "a teammate spawns into the antechamber with you".
##
## Host and client both ROUTE here and the session is live, but peer bodies were
## spawned by `Arena._spawn_hero_net` through a `MultiplayerSpawner` plus the
## `party_ready` handshake — and none of that machinery existed in this file, so the
## room was a co-op lobby you stood in alone.
##
## ⚠ THIS IS A PORT, NOT A COPY. Three things differ from the Arena, and each of
## them is the reason a straight copy would have been wrong:
##
##   1. **The body is `Player`, not `Hero`.** The town walker is a different scene
##      with a different script. Spawning a `Hero` here would put a combat body with
##      spells, cooldowns and a damage model into a room with nothing to fight.
##   2. **The LOCAL player already exists.** `Main.tscn` parks one Player in the
##      scene and `_place_player` moves it to the doorstep. So the spawner must
##      create bodies for the OTHER peers only — spawning one for yourself would
##      leave you standing inside a twin.
##   3. **The handshake is tagged "antechamber".** See the `party_ready` note in
##      Net.gd: sharing the arena's one-shot would have meant nobody spawns in the
##      actual fight.
var _peers_root: Node2D = null
var _peer_spawner: MultiplayerSpawner = null

## Far enough apart that two stick figures do not overlap at the door, near enough
## that you can see who arrived without turning the camera.
const PARTY_SPAWN_GAP: float = 46.0


func _setup_peer_bodies() -> void:
	var net: Node = get_node_or_null("/root/Net")
	if net == null or not net.is_active():
		return
	_peers_root = Node2D.new()
	_peers_root.name = "Peers"
	add_child(_peers_root)

	_peer_spawner = MultiplayerSpawner.new()
	_peer_spawner.name = "PeerSpawner"
	add_child(_peer_spawner)
	_peer_spawner.spawn_path = _peers_root.get_path()
	_peer_spawner.spawn_function = Callable(self, "_spawn_peer_body")

	net.call("rearm_handshake", "antechamber")
	if net.is_host() and not net.party_ready.is_connected(_spawn_all_peer_bodies):
		net.party_ready.connect(_spawn_all_peer_bodies)
	net.call("notify_arena_ready", "antechamber")


func _spawn_all_peer_bodies(tag: String = "antechamber") -> void:
	if tag != "antechamber":
		return
	var net: Node = get_node_or_null("/root/Net")
	if net == null or not net.is_host() or _peer_spawner == null:
		return
	var i: int = 1
	for pid in net.peers():
		# ⚠ SKIP EVERY PEER THAT ALREADY HAS A BODY IN THIS ROOM — which, for the
		# local player, is always. `Main.tscn` parks one Player in the scene; spawning
		# a second for the same person puts you inside your own twin.
		if int(pid) == int(net.my_id()):
			continue
		var x: float = PLAYER_SPAWN.x - PARTY_SPAWN_GAP * float(i)
		_peer_spawner.spawn({"peer": int(pid), "cls": int(net.class_of(pid)), "x": x, "y": PLAYER_SPAWN.y})
		i += 1


## Runs on EVERY peer with identical data, so authority assignment is deterministic.
## Props are set BEFORE the spawner adds the node, exactly as `Arena._spawn_hero_net`
## does — a property written after `add_child` has already missed `_ready`.
func _spawn_peer_body(data: Dictionary) -> Node:
	var p: Node = load("res://scenes/Player.tscn").instantiate()
	p.name = "Peer_%d" % int(data["peer"])
	(p as Node2D).position = Vector2(float(data["x"]), float(data["y"]))
	p.set_multiplayer_authority(int(data["peer"]))
	# ⚠ OUT OF THE "player" GROUP. `_place_player`, every station's proximity check
	# and the town's overlay freeze all resolve the local player through that group —
	# `get_first_node_in_group("player")` would start returning whichever body was
	# added most recently, so your friend walking past the lectern would open YOUR
	# armoury. The group is local identity, not "is a person".
	p.remove_from_group("player")
	p.add_to_group("town_peer")
	if p.has_method("set_class_tint"):
		p.call("set_class_tint", ClassInfo.color_for(int(data["cls"])))
	return p


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
			cam.offset = Vector2(0.0, -44.0)


## The three townspeople, instanced here rather than parked in `Main.tscn` so the
## town's cast is one editable list (`TOWNSFOLK`) instead of a scene diff.
func _spawn_townsfolk() -> void:
	for entry: Dictionary in TOWNSFOLK:
		var path: String = String(entry.get("res", ""))
		if not ResourceLoader.exists(path):
			continue
		var npc: Node2D = NPC_SCENE.instantiate()
		npc.set("data", load(path))
		add_child(npc)
		npc.global_position = Vector2(float(entry.get("x", 0.0)), GROUND_Y)
		if npc.has_method("set_hub_patrol"):
			npc.call("set_hub_patrol", float(entry.get("x", 0.0)), float(entry.get("range", 40.0)))


# ----------------------------------------------------------------- the stations
func _spawn_tower_entrance() -> void:
	var door: StaticBody2D = TOWER_DOOR_SCRIPT.new()
	add_child(door)
	door.global_position = Vector2(TOWER_X, GROUND_Y)


func _spawn_class_altar() -> void:
	var altar: StaticBody2D = CLASS_ALTAR_SCRIPT.new()
	add_child(altar)
	altar.global_position = Vector2(ALTAR_X, GROUND_Y)


## The RACK and the LECTERN. Both are `ArmoryStation.gd` pointed at a different
## screen — see the header there. The rack is on the GROUND now: it used to sit on
## the loft behind a jump, and behind `if false:`, so in practice the whole armory
## (3 slots x 19 pieces, with live effect bags) had never been reachable in play.
func _spawn_stations() -> void:
	var rack: StaticBody2D = STATION_SCRIPT.new()
	rack.set("kind", "armory")
	add_child(rack)
	rack.global_position = Vector2(ARMORY_X, GROUND_Y)

	var lectern: StaticBody2D = STATION_SCRIPT.new()
	lectern.set("kind", "spells")
	add_child(lectern)
	lectern.global_position = Vector2(LECTERN_X, GROUND_Y)

	var archivist: StaticBody2D = STATION_SCRIPT.new()
	archivist.set("kind", "tree")
	add_child(archivist)
	archivist.global_position = Vector2(ARCHIVIST_X, GROUND_Y)

	# THE SPARRING RING. Free play was a button on the TITLE screen, which is the one
	# place a player is not yet curious about what their thumbs do. In the room it is
	# something you walk past, at the FAR END from the door, so nobody heading for
	# the tower is ever detoured through it.
	var ring: StaticBody2D = STATION_SCRIPT.new()
	ring.set("kind", "sparring")
	add_child(ring)
	ring.global_position = Vector2(SPARRING_X, GROUND_Y)

	# ⚠ THE PARTY STONE ONLY EXISTS IN A PARTY. A station that says "nobody here" to
	# a solo player is a dead object teaching them the room has broken parts — and
	# this room already had to answer the maker asking "what do I do there".
	if _session_is_party():
		var stone: StaticBody2D = STATION_SCRIPT.new()
		stone.set("kind", "party")
		add_child(stone)
		stone.global_position = Vector2(PARTY_X, GROUND_Y)


## Is this a co-op visit? Reads `GameState.session_kind`, which the title screen
## sets before it sends you here — so the room knows what kind of visit this is
## without asking the network, which may not have connected yet.
func _session_is_party() -> bool:
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs == null:
		return false
	return int(gs.get("session_kind")) != 0


## THE OUTFITTER, on demand. A `Control`, so it needs a `CanvasLayer` of its own to
## sit above a `Node2D` world; grouped `town_overlay` so the player and every
## station freeze underneath it without any of them knowing what it is.
func open_outfitter() -> void:
	if _outfitter != null and is_instance_valid(_outfitter):
		return
	if _outfitter_layer == null:
		_outfitter_layer = CanvasLayer.new()
		_outfitter_layer.layer = 95
		add_child(_outfitter_layer)
	_outfitter = Outfitter.new()
	_outfitter.add_to_group("town_overlay")
	_outfitter_layer.add_child(_outfitter)
	var gs: Node = get_node_or_null("/root/GameState")
	_outfitter.call("set_class", int(gs.get("selected_class")) if gs != null else 0)
	if _outfitter.has_signal(&"closed"):
		_outfitter.connect(&"closed", _on_outfitter_closed)


## THE SPELL TREE, on demand. Same lifetime rules as the Outfitter above and for the
## same reasons — a `Control` needs a `CanvasLayer` over a `Node2D` world, and the
## `town_overlay` group is what freezes the player and every station underneath it
## without any of them having to know what is open.
func open_spell_tree() -> void:
	if _tree_screen != null and is_instance_valid(_tree_screen):
		return
	if _outfitter_layer == null:
		_outfitter_layer = CanvasLayer.new()
		_outfitter_layer.layer = 95
		add_child(_outfitter_layer)
	_tree_screen = SpellTreeScreen.new()
	_tree_screen.add_to_group("town_overlay")
	_outfitter_layer.add_child(_tree_screen)
	var gs: Node = get_node_or_null("/root/GameState")
	_tree_screen.call("set_class", int(gs.get("selected_class")) if gs != null else 0)
	if _tree_screen.has_signal(&"closed"):
		_tree_screen.connect(&"closed", _on_spell_tree_closed)


func _on_spell_tree_closed() -> void:
	if _tree_screen != null and is_instance_valid(_tree_screen):
		# Out of the group in the same frame it closes, so the player is not frozen
		# for the frame between `closed` and `queue_free` landing.
		_tree_screen.remove_from_group("town_overlay")
		_tree_screen.queue_free()
	_tree_screen = null


func _on_outfitter_closed() -> void:
	if _outfitter != null and is_instance_valid(_outfitter):
		# Out of the group in the same frame it closes, so the player is not frozen
		# for the frame between `closed` and `queue_free` landing.
		_outfitter.remove_from_group("town_overlay")
		_outfitter.queue_free()
	_outfitter = null


# ---------------------------------------------------------------------- the HUD
## Two lines and nothing else. The top line is who you are; the bottom line is the
## only onboarding the town gets, and it points BOTH ways on purpose — the door is
## under your feet and the shops are behind you.
func _spawn_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)

	var who := Label.new()
	who.add_to_group("class_hud_label")
	who.position = Vector2(14, 10)
	who.add_theme_font_size_override("font_size", 16)
	who.add_theme_color_override("font_color", CHALK)
	who.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	who.add_theme_constant_override("outline_size", 4)
	layer.add_child(who)

	var guide := Label.new()
	guide.text = "◂  walk left: gear · spells · class     ·     the tower is right here  ▸     ·     Esc: title"
	guide.anchor_top = 1.0
	guide.anchor_bottom = 1.0
	guide.anchor_right = 1.0
	guide.offset_top = -26.0
	guide.offset_left = 14.0
	guide.offset_right = -14.0
	guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide.add_theme_font_size_override("font_size", 11)
	guide.add_theme_color_override("font_color", GRAPHITE)
	guide.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	guide.add_theme_constant_override("outline_size", 3)
	layer.add_child(guide)


## A MINIMAL TOUCH PAD, and deliberately not `TouchControls`. That layer is the
## combat one: twin sticks, a cast button and a spell row, all of which mean
## nothing here and one of which (`cast`) would be actively wrong. The town needs
## exactly three verbs, so it gets three pads that press the same NAMED ACTIONS a
## keyboard does — no raw keycodes anywhere, per the mobile-input rule.
##
## Hidden unless the device actually has a touchscreen, so desktop is untouched.
func _spawn_touch_pad() -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	# Walk: two wide pads in the bottom-left, thumb-sized.
	_pad(layer, "move_left", "◂", Vector2(14.0, -14.0 - 46.0), Vector2(52.0, 46.0), false)
	_pad(layer, "move_right", "▸", Vector2(72.0, -14.0 - 46.0), Vector2(52.0, 46.0), false)
	# Jump and interact under the other thumb. INTERACT is the biggest thing on the
	# screen because it is the only one that does anything in a town.
	_pad(layer, "jump", "▲", Vector2(-14.0 - 52.0, -14.0 - 46.0), Vector2(52.0, 46.0), true)
	_pad(layer, "talk", "E", Vector2(-14.0 - 52.0 - 74.0, -14.0 - 52.0), Vector2(68.0, 52.0), true)
	# BACK. A touch player has no Esc key, so without this the only exit from the
	# town on the target platform is to start a run.
	_pad(layer, "ui_cancel", "✕", Vector2(-14.0 - 38.0, -360.0), Vector2(38.0, 32.0), true)


## One pad, pressing one named action. `anchor_right` places it from the right edge
## when `from_right`, so the layout survives any window the game is opened at.
func _pad(layer: CanvasLayer, action: String, glyph: String, offset: Vector2,
		size: Vector2, from_right: bool) -> void:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(maxf(size.x, MIN_TAP), maxf(size.y, MIN_TAP))
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	if from_right:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
	b.offset_left = offset.x
	b.offset_right = offset.x + size.x
	b.offset_top = offset.y
	b.offset_bottom = offset.y + size.y
	b.add_theme_font_size_override("font_size", 20)
	b.modulate = Color(1.0, 1.0, 1.0, 0.62)
	# Press/release rather than a one-shot `pressed`, so holding ◂ walks.
	b.button_down.connect(func() -> void: Input.action_press(action, 1.0))
	b.button_up.connect(func() -> void: Input.action_release(action))
	# A pad that is still held when the town unloads would leave the action stuck
	# down for the whole run underneath it.
	b.tree_exiting.connect(func() -> void: Input.action_release(action))
	layer.add_child(b)


## THE WAY OUT THAT ISN'T THE TOWER. `PauseMenu` is spawned by the arena, not by
## this scene, so without this the only exit from the town was to start a run —
## a front door you can only leave by going upstairs is a trap, not a front door.
## Esc / Back goes to the title, and only when no panel is up (a panel eats its own
## ui_cancel first, so this never steals a "close this screen").
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		return
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("is_open") and lo.is_open():
		return
	for o: Node in get_tree().get_nodes_in_group("town_overlay"):
		if o is CanvasItem and (o as CanvasItem).visible:
			return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("go_to_title"):
		get_viewport().set_input_as_handled()
		gs.call("go_to_title")


func _reflect_selected_class() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var idx: int = int(gs.get("selected_class")) if gs != null else 0
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_class_tint"):
		player.call("set_class_tint", ClassInfo.color_for(idx))
	for label: Node in get_tree().get_nodes_in_group("class_hud_label"):
		if label is Label:
			(label as Label).text = "%s" % ClassInfo.name_for(idx)
