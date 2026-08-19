# WHAT SIZE DOES THE GAME ACTUALLY RENDER AT DURING A MOVIE SHOOT?
#
# Two separate questions, and conflating them is what made this confusing:
#
#   1. AT STARTUP, driven by `window/size/window_*_override` in project.godot —
#      which is the ONLY thing MovieWriter reads for its output size. This is the
#      path a real shoot takes.
#   2. AT RUNTIME, when `directed_clip_capture._set_render_size()` calls
#      `DisplayServer.window_set_size()`. Measured separately: asking for
#      1080x1920 there came back 1080x1570, because Windows clamps a window to
#      the desktop.
#
# If (1) and the movie size disagree, every frame is resampled and the whole
# picture is stretched — which would show up as the maker's "stick figures become
# all long and weird". If they agree, the render is honest and the softness has a
# different cause. This prints both. GUI binary only.
extends SceneTree


func _initialize() -> void:
	# STARTUP state, before anything resizes anything.
	await process_frame
	print("[hud] STARTUP window_get_size  = %s" % DisplayServer.window_get_size())
	print("[hud] STARTUP root.size        = %s" % root.size)
	print("[hud] STARTUP visible_rect     = %s" % root.get_visible_rect().size)
	print("[hud] STARTUP transform scale  = %s" % root.get_final_transform().get_scale())

	# Now the runtime resize the capture tool performs.
	var want := Vector2i(1080, 1920)
	DisplayServer.window_set_size(want)
	root.size = want
	await process_frame
	await process_frame
	print("[hud] AFTER-RESIZE window      = %s" % DisplayServer.window_get_size())
	print("[hud] AFTER-RESIZE root.size   = %s" % root.size)
	print("[hud] AFTER-RESIZE visible     = %s" % root.get_visible_rect().size)
	print("[hud] AFTER-RESIZE scale       = %s" % root.get_final_transform().get_scale())
	quit()
