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
const DEFAULT_EXIT_POINT: Vector2 = Vector2(870, 512)
## Wall collider thickness, matching Arena.tscn's authored value.
const WALL_THICKNESS: float = 16.0
## Where a hero stands when no floor layout says otherwise (sandbox / boss rush).
## Kept in step with LayoutDef.hero_start — both moved when the room grew (maker:
## "the map is too small"), or heroes would spawn in the left third of a 1160-wide
## room, mid-air, and drop.
const DEFAULT_HERO_START: Vector2 = Vector2(390, 512)

var _gs: Node = null
var _net: Node = null   # cached /root/Net (co-op); null / inactive in SP
var _run_mode: bool = false
var _current_floor_def: FloorDef = null
var _encounter: Encounter = null
var _hype: Hype = null            # the moment-to-moment reward loop (streaks, shouts)
var _room: Node2D = null
var _atmo: Atmosphere = null
var _portal: ExitPortal = null
var _return_portal: ExitPortal = null
const RETURN_PORTAL_COLOR: Color = Color(1.0, 0.85, 0.4)   # warm gold vs the cyan climb-exit
## Where the LEAVE portal stands on this floor, kept so the confirm can put it back.
var _return_pt: Vector2 = Vector2.ZERO
## True between "keep climbing" and the portal actually returning — see `_cancel_leave`.
var _return_pending: bool = false
## The leave confirmation overlay, or null.
var _confirm_layer: CanvasLayer = null
## How far a hero must step off the leave portal before it is allowed back. Comfortably
## wider than `ExitPortal.RADIUS` (30) so re-arming can never happen under a thumb.
const RETURN_REARM_RADIUS: float = 74.0
var _floor_banner: Label = null
var _pause_menu: PauseMenu = null
var _revive: Revive = null        # the pick-your-teammate-up channel + its prompt/pad
var _spawn_timer: float = 0.0
## Debounce: the party-wipe verdict is reached ONCE per run, on every peer.
var _wipe_handled: bool = false
## …and the GAME OVER card is built at most once for the life of this arena.
var _game_over_shown: bool = false
## …and exactly one of its two exits is ever taken. See `_leave_to`.
var _exit_taken: bool = false

## ── THE GAME OVER CARD ────────────────────────────────────────────────────────
## The card's palette IS `RunSummary`'s, so the screen you die on and the screen you
## land on read as one game rather than two. `ASH` in particular is already that
## file's `accent_for(WIPED)` — this is the existing convention, not a new one.
##
## ⚠ RESTATED RATHER THAN IMPORTED, and deliberately: naming `RunSummary` here would
## bolt a UI script's compile onto the largest scene script in the game, for four
## colours. `RunSummary` restates its own scene paths for the same class of reason.
## If that file's palette ever moves, these move with it.
const CARD_PAPER: Color = Color(0.055, 0.052, 0.075)
const CARD_ASH: Color = Color(0.96, 0.42, 0.36)
const CARD_CHALK: Color = Color(0.93, 0.92, 0.86)
const CARD_GRAPHITE: Color = Color(0.62, 0.63, 0.70)
## `GameState.HUB_SCENE`, restated for the same reason (`GameState` has no
## `class_name` — it resolves only as an autoload, so naming it would break every
## headless tool that loads this scene). Used ONLY to decide whether to draw the
## Antechamber button; the navigation itself still goes through `visit_hub()`.
const HUB_SCENE_PATH: String = "res://scenes/Main.tscn"
## How long a card nobody answers waits before clocking the death itself. Not a beat
## the player is meant to feel — see the call site in `_check_party_wipe`.
const IDLE_CLOCK_OUT: float = 25.0
## Which wall shapes have already been un-shared from the .tscn sub-resource
## (see _set_wall) — duplicate once, then mutate in place every floor after.
var _resized_walls: Dictionary = {}

## ------------------------------------------------------------- BOSS RUSH
## STRAIGHT TO THE ASHSPIRE GUARDIAN, no climb. The boss sits on floor 5, so the
## only way to look at it used to be to play four floors first — which is not a
## way to TEST it, and testing it is exactly what was asked for.
##
## Set true (by the duel's Esc menu, or by a tool) BEFORE this scene loads: the
## sandbox branch of _ready then builds the default room, spawns the guardian and
## nothing else, and switches to boss framing + the boss bed. It does NOT start a
## run — GameState is untouched, so this can never leave a half-begun climb behind.
##
## A STATIC because it has to survive the scene change that carries you here, and
## it is cleared on the way in so one boss fight never silently becomes forever.
static var boss_rush: bool = false
## Full boss hp (the multiplier a floor-5 FloorDef would have applied).
const BOSS_RUSH_HP_MULT: float = 1.6
var _boss_rush_active: bool = false


func _ready() -> void:
	# Music mood is chosen per-mode: run mode -> _setup_floor picks adventure/boss
	# from the floor type; sandbox -> adventure (below). (The hub set the town bed.)

	Atmosphere.add_glow(self)  # 2D bloom: pushed spell cores radiate
	PostProcess.add(self)      # reactive screen-space grade ("the look")
	_room = Node2D.new()
	_room.name = "Room"
	add_child(_room)
	_encounter = ENCOUNTER_SCRIPT.new()
	add_child(_encounter)
	_encounter.cleared.connect(_on_floor_cleared)
	# THE REWARD LOOP. Built before anything can die, and in BOTH modes: the F6
	# sandbox is where combat feel gets judged, so the streak/multi-kill feedback
	# has to be there too or the sandbox lies about how the game feels.
	_hype = Hype.new()
	add_child(_hype)
	_encounter.wave_started.connect(_on_wave_started)
	_encounter.wave_cleared.connect(_on_wave_cleared)
	_encounter.boss_spawned.connect(_on_boss_spawned)
	_build_ability_bar()
	_build_pause_overlay()
	# PICKING YOUR TEAMMATE UP. Parked here rather than in `FloorBuilder` (which owns
	# the per-floor props, incl. `SpellHandoff`) because a revive has to survive a
	# floor rebuild: it holds a live channel, and rebuilding the node under a player's
	# thumb would silently cancel it. One per arena, for the arena's whole life.
	_revive = Revive.new()
	_revive.name = "Revive"
	add_child(_revive)
	_setup_heroes()
	_setup_enemy_spawner()   # co-op: host-authoritative enemies replicate through this

	_gs = get_node_or_null("/root/GameState")
	_net = get_node_or_null("/root/Net")
	_run_mode = _gs != null and _gs.is_run_active()
	if _run_mode:
		_build_theme_layer()
		_build_floor_banner()
		if not _gs.floor_advanced.is_connected(_on_floor_advanced):
			_gs.floor_advanced.connect(_on_floor_advanced)
		# Co-op client: the host broadcasts "floor cleared" -> spawn our exit portal(s)
		# locally so any hero can pull the party forward (the host debounces advances).
		var net: Node = get_node_or_null("/root/Net")
		if net != null and net.is_active() and net.has_signal("net_floor_cleared") \
				and not net.net_floor_cleared.is_connected(_spawn_exit_portals):
			net.net_floor_cleared.connect(_spawn_exit_portals)
		_setup_floor(_gs.current_floor())
	else:
		# Sandbox: the default room (sized from its own layout, same as a real
		# floor) + an endless trickle (below).
		var sandbox_layout: LayoutDef = GameState.synthesize_floor_def(1).layout
		_apply_room_size(sandbox_layout.room_size)
		# ⚠ THE SANDBOX HAS TO USE THE SAME SPAWN PLACES THE TOWER DOES, or F6 is
		# measuring a different game. Enemies used to be sampled anywhere inside the
		# room rect — which in a side-on gravity room meant most were born hundreds of
		# pixels up and rained down ("the opponents should spawn from certain places
		# not just randomly in the air"). `configure_places` replaces that with the
		# doorways / ground marks / ledge-tops set; without this line the sandbox would
		# silently keep the old rect sampler and the fix would look unverifiable.
		_encounter.configure_places(sandbox_layout)
		FloorBuilder.build_props(_room, sandbox_layout)
		var music: Node = get_node_or_null("/root/Music")
		# BOSS RUSH: the guardian, alone, right now. Consume the flag on the way in
		# so a later F6 sandbox is a sandbox again.
		if boss_rush:
			boss_rush = false
			_boss_rush_active = true
			_encounter.spawn_boss(BOSS_RUSH_HP_MULT)
			# Fit-all framing, exactly as a real BOSS floor gets — the guardian is
			# big enough that a hero-glued camera cuts half of it off.
			for cam: Node in get_tree().get_nodes_in_group("combat_camera"):
				if cam.has_method("set_frame_all"):
					cam.set_frame_all(true)
			if music != null and music.has_method("play_boss"):
				music.play_boss()
			# Esc gets the two things you want during a boss test: another go, and
			# the way back to the duel you came from.
			if _pause_menu != null:
				_pause_menu.add_action("Fight the Boss Again", _restart_boss_rush)
				_pause_menu.add_action("Back to the Duel", _exit_to_duel)
		elif music != null and music.has_method("play_adventure"):
			music.play_adventure()


func _process(delta: float) -> void:
	# THE RUN-ENDING VERDICT. Watched on EVERY peer (and in single player), not just
	# the host: the card has to appear on both screens, and the host-only version was
	# a co-op-only mechanic. Only the host actually ENDS the run — see below.
	if _run_mode and not _wipe_handled:
		_check_party_wipe()
	# Put the LEAVE portal back once the hero who declined has stepped off it. Doing
	# this on contact instead would re-fire the confirm on the same frame it closed.
	if _return_pending and not is_instance_valid(_return_portal) and not _hero_near_return_point():
		_return_pending = false
		_build_return_portal()
	if _run_mode or _boss_rush_active:
		return  # Encounter drives the finite floor; a boss rush is the boss ALONE
	# Sandbox trickle: keep ~TARGET_ENEMY_COUNT alive forever.
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SANDBOX_SPAWN_INTERVAL
		# Bodies being DRAWN count toward the steady state: a spawn mark is a body
		# that is coming (Encounter.SPAWN_TELL_LEAD), and asking only the `enemy`
		# group would let the sandbox order more while the ink was still wet.
		if get_tree().get_nodes_in_group("enemy").size() \
				+ _encounter.pending_spawn_count() < TARGET_ENEMY_COUNT:
			_encounter.spawn(0.5, 1.0)


# ---------------------------------------------------------------------- RUN
func _setup_floor(floor: int) -> void:
	_current_floor_def = _gs.floor_def_for(floor)
	_apply_floor_music()
	_apply_room_size(_layout_room_size())
	_rebuild_room()
	_clear_portal()
	var theme: EnvTheme = _resolve_theme()
	if theme != null:
		_apply_theme(theme)
	_show_floor_banner(floor, theme)
	_apply_floor_camera()
	_encounter.run_floor(_current_floor_def)
	_raise_opening_thralls()


## "A WARLOCK SHOULD BEGIN A FLOOR WITH ONE THRALL ALREADY UP." The maker's explicit
## ask, and the one line of it that has to live outside `RaiseThrall.gd`.
##
## AFTER `run_floor`, not before: the spell asks the `Encounter` whether the floor
## has room under `MAX_LIVE_ENTITIES`, and asking before the floor's own wave exists
## would hand the Warlock a body the budget had not accounted for.
##
## Reached BY PATH and called with `call()`. `RaiseThrall.gd` deliberately declares no
## `class_name` — a brand-new one is absent from `global_script_class_cache.cfg` until
## something re-imports, and until then every file that NAMES it fails to compile,
## which in this file would take the whole Arena down. Same reason `SpellCaster`
## reaches every spectacle by path.
##
## The function itself no-ops for every case that is not a local Warlock who actually
## carries the spell (wrong class, client peer, no room on the floor), so this is
## unconditional here on purpose: the decision belongs in one place and it is not
## this one.
func _raise_opening_thralls() -> void:
	var scr: GDScript = load("res://scripts/combat/RaiseThrall.gd") as GDScript
	if scr == null:
		return
	scr.call(&"raise_opening_thralls", self)


## ONE SCREEN (1.3). THE TOWER is a one-screen arena brawler, so fit-all framing
## is the DEFAULT on every floor, not a boss-floor special case. Paired with
## room sizes that fit inside the framing zoom (see _apply_room_size), the whole
## floor is on screen at once and nobody fights off-camera.
func _apply_floor_camera() -> void:
	for cam: Node in get_tree().get_nodes_in_group("combat_camera"):
		if cam.has_method("set_frame_all"):
			cam.set_frame_all(true)


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


## The active floor's room_size, falling back to the LayoutDef default.
func _layout_room_size() -> Vector2:
	if _current_floor_def != null and _current_floor_def.layout != null:
		return _current_floor_def.layout.room_size
	return LayoutDef.new().room_size


## LayoutDef.room_size ACTUALLY DRIVES THE GEOMETRY (1.3). Until now Arena.tscn
## hard-coded a 1200x680 box — a Floor ColorRect plus four wall colliders — and
## `room_size` was read in exactly one place, to position a portal. Now the floor
## rect and all four walls are rebuilt from the floor's data, so a floor can be
## the size its layout says it is (and stay inside one screen at the framing
## zoom: 640x360 viewport / FRAME_ZOOM_MIN 0.5 minus FRAME_PAD ~= 980x500 max).
##
## Wall shapes are DUPLICATED on first use: they arrive as .tscn sub-resources,
## and mutating a shared resource in place would leak this floor's size into
## every other scene that loads the same one.
func _apply_room_size(size: Vector2) -> void:
	var w: float = maxf(size.x, WALL_THICKNESS * 4.0)
	var h: float = maxf(size.y, WALL_THICKNESS * 4.0)
	var floor_rect: ColorRect = get_node_or_null("Floor") as ColorRect
	if floor_rect != null:
		# ⚠ THE ROOM WASH IS A BACKDROP, NOT A LAYER IN THE STAGE. It sat at z -2 in
		# the .tscn, which is IN FRONT of where a ruin ledge parks itself (-4) — so
		# `FloorBuilder` had to shove every tower ledge to -1 to be visible at all,
		# and the tower ended up with a second, contradictory z scheme. Parking the
		# wash at BACKDROP puts it behind the whole stage ladder, so the tower and the
		# versus stage now order themselves identically. See StageLayers.
		StageLayers.apply(floor_rect, StageLayers.BACKDROP)
		floor_rect.offset_left = 0.0
		floor_rect.offset_top = 0.0
		floor_rect.offset_right = w
		floor_rect.offset_bottom = h
		floor_rect.size = Vector2(w, h)
	# THE ROOM, DRAWN. The wash above says what colour the room is; the shell says
	# where its GROUND and its EDGES are, which until now nothing did — see RoomShell.
	# Built here rather than in `_rebuild_room` because it is a function of the room's
	# SIZE, not of the floor's props, and `_rebuild_room` frees everything it owns.
	_ensure_room_shell().build(Vector2(w, h))
	var walls: Node = get_node_or_null("Walls")
	if walls == null:
		return
	_set_wall(walls, "WallTop", Vector2(w * 0.5, 0.0), Vector2(w, WALL_THICKNESS))
	_set_wall(walls, "WallBottom", Vector2(w * 0.5, h), Vector2(w, WALL_THICKNESS))
	_set_wall(walls, "WallLeft", Vector2(0.0, h * 0.5), Vector2(WALL_THICKNESS, h))
	_set_wall(walls, "WallRight", Vector2(w, h * 0.5), Vector2(WALL_THICKNESS, h))


## The room shell, created on first use. Found BY NAME rather than held on a member:
## `_apply_room_size` is re-driven on every floor and also directly by
## `tools/slice_test_one_screen.gd` against a freshly instantiated Arena, so a
## find-or-create is the shape that cannot end up with two of them or with a stale
## freed one.
func _ensure_room_shell() -> RoomShell:
	var shell: RoomShell = get_node_or_null("RoomShell") as RoomShell
	if shell != null:
		return shell
	shell = RoomShell.new()
	shell.name = "RoomShell"
	add_child(shell)
	return shell


func _set_wall(walls: Node, wall_name: String, pos: Vector2, size: Vector2) -> void:
	var cs: CollisionShape2D = walls.get_node_or_null(wall_name) as CollisionShape2D
	if cs == null:
		return
	cs.position = pos
	var shape: RectangleShape2D = cs.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		cs.shape = shape
	elif not _resized_walls.has(wall_name):
		shape = shape.duplicate() as RectangleShape2D
		cs.shape = shape
	_resized_walls[wall_name] = true
	shape.size = size


## Fresh room each floor: free the old props, build the new floor's props.
func _rebuild_room() -> void:
	for child in _room.get_children():
		child.queue_free()
	FloorBuilder.build_props(_room, _current_floor_def.layout)


# ------------------------------------------------------------------ wave beats
## THE PACING BEATS, routed from Encounter to the reward loop. These fire on every
## peer (Encounter emits them host-side; a co-op client's Encounter is idle, so
## clients currently see the shouts only for their own... which is the honest
## limitation to fix alongside the rest of the co-op replication work).
func _on_wave_started(index: int, total: int) -> void:
	if _hype != null:
		_hype.wave_opened(index, total)


func _on_wave_cleared(index: int, total: int) -> void:
	if _hype != null:
		_hype.wave_beaten(index, total)


func _on_boss_spawned() -> void:
	# Music FIRST, then the shout. A mood change resets the combat-intensity lift
	# (a new room should not arrive still shouting from the last one), so calling
	# these the other way round would have the boss bed immediately undo the
	# intensity the guardian's arrival just asked for.
	# The guardian gets that bed on EVERY floor now that every floor ends on one —
	# previously only a BOSS-typed floor ever heard it, which meant four of the
	# five guardians arrived to adventure music.
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_boss"):
		music.play_boss()
	if _hype != null:
		_hype.guardian_arrived()


## Host: the floor's fight is done -> open the exit portal(s), then (co-op) tell the
## clients to open theirs so ANY hero can pull the party forward.
func _on_floor_cleared() -> void:
	if not _run_mode:
		return
	_spawn_exit_portals()
	var net: Node = get_node_or_null("/root/Net")
	if net != null and net.is_active() and net.is_host():
		net.broadcast_floor_cleared()


## Build the climb-exit (+ a return-to-town portal on non-final floors). Idempotent —
## the co-op net_floor_cleared broadcast may arrive while the portal already exists.
func _spawn_exit_portals() -> void:
	if not _run_mode or is_instance_valid(_portal):
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
		_return_pt = return_pt
		_return_pending = false
		_build_return_portal()


## The LEAVE portal, built on its own so the confirm below can put it back.
##
## ⚠ ITS LABEL USED TO SAY "RETURN TO TOWN". Two portals with OPPOSITE CONSEQUENCES
## spawn together on every non-final cleared floor — a cyan one that continues the
## climb and a gold one that ENDS THE RUN FOR THE WHOLE PARTY — and the gold one was
## named after a place that is no longer on the critical path. "LEAVE THE TOWER"
## says what it costs.
func _build_return_portal() -> void:
	if is_instance_valid(_return_portal):
		return
	_return_portal = EXIT_PORTAL_SCRIPT.new() as ExitPortal
	_return_portal.portal_label = "LEAVE THE TOWER"
	_return_portal.ring_color = RETURN_PORTAL_COLOR
	_return_portal.trigger_group = "hero"
	add_child(_return_portal)
	_return_portal.global_position = _return_pt
	_return_portal.taken.connect(_on_return_taken)


## ⚠ THE RUN-ENDING PORTAL ASKS FIRST, AND IT IS THE ONLY ONE THAT DOES.
##
## Both portals used to fire on contact with no confirmation, so a player who walked
## the wrong way lost the session — on a phone, with a virtual stick, seconds after a
## fight, and in co-op for BOTH of them. The climb portal stays instant, because
## taking that one by accident costs nothing you were not already doing.
##
## Deliberately NOT `get_tree().paused`: pause is local, so in co-op it would freeze
## one player while the other kept moving. The floor is already cleared, so there is
## nothing left to freeze for.
func _on_return_taken() -> void:
	if is_instance_valid(_return_portal):
		if _return_portal.taken.is_connected(_on_return_taken):
			_return_portal.taken.disconnect(_on_return_taken)
		_return_portal.queue_free()
	_return_portal = null
	# A floor change (or leaving) must not leave a confirm hanging over the next fight,
	# nor a pending re-arm that would spawn a leave portal into a live floor.
	_return_pending = false
	_close_confirm()
	_show_leave_confirm()


## The confirm. Two thumb-sized targets, and a line that names what leaving actually
## costs — which under the persistent climb is far less than a player fears, so
## saying so plainly is the honest thing rather than a scare screen.
func _show_leave_confirm() -> void:
	if is_instance_valid(_confirm_layer):
		return
	_confirm_layer = CanvasLayer.new()
	_confirm_layer.layer = 80          # above the HUD (60), below the pause menu (90)
	add_child(_confirm_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # eat taps meant for the buttons
	_confirm_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	center.add_child(col)
	var head := Label.new()
	head.text = "LEAVE THE TOWER?"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", RETURN_PORTAL_COLOR)
	col.add_child(head)
	var note := Label.new()
	note.text = "the run ends here%s.
your climb is banked — floor %d is waiting." % [
		("  ·  for both of you" if _is_coop() else ""),
		mini(_gs.current_floor() + 1, _gs.total_floors()),
	]
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.72, 0.74, 0.82))
	col.add_child(note)
	col.add_child(_confirm_button("Keep climbing", _cancel_leave, Color(0.88, 0.94, 1.0)))
	col.add_child(_confirm_button("Leave", _confirm_leave, RETURN_PORTAL_COLOR))


func _confirm_button(text: String, cb: Callable, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(196, 32)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", tint)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _close_confirm() -> void:
	if is_instance_valid(_confirm_layer):
		_confirm_layer.queue_free()
	_confirm_layer = null


## Said no. The portal comes BACK — but NOT while a hero is still standing on it, or
## `ExitPortal`'s per-frame overlap poll would re-fire the instant it armed and the
## confirm would loop forever. `_process` puts it back once everyone has stepped clear.
func _cancel_leave() -> void:
	_close_confirm()
	_return_pending = _run_mode


func _confirm_leave() -> void:
	_close_confirm()
	_return_pending = false
	_clear_portal()
	# Co-op: the host owns the run spine -> ask it to return the party (ends the run
	# for everyone). SP: end the run directly.
	var net: Node = get_node_or_null("/root/Net")
	if net != null and net.is_active():
		net.request_return()
	else:
		_gs.return_to_hub()


func _is_coop() -> bool:
	return _net != null and _net.is_active() and _net.peers().size() > 1


## Is any hero still inside the leave portal's footprint?
func _hero_near_return_point() -> bool:
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if h is Node2D and is_instance_valid(h) 				and (h as Node2D).global_position.distance_to(_return_pt) < RETURN_REARM_RADIUS:
			return true
	return false


func _on_portal_taken() -> void:
	_clear_portal()
	# Co-op: request the host to advance the party (debounced to once per clear); the
	# host's floor_advanced rebuilds every peer. SP: advance directly (climb, or end
	# the run in victory past the last floor).
	var net: Node = get_node_or_null("/root/Net")
	if net != null and net.is_active():
		net.request_advance()
	else:
		_gs.advance_floor()


func _on_floor_advanced(new_floor: int) -> void:
	_setup_floor(new_floor)
	# Co-op: a downed hero comes back up on the next floor (the party carried them).
	if _net != null and _net.is_active():
		_revive_local_heroes()
	_wipe_handled = false


## Co-op client (host drives the spine + enemy lifecycle). False in SP.
func _is_net_client() -> bool:
	return _net != null and _net.is_active() and not _net.is_host()


func _is_coop_host() -> bool:
	return _net != null and _net.is_active() and _net.is_host()


## PARTY WIPE = GAME OVER. "if you all die then the game is over" (maker, 2026-08-01).
##
## When every hero in the run is a ghost there is nobody left to pick anyone up, so
## the run ends. This replaces the old behaviour (drop the party a floor and revive
## everyone), and it is deliberately the SAME code path in single player: solo you
## are the whole party, so your death reaches this verdict on the frame it happens —
## which is `DeathRules.SOLO_SELF_REVIVE_CHARGES == 0`, the shipped policy.
##
## Runs on every peer so the GAME OVER card lands on both screens; only the host (or
## single player) actually ends the run, because the host owns the run spine.
## Debounced by `_wipe_handled` to exactly one verdict per run.
func _check_party_wipe() -> void:
	var heroes: Array = get_tree().get_nodes_in_group("hero")
	var live: int = 0
	for h: Node in heroes:
		# ⚠ A DEPARTED PEER'S HERO MUST NOT BLOCK THE WIPE. `Net` frees it on
		# disconnect now, but `queue_free` lands at the end of the frame and the node
		# is still in the group until then — one tick of a frozen, never-downed puppet
		# is enough to hold the party in a fight nobody can lose or win. Skipping the
		# dying node is what keeps a dropped phone from soft-locking the run.
		if not is_instance_valid(h) or h.is_queued_for_deletion():
			continue
		live += 1
		if not (h.has_method("is_downed") and h.is_downed()):
			return   # someone's still standing — no wipe
		# ...and a hero mid-SECOND-WIND is a body that is already coming back on its
		# own clock. Calling the run over it would make the self-revive charge
		# (`DeathRules.SOLO_SELF_REVIVE_CHARGES`) unspendable the moment it mattered.
		if h.has_method("awaiting_second_wind") and bool(h.call("awaiting_second_wind")):
			return
	if live == 0:
		return
	_wipe_handled = true
	_show_game_over()
	# ⚠ THE RUN NO LONGER ENDS ON A TIMER. It used to: the card held for
	# `GAME_OVER_HOLD` and then navigated for you, which is why the card could not
	# carry a choice — anything you put on it was a race against the clock. The card
	# owns the ending now, and `_leave_to` is the only thing that closes a run out.
	#
	# This timer is the one exception: a player who dies and walks away must still have
	# the death CLOCKED. Under `RESET_CLIMB_ON_GAME_OVER == false` the falls counter is
	# the only thing a death costs, so letting it be dodged by not answering the card
	# would make dying free. Long enough that nobody deciding ever meets it. It runs on
	# the process clock and ignores time_scale, so a death inside a hit-stop resolves.
	get_tree().create_timer(IDLE_CLOCK_OUT, true, true, true).timeout.connect(_end_run_now)


## THE PARTY CARRIES ITS DEAD. Clearing a floor stands your ghost back up — you did
## not get picked up in the fight, but your friend finished it for both of you, and
## making a ghost ride the lift as a ghost would leave them dead for the whole next
## floor with no way back.
##
## Runs per-peer on the hero THIS peer owns (position syncs from the owner, so each
## peer reviving its own hero brings the whole party back up).
##
## ⚠ ONLY GHOSTS ARE REVIVED, AND ONLY TO `REVIVE_HP_FRACTION`. This used to call
## `revive()` on every local hero unconditionally, which full-healed the SURVIVOR
## too — so the optimal play on a hurt floor was to walk into the exit at 5 hp and be
## topped up, and dying just before it cost nothing at all. Neither of those should
## be true under a rule whose whole weight is "you only have so many bodies".
func _revive_local_heroes() -> void:
	var start: Vector2 = DEFAULT_HERO_START
	if _current_floor_def != null and _current_floor_def.layout != null:
		start = _current_floor_def.layout.hero_start
	var i: int = 0
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if not (h is Node2D) or not h.is_multiplayer_authority():
			continue
		if h.has_method("is_downed") and bool(h.call("is_downed")) and h.has_method("revive"):
			h.call("revive", DeathRules.REVIVE_HP_FRACTION)
		(h as Node2D).global_position = start + Vector2(50.0 * float(i), 0.0)
		i += 1


## ⚠ `_clear_enemies()` AND `_revive_hero()` ARE DELETED WITH THE FALL RULE. Both
## existed only to service `_on_fell` — rebuild the dropped floor in place and stand
## the single hero back up. Nothing falls any more (see `DeathRules`), so neither had
## a caller left, and a dead helper in a file this size is a trap waiting for someone
## to wire it back up to a rule that no longer exists.


## THE GAME OVER CARD. Every hero is a ghost; the run is over. Holds for
## `DeathRules.GAME_OVER_HOLD` while the ghosts drift under it, then offers the two
## exits and WAITS. It does not navigate for you any more.
##
## The second line names what the death actually cost, and that line changes with the
## policy: under the shipped rule the climb is KEPT, so it says so — a player who
## just lost a fight needs to know immediately that they did not lose the tower.
func _show_game_over() -> void:
	# `_wipe_handled` is cleared by a floor advance (the normal case), so in the narrow
	# window where a floor changes while the party is already all-ghosts the verdict can
	# be reached twice. `game_over()` is idempotent (it guards on `_run_active`); the
	# CARD is not, and two stacked ones would render as a smear.
	if _game_over_shown:
		return
	_game_over_shown = true
	_freeze_combatants()
	var layer := CanvasLayer.new()
	# ⚠ 85, NOT 70. `TouchControls` also sits on 70, and two CanvasLayers on the same
	# layer resolve taps by tree order — which put the thumbstick over the card's
	# button on a phone, the one device this has to work on. 85 clears the HUD (60) and
	# the leave-confirm (80) and still passes under the pause menu (90).
	layer.layer = 85
	# The card must stay alive if anything pauses the tree under it (the pause menu
	# does exactly that), or the only way out of a finished run becomes a dead button.
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # the run is over; nothing behind it wants taps
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(CARD_PAPER, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	# THE CARD IS AN ACTUAL CARD. Loose text over a dim is what an engine error looks
	# like; a bordered page is what the rest of this game looks like. One flat panel,
	# one hairline rule in the accent — no gradient, no shadow, no icon.
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = CARD_PAPER
	box.border_color = CARD_ASH
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.content_margin_top = 16.0
	box.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)
	var head := Label.new()
	# ⚠ 20 px, DOWN FROM 34, AND THE SKULLS ARE GONE. At 34 on a 640x360 base viewport
	# the headline was a third of the screen wide — it read as a shout over the fight
	# rather than a card the fight had stopped for. The skulls said nothing the two
	# words did not; they were decoration on a screen the maker wants plain.
	head.text = "GAME OVER"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", CARD_ASH)
	col.add_child(head)
	# The one line that survives the trim, because it is not flavour: it answers the
	# question a player has the instant they die, which is whether they just lost the
	# tower. See `_game_over_subtitle`.
	var note := Label.new()
	note.text = _game_over_subtitle()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", CARD_GRAPHITE)
	col.add_child(note)
	# THE TWO EXITS. Held back for `GAME_OVER_HOLD` so the word lands first and so a
	# key still held from the fight cannot choose for you, then revealed together.
	var exits := VBoxContainer.new()
	exits.add_theme_constant_override("separation", 4)
	exits.visible = false
	col.add_child(exits)
	# ⚠ THE ANTECHAMBER IS THE PROMINENT ONE, ON THE MAKER'S CALL: after a death the
	# thing you want is to change your class or your spells and go again, and that room
	# is where all of it lives. `visit_hub()` is the existing route; it is offered only
	# when the room is actually in this build, because a button that lands you nowhere
	# is worse than no button.
	if ResourceLoader.exists(HUB_SCENE_PATH):
		var again: Button = _confirm_button(
			"Return to Ashpire", _to_antechamber, CARD_CHALK)
		again.custom_minimum_size = Vector2(196, 34)
		exits.add_child(again)
	# …and the quiet one. Smaller type, dimmer ink, same tap target — restraint is in
	# the weight, never in the size of the thing your thumb has to find.
	var menu: Button = _confirm_button("Menu", _to_menu, CARD_GRAPHITE)
	menu.add_theme_font_size_override("font_size", 13)
	exits.add_child(menu)
	var reveal: Callable = func() -> void:
		if is_instance_valid(exits):
			exits.visible = true
	get_tree().create_timer(DeathRules.GAME_OVER_HOLD, true, true, true).timeout.connect(reveal)
	Juice.shake_camera(10.0)


## THE FIGHT STOPS WHEN THE RUN DOES.
##
## The card used to hang over a live battle: every hero was a ghost, so nothing was
## left to fight, and the enemies kept charging, casting and telegraphing at corpses
## for the whole hold. It read as a bug because it was one — the verdict had been
## reached and the arena had not been told.
##
## ⚠ DELIBERATELY NOT `get_tree().paused`. Pause is the wrong instrument here for
## three reasons, each on its own sufficient: the pause MENU can be opened over this
## card and its Resume would silently restart the fight underneath it; pause is local,
## so in co-op it would freeze one phone and not the other (the same reason
## `_on_return_taken` refuses it); and the hold exists so the ghosts can drift and the
## death spectacle can land, all of which pause would kill. Disabling the combatants
## leaves everything that is meant to keep moving moving.
##
## `PROCESS_MODE_DISABLED` propagates to children, so an enemy's synchronizers, timers
## and bound tweens stop with it. Nothing is freed — the scene change does that.
const FROZEN_GROUPS: Array[StringName] = [
	&"enemy",             # …and thralls/bosses, which join it via Enemy._ready
	&"thrall",
	&"enemy_projectile",
	&"telegraph",         # a tell for an attack that will never come
	&"player_spell",      # a dead hero's last cast should not go on killing for them
	&"stage_hazard",
]


func _freeze_combatants() -> void:
	# The spawner first: a wave scheduled one frame before the wipe would otherwise
	# walk fresh enemies onto the floor AFTER everything on it had been stopped.
	if is_instance_valid(_encounter):
		_encounter.process_mode = Node.PROCESS_MODE_DISABLED
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for group: StringName in FROZEN_GROUPS:
		for n: Node in tree.get_nodes_in_group(group):
			if is_instance_valid(n):
				n.process_mode = Node.PROCESS_MODE_DISABLED


## The verdict itself, reached either by the hold timer running out or by the player
## tapping through it. Host-or-single-player only; a co-op client's run is ended for
## it by the host (`Net.request_party_wipe` -> `_do_host_wipe`).
func _end_run_now() -> void:
	if _net != null and _net.is_active():
		if _net.is_host():
			_net.request_party_wipe()
	elif _gs != null and _gs.has_method("game_over"):
		_gs.game_over()


func _to_antechamber() -> void:
	# `visit_hub()` REPORTS rather than assumes — it returns false on a build with no
	# Antechamber. The button is already hidden in that case, so this is the second
	# belt: a stranded player is the one outcome that is not allowed.
	var go: Callable = func() -> void:
		if not bool(_gs.call("visit_hub")):
			_gs.call("go_to_title")
	_leave_to(go)


func _to_menu() -> void:
	_leave_to(func() -> void: _gs.call("go_to_title"))


## Close the run out and go somewhere. The two card buttons are the only callers.
##
## ⚠ THE ORDER IS LOAD-BEARING. `_end_run_now` runs FIRST so the death is CLOCKED —
## it ticks the falls counter, applies the climb policy and saves. Skipping it to
## navigate faster would make either button a way to die for free, which under
## `RESET_CLIMB_ON_GAME_OVER == false` is the only thing a death costs at all.
##
## `end_run` then queues the summary scene and `destination` queues the real one over
## it. Both land in the same frame and `SceneTree.change_scene_to_file` keeps only the
## last request, so the player arrives where they tapped. The summary is built and
## discarded inside that one deferred flush without ever being drawn — a known and
## accepted cost of `GameState.end_run` welding "clock the death" to "navigate", which
## cannot be unpicked from here.
##
## ⚠ AND IT HAPPENS ONCE. A double-tap during the scene change would otherwise stack a
## second pair of `change_scene_to_file` calls on a half-torn-down tree.
func _leave_to(destination: Callable) -> void:
	if _exit_taken or _gs == null:
		return
	_exit_taken = true
	_end_run_now()
	# A client's run is the host's to end, so leaving the session IS its exit. The host
	# must not do this here: `Net._on_gs_run_ended` already tears the session down
	# (deferred, so the wipe it just sent actually reaches the clients first).
	if _is_net_client():
		_net.leave()
	destination.call()


func _game_over_subtitle() -> String:
	var floor_now: int = _gs.current_floor() if _gs != null else 1
	if DeathRules.RESET_CLIMB_ON_GAME_OVER:
		return "the climb begins again"
	return "the climb holds — you return to Floor %d" % floor_now


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
## Spawn the hero(es). SP: one local hero at the classic centre. Co-op: the host
## spawns one Hero per peer through a MultiplayerSpawner (each with that peer's
## authority); clients get the spawns replicated automatically. The hero used to
## be hard-coded in Arena.tscn — it's now created here so co-op can vary the count.
var _heroes_root: Node2D = null
var _hero_spawner: MultiplayerSpawner = null


func _setup_heroes() -> void:
	_heroes_root = Node2D.new()
	_heroes_root.name = "Heroes"
	add_child(_heroes_root)
	var net: Node = get_node_or_null("/root/Net")
	if net != null and net.is_active():
		_hero_spawner = MultiplayerSpawner.new()
		_hero_spawner.name = "HeroSpawner"
		add_child(_hero_spawner)
		_hero_spawner.spawn_path = _heroes_root.get_path()
		_hero_spawner.spawn_function = Callable(self, "_spawn_hero_net")
		# THE READY HANDSHAKE, replacing the bare 0.6 s timer this used to be (whose
		# own comment admitted a handshake was the correct fix). A timer is a guess
		# about how long another phone takes to load a scene: too short and the spawn
		# arrives before the client's spawner exists and the hero is simply never
		# created there; too long and everyone stares at an empty room. Each peer's
		# Arena reports in from its own _ready and the host spawns when the party is
		# actually assembled — with a 4 s fallback inside Net so one silent peer
		# cannot hang the others.
		# THE HANDSHAKE IS NOW SCENE-KEYED (see the `party_ready` note in Net.gd). The
		# Antechamber uses the same machinery under its own tag, so this one re-arms
		# and reports under "arena" and the two can never satisfy each other's gate.
		net.call("rearm_handshake", "arena")
		if net.is_host() and not net.party_ready.is_connected(_spawn_all_heroes):
			net.party_ready.connect(_spawn_all_heroes)
		net.call("notify_arena_ready", "arena")
	else:
		var h: Node = load("res://scenes/combat/Hero.tscn").instantiate()
		(h as Node2D).position = DEFAULT_HERO_START
		_heroes_root.add_child(h)


func _spawn_all_heroes(tag: String = "arena") -> void:
	# Another scene's handshake completing is not this scene's cue to spawn a party.
	if tag != "arena":
		return
	var net: Node = get_node_or_null("/root/Net")
	if net == null or not net.is_host() or _hero_spawner == null:
		return
	var i: int = 0
	for pid in net.peers():
		var pos: Vector2 = DEFAULT_HERO_START + Vector2(60.0 * float(i), 0.0)
		_hero_spawner.spawn({"peer": int(pid), "cls": int(net.class_of(pid)), "x": pos.x, "y": pos.y})
		i += 1


## Co-op: a MultiplayerSpawner that replicates the host's enemy spawns (AND despawns
## on death) to every client. spawn_path is the Arena itself, so enemies stay DIRECT
## Arena children exactly like SP (their get_parent()==Arena world-spawning is
## unchanged). Both host + clients build each enemy from the same replicated data via
## Encounter.build_enemy_from_data; only the host runs their AI (Enemy gates on
## authority). No-op in SP — Encounter falls back to direct add_child.
var _enemy_spawner: MultiplayerSpawner = null


func _setup_enemy_spawner() -> void:
	var net: Node = get_node_or_null("/root/Net")
	if net == null or not net.is_active():
		return
	_enemy_spawner = MultiplayerSpawner.new()
	_enemy_spawner.name = "EnemySpawner"
	add_child(_enemy_spawner)
	_enemy_spawner.spawn_path = get_path()   # enemies are direct Arena children
	_enemy_spawner.spawn_function = Callable(self, "_spawn_enemy_net")
	_encounter.set_net_spawner(_enemy_spawner)


## Runs on every peer with identical spawn data. The host owns every enemy (authority
## = peer 1); clients build the same node as a puppet driven by the enemy's NetSync.
func _spawn_enemy_net(data: Dictionary) -> Node:
	var e: CharacterBody2D = _encounter.build_enemy_from_data(data)
	e.set_multiplayer_authority(1)
	return e


## The floor's Encounter — the live-entity budget authority. Enemies reach it
## through their parent (the Arena) to ask for spawn headroom; null in scenes
## that have no encounter.
func encounter() -> Encounter:
	return _encounter


## Route a runtime-spawned enemy (summoner minions, boss adds) through the same
## replicated path in co-op, or straight into the arena in SP. Called by enemies via
## get_parent().spawn_extra_enemy(...) — get_parent() is the Arena.
func spawn_extra_enemy(data: Dictionary) -> Node:
	# THE HARD CHOKE POINT for the 25-entity cap (1.4). Summoner minions and boss
	# adds both land here, so even a caller that forgets to ask can_spawn() first
	# cannot push the floor past its ceiling.
	if _encounter != null and not _encounter.can_spawn(1):
		return null
	if _enemy_spawner != null:
		return _enemy_spawner.spawn(data)
	var e: CharacterBody2D = _encounter.build_enemy_from_data(data)
	add_child(e)
	return e


## MultiplayerSpawner custom spawn — runs on every peer with identical data, so
## authority assignment is deterministic. Set props BEFORE the spawner adds it.
func _spawn_hero_net(data: Dictionary) -> Node:
	var h: Node = load("res://scenes/combat/Hero.tscn").instantiate()
	h.name = "Hero_%d" % int(data["peer"])
	(h as Node2D).position = Vector2(float(data["x"]), float(data["y"]))
	h.set("net_class", int(data["cls"]))
	h.set_multiplayer_authority(int(data["peer"]))
	return h


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
	# "Town" was a place this game no longer goes. Leaving mid-floor banks nothing and
	# lands on the run summary; leaving the sandbox lands on the title.
	_pause_menu.build("Leave the Tower")
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


## Leave the tower. Mid-floor in a run -> abandon (no bank, resume here next time),
## which routes through the run-summary card. Sandbox (no active run, i.e. the F6
## developer entry) -> the TITLE screen. NOT the parked v0.0 hub: see the note on
## the else branch, and `FreePlay._exit_to_hub`.
func _exit_to_hub() -> void:
	get_tree().paused = false
	if _gs != null and _gs.is_run_active() and _gs.has_method("abandon_to_hub"):
		_gs.abandon_to_hub()          # -> save, then the run-summary ceremony
	else:
		# NO RUN IS ACTIVE — the F6 feel sandbox, a boss rush, a free-play stage with
		# nobody on it. There is nothing to summarise and nothing to bank, so this must
		# NOT reach the run-end ceremony (`end_run` refuses on `_run_active` anyway);
		# it goes to the title screen, which is the boot scene and works on a phone.
		# It used to load the parked v0.0 AI-NPC town, which does not.
		get_tree().change_scene_to_file(GameState.TITLE_SCENE)


## Another go at the guardian: re-arm the flag and rebuild this scene.
func _restart_boss_rush() -> void:
	boss_rush = true
	get_tree().paused = false
	get_tree().reload_current_scene()


## Back to the 1v1 you came from.
func _exit_to_duel() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/combat/VersusArena.tscn")


# ------------------------------------------------------------------- theme/UI
## Themed atmosphere per floor band (tint + vignette + drifting motes) so each
## layer of the climb reads distinct — richer than the old flat colour wash.
func _build_theme_layer() -> void:
	_atmo = Atmosphere.new()
	add_child(_atmo)


## ⚠ TAKES THE WHOLE THEME, NOT A COLOUR. It used to take a bare tint and derive the
## highlight from it, which meant every floor was the same picture in a different
## hue — and with only three hues authored, mostly the same hue too.
##
## A biome now carries its own ACCENT (so Frostmarch highlights white-blue and the
## Emberworks highlights orange, rather than both highlighting a lighter version of
## their own wash) and its own EXPOSURE. `lit_wash()` applies the exposure; the
## authored hue stays readable in the table and in a diff, because `light` is a
## treatment rather than part of the colour.
func _apply_theme(theme: EnvTheme) -> void:
	if theme == null:
		return
	var wash: Color = theme.lit_wash()
	if _atmo != null:
		_atmo.build_wash(wash, theme.accent())
	# THE DRAWN ROOM TAKES THE FLOOR'S HUE TOO. Without this the shell would be the
	# same slab on all ten floors while the wash around it changed, which is the exact
	# "every floor is the same picture in a different hue" failure EnvTheme was
	# widened to fix. The shell keeps its own size — only the colour is pushed here.
	var shell: RoomShell = get_node_or_null("RoomShell") as RoomShell
	if shell != null:
		shell.build(shell.room_size, wash)
	PostProcess.set_theme(wash)  # re-tint the grade to match the floor


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
