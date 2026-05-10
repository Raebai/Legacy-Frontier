class_name MemoryUtils
extends Object

const MEMORY_VERSION: int = 2


# Lossless wrap; M10's consolidation produces real long_term content from short_term.
static func migrate_v1_to_v2(v1: Dictionary) -> Dictionary:
	return {
		"version": MEMORY_VERSION,
		"npc_id": v1.get("npc_id", ""),
		"long_term_summary": "",
		"short_term": v1.get("messages", []),
		"relationships": {},
		"stats": {"mood": 0.0},
	}


static func empty_v2(npc_id: String) -> Dictionary:
	return {
		"version": MEMORY_VERSION,
		"npc_id": npc_id,
		"long_term_summary": "",
		"short_term": [],
		"relationships": {},
		"stats": {"mood": 0.0},
	}


# Bands per docs/v0.5-design.md "System prompt assembly".
static func valence_word(v: float) -> String:
	if v > 0.6:
		return "deeply trusting"
	elif v > 0.2:
		return "warm"
	elif v > -0.2:
		return "neutral"
	elif v > -0.6:
		return "cold"
	else:
		return "hostile"


static func mood_word(m: float) -> String:
	if m > 0.5:
		return "bright and open"
	elif m > 0.2:
		return "settled"
	elif m > -0.2:
		return "even"
	elif m > -0.5:
		return "gloomy"
	else:
		return "dark"


static func patience_word(p: float) -> String:
	if p > 0.8:
		return "fresh and curious"
	elif p > 0.5:
		return "engaged"
	elif p > 0.2:
		return "fading"
	else:
		return "worn out, ready to leave"


# Char-count / 4 approximation. Underestimates by ~10–15% on Llama 3.2 BPE
# tokenization but adequate for observability — we only need order-of-magnitude.
static func estimate_tokens(text: String) -> int:
	@warning_ignore("integer_division")
	return text.length() / 4


# Example: "Mirelle [warm] — old friend, news node. Recent rumours: raebai said: ..."
static func compact_relationship(display_name: String, rel: Dictionary) -> String:
	var valence: float = float(rel.get("valence", 0.0))
	var key_facts: Array = rel.get("key_facts", [])  # Variant content from JSON; coerced to String per-element below
	var inbox: Array = rel.get("gossip_inbox", [])   # Variant content from JSON; per-element validated below

	var line: String = "%s [%s]" % [display_name, valence_word(valence)]
	if key_facts.size() > 0:
		var facts_str: Array[String] = []
		for f in key_facts:
			facts_str.append(str(f))
		line += " — " + ", ".join(facts_str)
	if inbox.size() > 0:
		var rumours: Array[String] = []
		for item in inbox:
			if not (item is Dictionary):
				continue
			var from_id: String = str(item.get("from", "someone"))
			var fact: String = str(item.get("fact", ""))
			rumours.append("%s said: %s" % [from_id, fact])
		if rumours.size() > 0:
			line += ". Recent rumours: " + "; ".join(rumours)
	return line + "."
