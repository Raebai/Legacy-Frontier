class_name VoiceDirector
extends Node
## THE THING THAT MAKES VOICES AND BARKS ACTUALLY FIRE.
##
## `Gibberish` is the maths and `Bark` is the line table; neither knows when to
## speak. This is the observer that watches the fight and decides. It exists as a
## separate node for one blunt reason: every combat call site that "should" fire a
## bark (`Hero._die`, `Enemy._die`, `Boss._enter_phase`, `Encounter`) is owned by
## another agent right now, and editing them would collide. So this reads the
## world through signals and groups that are ALREADY PUBLIC and touches nothing.
##
## ── WHERE IT LIVES ─────────────────────────────────────────────────────────
## At the scene-tree ROOT, alongside the autoloads, put there by `Sfx` the first
## frame an actual scene exists (and re-ensured by the Lobby). It is not
## registered in `project.godot` because that file belongs to another agent this
## session — but it behaves exactly like an autoload: one instance, survives every
## scene change, never re-created. `_ensure()` is idempotent, so both entry points
## can call it freely.
##
## It deliberately does NOT spawn under `--script` (no `current_scene` there), so
## the headless suites are untouched by it.
##
## ── WHAT IT HOOKS, AND WHAT IT CANNOT ──────────────────────────────────────
## Hooked, all read-only:
##   * `GameState` (autoload) — run_started / floor_advanced / fell / run_ended
##   * `Encounter` — wave_started / wave_cleared / boss_spawned  (duck-typed)
##   * `Boss` — phase_changed / defeated                          (duck-typed)
##   * `Hero.health_changed` — the low-health line and the hurt yelp
##   * any body in group "enemy" — its built-in `tree_exiting`, as a death cry
##
## NOT hooked, and this is the one real gap: **`Hype` exposes no signals.** Kill
## streaks, multi-kills, close calls and wave flourishes are all computed in
## `Hype.gd` and announced only as HUD shouts. There is a `combo()` readout, so
## the streak bark below is driven by POLLING it — which works, but is a poll. If
## the Hype owner adds `signal streak_rung(name, count)`, `signal multi_kill(n)`
## and `signal close_call()`, the polling here deletes and close-calls and
## multi-kills become barkable too. Flagged in the handoff as remaining work.
##
## Everything is duck-typed (`has_signal` / `has_method`) rather than statically
## typed against those classes on purpose: they are being edited concurrently,
## and a rename over there must degrade this to silence, never to a broken build.

## Node name at the root. Also the idempotence key.
const NODE_NAME: StringName = &"VoiceDirector"

## How often the world is re-scanned for things worth listening to. A quarter
## second is far below human notice for a bark and costs a couple of group
## lookups — this runs on a phone, so it is not per-frame.
const SCAN_INTERVAL: float = 0.25

## Chain length that earns a bark. Matches Hype's first named rung (RAMPAGE), so
## the line lands on the same beat as the shout rather than next to it.
const STREAK_BARK_AT: int = 3

## Fraction of max HP that counts as "the lines are smudging".
const LOW_HEALTH_FRACTION: float = 0.3

## A body leaving the tree is usually a death — but a scene change frees the
## whole arena at once. If more than this many exit on the same frame, it was a
## teardown, not a fight, and nobody screams.
const MASS_EXIT_GUARD: int = 3

## Floor on the gap between two death cries anywhere in the room. Twenty-five
## mobs dying to one nova must read as a crowd, not as a machine gun.
const DEATH_VOICE_GAP: float = 0.11

var _scan_t: float = 0.0
var _hero: Node = null
var _hype: Node = null
var _boss: Node = null
var _encounter: Node = null
var _game_state: Node = null

var _last_combo: int = 0
var _was_low: bool = false
var _last_death_voice: float = -99.0
var _exit_frame: int = -1
var _exit_count: int = 0
## Enemy instance ids already given a voice, so a body is not re-bound every scan.
var _voiced: Dictionary = {}


# ══════════════════════════════════════════════════════════════════ install
## The one live director. A static var rather than only a name lookup, because
## the install is DEFERRED: between `ensure()` and the node actually landing under
## root there is a window where `get_node_or_null` still says "no director", and
## two callers in that window would build two.
static var _instance: VoiceDirector = null


## Put exactly one director at the tree root. Safe to call from anywhere, any
## number of times, including from inside a `_ready` (which is what forced the
## deferred add: a parent is "busy setting up children" during its own _ready and
## a direct `add_child` on root fails outright there).
static func ensure(tree: SceneTree) -> Node:
	if tree == null or tree.root == null:
		return null
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var existing: Node = tree.root.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing != null:
		_instance = existing as VoiceDirector
		return existing
	var d := VoiceDirector.new()
	d.name = String(NODE_NAME)
	_instance = d
	tree.root.add_child.call_deferred(d)
	return d


func _ready() -> void:
	# Barks and voices keep working through hit-stop's Engine.time_scale crush,
	# for the same reason Sfx and Music do: the moment the game slows down is
	# exactly the moment something big just happened.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_game_state()


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN_INTERVAL
	_rescan()
	_poll_streak()
	_watch_health()


# ══════════════════════════════════════════════════════════════════ scanning
func _rescan() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if _hero == null or not is_instance_valid(_hero):
		_hero = _own_hero(tree)
	if _hype == null or not is_instance_valid(_hype):
		_hype = _first_in_group(tree, &"hype")
		_last_combo = 0
	_bind_encounter(tree)
	_bind_boss(tree)
	_bind_enemies(tree)


## The hero THIS peer drives. In co-op every peer has a puppet of everyone else,
## and barking the low-health line over someone else's head is worse than saying
## nothing — so authority decides, exactly as Hype does it.
func _own_hero(tree: SceneTree) -> Node:
	for h: Node in tree.get_nodes_in_group(&"hero"):
		if not is_instance_valid(h):
			continue
		if h.has_method(&"is_multiplayer_authority") and not h.is_multiplayer_authority():
			continue
		return h
	return null


func _first_in_group(tree: SceneTree, group: StringName) -> Node:
	for n: Node in tree.get_nodes_in_group(group):
		if is_instance_valid(n):
			return n
	return null


## Encounter is not in a group and its class is another agent's, so it is found
## by the signals it advertises. Duck-typing here is the whole reason a rename
## over there costs us silence instead of a red build.
func _bind_encounter(tree: SceneTree) -> void:
	if _encounter != null and is_instance_valid(_encounter):
		return
	_encounter = _find_by_signal(tree.current_scene, &"wave_started")
	if _encounter == null:
		return
	_connect_once(_encounter, &"wave_started", _on_wave_started)
	_connect_once(_encounter, &"wave_cleared", _on_wave_cleared)
	_connect_once(_encounter, &"boss_spawned", _on_boss_spawned)


func _bind_boss(tree: SceneTree) -> void:
	if _boss != null and is_instance_valid(_boss):
		return
	_boss = _find_by_signal(tree.current_scene, &"phase_changed")
	if _boss == null:
		return
	_connect_once(_boss, &"phase_changed", _on_boss_phase)
	_connect_once(_boss, &"defeated", _on_boss_down)
	_say_boss(&"boss_arrive")


## Give every new body a mouth. `tree_exiting` is a BUILT-IN Node signal, so this
## needs nothing at all from Enemy.gd — a body leaving the arena cries out, and a
## body that never dies never does.
func _bind_enemies(tree: SceneTree) -> void:
	for e: Node in tree.get_nodes_in_group(&"enemy"):
		if not is_instance_valid(e):
			continue
		var id: int = e.get_instance_id()
		if _voiced.has(id):
			continue
		_voiced[id] = true
		if not e.tree_exiting.is_connected(_on_body_exiting):
			e.tree_exiting.connect(_on_body_exiting.bind(e))
		# A scribble muttering to itself as it is drawn in. Quiet, occasional.
		if randf() < 0.25:
			Bark.voice_only(e, Gibberish.Mood.MUTTER, 2)
	# The map is per-arena and mobs are endless; drop ids for bodies that are
	# gone so this cannot grow for the length of a climb.
	if _voiced.size() > 128:
		var live: Dictionary = {}
		for e: Node in tree.get_nodes_in_group(&"enemy"):
			if is_instance_valid(e):
				live[e.get_instance_id()] = true
		_voiced = live


# ══════════════════════════════════════════════════════════════════ triggers
func _on_body_exiting(who: Node) -> void:
	var frame: int = Engine.get_process_frames()
	if frame != _exit_frame:
		_exit_frame = frame
		_exit_count = 0
	_exit_count += 1
	if _exit_count > MASS_EXIT_GUARD:
		return                       # the arena is being torn down, not killed
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - _last_death_voice < DEATH_VOICE_GAP:
		return
	_last_death_voice = now
	Bark.voice_only(who, Gibberish.Mood.DIE, 2)


func _on_wave_started(_index: int, _total: int) -> void:
	Bark.say(_hero, &"wave_start")


func _on_wave_cleared(_index: int, _total: int) -> void:
	Bark.say(_hero, &"wave_clear")


func _on_boss_spawned() -> void:
	# The boss node may not exist for another frame; the next scan barks for it.
	_boss = null


## THE THREE BEATS A GUARDIAN GETS, and all four artists speak them differently.
##
## Before this, every guardian in the tower barked the same three generic rows in
## the same voice: `Gibberish.voice_of` reads a node's NAME, and four boss scenes
## adopted into an arena get near-identical names, so the Scribble and the
## Illuminator were audibly the same creature saying the same words. `Boss` now
## stamps a title-derived seed and the bottom pitch slice onto itself, and this
## routes the line through `say_variant` so each hand speaks its own row.
##
## Phase 3 gets its OWN event rather than a third `boss_phase`: the last break is
## the guardian deciding the page is expendable, and it should not share a line with
## the first one.
func _on_boss_phase(phase: int) -> void:
	_say_boss(&"boss_final" if phase >= 3 else &"boss_phase")


func _on_boss_down() -> void:
	_say_boss(&"boss_down")


## Ask the guardian which row it speaks from, duck-typed like everything else here:
## a boss that has never heard of `bark_suffix` falls through to the generic rows
## rather than to a broken build.
func _say_boss(event: StringName) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var suffix: String = ""
	if _boss.has_method(&"bark_suffix"):
		suffix = String(_boss.call(&"bark_suffix"))
	Bark.say_variant(_boss, event, suffix, true)


## Hype has no signals (see the header), so the chain is polled. One bark per
## chain: crossing the rung again later in the same chain is not news.
func _poll_streak() -> void:
	if _hype == null or not _hype.has_method(&"combo"):
		return
	var c: int = int(_hype.call(&"combo"))
	if c >= STREAK_BARK_AT and _last_combo < STREAK_BARK_AT:
		Bark.say(_hero, &"streak", true)
	_last_combo = c


## The low-health line, edge-triggered. Hero.health_changed exists, but polling
## the ratio is simpler than tracking a connect across respawns and costs one
## method call every quarter second.
func _watch_health() -> void:
	if _hero == null or not is_instance_valid(_hero):
		_was_low = false
		return
	var hp: float = _number(_hero, [&"hp", &"health", &"current_hp"])
	var max_hp: float = _number(_hero, [&"max_hp", &"max_health"])
	if max_hp <= 0.0:
		return
	var low: bool = hp > 0.0 and hp / max_hp <= LOW_HEALTH_FRACTION
	if low and not _was_low:
		Bark.say(_hero, &"low_health", true)
	_was_low = low


# ══════════════════════════════════════════════════════════ GameState hooks
func _bind_game_state() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	_game_state = tree.root.get_node_or_null(^"GameState")
	if _game_state == null:
		return
	_connect_once(_game_state, &"run_started", _on_run_started)
	_connect_once(_game_state, &"floor_advanced", _on_floor_advanced)
	_connect_once(_game_state, &"fell", _on_fell)


func _on_run_started() -> void:
	_reset_for_new_floor()
	_say_soon(&"run_start")


func _on_floor_advanced(_floor: int) -> void:
	_reset_for_new_floor()
	_say_soon(&"floor_enter")


func _on_fell(_floor: int) -> void:
	_reset_for_new_floor()
	_say_soon(&"fall")


## A floor transition rebuilds the arena, so every cached node is stale. Clearing
## them here rather than waiting for `is_instance_valid` to notice means the very
## first scan on the new floor already has the right hero.
func _reset_for_new_floor() -> void:
	_hero = null
	_hype = null
	_boss = null
	_encounter = null
	_voiced.clear()
	_last_combo = 0
	_was_low = false


## The hero does not exist at the instant a floor signal fires — the arena builds
## it. So the line waits for a mouth to arrive rather than being dropped.
func _say_soon(event: StringName) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	await tree.create_timer(0.9, true, false, true).timeout
	if not is_instance_valid(self):
		return
	if _hero == null or not is_instance_valid(_hero):
		_hero = _own_hero(tree)
	Bark.say(_hero, event, true)


# ══════════════════════════════════════════════════════════════════ helpers
func _connect_once(who: Object, sig: StringName, cb: Callable) -> void:
	if who == null or not who.has_signal(sig):
		return
	if not who.is_connected(sig, cb):
		who.connect(sig, cb)


## Depth-first hunt for the first node advertising `sig`. Bounded by the arena's
## depth (a handful of levels) and only runs while the target is unbound.
func _find_by_signal(from: Node, sig: StringName) -> Node:
	if from == null:
		return null
	if from.has_signal(sig):
		return from
	for child: Node in from.get_children():
		var hit: Node = _find_by_signal(child, sig)
		if hit != null:
			return hit
	return null


## Read the first property that exists out of several candidate names. Hero's
## health fields belong to another agent and have been renamed before; this
## degrades to 0.0 instead of aborting the caller, which is the specific GDScript
## failure mode (a dead property read kills the enclosing function) that this
## repo has been bitten by.
func _number(who: Object, names: Array) -> float:
	for n: StringName in names:
		var v: Variant = who.get(n)
		if v != null and (v is int or v is float):
			return float(v)
	return 0.0
