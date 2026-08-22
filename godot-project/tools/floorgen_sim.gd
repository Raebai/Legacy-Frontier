extends SceneTree
## HOW LONG IS A *GENERATED* FLOOR? — and, the number that actually matters, HOW
## WIDE IS THE SPREAD?
##
## Run:
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
##       --path godot-project --script tools/floorgen_sim.gd
##   ... --script tools/floorgen_sim.gd -- --rolls=60 --dps=45
##
## Options (`--key=value`, order-independent):
##   --rolls=N     how many climb seeds to sweep. Default 40.
##   --dps=A,B,C   single-target damage per second. Default 45 (the middle of
##                 floor_sim's sweep — this tool is about VARIANCE, not about the
##                 player model, so one rate keeps the table readable).
##   --switch=SEC  seconds lost between finishing one body and hurting the next.
##   --dt=SEC      sim step. Default 0.05.
##
## ⚠ THE POINT OF THIS TOOL IS THE SPREAD, NOT THE AVERAGE. `tools/floor_sim.gd`
## already measures the authored table. What a generator can do that an authored
## table cannot is produce an OUTLIER — and a floor that occasionally resolves in
## twenty seconds is a worse problem than a floor whose average is short, because
## the average is a tuning job and the outlier is a broken promise. So this reports
## min / median / max and the min:max ratio per floor, and it flags any roll that
## lands outside a factor of the floor's own median.
##
## Every caveat on floor_sim applies here verbatim and is not repeated: enemy AI is
## off, there is nobody to chase, and so every number below is an OPTIMISTIC FLOOR on
## the real duration. Treat it as "is this floor 90 seconds or 12 minutes".

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const GS_PATH: String = "res://scripts/GameState.gd"

const SIM_LIMIT: float = 1800.0
## A roll further than this from its floor's own median is called out by name, so it
## can be replayed from its seed.
const OUTLIER_FACTOR: float = 1.6

var _rolls: int = 40
var _dps_list: Array[float] = [45.0]
var _switch: float = 0.55
var _dt: float = 0.05
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_parse_args()
	var gs: GDScript = load(GS_PATH) as GDScript
	var base: Resource = gs.build_default_tower()
	print("")
	print("════════════════════════════════════════════════════════════════════")
	print(" GENERATED FLOOR DURATION SPREAD — The Ashen Tower, %d climb seeds" % _rolls)
	print(" dps %s · per-target overhead %.2fs · step %.3fs" % [str(_dps_list), _switch, _dt])
	print(" A SIM IS NOT A PLAYTEST. Enemy AI is off; these are optimistic floors.")
	print("════════════════════════════════════════════════════════════════════")

	for dps: float in _dps_list:
		# floor index -> the durations every seed produced for it
		var per_floor: Array[Array] = []
		var per_floor_seed: Array[Array] = []
		var authored: Array[float] = []
		for i: int in (base.floors as Array).size():
			per_floor.append([] as Array)
			per_floor_seed.append([] as Array)
			authored.append(_sim_floor(base.floors[i], dps))
		for r: int in _rolls:
			var seed_value: int = 10007 * (r + 1) + 13
			var t: Resource = FloorGen.vary_tower(base, seed_value)
			for i: int in (t.floors as Array).size():
				per_floor[i].append(_sim_floor(t.floors[i], dps))
				per_floor_seed[i].append(seed_value)
		print("")
		print("  dps %.0f" % dps)
		print("  floor   authored     min       median      max      min:max   outliers")
		var tower_min: float = 0.0
		var tower_med: float = 0.0
		var tower_max: float = 0.0
		for i: int in per_floor.size():
			var xs: Array = per_floor[i].duplicate()
			xs.sort()
			var lo: float = float(xs[0])
			var hi: float = float(xs[xs.size() - 1])
			var med: float = float(xs[xs.size() / 2])
			tower_min += lo
			tower_med += med
			tower_max += hi
			var outliers: Array[String] = []
			for k: int in per_floor[i].size():
				var v: float = float(per_floor[i][k])
				if med > 0.0 and (v > med * OUTLIER_FACTOR or v < med / OUTLIER_FACTOR):
					outliers.append("seed %d (%s)" % [int(per_floor_seed[i][k]), _mmss(v)])
			print("  %-6d  %-10s  %-9s  %-10s  %-8s  %-8s  %s" % [
				i + 1, _mmss(authored[i]), _mmss(lo), _mmss(med), _mmss(hi),
				"%.2f" % (lo / maxf(hi, 0.001)),
				("none" if outliers.is_empty() else ", ".join(outliers)),
			])
		print("  TOWER   %-10s  %-9s  %-10s  %-8s" % [
			_mmss(_sum(authored)), _mmss(tower_min), _mmss(tower_med), _mmss(tower_max)])
	print("")
	quit(0)
	return true


func _sum(xs: Array[float]) -> float:
	var t: float = 0.0
	for x: float in xs:
		t += x
	return t


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rolls="):
			_rolls = clampi(arg.substr(8).to_int(), 1, 500)
		elif arg.begins_with("--dps="):
			var list: Array[float] = []
			for part: String in arg.substr(6).split(",", false):
				list.append(maxf(part.to_float(), 1.0))
			if not list.is_empty():
				_dps_list = list
		elif arg.begins_with("--switch="):
			_switch = maxf(arg.substr(9).to_float(), 0.0)
		elif arg.begins_with("--dt="):
			_dt = clampf(arg.substr(5).to_float(), 0.005, 0.25)


## Drive ONE floor through the real Encounter and time it. The same player model as
## floor_sim (hurt one thing at a time, lose `switch` between kills) so the two
## tools' numbers are directly comparable.
func _sim_floor(fd: FloorDef, dps: float) -> float:
	var arena := Node2D.new()
	root.add_child(arena)
	var hero := Node2D.new()
	hero.add_to_group("hero")
	arena.add_child(hero)
	if fd.layout != null:
		hero.global_position = fd.layout.hero_start
	var enc: Node = load(ENCOUNTER_PATH).new()
	arena.add_child(enc)
	enc.set_process(false)
	var done: Array[bool] = [false]
	enc.connect("cleared", func() -> void: done[0] = true)
	var t: float = 0.0
	var busy: float = 0.0
	enc.call("run_floor", fd)
	while not done[0] and t < SIM_LIMIT:
		enc.call("_process", _dt)
		var live: Array[Node] = get_nodes_in_group("enemy")
		for e: Node in live:
			e.set_physics_process(false)
		if busy > 0.0:
			busy -= _dt
		elif not live.is_empty():
			var target: Node = live[0]
			var hp: float = float(target.get("hp")) - dps * _dt
			if hp <= 0.0:
				target.free()
				busy = _switch
			else:
				target.set("hp", int(ceil(hp)))
		t += _dt
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	arena.free()
	return t


func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]
