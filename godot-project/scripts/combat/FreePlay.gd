class_name FreePlay
extends Node2D
## FREE PLAY — the stage, you, and nothing else.
##
## The maker's ask, verbatim: *"we need the ability for players to choose to just do
## no bots and play on the stage as well"*. This is the scene that answers it. No
## enemies, no waves, no timer, no run, no stocks, no way to lose. You drop onto the
## versus stage and you play: move, jump, dash, every spell, the ult, blink,
## nova, parry, melee, break the cover, ride the terraces, fall off the rim and come
## straight back.
##
## ---------------------------------------------------------------------------
## WHY THIS IS A SEPARATE SCENE AND NOT A FLAG ON THE ARENA.
##
## It is BOTH, and the split is the point. `VersusArena` owns the STAGE — 2000x1000
## of connected rock, the terraces, the rooted ruins, the destructible cover, the
## breakable lane, the ring-out pits — and none of that should be built twice. So
## free play does not rebuild it; it sets `VersusArena.free_play` and instantiates
## the arena as a child.
##
## What a separate scene buys is REACHABILITY. `VersusArena.tscn` has no route from
## the game today, and the one thing this mode must be is trivially reachable: open
## `scenes/combat/FreePlay.tscn` and press F6. That works with autoloads registered,
## needs no Lobby edit and no debug tooling, and it is how the maker will judge the
## feel. `FreePlay.enter(tree)` is the one-line hook for the Lobby button.
##
## ---------------------------------------------------------------------------
## IT IS THE ONBOARDING SURFACE, AND THAT IS HALF ITS JOB.
##
## The audit's fourth finding is that this game has ZERO onboarding — a player's
## first contact with the control scheme is a floor of things trying to kill them.
## A room where nothing can hurt you is where verbs get learned, so this scene
## prints the control card on screen (dismissible, and it stays dismissed) rather
## than hiding it behind the pause menu.
##
## ---------------------------------------------------------------------------
## RECONFIGURABLE WITHOUT A RESTART. Class, dummies, ring-out model and the stage
## itself all change live. That is a requirement, not a convenience: the whole
## purpose of a sandbox is to change ONE thing and immediately feel the difference,
## and a scene reload between every comparison destroys the comparison.
##
## ⚠ IT DOES NOT DUPLICATE THE DIRECTOR. `tools/director/Director.gd` (F1) already
## switches class live and grants any spell in the game, and it does both better
## than this ever will. Free play OFFERS it — the pause menu says so when the tools
## script is present — and otherwise stands entirely alone, because the director is
## gated out of release builds and free play is a SHIPPING feature that has to work
## without it.

## Reached BY PATH, never by `class_name VersusArena`. Naming the class here would
## compile it — and its whole autoload-touching dependency chain — at THIS script's
## parse time, which is the trap every capture tool in this project documents.
const ARENA_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"
const FREE_PLAY_SCENE: String = "res://scenes/combat/FreePlay.tscn"
## ⚠ THE TITLE SCREEN, NOT THE HUB — and the maker's own words are why: *"why is the
## hub still around, what do I do there"*. Backing out of free play used to load
## `res://scenes/Main.tscn`, the PARKED v0.0 village: a different game, with a class
## altar and a tower door and nothing for a player to do. Free play is the first
## thing anyone opens, so its exit
## was most people's first sight of it. The title screen is the boot scene, it works
## on a phone, and it is where every other exit in the game now lands. The hub stays
## on disk and stays reachable as an opt-in detour from the run-summary card; nobody
## should simply ARRIVE there.
const EXIT_SCENE: String = "res://scenes/ui/Lobby.tscn"
const DIRECTOR_SCRIPT: String = "res://tools/director/Director.gd"
## Screen space the controls card must keep clear: the AbilityBar hotbar along the
## bottom, and the hint line along the top.
const HOTBAR_RESERVE: float = 96.0
const HINT_RESERVE: float = 26.0

## The nine classes, in `Hero.HeroClass` order, under the names the design doc uses.
const CLASS_LABELS: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

## Which class free play starts on. A STATIC so it survives the scene reload that
## `Reset` performs, and so entering from the Lobby can pre-select the class the
## player already picked there without this scene having to reach into GameState.
static var start_class: int = -1

## ══ THE DOJO. Free play with a teacher in it. ═══════════════════════════════
## Maker: *"I want like a training that the user has the option to select at the start and
## when they click enter the tower for the first time when they start the game they get
## sent there and a sensei gives them some lore on the tower and how to attack and all
## that jazz"*.
##
## ⚠ THIS SCENE WAS ALREADY THE ANSWER AND NOBODY COULD REACH IT. Read this file's own
## header: *"IT IS THE ONBOARDING SURFACE, AND THAT IS HALF ITS JOB … this game has ZERO
## onboarding — a player's first contact with the control scheme is a floor of things
## trying to kill them. A room where nothing can hurt you is where verbs get learned."*
## That was written, built, given a control card and a dummy count and a no-death stage,
## and then `FreePlay.enter(tree)` — described in that header as "the one-line hook for
## the Lobby button" — was never called by anything in the shipping game. It has been F6
## only. So the training area the maker is asking for did not need building; it needed a
## door, a teacher, and a reason to be there.
##
## `dojo` is that mode: the same stage, plus a sensei who gives the Tower's lore and walks
## you through YOUR class's hands, and an exit that continues into the climb instead of
## dumping you back at the title.
static var dojo: bool = false

const SENSEI_SCENE: String = "res://scenes/NPC.tscn"
const SENSEI_DATA: String = "res://data/npcs/sensei.tres"
const COACH_SCRIPT: String = "res://scripts/ui/TrainingCoach.gd"
const PROFILE_SCRIPT: String = "res://scripts/PlayerProfile.gd"

## Where the sensei stands: to the LEFT of the player's drop, so he is the first thing on
## screen and is never between you and the straw you are being told to hit.
const SENSEI_X: float = -120.0

## What he becomes. Jade while he teaches; this the moment he stops.
const SENSEI_TURNED: Color = Color(0.86, 0.24, 0.30)

## ⚠ THE SWORDSAINT, and it is a character note rather than a coin toss. He is a martial
## teacher: the iai is a draw-cut that is stillness, one flash, and the cut resolving
## AFTER — which is exactly how a master should read against a student who has been
## practising for ninety seconds.
const SENSEI_CLASS: int = 8

## "Ridiculous damage and abilities and speed", by the maker's word. `_growth_damage_mult`
## is the levelling POWER axis and is already wired through both damage paths, so x6 needs
## no new plumbing. Vitality is high enough that a lucky ult cannot rob the scene of its
## ending — this fight has an author.
const SENSEI_POWER: float = 6.0
const SENSEI_VITALITY: int = 8
const SENSEI_BOT_TIER: int = 3

var _sensei: Node2D = null
var _coach: CanvasLayer = null

## Has the controls card been dismissed this session? Static for the same reason:
## being told the controls again every time you reset the stage is not onboarding,
## it is nagging.
static var controls_dismissed: bool = false

var _arena: Node2D = null
var _hint: Label = null
var _card: PanelContainer = null
var _class_btn: Button = null
var _dummy_btn: Button = null
var _ringout_btn: Button = null
var _class_id: int = 0


# ==========================================================================
# ENTRY POINTS
# ==========================================================================

## THE LOBBY HOOK. One line from a menu button:
##
##     FreePlay.enter(get_tree())
##
## ...or, if the Lobby would rather not name this class:
##
##     get_tree().change_scene_to_file("res://scenes/combat/FreePlay.tscn")
##
## `cls` pre-selects a class; -1 keeps whatever free play was last on (and falls
## back to `GameState.selected_class` on a cold start), so entering from the Lobby's
## own class picker lands you on the class you just chose.
static func enter(tree: SceneTree, cls: int = -1) -> void:
	start_class = cls
	tree.paused = false
	tree.change_scene_to_file(FREE_PLAY_SCENE)


func _ready() -> void:
	# ALWAYS, so Esc still reaches the pause overlay while the tree is paused. The
	# arena and the hero are PAUSABLE and still freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_class_id = _resolve_start_class()
	# Statics BEFORE the scene instantiates — `VersusArena._ready` reads them to
	# decide which of its three modes it is building.
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script != null:
		arena_script.set("free_play", true)
		arena_script.set("showcase_a", -1)
		arena_script.set("showcase_b", -1)
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(_arena)
	# The arena builds its hero, its HUD and its pause menu inside that `add_child`,
	# so everything below is talking to live nodes.
	_apply_class(_class_id, false)
	_build_overlay()
	_extend_pause_menu()
	if dojo:
		_begin_dojo()


## ⚠ CLEAR THE STATIC ON THE WAY OUT, and this is not optional book-keeping.
## `VersusArena.free_play` is a STATIC: it outlives this node, this scene and the
## scene change that leaves it. Without this, walking out of free play into the
## versus duel or into a capture tool's showcase would hand them an arena that
## builds one hero and no opponent — a silent, extremely confusing failure two
## scenes away from its cause.
func _exit_tree() -> void:
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script != null:
		arena_script.set("free_play", false)
	# ⚠ SAME REASON AS `free_play` ABOVE — `dojo` is a static and outlives this scene. A
	# dojo left set would put a sensei into the next plain free-play session and teach the
	# lesson again to someone who came in to test a spell.
	dojo = false


# ==========================================================================
# THE DOJO
# ==========================================================================

## Stand the sensei up and start the lesson.
##
## ⚠ HE IS A HERO BODY, NOT AN `NPC`, AND THAT IS THE WHOLE PLAN. He has to TEACH and then
## FIGHT, and a townsperson cannot fight — `NPC.tscn` is a StaticBody2D that ambles and
## says one line. Giving him a hero body from the first frame means the person who greets
## you and the person who beats you are the same object: no swap, no second silhouette, no
## moment where the teacher vanishes and a boss appears wearing his colour.
##
## ⚠ PHYSICS OFF WHILE HE TEACHES, and it is not an optimisation. A `Hero` with no
## controller falls through to the real `Input` singleton in `Hero._pressed`, so a live
## hero body MIRRORS EVERY BUTTON THE PLAYER PRESSES — the sensei would shadow-box your
## whole tutorial in perfect lockstep. `World._spawn_dummy_yard` and
## `VersusArena._rebuild_dummies` both carry this same warning; the symptom reads as "he
## is copying me", not as "he is broken".
## How many straw bodies the dojo opens with.
##
## ⚠ IT WAS ZERO, AND THE LESSON WAS TELLING YOU TO HIT ONE. `VersusArena.free_dummies`
## is a static defaulting to 0 and the dojo never raised it, so the Strike step's own
## words — *"Your basic attack ... Try it on a dummy"* — were addressed to an empty
## room. The `+` pad could summon them, but a lesson that requires the player to find a
## button before it can be obeyed is not a lesson. Maker: *"we need dummies in the
## training arena area as well"*.
const DOJO_DUMMIES: int = 3


func _begin_dojo() -> void:
	if _arena != null and is_instance_valid(_arena) 			and _arena.has_method("set_dummy_count"):
		_arena.call("set_dummy_count", DOJO_DUMMIES)
	_spawn_sensei()
	var coach_script: GDScript = load(COACH_SCRIPT) as GDScript
	if coach_script == null:
		return
	_coach = coach_script.new()
	add_child(_coach)
	if _coach.has_method("set_sensei"):
		_coach.call("set_sensei", _sensei, true)
	if _coach.has_signal("finished"):
		_coach.connect("finished", _on_lesson_finished)
	if _coach.has_method("start"):
		_coach.call("start", _class_id)


func _spawn_sensei() -> void:
	if _arena == null or not is_instance_valid(_arena):
		return
	var hero_scene: PackedScene = load("res://scenes/combat/Hero.tscn") as PackedScene
	if hero_scene == null:
		return
	_sensei = hero_scene.instantiate() as Node2D
	if _sensei == null:
		return
	_arena.add_child(_sensei)
	_sensei.set_physics_process(false)   # see the header: or he mirrors your input
	if _sensei.has_method("set_faction"):
		_sensei.call("set_faction", &"sensei", &"player")
	# ⚠ `"hero"`, NOT `"player"` — AND THIS IS THE GROUP-DRIFT TRAP `Hero._ready` WARNS
	# ABOUT BY NAME ("'hero' the tower group vs 'player' the old hub group"). A fighter
	# in an arena joins `hero`; `player` is the HUB body's group and nothing in this
	# scene is in it. So this lookup returned null, the `is Node2D` guard swallowed it,
	# the sensei was never moved off his spawn origin, and the teacher the whole dojo is
	# built around was standing off-camera for every player who ever reached it.
	# Photographed, not reasoned about: `tools/dojo_capture.gd` shows three dummies, the
	# lesson card, and no teacher anywhere in frame.
	#
	# He is excluded from his own search: he is a `Hero` body too, and he is added to the
	# tree above this line.
	var player: Node2D = null
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if h != _sensei and h is Node2D:
			player = h as Node2D
			break
	if player != null:
		# ⚠ HIS X COMES FROM THE STUDENT, HIS Y COMES FROM THE FLOOR, and taking both
		# from the student is what had him flying. This runs while the hero is still at
		# its spawn y — 55 px up, not yet fallen — and the sensei has physics disabled
		# (just above: or he mirrors your input), so he had nothing to pull him down
		# afterwards. He hung there beside a student standing on the ground for the
		# whole lesson. Maker: *"during the tutorial the bots are flying"*.
		var stand_y: float = player.global_position.y
		if _arena != null and is_instance_valid(_arena) 				and _arena.has_method("ground_stand_y"):
			stand_y = float(_arena.call("ground_stand_y"))
		_sensei.global_position = Vector2(player.global_position.x + SENSEI_X, stand_y)
	else:
		push_warning("FreePlay: no hero to stand the sensei next to — he stays at spawn")
	# A teacher does not wear a student's colours. Calm jade while he teaches; it is the
	# same value his `sensei.tres` carries, so if he is ever spawned as a townsperson
	# instead the two bodies still look like one person.
	_tint_sensei(Color(0.62, 0.86, 0.78))


func _tint_sensei(c: Color) -> void:
	if _sensei == null or not is_instance_valid(_sensei):
		return
	var rig: Variant = _sensei.get("rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("set_tint"):
		rig.call("set_tint", c)


## ══ THE TURN ════════════════════════════════════════════════════════════════
## Maker: *"have the sensei kill you at the end of the tutorial or turn evil and end with
## 'i'll see you in the tower...'"*, and *"the final tutorial fight is with the sensei and
## he just has ridiculous damage and abilities and speed — he can also be the floor 20
## boss"*.
##
## So the lesson does not end with a well done. It ends with the only person who has been
## kind to you putting you on the floor, and then leaving for the place you are about to
## go. That is the hook: the tutorial boss is not a tutorial boss, he is a preview, and
## `BossRoster`'s SENSEI entry means the promise is literally kept twenty floors later.
##
## ⚠ IT IS A REAL FIGHT, NOT A CUTSCENE, and that is the maker's word — "ridiculous damage
## and abilities and speed". He gets the same bot brain the duel uses, so he actually
## fights: dodges, casts, chases. The numbers below are what make it a lesson in humility
## rather than a boss you might fluke.
##
## ⚠ AND LOSING COSTS THE PLAYER NOTHING. This is the dojo — no floor drop, no lost gear,
## no climb state touched at all. `GameState` is never told. A tutorial that takes
## something from you for losing a fight it authored is a tutorial that lied.
func _on_lesson_finished(completed: bool) -> void:
	_mark_taught()
	if not completed or _sensei == null or not is_instance_valid(_sensei):
		_leave_dojo()
		return
	_sensei_turns()


func _mark_taught() -> void:
	var prof: GDScript = load(PROFILE_SCRIPT) as GDScript
	if prof != null and prof.has_method("mark_taught"):
		prof.call("mark_taught")


## He drops the teacher. Three beats, then he is hostile and absurd.
func _sensei_turns() -> void:
	if _sensei == null or not is_instance_valid(_sensei):
		return
	_sensei_say("Good. You learn quickly.", 2.2)
	await get_tree().create_timer(2.4).timeout
	if not is_instance_valid(_sensei):
		return
	# The colour turns before the words do — the player should feel it a beat early.
	_tint_sensei(SENSEI_TURNED)
	Juice.shake_camera(9.0)
	Juice.hit_stop(0.10)
	_sensei_say("Quickly enough to be worth killing.", 2.6)
	await get_tree().create_timer(2.6).timeout
	if not is_instance_valid(_sensei):
		return
	_arm_sensei()
	_sensei_say("Show me.", 1.6)
	_watch_for_defeat()


## RIDICULOUS, by the maker's word, and every number here is a multiplier on machinery
## that already exists rather than a special case:
##   * `_growth_damage_mult` is the levelling POWER axis, already wired through BOTH damage
##     paths (melee via the gear aggregate, spells via `SpellCaster._blood_pacted`), which
##     is why `BotMatch.CLASS_POWER` uses it too. x6 needs no new plumbing and cannot drift
##     from how damage is actually applied.
##   * the bot brain is the DUEL's brain at its top tier, so he genuinely dodges, chases
##     and casts. He is not a damage number standing still.
func _arm_sensei() -> void:
	if _sensei == null or not is_instance_valid(_sensei):
		return
	_sensei.set_physics_process(true)
	if _sensei.has_method("configure_class"):
		_sensei.call("configure_class", SENSEI_CLASS)
	_tint_sensei(SENSEI_TURNED)
	_sensei.set("_growth_damage_mult", SENSEI_POWER)
	var hp: Variant = _sensei.get("max_hp")
	if hp != null:
		_sensei.set("max_hp", int(hp) * SENSEI_VITALITY)
		_sensei.set("hp", int(hp) * SENSEI_VITALITY)
	# ⚠ ASKED OF THE ARENA, NOT REIMPLEMENTED. `VersusArena._attach_bot` is the one place
	# that knows how to give a hero body a brain, and it is guarded the same way the
	# capture tools reach this scene — a missing tools script must degrade to "he stands
	# there", never crash a tutorial.
	if _arena != null and is_instance_valid(_arena) and _arena.has_method("_attach_bot"):
		_arena.call("_attach_bot", _sensei, SENSEI_BOT_TIER)


## The player going down is the END OF THE SCENE, not a death. Polled rather than hooked
## because `Hero`'s death path belongs to the climb — it drops floors and writes the save —
## and the dojo must touch none of that.
func _watch_for_defeat() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	while is_instance_valid(player) and int(player.get("hp")) > 0:
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(self):
			return
	if not is_instance_valid(self):
		return
	# He does not gloat over the body. One line, and he is already somewhere else.
	_sensei_say("I'll see you in the tower...", 4.0)
	await get_tree().create_timer(3.6).timeout
	if is_instance_valid(self):
		_leave_dojo()


## ⚠ NOT `_say` — this file already had one, and naming a second the same made the
## whole script fail to parse ("Function \"_say\" has the same name as a previously
## declared function"), which took the dojo down without any suite noticing because
## none of them load this scene. The other `_say` flashes the ARENA BANNER; this one
## is a person speaking above their own head. Different things, different names.
func _sensei_say(text: String, hold: float = 3.0) -> void:
	if _sensei == null or not is_instance_valid(_sensei):
		return
	if _sensei.has_method("say"):
		_sensei.call("say", text, hold)
		return
	# A hero body has no `say` of its own; the shared bubble is what townspeople use, and
	# `Bark` will attach one to any Node2D.
	var bubble: Node = Bark._bubble_for(_sensei as Node2D)
	if bubble != null and bubble.has_method("say"):
		bubble.call("say", text, hold)


## Out of the dojo and into the thing it was for.
##
## ⚠ IT CONTINUES INTO THE CLIMB rather than returning to the title, because the player
## pressed ENTER THE TOWER to get here. Dropping them back at the front door would make
## the tutorial feel like an interruption of the thing they asked for instead of the first
## step of it.
func _leave_dojo() -> void:
	dojo = false
	get_tree().paused = false
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("enter_run"):
		gs.call("enter_run")
		return
	_exit_to_hub()


## The class to start on: the explicit request, then the last one played here, then
## whatever the player picked in the Lobby, then the Arcanist.
func _resolve_start_class() -> int:
	if start_class >= 0 and start_class < CLASS_LABELS.size():
		return start_class
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var picked: Variant = gs.get("selected_class")
		if picked != null:
			return clampi(int(picked), 0, CLASS_LABELS.size() - 1)
	return 0


# ==========================================================================
# LIVE RECONFIGURATION — the whole reason this mode exists
# ==========================================================================

## Swap the hero's class WITHOUT a reload. `Hero.configure_class` rebuilds the
## signature list, the hand and every cooldown, which is exactly what "be a
## Cryomancer now" means.
##
## ⚠ IT DOES NOT WRITE `GameState.selected_class`, deliberately. That field is the
## player's saved pick from the Lobby and it drives the next tower run; trying nine
## classes in a sandbox must not silently re-roll what you climb with. (The Tab key
## on the hero itself DOES write it — that is `Hero.cycle_class_next`, a different
## verb, and it is left alone.)
func _apply_class(cls: int, announce: bool = true) -> void:
	_class_id = clampi(cls, 0, CLASS_LABELS.size() - 1)
	start_class = _class_id
	var hero: Node = _hero()
	if hero != null and hero.has_method("configure_class"):
		hero.call("configure_class", _class_id)
	if _class_btn != null:
		_class_btn.text = "Class: %s" % CLASS_LABELS[_class_id]
	if announce:
		_say(CLASS_LABELS[_class_id])


func _cycle_class() -> void:
	_apply_class((_class_id + 1) % CLASS_LABELS.size())


## 0 -> 1 -> 2 -> 3 -> 0 practice dummies. A dummy is a hero-shaped body that can be
## hit and never hits back — the difference between "does this spell fire" and "does
## this spell LAND", which is the question a sandbox is actually for.
func _cycle_dummies() -> void:
	if _arena == null or not _arena.has_method("set_dummy_count"):
		return
	var now: int = int(_arena.call("dummy_count"))
	var next: int = (now + 1) % 4
	_arena.call("set_dummy_count", next)
	_refresh_dummy_label()
	_say("dummies: %d" % next)


func _refresh_dummy_label() -> void:
	if _dummy_btn == null or _arena == null or not _arena.has_method("dummy_count"):
		return
	_dummy_btn.text = "Practice dummies: %d" % int(_arena.call("dummy_count"))


## Ring-out (the Smash damage-% model) on or off, live. Off makes the stage a plain
## HP arena; on makes knockback scale with accumulated damage, which is the model
## the versus stage is built around. Being able to feel both back to back is the
## point of putting it on a button.
func _toggle_ringout() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var on: bool = not bool(gs.get("ringout_mode"))
	gs.set("ringout_mode", on)
	_refresh_ringout_label()
	_say("ring-out: %s" % ("ON" if on else "OFF"))


func _refresh_ringout_label() -> void:
	if _ringout_btn == null:
		return
	var gs: Node = get_node_or_null("/root/GameState")
	var on: bool = gs != null and bool(gs.get("ringout_mode"))
	_ringout_btn.text = "Ring-out model: %s" % ("ON" if on else "OFF")


## Cover, breakable platforms, hero position and health all back to frame one — and
## NOT via a scene reload, so the class you just switched to and the dummies you
## just placed survive it.
func _reset_stage() -> void:
	if _arena != null and _arena.has_method("reset_free_stage"):
		_arena.call("reset_free_stage")
	_say("stage reset")


## Top up. Nothing on this stage can kill you, but a long session of walking into
## your own meteor leaves the bar low enough to distract from what you are testing.
func _heal() -> void:
	var hero: Node = _hero()
	if hero == null:
		return
	var mx: Variant = hero.get("max_hp")
	if mx == null:
		return
	hero.set("hp", int(mx))
	if hero.get("damage_pct") != null:
		hero.set("damage_pct", 0.0)
	if hero.has_signal("health_changed"):
		hero.emit_signal("health_changed", int(mx), int(mx))
	_say("healed")


## Back out of free play to the TITLE screen (see EXIT_SCENE). Name kept because the
## pause menu binds to it by name; the destination is what changed.
func _exit_to_hub() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("ringout_mode", false)
	get_tree().paused = false
	get_tree().change_scene_to_file(EXIT_SCENE)


# ==========================================================================
# CHROME
# ==========================================================================

## The controls card and the hint line. Built on our OWN CanvasLayer above the
## arena's (60) but below the pause overlay, so a card is never trapped behind the
## dim when the game is paused.
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hint.offset_left = 16.0
	_hint.offset_top = 12.0
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0, 0.92))
	_hint.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.09, 0.95))
	_hint.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hint)
	_refresh_hint()

	if not controls_dismissed:
		# ⚠ NOT IN THE DOJO. The lesson has its own card and its own voice; the free-play
		# card lands on top of it, so the first thing a taught player saw was two panels
		# fighting for the same rectangle — one headed "The Tower" and one headed "FREE
		# PLAY", with a GOT IT button over the sensei's opening line. Free play keeps it;
		# the dojo is a different room with a different job.
		if not dojo:
			_build_controls_card(layer)


## THE ONBOARDING CARD. Every verb this game has, on screen, on the one surface
## where nothing is trying to kill you while you read it. Dismissed with any of the
## three obvious buttons and it STAYS dismissed for the session.
func _build_controls_card(layer: CanvasLayer) -> void:
	# ⚠ CENTRED IN THE SPACE ABOVE THE HOTBAR, not in the viewport. A plain
	# PRESET_CENTER put the bottom of the card straight through the ability bar and
	# the dismiss button underneath it — visible in the very first captured frame.
	# A full-rect CenterContainer with the bar's height reserved at the bottom keeps
	# both readable at any window size, which a hardcoded offset would not.
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.offset_bottom = -HOTBAR_RESERVE
	holder.offset_top = HINT_RESERVE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)

	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.10, 0.86)
	style.border_color = Color(0.55, 0.62, 0.85, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(11.0)
	_card.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_card.add_child(col)

	var title := Label.new()
	title.text = "FREE PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	col.add_child(title)

	var blurb := Label.new()
	blurb.text = "Nothing here can kill you."
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_font_size_override("font_size", 8)
	blurb.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
	col.add_child(blurb)

	# ⚠ THE FULL CONTROLS LIST IS DELIBERATELY NOT HERE ANY MORE.
	#
	# Maker: "the instructions are too long like there is too much going on this game
	# should be super simple". This card was printing all sixteen verbs at font size 9
	# over a room whose entire purpose is that you can safely press things and find
	# out. A wall of key bindings is the opposite of a practice room — it is homework
	# in front of a sandbox.
	#
	# What replaces it is one line naming the two things a new player cannot discover
	# by mashing: that nothing can hurt them, and where the full list lives when they
	# want it. `PauseMenu.controls_text()` still generates that list from the live
	# InputMap, one Esc away.
	var body := Label.new()
	body.text = "Move, jump, and hit things.        Esc for every control."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 9)
	body.add_theme_color_override("font_color", Color(0.62, 0.63, 0.70))
	col.add_child(body)

	var dismiss := Button.new()
	dismiss.text = "GOT IT"
	dismiss.focus_mode = Control.FOCUS_NONE
	dismiss.pressed.connect(_dismiss_card)
	col.add_child(dismiss)
	holder.add_child(_card)


func _dismiss_card() -> void:
	controls_dismissed = true
	if _card != null:
		_card.queue_free()
		_card = null


## Any real input dismisses the card too — a player who has already started moving
## has told you they do not want to read it.
func _unhandled_input(event: InputEvent) -> void:
	if _card == null:
		return
	if event is InputEventKey and event.is_pressed():
		if event.is_action_pressed("ui_cancel"):
			return   # Esc belongs to the pause menu, not to this card
		_dismiss_card()
	elif event is InputEventScreenTouch and event.is_pressed():
		_dismiss_card()


func _refresh_hint() -> void:
	if _hint == null:
		return
	# ⚠ THE ROOM SAYS WHICH ROOM IT IS. The dojo and free play are the same scene, and
	# the header called both of them FREE PLAY — so a player sent to be TAUGHT, by a
	# teacher, was told they were in a sandbox. Maker: *"the training should be in a new
	# place ... it should be with that sensei"*. It is a different place; it now says so.
	_hint.text = ("THE DOJO — %s      Esc: settings, class, dummies"
		if dojo else "FREE PLAY — %s      Esc: settings, class, dummies") 		% CLASS_LABELS[_class_id]


## Flash a line through the arena's own banner rather than standing up a second one.
func _say(text: String) -> void:
	_refresh_hint()
	if _arena != null and _arena.has_method("flash_banner"):
		_arena.call("flash_banner", text, 1.0)


## Hang the free-play knobs on the arena's EXISTING pause menu. One Esc, one menu:
## a second overlay of our own would fight the first for the key and stack two dims.
func _extend_pause_menu() -> void:
	if _arena == null or not _arena.has_method("pause_menu"):
		return
	var menu: Object = _arena.call("pause_menu")
	if menu == null:
		return
	menu.call("add_action", "Reset the stage", Callable(self, "_reset_stage"))
	# ⚠ "HEAL" IS GONE. Maker: "settings remove the heal button". It set
	# `hp = max_hp` on the live hero, ungated by `OS.is_debug_build()` — a cheat
	# sitting in a player-facing menu, one row under a real verb. `_heal` itself is
	# kept because "Reset the stage" is the honest version of the same wish and a
	# stage reset re-spawns you whole; nothing else calls it, so deleting the row is
	# the whole fix.

	menu.call("add_setting_section", "Free Play")
	_class_btn = menu.call("add_setting_button", "Class: %s" % CLASS_LABELS[_class_id],
		Callable(self, "_cycle_class")) as Button
	_dummy_btn = menu.call("add_setting_button", "Practice dummies: 0",
		Callable(self, "_cycle_dummies")) as Button
	_refresh_dummy_label()
	_ringout_btn = menu.call("add_setting_button", "Ring-out model: ON",
		Callable(self, "_toggle_ringout")) as Button
	_refresh_ringout_label()
	menu.call("add_setting_button", "Show the controls card again",
		Callable(self, "_show_card_again"))
	# The director is a DEV tool and is gated out of release builds, so free play
	# only mentions it when it is genuinely there — and never depends on it.
	if FileAccess.file_exists(DIRECTOR_SCRIPT):
		menu.call("add_setting_section", "Dev")
		menu.call("add_setting_button", "F1 opens the director (spells, classes)",
			Callable(self, "_noop"))


func _show_card_again() -> void:
	controls_dismissed = false
	if _card != null:
		return
	for child: Node in get_children():
		if child is CanvasLayer and (child as CanvasLayer).layer == 70:
			_build_controls_card(child as CanvasLayer)
			return


## A label row in the settings panel. `PauseMenu` only builds BUTTONS, so a purely
## informational line is a button that does nothing rather than a second widget kind.
func _noop() -> void:
	pass


func _hero() -> Node:
	if _arena != null and _arena.has_method("free_hero"):
		return _arena.call("free_hero") as Node
	return null
