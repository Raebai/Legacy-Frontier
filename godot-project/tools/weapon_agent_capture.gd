# Throwaway visual check for the spike rig's HELD WEAPONS (agent-owned; safe to
# delete). Modelled on tools/melee_agent_capture.gd. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/weapon_agent_capture.gd
#
# The melee is a DRAG, not a clip, so the only honest way to look at it is to
# actually drag the aim and watch what the springs do. Every weapon is rendered on
# BOTH FACINGS — a weapon that reads fine facing right and buries itself in the
# floor facing left is the classic mirrored-transform bug, and one facing proves
# nothing. Per weapon per facing:
#   context — the playground's OWN camera zoom, i.e. the size it is really played at
#   rest    — carried at the side, no input
#   drag1-3 — the cursor FLICKED across in ~0.12 s, then held while the arm catches
#             up and overshoots (the shots run past the end of the cursor move)
extends SceneTree

const WEAPONS: Array = ["", "sword", "dagger", "staff", "hammer", "greatsword"]
const FACINGS: Array = [[1.0, "r"], [-1.0, "l"]]
const DETAIL_ZOOM := 1.4
const CROP := Vector2i(680, 500)
## the aim sweeps across the body, mirrored per facing
const AIM_FROM := Vector2(-250.0, -170.0)
const AIM_TO := Vector2(300.0, 40.0)
const SWEEP := 14
const TAIL := 34
const SHOTS: Array = [8, 22, 44]


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	for kind: String in WEAPONS:
		var label: String = kind if kind != "" else "fists"
		for f: Array in FACINGS:
			var face: float = float(f[0])
			var tag: String = "%s_%s" % [label, String(f[1])]
			var scene: Node = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
			root.add_child(scene)
			for i in 10:
				await physics_frame               # let the playground build its figure
			scene.set_physics_process(false)      # we drive aim ourselves (no mouse)
			var fig: Node = scene.get("_fig")
			if fig == null:
				printerr("wepcap: no figure in the playground")
				quit(1)
				return
			fig.call("set_weapon", kind)
			var torso: Node2D = fig.get("_torso") as Node2D
			await _settle(fig, torso, 150, face, _aim(face, AIM_FROM))
			var cam: Camera2D = scene.get("_cam") as Camera2D
			await _save("wep_%s_context.png" % tag, cam, false)
			cam.zoom = Vector2(DETAIL_ZOOM, DETAIL_ZOOM)
			await _settle(fig, torso, 6, face, _aim(face, AIM_FROM))
			await _save("wep_%s_rest.png" % tag, cam, true)
			await _drag(fig, torso, cam, tag, face)
			scene.queue_free()
			await physics_frame
	quit(0)


## Mirror an aim offset for the facing under test.
func _aim(face: float, off: Vector2) -> Vector2:
	return Vector2(off.x * face, off.y)


## Hold the aim still for `n` frames with "use" released — the blade rests. Facing
## is pinned every frame so the rest pose under test is the one we asked for.
func _settle(fig: Node, torso: Node2D, n: int, face: float, aim_off: Vector2) -> void:
	fig.set("ctrl_weapon_drag", false)
	for i in n:
		fig.set("ctrl_aim", torso.global_position + aim_off)
		fig.set("_facing", face)          # pin the facing under test, not the aim's side
		await physics_frame


## Hold "use" and flick the aim across the body, then keep holding while the arm
## catches up. Unarmed, hold does nothing, so the fists run fires a single punch()
## instead — that is the comparison shot for "the bare-fist case is untouched".
func _drag(fig: Node, torso: Node2D, cam: Camera2D, tag: String, face: float) -> void:
	var armed: bool = String(fig.call("weapon")) != ""
	fig.set("ctrl_weapon_drag", armed)
	if not armed:
		fig.set("ctrl_aim", torso.global_position + _aim(face, AIM_TO))
		fig.call("punch")
	var shot := 0
	for i in SWEEP + TAIL:
		var t: float = clampf(float(i) / maxf(float(SWEEP - 1), 1.0), 0.0, 1.0)
		fig.set("ctrl_aim", torso.global_position + _aim(face, AIM_FROM).lerp(_aim(face, AIM_TO), t))
		await physics_frame
		while shot < SHOTS.size() and i >= int(SHOTS[shot]):
			await _save("wep_%s_drag%d.png" % [tag, shot + 1], cam, true)
			shot += 1
	fig.set("ctrl_weapon_drag", false)


func _save(fname: String, cam: Camera2D, crop: bool) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return
	if crop:
		# the camera tracks the torso, so the figure sits at the viewport centre
		var vp := Vector2i(root.size)
		var c := Vector2i(vp.x / 2, vp.y / 2 + int(20.0 * cam.zoom.y))
		var r := Rect2i(c - CROP / 2, CROP).intersection(Rect2i(Vector2i.ZERO, vp))
		img = img.get_region(r)
	img.save_png("user://" + fname)
	print("wepcap saved ", fname)
