extends Node2D
## Non-headless demo + screenshot harness for the stick-fight combat core.
## Instances the Arena, drives the REAL Hero input path with scripted presses,
## grabs the rendered viewport to PNGs, then quits.
## MUST run WITHOUT --headless (headless uses the dummy renderer -> blank frames):
##   godot --path godot-project res://tools/DemoCapture.tscn
## Screenshots are written to the scratchpad so the parent agent can read them.

# Screenshots land in `user://demo/` — resolves to
# %APPDATA%\Godot\app_userdata\Legacy Frontier\demo\ on Windows.
# The harness prints the globalized OS path on startup so you can find them.
const OUT_DIR: String = "user://demo"
const ARENA: PackedScene = preload("res://scenes/combat/Arena.tscn")
const PROP: PackedScene = preload("res://scenes/combat/DestructibleProp.tscn")
const BLAST: PackedScene = preload("res://scenes/combat/BlastSpell.tscn")
const QUIT_AT: float = 5.4

var _crate_spawned: bool = false
var _crate_blasted: bool = false
var _crate_pos: Vector2 = Vector2.ZERO

var _t: float = 0.0
var _shot: int = 0
var _setup_done: bool = false

# Capture timings (seconds) — spread to catch idle, run, cast, melee, blast
# telegraph bloom + detonation, and hopefully a brute's danger circle.
var _cap_times: Array[float] = [
	0.5, 1.3, 1.5, 2.1, 2.3, 2.9, 3.1, 3.7, 3.9, 4.35, 4.5, 4.8, 5.0, 5.15, 5.3,
]
var _cap_i: int = 0

# One-shot input pulses (parallel typed arrays; heterogeneous arrays trip the
# project's warnings-as-errors config).
var _pulse_times: Array[float] = [1.0, 1.8, 2.6, 3.4, 4.1]
var _pulse_acts: Array[String] = ["cycle_element", "cycle_element", "cycle_element", "cycle_colourway", "cycle_colourway"]
var _pulse_done: Array[bool] = []

var _rel_times: Array[float] = []
var _rel_acts: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	add_child(ARENA.instantiate())
	_pulse_done.resize(_pulse_times.size())
	_pulse_done.fill(false)
	Input.action_press("cast")  # hold cast: auto-fires at the nearest enemy
	# element showcase: hero stays put so the aura + bolt colour reads clearly
	print("[DEMO] harness started, out=", ProjectSettings.globalize_path(OUT_DIR))


func _spawn_show_crate() -> void:
	var heroes: Array = get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		return
	var hero: Node2D = heroes[0] as Node2D
	_crate_pos = hero.global_position + Vector2(80.0, 0.0)
	var crate: Node2D = PROP.instantiate() as Node2D
	hero.get_parent().add_child(crate)
	crate.global_position = _crate_pos


func _blast_show_crate() -> void:
	var heroes: Array = get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		return
	var hero: Node2D = heroes[0] as Node2D
	var b: Node2D = BLAST.instantiate() as Node2D
	hero.get_parent().add_child(b)
	b.call("detonate_at", _crate_pos)


func _queue_release(at: float, act: String) -> void:
	_rel_times.append(at)
	_rel_acts.append(act)


func _process(delta: float) -> void:
	_t += delta

	# Zoom the combat camera in on the first frame so the stick-figure animation
	# (staff, punch/kick, dash lean) is actually legible in the captures.
	if not _setup_done:
		_setup_done = true
		var cams: Array = get_tree().get_nodes_in_group("combat_camera")
		if not cams.is_empty():
			var cam: Camera2D = cams[0] as Camera2D
			if cam != null:
				cam.zoom = Vector2(2.6, 2.6)

	# Crate destruction showcase: spawn a crate next to the hero, then blast it —
	# shatters into debris + leaves a persistent scorch + crack decal, on camera.
	if not _crate_spawned and _t >= 99.0:
		_crate_spawned = true
		_spawn_show_crate()
	if not _crate_blasted and _t >= 99.0:
		_crate_blasted = true
		_blast_show_crate()

	for i in _pulse_times.size():
		if not _pulse_done[i] and _t >= _pulse_times[i]:
			_pulse_done[i] = true
			Input.action_press(_pulse_acts[i])
			_queue_release(_t + 0.08, _pulse_acts[i])

	var keep_t: Array[float] = []
	var keep_a: Array[String] = []
	for i in _rel_times.size():
		if _t >= _rel_times[i]:
			Input.action_release(_rel_acts[i])
		else:
			keep_t.append(_rel_times[i])
			keep_a.append(_rel_acts[i])
	_rel_times = keep_t
	_rel_acts = keep_a

	if _cap_i < _cap_times.size() and _t >= _cap_times[_cap_i]:
		_cap_i += 1
		_capture()

	if _t >= QUIT_AT:
		print("[DEMO] done, %d shots written" % _shot)
		get_tree().quit()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var tex: ViewportTexture = get_viewport().get_texture()
	if tex == null:
		print("[DEMO] ERROR: null viewport texture")
		return
	var img: Image = tex.get_image()
	if img == null:
		print("[DEMO] ERROR: null image")
		return
	var path: String = "%s/shot%02d.png" % [OUT_DIR, _shot]
	var err: int = img.save_png(path)
	print("[DEMO] shot%02d t=%.2f err=%d size=%dx%d" % [_shot, _t, err, img.get_width(), img.get_height()])
	_shot += 1
