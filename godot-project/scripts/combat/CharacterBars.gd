class_name CharacterBars
extends Node2D
## Every fighter's health readout. A child of the fighter (Hero/Enemy) so it follows
## position without following the rig's L/R flip. Polls the target's hp/max_hp each
## frame — the poll-don't-push idiom (AbilityBar) — so it needs no signals and works
## for any node exposing those fields.
##
## It draws in TWO coordinate spaces, and which one you get is the whole design:
##
##   * **ENEMIES stay over the head.** Body-attached, world-space, zoom-compensated.
##     With six enemies on screen, "which one of those is nearly dead" is a question
##     only a bar over that specific body can answer, and no amount of screen HUD
##     substitutes for it.
##   * **A PLAYER WITH A HOTBAR gets a screen plate instead.** Fixed in the bottom
##     corner, on a `CanvasLayer`, immune to the camera. See the HERO PLATE block.
##
## ══ WHY THE PLAYER'S BAR LEFT THE PLAYER'S HEAD ════════════════════════════════
## Maker: *"the health bar is blocking the stick figure, the main one — put that
## somewhere else so that it's clear and more professional"*.
##
## It was. A 52x7 bar centred over a 31px figure sits exactly where the player's eyes
## are, in a frame the camera has already tightened onto that figure, on top of the
## rig whose pose is the only thing telling you what you are currently doing. And the
## bar was there in the first place only because there was nowhere else for it: there
## was no screen-space player HUD in the game at all.
##
## The move also DELETES a problem rather than managing one. A `Node2D`'s on-screen
## size is its world size times the camera zoom, and `CombatCamera` swings 0.46..2.6 —
## **5.6x, during a fight**. `HudStyle.ui_scale()` exists to cancel that out, and it
## works, but it is compensation: the bar was shrinking and being grown back every
## frame. A `CanvasLayer` is not transformed by the camera, so the plate is the same
## number of pixels always. Nothing to compensate.
##
## ⚠ "A PLAYER" MEANS "HAS A HOTBAR", and that is a load-bearing definition rather
## than a convenience. `AbilityBar.bound_hero` is set for exactly the fighters a human
## is driving — player one, and each pad that joined through `LocalCoop`. A bot ally,
## a remote peer's body and a `BotMatch` fighter have no hotbar, keep the head bar, and
## stay readable as bodies. So `_resolve_plate` is not asking "am I the hero", it is
## asking "is someone holding the controls for me", which is the question that actually
## decides whether a screen corner should be spent on this fighter.
##
## ══ WHAT THE PLATE CARRIES ════════════════════════════════════════════════════
##   * A CHIP BAR. The damage you just took stays on screen as a pale ghost that
##     drains a beat later. It answers "how hard was that hit" — a question a bar that
##     snaps instantly cannot answer at all.
##   * SEGMENT TICKS every 25%, so "a quarter left" is read as a SHAPE.
##   * A HIT FLASH and a HEAL RIM, so losing and gaining health are equally loud.
##   * A DANGER PULSE under `LOW_FRACTION`.
##
## And on the BODY, for a plated player, exactly one thing survives: the danger ring at
## the feet. It is not a readout — it is a shape drawn around the figure, it is where
## the player's eyes already are, and it is the reason moving the bar to a corner does
## not cost you the "I am about to die" read.
##
## ⚠ NO NUMBERS, NO LABELS, ON PURPOSE. The standing rule is "this game has too much
## text and random UI pieces we dont need". Everything here is size, shape, motion and
## colour — nothing asks the player to read a word mid-fight.
##
## ══ THERE IS NO MANA BAR, BECAUSE THERE IS NO MANA ════════════════════════════
## Maker: *"remove the mana bar, we don't have that when in the tower"* — and they are
## right in the strongest possible sense. `Hero.gd:977` states it outright: mana no
## longer gates anything, `_cast_signature` neither checks nor spends it, and
## `Hero._physics_process` regenerates it at `MP_REGEN` 20/sec toward a `max_mp` of
## 100. **Nothing in the game can lower it.** The bar was therefore pinned at 100% for
## the entire lifetime of every hero that has ever existed: three pixels of solid blue,
## under the health bar, that had never once moved.
##
## Worse, two files carry a comment asserting this bar did not exist — `Hero.gd:991`
## ("`CharacterBars.configure(show_mp)` defaults to false and no caller has ever passed
## true, so the bar has never been drawn") and `BotMatch.gd:1681` (the same claim,
## called "dead code") — while `Hero.gd:1820` reads `bars.configure(self, true, -26.0)`.
## The one caller in the project passes true. Both comments are wrong, and the maker was
## looking at the bar they describe as impossible.
##
## The DRAW is gone and the `show_mp` parameter is kept: `Hero.gd` owns that call site
## and this file cannot edit it, so removing the parameter would break the build.
## `mp`/`max_mp` on `Hero` are also untouched — `SpellDef.mp_cost` still shelves spells
## through `SpellTier.of()` and still sizes cast sigils, so that field is load-bearing
## for reasons that have nothing to do with a bar.

const HudStyle := preload("res://scripts/ui/HudStyle.gd")

const WIDTH: float = 30.0
const HP_H: float = 4.0

## --- the head bar, for a fighter with NO hotbar (an enemy, a bot ally, a remote peer) ---
## The hero geometry is kept for the un-plated case: a co-op ally you can see but do not
## drive still needs a bar you can read from across the room.
const HERO_WIDTH: float = 52.0
const HERO_HP_H: float = 7.0

## Above this the bar is a resource; below it, it is a warning.
const LOW_FRACTION: float = 0.35

## --- the chip bar (damage just taken) ---
## Hold the ghost still for this long so the hit is legible, then drain it.
const CHIP_HOLD: float = 0.32
## Fraction of the bar the ghost drains per second once it lets go. 1.2 empties a
## full bar in under a second — fast enough not to lie about your current health.
const CHIP_DRAIN: float = 1.2
const CHIP_COLOR: Color = HudStyle.CHIP

## --- the hit flash ---
const FLASH_TIME: float = 0.18
## --- the heal pop (a green rim, so healing reads as loudly as being hit) ---
const HEAL_TIME: float = 0.30
## ONE green for "alive": the rim, the full end of the HP ramp and Hype's
## wave-cleared shout are the same colour, because to the player they mean the same
## thing. See HudStyle.MINT.
const HEAL_RIM: Color = HudStyle.MINT

## --- the danger ring at the feet ---
## The hero's collision box is centred on its origin and the figure stands ~15px
## above that; the ring sits at ground level under the body.
const RING_FEET_DROP: float = 14.0
const RING_RADIUS: float = 19.0
const RING_COLOR: Color = HudStyle.DANGER

## Above this % the fill bar saturates (the number keeps climbing regardless).
const PCT_VISUAL_MAX: float = 150.0
## Warm (low %) -> red (high %), Smash-style: the more hurt, the redder + farther you fly.
const PCT_WARM: Color = HudStyle.GOLD
const PCT_RED: Color = HudStyle.DANGER

## --- finding this fighter's hotbar ---
## Re-checked every `PLATE_POLL` seconds for `PLATE_WINDOW` seconds after the first
## frame, then never again.
##
## ⚠ IT CANNOT BE RESOLVED IN `configure()`, WHICH IS WHY THIS EXISTS. `Hero._ready`
## builds these bars; the hotbar is built later and elsewhere —
## `LocalCoop._build_bar_for` runs AFTER `heroes_root.add_child(h)` returns, and player
## one's is built by the Arena. A one-shot lookup at construction would find nothing and
## every player would keep the head bar. A window rather than a forever-poll because a
## fighter with no hotbar after four seconds does not have one, and re-learning that on
## every frame for the rest of a run is a tree walk for nothing.
const PLATE_POLL: float = 0.25
const PLATE_WINDOW: float = 4.0

var _target: Node = null
var _show_mp: bool = false
var _hp_ratio: float = 1.0
var _has_hp: bool = false
## SANDBOX Smash mode (GameState.ringout_mode): render a rising damage % instead
## of the green HP bar.
var _ringout: bool = false
var _pct: float = 0.0

## --- hero mode state ---
var _is_hero: bool = false
var _chip_ratio: float = 1.0
var _chip_hold: float = 0.0
var _flash: float = 0.0
var _heal_pop: float = 0.0
var _phase: float = 0.0
## Set by `_draw_hero` / `_draw` every frame: did a bar actually get painted over this
## fighter's head. Read by `draws_head_bar()`; see the note there for why it is a
## record of the draw rather than a restatement of the condition.
var _drew_head_bar: bool = false

## --- the screen plate ---
var _plate_layer: CanvasLayer = null
var _plate: Control = null
var _dock_right: bool = false
var _plate_clock: float = 0.0
var _plate_next_poll: float = 0.0


## Attach to `target` (read its hp/max_hp) and float the head bar `y_offset` above the
## origin (negative = up, above the head).
##
## ⚠ `show_mp` IS ACCEPTED AND IGNORED. See the mana block in the header: nothing in
## the game spends mana, so the bar it used to draw was a constant. The parameter
## survives because `Hero.gd:1820` passes it and this file does not own that call site.
func configure(target: Node, show_mp: bool = false, y_offset: float = -24.0) -> void:
	_target = target
	_show_mp = show_mp
	position = Vector2(0.0, y_offset)
	# ⚠ ABOVE THE DAMAGE NUMBERS, WHICH IT WAS NOT. This was 30 while
	# `DamageNumber` spawned at 60, so a number could sit on top of the bar it was
	# explaining. The bar is the persistent readout; the number is a garnish that
	# lives 0.7s. See HudStyle.Z_CHARACTER_BARS.
	z_index = HudStyle.Z_CHARACTER_BARS  # above the rig, the aura and the numbers
	# ⚠ GROUP MEMBERSHIP, not a new parameter. `Hero.gd` and `Enemy.gd` own the two
	# call sites and neither can be edited from here, so hero mode has to be something
	# this node can work out for itself. `"hero"` is the identity group ~40 places
	# already read (see `GhostForm.enter`'s note on why it is never dropped), which
	# makes it the one answer that cannot drift.
	_is_hero = target != null and target.is_in_group(&"hero")


# ══════════════════════════════════════════════════════════════ the public seam
## True once this fighter's health is being drawn on the SCREEN instead of over its
## head. Public so a test can assert the move happened without reading a private member.
func has_plate() -> bool:
	return _plate != null


## Where the plate is **on the screen the player is looking at**. `Rect2()` when there
## is none.
##
## ⚠ NOT `get_global_rect()`, AND THIS WAS CAUGHT BY A DELIBERATE REVERT RATHER THAN BY
## REVIEW. A `Control`'s global rect is its rect in ITS OWN CANVAS — for a control on a
## `CanvasLayer` that is screen space, but for one parented into world space it is WORLD
## space, and the two report the same numbers for a plate positioned off the viewport
## size. So the zoom-immunity suite passed unchanged when the plate was moved off the
## CanvasLayer and back under the Node2D — i.e. it passed on the exact regression it
## exists to catch. `get_global_transform_with_canvas()` folds in the canvas transform,
## which is where the camera lives, so this is the rect the VIEWER gets: identity for a
## layer, camera-dragged and camera-scaled for anything in the world.
func plate_rect() -> Rect2:
	if _plate == null:
		return Rect2()
	var xf: Transform2D = _plate.get_global_transform_with_canvas()
	return Rect2(xf.origin, _plate.size * xf.get_scale())


## True while a bar is still being drawn over this fighter's HEAD. A plated player must
## report FALSE — that is the maker's ask, stated as something measurable.
##
## ⚠ IT REPORTS WHAT `_draw` DID, NOT WHAT `_draw` OUGHT TO DO. Written the obvious way
## — `return _has_hp and not _ringout and _plate == null` — this is a second copy of the
## decision `_draw_hero` makes, and a suite reading it would keep passing while somebody
## deleted the early return that actually skips the draw. A flag set inside the draw is
## the only version that fails when the drawing changes. (A caller can tell the channel
## is live rather than merely quiet, because an UNDRIVEN fighter must report true — see
## `_test_undriven_keeps_head_bar`.)
func draws_head_bar() -> bool:
	return _drew_head_bar


## Whether any mana is drawn, anywhere, by anything this node owns. Permanently false;
## it exists so the removal is pinned by a test rather than by a comment — which is
## precisely how the old bar survived (see the mana block in the header: two files
## carried a comment saying it was not drawn, while it was).
func draws_mana() -> bool:
	return false


## Which corner the plate is in. Mirrors this fighter's own `AbilityBar.dock_right`.
func plate_docks_right() -> bool:
	return _dock_right


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		visible = false
		_set_plate_visible(false)
		return
	_phase += delta
	# Sandbox Smash: show the accrued damage % (rising, warm->red) instead of HP.
	_ringout = _is_ringout_mode()
	if _ringout:
		# ⚠ THE % STAYS ON THE BODY. Ring-out is Smash's model and Smash's readout is
		# per-fighter and positional: the number is not "your health", it is "how far
		# THIS body will fly", and a corner plate cannot say that about four fighters.
		_set_plate_visible(false)
		var pct: Variant = _target.get("damage_pct")
		_pct = float(pct) if pct != null else 0.0
		queue_redraw()
		return
	var max_hp: Variant = _target.get("max_hp")
	var hp: Variant = _target.get("hp")
	if max_hp != null and hp != null and int(max_hp) > 0:
		_set_hp_ratio(clampf(float(hp) / float(max_hp), 0.0, 1.0), delta)
		_has_hp = true
	if _is_hero:
		_tick_plate(delta)
	queue_redraw()


## Fold a fresh reading in, and run the chip/flash/heal clocks off the DELTA between
## readings. Derived from the polled ratio rather than from `health_changed` on
## purpose: the signal also fires on heals, on class config, on the round reset and
## on `_die` (which reports 0 and then heals straight back) — a chip bar driven by it
## would flash on all five. The difference between two polls is only ever the thing
## that actually happened to the bar.
func _set_hp_ratio(now: float, delta: float) -> void:
	if not _is_hero:
		_hp_ratio = now
		return
	if now < _hp_ratio - 0.0005:
		_flash = FLASH_TIME
		_chip_hold = CHIP_HOLD          # the ghost stays where the bar WAS
	elif now > _hp_ratio + 0.0005:
		_heal_pop = HEAL_TIME
		_chip_ratio = maxf(_chip_ratio, now)   # never let the ghost sit BELOW the fill
	_hp_ratio = now
	_flash = maxf(_flash - delta, 0.0)
	_heal_pop = maxf(_heal_pop - delta, 0.0)
	if _chip_hold > 0.0:
		_chip_hold -= delta
	else:
		_chip_ratio = maxf(_chip_ratio - CHIP_DRAIN * delta, _hp_ratio)
	_chip_ratio = maxf(_chip_ratio, _hp_ratio)


# ═══════════════════════════════════════════════════════════════ THE HERO PLATE
## Look for this fighter's hotbar until one turns up (or the window closes), then keep
## the plate's geometry current. Geometry is recomputed every frame rather than cached,
## because `AbilityBar.slot_scale()` reads `DisplayServer.is_touchscreen_available()`
## and the viewport is resizable — the bottom strip this sits on is not a constant.
func _tick_plate(delta: float) -> void:
	if _plate == null:
		if _plate_clock > PLATE_WINDOW:
			return
		_plate_clock += delta
		_plate_next_poll -= delta
		if _plate_next_poll > 0.0:
			return
		_plate_next_poll = PLATE_POLL
		_resolve_plate()
		if _plate == null:
			return
	_set_plate_visible(is_visible_in_tree())
	_layout_plate()
	_plate.queue_redraw()


## Find the `AbilityBar` bound to THIS fighter and, if there is one, build the plate in
## the corner that bar docks to.
##
## ⚠ BOUND, NOT NEAREST, NOT FIRST. `AbilityBar` itself learned `bound_hero` because
## `get_first_node_in_group("hero")` had it drawing player one's cooldowns to BOTH
## players in local co-op — "which is worse than no bar at all, because it looks right"
## (`LocalCoop.gd:419`). A plate that picked its hotbar by proximity or by tree order
## would reintroduce exactly that bug, one HUD element to the left.
func _resolve_plate() -> void:
	var bar: Node = _find_bound_ability_bar()
	if bar == null:
		return
	_dock_right = bool(bar.get(&"dock_right"))
	_plate_layer = CanvasLayer.new()
	# The persistent player rung — the same one the hotbar and the pause button are on.
	_plate_layer.layer = HudStyle.LAYER_HUD
	add_child(_plate_layer)
	_plate = Control.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⚠ THE `draw` SIGNAL, NOT A SECOND SCRIPT. A `Control` needs a `_draw` to paint,
	# and giving it one would mean a second file for a widget that has no state of its
	# own — every value it paints is already a member of this node. `CanvasItem.draw`
	# fires inside that item's own draw pass, so `_plate.draw_rect(...)` from the
	# handler paints into the plate, in the plate's local space, exactly as a `_draw`
	# override would.
	_plate.draw.connect(_draw_plate)
	_plate_layer.add_child(_plate)
	_layout_plate()


## Walk the CanvasLayers under the scene root for an `AbilityBar` whose `bound_hero` is
## our target. Restricted to CanvasLayer subtrees because that is where every hotbar in
## the project lives (`Arena` and `LocalCoop._build_bar_for` each build one inside a
## fresh layer), and a full scene walk during a fight, four times a second, is a walk
## over the whole arena.
func _find_bound_ability_bar() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	for child: Node in tree.root.get_children():
		if child is CanvasLayer:
			var found: Node = _search_for_bound_bar(child)
			if found != null:
				return found
	return null


func _search_for_bound_bar(from: Node) -> Node:
	if from is AbilityBar and from.get(&"bound_hero") == _target:
		return from
	for child: Node in from.get_children():
		var found: Node = _search_for_bound_bar(child)
		if found != null:
			return found
	return null


## Put the plate where `HudStyle.hero_plate_rect` says, for the viewport we actually
## have and for however much of the bottom this player's own hotbar has taken.
func _layout_plate() -> void:
	if _plate == null:
		return
	var view: Vector2 = _plate.get_viewport_rect().size
	var r: Rect2 = HudStyle.hero_plate_rect(view, _dock_right, _hotbar_reserved_height())
	_plate.position = r.position
	_plate.size = r.size


## How far up from the bottom edge this player's hotbar reaches. `occupied_height()` is
## the published height of one hotbar (`AbilityBar` exposes it because `CombatCamera`
## needed the same number and had been carrying a stale copy of the arithmetic);
## `dock_row` stacks players three and four upward off their own side, and the plate has
## to clear whichever row is actually theirs rather than the bottom one.
func _hotbar_reserved_height() -> float:
	var h: float = AbilityBar.occupied_height()
	var bar: Node = _find_bound_ability_bar()
	if bar != null:
		var row: int = int(bar.get(&"dock_row"))
		if row > 0:
			# `AbilityBar._draw`: each row above the first lifts by `slot_px + 8*k`.
			h += float(row) * (AbilityBar.SLOT_SIZE + 8.0) * AbilityBar.slot_scale()
	return h


## ⚠ A `CanvasLayer` DOES NOT INHERIT ITS PARENT'S VISIBILITY. `BotMatch` hides every
## fighter's bars with `(c as CharacterBars).visible = false` (BotMatch.gd:957) because
## a match draws its own fixed plates instead — and a layer parented to this node would
## have sailed straight through that and stacked a tower plate on top of the match's.
## The same is true of `_process`'s "the target is gone" branch.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_set_plate_visible(is_visible_in_tree())


func _set_plate_visible(v: bool) -> void:
	if _plate_layer != null and _plate_layer.visible != v:
		_plate_layer.visible = v


## The plate itself. Screen pixels throughout — **no `ui_scale`, deliberately**: this is
## on a `CanvasLayer`, the camera does not transform it, and multiplying by a zoom
## compensation here would make a fixed HUD element start breathing with the camera,
## which is the exact bug the move was made to delete.
func _draw_plate() -> void:
	if _plate == null or not _has_hp:
		return
	var w: float = _plate.size.x
	var h: float = _plate.size.y
	var at := Vector2.ZERO
	var pad: float = HudStyle.HERO_PLATE_FRAME
	var low: bool = _hp_ratio <= LOW_FRACTION
	var fill: Color = HudStyle.hp_color(_hp_ratio)
	if low:
		# The danger pulse rides the FILL, not just the frame: a bar that is both
		# short and beating is unmistakable in peripheral vision.
		fill = fill.lerp(HudStyle.CHALK, 0.20 + 0.20 * sin(_phase * 7.0))
	# A fat dark frame — the plate has to survive being drawn over a lit floor, and a
	# 1px outline at this size disappears into the post-process grade.
	_plate.draw_rect(Rect2(at - Vector2(pad, pad),
		Vector2(w, h) + Vector2(pad, pad) * 2.0), HudStyle.frame())
	_plate.draw_rect(Rect2(at, Vector2(w, h)), HudStyle.TRACK)
	# 1. THE CHIP — what you just lost, still on screen a beat later.
	if _chip_ratio > _hp_ratio:
		_plate.draw_rect(Rect2(at + Vector2(w * _hp_ratio, 0.0),
			Vector2(w * (_chip_ratio - _hp_ratio), h)), CHIP_COLOR)
	# 2. THE FILL.
	if _hp_ratio > 0.0:
		_plate.draw_rect(Rect2(at, Vector2(w * _hp_ratio, h)), fill)
	# 3. THE HIT FLASH — the whole fill whitens for a frame or two.
	if _flash > 0.0:
		var a: float = (_flash / FLASH_TIME) * 0.75
		_plate.draw_rect(Rect2(at, Vector2(w, h)), HudStyle.with_a(HudStyle.CHALK, a))
	# 4. SEGMENT TICKS, cut through everything above so the shape survives any fill.
	for i: int in range(1, HudStyle.HERO_PLATE_SEGMENTS):
		var tx: float = at.x + w * (float(i) / float(HudStyle.HERO_PLATE_SEGMENTS))
		_plate.draw_rect(Rect2(Vector2(tx - 0.5, at.y), Vector2(1.0, h)),
			HudStyle.ink(0.55))
	# 5. THE HEAL POP — a green rim, so a health pack landing is as loud as a hit.
	if _heal_pop > 0.0:
		var g: float = _heal_pop / HEAL_TIME
		_plate.draw_rect(Rect2(at - Vector2(pad, pad) * 0.5,
			Vector2(w, h) + Vector2(pad, pad)),
			HudStyle.with_a(HEAL_RIM, g * 0.85), false, pad)


# ══════════════════════════════════════════════════════ the body-attached half
## The multiplier that keeps this node's WORLD geometry a constant size ON SCREEN. See
## the ONE ZOOM RULE block in `HudStyle` for the arithmetic and the measurements. It
## applies to the enemy bar, the un-plated head bar and the ring-out % — and to nothing
## on the plate, which has no camera between it and the screen.
func _ui_scale() -> float:
	return HudStyle.ui_scale(self)


func _draw() -> void:
	_drew_head_bar = false
	if _ringout:
		_draw_pct()
		return
	if not _has_hp:
		return
	if _is_hero:
		_draw_hero()
		return
	# The enemy bar. Same geometry it has always had at the reference zoom; the
	# only change is that it now holds that size when the camera moves.
	var ui: float = _ui_scale()
	var w: float = WIDTH * ui
	_bar(Vector2(-w * 0.5, 0.0), w, HP_H * ui, _hp_ratio,
		HudStyle.hp_color(_hp_ratio), ui)
	_drew_head_bar = true


## What a hero draws ON ITS OWN BODY.
##
## With a plate, that is the danger ring and nothing else — the ring is not a readout,
## it is a shape around the figure, and it is what makes moving the bar to a corner cost
## the player nothing at the moment it matters.
##
## Without a plate (a bot ally, a remote peer, the frame or two before the hotbar
## exists) the old head bar is still the only thing saying how that body is doing, so it
## is still drawn.
func _draw_hero() -> void:
	if _hp_ratio <= LOW_FRACTION:
		_draw_danger()
	if _plate != null:
		return
	var ui: float = _ui_scale()
	var w: float = HERO_WIDTH * ui
	var h: float = HERO_HP_H * ui
	# ⚠ ANCHORED OFF THE SCALED HEIGHT. This used to read `HP_H - h` — an UNSCALED
	# constant minus a scaled one — so the bar's lower edge crept as the camera moved,
	# which is the one thing a bottom-anchored bar exists to prevent.
	_bar(Vector2(-w * 0.5, HP_H * ui - h), w, h, _hp_ratio,
		HudStyle.hp_color(_hp_ratio), ui)
	_drew_head_bar = true


## The last-legs read, drawn ON THE BODY. Two breathing arcs at the hero's feet —
## where the player's eyes already are.
##
## `-position.y` puts this back at the hero's own origin: `configure` offsets this
## node upward, and the ring must not travel with the bar.
## ⚠ THE ONE PIECE OF THIS FILE THAT IS HONESTLY WORLD-SPACE, and the line that
## decides it is: **a READOUT is zoom-compensated, a piece of BODY DECORATION is
## not.** The bars, the numbers and the % are things you read, so they hold a
## constant on-screen size. This ring is not read — it is a shape drawn AROUND the
## hero's feet, and a ring whose radius is pinned to the screen slides off the body
## the moment the camera moves. At the camera's tight end a compensated ring would
## have a smaller radius than the figure standing inside it.
func _draw_danger() -> void:
	var beat: float = 0.5 + 0.5 * sin(_phase * 6.0)
	# Deeper as the bar empties, so the ring is not a binary "you are low" but a dial.
	var urgency: float = clampf(1.0 - _hp_ratio / maxf(LOW_FRACTION, 0.01), 0.0, 1.0)
	var at := Vector2(0.0, -position.y + RING_FEET_DROP)
	var r: float = RING_RADIUS * (0.88 + 0.14 * beat)
	var a: float = (0.22 + 0.30 * urgency) * (0.55 + 0.45 * beat)
	draw_arc(at, r, 0.0, TAU, 30, HudStyle.with_a(RING_COLOR, a), 2.4, true)
	draw_arc(at, r * 0.6, 0.0, TAU, 24, HudStyle.with_a(RING_COLOR, a * 0.5), 1.4, true)


## Smash readout: a warm->red fill that grows with % + the number itself climbing
## over the head. The fill saturates at PCT_VISUAL_MAX; the number never caps.
func _draw_pct() -> void:
	# ⚠ THE READOUT ON THIS NODE USED TO BE THE ONLY UNCOMPENSATED THING ON IT: the
	# bar above was fully zoom-corrected and the number was drawn at a flat font 11
	# in WORLD units, so it ran 5 screen px at the camera's wide end and 29 at its
	# tight one — on the same node, in the same frame, as a bar that did not move.
	var ui: float = _ui_scale()
	var w: float = WIDTH * ui
	var x: float = -w * 0.5
	var ratio: float = clampf(_pct / PCT_VISUAL_MAX, 0.0, 1.0)
	var col: Color = PCT_WARM.lerp(PCT_RED, ratio)
	_bar(Vector2(x, 0.0), w, HP_H * ui, ratio, col, ui)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	# ⚠ CAPPED AT FOUR CHARACTERS. `"%d%%"` was uncapped into a 30px-wide draw box:
	# "1000%" was exactly clipped and "1234%" lost its last digit, which is worse
	# than saturating because a truncated number is a WRONG number, silently. Past
	# 999 the exact figure stops being information anyway — you are being launched
	# either way — so it saturates and says so.
	var shown: int = int(round(_pct))
	var label: String = "999+%" if shown > 999 else "%d%%" % shown
	var fs: int = int(round(float(HudStyle.SMALL) * ui))
	# Sit the number just above the bar, colour-matched to the fill, dark-outlined.
	var pos := Vector2(x, -3.0 * ui)
	draw_string_outline(font, pos + Vector2(0.0, -ui), label,
		HORIZONTAL_ALIGNMENT_CENTER, w, fs, HudStyle.outline_for(fs), HudStyle.ink(0.95))
	draw_string(font, pos + Vector2(0.0, -ui), label,
		HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


## True when the sandbox ring-out model is active (GameState.ringout_mode).
func _is_ringout_mode() -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	return gs != null and bool(gs.get("ringout_mode"))


## One WORLD-SPACE bar: frame, track, then a fill of `ratio` width. `ui` is the zoom
## compensation, applied to the FRAME as well as the bar — it was a hardcoded 1.0px,
## which is why the hero's head bar used to carry a hairline frame directly under a
## 2–4.8px one.
func _bar(pos: Vector2, w: float, h: float, ratio: float, fill: Color,
		ui: float = 1.0) -> void:
	var pad: float = HudStyle.frame_pad(ui)
	draw_rect(Rect2(pos - Vector2(pad, pad), Vector2(w + pad * 2.0, h + pad * 2.0)),
		HudStyle.frame())
	draw_rect(Rect2(pos, Vector2(w, h)), HudStyle.TRACK)
	if ratio > 0.0:
		draw_rect(Rect2(pos, Vector2(w * ratio, h)), fill)


## The three-stop HP ramp — green (full) -> gold (half) -> red (low) — lives in
## `HudStyle.hp_color`, so the bar and the rest of the HUD cannot drift apart.
