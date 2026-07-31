# Visual verification for the DROP ECONOMY's pickup entity + the handoff prompt.
# GUI binary required — the headless dummy renderer draws nothing:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/drop_capture.gd
# Output lands in %APPDATA%\Godot\app_userdata\Legacy Frontier\.
#
# WHAT TO LOOK FOR, because these are the claims only an eyeball can settle:
#   * THE TIER READS BEFORE THE NAME. A Tier 3 is bigger, gold, and wears three
#     rotating shards; a Tier 2 wears one thin ring in its own element colour. If
#     you cannot tell them apart with the frame at arm's length, the crown has
#     failed and the fix is the crown, not the label.
#   * THE BEACON SURVIVES A BUSY FLOOR. `drop_3_wide_640x360.png` is framed at the
#     ACTUAL game resolution with cover in the way. That is the real test: a pickup
#     you cannot find from across the room is not contested, and "both players race
#     for it" is the spec's requirement.
#   * THE NAME IS LEGIBLE AT 11 px over the arena floor tint. It is drawn twice
#     (dark, then light) for exactly this reason.
#   * THE HANDOFF PROMPT points at the RECEIVER, not the giver, and names the spell.
extends SceneTree

const PICKUP := "res://scenes/combat/SpellPickup.tscn"
const FLOOR_TOP: float = 150.0

## Close framing for the two shelf shots.
const NEAR_ZOOM: float = 1.15
## THE HONEST ONE. The project renders at a 640x360 base viewport, so this frame is
## what a phone actually shows — if the beacon does not survive here it does not
## survive at all.
const WIDE_ZOOM: float = 0.5

var _scene: Node2D = null
var _cam: Camera2D = null


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await physics_frame
	await _capture_shelves()
	await _capture_wide()
	quit(0)


## Tier 2 beside Tier 3, so the crown difference is a comparison and not a memory.
func _capture_shelves() -> void:
	_build(Vector2(0.0, 60.0), NEAR_ZOOM)
	_drop("petrify", Vector2(-140.0, FLOOR_TOP))
	_drop("the_void", Vector2(140.0, FLOOR_TOP))
	await _hold(40)
	await _save("drop_1_tier2_vs_tier3.png")
	await _hold(50)   # the Tier 3 shards rotate — a second phase of the same shot
	await _save("drop_2_tier3_shards_rotated.png")
	_teardown()


## The real question: can you find it at 640x360 with cover in the way?
func _capture_wide() -> void:
	_build(Vector2(0.0, 20.0), WIDE_ZOOM)
	for x: float in [-260.0, -120.0, 90.0, 250.0]:
		_rect(_scene, Vector2(x, FLOOR_TOP - 34.0), Vector2(56.0, 68.0),
			Color(0.30, 0.26, 0.30))
	_drop("meteor_storm", Vector2(200.0, FLOOR_TOP))
	_drop("chronostasis", Vector2(-320.0, FLOOR_TOP))
	await _hold(40)
	await _save("drop_3_wide_640x360.png")
	_teardown()


func _drop(id: String, at: Vector2) -> void:
	var p: Area2D = (load(PICKUP) as PackedScene).instantiate()
	_scene.add_child(p)
	p.global_position = at
	p.call(&"set_spell", id)


func _hold(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _build(cam_at: Vector2, zoom: float) -> void:
	RenderingServer.set_default_clear_color(Color(0.13, 0.14, 0.18))
	_scene = Node2D.new()
	Atmosphere.add_glow(_scene)
	PostProcess.add(_scene)
	root.add_child(_scene)
	_rect(_scene, Vector2(0.0, FLOOR_TOP + 40.0), Vector2(1800.0, 80.0),
		Color(0.20, 0.22, 0.27))
	_cam = Camera2D.new()
	_cam.position = cam_at
	_cam.zoom = Vector2(zoom, zoom)
	_scene.add_child(_cam)
	_cam.make_current()


func _rect(parent: Node, at: Vector2, size: Vector2, col: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	p.color = col
	p.position = at
	p.z_index = -5
	parent.add_child(p)


func _teardown() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("dropcap saved ", fname)
