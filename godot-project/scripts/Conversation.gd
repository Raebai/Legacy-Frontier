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
var _system_addendum: String = ""  # one-shot system-prompt augmentation, cleared after use
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
	# Returning visitor: drop a callback line referencing prior conversation.
	# Skipped on first-ever meeting (no memory yet) and when a request is mid-flight.
	if npc.short_term.size() > 0 and not _waiting:
		_fire_callback_greeting()


func _fire_callback_greeting() -> void:
	# Synthetic stage-direction user turn so the message grammar stays alternating.
	_engaged_npc.short_term.append({"role": "user", "content": "(walks back up to you)"})
	if _engaged_npc.has_method("show_thinking"):
		_engaged_npc.show_thinking()
	_pending_npc = _engaged_npc
	_system_addendum = """The player has just walked back up to you. Read the conversation history above carefully — they have spoken with you before.

Your reply MUST:
1. Address them by name IF they ever shared one in the history.
2. Reference one specific thing they said — a place, a plan, a feeling, a refusal.
3. Optionally end with a small invitation that ties back to that specific thing — never a generic question.

Your reply MUST NOT contain any of: "how can I help you", "welcome back, traveller", "good to see you again", "what brings you here". These are forbidden phrases.

Maximum 30 words.

Good examples:
"Raaed. Coldrose still on your mind?"
"Back already. The road you spoke of — did it open up for you?"
"You returned. The thing you would not speak of — is it any easier now?\""""
	_send_to_ollama()


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
	var npc: Node = _engaged_npc
	_engaged_npc = null
	_close_input_bar()
	# Persist what was said to disk (atomic write — survives a crash).
	if npc != null and npc.has_method("save_memory"):
		npc.save_memory()


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
		_engaged_npc.short_term.append({"role": "user", "content": trimmed})
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
	var npc: Node = _pending_npc

	# Stable prefix order for KV-cache reuse across calls in a session
	# (Token efficiency principle #1, docs/v0.5-design.md):
	# 1. personality (static across all calls for this NPC)
	# 2. long_term_summary (changes only at consolidation — rare)
	# 3. relationship blocks (changes on consolidation/gossip)
	# 4. state words (changes per turn — must come last so the prefix stays stable)
	# 5. one-shot addenda (_ending, _system_addendum)
	var parts: Array[String] = [data.personality_prompt]

	if not npc.long_term_summary.is_empty():
		parts.append("What you remember from before:\n" + npc.long_term_summary)

	# Relationship block assembly. M9 ships with player-only since v0.5 has only
	# one anchor at this milestone. M12 (Mirelle) adds the inactive-relationship
	# omission rule (include if mentioned recently OR has unconsumed gossip).
	if npc.relationships.has("player"):
		var rel_line: String = MemoryUtils.compact_relationship("the player", npc.relationships["player"])
		parts.append(rel_line)

	# State words. At M9 defaults (mood=0, patience=1.0) these are "even" and
	# "fresh and curious" — minimally directive seasoning. M11 wires real updates.
	parts.append("Right now you are feeling: %s." % MemoryUtils.mood_word(npc.mood))
	parts.append("Your patience for this conversation: %s." % MemoryUtils.patience_word(npc.patience))

	if _ending:
		parts.append("The player is saying goodbye. Reply with one brief parting line in character — do not ask another question.")
	if _system_addendum != "":
		parts.append(_system_addendum)
		_system_addendum = ""

	var system_content: String = "\n\n".join(parts)
	var messages: Array = []
	messages.append({"role": "system", "content": system_content})
	messages.append_array(_pending_npc.short_term)
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
	var was_ending: bool = _ending
	_ending = false
	if _engaged_npc != null:
		input_field.editable = true
		input_field.grab_focus()
	if target == null:
		return  # cancelled (e.g. Esc'd a non-farewell mid-thinking)

	if result != HTTPRequest.RESULT_SUCCESS:
		_render_error_on(target, _friendly_result_error(result))
		return
	if response_code != 200:
		_render_error_on(target, _friendly_http_error(response_code, body))
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("message"):
		_render_error_on(target, "Ollama replied with an unexpected shape.")
		return
	var content: String = String(parsed["message"].get("content", "")).strip_edges()
	if content == "":
		_render_error_on(target, "Ollama returned no text — try again.")
		return
	target.short_term.append({"role": "assistant", "content": content})
	if target.has_method("say"):
		target.say(content, 10.0)
	# After a farewell parting line lands, persist (player has already walked away —
	# the disengage() save path was skipped for them, so we save here instead).
	if was_ending and target.has_method("save_memory"):
		target.save_memory()


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
		target.say("[color=#cc6655][i]" + msg + "[/i][/color]", 6.0)


func _friendly_result_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Ollama isn't running. Start it from the system tray and try again."
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Could not resolve the Ollama host. Network or DNS issue."
		HTTPRequest.RESULT_TIMEOUT:
			return "Ollama took too long to reply. The model may be cold-loading."
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connection to Ollama dropped mid-reply."
		_:
			return "Could not reach Ollama (error %d)." % result


func _friendly_http_error(code: int, body: PackedByteArray) -> String:
	var body_text: String = body.get_string_from_utf8()
	# Ollama typically returns model-not-found as a 404 with an "error" field.
	if code == 404 and body_text.find("model") != -1:
		return "Model %s isn't pulled yet. Run: ollama pull %s" % [MODEL, MODEL]
	if code == 503:
		return "Ollama is busy or starting up. Try again in a moment."
	return "Ollama returned HTTP %d." % code
