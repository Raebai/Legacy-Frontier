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
