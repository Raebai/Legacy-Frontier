extends Node
## Slice 2 run-loop spine. Owns the HUB <-> RUN mode, the live-run accumulators,
## the floor plan (pure math), the last-run outcome record, and the run-fact
## injection that makes the hub NPCs AWARE of what happened on a run (the moat:
## "the town remembers your runs"). Autoload "GameState".
##
## Every combat-side caller reaches this through a guarded /root/GameState lookup
## so Arena.tscn still runs standalone (F6) as the pure feel sandbox with no
## GameState-driven floor structure. When a real run IS active, the same arena
## runs floor-by-floor.
##
## The record/fact builders and the floor math are STATIC + PURE so they test
## headlessly with no scene, no Ollama, no change_scene.

signal run_started
signal run_ended(outcome: Dictionary)        # combat resolved (victory or death)
signal floor_advanced(floor: int)            # cleared a floor, entering the next
signal returned_to_hub(outcome: Dictionary)  # hub NPCs have ingested the run
signal fell(new_floor: int)                  # died on a floor -> dropped, staying in the tower

enum Mode { HUB, RUN }

const HUB_SCENE: String = "res://scenes/Main.tscn"
const ARENA_SCENE: String = "res://scenes/combat/Arena.tscn"

## A run is TOTAL_FLOORS floors; the last one is the guardian floor.
const TOTAL_FLOORS: int = 5
## key_facts entry that carries the single most-recent run (replaced each return).
const RUN_FACT_PREFIX: String = "just back: "
## Must match MemoryConsolidator.MAX_KEY_FACTS_PER_ENTITY so a run fact obeys the
## same cap the consolidation pipeline enforces.
const KEY_FACTS_CAP: int = 5

## Climber save schema version (bump + migrate if the shape changes).
const CLIMBER_SAVE_VERSION: int = 1
## Where the persistent climber lives (highest/current floor, falls, conquered, rank).
const CLIMBER_PATH: String = "user://climber.json"

## Which hero class the next/current run uses. Read by Hero._ready(). Set from
## the hub or the debug switch. 0..7 (see Hero.HeroClass / CLASS_NAMES).
var selected_class: int = 0

## Player gear loadout override, set from the hub Armory (Loadout UI). Slot -> gear
## kind; "" = keep the class default. Applied by Hero._ready after configure_class,
## so the chosen weapon/head/body (and their GearAbilities) shape the run hero.
var loadout: Dictionary = {"weapon": "", "head": "", "body": ""}

## Player camera-zoom preference (combat). Lower = wider view. Read by
## CombatCamera as its resting zoom; adjustable live from the pause Settings.
## Default pulled back from the old tight 2.2 so more of the fight is visible.
var camera_zoom: float = 1.6

## Enemy difficulty (0 Easy, 1 Normal, 2 Hard, 3 Impossible). Enemy._ready scales
## stats + unlocks smart behaviours (dodge / deflect). Set in the practice arena.
var enemy_difficulty: int = 1
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard", "Impossible"]

## The tower being climbed. null = no authored tower -> floors are synthesized
## from the depth math (keeps the F6 sandbox + the pre-tower path working).
var active_tower: TowerDef = null

# --- persistent climber state (loaded at _ready, saved at every floor transition) ---
var _highest_floor: int = 1          # highest floor ever reached (monotonic)
var _falls: int = 0                  # cumulative falls (deaths); the town clocks these
var tower_conquered: bool = false    # cleared the guardian at least once this save
var _saved_rank_power: int = 0       # Rank.power snapshot, applied to /root/Rank on enter_run

var mode: int = Mode.HUB
var last_run: Dictionary = {}            # {} until the first run ends
var _pending_ingest: bool = false        # a finished run awaits hub-NPC ingest
var _run_hint_unshown: bool = false      # first post-run engage still owes the punch line

# --- live-run accumulators (reset each enter_run) ---
var _run_active: bool = false
var _floor: int = 1
var _kills: int = 0
var _boss_killed: bool = false
var _elements_used: Dictionary = {}      # used as a String set


# ---------------------------------------------------------------- transitions
const TOWER_PATH: String = "res://data/towers/ashspire.tres"


func _ready() -> void:
	_load_climber()


func enter_run() -> void:
	if active_tower == null:
		active_tower = _load_or_build_tower()
	# Persistent climb: a conquered tower re-climbs fresh; otherwise resume from
	# the saved floor. NEVER a blanket reset to 1.
	if tower_conquered:
		_floor = 1
		tower_conquered = false
	_floor = clampi(_floor, 1, total_floors())
	_highest_floor = maxi(_highest_floor, _floor)
	_restore_rank_power()
	_kills = 0
	_boss_killed = false
	_elements_used = {}
	_run_active = true
	mode = Mode.RUN
	run_started.emit()
	_change_scene(ARENA_SCENE)


## Prefer a maker-authored tower .tres if one exists; otherwise build the default
## Ashspire in code. Same data shapes either way.
func _load_or_build_tower() -> TowerDef:
	if ResourceLoader.exists(TOWER_PATH):
		var t: Resource = load(TOWER_PATH)
		if t is TowerDef:
			return t
	return build_default_tower()


## Total floors in the active tower (or the legacy const when none is set).
func total_floors() -> int:
	if active_tower != null:
		return active_tower.floors.size()
	return TOTAL_FLOORS


## Called by the arena when a floor is cleared and the player takes the exit.
## Advances the floor counter, or ends the run in victory past the last floor.
func advance_floor() -> void:
	if _is_net_client():
		return                            # co-op: only the host advances the party
	if not _run_active:
		return
	if _floor >= total_floors():
		_boss_killed = true               # cleared the guardian floor
		tower_conquered = true
		_highest_floor = maxi(_highest_floor, total_floors())
		_save_climber()
		end_run(false)
		return
	_floor += 1
	_highest_floor = maxi(_highest_floor, _floor)
	_save_climber()
	floor_advanced.emit(_floor)


## Co-op: enter the tower at `floor` WITHOUT a scene change (the Net RPC changes
## scene on all peers) and WITHOUT persistence (the host owns climber.json). Sets
## the shared run state so every peer's Arena runs in run-mode + builds the same
## floor (the default Ashspire is code-built identically on both sides).
func enter_coop_run(floor: int) -> void:
	if active_tower == null:
		active_tower = _load_or_build_tower()
	_floor = clampi(floor, 1, total_floors())
	_highest_floor = maxi(_highest_floor, _floor)
	_kills = 0
	_boss_killed = false
	_elements_used = {}
	_run_active = true
	mode = Mode.RUN
	run_started.emit()


## Co-op CLIENT mirror: the host drives the spine, so a client applies the host's
## floor directly (bypassing the _is_net_client guards on advance/fall) and re-emits
## the signal that rebuilds its Arena. is_fall picks fell (rebuild + revive) vs a
## normal floor_advanced. Host-side / SP never call this — it's the client receiver.
func net_set_floor(floor: int, is_fall: bool) -> void:
	if active_tower == null:
		active_tower = _load_or_build_tower()
	_floor = clampi(floor, 1, total_floors())
	_highest_floor = maxi(_highest_floor, _floor)
	_run_active = true
	mode = Mode.RUN
	if is_fall:
		fell.emit(_floor)
	else:
		floor_advanced.emit(_floor)


## In co-op only the HOST drives the run spine (advance/fall/return + persistence);
## clients follow the host's replicated floor. True on a client in a live session.
func _is_net_client() -> bool:
	var n: Node = get_node_or_null("/root/Net")
	return n != null and n.is_active() and not n.is_host()


## Failing a floor: drop 2 floors, stay in the tower, keep everything. Ticks the
## falls counter and emits `fell` — the Arena rebuilds the dropped floor in place
## and revives the hero. No scene change, no hub trip.
func fall() -> void:
	if _is_net_client():
		return                            # co-op: only the host drives falls
	if not _run_active:
		return                            # sandbox death: Hero handles the local reset
	_falls += 1
	_floor = fall_floor(_floor)
	_save_climber()
	fell.emit(_floor)


## Deliberate hub return from a cleared floor. Banks the cleared floor (resume
## continues the climb, no refight), then bounces to the hub with a "walked out
## alive" outcome the NPCs ingest.
func return_to_hub() -> void:
	if not _run_active:
		return
	if _floor < total_floors():
		_floor += 1
		_highest_floor = maxi(_highest_floor, _floor)
	_save_climber()
	end_run(false)


## Bail to the hub MID-FLOOR (from the pause menu) WITHOUT banking — you didn't
## clear this floor, so resume lands you back on it. Saves + bounces to the hub.
func abandon_to_hub() -> void:
	if not _run_active:
		return
	_save_climber()
	end_run(false)


## End the run (died == true on a hero death, false on a full clear) and bounce
## back to the hub. The outcome is frozen into last_run and queued for ingest.
func end_run(died: bool) -> void:
	if not _run_active:
		return                        # ignore a stray Hero._die in the sandbox
	_run_active = false
	last_run = build_outcome(
		_floor, _kills, _boss_killed, died,
		_elements_used.keys(), _rank_tier(), _rank_title(), _falls
	)
	_pending_ingest = true
	_run_hint_unshown = true
	mode = Mode.HUB
	run_ended.emit(last_run)
	_change_scene(HUB_SCENE)


## Called from World._ready() once the hub + its NPC children have loaded (child
## _ready fires before the parent, so NPC memory is already hydrated here). Pushes
## the finished run into every hub NPC's durable memory, exactly once.
func apply_run_to_hub_npcs(tree: SceneTree) -> void:
	if not _pending_ingest or last_run.is_empty():
		return
	var fact: String = build_run_fact(last_run)
	for npc in tree.get_nodes_in_group("npc"):
		ingest_run_fact(npc, fact)
	_pending_ingest = false
	returned_to_hub.emit(last_run)


func _change_scene(path: String) -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.change_scene_to_file(path)


# --------------------------------------------------- climber persistence (IO)
## Atomic save: write <path>.tmp then rename over the real file, so a crash
## mid-write can't corrupt an existing climber. Mirrors NPC.save_memory.
func _save_climber(path: String = CLIMBER_PATH) -> void:
	var payload: Dictionary = build_climber_save(
		_floor, _highest_floor, _falls, tower_conquered, _live_rank_power()
	)
	var tmp_path: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("GameState._save_climber: cannot open %s for writing" % tmp_path)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("GameState._save_climber: cannot open user://")
		return
	var err: int = dir.rename(tmp_path.get_file(), path.get_file())
	if err != OK:
		push_error("GameState._save_climber: rename %s -> %s failed (err=%d)" % [tmp_path.get_file(), path.get_file(), err])


## Load the climber from disk into the runtime vars. Missing file -> defaults
## (fresh climber at floor 1) so the pre-step-5 behaviour is preserved exactly.
func _load_climber(path: String = CLIMBER_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameState._load_climber: malformed save, ignoring")
		return
	var state: Dictionary = parse_climber_save(parsed)
	_floor = int(state["current_floor"])
	_highest_floor = int(state["highest_floor"])
	_falls = int(state["falls"])
	tower_conquered = bool(state["tower_conquered"])
	_saved_rank_power = int(state["rank_power"])


## The live rank power to persist. Reads /root/Rank when present (combat), else
## falls back to the last-saved snapshot (headless / hub) so a save never zeroes it.
func _live_rank_power() -> int:
	if not is_inside_tree():
		return _saved_rank_power
	var r: Node = get_node_or_null("/root/Rank")
	if r != null:
		return int(r.power)
	return _saved_rank_power


## Push the saved rank power back into /root/Rank (called on entering the tower,
## where the Rank HUD + aura live). No-op headless / if Rank is absent.
func _restore_rank_power() -> void:
	if not is_inside_tree():
		return
	var r: Node = get_node_or_null("/root/Rank")
	if r != null and r.has_method("set_power"):
		r.set_power(_saved_rank_power)


# --------------------------------------------------- live-run notifications
func notify_kill() -> void: _kills += 1
func notify_boss_killed() -> void: _boss_killed = true
func notify_element_used(display_name: String) -> void: _elements_used[display_name] = true
func is_run_active() -> bool: return _run_active
func current_floor() -> int: return _floor


## One-shot punch line for the FIRST hub engage after a run — makes the opening
## reference the run deterministically. Empty on every later call.
func consume_callback_run_hint() -> String:
	if last_run.is_empty() or not _run_hint_unshown:
		return ""
	_run_hint_unshown = false
	return run_hint_text(last_run)


func _rank_tier() -> int:
	if not is_inside_tree():
		return 0
	var r: Node = get_node_or_null("/root/Rank")
	return int(r.call("tier")) if r != null else 0


func _rank_title() -> String:
	if not is_inside_tree():
		return "Nameless"
	var r: Node = get_node_or_null("/root/Rank")
	return String(r.call("title")) if r != null else "Nameless"


# ======================================================================
# PURE / STATIC — outcome record, run facts, floor math (headless-testable)
# ======================================================================

## Frozen record of a finished run.
static func build_outcome(
	floor_reached: int, kills: int, boss_killed: bool, died: bool,
	elements: Array, rank_tier: int, rank_title: String, falls: int = 0
) -> Dictionary:
	var elems: Array = []
	for e in elements:
		elems.append(str(e))
	return {
		"floor_reached": floor_reached,
		"enemies_killed": kills,
		"boss_killed": boss_killed,
		"cleared": (not died),
		"died": died,
		"rank_tier": rank_tier,
		"rank_title": rank_title,
		"elements_used": elems,
		"falls": maxi(falls, 0),
	}


## The durable one-line memory the hub NPCs carry about the latest run.
static func build_run_fact(run: Dictionary) -> String:
	var floor_reached: int = int(run.get("floor_reached", 1))
	var kills: int = int(run.get("enemies_killed", 0))
	var falls: int = int(run.get("falls", 0))
	var elems: Array = run.get("elements_used", [])
	var elem_clause: String = ""
	if elems.size() > 0:
		elem_clause = ", wielding %s" % String(elems[0]).to_lower()
	var fall_clause: String = ""
	if falls > 0:
		fall_clause = " (%d falls so far)" % falls
	if bool(run.get("died", false)):
		return "%sfell on floor %d after %d kills%s, came back rattled%s" % [
			RUN_FACT_PREFIX, floor_reached, kills, elem_clause, fall_clause
		]
	if bool(run.get("boss_killed", false)):
		return "%sconquered all %d floors and felled the guardian%s" % [
			RUN_FACT_PREFIX, floor_reached, elem_clause
		]
	return "%swalked out of floor %d alive after %d kills%s%s" % [
		RUN_FACT_PREFIX, floor_reached, kills, elem_clause, fall_clause
	]


## Human-facing punch line for the one-shot greeting addendum.
static func run_hint_text(run: Dictionary) -> String:
	var floor_reached: int = int(run.get("floor_reached", 1))
	if bool(run.get("died", false)):
		var falls: int = int(run.get("falls", 0))
		var fall_note: String = ""
		if falls > 1:
			fall_note = " That is %d falls now." % falls
		return ("The player has JUST returned from the tower — they died on floor %d.%s "
			+ "Open by acknowledging that specifically, in your own voice — needle them "
			+ "or console them, but reference the fall.") % [floor_reached, fall_note]
	if bool(run.get("boss_killed", false)):
		return ("The player has JUST returned from the tower — they cleared every floor "
			+ "and put down the guardian. Open by reacting to THAT feat specifically, in "
			+ "your own voice.")
	return ("The player has JUST returned from the tower — they made it to floor %d and "
		+ "walked out alive. Open by reacting to that specifically, in your own voice.") % floor_reached


## Dedupe any prior run-marked fact, append the fresh one, honour the cap
## (same oldest-drop policy as the consolidation pipeline).
static func merge_run_fact(key_facts: Array, fact: String, cap: int) -> Array:
	var kept: Array = []
	for f in key_facts:
		if not str(f).begins_with(RUN_FACT_PREFIX):
			kept.append(f)          # preserve real durable facts
	kept.append(fact)               # freshest run fact goes last
	while kept.size() > cap:
		kept.pop_front()
	return kept


## Write the run fact into an NPC's durable player relationship + save. `npc`
## typed Object so a RefCounted stub can drive this in headless tests.
static func ingest_run_fact(npc: Object, fact: String) -> void:
	if not npc.has_method("_ensure_player_relationship"):
		return
	npc._ensure_player_relationship()
	var rel: Dictionary = npc.relationships["player"]
	rel["key_facts"] = merge_run_fact(rel.get("key_facts", []), fact, KEY_FACTS_CAP)
	if npc.has_method("save_memory"):
		npc.save_memory()


## The FloorDef for a given floor: the authored one if a tower is active, else a
## FloorDef synthesized from the depth math (identical to pre-tower behaviour).
func floor_def_for(floor: int) -> FloorDef:
	if active_tower != null and floor >= 1 and floor <= active_tower.floors.size():
		return active_tower.floors[floor - 1]
	return synthesize_floor_def(floor)


## Build a FloorDef purely from the depth math — the null-tower fallback. Pure +
## static so it is headless-testable and matches the old f(floor) values exactly.
static func synthesize_floor_def(floor: int) -> FloorDef:
	var fd := FloorDef.new()
	fd.floor_type = FloorDef.FloorType.COMBAT
	fd.enemy_budget = floor_enemy_budget(floor)
	fd.concurrent_cap = floor_concurrent_cap(floor)
	fd.brute_chance = floor_brute_chance(floor)
	fd.hp_multiplier = 1.0 + 0.15 * float(maxi(floor - 1, 0))
	var theme := EnvTheme.new()
	theme.name = floor_theme(floor)
	theme.wash_tint = floor_theme_tint(floor)
	fd.theme = theme
	fd.layout = default_layout()
	return fd


## The legacy arena geometry as a LayoutDef — the null-tower fallback room + the
## F6 sandbox room. Authored towers supply their own LayoutDefs.
static func default_layout() -> LayoutDef:
	var l := LayoutDef.new()
	l.crate_positions = [
		Vector2(300, 180), Vector2(900, 180), Vector2(280, 520),
		Vector2(920, 500), Vector2(600, 140), Vector2(770, 470),
	]
	l.weapon_pickups = [Vector2(560, 200)]
	return l


## Failing a floor drops you 2 floors but never below 1. Pure so it tests headlessly.
static func fall_floor(current: int) -> int:
	return maxi(current - 2, 1)


## The on-disk climber record. All fields clamped to their floors; highest is
## never below current. Static + pure -> headless-testable.
static func build_climber_save(current_floor: int, highest_floor: int, falls: int, tower_conquered: bool, rank_power: int) -> Dictionary:
	var current: int = maxi(current_floor, 1)
	return {
		"version": CLIMBER_SAVE_VERSION,
		"current_floor": current,
		"highest_floor": maxi(highest_floor, current),
		"falls": maxi(falls, 0),
		"tower_conquered": tower_conquered,
		"rank_power": maxi(rank_power, 0),
	}


## Parse a raw (JSON-loaded) climber dict into typed fields. JSON.parse_string
## returns numbers as TYPE_FLOAT, so EVERY int is coerced through int() — the M9
## trap. A malformed/empty dict yields fresh-climber defaults (floor 1).
static func parse_climber_save(raw: Dictionary) -> Dictionary:
	var current: int = maxi(int(raw.get("current_floor", 1)), 1)
	var highest: int = maxi(int(raw.get("highest_floor", current)), current)
	var falls: int = maxi(int(raw.get("falls", 0)), 0)
	var conquered: bool = bool(raw.get("tower_conquered", false))
	var rank_power: int = maxi(int(raw.get("rank_power", 0)), 0)
	return {
		"current_floor": current,
		"highest_floor": highest,
		"falls": falls,
		"tower_conquered": conquered,
		"rank_power": rank_power,
	}


# ======================================================================
# The Ashspire — the default tower, built in code (a maker-authored
# data/towers/ashspire.tres wins if present). Five TYPED floors so each plays
# and reads differently: combat -> combat -> elite -> combat -> boss.
# ======================================================================
static func build_default_tower() -> TowerDef:
	var t := TowerDef.new()
	t.id = "ashspire"
	t.display_name = "The Ashspire"
	t.theme = _theme("surface", Color(0.20, 0.28, 0.22))
	t.floors = [
		# type, budget, cap, brute%, hp×, theme, layout
		_make_floor(FloorDef.FloorType.COMBAT, 5, 3, 0.30, 1.0, _theme("surface", Color(0.20, 0.28, 0.22)), default_layout()),
		_make_floor(FloorDef.FloorType.COMBAT, 6, 4, 0.35, 1.1, _theme("surface", Color(0.20, 0.28, 0.22)), default_layout()),
		_make_floor(FloorDef.FloorType.ELITE, 4, 3, 0.55, 1.3, _theme("underground", Color(0.16, 0.13, 0.20)), _elite_layout()),
		_make_floor(FloorDef.FloorType.COMBAT, 8, 4, 0.45, 1.3, _theme("underground", Color(0.16, 0.13, 0.20)), default_layout()),
		_make_floor(FloorDef.FloorType.BOSS, 6, 4, 0.70, 1.6, _theme("sky", Color(0.22, 0.26, 0.40)), _boss_layout()),
	]
	return t


static func _theme(name: String, tint: Color) -> EnvTheme:
	var e := EnvTheme.new()
	e.name = name
	e.wash_tint = tint
	return e


static func _make_floor(type: int, budget: int, cap: int, brute: float, hp: float, theme: EnvTheme, layout: LayoutDef) -> FloorDef:
	var f := FloorDef.new()
	f.floor_type = type
	f.enemy_budget = budget
	f.concurrent_cap = cap
	f.brute_chance = brute
	f.hp_multiplier = hp
	f.theme = theme
	f.layout = layout
	return f


## Elite: a more open room (fewer crates) so the tankier fight has space.
static func _elite_layout() -> LayoutDef:
	var l := LayoutDef.new()
	l.crate_positions = [Vector2(300, 180), Vector2(920, 500)]
	l.weapon_pickups = [Vector2(560, 200)]
	return l


## Boss: a clean arena — no crates, no pickup clutter.
static func _boss_layout() -> LayoutDef:
	var l := LayoutDef.new()
	l.crate_positions = []
	l.weapon_pickups = []
	return l


## How many enemies a floor spawns in total (ramps with depth; guardian floor
## is the densest).
static func floor_enemy_budget(floor: int) -> int:
	return 4 + 2 * maxi(floor - 1, 0)   # 4, 6, 8, 10, 12


## Max enemies alive at once on a floor (pressure ramps a little with depth).
static func floor_concurrent_cap(floor: int) -> int:
	return clampi(3 + floor / 2, 3, 7)


## Brute-mix probability for a floor — deeper floors lean tankier/telegraphed.
static func floor_brute_chance(floor: int) -> float:
	return clampf(0.35 + 0.1 * float(floor - 1), 0.35, 0.75)


## Terraria-flavoured layer theme per floor band (surface -> underground -> sky).
static func floor_theme(floor: int) -> String:
	if floor <= 2:
		return "surface"
	if floor <= 4:
		return "underground"
	return "sky"


## Ambient floor tint for the theme (drives the arena's "which layer" read).
static func floor_theme_tint(floor: int) -> Color:
	match floor_theme(floor):
		"underground":
			return Color(0.16, 0.13, 0.20)   # dim cavern
		"sky":
			return Color(0.22, 0.26, 0.40)   # cold high air
		_:
			return Color(0.20, 0.28, 0.22)   # green surface
