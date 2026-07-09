extends Area2D
## Ground weapon pickup — the hero walks over it to equip. Swaps the rig's
## weapon slot and the melee tuning via Hero.equip_weapon ("gear = visual
## + ability"). Placeholder _draw icon until real drop sprites exist.

@export var weapon_kind: String = "sword"

var _consumed: bool = false
var _phase: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# Gentle glow pulse so the pickup reads as interactable on the floor.
	_phase += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _consumed:
		return
	if not body.is_in_group("hero") or not body.has_method("equip_weapon"):
		return
	_consumed = true
	body.equip_weapon(weapon_kind)
	Sfx.play("cast", -6.0, 0.1)
	queue_free()


func _draw() -> void:
	var glow_alpha: float = 0.14 + 0.08 * sin(_phase * 3.0)
	draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.9, 0.4, glow_alpha))
	match weapon_kind:
		"sword":
			var blade_col := Color(0.85, 0.9, 1.0, 1.0)
			var hilt_col := Color(0.8, 0.6, 0.3, 1.0)
			draw_line(Vector2(-4, 6), Vector2(7, -7), blade_col, 2.5)  # blade
			draw_line(Vector2(-6, 1), Vector2(-1, 6), hilt_col, 2.0)  # crossguard
			draw_line(Vector2(-4, 6), Vector2(-7, 9), hilt_col, 2.5)  # grip
		_:
			draw_circle(Vector2.ZERO, 4.0, Color(0.9, 0.9, 0.9, 1.0))
