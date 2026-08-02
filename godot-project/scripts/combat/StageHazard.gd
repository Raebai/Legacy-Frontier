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
	# ⚠ THIS DREW AT z 0 — AMONG THE FIGHTERS. A blast zone on the versus stage is
	# 360x1800 px of near-black, so on any stage where a pit sits inside the play
	# area it painted over everything at the fighters' own layer. A pit is a hole IN
	# the ground, so it belongs one rung under the ledges. See StageLayers.
	StageLayers.apply(self, StageLayers.HAZARD)
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


## RULE 3 OF THE STAGE LEGEND (see StageLayers): near-black inside a hard red LIP,
## and nothing else on the stage is allowed to look like this. The lip is drawn
## thickest along the TOP edge, because that is the line the player crosses — a pit
## announces itself at the moment you are deciding whether to jump, not once you are
## already inside it.
func _draw_pit(r: Rect2) -> void:
	draw_rect(r, StageLayers.VOID, true)
	var inset: float = minf(zone_size.x, zone_size.y) * 0.14
	var core: Rect2 = r.grow(-inset * 2.2)
	if core.size.x > 0.0 and core.size.y > 0.0:
		draw_rect(core, Color(0.0, 0.0, 0.0, 1.0), true)
	# Warning hatch along the lip, then the lip itself.
	var lip: float = maxf(3.0, minf(zone_size.x, zone_size.y) * 0.05)
	var step: float = maxf(8.0, lip * 2.4)
	var x: float = r.position.x
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y + lip), Vector2(minf(x + lip, r.end.x), r.position.y),
			Color(StageLayers.KILL_RED.r, StageLayers.KILL_RED.g, StageLayers.KILL_RED.b, 0.55),
			1.5, true)
		x += step
	draw_rect(Rect2(r.position, Vector2(r.size.x, lip)),
		Color(StageLayers.KILL_RED.r, StageLayers.KILL_RED.g, StageLayers.KILL_RED.b, 0.9), true)
	draw_rect(r, Color(StageLayers.KILL_RED.r, StageLayers.KILL_RED.g,
		StageLayers.KILL_RED.b, 0.75), false, 1.5)


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
