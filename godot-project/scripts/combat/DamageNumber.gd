class_name DamageNumber
extends Node2D
## A pooled floating combat number: pops at the hit, drifts up + arcs slightly,
## then fades. Spawned on EVERY hit AND every DoT tick so damage always READS
## (maker: "show the dot damage on the enemy" + damage numbers). Drawn with the
## fallback font — zero asset dependency; draw-time only, so headless-safe. Big
## hits scale up + punch brighter (the crit read). A global cap keeps DoT spam
## from flooding the screen.
##
## ⚠ THIS FILE USED TO SAY "pooled" AND NOT BE. Every `spawn()` did a fresh
## `DamageNumber.new()`, and the MAX_ALIVE cap was enforced by
## `get_tree().get_nodes_in_group("damage_number").size()` — an O(n) walk of the
## group that also ALLOCATES a fresh Array, run on every hit and every DoT tick.
## With a burning crowd that is the hottest path in the combat frame, and it was
## pure overhead: the answer it computed is a number the class can simply keep.
##
## The pool now really is one. Two static pieces do the work:
##
##   `_alive` — an integer, so the cap is an O(1) compare instead of a group walk.
##   `_pool`  — retired instances, kept parented and merely hidden rather than
##              detached, so they cannot become orphans that outlive their arena
##              (a detached free-list is the obvious implementation and it leaks
##              on scene change, which shows up as Godot's "N objects still in
##              use at exit" and, worse, as a pool full of nodes belonging to a
##              tower floor that no longer exists).
##
## The one thing a counter must get right that a group walk got right for free is
## staying accurate when nodes die WITHOUT being released — which is what happens
## every time a floor is torn down mid-fight. `_exit_tree` is the guard: if a
## still-active number leaves the tree, it decrements on the way out. Without it
## the counter ratchets up, hits MAX_ALIVE, and damage numbers silently stop
## appearing for the rest of the session.

const RISE_SPEED: float = 52.0
const LIFETIME: float = 0.72
const GRAVITY: float = 46.0     # slight downward pull so the number arcs
const MAX_ALIVE: int = 64       # global cap (the pool ceiling)
const BIG_HIT: int = 20         # >= this reads as a heavy hit -> bigger + longer
const BASE_SIZE: int = 15
const BIG_SIZE: int = 26

## Live count of numbers currently animating. The cap check, O(1).
static var _alive: int = 0
## Retired instances available for reuse. Still children of their arena, hidden
## and not processing. Never larger than MAX_ALIVE.
static var _pool: Array[DamageNumber] = []

var _text: String = ""
var _color: Color = Color(1.0, 1.0, 1.0)
var _age: float = 0.0
var _life: float = LIFETIME
var _vel: Vector2 = Vector2.ZERO
var _size: int = BASE_SIZE
var _pop: float = 1.2  # eases to 1.0 — a quick scale-in punch
## Animating right now (and therefore counted in `_alive`). The flag is what keeps
## `_release` and `_exit_tree` from both decrementing the same number.
var _active: bool = false


## Spawn a floating "-N" over `world_pos` under `parent` (the arena node). `color`
## tints it (element hue for DoT ticks, near-white for physical); `crit` forces
## the big treatment. No-op past the global cap so ticks can't flood the screen.
static func spawn(parent: Node, world_pos: Vector2, amount: int, color: Color = Color(1, 1, 1), crit: bool = false) -> void:
	if parent == null or not parent.is_inside_tree() or amount <= 0:
		return
	if _alive >= MAX_ALIVE:
		return
	var dn: DamageNumber = _take(parent)
	dn._text = "-" + str(absi(amount))
	dn._color = color
	var big: bool = crit or amount >= BIG_HIT
	dn._size = BIG_SIZE if big else BASE_SIZE
	dn._life = LIFETIME * (1.2 if big else 1.0)
	dn._pop = 1.5 if big else 1.2
	dn._age = 0.0
	# A deterministic sideways drift from the spawn position (no RNG needed) so a
	# cluster of ticks fans out instead of stacking into an unreadable pile.
	var jitter: float = sin(world_pos.x * 0.7 + world_pos.y * 1.3)
	dn._vel = Vector2(jitter * 22.0, -RISE_SPEED)
	dn.global_position = world_pos + Vector2(0.0, -6.0)
	dn.z_index = 60  # above fighters + most VFX
	dn._active = true
	_alive += 1
	dn.visible = true
	dn.set_process(true)
	dn.queue_redraw()


## A number ready to be configured: a retired one if the pool has a usable entry,
## otherwise a fresh node.
##
## "Usable" means still valid, still in the tree, and belonging to THIS parent.
## The parent check is the one that matters: a pooled number left over from the
## previous tower floor is attached to a node that is on its way out, and reusing
## it would draw the hit into a scene the camera is no longer looking at. Those
## are dropped (freed) rather than reparented — reparenting is the more clever
## answer and buys nothing, because there is only ever one arena and the pool
## self-purges within a single floor's worth of hits.
static func _take(parent: Node) -> DamageNumber:
	while not _pool.is_empty():
		var candidate: DamageNumber = _pool.pop_back()
		if not is_instance_valid(candidate):
			continue  # went down with its arena
		if candidate.is_inside_tree() and candidate.get_parent() == parent:
			return candidate
		candidate.queue_free()
	var dn := DamageNumber.new()
	dn.add_to_group("damage_number")
	dn.visible = false
	dn.set_process(false)
	parent.add_child(dn)
	return dn


## Retire an animating number: stop paying for it, and offer it back to the pool.
func _release() -> void:
	if not _active:
		return
	_active = false
	_alive -= 1
	visible = false
	set_process(false)
	if _pool.size() < MAX_ALIVE:
		_pool.append(self)
	else:
		queue_free()


## The counter's safety net — see the file header. An active number that leaves
## the tree (its arena was torn down mid-fight) must give its slot back, or the
## cap ratchets shut permanently.
func _exit_tree() -> void:
	if _active:
		_active = false
		_alive -= 1


## Test hook + arena teardown: forget the pool entirely. Mirrors
## ImpactFrame.reset_arbiter(). Not called in normal play.
static func reset_pool() -> void:
	for d: DamageNumber in _pool:
		if is_instance_valid(d):
			d.queue_free()
	_pool.clear()
	_alive = 0


## Diagnostics (the perf overlay reads this): how many numbers are animating.
static func alive_count() -> int:
	return _alive


## Diagnostics: how many retired instances are banked for reuse.
static func pooled_count() -> int:
	return _pool.size()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		_release()
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
