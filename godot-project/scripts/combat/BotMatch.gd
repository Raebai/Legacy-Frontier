class_name BotMatch
extends Node2D
## BOT vs BOT, WATCHABLE — the maker's second ask: *"we need really good bots to
## fight each other as well so that we can get some good content"*.
##
## The showcase mode inside `VersusArena` already puts two bot-driven heroes on the
## stage, but the ONLY way to reach it is a capture tool: you set two statics from a
## `--script` invocation, it renders PNGs, and you look at the PNGs afterwards. That
## is a rendering pipeline, not a way to WATCH a fight — and you cannot tell whether
## bots are fun to watch by reading a frame sequence.
##
## So this is the same fight, live, with the matchup on a menu:
##   · open `scenes/combat/BotMatch.tscn` and press F6 (or `BotMatch.enter(tree)`),
##   · Esc gives you class A, class B, difficulty and a rematch,
##   · the `ClipDirector` camera is on, so what you are watching is FRAMED THE WAY
##     THE CLIP WILL BE — which is the whole point of watching it before shooting it.
##
## ⚠ NOTHING HERE HELPS EITHER BOT. Both fighters get the same stock
## `BotController` + `BotBrain` + `BotProfile` the game ships, at the same tier,
## seeing only what a human sees. The only things this scene decides are WHO is on
## the stage and where the camera is. A staged fight between rigged bots is
## worthless for finding bugs and dishonest as marketing.
##
## PAIRINGS ARE NOT ARBITRARY. The default is Stormcaller vs Cryomancer because
## opposed elements are what make the reaction matrix fire — lightning through a
## frost field is `supercharge`, the best row in the table and the one the
## Stormcaller kit is literally built around. Two same-element bots produce a
## technically correct fight with nothing in it worth filming.

const ARENA_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"
const BOT_MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
const HUB_SCENE: String = "res://scenes/Main.tscn"

const CLASS_LABELS: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]
const TIER_LABELS: Array[String] = ["Easy", "Normal", "Hard", "Impossible"]

## STATICS, and they survive the scene reload every matchup change performs. A
## member would reset to its default on the first change and the maker would never
## be able to leave the opening pairing — the same reason `VersusArena`'s duel knobs
## are statics.
static var class_a: int = 6      # STORMCALLER
static var class_b: int = 5      # CRYOMANCER
static var difficulty: int = 3   # the tier that plays the whole kit (combo 0.90)
## Lower than the showcase's own 320 on purpose: a clip needs the fight to END.
static var fighter_hp: int = 190

var _arena: Node2D = null
var _readout: Label = null
var _labels: Dictionary = {}


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
		arena_script.set("showcase_a", clampi(class_a, 0, CLASS_LABELS.size() - 1))
		arena_script.set("showcase_b", clampi(class_b, 0, CLASS_LABELS.size() - 1))
		arena_script.set("showcase_difficulty", clampi(difficulty, 0, 3))
		arena_script.set("showcase_directed", true)
		arena_script.set("showcase_hp_override", fighter_hp)
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(_arena)
	_build_overlay()
	_extend_pause_menu()


## ⚠ CLEAR THE SHOWCASE STATICS ON THE WAY OUT. They outlive this node, this scene
## and the scene change that leaves it — so walking from a bot match into the versus
## duel would hand the duel two bots and no player, with the cause two scenes back.
func _exit_tree() -> void:
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script == null:
		return
	arena_script.set("showcase_a", -1)
	arena_script.set("showcase_b", -1)
	arena_script.set("showcase_directed", false)
	arena_script.set("showcase_hp_override", 0)


# ==========================================================================

## A live readout of what the DIRECTOR thinks, over the fight it is filming. This is
## the thing that turns "watch two bots" into "tune the clip engine": if the heat
## number sits at 0.05 through an exchange, the camera is going to open late and the
## thresholds are wrong.
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	_readout = Label.new()
	_readout.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_readout.offset_left = 16.0
	_readout.offset_top = -46.0
	_readout.add_theme_font_size_override("font_size", 12)
	_readout.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0, 0.9))
	_readout.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.09, 0.95))
	_readout.add_theme_constant_override("outline_size", 4)
	layer.add_child(_readout)


func _process(_delta: float) -> void:
	if _readout == null:
		return
	var d: Object = _director()
	if d == null:
		_readout.text = "%s vs %s — %s" % [_label(class_a), _label(class_b), _tier()]
		return
	_readout.text = "%s vs %s — %s     heat %.2f %s%s" % [
		_label(class_a), _label(class_b), _tier(),
		float(d.call("heat")),
		"[ROLLING]" if bool(d.call("is_hot")) else "",
		"  KO" if bool(d.call("saw_knockdown")) else "",
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
## a kit. Applied to BOTH fighters, so it is a length knob and never an advantage.
func _cycle_hp() -> void:
	const STEPS: Array[int] = [120, 190, 260, 340]
	var i: int = STEPS.find(fighter_hp)
	fighter_hp = STEPS[(i + 1) % STEPS.size()] if i >= 0 else STEPS[1]
	_reload()


func _rematch() -> void:
	_reload()


func _reload() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
