# CIRCLE HAND-OFF capture (circle-agent-owned; named uniquely so parallel agents'
# capture scripts can't collide). GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/handoff_capture.gd
#
# WHY THIS EXISTS: the two-circles-per-cast bug is PURELY VISUAL — a headless
# suite can assert "one circle exists" all day and still not tell you whether the
# sigil BLINKED. So this drives one real beam cast in the maker's own playtest
# scene (SpellPlayground) and samples the frames AROUND the windup->release seam,
# which is exactly where the restart shows.
#
# The eight cells are placed RELATIVE to the windup length (not at fixed wall
# times) so the sheet brackets the hand-off no matter how the tier tuning moves:
#   [0][1] mid + end of windup   -> the CAST-side sigil, alive
#   [2][3] the two frames after release  -> where a blink-out would appear
#   [4][5][6][7] the beam charging + firing -> the MUZZLE sigil
# A correct hand-off = one continuous sigil across cells 1..5. The bug = cell 2/3
# empty-ish (circle 1 blooming away) then a fresh small circle popping in at 4.
#
# Output: user://handoff_sheet.png (4x2 contact sheet) + the raw cells alongside.
extends SceneTree

const OUT: String = "user://handoff_sheet.png"
const CELL: Vector2i = Vector2i(420, 236)
const COLS: int = 4
const ROWS: int = 3
## Camera zoom for the capture. The seam is a ~90 px sigil on a 1280 px frame at
## the playground's default framing — far too small to judge a blink. Pushed in
## hard because this sheet exists to answer one question: does the sigil restart?
const CAPTURE_ZOOM: float = 2.6
## Mirror of SpellPlaygroundController._TIER_WINDUP. Duplicated rather than read
## off the scene because a script-level const is not reachable through a Node
## reference in GDScript, and this harness must not edit the controller.
const TIER_WINDUP: Dictionary = {0: 0.35, 1: 1.0, 2: 1.9}
## Where the mouse is parked, in WINDOW pixels — the playground re-reads the aim
## at release, so an unparked (0,0) cursor would aim the shot up-and-left out of
## frame and hide the muzzle sigil behind the camera edge.
const AIM_WINDOW_POS: Vector2 = Vector2(1180.0, 380.0)
## How far above the caster the windup sigil hangs in --seam mode. Mirrors
## Hero.CAST_CIRCLE_ABOVE's intent (the maker's "the circle should sit ABOVE the
## caster" ask), exaggerated here so the TRAVEL down to the muzzle is legible in
## a contact sheet rather than a 24 px nudge.
const SEAM_CIRCLE_ABOVE: float = 110.0

var _scene: Node
var _sheet: Image = null


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_sheet = Image.create(CELL.x * COLS, CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.02, 0.02, 0.04, 1.0))
	_run()


func _run() -> void:
	for _i: int in 90:
		await physics_frame          # let the ragdoll settle onto the floor
	var hud: Label = _scene.get("_hud")
	if hud != null:
		hud.visible = false          # clean frames — the sigil is the subject
	var bar: Node = _scene.get("_bar")
	if bar is CanvasItem:
		(bar as CanvasItem).visible = false
	Input.warp_mouse(AIM_WINDOW_POS)
	for _i: int in 4:
		await physics_frame          # let the warped cursor register

	# Pick the first BEAM in the library — BeamSpell is the reference spectacle
	# for the seam, and its long CHARGE_TIME makes the muzzle sigil unmissable.
	var spells: Array = _scene.get("_spells")
	var idx: int = _first_beam(spells)
	if idx < 0:
		printerr("handoff_capture: no BEAM spell in the library")
		quit(1)
		return
	_scene.set("_sidx", idx)
	var spell: SpellDef = spells[idx]
	spell.length = 700.0             # runtime-only framing tweak; keeps the tip in shot
	var windup: float = CastStyle.duration(CastStyle.for_spell(spell.kind)) \
		* float(TIER_WINDUP[SpellTier.of(spell)])
	print("handoff_capture: spell=", spell.display_name, " windup=", windup)

	var cam: Camera2D = _scene.get("_cam")
	if cam != null:
		cam.zoom = Vector2(CAPTURE_ZOOM, CAPTURE_ZOOM)
		# Frame the WHOLE ritual, not just the fighter: in --seam mode the sigil
		# starts a long way over the caster's head and travels down, so a camera
		# centred on the torso crops off the half of the shot that matters.
		if _seam_mode():
			cam.offset = Vector2(0.0, -SEAM_CIRCLE_ABOVE * 0.75)

	# Sample times, in seconds from the press. Relative to `windup` so the seam is
	# always bracketed no matter how tier tuning moves; the first two cells are the
	# cast sigil at full strength, then every other FRAME across the release, then
	# the beam's own CHARGE_TIME (0.34) out to the discharge.
	var marks: Array[float] = [
		windup * 0.55,
		windup - 0.02,
		windup + 0.02,
		windup + 0.05,
		windup + 0.09,
		windup + 0.13,
		windup + 0.18,
		windup + 0.24,
		windup + 0.30,
		windup + 0.35,
		windup + 0.42,
		windup + 0.55,
	]
	if _seam_mode():
		_cast_with_handoff(spell, windup)
	else:
		_scene.call("_cast")         # coroutine — returns immediately, runs on the tree
	var elapsed: float = 0.0
	var step: float = 1.0 / 60.0
	for cell: int in marks.size():
		while elapsed < marks[cell]:
			await physics_frame
			elapsed += step
		print("  cell %d  t=%.3f  circles=%s" % [cell, elapsed, _census(_scene)])
		await _grab(cell)
	print("handoff_capture: live circles at end = ", _census(_scene))
	var out: String = OUT.replace(".png", "_seam.png") if _seam_mode() else OUT
	var err: int = _sheet.save_png(out)
	if err == OK:
		print("handoff_capture: saved ", ProjectSettings.globalize_path(out))
	else:
		printerr("handoff_capture: save failed err=", err)
	quit(0)


## `--seam` on the command line switches from reproducing the BUG (the
## playground's own two-spawner _cast) to reproducing the FIX.
func _seam_mode() -> bool:
	return OS.get_cmdline_args().has("--seam")


## THE ROUTED CASTER EDIT, executed from outside the file. SpellPlaygroundController
## and Hero are owned by other agents this session, so this harness performs the
## caster half of the hand-off itself — verbatim the two lines those files need:
## a windup sigil that hangs ABOVE the caster, then MagicCircle.offer() at the
## moment of release instead of vanish(). Everything downstream (adopt_or_open,
## the travel, the fold, BeamSpell) is the real shipped code path.
func _cast_with_handoff(spell: SpellDef, windup: float) -> void:
	var fig: Node = _scene.get("_fig")
	var torso: Node2D = fig.get("_torso")
	var origin: Vector2 = torso.global_position
	var target: Vector2 = _scene.get_global_mouse_position()
	var aim: Vector2 = (target - origin).normalized()
	fig.call("cast", aim, CastStyle.for_spell(spell.kind))
	# The windup sigil, hung OVER the caster's head — the ritual gathering before
	# it descends into the hand.
	var circle: MagicCircle = MagicCircle.new()
	_scene.add_child(circle)
	circle.global_position = origin + Vector2(0.0, -SEAM_CIRCLE_ABOVE)
	circle.appear(Color(0.62, 0.42, 1.0), 86.0, maxf(windup * 0.7, 0.08))
	circle.set_orientation(true, aim, 0.22)
	await create_timer(windup).timeout  # SceneTree's own timer — no get_tree() here
	if not is_instance_valid(fig) or not is_instance_valid(circle):
		return
	# >>> THE ONE LINE. Was: circle.vanish(0.14)
	MagicCircle.offer(circle, fig)
	var release_origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	SpellCaster.cast(spell, _scene, release_origin, _scene.get_global_mouse_position(),
		Color(0.78, 0.84, 1.0), "", fig)


## Every live MagicCircle under `n`, as "parentName@x,y". The contact sheet is the
## real verdict, but this census is the unambiguous corroborating signal: the two
## sigils in this bug can happen to be the SAME SIZE and 46 px apart, which the eye
## reads as one circle jittering. The census cannot be fooled — it names the count
## AND the owner, so "the caster's circle died and the beam built its own" is
## visible as a parent change from the arena to the BeamSpell node.
func _census(n: Node) -> Array[String]:
	var out: Array[String] = []
	if n is MagicCircle:
		var p: Node = n.get_parent()
		out.append("%s@%.0f,%.0f" % [
			p.name if p != null else "?",
			(n as Node2D).global_position.x, (n as Node2D).global_position.y,
		])
	for c: Node in n.get_children():
		out.append_array(_census(c))
	return out


func _first_beam(spells: Array) -> int:
	for i: int in spells.size():
		if int((spells[i] as SpellDef).kind) == int(SpellDef.Kind.BEAM):
			return i
	return -1


func _grab(cell: int) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.save_png("user://handoff_%scell_%d.png" % ["seam_" if _seam_mode() else "", cell])
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL),
		Vector2i((cell % COLS) * CELL.x, (cell / COLS) * CELL.y))
