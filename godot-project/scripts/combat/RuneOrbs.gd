class_name RuneOrbs
extends Node2D
## Arcanist SIGNATURE — ARCANE MISSILES (SpellDef.Kind.MISSILES). A fan of small
## spinning rune-glyphs streams from the weapon tip along the AIM and pops in a
## precise arcane burst (Unstable). Precise control — not a beam, not a meteor.
## `count` orbs, `reach` unused, damage per orb. Draws in world coordinates; each
## orb is a bright core under a slowly spinning glyph.
##
## NO HOMING (magic-overhaul rule 1). Each orb flies a STRAIGHT line along its own
## fan angle; the only curvature is a cosmetic weave around that fixed axis, which
## never changes where the orb ends up. Landing hits is the caster's aim, and the
## stagger between launches is the target's dodge window.

const SPEED: float = 430.0
const HIT_RADIUS: float = 16.0
## ⚠ THE RANGE, AND THE SAFETY BOUND — an orb flies until it meets the world, meets
## a body, or has travelled this far, whichever comes first.
##
## THE MAKER: *"projectiles ... need to keep going until it hit something not just
## despawn in the air ... should have further distances."* This volley was the
## worst offender in the kit: the only thing ending it was a 1.7 s clock, which at
## SPEED 430 is **731 px** — barely past mid-screen — and the clock did not even
## call `_burst`, so a volley that reached its limit blinked out silently. Range is
## now a DISTANCE, and running out of it resolves the orb where it stopped.
##
## Why a distance rather than "no limit at all": the bound is what keeps an orb
## fired down an open corridor from becoming an entity that never resolves, and
## this project has an entity budget. 1700 is deliberately past the width of the
## one-screen floors that ship, so in practice a wall stops the orb first and the
## cap is scenery. Rejected: matching `Spell.gd`'s 2600 — a bolt is one projectile,
## this is a fan of up to six, so the leak it guards against is six times cheaper
## to trigger. UNTESTED GUESS; this is the number to move if the Q now outranges
## what the player can see.
const MAX_RANGE: float = 1700.0
## Hard backstop on the NODE, not on the flight. MAX_RANGE / SPEED is ~3.95 s, so
## this can only fire if an orb somehow stops advancing — it exists so a wedged
## volley still frees itself rather than living forever.
const MAX_LIFE: float = 4.5
const ORB_R: float = 6.0
const FAN_SPREAD: float = 0.3   # radians between adjacent orbs in the fan
const STAGGER: float = 0.055    # launch delay per orb — they STREAM out, not a wall
const WEAVE_AMP: float = 7.0    # cosmetic sideways weave (px) around the fixed axis
const WEAVE_FREQ: float = 11.0

## WHO THIS SPELL MAY HURT. Stamped by SpellCaster._stamp() at cast time, so it
## follows the CASTER's faction rather than being fixed at "enemy" forever. Every
## spectacle used to scan the literal group "enemy", which is why a hero-shaped
## bot's spells passed harmlessly through another hero: the aim was right, the
## spectacle spawned and drew, then it queried a group its target was not in.
## Nothing errored. Defaults to "enemy", so single player is byte-identical.
var target_group: String = "enemy"
var element_id: int = Elements.Element.ARCANE
var _color: Color = Color(0.85, 0.5, 1.0, 1.0)
var _dmg: int = 24
var _orbs: Array = []   # each: {origin, dir, perp, delay, phase, alive, pos, spin}
var _elapsed: float = 0.0

## WHO CAST THIS. `SpellCaster._stamp` has always written this name onto every
## spectacle it builds, but this file never declared it — and `set()` on an
## undeclared property is a silent no-op, so the write went nowhere. That cost
## nothing while a hero's spells scanned `"enemy"` (the caster was never in that
## group) and became a SELF-KILL the moment friendly fire pointed them at the
## shared `"mortal"` group. Declaring it is what arms `SpellTargets.hostiles()` /
## `SpellTargets.owner_of()`, which is where the exclusion is now enforced.
var caster_node: Node = null
## The shelf this volley sits on. Declared for the same reason `caster_node` above
## is: `SpellCaster._stamp` has always written it and `set()` on an undeclared
## property is a silent no-op, so the write went nowhere and the summoning sigil
## had no way to know whether it was drawing a jab or a finisher.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT


func launch(origin: Vector2, aim: Vector2, color: Color, count: int = 5, damage: int = 24, _effect: String = "arcane") -> void:
	_color = color
	_dmg = damage
	var base: Vector2 = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	for i in count:
		# Fan outward from the centre of the volley, innermost orbs leaving first.
		var offset: float = float(i) - float(count - 1) * 0.5
		var dir: Vector2 = base.rotated(offset * FAN_SPREAD)
		_orbs.append({
			"origin": origin,
			"dir": dir,
			"perp": dir.orthogonal(),
			"delay": absf(offset) * STAGGER,
			"phase": float(i) * 1.7,
			"alive": true,
			"pos": origin,
			"spin": float(i) * 1.3,
		})
	global_position = Vector2.ZERO
	# THE VOLLEY GATE. The orbs stream out THROUGH a sigil rather than appearing at
	# the weapon tip, so the fan reads as being summoned rather than spawned. Edge-on
	# along the aim because the orbs have a direction of travel; held just past the
	# last orb's stagger so the gate closes behind the volley instead of with it.
	SpellSigil.open(self, origin, color, 1.0, true, base, false, 0.16,
		float(count) * STAGGER + 0.34)
	Sfx.play("cast", 1.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	var any_alive: bool = false
	for orb in _orbs:
		if not orb["alive"]:
			continue
		any_alive = true
		var age: float = _elapsed - float(orb["delay"])
		if age <= 0.0:
			continue  # still queued at the weapon tip
		var prev: Vector2 = orb["pos"]
		orb["pos"] = _orb_position(orb, age)
		orb["spin"] = float(orb["spin"]) + delta * 8.0
		# ⚠ THE WORLD SWEEP. THIS IS THE MAKER'S "the projectiles shouldn't go through
		# the floor or anything", and it was the real thing — this file contained ZERO
		# references to `SpellWorld`. An orb's position was pure arithmetic
		# (`origin + dir * SPEED * age`) and its only collision test was a distance
		# check against bodies and crates. Nothing ever asked what was BETWEEN one
		# frame's position and the next, so at SPEED 430 over the 1.7 s clock this file
		# used to fly on, an orb flew 731 px straight through floors, ledges, walls
		# and platforms. (That clock is gone — see MAX_RANGE — but the sweep below is
		# what makes a longer flight safe to give it.)
		#
		# It went unnoticed for two compounding reasons worth recording: this volley
		# is a Cleric damage line AND the Cryomancer's Q ("Ice Shards"), so it fires
		# constantly; and the bot-sim's `spell_below_floor` probe only watches the
		# `"player_spell"` group, which ONLY `Spell.gd` joins — so the one spectacle
		# that actually flew through the world was invisible to the one check that
		# was looking for exactly that.
		#
		# Swept per frame from the PREVIOUS position, not point-tested at the new one:
		# a point test at 430 px/s tunnels straight through anything thinner than
		# 7 px at 60 fps, which is most ledges.
		var world: Dictionary = SpellWorld.first_solid(prev, orb["pos"], [], self)
		if bool(world["hit"]):
			orb["pos"] = world["position"]
			_burst(orb)          # it breaks ON the surface, not inside it
			orb["alive"] = false
			continue
		var e: Node = _target_within(orb["pos"], HIT_RADIUS)
		if e != null:
			_pop(orb, e)
			continue
		# END OF RANGE. Measured on the orb's OWN age, not on `_elapsed`: the fan is
		# staggered, so a shared clock cut the outer orbs' flight short by their
		# launch delay — the outermost of a six-orb fan got 683 px where the innermost
		# got 731. Every orb now gets the same budget.
		#
		# It BURSTS rather than blinking out. `_burst` was split out precisely so "an
		# orb stopped by a wall looks like an orb stopped by a body", and the one path
		# that never called it was this one — which is what made a spent volley read
		# as the spell fizzling.
		if SPEED * age >= MAX_RANGE:
			_burst(orb)
			orb["alive"] = false
	if _elapsed >= MAX_LIFE:
		for orb in _orbs:
			if bool(orb["alive"]):
				_burst(orb)
			orb["alive"] = false
	if not any_alive:
		queue_free()
		return
	queue_redraw()


## Straight-line travel along the orb's fixed launch axis, plus a purely cosmetic
## weave perpendicular to it. The weave tapers in from the muzzle so the stream
## reads as ribboning rather than wobbling off-aim.
func _orb_position(orb: Dictionary, age: float) -> Vector2:
	var along: Vector2 = (orb["origin"] as Vector2) + (orb["dir"] as Vector2) * SPEED * age
	var taper: float = clampf(age * 4.0, 0.0, 1.0)
	var wob: float = sin(age * WEAVE_FREQ + float(orb["phase"])) * WEAVE_AMP * taper
	return along + (orb["perp"] as Vector2) * wob


func _pop(orb: Dictionary, e: Node) -> void:
	orb["alive"] = false
	if e.has_method("take_damage"):
		SpellTargets.hurt(e, _dmg, Color(_color.r, _color.g, _color.b, 1.0))
	if e.has_method("apply_status"):
		e.apply_status(element_id)
	_burst(orb)


## The pop VFX on its own, so an orb that breaks on geometry looks like an orb that
## breaks on a body. Split out when the world sweep landed: without it, an orb
## stopped by a wall would have vanished silently, which reads as the spell fizzling
## rather than as it hitting something.
func _burst(orb: Dictionary) -> void:
	CombatVfx.spawn_burst(get_parent(), orb["pos"],
		Color(_color.r, _color.g, _color.b, 0.95), Color(_color.r, _color.g, _color.b, 0.0),
		10, 0.3, 50.0, 140.0, 0.6, 1.6, 0.0, 0.0, true)


## Nearest damageable thing the orb has physically flown into — enemies first,
## then destructible cover (so a volley chews through crates like it should).
func _target_within(p: Vector2, r: float) -> Node:
	# The hostile faction, then the always-neutral destructibles — cover belongs to
	# nobody, so it stays a literal rather than following the caster.
	# hostiles(): an orb's first frame is AT the caster's hand. (Passing the
	# destructible literal through the same call is harmless — a caster is not a
	# crate, so nothing is removed from that pass.)
	for group: String in [target_group, "destructible"]:
		for e: Node in SpellTargets.hostiles(self, group):
			if e is Node2D and is_instance_valid(e) and p.distance_to((e as Node2D).global_position) <= r:
				return e
	return null


func _draw() -> void:
	for orb in _orbs:
		if not orb["alive"] or _elapsed < float(orb["delay"]):
			continue
		var p: Vector2 = orb["pos"]
		var spin: float = orb["spin"]
		draw_circle(p, ORB_R * 1.7, Color(_color.r, _color.g, _color.b, 0.28), true, -1.0, true)  # halo
		draw_circle(p, ORB_R * 0.6, Color(1.4, 1.1, 1.7, 0.95), true, -1.0, true)                 # HDR core
		# Two counter-spinning rune triangles (a tiny arcane glyph).
		var tri := PackedVector2Array()
		for k in 4:
			tri.append(p + Vector2.from_angle(spin + TAU * float(k) / 3.0) * ORB_R)
		draw_polyline(tri, Color(_color.r, _color.g, _color.b, 0.9), 1.5, true)
		var tri2 := PackedVector2Array()
		for k in 4:
			tri2.append(p + Vector2.from_angle(-spin * 1.3 + TAU * float(k) / 3.0) * ORB_R * 0.6)
		draw_polyline(tri2, Color(1.2, 0.9, 1.5, 0.7), 1.0, true)
