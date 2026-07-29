# Visual verification for HOLLOW PURPLE — the four beats, rendered (agent-owned;
# safe to delete). Modelled on tools/melee_agent_capture.gd. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/hollow_purple_capture.gd
#
# ⚠ WHAT THIS FILE USED TO GET WRONG, AND WHY NOTHING RENDERED.
# It staged two beams from two SEPARATE left-hand origins and never assigned
# `caster_node` on either. Both hollow_purple rows in ReactionTable carry a
# `require_owner` predicate — "same" at priority 100, "different" at 95 — and
# SpellReactor._owner_relation reports "unowned" when either side has no caster.
# "unowned" satisfies NEITHER predicate, so the pair matched no rule, no
# HollowPurple was ever constructed, and every symptom followed from that: no
# magic-circle gate, no discharge, no output from a print inside `_process`, and
# no error anywhere, because nothing had gone wrong. The beams simply crossed.
#
# So this now stages the HEADLINE path instead: the SELF-COMBO. ONE caster
# double-taps two opposing-element beams from the same muzzle inside the combo
# window, they are absorbed into a gate a fixed distance in FRONT of them, and
# the annihilation fires back out along their aim. A final short run keeps the
# rarer two-caster crossing (priority 95) on camera as well, because that row
# stages at the geometric crossing instead and should look different.
#
# Beats are counted from the fusion ITSELF, not from the cast: the tool waits on
# SpellReactor's `reaction_fired` signal and counts physics frames after it. The
# old hand-computed "charge ends at 41, so the circle opens at ~45" arithmetic
# silently drifts the moment a timing constant moves, and a capture whose frame
# numbers have drifted looks exactly like a spectacle that is broken.
#
# Hit-stop is disabled for the run so the beat timeline maps cleanly onto frame
# counts; everything else is the real spectacle.
extends SceneTree

const BEAM := "res://scripts/combat/BeamSpell.gd"
const FLOOR_Y := 300.0

## The caster's muzzle, and the two aims of the double-tap. Both beams leave the
## SAME point — that is what makes this a self-combo and why the fusion cannot
## stage at a "crossing": there isn't one. The angles differ by ~18 degrees so
## the two absorbed beams are visibly distinct as they wind into the gate.
const MUZZLE := Vector2(-620.0, 40.0)
const AIM_FIRST := Vector2(1.0, -0.16)
const AIM_SECOND := Vector2(1.0, 0.10)
## Physics frames between the two casts. BeamSpell is reactable for
## CHARGE + FIRE + FADE = 0.82 s and inert for the first 0.34 s of that, so the
## window in which two casts are BOTH live is ~0.48 s; 18 frames at 120 Hz is
## 0.15 s, a believable double-tap sitting comfortably inside it.
const DOUBLE_TAP_GAP := 18

## Where the two SEPARATE casters stand for the contrast run, and the point they
## both shoot at, so their beams genuinely cross out in the open.
const CROSS_POINT := Vector2(0.0, 60.0)
const CROSS_ORIGIN_LOW := Vector2(-520.0, 320.0)
const CROSS_ORIGIN_HIGH := Vector2(-520.0, -200.0)

## [label, element A, element B, two_casters, [[physics frame AFTER the fusion
## begins, stage name], ...]].
##
## Beat boundaries at 120 Hz: INTAKE 0-72, HELD 72-94, DISCHARGE 94-204. The
## intake's own FAR_EATEN_AT (0.42) puts the switch from "swallowing the
## overshoot" to "winding in from the muzzle" at frame ~30.
const RUNS: Array = [
	["fireice", Elements.Element.FIRE, Elements.Element.ICE, false, [
		[2, "1_gate_opens"],
		[16, "2_far_eaten"],
		[34, "3_vortex"],
		[52, "4_wound_in"],
		[68, "5_swallowed"],
		[80, "6_held"],
		[98, "7_discharge"],
		[112, "8_lance"],
		[150, "9_ring"],
		[196, "10_aftermath"],
	]],
	# A different opposing pair = a different computed purple, from the same row.
	["shadowholy", Elements.Element.SHADOW, Elements.Element.HOLY, false, [
		[34, "3_vortex"],
		[80, "6_held"],
		[112, "8_lance"],
	]],
	["arcanewind", Elements.Element.ARCANE, Elements.Element.WIND, false, [
		[34, "3_vortex"],
		[112, "8_lance"],
	]],
	# THE OTHER ROW. Two casters, so the fusion stages at the geometric crossing
	# and fires along the bisector — deliberately framed the same way, so the
	# difference from the self-combo is the only thing that changes.
	["crosscaster", Elements.Element.FIRE, Elements.Element.ICE, true, [
		[34, "3_vortex"],
		[112, "8_lance"],
	]],
]

## Where to point the camera and how wide to open it.
##
## ⚠ THE PROJECT STRETCHES. `project.godot` renders at a small base viewport and
## the 1280x720 window scales it up ~2x, so the world-to-pixel factor is TWICE
## the Camera2D zoom. Framing computed as if `zoom` were the whole story shows
## about half the world you expect — which is how an earlier pass put the gate
## hard against the left edge with the lance's tail cut off.
##
## The composition has to hold the WHOLE discharge: the lance runs one beam-length
## (1100 px) forward of the gate and 0.42 of that behind it, so from tail to tip
## is ~1560 px of world. At zoom 0.38 that is 1560 * 0.76 = ~1190 px of screen,
## inside a 1280-wide frame with a little air at each end.
const CAM_AT := Vector2(-100.0, 110.0)
const CAM_ZOOM := 0.38

var _scene: Node2D = null
var _cam: Camera2D = null
var _fused: bool = false


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await physics_frame  # the tree has to be live before /root lookups work
	# Hit-stop would stretch the beat timeline against the frame counter; the
	# spectacle itself is untouched.
	var tuning: Node = root.get_node_or_null(^"/root/Tuning")
	if tuning != null and tuning.get(&"cfg") != null:
		tuning.cfg.set(&"hit_stop_enabled", false)
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("hpcap: SpellReactor autoload missing — nothing can fuse")
		quit(1)
		return
	reactor.connect(&"reaction_fired", _on_reaction_fired)
	for entry: Array in RUNS:
		await _capture_run(entry)
	quit(0)


func _on_reaction_fired(outcome: String, point: Vector2, _a: Node, _b: Node) -> void:
	if outcome == "hollow_purple":
		_fused = true
		print("hpcap fusion staged at ", point)


func _capture_run(entry: Array) -> void:
	var label: String = entry[0]
	var ea: int = entry[1]
	var eb: int = entry[2]
	var two_casters: bool = entry[3]
	var stages: Array = entry[4]
	_scene = _build_arena()
	root.add_child(_scene)
	_cam.make_current()  # only legal once the camera is actually in the tree
	for i in 20:
		await physics_frame
	_fused = false
	if two_casters:
		var west: Node2D = _caster("West")
		var east: Node2D = _caster("East")
		_fire(west, CROSS_ORIGIN_LOW, CROSS_POINT - CROSS_ORIGIN_LOW, ea)
		_fire(east, CROSS_ORIGIN_HIGH, CROSS_POINT - CROSS_ORIGIN_HIGH, eb)
	else:
		# ONE caster node, handed to BOTH beams — this single shared reference is
		# the entire difference between a fusion and two beams that ignore each
		# other. It is an identity token for the reaction layer, nothing more.
		var caster: Node2D = _caster("Caster")
		_fire(caster, MUZZLE, AIM_FIRST, ea)
		for i in DOUBLE_TAP_GAP:
			await physics_frame
		await _save("hp_%s_0_double_tap.png" % label)
		_fire(caster, MUZZLE, AIM_SECOND, eb)
	# Wait for the fusion rather than assuming which frame it lands on. The cap
	# is generous but finite: a run that never fuses must fail LOUDLY here rather
	# than quietly writing a folder of pictures of two ordinary beams.
	var waited: int = 0
	while not _fused and waited < 300:
		await physics_frame
		waited += 1
	if not _fused:
		printerr("hpcap: %s NEVER FUSED — no HollowPurple was staged" % label)
		_scene.queue_free()
		await physics_frame
		return
	var done: int = 0
	for stage: Array in stages:
		while done < int(stage[0]):
			await physics_frame
			done += 1
		await _save("hp_%s_%s.png" % [label, stage[1]])
	_scene.queue_free()
	# The fusion holds SpellReactor's global one-shot slot until it leaves the
	# tree; the next run cannot stage anything until that has actually happened.
	for i in 4:
		await physics_frame


## A bare arena: the bloom pass, the screen grade, a floor and a few blocks for
## scale, and a static camera parked between the caster and the lance's reach.
##
## Deliberately NOT the SpellPlayground — that scene pulls in scripts/spike,
## which another agent is editing, and a capture tool that cannot render because
## somebody else's file is mid-edit is a capture tool that stops being used.
## Everything the spectacle actually needs (glow + post-process) is set up here.
func _build_arena() -> Node2D:
	RenderingServer.set_default_clear_color(Color(0.13, 0.14, 0.18))
	var arena := Node2D.new()
	Atmosphere.add_glow(arena)     # 2D bloom, so the HDR cores actually radiate
	PostProcess.add(arena)         # the reactive grade, so the shock ripple shows
	_rect(arena, Vector2(0.0, FLOOR_Y + 60.0), Vector2(2400.0, 120.0), Color(0.20, 0.22, 0.27))
	for x: float in [-420.0, -140.0, 180.0, 470.0]:
		_rect(arena, Vector2(x, FLOOR_Y - 34.0), Vector2(68.0, 68.0), Color(0.26, 0.28, 0.34))
	# Centred between the muzzle and the lance's far reach, not on the gate: the
	# whole silhouette has to be in shot for the payoff frames to mean anything.
	_cam = Camera2D.new()
	_cam.position = CAM_AT
	_cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	arena.add_child(_cam)
	return arena


## A stand-in caster. The reaction layer only ever compares this node by
## IDENTITY (SpellReactor._owner_relation is an `==`), so a bare Node2D is a
## complete caster as far as the fusion is concerned.
func _caster(node_name: String) -> Node2D:
	var c := Node2D.new()
	c.name = node_name
	_scene.add_child(c)
	return c


func _rect(parent: Node, at: Vector2, size: Vector2, col: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	p.color = col
	p.position = at
	p.z_index = -5
	parent.add_child(p)


func _fire(caster: Node, origin: Vector2, dir: Vector2, element: int) -> void:
	var beam: Node2D = (load(BEAM) as GDScript).new()
	_scene.add_child(beam)
	beam.set("element_id", element)
	# THE LINE WHOSE ABSENCE BROKE THIS TOOL. Without an owner the pair is
	# "unowned" and matches no hollow_purple row at all.
	beam.set("caster_node", caster)
	beam.call("fire", origin, dir.normalized(), Elements.color(element),
		1100.0, 30.0, 46, Elements.effect_name(element))


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("hpcap saved ", fname)
