extends StaticBody2D

@export var data: NPCData

@onready var hint_label: Label = $HintLabel
@onready var proximity_area: Area2D = $ProximityArea


func _ready() -> void:
	hint_label.visible = false
	proximity_area.body_entered.connect(_on_body_entered)
	proximity_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		hint_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		hint_label.visible = false
