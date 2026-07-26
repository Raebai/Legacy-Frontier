# Throwaway render check for the ZONE-spell rework (blizzard squall + shadow
# root). Modelled on tools/spell_playground_capture.gd. GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/zone_agent_capture.gd
extends SceneTree

const SHADOW_ROOT_PATH: String = "res://scripts/combat/ShadowRoot.gd"

var _scene: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	for i in 70:
		await physics_frame                      # settle the figure + dummies
	var fig: Node = _scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	# ---- BLIZZARD at the right dummy (x=220): 3 shots a beat apart so the
	# wind-driven motion is provable frame-over-frame.
	var bliz: SpellDef = null
	for s: SpellDef in _scene.get("_spells"):
		if s.id == "blizzard":
			bliz = s
	SpellCaster.cast(bliz, _scene, origin, Vector2(220.0, 315.0), Color(0.5, 0.85, 1.0), "")
	for i in 30:
		await physics_frame
	_save("zone_blizzard_a.png")
	for i in 30:
		await physics_frame
	_save("zone_blizzard_b.png")
	for i in 90:
		await physics_frame
	_save("zone_blizzard_c.png")                 # late: ice accretion visible
	# Let the squall blow out fully (4.2 s life + fade) before the shadow shots.
	for i in 480:
		await physics_frame
	# ---- SHADOW ROOT driven directly (not yet dispatched) at the right dummy
	# (x=220 — far enough that MIN_RUN doesn't overshoot the lock past it).
	var sr: Node2D = (load(SHADOW_ROOT_PATH) as GDScript).new()
	_scene.add_child(sr)
	sr.set("element_id", Elements.Element.SHADOW)
	sr.call("erupt", origin, Vector2(220.0, 315.0) - origin,
		Elements.color(Elements.Element.SHADOW), 64.0, 26, "shadow")
	for i in 30:
		await physics_frame                      # 0.25 s: mid-surge telegraph
	_save("zone_shadow_telegraph.png")
	for i in 50:
		await physics_frame                      # ~0.67 s: snapped + gripping
	_save("zone_shadow_locked.png")
	for i in 60:
		await physics_frame                      # ~1.17 s: grip held, overlay on
	_save("zone_shadow_grip_late.png")
	quit(0)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("zonecap saved ", fname)
