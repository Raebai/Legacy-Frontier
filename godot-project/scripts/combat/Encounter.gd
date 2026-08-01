class_name Encounter
extends Node
## The floor's fight: THE TOWER shape is 3-5 escalating WAVES, then the floor's
## boss. Clearing the LAST wave summons the boss — on every floor, not just
## BOSS-typed ones — and the floor is `cleared` only when the boss is dead.
##
## ── PACING: THERE IS NO QUIET BEAT ──────────────────────────────────────────
## The first cut of waves ran "spawn budget -> wait for an EMPTY room -> pause
## 1.5s -> next wave". Both halves of that are dead air, and dead air is the exact
## opposite of the brief ("action packed like there is so much going on to be done
## always, like endorphin chasing"). Three changes, all in _tick_wave:
##
##   1. VANGUARD. A wave OPENS with a group landing at once, not a 0.55s trickle.
##      The lore is that an unseen hand DRAWS each floor and its mobs live, so
##      bodies appearing from nothing is diegetic — spawning gets to be showy and
##      aggressive rather than apologetic.
##   2. OVERLAP. A wave hands off once it is down to its last `handoff_alive`
##      bodies, not once the room is empty. The next wave's vanguard therefore
##      drops in while you are still finishing the stragglers, so the pressure
##      curve never returns to zero between waves.
##   3. SURGE, not BREAK. What used to be a silent 1.5s pause is now a short
##      (~0.85s) LOUD beat: `wave_cleared` fires the reward flourish (Hype),
##      `wave_started` fires the announce + camera pull, and the leftovers from
##      the previous wave are usually still swinging at you through all of it.
##
## Escalation is authored as the MIX (WaveDef.archetypes), never as HP — see
## FloorDef.hp_multiplier for why.
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
## A wave has been BEATEN (its budget is spent and it is down to its last
## stragglers). THE REWARD BEAT — clearing a wave has to feel like winning
## something, not like a timer expiring. Fires once per wave, including the last
## one just before the guardian is called in.
signal wave_cleared(index: int, total: int)
## The last wave is down and the floor's guardian has arrived.
signal boss_spawned

const ENEMY_SCENE: PackedScene = preload("res://scenes/combat/Enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/combat/Boss.tscn")
const SPAWN_TRIES: int = 20
## Seconds between the trickle spawns that follow a wave's vanguard. Tightened
## from 0.55: at the old rate a 5-enemy wave took nearly 3 seconds just to finish
## arriving, which reads as the room filling up rather than as a wave hitting.
const SPAWN_INTERVAL: float = 0.35

# BOSS floor: one big GOLD guardian (BRUTE base — telegraphed heavy swing),
# hp scaled by the floor's hp_multiplier. A handful of adds trickle alongside;
# the floor clears only when the guardian AND every add are dead.
## Guardian HP at full scale. Raised 520 -> 640 during the pacing measurement
## pass: the guardian is the one fight on a floor where a long committed duel is
## the DESIGN rather than a symptom, and at 520 the floor-1 mini-guardian was a
## ~7-second speed bump between the last wave and the exit portal.
const BOSS_BASE_HP: int = 640
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
## THE SURGE BEAT (was DEFAULT_WAVE_BREAK 1.5). Short and loud, not silent — see
## the PACING block at the top. Long enough to read the wave-clear flourish and
## the next wave's announce, short enough that you never put the phone down.
const DEFAULT_SURGE: float = 0.85
## OVERLAP. A wave is "beaten" once it is down to this fraction of its concurrent
## cap, so the next wave's vanguard lands while its last bodies are still up.
const HANDOFF_ALIVE_FRACTION: float = 0.4
const HANDOFF_ALIVE_MAX: int = 3
## THE DRAW-IN. Fraction of a wave's concurrent cap that arrives AT ONCE when the
## wave opens (the rest trickles at SPAWN_INTERVAL). 0.6 means a cap-5 wave slams
## three bodies down the instant it starts.
const VANGUARD_CAP_FRACTION: float = 0.6
## Safety valve: if the boss never materializes (a spawner hiccup in co-op), do
## not soft-lock the floor — clear it after this long with nothing alive.
const BOSS_ARRIVAL_GRACE: float = 4.0

## Where the fight is in its life. WAVES = spawning/killing the current wave,
## SURGE = the short LOUD beat between waves (stragglers usually still alive
## through it), BOSS = the guardian is up. SURGE keeps ordinal 2, where the old
## silent BREAK sat.
enum Phase { IDLE, WAVES, SURGE, BOSS, DONE }

# Spawn area (from the floor's LayoutDef; defaults match the legacy arena rect).
var _rect_min: Vector2 = Vector2(80, 80)
var _rect_max: Vector2 = Vector2(1120, 600)
var _min_dist: float = 160.0
# Floor-level knobs (waves inherit from these unless they override).
var _brute: float = 0.35
var _hp: float = 1.0
var _boss_hp: float = 1.0
var _boss_scale: float = 1.0
## Guardian HP as a fraction of the full colossus. Separate from `_boss_scale`
## (which is now only the BODY size) — see `boss_hp_fraction_for_type`.
var _boss_hp_fraction: float = 1.0
var _spawns_boss: bool = true
var _wave_break: float = DEFAULT_SURGE
# Wave state.
var _waves: Array[WaveDef] = []
var _wave_index: int = -1
var _wave_spawned: int = 0
var _wave_budget: int = 0
var _wave_cap: int = 3
var _wave_brute: float = 0.35
var _wave_hp: float = 1.0
var _wave_interval: float = SPAWN_INTERVAL
## Bodies still owed by the opening VANGUARD (they land in one tick, together).
var _wave_burst: int = 0
## Alive-count at or below which this wave hands off to the next (the overlap).
var _wave_handoff: int = 0
## This wave's archetype roster ([] = the floor's weighted roll over all eight).
var _wave_roster: Array[int] = []
var _timer: float = 0.0
var _break_timer: float = 0.0
var _phase: int = Phase.IDLE
var _running: bool = false
var _boss_seen: bool = false
var _boss_grace: float = 0.0
# --- boss roster + modifiers (see the ROSTER block above spawn_boss) ---
var _depth: int = 0
var _forced_boss: String = ""
var _forced_mods: Array[String] = []
var _allow_mods: bool = false
## The last roll, kept for logging / capture tooling. {"boss","mods","seed","depth"}.
var _boss_roll: Dictionary = {}

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
	_boss_hp = resolved_boss_hp(floor_def)
	_boss_scale = resolved_boss_scale(floor_def)
	_boss_hp_fraction = resolved_boss_hp_fraction(floor_def)
	_wave_break = maxf(floor_def.wave_break, 0.0)
	_waves = resolved_waves(floor_def)
	_spawns_boss = floor_def.floor_type != FloorDef.FloorType.REST \
		and not floor_def.special_tags.has("no_boss")
	# WHICH ARTIST DREW THIS FLOOR, and what rides along. Resolved here rather than
	# at spawn time so an authored floor's pins are read once, with the FloorDef in
	# hand, instead of being re-parsed inside the spawn path.
	_depth = _resolve_depth(floor_def)
	var pins: Dictionary = BossRoster.parse_tags(floor_def.special_tags)
	_forced_boss = String(pins["boss"])
	_forced_mods = []
	for m in (pins["mods"] as Array):
		_forced_mods.append(String(m))
	_allow_mods = bool(pins["allow_mods"]) and _modifiers_enabled()
	_boss_roll = {}
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
		Phase.SURGE:
			# NOT a pause. The previous wave's last bodies are usually still up and
			# fighting through this whole beat — it exists to let the flourish and
			# the next wave's announce land, not to give anyone a rest.
			_break_timer -= delta
			if _break_timer <= 0.0:
				_start_wave(_wave_index + 1)
		Phase.BOSS:
			_tick_boss(delta, alive)


## Spawn this wave: the VANGUARD lands in one tick, the remainder trickles under
## the concurrent cap. The wave then hands off once it is down to its last
## `_wave_handoff` bodies — NOT once the room is empty (see the PACING block).
func _tick_wave(delta: float, alive: int) -> void:
	if _wave_spawned < _wave_budget:
		_timer -= delta
		if _timer > 0.0:
			return
		if _wave_burst > 0:
			# THE DRAW-IN. One tick, a group of bodies, all at once. Each still asks
			# the 25-entity budget individually, so the burst can never be the thing
			# that breaks the cap — it just refuses to finish if the room is full.
			while _wave_burst > 0 and _wave_spawned < _wave_budget \
					and alive < _wave_cap and can_spawn(1):
				spawn(_wave_brute, _wave_hp, _wave_roster)
				_wave_spawned += 1
				_wave_burst -= 1
				alive += 1
			_wave_burst = 0        # whatever the cap swallowed falls back to the trickle
			_timer = _wave_interval
			return
		if alive < _wave_cap and can_spawn(1):
			_timer = _wave_interval
			spawn(_wave_brute, _wave_hp, _wave_roster)
			_wave_spawned += 1
		return
	if alive > _wave_handoff:
		return
	# Wave BEATEN. Fire the reward beat, then hand straight on: the next wave (or
	# the guardian) arrives while these last bodies are still swinging.
	wave_cleared.emit(_wave_index, _waves.size())
	if _wave_index + 1 < _waves.size():
		_phase = Phase.SURGE
		_break_timer = _wave_break
	else:
		_begin_boss()


## The floor ends when the guardian AND every last straggler is dead.
## `_boss_seen` is set by the guardian ACTUALLY BEING THERE (it is the only enemy
## exposing current_phase) rather than by "something is alive" — with overlapping
## waves the boss now arrives on top of stragglers, and the old reading would have
## let their deaths satisfy the gate for a boss that never spawned.
## BOSS_ARRIVAL_GRACE is the anti-soft-lock valve if it genuinely never comes.
func _tick_boss(delta: float, alive: int) -> void:
	if _boss_present():
		_boss_seen = true
	if alive > 0:
		return
	if _boss_seen:
		_finish()
		return
	_boss_grace -= delta
	if _boss_grace <= 0.0:
		push_warning("Encounter: floor boss never arrived — clearing to avoid a soft-lock")
		_finish()


## Is the floor's guardian standing in the room? `current_phase` is the Boss's
## own signature method — no other enemy has it, and it needs no class reference.
func _boss_present() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for e: Node in tree.get_nodes_in_group("enemy"):
		if e.has_method("current_phase"):
			return true
	return false


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
	_wave_roster = w.archetypes
	# Clamped BELOW the budget, never to it: a 1-enemy wave whose handoff was also 1
	# would be "beaten" the instant it spawned, and the floor would sprint through
	# its own wave list without anyone fighting anything.
	_wave_handoff = clampi(w.resolved_handoff(handoff_for_cap(_wave_cap)), 0, maxi(_wave_budget - 1, 0))
	# The burst is armed here but SPAWNED IN _tick_wave, gated on `_timer`. That is
	# load-bearing for co-op: run_floor sets _timer = COOP_SPAWN_DELAY after opening
	# wave 0 so late-loading clients' EnemySpawner exists, and a vanguard that fired
	# here would sail straight past that hold.
	_wave_burst = clampi(w.resolved_vanguard(vanguard_for_cap(_wave_cap)), 0, _wave_budget)
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
	# THE ROLL HAPPENS EXACTLY HERE AND NOWHERE ELSE, and this line is only reached
	# on the HOST (a co-op client returns out of run_floor before it ever starts a
	# wave). Everything downstream is pure construction from the dictionary the roll
	# produces, which is what keeps the two phones fighting the same boss — see the
	# CO-OP block in BossRoster.gd.
	_boss_roll = BossRoster.roll(_depth, randi(), _forced_boss, _forced_mods, _allow_mods)
	# _boss_hp, not the trash multiplier: depth HP scaling now lives on the
	# guardian alone (FloorDef.boss_hp_multiplier).
	# HP fraction and BODY fraction are two arguments now, not one number passed
	# twice — see `boss_hp_fraction_for_type` for why they came apart.
	spawn_boss(_boss_hp * _boss_hp_fraction, _boss_scale,
		String(_boss_roll["boss"]), _boss_roll["mods"], int(_boss_roll["seed"]))
	boss_spawned.emit()


## THIS FLOOR'S DEPTH. The authored field wins; a floor that does not carry one
## (a hand-built FloorDef, an older authored .tres) falls back to the live run, and
## finally to 1 — which yields zero modifiers, i.e. exactly the pre-roster boss.
func _resolve_depth(floor_def: FloorDef) -> int:
	if floor_def != null and floor_def.depth > 0:
		return floor_def.depth
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_method("current_floor"):
		return maxi(int(gs.call("current_floor")), 1)
	return 1


## ⚠ NOT `get_node_or_null("/root/GameState")`. An absolute path from a node that is
## not inside the ACTIVE scene tree does not return null — it raises an engine error,
## which ABORTS THE ENCLOSING FUNCTION and hands the caller the return type's zero
## value with nothing said. Encounter is reachable from harnesses that build their
## world in `_initialize` (there is no current scene at that point), and this exact
## shape has already cost this codebase one silent bug: `_boss_spawn_position`'s
## unguarded `get_tree()` used to abort and spawn the guardian at (0, 0).
##
## Going through `tree.root` makes it a RELATIVE lookup, which is legal from
## anywhere, and the is_inside_tree guard covers the genuinely-detached case.
func _autoload(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


## MODIFIERS ARE A CLIMB FEATURE. They ride only when a real run is in progress —
## the F6 combat sandbox, the boss-rush path and every headless harness get the
## plain, unmodified boss.
##
## That is a design call, not a convenience: the sandbox exists to measure FEEL, and
## a boss that teleports, splits or plays dead depending on an unseeded roll makes
## the sandbox useless for exactly the thing it is for. It also keeps the roster
## honest under test — a suite that spawns a floor gets a deterministic fight.
func _modifiers_enabled() -> bool:
	var gs: Node = _autoload("GameState")
	if gs == null or not gs.has_method("is_run_active"):
		return false
	return bool(gs.call("is_run_active"))


## The roll that produced the floor's current guardian, or {} before one is spawned.
## Read by capture tooling and by the headless roster suite.
func boss_roll() -> Dictionary:
	return _boss_roll


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
		# The synthesized fallback escalates the MIX, not the HP (which stays at
		# the floor's inherit default): more bodies, then a nastier weighting.
		w.brute_chance = clampf(brute + 0.08 * float(i), 0.0, 1.0)
		out.append(w)
	return out


## How many of a wave's bodies land AT ONCE when it opens. Never zero: a wave that
## opens with one enemy trickling in is not a wave, it is a lull.
static func vanguard_for_cap(cap: int) -> int:
	return maxi(int(round(float(maxi(cap, 1)) * VANGUARD_CAP_FRACTION)), 2)


## Alive-count at or below which a wave hands off to the next one — the overlap
## that keeps pressure from ever hitting zero between waves.
static func handoff_for_cap(cap: int) -> int:
	return clampi(int(round(float(maxi(cap, 1)) * HANDOFF_ALIVE_FRACTION)), 1, HANDOFF_ALIVE_MAX)


## The floor's GUARDIAN hp multiplier: the authored boss curve, falling back to
## the legacy `hp_multiplier` so a FloorDef written before the split scales its
## boss exactly as it always did.
static func resolved_boss_hp(floor_def: FloorDef) -> float:
	if floor_def == null:
		return 1.0
	if floor_def.boss_hp_multiplier > 0.0:
		return floor_def.boss_hp_multiplier
	return floor_def.hp_multiplier


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


## Boss SIZE for a floor type, as a fraction of the full guardian. BOSS floors get
## the colossus; everything else gets a scaled-down one so every floor still ends on
## a fight (bosses 2-4 are a later phase).
##
## ⚠ THIS IS A VISUAL SCALE AND NOTHING ELSE NOW. It used to be BOTH the body size
## and the HP fraction (`spawn_boss(_boss_hp * _boss_scale, _boss_scale)`), which
## meant "draw it smaller" and "make it die faster" were the same decision. See
## `boss_hp_fraction_for_type` for why they had to come apart.
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


## Boss HP for a floor type, as a fraction of the full guardian's.
##
## ══ WHY THIS IS NOT `boss_scale_for_type` ═════════════════════════════════════
## The fun audit ran `tools/floor_sim.gd` and measured the mini-guardian at 6-13
## seconds on floor 1 — and the Boss class has THREE HP-gated phases at 66% and
## 33%, with escalating attack cadence, which in a six-second fight are both crossed
## inside about four seconds. The best-built thing in the combat layer was invisible
## on four floors out of five.
##
## The cause was one number doing two jobs. A mini-guardian should LOOK smaller —
## it is not the Ashspire colossus and it must not pretend to be — but a body at 45%
## size does not have to die at 45% HP. Splitting them lets the fight last long
## enough to show its own phases while the silhouette stays honest about rank.
##
## THE NUMBERS ARE SIZED, NOT GUESSED: at the sim's 45 dps reference a floor-1
## guardian goes from ~0:11 to ~0:19 and floor 4 from ~0:15 to ~0:25 — long enough
## to reach phase 3, short enough that the whole five-floor climb stays inside the
## ~6-7 minute run shape the audit argues for (it lands at ~6:45, up from 6:04).
## This is the ONE place trash-vs-boss HP asymmetry is allowed: the spec's "higher
## floors add modifiers, not HP" governs the DEPTH curve, and this is not a depth
## curve — every floor type gets the same fraction at every depth.
static func boss_hp_fraction_for_type(floor_type: int) -> float:
	match floor_type:
		FloorDef.FloorType.BOSS:
			return 1.0
		FloorDef.FloorType.ELITE:
			return 0.90
		FloorDef.FloorType.PVP:
			return 0.85
		_:
			return 0.80


## The floor's authored boss_scale, or the floor-type default when it is <= 0.
static func resolved_boss_scale(floor_def: FloorDef) -> float:
	if floor_def == null:
		return 1.0
	if floor_def.boss_scale > 0.0:
		return floor_def.boss_scale
	return boss_scale_for_type(floor_def.floor_type)


## The floor's guardian HP fraction. An AUTHORED `boss_scale` still wins — a floor
## that deliberately says "this one is a 0.3 statue" gets a 0.3 statue in both size
## and HP, because that author was making one statement about one fight. Only the
## floor-TYPE default splits the two.
static func resolved_boss_hp_fraction(floor_def: FloorDef) -> float:
	if floor_def == null:
		return 1.0
	if floor_def.boss_scale > 0.0:
		return floor_def.boss_scale
	return boss_hp_fraction_for_type(floor_def.floor_type)


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
## ── THE ROSTER RIDES IN THE SPAWN DICTIONARY ─────────────────────────────────
## `boss_id` names which of BossRoster's four artists drew this floor, and `mods`
## lists the modifiers riding it. BOTH TRAVEL IN THE DICT ON PURPOSE. The roll they
## came from happened once, on the host, in `_begin_boss`; from here down there is
## no randomness at all, so `build_enemy_from_data` stays what
## tools/slice_test_coop.gd locks it as — pure construction that produces a
## byte-identical boss on every peer from identical data.
##
## Defaulted so every pre-roster caller is unchanged: `spawn_boss(1.4)` from the
## boss-rush path still builds the plain Ashspire Guardian with no modifiers.
##
## The per-boss `hp_scale` applied here is IDENTITY, not depth difficulty — a
## scribble is a short violent fight and an illuminator is a long one. The depth
## curve is `hp_mult`, which arrives from FloorDef.boss_hp_multiplier and is not
## touched. See the warning on BossRoster.ENTRIES.
func spawn_boss(hp_mult: float, body_scale: float = 1.0,
		boss_id: String = BossRoster.GUARDIAN, mods: Array = [], roll_seed: int = 0) -> Node:
	var pos: Vector2 = _boss_spawn_position()
	var s: float = clampf(body_scale, 0.3, 1.0)
	var bid: String = boss_id if BossRoster.has(boss_id) else BossRoster.GUARDIAN
	var mod_ids: Array[String] = []
	for m in mods:
		mod_ids.append(String(m))
	return _emit_enemy({
		"boss": true,
		"bid": bid,
		"mods": mod_ids,
		"bseed": roll_seed,                          # replay handle; construction ignores it
		# set pre-_ready so Enemy._apply_archetype_defaults leaves the explicit values
		"hp": maxi(int(round(BOSS_BASE_HP * hp_mult * BossRoster.hp_scale(bid))), 1),
		"spd": BOSS_MOVE_SPEED * BossRoster.speed_scale(bid),
		"touch": maxi(int(round(BOSS_TOUCH_DAMAGE * lerpf(0.6, 1.0, s))), 1),
		"bscale": s,
		"x": pos.x, "y": pos.y,
	})


## The guardian stands well to one side of the hero (toward centre) so the
## colossus reads as its own giant silhouette, not stacked on the player.
##
## ⚠ THE get_tree() GUARD IS THE WHOLE POINT OF THIS COMMENT. spawn_boss() is
## reachable from a caller that has not added this Encounter to a tree yet (the
## boss-rush path and headless harnesses both do it during _initialize). An
## unguarded get_tree() there does not return null — it ERRORS, which ABORTS the
## enclosing function and hands the caller a zero Vector2, so the guardian
## silently spawned at (0,0) in the corner of the room and nothing said a word.
func _boss_spawn_position() -> Vector2:
	var center := Vector2((_rect_min.x + _rect_max.x) * 0.5, (_rect_min.y + _rect_max.y) * 0.5)
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	if tree == null:
		return Vector2(clampf(center.x + 300.0, _rect_min.x, _rect_max.x), center.y)
	var heroes: Array[Node] = tree.get_nodes_in_group("hero")
	if heroes.size() > 0 and heroes[0] is Node2D:
		var hx: float = (heroes[0] as Node2D).global_position.x
		var bx: float = hx + (300.0 if hx < center.x else -300.0)
		return Vector2(clampf(bx, _rect_min.x + 70.0, _rect_max.x - 70.0), center.y)
	return Vector2(clampf(center.x + 300.0, _rect_min.x, _rect_max.x), center.y)


## Spawn one enemy into the arena. `roster` (a wave's authored archetype list)
## replaces the weighted roll when it is non-empty — THE difficulty dial, so a
## wave can be "two chargers and a mage" rather than "the same soup, tankier".
## Defaulted so the F6 sandbox's spawn(0.5, 1.0) is byte-identical to before.
func spawn(brute_chance: float, hp_mult: float, roster: Array[int] = []) -> void:
	var kind: int = _roll_archetype(brute_chance, roster)
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
		# WHICH ARTIST. Absent on legacy/hand-written spawn dicts -> the Ashspire
		# Guardian, so every pre-roster caller builds byte-identically to before.
		e = _boss_scene(String(data.get("bid", BossRoster.GUARDIAN))).instantiate()
		e.max_hp = int(data["hp"])
		e.move_speed = float(data["spd"])
		e.touch_damage = int(data["touch"])
		# Absent on legacy/hand-written spawn dicts -> 1.0 = the full colossus, so
		# every pre-waves caller builds byte-identically to before.
		e.body_scale = float(data.get("bscale", 1.0))
		# MODIFIERS ARE ATTACHED HERE — before the boss enters the tree, and on
		# EVERY peer, because this function is the one construction path both the
		# single-player add_child and the co-op MultiplayerSpawner run through.
		# Riders defer their own setup to their first _process, so pre-tree is safe
		# (see BossModifier.gd). Attaching after add_child would work in SP and
		# silently not happen in co-op, where the add_child lives in Arena.gd.
		var mods: Array = data.get("mods", [])
		if not mods.is_empty():
			BossModifier.attach(e, mods, data)
		# A boss body that is NOT this floor's headline act (today: a Split copy)
		# gives up its top bar and its name card, and starts already fighting.
		if bool(data.get("quiet", false)):
			var q_gs: GDScript = load("res://scripts/combat/bossmods/BossQuiet.gd") as GDScript
			if q_gs != null:
				var q: Node = q_gs.new()
				q.name = "Quiet"
				q.set("target_phase", int(data.get("qphase", 1)))
				e.add_child(q)
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


## PackedScene for a roster id, cached. Loaded at RUNTIME rather than preloaded:
## four `preload`s at the top of this file would drag four boss scripts and their
## whole spell chains into the dependency graph of every harness that so much as
## touches Encounter — the trap documented at the top of tools/slice_test_boss.gd,
## where pulling Boss in early boot resolves its spells before the Sfx autoload
## exists. The default Guardian keeps its preload because it always had one.
static var _boss_scene_cache: Dictionary = {}


func _boss_scene(boss_id: String) -> PackedScene:
	if boss_id == BossRoster.GUARDIAN:
		return BOSS_SCENE
	if _boss_scene_cache.has(boss_id):
		return _boss_scene_cache[boss_id] as PackedScene
	var ps: PackedScene = load(BossRoster.scene_path(boss_id)) as PackedScene
	if ps == null:
		push_warning("Encounter: no scene for boss '%s' — falling back to the Guardian" % boss_id)
		ps = BOSS_SCENE
	_boss_scene_cache[boss_id] = ps
	return ps


## Weighted roll over ALL EIGHT archetypes. Chaser is the backbone; the tankier /
## trickier kinds (brute, summoner, assassin, bomber, mage) scale up with
## brute_chance — the FloorDef's floor-difficulty knob — so deeper floors get
## nastier and more varied. Insertion order is deterministic (GDScript dicts keep
## it), so the accumulate-until-r walk is stable.
func _roll_archetype(brute_chance: float, roster: Array[int] = []) -> int:
	# An authored wave roster wins outright: this is how a floor escalates by
	# COMPOSITION (wave 4 = "charger + charger + mage, at once") instead of by
	# quietly multiplying everyone's HP.
	if not roster.is_empty():
		return int(roster[randi() % roster.size()])
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
