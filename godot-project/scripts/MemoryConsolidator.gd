# Pure-function helpers for M10 LLM consolidation pipeline (D-039).
# Static methods: build_prompt assembles the NPC-aware consolidation prompt,
# parse_response parses Ollama's JSON output with int/float type-coercion
# casts (D-040 / M9 trap), apply_to_npc applies deltas to the runtime state.
# Failure paths: parse_response returns a dict with `error` key when the
# response is unparseable; callers fall back to build_truncate_concat_summary.
class_name MemoryConsolidator
extends Object

const PROMPT_PATH: String = "res://data/prompts/memory_consolidation.txt"
const MAX_LONG_TERM_WORDS: int = 80
const MAX_NEW_FACTS_PER_ENTITY: int = 3
const MAX_KEY_FACTS_PER_ENTITY: int = 5
const TRUNCATE_CONCAT_CHAR_LIMIT: int = 1000


# Build the consolidation prompt for `npc`. Reads the template once per call
# (file is small; cache later only if it becomes a bottleneck).
static func build_prompt(npc: Object) -> String:
	var template: String = _read_template()
	if template == "":
		push_error("MemoryConsolidator.build_prompt: empty prompt template")
		return ""
	var npc_name: String = npc.data.npc_name if npc.data != null else "the NPC"
	# Pass the full personality_prompt rather than the first line — the slice
	# would strip Raebai's anti-patterns + few-shot examples that define the
	# voice we're trying to preserve (Raebai-waffliness-is-a-feature memory).
	# Consolidation runs once per ~15-turn block; the token cost is fine.
	var personality: String = ""
	if npc.data != null:
		personality = npc.data.personality_prompt
	var long_term: String = npc.long_term_summary if npc.long_term_summary != "" else "(none yet)"
	var compact_rels: String = _compact_relationships_for_prompt(npc)
	var short_term_text: String = _format_short_term(npc.short_term)
	var n_turns: int = npc.short_term.size()
	template = template.replace("{npc_name}", npc_name)
	template = template.replace("{personality_prompt}", personality)
	template = template.replace("{long_term_summary_or_empty}", long_term)
	template = template.replace("{compact_relationships}", compact_rels)
	template = template.replace("{short_term_messages}", short_term_text)
	template = template.replace("{N}", str(n_turns))
	return template


# Parse Ollama's JSON response. Returns a dict with the expected shape, or
# {"error": "<reason>"} if the response is unparseable. Caller falls back to
# build_truncate_concat_summary in the error case.
#
# Type-coercion: Godot's JSON.parse_string returns numbers as TYPE_FLOAT.
# We cast valence_delta and mood_delta to float defensively; consumed_inbox_indices
# entries to int. new_facts to str. The M9 trap (NPC.gd:154-156) is the canonical
# pattern for this.
static func parse_response(json_text: String) -> Dictionary:
	if json_text == "":
		return {"error": "empty response"}
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "not a JSON object"}
	var dict: Dictionary = parsed as Dictionary
	var out: Dictionary = {
		"updated_long_term_summary": str(dict.get("updated_long_term_summary", "")),
		"relationship_updates": {},
		"mood_delta": _coerce_float(dict.get("mood_delta", 0.0)),
		"strong_facts_to_share": [],
	}
	# Bound long_term to MAX_LONG_TERM_WORDS even if the LLM ignored the cap.
	out["updated_long_term_summary"] = _truncate_to_word_cap(out["updated_long_term_summary"], MAX_LONG_TERM_WORDS)
	var rel_updates_raw: Variant = dict.get("relationship_updates", {})
	if rel_updates_raw is Dictionary:
		for entity_id in rel_updates_raw.keys():
			var entry_raw: Variant = rel_updates_raw[entity_id]
			if not (entry_raw is Dictionary):
				continue
			var entry: Dictionary = entry_raw as Dictionary
			var new_facts: Array[String] = []
			var nf_raw: Variant = entry.get("new_facts", [])
			if nf_raw is Array:
				for f in nf_raw:
					new_facts.append(str(f))
					if new_facts.size() >= MAX_NEW_FACTS_PER_ENTITY:
						break
			var consumed_raw: Variant = entry.get("consumed_inbox_indices", [])
			var consumed: Array[int] = []
			if consumed_raw is Array:
				for idx in consumed_raw:
					consumed.append(int(_coerce_float(idx)))
			out["relationship_updates"][str(entity_id)] = {
				"valence_delta": _coerce_float(entry.get("valence_delta", 0.0)),
				"new_facts": new_facts,
				"consumed_inbox_indices": consumed,
			}
	var sfts_raw: Variant = dict.get("strong_facts_to_share", [])
	if sfts_raw is Array:
		for item_raw in sfts_raw:
			if not (item_raw is Dictionary):
				continue
			var item: Dictionary = item_raw as Dictionary
			var share_with_arr: Array[String] = []
			var sw_raw: Variant = item.get("share_with", [])
			if sw_raw is Array:
				for sid in sw_raw:
					share_with_arr.append(str(sid))
			out["strong_facts_to_share"].append({
				"about": str(item.get("about", "")),
				"fact": str(item.get("fact", "")),
				"share_with": share_with_arr,
			})
	return out


# Apply parsed consolidation result to the NPC's runtime state. After this,
# short_term is cleared and the four-layer state reflects the consolidation.
# Caller is responsible for save_memory() after.
static func apply_to_npc(npc: Object, parsed: Dictionary) -> void:
	if parsed.has("error"):
		push_warning("MemoryConsolidator.apply_to_npc: error in parsed result, applying truncate-concat fallback")
		npc.long_term_summary = build_truncate_concat_summary(npc)
		npc.short_term.clear()
		return
	# 1. Update long_term_summary.
	var new_lts: String = parsed.get("updated_long_term_summary", "")
	if new_lts != "":
		npc.long_term_summary = new_lts
	# 2. Apply relationship_updates.
	var rel_updates: Dictionary = parsed.get("relationship_updates", {})
	for entity_id in rel_updates.keys():
		var update: Dictionary = rel_updates[entity_id]
		if not npc.relationships.has(entity_id):
			# Lazy-create at default shape.
			npc.relationships[entity_id] = {
				"valence": 0.0,
				"key_facts": [],
				"gossip_inbox": [],
			}
		var rel: Dictionary = npc.relationships[entity_id]
		var current_valence: float = _coerce_float(rel.get("valence", 0.0))
		var valence_delta: float = _coerce_float(update.get("valence_delta", 0.0))
		rel["valence"] = clampf(current_valence + valence_delta, -1.0, 1.0)
		# Append new_facts (cap at MAX_KEY_FACTS_PER_ENTITY in the registry).
		var existing_facts_raw: Variant = rel.get("key_facts", [])
		var existing_facts: Array = existing_facts_raw if existing_facts_raw is Array else []
		var new_facts_raw: Variant = update.get("new_facts", [])
		if new_facts_raw is Array:
			for f in new_facts_raw:
				existing_facts.append(str(f))
		# Trim oldest if we exceed cap.
		while existing_facts.size() > MAX_KEY_FACTS_PER_ENTITY:
			existing_facts.pop_front()
		rel["key_facts"] = existing_facts
		# Process consumed_inbox_indices: drop those items from gossip_inbox.
		var consumed_indices: Array = update.get("consumed_inbox_indices", [])
		if consumed_indices.size() > 0 and rel.has("gossip_inbox"):
			var inbox: Array = rel["gossip_inbox"]
			# Drop in descending index order so earlier indices remain valid.
			consumed_indices.sort()
			consumed_indices.reverse()
			for idx in consumed_indices:
				if idx >= 0 and idx < inbox.size():
					inbox.remove_at(idx)
			rel["gossip_inbox"] = inbox
	# 3. Apply mood_delta.
	var mood_delta: float = _coerce_float(parsed.get("mood_delta", 0.0))
	npc.mood = clampf(npc.mood + mood_delta, -1.0, 1.0)
	# 4. Decay mood by -0.05 toward 0 per consolidation cycle (D-040).
	if npc.mood > 0.05:
		npc.mood -= 0.05
	elif npc.mood < -0.05:
		npc.mood += 0.05
	else:
		npc.mood = 0.0
	# 5. Stash strong_facts_to_share on the NPC for M13 to consume after save.
	if parsed.has("strong_facts_to_share") and parsed["strong_facts_to_share"].size() > 0:
		npc.pending_facts_to_share.append_array(parsed["strong_facts_to_share"])
	# 6. Clear short_term — the conversation is now in long_term_summary.
	npc.short_term.clear()


# Fallback when parse_response fails: concatenate short_term verbatim into a
# truncated long_term summary. Loses LLM-judgment polish but preserves the
# raw content so nothing is lost. Logged for offline review.
static func build_truncate_concat_summary(npc: Object) -> String:
	var parts: Array[String] = []
	for entry in npc.short_term:
		if not (entry is Dictionary):
			continue
		var role: String = str(entry.get("role", ""))
		var content: String = str(entry.get("content", ""))
		parts.append("%s: %s" % [role, content])
	var joined: String = "\n".join(parts)
	if joined.length() > TRUNCATE_CONCAT_CHAR_LIMIT:
		joined = joined.substr(0, TRUNCATE_CONCAT_CHAR_LIMIT) + "..."
	# Keep existing long_term if it had content; otherwise use the concat.
	if npc.long_term_summary != "":
		return npc.long_term_summary + "\n\n[unconsolidated, raw]:\n" + joined
	return "[Raw conversation log — LLM consolidation failed]:\n" + joined


# ---- internal helpers ----------------------------------------------------

static func _read_template() -> String:
	var f: FileAccess = FileAccess.open(PROMPT_PATH, FileAccess.READ)
	if f == null:
		push_error("MemoryConsolidator: could not read prompt template at %s" % PROMPT_PATH)
		return ""
	var content: String = f.get_as_text()
	f.close()
	return content


static func _coerce_float(v: Variant) -> float:
	var t: int = typeof(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return float(v)
	if t == TYPE_STRING:
		return float(v)
	return 0.0


static func _truncate_to_word_cap(text: String, max_words: int) -> String:
	var words: PackedStringArray = text.split(" ", false)
	if words.size() <= max_words:
		return text
	return " ".join(Array(words).slice(0, max_words)) + "..."


static func _compact_relationships_for_prompt(npc: Object) -> String:
	if npc.relationships.is_empty():
		return "(none)"
	var lines: Array[String] = []
	for entity_id in npc.relationships.keys():
		var rel: Dictionary = npc.relationships[entity_id]
		lines.append(MemoryUtils.compact_relationship(str(entity_id), rel))
	return "\n".join(lines)


static func _format_short_term(short_term: Array) -> String:
	var lines: Array[String] = []
	for entry in short_term:
		if not (entry is Dictionary):
			continue
		var role: String = str(entry.get("role", ""))
		var content: String = str(entry.get("content", ""))
		var label: String = "Player" if role == "user" else "You"
		lines.append("%s: %s" % [label, content])
	return "\n".join(lines)
