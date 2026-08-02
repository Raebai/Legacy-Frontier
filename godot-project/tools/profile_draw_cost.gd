# Run WITH THE GUI BINARY (a headless run renders nothing and every number below
# is zero or a lie):
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/profile_draw_cost.gd -- ++seconds=6 ++width=1920 ++height=1080
#   optional: ++quality=low   ++scene=res://scenes/combat/Arena.tscn   ++nopost=1
#
# THE MEASUREMENT THIS PROJECT DID NOT HAVE.
#
# Every perf figure in docs/mobile-export.md comes from `Performance.TIME_PROCESS`
# and `TIME_PHYSICS_PROCESS`. Both EXCLUDE `_draw`. That was measured, not assumed:
# 40k draw primitives moved TIME_PROCESS by 0.0000 ms while wall-clock moved 9.2 ms.
# This game draws essentially all of itself procedurally in `_draw()` — 78 scripts
# implement it — so the existing numbers have been measuring the smaller half of
# the frame and calling it the frame.
#
# ── WHY THIS ASSERTS COUNTS AND NOT MILLISECONDS ─────────────────────────────
# Same reason as tools/slice_test_perf_budget.gd and tools/profile_magic_circle.gd:
# wall-clock on this machine is non-monotonic by ~20x for sub-millisecond work,
# because a frame absorbs extra work into idle time until it crosses the pacing
# budget and then reports it all at once. So this tool reports two DETERMINISTIC
# work counters and no headline time:
#
#   REDRAWS/SEC per class — counted off `CanvasItem`'s own `draw` signal, which
#     fires exactly once per `_draw()` invocation. This is the CPU side: how many
#     times per second each class rebuilds its command list. It is the number that
#     `queue_redraw()` policy controls and the only one a script can lower without
#     changing the picture.
#
#   PRIMITIVES per class — the renderer's own `RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME`,
#     attributed by ABLATION: freeze the scene, hide every instance of one class,
#     read the drop. This is the GPU side: what gets rasterised every frame whether
#     or not anything redrew.
#
# The two multiply into the only ranking that means anything —
#     CPU work rate  ~  redraws/sec x primitives-per-redraw
#     GPU work rate  ~  primitives-in-frame x refresh
# — and a system can be top of one table and absent from the other. `ArenaTerrain`
# draws once, ever, and is pure GPU. `CharacterRig` redraws 60 times a second on
# every fighter and is nearly all CPU. Reading one table alone gets the wrong answer.
#
# ── WHY THE ABLATION PASS PAUSES THE TREE ────────────────────────────────────
# Primitives-in-frame is only a repeatable number if the scene is not moving. In a
# live sandbox fight it swings by thousands between frames (a spell spawns, a body
# dies) and a hide/show delta of a few hundred is invisible inside that. Paused,
# canvas items keep their last command buffers and the renderer re-issues them
# unchanged, so the count is flat to +-0 and a hide is attributable to the byte.
# The redraw census therefore runs LIVE (rates need motion) and the primitive
# census runs PAUSED (attribution needs stillness). Two phases, on purpose.
#
# ⚠ WHAT THIS STILL CANNOT SEE. Fill cost. Chromatic aberration, the vignette, the
# grain, MSAA resolve and the framebuffer mipmap chain are per-PIXEL work that
# issues ~2 primitives total and therefore does not appear in either table above.
# `tools/profile_fill_cost.gd` is the A/B for those, and it is a wall-clock tool
# with all the caveats that implies.
#
# Test-idiom note: a HARNESS, not an assertion suite — no pass/fail sentinels, it
# prints tables for a human. `tools/slice_test_draw_budget.gd` is the suite.
extends SceneTree

const DEFAULT_SCENE: String = "res://scenes/combat/Arena.tscn"
## Seconds discarded before anything is counted. SECONDS AND NOT FRAMES, because
## the sandbox trickles its crowd in on a 1.2 s timer (Arena.SANDBOX_SPAWN_INTERVAL)
## and a frame count settles in 0.6 s on a fast machine — which measured a two-body
## stage and called it the fight. Long enough for the arena to reach its steady
## ~5-enemy population.
const SETTLE_SECONDS: float = 9.0
## Frames the paused ablation averages each configuration over. Paused, the count
## is flat, so this is belt-and-braces against a stray one-shot effect expiring.
const ABLATE_FRAMES: int = 6
## Classes with fewer primitives than this are folded into the "rest" row rather
## than given a line each — 60 rows of 12 primitives is not a ranking.
const NOISE_FLOOR: int = 40

var _seconds: float = 6.0
## Extra bodies pushed into the sandbox before measuring. The sandbox idles at 5
## (Arena.TARGET_ENEMY_COUNT); a real wave runs to Encounter.MAX_LIVE_ENTITIES = 25,
## and the whole question is how the frame scales between those two, so a run that
## only ever measures 5 measures the wrong game.
var _crowd: int = 0
var _scene_path: String = DEFAULT_SCENE
var _force_low: bool = false
var _kill_post: bool = false
var _width: int = 1920
var _height: int = 1080

var _root_node: Node = null
var _settled: float = 0.0
var _quality_applied: bool = false
var _elapsed: float = 0.0
var _phase: int = 0            # 0 settle, 1 live census, 2 ablate, 3 done
## script-class name -> draw-signal count during the live window.
var _redraws: Dictionary = {}
## script-class name -> Array[CanvasItem] captured at the census.
var _by_class: Dictionary = {}
var _connected: int = 0
var _frames_live: int = 0
var _frame_ms: PackedFloat64Array = PackedFloat64Array()
## Node class names added during the frame currently being timed. A hitch is far
## more often a node being BUILT than anything being drawn — a spell's first
## instantiation pays a `load()`, a scene tree walk and a shader pipeline compile,
## none of which recur and none of which any per-frame counter attributes to it.
var _born_this_frame: Array[String] = []
## ms -> the classes born in that frame. Only frames over HITCH_MS are kept.
var _hitches: Array = []
## A frame this long is a visible stutter at any refresh rate a human plays at.
const HITCH_MS: float = 12.0


func _initialize() -> void:
	_parse_args()
	# Determinism: the sandbox picks spawn positions and spell jitter off the global
	# RNG, and an unseeded run puts a different crowd in front of the camera each
	# time, which is most of why two runs of a draw census used to disagree.
	seed(20260802)
	if DisplayServer.get_name() == "headless":
		printerr("profile_draw_cost: HEADLESS. The dummy renderer reports zero primitives")
		printerr("  and draws nothing. Re-run with godot-engine/Godot_v4.6.2-stable_win64.exe.")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(_width, _height))
	# UNCAPPED, or the fps line at the bottom of the redraw table reports the
	# monitor's refresh rate and every configuration ties at 16.67 ms — the exact
	# trap already recorded in docs/mobile-export.md.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		printerr("profile_draw_cost: could not load ", _scene_path)
		quit(1)
		return
	_root_node = packed.instantiate()
	root.add_child(_root_node)
	print("[draw] scene=%s window=%dx%d quality=%s post=%s"
		% [_scene_path, _width, _height, "LOW(forced)" if _force_low else "auto",
			"OFF(forced)" if _kill_post else "as-configured"])


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var body: String = arg.trim_prefix("++")
		var bits: PackedStringArray = body.split("=")
		if bits.size() != 2:
			continue
		match bits[0]:
			"seconds": _seconds = maxf(float(bits[1]), 1.0)
			"scene": _scene_path = bits[1]
			"width": _width = maxi(int(bits[1]), 320)
			"height": _height = maxi(int(bits[1]), 180)
			"quality": _force_low = bits[1] == "low"
			"nopost": _kill_post = bits[1] != "0"
			"crowd": _crowd = maxi(int(bits[1]), 0)


func _process(delta: float) -> bool:
	match _phase:
		0:
			if not _quality_applied:
				_quality_applied = true
				_apply_quality()
			_settled += delta
			if _settled >= SETTLE_SECONDS:
				# Phase 4 is "crowding" — a coroutine, so the phase has to change
				# BEFORE the await or `_process` re-enters it every frame while the
				# first call is still suspended and spawns the stage flat.
				_phase = 4
				_fill_crowd()
		1:
			_elapsed += delta
			_frames_live += 1
			_frame_ms.append(delta * 1000.0)
			_note_hitch(delta * 1000.0)
			_born_this_frame.clear()
			if _elapsed >= _seconds:
				_phase = 2
				_report_redraws()
				# ⚠ NEVER `return true` here. A `true` from SceneTree._process quits
				# the loop, and the ablation pass is a coroutine that needs frames to
				# still be happening — the first version of this tool printed the
				# redraw table and exited before the primitive table existed, which
				# looked exactly like the ablation finding nothing.
				_begin_ablation()
	return false


# ------------------------------------------------------------------- quality
func _apply_quality() -> void:
	var t: Node = root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		if _force_low or _kill_post:
			print("[draw] ⚠ Tuning autoload unreachable — quality/post overrides NOT applied")
		return
	if _force_low:
		t.cfg.set(&"graphics_quality", TuningConfig.Quality.LOW)
	if _kill_post:
		t.cfg.set(&"post_process_enabled", false)


# ---------------------------------------------------------------- the crowd
## Push the stage up to `++crowd` bodies through the SHIPPING spawner, not by
## instancing Enemy.tscn by hand — a hand-built body skips `Encounter`'s archetype
## roll, elite roll and rig configuration, and an elite is the single most expensive
## body in the game (EliteMark switches its rig's aura on, which re-runs the whole
## articulated figure once per halo layer). A crowd of hand-made plain chasers would
## therefore be a fixture cheaper than reality.
func _fill_crowd() -> void:
	if _crowd <= 0:
		_begin_live_census()
		_phase = 1
		return
	var enc: Node = _find_encounter(_root_node)
	if enc == null or not enc.has_method("spawn"):
		print("[draw] ⚠ no Encounter found — ++crowd ignored")
		_begin_live_census()
		_phase = 1
		return
	# ⚠ COUNT THE UNBORN. A spawn does not produce a body — it produces a SpawnTell
	# that becomes a body 0.4 s later (Encounter.SPAWN_TELL_LEAD), so the "enemy"
	# group does not move for four hundred milliseconds after a spawn call. A loop
	# that watches only the group therefore sees no progress and keeps asking: the
	# first version of this ran its 200-iteration guard to exhaustion and put 199
	# bodies on a stage whose own cap is 25. Encounter tracks the pending ones for
	# exactly this reason; ask it.
	var guard: int = 0
	while _crowd_size(enc) < _crowd and guard < 64:
		guard += 1
		enc.call("spawn", 0.25, 1.0)
		if _crowd_size(enc) >= _crowd:
			break
	# Let the tells resolve into bodies before anything is counted.
	var wait: float = 0.0
	while wait < 1.2:
		wait += 0.05
		await root.get_tree().create_timer(0.05).timeout
	# KEEP THE CROWD ALIVE for the whole window. Without this the hero and the pit
	# hazards clear the stage within a second or two and the back half of the
	# measurement is a different, emptier experiment from the front half — which is
	# why an earlier ++crowd=25 run reported "0 enemies live" and a 600 fps frame.
	for e: Node in root.get_tree().get_nodes_in_group(&"enemy"):
		if e.get(&"max_hp") != null:
			e.set(&"max_hp", 100000000)
			e.set(&"hp", 100000000)
	print("[draw] crowd: %d enemies live (asked for %d, %d spawn calls, held immortal)"
		% [root.get_tree().get_nodes_in_group(&"enemy").size(), _crowd, guard])
	_begin_live_census()
	_phase = 1


## Live bodies PLUS the ones already promised. See the warning in `_fill_crowd`.
func _crowd_size(enc: Node) -> int:
	var live: int = root.get_tree().get_nodes_in_group(&"enemy").size()
	if enc.has_method("pending_spawn_count"):
		live += int(enc.call("pending_spawn_count"))
	return live


func _find_encounter(n: Node) -> Node:
	if n.get_script() != null and (n.get_script() as Script).resource_path.ends_with("Encounter.gd"):
		return n
	for c: Node in n.get_children():
		var f: Node = _find_encounter(c)
		if f != null:
			return f
	return null


# --------------------------------------------------------------- live census
## Connect to every CanvasItem's `draw` signal. That signal fires once per `_draw()`
## call and nowhere else, so the tally is the redraw rate exactly — not an estimate
## off `queue_redraw` call sites, which lie (two queues in one frame draw once) and
## miss the ones the engine issues itself (a visibility flip, a transform change on
## a Control, a window resize).
func _begin_live_census() -> void:
	_walk_and_connect(_root_node)
	# ⚠ AND EVERY ITEM BORN LATER. A one-shot walk instruments the STAGE and misses
	# every spell, every damage number, every debris chunk and every spawn tell —
	# i.e. it misses the entire transient half of the frame, which is the half the
	# spec's 8-effect ceiling is about. The first run of this tool reported six
	# classes because of exactly that.
	root.get_tree().node_added.connect(_on_node_added)
	print("[draw] live census: %d canvas items instrumented (+ everything spawned) over %.1fs"
		% [_connected, _seconds])


func _on_node_added(n: Node) -> void:
	if _phase != 1:
		return
	# Every node, not just canvas items — a hitch is often a body, an Area2D or an
	# AudioStreamPlayer being built, and filtering to drawables first would hide the
	# very thing this list exists to name.
	_born_this_frame.append(_node_key(n))
	var ci: CanvasItem = n as CanvasItem
	if ci == null:
		return
	_register(ci)


func _node_key(n: Node) -> String:
	var s: Script = n.get_script() as Script
	if s != null and s.resource_path != "":
		return s.resource_path.get_file().get_basename()
	return "(" + n.get_class() + ")"


func _note_hitch(ms: float) -> void:
	if ms < HITCH_MS:
		return
	_hitches.append({"ms": ms, "born": _born_this_frame.duplicate()})


func _report_hitches() -> void:
	if _hitches.is_empty():
		print("  no frame exceeded %.0f ms." % HITCH_MS)
		return
	_hitches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["ms"]) > float(b["ms"]))
	print("  %d frame(s) over %.0f ms:" % [_hitches.size(), HITCH_MS])
	for i: int in mini(_hitches.size(), 10):
		var h: Dictionary = _hitches[i]
		var born: Array = h["born"]
		var tally: Dictionary = {}
		for k: String in born:
			tally[k] = int(tally.get(k, 0)) + 1
		var parts: Array[String] = []
		for k: String in tally.keys():
			parts.append("%s x%d" % [k, int(tally[k])])
		print("    %8.2f ms  built that frame: %s"
			% [float(h["ms"]), "nothing" if parts.is_empty() else ", ".join(parts)])


func _walk_and_connect(n: Node) -> void:
	var ci: CanvasItem = n as CanvasItem
	if ci != null:
		_register(ci)
	for c: Node in n.get_children():
		_walk_and_connect(c)


func _register(ci: CanvasItem) -> void:
	var key: String = _class_key(ci)
	if not _by_class.has(key):
		_by_class[key] = []
		_redraws[key] = 0
	(_by_class[key] as Array).append(ci)
	# `bind` carries the class key so one callable serves every instance.
	ci.draw.connect(_on_item_drew.bind(key))
	_connected += 1


func _on_item_drew(key: String) -> void:
	_redraws[key] = int(_redraws[key]) + 1


## What to call a canvas item in the table. The SCRIPT is the unit of blame — two
## nodes with the same engine class and different scripts are different systems,
## and `get_class()` would file both under `Node2D`.
func _class_key(ci: CanvasItem) -> String:
	var s: Script = ci.get_script() as Script
	if s != null and s.resource_path != "":
		return s.resource_path.get_file().get_basename()
	return "(" + ci.get_class() + ")"


func _report_redraws() -> void:
	var rows: Array = []
	for key: String in _redraws.keys():
		var n: int = int(_redraws[key])
		if n <= 0:
			continue
		var live: int = _live_count(key)
		var seen: int = (_by_class[key] as Array).size()
		rows.append({
			"key": key,
			"draws": n,
			"hz": float(n) / maxf(_elapsed, 0.001),
			"n": live,
			"seen": seen,
			# Per-instance rate is against the number ALIVE, not the number ever seen —
			# a spell that lived 0.3 s of a 5 s window would otherwise report a rate
			# 16x lower than the one it actually ran at while it existed.
			"hz_each": (float(n) / maxf(_elapsed, 0.001)) / maxf(float(live), 1.0),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["hz"]) > float(b["hz"]))
	print("")
	print("══ REDRAWS PER SECOND (the CPU side: how often _draw rebuilds a command list) ══")
	print("  %-26s %10s %6s %6s %10s" % ["class", "draws/s", "live", "seen", "draws/s ea"])
	var total: float = 0.0
	for r: Dictionary in rows:
		total += float(r["hz"])
		if float(r["hz"]) < 1.0:
			continue
		print("  %-26s %10.1f %6d %6d %10.1f"
			% [r["key"], r["hz"], r["n"], r["seen"], r["hz_each"]])
	print("  %-26s %10.1f" % ["TOTAL (all classes)", total])
	var ms: Array = Array(_frame_ms)
	ms.sort()
	var med: float = float(ms[ms.size() / 2]) if not ms.is_empty() else 0.0
	var p99: float = float(ms[mini(int(float(ms.size()) * 0.99), ms.size() - 1)]) if not ms.is_empty() else 0.0
	# Median AND p99, never a mean. A 4 ms average with one 60 ms hitch a second
	# reads as 250 fps on any counter that reports a mean and reads as a stutter to
	# the player — the same argument PerfOverlay makes for showing WORST.
	print("  frames %d over %.2fs | median %.2f ms (%.0f fps) | p99 %.2f ms | worst %.2f ms"
		% [_frames_live, _elapsed, med, 1000.0 / maxf(med, 0.001), p99,
			float(ms[ms.size() - 1]) if not ms.is_empty() else 0.0])
	print("  live entities: %d enemies + heroes"
		% root.get_tree().get_nodes_in_group(&"enemy").size())
	print("")
	print("══ HITCHES (a stutter is not a low average; it is one frame in a hundred) ══")
	_report_hitches()


func _live_count(key: String) -> int:
	var n: int = 0
	for ci: Variant in (_by_class[key] as Array):
		if is_instance_valid(ci) and (ci as CanvasItem).is_visible_in_tree():
			n += 1
	return n


# ----------------------------------------------------------------- ablation
## Freeze, then hide one class at a time and read the drop in primitives-in-frame.
func _begin_ablation() -> void:
	root.get_tree().paused = true
	_run_ablation()


func _run_ablation() -> void:
	var base: int = await _sample_primitives()
	var base_calls: int = int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var rows: Array = []
	for key: String in _by_class.keys():
		var items: Array = _by_class[key]
		var hidden: Array = []
		for ci: Variant in items:
			if is_instance_valid(ci) and (ci as CanvasItem).visible:
				(ci as CanvasItem).visible = false
				hidden.append(ci)
		if hidden.is_empty():
			continue
		var without: int = await _sample_primitives()
		for ci: Variant in hidden:
			(ci as CanvasItem).visible = true
		rows.append({"key": key, "prims": base - without, "n": hidden.size()})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["prims"]) > int(b["prims"]))
	print("")
	print("══ PRIMITIVES IN FRAME (the GPU side: rasterised every frame, redraw or not) ══")
	print("  total primitives: %d   draw calls: %d   window: %dx%d"
		% [base, base_calls, _width, _height])
	print("  %-26s %10s %6s %10s" % ["class", "prims", "nodes", "prims ea"])
	var rest: int = 0
	var rest_n: int = 0
	for r: Dictionary in rows:
		var p: int = int(r["prims"])
		if p < NOISE_FLOOR:
			rest += maxi(p, 0)
			rest_n += 1
			continue
		print("  %-26s %10d %6d %10.1f"
			% [r["key"], p, r["n"], float(p) / maxf(float(r["n"]), 1.0)])
	print("  %-26s %10d %6d" % ["(rest, each < %d)" % NOISE_FLOOR, rest, rest_n])
	print("")
	print("NOTE: ablation is additive-ish, not exact — hiding a parent hides children,")
	print("  so nested classes double-count. Read the RANKING, not the sum.")
	_report_fill_context()
	quit(0)


## One primitives-in-frame reading, taken after the frame it describes has actually
## been submitted. `RenderingServer.frame_post_draw` is the only point at which the
## counter refers to the frame just drawn rather than the one before it.
func _sample_primitives() -> int:
	var acc: int = 0
	for i: int in ABLATE_FRAMES:
		await process_frame
		await RenderingServer.frame_post_draw
		acc += int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	@warning_ignore("integer_division")
	var out: int = acc / ABLATE_FRAMES
	return out


## The per-pixel work neither table above can see, printed so a reader is not left
## thinking the primitive count is the whole frame.
func _report_fill_context() -> void:
	var vp: Vector2i = DisplayServer.window_get_size()
	var msaa: int = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d", 0))
	var hdr: bool = bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false))
	var post: bool = false
	var pp: Node = root.get_tree().get_first_node_in_group(&"post_process")
	if pp != null:
		post = true
	print("══ FILL CONTEXT (per-pixel work; NOT in either table above) ══")
	print("  window %dx%d = %.1f Mpx/frame" % [vp.x, vp.y, float(vp.x * vp.y) / 1e6])
	print("  msaa_2d=%d (%s)  hdr_2d=%s  post_process node present=%s"
		% [msaa, ["off", "2x", "4x", "8x"][clampi(msaa, 0, 3)], hdr, post])
	print("  -> use tools/profile_fill_cost.gd to A/B these; they are invisible here.")
