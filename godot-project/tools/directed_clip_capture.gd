# THE DIRECTED CLIP ENGINE — renders a bot-vs-bot fight as a PNG frame sequence
# that starts where the fight starts, follows the action, and stops on the KO.
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
#   --hp=N             HP per fighter. Default 190 — lower than the 320 the showcase
#                      normally uses, because a clip needs the fight to END.
#   --patience=N       seconds to wait for the fight to catch before giving up and
#                      rolling anyway. Default 12.
#   --tail=N           seconds of clip after a knockdown. Default 1.6.
#   --ringout=1        keep the stage's Smash damage-%/ring-out model. OFF by
#                      default: under it a hit accumulates damage-% instead of
#                      draining HP, and a measured 65-second capture ended with both
#                      fighters past 200% and nobody down. A clip has to END.
#   --out=NAME         subfolder under user://clips.
#
# ---------------------------------------------------------------------------
# WHAT THIS DOES THAT `bot_clip_capture.gd` DOES NOT, and why both exist.
#
# The older tool is a FIXED capture: warm up N frames, then save every Nth for a
# fixed count, with the arena's plain pair-framing camera. It is deterministic and
# it is the right tool when you want a known-length sample of a known matchup.
#
# This one is DIRECTED. `ClipDirector` scores the live board every frame — damage in
# the last second, spells in flight, armed telegraphs, how close the fighters are —
# and this tool uses that to decide THREE things the fixed tool cannot:
#   · WHEN TO ROLL. Waits for `is_hot()` instead of a frame count, so the clip opens
#     on an exchange rather than on two stick figures walking toward each other.
#   · WHERE TO POINT. The director owns the camera and leans the framing toward the
#     fighter who just took damage and toward the live spell geometry, so the payoff
#     lands in the middle of the picture instead of at the edge of it.
#   · WHEN TO STOP. Ends `--tail` seconds after the knockdown. The first capture
#     ever run in this project shot 400 frames and spent 340 of them on a corpse.
#
# It also writes `clip.json` beside the frames: the matchup, the settings, and the
# director's own beat list (when it caught, peak heat and when, when the KO landed),
# so a clip can be cut down or re-shot without re-watching it.
#
# ⚠ NOTHING HERE HELPS A BOT. Both fighters get the same stock BotController +
# BotBrain + BotProfile the game ships, at the same tier, seeing only what a human
# sees. The only things this tool changes are WHO is on the stage, how much HP they
# carry (applied to BOTH, so it is a clip-length knob and never an advantage), and
# where the camera is. A clip of a rigged fight is worthless for finding bugs and
# dishonest as marketing.
extends SceneTree

const ARENA_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"

const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

var _class_a: int = 6
var _class_b: int = 5
var _difficulty: int = 3
var _seconds: float = 14.0
var _fps: int = 30
var _hp: int = 190
var _patience: float = 12.0
var _tail: float = 1.6
var _out: String = "directed"
## Keep the stage's ring-out model? OFF by default so the fight resolves on HP.
var _ringout: bool = false

var _dir: String = ""
var _arena: Node = null
var _director: Object = null
var _saved: int = 0
var _walked: int = 0
var _rolling: bool = false
var _roll_started_at: float = 0.0


func _initialize() -> void:
	_parse_args()
	_dir = "user://clips/%s" % _out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	# Statics BEFORE the scene instantiates — `VersusArena._ready` reads them to
	# decide which of its three modes it is building and who is in it.
	#
	# ⚠ REACHED BY PATH, NEVER BY `class_name`. Naming `VersusArena` here would
	# compile it — and its whole dependency chain, which touches the `Sfx` / `Rank` /
	# `Juice` autoloads — at THIS script's parse time, before the main loop has
	# registered any autoload. The result is "Compile Error: Identifier not found:
	# Sfx", a scene that silently fails to build, and a capture of an empty room.
	# Measured, not assumed: the first run of `bot_clip_capture` did exactly that.
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script != null:
		arena_script.set("free_play", false)
		arena_script.set("showcase_a", _class_a)
		arena_script.set("showcase_b", _class_b)
		arena_script.set("showcase_difficulty", _difficulty)
		arena_script.set("showcase_directed", true)
		arena_script.set("showcase_hp_override", _hp)
		# HP DEATH, NOT RING-OUT. See `VersusArena.showcase_ringout`: under the Smash
		# model a hit accumulates damage-% rather than draining HP, and a measured
		# 65-second capture ended with both fighters past 200% and neither down. A
		# clip has to END.
		arena_script.set("showcase_ringout", _ringout)
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(_arena)
	print("[clip] %s vs %s  tier=%d  hp=%d  up to %.0fs at %d fps -> %s"
		% [_name(_class_a), _name(_class_b), _difficulty, _hp, _seconds, _fps,
			ProjectSettings.globalize_path(_dir)])
	_run()


## ⚠ THE DIRECTOR IS FETCHED AFTER THE FIRST FRAME, NOT IN `_initialize`.
##
## A node added while the SceneTree is still inside `_initialize` does not get its
## `_ready` synchronously — so `VersusArena._ready` has not run yet, the arena has
## not built its fighters, its camera or its director, and `clip_director()` returns
## null. Asking once at construction time therefore always answers "no director",
## and the tool silently degrades to a fixed capture that rolls from frame one and
## reports `heat 0.00` for its whole length. MEASURED, not assumed: the first run of
## this tool did exactly that, and `tools/bot_sim.gd` carries the same note about
## the same trap for the same reason.
func _bind_director() -> void:
	if _director != null or _arena == null:
		return
	if not _arena.has_method("clip_director"):
		return
	_director = _arena.call("clip_director")
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
			"hp": _hp = maxi(int(value), 20)
			"patience": _patience = maxf(float(value), 0.0)
			"tail": _tail = maxf(float(value), 0.0)
			"ringout": _ringout = value != "0"
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
	var max_walk: int = int((_patience + _seconds + _tail + 4.0) * 60.0)
	while _saved < max_saved and _walked < max_walk:
		await process_frame
		await RenderingServer.frame_post_draw
		_walked += 1
		if _walked == 2:
			_bind_director()   # the arena's _ready has run by now — see _bind_director
		var now: float = float(_walked) / 60.0
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
		# STOP ON THE KO, plus a short tail. A clip that keeps rolling past the
		# knockdown is mostly a still frame of a corpse.
		if _knocked_down() and _since_ko() >= _tail:
			print("[clip] knockdown — closing the shot")
			break
	_write_manifest()
	print("[clip] DONE — %d frames (%.1fs) in %s"
		% [_saved, float(_saved) / float(_fps), ProjectSettings.globalize_path(_dir)])
	if _saved == 0:
		printerr("[clip] NO FRAMES WRITTEN. If this was run with --headless, that is "
			+ "why: the dummy renderer draws nothing. Use the GUI binary.")
	quit(0)


# ---- director questions, each guarded so a missing director degrades rather than
# crashes. Without one the tool still works — it simply rolls from frame one and
# runs to the frame budget, i.e. it becomes `bot_clip_capture` with a manifest.

func _is_hot() -> bool:
	return _director != null and bool(_director.call("is_hot"))


func _heat() -> float:
	return 0.0 if _director == null else float(_director.call("heat"))


func _knocked_down() -> bool:
	return _director != null and bool(_director.call("saw_knockdown"))


func _since_ko() -> float:
	return 0.0 if _director == null else float(_director.call("seconds_since_knockdown"))


## The clip's own paperwork, beside its frames. What was shot, how, and what the
## director thought happened — enough to re-shoot it or to cut it down without
## watching it back frame by frame.
func _write_manifest() -> void:
	var payload: Dictionary = {
		"matchup": "%s_vs_%s" % [_name(_class_a), _name(_class_b)],
		"class_a": _class_a, "class_b": _class_b,
		"difficulty": _difficulty, "hp": _hp,
		"fps": _fps, "frames": _saved,
		"seconds": snappedf(float(_saved) / float(_fps), 0.01),
		"rolled_at": snappedf(_roll_started_at, 0.01),
		"director": {} if _director == null else _director.call("report"),
		"encode": "python python-tools/frames_to_gif.py %s --fps %d --width 720"
			% [ProjectSettings.globalize_path(_dir), _fps],
		"godot": Engine.get_version_info().get("string", ""),
	}
	var f: FileAccess = FileAccess.open("%s/clip.json" % _dir, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
