# Throwaway visual check for the BASIC BOLT redesign (agent-owned; safe to
# delete). GUI binary required — the dummy renderer draws nothing:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/bolt_agent_capture.gd
#
# Two shots, answering two different questions:
#   bolt_sheet.png  — every element's bolt, side by side, MAGNIFIED. "Are these
#                     eight different objects, or one object with the hue
#                     rotated?" is a question you cannot answer at 12 px, and the
#                     whole point of the redesign is that the answer changed.
#   bolt_flight.png — real Spell.tscn instances mid-flight in the playground, at
#                     game scale, so the wake / muzzle / travel read is judged at
#                     the size the maker actually sees.
#   bolt_impact.png — the same volley one beat later, landing on the dummies.
extends SceneTree

const SPELL_SCENE: String = "res://scenes/combat/Spell.tscn"
const BOLT_VISUAL: String = "res://scripts/combat/SpellBoltVisual.gd"
## The eight elements, in Elements.Element order.
const EFFECTS: Array[String] = [
	"fire", "frost", "lightning", "shadow", "arcane", "earth", "holy", "wind",
]
## Magnification for the sheet — a bolt is ~50 px end to end and the question
## being asked is about SILHOUETTE, which needs pixels.
const SHEET_ZOOM: float = 2.1
const SHEET_ROW_H: float = 41.0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await _sheet()
	await _flight()
	quit(0)


## A magnified line-up of every element's bolt visual, drawn standalone (no
## Spell parent) so nothing moves and the silhouettes can be compared directly.
func _sheet() -> void:
	var page := Node2D.new()
	root.add_child(page)
	var bg := ColorRect.new()
	bg.size = Vector2(1280, 720)
	bg.color = Color(0.03, 0.03, 0.045)
	page.add_child(bg)
	var script: GDScript = load(BOLT_VISUAL)
	for i: int in EFFECTS.size():
		var effect: String = EFFECTS[i]
		var holder := Node2D.new()
		holder.position = Vector2(230.0, 30.0 + SHEET_ROW_H * float(i))
		holder.scale = Vector2(SHEET_ZOOM, SHEET_ZOOM)
		page.add_child(holder)
		var vis: Node2D = script.new()
		holder.add_child(vis)
		# Same two calls the live Spell makes, in the same order.
		vis.call("set_tint", Elements.color(i))
		vis.call("set_shape", effect)
		var label := Label.new()
		label.text = effect
		label.position = Vector2(30.0, holder.position.y - 9.0)
		label.add_theme_font_size_override("font_size", 11)
		page.add_child(label)
	# Let the animated shapes tick a few frames so the guttering/restriking
	# variants are captured mid-animation rather than on their zeroth state.
	for i in 30:
		await physics_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://bolt_sheet.png")
		print("boltcap saved bolt_sheet.png")
	page.queue_free()
	for i in 5:
		await physics_frame


## Real bolts, real speed, real scale — fired across the playground at the dummy
## cluster so the wake, the muzzle and the impact are judged in situ.
func _flight() -> void:
	var scene: Node = (load("res://scenes/spike/SpellPlayground.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 70:
		await physics_frame
	var hud: Label = scene.get("_hud")
	if hud != null:
		hud.visible = false
	var fig: Node = scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	var bolt_scene: PackedScene = load(SPELL_SCENE)
	# One bolt per element, fanned slightly so they do not overlap in the frame.
	for i: int in EFFECTS.size():
		var b: Area2D = bolt_scene.instantiate()
		scene.add_child(b)
		b.global_position = origin + Vector2(0.0, -6.0 + 9.0 * float(i))
		b.set("element_id", i)
		b.call("set_element_color", Elements.color(i))
		b.call("launch", Vector2.RIGHT.rotated(deg_to_rad(-14.0 + 4.0 * float(i))))
	for i in 22:
		await physics_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://bolt_flight.png")
		print("boltcap saved bolt_flight.png")
	for i in 34:
		await physics_frame
	await RenderingServer.frame_post_draw
	var img2: Image = root.get_texture().get_image()
	if img2 != null:
		img2.save_png("user://bolt_impact.png")
		print("boltcap saved bolt_impact.png")
	scene.queue_free()
	for i in 5:
		await physics_frame
