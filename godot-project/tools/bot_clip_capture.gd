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

## ⚠ `--scene=botmatch` CAPTURES WHAT THE MAKER ACTUALLY WATCHES. "Watch Bots" on the
## title screen opens `BotMatch`, which WRAPS the arena and adds its own intro card,
## overlay, bout counter and `ClipDirector` framing. Capturing `VersusArena` alone —
## the default, and the only thing this tool could do before — reviews a presentation
## nobody sees, and every framing note taken from it is about the wrong picture.
const BOT_MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"

## ⚠ CINEMATIC MODE ON BY DEFAULT HERE, unlike everywhere else in the project.
## `Cinematic.enabled` is deliberately OFF globally because ~69 capture tools exist to
## photograph exactly the diagnostics it hides. THIS tool is not one of them: its whole
## stated purpose is a frame sequence someone can watch, and it was burning the clip
## engine's own `heat 0.00 [ROLLING]` readout into the bottom-left and the touch PAUSE
## button into the top-right of every single frame. `directed_clip_capture.gd` already
## opts in for the same reason; this one simply never did, so every clip it has ever
## produced carried the instruments. `--clean=0` restores the old behaviour.
const CINEMATIC_SCRIPT: String = "res://scripts/combat/Cinematic.gd"

var _class_a: int = 0
var _class_b: int = 5
var _frames: int = 420
var _every: int = 2
var _warmup: int = 90
var _difficulty: int = 2
var _out: String = "clip"
## "arena" (default) or "botmatch" — see BOT_MATCH_SCENE.
var _scene: String = "arena"
## Cinematic mode — see CINEMATIC_SCRIPT. On unless `--clean=0`.
var _clean: bool = true
## 9:16 crop for TikTok / Reels. OFF by default — see `_crop_vertical`.
var _vertical: bool = false

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
	# ⚠ BEFORE THE SCENE IS BUILT. `Cinematic.mark()` applies the current mode the
	# instant a node registers, so a diagnostic built before this flag is set would
	# stay visible for the whole capture. By `load()` + `set()`, never by the
	# `Cinematic` identifier — this runs under `--script`, where naming a class that
	# reaches an autoload is a parse-time failure and a capture of an empty room.
	var cine: GDScript = load(CINEMATIC_SCRIPT) as GDScript
	if cine != null:
		cine.set("enabled", _clean)
	else:
		print("[clip] ⚠ no Cinematic.gd — the heat readout and pause button will show")
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script != null:
		arena_script.set("showcase_a", _class_a)
		arena_script.set("showcase_b", _class_b)
		arena_script.set("showcase_difficulty", _difficulty)
	# BotMatch rolls its OWN matchup and re-seats the fighters, so --a/--b are only
	# honoured by the bare arena. Say so rather than letting the flags look ignored.
	if _scene == "botmatch":
		print("[clip] scene=botmatch — it rolls its own matchup, so --a/--b are ignored")
		root.add_child((load(BOT_MATCH_SCENE) as PackedScene).instantiate())
	else:
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
			"scene": _scene = value
			"clean": _clean = value != "0"
			"vertical": _vertical = value != "0"


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
		if _vertical:
			img = _crop_vertical(img)
		img.save_png("%s/f%04d.png" % [_dir, _saved])
		_saved += 1
		# Progress on a cadence, so a long capture is visibly alive rather than a
		# silent multi-minute hang.
		if _saved % 30 == 0:
			print("[clip] saved %d frames (walked %d/%d)" % [_saved, _frame, _frames])
	print("[clip] DONE — %d frames in %s" % [_saved, ProjectSettings.globalize_path(_dir)])
	quit(0)


## ── 9:16 FOR TIKTOK / REELS ──────────────────────────────────────────────────
## Maker: *"the 9:16 should be an option just like the landscape, we can post both and
## see what lands better"*. So this is a FLAG, not a replacement — landscape stays the
## default and the same bout can be rendered both ways for an A/B.
##
## ⚠ A CENTRE CROP, AND THAT IS A REAL LIMITATION RATHER THAN A DETAIL. A side-on duel
## is horizontally wide and vertically empty; 9:16 is the opposite. Cropping a 1366-wide
## frame to 9:16 keeps a 432 px-wide column, and the two fighters routinely stand 560 px
## apart (`BotMatch.SPAWN_SPREAD * 2`) — so one of them will often be outside it. The
## honest fix is a tighter game camera that keeps both bodies in the middle band, which
## is a change to `CombatCamera`, not to a capture tool. Until that exists this is for
## judging framing and posting tests, not for shipping every clip.
##
## ⚠ NEVER LETTERBOX. Black bars read as reposted horizontal content and are named in
## the short-form research as an instant swipe. Crop, or do not go vertical.
##
## The crop is horizontally CENTRED and vertically FULL-HEIGHT, which keeps the HP
## plates (top band) and the fight floor in frame rather than slicing the plates off.
func _crop_vertical(src: Image) -> Image:
	var h: int = src.get_height()
	var want_w: int = int(round(float(h) * 9.0 / 16.0))
	if want_w >= src.get_width():
		return src        # already at least as tall as it is wide; nothing to crop
	var x: int = int((src.get_width() - want_w) * 0.5)
	return src.get_region(Rect2i(x, 0, want_w, h))
