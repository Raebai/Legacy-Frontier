# Run: godot --headless --path godot-project --script tools/_probe_boss_audit.gd
#
# READ-ONLY AUDIT PROBE. Measures what a ten-floor Ashspire climb actually draws
# today: which artist stands on each floor, at what body scale, at what HP, and
# how many DISTINCT artists a whole climb sees. Prints a table; changes nothing.
extends SceneTree

const CLIMBS: int = 200


func _initialize() -> void:
	var gs: GDScript = load("res://scripts/GameState.gd") as GDScript
	var enc: GDScript = load("res://scripts/combat/Encounter.gd") as GDScript
	var tower: Resource = gs.call("build_default_tower")

	print("=== ASHSPIRE FLOOR TABLE (authored) ===")
	print("fl  type      boss_scale  hp_frac  boss_hp_mult  tags  eligible")
	for i: int in (tower.get("floors") as Array).size():
		var f: Resource = (tower.get("floors") as Array)[i]
		var t: int = int(f.get("floor_type"))
		var scale: float = float(enc.call("resolved_boss_scale", f))
		var frac: float = float(enc.call("resolved_boss_hp_fraction", f))
		print("%2d  %-9s %-11.2f %-8.2f %-13.2f %-5s %s" % [
			i + 1, _type_name(t), scale, frac, float(f.get("boss_hp_multiplier")),
			str(f.get("special_tags")), str(BossRoster.eligible(i + 1))])

	print("\n=== ONE CLIMB, TEN FLOORS (seed 0 == FloorGen.last_seed default) ===")
	_one_climb(0, true)

	print("\n=== DISTINCT ARTISTS PER CLIMB, over %d seeds ===" % CLIMBS)
	var hist: Dictionary = {}
	var per_boss_floors: Dictionary = {}
	for c: int in CLIMBS:
		var seedv: int = c * 2654435761
		var seen: Dictionary = {}
		for d: int in range(1, 11):
			var r: Dictionary = BossRoster.roll(
				d, FloorGen.mix_seed(seedv, d * 2654435761), "", [], true)
			var bid: String = String(r["boss"])
			seen[bid] = true
			var key: String = "%s@%d" % [bid, d]
			per_boss_floors[key] = int(per_boss_floors.get(key, 0)) + 1
		hist[seen.size()] = int(hist.get(seen.size(), 0)) + 1
	var keys: Array = hist.keys()
	keys.sort()
	for k in keys:
		print("  %d distinct artists in a 10-floor climb: %d / %d climbs (%.0f%%)"
			% [int(k), int(hist[k]), CLIMBS, 100.0 * float(hist[k]) / float(CLIMBS)])

	print("\n=== HOW OFTEN EACH ARTIST DRAWS EACH FLOOR (%d climbs) ===" % CLIMBS)
	print("fl   " + "  ".join(PackedStringArray(BossRoster.ids())))
	for d: int in range(1, 11):
		var row: Array[String] = []
		for bid: String in BossRoster.ids():
			row.append("%5.1f%%" % (100.0 * float(int(per_boss_floors.get("%s@%d" % [bid, d], 0))) / float(CLIMBS)))
		print("%2d  %s" % [d, "  ".join(PackedStringArray(row))])

	print("\n=== GUARDIAN REPEAT COUNT PER CLIMB ===")
	var rep: Dictionary = {}
	for c2: int in CLIMBS:
		var seedv2: int = c2 * 2654435761
		var n: int = 0
		for d2: int in range(1, 11):
			if String(BossRoster.roll(d2, FloorGen.mix_seed(seedv2, d2 * 2654435761))["boss"]) == BossRoster.GUARDIAN:
				n += 1
		rep[n] = int(rep.get(n, 0)) + 1
	var rk: Array = rep.keys()
	rk.sort()
	for k2 in rk:
		print("  the Ashspire Guardian appears %d times: %d climbs" % [int(k2), int(rep[k2])])

	print("\n=== FULL-CEREMONY FLOORS (body_scale >= 0.9) ===")
	for i2: int in (tower.get("floors") as Array).size():
		var f2: Resource = (tower.get("floors") as Array)[i2]
		var s2: float = float(enc.call("resolved_boss_scale", f2))
		if s2 >= 0.9:
			print("  floor %d gets the FULL ceremony (scale %.2f)" % [i2 + 1, s2])
	quit(0)


func _one_climb(seedv: int, verbose: bool) -> void:
	for d: int in range(1, 11):
		var r: Dictionary = BossRoster.roll(d, FloorGen.mix_seed(seedv, d * 2654435761))
		if verbose:
			print("  floor %2d -> %-14s mods=%s" % [d, String(r["boss"]), str(r["mods"])])


func _type_name(t: int) -> String:
	match t:
		0: return "COMBAT"
		1: return "ELITE"
		2: return "BOSS"
		3: return "REST"
		4: return "PVP"
	return "?"
