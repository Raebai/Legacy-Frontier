extends SceneTree
## WHICH SPELLS CAST WITHOUT THE FIGURE VISIBLY CASTING?
##
## Maker: *"sometimes some of the spell casts werent showing with the stick figure"*.
## The spell arrives, but nothing about the body says it threw one.
##
## Two channels carry that read, and they are opened from different places:
##   * the WINDUP SIGIL — `Hero._open_cast_sigil`, called from the summon ceremony and
##     the float-channel and nowhere else. A cast that takes neither route has no ring.
##   * the RIG GESTURE — `CharacterRig.cast_gesture`, the arms actually committing.
##
## So for every spell cast in a real bout this records whether a `MagicCircle` existed
## on the caster within a short window either side. A spell that scores 0 of N is one
## the figure never visibly casts.
##
## ⚠ THE GESTURE CANNOT BE SAMPLED AT THE CAST. `spell_cast` emits at RELEASE, and
## `cast_gesture` plays during the WINDUP that precedes it — a 0.2 s gesture is
## routinely over by the time the spell exists. A first version sampled
## `_gesture_active` on the signal and reported "NO ARM GESTURE" for two thirds of the
## library; the flagged set was just the spells with SHORT windups, which is a
## measurement of windup length wearing the costume of a bug. Gestures are counted as
## EDGES over every frame instead, and compared against the cast count for the bout.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_cast_visuals.gd

const MATCH_SCENE := "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT := "res://scripts/combat/BotMatch.gd"
const SETTLE: int = 120
const FRAMES: int = 5400
## Frames after the cast in which a sigil still counts as belonging to it.
const WINDOW: int = 30
const PAIRS: Array[Array] = [[6, 8], [3, 6], [0, 1], [5, 2], [7, 4]]

var _pending: Array[Dictionary] = []
var _tally: Dictionary = {}
var _frame: int = 0


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	root.size = Vector2i(1366, 768)
	await process_frame
	for pair: Array in PAIRS:
		await _run(int(pair[0]), int(pair[1]))
	print("")
	print("=== DID THE FIGURE VISIBLY CAST? ==========================================")
	print("  spell                        casts   sigil   gesture   cast-pose")
	var keys: Array = _tally.keys()
	keys.sort()
	var silent: Array[String] = []
	for k: String in keys:
		var row: Dictionary = _tally[k]
		var n: int = int(row["n"])
		var seen: int = int(row["seen"])
		var flag: String = ""
		if seen == 0:
			flag = "   *** NEVER ***"
			silent.append(k)
		elif seen < n:
			flag = "   (sometimes)"
		var g: int = int(row.get("gest", 0))
		var cp: int = int(row.get("castpose", 0))
		if g == 0:
			flag += "   <-- NO ARM GESTURE"
		print("  %-28s %5d   %5d   %5d     %5d%s" % [k, n, seen, g, cp, flag])
	print("")
	print("  SPELLS THAT NEVER SHOW A SIGIL: %s" % ("none" if silent.is_empty() else ", ".join(silent)))
	quit()


func _on_cast(id: String, _is_ult: bool, who: Node2D) -> void:
	# ⚠ ALSO SAMPLE THE RIG. The sigil is one channel; the ARMS are the other, and a
	# body can open a ring while standing like it is waiting for a bus. `_gesture_active`
	# is set by `CharacterRig.cast_gesture` and is the honest read of "did the figure
	# actually commit to a cast", where `state == CAST` can also come from elsewhere.
	var gest: bool = false
	var st: int = -1
	var rig: Node = who.get_node_or_null("CharacterRig") if is_instance_valid(who) else null
	if rig == null and is_instance_valid(who):
		for c: Node in who.get_children():
			if c is CharacterRig:
				rig = c
				break
	if rig != null:
		gest = bool(rig.get("_gesture_active"))
		st = int(rig.get("state"))
	if not _tally.has(id):
		_tally[id] = {"n": 0, "seen": 0, "gest": 0, "castpose": 0}
	var row: Dictionary = _tally[id]
	row["n"] = int(row["n"]) + 1
	row["gest"] = int(row.get("gest", 0)) + (1 if gest else 0)
	row["castpose"] = int(row.get("castpose", 0)) + (1 if st == CharacterRig.State.CAST else 0)
	_pending.append({"id": id, "who": who, "until": _frame + WINDOW, "seen": false})


func _run(a: int, b: int) -> void:
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	script.set("class_a", a)
	script.set("class_b", b)
	script.set("auto_rematch", false)
	var m: Node = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(m)
	for i: int in SETTLE:
		await process_frame
	for n: Node in root.get_tree().get_nodes_in_group(&"hero"):
		if n.has_signal("spell_cast"):
			var body: Node2D = n as Node2D
			n.connect("spell_cast", func(id: String, u: bool) -> void: _on_cast(id, u, body))
	var was: Dictionary = {}
	var edges: int = 0
	var casts_before: int = _total_casts()
	for i: int in FRAMES:
		await process_frame
		_frame += 1
		for h: Node in root.get_tree().get_nodes_in_group(&"hero"):
			var rg: Node = null
			for c: Node in h.get_children():
				if c is CharacterRig:
					rg = c
					break
			if rg == null:
				continue
			var now: bool = bool(rg.get("_gesture_active"))
			var id2: int = h.get_instance_id()
			if now and not bool(was.get(id2, false)):
				edges += 1
			was[id2] = now
		if _pending.is_empty():
			continue
		# A sigil is a MagicCircle parented into the arena near the caster.
		var live: Array[Vector2] = []
		for c: Node in _circles(root):
			live.append((c as Node2D).global_position)
		var keep: Array[Dictionary] = []
		for e: Dictionary in _pending:
			if not bool(e["seen"]):
				var who: Node2D = e["who"]
				if is_instance_valid(who):
					for q: Vector2 in live:
						if q.distance_to(who.global_position) < 140.0:
							e["seen"] = true
							(_tally[e["id"]] as Dictionary)["seen"] = \
								int((_tally[e["id"]] as Dictionary)["seen"]) + 1
							break
			if _frame < int(e["until"]) and not bool(e["seen"]):
				keep.append(e)
		_pending = keep
	print("  bout: %d casts, %d cast-gesture activations" % [
		_total_casts() - casts_before, edges])
	_pending.clear()
	m.queue_free()
	await process_frame


func _total_casts() -> int:
	var t: int = 0
	for k: String in _tally.keys():
		t += int((_tally[k] as Dictionary)["n"])
	return t


func _circles(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c: Node in n.get_children():
		if c is MagicCircle:
			out.append(c)
		out.append_array(_circles(c))
	return out
