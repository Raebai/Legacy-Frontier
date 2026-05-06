extends StaticBody2D

@export var data: NPCData

@onready var hint_label: Label = $HintLabel
@onready var proximity_area: Area2D = $ProximityArea

var _player_in_range: bool = false


func _ready() -> void:
	hint_label.visible = false
	proximity_area.body_entered.connect(_on_body_entered)
	proximity_area.body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("talk") and _player_in_range and not Dialogue.is_open():
		Dialogue.open(data)
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		hint_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		hint_label.visible = false
