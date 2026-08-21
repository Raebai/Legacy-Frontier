extends SceneTree
## ARE TWO SPELL TITLES EVER ON SCREEN AT ONCE?
##
## Maker: *"we are still seeing double headers for some of these spells"*. A previous
## pass proved the DISPATCH is not doubled (exactly one announce per cast) and fixed a
## DRAWING artefact where the ult title slid across itself. The report came back, so
## this counts the thing the maker can actually see: how many live title nodes exist on
## the same frame, and how many of those are ult banners.
##
## ⚠ `queue_free()` IS DEFERRED, which is the prime suspect. `CastName._ult_banner`
## dedupes by freeing every existing member of `ULT_GROUP` before adding its own — but
## a queued free does not leave the tree until the end of the frame, so two ults cast
## on the same frame BOTH draw, and a spell that announces more than once per cast
## would stack for as long as it kept announcing.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_cast_titles.gd

const MATCH_SCENE := "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT := "res://scripts/combat/BotMatch.gd"
const SETTLE: int = 120
const FRAMES: int = 3600
## Pairs picked to cover both announcement rungs across different kits.
const PAIRS: Array[Array] = [[6, 8], [3, 6], [0, 1], [7, 4]]
const NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut", "Cleric",
	"Cryomancer", "Stormcaller", "Necromancer", "Swordsaint",
]


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	# Headless has no window and therefore no aspect; the stretch solve falls back to a
	# square viewport. The ult banner is positioned from `get_visible_rect()`, so give
	# it the real shape.
	root.size = Vector2i(1366, 768)
	await process_frame
	var worst_ult: int = 0
	var worst_any: int = 0
	var offenders: Dictionary = {}
	for pair: Array in PAIRS:
		var r: Dictionary = await _run(int(pair[0]), int(pair[1]))
		print("  %-26s max ult banners=%d  max titles=%d  frames w/ 2+ ults=%d" % [
			r["pair"], r["worst_ult"], r["worst_any"], r["doubled_frames"]])
		worst_ult = maxi(worst_ult, int(r["worst_ult"]))
		worst_any = maxi(worst_any, int(r["worst_any"]))
		for k: String in (r["names"] as Dictionary).keys():
			offenders[k] = maxi(int(offenders.get(k, 0)), int((r["names"] as Dictionary)[k]))
	print("")
	print("  WORST SIMULTANEOUS ULT BANNERS: %d   (1 is correct, 2+ is the bug)" % worst_ult)
	print("  WORST SIMULTANEOUS TITLES ANY KIND: %d" % worst_any)
	var dupes: Array[String] = []
	for k: String in offenders.keys():
		if int(offenders[k]) > 1:
			dupes.append("%s x%d" % [k, int(offenders[k])])
	print("  SAME NAME ON SCREEN TWICE: %s" % ("none" if dupes.is_empty() else ", ".join(dupes)))
	quit()


func _run(a: int, b: int) -> Dictionary:
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	script.set("class_a", a)
	script.set("class_b", b)
	script.set("auto_rematch", true)
	var m: Node = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(m)
	for i: int in SETTLE:
		await process_frame
	var worst_ult: int = 0
	var worst_any: int = 0
	var doubled: int = 0
	var names: Dictionary = {}
	for i: int in FRAMES:
		await process_frame
		var ults: int = 0
		for n: Node in root.get_tree().get_nodes_in_group(&"cast_ult_banner"):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				ults += 1
		# Every live title node, ult or heavy, and what each one says.
		var seen: Dictionary = {}
		var total: int = 0
		for n: Node in _all(root):
			if n is CastName and is_instance_valid(n) and not n.is_queued_for_deletion():
				total += 1
				var t: String = String(n.get("_text"))
				seen[t] = int(seen.get(t, 0)) + 1
		for t: String in seen.keys():
			names[t] = maxi(int(names.get(t, 0)), int(seen[t]))
		worst_ult = maxi(worst_ult, ults)
		worst_any = maxi(worst_any, total)
		if ults > 1:
			doubled += 1
	m.queue_free()
	await process_frame
	return {
		"pair": "%s v %s" % [NAMES[a], NAMES[b]],
		"worst_ult": worst_ult, "worst_any": worst_any,
		"doubled_frames": doubled, "names": names,
	}


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c: Node in n.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out
