extends CanvasLayer

const OLLAMA_URL: String = "http://127.0.0.1:11434/api/chat"
const MODEL: String = "llama3.2:3b"

@onready var http: HTTPRequest = $HTTPRequest
@onready var input_bar: PanelContainer = $InputBar
@onready var input_field: LineEdit = $InputBar/HBox/LineEdit
@onready var last_said: RichTextLabel = $LastSaidLabel
@onready var last_said_timer: Timer = $LastSaidTimer
@onready var saving_overlay: Control = $SavingOverlay

# State separation:
#   _engaged_npc — input bar is open and aimed at this NPC. Player movement is frozen.
#   _pending_npc — an LLM response is in flight; the reply will land on this NPC's bubble.
# Normal whisper: both refer to the same NPC. Farewell: input bar closes immediately
# (player free to walk), but _pending_npc keeps the in-flight reply alive so the parting
# line still renders when it arrives.
var _engaged_npc: Node = null
var _pending_npc: Node = null
var _waiting: bool = false
var _ending: bool = false  # in-flight response is a player-side farewell parting line (D-037)
var _ending_low_patience: bool = false  # in-flight response carries the M11 wrap-up addendum (D-042)
var _system_addendum: String = ""  # one-shot system-prompt augmentation, cleared after use
var _farewell_regex: RegEx = null


func _ready() -> void:
	input_bar.visible = false
	last_said.visible = false
	saving_overlay.visible = false
	input_field.keep_editing_on_text_submit = true
	input_field.text_submitted.connect(_on_text_submitted)
	input_field.text_changed.connect(_on_text_changed)
	last_said_timer.timeout.connect(_hide_last_said)
	http.request_completed.connect(_on_request_completed)
	_farewell_regex = RegEx.create_from_string("\\b(bye|goodbye|farewell|later|peace|see\\s+(?:you|ya)|i'?m\\s+out|gotta\\s+go|got\\s+to\\s+go|good\\s+night|safe\\s+travels|take\\s+care)\\b")
	# M10 D-039 quit handler: intercept the window close so we can flush
	# in-flight consolidations + force-fire one per NPC with non-empty
	# short_term before the process exits. Without set_auto_accept_quit(false),
	# NOTIFICATION_WM_CLOSE_REQUEST fires AFTER Godot has decided to close —
	# any await inside the handler races against the exit and usually loses.
	get_tree().set_auto_accept_quit(false)


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
	# M10 D-039: if a consolidation completed while the player was away,
	# atomic-swap the new long_term + relationships into the NPC at engage
	# time. Idempotent; has_pending_consolidation gates the actual work.
	# Order matters: the swap must run BEFORE we read npc.relationships
	# for the patience burnout lookup below, since consolidation may have
	# updated low_patience_dismissals or other counters.
	if npc.has_method("apply_pending_consolidation_if_ready"):
		npc.apply_pending_consolidation_if_ready()
	# M11 D-040 (refined 2026-05-10): starting patience reflects accumulated
	# burnout from prior dismissals. The original D-040 locked "Resets to 1.0
	# on engage" assuming M10's LLM-driven valence_delta would carry the
	# burnout signal between conversations. M10 hasn't shipped — until it
	# does, low_patience_dismissals is the proxy. 0.25 per prior dismissal
	# means burnout snowballs across engagements ("memory is important"):
	#   0 dismissals -> 1.00 ("fresh and curious")
	#   1 dismissal  -> 0.75 ("engaged" but warming down)
	#   2 dismissals -> 0.50
	#   3 dismissals -> 0.25 ("fading")
	#   4+ dismissals -> 0.00 ("worn out" — first message any tone triggers wrap-up)
	# When M10 lands, this becomes derive-from-trust instead of derive-from-
	# counter; same UX, more durable.
	var dismissals: int = 0
	if "relationships" in npc and npc.relationships.has("player"):
		dismissals = int(npc.relationships["player"].get("low_patience_dismissals", 0))
	npc.patience = clampf(1.0 - 0.25 * float(dismissals), 0.0, 1.0)
	if dismissals > 0:
		print("[patience] %s: engage with %d prior dismissals -> starting patience %.2f" % [npc.data.npc_id, dismissals, npc.patience])
	input_field.placeholder_text = "Whisper to %s — Enter to send, Esc to leave" % npc.data.npc_name
	_open_input_bar()
	# Returning visitor: drop a callback line referencing prior conversation.
	# Skipped on first-ever meeting (no memory yet) and when a request is mid-flight.
	# Gate considers BOTH short_term (in-session continuity) AND long_term_summary
	# (post-M10 consolidation moved past convos into long_term, clearing short_term).
	# Pre-fix this used only short_term, so first re-engage after consolidation
	# was silent — long_term had the memory but the gate evaluated false.
	var has_memory: bool = npc.short_term.size() > 0 or not npc.long_term_summary.is_empty()
	if has_memory and not _waiting:
		_fire_callback_greeting()


func _fire_callback_greeting() -> void:
	# Synthetic stage-direction user turn so the message grammar stays alternating.
	_engaged_npc.short_term.append({"role": "user", "content": "(walks back up to you)"})
	if _engaged_npc.has_method("show_thinking"):
		_engaged_npc.show_thinking()
	_pending_npc = _engaged_npc
	_system_addendum = """The player has just walked back up to you. The "What you remember from before" block above holds the substance of past conversations with them; recent turns may also appear after the system block.

Your reply MUST:
1. Address them by name IF mentioned in what you remember.
2. Reference one specific thing you remember — a place, a plan, a fear, a refusal.
3. Optionally end with a small invitation that ties back to that specific thing — never a generic question.

Your reply MUST NOT contain any of: "how can I help you", "welcome back, traveller", "good to see you again", "what brings you here". These are forbidden phrases.

Maximum 30 words.

Good examples:
"Raaed. Coldrose still on your mind?"
"Back already. The road you spoke of — did it open up for you?"
"You returned. The thing you would not speak of — is it any easier now?\""""
	# If the player just returned from a tower run, make the opening reference
	# it specifically (one-shot; the durable key_fact carries it thereafter).
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("consume_callback_run_hint"):
		var run_hint: String = gs.consume_callback_run_hint()
		if run_hint != "":
			_system_addendum += "\n\n" + run_hint
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
		_ending_low_patience = false  # cancelled with the request
	var npc: Node = _engaged_npc
	_engaged_npc = null
	_close_input_bar()
	# Persist what was said to disk (atomic write — survives a crash).
	if npc != null and npc.has_method("save_memory"):
		npc.save_memory()
	# M10 D-039: trigger async consolidation if short_term crossed the
	# threshold. Fire-and-forget — player keeps moving while the model
	# thinks; the result lands on npc._pending_consolidation and is applied
	# at next engage via apply_pending_consolidation_if_ready.
	if npc != null and npc.has_method("maybe_consolidate"):
		npc.maybe_consolidate()


# ---- input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and input_bar.visible:
		_close_or_disengage()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat") and not input_bar.visible:
		var sel: Node = get_node_or_null("/root/ClassSelect")
		if sel != null and sel.has_method("is_open") and sel.is_open():
			return  # don't open the broadcast bar over the class-select panel
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
		# M11: rule-based patience update before farewell detection so a
		# patience-driven farewell (Task 4) can fire on this turn if applicable.
		var delta: float = Patience.compute_delta(trimmed, _engaged_npc)
		var old_patience: float = _engaged_npc.patience
		_engaged_npc.patience = clampf(old_patience + delta, 0.0, 1.0)
		print("[patience] %s: %.2f -> %.2f" % [_engaged_npc.data.npc_id, old_patience, _engaged_npc.patience])
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
		elif _engaged_npc.patience < Patience.FAREWELL_THRESHOLD:
			# M11 D-042 (updated 2026-05-10): patience worn out — inject a
			# one-shot addendum telling the LLM this is its final reply.
			# Engine instant-closes when the reply lands, regardless of the
			# specific phrasing (the original regex-on-reply gate was too
			# brittle on Llama 3.2 3B — see decisions.md D-042). Reuses the
			# _system_addendum slot; callback greeting fires only at engage
			# time so it can't collide with this mid-conversation addendum.
			# Few-shot examples + explicit no-question rule address the M11
			# playtest finding that personality prompts emphasising question-
			# asking (Raebai's whole voice) override generic "wrap up" instructions
			# unless the wrap-up shape is shown by example. _send_to_ollama
			# also lowers num_predict to 30 when this flag is set so the
			# model can't produce a 40-word "wrap-up" with a trailing question.
			_ending_low_patience = true
			_system_addendum = "Your patience for this conversation is worn out. This is your final reply. Write ONE short statement that ends the conversation — no question, no offer, no invitation. Examples of the shape: \"Hm. Sit elsewhere then.\" / \"Let me be, Raaed.\" / \"Go on. The road is yours.\" / \"Walk easy.\" Stay in your voice; don't be rude unless your trust toward this person is also low."
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
	# M11 D-042: lower num_predict for the wrap-up turn so the model can't
	# produce a 40-word "wrap-up" with a trailing question (M11 playtest
	# showed Raebai's question-asking voice persists through generic wrap-up
	# instructions; combined with the few-shot examples in _system_addendum,
	# 30 tokens is enough to land a short statement and not enough to drift
	# into a continuation). Normal turns capped at 45 (post-M10 session 14
	# verification — user feedback "he talks too much"). 45 is ~30-35 words
	# which is in-range without flattening voice; if still too much we lower
	# further or add per-NPC overrides. Personality prompts deliberately
	# NOT touched (Raebai-waffliness voice rules preserved).
	var num_predict: int = 30 if _ending_low_patience else 45
	var body: Dictionary = {
		"model": MODEL,
		"messages": messages,
		"stream": false,
		"keep_alive": "30m",
		"options": {
			"num_predict": num_predict,
			"stop": ["\n\n"],
		},
	}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body_json: String = JSON.stringify(body)
	# Observability: log estimated input tokens per call (token-efficiency item #16).
	# Uses MemoryUtils.estimate_tokens (char/4 approximation). Underestimates by
	# ~10–15% on Llama 3.2 BPE; adequate for spotting prompt growth.
	print("[ollama] %s tokens-in≈%d" % [_pending_npc.data.npc_id, MemoryUtils.estimate_tokens(body_json)])
	var err: int = http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, body_json)
	if err != OK:
		_finish_with_error("Could not start request to Ollama (Godot error %d)." % err)


func _on_request_completed(result: int, response_code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	_waiting = false
	var target: Node = _pending_npc
	_pending_npc = null
	var was_ending: bool = _ending
	_ending = false
	var was_ending_low_patience: bool = _ending_low_patience
	_ending_low_patience = false
	# Re-enable input ONLY when the conversation continues. On a wrap-up
	# close, the bar stays disabled during the 1.5s pacing pause so the
	# player can't sneak another message in before the parting line lands.
	if _engaged_npc != null and not was_ending_low_patience:
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
		# M10 D-039: D-037 player-side farewell exits skip disengage(), so the
		# consolidation trigger lives here for that path too.
		if target.has_method("maybe_consolidate"):
			target.maybe_consolidate()
	# M11 D-042 (updated 2026-05-10): if this in-flight request carried the
	# wrap-up addendum, the NPC's reply IS the parting line regardless of
	# specific phrasing. Patience itself is the trigger; we don't grade the
	# LLM's wording afterwards. The earlier regex-on-reply gate was too
	# brittle on Llama 3.2 3B — the model frequently produced in-character
	# dismissals using words D-037's narrow regex didn't catch. Instant-
	# close fires whenever was_ending_low_patience is true and a valid
	# reply landed (error paths already returned before this point).
	if was_ending_low_patience:
		if target.has_method("record_low_patience_dismissal"):
			target.record_low_patience_dismissal()
		if target.has_method("save_memory"):
			target.save_memory()
		# M10 D-039: M11 wrap-up close also bypasses disengage(), so trigger
		# async consolidation here. The dismissal counter was just bumped
		# above; consolidation reads that into the LLM prompt context.
		if target.has_method("maybe_consolidate"):
			target.maybe_consolidate()
		# Pacing pause: the parting line is already rendering in the bubble
		# via target.say() above; hold the input bar open (but disabled)
		# for 1.5s so the player can read the line before the bar visibly
		# closes. Without this, the close feels abrupt — bubble appears
		# and bar disappears in the same frame. After the pause we re-check
		# that we're still engaged with the same target (player could have
		# walked away mid-pause, triggering disengage from NPC._on_body_exited).
		if _engaged_npc != null:
			await get_tree().create_timer(1.5).timeout
			if _engaged_npc == target:
				_engaged_npc = null
				_close_input_bar()


func _finish_with_error(msg: String) -> void:
	_waiting = false
	var target: Node = _pending_npc
	_pending_npc = null
	_ending = false
	_ending_low_patience = false
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


# ---- M10 quit handler: parallel-sync consolidation --------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_quit_request()


# Quit handler (D-039 / D-045 #9), refined Session 14 after the first
# playtest of M10 showed the original force-fire policy produced 10-15s
# closes when both NPCs had pending consolidations from disengage. The
# slow close was 100% redundant: the in-memory pending swaps were ignored
# and fresh HTTP consolidations were fired from scratch — repeating work
# that had already completed seconds before.
#
# Refined policy:
# 1. Mid-conversation: disengage() — saves short_term + triggers
#    threshold-gated async consolidation via maybe_consolidate.
# 2. Apply any already-completed pending consolidations (free, in-memory,
#    no HTTP). This is the common case after a normal play session.
# 3. Await any in-flight consolidations (the ones disengage just fired
#    or that arrived from earlier engagements) with a 5s timeout. The
#    timeout protects against Ollama hangs (the underlying HTTPRequest
#    timeout is 60s, which is too long for a close).
# 4. After the wait, apply whatever completed; save_memory regardless so
#    raw short_term sits on disk if consolidation timed out — next
#    session's disengage will retry the consolidation organically.
# 5. We deliberately do NOT force-fire new consolidations on quit. If
#    short_term crossed the threshold during play, disengage already
#    triggered consolidation. Below-threshold short_term is small enough
#    to fit in next session's prompt without bloating; auto-handles
#    on next disengage when accumulated turns push past 15.
const QUIT_AWAIT_TIMEOUT_MS: int = 5000


func _on_quit_request() -> void:
	print("[quit] consolidation pass starting")
	# Mid-conversation save: disengage() cancels in-flight whisper + persists
	# state. maybe_consolidate inside disengage is threshold-gated.
	if _engaged_npc != null:
		disengage()
	var npcs: Array = get_tree().get_nodes_in_group("npc")
	# Phase 1: apply any already-completed pending consolidations. Instant.
	var applied_count: int = 0
	for npc in npcs:
		if not (npc.has_method("has_pending_consolidation") and npc.has_method("apply_pending_consolidation_if_ready")):
			continue
		if npc.has_pending_consolidation():
			npc.apply_pending_consolidation_if_ready()  # internally saves
			applied_count += 1
	if applied_count > 0:
		print("[quit] applied %d pending consolidation(s) instantly" % applied_count)
	# Phase 2: collect in-flight consolidations.
	var npcs_in_flight: Array = []
	for npc in npcs:
		if npc.has_method("is_consolidating") and npc.is_consolidating():
			npcs_in_flight.append(npc)
	if npcs_in_flight.is_empty():
		print("[quit] nothing in flight — exit immediate")
		get_tree().quit()
		return
	# Phase 3: await with timeout. Poll completion every frame; bail at 5s.
	saving_overlay.visible = true
	await get_tree().process_frame
	print("[quit] awaiting %d in-flight consolidation(s), 5s cap" % npcs_in_flight.size())
	var deadline_ms: int = Time.get_ticks_msec() + QUIT_AWAIT_TIMEOUT_MS
	var timed_out: bool = false
	while true:
		var any_in_flight: bool = false
		for npc in npcs_in_flight:
			if npc.is_consolidating():
				any_in_flight = true
				break
		if not any_in_flight:
			break
		if Time.get_ticks_msec() > deadline_ms:
			timed_out = true
			break
		await get_tree().process_frame
	# Phase 4: apply whatever completed; save_memory always so raw short_term
	# is durable even if consolidation timed out.
	for npc in npcs_in_flight:
		if npc.has_method("apply_pending_consolidation_if_ready"):
			npc.apply_pending_consolidation_if_ready()
		if npc.has_method("save_memory"):
			npc.save_memory()
	if timed_out:
		print("[quit] timed out — raw short_term saved, consolidation retries next session")
	print("[quit] consolidation pass complete")
	get_tree().quit()
