extends SceneTree
## STAMP THE MARK TO PNG — app icon, store tile, social avatar.
##
## The logo is drawn code (see GameLogo), which is what makes it scale, but a store
## page and a TikTok profile both want a FILE. This renders the same Control into an
## offscreen viewport at several sizes and writes them next to the project.
##
## ⚠ IT MUST RUN WITH A REAL RENDERER. `--headless` gives you a null rendering driver
## and every `get_texture().get_image()` comes back blank — the same fault that made
## `capture_screenshot` useless under the dummy driver. So this is run WITHOUT
## `--headless`, exactly like the clip tools:
##
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --path godot-project \
##       --script tools/render_logo.gd
##
## ⚠ AND THE PHASE IS FROZEN. The emblem turns, so an unfrozen stamp would produce a
## different icon every run and no two exports would match. `frozen_phase` pins it to
## the angle the mark was designed at.

const OUT_DIR: String = "res://assets/brand"
## Frozen at a phase where a long tick sits at the top of the ring — the mark reads
## upright rather than caught mid-turn.
const PHASE: float = 0.0
## `icon` is what project.godot points at; the rest are for stores and socials.
const JOBS: Array[Dictionary] = [
	{"name": "icon.png", "size": 512, "wordmark": false},
	{"name": "icon_256.png", "size": 256, "wordmark": false},
	{"name": "icon_128.png", "size": 128, "wordmark": false},
	{"name": "avatar_1024.png", "size": 1024, "wordmark": false},
	{"name": "logo_wordmark_1024.png", "size": 1024, "wordmark": true},
	{"name": "logo_wordmark_512.png", "size": 512, "wordmark": true},
]


func _initialize() -> void:
	# ⚠ The tree does not exist yet in `_initialize`. Everything below runs a frame on.
	call_deferred("_go")


func _go() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for job: Dictionary in JOBS:
		await _stamp(int(job["size"]), bool(job["wordmark"]), String(job["name"]))
	print("[logo] done — %d files in %s" % [JOBS.size(), OUT_DIR])
	quit()


func _stamp(px: int, wordmark: bool, file_name: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	# TRANSPARENT, because an icon sits on whatever the OS or the platform puts behind
	# it. The Lobby supplies its own PAPER; a baked-in background would show as a black
	# square on every rounded-corner launcher.
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# 4x MSAA — the mark is nothing but thin arcs and a polygon, so aliasing is the
	# whole quality difference. (8x is banned by slice_test_render_budget; 4x stands.)
	vp.msaa_2d = Viewport.MSAA_4X
	root.add_child(vp)

	var logo := GameLogo.new()
	logo.size = Vector2(px, px)
	logo.show_wordmark = wordmark
	logo.frozen_phase = PHASE
	# The wordmark variant needs the emblem to give up room for the letters.
	logo.emblem_scale = 0.92 if wordmark else 1.0
	vp.add_child(logo)

	# Two frames: one to lay out and draw, one to be sure the target has the result.
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var path: String = "%s/%s" % [OUT_DIR, file_name]
	var err: int = img.save_png(path)
	# ⚠ A BLANK PNG SAVES JUST FINE. `save_png` returning OK says the file was written,
	# not that anything is in it — which is exactly how a null renderer produces six
	# "successful" exports of nothing. So check that some pixel actually has alpha.
	var lit: int = 0
	for y: int in range(0, img.get_height(), maxi(img.get_height() / 32, 1)):
		for x: int in range(0, img.get_width(), maxi(img.get_width() / 32, 1)):
			if img.get_pixel(x, y).a > 0.02:
				lit += 1
	print("[logo] %-26s %4dpx  err=%d  lit_samples=%d%s" % [
		file_name, px, err, lit, "   *** BLANK — is this running under --headless? ***" if lit == 0 else ""])
	vp.queue_free()
	await process_frame
