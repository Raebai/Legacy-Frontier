class_name ExitPortal
extends Area2D
## Floor-clear exit. Appears when a run floor is cleared; walking the hero into
## it advances the run to the next floor (or ends it in victory past the last).
## Primitive-drawn pulsing ring placeholder; shader VFX later.

signal taken

const RADIUS: float = 30.0

var _t: float = 0.0
var _armed: bool = false   # ignore the entry-frame overlap; require a real walk-in


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	cs.shape = circle
	add_child(cs)
	var label := Label.new()
	label.text = "EXIT"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-40, -RADIUS - 24)
	label.size = Vector2(80, 16)
	label.add_theme_color_override("font_color", Color(0.7, 1.0, 1.0, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.1, 0.12, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	body_entered.connect(_on_body_entered)
	# Arm after a beat so the portal can spawn under the hero without instantly
	# firing — the hero must actually step in (or step out and back).
	get_tree().create_timer(0.35).timeout.connect(func() -> void: _armed = true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if _armed and body.is_in_group("hero"):
		taken.emit()


func _draw() -> void:
	var pulse: float = 0.6 + 0.4 * sin(_t * 4.0)
	draw_circle(Vector2.ZERO, RADIUS, Color(0.3, 0.9, 1.0, 0.16 * pulse))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 44, Color(0.5, 1.0, 1.0, 0.85 * pulse), 3.0)
	draw_arc(Vector2.ZERO, RADIUS * 0.6, 0.0, TAU, 32, Color(0.8, 1.0, 1.0, 0.5 * pulse), 2.0)
