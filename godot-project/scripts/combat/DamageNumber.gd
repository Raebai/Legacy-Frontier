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

const HudStyle := preload("res://scripts/ui/HudStyle.gd")

const RISE_SPEED: float = 52.0
const LIFETIME: float = 0.72
const GRAVITY: float = 46.0     # slight downward pull so the number arcs
const MAX_ALIVE: int = 64       # global cap (the pool ceiling)
const BIG_HIT: int = 20         # >= this reads as a heavy hit -> bigger + longer
## ⚠ THESE ARE WORLD UNITS ON A Node2D, AND THAT USED TO BE THE WHOLE PROBLEM.
## Multiplied by the camera's zoom (0.46 .. 2.6) and by `_pop` (up to 1.5), a
## damage number ran from **7 screen pixels to 101** across a single fight — the
## same "-12" was unreadable when the camera pulled back to frame a crowd and a
## billboard when it pushed in on a duel. `_draw` now multiplies by
## `HudStyle.ui_scale`, which holds it at 29px (62 for a crit pop) throughout. See
## the ONE ZOOM RULE block in `HudStyle`.
const BASE_SIZE: int = HudStyle.SMALL + 4   # 15 — unchanged at the reference zoom
const BIG_SIZE: int = HudStyle.TITLE        # 26 — unchanged at the reference zoom

## Live count of numbers currently animating. The cap check, O(1).
static var _alive: int = 0
## Retired instances available for reuse. Still children of their arena, hidden
## and not processing. Never larger than MAX_ALIVE.
##
## ⚠ DELIBERATELY UNTYPED, and this cost a real bug. As `Array[DamageNumber]`,
## reading an element whose node had already been freed — which is the NORMAL
## state of this pool the moment a floor is torn down — raises "Trying to assign
## invalid previously freed instance" on the typed assignment. In GDScript a
## runtime error ABORTS THE ENCLOSING FUNCTION and returns the type's zero, so
## `_take` would have handed `spawn()` a null and crashed on the next line, and
## `reset_pool` would have stopped half-way through cleaning up. Every read below
## therefore goes through a Variant and an `is_instance_valid` check BEFORE any
## cast. Caught by tools/slice_test_mobile_config.gd, which teardown-tests the
## pool on purpose.
static var _pool: Array = []

var _text: String = ""
var _color: Color = HudStyle.CHALK
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
## ⚠ OFF. Maker: *"you can remove the damage numbers I think they are overwhelming if
## the health bar is above them / at the top in all combat"* — and they are right that
## it is duplicated information: every fighter already wears a bar, and the duel puts
## both totals across the top of the screen in the corner colours.
##
## A FLAG RATHER THAN A DELETION, and rather than editing the ~20 call sites. The
## numbers are the only per-hit readout the game has, so they are genuinely useful
## while TUNING (which hit did what, is that spell landing twice) — deleting them
## would throw away a debugging instrument to answer a presentation note. Flip this to
## re-arm every call site at once.
##
## The pool, the cap and the recycling all still work when it is on; the suite that
## covers them sets this true, because that test is about the POOL and not about
## whether the feature is switched on.
static var show_numbers: bool = false


static func spawn(parent: Node, world_pos: Vector2, amount: int, color: Color = HudStyle.CHALK, crit: bool = false) -> void:
	if not show_numbers:
		return
	if parent == null or not parent.is_inside_tree() or amount <= 0:
		return
	if _alive >= MAX_ALIVE:
		return
	var dn: DamageNumber = _take(parent)
	# Bounded so `_draw` can safely draw unclipped — see its note. Past four digits
	# the exact figure is not information anyone reads mid-fight.
	dn._text = "-9999+" if absi(amount) > 9999 else "-" + str(absi(amount))
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
	# ⚠ BELOW THE HEALTH BARS, WHICH IT WAS NOT. This was 60 against
	# `CharacterBars`' 30, so the number explaining a hit could cover the bar that
	# hit moved. Both indices now come from one place.
	dn.z_index = HudStyle.Z_DAMAGE_NUMBER  # above fighters + most VFX
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
		var raw: Variant = _pool.pop_back()   # Variant first — see the _pool note
		if not is_instance_valid(raw):
			continue  # went down with its arena
		var candidate: DamageNumber = raw
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
	for raw: Variant in _pool:
		if is_instance_valid(raw):
			(raw as DamageNumber).queue_free()
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
	var ui: float = HudStyle.ui_scale(self)
	var fs: int = maxi(1, int(round(float(_size) * _pop * ui)))
	var col: Color = HudStyle.with_a(_color, alpha)
	var outline: Color = HudStyle.ink(alpha * 0.95)
	# ⚠ THE OUTLINE WEIGHT IS NO LONGER A FUNCTION OF THE FONT SIZE. `maxi(4, fs/4)`
	# ran from 4 to 25 across the zoom range, so the same number was outlined like
	# body copy at one moment and like a title card the next. `HudStyle.outline_for`
	# gives the HUD two weights; the compensation scales the whole glyph anyway.
	var stroke: int = int(round(float(HudStyle.outline_for(_size)) * ui))
	# Center the text horizontally on the origin.
	var w: float = font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos: Vector2 = Vector2(-w * 0.5, 0.0)
	# ⚠ `-1` FOR THE WIDTH IS "NO CLIP", AND THAT IS DELIBERATE HERE — but only
	# because the STRING is bounded instead. `spawn()` caps the printed magnitude,
	# so the longest text this can ever draw is five characters; an unbounded amount
	# used to render "-99999" straight off the side of the fighter it belonged to.
	draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, stroke, outline)
	draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
