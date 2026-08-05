# READ-ONLY PROBE (safe to delete). GUI BINARY ONLY — no --headless.
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_timestop_arena.gd
#
# THE TIME-STOP BUBBLE OVER THE REAL ARENA, WHICH IS THE CASE THAT WAS NEVER SHOT.
# `_probe_timestop.gd` stages the spell over a hand-built dark scene, so the negative
# inside the ring reads BRIGHT WHITE and looks spectacular. The shipping arena has a
# PALE sky, and a negative of pale is DARK — the same shader, the opposite picture.
# The handoff says this in as many words and flags the probe image as "not the look
# you will get". This probe gets the look you will get.
#
# It also MEASURES the thing the eye is bad at: mean luma inside the ring versus
# outside it, per shot, so "it inverted" is a number and not an impression. An
# instrument that measures brightness cannot tell an inversion from a blowout — so
# this one reports BOTH sides and their difference, and the sign of that difference
# is the whole finding.
#
# Frames land in %APPDATA%/Godot/app_userdata/Ashpire/timestop_arena/.
extends SceneTree

const ARENA: String = "res://scenes/combat/Arena.tscn"
## Sampled across the freeze: just before, the instant it lands, mid-hold, the snap.
const SHOTS: Array[float] = [0.30, 0.80, 1.60, 2.60, 3.05, 3.30]

var _dir: String = "user://timestop_arena"
var _root: Node = null
var _shot: int = 0
var _spell: Node = null


func _initialize() -> void:
	Engine.max_fps = 60
	_root = (load(ARENA) as PackedScene).instantiate()
	root.add_child(_root)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	for i: int in 120:
		await process_frame

	var heroes: Array = _root.get_tree().get_nodes_in_group("player")
	if heroes.is_empty():
		heroes = _root.get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		printerr("[timestop] no hero"); quit(1); return
	var hero: Node2D = heroes[0] as Node2D

	var spell: SpellDef = SpellLibrary._spell_by_id().get("chronostasis") as SpellDef
	if spell == null:
		printerr("[timestop] no chronostasis in the library"); quit(1); return
	print("[timestop] radius %.0f  length %.1f" % [spell.radius, spell.length])

	# ⚠ A BASELINE, BECAUSE THE ARENA IS ALREADY PALE. Judging "is the bubble bounded"
	# by eye against a cream sky is exactly the mistake the crater pass made: a big
	# soft-edged pale disc over an already-pale background reads as unbounded whether
	# it is or not. The only honest question is WHAT THIS EFFECT CHANGED, so the same
	# shot is taken with no spell in flight and everything below is a difference.
	var baseline: Image = null
	await RenderingServer.frame_post_draw
	baseline = root.get_texture().get_image()
	if baseline != null:
		baseline.save_png("%s/baseline.png" % _dir)

	# ⚠ AND A CONTROL RUN, because the baseline alone CANNOT answer the question. The
	# spell also pulls the camera (`Juice.zoom_pull_camera`), and a zoom change moves
	# every pixel in the frame — so a diff against a pre-cast baseline reports a large
	# change everywhere, bubble or no bubble, and would "prove" an unbounded effect for
	# a perfectly bounded one. `--nobubble` runs the identical cast with the negative
	# suppressed through the accessibility gate, so the two runs differ in the plate
	# and in nothing else.
	var no_bubble: bool = OS.get_cmdline_user_args().has("--nobubble")
	if no_bubble:
		var tuning: Node = root.get_node_or_null(^"/root/Tuning")
		if tuning != null and tuning.get(&"cfg") != null:
			tuning.cfg[&"reduce_flashing"] = true
			print("[timestop] CONTROL RUN — negative suppressed")
		_dir += "_control"
		DirAccess.make_dir_recursive_absolute(_dir)

	# Centred a little ahead of the hero so the ring lands over live arena scenery
	# rather than over the hero's own body — the claim under test is what the SKY and
	# the FLOOR do inside the ring, and a figure filling it would hide both.
	var centre: Vector2 = hero.global_position + Vector2(90.0, -20.0)
	_spell = load("res://scripts/combat/Chronostasis.gd").new()
	_spell.set("target_group", "enemy")
	_spell.set("_target_group", "enemy")
	_spell.set("caster_node", hero)
	_root.add_child(_spell)
	_spell.call("cataclysm", hero, hero.global_position, centre, spell,
		Color(0.72, 0.92, 1.0), "ice")

	# The SPELL'S clock, never a frame counter — this scene renders well above 60 fps
	# and a 1/60-per-frame counter reported "3.32 s" for about one real second.
	var guard: int = 0
	while _shot < SHOTS.size() and guard < 40000:
		await process_frame
		await RenderingServer.frame_post_draw
		guard += 1
		var t: float = float(_spell.get("_elapsed")) if is_instance_valid(_spell) else 99.0
		if t >= SHOTS[_shot]:
			var img: Image = root.get_texture().get_image()
			if img != null:
				var p: String = "%s/a%d_%.2fs.png" % [_dir, _shot, t]
				img.save_png(p)
				_report(img, centre, spell.radius, t)
				_profile(img, baseline, centre, spell.radius, t)
				_uniforms(t)
			_shot += 1
	print("[timestop] DONE -> %s" % ProjectSettings.globalize_path(_dir))
	quit(0)


## Mean luma inside the ring vs a ring-width band just outside it, in SCREEN space.
## Reported as a pair plus the delta: a negative flips the sign of that delta, and
## which way it flips is exactly what a pale sky changes.
func _report(img: Image, centre_world: Vector2, radius: float, t: float) -> void:
	var cam: Camera2D = _find_camera(_root)
	if cam == null:
		print("[timestop] %.2fs  (no camera — image saved, unmeasured)" % t)
		return
	var vp: Vector2 = Vector2(img.get_width(), img.get_height())
	var screen: Vector2 = _to_image(centre_world, cam, vp)
	var r_px: float = radius * cam.zoom.x * _upscale(vp)
	var inside_sum: float = 0.0
	var inside_n: int = 0
	var out_sum: float = 0.0
	var out_n: int = 0
	# Every 4th pixel: this is a look-at-it probe, not a hot path, and a quarter
	# sample over a 235 px disc is still thousands of pixels a side.
	for y: int in range(0, img.get_height(), 4):
		for x: int in range(0, img.get_width(), 4):
			var d: float = Vector2(float(x), float(y)).distance_to(screen)
			if d > r_px * 1.9:
				continue
			var c: Color = img.get_pixel(x, y)
			var luma: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if d <= r_px * 0.85:
				inside_sum += luma
				inside_n += 1
			elif d >= r_px * 1.15:
				out_sum += luma
				out_n += 1
	var ins: float = inside_sum / maxf(float(inside_n), 1.0)
	var outs: float = out_sum / maxf(float(out_n), 1.0)
	print("[timestop] %.2fs  inside=%.3f  outside=%.3f  delta=%+.3f  (%s)"
		% [t, ins, outs, ins - outs,
			"INSIDE BRIGHTER" if ins > outs else "INSIDE DARKER"])


## HOW FAR OUT DID THIS EFFECT REACH? Mean absolute per-pixel change from the
## baseline, binned by distance from the ring centre in units of the ring's own
## radius. A BOUNDED bubble falls to ~0 past 1.0; an unbounded one does not, and no
## amount of looking at a pale frame will separate those two.
##
## Reported alongside the drawn ring so the two extents can be compared directly:
## the whole ruling behind this spell is that the screen must not claim more than the
## hitbox has.
func _profile(img: Image, base: Image, centre_world: Vector2, radius: float, t: float) -> void:
	if base == null or img == null:
		return
	if base.get_width() != img.get_width() or base.get_height() != img.get_height():
		return
	var cam: Camera2D = _find_camera(_root)
	if cam == null:
		return
	var vp: Vector2 = Vector2(img.get_width(), img.get_height())
	var screen: Vector2 = _to_image(centre_world, cam, vp)
	var r_px: float = radius * cam.zoom.x * _upscale(vp)
	var bins: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var counts: Array[int] = [0, 0, 0, 0, 0]
	var edges: Array[float] = [0.5, 0.9, 1.2, 2.0, 99.0]
	for y: int in range(0, img.get_height(), 3):
		for x: int in range(0, img.get_width(), 3):
			var k: float = Vector2(float(x), float(y)).distance_to(screen) / maxf(r_px, 1.0)
			var b: int = 0
			while b < edges.size() - 1 and k > edges[b]:
				b += 1
			var a: Color = img.get_pixel(x, y)
			var c: Color = base.get_pixel(x, y)
			bins[b] += absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b)
			counts[b] += 1
	var parts: PackedStringArray = PackedStringArray()
	for i: int in bins.size():
		parts.append("<%.1fR %.3f" % [edges[i], bins[i] / maxf(float(counts[i]), 1.0) / 3.0])
	print("[timestop] %.2fs  changed-vs-baseline  %s" % [t, " ".join(parts)])


## WHAT THE SHADER WAS ACTUALLY TOLD. The pixels and the intent can disagree, and
## when they do, the uniforms say which side of `_push_bubble` the fault is on:
## a `bubble_radius` of -1 means the plate was never told it was a bubble at all.
func _uniforms(t: float) -> void:
	for n: Node in _all(_root):
		if not (n is ImpactFrame):
			continue
		for c: Node in n.get_children():
			var cr: ColorRect = c as ColorRect
			if cr == null or cr.material == null:
				continue
			var m: ShaderMaterial = cr.material as ShaderMaterial
			var vp: Viewport = n.get_viewport()
			var cam: Camera2D = vp.get_camera_2d() if vp != null else null
			var vsize: Vector2 = Vector2(vp.get_visible_rect().size) if vp != null else Vector2.ZERO
			# The pushed radius NEXT TO the ring the world draws, both in the shader's
			# own units (full viewport heights). These two are supposed to differ by
			# exactly `Chronostasis.BUBBLE_SCALE`; anything else is a projection fault
			# and not a taste question.
			var ring_units: float = 0.0
			if cam != null and vsize.y > 0.0:
				ring_units = (235.0 * cam.zoom.x) / vsize.y
			print("[timestop] %.2fs  uniforms  radius=%s centre=%s amount=%s | cam_zoom=%s vp=%s ring_units=%.3f ratio=%.2f"
				% [t, m.get_shader_parameter(&"bubble_radius"),
					m.get_shader_parameter(&"bubble_centre"),
					m.get_shader_parameter(&"amount"),
					cam.zoom if cam != null else Vector2.ZERO, vsize, ring_units,
					float(m.get_shader_parameter(&"bubble_radius")) / maxf(ring_units, 0.0001)])
			return


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out


## ⚠ THE GAME RENDERS AT 640x360 AND THE SAVED PNG IS 1920x1080. Camera zoom is in
## VIEWPORT units, so a world radius projected with zoom alone lands three times too
## small in the image — which put this probe's own "outside the ring" band INSIDE the
## bubble and had it reporting, confidently, that a correctly bounded effect was
## unbounded. The uniforms were right and the instrument was wrong; this factor is
## the difference between those two answers.
func _upscale(image_size: Vector2) -> float:
	var vp: Viewport = root
	var visible: Vector2 = Vector2(vp.get_visible_rect().size)
	if visible.y < 1.0:
		return 1.0
	return image_size.y / visible.y


func _to_image(world: Vector2, cam: Camera2D, image_size: Vector2) -> Vector2:
	var k: float = _upscale(image_size)
	return (world - cam.get_screen_center_position()) * cam.zoom * k + image_size * 0.5


func _find_camera(from: Node) -> Camera2D:
	if from is Camera2D and (from as Camera2D).is_current():
		return from as Camera2D
	for c: Node in from.get_children():
		var f: Camera2D = _find_camera(c)
		if f != null:
			return f
	return null
