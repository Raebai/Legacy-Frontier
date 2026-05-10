extends Node2D

# v0.5 layout: two rooms connected by a 3-tile-tall corridor.
#
#   First room          Connector       Second room
#   x ∈ [0, 23]         x ∈ [24, 27]    x ∈ [28, 47]
#   y ∈ [0, 15]         y ∈ [7, 9]      y ∈ [0, 15]
#
# Doorway gaps in the inner walls (x=23 and x=28 at y ∈ [7,9]) are floor.
# Stone fills the cross-strip between rooms above/below the connector
# (x ∈ [24, 27], y ∉ [7, 9]) so the camera never reveals void.

const WORLD_WIDTH: int = 48
const WORLD_HEIGHT: int = 16
const FIRST_ROOM_X_END: int = 23  # last column of the first room
const SECOND_ROOM_X_START: int = 28  # first column of the second room
const CONNECTOR_X_START: int = 24
const CONNECTOR_X_END: int = 27
const CONNECTOR_Y_START: int = 7
const CONNECTOR_Y_END: int = 9
const SOURCE_ID: int = 0
const GRASS_TILE: Vector2i = Vector2i(0, 0)
const WALL_TILE: Vector2i = Vector2i(1, 0)

@onready var tilemap: TileMapLayer = $TileMapLayer


func _ready() -> void:
	_paint_world()


func _paint_world() -> void:
	for x in range(WORLD_WIDTH):
		for y in range(WORLD_HEIGHT):
			var atlas_coords: Vector2i = _classify(x, y)
			tilemap.set_cell(Vector2i(x, y), SOURCE_ID, atlas_coords)


func _classify(x: int, y: int) -> Vector2i:
	var in_connector_y: bool = y >= CONNECTOR_Y_START and y <= CONNECTOR_Y_END
	# Connector strip (the 4×16 vertical band between rooms).
	if x >= CONNECTOR_X_START and x <= CONNECTOR_X_END:
		# Floor only inside the 3-tall corridor; stone everywhere else
		# in the strip so the camera never reveals void.
		return GRASS_TILE if in_connector_y else WALL_TILE
	# First room (x ∈ [0, 23]).
	if x <= FIRST_ROOM_X_END:
		var on_first_border: bool = (
			x == 0
			or y == 0
			or y == WORLD_HEIGHT - 1
			or (x == FIRST_ROOM_X_END and not in_connector_y)
		)
		return WALL_TILE if on_first_border else GRASS_TILE
	# Second room (x ∈ [28, 47]).
	var on_second_border: bool = (
		x == WORLD_WIDTH - 1
		or y == 0
		or y == WORLD_HEIGHT - 1
		or (x == SECOND_ROOM_X_START and not in_connector_y)
	)
	return WALL_TILE if on_second_border else GRASS_TILE
