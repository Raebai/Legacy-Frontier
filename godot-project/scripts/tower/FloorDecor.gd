class_name FloorDecor
extends Node2D
## THE TOWER'S BACK WALL. Maker: *"make the map just feel cooler, more like detail and
## stuff generally"*, alongside *"make the map larger and more interactive"*.
##
## ⚠ WHY THE ROOM HAD NO DETAIL AND COULD NOT EASILY GET ANY. The tower floor is three
## flat things: an opaque `Floor` ColorRect (the wash), `RoomShell`'s air rect + ground
## + lit cap, and the ledges. Between the wash and the ledges there was NOTHING — a
## fighter stood in front of a single flat colour that changed hue once per floor. Ten
## authored biomes were carrying the whole visual identity of the climb as ten tints.
##
## This is the layer that gives each of those ten a SHAPE. It is one `_draw` on one
## Node2D, and everything it paints is a flat polygon, line or rect — no particles, no
## per-instance nodes, no textures, nothing that allocates. It repaints exactly once per
## floor (`build` -> `queue_redraw`), so its ongoing cost after a floor loads is a single
## cached canvas item that the renderer replays.
##
## ── THE THREE RULES IT OBEYS ─────────────────────────────────────────────────
##   1. LOW CONTRAST, ALWAYS. `StageLayers`' visual grammar is explicit: the ONE bright
##      warm horizontal line on the stage means "you can stand on this", and nothing
##      else may compete for the eye at fighter size. Every colour below is derived from
##      the floor's own wash by small lifts and darkenings; the accent is used sparingly
##      and never at full strength. If you can read this layer while fighting, it is
##      wrong.
##   2. NOTHING IN THE PLAY SPACE READS AS SOLID. This layer has no colliders and never
##      will. So it must not paint anything that looks like a ledge — no bright warm
##      horizontal caps, no slab shapes at ledge height in the middle of the room. Ribs
##      are VERTICAL, hangers come off the CEILING, and biome bands are full-width so
##      they read as wall rather than as furniture.
##   3. DETERMINISTIC. Hashed pseudo-noise, never an RNG, for the same reason
##      `ArenaTerrain` uses one: a `_draw` that rolls dice shimmers between frames, and
##      in co-op two phones would paint different rooms.
##
## ⚠ IT PARKS ITSELF UNCONDITIONALLY IN `_ready`, and that is not belt-and-braces — it
## is the whole lesson of `Atmosphere`'s "weird blinds": a CanvasItem draws on entering
## the tree whether or not anyone called `build()`, and a drawer that only sets its
## z-index inside `build()` will paint one frame at z 0, on the fighters' own rung.
## `_draw` is ALSO gated on having been built, for the same reason and independently.
##
## ⚠ IT IS NOT IN `StageLayers.DRAWERS`, AND IT CANNOT BE. That registry is keyed by
## script BASENAME and `slice_test_stage_layers` resolves every key to
## `res://scripts/combat/<name>.gd`; this file lives under `scripts/tower/`, so
## registering it would fail the suite on a load error. The scanner that catches
## unregistered drawers only matches `extends StaticBody2D` and would never have seen
## this anyway. The two independent guards above are what stand in for the registry.

## The room's standable floor. `Arena.WALL_THICKNESS` is 16 and the bottom wall is
## CENTRED on y = room_h, so the ground is half a thickness above it. Mirrors
## `FloorGen.WALL_THICKNESS` / `RoomShell.WALL`; hardcoded for the same reason they are.
const WALL: float = 16.0

## How far the wall is lifted off the room wash. Deliberately tiny: this is the
## difference between "there is a wall back there" and "there is a second bright
## rectangle competing with the fight".
const WALL_LIFT: float = 0.05
## The skirting where the wall meets the floor — a value break, NOT a lit cap. A warm
## bright horizontal here would be a lie under rule 1 of the stage legend.
const SKIRT_H: float = 7.0
const SKIRT_DARKEN: float = 0.30

## Structural ribs up the wall. Count is derived from the room width so a wider room
## gets MORE wall rather than the same wall stretched.
const RIB_SPACING: float = 168.0
const RIB_W: float = 26.0
const RIB_LIFT: float = 0.09
## ...and the shadow down one side of each rib, which is the only reason a flat
## rectangle reads as relief at all.
const RIB_SHADE: float = 0.22

## The motif's strength against the wall. Everything biome-specific is multiplied
## through this before it is drawn.
const MOTIF_ALPHA: float = 0.30
## ...and the one thing per biome that is allowed to be a LIGHT (a furnace mouth, a
## sconce, a star). Still under half, because the fighters and their spells own light.
const GLOW_ALPHA: float = 0.42

## Mobile trim. Ribs and speckle are the two counts that scale with room width, so they
## are the two that get cut; the wall, the skirt and the biome band are structural and
## stay, because a floor with no wall at all is a different floor, not a cheaper one.
const LOW_RIB_SPACING: float = 300.0
const LOW_SPECK_DIV: int = 3

var room_size: Vector2 = Vector2(1160.0, 560.0)
var tint: Color = Color(0.20, 0.18, 0.19)
var accent: Color = Color(0.85, 0.55, 0.35)
var biome: String = ""
## Has anyone actually asked for a back wall? See the ⚠ block above — a bare
## `FloorDecor.new()` must paint nothing.
var _built: bool = false


func _ready() -> void:
	StageLayers.apply(self, StageLayers.DECOR)   # the one z table; see StageLayers


## Re-draw the wall for a floor. Safe to call repeatedly on the same node — the tower
## rebuilds every floor through this, exactly as `RoomShell.build` is rebuilt.
func build(size: Vector2, room_tint: Color, room_accent: Color, biome_name: String) -> void:
	room_size = size
	if room_tint.a > 0.0:
		tint = room_tint
	if room_accent.a > 0.0:
		accent = room_accent
	biome = biome_name
	_built = true
	StageLayers.apply(self, StageLayers.DECOR)
	queue_redraw()


# ------------------------------------------------------------------ the drawing
func _draw() -> void:
	if not _built:
		return
	var w: float = room_size.x
	var ground_y: float = room_size.y - WALL * 0.5
	var low: bool = TuningConfig.quality_is_low()

	# --- the wall itself. One rect, a hair off the wash, so the room has a BACK.
	var wall_col: Color = tint.lightened(WALL_LIFT)
	draw_rect(Rect2(0.0, 0.0, w, ground_y), wall_col, true)

	# --- structural ribs. Vertical on purpose (rule 2): a horizontal band at ledge
	# height reads as somewhere to stand, and there is nothing to stand on back here.
	var spacing: float = LOW_RIB_SPACING if low else RIB_SPACING
	var ribs: int = maxi(2, int(w / spacing))
	var rib_col: Color = tint.lightened(RIB_LIFT)
	var rib_shade: Color = tint.darkened(RIB_SHADE)
	for i: int in ribs:
		var rx: float = w * (float(i) + 0.5) / float(ribs) - RIB_W * 0.5
		draw_rect(Rect2(rx, 0.0, RIB_W, ground_y), rib_col, true)
		draw_rect(Rect2(rx + RIB_W - 3.0, 0.0, 3.0, ground_y), rib_shade, true)

	# --- the biome. The whole point of the file.
	_draw_motif(w, ground_y, low)

	# --- the skirting, LAST so it sits over the ribs and the motif and reads as the
	# wall meeting the floor rather than as a stripe painted on it.
	draw_rect(Rect2(0.0, ground_y - SKIRT_H, w, SKIRT_H), tint.darkened(SKIRT_DARKEN), true)


## Cheap deterministic pseudo-noise in [0,1) from two ints. Lifted from
## `ArenaTerrain._h` verbatim so the two stage drawers jitter identically — a second
## hash would be a second thing to get subtly wrong.
func _h(a: int, b: int) -> float:
	var n: int = (a * 73856093) ^ (b * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65536.0


## The motif colour: the floor's accent, pushed toward the wall and kept faint.
func _ink(strength: float = 1.0) -> Color:
	return Color(accent.r, accent.g, accent.b, MOTIF_ALPHA * strength)


func _shade(strength: float = 1.0) -> Color:
	return Color(tint.r * 0.45, tint.g * 0.45, tint.b * 0.5, MOTIF_ALPHA * 1.4 * strength)


# ------------------------------------------------------------------- the biomes
## ⚠ MATCHED ON THE BIOME'S NAME, which is the only per-floor identity that reaches
## this layer (`EnvTheme.name`, straight out of `GameState.BIOMES`). A floor whose name
## is not in the table gets the generic arcade — which is what every hand-written
## `EnvTheme` and every `FloorGen._jitter_theme` copy produces, so the fallback is the
## COMMON case for the versus stage and the sandbox and has to look finished, not
## like a missing asset.
func _draw_motif(w: float, ground_y: float, low: bool) -> void:
	match biome:
		"Ashfall Verge":     _motif_ashfall(w, ground_y, low)
		"Verdant Tier":      _motif_verdant(w, ground_y, low)
		"Frostmarch":        _motif_frost(w, ground_y, low)
		"The Crimson Room":  _motif_crimson(w, ground_y)
		"The Sunken Vault":  _motif_vault(w, ground_y)
		"The Emberworks":    _motif_ember(w, ground_y)
		"Glasswood":         _motif_glasswood(w, ground_y, low)
		"The Drowned Gallery": _motif_drowned(w, ground_y, low)
		"Stormreach":        _motif_storm(w, ground_y, low)
		"The Apex":          _motif_apex(w, ground_y, low)
		_:                   _motif_arcade(w, ground_y)


## A row of arches along the wall. The shared skeleton behind half the biomes below —
## drawn as a trapezoid rather than a real curve because at fighter size the difference
## is invisible and a polygon is one command where an arc is a tessellation.
func _arcade(w: float, ground_y: float, count: int, top: float, col: Color) -> void:
	var pitch: float = w / float(maxi(count, 1))
	var half: float = pitch * 0.30
	for i: int in count:
		var cx: float = pitch * (float(i) + 0.5)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - half, ground_y),
			Vector2(cx - half, top + half * 0.55),
			Vector2(cx - half * 0.45, top),
			Vector2(cx + half * 0.45, top),
			Vector2(cx + half, top + half * 0.55),
			Vector2(cx + half, ground_y),
		]), col)


## Things hanging off the ceiling: `count` tapered spikes of varying length. Icicles,
## roots, banners and stalactites are all this function with different numbers.
func _hangers(w: float, count: int, max_len: float, half_w: float, col: Color, salt: int) -> void:
	for i: int in count:
		var hx: float = w * (float(i) + 0.5) / float(maxi(count, 1))
		hx += (_h(i, salt) - 0.5) * w / float(maxi(count, 1)) * 0.6
		var len_h: float = max_len * (0.35 + 0.65 * _h(i, salt + 7))
		draw_colored_polygon(PackedVector2Array([
			Vector2(hx - half_w, 0.0),
			Vector2(hx + half_w, 0.0),
			Vector2(hx, len_h),
		]), col)


## Scattered dots across the wall — ash, bubbles, stars, sparks.
func _specks(w: float, ground_y: float, count: int, radius: float, col: Color, salt: int) -> void:
	for i: int in count:
		var sx: float = w * _h(i, salt)
		var sy: float = ground_y * _h(i, salt + 3)
		draw_circle(Vector2(sx, sy), radius * (0.6 + 0.8 * _h(i, salt + 5)), col, true, -1.0, false)


# -- 1. Ashfall Verge — a burnt-out gantry, sagging, with ash in the air.
func _motif_ashfall(w: float, ground_y: float, low: bool) -> void:
	var beam: Color = _shade()
	var y: float = ground_y * 0.34
	# A broken gantry: four runs of beam with gaps blown through it.
	for i: int in 5:
		if _h(i, 21) < 0.28:
			continue      # the gap. A continuous beam would read as a ledge (rule 2).
		var x0: float = w * float(i) / 5.0 + 6.0
		var sag: float = 9.0 * _h(i, 31)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0, y), Vector2(x0 + w / 5.0 - 12.0, y + sag),
			Vector2(x0 + w / 5.0 - 12.0, y + sag + 9.0), Vector2(x0, y + 9.0),
		]), beam)
	_specks(w, ground_y, 26 if not low else 26 / LOW_SPECK_DIV, 2.2, _ink(0.8), 61)


# -- 2. Verdant Tier — overgrowth. Roots down the wall, a canopy over the top.
func _motif_verdant(w: float, ground_y: float, low: bool) -> void:
	draw_rect(Rect2(0.0, 0.0, w, ground_y * 0.13), _shade(1.2), true)   # the canopy
	_hangers(w, 5 if low else 9, ground_y * 0.46, 7.0, _shade(0.9), 11)
	# Leaf clusters where the roots leave the canopy — the accent, faint.
	for i: int in (4 if low else 8):
		var lx: float = w * (float(i) + 0.5) / (4.0 if low else 8.0)
		draw_circle(Vector2(lx, ground_y * (0.16 + 0.12 * _h(i, 5))),
			10.0 + 6.0 * _h(i, 9), _ink(0.7), true, -1.0, false)


# -- 3. Frostmarch — a frozen wall: icicles off the ceiling, a rime line low down.
func _motif_frost(w: float, ground_y: float, low: bool) -> void:
	_hangers(w, 8 if low else 16, ground_y * 0.30, 6.0, _ink(0.85), 3)
	# Rime: a pale band creeping UP from the floor, uneven along its top edge.
	var steps: int = 10 if low else 20
	for i: int in steps:
		var bx: float = w * float(i) / float(steps)
		var bh: float = ground_y * (0.05 + 0.05 * _h(i, 17))
		draw_rect(Rect2(bx, ground_y - SKIRT_H - bh, w / float(steps) + 1.0, bh),
			_ink(0.55), true)


# -- 4. The Crimson Room — hanging banners between the ribs. No noise at all: this
# room's whole character is that it is DELIBERATE, so its motif is the only one in the
# set that is perfectly regular.
func _motif_crimson(w: float, ground_y: float) -> void:
	for i: int in 6:
		var bx: float = w * (float(i) + 0.5) / 6.0
		var bw: float = w * 0.055
		var bh: float = ground_y * 0.52
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx - bw, 0.0), Vector2(bx + bw, 0.0),
			Vector2(bx + bw, bh), Vector2(bx, bh - bw * 0.9), Vector2(bx - bw, bh),
		]), _ink(1.15))
		# The sconce above it — the room's one light.
		draw_circle(Vector2(bx, ground_y * 0.20), 4.0,
			Color(accent.r, accent.g, accent.b, GLOW_ALPHA), true, -1.0, false)


# -- 5. The Sunken Vault — masonry: deep arched niches and a rivet line.
func _motif_vault(w: float, ground_y: float) -> void:
	_arcade(w, ground_y, 5, ground_y * 0.30, _shade(1.3))
	var ry: float = ground_y * 0.62
	var n: int = int(w / 46.0)
	for i: int in n:
		draw_circle(Vector2(w * (float(i) + 0.5) / float(n), ry), 2.6, _ink(0.7), true, -1.0, false)


# -- 6. The Emberworks — a foundry wall: pipes across it, furnace mouths glowing.
func _motif_ember(w: float, ground_y: float) -> void:
	# Two pipe runs. Thin, so they read as pipe and not as a walkway (rule 2).
	for k: int in 2:
		var py: float = ground_y * (0.22 + 0.30 * float(k))
		draw_rect(Rect2(0.0, py, w, 5.0), _shade(1.2), true)
	for i: int in 4:
		var fx: float = w * (float(i) + 0.5) / 4.0
		var fy: float = ground_y * 0.74
		draw_rect(Rect2(fx - 20.0, fy - 24.0, 40.0, 24.0), _shade(1.5), true)
		draw_rect(Rect2(fx - 14.0, fy - 18.0, 28.0, 18.0),
			Color(accent.r, accent.g, accent.b, GLOW_ALPHA), true)


# -- 7. Glasswood — tall thin panes, leaning slightly, like a petrified forest.
func _motif_glasswood(w: float, ground_y: float, low: bool) -> void:
	var n: int = 7 if low else 13
	for i: int in n:
		var gx: float = w * (float(i) + 0.5) / float(n)
		var lean: float = (_h(i, 13) - 0.5) * 26.0
		var top: float = ground_y * (0.06 + 0.22 * _h(i, 19))
		var half: float = 5.0 + 5.0 * _h(i, 23)
		draw_colored_polygon(PackedVector2Array([
			Vector2(gx - half + lean, top), Vector2(gx + half + lean, top),
			Vector2(gx + half, ground_y), Vector2(gx - half, ground_y),
		]), _ink(0.9))


# -- 8. The Drowned Gallery — a waterline. Everything below it is lighter and calmer,
# which is the one motif in the set that changes the whole lower half of the wall.
func _motif_drowned(w: float, ground_y: float, low: bool) -> void:
	_arcade(w, ground_y, 4, ground_y * 0.34, _shade(1.2))
	var line: float = ground_y * 0.58
	draw_rect(Rect2(0.0, line, w, ground_y - line), _ink(0.65), true)
	draw_rect(Rect2(0.0, line - 2.0, w, 3.0),
		Color(accent.r, accent.g, accent.b, GLOW_ALPHA * 0.7), true)
	# Bubbles, only under the line.
	for i: int in (6 if low else 16):
		draw_circle(Vector2(w * _h(i, 43), line + (ground_y - line) * _h(i, 47)),
			1.8 + 2.6 * _h(i, 53), _ink(0.8), false, 1.0, false)


# -- 9. Stormreach — masts and a cloud bank. The only biome whose motif reaches the
# TOP of the room, which is what makes it read as open sky rather than as a chamber.
func _motif_storm(w: float, ground_y: float, low: bool) -> void:
	draw_rect(Rect2(0.0, 0.0, w, ground_y * 0.20), _shade(1.1), true)
	for i: int in (3 if low else 6):
		var mx: float = w * (float(i) + 0.5) / (3.0 if low else 6.0)
		draw_rect(Rect2(mx - 3.0, ground_y * 0.10, 6.0, ground_y * 0.72), _shade(1.3), true)
		draw_circle(Vector2(mx, ground_y * 0.10), 5.0,
			Color(accent.r, accent.g, accent.b, GLOW_ALPHA), true, -1.0, false)


# -- 10. The Apex — nothing but sky and stars. The climb's last room is the one with
# the LEAST wall, and that is the whole statement.
func _motif_apex(w: float, ground_y: float, low: bool) -> void:
	_specks(w, ground_y * 0.86, 22 if not low else 22 / LOW_SPECK_DIV, 2.0,
		Color(accent.r, accent.g, accent.b, GLOW_ALPHA * 0.8), 71)
	# A horizon glow along the floor line — light coming from BELOW, which no other
	# floor in the tower does.
	draw_rect(Rect2(0.0, ground_y - SKIRT_H - 26.0, w, 26.0), _ink(0.75), true)


## THE FALLBACK, and it has to look finished — see the ⚠ on `_draw_motif`.
func _motif_arcade(w: float, ground_y: float) -> void:
	_arcade(w, ground_y, 5, ground_y * 0.32, _shade())
