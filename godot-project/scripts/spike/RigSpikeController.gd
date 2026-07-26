extends Node2D
## THROWAWAY SPIKE harness. One physics stick fighter on a floor with platforms +
## walls. Live-tune the gains on screen. Delete scripts/spike/ + scenes/spike/ to
## remove; touches no game code.

const FIG := preload("res://scripts/spike/SpikeFigure.gd")

const FLOOR_TOP := 300.0
const FIG_COLOR := Color(0.93, 0.51, 0.51)     # Stick Fight salmon red

var _fig: SpikeFigure
var _hud: Label
var _cam: Camera2D
var _shake := 0.0
var _shake_dir := Vector2.ZERO
var _capturing := false

var _knobs := {
	"stiffness": 3000.0,
	"damping": 90.0,
	"max_torque": 14000.0,
	"air_factor": 0.2,
	"grav_scale": 2.0,
	"jump_speed": 700.0,
	"move_speed": 300.0,
	"upright_k": 55000.0,
	"punch_lunge": 3400.0,
}
var _knob_order := ["stiffness", "damping", "max_torque", "air_factor", "grav_scale", "jump_speed", "move_speed", "upright_k", "punch_lunge"]
var _sel := 0


func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	get_viewport().use_hdr_2d = false          # game project has hdr_2d on; spike wants WYSIWYG color
	RenderingServer.set_default_clear_color(Color(0.24, 0.21, 0.17))   # warm Stick Fight brown
	_mute_game_overlays()
	_center_window()
	_build_world()
	_spawn_figure()
	_build_camera()
	_build_hud()
	if OS.get_cmdline_user_args().has("--spikecap"):
		_capture_sequence()


func _mute_game_overlays() -> void:
	# the spike scene runs inside the full game project — hide the game's autoload
	# HUD/overlay layers (rank banner, dimmers) so renders show ONLY the spike.
	# Runtime visibility only; touches no game code. Some HUDs build deferred, so
	# sweep again over the first few frames.
	for i in 8:
		var scene := get_tree().current_scene
		for child in get_tree().root.get_children():
			if child == scene or child == self:
				continue
			_hide_canvases(child)
		await get_tree().process_frame


func _hide_canvases(n: Node) -> void:
	if n is CanvasLayer:
		n.visible = false
		return
	if n is CanvasItem:
		n.visible = false
		return
	for c in n.get_children():
		_hide_canvases(c)


func _center_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	w.mode = Window.MODE_WINDOWED
	w.size = Vector2i(1280, 720)
	var usable := DisplayServer.screen_get_usable_rect(0)
	var pos := usable.position + (usable.size - Vector2i(1280, 720)) / 2
	DisplayServer.window_set_position(pos)
	DisplayServer.window_set_current_screen(0)
	DisplayServer.window_request_attention()
	w.grab_focus()


func _build_world() -> void:
	# a BOX arena — floor + ceiling + two side walls so you can wall-jump around INSIDE it,
	# plus a few interior ledges to kick between
	var half_w := 430.0                # interior half-width (compact — walls close for wall-jumping)
	var floor_y := 340.0               # floor SURFACE
	var ceil_y := -110.0               # ceiling SURFACE
	var th := 44.0
	var mid_y := (floor_y + ceil_y) * 0.5
	var wall_h := (floor_y - ceil_y) + th * 2.0
	_static_rect(Vector2(0, floor_y + th * 0.5), Vector2(half_w * 2 + th * 2, th))   # floor
	_static_rect(Vector2(0, ceil_y - th * 0.5), Vector2(half_w * 2 + th * 2, th))    # ceiling
	_static_rect(Vector2(-half_w - th * 0.5, mid_y), Vector2(th, wall_h))            # left wall
	_static_rect(Vector2(half_w + th * 0.5, mid_y), Vector2(th, wall_h))             # right wall
	# interior ledges — wall-jump between these and the side walls
	_static_rect(Vector2(-200, 200), Vector2(150, 22))
	_static_rect(Vector2(200, 90), Vector2(150, 22))


func _static_rect(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = SpikeFigure.WORLD_LAYER
	body.collision_mask = 0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	var ln := Polygon2D.new()
	ln.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	ln.color = Color(0.42, 0.45, 0.52)         # clearly-visible stone (was near-invisible vs the bg)
	ln.position = pos
	add_child(ln)


func _spawn_figure() -> void:
	_fig = FIG.new()
	_fig.spawn_pos = Vector2(0, 150)
	_fig.body_color = FIG_COLOR
	_fig.configure(_knobs)
	add_child(_fig)
	_fig.punched.connect(func(d): _shake = maxf(_shake, 0.5); _shake_dir = d)


func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(0, 150)         # frame the box (figure stands on the floor)
	cam.zoom = Vector2(0.66, 0.66)         # zoomed OUT to show the whole box
	add_child(cam)
	cam.make_current()
	_cam = cam


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 4)
	_hud.visible = false            # clean screen by default — press TAB to show tuning
	layer.add_child(_hud)


func _physics_process(_delta: float) -> void:
	if _fig == null or _capturing:
		return
	var mx := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mx -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mx += 1.0
	_fig.ctrl_move_x = mx
	_fig.ctrl_jump = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_SPACE)
	_fig.ctrl_duck = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	_fig.ctrl_aim = get_global_mouse_position()
	_fig.ctrl_aim_hold = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _process(delta: float) -> void:
	if _hud != null:
		_hud.text = _hud_text()
	# keep the whole box framed during capture (static — don't chase the figure)
	# subtle punch screenshake (trauma decays; offset scales with trauma^2)
	if _cam != null:
		if _shake > 0.0:
			_shake = maxf(0.0, _shake - delta * 2.2)
			var amp := _shake * _shake * 5.0
			# tiny KICK in the punch direction + a whisper of random jitter
			_cam.offset = _shake_dir * amp * 1.6 + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * 0.35
		else:
			_cam.offset = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if _fig == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_fig.punch()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_H:
				var d := Vector2(_fig._facing if _fig._facing != 0 else 1.0, -0.35)
				_fig.hit(d.normalized(), 460.0)
			KEY_K:
				_fig.kill()
			KEY_R:
				get_tree().reload_current_scene()
			KEY_TAB:
				if _hud != null:
					_hud.visible = not _hud.visible
			KEY_BRACKETLEFT:
				_adjust(0.926)
			KEY_BRACKETRIGHT:
				_adjust(1.08)
			_:
				var idx: int = event.keycode - KEY_1
				if idx >= 0 and idx < _knob_order.size():
					_sel = idx


func _adjust(factor: float) -> void:
	var key: String = _knob_order[_sel]
	_knobs[key] = _knobs[key] * factor
	if _fig != null:
		_fig.configure(_knobs)


func _hud_text() -> String:
	var s := "PHYSICS RIG SPIKE — red fighter\n"
	s += "move: A/D or arrows   jump: W/Space/Up   duck: S/Down   aim: mouse   punch: click\n"
	s += "H = take a hit (stagger)   K = kill (floor ragdoll)   R = reset\n"
	s += "select knob: number keys   adjust: [ - ]\n\n"
	for i in _knob_order.size():
		var key: String = _knob_order[i]
		var mark := ">" if i == _sel else " "
		s += "%s %d %-11s %.1f\n" % [mark, i + 1, key, _knobs[key]]
	return s


# ---- throwaway motion capture (run with `-- --spikecap`) ----

func _capture_sequence() -> void:
	_capturing = true
	_cam.make_current()
	var t: RigidBody2D = _fig._parts["torso"]
	await _hold(180, func(): _drive(0.0, false, false, Vector2(150, -30)))
	_save("spike_aim_right.png")
	await _hold(45, func(): _drive(0.0, false, false, Vector2(-150, -30)))
	_save("spike_aim_left.png")
	await _hold(45, func(): _drive(0.0, false, false, Vector2(0, -160)))
	_save("spike_aim_up.png")
	# walk right — two frames across a stride
	await _hold(55, func(): _drive(1.0, false, false, Vector2(150, -20)))
	_save("spike_walk1.png")
	await _hold(7, func(): _drive(1.0, false, false, Vector2(150, -20)))
	_save("spike_walk2.png")
	await _hold(50, func(): _drive(0.0, false, false, Vector2(150, -20)))
	# jump while moving — capture early (launch streaks + limb fling), then mid-air
	# (loose dangling ragdoll limbs), then falling
	await _hold(8, func(): _drive(1.0, true, false, Vector2(150, -20)))
	_save("spike_jump.png")
	await _hold(22, func(): _drive(1.0, false, false, Vector2(150, -20)))
	_save("spike_jump2.png")
	await _hold(24, func(): _drive(1.0, false, false, Vector2(150, -20)))
	_save("spike_jump3.png")
	await _hold(60, func(): _drive(0.0, false, false, Vector2(150, -20)))
	# duck — hold it long enough to flop ALL THE WAY down (prone), capture mid + flat
	await _hold(20, func(): _drive(0.0, false, true, Vector2(150, -20)))
	_save("spike_duck_mid.png")
	await _hold(85, func(): _drive(0.0, false, true, Vector2(150, -20)))
	_save("spike_duck.png")
	# CRAWL — stay prone (down held) + press RIGHT → slow crawl along the ground
	await _hold(70, func(): _drive(1.0, false, true, Vector2(150, -20)))
	_save("spike_crawl.png")
	await _hold(50, func(): _drive(0.0, false, false, Vector2(150, -20)))
	# --- RESISTANCE: run into the right wall and lean INTO it (feel the obstacle) ---
	await _hold(240, func(): _drive(1.0, false, false, Vector2(150, -20)))   # pinned on the right wall
	_save("spike_wall_push.png")
	# --- WALL CLING + JUMP: hop up the wall, cling+slide (braced legs + dust), then climb off ---
	await _hold(2, func(): _drive(1.0, true, false, Vector2(150, -20)))      # ground hop up the wall
	await _hold(55, func(): _drive(1.0, false, false, Vector2(150, -20)))    # cling + SLIDE down, pressed in
	_save("spike_wall_cling.png")
	await _hold(3, func(): _drive(1.0, true, false, Vector2(150, -20)))      # WALL JUMP (holding in = climb kick)
	await _hold(8, func(): _drive(0.0, false, false, Vector2(150, -20)))
	_save("spike_wall_jump.png")
	await _hold(70, func(): _drive(0.0, false, false, Vector2(150, -20)))
	# --- FACING: face right, go prone, press LEFT while prone → must NOT auto-swap ---
	await _hold(40, func(): _drive(1.0, false, false, Vector2(150, -20)))    # face right
	await _hold(55, func(): _drive(0.0, false, true, Vector2(150, -20)))     # prone (facing locked)
	await _hold(45, func(): _drive(-1.0, false, true, Vector2(150, -20)))    # press LEFT while prone
	_save("spike_duck_turn.png")
	await _hold(60, func(): _drive(0.0, false, false, Vector2(150, -20)))
	# punch (settle upright first so the pose reads clean)
	await _hold(40, func(): _drive(0.0, false, false, Vector2(150, -40)))
	_fig.punch()
	await _hold(5, func(): _drive(0.0, false, false, Vector2(150, -40)))
	_save("spike_punch.png")
	# hit stagger (stays standing)
	await _hold(60, func(): _drive(0.0, false, false, Vector2(150, -30)))
	_fig.hit(Vector2(0.94, -0.34), 460.0)
	await _hold(10, func(): _drive(0.0, false, false, Vector2(150, -30)))
	_save("spike_hit.png")
	# kill → floor ragdoll
	await _hold(60, func(): _drive(0.0, false, false, Vector2(150, -30)))
	_fig.kill()
	await _hold(120, func(): _drive(0.0, false, false, Vector2(150, -30)))
	_save("spike_dead.png")
	get_tree().quit(0)


func _drive(mx: float, jump: bool, duck: bool, aim_off: Vector2) -> void:
	_fig.ctrl_move_x = mx
	_fig.ctrl_jump = jump
	_fig.ctrl_duck = duck
	_fig.ctrl_aim = _fig._parts["torso"].global_position + aim_off


func _hold(frames: int, fn: Callable) -> void:
	for i in frames:
		fn.call()
		await get_tree().physics_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("user://" + name)
		print("spikecap saved ", name)
