# Run with the GUI binary:
#   python python-tools/run_capture.py boss_roster
# EVERY ARTIST IN THE TOWER, SIDE BY SIDE, ON ONE SHEET — one frame per roster id,
# each with its own name, epithet and body, framed at the size the player meets it.
#
# ⚠ WHY THIS EXISTS. `slice_test_bossmods` asserts that every artist "draws a body of
# its own size", and it asserts it as a COUNT of distinct rig heights. That is the right
# assertion and it is not a picture: when the Sensei shipped pointing at the Ashen
# Guardian's own scene, the count went from 6 to 6-across-7 and the failure text said
# "6 distinct across 7 bosses" — true, correct, and no help at all in seeing that two
# entries in the roster were the same person. A sheet is.
#
# Outputs one PNG per roster id: user://boss_roster_<id>.png
#
# ⚠ Under `--headless` Godot uses the DUMMY renderer and every PNG comes out blank
# while reporting success. Use the GUI binary (run_capture.py always does).
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const ROSTER_PATH: String = "res://scripts/tower/BossRoster.gd"

## Where the body stands and how tightly the camera holds it. Chosen so a 60 px
## Scribble and a 102 px Illuminator are BOTH fully in frame at the same zoom — the
## whole point is comparing them, and a per-boss framing would hide the size difference
## this sheet exists to show.
const STAND: Vector2 = Vector2(900.0, 300.0)
## ⚠ 1.9 -> 1.15, MEASURED OFF A SHEET. At 1.9 the tallest bodies ran off the bottom
## of frame — the rig draws DOWN from its origin as well as up, so "the figure is 99 px
## and the view is 189" was arithmetic about the wrong span. 1.15 holds every body on
## the roster whole, which is the only thing this sheet has to do.
const ZOOM: float = 1.15

var _arena: Node2D = null
var _cam: Camera2D = null


func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()


func _settle(n: int) -> void:
	for i: int in n:
		await process_frame


func _run() -> void:
	_arena = Node2D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_cam = Camera2D.new()
	_arena.add_child(_cam)
	_cam.make_current()
	_cam.zoom = Vector2(ZOOM, ZOOM)
	# ⚠ A FLOOR, AND THE FIRST SHEET PROVED WHY. A boss is a `CharacterBody2D` under
	# gravity, and a bare arena is a hole: at 50 settle frames the body had already
	# dropped far enough to be entering the bottom of frame, and at 240 it was gone
	# entirely, leaving a sheet of name cards over empty rooms. It photographed as
	# "the camera is framed wrong" — the body was simply somewhere else by then.
	# Layer 1 is what every rig's floor probe and every body's collision looks for.
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector2(STAND.x, STAND.y + 40.0)
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(1400.0, 60.0)
	cs.shape = box
	floor_body.add_child(cs)
	_arena.add_child(floor_body)

	# ⚠ READ OFF THE ROSTER, NEVER HAND-LISTED. A sheet with a hard-coded id list is a
	# sheet that silently stops covering the boss added tomorrow — which is exactly the
	# failure `slice_test_bossmods` had before it was driven off `BossRoster.ids()`.
	var roster: GDScript = load(ROSTER_PATH) as GDScript
	if roster == null:
		printerr("boss_roster_capture: could not load the roster")
		quit(1)
		return
	var ids: Array = roster.call("ids")
	for bid: String in ids:
		var boss: Node = _build(String(bid))
		if boss == null:
			printerr("boss_roster_capture: %s did not build" % bid)
			continue
		# ⚠ LONG ENOUGH FOR THE INTRO CARD TO CLEAR, and that number was measured not
		# guessed: at 50 frames the first sheet came back as a full-screen name card
		# with the body's head just entering the bottom edge. The ceremony is the point
		# of a boss arriving and it is NOT the point of this sheet, which is the body.
		await _settle(150)
		# Framed AFTER the settle, off the body's LIVE position — a camera parked before
		# the body has finished arriving frames where the body used to be.
		_cam.position = (boss as Node2D).global_position + Vector2(0.0, -46.0)
		await _settle(8)
		var title: String = String(boss.call("boss_title")) \
			if boss.has_method("boss_title") else "?"
		var h: float = 0.0
		var rig: Node = boss.get_node_or_null("Rig")
		if rig != null:
			h = float(rig.get("height"))
		var out: String = "user://boss_roster_%s.png" % bid
		var img: Image = root.get_texture().get_image()
		var err: int = img.save_png(out)
		print("%s  %-14s %-26s rig %.0f  %s"
			% ["ok " if err == OK else "ERR", bid, title, h, out])
		boss.queue_free()
		await _settle(4)
	quit(0)


## The same construction path `slice_test_bossmods._build` uses, so what is
## photographed is what is asserted about rather than a second way of making a boss.
func _build(bid: String) -> Node:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var data: Dictionary = {
		"boss": true, "hp": 600, "spd": 66.0, "touch": 26, "bscale": 1.0,
		"x": STAND.x, "y": STAND.y, "bid": bid,
	}
	var e: Node = enc.build_enemy_from_data(data)
	enc.free()
	if e == null:
		return null
	_arena.add_child(e)
	return e
