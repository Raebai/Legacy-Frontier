extends ExitPortal
## THE WAY OUT OF THE TOWER — a TELEPORT PAD, on the ground, in the middle of the
## arena. It appears when the floor's boss dies; you WALK ONTO it, a column of
## light rises and takes you, and the run ends back in the Antechamber.
##
## Maker's ruling, verbatim: "once killing the boss, the 'leave the tower' thing
## should be a door that spawns on the ground in the middle, or a teleport pad like
## what we use in the hubs except it summons a beam of light that looks like you
## teleported."
##
## ── IT IS A SUBCLASS OF `ExitPortal`, AND THAT IS THE WHOLE POINT ─────────────
## The thing this replaces is the gold `ExitPortal` labelled "LEAVE THE TOWER":
## `Arena._build_return_portal` builds it, `Arena._on_return_taken` answers its
## `taken` signal by putting up the confirm card, and `Arena._confirm_leave` is what
## actually leaves (`Net.request_return()` in co-op, `GameState.return_to_hub()` in
## single player). ⚠ THIS PAD DOES NOT REIMPLEMENT ANY OF THAT. It emits the same
## `taken`, from the same `_fire()` once-guard, into the same handler — so there is
## still exactly ONE way out of a cleared floor and exactly one place that decides
## what leaving costs. Extending rather than copying also keeps `Arena`'s
## `_return_portal: ExitPortal` typed field, its `_clear_portal()` teardown and its
## `_cancel_leave()` re-arm working untouched: the hook is which script gets `.new()`d.
##
## ⚠ NO `class_name`. A brand-new global class is absent from
## `global_script_class_cache.cfg` until the editor rescans, which breaks every
## headless tool that loads this file before then. Reached by `preload` from `Arena`
## and by `load()` from its test — the same rule `RaiseThrall.gd` follows.
##
## ── THE ORDER IS BEAM, *THEN* `taken`, AND IT HAS TO BE ───────────────────────
## `Arena._on_return_taken` **frees this node** the instant `taken` arrives (it has
## to — the confirm's "keep climbing" branch rebuilds a fresh one once you step
## off). So a beam played after the emit would be destroyed on the same frame and
## nobody would ever see it. The trip therefore runs first: step on -> the hero is
## taken hold of, lifted and faded while the column climbs (~0.3 s) -> the beam
## reaches full -> ONLY THEN `taken`, and the confirm card lands on a screen where
## the light is already at its brightest. That is `ArmoryStation`'s "the beam plays
## WHILE the screen opens" grammar, reached from the other side.
##
## ⚠ WHICH MEANS THE HERO MUST BE PUT BACK ON THE WAY OUT OF THE TREE. We freeze and
## float a body we do not own the lifetime of, and the node doing the freezing is
## about to be freed by someone else. `_exit_tree` is the only place that is
## guaranteed to run for BOTH endings (confirm opened, or the floor was torn down
## under us), so the restore lives there and `_release_player` is idempotent.
## Getting this wrong leaves a player frozen, half-transparent, hanging in the air.
##
## ── WHY THE CONFIRM STAYS ─────────────────────────────────────────────────────
## `Arena`'s confirm exists because walking the wrong way used to end the session
## for the whole party. Moving the exit to the MIDDLE of the room makes an accidental
## brush MORE likely, not less — the middle is where you already are. So the pad
## carries two rings, exactly as `TowerDoor` does: a wide one that only lights the
## hint, and a tight one, no bigger than the disc you can see, that actually takes
## you. The card behind it is the backstop, not a nag.
##
## ── TWO WAYS IN, ONE DOOR ─────────────────────────────────────────────────────
## Walking in is the maker's ask. `talk` still works because that is what a
## controller and the touch pad press, and a pad you can only reach with precise
## walking is unreachable on a phone. Both routes land in `_enter`, so there is one
## set of guards rather than two — `TowerDoor`'s exact pattern.

## ── THE DISC ──────────────────────────────────────────────────────────────────
## Restated from `ArmoryStation` rather than imported: that script has no
## `class_name` (it is attached by `World`), and this is the same restate-the-few-
## numbers trade `Arena` already makes with `RunSummary`'s palette. If the hub pads
## are ever re-proportioned, these move with them — they are meant to read as one
## family of object.
##
## Sized off the ring it replaces so the two exits on a cleared floor stay legible
## at the same scale: the cyan climb-exit is `ExitPortal.RADIUS` across, and this is
## a hair wider because it lies down and a flattened shape reads smaller.
const PAD_RADIUS: float = RADIUS * 1.15
## It LIES DOWN: an ellipse, not a circle. The whole invitation is "stand here",
## which no upright shape can say.
const PAD_SQUASH: float = 0.30
const PAD_RIM_WIDTH: float = 2.0

## ── THE COLUMN ────────────────────────────────────────────────────────────────
## Present at rest and low, so the pad announces itself from across the room; the
## ACTIVATION is the same column at full brightness. One drawing, so the two can
## never disagree with each other.
const COLUMN_WIDTH: float = PAD_RADIUS * 0.70
const COLUMN_HEIGHT: float = PAD_RADIUS * 3.0
const COLUMN_REST_ALPHA: float = 0.09
## Units of `_beam` per second. The rise is deliberately shorter than any card takes
## to animate in — the beam is the answer to "did that work", not a cutscene.
const BEAM_RISE: float = 3.4
const BEAM_FALL: float = 2.2
## How far the hero rises while the beam holds them. Enough to read as "gone", small
## enough that the framing camera never has to move for it.
const LIFT_HEIGHT: float = 40.0
## How much of the hero is left behind at full beam. Not 1.0: a body that vanishes
## completely reads as a bug on the frame the confirm appears over it.
const LIFT_FADE: float = 0.85

## ── THE TWO RINGS ─────────────────────────────────────────────────────────────
## ⚠ THE CATCH VOLUME IS TALL, NOT ROUND, AND THAT IS DELIBERATE. A floor's ground
## line is `room_size.y - WALL_THICKNESS * 0.5` but a hero's ORIGIN stands 40 px
## above it (`FloorGen`: `hero_start = Vector2(hx, ground_y - 40.0)`), and the pad's
## own origin is wherever the caller put it. A circle centred on the disc would
## depend on which of those two the hook chose; a column that spans from the disc up
## past head height catches a body standing on the pad either way.
const CATCH_HEIGHT: float = 96.0
## The step that takes you: no wider than the disc you can see, so "I did not mean
## to do that" is not a thing the pad can cause on its own.
const ENTER_RADIUS: float = PAD_RADIUS * 0.62
## The ring that only lights the hint — you can read the pad from a jog away.
const HINT_RADIUS: float = PAD_RADIUS * 4.0
## ⚠ MASK 1 AND 2. A `Hero` is on collision layer 2 (`Hero.tscn`), and an `Area2D`'s
## default mask is bit 1 ALONE — the exact trap `ArmoryStation` and `TowerDoor` each
## carry a comment about, where a ring went silently blind the day the body it
## watched changed layers. Watching both is the honest fix: this ring's question is
## "is a fighter standing here", not "which layer did they happen to be authored on".
const BODY_MASK: int = 1 | 2
## Ignore the frame the pad is born on: it spawns into a room a hero may already be
## standing in the middle of (which, on a pad placed in the middle, is likely). Same
## value and same reason as `ExitPortal`'s own arm delay.
const ARM_DELAY: float = 0.35

## The glyph over the pad. A PICTURE, not a second word — the label already says
## "LEAVE THE TOWER" and the maker's standing rule for every screen in this game is
## "remove the words, keep the picture". Down-and-out, because that is the trip.
const GLYPH: String = "⇩"
const GLYPH_FONT_SIZE: int = 20
const HINT_TEXT: String = "walk in"

## The pad's drawing surface. A child `Node2D` at z -1 rather than `_draw` on the
## body, so the hero stands ON the disc and IN FRONT of the light rather than behind
## both — which is what makes the rise read as being taken upward.
var _art: Node2D = null
## 0 at rest, 1 at full beam. The ONLY animation variable: the disc, the rim, the
## column and the lift all read it, so the pad can never be lit in one part and dark
## in another.
var _beam: float = 0.0
var _beam_up: bool = false
## Latched the moment a hero commits, so a second body brushing the ring mid-rise
## cannot start a second trip.
var _leaving: bool = false
var _in_range: bool = false
var _hint: Label = null
var _step: Area2D = null

## The body we took hold of, and everything about it we have to give back. Restored
## from what was READ here, never from constants — a hero mid-jump, or one some other
## system had tinted or already frozen, must land back exactly as they were.
var _lifted: Node2D = null
var _lift_from: Vector2 = Vector2.ZERO
var _lift_alpha: float = 1.0
var _lift_was_processing: bool = true


func _ready() -> void:
	# ⚠ `super._ready()` IS NOT CALLED, ON PURPOSE. `ExitPortal._ready` gives itself a
	# 30 px circle collider and wires `body_entered` straight to `_fire` — i.e. a ring
	# that takes you the moment you touch it, which is the exact behaviour the two-ring
	# split exists to replace. What we inherit and DO want is the contract: the `taken`
	# signal, `portal_label` / `ring_color` / `trigger_group`, and `_fire()`'s
	# once-and-once-only guard.
	_art = Node2D.new()
	_art.name = "Art"
	_art.z_index = -1
	_art.draw.connect(_draw_pad)
	add_child(_art)

	_build_label()
	_build_hint_ring()
	_build_step_ring()

	# `_armed` is the base class's flag; `_fire()` does not read it, so the gate lives
	# in `_enter`. One timer, same duration as the ring it replaces.
	get_tree().create_timer(ARM_DELAY).timeout.connect(func() -> void: _armed = true)


## ⚠ THE INHERITED RING MUST NOT DRAW. `ExitPortal._draw` paints the pulsing circle
## on the body itself; left alone the pad would wear both its own disc and the ring
## it was built to replace, at two different z levels. Everything this node draws is
## drawn on `_art`.
func _draw() -> void:
	pass


## The word, and the picture. The word stays (unlike the hub pads, which are glyph-
## only) because a cleared floor has TWO exits standing in it with opposite
## consequences — the cyan one climbs, this gold one ends the run — and telling them
## apart by colour alone is a coin flip made under fight adrenaline.
func _build_label() -> void:
	var label := Label.new()
	label.text = portal_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(PAD_RADIUS * 6.0, 16.0)
	label.position = Vector2(-PAD_RADIUS * 3.0, -COLUMN_HEIGHT - 30.0)
	label.add_theme_color_override("font_color", ring_color.lightened(0.3))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)

	var glyph := Label.new()
	glyph.text = GLYPH
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.size = Vector2(PAD_RADIUS * 2.0, GLYPH_FONT_SIZE)
	glyph.position = Vector2(-PAD_RADIUS, -COLUMN_HEIGHT * 0.62)
	glyph.add_theme_font_size_override("font_size", GLYPH_FONT_SIZE)
	glyph.add_theme_color_override("font_color", ring_color)
	glyph.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.09, 0.9))
	glyph.add_theme_constant_override("outline_size", 4)
	add_child(glyph)

	_hint = Label.new()
	_hint.text = HINT_TEXT
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size = Vector2(PAD_RADIUS * 4.0, 14.0)
	_hint.position = Vector2(-PAD_RADIUS * 2.0, -COLUMN_HEIGHT - 48.0)
	_hint.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.visible = false
	add_child(_hint)


## The WIDE ring, on the pad's own body: it lights the hint and nothing else.
func _build_hint_ring() -> void:
	collision_mask = BODY_MASK
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HINT_RADIUS
	cs.shape = circle
	cs.position = Vector2(0.0, -CATCH_HEIGHT * 0.5)
	add_child(cs)
	body_entered.connect(_on_hint_entered)
	body_exited.connect(_on_hint_exited)


## The TIGHT ring: the step that actually takes you. Its own `Area2D` child so the
## hint ring above can be wide without the trip being wide with it.
func _build_step_ring() -> void:
	_step = Area2D.new()
	_step.name = "Step"
	_step.collision_mask = BODY_MASK
	add_child(_step)
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(ENTER_RADIUS * 2.0, CATCH_HEIGHT)
	cs.shape = box
	cs.position = Vector2(0.0, -CATCH_HEIGHT * 0.5)
	_step.add_child(cs)
	_step.body_entered.connect(_enter)


func _on_hint_entered(body: Node) -> void:
	if body.is_in_group(trigger_group):
		_in_range = true
		if _hint != null:
			_hint.visible = true


func _on_hint_exited(body: Node) -> void:
	if body.is_in_group(trigger_group):
		_in_range = false
		if _hint != null:
			_hint.visible = false


## ⚠ E IS NOT A LEFTOVER, AND IT IS NOT FREE EITHER. `talk` is also `Revive`'s
## channel key (see `Revive.REVIVE_ACTION`), and `Revive` POLLS the action rather
## than consuming an event — so marking this handled would not stop it. A cleared
## floor can still have a downed teammate lying on it, and stealing their pick-up
## key to end the run is the worst possible misfire. So the fallback stands down
## entirely while anyone is down; walking onto the pad still works, and so does the
## keypress the moment they are back up.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("talk") or not _in_range:
		return
	if _someone_is_down():
		return
	get_viewport().set_input_as_handled()
	_enter(_nearest_trigger_body())


func _someone_is_down() -> bool:
	for h: Node in get_tree().get_nodes_in_group(&"hero"):
		if h.has_method(&"is_downed") and bool(h.call(&"is_downed")):
			return true
	return false


## Whoever the `talk` press should be spoken for. The keypress has no body attached
## to it, so the pad picks the closest fighter inside the hint ring — which on a pad
## is the one standing on it.
func _nearest_trigger_body() -> Node:
	var best: Node = null
	var best_d: float = INF
	for h: Node in get_tree().get_nodes_in_group(trigger_group):
		if not (h is Node2D) or not is_instance_valid(h):
			continue
		var d: float = (h as Node2D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = h
	return best


## THE ONE DOOR. Both routes land here, so the guards are written once.
func _enter(body: Node) -> void:
	if _leaving or _taken or not _armed:
		return
	if body == null or not body.is_in_group(trigger_group):
		return
	_leaving = true
	_beam_up = true
	_take_hold_of(body)


## Take hold of the fighter standing on the pad.
##
## ⚠ ONLY A BODY WE OWN. In co-op a remote hero is a PUPPET whose position arrives
## over the wire every frame; freezing and floating one locally would fight the
## replication and put someone else's hero somewhere it is not. The beam and the
## `taken` emit still happen for everyone (matching `ExitPortal`, where any hero in
## `trigger_group` fires the exit) — it is only the lift that is authority-gated.
## `is_multiplayer_authority()` is true for everything in single player.
func _take_hold_of(body: Node) -> void:
	if not (body is Node2D) or not body.is_multiplayer_authority():
		return
	_lifted = body as Node2D
	_lift_from = _lifted.global_position
	_lift_alpha = _lifted.modulate.a
	# RECORDED, not assumed true. `ArmoryStation` restores this to `true`
	# unconditionally, which is safe in a town where nothing else freezes anyone; a
	# cleared tower floor can have a hero already held by something else, and handing
	# them back "running" would be this pad silently cancelling it.
	_lift_was_processing = _lifted.is_physics_processing()
	# A `Hero` knows nothing about pads: left running it would keep reading input and
	# keep applying gravity, and would simply walk back out of its own beam.
	_lifted.set_physics_process(false)


## The beam clock, the lift, and the emit.
##
## ⚠ `taken` FIRES AT THE TOP OF THE RISE, NOT AT THE BOTTOM. See the header: the
## `Arena` handler frees this node, so everything the pad wants seen has to have been
## seen already.
func _process(delta: float) -> void:
	_t += delta
	_beam = clampf(_beam + (BEAM_RISE if _beam_up else -BEAM_FALL) * delta, 0.0, 1.0)
	if _lifted != null and is_instance_valid(_lifted):
		_lifted.global_position = _lift_from + Vector2(0.0, -LIFT_HEIGHT * _beam)
		_lifted.modulate.a = _lift_alpha * (1.0 - LIFT_FADE * _beam)
	if _beam_up and _beam >= 1.0:
		_fire()          # inherited: guarded, emits `taken` exactly once
	elif not _beam_up and _armed and not _taken and not _leaving:
		# Walk-in poll, for the same reason `ExitPortal` polls: `body_entered` only
		# fires on the ENTER edge, which is missed by a body that was already inside
		# the shape when the pad armed — and on a pad in the MIDDLE of the room, that
		# is the common case, not the corner one.
		for b: Node in _step.get_overlapping_bodies():
			if b.is_in_group(trigger_group):
				_enter(b)
				break
	if _art != null:
		_art.queue_redraw()


## ⚠ THE HERO IS PUT BACK HERE, AND ONLY HERE. This node does not choose when it
## dies — `Arena._on_return_taken` frees it to raise the confirm, and
## `Arena._clear_portal` frees it when the floor is torn down. `_exit_tree` is the
## one path both of those go through. If the player then says "keep climbing",
## `Arena` builds a fresh pad once they have stepped clear, and they are standing
## exactly where they were with the alpha and the physics they arrived with.
func _exit_tree() -> void:
	_release_player()


## Idempotent: safe to call twice, safe to call on a pad that never lifted anyone.
func _release_player() -> void:
	if _lifted != null and is_instance_valid(_lifted):
		_lifted.global_position = _lift_from
		_lifted.modulate.a = _lift_alpha
		_lifted.set_physics_process(_lift_was_processing)
	_lifted = null


## ── THE DRAWING ───────────────────────────────────────────────────────────────
## The whole pad in one function: a floor glow, a flat disc, its rim, a column of
## light standing on it and a white-hot core inside the column. `_beam` is the only
## variable any of them read.
##
## ⚠ DRAWN, NOT NODES, and that is what makes it degrade for free at LOW quality:
## this is fewer draw calls than the single pulsing ring it replaces, and there is
## nothing to animate out of step with anything else.
func _draw_pad() -> void:
	var col: Color = ring_color
	var lit: float = clampf(_beam, 0.0, 1.0)
	# A slow breath at rest so the pad is legible across a big room without being a
	# strobe. Same idea (and the same `_t`) as the ring it replaces.
	var pulse: float = 0.75 + 0.25 * sin(_t * 3.0)

	# Widest and faintest: the pad has a footprint before it has an edge.
	_ellipse(Vector2.ZERO, PAD_RADIUS * (1.35 + 0.25 * lit),
		Color(col.r, col.g, col.b, (0.06 + 0.14 * lit) * pulse))
	# The disc, then the rim. The rim is the part that reads at distance.
	_ellipse(Vector2.ZERO, PAD_RADIUS, Color(col.r, col.g, col.b, 0.14 + 0.30 * lit))
	_ellipse_line(Vector2.ZERO, PAD_RADIUS,
		Color(col.r, col.g, col.b, (0.55 + 0.45 * lit) * pulse), PAD_RIM_WIDTH + lit * 1.5)

	# THE COLUMN. Alpha falls off upward so the light reads as LEAVING rather than as
	# a painted bar, and it narrows as it brightens — a beam gathering, not a slab.
	var a: float = COLUMN_REST_ALPHA + (0.62 - COLUMN_REST_ALPHA) * lit
	var half: float = COLUMN_WIDTH * 0.5 * (1.0 - 0.25 * lit)
	var top: float = -COLUMN_HEIGHT * (0.55 + 0.45 * lit)
	_art.draw_polygon(
		PackedVector2Array([
			Vector2(-half, 0.0), Vector2(half, 0.0),
			Vector2(half * 0.55, top), Vector2(-half * 0.55, top),
		]),
		PackedColorArray([
			Color(col.r, col.g, col.b, a), Color(col.r, col.g, col.b, a),
			Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0),
		]))
	# The white-hot core, only while it is firing. This is the frame the eye catches;
	# without it the beam reads as the pad merely getting brighter.
	if lit > 0.02:
		var core: float = half * 0.32
		_art.draw_polygon(
			PackedVector2Array([
				Vector2(-core, 0.0), Vector2(core, 0.0),
				Vector2(core * 0.4, top * 1.05), Vector2(-core * 0.4, top * 1.05),
			]),
			PackedColorArray([
				Color(1.0, 1.0, 1.0, 0.55 * lit), Color(1.0, 1.0, 1.0, 0.55 * lit),
				Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.0),
			]))


## A filled ellipse, flattened by `PAD_SQUASH` so it lies on the floor. Drawing a
## circle under a scaled transform would scale the rim WIDTH with it, which is what
## makes a squashed ring read as a smudge at distance.
func _ellipse(at: Vector2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in 22:
		var t: float = TAU * float(i) / 22.0
		pts.append(at + Vector2(cos(t) * radius, sin(t) * radius * PAD_SQUASH))
	_art.draw_colored_polygon(pts, col)


func _ellipse_line(at: Vector2, radius: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i: int in 23:
		var t: float = TAU * float(i % 22) / 22.0
		pts.append(at + Vector2(cos(t) * radius, sin(t) * radius * PAD_SQUASH))
	_art.draw_polyline(pts, col, width)
