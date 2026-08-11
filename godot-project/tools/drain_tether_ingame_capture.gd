# Drain Tether, cast IN THE SPELL PLAYGROUND — the scene the maker actually plays.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/drain_tether_ingame_capture.gd
# Saves user://drain_tether_ig_{coil,lash,drain}.png.
#
# The synthetic bench (tools/drain_tether_capture.gd) has no physics world, so it
# cannot show the two things that only exist in a real arena: the whip cracking on
# level geometry (SpellWorld.first_solid), and the hook meeting a sparring dummy
# whose DRAWN HEAD sits ~19 px above its node origin. Those are exactly the cases
# the rework is about, so they get looked at here rather than assumed.
extends SceneTree

const TETHER_PATH: String = "res://scripts/combat/DrainTether.gd"

var _scene: Node = null
var _coil_done: bool = false
var _lash_done: bool = false
var _drain_done: bool = false


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	for i: int in 90:
		await physics_frame                     # let the figure + dummies settle on the floor
	var spell: SpellDef = _find_tether()
	if spell == null:
		printerr("drain_tether_ingame_capture: no drain_tether in the playground loadout")
		quit(1)
		return
	var origin: Vector2 = _caster_point()
	var target: Node2D = _far_dummy(origin)
	if target == null:
		printerr("drain_tether_ingame_capture: no dummy to aim at")
		quit(1)
		return
	# Aim at the drawn HEAD, not the node origin — the whole point of the
	# silhouette fix is that this is where a player aims.
	var at: Vector2 = target.head_point() if target.has_method("head_point") \
		else target.global_position
	SpellCaster.cast(spell, _scene, origin, at, Elements.color(Elements.Element.SHADOW), "")
	var whip: Node2D = _find_whip()
	var frames: int = 0
	var last_state: int = -1
	while frames < 900 and whip != null and is_instance_valid(whip):
		await physics_frame
		frames += 1
		# Re-check AFTER the await: a whip that cracked on cover frees itself
		# mid-frame, and reading a freed instance is an error, not a null.
		if not is_instance_valid(whip):
			break
		var st: int = int(whip.get("_state"))   # 0 COIL / 1 LASH / 2 DRAIN
		var t: float = float(whip.get("_t"))
		if st != last_state:
			last_state = st
			print("drain_tether_ingame_capture: state -> ", st, " at frame ", frames)
		# Independent flags, not an elif chain: the whip can blow through LASH in
		# three physics frames on a close target, and an ordered chain would then
		# jam and silently never take the later shots.
		if not _coil_done and st == 0 and t > 0.16:
			_coil_done = true
			await _save("drain_tether_ig_coil.png")
		elif not _lash_done and st == 1 and t > 0.02:
			_lash_done = true
			await _save("drain_tether_ig_lash.png")
		elif not _drain_done and st == 2 and t > 0.30:
			_drain_done = true
			await _save("drain_tether_ig_drain.png")
			break
	quit(0)


func _find_tether() -> SpellDef:
	for s: SpellDef in SpellLibrary.build_all():
		if s.id == "drain_tether":
			return s
	return null


## The playground rig drives a RigidBody2D torso hung off its node, so the node's
## own position is the spawn point, not the body — the same resolution RiftDagger
## does in `_owner_point`.
func _caster_point() -> Vector2:
	var fig: Node = _scene.get("_fig")
	if fig == null:
		return Vector2.ZERO
	var torso: Variant = fig.get("_torso")
	if is_instance_valid(torso) and torso is Node2D:
		return (torso as Node2D).global_position
	return (fig as Node2D).global_position if fig is Node2D else Vector2.ZERO


## The FURTHEST dummy still inside the whip's reach. Deliberately not the
## nearest: a close target is bitten within three physics frames, so the lash —
## the beat this whole rework is about — never gets a frame to be photographed in.
func _far_dummy(from: Vector2) -> Node2D:
	var reach: float = float((load(TETHER_PATH) as GDScript).get_script_constant_map()["RANGE"])
	var best: Node2D = null
	var bd: float = 0.0
	for e: Node in _scene.get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var d: float = from.distance_to((e as Node2D).global_position)
		if d > bd and d < reach * 0.9:
			bd = d
			best = e as Node2D
	return best


func _find_whip() -> Node2D:
	var script: GDScript = load(TETHER_PATH) as GDScript
	for n: Node in _scene.get_children():
		if n.get_script() == script:
			return n as Node2D
	return null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("drain_tether_ingame_capture: saved ", fname)
