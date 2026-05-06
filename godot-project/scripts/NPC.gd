extends StaticBody2D

const MEMORY_DIR: String = "user://npc_memory"
const MEMORY_VERSION: int = 1

@export var data: NPCData

@onready var hint_label: Label = $HintLabel
@onready var proximity_area: Area2D = $ProximityArea
@onready var speech_bubble: Node2D = $SpeechBubble

var _player_in_range: bool = false
var messages: Array = []  # role/content dicts. Loaded from disk on _ready, persisted on engagement-end.


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
		"version": MEMORY_VERSION,
		"npc_id": data.npc_id,
		"messages": messages,
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
	var saved_messages: Variant = parsed.get("messages", [])
	if not (saved_messages is Array):
		push_warning("NPC._load_memory: %s 'messages' is not an array, ignoring" % path)
		return
	messages = saved_messages
