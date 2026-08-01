class_name Revive
extends Node2D
## PICKING YOUR TEAMMATE BACK UP — the only exit from ghost form.
##
## The maker's rule: "dying cost is a life in ghost form until your teammate revives
## you; if you all die then the game is over". `GhostForm` owns the being-dead half;
## this file owns the coming-back half, and it is the mechanic that makes the rule a
## co-op rule instead of a lives counter.
##
## ══ THE MECHANIC, AND WHY IT IS A CHANNEL ══════════════════════════════════════
## Two shapes were on the table:
##
##   A. INSTANT ON TOUCH. Frictionless. Also decision-free: you walk over your
##      friend and they are up, so being downed costs the party nothing but a jog
##      and "if you all die the game is over" almost never gets to happen.
##   B. PROXIMITY + A CHANNEL.  <- SHIPPED.
##      `CHANNEL_TIME` seconds inside `RANGE`. Those seconds are spent NOT dodging,
##      NOT casting, standing next to the exact spot that just killed somebody. So
##      picking someone up is a read — "can I survive two seconds here, or do I
##      clear the pack first?" — and that read is the whole social texture of the
##      mechanic. It is also what makes `GhostForm`'s HAUNT gust matter: the ghost's
##      job is to buy the rescuer those two seconds.
##
## ══ WHAT CANCELS IT, DELIBERATELY ══════════════════════════════════════════════
##   * LETTING GO cancels, and the progress resets to zero. No partial credit: a
##     revive you have to commit to twice is one you did not commit to once.
##   * LEAVING `RANGE` cancels (either of you — the ghost drifting away breaks it
##     too, which is the ghost's half of the contract).
##   * TAKING DAMAGE DOES **NOT** CANCEL, and that is a decision rather than an
##     omission. Friendly fire is on, a floor is a swarm, and a revive that breaks
##     on any chip damage is a revive that is impossible in precisely the fights
##     where somebody went down. The cost is already paid by standing still; adding
##     a second failure condition on top does not make it tenser, it makes it not
##     exist. `CANCEL_ON_DAMAGE` is here so that call can be reversed after a
##     playtest rather than re-argued from scratch.
##
## ══ ONE BUTTON, AND IT WORKS ON A PHONE ════════════════════════════════════════
## There is no spare button. `SpellHandoff` solved exactly this problem by reusing
## the hub's unused `talk` action and having `TouchControls` draw a CONTEXTUAL pad in
## the centre dead band between the thumb zones — and that precedent is followed here
## verbatim, including publishing `can_revive()` / `revive_label()` / `revive_progress()`
## and joining `PROMPT_GROUP` so a pad can find this node without either file
## importing the other.
##
## ⚠ THE PAD IS DRAWN HERE, NOT IN `TouchControls`, AND THAT IS A FILE-OWNERSHIP
## CHOICE RATHER THAN A DESIGN ONE. `TouchControls.gd` belongs to another workstream
## right now. Leaving the pad unbuilt would ship a mechanic that is literally
## unreachable on the target platform — the exact bug the handoff pad was written to
## fix — so this node builds its own, in the same dead band, lifted clear of the
## handoff slot. When `TouchControls` adopts the query API above, delete
## `RevivePad` and `_build_pad()` from this file and nothing else changes.
##
## ⚠ COLLIDING WITH THE HANDOFF: they cannot both be live. `GhostForm.enter` takes a
## ghost out of the target groups but leaves it in `hero`, so `SpellHandoff` can still
## see a ghost as a receiver — however it only offers at all when the giver is holding
## a Tier 3 drop, and the outcome of a double-fire (they get the spell AND get picked
## up) is harmless. The pads sit at different heights so a thumb can never hit both.

## The action a revive is driven by. The SAME one `SpellHandoff` polls, for the same
## reason it chose it: `talk` is the v0.0 hub's NPC key and is bound to nothing inside
## the arena, so it costs no new keybinding and collides with nothing in combat.
const REVIVE_ACTION: StringName = &"talk"

## How close you have to be. Wider than the handoff's 74 (that one wants you to have
## deliberately stopped; this one has to be reachable while something is chasing you)
## but still close enough that you are standing in the danger. UNTESTED FEEL GUESS.
const RANGE: float = 92.0
## Seconds of holding. UNTESTED FEEL GUESS — the number that decides whether a revive
## is a brave call or a formality. Two seconds is roughly one enemy attack cycle.
const CHANNEL_TIME: float = 2.0
## See the header. Flip after playing, not before.
const CANCEL_ON_DAMAGE: bool = false

## Joined so a touch layer can ask "is a revive live right now" without importing
## this class. Mirrors `SpellHandoff.HANDOFF_GROUP`.
const PROMPT_GROUP: StringName = &"revive_prompt"

## --- the in-world prompt + progress ring (drawn on the GHOST) ---
const RING_RADIUS: float = 27.0
const RING_WIDTH: float = 3.4
const RING_BG: Color = Color(0.35, 0.38, 0.48, 0.45)
const RING_FILL: Color = Color(0.55, 1.0, 0.78, 0.95)
const PROMPT_COLOR: Color = Color(0.72, 1.0, 0.88, 1.0)
const TETHER_COLOR: Color = Color(0.55, 1.0, 0.78, 0.30)
const FLASH_TIME: float = 0.8

## --- the contextual touch pad (centre dead band, above the handoff slot) ---
const PAD_SIZE: Vector2 = Vector2(128.0, 34.0)
## Up from the bottom edge. `TouchControls.HANDOFF_LIFT` is 30 and its pad is 34
## tall, so 74 clears it with room — the two can never be under one thumb.
const PAD_LIFT: float = 74.0
const PAD_BG: Color = Color(0.06, 0.14, 0.11, 0.74)
const PAD_RIM: Color = Color(0.55, 1.0, 0.78, 0.9)
const PAD_TEXT: Color = Color(0.86, 1.0, 0.94, 0.98)
const PAD_FONT_SIZE: int = 11
const PAD_LAYER: int = 61   # just above the ability bar (60), below the pause menu (90)

## Force the touch pad on a desktop build. Capture tools and the headless suite set
## this; the game never does. Mirrors `TouchControls.force_visible`.
var force_pad: bool = false

var _rescuer: Node2D = null
var _ghost: Node2D = null
var _progress: float = 0.0
var _phase: float = 0.0
var _flash: float = 0.0
var _flash_at: Vector2 = Vector2.ZERO
var _pad: RevivePad = null
var _pad_layer: CanvasLayer = null


func _ready() -> void:
	add_to_group(PROMPT_GROUP)
	_build_pad()


# ═════════════════════════════════════════════════════════ the published query
## Is there a live revive offer this instant — a living local player, a ghost inside
## `RANGE`? The pad's whole existence is this boolean, and it is the SAME state
## `_draw` renders the in-world prompt from, so the button and the prompt can never
## disagree about whether a revive is possible.
func can_revive() -> bool:
	return _rescuer != null and _ghost != null


## How far through the channel we are, 0..1. Drawn both in-world and on the pad, so
## a thumb player can see the bar they are filling without looking away from it.
func revive_progress() -> float:
	return clampf(_progress / maxf(CHANNEL_TIME, 0.001), 0.0, 1.0)


## Label for the pad. Deliberately the VERB, not a name: at 640x360 with a fight on,
## "REVIVE" is legible and "Revive Raaed" is a smear.
func revive_label() -> String:
	return "" if not can_revive() else "REVIVE"


# ═══════════════════════════════════════════════════════════════════ the loop
func _process(delta: float) -> void:
	_phase += delta
	_flash = maxf(_flash - delta, 0.0)
	_resolve_pair()
	if can_revive() and Input.is_action_pressed(REVIVE_ACTION):
		_progress += delta
		if _progress >= CHANNEL_TIME:
			_progress = 0.0
			_complete()
	else:
		# Hard reset, no partial credit. See the header.
		_progress = 0.0
	_sync_pad()
	queue_redraw()


## Finish the channel. ONE authoritative decision: in co-op the request goes to the
## host, which awards it once and replays the identical apply on both peers
## (`Net.request_revive`, modelled on the pickup race). In single player there is no
## host to ask, so the same `apply` runs directly — one implementation, two callers.
func _complete() -> void:
	var ghost: Node2D = _ghost
	if ghost == null or not is_instance_valid(ghost):
		return
	_flash = FLASH_TIME
	_flash_at = ghost.global_position
	var net: Node = get_node_or_null(^"/root/Net")
	if net != null and net.has_method(&"is_active") and bool(net.call(&"is_active")) \
			and net.has_method(&"request_revive"):
		net.call(&"request_revive", ghost)
		return
	apply(ghost)


## THE APPLY, and the only place a hero comes back up. Static so `Net._client_revive`
## can run the byte-identical code path on every peer.
##
## ⚠ THE AUTHORITY TEST IS INSIDE, NOT OUTSIDE. The RPC is `call_local`, so both peers
## run this — but only the ghost's OWNER may mutate its state, because `downed` and
## `hp` replicate from there and a puppet writing them would be corrected a frame
## later, flickering the ghost off and back on. Every peer still plays the FX, which
## is the half that has to be seen on both screens.
##
## ⚠ AUTOLOAD-FREE. Named from `Net`, so no `Sfx` / `Tuning` identifier may appear in
## this function — under `--script` an autoload name inside a static function is a
## compile error that fails the whole dependency chain and reports as something else
## entirely. Sound goes through the tree lookup, the same idiom `SpellDeflect._sfx` uses.
static func apply(ghost: Node) -> bool:
	if ghost == null or not is_instance_valid(ghost) or not ghost.has_method(&"revive"):
		return false
	var at: Vector2 = (ghost as Node2D).global_position if ghost is Node2D else Vector2.ZERO
	_fx(ghost, at)
	if _owns(ghost):
		ghost.call(&"revive", DeathRules.REVIVE_HP_FRACTION)
	return true


## Does THIS peer drive that body? True in single player (no session), true on the
## owning peer in co-op. Read through the tree so nothing static names the autoload.
static func _owns(body: Node) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	var net: Node = tree.root.get_node_or_null(^"/root/Net")
	if net == null or not net.has_method(&"is_active") or not bool(net.call(&"is_active")):
		return true
	return body.is_multiplayer_authority()


## The comeback beat: a bright chalk bloom where the drawing gets redrawn, plus a
## crisp ding. Deliberately loud — coming back up is the payoff for the ghost's
## whole 20 seconds, and a silent revive would waste it.
static func _fx(ghost: Node, at: Vector2) -> void:
	var parent: Node = ghost.get_parent()
	if parent != null:
		CombatVfx.spawn_burst(parent, at,
			Color(1.5, 2.2, 1.9, 1.0), Color(0.5, 1.0, 0.8, 0.0),
			26, 0.55, 60.0, 240.0, 1.1, 3.0, 0.0, 0.0, true)
	Juice.shake_camera(5.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx: Node = tree.root.get_node_or_null(^"/root/Sfx")
	if sfx != null and sfx.has_method(&"play"):
		sfx.call(&"play", "ding", 1.2, 0.02)


# ═══════════════════════════════════════════════════════════════ who and whom
## Who could revive, and whom. Both are re-derived every frame rather than cached:
## heroes are respawned on a floor change and a cached handle to a freed body is
## exactly the stale reference that turns a co-op mechanic into a crash.
func _resolve_pair() -> void:
	var was: Node2D = _ghost
	_rescuer = null
	_ghost = null
	for h: Node in get_tree().get_nodes_in_group(&"hero"):
		if not _usable(h) or _is_ghost(h):
			continue
		if _is_local_player(h):
			_rescuer = h as Node2D
			break
	if _rescuer == null:
		return
	var best: float = RANGE
	for h: Node in get_tree().get_nodes_in_group(GhostForm.GHOST_GROUP):
		if h == _rescuer or not _usable(h) or not _is_ghost(h):
			continue
		# A hero mid-SECOND-WIND is already coming back on its own clock; offering to
		# revive it would let one press be spent on a body that did not need it.
		if h.has_method(&"awaiting_second_wind") and bool(h.call(&"awaiting_second_wind")):
			continue
		var d: float = _rescuer.global_position.distance_to((h as Node2D).global_position)
		if d < best:
			best = d
			_ghost = h as Node2D
	# Switching targets mid-channel must not inherit the old target's progress.
	if _ghost != was:
		_progress = 0.0


func _usable(n: Node) -> bool:
	return is_instance_valid(n) and not n.is_queued_for_deletion() and n is Node2D


func _is_ghost(h: Node) -> bool:
	return h.has_method(&"is_downed") and bool(h.call(&"is_downed"))


## Is this hero the one at the keyboard/thumbs? Copied from `SpellHandoff` rather
## than reinvented, INCLUDING its hard-won detail: read `controller` into a Variant
## first. The original asked for members that existed nowhere, `bool(null)` is an
## illegal conversion, an illegal conversion ABORTS the enclosing function, and the
## whole handoff mechanic silently never worked. Do not "simplify" this.
func _is_local_player(h: Node) -> bool:
	var driver: Variant = h.get(&"controller")
	if driver != null:
		return false
	var net: Node = get_node_or_null(^"/root/Net")
	if net != null and net.has_method(&"is_active") and bool(net.call(&"is_active")):
		return h.is_multiplayer_authority()
	return true


# ══════════════════════════════════════════════════════════════════════ drawing
func _draw() -> void:
	if _flash > 0.0:
		_draw_flash()
	if not can_revive():
		return
	var at: Vector2 = _ghost.global_position
	_draw_tether(at)
	_draw_ring(at)
	_draw_prompt(at)


## The filling ring, drawn on the GHOST. Both players are looking at the body on the
## floor, so that is where the bar goes — the rescuer sees their own progress and the
## ghost sees rescue arriving, from one drawing.
func _draw_ring(at: Vector2) -> void:
	draw_arc(at, RING_RADIUS, 0.0, TAU, 40, RING_BG, RING_WIDTH * 0.6, true)
	var p: float = revive_progress()
	if p <= 0.0:
		return
	# Starts at 12 o'clock and sweeps clockwise, the way every progress ring does.
	draw_arc(at, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * p, 48, RING_FILL, RING_WIDTH, true)


func _draw_prompt(at: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(_phase * 4.0)
	var p: float = revive_progress()
	var text: String = "[E] REVIVE" if p <= 0.0 else "REVIVE  %d%%" % int(round(p * 100.0))
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	var origin: Vector2 = at + Vector2(-w * 0.5, -46.0)
	draw_string(font, origin + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
		Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
		Color(PROMPT_COLOR.r, PROMPT_COLOR.g, PROMPT_COLOR.b, 0.72 + 0.28 * pulse))


## A line between the two, so in a crowd it is obvious WHO is being picked up.
func _draw_tether(at: Vector2) -> void:
	if _rescuer == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(_phase * 4.0)
	draw_line(_rescuer.global_position + Vector2(0.0, -14.0), at + Vector2(0.0, -14.0),
		Color(TETHER_COLOR.r, TETHER_COLOR.g, TETHER_COLOR.b,
			TETHER_COLOR.a + 0.2 * pulse), 1.8, true)


func _draw_flash() -> void:
	var t: float = _flash / FLASH_TIME
	draw_arc(_flash_at, 24.0 + 46.0 * (1.0 - t), 0.0, TAU, 40,
		Color(RING_FILL.r, RING_FILL.g, RING_FILL.b, t * 0.9), 2.6, true)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var text: String = "UP!"
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14).x
	draw_string(font, _flash_at + Vector2(-w * 0.5, -62.0 - 20.0 * (1.0 - t)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(PROMPT_COLOR.r, PROMPT_COLOR.g, PROMPT_COLOR.b, t))


# ═════════════════════════════════════════════════════════════════ the touch pad
## Built once, hidden until there is a ghost to pick up. Never built at all on a
## device with no touchscreen, so a desktop run is byte-identical to having no pad.
func _build_pad() -> void:
	if not (force_pad or DisplayServer.is_touchscreen_available()):
		return
	_pad_layer = CanvasLayer.new()
	_pad_layer.name = "RevivePadLayer"
	_pad_layer.layer = PAD_LAYER
	add_child(_pad_layer)
	_pad = RevivePad.new()
	_pad.visible = false
	_pad.anchor_left = 0.5
	_pad.anchor_right = 0.5
	_pad.anchor_top = 1.0
	_pad.anchor_bottom = 1.0
	_pad.offset_left = -PAD_SIZE.x * 0.5
	_pad.offset_right = PAD_SIZE.x * 0.5
	_pad.offset_top = -PAD_LIFT - PAD_SIZE.y
	_pad.offset_bottom = -PAD_LIFT
	# Consumes its own taps so no thumb stick spawns underneath it — the same rule
	# the handoff pad follows for the same reason.
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad_layer.add_child(_pad)


## Show/hide + feed the pad this frame's state. ⚠ THE RELEASE ON HIDE IS THE BUG
## GUARD: a pad that vanishes mid-press (the ghost got picked up, or drifted away)
## must not leave `talk` held down forever — every later revive would then start the
## instant it became legal, with nobody pressing anything.
func _sync_pad() -> void:
	if _pad == null:
		return
	if not can_revive():
		if _pad.visible:
			_pad.release()
			_pad.visible = false
		return
	_pad.progress = revive_progress()
	_pad.label = revive_label()
	_pad.visible = true


## True while the contextual revive pad is on screen. Test/capture affordance.
func pad_visible() -> bool:
	return _pad != null and _pad.visible


## THE CONTEXTUAL REVIVE PAD. Presses the SAME `talk` action the keyboard path polls
## rather than calling `_complete()` directly — one input path, so a change to when a
## revive is legal cannot land on desktop and miss the phone.
class RevivePad extends Control:
	var label: String = "REVIVE"
	var progress: float = 0.0
	var _held: bool = false
	var _phase: float = 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_phase += delta
		if visible:
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var pressed: bool = false
		var is_press_event: bool = false
		if event is InputEventScreenTouch:
			is_press_event = true
			pressed = (event as InputEventScreenTouch).pressed
		elif event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			is_press_event = true
			pressed = (event as InputEventMouseButton).pressed
		if not is_press_event:
			return
		accept_event()
		if pressed:
			press()
		else:
			release()

	## Public so a headless test can drive the affordance the way a thumb does —
	## through the real action, rather than by calling the revive directly.
	func press() -> void:
		if _held:
			return
		_held = true
		Input.action_press(Revive.REVIVE_ACTION)

	func release() -> void:
		if not _held:
			return
		_held = false
		Input.action_release(Revive.REVIVE_ACTION)

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		var pulse: float = 0.5 + 0.5 * sin(_phase * 4.0)
		draw_rect(box, Revive.PAD_BG, true)
		# THE FILL IS THE FEEDBACK. A hold with no visible progress under the thumb
		# reads as a button that did not work, and the player lets go at 80%.
		if progress > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(progress, 0.0, 1.0), size.y)),
				Color(Revive.RING_FILL.r, Revive.RING_FILL.g, Revive.RING_FILL.b, 0.30), true)
		draw_rect(box, Color(Revive.PAD_RIM.r, Revive.PAD_RIM.g, Revive.PAD_RIM.b,
			0.45 + 0.45 * pulse), false, 2.0 if _held else 1.5)
		var font: Font = ThemeDB.fallback_font
		if font == null:
			return
		var text: String = "REVIVE" if label == "" else label
		if progress > 0.0:
			text = "HOLD  %d%%" % int(round(progress * 100.0))
		draw_string(font, Vector2(0.0, size.y * 0.5 + float(Revive.PAD_FONT_SIZE) * 0.38),
			text, HORIZONTAL_ALIGNMENT_CENTER, size.x, Revive.PAD_FONT_SIZE, Revive.PAD_TEXT)
