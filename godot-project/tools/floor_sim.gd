extends SceneTree
## HOW LONG IS A FLOOR? — a headless estimator for the wave tables.
##
## Run:
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
##       --path godot-project --script tools/floor_sim.gd
##   ... --script tools/floor_sim.gd -- --dps=30,45,65 --legacy
##
## Options (`--key=value`, order-independent):
##   --dps=A,B,C     single-target damage per second to sweep. Default 30,45,65.
##   --switch=SEC    seconds lost between finishing one body and hurting the next
##                   (travel, dodging, repositioning). Default 0.55.
##   --dt=SEC        sim step. Default 0.05.
##   --legacy        ALSO report the pre-pacing-pass shape (1.5s silent break,
##                   0.55s trickle, no vanguard, hand off only on an empty room)
##                   against the SAME wave tables, so the delta is attributable to
##                   the pacing change rather than to a re-authored floor.
##   --strict        exit 1 if any floor's median run falls outside the 4-7 minute
##                   window. Off by default: a sim finding is a prompt to look, not
##                   a build break.
##
## ⚠ A SIM IS NOT A PLAYTEST, AND THIS ONE IS NARROWER THAN IT LOOKS.
## What it genuinely measures: the REAL Encounter driving the REAL floor data —
## wave budgets, concurrent caps, spawn intervals, the vanguard burst, the overlap
## handoff, the surge beat, the 25-entity cap and the guardian's HP — against a
## player abstracted to two numbers (a damage rate and a per-target overhead).
## What it CANNOT tell you: whether any of it is fun, whether the telegraphs are
## readable, whether a mage kites out of reach, whether you die. Enemy AI is
## switched OFF in here (there is nobody to chase), so no enemy ever spends time
## being unkillable, which makes every number below an OPTIMISTIC FLOOR on the
## real duration. Treat it as "is this floor 90 seconds or 12 minutes", never as
## "this floor takes 5:04".
##
## It also reports DEAD AIR — sim seconds with a live wave budget and NOBODY in
## the room. That is the number the pacing pass exists to drive to zero, and it is
## the one measurement here that is about the thing being fixed rather than about
## an assumed player.

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const GS_PATH: String = "res://scripts/GameState.gd"

## ⚠ THE TARGET IS A WHOLE CLIMB, NOT ONE FLOOR.
##
## This used to hold 240-420 s and compare it against a SINGLE FLOOR, because the
## design doc says "4 to 7 minutes per floor". Competitor research (see
## `docs/audit-fun-and-competitors.md`) settled that the doc's unit is wrong: a
## 4-7 minute FLOOR means a 20-35 minute run, which is precisely the band where
## the nearest comparables draw session-length complaints in their reviews. The
## same research puts a whole climb of 4-10 minutes right on Archero's run length.
##
## The practical damage was that the tool printed "OUTSIDE 4-7min" against every
## floor of a correctly-tuned tower — fifteen false alarms, which is how a real
## signal gets ignored. The window now applies to the CLIMB total, and per-floor
## rows report their share instead of being judged against a target they were
## never meant to meet.
const TARGET_MIN: float = 240.0
const TARGET_MAX: float = 600.0
## Runaway guard: a floor that has not finished by here is reported as a stall
## rather than hanging the tool.
const SIM_LIMIT: float = 1800.0

var _dps_list: Array[float] = [30.0, 45.0, 65.0]
var _switch: float = 0.55
var _dt: float = 0.05
var _legacy: bool = false
var _strict: bool = false
var _ran: bool = false
var _out_of_window: int = 0


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_parse_args()
	var gs: GDScript = load(GS_PATH) as GDScript
	print("")
	print("════════════════════════════════════════════════════════════════════")
	print(" FLOOR DURATION ESTIMATE — The Ashspire")
	print(" dps sweep %s · per-target overhead %.2fs · step %.3fs" % [str(_dps_list), _switch, _dt])
	print(" A SIM IS NOT A PLAYTEST. Enemy AI is off; these are optimistic floors.")
	print("════════════════════════════════════════════════════════════════════")
	_report(gs, false)
	if _legacy:
		print("")
		print("──── SAME WAVE TABLES, PRE-PACING-PASS SHAPE ────────────────────────")
		print(" (1.5s silent break · 0.55s trickle · no vanguard · empty-room handoff)")
		_report(gs, true)
	print("")
	if _strict and _out_of_window > 0:
		printerr("floor_sim: %d floor/dps combinations fell outside the %.0f-%.0fs window"
			% [_out_of_window, TARGET_MIN, TARGET_MAX])
		quit(1)
	else:
		quit(0)
	return true


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--legacy":
			_legacy = true
		elif arg == "--strict":
			_strict = true
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


func _report(gs: GDScript, legacy: bool) -> void:
	var tower: Resource = gs.build_default_tower()
	var totals: Dictionary = {}   # dps -> tower seconds
	for dps: float in _dps_list:
		totals[dps] = 0.0
	for i: int in (tower.floors as Array).size():
		var fd: FloorDef = tower.floors[i]
		var head: String = "Floor %d  ·  %s  ·  %d waves, %d bodies + guardian" % [
			i + 1, _type_name(int(fd.floor_type)), (fd.waves as Array).size(), int(fd.enemy_budget)
		]
		print("")
		print(head)
		for dps: float in _dps_list:
			var r: Dictionary = _sim_floor(fd, dps, legacy)
			totals[dps] = float(totals[dps]) + float(r["total"])
			# A FLOOR is never judged against the window — see TARGET_MIN. It reports
			# its own shape; the climb total below is what carries a verdict.
			print("   dps %-4.0f  total %-7s  waves %-7s  guardian %-7s  dead air %-6s  %s" % [
				dps,
				_mmss(float(r["total"])),
				_mmss(float(r["waves"])),
				_mmss(float(r["boss"])),
				_secs(float(r["dead"])),
				("stall?" if float(r["total"]) >= SIM_LIMIT else ""),
			])
			print("      per wave: %s" % str(r["per_wave"]))
	print("")
	print("   TOWER TOTAL (5 floors)   ·   target window %s - %s for a WHOLE CLIMB:"
		% [_mmss(TARGET_MIN), _mmss(TARGET_MAX)])
	for dps: float in _dps_list:
		var t: float = float(totals[dps])
		var ok: bool = t >= TARGET_MIN and t <= TARGET_MAX
		if not ok and not legacy:
			_out_of_window += 1
		print("      dps %-4.0f  %-7s  %s" % [
			dps, _mmss(t), ("in window" if ok else "OUTSIDE the climb window")
		])


## Drive ONE floor through the real Encounter and time it.
func _sim_floor(fd: FloorDef, dps: float, legacy: bool) -> Dictionary:
	var arena := Node2D.new()
	root.add_child(arena)
	# A hero stand-in: the spawn-point rejection and the 25-entity budget both
	# count heroes, so leaving it out would quietly make the room bigger.
	var hero := Node2D.new()
	hero.add_to_group("hero")
	arena.add_child(hero)
	if fd.layout != null:
		hero.global_position = fd.layout.hero_start
	var enc: Node = load(ENCOUNTER_PATH).new()
	arena.add_child(enc)
	enc.set_process(false)   # hand-driven, so nothing advances behind the clock

	var floor_def: FloorDef = _shape(fd, legacy)
	var done: Array[bool] = [false]
	enc.connect("cleared", func() -> void: done[0] = true)
	var wave_marks: Array[float] = []
	enc.connect("wave_cleared", func(_i: int, _n: int) -> void: wave_marks.append(0.0))

	var t: float = 0.0
	var dead: float = 0.0
	var boss_started: float = -1.0
	var per_wave: Array = []
	var last_mark: float = 0.0
	var busy: float = 0.0
	enc.call("run_floor", floor_def)
	while not done[0] and t < SIM_LIMIT:
		enc.call("_process", _dt)
		# Newly arrived bodies: silence their AI. There is no real hero to chase,
		# and this is a measurement of SPAWN PACING against KILL THROUGHPUT, not a
		# fight — running eight stick figures' physics would only add noise.
		var live: Array[Node] = get_nodes_in_group("enemy")
		for e: Node in live:
			e.set_physics_process(false)
		# DEAD AIR: the wave still owes bodies (or the boss is due) and the room is
		# empty. This is what the pacing pass exists to remove.
		var phase: int = int(enc.call("phase"))
		if live.is_empty() and phase != 4:
			dead += _dt
		# The player model: hurt one thing at a time, lose `switch` between kills.
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
		if wave_marks.size() > per_wave.size():
			per_wave.append(_secs(t - last_mark))
			last_mark = t
		if boss_started < 0.0 and phase == 3:
			boss_started = t
	var total: float = t
	var boss: float = (total - boss_started) if boss_started >= 0.0 else 0.0
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	arena.free()
	return {
		"total": total,
		"waves": total - boss,
		"boss": boss,
		"dead": dead,
		"per_wave": per_wave,
		"stalled": t >= SIM_LIMIT,
	}


## The floor as it will actually run, or a reconstruction of the pre-pacing-pass
## shape against the SAME wave tables (so the comparison isolates the pacing).
## Duplicated rather than mutated: FloorDefs come from a static builder and are
## shared across the dps sweep.
func _shape(fd: FloorDef, legacy: bool) -> FloorDef:
	if not legacy:
		return fd
	var out: FloorDef = fd.duplicate(true) as FloorDef
	out.wave_break = 1.5
	var waves: Array[WaveDef] = []
	for w: WaveDef in out.waves:
		var c: WaveDef = w.duplicate(true) as WaveDef
		c.spawn_interval = 0.55
		c.vanguard = 0        # no draw-in: one body every interval
		c.handoff_alive = 0   # hand off only once the room is genuinely empty
		waves.append(c)
	out.waves = waves
	return out


func _type_name(t: int) -> String:
	match t:
		1: return "ELITE"
		2: return "BOSS"
		3: return "REST"
		4: return "PVP"
		_: return "COMBAT"


func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func _secs(s: float) -> String:
	return "%.1fs" % s
