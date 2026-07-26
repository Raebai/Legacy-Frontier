extends Node2D
## SPELL AUDIT SANDBOX — cycle through every spell and fire it at destructible cover
## + practice dummies to review its VFX, its DAMAGE, and how it DESTROYS the arena.
## Throwaway sandbox (like the stickman RigSpike): touches no game logic, just spawns
## the real spell spectacles via SpellCaster. Delete scenes/spike/ + scripts/spike/ to remove.
##
## CONTROLS:  ← →  (or A/D, [ ])  cycle spell    SPACE / ENTER / click  CAST    R  reset arena

const ENEMY_SCENE := "res://scenes/combat/Enemy.tscn"
const DESTRUCTIBLE := "res://scripts/combat/DestructibleTerrain.gd"
const COMBAT_CAMERA := "res://scripts/combat/CombatCamera.gd"

const GROUND_Y := 470.0
const CASTER := Vector2(250.0, GROUND_Y - 44.0)   # where the spell originates (a marker)
const TARGET := Vector2(515.0, GROUND_Y - 30.0)   # where point-spells land / beams cross
const COVER_X := [455.0, 545.0, 635.0]
const DUMMY_X := [500.0, 590.0]

var _spells: Array = []
var _idx := 0
var _cam: Camera2D
var _hud: Label
var _covers: Array = []
var _dummies: Array = []
var _permanent: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spells = SpellLibrary.build_all()
	_build_background()
	_build_camera()
	_build_ground()
	_build_hud()
	_center_window()
	_build_targets()
	_update_hud()


func _center_window() -> void:
	var w := get_window()
	if w != null:
		w.size = Vector2i(1280, 720)


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.17)
	bg.size = Vector2(4000, 3000)
	bg.position = Vector2(-1500, -1600)
	bg.z_index = -100
	add_child(bg)
	_permanent.append(bg)


func _build_camera() -> void:
	var cam: Camera2D = (load(COMBAT_CAMERA) as GDScript).new()
	add_child(cam)
	cam.position = Vector2(505, 375)
	cam.zoom = Vector2(1.08, 1.08)
	if cam.has_method("set_base_zoom"):
		cam.call("set_base_zoom", 1.08)
	cam.make_current()
	_cam = cam
	_permanent.append(cam)


func _build_ground() -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(505, GROUND_Y + 220)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(2400, 440)
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	_permanent.append(body)
	var g := Polygon2D.new()
	g.polygon = PackedVector2Array([
		Vector2(-700, GROUND_Y), Vector2(1700, GROUND_Y),
		Vector2(1700, GROUND_Y + 440), Vector2(-700, GROUND_Y + 440),
	])
	g.color = Color(0.27, 0.25, 0.21)
	g.z_index = -10
	add_child(g)
	_permanent.append(g)


func _build_targets() -> void:
	for cx: float in COVER_X:
		var block: Node2D = (load(DESTRUCTIBLE) as GDScript).new()
		block.position = Vector2(cx, GROUND_Y - 32.0)
		add_child(block)
		_covers.append(block)
	var es: PackedScene = load(ENEMY_SCENE)
	for dx: float in DUMMY_X:
		var d: Node = es.instantiate()
		d.set("passive", true)          # no chase/attack AI; "dies" -> respawns in place
		d.set("max_hp", 99999)          # tanky — audit, not a kill
		d.set("tint", Color(0.56, 0.56, 0.6))
		d.set("position", Vector2(dx, GROUND_Y - 46.0))
		add_child(d)
		d.add_to_group("dummy")         # also joins "enemy" via Enemy._ready -> spells hit it
		_dummies.append(d)


func _reset_arena() -> void:
	# free everything that isn't a permanent fixture (cover, dummies, spent spell/debris nodes)
	for child: Node in get_children():
		if child in _permanent:
			continue
		if child is CanvasLayer:      # the HUD layer
			continue
		child.queue_free()
	_covers.clear()
	_dummies.clear()
	call_deferred("_build_targets")


func _cast() -> void:
	if _spells.is_empty():
		return
	var spell: SpellDef = _spells[_idx]
	SpellCaster.cast(spell, self, CASTER, TARGET, Color(0.78, 0.84, 1.0), "")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT, KEY_D, KEY_BRACKETRIGHT:
				_idx = (_idx + 1) % _spells.size()
				_update_hud()
			KEY_LEFT, KEY_A, KEY_BRACKETLEFT:
				_idx = (_idx - 1 + _spells.size()) % _spells.size()
				_update_hud()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_cast()
			KEY_R:
				_reset_arena()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cast()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(22, 14)
	_hud.size = Vector2(1236, 300)
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hud)


func _update_hud() -> void:
	if _hud == null or _spells.is_empty():
		return
	var s: SpellDef = _spells[_idx]
	_hud.text = "SPELL AUDIT   [%d / %d]   %s\n%s · %s · dmg %d · mp %d · cd %.1fs%s\n\n%s\n\n<- ->  cycle spell     SPACE / click  CAST     R  reset arena" % [
		_idx + 1, _spells.size(), s.display_name,
		_kind_name(s.kind), _elem_name(s.element), int(s.damage), int(s.mp_cost), float(s.cooldown),
		_extra(s), s.description,
	]


func _extra(s: SpellDef) -> String:
	var parts: Array = []
	if s.count > 0:
		parts.append("x%d" % s.count)
	if s.radius > 0.0:
		parts.append("r%d" % int(s.radius))
	if s.reach > 0.0:
		parts.append("reach %d" % int(s.reach))
	if s.length > 0.0 and s.kind == SpellDef.Kind.BEAM:
		parts.append("len %d" % int(s.length))
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


func _draw() -> void:
	# a small caster marker so it's clear where the spells come from
	draw_circle(CASTER + Vector2(0, -20), 9.0, Color(0.85, 0.88, 0.95))
	draw_line(CASTER + Vector2(0, -11), CASTER + Vector2(0, 22), Color(0.85, 0.88, 0.95), 5.0)
	draw_line(CASTER + Vector2(0, 22), CASTER + Vector2(-9, 42), Color(0.85, 0.88, 0.95), 5.0)
	draw_line(CASTER + Vector2(0, 22), CASTER + Vector2(9, 42), Color(0.85, 0.88, 0.95), 5.0)
