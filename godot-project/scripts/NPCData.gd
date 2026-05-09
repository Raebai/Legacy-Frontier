class_name NPCData
extends Resource

# Stable per-NPC id used for the persistence file path (user://npc_memory/<npc_id>.json).
# Leave empty for transient NPCs that should not persist memory across sessions.
@export var npc_id: String = ""
@export var npc_name: String = "Unknown"
@export_multiline var personality_prompt: String = ""
@export var stats: EntityStats = null  # data shape only; runtime mood/patience live on NPC instance from v0.5

# ---- v0.5 D-031 tier system ----------------------------------------------
# 0 = ambient (canned only, no LLM, E does nothing)
# 1 = side character (canned greeting + LLM dialogue, lighter memory) — not implemented in v0.5
# 2 = anchor (full LLM, full memory, async consolidation) — default keeps existing behaviour
@export_range(0, 2) var tier: int = 2

# ---- v0.5 D-034 patience tuning ------------------------------------------
@export_range(0.0, 0.5, 0.005) var patience_decay_rate: float = 0.05

# ---- Tier 0 ambient: canned line buckets (unused for Tier 2 anchors) -----
@export var canned_greetings: Array[String] = []
@export var canned_reactions_neutral: Array[String] = []
@export var canned_reactions_hostile: Array[String] = []
@export var canned_reactions_friendly: Array[String] = []
@export var canned_reactions_curious: Array[String] = []
