# DOES THE FIGHTER READ AGAINST THE STAGE, IN ALL TEN BIOMES?
#
# GUI binary only — a --headless run draws with the dummy renderer, saves ten
# successful PNGs and every one of them is blank:
#   Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/biome_read_capture.gd
#
# -> user://biome_read_<n>_<name>.png, one per biome
#
# WHY. `VersusArena` dresses itself from one of `GameState.BIOMES`, rolled per bout —
# ten skies from no new art, which is a good trade. But the constraint the roll is
# checked against is VALUE against the ground band ("far enough that the fighters have
# something to be silhouetted against"), and value is only half of it. Two captures of
# the same fight came up teal and orange: against the teal the red fighters read at a
# glance, and against the orange they sat in the stage's own hue and had to be looked
# for.
#
# That is not a new class of bug here — `Atmosphere`'s own note says the tower spires
# were "blue-grey, which is the hero's own hue ... a row of tall blue bars, in the
# player's colour", and hazing them is what fixed it. This asks whether the same thing
# is true of the whole stage, for each of the ten.
#
# ⚠ IT PHOTOGRAPHS AND MEASURES NOTHING ITSELF. Ten PNGs, named by biome, for the eye
# and for a pixel probe. Deciding "reads / does not read" from a computed hue distance
# would be measuring the palette rather than the frame, which is the trap this repo
# keeps paying for.
# ⚠ ONE BIOME PER PROCESS, AND THE FIRST VERSION OF THIS TOOL IS WHY. It looped all
# ten inside a single tree — `add_child`, shoot, `queue_free`, repeat — and produced
# ten PNGs that all saved successfully. Two of them had a stage in; one had caught the
# PAUSE MENU; the other seven were black frames with a leftover HUD and a wash. Arena
# state, the camera, the autoloads and the HUD CanvasLayers do not unwind on
# `queue_free`, so every shot after the first was of a half-torn-down world.
#
# The loop lives in the SHELL now, one engine boot per biome. It is slower and it is
# the only version whose output means anything:
#
#   for i in 0 1 2 3 4 5 6 7 8 9; do \
#     Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/biome_read_capture.gd -- $i ; done
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
## Long enough for the sigil-and-settle opening and for the bots to separate.
const SETTLE: float = 2.6


func _initialize() -> void:
	_run()


func _run() -> void:
	var idx: int = 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			idx = int(arg)
	var packed: PackedScene = load(SCENE)
	if packed == null:
		printerr("could not load ", SCENE)
		quit(1)
		return
	var scene: Node = packed.instantiate()
	# ⚠ SET BEFORE THE SCENE ENTERS THE TREE. `_stage_theme()` is read once during the
	# arena's own build, so a biome assigned after `add_child` is assigned after the sky
	# it was meant to choose has already been painted.
	scene.set("stage_biome", idx)
	root.add_child(scene)
	await create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw

	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("no frame — was this run with the GUI binary?")
		quit(1)
		return
	var rolled: int = int(scene.get("stage_biome_rolled"))
	var path: String = "user://biome_read_%02d.png" % rolled
	img.save_png(path)
	print("biome %d (rolled %d) -> %s"
		% [idx, rolled, ProjectSettings.globalize_path(path)])
	quit(0)
