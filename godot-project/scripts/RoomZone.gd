class_name RoomZone
extends Area2D

# Stable per-room id ("first", "connector", "second" for v0.5).
# Bodies entering this zone receive room_id on their current_room_id property.
# Earshot logic in M14 broadcast reactions reads it.
@export var room_id: String = ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	# Direct property write — avoids method-existence checks and works for
	# any body (Player or NPC) that declares `current_room_id: String`.
	if "current_room_id" in body:
		body.current_room_id = room_id
