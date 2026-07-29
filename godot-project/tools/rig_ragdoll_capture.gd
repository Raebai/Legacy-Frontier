# THE RAGDOLL A/B — does the game rig now have the spike's WEIGHT?
#
# MUST run with the GUI (non-headless) binary; the dummy renderer saves black:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/rig_ragdoll_capture.gd
# Output: user://ragdoll_00.png .. user://ragdoll_06.png (one per sampled beat)
#
# Three motions, the exact three the feel keeps being judged on, each rendered TWICE
# side by side in the same frame:
#
#   row 1  LAND    — a real fall onto a floor. The whole question: do the knees buckle
#                    and the body sink over planted feet, then recover?
#   row 2  HIT     — a blow + flop. Does the BODY go loose and topple, or do only the
#                    hands rattle while a rigid stick stands there?
#   row 3  RUN/TURN— run right, stop, turn, run left. Does the body lean into travel
#                    and settle late, or does it stay bolt upright?
#
# LEFT column = body springs OFF, RIGHT column = ON. Both columns are the SAME script
# on the SAME code path, gated only by `CharacterRig.body_springs` — so this is a real
# comparison, not a reconstruction of what the old rig "would have" done.
#
# A still frame cannot show weight, so this deliberately samples a SEQUENCE. Read the
# frames in order: the landing beat lives across ragdoll_02..04, and a single frame of
# it proves nothing either way.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const W: int = 760
const H: int = 660
const FIG_H: float = 88.0        # ~3x the game rig, purely so the render is legible
const X_OFF: float = 250.0       # "springs OFF" column
const X_ON: float = 540.0        # "springs ON" column
## Floor y per row, and the row's label baseline.
const ROW_FLOOR: Array[float] = [200.0, 400.0, 610.0]
## Frames at which the viewport is saved. Chosen around the events below, not evenly:
## the landing beat is 3 frames long and needs three samples inside it.
const SHOTS: Array[int] = [0, 26, 30, 34, 40, 58, 96]

var _rigs: Array[CharacterRig] = []      # [land_off, land_on, hit_off, hit_on, run_off, run_on]
var _fall_v: Array[float] = [0.0, 0.0]
var _shot: int = 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	# ⚠ The project stretches a 640x360 BASE viewport up to the window. Every other
	# capture in tools/ either lives inside that 640x360 or silently gets cropped —
	# the first run of this one put two of the three rows off-screen. Disabling the
	# content scale makes coordinates 1:1 with pixels, which is what a diagnostic
	# render wants: this is a measuring instrument, not a screenshot of the game.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(W, H)
	root.content_scale_size = Vector2i(W, H)
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.16)
	bg.size = Vector2(W, H)
	root.add_child(bg)

	_label("BODY SPRINGS  OFF", Vector2(150, 6), Color(0.75, 0.55, 0.55))
	_label("BODY SPRINGS  ON  (the spike's torso)", Vector2(430, 6), Color(0.6, 0.9, 0.7))

	var rows: Array[String] = [
		"LAND   fall 780 px/s onto the floor",
		"HIT    blow from the left + flop",
		"RUN    right, stop, turn, run left",
	]
	for r: int in 3:
		_label(rows[r], Vector2(10, ROW_FLOOR[r] - 150.0), Color(0.55, 0.6, 0.72))
		_floor(Vector2(W * 0.5, ROW_FLOOR[r] + 22.0), Vector2(W - 40.0, 44.0))
		# Standing y puts the drawn FEET (local +height/2) exactly on the floor line.
		var stand: float = ROW_FLOOR[r] - FIG_H * 0.5
		var start_y: float = stand - 150.0 if r == 0 else stand
		_rigs.append(_make(Vector2(X_OFF, start_y), false))
		_rigs.append(_make(Vector2(X_ON, start_y), true))
	_run()


func _make(at: Vector2, springs: bool) -> CharacterRig:
	var rig: CharacterRig = (load(RIG_PATH) as GDScript).new() as CharacterRig
	rig.height = FIG_H
	rig.body_springs = springs
	rig.limb_color = Color(0.62, 0.84, 1.0) if springs else Color(0.86, 0.62, 0.62)
	rig.position = at
	root.add_child(rig)
	rig.set_grounded(true)
	rig.play(CharacterRig.State.IDLE)
	return rig


func _label(text: String, at: Vector2, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override("font_color", col)
	root.add_child(l)


## A solid on GROUND_MASK (physics layer 1) so CharacterRig's downward probe finds it —
## without a real collider the rig falls back to its own standing foot line and the
## landing being tested here would be measured against nothing.
func _floor(pos: Vector2, size: Vector2) -> void:
	var b := StaticBody2D.new()
	b.position = pos
	b.collision_layer = 1
	b.collision_mask = 0
	var c := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	root.add_child(b)
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5),
	])
	p.color = Color(0.19, 0.22, 0.28)
	p.position = pos
	root.add_child(p)


func _run() -> void:
	var dt: float = 1.0 / 60.0
	var stand0: float = ROW_FLOOR[0] - FIG_H * 0.5
	var run_x0: float = X_OFF
	for step: int in 130:
		# --- row 1: FALL then LAND. The rig derives impact speed from the node's own
		# world travel, so an honest fall is simply moving the node under gravity.
		for i: int in 2:
			var rig: CharacterRig = _rigs[i]
			if rig.position.y < stand0:
				_fall_v[i] = minf(_fall_v[i] + 1900.0 * dt, 780.0)
				rig.position.y = minf(rig.position.y + _fall_v[i] * dt, stand0)
				rig.set_grounded(false)
				rig.play(CharacterRig.State.AIR)
				rig.set_air_phase(false, false)
				rig.set_body_velocity(Vector2(0.0, _fall_v[i]))
			else:
				if _fall_v[i] != 0.0:
					_fall_v[i] = 0.0
					rig.set_air_phase(false, true)
				rig.set_grounded(true)
				rig.play(CharacterRig.State.IDLE)
				rig.set_body_velocity(Vector2.ZERO)

		# --- row 2: a BLOW at step 28 — impulse + flop, exactly what Hero/Enemy do on
		# a knockback. Then released at 70 so the recovery is visible too.
		if step == 28:
			for i: int in [2, 3]:
				_rigs[i].play(CharacterRig.State.HURT)
				_rigs[i].apply_impulse(Vector2(1.0, -0.25).normalized(), 900.0)
				_rigs[i].flop(0.85, 0.45)
				_rigs[i].set_body_velocity(Vector2(320.0, 0.0))
		if step == 70:
			for i: int in [2, 3]:
				_rigs[i].set_limp(0.0)
				_rigs[i].play(CharacterRig.State.IDLE)
				_rigs[i].set_body_velocity(Vector2.ZERO)

		# --- row 3: RUN right, STOP, TURN, RUN left. Travel is real node motion so the
		# world-locked gait and the lean both see a genuine speed.
		var rv: float = 0.0
		if step < 34:
			rv = 210.0
		elif step < 52:
			rv = 0.0
		elif step < 96:
			rv = -210.0
		for i: int in [4, 5]:
			var rig: CharacterRig = _rigs[i]
			rig.position.x += rv * dt
			rig.set_body_velocity(Vector2(rv, 0.0))
			if absf(rv) > 1.0:
				rig.set_facing(Vector2(rv, 0.0))
				rig.play(CharacterRig.State.RUN)
			else:
				rig.play(CharacterRig.State.IDLE)

		await physics_frame
		if _shot < SHOTS.size() and step == SHOTS[_shot]:
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			if img != null:
				var path: String = "user://ragdoll_%02d.png" % _shot
				img.save_png(path)
				print("ragdoll_capture: step %3d  ride(on)=%6.2f  pitch(on)=%6.3f  -> %s"
					% [step, _rigs[1].body_ride(), _rigs[3].body_pitch(),
						ProjectSettings.globalize_path(path)])
			_shot += 1
	# Keep run_x0 referenced so the row-3 start is documented in the log, not just the art.
	print("ragdoll_capture: done (row 3 started at x=%.0f)" % run_x0)
	quit(0)
