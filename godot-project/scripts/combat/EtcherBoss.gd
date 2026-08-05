class_name EtcherBoss
extends TowerBoss
## THE ETCHER — a copper plate, bitten in acid.
##
## ── THE ARTIST ───────────────────────────────────────────────────────────────
## A printmaker. It does not draw the floor, it BITES it: wax ground, a needle, and
## an acid bath that eats everything the needle exposed. Verdigris green on beaten
## copper. It appears from floor 3 and never stops, because etching is a craft that
## only gets more exact.
##
## ── HOW IT FIGHTS DIFFERENTLY ────────────────────────────────────────────────
## THE ANSWER TO ITS BIGGEST TELL IS TO WALK TOWARD IT AND HIT IT.
##
## Every other boss on the roster answers a big cast with "survive it" — dodge the
## lane, find the cell, live through the page. `bath` is the one cast in the game
## that can be TAKEN OFF THE BOARD: it is a BATH_WINDUP-second rooted wind-up, and
## landing BREAK_FRACTION of the boss's own max HP inside that window aborts it
## outright, staggers the body for BREAK_STAGGER seconds, and hands you a free
## window it created by failing.
##
##   Scribble      — out-time it.
##   Cartographer  — out-position it.
##   Illuminator   — survive it, then punish.
##   Eraser        — give up ground and close in.
##   Etcher        — INTERRUPT it. The punish window is the one you took.
##
## ── WHY `mordant` EXISTS, AND WHY THE BOSS IS A QTE WITHOUT IT ───────────────
## A breakable cast with no price is not a decision, it is a button: see the tell,
## walk in, hit it, every time, forever. `mordant` opens an acid pool UNDER THE
## ETCHER ITSELF from P2, so the ground you have to stand on to break the bath is
## the ground that is hurting you. The break stops being free and starts being a
## trade — how much HP is this window worth — which is a question, and a button is
## not.
##
## P1 has no mordant on purpose: the first bath a player ever sees teaches that the
## break exists, and it teaches it cleanly. The price arrives once the lesson has.
##
## ── ⚠ TWO PLACES THIS MECHANIC CAN SILENTLY DO NOTHING ───────────────────────
## 1. THE BREAK IS SAMPLED IN `_physics_process`, NOT IN `take_damage`. That
##    function carries the co-op authority path (`Boss.take_damage` forwards a
##    puppet hit before any of its own logic) and overriding it is the one thing
##    `TowerBoss`'s own header says not to do. `hp` is already replicated by the
##    enemy synchronizer, so reading it costs nothing and adds nothing to the wire.
## 2. THE TIMER FIRES WHATEVER HAPPENS. Godot's timer does not know the cast was
##    broken, so `_bath_resolve` MUST early-return on `_bath_broken` — that is the
##    single line between "the break works" and "the break plays a sound and the
##    convergence lands anyway".

const RIG_H: float = 86.0
## Beaten copper, and the verdigris the acid leaves.
const COPPER: Color = Color(0.62, 0.42, 0.28)
const VERDIGRIS: Color = Color(0.45, 0.95, 0.62)

## BITE. The fast ray. It exists so that "stand off and wait for the next bath" is
## not a strategy — this boss is slow (speed_scale 0.55) and without a cheap ranged
## poke the correct play against it would be to do nothing at all.
const BITE_TELL: float = 0.45
const BITE_LEN: float = 900.0
const BITE_WIDTH: float = 30.0
const BITE_RADIUS: float = 62.0
const BITE_DAMAGE: int = 25

## FOUL (P1-2). A short pool on the hero's ground: range is not free either.
const FOUL_TELL: float = 0.5
const FOUL_RADIUS: float = 70.0
const FOUL_TICK: int = 8
const FOUL_LIFE: float = 4.0

## MORDANT (P2+). The pool it opens under ITSELF — the price of the break. Bigger
## and longer than `foul`, because it is not trying to catch you: it is sitting on
## the exact tile you have to come to.
const MORDANT_TELL: float = 0.45
const MORDANT_RADIUS: float = 92.0
const MORDANT_TICK: int = 9
const MORDANT_LIFE: float = 5.5

## THE BATH. The whole boss.
const BATH_WINDUP: float = 2.2
const BATH_RADIUS: float = 210.0
const BATH_DAMAGE: int = 46
## Damage that must land INSIDE the window to abort the cast, as a fraction of the
## Etcher's own max HP — so the break costs the same share of the fight at every
## depth, and a deep-floor HP curve can never quietly make it impossible.
const BREAK_FRACTION: float = 0.055
const BREAK_STAGGER: float = 1.6

## PLATE (P3). Two baths back to back, each shorter, each harder to break. It is the
## same question asked twice with less time and a bigger bill.
const PLATE_WINDUP: float = 1.5
const PLATE_GAP: float = 1.9
const PLATE_BREAK_MULT: float = 1.5

## Live bath state. `_bath_hp_mark` is the HP the cast opened at; the break test is
## a subtraction against it, so it needs no damage hook of its own.
var _bath_active: bool = false
var _bath_broken: bool = false
var _bath_hp_mark: int = 0
var _bath_need: int = 0
## Seconds of stagger still owed. Gates `_choose_attack` rather than touching
## `_busy`, whose timer is already scheduled by the attack that got broken.
var _stagger: float = 0.0
## Movement parked for the duration of a rooted cast, restored afterwards.
var _speed_mark: float = -1.0


func boss_title() -> String: return "THE ETCHER"
func boss_artist() -> String: return "needle and acid, on beaten copper"
## THE BILLING. An etcher does not add — it exposes, and then lets the acid decide
## how deep. The epithet is the threat and the tell in one line.
func boss_epithet() -> String: return "WHO LETS THE ACID DECIDE"
func bark_suffix() -> String: return "etcher"
## Its redraw is a bite: the page goes into the bath and comes back scored.
## Named `etch` rather than `bite` so the redraw hand and the P1 attack id are not
## the same word inside one file.
func redraw_style() -> StringName: return &"etch"
func boss_accent() -> Color: return VERDIGRIS
func boss_tint() -> Color: return COPPER
func boss_rig_height() -> float: return RIG_H
func boss_preset() -> String: return "warlock"


## The slowest cadence on the roster, and it stays slow. A boss whose signature is
## a breakable cast has to leave room to be walked up to — tighten this and the
## break stops being reachable, which would delete the only thing it is for.
func phase_cooldown(p: int) -> float:
	match p:
		1: return 2.6
		2: return 2.1
		3: return 1.6
	return 2.4


func _phase_attack_ids(phase: int) -> Array:
	match phase:
		1: return ["bite", "foul", "bath"]
		2: return ["bite", "foul", "mordant", "bath"]
		3: return ["plate", "bite", "mordant", "bath"]
	return []


func gesture_for(id: String) -> int:
	return CharacterRig.GestureKind.GATHER if id in ["bath", "plate"] else CharacterRig.GestureKind.RAISE


func _attack_duration(id: String) -> float:
	match id:
		"bite": return BITE_TELL + 0.5
		"foul": return FOUL_TELL + 0.45
		"mordant": return MORDANT_TELL + 0.45
		"bath": return BATH_WINDUP + 0.6
		"plate": return PLATE_WINDUP + PLATE_GAP + 0.6
	return 1.2


func _perform(id: String) -> void:
	match id:
		"bite": _atk_bite()
		"foul": _atk_foul()
		"mordant": _atk_mordant()
		"bath": _atk_bath(BATH_WINDUP, 1.0)
		"plate": _atk_plate()


# ---------------------------------------------------------------- the moveset
## BITE. A ruled line struck along the hero's bearing, landing as a single hard
## mark rather than a beam — the needle going in, not the acid.
func _atk_bite() -> void:
	if not is_instance_valid(_hero):
		return
	var aim: Vector2 = _hero.global_position - global_position
	aim = Vector2(aim.x, aim.y * 0.3)
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	var dir: Vector2 = aim.normalized()
	var at: Vector2 = _hero.global_position
	lane_tell(dir, BITE_LEN, BITE_WIDTH, BITE_TELL, func() -> void:
		var d: Node = spawn_spectacle("res://scripts/combat/DivineRay.gd",
			Elements.Element.EARTH, SpellTier.Tier.HEAVY)
		if d != null:
			d.call("strike", at, VERDIGRIS, BITE_RADIUS, BITE_DAMAGE, "earth")
		_bfx("ray", {"pos": at, "col": VERDIGRIS, "r": BITE_RADIUS, "fx": "earth",
			"el": Elements.Element.EARTH})
		Juice.shake_camera(4.5))


## FOUL. A short pool where you are standing.
func _atk_foul() -> void:
	if not is_instance_valid(_hero):
		return
	_pool_at(_hero.global_position, FOUL_RADIUS, FOUL_TICK, FOUL_LIFE, FOUL_TELL)


## MORDANT. A pool under the Etcher itself — see the class doc. This is the price
## of the break, and it is the reason the break is a decision.
func _atk_mordant() -> void:
	_pool_at(global_position, MORDANT_RADIUS, MORDANT_TICK, MORDANT_LIFE, MORDANT_TELL)


## THE BATH. A rooted wind-up that can be taken off the board.
##
## The circle states the radius while the band fills, so the wind-up is COUNTABLE
## off the rim rather than merely watched — which is what makes "do I have time to
## reach it and land enough" an answerable question instead of a gamble.
func _atk_bath(windup: float, break_mult: float) -> void:
	_bath_active = true
	_bath_broken = false
	_bath_hp_mark = int(hp)
	_bath_need = maxi(int(round(float(max_hp) * BREAK_FRACTION * break_mult)), 1)
	_root_body(true)
	summon_circle(global_position, Elements.Element.EARTH, SpellTier.Tier.ULT,
		BATH_RADIUS * 0.55, windup, true)
	get_tree().create_timer(windup).timeout.connect(_bath_resolve)


## PLATE (P3). Two shorter baths back to back at a raised break bar. The second one
## only opens if the boss is still standing and the first was not broken — a broken
## plate is a broken plate, and stacking a second cast on top of a stagger would
## take the reward straight back off the player who earned it.
func _atk_plate() -> void:
	_atk_bath(PLATE_WINDUP, PLATE_BREAK_MULT)
	get_tree().create_timer(PLATE_GAP).timeout.connect(func() -> void:
		if not is_instance_valid(self) or _bphase == BPhase.DEAD:
			return
		if _stagger > 0.0:
			return
		_atk_bath(PLATE_WINDUP, PLATE_BREAK_MULT))


## ⚠ THE EARLY RETURN IS THE MECHANIC. The timer fires whether or not the cast
## survived; without this line the break plays its whole reaction and the acid
## lands anyway, and nothing anywhere reports a fault.
func _bath_resolve() -> void:
	if not is_instance_valid(self) or _bphase == BPhase.DEAD:
		return
	_root_body(false)
	if _bath_broken:
		_bath_active = false
		return
	_bath_active = false
	var at: Vector2 = _hero.global_position if is_instance_valid(_hero) else global_position
	var s: Node = spawn_spectacle("res://scripts/combat/StarConvergence.gd",
		Elements.Element.EARTH, SpellTier.Tier.ULT)
	if s != null:
		s.call("converge", at, VERDIGRIS, BATH_RADIUS, BATH_DAMAGE, "earth")
	_bfx("convergence", {"pos": at, "col": VERDIGRIS, "r": BATH_RADIUS, "fx": "earth",
		"el": Elements.Element.EARTH})
	Juice.epic_moment({"strength": 1.0, "shake": 13.0, "sfx": "blast"})


## THE BREAK ITSELF. Landed enough inside the window: the cast dies, the body
## staggers, and the window it hands back is the reward.
func _break_bath() -> void:
	_bath_active = false
	_bath_broken = true
	_stagger = BREAK_STAGGER
	_root_body(false)
	if is_instance_valid(rig):
		rig.play(CharacterRig.State.HURT)
		rig.flash_color(Color(1.4, 1.6, 1.4), 0.2)
	Juice.on_hit({"shake": 10.0, "sfx": "blast", "hitstop": 0.09})
	# The break is the loudest thing that happens in this fight and it happens on
	# the HOST's arithmetic. A client that only saw the acid not land would read it
	# as the boss whiffing rather than as their partner earning a window.
	_bfx("beat", {"str": 0.9, "shake": 10.0, "sfx": "blast", "frame": true,
		"pos": global_position})


# ------------------------------------------------------------------- internals
## Park (or restore) the body's own movement. A wind-up that walks is not a
## wind-up you can commit to reaching. `_speed_mark` < 0 means "not parked", so a
## double park cannot lose the original value.
func _root_body(on: bool) -> void:
	if on:
		if _speed_mark < 0.0:
			_speed_mark = float(move_speed)
			move_speed = 0.0
		return
	if _speed_mark >= 0.0:
		move_speed = _speed_mark
		_speed_mark = -1.0


## ⚠ SAMPLED HERE RATHER THAN IN `take_damage` — see the class doc. `super` first,
## always: `Boss._physics_process` is where the co-op puppet guard lives.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_stagger = maxf(_stagger - delta, 0.0)
	if not _bath_active:
		return
	if _bath_hp_mark - int(hp) >= _bath_need:
		_break_bath()


## While staggered the body does nothing, and the cooldown is kept short so it
## resumes on the beat the stagger ends rather than a full cadence later. The base
## loop is untouched: this only declines to take its turn.
func _choose_attack() -> void:
	if _stagger > 0.0:
		_attack_cd = 0.15
		return
	super._choose_attack()


## Open an acid pool, telegraphed. One helper for both `foul` and `mordant` so the
## two differ only in where they land and what they cost — which is the whole
## design distinction and should be the whole code distinction too.
func _pool_at(at: Vector2, radius: float, tick: int, life: float, windup: float) -> void:
	zone_tell(at, radius, windup, func() -> void:
		var z: Node = spawn_spectacle("res://scripts/combat/ZoneSpell.gd",
			Elements.Element.EARTH, SpellTier.Tier.HEAVY)
		if z == null:
			return
		z.call("open", at, VERDIGRIS, radius, tick, "earth", life)
		_bfx("zone", {"pos": at, "col": VERDIGRIS, "r": radius, "fx": "earth",
			"el": Elements.Element.EARTH, "life": life}))
