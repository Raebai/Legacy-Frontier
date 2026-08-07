class_name GravityFlip
extends Node2D
## GRAVITY WELL — the Juggernaut's carried CONTROL slot (`SpellLibrary.CLASS_KITS[3]`).
## A cylinder of inverted gravity dropped on a spot. Inside it you keep every verb you
## had; what you lose is the floor. Then it lets go, and your HEIGHT is the bill.
##
## ⚠ THIS FILE ARGUED THE OPPOSITE UNTIL 2026-08-05 AND THE MAKER OVERTURNED IT.
## The old header read: *"there is no `radius` because there is no edge — reaching for
## the arena wall to get out from under it would make this a zone, and a zone is a
## completely different (and much safer) spell."* The ruling was: *"gravity flip should
## let you move freely inside the gravity radius while it is working."* That sentence
## contains a radius. The old reasoning is REPLACED rather than softened, so the file
## does not contradict its own numbers.
##
## WHY THE EDGE MAKES IT BETTER AND NOT SAFER — MEASURED, not argued. On the shipping
## room (1160x540, wall collider at y=0) with the shipping numbers, a body standing on
## the floor reaches the ceiling in **1.22 s and then spends 3.78 s — 76% of the spell —
## pinned against it.** The roomwide version had exactly one decision in it (when to
## press) and then four seconds in which nobody, caster included, could do anything. The
## well gives the button a WHERE as well as a WHEN, gives everyone inside something to
## do, and gives everyone outside a reason to care about a line on the floor.
##
## THE THREE BEATS:
##   ENTER    a real radius, read from `SpellDef.radius` — which this file used to leave
##            at the class default of 90 and never read. Capture is HYSTERETIC: caught
##            at `_radius`, released only at `_radius + EXIT_MARGIN`, so a body walking
##            the rim cannot strobe once per frame.
##   FLOAT    free movement. Horizontal input, dash, cast and melee ALREADY worked —
##            this field only ever wrote `velocity.y`. What is NEW is that a caught body
##            keeps GROUND-grade steering while airborne: losing the floor otherwise
##            costs 44% of your authority (AIR_ACCEL 1450 vs GROUND_ACCEL 2600).
##   COLLAPSE the field lets go and the drop is charged for. Damage scales from nothing
##            below `COLLAPSE_FLOOR` to the authored damage at the cap, and the landing
##            staggers. THAT is what makes free movement a skill rather than a holiday:
##            the five seconds are yours to spend getting LOW, getting OUT past the rim,
##            or shoving somebody else UP.
##
## ⚠ THIS SPELL DEALT ZERO DAMAGE BEFORE TODAY. The old header promised "the pile-up is
## the payoff"; the old `_end()` stopped pushing and freed itself, and nothing anywhere
## turned a fall into a number. The prose was the feature.
##
## ⚠ HOW THE INVERSION WORKS — unchanged. `Hero.GRAVITY` / `Enemy.GRAVITY` are consts in
## files this does not own and there is no global gravity, so the field OVERPOWERS
## gravity from outside. `slice_test_tier_spells` pins `LIFT` above the larger of the
## two so drift fails loudly instead of feeling mushy.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.WIND
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## Upward acceleration, px/s^2. Must exceed the heaviest gravity in the game by enough
## that the NET is a clear rise — a body drifting up at 200 px/s reads as broken
## physics, one that is LIFTED reads as a spell. Pinned by a suite.
const LIFT: float = 3400.0
const MAX_RISE: float = 520.0

## ---------------------------------------------------------------- THE CYLINDER
## Fallback when no SpellDef was handed over (a capture tool, a bare `.new()` in a
## test). A little over half the room's half-width: big enough to swallow a knot of
## three, small enough that "get out" is a real answer at Hero.SPEED 210 (~1.5 s from
## the centre to the rim). UNTESTED FEEL GUESS.
const RADIUS: float = 320.0
## Hysteresis — caught at `_radius`, released at `_radius + EXIT_MARGIN`. About one body
## width, so a body pacing the rim cannot flicker between ground- and air-grade steering
## every frame, which with a control grant is a visible stutter rather than a cosmetic.
const EXIT_MARGIN: float = 34.0
## How far above the anchor the lid sits. Deliberately SHORTER than the room, or a low
## floor and a tall floor are different spells. Also the reference for full damage.
const CEILING_LIFT: float = 260.0
## The lift tapers to nothing across this band below the cap, so a body ARRIVES and
## hovers instead of being smeared into the ceiling.
const SETTLE_BAND: float = 44.0
const CATCH_BELOW: float = 48.0
const CATCH_ABOVE: float = 64.0

## ------------------------------------------------------------------ THE COLLAPSE
## Drop below which the landing is FREE. This constant IS the skill expression: five
## seconds is plenty of time to get under it, and a body that spends them getting low
## pays nothing.
const COLLAPSE_FLOOR: float = 90.0
## How long we keep watching for landings. The longest fall the cap can produce is
## 0.50 s; the longest the room can is 0.75 s.
const COLLAPSE_WATCH: float = 1.4
## ⚠ NOW REDUNDANT BUT KEPT AS THE EXPLICIT STATEMENT. The maker ruled the caster out
## of the spell entirely ("gravity spell should affect everyone except the caster"), so
## the caster is never lifted and therefore never in `_watch` to be billed. This stays
## FALSE and stays declared, because "the caster is not hurt by their own well" is a
## rule worth being able to find, and flipping it alone would now do nothing — the
## exclusion lives in `_lift_everyone`. ⚠ A CO-OP PARTNER IS STILL CAUGHT AND STILL
## BILLED: "everyone except the caster" means everyone.
const CASTER_EATS_COLLAPSE: bool = false
## The landing stun, reusing the EARTH stagger channel exactly as ShadowRoot does for
## its root. On an Enemy that is a hard CC; on a Hero it is a 0.32x slow for 0.70 s — a
## stagger, not a lock. Stated plainly so nobody reads "stun" and expects one.
const LANDING_STUN_ELEMENT: int = Elements.Element.EARTH

const WARN_TIME: float = 0.8
## Motes drifting up INSIDE the well. Confined to the footprint now — the old
## `MOTE_SPAN` was 1100x620, i.e. the whole room, which drew a boundary that did not
## exist and hid the one that did.
const MOTES: int = 34
const RIBS: int = 15

var _life: float = 5.0
var _elapsed: float = 0.0
var _color: Color = Color(0.55, 0.95, 0.9)
var _center: Vector2 = Vector2.ZERO
var _anchor: Vector2 = Vector2.ZERO
var _ceiling_y: float = -CEILING_LIFT
var _radius: float = RADIUS
var _exit_radius: float = RADIUS + EXIT_MARGIN
var _damage: int = 0
var _seed: int = 0
## Which of the held ids is the CASTER — it gets the zone fact but never the lift or
## the control grant, so its release must not decrement a count it never incremented.
var _caster_ids: Dictionary = {}
## instance_id -> Node2D. Every id in here has had `enter_grav_zone()` called once,
## and `enter_grav_field()` too unless it is in `_caster_ids`.
var _held: Dictionary = {}
var _collapsing: bool = false
var _collapse_t: float = 0.0
var _watch: Array[Dictionary] = []
var _ground_sigil: MagicCircle = null


## ⚠ `target` IS NOW READ. It used to be `_target` — underscored, discarded — while
## `SpellCaster`'s HEX arm has always computed `caster_pos + aim` clamped to
## `spell.reach` and handed it over. PLACED-AT-AIM, and the reason is the reversal
## itself: a zone whose edge always sits on its caster has no placement decision,
## because "am I inside?" is permanently yes. Placed, the Juggernaut chooses — drop it
## ON the pack and stand out on the rim, or drop it on himself to swallow a charge.
func hex(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_life = maxf(spell.length, 0.5)
	_color = color
	_damage = maxi(spell.damage, 0)
	_radius = maxf(spell.radius, 60.0)
	_exit_radius = _radius + EXIT_MARGIN
	_center = target
	# Dropped onto the floor beneath the aim point, so the anchor lies on the ground on
	# a ledge or a slope instead of hanging. `floor_point` returns its input unchanged
	# when there is no floor (and headless, where there is no physics world at all),
	# which is the conservative direction.
	_anchor = SpellWorld.floor_point(target, SpellWorld.FLOOR_PROBE, [], self)
	_ceiling_y = _anchor.y - CEILING_LIFT
	_seed = randi()
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	# THE GROUND ANCHOR — the signature circle, laid flat, scaled to the well's real
	# footprint rather than to its cost shelf. `hold = 0` because this one lives as long
	# as the field does; `_end()` closes it. The old call passed 0.5, which bloomed the
	# circle out at half a second and left 4.5 s of unmarked zone.
	var shelf: float = maxf(SpellSigil.radius_for(spell_tier), 1.0)
	_ground_sigil = SpellSigil.open(self, _anchor, color, _radius / shelf,
		false, Vector2.UP, true, 0.16, 0.0)
	SpellDrops.sfx("levitate", -1.0, 0.12, 0.7)
	Juice.zoom_pull_camera(0.2, _life * 0.5, 0.25, 0.7)   # pull back: the room matters now
	Juice.shake_camera(5.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _collapsing:
		_collapse_t += delta
		_watch_landings()
		queue_redraw()
		if _watch.is_empty() or _collapse_t >= COLLAPSE_WATCH:
			queue_free()
		return
	_elapsed += delta
	if _elapsed >= _life:
		_end()
		return
	_lift_everyone(delta)
	queue_redraw()


## THE MECHANIC.
##
## ⚠ THE CASTER IS EXCLUDED — FROM THE LIFT AS WELL AS THE COLLAPSE. Maker, 2026-08-05:
## *"gravity spell should affect everyone except the caster."*
##
## This overturns the ONE piece of the old design that survived the well reversal. The
## original spec said "inverts gravity 5s, CASTER INCLUDED", and this file scanned its
## group bare on purpose — it was the single effect in the drop set that reached its
## own thrower, and `slice_test_friendly_fire`'s EXEMPT table named it for exactly that.
## That is no longer the design.
##
## And it is the right call for the well specifically, which is worth writing down
## rather than just obeying: "caster included" made sense when the spell was roomwide
## and had no edge, because there was nowhere to stand — being caught by your own flip
## was the cost of casting it. The well is PLACED, so the Juggernaut already chooses
## whether to be inside it; lifting the caster on top of that charges twice for one
## decision, and it made the obvious play (drop it on the pack, stay on the rim) also
## the only play.
##
## A CO-OP PARTNER IS STILL CAUGHT. "Everyone except the caster" means everyone.
func _lift_everyone(delta: float) -> void:
	var seen: Dictionary = {}
	var own: Object = SpellTargets.owner_of(self)
	var skip: int = own.get_instance_id() if own != null else 0
	for n: Node in get_tree().get_nodes_in_group(target_group):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		# ⚠ THE CASTER IS NO LONGER SKIPPED OUTRIGHT — it is skipped from the LIFT and
		# from the control grant, which is the policy above, but it is still tracked as
		# being INSIDE THE WELL. Maker, correcting me: *"no as in the caster of gravity
		# well can fly in the gravity well area"*.
		#
		# My first fix keyed the no-upward-dash rule on `Hero.grav_fields`, which is
		# incremented by `_capture` — and this `continue` meant the caster never
		# reached `_capture`, so the caster's count stayed at zero and the rule never
		# applied to the one body that was actually flying. Exactly the wrong half.
		#
		# The zone count below is a SEPARATE, weaker fact: "you are standing in a
		# gravity well", with none of the ground-accel steering `grav_fields` grants.
		# It changes nothing about who gets lifted and nothing about who can steer.
		var is_caster: bool = n.get_instance_id() == skip
		var v: Variant = n.get(&"velocity")
		if v == null or not (v is Vector2):
			continue   # not a moving body — nothing to invert
		var body: Node2D = n as Node2D
		if body == null:
			continue
		var id: int = body.get_instance_id()
		var was_held: bool = _held.has(id)
		seen[id] = true
		if not _inside(body.global_position, was_held):
			if was_held:
				_release(body)
				_held.erase(id)
			continue
		if not was_held:
			_held[id] = body
			if is_caster:
				_caster_ids[id] = true
			_capture(body, is_caster)
		if is_caster:
			continue   # no lift for the caster — that policy is unchanged
		var vel: Vector2 = v as Vector2
		# THE CAP. Both the acceleration and the terminal speed taper across
		# SETTLE_BAND, so a body reaches the lid and hovers under it. Without the taper
		# on MAX_RISE too, a body at the cap still carries 520 px/s of intent and
		# jitters against the ceiling.
		var head: float = body.global_position.y - _ceiling_y
		var taper: float = clampf(head / SETTLE_BAND, 0.0, 1.0)
		vel.y = maxf(vel.y - LIFT * taper * delta, -MAX_RISE * taper)
		body.set(&"velocity", vel)
	# Anyone who left the group entirely (died, despawned) still owes a release, or
	# their control grant leaks forever.
	for id: int in _held.keys():
		if seen.has(id):
			continue
		var b: Variant = _held[id]
		if b is Node2D and is_instance_valid(b as Node2D):
			_release(b as Node2D)
		_held.erase(id)


## A CYLINDER, not a sphere: horizontal band plus generous vertical slack. Same ruling
## `ShadowRoot` makes about its column — a bounding circle would reach ground a body
## standing there would not be caught on. `already` selects the wider release radius.
func _inside(pos: Vector2, already: bool) -> bool:
	var r: float = _exit_radius if already else _radius
	if absf(pos.x - _anchor.x) > r:
		return false
	return pos.y <= _anchor.y + CATCH_BELOW and pos.y >= _ceiling_y - CATCH_ABOVE


## FREE MOVEMENT, the half that was actually missing. Duck-typed: `Hero` answers,
## `Enemy` does not, and neither does a test stub — all three correct. An enemy has no
## air-accel penalty to lift (it is driven by its AI, not a stick), so there is nothing
## to give it, and saying so is better than pretending the grant is universal.
## TWO FACTS, NOT ONE, and the caster gets only the weaker of them.
##
##   `enter_grav_field` — "you are being held up by this, and you may steer as if
##                        planted". Lift plus ground-grade air control. NOT the caster.
##   `enter_grav_zone`  — "you are standing inside a gravity well". Nothing else.
##                        Everyone, caster included, and it is what stops a body
##                        staircasing out on dashes. See `Hero.grav_zones`.
##
## They were one call, which is why the maker's *"the caster of gravity well can fly
## in the gravity well area"* survived the first fix: the caster was excluded from
## `_capture` entirely, so the no-upward-dash rule keyed on `grav_fields` never
## applied to the one body that was flying.
func _capture(body: Node2D, caster: bool) -> void:
	if body.has_method(&"enter_grav_zone"):
		body.call(&"enter_grav_zone")
	if not caster and body.has_method(&"enter_grav_field"):
		body.call(&"enter_grav_field")


func _release(body: Node2D) -> void:
	if body.has_method(&"exit_grav_zone"):
		body.call(&"exit_grav_zone")
	# ⚠ ONLY IF IT WAS GRANTED. `Hero.exit_grav_field` floors at zero, so an unmatched
	# release looks harmless on its own — but with TWO overlapping wells it would
	# decrement a count this well never incremented and free a body the OTHER well is
	# still holding. Tracked rather than clamped, for that reason.
	if not _caster_ids.has(body.get_instance_id()) and body.has_method(&"exit_grav_field"):
		body.call(&"exit_grav_field")
	_caster_ids.erase(body.get_instance_id())


## Gravity comes back and the bill arrives.
##
## ⚠ WHO IS BILLED. The caster is skipped unless `CASTER_EATS_COLLAPSE`, via
## `SpellTargets.owner_of(self)` — the same predicate `hostiles()` uses, applied to this
## file's own tracked set rather than to a group scan.
##
## ⚠ A CO-OP PARTNER **IS** BILLED, and that is not an oversight. Under friendly fire
## `SpellCaster.damage_group` stamps the shared `mortal` group, so a partner is in
## everything; excluding them would make this the only spell in the game with a
## team-shaped hole in it, and the lift has always caught them anyway. The new part is
## that catching them now costs health. THIS IS THE SHARPEST EDGE THIS CHANGE ADDS and
## it deserves the maker's eye on playtest.
func _end() -> void:
	_collapsing = true
	_collapse_t = 0.0
	var blocked: int = 0
	var own: Object = SpellTargets.owner_of(self)
	if own != null and not CASTER_EATS_COLLAPSE:
		blocked = own.get_instance_id()
	for id: int in _held.keys():
		var b: Variant = _held[id]
		if not (b is Node2D) or not is_instance_valid(b as Node2D):
			continue
		var body: Node2D = b as Node2D
		_release(body)
		if id == blocked:
			continue
		_watch.append({"node": body, "from_y": body.global_position.y})
	_held.clear()
	SpellSigil.close(_ground_sigil)
	_ground_sigil = null
	CombatVfx.spawn_burst(get_parent(), _center, Color(_color.r, _color.g, _color.b, 0.7),
		Color(_color.r, _color.g, _color.b, 0.0), 18, 0.5, 60.0, 220.0, 1.2, 3.2)
	Juice.shake_camera(8.0)
	SpellDrops.sfx("rx_ground_out", -4.0, 0.1, 0.6)


## ⚠ DUCK-TYPED ON `is_on_floor`, WITH A TIMER BACKSTOP. Hero and Enemy are both
## CharacterBody2D and answer it; a test stub does NOT, and a body that never lands —
## killed mid-air, standing on a crate that shattered under it — must still be settled
## up rather than watched forever. On expiry the drop is measured to wherever it got to,
## which UNDER-bills rather than over-bills: the conservative direction for a brand-new
## damage path.
func _watch_landings() -> void:
	var expired: bool = _collapse_t >= COLLAPSE_WATCH
	for i: int in range(_watch.size() - 1, -1, -1):
		var e: Dictionary = _watch[i]
		var b: Variant = e["node"]
		if not (b is Node2D) or not is_instance_valid(b as Node2D) \
				or (b as Node2D).is_queued_for_deletion():
			_watch.remove_at(i)
			continue
		var body: Node2D = b as Node2D
		var landed: bool = expired
		if not landed and body.has_method(&"is_on_floor"):
			landed = bool(body.call(&"is_on_floor"))
		if not landed:
			continue
		_land(body, body.global_position.y - float(e["from_y"]))
		_watch.remove_at(i)


## The bill. Linear from nothing at `COLLAPSE_FLOOR` to the full authored damage at the
## cap — one dial, in the data file, no second reference constant.
##
## Routed through `SpellDeflect` deliberately: a player who reads the collapse coming
## and holds the guard has BRACED, and that is a beat worth having. A deflect zeroes the
## damage AND the stun — being staggered by a landing you blocked would make the parry a
## half-answer.
func _land(body: Node2D, drop: float) -> void:
	if drop < COLLAPSE_FLOOR:
		return   # you got low. That was the play; it is supposed to cost nothing.
	var k: float = clampf((drop - COLLAPSE_FLOOR) / maxf(CEILING_LIFT - COLLAPSE_FLOOR, 1.0),
		0.0, 1.0)
	var dmg: int = int(roundf(float(_damage) * k))
	var at: Vector2 = SpellTargets.aim_point(body)
	if dmg > 0:
		dmg = SpellDeflect.resolve(body, dmg, Vector2.DOWN, at)
	if dmg > 0:
		SpellTargets.hurt(body, dmg, Color(_color.r, _color.g, _color.b, 1.0))
		if body.has_method(&"apply_status"):
			body.call(&"apply_status", LANDING_STUN_ELEMENT)
	CombatVfx.spawn_burst(get_parent(), at + Vector2(0.0, 12.0),
		Color(_color.r, _color.g, _color.b, 0.8), Color(_color.r, _color.g, _color.b, 0.0),
		int(6.0 + 12.0 * k), 0.35, 60.0, 90.0 + 220.0 * k, 0.8, 2.4)
	Juice.shake_camera(2.0 + 5.0 * k)


## Freed early (arena teardown, a reaction consuming us) — hand every grant back.
## Without this a hero freed mid-field keeps ground-grade air steering for the rest of
## the run, and it would look like a physics bug rather than a leak.
func _exit_tree() -> void:
	for id: int in _held.keys():
		var b: Variant = _held[id]
		if b is Node2D and is_instance_valid(b as Node2D):
			_release(b as Node2D)
	_held.clear()


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


## THE CYLINDER, DRAWN. Three reads, in the order a player needs them: the two RIMS as
## dashed vertical ribs ("the line is there, and you are on this side of it") — the read
## the old spell had no way to give, because it had no boundary; the MOTES streaming up
## inside the footprint ("and it is working"); and the WARNING in the last `WARN_TIME`
## ("and it is about to stop"), which is now a threat rather than trivia.
func _draw() -> void:
	if _collapsing:
		return   # the field is gone; the burst and the landings carry the beat
	var remaining: float = _life - _elapsed
	var warn: float = clampf(1.0 - remaining / WARN_TIME, 0.0, 1.0)
	var alpha: float = 0.35 + 0.4 * warn
	var top: float = _ceiling_y
	var bot: float = _anchor.y
	var span: float = maxf(bot - top, 1.0)
	var ribs: int = RIBS / 2 if TuningConfig.quality_is_low() else RIBS
	ribs = maxi(ribs, 4)
	var rib_h: float = span / float(ribs)
	var scroll: float = fposmod(_elapsed * 90.0, rib_h * 2.0)
	for side: int in 2:
		var x: float = _anchor.x + (_radius if side == 1 else -_radius)
		for i: int in ribs:
			var y0: float = top + float(i) * rib_h * 2.0 + scroll - rib_h
			var y1: float = y0 + rib_h * (0.55 + 0.25 * warn)
			var a: float = clampf(y0, top, bot)
			var b: float = clampf(y1, top, bot)
			if b - a <= 0.5:
				continue
			# Fades toward the cap so the rim reads as a wall of air, not a fence.
			var f: float = 1.0 - 0.55 * ((bot - a) / span)
			draw_line(Vector2(x, a), Vector2(x, b),
				Color(_color.r, _color.g, _color.b, alpha * f), 2.0 + 1.4 * warn, true)
	for i: int in MOTES:
		var fx: float = _hash01(_seed + i * 131)
		var fy: float = _hash01(_seed + i * 977 + 7)
		var speed: float = 70.0 + 130.0 * _hash01(_seed + i * 53 + 3)
		# Wraps rather than resetting, so the field looks continuous from the frame it
		# opens instead of starting empty.
		var y: float = fposmod(fy * span - _elapsed * speed, span)
		var p := Vector2(_anchor.x - _radius + fx * _radius * 2.0, bot - y)
		var ln: float = 8.0 + 16.0 * warn
		draw_line(p, p + Vector2.UP * ln,
			Color(_color.r, _color.g, _color.b, alpha * (0.4 + 0.6 * fx)), 1.6, true)
