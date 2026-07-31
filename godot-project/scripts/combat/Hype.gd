class_name Hype
extends Node
## THE MOMENT-TO-MOMENT REWARD LOOP — the endorphin half of "action packed like
## there is so much going on to be done always".
##
## WHY THIS EXISTS SEPARATELY FROM Rank. `Rank` is the SLOW loop: kills accrue
## power, six tiers over a whole climb, and a tier-up happens maybe twice a
## session. That is progression, and progression is not a feedback loop — it is
## too rare to chase. What was missing is the loop that fires every few SECONDS,
## reads instantly, and makes you want the next one immediately:
##
##   · KILL STREAK   — kills inside a rolling window chain; the counter climbs and
##                     the named rungs (RAMPAGE / CARNAGE / UNSTOPPABLE …) land as
##                     a shout. Let the window lapse and you lose it, which is the
##                     thing that makes you push instead of retreat.
##   · MULTI-KILL    — several kills inside a fraction of a second. This is what
##                     rewards playing the AoE spells well, and it is the clip.
##   · CLOSE CALL    — dropped under a quarter health and lived through it. The
##                     game noticing the near-death is what turns a scare into a
##                     story.
##   · WAVE FLOURISH — clearing a wave has to feel like WINNING something, not
##                     like a timer expiring: shout, camera punch, music swell,
##                     and a chunk of rank power banked on the spot.
##
## NOT AN AUTOLOAD. It is built by the Arena and registered in group "hype";
## Enemy._die finds it by group. That keeps it per-arena (so a streak cannot leak
## across a scene change), keeps project.godot untouched, and makes it trivially
## absent in the headless suites that instantiate an arena with no autoloads —
## every autoload it uses is reached through a guarded tree lookup (_autoload)
## for the same reason.

## Group the rest of the combat layer finds this by.
const GROUP: StringName = &"hype"

# ── streak windows ───────────────────────────────────────────────────────────
## A kill keeps the chain alive for this long. Long enough to cross the room for
## the next body, short enough that camping breaks it.
const COMBO_WINDOW: float = 3.2
## Kills closer together than this count as ONE multi-kill event.
const MULTI_WINDOW: float = 0.7

## Named rungs of the chain: [kills, shout, rank power bonus].
const STREAK_RUNGS: Array = [
	[3, "RAMPAGE", 2],
	[5, "FRENZY", 3],
	[8, "CARNAGE", 5],
	[12, "UNSTOPPABLE", 8],
	[17, "APOCALYPSE", 12],
	[24, "ASCENDANT", 18],
]

## Multi-kill shouts by count (index 2 = double). Anything past the table is the
## last entry, because at that point the number itself is the joke.
const MULTI_SHOUTS: Array[String] = ["", "", "DOUBLE KILL", "TRIPLE KILL", "SLAUGHTER", "MASSACRE"]
const MULTI_POWER: int = 2

## Below this fraction of max HP, the hero is "in the red" and a survival counts.
const CLOSE_CALL_FRACTION: float = 0.25
## Survive that long without taking another hit and it lands as a CLOSE CALL.
const CLOSE_CALL_SURVIVE: float = 3.5
const CLOSE_CALL_POWER: int = 4

## Rank power banked for beating a wave, and for the floor's guardian.
const WAVE_CLEAR_POWER: int = 6

# ── look ─────────────────────────────────────────────────────────────────────
const HUD_LAYER: int = 55          # above the ability bar (?), below pause (90)
const SHOUT_HOLD: float = 0.55
const SHOUT_FADE: float = 0.45
const COMBO_COLOR_LOW: Color = Color(0.95, 0.92, 0.80)
const COMBO_COLOR_HIGH: Color = Color(1.0, 0.45, 0.25)
## Chain length at which the combo colour reaches COMBO_COLOR_HIGH.
const COMBO_COLOR_SPAN: float = 14.0

var _combo: int = 0
var _combo_timer: float = 0.0
var _rung: int = -1                # highest STREAK_RUNGS index announced this chain
var _multi: int = 0
var _multi_timer: float = 0.0
var _best_combo: int = 0

var _hero: Node = null
var _in_red: bool = false
var _red_timer: float = 0.0

var _combo_label: Label = null
var _combo_bar: ColorRect = null
var _combo_bar_bg: ColorRect = null
var _shout: Label = null
var _shout_tween: Tween = null


func _ready() -> void:
	add_to_group(GROUP)
	_build_hud()
	_refresh_combo_hud()
	# The hero may not exist yet (co-op spawns it on a timer), so this retries.
	_try_bind_hero()


func _process(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		_try_bind_hero()
	if _multi_timer > 0.0:
		_multi_timer -= delta
		if _multi_timer <= 0.0:
			_resolve_multi()
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_break_chain()
		else:
			_refresh_combo_hud()
	if _in_red:
		_red_timer -= delta
		if _red_timer <= 0.0:
			_in_red = false
			_shout_it("CLOSE CALL", Color(0.55, 0.95, 1.0), 0.9)
			_grant(CLOSE_CALL_POWER)
			_sfx("ding", -2.0, 0.06, 0.8)


# ══════════════════════════════════════════════════════════════════ KILLS
## Called by Enemy._die (found by group). `_where` is the body's position — taken
## but unused today, kept in the signature because a world-space burst at the kill
## is the obvious next beat and changing every call site later is the expensive
## part. `tint` is the victim's silhouette colour, so the shout wears its hue.
func notify_kill(_where: Vector2 = Vector2.ZERO, tint: Color = Color(1, 1, 1, 1)) -> void:
	_combo += 1
	_best_combo = maxi(_best_combo, _combo)
	_combo_timer = COMBO_WINDOW
	_multi += 1
	_multi_timer = MULTI_WINDOW
	_refresh_combo_hud()
	_check_rung(tint)
	# Music leans on the chain: a hot streak IS the peak of the wave.
	_set_intensity(clampf(float(_combo) / COMBO_COLOR_SPAN, 0.0, 1.0))


## Announce the highest named rung this chain has just crossed. One shout per
## rung per chain — crossing 8 does not also re-announce 3 and 5.
func _check_rung(tint: Color) -> void:
	var hit: int = -1
	for i: int in STREAK_RUNGS.size():
		if _combo >= int(STREAK_RUNGS[i][0]):
			hit = i
	if hit <= _rung:
		return
	_rung = hit
	var row: Array = STREAK_RUNGS[hit]
	_shout_it(String(row[1]), tint.lightened(0.35), 1.0 + 0.08 * float(hit))
	_grant(int(row[2]))
	_sfx("ding", 0.0, 0.05, 1.0 + 0.12 * float(hit))
	_camera_punch(0.05 + 0.012 * float(hit), 0.06 + 0.02 * float(hit))


## The multi-kill window lapsed: if more than one body went down inside it, that
## was an AoE landing well and it gets its own, louder shout.
func _resolve_multi() -> void:
	var n: int = _multi
	_multi = 0
	if n < 2:
		return
	var idx: int = clampi(n, 0, MULTI_SHOUTS.size() - 1)
	_shout_it(MULTI_SHOUTS[idx], Color(1.0, 0.85, 0.35), 1.15)
	_grant(MULTI_POWER * (n - 1))
	_sfx("overpower", -1.0, 0.05, 1.0)
	_camera_punch(0.07, 0.14)


## The chain lapsed. Deliberately SILENT — a failure sting every few seconds
## would be nagging, and the counter vanishing is loss enough.
func _break_chain() -> void:
	_combo = 0
	_rung = -1
	_combo_timer = 0.0
	_set_intensity(0.0)
	_refresh_combo_hud()


# ══════════════════════════════════════════════════════════════════ WAVES
## A wave is opening: the unseen hand is DRAWING the next mob in. Announce it,
## and pull the camera back so the arrival is something you watch land.
func wave_opened(index: int, total: int) -> void:
	_shout_it("WAVE %d / %d" % [index + 1, total], Color(0.72, 0.86, 1.0), 0.85)
	_sfx("sigil_form", -3.0, 0.05, 1.0 + 0.04 * float(index))
	_camera_pull(0.13, 0.35)
	_set_intensity(clampf(0.25 + 0.15 * float(index), 0.0, 1.0))


## A wave is BEATEN. The reward beat: shout, punch, swell, power banked. This
## fires while the wave's last stragglers may still be standing — that is the
## point, the win lands on top of the fight instead of after it.
func wave_beaten(index: int, total: int) -> void:
	var last: bool = index + 1 >= total
	_shout_it("WAVE %d DOWN" % (index + 1), Color(0.55, 1.0, 0.7), 1.1 if last else 0.95)
	_grant(WAVE_CLEAR_POWER)
	_sfx("holy_swell", -2.0, 0.04, 1.0)
	_camera_punch(0.08, 0.16)
	_music_flourish()


## The floor's guardian has arrived. The loudest beat a floor has before its end.
func guardian_arrived() -> void:
	_shout_it("THE GUARDIAN", Color(1.0, 0.78, 0.3), 1.3)
	_sfx("breach", 0.0, 0.04, 0.9)
	_camera_pull(0.2, 0.7)
	_camera_trauma(0.35)
	_set_intensity(1.0)


# ══════════════════════════════════════════════════════════ CLOSE CALLS
## Bind to whichever hero this peer owns and watch its health. Retried from
## _process because co-op spawns heroes on a delay after the arena builds.
func _try_bind_hero() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for h: Node in tree.get_nodes_in_group(&"hero"):
		if not is_instance_valid(h) or not h.has_signal(&"health_changed"):
			continue
		if h.has_method(&"is_multiplayer_authority") and not h.is_multiplayer_authority():
			continue   # co-op: only care about MY near-death
		_hero = h
		if not h.is_connected(&"health_changed", _on_hero_health):
			h.connect(&"health_changed", _on_hero_health)
		return


## Dropping into the red arms the close-call timer; every further hit re-arms it,
## so it only pays out once you have actually stopped being hit.
func _on_hero_health(hp: int, max_hp: int) -> void:
	if max_hp <= 0:
		return
	var frac: float = float(hp) / float(max_hp)
	if hp <= 0:
		_in_red = false          # dying is not a close call
		_break_chain()
		return
	if frac <= CLOSE_CALL_FRACTION:
		_in_red = true
		_red_timer = CLOSE_CALL_SURVIVE
	elif frac > CLOSE_CALL_FRACTION * 2.0:
		_in_red = false          # healed well clear of it — nothing to survive


# ══════════════════════════════════════════════════════════════════ HUD
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HypeHud"
	layer.layer = HUD_LAYER
	add_child(layer)

	# The shout: centre-upper, big, outlined, fades. One label reused for every
	# beat so two shouts can never overlap into mush.
	_shout = Label.new()
	_shout.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_shout.offset_top = 62.0
	_shout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shout.add_theme_font_size_override("font_size", 26)
	_shout.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.07, 0.95))
	_shout.add_theme_constant_override("outline_size", 7)
	_shout.modulate.a = 0.0
	layer.add_child(_shout)

	# The chain counter + its draining window bar, bottom-right, out of the way
	# of the thumbs (mobile: the right thumb owns the spell buttons lower down).
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -160.0
	box.offset_right = -12.0
	box.offset_top = 34.0
	box.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(box)

	_combo_label = Label.new()
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.add_theme_font_size_override("font_size", 20)
	_combo_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.07, 0.95))
	_combo_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_combo_label)

	_combo_bar_bg = ColorRect.new()
	_combo_bar_bg.custom_minimum_size = Vector2(148.0, 3.0)
	_combo_bar_bg.color = Color(0.1, 0.1, 0.14, 0.55)
	box.add_child(_combo_bar_bg)
	_combo_bar = ColorRect.new()
	_combo_bar.color = COMBO_COLOR_LOW
	_combo_bar.anchor_right = 1.0
	_combo_bar.anchor_bottom = 1.0
	_combo_bar_bg.add_child(_combo_bar)


func _refresh_combo_hud() -> void:
	if _combo_label == null:
		return
	var showing: bool = _combo >= 2
	_combo_label.visible = showing
	if _combo_bar_bg != null:
		_combo_bar_bg.visible = showing
	if not showing:
		return
	var heat: float = clampf(float(_combo) / COMBO_COLOR_SPAN, 0.0, 1.0)
	var col: Color = COMBO_COLOR_LOW.lerp(COMBO_COLOR_HIGH, heat)
	_combo_label.text = "%d  CHAIN" % _combo
	_combo_label.add_theme_color_override("font_color", col)
	if _combo_bar != null:
		_combo_bar.color = col
		_combo_bar.anchor_right = clampf(_combo_timer / COMBO_WINDOW, 0.0, 1.0)


## One shout, one tween. `scale` bumps the font so a bigger beat reads bigger
## without needing a second label.
func _shout_it(text: String, color: Color, scale: float = 1.0) -> void:
	if _shout == null or text == "":
		return
	_shout.text = text
	_shout.add_theme_color_override("font_color", color)
	_shout.add_theme_font_size_override("font_size", int(round(26.0 * scale)))
	_shout.modulate.a = 1.0
	if _shout_tween != null and _shout_tween.is_valid():
		_shout_tween.kill()
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	_shout_tween = tree.create_tween()
	_shout_tween.tween_interval(SHOUT_HOLD)
	_shout_tween.tween_property(_shout, "modulate:a", 0.0, SHOUT_FADE)


# ══════════════════════════════════════════════ guarded autoload reach-outs
## Every one of these is a TREE lookup, never the bare autoload identifier: the
## headless suites instantiate the Arena (and therefore this) in a --script
## context where no autoload is registered at all. And relative-from-root
## (`get_tree().root.get_node_or_null(^"Rank")`) rather than the absolute
## "/root/Rank" — a --script context has no active scene, and an absolute
## get_node logs an error there on EVERY call even though it returns null
## harmlessly. Sfx.gd documents the same idiom for the same reason.
func _autoload(singleton: StringName) -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(singleton))


func _grant(power: int) -> void:
	var r: Node = _autoload(&"Rank")
	if r != null and r.has_method("add_power"):
		r.call("add_power", power)


func _sfx(key: String, db: float = 0.0, jitter: float = 0.06, pitch: float = 1.0) -> void:
	var s: Node = _autoload(&"Sfx")
	if s != null and s.has_method("play"):
		s.call("play", key, db, jitter, pitch)


func _set_intensity(t: float) -> void:
	var m: Node = _autoload(&"Music")
	if m != null and m.has_method("set_intensity"):
		m.call("set_intensity", t)


func _music_flourish() -> void:
	var m: Node = _autoload(&"Music")
	if m != null and m.has_method("flourish"):
		m.call("flourish")


func _camera_punch(amount: float, trauma: float) -> void:
	for cam: Node in _cameras():
		if cam.has_method("zoom_punch"):
			cam.call("zoom_punch", amount, 0.2)
		if trauma > 0.0 and cam.has_method("add_trauma"):
			cam.call("add_trauma", trauma)


func _camera_pull(amount: float, hold: float) -> void:
	for cam: Node in _cameras():
		if cam.has_method("zoom_pull"):
			cam.call("zoom_pull", amount, hold)


func _camera_trauma(amount: float) -> void:
	for cam: Node in _cameras():
		if cam.has_method("add_trauma"):
			cam.call("add_trauma", amount)


func _cameras() -> Array[Node]:
	var tree: SceneTree = get_tree()
	if tree == null:
		return [] as Array[Node]
	return tree.get_nodes_in_group("combat_camera")


# ══════════════════════════════════════════════════════════════ readouts
func combo() -> int:
	return _combo


func best_combo() -> int:
	return _best_combo
