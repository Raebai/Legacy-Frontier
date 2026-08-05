class_name Lobby
extends Control
## THE TITLE SCREEN — and the first thing anybody ever sees of THE TOWER.
##
## (`class_name` is here for one narrow reason: the `_Paper` inner class at the
## bottom draws with this script's palette constants, and an inner class can only
## reach them through a named outer scope.)
##
## Keeps everything the old orphaned lobby did (Play Solo / Host Co-op / Join by
## IP / class pick / live peer list / Start Run) and changes two things that
## mattered:
##
## 1. **CLIMB IS THE FIRST THING, AND IT STARTS A RUN.** It calls
##    `GameState.enter_run()`, which owns the persistent climb (resume from your
##    saved floor, never a blanket reset) and does the scene change itself. One
##    press from opening the game to fighting, and that is deliberately protected:
##    `slice_test_town` fails if anything is ever built above it.
##
##    THE TOWN IS BELOW IT, AS A DETOUR. "The Town" opens `scenes/Main.tscn` —
##    which is no longer the v0.0 AI village but the game's front door: a class
##    statue, a spell lectern, an armory rack, three townspeople who speak in
##    barks, and the tower door you spawn standing on. The LLM stack that used to
##    live in there (`Conversation`, the memory pipeline, the local model server)
##    is DELETED, not parked — see `World.gd` and `NPC.gd`.
##
## 2. **It looks like the game.** The backdrop is a SUMMONING CIRCLE opening —
##    the signature this project committed to, drawn live every boot and never
##    finishing. (It replaced a hand-drawn tower that stopped after 2.6 s and left
##    the screen a still image; see `_Sigil`.) The old note is kept below because
##    the LORE it describes is unchanged — you are a drawing climbing toward
##    whoever holds the pencil:
##    The tower was DRAWN — an unseen hand sketches
##    each floor, its mobs and its boss, and you are a drawing climbing toward
##    whoever holds the pencil. So the backdrop is not art, it is a tower being
##    drawn, live, in chalk, every time you open the game: crude scribbles at the
##    bottom, confident ink at the top. `_Paper` below does it in `_draw()` with
##    a seeded RNG, which is why it costs zero bytes of assets and never repeats
##    the same wobble twice.
##
## Built in code, house style (ClassSelect / Loadout / PauseMenu all do this).
## Laid out for the 640×360 base viewport in LANDSCAPE, with every tappable
## target at least 30 px tall in base units — which on any real phone is a
## comfortable thumb.

const CREDITS_SCENE: PackedScene = preload("res://scenes/ui/Credits.tscn")

# ── the look ────────────────────────────────────────────────────────────────
const PAPER: Color = Color(0.055, 0.052, 0.075)      # ink-dark sketchbook
const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)
const RULE: Color = Color(0.16, 0.17, 0.23)          # faint ruled lines
const ACCENT_FALLBACK: Color = Color(0.55, 0.9, 1.0)

const BUTTON_H: float = 30.0
const PANEL_W: float = 292.0

## FIXED height of the discovered-host list, in base units. This is the whole
## reason a variable-length list cannot break the layout: the ScrollContainer
## reports a minimum height of zero on its scrolling axis, so this constant — not
## the number of hosts on the network — decides how tall the join screen is. One
## host or nine, the panel measures the same.
const HOST_LIST_H: float = 104.0
## A discovered host is a tap target like any other.
const HOST_ROW_H: float = 32.0

## How often the host list is re-read while the join screen is open.
##
## `Net.hosts_changed` fires when a host APPEARS or when a full session drops
## off — but a host that simply walks away expires by TTL inside
## `discovered_hosts()`, with no signal. Signal-only would therefore leave a dead
## button on screen forever, and tapping it is a guaranteed failed join. So the
## signal drives the fast path and this poll sweeps the corpses.
const HOST_POLL: float = 1.0

var _net: Node = null
var _selected_class: int = 0
var _status: Label = null
var _peers_label: Label = null
var _class_btn: Button = null
var _class_kit: Label = null
var _ip_edit: LineEdit = null
var _start_btn: Button = null
var _paper: Control = null
var _credits: Control = null
var _free_btn: Button = null
## FIGHT A BOT. Held so the label can name the opponent you are about to get — see
## `_refresh_duel_button`.
var _duel_btn: Button = null
## THE OUTFITTER — choose your three / armory / colourway. An OVERLAY like the
## credits, not a scene change: the player is often mid-lobby with a peer connected,
## and dressing your hero must not drop them.
var _outfitter: Control = null
## The main menu column. Held so the suite can assert the whole panel still fits
## the 640×360 base viewport — the thing that silently breaks the first time
## somebody adds one more row.
var _col: VBoxContainer = null

# ── the join screen ─────────────────────────────────────────────────────────
## A SEPARATE column that swaps in for `_col`, rather than more rows appended to
## it. That is a layout decision, not a navigation one: the host list is
## variable-length, and the only way to promise it can never push the panel past
## 360 px is to give it a screen whose height does not depend on it.
var _join_col: VBoxContainer = null
var _host_list: VBoxContainer = null
var _host_scroll: ScrollContainer = null
var _join_status: Label = null
var _searching: bool = false
var _poll_t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_net = get_node_or_null("/root/Net")
	# The bark/voice observer normally installs itself from Sfx on the first
	# frame a scene exists. Re-ensuring it here is free and covers the maker's
	# other entry point: F6 straight into an arena scene, never through here.
	VoiceDirector.ensure(get_tree())

	_paper = _Sigil.new()
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paper)

	# THE CLASS COMES FROM THE STATUE NOW. The title has no cycler, so the last class
	# chosen in the Antechamber is the one this screen hosts with.
	var gs0: Node = get_node_or_null("/root/GameState")
	if gs0 != null:
		_selected_class = int(gs0.get("selected_class"))
	_build_ui()
	_apply_class_tint()
	# ⚠ THE BOOT SCREEN USED TO BE SILENT. The first thing anyone ever hears, and it
	# played nothing at all. Guarded lookup so a headless harness (which has no Music
	# autoload and no audio device) is unaffected.
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_title"):
		music.call("play_title")

	# Only LAN discovery needs a frame pump, and it is off until the join screen
	# opens (Net does the same thing for the same reason).
	set_process(false)

	if _net != null:
		_net.lobby_changed.connect(_refresh)
		_net.server_started.connect(_refresh)
		_net.join_ok.connect(_on_join_ok)
		_net.join_failed.connect(_on_join_failed)
	_refresh()
	_music_town()

	# A saved hand, if there is one to restore. No-op until `GameState.spell_roles`
	# exists — see the handoff note on `SpellLibrary.hydrate_from_state`.
	SpellLibrary.hydrate_from_state(get_node_or_null("/root/GameState"))
	_apply_class_tint()
	if _free_btn != null:
		_free_btn.visible = free_play_available()
	# ⚠ THE "new here?" ONBOARDING LINE IS DELETED, and it was worse than clutter —
	# it was WRONG. Maker: "remove that random new here text".
	#
	# It read "new here? Free Play has no enemies — just try your three spells" and
	# pointed at a Free Play BUTTON THAT IS NOT ON THIS SCREEN ANY MORE: free play
	# moved into the Antechamber's sparring ring when the title was cut from ten
	# buttons to three. So the one sentence of onboarding the screen could afford was
	# spending itself directing a new player to something they could not see.
	#
	# The status row it lived in still exists and is still used — by the join flow,
	# the host flow and the peer count, all of which say something true when they
	# say anything at all.

	# ⚠ PAY THE SPELL-SCRIPT COMPILE HERE, WHERE NOBODY IS FIGHTING.
	# `SpellCaster` reaches its 22 spectacle scripts by `load()` on a PATH rather
	# than `preload` — deliberately, so headless tooling can drive the dispatcher
	# without dragging autoload-referencing scenes into a compile. The cost is that
	# the FIRST time a player throws each spell, that script compiles DURING THE
	# CAST: worst first cast measured at 126 ms on desktop and 1411 ms summed across
	# the roster, which on a 3-5x slower phone is a 130-630 ms freeze landing
	# repeatedly through the first minute of play. After warming: worst 3.1 ms.
	#
	# THE TITLE SCREEN IS THE RIGHT PLACE because it is the one moment the player is
	# idle by design — the ~718 ms is spent while they read a class name, not while
	# they dodge. It is idempotent, so the arena calling it again costs nothing.
	SpellCaster.warm()


## Leaving the scene entirely must not leave a UDP socket bound and a per-frame
## pump running on the Net autoload — the autoload outlives this scene, so a
## missed teardown here leaks for the rest of the session.
func _exit_tree() -> void:
	_stop_discovery()


func _on_join_ok() -> void:
	# We are in a session now; there is nothing left to discover, and holding the
	# listener open would keep pumping Net every frame through the whole run.
	_stop_discovery()
	# ⚠ WAIT IN THE ROOM, NOT ON THE TITLE SCREEN. Maker: "a teammate spawns into the
	# antechamber with you". A client used to sit on this menu reading "waiting for
	# the host" until the run started, so the two players never occupied the same
	# space until they were already fighting.
	var gsj: Node = get_node_or_null("/root/GameState")
	if gsj != null:
		gsj.set("session_kind", 2)   # SessionKind.ONLINE
		if gsj.has_method("visit_hub") and bool(gsj.call("visit_hub")):
			return
	_say("connected — waiting for the host")


func _on_join_failed() -> void:
	_say("no answer. check the address, or pick a game above.")


# ══════════════════════════════════════════════════════════════════════ UI
func _build_ui() -> void:
	# The panel hugs the RIGHT so the drawn tower on the left is never covered,
	# and so both thumbs land near the controls in landscape.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.custom_minimum_size = Vector2(PANEL_W, 0)
	right.add_theme_constant_override("separation", 3)
	margin.add_child(right)
	_col = right

	var title := Label.new()
	title.text = "ASHPIRE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", CHALK)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	right.add_child(title)

	# ⚠ TWO TAGLINES DELETED, AND ONE OF THEM HAD AN ARGUMENT BEHIND IT.
	#
	# "someone is drawing this" was a mood line under the logo. "friendly fire is
	# always on" was a deliberate signpost — the two games that ship friendly fire and
	# keep their reception both say so up front, and Frozenbyte publicly called NOT
	# advertising it in Nine Parchments "a clear mistake on their part".
	#
	# Both are gone anyway. Maker, on the title screen: "remove the 'someone is
	# drawing this' and 'something always on' lines, it's corny." The reasoning for
	# the second one is preserved here rather than in the argument it lost: if
	# friendly fire ever needs announcing again, the place for it is the moment it
	# first hurts somebody — a bark, in the fight — not a caption on the front door.

	# ── class ──
	# THE CLASS IS PICKED AT THE STATUE, in the room, on a body you can see. A cycler
	# here was choosing a hero for a fight you had not walked to yet.

	# ── the one button that matters ──
	# ⚠ TWO VERBS, NOT EIGHT BUTTONS. Maker: "there should be an Enter the tower
	# button and a multiplayer Button… like make it way simpler and less buttons and
	# less confusing".
	#
	# ENTER THE TOWER is the whole game and gets the big row. Everything else is
	# either a way to bring a friend (the MULTIPLAYER row) or something you do before
	# you climb (the PREPARE row) — labelled, so the screen answers "what is this
	# group for" instead of presenting eight equal choices.
	var play := _button("ENTER THE TOWER  ▸", _play_solo, 19)
	play.custom_minimum_size = Vector2(PANEL_W, BUTTON_H + 8.0)
	play.add_theme_color_override("font_color", CHALK)
	right.add_child(play)

	# ── PREPARE: the safe room, and everything you decide before you climb ──
	#
	# ⚠ HEIGHT IS THE BINDING CONSTRAINT ON THIS SCREEN, not space on the page. The
	# column measured 306 px of a 360 px viewport before these existed, with 20 px of
	# margin and a hidden "Start Run" row that appears when you host — so there was
	# room for ONE more full-width row and this needed TWO. Pairing the four secondary
	# actions into two HBox rows costs exactly what the two stacked rows they replace
	# cost, so the panel is the same height it was and `slice_test_shell`'s 360 px
	# bound is untouched. Both halves still clear MIN_TAP.
	# ⚠ EVERY PREP BUTTON MOVED INTO THE ANTECHAMBER. Maker, twice: "the tower intro
	# still has too many buttons… and again its too many buttons", plus "I want to
	# choose my class in the antechamber".
	#
	# The room already owns all of it and always did — the STATUE is class select, the
	# RACK is the armoury, the LECTERN is your three spells, the RING is free play and
	# the DOOR is the tower. Duplicating them as buttons here meant the title screen
	# was a menu for a room you were about to walk into anyway, and the room could
	# never be the front door while its own contents were listed on the doorstep.
	#
	# What is left is the only question a title screen has to ask: alone, or with
	# someone.
	right.add_child(_group_label("MULTIPLAYER"))
	var coop := HBoxContainer.new()
	coop.add_theme_constant_override("separation", 6)
	right.add_child(coop)
	# LOCAL and ONLINE side by side, which is the split the maker asked for. Local
	# routes through the same host path on the loopback — one code path, and the
	# only honest one until a second gamepad is actually wired.
	coop.add_child(_half("Host Co-op", _host))
	coop.add_child(_half("Join a Game", _open_join))

	_start_btn = _button("Start Run", _start_run, 15)
	_start_btn.visible = false
	right.add_child(_start_btn)

	# Paired into ONE row rather than stacked, because the column measures 306 of
	# 360 px and a stacked pair would blow the budget the layout suite pins.
	var extras := HBoxContainer.new()
	extras.add_theme_constant_override("separation", 6)
	right.add_child(extras)
	# WATCH BOTS FIGHT — two AI heroes on the versus stage with the clip camera on.
	# It is a spectator mode and a content tool at once: the maker wants bot-vs-bot
	# fights recorded as short clips, and ClipDirector already scores the board and
	# frames the decisive beat. Reached by path + static call for the same reason
	# Free Play is — a bare identifier drags the versus arena's dependency chain
	# into the title screen's compile.
	# ⚠ THE TOWN IS A DETOUR, NOT THE ROUTE. It sits three rows below CLIMB, in the
	# secondary row, because the fast path must stay the FIRST thing a thumb lands
	# on: nobody who wants to fight is ever taken on a tour. Going through the town
	# costs one extra press over CLIMB and no walking at all — you spawn on the
	# tower's doorstep and every station is behind you. See the rules at the top of
	# `World.gd`.
	# ⚠ THIS BUTTON WAS DELETED AND `_watch_bots` WAS LEFT WITH ZERO CALLERS. The
	# twelve lines of comment above survived the cut, so the file went on describing a
	# feature nothing could reach: there has been NO in-game route to a bot fight at
	# all. `scenes/combat/BotMatch.tscn` is referenced only by `tools/` and the test
	# suites, and the note claiming free play "moved into the Antechamber's sparring
	# ring" is also stale — `ArmoryStation` deleted the `"sparring"` kind and `World`
	# builds no such station.
	#
	# It goes back because the maker's stated goal for this mode is to record duels to
	# share, and a content tool nobody can open from the game is a command-line script.
	extras.add_child(_half("Watch Bots", _watch_bots))
	extras.add_child(_half("Credits", _open_credits))

	# The status row exists anyway and is empty at boot, so it is a free place to say
	# what the safe button is — the one sentence of onboarding this screen can afford.
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 10)
	_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	right.add_child(_status)
	_peers_label = Label.new()
	_peers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_peers_label.add_theme_font_size_override("font_size", 10)
	_peers_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	right.add_child(_peers_label)

	_build_join_screen(margin)


## THE JOIN SCREEN — "two phones in one room", which is the spec's whole
## multiplayer picture and is emphatically not "type an IP address".
##
## `Net` already does the hard half: `host()` starts a UDP broadcast beacon
## automatically, and a full session stops listing itself so a discovered host is
## never a guaranteed-failed join. This is the last mile — turning that list into
## something a thumb can hit.
##
## The manual address field SURVIVES, deliberately. Broadcast is blocked on a lot
## of hotel, campus and guest wifi, and when discovery finds nothing a typed
## address is the difference between "co-op is broken" and "co-op needs one more
## tap".
func _build_join_screen(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_theme_constant_override("separation", 4)
	col.visible = false
	parent.add_child(col)
	_join_col = col

	var head := Label.new()
	head.text = "FIND A GAME"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", CHALK)
	col.add_child(head)

	_join_status = Label.new()
	_join_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.add_theme_font_size_override("font_size", 10)
	_join_status.add_theme_color_override("font_color", GRAPHITE)
	col.add_child(_join_status)

	# THE BOUND. A ScrollContainer reports zero minimum size on whatever axis it
	# scrolls, so the panel's height is this constant and nothing else — nine
	# hosts measure exactly the same as one. Without it, the list is the one
	# control on this screen whose size is decided by the local network.
	_host_scroll = ScrollContainer.new()
	_host_scroll.custom_minimum_size = Vector2(PANEL_W, HOST_LIST_H)
	_host_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_host_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(_host_scroll)

	_host_list = VBoxContainer.new()
	_host_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_list.add_theme_constant_override("separation", 3)
	_host_scroll.add_child(_host_list)

	var or_line := Label.new()
	or_line.text = "or type the host's address"
	or_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_line.add_theme_font_size_override("font_size", 9)
	or_line.add_theme_color_override("font_color", GRAPHITE)
	col.add_child(or_line)

	var manual := HBoxContainer.new()
	manual.alignment = BoxContainer.ALIGNMENT_CENTER
	manual.add_theme_constant_override("separation", 6)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "host address"
	_ip_edit.custom_minimum_size = Vector2(PANEL_W - 96.0, BUTTON_H)
	_ip_edit.add_theme_font_size_override("font_size", 13)
	manual.add_child(_ip_edit)
	var join_btn := _button("Join", _join, 14)
	join_btn.custom_minimum_size = Vector2(88, BUTTON_H)
	manual.add_child(join_btn)
	col.add_child(manual)

	col.add_child(_button("Back", _close_join, 12))


# ══════════════════════════════════════════════════════════════════ actions
func _cycle_class() -> void:
	# Derived from the real roster, NEVER a hardcoded count. A literal `% 8` made
	# the 9th class (the Swordsaint) unselectable in co-op the moment it was
	# added — and it failed SILENTLY: the button simply never reached it, so the
	# class looked missing rather than unreachable. Any future class is now
	# selectable for free.
	_selected_class = (_selected_class + 1) % maxi(ClassInfo.count(), 1)
	_apply_class_tint()
	_sfx("ding", -6.0)


func _apply_class_tint() -> void:
	var i: int = clampi(_selected_class, 0, maxi(ClassInfo.count() - 1, 0))
	var info: Dictionary = ClassInfo.CLASSES[i] if i < ClassInfo.CLASSES.size() else {}
	var accent: Color = ClassInfo.color_for(i) if ClassInfo.count() > 0 else ACCENT_FALLBACK
	if _class_btn != null:
		_class_btn.text = "◂  %s  ▸" % String(info.get("name", "Class %d" % i))
		_class_btn.add_theme_color_override("font_color", accent)
		_class_btn.add_theme_color_override("font_hover_color", accent.lightened(0.25))
	if _class_kit != null:
		# ONE line, not two. The panel has to clear 360 px of height with the co-op
		# "Start Run" row also showing, and the two-line blurb was the row that
		# pushed it over. The kit is the useful half — it is what you are about to
		# play with; the fantasy tagline is flavour you can read on the class card.
		#
		# And it is now the LIVE hand rather than the authored blurb, because the hand
		# is a choice: `ClassInfo.kit` is a fixed sentence and the Outfitter can change
		# what you actually carry, so reading the class card here would start lying the
		# first time anybody used the Loadout button. Falls back to the blurb for a
		# class the spell library has no kit for.
		_class_kit.text = _hand_line(i)
	if _paper != null:
		_paper.set("accent", accent)
		_paper.queue_redraw()
	# The duel opponent is derived from YOUR pick (it refuses to be a mirror), so the
	# tooltip has to be re-derived every time the class cycler moves.
	_refresh_duel_button()


## The three spells this class is CARRYING right now, as one line. Derived from the
## same call the hero makes (`SpellLibrary.build_for_class`), so what the title screen
## says you are about to play with is what you are about to play with.
func _hand_line(class_id: int) -> String:
	var names: Array = []
	for spell: Variant in SpellLibrary.build_for_class(class_id):
		if spell != null:
			names.append(String((spell as SpellDef).display_name))
	if names.is_empty():
		var info: Dictionary = ClassInfo.CLASSES[class_id] if class_id < ClassInfo.CLASSES.size() else {}
		return String(info.get("kit", ""))
	return "  ·  ".join(names)


## THE ENTRY POINT. `GameState.enter_run()` owns the persistent climb — it
## resumes the saved floor rather than resetting to 1, restores banked rank
## power, and performs the scene change into the arena itself. Reached through
## the tree rather than the bare `GameState` identifier so this script stays
## loadable in a headless harness with no autoloads registered.
## ⚠ ENTER THE TOWER NOW LANDS IN THE ANTECHAMBER, NOT STRAIGHT IN A FIGHT.
##
## This deliberately supersedes the older "one press from opening the game to
## fighting" rule that `slice_test_town` was written to protect. The maker asked
## for the opposite in the 2026-08-04 brief: "once you enter the tower you go to
## the lobby area where you can resume your journey".
##
## THE FAST PATH SURVIVES ANYWAY, and that is why this is not a real cost: the
## Antechamber spawns you ON the tower door (`World.PLAYER_SPAWN` is 54 px from
## it), so it is still one press to descend once you are there. The room is
## something you may walk INTO, not something you are walked THROUGH.
func _play_solo() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		_say("the tower is missing. (GameState unavailable)")
		return
	gs.set("session_kind", 0)   # SessionKind.SOLO
	gs.set("selected_class", _selected_class)
	_stop_discovery()
	# The room is the front door. Falls back to starting the run outright on a build
	# with no town, so a missing scene cannot strand a player on the title screen.
	if gs.has_method("visit_hub") and bool(gs.call("visit_hub")):
		_say("entering...")
		return
	if not gs.has_method("enter_run"):
		_say("the tower is missing. (GameState unavailable)")
		return
	# We are about to leave this scene. `_exit_tree` catches it too, but doing it
	# here means the socket is closed BEFORE the arena starts loading rather than
	# during it.
	_stop_discovery()
	gs.set("selected_class", _selected_class)
	_say("climbing...")
	gs.call("enter_run")


## FREE PLAY — the stage, you, and nothing else. No enemies, no waves, no run, no way
## to lose; move, jump, dash, throw all three spells, break the cover, fall off the
## rim and come straight back.
##
## Reached by PATH and a static call rather than the bare `FreePlay` identifier, for
## the reason that file documents about itself: it is one hop from the versus arena
## and its dependency chain, and a hard reference here would drag that whole chain
## into the compile of the boot scene. The by-path form also means a build without the
## script simply hides the button instead of failing to load the title screen.
const FREE_PLAY_SCRIPT: String = "res://scripts/combat/FreePlay.gd"


func free_play_available() -> bool:
	return ResourceLoader.exists(FREE_PLAY_SCRIPT)


func _free_play() -> void:
	if not free_play_available():
		_say("free play is missing from this build.")
		return
	_stop_discovery()
	# The same class you picked on this screen, and recorded where everything else
	# reads it from — so walking out of free play into a run keeps your choice.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("selected_class", _selected_class)
	var script: GDScript = load(FREE_PLAY_SCRIPT) as GDScript
	if script == null:
		_say("free play failed to load.")
		return
	_say("warming up...")
	script.call("enter", get_tree(), _selected_class)


## WATCH BOTS FIGHT — two AI heroes on the versus stage, with `ClipDirector` scoring
## the board and framing the decisive beat. Spectator mode and content tool at once.
##
## By path and static call for exactly the reason free play is: a bare `BotMatch`
## identifier would drag the versus arena's dependency chain into the title screen's
## compile, and by-path means a build without the script hides the button rather
## than failing to load the boot scene.
const BOT_MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"


func bot_match_available() -> bool:
	return ResourceLoader.exists(BOT_MATCH_SCRIPT)


func _watch_bots() -> void:
	if not bot_match_available():
		_say("the bot arena is missing from this build.")
		return
	_stop_discovery()
	var script: GDScript = load(BOT_MATCH_SCRIPT) as GDScript
	if script == null:
		_say("the bot arena failed to load.")
		return
	# ROLL THE MATCHUP. This button existed to show off the roster and opened the
	# same STORMCALLER vs CRYOMANCER every single time, because that is what the
	# statics default to. Pressing it twice showed one fight twice.
	script.set("random_matchup", true)
	_say("finding a fight...")
	script.call("enter", get_tree())


## FIGHT A BOT — the maker, with their own hands, against ONE bot hero, on the versus
## stage. `VersusArena`'s duel mode is a COMPLETE, shipped feature (mirrored spawns, a
## learning bot, a difficulty tier, a rematch grace) and until now the only way to reach
## it was to open the scene in the editor and press F6. `FreePlay.gd`'s header says so
## outright. This is the missing button.
##
## By path + `load()` + static `set()`, exactly like Free Play and Watch Bots above, and
## for the same reason: a bare `VersusArena` identifier here would compile that class —
## and its whole autoload-touching dependency chain — at the BOOT SCREEN's parse time.
const VERSUS_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const VERSUS_SCRIPT: String = "res://scripts/combat/VersusArena.gd"
## The tier a duel opens on when nothing sane is already set. 1 = Normal in
## `BotProfile.Tier`, which is `VersusArena.duel_difficulty`'s own shipped default.
const DUEL_DEFAULT_TIER: int = 1


func versus_available() -> bool:
	return ResourceLoader.exists(VERSUS_SCRIPT) and ResourceLoader.exists(VERSUS_SCENE)


## ⚠ THE DUEL IS THE ARENA'S DEFAULT MODE — BUT ONLY IF THE STATICS ARE CLEAN, AND THEY
## ARE ROUTINELY NOT. `VersusArena._is_duel()` is literally "not a showcase", so all
## three of these have to be put back by hand before the scene change:
##
##   * `showcase_a` / `showcase_b` — `BotMatch` sets them to two class ids. It does
##     clear them in its own `_exit_tree`, but this screen must not depend on somebody
##     else's teardown having run to hand the player the mode they asked for.
##   * `free_play` — same story with `FreePlay`. Belt and braces, one line, and the
##     failure it prevents (you press "Fight a Bot" and get an empty sandbox with no
##     opponent) is silent and two scenes away from its cause.
##
## `duel_human` is set for completeness; it no longer decides anything (see the DUEL
## block in `VersusArena`), but leaving one of a mode's four knobs unstated is how the
## next person reading this concludes it is not needed.
func _fight_bot() -> void:
	if not versus_available():
		_say("the duel stage is missing from this build.")
		return
	var script: GDScript = load(VERSUS_SCRIPT) as GDScript
	if script == null:
		_say("the duel stage failed to load.")
		return
	_stop_discovery()
	# Your class, recorded where the hero reads it from — `VersusArena._spawn_duel`
	# builds the human from `GameState.selected_class`, so without this you fight as
	# whatever you last played rather than as whatever the button above says.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("selected_class", _selected_class)
	script.set("showcase_a", -1)
	script.set("showcase_b", -1)
	script.set("free_play", false)
	script.set("duel_human", true)
	script.set("duel_bot_class", duel_opponent())
	script.set("duel_difficulty", duel_tier())
	_say("stepping up...")
	get_tree().paused = false
	get_tree().change_scene_to_file(VERSUS_SCENE)


## WHO YOU FIGHT. Whatever the arena's own knob is already set to — the maker can cycle
## it from the pause menu mid-fight ("Bot Duel → bot class") and that choice must
## survive a trip back to the title screen — EXCEPT when it would hand you a mirror of
## your own pick, which is the one matchup nobody wants by accident. Falls back to the
## next class along, which is always a different one.
func duel_opponent() -> int:
	var n: int = maxi(ClassInfo.count(), 1)
	var script: GDScript = load(VERSUS_SCRIPT) as GDScript
	var current: Variant = script.get("duel_bot_class") if script != null else null
	var bot: int = int(current) if current != null else 0
	bot = posmod(bot, n)
	if bot == posmod(_selected_class, n) and n > 1:
		bot = (bot + 1) % n
	return bot


## ...and at what tier. Preserved the same way, sanitised into 0..3 so a knob left in a
## bad state by a capture tool cannot follow the player into a fight.
func duel_tier() -> int:
	var script: GDScript = load(VERSUS_SCRIPT) as GDScript
	var current: Variant = script.get("duel_difficulty") if script != null else null
	if current == null:
		return DUEL_DEFAULT_TIER
	var tier: int = int(current)
	return tier if tier >= 0 and tier <= 3 else DUEL_DEFAULT_TIER


## The button names its opponent. There is no room on this screen for a fourth row and
## no second press to spend on a cycler, so the tooltip is where the "you can change
## this" lives — the arena's own pause menu already cycles the bot's class and tier, and
## `duel_opponent()` preserves whatever it was left on.
func _refresh_duel_button() -> void:
	if _duel_btn == null:
		return
	_duel_btn.visible = versus_available()
	if not _duel_btn.visible:
		return
	_duel_btn.tooltip_text = "1v1 against %s — Esc in the fight changes the bot + tier" \
		% ClassInfo.name_for(duel_opponent())


## THE OUTFITTER. Everything you decide before you climb: which three of your class's
## five spells you carry, the armory, and your colourway. An overlay, aimed at the
## class currently selected on this screen.
func _open_outfitter() -> void:
	if _outfitter != null and is_instance_valid(_outfitter):
		return
	_outfitter = Outfitter.new()
	add_child(_outfitter)
	_outfitter.call("set_class", _selected_class)
	if _outfitter.has_signal(&"closed"):
		_outfitter.connect(&"closed", _on_outfitter_closed)


func _on_outfitter_closed() -> void:
	if _outfitter != null and is_instance_valid(_outfitter):
		_outfitter.queue_free()
	_outfitter = null
	# The kit line under the class button is a summary of the hand, and the hand may
	# have just changed underneath it.
	_apply_class_tint()


func _host() -> void:
	if _net == null:
		return
	# You cannot listen for other people's games while running your own; Net.host()
	# starts the beacon that advertises THIS session instead.
	_stop_discovery()
	# The room needs to know this is a party BEFORE anyone connects — see
	# `GameState.session_kind`.
	var gs2: Node = get_node_or_null("/root/GameState")
	if gs2 != null:
		gs2.set("session_kind", 2)   # SessionKind.ONLINE
	var err: int = _net.host(_selected_class)
	if err == OK:
		# The beacon is automatic (Net.host starts it), so the other phone should
		# simply see this machine in its list — the address is the fallback.
		_say("hosting — they should see you under Join a Game")
		# The host waits in the room as well, so the Party Stone is somewhere both
		# players are standing rather than a thing only one of them ever sees.
		var gsh: Node = get_node_or_null("/root/GameState")
		if gsh != null and gsh.has_method("visit_hub"):
			gsh.call("visit_hub")
	else:
		_say("host failed (err %d) — port in use?" % err)


func _join() -> void:
	if _net == null:
		return
	var err: int = _net.join(_ip_edit.text.strip_edges(), _selected_class)
	_say(("reaching %s..." % _ip_edit.text) if err == OK else ("join error %d" % err))


# ═════════════════════════════════════════════════════════════ LAN discovery
## Enter the join screen and start listening for beacons.
func _open_join() -> void:
	if _join_col == null:
		return
	_col.visible = false
	_join_col.visible = true
	_start_discovery()
	_redraw_hosts()


## Leave it, and stop listening. Discovery holds a bound UDP socket and a per-frame
## pump on `Net`; leaving it running because the player wandered back to the title
## is exactly the kind of thing that quietly costs battery on a phone.
func _close_join() -> void:
	_stop_discovery()
	if _join_col != null:
		_join_col.visible = false
	if _col != null:
		_col.visible = true


func _start_discovery() -> void:
	if _net == null or _searching:
		return
	if not _net.has_method("start_discovery"):
		_join_status.text = "this build has no LAN discovery — type the address below."
		return
	var err: int = int(_net.call("start_discovery"))
	if err != OK:
		# Broadcast is blocked on plenty of guest wifi, and the listen port can
		# already be taken. Say so plainly and point at the fallback rather than
		# leaving an empty list that reads as "nobody is playing".
		_searching = false
		_join_status.text = "can't search this network (err %d) — type the address below." % err
		return
	_searching = true
	_poll_t = HOST_POLL
	if _net.has_signal(&"hosts_changed") and not _net.is_connected(&"hosts_changed", _redraw_hosts):
		_net.connect(&"hosts_changed", _redraw_hosts)
	set_process(true)


func _stop_discovery() -> void:
	if _net == null:
		return
	if _net.has_signal(&"hosts_changed") and _net.is_connected(&"hosts_changed", _redraw_hosts):
		_net.disconnect(&"hosts_changed", _redraw_hosts)
	if _searching and _net.has_method("stop_discovery"):
		_net.call("stop_discovery")
	_searching = false
	set_process(false)


## The sweep the signal cannot do. `Net.hosts_changed` fires on arrival and when a
## full session drops off, but a host that simply leaves expires by TTL inside
## `discovered_hosts()` and emits nothing — so a signal-only list keeps a dead
## button on screen indefinitely, and tapping it is a guaranteed failed join.
func _process(delta: float) -> void:
	if not _searching:
		set_process(false)
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = HOST_POLL
		_redraw_hosts()


## Rebuild the list. Cheap (at most a handful of rows, at most once a second) and
## far simpler than diffing, which for a two-player game would be more code than
## the feature.
func _redraw_hosts(_a = null) -> void:
	if _host_list == null:
		return
	for child: Node in _host_list.get_children():
		# Removed BEFORE freeing: queue_free defers to the end of the frame, so a
		# row left parented would still be measured by the layout pass that runs
		# in between and the list would flicker one row taller.
		_host_list.remove_child(child)
		child.queue_free()
	var hosts: Array = []
	if _net != null and _net.has_method("discovered_hosts"):
		hosts = _net.call("discovered_hosts")
	if hosts.is_empty():
		if _searching:
			_join_status.text = "looking for games on this wifi..."
		return
	_join_status.text = "%d game%s nearby — tap to join" % [hosts.size(), "" if hosts.size() == 1 else "s"]
	for entry: Dictionary in hosts:
		_host_list.add_child(_host_row(entry))


## One discovered host, as a thumb-sized button.
func _host_row(entry: Dictionary) -> Button:
	var ip: String = String(entry.get("ip", ""))
	var port: int = int(entry.get("port", _default_port()))
	var host_name: String = String(entry.get("name", ip))
	var b := Button.new()
	b.text = "▸  %s" % host_name
	# The address is the tie-breaker when two machines share a name, which on a
	# home network is not unusual. Small, secondary, always present.
	b.tooltip_text = "%s:%d" % [ip, port]
	b.custom_minimum_size = Vector2(PANEL_W - 16.0, HOST_ROW_H)
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.pressed.connect(_join_discovered.bind(ip, port, host_name))
	return b


## The port comes from the BEACON, not from a constant here: the host advertises
## the port it is actually listening on, and hardcoding `DEFAULT_PORT` would break
## the moment anyone hosts on a second port to test two sessions on one machine.
func _join_discovered(ip: String, port: int, host_name: String) -> void:
	if _net == null or not _net.has_method("join"):
		return
	var err: int = int(_net.call("join", ip, _selected_class, port))
	_say(("joining %s..." % host_name) if err == OK
		else ("could not reach %s (err %d)" % [host_name, err]))


func _default_port() -> int:
	if _net != null:
		var p: Variant = _net.get("DEFAULT_PORT")
		if p != null and (p is int):
			return int(p)
	return 24565


## One line of feedback, written to whichever screen is actually in front of the
## player. Without this, a join started from the discovery list reports into the
## title screen's status label, which is hidden at the time.
func _say(text: String) -> void:
	if _join_col != null and _join_col.visible and _join_status != null:
		_join_status.text = text
	if _status != null:
		_status.text = text


func _start_run() -> void:
	_stop_discovery()
	if _net != null and _net.has_method("start_coop_run"):
		_net.start_coop_run()   # Net broadcasts the scene change + run state to all peers


## Credits are an OVERLAY, not a scene change: hosting a lobby and then reading
## the credits must not drop the peer you were waiting for.
## THE TOWN — where you change class, pick which three spells you carry, take gear
## off the rack, choose a colourway, and talk to the three people who live there.
##
## Routed through `GameState.visit_hub()` rather than a `change_scene_to_file` here,
## because the mode flag it sets is what tells the rest of the game you are not in a
## run. Falls back to nothing if the town is not in this build, rather than throwing
## the player at a black screen.
func _visit_town() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("visit_hub") and bool(gs.call("visit_hub")):
		return
	_say("the town isn't in this build.")


func _open_credits() -> void:
	if _credits != null and is_instance_valid(_credits):
		return
	_credits = CREDITS_SCENE.instantiate()
	add_child(_credits)
	if _credits.has_signal(&"closed"):
		_credits.connect(&"closed", _on_credits_closed)


func _on_credits_closed() -> void:
	if _credits != null and is_instance_valid(_credits):
		_credits.queue_free()
	_credits = null


func _refresh(_a = null) -> void:
	if _net == null:
		return
	var hosting: bool = _net.is_host()
	_start_btn.visible = hosting
	if _net.is_active():
		var ids: Array = _net.peers()
		_peers_label.text = "%d in the party" % ids.size()
	else:
		_peers_label.text = ""


# ══════════════════════════════════════════════════════════════════ helpers
func _button(text: String, cb: Callable, font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(PANEL_W, BUTTON_H)
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE   # a stray focus ring on a phone reads as a bug
	b.pressed.connect(cb)
	_make_alive(b)
	return b


## ══ THE BUTTONS ANSWER YOU ═══════════════════════════════════════════════════
## Maker, 2026-08-04: "have the buttons glow and like interact with the user".
##
## A Godot `Button` with no styling is a grey rectangle that changes shade slightly
## on hover, which on a dark screen reads as nothing happening. Four channels are
## wired here and they cost nothing at rest:
##
##   * **HOVER / PRESS GLOW** — a real `StyleBoxFlat` per state, bordered in the
##     class accent, so the button LIGHTS rather than merely tinting.
##   * **LIFT** — a small scale-up on hover. `pivot_offset` is re-centred on resize,
##     because a Control scales about its top-left by default and an un-pivoted
##     button grows to the right instead of swelling in place.
##   * **PUNCH** — a snap down on press and a spring back on release, which is the
##     half that makes a touch feel ACKNOWLEDGED on a device with no hover at all.
##   * **SOUND** — the existing UI cue, so the screen is audible as well as visible.
##
## ⚠ TOUCH HAS NO HOVER, so press/release carry the whole effect on the target
## platform and are wired separately rather than as a hover variant.
## ⚠ IDEMPOTENT. `_restyle_buttons` re-runs this on every class-accent change, and
## a signal connected a second time fires a second time — two tweens racing the
## same property, and the scale settling wherever the loser happened to stop. The
## SKIN is re-applied every call (that is the point); the WIRING happens once.
func _make_alive(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _btn_style(0.0))
	b.add_theme_stylebox_override("hover", _btn_style(1.0))
	b.add_theme_stylebox_override("pressed", _btn_style(1.0, true))
	b.add_theme_stylebox_override("focus", _btn_style(0.6))
	if b.has_meta("alive"):
		return
	b.set_meta("alive", true)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	# ⚠ NO HOVER SOUND. There is no UI tick in `Sfx`'s key table — every candidate is
	# a combat cue — and inventing a key plays silence rather than failing loudly.
	# The press already carries audio through each action's own handler.
	b.mouse_entered.connect(func() -> void: _btn_scale(b, 1.035))
	b.mouse_exited.connect(func() -> void: _btn_scale(b, 1.0))
	b.button_down.connect(func() -> void: _btn_scale(b, 0.965, 0.06))
	b.button_up.connect(func() -> void: _btn_scale(b, 1.0, 0.16))


## One tween per button, killed before the next starts — without that, a fast
## mouse over a row of buttons stacks tweens on the same property and the scale
## settles wherever the last one happened to finish.
func _btn_scale(b: Button, to: float, time: float = 0.11) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var prev: Variant = b.get_meta("scale_tween", null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	b.pivot_offset = b.size * 0.5
	var tw: Tween = b.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK if to > 1.0 else Tween.TRANS_QUAD)
	tw.tween_property(b, "scale", Vector2(to, to), time)
	b.set_meta("scale_tween", tw)


## The button's skin at a given glow strength. Built rather than themed because the
## accent follows the player's CLASS and has to be re-applied when that changes.
func _btn_style(glow: float, pressed: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var a: Color = _accent_now()
	sb.bg_color = Color(a.r * 0.16, a.g * 0.16, a.b * 0.20, 0.42 + 0.30 * glow)
	if pressed:
		sb.bg_color = Color(a.r * 0.30, a.g * 0.30, a.b * 0.34, 0.90)
	sb.border_color = Color(a.r, a.g, a.b, 0.28 + 0.62 * glow)
	sb.set_border_width_all(1 if glow < 0.5 else 2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	# The glow itself. A shadow in the accent colour with no offset reads as light
	# coming OFF the button rather than as a drop shadow under it.
	sb.shadow_color = Color(a.r, a.g, a.b, 0.34 * glow)
	sb.shadow_size = int(round(9.0 * glow))
	return sb


func _accent_now() -> Color:
	var gs: Node = get_node_or_null("/root/GameState")
	var idx: int = int(gs.get("selected_class")) if gs != null else 0
	return ClassInfo.color_for(idx)


## Re-skin every button when the class accent changes, or the glow stays the
## previous class's colour until the scene is rebuilt.
func _restyle_buttons(node: Node) -> void:
	for c: Node in node.get_children():
		if c is Button:
			_make_alive(c as Button)
		_restyle_buttons(c)


## Half a row. Two of these in an HBox occupy exactly the height of one full-width
## button, which is the entire reason four secondary actions fit where two did.
func _half(text: String, cb: Callable) -> Button:
	var b: Button = _button(text, cb, 13)
	b.custom_minimum_size = Vector2(PANEL_W * 0.5 - 3.0, BUTTON_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _sfx(key: String, db: float = 0.0) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s != null and s.has_method("play"):
		s.call("play", key, db)


## ⚠ THE TITLE BED, NOT THE TOWN BED — and this function is why the title screen
## was silent even after `Mood.TITLE` existed. `_ready` starts the title track and
## then this ran a few lines later and replaced it with the town's, so the boot
## screen played the ambience of a room you are not in. Falls back to the town bed
## on a build that predates `play_title`.
func _music_town() -> void:
	var m: Node = get_node_or_null("/root/Music")
	if m == null:
		return
	if m.has_method("play_title"):
		m.call("play_title")
	elif m.has_method("play_town"):
		m.call("play_town")


## A quiet caption over a group of buttons. The title screen's problem was never
## the NUMBER of things on it so much as that eight buttons all looked equally
## important; naming the two groups answers "what is this for" before a thumb has
## to guess.
func _group_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", GRAPHITE)
	return l


# ═══════════════════════════════════════════════════════════ THE SUMMONING SIGIL
## THE BACKDROP: A MAGIC CIRCLE OPENING, FOREVER.
##
## Maker, 2026-08-04: "change that weird tower thing to a cool ass animation like
## a slow magic circle opening up with some elements coming out of it something
## awesome like that".
##
## ⚠ IT IS THE GAME'S OWN SIGNATURE, NOT A NEW IDEA. The summoning circle is the
## thing this project has committed to as its look — every cast in the game opens
## one — so the title screen draws the same grammar rather than a decoration that
## appears nowhere else: an outer ring, a counter-rotating rune band, tick marks,
## spokes, and an inner star.
##
## ⚠ AND IT REPLACED A TOWER FOR A REASON WORTH KEEPING. `_Paper` drew a hand
## sketching a tower, ran for 2.6 s and then called `set_process(false)` — so on
## every boot, a few seconds in, the title screen became a STILL IMAGE. This one
## has no end state: it scribes itself, then breathes and pours elements forever.
##
## Costs one `_draw` per frame. ⚠ MUST DEGRADE at `graphics_quality = LOW`, and
## does: the bloom is dropped and the mote and rune budgets halve. The circle, the
## star and the pour survive, because they are the thing being asked for.
class _Sigil:
	extends Control

	## How long the circle takes to scribe itself. SLOW on purpose — the maker asked
	## for "a slow magic circle opening up", and the reveal is the first beat.
	const OPEN_TIME: float = 3.4

	## Ring geometry, as fractions of the sigil radius.
	const R_OUTER: float = 1.0
	const R_TICKS: float = 0.90
	const R_RUNES: float = 0.78
	const R_INNER: float = 0.46
	const TICKS: int = 36
	const RUNES: int = 18
	const SPOKES: int = 8
	## Seven points, one per castable element. See ELEMS.
	const STAR_POINTS: int = 7

	## THE POUR. Motes leave the RIM, not the centre — a circle that vents at its
	## edge reads as a gate something is coming through; one that vents at its middle
	## reads as a firework.
	const MOTES_HIGH: int = 46
	const MOTES_LOW: int = 14
	const MOTE_LIFE: float = 3.1
	const MOTE_RISE: float = 62.0

	const BREATH_HZ: float = 0.22
	const BREATH_AMP: float = 0.022
	## Band rotation, rad/sec. The two bands turn OPPOSITE ways, which is what makes
	## a static drawing read as a mechanism instead of a picture.
	const SPIN_OUTER: float = 0.085
	const SPIN_RUNES: float = -0.13

	## Set by `Lobby._apply_class_tint` — the circle wears your class's colour.
	var accent: Color = Lobby.ACCENT_FALLBACK

	var _t: float = 0.0
	var _rng := RandomNumberGenerator.new()
	## Each mote: [angle, unused, age, element, out_speed, orbital_drift]
	var _motes: Array = []
	var _spawn_acc: float = 0.0

	## The seven CASTABLE elements, in the order the star's points are drawn.
	##
	## ⚠ WIND IS DELIBERATELY ABSENT even though `Elements.Element` declares it.
	## Nothing in the game casts wind, and a title screen advertising an element the
	## player can never hold is a promise the game does not keep.
	const ELEMS: Array[int] = [
		Elements.Element.FIRE, Elements.Element.ICE, Elements.Element.LIGHTNING,
		Elements.Element.SHADOW, Elements.Element.ARCANE, Elements.Element.EARTH,
		Elements.Element.HOLY,
	]


	func _ready() -> void:
		_rng.seed = 0x516114
		set_process(true)


	func _low() -> bool:
		return TuningConfig.quality_is_low()


	func _mote_budget() -> int:
		return MOTES_LOW if _low() else MOTES_HIGH


	func _process(delta: float) -> void:
		_t += delta
		# Nothing pours until the gate is most of the way open — the reveal has to
		# land as a CAUSE, with the elements as its consequence.
		if _open() > 0.55:
			_spawn_acc += delta * float(_mote_budget()) / MOTE_LIFE
			while _spawn_acc >= 1.0:
				_spawn_acc -= 1.0
				_spawn_mote()
		var i: int = _motes.size() - 1
		while i >= 0:
			var m: Array = _motes[i]
			m[2] += delta
			if m[2] >= MOTE_LIFE:
				_motes.remove_at(i)
			else:
				m[0] += m[5] * delta          # slow orbital drift as it leaves
			i -= 1
		queue_redraw()


	func _spawn_mote() -> void:
		_motes.append([
			_rng.randf() * TAU,                      # angle on the rim
			0.0,                                     # (unused — kept for shape)
			0.0,                                     # age
			ELEMS[_rng.randi() % ELEMS.size()],
			_rng.randf_range(0.55, 1.25),            # outward speed
			_rng.randf_range(-0.30, 0.30),           # orbital drift
		])


	## 0 -> 1 as the circle scribes itself, eased so the hand slows into the finish.
	func _open() -> float:
		return 1.0 - pow(1.0 - clampf(_t / OPEN_TIME, 0.0, 1.0), 3.0)


	## ⚠ BIASED LEFT, and that is a layout contract rather than taste: the menu
	## column hugs the RIGHT edge (`PANEL_W` wide), so a centred circle would sit
	## under the buttons and fight them for legibility.
	func _centre() -> Vector2:
		return Vector2(size.x * 0.34, size.y * 0.52)


	func _radius() -> float:
		var breath: float = 1.0 + sin(_t * TAU * BREATH_HZ) * BREATH_AMP
		return minf(size.x * 0.42, size.y * 0.62) * 0.62 * breath


	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Lobby.PAPER)
		var c: Vector2 = _centre()
		var r: float = _radius()
		if r <= 1.0:
			return
		var open: float = _open()
		_draw_bloom(c, r, open)
		_draw_ring(c, r * R_OUTER, open, 2.0, 0.85)
		_draw_ticks(c, r, open)
		_draw_runes(c, r, open)
		_draw_spokes(c, r, open)
		_draw_star(c, r * R_INNER, open)
		_draw_motes(c, r)


	## A soft bloom under the figure so the circle reads as a LIGHT SOURCE rather
	## than as line art. Concentric translucent discs — cheap, and the stand-in for
	## an actual glow shader on a screen that does not run the combat grade.
	func _draw_bloom(c: Vector2, r: float, open: float) -> void:
		if _low():
			return
		var rings: int = 7
		for i in rings:
			var f: float = float(i) / float(rings)
			draw_circle(c, r * (0.55 + f * 0.75),
				Color(accent.r, accent.g, accent.b, 0.055 * (1.0 - f) * open))


	## An arc that SWEEPS INTO EXISTENCE rather than fading in. The circle is being
	## inscribed, and a stroke growing from one end is the only version of that which
	## reads as drawing — a fade reads as a light coming on.
	func _draw_ring(c: Vector2, r: float, open: float, w: float, alpha: float) -> void:
		if open <= 0.0:
			return
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * open, 96,
			Color(accent.r, accent.g, accent.b, alpha * minf(open * 1.4, 1.0)), w, true)


	## The tick band. Ticks appear IN SEQUENCE with the sweep, so the ring and its
	## graduations are inscribed by the same hand at the same moment.
	func _draw_ticks(c: Vector2, r: float, open: float) -> void:
		var shown: int = int(floor(TICKS * open))
		var spin: float = _t * SPIN_OUTER
		for i in shown:
			var ang: float = spin - PI * 0.5 + TAU * float(i) / float(TICKS)
			var long: bool = (i % 3) == 0
			var d := Vector2.from_angle(ang)
			draw_line(c + d * (r * (R_TICKS - (0.055 if long else 0.028))),
				c + d * (r * R_TICKS),
				Color(accent.r, accent.g, accent.b, 0.30 + (0.35 if long else 0.0)),
				1.8 if long else 1.0)


	## The rune band, counter-rotating.
	##
	## Runes are short chorded STROKES rather than glyphs: at this size a real
	## alphabet is mush, and the eye reads "writing" from rhythm alone. Seeded per
	## index so each rune is distinct and stable across frames — re-rolling every
	## frame would make the band boil.
	func _draw_runes(c: Vector2, r: float, open: float) -> void:
		if open < 0.35:
			return
		var count: int = int(RUNES * 0.5) if _low() else RUNES
		var a: float = (open - 0.35) / 0.65
		var spin: float = _t * SPIN_RUNES
		for i in count:
			var ang: float = spin + TAU * float(i) / float(count)
			var d := Vector2.from_angle(ang)
			var n := Vector2(-d.y, d.x)
			var base: Vector2 = c + d * (r * R_RUNES)
			_rng.seed = 0x9E37 + i * 131
			for _s in 3:
				var o1: Vector2 = base + n * _rng.randf_range(-5.0, 5.0) + d * _rng.randf_range(-4.0, 4.0)
				var o2: Vector2 = o1 + n * _rng.randf_range(-4.0, 4.0) + d * _rng.randf_range(-5.0, 5.0)
				draw_line(o1, o2, Color(accent.r, accent.g, accent.b, 0.55 * a), 1.0)


	func _draw_spokes(c: Vector2, r: float, open: float) -> void:
		if open < 0.5:
			return
		var a: float = (open - 0.5) / 0.5
		var spin: float = _t * SPIN_OUTER
		for i in SPOKES:
			var d := Vector2.from_angle(spin + TAU * float(i) / float(SPOKES))
			draw_line(c + d * (r * R_INNER), c + d * (r * R_RUNES),
				Color(accent.r, accent.g, accent.b, 0.18 * a), 1.0)


	## THE INNER STAR — seven points, one per castable element, each in ITS OWN
	## COLOUR. This is the "elements" half of the ask standing still, so the pour has
	## somewhere visible to have come from.
	func _draw_star(c: Vector2, r: float, open: float) -> void:
		if open < 0.62:
			return
		var a: float = (open - 0.62) / 0.38
		var pts: Array[Vector2] = []
		for i in STAR_POINTS:
			var ang: float = -PI * 0.5 + TAU * float(i) / float(STAR_POINTS) + _t * SPIN_RUNES * 0.5
			pts.append(c + Vector2.from_angle(ang) * r)
		# Chord every point to the one TWO along — the heptagram, and the only star
		# at seven points that closes in a single unbroken stroke.
		for i in STAR_POINTS:
			var col: Color = Elements.color(ELEMS[i])
			draw_line(pts[i], pts[(i + 2) % STAR_POINTS], Color(col.r, col.g, col.b, 0.42 * a), 1.4)
		# A bead of each element's colour on its own point, breathing OUT OF PHASE so
		# the ring shimmers instead of pulsing as one lamp.
		for i in STAR_POINTS:
			var col2: Color = Elements.color(ELEMS[i])
			var puls: float = 0.6 + 0.4 * sin(_t * 2.1 + float(i) * 0.9)
			draw_circle(pts[i], 2.6 * puls, Color(col2.r, col2.g, col2.b, 0.9 * a))


	## THE POUR. Elements leaving the gate: outward from the rim, lifting, fading.
	func _draw_motes(c: Vector2, r: float) -> void:
		for m: Array in _motes:
			var life: float = clampf(float(m[2]) / MOTE_LIFE, 0.0, 1.0)
			var col: Color = Elements.color(int(m[3]))
			var p: Vector2 = c + Vector2.from_angle(float(m[0])) * (r * (1.0 + life * float(m[4]) * 0.55))
			# Lift, so the pour has a DIRECTION and does not read as a flat ripple.
			p.y -= MOTE_RISE * life * life
			# Fade in fast, out slow — a mote that pops into existence at full alpha
			# reads as a rendering glitch at the rim.
			var fade: float = (1.0 - life) * minf(life * 6.0, 1.0)
			draw_circle(p, maxf(2.3 * (1.0 - life * 0.45), 0.7),
				Color(col.r, col.g, col.b, 0.85 * fade))
