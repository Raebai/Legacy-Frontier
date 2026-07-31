class_name CartographerBoss
extends TowerBoss
## THE CARTOGRAPHER — compass and ruler, ink on graph paper.
##
## ── THE ARTIST ───────────────────────────────────────────────────────────────
## A draughtsman. Every line it makes is measured: straight edges at exact angles,
## arcs struck from a fixed centre, a lattice at even spacing. It does not draw a
## monster — it draws the FLOOR, and you happen to be standing on it. Robe, hat and
## staff, in ink-black with cyan drafting lines, because the fantasy here is a
## technician rather than a beast.
##
## ── HOW IT FIGHTS DIFFERENTLY ────────────────────────────────────────────────
## THE FIGHT IS GEOMETRY, AND IT NEVER CHASES YOU.
##
## The Scribble asks "can you keep time?". This asks "can you read a shape?". It
## walks barely at all (speed_scale 0.62 in the roster) and instead REPOSITIONS by
## redrawing itself at a chosen coordinate. Its whole kit is danger written as
## figures on the page:
##
##   STRAIGHTEDGE  a ruled line clean across the arena at a fixed angle.
##                 Answer: be off the line. Not "dodge" — *stand elsewhere*.
##   COMPASS       an arc struck from the boss at a fixed RADIUS.
##                 Answer: be nearer or further. The one attack in the whole game
##                 where the safe place is defined by distance and nothing else,
##                 and the reason this boss is worth having in the roster at all.
##   LATTICE       a grid of pillars at even spacing.
##                 Answer: stand in a cell. The gaps are the mechanic.
##   PROJECTION    a bombardment on your last known coordinate.
##                 Answer: stop being at your last known coordinate.
##
## Nothing here is about timing a dodge and nothing is about a punish window. Every
## answer is a POSITION, which makes it the exact complement of the other two
## bosses rather than a differently-coloured version of either.
##
## ── WHY THE COMPASS IS AN ANNULUS AND NOT A CIRCLE ───────────────────────────
## A nova (danger everywhere inside a radius) teaches "run outward", which is what
## every other AoE in the game already teaches. A ring of strikes AT a radius has
## two safe answers — inside and outside — and the inside one means walking TOWARD
## the boss while it casts. That is a genuinely new decision on a phone, it is
## readable at 640x360 because a ring of separate marks survives downsampling where
## a soft gradient does not, and it is the single thing this boss is remembered for.

const RIG_H: float = 92.0
const INK: Color = Color(0.15, 0.17, 0.25)
const DRAFT: Color = Color(0.38, 0.86, 1.0)

## STRAIGHTEDGE. Ruled at a fixed set of angles rather than at the hero — a drawn
## line is a decision the artist made, not an aim.
const RULE_ANGLES: Array[float] = [0.0, 0.16, -0.16]
const RULE_LEN: float = 1000.0
const RULE_WIDTH: float = 34.0
const RULE_WINDUP: float = 0.66
const RULE_DAMAGE: int = 30

## COMPASS. Marks struck on a circle of this radius around the boss.
const COMPASS_RADIUS: float = 205.0
const COMPASS_MARKS: int = 9
const COMPASS_STAGGER: float = 0.045
const COMPASS_MARK_RADIUS: float = 58.0
const COMPASS_DAMAGE: int = 26

## LATTICE. Columns at even spacing across the hero's neighbourhood; the even
## spacing IS the safety, so it must not be jittered.
const LATTICE_SPACING: float = 132.0
const LATTICE_COLUMNS: int = 5
const LATTICE_STAGGER: float = 0.09
const LATTICE_RADIUS: float = 62.0
const LATTICE_DAMAGE: int = 27

## REDRAW. The Cartographer's own reposition — precise, announced, and to an exact
## offset rather than a random one.
const REDRAW_TELL: float = 0.6
const REDRAW_OFFSETS: Array[float] = [-300.0, -230.0, 230.0, 300.0]


func boss_title() -> String: return "THE CARTOGRAPHER"
func boss_artist() -> String: return "compass and ruler, ink on graph paper"
func boss_accent() -> Color: return DRAFT
func boss_tint() -> Color: return INK
func boss_rig_height() -> float: return RIG_H
func boss_preset() -> String: return "mage"


## Measured, not frantic. The cadence tightens only slightly with depth: this boss
## escalates by drawing MORE FIGURES AT ONCE (see P3's crosshatch), not by drawing
## the same one faster. A geometry puzzle you are not given time to read is not a
## geometry puzzle.
func phase_cooldown(p: int) -> float:
	match p:
		1: return 2.5
		2: return 2.0
		3: return 1.7
	return 2.2


func _phase_attack_ids(phase: int) -> Array:
	match phase:
		1: return ["straightedge", "lattice"]
		2: return ["straightedge", "compass", "lattice", "redraw"]
		3: return ["crosshatch", "compass", "lattice", "projection"]
	return []


func gesture_for(id: String) -> int:
	return CharacterRig.GestureKind.GATHER if id == "compass" else CharacterRig.GestureKind.RAISE


func _attack_duration(id: String) -> float:
	match id:
		"straightedge": return RULE_WINDUP + 0.6
		"crosshatch": return RULE_WINDUP + 0.9
		"compass": return 1.25
		"lattice": return 1.15
		"projection": return 1.3
		"redraw": return REDRAW_TELL + 0.25
	return 1.0


func _perform(id: String) -> void:
	match id:
		"straightedge": _atk_rule(1)
		"crosshatch": _atk_rule(2)
		"compass": _atk_compass()
		"lattice": _atk_lattice()
		"projection": _atk_projection()
		"redraw": _atk_redraw()


# ---------------------------------------------------------------- the moveset
## A RULED LINE (or two crossed ones in P3). Aimed at the hero's BEARING but snapped
## to one of a small set of angles, so it always reads as a drawn edge rather than
## as a tracking shot — and so the same three lines recur often enough to be learnt.
func _atk_rule(count: int) -> void:
	if not is_instance_valid(_hero):
		return
	var toward: float = signf(_hero.global_position.x - global_position.x)
	if toward == 0.0:
		toward = 1.0
	var picked: Array[float] = []
	while picked.size() < mini(count, RULE_ANGLES.size()):
		var a: float = RULE_ANGLES[randi() % RULE_ANGLES.size()]
		if not picked.has(a):
			picked.append(a)
	for a: float in picked:
		var dir := Vector2(toward, 0.0).rotated(a * toward)
		lane_tell(dir, RULE_LEN, RULE_WIDTH, RULE_WINDUP, func() -> void: _ink_line(dir))


func _ink_line(dir: Vector2) -> void:
	var origin: Vector2 = rig.get_weapon_tip() if is_instance_valid(rig) else global_position
	var beam: Node = spawn_spectacle("res://scripts/combat/BeamSpell.gd",
		Elements.Element.ARCANE, SpellTier.Tier.HEAVY)
	if beam == null:
		return
	beam.call("fire", origin, dir, DRAFT, RULE_LEN, RULE_WIDTH, RULE_DAMAGE, "arcane")
	_bfx("beam", {"pos": origin, "dir": dir, "col": DRAFT, "len": RULE_LEN,
		"w": RULE_WIDTH, "fx": "arcane", "el": Elements.Element.ARCANE})
	Juice.shake_camera(5.0)


## THE COMPASS ARC. A ring of strikes at a fixed radius, struck round the circle in
## order so you can SEE the arc being drawn rather than having it appear. The
## summoning circle at the centre states the radius up front — it is the compass
## point, and it is scaled to the ring so the ring is legible before any mark lands.
func _atk_compass() -> void:
	var centre: Vector2 = global_position
	summon_circle(centre, Elements.Element.HOLY, SpellTier.Tier.ULT, COMPASS_RADIUS * 0.62, 0.9, true)
	for i: int in COMPASS_MARKS:
		var th: float = TAU * float(i) / float(COMPASS_MARKS)
		# Squashed on y: the arena is a side-on room, and a true circle would put
		# half its marks in the ceiling. Flattening it makes the annulus a band of
		# floor either side of the boss, which is what the player can actually walk.
		var at: Vector2 = centre + Vector2(cos(th) * COMPASS_RADIUS, sin(th) * COMPASS_RADIUS * 0.34)
		var delay: float = COMPASS_STAGGER * float(i)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(self) or _bphase == BPhase.DEAD:
				return
			var d: Node = spawn_spectacle("res://scripts/combat/DivineRay.gd",
				Elements.Element.HOLY, SpellTier.Tier.HEAVY)
			if d != null:
				d.call("strike", at, DRAFT, COMPASS_MARK_RADIUS, COMPASS_DAMAGE, "holy")
			# THE ANNULUS IS THE WHOLE ATTACK. A client that could not see the ring
			# would have no way to find its safe radius — the one thing this boss is
			# remembered for would be invisible on half the phones in the room.
			_bfx("ray", {"pos": at, "col": DRAFT, "r": COMPASS_MARK_RADIUS,
				"fx": "holy", "el": Elements.Element.HOLY}))
	Juice.zoom_pull_camera(0.13, 0.55)


## THE LATTICE. Columns on an even grid across the hero's neighbourhood. The
## spacing is a constant and is never jittered: the gaps between the columns are
## the entire mechanic, and a lattice with random spacing is just a bombardment.
func _atk_lattice() -> void:
	if not is_instance_valid(_hero):
		return
	var base: Vector2 = _hero.global_position
	# Offset the phase of the grid so it is not permanently centred on the player —
	# otherwise the hero is always exactly between two columns and it is free.
	var shift: float = LATTICE_SPACING * (0.5 if (randi() % 2) == 0 else 0.0)
	var half: int = LATTICE_COLUMNS / 2
	for i: int in LATTICE_COLUMNS:
		var x: float = base.x + LATTICE_SPACING * float(i - half) + shift
		var delay: float = LATTICE_STAGGER * float(i)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(self) or _bphase == BPhase.DEAD:
				return
			var p: Node = spawn_spectacle("res://scripts/combat/RockPillar.gd",
				Elements.Element.EARTH, SpellTier.Tier.HEAVY)
			if p != null:
				p.call("erupt", Vector2(x, base.y), DRAFT.lerp(INK, 0.35),
					LATTICE_RADIUS, LATTICE_DAMAGE, "earth")
			# The GAPS between the columns are the mechanic, so the columns have to
			# exist on both screens or one player is standing in a cell they cannot see.
			_bfx("pillar", {"pos": Vector2(x, base.y), "col": DRAFT.lerp(INK, 0.35),
				"r": LATTICE_RADIUS}))


## PROJECTION. A bombardment plotted onto your last known coordinate — the
## Cartographer's answer to a player who has learned to stand still and read.
func _atk_projection() -> void:
	if not is_instance_valid(_hero):
		return
	var at: Vector2 = _hero.global_position
	summon_circle(at + Vector2(0.0, -150.0), Elements.Element.ARCANE, SpellTier.Tier.ULT, 78.0, 0.8)
	var m: Node = spawn_spectacle("res://scripts/combat/MeteorSigil.gd",
		Elements.Element.ARCANE, SpellTier.Tier.ULT)
	if m != null:
		m.call("rain", at, DRAFT, 155.0, 20, 11, "arcane")
	_bfx("meteor", {"pos": at, "col": DRAFT, "r": 155.0, "n": 11, "fx": "arcane",
		"el": Elements.Element.ARCANE})
	Juice.zoom_pull_camera(0.16, 0.5)


## REDRAW. It does not walk to a better position — it draws itself at one. The mark
## lands first (ground sigil, charge band filling), then the body. Distinct from the
## UNFINISHED modifier's version, which is erratic and lands next to the hero: this
## one is measured, always to a fixed offset, and always AWAY, because the
## Cartographer wants range and the modifier wants chaos.
func _atk_redraw() -> void:
	if not is_instance_valid(_hero):
		return
	var away: float = signf(global_position.x - _hero.global_position.x)
	if away == 0.0:
		away = 1.0
	var off: float = REDRAW_OFFSETS[randi() % REDRAW_OFFSETS.size()]
	var dest := Vector2(_hero.global_position.x + absf(off) * away, global_position.y)
	# The mark itself crosses through `summon_circle`. The two puffs are the erase
	# and the arrival, and the boss's new POSITION crosses for free (replicated), so
	# a client without them sees the body jump with no punctuation either side.
	summon_circle(dest, Elements.Element.ARCANE, SpellTier.Tier.HEAVY, 56.0, REDRAW_TELL, true)
	CombatVfx.spawn_burst(get_parent(), global_position + Vector2(0.0, -26.0),
		Color(DRAFT.r, DRAFT.g, DRAFT.b, 0.9), Color(DRAFT.r, DRAFT.g, DRAFT.b, 0.0),
		16, 0.4, 50.0, 150.0, 0.8, 2.0, 0.0, 0.0, true)
	_bfx("burst", {"pos": global_position + Vector2(0.0, -26.0),
		"col": Color(DRAFT.r, DRAFT.g, DRAFT.b, 0.9), "n": 16, "life": 0.4,
		"v0": 50.0, "v1": 150.0, "s0": 0.8, "s1": 2.0})
	get_tree().create_timer(REDRAW_TELL).timeout.connect(func() -> void:
		if not is_instance_valid(self) or _bphase == BPhase.DEAD:
			return
		global_position = dest
		CombatVfx.spawn_burst(get_parent(), dest + Vector2(0.0, -26.0),
			Color(1.2, 1.3, 1.35, 0.95), Color(DRAFT.r, DRAFT.g, DRAFT.b, 0.0),
			20, 0.38, 70.0, 200.0, 0.7, 2.0, 0.0, 0.0, true)
		_bfx("burst", {"pos": dest + Vector2(0.0, -26.0),
			"col": Color(1.2, 1.3, 1.35, 0.95),
			"col2": Color(DRAFT.r, DRAFT.g, DRAFT.b, 0.0), "n": 20, "life": 0.38,
			"v0": 70.0, "v1": 200.0, "s0": 0.7, "s1": 2.0})
		Juice.shake_camera(4.0))
