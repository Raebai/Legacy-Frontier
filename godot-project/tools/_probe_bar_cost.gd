# READ-ONLY PROBE (safe to delete). What does the ability bar COST to draw right now?
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_bar_cost.gd
#
# ⚠ THE FIRST VERSION OF THIS PROBE LIED. It measured the bar inside VersusArena and
# reported the bar making draw calls go DOWN — the live fight's variance is an order of
# magnitude larger than the thing being measured. So: an EMPTY scene, one real Hero for
# the contract, and N copies of the bar, timed against N = 0. Per-bar cost = the slope.
#
# ⚠ Performance.TIME_PROCESS EXCLUDES _draw, so wall-clock frame time is the only
# honest instrument here. Engine.max_fps is forced to 0 so nothing clamps the loop.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const COPIES: int = 60
const SAMPLES: int = 240
const WARMUP: int = 60

var _bars: Array[Node] = []


func _initialize() -> void:
	Engine.max_fps = 0
	_run()


func _run() -> void:
	var hero: Node = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	for i: int in 30:
		await process_frame
	if not hero.has_method("ability_hud_state"):
		print("_probe_bar_cost: hero has no contract")
		quit(1)
		return
	var slots: int = (hero.call("ability_hud_state") as Array).size()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	for i: int in COPIES:
		var bar := AbilityBar.new()
		layer.add_child(bar)
		_bars.append(bar)
	var with_bars: float = await _sample()
	for b: Node in _bars:
		(b as CanvasItem).visible = false
	var without: float = await _sample()
	var per_bar_us: float = (with_bars - without) * 1000.0 / float(COPIES)
	print("slots drawn per bar : %d" % slots)
	print("%d bars   : %.3f ms/frame" % [COPIES, with_bars])
	print("0 bars    : %.3f ms/frame" % without)
	print("PER BAR   : %.1f us/frame  (%.2f%% of a 16.67 ms budget)" % [
		per_bar_us, per_bar_us / 166.7])
	quit(0)


func _sample() -> float:
	for i: int in WARMUP:
		await process_frame
	var t0: int = Time.get_ticks_usec()
	for i: int in SAMPLES:
		await process_frame
	return float(Time.get_ticks_usec() - t0) / float(SAMPLES) / 1000.0
