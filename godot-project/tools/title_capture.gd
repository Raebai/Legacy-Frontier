# The TITLE SCREEN, as drawn. GUI binary only — under --headless Godot uses the dummy
# renderer, every frame saves successfully and every PNG is blank, which looks exactly
# like a pass:
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/title_capture.gd
#
# -> user://title_screen.png          the front door, as a player sees it
# -> user://title_coop.png            the co-op panel open, where "Start Run" lives
#
# WHY IT EXISTS. The front door had no capture tool at all, and it is the one screen
# every player sees. It is also where this project's font fault was reported from: both
# primary buttons are built by `Lobby._button("SINGLE PLAYER  ▸", ...)`, so their labels
# are CONSTRUCTOR ARGUMENTS, which is how a gate written to catch undrawable glyphs
# walked straight past the two most important strings in the game.
#
# ⚠ SO IT PHOTOGRAPHS RATHER THAN ASSERTS. `slice_test_font_coverage` can prove a glyph
# is in the font; only this can show what the row LOOKS like once it is — whether the
# display face fits the button, whether the marker reads at size, whether a condensed
# face has quietly changed every width on the screen.
extends SceneTree

const TITLE: String = "res://scenes/ui/Lobby.tscn"
## Big enough to judge at, and the committed window override, so what is framed here is
## the shape the player gets rather than the 640x360 the project stretches from.
const SHOT: Vector2i = Vector2i(1366, 768)
## Comfortably past `_Sigil.OPEN_TIME` (3.4 s) plus the button tween that follows it.
const SETTLE: float = 6.0
const PANEL_SETTLE: float = 1.2


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load(TITLE) as PackedScene
	if packed == null:
		push_error("could not load %s" % TITLE)
		quit(1)
		return

	# A SubViewport, so the project's 640x360 stretch does not decide the resolution
	# this is judged at. The maker's rule, paid for on the rig: look at it BIG.
	var sub := SubViewport.new()
	sub.size = SHOT
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)

	var scene: Node = packed.instantiate()
	sub.add_child(scene)

	# ⚠ WAIT ON THE CLOCK, NOT ON FRAMES. The opening sigil runs for `_Sigil.OPEN_TIME`
	# (3.4 s) and the buttons tween in after 42% of it. A frame count is not a duration:
	# 150 `process_frame`s in this harness elapsed well under a second, and the first
	# version of this tool photographed a half-swept arc on an empty screen — a frame
	# that saved successfully and showed none of what it was written to show.
	await create_timer(SETTLE).timeout
	await _shot(sub, "title_screen", "the front door")

	# The co-op panel is hidden until asked for, and it carries the Start Run row that
	# only exists once you are hosting. Worth its own frame: it is three more buttons
	# in the display face and the layout that has to hold them.
	var toggled: bool = _open_coop(scene)
	if toggled:
		await create_timer(PANEL_SETTLE).timeout
		await _shot(sub, "title_coop", "the co-op panel")
	else:
		print("title_capture: could not open the co-op panel — skipped that frame")
	quit(0)


## Press the thing rather than reaching into private state, so what is photographed is
## what a player's tap produces.
func _open_coop(scene: Node) -> bool:
	for b: Node in _buttons(scene):
		var text: String = String((b as Button).text).to_upper()
		if text.contains("MULTIPLAYER") or text.contains("CO-OP"):
			(b as Button).emit_signal(&"pressed")
			return true
	return false


func _buttons(n: Node) -> Array:
	var out: Array = []
	if n is Button:
		out.append(n)
	for c: Node in n.get_children():
		out.append_array(_buttons(c))
	return out


func _shot(sub: SubViewport, name: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	if img == null:
		print("title_capture: no frame for %s — GUI binary?" % name)
		return
	var path: String = "user://%s.png" % name
	img.save_png(path)
	print("title_capture: %s -> %s (%s)"
		% [name, ProjectSettings.globalize_path(path), what])
