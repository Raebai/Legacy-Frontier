# HOW OFTEN DOES EACH AUTHORED REACTION ACTUALLY FIRE — counted over real bouts.
#
# THE REASON THIS EXISTS RATHER THAN A READ OF THE TABLE. `ReactionTable` is 21
# authored rows and every one of them reads like it works. This repo has been
# burned once already by exactly that shape of confidence: a comment described
# scoring that was never written, and the named cause refused 0 of 482 looks. A row
# in a data table is not evidence that anything ever hits it.
#
# So: run the REAL `BotMatch` — the scene the maker opens from Lobby → Watch Bots,
# with the real kits, the real bots and the real 1v1 — hook `SpellReactor`'s
# `reaction_fired` signal, and count. A reaction that fires ZERO times over a full
# sweep is the finding, whatever its row says.
#
#   Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#       --script tools/probe_reaction_count.gd -- --pairs=8 --round=25
#
# Options (mirroring tools/botmatch_sim.gd so the two are comparable):
#   --pairs=N        how many of PAIRINGS to run. Default 8.
#   --roundrobin=1   every unordered class pair instead — 36 bouts. The honest
#                    sample for "which reactions can this ROSTER produce", where
#                    the hand-picked eight answers "which do these eight produce".
#   --repeat=N       bouts per pairing under roundrobin. Default 1.
#   --round=SEC      game-seconds before a bout is called on health. Default 25.
#   --hp=N           shared HP pool. Default 190.
#   --drops=1        let Tier 3 drops in. OFF by default for the same reason
#                    botmatch_sim keeps it off: a cataclysm is not the kit.
#   --wall=SEC       hard wall-clock cap per bout.
#
# ⚠ IT COUNTS TWO DIFFERENT THINGS AND THE GAP BETWEEN THEM IS THE POINT.
#   `reaction_fired` counts reactions that FIRED (matched, overlapped, applied).
#   `SpellReactor.live_count()` is sampled to count how many effects were even IN
#   the system. A reaction cannot fire between two spells that never registered,
#   so a zero next to a healthy live-count is a TABLE problem and a zero next to an
#   empty registry is a REGISTRATION problem. They want opposite fixes.
extends SceneTree

const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"

const CLASS_COUNT: int = 9

## Same eight as botmatch_sim, deliberately: two harnesses reporting on the same
## bouts are comparable, two reporting on different ones are not.
const PAIRINGS: Array[Vector2i] = [
	Vector2i(6, 5), Vector2i(2, 0), Vector2i(3, 1), Vector2i(4, 7),
	Vector2i(8, 2), Vector2i(5, 0), Vector2i(7, 3), Vector2i(1, 6),
]

var _roundrobin: bool = false
var _repeat: int = 1
var _drops: bool = false
var _pairs: int = 8
var _round: float = 25.0
var _difficulty: int = 3
var _hp: int = 190
var _wall: float = 150.0

## outcome -> times fired across the whole sweep.
var _fired: Dictionary = {}
## outcome -> "CLASS_A x CLASS_B" of the first bout it fired in, for the report.
var _first_seen: Dictionary = {}
## Live-registry samples, so a zero can be read correctly (see the ⚠ above).
var _live_samples: int = 0
var _live_total: int = 0
var _live_peak: int = 0
var _bout_label: String = ""


func _initialize() -> void:
	_parse_args()
	_run()


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_args())
	argv.append_array(OS.get_cmdline_user_args())
	for raw: String in argv:
		var arg: String = String(raw)
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var key: String = arg.substr(2, arg.find("=") - 2)
		var value: String = arg.substr(arg.find("=") + 1)
		match key:
			"pairs": _pairs = clampi(int(value), 1, PAIRINGS.size())
			"repeat": _repeat = maxi(int(value), 1)
			"roundrobin": _roundrobin = int(value) != 0
			"drops": _drops = int(value) != 0
			"round": _round = maxf(float(value), 4.0)
			"difficulty": _difficulty = clampi(int(value), 0, 3)
			"hp": _hp = maxi(int(value), 40)
			"wall": _wall = maxf(float(value), 10.0)


func _run() -> void:
	# ⚠ ONE FRAME BEFORE ANYTHING ELSE. Autoloads are added to the tree AFTER
	# `_initialize()` returns, so a lookup of `/root/SpellReactor` from inside it
	# answers null and this probe reports "autoload is missing" on a project that has
	# it. `_run` is a coroutine, so `_initialize` starts it and the await resumes on
	# the first real frame, by which time the singletons exist.
	await process_frame
	# ⚠ STATICS BY PATH, NEVER BY class_name — naming `BotMatch` here compiles it and
	# its whole dependency chain at THIS script's parse time. Every capture tool in
	# this project documents the same trap.
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	var scene: PackedScene = load(MATCH_SCENE) as PackedScene
	if script == null or scene == null:
		printerr("[reaction-count] could not load BotMatch")
		quit(1)
		return
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("[reaction-count] SpellReactor autoload is missing")
		quit(1)
		return
	reactor.connect(&"reaction_fired", _on_reaction)
	script.set("drops", _drops)
	var queue: Array[Vector2i] = _queue()
	print("[reaction-count] %d bouts · tier %d · hp %d · round %.0fs · drops=%s"
		% [queue.size(), _difficulty, _hp, _round, str(_drops)])
	for i: int in queue.size():
		var pair: Vector2i = queue[i]
		script.set("class_a", pair.x)
		script.set("class_b", pair.y)
		script.set("difficulty", _difficulty)
		script.set("fighter_hp", _hp)
		script.set("round_seconds", _round)
		script.set("auto_rematch", false)
		script.set("swap_sides", i % 2 == 1)
		_bout_label = "%d v %d" % [pair.x, pair.y]
		await _one_match(scene, reactor, i)
	_report(queue.size())
	quit(0)


func _queue() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _roundrobin:
		for i: int in mini(_pairs, PAIRINGS.size()):
			out.append(PAIRINGS[i])
		return out
	for a: int in CLASS_COUNT:
		for b: int in range(a + 1, CLASS_COUNT):
			for _r: int in _repeat:
				out.append(Vector2i(a, b))
	return out


func _on_reaction(outcome: String, _point: Vector2, _a: Node, _b: Node) -> void:
	_fired[outcome] = int(_fired.get(outcome, 0)) + 1
	if not _first_seen.has(outcome):
		_first_seen[outcome] = _bout_label


func _one_match(scene: PackedScene, reactor: Node, index: int) -> void:
	var node: Node = scene.instantiate()
	root.add_child(node)
	var started: float = float(Time.get_ticks_msec()) / 1000.0
	var before: int = _total()
	while true:
		await process_frame
		if not is_instance_valid(node):
			break
		# Sample the registry every frame. Cheap (one int read) and it is the only
		# way to tell "the table never matched" from "nothing was ever in there".
		var live: int = int(reactor.call(&"live_count"))
		_live_samples += 1
		_live_total += live
		_live_peak = maxi(_live_peak, live)
		if node.has_method("match_over") and bool(node.call("match_over")):
			break
		if float(Time.get_ticks_msec()) / 1000.0 - started > _wall:
			break
	print("[reaction-count] bout %d (%s): %d reactions"
		% [index, _bout_label, _total() - before])
	if is_instance_valid(node):
		node.free()
	paused = false


func _total() -> int:
	var n: int = 0
	for k: String in _fired:
		n += int(_fired[k])
	return n


func _report(bouts: int) -> void:
	# Every outcome the table names, so a ZERO gets a printed row rather than being
	# absent from the report — an absent row reads as "not asked", which is the exact
	# misreading this whole probe exists to prevent.
	var authored: Array[String] = []
	for r: Dictionary in ReactionTable.rules():
		var k: String = String(r["outcome"])
		if k != "none" and not authored.has(k):
			authored.append(k)
	print("\n=== REACTIONS FIRED over %d bouts ===" % bouts)
	# `matched` is the table saying yes BEFORE geometry ran. matched > fired means
	# the row is right and the two effects never physically touched, which is a
	# completely different problem from matched == 0 (the row was never reached).
	print("%-22s %-8s %-9s %-9s %s"
		% ["outcome", "fired", "matched", "per bout", "first seen in"])
	var live_reactions: int = 0
	# ⚠ THE STATICS ARE READ OFF THE LOADED SCRIPT, NOT BY class_name. Naming
	# `SpellReactorNode` here would compile it and its dependency chain at this
	# tool's parse time — the trap every capture tool in this project documents.
	# `load()` returns the cached GDScript the autoload is already running, so its
	# static vars are the same storage.
	var reactor_script: GDScript = load("res://scripts/combat/SpellReactor.gd") as GDScript
	var matched: Dictionary = reactor_script.get("rule_matched") as Dictionary
	for k: String in authored:
		var n: int = int(_fired.get(k, 0))
		if n > 0:
			live_reactions += 1
		print("%-22s %-8d %-9d %-9.2f %s"
			% [k, n, int(matched.get(k, 0)), float(n) / maxf(float(bouts), 1.0),
				String(_first_seen.get(k, "—"))])
	# Anything the reactor emitted that the table does not name would be a bug in
	# this probe's idea of the table, so say so loudly rather than dropping it.
	for k: String in _fired:
		if not authored.has(k):
			print("%-22s %-8d %-9s ⚠ NOT IN ReactionTable.rules()"
				% [k, int(_fired[k]), ""])
	print("\n  %d of %d authored outcomes fired at least once" % [live_reactions, authored.size()])
	print("  total reactions: %d over %d bouts (%.2f per bout)"
		% [_total(), bouts, float(_total()) / maxf(float(bouts), 1.0)])
	var avg: float = float(_live_total) / maxf(float(_live_samples), 1.0)
	print("  registry: %.2f effects live on average, %d peak (%d samples)"
		% [avg, _live_peak, _live_samples])
	# WHAT WAS EVEN IN THE SYSTEM. Every zero above has to be read against this: a
	# reaction between two effects that were never both on the floor is not a table
	# failure, and `live_ticks` (30 Hz ticks spent ACTIVE) is what separates "the bot
	# never cast it" from "it exists for four frames".
	print("\n  registered effects, by description:")
	var regs: Dictionary = reactor_script.get("registrations") as Dictionary
	var ticks: Dictionary = reactor_script.get("live_ticks") as Dictionary
	var tags: Array = regs.keys()
	tags.sort()
	for t: String in tags:
		print("    %-22s cast %-5d  live for %d ticks (%.1f s)"
			% [t, int(regs[t]), int(ticks.get(t, 0)), float(ticks.get(t, 0)) / 30.0])
	# THE ACTIONABLE SILENCES — pairs that really met in play and had no row.
	print("\n  no-rule pairs that actually occurred (top 12):")
	var silences: Dictionary = reactor_script.get("no_rule_pairs") as Dictionary
	var ranked: Array = silences.keys()
	ranked.sort_custom(func(x: String, y: String) -> bool:
		return int(silences[x]) > int(silences[y]))
	for i: int in mini(12, ranked.size()):
		print("    %-6d %s" % [int(silences[ranked[i]]), String(ranked[i])])
	# WHERE THE PAIRS DIED, by stage. See the block above `pair_tests` in
	# SpellReactor for why a bare fired-count cannot be read without this.
	var tests: float = maxf(float(reactor_script.get("pair_tests")), 1.0)
	print("  pair tests: %d  ->  bucket-miss %d (%.0f%%)  no-rule %d (%.0f%%)  "
			% [int(tests),
				int(reactor_script.get("gate_bucket_miss")),
				100.0 * float(reactor_script.get("gate_bucket_miss")) / tests,
				int(reactor_script.get("gate_no_rule")),
				100.0 * float(reactor_script.get("gate_no_rule")) / tests]
		+ "memo %d  no-shape %d  no-overlap %d (%.0f%%)  APPLIED %d"
			% [int(reactor_script.get("gate_memo")),
				int(reactor_script.get("gate_no_shape")),
				int(reactor_script.get("gate_no_overlap")),
				100.0 * float(reactor_script.get("gate_no_overlap")) / tests,
				int(reactor_script.get("gate_applied"))])
