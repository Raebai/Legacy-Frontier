class_name ExitPortal
extends Area2D
## Floor-clear exit. Appears when a run floor is cleared; walking the hero into
## it advances the run to the next floor (or ends it in victory past the last).
## Primitive-drawn pulsing ring placeholder; shader VFX later.

signal taken

const RADIUS: float = 30.0

## Set before adding to the tree to reskin (the hub reuses this as the tower
## entrance). Defaults = cyan floor-exit.
var portal_label: String = "EXIT"
var ring_color: Color = Color(0.5, 1.0, 1.0)
## Which body group triggers the portal. The arena floor-exit wants the combat
## "hero"; the hub tower-entrance wants the hub "player" (they are DIFFERENT
## nodes in different groups — using the wrong one makes the portal never fire).
var trigger_group: String = "hero"

var _t: float = 0.0
var _armed: bool = false   # ignore the entry-frame overlap; require a real walk-in
var _taken: bool = false   # fire exactly once (poll + signal both guard on this)


func _ready() -> void:
	# ⚠ MASK 1 AND 2, AND WITHOUT IT THIS PORTAL COULD NOT SEE A HERO AT ALL. Measured:
	# a hero standing dead centre on the portal for 1.2 s produced `overlaps=0, taken=0`.
	# `Hero.tscn` is on collision layer 2; an Area2D's default mask is bit 1 alone. This
	# is the third place in the project to be caught by it — `ArmoryStation` and
	# `TowerDoor` each carry a paragraph about the same trap, and the town's pads went
	# silent the day the lobby body became a Hero. Watching both layers is the honest
	# fix: a portal's job is "is the person standing here", not "which scene are they".
	collision_mask = 1 | 2
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	cs.shape = circle
	add_child(cs)
	var label := Label.new()
	label.text = portal_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-70, -RADIUS - 24)
	label.size = Vector2(140, 16)
	label.add_theme_color_override("font_color", Color(ring_color.r, ring_color.g, ring_color.b, 0.95).lightened(0.3))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	body_entered.connect(_on_body_entered)
	# Arm after a beat so the portal can spawn under the hero without instantly
	# firing — the hero must actually step in (or step out and back).
	get_tree().create_timer(0.35).timeout.connect(func() -> void: _armed = true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	# Poll overlap each frame once armed: body_entered only fires on the ENTER
	# edge, which is missed if the body already overlaps when the portal arms or
	# only brushes the trigger. Polling get_overlapping_bodies makes walk-in
	# reliable. _taken guards against re-firing.
	if _armed and not _taken:
		for body in get_overlapping_bodies():
			if body.is_in_group(trigger_group):
				_fire()
				return


func _on_body_entered(body: Node) -> void:
	if _armed and body.is_in_group(trigger_group):
		_fire()


## Emit `taken` exactly once (guarded), regardless of whether the poll or the
## enter-signal got here first.
func _fire() -> void:
	if _taken:
		return
	_taken = true
	taken.emit()


func _draw() -> void:
	var pulse: float = 0.6 + 0.4 * sin(_t * 4.0)
	draw_circle(Vector2.ZERO, RADIUS, Color(ring_color.r, ring_color.g, ring_color.b, 0.16 * pulse))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 44, Color(ring_color.r, ring_color.g, ring_color.b, 0.85 * pulse), 3.0)
	draw_arc(Vector2.ZERO, RADIUS * 0.6, 0.0, TAU, 32, Color(ring_color.r, ring_color.g, ring_color.b, 0.5 * pulse).lightened(0.3), 2.0)
