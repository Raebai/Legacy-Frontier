extends CanvasLayer
## THE TUTORIAL. One prompt at a time, in the lobby, against the dummies that are
## already standing there.
##
## Maker: *"it needs a tutorial area where the users can learn all the basic moves and
## attacks per class and the aim of the game"*.
##
## ══ WHY THIS IS NOT A TUTORIAL AREA, AND THAT IS THE POINT ═══════════════════
## The obvious build is a training level. It was NOT built, because the maker has
## already ruled that exact thing out twice and building it would re-litigate both:
##
##   * The `"sparring"` station used to teleport you to `FreePlay` — a whole second
##     scene with its own stage and camera — and it was DELETED on this ruling:
##     *"you should be able to cast spells and stuff within the lobby instead of a
##     training ground; just have standing immortal test dummies on one side."*
##     `World._spawn_dummy_yard` is that yard. It is the training area. It exists.
##   * Asked which pads to keep: *"I only want one for class within which I can edit
##     spells, and one for armoury where I can look at my equipment"*. Three kinds were
##     deleted for being a colour, a glyph and a dead branch. A "tutorial" pad would be
##     a fourth, and the room is deliberately down to two.
##
## So what was missing was never the PLACE. The lobby already has immortal dummies, a
## floor, ledges and every button live. What was missing is that nothing ever TELLS you
## what the buttons are, what your particular class does with them, or what the Tower is
## for. This is that telling, and it adds no room, no pad and no prop.
##
## ══ IT TEACHES THE CLASS YOU ARE, NOT A GENERIC HERO ═════════════════════════
## Every step below is derived from live data — `ClassInfo.carried_spells` for the four
## spells you actually hold, `SpellBlurbs` for what each one does, `Hero.CLASS_CONFIG`'s
## `move_verb` for the movement verb, which is DIFFERENT for all nine classes by the
## standing class-identity ruling (the Stormcaller blinks, the Cryomancer slides, the
## Warlock swaps with its thrall). A hardcoded lesson would teach the Arcanist's game to
## a Cryomancer and would rot the first time a kit changed.
##
## ⚠ AND IT RE-READS ON EVERY START. You change class at the altar three steps away, so
## the lesson has to be rebuilt when you come back, not cached at `_ready`.
##
## ══ COMPLETION IS THE ACTION ITSELF ══════════════════════════════════════════
## A step ticks when the player PRESSES THE THING. Not when a timer expires, not when
## they tap "next" — those teach a menu, not a game. The check is on the named action
## (`Input.is_action_just_pressed`), never on a keycode, so it is satisfied identically
## by a keyboard, a pad, or the on-screen touch buttons `World._pad` builds — which is
## the whole reason this project routes every input through named actions (D-011).
##
## ⚠ IT NEVER BLOCKS. No modal, no pause, no input capture. You can walk off, open the
## armoury, or ignore it entirely and it keeps up; `skip()` closes it for good. A
## tutorial you cannot leave is the "another layer" the whole town was rewritten to stop
## being.
##
## ⚠ NO `class_name`, ON PURPOSE. Registering a global class rewrites
## `global_script_class_cache.cfg`, which has taken three suites down in this repo when
## more than one agent was editing the same checkout — and a `--script` harness resolves
## compile-time class dependencies BEFORE autoloads register, which is a second way the
## same name bites. `World` reaches this by `preload`, exactly as it reaches
## `ArmoryStation`, and exactly as `PlayerProfile` and `HudStyle` are reached.

## Emitted when the lesson ends, either by finishing or by being skipped. `World` listens
## so it can record that this player has seen it.
signal finished(completed: bool)

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const ClassInfo := preload("res://scripts/combat/ClassInfo.gd")
const SpellBlurbs := preload("res://scripts/combat/SpellBlurbs.gd")

## Above the world, below a screen the pads open — the armoury and the outfitter must
## cover this, or a lesson would be readable through a menu it is not talking about.
const LAYER: int = 60

## The prompt card, in the 640x360 base space. Anchored to the TOP so it cannot collide
## with the loadout bar, which owns the bottom of the screen.
const CARD_W: float = 300.0
const CARD_TOP: float = 14.0

## How long a ticked step stays up saying "yes, that" before the next one replaces it.
## Short enough not to be a wait, long enough that the tick is seen rather than inferred.
const TICK_HOLD: float = 0.45

## ⚠ THE MOVEMENT STEP NEEDS BOTH DIRECTIONS, and asking for "a move key" would let a
## player finish it by leaning on one. Two flags, both required.
const MOVE_BOTH_WAYS: bool = true

## What each class's `move_verb` is CALLED to a player. The config value is an engine
## name (`ice_slide`, `shadow_slip`); this is the sentence. A verb with no entry falls
## back to "Dash", which is honest rather than wrong.
const VERB_WORDS: Dictionary = {
	"charge": "Charge",
	"ice_slide": "Ice Slide",
	"shadow_slip": "Shadow Slip",
	"blink": "Blink",
	"dash": "Dash",
	"roll": "Roll",
	"vault": "Vault",
	"surge": "Surge",
	"step": "Step",
}

## One lesson step. `action` is the named input that satisfies it; `""` means the step is
## a CARD — something to read rather than do — and it is satisfied by the interact key.
class Step:
	var title: String = ""
	var body: String = ""
	var action: StringName = &""
	var second_action: StringName = &""  # both required when set (the move step)
	var done: bool = false
	var half: bool = false  # first of a two-action step has landed

	func _init(t: String, b: String, a: StringName = &"", a2: StringName = &"") -> void:
		title = t
		body = b
		action = a
		second_action = a2


var _steps: Array[Step] = []
var _at: int = 0
var _hold: float = 0.0
var _running: bool = false

var _card: PanelContainer = null
var _title: Label = null
var _body: Label = null
var _progress: Label = null
var _skip_hint: Label = null


func _ready() -> void:
	layer = LAYER
	_build_card()
	visible = false
	# ⚠ RUNS WHILE THE GAME DOES, and must not run while a pad's screen is open — the
	# screens pause nothing, so without this the lesson would tick on presses the player
	# is spending on a menu. `_process` checks that itself; the mode is ALWAYS so the
	# card survives a pause without vanishing mid-sentence.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## Build (or rebuild) the lesson for `class_id` and show it. Safe to call again — the
## player can change class at the altar three steps away, so the lesson is rebuilt from
## live data every time rather than cached.
func start(class_id: int) -> void:
	_steps = _lesson_for(class_id)
	_at = 0
	_hold = 0.0
	_running = not _steps.is_empty()
	visible = _running
	set_process(_running)
	if _running:
		_refresh()


## Close the lesson without finishing it. The player asked to be left alone; treat that
## as seen, so it does not ambush them again on the next visit.
func skip() -> void:
	if not _running:
		return
	_running = false
	visible = false
	set_process(false)
	finished.emit(false)


func is_running() -> bool:
	return _running


## The step the player is on, for the suite and for anything that wants to describe it.
func current_title() -> String:
	if _at < 0 or _at >= _steps.size():
		return ""
	return _steps[_at].title


func step_count() -> int:
	return _steps.size()


func completed_count() -> int:
	var n: int = 0
	for s: Step in _steps:
		if s.done:
			n += 1
	return n


## ══ THE LESSON ══════════════════════════════════════════════════════════════
## Order is deliberate and is the order a player discovers a platformer in: stand up and
## move, leave the ground, then the verb that makes YOUR class move differently, then hit
## something, then the kit from cheapest to biggest, then what it is all for.
##
## ⚠ THE AIM CARD IS LAST, NOT FIRST. A player who has not yet moved has no frame for
## "climb the Tower, and dying drops you two floors" — it is a rule about a thing they
## have never done. After they have hit a dummy with their own ult it is a promise.
func _lesson_for(class_id: int) -> Array[Step]:
	var out: Array[Step] = []
	var cls_name: String = ClassInfo.name_for(class_id)

	out.append(Step.new("Move", "Walk left and right. Everything in the Tower is decided by where you are standing.", &"move_left", &"move_right"))
	out.append(Step.new("Jump", "Leave the ground. Some of you can do it twice.", &"jump"))

	# THE CLASS'S OWN MOVEMENT VERB. Nine classes, nine verbs, by standing ruling — so
	# this step says a different word and teaches a different thing for each of them.
	var verb: String = _verb_word(class_id)
	out.append(Step.new(verb, "Your %s. Every class moves differently, and this one is yours." % verb.to_lower(), &"dash"))

	out.append(Step.new("Strike", "Your basic attack. It costs nothing and it is always there. Try it on a dummy.", &"melee"))

	# THE KIT, FROM LIVE DATA. Four spells; the last is the ult by `SpellLibrary`'s slot
	# contract. A class with no readable kit contributes no steps rather than fake ones.
	var spells: Array = ClassInfo.carried_spells(class_id)
	var keys: Array[StringName] = [&"spell_1", &"spell_2", &"spell_3", &"ultimate"]
	for i: int in mini(spells.size(), keys.size()):
		var sp: Variant = spells[i]
		if sp == null:
			continue
		var nm: String = String(sp.display_name)
		var blurb: String = SpellBlurbs.for_spell(sp)
		var is_ult: bool = i == keys.size() - 1
		if blurb == "":
			blurb = "Your finisher." if is_ult else "One of your spells."
		out.append(Step.new(nm, ("%s  Your ult — the biggest thing you own." % blurb) if is_ult else blurb, keys[i]))

	# ⚠ THE AIM OF THE GAME, WHICH THE MAKER ASKED FOR BY NAME and which nothing in the
	# game had ever said out loud. Read, not done — satisfied by the interact key.
	out.append(Step.new("The Tower", "That is the whole of %s. Now climb: each floor is harder than the last, and the Tower does not end.\n\nDie and you fall two floors — but you keep everything you earned.\n\nThe dummies here never die. Practise as long as you like." % cls_name, &""))
	return out


## The player-facing word for a class's movement verb, read from `Hero.CLASS_CONFIG`.
##
## ⚠ REACHED BY `load`, NOT BY `class_name`. `Hero.gd` deliberately has no `class_name`,
## and naming it here would force compile-time resolution a `--script` harness runs before
## autoloads exist — the trap that took three suites down once already.
func _verb_word(class_id: int) -> String:
	var hero_script: GDScript = load("res://scripts/combat/Hero.gd") as GDScript
	if hero_script == null:
		return "Dash"
	var consts: Dictionary = hero_script.get_script_constant_map()
	if not consts.has("CLASS_CONFIG"):
		return "Dash"
	var cfg: Dictionary = consts["CLASS_CONFIG"]
	if not cfg.has(class_id):
		return "Dash"
	var verb: String = String((cfg[class_id] as Dictionary).get("move_verb", ""))
	return String(VERB_WORDS.get(verb, "Dash"))


func _process(delta: float) -> void:
	if not _running:
		return
	# ⚠ A PAD'S SCREEN DOES NOT PAUSE THE GAME. Without this, every press the player
	# spends navigating the armoury would tick a step off behind it and the lesson would
	# finish itself while they were reading something else.
	if _a_screen_is_open():
		return
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_advance()
		return
	if _at < 0 or _at >= _steps.size():
		return
	var s: Step = _steps[_at]
	if s.action == &"":
		# A CARD. Any of the confirm-ish keys closes it, so a player never hunts for the
		# one that works.
		if Input.is_action_just_pressed(&"talk") or Input.is_action_just_pressed(&"jump") \
				or Input.is_action_just_pressed(&"melee"):
			_tick(s)
		return
	if s.second_action != &"":
		if Input.is_action_just_pressed(s.action) or Input.is_action_pressed(s.action):
			s.half = true
		if s.half and (Input.is_action_just_pressed(s.second_action) \
				or Input.is_action_pressed(s.second_action)):
			_tick(s)
		return
	if Input.is_action_just_pressed(s.action):
		_tick(s)


## True while one of the pad screens owns the player's presses.
func _a_screen_is_open() -> bool:
	for n: Node in get_tree().get_nodes_in_group(&"town_overlay"):
		if n is CanvasItem and (n as CanvasItem).visible:
			return true
	return false


func _tick(s: Step) -> void:
	s.done = true
	_hold = TICK_HOLD
	_refresh()


func _advance() -> void:
	_at += 1
	if _at >= _steps.size():
		_running = false
		visible = false
		set_process(false)
		finished.emit(true)
		return
	_refresh()


func _refresh() -> void:
	if _at < 0 or _at >= _steps.size():
		return
	var s: Step = _steps[_at]
	_title.text = s.title
	_body.text = s.body
	_progress.text = "%d / %d" % [_at + 1, _steps.size()]
	var accent: Color = HudStyle.MINT if s.done else HudStyle.GOLD
	HudStyle.label(_title, HudStyle.BODY, accent)
	_skip_hint.visible = not s.done


func _build_card() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_TOP_WIDE)
	centre.offset_top = CARD_TOP
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(CARD_W, 0.0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.GOLD))
	centre.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudStyle.label(_title, HudStyle.BODY, HudStyle.GOLD)
	head.add_child(_title)

	_progress = Label.new()
	HudStyle.label(_progress, HudStyle.SMALL, HudStyle.GRAPHITE)
	head.add_child(_progress)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(CARD_W - 20.0, 0.0)
	HudStyle.label(_body, HudStyle.SMALL, HudStyle.CHALK)
	col.add_child(_body)

	_skip_hint = Label.new()
	HudStyle.label(_skip_hint, HudStyle.MICRO, HudStyle.GRAPHITE)
	_skip_hint.text = "Press it to continue  ·  the dummies never die"
	col.add_child(_skip_hint)
