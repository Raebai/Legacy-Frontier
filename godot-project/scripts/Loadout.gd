extends CanvasLayer
## Hub/Lobby ARMOURY (autoload "Loadout"). A paper doll: a live preview of YOUR stick
## figure on the left, the three equip slots beside it, and the detail of whatever you
## just touched underneath. Built in code + scene-safe (mirrors ClassSelect / Outfitter
## / PauseMenu). "Default" (empty) keeps the class's own gear for that slot.
##
## == WHAT THE MAKER ASKED FOR, AND WHAT THAT MEANT ============================
## Verbatim: "Armoury - remove all of the options right now. That is where we can have
## players equip custom cool armour pieces and cool spellements to add attributes to
## their current tools, but right now I don't think we have any of those if I'm not
## mistaken, so add placeholder cool names of stuff that we can then introduce later."
## And: "it should have a little version of our figure, and when you add or equip stuff
## of course it changes how it looks in that little figure."
##
## "Remove all of the options" and "don't break the game" pull against each other, so
## the reading taken here is deliberate and stated: THE MACHINERY STAYS, THE CONTENT
## GOES. Slots, the equip flow, Hero._recompute_gear_effects, the save round-trip and
## the read-out are all exactly what a real item will need on the day one exists. What
## is being rejected is the CATALOGUE - nineteen stat-tweak weapons and hats that were
## never the "custom armour and spellements" this screen is supposed to be. So the
## nineteen are no longer OFFERED (see GearAbilities.PLACEHOLDER_SLOTS); their rows
## survive because the rig, the enemy roster and two other people's test suites read
## them. The header of GearAbilities.gd carries that argument in full.
##
## /!\ THE PLACEHOLDERS ARE HONESTLY INERT - EVERY `effect` IS `{}`. A placeholder that
## quietly applied +15% damage would be worse than no placeholder at all: it would look
## like content, behave like balance, and get tuned around long before anyone noticed it
## was a stub. That costs real gameplay, and the cost is written down rather than
## discovered in play - every number the armoury used to hand out is listed in the
## report that shipped with this change.
##
## == THE PAPER DOLL, AND WHY IT LOOKS SCHEMATIC ===============================
## The figure is a real CharacterRig - the SAME class the town player and the combat
## hero draw with - not a second drawing of a stick figure. It wears the class preset,
## so it is your body.
##
## A placeholder must not put GEAR on it. The two failure modes are symmetrical and both
## are lies: a placeholder that changes nothing on the doll makes the slot read as
## broken, and a placeholder that changes the doll claims to be implemented. So an
## equipped placeholder draws a SCHEMATIC MARKER at the point on the body it would
## occupy - a dashed ring and the slot's initial, obviously a diagram rather than an
## item. The screen shows WHERE a piece goes without pretending one is on.
##
## /!\ CharacterRig.GEAR_DRAW (the master clothing switch) is FALSE on the maker's
## "I just want to see STICKMEN". Helms and armour therefore would not be drawn on the
## doll even if they were real items - only held weapons draw. That is a second reason
## the marker is the honest channel here rather than a fallback.
##
## == LAYOUT: HOW IT WAS DECIDED (no browser - reasoned from constraints) =======
## I did not survey any armoury UI; I have no browser and will not pretend otherwise.
## The constraints decide most of it:
##   * 640x360 LOGICAL, and aspect="expand" means a taller phone gets a WIDER viewport
##     - so 360 px of HEIGHT is the hard budget and width is the axis with slack. Every
##     layout below is judged on height first.
##   * Tap targets no smaller than ~9 mm => BUTTON_H 30 px in this space.
##   * Reachable by tap alone; no hover, no keyboard.
## Chosen: DOLL ON THE LEFT, SLOT LIST SCROLLING ON THE RIGHT, DETAIL UNDERNEATH. The
## vertical stack is title / [doll | list] / detail / Done, which measures well inside
## 360 because the doll and the list share one band instead of queueing.
## Rejected, each for a measurement or a constraint rather than taste:
##   * DOLL CENTRED WITH SLOTS RADIATING AROUND IT (the classic RPG paper doll). Needs
##     fixed absolute positions for the slot chips, which cannot scroll; with 16 pieces
##     the piece list has nowhere to go. It also wants a square-ish canvas, and the one
##     axis this viewport does not have is height.
##   * DOLL ON TOP, LIST BENEATH. Stacks the two tallest things: the doll alone wants
##     ~150 px and the list ~150 px, plus title, detail and Done - past 360 before any
##     padding. This panel already shipped at 377 px tall once (17 px taller than the
##     whole viewport) and nobody caught it, because the screen was unreachable.
##   * TABS, ONE SLOT AT A TIME, DOLL ALWAYS UP. Fits, but hides two thirds of the
##     catalogue behind a tap and makes "what am I wearing" a three-tap question - the
##     opposite of what a paper doll is for.
## tools/slice_test_armory_layout.gd measures the result at 640x360 AND 800x360:
## nothing overflows, nothing overlaps, every tappable clears the thumb floor.

## /!\ SLOT KEYS ARE A CONTRACT WITH TWO FILES THIS ONE DOES NOT OWN.
## Hero._aggregate_gear iterates the literals "weapon"/"head"/"body" and
## GameState.LOADOUT_SLOTS sanitises every save against them. The LABELS are what
## changed, to match what the armoury is now for: one spellement (an attachment for the
## tools you already carry) and two pieces of armour. Renaming the KEYS would have
## dropped every saved loadout on the floor while looking like a cosmetic edit.
## /!\ `legs` IS THE FOURTH, AND IT IS NOT A NEW CONTRACT WITH Hero.gd. Hero still reads
## three; this screen and `GameState.LOADOUT_SLOTS` read four. Every greave is a
## placeholder with an empty effect bag, so a slot Hero never looks at applies nothing —
## the note in GameState.LOADOUT_SLOTS carries the full reasoning and the one-line fix.
## It exists because the maker asked for gear that REPLACES a body part, and the lower
## leg is the third one a stick figure has (`CharacterRig._draw_leg`).
const SLOTS: Array = ["weapon", "head", "body", "legs"]
const SLOT_LABELS: Dictionary = {
	"weapon": "SPELLEMENT", "head": "HELM", "body": "ARMOUR", "legs": "GREAVES",
}
## One-line "what goes here", because SPELLEMENT is a coined word and a player who has
## never seen it needs the slot to explain itself rather than be guessed at.
const SLOT_BLURBS: Dictionary = {
	"weapon": "attaches to the spells you already carry",
	"head": "worn on the head",
	"body": "worn on the body",
	"legs": "worn on the lower legs",
}
const HIGHLIGHT: Color = Color(0.55, 0.9, 1.0)
## Placeholder buttons are DIMMED rather than DISABLED. Disabling them would make the
## menu untappable and unreadable on a phone - a disabled Button eats its own press, so
## the detail pane could never explain what the item WILL do, and reading the promises
## is the entire job of this screen right now.
const PLACEHOLDER_TINT: Color = Color(0.72, 0.72, 0.78)
## EARNABLE — visible, dim, and captioned with the verb that opens it.
const LOCKED_TINT: Color = Color(0.46, 0.48, 0.55)
## CLASS_LOCKED — dimmest AND warm, so the two refusals are told apart by hue and not
## only by brightness. One of them you can fix by climbing; the other you fix by being
## someone else, and a player should not have to read the row twice to know which.
const CLASS_LOCKED_TINT: Color = Color(0.62, 0.50, 0.42)

## Laid out for the 640x360 base viewport in LANDSCAPE - the same budget the Lobby and
## the Outfitter are pinned to. Every piece button clears BUTTON_H.
const PANEL_W: float = 460.0
const BUTTON_H: float = 30.0
## The doll column. Wider than the rig on purpose: the schematic markers sit BESIDE the
## body (the spellement marker is off the hand), and a marker clipped by the column edge
## reads as a rendering bug.
const DOLL_W: float = 132.0
const DOLL_H: float = 158.0
## FIXED height of the scrolling slot list - it shares the band with the doll, so the two
## are deliberately the same height. A ScrollContainer reports zero minimum size on its
## scrolling axis, so this constant decides how tall the panel is, NOT the number of
## pieces in the registry. Add five more spellements and it measures exactly the same.
const LIST_H: float = 158.0
## Rig geometry inside the doll column. The rig draws about 31 px tall at scale 1, feet
## BELOW its origin - the same offset Player.gd compensates for.
const RIG_H: float = 31.0
const RIG_SCALE: float = 2.6
const RIG_FEET_Y: float = 136.0

var _slot_buttons: Dictionary = {}       # slot -> Array[Button]
var _options: Dictionary = {}            # slot -> Array[String], "" (Default) first
var _ability_label: RichTextLabel = null
var _scroll: ScrollContainer = null
## The panel column. Held so a suite can assert the whole armoury still fits 360 px.
var _col: VBoxContainer = null
## The paper doll: the Control that owns the frame + markers, and the real rig inside it.
var _doll: Control = null
var _rig: CharacterRig = null
## The piece the player last touched, so the detail pane can describe a SELECTION and not
## only the equipped set. Without it, tapping a promise you have not equipped tells you
## nothing - which is the one thing this screen exists to do right now.
var _focus_kind: String = ""


func _ready() -> void:
	layer = 90
	visible = false
	for slot: String in SLOTS:
		var opts: Array = [""]
		opts.append_array(GearAbilities.options_for(slot))
		_options[slot] = opts

	var dim := ColorRect.new()
	# Nearly opaque. This opens over the Outfitter rather than over an empty hub floor,
	# and at 0.62 a whole second menu read straight through the piece names.
	dim.color = Color(0.03, 0.03, 0.06, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_child(vbox)
	_col = vbox

	var title := Label.new()
	title.text = "ARMOURY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	vbox.add_child(title)

	# The one band that carries both tall things. See the layout note in the header.
	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", 8)
	vbox.add_child(band)
	band.add_child(_build_doll())

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(PANEL_W - DOLL_W - 16.0, LIST_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	band.add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(rows)
	for slot: String in SLOTS:
		rows.add_child(_build_slot_row(slot))

	# Detail read-out for the touched / equipped pieces.
	_ability_label = RichTextLabel.new()
	_ability_label.bbcode_enabled = true
	_ability_label.fit_content = true
	_ability_label.custom_minimum_size = Vector2(PANEL_W - 16.0, 44)
	_ability_label.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(_ability_label)

	# An explicit way out. Tap-away works (the dim eats the press), but a phone player
	# has no Esc key and no reason to guess that the darkness is a button.
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(PANEL_W - 16.0, BUTTON_H)
	done.add_theme_font_size_override("font_size", 14)
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	vbox.add_child(done)


## The doll column: a real CharacterRig inside a plain Control, plus a `draw` hook for
## the frame and the schematic slot markers.
##
## A Control + the `draw` SIGNAL is used in place of a Control SUBCLASS on purpose - a
## subclass would want a class_name, and registering a new global class is the recurring
## editor-cache trap this project has been bitten by repeatedly.
func _build_doll() -> Control:
	_doll = Control.new()
	_doll.custom_minimum_size = Vector2(DOLL_W, DOLL_H)
	_doll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doll.draw.connect(_on_doll_draw)
	# /!\ THE SAME BODY YOU FIGHT WITH. CharacterRig is what Player.gd and the combat
	# Hero draw with, so the preview cannot drift from the game - which is the entire
	# reason a paper doll is worth building instead of a piece of art.
	_rig = CharacterRig.new()
	_rig.position = Vector2(DOLL_W * 0.5, RIG_FEET_Y)
	_rig.scale = Vector2(RIG_SCALE, RIG_SCALE)
	_doll.add_child(_rig)
	_rig.play(CharacterRig.State.IDLE)
	return _doll


## Where each slot's marker sits on the body, in doll-local pixels. Derived FROM the rig
## geometry rather than typed in, so changing RIG_SCALE moves the markers with the body
## instead of leaving them floating where the old body used to be.
func _slot_anchor(slot: String) -> Vector2:
	var cx: float = DOLL_W * 0.5
	var h: float = RIG_H * RIG_SCALE
	match slot:
		"head":
			return Vector2(cx, RIG_FEET_Y - h * 0.86)
		"body":
			return Vector2(cx, RIG_FEET_Y - h * 0.55)
		"legs":
			return Vector2(cx, RIG_FEET_Y - h * 0.16)
		_:
			# The spellement rides the tools in your hand, so its marker sits off to the
			# side of the torso rather than on the body.
			return Vector2(cx + 26.0, RIG_FEET_Y - h * 0.50)


func _on_doll_draw() -> void:
	if _doll == null:
		return
	var r := Rect2(Vector2.ZERO, _doll.size)
	_doll.draw_rect(r, Color(0.10, 0.11, 0.16, 0.85), true)
	_doll.draw_rect(r, Color(0.34, 0.38, 0.48, 0.9), false, 1.0)
	var lo: Dictionary = _loadout()
	for slot: String in SLOTS:
		var kind: String = String(lo.get(slot, ""))
		if kind == "" or not GearAbilities.is_placeholder(kind):
			continue
		# /!\ AND NOW ONLY FOR A PIECE WITH NO SILHOUETTE. The maker asked to SEE the mock
		# items, so every helm / armour / greave draws on the body above (see
		# CharacterRig.MOCK_HEAD). A dashed ring drawn over a piece that is already on the
		# figure would read as "this failed to load". The eight SPELLEMENTS still get one,
		# because a spellement attaches to a spell and has no body part to become — which
		# is the case this marker was written for.
		if CharacterRig.draws_kind(kind):
			continue
		# SCHEMATIC ON PURPOSE - a dashed ring, not a piece of gear. See the header:
		# drawing real art here would claim the placeholder works, and drawing nothing
		# would make the slot read as broken. This says "a piece goes HERE, later".
		var c: Vector2 = _slot_anchor(slot)
		var col := Color(0.55, 0.9, 1.0, 0.85)
		var segments: int = 12
		for i: int in segments:
			if i % 2 == 1:
				continue   # every other arc omitted == a dashed circle
			var a0: float = TAU * float(i) / float(segments)
			var a1: float = TAU * float(i + 1) / float(segments)
			_doll.draw_arc(c, 9.0, a0, a1, 4, col, 1.5)
		var initial: String = String(SLOT_LABELS[slot]).substr(0, 1)
		_doll.draw_string(ThemeDB.fallback_font, c + Vector2(-3.0, 3.5), initial,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	# Caption. Names what the box is and - because every offered piece is a promise right
	# now - says so where the player's eyes already are.
	# /!\ THE CAPTION CHANGED WITH THE RULING ABOVE, and the old wording is why. It read
	# "PREVIEW - pieces not yet worn", which was true when nothing drew and is now a lie
	# on a body visibly wearing a helm. What is still absent is the STAT, not the item, so
	# the caption says that instead — same honesty, aimed at the thing that is actually
	# missing.
	_doll.draw_string(ThemeDB.fallback_font, Vector2(6.0, DOLL_H - 6.0),
		"PREVIEW - mock look, no stats yet", HORIZONTAL_ALIGNMENT_LEFT, DOLL_W - 12.0, 9,
		Color(0.62, 0.67, 0.78))


func _build_slot_row(slot: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var lbl := Label.new()
	lbl.text = String(SLOT_LABELS[slot])
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	row.add_child(lbl)
	var blurb := Label.new()
	blurb.text = String(SLOT_BLURBS[slot])
	blurb.add_theme_font_size_override("font_size", 9)
	blurb.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	row.add_child(blurb)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	row.add_child(flow)
	var buttons: Array = []
	for kind: String in _options[slot]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, BUTTON_H)
		b.add_theme_font_size_override("font_size", 12)
		b.focus_mode = Control.FOCUS_NONE   # a stray focus ring on a phone reads as a bug
		b.text = _option_label(kind)
		b.pressed.connect(_on_option.bind(slot, kind))
		flow.add_child(b)
		buttons.append(b)
	_slot_buttons[slot] = buttons
	return row


## Short button caption: "Default" for the empty slot, else the piece's name with a
## trailing marker naming it a promise. The marker is on the BUTTON and not only in the
## detail pane because the button is what a player scanning the list actually reads.
func _option_label(kind: String) -> String:
	if kind == "":
		return "Default"
	var a: Dictionary = GearAbilities.of(kind)
	var piece_name: String = String(a.get("name", kind))
	# /!\ THE STATE GOES ON THE BUTTON, NOT ONLY IN THE COLOUR. Maker: *"still not clear
	# what is unlockable and what isnt … and how to unlock it"*. A dimmed button says
	# SOMETHING is wrong and a phone has no hover to ask what, so a row that cannot be
	# taken carries its own condition — the same fix the grimoire's "(slot 4 only)" is.
	var st: int = _state_of(kind)
	if st != Progression.Owned.HELD:
		return "%s  🔒 %s" % [piece_name, Progression.gear_unlock_short(kind, ClassInfo.names())]
	return piece_name + " *" if GearAbilities.is_placeholder(kind) else piece_name


## HELD / EARNABLE / CLASS_LOCKED for one piece, against the live save. `""` (Default) is
## always HELD — taking nothing off the shelf is not something anyone has to earn.
##
## Read through the tree rather than as a bare global so this autoload stays loadable in a
## headless harness with no GameState registered; a missing one reads as a fresh climber
## (floor 1, level 1), which is the strictest answer and therefore the safe default.
func _state_of(kind: String) -> int:
	if kind == "":
		return Progression.Owned.HELD
	var gs: Node = get_node_or_null("/root/GameState")
	var floor_best: int = int(gs.call("highest_floor")) if gs != null and gs.has_method("highest_floor") else 1
	var lvl: int = int(gs.call("level")) if gs != null and gs.has_method("level") else 1
	var cls: int = int(gs.get("selected_class")) if gs != null else 0
	return Progression.gear_state(kind, floor_best, lvl, cls)


func is_open() -> bool:
	return visible


func open() -> void:
	sanitize_equipped()
	_refresh()
	_preview()
	visible = true


func close() -> void:
	visible = false


## Drop any equipped id the armoury no longer offers.
##
## /!\ THIS IS THE HALF OF "REMOVE ALL OF THE OPTIONS" THAT A MENU CHANGE ALONE DOES NOT
## REACH. A save written before this change still carries e.g. head: "helmet", and
## Hero._apply_gamestate_loadout would go on applying its +20% max HP forever - an
## invisible stat, from an item no longer in the game, that the player can no longer see,
## un-equip, or reason about. The menu is the source of truth for what is equippable, so
## anything outside it is cleared.
##
## It fires on open(), which means a returning player keeps the old bonus until the first
## time they visit the armoury. Closing that window properly belongs in
## GameState.sanitize_loadout (scripts/GameState.gd:1408) - not this file's to edit; the
## exact change is named in the report that shipped with this.
func sanitize_equipped() -> void:
	var lo: Dictionary = _loadout()
	for slot: String in SLOTS:
		var kind: String = String(lo.get(slot, ""))
		if kind != "" and not (_options[slot] as Array).has(kind):
			lo[slot] = ""


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_option(slot: String, kind: String) -> void:
	# /!\ A ROW YOU HAVE NOT EARNED STILL ANSWERS THE QUESTION IT WAS TAPPED WITH.
	# The button is NOT `disabled` (see PLACEHOLDER_TINT above — a disabled Button eats its
	# own press, so the detail pane could never say why), so the refusal lives here: focus
	# moves, the pane explains, nothing is equipped. Reading is not choosing.
	_focus_kind = kind
	if _state_of(kind) != Progression.Owned.HELD:
		_refresh()
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var lo: Variant = gs.get("loadout")
		if lo is Dictionary:
			(lo as Dictionary)[slot] = kind   # Dictionaries are references - mutate in place
	_focus_kind = kind
	_preview()
	_refresh()


## Dress the doll AND the hub stick in the class default + the chosen overrides. The hub
## half is a no-op outside the hub (scene-safe).
func _preview() -> void:
	var preset: String = _preset()
	if _rig != null and preset != "":
		_rig.class_preset(preset)
	# /!\ PLACEHOLDER KINDS ARE NEVER HANDED TO A RIG. set_equipment tolerates an unknown
	# kind (it draws nothing), so this is not a crash guard - it is an honesty guard. A
	# placeholder must not sit in the rig's equipment dict as though it were a piece; the
	# doll's dashed marker is where it gets to appear.
	var wearable: Dictionary = _wearable_loadout()
	if _rig != null:
		for slot: String in SLOTS:
			var kind: String = String(wearable.get(slot, ""))
			if kind != "":
				_rig.set_equipment(slot, kind)
	if _doll != null:
		_doll.queue_redraw()
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("preview_loadout"):
		return
	player.call("preview_loadout", preset, wearable)


## The equipped set a rig may legitimately wear.
##
## /!\ THE RULE WAS "STRIP EVERY PLACEHOLDER" AND IS NOW "STRIP EVERY PLACEHOLDER THE RIG
## CANNOT DRAW". The old rule existed so a promise could not sit in the equipment dict
## LOOKING like a working piece; the maker has since asked for exactly that look
## (*"make mock versions of like helmets and stuff that replace the character head"*), so
## the honesty is moved rather than dropped — the ART is now real and the DETAIL PANE
## still stamps [NOT YET IMPLEMENTED] on every one of them. A spellement, which has no
## silhouette at all, is still stripped: handing the rig an id it draws nothing for is
## the case that reads as a broken slot.
func _wearable_loadout() -> Dictionary:
	var out: Dictionary = {}
	var lo: Dictionary = _loadout()
	for slot: String in SLOTS:
		var kind: String = String(lo.get(slot, ""))
		out[slot] = kind if CharacterRig.draws_kind(kind) else ""
	return out


## The hero preset for the currently-selected class (for the default-gear preview).
## Hero.gd has no class_name, so its CLASS_CONFIG is read via a runtime (cached) load
## rather than a parse-time reference (which would fail this autoload's compile).
const HERO_PATH: String = "res://scripts/combat/Hero.gd"

func _preset() -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	var cls: int = int(gs.get("selected_class")) if gs != null else 0
	var cfg_all: Dictionary = (load(HERO_PATH) as GDScript).get_script_constant_map().get("CLASS_CONFIG", {})
	var cfg: Dictionary = cfg_all.get(cls, {})
	return String(cfg.get("preset", ""))


func _loadout() -> Dictionary:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var lo: Variant = gs.get("loadout")
		if lo is Dictionary:
			return lo
	return {"weapon": "", "head": "", "body": "", "legs": ""}


## Highlight the selected button per slot, dim the promises, refresh the detail pane.
func _refresh() -> void:
	var lo: Dictionary = _loadout()
	for slot: String in SLOTS:
		var sel: String = String(lo.get(slot, ""))
		var opts: Array = _options[slot]
		var buttons: Array = _slot_buttons.get(slot, [])
		for i: int in buttons.size():
			var kind: String = String(opts[i])
			var b: Button = buttons[i] as Button
			# THREE STATES, ORDERED BY INK: yours > a promise you hold > not yours yet.
			# LOCKED is dimmest because it is the only one the tap will refuse.
			var st: int = _state_of(kind)
			if st == Progression.Owned.CLASS_LOCKED:
				b.modulate = CLASS_LOCKED_TINT
			elif st == Progression.Owned.EARNABLE:
				b.modulate = LOCKED_TINT
			elif kind == sel:
				b.modulate = HIGHLIGHT
			elif GearAbilities.is_placeholder(kind):
				b.modulate = PLACEHOLDER_TINT
			else:
				b.modulate = Color.WHITE
	if _ability_label != null:
		_ability_label.text = _ability_text(lo)


## BBCode read-out. Describes the piece you just TOUCHED first (so tapping a promise you
## have not equipped still tells you what it is), then everything equipped.
func _ability_text(lo: Dictionary) -> String:
	var lines: Array = []
	if _focus_kind != "":
		var f: Dictionary = GearAbilities.of(_focus_kind)
		if not f.is_empty():
			lines.append(_piece_line(_focus_kind, f))
	for slot: String in SLOTS:
		var kind: String = String(lo.get(slot, ""))
		if kind == "" or kind == _focus_kind:
			continue
		var a: Dictionary = GearAbilities.of(kind)
		if a.is_empty():
			continue
		lines.append(_piece_line(kind, a))
	if lines.is_empty():
		return "[color=#9aa4b5]Class default gear. Every piece below is a NAME WE HAVE PROMISED, not a working item - equipping one changes nothing yet.[/color]"
	lines.append("[color=#9aa4b5]Marked * - named, not yet implemented. Equipping it changes nothing yet.[/color]")
	return "\n".join(lines)


func _piece_line(kind: String, a: Dictionary) -> String:
	var tag: String = "  [color=#c8a04a][NOT YET IMPLEMENTED][/color]" if GearAbilities.is_placeholder(kind) else ""
	# The condition is repeated here in full because the button caption CLIPS on a phone.
	# The row tells you there is a lock; this tells you the whole sentence.
	var st: int = _state_of(kind)
	if st != Progression.Owned.HELD:
		var word: String = "NOT YOURS YET" if st == Progression.Owned.EARNABLE else "ANOTHER CLASS'S"
		tag += "  [color=#e08a5a][%s — %s][/color]" % [
			word, Progression.gear_unlock_verb(kind, ClassInfo.names())]
	return "[color=#8fd0ff]%s[/color]%s  %s" % [a.get("name", kind), tag, a.get("desc", "")]
