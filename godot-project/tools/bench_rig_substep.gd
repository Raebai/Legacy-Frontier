# Run: godot --headless --path godot-project --script tools/bench_rig_substep.gd
#   optional: ++rigs=25 ++frames=600
#
# HOW MUCH DOES THE RIG'S SUB-STEPPING ACTUALLY COST? `CharacterRig` runs two
# springs at 1/480 s off `_physics_process`, i.e. EIGHT sub-steps per body per
# physics frame at 60 Hz, and at the 25-entity ceiling that looks like a lot of
# integration. Before touching a hand-tuned spring it is worth knowing whether it
# is 20% of the frame or 2%.
#
# Measures `advance()` directly on real CharacterRig nodes rather than inferring
# from a whole-crowd ablation, because a crowd ablation also removes the gait, the
# limb sim, the ground probe and the redraw, and cannot separate them.
#
# THREE STATES, because the answer differs per state and that difference is the
# whole optimisation:
#   REST     — grounded, standing still. Both springs sit at their rest point, so
#              every one of the 8 sub-steps integrates a zero derivative.
#   LANDING  — a real touchdown impulse in `_ride_vel`. This is what the
#              sub-stepping EXISTS for and must never be cheapened.
#   WALKING  — gait driving the pitch lean. The common case in a live fight.
#
# `body_springs` is the rig's own kill switch (it zeroes and returns before both
# loops), so springs-on minus springs-off is the cost of `_step_body` itself.
#
# ⚠ Dummy renderer: `_draw` never runs headless, so the rig's DRAWING cost — which
# on a phone is a procedural stick figure's worth of draw commands per body per
# frame — is NOT in these numbers and may well exceed the integration entirely.
# This measures the integration budget, which is the only part on the table.
extends SceneTree

const RIG_HEIGHT: float = 31.0

var _rigs: int = 25
var _frames: int = 600
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_parse_args()
	print("[bench] rigs=%d frames=%d  (60 Hz frame budget: 16.67 ms)" % [_rigs, _frames])
	print("[bench] %-10s %10s %10s %10s %9s" %
		["state", "springs", "no-springs", "delta ms", "per rig us"])
	for state: String in ["rest", "landing", "walking"]:
		var on: float = _run(state, true)
		var off: float = _run(state, false)
		var d: float = on - off
		print("[bench] %-10s %9.3f %10.3f %10.3f %9.2f"
			% [state, on, off, d, d * 1000.0 / float(_rigs)])
	print("[bench] `delta ms` is _step_body (BOTH springs, all %d rigs) per frame." % _rigs)
	print("[bench] REMINDER: dummy renderer — no _draw cost is in any of this.")
	quit(0)
	return true


## Total ms per simulated frame for `_rigs` rigs in `state`, averaged over the run.
func _run(state: String, springs: bool) -> float:
	var built: Array[CharacterRig] = []
	var host := Node2D.new()
	root.add_child(host)
	for i: int in _rigs:
		var rig := CharacterRig.new()
		rig.height = RIG_HEIGHT
		rig.body_springs = springs
		host.add_child(rig)
		rig.position = Vector2(float(i) * 40.0, 0.0)
		built.append(rig)
	# Settle first: a rig's first frames are dominated by _ready-time work and by
	# the springs finding their rest, neither of which recurs.
	for f: int in 30:
		for rig: CharacterRig in built:
			rig.advance(1.0 / 60.0)
	var t0: int = Time.get_ticks_usec()
	for f: int in _frames:
		for rig: CharacterRig in built:
			_drive(rig, state, f)
			rig.advance(1.0 / 60.0)
	var elapsed: int = Time.get_ticks_usec() - t0
	host.free()
	return float(elapsed) / float(_frames) / 1000.0


## Put a rig into the state under test for this frame.
func _drive(rig: CharacterRig, state: String, f: int) -> void:
	match state:
		"rest":
			pass   # grounded, still, both springs at rest
		"landing":
			# Re-kick the ride spring periodically so the run is mostly ringing
			# rather than mostly settled. The magnitude is a real touchdown's:
			# `_ride_vel += impact * LAND_ABSORB * _body_scale()` with impact near
			# LAND_FALL_FULL.
			if f % 40 == 0:
				rig.set(&"_ride_vel", 700.0)
		"walking":
			# Gait speed drives the pitch lean target, so the pitch spring is
			# genuinely chasing something every frame — the common live-fight case.
			rig.set_body_velocity(Vector2(sin(float(f) * 0.05) * 210.0, 0.0))


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_user_args())
	argv.append_array(OS.get_cmdline_args())
	for raw: String in argv:
		var a: String = raw.lstrip("+-")
		if not a.contains("="):
			continue
		var k: String = a.get_slice("=", 0)
		var v: String = a.get_slice("=", 1)
		match k:
			"rigs":
				_rigs = clampi(int(v), 1, 400)
			"frames":
				_frames = clampi(int(v), 30, 20000)
