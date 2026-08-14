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
	# BEFORE the scene instantiates — see `_go_vertical`.
	if _vertical:
		_go_vertical()
		print("[clip] vertical: rendering %dx%d natively (no crop)"
			% [VERTICAL_SIZE.x, VERTICAL_SIZE.y])
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
		# No crop. The frame is ALREADY 9:16 when `--vertical=1` — see VERTICAL_SIZE.
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
## ⚠ IT USED TO BE A CENTRE CROP, AND THE CROP COULD NEVER HAVE WORKED. Kept here as a
## record, because "render it wide and cut a column out of the middle" is the obvious
## idea and it fails for three independent reasons at once:
##
##   1. THE PLATES. `BotMatch._PlateDraw._draw` anchors off its own full width —
##      `x0 = PLATE_MARGIN` on the left, `vw - PLATE_MARGIN - PLATE_W` on the right —
##      against a ~640-wide canvas. So the plates sit at x 14..246 and 394..626 while
##      a centred 9:16 column of a 1366x768 frame keeps canvas x 218..421. Roughly
##      88% of each HP bar, and the whole of each class name, fell outside the cut.
##   2. THE FIGHTERS. They stand `SPAWN_SPREAD * 2` = 560 world px apart, and the
##      director deliberately frames that pair to fill a 16:9 width — so it pushes
##      them toward the left and right thirds, which are exactly the two regions a
##      centre crop throws away. The better it framed, the more reliably the column
##      landed in the empty gap BETWEEN them.
##   3. It is a post-hoc pixel operation, so nothing in the game ever knew the output
##      was vertical. No amount of tuning inside a capture tool can fix that.
##
## ⚠ SO THE FRAME IS RENDERED VERTICAL INSTEAD OF BEING CUT DOWN TO VERTICAL, and every
## one of the three faults above dissolves rather than being worked around. With the
## window at 9:16 the project's `canvas_items` + `expand` stretch keeps the canvas 640
## wide and grows it TALL, so the plates anchor inside a 640-wide canvas exactly as
## they were written to, and `ClipDirector` solves its zoom against the real viewport —
## it is framing for the shot that will actually be posted rather than for a shot that
## is about to be cut in half behind its back.
##
## What that trades: a side-on duel is horizontally wide and vertically empty, so a
## vertical frame carries a lot of arena above the fighters. That is the correct
## problem to have — it is filled with stage, not with black — and it is fixable in
## composition (the director's vertical bias), which a crop never was.
##
## ⚠ NEVER LETTERBOX. Black bars read as reposted horizontal content and are named in
## the short-form research as an instant swipe. Render vertical, or do not go vertical.
const VERTICAL_SIZE: Vector2i = Vector2i(720, 1280)


## Put the window into 9:16 BEFORE the scene is built.
##
## ⚠ THE ORDERING IS THE POINT, and it is the same lesson `Cinematic.mark()` records:
## a HUD laid out under the old aspect and resized afterwards has already decided where
## its plates go. Sizing first means every Control is born into the frame it will be
## photographed in.
##
## The root viewport is told the size as well as the window, because on some platforms
## the second does not follow the first inside the same frame — and a capture that
## reads `root.get_texture()` at the old size silently writes the old resolution while
## reporting the new one. Same reason `directed_clip_capture._set_render_size` does it.
func _go_vertical() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_size(VERTICAL_SIZE)
	root.size = VERTICAL_SIZE
