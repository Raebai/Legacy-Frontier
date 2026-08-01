class_name FreePlay
extends Node2D
## FREE PLAY — the stage, you, and nothing else.
##
## The maker's ask, verbatim: *"we need the ability for players to choose to just do
## no bots and play on the stage as well"*. This is the scene that answers it. No
## enemies, no waves, no timer, no run, no stocks, no way to lose. You drop onto the
## versus stage and you play: move, jump, dash, all three spells, the ult, blink,
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
const HUB_SCENE: String = "res://scenes/Main.tscn"
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


func _exit_to_hub() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("ringout_mode", false)
	get_tree().paused = false
	get_tree().change_scene_to_file(HUB_SCENE)


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
	blurb.text = "No enemies. No timer. Nothing can end this.\nLearn the verbs, then break the scenery."
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_font_size_override("font_size", 8)
	blurb.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
	col.add_child(blurb)

	var body := Label.new()
	# Read off `PauseMenu.CONTROLS_TEXT` rather than restated, so the one card a new
	# player reads can never drift from the one the settings menu shows.
	body.text = PauseMenu.CONTROLS_TEXT
	body.add_theme_font_size_override("font_size", 9)
	col.add_child(body)

	var dismiss := Button.new()
	dismiss.text = "GOT IT  —  play  (Esc for settings)"
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
	_hint.text = "FREE PLAY — %s      Esc: settings, class, dummies" % CLASS_LABELS[_class_id]


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
	menu.call("add_action", "Heal", Callable(self, "_heal"))

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
