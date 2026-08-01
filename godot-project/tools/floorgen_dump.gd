extends SceneTree
## READ A ROLL. Prints one generated floor as text — the room, the skyline, the
## cover, the spawn geometry and the wave table — so a roll can be inspected, diffed
## against another seed, or pasted into a bug report without opening the game.
##
## Run:
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
##       --path godot-project --script tools/floorgen_dump.gd -- --floor=3 --rolls=6
##
## Options: --floor=N (1-5, default 1) · --rolls=N (default 4) · --seed=N (dump one
## specific climb seed, e.g. the one `floorgen_sim` named as an outlier).

const GS_PATH: String = "res://scripts/GameState.gd"

var _floor: int = 1
var _rolls: int = 4
var _seed: int = -1
var _ran: bool = false


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--floor="):
			_floor = clampi(arg.substr(8).to_int(), 1, 5)
		elif arg.begins_with("--rolls="):
			_rolls = clampi(arg.substr(8).to_int(), 1, 50)
		elif arg.begins_with("--seed="):
			_seed = arg.substr(7).to_int()
	var base: Resource = (load(GS_PATH) as GDScript).build_default_tower()
	var seeds: Array[int] = []
	if _seed >= 0:
		seeds.append(_seed)
	else:
		for r: int in _rolls:
			seeds.append(10007 * (r + 1) + 13)
	for s: int in seeds:
		var t: Resource = FloorGen.vary_tower(base, s)
		_dump(t.floors[_floor - 1], s)
	quit(0)
	return true


func _dump(fd: FloorDef, seed_value: int) -> void:
	var l: LayoutDef = fd.layout
	var ground_y: float = l.room_size.y - FloorGen.WALL_THICKNESS * 0.5
	print("")
	print("──── floor %d · climb seed %d · %s ────" % [_floor, seed_value, str(fd.special_tags)])
	print("  room %s   ground y %.0f   theme %s %s"
		% [str(l.room_size), ground_y, fd.theme.name, str(fd.theme.wash_tint)])
	print("  hero %s   exit %s   spawn %s..%s  min-dist %.0f" % [
		str(l.hero_start), str(l.exit_point), str(l.spawn_rect_min),
		str(l.spawn_rect_max), l.min_spawn_dist_from_hero])
	print("  ledges: %d" % (l.platforms as Array).size())
	for p: Dictionary in l.platforms:
		print("     %s  x %.0f  y %.0f  w %.0f   rise above ground %.0f" % [
			("BREAKABLE " if bool(p["breakable"]) else "permanent"),
			float(p["x"]), float(p["y"]), float(p["w"]),
			ground_y - (float(p["y"]) - float(p["h"]) * 0.5)])
	print("  crates: %d   pickups: %d  %s"
		% [(l.crate_positions as Array).size(), (l.weapon_pickups as Array).size(),
			str(l.weapon_pickups)])
	print("  waves:")
	for w: WaveDef in fd.waves:
		print("     budget %-3d cap %-2d  vanguard %-3d interval %-6s  mix %s" % [
			w.enemy_budget, w.concurrent_cap, w.vanguard,
			("derived" if w.spawn_interval < 0.0 else "%.2f" % w.spawn_interval),
			str(w.archetypes)])
