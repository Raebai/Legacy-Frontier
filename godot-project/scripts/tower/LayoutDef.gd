class_name LayoutDef
extends Resource
## The physical shape of a floor's room, as data. The one arena shell is
## parameterized by these (size, where enemies may spawn, where the exit and
## crates sit). Seam for later: an optional layout_scene: PackedScene can be
## added for bespoke hand-authored rooms with zero consumer changes.

## ONE SCREEN (1.3). The room is sized so the WHOLE floor fits inside the fit-all
## camera at its widest: the base viewport is 640x360 and
## `CombatCamera.FRAME_ZOOM_MIN` is 0.42, so at most 1523x857 world units are visible,
## minus FRAME_PAD (300, 220) of breathing room => ~1223x637. `Arena._apply_room_size`
## builds the floor rect + all four walls from this.
##
## ⚠ THIS IS THE FALLBACK ROOM, AND IT IS NOT DEAD DATA. Run floors are redrawn by
## `FloorGen`, but the F6 sandbox and the null-tower fallback both come straight
## through `GameState.default_layout()`, which is a bare `LayoutDef.new()` with crate
## positions bolted on. So when the arena grew (maker: "the map is too small"), this
## had to grow with it or the one place combat feel is actually JUDGED would have kept
## measuring the old small box. Sized between FloorGen's MIN_ROOM and MAX_ROOM so the
## sandbox is a representative floor rather than an outlier at either end.
@export var room_size: Vector2 = Vector2(1160, 560)
@export var spawn_rect_min: Vector2 = Vector2(70, 70)
## ⚠ DERIVED FROM `room_size`, NOT INVENTED. `FloorGen.generate_layout` computes this
## as `room_size - 70` on both axes; this default mirrors that arithmetic so a
## hand-authored layout and a generated one describe the same inset, and so a future
## room-size change has an obvious partner to update.
@export var spawn_rect_max: Vector2 = Vector2(1090, 490)
@export var min_spawn_dist_from_hero: float = 160.0
## Standing on the ground (room_size.y - 8 is the floor's top face), one third in from
## the left wall so the room opens out in front of you.
@export var hero_start: Vector2 = Vector2(390, 512)
@export var exit_point: Vector2 = Vector2(870, 512)
@export var crate_positions: Array[Vector2] = []
@export var weapon_pickups: Array[Vector2] = []
## HEALTH PACKS, in the same idiom as `weapon_pickups` above so a floor authors both
## the same way. EMPTY on every hand-authored layout today, which is why
## `FloorBuilder.DEFAULT_HEALTH_PACKS` exists: an empty array here means "this floor
## has not been given an opinion", not "this floor wants none", and the builder places
## a sensible pair rather than shipping a tower with no healing in it at all. A floor
## that authors even ONE position takes over completely.
##
## ⚠ THERE IS THEREFORE NO WAY TO SAY "THIS FLOOR HAS NO PACKS" FROM HERE — an empty
## array is already spoken for. That is a deliberate trade while every authoring table
## is silent; when the first floor genuinely wants none, the honest fix is a
## `health_packs_authored: bool` beside this, not a magic sentinel position.
@export var health_pickups: Array[Vector2] = []
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
