class_name Juice
extends RefCounted
## Static game-feel helpers. Time-scale-safe so hit-stop restores itself.

# The active SceneTree is reachable via Engine's main loop.
static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func hit_stop(duration: float = 0.06) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	Engine.time_scale = 0.05
	# ignore_time_scale = true so the restore timer runs in real time.
	var timer: SceneTreeTimer = tree.create_timer(duration, true, false, true)
	await timer.timeout
	Engine.time_scale = 1.0


static func shake_camera(amount: float = 6.0) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("combat_camera"):
		if cam.has_method("add_shake"):
			cam.add_shake(amount)


## Directional camera punch along `dir` (px), eases back — pairs with
## shake_camera for hits that have a clear direction (melee follow-through).
static func kick_camera(dir: Vector2, amount: float) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("combat_camera"):
		if cam.has_method("kick"):
			cam.kick(dir, amount)


## Quick zoom-in kick that eases back — the "camera lunges at the blast" beat.
static func zoom_punch_camera(amount: float = 0.1, duration: float = 0.18) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("combat_camera"):
		if cam.has_method("zoom_punch"):
			cam.zoom_punch(amount, duration)


## Temporary zoom-OUT that eases wide, holds, eases back — the "camera pulls back
## to show the big spell" beat (meteor / divine ray / ultimate spectacles).
static func zoom_pull_camera(amount: float = 0.16, hold: float = 0.5, ease_in: float = 0.12, ease_out: float = 0.55) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("combat_camera"):
		if cam.has_method("zoom_pull"):
			cam.zoom_pull(amount, hold, ease_in, ease_out)
