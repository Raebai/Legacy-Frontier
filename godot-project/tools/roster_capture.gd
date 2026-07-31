# LOOK AT THE ROSTER. Renders every boss in BossRoster, plus a modifier showcase,
# into real frames of the real arena so the maker can judge them by eye instead of
# by description.
#
# MUST run with the GUI binary — the dummy renderer under --headless draws black:
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/roster_capture.gd
#
# Outputs (user:// = %APPDATA%/Godot/app_userdata/Legacy Frontier/):
#   roster_scribble_p1.png      roster_scribble_p3.png
#   roster_cartographer_p1.png  roster_cartographer_p3.png
#   roster_illuminator_p1.png   roster_illuminator_p3.png
#   roster_guardian_p1.png
#   roster_mods_patient.png     roster_mods_split.png
#   roster_mods_void.png        roster_mods_unfinished.png
#
# ── HOW IT GETS A BOSS ON SCREEN ─────────────────────────────────────────────
# NOT by playing the floor. The guardian only arrives after the last wave, so
# waiting one out would cost minutes per shot and the waves would be in every frame.
# Instead: build the arena in run mode, STOP the encounter, clear the room, and ask
# the encounter to spawn exactly the boss we want with exactly the modifiers we want
# — which is the same `spawn_boss` the floor itself calls, just with the roll
# supplied by hand instead of rolled.
#
# All boss access is duck-typed (.call/.get): no compile-time Boss dependency, so
# this file cannot drag the spell chain into early boot.
extends SceneTree

const SETTLE_SPAWN: int = 46      # long enough for the intro card to be up
const SETTLE_PHASE: int = 26
const HERO_OFFSET: Vector2 = Vector2(190.0, 34.0)

var _arena: Node = null
var _enc: Node = null


func _initialize() -> void:
	_run()


func _settle(n: int) -> void:
	for i: int in n:
		_keep_hero_alive()
		await process_frame


## THE CAPTURE HERO IS A CAMERA TRIPOD, NOT A PLAYER. It is parked next to the boss
## for scale and it does not fight back, so without this it dies inside a couple of
## stages — and a dead hero ends the run, drops a floor, REBUILDS THE ARENA and
## takes the encounter we were driving with it. The first pass of this file lost the
## Split shot to exactly that (the frame came back reading "YOU FELL").
func _keep_hero_alive() -> void:
	for h in root.get_tree().get_nodes_in_group("hero"):
		if h.get("max_hp") != null:
			h.set("hp", h.get("max_hp"))
		h.set("damage_pct", 0.0)


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("roster_capture: saved ", ProjectSettings.globalize_path(path))


func _live_bosses() -> Array:
	var out: Array = []
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if e.has_method("current_phase"):
			out.append(e)
	return out


## Clear the room of everything the floor spawned, so a shot is the boss and nothing
## else. `free()`, not `queue_free()`, so the next spawn sees an empty room now.
func _clear_room() -> void:
	for e in root.get_tree().get_nodes_in_group("enemy"):
		e.free()
	# ...and everything the last boss left in the air. A live spectacle whose caster
	# has just been freed also spams the reaction layer with "trying to cast a freed
	# object", which buries any real error in this file's output.
	for c: Node in _arena.get_children():
		if c.get("caster_node") != null or c is Telegraph or c is MagicCircle:
			c.free()


func _frame_hero_beside(boss: Node) -> void:
	if boss == null or not (boss is Node2D):
		return
	for h in root.get_tree().get_nodes_in_group("hero"):
		if h is Node2D:
			(h as Node2D).global_position = (boss as Node2D).global_position + HERO_OFFSET
			break


## Spawn one boss with a hand-supplied roll and hold it in `phase`.
func _stage(bid: String, mods: Array, phase: int, hp_mult: float = 1.0) -> Node:
	_clear_room()
	await process_frame
	var b: Node = _enc.call("spawn_boss", hp_mult, 1.0, bid, mods, 1)
	if b == null:
		printerr("roster_capture: spawn_boss returned null for ", bid)
		return null
	# Contact damage off for the shoot: the hero has to stand inside the boss's reach
	# for the scale read, and a colossus that keeps punching it turns every stage
	# into a race against the death screen.
	b.set("touch_damage", 0)
	await _settle(SETTLE_SPAWN)
	b = _live_bosses()[0] if not _live_bosses().is_empty() else b
	if is_instance_valid(b):
		b.set("touch_damage", 0)
	if phase > 1 and is_instance_valid(b):
		b.call("_enter_phase", phase)
		await _settle(SETTLE_PHASE)
	_frame_hero_beside(b)
	await _settle(6)
	return b


func _run() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("roster_capture: no GameState autoload")
		quit(1)
		return
	# Run mode so the arena builds a floor (and so modifiers are legal — Encounter
	# deliberately keeps them out of the sandbox; see Encounter._modifiers_enabled).
	gs.active_tower = gs.call("build_default_tower")
	gs.set("_run_active", true)
	gs.set("_floor", 5)
	gs.set("mode", 1)   # Mode.RUN
	_arena = load("res://scenes/combat/Arena.tscn").instantiate()
	root.add_child(_arena)
	await _settle(40)
	if not _arena.has_method("encounter"):
		printerr("roster_capture: arena exposes no encounter()")
		quit(1)
		return
	_enc = _arena.call("encounter")
	if _enc == null:
		printerr("roster_capture: no encounter on the arena")
		quit(1)
		return
	_enc.call("stop")   # we drive the spawns by hand from here

	# --- the four artists, opening phase -------------------------------------
	for bid: String in [BossRoster.SCRIBBLE, BossRoster.CARTOGRAPHER,
			BossRoster.ILLUMINATOR, BossRoster.GUARDIAN]:
		await _stage(bid, [], 1)
		await _shoot("user://roster_%s_p1.png" % bid)

	# --- the three new ones in their last phase (the escalation read) --------
	for bid2: String in [BossRoster.SCRIBBLE, BossRoster.CARTOGRAPHER, BossRoster.ILLUMINATOR]:
		await _stage(bid2, [], 3)
		await _shoot("user://roster_%s_p3.png" % bid2)

	# --- modifiers, one per shot so each is legible --------------------------
	# PATIENT: the body is washed toward the page and stands there. The HUD row
	# under the boss bar is the read.
	await _stage(BossRoster.CARTOGRAPHER, [BossModifier.PATIENT], 1)
	await _shoot("user://roster_mods_patient.png")

	# VOID-TOUCHED: the ground rotting where it stands. Driven by hand so the fields
	# are already open in the frame rather than four seconds away.
	var vb: Node = await _stage(BossRoster.ILLUMINATOR, [BossModifier.VOID_TOUCHED], 3)
	if vb != null:
		var vr: Node = vb.get_node_or_null("Mod_" + BossModifier.VOID_TOUCHED)
		if vr != null:
			for i: int in 3:
				vr.call("_tick", 9.0)
				await _settle(8)
	await _settle(10)
	await _shoot("user://roster_mods_void.png")

	# UNFINISHED: the redraw mark on the page, with the body still where it was.
	var ub: Node = await _stage(BossRoster.GUARDIAN, [BossModifier.UNFINISHED], 2)
	if ub != null:
		var ur: Node = ub.get_node_or_null("Mod_" + BossModifier.UNFINISHED)
		if ur != null:
			ub.set("_busy", false)
			ur.call("_tick", 30.0)
			await _settle(12)
	await _shoot("user://roster_mods_unfinished.png")

	# SPLIT: two halves where one boss was. hp_mult trimmed so the parent dies to a
	# single hand-applied hit rather than needing a whole fight.
	var sb: Node = await _stage(BossRoster.SCRIBBLE, [BossModifier.SPLIT], 2, 0.2)
	if sb != null:
		sb.call("take_damage", int(sb.get("hp")) + 50)
		await _settle(26)
	_frame_hero_beside(_live_bosses()[0] if not _live_bosses().is_empty() else null)
	await _settle(8)
	await _shoot("user://roster_mods_split.png")

	quit(0)
