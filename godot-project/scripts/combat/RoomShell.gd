class_name RoomShell
extends Node2D
## THE TOWER ROOM, DRAWN. Maker: *"clearer to the user where it is"*.
##
## ⚠ WHY THIS DID NOT EXIST AND HAD TO. The tower arena's entire visual room was one
## flat `ColorRect` (`Arena.tscn/Floor`, a near-black wash) with four INVISIBLE wall
## colliders. Nothing marked where the ground was, so a hero stood on a line that was
## not drawn, inside a box whose edges were not drawn, in front of a backdrop the same
## colour as the air. Every readable thing on that stage was a fighter or a ledge.
##
## That was survivable while the room was 980x500 and the camera sat close. It is not
## survivable now: the room grew to 1220x560 and `CombatCamera.FRAME_ZOOM_MIN` dropped
## to 0.42 to fit it, so the widest shot draws everything ~16% smaller than before. A
## bigger emptier void is not what "make the map larger" asked for.
##
## ⚠ AND IT IS DELIBERATELY ALMOST NOTHING. `ArenaTerrain` — the versus stage's ground
## — draws strata, cracks, boulders, pebbles and moss, which is right for a stage you
## stand still and look at. This is a one-screen brawl against the maker's standing
## "super simple" bar, so the shell draws exactly three things and no texture at all:
## a dark frame, a ground body, and RULE 1 of the stage legend (`StageLayers`) — the
## lit warm cap that means YOU CAN STAND ON THIS. The tower's ledges have worn that
## cap since they existed; its GROUND never did, which is the one place the legend was
## a legend with a hole in it.
##
## No collision. `Arena.tscn/Walls` already owns every collider in the room; a second
## body agreeing with it is a second body that can disagree with it.

## The room's own frame — near-black, so the play area is a lit stage inside a dark
## box. Not pure black: `StageLayers` reserves that read for a pit that kills you.
const FRAME: Color = StageLayers.UNDERSIDE
## How far past the walls to paint the frame. The fit-all camera reveals world well
## outside the room on the short axis, and a frame that stopped at the collider would
## show a hard edge with the sky behind it.
const BLEED: float = 220.0
## Wall thickness, matching `Arena.WALL_THICKNESS` / `FloorGen.WALL_THICKNESS`. The
## bottom wall is CENTRED on y = room_h, so the standable floor is half of this above.
const WALL: float = 16.0
## How deep the drawn ground body is. Only ever seen when the camera looks under the
## room, which the framing camera routinely does on a wide, short roll.
const GROUND_DEPTH: float = 180.0
## The ground body against the wash. Multiplied, not replaced, so each biome's floor
## is that biome's colour — a Frostmarch floor must not be the same slab as an
## Emberworks one, which is the whole point of `EnvTheme` carrying a hue per floor.
const GROUND_MIX: float = 0.62
## ...and the air above it lifts slightly, so the floor plane reads as a HORIZON
## rather than as a colour change nobody notices. Small on purpose: a strong split
## would draw the eye to the back wall, and the eye belongs on the fighters.
const AIR_LIFT: float = 0.10

var room_size: Vector2 = Vector2(1160.0, 540.0)
var tint: Color = Color(0.20, 0.18, 0.19)


func _ready() -> void:
	StageLayers.apply(self, StageLayers.TERRAIN)  # the one z table; see StageLayers
	queue_redraw()


## Re-shape the room. Called from `Arena._apply_room_size` on every floor, so it must
## be safe to call repeatedly on the same node.
func build(size: Vector2, room_tint: Color = Color(0, 0, 0, 0)) -> void:
	room_size = size
	if room_tint.a > 0.0:
		tint = room_tint
	queue_redraw()


func _draw() -> void:
	var w: float = room_size.x
	var h: float = room_size.y
	var ground_y: float = h - WALL * 0.5

	# --- the air. A hair lighter than the wash so the ground reads as a floor and
	# not as the same darkness continuing downward.
	draw_rect(Rect2(0.0, 0.0, w, ground_y), tint.lightened(AIR_LIFT), true)

	# --- the ground body, in this floor's own hue.
	var ground: Color = Color(tint.r * GROUND_MIX, tint.g * GROUND_MIX, tint.b * GROUND_MIX, 1.0)
	draw_rect(Rect2(0.0, ground_y, w, GROUND_DEPTH), ground, true)

	# --- RULE 1. The one bright warm horizontal line on the stage, and now the
	# ground wears the same one the ledges do.
	var cap: float = StageLayers.cap_height(WALL * 2.0)
	draw_rect(Rect2(0.0, ground_y, w, cap), StageLayers.CAP_CORE, true)
	draw_rect(Rect2(0.0, ground_y, w, cap * 0.45), StageLayers.CAP_LIT, true)

	# --- the frame: everything OUTSIDE the walls, painted flat so the room is a
	# legible rectangle at a glance. Drawn as four bands rather than one polygon
	# because four rects is the cheapest thing a tile GPU can be asked for, and this
	# repaints on every floor.
	# ⚠ THE SIDES ARE FLAT AND UNLIT ON PURPOSE. A lit inner edge on a vertical
	# surface is a tall bright bar, and tall bright bars either side of the fight are
	# how this stage earned the word "blinds" the first time. The cap is horizontal,
	# and horizontal is the whole signal.
	draw_rect(Rect2(-BLEED, -BLEED, w + BLEED * 2.0, BLEED), FRAME, true)                    # above
	draw_rect(Rect2(-BLEED, h + WALL * 0.5, w + BLEED * 2.0, BLEED), FRAME, true)            # below
	draw_rect(Rect2(-BLEED, -BLEED, BLEED, h + BLEED * 2.0), FRAME, true)                    # left
	draw_rect(Rect2(w, -BLEED, BLEED, h + BLEED * 2.0), FRAME, true)                         # right
