class_name RunSummary
extends Control
## ═══════════════════════════════════════════════════════════════════════════════
## THE RUN-END CEREMONY — the beat this game has never had.
## ═══════════════════════════════════════════════════════════════════════════════
##
## Before this screen existed, BOTH terminal states of THE TOWER walked into the
## parked v0.0 AI-NPC town: you conquered the tower -> a green tile-grid village,
## cut without ceremony; your party wiped -> the same village. There was no victory
## banner, card or text anywhere in the tower run, and the only
## `change_scene_to_file(".../Lobby.tscn")` in the entire project lived in the
## credits screen — so once a run ended, the title screen was unreachable.
##
## And it was reachable in the first sixty seconds: under the 2026-08-01 death rule
## a solo death ends the run immediately, so a new player met that town after their
## first mistake, having seen nothing of the game.
##
## ── WHAT THIS IS ──────────────────────────────────────────────────────────────
## One screen, three headlines, one grid of numbers, three buttons.
##
##   CONQUERED   you put the guardian down and walked out with the tower.
##   RUBBED OUT  the party ran out of bodies.
##   STEPPED OFF you left the tower alive, mid-climb (the leave portal, or pause).
##
## Every number on it already existed and was being thrown away:
## `GameState.build_outcome` has captured floor, kills, guardian, rank tier + title,
## elements and falls since Slice 2, and fed all of it to hub-NPC memory text that
## the player never saw. This renders it.
##
## ── WHAT IT IS NOT ────────────────────────────────────────────────────────────
## The spec is explicit: **no cutscenes, no codex, no dialogue boxes — nobody reads
## exposition on a phone.** So there is no story here, no "the hand withdraws...",
## no unlock crawl. Lore lands through art, spell names, boss design and one-line
## barks. What this screen is allowed to be is a PAGE IN THE BOOK: the tower is
## drawn, you are a drawing, and this is the page where the hand writes down what
## just happened. Hence the ruled paper, the chalk, and a single dry line under the
## headline in Bark's voice.
##
## ── WHERE IT LANDS YOU ────────────────────────────────────────────────────────
## `CLIMB AGAIN` re-enters the tower (the persistent climb resumes exactly where
## `GameState` saved it) and `TITLE` goes to the Lobby, which is the boot scene and
## the one screen that is known to work on a phone.
##
## The parked town survives as a THIRD, OPTIONAL button — never on the critical
## path, and hidden entirely on a build with no hub or on a touch device, because it
## needs an Ollama server on `127.0.0.1:11434` and on a phone that is the phone.
##
## Built in code, house style (Lobby / ClassSelect / PauseMenu all do this), laid
## out for the 640x360 base viewport in LANDSCAPE with every tap target >= 30 px.

## Palette — deliberately the Lobby's, so the ceremony and the title screen read as
## the same sketchbook rather than as two different games.
const PAPER: Color = Color(0.055, 0.052, 0.075)
const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)
const RULE: Color = Color(0.16, 0.17, 0.23)

const GOLD: Color = Color(1.0, 0.82, 0.36)      # conquered
const ASH: Color = Color(0.96, 0.42, 0.36)      # rubbed out
const SLATE: Color = Color(0.66, 0.82, 0.96)    # stepped off alive

const BUTTON_H: float = 30.0
const PANEL_W: float = 300.0
## Room left for the drawn page on the left. Same split as the Lobby's tower.
const STAT_W: float = 250.0

## The three outcomes, as one enum so the headline, the colour, the line and the
## sound cannot disagree about which run this was.
enum Outcome { CONQUERED, WIPED, WALKED }

## ⚠ THE TWO SCENE PATHS ARE RESTATED HERE RATHER THAN READ OFF THE RUN SPINE.
## `GameState` has no `class_name` — it resolves only as an AUTOLOAD, and autoloads
## are NOT registered under `--script`. Naming it as a bare identifier anywhere in
## this file would make the whole script fail to compile inside the capture tool and
## the headless suites, and it would surface as an unrelated missing method somewhere
## else entirely. The live node is still asked FIRST at every call site (`_to_title`,
## `_to_hub`); these are the fallbacks for when there is no autoload to ask.
const TITLE_PATH: String = "res://scenes/ui/Lobby.tscn"
const HUB_PATH: String = "res://scenes/Main.tscn"

const HEADLINES: Dictionary = {
	Outcome.CONQUERED: "THE TOWER IS DRAWN",
	Outcome.WIPED: "RUBBED OUT",
	Outcome.WALKED: "PAGE LEFT OPEN",
}
## One dry line, in Bark's voice — five words or fewer, present tense, no proper
## nouns, never an instruction. This is the ONLY prose on the screen.
const SUBLINES: Dictionary = {
	Outcome.CONQUERED: "you reached the hand.",
	Outcome.WIPED: "the hand pressed harder.",
	Outcome.WALKED: "you stepped off the page.",
}

var _outcome: Dictionary = {}
var _kind: int = Outcome.WALKED
var _gs: Node = null
var _paper: Control = null
## The stat + button column, held so the suite can assert the whole card still fits
## a 640x360 viewport — the thing that silently breaks the first time somebody adds
## one more row.
var _col: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gs = get_node_or_null(^"/root/GameState")
	_outcome = _read_outcome()
	_kind = classify(_outcome)

	_paper = _Page.new()
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.set("accent", accent_for(_kind))
	_paper.set("filled", _floors_done())
	_paper.set("total", int(_outcome.get("total_floors", 5)))
	add_child(_paper)

	_build_ui()
	_music()
	_sfx("holy" if _kind == Outcome.CONQUERED else "ding", -4.0)


## The run to render. Normally `GameState.last_run`; an empty dict when this scene
## is opened on its own (F6 on the .tscn, a capture tool), which must still draw
## rather than crash — a screen that only works after a real run is a screen nobody
## can look at.
func _read_outcome() -> Dictionary:
	if _gs != null:
		var r: Variant = _gs.get("last_run")
		if r is Dictionary and not (r as Dictionary).is_empty():
			return r as Dictionary
	return {}


## Which of the three beats this run was. STATIC + PURE so the suite can sweep it
## without a scene, and so there is exactly one implementation of the question.
##
## Order matters: a party that wiped ON the guardian floor may well have `boss_killed`
## false and `died` true, and a party that conquered has `died` false — so DEATH is
## asked first and "conquered" means the strict thing.
static func classify(run: Dictionary) -> int:
	if bool(run.get("died", false)):
		return Outcome.WIPED
	if bool(run.get("conquered", false)) or bool(run.get("boss_killed", false)):
		return Outcome.CONQUERED
	return Outcome.WALKED


static func accent_for(kind: int) -> Color:
	match kind:
		Outcome.CONQUERED:
			return GOLD
		Outcome.WIPED:
			return ASH
	return SLATE


## The stat rows, as [label, value] pairs. STATIC + PURE, driven only by the outcome
## dict, so the suite can assert what a victory shows without building a Control.
##
## ⚠ EVERY ROW HERE ALREADY EXISTED AND WAS BEING DISCARDED. `build_outcome` has
## captured all of it since Slice 2 and fed it to NPC memory text the player never
## read. The one genuinely new number is FRIENDLY FIRE, which nothing counted at all
## — see `GameState.notify_friendly_fire`.
static func stat_rows(run: Dictionary) -> Array:
	var rows: Array = []
	var floor_reached: int = int(run.get("floor_reached", 1))
	var total: int = maxi(int(run.get("total_floors", 0)), floor_reached)
	rows.append(["floor", "%d / %d" % [floor_reached, total]])
	rows.append(["kills", str(int(run.get("enemies_killed", 0)))])
	if bool(run.get("boss_killed", false)):
		rows.append(["guardian", "felled"])
	var elems: Array = run.get("elements_used", [])
	if not elems.is_empty():
		var names: Array[String] = []
		for e in elems:
			names.append(String(e))
		rows.append(["wielded", ", ".join(names).to_lower()])
	rows.append(["rank", String(run.get("rank_title", "Nameless"))])
	var ff: int = int(run.get("friendly_damage", 0))
	if ff > 0:
		rows.append(["friendly fire", "%d to each other" % ff])
	var highest: int = int(run.get("highest_floor", 0))
	if highest > floor_reached:
		rows.append(["your best", "floor %d" % highest])
	var falls: int = int(run.get("falls", 0))
	if falls > 0:
		rows.append(["falls", str(falls)])
	return rows


# ══════════════════════════════════════════════════════════════════════════ UI
func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.custom_minimum_size = Vector2(PANEL_W, 0)
	right.add_theme_constant_override("separation", 2)
	margin.add_child(right)
	_col = right

	var accent: Color = accent_for(_kind)

	var head := Label.new()
	head.text = String(HEADLINES.get(_kind, "RUN OVER"))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(PANEL_W, 0)
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", accent)
	head.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.9))
	head.add_theme_constant_override("outline_size", 6)
	right.add_child(head)

	var sub := Label.new()
	sub.text = String(SUBLINES.get(_kind, ""))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", GRAPHITE)
	right.add_child(sub)

	right.add_child(_spacer(4.0))
	right.add_child(_stat_block(accent))
	right.add_child(_spacer(4.0))

	# THE ONE BUTTON THAT MATTERS. Same shape and same emphasis as the Lobby's
	# CLIMB, because it is the same verb: the fastest possible loop back into a
	# fight is what the brief ("action packed, endorphin chasing") asks for.
	var again := _button("CLIMB AGAIN  ▸", _climb_again, 17)
	again.custom_minimum_size = Vector2(PANEL_W, BUTTON_H + 4.0)
	again.add_theme_color_override("font_color", CHALK)
	right.add_child(again)
	right.add_child(_button("Title", _to_title, 13))

	# The parked town, OPTIONAL and last. Hidden entirely where it cannot work.
	if _hub_is_offerable():
		var hub: Button = _button("Visit the town", _to_hub, 11)
		hub.tooltip_text = "the old hub — needs a local Ollama server"
		hub.add_theme_color_override("font_color", GRAPHITE)
		right.add_child(hub)


## Should the town button be drawn at all?
##
## ⚠ TWO CONDITIONS, AND THE SECOND IS THE ONE THAT MATTERS ON THE TARGET PLATFORM.
## The hub's NPCs talk to `http://127.0.0.1:11434`; on a phone that address is the
## phone's own loopback, so the button could only ever offer a mute village. It is
## therefore hidden on a touch build rather than shown-and-broken.
func _hub_is_offerable() -> bool:
	if not ResourceLoader.exists(HUB_PATH):
		return false
	return not DisplayServer.is_touchscreen_available()


func _stat_block(accent: Color) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(STAT_W, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 0)
	for row: Array in stat_rows(_outcome):
		var line := HBoxContainer.new()
		line.custom_minimum_size = Vector2(STAT_W, 0)
		var k := Label.new()
		k.text = String(row[0])
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_font_size_override("font_size", 11)
		k.add_theme_color_override("font_color", GRAPHITE)
		line.add_child(k)
		var v := Label.new()
		v.text = String(row[1])
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_theme_font_size_override("font_size", 11)
		v.add_theme_color_override("font_color", accent if String(row[0]) == "rank" else CHALK)
		line.add_child(v)
		box.add_child(line)
	return box


## How many floors of the tower the drawn page should show as finished.
func _floors_done() -> int:
	var f: int = int(_outcome.get("floor_reached", 1))
	if _kind == Outcome.CONQUERED:
		return maxi(f, int(_outcome.get("total_floors", f)))
	# You did not finish the floor you died on.
	return maxi(f - (1 if _kind == Outcome.WIPED else 0), 0)


# ══════════════════════════════════════════════════════════════════════ actions
## Straight back into the tower. `GameState.enter_run()` owns the persistent climb —
## it resumes the saved floor (or restarts a conquered tower at 1), restores banked
## rank power, and performs the scene change itself.
func _climb_again() -> void:
	if _gs != null and _gs.has_method("enter_run"):
		_gs.call("enter_run")
		return
	_to_title()


func _to_title() -> void:
	if _gs != null and _gs.has_method("go_to_title"):
		_gs.call("go_to_title")
		return
	get_tree().change_scene_to_file(TITLE_PATH)


func _to_hub() -> void:
	if _gs != null and _gs.has_method("visit_hub") and bool(_gs.call("visit_hub")):
		return
	_to_title()


## Esc / Back is the title, never the hub.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_to_title()


# ══════════════════════════════════════════════════════════════════════ helpers
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
	var s: Node = get_node_or_null(^"/root/Sfx")
	if s != null and s.has_method("play"):
		s.call("play", key, db)


## The town bed, matching the Lobby: the fight is over, and the card should not
## still be shouting the boss theme at you.
func _music() -> void:
	var m: Node = get_node_or_null(^"/root/Music")
	if m != null and m.has_method("play_town"):
		m.call("play_town")


# ═══════════════════════════════════════════════════════════════════════ THE PAGE
## The backdrop: the tower you just climbed, drawn, with the floors you reached
## inked in and the ones above still blank.
##
## Same hand as the Lobby's `_Paper` (and deliberately so — one sketchbook, not two)
## but it is doing a different job: the Lobby's draws the WHOLE tower as an
## invitation, and this one draws YOUR CLIMB as a record. The filled floors carry
## the outcome's colour, so a wipe and a conquest are different pictures before a
## single word has been read.
class _Page:
	extends Control

	const REVEAL_TIME: float = 1.1
	const REDRAW_HZ: float = 8.0

	var accent: Color = RunSummary.SLATE
	var filled: int = 0
	var total: int = 5
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
		draw_rect(Rect2(Vector2.ZERO, size), RunSummary.PAPER)
		var line_gap: float = maxf(14.0, size.y / 18.0)
		var y: float = line_gap
		while y < size.y:
			draw_line(Vector2(0.0, y), Vector2(size.x, y + 0.7), RunSummary.RULE, 1.0)
			y += line_gap

		var floors: int = maxi(total, 1)
		var progress: float = clampf(_t / REVEAL_TIME, 0.0, 1.0)
		progress = 1.0 - pow(1.0 - progress, 2.0)
		var base_x: float = size.x * 0.22
		var base_y: float = size.y * 0.92
		var top_y: float = size.y * 0.10
		var span: float = base_y - top_y
		var floor_h: float = span / float(floors)

		_rng.seed = 0xC0FFEE
		for i: int in floors:
			var t: float = float(i) / float(maxi(floors - 1, 1))
			var reached: bool = i < filled
			# Unreached floors are drawn faint and immediately; the reveal animates
			# only the part of the tower you actually climbed.
			if reached and progress < t * 0.9:
				break
			var wobble: float = lerpf(5.0, 0.8, t)
			var half_w: float = lerpf(size.x * 0.115, size.x * 0.045, t)
			var col: Color = accent if reached else RunSummary.GRAPHITE
			# The unreached floors have to be VISIBLE to do their job — "how much of
			# the tower is still above you" is the whole point of the picture, and at
			# 0.20 alpha on near-black paper they were simply not there.
			col.a = 0.95 if reached else 0.34
			var width: float = 2.2 if reached else 1.1
			var fy: float = base_y - floor_h * float(i)
			_scribble_box(
				Vector2(base_x - half_w, fy - floor_h * 0.86),
				Vector2(base_x + half_w, fy),
				col, width, wobble
			)

	func _scribble_box(a: Vector2, b: Vector2, col: Color, width: float, wobble: float) -> void:
		var corners: Array[Vector2] = [
			Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y),
		]
		for i in 4:
			_scribble_line(corners[i], corners[(i + 1) % 4], col, width, wobble)

	func _scribble_line(p0: Vector2, p1: Vector2, col: Color, width: float, wobble: float) -> void:
		var segments: int = 5
		var pts := PackedVector2Array()
		for s in segments + 1:
			var t: float = float(s) / float(segments)
			var p: Vector2 = p0.lerp(p1, t)
			var w: float = wobble * sin(PI * t)
			p += Vector2(_rng.randf_range(-w, w), _rng.randf_range(-w, w))
			pts.append(p)
		if pts.size() >= 2:
			draw_polyline(pts, col, width)
