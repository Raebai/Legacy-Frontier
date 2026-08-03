# LOOK AT THE NINE MOVEMENT VERBS. No assertion can settle whether a Shoulder Charge
# reads as a charge or whether the Stormcaller's blink reads as a discharge rather than
# a dropped frame — so this renders each class pressing its movement button and writes
# the frames out to be LOOKED at.
#
# Run (GUI binary — under --headless Godot uses the DUMMY renderer and every PNG is
# blank while the tool reports success):
#   python python-tools/run_capture.py movement_verb
#
# One row per class, three frames each: PRE (parked, the reference), MID (the verb in
# flight — where the trail/crackle/wake has to read), POST (where the body ended up).
# For the two teleports MID and POST are the same beat by construction, which is itself
# the thing to look at: they should read as one event with two ends, not as a body that
# skipped some frames.
extends SceneTree

const ARENA_PATH: String = "res://scenes/combat/VersusArena.tscn"
const CLASS_LABELS: Array[String] = [
	"0_arcanist_recall", "1_shadowblade_airdash", "2_brawler_charge",
	"3_juggernaut_surge", "4_cleric_radiantstep", "5_cryomancer_iceslide",
	"6_stormcaller_lightningblink", "7_warlock_thrallswap", "8_swordsaint_lunge",
]
## Frames to let the arena settle before the first press.
const SETTLE_FRAMES: int = 160
## Where in the travel the MID frame is taken. The shortest verb is the Swordsaint's
## 0.12 s (≈7 ticks at 60 Hz), so 4 lands inside every one of them.
const MID_FRAME: int = 4
## ...and how long after the press the POST frame is taken. Past the longest verb
## (the 0.55 s ice slide ≈ 33 ticks) so every row shows a settled body.
const POST_FRAME: int = 40


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	var scene: Node = load(ARENA_PATH).instantiate()
	root.add_child(scene)
	for _i: int in SETTLE_FRAMES:
		await physics_frame
	var heroes: Array = root.get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		printerr("movecap: NO HERO in the arena — nothing to photograph")
		quit(1)
		return
	var hero: Node = heroes[0]
	# Freeze the OTHER fighter so it does not wander into frame and confuse the read.
	for i: int in range(1, heroes.size()):
		(heroes[i] as Node).set_physics_process(false)
	var home: Vector2 = (hero as Node2D).global_position
	# Give the Warlock something to swap with, built to the published contract
	# (group `thrall`, meta `thrall_owner`) so the row shows a REAL swap rather than
	# the no-thrall fallback.
	var thrall: Node2D = _spawn_thrall(scene, hero, home + Vector2(300.0, -40.0))
	for cls: int in CLASS_LABELS.size():
		await _shoot_class(hero, cls, home, thrall)
	quit(0)


func _spawn_thrall(parent: Node, owner_hero: Node, at: Vector2) -> Node2D:
	var t := Node2D.new()
	t.set_script(load("res://tools/_thrall_stub.gd"))
	t.add_to_group(&"thrall")
	t.set_meta(&"thrall_owner", owner_hero)
	parent.add_child(t)
	t.global_position = at
	# A visible marker, or the swap row photographs an invisible partner.
	var mark := ColorRect.new()
	mark.color = Color(0.55, 0.2, 0.65, 0.9)
	mark.size = Vector2(14.0, 34.0)
	mark.position = Vector2(-7.0, -34.0)
	t.add_child(mark)
	return t


func _shoot_class(hero: Node, cls: int, home: Vector2, thrall: Node2D) -> void:
	hero.call("configure_class", cls)
	_park(hero, home)
	await physics_frame
	_park(hero, home)
	thrall.global_position = home + Vector2(300.0, -40.0)
	await _save("movecap_%s_a_pre.png" % CLASS_LABELS[cls])
	# Aim + press. `_aim_dir` is re-resolved from the mouse every physics tick, so the
	# press has to happen in the same synchronous block as the aim.
	_park(hero, home)
	hero.call("_start_dash")
	for _i: int in MID_FRAME:
		await physics_frame
	await _save("movecap_%s_b_mid.png" % CLASS_LABELS[cls])
	for _i: int in (POST_FRAME - MID_FRAME):
		await physics_frame
	await _save("movecap_%s_c_post.png" % CLASS_LABELS[cls])


func _park(hero: Node, home: Vector2) -> void:
	(hero as Node2D).global_position = home
	hero.set("velocity", Vector2.ZERO)
	hero.set("facing", Vector2.RIGHT)
	hero.set("_move_dir", Vector2.RIGHT)
	hero.set("_dash_cooldown_timer", 0.0)
	hero.set("_aim_dir", Vector2.RIGHT)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("movecap saved ", fname)
