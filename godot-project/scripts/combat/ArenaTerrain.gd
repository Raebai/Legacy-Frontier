class_name ArenaTerrain
extends Node2D
## Draw-only realistic layered terrain for the versus stage. Replaces the old
## "flat dark slabs with a neon-green rim" look (maker: "the map needs to look way
## better, more REALISTIC and actually FUN"). Given a list of solid TERRACES (the
## StaticBody colliders VersusArena builds), this renders ONE cohesive rock/earth
## landmass: each terrace becomes a rock shelf dropping to the stage floor, drawn
## in stacked strata (sunlit earthy crust -> mid rock -> deep rock) with horizontal
## bedding lines, vertical cracks, embedded boulders, scattered pebbles and sparse
## moss tufts on the lit edge. Overlapping shelves at stepped heights compose into
## a connected ridge with rubble at the risers — a believable place, not abstract
## floating blocks. Deterministic jitter (hashed, no RNG) so it stays stable.
##
## Terrace shape: { "surface_y": float, "x0": float, "x1": float }. Order the list
## back-to-front (lowest/rear shelves first) so nearer/higher rock overdraws it.

## Palette — warm earthy rock, sun from the upper-left. Deliberately NOT slate +
## neon green: a lit ochre crust, muted moss (an accent, never a full rim), and
## cool deep rock for depth.
## RULE 1 of the stage legend (see StageLayers): the ground's lit ridge is the SAME
## light as a ruin ledge's cap and a cover block's top, so "you can stand on this"
## is one signal across the whole stage instead of three near-misses.
const CRUST_TOP: Color = StageLayers.CAP_LIT          # sunlit earth ridge line
const CRUST_CORE: Color = StageLayers.CAP_CORE        # the shaded half of the cap
const CRUST_BODY: Color = Color(0.45, 0.38, 0.27)     # top soil band
const ROCK_UPPER: Color = Color(0.37, 0.35, 0.36)     # exposed rock face
const ROCK_DEEP: Color = Color(0.22, 0.21, 0.25)      # deep shadowed rock
const STRATA_LINE: Color = Color(0.10, 0.09, 0.12, 0.55)
const CRACK_COLOR: Color = Color(0.08, 0.07, 0.10, 0.7)
const MOSS: Color = Color(0.33, 0.44, 0.24, 0.9)      # muted, sparse — an accent
const MOSS_DARK: Color = Color(0.24, 0.34, 0.18, 0.9)
const PEBBLE: Color = Color(0.44, 0.41, 0.38)
const BOULDER: Color = Color(0.25, 0.24, 0.27)
const BOULDER_LIT: Color = Color(0.34, 0.33, 0.34)

const CRUST_H: float = 12.0        # sunlit soil band thickness
const UPPER_H: float = 90.0        # exposed-rock band before it goes deep
const RIM_H: float = 4.0           # bright top edge line

var terraces: Array[Dictionary] = []
@export var floor_y: float = 1000.0  # how far down each shelf is drawn


func _ready() -> void:
	StageLayers.apply(self, StageLayers.TERRAIN)  # the one z table; see StageLayers
	queue_redraw()


## Cheap deterministic pseudo-noise in [0,1) from two ints — stable across runs
## (no RNG in _draw so the terrain never shimmers between frames).
func _h(a: int, b: int) -> float:
	var n: int = (a * 73856093) ^ (b * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65536.0


func _draw() -> void:
	for t: Dictionary in terraces:
		_draw_shelf(float(t["surface_y"]), float(t["x0"]), float(t["x1"]))


## One terrace rendered as a rock shelf from its surface down to floor_y.
func _draw_shelf(surface_y: float, x0: float, x1: float) -> void:
	var w: float = x1 - x0
	if w <= 0.0:
		return
	var seed_x: int = int(x0)
	# --- Deep rock body (fills the whole column) then the upper-rock band on top.
	draw_rect(Rect2(x0, surface_y, w, floor_y - surface_y), ROCK_DEEP, true)
	draw_rect(Rect2(x0, surface_y, w, UPPER_H), ROCK_UPPER, true)
	# --- Top soil crust with a jittered lower edge so soil meets rock organically.
	var step: float = 22.0
	var n: int = maxi(2, int(w / step))
	var crust_top := PackedVector2Array()
	var crust_bot := PackedVector2Array()
	for i in range(n + 1):
		var fx: float = x0 + w * float(i) / float(n)
		var wob: float = (_h(seed_x + i, 7) - 0.5) * 6.0
		crust_top.append(Vector2(fx, surface_y + wob * 0.4))
		crust_bot.append(Vector2(fx, surface_y + CRUST_H + wob))
	var soil := PackedVector2Array()
	for p: Vector2 in crust_top:
		soil.append(p)
	for j in range(crust_bot.size() - 1, -1, -1):
		soil.append(crust_bot[j])
	draw_colored_polygon(soil, CRUST_BODY)
	# --- Horizontal strata / bedding lines across the exposed rock.
	for s in range(1, 5):
		var sy: float = surface_y + CRUST_H + float(s) * 17.0 + (_h(seed_x, s) - 0.5) * 5.0
		if sy > surface_y + UPPER_H + 40.0:
			break
		var poly := PackedVector2Array()
		var m: int = maxi(2, int(w / 40.0))
		for i in range(m + 1):
			var fx2: float = x0 + w * float(i) / float(m)
			poly.append(Vector2(fx2, sy + (_h(seed_x + i, s * 3) - 0.5) * 4.0))
		draw_polyline(poly, STRATA_LINE, 1.5, true)
	# --- Vertical cracks fracturing down from the surface.
	var cracks: int = maxi(1, int(w / 130.0))
	for c in range(cracks):
		var cx: float = x0 + w * (_h(seed_x, c * 5 + 1))
		var cy: float = surface_y + CRUST_H
		var pts := PackedVector2Array([Vector2(cx, cy)])
		var len_c: float = 26.0 + _h(seed_x + c, 11) * 46.0
		var seg: int = 4
		for k in range(1, seg + 1):
			var ky: float = cy + len_c * float(k) / float(seg)
			var kx: float = cx + (_h(seed_x + c, k * 7) - 0.5) * 14.0
			pts.append(Vector2(kx, ky))
		draw_polyline(pts, CRACK_COLOR, 1.6, true)
	# --- Embedded boulders in the deep rock (lit-from-above ellipse pairs).
	var rocks: int = maxi(1, int(w / 150.0))
	for r in range(rocks):
		var rx: float = x0 + w * (0.15 + 0.7 * _h(seed_x + r, 23))
		var ry: float = surface_y + 40.0 + _h(seed_x, r * 9 + 3) * (UPPER_H - 10.0)
		var rr: float = 7.0 + _h(seed_x + r, 31) * 9.0
		_draw_boulder(Vector2(rx, ry), rr)
	# --- RULE 1: the lit cap along the walkable ridge — shaded band, then the lit
	# line — plus sparse moss + pebbles on it.
	draw_rect(Rect2(x0, surface_y - RIM_H, w, RIM_H + 2.0), CRUST_CORE, true)
	draw_rect(Rect2(x0, surface_y - RIM_H, w, RIM_H * 0.5), CRUST_TOP, true)
	var tufts: int = maxi(1, int(w / 90.0))
	for tf in range(tufts):
		var tx: float = x0 + 12.0 + (w - 24.0) * _h(seed_x + tf, 41)
		if _h(seed_x, tf * 13) > 0.55:  # only ~45% of slots get moss — sparse
			_draw_moss(Vector2(tx, surface_y - RIM_H))
		if _h(seed_x, tf * 17 + 2) > 0.5:
			var pr: float = 1.4 + _h(seed_x + tf, 3) * 1.8
			draw_circle(Vector2(tx + 6.0, surface_y - RIM_H - pr * 0.4), pr, PEBBLE, true, -1.0, true)


func _draw_boulder(c: Vector2, r: float) -> void:
	draw_circle(c, r, BOULDER, true, -1.0, true)
	draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.6, BOULDER_LIT, true, -1.0, true)
	draw_arc(c, r, 0.0, TAU, 20, Color(0.10, 0.09, 0.11, 0.6), 1.0, true)


## A small clump of moss blades on the lit edge — three short strokes, muted.
func _draw_moss(base: Vector2) -> void:
	for b in range(3):
		var off: float = (float(b) - 1.0) * 3.2
		var col: Color = MOSS if b != 1 else MOSS_DARK
		draw_line(base + Vector2(off, 1.0), base + Vector2(off * 1.3, -4.5 - float(b % 2)), col, 1.6, true)
