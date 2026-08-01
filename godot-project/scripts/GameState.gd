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
## ⚠ `fell(new_floor)` IS GONE, and so are `fall()` and `fall_floor()`.
## They implemented the OLD death rule — die, drop a floor, keep climbing — which the
## maker replaced on 2026-08-01: "dying cost is a life in ghost form until your
## teammate revives you; if you all die then the game is over." Nothing falls any
## more, so a signal announcing a fall had no honest sender left; the party running
## out of bodies now routes to `game_over()` and out through `run_ended`. See
## `DeathRules` for what a game over costs the climb.
##
## Two things read `fell` and both degrade cleanly: `VoiceDirector` connects through
## a `has_signal` guard (its "fall" bark simply never fires again), and `Arena` used
## to rebuild the dropped floor (that whole path is deleted with the rule).

enum Mode { HUB, RUN }

## ═══════════════════════════════════════════════════════════════════════════════
## WHERE A RUN ENDS. THE ONE PLACE.
## ═══════════════════════════════════════════════════════════════════════════════
## ⚠ `end_run` USED TO LOAD `HUB_SCENE` — AND SO DID WINNING.
##
## Both terminal states of the game (conquer the tower / the party wipes) walked
## straight into `scenes/Main.tscn`: the parked v0.0 AI-NPC town, whose NPCs talk to
## a hardcoded Ollama server at `127.0.0.1:11434`. There was no victory screen
## anywhere in the tower, and no route back to the title from anything but the
## credits. Under the 2026-08-01 death rule a solo death ends the run immediately,
## so a first-time player reached that town **on their first death**, having seen
## nothing of the game.
##
## THE CONFLICT, AND HOW IT IS RESOLVED. The hub route was deliberate — "the town
## clocking your deaths is the moat" — and it directly contradicts
## `docs/THE-TOWER-mobile-plan.md`, which records the whole LLM/NPC stack as cut
## permanently and *cannot work on a phone at all* (loopback on a device is the
## device's own localhost).
##
## Neither commitment is abandoned:
##   * A run now ends on `SUMMARY_SCENE` — a ceremony that SHOWS the run (floor,
##     kills, guardians, rank, falls, team damage) and then lands the player on the
##     Lobby, which is the boot scene and works on a phone.
##   * THE PERSISTENT CLIMB IS UNTOUCHED. `_floor`, `_highest_floor`, `_falls`,
##     `tower_conquered` and `user://climber.json` are written exactly as before,
##     BEFORE the ceremony; nothing about the climb needed the hub to happen.
##   * The hub survives as an OPT-IN detour, `visit_hub()`, offered on the summary
##     card and never on the critical path. `_pending_ingest` is still armed by
##     every run, so the town's memory of your climb is intact the moment you walk
##     in — it simply is not a toll gate any more.
const HUB_SCENE: String = "res://scenes/Main.tscn"
const SUMMARY_SCENE: String = "res://scenes/ui/RunSummary.tscn"
const TITLE_SCENE: String = "res://scenes/ui/Lobby.tscn"
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

## Which THREE of a class's five authored roles the player carries. class id ->
## Array of role names. `{}` = that class uses its authored default hand.
##
## THE FIELD HAS TO EXIST HERE FOR THE PICK TO SURVIVE A QUIT. `SpellLibrary`
## holds the live pick in a static, which carries across the scene change into the
## arena but dies with the process; `hydrate_from_state`/`persist_to_state` bridge
## it to disk and are already called by the Lobby and the Outfitter. They were
## no-opping honestly until this line existed — deliberately, because `set()` on an
## undeclared property is a SILENT no-op in Godot, so `persist_to_state` reads the
## field back and returns false rather than pretending it saved.
var spell_roles: Dictionary = {}

## Body colourway index the player chose in the Outfitter. -1 = untouched, use the
## class default. Read by `Hero._configure_class` AT SPAWN — before this existed the
## pick was replayed onto the hero the first time the pause menu opened, so you
## played the whole first floor as the default palette.
var colourway: int = -1

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

## SANDBOX-ONLY Smash model. When true, fighters accrue a damage_pct instead of
## losing hp, knockback scales with that %, and the ONLY elimination is a ring-out
## (StageHazard pit). The tower leaves this FALSE so hp-death still clears floors
## and the slice/climb tests stay green. Set true by VersusArena._ready; forced
## false by enter_run / enter_coop_run so a tower run is never in ring-out mode.
var ringout_mode: bool = false

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
## Damage the party dealt to ITSELF this run. Friendly fire is the spec's social
## engine and the game never counted it, so nobody could ever be shown the bill.
## `FriendlyFire.report` banks it here and the summary card reads it back.
var _friendly_damage: int = 0


# ---------------------------------------------------------------- transitions
const TOWER_PATH: String = "res://data/towers/ashspire.tres"


func _ready() -> void:
	_load_climber()


func enter_run() -> void:
	ringout_mode = false                  # a tower run is HP-death, never ring-out
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
	_friendly_damage = 0
	_run_active = true
	mode = Mode.RUN
	run_started.emit()
	_change_scene(ARENA_SCENE)


## Prefer a maker-authored tower .tres if one exists; otherwise build the default
## Ashspire in code. Same data shapes either way.
##
## `FloorGen.apply` is the LAST step, and it is deliberately here rather than
## inside `build_default_tower()`: eight tools and suites call that static
## directly and assert on the authored numbers (`slice2_test_runloop` pins floor
## 1 at exactly 6 crates), so re-rolling in there would make the authored tower
## untestable. Here, the authored table stays the thing that is asserted and the
## generator is the thing that expresses it.
##
## The hand never draws the same room twice — FloorGen keeps each floor's
## IDENTITY (type, depth, wave count, total bodies, boss curve) and redraws its
## EXPRESSION (room proportion, ledge skyline, cover, spawns, pickups, mix).
func _load_or_build_tower() -> TowerDef:
	if ResourceLoader.exists(TOWER_PATH):
		var t: Resource = load(TOWER_PATH)
		if t is TowerDef:
			return FloorGen.apply(stamp_depths(t as TowerDef))
	return FloorGen.apply(build_default_tower())


## Write each floor's 1-based index into `FloorDef.depth`.
##
## Depth is what the boss roster reads to decide HOW MANY MODIFIERS a floor's
## guardian carries — the spec's "higher floors add modifiers, not HP" — and
## `Encounter.run_floor` is handed a FloorDef and nothing else, so the number has to
## be ON the data. Stamped rather than authored so a hand-written .tres cannot get
## it wrong, and only when it is unset, so a deliberately-lying floor survives.
static func stamp_depths(t: TowerDef) -> TowerDef:
	if t == null:
		return t
	for i: int in t.floors.size():
		var f: FloorDef = t.floors[i]
		if f != null and f.depth <= 0:
			f.depth = i + 1
	return t


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
	ringout_mode = false                  # co-op is a tower run: HP-death, not ring-out
	if active_tower == null:
		active_tower = _load_or_build_tower()
	_floor = clampi(floor, 1, total_floors())
	_highest_floor = maxi(_highest_floor, _floor)
	_kills = 0
	_boss_killed = false
	_elements_used = {}
	_friendly_damage = 0
	_run_active = true
	mode = Mode.RUN
	run_started.emit()


## Co-op CLIENT mirror: the host drives the spine, so a client applies the host's
## floor directly (bypassing the _is_net_client guard on advance) and re-emits the
## signal that rebuilds its Arena. Host-side / SP never call this — it's the client
## receiver. The old `is_fall` parameter went with the fall rule (see the note on
## the deleted `fell` signal): a floor only ever moves UP now.
func net_set_floor(floor: int) -> void:
	if active_tower == null:
		active_tower = _load_or_build_tower()
	_floor = clampi(floor, 1, total_floors())
	_highest_floor = maxi(_highest_floor, _floor)
	_run_active = true
	mode = Mode.RUN
	floor_advanced.emit(_floor)


## In co-op only the HOST drives the run spine (advance/fall/return + persistence);
## clients follow the host's replicated floor. True on a client in a live session.
func _is_net_client() -> bool:
	var n: Node = get_node_or_null("/root/Net")
	return n != null and n.is_active() and not n.is_host()


## GAME OVER — every hero is a ghost and nobody is left to pick anyone up.
##
## This is the replacement for `fall()`. The maker's rule ends the RUN rather than
## moving you down the tower, so: tick the falls counter (the hub NPCs turn it into
## "that is 4 falls now" — the town clocking your deaths is the moat, and it is the
## only lasting cost under the shipped policy), apply the climb policy, save, and
## bounce home with a `died` outcome.
##
## The outcome records the floor you DIED ON, not the floor you will resume on. They
## are the same number under `RESET_CLIMB_ON_GAME_OVER == false`, but if that is ever
## flipped the town must not start saying you fell on floor 1 when you fell on 4.
func game_over() -> void:
	if _is_net_client():
		return                            # co-op: only the host drives the run spine
	if not _run_active:
		return                            # sandbox death: Hero handles the local reset
	var died_on: int = _floor
	_falls += 1
	_floor = DeathRules.resume_floor_after_game_over(_floor, total_floors())
	_save_climber()
	end_run(true, died_on)


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


## End the run (died == true on a party wipe, false on a full clear) and bounce back
## to the hub. The outcome is frozen into last_run and queued for ingest.
##
## `floor_override` exists for `game_over()`, which has to move `_floor` to the
## RESUME floor before ending the run but must record the floor you actually died on.
## -1 (every other caller) keeps the pre-existing behaviour exactly.
func end_run(died: bool, floor_override: int = -1) -> void:
	if not _run_active:
		return                        # ignore a stray Hero._die in the sandbox
	_run_active = false
	last_run = build_outcome(
		(_floor if floor_override < 0 else floor_override),
		_kills, _boss_killed, died,
		_elements_used.keys(), _rank_tier(), _rank_title(), _falls,
		_friendly_damage, _highest_floor, total_floors()
	)
	_pending_ingest = true
	_run_hint_unshown = true
	mode = Mode.HUB
	run_ended.emit(last_run)
	# THE CEREMONY, NOT THE PARKED TOWN. See the SUMMARY_SCENE block at the top for
	# why this line moved and what it does not cost. Falls back to the title screen
	# rather than the hub if the card is ever missing from a build — a player who
	# finished a run must always end up somewhere they can start another one.
	_change_scene(SUMMARY_SCENE if ResourceLoader.exists(SUMMARY_SCENE) else TITLE_SCENE)


## THE OPT-IN DETOUR. Walk into the parked v0.0 town, where the NPCs read the run
## you just finished out of `_pending_ingest` and react to it.
##
## ⚠ NOT ON THE CRITICAL PATH, AND THAT IS THE WHOLE POINT. It needs a local Ollama
## server on `127.0.0.1:11434`, which on a phone is the device's own loopback, so
## anything that FORCES a player through here is broken on the target platform. The
## summary card offers it as a button and hides that button on a build that has no
## business showing it. Returns false when the hub is not in this build.
func visit_hub() -> bool:
	if not ResourceLoader.exists(HUB_SCENE):
		return false
	mode = Mode.HUB
	_change_scene(HUB_SCENE)
	return true


## Back to the title. The game had NO route here from anything but the credits
## screen — once a run ended, the thing you booted into was unreachable.
func go_to_title() -> void:
	mode = Mode.HUB
	_change_scene(TITLE_SCENE)


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
## Banked by `FriendlyFire.report`. The only number in the game that says what the
## party did to itself — without it, "friendly fire is the social engine" is a claim
## nobody can check after the fact.
func notify_friendly_fire(amount: int) -> void: _friendly_damage += maxi(amount, 0)
func friendly_damage() -> int: return _friendly_damage
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
## The three trailing fields exist for the SUMMARY CARD and are appended rather than
## inserted so every existing 7- and 8-argument caller (and the suites that pin them)
## is untouched. `conquered` is derived rather than stored: "you put the guardian
## down AND walked away with it" is one question, and two call sites answering it
## independently is how a victory screen ends up disagreeing with the save file.
static func build_outcome(
	floor_reached: int, kills: int, boss_killed: bool, died: bool,
	elements: Array, rank_tier: int, rank_title: String, falls: int = 0,
	friendly_damage: int = 0, highest_floor: int = 0, total_floors_in_tower: int = 0
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
		"conquered": (boss_killed and not died),
		"rank_tier": rank_tier,
		"rank_title": rank_title,
		"elements_used": elems,
		"falls": maxi(falls, 0),
		"friendly_damage": maxi(friendly_damage, 0),
		"highest_floor": maxi(highest_floor, floor_reached),
		"total_floors": maxi(total_floors_in_tower, floor_reached),
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
	fd.depth = maxi(floor, 1)   # the boss roster's modifier dial — see FloorDef.depth
	fd.enemy_budget = floor_enemy_budget(floor)
	fd.concurrent_cap = floor_concurrent_cap(floor)
	fd.brute_chance = floor_brute_chance(floor)
	# TRASH HP DOES NOT SCALE WITH DEPTH (spec: "higher floors add modifiers, not
	# HP"). The synthesized fallback follows the same policy as the authored tower:
	# depth rides on brute_chance (the archetype mix) and on the guardian's own
	# curve below. The old `1.0 + 0.15 * (floor - 1)` only made identical fights
	# take longer, which is the specific failure the rule exists to prevent.
	fd.hp_multiplier = 1.0
	fd.boss_hp_multiplier = floor_boss_hp_multiplier(floor)
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
	# Crate + pickup points, re-laid for the one-screen 960x480 room (1.3).
	l.crate_positions = [
		Vector2(240, 130), Vector2(720, 130), Vector2(225, 365),
		Vector2(735, 350), Vector2(480, 100), Vector2(615, 330),
	]
	l.weapon_pickups = [Vector2(450, 145)]
	return l


## ⚠ `fall_floor()` IS DELETED. It answered "which floor does a death drop you to",
## and under the 2026-08-01 rule a death does not drop you to any floor — it makes
## you a ghost. What replaced it is `DeathRules.resume_floor_after_game_over`, which
## answers the only remaining version of that question: after the whole party is
## dead and the run is over, where does the NEXT run start? Same shape, different
## question, and it lives with the rest of the death policy rather than here.


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
#
# THE FLOOR SHAPE (1.1/1.2): each floor is an ordered list of escalating WAVES
# and then a guardian. Wave counts climb with depth (3 -> 3 -> 4 -> 4 -> 5), and
# inside a floor each wave brings more bodies at a higher concurrent cap. The
# `enemy_budget` field is kept in sync with the wave totals so anything still
# reading the flat number (and the synthesized-wave fallback) agrees.
#
# ESCALATION IS THE MIX, NOT THE HP. Every floor below runs hp_multiplier 1.0.
# The spec is explicit — "higher floors add modifiers, not HP. HP scaling makes
# fights longer, not harder, and long is the enemy of chaos on a phone" — so the
# curve is carried by the third column of each wave: WHO shows up. The axis
# varies deliberately rather than only going up: more bodies -> a first telegraph
# -> a lane threat -> a ranged threat you cannot ignore -> two threats at once ->
# the whole roster. Depth HP scaling survives on the GUARDIAN alone
# (boss_hp_multiplier), where a longer committed duel is the point.
#
# Archetype ids (Enemy.Archetype): 0 CHASER · 1 BRUTE · 2 CASTER · 3 CHARGER
#                                  4 SUMMONER · 5 ASSASSIN · 6 BOMBER · 7 MAGE
# ======================================================================
const A_CHASER: int = 0
const A_BRUTE: int = 1
const A_CASTER: int = 2
const A_CHARGER: int = 3
const A_SUMMONER: int = 4
const A_ASSASSIN: int = 5
const A_BOMBER: int = 6
const A_MAGE: int = 7


static func build_default_tower() -> TowerDef:
	var t := TowerDef.new()
	t.id = "ashspire"
	t.display_name = "The Ashspire"
	t.theme = _theme("surface", Color(0.20, 0.28, 0.22))
	var surface: Color = Color(0.20, 0.28, 0.22)
	var under: Color = Color(0.16, 0.13, 0.20)
	var sky: Color = Color(0.22, 0.26, 0.40)
	t.floors = [
		# type, brute%, boss hp×, theme, layout, waves [budget, cap, roster]
		# --- 1 · SURFACE. Learn to swing. Bodies first, then the first tell. ---
		_make_floor(FloorDef.FloorType.COMBAT, 0.30, 1.0, _theme("surface", surface), default_layout(),
			_waves([
				[7, 4, [A_CHASER]],                            # pure pressure, nothing to read
				[9, 5, [A_CHASER, A_CHASER, A_BRUTE]],         # the first telegraph
				[11, 5, [A_CHASER, A_BRUTE, A_CHARGER]],       # ...and the first lane to dodge
			])),
		# --- 2 · SURFACE. Range enters: you can no longer only look forward. ---
		_make_floor(FloorDef.FloorType.COMBAT, 0.35, 1.15, _theme("surface", surface), default_layout(),
			_waves([
				[8, 4, [A_CHASER, A_CHARGER]],
				[10, 5, [A_CHASER, A_CASTER, A_BRUTE]],        # something shooting from the back
				[13, 6, [A_CHASER, A_CHARGER, A_CASTER, A_BRUTE]],
			])),
		# --- 3 · ELITE, UNDERGROUND. Fewer bodies, meaner ones. TANKIER is an
		#     archetype (BRUTE), never a multiplier. Ends on two threats at once. ---
		_make_floor(FloorDef.FloorType.ELITE, 0.55, 1.3, _theme("underground", under), _elite_layout(),
			_waves([
				[6, 4, [A_BRUTE, A_CHASER]],
				[8, 5, [A_BRUTE, A_CHARGER, A_ASSASSIN]],      # fast + heavy in the same breath
				[9, 5, [A_ASSASSIN, A_ASSASSIN, A_MAGE]],      # zoned while being harried
				[11, 6, [A_BRUTE, A_CHARGER, A_MAGE, A_SUMMONER]],
			])),
		# --- 4 · UNDERGROUND. The swarm floor: volume plus area denial. ---
		_make_floor(FloorDef.FloorType.COMBAT, 0.45, 1.45, _theme("underground", under), default_layout(),
			_waves([
				[9, 5, [A_CHASER, A_ASSASSIN]],
				[11, 6, [A_CHASER, A_CHARGER, A_BOMBER]],      # the floor starts denying you space
				[12, 6, [A_BRUTE, A_CASTER, A_MAGE]],
				[14, 7, [A_CHASER, A_CHARGER, A_ASSASSIN, A_BOMBER, A_MAGE]],
			])),
		# --- 5 · SKY. Everything the tower has, then the colossus. ---
		_make_floor(FloorDef.FloorType.BOSS, 0.70, 1.6, _theme("sky", sky), _boss_layout(),
			_waves([
				[8, 5, [A_CHASER, A_CHARGER]],
				[10, 6, [A_BRUTE, A_CASTER, A_ASSASSIN]],
				[12, 6, [A_CHARGER, A_MAGE, A_BOMBER]],
				[13, 7, [A_BRUTE, A_ASSASSIN, A_MAGE, A_SUMMONER]],
				[15, 7, [A_CHASER, A_BRUTE, A_CHARGER, A_ASSASSIN, A_BOMBER, A_MAGE]],
			])),
	]
	return stamp_depths(t)


## Build a wave list from [budget, concurrent_cap] or [budget, cap, archetypes]
## rows. HP is left inheriting the floor's (1.0) on purpose — the authored table
## is about PACING and COMPOSITION, which are the things that have to be tuned by
## feel; a wave that wants to be harder says so by naming nastier archetypes.
static func _waves(rows: Array) -> Array[WaveDef]:
	var out: Array[WaveDef] = []
	for row: Array in rows:
		var w := WaveDef.new()
		w.enemy_budget = int(row[0])
		w.concurrent_cap = int(row[1])
		if row.size() > 2:
			var roster: Array[int] = []
			for a in (row[2] as Array):
				roster.append(int(a))
			w.archetypes = roster
		out.append(w)
	return out


static func _theme(name: String, tint: Color) -> EnvTheme:
	var e := EnvTheme.new()
	e.name = name
	e.wash_tint = tint
	return e


## `boss_hp` is the GUARDIAN's depth multiplier. Trash HP is pinned at 1.0 on
## every authored floor by policy (see the header block) — depth is carried by
## the archetype mix, not by making the same fight take longer.
static func _make_floor(type: int, brute: float, boss_hp: float, theme: EnvTheme, layout: LayoutDef, waves: Array[WaveDef]) -> FloorDef:
	var f := FloorDef.new()
	f.floor_type = type
	f.waves = waves
	# Keep the legacy flat fields consistent with the authored waves: the budget
	# is the sum, the cap is the toughest wave's. Anything that still reads them
	# (and Encounter.synthesize_waves, if the wave list is ever cleared) then sees
	# the same floor, rather than a stale pre-waves number.
	var total: int = 0
	var cap: int = 1
	for w: WaveDef in waves:
		total += maxi(w.enemy_budget, 0)
		cap = maxi(cap, w.concurrent_cap)
	f.enemy_budget = total
	f.concurrent_cap = cap
	f.brute_chance = brute
	f.hp_multiplier = 1.0        # POLICY: trash HP never scales with depth
	f.boss_hp_multiplier = boss_hp
	f.theme = theme
	f.layout = layout
	return f


## Elite: a more open room (fewer crates) so the tankier fight has space.
static func _elite_layout() -> LayoutDef:
	var l := LayoutDef.new()
	l.crate_positions = [Vector2(240, 130), Vector2(735, 350)]
	l.weapon_pickups = [Vector2(450, 145)]
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
## THIS is the depth dial now that trash HP is flat: it reweights WHO spawns.
static func floor_brute_chance(floor: int) -> float:
	return clampf(0.35 + 0.1 * float(floor - 1), 0.35, 0.75)


## The GUARDIAN's depth HP curve — the one place a longer fight is legitimate,
## because it is one big committed duel rather than twelve bodies to shred.
static func floor_boss_hp_multiplier(floor: int) -> float:
	return 1.0 + 0.15 * float(maxi(floor - 1, 0))


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
