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
## 1. **"Play Solo" now starts a RUN.** It used to `change_scene_to_file` into
##    `res://scenes/Main.tscn` — the old hub, full of AI NPCs that talk to a
##    hardcoded local Ollama server at 127.0.0.1:11434. The spec cuts that
##    permanently ("Out permanently: persistent world, NPC memory, LLM anything")
##    and there is no hub in this game: you drop into a floor. So Play Solo now
##    calls `GameState.enter_run()`, which owns the persistent climb (resume from
##    your saved floor, never a blanket reset) and does the scene change itself.
##    On a phone, loopback Ollama is not merely absent — it is the device's own
##    localhost, so it could never have worked there.
##
##    THE HUB IS PARKED, NOT DELETED. `scenes/Main.tscn`, `NPC.gd`, `Player.gd`,
##    `Conversation.gd` and the memory stack are all still on disk and the
##    `Conversation` autoload is still registered — it is referenced as a BARE
##    GLOBAL by `Player.gd` and `NPC.gd`, so unregistering it stops `Main.tscn`
##    loading at all. Nothing here reaches for any of it; the hub is simply off
##    the critical path, and the maker can wire it back with one line.
##
## 2. **It looks like the game.** The tower is DRAWN — an unseen hand sketches
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

	_paper = _Paper.new()
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paper)

	_build_ui()
	_apply_class_tint()

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


## Leaving the scene entirely must not leave a UDP socket bound and a per-frame
## pump running on the Net autoload — the autoload outlives this scene, so a
## missed teardown here leaks for the rest of the session.
func _exit_tree() -> void:
	_stop_discovery()


func _on_join_ok() -> void:
	# We are in a session now; there is nothing left to discover, and holding the
	# listener open would keep pumping Net every frame through the whole run.
	_stop_discovery()
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
	title.text = "THE TOWER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", CHALK)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	right.add_child(title)

	var sub := Label.new()
	sub.text = "someone is drawing this"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", GRAPHITE)
	right.add_child(sub)

	# ── class ──
	_class_btn = _button("", _cycle_class, 15)
	right.add_child(_class_btn)
	_class_kit = Label.new()
	_class_kit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_kit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_kit.add_theme_font_size_override("font_size", 9)
	_class_kit.add_theme_color_override("font_color", GRAPHITE)
	right.add_child(_class_kit)

	# ── the one button that matters ──
	var play := _button("CLIMB  ▸", _play_solo, 19)
	play.custom_minimum_size = Vector2(PANEL_W, BUTTON_H + 8.0)
	play.add_theme_color_override("font_color", CHALK)
	right.add_child(play)

	right.add_child(_button("Host Co-op", _host, 14))
	right.add_child(_button("Join a Game", _open_join, 14))

	_start_btn = _button("Start Run", _start_run, 15)
	_start_btn.visible = false
	right.add_child(_start_btn)

	right.add_child(_button("Credits", _open_credits, 12))

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
		_class_kit.text = String(info.get("kit", ""))
	if _paper != null:
		_paper.set("accent", accent)
		_paper.queue_redraw()


## THE ENTRY POINT. `GameState.enter_run()` owns the persistent climb — it
## resumes the saved floor rather than resetting to 1, restores banked rank
## power, and performs the scene change into the arena itself. Reached through
## the tree rather than the bare `GameState` identifier so this script stays
## loadable in a headless harness with no autoloads registered.
func _play_solo() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("enter_run"):
		_say("the tower is missing. (GameState unavailable)")
		return
	# We are about to leave this scene. `_exit_tree` catches it too, but doing it
	# here means the socket is closed BEFORE the arena starts loading rather than
	# during it.
	_stop_discovery()
	gs.set("selected_class", _selected_class)
	_say("climbing...")
	gs.call("enter_run")


func _host() -> void:
	if _net == null:
		return
	# You cannot listen for other people's games while running your own; Net.host()
	# starts the beacon that advertises THIS session instead.
	_stop_discovery()
	var err: int = _net.host(_selected_class)
	if err == OK:
		# The beacon is automatic (Net.host starts it), so the other phone should
		# simply see this machine in its list — the address is the fallback.
		_say("hosting — they should see you under Join a Game")
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


func _music_town() -> void:
	var m: Node = get_node_or_null("/root/Music")
	if m != null and m.has_method("play_town"):
		m.call("play_town")


# ═══════════════════════════════════════════════════════════════════ THE PAPER
## The backdrop: a tower being DRAWN, live, every time the game opens.
##
## Deliberately procedural rather than an imported image, because the lore IS the
## process — an unseen hand sketching floor after floor. Early (low) floors are
## crude, wobbly, sparse scribbles on ruled paper; the higher it climbs the
## steadier the hand gets, until the top is confident ink. That escalation is the
## game's whole difficulty curve stated as a picture, with no words and no
## cutscene.
##
## It costs one `_draw` at 6 fps while the reveal runs and then goes quiet.
class _Paper:
	extends Control

	const FLOORS: int = 11
	const REVEAL_TIME: float = 2.6
	## Redraws per second during the reveal. The stroke wobble is re-rolled each
	## time, so a low rate reads as a hand working rather than as a low frame rate.
	const REDRAW_HZ: float = 7.0

	var accent: Color = Lobby.ACCENT_FALLBACK
	var _t: float = 0.0
	var _next_draw: float = 0.0
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		_rng.seed = 0xC0FFEE
		set_process(true)

	func _process(delta: float) -> void:
		if _t >= REVEAL_TIME:
			set_process(false)
			queue_redraw()
			return
		_t += delta
		_next_draw -= delta
		if _next_draw <= 0.0:
			_next_draw = 1.0 / REDRAW_HZ
			queue_redraw()

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(r, Lobby.PAPER)
		# Ruled paper. Faint, wide, and slightly off-horizontal so it reads as a
		# real page rather than as a grid overlay.
		var line_gap: float = maxf(14.0, size.y / 18.0)
		var y: float = line_gap
		while y < size.y:
			draw_line(Vector2(0.0, y), Vector2(size.x, y + 0.7), Lobby.RULE, 1.0)
			y += line_gap

		var progress: float = clampf(_t / REVEAL_TIME, 0.0, 1.0)
		# Ease-out: the hand starts fast and lingers over the top floors, which is
		# also where the drawing gets careful.
		progress = 1.0 - pow(1.0 - progress, 2.0)

		# The tower occupies the left third, standing on the bottom edge.
		var base_x: float = size.x * 0.22
		var base_y: float = size.y * 0.94
		var top_y: float = size.y * 0.08
		var span: float = base_y - top_y
		var floor_h: float = span / float(FLOORS)

		_rng.seed = 0xC0FFEE
		for i in FLOORS:
			var t: float = float(i) / float(FLOORS - 1)     # 0 bottom .. 1 top
			if progress < t * 0.98:
				break
			# The hand gets steadier as it climbs: wobble falls, the stroke
			# darkens toward chalk, and the floor narrows.
			var wobble: float = lerpf(5.0, 0.6, t)
			var half_w: float = lerpf(size.x * 0.115, size.x * 0.042, t)
			var col: Color = Lobby.GRAPHITE.lerp(Lobby.CHALK, t)
			col.a = lerpf(0.45, 1.0, t)
			var width: float = lerpf(1.0, 2.2, t)
			var fy: float = base_y - floor_h * float(i)
			_scribble_box(
				Vector2(base_x - half_w, fy - floor_h * 0.86),
				Vector2(base_x + half_w, fy),
				col, width, wobble
			)
			# Every third floor is a landing the eye can count.
			if i % 3 == 0:
				draw_line(
					Vector2(base_x - half_w - 6.0, fy),
					Vector2(base_x + half_w + 6.0, fy),
					col, width
				)

		# The pencil tip: a mark of class-coloured light sitting exactly where the
		# hand has reached. It IS the "who is holding the pencil" question, and it
		# needs no sentence to ask it.
		var tip_y: float = base_y - span * progress
		var glow: Color = accent
		glow.a = 0.85 if progress < 1.0 else 0.35
		draw_circle(Vector2(base_x, tip_y), 3.0, glow)
		glow.a *= 0.28
		draw_circle(Vector2(base_x, tip_y), 10.0, glow)

	## One hand-drawn rectangle: four strokes, each jittered, each overshooting
	## its corner slightly — which is what makes a line look drawn rather than
	## computed.
	func _scribble_box(a: Vector2, b: Vector2, col: Color, width: float, wobble: float) -> void:
		var corners: Array[Vector2] = [
			Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y),
		]
		for i in 4:
			var p0: Vector2 = corners[i]
			var p1: Vector2 = corners[(i + 1) % 4]
			_scribble_line(p0, p1, col, width, wobble)

	func _scribble_line(p0: Vector2, p1: Vector2, col: Color, width: float, wobble: float) -> void:
		var segments: int = 5
		var pts := PackedVector2Array()
		for s in segments + 1:
			var t: float = float(s) / float(segments)
			var p: Vector2 = p0.lerp(p1, t)
			# No jitter on the endpoints, or the box falls apart at the corners.
			var w: float = wobble * sin(PI * t)
			p += Vector2(_rng.randf_range(-w, w), _rng.randf_range(-w, w))
			pts.append(p)
		if pts.size() >= 2:
			draw_polyline(pts, col, width)
