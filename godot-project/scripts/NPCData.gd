class_name NPCData
extends Resource

# Stable per-NPC id used for the persistence file path (user://npc_memory/<npc_id>.json).
# Leave empty for transient NPCs that should not persist memory across sessions.
@export var npc_id: String = ""
@export var npc_name: String = "Unknown"
@export_multiline var personality_prompt: String = ""
@export var stats: EntityStats = null  # data shape only in v0.0; behaviour wiring lands v0.5 (D-034)
