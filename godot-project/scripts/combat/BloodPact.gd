class_name BloodPact
extends Node2D
## BLOOD PACT — Tier 2 floor pickup. Everything you CAST hits far harder, and you
## pay for it in health for as long as it lasts. There is no way to end it early;
## that is the spell.
##
## TWO SEAMS, AND BOTH ARE ONES THIS AGENT OWNS.
##   THE BUFF   — `SpellCaster.cast()` asks `multiplier_for(caster)` before it
##                dispatches and casts a boosted DUPLICATE of the SpellDef. It has
##                to be a duplicate: a SpellDef is a Resource handed out by
##                `SpellLibrary`, and scaling `spell.damage` in place would leave
##                the hero permanently buffed the moment the pact expired.
##   THE COST   — this node bills the caster every second through
##                `SpellTargets.hurt`, which means the drain runs the real damage
##                path. YOU CAN DIE TO YOUR OWN PACT. That is deliberate and it is
##                the only reason the buff is allowed to be as large as it is.
##
## ✔ IT BUFFS MELEE NOW. This block used to read *"IT DOES NOT BUFF MELEE ... if that
## ever changes, the hook is one line in `Hero` calling the same
## `multiplier_for(self)`"*. That line exists: `Hero._on_melee_hit_frame` scales
## `_melee_damage` by `multiplier_for(self, self)` before it is dealt.
##
## It was the single most valuable thing the pact was missing, because the pact is the
## SWORDSAINT's control slot and a damage buff that skipped the sword was a buff the
## class could barely spend. Maker: *"the blood pact needs to be buffed"*.
##
## Scoped to the hit-frame path deliberately: the uppercut, the fire punch and the
## unsheathe cut add `_melee_damage` to their own authored numbers and are not the
## primary the pact is meant to make dangerous.
##
## ⚠ THE PACT IS PER-CASTER, NOT GLOBAL. `multiplier_for` matches on the caster
## instance, so a hero drinking their own pact does not buff their teammate's
## spells — and two pacts on the same body deliberately do NOT stack (the largest
## wins), because stacking a self-damage buff is how a spell becomes a suicide
## button by arithmetic rather than by decision.

## The group every live pact joins, so `multiplier_for` is one group scan and never
## a walk of the whole arena.
const PACT_GROUP: StringName = &"blood_pact"

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.SHADOW
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## Ring drawn at the caster's feet. Deep arterial red against every element palette.
const RING_COLOR: Color = Color(0.85, 0.12, 0.18)
const RING_RADIUS: float = 30.0
## Drip cadence, seconds. Slow enough to read as a heartbeat rather than a leak.
const DRIP_INTERVAL: float = 0.28

var _life: float = 8.0
var _elapsed: float = 0.0
var _mult: float = 1.75
var _drain_per_second: float = 5.0
## Fractional HP owed. Damage is an int, so the drain accumulates and pays whole
## points — otherwise a 5 HP/s drain at 60 fps rounds to zero every single frame
## and the spell costs nothing at all.
var _owed: float = 0.0
var _drip: float = 0.0
var _color: Color = RING_COLOR
## Seconds between settlements. See `_physics_process`: the pact used to bill five
## times a second through the real hurt path, i.e. forty flashes, hit-stops and
## camera shakes across one cast.
const BILL_INTERVAL: float = 0.8
var _bill: float = 0.0
## The aura this body wore before the pact borrowed it. See `_light_the_aura`.
var _had_aura: bool = false
var _prev_aura: Color = Color.WHITE
var _prev_aura_strength: float = 0.0
var _prev_aura_tier: int = 0

## How high above the body the mark floats, and how big it is drawn.
const KANJI_LIFT: float = 62.0
const KANJI_SIZE: float = 15.0

## ══ WHAT THE PACT IS FOR ════════════════════════════════════════════════════════
## Maker: *"what is the benefit of the pact it needs to like make the stick man super
## saiyan deflect most attacks for the next 5 seconds so it can get up close and
## personal move faster and do more damage give it like a super siyan aura"*.
##
## It used to be a SPELL-DAMAGE multiplier and nothing else — which is a strange thing
## to hand the one class in the roster built around a sword, and it read as nothing at
## all: you cast it, a ring appeared at your feet, and your numbers were quietly bigger
## somewhere off screen. Three additions turn it into a state you can SEE and a reason
## to walk forward:
##
##   WARD    — most of what lands on you is shrugged off. This is the "get up close
##             and personal" half; without it the drain plus the approach is simply a
##             faster death, and the Swordsaint's whole problem is closing distance.
##   SPEED   — you move like you mean it.
##   AURA    — the rig's existing rank aura, forced to its top tier in gold. Reusing
##             `set_aura` rather than inventing a second glow means it composes with
##             everything already drawn on the figure and degrades on LOW quality for
##             free.
##
## ⚠ THE DRAIN IS UNCHANGED AND STILL KILLS. Every one of these makes the pact
## stronger, so the price has to stay real — it is still billed through `take_damage`
## and it can still finish you. A super mode you cannot lose is a cooldown, not a
## decision.
const PACT_WARD: float = 0.62          # share of incoming damage refused
const PACT_SPEED_MULT: float = 1.32
const AURA_COLOR: Color = Color(1.0, 0.86, 0.25)


func hex(caster: Node, _origin: Vector2, _target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_life = maxf(spell.length, 0.5)
	# `radius` is the multiplier and `count` the drain — see the SpellDef's note on
	# the field-doubling this codebase already does for ZONE lifetimes.
	_mult = maxf(spell.radius, 1.0)
	_drain_per_second = maxf(float(spell.count), 0.0)
	_color = color
	global_position = Vector2.ZERO
	add_to_group(PACT_GROUP)
	SpellSigil.open(self, _caster_pos(), RING_COLOR, 0.9, false, Vector2.RIGHT, true, 0.1, 0.4)
	SpellDrops.sfx("cast_shadow", -3.0, 0.1, 0.62)
	# ⚠ NO CAMERA SHAKE. Maker: *"it shakes the screen too much"*. This was one call
	# at cast — but see `_physics_process`: the real offender was the DRAIN, and
	# removing this as well means the pact opens on its sound and its sigil rather
	# than on a jolt. A buff you put on yourself should not read like being hit.
	_light_the_aura(true)
	queue_redraw()


## The gold. Reuses the rig's own rank aura at its top tier rather than adding a
## second glow system, so it composes with the element tint, the status VFX and the
## weapon trail already on the figure — and it degrades on LOW quality for free,
## because that gate is inside `CharacterRig` and not here.
##
## ⚠ THE PREVIOUS AURA IS PUT BACK. The aura is not the pact's property, it is the
## HERO's (element colour, rank tier), so this borrows it and returns it. Leaving a
## gold tier-5 aura on a body after its pact expired would be a permanent visual lie
## about a buff that had ended.
func _light_the_aura(on: bool) -> void:
	var rig: Variant = null
	if caster_node != null and is_instance_valid(caster_node):
		rig = caster_node.get(&"rig")
	if rig == null or not is_instance_valid(rig as Object):
		return
	var r: Object = rig as Object
	if on:
		if not r.has_method("set_aura"):
			return
		_prev_aura = r.get(&"aura_color")
		_prev_aura_strength = float(r.get(&"aura_strength"))
		_prev_aura_tier = int(r.get(&"aura_tier"))
		_had_aura = true
		r.call("set_aura", AURA_COLOR, 1.0)
		if r.has_method("set_aura_tier"):
			r.call("set_aura_tier", 5)
	elif _had_aura and r.has_method("set_aura"):
		r.call("set_aura", _prev_aura, _prev_aura_strength)
		if r.has_method("set_aura_tier"):
			r.call("set_aura_tier", _prev_aura_tier)


## The multiplier every spell cast by `caster` is scaled by, or 1.0. Largest live
## pact wins; pacts never stack (see the header).
##
## `ctx` only has to be SOMETHING in the tree — the caster itself is the usual
## argument. Returns 1.0 with no tree, which is the headless / `--script` case and
## the conservative direction.
static func multiplier_for(caster: Object, ctx: Node) -> float:
	if caster == null or not is_instance_valid(caster) or ctx == null or not ctx.is_inside_tree():
		return 1.0
	var tree: SceneTree = ctx.get_tree()
	if tree == null:
		return 1.0
	var best: float = 1.0
	var want: int = (caster as Object).get_instance_id()
	for p: Node in tree.get_nodes_in_group(PACT_GROUP):
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			continue
		var owner_node: Variant = p.get(&"caster_node")
		if owner_node == null or not is_instance_valid(owner_node as Object):
			continue
		if (owner_node as Object).get_instance_id() != want:
			continue
		best = maxf(best, float(p.get(&"_mult")))
	return best


## Is this body inside a live pact? One group scan, same shape and same per-caster
## matching as `multiplier_for`, so the two can never disagree about who is pacted.
static func is_pacted(caster: Object, ctx: Node) -> bool:
	return multiplier_for(caster, ctx) > 1.0


## The share of incoming damage a pacted body refuses, or 0.0. Kept here rather than
## on `Hero` so the number lives with the spell that grants it — a ward the victim
## owns is a ward nobody can find when they are reading the spell.
static func ward_for(caster: Object, ctx: Node) -> float:
	return PACT_WARD if is_pacted(caster, ctx) else 0.0


## The movement multiplier a pacted body carries, or 1.0.
static func speed_mult(caster: Object, ctx: Node) -> float:
	return PACT_SPEED_MULT if is_pacted(caster, ctx) else 1.0


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if not _caster_ok() or _elapsed >= _life:
		_end()
		return
	_owed += _drain_per_second * delta
	# ══ THE DRAIN BILLS IN BEATS, NOT IN DROPLETS ═══════════════════════════════
	# Maker: *"it shakes the screen too much"*. The cast shake was one call; THIS was
	# forty. At 5 HP/s the old `_owed >= 1.0` test paid a whole point about five times
	# a second, and every payment went through `take_damage` — which is the real hurt
	# path, so each one fired a hurt flash, a hit-stop AND a camera shake. An eight
	# second pact was forty jolts, and the player had done nothing but buff themselves.
	#
	# Same total cost, an eighth of the events: it now settles up once a beat. That
	# also reads BETTER — a heartbeat you can count, which is what the drip cadence was
	# always trying to say, rather than a continuous rattle.
	#
	# ⚠ STILL THROUGH `take_damage`, and that is not negotiable: the pact must be able
	# to KILL you, and only the real path runs the death. Bypassing it to make the
	# screen calmer would quietly remove the entire reason the buff is allowed to be
	# this large.
	_bill += delta
	if _bill >= BILL_INTERVAL and _owed >= 1.0:
		_bill = 0.0
		var pay: int = int(floorf(_owed))
		_owed -= float(pay)
		SpellTargets.hurt(caster_node, pay, RING_COLOR)
	_drip += delta
	if _drip >= DRIP_INTERVAL:
		_drip = 0.0
		CombatVfx.spawn_burst(get_parent(), _caster_pos(), Color(0.9, 0.15, 0.2, 0.85),
			Color(0.35, 0.02, 0.05, 0.0), 4, 0.4, 20.0, 70.0, 0.8, 2.0)
	queue_redraw()


func _caster_ok() -> bool:
	return caster_node != null and is_instance_valid(caster_node) \
		and not caster_node.is_queued_for_deletion() and HpWatch.is_alive(caster_node)


func _caster_pos() -> Vector2:
	# ⚠ VALIDITY BEFORE `is` — `_caster_ok()` just above gets this order right; this
	# function was the odd one out, and the pact outlives its caster by design.
	if is_instance_valid(caster_node) and caster_node is Node2D:
		return (caster_node as Node2D).global_position
	return Vector2.ZERO


func _end() -> void:
	# ⚠ THE GROUP LEAVES FIRST. `ward_for` / `speed_mult` / `multiplier_for` all read
	# membership, and `queue_free` does not take effect until the end of the frame —
	# so freeing without removing would leave the body warded and fast for one more
	# frame after the pact it is reading has ended.
	if is_in_group(PACT_GROUP):
		remove_from_group(PACT_GROUP)
	_light_the_aura(false)
	queue_free()


## A pulsing arterial ring under the caster plus a rising bar of how much of the
## pact is left. Both are drawn AT the caster every frame rather than parented to
## them, because a spectacle in this codebase never owns a transform.
func _draw() -> void:
	if not _caster_ok():
		return
	var at: Vector2 = _caster_pos()
	var beat: float = 0.5 + 0.5 * sin(_elapsed * 7.0)
	draw_arc(at + Vector2(0.0, 4.0), RING_RADIUS + 3.0 * beat, 0.0, TAU, 32,
		Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, 0.45 + 0.25 * beat), 2.6, true)
	draw_arc(at + Vector2(0.0, 4.0), RING_RADIUS * 0.6, 0.0, TAU, 24,
		Color(1.4, 0.3, 0.35, 0.4 + 0.3 * beat), 1.6, true)
	# Remaining-duration arc, drawn on the ring itself so the player never has to
	# look away from their own feet to know how much bleeding is left.
	var left: float = clampf(1.0 - _elapsed / _life, 0.0, 1.0)
	draw_arc(at + Vector2(0.0, 4.0), RING_RADIUS + 7.0, -PI * 0.5,
		-PI * 0.5 + TAU * left, 40, Color(1.5, 0.35, 0.4, 0.9), 3.0, true)
	_draw_kanji(at + Vector2(0.0, -KANJI_LIFT), beat)


## ══ 血 — "BLOOD", OVER THE HEAD, FOR AS LONG AS THE PACT HOLDS ══════════════════
## Maker: *"add like a japanese kanji above the character whilst the ability is on"*.
##
## ⚠ DRAWN AS STROKES, NOT AS TEXT, AND THAT IS A CORRECTNESS POINT RATHER THAN A
## STYLE ONE. `ThemeDB.fallback_font` is Open Sans, which carries no CJK coverage at
## all — `draw_string("血")` renders an empty box (or nothing) and would have looked
## like a bug on every machine that does not happen to have a fallback installed.
## Vector strokes always render, they scale with the figure, and they match how every
## other glyph in this game is already drawn (the sigil's runes, the cast circles'
## motifs, the hotbar's figures).
##
## The character is 皿 (a dish) under a single top stroke — a vessel holding blood.
## Six strokes, in writing order, which is why they are listed the way they are.
func _draw_kanji(top: Vector2, beat: float) -> void:
	var w: float = KANJI_SIZE
	var h: float = KANJI_SIZE * 1.15
	# Brightens on the same heartbeat as the ring, so the mark and the drain read as
	# one system rather than two effects that happen to be on at the same time.
	var col := Color(1.35, 0.28, 0.32, 0.72 + 0.22 * beat)
	var th: float = maxf(w * 0.11, 1.4)
	var l: float = top.x - w * 0.5
	var r: float = top.x + w * 0.5
	var y0: float = top.y
	var y1: float = top.y + h
	# 1 — the lone stroke on top, leaning left, that turns 皿 into 血.
	draw_line(Vector2(top.x - w * 0.10, y0), Vector2(top.x - w * 0.30, y0 + h * 0.16), col, th, true)
	# 2 — the lid.
	draw_line(Vector2(l, y0 + h * 0.22), Vector2(r, y0 + h * 0.22), col, th, true)
	# 3, 4 — the two walls of the vessel, tapering inward the way the character does.
	draw_line(Vector2(l + w * 0.08, y0 + h * 0.22), Vector2(l + w * 0.14, y1 - h * 0.14), col, th, true)
	draw_line(Vector2(r - w * 0.08, y0 + h * 0.22), Vector2(r - w * 0.14, y1 - h * 0.14), col, th, true)
	# 5, 6 — the two uprights inside it.
	draw_line(Vector2(top.x - w * 0.16, y0 + h * 0.30), Vector2(top.x - w * 0.16, y1 - h * 0.16), col, th, true)
	draw_line(Vector2(top.x + w * 0.16, y0 + h * 0.30), Vector2(top.x + w * 0.16, y1 - h * 0.16), col, th, true)
	# 7 — the base the whole character stands on, drawn heavier: it is the stroke the
	# eye reads first at this size and it is what stops the glyph looking like a fence.
	draw_line(Vector2(l - w * 0.06, y1), Vector2(r + w * 0.06, y1), col, th * 1.25, true)
