# STICKMAN LOOK capture — the "is it actually a stickman?" render.
#
# Draws the SAME figure four ways so the change can be judged rather than argued:
#   row 1  OLD proportions (head 0.18h / limb 0.16h) + clothing ON  = what shipped
#   row 2  NEW proportions (head 0.105h / limb 0.075h), plain       = the ask
#   row 3  NEW proportions, holding a sword / staff / hammer        = armed stickman
#   row 4  NEW proportions at the REAL in-game rig height (31 px)   = readability check
#
# The old row is produced by writing the OLD factors back onto the rig instance's
# drawn pose — there is no second copy of the rig to diff against, so the before
# shot has to be reconstructed. It is reconstructed through the same draw_figure
# the game calls, with only `w` and `r` swapped, so nothing else can drift.
#
# MUST run with the GUI (non-headless) binary — the dummy renderer saves black:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/stickman_look_capture.gd
# Output: user://stickman_look.png
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const BIG_H: float = 74.0    # display height — proportions are scale-free, this is just legibility
const GAME_H: float = 31.0    # the real CharacterRig.height default
const TINT: Color = Color(0.55, 0.75, 1.0)

var _rig_script: GDScript


func _initialize() -> void:
	_rig_script = load(RIG_PATH) as GDScript
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.14, 0.18)
	# ⚠ The project stretches a 640x360 BASE viewport up to the window, so every
	# coordinate here is in GAME pixels, not screen pixels. That is a feature for this
	# particular capture: it means the "31 px rig" row is rendered at exactly the size
	# the maker sees in play, upscaled by the same filter the game uses.
	bg.size = Vector2(640, 360)
	root.add_child(bg)

	# --- row 1: BEFORE (old fat proportions + the clothing that replaced body parts)
	_label("BEFORE  head 0.18h / limb 0.16h  + clothing", Vector2(8, 0))
	_old_figure(Vector2(60, 52), "", "")
	_old_figure(Vector2(170, 52), "", "sword")
	_old_figure(Vector2(290, 52), "hat", "staff")       # the mage preset: hat + robe + staff
	_old_figure(Vector2(410, 52), "helmet", "hammer")
	_old_figure(Vector2(540, 52), "hood", "")

	# --- row 2: AFTER (live rig, clothing off by default) — plain, then armed
	_label("AFTER  head 0.105h / limb 0.075h  ·  clothing off", Vector2(8, 96))
	_new_figure(Vector2(60, 150), "")
	_new_figure(Vector2(170, 150), "sword")
	_new_figure(Vector2(290, 150), "staff")
	_new_figure(Vector2(410, 150), "hammer")
	_new_figure(Vector2(540, 150), "scythe")

	# --- row 3: TRUE game size (31 px), 1:1 and magnified, to check it survives play
	_label("AFTER at the real rig height (31 px) — 1:1, then 2x and 4x", Vector2(8, 196))
	_new_figure(Vector2(30, 250), "", GAME_H)
	_new_figure(Vector2(60, 250), "sword", GAME_H)
	for z: int in [2, 4]:
		var zoom := Node2D.new()
		zoom.scale = Vector2(float(z), float(z))
		zoom.position = Vector2(120.0 if z == 2 else 300.0, 260.0)
		root.add_child(zoom)
		_new_figure(Vector2(0, 0), "", GAME_H, zoom)
		_new_figure(Vector2(30, 0), "sword", GAME_H, zoom)
	_run()


func _label(text: String, at: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	root.add_child(l)


## A live rig in its CURRENT (new) form. Clothing is suppressed by the static
## draw_clothing flag, so only the weapon slot is worth setting.
func _new_figure(at: Vector2, weapon: String, h: float = BIG_H, parent: Node = null) -> Node2D:
	var rig: Node2D = _rig_script.new()
	rig.set("height", h)
	(parent if parent != null else root).add_child(rig)
	rig.position = at
	rig.call("set_tint", TINT)
	if weapon != "":
		rig.call("set_equipment", "weapon", weapon)
	rig.call("play", 0)  # State.IDLE
	return rig


## The BEFORE shot: a plain Node2D that calls the shared static draw_figure with the
## OLD w/r substituted into a live pose, and clothing forced back on. Everything else
## — the IK, the keyline, the gear helpers — is the same code path the game runs.
func _old_figure(at: Vector2, head: String, weapon: String) -> void:
	var src: Node2D = _rig_script.new()
	src.set("height", BIG_H)
	root.add_child(src)
	src.position = Vector2(-5000, -5000)   # parked off-screen; only its pose is wanted
	src.call("play", 0)
	var node := OldLook.new()
	node.rig_script = _rig_script
	node.pose = src.call("_compute_pose")
	node.fig_height = BIG_H
	node.tint = TINT
	node.slots = {}
	if head != "":
		node.slots["head"] = head
		node.slots["body"] = "robe" if head == "hat" else "armor"
	if weapon != "":
		node.slots["weapon"] = weapon
	root.add_child(node)
	node.position = at


func _run() -> void:
	for i: int in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://stickman_look.png")
		print("stickman_look: saved ", ProjectSettings.globalize_path("user://stickman_look.png"))
	quit(0)


## Re-draws a captured pose at the OLD stroke metrics with clothing forced on.
class OldLook extends Node2D:
	var rig_script: GDScript
	var pose: Dictionary
	var fig_height: float = 150.0
	var tint: Color = Color.WHITE
	var slots: Dictionary = {}

	func _draw() -> void:
		var p: Dictionary = pose.duplicate()
		p["w"] = fig_height * 0.16    # the OLD LIMB_W_FACTOR
		p["r"] = fig_height * 0.18    # the OLD HEAD_R_FACTOR
		# The old head sat lower (head_center = -h/2 + r with the bigger r) — rebuild
		# it so the before shot is the real old silhouette, not the new skeleton
		# wearing a fat head.
		var head: Vector2 = p["head_center"]
		p["head_center"] = Vector2(head.x, -fig_height * 0.5 + p["r"])
		p["neck"] = (p["head_center"] as Vector2) + Vector2(0.0, p["r"])
		p["hand_lead_r"] = float(p["w"]) * 0.5
		p["hand_off_r"] = float(p["w"]) * 0.5
		p["foot_r"] = float(p["w"]) * 0.5
		var prev: bool = rig_script.get("draw_clothing")
		rig_script.set("draw_clothing", true)
		rig_script.call("draw_figure", self, p, tint, slots, fig_height,
			rig_script.get("OUTLINE_COLOR"))
		rig_script.set("draw_clothing", prev)
