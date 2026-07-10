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

## Which hero class the next/current run uses. Read by Hero._ready(). Set from
## the hub or the debug switch. 0 == MAGE, 1 == ROGUE (see Hero.HeroClass).
var selected_class: int = 0

## The tower being climbed. null = no authored tower -> floors are synthesized
## from the depth math (keeps the F6 sandbox + the pre-tower path working).
var active_tower: TowerDef = null

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
func enter_run() -> void:
	_floor = 1
	_kills = 0
	_boss_killed = false
	_elements_used = {}
	_run_active = true
	mode = Mode.RUN
	run_started.emit()
	_change_scene(ARENA_SCENE)


## Called by the arena when a floor is cleared and the player takes the exit.
## Advances the floor counter, or ends the run in victory past the last floor.
func advance_floor() -> void:
	if not _run_active:
		return
	if _floor >= TOTAL_FLOORS:
		_boss_killed = true          # cleared the guardian floor
		end_run(false)
		return
	_floor += 1
	floor_advanced.emit(_floor)


## End the run (died == true on a hero death, false on a full clear) and bounce
## back to the hub. The outcome is frozen into last_run and queued for ingest.
func end_run(died: bool) -> void:
	if not _run_active:
		return                        # ignore a stray Hero._die in the sandbox
	_run_active = false
	last_run = build_outcome(
		_floor, _kills, _boss_killed, died,
		_elements_used.keys(), _rank_tier(), _rank_title()
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
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.change_scene_to_file(path)


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
	var r: Node = get_node_or_null("/root/Rank")
	return int(r.call("tier")) if r != null else 0


func _rank_title() -> String:
	var r: Node = get_node_or_null("/root/Rank")
	return String(r.call("title")) if r != null else "Nameless"


# ======================================================================
# PURE / STATIC — outcome record, run facts, floor math (headless-testable)
# ======================================================================

## Frozen record of a finished run.
static func build_outcome(
	floor_reached: int, kills: int, boss_killed: bool, died: bool,
	elements: Array, rank_tier: int, rank_title: String
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
	}


## The durable one-line memory the hub NPCs carry about the latest run.
static func build_run_fact(run: Dictionary) -> String:
	var floor_reached: int = int(run.get("floor_reached", 1))
	var kills: int = int(run.get("enemies_killed", 0))
	var elems: Array = run.get("elements_used", [])
	var elem_clause: String = ""
	if elems.size() > 0:
		elem_clause = ", wielding %s" % String(elems[0]).to_lower()
	if bool(run.get("died", false)):
		return "%sfell on floor %d after %d kills%s, came back rattled" % [
			RUN_FACT_PREFIX, floor_reached, kills, elem_clause
		]
	if bool(run.get("boss_killed", false)):
		return "%sconquered all %d floors and felled the guardian%s" % [
			RUN_FACT_PREFIX, floor_reached, elem_clause
		]
	return "%swalked out of floor %d alive after %d kills%s" % [
		RUN_FACT_PREFIX, floor_reached, kills, elem_clause
	]


## Human-facing punch line for the one-shot greeting addendum.
static func run_hint_text(run: Dictionary) -> String:
	var floor_reached: int = int(run.get("floor_reached", 1))
	if bool(run.get("died", false)):
		return ("The player has JUST returned from the tower — they died on floor %d. "
			+ "Open by acknowledging that specifically, in your own voice — needle them "
			+ "or console them, but reference the fall.") % floor_reached
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
	return fd


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
