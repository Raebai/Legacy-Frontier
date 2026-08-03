extends SceneTree
## THE BOT SIMULATION — an automated bug-finder that fights bots against each
## other across class pairings and reports every anomaly it can measure.
##
## Run (headless, no window, no rendering):
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
##       --path godot-project --script tools/bot_sim.gd -- --mode=duel --dur=20
##
## Options (all optional; `--key=value`, order-independent):
##   --mode=duel|vs_enemy|all   what fights what. Default duel.
##   --seed=N                   master seed. Default 20260727. PRINTED IN EVERY
##                              REPORT — a bug you cannot replay is a rumour.
##   --dur=SECONDS              game-clock length of one match. Default 20.
##   --classes=0,1,5            restrict the roster. Default all 9.
##   --max-matches=N            stop after N matches (smoke runs).
##   --difficulty-b=0..3        tier for the SECOND fighter, to put two tiers against
#                              each other. Defaults to the same as --difficulty.
#   --out=user://bot_sim       report directory.
##
## WHY A FIGHT NOBODY WATCHES IS WORTH RUNNING. It is only worth running if it
## can tell you something is wrong, so every check lives in `BotSimProbe` as a
## pure predicate and every finding is emitted as ONE ROW carrying the pairing,
## the game-clock timestamp and the seed. `python-tools/bot_sim_report.py`
## aggregates many runs into "which pairing breaks most, which spell never
## fires, which anomaly is most common".
##
## DETERMINISM. The global RNG is seeded per match from the master seed and the
## pairing index, so `--seed=X` replays a found bug exactly. This is not
## airtight: any game code constructing its own unseeded `RandomNumberGenerator`
## escapes it, and `Time`-derived values escape it entirely. Where a replay does
## not reproduce, that is itself a finding worth reporting.
##
## FAIRNESS IS STRUCTURAL. The driver below reads only what a human sees on
## screen — the opponent's position, its own cooldowns and mana. No bot is handed
## privileged information and no bot is given a stat buff, because a clip of a
## bot cheating is worthless for finding bugs and dishonest for marketing.
##
## ⚠ THE HARNESS MUST NEVER WEAKEN THE GAME TO PASS. It exits 0 even when it
## finds problems; finding them IS the deliverable. `--strict` flips that for CI.

const CONTROLLER_SCRIPT: String = "res://tools/sim_controller.gd"
const HERO_CONTROLLER_BASE: String = "res://scripts/combat/HeroController.gd"
const BOT_BRAIN_SCRIPT: String = "res://scripts/combat/BotBrain.gd"
const BOT_PROFILE_SCRIPT: String = "res://scripts/combat/BotProfile.gd"
const BOT_CONTROLLER_SCRIPT: String = "res://scripts/combat/BotController.gd"

## Indices match `Hero.HeroClass`; names are the ones the design doc uses, which
## is not always the enum name (HeroClass.MAGE is the Arcanist, ROGUE is the
## Shadowblade). Reports read better with the design name.
const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

## Enemy archetypes used by `vs_enemy`: CASTER(2) and CHARGER(3). Both telegraph,
## which is what makes the fight legible and the dodge brain testable.
const VS_ENEMY_ARCHETYPES: Array[int] = [2, 3]

## Hero members this harness reaches DYNAMICALLY (Hero.gd has no `class_name`, so
## every access is a runtime lookup). Reading a member that has MOVED is not a
## test failure in GDScript — it logs an error and ABORTS the enclosing function,
## handing back a zero value that reads as "nothing wrong". So the list is checked
## by name once per run and a miss is filed as its own loud anomaly rather than
## quietly disabling half the detectors.
##
## ⚠ `_signature_cd_timer` USED TO BE ON THIS LIST AND NO LONGER EXISTS. The hero
## ran one shared signature cooldown bank; per-slot cooldowns moved to `HandSlots`
## (`Hero._hand`) and the bank was deleted. The list was not updated, so every match
## filed `harness_probe_missing`, `probe_ok` went false for every fighter, and that
## flag gates the whole signature-attempt sampler — which is why the same runs ALSO
## reported `no_castable_signature` and `never_spent_mana` for all nine classes. The
## bots were fine. Twenty-four of the twenty-four "errors" in that report were this
## one stale string. Cooldowns are read through the PUBLIC accessors now
## (`signature_cooldown` / `signature_ready`), which cannot go stale silently.
const HERO_PROBE_MEMBERS: Array[String] = [
	"hp", "max_hp", "mp", "max_mp", "_signature_index",
	"_cast_cooldown_timer", "_blast_cooldown_timer", "_blink_cooldown_timer",
	"_nova_cooldown_timer", "_dash_cooldown_timer", "_melee_cooldown_timer",
]
## ...and the public METHODS this harness leans on. Same reasoning, different
## namespace: a renamed method aborts the caller exactly as a renamed member does.
const HERO_PROBE_METHODS: Array[String] = [
	"signature_cooldown", "signature_ready", "current_signature",
	"bot_select_signature", "bot_body_state",
]

## Every action the driver may hold. Released in bulk between matches so no press
## leaks from one pairing into the next.
const ALL_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"jump",
	&"cast", &"melee", &"dash", &"parry", &"blast", &"blink", &"nova",
	&"ultimate", &"cycle_signature",
	&"aim_left", &"aim_right", &"aim_up", &"aim_down",
]

## Driver feel. These shape WHAT the harness bot does, not how hard it hits —
## nothing here touches a damage number.
const DECIDE_INTERVAL: float = 0.22      # how often the driver re-plans
const PREFERRED_RANGE: float = 210.0     # the band the driver tries to hold
const MELEE_RANGE: float = 95.0
## Rotate to the next signature this often and try to cast it. A DETERMINISTIC
## rotation rather than a random pick, because it is what makes "this spell never
## fired" a measurement instead of a coincidence: over a 20 s match every one of
## the five kit slots gets asked for several times.
const SIG_ROTATE_PERIOD: float = 2.4
## Minimum gap between two counted asks for the same slot. A press held across
## sixty frames is one intention, not sixty.
const ATTEMPT_MIN_GAP: float = 0.35
## Trailing window used by the stalemate check.
const STALEMATE_WINDOW: float = 10.0
## Real-time escape hatch. Hit-stop drops `Engine.time_scale` to 0.05, so a match
## that keeps connecting can burn far more wall-clock than game-clock; without
## this a pathological run would hang a CI job forever.
const WALL_CLOCK_FACTOR: float = 6.0

# ---- configuration ---------------------------------------------------------
var _mode: String = "duel"
var _master_seed: int = 20260727
var _duration: float = 20.0
var _classes: Array[int] = []
var _max_matches: int = 0
var _out_dir: String = "user://bot_sim"
var _strict: bool = false
## Which of the two conflicting readings of `cast_slot` to drive. See
## `_adapt_brain_intent` — running both is the measurement.
var _slot_map: String = "role"
## Difficulty tier handed to BotProfile. Reaction delay and error rate only.
var _difficulty: int = 2
## Difficulty for the SECOND fighter, when you want an asymmetric match. -1 means
## "the same as `--difficulty`", which is the default and the only fair pairing.
##
## ⚠ THIS IS THE ONLY HONEST WAY TO ASK "IS DIFFICULTY A REAL DIAL". Running the
## whole roster at one tier tells you which CLASSES win; it tells you nothing about
## whether an Impossible bot actually beats an Easy one, because both sides move
## together. `--difficulty=0 --difficulty-b=3` puts the tiers against each other and
## the win column answers the question directly.
var _difficulty_b: int = -1
var _profile_script: GDScript = null

# ---- run state -------------------------------------------------------------
var _queue: Array[Dictionary] = []
var _match_index: int = -1
var _arena: SimArena = null
var _fighters: Array[Dictionary] = []
var _elapsed: float = 0.0
var _wall_start_ms: int = 0
var _cooldown_frames: int = 0
var _spawn_delay: int = 0
var _anomalies: Array[Dictionary] = []
## "kind|pairing" -> {"at": float, "row": Dictionary}, for the repeat collapse in
## `_file`. Cleared per match so two matches never share a dedup window.
var _seen_findings: Dictionary = {}
## How long an identical finding is folded into the previous row instead of
## appending a new one. Long enough to swallow a per-frame detector firing
## through one event; short enough that two separate incidents stay two rows.
const FINDING_DEDUP_WINDOW: float = 1.5
var _matches: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seam: String = "unknown"            # "controller" | "input" | "none"
var _brain: GDScript = null              # BotBrain, when another agent has landed it
var _bot_controller_script: GDScript = null  # the shipped BotController, when present
## Trailing HP samples for the stalemate check: [{"t": float, "total": int}, ...]
var _hp_trail: Array[Dictionary] = []
var _done: bool = false


func _initialize() -> void:
	_parse_args()
	_resolve_seam()
	_build_queue()
	print("[sim] bot_sim starting — mode=%s seed=%d dur=%.1fs matches=%d seam=%s brain=%s"
		% [_mode, _master_seed, _duration, _queue.size(), _seam,
			"BotBrain" if _brain != null else "builtin"])
	_advance_match()


## One fixed 1/60 step. Sampling lives on the PHYSICS clock, not the render
## clock, so a run is reproducible regardless of how fast the machine draws.
func _physics_process(delta: float) -> bool:
	if _done:
		return true
	if _cooldown_frames > 0:
		# Let the freed arena actually leave the tree before the next one is built;
		# a spectacle still resolving from the previous match would otherwise leak
		# damage into the next pairing's numbers.
		_cooldown_frames -= 1
		if _cooldown_frames == 0:
			_advance_match()
		return false
	if _spawn_delay > 0:
		# ⚠ FIGHTERS ARE SPAWNED A FRAME AFTER THE ARENA, NOT IN THE SAME CALL.
		# A node added while the SceneTree is still inside `_initialize` does not
		# get its `_ready` synchronously, so `@onready var rig` is still null —
		# and calling `configure_class` on it throws "Nonexistent function
		# 'class_preset' in base 'Nil'" and leaves the hero half-configured with
		# no class, no kit and no signatures. Measured, not assumed: the first
		# smoke run failed exactly this way. Waiting a frame makes the ordering
		# identical to how the game itself builds an arena.
		_spawn_delay -= 1
		if _spawn_delay == 0:
			_spawn_fighters()
		return false
	if _arena == null or _fighters.is_empty():
		return false
	_tick_match(delta)
	return false


# ============================================================== configuration

func _parse_args() -> void:
	# Godot hands user arguments back through two different calls depending on
	# whether they were separated by `--` or `++`. Scanning both means the caller
	# does not have to remember which, and stray engine flags simply do not match
	# the `--key=value` shape below.
	var argv: Array = []
	argv.append_array(OS.get_cmdline_args())
	argv.append_array(OS.get_cmdline_user_args())
	for raw: String in argv:
		var arg: String = String(raw)
		if not arg.begins_with("--") or not arg.contains("="):
			if arg == "--strict":
				_strict = true
			continue
		var key: String = arg.substr(2, arg.find("=") - 2)
		var value: String = arg.substr(arg.find("=") + 1)
		match key:
			"mode": _mode = value
			"seed": _master_seed = int(value)
			"dur": _duration = maxf(float(value), 1.0)
			"out": _out_dir = value
			"max-matches": _max_matches = int(value)
			"slotmap": _slot_map = value
			"difficulty": _difficulty = clampi(int(value), 0, 3)
			"difficulty-b": _difficulty_b = clampi(int(value), 0, 3)
			"classes":
				for part: String in value.split(",", false):
					var id: int = int(part)
					if id >= 0 and id < CLASS_NAMES.size():
						_classes.append(id)
	if _classes.is_empty():
		for i: int in CLASS_NAMES.size():
			_classes.append(i)


## Work out how a hero can be driven at all, once, up front.
##
##   "controller" — the per-instance input seam exists, so TWO bots can fight.
##   "input"      — no seam yet; `Input` is process-global, so exactly ONE hero
##                  can be driven and the opponent has to be a target or an
##                  `Enemy` (which drives itself).
##
## Reporting the degradation loudly is the whole point: a harness that silently
## measured half a fight would be worse than one that refused to run.
func _resolve_seam() -> void:
	if FileAccess.file_exists(BOT_BRAIN_SCRIPT):
		_brain = load(BOT_BRAIN_SCRIPT) as GDScript
	if FileAccess.file_exists(BOT_PROFILE_SCRIPT):
		_profile_script = load(BOT_PROFILE_SCRIPT) as GDScript
	if FileAccess.file_exists(BOT_CONTROLLER_SCRIPT):
		_bot_controller_script = load(BOT_CONTROLLER_SCRIPT) as GDScript
	# The seam landed as `Hero.controller: Object` — deliberately UNtyped, so any
	# object with the six polled methods is accepted and the harness needs no
	# subclass of anything. `_register` still reads the property back after
	# assigning, so if `controller` is ever tightened to a concrete class the
	# rejection degrades to Input mode LOUDLY rather than producing a silent run
	# of motionless bots that reports a clean sweep.
	if FileAccess.file_exists(BOT_CONTROLLER_SCRIPT) \
			or FileAccess.file_exists(HERO_CONTROLLER_BASE):
		_seam = "controller"
		return
	_seam = "input"


## The match list. Duel is every unordered class pairing (36 for the full roster);
## vs_enemy is one match per class against the tower's own AI.
func _build_queue() -> void:
	var want_duel: bool = _mode == "duel" or _mode == "all"
	var want_enemy: bool = _mode == "vs_enemy" or _mode == "all"
	if want_duel:
		for i: int in _classes.size():
			for j: int in range(i + 1, _classes.size()):
				_queue.append({"kind": "duel", "a": _classes[i], "b": _classes[j]})
	if want_enemy:
		for c: int in _classes:
			_queue.append({"kind": "vs_enemy", "a": c, "b": -1})
	if _max_matches > 0 and _queue.size() > _max_matches:
		_queue.resize(_max_matches)


# ================================================================ match setup

func _advance_match() -> void:
	_match_index += 1
	if _match_index >= _queue.size():
		_finish_run()
		return
	_begin_match(_queue[_match_index])


func _begin_match(spec: Dictionary) -> void:
	# Per-match seeding from (master, index) so one match's RNG consumption cannot
	# shift the next match's stream — otherwise re-running a single pairing with
	# `--max-matches` would produce a different fight than the full sweep did.
	var match_seed: int = _master_seed + _match_index * 7919
	seed(match_seed)          # the engine-global RNG that game code reaches for
	_rng.seed = match_seed    # the driver's own stream
	_elapsed = 0.0
	_wall_start_ms = Time.get_ticks_msec()
	_hp_trail.clear()
	_fighters.clear()
	# A fresh dedup window per match: the same kind in a new pairing is a new
	# finding, and the clock restarts at 0 here anyway.
	_seen_findings.clear()
	# Deflects are counted PER MATCH, so "which pairing never parries" is answerable
	# rather than only "somebody parried at some point in the sweep".
	SpellDeflect.reset_counts()
	_arena = SimArena.new()
	root.add_child(_arena)
	_spawn_delay = 2       # see the note in _physics_process
	print("[sim] BEGIN match=%d pairing=%s seed=%d" % [_match_index, _pairing_label(), match_seed])


## Second half of match setup, one frame later, once the arena is genuinely live.
func _spawn_fighters() -> void:
	var spec: Dictionary = _queue[_match_index]
	if String(spec["kind"]) == "duel":
		_begin_duel(int(spec["a"]), int(spec["b"]))
	else:
		_begin_vs_enemy(int(spec["a"]))


func _begin_duel(a: int, b: int) -> void:
	var hero_a: CharacterBody2D = _arena.spawn_hero(a, -220.0)
	var hero_b: CharacterBody2D = _arena.spawn_hero(b, 220.0)
	# THE FACTION SEAM. Damage in this codebase used to be routed by the hardwired
	# group `"enemy"`, so two heroes swinging at each other did literally nothing.
	# `hostile_group` is what makes hero-vs-hero real; without these two lines the
	# whole duel mode measures an empty room. Set through `set_hostile` when the
	# hero publishes it (it also flips the collision mask) and by direct field
	# assignment otherwise.
	_make_hostile(hero_a, &"hero")
	_make_hostile(hero_b, &"hero")
	_register(hero_a, _labelled(CLASS_NAMES[a], 0), a, true, 0)
	# With no per-instance seam, `Input` drives BOTH heroes identically, which is
	# not a fight — it is one hero mirrored. So the second hero becomes a standing
	# target instead. That still answers the question this mode exists to ask:
	# does hero A's whole kit do ANY damage to hero B? Today it does not, and that
	# is the faction bug this harness was built to catch.
	var b_driven: bool = _seam == "controller"
	# The label carries the TIER when the two sides differ, so the balance table
	# reports "ARCANIST@Easy" against "ARCANIST@Impossible" instead of merging both
	# into one row and averaging the dial away.
	_register(hero_b, _labelled(CLASS_NAMES[b], 1), b, b_driven, 1)
	if not b_driven:
		hero_b.set_physics_process(false)   # stand still; take_damage still lands


## Class name, plus the tier when the two sides are on different ones.
func _labelled(name: String, side: int) -> String:
	if _difficulty_b < 0:
		return name
	var tier: int = _difficulty_b if side == 1 else _difficulty
	return "%s@%s" % [name, BotProfile.TIERS[clampi(tier, 0, 3)]["name"]]


func _begin_vs_enemy(a: int) -> void:
	var hero: CharacterBody2D = _arena.spawn_hero(a, -240.0)
	_register(hero, CLASS_NAMES[a], a, true, 0)
	# Enemies drive themselves, so this mode works with or without the input seam
	# and — unlike duel — damage routes in BOTH directions today. It is where the
	# real signal lives until the faction seam lands.
	for i: int in VS_ENEMY_ARCHETYPES.size():
		var foe: CharacterBody2D = _arena.spawn_enemy(
			VS_ENEMY_ARCHETYPES[i], 200.0 + float(i) * 130.0)
		_register(foe, "ENEMY_%d" % VS_ENEMY_ARCHETYPES[i], -1, false, 1)


## Point a hero's attacks at `group`. Prefers the published setter (which also
## fixes up the collision mask) and falls back to the bare field, so the harness
## keeps working whichever way the seam settles.
func _make_hostile(hero: CharacterBody2D, group: StringName) -> void:
	if hero.has_method("set_hostile"):
		hero.call("set_hostile", group)
	else:
		hero.set("hostile_group", group)


## Build the per-fighter record and, where possible, hand it its own controller.
func _register(node: CharacterBody2D, label: String, class_id: int, driven: bool,
		side: int) -> void:
	var rec: Dictionary = {
		"node": node, "label": label, "class_id": class_id, "driven": driven,
		"side": side,
		"is_hero": node.is_in_group("hero"),
		"ctrl": null, "inner": null,
		"max_hp": int(node.get("max_hp")),
		"hp_last": int(node.get("hp")),
		"damage_taken": 0, "mp_spent": 0.0,
		"pos_last": node.global_position, "moved": 0.0,
		"presses": 0, "idle_t": 0.0,
		"died_at": -1.0,
		"decide_t": 0.0, "sig_t": 0.0,
		"want_slot": -1, "sig_step_cool": 0,
		"sig_attempts": {}, "sig_fires": {}, "sig_blockers": {},
		# slot index -> how many frames the brain committed that slot. The ONLY
		# honest answer to "does the bot use its whole 4+1 kit", because it is
		# taken straight off the published intent with no gate in front of it.
		"slot_presses": {},
		## verb -> frames the brain held it. See `_observe_bot_intent`.
		"verb_presses": {},
		"last_attempt_t": -99.0, "last_slot_press_t": -99.0,
		"pending": {},               # {"id": String, "frames": int}
		"probe_ok": true,
		"aim": Vector2.RIGHT,
	}
	if rec["is_hero"]:
		rec["mp_last"] = float(node.get("mp"))
		rec["probe_ok"] = _check_probe(node, label)
	if driven and _seam == "controller":
		# THE SHIPPED PATH, not a harness imitation of it. `BotController` builds
		# its own blackboard, asks `BotBrain`, and derives its own press edges;
		# `Hero._physics_process` calls `controller.tick(self, _bot_clock)` once a
		# frame. So the sim attaches the real thing and then only WATCHES. That is
		# the difference between measuring the game's bot and measuring a mock of
		# it — and it is the only version worth putting in a clip.
		var ctrl: RefCounted = null
		if _bot_controller_script != null:
			ctrl = _bot_controller_script.new()
			ctrl.set("brain", _brain)
			ctrl.set("profile", _profile_for(rec))
		else:
			# No BotController in the tree: fall back to the harness's own virtual
			# gamepad, driven by the built-in driver below. Strictly worse — it
			# measures a mock instead of the shipped bot — so it is only ever a
			# degradation path, and the seam line in the report says which ran.
			ctrl = (load(CONTROLLER_SCRIPT) as GDScript).new()
		node.set("controller", ctrl)
		# READ IT BACK. A strictly-typed property silently refuses a value it does
		# not accept, and a controller that was never installed would produce a
		# perfectly quiet, perfectly wrong "this bot never acted" run.
		if node.get("controller") == null:
			_file(BotSimProbe.SEV_ERROR, "seam_rejected",
				"%s: Hero.controller refused the harness controller — falling back to Input"
					% label)
			_seam = "input"
		else:
			rec["ctrl"] = ctrl
			# `inner` is only populated on the fallback path, where the harness's
			# own controller IS the button state. With the shipped BotController
			# attached there is nothing for the harness to press.
			rec["inner"] = ctrl if _bot_controller_script == null else null
	# ⚠ A DEATH HAS TO BE HEARD, NOT POLLED — and until this landed THIS HARNESS COULD
	# NOT REPORT A KILL AT ALL. `Hero.take_damage` emits `health_changed(0, max)` and
	# THEN calls `_die()`; `_die()` outside a run and outside a net session (which a sim
	# match is, on both counts) runs `hp = max_hp` and returns. So by the time `_sample`
	# polls `hp <= 0` the body has already been healed to full, inside the same call.
	#
	# The damage was always real: an ARCANIST vs BRAWLER bout at --dur=180 burned 2319
	# damage across a combined 205 max HP — eleven full health bars — and was scored a
	# DRAW. Every "0 kill / N points" line this harness has ever printed, and every
	# balance number derived from `hp_last`, was ranking resurrected bodies. That is
	# also the whole "Brawler win rate is disputed between two harnesses" disagreement.
	#
	# `BotMatch.gd` already documents and works around exactly this; the sim never got
	# the same treatment. Same fix, same reason.
	if bool(rec["is_hero"]) and node.has_signal(&"health_changed"):
		node.health_changed.connect(_on_fighter_health.bind(rec))
	_fighters.append(rec)


## The real moment of death, caught off the signal before `_die()` heals it away.
func _on_fighter_health(current: int, _maximum: int, rec: Dictionary) -> void:
	if current > 0 or float(rec["died_at"]) >= 0.0:
		return
	rec["died_at"] = _elapsed
	rec["hp_last"] = 0
	if BotSimProbe.fast_kill(_elapsed):
		_file(BotSimProbe.SEV_WARN, "fast_kill",
			"%s died %.2fs into the fight" % [rec["label"], _elapsed])


## Confirm every dynamically-reached Hero member still exists, by name. A rename
## upstream would otherwise abort the sampling function mid-way and hand back a
## zero that reads as "no anomalies" — the exact silent-pass failure mode the
## house test rules exist to prevent.
func _check_probe(node: Object, label: String) -> bool:
	var present: Dictionary = {}
	for p: Dictionary in node.get_property_list():
		present[String(p["name"])] = true
	var missing: Array[String] = []
	for name: String in HERO_PROBE_MEMBERS:
		if not present.has(name):
			missing.append(name)
	for name: String in HERO_PROBE_METHODS:
		if not node.has_method(name):
			missing.append("%s()" % name)
	if missing.is_empty():
		return true
	_file(BotSimProbe.SEV_ERROR, "harness_probe_missing",
		"%s: Hero no longer declares %s — those detectors are DISABLED this run"
			% [label, ", ".join(missing)])
	return false


# ===================================================================== ticking

func _tick_match(delta: float) -> void:
	_elapsed += delta
	for rec: Dictionary in _fighters:
		if not _alive(rec):
			continue
		_drive(rec, delta)
		_sample(rec, delta)
	_check_world_integrity()
	_check_stalemate()
	var reason: String = _end_reason()
	if reason != "":
		_end_match(reason)


func _alive(rec: Dictionary) -> bool:
	var node: Node = rec["node"]
	return node != null and is_instance_valid(node) and not node.is_queued_for_deletion()


# ---- the driver ------------------------------------------------------------

## Decide and apply this fighter's inputs.
##
## The intent comes from `BotBrain.decide` when another agent has landed it, and
## from the built-in driver below otherwise, so this harness is useful before the
## brain exists and becomes a test OF the brain the moment it does.
func _drive(rec: Dictionary, delta: float) -> void:
	if not bool(rec["driven"]):
		return
	var node: CharacterBody2D = rec["node"]
	var foe: Dictionary = _opponent_of(rec)
	if foe.is_empty():
		return
	var foe_node: Node2D = foe["node"]
	var ctrl: Object = rec["ctrl"]
	if ctrl != null and ctrl.has_method("tick"):
		# The hero already ticked its own controller this frame. Nothing to drive —
		# just read what the brain asked for, so the reachability counters still
		# see every ask without the harness inventing any of them.
		_observe_bot_intent(rec, ctrl)
		return
	rec["decide_t"] = float(rec["decide_t"]) - delta
	rec["sig_t"] = float(rec["sig_t"]) - delta
	var intent: Dictionary = {}
	if _brain != null and _brain.has_method("decide"):
		var raw: Variant = _brain.call("decide", _blackboard(rec, foe_node),
			_profile_for(rec))
		if typeof(raw) == TYPE_DICTIONARY:
			intent = _adapt_brain_intent(rec, raw)
	if intent.is_empty():
		intent = _builtin_intent(rec, node, foe_node)
	_apply_intent(rec, intent)


## Read the shipped bot's own latched intent and fold it into the counters.
##
## `BotController` publishes `intent` precisely so a test or an overlay can see
## what the brain wanted without re-running it. Slot 4 is the ult in BotIntent's
## numbering, and the ult is the only slot that reaches a kit signature — which is
## itself the finding this counter exists to prove.
func _observe_bot_intent(rec: Dictionary, ctrl: Object) -> void:
	var raw: Variant = ctrl.get("intent")
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var i: Dictionary = raw
	rec["aim"] = i.get("aim", rec["aim"])
	var slot: int = int(i.get("cast_slot", -1))
	# ⚠ THE COMMENT ABOVE USED TO SAY "slot 4 is the only one that reaches a kit
	# signature", and this line used to read `== 4` because of it. That stopped
	# being true when `cast_slot` 0..4 became a direct index into
	# `Hero._signatures` — so the harness was measuring one fifth of the kit and
	# reporting the other four as never used. THE ANSWER TO "DO BOTS USE THEIR
	# WHOLE KIT" WAS AN ARTEFACT OF THIS LINE.
	#
	# `slot_presses` is the honest histogram: it counts what the brain committed,
	# per slot, with none of `_note_signature_attempt`'s gating (which exists to
	# answer a different question — "the gate was open and nothing came out").
	if slot >= 0:
		var hist: Dictionary = rec["slot_presses"]
		hist[slot] = int(hist.get(slot, 0)) + 1
		# Only one press per decision latch reaches the body, so debounce the same
		# way the attempt counter does or a 0.22 s latch is 13 identical rows.
		if _elapsed - float(rec.get("last_slot_press_t", -99.0)) >= ATTEMPT_MIN_GAP:
			rec["last_slot_press_t"] = _elapsed
			# ⚠ THE SLOT COMES FROM THE INTENT, not from `Hero._signature_index`.
			# Reading the hero's own index here was a RACE: the controller applies
			# `bot_select_signature` and the body consumes the press inside the same
			# physics frame, so by the time this ran the selection could already have
			# moved on and the slot's cooldown could already be ticking — which made
			# `signature_ready()` false and the attempt silently un-recorded. That is
			# what produced nine `no_castable_signature` rows for bots the histogram
			# shows using all three slots.
			_note_signature_attempt(rec, slot)
	# WHICH VERBS, not just how many. "Does the bot use its whole kit" is a question
	# about the ABILITY buttons and the melee swing as much as about the three kit
	# slots — and those three were never counted here, which is part of why nobody
	# noticed the brain had never pressed one. `verb_presses` is the histogram that
	# makes a missing verb visible in the summary instead of only in play.
	var held: int = 0
	for key: String in ["fire", "swing", "dash", "guard", "jump",
			"ability_blast", "ability_blink", "ability_nova"]:
		if bool(i.get(key, false)):
			held += 1
			var verbs: Dictionary = rec["verb_presses"]
			verbs[key] = int(verbs.get(key, 0)) + 1
	if i.has("cast_slot") and int(i["cast_slot"]) >= 0:
		held += 1
	rec["presses"] = int(rec["presses"]) + held


## The difficulty dial, and the only thing the harness varies between bots.
## Everything in a profile is reaction delay and error rate — never knowledge and
## never stats, because a bot that cheats produces a worthless bug report and a
## dishonest clip. Falls back to an empty dict when `BotProfile` has not landed,
## which every consumer treats as "defaults".
func _profile_for(_rec: Dictionary) -> Dictionary:
	if _profile_script == null:
		return {}
	# Side 1 may run a different tier — see `_difficulty_b`.
	var tier: int = _difficulty
	if _difficulty_b >= 0 and int(_rec.get("side", 0)) == 1:
		tier = _difficulty_b
	# `of(tier)` is BotProfile's own accessor; the alternates are checked so a
	# rename upstream degrades to defaults instead of throwing every frame.
	for method: String in ["of", "get_profile", "for_tier"]:
		if _profile_script.has_method(method):
			return _profile_script.call(method, tier)
	return {}


## Translate BotBrain's intent vocabulary into the buttons a Hero actually reads.
##
## ⚠ THIS IS WHERE THE TWO LIVE MODULES DISAGREE, and the harness measures the
## disagreement rather than picking a winner:
##
##   BotBrain says  "cast_slot: 0..3 spell slots, 4 = ult", and its whole scorer
##                  rests on SpellLibrary.ROLE_ORDER — slot 0 is ALWAYS the kit's
##                  damage line, slot 3 the payoff, slot 4 the ult.
##   BotController  maps those same indices through SLOT_ACTIONS to the hero's
##                  Q / R / T / melee / G buttons, which are a DIFFERENT five
##                  things entirely. Only index 4 lines up by coincidence.
##
## `--slotmap=role` drives what the brain means (select the signature, then fire
## it); `--slotmap=controller` drives what ships today. Running both is how the
## sim turns "these disagree" from an assertion into a measurement.
func _adapt_brain_intent(rec: Dictionary, raw: Dictionary) -> Dictionary:
	var move: Vector2 = raw.get("move", Vector2.ZERO)
	var intent: Dictionary = {
		"aim": raw.get("aim", rec["aim"]),
		"move_x": move.x,
		"cast": bool(raw.get("fire", false)),
		"dash": bool(raw.get("dash", false)),
		"parry": bool(raw.get("guard", false)),
		"jump": bool(raw.get("jump", false)) or move.y < -0.5,
		"melee": false, "blast": false, "blink": false, "nova": false,
		"ultimate": false, "cycle_signature": false,
	}
	if not raw.has("cast_slot"):
		return intent
	var slot: int = int(raw["cast_slot"])
	if slot < 0 or slot >= 5:
		return intent
	if _slot_map == "controller":
		# What ships: the slot index is a direct button. Q / R / T / melee / G.
		var actions: Array[String] = ["blast", "blink", "nova", "melee", "ultimate"]
		intent[actions[slot]] = true
		return intent
	# What the brain means: slot index is the KIT ROLE, so the hero has to select
	# that signature first. Latched, because reaching it takes several frames of
	# cycling and re-deciding every frame would leave the bot cycling forever.
	rec["want_slot"] = slot
	return intent


## What a bot is allowed to know: the same things a player reads off the screen —
## the opponent's drawn body, its own floating HP/MP bars, its own cooldown pips,
## the drawn telegraph rings and the projectiles in flight. Nothing privileged.
##
## The key names are BotBrain's documented contract, not this harness's
## preference. Getting that wrong is not a stylistic matter: feeding
## `Hero.ability_hud_state()` straight into `"cooldowns"` — which is what the
## build plan tells implementers to do — hands the scorer an Array of
## DICTIONARIES where it documents an Array of FLOATS, and `float(Dictionary)`
## throws "Nonexistent 'float' constructor" every frame. That is a real finding,
## filed as `blackboard_contract_mismatch`; the shape below is the documented one.
func _blackboard(rec: Dictionary, foe: Node2D) -> Dictionary:
	var node: CharacterBody2D = rec["node"]
	var max_hp: float = maxf(float(rec["max_hp"]), 1.0)
	var max_mp: float = maxf(float(node.get("max_mp")), 1.0)
	var foe_max: float = maxf(float(foe.get("max_hp")), 1.0)
	return {
		"now": _elapsed,
		"self_pos": node.global_position,
		"self_vel": node.velocity,
		"self_hp_frac": clampf(float(node.get("hp")) / max_hp, 0.0, 1.0),
		"self_mp_frac": clampf(float(node.get("mp")) / max_mp, 0.0, 1.0),
		"on_floor": node.is_on_floor(),
		"facing": signf(float(rec["aim"].x)),
		"foe_pos": foe.global_position,
		"foe_vel": foe.get("velocity") if foe.get("velocity") != null else Vector2.ZERO,
		"foe_hp_frac": clampf(float(foe.get("hp")) / foe_max, 0.0, 1.0),
		"foe_facing": 0.0,
		"threats": _visible_threats(node),
		"hazards": [],                      # this stage has no pits, by design
		"cooldowns": _slot_cooldowns(node),
		"class_id": int(rec["class_id"]),
		"reach": 58.0,
		"dash_ready": float(node.get("_dash_cooldown_timer")) <= 0.0,
		"blink_ready": float(node.get("_blink_cooldown_timer")) <= 0.0,
	}


## Per-slot cooldowns in the shape BotBrain documents: one float per slot, 0.0 =
## ready.
##
## ⚠ WHICH FIVE THINGS "THE SLOTS" ARE IS ITSELF CONTESTED, which is why this is
## a switch. Under `role` (what BotBrain means: SpellLibrary.ROLE_ORDER, slot 0 =
## the damage line, slot 4 = the ult) all five kit spells share ONE timer on the
## hero — `_signature_cd_timer` — so the honest answer is the same value five
## times. Under `controller` (what BotController.SLOT_ACTIONS actually presses)
## the five are Q / R / T / melee / G, which do have five separate timers.
## ⚠ THE "ONE SHARED TIMER" NOTE ABOVE IS HISTORY. `HandSlots` owns a real cooldown
## per slot now, so the honest answer under `role` is genuinely per-slot — and the
## hand is THREE spells (`SpellTier.SLOT_COUNT`), not five. The whole array is
## delegated to the body's own `bot_body_state()` where possible, which is what the
## shipped `BotController` reads: two harnesses deriving the same array two different
## ways is exactly how they drift.
func _slot_cooldowns(node: CharacterBody2D) -> Array:
	if _slot_map != "controller" and node.has_method("bot_body_state"):
		var own: Dictionary = node.call("bot_body_state")
		var cds: Variant = own.get("cooldowns")
		if cds is Array:
			return cds as Array
	if _slot_map == "controller":
		return [
			float(node.get("_blast_cooldown_timer")),
			float(node.get("_blink_cooldown_timer")),
			float(node.get("_nova_cooldown_timer")),
			float(node.get("_melee_cooldown_timer")),
			float(node.call("signature_cooldown", 0)),
		]
	var out: Array = []
	for i: int in 3:
		out.append(float(node.call("signature_cooldown", i)))
	return out


## Threats this body could see drawn on screen: live projectiles and live
## telegraph regions. Descriptors follow BotBrain's `_normalise` shape.
##
## ⚠ Only `player_spell` / `enemy_projectile` members are read through their
## transform, because those are genuinely moving bodies. Telegraphs are asked for
## their own published geometry — every other spectacle in this codebase parks at
## the arena origin and would report (0, 0).
func _visible_threats(me: CharacterBody2D) -> Array:
	var out: Array = []
	for group: String in ["player_spell", "enemy_projectile"]:
		for n: Node in get_nodes_in_group(group):
			if not (n is Node2D) or n == me:
				continue
			var p: Vector2 = (n as Node2D).global_position
			if BotSimProbe.position_is_broken(p):
				continue
			var vel: Vector2 = Vector2.from_angle((n as Node2D).rotation) \
				* (460.0 if group == "player_spell" else 260.0)
			if n.has_method("travel_velocity"):
				vel = n.call("travel_velocity")
			out.append({"kind": "projectile", "pos": p, "vel": vel,
				"id": n.get_instance_id(), "damage": int(n.get("damage")) if n.get("damage") != null else 0,
				"parryable": n.has_method("reflect")})
	for n: Node in get_nodes_in_group("telegraph"):
		if not n.has_method("danger_shape"):
			continue
		var shape: Dictionary = n.call("danger_shape")
		shape["id"] = n.get_instance_id()
		shape["tti"] = float(n.call("time_to_fire")) if n.has_method("time_to_fire") else 0.5
		out.append(shape)
	return out


## The harness's own brain — deliberately simple, deliberately fair.
##
## It exists to EXERCISE the game, not to play it well: hold a band, aim at the
## opponent, throw the primary constantly, and rotate deterministically through
## all five kit slots so every spell in every class gets asked for. That rotation
## is what turns "this spell never fired" into a measurement.
func _builtin_intent(rec: Dictionary, node: CharacterBody2D, foe: Node2D) -> Dictionary:
	var to_foe: Vector2 = foe.global_position - node.global_position
	var dist: float = to_foe.length()
	var intent: Dictionary = {
		"aim": to_foe.normalized() if dist > 1.0 else Vector2.RIGHT,
		"move_x": 0.0, "cast": false, "melee": false, "dash": false,
		"blast": false, "blink": false, "nova": false, "parry": false,
		"jump": false, "ultimate": false, "cycle_signature": false,
	}
	# Hold the band. Closing when far and backing off when close is what keeps a
	# ranged kit throwing and a melee kit connecting, without either bot parking.
	if dist > PREFERRED_RANGE + 40.0:
		intent["move_x"] = signf(to_foe.x)
	elif dist < PREFERRED_RANGE - 60.0:
		intent["move_x"] = -signf(to_foe.x)
	if float(rec["decide_t"]) <= 0.0:
		rec["decide_t"] = DECIDE_INTERVAL
		# The primary is held whenever it is legal; the hero's own cooldown gate
		# decides whether it comes out, which is exactly how a player plays it.
		intent["cast"] = true
		if dist < MELEE_RANGE:
			intent["melee"] = true
		var roll: float = _rng.randf()
		if roll < 0.18:
			intent["dash"] = true
		elif roll < 0.30:
			intent["blast"] = true
		elif roll < 0.40:
			intent["blink"] = true
		elif roll < 0.48:
			intent["nova"] = true
		elif roll < 0.56:
			intent["parry"] = true
		elif roll < 0.64:
			intent["jump"] = true
	# Deterministic signature rotation: step to the next slot, then ask for it on
	# the following decision. Every kit slot therefore gets several honest asks
	# per match, which is what the never-fired detector needs to mean anything.
	if float(rec["sig_t"]) <= 0.0:
		rec["sig_t"] = SIG_ROTATE_PERIOD
		intent["cycle_signature"] = true
	elif float(rec["sig_t"]) < SIG_ROTATE_PERIOD - 0.25 \
			and float(rec["sig_t"]) > SIG_ROTATE_PERIOD - 0.45:
		intent["ultimate"] = true
	return intent


## Turn an intent into held buttons — through this fighter's own controller when
## the seam exists, or through the process-global `Input` when it does not.
func _apply_intent(rec: Dictionary, intent: Dictionary) -> void:
	_resolve_want_slot(rec, intent)
	var aim: Vector2 = intent.get("aim", Vector2.RIGHT)
	rec["aim"] = aim
	var move_x: float = float(intent.get("move_x", 0.0))
	var pressed: int = 0
	# The ultimate is pre-flighted BEFORE the press so the harness knows whether
	# the gate was genuinely open. An attempt made into a running cooldown proves
	# nothing about whether the spell works.
	if bool(intent.get("ultimate", false)):
		# The FALLBACK driver's path (no shipped BotController). It presses `ultimate`
		# against whatever the hero currently has selected, so `_signature_index` IS
		# the right slot here — unlike the shipped path, where the intent carries it.
		_note_signature_attempt(rec, int((rec["node"] as Node).get("_signature_index")))
	var ctrl: RefCounted = rec["ctrl"]
	if ctrl != null:
		var inner: RefCounted = rec["inner"]
		inner.clear()
		inner.aim_dir = aim
		if move_x > 0.1:
			inner.press(&"move_right")
		elif move_x < -0.1:
			inner.press(&"move_left")
		for key: String in ["cast", "melee", "dash", "parry", "blast", "blink",
				"nova", "jump", "ultimate", "cycle_signature"]:
			if bool(intent.get(key, false)):
				inner.press(StringName(key))
				pressed += 1
		inner.commit()
	else:
		# Global-Input path. Only ever ONE fighter is driven this way (see
		# `_begin_duel`), because two would share the same buttons.
		_release_all_actions()
		if move_x > 0.1:
			Input.action_press(&"move_right")
		elif move_x < -0.1:
			Input.action_press(&"move_left")
		# There is no mouse in a headless run, so aim goes through the analog
		# `aim_*` actions — the same stick a phone player uses. Using the mouse
		# path instead would aim every spell at the viewport origin.
		var a: Vector2 = aim.normalized()
		if a.x >= 0.0:
			Input.action_press(&"aim_right", a.x)
		else:
			Input.action_press(&"aim_left", -a.x)
		if a.y >= 0.0:
			Input.action_press(&"aim_down", a.y)
		else:
			Input.action_press(&"aim_up", -a.y)
		for key: String in ["cast", "melee", "dash", "parry", "blast", "blink",
				"nova", "jump", "ultimate", "cycle_signature"]:
			if bool(intent.get(key, false)):
				Input.action_press(StringName(key))
				pressed += 1
	rec["presses"] = int(rec["presses"]) + pressed


## Walk the hero's signature selector to the slot the brain asked for, then fire.
##
## A hero has no "cast slot N" button: all five kit spells live behind ONE key
## (`ultimate`) and `cycle_signature` steps which of them it will cast. So
## reaching slot 3 means pressing the selector until `_signature_index` says 3.
##
## ⚠ THIS IS EXACTLY WHAT `BotController.FORBIDDEN` MAKES IMPOSSIBLE. It hard-
## returns false for `cycle_signature`, on the reasoning that it "rewrites the
## loadout mid-fight". It does not — it is the selector, not a re-roll — and
## suppressing it strands every bot on signature index 0 for the whole match,
## which puts four of every class's five curated spells permanently out of reach.
## The harness presses it deliberately so the other four can be measured at all;
## the divergence is filed in the report.
##
## The alternate-frame gate exists because `_cycle_signature` runs on a
## just_pressed EDGE: a button held down for three frames is one press, so the
## selector has to be released between steps.
func _resolve_want_slot(rec: Dictionary, intent: Dictionary) -> void:
	var want: int = int(rec.get("want_slot", -1))
	if want < 0 or not bool(rec["is_hero"]) or not bool(rec["probe_ok"]):
		return
	rec["sig_step_cool"] = maxi(int(rec.get("sig_step_cool", 0)) - 1, 0)
	var current: int = int(rec["node"].get("_signature_index"))
	if current == want:
		intent["ultimate"] = true
		rec["want_slot"] = -1
		return
	if int(rec["sig_step_cool"]) <= 0:
		intent["cycle_signature"] = true
		rec["sig_step_cool"] = 2      # release for a frame so the next press is an edge


func _release_all_actions() -> void:
	for a: StringName in ALL_ACTIONS:
		Input.action_release(a)


# ---- signature (spell-slot) reachability ------------------------------------

## Record that this fighter ASKED for its current signature with the gate open.
##
## `_cast_signature` sets `_signature_cd_timer = spell.cooldown` and deducts the
## mana the instant it commits, so an attempt made while the cooldown is at zero
## and mana covers the cost either fires on the next frame or is a defect.
func _note_signature_attempt(rec: Dictionary, slot: int) -> void:
	if not bool(rec["is_hero"]) or not bool(rec["probe_ok"]):
		return
	var node: CharacterBody2D = rec["node"]
	if not node.has_method("signature_at"):
		return
	var spell: Object = node.call("signature_at", slot)
	if spell == null:
		return    # the class does not hold that slot; nothing was asked for
	var id: String = String(spell.get("id"))
	# THE PER-SLOT COOLDOWN, through the public accessor. There is no shared bank any
	# more (`HandSlots` owns one timer per slot), and the mana gate is gone from
	# `Hero._cast_signature` entirely — so "the gate was open" now means exactly one
	# thing: this slot's own timer is at zero.
	#
	# Checked against the PREVIOUS frame's reading rather than this one, because the
	# body may already have consumed the press: a cooldown that is ticking RIGHT NOW
	# on the slot we just asked for is a FIRE, not a shut gate. `_resolve` below is
	# what tells the two apart; here we only refuse when the slot was on cooldown and
	# STAYS on cooldown, which is the genuinely uninformative case.
	var already: float = float(node.call("signature_cooldown", slot))
	var spell_cd: float = float(spell.get("cooldown"))
	if already > 0.0 and already < spell_cd - 0.05:
		return    # mid-cooldown from an earlier cast; this press proves nothing
	# ONE ATTEMPT PER GAP, not one per frame. Without this a spell that never
	# fires accumulates an attempt on all 60 frames of every second — the count
	# stops meaning "how many times a player would have tried" and the report
	# reads as noise rather than as a measurement.
	if _elapsed - float(rec.get("last_attempt_t", -99.0)) < ATTEMPT_MIN_GAP:
		return
	rec["last_attempt_t"] = _elapsed
	var attempts: Dictionary = rec["sig_attempts"]
	attempts[id] = int(attempts.get(id, 0)) + 1
	# Record WHY it might not come out, so a `spell_never_fired` row is actionable
	# instead of merely alarming. These are the four states in Hero that swallow
	# an `ultimate` press before `_cast_signature` is ever reached.
	var blockers: Array[String] = []
	if bool(node.get("is_dashing")):
		blockers.append("dashing")
	if bool(node.get("_channeling")):
		blockers.append("channeling")
	if bool(node.get("_summoning")):
		blockers.append("summoning")
	if node.get("_guard") != null:
		blockers.append("guarding")
	var seen: Dictionary = rec["sig_blockers"]
	seen[id] = blockers if blockers.is_empty() else blockers
	# The SLOT travels with the attempt: resolution asks that slot's own timer, and
	# the bot may have re-selected by the time the answer arrives.
	rec["pending"] = {"id": id, "slot": slot, "frames": 6}


## Resolve last frame's attempt. A commit is unmistakable: the cooldown timer went
## positive. Checked over a few frames rather than one because a press can be
## consumed a frame late by the input buffer.
func _resolve_signature_attempt(rec: Dictionary) -> void:
	var pending: Dictionary = rec["pending"]
	if pending.is_empty():
		return
	var node: CharacterBody2D = rec["node"]
	# A commit is unmistakable: THAT SLOT's own timer went positive. Reads the public
	# accessor, because the shared `_signature_cd_timer` bank this used to poll no
	# longer exists (see HERO_PROBE_MEMBERS).
	if float(node.call("signature_cooldown", int(pending.get("slot", 0)))) > 0.0:
		var fires: Dictionary = rec["sig_fires"]
		var id: String = String(pending["id"])
		fires[id] = int(fires.get(id, 0)) + 1
		rec["pending"] = {}
		return
	pending["frames"] = int(pending["frames"]) - 1
	if int(pending["frames"]) <= 0:
		rec["pending"] = {}


# ---- per-fighter sampling ---------------------------------------------------

func _sample(rec: Dictionary, delta: float) -> void:
	var node: CharacterBody2D = rec["node"]
	var pos: Vector2 = node.global_position
	# World integrity, per body. `position_is_broken` is checked first because a
	# NaN makes every subsequent geometric test meaningless.
	if BotSimProbe.position_is_broken(pos):
		_file(BotSimProbe.SEV_ERROR, "nan_position",
			"%s reached a non-finite position %s" % [rec["label"], pos])
		node.global_position = Vector2(0.0, SimArena.FLOOR_Y - 40.0)  # so the run continues
	elif BotSimProbe.escaped_bounds(pos, SimArena.bounds()):
		_file(BotSimProbe.SEV_ERROR, "body_escaped_bounds",
			"%s left the arena at %s (bounds %s)" % [rec["label"], pos, SimArena.bounds()])
		node.global_position = Vector2(0.0, SimArena.FLOOR_Y - 40.0)
	elif BotSimProbe.below_floor(pos.y, SimArena.FLOOR_Y):
		# ⚠ X MATTERS AS MUCH AS Y, and leaving it out of the row is what made this
		# finding unreadable. The slab only spans FLOOR_X0..FLOOR_X1; past that
		# there is nothing to stand on, so a body out there is FALLING PAST THE
		# EDGE, not sinking through the ground — a different thing entirely, and on
		# a stage with ring-out zones it is not even a bug.
		var off_slab: bool = pos.x < SimArena.FLOOR_X0 or pos.x > SimArena.FLOOR_X1
		# ⚠ TWO DIFFERENT EVENTS, AND CONFLATING THEM WAS THE BUG IN THE REPORT.
		#
		# MEASURED, not assumed: with x in the row, every single `body_below_floor`
		# in the ranged-class sweep turned out to be `off_slab` — a fighter knocked
		# clean past the ±900 slab by a big hit, then falling through the empty air
		# where this harness simply has no floor. Nothing sank through the ground.
		# On the real `VersusArena` that same fall is a RING-OUT, the central
		# mechanic of the stage; here it is a limit of a deliberately minimal test
		# arena. Filing it as an ERROR called "fell through the floor" sent the
		# maker hunting a collision bug that does not exist.
		#
		# So the off-slab case gets its own kind and WARN severity — still visible
		# (it does mean knockback is throwing bodies past the test geometry, worth
		# knowing) but no longer masquerading as a world-integrity defect. The
		# genuine article, a body inside the slab, stays an ERROR.
		if off_slab:
			_file(BotSimProbe.SEV_WARN, "body_off_test_slab",
				"%s was knocked past the edge of the test slab and fell at %s "
				% [rec["label"], pos]
				+ "(slab x=%.0f..%.0f) — a ring-out on the real stage, not a floor bug"
					% [SimArena.FLOOR_X0, SimArena.FLOOR_X1],
				{"off_slab": true, "x": pos.x, "y": pos.y})
		else:
			_file(BotSimProbe.SEV_ERROR, "body_below_floor",
				"%s sank through the floor at %s (floor y=%.1f)"
					% [rec["label"], pos, SimArena.FLOOR_Y],
				{"off_slab": false, "x": pos.x, "y": pos.y})
		# ⚠ AND THE RECOVERY HAS TO PUT IT BACK ON THE SLAB. The old one preserved
		# x — so a body that had fallen off the EDGE was teleported back to the same
		# x, which is still over nothing, and fell again immediately. One knockback
		# then produced an unbounded stream of rows for as long as the match ran.
		# Clamping x well inside the span makes the recovery actually recover.
		node.global_position = Vector2(
			clampf(pos.x, SimArena.FLOOR_X0 + 80.0, SimArena.FLOOR_X1 - 80.0),
			SimArena.FLOOR_Y - 40.0)

	# Health. Sampled rather than signal-driven so it catches every path that can
	# move HP, including ones that forget to emit `health_changed`.
	var hp: int = int(node.get("hp"))
	var max_hp: int = int(rec["max_hp"])
	if BotSimProbe.hp_out_of_range(hp, max_hp):
		_file(BotSimProbe.SEV_ERROR, "hp_out_of_range",
			"%s hp=%d outside [0, %d]" % [rec["label"], hp, max_hp])
	var drop: int = int(rec["hp_last"]) - hp
	if drop > 0:
		rec["damage_taken"] = int(rec["damage_taken"]) + drop
		if BotSimProbe.damage_outlier(drop, max_hp):
			# WARN, not ERROR. An implausible hit is a signal for the maker to
			# look at a number — it is not the harness's place to call it a defect
			# or, worse, to tune it.
			_file(BotSimProbe.SEV_WARN, "damage_outlier",
				"%s took %d in one sample (%.0f%% of %d max HP)"
					% [rec["label"], drop, 100.0 * float(drop) / float(max_hp), max_hp])
	# ⚠ ONCE DEAD, STAY DEAD. `_die()` heals the body back to `max_hp` outside a run,
	# so polling `hp` here would resurrect the record the `health_changed` listener
	# just wrote — and the judge would rank a corpse at full health. The signal is the
	# authority on death; this poll only tracks the living.
	if float(rec["died_at"]) >= 0.0:
		return
	rec["hp_last"] = hp
	if hp <= 0:
		rec["died_at"] = _elapsed
		if BotSimProbe.fast_kill(_elapsed):
			_file(BotSimProbe.SEV_WARN, "fast_kill",
				"%s died %.2fs into the fight" % [rec["label"], _elapsed])

	if bool(rec["is_hero"]) and bool(rec["probe_ok"]):
		var mp: float = float(node.get("mp"))
		var spent: float = float(rec["mp_last"]) - mp
		if spent > 0.0:
			rec["mp_spent"] = float(rec["mp_spent"]) + spent
		rec["mp_last"] = mp
		_resolve_signature_attempt(rec)

	# Liveness. A driven fighter that neither moves nor presses anything for a
	# whole window has stopped acting — a latched state, or a brain that threw.
	var moved: float = pos.distance_to(rec["pos_last"])
	rec["pos_last"] = pos
	if bool(rec["driven"]):
		rec["moved"] = float(rec["moved"]) + moved
		rec["idle_t"] = float(rec["idle_t"]) + delta
		if BotSimProbe.actor_idle(float(rec["moved"]), int(rec["presses"]),
				float(rec["idle_t"])):
			_file(BotSimProbe.SEV_ERROR, "actor_idle",
				"%s stopped acting: %.1f px and %d presses over %.1fs"
					% [rec["label"], rec["moved"], rec["presses"], rec["idle_t"]])
		if float(rec["idle_t"]) >= BotSimProbe.IDLE_SECONDS:
			rec["idle_t"] = 0.0
			rec["moved"] = 0.0
			rec["presses"] = 0


# ---- world-level checks -----------------------------------------------------

## Spell effects that resolve below the ground plane. Spells passing through
## terrain has been the single biggest bug class this month, so it gets a check
## of its own rather than being left to the maker's eye in a clip.
##
## ⚠ ONLY GROUP `player_spell` IS READ THROUGH ITS TRANSFORM, and only because
## `Spell.gd` documents itself as the one spectacle where the node genuinely IS
## the effect. Every other spectacle parks at the arena origin and draws in world
## coordinates, so reading `global_position` off one would report (0, 0) and
## produce a stream of false positives. Those are read through
## `danger_shape()` / `lane_geometry()` when they publish one, and skipped when
## they do not.
func _check_world_integrity() -> void:
	for n: Node in get_nodes_in_group("player_spell"):
		if not (n is Node2D):
			continue
		var pos: Vector2 = (n as Node2D).global_position
		if BotSimProbe.position_is_broken(pos):
			_file(BotSimProbe.SEV_ERROR, "spell_nan_position",
				"a projectile reached a non-finite position %s" % pos)
			n.queue_free()
		elif BotSimProbe.below_floor(pos.y, SimArena.FLOOR_Y, 24.0):
			_file(BotSimProbe.SEV_ERROR, "spell_below_floor",
				"a projectile resolved below the floor at %s (floor=%.1f)"
					% [pos, SimArena.FLOOR_Y])
			n.queue_free()
	for n: Node in get_nodes_in_group("telegraph"):
		if not n.has_method("danger_shape"):
			continue
		var shape: Dictionary = n.call("danger_shape")
		var c: Vector2 = shape.get("center", shape.get("from", Vector2.ZERO))
		if BotSimProbe.position_is_broken(c):
			_file(BotSimProbe.SEV_ERROR, "telegraph_nan_geometry",
				"a telegraph published a non-finite centre %s" % c)


## The fight is not progressing. Uses a trailing window of total HP across every
## fighter, so it fires for a genuine softlock AND for two bots that simply
## cannot reach one another — both worth a row, and not distinguishable here.
func _check_stalemate() -> void:
	var total: int = 0
	for rec: Dictionary in _fighters:
		total += int(rec["hp_last"])
	_hp_trail.append({"t": _elapsed, "total": total})
	while _hp_trail.size() > 2 and float(_hp_trail[0]["t"]) < _elapsed - STALEMATE_WINDOW:
		_hp_trail.pop_front()
	var span: float = _elapsed - float(_hp_trail[0]["t"])
	var movement: int = absi(int(_hp_trail[0]["total"]) - total)
	if BotSimProbe.stalemate(movement, span, STALEMATE_WINDOW):
		_file(BotSimProbe.SEV_WARN, "stalemate",
			"no HP moved in %.1fs (total stayed at %d)" % [span, total])
		_hp_trail.clear()   # one row per stall, not one per frame


# ================================================================== match end

## A match ends when one SIDE is wiped, when the game clock runs out, or when the
## real clock runs away from it. Sides come from the `side` field stamped at
## registration — never from comparing fighter records, because `==` on a
## Dictionary in GDScript is a VALUE comparison, so two structurally identical
## records would read as the same fighter.
func _end_reason() -> String:
	var wall_s: float = float(Time.get_ticks_msec() - _wall_start_ms) / 1000.0
	if wall_s > _duration * WALL_CLOCK_FACTOR:
		return "wall_timeout"
	if _elapsed >= _duration:
		return "timeout"
	var alive: Dictionary = {0: false, 1: false}
	for rec: Dictionary in _fighters:
		if _alive(rec) and int(rec["hp_last"]) > 0:
			alive[int(rec["side"])] = true
	if not bool(alive[0]) or not bool(alive[1]):
		return "kill"
	return ""


func _end_match(reason: String) -> void:
	_release_all_actions()
	var total_damage: int = 0
	for rec: Dictionary in _fighters:
		total_damage += int(rec["damage_taken"])

	# The headline check. Two fighters swinging for a whole match with nothing
	# landing in either direction is never anything but a defect — and it is the
	# exact signature of hero-vs-hero damage being routed by group rather than by
	# faction, which is the state of the code this harness was built against.
	if BotSimProbe.no_damage_exchanged(total_damage, _elapsed):
		_file(BotSimProbe.SEV_ERROR, "no_damage_exchanged",
			"nobody took a single point of damage in %.1fs of fighting" % _elapsed)
	if reason == "wall_timeout":
		_file(BotSimProbe.SEV_ERROR, "wall_timeout",
			"match exceeded %.0fs of real time — something is not advancing"
				% (_duration * WALL_CLOCK_FACTOR))

	var result: Dictionary = _judge(reason)
	var summary: Dictionary = {
		"index": _match_index, "pairing": _pairing_label(),
		"seed": _master_seed + _match_index * 7919,
		"mode": String(_queue[_match_index]["kind"]),
		"elapsed": snappedf(_elapsed, 0.01), "reason": reason,
		"total_damage": total_damage, "seam": _seam, "fighters": [],
		# DID ANYBODY PARRY. See the note on `SpellDeflect.deflect_count`: the whole
		# deflect stack has existed for a long time with nothing able to say whether a
		# bot ever reached it, and "no bad deflect was seen" is not evidence.
		"deflects": SpellDeflect.deflect_count,
		"deflects_by_group": SpellDeflect.deflects_by_group.duplicate(),
		# WHO WON, and by what. Without this the sim could tell you a fight was
		# ANOMALOUS but never whether it was BALANCED — and "is difficulty a real
		# dial, is any class a free win" is the question the maker actually asks.
		"winner": result.get("winner", ""),
		"loser": result.get("loser", ""),
		"outcome": result.get("outcome", "draw"),
	}
	for rec: Dictionary in _fighters:
		if bool(rec["is_hero"]) and bool(rec["driven"]):
			_check_spell_reachability(rec)
			# ⚠ `never_spent_mana` IS GONE, and deleting it was the fix rather than
			# retuning it. `Hero._cast_signature` no longer checks or deducts mana at
			# all (the mana gate was removed when kits went to three buttons), so mana
			# is now a bar that only ever regenerates — and a detector whose predicate
			# is permanently true fires on every match forever and buries the real
			# findings under itself. The QUESTION it was asking is still worth asking,
			# so it is asked honestly: did this bot commit any kit slot at all?
			var hist: Dictionary = rec["slot_presses"]
			if hist.is_empty() and _elapsed >= 8.0:
				_file(BotSimProbe.SEV_ERROR, "never_cast_kit",
					"%s committed no kit slot in %.1fs — the scorer never cleared threshold"
						% [rec["label"], _elapsed])
		summary["fighters"].append({
			"label": rec["label"], "class_id": rec["class_id"],
			"driven": rec["driven"], "hp": rec["hp_last"], "max_hp": rec["max_hp"],
			"damage_taken": rec["damage_taken"],
			"mp_spent": snappedf(float(rec["mp_spent"]), 0.1),
			"died_at": rec["died_at"],
			"sig_attempts": rec["sig_attempts"], "sig_fires": rec["sig_fires"],
			"verb_presses": rec["verb_presses"],
			# The kit-coverage answer: how many slots this bot actually committed,
			# and how often each. A histogram with one key is a bot fighting with
			# one spell; five keys is a bot playing its kit.
			"slot_presses": rec["slot_presses"],
		})
	_matches.append(summary)
	print("[sim] END   match=%d pairing=%s reason=%s elapsed=%.1fs damage=%d winner=%s (%s)"
		% [_match_index, _pairing_label(), reason, _elapsed, total_damage,
			summary["winner"] if String(summary["winner"]) != "" else "-",
			summary["outcome"]])

	for rec: Dictionary in _fighters:
		if bool(rec["is_hero"]) and rec["ctrl"] != null and _alive(rec):
			(rec["node"] as Node).set("controller", null)
	_fighters.clear()
	_arena.queue_free()
	_arena = null
	_cooldown_frames = 4


## A kit slot that was asked for with the gate open and never came out. This is
## the check that would have caught the unequippable beam family and the two ults
## that silently applied no status.
func _check_spell_reachability(rec: Dictionary) -> void:
	var attempts: Dictionary = rec["sig_attempts"]
	var fires: Dictionary = rec["sig_fires"]
	for id: String in attempts.keys():
		var n: int = int(attempts[id])
		var f: int = int(fires.get(id, 0))
		if BotSimProbe.never_fired(n, f):
			var blockers: Array = rec["sig_blockers"].get(id, [])
			var why: String = "no blocking state — the press reached a clear gate" \
				if blockers.is_empty() else "hero was %s" % ", ".join(blockers)
			_file(BotSimProbe.SEV_ERROR, "spell_never_fired",
				"%s: `%s` asked for %d times with cooldown at zero and mana covered, fired %d (%s)"
					% [rec["label"], id, n, f, why],
				{"class": rec["label"], "spell": id, "attempts": n, "fires": f,
					"blockers": blockers, "slot_map": _slot_map})
	# A hero whose kit produced NO attempts at all never even reached the ask —
	# an empty signature list, or a class whose loadout failed to build.
	# ⚠ CROSS-CHECKED AGAINST THE HONEST HISTOGRAM. `sig_attempts` is a GATED count
	# (it only records asks made with the slot off cooldown), so an empty one is
	# ambiguous: it means either "this hero has no kit" or "the harness's accounting
	# lost the race with the body". `slot_presses` is ungated — it is what the brain
	# committed, straight off the published intent — so a non-empty histogram proves
	# the kit was reachable and this row would be a false positive.
	if attempts.is_empty() and (rec["slot_presses"] as Dictionary).is_empty() \
			and _elapsed >= 8.0:
		_file(BotSimProbe.SEV_ERROR, "no_castable_signature",
			"%s never had a castable signature in %.1fs" % [rec["label"], _elapsed])


## WHO WON. Two ways to win, and the distinction is worth carrying:
##   "kill"   — somebody hit zero. Unambiguous.
##   "points" — the clock ran out and one fighter is meaningfully healthier. This is
##              the honest reading of a timeout: a bot that spent twenty seconds at
##              90% against one at 30% won that fight, and calling it a draw would
##              hide every balance signal in a run where nothing quite finishes.
##   "draw"   — the clock ran out inside the margin, or the match aborted on the
##              wall clock (in which case nothing measured is trustworthy anyway).
##
## `HP_MARGIN` is a fraction of max HP, not points, so it means the same thing to a
## 100 HP sim fighter and a 320 HP showcase one.
const HP_MARGIN: float = 0.12


func _judge(reason: String) -> Dictionary:
	if reason == "wall_timeout":
		return {"outcome": "draw"}
	var best: Dictionary = {}
	var worst: Dictionary = {}
	var best_frac: float = -1.0
	var worst_frac: float = 2.0
	for rec: Dictionary in _fighters:
		if not bool(rec["is_hero"]):
			continue
		var frac: float = float(rec["hp_last"]) / maxf(float(rec["max_hp"]), 1.0)
		if frac > best_frac:
			best_frac = frac
			best = rec
		if frac < worst_frac:
			worst_frac = frac
			worst = rec
	if best.is_empty() or worst.is_empty() or best == worst:
		return {"outcome": "draw"}
	if worst_frac <= 0.0:
		return {"winner": best["label"], "loser": worst["label"], "outcome": "kill"}
	if best_frac - worst_frac >= HP_MARGIN:
		return {"winner": best["label"], "loser": worst["label"], "outcome": "points"}
	return {"outcome": "draw"}


func _pairing_label() -> String:
	var spec: Dictionary = _queue[_match_index]
	if String(spec["kind"]) == "duel":
		return "%s_vs_%s" % [CLASS_NAMES[int(spec["a"])], CLASS_NAMES[int(spec["b"])]]
	return "%s_vs_ENEMIES" % CLASS_NAMES[int(spec["a"])]


## The nearest living fighter on the OTHER side. Side, not identity, for the same
## Dictionary-equality reason documented on `_end_reason`.
func _opponent_of(rec: Dictionary) -> Dictionary:
	var me: Node2D = rec["node"]
	var my_side: int = int(rec["side"])
	var best: Dictionary = {}
	var best_d: float = INF
	for other: Dictionary in _fighters:
		if int(other["side"]) == my_side or not _alive(other):
			continue
		if int(other["hp_last"]) <= 0:
			continue
		var d: float = me.global_position.distance_to((other["node"] as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


# ==================================================================== reporting

## Every finding is one row, carrying the pairing, the timestamp and the seed —
## enough to replay it with `--seed=<master> --classes=<a>,<b>`.
func _file(severity: String, kind: String, detail: String, context: Dictionary = {}) -> void:
	var pairing: String = _pairing_label() if _match_index >= 0 and _match_index < _queue.size() \
		else "setup"
	# ⚠ DEDUP, AND WHY IT IS NOT COSMETIC. Several detectors run per body per
	# frame, so ONE event that persists for a second is sixty identical rows. A
	# report that says "329 body_below_floor" when what happened was two fighters
	# sinking once each does not describe the game — it describes the sample rate,
	# and it buries every other finding under a single stuck body. Identical
	# kind+pairing inside FINDING_DEDUP_WINDOW increments a `repeats` count on the
	# row that is already there.
	var key: String = "%s|%s" % [kind, pairing]
	if _seen_findings.has(key):
		var prev: Dictionary = _seen_findings[key]
		if _elapsed - float(prev["at"]) <= FINDING_DEDUP_WINDOW:
			prev["at"] = _elapsed
			var row: Dictionary = prev["row"]
			row["repeats"] = int(row.get("repeats", 1)) + 1
			return
	var a: Dictionary = BotSimProbe.anomaly(kind, severity, pairing, _master_seed,
		_elapsed, detail, context)
	a["repeats"] = 1
	_anomalies.append(a)
	_seen_findings[key] = {"at": _elapsed, "row": a}
	print("[sim] %s %-24s %-28s %s" % [severity.to_upper(), kind, pairing, detail])


func _finish_run() -> void:
	_done = true
	_release_all_actions()
	_check_deflect_occurrence()
	var stamp: String = "run_%d_%s_%s" % [_master_seed, _mode, _slot_map]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var payload: Dictionary = {
		"seed": _master_seed, "mode": _mode, "duration": _duration,
		"slot_map": _slot_map, "difficulty": _difficulty,
		"seam": _seam, "brain": "BotBrain" if _brain != null else "builtin",
		"classes": _classes, "matches": _matches, "anomalies": _anomalies,
		"summary": BotSimProbe.summarize(_anomalies),
		"balance": _balance_report(),
		"godot": Engine.get_version_info().get("string", ""),
	}
	_write(_out_dir.path_join(stamp + ".json"), JSON.stringify(payload, "  "))
	var rows: Array[String] = [BotSimProbe.csv_header()]
	for a: Dictionary in _anomalies:
		rows.append(BotSimProbe.csv_row(a))
	_write(_out_dir.path_join(stamp + ".csv"), "\n".join(rows) + "\n")
	_print_summary(payload)
	quit(1 if (_strict and int(payload["summary"]["errors"]) > 0) else 0)


## A MINIMUM-OCCURRENCE CHECK, NOT AN ABSENCE-OF-BADNESS ONE.
##
## Every other defensive assertion in this project has been of the form "no bad
## deflect was seen", which is trivially satisfied by a deflect layer that never runs
## at all — and this codebase has already shipped exactly that twice (the whole reflex
## layer dead behind a null-returning helper; an entire ledge skyline deleted while
## the geometry suite stayed green). Bots hold guard for a measurable share of every
## match, so the question "does holding it ever actually turn a hit away" has a
## floor, and a run that comes in under it is a finding.
##
## Deliberately a floor of ONE PER RUN rather than a rate: the honest rate depends on
## how often a spell happens to arrive inside a 0.16 s window, which is a tuning
## question. Zero across a whole sweep is not a tuning question.
func _check_deflect_occurrence() -> void:
	var total: int = 0
	var matches_with: int = 0
	for m: Dictionary in _matches:
		var n: int = int(m.get("deflects", 0))
		total += n
		if n > 0:
			matches_with += 1
	if total <= 0:
		_file(BotSimProbe.SEV_ERROR, "no_deflect_in_run",
			"not one spell was deflected in %d matches — the guard is pressed but never turns anything away"
				% _matches.size())
		return
	print("[sim] deflects: %d across %d/%d matches" % [total, matches_with, _matches.size()])


## ============================================================== the balance report
## THE NUMBERS THE MAKER ASKED FOR, and the reason this harness stopped being only a
## crash-finder: a win-rate spread per class and a slot-usage distribution per class.
##
## An anomaly list tells you the game is BROKEN. Neither of these tells you that —
## they tell you whether it is any GOOD. A class that wins 90% of its matches is not
## an error and will never file one; a class whose bot spends 95% of its casts on
## slot 0 is not an error either, and is exactly the "leans on its damage line"
## complaint that has to be measured rather than eyeballed.
##
## SPREAD, not just the mean: the worst and best win rates in the roster and the gap
## between them is the one number that says whether difficulty is a dial or a coin.
func _balance_report() -> Dictionary:
	var per_class: Dictionary = {}   # class name -> {matches, wins, losses, draws, slots{}, verbs{}}
	for m: Dictionary in _matches:
		var winner: String = String(m.get("winner", ""))
		var loser: String = String(m.get("loser", ""))
		for f: Variant in m.get("fighters", []):
			if not (f is Dictionary):
				continue
			var fr: Dictionary = f
			if not bool(fr.get("driven", false)):
				continue
			var label: String = String(fr.get("label", "?"))
			if not per_class.has(label):
				per_class[label] = {"matches": 0, "wins": 0, "losses": 0, "draws": 0,
					"slots": {}, "verbs": {}, "damage_taken": 0}
			var row: Dictionary = per_class[label]
			row["matches"] = int(row["matches"]) + 1
			row["damage_taken"] = int(row["damage_taken"]) + int(fr.get("damage_taken", 0))
			if label == winner:
				row["wins"] = int(row["wins"]) + 1
			elif label == loser:
				row["losses"] = int(row["losses"]) + 1
			else:
				row["draws"] = int(row["draws"]) + 1
			_merge_counts(row["slots"], fr.get("slot_presses", {}))
			_merge_counts(row["verbs"], fr.get("verb_presses", {}))
	# Roster-wide spread. Classes with no decided match are excluded from the spread
	# (a 0/0 record is not a 0% win rate) but stay in the table, because "this class
	# never resolved a single fight" is itself the finding.
	var rates: Array[float] = []
	for label: String in per_class.keys():
		var row: Dictionary = per_class[label]
		var decided: int = int(row["wins"]) + int(row["losses"])
		row["decided"] = decided
		row["win_rate"] = -1.0 if decided == 0 else snappedf(float(row["wins"]) / float(decided), 0.001)
		# The kit-coverage number, in one figure: what fraction of this bot's casts
		# went to its single most-used slot. 1.0 = it fought with one spell.
		row["top_slot_share"] = snappedf(_top_share(row["slots"]), 0.001)
		row["slots_used"] = (row["slots"] as Dictionary).size()
		if decided > 0:
			rates.append(float(row["win_rate"]))
	rates.sort()
	var spread: Dictionary = {"classes_rated": rates.size()}
	if not rates.is_empty():
		spread["min"] = rates[0]
		spread["max"] = rates[rates.size() - 1]
		spread["gap"] = snappedf(rates[rates.size() - 1] - rates[0], 0.001)
	return {"per_class": per_class, "spread": spread,
		"draws": _count_outcome("draw"), "kills": _count_outcome("kill"),
		"points": _count_outcome("points")}


func _count_outcome(kind: String) -> int:
	var n: int = 0
	for m: Dictionary in _matches:
		if String(m.get("outcome", "")) == kind:
			n += 1
	return n


func _merge_counts(into: Dictionary, from: Variant) -> void:
	if not (from is Dictionary):
		return
	for k: Variant in (from as Dictionary).keys():
		var key: String = str(k)
		into[key] = int(into.get(key, 0)) + int((from as Dictionary)[k])


## Fraction of all presses that went to the single most-used entry. 0.0 for an empty
## histogram — a bot that never cast has no concentration, and reporting 1.0 would
## make "never used its kit" look identical to "used one spell".
func _top_share(hist: Dictionary) -> float:
	var total: int = 0
	var top: int = 0
	for k: Variant in hist.keys():
		var n: int = int(hist[k])
		total += n
		top = maxi(top, n)
	return 0.0 if total <= 0 else float(top) / float(total)


func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[sim] could not write ", path)
		return
	f.store_string(text)
	f.close()
	print("[sim] wrote ", ProjectSettings.globalize_path(path))


func _print_summary(payload: Dictionary) -> void:
	var s: Dictionary = payload["summary"]
	print("\n=========================== BOT SIM SUMMARY ===========================")
	print("seed=%d  mode=%s  matches=%d  seam=%s  brain=%s"
		% [_master_seed, _mode, _matches.size(), _seam, payload["brain"]])
	print("anomalies: %d total  (%d error, %d warn)"
		% [s["total"], s["errors"], s["warns"]])
	var kinds: Dictionary = s["by_kind"]
	var names: Array = kinds.keys()
	names.sort()
	for k: String in names:
		print("   %-26s %d" % [k, kinds[k]])
	_print_balance(payload.get("balance", {}))
	print("REPLAY ANY FINDING WITH:  --seed=%d --mode=%s --dur=%.0f" % [_master_seed, _mode, _duration])
	print("=======================================================================")


## The balance table. Printed rather than only written, because a number in a JSON
## file nobody opens is a number nobody has.
##
## Columns:
##   W-L-D      decided wins, decided losses, draws
##   win%       wins / decided. "-" when nothing this class fought was decided.
##   slots      how many DISTINCT kit slots this bot ever committed (out of 3)
##   top-slot   share of its casts that went to its single favourite slot. This is
##              the "leans on its damage line" measurement: 1.00 means one spell.
##   verbs      which of the eight non-kit buttons it ever pressed. A verb missing
##              from every row is a verb the brain cannot reach.
func _print_balance(balance: Dictionary) -> void:
	var per_class: Dictionary = balance.get("per_class", {})
	if per_class.is_empty():
		return
	print("\n--- BALANCE -----------------------------------------------------------")
	print("outcomes: %d kill / %d points / %d draw"
		% [balance.get("kills", 0), balance.get("points", 0), balance.get("draws", 0)])
	print("%-13s %-9s %6s %6s %9s   %s" % ["class", "W-L-D", "win%", "slots", "top-slot", "verbs"])
	var names: Array = per_class.keys()
	names.sort()
	for label: String in names:
		var row: Dictionary = per_class[label]
		var rate: float = float(row.get("win_rate", -1.0))
		print("%-13s %-9s %6s %6s %9.2f   %s" % [
			label,
			"%d-%d-%d" % [row.get("wins", 0), row.get("losses", 0), row.get("draws", 0)],
			"-" if rate < 0.0 else "%.0f%%" % (rate * 100.0),
			"%d/3" % int(row.get("slots_used", 0)),
			float(row.get("top_slot_share", 0.0)),
			_verb_line(row.get("verbs", {})),
		])
	var spread: Dictionary = balance.get("spread", {})
	if spread.has("gap"):
		print("win-rate spread: %.0f%% .. %.0f%%  (gap %.0f pts over %d rated classes)"
			% [float(spread["min"]) * 100.0, float(spread["max"]) * 100.0,
				float(spread["gap"]) * 100.0, int(spread["classes_rated"])])


## The eight non-kit verbs as a compact presence line. Short names so the table
## stays one line per class; a lower-case letter means the brain never pressed it.
const VERB_KEYS: Array[String] = [
	"fire", "swing", "dash", "guard", "jump",
	"ability_blast", "ability_blink", "ability_nova",
]
const VERB_TAGS: Array[String] = ["fire", "swing", "dash", "guard", "jump", "Q", "R", "T"]


func _verb_line(verbs: Variant) -> String:
	if not (verbs is Dictionary):
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for i: int in VERB_KEYS.size():
		var n: int = int((verbs as Dictionary).get(VERB_KEYS[i], 0))
		parts.append(VERB_TAGS[i] if n > 0 else "·")
	return " ".join(parts)
