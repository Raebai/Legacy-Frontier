# Throwaway visual check for the LIGHTNING spells (thunderclap RUSH + chain_lightning
# CHAIN). GUI binary — the headless renderer draws nothing, so this MUST be run
# with the windowed build:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/lightning_agent_capture.gd
# PNGs land in %APPDATA%\Godot\app_userdata\Legacy Frontier\.
extends SceneTree

var _scene: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _spell(id: String) -> SpellDef:
	for s: SpellDef in _scene.get("_spells"):
		if s.id == id:
			return s
	return null


func _run() -> void:
	for i in 70:
		await physics_frame                      # settle the figure + dummies on the floor
	var fig: Node = _scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	# Aim flat-right down the dummy line so the lance crosses both dummies.
	var target := Vector2(origin.x + 500.0, origin.y)

	# --- CHIDORI (RUSH) --------------------------------------------------
	SpellCaster.cast(_spell("thunderclap"), _scene, origin, target, Color(1.0, 0.9, 0.35), "")
	# 120 Hz. CHARGE_TIME 0.16 = frame 19; FLASH_TIME 0.05 = 6 more frames.
	for i in 14:
		await physics_frame
	await _save("lightning_thunderclap_charge.png")   # the tell, mid-charge
	for i in 8:
		await physics_frame
	await _save("lightning_thunderclap_flash.png")    # inside the flash window
	for i in 6:
		await physics_frame
	await _save("lightning_thunderclap_strike.png")   # bolt at full, flash gone
	for i in 10:
		await physics_frame
	await _save("lightning_thunderclap_fade.png")     # guttering afterimage

	for i in 60:
		await physics_frame

	# --- CHAIN LIGHTNING (CHAIN) ----------------------------------------
	var origin2: Vector2 = (fig.get("_torso") as Node2D).global_position
	SpellCaster.cast(_spell("chain_lightning"), _scene, origin2,
		Vector2(origin2.x + 500.0, origin2.y), Color(1.0, 0.95, 0.4), "")
	for i in 8:
		await physics_frame
	await _save("lightning_chain_early.png")
	for i in 14:
		await physics_frame
	await _save("lightning_chain_late.png")
	quit(0)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("ltcap saved ", fname)
