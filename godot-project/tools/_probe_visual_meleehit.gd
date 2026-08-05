# READ-ONLY DIAGNOSTIC. GUI BINARY ONLY (headless writes blank PNGs):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_visual_meleehit.gd
#
# "WHEN I HIT SOMEONE THEY HAVE THIS WEIRD SPHERE-ISH WHITE THING ON THEM."
#
# Four candidates, and only a picture separates them:
#   (i)   a white BURST spawned at the contact point,
#   (ii)  a white MODULATE flash repainting the victim's own figure,
#   (iii) bloom — the arena adds a WorldEnvironment glow, and `Enemy._flash` paints
#         the victim at Color(1.7, 1.7, 1.7), i.e. HDR, i.e. deliberately blooming,
#   (iv)  an ImpactFrame LOCAL ring.
#
# So it shoots the SAME hit three ways, tightly zoomed on the VICTIM:
#   _pv_hit_N.png       an ordinary sword hit, arena glow ON  (what the maker sees)
#   _pv_hitnoglow_N.png the same hit with the WorldEnvironment removed
#   _pv_hurthero_N.png  the same damage dealt to a HERO, whose flash is already RED
# If (ii)/(iii) is the answer, the white blob is on the victim's own silhouette, it
# is gone in the no-glow strip, and the hero strip is red where the enemy strip is
# white. If (i)/(iv), a separate mark survives the no-glow strip.
extends SceneTree

const ARENA: String = "res://scenes/combat/Arena.tscn"
const ZOOM: float = 6.0

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


func _first_in(g: String) -> Node2D:
	var a: Array = _root.get_tree().get_nodes_in_group(g)
	return a[0] as Node2D if not a.is_empty() else null


func _shoot(prefix: String, at: Node2D, frames: int) -> void:
	for i: int in frames:
		_cam.position = at.global_position + Vector2(0.0, -6.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		print("%s user://%s_%d.png" % [
			"ok " if img.save_png("user://%s_%d.png" % [prefix, i]) == OK else "ERR",
			prefix, i])


func _run() -> void:
	for i: int in 120:
		await process_frame

	var hero: Node2D = _first_in("player")
	if hero == null:
		hero = _first_in("hero")
	var enemy: Node2D = null
	for n: Node in _root.get_tree().get_nodes_in_group("enemy"):
		enemy = n as Node2D
		break
	print("hero=%s enemy=%s" % [str(hero), str(enemy)])
	if hero == null or enemy == null:
		quit(1)
		return

	# Hide the HUD or every zoomed shot is a picture of the ability bar.
	for c: Node in _all(_root):
		if c is CanvasLayer and not (c is ImpactFrame):
			(c as CanvasLayer).visible = false
		if c is Camera2D:
			(c as Camera2D).enabled = false
	_cam = Camera2D.new()
	_root.add_child(_cam)
	_cam.make_current()
	_cam.zoom = Vector2(ZOOM, ZOOM)

	hero.call("equip_weapon", "sword")
	enemy.set("hp", 9999)
	enemy.set("max_hp", 9999)
	enemy.global_position = hero.global_position + Vector2(46.0, 0.0)
	for i: int in 40:
		await process_frame

	# ── 1. THE HIT AS THE MAKER MEETS IT ─────────────────────────────────────
	enemy.call("take_damage", 20)
	await _shoot("_pv_hit", enemy, 8)

	# ── 2. THE SAME HIT WITH THE ARENA'S BLOOM TAKEN AWAY ────────────────────
	for c: Node in _all(_root):
		if c is WorldEnvironment:
			(c as WorldEnvironment).environment = null
	for i: int in 40:
		await process_frame
	enemy.call("take_damage", 20)
	await _shoot("_pv_hitnoglow", enemy, 8)

	# ── 3. A HERO TAKING THE SAME DAMAGE (its flash is already RED) ───────────
	hero.call("take_damage", 20)
	await _shoot("_pv_hurthero", hero, 8)

	# ── 4. THE PROPOSED FIX, POSED AT RUNTIME ────────────────────────────────
	# `Enemy._flash` paints Color(1.7, 1.7, 1.7). Hero already uses
	# Hero.HURT_FLASH_COLOR = Color(1.0, 0.2, 0.2). This is that one line, posed:
	# non-HDR, so the bloom has nothing to blow out either.
	var er: Node = enemy.get("rig")
	if er != null:
		er.call("flash_color", Color(1.0, 0.2, 0.2), 0.6)
	await _shoot("_pv_redfix", enemy, 3)
	quit(0)
