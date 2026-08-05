# READ-ONLY DIAGNOSTIC. GUI BINARY ONLY.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_visual_trail.gd
#
# THE WEAPON TRAIL'S ELEMENTAL CASE, WHICH HAD NEVER BEEN LOOKED AT. The trail
# takes `aura_color` when `aura_strength > 0`, so a fire fist is supposed to streak
# fire — but the frame that verified the trail existing was shot with no aura up, so
# the elemental branch was reasoned and not seen.
#
# A BRAWLER (fists, no blade) on FIRE, swinging, at the zoom the ribbon is actually
# visible at. Fists on purpose: a sword already drags a bright slash arc that would
# hide whether the ribbon under it is orange or grey, and the maker's own words for
# this feature were "if someone's using fire fist".
#
# It also PRINTS the two colours the branch chooses between, because "it looks
# orange" and "it took the aura branch" are different claims and only one of them
# survives a screenshot of a warm-lit arena.
extends SceneTree

const ARENA: String = "res://scenes/combat/Arena.tscn"
const BRAWLER: int = 2
const FIRE: int = 0

var _cam: Camera2D = null
var _root: Node = null


func _initialize() -> void:
	Engine.max_fps = 60
	_root = (load(ARENA) as PackedScene).instantiate()
	root.add_child(_root)
	_run.call_deferred()


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out


func _run() -> void:
	for i: int in 120:
		await process_frame
	var heroes: Array = _root.get_tree().get_nodes_in_group("player")
	if heroes.is_empty():
		heroes = _root.get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		printerr("no hero"); quit(1); return
	var hero: Node2D = heroes[0] as Node2D
	var enemy: Node2D = null
	for n: Node in _root.get_tree().get_nodes_in_group("enemy"):
		enemy = n as Node2D
		break
	if enemy == null:
		printerr("no enemy"); quit(1); return

	for c: Node in _all(_root):
		if c is CanvasLayer and not (c is ImpactFrame):
			(c as CanvasLayer).visible = false
		if c is Camera2D:
			(c as Camera2D).enabled = false
	_cam = Camera2D.new()
	_root.add_child(_cam)
	_cam.make_current()
	_cam.zoom = Vector2(5.0, 5.0)

	hero.call("configure_class", BRAWLER)
	hero.set("_element", FIRE)
	hero.call("_apply_element")
	# Rank tier drives how much aura GLOW is drawn; the trail keys off strength, not
	# tier. Lit here so the frame shows the case the maker would actually be in.
	var rig: Node2D = hero.get("rig") as Node2D
	if rig != null:
		rig.call("set_aura_tier", 2)
	enemy.set("hp", 9999)
	enemy.set("max_hp", 9999)
	enemy.global_position = hero.global_position + Vector2(40.0, 0.0)
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.set("facing", Vector2.RIGHT)
	for i: int in 30:
		await process_frame

	if rig != null:
		print("aura_strength = ", rig.get("aura_strength"),
			"   aura_color = ", rig.get("aura_color"),
			"   limb_color = ", rig.get("limb_color"))
		print("branch = ", "AURA (elemental)" if float(rig.get("aura_strength")) > 0.0 else "LIMB (grey)")

	var mid: Vector2 = hero.global_position.lerp(enemy.global_position, 0.5)
	_cam.position = mid + Vector2(0.0, -8.0)

	hero.call("_melee")
	for i: int in 26:
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var p: String = "user://_pv_trail_%02d.png" % i
		if img.save_png(p) != OK:
			printerr("ERR ", p)
	print("ok  26 trail frames")
	quit(0)
