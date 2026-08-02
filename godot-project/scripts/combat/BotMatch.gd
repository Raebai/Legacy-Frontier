class_name BotMatch
extends Node2D
## BOT vs BOT, WATCHABLE — and now a MATCH rather than an exhibition.
##
## The maker's note, verbatim, after watching it: *"yo the whole watch bots thing is
## awesome — like it needs them to start equal and the camera needs to follow it
## cinematically please so the audience can see it all all the time. make sure its
## good like video quality and the sound effects need to be improved please. and of
## course they need health bars, and to move around so that they can die and the
## watch can end. but give them health etc based on their characters, who they are,
## damage types"*.
##
## ---------------------------------------------------------------------------
## ⚠ WHY THE FIGHT NEVER ENDED. Three independent reasons, all of them measured by
## reading the code they live in, and all three had to be fixed for a bout to resolve:
##
##   1. THE RING-OUT MODEL WAS ON. `VersusArena.showcase_ringout` defaults to TRUE
##      and this scene never set it, so `Hero.take_damage` piled onto `damage_pct`
##      and NEVER DRAINED HP. Nothing that watches HP could ever see a knockdown.
##   2. HP DEATH SELF-HEALS. Turning the ring-out model off is not enough. Outside a
##      run and outside a net session, `Hero._die()` runs `hp = max_hp` IN THE SAME
##      CALL as the fatal hit. So HP never rests at zero for even one frame, and
##      `VersusArena._poll_showcase_end` / `ClipDirector._check_knockdown` — which
##      both poll `hp <= 0` once a frame — can never fire. The fighters on this stage
##      were, literally, immortal. The signal `health_changed` DOES report `hp == 0`,
##      because `take_damage` emits it before calling `_die`; that is the only honest
##      hook, and it is what this file listens to.
##   3. THERE WAS NO TERMINAL STATE ANYWHERE. `_poll_showcase_end` deliberately
##      RESETS the bout (it is a sparring loop, by design, so the clip camera keeps
##      rolling), and a stock-out routes to `_restock`, which refills both sides and
##      carries on. Even a working knockdown would only have started the next round.
##      Nothing in the scene could ever say "this one is over".
##
## So the match spine lives HERE: this node holds the win condition, the round clock
## and the result beat, and `VersusArena` stays exactly the exhibition stage it is.
##
## ---------------------------------------------------------------------------
## EQUAL FOOTING, CHARACTERFUL STATS — the two halves of the maker's ask, which pull
## against each other, resolved as:
##
##   FOOTING is mirrored and identical. Both fighters spawn the same distance from
##   the centre of the fight floor, on the same flat ground, facing each other, at
##   the same bot tier, on the same clock, with the same cooldowns. Neither side is
##   handed an opening advantage of any kind, and because this stage is NOT
##   left-right symmetric (the terraces and the bluff are all on the right), the
##   sides SWAP on every rematch so nothing the map gives away accrues to one class.
##
##   STATS are not identical, because a Juggernaut with an Arcanist's health is not a
##   Juggernaut. `CLASS_VITALITY` scales the shared HP pool by who the fighter IS.
##   It is a multiplier on ONE shared number, so the knob stays a match-length knob:
##   change `fighter_hp` and every matchup scales together.
##
## ⚠ AND THAT IS THE WHOLE OF IT. Nothing here touches damage, cooldowns, reaction
## time, error rate or what a bot can see. Both fighters get the same stock
## `BotController` + `BotBrain` + `BotProfile` the game ships. If a matchup is
## lopsided that is a BALANCE FINDING to report — `tools/botmatch_sim.gd` measures it
## — and never something to paper over with a handicap. A clip of a rigged fight is
## worthless for finding bugs and dishonest as marketing.
##
## ⚠ CLASS_VITALITY IS LOCAL TO THIS MODE. It is applied to the two bodies this scene
## stands up, after the arena has built them. It does not touch the tower, the duel,
## free play or the class definitions — per-class vitality does not exist as a real
## stat anywhere in this project yet, and inventing one inside a spectator mode would
## be the wrong place to put it.

const ARENA_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"
const BOT_MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
## LEAVING GOES TO THE TITLE, NOT THE HUB.
##
## This used to be `res://scenes/Main.tscn` — the parked v0.0 AI-NPC town, which
## the design doc cuts permanently and which cannot work on a phone at all (its
## NPCs talk to a hardcoded Ollama at 127.0.0.1). The run spine was moved off it,
## but every SANDBOX exit still pointed there, so backing out of a bot match
## dropped you into a different game's village with nothing to do in it. The maker
## found it immediately and asked why it was there.
##
## The Lobby is the boot scene, works on a phone, and is where every other exit in
## the game now lands. The hub stays on disk and stays reachable as an opt-in
## detour from the run-summary card; it is simply not somewhere you arrive by
## accident.
const HUB_SCENE: String = "res://scenes/ui/Lobby.tscn"

const CLASS_LABELS: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]
const TIER_LABELS: Array[String] = ["Easy", "Normal", "Hard", "Impossible"]

## Per-class tint, for the name plates. Read from `ClassInfo` rather than restated,
## so a class recoloured on the select screen is recoloured here too.
const FALLBACK_TINT: Color = Color(0.85, 0.88, 0.95)

## WHO THEY ARE, as a multiplier on the shared HP pool. Ordered like CLASS_LABELS.
##
## Derived from each class's own fantasy line in `ClassInfo.CLASSES` and its kit in
## `Hero.CLASS_CONFIG` — a tank that trades melee range for a block is supposed to
## outlast a zoner that never wants to be touched, and a pure-melee class that has to
## cross the whole stage to do anything is supposed to survive the crossing.
##
## ⚠ THE BRAWLER NUMBER IS DELIBERATE AND IT IS NOT A HANDICAP. The bot sim measures
## the Brawler winning 14% at Normal — the pure-melee class is the one most hurt by
## the reflex layer working, because everything it does requires being in range. The
## fix for that is its KIT, not its health bar, and that is another agent's file. The
## 1.15 here is what its own class card already promises ("knockout" bruiser) and it
## is applied before any fight is run, not tuned until it wins.
const CLASS_VITALITY: Array[float] = [
	0.90,  # ARCANIST     — ranged arcane zoner; never wants to be touched
	0.85,  # SHADOWBLADE  — in-and-out assassin; the glass in glass cannon
	1.15,  # BRAWLER      — pure melee, no magic; has to cross the stage to exist
	1.35,  # JUGGERNAUT   — unbreakable siege tank; the whole fantasy is not dying
	1.05,  # CLERIC       — radiant bruiser, and already sustains through lifesteal
	0.92,  # CRYOMANCER   — control caster; wins on spacing, not on absorbing
	0.88,  # STORMCALLER  — hyper-mobile; pays for the mobility
	0.95,  # WARLOCK      — attrition hexer; wins long fights, not short trades
	1.00,  # SWORDSAINT   — the duelist baseline; guard-and-punish, no ailment
]

## STATICS, and they survive the scene reload every matchup change performs. A
## member would reset to its default on the first change and the maker would never
## be able to leave the opening pairing — the same reason `VersusArena`'s duel knobs
## are statics.
static var class_a: int = 6      # STORMCALLER
static var class_b: int = 5      # CRYOMANCER
static var difficulty: int = 3   # the tier that plays the whole kit (combo 0.90)
## Lower than the showcase's own 320 on purpose: a clip needs the fight to END.
## Scaled per fighter by CLASS_VITALITY.
static var fighter_hp: int = 190
## Which side each class starts on. Flipped on every rematch so the stage's own
## left/right asymmetry cannot accrue to one class over a series. See the footing
## note at the top of this file.
static var swap_sides: bool = false
## Roll straight into the next bout after the result card. TRUE for the maker
## watching (it becomes a highlight reel); a capture tool turns it OFF so the clip
## ends where the match does.
static var auto_rematch: bool = true

## ------------------------------------------------------------------ MATCH RULES
## Where the two fighters stand, as a distance either side of the CENTRE OF THE FIGHT
## FLOOR. `VersusArena`'s own showcase spawns are 520 / 1080, whose midpoint is 800 —
## 80 px right of the flat ground's actual centre, so one fighter started nearer the
## stairs than the other did the mound. Mirrored about the real centre instead.
const FLOOR_CENTRE_X: float = 720.0     # (40 + 1400) / 2, the main walkable ground
const SPAWN_SPREAD: float = 280.0       # same 560 px gap the showcase always used
const SPAWN_Y: float = 716.0
## Off the rock entirely — a fall nothing recovers from. The terrain spans x 40..1965
## (VersusArena.TERRACES), so anything outside this is in the air over a blast zone.
const RIM_LEFT: float = 24.0
const RIM_RIGHT: float = 1980.0
## Nobody watches a stalemate. If neither fighter has gone down by here the match is
## decided on the health bars, which is a real result and not a cop-out: the fighter
## who took less punishment over 50 seconds won the fight the audience watched.
##
## A STATIC rather than a const so `tools/botmatch_sim.gd` can run a shorter round
## without editing the number the maker watches. GAME seconds, so hit-stop stretches
## the wall clock but never the fight.
static var round_seconds: float = 50.0
## How close two health fractions have to be before a timeout is called a DRAW
## rather than a decision.
const DRAW_MARGIN: float = 0.04
## Real seconds the frozen KO frame holds before the result card slams in.
const FREEZE_BEAT: float = 0.55
## ...and how long the card holds before the next bout, when `auto_rematch` is on.
const RESULT_HOLD: float = 4.2

enum Outcome { NONE, KO, RINGOUT, DECISION, DRAW }

var _arena: Node2D = null
var _readout: Label = null
var _labels: Dictionary = {}

## ---- the two fighters, in side order (0 = left, 1 = right) -----------------
var _fighters: Array[Node2D] = []
var _fighter_class: Array[int] = [-1, -1]
var _fighter_max: Array[int] = [1, 1]
var _fighter_hp_now: Array[int] = [1, 1]
## Latched at the decisive beat, so the plates show the KO state and not the value
## `Hero._die` heals it back to a microsecond later.
var _final_hp: Array[int] = [-1, -1]

## ---- match state ----------------------------------------------------------
var _clock: float = 0.0
var _outcome: int = Outcome.NONE
var _winner: int = -1                 # side index, or -1 for a draw
var _decided_at: float = -1.0         # REAL seconds (unscaled) when it was decided
var _frozen: bool = false
var _result_card: Control = null
var _plates: Array[Dictionary] = []
var _clock_label: Label = null
var _music_band: int = -1


## The one-line hook, for a Lobby button or a dev menu:
##     BotMatch.enter(get_tree())
static func enter(tree: SceneTree) -> void:
	tree.paused = false
	tree.change_scene_to_file(BOT_MATCH_SCENE)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Statics BEFORE the scene instantiates — `VersusArena._ready` reads them all.
	# Reached BY PATH, never by `class_name`, for the autoload-at-parse-time reason
	# every capture tool in this project documents.
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script != null:
		arena_script.set("free_play", false)
		arena_script.set("showcase_a", _left_class())
		arena_script.set("showcase_b", _right_class())
		arena_script.set("showcase_difficulty", clampi(difficulty, 0, 3))
		arena_script.set("showcase_directed", true)
		arena_script.set("showcase_hp_override", fighter_hp)
		# ⚠ REASON 1 THAT FIGHTS NEVER ENDED. This static defaults to TRUE and this
		# scene never set it, so hits piled onto `damage_pct` and HP never moved. A
		# watch that cannot end is not a watch. HP death is the model that resolves.
		arena_script.set("showcase_ringout", false)
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(_arena)
	_adopt_fighters()
	_hide_duplicate_chrome()
	_build_overlay()
	_extend_pause_menu()
	_open_bout()


## ⚠ CLEAR THE SHOWCASE STATICS ON THE WAY OUT. They outlive this node, this scene
## and the scene change that leaves it — so walking from a bot match into the versus
## duel would hand the duel two bots and no player, with the cause two scenes back.
## `showcase_ringout` is restored to its shipped TRUE for the same reason in reverse:
## the played sandbox is a Smash stage and is supposed to be.
func _exit_tree() -> void:
	# ...and NEVER leave the tree paused. `_freeze` pauses on the decisive beat; a
	# scene change out of a frozen result card would otherwise hand the Lobby a
	# paused tree, which reads as the game having hung.
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	_set_rank_hud(true)   # the autoload outlives this scene; see _hide_duplicate_chrome
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script == null:
		return
	arena_script.set("showcase_a", -1)
	arena_script.set("showcase_b", -1)
	arena_script.set("showcase_directed", false)
	arena_script.set("showcase_hp_override", 0)
	arena_script.set("showcase_ringout", true)


# ==========================================================================
# THE FIGHTERS — footing, stats, and the only honest death signal on this stage
# ==========================================================================

func _left_class() -> int:
	var a: int = clampi(class_a, 0, CLASS_LABELS.size() - 1)
	var b: int = clampi(class_b, 0, CLASS_LABELS.size() - 1)
	return b if swap_sides else a


func _right_class() -> int:
	var a: int = clampi(class_a, 0, CLASS_LABELS.size() - 1)
	var b: int = clampi(class_b, 0, CLASS_LABELS.size() - 1)
	return a if swap_sides else b


## Take the two bodies the arena built, put them on mirrored footing, give them the
## health their class earns, and subscribe to the one signal that can see a death.
##
## The arena spawns fighter A first, so tree order IS side order.
func _adopt_fighters() -> void:
	_fighters.clear()
	for n: Node in get_tree().get_nodes_in_group(&"hero"):
		if n is Node2D and is_instance_valid(n):
			_fighters.append(n as Node2D)
	if _fighters.size() != 2:
		return
	_fighter_class[0] = _left_class()
	_fighter_class[1] = _right_class()
	for side: int in 2:
		var f: Node2D = _fighters[side]
		var hp: int = _vital_hp(_fighter_class[side])
		f.set("max_hp", hp)
		f.set("hp", hp)
		_fighter_max[side] = hp
		_fighter_hp_now[side] = hp
		# MIRRORED FOOTING. Same distance from the centre of the fight floor, same
		# flat ground, facing each other.
		var x: float = FLOOR_CENTRE_X + (SPAWN_SPREAD if side == 1 else -SPAWN_SPREAD)
		f.global_position = Vector2(x, SPAWN_Y)
		f.set("facing", Vector2.RIGHT if side == 0 else Vector2.LEFT)
		_reseat_registry(f)
		# ⚠ THE ONLY DEATH SIGNAL THAT WORKS HERE. See reason 2 at the top of the
		# file: `Hero.take_damage` emits `health_changed(0, max)` and only THEN calls
		# `_die`, which heals straight back to full. Polling `hp` misses it every
		# time; the signal does not.
		if f.has_signal("health_changed"):
			f.connect("health_changed", _on_health_changed.bind(side))


## HP for a class: the shared pool, scaled by who they are. Never below 40, so a
## short-clip HP setting cannot make a squishy class die to one stray bolt.
func _vital_hp(class_id: int) -> int:
	var mult: float = 1.0
	if class_id >= 0 and class_id < CLASS_VITALITY.size():
		mult = CLASS_VITALITY[class_id]
	return maxi(int(round(float(fighter_hp) * mult)), 40)


## Tell the arena's ring-out registry where this fighter now lives, so a respawn
## puts it back on the mirrored footing rather than on the arena's own spawn point.
##
## `_registry` is a plain member on `VersusArena`; this reads and rewrites one field
## of one row and touches nothing else. A private read is the smaller evil than a
## fighter respawning 80 px off its opponent's mirror.
func _reseat_registry(f: Node2D) -> void:
	if _arena == null:
		return
	var reg: Variant = _arena.get("_registry")
	if not (reg is Dictionary):
		return
	var row: Variant = (reg as Dictionary).get(f.get_instance_id())
	if row is Dictionary:
		(row as Dictionary)["spawn"] = f.global_position


## The death hook. `hp == 0` here is the fatal frame, before `Hero._die` heals it.
func _on_health_changed(hp: int, _max_hp: int, side: int) -> void:
	if side < 0 or side > 1:
		return
	_fighter_hp_now[side] = hp
	if hp <= 0 and _outcome == Outcome.NONE:
		_decide(Outcome.KO, 1 - side)


# ==========================================================================
# THE MATCH
# ==========================================================================

func _open_bout() -> void:
	_clock = 0.0
	_outcome = Outcome.NONE
	_winner = -1
	_decided_at = -1.0
	_frozen = false
	_final_hp[0] = -1
	_final_hp[1] = -1
	_play("ding", 0.0)


func _process(delta: float) -> void:
	_tick_readout()
	if _outcome != Outcome.NONE:
		_tick_result(delta)
		_paint_hud()
		return
	_clock += delta
	_sample_fighters()
	_check_rimout()
	_check_timeout()
	_drive_music()
	_paint_hud()


## Poll HP for the BARS only. It is not a death check — see reason 2 at the top.
func _sample_fighters() -> void:
	for side: int in _fighters.size():
		var f: Node2D = _fighters[side]
		if is_instance_valid(f):
			_fighter_hp_now[side] = int(f.get("hp"))


## A fighter off the rock is falling into a blast zone and is not coming back.
##
## Detected by POSITION rather than by the arena's pit signal, because the pit
## routes to `_on_fighter_fell`, which burns a stock and respawns — i.e. by the time
## the arena has an opinion the fighter is already back on its feet at full health,
## and the most watchable event this game has has been erased.
func _check_rimout() -> void:
	for side: int in _fighters.size():
		var f: Node2D = _fighters[side]
		if not is_instance_valid(f):
			continue
		var x: float = f.global_position.x
		if x < RIM_LEFT or x > RIM_RIGHT:
			_decide(Outcome.RINGOUT, 1 - side)
			return


## Nobody watches a stalemate. On the clock, the healthier fighter takes it.
func _check_timeout() -> void:
	if _clock < round_seconds:
		return
	var a: float = _hp_frac(0)
	var b: float = _hp_frac(1)
	if absf(a - b) <= DRAW_MARGIN:
		_decide(Outcome.DRAW, -1)
	else:
		_decide(Outcome.DECISION, 0 if a > b else 1)


func _hp_frac(side: int) -> float:
	if side < 0 or side >= _fighter_hp_now.size():
		return 0.0
	return clampf(float(_fighter_hp_now[side]) / maxf(float(_fighter_max[side]), 1.0), 0.0, 1.0)


## THE RESULT BEAT. Freeze on the killing frame, hold it, slam the card in.
##
## The freeze is a real tree pause, and it is what STOPS THE ARENA FROM ERASING THE
## ENDING: `VersusArena._process` early-outs while paused, so its sparring-loop reset
## (which would teleport both fighters back to their spawns at full health, on the
## very frame the fight was won) never runs. `_match_over` is latched on the arena as
## well, so the reset stays dead even if something unpauses.
##
## The `ClipDirector` keeps ticking through the pause — it inherits PROCESS_MODE
## ALWAYS from the arena — so the camera settles onto the KO instead of stopping dead
## with it. That settle IS the shot.
func _decide(outcome: int, winner: int) -> void:
	if _outcome != Outcome.NONE:
		return
	_outcome = outcome
	_winner = winner
	_decided_at = _real_seconds()
	_final_hp[0] = _fighter_hp_now[0]
	_final_hp[1] = _fighter_hp_now[1]
	if outcome == Outcome.KO and winner >= 0:
		_final_hp[1 - winner] = 0
	elif outcome == Outcome.RINGOUT and winner >= 0:
		_final_hp[1 - winner] = 0
	# Tell the camera operator where to look. It cannot see this itself — see the
	# note on `ClipDirector.note_knockdown`.
	var d: Object = _director()
	if d != null:
		var loser: int = -1 if winner < 0 else 1 - winner
		var at: Vector2 = Vector2.INF
		if loser >= 0 and loser < _fighters.size() and is_instance_valid(_fighters[loser]):
			at = _fighters[loser].global_position
		if outcome == Outcome.RINGOUT and d.has_method("note_ringout"):
			d.call("note_ringout", at)
		elif d.has_method("note_knockdown"):
			d.call("note_knockdown", at, _outcome_word())
	_freeze()
	_sting()


func _freeze() -> void:
	if _frozen:
		return
	_frozen = true
	if _arena != null:
		_arena.set("_match_over", true)
	get_tree().paused = true


## Real (unscaled) seconds. The result beat must not stretch when hit-stop drops
## `Engine.time_scale` to 0.05 on the very hit that ended the fight — which is
## exactly when it would, since that hit is a kill.
func _real_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _tick_result(_delta: float) -> void:
	var age: float = _real_seconds() - _decided_at
	if _result_card != null and not _result_card.visible and age >= FREEZE_BEAT:
		_show_result_card()
	if auto_rematch and age >= RESULT_HOLD:
		_reload()


func _outcome_word() -> String:
	match _outcome:
		Outcome.KO: return "KO"
		Outcome.RINGOUT: return "RING-OUT"
		Outcome.DECISION: return "DECISION"
		Outcome.DRAW: return "DRAW"
	return ""


## The machine-readable result, for a capture tool's manifest and for the sim.
func result() -> Dictionary:
	return {
		"outcome": _outcome_word(),
		"over": _outcome != Outcome.NONE,
		"winner_side": _winner,
		"winner": "" if _winner < 0 else _label(_fighter_class[_winner]),
		"loser": "" if _winner < 0 else _label(_fighter_class[1 - _winner]),
		"left": _label(_fighter_class[0]), "right": _label(_fighter_class[1]),
		"left_hp": _final_hp[0] if _final_hp[0] >= 0 else _fighter_hp_now[0],
		"right_hp": _final_hp[1] if _final_hp[1] >= 0 else _fighter_hp_now[1],
		"left_max": _fighter_max[0], "right_max": _fighter_max[1],
		"seconds": snappedf(_clock, 0.01),
		"tier": _tier(),
	}


func match_over() -> bool:
	return _outcome != Outcome.NONE


# ==========================================================================
# SOUND
#
# ⚠ WHAT THIS FILE CAN AND CANNOT DO ABOUT THE MAKER'S "the sound effects need to be
# improved". The 248-key roster, its per-key trims, its weight classes and its
# ducking rules all live in `Sfx.gd`, which this agent does not own. What a match
# CAN do from here is the structural half that was simply absent: the fight had no
# audio punctuation at all — no bell, no stinger on the decisive hit, and a music bed
# that sat at one level whether the fighters were circling or trading ults.
# ==========================================================================

## The bell, the stinger, and the card. Weighted so the KO reads as the loudest
## thing in the clip.
func _sting() -> void:
	match _outcome:
		Outcome.KO:
			_play("enemy_death_big", 2.0)
			_play("sub_boom", 0.0, 0.05)
		Outcome.RINGOUT:
			_play("body_fall", 2.0)
			_play("sub_boom", -2.0, 0.06)
		_:
			_play("ding", 1.0)


## Music intensity follows the director's heat, in BANDS rather than continuously.
## `Music.set_intensity` re-arms a tween on every distinct value, so driving it from
## a per-frame float would rebuild a tween sixty times a second and the bed would
## never actually get anywhere.
func _drive_music() -> void:
	var d: Object = _director()
	if d == null:
		return
	var band: int = clampi(int(float(d.call("heat")) * 4.0), 0, 3)
	if band == _music_band:
		return
	_music_band = band
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("set_intensity"):
		music.call("set_intensity", float(band) / 3.0)


## Guarded, because this scene is instantiated by headless harnesses that have no
## `Sfx` autoload and a hard reference would abort the calling function.
func _play(key: String, db: float = 0.0, delay: float = 0.0) -> void:
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		# (key, volume_db, pitch_variation, pitch_base, delay) — the last two are
		# easy to transpose, and transposing them re-pitches the sample instead of
		# spacing the beat.
		sfx.call("play", key, db, 0.06, 1.0, delay)


# ==========================================================================
# THE HUD — health bars that read at 640x360 without covering the fight
#
# ⚠ `CharacterBars` IS NOT THE COMPONENT FOR THIS, and it was checked before this was
# written. It is a 30 px floating bar parented to the fighter (Hero.gd:977 and
# Enemy.gd:919 both add one), so at the clip camera's zoom it renders about 15 screen
# pixels wide, under the fighter's own spell glow, and it moves with the body — the
# audience cannot track a number that is walking around the frame. It stays exactly
# as it is and keeps doing its job in the tower. What a MATCH needs is a fighting
# game's plates: fixed, screen-space, top corners, out of the fight's way. (Note in
# passing: `CharacterBars.configure(show_mp)` defaults false and no caller in the
# project has ever passed true, so the MP half of that component is dead code.)
# ==========================================================================

const PLATE_W: float = 232.0
const PLATE_H: float = 10.0
const PLATE_MARGIN: float = 14.0
const PLATE_TOP: float = 12.0
const PLATE_BG: Color = Color(0.05, 0.06, 0.10, 0.80)
const PLATE_EDGE: Color = Color(0.0, 0.0, 0.0, 0.65)
const HP_FULL: Color = Color(0.36, 0.88, 0.42)
const HP_MID: Color = Color(0.96, 0.83, 0.24)
const HP_LOW: Color = Color(0.94, 0.26, 0.22)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	for side: int in 2:
		_plates.append(_build_plate(layer, side))
	_clock_label = _make_label(layer, 13, Color(0.92, 0.95, 1.0, 0.92))
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_clock_label.offset_top = PLATE_TOP - 2.0
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_result_card(layer)
	# The director's own opinion, over the fight it is filming. This is the thing that
	# turns "watch two bots" into "tune the clip engine": if the heat number sits at
	# 0.05 through an exchange, the camera opens late and the thresholds are wrong.
	_readout = _make_label(layer, 11, Color(0.86, 0.92, 1.0, 0.75))
	_readout.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_readout.offset_left = 12.0
	_readout.offset_top = -22.0


## One fighter's plate: a name, a class-tinted flash, and a bar that DRAINS TOWARD
## THE CENTRE of the screen, so the two bars read as one contest rather than as two
## unrelated meters.
func _build_plate(layer: CanvasLayer, side: int) -> Dictionary:
	var draw := _PlateDraw.new()
	draw.side = side
	draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(draw)
	# The name sits ON TOP of the bar's layer, added after it, so the outline is not
	# buried under the plate's own background.
	var name_label: Label = _make_label(layer, 12, Color(0.95, 0.97, 1.0))
	name_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	return {"name": name_label, "draw": draw}


## ⚠ THREE HUDS WERE STACKED ON THE SAME 40 PIXELS, and the first captured frame is
## how it was found: the arena's own "STORMCALLER vs CRYOMANCER" card, the `Rank`
## autoload's "Nameless · Tier 0" title, and this file's plates and clock, all drawn
## over each other in the top strip. Unreadable, and it is the first thing an audience
## sees.
##
## The plates say everything the arena's card said and more, so the card goes; the
## rank title belongs to a RUN and this is a spectator mode, so it goes too. Both are
## hidden at RUNTIME rather than edited out of their own files — the arena is still an
## exhibition stage when something else drives it, and `Rank`'s HUD is an autoload
## that outlives this scene, which is why `_exit_tree` puts it back.
func _hide_duplicate_chrome() -> void:
	if _arena != null:
		for layer: Node in _arena.get_children():
			if not (layer is CanvasLayer):
				continue
			# DIRECT children only. The pause overlay's own labels are nested inside
			# a panel, and blanking those would empty the menu.
			for ctl: Node in layer.get_children():
				if ctl is Label:
					(ctl as Label).visible = false
	_set_rank_hud(false)


func _set_rank_hud(shown: bool) -> void:
	var rank: Node = get_node_or_null("/root/Rank")
	if rank == null:
		return
	var label: Variant = rank.get("_hud_label")
	if label is Label and is_instance_valid(label):
		(label as Label).visible = shown


func _make_label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.07, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_result_card(layer: CanvasLayer) -> void:
	_result_card = Control.new()
	_result_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_card.visible = false
	layer.add_child(_result_card)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_card.add_child(dim)
	var head := _make_label(_result_card, 30, Color(1.0, 0.97, 0.86))
	head.name = "Head"
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 132.0
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _make_label(_result_card, 13, Color(0.86, 0.90, 1.0, 0.9))
	sub.name = "Sub"
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 172.0
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _show_result_card() -> void:
	if _result_card == null:
		return
	var head: Label = _result_card.get_node_or_null("Head") as Label
	var sub: Label = _result_card.get_node_or_null("Sub") as Label
	if head != null:
		head.text = "DRAW" if _winner < 0 else "%s WINS" % _label(_fighter_class[_winner])
		head.add_theme_color_override("font_color",
			Color(0.92, 0.94, 1.0) if _winner < 0 else _tint(_fighter_class[_winner]))
	if sub != null:
		var lhp: int = _final_hp[0] if _final_hp[0] >= 0 else _fighter_hp_now[0]
		var rhp: int = _final_hp[1] if _final_hp[1] >= 0 else _fighter_hp_now[1]
		sub.text = "%s  ·  %.1fs  ·  %d — %d" % [_outcome_word(), _clock, lhp, rhp]
	_result_card.visible = true
	_play("holy_swell", -1.0)


## Push the current numbers into the plates. Poll-don't-push (the AbilityBar idiom).
func _paint_hud() -> void:
	if _plates.size() != 2:
		return
	for side: int in 2:
		var plate: Dictionary = _plates[side]
		var name_label: Label = plate["name"]
		var draw: _PlateDraw = plate["draw"]
		var cls: int = _fighter_class[side] if side < _fighter_class.size() else -1
		var shown: int = _final_hp[side] if _final_hp[side] >= 0 else _fighter_hp_now[side]
		var frac: float = clampf(float(shown) / maxf(float(_fighter_max[side]), 1.0), 0.0, 1.0)
		name_label.text = "%s   %d" % [_label(cls), maxi(shown, 0)]
		name_label.add_theme_color_override("font_color", _tint(cls))
		var vw: float = float(get_viewport().get_visible_rect().size.x)
		name_label.size = Vector2(PLATE_W, 16.0)
		name_label.horizontal_alignment = \
			HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		name_label.position = Vector2(
			PLATE_MARGIN if side == 0 else vw - PLATE_MARGIN - PLATE_W,
			PLATE_TOP + PLATE_H + 3.0)
		draw.frac = frac
		draw.tint = _hp_tint(frac)
		draw.queue_redraw()
	if _clock_label != null:
		var left: float = maxf(round_seconds - _clock, 0.0)
		_clock_label.text = "%s  %d:%02d" % [_tier(), int(left) / 60, int(left) % 60]


func _hp_tint(frac: float) -> Color:
	if frac > 0.5:
		return HP_MID.lerp(HP_FULL, (frac - 0.5) * 2.0)
	return HP_LOW.lerp(HP_MID, frac * 2.0)


func _tint(class_id: int) -> Color:
	if class_id < 0 or class_id >= ClassInfo.count():
		return FALLBACK_TINT
	return ClassInfo.color_for(class_id)


## The bar itself, drawn rather than laid out, because it drains toward the centre
## and a `ProgressBar` fills from a fixed edge. A `Control` subclass so the draw
## happens in screen space at the base viewport's scale.
class _PlateDraw extends Control:
	var side: int = 0
	var frac: float = 1.0
	var tint: Color = Color(0.36, 0.88, 0.42)

	func _draw() -> void:
		var vw: float = size.x
		var x0: float = BotMatch.PLATE_MARGIN if side == 0 \
			else vw - BotMatch.PLATE_MARGIN - BotMatch.PLATE_W
		var box := Rect2(Vector2(x0, BotMatch.PLATE_TOP),
			Vector2(BotMatch.PLATE_W, BotMatch.PLATE_H))
		draw_rect(box.grow(1.0), BotMatch.PLATE_EDGE)
		draw_rect(box, BotMatch.PLATE_BG)
		var w: float = BotMatch.PLATE_W * clampf(frac, 0.0, 1.0)
		# Left plate drains right-to-left; right plate drains left-to-right. Both
		# empty toward the middle of the screen, so the gap between them IS the score.
		var fx: float = x0 if side == 0 else x0 + BotMatch.PLATE_W - w
		draw_rect(Rect2(Vector2(fx, BotMatch.PLATE_TOP), Vector2(w, BotMatch.PLATE_H)), tint)


func _tick_readout() -> void:
	if _readout == null:
		return
	var d: Object = _director()
	if d == null:
		_readout.text = "%s vs %s" % [_label(_fighter_class[0]), _label(_fighter_class[1])]
		return
	_readout.text = "heat %.2f %s%s" % [
		float(d.call("heat")),
		"[ROLLING]" if bool(d.call("is_hot")) else "",
		"  %s" % _outcome_word() if _outcome != Outcome.NONE else "",
	]


func _director() -> Object:
	if _arena != null and _arena.has_method("clip_director"):
		return _arena.call("clip_director") as Object
	return null


func _label(id: int) -> String:
	return CLASS_LABELS[id] if id >= 0 and id < CLASS_LABELS.size() else "?"


func _tier() -> String:
	return TIER_LABELS[clampi(difficulty, 0, 3)]


# ==========================================================================
# THE MATCHUP KNOBS
#
# Every one of them RELOADS THE SCENE, and unlike free play that is the right call
# here: a matchup change means two different bodies with two different kits and two
# fresh brains. There is nothing to preserve across it — no learned record, no
# session, no position worth keeping — so a reload is the honest, simplest way to
# get a clean bout, and it is why all four knobs are statics.
# ==========================================================================

func _extend_pause_menu() -> void:
	if _arena == null or not _arena.has_method("pause_menu"):
		return
	var menu: Object = _arena.call("pause_menu")
	if menu == null:
		return
	menu.call("add_action", "Rematch", Callable(self, "_rematch"))
	menu.call("add_setting_section", "Bot Match")
	_labels["a"] = menu.call("add_setting_button", "Fighter A: %s" % _label(class_a),
		Callable(self, "_cycle_a"))
	_labels["b"] = menu.call("add_setting_button", "Fighter B: %s" % _label(class_b),
		Callable(self, "_cycle_b"))
	_labels["tier"] = menu.call("add_setting_button", "Difficulty: %s" % _tier(),
		Callable(self, "_cycle_tier"))
	_labels["hp"] = menu.call("add_setting_button", "Fighter HP: %d" % fighter_hp,
		Callable(self, "_cycle_hp"))
	_labels["loop"] = menu.call("add_setting_button",
		"Auto-rematch: %s" % ("on" if auto_rematch else "off"),
		Callable(self, "_cycle_loop"))


func _cycle_a() -> void:
	class_a = (class_a + 1) % CLASS_LABELS.size()
	if class_a == class_b:
		# A mirror match is a legal and interesting thing to watch, but it is a
		# DELIBERATE choice — walking into one by accident while cycling is not, and
		# it is the pairing most likely to produce the stalemate the brain's
		# stagnation model exists to break.
		class_a = (class_a + 1) % CLASS_LABELS.size()
	_reload()


func _cycle_b() -> void:
	class_b = (class_b + 1) % CLASS_LABELS.size()
	if class_b == class_a:
		class_b = (class_b + 1) % CLASS_LABELS.size()
	_reload()


func _cycle_tier() -> void:
	difficulty = (difficulty + 1) % TIER_LABELS.size()
	_reload()


## 120 / 190 / 260 / 340. Shorter bouts make better clips; longer ones show more of
## a kit. It is the pool BOTH fighters' vitality scales from, so it is a length knob
## and never an advantage.
func _cycle_hp() -> void:
	const STEPS: Array[int] = [120, 190, 260, 340]
	var i: int = STEPS.find(fighter_hp)
	fighter_hp = STEPS[(i + 1) % STEPS.size()] if i >= 0 else STEPS[1]
	_reload()


func _cycle_loop() -> void:
	auto_rematch = not auto_rematch
	_reload()


func _rematch() -> void:
	_reload()


## SIDES SWAP ON EVERY RELOAD. This stage is not left-right symmetric — every terrace
## and the whole bluff are on the right — so a series in which one class always
## started on the left would be measuring the map as much as the matchup.
func _reload() -> void:
	swap_sides = not swap_sides
	get_tree().paused = false
	get_tree().reload_current_scene()
