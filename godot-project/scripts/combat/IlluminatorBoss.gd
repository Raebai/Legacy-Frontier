class_name IlluminatorBoss
extends TowerBoss
## THE ILLUMINATOR — gold leaf on vellum, and it wants you dead.
##
## ── THE ARTIST ───────────────────────────────────────────────────────────────
## The deep-floor end of the ladder: confident ink laid down once and never
## corrected, gilded, hooded, holding a radiant staff. Where the Scribble is a
## tantrum and the Cartographer is a technician, this is somebody who has done this
## before and is taking their time about it.
##
## ── HOW IT FIGHTS DIFFERENTLY ────────────────────────────────────────────────
## THE FIGHT IS COMMITMENT AND PUNISH WINDOWS. It is the Cuphead rung of the ladder.
##
## Everything it does is enormous, slow, unmistakable, and leaves it rooted for a
## long time afterwards. The rhythm is not "dodge, dodge, dodge" (Scribble) or
## "read the shape, take your place" (Cartographer) — it is:
##
##     survive the big thing  ->  it is stuck  ->  get your damage in  ->  repeat
##
## and the fight is decided by whether you can hold your nerve during the cast and
## whether you actually take the window afterwards. That is why `_attack_duration`
## here is measured in whole seconds while the Scribble's is measured in fractions:
## `Boss._unbusy_after` keeps the boss rooted and choosing nothing for that entire
## span, and THE ROOTED TIME IS THE FIGHT. Shortening those numbers to make the
## boss "more active" would delete the design.
##
## ── EVERY BIG CAST OBEYS THE SPEC'S THREE TESTS ──────────────────────────────
## "Big spells are loud, committal, answerable and rare. Unmistakable wind-up.
##  Punishable cast. There is a play against it."
##
##   VERDICT      a column of light marching across the room, one strike at a time,
##                from one side to the other. Loud (it walks), answerable (run the
##                other way, or through the gap behind it), punishable (2.2 s).
##   GILDING      three beams sweeping through a rotating arc. Answerable by
##                running AROUND it — the only attack in the roster whose answer is
##                circular motion. Punishable (2.4 s).
##   PSALM        a wide bombardment on the hero. Answerable by leaving. (2.0 s)
##   ATTENDANTS   two gilded bodies out of a summoning circle. The pressure valve —
##                without it a player can simply stand at max range during the
##                recovery windows, and the fight has no cost to waiting.
##   THE FINAL PAGE (P3 only) the biggest thing in the game's boss kit: a full
##                convergence at the arena's heart with a 1.5 s wind-up and a 3.0 s
##                recovery. Rare by construction — it is one entry in one phase's
##                list — which is exactly the rarity the spec asks for.

const RIG_H: float = 102.0
const VELLUM: Color = Color(0.38, 0.17, 0.19)
const GOLD: Color = Color(1.0, 0.82, 0.36)

## VERDICT — a marching column of light.
const VERDICT_STEPS: int = 7
const VERDICT_SPACING: float = 118.0
const VERDICT_STAGGER: float = 0.13
const VERDICT_RADIUS: float = 72.0
const VERDICT_DAMAGE: int = 30

## GILDING — beams swept through an arc.
const GILD_BEAMS: int = 3
const GILD_STAGGER: float = 0.3
const GILD_ARC: float = 0.5          # radians swept across the set
const GILD_WINDUP: float = 0.75
const GILD_LEN: float = 1000.0
const GILD_WIDTH: float = 40.0
const GILD_DAMAGE: int = 32

## PSALM — the wide bombardment.
const PSALM_RADIUS: float = 190.0
const PSALM_DAMAGE: int = 22
const PSALM_COUNT: int = 14

## ATTENDANTS — the pressure valve. Capped hard: this is not an add fight.
const ATTENDANT_COUNT: int = 2
const ATTENDANT_HP: int = 26
const ATTENDANT_SPEED: float = 150.0
const ATTENDANT_TOUCH: int = 10

## THE FINAL PAGE — the rarest, loudest thing the roster has.
const PAGE_WINDUP: float = 1.5
const PAGE_RADIUS: float = 235.0
const PAGE_DAMAGE: int = 120


func boss_title() -> String: return "THE ILLUMINATOR"
func boss_artist() -> String: return "gold leaf on vellum"
## THE BILLING. The deep-floor end of the ladder: a hand that has done this to
## climbers before and is taking its time about this one.
func boss_epithet() -> String: return "GILDED, AND IT HAS DONE THIS BEFORE"
func bark_suffix() -> String: return "illuminator"
## It does not erase the page. It ILLUMINATES it — rules, leaf, and light thrown
## out of itself while you stand in the middle of the composition.
func redraw_style() -> StringName: return &"gild"
func boss_accent() -> Color: return GOLD
func boss_tint() -> Color: return VELLUM
func boss_rig_height() -> float: return RIG_H
func boss_preset() -> String: return "cleric"


## SHORT gaps between attacks, LONG attacks. That inversion is the whole rhythm:
## the boss is almost always mid-cast or mid-recovery, so the fight is a sequence of
## discrete committed events rather than a stream, and the player's damage all
## happens inside windows the boss handed them.
func phase_cooldown(p: int) -> float:
	match p:
		1: return 1.1
		2: return 0.9
		3: return 0.7
	return 1.0


func _phase_attack_ids(phase: int) -> Array:
	match phase:
		1: return ["verdict", "psalm"]
		2: return ["gilding", "verdict", "attendants", "psalm"]
		3: return ["final_page", "gilding", "verdict", "attendants"]
	return []


func gesture_for(id: String) -> int:
	return CharacterRig.GestureKind.GATHER if id in ["attendants", "final_page"] \
		else CharacterRig.GestureKind.RAISE


## THE PUNISH WINDOWS, in seconds. These are not pacing numbers to be trimmed — see
## the class doc. `Boss._unbusy_after` roots the boss for this long, and that rooted
## time is where the player's entire damage output comes from.
func _attack_duration(id: String) -> float:
	match id:
		"verdict": return 2.2
		"gilding": return 2.4
		"psalm": return 2.0
		"attendants": return 1.4
		"final_page": return PAGE_WINDUP + 3.0
	return 1.6


func _perform(id: String) -> void:
	match id:
		"verdict": _atk_verdict()
		"gilding": _atk_gilding()
		"psalm": _atk_psalm()
		"attendants": _atk_summon()
		"final_page": _atk_final_page()


# ---------------------------------------------------------------- the moveset
## VERDICT. A column of light that WALKS. Each strike carries DivineRay's own tell,
## and because they land in order and evenly spaced, the second one tells you where
## the third will be — so the attack teaches its own answer while it is happening.
## Starts on the far side of the hero and marches through them, so standing still is
## always wrong and the correct move is toward the strikes that have already fallen.
func _atk_verdict() -> void:
	if not is_instance_valid(_hero):
		return
	var toward: float = signf(_hero.global_position.x - global_position.x)
	if toward == 0.0:
		toward = 1.0
	var start: Vector2 = _hero.global_position - Vector2(toward * VERDICT_SPACING * 2.0, 0.0)
	for i: int in VERDICT_STEPS:
		var at: Vector2 = start + Vector2(toward * VERDICT_SPACING * float(i), 0.0)
		var delay: float = VERDICT_STAGGER * float(i)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(self) or _bphase == BPhase.DEAD:
				return
			var d: Node = spawn_spectacle("res://scripts/combat/DivineRay.gd",
				Elements.Element.HOLY, SpellTier.Tier.HEAVY)
			if d != null:
				d.call("strike", at, GOLD, VERDICT_RADIUS, VERDICT_DAMAGE, "holy")
			# The column TEACHES ITS OWN ANSWER while it walks — the second strike
			# tells you where the third will be. That lesson has to be legible on both
			# screens or the client is only ever guessing where it marches next.
			_bfx("ray", {"pos": at, "col": GOLD, "r": VERDICT_RADIUS, "fx": "holy",
				"el": Elements.Element.HOLY}))
	Juice.zoom_pull_camera(0.15, 0.9)


## GILDING. Three beams fired through a rotating arc — the answer is to run AROUND
## the boss rather than away from it, which is a shape nothing else in the roster
## asks for. Each beam gets its own lane tell at its own angle, so the sweep is
## visible as a sweep before the first shot leaves.
func _atk_gilding() -> void:
	if not is_instance_valid(_hero):
		return
	var base: Vector2 = (_hero.global_position - global_position)
	base = Vector2(base.x, base.y * 0.3).normalized()
	if base == Vector2.ZERO:
		base = Vector2.RIGHT
	# Rotation direction is rolled once so the whole sweep is coherent: a set that
	# alternated would be noise instead of an arc.
	var spin: float = 1.0 if (randi() % 2) == 0 else -1.0
	for i: int in GILD_BEAMS:
		var f: float = float(i) / float(maxi(GILD_BEAMS - 1, 1)) - 0.5
		var dir: Vector2 = base.rotated(f * GILD_ARC * spin)
		var delay: float = GILD_STAGGER * float(i)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(self) or _bphase == BPhase.DEAD:
				return
			lane_tell(dir, GILD_LEN, GILD_WIDTH, GILD_WINDUP, func() -> void: _gild_beam(dir)))


func _gild_beam(dir: Vector2) -> void:
	var origin: Vector2 = rig.get_weapon_tip() if is_instance_valid(rig) else global_position
	var beam: Node = spawn_spectacle("res://scripts/combat/BeamSpell.gd",
		Elements.Element.HOLY, SpellTier.Tier.HEAVY)
	if beam == null:
		return
	beam.call("fire", origin, dir, GOLD, GILD_LEN, GILD_WIDTH, GILD_DAMAGE, "holy")
	_bfx("beam", {"pos": origin, "dir": dir, "col": GOLD, "len": GILD_LEN,
		"w": GILD_WIDTH, "fx": "holy", "el": Elements.Element.HOLY})
	Juice.shake_camera(6.0)


## PSALM. A wide gilded bombardment on the hero's ground, opened by a full ULT
## summoning circle overhead so the size is stated before anything falls.
func _atk_psalm() -> void:
	if not is_instance_valid(_hero):
		return
	var at: Vector2 = _hero.global_position
	summon_circle(at + Vector2(0.0, -175.0), Elements.Element.HOLY, SpellTier.Tier.ULT, 96.0, 0.85)
	var m: Node = spawn_spectacle("res://scripts/combat/MeteorSigil.gd",
		Elements.Element.HOLY, SpellTier.Tier.ULT)
	if m != null:
		m.call("rain", at, GOLD, PSALM_RADIUS, PSALM_DAMAGE, PSALM_COUNT, "holy")
	_bfx("meteor", {"pos": at, "col": GOLD, "r": PSALM_RADIUS, "n": PSALM_COUNT,
		"fx": "holy", "el": Elements.Element.HOLY})
	Juice.zoom_pull_camera(0.18, 0.7)


## ATTENDANTS. Also the override of the base's phase-2 opener, so entering P2
## summons the Illuminator's own retinue rather than the Ashen Tower's ember adds.
##
## Capped twice on purpose: by ADD_CAP (this must not become an add fight) and by
## the floor's LIVE ENTITY BUDGET, which the boss does not own and has to ask about
## — a summoning boss that skipped `_spawn_headroom` could push the floor past its
## own ceiling, which is a bug this codebase has already had once.
func _atk_summon() -> void:
	_prune_summoned()
	var n: int = mini(ATTENDANT_COUNT, ADD_CAP - _summoned.size())
	n = mini(n, _spawn_headroom())
	if n <= 0:
		return
	summon_circle(global_position + Vector2(0.0, -30.0), Elements.Element.HOLY,
		SpellTier.Tier.HEAVY, 88.0, 0.7, true)
	for i: int in n:
		var pos: Vector2 = global_position + Vector2(randf_range(-96.0, 96.0), -18.0)
		var e: Node = _spawn_runtime_enemy({
			"boss": false, "arch": 0, "hp": ATTENDANT_HP,
			"spd": ATTENDANT_SPEED, "touch": ATTENDANT_TOUCH,
			"tint": Color(1.0, 0.86, 0.5, 1), "tele": false,
			"x": pos.x, "y": pos.y,
		})
		if e != null:
			_summoned.append(e)


## THE FINAL PAGE. The rarest and loudest thing the roster does: the artist finishes
## the illumination and closes the book on you.
##
## A 1.5 s wind-up under a full ULT sigil (outer summoning ring, second glyph band —
## the sigil vocabulary's own "this is the big one" read), then a convergence with
## the largest radius and damage in the boss kit, then THREE FULL SECONDS rooted.
## Every one of the spec's tests: unmistakable wind-up, punishable cast, and the
## play against it is simply "be anywhere but the middle of the room, then come and
## collect".
func _atk_final_page() -> void:
	var centre: Vector2 = global_position
	if is_instance_valid(_hero):
		centre = (global_position + _hero.global_position) * 0.5
	summon_circle(centre, Elements.Element.HOLY, SpellTier.Tier.ULT, 138.0, PAGE_WINDUP, true)
	zone_tell(centre, PAGE_RADIUS, PAGE_WINDUP, func() -> void:
		var s: Node = spawn_spectacle("res://scripts/combat/StarConvergence.gd",
			Elements.Element.HOLY, SpellTier.Tier.ULT)
		if s != null:
			s.call("converge", centre, GOLD, PAGE_RADIUS, PAGE_DAMAGE, "holy")
		# The one full-screen mark this boss spends per cast, and only on this cast.
		Juice.epic_moment({"strength": 1.35, "shake": 19.0, "sfx": "cannon"})
		Juice.tier_frame(SpellTier.Tier.ULT, centre, Elements.Element.HOLY)
		# THE RAREST THING IN THE BOSS KIT, and until now the half of the party that
		# was not hosting never saw it happen at all.
		_bfx("convergence", {"pos": centre, "col": GOLD, "r": PAGE_RADIUS,
			"fx": "holy", "el": Elements.Element.HOLY})
		_bfx("beat", {"pos": centre, "str": 1.35, "shake": 19.0, "sfx": "cannon"}))
	Juice.zoom_pull_camera(0.22, PAGE_WINDUP + 0.6, 0.2, 0.7)
