extends SceneTree
## STAMP EVERY CLEFT VARIANT SIDE BY SIDE — a chooser, not a deliverable.
##
## Maker: *"come up with 3/4 variations of the logo all cool to see and simple please"*.
## Four marks cannot be judged from four descriptions, and they cannot be judged one at
## a time either — the whole question is which one wins against the others.
##
## ⚠ SAME RULES AS render_logo.gd, for the same reasons. Runs WITHOUT `--headless`
## (a null rendering driver hands back blank images that save successfully), and the
## phase is FROZEN so a variant does not change between the run that made it and the run
## that ships it.
##
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --path godot-project \
##       --script tools/render_logo_variants.gd
##
## ⚠ THE WINNER IS NOT PICKED HERE. This writes to `variants/`, which nothing consumes.
## Once the maker chooses, set `GameLogo.cleft_look`'s default and re-run
## `render_logo.gd` + `build_social_kit.py` — that is what rewrites the real kit.

const OUT_DIR: String = "res://assets/brand/variants"
const PHASE: float = 0.0
## 512, not 1024: these are for looking at four-up, and half the size renders in half
## the time for a decision that does not depend on the last octave of detail.
const PX: int = 512

## ⚠ THE LIGHT IS FIXED AT SIGIL AND THE STONE VARIES. Round one varied the light and
## the maker picked SIGIL; round two asks "optimise the towers", so holding the winner
## fixed is the only way the next comparison is about the thing being compared.
const LOOKS: Array[Dictionary] = [
	{"name": "1_stepped.png", "cut": 0},
	{"name": "2_battered.png", "cut": 1},
	{"name": "3_buttress.png", "cut": 2},
	{"name": "4_chamfer.png", "cut": 3},
]


func _initialize() -> void:
	# ⚠ The tree does not exist yet in `_initialize`. Everything below runs a frame on.
	call_deferred("_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for job: Dictionary in LOOKS:
		await _stamp(int(job["cut"]), String(job["name"]))
	print("[variants] done — %d files in %s" % [LOOKS.size(), OUT_DIR])
	quit()


func _stamp(cut: int, file_name: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(PX, PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_2d = Viewport.MSAA_4X
	root.add_child(vp)

	var logo := GameLogo.new()
	logo.size = Vector2(PX, PX)
	logo.show_wordmark = false
	logo.frozen_phase = PHASE
	logo.emblem = GameLogo.Emblem.CLEFT
	logo.cleft_look = GameLogo.CleftLook.SIGIL
	logo.tower_cut = cut as GameLogo.TowerCut
	vp.add_child(logo)

	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path: String = "%s/%s" % [OUT_DIR, file_name]
	var err: int = img.save_png(path)
	# ⚠ A BLANK PNG SAVES JUST FINE — `save_png` returning OK says a file was written,
	# not that anything is in it. Count lit pixels or this tool will cheerfully report
	# four successful exports of nothing.
	var lit: int = 0
	for y: int in range(0, img.get_height(), 8):
		for x: int in range(0, img.get_width(), 8):
			if img.get_pixel(x, y).a > 0.02:
				lit += 1
	print("[variants] %-14s err=%d  lit=%d%s"
		% [file_name, err, lit, "   *** BLANK ***" if lit == 0 else ""])
	vp.queue_free()
