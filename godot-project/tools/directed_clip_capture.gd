# THE DIRECTED CLIP ENGINE — renders a bot-vs-bot MATCH as a PNG frame sequence that
# starts where the fight starts, follows the action, and stops on the result.
#
# Run (GUI binary — NOT --headless; the dummy renderer draws nothing and reports
# success, which is how blank clips get shipped):
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/directed_clip_capture.gd -- --a=6 --b=5 --seconds=14
#
# ...or through the index, which knows to use the GUI binary:
#   python python-tools/run_capture.py directed_clip_capture
#
# Then encode it:
#   python python-tools/frames_to_gif.py <the printed path> --fps 30 --width 720
#
# Options:
#   --a=N --b=N        Hero.HeroClass ids for the two fighters. Default 6 vs 5
#                      (STORMCALLER vs CRYOMANCER — lightning into ice, so the
#                      reaction matrix's best row, `supercharge`, is on the table).
#   --difficulty=0..3  BotProfile tier for BOTH bots. Reaction delay and error rate
#                      only. Default 3, because a clip wants the tier that plays the
#                      whole kit — `combo` is 0.90 at Impossible and 0.10 at Easy,
#                      and the combo weight is the CLIP dial as much as the
#                      difficulty one.
#   --seconds=N        maximum length of the SAVED clip. Default 14.
#   --fps=N            saved frames per second. Default 30 (every 2nd frame at 60).
#   --hp=N             the shared HP pool `BotMatch.CLASS_VITALITY` scales per class.
#                      Default 260 — measured: at 190 with two Impossible bots a bout
#                      resolves in about six seconds, which is a highlight but not a
#                      fight. 260 buys the approach-exchange-finish shape.
#   --round=N          game-seconds before the bout is decided on the health bars.
#   --patience=N       seconds to wait for the fight to catch before giving up and
#                      rolling anyway. Default 12.
#   --tail=N           seconds of clip after the match is decided. Default 1.8 —
#                      long enough to hold the freeze AND the result card, which are
#                      the two frames anybody actually shares.
#   --width= --height= RENDER SIZE. Default 1920x1080. See the note below.
#   --out=NAME         subfolder under user://clips.
#
# ---------------------------------------------------------------------------
# WHY THIS FILMS `BotMatch` AND NOT `VersusArena` DIRECTLY.
#
# It used to set the arena's showcase statics itself and film the bare exhibition
# stage. That stage has no win condition — it is a SPARRING LOOP by design, and
# separately its fighters could not die at all (`Hero._die` heals to full outside a
# run; see the header of `scripts/combat/BotMatch.gd` for the full three-cause
# diagnosis). So every clip it produced ran to its frame budget and ended wherever
# the budget ran out, which is why `--seconds` was doing the job a KO should.
#
# `BotMatch` is where the match spine now lives: mirrored footing, per-class health,
# health-bar plates, a decisive end, a freeze on the killing frame and a result card.
# Filming it means the clip and the thing the maker watches from Lobby → Watch Bots
# are THE SAME FIGHT, framed the same way, ending the same way — which was always the
# stated point of having a watchable mode at all.
#
# ---------------------------------------------------------------------------
# RESOLUTION, AND WHY IT COSTS NOTHING TO RAISE IT.
#
# This project's design viewport is 640x360 with `stretch/mode="canvas_items"` and
# `stretch/aspect="expand"`. That is a CONTENT scale, not a render scale: the window
# can be any size and the game lays itself out against the same 640x360-ish box, so
# raising the render size gives genuinely sharper frames of an IDENTICAL composition.
# Nothing about the game's design viewport changes and no framing constant moves —
# `ClipDirector` reads `get_visible_rect()`, which stays at the content scale.
#
# The default was the 1366x768 window override, i.e. whatever the GUI binary happened
# to open, and every frame then went through a downscale to 720 in the encoder. 1920
# wide rendered and LANCZOS-ed down to 720 is visibly cleaner than 1366 down to 720,
# and 16:9 exactly matches 640x360 so there is NO letterboxing at either size.
#
# ⚠ THE REAL VIDEO CEILING IS NOT HERE. It is that ffmpeg is not installed on this
# machine, so the only single-file output anybody can double-click is a palettised
# GIF. See `python-tools/frames_to_gif.py`. Rendering at 1920 means the frames are
# ready for a real encoder the day there is one.
#
# ⚠ NOTHING HERE HELPS A BOT. Both fighters get the same stock BotController +
# BotBrain + BotProfile the game ships, at the same tier, on mirrored footing, seeing
# only what a human sees. The only things this tool changes are WHO is on the stage,
# how big the shared HP pool is, and where the camera is. A clip of a rigged fight is
# worthless for finding bugs and dishonest as marketing.
extends SceneTree

const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"

const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

var _class_a: int = 6
var _class_b: int = 5
var _difficulty: int = 3
var _seconds: float = 14.0
var _fps: int = 30
var _hp: int = 260
var _round: float = 40.0
var _patience: float = 12.0
var _tail: float = 1.8
var _out: String = "directed"
var _width: int = 1920
var _height: int = 1080

var _dir: String = ""
var _match: Node = null
var _director: Object = null
var _saved: int = 0
var _walked: int = 0
var _rolling: bool = false
var _roll_started_at: float = 0.0
var _decided_at: float = -1.0


func _initialize() -> void:
	_parse_args()
	_dir = "user://clips/%s" % _out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	_clear_dir()
	_set_render_size()
	# Statics BEFORE the scene instantiates — `BotMatch._ready` reads them all, then
	# sets the arena's own statics from them.
	#
	# ⚠ REACHED BY PATH, NEVER BY `class_name`. Naming `BotMatch` here would compile
	# it — and its whole dependency chain, which touches the `Sfx` / `Rank` / `Juice`
	# autoloads — at THIS script's parse time, before the main loop has registered any
	# autoload. The result is "Compile Error: Identifier not found: Sfx", a scene that
	# silently fails to build, and a capture of an empty room. Measured, not assumed:
	# the first run of `bot_clip_capture` did exactly that.
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	if script != null:
		script.set("class_a", _class_a)
		script.set("class_b", _class_b)
		script.set("difficulty", _difficulty)
		script.set("fighter_hp", _hp)
		script.set("round_seconds", _round)
		# A clip ends where the match does. An auto-rematch would reload the scene out
		# from under the capture and the tail would be the NEXT fight's opening.
		script.set("auto_rematch", false)
	_match = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(_match)
	print("[clip] %s vs %s  tier=%d  hp=%d  %dx%d  up to %.0fs at %d fps -> %s"
		% [_name(_class_a), _name(_class_b), _difficulty, _hp, _width, _height,
			_seconds, _fps, ProjectSettings.globalize_path(_dir)])
	_run()


## ⚠ WIPE THE OLD FRAMES FIRST, and this is not tidiness.
##
## The encoder globs `*.png` in name order. A short run into a folder that held a
## long one leaves the previous clip's tail behind, so a 146-frame KO encodes as a
## 480-frame GIF whose last 334 frames are somebody else's fight. Measured — the
## first run of this tool into an existing folder produced exactly that.
func _clear_dir() -> void:
	var abs: String = ProjectSettings.globalize_path(_dir)
	var d: DirAccess = DirAccess.open(abs)
	if d == null:
		return
	for f: String in d.get_files():
		if f.ends_with(".png"):
			d.remove(f)


## Raise the render size without touching the design viewport. See the header.
##
## The window is resized AND the root viewport is told the same size, because on some
## platforms the second does not follow the first inside the same frame — and a
## capture that reads `root.get_texture()` at the old size silently writes the old
## resolution while reporting the new one.
func _set_render_size() -> void:
	var want := Vector2i(maxi(_width, 320), maxi(_height, 180))
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_size(want)
	root.size = want


## ⚠ THE DIRECTOR IS FETCHED AFTER THE FIRST FRAME, NOT IN `_initialize`.
##
## A node added while the SceneTree is still inside `_initialize` does not get its
## `_ready` synchronously — so the scene has not built its fighters, its camera or its
## director, and `clip_director()` returns null. Asking once at construction time
## therefore always answers "no director", and the tool silently degrades to a fixed
## capture that rolls from frame one and reports `heat 0.00` for its whole length.
## MEASURED, not assumed: the first run of this tool did exactly that, and
## `tools/bot_sim.gd` carries the same note about the same trap for the same reason.
func _bind_director() -> void:
	if _director != null or _match == null:
		return
	for child: Node in _match.get_children():
		if child.has_method("clip_director"):
			_director = child.call("clip_director")
			break
	if _director == null:
		print("[clip] ⚠ no ClipDirector — the arena did not build one. "
			+ "Framing falls back to the plain pair camera and the clip will roll "
			+ "from frame one.")


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
			"a": _class_a = clampi(int(value), 0, CLASS_NAMES.size() - 1)
			"b": _class_b = clampi(int(value), 0, CLASS_NAMES.size() - 1)
			"difficulty": _difficulty = clampi(int(value), 0, 3)
			"seconds": _seconds = maxf(float(value), 1.0)
			"fps": _fps = clampi(int(value), 5, 60)
			"hp": _hp = maxi(int(value), 40)
			"round": _round = maxf(float(value), 5.0)
			"patience": _patience = maxf(float(value), 0.0)
			"tail": _tail = maxf(float(value), 0.0)
			"width": _width = maxi(int(value), 320)
			"height": _height = maxi(int(value), 180)
			"out": _out = value


func _name(id: int) -> String:
	return CLASS_NAMES[id] if id >= 0 and id < CLASS_NAMES.size() else "?"


## Walk the fight one rendered frame at a time.
##
## ⚠ `await RenderingServer.frame_post_draw` EVERY frame, not once at the end.
## Reading `root.get_texture().get_image()` before the draw has completed hands back
## the PREVIOUS frame — which, over a sequence, shifts the whole clip one frame out
## of step with the beats it exists to show.
func _run() -> void:
	# Every Nth rendered frame is saved. The engine runs at 60; --fps=30 saves every
	# second frame, --fps=20 every third.
	var every: int = maxi(int(round(60.0 / float(_fps))), 1)
	var max_saved: int = int(_seconds * float(_fps))
	# Hard ceiling on frames WALKED, so a fight that never catches (or a bug that
	# freezes one) cannot hang the tool forever.
	var max_walk: int = int((_patience + _seconds + _tail + 8.0) * 60.0)
	while _saved < max_saved and _walked < max_walk:
		await process_frame
		await RenderingServer.frame_post_draw
		_walked += 1
		if _walked == 2:
			_bind_director()   # the scene's _ready has run by now — see _bind_director
		var now: float = float(_walked) / 60.0
		if _decided_at < 0.0 and _match_over():
			_decided_at = now
			print("[clip] the match resolved at %.1fs — %s" % [now, _outcome()])
		if not _rolling:
			# ROLL WHEN THE FIGHT CATCHES, or when patience runs out — an unexciting
			# clip is still better than no clip, and "it never got hot" is itself a
			# finding worth seeing rather than a silent empty folder.
			if _is_hot() or now >= _patience:
				_rolling = true
				_roll_started_at = now
				print("[clip] rolling at %.1fs (%s)"
					% [now, "the fight caught" if _is_hot() else "out of patience"])
			else:
				continue
		if _walked % every != 0:
			continue
		var img: Image = root.get_texture().get_image()
		if img == null:
			continue
		img.save_png("%s/f%04d.png" % [_dir, _saved])
		_saved += 1
		if _saved % 30 == 0:
			print("[clip] saved %d frames (%.1fs of clip, heat %.2f)"
				% [_saved, float(_saved) / float(_fps), _heat()])
		# STOP ON THE RESULT, plus a tail long enough to hold the freeze and the
		# card. A clip that keeps rolling past the ending is mostly a still frame; a
		# clip that cuts before the card throws away its own payoff.
		if _decided_at >= 0.0 and now - _decided_at >= _tail:
			print("[clip] result held — closing the shot")
			break
	_write_manifest()
	print("[clip] DONE — %d frames (%.1fs) in %s"
		% [_saved, float(_saved) / float(_fps), ProjectSettings.globalize_path(_dir)])
	if _saved == 0:
		printerr("[clip] NO FRAMES WRITTEN. If this was run with --headless, that is "
			+ "why: the dummy renderer draws nothing. Use the GUI binary.")
	quit(0)


# ---- questions, each guarded so a missing director or scene degrades rather than
# crashes. Without a director the tool still works — it simply rolls from frame one
# and runs to the frame budget.

func _is_hot() -> bool:
	return _director != null and bool(_director.call("is_hot"))


func _heat() -> float:
	return 0.0 if _director == null else float(_director.call("heat"))


func _match_over() -> bool:
	if _match == null or not is_instance_valid(_match) or not _match.has_method("match_over"):
		# Fall back to the director's own latch, which still catches a decisive beat
		# on a stage that has no match spine.
		return _director != null and bool(_director.call("saw_knockdown"))
	return bool(_match.call("match_over"))


func _result() -> Dictionary:
	if _match == null or not is_instance_valid(_match) or not _match.has_method("result"):
		return {}
	return _match.call("result") as Dictionary


func _outcome() -> String:
	var r: Dictionary = _result()
	return "%s %s" % [String(r.get("outcome", "?")), String(r.get("winner", ""))]


## The clip's own paperwork, beside its frames. What was shot, how, who won, and what
## the director thought happened — enough to re-shoot it or to cut it down without
## watching it back frame by frame.
func _write_manifest() -> void:
	var payload: Dictionary = {
		"matchup": "%s_vs_%s" % [_name(_class_a), _name(_class_b)],
		"class_a": _class_a, "class_b": _class_b,
		"difficulty": _difficulty, "hp": _hp,
		"render": "%dx%d" % [_width, _height],
		"fps": _fps, "frames": _saved,
		"seconds": snappedf(float(_saved) / float(_fps), 0.01),
		"rolled_at": snappedf(_roll_started_at, 0.01),
		"decided_at": snappedf(_decided_at, 0.01),
		"result": _result(),
		"director": {} if _director == null else _director.call("report"),
		"encode": "python python-tools/make_clip.py --no-shoot --a %d --b %d --out %s"
			% [_class_a, _class_b, _out],
		"godot": Engine.get_version_info().get("string", ""),
	}
	var f: FileAccess = FileAccess.open("%s/clip.json" % _dir, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
