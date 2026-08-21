# DOES THE WATCH ACTUALLY END — measured, over real matches, rather than asserted.
#
# `tools/bot_sim.gd` fights bots through its own driver to hunt anomalies. This tool
# does something narrower and, for the content engine, more important: it runs the
# REAL `BotMatch` scene — the same one the maker opens from Lobby → Watch Bots and
# the same one `directed_clip_capture` films — and reports, per matchup, whether it
# RESOLVED and who won.
#
# It exists because "the fight must end" is not an opinion you can eyeball once. Three
# separate things stopped bouts from resolving (see the header of
# `scripts/combat/BotMatch.gd`), two of them invisible from the outside, and the only
# honest way to know they are all fixed is to run a lot of fights and count.
#
# Run (headless is fine and much faster — nothing here needs a rendered pixel):
#   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
#       --path godot-project --script tools/botmatch_sim.gd -- --pairs=6 --round=25
#
# Options:
#   --pairs=N       how many matchups to run. Default 6. They are drawn from
#                   `PAIRINGS` in order — hand-picked opposed-element and
#                   melee-vs-ranged matchups rather than a random sweep, because a
#                   sample of six mirror-ish pairings answers nothing.
#   --round=SEC     game-seconds before a bout is decided on health. Default 25
#                   (the shipped watch uses 50; a sim wants throughput).
#   --difficulty=N  BotProfile tier for BOTH fighters, 0..3. Default 3.
#   --hp=N          the shared HP pool CLASS_VITALITY scales. Default 190.
#   --wall=SEC      hard wall-clock cap per bout, so a hang cannot hang the sim.
#                   Hit-stop drops `Engine.time_scale` to 0.05, so wall time runs
#                   well ahead of game time and this is NOT the same as --round.
#   --out=PATH      report directory. Default user://botmatch_sim.
#
# ⚠ IT DOES NOT WEAKEN THE FIGHT TO GET AN ANSWER. Both fighters are the stock bot
# stack at the same tier on mirrored footing; the only thing this tool changes is how
# long a bout may run before it is called on the health bars. A lopsided matchup is a
# BALANCE FINDING to report, not something to fix by handing somebody a stat.
extends SceneTree

const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"

const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

## Hand-picked, not swept. Each row is a matchup that is supposed to produce
## something: opposed elements (the reaction matrix's best rows), melee against
## ranged (the Brawler question), tank against burst (the vitality question).
## The roster size the round-robin walks.
const CLASS_COUNT: int = 9

const PAIRINGS: Array[Vector2i] = [
	Vector2i(6, 5),   # STORMCALLER vs CRYOMANCER — lightning into frost: supercharge
	Vector2i(2, 0),   # BRAWLER vs ARCANIST       — pure melee against a pure zoner
	Vector2i(3, 1),   # JUGGERNAUT vs SHADOWBLADE — the wall against the knife
	Vector2i(4, 7),   # CLERIC vs WARLOCK         — holy against shadow: banish
	Vector2i(8, 2),   # SWORDSAINT vs BRAWLER     — guard-and-punish against pressure
	Vector2i(5, 0),   # CRYOMANCER vs ARCANIST    — two casters, different ranges
	Vector2i(7, 3),   # WARLOCK vs JUGGERNAUT     — attrition against the longest bar
	Vector2i(1, 6),   # SHADOWBLADE vs STORMCALLER— the two fastest bodies
]

## ROUND-ROBIN. `PAIRINGS` is eight hand-picked matchups chosen to be INTERESTING,
## which is exactly the wrong sample for a balance question: it asks the eight fights
## somebody already thought were worth watching. `--roundrobin=1` runs every unordered
## pair of the roster instead — 36 for nine classes — `--repeat` times each, with the
## sides alternating so nothing this asymmetric stage gives away accrues to one side.
var _roundrobin: bool = false
var _repeat: int = 1
## ⚠ DROPS OFF BY DEFAULT IN A SWEEP, AND THAT IS NOT A DETAIL. `BotMatch` now hands
## each fighter a random Tier 3 — the maker's "the bots should have the cool spells" —
## and a cataclysm swings a duel harder than any class difference this sweep exists to
## measure. Left on, the numbers would be "class plus whatever it rolled" reported as
## "class". `--drops=1` measures the SHOWCASE configuration, which is a legitimate
## question and a different one.
var _drops: bool = false
var _pairs: int = 6
var _round: float = 25.0
var _difficulty: int = 3
var _hp: int = 190
var _wall: float = 150.0
var _out: String = "user://botmatch_sim"

var _rows: Array[Dictionary] = []


func _initialize() -> void:
	_parse_args()
	print("[botmatch-sim] %d matchups · tier %d · hp %d · round %.0fs"
		% [_pairs, _difficulty, _hp, _round])
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
			"out": _out = value


func _run() -> void:
	# ⚠ STATICS BY PATH, NEVER BY `class_name`. Naming `BotMatch` here would compile
	# it and its whole dependency chain at THIS script's parse time — the same trap
	# every capture tool in this project documents.
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	if script == null:
		printerr("[botmatch-sim] could not load ", MATCH_SCRIPT)
		quit(1)
		return
	var scene: PackedScene = load(MATCH_SCENE) as PackedScene
	if scene == null:
		printerr("[botmatch-sim] could not load ", MATCH_SCENE)
		quit(1)
		return
	script.set("drops", _drops)
	var queue: Array[Vector2i] = _queue()
	print("[botmatch-sim] %d bouts, roundrobin=%s drops=%s"
		% [queue.size(), str(_roundrobin), str(_drops)])
	for i: int in queue.size():
		var pair: Vector2i = queue[i]
		script.set("class_a", pair.x)
		script.set("class_b", pair.y)
		script.set("difficulty", _difficulty)
		script.set("fighter_hp", _hp)
		script.set("round_seconds", _round)
		# The sim owns the pacing, not the scene: an auto-rematch would reload the
		# current scene out from under a tool that is not driving one.
		script.set("auto_rematch", false)
		# Alternate the opening side across the sweep for the same reason the live
		# mode swaps it — this stage is not left-right symmetric.
		script.set("swap_sides", i % 2 == 1)
		await _one_match(scene, i)
	_report()
	quit(0)


## The bouts to run. Hand-picked by default; every unordered pair under
## `--roundrobin`, which is the only sample a per-class win rate can honestly come
## from — a hand-picked eight answers "are these eight fights good", not "is the
## roster balanced".
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


func _one_match(scene: PackedScene, index: int) -> void:
	var node: Node = scene.instantiate()
	root.add_child(node)
	var started: float = float(Time.get_ticks_msec()) / 1000.0
	var over: bool = false
	while true:
		await process_frame
		if not is_instance_valid(node):
			break
		if node.has_method("match_over") and bool(node.call("match_over")):
			over = true
			break
		if float(Time.get_ticks_msec()) / 1000.0 - started > _wall:
			break
	var row: Dictionary = {}
	if is_instance_valid(node) and node.has_method("result"):
		row = node.call("result") as Dictionary
	row["index"] = index
	row["resolved"] = over
	row["wall"] = snappedf(float(Time.get_ticks_msec()) / 1000.0 - started, 0.1)
	if not over:
		row["outcome"] = "UNRESOLVED"
	_rows.append(row)
	print("[botmatch-sim] %-12s vs %-12s -> %-10s %s  (%.1fs game, %.0fs wall)"
		% [String(row.get("left", "?")), String(row.get("right", "?")),
			String(row.get("outcome", "?")), String(row.get("winner", "")),
			float(row.get("seconds", 0.0)), float(row["wall"])])
	if is_instance_valid(node):
		node.free()          # immediate, so `_exit_tree` unpauses before the next bout
	# The freeze is a real tree pause; belt-and-braces in case a bout was cut off by
	# the wall clock while frozen.
	paused = false


func _report() -> void:
	var resolved: int = 0
	var draws: int = 0
	var by_outcome: Dictionary = {}
	var wins: Dictionary = {}
	var played: Dictionary = {}
	for r: Dictionary in _rows:
		if bool(r.get("resolved", false)):
			resolved += 1
		var kind: String = String(r.get("outcome", "?"))
		by_outcome[kind] = int(by_outcome.get(kind, 0)) + 1
		if kind == "DRAW":
			draws += 1
		for side_key: String in ["left", "right"]:
			var who: String = String(r.get(side_key, ""))
			if who != "":
				played[who] = int(played.get(who, 0)) + 1
		var w: String = String(r.get("winner", ""))
		if w != "":
			wins[w] = int(wins.get(w, 0)) + 1
	print("\n[botmatch-sim] %d/%d bouts RESOLVED (%d draws)" % [resolved, _rows.size(), draws])
	for kind: String in by_outcome:
		print("    %-11s %d" % [kind, int(by_outcome[kind])])
	# ⚠ WHY A GATE STAT IS IN A BALANCE REPORT. Maker: *"I havent seen many ults in
	# these stick battles"*. `bot_cast_probe` proves the brain ASKS for its ult as
	# often as anything else, but it passes no threats, so the channel-safety gate
	# never runs there and the probe cannot see its own suspect. This harness has real
	# bodies throwing real spells at each other, which makes it the only place the
	# question can be answered. See `BotBrain.channel_chances`.
	if BotBrain.channel_chances > 0:
		print("  channel gate: %d/%d channelled casts refused (%.0f%%), %d of them ults"
			% [BotBrain.channel_refusals, BotBrain.channel_chances,
				100.0 * float(BotBrain.channel_refusals) / float(BotBrain.channel_chances),
				BotBrain.ult_channel_refusals])
	# ⚠ AND THE CHANNEL GATE TURNED OUT TO BE INNOCENT. Over a real 8-bout run it
	# refused 0 of 419 casts and 0 ults, while the ult slot still fired in 1 bout of 8.
	# So the same question is now asked of EVERY gate, by reason, and printed here
	# because this harness is the only place with real bodies to ask it of.
	if BotBrain.ult_considered > 0:
		var looks: float = float(BotBrain.ult_considered)
		print("  ult slot: %d looks -> cooldown %d (%.0f%%)  absent %d (%.0f%%)  "
			% [BotBrain.ult_considered,
				BotBrain.ult_gate_cooldown, 100.0 * float(BotBrain.ult_gate_cooldown) / looks,
				BotBrain.ult_gate_absent, 100.0 * float(BotBrain.ult_gate_absent) / looks]
			+ "mana %d  range %d (%.0f%%)  channel %d  scored %d (%.0f%%)"
			% [BotBrain.ult_gate_mana,
				BotBrain.ult_gate_range, 100.0 * float(BotBrain.ult_gate_range) / looks,
				BotBrain.ult_channel_refusals,
				BotBrain.ult_scored, 100.0 * float(BotBrain.ult_scored) / looks])
		print("    of the beats where nothing was pressed, the ult was the best idea "
			+ "on the hand %d time(s) and still under the threshold"
			% BotBrain.ult_best_but_under_threshold)
	print("  win record:")
	for who: String in played:
		print("    %-12s %d/%d" % [who, int(wins.get(who, 0)), int(played[who])])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var payload: Dictionary = {
		"pairs": _pairs, "round_seconds": _round, "difficulty": _difficulty,
		"hp": _hp, "resolved": resolved, "of": _rows.size(), "draws": draws,
		"by_outcome": by_outcome, "wins": wins, "played": played, "rows": _rows,
		"godot": Engine.get_version_info().get("string", ""),
	}
	var path: String = "%s/report.json" % _out
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
		print("  -> ", ProjectSettings.globalize_path(path))
