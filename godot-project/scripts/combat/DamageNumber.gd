class_name DamageNumber
extends Node2D
## A pooled floating combat number: pops at the hit, drifts up + arcs slightly,
## then fades. Spawned on EVERY hit AND every DoT tick so damage always READS
## (maker: "show the dot damage on the enemy" + damage numbers). Drawn with the
## fallback font — zero asset dependency; draw-time only, so headless-safe. Big
## hits scale up + punch brighter (the crit read). A global cap keeps DoT spam
## from flooding the screen (the "pool").

const RISE_SPEED: float = 52.0
const LIFETIME: float = 0.72
const GRAVITY: float = 46.0     # slight downward pull so the number arcs
const MAX_ALIVE: int = 64       # global cap (the pool ceiling)
const BIG_HIT: int = 20         # >= this reads as a heavy hit -> bigger + longer
const BASE_SIZE: int = 15
const BIG_SIZE: int = 26

var _text: String = ""
var _color: Color = Color(1.0, 1.0, 1.0)
var _age: float = 0.0
var _life: float = LIFETIME
var _vel: Vector2 = Vector2.ZERO
var _size: int = BASE_SIZE
var _pop: float = 1.2  # eases to 1.0 — a quick scale-in punch


## Spawn a floating "-N" over `world_pos` under `parent` (the arena node). `color`
## tints it (element hue for DoT ticks, near-white for physical); `crit` forces
## the big treatment. No-op past the global cap so ticks can't flood the screen.
static func spawn(parent: Node, world_pos: Vector2, amount: int, color: Color = Color(1, 1, 1), crit: bool = false) -> void:
	if parent == null or not parent.is_inside_tree() or amount <= 0:
		return
	var tree: SceneTree = parent.get_tree()
	if tree != null and tree.get_nodes_in_group("damage_number").size() >= MAX_ALIVE:
		return
	var dn := DamageNumber.new()
	dn.add_to_group("damage_number")
	dn._text = "-" + str(absi(amount))
	dn._color = color
	var big: bool = crit or amount >= BIG_HIT
	dn._size = BIG_SIZE if big else BASE_SIZE
	dn._life = LIFETIME * (1.2 if big else 1.0)
	dn._pop = 1.5 if big else 1.2
	# A deterministic sideways drift from the spawn position (no RNG needed) so a
	# cluster of ticks fans out instead of stacking into an unreadable pile.
	var jitter: float = sin(world_pos.x * 0.7 + world_pos.y * 1.3)
	dn._vel = Vector2(jitter * 22.0, -RISE_SPEED)
	parent.add_child(dn)
	dn.global_position = world_pos + Vector2(0.0, -6.0)
	dn.z_index = 60  # above fighters + most VFX


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	global_position += _vel * delta
	_vel.y += GRAVITY * delta
	_pop = move_toward(_pop, 1.0, delta * 5.0)
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var frac: float = _age / _life
	var alpha: float = 1.0 - smoothstep(0.5, 1.0, frac)  # hold, then fade out
	var fs: int = int(round(float(_size) * _pop))
	var col: Color = Color(_color.r, _color.g, _color.b, alpha)
	var outline: Color = Color(0.05, 0.04, 0.07, alpha * 0.95)
	# Center the text horizontally on the origin.
	var w: float = font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos: Vector2 = Vector2(-w * 0.5, 0.0)
	draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, fs / 4), outline)
	draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
