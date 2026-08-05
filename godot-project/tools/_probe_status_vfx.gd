# READ-ONLY DIAGNOSTIC. GUI BINARY ONLY (headless writes blank PNGs):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_status_vfx.gd
#
# "the lightning effect should be little lightning particles on the user, not that
#  large circle thing. Same with the frozen and burnt effects."
#
# Shoots each StatusComponent ailment overlay, zoomed hard on a HERO (the "user")
# and on an ENEMY, so the size of the drawn overlay can be compared against the
# 31px-tall rig it is supposed to be sitting on.
#
#   _ps_hero_<ail>_N.png / _ps_enemy_<ail>_N.png
extends SceneTree

const ARENA: String = "res://scenes/combat/Arena.tscn"
const ZOOM: float = 9.0

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


# Re-applies the ailment every frame so short ones (shock 0.35s, freeze 0.6s)
# stay lit for the whole strip.
func _shoot(prefix: String, at: Node2D, elem: int, reapply: int, frames: int) -> void:
	for i: int in frames:
		for _k: int in reapply:
			at.call("apply_status", elem, false)
		_cam.position = at.global_position + Vector2(0.0, -6.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		print("%s user://%s_%d.png" % [
			"ok " if img.save_png("user://%s_%d.png" % [prefix, i]) == OK else "ERR",
			prefix, i])


func _clear(at: Node2D) -> void:
	var s: Node = null
	for c: Node in at.get_children():
		if c.get_script() != null and c.has_method("slow_factor"):
			s = c
	if s != null:
		s.free()
	at.set("_status", null)
	for i: int in 10:
		await process_frame


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
	if hero == null:
		quit(1)
		return

	for c: Node in _all(_root):
		if c is CanvasLayer and not (c is ImpactFrame):
			(c as CanvasLayer).visible = false
		if c is Camera2D:
			(c as Camera2D).enabled = false
	_cam = Camera2D.new()
	_root.add_child(_cam)
	_cam.make_current()
	_cam.zoom = Vector2(ZOOM, ZOOM)

	hero.set("hp", 99999)
	hero.set("max_hp", 99999)
	if enemy != null:
		enemy.set("hp", 99999)
		enemy.set("max_hp", 99999)
		enemy.global_position = hero.global_position + Vector2(120.0, 0.0)
	for i: int in 30:
		await process_frame

	# LIGHTNING = shock arcs — the one the maker named first.
	await _shoot("_ps_hero_shock", hero, Elements.Element.LIGHTNING, 1, 6)
	await _clear(hero)
	# ICE applied twice per frame = chill then FREEZE (the ice block).
	await _shoot("_ps_hero_freeze", hero, Elements.Element.ICE, 2, 6)
	await _clear(hero)
	# ICE once, then let it sit as CHILL.
	hero.call("apply_status", Elements.Element.ICE, false)
	await _shoot("_ps_hero_chill", hero, -1, 0, 4)
	await _clear(hero)
	await _shoot("_ps_hero_burn", hero, Elements.Element.FIRE, 1, 6)
	await _clear(hero)
	await _shoot("_ps_hero_weaken", hero, Elements.Element.SHADOW, 1, 4)
	await _clear(hero)
	await _shoot("_ps_hero_unstable", hero, Elements.Element.ARCANE, 1, 4)
	await _clear(hero)

	if enemy != null:
		await _shoot("_ps_enemy_shock", enemy, Elements.Element.LIGHTNING, 1, 4)
		await _clear(enemy)
		await _shoot("_ps_enemy_burn", enemy, Elements.Element.FIRE, 1, 4)
	quit(0)
