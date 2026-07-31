class_name ScribbleBoss
extends TowerBoss
## THE SCRIBBLE — drawn by a child with a blunt pencil, on lined paper.
##
## ── THE ARTIST ───────────────────────────────────────────────────────────────
## The crudest thing in the tower. Graphite, pressed too hard, gone over four
## times. It is not a design so much as a tantrum that got a body: no symmetry, no
## weapon, no ceremony, one red crayon slash across the middle where the child
## scribbled it out and then changed their mind. It appears on floors 1-3 and never
## again, because escalation in this tower is ARTISTIC SKILL and the tower gets
## better at drawing.
##
## ── HOW IT FIGHTS DIFFERENTLY ────────────────────────────────────────────────
## THE FIGHT IS RHYTHM AND SPACING, AND IT HAS NO RANGED OPTIONS AT ALL.
##
## Every other boss in the roster makes you solve a picture — where the safe cell
## is, which radius to stand at, which half of the room the big cast will not
## reach. The Scribble makes you solve a METRONOME. It is on you constantly, it
## crosses the room in a straight scribbled streak, and the only answers are
## dodge timing and being somewhere the lane is not. Nothing to out-position; only
## something to out-time.
##
## Concretely, against the other three:
##   Scribble      — wants to be AT you.       Answer: dodge on the beat.
##   Cartographer  — wants you at a DISTANCE.  Answer: stand in the right cell.
##   Illuminator   — wants you COMMITTED.      Answer: survive, then punish.
##
## ── THE DASH IS A KNOCKBACK ON ITSELF, AND THAT IS DELIBERATE ────────────────
## `Boss._physics_process` computes `velocity.x = _knockback.x + approach` and
## bleeds `_knockback` toward zero at KNOCKBACK_DECAY. Firing a large self-impulse
## into that field therefore produces a hard launch that DECELERATES on its own,
## with no new state machine, no second `move_and_slide`, and — critically — no
## override of `_physics_process`, which is where the co-op puppet guard lives and
## is the one function on this class it would be dangerous to reimplement.
##
## The dash's hitbox is the BODY. There is no separate damage volume, which is the
## honest reading of "a scribble crossed the page through you": the lane telegraph
## is the promise, the body is the thing that keeps it.

const RIG_H: float = 60.0
const GRAPHITE: Color = Color(0.30, 0.29, 0.33)
const CRAYON: Color = Color(0.93, 0.26, 0.21)

## Lane tell length / width / wind-up for a single streak.
const DASH_LEN: float = 420.0
const DASH_WIDTH: float = 40.0
const DASH_WINDUP: float = 0.42
## Self-impulse fired down the lane. Bleeds off at Enemy.KNOCKBACK_DECAY (900 px/s),
## so this is a ~1.0 s deceleration from a very fast opening frame.
const DASH_IMPULSE: float = 1150.0
## Contact reach + re-hit gap WHILE DASHING. Shorter than the standard 0.8 s: a
## streak that passes through you should be able to clip you twice on a bad read,
## and a full second of immunity would make the signature attack whiff invisibly.
const DASH_TOUCH_GAP: float = 0.42
const DASH_TOUCH_REACH: float = 40.0
## How long the body counts as "streaking" after a dash fires.
const DASH_ACTIVE: float = 0.55

## The fan: three lanes at once, one of which you have to be in the gap of.
const FAN_ANGLES: Array[float] = [-0.34, 0.0, 0.34]
## Frenzy (P3): four streaks back to back, tells shortened to the edge of readable.
const FRENZY_COUNT: int = 4
const FRENZY_GAP: float = 0.46
const FRENZY_WINDUP: float = 0.26

var _dash_active: float = 0.0


func boss_title() -> String: return "THE SCRIBBLE"
func boss_artist() -> String: return "a child, blunt pencil, lined paper"
func boss_accent() -> Color: return CRAYON
func boss_tint() -> Color: return GRAPHITE
func boss_rig_height() -> float: return RIG_H
func boss_preset() -> String: return "brawler"


## FAST AND GETTING FASTER — the rhythm tightens instead of the numbers growing.
## By P3 it is attacking twice as often as it opened, and every attack is a lane.
func phase_cooldown(p: int) -> float:
	match p:
		1: return 1.7
		2: return 1.25
		3: return 0.85
	return 1.6


## Crude on purpose: the graphite barely changes, the crayon slash gets angrier.
## An artist this bad has no second act, so the escalation is in the RED.
func phase_palette(p: int) -> Dictionary:
	var k: float = float(clampi(p, 1, 3) - 1) / 2.0
	return {
		"tint": GRAPHITE.lerp(Color(0.42, 0.26, 0.27), k),
		"aura": CRAYON,
		"strength": lerpf(0.30, 0.72, k),
		"tier": 2 + clampi(p - 1, 0, 2),
		"mark": lerpf(0.35, 1.0, k),
	}


func _phase_attack_ids(phase: int) -> Array:
	match phase:
		1: return ["streak", "scratch"]
		2: return ["streak", "fan", "tantrum"]
		3: return ["frenzy", "fan", "scratch", "tantrum"]
	return []


func gesture_for(id: String) -> int:
	return CharacterRig.GestureKind.STOMP if id in ["scratch", "tantrum"] else CharacterRig.GestureKind.FLICK


func _attack_duration(id: String) -> float:
	match id:
		"streak": return DASH_WINDUP + 0.55
		"fan": return DASH_WINDUP + 0.7
		"scratch": return 0.85
		"tantrum": return 0.6
		"frenzy": return FRENZY_WINDUP + FRENZY_GAP * float(FRENZY_COUNT)
	return 0.8


func _perform(id: String) -> void:
	match id:
		"streak": _atk_streak()
		"fan": _atk_fan()
		"scratch": _atk_scratch()
		"tantrum": _atk_tantrum()
		"frenzy": _atk_frenzy()


# ---------------------------------------------------------------- the moveset
## ONE STREAK. Snapshot the aim, lay the lane, launch down it when the lane expires.
func _atk_streak(windup: float = DASH_WINDUP) -> void:
	if not is_instance_valid(_hero):
		return
	var dir: Vector2 = _aim_at_hero()
	lane_tell(dir, DASH_LEN, DASH_WIDTH, windup, func() -> void: _launch(dir))


## THE FAN. Three lanes at once, spread around the hero's bearing — the read stops
## being "step out of the line" and becomes "find the gap", which is the same skill
## one notch harder and is why this is a P2 attack rather than a P1 one.
##
## Only ONE of the three is actually taken (rolled up front, before any tell is
## drawn, so it can never be the one the player watched the body commit to). The
## other two are real, visible lanes with nothing coming down them — the crude
## artist's version of a feint, and cheap to read once you know the trick.
func _atk_fan() -> void:
	if not is_instance_valid(_hero):
		return
	var base: Vector2 = _aim_at_hero()
	var taken: int = randi() % FAN_ANGLES.size()
	for i: int in FAN_ANGLES.size():
		var dir: Vector2 = base.rotated(FAN_ANGLES[i])
		if i == taken:
			lane_tell(dir, DASH_LEN, DASH_WIDTH, DASH_WINDUP, func() -> void: _launch(dir))
		else:
			lane_tell(dir, DASH_LEN * 0.85, DASH_WIDTH * 0.8, DASH_WINDUP, func() -> void: pass)


## FRENZY (P3). Four streaks back to back with the tell cut to the bone. This is the
## boss scribbling itself out — the point at which the fight stops being about
## reading and becomes about keeping a rhythm going under pressure.
func _atk_frenzy() -> void:
	for i: int in FRENZY_COUNT:
		var delay: float = FRENZY_GAP * float(i)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(self) and _bphase != BPhase.DEAD:
				_atk_streak(FRENZY_WINDUP))


## SCRATCH. A scrawl torn across the floor away from the body — the ground answer,
## and the only attack it has that punishes standing still at range rather than
## standing still up close. Shadow root recoloured graphite: a reaching, grabbing
## ground eruption is exactly what a pencil gouging the page looks like.
func _atk_scratch() -> void:
	if not is_instance_valid(_hero):
		return
	var aim: Vector2 = _hero.global_position - global_position
	var n: Node = spawn_spectacle("res://scripts/combat/ShadowRoot.gd",
		Elements.Element.SHADOW, SpellTier.Tier.HEAVY)
	if n == null:
		return
	var scrawl_col: Color = GRAPHITE.lerp(CRAYON, 0.35)
	n.call("erupt", global_position, aim, scrawl_col, 74.0, 26, "shadow")
	# Co-op twin — same shape as the Guardian's `_atk_beam`/`_atk_rays`: build the
	# real thing, then hand the client a damage-free copy of it.
	_bfx("root", {"pos": global_position, "aim": aim, "col": scrawl_col, "r": 74.0,
		"fx": "shadow", "el": Elements.Element.SHADOW})
	Juice.shake_camera(4.0)


## TANTRUM. It thrashes where it stands and the page shoves back. Short, close,
## and the reason you cannot simply live inside its hitbox between streaks.
func _atk_tantrum() -> void:
	var n: Node = load("res://scenes/combat/EnergyNova.tscn").instantiate()
	n.set("target_group", "hero")
	n.set("_target_group", "hero")
	n.set("caster_node", self)
	n.set("element_id", Elements.Element.EARTH)
	get_parent().add_child(n)
	n.call("activate_at", global_position)
	_bfx("nova", {"pos": global_position})
	Juice.on_hit({"shake": 9.0, "sfx": "blast", "hitstop": 0.05})


# ------------------------------------------------------------------- internals
func _aim_at_hero() -> Vector2:
	var d: Vector2 = _hero.global_position - global_position
	# Flattened toward horizontal: this is a side-on game and a lane that dives at
	# 60 degrees is unreadable at 640x360 — and undodgeable, because the player
	# cannot move that way.
	d = Vector2(d.x, d.y * 0.3)
	return d.normalized() if d != Vector2.ZERO else Vector2.RIGHT


## The launch. See the class doc: a self-impulse into the base's knockback field,
## which decelerates on its own. `do_flop` false — a flop would ragdoll the body
## mid-dash and the streak has to stay a straight line to match its own lane.
func _launch(dir: Vector2) -> void:
	_knockback = Vector2(dir.x, 0.0).normalized() * DASH_IMPULSE
	_dash_active = DASH_ACTIVE
	_touch_cooldown = 0.0        # the streak gets its first contact for free
	if is_instance_valid(rig):
		rig.play(CharacterRig.State.DASH)
		rig.flash_color(Color(1.5, 1.2, 1.2), 0.12)
	Juice.shake_camera(5.5)
	# Co-op: the BODY crossing the room is free — position is replicated by the
	# enemy synchronizer — so the twin carries only the flash and the shake that
	# make it read as a launch rather than as a teleport.
	_bfx("dash", {"shake": 5.5})


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_dash_active = maxf(_dash_active - delta, 0.0)


## Wider reach and a shorter re-hit gap while the streak is live; the ordinary
## contact rules the rest of the time.
func _boss_touch() -> void:
	if _dash_active <= 0.0:
		super._boss_touch()
		return
	if not is_instance_valid(_hero) or _touch_cooldown > 0.0:
		return
	if global_position.distance_to(_hero.global_position) < DASH_TOUCH_REACH + RIG_H * body_scale * 0.35:
		if _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = DASH_TOUCH_GAP
			Juice.on_hit({"shake": 7.0, "sfx": "blast", "hitstop": 0.06})
