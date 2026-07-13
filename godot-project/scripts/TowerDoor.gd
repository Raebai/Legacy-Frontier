extends StaticBody2D
## The tower ENTRANCE in the hub — a proper doorway you walk up to and press E to
## enter (maker: "I shouldn't just walk into a circle; it should be a door, press E
## near it"). Same walk-up idiom as the NPCs + class altar. Builds its own arched
## stone door + glowing threshold in code; on E in range it starts the run.

const HINT_TEXT: String = "[E] Enter the Tower"
const FRAME_COLOR: Color = Color(0.16, 0.15, 0.2)
const STONE_COLOR: Color = Color(0.26, 0.24, 0.3)
const GLOW_COLOR: Color = Color(1.0, 0.62, 0.3)      # warm arcane threshold glow
const DOOR_W: float = 62.0
const DOOR_H: float = 96.0
const PROXIMITY_RADIUS: float = 52.0

var _hint: Label = null
var _in_range: bool = false
var _phase: float = 0.0


func _ready() -> void:
	# Threshold glow (behind the door — pulses in _process).
	var glow := ColorRect.new()
	glow.name = "Glow"
	glow.color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.5)
	glow.size = Vector2(DOOR_W - 12.0, DOOR_H - 12.0)
	glow.position = Vector2(-(DOOR_W - 12.0) * 0.5, -DOOR_H + 4.0)
	glow.z_index = -1
	add_child(glow)
	# Stone door body (dark) + a lighter arched frame around it.
	var frame := ColorRect.new()
	frame.color = STONE_COLOR
	frame.size = Vector2(DOOR_W + 16.0, DOOR_H + 12.0)
	frame.position = Vector2(-(DOOR_W + 16.0) * 0.5, -DOOR_H - 6.0)
	add_child(frame)
	var arch := Polygon2D.new()  # a pointed keystone arch on top
	arch.polygon = PackedVector2Array([
		Vector2(-(DOOR_W + 16.0) * 0.5, -DOOR_H - 6.0),
		Vector2((DOOR_W + 16.0) * 0.5, -DOOR_H - 6.0),
		Vector2(0.0, -DOOR_H - 34.0),
	])
	arch.color = STONE_COLOR
	add_child(arch)
	var door := ColorRect.new()
	door.color = FRAME_COLOR
	door.size = Vector2(DOOR_W, DOOR_H)
	door.position = Vector2(-DOOR_W * 0.5, -DOOR_H)
	add_child(door)
	# Solid collider so the player can't walk THROUGH the tower (must press E).
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(DOOR_W + 16.0, DOOR_H)
	shape.shape = rect
	shape.position = Vector2(0.0, -DOOR_H * 0.5)
	add_child(shape)
	# Proximity trigger + hint.
	var area := Area2D.new()
	add_child(area)
	var area_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PROXIMITY_RADIUS
	area_shape.shape = circle
	area_shape.position = Vector2(0.0, -DOOR_H * 0.5)
	area.add_child(area_shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_hint = Label.new()
	_hint.text = HINT_TEXT
	_hint.position = Vector2(-58.0, -DOOR_H - 54.0)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.visible = false
	add_child(_hint)


func _process(delta: float) -> void:
	_phase += delta
	var glow: ColorRect = get_node_or_null("Glow")
	if glow != null:
		glow.color.a = 0.35 + 0.2 * (0.5 + 0.5 * sin(_phase * 2.2))


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = true
		_hint.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = false
		_hint.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("talk") or not _in_range:
		return
	# Don't enter over an open class-select panel or an NPC chat.
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		return
	var conv: Node = get_node_or_null("/root/Conversation")
	if conv != null and conv.has_method("is_input_open") and conv.is_input_open():
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("enter_run"):
		get_viewport().set_input_as_handled()
		gs.enter_run()
