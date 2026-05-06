extends CanvasLayer

const OLLAMA_URL: String = "http://127.0.0.1:11434/api/chat"
const MODEL: String = "llama3.2:3b"

@onready var http: HTTPRequest = $HTTPRequest
@onready var input_bar: PanelContainer = $InputBar
@onready var input_field: LineEdit = $InputBar/HBox/LineEdit
@onready var last_said: RichTextLabel = $LastSaidLabel
@onready var last_said_timer: Timer = $LastSaidTimer

# State separation:
#   _engaged_npc — input bar is open and aimed at this NPC. Player movement is frozen.
#   _pending_npc — an LLM response is in flight; the reply will land on this NPC's bubble.
# Normal whisper: both refer to the same NPC. Farewell: input bar closes immediately
# (player free to walk), but _pending_npc keeps the in-flight reply alive so the parting
# line still renders when it arrives.
var _engaged_npc: Node = null
var _pending_npc: Node = null
var _waiting: bool = false
var _ending: bool = false  # in-flight response is a farewell parting line
var _farewell_regex: RegEx = null


func _ready() -> void:
	input_bar.visible = false
	last_said.visible = false
	input_field.keep_editing_on_text_submit = true
	input_field.text_submitted.connect(_on_text_submitted)
	input_field.text_changed.connect(_on_text_changed)
	last_said_timer.timeout.connect(_hide_last_said)
	http.request_completed.connect(_on_request_completed)
	_farewell_regex = RegEx.create_from_string("\\b(bye|goodbye|farewell|later|peace|see\\s+(?:you|ya)|i'?m\\s+out|gotta\\s+go|got\\s+to\\s+go|good\\s+night|safe\\s+travels|take\\s+care)\\b")


# ---- public API ----------------------------------------------------------

func is_input_open() -> bool:
	return input_bar.visible


func is_engaged() -> bool:
	return _engaged_npc != null


func engaged_npc() -> Node:
	return _engaged_npc


func engage(npc: Node) -> void:
	if input_bar.visible:
		return
	_engaged_npc = npc
	input_field.placeholder_text = "Whisper to %s — Enter to send, Esc to leave" % npc.data.npc_name
	_open_input_bar()


func disengage() -> void:
	if _engaged_npc == null:
		return
	# Cancel a non-farewell pending request (Esc / walking out should kill mid-thinking
	# whisper). A farewell request is allowed to land — _engaged_npc was already nulled
	# in _on_text_submitted, so we don't reach this branch in that case.
	if _waiting and not _ending:
		http.cancel_request()
		_waiting = false
		_pending_npc = null
	_engaged_npc = null
	_close_input_bar()


# ---- input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and input_bar.visible:
		_close_or_disengage()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat") and not input_bar.visible:
		_open_broadcast()
		get_viewport().set_input_as_handled()


func _open_broadcast() -> void:
	_engaged_npc = null
	input_field.placeholder_text = "Speak — Enter to send, Esc to close"
	_open_input_bar()


func _open_input_bar() -> void:
	input_bar.visible = true
	input_field.clear()
	input_field.editable = true
	input_field.grab_focus()


func _close_input_bar() -> void:
	input_bar.visible = false
	input_field.release_focus()
	_hide_last_said()


func _show_last_said(text: String) -> void:
	last_said.text = "[i][color=#bbbbbb]you said: " + text + "[/color][/i]"
	last_said.visible = true
	last_said_timer.start()


func _hide_last_said() -> void:
	last_said.visible = false
	last_said_timer.stop()


func _on_text_changed(_new_text: String) -> void:
	if last_said.visible:
		_hide_last_said()


func _close_or_disengage() -> void:
	if _engaged_npc != null:
		disengage()
	else:
		_close_input_bar()


# ---- submission ----------------------------------------------------------

func _on_text_submitted(message: String) -> void:
	if _waiting:
		return
	var trimmed: String = message.strip_edges()
	if trimmed == "":
		_close_or_disengage()
		return
	input_field.clear()
	var player: Node = get_tree().get_first_node_in_group("player")
	if _engaged_npc != null:
		_show_last_said(trimmed)
		var is_farewell: bool = _farewell_regex != null and _farewell_regex.search(trimmed.to_lower()) != null
		# Stage the request: append to NPC history, show their thinking bubble,
		# then assign _pending_npc so the response routes correctly even after
		# we close the UI on a farewell.
		_engaged_npc.messages.append({"role": "user", "content": trimmed})
		if _engaged_npc.has_method("show_thinking"):
			_engaged_npc.show_thinking()
		_pending_npc = _engaged_npc
		if is_farewell:
			_ending = true
			# Close UI instantly. Player walks free. Reply still lands on _pending_npc.
			_engaged_npc = null
			_close_input_bar()
		_send_to_ollama()
	else:
		# broadcast: world sees your bubble; bar closes.
		if player and player.has_method("say"):
			player.say(trimmed, 8.0)
		_close_input_bar()


func _send_to_ollama() -> void:
	if _pending_npc == null:
		return
	_waiting = true
	if _engaged_npc != null:
		input_field.editable = false
	var data: NPCData = _pending_npc.data
	var system_content: String = data.personality_prompt
	if _ending:
		system_content += "\n\nThe player is saying goodbye. Reply with one brief parting line in character — do not ask another question."
	var messages: Array = []
	messages.append({"role": "system", "content": system_content})
	messages.append_array(_pending_npc.messages)
	var body: Dictionary = {
		"model": MODEL,
		"messages": messages,
		"stream": false,
		"options": {
			"num_predict": 60,
			"stop": ["\n\n"],
		},
	}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var err: int = http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_finish_with_error("Could not start request to Ollama (Godot error %d)." % err)


func _on_request_completed(result: int, response_code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	_waiting = false
	var target: Node = _pending_npc
	_pending_npc = null
	_ending = false
	if _engaged_npc != null:
		input_field.editable = true
		input_field.grab_focus()
	if target == null:
		return  # cancelled (e.g. Esc'd a non-farewell mid-thinking)

	if result != HTTPRequest.RESULT_SUCCESS:
		_render_error_on(target, "Could not reach Ollama (result=%d). Is the server running?" % result)
		return
	if response_code != 200:
		_render_error_on(target, "Ollama returned HTTP %d." % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("message"):
		_render_error_on(target, "Unexpected Ollama response.")
		return
	var content: String = String(parsed["message"].get("content", "")).strip_edges()
	if content == "":
		_render_error_on(target, "Empty response from Ollama.")
		return
	target.messages.append({"role": "assistant", "content": content})
	if target.has_method("say"):
		target.say(content, 10.0)


func _finish_with_error(msg: String) -> void:
	_waiting = false
	var target: Node = _pending_npc
	_pending_npc = null
	_ending = false
	if _engaged_npc != null:
		input_field.editable = true
		input_field.grab_focus()
	if target != null:
		_render_error_on(target, msg)


func _render_error_on(target: Node, msg: String) -> void:
	if target.has_method("say"):
		target.say("[color=red][i](" + msg + ")[/i][/color]", 5.0)
