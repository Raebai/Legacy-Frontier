extends StaticBody2D

const MEMORY_DIR: String = "user://npc_memory"
# MEMORY_VERSION lives on MemoryUtils; reference it via MemoryUtils.MEMORY_VERSION.

@export var data: NPCData

@onready var hint_label: Label = $HintLabel
@onready var proximity_area: Area2D = $ProximityArea
@onready var speech_bubble: Node2D = $SpeechBubble

var _player_in_range: bool = false

# v0.5 four-layer memory state (per docs/v0.5-design.md "Memory architecture").
# Persistent identity lives on `data` (NPCData resource).
# The other three layers are runtime state, persisted to user://npc_memory/<npc_id>.json
# at disengage / quit, hydrated from disk on _ready.
var short_term: Array[Dictionary] = []           # role/content dicts (same shape as v0.0 messages)
var long_term_summary: String = ""               # consolidated paragraph, populated by M10
var relationships: Dictionary = {}               # entity_id -> {valence, key_facts, gossip_inbox}
var mood: float = 0.0                            # NPC-wide; runtime override of data.stats.mood seed

# Runtime-only patience scalar — not persisted per docs/v0.5-design.md D-034.
# M11 wires the per-turn rule-based decay; M9 ships the slot at 1.0 (fresh).
var patience: float = 1.0


func _ready() -> void:
	hint_label.visible = false
	proximity_area.body_entered.connect(_on_body_entered)
	proximity_area.body_exited.connect(_on_body_exited)
	_load_memory()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("talk") and _player_in_range and not Conversation.is_engaged():
		Conversation.engage(self)
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		hint_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		hint_label.visible = false
		# If we were the engaged NPC and player walked away, end the conversation.
		if Conversation.is_engaged() and Conversation.engaged_npc() == self:
			Conversation.disengage()


func say(text: String, fade_seconds: float = 6.0) -> void:
	speech_bubble.say(text, fade_seconds)


func show_thinking() -> void:
	speech_bubble.show_thinking()


# ---- persistence ---------------------------------------------------------

# Atomic save: write to <file>.tmp, then rename. Prevents a crash mid-write
# from corrupting an existing memory file.
func save_memory() -> void:
	if data == null or data.npc_id == "":
		return  # transient NPC, never persists
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("NPC.save_memory: could not open user://")
		return
	if not dir.dir_exists("npc_memory"):
		dir.make_dir("npc_memory")
	var filename: String = data.npc_id + ".json"
	var tmp_filename: String = filename + ".tmp"
	var tmp_path: String = MEMORY_DIR + "/" + tmp_filename
	var payload: Dictionary = {
		"version": MemoryUtils.MEMORY_VERSION,
		"npc_id": data.npc_id,
		"long_term_summary": long_term_summary,
		"short_term": short_term,
		"relationships": relationships,
		"stats": {"mood": mood},
	}
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("NPC.save_memory: could not open %s for writing" % tmp_path)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	var memory_dir: DirAccess = DirAccess.open(MEMORY_DIR)
	if memory_dir == null:
		push_error("NPC.save_memory: could not open %s" % MEMORY_DIR)
		return
	var rename_err: int = memory_dir.rename(tmp_filename, filename)
	if rename_err != OK:
		push_error("NPC.save_memory: rename %s -> %s failed (err=%d)" % [tmp_filename, filename, rename_err])


func _load_memory() -> void:
	if data == null or data.npc_id == "":
		return
	# Seed mood from EntityStats baseline (v0.0 first-load path).
	if data.stats != null:
		mood = data.stats.mood
	var path: String = MEMORY_DIR + "/" + data.npc_id + ".json"
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("NPC._load_memory: could not open %s for reading" % path)
		return
	var content: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("NPC._load_memory: %s is not a JSON object, ignoring" % path)
		return
	var dict: Dictionary = parsed as Dictionary
	# JSON boundary: Godot's JSON parser returns numbers as TYPE_FLOAT — a JSON 2
	# arrives as 2.0. Accept both TYPE_INT and TYPE_FLOAT; fall back to 1 for null,
	# string, dict, or anything else, which then triggers the migration branch
	# (the correct conservative behaviour for malformed/hand-edited saves).
	var raw_version: Variant = dict.get("version", 1)
	var is_numeric: bool = typeof(raw_version) == TYPE_INT or typeof(raw_version) == TYPE_FLOAT
	var version: int = int(raw_version) if is_numeric else 1
	if version != MemoryUtils.MEMORY_VERSION:
		dict = MemoryUtils.migrate_v1_to_v2(dict)
		short_term.clear()
		for item in dict["short_term"]:
			if item is Dictionary:
				short_term.append(item)
		long_term_summary = dict["long_term_summary"]
		relationships = dict["relationships"]
		# v1 had no persisted mood — the EntityStats seed set above stands.
		# Save the migrated form so subsequent loads skip this branch.
		# A failed save here is non-fatal: in-memory state is valid, the next
		# launch simply re-migrates from the still-v1 file on disk.
		save_memory()
		return
	# v2 direct load
	short_term.clear()
	var raw_short_term: Variant = dict.get("short_term", [])
	if raw_short_term is Array:
		for item in raw_short_term:
			if item is Dictionary:
				short_term.append(item)
	long_term_summary = str(dict.get("long_term_summary", ""))
	relationships = dict.get("relationships", {})
	var stats_dict: Dictionary = dict.get("stats", {})
	mood = float(stats_dict.get("mood", mood))
