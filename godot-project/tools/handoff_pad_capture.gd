# Render the two HUD gaps this task closed, so they can be LOOKED at instead of
# reasoned about. GUI binary only (a --headless run has a dummy renderer and saves a
# blank frame):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/handoff_pad_capture.gd
#
# Frame 1 — `user://handoff_pad_touch.png`: the mobile pad with a Tier 3 in hand.
#   * the CONTEXTUAL HANDOFF PAD in the centre dead band, naming the spell it would
#     give away (it does not exist at all in frame 3, which is the point of it);
#   * GOLD CHARGE PIPS on the ult pad — how many uses are left, visible BEFORE you
#     commit, which is the whole difference between a decision and a surprise.
# Frame 2 — `user://handoff_pad_desktop.png`: the same two counts on the desktop
#   hotbar, which is what a player without a touchscreen actually sees.
# Frame 3 — `user://handoff_pad_absent.png`: the teammate has walked out of range.
#   The pad is gone and the dead band is dead again — the negative case matters,
#   because a contextual affordance that never goes away is just a button.
extends SceneTree

const ARENA: String = "res://scenes/combat/VersusArena.tscn"
## Close enough for `SpellHandoff.RANGE` (74 px), and far enough that the two rigs
## are still separately readable in the frame.
const NEAR: float = 52.0
const FAR: float = 600.0

var _pad: TouchControls = null


func _initialize() -> void:
	var scene: Node = (load(ARENA) as PackedScene).instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for i: int in 90:
		await process_frame
	var heroes: Array = root.get_tree().get_nodes_in_group("hero")
	if heroes.size() < 2:
		print("handoff_pad_capture: need two heroes, got %d" % heroes.size())
		quit(1)
		return
	var local: Node2D = _local_hero(heroes)
	var mate: Node2D = _other(heroes, local)
	# Give the local player something worth handing over: a real Tier 3, with its real
	# charge count, so the pips below are the shipped number and not a prop.
	var tier3: Array = SpellLibrary.build_tier3()
	if not tier3.is_empty():
		SpellGrant.apply(local, tier3[0] as SpellDef)
	# The floor's handoff node is parked by FloorBuilder; VersusArena has no floor, so
	# stand one up here. Same class, same rules.
	var handoff := SpellHandoff.new()
	scene.add_child(handoff)
	_pad = TouchControls.new()
	_pad.force_visible = true
	root.add_child(_pad)

	mate.global_position = local.global_position + Vector2(NEAR, 0.0)
	await _settle()
	await _shot("handoff_pad_touch", "touch pad: contextual GIVE + charge pips")

	# Desktop read: the hotbar stands down while a pad is live, so the pad has to go
	# for this frame to be the thing a keyboard player sees.
	_pad.queue_free()
	_pad = null
	await _settle()
	await _shot("handoff_pad_desktop", "desktop hotbar: charge pips on the ult slot")

	# And the negative case.
	_pad = TouchControls.new()
	_pad.force_visible = true
	root.add_child(_pad)
	mate.global_position = local.global_position + Vector2(FAR, 0.0)
	await _settle()
	await _shot("handoff_pad_absent", "teammate out of range: no pad, dead band dead")
	quit(0)


## Which hero is the one at the keyboard — the same duck-typed test `SpellHandoff`
## uses, so the capture cannot frame a bot as the giver.
func _local_hero(heroes: Array) -> Node2D:
	for h: Node in heroes:
		# `get()` on a property that does not exist returns a NULL Variant, and
		# `bool(null)` is not a legal conversion — it aborts the enclosing function.
		# So the null is tested before the cast, not folded into it.
		var bot: Variant = h.get(&"bot_driven")
		if (bot == null or not bool(bot)) and h.get(&"_bot") == null:
			return h as Node2D
	return heroes[0] as Node2D


func _other(heroes: Array, not_this: Node2D) -> Node2D:
	for h: Node in heroes:
		if h != not_this:
			return h as Node2D
	return heroes[0] as Node2D


func _settle() -> void:
	for i: int in 20:
		await process_frame


func _shot(name: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("handoff_pad_capture: no frame for %s" % name)
		return
	var path: String = "user://%s.png" % name
	img.save_png(path)
	print("handoff_pad_capture: %s -> %s (%s)" % [
		name, ProjectSettings.globalize_path(path), what])
