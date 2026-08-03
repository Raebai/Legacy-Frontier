class_name Shatter
extends Node2D
## SHATTER — the Cryomancer's damage signature, and the second half of the only
## two-button combo in the game.
##
## It replaces `frostpiercer`, which was a BeamSpell — one of FIVE classes that
## all threw the same beam down the same damage corridor. The maker's ruling was
## "we cannot have any recolours", and the answer for this class was not a
## different-looking beam but a different QUESTION: the Cryomancer already owns
## the only spell in the game that takes a body off the board (Blizzard's
## rime -> encase -> shatter fuse). Nothing consumed that state. Now something does.
##
## ── THE WHOLE IDENTITY: FREEZE, THEN BREAK ───────────────────────────────────
## Cast on a warm target this is a weak thump — deliberately, embarrassingly weak.
## Cast on a body that Blizzard has rimed it is an ordinary hit. Cast on a body
## that is ENCASED, or frozen by any other means, it detonates the casing:
## triple damage on that body, and the flying casing shards splash everything
## standing near it. Freezing a crowd and then breaking all of them at once is the
## Cryomancer's payoff and nobody else in the roster can express it.
##
##   WARM   x `WARM_MULT`   (0.35)
##   RIMED  x `RIMED_MULT`  (1.00)  — chilled, or carrying a live rime meter
##   FROZEN x `FROZEN_MULT` (3.00)  — frozen/staggered, or encased by a Blizzard
##
## ⚠ IT APPLIES NO ICE TO AN ALREADY-COLD BODY, and that is a rule rather than an
## oversight. `StatusComponent.apply(ICE)` on an already-chilled body FREEZES it,
## so a spell that re-applied ice on every hit would rebuild exactly the
## chill->freeze->chill stunlock that Blizzard's rework was written to delete
## ("ice is not fair"). Shatter CONSUMES cold; only a warm target is chilled, and
## that is the spell setting up its own next cast.
##
## ── THE TELL AND THE COUNTERPLAY (the locked "everything is dodgeable" rule) ──
##   TELL         A cryo-mark snaps flat onto the ground at the aimed point and a
##                fracture lattice etches outward across the full blast radius for
##                `FUSE` seconds. Anything already frozen inside it visibly
##                crazes. The footprint drawn IS the footprint that bites.
##   COUNTERPLAY  Two, at different timescales. Immediately: the fuse plus a small
##                fixed radius — step off the mark. Structurally: do not be
##                frozen. The whole spell is a conditional, and leaving the
##                Blizzard before the rime meter fills turns a 3x detonation into
##                a 0.35x tap. That second one is the real counterplay, and it is
##                readable a second and a half before this spell is even cast.
##
## ⚠ ELEMENT IS DECLARED, NEVER INFERRED — see the same note on `RadiantVolley`.
## ICE here, so the mark opposes FIRE in the reaction table rather than guessing.

# ------------------------------------------------------------------- IDENTITY
## Stamped by `SpellCaster._stamp()`. All five DECLARED, because `set()` on an
## undeclared property is a silent no-op and an un-stamped spectacle is inert in
## the entire reaction system without erroring once.
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.ICE
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT
## PULSE — a ring leaves this centre. Stated here because `SpellSigil`'s
## script-keyed motif table lives in a file this agent does not own; the
## `sigil_motif` override is the sanctioned route (`SpellSigil._motif_of`).
var sigil_motif: int = MagicCircle.Motif.PULSE

# --------------------------------------------------------------- THE CONDITION
## How cold a body is when the casing breaks. The ONE axis this spell reads.
enum Cold { WARM, RIMED, FROZEN }

## ⚠ THESE THREE NUMBERS ARE THE SPELL. Named constants rather than inline
## literals precisely so the combo can be tuned (and tested) as a ratio.
## Weak enough on a warm target that opening with it is a mistake.
const WARM_MULT: float = 0.35
## Ordinary against a chilled/riming body — the mid rung exists so the fuse has a
## meaningful middle rather than a cliff.
const RIMED_MULT: float = 1.0
## The payoff. 3x is the reason to spend a second and a half holding someone in a
## Blizzard, and it is why this class's control slot is not filler.
const FROZEN_MULT: float = 3.0
## Rime-meter fraction at or above which a body counts as RIMED. Below this the
## frost has barely started and calling it cold would make the fuse meaningless.
const RIME_MIN: float = 0.15

## Casing shards from a FROZEN break splash everything near that body, once each.
## The crowd payoff: freeze a cluster, break one, the rest wear the debris.
const SHARD_DAMAGE_FRAC: float = 0.35
const SHARD_RADIUS: float = 96.0

## The tell window. Short — this is a combo finisher, not a bombardment — but a
## real one: at 60 fps it is seventeen frames of warning.
const FUSE: float = 0.28
## How long the break stays on screen after it bites.
const BURST_LIFE: float = 0.40
## Outward shove, scaled by how cold the victim was: a warm body is nudged, a
## casing bursting is a real hit.
const KNOCKBACK: float = 240.0
const DEFAULT_RADIUS: float = 104.0
## Blades of the fracture lattice drawn during the fuse, and the cheap count that
## ships to the phone.
const FRACTURES: int = 14
const FRACTURES_LOW: int = 7

# ---------------------------------------------------------------- WORK COUNTERS
## Deterministic tallies (see the same note on `RadiantVolley`): the suite asserts
## what the break DID, never how many milliseconds it took.
var bodies_hit: int = 0
var frozen_breaks: int = 0
var shard_hits: int = 0
var damage_dealt: int = 0

var _at: Vector2 = Vector2.ZERO
var _color: Color = Color(0.55, 0.85, 1.0)
var _radius: float = DEFAULT_RADIUS
var _base_damage: int = 42
var _elapsed: float = 0.0
var _broken: bool = false
var _seed: int = 0


## Damage multiplier for a cold state. Pure, so the combo's whole balance claim is
## assertable without a scene.
static func multiplier_for(state: int) -> float:
	match state:
		Cold.FROZEN:
			return FROZEN_MULT
		Cold.RIMED:
			return RIMED_MULT
	return WARM_MULT


## What `base` damage becomes against a body in `state`. Derived from
## `multiplier_for`, never restated — a second copy of the ladder is how the
## tested number and the dealt number drift apart.
static func damage_for(base: int, state: int) -> int:
	return maxi(int(round(float(base) * multiplier_for(state))), 1)


## THE HEX ENTRY POINT. Fixed signature shared by every spell on the
## `SpellDef.Kind.HEX` fork — see `SpellCaster.HEX_SCRIPTS`.
func hex(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_color = color
	_seed = randi()
	if spell != null:
		_base_damage = maxi(spell.damage, 1)
		if spell.radius > 0.0:
			_radius = spell.radius
	# Seat the mark on the actual floor under the aim, via the shared probe rather
	# than a private raycast (docs/spell-world-contract.md). Over a pit this hands
	# the aim point straight back, which is correct: the fracture still happens in
	# the air where you pointed, it just has no floor to craze.
	_at = SpellWorld.floor_point(target, 220.0, [], self)
	# ⚠ WORLD SPACE. A spectacle parks at the arena origin, so `global_position` is
	# (0, 0) and not where the effect is. Everything below is absolute.
	global_position = Vector2.ZERO
	# THE SUMMONING CIRCLE, flat on the floor and scaled to the footprint it is
	# about to break — a placed spell's gate lies down.
	SpellSigil.open(self, _at, color, _radius / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.16, FUSE + BURST_LIFE)
	SpellDrops.sfx("ice_encase", -3.0, 0.10, 1.25)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if not _broken and _elapsed >= FUSE:
		_broken = true
		_break()
	if _elapsed >= FUSE + BURST_LIFE:
		queue_free()
		return
	queue_redraw()


# ------------------------------------------------------------------- THE BREAK
## The one damaging beat. Everything inside the drawn footprint, each body scored
## on its own cold state — this is the only place the multipliers are applied.
func _break() -> void:
	# `SpellTargets.in_radius` over `hostiles()`: the sanctioned selector. It
	# excludes the caster's own body (friendly fire points every spell at the
	# shared `mortal` group, and the caster is usually standing in the blast) and
	# it measures to the SILHOUETTE rather than to a body's origin.
	var caught: Array = SpellTargets.in_radius(_at, _radius,
		SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self)
	var frozen: Array[Node2D] = []
	for body: Node in caught:
		var state: int = cold_state(body)
		if _hurt_one(body, damage_for(_base_damage, state), state) and state == Cold.FROZEN:
			frozen_breaks += 1
			if body is Node2D:
				frozen.append(body as Node2D)
	# The casing shards. Splash from each broken casing, once per victim across the
	# whole detonation, so a tight cluster of frozen bodies does not multiply into
	# a nonsense number.
	if not frozen.is_empty():
		_splash(frozen, caught)
	# Cover is faction-blind — it belongs to nobody — so it stays a literal group
	# and takes the flat base, never a cold multiplier (a crate cannot be frozen).
	for prop: Node in SpellTargets.in_radius(_at, _radius,
			SpellTargets.hostiles(self, &"destructible"), [caster_node], self):
		if prop.has_method("damage_at"):
			prop.call("damage_at", _base_damage,
				(prop as Node2D).global_position if prop is Node2D else _at, Vector2.UP)
		else:
			SpellTargets.hurt(prop, _base_damage, _color)
	_burst()


## Apply one body's share. Returns true when damage actually landed (a guard can
## eat it whole), so the caller can tell a real casing break from a parried one.
func _hurt_one(body: Node, amount: int, state: int) -> bool:
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return false
	var at: Vector2 = SpellTargets.aim_point(body)
	var away: Vector2 = Vector2.UP
	if body is Node2D:
		var span: Vector2 = (body as Node2D).global_position - _at
		if span.length_squared() > 0.0001:
			away = span.normalized()
	var dealt: int = SpellDeflect.resolve(body, amount, away, at)
	if dealt <= 0:
		return false
	# ⚠ `take_damage` ships two signatures (Hero one arg, Enemy two). The wrong one
	# THROWS and aborts the enclosing function — always route through
	# `SpellTargets.hurt`, which adapts the arity.
	SpellTargets.hurt(body, dealt, Color(_color.r, _color.g, _color.b, 1.0))
	bodies_hit += 1
	damage_dealt += dealt
	# ⚠ ICE ONLY ON A WARM BODY. See the header: a second ICE application on an
	# already-chilled body is a FREEZE, and re-freezing on every hit is the exact
	# stunlock Blizzard's rework deleted. Shatter consumes cold, it does not stack it.
	if state == Cold.WARM and element_id >= 0 and body.has_method("apply_status"):
		body.apply_status(element_id)
	if body.has_method("apply_knockback"):
		body.call("apply_knockback", away * KNOCKBACK * multiplier_for(state))
	return true


## Casing shards. Each frozen body that actually broke throws debris; every OTHER
## caught body within `SHARD_RADIUS` of any of them takes one shard hit, total.
func _splash(frozen: Array[Node2D], caught: Array) -> void:
	var amount: int = maxi(int(round(float(_base_damage) * SHARD_DAMAGE_FRAC)), 1)
	var spent: Dictionary = {}
	for source: Node2D in frozen:
		if not is_instance_valid(source):
			continue
		CombatVfx.spawn_burst(get_parent(), source.global_position,
			Color(1.05, 1.35, 1.7, 0.95), Color(0.5, 0.75, 1.0, 0.0),
			22, 0.45, 120.0, 340.0, 0.5, 1.6, 0.0, 0.0, true)
		for body: Node in caught:
			if body == source or body == null or not is_instance_valid(body):
				continue
			if not body is Node2D:
				continue
			var id: int = body.get_instance_id()
			if spent.has(id):
				continue
			if source.global_position.distance_to((body as Node2D).global_position) > SHARD_RADIUS:
				continue
			spent[id] = true
			if SpellTargets.hurt(body, amount, Color(0.85, 0.97, 1.0, 1.0)):
				shard_hits += 1


func _burst() -> void:
	CombatVfx.spawn_burst(get_parent(), _at,
		Color(1.0, 1.3, 1.65, 0.95), Color(0.45, 0.72, 1.0, 0.0),
		26, 0.5, 90.0, 300.0, 0.6, 2.0, 0.0, 0.0, true)
	ScorchDecal.spawn(get_parent(), _at, _radius * 0.5, "crack",
		Color(0.62, 0.82, 1.0, 0.45), 2.4)
	# `ice_shatter`, not the generic `ice` stem: the whole point of this spell is
	# that it is Blizzard's third beat fired on demand, and the ear should agree.
	Juice.on_hit({"dir": Vector2.UP, "shake": 4.0 + 3.0 * float(frozen_breaks > 0),
		"sfx": "ice_shatter", "sfx_pitch": 0.08,
		"hitstop": 0.05 if frozen_breaks > 0 else 0.02})


# ------------------------------------------------------- reading how cold it is
## How cold `body` is, WITHOUT touching a single file this agent does not own.
##
## Two independent sources, because the two mechanics that make a body cold live
## in two different places and neither publishes a getter:
##   1. Its `StatusComponent` child — the chill/freeze channel every element uses.
##      Duck-typed on `is_hard_cc` + `slow_factor` rather than on the node's NAME,
##      because a node added with `add_child(StatusComponent.new())` is named by
##      the engine and that name is not a contract.
##   2. A live `ZoneSpell` (Blizzard) that has rime accrued on this body. Its
##      `_rime` dictionary is keyed by instance id; a body with a casing (`enc >= 0`)
##      is FROZEN outright and one with a part-filled meter is RIMED.
##
## ⚠ EVERY READ GOES THROUGH `Object.get()`, which answers `null` for a property
## that has moved rather than erroring — so a rename downstream degrades this to
## "warm" instead of aborting the detonation half-way. The suite pins the property
## NAMES separately so the degradation is loud rather than silent.
func cold_state(body: Node) -> int:
	if body == null or not is_instance_valid(body):
		return Cold.WARM
	var status: int = _status_cold(body)
	if status == Cold.FROZEN:
		return Cold.FROZEN
	var rime: int = _rime_cold(body)
	return maxi(status, rime)   # Cold is ordered WARM < RIMED < FROZEN


func _status_cold(body: Node) -> int:
	for child: Node in body.get_children():
		if not child.has_method(&"is_hard_cc") or not child.has_method(&"slow_factor"):
			continue
		var freeze: Variant = child.get(&"_freeze")
		if freeze != null and float(freeze) > 0.0:
			return Cold.FROZEN
		var chill: Variant = child.get(&"_chill")
		if chill != null and float(chill) > 0.0:
			return Cold.RIMED
	return Cold.WARM


## Blizzard's fuse, read off any live field that is tracking this body. Fields are
## siblings — `SpellCaster` parents every spectacle to the same arena node — so the
## sibling walk is both the cheapest and the only reliable place to find them.
func _rime_cold(body: Node) -> int:
	var parent: Node = get_parent()
	if parent == null:
		return Cold.WARM
	var id: int = body.get_instance_id()
	var best: int = Cold.WARM
	for sibling: Node in parent.get_children():
		if sibling == self or not is_instance_valid(sibling):
			continue
		var raw: Variant = sibling.get(&"_rime")
		if raw == null or not (raw is Dictionary):
			continue
		var table: Dictionary = raw as Dictionary
		if not table.has(id):
			continue
		var rec: Dictionary = table[id] as Dictionary
		if float(rec.get("enc", -1.0)) >= 0.0:
			return Cold.FROZEN   # encased: nothing colder to find
		# ⚠ THE FULL-METER VALUE IS READ OFF THE FIELD'S OWN SCRIPT, not restated
		# here. `Object.get()` cannot see a `const` (constants are not properties),
		# so the script's constant map is the only honest route — and it keeps this
		# file from naming `ZoneSpell` at all, which is what makes "a future field
		# with a different fuse length" score correctly for free. A field that
		# publishes no fuse length cannot be scored, so it is skipped rather than
		# guessed at.
		var scr: Script = sibling.get_script() as Script
		if scr == null:
			continue
		var consts: Dictionary = scr.get_script_constant_map()
		if not consts.has("RIME_TO_ENCASE"):
			continue
		var full: float = float(consts["RIME_TO_ENCASE"])
		if full > 0.0 and float(rec.get("t", 0.0)) / full >= RIME_MIN:
			best = maxi(best, Cold.RIMED)
	return best


# --------------------------------------------------------------------- THE LOOK
## ⚠ MUST DEGRADE AT `graphics_quality = LOW` (the phone preview, a hard rule).
## LOW halves the fracture blades and drops the crystal dust. The FOOTPRINT RING
## and the fuse's closing arc are drawn identically at both settings: they are the
## tell and the hitbox's advert, and thinning a telegraph is a fairness change
## rather than a fidelity one.
func _draw() -> void:
	var low: bool = TuningConfig.quality_is_low()
	if not _broken:
		_draw_fuse(low)
		return
	_draw_break(low)


func _draw_fuse(low: bool) -> void:
	var f: float = clampf(_elapsed / FUSE, 0.0, 1.0)
	# The footprint, flat on the floor. Same radius the damage query uses.
	draw_set_transform(_at, 0.0, Vector2(1.0, 0.42))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 40,
		Color(0.55, 0.82, 1.0, 0.28 + 0.30 * f), 2.0, true)
	# The closing arc: how much fuse is left, drawn on the floor so it cannot be
	# mistaken for the blast itself.
	draw_arc(Vector2.ZERO, _radius * 0.86, -PI * 0.5, -PI * 0.5 + TAU * f, 40,
		Color(1.15, 1.5, 1.85, 0.9), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Fracture blades etching outward from the mark.
	var blades: int = FRACTURES_LOW if low else FRACTURES
	for i: int in blades:
		var ang: float = TAU * float(i) / float(blades) + float(_seed % 31) * 0.07
		var len: float = _radius * (0.35 + 0.65 * f) * (0.7 + 0.3 * _hash01(i * 71))
		var a: Vector2 = _at + Vector2.from_angle(ang) * (_radius * 0.12)
		var b: Vector2 = _at + Vector2.from_angle(ang) * len
		draw_line(a, b, Color(0.78, 0.95, 1.1, 0.35 + 0.5 * f), 1.0 + 1.6 * f, true)
		if not low:
			var mid: Vector2 = a.lerp(b, 0.62)
			draw_line(mid, mid + Vector2.from_angle(ang + 0.9) * len * 0.22,
				Color(0.9, 1.0, 1.15, 0.28 * f), 1.0, true)


func _draw_break(low: bool) -> void:
	var k: float = clampf((_elapsed - FUSE) / BURST_LIFE, 0.0, 1.0)
	var alpha: float = 1.0 - k
	# The ring leaving the centre — PULSE, the motif the sigil is stating.
	draw_set_transform(_at, 0.0, Vector2(1.0, 0.42))
	draw_arc(Vector2.ZERO, _radius * (0.4 + 0.9 * k), 0.0, TAU, 44,
		Color(1.2, 1.55, 1.9, 0.85 * alpha), 4.0 * alpha + 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if low:
		return
	# Crystal splinters thrown out of the break. Garnish — first thing to go.
	for i: int in 12:
		var ang: float = TAU * _hash01(_seed + i * 37)
		var d: float = _radius * (0.3 + 1.1 * k) * (0.6 + 0.5 * _hash01(i * 13 + 5))
		var p: Vector2 = _at + Vector2.from_angle(ang) * d
		draw_line(p, p - Vector2.from_angle(ang) * (7.0 + 9.0 * k),
			Color(0.95, 1.15, 1.4, 0.75 * alpha), 1.6, true)


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)
