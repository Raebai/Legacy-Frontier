class_name LayoutDef
extends Resource
## The physical shape of a floor's room, as data. The one arena shell is
## parameterized by these (size, where enemies may spawn, where the exit and
## crates sit). Seam for later: an optional layout_scene: PackedScene can be
## added for bespoke hand-authored rooms with zero consumer changes.

@export var room_size: Vector2 = Vector2(1200, 680)
@export var spawn_rect_min: Vector2 = Vector2(80, 80)
@export var spawn_rect_max: Vector2 = Vector2(1120, 600)
@export var min_spawn_dist_from_hero: float = 160.0
@export var hero_start: Vector2 = Vector2(600, 340)
@export var exit_point: Vector2 = Vector2(600, 130)
@export var crate_positions: Array[Vector2] = []
@export var weapon_pickups: Array[Vector2] = []
