extends SceneTree
## WHERE DOES THE RANK LADDER LAND? — a headless accrual model for `Rank`.
##
## Run:
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
##       --path godot-project --script tools/rank_sim.gd
##   ... --script tools/rank_sim.gd -- --streak=0.35 --from=3
##
## Options (`--key=value`, order-independent):
##   --streak=F   fraction of a floor's kills that also land a STREAK/MULTI bonus.
##                Default 0.30. 0 = the pessimistic floor (kills + wave clears only).
##   --from=N     start the climb on floor N (the persistent climb resumes on your
##                saved floor, so a real session is usually NOT five floors).
##
## ══ WHY ═══════════════════════════════════════════════════════════════════════
## The fun audit measured `Rank` exhausting itself in the first ~40 seconds: 6 tiers
## over 84 power, at 3 power per kill, against a floor that banks 27 kills. Then it
## PERSISTED, so it was maxed for every future run too. This walks the real floor
## tables against the real `Rank` curve and prints which floor each tier lands on,
## so the curve can be sized to a climb instead of to a paragraph.
##
## ══ WHAT IT MEASURES ══════════════════════════════════════════════════════════
## The three grant channels that exist today: `Rank.KILL_POWER` per body
## (Enemy._die), `Hype.WAVE_CLEAR_POWER` per wave beaten, and an ESTIMATE of the
## streak / multi-kill bonuses (`Hype.STREAK_RUNGS`, `MULTI_POWER`), which depend on
## how the player actually chains and therefore cannot be read off a table. The
## streak estimate is the only guess in here and it is on the command line.

const GS_PATH: String = "res://scripts/GameState.gd"
const RANK_PATH: String = "res://scripts/combat/Rank.gd"
const HYPE_PATH: String = "res://scripts/combat/Hype.gd"

var _streak: float = 0.30
var _from: int = 1
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_parse_args()
	var gs: GDScript = load(GS_PATH) as GDScript
	var rank: GDScript = load(RANK_PATH) as GDScript
	var hype: GDScript = load(HYPE_PATH) as GDScript
	var tower: Resource = gs.build_default_tower()
	var tiers: Array = rank.get("TIER_POWER")
	var titles: Array = rank.get("TIER_TITLE")
	var kill_power: int = int(rank.get("KILL_POWER"))
	var wave_power: int = int(hype.get("WAVE_CLEAR_POWER"))
	var multi_power: int = int(hype.get("MULTI_POWER"))
	print("")
	print("════════════════════════════════════════════════════════════════════")
	print(" RANK LADDER — accrual across a climb starting on floor %d" % _from)
	print(" curve %s   kill %d   wave %d   streak estimate %.0f%% of kills"
		% [str(tiers), kill_power, wave_power, _streak * 100.0])
	print("════════════════════════════════════════════════════════════════════")
	var power: int = 0
	var reached: Dictionary = {}
	var floors: Array = tower.get("floors")
	for i: int in range(floors.size()):
		var f: Resource = floors[i]
		var depth: int = i + 1
		if depth < _from:
			continue
		var bodies: int = 0
		var waves: Array = f.get("waves")
		for w in waves:
			bodies += maxi(int(w.get("enemy_budget")), 0)
		if bodies == 0:
			bodies = int(f.get("enemy_budget"))
		var kills: int = bodies + 1                       # + the floor's guardian
		var gained: int = kills * kill_power
		gained += waves.size() * wave_power               # Hype.wave_beaten
		# Streak / multi estimate: a chained kill is worth a multi bonus, and every
		# so often a named rung on top. Deliberately crude and deliberately visible.
		gained += int(round(float(kills) * _streak * float(multi_power)))
		var before: int = power
		power += gained
		for t: int in range(tiers.size()):
			var need: int = int(tiers[t])
			if before < need and power >= need and not reached.has(t):
				reached[t] = depth
		print(" floor %d  %2d waves  %3d kills  +%4d  ->  total %5d   (%s)"
			% [depth, waves.size(), kills, gained, power, _title_at(tiers, titles, power)])
	print("")
	print(" tier landings:")
	for t: int in range(tiers.size()):
		var where: String = "floor %d" % int(reached[t]) if reached.has(t) else "NOT REACHED"
		if t == 0:
			where = "start"
		print("   tier %d  %-11s  need %5d   %s" % [t, String(titles[t]), int(tiers[t]), where])
	print("")
	print(" a climb that tops out on floor 1 has no reward channel left for floors")
	print(" 2-5; a climb that never reaches the top tier has one all the way up.")
	print("")
	quit(0)
	return true


func _title_at(tiers: Array, titles: Array, power: int) -> String:
	var t: int = 0
	for i: int in range(tiers.size()):
		if power >= int(tiers[i]):
			t = i
	return String(titles[t])


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--streak="):
			_streak = maxf(float(arg.substr(9)), 0.0)
		elif arg.begins_with("--from="):
			_from = clampi(int(arg.substr(7)), 1, 5)
