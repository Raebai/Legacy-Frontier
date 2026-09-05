extends Node
## Slice 2 run-loop spine. Owns the HUB <-> RUN mode, the live-run accumulators,
## the floor plan (pure math), and the last-run outcome record. Autoload
## "GameState".
##
## Every combat-side caller reaches this through a guarded /root/GameState lookup
## so Arena.tscn still runs standalone (F6) as the pure feel sandbox with no
## GameState-driven floor structure. When a real run IS active, the same arena
## runs floor-by-floor.
##
## The record builders and the floor math are STATIC + PURE so they test
## headlessly with no scene and no change_scene.

signal run_started
signal run_ended(outcome: Dictionary)        # combat resolved (victory or death)
signal floor_advanced(floor: int)            # cleared a floor, entering the next
## XP landed. `kind` is "kill" / "guardian" / "clear" — the level-up spectacle and
## the floating number both read it, and it is what lets a guardian pay louder than
## a trash mob without either of them knowing the other exists.
signal xp_gained(amount: int, kind: String, where: Vector2)
## A LEVEL. The one progression beat the player is shown, and the reason
## `LevelUpBurst` exists. Emitted AFTER the new level is banked, so a listener that
## asks `level()` in the handler gets the level it is celebrating.
signal leveled_up(new_level: int)
## A guardian banked a CLASS PICK. The town's altar is what spends it.
signal class_choice_earned(floor: int)
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
## straight into `scenes/Main.tscn`, the parked v0.0 town. There was no victory
## screen anywhere in the tower, and no route back to the title from anything but
## the credits. Under the 2026-08-01 death rule a solo death ends the run
## immediately, so a first-time player reached that town **on their first death**,
## having seen nothing of the game.
##
## How it is resolved:
##   * A run now ends on `SUMMARY_SCENE` — a ceremony that SHOWS the run (floor,
##     kills, guardians, rank, falls, team damage) and then lands the player on the
##     Lobby, which is the boot scene and works on a phone.
##   * THE PERSISTENT CLIMB IS UNTOUCHED. `_floor`, `_highest_floor`, `_falls`,
##     `tower_conquered` and `user://climber.json` are written exactly as before,
##     BEFORE the ceremony; nothing about the climb needed the hub to happen.
##   * The hub survives as an OPT-IN detour, `visit_hub()`, offered on the summary
##     card and never on the critical path.
const HUB_SCENE: String = "res://scenes/Main.tscn"
const SUMMARY_SCENE: String = "res://scenes/ui/RunSummary.tscn"
const TITLE_SCENE: String = "res://scenes/ui/Lobby.tscn"
const ARENA_SCENE: String = "res://scenes/combat/Arena.tscn"

## A run is TOTAL_FLOORS floors; the last one is the guardian floor.
##
## ⚠ 5 -> 10 ON 2026-08-04, AND THAT OVERTURNS A PRIOR RULING. The recorded call was
## "5 floors, seeded-randomised rather than the spec's 15 + procedural". Checkpoints
## need a tower taller than one band, so the maker was shown the conflict directly
## and chose to build the checkpoint system while keeping the tower short — nothing
## is playtested yet, and six-fold content growth before the combat feels good is
## the risky move.
##
## THIS AND `DeathRules.CHECKPOINT_BAND` ARE THE ONLY TWO NUMBERS between here and
## the 30-floor / 10-band shape. See
## docs/superpowers/specs/2026-08-04-tower-shape-and-feel-design.md §1.4.
const TOTAL_FLOORS: int = 10

## Climber save schema version (bump + migrate if the shape changes).
##
## ⚠ 1 -> 2 ON 2026-08-04 adds the levelling record: `xp`, `unlocked_nodes`,
## `unlocked_classes`. THE MIGRATION IS A LOSSLESS WRAP and needs no branch — every
## field is read through `.get(key, default)`, so a v1 save simply arrives with no
## XP, no tree and the six starting classes, which is exactly right for a climber
## who has never levelled. Same principle as D-044.
##
## ⚠ AND IT DELIBERATELY DOES NOT BRANCH ON THE VERSION NUMBER. The M9 bug was a
## version check that misread `2` as `2.0` (JSON gives floats), decided a valid save
## needed migrating, and destroyed it. A parser that never asks the version cannot
## make that mistake. The number is stamped for humans and for a future shape change
## that genuinely cannot be defaulted.
const CLIMBER_SAVE_VERSION: int = 2
## Where the persistent climber lives (highest/current floor, falls, conquered, rank).
const CLIMBER_PATH: String = "user://climber.json"

## ══ THE SCORE ═════════════════════════════════════════════════════════════════
## Maker, 2026-09-04: *"revamp the tower so thats its infinite and you are scored on
## like how high you get ... and the game is just who can get highest in the tower"*.
## Design note: docs/superpowers/specs/2026-09-04-infinite-tower-and-score.md
##
## ⚠ `preload`, NOT a `class_name`. It hands back the SCRIPT OBJECT, so every entry
## point on that file is `static` — and it needs no import step, which is the only
## reliable way to add a script to this project without the global class cache being
## the thing that decides whether the build parses.
const ClimbScore := preload("res://scripts/tower/ClimbScore.gd")

## The local board. A SEPARATE FILE from climber.json, deliberately: the climber is
## one record rewritten on every floor transition, and the board is a list that grows.
## Merging them makes the per-floor write bigger every run and lets a corrupt board
## take the climber down with it.
const SCORES_PATH: String = "user://scores.json"

## ══ HOW HIGH THE CLIMB MAY GO ═════════════════════════════════════════════════
## "Infinite", with a number, and the number is the point.
##
## An unbounded floor counter is a place for a hand-edited save, an overflowing
## format string or a runaway loop to live, and every consumer that prints "Floor %d"
## wants a bound it can trust. At roughly ninety seconds a floor, 9999 is two hundred
## and fifty hours in one unbroken sitting — and the difficulty curve reaches its
## terminal state around floor 41 (see `ascent_floor_def`), so the last ~9950 floors
## are the same floor with a different number on it anyway. This is a guard rail, not
## a design statement.
const MAX_CLIMB_FLOOR: int = 9999

## Which hero class the next/current run uses. Read by Hero._ready(). Set from
## the hub or the debug switch. 0..7 (see Hero.HeroClass / CLASS_NAMES).
var selected_class: int = 0

## SAME-SCREEN CO-OP: what each LOCAL player after the first plays as, keyed by the
## pad `device` id that joined. -1 or absent means "whatever player one picked".
##
## ⚠ A SEPARATE STORE, NOT `selected_class`. That one is a single global "the class
## you last confirmed" and is written by the hub altar, the in-run `switch_class`, the
## versus arena and four Lobby paths (`ClassSelect.gd:155`, `Hero.gd:3021`,
## `Lobby.gd:541/555/585/673`) - so parking player two's choice in it would have player
## two's pick silently become player one's the next time either of them switched.
##
## ⚠ KEYED BY DEVICE, MIRRORING `Net.peer_class`. The networked path already solved
## this exact problem with an id->class dictionary read through `class_of(peer)` and
## applied by setting `net_class` on the body BEFORE `_ready` resolves it
## (`Arena.gd:1219`). Local co-op uses the same shape and the same consumption point,
## so there is one way this works rather than two.
var local_class: Dictionary = {}


## The class a local player on `device` should spawn as, or -1 for "same as player one".
func local_class_of(device: int) -> int:
	return int(local_class.get(device, -1))


func set_local_class(device: int, cls: int) -> void:
	local_class[device] = cls

## Player gear loadout override, set from the hub Armory (Loadout UI). Slot -> gear
## kind; "" = keep the class default. Applied by Hero._ready after configure_class,
## so the chosen weapon/head/body (and their GearAbilities) shape the run hero.
var loadout: Dictionary = {"weapon": "", "head": "", "body": "", "legs": ""}

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

## The Tier 2 / Tier 3 spells equipped in the hub, `class_id -> {slot: spell_id}`.
## Written by `SpellLibrary.persist_to_state`, read by `hydrate_from_state`. Separate
## from `spell_roles` because they answer different questions: that one picks WHICH
## FOUR of a class's five authored roles it carries, this one puts a spell no class
## authors into a numbered slot. See the grimoire block in `SpellLibrary`.
var spell_equipped: Dictionary = {}

## Body colourway index the player chose in the Outfitter. -1 = untouched, use the
## class default. Read by `Hero._configure_class` AT SPAWN — before this existed the
## pick was replayed onto the hero the first time the pause menu opened, so you
## played the whole first floor as the default palette.
var colourway: int = -1

## Player camera-zoom preference (combat). Lower = wider view. Read by
## CombatCamera as its resting zoom; adjustable live from the pause Settings.
## Default pulled back from the old tight 2.2 so more of the fight is visible.
var camera_zoom: float = 1.6

## ⚠ HOW A PVP FIGHT IS WON — the maker's choice, exposed rather than assumed.
##
## Maker: "the knockback stuff is heavy but I like health instead for the pvp (or in
## settings give the users the options to choose lives vs percentages)".
##
## HEALTH (0, the default): hp drains and zero is a loss. Reads like a fighting game
## and does not depend on the knockback curve at all.
## STOCKS (1): the Smash model — a hit accrues `damage_pct` instead of draining hp,
## knockback scales with that %, and the only elimination is a ring-out. Both models
## are already fully built in `VersusArena`; this only chooses between them.
##
## The sandbox used to force STOCKS unconditionally. It is a preference, not a
## property of the arena, so it lives here where the settings panel can reach it.
enum PvpRules { HEALTH, STOCKS }
var pvp_rules: int = PvpRules.HEALTH

## ⚠ WHAT KIND OF VISIT THIS IS — set by the title screen BEFORE the Antechamber
## loads, and the reason there is one prep room instead of two.
##
## Maker: "there should be an Enter the tower button and a multiplayer Button…
## once you enter the tower you go to the lobby area where you can resume your
## journey". Both doors land in the SAME room; this is what the room reads to know
## whether to stand the Party Stone up.
##
## Deliberately NOT `Net.is_active()`: you arrive in the room BEFORE a friend has
## connected, so asking the network would say "solo" during the exact window the
## room most needs to say "waiting". This records the INTENT of the press.
enum SessionKind { SOLO, LOCAL, ONLINE }
var session_kind: int = SessionKind.SOLO

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

## ══ THE LEVELLING RECORD ══════════════════════════════════════════════════════
## LIFETIME XP, and the ONLY number stored. Level is derived from it
## (`Progression.level_for_xp`), and Growth is derived from level + class. Nothing
## downstream is persisted, so a retune of the curve updates every existing save
## for free and no two stored numbers can ever disagree about the same climber.
##
## ⚠ NEVER RESET. Maker's ruling, 2026-08-04: levelling persists across climbs,
## deaths and tower conquests — "the one thing that is yours regardless of how the
## run went". `Rank` is the per-climb channel and stays that way.
var _xp: int = 0

## Spell-tree nodes bought, by id. Skill points SPENT are derived by summing these
## nodes' costs; points EARNED are `level - 1`. Neither is stored, for the same
## reason Growth is not: a stored balance can drift from the thing it is a balance of.
var unlocked_nodes: Array[String] = []

## Guardian picks banked and not yet spent. The altar in the town turns each of
## these into one locked class of the player's choosing.
var pending_class_choices: int = 0

## Which guardian floors have already paid out a pick. A conquered tower re-climbs
## from floor 1, so without this the floor-5 guardian would hand out a class on
## every lap and all three would be four laps of the easiest boss in the game.
var _earned_choice_floors: Array[int] = []

## Locked classes earned (Stormcaller / Warlock / Swordsaint). The six starters are
## not listed — `Progression.is_class_unlocked` knows them, so this array holds only
## what was actually won and a fresh save is legitimately empty.
var unlocked_classes: Array[int] = []

## ⚠ THE PARTY'S POWER LEVEL, FROZEN FOR THE RUN. -1 = solo / not resolved, i.e.
## use your own level. Set once when the party enters the tower, alongside
## `party_start_floor`, and never recomputed mid-run — recomputing live means a
## friend joining mid-fight silently drops your max hp out from under your current
## hp. See `Progression.party_growth_level` for why the cap exists at all.
var _party_level: int = -1

## THE FLOOR IS THE UNIT OF XP, AND THIS IS WHAT MAKES THAT TRUE IN CODE.
##
## A floor's kill share is a PURSE, drawn down one body at a time and never
## refilled. Without it, anything that spawns extra bodies mid-floor — a SUMMONER's
## minions, a boss's adds, the Warlock's own thralls — would mint XP the floor was
## never worth, and "stand on floor 1 next to a summoner" would be the best farm in
## the game. With it, that play yields exactly nothing extra.
var _floor_kill_purse: int = 0

var mode: int = Mode.HUB
var last_run: Dictionary = {}            # {} until the first run ends

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

## THE HIGHEST FLOOR *THIS RUN* TOUCHED — the headline score input.
##
## ⚠ NOT the same number as `_highest_floor`, and the difference is the whole reason
## both exist. `_highest_floor` is the climber's lifetime best and is monotonic across
## every run forever; this is one run's peak and resets on every entry. A board row
## says what a RUN did, so it has to be this one — otherwise every row after your best
## run would silently claim your best run's height.
var _run_peak_floor: int = 1

## When the current run started, in engine milliseconds. The score's tiebreak.
##
## ⚠ `Time.get_ticks_msec()` is ~20x wrong inside `--write-movie` (a documented trap in
## docs/NEXT-SESSION.md), which is a clip-render mode nobody scores a run in. The
## ORDERING rule that consumes this lives in `ClimbScore.is_better` and is tested
## against explicit numbers, so the rule is never dependent on the clock being right.
var _run_started_ms: int = 0

## THE LOCAL BOARD, newest-best-first. Loaded at `_ready`, written at `end_run`.
## The personal best is `ClimbScore.best(score_history)` — DERIVED, never stored
## beside the list it is the best of.
var score_history: Array = []

## Ascent floors already synthesized this climb, keyed by depth.
##
## ⚠ THIS CACHE IS CORRECTNESS, NOT SPEED. `floor_def_for` is called several times per
## floor — `Arena` builds the room from it, `Encounter` runs the fight from it, the
## XP purse counts bodies from it — and each caller MUST be handed the same floor. It
## is a pure function of (id, depth, seed) so a re-derive would agree anyway; caching
## makes that true by construction rather than by argument, and stops a future
## non-pure line from silently building a room that does not match its fight.
var _ascent_cache: Dictionary = {}


# ---------------------------------------------------------------- transitions
const TOWER_PATH: String = "res://data/towers/ashspire.tres"


func _ready() -> void:
	_load_climber()
	_load_scores()


## ══ START THE CLIMB OVER ═══════════════════════════════════════════════════════
## Maker: *"give me an option to reset the tower by speaking to one of the NPCs outside
## of it"*.
##
## ⚠ THE CLIMB IS DELIBERATELY PERSISTENT AND THIS IS THE ONLY DOOR OUT OF THAT.
## `enter_run` resumes from the saved floor and its own comment says "NEVER a blanket
## reset to 1" — that is the whole Tower-of-God shape of the game, and a death costing
## floors only means something if the floors are otherwise kept. So the reset is not a
## setting, not a menu item and not a keypress: it is a thing you walk over to a person
## and ask for, which is the friction the decision deserves.
##
## WHAT IT CLEARS: the floor you resume on, and the conquered flag.
## WHAT IT KEEPS, AND WHY: `_highest_floor` and `_falls` are the town's MEMORY of you —
## the Doorkeeper reads them back ("that is 4 falls now"), and a reset that wiped them
## would erase the only record the town keeps. You are starting the climb again, not
## becoming a stranger. Rank/level and the loadout are likewise untouched: this resets
## the TOWER, which is what was asked for, not the character.
func reset_climb() -> void:
	_floor = 1
	tower_conquered = false
	# Rebuilt on the next `enter_run`, so a fresh climb is a fresh tower rather than
	# the same rooms in the same order.
	active_tower = null
	# ...and the ascent goes with it. The cache is keyed by depth alone, so a stale
	# entry would hand the NEW climb the OLD climb's floor 37 — the one bug a
	# depth-keyed cache can have, and the reset is where it would have appeared.
	_ascent_cache.clear()
	_save_climber()


func enter_run() -> void:
	ringout_mode = false                  # a tower run is HP-death, never ring-out
	if active_tower == null:
		active_tower = _load_or_build_tower()
	# Persistent climb: resume from the saved floor. NEVER a blanket reset to 1.
	#
	# ⚠ ON AN ENDLESS TOWER, CONQUEST NO LONGER RESETS YOU. Clearing the authored
	# summit used to end the run and send the next one back to floor 1; under the
	# endless climb the summit is a MILESTONE you climb through, so `tower_conquered`
	# is a badge the card and the hub NPCs read, not a reset trigger. `reset_climb()`
	# — walking over to a person and asking — remains the one door back to floor 1,
	# which is the friction that decision was given on purpose.
	if tower_conquered and not is_endless():
		_floor = 1
		tower_conquered = false
	_floor = clampi(_floor, 1, climb_ceiling())
	_highest_floor = maxi(_highest_floor, _floor)
	_run_peak_floor = _floor
	_run_started_ms = Time.get_ticks_msec()
	_restore_rank_power()
	_kills = 0
	_boss_killed = false
	_elements_used = {}
	_friendly_damage = 0
	_run_active = true
	mode = Mode.RUN
	clear_party_level()      # a solo run plays at your own level, always
	_open_floor_purse()
	run_started.emit()
	_change_scene(ARENA_SCENE)


## Prefer a maker-authored tower .tres if one exists; otherwise build the default
## Ashen Tower in code. Same data shapes either way.
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
##
## ⚠ AND THE ENDLESS FLAG IS SET *HERE*, not in `build_default_tower()`, for exactly
## the reason above one level up. Eight tools and suites call the builder directly and
## assert against the authored ten — `slice2_test_runloop` pins `floors.size() ==
## TOTAL_FLOORS`, `slice_test_climb` pins that clearing the last floor CONQUERS and
## emits no `floor_advanced`. Those describe the authored spine and they are still
## true of it. Endlessness is a property of the tower as PLAYED, so it is applied on
## the way to being played, next to the generator that is applied for the same reason.
func _load_or_build_tower() -> TowerDef:
	_ascent_cache.clear()          # a new tower means a new ascent
	if ResourceLoader.exists(TOWER_PATH):
		var t: Resource = load(TOWER_PATH)
		if t is TowerDef:
			return _make_endless(FloorGen.apply(stamp_depths(t as TowerDef)))
	return _make_endless(FloorGen.apply(build_default_tower()))


## Mark a tower as one the climb does not fall off the end of. Separated so the one
## line that turns the game infinite is greppable, and so a future "this tower really
## does end" (a scripted campaign, a tutorial tower) has an obvious place to say so.
func _make_endless(t: TowerDef) -> TowerDef:
	if t != null:
		t.endless = true
	return t


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
##
## ⚠ THIS STILL MEANS "HOW TALL IS THE AUTHORED SPINE", AND IT WAS NOT REDEFINED.
## The tower is endless now, so there is a real temptation to make this answer
## "infinity" or "where you are". It answers neither. It is read by the checkpoint
## clamp, the summary card and the floor banner, and silently changing what it means
## is precisely the `TOTAL_FLOORS`-vs-`total_floors()` bug this repo already recorded
## once (every climb test passed while the two disagreed). The new questions got new
## methods instead: `is_endless`, `climb_ceiling`, `has_next_floor`, `floor_label`.
func total_floors() -> int:
	if active_tower != null:
		return active_tower.floors.size()
	return TOTAL_FLOORS


## Does the climb continue past the authored spine? See `TowerDef.endless`.
func is_endless() -> bool:
	return active_tower != null and active_tower.endless


## The highest floor the climb may reach. The authored spine's height on a finite
## tower; the guard-rail constant on an endless one (see MAX_CLIMB_FLOOR).
func climb_ceiling() -> int:
	return MAX_CLIMB_FLOOR if is_endless() else total_floors()


## Is there a floor above the one you are on? The question `Arena` is really asking
## when it decides whether to draw the walk-home portal beside the climb portal, and
## the question `advance_floor` asks before it ends the run in victory.
##
## Its own method because `current_floor() < total_floors()` — which is what the two
## call sites used to spell — silently became FALSE forever at floor 10 the moment the
## tower stopped ending there.
func has_next_floor() -> bool:
	return _floor < climb_ceiling()


## "Floor 7 / 10" on the authored spine, "Floor 34" once you are past it.
##
## One implementation, because the banner, the run card and the board all want this
## string and three of them inventing it independently is how a game ends up showing
## "Floor 34 / 10" on one screen and "Floor 34" on another.
func floor_label(floor: int = -1) -> String:
	var f: int = _floor if floor < 0 else floor
	if is_endless() and f > total_floors():
		return "Floor %d" % f
	return "Floor %d / %d" % [f, total_floors()]


## Called by the arena when a floor is cleared and the player takes the exit.
## Advances the floor counter, or ends the run in victory past the last floor.
func advance_floor() -> void:
	if _is_net_client():
		return                            # co-op: only the host advances the party
	if not _run_active:
		return
	# THE CLEAR SHARE, paid for taking the exit — banked BEFORE the floor number
	# moves, or the last floor of the tower would pay at the price of a floor that
	# does not exist.
	grant_xp(Progression.clear_xp(_floor), "clear")
	if _floor >= total_floors():
		# ══ THE SUMMIT OF THE AUTHORED SPINE ══════════════════════════════════════
		# It is still a MILESTONE — `tower_conquered` is what the summary card, the hub
		# NPCs and the class-choice hook read, and clearing floor 10 has always been
		# the moment they are talking about. What it stopped being is an ENDING.
		_boss_killed = true               # cleared the guardian floor
		tower_conquered = true
		_highest_floor = maxi(_highest_floor, total_floors())
		if not is_endless():
			# A finite tower (the F6 sandbox, a scripted tower, and every suite that
			# drives `build_default_tower()` directly) behaves exactly as before: the
			# run ends here in victory and emits no `floor_advanced`.
			_save_climber()
			end_run(false)
			return
		# ...and on an endless one, the ascent begins. Falling through is the whole
		# implementation: the floor moves, the purse opens, the save is written and
		# `floor_advanced` fires, which is what rebuilds the Arena on every peer.
	if _floor >= climb_ceiling():
		# The guard rail, reached only by a hand-edited save. Ending the run is the
		# right answer — there is no floor above this one to advance to, and looping
		# forever on the same number is worse than a victory card.
		_save_climber()
		end_run(false)
		return
	_floor += 1
	_highest_floor = maxi(_highest_floor, _floor)
	_run_peak_floor = maxi(_run_peak_floor, _floor)
	_open_floor_purse()                   # a new floor, a new purse
	_save_climber()
	floor_advanced.emit(_floor)


## Co-op: enter the tower at `floor` WITHOUT a scene change (the Net RPC changes
## scene on all peers) and WITHOUT persistence (the host owns climber.json). Sets
## the shared run state so every peer's Arena runs in run-mode + builds the same
## floor (the default Ashen Tower is code-built identically on both sides).
## WHERE A PARTY STARTS, given every member's own saved floor.
##
## The lowest CHECKPOINT in the party — not the lowest floor, and not the host's.
## That distinction is the entire co-op progression model:
##
##   * Two climbers in the same band already share a checkpoint, so the common case
##     needs no negotiation at all and nobody is moved.
##   * A climber further up re-treads only the bands they are ahead by — and a floor
##     scaled for two is not the floor they cleared alone.
##   * Nobody can be pulled into content past their own band, so a friend cannot
##     boost you up the tower.
##   * It is self-levelling: once the trailing player catches up, the party climbs in
##     lockstep from then on.
##
## Pure + static so it tests headlessly and so the rule has one implementation.
## An empty party answers 1 rather than erroring — a lobby with nobody in it still
## has to name a floor.
static func party_start_floor(floors: Array) -> int:
	var best: int = -1
	for f in floors:
		var cp: int = DeathRules.checkpoint_for(int(f))
		if best < 0 or cp < best:
			best = cp
	return maxi(best, 1)


func enter_coop_run(floor: int) -> void:
	ringout_mode = false                  # co-op is a tower run: HP-death, not ring-out
	if active_tower == null:
		active_tower = _load_or_build_tower()
	# ⚠ `climb_ceiling()`, NOT `total_floors()`. A party climbing an endless tower can
	# legitimately be handed floor 37; clamping that to the authored ten would silently
	# drop the whole party back to floor 10 the moment they crossed the summit.
	_floor = clampi(floor, 1, climb_ceiling())
	_highest_floor = maxi(_highest_floor, _floor)
	_run_peak_floor = _floor
	_run_started_ms = Time.get_ticks_msec()
	_kills = 0
	_boss_killed = false
	_elements_used = {}
	_friendly_damage = 0
	_run_active = true
	mode = Mode.RUN
	_open_floor_purse()
	run_started.emit()


## Co-op CLIENT mirror: the host drives the spine, so a client applies the host's
## floor directly (bypassing the _is_net_client guard on advance) and re-emits the
## signal that rebuilds its Arena. Host-side / SP never call this — it's the client
## receiver. The old `is_fall` parameter went with the fall rule (see the note on
## the deleted `fell` signal): a floor only ever moves UP now.
func net_set_floor(floor: int) -> void:
	if active_tower == null:
		active_tower = _load_or_build_tower()
	# `climb_ceiling()` for the same reason `enter_coop_run` uses it: the host may be
	# replicating an ascent floor, and clamping to the spine would desync the party's
	# floor number from the fight the host is actually running.
	_floor = clampi(floor, 1, climb_ceiling())
	_highest_floor = maxi(_highest_floor, _floor)
	_run_peak_floor = maxi(_run_peak_floor, _floor)
	_run_active = true
	mode = Mode.RUN
	# The client opens its OWN purse for the new floor. It never draws from it (kills
	# resolve host-side and arrive as relayed grants), but a client that later
	# becomes the authority for anything must not be sitting on an empty one.
	_open_floor_purse()
	floor_advanced.emit(_floor)


## In co-op only the HOST drives the run spine (advance/fall/return + persistence);
## clients follow the host's replicated floor. True on a client in a live session.
## The `is_inside_tree()` guard is the same one `_is_net_host` carries, and for the
## same reason: an absolute `get_node()` from a node that is not in the tree is an
## ERROR in Godot, not a null, and the headless suites drive a bare
## `GameState.new()` on purpose. This one predates the levelling work — it was
## printing four red lines into every climb-suite run, which is exactly the kind of
## standing noise that trains people to ignore the error stream.
func _is_net_client() -> bool:
	if not is_inside_tree():
		return false
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
	# ⚠ `climb_ceiling()`, NOT `total_floors()`. `resume_floor_after_game_over` CLAMPS
	# its first argument to its second before taking the checkpoint band, so passing
	# the authored ten would turn "you fell on floor 37" into "you fell on floor 10"
	# and resume you at 6 — deleting twenty-seven floors on one death. The band
	# arithmetic itself (`DeathRules.checkpoint_for`) extends to any depth unchanged:
	# floor 37 -> 36, which is the guardian floor's own band, which is the alignment
	# the ascent's five-floor type rhythm was chosen for.
	_floor = DeathRules.resume_floor_after_game_over(_floor, climb_ceiling())
	_save_climber()
	end_run(true, died_on)


## Deliberate hub return from a cleared floor. Banks the cleared floor (resume
## continues the climb, no refight), then bounces to the hub with a "walked out
## alive" outcome the NPCs ingest.
func return_to_hub() -> void:
	if not _run_active:
		return
	# Walking out of a floor you CLEARED pays the same clear share taking the exit
	# does — the two are the same event with different destinations, and paying only
	# one of them would make "go home" quietly cost you a fifth of the floor.
	grant_xp(Progression.clear_xp(_floor), "clear")
	# `has_next_floor()`, not `_floor < total_floors()`: on an endless tower there is
	# always a floor above, and the old spelling would have stopped banking the cleared
	# floor from the summit onward — walking home from floor 34 would have put you back
	# on floor 34 to refight it.
	if has_next_floor():
		_floor += 1
		_highest_floor = maxi(_highest_floor, _floor)
		_run_peak_floor = maxi(_run_peak_floor, _floor)
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
	# ══ THE SCORE, BANKED ═════════════════════════════════════════════════════════
	# Recorded BEFORE the outcome is frozen, so the card can be handed this run's
	# place on the board rather than having to go and look it up. Every route out of a
	# run passes through here — death, walking home, abandoning, conquering — which is
	# why this is the one place it is done: peak floor is peak floor however the run
	# ended, and a route that scored and a route that did not would be a board with a
	# hole in it that nobody could see.
	var died_floor: int = (_floor if floor_override < 0 else floor_override)
	_run_peak_floor = maxi(_run_peak_floor, died_floor)
	var rec: Dictionary = ClimbScore.make_record(
		_run_peak_floor, _elapsed_ms(), selected_class, died, _kills,
		int(Time.get_unix_time_from_system()), _is_coop_session()
	)
	var place: int = ClimbScore.rank_of(score_history, rec)
	var record: bool = ClimbScore.is_record(score_history, rec)
	var prev_best: int = ClimbScore.best_floor(score_history)
	score_history = ClimbScore.insert(score_history, rec)
	_save_scores()
	last_run = build_outcome(
		died_floor,
		_kills, _boss_killed, died,
		_elements_used.keys(), _rank_tier(), _rank_title(), _falls,
		_friendly_damage, _highest_floor, total_floors(),
		_run_peak_floor, _elapsed_ms(), place, record, maxi(prev_best, 0)
	)
	mode = Mode.HUB
	run_ended.emit(last_run)
	# THE CEREMONY, NOT THE PARKED TOWN. See the SUMMARY_SCENE block at the top for
	# why this line moved and what it does not cost. Falls back to the title screen
	# rather than the hub if the card is ever missing from a build — a player who
	# finished a run must always end up somewhere they can start another one.
	_change_scene(SUMMARY_SCENE if ResourceLoader.exists(SUMMARY_SCENE) else TITLE_SCENE)


## THE OPT-IN DETOUR. Walk into the parked v0.0 town.
##
## ⚠ NOT ON THE CRITICAL PATH, AND THAT IS THE WHOLE POINT. The summary card offers
## it as a button and hides that button on a build that has no business showing it.
## Returns false when the hub is not in this build.
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


func _change_scene(path: String) -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.change_scene_to_file(path)


# --------------------------------------------------- climber persistence (IO)
## Atomic save: write <path>.tmp then rename over the real file, so a crash
## mid-write can't corrupt an existing climber.
func _save_climber(path: String = CLIMBER_PATH) -> void:
	# ═══════════════════════════════════════════════════════════════════════════
	# ⚠ A TEST RUN MUST NEVER WRITE THE PLAYER'S REAL SAVE. THIS IS THAT GUARD.
	# ═══════════════════════════════════════════════════════════════════════════
	# It bit three times in one session before it was fixed here rather than
	# patched at each call site:
	#
	#   1. A suite drove `advance_floor()` on a bare `GameState.new()`. That saves,
	#      so the maker's climber.json quietly gained 123 xp.
	#   2. Hero stats read `power_level()`, so on the NEXT run two class-stat suites
	#      spawned level-2 heroes and went red — for a reason that had nothing to do
	#      with the code under test, and that would have gone green again on a fresh
	#      save while hiding any real regression.
	#   3. Fixing those, adding a new end-to-end suite, and running it did it AGAIN
	#      (589 xp), reddening two different suites. At that point it is not a
	#      mistake anyone is going to stop making; it is a missing guard.
	#
	# THE DISCRIMINATOR IS THE TREE. The real autoload is always inside it; a bare
	# `GameState.new()` — which is precisely what makes the run spine testable
	# without a scene — never is. A test that genuinely wants to prove the disk
	# round-trip passes an EXPLICIT path (slice_test_climb does), and saying so is
	# taken as "I know what I am doing".
	if path == CLIMBER_PATH and not is_inside_tree():
		return
	var payload: Dictionary = build_climber_save(
		_floor, _highest_floor, _falls, tower_conquered, _live_rank_power(),
		_xp, unlocked_nodes, unlocked_classes,
		pending_class_choices, _earned_choice_floors, loadout,
		spell_roles, spell_equipped
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
	_xp = int(state["xp"])
	unlocked_nodes = state["unlocked_nodes"]
	unlocked_classes = state["unlocked_classes"]
	pending_class_choices = int(state["pending_class_choices"])
	_earned_choice_floors = state["earned_choice_floors"]
	# The hub's gear choice, restored. `Hero._apply_gamestate_loadout` re-reads this
	# after every `configure_class`, so a climber walks back into the tower wearing
	# what they picked last session rather than their class default.
	loadout = state["loadout"]


# ------------------------------------------------------------- the local board
## How long the current run has been going, in milliseconds. 0 outside a run.
func _elapsed_ms() -> int:
	if _run_started_ms <= 0:
		return 0
	return maxi(Time.get_ticks_msec() - _run_started_ms, 0)


## Is this a networked session? Recorded as a FACT on a board row (co-op runs are
## easier per head and it is honest to say which rows were which), never as a score
## input. Same `is_inside_tree()` guard as `_is_net_host` and for the same reason: an
## absolute `get_node()` from a detached node is an ERROR, and the suites drive a bare
## `GameState.new()` on purpose.
func _is_coop_session() -> bool:
	if not is_inside_tree():
		return false
	var n: Node = get_node_or_null("/root/Net")
	return n != null and n.is_active()


## THE PERSONAL BEST, derived from the board. `{}` until the first run finishes.
func best_climb() -> Dictionary:
	return ClimbScore.best(score_history)


## The best floor ever recorded on the board. 0 means "no finished run yet" — which is
## not the same as `_highest_floor`, which counts a floor the moment you STAND on it.
func best_climb_floor() -> int:
	return ClimbScore.best_floor(score_history)


## The board, ranked. Handed to whatever draws it.
func score_board() -> Array:
	return ClimbScore.ranked(score_history)


## Write the local board. Atomic (tmp-then-rename), and carrying the SAME tree guard
## `_save_climber` carries — a test run must never write the player's real board, and
## the discriminator is the same one: the real autoload is always inside the tree and
## a bare `GameState.new()` never is. A suite that genuinely wants the disk round-trip
## passes an explicit path, which is taken as "I know what I am doing".
func _save_scores(path: String = SCORES_PATH) -> void:
	if path == SCORES_PATH and not is_inside_tree():
		return
	var payload: Dictionary = ClimbScore.build_board(score_history)
	var tmp_path: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("GameState._save_scores: cannot open %s for writing" % tmp_path)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("GameState._save_scores: cannot open user://")
		return
	var err: int = dir.rename(tmp_path.get_file(), path.get_file())
	if err != OK:
		push_error("GameState._save_scores: rename %s -> %s failed (err=%d)"
			% [tmp_path.get_file(), path.get_file(), err])


## Load the local board. A missing or malformed file yields an EMPTY board and no
## error path — the board is a nice-to-have, and a corrupt one must never be able to
## stop the game from starting the way a corrupt climber save could.
##
## ⚠ AND IT RECONCILES `_highest_floor` UPWARD. The board and the monotone counter are
## two records of the same fact, and the codebase's own standing lesson is that two
## stored numbers about one thing will eventually disagree. They cannot be collapsed
## into one (the counter ticks when you STAND on a floor; a board row exists only once
## a run has FINISHED), so instead the load makes the counter the maximum of the two.
## A hand-deleted climber.json therefore does not silently erase a real best.
func _load_scores(path: String = SCORES_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	var board: Dictionary = ClimbScore.parse_board(parsed)
	score_history = board["history"]
	_highest_floor = maxi(_highest_floor, ClimbScore.best_floor(score_history))


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


# ═══════════════════════════════════════════════════════════════════════════════
# XP — THE ONE PLACE IT ENTERS
# ═══════════════════════════════════════════════════════════════════════════════

## Current level, derived from lifetime XP. Never stored.
func level() -> int:
	return Progression.level_for_xp(_xp)


func xp() -> int:
	return _xp


## The climber's lifetime best floor. A PUBLIC READ of `_highest_floor`, which the
## unlock table (`Progression.gear_state` / `spell_state`) is stated in terms of and
## which two UI screens now ask for. It existed only as an underscore field others were
## reaching into with `gs.get("_highest_floor")` — a private name read through a string
## is a rename waiting to fail silently, and there are now three more callers.
func highest_floor() -> int:
	return maxi(_highest_floor, 1)


## XP banked into the current level, and what the next one costs — the two numbers
## a progress bar needs, both derived so the bar can never disagree with the level.
func xp_into_level() -> int:
	return Progression.xp_into_level(_xp)


func xp_for_next_level() -> int:
	return Progression.xp_to_next(level())


## The level a HERO is built at. Solo: your own. Co-op: the party cap, frozen at
## entry. This is the single accessor every stat consumer reads, so there is exactly
## one answer to "how strong am I right now".
func power_level() -> int:
	if _party_level > 0:
		return mini(_party_level, level())
	return level()


## Resolve the party's power level and FREEZE it for the run. Called with every
## member's level at the moment the party enters the tower — the same moment
## `party_start_floor` resolves where they start.
func set_party_levels(levels: Array) -> void:
	_party_level = Progression.party_growth_level(levels) if not levels.is_empty() else -1


## Solo, or a run that never resolved a party: clear the cap.
func clear_party_level() -> void:
	_party_level = -1


## THE ONE PLACE XP IS BANKED. Everything else routes here.
##
## Returns the number of levels gained (0 normally), so a caller can react without
## having to diff `level()` around the call itself.
##
## ⚠ THE LEVEL IS RE-DERIVED, NOT INCREMENTED. Adding XP and separately bumping a
## stored level is two sources of truth for one fact; deriving both sides from `_xp`
## means a level-up cannot be missed, double-counted, or awarded twice by a retry.
func grant_xp(amount: int, kind: String = "kill", where: Vector2 = Vector2.ZERO) -> int:
	var n: int = maxi(amount, 0)
	if n <= 0:
		return 0
	var before: int = Progression.level_for_xp(_xp)
	_xp += n
	var after: int = Progression.level_for_xp(_xp)
	xp_gained.emit(n, kind, where)
	# Co-op: the host is the only peer that runs enemy death, so it is the only peer
	# that can see a kill happen. Everyone in the fight earned it, so the host relays
	# the grant and every peer banks it into their OWN save.
	if _is_net_host():
		var net: Node = get_node_or_null("/root/Net")
		if net != null and net.has_method("broadcast_xp"):
			net.call("broadcast_xp", n, kind, where)
	for l: int in range(before + 1, after + 1):
		leveled_up.emit(l)
	return maxi(after - before, 0)


## Co-op CLIENT receiver. Banks the host's relayed grant WITHOUT re-broadcasting —
## the guard is `_is_net_host()` inside `grant_xp`, and a client is not the host, so
## this could safely call straight through. It goes through the same function on
## purpose: one banking path means a client and a host can never level differently.
func receive_net_xp(amount: int, kind: String, where: Vector2 = Vector2.ZERO) -> void:
	grant_xp(amount, kind, where)


## FLUSH THE CLIMBER TO DISK FROM OUTSIDE A RUN.
##
## Every other save happens on a floor transition, which is fine for the climb but
## not for the two things you do in the TOWN: spending a skill point and picking an
## unlocked class. Without this, buying a node and then quitting from the hub loses
## the purchase — and the point is spent, because `points_spent` is derived from the
## nodes that did not save. Public because the tree screen and the class altar are
## legitimately outside the run spine.
func save_progress() -> void:
	_save_climber()


## A locked class was earned. Idempotent, so a second grant of the same class (a
## replayed guardian, a co-op double-award) cannot put it in the list twice and make
## `choosable_classes` disagree with itself.
func unlock_class(hero_class: int) -> bool:
	if Progression.is_class_unlocked(hero_class, unlocked_classes):
		return false
	unlocked_classes.append(int(hero_class))
	save_progress()
	return true


## SPEND a banked guardian pick on a specific locked class. Returns false — and
## costs nothing — in every refusing case, so the altar can call it optimistically
## and read the answer rather than having to re-derive the rules itself.
##
## ⚠ THE "ALREADY HELD" REFUSAL IS THE ONE THAT MATTERS. Two taps on the same card
## before the panel redraws would otherwise burn a second pick on a class the
## climber already owns — the pick is gone, and nothing is gained. It is the exact
## shape of the co-op pickup double-award that was fixed earlier on this branch.
func spend_class_choice(hero_class: int) -> bool:
	if pending_class_choices <= 0:
		return false
	if not Progression.LOCKED_CLASSES.has(hero_class):
		return false
	if Progression.is_class_unlocked(hero_class, unlocked_classes):
		return false
	pending_class_choices -= 1
	unlocked_classes.append(int(hero_class))
	save_progress()
	return true


## ⚠ THE `is_inside_tree()` GUARD IS LOAD-BEARING, not defensive noise. An absolute
## `get_node()` from a node that is not in the tree is an ERROR in Godot, not a null
## — and the headless suites drive a bare `GameState.new()` on purpose (that is what
## makes the run spine testable without a scene). Every other tree lookup in this
## file already carries it; this one was added last and did not, which turned a
## clean test into eight lines of red herring.
func _is_net_host() -> bool:
	if not is_inside_tree():
		return false
	var n: Node = get_node_or_null("/root/Net")
	return n != null and n.is_active() and n.is_host()


## Open the floor's kill purse. Called at every floor entry — see `_floor_kill_purse`.
func _open_floor_purse() -> void:
	_floor_kill_purse = int(round(Progression.floor_xp_value(_floor) * Progression.KILL_SHARE))


## How many bodies this floor authored — the denominator the per-enemy XP is derived
## against. Sums the authored waves, falling back to the flat field for a floor that
## has none (the synthesized fallback, and the F6 sandbox).
func _floor_body_count() -> int:
	var fd: FloorDef = floor_def_for(_floor)
	if fd == null:
		return 1
	var total: int = 0
	for w: WaveDef in fd.waves:
		total += maxi(w.enemy_budget, 0)
	return maxi(total if total > 0 else fd.enemy_budget, 1)


# --------------------------------------------------- live-run notifications
## A villain fell. Pays from the floor's purse and never past it.
func notify_kill(where: Vector2 = Vector2.ZERO) -> void:
	_kills += 1
	if not _run_active:
		return
	var per: int = Progression.enemy_xp(_floor, _floor_body_count())
	# The purse can hand out less than a full body's worth on the last one, which is
	# correct: the floor pays what it is worth and then it is empty.
	var pay: int = mini(per, maxi(_floor_kill_purse, 0))
	if pay <= 0:
		return
	_floor_kill_purse -= pay
	grant_xp(pay, "kill", where)


## THE GUARDIAN FELL. The biggest single XP event on a floor, and paid OUTSIDE the
## kill purse because it is not one of the floor's bodies — it is what the floor was
## built toward.
##
## ⚠ THIS ALSO CLOSES A LATENT GAP. `notify_boss_killed` existed and was called by
## NOBODY: `_boss_killed` was only ever set inside `advance_floor` when clearing the
## LAST floor, so a guardian felled on floors 1-9 was never recorded in the outcome
## at all. `Boss` now routes its death here.
func notify_guardian_killed(where: Vector2 = Vector2.ZERO) -> void:
	_boss_killed = true
	if not _run_active:
		return
	grant_xp(Progression.guardian_xp(_floor), "guardian", where)
	_maybe_earn_class_choice()


## ⚠ THE GUARDIAN GRANTS A CHOICE, NOT A DROP.
##
## The maker floated "the 5th floor boss is a one time one of the 3 remaining
## classes". A RANDOM one means the class you get is a coin flip and the correct
## play is to farm the boss until it gives you the one you wanted. Felling the
## guardian instead banks a PICK, which you spend at the altar in the town.
## Deterministic, still a milestone, and the choosing is the part you remember.
##
## Banked rather than spent here for two reasons: a class-select screen popping up
## mid-fight is the worst possible moment for it, and the pick has to survive the
## walk home — including a walk home that ends in a party wipe on the next floor.
func _maybe_earn_class_choice() -> void:
	if not Progression.CLASS_UNLOCK_FLOORS.has(_floor):
		return
	if Progression.choosable_classes(unlocked_classes).is_empty():
		return
	# ⚠ ONE PER FLOOR, EVER. `_earned_choice_floors` is what stops a re-climb of the
	# tower (which is the SHIPPED behaviour — a conquered tower re-climbs from floor
	# 1) handing out the same guardian's reward on every lap. Without it, three
	# classes would be four re-climbs of floor 5.
	if _earned_choice_floors.has(_floor):
		return
	_earned_choice_floors.append(_floor)
	pending_class_choices += 1
	_save_climber()
	class_choice_earned.emit(_floor)


func notify_boss_killed() -> void: _boss_killed = true
func notify_element_used(display_name: String) -> void: _elements_used[display_name] = true
## Banked by `FriendlyFire.report`. The only number in the game that says what the
## party did to itself — without it, "friendly fire is the social engine" is a claim
## nobody can check after the fact.
func notify_friendly_fire(amount: int) -> void: _friendly_damage += maxi(amount, 0)
func friendly_damage() -> int: return _friendly_damage
func is_run_active() -> bool: return _run_active
func current_floor() -> int: return _floor


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
##
## ⚠ THE FIVE SCORE FIELDS ARE APPENDED TOO, and for the same reason. They are what
## the run card needs to say "floor 34, a new best, 2nd of 25" without going and
## computing any of it a second time — and a second computation of a ranking is how a
## victory screen ends up disagreeing with the board it is supposed to be reporting.
## `peak_floor` is NOT the same as `floor_reached`: you can die on floor 34 having
## walked back down to 32, and the score is the height you reached.
static func build_outcome(
	floor_reached: int, kills: int, boss_killed: bool, died: bool,
	elements: Array, rank_tier: int, rank_title: String, falls: int = 0,
	friendly_damage: int = 0, highest_floor: int = 0, total_floors_in_tower: int = 0,
	peak_floor: int = 0, elapsed_ms: int = 0, board_place: int = 0,
	is_record: bool = false, previous_best: int = 0
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
		# ── THE SCORE. `peak_floor` is the headline, `elapsed_ms` the tiebreak; the
		# other three are what the card says ABOUT them. See ClimbScore.
		"peak_floor": maxi(peak_floor, floor_reached),
		"elapsed_ms": maxi(elapsed_ms, 0),
		"board_place": maxi(board_place, 0),
		"is_record": is_record,
		"previous_best": maxi(previous_best, 0),
	}



## The FloorDef for a given floor: the authored one if a tower is active, else a
## FloorDef synthesized from the depth math (identical to pre-tower behaviour).
##
## ⚠ THREE ANSWERS NOW, AND THE THIRD IS THE ASCENT. Past the authored spine on an
## endless tower the floor is SYNTHESIZED (`ascent_floor_def`) and then run through
## the very same `FloorGen.vary_floor` an authored floor is redrawn by — so it gets a
## generated room, a jittered biome, a varied mix and the same `gen:`/`genseed:` tags.
## Everything downstream is handed a `FloorDef` and cannot tell which kind it got,
## which is the whole point: `Encounter`, `Arena`, `FloorBuilder`, `BossRoster` and
## `EliteRoster` needed no change at all to climb forever.
func floor_def_for(floor: int) -> FloorDef:
	if active_tower != null and floor >= 1 and floor <= active_tower.floors.size():
		return active_tower.floors[floor - 1]
	if is_endless() and floor > active_tower.floors.size():
		return _ascent_floor(floor)
	return synthesize_floor_def(floor)


## One ascent floor, cached by depth. See `_ascent_cache` for why the cache is
## correctness rather than speed.
##
## The seed comes off the TOWER (`TowerDef.climb_seed`, stamped by `FloorGen`), not
## off `FloorGen.last_seed`: that static is process-global and any other climb or tool
## in the same process may have moved it, whereas the tower's own number is the one
## this climb was actually drawn with — and in co-op it is the pinned 0 both peers
## share, so both derive the same floor 37.
func _ascent_floor(floor: int) -> FloorDef:
	var d: int = clampi(floor, 1, MAX_CLIMB_FLOOR)
	if _ascent_cache.has(d):
		return _ascent_cache[d]
	var tower_id: String = active_tower.id if active_tower != null else "ashspire"
	var seed_value: int = active_tower.climb_seed if active_tower != null else 0
	var fd: FloorDef = FloorGen.vary_floor(ascent_floor_def(d), d, tower_id, seed_value, true)
	# HEALING, TAKEN AWAY — stamped after the redraw because `FloorGen.generate_layout`
	# builds a fresh LayoutDef and never has an opinion about packs, so this is the
	# only place the ascent's opinion can survive. See `LayoutDef.health_packs_authored`.
	if fd.layout != null:
		fd.layout.health_packs_authored = true
		fd.layout.health_pickups = _ascent_health_packs(d, fd.layout)
	_ascent_cache[d] = fd
	return fd


## Where an ascent floor's health packs go, and how many.
##
## 2 to floor 20, 1 from 21, NONE from 36 — the design note's terminal escalation, and
## the honest opposite of an HP sponge: it does not make a fight longer, it makes your
## margin inside one smaller. The positions mirror `FloorBuilder.DEFAULT_HEALTH_PACKS`
## (the same room fractions, resolved against this floor's own room) so the pack sits
## where a player has learned packs sit, and so nothing random enters a function both
## co-op peers must agree on.
static func _ascent_health_packs(depth: int, layout: LayoutDef) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if depth >= ASCENT_NO_HEAL_DEPTH:
		return out
	var want: int = 1 if depth >= ASCENT_ONE_PACK_DEPTH else 2
	var room: Vector2 = layout.room_size
	for i: int in mini(want, DEFAULT_HEALTH_PACK_FRACTIONS.size()):
		var frac: Vector2 = DEFAULT_HEALTH_PACK_FRACTIONS[i]
		out.append(Vector2(room.x * frac.x, room.y * frac.y))
	return out


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
	fd.theme = floor_env(floor)
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
## The three levelling fields are APPENDED with defaults rather than inserted, so
## every existing 5-argument caller (and the suites that pin them) is untouched.
static func build_climber_save(current_floor: int, highest_floor: int, falls: int, tower_conquered: bool, rank_power: int,
		xp: int = 0, unlocked_nodes: Array = [], unlocked_classes: Array = [],
		pending_class_choices: int = 0, earned_choice_floors: Array = [],
		loadout: Dictionary = {}, spell_roles: Dictionary = {},
		spell_equipped: Dictionary = {}) -> Dictionary:
	var current: int = maxi(current_floor, 1)
	var nodes: Array = []
	for n in unlocked_nodes:
		var id: String = str(n)
		if id != "" and not nodes.has(id):
			nodes.append(id)
	var classes: Array = []
	for c in unlocked_classes:
		var ci: int = int(c)
		if not classes.has(ci):
			classes.append(ci)
	return {
		"version": CLIMBER_SAVE_VERSION,
		"current_floor": current,
		"highest_floor": maxi(highest_floor, current),
		"falls": maxi(falls, 0),
		"tower_conquered": tower_conquered,
		"rank_power": maxi(rank_power, 0),
		"xp": maxi(xp, 0),
		"unlocked_nodes": nodes,
		"unlocked_classes": classes,
		"pending_class_choices": maxi(pending_class_choices, 0),
		"earned_choice_floors": earned_choice_floors.duplicate(),
		# ⚠ THE HUB LOADOUT IS PART OF THE CLIMBER, NOT PART OF THE RUN.
		#
		# Maker: *"it should be like equippable in the hub and changing the weapon"*.
		# It already was — the Armory pad writes `GameState.loadout` and
		# `Hero._apply_gamestate_loadout` re-applies it after every class setup — but
		# `loadout` was a plain var that nothing ever wrote to disk. So the choice
		# survived walking into the tower and did NOT survive quitting the game, which
		# makes "equippable in the hub" a thing you re-do every session.
		#
		# Sanitised to the three real slots on the way out rather than duplicated
		# whole: an old save, a hand-edited one, or a future slot that gets removed
		# must not be able to put an unknown key into the rig's equipment dictionary.
		"loadout": sanitize_loadout(loadout),
		# ⚠ AND THE SPELL PICKS, WHICH HAD THE SAME HOLE `loadout` IS DESCRIBED AS HAVING
		# ABOVE. `spell_roles` was declared, hydrated and persisted, and never written to
		# disk — so a re-ordered hand survived walking into the tower and did not survive
		# quitting. `spell_equipped` would have shipped with the identical hole, and the
		# maker's answer to "how do the Tier 3s reach the player" was EQUIP THEM IN THE
		# HUB, which is not a feature if the hub forgets.
		#
		# Duplicated rather than sanitised: unlike `loadout`, an unknown key here cannot
		# reach a rig — `SpellLibrary.set_equipped` validates the slot AND the id on the
		# way back in, so a hand-edited save is refused at hydrate time, not trusted here.
		"spell_roles": spell_roles.duplicate(true),
		"spell_equipped": spell_equipped.duplicate(true),
	}


## The three gear slots, and the only keys allowed into a save or out of one.
## ⚠ `legs` JOINED ON 2026-09-05 AND `Hero._aggregate_gear` STILL ITERATES THREE.
## That is deliberate, not an oversight: this list decides what SURVIVES A SAVE, and the
## player's greave choice has to, or the armoury forgets it the moment they walk away.
## What Hero reads decides what APPLIES A STAT, and every greave is a placeholder with an
## empty effect bag — so a fourth slot Hero never looks at cannot apply anything, and the
## day one earns a real stat the fix is one literal in a file this one does not own.
## A save written before this simply has no `legs` key; `sanitize_loadout` reads "" for it.
const LOADOUT_SLOTS: Array[String] = ["weapon", "head", "body", "legs"]


## A loadout dict reduced to known slots with string values. Shared by the writer
## and the reader so a save cannot round-trip into something the rig would not
## accept — see the note in `build_climber_save`.
static func sanitize_loadout(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for slot: String in LOADOUT_SLOTS:
		var v: Variant = (raw as Dictionary).get(slot, "")
		# ⚠ THE ITEM MUST STILL BE OFFERED, not merely be a non-empty string. The armoury
		# catalogue was replaced with placeholders, and a save written before that still
		# names a piece like `head: "helmet"` — which `Hero._apply_gamestate_loadout`
		# happily keeps applying, so a returning player carries a +20% max HP bonus from
		# an item that is no longer in the game and that they cannot see, unequip, or
		# explain. The armoury sanitises on open, but only for a player who walks to it.
		# This is the one place every load path passes through.
		if typeof(v) == TYPE_STRING and String(v) != "" 				and (GearAbilities.PLACEHOLDER_SLOTS.get(slot, []) as Array).has(String(v)):
			out[slot] = String(v)
	return out


## Parse a raw (JSON-loaded) climber dict into typed fields. JSON.parse_string
## returns numbers as TYPE_FLOAT, so EVERY int is coerced through int() — the M9
## trap. A malformed/empty dict yields fresh-climber defaults (floor 1).
static func parse_climber_save(raw: Dictionary) -> Dictionary:
	var current: int = maxi(int(raw.get("current_floor", 1)), 1)
	var highest: int = maxi(int(raw.get("highest_floor", current)), current)
	var falls: int = maxi(int(raw.get("falls", 0)), 0)
	var conquered: bool = bool(raw.get("tower_conquered", false))
	var rank_power: int = maxi(int(raw.get("rank_power", 0)), 0)
	# THE v1 -> v2 MIGRATION, and it is these three lines. A save written before
	# levelling existed has none of these keys, so it arrives as a level-1 climber
	# with the six starting classes — which is exactly what it is.
	var xp: int = maxi(int(raw.get("xp", 0)), 0)
	var nodes: Array[String] = []
	for n in (raw.get("unlocked_nodes", []) as Array):
		var id: String = str(n)
		if id != "" and not nodes.has(id):
			nodes.append(id)
	# ⚠ int() ON EVERY ELEMENT. JSON.parse_string gives `6.0`, not `6`, and an array
	# of floats compared with `==` against an int class id matches NOTHING — an
	# unlocked class would silently re-lock on every load. The M9 trap, in a list.
	var classes: Array[int] = []
	for c in (raw.get("unlocked_classes", []) as Array):
		var ci: int = int(c)
		if not classes.has(ci):
			classes.append(ci)
	# ⚠ int() ON EVERY ELEMENT, same trap as `unlocked_classes` above. A guardian floor
	# that came back as 5.0 would never match `_floor`, so the re-climb guard would
	# silently stop guarding and floor 5 would pay a class pick on every lap.
	var earned: Array[int] = []
	for f in (raw.get("earned_choice_floors", []) as Array):
		var fi: int = int(f)
		if not earned.has(fi):
			earned.append(fi)
	# Absent on every save written before the hub loadout was persisted, which is
	# exactly what an empty loadout means: the class defaults win. No migration
	# needed and none should be added.
	var gear: Dictionary = sanitize_loadout(raw.get("loadout", {}))
	return {
		"current_floor": current,
		"highest_floor": highest,
		"falls": falls,
		"tower_conquered": conquered,
		"rank_power": rank_power,
		"xp": xp,
		"unlocked_nodes": nodes,
		"unlocked_classes": classes,
		"pending_class_choices": maxi(int(raw.get("pending_class_choices", 0)), 0),
		"earned_choice_floors": earned,
		"loadout": gear,
		# Absent on every save written before this existed, and an empty dictionary is
		# exactly right for that: the authored hand wins. No migration needed.
		"spell_roles": raw.get("spell_roles", {}) if raw.get("spell_roles", {}) is Dictionary else {},
		"spell_equipped": raw.get("spell_equipped", {}) if raw.get("spell_equipped", {}) is Dictionary else {},
	}


# ======================================================================
# The Ashen Tower — the default tower, built in code (a maker-authored
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

## ══ THE BREATH BETWEEN WAVES (early floors only) ══════════════════════════════
## `FloorDef.wave_break` defaults to 0.85 — the SURGE beat, deliberately short and
## loud rather than silent (see the PACING block at the top of Encounter.gd). The
## early floors override it upward, and floors 4+ keep the tower's own relentless
## default, because the maker's note was "the difficulty is nicer later up".
##
## ⚠ THIS DOES NOT REINTRODUCE DEAD AIR, and the reason is the OVERLAP, not the
## number. The surge does not start when the room empties — it starts when the
## wave is down to its last `handoff_alive` bodies, which are still up and still
## swinging through the whole beat. So the break is bounded by the player's own
## aggression: kill the stragglers fast and you have BOUGHT the quiet; leave them
## and the next wave lands on top of a fight already in progress. A 1.8s beat is
## about one room-crossing at hero SPEED — enough to pick a corner, not enough to
## put the phone down.
##
## Floor 1's LAST wave is the one place the room genuinely empties (handoff 0, so
## the first guardian anyone meets arrives alone) — and that transition does not
## use this timer at all: `_tick_wave` calls `_begin_boss()` directly.
const EARLY_WAVE_BREAKS: Array[float] = [1.8, 1.4, 1.1]


# ══════════════════════════════════════════════════════════════════════════════
# THE ASCENT — every floor past the authored spine
# ══════════════════════════════════════════════════════════════════════════════
# Design note: docs/superpowers/specs/2026-09-04-infinite-tower-and-score.md SS2.
#
# ⚠ THE ONE RULE THIS FILE ALREADY STATES AT FOUR SITES, AND WHICH AN INFINITE CURVE
# IS THE STRONGEST POSSIBLE TEMPTATION TO BREAK:
#
#     "higher floors add modifiers, not HP. HP scaling makes fights longer, not
#      harder, and long is the enemy of chaos on a phone."
#
# So `hp_multiplier` is 1.0 at EVERY generated depth, forever, and
# `tools/slice_test_endless.gd` fails the build if a single ascent floor ever says
# otherwise. Depth is carried by WHO shows up, HOW MANY AT ONCE, and what rules ride
# the room — never by how long the same body takes to kill.
#
# ── WHAT ESCALATES, AND WHERE IT STOPS ────────────────────────────────────────
#   type rhythm   C,C,E,C,B repeating every 5 — a guardian at 15/20/25..., which
#                 puts a checkpoint (DeathRules band 5) right after each one
#   archetype mix 2 classes -> 3 (f17) -> 4 (f23), and widening INSIDE each floor
#   wave count    4 -> 5 (f16) -> 6 (f21), and 6 is the ceiling
#   bodies        78 +2/floor -> 90 at floor 16, then FLAT
#   pressure cap  8 -> 9 (f16) -> 10 (f21), then FLAT
#   guardian HP   x2.4 +0.1/floor -> x4.0 at floor 26, then FLAT
#   floor affixes 1 (f11) -> 2 (f26) -> 3 (f41)          [FloorGen]
#   healing       2 packs -> 1 (f21) -> none (f36)
#
# ⚠ EVERYTHING PLATEAUS, AND THAT IS THE DESIGN RATHER THAN AN OVERSIGHT. By floor 41
# the tower is at terminal intensity and stays there. For a HEIGHT score that is the
# correct shape: past the plateau the question stops being "can you survive what is
# next" and becomes "how long can you hold at the ceiling", which is exactly what the
# score measures. An unbounded curve is just a wall with a floor number on it, and
# every player's score would converge on the same floor anyway.

## The ascent's band length. 5, matching `DeathRules.CHECKPOINT_BAND`, so that a
## band's guardian and the checkpoint you resume on after failing it are the same
## boundary. That alignment is free and it is why the period is not 4 or 6.
const ASCENT_BAND: int = 5

## Body count continues the authored curve from floor 10's 78 and stops at 90.
## 90 bodies at a cap of 10 is already ~4 minutes of continuous fighting; a floor-60
## room holding 300 would be a chore at exactly the same peak intensity.
const ASCENT_BODY_STEP: int = 2
const ASCENT_BODY_CAP: int = 90

## Concurrent alive. Ten on a 640x360 screen under a fit-all camera is already dense;
## twelve is soup, and the maker's own note on the early floors was "there are too
## many opponents".
const ASCENT_CAP_MAX: int = 10

## Waves per floor. Six is the ceiling because a seventh wave is not harder, it is
## longer — the exact failure mode the HP rule exists to prevent, wearing a hat.
const ASCENT_MIN_WAVES: int = 4
const ASCENT_MAX_WAVES: int = 6

## The guardian's depth HP curve, continued from floor 10's x2.4 and CAPPED. This is
## the one place depth may legitimately buy HP (one committed duel, not twelve bodies
## to shred) and x4.0 is where it stops being a duel and starts being a wait.
const ASCENT_BOSS_HP_STEP: float = 0.1
const ASCENT_BOSS_HP_CAP: float = 4.0

## ══ HOW MANY THREAT CLASSES ARRIVE AT ONCE — the headline escalation ═════════
##
## ⚠ THE ESCALATION IS *HOW EARLY THE FLOOR GETS WIDE*, NOT HOW WIDE IT EVER GETS,
## AND THE FIRST VERSION HAD THAT BACKWARDS. It ramped a floor's MAXIMUM breadth from
## 2 up to 4 — which sounds like escalation and is actually a cliff at the seam. The
## authored spine already ENDS wide: floor 10's finale is chaser/brute/charger/
## assassin/bomber/mage, all four classes at once. So an ascent that opened at two
## classes made floors 11-15 NARROWER than the floor below them.
##
## `tools/probe_endless_curve.gd` measured exactly that, and it is the whole reason
## this block reads the way it does: floors 11-15 came back at index 32.8 / 31.4 /
## 30.1 / 31.9 / 32.2 against floor 10's 32.4 — four of the first five ascent floors
## were a step DOWN from the summit. That is the "an infinite tower that starts with
## procedural filler is strictly worse than what exists" failure, moved to floor 11.
##
## So every ascent floor's FINALE is four classes, continuing the spine, and what
## climbs with depth is the OPENING: floor 11 opens at two and widens across its waves,
## floor 17 opens at three, floor 23 opens at four and every wave of it is a finale.
## The floor stops giving you a narrow wave to settle into, which is a harder floor in
## the way the maker asked for and in no other way.
const ASCENT_BREADTH_OPEN_MIN: int = 2   # the opening wave, on the first ascent floors
const ASCENT_BREADTH_MAX: int = 4        # the finale, on EVERY ascent floor
const ASCENT_BREADTH_EVERY: int = 6      # the opening widens by one every six floors

## Where a COMBAT floor starts concentrating its elite budget into one wave (an ELITE
## floor always does, mirroring the authored table). Below this the ascent's elites
## are still sprinkled, which keeps the first ascent band reading as "more of the
## tower" rather than as "a new system".
const ASCENT_ELITE_WAVE_DEPTH: int = 21

## Healing, taken away — the terminal escalation. See `_ascent_health_packs`.
const ASCENT_ONE_PACK_DEPTH: int = 21
const ASCENT_NO_HEAL_DEPTH: int = 36

## ⚠ DUPLICATED FROM `FloorBuilder.DEFAULT_HEALTH_PACKS`, DELIBERATELY, AND GUARDED
## BY A TEST. `tools/slice_test_endless.gd` fails if these two ever disagree.
##
## This is the same trade `FloorGen.FLOOR_AFFIX_POOL` already makes against
## `EliteRoster.FLOOR_AFFIX_POOL`, and for a sharper version of the same reason.
## Naming `FloorBuilder` here puts it in `GameState`'s COMPILE graph, and
## `FloorBuilder` preloads `DestructibleProp.tscn`, whose script calls `Sfx.play`.
## `Sfx` is an AUTOLOAD, not a `class_name` — so in any `--script` harness that
## `load()`s GameState from `_init`, the autoloads are not registered yet, the
## identifier does not resolve, and the WHOLE compile fails with an error that names
## a crate sound effect and points nowhere near the tower. It was caught by
## `slice_test_runend` doing exactly that, and this project has the mirror-image trap
## already recorded ("preloading Arena.gd forces compile-time resolution of the
## GameState autoload").
##
## The general cost is worth stating too: `GameState` is loaded by a lot of suites,
## so every compile-scope dependency added here is paid by all of them.
const DEFAULT_HEALTH_PACK_FRACTIONS: Array[Vector2] = [
	Vector2(0.18, 0.34), Vector2(0.82, 0.34),
]

## The four threat classes, in the fixed order the rotation walks. Mirrors
## `FloorGen.CLASS_*` — the same four pairs, written here as a table so the
## composition below reads as data rather than as four constant lookups.
const ASCENT_CLASSES: Array = [
	[A_CHASER, A_ASSASSIN],     # PRESSURE — bodies in your face
	[A_BRUTE, A_CHARGER],       # HEAVY    — telegraphed commitment
	[A_CASTER, A_MAGE],         # RANGED   — you cannot only look forward
	[A_SUMMONER, A_BOMBER],     # ODD      — threat multipliers
]


## THE ASCENT BLUEPRINT for one depth. Pure + static, so the whole curve is readable
## from a headless probe (`tools/probe_endless_curve.gd`) without a run being active —
## which is the only way an escalation like this gets argued about rather than trusted.
##
## What comes back is a plain `FloorDef` in exactly the shape `_make_floor` produces
## for an authored floor. `_ascent_floor` then runs it through `FloorGen.vary_floor`,
## which draws the room, jitters the biome and varies the mix — the same treatment an
## authored floor gets, which is what makes the two indistinguishable downstream.
static func ascent_floor_def(depth: int) -> FloorDef:
	var d: int = maxi(depth, TOTAL_FLOORS + 1)
	var since: int = d - TOTAL_FLOORS                 # 1 on the first ascent floor
	@warning_ignore("integer_division")
	var band: int = (since - 1) / ASCENT_BAND         # 0, 1, 2, ...
	var pos: int = (since - 1) % ASCENT_BAND          # 0..4 inside the band

	# ── THE TYPE RHYTHM. Band 1's own shape (C, C, E, C, B), repeating.
	var ftype: int = FloorDef.FloorType.COMBAT
	if pos == ASCENT_BAND - 1:
		ftype = FloorDef.FloorType.BOSS
	elif pos == 2:
		ftype = FloorDef.FloorType.ELITE

	# ── HOW MUCH FIGHT. Continues floor 10's numbers rather than restarting them, so
	#    crossing the summit is a step up and not a fresh start.
	var bodies: int = mini(ASCENT_BODY_CAP, 78 + ASCENT_BODY_STEP * since)
	var cap: int = mini(ASCENT_CAP_MAX, 8 + band)
	var n_waves: int = clampi(ASCENT_MIN_WAVES + band, ASCENT_MIN_WAVES, ASCENT_MAX_WAVES)
	if ftype == FloorDef.FloorType.BOSS:
		n_waves = mini(n_waves + 1, ASCENT_MAX_WAVES)
	@warning_ignore("integer_division")
	var opening: int = clampi(ASCENT_BREADTH_OPEN_MIN + (since - 1) / ASCENT_BREADTH_EVERY,
		ASCENT_BREADTH_OPEN_MIN, ASCENT_BREADTH_MAX)

	# ── THE WAVES.
	var elite_idx: int = -1
	if ftype == FloorDef.FloorType.ELITE \
			or (ftype == FloorDef.FloorType.COMBAT and d >= ASCENT_ELITE_WAVE_DEPTH):
		# The SECOND-TO-LAST wave, which is where every authored elite wave sits
		# (floors 3, 7 and 9 all put it at n-2): late enough to be an event, early
		# enough that the floor still has a finale after it.
		elite_idx = maxi(n_waves - 2, 0)
	var waves: Array[WaveDef] = []
	var budgets: Array[int] = _ascent_budgets(bodies, n_waves)
	for i: int in n_waves:
		var w := WaveDef.new()
		w.enemy_budget = budgets[i]
		# The cap RAMPS INSIDE THE FLOOR too — the last wave is the floor's stated
		# pressure and the opener is two below it, which is the shape every authored
		# floor uses (floor 6 is 5/6/6/7 against a floor cap of 7).
		w.concurrent_cap = clampi(cap - mini(2, n_waves - 1 - i), 2, cap)
		w.archetypes = _ascent_roster(d, i, n_waves, opening)
		w.hp_multiplier = -1.0            # inherit the floor's 1.0. NEVER set here.
		w.brute_chance = -1.0
		w.spawn_interval = -1.0
		w.vanguard = -1
		# Left derived: the handoff threshold is the one wave knob that can put dead
		# air back into a floor, and dead air is what the pacing pass removed.
		w.handoff_alive = -1
		w.elite_wave = (i == elite_idx)
		waves.append(w)

	var f := FloorDef.new()
	f.floor_type = ftype
	f.depth = d
	f.waves = waves
	f.enemy_budget = bodies
	f.concurrent_cap = cap
	f.brute_chance = clampf(0.50 + 0.02 * float(since), 0.50, 0.75)
	f.hp_multiplier = 1.0             # ⚠ THE RULE. Never anything else, at any depth.
	f.boss_hp_multiplier = clampf(2.4 + ASCENT_BOSS_HP_STEP * float(since),
		2.4, ASCENT_BOSS_HP_CAP)
	f.theme = floor_env(d)            # the biome table wraps past ten, by design
	f.layout = default_layout()       # replaced wholesale by FloorGen.generate_layout
	return f


## Split `bodies` across `n` waves as a non-decreasing ramp summing EXACTLY to
## `bodies`. Weighted `6, 7, 8 ...` so the last wave is roughly 1.4x the first — the
## same gentle escalation the authored floors carry (floor 8 is 11/13/15/16).
##
## The remainder lands on the LAST wave, never the first: a rounding crumb belongs on
## the floor's finale, and putting it on the opener would make the ramp start high.
static func _ascent_budgets(bodies: int, n: int) -> Array[int]:
	var out: Array[int] = []
	var waves: int = maxi(n, 1)
	var total_w: int = 0
	for i: int in waves:
		total_w += 6 + i
	var running: int = 0
	for i2: int in waves:
		@warning_ignore("integer_division")
		var share: int = maxi(1, bodies * (6 + i2) / total_w)
		out.append(share)
		running += share
	out[waves - 1] += bodies - running
	# The remainder can only be positive here (integer division floors every share),
	# but a floor whose last wave came back SMALLER than its neighbour would be a
	# difficulty inversion inside one floor, so it is clamped rather than assumed.
	if waves >= 2:
		out[waves - 1] = maxi(out[waves - 1], out[waves - 2])
	return out


## THE MIX for one wave. The headline escalation axis.
##
## Wave 0 fields `opening` classes and the LAST WAVE ALWAYS FIELDS FOUR, so a floor
## escalates inside itself and its finale never drops below the width the spine had
## already reached. What depth moves is `opening` — see the ASCENT_BREADTH block for
## why that is the escalation and the maximum is not.
##
## The rotation is keyed on `(depth + wave)` so two consecutive floors never field the
## same opening pair, and the member of each class is keyed the same way so the tower
## never settles into "the chaser is the pressure class".
##
## The last wave repeats its lead class once. Duplicates in a roster ARE weights (the
## spawn roll is uniform), so that one entry is what stops a four-class finale from
## arriving as one neat helping of each — the argument `FloorGen.give_character` makes.
static func _ascent_roster(depth: int, wave: int, n_waves: int, opening: int) -> Array[int]:
	var out: Array[int] = []
	var span: int = maxi(n_waves - 1, 1)
	@warning_ignore("integer_division")
	var k: int = clampi(opening + (wave * (ASCENT_BREADTH_MAX - opening)) / span,
		opening, ASCENT_BREADTH_MAX)
	var start: int = (depth + wave) % ASCENT_CLASSES.size()
	for c: int in k:
		var cls: Array = ASCENT_CLASSES[(start + c) % ASCENT_CLASSES.size()]
		out.append(int(cls[(depth + wave + c) % cls.size()]))
	if wave == n_waves - 1 and not out.is_empty():
		out.append(out[0])
	return out


static func build_default_tower() -> TowerDef:
	var t := TowerDef.new()
	t.id = "ashspire"
	t.display_name = "The Ashen Tower"
	t.theme = floor_env(1)
	t.floors = [
		# type, brute%, boss hp×, theme, layout, waves [budget, cap, roster]
		#
		# ══ THE EASING IS TAPERED BY DEPTH, AND THAT IS THE WHOLE DECISION ═══════
		# Two playtest notes arrived together and they pull in opposite directions:
		# "its very difficult ... there are too many opponents", and "of course it
		# can get harder as we progress, this difficulty is nicer later up in the
		# tower". Flattening the whole curve would have answered the first and
		# thrown away the second, so instead ONE rule runs down the table:
		#
		#     bodies x min(1.0, 0.6 + 0.1 * (depth - 1))
		#
		# i.e. floor 1 x0.6, floor 2 x0.7, floor 3 x0.8, floor 4 x0.9, and floors
		# 5-10 UNTOUCHED. The result is a STEEPER climb, not a lower one: the
		# opening is gentle and it ramps into the density that already feels right.
		# Concurrent caps come down with it on floors 1-3 only — the cap is what
		# decides how many things are on screen at once, which is the half of "too
		# many opponents" you feel rather than count.
		#
		# ⚠ NOT ONE HP NUMBER MOVED, and this is the prompt that most tempts it.
		# Every floor still runs trash at 1.0: "higher floors add modifiers, not HP.
		# HP scaling makes fights longer, not harder, and long is the enemy of chaos
		# on a phone." Fewer bodies and (in Enemy.gd) softer, slower ones — never
		# spongier ones.
		#
		# --- 1 · SURFACE. THE TEACHING FLOOR: ONE new tell per wave, and never two
		#     new things at once. It opens at cap THREE (not four) because a
		#     first-time player has not yet found the dash, and it closes its last
		#     wave with handoff 0 so the FIRST GUARDIAN THEY EVER MEET arrives to a
		#     clean room — a lesson you can read, not a boss fought through a crowd.
		#     Only TWO archetypes live here; the lane (CHARGER) is floor 2's lesson.
		#
		#     THIS IS THE SECOND CUT TO THIS FLOOR. The first one took wave 1 from
		#     six bodies to four and left the caps alone ("maybe one or two less
		#     opponents in the start"); the complaint came back, so this pass is
		#     bigger and it takes the CAPS too — 3/4/5 became 3/3/4, so the room is
		#     never holding more than four bodies on the floor where the player is
		#     still learning what a tell is. 22 bodies -> 14.
		#
		#     Wave 1 is THREE and not the rule's 2: a pair is not a wave, and the
		#     opener still has to read as one. ---
		_make_floor(FloorDef.FloorType.COMBAT, 0.30, 1.0, floor_env(1), default_layout(),
			_waves([
				[3, 3, [A_CHASER]],                            # pure pressure, nothing to read
				[5, 3, [A_CHASER, A_CHASER, A_BRUTE]],         # ONE new tell: the heavy swing
				[6, 4, [A_CHASER, A_BRUTE], 0],                # the same two, now at pressure
			])),
		# --- 2 · SURFACE. Two lessons, one per wave: the LANE, then RANGE — and only
		#     the last wave asks for both at once. x0.7: 30 bodies -> 21, caps 4/5/6
		#     -> 3/4/5 (its opener still matches floor 1's, which is the ramp). ---
		_make_floor(FloorDef.FloorType.COMBAT, 0.35, 1.15, floor_env(2), default_layout(),
			_waves([
				[5, 3, [A_CHASER, A_CHARGER]],                 # ONE new tell: the lane to dodge
				[7, 4, [A_CHASER, A_CHASER, A_CASTER]],        # something shooting from the back
				[9, 5, [A_CHASER, A_CHARGER, A_CASTER, A_BRUTE]],
			])),
		# --- 3 · ELITE, UNDERGROUND. Fewer bodies, meaner ones. TANKIER is an
		#     archetype (BRUTE), never a multiplier. Ends on two threats at once.
		#     x0.8: 34 -> 27. The caps lose one only where they were highest, so the
		#     floor keeps its "mean, not many" identity. ---
		_make_floor(FloorDef.FloorType.ELITE, 0.55, 1.3, floor_env(3), _elite_layout(),
			_waves([
				[5, 4, [A_BRUTE, A_CHASER]],
				[6, 4, [A_BRUTE, A_CHARGER, A_ASSASSIN]],      # fast + heavy in the same breath
				# THE ELITE WAVE. Floor 3's budget of 1 lands in THESE seven bodies
				# rather than anywhere across the floor's 27 — a 4x concentration, and
				# the wave is already the meanest mix before the finale.
				[7, 5, [A_ASSASSIN, A_ASSASSIN, A_MAGE], -1, true],
				[9, 5, [A_BRUTE, A_CHARGER, A_MAGE, A_SUMMONER]],
			])),
		# --- 4 · UNDERGROUND. The swarm floor: volume plus area denial. x0.9 is the
		#     LAST rung of the taper — 46 -> 42, a nudge rather than a cut — and the
		#     caps are left exactly as authored, because by floor 4 the player has
		#     met every tell floors 1-3 taught and the density is the point. ---
		_make_floor(FloorDef.FloorType.COMBAT, 0.45, 1.45, floor_env(4), default_layout(),
			_waves([
				[8, 5, [A_CHASER, A_ASSASSIN]],
				[10, 6, [A_CHASER, A_CHARGER, A_BOMBER]],      # the floor starts denying you space
				[11, 6, [A_BRUTE, A_CASTER, A_MAGE]],
				[13, 7, [A_CHASER, A_CHARGER, A_ASSASSIN, A_BOMBER, A_MAGE]],
			])),
		# ⚠ FLOORS 5-10 BELOW ARE DELIBERATELY UNTOUCHED by the easing pass. The
		# maker's own words are that the difficulty "is nicer later up in the tower",
		# so the top of the curve is the TARGET the early floors now ramp toward —
		# not a thing to be dragged down with them. They still get the global damage
		# and move-speed cuts from Enemy.gd, which is softening enough.
		# --- 5 · SKY. Everything the tower has, then the colossus. ---
		_make_floor(FloorDef.FloorType.BOSS, 0.70, 1.6, floor_env(5), _boss_layout(),
			_waves([
				[8, 5, [A_CHASER, A_CHARGER]],
				[10, 6, [A_BRUTE, A_CASTER, A_ASSASSIN]],
				[12, 6, [A_CHARGER, A_MAGE, A_BOMBER]],
				[13, 7, [A_BRUTE, A_ASSASSIN, A_MAGE, A_SUMMONER]],
				[15, 7, [A_CHASER, A_BRUTE, A_CHARGER, A_ASSASSIN, A_BOMBER, A_MAGE]],
			])),
		# ══ BAND 2 ══ Checkpoint at floor 6 (DeathRules.CHECKPOINT_BAND). Floors 1-5
		# taught the tower's whole vocabulary and floor 5 proved it; band 2 stops
		# introducing archetypes and starts COMBINING them, which is why every roster
		# below is drawn from what you have already been taught to read.
		#
		# Budgets continue the band-1 curve rather than restarting it, so crossing the
		# checkpoint is a step up and not a fresh start.
		# --- 6 · THE EMBERWORKS. Pressure returns, but everything now arrives in
		#     pairs — the floor asks whether you can fight two things at once as a
		#     baseline rather than as a climax. ---
		_make_floor(FloorDef.FloorType.COMBAT, 0.50, 1.7, floor_env(6), default_layout(),
			_waves([
				[10, 5, [A_CHASER, A_BRUTE]],
				[12, 6, [A_CHARGER, A_CASTER]],
				[14, 6, [A_BRUTE, A_CHARGER, A_BOMBER]],
				[15, 7, [A_CHASER, A_BRUTE, A_CASTER, A_BOMBER]],
			])),
		# --- 7 · GLASSWOOD. The ASSASSIN floor: fast, fragile, and always behind you.
		#     Fewer bodies than 6 on purpose — this one is about attention, not volume. ---
		_make_floor(FloorDef.FloorType.ELITE, 0.40, 1.8, floor_env(7), _elite_layout(),
			_waves([
				[9, 5, [A_ASSASSIN, A_ASSASSIN]],
				[11, 5, [A_ASSASSIN, A_CHARGER, A_MAGE]],
				[13, 6, [A_ASSASSIN, A_ASSASSIN, A_SUMMONER], -1, true],  # THE ELITE WAVE
				[14, 6, [A_ASSASSIN, A_CHARGER, A_MAGE, A_SUMMONER]],
			])),
		# --- 8 · THE DROWNED GALLERY. Area denial: the floor takes space away from you
		#     and the fight becomes about where you are allowed to stand. ---
		_make_floor(FloorDef.FloorType.COMBAT, 0.50, 1.9, floor_env(8), default_layout(),
			_waves([
				[11, 6, [A_BOMBER, A_CHASER]],
				[13, 6, [A_BOMBER, A_MAGE, A_BRUTE]],
				[15, 7, [A_CASTER, A_MAGE, A_BOMBER]],
				[16, 7, [A_BRUTE, A_BOMBER, A_MAGE, A_CHARGER]],
			])),
		# --- 9 · STORMREACH. The last ordinary floor, and the densest: everything the
		#     tower has, at volume, with no new lesson to spare attention for. ---
		_make_floor(FloorDef.FloorType.ELITE, 0.60, 2.0, floor_env(9), _elite_layout(),
			_waves([
				[13, 6, [A_CHASER, A_CHARGER, A_ASSASSIN]],
				[15, 7, [A_BRUTE, A_CASTER, A_BOMBER]],
				[16, 7, [A_ASSASSIN, A_MAGE, A_SUMMONER], -1, true],      # THE ELITE WAVE
				[18, 8, [A_CHASER, A_BRUTE, A_CHARGER, A_ASSASSIN, A_MAGE]],
			])),
		# --- 10 · THE APEX. The tower's roof and its last guardian. Ends on every
		#      archetype at once — the same shape floor 5 used, at the top of the curve. ---
		_make_floor(FloorDef.FloorType.BOSS, 0.70, 2.4, floor_env(10), _boss_layout(),
			_waves([
				[12, 6, [A_CHASER, A_CHARGER]],
				[14, 7, [A_BRUTE, A_CASTER, A_ASSASSIN]],
				[16, 7, [A_CHARGER, A_MAGE, A_BOMBER]],
				[17, 8, [A_BRUTE, A_ASSASSIN, A_MAGE, A_SUMMONER]],
				[19, 8, [A_CHASER, A_BRUTE, A_CHARGER, A_ASSASSIN, A_BOMBER, A_MAGE]],
			])),
	]
	# Applied here rather than through `_make_floor` because it is a property of the
	# first few floors specifically, not of a floor TYPE — see EARLY_WAVE_BREAKS.
	for i: int in mini(EARLY_WAVE_BREAKS.size(), t.floors.size()):
		t.floors[i].wave_break = EARLY_WAVE_BREAKS[i]
	return stamp_depths(t)


## Build a wave list from [budget, concurrent_cap], [budget, cap, archetypes] or
## [budget, cap, archetypes, handoff_alive] rows. HP is left inheriting the
## floor's (1.0) on purpose — the authored table is about PACING and COMPOSITION,
## which are the things that have to be tuned by feel; a wave that wants to be
## harder says so by naming nastier archetypes.
##
## The 4th column is the OVERLAP, and it exists for exactly one row today: floor
## 1's last wave sets it to 0 so the tower's first guardian arrives to an empty
## room. Everywhere else it is left at -1 (derive from the cap), because the
## overlap is what keeps a floor's pressure from ever hitting zero and undoing it
## wholesale would put the dead air back.
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
		if row.size() > 3:
			w.handoff_alive = int(row[3])
		# 5th column: THE ELITE WAVE. The floor's whole elite budget spends inside
		# THIS wave instead of being sprinkled across every body on the floor — see
		# `WaveDef.elite_wave`. It is a PACING flag on a wave that already exists,
		# not a new wave: the tower holds two invariants that a short inserted wave
		# would break (budgets never shrink across a floor, and exactly ONE wave in
		# the whole tower may hand off at 0). So this concentrates, it does not stage.
		if row.size() > 4:
			w.elite_wave = bool(row[4])
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
## ⚠ ONE BIOME PER FLOOR — the whole tower's visual identity, in one table.
##
## This replaced a THREE-value band lookup (surface / underground / sky) where nine
## of ten floors shared a colour with a neighbour. Maker: "I want more diversity on
## the floors like a snow place background a sunny green one like a red room".
##
## `light` is the exposure, and the register is DELIBERATELY DIM — but per-floor, not
## uniformly. A tower that is dark everywhere has no shape; the point of Frostmarch
## at 1.05 and the Sunken Vault at 0.68 is that the climb gets DARKER and you can
## feel it, with a bright floor between two black ones so the descent reads. Each
## floor keeps its own saturated hue and only the exposure moves, which is also what
## makes a spell read as a real light source.
##
## Ten entries for a ten-floor tower. `floor_for_index` wraps, so a tower that grows
## past this table repeats biomes rather than falling off the end.
## `wx` is the floor's AIR (`EnvTheme.Weather`) — what falls, drifts or rises through
## it. Paired with the hue rather than chosen freely: ash over the ash verge, leaves
## over the green tier, embers RISING out of the two hot rooms, bubbles rising in the
## drowned one. The two rooms that get GLINT (Sunken Vault, Glasswood) are the two
## the register calls still and enclosed, so their air hangs rather than travels.
const BIOMES: Array = [
	{"n": "Ashfall Verge",       "w": Color(0.20, 0.18, 0.19), "a": Color(0.85, 0.55, 0.35), "l": 0.86, "wx": EnvTheme.Weather.ASH},
	{"n": "Verdant Tier",        "w": Color(0.24, 0.34, 0.20), "a": Color(0.80, 0.95, 0.45), "l": 1.12, "wx": EnvTheme.Weather.LEAVES, "sky": EnvTheme.SkyKind.SUNSET},
	{"n": "Frostmarch",          "w": Color(0.30, 0.36, 0.44), "a": Color(0.85, 0.95, 1.00), "l": 1.05, "wx": EnvTheme.Weather.SNOW, "sky": EnvTheme.SkyKind.SUNSET},
	{"n": "The Crimson Room",    "w": Color(0.28, 0.10, 0.12), "a": Color(1.00, 0.35, 0.35), "l": 0.80, "wx": EnvTheme.Weather.EMBERS},
	{"n": "The Sunken Vault",    "w": Color(0.14, 0.15, 0.22), "a": Color(0.55, 0.80, 0.90), "l": 0.68, "wx": EnvTheme.Weather.GLINT},
	{"n": "The Emberworks",      "w": Color(0.28, 0.16, 0.10), "a": Color(1.00, 0.60, 0.25), "l": 0.92, "wx": EnvTheme.Weather.EMBERS},
	{"n": "Glasswood",           "w": Color(0.26, 0.28, 0.32), "a": Color(0.90, 0.85, 1.00), "l": 0.98, "wx": EnvTheme.Weather.GLINT},
	{"n": "The Drowned Gallery", "w": Color(0.10, 0.24, 0.26), "a": Color(0.40, 0.90, 0.90), "l": 0.74, "wx": EnvTheme.Weather.BUBBLES},
	{"n": "Stormreach",          "w": Color(0.20, 0.16, 0.32), "a": Color(0.75, 0.70, 1.00), "l": 0.84, "wx": EnvTheme.Weather.RAIN},
	{"n": "The Apex",            "w": Color(0.30, 0.28, 0.22), "a": Color(1.00, 0.92, 0.65), "l": 1.18, "wx": EnvTheme.Weather.STARFALL, "sky": EnvTheme.SkyKind.ECLIPSE},
]


## The biome row for a floor, wrapping past the end of the table.
static func biome_for(floor: int) -> Dictionary:
	if BIOMES.is_empty():
		return {"n": "surface", "w": Color(0.20, 0.28, 0.22), "a": Color(0, 0, 0, 0), "l": 1.0}
	var i: int = (maxi(floor, 1) - 1) % BIOMES.size()
	return BIOMES[i]


static func floor_theme(floor: int) -> String:
	return String(biome_for(floor)["n"])


## Ambient floor tint for the theme (drives the arena's "which layer" read).
static func floor_theme_tint(floor: int) -> Color:
	return biome_for(floor)["w"]


## The floor's full environment identity. One builder, used by both the authored
## tower and the synthesized fallback, so a floor cannot look different depending on
## which of the two produced it.
static func floor_env(floor: int) -> EnvTheme:
	var row: Dictionary = biome_for(floor)
	var e := EnvTheme.new()
	e.name = String(row["n"])
	e.wash_tint = row["w"]
	e.accent_tint = row["a"]
	e.light = float(row["l"])
	e.weather = int(row.get("wx", EnvTheme.Weather.NONE))
	e.sky = int(row.get("sky", EnvTheme.SkyKind.NONE))
	return e
