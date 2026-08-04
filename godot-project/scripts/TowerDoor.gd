extends StaticBody2D
## The tower ENTRANCE in the hub — a doorway you WALK INTO.
##
## ⚠ THE RULING REVERSED, AND BOTH HALVES WERE THE MAKER'S. It was "I shouldn't just
## walk into a circle; it should be a door, press E near it" — so it became a door
## with a keypress. It is now "when you get close to the door, like you can walk into
## it and be teleported instead of pressing a certain button". Both asks are the same
## underlying complaint: the DOOR is the thing, not the prompt. So it keeps the door
## and loses the key.
##
## ⚠ WHICH MEANS THE SOLID COLLIDER HAD TO GO. It existed precisely to stop you
## walking through ("must press E"); leaving it in place with a walk-in trigger would
## mean bumping into an invisible wall an inch before the thing that teleports you.
##
## ⚠ AND THE TRIGGER IS NOT THE HINT RING. You SPAWN inside the hint ring (that is
## deliberate — `World.PLAYER_SPAWN` is on the doorstep so leaving costs zero walking),
## so a walk-in on the same radius would fire on the first frame of the town and you
## would never see the room at all. There are two rings now: the wide one lights the
## threshold, the narrow one at the doorway itself takes you.
const HINT_TEXT: String = "walk in"
const FRAME_COLOR: Color = Color(0.16, 0.15, 0.2)
const STONE_COLOR: Color = Color(0.26, 0.24, 0.3)
const GLOW_COLOR: Color = Color(1.0, 0.62, 0.3)      # warm arcane threshold glow
## ⚠ BIGGER, BECAUSE IT IS THE DESTINATION. Maker: "the tower should be way higher and
## further out to the right slightly and just look cooler". 62x96 read as a garden
## gate next to a figure 31 px tall; this is a tower mouth you walk into.
const DOOR_W: float = 96.0
const DOOR_H: float = 188.0
## How far the tower rises ABOVE its own doorway — drawn, not collided, so it costs
## nothing but silhouette. This is most of "way higher".
const TOWER_RISE: float = 300.0
const TOWER_TAPER: float = 0.62      # how much narrower the top is than the base
## The step you cross to be taken. Narrower than the spawn offset (54) so standing
## still on arrival never triggers it.
const ENTER_RADIUS: float = 34.0
## ⚠ SIZED TO REACH THE SPAWN POINT. `World.PLAYER_SPAWN` is `TOWER_X - 54`, on the
## doorstep, so the hint is up on the town's FIRST FRAME and leaving costs one key
## press and zero steps of walking. Shrinking this re-introduces the walk this
## whole layout exists to delete — see rule 2 at the top of `World.gd`.
## ⚠ WIDENED WITH THE DOORWAY. `World.PLAYER_SPAWN` stands you 104 px out now (the
## door is 96 wide and you WALK INTO it, so the old 54 put you on the threshold), and
## a hint ring that no longer reaches the spawn point means the town opens with no
## sign of the way out at all.
const PROXIMITY_RADIUS: float = 150.0

var _hint: Label = null
var _in_range: bool = false
var _phase: float = 0.0


func _ready() -> void:
	# Threshold glow (behind the door — pulses in _process).
	var glow := ColorRect.new()
	glow.name = "Glow"
	glow.color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.5)
	glow.size = Vector2(DOOR_W - 12.0, DOOR_H - 12.0)
	glow.position = Vector2(-(DOOR_W - 12.0) * 0.5, -DOOR_H + 4.0)
	glow.z_index = -1
	add_child(glow)
	# Stone door body (dark) + a lighter arched frame around it.
	var frame := ColorRect.new()
	frame.color = STONE_COLOR
	frame.size = Vector2(DOOR_W + 16.0, DOOR_H + 12.0)
	frame.position = Vector2(-(DOOR_W + 16.0) * 0.5, -DOOR_H - 6.0)
	add_child(frame)
	var arch := Polygon2D.new()  # a pointed keystone arch on top
	arch.polygon = PackedVector2Array([
		Vector2(-(DOOR_W + 16.0) * 0.5, -DOOR_H - 6.0),
		Vector2((DOOR_W + 16.0) * 0.5, -DOOR_H - 6.0),
		Vector2(0.0, -DOOR_H - 34.0),
	])
	arch.color = STONE_COLOR
	add_child(arch)
	var door := ColorRect.new()
	door.color = FRAME_COLOR
	door.size = Vector2(DOOR_W, DOOR_H)
	door.position = Vector2(-DOOR_W * 0.5, -DOOR_H)
	add_child(door)
	_build_shaft()
	# NO SOLID COLLIDER — see the header. The doorway is a threshold, not a wall.
	# Proximity trigger + hint.
	var area := Area2D.new()
	add_child(area)
	# ⚠ MASK 1 AND 2 — see the same note on `ArmoryStation`. The town body is a `Hero`
	# (collision layer 2) since casting moved into the lobby; an Area2D's default mask
	# of 1 stopped seeing it, and the door went as quiet as the pads.
	area.collision_mask = 1 | 2
	var area_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PROXIMITY_RADIUS
	_build_threshold()
	area_shape.shape = circle
	area_shape.position = Vector2(0.0, -DOOR_H * 0.5)
	area.add_child(area_shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_hint = Label.new()
	_hint.text = HINT_TEXT
	_hint.position = Vector2(-58.0, -DOOR_H - 54.0)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.visible = false
	add_child(_hint)


func _process(delta: float) -> void:
	_phase += delta
	var glow: ColorRect = get_node_or_null("Glow")
	if glow != null:
		glow.color.a = 0.35 + 0.2 * (0.5 + 0.5 * sin(_phase * 2.2))


## THE TOWER ITSELF, above the door: a tapering shaft with banded courses and a lit
## crown, behind everything else so the doorway stays the brightest thing at ground
## level. Drawn as flat polygons in the same palette as the frame — this is a
## silhouette against the sky, not a building.
func _build_shaft() -> void:
	var base_half: float = (DOOR_W + 16.0) * 0.5
	var top_half: float = base_half * TOWER_TAPER
	var top_y: float = -DOOR_H - 34.0 - TOWER_RISE
	var shaft := Polygon2D.new()
	shaft.polygon = PackedVector2Array([
		Vector2(-base_half, -DOOR_H - 6.0), Vector2(base_half, -DOOR_H - 6.0),
		Vector2(top_half, top_y), Vector2(-top_half, top_y),
	])
	shaft.color = STONE_COLOR.darkened(0.35)
	shaft.z_index = -3
	add_child(shaft)
	# Courses: a few lighter bands so the height reads as STOREYS rather than as one
	# long block. Four is enough to scale it and cheap enough to cost nothing.
	for i: int in 4:
		var t: float = (float(i) + 1.0) / 5.0
		var y: float = lerpf(-DOOR_H - 6.0, top_y, t)
		var half: float = lerpf(base_half, top_half, t)
		var band := Polygon2D.new()
		band.polygon = PackedVector2Array([
			Vector2(-half, y), Vector2(half, y),
			Vector2(half * 0.99, y + 5.0), Vector2(-half * 0.99, y + 5.0),
		])
		band.color = STONE_COLOR.darkened(0.15)
		band.z_index = -2
		add_child(band)
	# The crown: a lit slit at the top, the same warm colour as the threshold, so the
	# eye is walked from the door up the shaft and off the top of the screen.
	var crown := ColorRect.new()
	crown.color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.55)
	crown.size = Vector2(top_half * 0.5, 26.0)
	crown.position = Vector2(-top_half * 0.25, top_y + 22.0)
	crown.z_index = -1
	add_child(crown)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = true
		_hint.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = false
		_hint.visible = false


## THE STEP THAT TAKES YOU. A second, much tighter Area2D on the doorway itself.
##
## ⚠ IT LATCHES. `enter_run` is not idempotent and a body can register more than one
## overlap frame while the scene is still swapping, so a bare `body_entered` could
## start the run twice. One shot per doorway, and the doorway is freed with the town.
func _build_threshold() -> void:
	var step := Area2D.new()
	step.collision_mask = 1 | 2   # the town body is a Hero (layer 2); see ArmoryStation
	add_child(step)
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = ENTER_RADIUS
	cs.shape = c
	cs.position = Vector2(0.0, -DOOR_H * 0.4)
	step.add_child(cs)
	step.body_entered.connect(func(b: Node) -> void:
		if b.is_in_group("player") and not _entering:
			_entering = true
			_enter())


var _entering: bool = false


## ⚠ E STILL WORKS, AND IT IS NOT A LEFTOVER. Walking in is the way the maker asked
## for; the key is what a controller and the touch pad's `talk` button press, and
## removing it would make the tower unreachable on a device with no walking precision.
## Both routes land in `_enter`, so there is one set of guards, not two.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("talk") or not _in_range:
		return
	get_viewport().set_input_as_handled()
	_enter()


## Start the run — unless a town screen is up. The door sits UNDER the panels, so a
## stray Enter while picking a class must not start a climb, and neither must a body
## nudged across the threshold by a screen closing.
func _enter() -> void:
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		_entering = false
		return
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("is_open") and lo.is_open():
		_entering = false
		return
	for o: Node in get_tree().get_nodes_in_group("town_overlay"):
		if o is CanvasItem and (o as CanvasItem).visible:
			_entering = false
			return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("enter_run"):
		gs.enter_run()
