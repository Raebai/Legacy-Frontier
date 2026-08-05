# READ-ONLY PROBE (safe to delete). LOOK at the ability bar at a size a human can judge.
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_bar_look.gd
#
# Frames (in %APPDATA%/Godot/app_userdata/Legacy Frontier/):
#   _probe_bar_context.png  full frame, so the bar is judged in the scene it lives in
#   _probe_bar_rest.png     bar band, everything READY, 3x NEAREST
#   _probe_bar_cool.png     bar band, four different cooldown fractions running, 3x
#   _probe_bar_tiny.png     bar band at TRUE 640x360 phone pixels, 6x NEAREST
extends SceneTree

const ARENA: String = "res://scenes/combat/VersusArena.tscn"
## Bar band in BASE (640x360) coords — the bar is centred and bottom-anchored.
const BAND_BASE: Rect2i = Rect2i(100, 282, 440, 78)
const PHONE: Vector2i = Vector2i(640, 360)


func _initialize() -> void:
	var scene: Node = (load(ARENA) as PackedScene).instantiate()
	root.add_child(scene)
	_run()


func _run() -> void:
	for i: int in 100:
		await process_frame
	var hero: Node = _local_hero()
	if hero == null:
		print("_probe_bar_look: no hero")
		quit(1)
		return
	print("_probe_bar_look: hero=%s class=%s" % [hero.name, hero.call("class_display_name")])
	var st: Array = hero.call("ability_hud_state")
	for s: Variant in st:
		print("  slot ", s)

	await _settle()
	await _shot_full("_probe_bar_context")
	await _shot_band("_probe_bar_rest", 3)
	await _shot_phone("_probe_bar_tiny", 6)

	# Four different cooldown fractions + the dash, so the veil, the timer text and
	# the ready-glow are all on screen in one frame.
	var fracs: Array[float] = [0.25, 0.6, 0.85, 0.45]
	for i: int in SpellTier.SLOT_COUNT:
		var sig: SpellDef = hero.call("signature_at", i) as SpellDef
		var cd: float = maxf(sig.cooldown, 1.0) if sig != null else 4.0
		hero._hand.start_cooldown(hero._hand_slot(i), cd * fracs[i])
	await _settle()
	await _shot_band("_probe_bar_cool", 3)
	quit(0)


func _local_hero() -> Node:
	for h: Node in root.get_tree().get_nodes_in_group("hero"):
		var bot: Variant = h.get(&"bot_driven")
		if (bot == null or not bool(bot)) and h.get(&"_bot") == null:
			return h
	var all: Array = root.get_tree().get_nodes_in_group("hero")
	return all[0] if not all.is_empty() else null


func _settle() -> void:
	for i: int in 8:
		await process_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _shot_full(name: String) -> void:
	var img: Image = await _grab()
	img.save_png("user://%s.png" % name)
	print("%s -> %dx%d" % [name, img.get_width(), img.get_height()])


## Crop the bar band out of the real framebuffer and blow it up with NEAREST, so
## every pixel judged is a pixel the renderer actually drew.
func _shot_band(name: String, zoom: int) -> void:
	var img: Image = await _grab()
	var s: float = float(img.get_width()) / 640.0
	var r := Rect2i(
		int(BAND_BASE.position.x * s), int(BAND_BASE.position.y * s),
		int(BAND_BASE.size.x * s), int(BAND_BASE.size.y * s)
	)
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var band: Image = img.get_region(r)
	band.resize(band.get_width() * zoom, band.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	band.save_png("user://%s.png" % name)
	print("%s -> band %s scale=%.2f out %dx%d" % [
		name, r, s, band.get_width(), band.get_height()])


## The honest phone read: squash the grab down to a real 640x360 framebuffer FIRST,
## crop 1:1, then upscale NEAREST. Anything that survives this survives a phone.
func _shot_phone(name: String, zoom: int) -> void:
	var img: Image = await _grab()
	img.resize(PHONE.x, PHONE.y, Image.INTERPOLATE_LANCZOS)
	var band: Image = img.get_region(BAND_BASE.intersection(Rect2i(Vector2i.ZERO, PHONE)))
	band.resize(band.get_width() * zoom, band.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	band.save_png("user://%s.png" % name)
	print("%s -> %dx%d" % [name, band.get_width(), band.get_height()])
