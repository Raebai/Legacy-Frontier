class_name PerfOverlay
extends CanvasLayer
## THE NUMBERS, ON THE DEVICE. Autoloaded as `Perf`; hidden until asked for.
##
## Before this file the project had NO performance instrumentation in game code
## at all — not one `Performance.get_monitor` call outside a vendored addon. That
## is survivable on a desktop with headroom to spare and is not survivable on the
## target device (a three-year-old mid-range Android), because the two failure
## modes that matter there are both INVISIBLE to the naked eye until they are
## severe:
##
##   * A frame-time SPIKE. Average FPS hides it completely — a 16 ms average with
##     one 90 ms hitch per second reads as "60 fps" on any counter that reports a
##     mean, and reads as a stutter to the player. WORST is therefore the headline
##     number here, not FPS.
##   * THERMAL THROTTLE. The phone is fine for ninety seconds and then quietly
##     halves its clocks. You cannot see that in a single reading; you see it as
##     WORST drifting upward over a few minutes with nothing on screen having
##     changed. Leave the overlay up during a long climb and that drift IS the
##     measurement.
##
## Toggle: F3 on a desktop, or a THREE-FINGER TAP on a touchscreen. The finger
## gesture is not a flourish — the phone has no F3, and an instrument you cannot
## reach on the device you are profiling is not an instrument. `toggle()` is also
## public so a settings row can drive it once someone owns PauseMenu.
##
## Deliberately cheap: it samples at UPDATE_HZ rather than per frame, and does
## nothing whatsoever while hidden, so leaving it in the shipping build costs an
## invisible node and a `visible` check.

## Sampling rate. Fast enough to watch a number move, slow enough that the
## overlay is never a meaningful share of what it is measuring.
const UPDATE_HZ: float = 4.0
## Rolling window for the WORST frame-time reading. One second is short enough to
## still feel attributable to what you just did.
const WORST_WINDOW: float = 1.0
## The spec's live-entity ceiling, shown alongside the live count so the reading
## has a target to be judged against instead of being a bare number.
const ENTITY_CEILING: int = 25
## Frame-time bands, in milliseconds. 60 fps is 16.7 ms; 30 fps is 33.3 ms. The
## target device is expected to hold 30, so amber is "missed 60" and red is
## "missed 30" — the point at which the game is visibly stuttering.
const MS_GOOD: float = 16.7
const MS_WARN: float = 33.3

## Groups counted as "live entities". Note `hero` and not `player`: the tower
## stack uses `hero`, the parked v0.0 hub used `player`, and mixing them up is a
## documented way to make a mechanic silently do nothing in this codebase.
const ENTITY_GROUPS: Array[StringName] = [&"hero", &"enemy"]

var _label: Label
var _panel: ColorRect
var _accum: float = 0.0
var _worst_ms: float = 0.0
var _worst_age: float = 0.0
var _touches: Dictionary = {}


func _ready() -> void:
	layer = 200  # above the HUD (50/60/100) and the impact frames (90)
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep reading through pause + hit-stop
	visible = false
	_panel = ColorRect.new()
	_panel.color = Color(0.03, 0.03, 0.05, 0.62)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(6, 6)
	_panel.size = Vector2(196, 118)
	add_child(_panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(12, 9)
	_label.add_theme_font_size_override(&"font_size", 10)
	add_child(_label)
	# The most diagnostic thing in the project. An autoload, so it outlives every scene
	# — which is exactly why it registers once here rather than being hunted down by
	# whatever host happens to be filming. See `scripts/combat/Cinematic.gd`.
	Cinematic.mark(self)
	_sample()


## Show/hide the overlay. Public so a PauseMenu row can drive it without this
## file needing to know PauseMenu exists.
##
## ⚠ REFUSES WHILE CINEMATIC MODE IS ON. F3 and the three-finger tap are both global
## and both reach this while a clip is rolling; without the guard the one key most
## likely to be pressed by reflex would put a frame-time panel into the recording.
func toggle() -> void:
	if not Cinematic.shows_chrome():
		return
	visible = not visible
	if visible:
		_worst_ms = 0.0
		_worst_age = 0.0
		_sample()


func _input(event: InputEvent) -> void:
	# Raw key rather than a named action ON PURPOSE. Every gameplay input in this
	# project goes through the action map precisely so a touch layer can drive it
	# (the mobile-first rule), and a debug overlay is not gameplay — giving it an
	# action would put a dev tool in the same list the touch UI is generated from.
	# The touchscreen half of the toggle is handled below instead.
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F3:
			toggle()
		return
	# THREE-FINGER TAP: the only way to reach this on the device it exists for.
	# Three because one and two are gameplay (the twin-stick), so a third finger
	# cannot be produced by playing.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = true
			if _touches.size() >= 3:
				_touches.clear()
				toggle()
		else:
			_touches.erase(t.index)


func _process(delta: float) -> void:
	if not visible:
		return
	# WORST is tracked every frame even though the display refreshes at UPDATE_HZ —
	# sampling the spike at 4 Hz would miss it, which is the entire point of it.
	var ms: float = delta * 1000.0
	_worst_age += delta
	if ms > _worst_ms or _worst_age >= WORST_WINDOW:
		if _worst_age >= WORST_WINDOW:
			_worst_ms = ms
			_worst_age = 0.0
		else:
			_worst_ms = ms
	_accum += delta
	if _accum < 1.0 / UPDATE_HZ:
		return
	_accum = 0.0
	_sample()


func _sample() -> void:
	if _label == null:
		return
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var bodies: int = int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS))
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var entities: int = live_entity_count()
	_label.text = "\n".join([
		"FPS  %4.0f   worst %5.1fms" % [fps, _worst_ms],
		"cpu  proc %4.1f  phys %4.1f" % [proc_ms, phys_ms],
		"draw %4d   nodes %5d" % [draws, nodes],
		"bodies %3d  vram %6.1fMB" % [bodies, vram_mb],
		"entities %2d / %d" % [entities, ENTITY_CEILING],
		"pool dmg %2d+%-2d  vfx %2d" % [
			DamageNumber.alive_count(), DamageNumber.pooled_count(),
			CombatVfx.pooled_count()],
		"gfx %s" % ("LOW" if TuningConfig.quality_is_low() else "HIGH"),
	])
	# The panel is the only colour signal: green under 60 fps budget, amber under
	# 30, red past it. Colouring the text instead was tried on paper and rejected —
	# a wall of coloured monospace is harder to read at a glance than one tinted box.
	var col := Color(0.10, 0.30, 0.12, 0.62)
	if _worst_ms > MS_WARN:
		col = Color(0.36, 0.06, 0.08, 0.66)
	elif _worst_ms > MS_GOOD:
		col = Color(0.34, 0.26, 0.04, 0.64)
	_panel.color = col


## Live fighters on the floor, against which ENTITY_CEILING is judged. Static so
## the stress harness in tools/ can assert the same number the overlay shows —
## one definition of "an entity", not two that drift apart.
static func live_entity_count() -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var n: int = 0
	for g: StringName in ENTITY_GROUPS:
		n += tree.get_nodes_in_group(g).size()
	return n
