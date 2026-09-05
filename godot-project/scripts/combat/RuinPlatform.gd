class_name RuinPlatform
extends StaticBody2D
## A weathered broken-stone platform you can stand + jump on — the "ruins" that
## fill the vertical space over the ground so the stage reads as a real place with
## aerial routes, not scattered abstract slabs. Solid (layer 1). Drawn as a fitted
## masonry slab with a sunlit bevel, cracks + chipped corners, sparse moss, and a
## couple of support struts / hanging rubble BENEATH so it looks ROOTED to the
## world rather than floating (maker: "platforms that feel intentional + connected
## to the ground, not disconnected abstract blocks").

@export var platform_size: Vector2 = Vector2(190.0, 24.0)

## ══ IT TAKES HOLES NOW, AND IT STILL NEVER LEAVES ══════════════════════════
## Maker: *"please make the floating platforms destroyable into bits just like the floor
## was beforehand as well"*. "The floating platforms" is all of them, and the previous
## reading — only `BreakablePlatform` is destructible — leaves most of the tower out:
## `FloorGen` authors `"breakable"` explicitly as `rng.randf() < break_chance`, and that
## chance is **0.0 on floors 1-2** and caps at **0.5** thereafter. So at least half of
## every floor's ledges are this script, and the first two floors are ENTIRELY this
## script. Carving only the amber ones would have shipped a fix the maker could not see
## on the floors they start on.
##
## ⚠ SO IT CARVES, BUT IT DOES NOT BREAK, AND THAT IS THE LEGEND HOLDING RATHER THAN
## BENDING. `StageLayers` rule 2 is AMBER = IT BREAKS, and it stays literally true: an
## amber ledge can be removed from the world, a stone one cannot. What a stone one can
## now do is lose chunks and knit them back — the ledge is always there, so nothing
## `FloorGen` reasoned about when it placed a spawn or a pickup is ever absent, and this
## script keeps its whole point (the "escape hatch for a ledge some floor genuinely
## needs to keep", per `FloorBuilder.build_platforms`).
##
## ⚠ AND IT IS REACHED BY `BODY_META` ONLY — no group, of either kind.
##   * NOT `DestructibleStage.GROUP_NAME`: `stage_in` returns THE FIRST MEMBER, so
##     ledges in that group would steer every `carve_area` in the game onto one
##     arbitrary plank. See `DestructibleStage.advertise_in_group`.
##   * NOT `"destructible"` either, and this one is the sharper trap:
##     `SpellWorld.is_smashable` returns true for anything in it and
##     `smash_destructibles` DEFAULTS TO TRUE, so joining would make these ledges
##     invisible to `floor_below` / `floor_point` / `ground_path` — where `BoulderHurl`
##     rips its rock, where `FaultLine` reads terrain, where `GraveTide` walks, where
##     `AegisWard` plants and where every crater is snapped. `BreakablePlatform` is in
##     that group and always has been; this one has never been and must not start.
##
## The cost of that is honest and worth writing down: `carve_from_body` sites reach this
## ledge (`Spell`, `BeamSpell`, `BoulderHurl`, `DivineRay`, `EnergyNova`, `RiftDagger` —
## anything that stops ON it), and the eleven `carve_area` AoE sites do not, because
## those find their target by the group scan this ledge is correctly absent from.

## How long a hole stays open. Longer than a breakable ledge's default regen — this one
## never goes away, so the hole IS the whole event and needs to last long enough to
## change a fight. Refreshed by every fresh bite.
const REPAIR_TIME: float = 9.0
const REPAIR_POOF: Color = Color(0.80, 0.78, 0.70, 0.75)
const REPAIR_POOF_END: Color = Color(0.80, 0.78, 0.70, 0.0)

## PALETTE — RULE 1 OF THE STAGE LEGEND (see StageLayers). The lit cap is the whole
## point of this platform: it is the one thing that tells a player mid-jump that
## there is something here to land on. Everything below it is deliberately quiet.
##
## The previous pass had a 0.55-value "sunlit bevel" over a 0.41 body — a six-percent
## step, invisible against the tower's near-black wash at the framing zoom. The cap
## is now shared with the ground crust and the breakable ledge, so every standable
## surface in the game wears the same light.
const STONE: Color = Color(0.33, 0.31, 0.32)
const STONE_LIT: Color = StageLayers.CAP_LIT       # the lit top line
const STONE_CORE: Color = StageLayers.CAP_CORE     # the cap's shaded half
const STONE_DARK: Color = Color(0.18, 0.17, 0.19)
const EDGE: Color = StageLayers.EDGE_DARK
const CRACK: Color = Color(0.09, 0.08, 0.10, 0.7)
const MOSS: Color = Color(0.33, 0.44, 0.24, 0.85)
const STRUT: Color = Color(0.16, 0.15, 0.16)


var _grid: DestructibleStage = null
var _repair_timer: float = 0.0
## The grid's carve counter as of last frame. Polled rather than signalled: this script
## has no damage entry of its own (see the header — it is deliberately out of the
## `"destructible"` group), so the carve arrives INSIDE the grid via `carve_from_body`
## and the only honest way to notice is to watch the number it keeps.
var _seen_carves: int = 0
## Cached once — never per-draw or per-frame (mobile-first, 640x360 base).
var _low: bool = false


func _ready() -> void:
	StageLayers.apply(self, StageLayers.PLATFORM)
	_low = TuningConfig.quality_is_low()
	# ⚠ THE SINGLE `RectangleShape2D` IS GONE, replaced by the grid's merged rectangles
	# — which start out as exactly that one box over a whole slab and then lose pieces.
	# Collision stays on layer 1 (this body's default), unchanged.
	_grid = DestructibleStage.attach_ledge(self, platform_size, STONE)
	queue_redraw()


func _process(delta: float) -> void:
	if _grid == null or not is_instance_valid(_grid):
		return
	if _grid.carve_events != _seen_carves:
		_seen_carves = _grid.carve_events
		_repair_timer = REPAIR_TIME   # refreshed, not accumulated
		DebrisChunk.spawn_burst(get_parent(), global_position, STONE_LIT,
			1 if _low else 3, Vector2.UP, 140.0)
		queue_redraw()
	if _repair_timer <= 0.0:
		return
	_repair_timer -= delta
	if _repair_timer > 0.0:
		return
	# Knit the holes shut. Quiet: the ledge never left, so there is nothing to announce.
	_grid.build_from_rects([Rect2(-platform_size * 0.5, platform_size)] as Array[Rect2])
	_grid.rebuild_collision(self, self)
	_seen_carves = _grid.carve_events
	CombatVfx.spawn_burst(get_parent(), global_position, REPAIR_POOF, REPAIR_POOF_END,
		1 if _low else 8, 0.3, 40.0, 90.0, 1.0, 2.5)
	_grid.queue_redraw()
	queue_redraw()


func _h(a: int, b: int) -> float:
	var n: int = (a * 73856093) ^ (b * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65536.0


func _draw() -> void:
	var half: Vector2 = platform_size * 0.5
	var seed_x: int = int(position.x)
	var cap: float = StageLayers.cap_height(platform_size.y)
	# --- Support struts + hanging rubble beneath, so it reads rooted. Two tapered
	# stone legs dropping from the underside + a few clinging chunks. DARK and thin:
	# they are there to root the ledge, and anything below the cap that catches the
	# eye is competing with the cap for the one glance the player has mid-jump.
	for s in range(2):
		var sx: float = lerpf(-half.x * 0.55, half.x * 0.55, float(s))
		var drop: float = 26.0 + _h(seed_x, s * 3) * 20.0
		var leg := PackedVector2Array([
			Vector2(sx - 6.0, half.y - 2.0),
			Vector2(sx + 6.0, half.y - 2.0),
			Vector2(sx + 3.0, half.y + drop),
			Vector2(sx - 3.0, half.y + drop),
		])
		draw_colored_polygon(leg, STRUT)
	for r in range(3):
		var rx: float = lerpf(-half.x * 0.7, half.x * 0.7, _h(seed_x, r * 7 + 1))
		var rr: float = 3.0 + _h(seed_x + r, 5) * 4.0
		draw_circle(Vector2(rx, half.y + 4.0 + _h(seed_x, r * 5) * 10.0), rr, STONE_DARK, true, -1.0, true)
	# --- The slab body with a jittered (chipped) silhouette.
	var body := PackedVector2Array([
		Vector2(-half.x + _h(seed_x, 1) * 5.0, -half.y),
		Vector2(half.x - _h(seed_x, 2) * 5.0, -half.y + _h(seed_x, 8) * 3.0),
		Vector2(half.x, half.y - _h(seed_x, 3) * 4.0),
		Vector2(-half.x + _h(seed_x, 4) * 3.0, half.y),
	])
	draw_colored_polygon(body, STONE)
	# Deep underside shade — the dark half of the value step that makes the ledge
	# read as a lit horizontal SURFACE rather than as a floating rectangle.
	draw_rect(Rect2(-half.x, half.y - cap * 0.7, platform_size.x, cap * 0.7),
		StageLayers.UNDERSIDE, true)
	# --- RULE 1: the lit cap along the walkable surface. Two bands (shaded, then
	# lit) so the top edge has thickness at any zoom.
	draw_rect(Rect2(-half.x, -half.y, platform_size.x, cap), STONE_CORE, true)
	draw_rect(Rect2(-half.x, -half.y, platform_size.x, maxf(cap * 0.45, 1.5)), STONE_LIT, true)
	# --- Masonry seams (a few vertical joints) + a diagonal crack. BELOW the cap
	# only: a seam cutting the lit line would break the one unbroken horizontal.
	var joints: int = maxi(2, int(platform_size.x / 46.0))
	for j in range(1, joints):
		var jx: float = -half.x + platform_size.x * float(j) / float(joints) + (_h(seed_x, j) - 0.5) * 6.0
		draw_line(Vector2(jx, -half.y + cap + 1.0), Vector2(jx, half.y - 2.0), EDGE, 1.2, true)
	draw_line(Vector2(-half.x * 0.3, -half.y + cap + 1.0), Vector2(half.x * 0.15, half.y - 3.0), CRACK, 1.6, true)
	# --- Sparse moss clinging to the lit edge. Two tufts, not three, and short: it
	# is flavour on the cap, and the cap has a job.
	for m in range(2):
		if _h(seed_x, m * 11) > 0.55:
			var mx: float = lerpf(-half.x * 0.8, half.x * 0.8, _h(seed_x + m, 9))
			draw_line(Vector2(mx, -half.y), Vector2(mx + 1.0, -half.y - 3.5), MOSS, 1.6, true)
	# Crisp silhouette edge.
	var outline: PackedVector2Array = body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, EDGE, 1.4, true)
