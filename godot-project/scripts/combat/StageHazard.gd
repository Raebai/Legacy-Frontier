class_name StageHazard
extends Area2D
## Versus-arena stage hazard: PIT (fall in -> ring-out, lose a stock) or SLOPE
## (slides fighters toward the edge). Self-builds its CollisionShape2D in
## _ready and POLLS get_overlapping_bodies each physics frame (ExitPortal
## idiom) — no reliance on enter/exit edge signals. Fighter identity comes
## from groups ("hero" / "enemy"), NOT collision layers: the mask scans ALL
## layers and code filters, so layer reshuffles can't silently break hazards.
## Primitive-drawn placeholder visual; real art later.

## A PIT reports a fighter falling in. The stocks/respawn manager consumes
## this — the hazard itself never damages, despawns, or respawns anyone.
signal fighter_fell(body)

enum Mode { PIT, SLOPE }

@export var mode: Mode = Mode.PIT
@export var zone_size: Vector2 = Vector2(96, 96)
## SLOPE only: direction fighters get pushed (normalized at use).
@export var slide_dir: Vector2 = Vector2.DOWN
## SLOPE only: slide speed in px/s.
@export var slide_strength: float = 140.0

## PIT dedup: instance_id -> true for fighters already reported while they
## remain overlapping. Pruned when a body stops overlapping, so a respawned
## fighter walking back in falls (and reports) again.
var _reported: Dictionary = {}


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = zone_size
	cs.shape = rect
	add_child(cs)
	monitoring = true
	# Scan every layer; _is_fighter does the real filtering in code.
	collision_mask = 0xFFFFFFFF
	add_to_group("stage_hazard")


func _physics_process(delta: float) -> void:
	var bodies: Array = get_overlapping_bodies()
	match mode:
		Mode.PIT:
			report_fallers(bodies)
		Mode.SLOPE:
			slide_bodies(bodies, delta)


## A "fighter" is anything ring-out-able: the hero or any enemy.
func _is_fighter(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	return body.is_in_group("hero") or body.is_in_group("enemy")


## PIT core, directly callable so headless tests can drive it without real
## physics overlap. Emits `fighter_fell` once per NEW fighter in `bodies`,
## prunes dedup entries for bodies no longer present (respawn re-entry works),
## and returns how many fighters it emitted for this call.
func report_fallers(bodies: Array) -> int:
	var present: Dictionary = {}
	for body in bodies:
		if body != null and is_instance_valid(body):
			present[body.get_instance_id()] = true
	for id in _reported.keys():
		if not present.has(id):
			_reported.erase(id)
	var emitted: int = 0
	for body in bodies:
		if not _is_fighter(body):
			continue
		var id: int = body.get_instance_id()
		if _reported.has(id):
			continue
		_reported[id] = true
		fighter_fell.emit(body)
		emitted += 1
	return emitted


## SLOPE core, directly callable for the same headless-test reason: nudges
## every fighter body in `bodies` along slide_dir by slide_strength px/s.
func slide_bodies(bodies: Array, delta: float) -> void:
	if slide_dir.length_squared() <= 0.000001:
		return   # zero direction: a slope that pushes nowhere is a no-op, not a NaN
	var dir: Vector2 = slide_dir.normalized()
	for body in bodies:
		if _is_fighter(body) and body is Node2D:
			(body as Node2D).global_position += dir * slide_strength * delta


func _draw() -> void:
	var r := Rect2(-zone_size * 0.5, zone_size)
	if mode == Mode.PIT:
		_draw_pit(r)
	else:
		_draw_slope(r)


## Dark void with nested-inset "falloff" and a thin danger border.
func _draw_pit(r: Rect2) -> void:
	draw_rect(r, Color(0.05, 0.03, 0.08, 0.8), true)
	var inset: float = minf(zone_size.x, zone_size.y) * 0.14
	var inner: Rect2 = r.grow(-inset)
	if inner.size.x > 0.0 and inner.size.y > 0.0:
		draw_rect(inner, Color(0.02, 0.01, 0.04, 0.9), true)
	var core: Rect2 = r.grow(-inset * 2.2)
	if core.size.x > 0.0 and core.size.y > 0.0:
		draw_rect(core, Color(0.0, 0.0, 0.0, 0.96), true)
	draw_rect(r, Color(0.85, 0.25, 0.2, 0.85), false, 1.5)


## Translucent direction-tinted panel with chevrons pointing along slide_dir.
func _draw_slope(r: Rect2) -> void:
	var dir: Vector2 = Vector2.DOWN
	if slide_dir.length_squared() > 0.000001:
		dir = slide_dir.normalized()
	# Direction-shifted tint so differently-aimed slopes read apart at a glance.
	var tint := Color(0.5 + 0.28 * dir.x, 0.5, 0.5 + 0.28 * dir.y, 0.22)
	draw_rect(r, tint, true)
	draw_rect(r, Color(tint.r, tint.g, tint.b, 0.7), false, 1.5)
	var perp := Vector2(-dir.y, dir.x)
	var half: float = minf(zone_size.x, zone_size.y) * 0.5
	var arm: float = half * 0.24
	var chevron_color := Color(0.95, 0.95, 0.85, 0.75)
	for i in range(3):
		# Three chevron tips staggered along the slide direction.
		var tip: Vector2 = dir * half * (-0.35 + 0.45 * float(i))
		var back: Vector2 = tip - dir * arm
		draw_line(back + perp * arm, tip, chevron_color, 2.0)
		draw_line(back - perp * arm, tip, chevron_color, 2.0)
