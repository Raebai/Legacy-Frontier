# THE CLIP ENGINE — renders a real bot-vs-bot fight to a PNG frame sequence that
# `python-tools/frames_to_gif.py` encodes into a watchable animated GIF.
#
# Run (GUI binary — NOT --headless; the dummy renderer draws nothing):
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/bot_clip_capture.gd -- --a=0 --b=5 --frames=300 --every=2
#
# Options:
#   --a=N --b=N        Hero.HeroClass ids for the two fighters. Default 0 vs 5
#                      (ARCANIST vs CRYOMANCER — arcane/fire vs ice, so the
#                      reaction matrix actually fires).
#   --frames=N         how many rendered frames to walk. Default 420 (~7 s).
#   --every=N          save every Nth frame. 2 at 60 fps gives a 30 fps clip.
#   --warmup=N         frames to discard before the first save, so the capture
#                      starts on a live fight rather than on the spawn poof.
#   --difficulty=0..3  BotProfile tier. Reaction delay and error rate only.
#   --out=NAME         subfolder under user://clips.
#
# WHY A PNG SEQUENCE AND NOT `--write-movie`. Godot's MovieWriter renders at a
# fixed timestep (genuinely nicer for determinism) but emits uncompressed AVI —
# roughly half a gigabyte for seven seconds at this resolution, which is not a
# file anyone can hand to anybody. ffmpeg is not installed to transcode it.
# Pillow IS installed, so PNG frames -> GIF is the route that ends in a file the
# maker can open, and it has the decisive advantage that the frames can be READ
# BACK and the framing checked before the clip is called done. Several capture
# tools in this project have shipped with the payoff cropped off the edge; the
# only defence is looking at the output.
extends SceneTree

const ARENA_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"

var _class_a: int = 0
var _class_b: int = 5
var _frames: int = 420
var _every: int = 2
var _warmup: int = 90
var _difficulty: int = 2
var _out: String = "clip"

var _frame: int = 0
var _saved: int = 0
var _dir: String = ""
var _running: bool = false


func _initialize() -> void:
	_parse_args()
	_dir = "user://clips/%s" % _out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	# Statics BEFORE the scene instantiates — VersusArena._ready reads them to
	# decide whether it is building the normal arena or a two-bot duel.
	#
	# ⚠ REACHED BY PATH, NEVER BY `class_name`. Naming `VersusArena` here would
	# compile it — and its whole dependency chain, which touches the `Sfx` / `Rank`
	# / `Juice` autoloads — at THIS script's parse time, before the main loop has
	# registered any autoload. The result is "Compile Error: Identifier not found:
	# Sfx", a scene that silently fails to build, and a capture of an empty room.
	# Measured, not assumed: the first run of this tool did exactly that.
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script != null:
		arena_script.set("showcase_a", _class_a)
		arena_script.set("showcase_b", _class_b)
		arena_script.set("showcase_difficulty", _difficulty)
	root.add_child((load(ARENA_SCENE) as PackedScene).instantiate())
	print("[clip] classes %d vs %d, %d frames, every %d, warmup %d -> %s"
		% [_class_a, _class_b, _frames, _every, _warmup,
			ProjectSettings.globalize_path(_dir)])
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
			"a": _class_a = int(value)
			"b": _class_b = int(value)
			"frames": _frames = int(value)
			"every": _every = maxi(int(value), 1)
			"warmup": _warmup = int(value)
			"difficulty": _difficulty = clampi(int(value), 0, 3)
			"out": _out = value


## Walk the fight one rendered frame at a time, grabbing the viewport after the
## draw has actually happened.
##
## ⚠ `await RenderingServer.frame_post_draw` EVERY frame, not just once at the
## end. Reading `root.get_texture().get_image()` before the draw completes hands
## back the PREVIOUS frame — which, over a sequence, silently shifts the whole
## clip one frame out of step with the audio-visual beats it is meant to show.
func _run() -> void:
	_running = true
	while _frame < _frames:
		await process_frame
		await RenderingServer.frame_post_draw
		_frame += 1
		if _frame <= _warmup:
			continue
		if (_frame - _warmup) % _every != 0:
			continue
		var img: Image = root.get_texture().get_image()
		if img == null:
			continue
		img.save_png("%s/f%04d.png" % [_dir, _saved])
		_saved += 1
		# Progress on a cadence, so a long capture is visibly alive rather than a
		# silent multi-minute hang.
		if _saved % 30 == 0:
			print("[clip] saved %d frames (walked %d/%d)" % [_saved, _frame, _frames])
	print("[clip] DONE — %d frames in %s" % [_saved, ProjectSettings.globalize_path(_dir)])
	quit(0)
