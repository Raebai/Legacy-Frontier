# Run: godot --headless --path godot-project --script tools/probe_cast_warmup.gd
#
# SETTLES ONE QUESTION: is `SpellCaster.cast()` expensive PER CAST, or expensive
# ONCE PER SPELL TYPE?
#
# `tools/profile_spectacles.gd` measured casts at 100 µs to 3.8 ms and reported
# that as per-cast cost. An independent probe casting the same spells ten times
# measured 0.007 ms on the first call and ~0 after — 400x apart. Both can be right
# if the cost is FIRST-TOUCH: `SpellCaster` reaches its 25 spectacle scripts with
# `load()` by PATH rather than `preload`, deliberately, so headless tools can call
# it without early-compiling the autoload-referencing scenes (SpellCaster.gd:8-9).
# A path `load()` of an uncompiled script parses and compiles it on the spot.
#
# The two hypotheses make opposite predictions and this measures both directly:
#   PER-CAST     -> cast #1, #2, #3 all cost about the same.
#   FIRST-TOUCH  -> cast #1 is milliseconds, #2 onward are microseconds, AND
#                   `ResourceLoader.has_cached()` flips false -> true across #1.
#
# The `has_cached` column is the important one: it is direct evidence of the
# MECHANISM rather than an inference from a timer, so it settles the question even
# on a machine whose wall-clock cannot be trusted (which this one's cannot — see
# the header of tools/profile_magic_circle.gd).
extends SceneTree

const ROOM_WIDTH: float = 960.0

var _arena: SimArena = null
var _hero: Node = null
var _boot: int = 2
var _done: bool = false


func _initialize() -> void:
	_arena = SimArena.new()
	root.add_child(_arena)


func _physics_process(_d: float) -> bool:
	if _done:
		return true
	# Fighters spawn a frame AFTER the arena — a node added inside `_initialize`
	# has no `_ready` yet, so `@onready var rig` is null and configure_class throws.
	if _boot > 0:
		_boot -= 1
		if _boot == 0:
			_run()
		return false
	return false


func _run() -> void:
	_hero = _arena.spawn_hero(0, -ROOM_WIDTH * 0.25)
	var spells: Array = SpellLibrary.build_all()
	# `++warm=1` proves the fix: with the warm-up run first, every row should read
	# `cached? YES` and no first cast should be in the tens of milliseconds.
	# BOTH argv lists: Godot routes user arguments to one or the other depending on
	# whether they were separated by `--` or `++`, and scanning only the first is
	# why this flag silently did nothing on its first run.
	var argv: Array = []
	argv.append_array(OS.get_cmdline_user_args())
	argv.append_array(OS.get_cmdline_args())
	for raw: String in argv:
		if raw.lstrip("+-") == "warm=1":
			var t0: int = Time.get_ticks_usec()
			var n: int = SpellCaster.warm()
			print("[warm] SpellCaster.warm() loaded %d scripts in %.1f ms"
				% [n, float(Time.get_ticks_usec() - t0) / 1000.0])
	print("[warm] %-22s %-18s %9s %9s %9s %9s"
		% ["spell", "script", "cached?", "cast#1 us", "cast#2 us", "cast#3 us"])
	var total_first: float = 0.0
	var total_rest: float = 0.0
	for s: SpellDef in spells:
		var path: String = _script_for(s)
		var cached_before: bool = path != "" and ResourceLoader.has_cached(path)
		var t: Array[float] = []
		for i: int in 3:
			var t0: int = Time.get_ticks_usec()
			SpellCaster.cast(s, _arena, (_hero as Node2D).global_position,
				Vector2(ROOM_WIDTH * 0.25, SimArena.FLOOR_Y - 50.0),
				Color(0.6, 0.8, 1.0), s.effect, _hero, &"mortal")
			t.append(float(Time.get_ticks_usec() - t0))
		total_first += t[0]
		total_rest += (t[1] + t[2]) * 0.5
		print("[warm] %-22s %-18s %9s %9.1f %9.1f %9.1f"
			% [s.id, path.get_file().get_basename(),
				("YES" if cached_before else "no") if path != "" else "-",
				t[0], t[1], t[2]])
	print("[warm] --------------------------------------------------")
	print("[warm] SUM first cast %.2f ms   SUM warm cast %.2f ms   ratio %.0fx"
		% [total_first / 1000.0, total_rest / 1000.0,
			total_first / maxf(total_rest, 1.0)])
	print("[warm] If the ratio is large and 'cached?' reads 'no' on the expensive")
	print("[warm] rows, the cost is first-touch script load, not per-cast work.")
	_done = true
	quit(0)


## Best-effort map from a spell to the spectacle script `SpellCaster` will `load()`
## for it. Only used to label rows and to ask `has_cached`, so a miss is harmless.
func _script_for(s: SpellDef) -> String:
	if SpellCaster.HEX_SCRIPTS.has(s.id):
		return String(SpellCaster.HEX_SCRIPTS[s.id])
	if SpellCaster.CATACLYSM_SCRIPTS.has(s.id):
		return String(SpellCaster.CATACLYSM_SCRIPTS[s.id])
	match s.kind:
		SpellDef.Kind.BEAM: return SpellCaster.BEAM_PATH
		SpellDef.Kind.DIVINE_RAY: return SpellCaster.RAY_PATH
		SpellDef.Kind.METEOR: return SpellCaster.METEOR_PATH
		SpellDef.Kind.CONVERGENCE: return SpellCaster.CONVERGENCE_PATH
		SpellDef.Kind.RUSH: return SpellCaster.RUSH_PATH
		SpellDef.Kind.BOULDER: return SpellCaster.BOULDER_PATH
		SpellDef.Kind.PILLAR: return SpellCaster.PILLAR_PATH
		SpellDef.Kind.WALL: return SpellCaster.WALL_PATH
		SpellDef.Kind.ICE_WALL: return SpellCaster.ICE_WALL_PATH
		SpellDef.Kind.CHAIN: return SpellCaster.CHAIN_PATH
		SpellDef.Kind.ZONE: return SpellCaster.ZONE_PATH
		SpellDef.Kind.MISSILES: return SpellCaster.MISSILES_PATH
		SpellDef.Kind.TETHER: return SpellCaster.TETHER_PATH
		SpellDef.Kind.FLURRY: return SpellCaster.FLURRY_PATH
		SpellDef.Kind.BLINK_STRIKE: return SpellCaster.BLINK_PATH
		SpellDef.Kind.CRAWLER: return SpellCaster.CRAWLER_PATH
		SpellDef.Kind.THROWN_ANCHOR: return SpellCaster.DAGGER_PATH
		SpellDef.Kind.WARD: return SpellCaster.WARD_PATH
		SpellDef.Kind.ARC: return SpellCaster.ARC_PATH
		_: return ""
