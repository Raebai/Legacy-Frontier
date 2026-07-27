extends Node2D
## SPELL PLAYGROUND — play the ragdoll stick fighter AND cast/cycle every spell at
## destructible cover + practice dummies. The stickman spike (movement, jump, wall-jump,
## punch, ragdoll) + the real spell tree (SpellCaster) + destructibles, in one throwaway
## sandbox. Touches no game logic. Delete scripts/spike/ + scenes/spike/ to remove.
##
## Combat verbs use the GAME's input map so the sandbox is a true preview, not a
## third control scheme: LMB cast · F melee · RMB deflect · SPACE dash.
## move A/D (or arrows) · jump W/Up · duck/crawl S · aim MOUSE ·
## Q/E or SCROLL cycle spell · HOLD RMB = guard ring · B incoming test-bolt ·
## H hit · K kill · R reset · TAB physics-tune

const FIG := preload("res://scripts/spike/SpikeFigure.gd")
const ENEMY_SCENE := "res://scenes/combat/Enemy.tscn"
const DESTRUCTIBLE := "res://scripts/combat/DestructibleTerrain.gd"

const FLOOR_Y := 340.0
const HALF_W := 560.0
const CEIL_Y := -320.0
const FIG_COLOR := Color(0.93, 0.51, 0.51)
const COVER_X := [-210.0, 90.0, 360.0]
## How close the fighter must be to a standing rock wall for a punch to shove it.
## Generous vs the 96 px dummy punch: the wall is a big object and hunting for a
## pixel-perfect contact point would make the shove feel unreliable.
const SHOVE_REACH := 150.0
const DUMMY_X := [-70.0, 220.0]

var _fig: SpikeFigure
var _cam: Camera2D
var _hud: Label
var _spells: Array = []
var _sidx := 0
var _covers: Array = []
var _dummies: Array = []
var _shake := 0.0
var _shake_dir := Vector2.ZERO
var _cast_cd := 0.0
## What is in the hand right now, and the bar that shows it.
var _slots: HandSlots = null
var _bar: LoadoutBar = null

var _knobs := {
	"stiffness": 3000.0, "damping": 90.0, "max_torque": 14000.0, "air_factor": 0.2,
	"grav_scale": 2.0, "jump_speed": 700.0, "move_speed": 300.0, "upright_k": 55000.0, "punch_lunge": 3400.0,
}
var _knob_order := ["stiffness", "damping", "max_torque", "air_factor", "grav_scale", "jump_speed", "move_speed", "upright_k", "punch_lunge"]
var _sel := 0
var _show_tune := false


func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	RenderingServer.set_default_clear_color(Color(0.13, 0.14, 0.18))
	Atmosphere.add_glow(self)                 # 2D bloom so spell cores radiate
	_spells = SpellLibrary.build_all()
	_center_window()
	_build_world()
	_build_targets()
	_spawn_figure()
	_build_camera()
	_build_hud()
	_build_bar()
	_update_hud()


func _center_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	w.mode = Window.MODE_WINDOWED
	w.size = Vector2i(1280, 720)


func _build_world() -> void:
	var th := 44.0
	var mid_y := (FLOOR_Y + CEIL_Y) * 0.5
	var wall_h := (FLOOR_Y - CEIL_Y) + th * 2.0
	_static_rect(Vector2(0, FLOOR_Y + th * 0.5), Vector2(HALF_W * 2 + th * 2, th))   # floor
	_static_rect(Vector2(0, CEIL_Y - th * 0.5), Vector2(HALF_W * 2 + th * 2, th))    # ceiling
	_static_rect(Vector2(-HALF_W - th * 0.5, mid_y), Vector2(th, wall_h))            # left wall
	_static_rect(Vector2(HALF_W + th * 0.5, mid_y), Vector2(th, wall_h))             # right wall
	_static_rect(Vector2(-320, 150), Vector2(150, 22))                              # ledges to wall-jump
	_static_rect(Vector2(-90, -40), Vector2(150, 22))


func _static_rect(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = SpikeFigure.WORLD_LAYER   # layer 1 — stickman + dummies both stand on it
	body.collision_mask = 0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	poly.color = Color(0.32, 0.35, 0.42)
	poly.position = pos
	poly.z_index = -5
	add_child(poly)


func _build_targets() -> void:
	for cx: float in COVER_X:
		var block: Node2D = (load(DESTRUCTIBLE) as GDScript).new()
		block.position = Vector2(cx, FLOOR_Y - 32.0)
		add_child(block)
		_covers.append(block)
	var es: PackedScene = load(ENEMY_SCENE)
	for dx: float in DUMMY_X:
		var d: Node = es.instantiate()
		d.set("passive", true)
		d.set("max_hp", 99999)
		d.set("tint", Color(0.56, 0.56, 0.6))
		d.set("scale", Vector2(1.9, 1.9))            # match the stick fighter's size (dummies default ~half)
		d.set("position", Vector2(dx, FLOOR_Y - 100.0))
		add_child(d)
		d.add_to_group("dummy")
		_dummies.append(d)


func _spawn_figure() -> void:
	_fig = FIG.new()
	_fig.spawn_pos = Vector2(0, 120)
	_fig.body_color = FIG_COLOR
	_fig.configure(_knobs)
	add_child(_fig)
	_fig.punched.connect(_on_punch)
	_fig.parried.connect(_on_parried)


## The stickman's punch lands on nearby dummies: damage + a satisfying knockback shove.
## A punch that lands on a standing ROCK WALL instead SHOVES it — the wall becomes a
## grinding projectile that plows the arena until it hits something solid.
func _on_punch(dir: Vector2) -> void:
	_shake = maxf(_shake, 0.5)
	_shake_dir = dir
	var t: Node2D = _fig.get("_torso")
	if t == null:
		return
	var origin: Vector2 = t.global_position
	# Wall first: if one is in reach, the punch commits to shoving it rather than
	# also cutting through to whatever stands behind it.
	var wall: Node2D = RockWall.find_shoveable_near(get_tree(), origin, SHOVE_REACH)
	if wall != null:
		# footprint_center(), not global_position: the wall node sits at the arena
		# origin and draws in world coords. Gate on facing so punching AWAY from
		# a wall never drags it back onto you.
		var to_wall: Vector2 = wall.call("footprint_center") - origin
		if to_wall.normalized().dot(dir) > 0.1:
			if wall.call("shove", Vector2(signf(to_wall.x) if to_wall.x != 0.0 else 1.0, 0.0)):
				_shake = maxf(_shake, 0.9)
				return
	var connected := false
	for d in _dummies:
		if not is_instance_valid(d):
			continue
		var to: Vector2 = (d as Node2D).global_position - origin
		if to.length() < 96.0 and to.normalized().dot(dir) > 0.25:   # in front, in range
			connected = true
			if d.has_method("take_damage"):
				d.call("take_damage", 22)
			if d.has_method("apply_knockback"):
				d.call("apply_knockback", dir * 620.0)
	if connected:
		Sfx.play("melee_hit", 0.0, 0.1)              # the CONNECT crack (swing already played on the rig)


## A successful deflect: localized impact frame AT the parry point (ding + shell fire
## on the rig itself) — the curated "big deflect" beat from the feel study.
func _on_parried(world_pos: Vector2) -> void:
	Juice.impact_frame(0.45, world_pos)


## The League-style strip along the bottom: fists, then the spells you can reach.
## The playground carries all 26 so every spell stays reviewable; the real game
## caps this at four chosen out of combat.
func _build_bar() -> void:
	_slots = HandSlots.new()
	_slots.rebuild([], _spells)
	_slots.select(mini(_sidx + 1, _slots.slots.size() - 1))
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_bar = LoadoutBar.new()
	_bar.slots = _slots
	layer.add_child(_bar)
	_bar.slot_selected.connect(_on_slot_selected)


## Tapping a square picks it; slot 0 is fists, so spell indices are offset by one.
func _on_slot_selected(index: int) -> void:
	if index > 0:
		_sidx = wrapi(index - 1, 0, _spells.size())
	_update_hud()


func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = _fig.spawn_pos
	cam.zoom = Vector2(0.55, 0.55)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	add_child(cam)
	cam.make_current()
	_cam = cam


func _physics_process(_delta: float) -> void:
	if _fig == null:
		return
	_cast_cd = maxf(0.0, _cast_cd - _delta)
	# Movement through named actions too, so a virtual joystick can drive the
	# playground later without touching this file (the project's mobile-first rule
	# is that code names actions and never keys).
	_fig.ctrl_move_x = Input.get_axis("move_left", "move_right")
	# Jump is W/Up only — SPACE belongs to dash, matching the game's input map.
	_fig.ctrl_jump = Input.is_action_pressed("jump")
	_fig.ctrl_duck = Input.is_action_pressed("move_down")
	_fig.ctrl_aim = get_global_mouse_position()
	# Aim-hold is the CAST button held down, so it follows the rebind rather than
	# staying pinned to whatever the left mouse button happens to do.
	_fig.ctrl_aim_hold = Input.is_action_pressed("cast")


func _process(delta: float) -> void:
	if _cam != null and _fig != null:
		var t: Node = _fig.get("_torso")
		if t != null:
			_cam.position = (t as Node2D).global_position
		if _shake > 0.0:
			_shake = maxf(0.0, _shake - delta * 2.2)
			var amp := _shake * _shake * 5.0
			_cam.offset = _shake_dir * amp * 1.6 + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * 0.35
		else:
			_cam.offset = Vector2.ZERO


func _cast() -> void:
	if _fig == null or _spells.is_empty() or _cast_cd > 0.0:
		return
	_cast_cd = 0.35
	var t: Node2D = _fig.get("_torso")
	var origin: Vector2 = t.global_position if t != null else _fig.global_position
	var target: Vector2 = get_global_mouse_position()
	var spell: SpellDef = _spells[_sidx]
	# Rule 4: the rig throws each KIND of spell with its own body language — a wall
	# gets slammed out of the ground, a bombardment gets a ritual circle, a chidori
	# gets coiled into the chest. The pose fires FIRST so the windup reads as the
	# cause of the spectacle rather than a shrug alongside it.
	var pose: int = CastStyle.for_spell(spell.kind)
	_fig.cast((target - origin).normalized(), pose)
	SpellCaster.cast(spell, self, origin, target, Color(0.78, 0.84, 1.0), "", _fig)
	_shake = maxf(_shake, 0.35)
	_shake_dir = (target - origin).normalized()


## Dash toward held movement keys (true 8-way incl. straight up/down); with no
## direction held, dash toward the mouse aim.
func _dash() -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir == Vector2.ZERO:
		var t: Node2D = _fig.get("_torso")
		if t != null:
			dir = (get_global_mouse_position() - t.global_position).normalized()
	_fig.dash(dir)


## Lob a slow hostile test-bolt in from ahead of the figure, aimed at it — the
## deflect target: parry (C) as it arrives to reflect it back out with the ding.
func _spawn_test_bolt() -> void:
	var t: Node2D = _fig.get("_torso")
	if t == null:
		return
	var facing: float = _fig.get("_facing")
	var proj := EnemyProjectile.new()
	add_child(proj)
	proj.global_position = t.global_position + Vector2(facing * 330.0, -26.0)
	proj.launch((t.global_position - proj.global_position).normalized())


## Q/E and the scroll wheel move the SAME selection the bar shows, so the two
## never disagree about what is in your hand.
func _cycle_synced(d: int) -> void:
	_cycle(d)
	if _slots != null:
		_slots.select(_sidx + 1)


func _cycle(step: int) -> void:
	_sidx = (_sidx + step + _spells.size()) % _spells.size()
	_update_hud()


func _reset_arena() -> void:
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if _fig == null:
		return
	# The four combat verbs go through the ACTION MAP, not raw keys, so the
	# playground answers the same bindings the shipped game does instead of being
	# a third control scheme to remember: LMB cast · F melee · RMB deflect ·
	# SPACE dash. The sandbox-only keys below stay on raw keycodes deliberately —
	# they are debug affordances (spawn a bolt, kill, reset) and do not belong in
	# the game's input map.
	if event.is_action_pressed("cast"):
		# Holding the guard costs your offence — the trade that stops a sustained
		# hold being free. Same rule on every platform.
		if _fig.is_guarding():
			return
		if _slots != null and _slots.primary_action() == "punch":
			_fig.punch()
		else:
			_cast()
		return
	if event.is_action_pressed("melee"):
		_fig.punch()
		return
	if event.is_action_pressed("parry"):
		_fig.guard_press()
		return
	if event.is_action_released("parry"):
		_fig.guard_release()
		return
	if event.is_action_pressed("dash"):
		_dash()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				_cycle_synced(1)
			KEY_Q:
				_cycle_synced(-1)
			KEY_B:
				_spawn_test_bolt()
			KEY_H:
				var d := Vector2(_fig._facing if _fig._facing != 0 else 1.0, -0.35)
				_fig.hit(d.normalized(), 460.0)
			KEY_K:
				_fig.kill()
			KEY_R:
				_reset_arena()
			KEY_TAB:
				_show_tune = not _show_tune
				_update_hud()
			KEY_BRACKETLEFT:
				_adjust(0.926)
			KEY_BRACKETRIGHT:
				_adjust(1.08)
			_:
				var idx: int = event.keycode - KEY_1
				if idx >= 0 and idx < _knob_order.size():
					_sel = idx
					_update_hud()


func _adjust(factor: float) -> void:
	if not _show_tune:
		return
	var key: String = _knob_order[_sel]
	_knobs[key] = _knobs[key] * factor
	if _fig != null:
		_fig.configure(_knobs)
	_update_hud()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(20, 14)
	_hud.size = Vector2(1236, 320)
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hud)


func _update_hud() -> void:
	if _hud == null or _spells.is_empty():
		return
	var s: SpellDef = _spells[_sidx]
	var txt := "SPELL PLAYGROUND   [%d / %d]   %s\n%s · %s · dmg %d · cd %.1fs%s\n\nLMB  CAST toward mouse    F  punch    RMB  HOLD to guard    SPACE  dash    Q E / SCROLL  cycle    B  test-bolt    R  reset\nmove A/D · jump W/Up · duck/crawl S · aim mouse · H hit · K kill · TAB tune" % [
		_sidx + 1, _spells.size(), s.display_name,
		_kind_name(s.kind), _elem_name(s.element), int(s.damage), float(s.cooldown), _extra(s),
	]
	if _show_tune:
		txt += "\n\n-- physics tune (number keys select · [ ] adjust) --"
		for i in _knob_order.size():
			var key: String = _knob_order[i]
			var mark := ">" if i == _sel else " "
			txt += "\n%s %d %-11s %.1f" % [mark, i + 1, key, _knobs[key]]
	_hud.text = txt


func _extra(s: SpellDef) -> String:
	var parts: Array = []
	if s.count > 0:
		parts.append("x%d" % s.count)
	if s.radius > 0.0:
		parts.append("r%d" % int(s.radius))
	if s.reach > 0.0:
		parts.append("reach %d" % int(s.reach))
	return ("  ·  " + " · ".join(parts)) if not parts.is_empty() else ""


func _kind_name(k: int) -> String:
	match k:
		SpellDef.Kind.BEAM: return "BEAM"
		SpellDef.Kind.DIVINE_RAY: return "RAY"
		SpellDef.Kind.METEOR: return "METEOR"
		SpellDef.Kind.CONVERGENCE: return "CONVERGENCE"
		SpellDef.Kind.RUSH: return "RUSH"
		SpellDef.Kind.NOVA: return "NOVA"
		SpellDef.Kind.BOULDER: return "BOULDER"
		SpellDef.Kind.PILLAR: return "PILLAR"
		SpellDef.Kind.WALL: return "WALL"
		SpellDef.Kind.ICE_WALL: return "ICE WALL"
		SpellDef.Kind.CHAIN: return "CHAIN"
		SpellDef.Kind.ZONE: return "ZONE"
		SpellDef.Kind.MISSILES: return "MISSILES"
		SpellDef.Kind.TETHER: return "TETHER"
		SpellDef.Kind.FLURRY: return "FLURRY"
		SpellDef.Kind.BLINK_STRIKE: return "BLINK"
		SpellDef.Kind.CRAWLER: return "CRAWLER"
		SpellDef.Kind.THROWN_ANCHOR: return "ANCHOR"
	return "SPELL"


func _elem_name(e: int) -> String:
	match e:
		0: return "FIRE"
		1: return "ICE"
		2: return "LIGHTNING"
		3: return "SHADOW"
		4: return "ARCANE"
		5: return "EARTH"
		6: return "HOLY"
		7: return "WIND"
	return "—"
