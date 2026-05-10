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

# ---- v0.5 D-034 / D-040 patience tuning ----------------------------------
@export_range(0.0, 0.5, 0.005) var patience_decay_rate: float = 0.05

# Lightweight per-NPC vocabulary that aligns positively with patience —
# substring-contains (case-insensitive), so plurals / verb-forms / compounds
# typically match without per-form enumeration. Keep the list short (~5-10
# entries); long lists slow the per-turn check and over-trigger.
@export var interest_keywords: Array[String] = []

# ---- Tier 0 ambient: canned line buckets (unused for Tier 2 anchors) -----
@export var canned_greetings: Array[String] = []
@export var canned_reactions_neutral: Array[String] = []
@export var canned_reactions_hostile: Array[String] = []
@export var canned_reactions_friendly: Array[String] = []
@export var canned_reactions_curious: Array[String] = []

# ---- v0.5 M12 visual + relationship seeds --------------------------------
# Per-NPC tint applied to the placeholder ColorRect by NPC._ready. Default
# is Raebai's existing orange so first_npc.tres without an explicit setting
# renders identically to v0.0/M9.
@export var display_color: Color = Color(0.95, 0.5, 0.2, 1.0)

# Seed relationships merged into the runtime registry on _load_memory ONLY
# for entities not already present in the saved state. Lets two anchors
# start out "knowing" each other (e.g. Mirelle ↔ Raebai at valence 0.7)
# without needing a consolidation cycle to bootstrap.
#
# Each entry shape: {"entity_id": String, "valence": float, "key_facts": Array[String]}
# Inspector edits work via Godot's Dictionary editor.
@export var initial_relationships: Array[Dictionary] = []
