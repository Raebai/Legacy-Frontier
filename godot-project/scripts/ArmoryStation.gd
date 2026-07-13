extends StaticBody2D
## Armory station on the hub's second-floor loft (maker: "maybe a second floor for
## stuff like armaments"). A weapon-rack you walk up to and press E — for now it
## shows a short toast (gear/loadout is a later feature); the point is the hub has
## a proper armory space. Same walk-up idiom as the NPCs / altar / tower door.

const HINT_TEXT: String = "[E] Armory"
const TOAST_TEXT: String = "⚒  Armory — gear & spell loadout coming soon"
const RACK_COLOR: Color = Color(0.32, 0.26, 0.2)
const BLADE_COLOR: Color = Color(0.7, 0.75, 0.82)

var _hint: Label = null
var _toast: Label = null
var _in_range: bool = false
var _toast_t: float = 0.0


func _ready() -> void:
	# A little weapon rack: a post with a couple of blades leaning on it.
	var post := ColorRect.new()
	post.color = RACK_COLOR
	post.size = Vector2(6.0, 30.0)
	post.position = Vector2(-3.0, -30.0)
	add_child(post)
	for dx: float in [-8.0, 8.0]:
		var blade := ColorRect.new()
		blade.color = BLADE_COLOR
		blade.size = Vector2(3.0, 26.0)
		blade.position = Vector2(dx, -28.0)
		blade.rotation = 0.2 * signf(dx)
		add_child(blade)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26.0, 30.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -15.0)
	add_child(shape)
	var area := Area2D.new()
	add_child(area)
	var area_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	area_shape.shape = circle
	area_shape.position = Vector2(0.0, -15.0)
	area.add_child(area_shape)
	area.body_entered.connect(func(b: Node) -> void:
		if b.is_in_group("player"): _in_range = true; _hint.visible = true)
	area.body_exited.connect(func(b: Node) -> void:
		if b.is_in_group("player"): _in_range = false; _hint.visible = false)
	_hint = Label.new()
	_hint.text = HINT_TEXT
	_hint.position = Vector2(-30.0, -54.0)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.visible = false
	add_child(_hint)
	_toast = Label.new()
	_toast.text = TOAST_TEXT
	_toast.position = Vector2(-96.0, -80.0)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_toast.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.95))
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.visible = false
	add_child(_toast)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("talk") or not _in_range:
		return
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		return
	_toast.visible = true
	_toast_t = 2.5
	get_viewport().set_input_as_handled()
