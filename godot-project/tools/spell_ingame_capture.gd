# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/spell_ingame_capture.gd
# Verifies the full IN-GAME signature path: presses the Ultimate action so the
# hero casts its equipped SpellDef via SpellCaster, MP drains, and the floating
# HP/MP bars render over the fighters. 2x2 sheet -> user://spell_ingame.png:
#   [0] beam via Ultimate (bars + drained MP)   [1] beam mid
#   [2] divine ray via Ultimate (after cycling)  [3] bars close-up
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
const OUT: String = "user://spell_ingame.png"
const CELL: Vector2i = Vector2i(480, 270)

var _sheet: Image = null
var _hero: Node2D = null


func _initialize() -> void:
	root.add_child((load(SCENE) as PackedScene).instantiate())
	_sheet = Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.03, 0.03, 0.05, 1.0))
	_run()


func _run() -> void:
	for _i: int in 40:
		await process_frame
	_hero = _find_hero()
	_zoom(1.5)
	# --- Ultimate #1: the equipped beam, fired by the input action. ---
	_aim(0.86, 0.46)
	Input.action_press("ultimate")
	await _wait(1)
	Input.action_release("ultimate")
	await _wait(11)   # mid-charge: sigil visible, before the fire-frame hitstop
	_grab(0)
	await _wait(7)    # ~fire frame
	_grab(1)
	# --- Cycle to the divine ray (verify cycle_signature), then fire. ---
	for _c: int in 3:  # zoltraak -> frostpiercer -> infernal -> judgment (divine ray)
		Input.action_press("cycle_signature")
		await _wait(1)
		Input.action_release("cycle_signature")
		await _wait(1)
	if _hero != null:  # top up so the demo isn't gated by the shared ult cooldown
		_hero.set("mp", 100.0)
		_hero.set("_signature_cd_timer", 0.0)
	_aim(0.60, 0.5)
	Input.action_press("ultimate")
	await _wait(1)
	Input.action_release("ultimate")
	await _wait(27)
	_grab(2)
	# --- Bars close-up. ---
	_zoom(2.6)
	await _wait(6)
	_grab(3)
	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("spell_ingame: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("spell_ingame: save failed err=", err)
	quit(0)


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _aim(fx: float, fy: float) -> void:
	var ws: Vector2i = DisplayServer.window_get_size()
	Input.warp_mouse(Vector2(ws) * Vector2(fx, fy))


func _zoom(z: float) -> void:
	if _hero == null:
		return
	for child: Node in _hero.get_children():
		if child is Camera2D:
			(child as Camera2D).zoom = Vector2(z, z)
			return


func _grab(cell: int) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((cell % 2) * CELL.x, (cell / 2) * CELL.y))


func _find_hero() -> Node2D:
	var heroes: Array = get_nodes_in_group("hero")
	return heroes[0] as Node2D if not heroes.is_empty() else null
