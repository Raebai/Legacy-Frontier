# THE THREE-WAY LOOK TEST: does the game rig STAND and RAGDOLL like the spike?
#
# GUI binary — the headless one draws nothing and still reports success:
#   python python-tools/run_capture.py rig_vs_spike
#   ...or directly, with a tag:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/rig_vs_spike_capture.gd -- ++tag=before
#
# LEFT column  = CharacterRig (the game rig, drawn at the spike's own height so the
#                comparison is of PROPORTION and not of size — posture is a ratio and
#                slice_test_rig_posture pins that it is identical at 18/31/47/60 px).
# RIGHT column = SpikeFigure, real physics on a real floor. THE REFERENCE. The maker
#                signed this one off; it is the answer sheet, not a second opinion.
#
# Three rows, the three things the feel is judged on:
#   STAND  is he UPRIGHT with a hair of knee, or squatting?
#   WALK   both figures cross their own half at their own speed. Read the LEG POSE,
#          not the x position — they will not be at the same place and need not be.
#   HIT    a blow at step 150. Does the body go LOOSE and tumble, or do the hands
#          rattle while a rigid stick stands there? A still frame cannot show weight,
#          so this samples five beats across the flop — read them in order.
#
# ⚠ RENDERED THROUGH A SubViewport, NOT THE WINDOW. Saving `root.get_texture()` gives
# you whatever size the OS decided the window should be (measured: a requested 1280x720
# came back as a letterboxed 1366x768 with everything shifted), which silently crops a
# row off the bottom of a diagnostic render. A SubViewport is exactly the size asked
# for, so the layout arithmetic below is the layout on disk.
#
# ++tag=before / ++tag=after names the output, so the posture/ragdoll before-and-after
# is TWO RUNS OF ONE BINARY rather than a reconstruction of a remembered one. The spike
# column is byte-identical between the two runs, which is what anchors the comparison.
#   user://rigspike_<tag>_00.png .. _07.png
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const SPIKE_PATH: String = "res://scripts/spike/SpikeFigure.gd"
## WORLD size. The viewport is ZOOM times this: the spike's segment lengths are absolute
## pixels and its torso is a RigidBody2D, so it cannot be scaled by a node transform
## without distorting its physics. Zooming the CAMERA instead magnifies both columns
## identically and touches neither.
const W: int = 600
const H: int = 660
const ZOOM: float = 1.8
## The spike's own drawn height. The rig is drawn at the same number so the two
## silhouettes can be laid against each other directly.
const FIG_H: float = 84.0
## ⚠ ROWS ARE 220 px APART, WHICH IS MORE THAN THE LAYOUT NEEDS, AND THAT IS DELIBERATE.
## SpikeFigure's ride spring fires hard on its FIRST probed frame (`_last_floor_y` starts
## at 0, so the very first support term is computed against nothing) and MEASURED it
## launches the torso ~67 px upward before settling. At the 128 px spacing this file
## started with, two of the three spikes cleared the floor above them and came to rest on
## the wrong row — one row silently rendered with no reference figure in it at all.
const ROW_FLOOR: Array[float] = [160.0, 380.0, 600.0]
const ROW_LABEL: Array[String] = [
	"STAND  idle, settled",
	"WALK  crossing L to R (read the LEGS, not the x)",
	"HIT  blow from the left at step 150 + flop",
]
## Left edge of each column's half of the world.
const COL_X: Array[float] = [24.0, 350.0]
const HALF_W: float = 280.0
## Sampled beats: settled stand, two walk frames, then the flop at +2/+8/+16/+30/+50.
const SHOTS: Array[int] = [58, 80, 100, 152, 158, 166, 180, 200]
const HIT_STEP: int = 150
const RIG_SPEED: float = 210.0     # Hero.SPEED
const SPIKE_SPEED: float = 300.0   # SpikeFigure.move_speed default

var _tag: String = "after"
var _vp: SubViewport
var _rigs: Array[Node2D] = []      # [stand, walk, hit]
var _spikes: Array[Node2D] = []    # [stand, walk, hit]
var _shot: int = 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("++tag="):
			_tag = a.split("=")[1]
	# The shipped tick. The two spike hosts force 120; this deliberately does not, so
	# what is rendered is what the game runs.
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(int(W * ZOOM), int(H * ZOOM))

	_vp = SubViewport.new()
	_vp.size = Vector2i(int(W * ZOOM), int(H * ZOOM))
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	root.add_child(_vp)

	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.16)
	bg.size = Vector2(W * ZOOM, H * ZOOM)
	_vp.add_child(bg)
	# The magnifier. Set on the viewport's own canvas transform rather than with a
	# Camera2D: a camera added from `_initialize()` is not reliably in-tree when
	# make_current() is called (it errors and silently does nothing), and a diagnostic
	# render must not depend on that. World (0,0) maps to screen (0,0) at ZOOM, so the
	# layout arithmetic above is screen coordinates divided by ZOOM, exactly.
	_vp.canvas_transform = Transform2D().scaled(Vector2(ZOOM, ZOOM))

	# Labels are Control nodes: they live in the viewport's SCREEN space and are not
	# zoomed, so their positions are world * ZOOM by hand.
	_label("CharacterRig  (the game rig)  [%s]" % _tag, Vector2(20, 4), Color(0.62, 0.84, 1.0))
	_label("SpikeFigure  (the reference)", Vector2(COL_X[1] * ZOOM - 40.0, 4), Color(0.93, 0.62, 0.62))
	for r: int in 3:
		# Well clear of both columns' figures, in the dead space to the right of the rig.
		_label(ROW_LABEL[r], Vector2(190.0, (ROW_FLOOR[r] - 96.0) * ZOOM),
			Color(0.55, 0.6, 0.72))
		_floor(ROW_FLOOR[r])
		# Column 0: the game rig, standing with its drawn feet (local +height/2) on the
		# floor line. Left in the tree so its own _physics_process drives it and its
		# ground probe finds the real floor — i.e. exactly the in-game code path.
		var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
		rig.set("height", FIG_H)
		rig.set("limb_color", Color(0.62, 0.84, 1.0))
		# The WALK row starts at the left of its lane so it is still framed at the two
		# walk shots; the other two rows sit where they read best.
		var start_x: float = COL_X[0] + (10.0 if r == 1 else 40.0)
		rig.position = Vector2(start_x, ROW_FLOOR[r] - FIG_H * 0.5)
		_vp.add_child(rig)
		rig.call("set_grounded", true)
		rig.call("play", 0)   # State.IDLE
		_rigs.append(rig)
		# Column 1: the spike. Its node never moves; the RigidBody2D torso does.
		var fig: Node2D = (load(SPIKE_PATH) as GDScript).new() as Node2D
		fig.set("spawn_pos", Vector2(COL_X[1] + (0.0 if r == 1 else 40.0), ROW_FLOOR[r] - 62.0))
		fig.set("move_speed", SPIKE_SPEED)
		_vp.add_child(fig)
		_spikes.append(fig)
	_run()


func _label(text: String, at: Vector2, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override("font_color", col)
	_vp.add_child(l)


## A solid on physics layer 1 — CharacterRig.GROUND_MASK and SpikeFigure.WORLD_LAYER
## are both bit 1, so one floor serves both. Without a real collider the rig falls back
## to its own standing foot line and the spike has nothing to ride on at all.
func _floor(y: float) -> void:
	var b := StaticBody2D.new()
	b.position = Vector2(W * 0.5, y + 7.0)
	b.collision_layer = 1
	b.collision_mask = 0
	var c := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(W * 4.0, 14.0)
	c.shape = s
	b.add_child(c)
	_vp.add_child(b)
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-W, -7.0), Vector2(W, -7.0), Vector2(W, 7.0), Vector2(-W, 7.0)])
	p.color = Color(0.19, 0.22, 0.28)
	p.position = b.position
	_vp.add_child(p)


func _run() -> void:
	var dt: float = 1.0 / 60.0
	for step: int in 215:
		# --- row 1 STAND: nothing. Both figures simply hold their resting pose.
		# --- row 2 WALK: real travel, so the world-locked gait and the lean both see a
		#     genuine speed.
		#
		#     ⚠ NOTHING IS TELEPORTED BACK. An earlier version wrapped each figure to its
		#     lane's left edge to keep it framed, and it WRECKED the reference column:
		#     both rigs hold their foot plants in WORLD space, so moving the body without
		#     moving the plants stretches the legs out behind it — the spike rendered
		#     lying nearly flat, mid-walk, and looked like the broken one. The walk shots
		#     are taken early enough instead that both figures are still in their lane.
		if step >= 60:
			var rw: Node2D = _rigs[1]
			rw.position.x += RIG_SPEED * dt
			rw.call("set_body_velocity", Vector2(RIG_SPEED, 0.0))
			rw.call("set_facing", Vector2.RIGHT)
			rw.call("play", 1)   # State.RUN
			_spikes[1].set("ctrl_move_x", 1.0)

		# --- row 3 HIT: the blow both rigs already take from a knockback, at each one's
		#     own amplitude (they share no unit — see IMPULSE_TO_SPIN's note).
		if step == HIT_STEP:
			var rh: Node2D = _rigs[2]
			rh.call("play", 6)   # State.HURT
			rh.call("apply_impulse", Vector2(1.0, -0.25).normalized(), 900.0)
			rh.call("flop", 0.85, 0.45)
			rh.call("set_body_velocity", Vector2(320.0, 0.0))
			_spikes[2].call("hit", Vector2(1.0, -0.25).normalized(), 2400.0)

		await physics_frame
		if _shot < SHOTS.size() and step == SHOTS[_shot]:
			await RenderingServer.frame_post_draw
			var img: Image = _vp.get_texture().get_image()
			if img != null:
				var path: String = "user://rigspike_%s_%02d.png" % [_tag, _shot]
				img.save_png(path)
				print("rig_vs_spike: step %3d -> %s" % [step, ProjectSettings.globalize_path(path)])
			_shot += 1
	# Sanity line, not decoration: if a spike ever settles on the wrong row's floor
	# again (see the ⚠ on ROW_FLOOR) this is what says so without opening the PNG.
	for i: int in 3:
		var t: RigidBody2D = (_spikes[i].get("_parts") as Dictionary)["torso"]
		print("rig_vs_spike: row %d floor %.0f | rig y %.1f | spike torso y %.1f"
			% [i, ROW_FLOOR[i], _rigs[i].position.y, t.global_position.y])
	print("rig_vs_spike: done (tag=%s)" % _tag)
	quit(0)
