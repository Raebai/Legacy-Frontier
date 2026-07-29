# Run: godot --headless --path godot-project --script tools/boot_check.gd -- <res://scene> [frames]
#
# DOES THE SCENE ACTUALLY BOOT? The slice suites drive scripts through seams; this
# instantiates the PACKED scene the maker's F5 loads, lets it live for a stretch of
# real frames, and reports what is on the stage afterwards. That catches the class
# of break a seam test cannot see — a .tscn that no longer matches its script, a
# _ready that throws, a node that frees itself on frame two.
#
# Scenes are reached BY PATH (never by `class_name`), the capture-tool idiom: a
# --script harness has no autoloads registered, so naming a class whose dependency
# chain touches one is a compile error before a single frame runs.
extends SceneTree

const DEFAULT_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const DEFAULT_FRAMES: int = 60

var _frames_left: int = DEFAULT_FRAMES
var _started: bool = false
var _scene_path: String = DEFAULT_SCENE
var _scene: Node = null
## Set true by _boss_rush if the caller asked for the tower arena's boss rush.
var _boss_rush: bool = false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_read_args()
		if _boss_rush:
			var arena: GDScript = load("res://scripts/combat/Arena.gd") as GDScript
			if arena != null:
				arena.set("boss_rush", true)
		var packed: PackedScene = load(_scene_path) as PackedScene
		if packed == null:
			printerr("FAIL: %s did not load as a PackedScene" % _scene_path)
			quit(1)
			return true
		_scene = packed.instantiate()
		root.add_child(_scene)
		print("[boot] %s instantiated" % _scene_path)
		return false
	_frames_left -= 1
	if _frames_left > 0:
		return false
	_report()
	quit(0)
	return true


func _read_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--boss":
			_boss_rush = true
		elif a.begins_with("res://"):
			_scene_path = a
		elif a.is_valid_int():
			_frames_left = maxi(int(a), 1)


func _report() -> void:
	var alive: bool = _scene != null and is_instance_valid(_scene) \
		and not _scene.is_queued_for_deletion()
	print("[boot] survived %d frames: root=%s heroes=%d enemies=%d bosses=%d" % [
		DEFAULT_FRAMES if _frames_left <= 0 else _frames_left,
		"alive" if alive else "GONE",
		get_nodes_in_group("hero").size(),
		get_nodes_in_group("enemy").size(),
		get_nodes_in_group("boss").size(),
	])
	if not alive:
		printerr("FAIL: the scene freed itself during boot")
	else:
		print("boot check: OK")
