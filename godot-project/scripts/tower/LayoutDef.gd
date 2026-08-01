class_name LayoutDef
extends Resource
## The physical shape of a floor's room, as data. The one arena shell is
## parameterized by these (size, where enemies may spawn, where the exit and
## crates sit). Seam for later: an optional layout_scene: PackedScene can be
## added for bespoke hand-authored rooms with zero consumer changes.

## ONE SCREEN (1.3). The room is now sized so the WHOLE floor fits inside the
## fit-all camera at its widest: the base viewport is 640x360 and
## CombatCamera.FRAME_ZOOM_MIN is 0.5, so at most 1280x720 world units are
## visible, minus FRAME_PAD (300, 220) of breathing room => ~980x500. 960x480
## sits just inside that with a little slack, and Arena._apply_room_size builds
## the floor rect + all four walls from it.
@export var room_size: Vector2 = Vector2(960, 480)
@export var spawn_rect_min: Vector2 = Vector2(70, 70)
@export var spawn_rect_max: Vector2 = Vector2(890, 420)
@export var min_spawn_dist_from_hero: float = 160.0
@export var hero_start: Vector2 = Vector2(480, 300)
@export var exit_point: Vector2 = Vector2(480, 110)
@export var crate_positions: Array[Vector2] = []
@export var weapon_pickups: Array[Vector2] = []
## THE SKYLINE. Ledges the floor is drawn with, as
## `{"x", "y", "w", "h", "breakable"}` — x/y are the platform's CENTRE, so a ledge's
## standing surface is `y - h * 0.5`. `breakable` picks the amber-rimmed
## `BreakablePlatform` (shatters, then re-forms) over the permanent `RuinPlatform`.
##
## Dictionaries rather than a resource per ledge on purpose: this is generated data
## (see `FloorGen`), and a plain dict compares field-for-field in a determinism test
## with no instance identity in the way — the same reason enemy spawn data crosses
## the co-op wire as a dict.
##
## EMPTY on every hand-authored layout, which is why the tower has been a bare box:
## `RuinPlatform` / `BreakablePlatform` were built and wired only into VersusArena.
@export var platforms: Array[Dictionary] = []
