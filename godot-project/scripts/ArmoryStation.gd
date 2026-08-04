extends StaticBody2D
## A TOWN STATION — a thing you walk up to and press interact on, which opens one
## of the screens the game already had and no player could reach.
##
## TWO KINDS, one script, because they differ only in what they draw and which
## screen they open:
##
##   * `"armory"` — a weapon rack. Opens `Loadout` (3 slots x 19 pieces with real
##     effect bags that `Hero._aggregate_gear` already consumes). This had been
##     built, finished, and unreachable behind a literal `if false:` in the parked
##     hub since the day it was written.
##   * `"spells"` — a lectern. Opens the `Outfitter`: **choose your three** of your
##     class's five authored roles (six hands per class, 54 across the roster) plus
##     your colourway. The only customisation in the game that changes how you fight.
##   * `"sparring"` — a chalk ring with adummy. Opens FREE PLAY: no enemies, no
##     stakes, just your three spells. This is the game's only onboarding surface
##     and it used to be a title-screen button, which is the one place a player is
##     not yet curious. In the room, it is a thing you walk past on your way to
##     the door.
##   * `"party"` — a standing stone, and the ONLY station that is co-op-only:
##     `World` does not spawn it in a solo session. Press it to begin the climb
##     together (host) or to read who is here (client).
##
## ⚠ THE STATION IS THE SCREEN. It does not open a menu that then offers the
## armory; pressing interact on the rack IS opening the armory. That is the whole
## defence against the town being "another layer" — see the rules at the top of
## `World.gd`.

## Set by `World._spawn_stations` before the node enters the tree.
@export var kind: String = "armory"

const PROXIMITY_RADIUS: float = 46.0
const RACK_COLOR: Color = Color(0.32, 0.26, 0.2)
const BLADE_COLOR: Color = Color(0.7, 0.75, 0.82)
const LECTERN_COLOR: Color = Color(0.26, 0.22, 0.30)
const PAGE_COLOR: Color = Color(0.90, 0.88, 0.80)

var _hint: Label = null
var _in_range: bool = false


func _ready() -> void:
	match kind:
		"spells": _build_lectern()
		"tree": _build_lectern()
		"sparring": _build_ring()
		"party": _build_stone()
		_: _build_rack()

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26.0, 30.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -15.0)
	add_child(shape)

	var area := Area2D.new()
	add_child(area)
	var area_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PROXIMITY_RADIUS
	area_shape.shape = circle
	area_shape.position = Vector2(0.0, -15.0)
	area.add_child(area_shape)
	area.body_entered.connect(func(b: Node) -> void:
		if b.is_in_group("player"):
			_in_range = true
			_hint.visible = true)
	area.body_exited.connect(func(b: Node) -> void:
		if b.is_in_group("player"):
			_in_range = false
			_hint.visible = false)

	_hint = Label.new()
	_hint.text = _hint_text()
	_hint.position = Vector2(-32.0, -60.0)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.visible = false
	add_child(_hint)


## A post with a couple of blades leaning on it.
func _build_rack() -> void:
	var post := ColorRect.new()
	post.color = RACK_COLOR
	post.size = Vector2(6.0, 34.0)
	post.position = Vector2(-3.0, -34.0)
	add_child(post)
	for dx: float in [-9.0, 9.0]:
		var blade := ColorRect.new()
		blade.color = BLADE_COLOR
		blade.size = Vector2(3.0, 28.0)
		blade.position = Vector2(dx, -30.0)
		blade.rotation = 0.2 * signf(dx)
		add_child(blade)


## A slanted reading stand with an open page on it — the page is the only bright
## thing at this end of the town, so it reads as "there is something here".
func _build_lectern() -> void:
	var stand := ColorRect.new()
	stand.color = LECTERN_COLOR
	stand.size = Vector2(8.0, 30.0)
	stand.position = Vector2(-4.0, -30.0)
	add_child(stand)
	var desk := Polygon2D.new()
	desk.polygon = PackedVector2Array([
		Vector2(-16.0, -30.0), Vector2(16.0, -34.0),
		Vector2(16.0, -28.0), Vector2(-16.0, -24.0),
	])
	desk.color = LECTERN_COLOR
	add_child(desk)
	# A soft warm wash behind the page. The lectern is the smallest silhouette in
	# the town and on the first capture it read as a white stick; the glow is what
	# makes it announce itself from across the street.
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.86, 0.55, 0.10)
	glow.size = Vector2(56.0, 40.0)
	glow.position = Vector2(-28.0, -56.0)
	glow.z_index = -1
	add_child(glow)
	var page := Polygon2D.new()
	page.polygon = PackedVector2Array([
		Vector2(-16.0, -34.0), Vector2(0.0, -38.0),
		Vector2(16.0, -42.0), Vector2(16.0, -36.0),
		Vector2(0.0, -32.0), Vector2(-16.0, -28.0),
	])
	page.color = PAGE_COLOR
	add_child(page)


## A chalk ring on the ground with a straw dummy standing in it. Drawn low and
## wide so it reads as somewhere you STEP INTO rather than something you press —
## the ring is the invitation, the dummy is what tells you it is for hitting.
func _build_ring() -> void:
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	for i: int in 20:
		var a: float = TAU * float(i) / 20.0
		pts.append(Vector2(cos(a) * 30.0, -2.0 + sin(a) * 8.0))
	ring.polygon = pts
	# ⚠ 0.10 WAS INVISIBLE. Judged from `town_capture`, not from the number: at a
	# tenth alpha over this backdrop the ring read as a smudge and the whole station
	# looked like a second weapon rack. The ring is the part that says "step in".
	ring.color = Color(0.85, 0.85, 0.80, 0.22)
	ring.z_index = -1
	add_child(ring)
	var post := ColorRect.new()
	post.color = RACK_COLOR
	post.size = Vector2(5.0, 30.0)
	post.position = Vector2(-2.5, -30.0)
	add_child(post)
	var torso := ColorRect.new()
	torso.color = Color(0.62, 0.55, 0.36)   # straw
	torso.size = Vector2(16.0, 16.0)
	torso.position = Vector2(-8.0, -34.0)
	add_child(torso)
	var arms := ColorRect.new()
	arms.color = Color(0.62, 0.55, 0.36)
	arms.size = Vector2(30.0, 4.0)
	arms.position = Vector2(-15.0, -30.0)
	add_child(arms)
	# A HEAD, so the silhouette is a FIGURE. Without it the post-and-crossbar read
	# as the weapon rack from across the room — same brown, same height, and the
	# player has no reason to walk over and find out which is which.
	var head := ColorRect.new()
	head.color = Color(0.70, 0.63, 0.44)
	head.size = Vector2(10.0, 10.0)
	head.position = Vector2(-5.0, -44.0)
	add_child(head)


## A standing stone. Tall, plain and lit — it has to read from across the room
## because it is the thing you look for when a friend is supposed to be here.
func _build_stone() -> void:
	var stone := Polygon2D.new()
	stone.polygon = PackedVector2Array([
		Vector2(-10.0, 0.0), Vector2(-7.0, -40.0),
		Vector2(7.0, -44.0), Vector2(11.0, 0.0),
	])
	stone.color = Color(0.30, 0.32, 0.38)
	add_child(stone)
	var glow := ColorRect.new()
	glow.color = Color(0.55, 0.85, 1.0, 0.12)
	glow.size = Vector2(44.0, 52.0)
	glow.position = Vector2(-22.0, -58.0)
	glow.z_index = -1
	add_child(glow)


## The hint IS the state for the party stone — it is the only station whose label
## changes with the world rather than with the player.
func _hint_text() -> String:
	match kind:
		"spells": return "[E] Spells"
		"tree": return _tree_hint()
		"sparring": return "[E] Sparring ring"
		"party":
			var net: Node = get_node_or_null(^"/root/Net")
			if net == null or not bool(net.call(&"is_active")):
				return "nobody here yet"
			if not bool(net.call(&"is_host")):
				return "waiting for the host"
			return "[E] Begin the climb together"
		_: return "[E] Armory"


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("talk") or not _in_range:
		return
	if _overlay_open():
		return
	if kind == "sparring":
		# Free play is reached BY PATH and by static call, exactly as the title screen
		# reaches it: a bare identifier would drag the versus arena's whole dependency
		# chain into a script that loads with the town.
		var fp: GDScript = load("res://scripts/combat/FreePlay.gd") as GDScript
		if fp != null:
			var gs: Node = get_node_or_null(^"/root/GameState")
			var cls: int = 0 if gs == null else int(gs.get("selected_class"))
			get_viewport().set_input_as_handled()
			fp.call("enter", get_tree(), cls)
		return
	if kind == "party":
		# Only the HOST can start; a client pressing this is answered by the hint,
		# which already says what it is waiting for.
		var net: Node = get_node_or_null(^"/root/Net")
		if net != null and bool(net.call(&"is_active")) and bool(net.call(&"is_host")):
			get_viewport().set_input_as_handled()
			net.call(&"start_coop_run")
		elif _hint != null:
			_hint.text = _hint_text()   # re-read: a friend may have joined since
		return
	if kind == "tree":
		# Same ownership rule as the Outfitter below: a full-screen Control cannot be
		# parented to a StaticBody2D sitting in world space, so the town owns it.
		var town_t: Node = get_tree().current_scene
		if town_t != null and town_t.has_method("open_spell_tree"):
			town_t.call("open_spell_tree")
			get_viewport().set_input_as_handled()
		return
	if kind == "spells":
		# The Outfitter is a Control and needs a CanvasLayer, so the town owns its
		# lifetime rather than this station parenting a full-screen panel to a
		# StaticBody2D sitting in world space.
		var town: Node = get_tree().current_scene
		if town != null and town.has_method("open_outfitter"):
			town.call("open_outfitter")
			get_viewport().set_input_as_handled()
		return
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("open"):
		lo.call("open")
		get_viewport().set_input_as_handled()


## True while any other town screen is up. See the same helper on `NPC.gd`.
func _overlay_open() -> bool:
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		return true
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("is_open") and lo.is_open():
		return true
	for o: Node in get_tree().get_nodes_in_group("town_overlay"):
		if o is CanvasItem and (o as CanvasItem).visible:
			return true
	return false


## ⚠ THE HINT CARRIES THE UNSPENT-POINT COUNT, and that is the only prompting the
## tree gets. A level-up already fires a spectacle in the fight; a second nag in the
## town would be the "you have unspent points!" badge that every RPG menu wears and
## that this town's whole design brief exists to avoid. But a player who has never
## opened this screen has no way to learn a point is waiting, so the station says so
## and then says nothing else.
func _tree_hint() -> String:
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs == null:
		return "[E] The Archivist"
	var owned: Array = gs.get("unlocked_nodes") as Array
	var spare: int = SpellTree.points_available(int(gs.call("level")), owned)
	if spare <= 0:
		return "[E] The Archivist"
	return "[E] The Archivist  ·  %d point%s" % [spare, "" if spare == 1 else "s"]
