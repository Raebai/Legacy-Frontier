extends StaticBody2D

const MEMORY_DIR: String = "user://npc_memory"
# MEMORY_VERSION lives on MemoryUtils; reference it via MemoryUtils.MEMORY_VERSION.

@export var data: NPCData

@onready var hint_label: Label = $HintLabel
@onready var proximity_area: Area2D = $ProximityArea
@onready var speech_bubble: Node2D = $SpeechBubble
@onready var _consolidator_http: HTTPRequest = $ConsolidatorHTTP

var _player_in_range: bool = false

## Hub side-on ambience: the NPC ambles back and forth on the town ground and
## STOPS when the player is close enough to talk (maker: "show NPCs walking around
## but stop when you go up to them"). Off until World calls set_hub_patrol().
var _hub_rig: CharacterRig = null
var _patrol_center: float = 0.0
var _patrol_range: float = 0.0
var _patrol_dir: float = 1.0
const PATROL_SPEED: float = 32.0

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

# Set by RoomZone Area2Ds on body_entered. M14 broadcast earshot reads it.
var current_room_id: String = ""

# M10 consolidation lifecycle state.
# _consolidating: an async consolidation HTTP request is in flight.
# _pending_consolidation: parsed consolidation result waiting to be applied at
#   next engage (deferred-swap rule from D-039 — never mutate a running NPC
#   instance mid-conversation). null when nothing pending.
# pending_facts_to_share: queue of gossip events emitted by consolidation,
#   consumed by M13. PERSISTED across save/load — without persistence the queue
#   would evaporate on quit and M13 propagation would silently lose data.
var _consolidating: bool = false
var _pending_consolidation: Variant = null
var pending_facts_to_share: Array = []

const CONSOLIDATION_TURN_THRESHOLD: int = 15
const OLLAMA_URL: String = "http://127.0.0.1:11434/api/chat"
const OLLAMA_MODEL: String = "llama3.2:3b"


func _ready() -> void:
	hint_label.visible = false
	proximity_area.body_entered.connect(_on_body_entered)
	proximity_area.body_exited.connect(_on_body_exited)
	# Replace the block "Visual" with a stick-figure rig (maker: "everything should
	# be in stick form"), tinted per-NPC from NPCData so the shared NPC.tscn still
	# renders distinct characters without a code-change-per-character (M12).
	var block: Node = get_node_or_null("Visual")
	if block != null:
		(block as CanvasItem).visible = false
	_hub_rig = CharacterRig.new()
	add_child(_hub_rig)
	# Feet at the node origin (rig draws feet height*0.5 below its own origin) so the
	# NPC stands ON the ground, not sunk into it.
	_hub_rig.position.y = -_hub_rig.height * 0.5
	_hub_rig.play(CharacterRig.State.IDLE)
	if data != null:
		_hub_rig.set_tint(data.display_color)
	_load_memory()
	_consolidator_http.request_completed.connect(_on_consolidation_completed)


## World calls this to make the NPC amble around `center_x` within +/- range.
func set_hub_patrol(center_x: float, patrol_range: float) -> void:
	_patrol_center = center_x
	_patrol_range = patrol_range


## Hub patrol: walk back and forth, but STOP (idle, facing the player) whenever the
## player is close enough to talk or a conversation is active. NPC is a StaticBody2D
## so we just animate its x directly — no gravity needed on the flat town ground.
func _physics_process(delta: float) -> void:
	if _patrol_range <= 0.0 or _hub_rig == null:
		return  # not a patrolling hub NPC (e.g. headless tests)
	var conversing: bool = Conversation != null and Conversation.is_engaged()
	if _player_in_range or conversing:
		_hub_rig.play(CharacterRig.State.IDLE)
		return
	var nx: float = global_position.x + _patrol_dir * PATROL_SPEED * delta
	if nx > _patrol_center + _patrol_range:
		_patrol_dir = -1.0
		nx = _patrol_center + _patrol_range
	elif nx < _patrol_center - _patrol_range:
		_patrol_dir = 1.0
		nx = _patrol_center - _patrol_range
	global_position.x = nx
	_hub_rig.play(CharacterRig.State.RUN)
	_hub_rig.set_facing(Vector2(_patrol_dir, 0.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("talk") and _player_in_range and not Conversation.is_engaged() \
			and not _class_select_open():
		Conversation.engage(self)
		get_viewport().set_input_as_handled()


## True while the hub Class-Select panel is open (don't open a chat over it).
## Guarded lookup so headless NPC tests without the autoload stay safe.
func _class_select_open() -> bool:
	var sel: Node = get_node_or_null("/root/ClassSelect")
	return sel != null and sel.has_method("is_open") and sel.is_open()


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
		# M10 deviation: pending_facts_to_share is persisted so M13 gossip
		# survives a quit between consolidation-emit and consume. Without
		# persistence the queue evaporates on close.
		"pending_facts_to_share": pending_facts_to_share,
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


# Orchestrator. Three paths land here:
#   1. No save file on disk (first-time NPC like Mirelle on launch one)
#   2. v1 save on disk (Raebai's v0.0 save before M9 verification migrated it)
#   3. v2 save on disk (the steady state after M9)
# Initial-relationships seeding fires on ALL three paths so first-time NPCs
# start out knowing their pre-existing village (D-039 + M12 design).
func _load_memory() -> void:
	if data == null or data.npc_id == "":
		return
	# Seed mood from EntityStats baseline (v0.0 first-load path).
	if data.stats != null:
		mood = data.stats.mood
	var path: String = MEMORY_DIR + "/" + data.npc_id + ".json"
	var did_v1_migration: bool = false
	if FileAccess.file_exists(path):
		did_v1_migration = _load_persisted_state(path)
	# Seed initial_relationships for entities not already in the registry.
	# Runs whether or not a save was loaded — applies to first-time NPCs
	# (no save yet) AND subsequent loads where the saved relationships
	# dict is missing newly-introduced anchors.
	_seed_initial_relationships()
	# If we just migrated v1->v2, persist the migrated state. Seeded
	# relationships go in the same write so disk is consistent immediately.
	if did_v1_migration:
		save_memory()


# Returns true if a v1->v2 migration occurred (caller should re-save).
func _load_persisted_state(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("NPC._load_memory: could not open %s for reading" % path)
		return false
	var content: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("NPC._load_memory: %s is not a JSON object, ignoring" % path)
		return false
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
		# v1 had no persisted mood — the EntityStats seed set in _load_memory stands.
		return true
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
	# M10 deviation: hydrate pending_facts_to_share queue if persisted.
	# Pre-M10 saves won't have this field — default to empty.
	pending_facts_to_share.clear()
	var pfts_raw: Variant = dict.get("pending_facts_to_share", [])
	if pfts_raw is Array:
		for item in pfts_raw:
			if item is Dictionary:
				pending_facts_to_share.append(item)
	return false


# Merge data.initial_relationships seeds into the runtime registry for
# entities not already present. Saved relationships that have evolved
# through consolidation are preserved — the seed only fills missing entries.
# Edge cases (malformed seed dicts, empty entity_id, non-Array key_facts)
# are skipped silently.
func _seed_initial_relationships() -> void:
	if data == null:
		return
	# `seed_entry` instead of `seed` — Godot's `seed()` RNG-seeder is a built-in
	# global; using `seed` as an iterator variable shadows it (parse-time warning).
	for seed_entry in data.initial_relationships:
		if not (seed_entry is Dictionary):
			continue
		var entity_id: String = str(seed_entry.get("entity_id", ""))
		if entity_id == "":
			continue
		if relationships.has(entity_id):
			continue
		var key_facts_seed: Variant = seed_entry.get("key_facts", [])
		var key_facts: Array = []
		if key_facts_seed is Array:
			for fact in key_facts_seed:
				key_facts.append(str(fact))
		relationships[entity_id] = {
			"valence": float(seed_entry.get("valence", 0.0)),
			"key_facts": key_facts,
			"gossip_inbox": [],
		}


# M11: Ensure relationships["player"] exists before any code path tries to
# write to it. Bootstrap (_seed_initial_relationships) only seeds explicit
# data.initial_relationships entries — the player isn't there until
# something (M11 patience counter, M10 consolidation, M13 gossip) needs
# to track them.
func _ensure_player_relationship() -> void:
	if relationships.has("player"):
		return
	relationships["player"] = {
		"valence": 0.0,
		"key_facts": [],
		"gossip_inbox": [],
		"low_patience_dismissals": 0,
	}


# M11 D-042: increment the dismissal counter on relationships.player.
# M10 consolidation will read this when shaping valence_delta — repeated
# patience-driven dismissals mean the player's reputation with this NPC
# decays faster.
func record_low_patience_dismissal() -> void:
	_ensure_player_relationship()
	var player_rel: Dictionary = relationships["player"]
	# int() cast handles the JSON-parse-as-float case (the M9 trap) — saved
	# state arrives as TYPE_FLOAT; freshly-seeded state is TYPE_INT.
	var current: int = int(player_rel.get("low_patience_dismissals", 0))
	player_rel["low_patience_dismissals"] = current + 1


# ---- M10 consolidation lifecycle ----------------------------------------

# True when an async consolidation HTTP request is in flight.
func is_consolidating() -> bool:
	return _consolidating


# True if a parsed result is waiting to be applied at next engage.
func has_pending_consolidation() -> bool:
	return _pending_consolidation != null


# Disengage-time gate: fire async consolidation if short_term crossed the
# threshold. Returns true if a request was actually fired. Fire-and-forget —
# the result lands on _pending_consolidation; apply_pending_consolidation_if_ready
# performs the atomic swap at next engage.
func maybe_consolidate() -> bool:
	if _consolidating:
		return false  # one already in flight
	if short_term.size() < CONSOLIDATION_TURN_THRESHOLD:
		return false  # below threshold
	if data == null or data.npc_id == "":
		return false  # transient NPC, never consolidates
	return start_consolidation()


# Lower-level: fire the consolidation HTTP request unconditionally (caller has
# already decided this NPC should consolidate). Used by maybe_consolidate (with
# threshold gate) and by the quit handler (forces consolidation regardless of
# turn count so end-of-session state is captured).
func start_consolidation() -> bool:
	if _consolidating:
		return false
	if short_term.is_empty():
		return false  # nothing to consolidate
	_consolidating = true
	var prompt: String = MemoryConsolidator.build_prompt(self)
	if prompt == "":
		_consolidating = false
		return false
	var messages: Array = [{"role": "user", "content": prompt}]
	var body: Dictionary = {
		"model": OLLAMA_MODEL,
		"messages": messages,
		"stream": false,
		"format": "json",  # D-039: grammar-constrained JSON output
		"keep_alive": "30m",  # D-045 #8
		"options": {
			"num_predict": 400,  # consolidation outputs are larger than turn replies
		},
	}
	var body_json: String = JSON.stringify(body)
	print("[consolidate] %s start, prompt tokens≈%d" % [data.npc_id, MemoryUtils.estimate_tokens(body_json)])
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var err: int = _consolidator_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, body_json)
	if err != OK:
		push_error("NPC.start_consolidation: request error %d for %s" % [err, data.npc_id])
		_consolidating = false
		return false
	return true


func _on_consolidation_completed(result: int, response_code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	_consolidating = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("[consolidate] %s failed result=%d code=%d — short_term preserved, retry on next trigger" % [data.npc_id, result, response_code])
		return
	var resp: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(resp) != TYPE_DICTIONARY or not resp.has("message"):
		push_warning("[consolidate] %s unexpected response shape" % data.npc_id)
		return
	var content: String = String(resp["message"].get("content", ""))
	var parsed: Dictionary = MemoryConsolidator.parse_response(content)
	_pending_consolidation = parsed
	print("[consolidate] %s complete (deferred to next engage swap)" % data.npc_id)


# Atomic swap at engage time per D-039: if a consolidation result is waiting,
# apply it and clear the pending slot. Idempotent — calling twice is safe.
# Saves to disk after applying so the consolidated state is durable immediately.
func apply_pending_consolidation_if_ready() -> void:
	if _pending_consolidation == null:
		return
	var parsed: Dictionary = _pending_consolidation
	_pending_consolidation = null
	MemoryConsolidator.apply_to_npc(self, parsed)
	save_memory()
	print("[consolidate] %s pending-swap applied at engage" % data.npc_id)
