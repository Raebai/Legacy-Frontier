extends Node2D

const ROOM_WIDTH: int = 24
const ROOM_HEIGHT: int = 16
const SOURCE_ID: int = 0
const GRASS_TILE: Vector2i = Vector2i(0, 0)
const WALL_TILE: Vector2i = Vector2i(1, 0)

@onready var tilemap: TileMapLayer = $TileMapLayer


func _ready() -> void:
	_paint_room()


func _paint_room() -> void:
	for x in range(ROOM_WIDTH):
		for y in range(ROOM_HEIGHT):
			var is_border: bool = (
				x == 0 or x == ROOM_WIDTH - 1
				or y == 0 or y == ROOM_HEIGHT - 1
			)
			var atlas_coords: Vector2i = WALL_TILE if is_border else GRASS_TILE
			tilemap.set_cell(Vector2i(x, y), SOURCE_ID, atlas_coords)
