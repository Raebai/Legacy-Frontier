class_name Encounter
extends Node
## The floor's fight: THE TOWER shape is 3-5 escalating WAVES, then the floor's
## boss. A wave spawns its whole budget under its own concurrent cap; when the
## budget is spent AND the room is empty, a quiet beat passes and the next
## (harder) wave starts. Clearing the LAST wave summons the boss — on every
## floor, not just BOSS-typed ones — and the floor is `cleared` only when the
## boss is dead.
##
## Owns the weighted archetype roll + stats, spawn-point selection, and (1.4) the
## LIVE ENTITY BUDGET: it is the single authority on how many bodies may exist,
## so summoner minions and boss adds ask it via can_spawn() instead of each
## keeping a private cap that the floor knew nothing about.
##
## Driven by a FloorDef. Added as a child of the arena; enemies are spawned into
## the arena (get_parent()). Also exposes spawn() directly for the endless F6
## SANDBOX (no floor budget).

signal cleared
## A wave began: 0-based index + the floor's total wave count. For the HUD /
## announcer beat, and what the headless wave tests assert against.
signal wave_started(index: int, total: int)
## The last wave is down and the floor's guardian has arrived.
signal boss_spawned

const ENEMY_SCENE: PackedScene = preload("res://scenes/combat/Enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/combat/Boss.tscn")
const SPAWN_TRIES: int = 20
const SPAWN_INTERVAL: float = 0.55

# BOSS floor: one big GOLD guardian (BRUTE base — telegraphed heavy swing),
# hp scaled by the floor's hp_multiplier. A handful of adds trickle alongside;
# the floor clears only when the guardian AND every add are dead.
const BOSS_BASE_HP: int = 520
const BOSS_HEIGHT: float = 42.0       # rig height (visual size); collision stays clean
const BOSS_TOUCH_DAMAGE: int = 26
const BOSS_MOVE_SPEED: float = 66.0
const BOSS_TINT: Color = Color(0.95, 0.78, 0.25, 1)   # gold
const BOSS_ADD_BUDGET: int = 3        # the guardian is the star; only a few adds

## THE LIVE ENTITY CAP (spec: "25 entities max"). Counted across players +
## enemies + minions + boss adds — see live_entity_count(). Everything that
## spawns a body asks can_spawn() first; Arena.spawn_extra_enemy is the hard
## choke point that even a caller who forgets cannot slip past.
const MAX_LIVE_ENTITIES: int = 25

## Default wave shape when a FloorDef predates waves (or is synthesized).
const SYNTH_WAVE_COUNT: int = 3
const DEFAULT_WAVE_BREAK: float = 1.5
## Safety valve: if the boss never materializes (a spawner hiccup in co-op), do
## not soft-lock the floor — clear it after this long with nothing alive.
const BOSS_ARRIVAL_GRACE: float = 4.0

## Where the fight is in its life. WAVES = spawning/killing the current wave,
## BREAK = the beat between waves, BOSS = the guardian is up.
enum Phase { IDLE, WAVES, BREAK, BOSS, DONE }

# Spawn area (from the floor's LayoutDef; defaults match the legacy arena rect).
var _rect_min: Vector2 = Vector2(80, 80)
var _rect_max: Vector2 = Vector2(1120, 600)
var _min_dist: float = 160.0
# Floor-level knobs (waves inherit from these unless they override).
var _brute: float = 0.35
var _hp: float = 1.0
var _boss_scale: float = 1.0
var _spawns_boss: bool = true
var _wave_break: float = DEFAULT_WAVE_BREAK
# Wave state.
var _waves: Array[WaveDef] = []
var _wave_index: int = -1
var _wave_spawned: int = 0
var _wave_budget: int = 0
var _wave_cap: int = 3
var _wave_brute: float = 0.35
var _wave_hp: float = 1.0
var _wave_interval: float = SPAWN_INTERVAL
var _timer: float = 0.0
var _break_timer: float = 0.0
var _phase: int = Phase.IDLE
var _running: bool = false
var _boss_seen: bool = false
var _boss_grace: float = 0.0

## Co-op: enemies are HOST-authoritative. In a session the host builds every enemy
## through Arena's MultiplayerSpawner (so spawns + despawns replicate to clients);
## clients never spawn/clear (the host drives + Net broadcasts floor changes). null
## / inactive in SP -> the direct add_child path (byte-identical to before).
var _net: Node = null
var _net_spawner: MultiplayerSpawner = null
## Co-op safety delay before the first host spawn, so late-loading clients' Arena +
## EnemySpawner are ready to receive the replicated spawns (mirrors the hero spawner).
const COOP_SPAWN_DELAY: float = 0.7


func _ready() -> void:
	_net = get_node_or_null("/root/Net")


## Arena wires the co-op enemy spawner here (host + client both, so both build the
## same enemies from the replicated spawn data).
func set_net_spawner(spawner: MultiplayerSpawner) -> void:
	_net_spawner = spawner


## In a live session only the HOST spawns/clears enemies; clients mirror via the
## spawner + Net floor broadcasts. False in SP (host-of-one).
func _is_net_client() -> bool:
	return _net != null and _net.is_active() and not _net.is_host()


func configure(rect_min: Vector2, rect_max: Vector2, min_dist: float) -> void:
	_rect_min = rect_min
	_rect_max = rect_max
	_min_dist = min_dist


## Begin a finite floor from its FloorDef: resolve its wave list, then run the
## waves -> boss sequence. A REST floor (budget 0, no waves) clears the instant
## it starts — nothing to fight, and no guardian either.
func run_floor(floor_def: FloorDef) -> void:
	var layout: LayoutDef = floor_def.layout
	if layout != null:
		configure(layout.spawn_rect_min, layout.spawn_rect_max, layout.min_spawn_dist_from_hero)
	_brute = floor_def.brute_chance
	_hp = floor_def.hp_multiplier
	_boss_scale = resolved_boss_scale(floor_def)
	_wave_break = maxf(floor_def.wave_break, 0.0)
	_waves = resolved_waves(floor_def)
	_spawns_boss = floor_def.floor_type != FloorDef.FloorType.REST \
		and not floor_def.special_tags.has("no_boss")
	_wave_index = -1
	_boss_seen = false
	_boss_grace = 0.0
	_timer = 0.0
	_break_timer = 0.0
	_phase = Phase.IDLE
	_running = true
	# Co-op client: the host owns spawning + the clear gate. Configure the room but
	# spawn nothing here — enemies arrive over the spawner, floor changes over Net.
	if _is_net_client():
		_running = false
		return
	# A REST floor (or an authored empty floor with no boss) is already over.
	if _waves.is_empty() and not _spawns_boss:
		_finish()
		return
	if _waves.is_empty():
		_begin_boss()
		return
	_start_wave(0)
	# Co-op host: hold the first spawn briefly so every client's EnemySpawner exists.
	if _net != null and _net.is_active():
		_timer = COOP_SPAWN_DELAY


func stop() -> void:
	_running = false


## Which wave is running (0-based; -1 before the first). `wave_count()` is the
## floor's total. Read by the HUD and the headless wave tests.
func current_wave() -> int:
	return _wave_index


func wave_count() -> int:
	return _waves.size()


func phase() -> int:
	return _phase


func _process(delta: float) -> void:
	if not _running or _phase == Phase.DONE or _is_net_client():
		return
	var alive: int = _live_enemy_count()
	match _phase:
		Phase.WAVES:
			_tick_wave(delta, alive)
		Phase.BREAK:
			_break_timer -= delta
			if _break_timer <= 0.0:
				_start_wave(_wave_index + 1)
		Phase.BOSS:
			_tick_boss(delta, alive)


## Spawn this wave's budget under its own cap + interval; when the budget is
## spent AND the room is empty, hand off to the break (or the boss).
func _tick_wave(delta: float, alive: int) -> void:
	if _wave_spawned < _wave_budget:
		_timer -= delta
		if _timer <= 0.0 and alive < _wave_cap and can_spawn(1):
			_timer = _wave_interval
			spawn(_wave_brute, _wave_hp)
			_wave_spawned += 1
		return
	if alive > 0:
		return
	# Wave down. Next wave after a beat, or the guardian if that was the last.
	if _wave_index + 1 < _waves.size():
		_phase = Phase.BREAK
		_break_timer = _wave_break
	else:
		_begin_boss()


## The floor ends when the guardian dies. _boss_seen guards the frame(s) between
## asking for the boss and it actually existing (the co-op spawner is not
## same-frame); BOSS_ARRIVAL_GRACE is the anti-soft-lock valve if it never comes.
func _tick_boss(delta: float, alive: int) -> void:
	if alive > 0:
		_boss_seen = true
		return
	if _boss_seen:
		_finish()
		return
	_boss_grace -= delta
	if _boss_grace <= 0.0:
		push_warning("Encounter: floor boss never arrived — clearing to avoid a soft-lock")
		_finish()


func _start_wave(index: int) -> void:
	if index < 0 or index >= _waves.size():
		_begin_boss()
		return
	var w: WaveDef = _waves[index]
	_wave_index = index
	_wave_spawned = 0
	_wave_budget = maxi(w.enemy_budget, 0)
	_wave_cap = maxi(w.concurrent_cap, 1)
	_wave_brute = w.resolved_brute(_brute)
	_wave_hp = w.resolved_hp(_hp)
	_wave_interval = maxf(w.resolved_interval(SPAWN_INTERVAL), 0.05)
	_timer = 0.0
	_phase = Phase.WAVES
	wave_started.emit(index, _waves.size())


## Every floor ends on a guardian. Non-BOSS floors get the same Ashspire
## Guardian scaled down (boss_scale_for_type) — bosses 2-4 are a later phase, so
## a lean mini-guardian is the honest placeholder rather than no boss at all.
func _begin_boss() -> void:
	if not _spawns_boss:
		_finish()
		return
	_phase = Phase.BOSS
	_boss_seen = false
	_boss_grace = BOSS_ARRIVAL_GRACE
	spawn_boss(_hp * _boss_scale, _boss_scale)
	boss_spawned.emit()


func _finish() -> void:
	_phase = Phase.DONE
	_running = false
	cleared.emit()


# ------------------------------------------------------------------ wave data
## The wave list a floor actually runs: the authored one, or a synthesized
## escalating 3-wave split of the legacy `enemy_budget`. Pure — headless-tested.
static func resolved_waves(floor_def: FloorDef) -> Array[WaveDef]:
	if floor_def == null:
		return [] as Array[WaveDef]
	if not floor_def.waves.is_empty():
		return floor_def.waves
	return synthesize_waves(floor_def.enemy_budget, floor_def.concurrent_cap, floor_def.brute_chance)


## Split a legacy flat budget into SYNTH_WAVE_COUNT escalating waves. The split
## is the largest-remainder method over weights 1 : 1.5 : 2, so it is
## deterministic (co-op peers agree), every wave gets at least one enemy, and the
## shares always sum EXACTLY to the original budget — the floor never gets
## quietly longer or shorter than it was authored to be.
static func synthesize_waves(budget: int, cap: int, brute: float) -> Array[WaveDef]:
	var out: Array[WaveDef] = []
	var total: int = maxi(budget, 0)
	if total <= 0:
		return out
	var count: int = mini(SYNTH_WAVE_COUNT, total)
	var shares: Array[int] = split_budget(total, count)
	for i: int in count:
		var w := WaveDef.new()
		w.enemy_budget = shares[i]
		# Pressure ramps across the floor: the opener breathes, the last wave bites.
		w.concurrent_cap = maxi(cap - 1 + i, 2)
		w.brute_chance = clampf(brute + 0.08 * float(i), 0.0, 1.0)
		out.append(w)
	return out


## Largest-remainder split of `total` across `count` escalating shares (weights
## 1, 1.5, 2, ...). Sums to `total`; each share >= 1. Pure + deterministic.
static func split_budget(total: int, count: int) -> Array[int]:
	var out: Array[int] = []
	if count <= 0 or total <= 0:
		return out
	if count >= total:
		for i: int in total:
			out.append(1)
		return out
	var weights: Array[float] = []
	var weight_sum: float = 0.0
	for i: int in count:
		var w: float = 1.0 + 0.5 * float(i)
		weights.append(w)
		weight_sum += w
	var remainders: Array[float] = []
	var assigned: int = 0
	for i: int in count:
		var exact: float = float(total) * weights[i] / weight_sum
		var base: int = int(floor(exact))
		out.append(base)
		remainders.append(exact - floor(exact))
		assigned += base
	# Hand out what floor() dropped, biggest fractional part first. leftover is
	# always < count, so this is one pass and each share gains at most 1. Index
	# order breaks ties, so two co-op peers always produce the same list.
	var leftover: int = total - assigned
	var taken: Dictionary = {}
	while leftover > 0:
		var best: int = -1
		for i: int in count:
			if taken.has(i):
				continue
			if best < 0 or remainders[i] > remainders[best]:
				best = i
		if best < 0:
			break
		out[best] += 1
		taken[best] = true
		leftover -= 1
	# Every wave must be a wave: lift any empty share by taking from the biggest.
	for i: int in count:
		if out[i] > 0:
			continue
		var biggest: int = 0
		for j: int in count:
			if out[j] > out[biggest]:
				biggest = j
		if out[biggest] <= 1:
			break
		out[biggest] -= 1
		out[i] += 1
	return out


## Boss strength for a floor type, as a fraction of the full guardian. BOSS
## floors get the colossus; everything else gets a scaled-down one so every
## floor still ends on a fight (bosses 2-4 are a later phase).
static func boss_scale_for_type(floor_type: int) -> float:
	match floor_type:
		FloorDef.FloorType.BOSS:
			return 1.0
		FloorDef.FloorType.ELITE:
			return 0.62
		FloorDef.FloorType.PVP:
			return 0.75
		_:
			return 0.45


## The floor's authored boss_scale, or the floor-type default when it is <= 0.
static func resolved_boss_scale(floor_def: FloorDef) -> float:
	if floor_def == null:
		return 1.0
	if floor_def.boss_scale > 0.0:
		return floor_def.boss_scale
	return boss_scale_for_type(floor_def.floor_type)


# -------------------------------------------------------- live entity budget
## Everything alive that counts against MAX_LIVE_ENTITIES: the players plus every
## enemy body (mobs, summoner minions and boss adds all join group "enemy", so
## this is the whole population in one scan).
func live_entity_count() -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	return tree.get_nodes_in_group("enemy").size() + tree.get_nodes_in_group("hero").size()


## Is there room for `n` more bodies? THE one question every spawner must ask.
func can_spawn(n: int = 1) -> bool:
	return live_entity_count() + maxi(n, 0) <= MAX_LIVE_ENTITIES


## How many more bodies may exist right now (never negative). Callers that want
## to spawn a batch (summoner minions, boss adds) clamp against this.
func spawn_headroom() -> int:
	return maxi(MAX_LIVE_ENTITIES - live_entity_count(), 0)


func _live_enemy_count() -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	return tree.get_nodes_in_group("enemy").size()


## Spawn the floor's GUARDIAN — a scaled-up gold BRUTE. Stats are set BEFORE
## add_child so _apply_archetype_defaults (which only fills still-default fields)
## leaves them; the rig height is bumped AFTER add_child (rig is @onready). Returns
## the guardian so a caller could wire a health banner / phase logic later.
##
## `body_scale` shrinks the colossus for a non-BOSS floor's mini-guardian (1.0 is
## the full Ashspire Guardian). It rides in the spawn data, so co-op peers build
## the same size from the same dict.
func spawn_boss(hp_mult: float, body_scale: float = 1.0) -> Node:
	var pos: Vector2 = _boss_spawn_position()
	var s: float = clampf(body_scale, 0.3, 1.0)
	return _emit_enemy({
		"boss": true,
		"hp": int(round(BOSS_BASE_HP * hp_mult)),   # set pre-_ready so defaults don't override
		"spd": BOSS_MOVE_SPEED,
		"touch": maxi(int(round(BOSS_TOUCH_DAMAGE * lerpf(0.6, 1.0, s))), 1),
		"bscale": s,
		"x": pos.x, "y": pos.y,
	})


## The guardian stands well to one side of the hero (toward centre) so the
## colossus reads as its own giant silhouette, not stacked on the player.
func _boss_spawn_position() -> Vector2:
	var center := Vector2((_rect_min.x + _rect_max.x) * 0.5, (_rect_min.y + _rect_max.y) * 0.5)
	var heroes: Array[Node] = get_tree().get_nodes_in_group("hero")
	if heroes.size() > 0 and heroes[0] is Node2D:
		var hx: float = (heroes[0] as Node2D).global_position.x
		var bx: float = hx + (300.0 if hx < center.x else -300.0)
		return Vector2(clampf(bx, _rect_min.x + 70.0, _rect_max.x - 70.0), center.y)
	return Vector2(clampf(center.x + 300.0, _rect_min.x, _rect_max.x), center.y)


## Spawn one enemy of a weighted-random archetype into the arena.
func spawn(brute_chance: float, hp_mult: float) -> void:
	var kind: int = _roll_archetype(brute_chance)
	var s: Dictionary = _archetype_stats(kind, hp_mult)
	var pos: Vector2 = _pick_spawn_position()
	_emit_enemy({
		"boss": false, "arch": kind,
		"hp": s["hp"], "spd": s["spd"], "touch": s["touch"], "tint": s["tint"], "tele": s["tele"],
		"x": pos.x, "y": pos.y,
	})


## The one place an enemy enters the world: co-op host -> through the MultiplayerSpawner
## (replicated to clients, authority set in Arena._spawn_enemy_net); SP -> direct
## add_child. Returns the built node in SP (null in co-op — the spawner owns it).
func _emit_enemy(data: Dictionary) -> Node:
	if _net_spawner != null:
		_net_spawner.spawn(data)
		return null
	var e: CharacterBody2D = build_enemy_from_data(data)
	get_parent().add_child(e)
	return e


## Pure construction from a spawn-data dict — the single source of truth used by the
## SP direct path AND Arena's MultiplayerSpawner spawn_function (which runs on every
## peer with identical data, so host + clients build byte-identical enemies). Stats
## are set pre-_ready so Enemy._apply_archetype_defaults leaves the explicit values.
func build_enemy_from_data(data: Dictionary) -> CharacterBody2D:
	var e: CharacterBody2D
	if bool(data.get("boss", false)):
		e = BOSS_SCENE.instantiate()   # Boss._ready installs rig height/tint/aura + bar + intro
		e.max_hp = int(data["hp"])
		e.move_speed = float(data["spd"])
		e.touch_damage = int(data["touch"])
		# Absent on legacy/hand-written spawn dicts -> 1.0 = the full colossus, so
		# every pre-waves caller builds byte-identically to before.
		e.body_scale = float(data.get("bscale", 1.0))
	else:
		e = ENEMY_SCENE.instantiate()
		e.archetype = int(data["arch"])
		e.max_hp = int(data["hp"])
		e.move_speed = float(data["spd"])
		e.touch_damage = int(data["touch"])
		e.tint = data["tint"]
		e.uses_telegraphed_attack = bool(data["tele"])
	e.position = Vector2(float(data["x"]), float(data["y"]))
	return e


## Weighted roll over ALL EIGHT archetypes. Chaser is the backbone; the tankier /
## trickier kinds (brute, summoner, assassin, bomber, mage) scale up with
## brute_chance — the FloorDef's floor-difficulty knob — so deeper floors get
## nastier and more varied. Insertion order is deterministic (GDScript dicts keep
## it), so the accumulate-until-r walk is stable.
func _roll_archetype(brute_chance: float) -> int:
	var weights: Dictionary = {
		0: 0.30,                          # CHASER — fast weak backbone
		1: 0.14 + 0.24 * brute_chance,    # BRUTE — telegraphed heavy
		2: 0.16,                          # CASTER — dodgeable bolt
		3: 0.13,                          # CHARGER — lane dash
		4: 0.03 + 0.07 * brute_chance,    # SUMMONER — rare threat-multiplier
		5: 0.06 + 0.08 * brute_chance,    # ASSASSIN — fast hit-and-run
		6: 0.04 + 0.06 * brute_chance,    # BOMBER — biggest telegraphed blast
		7: 0.05 + 0.08 * brute_chance,    # MAGE — telegraphed AoE
	}
	var total: float = 0.0
	for w: float in weights.values():
		total += w
	var r: float = randf() * total
	var acc: float = 0.0
	for kind: int in weights:
		acc += float(weights[kind])
		if r < acc:
			return kind
	return 0  # CHASER fallback


## Pure per-archetype stat table {hp, spd, touch, tint, tele}, scaled by hp_mult.
## Values match Enemy.ARCHETYPE_DEFAULTS so both spawn paths agree. Pure so it can
## build a spawn-data dict without instantiating a throwaway node.
func _archetype_stats(kind: int, hp_mult: float) -> Dictionary:
	match kind:
		1:  # BRUTE — slow, tanky, telegraphed heavy strike
			return {"hp": int(round(70 * hp_mult)), "spd": 62.0, "touch": 18, "tint": Color(0.7, 0.25, 0.45, 1), "tele": true}
		2:  # CASTER — kites and lobs a dodgeable bolt
			return {"hp": int(round(30 * hp_mult)), "spd": 80.0, "touch": 6, "tint": Color(0.55, 0.45, 0.95, 1), "tele": false}
		3:  # CHARGER — telegraphs a lane then rockets down it
			return {"hp": int(round(45 * hp_mult)), "spd": 55.0, "touch": 10, "tint": Color(0.9, 0.6, 0.2, 1), "tele": false}
		4:  # SUMMONER — kites and telegraphs a minion summon; priority target
			return {"hp": int(round(36 * hp_mult)), "spd": 72.0, "touch": 6, "tint": Color(0.35, 0.8, 0.55, 1), "tele": false}
		5:  # ASSASSIN — fast, fragile hit-and-run, weaving approach
			return {"hp": int(round(20 * hp_mult)), "spd": 175.0, "touch": 8, "tint": Color(0.82, 0.86, 0.92, 1), "tele": false}
		6:  # BOMBER — walking bomb; roots and telegraphs the biggest blast
			return {"hp": int(round(55 * hp_mult)), "spd": 70.0, "touch": 6, "tint": Color(0.34, 0.35, 0.4, 1), "tele": false}
		7:  # MAGE — kites like a caster but telegraphs a ground AoE
			return {"hp": int(round(34 * hp_mult)), "spd": 78.0, "touch": 6, "tint": Color(0.5, 0.3, 0.85, 1), "tele": false}
		_:  # CHASER — fast, weak
			return {"hp": int(round(24 * hp_mult)), "spd": 140.0, "touch": 8, "tint": Color(0.95, 0.5, 0.25, 1), "tele": false}


func _pick_spawn_position() -> Vector2:
	# Reject positions within _min_dist of the hero so an enemy can never spawn
	# straight into contact-damage range.
	var heroes: Array[Node] = get_tree().get_nodes_in_group("hero")
	var hero: Node2D = null
	if heroes.size() > 0:
		hero = heroes[0] as Node2D
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist: float = -1.0
	for i in SPAWN_TRIES:
		var pos := Vector2(
			randf_range(_rect_min.x, _rect_max.x),
			randf_range(_rect_min.y, _rect_max.y)
		)
		if hero == null:
			return pos
		var dist: float = pos.distance_to(hero.global_position)
		if dist >= _min_dist:
			return pos
		if dist > best_dist:
			best_dist = dist
			best_pos = pos
	return best_pos
