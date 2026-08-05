# READ-ONLY DIAGNOSTIC — does a bot duel resolve, is the roster balanced, and is
# there dead air? Runs the REAL `BotMatch` scene (the same one Lobby -> Watch Bots
# opens and `directed_clip_capture` films) over every unordered class pairing in BOTH
# side orders, and samples the board once per frame.
#
#   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
#       --path godot-project --script tools/_probe_duel_quality.gd -- --hp=190 --round=30
#
# Options: --hp=N --round=SEC --difficulty=0..3 --wall=SEC --limit=N --out=PATH
#
# WHAT IT ADDS OVER `tools/botmatch_sim.gd`: that tool runs 8 hand-picked pairings,
# which cannot answer a balance question. This runs 72 bouts (36 pairings x 2 sides,
# so the stage's left/right asymmetry cancels) and additionally buckets each bout's
# game clock into one-second bins, marking a bin ACTIVE if any of the three things an
# audience can see happened in it: HP moved, a spell/projectile was in flight, or a
# telegraph was armed. That is the dead-air measurement.
#
# It changes nothing. Both fighters are the stock BotController + BotBrain + BotProfile
# at the same tier on mirrored footing.
extends SceneTree

const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"

const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]
const SPELL_GROUPS: Array[StringName] = [&"player_spell", &"enemy_projectile"]

var _hp: int = 190
var _round: float = 30.0
var _difficulty: int = 3
var _wall: float = 90.0
var _limit: int = 0
var _out: String = "user://duel_quality"

var _rows: Array[Dictionary] = []


func _initialize() -> void:
	_parse_args()
	print("[duel-probe] hp=%d round=%.0fs tier=%d" % [_hp, _round, _difficulty])
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
			"hp": _hp = maxi(int(value), 40)
			"round": _round = maxf(float(value), 4.0)
			"difficulty": _difficulty = clampi(int(value), 0, 3)
			"wall": _wall = maxf(float(value), 10.0)
			"limit": _limit = int(value)
			"out": _out = value


func _run() -> void:
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	var scene: PackedScene = load(MATCH_SCENE) as PackedScene
	if script == null or scene == null:
		printerr("[duel-probe] could not load the match")
		quit(1)
		return
	var pairs: Array[Vector2i] = []
	for i: int in CLASS_NAMES.size():
		for j: int in range(i + 1, CLASS_NAMES.size()):
			pairs.append(Vector2i(i, j))
			pairs.append(Vector2i(j, i))    # both side orders
	if _limit > 0 and pairs.size() > _limit:
		pairs.resize(_limit)
	for n: int in pairs.size():
		var p: Vector2i = pairs[n]
		script.set("class_a", p.x)
		script.set("class_b", p.y)
		script.set("difficulty", _difficulty)
		script.set("fighter_hp", _hp)
		script.set("round_seconds", _round)
		script.set("auto_rematch", false)
		script.set("swap_sides", false)
		script.set("intro_seconds", 0.0)
		script.set("taunts", false)
		await _one(scene, n)
	_report()
	quit(0)


func _one(scene: PackedScene, index: int) -> void:
	var node: Node = scene.instantiate()
	root.add_child(node)
	var started: float = float(Time.get_ticks_msec()) / 1000.0
	var over: bool = false
	# One-second activity bins over the GAME clock, plus the raw event counts.
	var bins: Dictionary = {}          # int second -> true
	var damage_bins: Dictionary = {}
	var spell_bins: Dictionary = {}
	var hp_seen: Dictionary = {}       # instance_id -> int
	var damage_events: int = 0
	var last_clock: float = 0.0
	while true:
		await process_frame
		if not is_instance_valid(node):
			break
		var clock: float = 0.0
		var r0: Variant = node.call("result") if node.has_method("result") else null
		if r0 is Dictionary:
			clock = float((r0 as Dictionary).get("seconds", 0.0))
		last_clock = clock
		var bin: int = int(floor(clock))
		var hot: bool = false
		# HP movement, per fighter.
		for f: Node in get_nodes_in_group(&"hero"):
			if not is_instance_valid(f):
				continue
			var id: int = f.get_instance_id()
			var hp: int = int(f.get("hp"))
			if hp_seen.has(id) and hp < int(hp_seen[id]):
				damage_events += 1
				damage_bins[bin] = true
				hot = true
			hp_seen[id] = hp
		# Anything in flight.
		var flying: int = 0
		for g: StringName in SPELL_GROUPS:
			flying += get_nodes_in_group(g).size()
		if flying > 0:
			spell_bins[bin] = true
			hot = true
		# An armed telegraph is a promise the audience can read.
		for t: Node in get_nodes_in_group(&"telegraph"):
			if t.has_method(&"is_armed") and bool(t.call(&"is_armed")):
				hot = true
				break
		if hot:
			bins[bin] = true
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
	if not over:
		row["outcome"] = "UNRESOLVED"
	var span: int = maxi(int(ceil(maxf(last_clock, 0.001))), 1)
	row["span_s"] = span
	row["active_s"] = bins.size()
	row["damage_s"] = damage_bins.size()
	row["spell_s"] = spell_bins.size()
	row["damage_events"] = damage_events
	_rows.append(row)
	print("[duel-probe] %2d  %-12s vs %-12s -> %-10s %-12s %5.1fs  active %d/%d"
		% [index, String(row.get("left", "?")), String(row.get("right", "?")),
			String(row.get("outcome", "?")), String(row.get("winner", "")),
			float(row.get("seconds", 0.0)), int(row["active_s"]), span])
	if is_instance_valid(node):
		node.free()
	paused = false


func _report() -> void:
	var wins: Dictionary = {}
	var played: Dictionary = {}
	var by_outcome: Dictionary = {}
	var durations: Array[float] = []
	var active_total: int = 0
	var span_total: int = 0
	var damage_total: int = 0
	var spell_total: int = 0
	for r: Dictionary in _rows:
		var kind: String = String(r.get("outcome", "?"))
		by_outcome[kind] = int(by_outcome.get(kind, 0)) + 1
		for k: String in ["left", "right"]:
			var who: String = String(r.get(k, ""))
			if who != "":
				played[who] = int(played.get(who, 0)) + 1
		var w: String = String(r.get("winner", ""))
		if w != "":
			wins[w] = int(wins.get(w, 0)) + 1
		durations.append(float(r.get("seconds", 0.0)))
		active_total += int(r.get("active_s", 0))
		span_total += int(r.get("span_s", 0))
		damage_total += int(r.get("damage_s", 0))
		spell_total += int(r.get("spell_s", 0))
	durations.sort()
	var n: int = durations.size()
	print("\n[duel-probe] %d bouts" % n)
	for kind: String in by_outcome:
		print("    %-12s %d" % [kind, int(by_outcome[kind])])
	if n > 0:
		print("  duration  p10 %.1fs  median %.1fs  p90 %.1fs  min %.1fs  max %.1fs"
			% [durations[int(n * 0.1)], durations[n / 2], durations[mini(int(n * 0.9), n - 1)],
				durations[0], durations[n - 1]])
	print("  PACING (1 s bins over the game clock, all bouts pooled):")
	print("    any activity   %d/%d = %.0f%%"
		% [active_total, span_total, 100.0 * float(active_total) / maxf(float(span_total), 1.0)])
	print("    damage landed  %d/%d = %.0f%%"
		% [damage_total, span_total, 100.0 * float(damage_total) / maxf(float(span_total), 1.0)])
	print("    spell in air   %d/%d = %.0f%%"
		% [spell_total, span_total, 100.0 * float(spell_total) / maxf(float(span_total), 1.0)])
	print("  WIN RATE:")
	var names: Array = played.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ra: float = float(int(wins.get(a, 0))) / maxf(float(int(played[a])), 1.0)
		var rb: float = float(int(wins.get(b, 0))) / maxf(float(int(played[b])), 1.0)
		return ra > rb)
	for who: String in names:
		var wn: int = int(wins.get(who, 0))
		var pl: int = int(played[who])
		print("    %-12s %2d/%2d  %3.0f%%" % [who, wn, pl, 100.0 * float(wn) / maxf(float(pl), 1.0)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var f: FileAccess = FileAccess.open("%s/report.json" % _out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"hp": _hp, "round": _round, "difficulty": _difficulty,
			"wins": wins, "played": played, "by_outcome": by_outcome,
			"active_s": active_total, "span_s": span_total,
			"damage_s": damage_total, "spell_s": spell_total,
			"rows": _rows,
		}, "\t"))
		f.close()
		print("  -> ", ProjectSettings.globalize_path("%s/report.json" % _out))
