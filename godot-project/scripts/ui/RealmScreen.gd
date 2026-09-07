extends Control
## ═══════════════════════════════════════════════════════════════════════════════
## YOUR REALM — the screen behind the title's MULTIPLAYER button.
## ═══════════════════════════════════════════════════════════════════════════════
##
## Maker: *"pressing multiplayer should take you to a character selection screen where
## you can add other people to your realm etc. and connect local play"*.
##
## ⚠ THE HONEST VERSION OF THAT ASK, AND WHY IT IS SMALLER THAN IT SOUNDS. Two things
## in the sentence do not exist in this game:
##
##   1. **"add other people to your realm"** implies a FRIEND LIST, and a friend list
##      needs a person to key on. Until `PlayerProfile` landed there was no player
##      identity here at all — `Net` tracked a class and a floor and nothing else — so
##      this screen could only ever have said "Player 2 — Stormcaller". Identity is
##      built first (see `PlayerProfile`); the list it makes possible is not built yet
##      and this screen does not pretend otherwise.
##   2. **more than one other person.** `Net.MAX_PLAYERS` is 2, and that is the settled
##      mobile scope-lock rather than a placeholder: the 25-entity budget, the one-screen
##      arena and the friendly-fire social loop are all balanced around exactly two
##      thumbs in one room. So this screen has TWO seats, drawn as two cards, and it does
##      not offer a third.
##
## ⚠ "CONNECT LOCAL PLAY" WAS ALREADY BUILT AND HAD NO DOOR, WHICH IS THE REAL FIND.
## `LocalCoop.gd` is shipped, and `Arena` builds one on every offline run: a second
## person picks up a pad, presses A, and a climber walks in mid-floor. Its own header
## says *"NO LOBBY, NO MENU, NO DEVICE-ASSIGNMENT SCREEN — the pad IS the join"*, which
## is the right design and is exactly why nothing in the game has ever SAID SO. And
## `GameState.SessionKind.LOCAL` was declared and written by nobody, so the hub's Party
## Stone — which stands up for any non-solo visit — could never appear for a couch game.
##
## So LOCAL PLAY here is not a second path and builds no machinery. It sets the enum
## value that already existed and walks you into the same room SINGLE PLAYER does, with
## the one sentence of instruction the feature was missing. It deliberately does NOT go
## through `Net`: a loopback host is a real network session with a real socket, and
## calling that "local play" would be relabelling the wrong thing.
##
## ⚠ HEIGHT IS THE SCARCE AXIS AND WIDTH IS NOT. `project.godot` is 640x360 with
## `stretch/aspect="expand"`, which keeps the base HEIGHT and grows the width — so a
## taller phone gets a WIDER logical viewport, never a shorter one. 360 px is therefore
## a hard ceiling and 640 px is a floor. Every number below is chosen against that, and
## `tools/slice_test_realm.gd` measures the resolved column rather than trusting it.
##
## ⚠ AN OVERLAY, NOT A SCENE CHANGE, for the reason `Lobby._open_credits` gives about
## the credits: you are often already HOSTING when you open this, and a scene change
## would drop the peer you are waiting for.
##
## ⚠ NO `class_name`. Same reason `Settings`, `HudStyle` and `PlayerProfile` carry none:
## registering a global class rewrites `global_script_class_cache.cfg`, and this checkout
## is edited by several agents at once. `Lobby` reaches this by PATH and `load()`, which
## is the same shape it already uses for Free Play, Watch Bots and the duel stage.

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const PlayerProfile := preload("res://scripts/PlayerProfile.gd")

signal closed
## The three verbs. Emitted rather than called, so this screen knows nothing about the
## Lobby's private methods and the Lobby keeps being the single owner of "what hosting
## actually does" — it already holds the `session_kind` writes and the discovery
## teardown that must happen around each one.
signal host_pressed
signal join_pressed
signal local_pressed
signal start_pressed

# ── the look, borrowed from the title screen so this reads as the same game ──
const PAPER: Color = Color(0.055, 0.052, 0.075)
const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)

## ⚠ RESTATED, NOT READ FROM `Outfitter.MIN_TAP`, AND THE DUPLICATION IS DELIBERATE.
## The value is 30.0 (`scripts/ui/Outfitter.gd:72`) and `World` and `Lobby` hold the same
## floor. Reaching for the constant would couple this screen's compile to a file another
## workstream owns — and, more importantly, `slice_test_realm` asserts against a LITERAL
## 30 for the reason `slice_test_settings` writes out its own 46: *a test may not read the
## value under test*, or lowering the constant moves the floor with the buttons and the
## suite stays green through the exact regression it exists to catch.
##
## 30 px on the 640x360 base is 5.5 mm on a 6.1" phone — the game-wide floor, not the
## 46 px the title screen's two primaries hold to. This screen is one press IN from the
## front door and has five rows to fit, so it sits at the floor rather than above it.
const MIN_TAP: float = 30.0
## The two verbs on this screen that start something get the taller row. Still well
## inside the height budget — see `_build`.
const ACTION_H: float = 34.0
## Each identity card. Two of them side by side occupy the width the base viewport has
## going spare, which is the axis that is not scarce.
const CARD_H: float = 92.0

var _net: Node = null
var _name_edit: LineEdit = null
var _you_name: Label = null
var _you_class: Label = null
var _peer_name: Label = null
var _peer_class: Label = null
var _peer_caption: Label = null
var _status: Label = null
var _start_btn: Button = null
## The measured column. Held for the same reason `Lobby._col` is: it is the thing the
## suite measures, and a screen whose height is only ever eyeballed is a screen that
## walks off the bottom of a phone the first time somebody adds a row.
var _col: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_net = get_node_or_null("/root/Net")
	_build()
	if _net != null and _net.has_signal(&"lobby_changed"):
		_net.connect(&"lobby_changed", _refresh)
	_refresh()


func _exit_tree() -> void:
	# The autoload outlives this overlay, so a missed disconnect is a call into a freed
	# Control for the rest of the session.
	if _net != null and _net.has_signal(&"lobby_changed") and _net.is_connected(&"lobby_changed", _refresh):
		_net.disconnect(&"lobby_changed", _refresh)


## ESC closes, because a full-screen overlay with only a Back button is a trap on
## desktop. `_unhandled_input` rather than `_input` so the name field gets the key
## first — a `LineEdit` uses Escape to release focus.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		accept_event()
		_close()


# ══════════════════════════════════════════════════════════════════════════ UI
func _build() -> void:
	# ⚠ AN OPAQUE-ENOUGH GROUND, AND IT IS NOT DECORATION. The title screen's `_Sigil`
	# is a full-screen animated summoning circle; type laid straight on top of it has a
	# rune band drifting through it. 0.9 is dark enough to read against and light enough
	# that the circle is still visibly behind this rather than replacing it.
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(PAPER.r, PAPER.g, PAPER.b, 0.90)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)
	_col = col

	var head := Label.new()
	head.text = "YOUR REALM"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.label(head, HudStyle.LEAD, CHALK)
	col.add_child(head)

	col.add_child(_build_name_row())
	col.add_child(_build_cards())
	col.add_child(_build_actions())

	# ⚠ "Start Run" IS THE ONLY WAY A PARTY EVER ENTERS THE TOWER, and it used to live
	# on the title screen's collapsed co-op panel. That panel is no longer the door (see
	# `Lobby._open_realm`), so without this row a host could gather a friend and then
	# have nothing to press. Hidden until `is_host()` — `_refresh` owns that rule, the
	# same way `Lobby._refresh` owns it for the panel.
	# ⚠ THIS NOTE USED TO SAY "`›` (U+203A), NEVER `▸` (U+25B8)". THAT RULE IS DEAD, and
	# it is written out rather than deleted because it was emphatic and correct at the
	# time: the theme declared no Font resource and the repo shipped no font file, so
	# every control fell back to Godot's built-in Open Sans subset and anything past
	# Latin-1 drew as a zero-width nothing with no error. Ten of those shipped.
	#
	# 2026-09-07: the theme carries DejaVu Sans with `allow_system_fallback` off, which
	# covers `▸ ◂ █ ◆ ● ■ →` and the rest. `tools/slice_test_font_coverage.gd` is still
	# the gate and still asks the font the game actually resolves — it just passes now,
	# and it goes red if the font or that import setting is ever lost.
	_start_btn = _action("Start Run  ▸", func() -> void: start_pressed.emit())
	_start_btn.custom_minimum_size = Vector2(0, ACTION_H)
	_start_btn.add_theme_color_override("font_color", CHALK)
	_start_btn.visible = false
	col.add_child(_start_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.label(_status, HudStyle.SMALL, GRAPHITE)
	col.add_child(_status)

	var back: Button = _action("Back", _close)
	back.custom_minimum_size = Vector2(0, MIN_TAP)
	back.add_theme_color_override("font_color", GRAPHITE)
	col.add_child(back)


## THE NAME FIELD — the actual feature this screen exists to expose.
##
## ⚠ SAVED ON `focus_exited` AS WELL AS ON `text_submitted`, and the second one is the
## one that matters on the target platform. A phone has no Enter key in the way a
## keyboard does; a player types their name and then TAPS A BUTTON, which fires
## `focus_exited` and never `text_submitted`. Wiring only submit would mean the name was
## kept exactly when the player used a keyboard and silently dropped when they used a
## thumb.
func _build_name_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var caption := Label.new()
	caption.text = "YOU ARE"
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.label(caption, HudStyle.SMALL, GRAPHITE)
	row.add_child(caption)

	_name_edit = LineEdit.new()
	_name_edit.text = PlayerProfile.display_name()
	_name_edit.placeholder_text = "your name"
	# ⚠ THE ENGINE'S OWN CAP AS WELL AS THE SANITISER'S. `PlayerProfile.sanitize_name`
	# is the authority and truncates anyway, but `max_length` stops a 4000-character
	# paste from ever being MEASURED by the layout pass — a `LineEdit` widens its
	# container while it holds text, so the cap is a layout guard first and a data guard
	# second.
	_name_edit.max_length = PlayerProfile.MAX_NAME_CHARS
	_name_edit.custom_minimum_size = Vector2(0, MIN_TAP)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", HudStyle.BODY)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	row.add_child(_name_edit)
	return row


## Store what was typed, and PUT BACK what was actually stored. The two differ whenever
## the sanitiser did something — a trailing space, a pasted newline, a 40-character name
## capped to 16 — and a field that keeps showing the rejected text is a field that lies
## about what your friend is going to see.
func _commit_name() -> void:
	if _name_edit == null:
		return
	var stored: String = PlayerProfile.set_display_name(_name_edit.text)
	_name_edit.text = stored
	# The host's own row in the live table, if a session is already up. Hosting and THEN
	# renaming yourself is a normal order of operations on this screen.
	if _net != null and _net.is_active() and _net.has_method("name_of"):
		var table: Variant = _net.get("peer_name")
		if table is Dictionary:
			(table as Dictionary)[int(_net.my_id())] = stored
	_refresh()


## TWO SEATS, SIDE BY SIDE. Your character on the left, the joined peer on the right —
## which is the shape the maker asked for and also the only shape that fits: the cards
## are the one element here allowed to spend WIDTH, the axis that grows on a taller phone.
func _build_cards() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, CARD_H)

	var you := _card(HudStyle.AZURE)
	_you_name = _card_title(you, PlayerProfile.display_name())
	_you_class = _card_sub(you, "")
	_card_sub(you, "this device")
	row.add_child(you)

	var them := _card(HudStyle.GRAPHITE)
	_peer_name = _card_title(them, "waiting for a friend…")
	_peer_class = _card_sub(them, "")
	_peer_caption = _card_sub(them, "")
	row.add_child(them)
	return row


## ⚠ AN EMPTY SEAT MUST READ AS AN INVITATION, NOT AS A BUG. A right-hand card that is
## blank, or that says "Player 2 — —", is indistinguishable from a screen that failed to
## load. So the empty state is a sentence in the second person, and the accent is
## GRAPHITE rather than a class colour precisely so it reads as "not yet" rather than as
## "someone grey".
func _card(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", HudStyle.panel(accent))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	return p


func _card_title(card: PanelContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# ⚠ CLIPPED, NOT WRAPPED. An unwrapped, unclipped `Label` does not shrink — it
	# WIDENS ITS PARENT, which here means one long name pushes the other card off the
	# screen. (`slice_test_settings` has a whole test about that exact failure on the
	# settings page.) Clipping keeps the two seats the same size whatever arrives over
	# the wire, and the name is capped at 16 characters anyway.
	l.clip_text = true
	HudStyle.label(l, HudStyle.BODY, CHALK)
	(card.get_child(0) as VBoxContainer).add_child(l)
	return l


func _card_sub(card: PanelContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	HudStyle.label(l, HudStyle.SMALL, GRAPHITE)
	(card.get_child(0) as VBoxContainer).add_child(l)
	return l


## THE THREE VERBS, in one row. Three half-height rows stacked would cost 3 x 34 + two
## separations = 114 px of a 360-px screen; one row costs 34.
func _build_actions() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# ⚠ THE LABEL SAYS WHICH NETWORK IT IS ON. `Net.host()` starts a UDP beacon that
	# advertises this machine, so the other phone finds it under Join without anyone
	# reading an IP aloud — but only on the same wifi. Saying so on the button is the
	# difference between "co-op is broken" and "we are on different networks".
	row.add_child(_action("Host Co-op", func() -> void: host_pressed.emit()))
	row.add_child(_action("Join a Game", func() -> void: join_pressed.emit()))
	row.add_child(_action("Local Play", func() -> void: local_pressed.emit()))
	return row


func _action(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ACTION_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", HudStyle.SMALL)
	# A stray focus ring on a phone reads as a rendering bug — the same rule every other
	# screen in this game holds to, and `slice_test_shell` asserts it on the title.
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.pressed.connect(cb)
	return b


# ═══════════════════════════════════════════════════════════════════════ state
## Repaint from `Net`. Driven by `lobby_changed`, which fires on host, on a peer
## arriving, on a peer leaving and on either name table landing — so this is the one
## place that decides what the two cards say.
func _refresh(_a: Variant = null) -> void:
	if _you_name == null:
		return
	var me: int = 1
	var active: bool = false
	if _net != null:
		active = bool(_net.is_active())
		me = int(_net.my_id())

	_you_name.text = PlayerProfile.display_name()
	_you_class.text = _class_label(me)

	var other: int = _other_peer(me, active)
	if other > 0:
		_peer_name.text = _net.call("name_of", other)
		_peer_class.text = _class_label(other)
		_peer_caption.text = "in your realm"
	else:
		_peer_name.text = "waiting for a friend…"
		_peer_class.text = ""
		# ⚠ THE EMPTY SEAT TELLS YOU WHAT TO DO NEXT, and what that is depends on
		# whether you have started anything. "Nobody here" is a status; "Host, then they
		# tap you under Join" is an instruction.
		_peer_caption.text = "hosting — they find you under Join" if _is_hosting() \
			else "host, or join their game"

	if _start_btn != null:
		_start_btn.visible = _is_hosting()
	if _status != null and _status.text == "":
		_status.text = "a second player on this device presses A or START on a pad"


## The OTHER seat, or 0. `MAX_PLAYERS` is 2, so "the other one" is exact rather than a
## heuristic — the same reasoning `Net._announce_friendly_fire` relies on when it names
## the player who shot you.
func _other_peer(me: int, active: bool) -> int:
	if not active or _net == null:
		return 0
	for pid: Variant in _net.call("peers"):
		if int(pid) != me:
			return int(pid)
	return 0


func _is_hosting() -> bool:
	return _net != null and bool(_net.is_host())


## "Stormcaller", or "" for a seat whose class has not arrived yet. Reached through
## `ClassInfo`, which is a global CLASS and not an autoload, so it is safe to name.
func _class_label(peer_id: int) -> String:
	if _net == null or not _net.is_active():
		var gs: Node = get_node_or_null("/root/GameState")
		return ClassInfo.name_for(int(gs.get("selected_class"))) if gs != null else ""
	var table: Variant = _net.get("peer_class")
	if table is Dictionary and (table as Dictionary).has(peer_id):
		return ClassInfo.name_for(int(_net.call("class_of", peer_id)))
	return ""


## One line of feedback, written by the Lobby after it has acted on one of the signals
## above — this screen deliberately does not know whether a host succeeded.
func say(text: String) -> void:
	if _status != null:
		_status.text = text


func _close() -> void:
	closed.emit()
