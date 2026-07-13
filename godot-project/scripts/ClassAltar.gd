extends StaticBody2D
## Hub Class-Select landmark. A gold pillar you walk up to and press E (tap) to
## open the ClassSelect panel — the exact walk-up-and-interact idiom as the NPCs
## and the tower portal, using the same `talk` action + "player" group. Builds its
## own body / trigger / hint in code (house style) so World can spawn it without a
## .tscn. Solid, so the player bumps it like an NPC.

const HINT_TEXT: String = "[E] Choose Class"
const PILLAR_COLOR: Color = Color(0.95, 0.82, 0.35)
const PROXIMITY_RADIUS: float = 42.0

var _hint: Label = null
var _in_range: bool = false


func _ready() -> void:
	# Visual: a gold pillar (a tall bright block so it reads as a landmark).
	var visual := ColorRect.new()
	visual.color = PILLAR_COLOR
	visual.size = Vector2(22, 30)
	visual.position = Vector2(-11, -20)
	add_child(visual)
	var glow := ColorRect.new()  # soft top accent
	glow.color = Color(1.0, 0.95, 0.6, 0.5)
	glow.size = Vector2(22, 6)
	glow.position = Vector2(-11, -22)
	add_child(glow)
	# Solid body collider (layer 1 so the top-down player bumps it).
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 26)
	shape.shape = rect
	shape.position = Vector2(0, -6)
	add_child(shape)
	# Proximity trigger.
	var area := Area2D.new()
	add_child(area)
	var area_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PROXIMITY_RADIUS
	area_shape.shape = circle
	area.add_child(area_shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	# Floating hint.
	_hint = Label.new()
	_hint.text = HINT_TEXT
	_hint.position = Vector2(-40, -46)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_hint.visible = false
	add_child(_hint)


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
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel == null or sel.is_open():
		return
	# Don't open over an active NPC conversation.
	var conv: Node = get_node_or_null("/root/Conversation")
	if conv != null and conv.has_method("is_input_open") and conv.is_input_open():
		return
	sel.open()
	get_viewport().set_input_as_handled()
