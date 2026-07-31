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
## The button column. Held so the suite can assert the whole panel still fits the
## 640×360 base viewport — the thing that silently breaks the first time somebody
## adds one more row.
var _col: VBoxContainer = null


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

	if _net != null:
		_net.lobby_changed.connect(_refresh)
		_net.server_started.connect(_refresh)
		_net.join_ok.connect(func() -> void: _status.text = "connected — waiting for the host")
		_net.join_failed.connect(func() -> void: _status.text = "no answer. check the address.")
	_refresh()
	_music_town()


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

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 6)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "host address"
	_ip_edit.custom_minimum_size = Vector2(PANEL_W - 96.0, BUTTON_H)
	_ip_edit.add_theme_font_size_override("font_size", 13)
	join_row.add_child(_ip_edit)
	var join_btn := _button("Join", _join, 14)
	join_btn.custom_minimum_size = Vector2(88, BUTTON_H)
	join_row.add_child(join_btn)
	right.add_child(join_row)

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
		_status.text = "the tower is missing. (GameState unavailable)"
		return
	gs.set("selected_class", _selected_class)
	_status.text = "climbing..."
	gs.call("enter_run")


func _host() -> void:
	if _net == null:
		return
	var err: int = _net.host(_selected_class)
	if err == OK:
		_status.text = "hosting on port %d — they Join your address" % _net.DEFAULT_PORT
	else:
		_status.text = "host failed (err %d) — port in use?" % err


func _join() -> void:
	if _net == null:
		return
	var err: int = _net.join(_ip_edit.text.strip_edges(), _selected_class)
	_status.text = ("reaching %s..." % _ip_edit.text) if err == OK else "join error %d" % err


func _start_run() -> void:
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
