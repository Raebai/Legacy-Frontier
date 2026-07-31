class_name Equinox
extends Node2D
## EQUINOX — Tier 3 boss drop, one charge. THE SWAP FOR REWIND.
##
## Every living thing in the room is dragged to the SAME FRACTION of its own
## health: the mean of everyone present. Nothing is dealt and nothing is healed in
## the ordinary sense — the scales simply come level, and somebody always loses by
## it.
##
## ══ WHY THIS EXISTS INSTEAD OF REWIND ══════════════════════════════════════════
## The spec flagged Rewind as the suspicious one and it was right. A 4-second state
## rewind is not a spell, it is a netcode architecture: it has to restore the
## transform, velocity, HP, cooldown, status and animation state of every body, undo
## every spectacle spawned in the window, resurrect the dead, rebuild destroyed
## cover — and do all of it identically on two peers where each hero is authoritative
## over ITSELF. That last clause is the one that kills it: a rewind cast by peer A
## cannot legally move peer B's hero, so either it silently does not rewind the other
## player (a spell that lies) or authority moves to the caster for four seconds (a
## rewrite of the co-op model for one item on a drop table).
## `tools/rewind_spike.gd` measures what the cheap version actually covers.
##
## EQUINOX KEEPS EVERYTHING REWIND WAS FOR and drops the part that was a research
## project. It is catastrophic — it can hand a guardian a third of its bar back. It
## is decision-shaped — cast it dying and you live; cast it while your teammate is
## healthy and you have just mugged them to save yourself. It can lose you the
## floor. And in co-op it is the cleanest of the four, because it moves HP and
## nothing else, and HP already has an authority-correct route in this codebase.
##
## ⚠ THE MEAN IS OF FRACTIONS, NOT OF ABSOLUTE HP. Levelling raw HP would set a
## 100 HP hero and a 2000 HP guardian to the same number, which would either delete
## the boss or delete you depending on the arithmetic, every single time — a spell
## with one outcome is not a decision. Fractions make it relational: it is good for
## whoever is furthest below the room's average and bad for whoever is above it.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.HOLY
var caster_node: Node = null
var spell_tier: int = SpellTier.Tier.ULT

## The beat between the working opening and the scales tipping. Long, and it has to
## be: your teammate's only counterplay is to see it coming and use whatever heal or
## escape they have before it lands.
const LEVEL_TIME: float = 0.75
const AFTERGLOW: float = 0.5
const BEAM_COLOR: Color = Color(1.5, 1.35, 0.8)
## Below this many participating bodies the spell does nothing but flash — levelling
## one body against itself is a no-op and should read as a whiff, not as a bug.
const MIN_PARTICIPANTS: int = 2

var _center: Vector2 = Vector2.ZERO
var _radius: float = 900.0
var _color: Color = Color(1.0, 0.94, 0.6)
var _elapsed: float = 0.0
var _levelled: bool = false
## Rows drawn during the afterglow: {pos, gained (bool)}.
var _marks: Array[Dictionary] = []
var _mean: float = 0.0


func cataclysm(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_center = target
	_radius = maxf(spell.radius, 60.0)
	_color = color
	global_position = Vector2.ZERO
	SpellSigil.open(self, _center, color, 1.6, false, Vector2.RIGHT, true, 0.16, 0.6)
	SpellDrops.sfx("holy_swell", -1.0, 0.04, 0.8)
	Juice.zoom_pull_camera(0.24, 1.0, 0.24, 0.8)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if not _levelled and _elapsed >= LEVEL_TIME:
		_level()
	elif _levelled and _elapsed >= LEVEL_TIME + AFTERGLOW:
		queue_free()
		return
	queue_redraw()


## The whole spell. Two passes: measure the mean, then move everybody to it.
##
## The RAW group, not `hostiles()` — "you, your friend, the thing you are fighting"
## is the description, and a levelling that skipped its own caster would be a heal
## with extra steps.
func _level() -> void:
	_levelled = true
	var bodies: Array = []
	var sum: float = 0.0
	for n: Node in SpellTargets.in_radius(_center, _radius,
			get_tree().get_nodes_in_group(target_group), [], self, false):
		var f: float = HpWatch.fraction_of(n)
		if f < 0.0 or not HpWatch.is_alive(n):
			continue           # no publishable health — not part of the levelling
		bodies.append(n)
		sum += f
	if bodies.size() < MIN_PARTICIPANTS:
		SpellDrops.sfx("holy", -9.0, 0.1, 1.5)
		return
	_mean = mean_fraction(sum, bodies.size())
	for n: Node in bodies:
		var mx: int = HpWatch.max_hp_of(n)
		var cur: int = HpWatch.hp_of(n)
		var want: int = target_hp(_mean, mx)
		if want < cur:
			# Downward through the real damage path, so the death/HUD plumbing runs.
			SpellTargets.hurt(n, cur - want, Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 1.0))
			_marks.append({"pos": (n as Node2D).global_position, "gained": false})
		elif want > cur:
			HpWatch.gain(n, want - cur)
			_marks.append({"pos": (n as Node2D).global_position, "gained": true})
	Juice.on_hit({"shake": 18.0, "zoom": 0.16, "sfx": "verdict_burn", "sfx_pitch": 0.1,
		"hitstop": 0.12})
	PostProcess.shock(0.6, Juice.world_to_uv(_center))
	Juice.tier_frame(SpellTier.Tier.ULT, _center, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


## The fraction everything was levelled to, 0 before it fires. Public so the test
## suite can assert the arithmetic without reading a private.
func levelled_fraction() -> float:
	return _mean


## THE LEVEL, as pure arithmetic. Split out of `_level` so it is testable without a
## live arena — the spell body reaches `Juice` and `PostProcess`, which do not exist
## under a `--script` harness, and a test that cannot run is a rule that is not
## enforced.
static func mean_fraction(sum_of_fractions: float, participants: int) -> float:
	if participants <= 0:
		return 0.0
	return clampf(sum_of_fractions / float(participants), 0.0, 1.0)


## What a body with `max_hp` should be set to at fraction `mean`.
##
## FLOORED AT 1 so the levelling can never itself be a kill. Equinox is a LEVELLER;
## anything that dies after it dies to the next thing that lands, which is a far
## better story than "the spell that killed you was arithmetic". It also keeps the
## spell from being an unconditional wipe when the room's average is near zero.
static func target_hp(mean: float, max_hp: int) -> int:
	if max_hp <= 0:
		return 0
	return maxi(int(round(clampf(mean, 0.0, 1.0) * float(max_hp))), 1)


func _draw() -> void:
	if not _levelled:
		_draw_windup()
		return
	_draw_afterglow()


## A pair of scale-pans tipping toward level, drawn large and centred. The read has
## to be "something is about to happen to EVERYONE", which a ring cannot say —
## a ring says "stay outside me", and there is no outside.
func _draw_windup() -> void:
	var t: float = clampf(_elapsed / LEVEL_TIME, 0.0, 1.0)
	var span: float = 150.0
	var tilt: float = (1.0 - t) * 34.0
	var beam_l := _center + Vector2(-span, tilt)
	var beam_r := _center + Vector2(span, -tilt)
	draw_line(beam_l, beam_r, Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.85), 3.0, true)
	draw_line(_center + Vector2(0.0, -46.0), _center + Vector2(0.0, 26.0),
		Color(_color.r, _color.g, _color.b, 0.7), 2.4, true)
	for p: Vector2 in [beam_l, beam_r]:
		draw_arc(p, 26.0, 0.0, PI, 20, Color(_color.r, _color.g, _color.b, 0.8), 2.2, true)
	# A widening ground wash so the "no edge" truth is stated rather than implied.
	draw_circle(_center, 260.0 * t, Color(_color.r, _color.g, _color.b, 0.10 * t), true, -1.0, true)


## Who gained and who paid, marked on the bodies themselves for half a second. This
## is the spell's whole feedback loop — without it a player has no way to learn that
## they just healed the guardian.
func _draw_afterglow() -> void:
	var t: float = clampf((_elapsed - LEVEL_TIME) / AFTERGLOW, 0.0, 1.0)
	var a: float = 1.0 - t
	for m: Dictionary in _marks:
		var p: Vector2 = m["pos"]
		var up: bool = bool(m["gained"])
		var col := Color(0.6, 1.5, 0.8, a) if up else Color(1.6, 0.7, 0.5, a)
		var dir: Vector2 = Vector2.UP if up else Vector2.DOWN
		draw_line(p, p + dir * (30.0 + 24.0 * t), col, 3.0, true)
		draw_circle(p + dir * (30.0 + 24.0 * t), 4.0 * a, col, true, -1.0, true)
	draw_arc(_center, 260.0 + 200.0 * t, 0.0, TAU, 64,
		Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, a * 0.8), 3.0, true)
