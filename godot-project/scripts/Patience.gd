# Pure-function helpers for the runtime-only patience scalar (D-040).
# Patience itself lives on the NPC instance (npc.patience); this class
# computes per-turn deltas and the lookup helpers consumed by both
# whisper (M11) and broadcast overhear (M14, future).
#
# The `npc` parameter is typed as Object rather than Node so test stubs
# (RefCounted-extending inner classes) can be passed without manual node
# lifetime management. Production callers pass the actual NPC node; the
# function accesses npc.data and npc.short_term dynamically.
class_name Patience
extends Object

# Numeric design lives here in one place so M14 + future tuning don't
# scatter magic numbers. Per-NPC patience_decay_rate stays on NPCData.
const INSULT_DELTA: float = -0.25
const REPEAT_DELTA: float = -0.10
const COMPLIMENT_DELTA: float = 0.10
const INTEREST_DELTA: float = 0.05

# Patience floor below which the NPC's next reply receives the wrap-up
# addendum (D-042 NPC-initiated farewell trigger).
const FAREWELL_THRESHOLD: float = 0.2

# Levenshtein window for repeat-question detection (D-040: "< 5").
const REPEAT_LEVENSHTEIN_WINDOW: int = 5

# Compile-once (D-045 #12): static vars populated on first compute_delta call.
static var _insult_regex: RegEx = null
static var _compliment_regex: RegEx = null


# Compute the patience delta for `text` against `npc`. Sums the default
# decay (npc.data.patience_decay_rate) with all matching trigger deltas.
# Caller is responsible for clamping to [0.0, 1.0] and applying the new value.
static func compute_delta(text: String, npc: Object) -> float:
	_init_regexes()
	var lowered: String = text.to_lower().strip_edges()
	var delta: float = 0.0
	var triggers: Array[String] = []

	# Default per-turn baseline (always applies).
	if npc.data != null:
		delta -= npc.data.patience_decay_rate
		triggers.append("default(-%.2f)" % npc.data.patience_decay_rate)

	# Insult / profanity.
	if _insult_regex != null and _insult_regex.search(lowered) != null:
		delta += INSULT_DELTA
		triggers.append("insult(%+.2f)" % INSULT_DELTA)

	# Compliment / warmth.
	if _compliment_regex != null and _compliment_regex.search(lowered) != null:
		delta += COMPLIMENT_DELTA
		triggers.append("compliment(%+.2f)" % COMPLIMENT_DELTA)

	# Aligned with NPC's interest keywords (substring-contains, no regex).
	if _matches_interest(lowered, npc):
		delta += INTEREST_DELTA
		triggers.append("interest(%+.2f)" % INTEREST_DELTA)

	# Repeat question — Levenshtein vs any prior player turn in short_term.
	if _is_repeat_question(lowered, npc):
		delta += REPEAT_DELTA
		triggers.append("repeat(%+.2f)" % REPEAT_DELTA)

	# Observability: log the breakdown so playtest tuning can see why patience
	# moved. Hidden from the player (D-020); surfaces in editor debug-output.
	var npc_id: String = npc.data.npc_id if npc.data != null else "?"
	print("[patience] %s: delta %+0.2f from [%s]" % [npc_id, delta, ", ".join(triggers)])
	return delta


# Returns true if `lowered` (already lowercase, stripped) contains any of
# the NPC's interest_keywords as a substring. Case-insensitive.
static func _matches_interest(lowered: String, npc: Object) -> bool:
	if npc.data == null:
		return false
	for kw in npc.data.interest_keywords:
		if kw.is_empty():
			continue
		if lowered.find(kw.to_lower()) != -1:
			return true
	return false


# Returns true if `lowered` matches a prior PLAYER turn in npc.short_term
# within Levenshtein distance < REPEAT_LEVENSHTEIN_WINDOW. Iterates all prior
# user turns (synthetic stage-direction turns like "(walks back up to you)"
# are distinctive enough not to false-positive against real player text).
static func _is_repeat_question(lowered: String, npc: Object) -> bool:
	for entry in npc.short_term:
		if not (entry is Dictionary):
			continue
		if entry.get("role", "") != "user":
			continue
		var prior: String = str(entry.get("content", "")).to_lower().strip_edges()
		if prior == "":
			continue
		if levenshtein(lowered, prior) < REPEAT_LEVENSHTEIN_WINDOW:
			return true
	return false


# Standard DP Levenshtein distance — minimum number of single-character
# edits (insert/delete/substitute) to transform `a` into `b`.
# O(m*n) time, O(min(m,n)) space (two-row optimisation).
static func levenshtein(a: String, b: String) -> int:
	var m: int = a.length()
	var n: int = b.length()
	if m == 0:
		return n
	if n == 0:
		return m
	# Two rolling rows.
	var prev_row: Array[int] = []
	prev_row.resize(n + 1)
	for j in range(n + 1):
		prev_row[j] = j
	var curr_row: Array[int] = []
	curr_row.resize(n + 1)
	for i in range(1, m + 1):
		curr_row[0] = i
		for j in range(1, n + 1):
			var cost: int = 0 if a[i - 1] == b[j - 1] else 1
			curr_row[j] = mini(
				mini(prev_row[j] + 1, curr_row[j - 1] + 1),
				prev_row[j - 1] + cost,
			)
		# Swap: copy curr into prev for next iteration.
		for j in range(n + 1):
			prev_row[j] = curr_row[j]
	return prev_row[n]


# Lazy regex init. Called once per process; subsequent calls early-exit.
# Word-boundaries (\b) keep matches at whole-word granularity so "shut" in
# "shutter" doesn't trigger insult, etc.
static func _init_regexes() -> void:
	if _insult_regex != null:
		return
	_insult_regex = RegEx.new()
	# Family-friendly first-pass; tune in playtest. Order matters less than
	# the |-separated alternatives covering common forms.
	_insult_regex.compile("\\b(stupid|idiot|moron|dumb|fuck|shit|damn|piss|asshole|bitch|shut\\s+up|annoying|boring|ugly|hate(?:s|d)?\\s+(?:you|this))\\b")
	_compliment_regex = RegEx.new()
	_compliment_regex.compile("\\b(thanks?|thank\\s+you|appreciate|love|great|wonderful|kind|nice|amazing|brilliant|wise|helpful|grateful|thoughtful)\\b")
