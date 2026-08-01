# FREE PLAY, rendered — proof that the no-bots stage actually comes up: the
# onboarding controls card, then the empty arena with one hero on it, then the same
# stage with practice dummies standing on it.
#
# Run (GUI binary — NOT --headless; the dummy renderer draws nothing while cheerfully
# reporting success, which is how blank captures get shipped):
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/freeplay_capture.gd -- --class=0
#
# ...or through the index:
#   python python-tools/run_capture.py freeplay
#
# Options:
#   --class=N     Hero.HeroClass to start on. Default 0 (ARCANIST).
#   --dummies=N   practice dummies in the second half of the capture. Default 2.
#   --out=NAME    subfolder under user://freeplay.
#
# WHAT EACH SHOT IS FOR:
#   f0000  the controls card over the stage — the onboarding surface, and the one
#          thing that has to be legible or the whole point is lost.
#   f0001  the card dismissed: an empty arena, one hero, no opposition. This is the
#          literal maker ask ("no bots and play on the stage") and the frame that
#          proves it.
#   f0002+ dummies stood up live, WITHOUT a scene reload — the reconfigurable half.
extends SceneTree

const FREE_SCENE: String = "res://scenes/combat/FreePlay.tscn"
const FREE_SCRIPT: String = "res://scripts/combat/FreePlay.gd"

var _class: int = 0
var _dummies: int = 2
var _out: String = "shots"
var _dir: String = ""
var _saved: int = 0
var _root: Node = null


func _initialize() -> void:
	_parse_args()
	_dir = "user://freeplay/%s" % _out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	# ⚠ BY PATH, never by `class_name`. Naming `FreePlay` here would compile it and
	# its whole dependency chain (which reaches the Sfx / Rank / Juice autoloads) at
	# THIS script's parse time, before the main loop has registered any autoload.
	var free_script: GDScript = load(FREE_SCRIPT) as GDScript
	if free_script != null:
		free_script.set("start_class", _class)
		free_script.set("controls_dismissed", false)   # we want to SEE the card
	_root = (load(FREE_SCENE) as PackedScene).instantiate()
	root.add_child(_root)
	print("[freeplay] class=%d dummies=%d -> %s"
		% [_class, _dummies, ProjectSettings.globalize_path(_dir)])
	_run()


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_args())
	argv.append_array(OS.get_cmdline_user_args())
	for raw: String in argv:
		var arg: String = String(raw)
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var key: String = arg.substr(2, arg.find("=") - 2)
		var value: String = arg.substr(arg.find("=") + 1)
		match key:
			"class": _class = clampi(int(value), 0, 8)
			"dummies": _dummies = clampi(int(value), 0, 3)
			"out": _out = value


func _run() -> void:
	await _settle(45)          # let the stage build and the hero land on the floor
	await _shot("controls card over the stage")
	_root.call("_dismiss_card")
	await _settle(20)
	await _shot("the empty stage — one hero, no opposition")
	# Positions in the log, so a framing problem is diagnosable from the console
	# instead of by squinting at a PNG and doing camera arithmetic backwards.
	for h: Node in get_nodes_in_group("hero"):
		print("[freeplay]   body %s at %s%s" % [h.name, (h as Node2D).global_position,
			"  (dummy)" if h.is_in_group("free_dummy") else "  (YOU)"])
	var arena: Node = _find_arena()
	if arena != null and arena.has_method("set_dummy_count"):
		arena.call("set_dummy_count", _dummies)
		await _settle(30)
		await _shot("%d practice dummies, stood up live" % _dummies)
	print("[freeplay] DONE — %d frames in %s"
		% [_saved, ProjectSettings.globalize_path(_dir)])
	if _saved == 0:
		printerr("[freeplay] NO FRAMES WRITTEN — was this run with --headless?")
	quit(0)


func _find_arena() -> Node:
	for child: Node in _root.get_children():
		if child.has_method("free_hero"):
			return child
	return null


func _settle(frames: int) -> void:
	for _i: int in frames:
		await process_frame


## ⚠ `await RenderingServer.frame_post_draw` BEFORE every grab. Reading
## `root.get_texture().get_image()` before the draw completes hands back the
## PREVIOUS frame, so a shot taken immediately after a change shows the state
## before it — which is precisely the change the shot exists to prove.
func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.save_png("%s/f%04d.png" % [_dir, _saved])
	print("[freeplay] saved f%04d — %s" % [_saved, label])
	_saved += 1
