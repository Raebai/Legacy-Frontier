extends CanvasLayer
## THE TUTORIAL. One prompt at a time, in the lobby, against the dummies that are
## already standing there.
##
## Maker: *"it needs a tutorial area where the users can learn all the basic moves and
## attacks per class and the aim of the game"*.
##
## ══ IT RUNS IN TWO PLACES, AND THE DOJO IS THE ONE THAT MATTERS ══════════════
## This was first built lobby-only, on the reasoning that the maker had twice ruled out a
## training ground (the `"sparring"` pad that teleported you to `FreePlay` was deleted on
## *"you should be able to cast spells and stuff within the lobby instead of a training
## ground; just have standing immortal test dummies on one side"*, and the pads were cut
## to two by name). **The maker overruled that**: *"no no I want like a training that the
## user has the option to select at the start and when they click enter the tower for the
## first time … they get sent there and a sensei gives them some lore on the tower and how
## to attack"*. Their call, and the reasoning above was wrong about what they wanted — a
## room with a teacher in it is not the prop-scattered training ground that was cut.
##
## So there are two hosts, and this file serves both without knowing which it is in:
##
##   * **THE DOJO** (`FreePlay` with `dojo = true`) — the real thing. A no-death stage, a
##     sensei who gives the Tower's lore and then teaches, and a fight at the end. This is
##     where a new player is sent the first time they press ENTER THE TOWER.
##   * **THE LOBBY** — the same steps with no lore and no speaker, for a player who taps
##     HOW TO PLAY and wants the button list again next to the dummies. No pad, no prop.
##
## `set_sensei(who, with_lore)` is the only difference between them.
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
## ⚠ 14 -> 34, BECAUSE THE CARD LANDED ON TOP OF THE ROOM LABEL. The stage draws
## "THE DOJO — ARCANIST    Esc: settings, class, dummies" across the top-left, and at 14
## the card's own panel started inside that line: the label's words rendered over the
## card's dark fill, two unrelated pieces of text sharing the same pixels. Photographed
## in `proof/2026-10-18-tutorial-fixes/`, which is also why this is a number and not an
## opinion. 34 clears the label's baseline with room to spare at the 640x360 base size.
const CARD_TOP: float = 34.0

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

## THE SENSEI, when there is one. Maker: *"a sensei gives them some lore on the tower and
## how to attack and all that jazz"*.
##
## ⚠ OPTIONAL, AND THE LESSON MUST STAND UP WITHOUT HIM. The same coach runs in the hub,
## where there is no sensei and never will be — the lobby was cut down to two pads and a
## dummy yard on the maker's own ruling. So the sensei is a VOICE the lesson borrows when
## the dojo provides one, never a thing it depends on: every step still shows its card and
## still ticks on the same press if `_sensei` is null.
##
## The division of labour is deliberate. The sensei SAYS it, in his own voice, above his
## own head. The card says WHICH BUTTON, and stays up while you fumble for it. A talking
## head alone makes you re-trigger dialogue to remember a key; a card alone is a manual
## with nobody in it.
var _sensei: Node = null

## Whether to open with the Tower lore. False in the hub — a player who has walked into
## their own town does not need to be told what the Tower is for the fourth time.
var _lore: bool = false

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
## Give the lesson a voice and the Tower lore. Called by the dojo before `start`; the hub
## never calls it, so the hub lesson is the same steps with no lore and no speaker.
func set_sensei(who: Node, with_lore: bool = true) -> void:
	_sensei = who
	_lore = with_lore


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

	# ══ THE LORE, FIRST, AND SPOKEN BY A PERSON ══════════════════════════════
	# Maker: *"a sensei gives them some lore on the tower and how to attack and all that
	# jazz"*. Lore BEFORE the verbs, unlike the aim card that closes the lesson: what the
	# Tower IS is the reason to learn a button, so it is the greeting. What happens when
	# you DIE is a rule about a thing they have not done yet, so it stays at the end.
	#
	# ⚠ THESE ARE THE ONLY HARDCODED STRINGS IN THE LESSON, and they are hardcoded
	# because they are AUTHORED VOICE — the sensei's, not a description of a data table.
	# Everything below is derived from the class you are.
	if _lore:
		out.append(Step.new("The Tower", "So. You have come to climb.\n\nThe Tower has no summit that anyone has returned to describe. It has floors, and each one is worse than the last, and that is the whole of the arrangement.", &""))
		out.append(Step.new("The Sensei", "I am not going to fight you. Nothing on this floor can hurt you — it is the only floor where that is true.\n\nStay a while. Learn your hands.", &""))

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
	out.append(Step.new("The Climb", "That is the whole of %s.\n\nNow climb. Each floor is worse than the one below it and the Tower does not end.\n\nWhen you fall — and you will fall — you drop two floors. You keep everything you earned. The town keeps count.\n\nThe straw here never dies. Stay as long as you like." % cls_name, &""))
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
		# A CARD. More than one confirm-ish key closes it, so a player never hunts for
		# the one that works.
		#
		# ⚠ BUT NOT `jump`, AND THAT WAS THE WHOLE "RUSHED" BUG. `jump` is bound to W
		# and Up — the keys a player holds to WALK, and the keys this very lesson is
		# about to teach them. So anyone who touched a movement key during the eleven
		# lore cards blew straight through the story they were being told, several
		# cards at a time, while the card in front of them said "Press E to continue".
		# Maker: *"the text is weird and ... it feels rushed and cofusing"*.
		#
		# `talk` (E, and the on-screen E pad) is what the card names, and `melee` (F)
		# stays as the second key because it is not a movement key and cannot be hit
		# by accident while trying to walk.
		if Input.is_action_just_pressed(&"talk") or Input.is_action_just_pressed(&"melee"):
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


## Say the step out loud, if there is anyone to say it.
##
## ⚠ ONLY WHEN THE STEP ARRIVES, never on the tick. `_refresh` runs twice per step — once
## when it opens and once when it is ticked green — and speaking on both would have the
## sensei repeat every instruction back at you the instant you obeyed it.
##
## ⚠ AND THE BUBBLE GETS THE FIRST SENTENCE, NOT THE WHOLE CARD. `SpeechBubble` shrinks to
## fit its text and the lore steps are three paragraphs; the whole body would put a panel
## over half the stage. The card is already showing the full text — the bubble's job is to
## make it his voice, not to duplicate the card.
func _voice(s: Step) -> void:
	if _sensei == null or not is_instance_valid(_sensei) or not _sensei.has_method("say"):
		return
	var line: String = s.body.split("\n")[0].strip_edges()
	if line == "":
		return
	_sensei.call("say", line, 4.0)


func _refresh() -> void:
	if _at < 0 or _at >= _steps.size():
		return
	var s: Step = _steps[_at]
	if not s.done:
		_voice(s)
	_title.text = s.title
	_body.text = s.body
	_progress.text = "%d / %d" % [_at + 1, _steps.size()]
	var accent: Color = HudStyle.MINT if s.done else HudStyle.GOLD
	HudStyle.label(_title, HudStyle.BODY, accent)
	# ⚠ THE CARD NAMES THE KEY. Maker, playing: *"strike isnt regstering in the
	# training"*. It was registering fine — `melee` is bound to physical keycode 70,
	# the letter F, and NOTHING in this game ever says so. No step named its key, the
	# hint below said only "Press it to continue", and the desktop hotbar advertises
	# RMB, Spc and 1-4 but never the strike. Move and Jump are guessable; F is not, so
	# the lesson stopped dead on the one verb a player cannot find.
	#
	# ⚠ READ FROM THE InputMap, NEVER TYPED HERE. A second copy of a binding is a
	# binding that drifts — this branch has already paid for a test that hardcoded a
	# glyph and for two inverses of one caption format. Rebind `melee` and this line
	# follows on its own.
	_skip_hint.text = _hint_for(s)
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
	_skip_hint.text = "the dummies never die"
	col.add_child(_skip_hint)


## The line under the card: which key this step is waiting for, in the player's own
## keyboard's terms, plus the standing reassurance.
func _hint_for(s: Step) -> String:
	if s.action == &"":
		return "Press %s to continue  ·  the dummies never die" % _key_label(&"talk")
	var keys: String = _key_label(s.action)
	if s.second_action != &"":
		keys = "%s and %s" % [keys, _key_label(s.second_action)]
	return "Press %s  ·  the dummies never die" % keys


## A human name for whatever `action` is bound to, asked of the InputMap rather than
## written down. Prefers a keyboard key, falls back to a mouse button, and says the
## action's own name if it is bound to nothing at all — which is itself worth seeing on
## screen, because an unbound verb is a verb no player can perform.
static func _key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return String(action)
	var mouse: String = ""
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k: InputEventKey = e as InputEventKey
			# ⚠ PHYSICAL FIRST. Every binding in this project is by `physical_keycode`
			# so QWERTY and AZERTY behave the same; `keycode` is 0 on all of them and
			# reading it would return "(unset)" for the whole game.
			var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
			if code != 0:
				# ⚠ THE PHYSICAL->LAYOUT LOOKUP IS SKIPPED WITHOUT A WINDOW. The headless
				# display server has no keyboard layout and warns on every call, which
				# would put a stack trace in the log of every suite that builds a card.
				# The raw code is the right answer there anyway: no layout, no remap.
				if k.physical_keycode != 0 and DisplayServer.get_name() != "headless":
					code = DisplayServer.keyboard_get_keycode_from_physical(code)
				return OS.get_keycode_string(code)
		elif e is InputEventMouseButton and mouse == "":
			match (e as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: mouse = "LMB"
				MOUSE_BUTTON_RIGHT: mouse = "RMB"
				MOUSE_BUTTON_MIDDLE: mouse = "MMB"
				_: mouse = "Mouse %d" % (e as InputEventMouseButton).button_index
	if mouse != "":
		return mouse
	return String(action)
